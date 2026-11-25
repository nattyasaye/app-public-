import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/calendar_repository.dart';
import 'package:personal_management_app/data/repositories/inbox_repository.dart';
import 'package:personal_management_app/data/repositories/notes_repository.dart';
import 'package:personal_management_app/data/repositories/search_repository.dart';
import 'package:personal_management_app/data/repositories/tasks_repository.dart';
import 'package:personal_management_app/ui/screens/notes_view.dart';

import 'support/sqlite_test_helper.dart';

class _StageN41InMemoryNotesRepository implements INotesRepository {
  final Map<String, NoteEntity> store = <String, NoteEntity>{};
  bool failUpdates = false;

  void seed(NoteEntity note) {
    store[note.id] = note;
  }

  @override
  Future<NoteEntity> createNote(NoteEntity note) async {
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
        .where(
          (n) =>
              n.linkedModule == linkedModule &&
              n.linkedId == linkedId &&
              (includeArchived || !n.isArchived) &&
              (includeTrashed || !n.isTrashed),
        )
        .toList();
  }

  @override
  Future<List<NoteEntity>> searchNotes(String query) async {
    return store.values
        .where((n) => !n.isTrashed && n.matchesQuery(query))
        .toList();
  }

  @override
  Future<NoteEntity> updateNote(NoteEntity note) async {
    if (failUpdates) {
      throw Exception('Simulated persistence failure');
    }
    store[note.id] = note;
    return note;
  }

  @override
  Future<int> clearLinksForTarget({
    required String linkedModule,
    required String linkedId,
  }) async {
    return 0;
  }
}

