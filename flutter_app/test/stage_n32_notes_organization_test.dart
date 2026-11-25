import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/application/notes/notes_state.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/notes_repository.dart';
import 'package:personal_management_app/domain/notes/note_helpers.dart';
import 'package:personal_management_app/domain/notes/note_models.dart';
import 'package:personal_management_app/ui/screens/notes_view.dart';
import 'package:personal_management_app/ui/widgets/shared_ui_widgets.dart';

import 'support/sqlite_test_helper.dart';

class _InMemoryNotesRepo implements INotesRepository {
  final Map<String, NoteEntity> store = <String, NoteEntity>{};

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

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage N3.2 — Flutter Notes Organization & Filtering', () {
    test(
      '1. Pure domain helpers support tag reuse, duplicate prevention, reserved folders, date filters, and created sort',
      () {
        final notes = [
          NoteEntity(
            id: 'n1',
            title: 'Zebra',
            content: 'Body',
            category: 'work_log',
            tags: const ['Architecture', 'etb'],
            isPinned: true,
            createdAt: DateTime.utc(2026, 11, 17, 21, 30),
            updatedAt: DateTime.utc(2026, 11, 24, 8),
          ),
          NoteEntity(
            id: 'n2',
            title: 'Alpha',
            content: 'Body',
            category: 'reference',
            tags: const ['architecture', 'Focus'],
            createdAt: DateTime.utc(2026, 11, 23, 8),
            updatedAt: DateTime.utc(2026, 11, 23, 9),
          ),
          NoteEntity(
            id: 'n3',
            title: 'Trashed Tag Holder',
            content: 'Body',
            isTrashed: true,
            tags: const ['DeadTag'],
            createdAt: DateTime.utc(2026, 11, 24, 8),
            updatedAt: DateTime.utc(2026, 11, 24, 9),
          ),
        ];

        final tags = NoteDomainHelpers.collectUniqueTags(notes);
        expect(tags, ['Architecture', 'etb', 'Focus']);
        expect(
          NoteDomainHelpers.resolveTagForReuse('  #architecture ', tags),
          'Architecture',
        );
        expect(
          NoteDomainHelpers.resolveTagForReuse('NewTag', tags),
          'NewTag',
        );
        expect(NoteDomainHelpers.resolveTagForReuse('###', tags), isNull);
        expect(
          NoteDomainHelpers.matchesTagFilter(notes.first.tags, 'ARCHITECTURE'),
          isTrue,
        );
        expect(NoteDomainHelpers.isReservedFolderName('Trash'), isTrue);
        expect(NoteDomainHelpers.isReservedFolderName('Research'), isFalse);

        final nowUtc = DateTime.utc(2026, 11, 24, 12);
        expect(
          NoteDomainHelpers.matchesDateFilter(
            notes[0],
            NoteDateFilterMode.created7d,
            nowUtc: nowUtc,
          ),
          isTrue,
        );
        expect(
          NoteDomainHelpers.matchesDateFilter(
            NoteEntity(
              id: 'old',
              title: 'Old',
              content: '',
              createdAt: DateTime.utc(2026, 10, 1),
              updatedAt: DateTime.utc(2026, 10, 5),
            ),
            NoteDateFilterMode.updated30d,
            nowUtc: nowUtc,
          ),
          isFalse,
        );

        final createdSorted = NoteDomainHelpers.sortNotes(
          [notes[0], notes[1]],
          sortBy: NoteSortMode.created,
          pinFirst: false,
        );
        expect(createdSorted.map((n) => n.id).toList(), ['n2', 'n1']);
      },
    );

