import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/application/tasks/tasks_controller.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/notes_repository.dart';
import 'package:personal_management_app/data/repositories/search_repository.dart';
import 'package:personal_management_app/data/repositories/tasks_repository.dart';
import 'package:personal_management_app/domain/notes/note_helpers.dart';
import 'package:personal_management_app/ui/screens/notes_view.dart';

import 'support/sqlite_test_helper.dart';

class _ControllableNotesRepository implements INotesRepository {
  final Map<String, NoteEntity> store = <String, NoteEntity>{};
  Completer<void>? nextCreateGate;
  Completer<void>? nextUpdateGate;
  bool shouldThrowOnCreate = false;
  bool shouldThrowOnUpdate = false;
  int createCalls = 0;
  int updateCalls = 0;

  void seed(NoteEntity note) {
    store[note.id] = note;
  }

  @override
  Future<NoteEntity> createNote(NoteEntity note) async {
    createCalls++;
    final gate = nextCreateGate;
    if (gate != null) {
      nextCreateGate = null;
      await gate.future;
    }
    if (shouldThrowOnCreate) {
      throw StateError('Simulated create failure');
    }
    final persisted = note.copyWith(updatedAt: note.updatedAt);
    store[persisted.id] = persisted;
    return persisted;
  }

  @override
  Future<NoteEntity> updateNote(NoteEntity note) async {
    updateCalls++;
    final gate = nextUpdateGate;
    if (gate != null) {
      nextUpdateGate = null;
      await gate.future;
    }
    if (shouldThrowOnUpdate) {
      throw StateError('Simulated update failure');
    }
    if (!store.containsKey(note.id)) {
      throw StateError('Missing note ${note.id}');
    }
    store[note.id] = note;
    return note;
  }

  @override
  Future<void> deleteNote(String id) async {
    store.remove(id);
  }

  @override
  Future<NoteEntity?> getNoteById(String id) async => store[id];

  @override
  Future<List<NoteEntity>> getNotes({
    String? category,
    String? projectId,
    String? goalId,
    String? linkedModule,
    String? linkedId,
    bool includeArchived = false,
    bool includeTrashed = false,
  }) async {
    return store.values.where((n) {
      if (category != null &&
          category != 'all' &&
          n.category != NoteEntity.normalizeCategory(category)) {
        return false;
      }
      if (!includeArchived && n.isArchived) return false;
      if (!includeTrashed && n.isTrashed) return false;
      return true;
    }).toList();
  }

  @override
  Future<List<NoteEntity>> getNotesByLink({
    required String linkedModule,
    required String linkedId,
    bool includeArchived = true,
    bool includeTrashed = false,
  }) async {
    return store.values
        .where((n) =>
            n.linkedModule == linkedModule &&
            n.linkedId == linkedId &&
            (includeArchived || !n.isArchived) &&
            (includeTrashed || !n.isTrashed))
        .toList();
  }

  @override
  Future<List<NoteEntity>> searchNotes(String query) async {
    return store.values
        .where((n) => !n.isTrashed && n.matchesQuery(query))
        .toList();
  }

  @override
  Future<int> clearLinksForTarget({
    required String linkedModule,
    required String linkedId,
  }) async {
    return 0;
  }
}

Future<void> _disposeDbFixture(
  WidgetTester tester,
  AppDatabase db,
  List<ChangeNotifier> controllers,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
  for (final ctrl in controllers) {
    ctrl.dispose();
  }
  await tester.runAsync(
    () => db.close().timeout(const Duration(seconds: 10)),
  );
}

