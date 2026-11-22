import '../../core/date/shared_date.dart';
import '../projects/progress_engine.dart';
import '../projects/project_models.dart';
import './daily_planning_engine.dart';
import './task_models.dart';

/// Pure Stage 6 operational overview of today's planned tasks (My Day).
class TodayPlanOverviewSummary {
  final CalendarDate planDate;
  final int totalPlannedCount;
  final int completedCount;
  final int remainingCount;
  final int progressPercentage;
  final int carryForwardCount;

  const TodayPlanOverviewSummary({
    required this.planDate,
    required this.totalPlannedCount,
    required this.completedCount,
    required this.remainingCount,
    required this.progressPercentage,
    required this.carryForwardCount,
  });
}

/// Pure Stage 6 operational summary across all non-archived, non-cancelled tasks.
class TaskOverviewSummary {
  final CalendarDate today;
  final int overdueCount;
  final int dueTodayCount;
  final int todayViewCount;
  final int upcomingCount;
  final int completedCount;
  final int remainingCount;
  final int totalActiveAndCompleted;
  final int completionPercentage;
  final int archivedCount;
  final TodayPlanOverviewSummary todayPlan;
  final DailyPlanSnapshot dailyPlanSnapshot;

  const TaskOverviewSummary({
    required this.today,
    required this.overdueCount,
    required this.dueTodayCount,
    required this.todayViewCount,
    required this.upcomingCount,
    required this.completedCount,
    required this.remainingCount,
    required this.totalActiveAndCompleted,
    required this.completionPercentage,
    required this.archivedCount,
    required this.todayPlan,
    required this.dailyPlanSnapshot,
  });
}

/// Consistent derived progress and task/milestone counts for a single project.
class ProjectProgressOverviewItem {
  final ProjectEntity project;
  final int totalTasks;
  final int completedTasks;
  final int remainingTasks;
  final int overdueTasks;
  final int totalMilestones;
  final int completedMilestones;
  final int remainingMilestones;
  final bool hasMilestones;
  final int derivedPercentage;
  final ProjectProgressSummary? trackingSummary;
  final String? primaryMetricTitle;
  final int? primaryPercentage;
  final int displayPercentage;

  const ProjectProgressOverviewItem({
    required this.project,
    required this.totalTasks,
    required this.completedTasks,
    required this.remainingTasks,
    required this.overdueTasks,
    required this.totalMilestones,
    required this.completedMilestones,
    required this.remainingMilestones,
    required this.hasMilestones,
    required this.derivedPercentage,
    this.trackingSummary,
    this.primaryMetricTitle,
    this.primaryPercentage,
    required this.displayPercentage,
  });
}

/// Aggregated Stage 6 summary across non-archived projects (unless explicitly included).
class ProjectsOverviewSummary {
  final List<ProjectProgressOverviewItem> projects;
  final int totalProjectsCount;
  final int activeProjectsCount;
  final int onHoldProjectsCount;
  final int completedProjectsCount;
  final int totalTasks;
  final int completedTasks;
  final int remainingTasks;
  final int totalMilestones;
  final int completedMilestones;

  const ProjectsOverviewSummary({
    required this.projects,
    required this.totalProjectsCount,
    required this.activeProjectsCount,
    required this.onHoldProjectsCount,
    required this.completedProjectsCount,
    required this.totalTasks,
    required this.completedTasks,
    required this.remainingTasks,
    required this.totalMilestones,
    required this.completedMilestones,
  });
}

/// Deterministic, zero-persistence Stage 6 calculation engine.
/// Mirrors `src/domain/taskSummaries.ts` 1-to-1 for cross-platform consistency.
class TaskSummaryEngine {
  static const Map<String, int> _projectStatusRank = {
    'active': 0,
    'on_hold': 1,
    'completed': 2,
  };

  static bool _isCancelledOrCompleted(TaskEntity task) =>
      task.isCompleted ||
      task.status == 'completed' ||
      task.status == 'cancelled';

