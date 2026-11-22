import '../../core/date/shared_date.dart';
import 'task_models.dart';

/// Domain contract for Task persistence and lifecycle management.
abstract class ITaskRepositoryContract {
  Future<List<TaskEntity>> getTasks({
    String? status,
    String? priority,
    String? projectId,
    bool? isOverdue,
  });

  Future<TaskEntity?> getTaskById(String id);
  Future<TaskEntity> createTask(TaskEntity task);
  Future<TaskEntity> updateTask(TaskEntity task);
  Future<void> updateTaskStatus(String id, String newStatus);
  Future<void> rescheduleTask(String id, CalendarDate? newDueDate);
  Future<void> postponeTaskDays(String id, int days);
  Future<void> deleteTask(String id);
  Future<List<TaskEntity>> getTasksForProject(String projectId);
  Future<List<DailyPlanningEntryEntity>> getDailyPlanningEntries({
    CalendarDate? planDate,
    String? taskId,
  });
  Future<DailyPlanningEntryEntity> upsertDailyPlanningEntry(
    DailyPlanningEntryEntity entry,
  );
  Future<void> deleteDailyPlanningEntry(String id);
  Future<void> deleteDailyPlanningEntriesForTask(String taskId);
}

/// Domain contract for Project persistence and lifecycle management.
abstract class IProjectRepositoryContract {
  Future<List<ProjectEntity>> getProjects({String? status});
  Future<ProjectEntity?> getProjectById(String id);
  Future<ProjectEntity> createProject(ProjectEntity project);
  Future<ProjectEntity> updateProject(ProjectEntity project);
  Future<void> deleteProject(String id);
}

/// Domain contract for Milestone persistence and progress tracking.
abstract class IMilestoneRepositoryContract {
  Future<List<MilestoneEntity>> getAllMilestones();
  Future<List<MilestoneEntity>> getMilestonesForProject(String projectId);
  Future<MilestoneEntity> createMilestone(MilestoneEntity milestone);
  Future<void> toggleMilestone(String milestoneId, bool isCompleted);
  Future<void> deleteMilestone(String milestoneId);
}

/// Cohesive Tasks Repository unifying Tasks, Projects, and Milestones.
///
/// Ensures single-unit atomic database transaction boundaries and consistent
/// relational integrity across Tasks and Projects.
abstract class ITasksRepository
    implements
        ITaskRepositoryContract,
        IProjectRepositoryContract,
        IMilestoneRepositoryContract {
  /// Retrieves a project along with its constituent tasks, milestones, and computed progress percentage.
  Future<
      ({
        ProjectEntity project,
        List<TaskEntity> tasks,
        List<MilestoneEntity> milestones,
        int progressPercentage,
      })?> getProjectWithProgress(String projectId);
}
