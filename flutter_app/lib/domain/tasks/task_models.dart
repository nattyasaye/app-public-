import '../../core/date/shared_date.dart';

/// Pure domain models for the Daywell To-Do and Projects module.
///
/// Invariants:
/// - Zero dependencies on Flutter widgets or Drift SQLite implementation.
/// - Immutable value objects with copyWith and JSON serialization.

class TaskSubtask {
  final String id;
  final String title;
  final bool done;

  const TaskSubtask({
    required this.id,
    required this.title,
    this.done = false,
  });

  TaskSubtask copyWith({
    String? id,
    String? title,
    bool? done,
  }) {
    return TaskSubtask(
      id: id ?? this.id,
      title: title ?? this.title,
      done: done ?? this.done,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'done': done,
      };

  factory TaskSubtask.fromJson(
    Map<String, dynamic> json, {
    required String fallbackId,
  }) {
    final rawId = json['id']?.toString().trim();
    return TaskSubtask(
      id: (rawId != null && rawId.isNotEmpty) ? rawId : fallbackId,
      title: (json['title'] ?? '').toString(),
      done: json['done'] == true || json['completed'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskSubtask &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          done == other.done;

  @override
  int get hashCode => Object.hash(id, title, done);

  static String nextId(String taskId, List<TaskSubtask> existing) {
    final prefix = taskId.trim().isNotEmpty ? taskId.trim() : 'task';
    final used = existing.map((e) => e.id).toSet();
    var counter = existing.length + 1;
    while (used.contains('$prefix-sub-$counter')) {
      counter++;
    }
    return '$prefix-sub-$counter';
  }

  static List<TaskSubtask> normalizeList(
    List<TaskSubtask> items, {
    required String taskId,
  }) {
    final normalized = <TaskSubtask>[];
    final seenIds = <String>{};
    for (final item in items) {
      final trimmedTitle = item.title.trim();
      if (trimmedTitle.isEmpty) continue;
      var candidateId = item.id.trim();
      if (candidateId.isEmpty || seenIds.contains(candidateId)) {
        candidateId = nextId(taskId, normalized);
      }
      seenIds.add(candidateId);
      normalized.add(
        TaskSubtask(id: candidateId, title: trimmedTitle, done: item.done),
      );
    }
    return List<TaskSubtask>.unmodifiable(normalized);
  }

  static List<TaskSubtask> reorderList(
    List<TaskSubtask> items,
    int fromIndex,
    int toIndex,
  ) {
    if (fromIndex < 0 ||
        fromIndex >= items.length ||
        toIndex < 0 ||
        toIndex >= items.length ||
        fromIndex == toIndex) {
      return List<TaskSubtask>.from(items);
    }
    final next = List<TaskSubtask>.from(items);
    final moved = next.removeAt(fromIndex);
    next.insert(toIndex, moved);
    return List<TaskSubtask>.unmodifiable(next);
  }
}

class TaskRecurrenceConfig {
  final String frequency; // 'daily', 'weekly', 'monthly', 'yearly'
  final int? interval;
  final List<int>? weekdays; // 1..7 (ISO Monday..Sunday)
  final CalendarDate? startDate;
  final CalendarDate? endDate;
  final String? repeatFrom; // 'due_date', 'completion_date'

  const TaskRecurrenceConfig({
    required this.frequency,
    this.interval,
    this.weekdays,
    this.startDate,
    this.endDate,
    this.repeatFrom,
  });

  TaskRecurrenceConfig copyWith({
    String? frequency,
    int? interval,
    List<int>? weekdays,
    bool clearWeekdays = false,
    CalendarDate? startDate,
    bool clearStartDate = false,
    CalendarDate? endDate,
    bool clearEndDate = false,
    String? repeatFrom,
    bool clearRepeatFrom = false,
  }) {
    return TaskRecurrenceConfig(
      frequency: frequency ?? this.frequency,
      interval: interval ?? this.interval,
      weekdays: clearWeekdays ? null : (weekdays ?? this.weekdays),
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      repeatFrom: clearRepeatFrom ? null : (repeatFrom ?? this.repeatFrom),
    );
  }

  Map<String, dynamic> toJson() => {
        'frequency': frequency,
        if (interval != null) 'interval': interval,
        if (weekdays != null) 'weekdays': weekdays,
        if (startDate != null) 'startDate': startDate!.toIsoString(),
        if (endDate != null) 'endDate': endDate!.toIsoString(),
        if (repeatFrom != null) 'repeatFrom': repeatFrom,
      };

  static TaskRecurrenceConfig? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final freq = raw['frequency']?.toString().trim() ?? '';
    if (!const {'daily', 'weekly', 'monthly', 'yearly'}.contains(freq)) {
      return null;
    }
    final rawInterval = raw['interval'];
    final interval =
        rawInterval is int && rawInterval >= 1 ? rawInterval : null;
    final rawWeekdays = raw['weekdays'];
    List<int>? weekdays;
    if (rawWeekdays is List) {
      weekdays = rawWeekdays
          .whereType<int>()
          .where((d) => d >= 1 && d <= 7)
          .toList(growable: false);
    }
    final startDate = SharedDateFormatter.tryParseFlexibleToCalendarDate(
      raw['startDate']?.toString(),
    );
    final endDate = SharedDateFormatter.tryParseFlexibleToCalendarDate(
      raw['endDate']?.toString(),
    );
    final rawRepeatFrom = raw['repeatFrom']?.toString().trim();
    final repeatFrom =
        const {'due_date', 'completion_date'}.contains(rawRepeatFrom)
            ? rawRepeatFrom
            : null;

    return TaskRecurrenceConfig(
      frequency: freq,
      interval: interval,
      weekdays: weekdays,
      startDate: startDate,
      endDate: endDate,
      repeatFrom: repeatFrom,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TaskRecurrenceConfig) return false;
    if (frequency != other.frequency ||
        interval != other.interval ||
        startDate != other.startDate ||
        endDate != other.endDate ||
        repeatFrom != other.repeatFrom) {
      return false;
    }
    final a = weekdays;
    final b = other.weekdays;
    if (a == null && b == null) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        frequency,
        interval,
        weekdays == null ? null : Object.hashAll(weekdays!),
        startDate,
        endDate,
        repeatFrom,
      );
}

class TaskEntity {
  final String id;
  final String title;
  final String? description;
  final String
      status; // 'inbox', 'not_started', 'in_progress', 'completed', 'cancelled'
  final String priority; // 'low', 'medium', 'high', 'urgent'
  final DateTime? completedAt;
  final CalendarDate? dueDate;
  final CalendarDate? scheduledDate;
  final String? scheduledTime; // 24h HH:MM
  final int? estimatedDurationMinutes;
  final String? projectId;
  final String? milestoneId;
  final List<TaskSubtask> subtasks;
  final List<String> labels;
  final bool isPinned;
  final bool isMyDay;
  final CalendarDate? myDayDate;
  final String? recurrenceRule; // 'none', 'daily', 'weekly', 'monthly'
  final TaskRecurrenceConfig? recurrenceConfig;
  final bool isArchived;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  TaskEntity({
    required this.id,
    required this.title,
    this.description,
    this.status = 'not_started',
    this.priority = 'medium',
    DateTime? completedAt,
    this.dueDate,
    this.scheduledDate,
    this.scheduledTime,
    this.estimatedDurationMinutes,
    this.projectId,
    this.milestoneId,
    this.subtasks = const [],
    this.labels = const [],
    this.isPinned = false,
    this.isMyDay = false,
    this.myDayDate,
    this.recurrenceRule,
    this.recurrenceConfig,
    this.isArchived = false,
    this.sortOrder = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : completedAt = completedAt?.toUtc(),
        createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc(),
        updatedAt = (updatedAt ?? EthiopiaClock.nowUtc()).toUtc();

  bool get isCompleted => status == 'completed';
  bool get isOverdue {
    if (dueDate == null || isCompleted || status == 'cancelled') return false;
    return dueDate!.isBefore(CalendarDate.today());
  }

  int get completedSubtaskCount => subtasks.where((s) => s.done).length;
  int get totalSubtaskCount => subtasks.length;
  double get subtaskProgress =>
      subtasks.isEmpty ? 0.0 : completedSubtaskCount / subtasks.length;
  int get subtaskProgressPercentage => (subtaskProgress * 100).round();

  TaskEntity copyWith({
    String? title,
    String? description,
    bool clearDescription = false,
    String? status,
    String? priority,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    CalendarDate? dueDate,
    bool clearDueDate = false,
    CalendarDate? scheduledDate,
    bool clearScheduledDate = false,
    String? scheduledTime,
    bool clearScheduledTime = false,
    int? estimatedDurationMinutes,
    String? projectId,
    bool clearProject = false,
    String? milestoneId,
    bool clearMilestone = false,
    List<TaskSubtask>? subtasks,
    List<String>? labels,
    bool? isPinned,
    bool? isMyDay,
    CalendarDate? myDayDate,
    bool clearMyDayDate = false,
    String? recurrenceRule,
    bool clearRecurrenceRule = false,
    TaskRecurrenceConfig? recurrenceConfig,
    bool clearRecurrenceConfig = false,
    bool? isArchived,
    int? sortOrder,
    DateTime? updatedAt,
  }) {
    return TaskEntity(
      id: id,
      title: title ?? this.title,
      description: clearDescription ? null : (description ?? this.description),
      status: status ?? this.status,
      priority: priority ?? this.priority,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      scheduledDate:
          clearScheduledDate ? null : (scheduledDate ?? this.scheduledDate),
      scheduledTime:
          clearScheduledTime ? null : (scheduledTime ?? this.scheduledTime),
      estimatedDurationMinutes:
          estimatedDurationMinutes ?? this.estimatedDurationMinutes,
      projectId: clearProject ? null : (projectId ?? this.projectId),
      milestoneId: clearMilestone ? null : (milestoneId ?? this.milestoneId),
      subtasks: subtasks ?? this.subtasks,
      labels: labels ?? this.labels,
      isPinned: isPinned ?? this.isPinned,
      isMyDay: isMyDay ?? this.isMyDay,
      myDayDate: clearMyDayDate ? null : (myDayDate ?? this.myDayDate),
      recurrenceRule:
          clearRecurrenceRule ? null : (recurrenceRule ?? this.recurrenceRule),
      recurrenceConfig: clearRecurrenceConfig
          ? null
          : (recurrenceConfig ?? this.recurrenceConfig),
      isArchived: isArchived ?? this.isArchived,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? EthiopiaClock.nowUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'status': status,
        'completed': isCompleted,
        'priority': priority,
        if (completedAt != null)
          'completedAt': EthiopiaClock.toUtcIsoString(completedAt!),
        'dueDate': dueDate?.toIsoString(),
        'scheduledDate': scheduledDate?.toIsoString(),
        if (scheduledTime != null) 'scheduledTime': scheduledTime,
        'estimatedDurationMinutes': estimatedDurationMinutes,
        'projectId': projectId,
        'milestoneId': milestoneId,
        'subtasks': subtasks.map((s) => s.toJson()).toList(growable: false),
        'labels': labels,
        'isPinned': isPinned,
        'isMyDay': isMyDay,
        if (myDayDate != null) 'myDayDate': myDayDate!.toIsoString(),
        'recurrenceRule': recurrenceRule,
        if (recurrenceConfig != null)
          'recurrenceConfig': recurrenceConfig!.toJson(),
        'isArchived': isArchived,
        'sortOrder': sortOrder,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
        'updatedAt': EthiopiaClock.toUtcIsoString(updatedAt),
      };

  factory TaskEntity.fromJson(Map<String, dynamic> json) {
    final taskId = (json['id'] ?? '').toString();
    final rawSubtasks = json['subtasks'];
    final parsedSubtasks = <TaskSubtask>[];
    if (rawSubtasks is List) {
      for (var i = 0; i < rawSubtasks.length; i++) {
        final item = rawSubtasks[i];
        if (item is Map) {
          parsedSubtasks.add(
            TaskSubtask.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)),
              fallbackId: '$taskId-sub-${i + 1}',
            ),
          );
        }
      }
    }

    final rawScheduledTime = json['scheduledTime']?.toString().trim();
    final scheduledTime = rawScheduledTime != null &&
            RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(rawScheduledTime)
        ? rawScheduledTime
        : null;

    final rawSortOrder = json['sortOrder'];
    final sortOrder =
        rawSortOrder is int && rawSortOrder >= 0 ? rawSortOrder : 0;

    return TaskEntity(
      id: taskId,
      title: json['title'] ?? '',
      description: json['description'],
      status: json['status'] ??
          (json['completed'] == true ? 'completed' : 'not_started'),
      priority: json['priority'] ?? 'medium',
      completedAt:
          EthiopiaClock.tryParseInstantUtc(json['completedAt']?.toString()),
      dueDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        json['dueDate']?.toString(),
      ),
      scheduledDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        json['scheduledDate']?.toString(),
      ),
      scheduledTime: scheduledTime,
      estimatedDurationMinutes: json['estimatedDurationMinutes'],
      projectId: json['projectId'],
      milestoneId: json['milestoneId'],
      subtasks: parsedSubtasks,
      labels: json['labels'] is List
          ? (json['labels'] as List).map((e) => e.toString()).toList()
          : const [],
      isPinned: json['isPinned'] ?? false,
      isMyDay: json['isMyDay'] ?? false,
      myDayDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        json['myDayDate']?.toString(),
      ),
      recurrenceRule: json['recurrenceRule'],
      recurrenceConfig:
          TaskRecurrenceConfig.tryFromJson(json['recurrenceConfig']),
      isArchived: json['isArchived'] == true,
      sortOrder: sortOrder,
      createdAt:
          EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString()),
      updatedAt:
          EthiopiaClock.tryParseInstantUtc(json['updatedAt']?.toString()),
    );
  }
}

