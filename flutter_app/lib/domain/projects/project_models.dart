import '../../core/date/shared_date.dart';

enum ProjectBlockType {
  counter('counter'),
  groupedList('grouped_list'),
  checklist('checklist'),
  schedule('schedule');

  final String wireValue;
  const ProjectBlockType(this.wireValue);

  static ProjectBlockType fromWire(String raw) {
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    throw ArgumentError.value(
        raw, 'blockType', 'Unsupported project block type');
  }

  static ProjectBlockType? tryFromWire(String? raw) {
    if (raw == null) return null;
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    return null;
  }
}

enum ProjectRecordType {
  group('group'),
  groupedItem('grouped_item'),
  checklistItem('checklist_item'),
  scheduleItem('schedule_item'),
  progressLog('progress_log');

  final String wireValue;
  const ProjectRecordType(this.wireValue);

  static ProjectRecordType fromWire(String raw) {
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    throw ArgumentError.value(
      raw,
      'recordType',
      'Unsupported project record type',
    );
  }

  static ProjectRecordType? tryFromWire(String? raw) {
    if (raw == null) return null;
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    return null;
  }
}

enum ProjectCustomFieldType {
  text('text'),
  number('number'),
  date('date'),
  boolean('boolean'),
  select('select');

  final String wireValue;
  const ProjectCustomFieldType(this.wireValue);

  static ProjectCustomFieldType? tryFromWire(String? raw) {
    if (raw == null) return null;
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    return null;
  }
}

enum ScheduleItemCompletionRule {
  manual('manual'),
  thresholdPercent('threshold_percent'),
  exactDuration('exact_duration');

  final String wireValue;
  const ScheduleItemCompletionRule(this.wireValue);

  static ScheduleItemCompletionRule? tryFromWire(String? raw) {
    if (raw == null) return null;
    for (final value in values) {
      if (value.wireValue == raw) return value;
    }
    return null;
  }
}

class ProjectCustomFieldDefinition {
  final String id;
  final String label;
  final ProjectCustomFieldType type;
  final bool required;
  final List<String> options;

  ProjectCustomFieldDefinition({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    List<String> options = const [],
  }) : options = List<String>.unmodifiable(options);

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'type': type.wireValue,
        'required': required,
        if (options.isNotEmpty) 'options': options,
      };
}

class ProjectCustomFieldsPayload {
  final List<ProjectCustomFieldDefinition> definitions;
  final Map<String, Object?> values;
  final String? primaryBlockId;

  ProjectCustomFieldsPayload({
    List<ProjectCustomFieldDefinition> definitions = const [],
    Map<String, Object?> values = const {},
    this.primaryBlockId,
  })  : definitions =
            List<ProjectCustomFieldDefinition>.unmodifiable(definitions),
        values = Map<String, Object?>.unmodifiable(values);

  Map<String, dynamic> toJson() => {
        if (definitions.isNotEmpty)
          'definitions': definitions.map((d) => d.toJson()).toList(),
        if (values.isNotEmpty) 'values': values,
        if (primaryBlockId != null && primaryBlockId!.trim().isNotEmpty)
          'primaryBlockId': primaryBlockId!.trim(),
      };

  static ProjectCustomFieldsPayload fromMap(Map<String, dynamic> raw) {
    final defs = <ProjectCustomFieldDefinition>[];
    final rawDefs = raw['definitions'];
    if (rawDefs is List) {
      for (final item in rawDefs) {
        if (item is Map) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          final type =
              ProjectCustomFieldType.tryFromWire(map['type']?.toString());
          if (type != null) {
            final opts = <String>[];
            if (map['options'] is List) {
              for (final opt in (map['options'] as List)) {
                opts.add(opt.toString());
              }
            }
            defs.add(
              ProjectCustomFieldDefinition(
                id: map['id']?.toString() ?? '',
                label: map['label']?.toString() ?? '',
                type: type,
                required: map['required'] == true,
                options: opts,
              ),
            );
          }
        }
      }
    }

    final vals = <String, Object?>{};
    final rawVals = raw['values'];
    if (rawVals is Map) {
      for (final entry in rawVals.entries) {
        vals[entry.key.toString()] = entry.value;
      }
    }

