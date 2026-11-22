import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { CalendarDate } from './date';
import { calculateProjectProgressSummary } from './projectsEngine';
import {
  SharedDailyPlanningEntry,
  SharedMilestone,
  SharedProject,
  SharedTask,
} from './sharedFoundation';
import {
  createTaskRecord,
  DaywellTaskRecord,
  filterTasksForView,
} from './taskOperations';
import {
  buildProjectsOverviewSummary,
  buildTaskOverviewSummary,
} from './taskSummaries';

const TODAY_ISO = '2026-11-22';

type TestTask = DaywellTaskRecord & SharedTask;

function makeTask(
  id: string,
  title: string,
  overrides: Partial<TestTask> = {}
): TestTask {
  const res = createTaskRecord(
    {
      id,
      title,
      priority: overrides.priority ?? 'medium',
      status: overrides.status ?? 'not_started',
      dueDate: overrides.dueDate,
      scheduledDate: overrides.scheduledDate,
      projectId: overrides.projectId,
    },
    new Date('2026-11-20T06:00:00.000Z')
  );
  if (!res.ok) {
    throw new Error(`Fixture task failed: ${JSON.stringify(res.errors)}`);
  }
  return {
    ...res.task,
    ...overrides,
    status: overrides.status ?? res.task.status ?? 'not_started',
  } as TestTask;
}

function makeProject(
  id: string,
  title: string,
  overrides: Partial<SharedProject> = {}
): SharedProject {
  return {
    id,
    title,
    status: overrides.status ?? 'active',
    isArchived: overrides.isArchived ?? false,
    createdAt: overrides.createdAt ?? '2026-11-01T00:00:00.000Z',
    updatedAt: overrides.updatedAt ?? '2026-11-01T00:00:00.000Z',
    ...overrides,
  };
}

function makeMilestone(
  id: string,
  projectId: string,
  title: string,
  isCompleted = false
): SharedMilestone {
  return {
    id,
    projectId,
    title,
    isCompleted,
    createdAt: '2026-11-01T00:00:00.000Z',
  };
}

function makePlanEntry(
  id: string,
  taskId: string,
  planDate = TODAY_ISO,
  action: SharedDailyPlanningEntry['action'] = 'planned'
): SharedDailyPlanningEntry {
  return {
    id,
    taskId,
    planDate,
    action,
    createdAt: '2026-11-22T05:00:00.000Z',
  };
}