Widget _wrapNotesApp({
  required NotesController controller,
  required Size surfaceSize,
  ({String noteId, int nonce})? requestedNoteFocus,
  void Function(Future<bool> Function()? flushHandler)?
      onRegisterPendingSaveFlush,
}) {
  return MaterialApp(
    theme: DaywellTheme.light,
    home: MediaQuery(
      data: MediaQueryData(size: surfaceSize),
      child: NotesView(
        controller: controller,
        requestedNoteFocus: requestedNoteFocus,
        onRegisterPendingSaveFlush: onRegisterPendingSaveFlush,
      ),
    ),
  );
}

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage N4.1 — Shared Search Integration (DriftSearchRepository)', () {
    test(
      '1. Searches note titles, Markdown-spanning content phrases, #tags, and formatted folders with Note snippets while excluding Trash and preserving Archive',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final notesRepo = DriftNotesRepository(db);
        final searchRepo = DriftSearchRepository(db);
        final now = DateTime.utc(2026, 3, 1, 10);

        await notesRepo.createNote(
          NoteEntity(
            id: 'note-active-md',
            title: 'Portfolio Design Notes',
            content:
                '## Story Arc\n- **Simplicity** vs *Power* trade-offs.\n- [ ] Ship offline review',
            category: 'work_projects',
            tags: const ['architecture', 'design'],
            createdAt: now,
            updatedAt: now,
          ),
        );
        await notesRepo.createNote(
          NoteEntity(
            id: 'note-amharic',
            title: 'የዓመት ዕቅድ ማስታወሻ',
            content: 'በየቀኑ 20 ደቂቃ የእግር ጉዞ።',
            category: 'reflection',
            tags: const ['ethiopian_calendar'],
            createdAt: now,
            updatedAt: now,
          ),
        );
        await notesRepo.createNote(
          NoteEntity(
            id: 'note-archived',
            title: 'Archived Tax Checklist',
            content: 'Keep receipts filed.',
            category: 'reference',
            tags: const ['tax'],
            isArchived: true,
            createdAt: now,
            updatedAt: now,
          ),
        );
        await notesRepo.createNote(
          NoteEntity(
            id: 'note-trashed',
            title: 'Trashed Portfolio Secret',
            content: 'Simplicity vs Power inside trash',
            category: 'work_projects',
            tags: const ['architecture'],
            isTrashed: true,
            createdAt: now,
            updatedAt: now,
          ),
        );
        // Legacy whitespace-only title stored directly in SQLite
        await db.into(db.notes).insert(
              NotesCompanion.insert(
                id: 'note-blank-title',
                title: '   ',
                content: 'Unique plain phrase inside untitled body.',
                category: const Value('general'),
                tagsJson: const Value('["fallback_tag"]'),
                createdAt: now,
                updatedAt: now,
              ),
            );

        // Title (English + Amharic) & blank-title normalization
        final byTitle = await searchRepo.searchAll('portfolio design');
        expect(byTitle.map((r) => r.id), ['note-active-md']);
        expect(byTitle.single.entityType, 'note');
        expect(byTitle.single.snippet, startsWith('Note • Work Projects • '));
        expect(byTitle.single.snippet!.contains('**'), isFalse);
        expect(byTitle.single.snippet!.contains('##'), isFalse);
        expect(byTitle.single.snippet!.contains('- [ ]'), isFalse);

        final byAmharic = await searchRepo.searchAll('ዕቅድ');
        expect(byAmharic.map((r) => r.id), ['note-amharic']);

        final untitledMatch = await searchRepo.searchAll('unique plain phrase');
        expect(untitledMatch.single.id, 'note-blank-title');
        expect(untitledMatch.single.title, 'Untitled Note');

        // Phrase across inline Markdown formatting
        final byMdPhrase = await searchRepo.searchAll('simplicity vs power');
        expect(byMdPhrase.map((r) => r.id), ['note-active-md']);

        // Tag (#tag & bare tag) and formatted folder matching
        final byHashTag = await searchRepo.searchAll('#architecture');
        expect(byHashTag.map((r) => r.id), ['note-active-md']);
        final byFolder = await searchRepo.searchAll('Work Projects');
        expect(byFolder.map((r) => r.id), ['note-active-md']);

        // Archive preserved with clear status snippet; Trash always excluded
        final byArchived = await searchRepo.searchAll('tax checklist');
        expect(byArchived.map((r) => r.id), ['note-archived']);
        expect(byArchived.single.snippet,
            startsWith('Note • Reference (Archived)'));

        final trashedQuery = await searchRepo.searchAll('Trashed Portfolio');
        expect(trashedQuery, isEmpty);
      },
    );

    test(
      '2. Dynamic edits, renames, folder changes, archive, trash, and restore reflect immediately while other modules remain unaffected',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final notesRepo = DriftNotesRepository(db);
        final controller = NotesController(repository: notesRepo);
        addTearDown(controller.dispose);
        await controller.loadNotes();

        final tasksRepo = DriftTasksRepository(db);
        final inboxRepo = DriftInboxRepository(db);
        final calendarRepo = DriftCalendarRepository(db);
        final searchRepo = DriftSearchRepository(db);

        await inboxRepo.captureQuickThought(
          'Inbox shared token alpha',
          category: 'task',
        );
        await tasksRepo.createTask(
          TaskEntity(
            id: 'task-shared-1',
            title: 'Task shared token alpha',
          ),
        );
        await calendarRepo.createEvent(
          CalendarEventEntity(
            id: 'event-shared-1',
            title: 'Event shared token alpha',
            dateIso: '2026-03-01',
          ),
        );

        final created = await controller.createNote(
          title: 'Initial Draft',
          content: 'Shared token alpha body.',
          category: 'general',
          tags: const ['initial'],
        );

        // Unfiltered search returns all 4 entity types without regressions
        final allAlpha = await searchRepo.searchAll('shared token alpha');
        expect(
          allAlpha.map((r) => r.entityType).toSet(),
          {'inbox', 'task', 'event', 'note'},
        );
        final tasksOnly = await searchRepo.searchAll(
          'shared token alpha',
          entityFilter: 'task',
        );
        expect(tasksOnly.map((r) => r.entityType), ['task']);

        // Rename, move folder, add tag -> immediately reflected in search
        await controller.updateNote(
          id: created.id,
          title: 'Renamed Strategy Guide',
          content: 'Shared token alpha body.',
          tags: const ['initial', 'roadmap'],
        );
        await controller.moveNoteToFolder(created.id, 'strategy_docs');

        expect(await searchRepo.searchAll('Initial Draft'), isEmpty);
        final byRenamed = await searchRepo.searchAll('Renamed Strategy Guide');
        expect(byRenamed.map((r) => r.id), [created.id]);
        expect(byRenamed.single.snippet, startsWith('Note • Strategy Docs'));
        expect(
          (await searchRepo.searchAll('#roadmap')).map((r) => r.id),
          [created.id],
        );

        // Archive -> stays searchable; Trash -> hidden; Restore -> searchable again
        await controller.toggleArchive(created.id);
        final archivedHit = await searchRepo.searchAll('Strategy Docs');
        expect(archivedHit.single.snippet,
            startsWith('Note • Strategy Docs (Archived)'));

        await controller.deleteNote(created.id);
        expect(await searchRepo.searchAll('Renamed Strategy Guide'), isEmpty);

        await controller.restoreFromTrash(created.id);
        expect(
          (await searchRepo.searchAll('Renamed Strategy Guide'))
              .map((r) => r.id),
          [created.id],
        );
      },
    );
  });

  group(
      'Stage N4.1 — Search Result Navigation & Unsaved Edit Safety (NotesView)',
      () {
    testWidgets(
      '3. Wide requestedNoteFocus opens archived/filtered targets, flushes pending edits, blocks on save error, handles deleted & trashed targets, and exposes tab-leave flush handler',
      (tester) async {
        const size = Size(960, 800);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = _StageN41InMemoryNotesRepository();
        final now = DateTime.utc(2026, 3, 2, 9);
        repo.seed(
          NoteEntity(
            id: 'note-open',
            title: 'Active Draft Note',
            content: 'Original draft text',
            category: 'reference',
            tags: const ['architecture'],
            createdAt: now,
            updatedAt: now,
          ),
        );
        repo.seed(
          NoteEntity(
            id: 'note-archived-target',
            title: 'Archived Research Target',
            content: 'Archived details inside learning folder',
            category: 'learning',
            tags: const ['finance'],
            isArchived: true,
            createdAt: now,
            updatedAt: now,
          ),
        );
        repo.seed(
          NoteEntity(
            id: 'note-trashed-target',
            title: 'Trashed Note Target',
            content: 'Inside trash',
            category: 'general',
            isTrashed: true,
            createdAt: now,
            updatedAt: now,
          ),
        );

        final controller = NotesController(repository: repo);
        addTearDown(controller.dispose);
        await controller.loadNotes();

        // Restrict active filters so the archived learning target would otherwise be hidden
        controller.setCategoryFilter('reference');
        controller.setTagFilter('architecture');
        controller.setSearchQuery('draft');

        Future<bool> Function()? registeredFlush;
        await tester.pumpWidget(
          _wrapNotesApp(
            controller: controller,
            surfaceSize: size,
            onRegisterPendingSaveFlush: (handler) => registeredFlush = handler,
          ),
        );
        await tester.pumpAndSettle();

        expect(registeredFlush, isNotNull);

        // Open Active Draft Note & type unsaved text without waiting 600ms debounce
        await tester.tap(find.text('Active Draft Note'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'Original draft text'),
          'Dirty edit before navigation',
        );
        await tester.pump();

        // Non-existent / permanently deleted noteId -> warning without discarding dirty draft
        await tester.pumpWidget(
          _wrapNotesApp(
            controller: controller,
            surfaceSize: size,
            requestedNoteFocus: (noteId: 'missing-note', nonce: 1),
            onRegisterPendingSaveFlush: (handler) => registeredFlush = handler,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('This note is no longer available.'), findsOneWidget);
        expect(find.text('Dirty edit before navigation'), findsOneWidget);

        // Trashed noteId -> restore prompt without discarding dirty draft or opening trashed note
        await tester.pumpWidget(
          _wrapNotesApp(
            controller: controller,
            surfaceSize: size,
            requestedNoteFocus: (noteId: 'note-trashed-target', nonce: 2),
            onRegisterPendingSaveFlush: (handler) => registeredFlush = handler,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Restore note from Trash before editing'),
            findsOneWidget);
        expect(find.text('Dirty edit before navigation'), findsOneWidget);

        // Simulated persistence failure aborts requestedNoteFocus switch preserving draft
        repo.failUpdates = true;
        await tester.pumpWidget(
          _wrapNotesApp(
            controller: controller,
            surfaceSize: size,
            requestedNoteFocus: (noteId: 'note-archived-target', nonce: 3),
            onRegisterPendingSaveFlush: (handler) => registeredFlush = handler,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Could not save current note changes'),
          findsOneWidget,
        );
        expect(find.text('Dirty edit before navigation'), findsOneWidget);

        // Recover & trigger focus again -> flushes Active Draft Note, aligns archive + clears conflicting filters, opens target in detail pane
        repo.failUpdates = false;
        await tester.pumpWidget(
          _wrapNotesApp(
            controller: controller,
            surfaceSize: size,
            requestedNoteFocus: (noteId: 'note-archived-target', nonce: 4),
            onRegisterPendingSaveFlush: (handler) => registeredFlush = handler,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          controller.state.findById('note-open')?.content,
          'Dirty edit before navigation',
        );
        expect(controller.state.sectionFilter, 'archive');
        expect(controller.state.categoryFilter, 'all');
        expect(controller.state.tagFilter, 'all');
        expect(controller.state.searchQuery, '');
        expect(find.byType(BackButton), findsNothing);
        expect(
          find.widgetWithText(TextField, 'Archived Research Target'),
          findsOneWidget,
        );

        // Tab-leave flush handler immediately persists edits without waiting 600ms
        await tester.enterText(
          find.widgetWithText(
            TextField,
            'Archived details inside learning folder',
          ),
          'Flushed on tab leave',
        );
        await tester.pump();
        final flushedOk = await registeredFlush!.call();
        await tester.pumpAndSettle();
        expect(flushedOk, isTrue);
        expect(
          controller.state.findById('note-archived-target')?.content,
          'Flushed on tab leave',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '4. Narrow requestedNoteFocus while editing flushes dirty draft and replaces active route without stacking routes',
      (tester) async {
        const size = Size(390, 800);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = _StageN41InMemoryNotesRepository();
        final now = DateTime.utc(2026, 3, 2, 9);
        repo.seed(
          NoteEntity(
            id: 'narrow-1',
            title: 'First Mobile Note',
            content: 'First mobile content',
            category: 'general',
            createdAt: now,
            updatedAt: now,
          ),
        );
        repo.seed(
          NoteEntity(
            id: 'narrow-2',
            title: 'Second Mobile Note',
            content: 'Second mobile content',
            category: 'reference',
            createdAt: now,
            updatedAt: now,
          ),
        );

        final controller = NotesController(repository: repo);
        addTearDown(controller.dispose);
        await controller.loadNotes();

        await tester.pumpWidget(
          _wrapNotesApp(controller: controller, surfaceSize: size),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('First Mobile Note'));
        await tester.pumpAndSettle();
        expect(find.byType(BackButton), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, 'First mobile content'),
          'Saved before mobile search jump',
        );
        await tester.pump();

        // Jump via requestedNoteFocus to narrow-2 while narrow-1 editor is open
        await tester.pumpWidget(
          _wrapNotesApp(
            controller: controller,
            surfaceSize: size,
            requestedNoteFocus: (noteId: 'narrow-2', nonce: 10),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          controller.state.findById('narrow-1')?.content,
          'Saved before mobile search jump',
        );
        expect(
          find.widgetWithText(TextField, 'Second Mobile Note'),
          findsOneWidget,
        );

        // Single Back tap returns straight to Notes list (route replaced cleanly)
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(BackButton), findsNothing);
        expect(find.text('First Mobile Note'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