    final rawPrimary = raw['primaryBlockId']?.toString().trim();
    return ProjectCustomFieldsPayload(
      definitions: defs,
      values: vals,
      primaryBlockId:
          (rawPrimary == null || rawPrimary.isEmpty) ? null : rawPrimary,
    );
  }
}

class CounterBlockConfig {
  final String? rollupSourceBlockId;
  final bool allowDirectLogging;

  const CounterBlockConfig({
    this.rollupSourceBlockId,
    bool? allowDirectLogging,
  }) : allowDirectLogging = allowDirectLogging ?? (rollupSourceBlockId == null);

  Map<String, dynamic> toJson() => {
        if (rollupSourceBlockId != null)
          'rollupSourceBlockId': rollupSourceBlockId,
        'allowDirectLogging': allowDirectLogging,
      };

  static CounterBlockConfig fromMap(Map<String, dynamic> raw) {
    final sourceId = raw['rollupSourceBlockId']?.toString().trim();
    final normalizedSource =
        (sourceId == null || sourceId.isEmpty) ? null : sourceId;
    final rawAllow = raw['allowDirectLogging'];
    return CounterBlockConfig(
      rollupSourceBlockId: normalizedSource,
      allowDirectLogging:
          rawAllow is bool ? rawAllow : (normalizedSource == null),
    );
  }
}

class GroupedListBlockConfig {
  final bool showGroupTotals;
  final bool showDailyTotals;
  final String? groupLabel;
  final String? itemLabel;

  const GroupedListBlockConfig({
    this.showGroupTotals = true,
    this.showDailyTotals = true,
    this.groupLabel,
    this.itemLabel,
  });

  Map<String, dynamic> toJson() => {
        'showGroupTotals': showGroupTotals,
        'showDailyTotals': showDailyTotals,
        if (groupLabel != null) 'groupLabel': groupLabel,
        if (itemLabel != null) 'itemLabel': itemLabel,
      };

  static GroupedListBlockConfig fromMap(Map<String, dynamic> raw) {
    return GroupedListBlockConfig(
      showGroupTotals: raw['showGroupTotals'] is bool
          ? raw['showGroupTotals'] as bool
          : true,
      showDailyTotals: raw['showDailyTotals'] is bool
          ? raw['showDailyTotals'] as bool
          : true,
      groupLabel: raw['groupLabel']?.toString(),
      itemLabel: raw['itemLabel']?.toString(),
    );
  }
}

class ChecklistBlockConfig {
  final bool allowReorder;

  const ChecklistBlockConfig({this.allowReorder = true});

  Map<String, dynamic> toJson() => {'allowReorder': allowReorder};

  static ChecklistBlockConfig fromMap(Map<String, dynamic> raw) {
    return ChecklistBlockConfig(
      allowReorder:
          raw['allowReorder'] is bool ? raw['allowReorder'] as bool : true,
    );
  }
}

class ScheduleBlockConfig {
  final ScheduleItemCompletionRule completionRule;
  final double autoCompleteThresholdRatio;
  final bool trackActualDuration;

  const ScheduleBlockConfig({
    this.completionRule = ScheduleItemCompletionRule.manual,
    this.autoCompleteThresholdRatio = 1.0,
    this.trackActualDuration = true,
  });

  Map<String, dynamic> toJson() => {
        'completionRule': completionRule.wireValue,
        'autoCompleteThresholdRatio': autoCompleteThresholdRatio,
        'trackActualDuration': trackActualDuration,
      };

  static ScheduleBlockConfig fromMap(Map<String, dynamic> raw) {
    final rule = ScheduleItemCompletionRule.tryFromWire(
          raw['completionRule']?.toString(),
        ) ??
        ScheduleItemCompletionRule.manual;
    final rawRatio = raw['autoCompleteThresholdRatio'];
    final ratio = rawRatio is num ? rawRatio.toDouble() : 1.0;
    return ScheduleBlockConfig(
      completionRule: rule,
      autoCompleteThresholdRatio: ratio,
      trackActualDuration: raw['trackActualDuration'] is bool
          ? raw['trackActualDuration'] as bool
          : true,
    );
  }
}