describe('Stage 6 — Task Dashboard & Progress Summaries (Web Domain & Integration Wiring)', () => {
  it('1. Computes overdue, dueToday, upcoming, completed, remaining, and My Day planned progress accurately while excluding archived and cancelled tasks', () => {
    const tasks: DaywellTaskRecord[] = [
      makeTask('t-overdue', 'Pay utilities', { dueDate: '2026-11-20' }),
      makeTask('t-due-today', 'Submit report', { dueDate: '2026-11-22' }),
      makeTask('t-sched-today', 'Call contractor', {
        scheduledDate: '2026-11-22',
      }),
      makeTask('t-upcoming', 'Plan sprint', { dueDate: '2026-11-25' }),
      makeTask('t-backlog', 'Clean garage'),
      makeTask('t-done-1', 'Morning walk', {
        status: 'completed',
        dueDate: '2026-11-22',
        completedAt: '2026-11-22T07:00:00.000Z',
      }),
      makeTask('t-done-2', 'Book flight', {
        status: 'completed',
        completedAt: '2026-11-21T10:00:00.000Z',
      }),
      makeTask('t-cancelled', 'Abandoned errand', {
        status: 'cancelled',
        dueDate: '2026-11-22',
      }),
      makeTask('t-archived-pending', 'Old pending task', {
        dueDate: '2026-11-19',
        isArchived: true,
      }),
      makeTask('t-archived-done', 'Old done task', {
        status: 'completed',
        isArchived: true,
      }),
    ];

    const entries: SharedDailyPlanningEntry[] = [
      makePlanEntry('dp-1', 't-due-today'),
      makePlanEntry('dp-2', 't-done-1'),
      makePlanEntry('dp-3', 't-overdue'),
    ];

    const overview = buildTaskOverviewSummary({
      tasks,
      dailyPlanningEntries: entries,
      todayIso: TODAY_ISO,
    });

    assert.strictEqual(overview.todayIso, TODAY_ISO);
    assert.strictEqual(overview.overdueCount, 1);
    assert.strictEqual(overview.dueTodayCount, 1);
    // todayViewCount counts due/scheduled <= today (t-overdue, t-due-today, t-sched-today)
    assert.strictEqual(overview.todayViewCount, 3);
    assert.strictEqual(overview.upcomingCount, 1);
    assert.strictEqual(overview.completedCount, 2);
    // Remaining pending active: t-overdue, t-due-today, t-sched-today, t-upcoming, t-backlog
    assert.strictEqual(overview.remainingCount, 5);
    assert.strictEqual(overview.totalActiveAndCompleted, 7);
    assert.strictEqual(overview.completionPercentage, Math.floor((2 * 100) / 7));
    assert.strictEqual(overview.archivedCount, 2);

    // My Day summary: 3 planned (t-due-today, t-done-1, t-overdue) -> 1 completed, 2 remaining
    assert.strictEqual(overview.todayPlan.planDateIso, TODAY_ISO);
    assert.strictEqual(overview.todayPlan.totalPlannedCount, 3);
    assert.strictEqual(overview.todayPlan.completedCount, 1);
    assert.strictEqual(overview.todayPlan.remainingCount, 2);
    assert.strictEqual(overview.todayPlan.progressPercentage, 33);

    // Filtered task navigation views agree with overview counts:
    const overdueList = filterTasksForView(tasks, {
      viewFilter: 'overdue',
      todayIso: TODAY_ISO,
    });
    assert.strictEqual(overdueList.length, overview.overdueCount);

    const dueTodayList = filterTasksForView(tasks, {
      viewFilter: 'active',
      dueDateFilter: 'today',
      todayIso: TODAY_ISO,
    });
    assert.strictEqual(dueTodayList.length, overview.dueTodayCount);

    const upcomingList = filterTasksForView(tasks, {
      viewFilter: 'upcoming',
      todayIso: TODAY_ISO,
    });
    assert.strictEqual(upcomingList.length, overview.upcomingCount);

    const completedList = filterTasksForView(tasks, {
      viewFilter: 'completed',
      todayIso: TODAY_ISO,
    });
    assert.strictEqual(completedList.length, overview.completedCount);

    const remainingList = filterTasksForView(tasks, {
      viewFilter: 'active',
      todayIso: TODAY_ISO,
    });
    assert.strictEqual(remainingList.length, overview.remainingCount);
  });

  it('2. Derives project progress consistently (task remaining, conditional milestones, archived exclusions, manual-completion guard)', () => {
    const projects: SharedProject[] = [
      makeProject('p-active', 'Website Launch', { status: 'active' }),
      makeProject('p-no-ms', 'Quick Cleanup', { status: 'active' }),
      makeProject('p-hold', 'Kitchen Remodel', {
        status: 'on_hold',
        description: 'Paused',
      }),
      makeProject('p-manual-with-pending', 'Mislabelled Completed', {
        status: 'completed',
      }),
      makeProject('p-manual-empty', 'Empty Finished Project', {
        status: 'completed',
      }),
      makeProject('p-archived', 'Archived Initiative', {
        status: 'active',
        isArchived: true,
      }),
    ];

    const tasks: TestTask[] = [
      makeTask('t1', 'Design', { projectId: 'p-active', status: 'completed' }),
      makeTask('t2', 'Build', {
        projectId: 'p-active',
        dueDate: '2026-11-20', // overdue
      }),
      makeTask('t3', 'Archived task in active project', {
        projectId: 'p-active',
        isArchived: true,
      }),
      makeTask('t4', 'Cancelled task in active project', {
        projectId: 'p-active',
        status: 'cancelled',
      }),
      makeTask('t5', 'Sweep', { projectId: 'p-no-ms', status: 'completed' }),
      makeTask('t6', 'Sort', { projectId: 'p-no-ms' }),
      makeTask('t7', 'Unfinished under completed status', {
        projectId: 'p-manual-with-pending',
      }),
      makeTask('t8', 'Task in archived project', {
        projectId: 'p-archived',
      }),
    ];

    const milestones: SharedMilestone[] = [
      makeMilestone('m1', 'p-active', 'Alpha Ready', true),
      makeMilestone('m2', 'p-active', 'Public Launch', false),
      makeMilestone('m3', 'p-archived', 'Old Milestone', true),
    ];

    const summary = buildProjectsOverviewSummary({
      projects,
      tasks,
      milestones,
      todayIso: TODAY_ISO,
    });

    // Archived project excluded by default
    assert.strictEqual(summary.totalProjectsCount, 5);
    assert.strictEqual(summary.activeProjectsCount, 2);
    assert.strictEqual(summary.onHoldProjectsCount, 1);
    assert.strictEqual(summary.completedProjectsCount, 2);
    assert.strictEqual(
      summary.projects.some((item) => item.project.id === 'p-archived'),
      false
    );

    const activeItem = summary.projects.find(
      (i) => i.project.id === 'p-active'
    )!;
    assert.strictEqual(activeItem.totalTasks, 2);
    assert.strictEqual(activeItem.completedTasks, 1);
    assert.strictEqual(activeItem.remainingTasks, 1);
    assert.strictEqual(activeItem.overdueTasks, 1);
    assert.strictEqual(activeItem.hasMilestones, true);
    assert.strictEqual(activeItem.totalMilestones, 2);
    assert.strictEqual(activeItem.completedMilestones, 1);
    assert.strictEqual(activeItem.remainingMilestones, 1);
    // (1 task + 1 milestone) / (2 tasks + 2 milestones) = 50%
    assert.strictEqual(activeItem.displayPercentage, 50);

    const noMsItem = summary.projects.find((i) => i.project.id === 'p-no-ms')!;
    assert.strictEqual(noMsItem.hasMilestones, false);
    assert.strictEqual(noMsItem.totalMilestones, 0);
    assert.strictEqual(noMsItem.totalTasks, 2);
    assert.strictEqual(noMsItem.completedTasks, 1);
    assert.strictEqual(noMsItem.remainingTasks, 1);
    assert.strictEqual(noMsItem.displayPercentage, 50);

    // Project marked completed still containing unfinished work stays at 0% derived
    const manualPendingItem = summary.projects.find(
      (i) => i.project.id === 'p-manual-with-pending'
    )!;
    assert.strictEqual(manualPendingItem.remainingTasks, 1);
    assert.strictEqual(manualPendingItem.displayPercentage, 0);

    // Manually completed project with 0 tasks and 0 milestones reports 100%
    const manualEmptyItem = summary.projects.find(
      (i) => i.project.id === 'p-manual-empty'
    )!;
    assert.strictEqual(manualEmptyItem.totalTasks, 0);
    assert.strictEqual(manualEmptyItem.displayPercentage, 100);

    // Aggregate excludes archived project & archived/cancelled tasks:
    // p-active (2 tasks) + p-no-ms (2 tasks) + p-manual-with-pending (1 task) = 5
    assert.strictEqual(summary.totalTasks, 5);
    assert.strictEqual(summary.completedTasks, 2);
    assert.strictEqual(summary.remainingTasks, 3);
    assert.strictEqual(summary.totalMilestones, 2);
    assert.strictEqual(summary.completedMilestones, 1);

    // Explicitly opting into archived content includes p-archived + archived tasks
    const withArchived = buildProjectsOverviewSummary({
      projects,
      tasks,
      milestones,
      todayIso: TODAY_ISO,
      includeArchivedProjects: true,
      includeArchivedTasks: true,
    });
    assert.strictEqual(withArchived.totalProjectsCount, 6);
    assert.strictEqual(
      withArchived.projects.some((i) => i.project.id === 'p-archived'),
      true
    );
    const activeWithArchivedTasks = withArchived.projects.find(
      (i) => i.project.id === 'p-active'
    )!;
    assert.strictEqual(activeWithArchivedTasks.totalTasks, 3);

    // Verify calculateProjectProgressSummary excludes archived tasks by default
    const trackingSummary = calculateProjectProgressSummary({
      project: projects[0],
      blocks: [],
      records: [],
      linkedTasks: tasks,
      milestones,
      asOfDate: CalendarDate.parse(TODAY_ISO),
    });
    assert.strictEqual(trackingSummary.linkedTasksTotal, 2);
    assert.strictEqual(trackingSummary.linkedTasksCompleted, 1);
  });

  it('3. Respects tracking block primaryMetric override when present while preserving task/milestone counts', () => {
    const project = makeProject('p-tracked', 'Book Reading');
    const summaryWithPrimary = calculateProjectProgressSummary({
      project,
      blocks: [],
      records: [],
      linkedTasks: [makeTask('t1', 'Read ch1', { projectId: 'p-tracked' })],
      milestones: [],
      asOfDate: CalendarDate.parse(TODAY_ISO),
    });

    const enrichedSummary = {
      ...summaryWithPrimary,
      primaryMetric: {
        blockId: 'blk-pages',
        blockType: 'counter' as const,
        title: 'Pages Read',
        isArchived: false,
        loggedTotal: 150,
        targetValue: 200,
        progressPercent: 75,
        todayTotal: 20,
        dailyTotalsByDate: {},
        completedCount: 0,
        totalCount: 0,
        plannedDurationMinutes: 0,
        actualLoggedDurationMinutes: 0,
        itemTotals: {},
        groupMetrics: [],
      },
      overallPercentage: 75,
    };

    const overview = buildProjectsOverviewSummary({
      projects: [project],
      tasks: [makeTask('t1', 'Read ch1', { projectId: 'p-tracked' })],
      milestones: [],
      trackingSummaries: { 'p-tracked': enrichedSummary },
      todayIso: TODAY_ISO,
    });

    assert.strictEqual(overview.projects.length, 1);
    assert.strictEqual(overview.projects[0].displayPercentage, 75);
    assert.strictEqual(overview.projects[0].primaryMetricTitle, 'Pages Read');
    assert.strictEqual(overview.projects[0].totalTasks, 1);
    assert.strictEqual(overview.projects[0].remainingTasks, 1);
    assert.strictEqual(overview.projects[0].hasMilestones, false);
  });

  it('4. Keeps Stage 6 domain pure (no React/DOM imports) and verifies Web dashboard & project views wire Stage 6 summaries without analytics tables', () => {
    const root = process.cwd();
    const summaryDomainSrc = fs.readFileSync(
      path.join(root, 'src/domain/taskSummaries.ts'),
      'utf8'
    );
    assert.doesNotMatch(
      summaryDomainSrc,
      /from\s+['"]react|window\.|document\.|localStorage/
    );

    const appSrc = fs.readFileSync(path.join(root, 'src/App.tsx'), 'utf8');
    assert.match(appSrc, /buildTaskOverviewSummary/);
    assert.match(appSrc, /buildProjectsOverviewSummary/);
    assert.match(appSrc, /openTasksFromDashboard/);
    assert.match(appSrc, /openProjectsFromDashboard/);
    assert.match(appSrc, /Tasks Overview/);
    assert.match(appSrc, /Project Progress/);
    assert.match(appSrc, /Today(&apos;|')s Plan \(My Day\)/);

    const tasksModuleSrc = fs.readFileSync(
      path.join(root, 'src/components/DaywellTasksModule.tsx'),
      'utf8'
    );
    assert.match(tasksModuleSrc, /dueDateFilter\?:\s*TaskDueDateFilter\s*\|\s*''/);
    assert.match(tasksModuleSrc, /planDate\?:\s*string/);
    assert.match(tasksModuleSrc, /setDueDateFilter\(requestedFilter\.dueDateFilter/);

    assert.match(appSrc, /listAllMilestones/);

    const projectsServiceSrc = fs.readFileSync(
      path.join(root, 'src/services/projectsService.ts'),
      'utf8'
    );
    assert.match(projectsServiceSrc, /listAllMilestones/);

    const workspaceSrc = fs.readFileSync(
      path.join(root, 'src/components/projects/ProjectsWorkspaceView.tsx'),
      'utf8'
    );
    assert.match(workspaceSrc, /taskRemaining/);
    assert.match(workspaceSrc, /remaining/);
    assert.doesNotMatch(workspaceSrc, /taskRemaining\}\s+left/);

    const detailSrc = fs.readFileSync(
      path.join(root, 'src/components/projects/ProjectDetailView.tsx'),
      'utf8'
    );
    assert.match(detailSrc, /} remaining`/);
    assert.match(detailSrc, /Marked complete/);
    assert.match(appSrc, /View Archived/);
    assert.match(appSrc, /overdueTasks > 0/);
    assert.match(appSrc, /Tracking: \{item\.primaryMetricTitle\}/);
  });

  it('5. Handles archived-only tasks cleanly in overview and includes archived tasks only when explicitly viewing an archived project detail', async () => {
    const { projectsService } = await import('../services/projectsService');

    const archivedOnlyTask = makeTask('t-only-arch', 'Old Archived Task', {
      isArchived: true,
    });
    const archivedOnlyOverview = buildTaskOverviewSummary({
      tasks: [archivedOnlyTask],
      todayIso: TODAY_ISO,
    });
    assert.strictEqual(archivedOnlyOverview.totalActiveAndCompleted, 0);
    assert.strictEqual(archivedOnlyOverview.archivedCount, 1);

    const store = new Map<string, string>();
    const prevWindow = (globalThis as any).window;
    const prevLocalStorage = (globalThis as any).localStorage;
    (globalThis as any).localStorage = {
      getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
      setItem: (k: string, v: string) => void store.set(k, String(v)),
      removeItem: (k: string) => void store.delete(k),
      clear: () => void store.clear(),
    };
    (globalThis as any).window = {
      dispatchEvent: () => true,
      CustomEvent: class CustomEvent {
        type: string;
        constructor(type: string) {
          this.type = type;
        }
      },
    };

    try {
      const activeProj = projectsService.createProjectWithBlocks({
        title: 'Active Proj',
        status: 'active',
        blocks: [],
      });
      const archivedProj = projectsService.createProjectWithBlocks({
        title: 'Archived Proj',
        status: 'active',
        blocks: [],
      });
      projectsService.setProjectArchived(archivedProj.id, true);

      const tActive = makeTask('ta', 'Active Task', { projectId: activeProj.id });
      const tActiveArch = makeTask('taa', 'Archived Task in Active Proj', {
        projectId: activeProj.id,
        isArchived: true,
      });
      const tArchProjDone = makeTask('tapd', 'Done in Archived Proj', {
        projectId: archivedProj.id,
        status: 'completed',
        isArchived: true,
      });
      const tArchProjOpen = makeTask('tapo', 'Open in Archived Proj', {
        projectId: archivedProj.id,
        isArchived: true,
      });
      store.set(
        'daywell_tasks',
        JSON.stringify([tActive, tActiveArch, tArchProjDone, tArchProjOpen])
      );

      // Active project detail keeps archived task excluded
      const activeSnap = projectsService.getProjectDetailSnapshot(activeProj.id)!;
      assert.strictEqual(activeSnap.derivedProgress.totalTasks, 1);
      assert.strictEqual(activeSnap.summary.linkedTasksTotal, 1);

      // Explicitly opening archived project detail includes its archived tasks
      const archivedSnap = projectsService.getProjectDetailSnapshot(archivedProj.id)!;
      assert.strictEqual(archivedSnap.derivedProgress.totalTasks, 2);
      assert.strictEqual(archivedSnap.derivedProgress.completedTasks, 1);
      assert.strictEqual(archivedSnap.derivedProgress.percentage, 50);
      assert.strictEqual(archivedSnap.summary.linkedTasksTotal, 2);
      assert.strictEqual(
        archivedSnap.sectionsView.unsectionedTasks.length,
        2
      );
    } finally {
      (globalThis as any).window = prevWindow;
      (globalThis as any).localStorage = prevLocalStorage;
    }
  });
});
