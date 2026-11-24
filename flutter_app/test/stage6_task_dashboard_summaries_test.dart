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
import 'package:personal_management_app/domain/projects/progress_engine.dart';
import 'package:personal_management_app/domain/projects/project_models.dart';
import 'package:personal_management_app/domain/tasks/task_summary_engine.dart';
import 'package:personal_management_app/ui/app_state.dart';
import 'package:personal_management_app/ui/screens/dashboard_view.dart';
import 'package:personal_management_app/ui/screens/projects/project_detail_screen.dart';
import 'package:personal_management_app/ui/screens/tasks_view.dart';

import 'support/sqlite_test_helper.dart';

class _Stage6WidgetState extends ChangeNotifier implements AppStateManager {
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

  _Stage6WidgetState({required AppDatabase db})
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

void main() {
  configureSqliteForHostTests();

  group('Stage 6 — Task Dashboard and Progress Summaries (Flutter)', () {
    test(
      '1. TaskSummaryEngine computes task overview, My Day summary, and project/milestone progress with archived exclusions and manual-completion guard',
      () {
        final today = CalendarDate(year: 2026, month: 11, day: 22);
        final projects = <ProjectEntity>[
          ProjectEntity(
              id: 'p-active', title: 'Alpha Launch', status: 'active'),
          ProjectEntity(
              id: 'p-no-ms', title: 'No Milestones', status: 'active'),
          ProjectEntity(
            id: 'p-manual-pending',
            title: 'Mislabelled Complete',
            status: 'completed',
          ),
          ProjectEntity(
            id: 'p-manual-empty',
            title: 'Empty Complete',
            status: 'completed',
          ),
          ProjectEntity(
            id: 'p-archived',
            title: 'Archived Project',
            status: 'active',
            isArchived: true,
          ),
        ];

        final tasks = <TaskEntity>[
          TaskEntity(
            id: 't-over',
            title: 'Overdue Task',
            dueDate: today.addDays(-1),
            projectId: 'p-active',
          ),
          TaskEntity(
            id: 't-due-today',
            title: 'Due Today Task',
            dueDate: today,
            projectId: 'p-no-ms',
          ),
          TaskEntity(
            id: 't-upcoming',
            title: 'Upcoming Task',
            dueDate: today.addDays(3),
            projectId: 'p-no-ms',
          ),
          TaskEntity(
            id: 't-done',
            title: 'Completed Task',
            status: 'completed',
            completedAt: DateTime.utc(2026, 11, 22, 8, 0),
            projectId: 'p-active',
          ),
          TaskEntity(
            id: 't-manual-open',
            title: 'Open Work',
            projectId: 'p-manual-pending',
          ),
          TaskEntity(
            id: 't-cancelled',
            title: 'Cancelled Work',
            status: 'cancelled',
            dueDate: today,
            projectId: 'p-active',
          ),
          TaskEntity(
            id: 't-archived',
            title: 'Archived Work',
            dueDate: today.addDays(-2),
            isArchived: true,
            projectId: 'p-active',
          ),
          TaskEntity(
            id: 't-in-arch-proj',
            title: 'Task inside archived project',
            projectId: 'p-archived',
          ),
        ];

        final milestones = <MilestoneEntity>[
          MilestoneEntity(
            id: 'm1',
            projectId: 'p-active',
            title: 'M1',
            isCompleted: true,
          ),
          MilestoneEntity(
            id: 'm2',
            projectId: 'p-active',
            title: 'M2',
            isCompleted: false,
          ),
          MilestoneEntity(
            id: 'm3',
            projectId: 'p-archived',
            title: 'Archived M',
            isCompleted: true,
          ),
        ];

        final entries = <DailyPlanningEntryEntity>[
          DailyPlanningEntryEntity(
            id: 'dp1',
            planDate: today,
            taskId: 't-due-today',
            action: 'planned',
          ),
          DailyPlanningEntryEntity(
            id: 'dp2',
            planDate: today,
            taskId: 't-done',
            action: 'planned',
          ),
        ];

        final taskOverview = TaskSummaryEngine.buildTaskOverview(
          tasks: tasks,
          dailyPlanningEntries: entries,
          today: today,
        );

        expect(taskOverview.overdueCount, 1);
        expect(taskOverview.dueTodayCount, 1);
        expect(taskOverview.upcomingCount, 1);
        expect(taskOverview.completedCount, 1);
        // Active non-archived pending: t-over, t-due-today, t-upcoming, t-manual-open, t-in-arch-proj = 5
        expect(taskOverview.remainingCount, 5);
        expect(taskOverview.archivedCount, 1);
        expect(taskOverview.todayPlan.totalPlannedCount, 2);
        expect(taskOverview.todayPlan.completedCount, 1);
        expect(taskOverview.todayPlan.remainingCount, 1);
        expect(taskOverview.todayPlan.progressPercentage, 50);

        final projectsOverview = TaskSummaryEngine.buildProjectsOverview(
          projects: projects,
          tasks: tasks,
          milestones: milestones,
          today: today,
        );

        // Archived project omitted by default
        expect(projectsOverview.totalProjectsCount, 4);
        expect(
          projectsOverview.projects.any((p) => p.project.id == 'p-archived'),
          isFalse,
        );

        final alpha = projectsOverview.projects
            .firstWhere((p) => p.project.id == 'p-active');
        expect(alpha.totalTasks, 2); // excludes t-cancelled and t-archived
        expect(alpha.completedTasks, 1);
        expect(alpha.remainingTasks, 1);
        expect(alpha.overdueTasks, 1);
        expect(alpha.hasMilestones, isTrue);
        expect(alpha.totalMilestones, 2);
        expect(alpha.completedMilestones, 1);
        expect(alpha.displayPercentage, 50);

        final noMs = projectsOverview.projects
            .firstWhere((p) => p.project.id == 'p-no-ms');
        expect(noMs.hasMilestones, isFalse);
        expect(noMs.totalMilestones, 0);
        expect(noMs.totalTasks, 2);
        expect(noMs.remainingTasks, 2);
        expect(noMs.displayPercentage, 0);

        final manualPending = projectsOverview.projects
            .firstWhere((p) => p.project.id == 'p-manual-pending');
        expect(manualPending.displayPercentage, 0);

        final manualEmpty = projectsOverview.projects
            .firstWhere((p) => p.project.id == 'p-manual-empty');
        expect(manualEmpty.displayPercentage, 100);

        // Explicit inclusion of archived projects & tasks includes p-archived + t-archived
        final withArchived = TaskSummaryEngine.buildProjectsOverview(
          projects: projects,
          tasks: tasks,
          milestones: milestones,
          today: today,
          includeArchivedProjects: true,
          includeArchivedTasks: true,
        );
        expect(withArchived.totalProjectsCount, 5);
        final alphaArchived =
            withArchived.projects.firstWhere((p) => p.project.id == 'p-active');
        expect(alphaArchived.totalTasks, 3);

        // ProgressEngine excludes archived tasks by default
        final summary = ProgressEngine.calculateProjectProgressSummary(
          project: projects.first,
          blocks: const <ProjectTrackingBlockEntity>[],
          records: const <ProjectTrackingRecordEntity>[],
          linkedTasks: tasks,
          milestones: milestones,
          asOfDate: today,
        );
        expect(summary.linkedTasksTotal, 2);
        expect(summary.linkedTasksCompleted, 1);
      },
    );

    test(
      '2. SQLite DriftProjectsRepository maps completedAt & isArchived cleanly, TasksModuleState matches summary rules, and openDashboardFilter resets stale filters',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final tasksCtrl = TasksController(
          repository: DriftTasksRepository(db),
        );
        addTearDown(tasksCtrl.dispose);

        final projRepo = DriftProjectsRepository(db);
        final projectsCtrl = ProjectsController(repository: projRepo);
        addTearDown(projectsCtrl.dispose);

        final today = CalendarDate.today();

        await projectsCtrl.createProject(
          id: 'proj-sql',
          title: 'SQLite Project',
          status: 'active',
        );
        await tasksCtrl.createTask(
          id: 'task-open',
          title: 'Open SQLite Task',
          projectId: 'proj-sql',
          dueDate: today,
        );
        await tasksCtrl.createTask(
          id: 'task-done',
          title: 'Done SQLite Task',
          projectId: 'proj-sql',
          status: 'completed',
        );
        await tasksCtrl.createTask(
          id: 'task-arch',
          title: 'Archived SQLite Task',
          projectId: 'proj-sql',
          isArchived: true,
        );

        await tasksCtrl.loadAll();
        await projectsCtrl.loadAll();

        final summary = await projRepo.getProjectProgressSummary('proj-sql');
        expect(summary.linkedTasksTotal, 2);
        expect(summary.linkedTasksCompleted, 1);

        final stateProgress = tasksCtrl.state.getProjectProgress('proj-sql');
        expect(stateProgress, 50);

        // openDashboardFilter applies requested view + dueDateFilter and clears stale search/tags
        tasksCtrl.setSearchQuery('stale query');
        tasksCtrl.setPriorityFilter('urgent');
        tasksCtrl.openDashboardFilter(
          viewFilter: 'active',
          dueDateFilter: 'today',
        );
        expect(tasksCtrl.state.viewFilter, 'active');
        expect(tasksCtrl.state.dueDateFilter, 'today');
        expect(tasksCtrl.state.searchQuery, isEmpty);
        expect(tasksCtrl.state.priorityFilter, isNull);
        expect(tasksCtrl.state.filteredTasks.map((t) => t.id), ['task-open']);
      },
    );

    Future<void> closeDbWithPump(
      WidgetTester tester,
      AppDatabase db, {
      required VoidCallback disposeControllers,
      bool resetSurface = false,
    }) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
      disposeControllers();
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
      if (resetSurface) {
        await tester.binding.setSurfaceSize(null);
      }
    }

    testWidgets(
      '3. DashboardTasksSection and DashboardProjectProgressSection render counts, My Day summary, conditional milestones, and interactive navigation',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1400));

