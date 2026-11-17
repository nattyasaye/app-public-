import 'dart:convert';
import 'package:drift/drift.dart';
import '../../core/date/shared_date.dart';
import '../database/app_database.dart';
import '../../domain/tasks/task_models.dart';
import '../../domain/tasks/task_contracts.dart';
import '../../domain/projects/progress_engine.dart';

export '../../domain/tasks/task_models.dart';
export '../../domain/tasks/task_contracts.dart';

/// Drift SQLite implementation of [ITasksRepository].
///
/// Unifies Task, Project, and Milestone persistence into a single atomic
/// relational persistence unit under Drift SQLite schema v8.
class DriftTasksRepository implements ITasksRepository {
  final AppDatabase _db;

  DriftTasksRepository(this._db);

  static List<({String title, bool done})> _decodeSubtasks(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => (
                title: (m['title'] ?? '').toString(),
                done: m['done'] == true,
              ))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static String _encodeSubtasks(List<({String title, bool done})> subtasks) {
    return jsonEncode(
      subtasks
          .map((s) => {'title': s.title, 'done': s.done})
          .toList(growable: false),
    );
  }

  static List<String> _decodeLabels(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((e) => e.toString()).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  TaskEntity _mapRowToTaskEntity(Task r) {
    return TaskEntity(
      id: r.id,
      title: r.title,
      description: r.description,
      status: r.status,
      priority: r.priority,
      dueDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(r.dueDate),
      scheduledDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        r.scheduledDate,
      ),
      estimatedDurationMinutes: r.estimatedDurationMinutes,
      projectId: r.projectId,
      milestoneId: r.milestoneId,
      subtasks: _decodeSubtasks(r.subtasksJson),
      labels: _decodeLabels(r.labelsJson),
      isPinned: r.isPinned,
      isMyDay: r.isMyDay,
      recurrenceRule: r.recurrenceRule,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    );
  }

  // ==========================================================================
  // ITaskRepositoryContract
  // ==========================================================================

  @override
  Future<List<TaskEntity>> getTasks({
    String? status,
    String? priority,
    String? projectId,
    bool? isOverdue,
  }) async {
    final query = _db.select(_db.tasks);

    if (status != null) {
      query.where((tbl) => tbl.status.equals(status));
    }
    if (priority != null) {
      query.where((tbl) => tbl.priority.equals(priority));
    }
    if (projectId != null) {
      query.where((tbl) => tbl.projectId.equals(projectId));
    }
    if (isOverdue == true) {
      final todayIso = CalendarDate.today().toIsoString();
      query.where((tbl) =>
          tbl.dueDate.isNotNull() &
          tbl.dueDate.isSmallerThanValue(todayIso) &
          tbl.status.isNotIn(['completed', 'cancelled']));
    }

    query.orderBy([
      (tbl) => OrderingTerm.desc(tbl.isPinned),
      (tbl) => OrderingTerm.asc(tbl.dueDate),
      (tbl) => OrderingTerm.desc(tbl.createdAt),
    ]);
    final rows = await query.get();
    return rows.map(_mapRowToTaskEntity).toList();
  }

  @override
  Future<TaskEntity?> getTaskById(String id) async {
    final query = _db.select(_db.tasks)..where((tbl) => tbl.id.equals(id));
    final r = await query.getSingleOrNull();
    if (r == null) return null;
    return _mapRowToTaskEntity(r);
  }

  @override
  Future<TaskEntity> createTask(TaskEntity task) async {
    final now = EthiopiaClock.nowUtc();
    final trimmedTitle = task.title.trim();
    await _db.into(_db.tasks).insert(
          TasksCompanion.insert(
            id: task.id,
            title: trimmedTitle.isEmpty ? 'Untitled Task' : trimmedTitle,
            description: Value(task.description?.trim()),
            status: Value(task.status),
            priority: Value(task.priority),
            dueDate: Value(task.dueDate?.toIsoString()),
            scheduledDate: Value(task.scheduledDate?.toIsoString()),
            estimatedDurationMinutes: Value(task.estimatedDurationMinutes),
            projectId: Value(task.projectId),
            milestoneId: Value(task.milestoneId),
            subtasksJson: Value(_encodeSubtasks(task.subtasks)),
            labelsJson: Value(jsonEncode(task.labels)),
            isPinned: Value(task.isPinned),
            isMyDay: Value(task.isMyDay),
            recurrenceRule: Value(task.recurrenceRule),
            createdAt: task.createdAt,
            updatedAt: now,
          ),
        );

    return task.copyWith(
      title: trimmedTitle.isEmpty ? 'Untitled Task' : trimmedTitle,
      updatedAt: now,
    );
  }

