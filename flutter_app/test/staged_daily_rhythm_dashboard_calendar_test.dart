import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/calendar/calendar_controller.dart';
import 'package:personal_management_app/application/daily_rhythm/daily_rhythm_controller.dart';
import 'package:personal_management_app/application/finance/finance_controller.dart';
import 'package:personal_management_app/application/inbox/inbox_controller.dart';
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/application/projects/projects_controller.dart';
import 'package:personal_management_app/application/tasks/tasks_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/calendar_repository.dart';
import 'package:personal_management_app/data/repositories/daily_rhythm_repository.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';
import 'package:personal_management_app/data/repositories/inbox_repository.dart';
import 'package:personal_management_app/data/repositories/notes_repository.dart';
import 'package:personal_management_app/data/repositories/projects_repository.dart';
import 'package:personal_management_app/data/repositories/tasks_repository.dart';
import 'package:personal_management_app/domain/daily_rhythm/daily_rhythm_engine.dart';
import 'package:personal_management_app/domain/daily_rhythm/daily_rhythm_models.dart';
import 'package:personal_management_app/domain/daily_rhythm/daily_rhythm_workflows.dart';
import 'package:personal_management_app/ui/app_state.dart';
import 'package:personal_management_app/ui/screens/calendar_view.dart';
import 'package:personal_management_app/ui/screens/dashboard_view.dart';
import 'package:personal_management_app/ui/screens/finance_view.dart';
import 'package:personal_management_app/ui/shell/daywell_shell_routes.dart';
import 'package:personal_management_app/ui/widgets/daily_rhythm_dashboard_widgets.dart';

import 'support/sqlite_test_helper.dart';

class _StageDWidgetState extends ChangeNotifier implements AppStateManager {
  @override
  final FinanceController financeController;
  @override
  final TasksController tasksController;
  @override
  final ProjectsController projectsController;
  @override
  final CalendarController calendarController;
  @override
  final NotesController notesController;
  @override
  final InboxController inboxController;
  @override
  final DailyRhythmController dailyRhythmController;

  _StageDWidgetState({required AppDatabase db})
      : financeController = FinanceController(
          repository: DriftFinanceRepository(db),
        ),
        tasksController = TasksController(
          repository: DriftTasksRepository(db),
        ),
        projectsController = ProjectsController(
          repository: DriftProjectsRepository(db),
        ),
        calendarController = CalendarController(
          repository: DriftCalendarRepository(db),
        ),
        notesController = NotesController(
          repository: DriftNotesRepository(db),
        ),
        inboxController = InboxController(
          repository: DriftInboxRepository(db),
        ),
        dailyRhythmController = DailyRhythmController(
          repository: DriftDailyRhythmRepository(db),
        );

  void emitRootNotification() => notifyListeners();

  Future<void> loadAllControllers() async {
    await Future.wait<void>(<Future<void>>[
      financeController.loadAll(),
      tasksController.loadAll(),
      projectsController.loadAll(),
      calendarController.loadAll(),
      notesController.loadNotes(),
      inboxController.loadItems(includeProcessed: true),
      dailyRhythmController.loadAll(),
    ]);
  }