class ProjectTrackingBlockEntity {
  final String id;
  final String projectId;
  final ProjectBlockType blockType;
  final String title;
  final int sortOrder;
  final String? unitLabel;
  final double? targetValue;
  final double? dailyTargetValue;
  final Map<String, dynamic> config;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProjectTrackingBlockEntity({
    required this.id,
    required this.projectId,
    required this.blockType,
    required this.title,
    this.sortOrder = 0,
    this.unitLabel,
    this.targetValue,
    this.dailyTargetValue,
    Map<String, dynamic>? config,
    this.isArchived = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : config = Map<String, dynamic>.unmodifiable(
          config ?? const <String, dynamic>{},
        ),
        createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc(),
        updatedAt = (updatedAt ?? createdAt ?? EthiopiaClock.nowUtc()).toUtc();

  ProjectTrackingBlockEntity copyWith({
    ProjectBlockType? blockType,
    String? title,
    int? sortOrder,
    String? unitLabel,
    bool clearUnitLabel = false,
    double? targetValue,
    bool clearTargetValue = false,
    double? dailyTargetValue,
    bool clearDailyTargetValue = false,
    Map<String, dynamic>? config,
    bool? isArchived,
    DateTime? updatedAt,
  }) {
    return ProjectTrackingBlockEntity(
      id: id,
      projectId: projectId,
      blockType: blockType ?? this.blockType,
      title: title ?? this.title,
      sortOrder: sortOrder ?? this.sortOrder,
      unitLabel: clearUnitLabel ? null : (unitLabel ?? this.unitLabel),
      targetValue: clearTargetValue ? null : (targetValue ?? this.targetValue),
      dailyTargetValue: clearDailyTargetValue
          ? null
          : (dailyTargetValue ?? this.dailyTargetValue),
      config: config ?? this.config,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'blockType': blockType.wireValue,
        'title': title,
        'sortOrder': sortOrder,
        'unitLabel': unitLabel,
        'targetValue': targetValue,
        'dailyTargetValue': dailyTargetValue,
        'config': config,
        'isArchived': isArchived,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
        'updatedAt': EthiopiaClock.toUtcIsoString(updatedAt),
      };

  factory ProjectTrackingBlockEntity.fromJson(Map<String, dynamic> json) {
    final created =
        EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString());
    final updated =
        EthiopiaClock.tryParseInstantUtc(json['updatedAt']?.toString());
    final rawConfig = json['config'];
    return ProjectTrackingBlockEntity(
      id: json['id']?.toString() ?? '',
      projectId: json['projectId']?.toString() ?? '',
      blockType: ProjectBlockType.fromWire(json['blockType']?.toString() ?? ''),
      title: json['title']?.toString() ?? '',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      unitLabel: json['unitLabel']?.toString(),
      targetValue: (json['targetValue'] as num?)?.toDouble(),
      dailyTargetValue: (json['dailyTargetValue'] as num?)?.toDouble(),
      config: rawConfig is Map
          ? rawConfig.map((k, v) => MapEntry(k.toString(), v))
          : const <String, dynamic>{},
      isArchived: json['isArchived'] == true,
      createdAt: created,
      updatedAt: updated ?? created,
    );
  }
}

class ProjectTrackingRecordEntity {
  final String id;
  final String projectId;
  final String blockId;
  final String? parentRecordId;
  final ProjectRecordType recordType;
  final String? title;
  final int sortOrder;
  final double? targetValue;
  final double? deltaValue;
  final int? durationMinutes;
  final bool isCompleted;
  final DateTime? completedAt;
  final CalendarDate? recordedDate;
  final CalendarDate? scheduledDate;
  final String? linkedTaskId;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProjectTrackingRecordEntity({
    required this.id,
    required this.projectId,
    required this.blockId,
    this.parentRecordId,
    required this.recordType,
    this.title,
    this.sortOrder = 0,
    this.targetValue,
    this.deltaValue,
    this.durationMinutes,
    this.isCompleted = false,
    DateTime? completedAt,
    this.recordedDate,
    this.scheduledDate,
    this.linkedTaskId,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : completedAt = completedAt?.toUtc(),
        metadata = Map<String, dynamic>.unmodifiable(
          metadata ?? const <String, dynamic>{},
        ),
        createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc(),
        updatedAt = (updatedAt ?? createdAt ?? EthiopiaClock.nowUtc()).toUtc();

  bool get isCorrection => metadata['isCorrection'] == true;
  String? get compensatesRecordId =>
      metadata['compensatesRecordId']?.toString();
  String? get correctionReason => metadata['correctionReason']?.toString();

  ProjectTrackingRecordEntity copyWith({
    String? parentRecordId,
    bool clearParentRecordId = false,
    String? title,
    bool clearTitle = false,
    int? sortOrder,
    double? targetValue,
    bool clearTargetValue = false,
    double? deltaValue,
    bool clearDeltaValue = false,
    int? durationMinutes,
    bool clearDurationMinutes = false,
    bool? isCompleted,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    CalendarDate? recordedDate,
    bool clearRecordedDate = false,
    CalendarDate? scheduledDate,
    bool clearScheduledDate = false,
    String? linkedTaskId,
    bool clearLinkedTaskId = false,
    Map<String, dynamic>? metadata,
    DateTime? updatedAt,
  }) {
    return ProjectTrackingRecordEntity(
      id: id,
      projectId: projectId,
      blockId: blockId,
      parentRecordId:
          clearParentRecordId ? null : (parentRecordId ?? this.parentRecordId),
      recordType: recordType,
      title: clearTitle ? null : (title ?? this.title),
      sortOrder: sortOrder ?? this.sortOrder,
      targetValue: clearTargetValue ? null : (targetValue ?? this.targetValue),
      deltaValue: clearDeltaValue ? null : (deltaValue ?? this.deltaValue),
      durationMinutes: clearDurationMinutes
          ? null
          : (durationMinutes ?? this.durationMinutes),
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      recordedDate:
          clearRecordedDate ? null : (recordedDate ?? this.recordedDate),
      scheduledDate:
          clearScheduledDate ? null : (scheduledDate ?? this.scheduledDate),
      linkedTaskId:
          clearLinkedTaskId ? null : (linkedTaskId ?? this.linkedTaskId),
      metadata: metadata ?? this.metadata,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'blockId': blockId,
        'parentRecordId': parentRecordId,
        'recordType': recordType.wireValue,
        'title': title,
        'sortOrder': sortOrder,
        'targetValue': targetValue,
        'deltaValue': deltaValue,
        'durationMinutes': durationMinutes,
        'isCompleted': isCompleted,
        'completedAt': completedAt != null
            ? EthiopiaClock.toUtcIsoString(completedAt!)
            : null,
        'recordedDate': recordedDate?.toIsoString(),
        'scheduledDate': scheduledDate?.toIsoString(),
        'linkedTaskId': linkedTaskId,
        'metadata': metadata,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
        'updatedAt': EthiopiaClock.toUtcIsoString(updatedAt),
      };

  factory ProjectTrackingRecordEntity.fromJson(Map<String, dynamic> json) {
    final created =
        EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString());
    final updated =
        EthiopiaClock.tryParseInstantUtc(json['updatedAt']?.toString());
    final rawMeta = json['metadata'];
    return ProjectTrackingRecordEntity(
      id: json['id']?.toString() ?? '',
      projectId: json['projectId']?.toString() ?? '',
      blockId: json['blockId']?.toString() ?? '',
      parentRecordId: json['parentRecordId']?.toString(),
      recordType:
          ProjectRecordType.fromWire(json['recordType']?.toString() ?? ''),
      title: json['title']?.toString(),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      targetValue: (json['targetValue'] as num?)?.toDouble(),
      deltaValue: (json['deltaValue'] as num?)?.toDouble(),
      durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
      isCompleted: json['isCompleted'] == true,
      completedAt:
          EthiopiaClock.tryParseInstantUtc(json['completedAt']?.toString()),
      recordedDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        json['recordedDate']?.toString(),
      ),
      scheduledDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        json['scheduledDate']?.toString(),
      ),
      linkedTaskId: json['linkedTaskId']?.toString(),
      metadata: rawMeta is Map
          ? rawMeta.map((k, v) => MapEntry(k.toString(), v))
          : const <String, dynamic>{},
      createdAt: created,
      updatedAt: updated ?? created,
    );
  }
}

class ProjectGroupMetric {
  final String groupId;
  final String title;
  final double? targetValue;
  final double loggedTotal;
  final double targetCompletedTotal;
  final double overTargetAmount;
  final int overTargetItemCount;
  final int itemCount;
  final int completedItemCount;
  final double? progressPercent;

  const ProjectGroupMetric({
    required this.groupId,
    required this.title,
    this.targetValue,
    required this.loggedTotal,
    double? targetCompletedTotal,
    this.overTargetAmount = 0,
    this.overTargetItemCount = 0,
    required this.itemCount,
    required this.completedItemCount,
    this.progressPercent,
  }) : targetCompletedTotal = targetCompletedTotal ?? loggedTotal;
}

class ProjectBlockProgressMetric {
  final String blockId;
  final ProjectBlockType blockType;
  final String title;
  final String? unitLabel;
  final bool isArchived;
  final double loggedTotal;
  final double? targetCompletedTotal;
  final double? overTargetAmount;
  final int? overTargetItemCount;
  final double? targetValue;
  final double? progressPercent;
  final double? dailyTargetValue;
  final double todayTotal;
  final Map<String, double> dailyTotalsByDate;
  final int completedCount;
  final int totalCount;
  final int plannedDurationMinutes;
  final int actualLoggedDurationMinutes;
  final Map<String, double> itemTotals;
  final List<ProjectGroupMetric> groupMetrics;
  final String? rollupSourceBlockId;
  final double? paceNeededPerDay;
  final int? daysRemaining;

  ProjectBlockProgressMetric({
    required this.blockId,
    required this.blockType,
    required this.title,
    this.unitLabel,
    this.isArchived = false,
    this.loggedTotal = 0,
    this.targetCompletedTotal,
    this.overTargetAmount,
    this.overTargetItemCount,
    this.targetValue,
    this.progressPercent,
    this.dailyTargetValue,
    this.todayTotal = 0,
    Map<String, double>? dailyTotalsByDate,
    this.completedCount = 0,
    this.totalCount = 0,
    this.plannedDurationMinutes = 0,
    this.actualLoggedDurationMinutes = 0,
    Map<String, double>? itemTotals,
    List<ProjectGroupMetric>? groupMetrics,
    this.rollupSourceBlockId,
    this.paceNeededPerDay,
    this.daysRemaining,
  })  : dailyTotalsByDate = Map<String, double>.unmodifiable(
          dailyTotalsByDate ?? const <String, double>{},
        ),
        itemTotals = Map<String, double>.unmodifiable(
          itemTotals ?? const <String, double>{},
        ),
        groupMetrics = List<ProjectGroupMetric>.unmodifiable(
          groupMetrics ?? const <ProjectGroupMetric>[],
        );
}

class ProjectProgressSummary {
  final String projectId;
  final List<ProjectBlockProgressMetric> blockMetrics;
  final String? primaryBlockId;
  final ProjectBlockProgressMetric? primaryMetric;
  final double? overallPercentage;
  final bool hasInvalidPrimaryBlockReference;
  final int linkedTasksCompleted;
  final int linkedTasksTotal;
  final int milestonesCompleted;
  final int milestonesTotal;

  ProjectProgressSummary({
    required this.projectId,
    required List<ProjectBlockProgressMetric> blockMetrics,
    this.primaryBlockId,
    this.primaryMetric,
    this.overallPercentage,
    this.hasInvalidPrimaryBlockReference = false,
    this.linkedTasksCompleted = 0,
    this.linkedTasksTotal = 0,
    this.milestonesCompleted = 0,
    this.milestonesTotal = 0,
  }) : blockMetrics = List<ProjectBlockProgressMetric>.unmodifiable(
          blockMetrics,
        );
}
