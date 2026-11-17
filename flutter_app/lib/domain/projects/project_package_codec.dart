import 'dart:convert';
import 'dart:math';

import '../../core/date/shared_date.dart';
import '../../core/shared_foundation_core.dart';
import '../tasks/task_models.dart';
import 'project_models.dart';

enum ProjectPackageErrorKind {
  malformedJson,
  invalidFormat,
  unsupportedVersion,
  validationFailed,
}

class ProjectPackageException implements Exception {
  final ProjectPackageErrorKind kind;
  final String message;

  const ProjectPackageException(this.kind, this.message);

  @override
  String toString() => message;
}

class DaywellProjectPackage {
  final String formatId;
  final int formatVersion;
  final DateTime exportedAt;
  final String sourcePlatform;
  final ProjectEntity project;
  final List<ProjectTrackingBlockEntity> trackingBlocks;
  final List<ProjectTrackingRecordEntity> trackingRecords;

  DaywellProjectPackage({
    required this.formatId,
    required this.formatVersion,
    required DateTime exportedAt,
    required this.sourcePlatform,
    required this.project,
    required List<ProjectTrackingBlockEntity> trackingBlocks,
    required List<ProjectTrackingRecordEntity> trackingRecords,
  })  : exportedAt = exportedAt.toUtc(),
        trackingBlocks =
            List<ProjectTrackingBlockEntity>.unmodifiable(trackingBlocks),
        trackingRecords =
            List<ProjectTrackingRecordEntity>.unmodifiable(trackingRecords);

  Map<String, dynamic> toJson() => {
        'formatId': formatId,
        'formatVersion': formatVersion,
        'exportedAt': EthiopiaClock.toUtcIsoString(exportedAt),
        'sourcePlatform': sourcePlatform,
        'project': _projectToPackageJson(project),
        'trackingBlocks':
            trackingBlocks.map(_blockToPackageJson).toList(growable: false),
        'trackingRecords':
            trackingRecords.map(_recordToPackageJson).toList(growable: false),
      };
}

class PreparedProjectPackageImport {
  final int sourceFormatVersion;
  final String sourcePlatform;
  final DateTime exportedAt;
  final ProjectEntity project;
  final List<ProjectTrackingBlockEntity> trackingBlocks;
  final List<ProjectTrackingRecordEntity> trackingRecords;

  PreparedProjectPackageImport({
    required this.sourceFormatVersion,
    required this.sourcePlatform,
    required DateTime exportedAt,
    required this.project,
    required List<ProjectTrackingBlockEntity> trackingBlocks,
    required List<ProjectTrackingRecordEntity> trackingRecords,
  })  : exportedAt = exportedAt.toUtc(),
        trackingBlocks =
            List<ProjectTrackingBlockEntity>.unmodifiable(trackingBlocks),
        trackingRecords =
            List<ProjectTrackingRecordEntity>.unmodifiable(trackingRecords);
}

Map<String, dynamic> _projectToPackageJson(ProjectEntity project) {
  final map = <String, dynamic>{
    'id': project.id,
    'title': project.title.trim(),
    if (project.description != null && project.description!.trim().isNotEmpty)
      'description': project.description!.trim(),
    'status': project.status,
    if (project.targetDate != null)
      'targetDate': project.targetDate!.toIsoString(),
    if (project.startDate != null)
      'startDate': project.startDate!.toIsoString(),
    // goalId intentionally omitted for self-contained portability
    'isArchived': project.isArchived,
    'customFields': _deepCopyMap(project.customFields),
    'createdAt': EthiopiaClock.toUtcIsoString(project.createdAt),
    'updatedAt': EthiopiaClock.toUtcIsoString(project.updatedAt),
  };
  return map;
}

Map<String, dynamic> _blockToPackageJson(ProjectTrackingBlockEntity block) {
  return <String, dynamic>{
    'id': block.id,
    'projectId': block.projectId,
    'blockType': block.blockType.wireValue,
    'title': block.title.trim(),
    'sortOrder': block.sortOrder,
    if (block.unitLabel != null && block.unitLabel!.trim().isNotEmpty)
      'unitLabel': block.unitLabel!.trim(),
    if (block.targetValue != null) 'targetValue': block.targetValue,
    if (block.dailyTargetValue != null)
      'dailyTargetValue': block.dailyTargetValue,
    'config': _deepCopyMap(block.config),
    'isArchived': block.isArchived,
    'createdAt': EthiopiaClock.toUtcIsoString(block.createdAt),
    'updatedAt': EthiopiaClock.toUtcIsoString(block.updatedAt),
  };
}

Map<String, dynamic> _recordToPackageJson(ProjectTrackingRecordEntity record) {
  return <String, dynamic>{
    'id': record.id,
    'projectId': record.projectId,
    'blockId': record.blockId,
    if (record.parentRecordId != null && record.parentRecordId!.trim().isNotEmpty)
      'parentRecordId': record.parentRecordId!.trim(),
    'recordType': record.recordType.wireValue,
    if (record.title != null && record.title!.trim().isNotEmpty)
      'title': record.title!.trim(),
    'sortOrder': record.sortOrder,
    if (record.targetValue != null) 'targetValue': record.targetValue,
    if (record.deltaValue != null) 'deltaValue': record.deltaValue,
    if (record.durationMinutes != null)
      'durationMinutes': record.durationMinutes,
    'isCompleted': record.isCompleted,
    if (record.completedAt != null)
      'completedAt': EthiopiaClock.toUtcIsoString(record.completedAt!),
    if (record.recordedDate != null)
      'recordedDate': record.recordedDate!.toIsoString(),
    if (record.scheduledDate != null)
      'scheduledDate': record.scheduledDate!.toIsoString(),
    // linkedTaskId intentionally omitted for self-contained portability
    'metadata': _deepCopyMap(record.metadata),
    'createdAt': EthiopiaClock.toUtcIsoString(record.createdAt),
    'updatedAt': EthiopiaClock.toUtcIsoString(record.updatedAt),
  };
}

Map<String, dynamic> _deepCopyMap(Map<String, dynamic> input) {
  if (input.isEmpty) return <String, dynamic>{};
  final encoded = jsonEncode(input);
  final decoded = jsonDecode(encoded);
  if (decoded is Map) {
    return decoded.map((k, v) => MapEntry(k.toString(), v));
  }
  return <String, dynamic>{};
}

class ProjectPackageCodec {
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
  static const Set<String> _validScheduleRules = {
    'manual',
    'threshold_percent',
    'exact_duration',
  };

  static int _idSequence = 0;
  static final Random _random = Random();

