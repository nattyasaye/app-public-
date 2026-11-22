import { CalendarDate } from './date';
import {
  buildDailyPlanSnapshot,
  DailyPlanSnapshot,
} from './dailyPlanningOperations';
import {
  calculateDerivedTaskMilestoneProgress,
  DerivedTaskMilestoneProgress,
  ProjectMilestoneInput,
  ProjectProgressSummary,
} from './projectsEngine';
import {
  SharedDailyPlanningEntry,
  SharedProject,
} from './sharedFoundation';
import {
  computeTaskTabCounts,
  DaywellTaskRecord,
  isTaskCompleted,
  resolveEffectiveTaskStatus,
  TaskTabCounts,
} from './taskOperations';

export interface TodayPlanOverviewSummary {
  planDateIso: string;
  totalPlannedCount: number;
  completedCount: number;
  remainingCount: number;
  progressPercentage: number;
  carryForwardCount: number;
}

export interface TaskOverviewSummary {
  todayIso: string;
  overdueCount: number;
  dueTodayCount: number;
  todayViewCount: number;
  upcomingCount: number;
  completedCount: number;
  remainingCount: number;
  totalActiveAndCompleted: number;
  completionPercentage: number;
  archivedCount: number;
  tabCounts: TaskTabCounts;
  todayPlan: TodayPlanOverviewSummary;
  dailyPlanSnapshot: DailyPlanSnapshot;
}

export interface ProjectProgressOverviewItem {
  project: SharedProject;
  totalTasks: number;
  completedTasks: number;
  remainingTasks: number;
  overdueTasks: number;
  totalMilestones: number;
  completedMilestones: number;
  remainingMilestones: number;
  hasMilestones: boolean;
  derivedProgress: DerivedTaskMilestoneProgress;
  trackingSummary?: ProjectProgressSummary;
  primaryMetricTitle?: string;
  primaryPercentage?: number;
  displayPercentage: number;
}

export interface ProjectsOverviewSummary {
  projects: ProjectProgressOverviewItem[];
  totalProjectsCount: number;
  activeProjectsCount: number;
  onHoldProjectsCount: number;
  completedProjectsCount: number;
  totalTasks: number;
  completedTasks: number;
  remainingTasks: number;
  totalMilestones: number;
  completedMilestones: number;
}

export function buildTaskOverviewSummary(params: {
  tasks: readonly DaywellTaskRecord[];
  dailyPlanningEntries?: readonly SharedDailyPlanningEntry[];
  todayIso?: string;
}): TaskOverviewSummary {
  const today = params.todayIso
    ? CalendarDate.tryParse(params.todayIso)?.toIsoString() ??
      CalendarDate.today().toIsoString()
    : CalendarDate.today().toIsoString();
  const entries = params.dailyPlanningEntries ?? [];

  const tabCounts = computeTaskTabCounts(params.tasks, today);

  let dueTodayCount = 0;
  for (const task of params.tasks) {
    if (task.isArchived) continue;
    const status = resolveEffectiveTaskStatus(task);
    if (status === 'completed' || status === 'cancelled') continue;
    if (task.dueDate === today) {
      dueTodayCount += 1;
    }
  }

  const remainingCount = tabCounts.activePendingCount;
  const completedCount = tabCounts.completedCount;
  const totalActiveAndCompleted = remainingCount + completedCount;
  const completionPercentage =
    totalActiveAndCompleted === 0
      ? 0
      : Math.min(
          100,
          Math.max(
            0,
            Math.floor((completedCount * 100) / totalActiveAndCompleted)
          )
        );

  const dailyPlanSnapshot = buildDailyPlanSnapshot(
    params.tasks,
    entries,
    today,
    today
  );

  return {
    todayIso: today,
    overdueCount: tabCounts.overdueCount,
    dueTodayCount,
    todayViewCount: tabCounts.todayCount,
    upcomingCount: tabCounts.upcomingCount,
    completedCount,
    remainingCount,
    totalActiveAndCompleted,
    completionPercentage,
    archivedCount: tabCounts.archivedCount,
    tabCounts,
    todayPlan: {
      planDateIso: today,
      totalPlannedCount: dailyPlanSnapshot.totalPlannedCount,
      completedCount: dailyPlanSnapshot.completedCount,
      remainingCount: dailyPlanSnapshot.remainingCount,
      progressPercentage: dailyPlanSnapshot.progressPercentage,
      carryForwardCount: dailyPlanSnapshot.carryForwardSuggestions.length,
    },
    dailyPlanSnapshot,
  };
}

const PROJECT_STATUS_SORT_RANK: Record<SharedProject['status'], number> = {
  active: 0,
  on_hold: 1,
  completed: 2,
};