  static TaskOverviewSummary buildTaskOverview({
    required List<TaskEntity> tasks,
    List<DailyPlanningEntryEntity> dailyPlanningEntries = const [],
    CalendarDate? today,
  }) {
    final resolvedToday = today ?? CalendarDate.today();

    var overdueCount = 0;
    var dueTodayCount = 0;
    var todayViewCount = 0;
    var upcomingCount = 0;
    var completedCount = 0;
    var remainingCount = 0;
    var archivedCount = 0;

    for (final task in tasks) {
      if (task.isArchived) {
        archivedCount += 1;
        continue;
      }
      if (task.isCompleted || task.status == 'completed') {
        completedCount += 1;
        continue;
      }
      if (task.status == 'cancelled') {
        continue;
      }

      remainingCount += 1;

      if (task.dueDate != null && task.dueDate!.isBefore(resolvedToday)) {
        overdueCount += 1;
      }
      if (task.dueDate != null && task.dueDate == resolvedToday) {
        dueTodayCount += 1;
      }

      final dueTodayOrEarlier =
          task.dueDate != null && !task.dueDate!.isAfter(resolvedToday);
      final scheduledTodayOrEarlier = task.scheduledDate != null &&
          !task.scheduledDate!.isAfter(resolvedToday);
      if (dueTodayOrEarlier || scheduledTodayOrEarlier) {
        todayViewCount += 1;
      }

      final dueLater =
          task.dueDate != null && task.dueDate!.isAfter(resolvedToday);
      final scheduledLater = task.scheduledDate != null &&
          task.scheduledDate!.isAfter(resolvedToday);
      if (dueLater || scheduledLater) {
        upcomingCount += 1;
      }
    }

    final totalActiveAndCompleted = remainingCount + completedCount;
    final completionPercentage = totalActiveAndCompleted == 0
        ? 0
        : ((completedCount * 100) ~/ totalActiveAndCompleted).clamp(0, 100);

    final dailyPlanSnapshot = DailyPlanningEngine.buildSnapshot(
      tasks: tasks,
      entries: dailyPlanningEntries,
      selectedDate: resolvedToday,
      today: resolvedToday,
    );

    return TaskOverviewSummary(
      today: resolvedToday,
      overdueCount: overdueCount,
      dueTodayCount: dueTodayCount,
      todayViewCount: todayViewCount,
      upcomingCount: upcomingCount,
      completedCount: completedCount,
      remainingCount: remainingCount,
      totalActiveAndCompleted: totalActiveAndCompleted,
      completionPercentage: completionPercentage,
      archivedCount: archivedCount,
      todayPlan: TodayPlanOverviewSummary(
        planDate: resolvedToday,
        totalPlannedCount: dailyPlanSnapshot.totalPlannedCount,
        completedCount: dailyPlanSnapshot.completedCount,
        remainingCount: dailyPlanSnapshot.remainingCount,
        progressPercentage: dailyPlanSnapshot.progressPercentage,
        carryForwardCount: dailyPlanSnapshot.carryForwardSuggestions.length,
      ),
      dailyPlanSnapshot: dailyPlanSnapshot,
    );
  }