  static String _defaultGenerateId(String prefix) {
    _idSequence = (_idSequence + 1) % 1000000;
    final nowMicros = EthiopiaClock.nowUtc().microsecondsSinceEpoch;
    final rand = _random.nextInt(100000);
    return '$prefix-$nowMicros-$_idSequence-$rand';
  }

  /// Builds a clean `.daywellproject` filename from a project title.
  static String buildFilename(String projectTitle) {
    final slug = projectTitle
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final truncated = slug.length > 48 ? slug.substring(0, 48) : slug;
    final base = truncated.isEmpty ? 'daywell-project' : truncated;
    return '$base${SharedProjectPackageSpec.fileExtension}';
  }

  /// Orders blocks so non-rollup base blocks precede rollup counters.
  static List<ProjectTrackingBlockEntity> sortBlocksTopologically(
    List<ProjectTrackingBlockEntity> blocks,
  ) {
    final base = <ProjectTrackingBlockEntity>[];
    final rollups = <ProjectTrackingBlockEntity>[];
    for (final blk in blocks) {
      if (blk.blockType == ProjectBlockType.counter &&
          CounterBlockConfig.fromMap(blk.config).rollupSourceBlockId != null) {
        rollups.add(blk);
      } else {
        base.add(blk);
      }
    }
    int cmp(ProjectTrackingBlockEntity a, ProjectTrackingBlockEntity b) {
      final orderCmp = a.sortOrder.compareTo(b.sortOrder);
      if (orderCmp != 0) return orderCmp;
      final createdCmp = a.createdAt.compareTo(b.createdAt);
      if (createdCmp != 0) return createdCmp;
      return a.id.compareTo(b.id);
    }

    base.sort(cmp);
    rollups.sort(cmp);
    return [...base, ...rollups];
  }

  static int _recordPhaseRank(ProjectTrackingRecordEntity rec) {
    switch (rec.recordType) {
      case ProjectRecordType.group:
        return 0;
      case ProjectRecordType.groupedItem:
      case ProjectRecordType.checklistItem:
      case ProjectRecordType.scheduleItem:
        return 1;
      case ProjectRecordType.progressLog:
        return rec.isCorrection ? 3 : 2;
    }
  }

