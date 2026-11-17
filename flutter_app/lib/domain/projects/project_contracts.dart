import '../../core/date/shared_date.dart';
import '../tasks/task_models.dart';
import 'project_models.dart';
import 'project_package_codec.dart';

/// Repository contract for the Stage 1 Projects tracking foundation.
abstract class IProjectsRepository {
  Future<List<ProjectEntity>> getProjects({
    String? status,
    bool includeArchived = true,
  });

  Future<ProjectEntity?> getProjectById(String id);

  Future<ProjectEntity> createProject(ProjectEntity project);

  Future<ProjectEntity> updateProject(ProjectEntity project);

  Future<ProjectEntity> setProjectArchived(String projectId, bool isArchived);

  Future<void> deleteProject(String projectId);

  Future<List<ProjectTrackingBlockEntity>> getBlocksForProject(
    String projectId, {
    bool includeArchived = true,
  });

  Future<ProjectTrackingBlockEntity> createBlock(
    ProjectTrackingBlockEntity block,
  );

  Future<ProjectTrackingBlockEntity> updateBlock(
    ProjectTrackingBlockEntity block,
  );

  Future<ProjectTrackingBlockEntity> setBlockArchived(
    String blockId,
    bool isArchived,
  );

  Future<void> deleteBlock(String blockId);

  Future<List<ProjectTrackingRecordEntity>> getRecordsForProject(
    String projectId, {
    String? blockId,
  });

  Future<ProjectTrackingRecordEntity> createRecord(
    ProjectTrackingRecordEntity record,
  );

  Future<ProjectTrackingRecordEntity> updateRecord(
    ProjectTrackingRecordEntity record,
  );

  Future<ProjectTrackingRecordEntity> appendProgressLog(
    ProjectTrackingRecordEntity logRecord,
  );

  Future<ProjectTrackingRecordEntity> appendProgressCorrection({
    required String targetLogId,
    required double correctionDelta,
    required CalendarDate recordedDate,
    required String reason,
    String? correctionId,
  });

  Future<void> deleteRecord(String recordId);

  Future<ProjectProgressSummary> getProjectProgressSummary(
    String projectId, {
    CalendarDate? asOfDate,
  });

  Future<String> exportProjectPackageJson(String projectId);

  Future<PreparedProjectPackageImport> importProjectPackageJson(String rawJson);
}