        final fixture = await tester.runAsync(() async {
          final db = AppDatabase(NativeDatabase.memory());
          await db.ensureInitialized();
          final state = _Stage6WidgetState(db: db);

          final today = CalendarDate.today();
          final tasksRepo = DriftTasksRepository(db);
          final projectsRepo = DriftProjectsRepository(db);

          await projectsRepo.createProject(
            ProjectEntity(
              id: 'p-live',
              title: 'Active Roadmap',
              status: 'active',
            ),
          );
          await projectsRepo.createProject(
            ProjectEntity(
              id: 'p-arch',
              title: 'Hidden Archived Project',
              status: 'active',
              isArchived: true,
            ),
          );
          await tasksRepo.createTask(
            TaskEntity(
              id: 't-over',
              title: 'Overdue Task Item',
              dueDate: today.addDays(-1),
              projectId: 'p-live',
            ),
          );
          await tasksRepo.createTask(
            TaskEntity(
              id: 't-today',
              title: 'Today Task Item',
              dueDate: today,
              projectId: 'p-live',
            ),
          );
          await tasksRepo.createTask(
            TaskEntity(
              id: 't-done',
              title: 'Done Task Item',
              status: 'completed',
              projectId: 'p-live',
            ),
          );
          await tasksRepo.upsertDailyPlanningEntry(
            DailyPlanningEntryEntity(
              id: 'dp-today',
              planDate: today,
              taskId: 't-today',
              action: 'planned',
            ),
          );

          await state.loadAllControllers();
          return (db: db, state: state);
        });