class DailyPlanningEntryEntity {
  final String id;
  final CalendarDate planDate;
  final String taskId;
  final String action; // 'planned', 'carried_forward', 'completed', 'dismissed'
  final DateTime createdAt;
  final DateTime? updatedAt;

  DailyPlanningEntryEntity({
    required this.id,
    required this.planDate,
    required this.taskId,
    this.action = 'planned',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc(),
        updatedAt = updatedAt?.toUtc();

  DailyPlanningEntryEntity copyWith({
    CalendarDate? planDate,
    String? taskId,
    String? action,
    DateTime? updatedAt,
  }) {
    return DailyPlanningEntryEntity(
      id: id,
      planDate: planDate ?? this.planDate,
      taskId: taskId ?? this.taskId,
      action: action ?? this.action,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'planDate': planDate.toIsoString(),
        'taskId': taskId,
        'action': action,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
        if (updatedAt != null)
          'updatedAt': EthiopiaClock.toUtcIsoString(updatedAt!),
      };

  factory DailyPlanningEntryEntity.fromJson(Map<String, dynamic> json) {
    final parsedDate = SharedDateFormatter.tryParseFlexibleToCalendarDate(
          json['planDate']?.toString(),
        ) ??
        CalendarDate.today();
    return DailyPlanningEntryEntity(
      id: (json['id'] ?? '').toString(),
      planDate: parsedDate,
      taskId: (json['taskId'] ?? '').toString(),
      action: (json['action'] ?? 'planned').toString(),
      createdAt:
          EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString()),
      updatedAt:
          EthiopiaClock.tryParseInstantUtc(json['updatedAt']?.toString()),
    );
  }
}

class ProjectEntity {
  final String id;
  final String title;
  final String? description;
  final String status; // 'active', 'completed', 'on_hold'
  final CalendarDate? targetDate;
  final String? goalId;
  final bool isArchived;
  final CalendarDate? startDate;
  final Map<String, dynamic> customFields;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProjectEntity({
    required this.id,
    required this.title,
    this.description,
    this.status = 'active',
    this.targetDate,
    this.goalId,
    this.isArchived = false,
    this.startDate,
    Map<String, dynamic>? customFields,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : customFields = Map<String, dynamic>.unmodifiable(
          customFields ?? const <String, dynamic>{},
        ),
        createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc(),
        updatedAt = (updatedAt ?? createdAt ?? EthiopiaClock.nowUtc()).toUtc();

  ProjectEntity copyWith({
    String? title,
    String? description,
    String? status,
    CalendarDate? targetDate,
    bool clearTargetDate = false,
    String? goalId,
    bool clearGoalId = false,
    bool? isArchived,
    CalendarDate? startDate,
    bool clearStartDate = false,
    Map<String, dynamic>? customFields,
    DateTime? updatedAt,
  }) {
    return ProjectEntity(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      targetDate: clearTargetDate ? null : (targetDate ?? this.targetDate),
      goalId: clearGoalId ? null : (goalId ?? this.goalId),
      isArchived: isArchived ?? this.isArchived,
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      customFields: customFields ?? this.customFields,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'status': status,
        'targetDate': targetDate?.toIsoString(),
        'goalId': goalId,
        'isArchived': isArchived,
        'startDate': startDate?.toIsoString(),
        'customFields': customFields,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
        'updatedAt': EthiopiaClock.toUtcIsoString(updatedAt),
      };

  factory ProjectEntity.fromJson(Map<String, dynamic> json) {
    final created =
        EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString());
    final updated =
        EthiopiaClock.tryParseInstantUtc(json['updatedAt']?.toString());
    final rawCustomFields = json['customFields'];
    final customFieldsMap = rawCustomFields is Map
        ? rawCustomFields.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
    return ProjectEntity(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      status: json['status']?.toString() ?? 'active',
      targetDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        json['targetDate']?.toString(),
      ),
      goalId: json['goalId']?.toString(),
      isArchived: json['isArchived'] == true,
      startDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        json['startDate']?.toString(),
      ),
      customFields: customFieldsMap,
      createdAt: created,
      updatedAt: updated ?? created,
    );
  }
}

class MilestoneEntity {
  final String id;
  final String projectId;
  final String title;
  final CalendarDate? dueDate;
  final bool isCompleted;
  final DateTime createdAt;

  MilestoneEntity({
    required this.id,
    required this.projectId,
    required this.title,
    this.dueDate,
    this.isCompleted = false,
    DateTime? createdAt,
  }) : createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc();

  MilestoneEntity copyWith({
    String? title,
    CalendarDate? dueDate,
    bool clearDueDate = false,
    bool? isCompleted,
  }) {
    return MilestoneEntity(
      id: id,
      projectId: projectId,
      title: title ?? this.title,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'title': title,
        'dueDate': dueDate?.toIsoString(),
        'isCompleted': isCompleted,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
      };

  factory MilestoneEntity.fromJson(Map<String, dynamic> json) =>
      MilestoneEntity(
        id: json['id'],
        projectId: json['projectId'] ?? '',
        title: json['title'] ?? '',
        dueDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
          json['dueDate']?.toString(),
        ),
        isCompleted: json['isCompleted'] ?? false,
        createdAt:
            EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString()),
      );
}

class TaskReminderEntity {
  final String id;
  final String targetId;
  final String targetType;
  final String? title;
  final String? channelId;
  final DateTime triggerTimeUtc;
  final bool isActive;
  final DateTime createdAt;

