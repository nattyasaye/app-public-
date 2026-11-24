import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/application/tasks/tasks_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/interfaces/platform_service_interfaces.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/database_persistence_coordinator.dart';
import 'package:personal_management_app/data/repositories/notes_repository.dart';
import 'package:personal_management_app/data/repositories/tasks_repository.dart';
import 'package:personal_management_app/domain/notes/task_notes_helpers.dart';
import 'package:personal_management_app/services/backup/encryption_backup_service.dart';
import 'package:personal_management_app/ui/screens/notes_view.dart';
import 'package:personal_management_app/ui/screens/tasks_view.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  setUpAll(configureSqliteForHostTests);

  group(
      'Stage 8 — Flutter Task–Notes Integration (Persistence, Lifecycle, Backup & UI)',
      () {
    test(
      '1. Persists linkedModule/linkedId across DriftNotesRepository & NotesController, clamps task-created titles <= 250 chars, and preserves note on unlink',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final tasksRepo = DriftTasksRepository(db);
        final notesRepo = DriftNotesRepository(db);
        final longTitle = 'T' * 290;
        final task = await tasksRepo.createTask(
          TaskEntity(
            id: 'task-s8-1',
            title: longTitle,
            description: 'Inspect solar inverter logs before evening',
          ),
        );
        final otherTask = await tasksRepo.createTask(
          TaskEntity(
            id: 'task-s8-2',
            title: 'Order filters',
          ),
        );

        final notesCtrl = NotesController(repository: notesRepo);
        addTearDown(notesCtrl.dispose);

        final existing = await notesCtrl.createNote(
          id: 'note-existing',
          title: 'Wiring notes',
          content: 'Diagram v2',
          tags: const ['electrical'],
        );
        final archivedNote = await notesRepo.createNote(
          NoteEntity(
            id: 'note-archived',
            title: 'Archived reference',
            content: 'Historical meter log',
            isArchived: true,
          ),
        );
        await notesCtrl.loadNotes();

        // Create new note from task via domain helper
        final createdFromTask = await notesCtrl.createNote(
          id: 'note-from-task',
          title: TaskNotesHelper.buildDefaultTaskNoteTitle(task),
          content: TaskNotesHelper.buildDefaultTaskNoteBody(task),
          linkedModule: NoteEntity.taskLinkModule,
          linkedId: task.id,
        );
        expect(createdFromTask.title.length, NoteEntity.maxTitleLength);
        expect(createdFromTask.linkedModule, 'tasks');
        expect(createdFromTask.linkedId, task.id);

        // Link existing active & archived notes via generic controller action
        await notesCtrl.linkNoteToEntity(
          existing.id,
          module: NoteEntity.taskLinkModule,
          entityId: task.id,
        );
        await notesCtrl.linkNoteToEntity(
          archivedNote.id,
          module: NoteEntity.taskLinkModule,
          entityId: task.id,
        );

        final linkedForTask = await notesRepo.getNotesByLink(
          linkedModule: NoteEntity.taskLinkModule,
          linkedId: task.id,
        );
        expect(
          linkedForTask.map((n) => n.id).toSet(),
          equals({'note-from-task', 'note-existing', 'note-archived'}),
        );

        // Reassign existing note to otherTask, then verify counts
        await notesCtrl.linkNoteToEntity(
          existing.id,
          module: NoteEntity.taskLinkModule,
          entityId: otherTask.id,
        );
        expect(
          TaskNotesHelper.countNotesForTask(notesCtrl.state.notes, task.id),
          2,
        );
        expect(
          TaskNotesHelper.countNotesForTask(
              notesCtrl.state.notes, otherTask.id),
          1,
        );

        // Unlink preserves note metadata cleanly
        final unlinked = await notesCtrl.unlinkNote(existing.id);
        expect(unlinked?.linkedModule, isNull);
        expect(unlinked?.linkedId, isNull);
        expect(unlinked?.content, 'Diagram v2');
        expect(unlinked?.tags, ['electrical']);
        expect((await notesRepo.getNoteById(existing.id))?.linkedId, isNull);
      },
    );

    test(
      '2. Safe lifecycle: archiving retains links; deleting task clears links safely without deleting notes; deleting note leaves task intact',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final tasksRepo = DriftTasksRepository(db);
        final notesRepo = DriftNotesRepository(db);
        late final NotesController notesCtrl;
        final tasksCtrl = TasksController(
          repository: tasksRepo,
          onTaskDeleted: (taskId) => notesCtrl.clearLinksForTarget(
            module: NoteEntity.taskLinkModule,
            targetId: taskId,
          ),
        );
        notesCtrl = NotesController(repository: notesRepo);
        addTearDown(() {
          tasksCtrl.dispose();
          notesCtrl.dispose();
        });

        await tasksCtrl.createTask(
          id: 'task-life-1',
          title: 'Archive then delete',
          dueDate: CalendarDate(year: 2026, month: 11, day: 25),
        );
        await notesCtrl.createNote(
          id: 'note-life-1',
          title: 'Linked Active Note',
          content: 'Keep forever',
          linkedModule: NoteEntity.taskLinkModule,
          linkedId: 'task-life-1',
        );
        await notesCtrl.createNote(
          id: 'note-life-2',
          title: 'Second Linked Note',
          content: 'Delete this note only',
          linkedModule: NoteEntity.taskLinkModule,
          linkedId: 'task-life-1',
        );

        // Archiving retains note link
        await tasksCtrl.archiveTask('task-life-1');
        expect(
          TaskNotesHelper.countNotesForTask(
              notesCtrl.state.notes, 'task-life-1'),
          2,
        );

        // Deleting one note does not damage task
        await notesCtrl.permanentlyDeleteNote('note-life-2');
        expect(await tasksRepo.getTaskById('task-life-1'), isNotNull);

        // Deleting task safely clears note links without deleting note-life-1
        await tasksCtrl.deleteTask('task-life-1');
        expect(await tasksRepo.getTaskById('task-life-1'), isNull);
        final survivingNote = await notesRepo.getNoteById('note-life-1');
        expect(survivingNote, isNotNull);
        expect(survivingNote!.content, 'Keep forever');
        expect(survivingNote.linkedModule, isNull);
        expect(survivingNote.linkedId, isNull);
        expect(notesCtrl.state.findById('note-life-1')?.linkedId, isNull);
      },
    );

    test(
      '3. Backup/restore round-trips Task–Notes links across .daywell, sanitizes orphaned links with diagnostics, keeps v10 compat, and rejects v12 fail-closed',
      () async {
        final sourceDb = AppDatabase(NativeDatabase.memory());
        await sourceDb.ensureInitialized();
        addTearDown(sourceDb.close);

        await DriftTasksRepository(sourceDb).createTask(
          TaskEntity(id: 'task-bk-1', title: 'Solar maintenance'),
        );
        await DriftNotesRepository(sourceDb).createNote(
          NoteEntity(
            id: 'note-bk-1',
            title: 'Panel spec',
            content: '450W monocrystalline',
            linkedModule: NoteEntity.taskLinkModule,
            linkedId: 'task-bk-1',
          ),
        );

        final coordinator = DatabasePersistenceCoordinator(sourceDb);
        final exported = await coordinator.exportSnapshot();
        expect(exported['databaseSchemaVersion'], 12);
        final exportedNote =
            (exported['notes'] as List).single as Map<String, dynamic>;
        expect(exportedNote['linkedModule'], 'tasks');
        expect(exportedNote['linkedId'], 'task-bk-1');

        final encService = EncryptionBackupService();
        final envelope = await encService.encryptDatabasePayload(
          rawDatabaseJson: jsonEncode(exported),
          passphrase: 'Stage8StrongPass!99',
          schemaVersion: exported['schemaVersion'] as int,
        );
        final decrypted = jsonDecode(
          await encService.decryptDatabasePayload(
            encryptedEnvelopeJson: envelope,
            passphrase: 'Stage8StrongPass!99',
          ),
        ) as Map<String, dynamic>;

        final targetDb = AppDatabase(NativeDatabase.memory());
        await targetDb.ensureInitialized();
        addTearDown(targetDb.close);

        final report = await DatabasePersistenceCoordinator(targetDb)
            .importSnapshotDetailed(decrypted);
        expect(report.diagnostics, isEmpty);
        final restoredNote =
            await DriftNotesRepository(targetDb).getNoteById('note-bk-1');
        expect(restoredNote?.linkedModule, 'tasks');
        expect(restoredNote?.linkedId, 'task-bk-1');

        // Orphaned task link in snapshot is cleared cleanly with diagnostic without deleting note
        final orphanSnap = Map<String, dynamic>.from(exported)
          ..['tasks'] = const <Map<String, dynamic>>[];
        final orphanReport = await DatabasePersistenceCoordinator(targetDb)
            .importSnapshotDetailed(orphanSnap);
        expect(
          orphanReport.diagnostics
              .any((d) => d.code == 'ORPHANED_NOTE_TASK_CLEARED'),
          isTrue,
        );
        final sanitizedNote =
            await DriftNotesRepository(targetDb).getNoteById('note-bk-1');
        expect(sanitizedNote, isNotNull);
        expect(sanitizedNote!.linkedModule, isNull);
        expect(sanitizedNote.linkedId, isNull);

        // Backward compatible pre-v11 snapshot without linkedModule/linkedId imports cleanly
        final v10CompatSnap = <String, dynamic>{
          'schemaVersion': 5,
          'snapshotFormatVersion': 2,
          'databaseSchemaVersion': 10,
          'accounts': const [],
          'transactions': const [],
          'notes': [
            {
              'id': 'note-legacy-v10',
              'title': 'Legacy v10 Note',
              'content': 'No link columns in v10',
              'createdAt': '2026-11-10T08:00:00.000Z',
              'updatedAt': '2026-11-10T08:00:00.000Z',
            },
          ],
        };
        final compatReport = await DatabasePersistenceCoordinator(targetDb)
            .importSnapshotDetailed(v10CompatSnap);
        expect(compatReport.restoredRecordCounts['notes'], 1);
        final v10Note =
            await DriftNotesRepository(targetDb).getNoteById('note-legacy-v10');
        expect(v10Note?.linkedModule, isNull);
        expect(v10Note?.linkedId, isNull);

        // Future v13 snapshot fails closed
        expect(
          () => DatabasePersistenceCoordinator.validateAndPrepareSnapshot({
            'schemaVersion': 5,
            'snapshotFormatVersion': 2,
            'databaseSchemaVersion': 13,
            'accounts': const [],
            'transactions': const [],
          }),
          throwsA(
            isA<BackupValidationException>().having(
              (e) => e.kind,
              'kind',
              BackupFailureKind.unsupportedFutureSchema,
            ),
          ),
        );
      },
    );

    testWidgets(
      '4. TasksView & NotesView UI workflows support creating/linking/opening/unlinking notes and bidirectional navigation',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 1400));

        final fixture = await tester.runAsync(() async {
          final db = AppDatabase(NativeDatabase.memory());
          await db.ensureInitialized();
          final tasksCtrl =
              TasksController(repository: DriftTasksRepository(db));
          final notesCtrl =
              NotesController(repository: DriftNotesRepository(db));
          await tasksCtrl.loadAll();
          await notesCtrl.loadNotes();

          await tasksCtrl.createTask(
            id: 'task-ui-1',
            title: 'Inspect Pump',
            description: 'Check pressure gauge',
          );
          await notesCtrl.createNote(
            id: 'note-ui-existing',
            title: 'Existing Pump Log',
            content: 'Baseline reading 2.4 bar',
          );
          await notesCtrl.createNote(
            id: 'note-ui-dangling',
            title: 'Dangling Note',
            content: 'Target removed externally',
            linkedModule: NoteEntity.taskLinkModule,
            linkedId: 'missing-task-id',
          );
          tasksCtrl.setViewFilter('all');
          return (db: db, tasksCtrl: tasksCtrl, notesCtrl: notesCtrl);
        });

        final db = fixture!.db;
        final tasksCtrl = fixture.tasksCtrl;
        final notesCtrl = fixture.notesCtrl;

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 20));
          tasksCtrl.dispose();
          notesCtrl.dispose();
          var closed = false;
          final closeFuture = db.close().whenComplete(() {
            closed = true;
          });
          final closeWatch = Stopwatch()..start();
          while (!closed && closeWatch.elapsed < const Duration(seconds: 10)) {
            await tester.pump(const Duration(milliseconds: 20));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
          }
          if (closed) {
            await closeFuture;
          } else {
            await tester.runAsync(
              () => closeFuture.timeout(const Duration(seconds: 5)),
            );
          }
          await tester.binding.setSurfaceSize(null);
        });

        Future<void> pumpUntil(
          bool Function() condition, {
          required String reason,
        }) async {
          final watch = Stopwatch()..start();
          while (!condition()) {
            if (watch.elapsed > const Duration(seconds: 10)) {
              fail(reason);
            }
            await tester.pump(const Duration(milliseconds: 20));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
          }
          await tester.pumpAndSettle();
        }

        String? openedNoteId;
        String? openedTaskId;

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: TasksView(
              controller: tasksCtrl,
              notesController: notesCtrl,
              onOpenNote: (id) => openedNoteId = id,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap task row to open Task Details sheet
        await tester.tap(find.text('Inspect Pump'));
        await tester.pumpAndSettle();

        expect(find.text('Linked Notes (0)'), findsOneWidget);
        expect(find.text('Link Existing'), findsOneWidget);
        expect(find.text('New Note'), findsOneWidget);

        // Link existing note from sheet
        await tester.ensureVisible(find.text('Link Existing'));
        await tester.tap(find.text('Link Existing'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Existing Pump Log'));
        await pumpUntil(
          () =>
              notesCtrl.state.findById('note-ui-existing')?.linkedId ==
                  'task-ui-1' &&
              find.text('Linked Notes (1)').evaluate().isNotEmpty,
          reason: 'Linking existing note did not persist.',
        );

        expect(find.text('Linked Notes (1)'), findsOneWidget);
        expect(find.text('Existing Pump Log'), findsWidgets);

        // Create new note from Task Details
        await tester.ensureVisible(find.text('New Note'));
        await tester.tap(find.text('New Note'));
        await pumpUntil(
          () =>
              openedNoteId != null &&
              notesCtrl.state.findById(openedNoteId!) != null,
          reason: 'New Note did not persist and invoke onOpenNote.',
        );
        expect(openedNoteId, isNotNull);
        final createdFromUi = notesCtrl.state.findById(openedNoteId!);
        expect(createdFromUi, isNotNull);
        expect(createdFromUi!.linkedModule, 'tasks');
        expect(createdFromUi.linkedId, 'task-ui-1');

        // Render NotesView with requestedNoteFocus -> opens Notes editor showing Linked Task bar & Open button
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: NotesView(
              controller: notesCtrl,
              tasksController: tasksCtrl,
              requestedNoteFocus: (noteId: 'note-ui-existing', nonce: 1),
              onOpenTask: (taskId) => openedTaskId = taskId,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Dangling task badge shows safe fallback on card when editor closes or behind route
        expect(find.text('Linked Task: Inspect Pump'), findsOneWidget);
        expect(find.text('Open'), findsOneWidget);

        await tester.tap(find.text('Open'));
        await pumpUntil(
          () =>
              openedTaskId == 'task-ui-1' &&
              find.text('Linked task unavailable').evaluate().isNotEmpty,
          reason: 'Open button did not save note, pop editor, and open task.',
        );
        expect(openedTaskId, 'task-ui-1');

        // Card view shows linked task badge and safe dangling fallback
        expect(find.text('Task: Inspect Pump'), findsWidgets);
        expect(find.text('Linked task unavailable'), findsOneWidget);
      },
    );
  });
}
