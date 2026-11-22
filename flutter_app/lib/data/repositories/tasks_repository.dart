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
/// Unifies Task, DailyPlanningEntry, Project, and Milestone persistence into a
/// single atomic relational persistence unit under Drift SQLite schema v10.
class DriftTasksRepository implements ITasksRepository {
  final AppDatabase _db;

  DriftTasksRepository(this._db);

  static List<TaskSubtask> _decodeSubtasks(String raw, String taskId) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final result = <TaskSubtask>[];
      for (var i = 0; i < decoded.length; i++) {
        final item = decoded[i];
        if (item is Map) {
          result.add(
            TaskSubtask.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)),
              fallbackId: '$taskId-sub-${i + 1}',
            ),
          );
        }
      }
      return List<TaskSubtask>.unmodifiable(result);
    } catch (_) {
      return const [];
    }
  }

  static String _encodeSubtasks(List<TaskSubtask> subtasks, String taskId) {
    return jsonEncode([
      for (var i = 0; i < subtasks.length; i++)
        {
          'id': subtasks[i].id.trim().isNotEmpty
              ? subtasks[i].id.trim()
              : '$taskId-sub-${i + 1}',
          'title': subtasks[i].title,
          'done': subtasks[i].done,
        }
    ]);
  }

  static TaskRecurrenceConfig? _decodeRecurrenceConfig(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return TaskRecurrenceConfig.tryFromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  static String? _encodeRecurrenceConfig(TaskRecurrenceConfig? config) {
    if (config == null) return null;
    return jsonEncode(config.toJson());
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
      completedAt: r.completedAt,
      dueDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(r.dueDate),
      scheduledDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        r.scheduledDate,
      ),
      scheduledTime: r.scheduledTime,
      estimatedDurationMinutes: r.estimatedDurationMinutes,
      projectId: r.projectId,
      milestoneId: r.milestoneId,
      subtasks: _decodeSubtasks(r.subtasksJson, r.id),
      labels: _decodeLabels(r.labelsJson),
      isPinned: r.isPinned,
      isMyDay: r.isMyDay,
      myDayDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(r.myDayDate),
      recurrenceRule: r.recurrenceRule,
      recurrenceConfig: _decodeRecurrenceConfig(r.recurrenceConfigJson),
      isArchived: r.isArchived,
      sortOrder: r.sortOrder,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    );
  }

  DailyPlanningEntryEntity _mapRowToDailyPlanningEntity(
    DailyPlanningEntry r,
  ) {
    return DailyPlanningEntryEntity(
      id: r.id,
      planDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(r.planDate) ??
          CalendarDate.today(),
      taskId: r.taskId,
      action: r.action,
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
    final effectiveCompletedAt =
        task.completedAt ?? (task.isCompleted ? now : null);
    await _db.into(_db.tasks).insert(
          TasksCompanion.insert(
            id: task.id,
            title: trimmedTitle.isEmpty ? 'Untitled Task' : trimmedTitle,
            description: Value(task.description?.trim()),
            status: Value(task.status),
            priority: Value(task.priority),
            completedAt: Value(effectiveCompletedAt),
            dueDate: Value(task.dueDate?.toIsoString()),
            scheduledDate: Value(task.scheduledDate?.toIsoString()),
            scheduledTime: Value(task.scheduledTime),
            estimatedDurationMinutes: Value(task.estimatedDurationMinutes),
            projectId: Value(task.projectId),
            milestoneId: Value(task.milestoneId),
            subtasksJson: Value(_encodeSubtasks(task.subtasks, task.id)),
            labelsJson: Value(jsonEncode(task.labels)),
            isPinned: Value(task.isPinned),
            isMyDay: Value(task.isMyDay),
            myDayDate: Value(task.myDayDate?.toIsoString()),
            recurrenceRule: Value(task.recurrenceRule),
            recurrenceConfigJson:
                Value(_encodeRecurrenceConfig(task.recurrenceConfig)),
            isArchived: Value(task.isArchived),
            sortOrder: Value(task.sortOrder),
            createdAt: task.createdAt,
            updatedAt: now,
          ),
        );

    return task.copyWith(
      title: trimmedTitle.isEmpty ? 'Untitled Task' : trimmedTitle,
      completedAt: effectiveCompletedAt,
      clearCompletedAt: effectiveCompletedAt == null,
      updatedAt: now,
    );
  }

  @override
  Future<TaskEntity> updateTask(TaskEntity task) async {
    final now = EthiopiaClock.nowUtc();
    final trimmedTitle = task.title.trim();
    final effectiveCompletedAt =
        task.isCompleted ? (task.completedAt ?? now) : null;
    await (_db.update(_db.tasks)..where((tbl) => tbl.id.equals(task.id))).write(
      TasksCompanion(
        title: Value(trimmedTitle.isEmpty ? 'Untitled Task' : trimmedTitle),
        description: Value(task.description?.trim()),
        status: Value(task.status),
        priority: Value(task.priority),
        completedAt: Value(effectiveCompletedAt),
        dueDate: Value(task.dueDate?.toIsoString()),
        scheduledDate: Value(task.scheduledDate?.toIsoString()),
        scheduledTime: Value(task.scheduledTime),
        estimatedDurationMinutes: Value(task.estimatedDurationMinutes),
        projectId: Value(task.projectId),
        milestoneId: Value(task.milestoneId),
        subtasksJson: Value(_encodeSubtasks(task.subtasks, task.id)),
        labelsJson: Value(jsonEncode(task.labels)),
        isPinned: Value(task.isPinned),
        isMyDay: Value(task.isMyDay),
        myDayDate: Value(task.myDayDate?.toIsoString()),
        recurrenceRule: Value(task.recurrenceRule),
        recurrenceConfigJson:
            Value(_encodeRecurrenceConfig(task.recurrenceConfig)),
        isArchived: Value(task.isArchived),
        sortOrder: Value(task.sortOrder),
        updatedAt: Value(now),
      ),
    );

    return task.copyWith(
      title: trimmedTitle.isEmpty ? 'Untitled Task' : trimmedTitle,
      completedAt: effectiveCompletedAt,
      clearCompletedAt: effectiveCompletedAt == null,
      updatedAt: now,
    );
  }

  @override
  Future<void> updateTaskStatus(String id, String newStatus) async {
    final now = EthiopiaClock.nowUtc();
    final existing = await (_db.select(_db.tasks)
          ..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
    final nextCompletedAt =
        newStatus == 'completed' ? (existing?.completedAt ?? now) : null;
    await (_db.update(_db.tasks)..where((tbl) => tbl.id.equals(id))).write(
      TasksCompanion(
        status: Value(newStatus),
        completedAt: Value(nextCompletedAt),
        updatedAt: Value(now),
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
    await _db.transaction(() async {
      await (_db.delete(_db.dailyPlanningEntries)
            ..where((tbl) => tbl.taskId.equals(id)))
          .go();
      await (_db.delete(_db.reminders)
            ..where(
              (tbl) => tbl.targetType.equals('task') & tbl.targetId.equals(id),
            ))
          .go();
      await (_db.delete(_db.tasks)..where((tbl) => tbl.id.equals(id))).go();
    });
  }

  @override
  Future<List<TaskEntity>> getTasksForProject(String projectId) async {
    final rows = await (_db.select(_db.tasks)
          ..where((tbl) => tbl.projectId.equals(projectId)))
        .get();
    return rows.map(_mapRowToTaskEntity).toList();
  }

  @override
  Future<List<DailyPlanningEntryEntity>> getDailyPlanningEntries({
    CalendarDate? planDate,
    String? taskId,
  }) async {
    final query = _db.select(_db.dailyPlanningEntries);
    if (planDate != null) {
      final dateIso = planDate.toIsoString();
      query.where((tbl) => tbl.planDate.equals(dateIso));
    }
    if (taskId != null) {
      query.where((tbl) => tbl.taskId.equals(taskId));
    }
    query.orderBy([
      (tbl) => OrderingTerm.asc(tbl.planDate),
      (tbl) => OrderingTerm.asc(tbl.createdAt),
    ]);
    final rows = await query.get();
    return rows.map(_mapRowToDailyPlanningEntity).toList();
  }

  @override
  Future<DailyPlanningEntryEntity> upsertDailyPlanningEntry(
    DailyPlanningEntryEntity entry,
  ) async {
    final now = EthiopiaClock.nowUtc();
    final dateIso = entry.planDate.toIsoString();
    return _db.transaction(() async {
      final existingByComposite = await (_db.select(_db.dailyPlanningEntries)
            ..where(
              (tbl) => tbl.taskId.equals(entry.taskId) & tbl.planDate.equals(dateIso),
            ))
          .getSingleOrNull();
      final existingById = existingByComposite ??
          await (_db.select(_db.dailyPlanningEntries)
                ..where((tbl) => tbl.id.equals(entry.id)))
              .getSingleOrNull();

      if (existingById != null) {
        final effectiveUpdatedAt = entry.updatedAt ?? now;
        await (_db.update(_db.dailyPlanningEntries)
              ..where((tbl) => tbl.id.equals(existingById.id)))
            .write(
          DailyPlanningEntriesCompanion(
            planDate: Value(dateIso),
            taskId: Value(entry.taskId),
            action: Value(entry.action),
            updatedAt: Value(effectiveUpdatedAt),
          ),
        );
        return DailyPlanningEntryEntity(
          id: existingById.id,
          planDate: entry.planDate,
          taskId: entry.taskId,
          action: entry.action,
          createdAt: existingById.createdAt,
          updatedAt: effectiveUpdatedAt,
        );
      }

      await _db.into(_db.dailyPlanningEntries).insert(
            DailyPlanningEntriesCompanion.insert(
              id: entry.id,
              planDate: dateIso,
              taskId: entry.taskId,
              action: Value(entry.action),
              createdAt: entry.createdAt,
              updatedAt: Value(entry.updatedAt ?? now),
            ),
          );
      return entry.copyWith(updatedAt: entry.updatedAt ?? now);
    });
  }

  @override
  Future<void> deleteDailyPlanningEntry(String id) async {
    await (_db.delete(_db.dailyPlanningEntries)
          ..where((tbl) => tbl.id.equals(id)))
        .go();
  }

  @override
  Future<void> deleteDailyPlanningEntriesForTask(String taskId) async {
    await (_db.delete(_db.dailyPlanningEntries)
          ..where((tbl) => tbl.taskId.equals(taskId)))
        .go();
  }

  TaskReminderEntity _mapReminderRowToEntity(Reminder row) {
    return TaskReminderEntity(
      id: row.id,
      targetId: row.targetId,
      targetType: row.targetType,
      title: row.title,
      channelId: row.channelId,
      triggerTimeUtc: row.triggerTimeUtc,
      isActive: row.isActive,
      createdAt: row.createdAt,
    );
  }

  @override
  Future<List<TaskReminderEntity>> getTaskReminders() async {
    final rows = await (_db.select(_db.reminders)
          ..where((tbl) => tbl.targetType.equals('task'))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.triggerTimeUtc)]))
        .get();
    final byTaskId = <String, TaskReminderEntity>{};
    for (final row in rows) {
      final entity = _mapReminderRowToEntity(row);
      final prev = byTaskId[entity.targetId];
      if (prev == null ||
          (entity.isActive && !prev.isActive) ||
          (entity.isActive == prev.isActive &&
              entity.id == 'rem-task-${entity.targetId}' &&
              prev.id != 'rem-task-${entity.targetId}')) {
        byTaskId[entity.targetId] = entity;
      }
    }
    return List<TaskReminderEntity>.unmodifiable(byTaskId.values);
  }

  @override
  Future<TaskReminderEntity?> getTaskReminderForTask(String taskId) async {
    final rows = await (_db.select(_db.reminders)
          ..where(
            (tbl) =>
                tbl.targetType.equals('task') & tbl.targetId.equals(taskId),
          ))
        .get();
    if (rows.isEmpty) return null;
    final entities = rows.map(_mapReminderRowToEntity).toList(growable: false);
    final canonicalId = 'rem-task-$taskId';
    return entities.firstWhere(
      (r) => r.id == canonicalId && r.isActive,
      orElse: () => entities.firstWhere(
        (r) => r.isActive,
        orElse: () => entities.firstWhere(
          (r) => r.id == canonicalId,
          orElse: () => entities.first,
        ),
      ),
    );
  }

  @override
  Future<TaskReminderEntity> upsertTaskReminder(
    TaskReminderEntity reminder,
  ) async {
    return _db.transaction(() async {
      final existingForTask = await (_db.select(_db.reminders)
            ..where(
              (tbl) =>
                  tbl.targetType.equals('task') &
                  tbl.targetId.equals(reminder.targetId),
            ))
          .get();

      final targetRow = existingForTask.isNotEmpty
          ? existingForTask.firstWhere(
              (r) => r.id == reminder.id,
              orElse: () => existingForTask.first,
            )
          : await (_db.select(_db.reminders)
                ..where((tbl) => tbl.id.equals(reminder.id)))
              .getSingleOrNull();

      // Remove any duplicate task reminder rows for this taskId.
      for (final dup in existingForTask) {
        if (targetRow == null || dup.id != targetRow.id) {
          await (_db.delete(_db.reminders)
                ..where((tbl) => tbl.id.equals(dup.id)))
              .go();
        }
      }

      final effectiveId = targetRow?.id ?? reminder.id;
      final normalized = reminder.copyWith(id: effectiveId, targetType: 'task');
      if (targetRow != null) {
        await (_db.update(_db.reminders)
              ..where((tbl) => tbl.id.equals(effectiveId)))
            .write(
          RemindersCompanion(
            targetId: Value(normalized.targetId),
            targetType: const Value('task'),
            title: Value(normalized.title),
            channelId: Value(normalized.channelId),
            triggerTimeUtc: Value(normalized.triggerTimeUtc),
            isActive: Value(normalized.isActive),
          ),
        );
        return TaskReminderEntity(
          id: effectiveId,
          targetId: normalized.targetId,
          targetType: 'task',
          title: normalized.title,
          channelId: normalized.channelId,
          triggerTimeUtc: normalized.triggerTimeUtc,
          isActive: normalized.isActive,
          createdAt: targetRow.createdAt,
        );
      }

      await _db.into(_db.reminders).insert(
            RemindersCompanion.insert(
              id: normalized.id,
              targetId: normalized.targetId,
              targetType: 'task',
              title: Value(normalized.title),
              channelId: Value(normalized.channelId),
              triggerTimeUtc: normalized.triggerTimeUtc,
              isActive: Value(normalized.isActive),
              createdAt: normalized.createdAt,
            ),
          );
      return normalized;
    });
  }

  @override
  Future<void> deleteTaskReminderForTask(String taskId) async {
    await (_db.delete(_db.reminders)
          ..where(
            (tbl) => tbl.targetType.equals('task') & tbl.targetId.equals(taskId),
          ))
        .go();
  }

  // ==========================================================================
  // IProjectRepositoryContract
  // ==========================================================================

  ProjectEntity _mapProjectRow(Project r) {
    Map<String, dynamic> customFields = const <String, dynamic>{};
    try {
      final decoded = jsonDecode(r.customFieldsJson);
      if (decoded is Map) {
        customFields = decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {
      customFields = const <String, dynamic>{};
    }
    return ProjectEntity(
      id: r.id,
      title: r.title,
      description: r.description,
      status: r.status,
      targetDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        r.targetDate,
      ),
      goalId: r.goalId,
      isArchived: r.isArchived,
      startDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        r.startDate,
      ),
      customFields: customFields,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt ?? r.createdAt,
    );
  }

  @override
  Future<List<ProjectEntity>> getProjects({String? status}) async {
    final query = _db.select(_db.projects);
    if (status != null) {
      query.where((tbl) => tbl.status.equals(status));
    }
    query.orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);
    final rows = await query.get();
    return rows.map(_mapProjectRow).toList();
  }

  @override
  Future<ProjectEntity?> getProjectById(String id) async {
    final query = _db.select(_db.projects)..where((tbl) => tbl.id.equals(id));
    final r = await query.getSingleOrNull();
    if (r == null) return null;
    return _mapProjectRow(r);
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
            isArchived: Value(project.isArchived),
            startDate: Value(project.startDate?.toIsoString()),
            customFieldsJson: Value(jsonEncode(project.customFields)),
            createdAt: project.createdAt,
            updatedAt: Value(project.updatedAt),
          ),
        );

    return project;
  }

  @override
  Future<ProjectEntity> updateProject(ProjectEntity project) async {
    final updated = project.copyWith(updatedAt: EthiopiaClock.nowUtc());
    await (_db.update(_db.projects)..where((tbl) => tbl.id.equals(updated.id)))
        .write(
      ProjectsCompanion(
        title: Value(updated.title.trim()),
        goalId: Value(updated.goalId),
        description: Value(updated.description?.trim()),
        targetDate: Value(updated.targetDate?.toIsoString()),
        status: Value(updated.status),
        isArchived: Value(updated.isArchived),
        startDate: Value(updated.startDate?.toIsoString()),
        customFieldsJson: Value(jsonEncode(updated.customFields)),
        updatedAt: Value(updated.updatedAt),
      ),
    );

    return updated;
  }

  @override
  Future<void> deleteProject(String id) async {
    await _db.transaction(() async {
      await (_db.update(_db.tasks)..where((tbl) => tbl.projectId.equals(id)))
          .write(
        const TasksCompanion(
          projectId: Value(null),
          milestoneId: Value(null),
        ),
      );
      await _db.customStatement(
        'UPDATE project_tracking_records SET parent_record_id = NULL '
        'WHERE project_id = ?;',
        [id],
      );
      await (_db.delete(_db.projectTrackingRecords)
            ..where((tbl) => tbl.projectId.equals(id)))
          .go();
      await (_db.delete(_db.projectTrackingBlocks)
            ..where((tbl) => tbl.projectId.equals(id)))
          .go();
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
  Future<MilestoneEntity> updateMilestone(MilestoneEntity milestone) async {
    final trimmedTitle = milestone.title.trim();
    final normalized = milestone.copyWith(
      title: trimmedTitle.isEmpty ? 'Untitled Milestone' : trimmedTitle,
    );
    await (_db.update(_db.milestones)
          ..where((tbl) => tbl.id.equals(normalized.id)))
        .write(
      MilestonesCompanion(
        title: Value(normalized.title),
        dueDate: Value(normalized.dueDate?.toIsoString()),
        isCompleted: Value(normalized.isCompleted),
      ),
    );
    return normalized;
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
    await _db.transaction(() async {
      await (_db.update(_db.tasks)
            ..where((tbl) => tbl.milestoneId.equals(milestoneId)))
          .write(const TasksCompanion(milestoneId: Value(null)));
      await (_db.delete(_db.milestones)
            ..where((tbl) => tbl.id.equals(milestoneId)))
          .go();
    });
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
