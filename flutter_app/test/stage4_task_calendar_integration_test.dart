import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/calendar/calendar_controller.dart';
import 'package:personal_management_app/application/projects/projects_controller.dart';
import 'package:personal_management_app/application/tasks/tasks_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/calendar_repository.dart';
import 'package:personal_management_app/data/repositories/projects_repository.dart';
import 'package:personal_management_app/data/repositories/tasks_repository.dart';
import 'package:personal_management_app/domain/tasks/task_calendar_engine.dart';
import 'package:personal_management_app/domain/tasks/task_recurrence_engine.dart';
import 'package:personal_management_app/ui/screens/calendar_view.dart';
import 'package:personal_management_app/ui/screens/tasks_view.dart';
import 'package:personal_management_app/ui/widgets/shared_ui_widgets.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  configureSqliteForHostTests();

  group(
      'Stage 4 — Task and Calendar Integration (Flutter Domain, Controllers & UI)',
      () {
    Future<
        ({
          AppDatabase db,
          CalendarController calendarCtrl,
          TasksController tasksCtrl,
          ProjectsController projectsCtrl,
        })> createWidgetHarness(
      WidgetTester tester, {
      Future<void> Function(
        CalendarController calendarCtrl,
        TasksController tasksCtrl,
        ProjectsController projectsCtrl,
      )? seed,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));

      final fixture = await tester.runAsync(() async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();

        final calCtrl = CalendarController(
          repository: DriftCalendarRepository(db),
        );
        final tasksCtrl = TasksController(
          repository: DriftTasksRepository(db),
        );
        final projectsCtrl = ProjectsController(
          repository: DriftProjectsRepository(db),
        );

        await Future.wait([
          calCtrl.loadAll(),
          tasksCtrl.loadAll(),
          projectsCtrl.loadAll(),
        ]);

        if (seed != null) {
          await seed(calCtrl, tasksCtrl, projectsCtrl);
        }

        return (
          db: db,
          calendarCtrl: calCtrl,
          tasksCtrl: tasksCtrl,
          projectsCtrl: projectsCtrl,
        );
      });

      final harness = fixture!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 20));
        harness.calendarCtrl.dispose();
        harness.tasksCtrl.dispose();
        harness.projectsCtrl.dispose();
        var closed = false;
        final closeFuture = harness.db.close().whenComplete(() {
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

      return harness;
    }

    Future<void> pumpUntil(
      WidgetTester tester,
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

    test(
      '1. TaskCalendarEngine projects scheduled vs due dates cleanly, separates recurring previews, and prevents duplicate entries after completion',
      () {
        final splitTask = TaskEntity(
          id: 'split-1',
          title: 'Draft quarterly report',
          scheduledDate: CalendarDate(year: 2026, month: 11, day: 23),
          scheduledTime: '09:00',
          estimatedDurationMinutes: 60,
          dueDate: CalendarDate(year: 2026, month: 11, day: 25),
          priority: 'high',
        );
        final archivedTask = TaskEntity(
          id: 'arch-1',
          title: 'Old item',
          dueDate: CalendarDate(year: 2026, month: 11, day: 24),
          isArchived: true,
        );

        expect(
          TaskCalendarEngine.getTaskPrimaryCalendarDate(splitTask),
          CalendarDate(year: 2026, month: 11, day: 23),
        );

        final range = DateRange(
          start: CalendarDate(year: 2026, month: 11, day: 20),
          end: CalendarDate(year: 2026, month: 12, day: 15),
        );
        final splitOccurrences = TaskCalendarEngine.projectTasksForDateRange(
          [splitTask, archivedTask],
          range,
        );
        expect(splitOccurrences.length, 2);
        expect(splitOccurrences[0].kind, TaskCalendarOccurrenceKind.scheduled);
        expect(
          splitOccurrences[0].companionDueDate,
          CalendarDate(year: 2026, month: 11, day: 25),
        );
        expect(splitOccurrences[1].kind, TaskCalendarOccurrenceKind.due);
        expect(
          splitOccurrences[1].companionScheduledDate,
          CalendarDate(year: 2026, month: 11, day: 23),
        );

        // Recurring task completion preserves historical completed row and spawns next occurrence without duplicate preview
        final recurring = TaskEntity(
          id: 'rec-cal-f1',
          title: 'Weekly ledger backup',
          dueDate: CalendarDate(year: 2026, month: 11, day: 22),
          scheduledDate: CalendarDate(year: 2026, month: 11, day: 22),
          recurrenceConfig: TaskRecurrenceConfig(
            frequency: 'weekly',
            interval: 1,
            weekdays: const [7],
            endDate: CalendarDate(year: 2026, month: 12, day: 8),
            repeatFrom: 'due_date',
          ),
        );

        final before =
            TaskCalendarEngine.projectTasksForDateRange([recurring], range);
        expect(before.length, 3);
        expect(before[0].kind, TaskCalendarOccurrenceKind.dueAndScheduled);
        expect(before[1].kind, TaskCalendarOccurrenceKind.recurringPreview);
        expect(before[2].kind, TaskCalendarOccurrenceKind.recurringPreview);

        final completedAt = DateTime.utc(2026, 11, 22, 9, 0);
        final completionOutcome =
            TaskRecurrenceEngine.completeTaskWithRecurrence(
          [recurring],
          'rec-cal-f1',
          nowUtc: completedAt,
        );
        expect(completionOutcome.generatedNextTask, isNotNull);

        final after = TaskCalendarEngine.projectTasksForDateRange(
          completionOutcome.tasks,
          range,
        );
        expect(after.length, 3);
        expect(after[0].completed, isTrue);
        expect(after[0].isProjectedOccurrence, isFalse);
        expect(
          after[1].occurrenceDate,
          CalendarDate(year: 2026, month: 11, day: 29),
        );
        expect(after[1].isProjectedOccurrence, isFalse);
        expect(
          after[2].occurrenceDate,
          CalendarDate(year: 2026, month: 12, day: 6),
        );
        expect(after[2].isProjectedOccurrence, isTrue);
      },
    );

    testWidgets(
      '2. CalendarView integrates events with scheduled/due/recurring tasks, supports completion + recurrence Undo, opens Tasks, and persists event creation',
      (WidgetTester tester) async {
        final today = CalendarDate.today();
        TaskEntity? recurringTask;

        final h = await createWidgetHarness(
          tester,
          seed: (calCtrl, tasksCtrl, _) async {
            await calCtrl.createEvent(
              title: 'Clinic Checkup',
              dateIso: today.toIsoString(),
              startTime: '10:00',
              endTime: '11:00',
              category: 'health',
            );

            recurringTask = await tasksCtrl.createTask(
              id: 'cal-ui-task-1',
              title: 'Review weekly budget',
              dueDate: today,
              scheduledDate: today,
              scheduledTime: '15:00',
              estimatedDurationMinutes: 30,
              recurrenceConfig: const TaskRecurrenceConfig(
                frequency: 'daily',
                interval: 3,
                repeatFrom: 'due_date',
              ),
            );
          },
        );
        expect(recurringTask, isNotNull);

        String? openedTaskId;

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: CalendarView(
              calendarController: h.calendarCtrl,
              tasksController: h.tasksCtrl,
              projectsController: h.projectsCtrl,
              onOpenTask: (id) => openedTaskId = id,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Clinic Checkup'), findsOneWidget);
        expect(find.text('Review weekly budget'), findsOneWidget);
        expect(find.text('Scheduled & Due'), findsOneWidget);

        // Tapping the task card invokes onOpenTask for Task details navigation
        await tester.ensureVisible(find.text('Review weekly budget'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review weekly budget'));
        await tester.pump();
        expect(openedTaskId, 'cal-ui-task-1');

        // Tapping checkbox completes task and spawns next recurring occurrence
        await tester.ensureVisible(
          find.byTooltip('Complete Review weekly budget'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Complete Review weekly budget'));
        await pumpUntil(
          tester,
          () =>
              h.tasksCtrl.state.tasks.length == 2 &&
              find.text('Undo').evaluate().isNotEmpty,
          reason: 'Completing recurring task did not spawn next occurrence',
        );

        expect(h.tasksCtrl.state.tasks.length, 2);
        expect(
          h.tasksCtrl.state.findTaskById('cal-ui-task-1')?.isCompleted,
          isTrue,
        );
        expect(find.text('Undo'), findsOneWidget);

        // Undo restores single uncompleted task state cleanly
        await tester.tap(find.text('Undo'));
        await pumpUntil(
          tester,
          () => h.tasksCtrl.state.tasks.length == 1,
          reason: 'Undo did not restore single uncompleted task state',
        );
        expect(h.tasksCtrl.state.tasks.length, 1);
        expect(
          h.tasksCtrl.state.findTaskById('cal-ui-task-1')?.isCompleted,
          isFalse,
        );

        // Switch to Agenda view -> verifies upcoming recurrence preview appears
        await tester.ensureVisible(find.text('Agenda'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Agenda'));
        await tester.pumpAndSettle();
        expect(find.text('Upcoming Recurrence'), findsWidgets);

        // Add Event modal creates and persists a CalendarEventEntity
        await tester.tap(find.byTooltip('Add Event'));
        await tester.pumpAndSettle();
        final titleField = find.descendant(
          of: find.widgetWithText(DaywellTextField, 'Event Title *'),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(titleField, 'Team Planning');
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final submitButton = find.widgetWithText(FilledButton, 'Add Event');
        await tester.ensureVisible(submitButton);
        await tester.pumpAndSettle();
        await tester.tap(submitButton);
        await pumpUntil(
          tester,
          () =>
              h.calendarCtrl.state.events.any(
                (e) => e.title == 'Team Planning',
              ) &&
              find.byType(TextFormField).evaluate().isEmpty,
          reason: 'Add Event modal did not persist Team Planning',
        );

        expect(
          h.calendarCtrl.state.events.any((e) => e.title == 'Team Planning'),
          isTrue,
        );
      },
    );

    testWidgets(
      '3. TasksView supports requestedTaskFocus into Task details and View in Calendar navigation using primary task date',
      (WidgetTester tester) async {
        final scheduledDate = CalendarDate(year: 2026, month: 11, day: 24);
        final dueDate = CalendarDate(year: 2026, month: 11, day: 28);

        final h = await createWidgetHarness(
          tester,
          seed: (_, tasksCtrl, __) async {
            await tasksCtrl.createTask(
              id: 'focus-task-1',
              title: 'Submit tax filing',
              scheduledDate: scheduledDate,
              dueDate: dueDate,
            );
          },
        );

        CalendarDate? jumpedDate;

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: TasksView(
              controller: h.tasksCtrl,
              projectsController: h.projectsCtrl,
              requestedTaskFocus: (taskId: 'focus-task-1', nonce: 1),
              onOpenCalendarDate: (date) => jumpedDate = date,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Task Details opened automatically via requestedTaskFocus
        expect(find.text('Submit tax filing'), findsWidgets);
        expect(find.text('View in Calendar'), findsOneWidget);

        await tester.ensureVisible(find.text('View in Calendar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('View in Calendar'));
        await tester.pumpAndSettle();

        expect(jumpedDate, scheduledDate);
      },
    );
  });
}
