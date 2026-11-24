import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/daily_rhythm/daily_rhythm_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/daily_rhythm_repository.dart';
import 'package:personal_management_app/domain/daily_rhythm/daily_rhythm_engine.dart';
import 'package:personal_management_app/domain/daily_rhythm/daily_rhythm_models.dart';
import 'package:personal_management_app/domain/daily_rhythm/daily_rhythm_workflows.dart';
import 'package:personal_management_app/domain/finance/finance_models.dart';
import 'package:personal_management_app/domain/tasks/task_models.dart';
import 'package:personal_management_app/ui/app_state.dart';
import 'package:personal_management_app/ui/widgets/daily_rhythm_workflow_widgets.dart';

import 'support/sqlite_test_helper.dart';

Widget _wrapWithTheme(
  Widget child, {
  ThemeMode themeMode = ThemeMode.light,
}) {
  return MaterialApp(
    theme: DaywellTheme.light,
    darkTheme: DaywellTheme.dark,
    themeMode: themeMode,
    home: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage C — Flutter Daily Rhythm Module Workflows', () {
    final fixedToday = CalendarDate(year: 2026, month: 11, day: 23);
    const fixedTodayIso = '2026-11-23';

    test(
      '1. Pure DailyRhythmWorkflows computes task review counts, Finance day state, and same-day ledger diffs accurately',
      () {
        final tasks = [
          TaskEntity(
            id: 't-overdue',
            title: 'Overdue bill',
            dueDate: CalendarDate(year: 2026, month: 11, day: 21),
            priority: 'high',
            createdAt: DateTime.utc(2026, 11, 20),
          ),
          TaskEntity(
            id: 't-today',
            title: 'Today call',
            dueDate: fixedToday,
            createdAt: DateTime.utc(2026, 11, 22),
          ),
          TaskEntity(
            id: 't-done',
            title: 'Morning stretch',
            status: 'completed',
            completedAt: DateTime.utc(2026, 11, 23, 5, 0),
            createdAt: DateTime.utc(2026, 11, 22),
          ),
        ];
        final planningEntries = [
          DailyPlanningEntryEntity(
            id: 'p-1',
            taskId: 't-today',
            planDate: fixedToday,
            action: DailyPlanningActions.planned,
            sortOrder: 0,
            createdAt: DateTime.utc(2026, 11, 23, 4, 0),
            updatedAt: DateTime.utc(2026, 11, 23, 4, 0),
          ),
        ];

        final snapshot = DailyRhythmWorkflows.buildTaskReviewSnapshot(
          tasks: tasks,
          planningEntries: planningEntries,
          targetDateIso: fixedTodayIso,
          today: fixedToday,
        );
        expect(snapshot.hasRelevantTasks, isTrue);
        expect(snapshot.confirmActionLabel, 'Confirm daily review');
        expect(snapshot.evidence.overdueCount, 1);
        expect(snapshot.evidence.todayCount, 1);
        expect(snapshot.evidence.plannedCount, 1);
        expect(snapshot.evidence.completedTodayCount, 1);

        final clearSnapshot = DailyRhythmWorkflows.buildTaskReviewSnapshot(
          tasks: const [],
          planningEntries: const [],
          targetDateIso: fixedTodayIso,
          today: fixedToday,
        );
        expect(clearSnapshot.hasRelevantTasks, isFalse);
        expect(clearSnapshot.confirmActionLabel, 'Confirm clear day');

        final entries = [
          JournalEntryModel(
            id: 'je-today',
            entryType: EntryType.expense,
            description: 'Coffee',
            occurrenceDate: fixedTodayIso,
            createdAt: DateTime.utc(2026, 11, 23, 7, 0),
          ),
          JournalEntryModel(
            id: 'je-void',
            entryType: EntryType.expense,
            description: 'Cancelled',
            occurrenceDate: fixedTodayIso,
            isVoided: true,
            createdAt: DateTime.utc(2026, 11, 23, 8, 0),
          ),
        ];
        final finSummary = DailyRhythmWorkflows.inspectFinanceDay(
          entries: entries,
          targetDateIso: fixedTodayIso,
          today: fixedToday,
        );
        expect(finSummary.hasTransactions, isTrue);
        expect(finSummary.transactionCount, 1);
        expect(
          finSummary.confirmActionLabel,
          "I've reviewed today's transactions",
        );

        final offDayEntries = [
          JournalEntryModel(
            id: 'je-old',
            entryType: EntryType.expense,
            description: 'Old',
            occurrenceDate: '2026-11-20',
            createdAt: DateTime.utc(2026, 11, 20, 7, 0),
          ),
        ];
        final offDayPostings = [
          PostingModel(
            id: 'p-old',
            entryId: 'je-old',
            accountId: 'acc-1',
            amountCents: 1000,
            direction: PostingDirection.credit,
            accountMovementDate: '2026-11-20',
          ),
        ];
        expect(
          DailyRhythmWorkflows.didLedgerChangeAffectDate(
            prevEntries: const [],
            prevPostings: const [],
            nextEntries: offDayEntries,
            nextPostings: offDayPostings,
            targetDateIso: fixedTodayIso,
            today: fixedToday,
          ),
          isFalse,
        );
        expect(
          DailyRhythmWorkflows.didLedgerChangeAffectDate(
            prevEntries: offDayEntries,
            prevPostings: offDayPostings,
            nextEntries: entries,
            nextPostings: [
              PostingModel(
                id: 'p-today',
                entryId: 'je-today',
                accountId: 'acc-1',
                amountCents: 500,
                direction: PostingDirection.credit,
                accountMovementDate: fixedTodayIso,
              ),
            ],
            targetDateIso: fixedTodayIso,
            today: fixedToday,
          ),
          isTrue,
        );
      },
    );

    test(
      '2. DailyRhythmController persists independent Faith, Task review, and Finance close transitions via DriftDailyRhythmRepository',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final repo = DriftDailyRhythmRepository(db);
        final ctrl = DailyRhythmController(repository: repo);
        addTearDown(ctrl.dispose);

        await ctrl.loadAll(today: fixedToday);

        final faith1 = await ctrl.updateFaith(
          dateIso: fixedTodayIso,
          bibleStudyDone: true,
          today: fixedToday,
          nowIso: '2026-11-23T06:00:00.000Z',
        );
        expect(faith1.applied, isTrue);
        expect(ctrl.state.dayFor(fixedTodayIso).bibleStudyDone, isTrue);
        expect(ctrl.state.dayFor(fixedTodayIso).prayerDone, isFalse);

        final faith2 = await ctrl.updateFaith(
          dateIso: fixedTodayIso,
          prayerDone: true,
          today: fixedToday,
          nowIso: '2026-11-23T06:15:00.000Z',
        );
        expect(faith2.applied, isTrue);
        expect(ctrl.state.dayFor(fixedTodayIso).isFaithComplete, isTrue);

        final pastLock = await ctrl.updateFaith(
          dateIso: '2026-11-22',
          bibleStudyDone: true,
          today: fixedToday,
        );
        expect(pastLock.applied, isFalse);
        expect(pastLock.reason, DailyRhythmMutationReason.lockedNonToday);

        final taskRes = await ctrl.confirmTaskReview(
          dateIso: fixedTodayIso,
          tasks: const [],
          planningEntries: const [],
          today: fixedToday,
          nowIso: '2026-11-23T17:00:00.000Z',
        );
        expect(taskRes.applied, isTrue);
        expect(ctrl.state.dayFor(fixedTodayIso).taskReviewConfirmed, isTrue);

        // Day still partial until Finance closes
        expect(ctrl.state.summary.todayRecord.qualifies, isFalse);

        final finClose = await ctrl.confirmFinanceClose(
          dateIso: fixedTodayIso,
          entries: const [],
          today: fixedToday,
          nowIso: '2026-11-23T18:00:00.000Z',
        );
        expect(finClose.applied, isTrue);
        expect(
          ctrl.state.dayFor(fixedTodayIso).financeCloseStatus,
          DailyRhythmFinanceCloseStatuses.closedNoTransactions,
        );
        expect(ctrl.state.summary.todayRecord.qualifies, isTrue);

        // Reloading from SQLite preserves check-ins
        final reloaded = DailyRhythmController(repository: repo);
        addTearDown(reloaded.dispose);
        await reloaded.loadAll(today: fixedToday);
        expect(reloaded.state.dayFor(fixedTodayIso).qualifies, isTrue);
      },
    );

    test(
      '3. AppStateManager Finance observer marks closed today record needs_reconfirmation only on same-day ledger changes',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final appState = AppStateManager(db: db);
        addTearDown(appState.dispose);
        await appState.initialize();

        await appState.financeController.completeSetup([
          AccountModel(
            id: 'acc-cash',
            name: 'Cash ETB',
            type: AccountType.asset,
            subType: AccountSubType.cash,
            openingBalanceCents: 100000,
            openingBalanceDate: '2026-11-01',
          ),
        ]);

        final today = CalendarDate.today();
        final todayIso = today.toIsoString();
        final yesterday = today.addDays(-1);
        final expCat = appState.financeController.state.activeCategories
            .firstWhere((c) => c.type == 'expense');

        await appState.dailyRhythmController.confirmFinanceClose(
          dateIso: todayIso,
          entries: appState.financeController.state.journalEntries,
          today: today,
        );
        expect(
          appState.dailyRhythmController.state.dayFor(todayIso).financeCloseStatus,
          DailyRhythmFinanceCloseStatuses.closedNoTransactions,
        );

        // Historical yesterday entry must NOT trigger needs_reconfirmation for today
        await appState.financeController.recordDirectExpense(
          accountId: 'acc-cash',
          categoryId: expCat.id,
          amountCents: 2000,
          date: yesterday,
          description: 'Yesterday snack',
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          appState.dailyRhythmController.state.dayFor(todayIso).financeCloseStatus,
          DailyRhythmFinanceCloseStatuses.closedNoTransactions,
        );

        // Same-day entry MUST transition closed today -> needs_reconfirmation
        await appState.financeController.recordDirectExpense(
          accountId: 'acc-cash',
          categoryId: expCat.id,
          amountCents: 3500,
          date: today,
          description: 'Today lunch',
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          appState.dailyRhythmController.state.dayFor(todayIso).financeCloseStatus,
          DailyRhythmFinanceCloseStatuses.needsReconfirmation,
        );
      },
    );

    testWidgets(
      '4. Stage C Daily Rhythm cards render cleanly in Light & Dark modes and trigger callbacks',
      (tester) async {
        var bibleToggled = false;
        var prayerToggled = false;
        var taskConfirmed = false;
        var financeConfirmed = false;
        var filterTodayTapped = false;

        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          await tester.pumpWidget(
            _wrapWithTheme(
              themeMode: mode,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DailyFaithCheckInCard(
                    dateIso: fixedTodayIso,
                    record: DailyRhythmDayEntity.empty(fixedTodayIso),
                    onToggleBibleStudy: (val) => bibleToggled = val,
                    onTogglePrayer: (val) => prayerToggled = val,
                  ),
                  const SizedBox(height: 12),
                  DailyTaskReviewCard(
                    snapshot: DailyRhythmWorkflows.buildTaskReviewSnapshot(
                      tasks: const [],
                      planningEntries: const [],
                      targetDateIso: fixedTodayIso,
                      today: fixedToday,
                    ),
                    record: DailyRhythmDayEntity.empty(fixedTodayIso),
                    onConfirmReview: () => taskConfirmed = true,
                  ),
                  const SizedBox(height: 12),
                  DailyFinanceCloseCard(
                    summary: DailyRhythmWorkflows.inspectFinanceDay(
                      entries: const [],
                      targetDateIso: fixedTodayIso,
                      today: fixedToday,
                    ),
                    record: const DailyRhythmDayEntity(
                      dateIso: fixedTodayIso,
                      financeCloseStatus:
                          DailyRhythmFinanceCloseStatuses.needsReconfirmation,
                    ),
                    isShowingTodayFilter: false,
                    onFilterToday: () => filterTodayTapped = true,
                    onConfirmClose: () => financeConfirmed = true,
                  ),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Daily Faith check-in'), findsOneWidget);
          expect(find.text('Daily task review'), findsOneWidget);
          expect(find.text('Confirm clear day'), findsOneWidget);
          expect(find.text('Daily Finance review'), findsOneWidget);
          expect(find.text('Confirm no transactions today'), findsOneWidget);
          expect(find.text('View Today'), findsOneWidget);
        }

        await tester.tap(find.text('Bible study'));
        await tester.tap(find.text('Prayer'));
        await tester.tap(find.text('Confirm clear day'));
        await tester.tap(find.text('View Today'));
        await tester.tap(find.text('Confirm no transactions today'));
        await tester.pump();

        expect(bibleToggled, isTrue);
        expect(prayerToggled, isTrue);
        expect(taskConfirmed, isTrue);
        expect(filterTodayTapped, isTrue);
        expect(financeConfirmed, isTrue);
      },
    );
  });
}
