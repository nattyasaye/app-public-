import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { CANONICAL_SEED_DATABASE } from './sharedFoundation';
import { SharedStateBridge } from '../services/sharedStateBridge';

function collectDartFiles(dir: string): string[] {
  if (!fs.existsSync(dir)) return [];
  const results: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...collectDartFiles(full));
    } else if (entry.name.endsWith('.dart')) {
      results.push(full);
    }
  }
  return results;
}

describe('STAGE 2 FINAL INTEGRATION & ARCHITECTURAL CONSOLIDATION AUDIT', () => {
  const rootDir = process.cwd();
  const libDir = path.join(rootDir, 'flutter_app', 'lib');

  it('1. Schema v5 Non-Destructive Migration: schemaVersion => 5, CalendarEvents, and full v1->v5 path preserved', () => {
    const tablesContent = fs.readFileSync(path.join(libDir, 'data', 'database', 'tables.dart'), 'utf8');
    const dbContent = fs.readFileSync(path.join(libDir, 'data', 'database', 'app_database.dart'), 'utf8');

    const versionMatch = dbContent.match(/int get schemaVersion => (\d+);/);
    assert.ok(versionMatch && Number(versionMatch[1]) >= 5, 'schemaVersion must be >= 5');
    assert.strictEqual(dbContent.includes('CalendarEvents,'), true);
    assert.strictEqual(tablesContent.includes('class CalendarEvents extends Table'), true);
    assert.strictEqual(tablesContent.includes('TextColumn get endDateIso => text().nullable()();'), true);

    // Non-destructive historical, v4, and v5 upgrades
    assert.strictEqual(dbContent.includes('if (from < 2)'), true);
    assert.strictEqual(dbContent.includes('if (from < 3)'), true);
    assert.strictEqual(dbContent.includes('if (from < 4)'), true);
    assert.strictEqual(dbContent.includes('if (from < 5)'), true);

    // Schema v4 columns for Tasks, Notes, and Finance
    assert.strictEqual(dbContent.includes('await m.addColumn(tasks, tasks.subtasksJson);'), true);
    assert.strictEqual(dbContent.includes('await m.addColumn(tasks, tasks.labelsJson);'), true);
    assert.strictEqual(dbContent.includes('await m.addColumn(tasks, tasks.isPinned);'), true);
    assert.strictEqual(dbContent.includes('await m.addColumn(tasks, tasks.isMyDay);'), true);
    assert.strictEqual(dbContent.includes('await m.addColumn(tasks, tasks.recurrenceRule);'), true);

    assert.strictEqual(dbContent.includes('await m.addColumn(notes, notes.tagsJson);'), true);
    assert.strictEqual(dbContent.includes('await m.addColumn(notes, notes.isPinned);'), true);
    assert.strictEqual(dbContent.includes('await m.addColumn(notes, notes.isFavorite);'), true);
    assert.strictEqual(dbContent.includes('await m.addColumn(notes, notes.isArchived);'), true);
    assert.strictEqual(dbContent.includes('await m.addColumn(notes, notes.isTrashed);'), true);

    const normalizedDbContent =
      dbContent.replace(/\(\s+/g, '(').replace(/\s+/g, ' ');
    assert.strictEqual(normalizedDbContent.includes('await m.addColumn(financialCategories, financialCategories.isArchived);'), true);
    assert.strictEqual(normalizedDbContent.includes('await m.addColumn(financialTransactions, financialTransactions.accountId);'), true);
    assert.strictEqual(normalizedDbContent.includes('await m.createTable(calendarEvents);'), true);
    assert.strictEqual(normalizedDbContent.includes('TableMigration('), true);

    // Must never wipe database on upgrade
    assert.strictEqual(dbContent.includes('deleteEverything'), false);
    assert.strictEqual(dbContent.includes('DROP TABLE'), false);
  });

  it('2. Deterministic First-Run-Only Seeding: Guarded by seedSentinelKey and insertOrIgnore', () => {
    const dbContent = fs.readFileSync(path.join(libDir, 'data', 'database', 'app_database.dart'), 'utf8');

    assert.strictEqual(dbContent.includes("static const String seedSentinelKey = 'initial_seed_completed';"), true);
    assert.strictEqual(dbContent.includes('Future<void> ensureInitialized() async'), true);
    assert.strictEqual(dbContent.includes('Future<void> seedDefaultsIfFirstRun() async'), true);
    assert.strictEqual(dbContent.includes('mode: InsertMode.insertOrIgnore'), true);
    assert.strictEqual(dbContent.includes('if (existingCategories.isEmpty)'), true);
  });

  it('3. Legacy Dual Repositories Removed: task_repository.dart, project_repository.dart, and note_repository.dart deleted', () => {
    const repoDir = path.join(libDir, 'data', 'repositories');
    assert.strictEqual(fs.existsSync(path.join(repoDir, 'task_repository.dart')), false);
    assert.strictEqual(fs.existsSync(path.join(repoDir, 'project_repository.dart')), false);
    assert.strictEqual(fs.existsSync(path.join(repoDir, 'note_repository.dart')), false);

    assert.strictEqual(fs.existsSync(path.join(repoDir, 'tasks_repository.dart')), true);
    assert.strictEqual(fs.existsSync(path.join(repoDir, 'notes_repository.dart')), true);
    assert.strictEqual(fs.existsSync(path.join(repoDir, 'inbox_repository.dart')), true);
    assert.strictEqual(fs.existsSync(path.join(repoDir, 'finance_repository.dart')), true);
    assert.strictEqual(fs.existsSync(path.join(repoDir, 'calendar_repository.dart')), true);
  });

  it('4. Strict Dependency Boundaries: Domain & Application layers contain zero Drift, SQLite, UI, or AppStateManager imports', () => {
    const domainFiles = collectDartFiles(path.join(libDir, 'domain'));
    const appFiles = collectDartFiles(path.join(libDir, 'application'));
    assert.ok(domainFiles.length >= 8);
    assert.ok(appFiles.length >= 8);

    for (const file of [...domainFiles, ...appFiles]) {
      const content = fs.readFileSync(file, 'utf8');
      assert.strictEqual(content.includes('package:drift'), false, `${file} must not import Drift`);
      assert.strictEqual(content.includes('package:sqflite'), false, `${file} must not import sqflite`);
      assert.strictEqual(content.includes('package:flutter/material.dart'), false, `${file} must not import Material UI`);
      assert.strictEqual(content.includes('app_database.dart'), false, `${file} must not import AppDatabase`);
      assert.strictEqual(content.includes('app_state.dart'), false, `${file} must not import AppStateManager`);
    }
  });

  it('5. Single Authoritative State Owner: AppStateManager is a thin composition root with async initialize() & dispose()', () => {
    const appState = fs.readFileSync(path.join(libDir, 'ui', 'app_state.dart'), 'utf8');

    // Sync bridges & duplicate seeding eliminated
    assert.strictEqual(appState.includes('_syncFinanceController'), false);
    assert.strictEqual(appState.includes('_syncTasksController'), false);
    assert.strictEqual(appState.includes('syncFromExternalState'), false);
    assert.strictEqual(appState.includes('_seedInitialData'), false);

    // No mutable domain lists held in AppStateManager
    assert.strictEqual(appState.includes('List<AccountModel> accounts ='), false);
    assert.strictEqual(appState.includes('List<TaskModel> tasks ='), false);
    assert.strictEqual(appState.includes('List<NoteModel> notes ='), false);
    assert.strictEqual(appState.includes('List<InboxItemModel> inboxItems ='), false);
    assert.strictEqual(appState.includes('List<TransactionModel> transactions ='), false);

    // Async initialization, lifecycle guards & deterministic disposal
    assert.strictEqual(appState.includes('Future<void> initialize()'), true);
    assert.strictEqual(appState.includes('Future<void> disposeAsync()'), true);
    assert.strictEqual(appState.includes('bool _isDisposed = false;'), true);
    assert.strictEqual(appState.includes('await _db.ensureInitialized();'), true);
    assert.strictEqual(appState.includes('await _rehydrateAllControllers();'), true);
    assert.strictEqual(appState.includes('calendarController.loadAll()'), true);
    assert.strictEqual(appState.includes('inboxController.startWatchingUnprocessed()'), true);
    assert.strictEqual(
      appState.includes('await _db.close();') ||
        (appState.includes('await _closeDbSafely();') &&
          appState.includes('await dbToClose.close()')),
      true
    );
  });

  it('6. Startup Readiness Gate & Error Recovery: MainDaywellScreen awaits AppStateManager.initialize()', () => {
    const mainDart = fs.readFileSync(path.join(libDir, 'main.dart'), 'utf8');

    assert.strictEqual(mainDart.includes('_state.initialize()'), true);
    assert.strictEqual(mainDart.includes('if (!_state.isInitialized)'), true);
    assert.strictEqual(mainDart.includes('_state.initializationError != null'), true);
    assert.strictEqual(
      mainDart.includes('onPressed: _state.initialize') ||
        mainDart.includes('_state.retryInitialize'),
      true
    );
    assert.strictEqual(mainDart.includes('controller: _state.tasksController'), true);
    assert.strictEqual(mainDart.includes('controller: _state.notesController'), true);
    assert.strictEqual(mainDart.includes('controller: _state.financeController'), true);
    assert.strictEqual(mainDart.includes('controller: _state.inboxController'), true);
  });

  it('6b. Native SQLite Verification Tests & CI Quality Gates Configured', () => {
    const migrationTest = fs.readFileSync(
      path.join(rootDir, 'flutter_app', 'test', 'database_migration_test.dart'),
      'utf8'
    );
    const stage2Test = fs.readFileSync(
      path.join(rootDir, 'flutter_app', 'test', 'stage2_consolidation_test.dart'),
      'utf8'
    );
    const workflow = fs.readFileSync(
      path.join(rootDir, '.github', 'workflows', 'android.yml'),
      'utf8'
    );
    const searchRepo = fs.readFileSync(
      path.join(libDir, 'data', 'repositories', 'search_repository.dart'),
      'utf8'
    );

    assert.strictEqual(migrationTest.includes('NativeDatabase('), true);
    assert.strictEqual(migrationTest.includes('PRAGMA user_version = 3;'), true);
    assert.strictEqual(migrationTest.includes('PRAGMA foreign_key_check'), true);
    assert.strictEqual(stage2Test.includes('NativeDatabase('), true);
    assert.strictEqual(stage2Test.includes('state1.disposeAsync()'), true);
    assert.strictEqual(stage2Test.includes('LazyDatabase('), true);
    assert.strictEqual(searchRepo.includes("import 'package:drift/drift.dart';"), true);
    assert.strictEqual(workflow.includes('dart format --output=none --set-exit-if-changed lib test'), true);
    assert.strictEqual(workflow.includes('flutter analyze'), true);
    assert.strictEqual(workflow.includes('flutter test'), true);

    const financeView = fs.readFileSync(
      path.join(libDir, 'ui', 'screens', 'finance_view.dart'),
      'utf8'
    );
    const financeWizard = fs.readFileSync(
      path.join(libDir, 'ui', 'screens', 'finance', 'finance_setup_wizard.dart'),
      'utf8'
    );
    assert.strictEqual(financeView.includes('FinanceSetupWizard(controller: ctrl)'), true);
    assert.strictEqual(financeWizard.includes('widget.controller.completeSetup('), true);

    const testFiles = collectDartFiles(path.join(rootDir, 'flutter_app', 'test'));
    assert.ok(testFiles.length >= 12);
    for (const tf of testFiles) {
      const tc = fs.readFileSync(tf, 'utf8');
      assert.strictEqual(tc.includes('../lib/'), false, `${tf} must use package: imports`);
    }
  });

  it('7. Presentation Routing: UI screens consume module controllers without shadow persistence state', () => {
    const tasksView = fs.readFileSync(path.join(libDir, 'ui', 'screens', 'tasks_view.dart'), 'utf8');
    const financeView = fs.readFileSync(path.join(libDir, 'ui', 'screens', 'finance_view.dart'), 'utf8');
    const dashboardView = fs.readFileSync(path.join(libDir, 'ui', 'screens', 'dashboard_view.dart'), 'utf8');
    const moreView = fs.readFileSync(path.join(libDir, 'ui', 'screens', 'more_view.dart'), 'utf8');

    // TasksView zero widget-local shadow persistence
    assert.strictEqual(tasksView.includes('_myDayIds'), false);
    assert.strictEqual(tasksView.includes('_pinnedIds'), false);
    assert.strictEqual(tasksView.includes('_taskLabels'), false);
    assert.strictEqual(tasksView.includes('_subtasks'), false);
    assert.strictEqual(tasksView.includes('widget.state.'), false);

    // FinanceView routes all mutations and reads via FinanceController
    assert.strictEqual(financeView.includes('widget.state.'), false);
    assert.strictEqual(financeView.includes('widget.effectiveController'), true);

    // Dashboard & More read from controllers cleanly
    assert.strictEqual(dashboardView.includes('state.financeController.state'), true);
    assert.strictEqual(dashboardView.includes('state.tasksController.state'), true);
    assert.strictEqual(dashboardView.includes('state.notesController.state'), true);
    assert.strictEqual(dashboardView.includes('state.tasksController.toggleTaskStatus'), true);
    assert.strictEqual(moreView.includes('state.financeController.state.savingsGoals.length'), true);
  });

  it('8. SQLite-Backed Backup, Restore, Bridge & Web SharedStateBridge Parity (Schema v5)', () => {
    const coordinator = fs.readFileSync(
      path.join(libDir, 'data', 'database', 'database_persistence_coordinator.dart'),
      'utf8'
    );
    const bridgeDart = fs.readFileSync(
      path.join(libDir, 'core', 'shared_foundation_bridge.dart'),
      'utf8'
    );
    const sharedFoundationDart = fs.readFileSync(
      path.join(libDir, 'core', 'shared_foundation.dart'),
      'utf8'
    );
    const sharedFoundationCoreDart = fs.readFileSync(
      path.join(libDir, 'core', 'shared_foundation_core.dart'),
      'utf8'
    );

    assert.strictEqual(coordinator.includes("'calendarEvents': calendarEvents"), true);
    assert.strictEqual(coordinator.includes('Future<void> importSnapshot('), true);
    assert.strictEqual(coordinator.includes('Future<int> purgeKnownSeedData()'), true);
    assert.strictEqual(bridgeDart.includes('static const int schemaVersion = 5;'), true);
    assert.strictEqual(bridgeDart.includes('static Future<bool> importFromCanonicalJson('), true);
    assert.strictEqual(bridgeDart.includes('await state.importCanonicalSnapshot('), true);
    assert.strictEqual(sharedFoundationCoreDart.includes('static const int schemaVersion = 5;'), true);
    assert.strictEqual(sharedFoundationDart.includes("export 'shared_foundation_core.dart';"), true);

    // Web TS parity check with CalendarEvents
    assert.strictEqual(CANONICAL_SEED_DATABASE.schemaVersion, 5);
    assert.strictEqual(Array.isArray(CANONICAL_SEED_DATABASE.calendarEvents), true);

    const live = SharedStateBridge.assembleLiveDatabaseState();
    assert.strictEqual(live.schemaVersion, 5);
    assert.strictEqual(Array.isArray(live.calendarEvents), true);

    const roundTrip = SharedStateBridge.importFromAndroidJson(
      SharedStateBridge.exportToAndroidJson({
        ...live,
        calendarEvents: [
          {
            id: 'evt-test-1',
            title: 'Sprint Review',
            date: '2026-11-12',
            endDate: '2026-11-14',
            isAllDay: false,
            category: 'work',
            colorHex: '#1B4D3E',
            hasReminder: true,
            createdAt: '2026-11-12T08:00:00.000Z',
            updatedAt: '2026-11-12T08:00:00.000Z',
          },
        ],
      })
    );
    assert.strictEqual(roundTrip.success, true);
    assert.strictEqual(roundTrip.state?.schemaVersion, 5);
    assert.strictEqual(roundTrip.state?.calendarEvents?.length, 1);
    assert.strictEqual(roundTrip.state?.calendarEvents?.[0].title, 'Sprint Review');
    assert.strictEqual(roundTrip.state?.calendarEvents?.[0].endDate, '2026-11-14');
  });
});
