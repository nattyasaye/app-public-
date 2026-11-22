import '../../domain/projects/project_models.dart';
import '../../domain/tasks/task_models.dart';

/// Immutable state container for the Stage 1 Daywell Projects module.
class ProjectsModuleState {
  final List<ProjectEntity> projects;
  final Map<String, List<ProjectTrackingBlockEntity>> blocksByProject;
  final Map<String, List<ProjectTrackingRecordEntity>> recordsByProject;
  final Map<String, ProjectProgressSummary> summariesByProject;
  final String? selectedProjectId;
  final bool includeArchived;
  final bool isLoading;
  final String? errorMessage;

  const ProjectsModuleState({
    this.projects = const [],
    this.blocksByProject = const {},
    this.recordsByProject = const {},
    this.summariesByProject = const {},
    this.selectedProjectId,
    this.includeArchived = false,
    this.isLoading = false,
    this.errorMessage,
  });

  List<ProjectEntity> get visibleProjects => includeArchived
      ? projects
      : projects.where((p) => !p.isArchived).toList(growable: false);

  List<ProjectEntity> get activeProjects => projects
      .where((p) => !p.isArchived && p.status == 'active')
      .toList(growable: false);

  List<ProjectEntity> get archivedProjects =>
      projects.where((p) => p.isArchived).toList(growable: false);

  ProjectEntity? findProjectById(String id) {
    for (final p in projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<ProjectTrackingBlockEntity> blocksForProject(
    String projectId, {
    bool? includeArchived,
  }) {
    final list = blocksByProject[projectId] ?? const [];
    final effectiveInclude = includeArchived ?? this.includeArchived;
    if (effectiveInclude) return list;
    return list.where((b) => !b.isArchived).toList(growable: false);
  }

  List<ProjectTrackingRecordEntity> recordsForProject(String projectId) {
    return recordsByProject[projectId] ?? const [];
  }

  List<ProjectTrackingRecordEntity> recordsForBlock(
    String projectId,
    String blockId,
  ) {
    final list = recordsByProject[projectId] ?? const [];
    return list.where((r) => r.blockId == blockId).toList(growable: false);
  }

  List<ProjectTrackingRecordEntity> sectionsForProject(String projectId) {
    final blocks = blocksForProject(projectId, includeArchived: false)
        .where((b) => b.blockType == ProjectBlockType.groupedList)
        .toList(growable: false);
    if (blocks.isEmpty) return const [];
    final blockIds = blocks.map((b) => b.id).toSet();
    final sections = recordsForProject(projectId)
        .where(
          (r) =>
              r.recordType == ProjectRecordType.group &&
              blockIds.contains(r.blockId),
        )
        .toList(growable: false);
    sections.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return List<ProjectTrackingRecordEntity>.unmodifiable(sections);
  }

  Set<String> taskIdsForSection(
    String projectId,
    String sectionIdOrUnsectioned, {
    Iterable<TaskEntity> allTasks = const [],
  }) {
    final blocks = blocksForProject(projectId, includeArchived: false)
        .where((b) => b.blockType == ProjectBlockType.groupedList)
        .toList(growable: false);
    final blockIds = blocks.map((b) => b.id).toSet();
    final records = recordsForProject(projectId);

    if (sectionIdOrUnsectioned == '__unsectioned__') {
      final validGroupIds = records
          .where(
            (r) =>
                r.recordType == ProjectRecordType.group &&
                blockIds.contains(r.blockId),
          )
          .map((g) => g.id)
          .toSet();
      final sectionedIds = <String>{};
      for (final rec in records) {
        if (rec.recordType == ProjectRecordType.groupedItem &&
            blockIds.contains(rec.blockId) &&
            rec.linkedTaskId != null &&
            rec.parentRecordId != null &&
            validGroupIds.contains(rec.parentRecordId)) {
          sectionedIds.add(rec.linkedTaskId!);
        }
      }
      return allTasks
          .where((t) => t.projectId == projectId && !sectionedIds.contains(t.id))
          .map((t) => t.id)
          .toSet();
    }

    final result = <String>{};
    for (final rec in records) {
      if (rec.recordType == ProjectRecordType.groupedItem &&
          blockIds.contains(rec.blockId) &&
          rec.parentRecordId == sectionIdOrUnsectioned &&
          rec.linkedTaskId != null) {
        result.add(rec.linkedTaskId!);
      }
    }
    return result;
  }

  ProjectProgressSummary? summaryForProject(String projectId) {
    return summariesByProject[projectId];
  }

  ProjectsModuleState copyWith({
    List<ProjectEntity>? projects,
    Map<String, List<ProjectTrackingBlockEntity>>? blocksByProject,
    Map<String, List<ProjectTrackingRecordEntity>>? recordsByProject,
    Map<String, ProjectProgressSummary>? summariesByProject,
    String? selectedProjectId,
    bool clearSelectedProject = false,
    bool? includeArchived,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ProjectsModuleState(
      projects: projects ?? this.projects,
      blocksByProject: blocksByProject ?? this.blocksByProject,
      recordsByProject: recordsByProject ?? this.recordsByProject,
      summariesByProject: summariesByProject ?? this.summariesByProject,
      selectedProjectId: clearSelectedProject
          ? null
          : (selectedProjectId ?? this.selectedProjectId),
      includeArchived: includeArchived ?? this.includeArchived,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
