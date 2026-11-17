import '../../core/date/shared_date.dart';

/// Pure domain models for the Daywell To-Do and Projects module.
///
/// Invariants:
/// - Zero dependencies on Flutter widgets or Drift SQLite implementation.
/// - Immutable value objects with copyWith and JSON serialization.

class TaskEntity {
  final String id;
  final String title;
  final String? description;
  final String
      status; // 'inbox', 'not_started', 'in_progress', 'completed', 'cancelled'
  final String priority; // 'low', 'medium', 'high', 'urgent'
  final CalendarDate? dueDate;
  final CalendarDate? scheduledDate;
  final int? estimatedDurationMinutes;
  final String? projectId;
  final String? milestoneId;
  final List<({String title, bool done})> subtasks;
  final List<String> labels;
  final bool isPinned;
  final bool isMyDay;
  final String? recurrenceRule; // 'none', 'daily', 'weekly', 'monthly'
  final DateTime createdAt;
  final DateTime updatedAt;

  TaskEntity({
    required this.id,
    required this.title,
    this.description,
    this.status = 'not_started',
    this.priority = 'medium',
    this.dueDate,
    this.scheduledDate,
    this.estimatedDurationMinutes,
    this.projectId,
    this.milestoneId,
    this.subtasks = const [],
    this.labels = const [],
    this.isPinned = false,
    this.isMyDay = false,
    this.recurrenceRule,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc(),
        updatedAt = (updatedAt ?? EthiopiaClock.nowUtc()).toUtc();

  bool get isCompleted => status == 'completed';
  bool get isOverdue {
    if (dueDate == null || isCompleted || status == 'cancelled') return false;
    return dueDate!.isBefore(CalendarDate.today());
  }

  TaskEntity copyWith({
    String? title,
    String? description,
    String? status,
    String? priority,
    CalendarDate? dueDate,
    bool clearDueDate = false,
    CalendarDate? scheduledDate,
    bool clearScheduledDate = false,
    int? estimatedDurationMinutes,
    String? projectId,
    bool clearProject = false,
    String? milestoneId,
    bool clearMilestone = false,
    List<({String title, bool done})>? subtasks,
    List<String>? labels,
    bool? isPinned,
    bool? isMyDay,
    String? recurrenceRule,
    DateTime? updatedAt,
  }) {
    return TaskEntity(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      scheduledDate:
          clearScheduledDate ? null : (scheduledDate ?? this.scheduledDate),
      estimatedDurationMinutes:
          estimatedDurationMinutes ?? this.estimatedDurationMinutes,
      projectId: clearProject ? null : (projectId ?? this.projectId),
      milestoneId: clearMilestone ? null : (milestoneId ?? this.milestoneId),
      subtasks: subtasks ?? this.subtasks,
      labels: labels ?? this.labels,
      isPinned: isPinned ?? this.isPinned,
      isMyDay: isMyDay ?? this.isMyDay,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
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
        'dueDate': dueDate?.toIsoString(),
        'scheduledDate': scheduledDate?.toIsoString(),
        'estimatedDurationMinutes': estimatedDurationMinutes,
        'projectId': projectId,
        'milestoneId': milestoneId,
        'subtasks': subtasks
            .map((s) => {'title': s.title, 'done': s.done})
            .toList(growable: false),
        'labels': labels,
        'isPinned': isPinned,
        'isMyDay': isMyDay,
        'recurrenceRule': recurrenceRule,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
        'updatedAt': EthiopiaClock.toUtcIsoString(updatedAt),
      };

  factory TaskEntity.fromJson(Map<String, dynamic> json) {
    final rawSubtasks = json['subtasks'];
    final parsedSubtasks = <({String title, bool done})>[];
    if (rawSubtasks is List) {
      for (final item in rawSubtasks) {
        if (item is Map) {
          parsedSubtasks.add((
            title: (item['title'] ?? '').toString(),
            done: item['done'] == true,
          ));
        }
      }
    }

    return TaskEntity(
      id: json['id'],
      title: json['title'] ?? '',
      description: json['description'],
      status: json['status'] ??
          (json['completed'] == true ? 'completed' : 'not_started'),
      priority: json['priority'] ?? 'medium',
      dueDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        json['dueDate']?.toString(),
      ),
      scheduledDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        json['scheduledDate']?.toString(),
      ),
      estimatedDurationMinutes: json['estimatedDurationMinutes'],
      projectId: json['projectId'],
      milestoneId: json['milestoneId'],
      subtasks: parsedSubtasks,
      labels: json['labels'] is List
          ? (json['labels'] as List).map((e) => e.toString()).toList()
          : const [],
      isPinned: json['isPinned'] ?? false,
      isMyDay: json['isMyDay'] ?? false,
      recurrenceRule: json['recurrenceRule'],
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
