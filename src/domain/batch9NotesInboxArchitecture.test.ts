import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';

describe('DAYWELL NOTES & INBOX MODULE ARCHITECTURE AUDIT (PROMPT 2.5)', () => {
  const rootDir = process.cwd();
  const libDir = path.join(rootDir, 'flutter_app', 'lib');
  const domainNotesDir = path.join(libDir, 'domain', 'notes');
  const domainInboxDir = path.join(libDir, 'domain', 'inbox');
  const appNotesDir = path.join(libDir, 'application', 'notes');
  const appInboxDir = path.join(libDir, 'application', 'inbox');
  const repoDir = path.join(libDir, 'data', 'repositories');
  const appDatabasePath = path.join(libDir, 'data', 'database', 'app_database.dart');

  it('1. Domain Layer Isolation: domain/notes and domain/inbox have zero Drift, SQLite, or Flutter imports', () => {
    for (const dir of [domainNotesDir, domainInboxDir]) {
      assert.strictEqual(fs.existsSync(dir), true, `${dir} must exist`);
      const files = fs.readdirSync(dir).filter((f) => f.endsWith('.dart'));
      assert.strictEqual(files.length >= 2, true, `Expected models + contracts in ${dir}`);

      for (const f of files) {
        const content = fs.readFileSync(path.join(dir, f), 'utf8');
        assert.strictEqual(content.includes('package:drift'), false, `${f} must not import Drift`);
        assert.strictEqual(content.includes('package:sqflite'), false, `${f} must not import sqflite`);
        assert.strictEqual(
          content.includes('package:flutter/material.dart') ||
            content.includes('package:flutter/widgets.dart'),
          false,
          `${f} must not import Flutter UI widgets`
        );
      }
    }
  });

  it('2. Legacy Drift-Coupled Note Repository Removed & Pure Contract Implementations Present', () => {
    const legacyRepoPath = path.join(repoDir, 'note_repository.dart');
    assert.strictEqual(
      fs.existsSync(legacyRepoPath),
      false,
      'Legacy Drift-coupled note_repository.dart must be removed'
    );

    const notesRepo = fs.readFileSync(path.join(repoDir, 'notes_repository.dart'), 'utf8');
    const inboxRepo = fs.readFileSync(path.join(repoDir, 'inbox_repository.dart'), 'utf8');

    assert.strictEqual(notesRepo.includes('class DriftNotesRepository implements INotesRepository'), true);
    assert.strictEqual(notesRepo.includes('_mapRowToEntity('), true);
    assert.strictEqual(inboxRepo.includes('class DriftInboxRepository implements IInboxRepository'), true);
    assert.strictEqual(inboxRepo.includes('_mapRowToEntity('), true);
  });

  it('3. Application Layer Encapsulation & No Cross-Module Coupling or Drift Leaks', () => {
    const notesController = fs.readFileSync(path.join(appNotesDir, 'notes_controller.dart'), 'utf8');
    const notesState = fs.readFileSync(path.join(appNotesDir, 'notes_state.dart'), 'utf8');
    const inboxController = fs.readFileSync(path.join(appInboxDir, 'inbox_controller.dart'), 'utf8');
    const inboxState = fs.readFileSync(path.join(appInboxDir, 'inbox_state.dart'), 'utf8');

    // Controllers depend only on domain contracts, never Drift or AppStateManager
    for (const [name, content] of [
      ['notes_controller.dart', notesController],
      ['inbox_controller.dart', inboxController],
    ]) {
      assert.strictEqual(content.includes('package:drift'), false, `${name} must not import Drift`);
      assert.strictEqual(content.includes('app_database.dart'), false, `${name} must not import AppDatabase`);
      assert.strictEqual(content.includes('app_state.dart'), false, `${name} must not import AppStateManager`);
      assert.strictEqual(content.includes('package:flutter/material.dart'), false, `${name} must not import Material UI`);
    }

    // Notes and Inbox must not depend on Finance, Tasks, or each other
    assert.strictEqual(notesController.includes('inbox'), false);
    assert.strictEqual(notesController.includes('tasks'), false);
    assert.strictEqual(notesController.includes('finance'), false);

    assert.strictEqual(inboxController.includes('notes_controller'), false);
    assert.strictEqual(inboxController.includes('tasks_controller'), false);
    assert.strictEqual(inboxController.includes('finance_controller'), false);

    // NotesModuleState & InboxModuleState derived properties
    assert.strictEqual(notesState.includes('class NotesModuleState'), true);
    assert.strictEqual(notesState.includes('filteredNotes'), true);
    assert.strictEqual(notesState.includes('activeNotesCount'), true);

    assert.strictEqual(inboxState.includes('class InboxModuleState'), true);
    assert.strictEqual(inboxState.includes('unprocessedItems'), true);
    assert.strictEqual(inboxState.includes('unprocessedCount'), true);

    // InboxController subscription lifecycle & disposal
    assert.strictEqual(inboxController.includes('StreamSubscription'), true);
    assert.strictEqual(inboxController.includes('void dispose()'), true);
    assert.strictEqual(inboxController.includes('_unprocessedSubscription?.cancel()'), true);
  });

  it('4. Single Authoritative Owner: AppStateManager holds zero duplicate Notes or Inbox lists/sync bridges', () => {
    const appState = fs.readFileSync(path.join(libDir, 'ui', 'app_state.dart'), 'utf8');

    assert.strictEqual(appState.includes('List<NoteModel> notes = []'), false);
    assert.strictEqual(appState.includes('List<InboxItemModel> inboxItems = []'), false);
    assert.strictEqual(appState.includes('_syncNotesController'), false);
    assert.strictEqual(appState.includes('_syncInboxController'), false);
    assert.strictEqual(appState.includes('void addNote('), false);
    assert.strictEqual(appState.includes('void updateNote('), false);
    assert.strictEqual(appState.includes('void deleteNote('), false);
    assert.strictEqual(appState.includes('void addInboxItem('), false);

    // Compatibility getters delegate to module controllers
    assert.strictEqual(appState.includes('List<NoteModel> get notes => notesController.state.notes'), true);
    assert.strictEqual(appState.includes('List<InboxItemModel> get inboxItems => inboxController.state.items'), true);
    assert.strictEqual(appState.includes('onTriageCapture: _handleInboxCaptureTriage'), true);
  });

  it('5. Presentation Routing: NotesView and QuickCaptureDialog route exclusively through module controllers', () => {
    const notesView = fs.readFileSync(path.join(libDir, 'ui', 'screens', 'notes_view.dart'), 'utf8');
    const quickCapture = fs.readFileSync(path.join(libDir, 'ui', 'widgets', 'quick_capture_dialog.dart'), 'utf8');

    // NotesView no longer keeps note flags in widget state or calls AppStateManager mutators
    assert.strictEqual(notesView.includes('final Set<String> _pinnedIds'), false);
    assert.strictEqual(notesView.includes('final Set<String> _favoriteIds'), false);
    assert.strictEqual(notesView.includes('final Set<String> _archivedIds'), false);
    assert.strictEqual(notesView.includes('final Set<String> _trashedIds'), false);
    assert.strictEqual(notesView.includes('final Map<String, List<String>> _noteTags'), false);
    assert.strictEqual(notesView.includes('widget.state.addNote'), false);
    assert.strictEqual(notesView.includes('widget.state.updateNote'), false);
    assert.strictEqual(notesView.includes('widget.state.deleteNote'), false);
    assert.strictEqual(notesView.includes('widget.effectiveController'), true);

    // QuickCaptureDialog routes through InboxController
    assert.strictEqual(quickCapture.includes('widget.state.addInboxItem'), false);
    assert.strictEqual(quickCapture.includes('InboxController get effectiveController'), true);
    assert.strictEqual(quickCapture.includes('effectiveController.captureQuickThought'), true);
  });

  it('6. Schema Version 5 Non-Destructive Migration Persists Note Metadata', () => {
    const dbContent = fs.readFileSync(appDatabasePath, 'utf8');
    const versionMatch = dbContent.match(/int get schemaVersion => (\d+);/);
    assert.ok(versionMatch && Number(versionMatch[1]) >= 5);
    assert.strictEqual(dbContent.includes('if (from < 4)'), true);
    assert.strictEqual(dbContent.includes('if (from < 5)'), true);
    assert.strictEqual(dbContent.includes('await m.addColumn(notes, notes.tagsJson);'), true);
    assert.strictEqual(dbContent.includes('await m.addColumn(notes, notes.isPinned);'), true);
    assert.strictEqual(dbContent.includes('await m.addColumn(notes, notes.isFavorite);'), true);
    assert.strictEqual(dbContent.includes('await m.addColumn(notes, notes.isArchived);'), true);
    assert.strictEqual(dbContent.includes('await m.addColumn(notes, notes.isTrashed);'), true);
  });
});
