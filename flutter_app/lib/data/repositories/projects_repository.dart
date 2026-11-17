import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/date/shared_date.dart';
import '../../domain/projects/progress_engine.dart';
import '../../domain/projects/project_contracts.dart';
import '../../domain/projects/project_models.dart';
import '../../domain/projects/project_package_codec.dart';
import '../../domain/projects/project_validation_service.dart';
import '../../domain/tasks/task_models.dart';
import '../database/app_database.dart';

/// Offline-first Drift SQLite implementation of [IProjectsRepository].
class DriftProjectsRepository implements IProjectsRepository {
  final AppDatabase _db;

  DriftProjectsRepository(this._db);

  ProjectEntity _mapProject(Project row) {
    return ProjectEntity(
      id: row.id,
      title: row.title,
      description: row.description,
      status: row.status,
      targetDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        row.targetDate,
      ),
      goalId: row.goalId,
      isArchived: row.isArchived,
      startDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        row.startDate,
      ),
      customFields: _decodeJsonMap(row.customFieldsJson),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt ?? row.createdAt,
    );
  }

  ProjectTrackingBlockEntity _mapBlock(ProjectTrackingBlock row) {
    return ProjectTrackingBlockEntity(
      id: row.id,
      projectId: row.projectId,
      blockType: ProjectBlockType.fromWire(row.blockType),
      title: row.title,
      sortOrder: row.sortOrder,
      unitLabel: row.unitLabel,
      targetValue: row.targetValue,
      dailyTargetValue: row.dailyTargetValue,
      config: _decodeJsonMap(row.configJson),
      isArchived: row.isArchived,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  ProjectTrackingRecordEntity _mapRecord(ProjectTrackingRecord row) {
    return ProjectTrackingRecordEntity(
      id: row.id,
      projectId: row.projectId,
      blockId: row.blockId,
      parentRecordId: row.parentRecordId,
      recordType: ProjectRecordType.fromWire(row.recordType),
      title: row.title,
      sortOrder: row.sortOrder,
      targetValue: row.targetValue,
      deltaValue: row.deltaValue,
      durationMinutes: row.durationMinutes,
      isCompleted: row.isCompleted,
      completedAt: row.completedAt,
      recordedDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        row.recordedDate,
      ),
      scheduledDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(
        row.scheduledDate,
      ),
      linkedTaskId: row.linkedTaskId,
      metadata: _decodeJsonMap(row.metadataJson),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  static Map<String, dynamic> _decodeJsonMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
      return const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  Future<void> _ensureGoalExists(String? goalId) async {
    final trimmed = goalId?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    final goalRow = await (_db.select(_db.goals)
          ..where((tbl) => tbl.id.equals(trimmed)))
        .getSingleOrNull();
    if (goalRow == null) {
      throw ProjectValidationException(
        'Cannot link project to missing goal "$trimmed".',
      );
    }
  }

  Future<void> _ensureTaskExists(String? linkedTaskId) async {
    final trimmed = linkedTaskId?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    final taskRow = await (_db.select(_db.tasks)
          ..where((tbl) => tbl.id.equals(trimmed)))
        .getSingleOrNull();
    if (taskRow == null) {
      throw ProjectValidationException(
        'Cannot link tracking record to missing task "$trimmed".',
      );
    }
  }

  TaskEntity _mapTask(Task r) {
    return TaskEntity(
      id: r.id,
      title: r.title,
      description: r.description,
      status: r.status,
      priority: r.priority,
      dueDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(r.dueDate),
      scheduledDate:
          SharedDateFormatter.tryParseFlexibleToCalendarDate(r.scheduledDate),
      estimatedDurationMinutes: r.estimatedDurationMinutes,
      projectId: r.projectId,
      milestoneId: r.milestoneId,
      isPinned: r.isPinned,
      isMyDay: r.isMyDay,
      recurrenceRule: r.recurrenceRule,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    );
  }

  MilestoneEntity _mapMilestone(Milestone r) {
    return MilestoneEntity(
      id: r.id,
      projectId: r.projectId,
      title: r.title,
      dueDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(r.dueDate),
      isCompleted: r.isCompleted,
      createdAt: r.createdAt,
    );
  }

  @override
  Future<List<ProjectEntity>> getProjects({
    String? status,
    bool includeArchived = true,
  }) async {
    final query = _db.select(_db.projects);
    if (status != null) {
      query.where((tbl) => tbl.status.equals(status));
    }
    if (!includeArchived) {
      query.where((tbl) => tbl.isArchived.equals(false));
    }
    query.orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);
    final rows = await query.get();
    return rows.map(_mapProject).toList();
  }

  @override
  Future<ProjectEntity?> getProjectById(String id) async {
    final row = await (_db.select(_db.projects)
          ..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _mapProject(row);
  }

  @override
  Future<ProjectEntity> createProject(ProjectEntity project) async {
    ProjectValidationService.validateProject(project);
    final normalized = project.copyWith(
      title: project.title.trim(),
      goalId: (project.goalId?.trim().isEmpty ?? true)
          ? null
          : project.goalId!.trim(),
      clearGoalId: project.goalId?.trim().isEmpty ?? false,
    );

    await _db.transaction(() async {
      final existing = await getProjectById(normalized.id);
      if (existing != null) {
        throw ProjectValidationException(
          'Duplicate project id "${normalized.id}".',
        );
      }
      await _ensureGoalExists(normalized.goalId);
      await _db.into(_db.projects).insert(
            ProjectsCompanion.insert(
              id: normalized.id,
              goalId: Value(normalized.goalId),
              title: normalized.title,
              description: Value(normalized.description?.trim()),
              status: Value(normalized.status),
              targetDate: Value(normalized.targetDate?.toIsoString()),
              isArchived: Value(normalized.isArchived),
              startDate: Value(normalized.startDate?.toIsoString()),
              customFieldsJson: Value(jsonEncode(normalized.customFields)),
              createdAt: normalized.createdAt,
              updatedAt: Value(normalized.updatedAt),
            ),
          );
    });
    return normalized;
  }

  @override
  Future<ProjectEntity> updateProject(ProjectEntity project) async {
    ProjectValidationService.validateProject(project);
    final now = EthiopiaClock.nowUtc();
    final updated = project.copyWith(
      title: project.title.trim(),
      goalId: (project.goalId?.trim().isEmpty ?? true)
          ? null
          : project.goalId!.trim(),
      clearGoalId: project.goalId?.trim().isEmpty ?? false,
      updatedAt: now,
    );

    await _db.transaction(() async {
      final existing = await getProjectById(updated.id);
      if (existing == null) {
        throw ProjectValidationException(
          'Cannot update missing project "${updated.id}".',
        );
      }
      await _ensureGoalExists(updated.goalId);
      await (_db.update(_db.projects)
            ..where((tbl) => tbl.id.equals(updated.id)))
          .write(
        ProjectsCompanion(
          goalId: Value(updated.goalId),
          title: Value(updated.title),
          description: Value(updated.description?.trim()),
          status: Value(updated.status),
          targetDate: Value(updated.targetDate?.toIsoString()),
          isArchived: Value(updated.isArchived),
          startDate: Value(updated.startDate?.toIsoString()),
          customFieldsJson: Value(jsonEncode(updated.customFields)),
          updatedAt: Value(updated.updatedAt),
        ),
      );
    });
    return updated;
  }

  @override
  Future<ProjectEntity> setProjectArchived(
    String projectId,
    bool isArchived,
  ) async {
    return _db.transaction(() async {
      final existing = await getProjectById(projectId);
      if (existing == null) {
        throw ProjectValidationException(
          'Cannot archive missing project "$projectId".',
        );
      }
      final updated = existing.copyWith(
        isArchived: isArchived,
        updatedAt: EthiopiaClock.nowUtc(),
      );
      await (_db.update(_db.projects)..where((tbl) => tbl.id.equals(projectId)))
          .write(
        ProjectsCompanion(
          isArchived: Value(isArchived),
          updatedAt: Value(updated.updatedAt),
        ),
      );
      return updated;
    });
  }

  @override
  Future<void> deleteProject(String projectId) async {
    await _db.transaction(() async {
      await (_db.update(_db.tasks)
            ..where((tbl) => tbl.projectId.equals(projectId)))
          .write(const TasksCompanion(projectId: Value(null)));

      await _deleteRecordsForProjectBottomUp(projectId);

      await (_db.delete(_db.projectTrackingBlocks)
            ..where((tbl) => tbl.projectId.equals(projectId)))
          .go();
      await (_db.delete(_db.milestones)
            ..where((tbl) => tbl.projectId.equals(projectId)))
          .go();
      await (_db.delete(_db.projects)..where((tbl) => tbl.id.equals(projectId)))
          .go();
    });
  }

  Future<void> _deleteRecordsForProjectBottomUp(String projectId) async {
    await (_db.delete(_db.projectTrackingRecords)
          ..where((tbl) =>
              tbl.projectId.equals(projectId) &
              tbl.recordType.equals(ProjectRecordType.progressLog.wireValue)))
        .go();
    await _db.customStatement(
      'UPDATE project_tracking_records SET parent_record_id = NULL '
      'WHERE project_id = ?;',
      [projectId],
    );
    await (_db.delete(_db.projectTrackingRecords)
          ..where((tbl) => tbl.projectId.equals(projectId)))
        .go();
  }

  @override
  Future<List<ProjectTrackingBlockEntity>> getBlocksForProject(
    String projectId, {
    bool includeArchived = true,
  }) async {
    final query = _db.select(_db.projectTrackingBlocks)
      ..where((tbl) => tbl.projectId.equals(projectId));
    if (!includeArchived) {
      query.where((tbl) => tbl.isArchived.equals(false));
    }
    query.orderBy([
      (tbl) => OrderingTerm.asc(tbl.sortOrder),
      (tbl) => OrderingTerm.asc(tbl.createdAt),
    ]);
    final rows = await query.get();
    return rows.map(_mapBlock).toList();
  }

  @override
  Future<ProjectTrackingBlockEntity> createBlock(
    ProjectTrackingBlockEntity block,
  ) async {
    return _db.transaction(() async {
      final project = await getProjectById(block.projectId);
      if (project == null) {
        throw ProjectValidationException(
          'Cannot create block "${block.id}": missing project "${block.projectId}".',
        );
      }
      final siblingBlocks = await getBlocksForProject(block.projectId);
      ProjectValidationService.validateBlock(
        block,
        expectedProjectId: project.id,
        projectBlocks: siblingBlocks,
        isNew: true,
      );
      final normalized = block.copyWith(title: block.title.trim());
      await _db.into(_db.projectTrackingBlocks).insert(
            ProjectTrackingBlocksCompanion.insert(
              id: normalized.id,
              projectId: normalized.projectId,
              blockType: normalized.blockType.wireValue,
              title: normalized.title,
              sortOrder: Value(normalized.sortOrder),
              unitLabel: Value(normalized.unitLabel),
              targetValue: Value(normalized.targetValue),
              dailyTargetValue: Value(normalized.dailyTargetValue),
              configJson: Value(jsonEncode(normalized.config)),
              isArchived: Value(normalized.isArchived),
              createdAt: normalized.createdAt,
              updatedAt: normalized.updatedAt,
            ),
          );
      return normalized;
    });
  }

  @override
  Future<ProjectTrackingBlockEntity> updateBlock(
    ProjectTrackingBlockEntity block,
  ) async {
    return _db.transaction(() async {
      final existingRow = await (_db.select(_db.projectTrackingBlocks)
            ..where((tbl) => tbl.id.equals(block.id)))
          .getSingleOrNull();
      if (existingRow == null) {
        throw ProjectValidationException(
          'Cannot update missing tracking block "${block.id}".',
        );
      }
      final existing = _mapBlock(existingRow);
      if (existing.projectId != block.projectId ||
          existing.blockType != block.blockType) {
        throw ProjectValidationException(
          'Cannot change projectId or blockType on existing block "${block.id}".',
        );
      }
      final siblingBlocks = await getBlocksForProject(block.projectId);
      final updated = block.copyWith(
        title: block.title.trim(),
        updatedAt: EthiopiaClock.nowUtc(),
      );
      ProjectValidationService.validateBlock(
        updated,
        expectedProjectId: existing.projectId,
        projectBlocks: siblingBlocks,
        isNew: false,
      );
      await (_db.update(_db.projectTrackingBlocks)
            ..where((tbl) => tbl.id.equals(updated.id)))
          .write(
        ProjectTrackingBlocksCompanion(
          title: Value(updated.title),
          sortOrder: Value(updated.sortOrder),
          unitLabel: Value(updated.unitLabel),
          targetValue: Value(updated.targetValue),
          dailyTargetValue: Value(updated.dailyTargetValue),
          configJson: Value(jsonEncode(updated.config)),
          isArchived: Value(updated.isArchived),
          updatedAt: Value(updated.updatedAt),
        ),
      );
      return updated;
    });
  }

  @override
  Future<ProjectTrackingBlockEntity> setBlockArchived(
    String blockId,
    bool isArchived,
  ) async {
    return _db.transaction(() async {
      final row = await (_db.select(_db.projectTrackingBlocks)
            ..where((tbl) => tbl.id.equals(blockId)))
          .getSingleOrNull();
      if (row == null) {
        throw ProjectValidationException(
          'Cannot archive missing block "$blockId".',
        );
      }
      final now = EthiopiaClock.nowUtc();
      await (_db.update(_db.projectTrackingBlocks)
            ..where((tbl) => tbl.id.equals(blockId)))
          .write(
        ProjectTrackingBlocksCompanion(
          isArchived: Value(isArchived),
          updatedAt: Value(now),
        ),
      );
      return _mapBlock(row).copyWith(isArchived: isArchived, updatedAt: now);
    });
  }

  @override
  Future<void> deleteBlock(String blockId) async {
    await _db.transaction(() async {
      await (_db.delete(_db.projectTrackingRecords)
            ..where((tbl) =>
                tbl.blockId.equals(blockId) &
                tbl.recordType.equals(ProjectRecordType.progressLog.wireValue)))
          .go();
      await _db.customStatement(
        'UPDATE project_tracking_records SET parent_record_id = NULL '
        'WHERE block_id = ?;',
        [blockId],
      );
      await (_db.delete(_db.projectTrackingRecords)
            ..where((tbl) => tbl.blockId.equals(blockId)))
          .go();
      await (_db.delete(_db.projectTrackingBlocks)
            ..where((tbl) => tbl.id.equals(blockId)))
          .go();
    });
  }

  @override
  Future<List<ProjectTrackingRecordEntity>> getRecordsForProject(
    String projectId, {
    String? blockId,
  }) async {
    final query = _db.select(_db.projectTrackingRecords)
      ..where((tbl) => tbl.projectId.equals(projectId));
    if (blockId != null) {
      query.where((tbl) => tbl.blockId.equals(blockId));
    }
    query.orderBy([
      (tbl) => OrderingTerm.asc(tbl.sortOrder),
      (tbl) => OrderingTerm.asc(tbl.createdAt),
    ]);
    final rows = await query.get();
    return rows.map(_mapRecord).toList();
  }

  @override
  Future<ProjectTrackingRecordEntity> createRecord(
    ProjectTrackingRecordEntity record,
  ) async {
    return _db.transaction(() async {
      final blockRow = await (_db.select(_db.projectTrackingBlocks)
            ..where((tbl) => tbl.id.equals(record.blockId)))
          .getSingleOrNull();
      if (blockRow == null) {
        throw ProjectValidationException(
          'Cannot create record "${record.id}": missing block "${record.blockId}".',
        );
      }
      final block = _mapBlock(blockRow);
      final normalized = record.copyWith(
        title: record.title?.trim(),
        linkedTaskId: (record.linkedTaskId?.trim().isEmpty ?? true)
            ? null
            : record.linkedTaskId!.trim(),
        clearLinkedTaskId: record.linkedTaskId?.trim().isEmpty ?? false,
      );
      final existingRecords = await getRecordsForProject(
        block.projectId,
        blockId: block.id,
      );
      ProjectValidationService.validateRecord(
        normalized,
        block: block,
        existingBlockRecords: existingRecords,
        isNew: true,
      );
      await _ensureTaskExists(normalized.linkedTaskId);

      await _db.into(_db.projectTrackingRecords).insert(
            ProjectTrackingRecordsCompanion.insert(
              id: normalized.id,
              projectId: normalized.projectId,
              blockId: normalized.blockId,
              parentRecordId: Value(normalized.parentRecordId),
              recordType: normalized.recordType.wireValue,
              title: Value(normalized.title),
              sortOrder: Value(normalized.sortOrder),
              targetValue: Value(normalized.targetValue),
              deltaValue: Value(normalized.deltaValue),
              durationMinutes: Value(normalized.durationMinutes),
              isCompleted: Value(normalized.isCompleted),
              completedAt: Value(normalized.completedAt),
              recordedDate: Value(normalized.recordedDate?.toIsoString()),
              scheduledDate: Value(normalized.scheduledDate?.toIsoString()),
              linkedTaskId: Value(normalized.linkedTaskId),
              metadataJson: Value(jsonEncode(normalized.metadata)),
              createdAt: normalized.createdAt,
              updatedAt: normalized.updatedAt,
            ),
          );
      return normalized;
    });
  }

  @override
  Future<ProjectTrackingRecordEntity> updateRecord(
    ProjectTrackingRecordEntity record,
  ) async {
    return _db.transaction(() async {
      final existingRow = await (_db.select(_db.projectTrackingRecords)
            ..where((tbl) => tbl.id.equals(record.id)))
          .getSingleOrNull();
      if (existingRow == null) {
        throw ProjectValidationException(
          'Cannot update missing tracking record "${record.id}".',
        );
      }
      final existing = _mapRecord(existingRow);
      ProjectValidationService.assertAppendOnlyLogProtection(
        existing: existing,
        isDelete: false,
      );
      if (existing.projectId != record.projectId ||
          existing.blockId != record.blockId ||
          existing.recordType != record.recordType) {
        throw ProjectValidationException(
          'Cannot change projectId, blockId, or recordType on tracking record "${record.id}".',
        );
      }

      final blockRow = await (_db.select(_db.projectTrackingBlocks)
            ..where((tbl) => tbl.id.equals(record.blockId)))
          .getSingleOrNull();
      if (blockRow == null) {
        throw ProjectValidationException(
          'Missing parent block "${record.blockId}" for record "${record.id}".',
        );
      }
      final block = _mapBlock(blockRow);
      final existingRecords = await getRecordsForProject(
        block.projectId,
        blockId: block.id,
      );
      final updated = record.copyWith(
        title: record.title?.trim(),
        linkedTaskId: (record.linkedTaskId?.trim().isEmpty ?? true)
            ? null
            : record.linkedTaskId!.trim(),
        clearLinkedTaskId: record.linkedTaskId?.trim().isEmpty ?? false,
        updatedAt: EthiopiaClock.nowUtc(),
      );
      ProjectValidationService.validateRecord(
        updated,
        block: block,
        existingBlockRecords: existingRecords,
        isNew: false,
      );
      await _ensureTaskExists(updated.linkedTaskId);

      await (_db.update(_db.projectTrackingRecords)
            ..where((tbl) => tbl.id.equals(updated.id)))
          .write(
        ProjectTrackingRecordsCompanion(
          parentRecordId: Value(updated.parentRecordId),
          title: Value(updated.title),
          sortOrder: Value(updated.sortOrder),
          targetValue: Value(updated.targetValue),
          deltaValue: Value(updated.deltaValue),
          durationMinutes: Value(updated.durationMinutes),
          isCompleted: Value(updated.isCompleted),
          completedAt: Value(updated.completedAt),
          recordedDate: Value(updated.recordedDate?.toIsoString()),
          scheduledDate: Value(updated.scheduledDate?.toIsoString()),
          linkedTaskId: Value(updated.linkedTaskId),
          metadataJson: Value(jsonEncode(updated.metadata)),
          updatedAt: Value(updated.updatedAt),
        ),
      );
      return updated;
    });
  }

  @override
  Future<ProjectTrackingRecordEntity> appendProgressLog(
    ProjectTrackingRecordEntity logRecord,
  ) {
    if (logRecord.recordType != ProjectRecordType.progressLog) {
      throw const ProjectValidationException(
        'appendProgressLog requires recordType == progress_log.',
      );
    }
    return createRecord(logRecord);
  }

  @override
  Future<ProjectTrackingRecordEntity> appendProgressCorrection({
    required String targetLogId,
    required double correctionDelta,
    required CalendarDate recordedDate,
    required String reason,
    String? correctionId,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw const ProjectValidationException(
        'Compensating progress correction requires a non-empty reason.',
      );
    }
    return _db.transaction(() async {
      final targetRow = await (_db.select(_db.projectTrackingRecords)
            ..where((tbl) => tbl.id.equals(targetLogId)))
          .getSingleOrNull();
      if (targetRow == null) {
        throw ProjectValidationException(
          'Cannot compensate missing progress log "$targetLogId".',
        );
      }
      final target = _mapRecord(targetRow);
      if (target.recordType != ProjectRecordType.progressLog) {
        throw ProjectValidationException(
          'Record "$targetLogId" is not a progress_log and cannot be compensated.',
        );
      }
      final now = EthiopiaClock.nowUtc();
      final id = (correctionId != null && correctionId.trim().isNotEmpty)
          ? correctionId.trim()
          : 'corr-${now.microsecondsSinceEpoch}';
      final correction = ProjectTrackingRecordEntity(
        id: id,
        projectId: target.projectId,
        blockId: target.blockId,
        parentRecordId: target.parentRecordId,
        recordType: ProjectRecordType.progressLog,
        deltaValue: correctionDelta,
        recordedDate: recordedDate,
        metadata: <String, dynamic>{
          'isCorrection': true,
          'compensatesRecordId': targetLogId,
          'correctionReason': trimmedReason,
        },
        createdAt: now,
        updatedAt: now,
      );
      return createRecord(correction);
    });
  }

  @override
  Future<void> deleteRecord(String recordId) async {
    await _db.transaction(() async {
      final row = await (_db.select(_db.projectTrackingRecords)
            ..where((tbl) => tbl.id.equals(recordId)))
          .getSingleOrNull();
      if (row == null) return;
      final existing = _mapRecord(row);
      ProjectValidationService.assertAppendOnlyLogProtection(
        existing: existing,
        isDelete: true,
      );
      final children = await (_db.select(_db.projectTrackingRecords)
            ..where((tbl) => tbl.parentRecordId.equals(recordId)))
          .get();
      if (children.isNotEmpty) {
        throw ProjectValidationException(
          'Cannot delete tracking record "$recordId" while ${children.length} child record(s) reference it.',
        );
      }
      await (_db.delete(_db.projectTrackingRecords)
            ..where((tbl) => tbl.id.equals(recordId)))
          .go();
    });
  }

  @override
  Future<ProjectProgressSummary> getProjectProgressSummary(
    String projectId, {
    CalendarDate? asOfDate,
  }) async {
    final project = await getProjectById(projectId);
    if (project == null) {
      throw ProjectValidationException(
        'Cannot compute summary for missing project "$projectId".',
      );
    }
    final blocks = await getBlocksForProject(projectId);
    final records = await getRecordsForProject(projectId);
    final taskRows = await (_db.select(_db.tasks)
          ..where((tbl) => tbl.projectId.equals(projectId)))
        .get();
    final milestoneRows = await (_db.select(_db.milestones)
          ..where((tbl) => tbl.projectId.equals(projectId)))
        .get();

    return ProgressEngine.calculateProjectProgressSummary(
      project: project,
      blocks: blocks,
      records: records,
      linkedTasks: taskRows.map(_mapTask).toList(),
      milestones: milestoneRows.map(_mapMilestone).toList(),
      asOfDate: asOfDate,
    );
  }

  @override
  Future<String> exportProjectPackageJson(String projectId) async {
    final project = await getProjectById(projectId);
    if (project == null) {
      throw ProjectPackageException(
        ProjectPackageErrorKind.validationFailed,
        'Cannot export missing project "$projectId".',
      );
    }
    final blocks = await getBlocksForProject(
      projectId,
      includeArchived: true,
    );
    final records = await getRecordsForProject(projectId);
    return ProjectPackageCodec.serialize(
      project: project,
      blocks: blocks,
      records: records,
      sourcePlatform: 'android',
    );
  }

  @override
  Future<PreparedProjectPackageImport> importProjectPackageJson(
    String rawJson,
  ) async {
    return _db.transaction(() async {
      final existingProjectRows = await _db.select(_db.projects).get();
      final existingBlockRows =
          await _db.select(_db.projectTrackingBlocks).get();
      final existingRecordRows =
          await _db.select(_db.projectTrackingRecords).get();

      final prepared = ProjectPackageCodec.prepareForImport(
        rawJson,
        existingProjectIds: existingProjectRows.map((r) => r.id),
        existingBlockIds: existingBlockRows.map((r) => r.id),
        existingRecordIds: existingRecordRows.map((r) => r.id),
      );

      final proj = prepared.project;
      await _db.into(_db.projects).insert(
            ProjectsCompanion.insert(
              id: proj.id,
              goalId: const Value(null),
              title: proj.title,
              description: Value(proj.description?.trim()),
              status: Value(proj.status),
              targetDate: Value(proj.targetDate?.toIsoString()),
              isArchived: Value(proj.isArchived),
              startDate: Value(proj.startDate?.toIsoString()),
              customFieldsJson: Value(jsonEncode(proj.customFields)),
              createdAt: proj.createdAt,
              updatedAt: Value(proj.updatedAt),
            ),
          );

      for (final block in prepared.trackingBlocks) {
        await _db.into(_db.projectTrackingBlocks).insert(
              ProjectTrackingBlocksCompanion.insert(
                id: block.id,
                projectId: block.projectId,
                blockType: block.blockType.wireValue,
                title: block.title,
                sortOrder: Value(block.sortOrder),
                unitLabel: Value(block.unitLabel),
                targetValue: Value(block.targetValue),
                dailyTargetValue: Value(block.dailyTargetValue),
                configJson: Value(jsonEncode(block.config)),
                isArchived: Value(block.isArchived),
                createdAt: block.createdAt,
                updatedAt: block.updatedAt,
              ),
            );
      }

      for (final record in prepared.trackingRecords) {
        await _db.into(_db.projectTrackingRecords).insert(
              ProjectTrackingRecordsCompanion.insert(
                id: record.id,
                projectId: record.projectId,
                blockId: record.blockId,
                parentRecordId: Value(record.parentRecordId),
                recordType: record.recordType.wireValue,
                title: Value(record.title),
                sortOrder: Value(record.sortOrder),
                targetValue: Value(record.targetValue),
                deltaValue: Value(record.deltaValue),
                durationMinutes: Value(record.durationMinutes),
                isCompleted: Value(record.isCompleted),
                completedAt: Value(record.completedAt),
                recordedDate: Value(record.recordedDate?.toIsoString()),
                scheduledDate: Value(record.scheduledDate?.toIsoString()),
                linkedTaskId: const Value(null),
                metadataJson: Value(jsonEncode(record.metadata)),
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
              ),
            );
      }

      return prepared;
    });
  }
}