  TaskReminderEntity({
    required this.id,
    required this.targetId,
    this.targetType = 'task',
    this.title,
    this.channelId,
    required DateTime triggerTimeUtc,
    this.isActive = true,
    DateTime? createdAt,
  })  : triggerTimeUtc = triggerTimeUtc.toUtc(),
        createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc();

  TaskReminderEntity copyWith({
    String? id,
    String? targetId,
    String? targetType,
    String? title,
    String? channelId,
    DateTime? triggerTimeUtc,
    bool? isActive,
  }) {
    return TaskReminderEntity(
      id: id ?? this.id,
      targetId: targetId ?? this.targetId,
      targetType: targetType ?? this.targetType,
      title: title ?? this.title,
      channelId: channelId ?? this.channelId,
      triggerTimeUtc: triggerTimeUtc ?? this.triggerTimeUtc,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'targetId': targetId,
        'targetType': targetType,
        if (title != null && title!.trim().isNotEmpty) 'title': title,
        if (channelId != null && channelId!.trim().isNotEmpty)
          'channelId': channelId,
        'triggerTimeUtc': EthiopiaClock.toUtcIsoString(triggerTimeUtc),
        'isActive': isActive,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
      };

  factory TaskReminderEntity.fromJson(Map<String, dynamic> json) {
    return TaskReminderEntity(
      id: (json['id'] ?? '').toString(),
      targetId: (json['targetId'] ?? '').toString(),
      targetType: (json['targetType'] ?? 'task').toString(),
      title: json['title']?.toString(),
      channelId: json['channelId']?.toString(),
      triggerTimeUtc:
          EthiopiaClock.tryParseInstantUtc(json['triggerTimeUtc']?.toString()),
      isActive: json['isActive'] != false,
      createdAt:
          EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString()),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskReminderEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          targetId == other.targetId &&
          targetType == other.targetType &&
          title == other.title &&
          channelId == other.channelId &&
          triggerTimeUtc == other.triggerTimeUtc &&
          isActive == other.isActive &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        targetId,
        targetType,
        title,
        channelId,
        triggerTimeUtc,
        isActive,
        createdAt,
      );
}
