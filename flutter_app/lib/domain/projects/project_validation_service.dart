import '../../core/date/shared_date.dart';
import '../../core/shared_foundation_core.dart';
import '../tasks/task_models.dart';
import 'project_models.dart';

class ProjectValidationException implements Exception {
  final String message;
  const ProjectValidationException(this.message);

  @override
  String toString() => 'ProjectValidationException: $message';
}

class ProjectValidationService {
  static final RegExp _fieldIdPattern = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');
  static const Set<String> _allowedCustomFieldTopKeys = {
    'definitions',
    'values',
    'primaryBlockId',
  };
  static const Set<String> _allowedDefinitionKeys = {
    'id',
    'label',
    'type',
    'required',
    'options',
  };

  static void validateProject(ProjectEntity project) {
    if (project.id.trim().isEmpty) {
      throw const ProjectValidationException('Project id must not be empty.');
    }
    final trimmedTitle = project.title.trim();
    if (trimmedTitle.isEmpty || trimmedTitle.length > 200) {
      throw const ProjectValidationException(
        'Project title must be between 1 and 200 characters.',
      );
    }
    if (!SharedProjectRules.statuses.contains(project.status)) {
      throw ProjectValidationException(
        'Invalid project status "${project.status}". Allowed: ${SharedProjectRules.statuses.join(', ')}.',
      );
    }
    if (project.startDate != null &&
        project.targetDate != null &&
        project.targetDate!.isBefore(project.startDate!)) {
      throw const ProjectValidationException(
        'Project targetDate cannot be earlier than startDate.',
      );
    }
    validateCustomFieldsMap(project.customFields);
  }

  static void validateCustomFieldsMap(Map<String, dynamic> raw) {
    if (raw.isEmpty) return;

    for (final key in raw.keys) {
      if (!_allowedCustomFieldTopKeys.contains(key)) {
        throw ProjectValidationException(
          'Unsupported customFields key "$key". Allowed keys: definitions, values, primaryBlockId.',
        );
      }
    }

    if (raw.containsKey('primaryBlockId') && raw['primaryBlockId'] != null) {
      final primary = raw['primaryBlockId'];
      if (primary is! String || primary.trim().isEmpty) {
        throw const ProjectValidationException(
          'customFields.primaryBlockId must be a non-empty string.',
        );
      }
    }

    final defsById = <String, Map<String, dynamic>>{};
    final rawDefs = raw['definitions'];
    if (rawDefs != null) {
      if (rawDefs is! List) {
        throw const ProjectValidationException(
          'customFields.definitions must be an array.',
        );
      }
      if (rawDefs.length > SharedProjectRules.maxCustomFieldDefinitions) {
        throw const ProjectValidationException(
          'customFields.definitions exceeds maximum allowed count (${SharedProjectRules.maxCustomFieldDefinitions}).',
        );
      }
      for (var i = 0; i < rawDefs.length; i++) {
        final item = rawDefs[i];
        if (item is! Map) {
          throw ProjectValidationException(
            'customFields.definitions[$i] must be an object.',
          );
        }
        final def = item.map((k, v) => MapEntry(k.toString(), v));
        for (final key in def.keys) {
          if (!_allowedDefinitionKeys.contains(key)) {
            throw ProjectValidationException(
              'Unsupported custom field definition key "$key" in definitions[$i].',
            );
          }
        }
        final id = def['id'];
        if (id is! String || !_fieldIdPattern.hasMatch(id)) {
          throw ProjectValidationException(
            'Invalid custom field id "${id ?? ''}" at definitions[$i].',
          );
        }
        if (defsById.containsKey(id)) {
          throw ProjectValidationException(
            'Duplicate custom field definition id "$id".',
          );
        }
        final label = def['label'];
        if (label is! String || label.trim().isEmpty || label.length > 120) {
          throw ProjectValidationException(
            'Invalid custom field label for "$id".',
          );
        }
        final rawType = def['type']?.toString();
        final fieldType = ProjectCustomFieldType.tryFromWire(rawType);
        if (fieldType == null) {
          throw ProjectValidationException(
            'Unsupported custom field type "$rawType" for "$id".',
          );
        }
        if (def['required'] != null && def['required'] is! bool) {
          throw ProjectValidationException(
            'customFields.definitions[$i].required must be a boolean.',
          );
        }

        final rawOptions = def['options'];
        if (fieldType == ProjectCustomFieldType.select) {
          if (rawOptions is! List || rawOptions.isEmpty) {
            throw ProjectValidationException(
              'Select custom field "$id" must define non-empty options.',
            );
          }
          if (rawOptions.length >
              SharedProjectRules.maxCustomFieldSelectOptions) {
            throw ProjectValidationException(
              'Select custom field "$id" exceeds max options (${SharedProjectRules.maxCustomFieldSelectOptions}).',
            );
          }
          final seenOptions = <String>{};
          for (final opt in rawOptions) {
            if (opt is! String || opt.trim().isEmpty) {
              throw ProjectValidationException(
                'Select custom field "$id" contains invalid option "$opt".',
              );
            }
            if (!seenOptions.add(opt)) {
              throw ProjectValidationException(
                'Select custom field "$id" contains duplicate option "$opt".',
              );
            }
          }
        } else if (rawOptions != null &&
            (rawOptions is! List || rawOptions.isNotEmpty)) {
          throw ProjectValidationException(
            'Non-select custom field "$id" cannot define options.',
          );
        }
        defsById[id] = def;
      }
    }

    final rawValues = raw['values'];
    if (rawValues != null && rawValues is! Map) {
      throw const ProjectValidationException(
        'customFields.values must be an object.',
      );
    }
    final valuesMap = rawValues is Map
        ? rawValues.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};