        final db = fixture!.db;
        final state = fixture.state;
        addTearDown(
          () => closeDbWithPump(
            tester,
            db,
            disposeControllers: state.dispose,
            resetSurface: true,
          ),
        );

        var openTasksCalls = 0;
        var openProjectsCalls = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: ListView(
                children: [
                  DashboardTasksSection(
                    state: state,
                    onOpenTasks: () => openTasksCalls += 1,
                  ),
                  DashboardProjectProgressSection(
                    state: state,
                    onOpenProjects: () => openProjectsCalls += 1,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Tasks Overview'), findsOneWidget);
        expect(find.text('1 / 3 done'), findsOneWidget);
        expect(find.text('Overdue'), findsOneWidget);
        expect(find.text('Due Today'), findsOneWidget);
        expect(find.text('Upcoming'), findsOneWidget);
        expect(find.text('Completed'), findsOneWidget);
        expect(find.text('Remaining'), findsOneWidget);
        expect(find.text("Today's Plan (My Day)"), findsOneWidget);
        expect(find.text('0 completed · 1 remaining'), findsOneWidget);

        // Project Progress omits archived project, surfaces overdue count, & hides milestones when none exist
        expect(find.text('Project Progress'), findsOneWidget);
        expect(find.text('Active Roadmap'), findsOneWidget);
        expect(find.text('Hidden Archived Project'), findsNothing);
        expect(find.textContaining('1/3 tasks · 2 remaining'), findsWidgets);
        expect(find.textContaining('1 overdue'), findsOneWidget);
        expect(find.textContaining('milestone'), findsNothing);

        // Tap Due Today summary tile -> routes to active + dueDateFilter: 'today'
        await tester.tap(find.text('Due Today'));
        await tester.pumpAndSettle();
        expect(openTasksCalls, 1);
        expect(state.tasksController.state.viewFilter, 'active');
        expect(state.tasksController.state.dueDateFilter, 'today');

        // Tap Today's Plan -> routes to My Day
        await tester.tap(find.text("Today's Plan (My Day)"));
        await tester.pumpAndSettle();
        expect(openTasksCalls, 2);
        expect(state.tasksController.state.viewFilter, 'my_day');

        // Tap All Projects -> calls onOpenProjects
        await tester.tap(find.text('All Projects'));
        await tester.pumpAndSettle();
        expect(openProjectsCalls, 1);

        // Tap Project Progress item -> navigates to ProjectDetailScreen
        await tester.tap(find.text('Active Roadmap'));
        await tester.pumpAndSettle();
        expect(find.byType(ProjectDetailScreen), findsOneWidget);
      },
    );

    testWidgets(
      '4. TasksView honors requestedSubTab nonce to switch cleanly between Tasks and Projects tabs',
      (WidgetTester tester) async {
        final fixture = await tester.runAsync(() async {
          final db = AppDatabase(NativeDatabase.memory());
          await db.ensureInitialized();
          final tasksCtrl = TasksController(
            repository: DriftTasksRepository(db),
          );
          final projectsCtrl = ProjectsController(
            repository: DriftProjectsRepository(db),
          );
          await tasksCtrl.loadAll();
          await projectsCtrl.loadAll();
          return (
            db: db,
            tasksCtrl: tasksCtrl,
            projectsCtrl: projectsCtrl,
          );
        });

        final db = fixture!.db;
        final tasksCtrl = fixture.tasksCtrl;
        final projectsCtrl = fixture.projectsCtrl;
        addTearDown(
          () => closeDbWithPump(
            tester,
            db,
            disposeControllers: () {
              tasksCtrl.dispose();
              projectsCtrl.dispose();
            },
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: TasksView(
              controller: tasksCtrl,
              projectsController: projectsCtrl,
              requestedSubTab: (tabIndex: 1, nonce: 1),
            ),
          ),
        );
        // Fire ProjectsWorkspaceTab's post-frame loadAll, then let real-loop DB
        // complete before settling animations.
        await tester.pump();
        final loadWatch = Stopwatch()..start();
        while (projectsCtrl.state.isLoading) {
          if (loadWatch.elapsed > const Duration(seconds: 10)) {
            fail('ProjectsWorkspaceTab initial loadAll did not complete.');
          }
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        await tester.pumpAndSettle();

        expect(find.text('Projects'), findsWidgets);
        expect(find.text('Search projects...'), findsOneWidget);
      },
    );

    testWidgets(
      '5. DashboardTasksSection offers View Archived for archived-only stores and TasksView surfaces Due Today active filter context',
      (WidgetTester tester) async {
        final fixture = await tester.runAsync(() async {
          final db = AppDatabase(NativeDatabase.memory());
          await db.ensureInitialized();
          final state = _Stage6WidgetState(db: db);

          final tasksRepo = DriftTasksRepository(db);
          await tasksRepo.createTask(
            TaskEntity(
              id: 't-arch-only',
              title: 'Archived Only Item',
              isArchived: true,
            ),
          );
          await state.loadAllControllers();
          return (db: db, state: state);
        });

        final db = fixture!.db;
        final state = fixture.state;
        addTearDown(
          () => closeDbWithPump(
            tester,
            db,
            disposeControllers: state.dispose,
          ),
        );

        var openedTasks = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: ListView(
                children: [
                  DashboardTasksSection(
                    state: state,
                    onOpenTasks: () => openedTasks += 1,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('View Archived'), findsOneWidget);
        await tester.tap(find.text('View Archived'));
        await tester.pumpAndSettle();
        expect(openedTasks, 1);
        expect(state.tasksController.state.viewFilter, 'archived');

        // Verify TasksView active filter summary renders Due Today when routed from Dashboard
        state.tasksController.openDashboardFilter(
          viewFilter: 'active',
          dueDateFilter: 'today',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: TasksView(
              controller: state.tasksController,
              projectsController: state.projectsController,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Due Today'), findsOneWidget);
      },
    );
  });
}
