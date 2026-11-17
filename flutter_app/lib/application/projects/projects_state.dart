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
