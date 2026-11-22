import 'package:flutter/foundation.dart';

import '../../core/date/shared_date.dart';
import '../../domain/projects/project_contracts.dart';
import '../../domain/projects/project_models.dart';
import '../../domain/projects/project_package_codec.dart';
import '../../domain/tasks/task_models.dart';
import 'projects_state.dart';

/// Module-scoped application controller for Daywell Projects, structured
/// tracking blocks, append-only progress logs, and progress summaries.
///
/// Sole owner of Stage 1 Projects controller state; delegates persistence
/// to [IProjectsRepository] and stays decoupled from Drift/SQLite and UI widgets.
class ProjectsController extends ChangeNotifier {
  final IProjectsRepository _repository;
  ProjectsModuleState _state;
  bool _isDisposed = false;

  ProjectsController({
    required IProjectsRepository repository,
    ProjectsModuleState? initialState,
  })  : _repository = repository,
        _state = initialState ?? const ProjectsModuleState();

  ProjectsModuleState get state => _state;

  // --- Hydration ---

  Future<void> loadAll({CalendarDate? asOfDate}) async {
    _state = _state.copyWith(isLoading: true, clearError: true);
    notifyListeners();
    try {
      final loadedProjects =
          await _repository.getProjects(includeArchived: true);
      final nextBlocks = <String, List<ProjectTrackingBlockEntity>>{};
      final nextRecords = <String, List<ProjectTrackingRecordEntity>>{};
      final nextSummaries = <String, ProjectProgressSummary>{};

      for (final project in loadedProjects) {
        final blocks = await _repository.getBlocksForProject(
          project.id,
          includeArchived: true,
        );
        final records = await _repository.getRecordsForProject(project.id);
        final summary = await _repository.getProjectProgressSummary(
          project.id,
          asOfDate: asOfDate,
        );
        nextBlocks[project.id] =
            List<ProjectTrackingBlockEntity>.unmodifiable(blocks);
        nextRecords[project.id] =
            List<ProjectTrackingRecordEntity>.unmodifiable(records);
        nextSummaries[project.id] = summary;
      }

      _state = _state.copyWith(
        projects: List<ProjectEntity>.unmodifiable(loadedProjects),
        blocksByProject:
            Map<String, List<ProjectTrackingBlockEntity>>.unmodifiable(
          nextBlocks,
        ),
        recordsByProject:
            Map<String, List<ProjectTrackingRecordEntity>>.unmodifiable(
          nextRecords,
        ),
        summariesByProject: Map<String, ProjectProgressSummary>.unmodifiable(
          nextSummaries,
        ),
        isLoading: false,
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
    notifyListeners();
  }

  Future<void> refreshProject(
    String projectId, {
    CalendarDate? asOfDate,
  }) async {
    try {
      final loadedProjects =
          await _repository.getProjects(includeArchived: true);
      final blocks = await _repository.getBlocksForProject(
        projectId,
        includeArchived: true,
      );
      final records = await _repository.getRecordsForProject(projectId);
      final summary = await _repository.getProjectProgressSummary(
        projectId,
        asOfDate: asOfDate,
      );

      final nextBlocks = Map<String, List<ProjectTrackingBlockEntity>>.from(
        _state.blocksByProject,
      )..[projectId] = List<ProjectTrackingBlockEntity>.unmodifiable(blocks);
      final nextRecords = Map<String, List<ProjectTrackingRecordEntity>>.from(
        _state.recordsByProject,
      )..[projectId] = List<ProjectTrackingRecordEntity>.unmodifiable(records);
      final nextSummaries =
          Map<String, ProjectProgressSummary>.from(_state.summariesByProject)
            ..[projectId] = summary;

      _state = _state.copyWith(
        projects: List<ProjectEntity>.unmodifiable(loadedProjects),
        blocksByProject:
            Map<String, List<ProjectTrackingBlockEntity>>.unmodifiable(
          nextBlocks,
        ),
        recordsByProject:
            Map<String, List<ProjectTrackingRecordEntity>>.unmodifiable(
          nextRecords,
        ),
        summariesByProject: Map<String, ProjectProgressSummary>.unmodifiable(
          nextSummaries,
        ),
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  // --- Selection & Filters ---

  void selectProject(String? projectId) {
    if (projectId == null) {
      _state = _state.copyWith(clearSelectedProject: true);
    } else {
      _state = _state.copyWith(selectedProjectId: projectId);
    }
    notifyListeners();
  }

  void setIncludeArchived(bool includeArchived) {
    _state = _state.copyWith(includeArchived: includeArchived);
    notifyListeners();
  }

  // --- Project Lifecycle ---

  Future<ProjectEntity?> createProject({
    String? id,
    required String title,
    String? description,
    String status = 'active',
    CalendarDate? startDate,
    CalendarDate? targetDate,
    String? goalId,
    bool isArchived = false,
    Map<String, dynamic>? customFields,
  }) async {
    final now = EthiopiaClock.nowUtc();
    final project = ProjectEntity(
      id: id ?? 'proj-${now.microsecondsSinceEpoch}',
      title: title.trim(),
      description: description?.trim(),
      status: status,
      startDate: startDate,
      targetDate: targetDate,
      goalId: goalId,
      isArchived: isArchived,
      customFields: customFields,
      createdAt: now,
      updatedAt: now,
    );
    try {
      final created = await _repository.createProject(project);
      await refreshProject(created.id);
      return created;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<ProjectEntity?> updateProject(ProjectEntity project) async {
    try {
      final updated = await _repository.updateProject(project);
      await refreshProject(updated.id);
      return updated;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<ProjectEntity?> setProjectArchived(
    String projectId,
    bool isArchived,
  ) async {
    try {
      final updated =
          await _repository.setProjectArchived(projectId, isArchived);
      await refreshProject(updated.id);
      return updated;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<bool> deleteProject(String projectId) async {
    try {
      await _repository.deleteProject(projectId);
      final loadedProjects =
          await _repository.getProjects(includeArchived: true);
      final nextBlocks = Map<String, List<ProjectTrackingBlockEntity>>.from(
        _state.blocksByProject,
      )..remove(projectId);
      final nextRecords = Map<String, List<ProjectTrackingRecordEntity>>.from(
        _state.recordsByProject,
      )..remove(projectId);
      final nextSummaries =
          Map<String, ProjectProgressSummary>.from(_state.summariesByProject)
            ..remove(projectId);

      _state = _state.copyWith(
        projects: List<ProjectEntity>.unmodifiable(loadedProjects),
        blocksByProject:
            Map<String, List<ProjectTrackingBlockEntity>>.unmodifiable(
          nextBlocks,
        ),
        recordsByProject:
            Map<String, List<ProjectTrackingRecordEntity>>.unmodifiable(
          nextRecords,
        ),
        summariesByProject: Map<String, ProjectProgressSummary>.unmodifiable(
          nextSummaries,
        ),
        clearSelectedProject: _state.selectedProjectId == projectId,
        clearError: true,
      );
      notifyListeners();
      return true;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return false;
    }
  }

  // --- Tracking Blocks ---

  Future<ProjectTrackingBlockEntity?> createBlock({
    String? id,
    required String projectId,
    required ProjectBlockType blockType,
    required String title,
    int sortOrder = 0,
    String? unitLabel,
    double? targetValue,
    double? dailyTargetValue,
    Map<String, dynamic>? config,
    bool isArchived = false,
  }) async {
    final now = EthiopiaClock.nowUtc();
    final block = ProjectTrackingBlockEntity(
      id: id ?? 'blk-${now.microsecondsSinceEpoch}',
      projectId: projectId,
      blockType: blockType,
      title: title.trim(),
      sortOrder: sortOrder,
      unitLabel: unitLabel,
      targetValue: targetValue,
      dailyTargetValue: dailyTargetValue,
      config: config,
      isArchived: isArchived,
      createdAt: now,
      updatedAt: now,
    );
    try {
      final created = await _repository.createBlock(block);
      await refreshProject(projectId);
      return created;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<ProjectTrackingBlockEntity?> updateBlock(
    ProjectTrackingBlockEntity block,
  ) async {
    try {
      final updated = await _repository.updateBlock(block);
      await refreshProject(updated.projectId);
      return updated;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<ProjectTrackingBlockEntity?> setBlockArchived(
    String blockId,
    bool isArchived,
  ) async {
    try {
      final updated = await _repository.setBlockArchived(blockId, isArchived);
      await refreshProject(updated.projectId);
      return updated;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<bool> deleteBlock(String projectId, String blockId) async {
    try {
      await _repository.deleteBlock(blockId);
      await refreshProject(projectId);
      return true;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return false;
    }
  }

  // --- Tracking Records & Append-Only Logs ---

  Future<ProjectTrackingRecordEntity?> createRecord({
    String? id,
    required String projectId,
    required String blockId,
    String? parentRecordId,
    required ProjectRecordType recordType,
    String? title,
    int sortOrder = 0,
    double? targetValue,
    double? deltaValue,
    int? durationMinutes,
    bool isCompleted = false,
    DateTime? completedAt,
    CalendarDate? recordedDate,
    CalendarDate? scheduledDate,
    String? linkedTaskId,
    Map<String, dynamic>? metadata,
  }) async {
    final now = EthiopiaClock.nowUtc();
    final record = ProjectTrackingRecordEntity(
      id: id ?? 'rec-${now.microsecondsSinceEpoch}',
      projectId: projectId,
      blockId: blockId,
      parentRecordId: parentRecordId,
      recordType: recordType,
      title: title,
      sortOrder: sortOrder,
      targetValue: targetValue,
      deltaValue: deltaValue,
      durationMinutes: durationMinutes,
      isCompleted: isCompleted,
      completedAt: completedAt,
      recordedDate: recordedDate,
      scheduledDate: scheduledDate,
      linkedTaskId: linkedTaskId,
      metadata: metadata,
      createdAt: now,
      updatedAt: now,
    );
    try {
      final created = await _repository.createRecord(record);
      await refreshProject(projectId);
      return created;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<ProjectTrackingRecordEntity?> updateRecord(
    ProjectTrackingRecordEntity record,
  ) async {
    try {
      final updated = await _repository.updateRecord(record);
      await refreshProject(updated.projectId);
      return updated;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<ProjectTrackingRecordEntity?> appendProgressLog({
    String? id,
    required String projectId,
    required String blockId,
    String? parentRecordId,
    required double deltaValue,
    required CalendarDate recordedDate,
    String? title,
    Map<String, dynamic>? metadata,
  }) async {
    final now = EthiopiaClock.nowUtc();
    final log = ProjectTrackingRecordEntity(
      id: id ?? 'log-${now.microsecondsSinceEpoch}',
      projectId: projectId,
      blockId: blockId,
      parentRecordId: parentRecordId,
      recordType: ProjectRecordType.progressLog,
      title: title,
      deltaValue: deltaValue,
      recordedDate: recordedDate,
      metadata: metadata,
      createdAt: now,
      updatedAt: now,
    );
    try {
      final created = await _repository.appendProgressLog(log);
      await refreshProject(projectId);
      return created;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<ProjectTrackingRecordEntity?> appendProgressCorrection({
    required String targetLogId,
    required double correctionDelta,
    required CalendarDate recordedDate,
    required String reason,
    String? correctionId,
  }) async {
    try {
      final created = await _repository.appendProgressCorrection(
        targetLogId: targetLogId,
        correctionDelta: correctionDelta,
        recordedDate: recordedDate,
        reason: reason,
        correctionId: correctionId,
      );
      await refreshProject(created.projectId);
      return created;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<bool> deleteRecord(String projectId, String recordId) async {
    try {
      await _repository.deleteRecord(recordId);
      await refreshProject(projectId);
      return true;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return false;
    }
  }

  Future<ProjectProgressSummary?> loadProjectSummary(
    String projectId, {
    CalendarDate? asOfDate,
  }) async {
    try {
      final summary = await _repository.getProjectProgressSummary(
        projectId,
        asOfDate: asOfDate,
      );
      final nextSummaries =
          Map<String, ProjectProgressSummary>.from(_state.summariesByProject)
            ..[projectId] = summary;
      _state = _state.copyWith(
        summariesByProject: Map<String, ProjectProgressSummary>.unmodifiable(
          nextSummaries,
        ),
        clearError: true,
      );
      notifyListeners();
      return summary;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  // --- Portable .daywellproject Package Export & Import ---

  Future<String?> exportProjectPackageJson(String projectId) async {
    try {
      final json = await _repository.exportProjectPackageJson(projectId);
      if (_state.errorMessage != null) {
        _state = _state.copyWith(clearError: true);
        notifyListeners();
      }
      return json;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<PreparedProjectPackageImport?> importProjectPackageJson(
    String rawJson,
  ) async {
    try {
      final imported = await _repository.importProjectPackageJson(rawJson);
      await refreshProject(imported.project.id);
      return imported;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  // --- Stage 1.3 Project Sections & Linked Task Organization ---

  ProjectTrackingBlockEntity? findProjectSectionsBlock(String projectId) {
    final blocks = _state
        .blocksForProject(projectId, includeArchived: false)
        .where((b) => b.blockType == ProjectBlockType.groupedList)
        .toList(growable: false);
    if (blocks.isEmpty) return null;
    for (final b in blocks) {
      if (b.config['kind'] == 'task_sections') return b;
    }
    for (final b in blocks) {
      if (b.title.trim().toLowerCase() == 'task sections') return b;
    }
    return blocks.first;
  }

  Future<ProjectTrackingBlockEntity?> ensureProjectSectionsBlock(
    String projectId,
  ) async {
    final cached = findProjectSectionsBlock(projectId);
    if (cached != null) return cached;

    final freshBlocks = (await _repository.getBlocksForProject(
      projectId,
      includeArchived: false,
    ))
        .where((b) => b.blockType == ProjectBlockType.groupedList)
        .toList(growable: false);
    for (final b in freshBlocks) {
      if (b.config['kind'] == 'task_sections') return b;
    }
    for (final b in freshBlocks) {
      if (b.title.trim().toLowerCase() == 'task sections') return b;
    }
    if (freshBlocks.isNotEmpty) return freshBlocks.first;

    return createBlock(
      projectId: projectId,
      blockType: ProjectBlockType.groupedList,
      title: 'Task Sections',
      config: const {
        'kind': 'task_sections',
        'groupLabel': 'Section',
        'itemLabel': 'Task',
        'showGroupTotals': false,
        'showDailyTotals': false,
      },
    );
  }

  Future<ProjectTrackingRecordEntity?> createProjectSection(
    String projectId,
    String title,
  ) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      _state = _state.copyWith(errorMessage: 'Section title is required.');
      notifyListeners();
      return null;
    }
    final block = await ensureProjectSectionsBlock(projectId);
    if (block == null) return null;

    final existingGroups = _state
        .recordsForProject(projectId)
        .where(
          (r) =>
              r.blockId == block.id && r.recordType == ProjectRecordType.group,
        )
        .length;

    return createRecord(
      projectId: projectId,
      blockId: block.id,
      recordType: ProjectRecordType.group,
      title: trimmed,
      sortOrder: existingGroups,
    );
  }

  Future<ProjectTrackingRecordEntity?> renameProjectSection(
    String projectId,
    String sectionRecordId,
    String title,
  ) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      _state = _state.copyWith(errorMessage: 'Section title is required.');
      notifyListeners();
      return null;
    }
    final records = await _repository.getRecordsForProject(projectId);
    ProjectTrackingRecordEntity? target;
    for (final rec in records) {
      if (rec.id == sectionRecordId &&
          rec.recordType == ProjectRecordType.group) {
        target = rec;
        break;
      }
    }
    if (target == null) {
      _state = _state.copyWith(errorMessage: 'Section not found.');
      notifyListeners();
      return null;
    }
    return updateRecord(
      target.copyWith(
        title: trimmed,
        updatedAt: EthiopiaClock.nowUtc(),
      ),
    );
  }

  Future<
      ({
        ProjectTrackingRecordEntity? deletedGroup,
        List<String> detachedTaskIds,
      })> deleteProjectSection(
    String projectId,
    String sectionRecordId,
  ) async {
    try {
      final records = await _repository.getRecordsForProject(projectId);
      ProjectTrackingRecordEntity? targetGroup;
      for (final rec in records) {
        if (rec.id == sectionRecordId &&
            rec.recordType == ProjectRecordType.group) {
          targetGroup = rec;
          break;
        }
      }
      if (targetGroup == null) {
        return (deletedGroup: null, detachedTaskIds: const <String>[]);
      }

      final children =
          records.where((r) => r.parentRecordId == sectionRecordId).toList();
      final detachedTaskIds = <String>[];

      for (final child in children) {
        if (child.linkedTaskId != null && child.linkedTaskId!.isNotEmpty) {
          detachedTaskIds.add(child.linkedTaskId!);
        }
        final hasLogs = records.any(
          (r) =>
              r.parentRecordId == child.id &&
              r.recordType == ProjectRecordType.progressLog,
        );
        if (hasLogs) {
          await _repository.updateRecord(
            child.copyWith(
              clearParentRecordId: true,
              clearLinkedTaskId: true,
              updatedAt: EthiopiaClock.nowUtc(),
            ),
          );
        } else {
          await _repository.deleteRecord(child.id);
        }
      }

      await _repository.deleteRecord(sectionRecordId);
      await refreshProject(projectId);
      return (deletedGroup: targetGroup, detachedTaskIds: detachedTaskIds);
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return (deletedGroup: null, detachedTaskIds: const <String>[]);
    }
  }

  Future<ProjectTrackingRecordEntity?> restoreProjectSection(
    String projectId,
    ProjectTrackingRecordEntity deletedGroup,
    List<String> detachedTaskIds, {
    List<TaskEntity> tasks = const [],
  }) async {
    try {
      final blocks = await _repository.getBlocksForProject(
        projectId,
        includeArchived: true,
      );
      var targetBlockId = deletedGroup.blockId;
      final hasBlock = blocks.any((b) => b.id == targetBlockId);
      if (!hasBlock) {
        final ensured = await ensureProjectSectionsBlock(projectId);
        if (ensured == null) return null;
        targetBlockId = ensured.id;
      }

      final records = await _repository.getRecordsForProject(
        projectId,
        blockId: targetBlockId,
      );
      ProjectTrackingRecordEntity restoredGroup;
      final existingGroup = records
          .where((r) => r.id == deletedGroup.id)
          .cast<ProjectTrackingRecordEntity?>()
          .firstWhere((_) => true, orElse: () => null);
      if (existingGroup != null) {
        restoredGroup = existingGroup;
      } else {
        restoredGroup = await _repository.createRecord(
          ProjectTrackingRecordEntity(
            id: deletedGroup.id,
            projectId: projectId,
            blockId: targetBlockId,
            recordType: ProjectRecordType.group,
            title: deletedGroup.title,
            sortOrder: deletedGroup.sortOrder,
            createdAt: deletedGroup.createdAt,
            updatedAt: EthiopiaClock.nowUtc(),
          ),
        );
      }

      final taskById = <String, TaskEntity>{
        for (final t in tasks) t.id: t,
      };
      for (final taskId in detachedTaskIds) {
        final task = taskById[taskId];
        await assignTaskToProjectSection(
          projectId: projectId,
          taskId: taskId,
          taskTitle: task?.title ?? 'Task',
          taskCompleted: task?.isCompleted ?? false,
          sectionRecordId: restoredGroup.id,
        );
      }

      await refreshProject(projectId);
      return restoredGroup;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<String?> detachTaskFromProjectSections(
    String projectId,
    String taskId,
  ) async {
    try {
      final records = await _repository.getRecordsForProject(projectId);
      String? previousSectionId;
      for (final rec in records) {
        if (rec.linkedTaskId != taskId) continue;
        previousSectionId ??= rec.parentRecordId;
        final hasLogs = records.any(
          (r) =>
              r.parentRecordId == rec.id &&
              r.recordType == ProjectRecordType.progressLog,
        );
        if (hasLogs || rec.recordType != ProjectRecordType.groupedItem) {
          await _repository.updateRecord(
            rec.copyWith(
              clearLinkedTaskId: true,
              updatedAt: EthiopiaClock.nowUtc(),
            ),
          );
        } else {
          await _repository.deleteRecord(rec.id);
        }
      }
      await refreshProject(projectId);
      return previousSectionId;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<void> assignTaskToProjectSection({
    required String projectId,
    required String taskId,
    required String taskTitle,
    bool taskCompleted = false,
    String? sectionRecordId,
  }) async {
    try {
      final records = await _repository.getRecordsForProject(projectId);
      for (final rec in records) {
        if (rec.linkedTaskId != taskId) continue;
        final hasLogs = records.any(
          (r) =>
              r.parentRecordId == rec.id &&
              r.recordType == ProjectRecordType.progressLog,
        );
        if (hasLogs || rec.recordType != ProjectRecordType.groupedItem) {
          await _repository.updateRecord(
            rec.copyWith(
              clearLinkedTaskId: true,
              updatedAt: EthiopiaClock.nowUtc(),
            ),
          );
        } else {
          await _repository.deleteRecord(rec.id);
        }
      }

      if (sectionRecordId != null && sectionRecordId.trim().isNotEmpty) {
        final refreshedRecords =
            await _repository.getRecordsForProject(projectId);
        ProjectTrackingRecordEntity? targetSection;
        for (final rec in refreshedRecords) {
          if (rec.id == sectionRecordId &&
              rec.recordType == ProjectRecordType.group) {
            targetSection = rec;
            break;
          }
        }
        if (targetSection != null) {
          final existingItemsCount = refreshedRecords
              .where(
                (r) =>
                    r.parentRecordId == targetSection!.id &&
                    r.recordType == ProjectRecordType.groupedItem,
              )
              .length;
          final now = EthiopiaClock.nowUtc();
          await _repository.createRecord(
            ProjectTrackingRecordEntity(
              id: 'rec-${now.microsecondsSinceEpoch}',
              projectId: projectId,
              blockId: targetSection.blockId,
              parentRecordId: targetSection.id,
              recordType: ProjectRecordType.groupedItem,
              title: taskTitle.trim().isEmpty ? 'Task' : taskTitle.trim(),
              sortOrder: existingItemsCount,
              isCompleted: taskCompleted,
              completedAt: taskCompleted ? now : null,
              linkedTaskId: taskId,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
      }

      await refreshProject(projectId);
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> syncTaskSectionLink(String projectId, TaskEntity task) async {
    try {
      final records = await _repository.getRecordsForProject(projectId);
      var changed = false;
      for (final rec in records) {
        if (rec.linkedTaskId != task.id) continue;
        if (rec.title != task.title || rec.isCompleted != task.isCompleted) {
          await _repository.updateRecord(
            rec.copyWith(
              title: task.title,
              isCompleted: task.isCompleted,
              completedAt: task.isCompleted ? (task.completedAt ?? EthiopiaClock.nowUtc()) : null,
              clearCompletedAt: !task.isCompleted,
              updatedAt: EthiopiaClock.nowUtc(),
            ),
          );
          changed = true;
        }
      }
      if (changed) {
        await refreshProject(projectId);
      }
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  void clearError() {
    if (_state.errorMessage != null) {
      _state = _state.copyWith(clearError: true);
      notifyListeners();
    }
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    super.dispose();
  }
}
