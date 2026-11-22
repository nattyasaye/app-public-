import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const REPO_ROOT = process.cwd();

function read(relPath: string): string {
  return fs.readFileSync(path.join(REPO_ROOT, relPath), 'utf8');
}

describe('Stage 8 — Flutter Task–Notes Integration & Schema v11 Contract', () => {
  it('1. Shared Foundation schema_contracts.json and generated artifacts define v11 Note linkedModule/linkedId', () => {
    const contracts = JSON.parse(read('shared_foundation/schema_contracts.json'));
    assert.strictEqual(contracts.schemaVersion, 11);

    const noteFields = contracts.entities.Note.fields;
    assert.deepStrictEqual(noteFields.linkedModule, {
      type: 'string',
      enum: ['tasks', 'finance', 'calendar'],
      required: false,
    });
    assert.deepStrictEqual(noteFields.linkedId, {
      type: 'string',
      required: false,
    });

    const tsFoundation = read('src/domain/sharedFoundation.ts');
    assert.match(tsFoundation, /linkedModule\?: 'tasks' \| 'finance' \| 'calendar';/);
    assert.match(tsFoundation, /linkedId\?: string;/);

    const dartFoundationCore = read('flutter_app/lib/core/shared_foundation_core.dart');
    assert.match(dartFoundationCore, /static const int schemaVersion = 5;/);
    assert.match(dartFoundationCore, /class KnownSeedIds/);
  });

  it('2. Flutter Drift schema, AppDatabase v10->v11 migration, and compatibility baseline enforce safe additive upgrade', () => {
    const tables = read('flutter_app/lib/data/database/tables.dart');
    assert.match(tables, /class Notes extends Table[\s\S]*TextColumn get linkedModule => text\(\)\.nullable\(\)\(\);/);
    assert.match(tables, /class Notes extends Table[\s\S]*TextColumn get linkedId => text\(\)\.nullable\(\)\(\);/);

    const appDb = read('flutter_app/lib/data/database/app_database.dart');
    assert.match(appDb, /int get schemaVersion => 11;/);
    assert.match(appDb, /if \(from < 11\)/);
    assert.match(appDb, /'linked_module'/);
    assert.match(appDb, /'linked_id'/);
    assert.match(appDb, /_createV11NotePerformanceIndices\(\)/);
    assert.match(appDb, /idx_notes_linked[\s\S]*ON notes\(linked_module, linked_id\)/);
    assert.match(appDb, /PRAGMA foreign_key_check/);

    const migBaseline = JSON.parse(read('scripts/migration_compatibility_baseline.json'));
    assert.strictEqual(migBaseline.minimumSchemaVersion, 11);
    const step11 = migBaseline.releasedUpgradeSteps.find((s: { version: number }) => s.version === 11);
    assert.ok(step11, 'Baseline must track released v11 upgrade step');
    assert.deepStrictEqual(step11.requiredMarkers, ['notes.linkedModule', 'notes.linkedId']);
  });

  it('3. Flutter domain helpers remain pure, NotesController stays generic, and task deletion safely unlinks notes', () => {
    const helper = read('flutter_app/lib/domain/notes/task_notes_helpers.dart');
    assert.doesNotMatch(helper, /package:flutter\//);
    assert.doesNotMatch(helper, /package:drift\//);
    assert.match(helper, /class TaskNotesHelper/);
    assert.match(helper, /getNotesForTask/);
    assert.match(helper, /getAvailableNotesForTaskLink/);
    assert.match(helper, /buildDefaultTaskNoteTitle/);
    assert.match(helper, /findLinkedTask/);

    const noteModels = read('flutter_app/lib/domain/notes/note_models.dart');
    assert.match(noteModels, /static const String taskLinkModule = 'tasks';/);
    assert.match(noteModels, /normalizeLinkPair/);
    assert.match(noteModels, /clampTitle/);
    assert.match(noteModels, /taskId/);

    const notesController = read('flutter_app/lib/application/notes/notes_controller.dart');
    assert.strictEqual(
      notesController.includes("'tasks'"),
      false,
      'NotesController must remain generic without hardcoded "tasks" module literal'
    );
    assert.match(notesController, /Future<NoteEntity\?> linkNoteToEntity/);
    assert.match(notesController, /Future<NoteEntity\?> unlinkNote/);
    assert.match(notesController, /Future<void> clearLinksForTarget/);

    const tasksRepo = read('flutter_app/lib/data/repositories/tasks_repository.dart');
    assert.match(tasksRepo, /deleteTask[\s\S]*tbl\.linkedModule\.equals\('tasks'\)[\s\S]*tbl\.linkedId\.equals\(id\)/);

    const tasksController = read('flutter_app/lib/application/tasks/tasks_controller.dart');
    assert.match(tasksController, /onTaskDeleted/);

    const appState = read('flutter_app/lib/ui/app_state.dart');
    assert.match(appState, /onTaskDeleted:\s*_handleTaskDeleted/);
    assert.match(appState, /clearLinksForTarget/);
  });

  it('4. Version policy, Backup coordinator, Encryption service, and Web bridge synchronize schema v11 & compat bounds', () => {
    const policy = read('flutter_app/lib/core/snapshot_version_policy.dart');
    assert.match(policy, /supportedDatabaseSchemaVersion = 11/);
    assert.match(policy, /maxSupportedDatabaseSchemaVersion = 11/);
    assert.match(
      policy,
      /rawDbVersion != 9 &&[\s\S]*rawDbVersion != 10 &&[\s\S]*rawDbVersion != supportedDatabaseSchemaVersion/
    );

    const webPolicy = read('src/domain/snapshotVersionPolicy.ts');
    assert.match(webPolicy, /supportedDatabaseSchemaVersion:\s*11/);
    assert.match(webPolicy, /maxSupportedDatabaseSchemaVersion:\s*11/);
    assert.match(
      webPolicy,
      /dsv !== 9 &&[\s\S]*dsv !== 10 &&[\s\S]*dsv !== SNAPSHOT_VERSION_BOUNDS\.supportedDatabaseSchemaVersion/
    );

    const coordinator = read('flutter_app/lib/data/database/database_persistence_coordinator.dart');
    assert.match(coordinator, /'linkedModule':\s*n\.linkedModule/);
    assert.match(coordinator, /'linkedId':\s*n\.linkedId/);
    assert.match(coordinator, /ORPHANED_NOTE_TASK_CLEARED/);

    const encService = read('flutter_app/lib/services/backup/encryption_backup_service.dart');
    assert.match(encService, /maxSupportedDatabaseSchemaVersion = 11/);
  });

  it('5. Flutter TasksView, NotesView, and MainDaywellScreen implement bidirectional UI without raw colors or duplicate note editor', () => {
    const tasksView = read('flutter_app/lib/ui/screens/tasks_view.dart');
    assert.match(tasksView, /notesController/);
    assert.match(tasksView, /onOpenNote/);
    assert.match(tasksView, /_TaskDetailsLinkedNotesPanel/);
    assert.match(tasksView, /_LinkExistingNoteSheet/);
    assert.match(tasksView, /Link Existing/);
    assert.match(tasksView, /New Note/);
    assert.doesNotMatch(tasksView, /Color\(0x/);

    const notesView = read('flutter_app/lib/ui/screens/notes_view.dart');
    assert.match(notesView, /tasksController/);
    assert.match(notesView, /requestedNoteFocus/);
    assert.match(notesView, /onOpenTask/);
    assert.match(notesView, /_NoteTaskPickerSheet/);
    assert.match(notesView, /Linked task unavailable/);
    assert.doesNotMatch(notesView, /Color\(0x/);

    const mainView = read('flutter_app/lib/main.dart');
    assert.match(mainView, /_requestedNoteFocus/);
    assert.match(mainView, /onOpenNote:\s*\(String noteId\)[\s\S]*_requestedNoteFocus[\s\S]*DaywellTabId\.notes/);
    assert.match(mainView, /onOpenTask:\s*\(String taskId\)[\s\S]*_requestedTaskFocus[\s\S]*DaywellTabId\.tasks/);
  });
});
