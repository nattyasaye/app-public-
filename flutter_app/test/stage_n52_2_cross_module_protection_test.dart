import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/calendar/calendar_controller.dart';
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/application/projects/projects_controller.dart';
import 'package:personal_management_app/application/tasks/tasks_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/calendar_repository.dart';
import 'package:personal_management_app/data/repositories/notes_repository.dart';
import 'package:personal_management_app/data/repositories/projects_repository.dart';
import 'package:personal_management_app/data/repositories/tasks_repository.dart';
import 'package:personal_management_app/ui/screens/calendar_view.dart';
import 'package:personal_management_app/ui/screens/notes_view.dart';
import 'package:personal_management_app/ui/screens/tasks_view.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage N5.2.2 — Cross-Module Note Relationship Protection', () {
    test(
      '1. NotesController blocks silent cross-module & Calendar link overwrites by default while keeping Stage 8 Task->Task reassignment and strict allowReassign=false',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final nowUtc = DateTime.utc(2026, 3, 20);
        await db.into(db.goals).insert(
              GoalsCompanion.insert(
                id: 'goal-1',
                title: 'Governance Goal',
                createdAt: nowUtc,
              ),
            );
        await db.into(db.projects).insert(
              ProjectsCompanion.insert(
                id: 'proj-gov',
                title: 'Governance Project',
                createdAt: nowUtc,
              ),
            );

        final notesCtrl = NotesController(repository: DriftNotesRepository(db));
        addTearDown(notesCtrl.dispose);

        final calNote = await notesCtrl.createNote(
          id: 'n-cal-protected',
          title: 'Board Agenda',
          content: 'Check [[Q2 Forecast]]',
          category: 'work_projects',
          projectId: 'proj-gov',
          goalId: 'goal-1',
          tags: const ['board'],
          isPinned: true,
          isFavorite: true,
          linkedModule: NoteEntity.calendarLinkModule,
          linkedId: 'evt-board',
        );

        // Omitting allowReassign blocks Calendar -> Task silent overwrite
        final blockedDefault = await notesCtrl.linkNoteToEntity(
          calNote.id,
          module: NoteEntity.taskLinkModule,
          entityId: 'task-1',
        );
        expect(blockedDefault, isNull);
        expect(
          notesCtrl.state.findById(calNote.id)?.linkedModule,
          NoteEntity.calendarLinkModule,
        );
        expect(
          notesCtrl.state.findById(calNote.id)?.linkedId,
          'evt-board',
        );

        // Omitting allowReassign blocks Calendar -> Calendar silent overwrite
        final blockedCalToCal = await notesCtrl.linkNoteToEntity(
          calNote.id,
          module: NoteEntity.calendarLinkModule,
          entityId: 'evt-other',
        );
        expect(blockedCalToCal, isNull);

        // Omitting allowReassign blocks Task -> Calendar silent overwrite
        final taskNote = await notesCtrl.createNote(
          id: 'n-task-existing',
          title: 'Task Checklist',
          content: '',
          linkedModule: NoteEntity.taskLinkModule,
          linkedId: 'task-a',
        );
        final blockedTaskToCal = await notesCtrl.linkNoteToEntity(
          taskNote.id,
          module: NoteEntity.calendarLinkModule,
          entityId: 'evt-board',
        );
        expect(blockedTaskToCal, isNull);

        // Stage 8 compatibility: Task -> Task without allowReassign still reassigns
        final taskToTask = await notesCtrl.linkNoteToEntity(
          taskNote.id,
          module: NoteEntity.taskLinkModule,
          entityId: 'task-b',
        );
        expect(taskToTask?.linkedModule, NoteEntity.taskLinkModule);
        expect(taskToTask?.linkedId, 'task-b');

        // allowReassign: false strictly blocks even Task -> Task
        final strictBlocked = await notesCtrl.linkNoteToEntity(
          taskNote.id,
          module: NoteEntity.taskLinkModule,
          entityId: 'task-c',
          allowReassign: false,
        );
        expect(strictBlocked, isNull);
        expect(notesCtrl.state.findById(taskNote.id)?.linkedId, 'task-b');

        // Confirmed replacement changes only primary link and keeps metadata & projectId
        final confirmed = await notesCtrl.linkNoteToEntity(
          calNote.id,
          module: NoteEntity.taskLinkModule,
          entityId: 'task-1',
          allowReassign: true,
        );
        expect(confirmed?.linkedModule, NoteEntity.taskLinkModule);
        expect(confirmed?.linkedId, 'task-1');
        expect(confirmed?.projectId, 'proj-gov');
        expect(confirmed?.goalId, 'goal-1');
        expect(confirmed?.category, 'work_projects');
        expect(confirmed?.tags, const ['board']);
        expect(confirmed?.isPinned, isTrue);
        expect(confirmed?.isFavorite, isTrue);
        expect(confirmed?.content, 'Check [[Q2 Forecast]]');
      },
    );

    testWidgets(
      '2. TasksView shows Calendar event title & missing-event warning, confirms replacement, cancels safely, preserves metadata, and links non-conflicting notes without confirmation',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final calendarRepo = DriftCalendarRepository(db);
        final calendarCtrl = CalendarController(repository: calendarRepo);
        final tasksCtrl = TasksController(repository: DriftTasksRepository(db));
        final projectsCtrl =
            ProjectsController(repository: DriftProjectsRepository(db));
        final notesCtrl = NotesController(repository: DriftNotesRepository(db));
        addTearDown(() {
          calendarCtrl.dispose();
          tasksCtrl.dispose();
          projectsCtrl.dispose();
          notesCtrl.dispose();
        });

        await calendarRepo.createEvent(
          CalendarEventEntity(
            id: 'evt-review-1',
            title: 'Architecture Review',
            dateIso: '2026-03-20',
          ),
        );
        await tasksCtrl.createTask(
          id: 'task-primary',
          title: 'Finalize Spec',
        );
        await tasksCtrl.createTask(
          id: 'task-other',
          title: 'Other Task',
        );
        await db.into(db.projects).insert(
              ProjectsCompanion.insert(
                id: 'proj-core',
                title: 'Core Architecture',
                createdAt: DateTime.utc(2026, 3, 20),
              ),
            );
        await notesCtrl.createNote(
          id: 'note-cal-live',
          title: 'Review Talking Points',
          content: 'Verify constraints',
          projectId: 'proj-core',
          tags: const ['arch'],
          linkedModule: NoteEntity.calendarLinkModule,
          linkedId: 'evt-review-1',
        );
        await notesCtrl.createNote(
          id: 'note-cal-missing',
          title: 'Orphan Event Note',
          content: '',
          linkedModule: NoteEntity.calendarLinkModule,
          linkedId: 'evt-missing-999',
        );
        await notesCtrl.createNote(
          id: 'note-task-other',
          title: 'Other Task Note',
          content: '',
          linkedModule: NoteEntity.taskLinkModule,
          linkedId: 'task-other',
        );
        await calendarCtrl.loadAll();
        await tasksCtrl.loadAll();
        await projectsCtrl.loadAll();
        await notesCtrl.loadNotes();

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: TasksView(
              controller: tasksCtrl,
              projectsController: projectsCtrl,
              notesController: notesCtrl,
              calendarController: calendarCtrl,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open Task Details for Finalize Spec -> open Link Existing sheet
        await tester.tap(find.text('Finalize Spec').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Link Existing'));
        await tester.pumpAndSettle();

        expect(
          find.text('Currently linked to Calendar event "Architecture Review"'),
          findsOneWidget,
        );
        expect(find.text('Linked event unavailable'), findsOneWidget);
        expect(
          find.text('Linked to "Other Task" (tap reassigns)'),
          findsOneWidget,
        );

        // Tap Calendar-linked note -> Confirmation Dialog appears; Cancel preserves Calendar link
        await tester.tap(find.text('Review Talking Points'));
        await tester.pumpAndSettle();
        expect(find.text('Replace existing link?'), findsOneWidget);
        expect(
          find.textContaining('Calendar event "Architecture Review"'),
          findsAtLeastNWidgets(1),
        );

        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        expect(
          notesCtrl.state.findById('note-cal-live')?.linkedModule,
          NoteEntity.calendarLinkModule,
        );
        expect(
          notesCtrl.state.findById('note-cal-live')?.linkedId,
          'evt-review-1',
        );

        // Tap missing-event Calendar note -> Confirmation Dialog shows unavailable-event warning; Cancel preserves
        await tester.tap(find.text('Orphan Event Note'));
        await tester.pumpAndSettle();
        expect(find.text('Replace existing link?'), findsOneWidget);
        expect(
          find.textContaining('an unavailable Calendar event'),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        expect(
          notesCtrl.state.findById('note-cal-missing')?.linkedId,
          'evt-missing-999',
        );

        // Tap Review Talking Points and confirm replacement -> switches to task-primary keeping projectId/tags/content
        await tester.tap(find.text('Review Talking Points'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Replace link'));
        await tester.pumpAndSettle();

        final replaced = notesCtrl.state.findById('note-cal-live')!;
        expect(replaced.linkedModule, NoteEntity.taskLinkModule);
        expect(replaced.linkedId, 'task-primary');
        expect(replaced.projectId, 'proj-core');
        expect(replaced.tags, const ['arch']);
        expect(replaced.content, 'Verify constraints');

        // Re-open Link Existing and tap existing Task->Task candidate -> links immediately WITHOUT confirmation dialog
        await tester.tap(find.text('Link Existing'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Other Task Note'));
        await tester.pumpAndSettle();

        expect(find.text('Replace existing link?'), findsNothing);
        expect(
          notesCtrl.state.findById('note-task-other')?.linkedId,
          'task-primary',
        );
      },
    );

    testWidgets(
      '3. TasksView Unlink Undo never overwrites a newer Calendar link applied before tapping Undo',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final calendarRepo = DriftCalendarRepository(db);
        final calendarCtrl = CalendarController(repository: calendarRepo);
        final tasksCtrl = TasksController(repository: DriftTasksRepository(db));
        final projectsCtrl =
            ProjectsController(repository: DriftProjectsRepository(db));
        final notesCtrl = NotesController(repository: DriftNotesRepository(db));
        addTearDown(() {
          calendarCtrl.dispose();
          tasksCtrl.dispose();
          projectsCtrl.dispose();
          notesCtrl.dispose();
        });

        await calendarRepo.createEvent(
          CalendarEventEntity(
            id: 'evt-undo-guard',
            title: 'Sprint Demo',
            dateIso: '2026-03-21',
          ),
        );
        await tasksCtrl.createTask(
          id: 'task-undo-1',
          title: 'Write Demo Script',
        );
        await notesCtrl.createNote(
          id: 'note-undo-1',
          title: 'Demo Outline',
          content: '',
          linkedModule: NoteEntity.taskLinkModule,
          linkedId: 'task-undo-1',
        );
        await calendarCtrl.loadAll();
        await tasksCtrl.loadAll();
        await projectsCtrl.loadAll();
        await notesCtrl.loadNotes();

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: TasksView(
              controller: tasksCtrl,
              projectsController: projectsCtrl,
              notesController: notesCtrl,
              calendarController: calendarCtrl,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Write Demo Script').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Unlink Note'));
        await tester.pumpAndSettle();

        expect(notesCtrl.state.findById('note-undo-1')?.linkedModule, isNull);

        // Before tapping Undo, note is linked to Calendar event
        await notesCtrl.linkNoteToEntity(
          'note-undo-1',
          module: NoteEntity.calendarLinkModule,
          entityId: 'evt-undo-guard',
        );

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();

        // Newer Calendar link MUST stay intact
        final afterUndo = notesCtrl.state.findById('note-undo-1')!;
        expect(afterUndo.linkedModule, NoteEntity.calendarLinkModule);
        expect(afterUndo.linkedId, 'evt-undo-guard');
        expect(
          find.text('Could not undo: note relationship changed.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '4. CalendarView Unlink Undo never overwrites a newer Task link applied before tapping Undo',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final calendarRepo = DriftCalendarRepository(db);
        final calendarCtrl = CalendarController(repository: calendarRepo);
        final tasksCtrl = TasksController(repository: DriftTasksRepository(db));
        final notesCtrl = NotesController(repository: DriftNotesRepository(db));
        addTearDown(() {
          calendarCtrl.dispose();
          tasksCtrl.dispose();
          notesCtrl.dispose();
        });

        final targetDate = CalendarDate(year: 2026, month: 3, day: 25);
        calendarCtrl.setSelectedCalendarDate(targetDate);
        await calendarRepo.createEvent(
          CalendarEventEntity(
            id: 'evt-cal-undo',
            title: 'Design Critique',
            dateIso: targetDate.toIsoString(),
          ),
        );
        await tasksCtrl.createTask(id: 'task-takeover', title: 'Apply Edits');
        await notesCtrl.createNote(
          id: 'note-cal-undo',
          title: 'Critique Feedback',
          content: '',
          linkedModule: NoteEntity.calendarLinkModule,
          linkedId: 'evt-cal-undo',
        );
        await calendarCtrl.loadAll();
        await tasksCtrl.loadAll();
        await notesCtrl.loadNotes();

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: CalendarView(
              calendarController: calendarCtrl,
              tasksController: tasksCtrl,
              notesController: notesCtrl,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Design Critique').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Unlink Critique Feedback'));
        await tester.pumpAndSettle();

        // Relink to Task before Undo
        await notesCtrl.linkNoteToEntity(
          'note-cal-undo',
          module: NoteEntity.taskLinkModule,
          entityId: 'task-takeover',
        );

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();

        final afterUndo = notesCtrl.state.findById('note-cal-undo')!;
        expect(afterUndo.linkedModule, NoteEntity.taskLinkModule);
        expect(afterUndo.linkedId, 'task-takeover');
        expect(
          find.text('Could not undo: note relationship changed.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '5. NotesView confirms cross-module event switch when changing event and blocks Undo when target event is gone',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final calendarRepo = DriftCalendarRepository(db);
        final calendarCtrl = CalendarController(repository: calendarRepo);
        final tasksCtrl = TasksController(repository: DriftTasksRepository(db));
        final projectsCtrl =
            ProjectsController(repository: DriftProjectsRepository(db));
        final notesCtrl = NotesController(repository: DriftNotesRepository(db));
        addTearDown(() {
          calendarCtrl.dispose();
          tasksCtrl.dispose();
          projectsCtrl.dispose();
          notesCtrl.dispose();
        });

        await calendarRepo.createEvent(
          CalendarEventEntity(
            id: 'evt-one',
            title: 'First Meeting',
            dateIso: '2026-03-26',
          ),
        );
        await calendarRepo.createEvent(
          CalendarEventEntity(
            id: 'evt-two',
            title: 'Second Meeting',
            dateIso: '2026-03-27',
          ),
        );
        await notesCtrl.createNote(
          id: 'note-editor-1',
          title: 'Meeting Brief',
          content: '',
          linkedModule: NoteEntity.calendarLinkModule,
          linkedId: 'evt-one',
        );
        await calendarCtrl.loadAll();
        await tasksCtrl.loadAll();
        await projectsCtrl.loadAll();
        await notesCtrl.loadNotes();

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: NotesView(
              controller: notesCtrl,
              tasksController: tasksCtrl,
              projectsController: projectsCtrl,
              calendarController: calendarCtrl,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Meeting Brief').first);
        await tester.pumpAndSettle();

        // Change Linked Event -> asks confirmation; Cancel keeps First Meeting
        await tester.tap(find.byTooltip('Change Linked Event'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Second Meeting'));
        await tester.pumpAndSettle();
        expect(find.text('Replace existing link?'), findsOneWidget);
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        expect(
          notesCtrl.state.findById('note-editor-1')?.linkedId,
          'evt-one',
        );

        // Unlink event, delete First Meeting, then tap Undo -> blocked safely
        await tester.tap(find.byTooltip('Unlink Event'));
        await tester.pumpAndSettle();
        await calendarCtrl.deleteEvent('evt-one');
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();

        expect(notesCtrl.state.findById('note-editor-1')?.linkedId, isNull);
        expect(
          find.text('Could not undo: linked event is no longer available.'),
          findsOneWidget,
        );
      },
    );
  });
}