    for (final entry in valuesMap.entries) {
      final def = defsById[entry.key];
      if (def == null) {
        throw ProjectValidationException(
          'Unknown custom field value key "${entry.key}" without a matching definition.',
        );
      }
      final val = entry.value;
      if (val is Map || val is List) {
        throw ProjectValidationException(
          'Nested objects or arrays are not allowed in custom field value "${entry.key}".',
        );
      }
      final isRequired = def['required'] == true;
      if (val == null) {
        if (isRequired) {
          throw ProjectValidationException(
            'Required custom field "${entry.key}" cannot be null.',
          );
        }
        continue;
      }
      final fieldType =
          ProjectCustomFieldType.tryFromWire(def['type'].toString())!;
      switch (fieldType) {
        case ProjectCustomFieldType.text:
          if (val is! String) {
            throw ProjectValidationException(
              'Custom field "${entry.key}" expects a text string.',
            );
          }
          if (val.length > SharedProjectRules.maxCustomFieldTextLength) {
            throw ProjectValidationException(
              'Custom field "${entry.key}" exceeds max length (${SharedProjectRules.maxCustomFieldTextLength}).',
            );
          }
          if (isRequired && val.trim().isEmpty) {
            throw ProjectValidationException(
              'Required custom field "${entry.key}" cannot be blank.',
            );
          }
        case ProjectCustomFieldType.number:
          if (val is! num || !val.isFinite) {
            throw ProjectValidationException(
              'Custom field "${entry.key}" expects a finite number.',
            );
          }
        case ProjectCustomFieldType.date:
          if (val is! String || CalendarDate.tryParse(val) == null) {
            throw ProjectValidationException(
              'Custom field "${entry.key}" expects canonical YYYY-MM-DD date.',
            );
          }
        case ProjectCustomFieldType.boolean:
          if (val is! bool) {
            throw ProjectValidationException(
              'Custom field "${entry.key}" expects a boolean.',
            );
          }
        case ProjectCustomFieldType.select:
          final opts = (def['options'] as List).cast<String>();
          if (val is! String || !opts.contains(val)) {
            throw ProjectValidationException(
              'Custom field "${entry.key}" value "$val" is not in allowed options.',
            );
          }
      }
    }