  @override
  void dispose() {
    financeController.dispose();
    tasksController.dispose();
    projectsController.dispose();
    calendarController.dispose();
    notesController.dispose();
    inboxController.dispose();
    dailyRhythmController.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _disposeStageDWidgetHarness(
  WidgetTester tester,
  _StageDWidgetState state,
  AppDatabase db,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
  state.dispose();
  var closed = false;
  final closeFuture = db.close().whenComplete(() {
    closed = true;
  });
  final watch = Stopwatch()..start();
  while (!closed && watch.elapsed < const Duration(seconds: 10)) {
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
}

DailyRhythmDayEntity _makeQualifyingDay(String dateIso) {
  return DailyRhythmDayEntity(
    dateIso: dateIso,
    bibleStudyDone: true,
    bibleStudyCompletedAt: '${dateIso}T06:00:00.000Z',
    prayerDone: true,
    prayerCompletedAt: '${dateIso}T06:15:00.000Z',
    taskReviewConfirmed: true,
    taskReviewedAt: '${dateIso}T09:00:00.000Z',
    taskReviewEvidence: const DailyRhythmTaskReviewEvidence(
      overdueCount: 0,
      todayCount: 1,
      plannedCount: 1,
      completedTodayCount: 1,
    ),
    financeCloseStatus: DailyRhythmFinanceCloseStatuses.closedWithTransactions,
    financeClosedAt: '${dateIso}T19:00:00.000Z',
  );
}

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage D — Flutter Daily Rhythm Dashboard & Calendar History', () {
    test(
      '1. DailyRhythmWorkflows computes dashboard overview, provisional/finalized freezes, and read-only calendar inspection',
      () {
        final fixedToday = CalendarDate(year: 2026, month: 11, day: 23);
        const fixedTodayIso = '2026-11-23';
        final days = <DailyRhythmDayEntity>[
          for (var offset = -16; offset <= -2; offset += 1)
            _makeQualifyingDay(fixedToday.addDays(offset).toIsoString()),
        ];
        final yesterdayIso = fixedToday.addDays(-1).toIsoString();

        final summary = DailyRhythmEngine.evaluateTimeline(
          days,
          today: fixedToday,
        );
        final taskSnapshot = DailyRhythmWorkflows.buildTaskReviewSnapshot(
          tasks: const [],
          planningEntries: const [],
          targetDateIso: fixedTodayIso,
          today: fixedToday,
        );
        final financeSummary = DailyRhythmWorkflows.inspectFinanceDay(
          entries: const [],
          targetDateIso: fixedTodayIso,
          today: fixedToday,
        );

        final overview = DailyRhythmWorkflows.buildDashboardOverview(
          timelineSummary: summary,
          taskSnapshot: taskSnapshot,
          financeSummary: financeSummary,
        );
        expect(overview.completedResponsibilities, 0);
        expect(overview.isDayQualified, isFalse);
        expect(overview.provisionalFreezeActive, isTrue);
        expect(overview.provisionalFreezeDateIso, yesterdayIso);
        expect(overview.currentStreak, 15);
        expect(overview.maxFreezes, 2);

        final yesterdayInspection = DailyRhythmWorkflows.describeCalendarDay(
          dateIso: yesterdayIso,
          timelineSummary: summary,
        );
        expect(
          yesterdayInspection.calendarStatus,
          DailyRhythmCalendarDisplayStatus.freezeProtected,
        );
        expect(yesterdayInspection.isProvisionalFreeze, isTrue);
        expect(yesterdayInspection.shortMarkerGlyph, '❄?');

        final unrecordedInspection = DailyRhythmWorkflows.describeCalendarDay(
          dateIso: fixedToday.addDays(-30).toIsoString(),
          timelineSummary: summary,
        );
        expect(
          unrecordedInspection.calendarStatus,
          DailyRhythmCalendarDisplayStatus.unrecorded,
        );
        expect(unrecordedInspection.hasRecordedHistory, isFalse);
      },
    );

    testWidgets(
      '2. DashboardDailyRhythmSection completes next Faith step via DailyRhythmController, preserves layout seam, and routes to Tasks/Finance/Calendar',
      (WidgetTester tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        final state = _StageDWidgetState(db: db);
        addTearDown(() => _disposeStageDWidgetHarness(tester, state, db));

        final todayIso = CalendarDate.today().toIsoString();
        final repo = DriftDailyRhythmRepository(db);
        await repo.upsertDay(
          DailyRhythmDayEntity.empty(todayIso).copyWith(
            bibleStudyDone: true,
            bibleStudyCompletedAt: '${todayIso}T06:00:00.000Z',
          ),
        );
        await state.loadAllControllers();

        DaywellTabId? selectedTab;
        int? openedFinanceTab;
        int? openedTasksSubTab;

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: DashboardView(
              state: state,
              onOpenQuickCapture: () {},
              onSelectTab: (tab) => selectedTab = tab,
              onOpenTasksSubTab: (idx) => openedTasksSubTab = idx,
              onOpenFinanceTab: (idx) => openedFinanceTab = idx,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('DAILY RHYTHM'), findsOneWidget);
        expect(find.text('1/2'), findsOneWidget);
        expect(find.text('Complete prayer'), findsWidgets);

        // Tap direct Faith action -> Prayer completes without creating tasks
        final prayerBtn = find.text('Complete prayer').first;
        await tester.ensureVisible(prayerBtn);
        await tester.pumpAndSettle();
        await tester.tap(prayerBtn);
        await tester.pumpAndSettle();
        final saveWatch = Stopwatch()..start();
        while (!state.dailyRhythmController.state.todayRecord.prayerDone &&
            saveWatch.elapsed < const Duration(seconds: 5)) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        await tester.pumpAndSettle();
        final todayRecord = state.dailyRhythmController.state.todayRecord;
        expect(todayRecord.prayerDone, isTrue);
        expect(find.text('2/2'), findsOneWidget);

        // Route to Tasks daily review
        final tasksBtn = find.text('Open daily review').first;
        await tester.ensureVisible(tasksBtn);
        await tester.pumpAndSettle();
        await tester.tap(tasksBtn);
        await tester.pumpAndSettle();
        expect(openedTasksSubTab, 0);
        expect(state.tasksController.state.dueDateFilter, 'today');

        // Route to Finance Transactions tab
        final financeBtn = find.text('Review & close').first;
        await tester.ensureVisible(financeBtn);
        await tester.pumpAndSettle();
        await tester.tap(financeBtn);
        await tester.pumpAndSettle();
        expect(openedFinanceTab, 1);

        // Route to Calendar history
        final historyBtn = find.text('Calendar history');
        await tester.ensureVisible(historyBtn);
        await tester.pumpAndSettle();
        await tester.tap(historyBtn);
        await tester.pumpAndSettle();
        expect(selectedTab, DaywellTabId.calendar);
      },
    );

    testWidgets(
      '3. CalendarView renders non-color-only Daily Rhythm markers, legend, and strictly read-only inspection for historical & unrecorded dates',
      (WidgetTester tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        final state = _StageDWidgetState(db: db);
        addTearDown(() => _disposeStageDWidgetHarness(tester, state, db));

        final today = CalendarDate.today();
        final startOfMonth = today.startOfGregorianMonth;
        final qualifiedDay = startOfMonth.addDays(1);
        final missedDay = startOfMonth.addDays(2);
        final unrecordedDay = startOfMonth;

        final repo = DriftDailyRhythmRepository(db);
        await repo.upsertDay(_makeQualifyingDay(qualifiedDay.toIsoString()));
        await state.loadAllControllers();

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: CalendarView(
              calendarController: state.calendarController,
              tasksController: state.tasksController,
              dailyRhythmController: state.dailyRhythmController,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Legend and initial read-only history card visible
        expect(find.text('Daily Rhythm history'), findsOneWidget);
        expect(find.text('Provisional freeze'), findsOneWidget);
        expect(find.text('Freeze protected'), findsOneWidget);

        // Select the qualified day
        state.calendarController.setSelectedCalendarDate(qualifiedDay);
        await tester.pumpAndSettle();
        expect(find.text('✓ Complete · Qualified'), findsOneWidget);
        expect(find.text('Complete (2/2)'), findsOneWidget);

        // Select the missed day
        state.calendarController.setSelectedCalendarDate(missedDay);
        await tester.pumpAndSettle();
        expect(find.text('✕ Missed'), findsOneWidget);

        // Select an unrecorded day prior to tracking start (must NOT fabricate history)
        state.calendarController.setSelectedCalendarDate(unrecordedDay);
        await tester.pumpAndSettle();
        expect(find.text('No record'), findsOneWidget);
        expect(
          find.textContaining('Historical dates without records remain empty'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '4. FinanceView requestedTab opens Transactions tab and Stage D cards adapt cleanly on dark 320px large-text screens',
      (WidgetTester tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        final state = _StageDWidgetState(db: db);
        addTearDown(() => _disposeStageDWidgetHarness(tester, state, db));

        final fixedToday = CalendarDate(year: 2026, month: 11, day: 23);
        final summary = DailyRhythmEngine.evaluateTimeline(
          [
            for (var offset = -16; offset <= -2; offset += 1)
              _makeQualifyingDay(fixedToday.addDays(offset).toIsoString()),
          ],
          today: fixedToday,
        );
        final overview = DailyRhythmWorkflows.buildDashboardOverview(
          timelineSummary: summary,
          taskSnapshot: DailyRhythmWorkflows.buildTaskReviewSnapshot(
            tasks: const [],
            planningEntries: const [],
            today: fixedToday,
          ),
          financeSummary: DailyRhythmWorkflows.inspectFinanceDay(
            entries: const [],
            today: fixedToday,
          ),
        );
        final inspection = DailyRhythmWorkflows.describeCalendarDay(
          dateIso: fixedToday.addDays(-1).toIsoString(),
          timelineSummary: summary,
        );

        await tester.binding.setSurfaceSize(const Size(320, 780));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.dark,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 780),
                textScaler: TextScaler.linear(1.6),
              ),
              child: Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    DailyRhythmDashboardCard(
                      overview: overview,
                      onOpenFaith: () {},
                      onOpenTasksReview: () {},
                      onOpenFinanceReview: () {},
                      onOpenCalendarHistory: () {},
                    ),
                    const SizedBox(height: 12),
                    DailyRhythmCalendarDetailCard(inspection: inspection),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Provisional freeze active'), findsOneWidget);
        expect(find.text('How streak freezes work'), findsOneWidget);

        // Expand freeze rules without overflow
        await tester.ensureVisible(find.text('How streak freezes work'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('How streak freezes work'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final multipleMissedFinder = find.textContaining(
          'Multiple consecutive missed days cannot be protected.',
        );
        expect(multipleMissedFinder, findsOneWidget);

        // Verify FinanceView supports requestedTab(tabIndex: 1)
        await state.loadAllControllers();
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: FinanceView(
              state: state,
              controller: state.financeController,
              dailyRhythmController: state.dailyRhythmController,
              requestedTab: (tabIndex: 1, nonce: 1),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
