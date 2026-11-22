import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/projects/projects_controller.dart';
import 'package:personal_management_app/application/tasks/tasks_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/database_persistence_coordinator.dart';
import 'package:personal_management_app/data/repositories/projects_repository.dart';
import 'package:personal_management_app/data/repositories/tasks_repository.dart';
import 'package:personal_management_app/domain/projects/project_models.dart';
import 'package:personal_management_app/domain/tasks/task_models.dart';
import 'package:personal_management_app/domain/tasks/task_recurrence_engine.dart';
import 'package:personal_management_app/ui/screens/tasks_view.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  configureSqliteForHostTests();

  group('Stage 3 — Task Recurrence System (Flutter Domain, Controller, SQLite & UI)',
      () {
    Future<
        ({
          AppDatabase db,
          DriftTasksRepository tasksRepo,
          DriftProjectsRepository projectsRepo,
          TasksController tasksCtrl,
          ProjectsController projectsCtrl,
        })> createHarness() async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.ensureInitialized();
      addTearDown(db.close);

      final tasksRepo = DriftTasksRepository(db);
      final projectsRepo = DriftProjectsRepository(db);
      final tasksCtrl = TasksController(repository: tasksRepo);
      final projectsCtrl = ProjectsController(repository: projectsRepo);
      addTearDown(tasksCtrl.dispose);
      addTearDown(projectsCtrl.dispose);
      await tasksCtrl.loadAll();
      await projectsCtrl.loadAll();

      return (
        db: db,
        tasksRepo: tasksRepo,
        projectsRepo: projectsRepo,
        tasksCtrl: tasksCtrl,
        projectsCtrl: projectsCtrl,
      );
    }

    test(
      '1. Pure domain engine calculates daily, weekly ISO weekdays, every-N, monthly/yearly clamping, start/end dates & repeatFrom modes',
      () {
        expect(
          TaskRecurrenceEngine.computeNextRecurrenceDate(
            const CalendarDate(year: 2026, month: 11, day: 22),
            const TaskRecurrenceConfig(frequency: 'daily', interval: 3),
          ),
          const CalendarDate(year: 2026, month: 11, day: 25),
        );

        // Weekly Mon(1), Wed(3), Fri(5) every 2 weeks
        expect(
          TaskRecurrenceEngine.computeNextRecurrenceDate(
            const CalendarDate(year: 2026, month: 11, day: 23), // Mon
            const TaskRecurrenceConfig(
              frequency: 'weekly',
              interval: 2,
              weekdays: [1, 3, 5],
            ),
          ),
          const CalendarDate(year: 2026, month: 11, day: 25), // Wed same week
        );
        expect(
          TaskRecurrenceEngine.computeNextRecurrenceDate(
            const CalendarDate(year: 2026, month: 11, day: 27), // Fri
            const TaskRecurrenceConfig(
              frequency: 'weekly',
              interval: 2,
              weekdays: [1, 3, 5],
            ),
          ),
          const CalendarDate(year: 2026, month: 12, day: 7), // Mon + 2 weeks
        );

        // Monthly Jan 31 -> Feb 28 (2026) and Feb 29 (2024 leap)
        expect(
          TaskRecurrenceEngine.computeNextRecurrenceDate(
            const CalendarDate(year: 2026, month: 1, day: 31),
            const TaskRecurrenceConfig(frequency: 'monthly', interval: 1),
          ),
          const CalendarDate(year: 2026, month: 2, day: 28),
        );
        expect(
          TaskRecurrenceEngine.computeNextRecurrenceDate(
            const CalendarDate(year: 2024, month: 1, day: 31),
            const TaskRecurrenceConfig(frequency: 'monthly', interval: 1),
          ),
          const CalendarDate(year: 2024, month: 2, day: 29),
        );

        // Yearly leap clamping
        expect(
          TaskRecurrenceEngine.computeNextRecurrenceDate(
            const CalendarDate(year: 2024, month: 2, day: 29),
            const TaskRecurrenceConfig(frequency: 'yearly', interval: 1),
          ),
          const CalendarDate(year: 2025, month: 2, day: 28),
        );

        // Start date floor & end date cap
        expect(
          TaskRecurrenceEngine.computeNextRecurrenceDate(
            const CalendarDate(year: 2026, month: 11, day: 20),
            const TaskRecurrenceConfig(
              frequency: 'daily',
              interval: 1,
              startDate: CalendarDate(year: 2026, month: 11, day: 28),
            ),
          ),
          const CalendarDate(year: 2026, month: 11, day: 28),
        );
        expect(
          TaskRecurrenceEngine.computeNextRecurrenceDate(
            const CalendarDate(year: 2026, month: 11, day: 28),
            const TaskRecurrenceConfig(
              frequency: 'daily',
              interval: 2,
              endDate: CalendarDate(year: 2026, month: 11, day: 29),
            ),
          ),
          isNull,
        );

        // Validation catches endDate < startDate & interval < 1
        final invalid = TaskRecurrenceEngine.validateConfig(
          const TaskRecurrenceConfig(
            frequency: 'weekly',
            interval: 0,
            startDate: CalendarDate(year: 2026, month: 12, day: 10),
            endDate: CalendarDate(year: 2026, month: 12, day: 1),
          ),
        );
        expect(invalid.isValid, isFalse);
        expect(invalid.errors.containsKey('recurrenceInterval'), isTrue);
        expect(invalid.errors.containsKey('recurrenceEndDate'), isTrue);

        // repeatFrom completion_date uses Ethiopia UTC+3 civil date and preserves lead time
        final compTask = TaskEntity(
          id: 'comp-anchor',
          title: 'Water plants',
          scheduledDate: const CalendarDate(year: 2026, month: 11, day: 19),
          dueDate: const CalendarDate(year: 2026, month: 11, day: 20),
          recurrenceConfig: const TaskRecurrenceConfig(
            frequency: 'daily',
            interval: 3,
            repeatFrom: 'completion_date',
          ),
        );
        final nextDates = TaskRecurrenceEngine.computeNextOccurrenceDates(
          compTask,
          compTask.recurrenceConfig!,
          forCompletion: true,
          nowUtc: DateTime.utc(2026, 11, 22, 22, 0), // 2026-11-23 01:00 UTC+3
        );
        expect(nextDates?.dueDate, const CalendarDate(year: 2026, month: 11, day: 26));
        expect(
          nextDates?.scheduledDate,
          const CalendarDate(year: 2026, month: 11, day: 25),
        );
      },
    );

    test(
      '2. TasksController spawns next occurrence with reset subtasks, non-My-Day state, duplicate guard, skip, reschedule, stop, Undo & v10 SQLite roundtrip',
      () async {
        final h = await createHarness();
        final ctrl = h.tasksCtrl;

        final created = await ctrl.createTask(
          id: 'frec-1',
          title: 'Weekly tax summary',
          dueDate: const CalendarDate(year: 2026, month: 11, day: 22),
          scheduledDate: const CalendarDate(year: 2026, month: 11, day: 21),
          isMyDay: true,
          myDayDate: const CalendarDate(year: 2026, month: 11, day: 22),
          subtasks: const [
            TaskSubtask(id: 'frec-1-sub-1', title: 'Gather receipts', done: true),
            TaskSubtask(id: 'frec-1-sub-2', title: 'File PDF', done: true),
          ],
          recurrenceConfig: const TaskRecurrenceConfig(
            frequency: 'weekly',
            interval: 1,
            repeatFrom: 'due_date',
          ),
        );
        expect(created, isNotNull);

        // Complete -> spawns next occurrence
        final firstToggle = await ctrl.toggleTaskWithRecurrence(
          'frec-1',
          nowUtc: DateTime.utc(2026, 11, 22, 9, 0),
        );
        expect(firstToggle.updatedTask?.isCompleted, isTrue);
        expect(firstToggle.generatedNextTask, isNotNull);
        final spawned = firstToggle.generatedNextTask!;
        expect(spawned.isCompleted, isFalse);
        expect(spawned.dueDate, const CalendarDate(year: 2026, month: 11, day: 29));
        expect(
          spawned.scheduledDate,
          const CalendarDate(year: 2026, month: 11, day: 28),
        );
        expect(spawned.isMyDay, isFalse);
        expect(spawned.myDayDate, isNull);
        expect(spawned.subtasks.length, 2);
        expect(spawned.subtasks.every((s) => !s.done), isTrue);
        expect(ctrl.state.tasks.length, 2);

        // Reopening & completing frec-1 again does NOT create duplicate next occurrence
        await ctrl.toggleTaskWithRecurrence('frec-1');
        final duplicateAttempt = await ctrl.toggleTaskWithRecurrence('frec-1');
        expect(duplicateAttempt.generatedNextTask, isNull);
        expect(duplicateAttempt.duplicatePrevented, isTrue);
        expect(ctrl.state.tasks.length, 2);

        // Skip spawned occurrence -> advances another 7 days
        final skipped = await ctrl.skipRecurrenceOccurrence(spawned.id);
        expect(
          skipped?.dueDate,
          const CalendarDate(year: 2026, month: 12, day: 6),
        );
        expect(
          skipped?.scheduledDate,
          const CalendarDate(year: 2026, month: 12, day: 5),
        );

        // Reschedule spawned occurrence preserves lead time and config
        final rescheduled = await ctrl.rescheduleTaskOccurrence(
          spawned.id,
          const CalendarDate(year: 2026, month: 12, day: 10),
        );
        expect(
          rescheduled?.dueDate,
          const CalendarDate(year: 2026, month: 12, day: 10),
        );
        expect(
          rescheduled?.scheduledDate,
          const CalendarDate(year: 2026, month: 12, day: 9),
        );
        expect(rescheduled?.recurrenceConfig?.frequency, 'weekly');

        // Stop recurrence removes rule while preserving task & dates
        final stopped = await ctrl.stopTaskRecurrence(spawned.id);
        expect(stopped?.recurrenceConfig, isNull);
        expect(stopped?.recurrenceRule, isNull);
        expect(
          stopped?.dueDate,
          const CalendarDate(year: 2026, month: 12, day: 10),
        );

        // Undo completion deletes generated occurrence and restores previous snapshot
        await ctrl.undoGeneratedRecurrenceCompletion(
          previousTask: created!,
          generatedNextTaskId: spawned.id,
        );
        expect(ctrl.state.tasks.length, 1);
        expect(ctrl.state.findTaskById('frec-1')?.isCompleted, isFalse);

        // Persist across v10 snapshot export/restore
        final coordinator = DatabasePersistenceCoordinator(h.db);
        final exported = await coordinator.exportSnapshot();
        final targetDb = AppDatabase(NativeDatabase.memory());
        await targetDb.ensureInitialized();
        addTearDown(targetDb.close);
        final importReport = await DatabasePersistenceCoordinator(targetDb)
            .importSnapshotDetailed(exported);
        expect(importReport.diagnostics, isEmpty);
        final restoredTasks = await DriftTasksRepository(targetDb).getTasks();
        expect(restoredTasks.single.recurrenceConfig?.frequency, 'weekly');
      },
    );

    test(
      '3. Completing a recurring task inside a Project copies its Project Section link cleanly',
      () async {
        final h = await createHarness();
        final project = await h.projectsCtrl.createProject(
          id: 'proj-rec-1',
          title: 'Monthly Operations',
        );
        expect(project, isNotNull);
        final section = await h.projectsCtrl.createProjectSection(
          project!.id,
          'Finance Reviews',
        );
        expect(section, isNotNull);

        final task = await h.tasksCtrl.createTask(
          id: 'proj-rec-task-1',
          title: 'Reconcile ledger',
          projectId: project.id,
          dueDate: const CalendarDate(year: 2026, month: 11, day: 25),
          recurrenceConfig: const TaskRecurrenceConfig(
            frequency: 'monthly',
            interval: 1,
          ),
        );
        expect(task, isNotNull);
        await h.projectsCtrl.assignTaskToProjectSection(
          projectId: project.id,
          taskId: task!.id,
          taskTitle: task.title,
          taskCompleted: task.isCompleted,
          sectionRecordId: section!.id,
        );

        final toggleRes = await h.tasksCtrl.toggleTaskWithRecurrence(task.id);
        expect(toggleRes.generatedNextTask, isNotNull);
        await h.projectsCtrl.syncTaskSectionLink(
          project.id,
          toggleRes.updatedTask!,
        );
        await h.projectsCtrl.copyTaskSectionLink(
          project.id,
          task.id,
          toggleRes.generatedNextTask!,
        );

        final records =
            h.projectsCtrl.state.recordsByProject[project.id] ?? const [];
        final sectionLinks = records
            .where(
              (r) =>
                  r.recordType == ProjectRecordType.groupedItem &&
                  r.parentRecordId == section.id &&
                  r.linkedTaskId != null,
            )
            .map((r) => r.linkedTaskId!)
            .toSet();
        expect(sectionLinks.contains(task.id), isTrue);
        expect(
          sectionLinks.contains(toggleRes.generatedNextTask!.id),
          isTrue,
        );
      },
    );

    testWidgets(
      '4. TasksView renders recurrence summary & TaskRecurrenceDetailsSection controls (Skip, Reschedule, Edit, Stop)',
      (WidgetTester tester) async {
        final h = await createHarness();
        await h.tasksCtrl.createTask(
          id: 'ui-rec-1',
          title: 'Pay studio rent',
          dueDate: CalendarDate.today(),
          recurrenceConfig: const TaskRecurrenceConfig(
            frequency: 'monthly',
            interval: 1,
            repeatFrom: 'due_date',
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: TasksView(
              controller: h.tasksCtrl,
              projectsController: h.projectsCtrl,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Pay studio rent'), findsOneWidget);
        expect(find.text('Monthly'), findsOneWidget);

        // Open task details sheet
        await tester.tap(find.text('Pay studio rent'));
        await tester.pumpAndSettle();

        expect(find.text('Recurrence: Monthly'), findsOneWidget);
        expect(find.text('Skip Occurrence'), findsOneWidget);
        expect(find.text('Stop Recurrence'), findsOneWidget);

        // Skip occurrence from details sheet
        await tester.tap(find.text('Skip Occurrence'));
        await tester.pumpAndSettle();

        final afterSkip = h.tasksCtrl.state.findTaskById('ui-rec-1')!;
        expect(afterSkip.dueDate!.isAfter(CalendarDate.today()), isTrue);
      },
    );
  });
}