  @override
  Future<TaskEntity> updateTask(TaskEntity task) async {
    final now = EthiopiaClock.nowUtc();
    final trimmedTitle = task.title.trim();
    await (_db.update(_db.tasks)..where((tbl) => tbl.id.equals(task.id))).write(
      TasksCompanion(
        title: Value(trimmedTitle.isEmpty ? 'Untitled Task' : trimmedTitle),
        description: Value(task.description?.trim()),
        status: Value(task.status),
        priority: Value(task.priority),
        dueDate: Value(task.dueDate?.toIsoString()),
        scheduledDate: Value(task.scheduledDate?.toIsoString()),
        estimatedDurationMinutes: Value(task.estimatedDurationMinutes),
        projectId: Value(task.projectId),
        milestoneId: Value(task.milestoneId),
        subtasksJson: Value(_encodeSubtasks(task.subtasks)),
        labelsJson: Value(jsonEncode(task.labels)),
        isPinned: Value(task.isPinned),
        isMyDay: Value(task.isMyDay),
        recurrenceRule: Value(task.recurrenceRule),
        updatedAt: Value(now),
      ),
    );

    return task.copyWith(
      title: trimmedTitle.isEmpty ? 'Untitled Task' : trimmedTitle,
      updatedAt: now,
    );
  }

  @override
  Future<void> updateTaskStatus(String id, String newStatus) async {
    await (_db.update(_db.tasks)..where((tbl) => tbl.id.equals(id))).write(
      TasksCompanion(
        status: Value(newStatus),
        updatedAt: Value(EthiopiaClock.nowUtc()),
      ),
    );
  }

  @override
  Future<void> rescheduleTask(String id, CalendarDate? newDueDate) async {
    await (_db.update(_db.tasks)..where((tbl) => tbl.id.equals(id))).write(
      TasksCompanion(
        dueDate: Value(newDueDate?.toIsoString()),
        updatedAt: Value(EthiopiaClock.nowUtc()),
      ),
    );
  }

