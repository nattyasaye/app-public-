import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/tasks/tasks_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/tasks_repository.dart';
import 'package:personal_management_app/domain/tasks/daily_planning_engine.dart';
import 'package:personal_management_app/ui/screens/tasks_view.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  configureSqliteForHostTests();

  group('Stage 2 — My Day and Daily Planning (Flutter Controller, SQLite & UI)',
      () {
    Future<({AppDatabase db, DriftTasksRepository repo, TasksController ctrl})>
        createHarness() async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.ensureInitialized();
      addTearDown(db.close);
      final repo = DriftTasksRepository(db);
      final ctrl = TasksController(repository: repo);
      addTearDown(ctrl.dispose);
      await ctrl.loadAll();
      return (db: db, repo: repo, ctrl: ctrl);
    }

    test(
      '1. Controller plans, removes from My Day without deleting Task, and reorders planned tasks',
      () async {
        final harness = await createHarness();
        final ctrl = harness.ctrl;
        final today = CalendarDate.today();

        await ctrl.createTask(id: 'm2-t1', title: 'Prepare weekly notes');
        await ctrl.createTask(id: 'm2-t2', title: 'Pay internet bill');
        await ctrl.createTask(id: 'm2-t3', title: 'Review budget');

        await ctrl.planTaskForDate('m2-t1', date: today);
        await ctrl.planTaskForDate('m2-t2', date: today);
        await ctrl.planTaskForDate('m2-t3', date: today);

        final initialSnap = ctrl.state.buildDailyPlanSnapshot(date: today);
        expect(
          initialSnap.remainingItems.map((i) => i.task.id).toList(),
          ['m2-t1', 'm2-t2', 'm2-t3'],
        );

        // Move m2-t3 up one position
        await ctrl.movePlannedTaskOrder('m2-t3', delta: -1, date: today);
        final movedSnap = ctrl.state.buildDailyPlanSnapshot(date: today);
        expect(
          movedSnap.remainingItems.map((i) => i.task.id).toList(),
          ['m2-t1', 'm2-t3', 'm2-t2'],
        );

        // Remove m2-t2 from My Day without deleting underlying Task
        await ctrl.removeTaskFromPlannedDay('m2-t2', date: today);
        expect(ctrl.state.findTaskById('m2-t2'), isNotNull);
        final afterRemoveSnap = ctrl.state.buildDailyPlanSnapshot(date: today);
        expect(
          afterRemoveSnap.remainingItems.map((i) => i.task.id).toList(),
          ['m2-t1', 'm2-t3'],
        );
        expect(afterRemoveSnap.dismissedCount, 1);
        expect(
          DailyPlanningEngine.findEntry(
            ctrl.state.dailyPlanningEntries,
            'm2-t2',
            today,
          )?.action,
          DailyPlanningActions.dismissed,
        );
      },
    );

    test(
      '2. Carry forward creates no duplicate entries, preserves planning history, and updates completion state',
      () async {
        final harness = await createHarness();
        final ctrl = harness.ctrl;
        final today = CalendarDate.today();
        final yesterday = today.addDays(-1);
        final twoDaysAgo = today.addDays(-2);

        await ctrl.createTask(
          id: 'cf-unfinished',
          title: 'Carry me forward',
          dueDate: twoDaysAgo,
        );
        await ctrl.createTask(
          id: 'cf-done',
          title: 'Already completed yesterday',
          status: 'completed',
        );

        await ctrl.planTaskForDate('cf-unfinished', date: yesterday);
        await ctrl.planTaskForDate('cf-done', date: yesterday);

        // Carry forward unfinished tasks to Today
        final carriedCount = await ctrl.carryForwardUnfinishedTasks(
          toDate: today,
        );
        expect(carriedCount, 1);
        expect(
          DailyPlanningEngine.findEntry(
            ctrl.state.dailyPlanningEntries,
            'cf-unfinished',
            today,
          )?.action,
          DailyPlanningActions.carriedForward,
        );
        expect(
          DailyPlanningEngine.findEntry(
            ctrl.state.dailyPlanningEntries,
            'cf-unfinished',
            yesterday,
          )?.action,
          DailyPlanningActions.planned,
        );

        // Second carry forward must produce zero duplicates
        final secondCarry = await ctrl.carryForwardUnfinishedTasks(
          toDate: today,
        );
        expect(secondCarry, 0);
        expect(
          ctrl.state.dailyPlanningEntries
              .where(
                (e) => e.taskId == 'cf-unfinished' && e.planDate == today,
              )
              .length,
          1,
        );

        // Complete carried-forward task today and verify yesterday review
        ctrl.setSelectedPlanDate(today);
        await ctrl.toggleTaskStatus('cf-unfinished');

        expect(
          DailyPlanningEngine.findEntry(
            ctrl.state.dailyPlanningEntries,
            'cf-unfinished',
            today,
          )?.action,
          DailyPlanningActions.completed,
        );
        expect(
          DailyPlanningEngine.findEntry(
            ctrl.state.dailyPlanningEntries,
            'cf-unfinished',
            yesterday,
          )?.action,
          DailyPlanningActions.planned,
        );

        final yesterdaySnap =
            ctrl.state.buildDailyPlanSnapshot(date: yesterday, today: today);
        final yesterdayItem =
            yesterdaySnap.items.firstWhere((i) => i.task.id == 'cf-unfinished');
        expect(yesterdayItem.completedLater, isTrue);
        expect(yesterdayItem.isCompletedForDay, isFalse);

        // Reopen restores 'carried_forward' on Today
        await ctrl.toggleTaskStatus('cf-unfinished');
        expect(
          DailyPlanningEngine.findEntry(
            ctrl.state.dailyPlanningEntries,
            'cf-unfinished',
            today,
          )?.action,
          DailyPlanningActions.carriedForward,
        );

        // Reload from SQLite verifies persistence across fresh controller
        final freshCtrl = TasksController(repository: harness.repo);
        addTearDown(freshCtrl.dispose);
        await freshCtrl.loadAll();
        expect(
          DailyPlanningEngine.findEntry(
            freshCtrl.state.dailyPlanningEntries,
            'cf-unfinished',
            yesterday,
          )?.action,
          DailyPlanningActions.planned,
        );
        expect(
          DailyPlanningEngine.findEntry(
            freshCtrl.state.dailyPlanningEntries,
            'cf-unfinished',
            today,
          )?.action,
          DailyPlanningActions.carriedForward,
        );
      },
    );

    testWidgets(
      '3. TasksView My Day workspace displays suggestions, plans tasks, reorders, removes without deleting, and reviews history',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 1600));

        final today = CalendarDate.today();
        final yesterday = today.addDays(-1);
        final fixture = await tester.runAsync(() async {
          final db = AppDatabase(NativeDatabase.memory());
          await db.ensureInitialized();
          final repo = DriftTasksRepository(db);
          final ctrl = TasksController(repository: repo);
          await ctrl.loadAll();

          await ctrl.createTask(
            id: 'ui-yesterday',
            title: 'Yesterday carryover item',
          );
          await ctrl.planTaskForDate('ui-yesterday', date: yesterday);

          await ctrl.createTask(
            id: 'ui-overdue',
            title: 'Overdue filing',
            dueDate: today.addDays(-3),
          );
          await ctrl.createTask(
            id: 'ui-scheduled',
            title: 'Scheduled review',
            scheduledDate: today,
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

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: TasksView(controller: ctrl),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to My Day filter chip
        final myDayChip = find.text('My Day');
        await tester.ensureVisible(myDayChip);
        await tester.pumpAndSettle();
        await tester.tap(myDayChip);
        await tester.pumpAndSettle();

        expect(find.text('Remaining for This Day'), findsOneWidget);
        expect(find.text('Nothing planned for this day yet'), findsOneWidget);
        expect(find.text('Yesterday carryover item'), findsOneWidget);
        expect(find.text('Overdue filing'), findsOneWidget);
        expect(find.text('Scheduled review'), findsOneWidget);

        // Carry forward all unfinished tasks
        final carryForwardBtn = find.text('Carry forward all (1)');
        await tester.ensureVisible(carryForwardBtn);
        await tester.pumpAndSettle();
        await tester.tap(carryForwardBtn);
        await pumpUntil(
          () => DailyPlanningEngine.isTaskPlannedForDate(
            ctrl.state.findTaskById('ui-yesterday')!,
            ctrl.state.dailyPlanningEntries,
            today,
            today: today,
          ),
          reason: 'Carry forward all button did not persist planned entry.',
        );

        expect(
          DailyPlanningEngine.isTaskPlannedForDate(
            ctrl.state.findTaskById('ui-yesterday')!,
            ctrl.state.dailyPlanningEntries,
            today,
            today: today,
          ),
          isTrue,
        );

        // Remove from My Day keeps task in underlying Tasks store
        final removeFromDayBtn =
            find.byTooltip('Remove Yesterday carryover item from My Day');
        await tester.ensureVisible(removeFromDayBtn);
        await tester.pumpAndSettle();
        await tester.tap(removeFromDayBtn);
        await pumpUntil(
          () =>
              DailyPlanningEngine.findEntry(
                ctrl.state.dailyPlanningEntries,
                'ui-yesterday',
                today,
              )?.action ==
              DailyPlanningActions.dismissed,
          reason: 'Remove from My Day did not persist dismissed entry.',
        );
        expect(ctrl.state.findTaskById('ui-yesterday'), isNotNull);

        // Step to previous day and verify history review + carry-to-today banner
        final previousDayBtn = find.byTooltip('Previous day');
        await tester.ensureVisible(previousDayBtn);
        await tester.pumpAndSettle();
        await tester.tap(previousDayBtn);
        await tester.pumpAndSettle();
        expect(find.text('Past Day Review'), findsOneWidget);
        expect(find.text('Yesterday carryover item'), findsOneWidget);
      },
    );
  });
}