    test(
      '2. NotesController + DriftNotesRepository + AppDatabase persist custom folders, rename safely, and preserve all notes on folder deletion',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        List<String> storedFolders = <String>[];
        final repo = DriftNotesRepository(db);
        final controller = NotesController(
          repository: repo,
          loadCustomFolders: () async {
            final raw = await db.readAppSetting(
              NotesController.customFoldersSettingKey,
            );
            if (raw == null || raw.isEmpty) return const <String>[];
            return raw.split('\n').where((e) => e.isNotEmpty).toList();
          },
          saveCustomFolders: (folders) async {
            storedFolders = folders;
            await db.writeAppSetting(
              NotesController.customFoldersSettingKey,
              folders.join('\n'),
            );
          },
        );
        addTearDown(controller.dispose);

        await controller.loadNotes();

        // Create custom folder + block reserved/built-in/empty
        expect((await controller.createFolder('')).ok, isFalse);
        expect((await controller.createFolder('Favorites')).ok, isFalse);
        expect((await controller.createFolder('general')).ok, isFalse);
        final createdFolder = await controller.createFolder('Research');
        expect(createdFolder.ok, isTrue);
        expect(createdFolder.folder, 'research');
        expect(storedFolders, ['research']);

        // Seed active, archived, and trashed notes in custom folder
        final nActive = await controller.createNote(
          title: 'Active Research Note',
          content: 'Findings',
          category: 'research',
          tags: const ['field'],
          linkedModule: 'tasks',
          linkedId: 'task-99',
        );
        final nArchived = await controller.createNote(
          title: 'Archived Research Note',
          content: 'Old findings',
          category: 'research',
        );
        await controller.toggleArchive(nArchived.id);
        final nTrashed = await controller.createNote(
          title: 'Trashed Research Note',
          content: 'Discard',
          category: 'research',
        );
        await controller.deleteNote(nTrashed.id);

        // Rename custom folder -> updates active & archived notes, keeps Trash untouched
        final renamed = await controller.renameFolder('research', 'Lab Notes');
        expect(renamed.ok, isTrue);
        expect(renamed.folder, 'lab notes');
        expect(renamed.affectedCount, 2);
        expect(controller.state.findById(nActive.id)?.category, 'lab notes');
        expect(controller.state.findById(nActive.id)?.linkedId, 'task-99');
        expect(controller.state.findById(nArchived.id)?.category, 'lab notes');
        expect(controller.state.findById(nTrashed.id)?.category, 'research');

        // Reload in fresh controller verifies SQLite persistence of folders & moved notes
        final controller2 = NotesController(
          repository: repo,
          loadCustomFolders: () async {
            final raw = await db.readAppSetting(
              NotesController.customFoldersSettingKey,
            );
            if (raw == null || raw.isEmpty) return const <String>[];
            return raw.split('\n').where((e) => e.isNotEmpty).toList();
          },
          saveCustomFolders: (folders) async {
            await db.writeAppSetting(
              NotesController.customFoldersSettingKey,
              folders.join('\n'),
            );
          },
        );
        addTearDown(controller2.dispose);
        await controller2.loadNotes();
        expect(controller2.state.customFolders, ['lab notes']);
        expect(controller2.state.findById(nActive.id)?.category, 'lab notes');

        // Delete folder -> zero note loss, active & archived move safely to general
        controller2.setCategoryFilter('lab notes');
        final deleted = await controller2.deleteFolder('lab notes');
        expect(deleted.ok, isTrue);
        expect(deleted.movedCount, 2);
        expect(deleted.destinationFolder, 'general');
        expect(controller2.state.categoryFilter, 'all');
        expect(controller2.state.customFolders, isEmpty);
        expect(controller2.state.findById(nActive.id)?.category, 'general');
        expect(controller2.state.findById(nArchived.id)?.category, 'general');
        expect(controller2.state.findById(nTrashed.id)?.category, 'research');
        expect(
          await repo.getNotes(includeArchived: true, includeTrashed: true),
          hasLength(3),
        );

        // Move note between folders; reject trashed notes
        final moveOk =
            await controller2.moveNoteToFolder(nActive.id, 'reference');
        expect(moveOk.saved, isTrue);
        expect(controller2.state.findById(nActive.id)?.category, 'reference');
        final moveTrashed =
            await controller2.moveNoteToFolder(nTrashed.id, 'general');
        expect(moveTrashed.saved, isFalse);
      },
    );

    test(
      '3. Combined orthogonal filtering excludes Archive/Trash from active views and combines folder + tag + date + search + sort',
      () async {
        final now = DateTime.now().toUtc();
        final repo = _InMemoryNotesRepo();
        repo.seed(
          NoteEntity(
            id: 'n-match-1',
            title: 'Sprint Notes',
            content: 'Action plan',
            category: 'work',
            tags: const ['Focus', 'q2'],
            isPinned: true,
            isFavorite: true,
            createdAt: now.subtract(const Duration(days: 5)),
            updatedAt: now.subtract(const Duration(days: 1)),
          ),
        );
        repo.seed(
          NoteEntity(
            id: 'n-match-2',
            title: 'Alpha Sprint',
            content: 'Action plan',
            category: 'work',
            tags: const ['focus'],
            isPinned: false,
            isFavorite: true,
            createdAt: now.subtract(const Duration(days: 2)),
            updatedAt: now.subtract(const Duration(days: 2)),
          ),
        );
        repo.seed(
          NoteEntity(
            id: 'n-archived',
            title: 'Archived Action',
            content: 'Action plan',
            category: 'work',
            tags: const ['focus'],
            isFavorite: true,
            isArchived: true,
            createdAt: now,
            updatedAt: now,
          ),
        );
        repo.seed(
          NoteEntity(
            id: 'n-trashed',
            title: 'Trashed Action',
            content: 'Action plan',
            category: 'work',
            tags: const ['focus'],
            isFavorite: true,
            isTrashed: true,
            createdAt: now,
            updatedAt: now,
          ),
        );

        final controller = NotesController(repository: repo);
        addTearDown(controller.dispose);
        await controller.loadNotes();

        controller.setSectionFilter('favorites');
        controller.setCategoryFilter('work');
        controller.setTagFilter('focus');
        controller.setDateFilter('updated_7d');
        controller.setSearchQuery('action');
        controller.setSortBy('alpha');

        expect(
          controller.state.filteredNotes.map((n) => n.id).toList(),
          ['n-match-1', 'n-match-2'],
        );

        controller.setSortBy('created');
        expect(
          controller.state.filteredNotes.map((n) => n.id).toList(),
          ['n-match-1', 'n-match-2'],
        );

        controller.clearFilters();
        expect(controller.state.filteredNotes.map((n) => n.id).toSet(), {
          'n-match-1',
          'n-match-2',
        });
      },
    );

    testWidgets(
      '4. NotesView supports folder create/rename/delete, card Move to Folder, tag/date filters, +N badge, empty-folder state, and tag reuse dialog',
      (WidgetTester tester) async {
        final now = DateTime.now().toUtc();
        final repo = _InMemoryNotesRepo();
        repo.seed(
          NoteEntity(
            id: 'n1',
            title: 'Roadmap Planning',
            content: 'Review milestones and priorities.',
            category: 'reflection',
            tags: const ['architecture', 'q2', 'extra'],
            isPinned: true,
            isFavorite: true,
            createdAt: now.subtract(const Duration(days: 2)),
            updatedAt: now.subtract(const Duration(hours: 3)),
          ),
        );
        repo.seed(
          NoteEntity(
            id: 'n2',
            title: 'Reading Highlights',
            content: 'Notes on architecture and clean layering.',
            category: 'learning',
            tags: const ['reading'],
            createdAt: now.subtract(const Duration(days: 10)),
            updatedAt: now.subtract(const Duration(days: 9)),
          ),
        );

        final controller = NotesController(repository: repo);
        await controller.loadNotes();

        await tester.binding.setSurfaceSize(const Size(360, 760));
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light(),
            home: NotesView(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        // Overflow tag badge (+1) and folder/tag chips are visible
        expect(find.text('+1'), findsOneWidget);
        expect(find.text('All Tags'), findsOneWidget);
        expect(find.text('Updated 7d'), findsOneWidget);

        // Tag + Date filtering updates list & offers Clear filters when empty
        await tester.tap(find.text('#reading'));
        await tester.pumpAndSettle();
        expect(find.text('Reading Highlights'), findsOneWidget);
        expect(find.text('Roadmap Planning'), findsNothing);

        await tester.tap(find.text('Updated 7d'));
        await tester.pumpAndSettle();
        expect(find.text('No notes match your active filters'), findsOneWidget);
        await tester.tap(find.text('Clear filters').last);
        await tester.pumpAndSettle();
        expect(find.text('Roadmap Planning'), findsOneWidget);

        // Create a custom folder from the list -> empty-folder state shown
        await tester.tap(find.text('New Folder'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(DaywellTextField), 'Research');
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();
        expect(controller.state.categoryFilter, 'research');
        expect(find.text('No notes in Research'), findsOneWidget);
        expect(find.text('Folder: Research'), findsOneWidget);

        // Rename custom folder
        await tester.tap(find.text('Rename'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(DaywellTextField), 'Field Lab');
        await tester.tap(find.widgetWithText(DaywellButton, 'Rename'));
        await tester.pumpAndSettle();
        expect(controller.state.categoryFilter, 'field lab');
        expect(find.text('Folder: Field Lab'), findsOneWidget);

        // Move a note to Field Lab via card menu
        await tester.tap(find.text('All Folders'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Note actions').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Move to Folder'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Field Lab').last);
        await tester.pumpAndSettle();
        expect(controller.state.findById('n1')?.category, 'field lab');

        // Delete Field Lab -> confirmation dialog warns no notes will be deleted & moves note to General
        await tester.tap(find.text('Field Lab').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete Folder'));
        await tester.pumpAndSettle();
        expect(find.byType(DaywellConfirmationDialog), findsOneWidget);
        await tester.tap(find.widgetWithText(DaywellButton, 'Delete Folder'));
        await tester.pumpAndSettle();
        expect(controller.state.findById('n1')?.category, 'general');

        // Open editor for Reading Highlights -> Add Tag shows Existing tags chips and reuses casing
        await tester.tap(find.text('Reading Highlights'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Tag'));
        await tester.pumpAndSettle();
        expect(find.text('Existing tags'), findsOneWidget);
        await tester.tap(find.text('#architecture'));
        await tester.pumpAndSettle();
        expect(find.text('#architecture'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.binding.setSurfaceSize(null);
      },
    );
  });
}