    for (final defEntry in defsById.entries) {
      if (defEntry.value['required'] == true &&
          !valuesMap.containsKey(defEntry.key)) {
        throw ProjectValidationException(
          'Missing value for required custom field "${defEntry.key}".',
        );
      }
    }
  }

  static void validateBlock(
    ProjectTrackingBlockEntity block, {
    required String expectedProjectId,
    List<ProjectTrackingBlockEntity> projectBlocks = const [],
    bool isNew = true,
  }) {
    if (block.id.trim().isEmpty) {
      throw const ProjectValidationException('Block id must not be empty.');
    }
    if (block.projectId != expectedProjectId) {
      throw ProjectValidationException(
        'Block "${block.id}" projectId "${block.projectId}" does not match project "$expectedProjectId".',
      );
    }
    if (isNew && projectBlocks.any((b) => b.id == block.id)) {
      throw ProjectValidationException(
        'Duplicate tracking block id "${block.id}".',
      );
    }
    if (isNew &&
        projectBlocks.length >= SharedProjectRules.maxBlocksPerProject) {
      throw const ProjectValidationException(
        'Project exceeds maximum tracking blocks (${SharedProjectRules.maxBlocksPerProject}).',
      );
    }
    final title = block.title.trim();
    if (title.isEmpty || title.length > 200) {
      throw const ProjectValidationException(
        'Block title must be between 1 and 200 characters.',
      );
    }
    if (block.sortOrder < 0) {
      throw const ProjectValidationException(
        'Block sortOrder must be non-negative.',
      );
    }
    if (block.targetValue != null &&
        (!block.targetValue!.isFinite || block.targetValue! < 0)) {
      throw const ProjectValidationException(
        'Block targetValue must be finite and non-negative.',
      );
    }
    if (block.dailyTargetValue != null &&
        (!block.dailyTargetValue!.isFinite || block.dailyTargetValue! < 0)) {
      throw const ProjectValidationException(
        'Block dailyTargetValue must be finite and non-negative.',
      );
    }

    switch (block.blockType) {
      case ProjectBlockType.counter:
        final cfg = CounterBlockConfig.fromMap(block.config);
        final sourceId = cfg.rollupSourceBlockId;
        if (sourceId != null) {
          if (sourceId == block.id) {
            throw ProjectValidationException(
              'Counter block "${block.id}" cannot roll up from itself.',
            );
          }
          if (cfg.allowDirectLogging) {
            throw ProjectValidationException(
              'Rollup counter block "${block.id}" cannot allow direct logging alongside rollupSourceBlockId "$sourceId".',
            );
          }
          final sourceMatches =
              projectBlocks.where((b) => b.id == sourceId).toList();
          if (sourceMatches.isEmpty) {
            throw ProjectValidationException(
              'Counter block "${block.id}" references missing rollupSourceBlockId "$sourceId" in project "$expectedProjectId".',
            );
          }
          final sourceBlock = sourceMatches.first;
          if (sourceBlock.blockType == ProjectBlockType.counter) {
            final nested =
                CounterBlockConfig.fromMap(sourceBlock.config).rollupSourceBlockId;
            if (nested != null) {
              throw ProjectValidationException(
                'Counter block "${block.id}" cannot chain rollups through another rollup counter "$sourceId".',
              );
            }
          }
        }
      case ProjectBlockType.groupedList:
        GroupedListBlockConfig.fromMap(block.config);
      case ProjectBlockType.checklist:
        ChecklistBlockConfig.fromMap(block.config);
      case ProjectBlockType.schedule:
        final cfg = ScheduleBlockConfig.fromMap(block.config);
        final rawRule = block.config['completionRule']?.toString();
        if (rawRule != null &&
            ScheduleItemCompletionRule.tryFromWire(rawRule) == null) {
          throw ProjectValidationException(
            'Unsupported schedule completionRule "$rawRule".',
          );
        }
        if (!cfg.autoCompleteThresholdRatio.isFinite ||
            cfg.autoCompleteThresholdRatio <= 0 ||
            cfg.autoCompleteThresholdRatio > 1.0) {
          throw const ProjectValidationException(
            'Schedule autoCompleteThresholdRatio must be within (0.0, 1.0].',
          );
        }
    }
  }

  static void validateRecord(
    ProjectTrackingRecordEntity record, {
    required ProjectTrackingBlockEntity block,
    List<ProjectTrackingRecordEntity> existingBlockRecords = const [],
    bool isNew = true,
  }) {
    if (record.id.trim().isEmpty) {
      throw const ProjectValidationException('Record id must not be empty.');
    }
    if (record.projectId != block.projectId) {
      throw ProjectValidationException(
        'Record "${record.id}" projectId "${record.projectId}" does not match block project "${block.projectId}".',
      );
    }
    if (record.blockId != block.id) {
      throw ProjectValidationException(
        'Record "${record.id}" blockId "${record.blockId}" does not match block "${block.id}".',
      );
    }
    if (isNew && existingBlockRecords.any((r) => r.id == record.id)) {
      throw ProjectValidationException(
        'Duplicate tracking record id "${record.id}".',
      );
    }
    if (record.sortOrder < 0) {
      throw const ProjectValidationException(
        'Record sortOrder must be non-negative.',
      );
    }
    if (record.targetValue != null &&
        (!record.targetValue!.isFinite || record.targetValue! < 0)) {
      throw const ProjectValidationException(
        'Record targetValue must be finite and non-negative.',
      );
    }
    if (record.durationMinutes != null && record.durationMinutes! < 0) {
      throw const ProjectValidationException(
        'Record durationMinutes must be non-negative.',
      );
    }

    final byId = <String, ProjectTrackingRecordEntity>{
      for (final item in existingBlockRecords) item.id: item,
    };

    ProjectTrackingRecordEntity? parent;
    if (record.parentRecordId != null) {
      if (record.parentRecordId == record.id) {
        throw ProjectValidationException(
          'Record "${record.id}" cannot set itself as parentRecordId.',
        );
      }
      parent = byId[record.parentRecordId];
      if (parent == null) {
        throw ProjectValidationException(
          'Record "${record.id}" references missing or cross-block parentRecordId "${record.parentRecordId}".',
        );
      }
      // Walk ancestors to guard against cycles and excessive nesting depth
      final visited = <String>{record.id};
      ProjectTrackingRecordEntity? cursor = parent;
      var depth = 1;
      while (cursor != null) {
        if (!visited.add(cursor.id)) {
          throw ProjectValidationException(
            'Cycle detected in parentRecordId hierarchy involving "${record.id}".',
          );
        }
        depth += 1;
        if (depth > SharedProjectRules.maxHierarchyDepth) {
          throw ProjectValidationException(
            'Record hierarchy exceeds maximum depth (${SharedProjectRules.maxHierarchyDepth}).',
          );
        }
        cursor =
            cursor.parentRecordId != null ? byId[cursor.parentRecordId!] : null;
      }
    }

    final trimmedTitle = record.title?.trim();
    if (trimmedTitle != null &&
        trimmedTitle.length > SharedProjectRules.maxTrackingRecordTitleLength) {
      throw ProjectValidationException(
        'Record title cannot exceed ${SharedProjectRules.maxTrackingRecordTitleLength} characters.',
      );
    }

    switch (record.recordType) {
      case ProjectRecordType.group:
        if (block.blockType != ProjectBlockType.groupedList) {
          throw ProjectValidationException(
            'Record type "group" is only valid in grouped_list blocks.',
          );
        }
        if (record.parentRecordId != null) {
          throw const ProjectValidationException(
            'Group records must be top-level (parentRecordId must be null).',
          );
        }
        if ((record.title ?? '').trim().isEmpty) {
          throw const ProjectValidationException(
            'Group record must have a non-empty title.',
          );
        }
      case ProjectRecordType.groupedItem:
        if (block.blockType != ProjectBlockType.groupedList) {
          throw ProjectValidationException(
            'Record type "grouped_item" is only valid in grouped_list blocks.',
          );
        }
        if ((record.title ?? '').trim().isEmpty) {
          throw const ProjectValidationException(
            'Grouped item record must have a non-empty title.',
          );
        }
        if (parent != null && parent.recordType != ProjectRecordType.group) {
          throw ProjectValidationException(
            'Grouped item "${record.id}" parentRecordId must reference a "group" record.',
          );
        }
      case ProjectRecordType.checklistItem:
        if (block.blockType != ProjectBlockType.checklist) {
          throw ProjectValidationException(
            'Record type "checklist_item" is only valid in checklist blocks.',
          );
        }
        if (record.parentRecordId != null) {
          throw const ProjectValidationException(
            'Checklist items cannot have a parentRecordId.',
          );
        }
        if ((record.title ?? '').trim().isEmpty) {
          throw const ProjectValidationException(
            'Checklist item record must have a non-empty title.',
          );
        }
      case ProjectRecordType.scheduleItem:
        if (block.blockType != ProjectBlockType.schedule) {
          throw ProjectValidationException(
            'Record type "schedule_item" is only valid in schedule blocks.',
          );
        }
        if (record.parentRecordId != null) {
          throw const ProjectValidationException(
            'Schedule items cannot have a parentRecordId.',
          );
        }
        if ((record.title ?? '').trim().isEmpty) {
          throw const ProjectValidationException(
            'Schedule item record must have a non-empty title.',
          );
        }
      case ProjectRecordType.progressLog:
        if (block.blockType == ProjectBlockType.checklist) {
          throw const ProjectValidationException(
            'Progress logs cannot be attached to checklist blocks.',
          );
        }
        if (record.recordedDate == null) {
          throw ProjectValidationException(
            'Progress log "${record.id}" requires recordedDate (YYYY-MM-DD).',
          );
        }
        if (block.blockType == ProjectBlockType.counter) {
          final cfg = CounterBlockConfig.fromMap(block.config);
          if (cfg.rollupSourceBlockId != null || !cfg.allowDirectLogging) {
            throw ProjectValidationException(
              'Cannot log directly on rollup counter block "${block.id}" (source: "${cfg.rollupSourceBlockId}"). Log against the source block items instead.',
            );
          }
          if (record.parentRecordId != null) {
            throw const ProjectValidationException(
              'Direct counter progress logs must have parentRecordId == null.',
            );
          }
        } else if (block.blockType == ProjectBlockType.groupedList) {
          if (parent == null ||
              parent.recordType != ProjectRecordType.groupedItem) {
            throw ProjectValidationException(
              'Progress log "${record.id}" in a grouped_list block must reference a parent grouped_item record.',
            );
          }
        } else if (block.blockType == ProjectBlockType.schedule) {
          if (parent == null ||
              parent.recordType != ProjectRecordType.scheduleItem) {
            throw ProjectValidationException(
              'Progress log "${record.id}" in a schedule block must reference a parent schedule_item record.',
            );
          }
        }

        final delta = record.deltaValue;
        if (delta == null || !delta.isFinite || delta == 0) {
          throw ProjectValidationException(
            'Progress log "${record.id}" must have a finite non-zero deltaValue.',
          );
        }
        if (record.isCorrection) {
          final targetId = record.compensatesRecordId?.trim() ?? '';
          final reason = record.correctionReason?.trim() ?? '';
          if (targetId.isEmpty) {
            throw const ProjectValidationException(
              'Compensating progress correction requires metadata.compensatesRecordId.',
            );
          }
          if (reason.isEmpty) {
            throw const ProjectValidationException(
              'Compensating progress correction requires metadata.correctionReason.',
            );
          }
          if (targetId == record.id) {
            throw const ProjectValidationException(
              'Compensating progress correction cannot reference itself.',
            );
          }
          final target = byId[targetId];
          if (target == null ||
              target.recordType != ProjectRecordType.progressLog) {
            throw ProjectValidationException(
              'Compensating correction "${record.id}" references missing or non-log record "$targetId".',
            );
          }
          if (target.parentRecordId != record.parentRecordId) {
            throw ProjectValidationException(
              'Compensating correction "${record.id}" must match parentRecordId of target log "$targetId".',
            );
          }
        } else if (delta <= 0) {
          throw ProjectValidationException(
            'Progress log "${record.id}" deltaValue must be > 0 (use explicit compensating correction for negative adjustments).',
          );
        }
    }
  }

  static void assertAppendOnlyLogProtection({
    required ProjectTrackingRecordEntity existing,
    bool isDelete = false,
  }) {
    if (existing.recordType == ProjectRecordType.progressLog) {
      if (isDelete) {
        throw ProjectValidationException(
          'Progress log "${existing.id}" is append-only and cannot be silently deleted; append a compensating correction instead.',
        );
      }
      throw ProjectValidationException(
        'Progress log "${existing.id}" is append-only and cannot be mutated; append a compensating correction instead.',
      );
    }
  }
}