  @override
  Future<void> postponeTaskDays(String id, int days) async {
    final task = await (_db.select(_db.tasks)
          ..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
    if (task == null) return;

    final currentDue =
        SharedDateFormatter.tryParseFlexibleToCalendarDate(task.dueDate) ??
            CalendarDate.today();
    final newDue = currentDue.addDays(days);
    await rescheduleTask(id, newDue);
  }

  @override
  Future<void> deleteTask(String id) async {
    await (_db.delete(_db.tasks)..where((tbl) => tbl.id.equals(id))).go();
  }

  @override
  Future<List<TaskEntity>> getTasksForProject(String projectId) async {
    final rows = await (_db.select(_db.tasks)
          ..where((tbl) => tbl.projectId.equals(projectId)))
        .get();
    return rows.map(_mapRowToTaskEntity).toList();
  }

  // ==========================================================================
  // IProjectRepositoryContract
  // ==========================================================================

  @override
  Future<List<ProjectEntity>> getProjects({String? status}) async {
    final query = _db.select(_db.projects);
    if (status != null) {
      query.where((tbl) => tbl.status.equals(status));
    }
    query.orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);
    final rows = await query.get();

    return rows
        .map((r) => ProjectEntity(
              id: r.id,
              title: r.title,
              description: r.description,
              status: r.status,
              targetDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
                r.targetDate,
              ),
              goalId: r.goalId,
              createdAt: r.createdAt,
            ))
        .toList();
  }

  @override
  Future<ProjectEntity?> getProjectById(String id) async {
    final query = _db.select(_db.projects)..where((tbl) => tbl.id.equals(id));
    final r = await query.getSingleOrNull();
    if (r == null) return null;

    return ProjectEntity(
      id: r.id,
      title: r.title,
      description: r.description,
      status: r.status,
      targetDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        r.targetDate,
      ),
      goalId: r.goalId,
      createdAt: r.createdAt,
    );
  }

  @override
  Future<ProjectEntity> createProject(ProjectEntity project) async {
    await _db.into(_db.projects).insert(
          ProjectsCompanion.insert(
            id: project.id,
            title: project.title.trim(),
            goalId: Value(project.goalId),
            description: Value(project.description?.trim()),
            targetDate: Value(project.targetDate?.toIsoString()),
            status: Value(project.status),
            createdAt: project.createdAt,
          ),
        );

    return project;
  }

  @override
  Future<ProjectEntity> updateProject(ProjectEntity project) async {
    await (_db.update(_db.projects)..where((tbl) => tbl.id.equals(project.id)))
        .write(
      ProjectsCompanion(
        title: Value(project.title.trim()),
        goalId: Value(project.goalId),
        description: Value(project.description?.trim()),
        targetDate: Value(project.targetDate?.toIsoString()),
        status: Value(project.status),
      ),
    );

    return project;
  }

  @override
  Future<void> deleteProject(String id) async {
    await _db.transaction(() async {
      await (_db.update(_db.tasks)..where((tbl) => tbl.projectId.equals(id)))
          .write(
        const TasksCompanion(projectId: Value(null)),
      );
      await (_db.delete(_db.milestones)
            ..where((tbl) => tbl.projectId.equals(id)))
          .go();
      await (_db.delete(_db.projects)..where((tbl) => tbl.id.equals(id))).go();
    });
  }

  // ==========================================================================
  // IMilestoneRepositoryContract
  // ==========================================================================

  @override
  Future<List<MilestoneEntity>> getAllMilestones() async {
    final rows = await (_db.select(_db.milestones)
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.dueDate)]))
        .get();

    return rows
        .map((r) => MilestoneEntity(
              id: r.id,
              projectId: r.projectId,
              title: r.title,
              dueDate:
                  SharedDateFormatter.tryParseFlexibleToCalendarDate(r.dueDate),
              isCompleted: r.isCompleted,
              createdAt: r.createdAt,
            ))
        .toList();
  }

  @override
  Future<List<MilestoneEntity>> getMilestonesForProject(
      String projectId) async {
    final rows = await (_db.select(_db.milestones)
          ..where((tbl) => tbl.projectId.equals(projectId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.dueDate)]))
        .get();

    return rows
        .map((r) => MilestoneEntity(
              id: r.id,
              projectId: r.projectId,
              title: r.title,
              dueDate:
                  SharedDateFormatter.tryParseFlexibleToCalendarDate(r.dueDate),
              isCompleted: r.isCompleted,
              createdAt: r.createdAt,
            ))
        .toList();
  }

  @override
  Future<MilestoneEntity> createMilestone(MilestoneEntity milestone) async {
    await _db.into(_db.milestones).insert(
          MilestonesCompanion.insert(
            id: milestone.id,
            projectId: milestone.projectId,
            title: milestone.title.trim(),
            dueDate: Value(milestone.dueDate?.toIsoString()),
            isCompleted: Value(milestone.isCompleted),
            createdAt: milestone.createdAt,
          ),
        );

    return milestone;
  }

  @override
  Future<void> toggleMilestone(String milestoneId, bool isCompleted) async {
    await (_db.update(_db.milestones)
          ..where((tbl) => tbl.id.equals(milestoneId)))
        .write(
      MilestonesCompanion(isCompleted: Value(isCompleted)),
    );
  }

  @override
  Future<void> deleteMilestone(String milestoneId) async {
    await (_db.delete(_db.milestones)
          ..where((tbl) => tbl.id.equals(milestoneId)))
        .go();
  }

  // ==========================================================================
  // Progress Calculation Aggregate
  // ==========================================================================

  @override
  Future<
      ({
        ProjectEntity project,
        List<TaskEntity> tasks,
        List<MilestoneEntity> milestones,
        int progressPercentage,
      })?> getProjectWithProgress(String projectId) async {
    final project = await getProjectById(projectId);
    if (project == null) return null;

    final projectTasks = await getTasksForProject(projectId);
    final projectMilestones = await getMilestonesForProject(projectId);

    final completedTasks = projectTasks.where((t) => t.isCompleted).length;
    final completedMilestones =
        projectMilestones.where((m) => m.isCompleted).length;

    final progress = ProgressEngine.calculateProgressPercentage(
      totalTasks: projectTasks.length,
      completedTasks: completedTasks,
      totalMilestones: projectMilestones.length,
      completedMilestones: completedMilestones,
      isProjectManuallyCompleted: project.status == 'completed',
    );

    return (
      project: project,
      tasks: projectTasks,
      milestones: projectMilestones,
      progressPercentage: progress,
    );
  }
}
