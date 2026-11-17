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
