import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/tasks/tasks_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/tasks_repository.dart';
import 'package:personal_management_app/domain/tasks/task_models.dart';
import 'package:personal_management_app/ui/screens/tasks_view.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  configureSqliteForHostTests();

  group('Stage 1.2 — Subtasks & Checklists (Flutter Domain, Persistence & UI)',
      () {
    Future<({AppDatabase db, DriftTasksRepository repo, TasksController ctrl})>
        createHarness() async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.ensureInitialized();
      addTearDown(db.close);
      final repo = DriftTasksRepository(db);
      final ctrl = TasksController(repository: repo);
      return (db: db, repo: repo, ctrl: ctrl);
    }

    test(
      '1–7. Domain progress calculation, controller subtask CRUD/reorder/restore, and Drift SQLite persistence roundtrip preserve parent metadata',
      () async {
        final harness = await createHarness();
        final ctrl = harness.ctrl;
        final today = CalendarDate.today();

        // Create parent task with zero subtasks and verify 0% computed progress
        final created = await ctrl.createTask(
          id: 's12-task-1',
          title: 'Monthly office prep',
          priority: 'high',
          status: 'in_progress',
          scheduledDate: today,
          dueDate: today,
          labels: const ['ops'],
          isPinned: true,
          sortOrder: 7,
        );
        expect(created, isNotNull);
        expect(created!.completedSubtaskCount, 0);
        expect(created.totalSubtaskCount, 0);
        expect(created.subtaskProgress, 0.0);
        expect(created.subtaskProgressPercentage, 0);

        // Blank subtask rejected safely
        await ctrl.addSubtask('s12-task-1', '   ');
        expect(ctrl.state.errorMessage, 'Subtask title is required');
        expect(ctrl.state.findTaskById('s12-task-1')!.subtasks, isEmpty);

        // Add 3 subtasks cleanly
        await ctrl.addSubtask('s12-task-1', 'Collect invoices');
        await ctrl.addSubtask('s12-task-1', 'Review receipt amounts');
        await ctrl.addSubtask('s12-task-1', 'Archive folder');

        var task = ctrl.state.findTaskById('s12-task-1')!;
        expect(task.totalSubtaskCount, 3);
        expect(task.completedSubtaskCount, 0);
        expect(task.subtaskProgressPercentage, 0);

        // Toggle 2 subtasks complete -> 2/3 (67%)
        await ctrl.toggleSubtask('s12-task-1', 0, true);
        await ctrl.toggleSubtaskById('s12-task-1', task.subtasks[1].id);
        task = ctrl.state.findTaskById('s12-task-1')!;
        expect(task.completedSubtaskCount, 2);
        expect(task.subtaskProgressPercentage, 67);

        // Edit title (reject blank, accept valid trimmed title)
        final badEdit = await ctrl.editSubtaskTitle(
          's12-task-1',
          task.subtasks[1].id,
          '  ',
        );
        expect(badEdit, isFalse);
        expect(ctrl.state.errorMessage, 'Subtask title is required');

        final goodEdit = await ctrl.editSubtaskTitle(
          's12-task-1',
          task.subtasks[1].id,
          '  Verify ETB receipt totals  ',
        );
        expect(goodEdit, isTrue);
        task = ctrl.state.findTaskById('s12-task-1')!;
        expect(task.subtasks[1].title, 'Verify ETB receipt totals');
        expect(task.subtasks[1].done, isTrue);

        // Reorder last item to top
        await ctrl.moveSubtask('s12-task-1', 2, 0);
        task = ctrl.state.findTaskById('s12-task-1')!;
        expect(
          task.subtasks.map((s) => s.title).toList(),
          ['Archive folder', 'Collect invoices', 'Verify ETB receipt totals'],
        );

        // Delete item, add a new one (must not collide IDs), then test restoreSubtasks
        final snapshotBeforeDelete = List<TaskSubtask>.from(task.subtasks);
        final firstId = task.subtasks.first.id;
        await ctrl.deleteSubtask('s12-task-1', firstId);
        task = ctrl.state.findTaskById('s12-task-1')!;
        expect(task.subtasks.length, 2);
        expect(task.completedSubtaskCount, 2);
        expect(task.subtaskProgressPercentage, 100);

        await ctrl.addSubtask('s12-task-1', 'Send confirmation');
        task = ctrl.state.findTaskById('s12-task-1')!;
        expect(task.subtasks.map((s) => s.id).toSet().length, 3);

        // Undo restore brings exact deleted snapshot back cleanly
        await ctrl.restoreSubtasks('s12-task-1', snapshotBeforeDelete);

        // Reload in a fresh controller backed by the same Drift SQLite DB
        final reloadedCtrl = TasksController(repository: harness.repo);
        await reloadedCtrl.loadAll();
        final reloaded = reloadedCtrl.state.findTaskById('s12-task-1')!;
        expect(
          reloaded.subtasks.map((s) => s.title).toList(),
          ['Archive folder', 'Collect invoices', 'Verify ETB receipt totals'],
        );
        expect(reloaded.completedSubtaskCount, 2);
        expect(reloaded.totalSubtaskCount, 3);
        expect(reloaded.subtaskProgressPercentage, 67);
        // Parent task metadata preserved
        expect(reloaded.isPinned, isTrue);
        expect(reloaded.labels, const ['ops']);
        expect(reloaded.sortOrder, 7);
        expect(reloaded.status, 'in_progress');
      },
    );

    testWidgets(
      'TasksView renders Task Details subtasks even when initially empty, supports add/toggle/edit/reorder/delete+Undo and progress readout',
      (WidgetTester tester) async {
        final harness = await createHarness();
        final ctrl = harness.ctrl;
        final today = CalendarDate.today();

        await ctrl.createTask(
          id: 's12-ui-1',
          title: 'Launch checklist',
          scheduledDate: today,
          dueDate: today,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: TasksView(controller: ctrl),
          ),
        );
        await tester.pumpAndSettle();

        // Open Task Details on task with 0 subtasks
        await tester.tap(find.text('Launch checklist'));
        await tester.pumpAndSettle();
        expect(find.text('Subtasks'), findsOneWidget);
        expect(find.text('0 subtasks'), findsOneWidget);

        // Add two subtasks directly from Task Details
        await tester.enterText(
          find.widgetWithText(TextField, 'Add a subtask...'),
          'First step',
        );
        await tester.tap(find.byTooltip('Add subtask'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'Add a subtask...'),
          'Second step',
        );
        await tester.tap(find.byTooltip('Add subtask'));
        await tester.pumpAndSettle();

        expect(find.text('0 of 2 done (0%)'), findsOneWidget);

        // Check first subtask complete -> 1 of 2 done (50%)
        await tester.tap(find.byType(Checkbox).at(1));
        await tester.pumpAndSettle();
        expect(find.text('1 of 2 done (50%)'), findsOneWidget);

        // Move second subtask up
        await tester.tap(find.byTooltip('Move up').at(1));
        await tester.pumpAndSettle();
        expect(
          ctrl.state.findTaskById('s12-ui-1')!.subtasks.first.title,
          'Second step',
        );

        // Edit first subtask title
        await tester.tap(find.byTooltip('Edit subtask').first);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Second step'),
          'Renamed first step',
        );
        await tester.tap(find.byTooltip('Save subtask'));
        await tester.pumpAndSettle();
        expect(
          ctrl.state.findTaskById('s12-ui-1')!.subtasks.first.title,
          'Renamed first step',
        );

        // Delete a subtask and verify Undo option appears
        await tester.tap(find.byTooltip('Delete subtask').first);
        await tester.pumpAndSettle();
        expect(ctrl.state.findTaskById('s12-ui-1')!.subtasks.length, 1);
        expect(find.text('Undo'), findsOneWidget);
      },
    );
  });
}
