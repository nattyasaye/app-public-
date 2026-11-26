import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/application/projects/projects_controller.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/database_persistence_coordinator.dart';
import 'package:personal_management_app/data/repositories/notes_repository.dart';
import 'package:personal_management_app/data/repositories/projects_repository.dart';
import 'package:personal_management_app/data/repositories/search_repository.dart';
import 'package:personal_management_app/domain/notes/project_notes_helpers.dart';
import 'package:personal_management_app/domain/tasks/task_models.dart';
import 'package:personal_management_app/ui/screens/notes_view.dart';
import 'package:personal_management_app/ui/screens/projects/project_detail_screen.dart';
import 'package:personal_management_app/ui/screens/projects/project_notes_widget.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage N5.1 — Project Notes Integration', () {
    test(
      '1. ProjectNotesHelper filters, sorts (active before archived, pinned first, trashed excluded), counts, and builds previews',
      () {
        final p1 = ProjectEntity(id: 'proj-1', title: 'Solar Upgrade');
        final longProj = ProjectEntity(id: 'proj-long', title: 'P' * 280);
        final t1 = DateTime.utc(2026, 3, 1, 9);
        final t2 = DateTime.utc(2026, 3, 2, 9);
        final t3 = DateTime.utc(2026, 3, 3, 9);

        final notes = <NoteEntity>[
          NoteEntity(
            id: 'n-arch',
            title: 'Archived Spec',
            content: 'Legacy inverter diagram',
            projectId: 'proj-1',
            isArchived: true,
            createdAt: t1,
            updatedAt: t3,
          ),
          NoteEntity(
            id: 'n-active',
            title: 'Cable Plan',
            content: '## Main\n- **6mm** copper run with [[Batteries]].',
            projectId: 'proj-1',
            createdAt: t1,
            updatedAt: t2,
          ),
          NoteEntity(
            id: 'n-pin',
            title: 'Breaker Safety',
            content: '- [ ] Tag out main line',
            projectId: 'proj-1',
            isPinned: true,
            createdAt: t1,
            updatedAt: t1,
          ),
          NoteEntity(
            id: 'n-trash',
            title: 'Deleted Quote',
            content: '',
            projectId: 'proj-1',
            isTrashed: true,
          ),
          NoteEntity(
            id: 'n-other',
            title: 'Other Note',
            content: '',
            projectId: 'proj-2',
          ),
        ];

        final result = ProjectNotesHelper.getNotesForProject(notes, 'proj-1');
        expect(
            result.map((n) => n.id).toList(), ['n-pin', 'n-active', 'n-arch']);
        expect(ProjectNotesHelper.countNotesForProject(notes, 'proj-1'), 3);
        expect(
          ProjectNotesHelper.countNotesForProject(
            notes,
            'proj-1',
            includeArchived: false,
          ),
          2,
        );
        expect(ProjectNotesHelper.isNoteLinkedToProject(notes[3], 'proj-1'),
            false);
        expect(
            ProjectNotesHelper.findLinkedProject(notes[1], [p1])?.id, 'proj-1');
        expect(ProjectNotesHelper.findLinkedProject(notes[4], [p1]), isNull);
        expect(
          ProjectNotesHelper.buildDefaultProjectNoteTitle(p1),
          'Solar Upgrade — Note',
        );
        expect(
          ProjectNotesHelper.buildDefaultProjectNoteTitle(longProj).length,
          NoteEntity.maxTitleLength,
        );
        expect(
          ProjectNotesHelper.buildContentPreview(notes[1].content),
          contains('6mm copper run'),
        );
      },
    );

    test(
      '2. DriftProjectsRepository, NotesController & DriftSearchRepository support creating/relinking/unlinking projectId, preserve notes on project archive/delete, and keep task links intact',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final projectsRepo = DriftProjectsRepository(db);
        final notesRepo = DriftNotesRepository(db);
        final searchRepo = DriftSearchRepository(db);
        final notesCtrl = NotesController(repository: notesRepo);
        addTearDown(notesCtrl.dispose);

        final p1 = await projectsRepo.createProject(
          ProjectEntity(id: 'proj-a', title: 'Coffee Export Portal'),
        );
        final p2 = await projectsRepo.createProject(
          ProjectEntity(id: 'proj-b', title: 'Warehouse Upgrade'),
        );

        final created = await notesCtrl.createNote(
          id: 'note-p1',
          title: ProjectNotesHelper.buildDefaultProjectNoteTitle(p1),
          content: 'Customs permit checklist [[Shipping Docs]]',
          projectId: p1.id,
          category: 'work_projects',
          tags: const ['logistics'],
          linkedModule: NoteEntity.taskLinkModule,
          linkedId: 'task-customs-1',
        );
        expect(created.projectId, p1.id);
        expect(created.linkedModule, NoteEntity.taskLinkModule);
        expect(created.linkedId, 'task-customs-1');

        // Reassign projectId to p2 via NotesController.setNoteProject while preserving task link & metadata
        final reassignRes = await notesCtrl.setNoteProject(
          noteId: created.id,
          projectId: p2.id,
        );
        expect(reassignRes.saved, isTrue);
        final reassigned = notesCtrl.state.findById(created.id);
        expect(reassigned?.projectId, p2.id);
        expect(reassigned?.linkedModule, NoteEntity.taskLinkModule);
        expect(reassigned?.linkedId, 'task-customs-1');
        expect(reassigned?.tags, const ['logistics']);
        expect(reassigned?.category, 'work_projects');

        // Search matches note by associated project title
        final searchHits = await searchRepo.searchAll(
          'Warehouse Upgrade',
          entityFilter: 'note',
        );
        expect(searchHits.map((r) => r.id), contains('note-p1'));
        expect(
            searchHits.first.snippet, contains('Project: Warehouse Upgrade'));

        // Clear project association without deleting note
        final clearRes = await notesCtrl.setNoteProject(
          noteId: created.id,
          projectId: null,
        );
        expect(clearRes.saved, isTrue);
        expect(notesCtrl.state.findById(created.id)?.projectId, isNull);
        expect(await notesRepo.getNoteById('note-p1'), isNotNull);

        // Relink to p1, archive p1 (note remains linked), then delete p1 (note remains intact & unlinked)
        await notesCtrl.setNoteProject(noteId: created.id, projectId: p1.id);
        await projectsRepo.setProjectArchived(p1.id, true);
        final afterArchive = await notesRepo.getNoteById('note-p1');
        expect(afterArchive?.projectId, p1.id);

        await projectsRepo.deleteProject(p1.id);
        final afterDelete = await notesRepo.getNoteById('note-p1');
        expect(afterDelete, isNotNull);
        expect(afterDelete?.projectId, isNull);
        expect(afterDelete?.linkedModule, NoteEntity.taskLinkModule);
        expect(afterDelete?.linkedId, 'task-customs-1');
        expect(afterDelete?.tags, const ['logistics']);
      },
    );

    test(
      '3. DatabasePersistenceCoordinator round-trips Note projectId and clears orphaned missing project references safely on restore',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final coordinator = DatabasePersistenceCoordinator(db);
        final payload = jsonEncode({
          'schemaVersion': 5,
          'snapshotFormatVersion': 2,
          'databaseSchemaVersion': 12,
          'exportedAt': '2026-03-05T10:00:00.000Z',
          'projects': [
            {
              'id': 'proj-live',
              'title': 'Live Project',
              'status': 'active',
              'isArchived': false,
              'createdAt': '2026-03-01T08:00:00.000Z',
              'updatedAt': '2026-03-01T08:00:00.000Z',
            },
          ],
          'notes': [
            {
              'id': 'note-valid-proj',
              'title': 'Valid Project Note',
              'body': 'Body',
              'folder': 'general',
              'tags': <String>[],
              'projectId': 'proj-live',
              'createdAt': '2026-03-01T08:00:00.000Z',
              'updatedAt': '2026-03-01T08:00:00.000Z',
            },
            {
              'id': 'note-orphan-proj',
              'title': 'Orphan Project Note',
              'body': 'Body',
              'folder': 'general',
              'tags': <String>[],
              'projectId': 'proj-deleted',
              'createdAt': '2026-03-01T08:00:00.000Z',
              'updatedAt': '2026-03-01T08:00:00.000Z',
            },
          ],
        });

        final report = await coordinator.importSnapshotDetailed(
          jsonDecode(payload) as Map<String, dynamic>,
        );
        expect(report.restoredRecordCounts['notes'], 2);

        final notesRepo = DriftNotesRepository(db);
        final validNote = await notesRepo.getNoteById('note-valid-proj');
        final orphanNote = await notesRepo.getNoteById('note-orphan-proj');
        expect(validNote?.projectId, 'proj-live');
        expect(orphanNote, isNotNull);
        expect(orphanNote?.projectId, isNull);
      },
    );

    testWidgets(
      '4. ProjectNotesWidget renders empty state, creates a note with projectId, opens existing project notes, and NotesView handles missing project references safely',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final fixture = await tester.runAsync(() async {
          final db = AppDatabase(NativeDatabase.memory());
          await db.ensureInitialized().timeout(const Duration(seconds: 15));

          final projectsRepo = DriftProjectsRepository(db);
          final notesRepo = DriftNotesRepository(db);
          final projectsCtrl = ProjectsController(repository: projectsRepo);
          final notesCtrl = NotesController(repository: notesRepo);

          final project = await projectsRepo.createProject(
            ProjectEntity(id: 'proj-ui-1', title: 'Field Research'),
          );
          await projectsCtrl.loadAll();
          await notesCtrl.loadNotes();
          return (
            db: db,
            projectsCtrl: projectsCtrl,
            notesCtrl: notesCtrl,
            project: project,
          );
        });
        final db = fixture!.db;
        final projectsCtrl = fixture.projectsCtrl;
        final notesCtrl = fixture.notesCtrl;
        final project = fixture.project;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 20));
          projectsCtrl.dispose();
          notesCtrl.dispose();
          await tester.runAsync(
            () => db.close().timeout(const Duration(seconds: 10)),
          );
        });

        final openedNoteIds = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ProjectNotesWidget(
                  project: project,
                  notesController: notesCtrl,
                  onOpenNote: openedNoteIds.add,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('NOTES (0)'), findsOneWidget);
        expect(find.text('No notes for this project yet'), findsOneWidget);

        // Tap New Note from ProjectNotesWidget
        await tester.tap(find.text('New Note').first);
        await tester.pumpAndSettle();

        expect(notesCtrl.state.notes.length, 1);
        final createdNote = notesCtrl.state.notes.first;
        expect(createdNote.projectId, 'proj-ui-1');
        expect(createdNote.title, 'Field Research — Note');
        expect(openedNoteIds, [createdNote.id]);
        expect(find.text('NOTES (1)'), findsOneWidget);

        // Simulate an in-memory note pointing to a missing project and verify ProjectDetailScreen + NotesView render cleanly
        notesCtrl.replaceNotes(<NoteEntity>[
          ...notesCtrl.state.notes,
          NoteEntity(
            id: 'note-missing-proj',
            title: 'Legacy Field Note',
            content: 'Still readable',
            projectId: 'proj-gone-999',
            createdAt: DateTime.utc(2026, 3, 4, 9),
            updatedAt: DateTime.utc(2026, 3, 4, 9),
          ),
        ]);

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: MediaQuery(
              data: const MediaQueryData(size: Size(1000, 800)),
              child: NotesView(
                controller: notesCtrl,
                projectsController: projectsCtrl,
                requestedNoteFocus: (noteId: 'note-missing-proj', nonce: 1),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Project unavailable'), findsWidgets);
        expect(find.text('Legacy Field Note'), findsWidgets);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: ProjectDetailScreen(
              projectId: project.id,
              projectsController: projectsCtrl,
              notesController: notesCtrl,
              onOpenNote: openedNoteIds.add,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('NOTES (1)'), findsOneWidget);
        expect(find.text('Field Research — Note'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