  /// Orders records topologically so parents precede children and target
  /// progress logs precede compensating corrections.
  static List<ProjectTrackingRecordEntity> sortRecordsTopologically(
    List<ProjectTrackingRecordEntity> records,
  ) {
    int baseCmp(
      ProjectTrackingRecordEntity a,
      ProjectTrackingRecordEntity b,
    ) {
      final rankCmp = _recordPhaseRank(a).compareTo(_recordPhaseRank(b));
      if (rankCmp != 0) return rankCmp;
      final orderCmp = a.sortOrder.compareTo(b.sortOrder);
      if (orderCmp != 0) return orderCmp;
      final createdCmp = a.createdAt.compareTo(b.createdAt);
      if (createdCmp != 0) return createdCmp;
      return a.id.compareTo(b.id);
    }

    final nonCorrections = records
        .where(
          (r) =>
              !(r.recordType == ProjectRecordType.progressLog && r.isCorrection),
        )
        .toList()
      ..sort(baseCmp);
    final corrections = records
        .where(
          (r) =>
              r.recordType == ProjectRecordType.progressLog && r.isCorrection,
        )
        .toList()
      ..sort(baseCmp);

    final byId = {for (final r in records) r.id: r};
    final depthCache = <String, int>{};

    int computeDepth(
      ProjectTrackingRecordEntity rec,
      Set<String> visiting,
    ) {
      final cached = depthCache[rec.id];
      if (cached != null) return cached;
      if (visiting.contains(rec.id)) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Cycle detected in compensating progress correction chain involving "${rec.id}".',
        );
      }
      final targetId = rec.compensatesRecordId?.trim();
      if (targetId == null || targetId.isEmpty) return 0;
      final target = byId[targetId];
      if (target == null) return 0;
      visiting.add(rec.id);
      final d = (target.recordType == ProjectRecordType.progressLog &&
              target.isCorrection)
          ? 1 + computeDepth(target, visiting)
          : 1;
      visiting.remove(rec.id);
      depthCache[rec.id] = d;
      return d;
    }

    corrections.sort((a, b) {
      final depthA = computeDepth(a, <String>{});
      final depthB = computeDepth(b, <String>{});
      if (depthA != depthB) return depthA.compareTo(depthB);
      return baseCmp(a, b);
    });

    return [...nonCorrections, ...corrections];
  }

  /// Builds and validates a `.daywellproject` package object for a single project.
  static DaywellProjectPackage buildPackage({
    required ProjectEntity project,
    required List<ProjectTrackingBlockEntity> blocks,
    required List<ProjectTrackingRecordEntity> records,
    DateTime? exportedAt,
    String sourcePlatform = 'android',
  }) {
    _validateProject(project);
    if (blocks.length > SharedProjectRules.maxBlocksPerProject) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Project exceeds maximum tracking blocks (${SharedProjectRules.maxBlocksPerProject}).',
      );
    }
    for (final blk in blocks) {
      if (blk.projectId != project.id) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Cannot export block "${blk.id}": projectId "${blk.projectId}" does not match "${project.id}".',
        );
      }
    }
    for (final rec in records) {
      if (rec.projectId != project.id) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Cannot export record "${rec.id}": projectId "${rec.projectId}" does not match "${project.id}".',
        );
      }
    }

    final cleanProject = ProjectEntity(
      id: project.id,
      title: project.title.trim(),
      description: project.description?.trim().isEmpty == true
          ? null
          : project.description?.trim(),
      status: project.status,
      targetDate: project.targetDate,
      // goalId cleared for self-contained export
      isArchived: project.isArchived,
      startDate: project.startDate,
      customFields: _deepCopyMap(project.customFields),
      createdAt: project.createdAt,
      updatedAt: project.updatedAt,
    );

    final orderedBlocks = sortBlocksTopologically(blocks)
        .map(
          (b) => ProjectTrackingBlockEntity(
            id: b.id,
            projectId: b.projectId,
            blockType: b.blockType,
            title: b.title.trim(),
            sortOrder: b.sortOrder,
            unitLabel: b.unitLabel?.trim().isEmpty == true
                ? null
                : b.unitLabel?.trim(),
            targetValue: b.targetValue,
            dailyTargetValue: b.dailyTargetValue,
            config: _deepCopyMap(b.config),
            isArchived: b.isArchived,
            createdAt: b.createdAt,
            updatedAt: b.updatedAt,
          ),
        )
        .toList(growable: false);

    final orderedRecords = sortRecordsTopologically(records)
        .map(
          (r) => ProjectTrackingRecordEntity(
            id: r.id,
            projectId: r.projectId,
            blockId: r.blockId,
            parentRecordId: r.parentRecordId?.trim().isEmpty == true
                ? null
                : r.parentRecordId?.trim(),
            recordType: r.recordType,
            title: r.title?.trim().isEmpty == true ? null : r.title?.trim(),
            sortOrder: r.sortOrder,
            targetValue: r.targetValue,
            deltaValue: r.deltaValue,
            durationMinutes: r.durationMinutes,
            isCompleted: r.isCompleted,
            completedAt: r.completedAt,
            recordedDate: r.recordedDate,
            scheduledDate: r.scheduledDate,
            // linkedTaskId cleared for self-contained export
            metadata: _deepCopyMap(r.metadata),
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
          ),
        )
        .toList(growable: false);

    return DaywellProjectPackage(
      formatId: SharedProjectPackageSpec.formatId,
      formatVersion: SharedProjectPackageSpec.currentFormatVersion,
      exportedAt: (exportedAt ?? EthiopiaClock.nowUtc()).toUtc(),
      sourcePlatform: sourcePlatform,
      project: cleanProject,
      trackingBlocks: orderedBlocks,
      trackingRecords: orderedRecords,
    );
  }

  /// Serializes a single project, all tracking blocks, and all records to pretty JSON.
  static String serialize({
    required ProjectEntity project,
    required List<ProjectTrackingBlockEntity> blocks,
    required List<ProjectTrackingRecordEntity> records,
    DateTime? exportedAt,
    String sourcePlatform = 'android',
  }) {
    final pkg = buildPackage(
      project: project,
      blocks: blocks,
      records: records,
      exportedAt: exportedAt,
      sourcePlatform: sourcePlatform,
    );
    return const JsonEncoder.withIndent('  ').convert(pkg.toJson());
  }

  /// Parses and strictly validates a `.daywellproject` JSON payload fail-closed.
  static DaywellProjectPackage parseAndValidate(String rawJson) {
    if (rawJson.trim().isEmpty) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.malformedJson,
        'Project package input is empty. Choose a .daywellproject file or paste valid JSON.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException catch (e) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.malformedJson,
        'Malformed JSON in project package: ${e.message}.',
      );
    } catch (e) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.malformedJson,
        'Malformed JSON in project package: $e.',
      );
    }

    if (decoded is! Map) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.invalidFormat,
        'Project package root must be a JSON object.',
      );
    }
    final root = decoded.map((k, v) => MapEntry(k.toString(), v));

    final formatId = root['formatId'];
    if (formatId != SharedProjectPackageSpec.formatId) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.invalidFormat,
        'Invalid project package formatId "${formatId ?? ''}". Expected "${SharedProjectPackageSpec.formatId}".',
      );
    }

    final rawVersion = root['formatVersion'];
    if (rawVersion is! int) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.invalidFormat,
        'Project package formatVersion must be an integer.',
      );
    }
    if (rawVersion < SharedProjectPackageSpec.minSupportedFormatVersion ||
        rawVersion > SharedProjectPackageSpec.currentFormatVersion) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.unsupportedVersion,
        'Unsupported .daywellproject formatVersion $rawVersion. This version of Daywell supports version ${SharedProjectPackageSpec.currentFormatVersion}.',
      );
    }

    final exportedAt = _requireIsoTimestamp(root['exportedAt'], 'exportedAt');
    final sourcePlatform =
        _optionalNonEmptyString(root['sourcePlatform'], 'sourcePlatform') ??
            'unknown';

    final rawProjectObj = root['project'];
    if (rawProjectObj is! Map) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Project package must contain a "project" object.',
      );
    }
    final rawProj = rawProjectObj.map((k, v) => MapEntry(k.toString(), v));

    final nowUtc = EthiopiaClock.nowUtc();
    final projId = _requireNonEmptyString(rawProj['id'], 'project.id');
    final projTitle = _requireNonEmptyString(rawProj['title'], 'project.title');
    final projStatusRaw = rawProj['status'];
    if (projStatusRaw is! String ||
        !SharedProjectRules.statuses.contains(projStatusRaw)) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Package field "project.status" must be one of: ${SharedProjectRules.statuses.join(', ')}.',
      );
    }

    final rawCustomFields = rawProj['customFields'];
    if (rawCustomFields != null && rawCustomFields is! Map) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Package field "project.customFields" must be a JSON object.',
      );
    }
    final customFields = rawCustomFields is Map
        ? rawCustomFields.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};

    final projCreatedAt =
        _optionalIsoTimestamp(rawProj['createdAt'], 'project.createdAt') ??
            nowUtc;
    final projUpdatedAt =
        _optionalIsoTimestamp(rawProj['updatedAt'], 'project.updatedAt') ??
            projCreatedAt;

    final project = ProjectEntity(
      id: projId,
      title: projTitle,
      description: _optionalNonEmptyString(
        rawProj['description'],
        'project.description',
      ),
      status: projStatusRaw,
      startDate: _optionalCanonicalDate(
        rawProj['startDate'],
        'project.startDate',
      ),
      targetDate: _optionalCanonicalDate(
        rawProj['targetDate'],
        'project.targetDate',
      ),
      // goalId cleared on import
      isArchived: _parseBool(
        rawProj['isArchived'],
        'project.isArchived',
        defaultValue: false,
      ),
      customFields: customFields,
      createdAt: projCreatedAt,
      updatedAt: projUpdatedAt,
    );

    _validateProject(project);

    final rawBlocksList = root['trackingBlocks'];
    if (rawBlocksList is! List) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Project package must contain a "trackingBlocks" array.',
      );
    }
    if (rawBlocksList.length > SharedProjectRules.maxBlocksPerProject) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Project package exceeds maximum tracking blocks (${SharedProjectRules.maxBlocksPerProject}).',
      );
    }

    final parsedBlocks = <ProjectTrackingBlockEntity>[];
    final blockIdsSeen = <String>{};

    for (int i = 0; i < rawBlocksList.length; i += 1) {
      final rawItem = rawBlocksList[i];
      final prefix = 'trackingBlocks[$i]';
      if (rawItem is! Map) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Package entry "$prefix" must be a JSON object.',
        );
      }
      final rawBlk = rawItem.map((k, v) => MapEntry(k.toString(), v));
      final blkId = _requireNonEmptyString(rawBlk['id'], '$prefix.id');
      if (!blockIdsSeen.add(blkId)) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Duplicate tracking block id "$blkId" in package.',
        );
      }
      final blkProjId = _optionalNonEmptyString(
        rawBlk['projectId'],
        '$prefix.projectId',
      );
      if (blkProjId != project.id) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Block "$blkId" projectId "${rawBlk['projectId'] ?? ''}" does not match package project "${project.id}".',
        );
      }
      final rawType = rawBlk['blockType'];
      final blockType =
          rawType is String ? ProjectBlockType.tryFromWire(rawType) : null;
      if (blockType == null) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Block "$blkId" has unsupported blockType "${rawType ?? ''}".',
        );
      }
      final blkTitle = _requireNonEmptyString(rawBlk['title'], '$prefix.title');
      final rawCfg = rawBlk['config'];
      if (rawCfg != null && rawCfg is! Map) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Block "$blkId" config must be an object.',
        );
      }
      final cfgMap = rawCfg is Map
          ? rawCfg.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};

      final blkCreatedAt =
          _optionalIsoTimestamp(rawBlk['createdAt'], '$prefix.createdAt') ??
              projCreatedAt;
      final blkUpdatedAt =
          _optionalIsoTimestamp(rawBlk['updatedAt'], '$prefix.updatedAt') ??
              blkCreatedAt;

      parsedBlocks.add(
        ProjectTrackingBlockEntity(
          id: blkId,
          projectId: project.id,
          blockType: blockType,
          title: blkTitle,
          sortOrder: _parseNonNegativeInt(
            rawBlk['sortOrder'],
            '$prefix.sortOrder',
            defaultValue: i,
          ),
          unitLabel: _optionalNonEmptyString(
            rawBlk['unitLabel'],
            '$prefix.unitLabel',
          ),
          targetValue: _optionalFiniteDouble(
            rawBlk['targetValue'],
            '$prefix.targetValue',
          ),
          dailyTargetValue: _optionalFiniteDouble(
            rawBlk['dailyTargetValue'],
            '$prefix.dailyTargetValue',
          ),
          config: cfgMap,
          isArchived: _parseBool(
            rawBlk['isArchived'],
            '$prefix.isArchived',
            defaultValue: false,
          ),
          createdAt: blkCreatedAt,
          updatedAt: blkUpdatedAt,
        ),
      );
    }

    final rawPrimary = project.customFields['primaryBlockId'];
    if (rawPrimary is String &&
        rawPrimary.trim().isNotEmpty &&
        !blockIdsSeen.contains(rawPrimary.trim())) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Project customFields.primaryBlockId "${rawPrimary.trim()}" references a missing tracking block.',
      );
    }

    final orderedBlocks = sortBlocksTopologically(parsedBlocks);
    final validatedBlocks = <ProjectTrackingBlockEntity>[];
    for (final blk in orderedBlocks) {
      _validateBlock(
        blk,
        expectedProjectId: project.id,
        projectBlocks: validatedBlocks,
        isNew: true,
      );
      validatedBlocks.add(blk);
    }
    final blockById = {for (final b in validatedBlocks) b.id: b};

    final rawRecordsList = root['trackingRecords'];
    if (rawRecordsList is! List) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Project package must contain a "trackingRecords" array.',
      );
    }

    final parsedRecords = <ProjectTrackingRecordEntity>[];
    final recordIdsSeen = <String>{};

    for (int i = 0; i < rawRecordsList.length; i += 1) {
      final rawItem = rawRecordsList[i];
      final prefix = 'trackingRecords[$i]';
      if (rawItem is! Map) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Package entry "$prefix" must be a JSON object.',
        );
      }
      final rawRec = rawItem.map((k, v) => MapEntry(k.toString(), v));
      final recId = _requireNonEmptyString(rawRec['id'], '$prefix.id');
      if (!recordIdsSeen.add(recId)) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Duplicate tracking record id "$recId" in package.',
        );
      }
      final recProjId = _optionalNonEmptyString(
        rawRec['projectId'],
        '$prefix.projectId',
      );
      if (recProjId != project.id) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Record "$recId" projectId "${rawRec['projectId'] ?? ''}" does not match package project "${project.id}".',
        );
      }
      final recBlockId = _optionalNonEmptyString(
        rawRec['blockId'],
        '$prefix.blockId',
      );
      if (recBlockId == null || !blockById.containsKey(recBlockId)) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Record "$recId" references missing blockId "${rawRec['blockId'] ?? ''}".',
        );
      }
      final rawRecType = rawRec['recordType'];
      final recordType = rawRecType is String
          ? ProjectRecordType.tryFromWire(rawRecType)
          : null;
      if (recordType == null) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Record "$recId" has unsupported recordType "${rawRecType ?? ''}".',
        );
      }
      final rawMeta = rawRec['metadata'];
      if (rawMeta != null && rawMeta is! Map) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Record "$recId" metadata must be an object.',
        );
      }
      final metaMap = rawMeta is Map
          ? rawMeta.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};

      final recCreatedAt =
          _optionalIsoTimestamp(rawRec['createdAt'], '$prefix.createdAt') ??
              projCreatedAt;
      final recUpdatedAt =
          _optionalIsoTimestamp(rawRec['updatedAt'], '$prefix.updatedAt') ??
              recCreatedAt;

      parsedRecords.add(
        ProjectTrackingRecordEntity(
          id: recId,
          projectId: project.id,
          blockId: recBlockId,
          parentRecordId: _optionalNonEmptyString(
            rawRec['parentRecordId'],
            '$prefix.parentRecordId',
          ),
          recordType: recordType,
          title: _optionalNonEmptyString(rawRec['title'], '$prefix.title'),
          sortOrder: _parseNonNegativeInt(
            rawRec['sortOrder'],
            '$prefix.sortOrder',
            defaultValue: i,
          ),
          targetValue: _optionalFiniteDouble(
            rawRec['targetValue'],
            '$prefix.targetValue',
          ),
          deltaValue: _optionalFiniteDouble(
            rawRec['deltaValue'],
            '$prefix.deltaValue',
          ),
          durationMinutes: _optionalNonNegativeInt(
            rawRec['durationMinutes'],
            '$prefix.durationMinutes',
          ),
          isCompleted: _parseBool(
            rawRec['isCompleted'],
            '$prefix.isCompleted',
            defaultValue: false,
          ),
          completedAt: _optionalIsoTimestamp(
            rawRec['completedAt'],
            '$prefix.completedAt',
          ),
          recordedDate: _optionalCanonicalDate(
            rawRec['recordedDate'],
            '$prefix.recordedDate',
          ),
          scheduledDate: _optionalCanonicalDate(
            rawRec['scheduledDate'],
            '$prefix.scheduledDate',
          ),
          // linkedTaskId cleared on import
          metadata: metaMap,
          createdAt: recCreatedAt,
          updatedAt: recUpdatedAt,
        ),
      );
    }

    final orderedRecords = sortRecordsTopologically(parsedRecords);
    final validatedByBlock = <String, List<ProjectTrackingRecordEntity>>{};
    for (final rec in orderedRecords) {
      final blk = blockById[rec.blockId]!;
      final blockRecords = validatedByBlock.putIfAbsent(blk.id, () => []);
      _validateRecord(
        rec,
        block: blk,
        existingBlockRecords: blockRecords,
        isNew: true,
      );
      blockRecords.add(rec);
    }

    return DaywellProjectPackage(
      formatId: SharedProjectPackageSpec.formatId,
      formatVersion: rawVersion,
      exportedAt: exportedAt,
      sourcePlatform: sourcePlatform,
      project: project,
      trackingBlocks: validatedBlocks,
      trackingRecords: orderedRecords,
    );
  }

  /// Validates [rawJson] and prepares a collision-free import bundle with
  /// fresh local IDs and cleared `goalId` / `linkedTaskId` references.
  static PreparedProjectPackageImport prepareForImport(
    String rawJson, {
    Iterable<String> existingProjectIds = const [],
    Iterable<String> existingBlockIds = const [],
    Iterable<String> existingRecordIds = const [],
    String Function(String prefix)? generateId,
  }) {
    final pkg = parseAndValidate(rawJson);
    final idGen = generateId ?? _defaultGenerateId;
    final usedProjects = Set<String>.from(existingProjectIds);
    final usedBlocks = Set<String>.from(existingBlockIds);
    final usedRecords = Set<String>.from(existingRecordIds);

    final newProjectId = _allocateUniqueId('proj', usedProjects, idGen);
    final blockIdMap = <String, String>{};
    for (final blk in pkg.trackingBlocks) {
      blockIdMap[blk.id] = _allocateUniqueId('blk', usedBlocks, idGen);
    }
    final recordIdMap = <String, String>{};
    for (final rec in pkg.trackingRecords) {
      recordIdMap[rec.id] = _allocateUniqueId('rec', usedRecords, idGen);
    }

    final nextCustomFields = _deepCopyMap(pkg.project.customFields);
    final rawPrimary = nextCustomFields['primaryBlockId'];
    if (rawPrimary is String && rawPrimary.trim().isNotEmpty) {
      final remappedPrimary = blockIdMap[rawPrimary.trim()];
      if (remappedPrimary == null) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Project primaryBlockId "$rawPrimary" could not be remapped.',
        );
      }
      nextCustomFields['primaryBlockId'] = remappedPrimary;
    }

    final importedProject = ProjectEntity(
      id: newProjectId,
      title: pkg.project.title,
      description: pkg.project.description,
      status: pkg.project.status,
      targetDate: pkg.project.targetDate,
      // goalId cleared
      isArchived: pkg.project.isArchived,
      startDate: pkg.project.startDate,
      customFields: nextCustomFields,
      createdAt: pkg.project.createdAt,
      updatedAt: pkg.project.updatedAt,
    );

    final importedBlocks = <ProjectTrackingBlockEntity>[];
    for (final blk in pkg.trackingBlocks) {
      final nextCfg = _deepCopyMap(blk.config);
      if (blk.blockType == ProjectBlockType.counter) {
        final rawSource = nextCfg['rollupSourceBlockId'];
        if (rawSource is String && rawSource.trim().isNotEmpty) {
          final remappedSource = blockIdMap[rawSource.trim()];
          if (remappedSource == null) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Block "${blk.id}" rollupSourceBlockId "$rawSource" could not be remapped.',
            );
          }
          nextCfg['rollupSourceBlockId'] = remappedSource;
        }
      }
      importedBlocks.add(
        ProjectTrackingBlockEntity(
          id: blockIdMap[blk.id]!,
          projectId: newProjectId,
          blockType: blk.blockType,
          title: blk.title,
          sortOrder: blk.sortOrder,
          unitLabel: blk.unitLabel,
          targetValue: blk.targetValue,
          dailyTargetValue: blk.dailyTargetValue,
          config: nextCfg,
          isArchived: blk.isArchived,
          createdAt: blk.createdAt,
          updatedAt: blk.updatedAt,
        ),
      );
    }

    final importedRecords = <ProjectTrackingRecordEntity>[];
    for (final rec in pkg.trackingRecords) {
      final nextMeta = _deepCopyMap(rec.metadata);
      final rawTarget = nextMeta['compensatesRecordId'];
      if (rawTarget is String && rawTarget.trim().isNotEmpty) {
        final remappedTarget = recordIdMap[rawTarget.trim()];
        if (remappedTarget == null) {
          throw ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Correction "${rec.id}" compensatesRecordId "$rawTarget" could not be remapped.',
          );
        }
        nextMeta['compensatesRecordId'] = remappedTarget;
      }

      importedRecords.add(
        ProjectTrackingRecordEntity(
          id: recordIdMap[rec.id]!,
          projectId: newProjectId,
          blockId: blockIdMap[rec.blockId]!,
          parentRecordId: rec.parentRecordId != null
              ? recordIdMap[rec.parentRecordId!]
              : null,
          recordType: rec.recordType,
          title: rec.title,
          sortOrder: rec.sortOrder,
          targetValue: rec.targetValue,
          deltaValue: rec.deltaValue,
          durationMinutes: rec.durationMinutes,
          isCompleted: rec.isCompleted,
          completedAt: rec.completedAt,
          recordedDate: rec.recordedDate,
          scheduledDate: rec.scheduledDate,
          // linkedTaskId cleared
          metadata: nextMeta,
          createdAt: rec.createdAt,
          updatedAt: rec.updatedAt,
        ),
      );
    }

    // Final post-remap invariant pass
    _validateProject(importedProject);
    final validatedBlocks = <ProjectTrackingBlockEntity>[];
    for (final blk in importedBlocks) {
      _validateBlock(
        blk,
        expectedProjectId: newProjectId,
        projectBlocks: validatedBlocks,
        isNew: true,
      );
      validatedBlocks.add(blk);
    }
    final blockById = {for (final b in validatedBlocks) b.id: b};
    final recordsByBlock = <String, List<ProjectTrackingRecordEntity>>{};
    for (final rec in importedRecords) {
      final blk = blockById[rec.blockId]!;
      final existing = recordsByBlock.putIfAbsent(blk.id, () => []);
      _validateRecord(
        rec,
        block: blk,
        existingBlockRecords: existing,
        isNew: true,
      );
      existing.add(rec);
    }

    return PreparedProjectPackageImport(
      sourceFormatVersion: pkg.formatVersion,
      sourcePlatform: pkg.sourcePlatform,
      exportedAt: pkg.exportedAt,
      project: importedProject,
      trackingBlocks: validatedBlocks,
      trackingRecords: importedRecords,
    );
  }

  static String _allocateUniqueId(
    String prefix,
    Set<String> usedIds,
    String Function(String prefix) idGen,
  ) {
    for (int attempt = 0; attempt < 32; attempt += 1) {
      final candidate = idGen(prefix);
      if (usedIds.add(candidate)) return candidate;
    }
    int seq = usedIds.length + 1;
    while (true) {
      final candidate =
          '$prefix-${EthiopiaClock.nowUtc().microsecondsSinceEpoch}-$seq';
      if (usedIds.add(candidate)) return candidate;
      seq += 1;
    }
  }

  static String _requireNonEmptyString(Object? raw, String fieldLabel) {
    if (raw is! String || raw.trim().isEmpty) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Package field "$fieldLabel" is required and must be a non-empty string.',
      );
    }
    return raw.trim();
  }

  static String? _optionalNonEmptyString(Object? raw, String fieldLabel) {
    if (raw == null) return null;
    if (raw is! String) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Package field "$fieldLabel" must be a string when present.',
      );
    }
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static CalendarDate? _optionalCanonicalDate(Object? raw, String fieldLabel) {
    if (raw == null) return null;
    if (raw is! String) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Package field "$fieldLabel" must be a canonical YYYY-MM-DD string.',
      );
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final parsed = CalendarDate.tryParse(trimmed);
    if (parsed == null) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Package field "$fieldLabel" ("$trimmed") must be canonical YYYY-MM-DD.',
      );
    }
    return parsed;
  }

  static DateTime _requireIsoTimestamp(Object? raw, String fieldLabel) {
    if (raw is! String || raw.trim().isEmpty) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Package field "$fieldLabel" must be a valid ISO-8601 timestamp string.',
      );
    }
    final parsed = EthiopiaClock.tryParseInstantUtc(raw.trim());
    if (parsed == null) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Package field "$fieldLabel" ("${raw.trim()}") is not a valid ISO-8601 timestamp.',
      );
    }
    return parsed;
  }

  static DateTime? _optionalIsoTimestamp(Object? raw, String fieldLabel) {
    if (raw == null) return null;
    return _requireIsoTimestamp(raw, fieldLabel);
  }

  static int _parseNonNegativeInt(
    Object? raw,
    String fieldLabel, {
    required int defaultValue,
  }) {
    if (raw == null) return defaultValue;
    if (raw is! int || raw < 0) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Package field "$fieldLabel" must be a non-negative integer.',
      );
    }
    return raw;
  }

  static int? _optionalNonNegativeInt(Object? raw, String fieldLabel) {
    if (raw == null) return null;
    if (raw is! int || raw < 0) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Package field "$fieldLabel" must be a non-negative integer.',
      );
    }
    return raw;
  }

  static double? _optionalFiniteDouble(Object? raw, String fieldLabel) {
    if (raw == null) return null;
    if (raw is! num || !raw.toDouble().isFinite) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Package field "$fieldLabel" must be a finite number.',
      );
    }
    return raw.toDouble();
  }

  static bool _parseBool(
    Object? raw,
    String fieldLabel, {
    required bool defaultValue,
  }) {
    if (raw == null) return defaultValue;
    if (raw is! bool) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Package field "$fieldLabel" must be a boolean.',
      );
    }
    return raw;
  }

  static void _validateProject(ProjectEntity project) {
    if (project.id.trim().isEmpty) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Project id must not be empty.',
      );
    }
    final title = project.title.trim();
    if (title.isEmpty || title.length > 200) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Project title must be between 1 and 200 characters.',
      );
    }
    if (!SharedProjectRules.statuses.contains(project.status)) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Invalid project status "${project.status}". Allowed: ${SharedProjectRules.statuses.join(', ')}.',
      );
    }
    if (project.startDate != null &&
        project.targetDate != null &&
        project.targetDate!.isBefore(project.startDate!)) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Project targetDate cannot be earlier than startDate.',
      );
    }
    _validateCustomFieldsMap(project.customFields);
  }

  static void _validateCustomFieldsMap(Map<String, dynamic> map) {
    if (map.isEmpty) return;
    for (final key in map.keys) {
      if (!_allowedCustomFieldTopKeys.contains(key)) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Unsupported customFields key "$key". Allowed keys: definitions, values, primaryBlockId.',
        );
      }
    }

    if (map.containsKey('primaryBlockId') && map['primaryBlockId'] != null) {
      final rawPrimary = map['primaryBlockId'];
      if (rawPrimary is! String || rawPrimary.trim().isEmpty) {
        throw const ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'customFields.primaryBlockId must be a non-empty string.',
        );
      }
    }

    final defsById = <String, Map<String, dynamic>>{};
    if (map.containsKey('definitions') && map['definitions'] != null) {
      final rawDefs = map['definitions'];
      if (rawDefs is! List) {
        throw const ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'customFields.definitions must be an array.',
        );
      }
      if (rawDefs.length > SharedProjectRules.maxCustomFieldDefinitions) {
        throw const ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'customFields.definitions exceeds maximum allowed count (${SharedProjectRules.maxCustomFieldDefinitions}).',
        );
      }
      for (int i = 0; i < rawDefs.length; i += 1) {
        final item = rawDefs[i];
        if (item is! Map) {
          throw ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'customFields.definitions[$i] must be an object.',
          );
        }
        final def = item.map((k, v) => MapEntry(k.toString(), v));
        for (final k in def.keys) {
          if (!_allowedDefinitionKeys.contains(k)) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Unsupported custom field definition key "$k" in definitions[$i].',
            );
          }
        }
        final id = def['id'];
        if (id is! String || !_fieldIdPattern.hasMatch(id)) {
          throw ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Invalid custom field id "${id ?? ''}" at definitions[$i].',
          );
        }
        if (defsById.containsKey(id)) {
          throw ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Duplicate custom field definition id "$id".',
          );
        }
        final label = def['label'];
        if (label is! String || label.trim().isEmpty || label.length > 120) {
          throw ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Invalid custom field label for "$id".',
          );
        }
        final fieldType = def['type'];
        if (fieldType is! String ||
            !SharedProjectRules.customFieldTypes.contains(fieldType)) {
          throw ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Unsupported custom field type "$fieldType" for "$id".',
          );
        }
        if (def['required'] != null && def['required'] is! bool) {
          throw ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'customFields.definitions[$i].required must be a boolean.',
          );
        }
        final rawOptions = def['options'];
        if (fieldType == 'select') {
          if (rawOptions is! List || rawOptions.isEmpty) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Select custom field "$id" must define non-empty options.',
            );
          }
          if (rawOptions.length >
              SharedProjectRules.maxCustomFieldSelectOptions) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Select custom field "$id" exceeds max options (${SharedProjectRules.maxCustomFieldSelectOptions}).',
            );
          }
          final seenOptions = <String>{};
          for (final opt in rawOptions) {
            if (opt is! String || opt.trim().isEmpty) {
              throw ProjectPackageException(
                ProjectPackageErrorKind.validationFailed,
                'Select custom field "$id" contains invalid option "$opt".',
              );
            }
            if (!seenOptions.add(opt)) {
              throw ProjectPackageException(
                ProjectPackageErrorKind.validationFailed,
                'Select custom field "$id" contains duplicate option "$opt".',
              );
            }
          }
        } else if (rawOptions != null &&
            (rawOptions is! List || rawOptions.isNotEmpty)) {
          throw ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Non-select custom field "$id" cannot define options.',
          );
        }
        defsById[id] = def;
      }
    }

    var valuesMap = const <String, dynamic>{};
    if (map.containsKey('values') && map['values'] != null) {
      final rawVals = map['values'];
      if (rawVals is! Map) {
        throw const ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'customFields.values must be an object.',
        );
      }
      valuesMap = rawVals.map((k, v) => MapEntry(k.toString(), v));
    }

    for (final entry in valuesMap.entries) {
      final key = entry.key;
      final val = entry.value;
      final def = defsById[key];
      if (def == null) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Unknown custom field value key "$key" without a matching definition.',
        );
      }
      if (val is Map || val is List) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Nested objects or arrays are not allowed in custom field value "$key".',
        );
      }
      final isRequired = def['required'] == true;
      if (val == null) {
        if (isRequired) {
          throw ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Required custom field "$key" cannot be null.',
          );
        }
        continue;
      }
      final fieldType = def['type'] as String;
      switch (fieldType) {
        case 'text':
          if (val is! String) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Custom field "$key" expects a text string.',
            );
          }
          if (val.length > SharedProjectRules.maxCustomFieldTextLength) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Custom field "$key" exceeds max length (${SharedProjectRules.maxCustomFieldTextLength}).',
            );
          }
          if (isRequired && val.trim().isEmpty) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Required custom field "$key" cannot be blank.',
            );
          }
        case 'number':
          if (val is! num || !val.toDouble().isFinite) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Custom field "$key" expects a finite number.',
            );
          }
        case 'date':
          if (val is! String || CalendarDate.tryParse(val) == null) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Custom field "$key" expects canonical YYYY-MM-DD date.',
            );
          }
        case 'boolean':
          if (val is! bool) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Custom field "$key" expects a boolean.',
            );
          }
        case 'select':
          final opts = (def['options'] as List).cast<String>();
          if (val is! String || !opts.contains(val)) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Custom field "$key" value "$val" is not in allowed options.',
            );
          }
      }
    }

    for (final entry in defsById.entries) {
      if (entry.value['required'] == true &&
          !valuesMap.containsKey(entry.key)) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Missing value for required custom field "${entry.key}".',
        );
      }
    }
  }

  static void _validateBlock(
    ProjectTrackingBlockEntity block, {
    required String expectedProjectId,
    required List<ProjectTrackingBlockEntity> projectBlocks,
    required bool isNew,
  }) {
    if (block.id.trim().isEmpty) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Block id must not be empty.',
      );
    }
    if (block.projectId != expectedProjectId) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Block "${block.id}" projectId "${block.projectId}" does not match project "$expectedProjectId".',
      );
    }
    if (isNew && projectBlocks.any((b) => b.id == block.id)) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Duplicate tracking block id "${block.id}".',
      );
    }
    if (isNew &&
        projectBlocks.length >= SharedProjectRules.maxBlocksPerProject) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Project exceeds maximum tracking blocks (${SharedProjectRules.maxBlocksPerProject}).',
      );
    }
    final title = block.title.trim();
    if (title.isEmpty || title.length > 200) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Block title must be between 1 and 200 characters.',
      );
    }
    if (block.sortOrder < 0) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Block sortOrder must be non-negative.',
      );
    }
    if (block.unitLabel != null && block.unitLabel!.trim().length > 64) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Block unitLabel cannot exceed 64 characters.',
      );
    }
    if (block.targetValue != null &&
        (!block.targetValue!.isFinite || block.targetValue! < 0)) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Block targetValue must be finite and non-negative.',
      );
    }
    if (block.dailyTargetValue != null &&
        (!block.dailyTargetValue!.isFinite || block.dailyTargetValue! < 0)) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Block dailyTargetValue must be finite and non-negative.',
      );
    }

    switch (block.blockType) {
      case ProjectBlockType.counter:
        final cfg = CounterBlockConfig.fromMap(block.config);
        final sourceId = cfg.rollupSourceBlockId;
        if (sourceId != null) {
          if (sourceId == block.id) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Counter block "${block.id}" cannot roll up from itself.',
            );
          }
          if (cfg.allowDirectLogging) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Rollup counter block "${block.id}" cannot allow direct logging alongside rollupSourceBlockId "$sourceId".',
            );
          }
          ProjectTrackingBlockEntity? sourceBlock;
          for (final candidate in projectBlocks) {
            if (candidate.id == sourceId) {
              sourceBlock = candidate;
              break;
            }
          }
          if (sourceBlock == null) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Counter block "${block.id}" references missing rollupSourceBlockId "$sourceId" in project "$expectedProjectId".',
            );
          }
          if (sourceBlock.blockType == ProjectBlockType.counter &&
              CounterBlockConfig.fromMap(sourceBlock.config)
                      .rollupSourceBlockId !=
                  null) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Counter block "${block.id}" cannot chain rollups through another rollup counter "$sourceId".',
            );
          }
        }
      case ProjectBlockType.groupedList:
        GroupedListBlockConfig.fromMap(block.config);
      case ProjectBlockType.checklist:
        ChecklistBlockConfig.fromMap(block.config);
      case ProjectBlockType.schedule:
        final rawRule = block.config['completionRule'];
        if (rawRule != null &&
            (rawRule is! String || !_validScheduleRules.contains(rawRule))) {
          throw ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Unsupported schedule completionRule "$rawRule".',
          );
        }
        final cfg = ScheduleBlockConfig.fromMap(block.config);
        if (!cfg.autoCompleteThresholdRatio.isFinite ||
            cfg.autoCompleteThresholdRatio <= 0 ||
            cfg.autoCompleteThresholdRatio > 1.0) {
          throw const ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Schedule autoCompleteThresholdRatio must be within (0.0, 1.0].',
          );
        }
    }
  }

  static void _validateRecord(
    ProjectTrackingRecordEntity record, {
    required ProjectTrackingBlockEntity block,
    required List<ProjectTrackingRecordEntity> existingBlockRecords,
    required bool isNew,
  }) {
    if (record.id.trim().isEmpty) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Record id must not be empty.',
      );
    }
    if (record.projectId != block.projectId) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Record "${record.id}" projectId "${record.projectId}" does not match block project "${block.projectId}".',
      );
    }
    if (record.blockId != block.id) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Record "${record.id}" blockId "${record.blockId}" does not match block "${block.id}".',
      );
    }
    if (isNew && existingBlockRecords.any((r) => r.id == record.id)) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Duplicate tracking record id "${record.id}".',
      );
    }
    if (record.sortOrder < 0) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Record sortOrder must be non-negative.',
      );
    }
    if (record.targetValue != null &&
        (!record.targetValue!.isFinite || record.targetValue! < 0)) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Record targetValue must be finite and non-negative.',
      );
    }
    if (record.durationMinutes != null && record.durationMinutes! < 0) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Record durationMinutes must be non-negative.',
      );
    }

    final byId = {for (final item in existingBlockRecords) item.id: item};
    ProjectTrackingRecordEntity? parent;
    final parentId = record.parentRecordId;
    if (parentId != null) {
      if (parentId == record.id) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Record "${record.id}" cannot set itself as parentRecordId.',
        );
      }
      parent = byId[parentId];
      if (parent == null) {
        throw ProjectPackageException(
          ProjectPackageErrorKind.validationFailed,
          'Record "${record.id}" references missing or cross-block parentRecordId "$parentId".',
        );
      }
      final visited = <String>{record.id};
      ProjectTrackingRecordEntity? cursor = parent;
      int depth = 1;
      while (cursor != null) {
        if (!visited.add(cursor.id)) {
          throw ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Cycle detected in parentRecordId hierarchy involving "${record.id}".',
          );
        }
        depth += 1;
        if (depth > SharedProjectRules.maxHierarchyDepth) {
          throw const ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Record hierarchy exceeds maximum depth (${SharedProjectRules.maxHierarchyDepth}).',
          );
        }
        cursor = cursor.parentRecordId != null
            ? byId[cursor.parentRecordId!]
            : null;
      }
    }

    final trimmedTitle = record.title?.trim();
    if (trimmedTitle != null &&
        trimmedTitle.length > SharedProjectRules.maxTrackingRecordTitleLength) {
      throw const ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Record title cannot exceed ${SharedProjectRules.maxTrackingRecordTitleLength} characters.',
      );
    }

    switch (record.recordType) {
      case ProjectRecordType.group:
        if (block.blockType != ProjectBlockType.groupedList) {
          throw const ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Record type "group" is only valid in grouped_list blocks.',
          );
        }
        if (record.parentRecordId != null) {
          throw const ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Group records must be top-level (parentRecordId must be null).',
          );
        }
        if (trimmedTitle == null || trimmedTitle.isEmpty) {
          throw const ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Group record must have a non-empty title.',
          );
        }
      case ProjectRecordType.groupedItem:
        if (block.blockType != ProjectBlockType.groupedList) {
          throw const ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Record type "grouped_item" is only valid in grouped_list blocks.',
          );
        }
        if (trimmedTitle == null || trimmedTitle.isEmpty) {
          throw const ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Grouped item record must have a non-empty title.',
          );
        }
        if (parent != null && parent.recordType != ProjectRecordType.group) {
          throw ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Grouped item "${record.id}" parentRecordId must reference a "group" record.',
          );
        }
      case ProjectRecordType.checklistItem:
        if (block.blockType != ProjectBlockType.checklist) {
          throw const ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Record type "checklist_item" is only valid in checklist blocks.',
          );
        }
        if (record.parentRecordId != null) {
          throw const ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Checklist items cannot have a parentRecordId.',
          );
        }
        if (trimmedTitle == null || trimmedTitle.isEmpty) {
          throw const ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Checklist item record must have a non-empty title.',
          );
        }
      case ProjectRecordType.scheduleItem:
        if (block.blockType != ProjectBlockType.schedule) {
          throw const ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Record type "schedule_item" is only valid in schedule blocks.',
          );
        }
        if (record.parentRecordId != null) {
          throw const ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Schedule items cannot have a parentRecordId.',
          );
        }
        if (trimmedTitle == null || trimmedTitle.isEmpty) {
          throw const ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Schedule item record must have a non-empty title.',
          );
        }
      case ProjectRecordType.progressLog:
        if (block.blockType == ProjectBlockType.checklist) {
          throw const ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Progress logs cannot be attached to checklist blocks.',
          );
        }
        if (record.recordedDate == null) {
          throw ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Progress log "${record.id}" requires recordedDate (YYYY-MM-DD).',
          );
        }
        if (block.blockType == ProjectBlockType.counter) {
          final cfg = CounterBlockConfig.fromMap(block.config);
          if (cfg.rollupSourceBlockId != null || !cfg.allowDirectLogging) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Cannot log directly on rollup counter block "${block.id}" (source: "${cfg.rollupSourceBlockId}"). Log against the source block items instead.',
            );
          }
          if (record.parentRecordId != null) {
            throw const ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Direct counter progress logs must have parentRecordId == null.',
            );
          }
        } else if (block.blockType == ProjectBlockType.groupedList) {
          if (parent == null ||
              parent.recordType != ProjectRecordType.groupedItem) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Progress log "${record.id}" in a grouped_list block must reference a parent grouped_item record.',
            );
          }
        } else if (block.blockType == ProjectBlockType.schedule) {
          if (parent == null ||
              parent.recordType != ProjectRecordType.scheduleItem) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Progress log "${record.id}" in a schedule block must reference a parent schedule_item record.',
            );
          }
        }

        final delta = record.deltaValue;
        if (delta == null || !delta.isFinite || delta == 0) {
          throw ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Progress log "${record.id}" must have a finite non-zero deltaValue.',
          );
        }
        if (record.isCorrection) {
          final targetId = record.compensatesRecordId?.trim() ?? '';
          final reason = record.correctionReason?.trim() ?? '';
          if (targetId.isEmpty) {
            throw const ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Compensating progress correction requires metadata.compensatesRecordId.',
            );
          }
          if (reason.isEmpty) {
            throw const ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Compensating progress correction requires metadata.correctionReason.',
            );
          }
          if (targetId == record.id) {
            throw const ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Compensating progress correction cannot reference itself.',
            );
          }
          final target = byId[targetId];
          if (target == null ||
              target.recordType != ProjectRecordType.progressLog) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Compensating correction "${record.id}" references missing or non-log record "$targetId".',
            );
          }
          if (target.parentRecordId != record.parentRecordId) {
            throw ProjectPackageException(
              ProjectPackageErrorKind.validationFailed,
              'Compensating correction "${record.id}" must match parentRecordId of target log "$targetId".',
            );
          }
        } else if (delta <= 0) {
          throw ProjectPackageException(
            ProjectPackageErrorKind.validationFailed,
            'Progress log "${record.id}" deltaValue must be > 0 (use explicit compensating correction for negative adjustments).',
          );
        }
    }
  }
}