  static ProjectsOverviewSummary buildProjectsOverview({
    required List<ProjectEntity> projects,
    required List<TaskEntity> tasks,
    List<MilestoneEntity> milestones = const [],
    Map<String, ProjectProgressSummary> trackingSummaries = const {},
    CalendarDate? today,
    bool includeArchivedProjects = false,
    bool includeArchivedTasks = false,
  }) {
    final resolvedToday = today ?? CalendarDate.today();

    final includedProjects = projects
        .where((p) => includeArchivedProjects || !p.isArchived)
        .toList(growable: false);

    var activeProjectsCount = 0;
    var onHoldProjectsCount = 0;
    var completedProjectsCount = 0;
    var totalTasksAggregate = 0;
    var completedTasksAggregate = 0;
    var totalMilestonesAggregate = 0;
    var completedMilestonesAggregate = 0;

    final items = <ProjectProgressOverviewItem>[];

    for (final project in includedProjects) {
      if (!project.isArchived) {
        if (project.status == 'active') {
          activeProjectsCount += 1;
        } else if (project.status == 'on_hold') {
          onHoldProjectsCount += 1;
        } else if (project.status == 'completed') {
          completedProjectsCount += 1;
        }
      }

      final projectTasks = tasks.where((t) {
        if (t.projectId != project.id) return false;
        if (!includeArchivedTasks && t.isArchived) return false;
        if (t.status == 'cancelled') return false;
        return true;
      }).toList(growable: false);

      final totalTasks = projectTasks.length;
      final completedTasks = projectTasks
          .where((t) => t.isCompleted || t.status == 'completed')
          .length;
      final remainingTasks = (totalTasks - completedTasks).clamp(0, totalTasks);
      final overdueTasks = projectTasks
          .where(
            (t) =>
                !_isCancelledOrCompleted(t) &&
                t.dueDate != null &&
                t.dueDate!.isBefore(resolvedToday),
          )
          .length;

      final projectMilestones = milestones
          .where((m) => m.projectId == project.id)
          .toList(growable: false);
      final totalMilestones = projectMilestones.length;
      final completedMilestones =
          projectMilestones.where((m) => m.isCompleted).length;
      final remainingMilestones =
          (totalMilestones - completedMilestones).clamp(0, totalMilestones);
      final hasMilestones = totalMilestones > 0;

      final derivedPercentage = ProgressEngine.calculateProgressPercentage(
        totalTasks: totalTasks,
        completedTasks: completedTasks,
        totalMilestones: totalMilestones,
        completedMilestones: completedMilestones,
        isProjectManuallyCompleted: project.status == 'completed' &&
            totalTasks == 0 &&
            totalMilestones == 0,
      );

      final trackingSummary = trackingSummaries[project.id];
      final int? primaryPercentage = (trackingSummary?.primaryMetric != null &&
              trackingSummary?.overallPercentage != null)
          ? trackingSummary!.overallPercentage!.round()
          : null;
      final displayPercentage = primaryPercentage ?? derivedPercentage;

      totalTasksAggregate += totalTasks;
      completedTasksAggregate += completedTasks;
      totalMilestonesAggregate += totalMilestones;
      completedMilestonesAggregate += completedMilestones;

      items.add(
        ProjectProgressOverviewItem(
          project: project,
          totalTasks: totalTasks,
          completedTasks: completedTasks,
          remainingTasks: remainingTasks,
          overdueTasks: overdueTasks,
          totalMilestones: totalMilestones,
          completedMilestones: completedMilestones,
          remainingMilestones: remainingMilestones,
          hasMilestones: hasMilestones,
          derivedPercentage: derivedPercentage,
          trackingSummary: trackingSummary,
          primaryMetricTitle: trackingSummary?.primaryMetric?.title,
          primaryPercentage: primaryPercentage,
          displayPercentage: displayPercentage,
        ),
      );
    }

    items.sort((a, b) {
      final rankA = _projectStatusRank[a.project.status] ?? 3;
      final rankB = _projectStatusRank[b.project.status] ?? 3;
      if (rankA != rankB) return rankA.compareTo(rankB);
      if (a.overdueTasks != b.overdueTasks) {
        return b.overdueTasks.compareTo(a.overdueTasks);
      }
      final aHasRem = a.remainingTasks > 0;
      final bHasRem = b.remainingTasks > 0;
      if (aHasRem != bHasRem) {
        return aHasRem ? -1 : 1;
      }
      return a.project.title.compareTo(b.project.title);
    });

    final remainingTasksAggregate =
        (totalTasksAggregate - completedTasksAggregate)
            .clamp(0, totalTasksAggregate);

    return ProjectsOverviewSummary(
      projects: List<ProjectProgressOverviewItem>.unmodifiable(items),
      totalProjectsCount: items.length,
      activeProjectsCount: activeProjectsCount,
      onHoldProjectsCount: onHoldProjectsCount,
      completedProjectsCount: completedProjectsCount,
      totalTasks: totalTasksAggregate,
      completedTasks: completedTasksAggregate,
      remainingTasks: remainingTasksAggregate,
      totalMilestones: totalMilestonesAggregate,
      completedMilestones: completedMilestonesAggregate,
    );
  }
}
