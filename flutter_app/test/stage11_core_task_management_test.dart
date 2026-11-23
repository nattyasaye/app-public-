import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/tasks/tasks_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/tasks_repository.dart';
import 'package:personal_management_app/ui/screens/tasks_view.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  configureSqliteForHostTests();

  group('Stage 1.1 — Core Task Management (Flutter Controller, State & UI)',
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
      '1–8. Controller supports create with status/dates, validation, edit preserving metadata, complete/reopen, archive/restore, active count filtering, and safe delete + restoreDeletedTask',
      () async {
        final harness = await createHarness();
        final ctrl = harness.ctrl;
        final today = CalendarDate.today();
        final tomorrow = today.addDays(1);

        // Rejects blank title on create
        final invalidCreate = await ctrl.createTask(title: '   ');
        expect(invalidCreate, isNull);
        expect(ctrl.state.errorMessage, 'Task title is required');

        // Creates task with status, priority, scheduledDate, dueDate, and existing metadata
        final created = await ctrl.createTask(
          id: 's11-task-1',
          title: 'Draft budget outline',
          description: 'Initial notes',
          priority: 'high',
          status: 'in_progress',
          scheduledDate: today,
          dueDate: tomorrow,
          labels: const ['finance'],
          isPinned: true,
          subtasks: const [
            TaskSubtask(id: 'sub-1', title: 'Gather numbers', done: true),
          ],
          sortOrder: 3,
        );
        expect(created, isNotNull);
        expect(created!.status, 'in_progress');
        expect(created.scheduledDate, today);
        expect(created.dueDate, tomorrow);

        // Today filter includes task due to scheduledDate <= today
        expect(ctrl.state.todayCount, 1);
        expect(ctrl.state.allCount, 1);
        expect(ctrl.state.archivedCount, 0);

        // Edit task: update title, clear description, change priority/status to completed, clear scheduledDate
        final edited = await ctrl.updateTask(
          id: 's11-task-1',
          title: 'Finalize budget outline',
          clearDescription: true,
          priority: 'urgent',
          status: 'completed',
          clearScheduledDate: true,
          dueDate: today,
        );
        expect(edited, isNotNull);
        expect(edited!.title, 'Finalize budget outline');
        expect(edited.description, isNull);
        expect(edited.priority, 'urgent');
        expect(edited.status, 'completed');
        expect(edited.completedAt, isNotNull);
        expect(edited.scheduledDate, isNull);
        expect(edited.dueDate, today);
        // Existing metadata preserved
        expect(edited.isPinned, isTrue);
        expect(edited.labels, const ['finance']);
        expect(edited.subtasks.length, 1);
        expect(edited.sortOrder, 3);

        // Reopen task clears completedAt
        await ctrl.toggleTaskStatus('s11-task-1');
        final reopened = ctrl.state.findTaskById('s11-task-1')!;
        expect(reopened.status, 'not_started');
        expect(reopened.completedAt, isNull);

        // Archive task isolates it from Today, All, Pending, Completed counts
        await ctrl.archiveTask('s11-task-1');
        expect(ctrl.state.todayCount, 0);
        expect(ctrl.state.allCount, 0);
        expect(ctrl.state.pendingTasks, isEmpty);
        expect(ctrl.state.archivedCount, 1);

        ctrl.setViewFilter('archived');
        expect(ctrl.state.filteredTasks.map((t) => t.id), ['s11-task-1']);

        // Restore task returns it to active lists
        await ctrl.restoreTask('s11-task-1');
        expect(ctrl.state.archivedCount, 0);
        expect(ctrl.state.todayCount, 1);
        expect(ctrl.state.allCount, 1);

        // Delete + restoreDeletedTask (Undo)
        final snapshot = ctrl.state.findTaskById('s11-task-1')!;
        await ctrl.deleteTask('s11-task-1');
        expect(ctrl.state.tasks, isEmpty);

        await ctrl.restoreDeletedTask(snapshot);
        expect(ctrl.state.tasks.length, 1);
        expect(ctrl.state.findTaskById('s11-task-1')!.title,
            'Finalize budget outline');
      },
    );

    testWidgets(
      'TasksView renders Create, Details, Edit, Complete/Reopen, Archive/Restore, and Safe Delete confirmation flows',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 1400));

        final fixture = await tester.runAsync(() async {
          final db = AppDatabase(NativeDatabase.memory());
          await db.ensureInitialized();
          final repo = DriftTasksRepository(db);
          final ctrl = TasksController(repository: repo);
          final today = CalendarDate.today();
          await ctrl.createTask(
            id: 'ui-task-1',
            title: 'Review contract',
            description: 'Check section 4 terms',
            priority: 'high',
            status: 'in_progress',
            scheduledDate: today,
            dueDate: today,
          );
          return (db: db, ctrl: ctrl);
        });

        final db = fixture!.db;
        final ctrl = fixture.ctrl;

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 20));
          ctrl.dispose();
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

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: TasksView(controller: ctrl),
          ),
        );
        await tester.pumpAndSettle();

        // Task card visible on Today tab
        expect(find.text('Review contract'), findsOneWidget);
        expect(find.text('In Progress'), findsOneWidget);

        // Tap task to open Details sheet
        await tester.tap(find.text('Review contract'));
        await tester.pumpAndSettle();
        expect(find.text('Check section 4 terms'), findsOneWidget);
        expect(find.text('Edit'), findsOneWidget);
        expect(find.text('Archive'), findsOneWidget);
        expect(find.text('Complete Task'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);

        // Open Edit sheet from Details
        await tester.ensureVisible(find.text('Edit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        expect(find.text('Edit Task'), findsOneWidget);
        expect(find.text('Save Changes'), findsOneWidget);

        // Update title and save
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Review contract'),
          'Review updated contract',
        );
        await tester.ensureVisible(find.text('Save Changes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();
        expect(find.text('Review updated contract'), findsOneWidget);

        // Open Details and Archive task
        await tester.tap(find.text('Review updated contract'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Archive'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archive'));
        await tester.pumpAndSettle();

        // Hidden from Today, visible in Archived chip
        expect(find.text('Review updated contract'), findsNothing);
        await tester.ensureVisible(find.text('Archived'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archived'));
        await tester.pumpAndSettle();
        expect(find.text('Review updated contract'), findsOneWidget);

        // Restore via Details
        await tester.tap(find.text('Review updated contract'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Restore'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restore'));
        await tester.pumpAndSettle();
        expect(ctrl.state.archivedCount, 0);

        // Switch back to All and test Safe Delete confirmation + Undo
        await tester.ensureVisible(find.text('All'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('All'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review updated contract'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(find.text('Delete task?'), findsOneWidget);
        await tester.tap(find.text('Delete Task'));
        await tester.pumpAndSettle();
        expect(ctrl.state.tasks, isEmpty);
        expect(find.text('Undo'), findsOneWidget);
      },
    );
  });
}