Future<void> _settle(WidgetTester tester) {
  return tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage N1.4 — Flutter Notes Lifecycle & Save Integrity', () {
    test(
      '1. Lifecycle filtering, counts, trash/restore preservation, and trashed-note immutability across DriftNotesRepository & NotesController',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final repo = DriftNotesRepository(db);
        final controller = NotesController(repository: repo);
        addTearDown(controller.dispose);

        final activePinnedFav = await controller.createNote(
          title: 'Pinned Favorite',
          content: '  Line 1\n    Indented line 2  \n',
          category: 'Work_Notes',
          tags: const ['Focus', 'focus', '  Architecture  ', ''],
          linkedModule: 'tasks',
          linkedId: 'task-101',
          isPinned: true,
          isFavorite: true,
        );
        final activePlain = await controller.createNote(
          title: 'Plain Active',
          content: 'Body',
        );
        final archivedNote = await controller.createNote(
          title: 'Archived Pinned Fav',
          content: 'Keep archived metadata',
          category: 'reference',
          tags: const ['spec'],
          linkedModule: 'finance',
          linkedId: 'tx-55',
          isPinned: true,
          isFavorite: true,
        );
        await controller.toggleArchive(archivedNote.id);

        // Verify category normalization, tag normalization, and untrimmed content preservation
        expect(activePinnedFav.category, 'work_notes');
        expect(activePinnedFav.tags, ['Focus', 'Architecture']);
        expect(activePinnedFav.content, '  Line 1\n    Indented line 2  \n');
        expect(activePlain.category, 'general');

        // Active / pinned / favorite / archived visibility & counts
        expect(controller.state.activeNotesCount, 2);
        expect(controller.state.pinnedNotesCount, 1);
        expect(controller.state.favoriteNotesCount, 1);
        expect(controller.state.archivedNotesCount, 1);
        expect(controller.state.trashedNotesCount, 0);

        controller.setSectionFilter('active');
        expect(
          controller.state.filteredNotes.map((n) => n.id).toSet(),
          {activePinnedFav.id, activePlain.id},
        );
        controller.setSectionFilter('pinned');
        expect(
          controller.state.filteredNotes.map((n) => n.id).toList(),
          [activePinnedFav.id],
        );
        controller.setSectionFilter('favorites');
        expect(
          controller.state.filteredNotes.map((n) => n.id).toList(),
          [activePinnedFav.id],
        );
        controller.setSectionFilter('archive');
        expect(
          controller.state.filteredNotes.map((n) => n.id).toList(),
          [archivedNote.id],
        );

        // Trash archived note -> excluded from archive, active, pinned, favorites; preserves metadata
        await controller.deleteNote(archivedNote.id);
        expect(controller.state.archivedNotesCount, 0);
        expect(controller.state.trashedNotesCount, 1);

        // Mutators on trashed note must be ignored & duplicate deleteNote must NOT permanently delete
        await controller.togglePin(archivedNote.id);
        await controller.toggleFavorite(archivedNote.id);
        await controller.toggleArchive(archivedNote.id);
        await controller.updateNote(
          id: archivedNote.id,
          title: 'Mutated in Trash',
          content: 'Should not persist',
        );
        await controller.deleteNote(archivedNote.id);

        final trashedRow = await repo.getNoteById(archivedNote.id);
        expect(trashedRow, isNotNull);
        expect(trashedRow!.title, 'Archived Pinned Fav');
        expect(trashedRow.isTrashed, isTrue);
        expect(trashedRow.isArchived, isTrue);
        expect(trashedRow.isPinned, isTrue);
        expect(trashedRow.isFavorite, isTrue);

        // Restore archived note from Trash -> returns to Archive with all metadata intact
        await controller.restoreFromTrash(archivedNote.id);
        final restoredArchived = controller.state.findById(archivedNote.id)!;
        expect(restoredArchived.isTrashed, isFalse);
        expect(restoredArchived.isArchived, isTrue);
        expect(restoredArchived.isPinned, isTrue);
        expect(restoredArchived.isFavorite, isTrue);
        expect(restoredArchived.tags, ['spec']);
        expect(restoredArchived.linkedModule, 'finance');
        expect(restoredArchived.linkedId, 'tx-55');
        expect(controller.state.archivedNotesCount, 1);

        // Trash activePinnedFav, restore -> returns to Active; then trash activePlain and emptyTrash
        await controller.deleteNote(activePinnedFav.id);
        expect(controller.state.activeNotesCount, 1);
        await controller.restoreFromTrash(activePinnedFav.id);
        expect(controller.state.activeNotesCount, 2);

        await controller.deleteNote(activePlain.id);
        await controller.emptyTrash();
        expect(await repo.getNoteById(activePlain.id), isNull);
        expect(await repo.getNoteById(activePinnedFav.id), isNotNull);
        expect(await repo.getNoteById(archivedNote.id), isNotNull);
      },
    );

    test(
      '2. Rapid createNote generates unique IDs, custom DB categories remain queryable without mutation, and search escapes % and _ literally',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final repo = DriftNotesRepository(db);
        final searchRepo = DriftSearchRepository(db);
        final controller = NotesController(repository: repo);
        addTearDown(controller.dispose);

        // Rapid creates inside the same event-loop turn must never collide on ID
        final createdPair = await Future.wait([
          controller.createNote(title: 'First', content: 'A'),
          controller.createNote(title: 'Second', content: 'B'),
        ]);
        expect(createdPair[0].id, isNot(createdPair[1].id));

        // Simulate legacy/imported mixed-case custom category directly in SQLite
        final now = DateTime.utc(2026, 11, 20, 10, 0);
        await db.into(db.notes).insert(
              NotesCompanion.insert(
                id: 'note-custom-case',
                title: '100% Budget Progress',
                content: 'Track alpha_beta metric',
                category: const Value('Work'),
                tagsJson: const Value('["custom_tag"]'),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db.into(db.notes).insert(
              NotesCompanion.insert(
                id: 'note-false-wildcard',
                title: '1000 Steps Log',
                content: 'Track alphaXbeta metric',
                category: const Value('general'),
                tagsJson: const Value('["other"]'),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db.into(db.notes).insert(
              NotesCompanion.insert(
                id: 'note-trashed-100',
                title: '100% Trashed Note',
                content: 'Should never show in search',
                isTrashed: const Value(true),
                createdAt: now,
                updatedAt: now,
              ),
            );

        // Reading does not rewrite raw SQLite row, yet getNotes(category: 'Work') matches
        final byCustomCategory = await repo.getNotes(category: 'Work');
        expect(
            byCustomCategory.map((n) => n.id).toList(), ['note-custom-case']);

        // Literal % search must NOT match '1000 Steps Log' or trashed note
        final percentMatches = await repo.searchNotes('100%');
        expect(percentMatches.map((n) => n.id).toList(), ['note-custom-case']);

        // Literal _ search must NOT match 'alphaXbeta'
        final underscoreMatches = await repo.searchNotes('alpha_beta');
        expect(
          underscoreMatches.map((n) => n.id).toList(),
          ['note-custom-case'],
        );

        // JSON syntax characters must not false-match tagsJson
        expect(await repo.searchNotes('["'), isEmpty);
        expect(
          (await repo.searchNotes('custom_tag')).map((n) => n.id).toList(),
          ['note-custom-case'],
        );

        // DriftSearchRepository.searchAll also treats % and _ literally and excludes trashed notes
        final globalPercent =
            await searchRepo.searchAll('100%', entityFilter: 'note');
        expect(globalPercent.map((r) => r.id).toList(), ['note-custom-case']);

        final globalUnderscore =
            await searchRepo.searchAll('alpha_beta', entityFilter: 'note');
        expect(
          globalUnderscore.map((r) => r.id).toList(),
          ['note-custom-case'],
        );
      },
    );

    testWidgets(
      '3. Editor prevents stale-save overwrite, preserves multiline whitespace, flushes on Back/dispose, skips blank drafts, and handles custom categories safely',
      (WidgetTester tester) async {
        final repo = _ControllableNotesRepository();
        repo.seed(
          NoteEntity(
            id: 'note-custom-1',
            title: 'Client Brief',
            content: 'Initial line',
            category: 'work_projects',
          ),
        );
        final controller = NotesController(repository: repo);
        addTearDown(controller.dispose);
        await controller.loadNotes();

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: NotesView(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        // Blank new draft must NOT create any note when opened and backed out
        await tester.tap(find.text('New Note'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(repo.createCalls, 0);
        expect(controller.state.notes.length, 1);

        // Open note with custom category 'work_projects' -> must NOT throw Dropdown assertion
        await tester.tap(find.text('Client Brief'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Work Projects'), findsWidgets);

        // Pause save #1 while editing save #2 -> save #1 completion must NOT show 'Saved' prematurely
        final firstSaveGate = Completer<void>();
        repo.nextUpdateGate = firstSaveGate;

        final bodyField = find.byType(TextField).last;
        await tester.enterText(bodyField, 'First edit');
        await tester.pump(const Duration(milliseconds: 650));
        expect(repo.updateCalls, 1);
        expect(find.text('Saving...'), findsOneWidget);

        // Type newer multiline text with intentional whitespace while save #1 is in flight
        await tester.enterText(bodyField, '  Line 1\n  Line 2  ');
        await tester.pump(const Duration(milliseconds: 650));

        // Release save #1 while pausing save #2 -> status must STILL be 'Saving...' (never premature 'Saved')
        final secondSaveGate = Completer<void>();
        repo.nextUpdateGate = secondSaveGate;
        firstSaveGate.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        expect(find.text('Saving...'), findsOneWidget);
        expect(find.text('Saved'), findsNothing);

        secondSaveGate.complete();
        await tester.pumpAndSettle();

        expect(find.text('Saved'), findsOneWidget);
        expect(repo.store['note-custom-1']?.content, '  Line 1\n  Line 2  ');
        expect(repo.store['note-custom-1']?.category, 'work_projects');

        // Type newer edit and immediately tap Pin -> pending edit must flush before togglePin
        await tester.enterText(bodyField, 'Flushed before pin\n');
        await tester.tap(find.byIcon(Icons.push_pin_outlined));
        await tester.pumpAndSettle();
        expect(
          repo.store['note-custom-1']?.content,
          'Flushed before pin\n',
        );
        expect(repo.store['note-custom-1']?.isPinned, isTrue);

        // Type newer edit and immediately tap Back before 600ms debounce -> PopScope flushes cleanly
        await tester.enterText(bodyField, 'Flushed on back navigation');
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        expect(find.byType(NotesView), findsOneWidget);
        expect(
          repo.store['note-custom-1']?.content,
          'Flushed on back navigation',
        );
      },
    );

    testWidgets(
      '4. Editor applies Untitled Note only at persistence boundary, reports write failures honestly, and blocks editing trashed notes',
      (WidgetTester tester) async {
        final repo = _ControllableNotesRepository();
        repo.seed(
          NoteEntity(
            id: 'note-trashed-ui',
            title: 'In Trash',
            content: 'Old body',
            isTrashed: true,
          ),
        );
        final controller = NotesController(repository: repo);
        addTearDown(controller.dispose);
        await controller.loadNotes();

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: NotesView(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        // Trashed note cannot be opened directly in editor
        await tester.tap(find.text('Trash'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('In Trash'));
        await tester.pumpAndSettle();
        expect(find.text('Restore note from Trash before editing'),
            findsOneWidget);
        expect(find.byType(NotesView), findsOneWidget);

        // Switch back to All Notes and test failed save reporting + recovery
        await tester.tap(find.text('All Notes'));
        await tester.pumpAndSettle();

        repo.shouldThrowOnCreate = true;
        await tester.tap(find.text('New Note'));
        await tester.pumpAndSettle();

        final titleField = find.byType(TextField).first;
        final bodyField = find.byType(TextField).last;
        await tester.enterText(bodyField, 'Unsaved body text');
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pumpAndSettle();

        // Failure must be surfaced honestly (never 'Saved'), and title input remains unmutated
        expect(find.text('Save failed'), findsOneWidget);
        expect(find.text('Saved'), findsNothing);
        expect(find.text('Unable to save note'), findsOneWidget);
        expect(
          tester.widget<TextField>(titleField).controller?.text,
          isEmpty,
        );
        expect(
          repo.store.values.any((n) => n.content == 'Unsaved body text'),
          isFalse,
        );

        // Recover DB write and tap Retry -> saves with 'Untitled Note' title fallback
        repo.shouldThrowOnCreate = false;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(find.text('Saved'), findsOneWidget);
        final created = controller.state.notes
            .firstWhere((n) => n.content == 'Unsaved body text');
        expect(created.title, NoteDomainHelpers.defaultTitle);
      },
    );

    testWidgets(
      '5. Rapid double-Back does not pop two routes and mid-flight edits are flushed before Back navigation completes',
      (WidgetTester tester) async {
        final repo = _ControllableNotesRepository();
        repo.seed(
          NoteEntity(
            id: 'note-pop-safety',
            title: 'Pop Safety Note',
            content: 'Initial content',
          ),
        );
        final controller = NotesController(repository: repo);
        addTearDown(controller.dispose);
        await controller.loadNotes();

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => NotesView(controller: controller),
                        ),
                      );
                    },
                    child: const Text('Open Notes'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Notes'));
        await tester.pumpAndSettle();
        expect(find.byType(NotesView), findsOneWidget);

        await tester.tap(find.text('Pop Safety Note'));
        await tester.pumpAndSettle();

        final bodyField = find.byType(TextField).last;
        await tester.enterText(bodyField, 'Edit before Back');

        final firstSaveGate = Completer<void>();
        repo.nextUpdateGate = firstSaveGate;

        // Tap Back twice rapidly while the first Back-triggered save is awaiting
        await tester.tap(find.byType(BackButton));
        await tester.pump();
        await tester.tap(find.byType(BackButton));
        await tester.pump();

        // While the first Back flush is still in flight, enter another edit
        await tester.enterText(bodyField, 'Edit during Back flush');
        await tester.pump();

        // Release first save -> editor must flush the newer edit before popping once
        firstSaveGate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(NotesView), findsOneWidget);
        expect(find.text('Open Notes'), findsNothing);
        expect(
          repo.store['note-pop-safety']?.content,
          'Edit during Back flush',
        );
      },
    );

    testWidgets(
      '6. Missing or trashed note updates never show Saved, preserve unsaved text, allow Retry after restore, and discard cleanly on second Back tap',
      (WidgetTester tester) async {
        final repo = _ControllableNotesRepository();
        repo.seed(
          NoteEntity(
            id: 'note-ext-lifecycle',
            title: 'External Lifecycle Note',
            content: 'Original body',
          ),
        );
        final controller = NotesController(repository: repo);
        addTearDown(controller.dispose);
        await controller.loadNotes();

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: NotesView(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('External Lifecycle Note'));
        await tester.pumpAndSettle();

        final bodyField = find.byType(TextField).last;
        await tester.enterText(bodyField, 'Edited before external trash');

        // Trash the note outside the editor before autosave completes
        await controller.deleteNote('note-ext-lifecycle');
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pumpAndSettle();

        expect(find.text('Save failed'), findsOneWidget);
        expect(find.text('Saved'), findsNothing);
        expect(find.text('Unable to save note'), findsOneWidget);
        expect(
          tester.widget<TextField>(bodyField).controller?.text,
          'Edited before external trash',
        );

        // Restore note and tap Retry -> persists cleanly and clears error
        await controller.restoreFromTrash('note-ext-lifecycle');
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(find.text('Saved'), findsOneWidget);
        expect(
          repo.store['note-ext-lifecycle']?.content,
          'Edited before external trash',
        );

        // Now delete the note permanently outside the editor and edit again
        await tester.enterText(bodyField, 'Unsaved on missing note');
        await controller.permanentlyDeleteNote('note-ext-lifecycle');
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pumpAndSettle();

        expect(find.text('Save failed'), findsOneWidget);
        expect(find.text('Saved'), findsNothing);

        // First Back tap stays open and warns to tap again to discard
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Could not save changes. Tap Back again to discard unsaved edits.',
          ),
          findsOneWidget,
        );
        expect(find.byType(NotesView), findsNothing);

        // Second Back tap intentionally discards and exits without recreating note
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(NotesView), findsOneWidget);
        expect(repo.store.containsKey('note-ext-lifecycle'), isFalse);
      },
    );

    testWidgets(
      '7. Failed task-link and unlink saves keep UI consistent with persisted note and allow Retry without phantom link changes',
      (WidgetTester tester) async {
        final fixture = await tester.runAsync(() async {
          final db = AppDatabase(NativeDatabase.memory());
          final ensureFuture = db.ensureInitialized();
          await ensureFuture.timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException(
              'db.ensureInitialized() timed out after 15s',
            ),
          );

          final tasksRepo = DriftTasksRepository(db);
          await tasksRepo.createTask(
            TaskEntity(
              id: 'task-link-1',
              title: 'Write integration tests',
            ),
          );
          final tasksController = TasksController(repository: tasksRepo);
          await tasksController.loadAll();

          final notesRepo = _ControllableNotesRepository();
          notesRepo.seed(
            NoteEntity(
              id: 'note-task-link',
              title: 'Task Link Consistency',
              content: 'Body text',
            ),
          );
          final notesController = NotesController(repository: notesRepo);
          await notesController.loadNotes();
          return (
            db: db,
            tasksController: tasksController,
            notesRepo: notesRepo,
            notesController: notesController,
          );
        });
        final db = fixture!.db;
        final tasksController = fixture.tasksController;
        final notesRepo = fixture.notesRepo;
        final notesController = fixture.notesController;
        addTearDown(
          () => _disposeDbFixture(
            tester,
            db,
            <ChangeNotifier>[notesController, tasksController],
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: NotesView(
              controller: notesController,
              tasksController: tasksController,
            ),
          ),
        );
        await _settle(tester);

        await tester.tap(find.text('Task Link Consistency'));
        await _settle(tester);

        // Fail task link persistence -> UI must NOT show linked task
        notesRepo.shouldThrowOnUpdate = true;
        await tester.tap(find.text('Link Task'));
        await _settle(tester);
        await tester.tap(find.text('Write integration tests'));
        await _settle(tester);

        expect(find.text('Linked Task: Write integration tests'), findsNothing);
        expect(find.text('Link Task'), findsOneWidget);
        expect(
          find.text('Could not link task. Kept previous link state.'),
          findsOneWidget,
        );
        expect(
          notesController.state.findById('note-task-link')?.linkedId,
          isNull,
        );

        // Recover DB and retry -> does NOT resurrect failed link; explicit link works
        notesRepo.shouldThrowOnUpdate = false;
        await tester.tap(find.text('Retry'));
        await _settle(tester);
        expect(find.text('Saved'), findsOneWidget);
        expect(find.text('Link Task'), findsOneWidget);
        expect(notesRepo.store['note-task-link']?.linkedId, isNull);

        await tester.tap(find.text('Link Task'));
        await _settle(tester);
        await tester.tap(find.text('Write integration tests'));
        await _settle(tester);
        expect(
          find.text('Linked Task: Write integration tests'),
          findsOneWidget,
        );
        expect(notesRepo.store['note-task-link']?.linkedId, 'task-link-1');

        // Fail task unlink persistence -> must keep Linked Task card and NOT show Unlinked SnackBar
        notesRepo.shouldThrowOnUpdate = true;
        await tester.tap(find.byIcon(Icons.link_off_outlined));
        await _settle(tester);

        expect(find.text('Unlinked task from note'), findsNothing);
        expect(
          find.text('Could not unlink task. Kept existing link.'),
          findsOneWidget,
        );
        expect(
          find.text('Linked Task: Write integration tests'),
          findsOneWidget,
        );
        expect(notesRepo.store['note-task-link']?.linkedId, 'task-link-1');

        // Recover DB and tap Retry -> link remains preserved
        notesRepo.shouldThrowOnUpdate = false;
        await tester.tap(find.text('Retry'));
        await _settle(tester);
        expect(find.text('Saved'), findsOneWidget);
        expect(
          find.text('Linked Task: Write integration tests'),
          findsOneWidget,
        );
        expect(notesRepo.store['note-task-link']?.linkedId, 'task-link-1');
      },
    );
  });
}