export function buildProjectsOverviewSummary(params: {
  projects: readonly SharedProject[];
  tasks: readonly DaywellTaskRecord[];
  milestones?: readonly ProjectMilestoneInput[];
  trackingSummaries?: Readonly<Record<string, ProjectProgressSummary>>;
  todayIso?: string;
  includeArchivedProjects?: boolean;
  includeArchivedTasks?: boolean;
}): ProjectsOverviewSummary {
  const includeArchivedProjects = params.includeArchivedProjects === true;
  const includeArchivedTasks = params.includeArchivedTasks === true;
  const today = params.todayIso
    ? CalendarDate.tryParse(params.todayIso)?.toIsoString() ??
      CalendarDate.today().toIsoString()
    : CalendarDate.today().toIsoString();
  const milestones = params.milestones ?? [];

  const filteredProjects = params.projects.filter(
    (p) => includeArchivedProjects || !p.isArchived
  );

  let activeProjectsCount = 0;
  let onHoldProjectsCount = 0;
  let completedProjectsCount = 0;
  let totalTasksAggregate = 0;
  let completedTasksAggregate = 0;
  let totalMilestonesAggregate = 0;
  let completedMilestonesAggregate = 0;

  const items: ProjectProgressOverviewItem[] = filteredProjects.map((project) => {
    if (!project.isArchived) {
      if (project.status === 'active') activeProjectsCount += 1;
      else if (project.status === 'on_hold') onHoldProjectsCount += 1;
      else if (project.status === 'completed') completedProjectsCount += 1;
    }

    const projectTasks = params.tasks.filter((t) => {
      if (t.projectId !== project.id) return false;
      if (!includeArchivedTasks && t.isArchived) return false;
      if (resolveEffectiveTaskStatus(t) === 'cancelled') return false;
      return true;
    });

    const totalTasks = projectTasks.length;
    const completedTasks = projectTasks.filter((t) => isTaskCompleted(t)).length;
    const remainingTasks = Math.max(0, totalTasks - completedTasks);
    const overdueTasks = projectTasks.filter(
      (t) => !isTaskCompleted(t) && Boolean(t.dueDate && t.dueDate < today)
    ).length;

    const projectMilestones = milestones.filter(
      (m) => m.projectId === project.id
    );
    const totalMilestones = projectMilestones.length;
    const completedMilestones = projectMilestones.filter(
      (m) => m.isCompleted
    ).length;
    const remainingMilestones = Math.max(
      0,
      totalMilestones - completedMilestones
    );
    const hasMilestones = totalMilestones > 0;

    const derivedProgress = calculateDerivedTaskMilestoneProgress({
      totalTasks,
      completedTasks,
      totalMilestones,
      completedMilestones,
      isProjectManuallyCompleted:
        project.status === 'completed' &&
        totalTasks === 0 &&
        totalMilestones === 0,
    });

    const trackingSummary = params.trackingSummaries?.[project.id];
    const primaryPercentage =
      trackingSummary?.primaryMetric &&
      trackingSummary.overallPercentage !== undefined
        ? Math.round(trackingSummary.overallPercentage)
        : undefined;
    const displayPercentage = primaryPercentage ?? derivedProgress.percentage;

    totalTasksAggregate += totalTasks;
    completedTasksAggregate += completedTasks;
    totalMilestonesAggregate += totalMilestones;
    completedMilestonesAggregate += completedMilestones;

    return {
      project,
      totalTasks,
      completedTasks,
      remainingTasks,
      overdueTasks,
      totalMilestones,
      completedMilestones,
      remainingMilestones,
      hasMilestones,
      derivedProgress,
      trackingSummary,
      primaryMetricTitle: trackingSummary?.primaryMetric?.title,
      primaryPercentage,
      displayPercentage,
    };
  });

  items.sort((a, b) => {
    const rankA = PROJECT_STATUS_SORT_RANK[a.project.status] ?? 3;
    const rankB = PROJECT_STATUS_SORT_RANK[b.project.status] ?? 3;
    if (rankA !== rankB) return rankA - rankB;
    if (a.overdueTasks !== b.overdueTasks) {
      return b.overdueTasks - a.overdueTasks;
    }
    if ((a.remainingTasks > 0) !== (b.remainingTasks > 0)) {
      return a.remainingTasks > 0 ? -1 : 1;
    }
    return a.project.title.localeCompare(b.project.title);
  });

  return {
    projects: items,
    totalProjectsCount: items.length,
    activeProjectsCount,
    onHoldProjectsCount,
    completedProjectsCount,
    totalTasks: totalTasksAggregate,
    completedTasks: completedTasksAggregate,
    remainingTasks: Math.max(0, totalTasksAggregate - completedTasksAggregate),
    totalMilestones: totalMilestonesAggregate,
    completedMilestones: completedMilestonesAggregate,
  };
}
