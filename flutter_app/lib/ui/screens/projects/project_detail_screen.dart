import 'package:flutter/material.dart';

import '../../../application/projects/projects_controller.dart';
import '../../../application/tasks/tasks_controller.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/projects/progress_engine.dart';
import '../../../domain/projects/project_models.dart';
import '../../../domain/projects/project_package_codec.dart';
import '../../../domain/tasks/task_models.dart';
import '../../../services/export/project_package_io_service.dart';
import '../../widgets/shared_ui_widgets.dart';
import 'project_form_sheet.dart';
import 'project_milestones_widget.dart';
import 'project_progress_history_widget.dart';
import 'project_tasks_sections_widget.dart';
import 'project_tracking_blocks_widget.dart';
import 'project_ui_helpers.dart';

class ProjectDetailScreen extends StatelessWidget {
  final String projectId;
  final ProjectsController projectsController;
  final TasksController? tasksController;

  const ProjectDetailScreen({
    super.key,
    required this.projectId,
    required this.projectsController,
    this.tasksController,
  });

  Future<void> _archiveOrRestore(
    BuildContext context,
    ProjectEntity project,
  ) async {
    final targetArchived = !project.isArchived;
    if (targetArchived) {
      final confirmed = await DaywellConfirmationDialog.show(
        context,
        title: 'Archive Project?',
        message:
            'Archive "${project.title}"? Its blocks and progress history remain preserved and can be restored anytime from the Archived view.',
        confirmLabel: 'Archive',
        icon: Icons.archive_outlined,
      );
      if (!confirmed || !context.mounted) return;
    }
    await projectsController.setProjectArchived(project.id, targetArchived);
    syncTasksControllerProjects(tasksController);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          targetArchived
              ? 'Archived "${project.title}"'
              : 'Restored "${project.title}"',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(() async {
              await projectsController.setProjectArchived(
                project.id,
                !targetArchived,
              );
              syncTasksControllerProjects(tasksController);
            }());
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _deleteForever(
    BuildContext context,
    ProjectEntity project,
  ) async {
    if (!project.isArchived) return;
    final confirmed = await DaywellConfirmationDialog.show(
      context,
      title: 'Delete Archived Project?',
      message:
          'Permanently delete "${project.title}", all of its tracking blocks, and its progress history? Linked tasks will be detached and kept safely.',
      confirmLabel: 'Delete Forever',
      isDestructive: true,
      icon: Icons.delete_forever_outlined,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await projectsController.deleteProject(project.id);
    syncTasksControllerProjects(tasksController);
    if (ok && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _exportPackage(
    BuildContext context,
    ProjectEntity project,
  ) async {
    final json = await projectsController.exportProjectPackageJson(project.id);
    if (!context.mounted) return;
    if (json == null) {
      final err =
          projectsController.state.errorMessage ?? 'Unable to export project.';
      projectsController.clearError();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $err')),
      );
      return;
    }
    final filename = ProjectPackageCodec.buildFilename(project.title);
    try {
      await ProjectPackageIoService.exportPackageFile(
        filename: filename,
        jsonContent: json,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Prepared "$filename" for export.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to share "$filename": $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final listenable = tasksController != null
        ? Listenable.merge([projectsController, tasksController!])
        : projectsController;

    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final state = projectsController.state;
        final project = state.findProjectById(projectId);

        if (project == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Project')),
            body: DaywellEmptyState(
              icon: Icons.folder_off_outlined,
              message: 'Project not found',
              subtitle: 'This project may have been deleted.',
              actionLabel: 'Back',
              onActionPressed: () => Navigator.of(context).maybePop(),
            ),
          );
        }

        final blocks =
            state.blocksForProject(project.id, includeArchived: true);
        final records = state.recordsForProject(project.id);
        final summary = state.summaryForProject(project.id);
        final linkedTasks = (tasksController?.state.tasks ??
                const <TaskEntity>[])
            .where(
              (t) =>
                  t.projectId == project.id &&
                  !t.isArchived &&
                  t.status != 'cancelled',
            )
            .toList(growable: false);
        final projectMilestones = (tasksController?.state.milestones ??
                const <MilestoneEntity>[])
            .where((m) => m.projectId == project.id)
            .toList(growable: false);
        final completedTasksCount =
            linkedTasks.where((t) => t.isCompleted).length;
        final completedMilestonesCount =
            projectMilestones.where((m) => m.isCompleted).length;

        final semantic = context.daywellColors;
        final textTheme = Theme.of(context).textTheme;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              project.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              DaywellIconButton(
                icon: Icons.file_download_outlined,
                tooltip: 'Export .daywellproject',
                onPressed: () => _exportPackage(context, project),
              ),
              DaywellIconButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit project',
                onPressed: () => ProjectFormSheet.show(
                  context,
                  projectsController: projectsController,
                  tasksController: tasksController,
                  existingProject: project,
                ),
              ),
              DaywellIconButton(
                icon: project.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
                tooltip:
                    project.isArchived ? 'Restore project' : 'Archive project',
                onPressed: () => _archiveOrRestore(context, project),
              ),
              if (project.isArchived)
                DaywellIconButton(
                  icon: Icons.delete_forever_outlined,
                  tooltip: 'Delete archived project permanently',
                  isDestructive: true,
                  onPressed: () => _deleteForever(context, project),
                ),
            ],
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: SharedDesignTokens.breakpointMaxContentWidth,
                ),
                child: ListView(
                  padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
                  children: [
                    if (state.errorMessage != null &&
                        state.errorMessage!.isNotEmpty) ...[
                      DaywellStatusBanner(
                        message: state.errorMessage!,
                        tone: DaywellStatusTone.error,
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingCompact),
                    ],
                    if (project.isArchived) ...[
                      DaywellStatusBanner(
                        title: 'Archived Project',
                        message:
                            'This project is archived. Restore it to resume active tracking, or delete it permanently.',
                        tone: DaywellStatusTone.warning,
                        actionLabel: 'Restore',
                        onActionPressed: () =>
                            _archiveOrRestore(context, project),
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingCompact),
                    ],
                    DaywellCard(
                      padding:
                          const EdgeInsets.all(SharedDesignTokens.spacingMd),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: SharedDesignTokens.spacingSm,
                            runSpacing: SharedDesignTokens.spacingXs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              DaywellStatusBadge(
                                label: projectStatusLabel(project),
                                tone: projectStatusTone(project),
                              ),
                              if (project.startDate != null)
                                Text(
                                  'Start: ${SharedDateFormatter.formatDual(project.startDate!, useAmharic: false)}',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: semantic.textSecondary,
                                  ),
                                ),
                              if (project.targetDate != null)
                                Text(
                                  'Target: ${SharedDateFormatter.formatDual(project.targetDate!, useAmharic: false)}',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: semantic.textSecondary,
                                  ),
                                ),
                              if (project.startDate != null &&
                                  project.targetDate != null) ...[
                                Builder(
                                  builder: (context) {
                                    final span =
                                        ProgressEngine.computeScheduleSpan(
                                      startDate: project.startDate,
                                      targetDate: project.targetDate,
                                    );
                                    if (span.totalDays == null) {
                                      return const SizedBox.shrink();
                                    }
                                    return Text(
                                      '${span.totalDays} days',
                                      style: DaywellTypography.numericBody(
                                        color: semantic.textSecondary,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                          if (project.description != null &&
                              project.description!.trim().isNotEmpty) ...[
                            const SizedBox(
                              height: SharedDesignTokens.spacingCompact,
                            ),
                            Text(
                              project.description!.trim(),
                              style: textTheme.bodyMedium?.copyWith(
                                color: semantic.textSecondary,
                              ),
                            ),
                          ],
                          if (project.goalId != null &&
                              project.goalId!.trim().isNotEmpty) ...[
                            const SizedBox(
                                height: SharedDesignTokens.spacingSm),
                            Text(
                              'Linked Goal: ${project.goalId!}',
                              style: textTheme.bodySmall?.copyWith(
                                color: semantic.textMuted,
                              ),
                            ),
                          ],
                          const SizedBox(height: SharedDesignTokens.spacingSm),
                          Builder(
                            builder: (_) {
                              final remainingTasksCount =
                                  (linkedTasks.length - completedTasksCount)
                                      .clamp(0, linkedTasks.length);
                              final parts = <String>[
                                '$completedTasksCount/${linkedTasks.length} ${linkedTasks.length == 1 ? 'task' : 'tasks'} · $remainingTasksCount remaining',
                                if (projectMilestones.isNotEmpty)
                                  '$completedMilestonesCount/${projectMilestones.length} ${projectMilestones.length == 1 ? 'milestone' : 'milestones'}',
                              ];
                              return Text(
                                parts.join(' · '),
                                style: DaywellTypography.numericBody(
                                  color: semantic.textSecondary,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    _buildOverallProgressCard(
                      context,
                      project: project,
                      summary: summary,
                      totalTasks: linkedTasks.length,
                      completedTasks: completedTasksCount,
                      totalMilestones: projectMilestones.length,
                      completedMilestones: completedMilestonesCount,
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingMd),
                    ProjectMilestonesWidget(
                      project: project,
                      milestones: projectMilestones,
                      tasks: linkedTasks,
                      tasksController: tasksController,
                      projectsController: projectsController,
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingMd),
                    ProjectTasksSectionsWidget(
                      project: project,
                      blocks: blocks,
                      records: records,
                      milestones: projectMilestones,
                      tasks: linkedTasks,
                      tasksController: tasksController,
                      projectsController: projectsController,
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingMd),
                    ProjectTrackingBlocksWidget(
                      project: project,
                      blocks: blocks,
                      records: records,
                      summary: summary,
                      projectsController: projectsController,
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingMd),
                    ProjectProgressHistoryWidget(
                      projectId: project.id,
                      blocks: blocks,
                      records: records,
                      projectsController: projectsController,
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingXl),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverallProgressCard(
    BuildContext context, {
    required ProjectEntity project,
    required ProjectProgressSummary? summary,
    required int totalTasks,
    required int completedTasks,
    required int totalMilestones,
    required int completedMilestones,
  }) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    if (summary == null) {
      return const SizedBox.shrink();
    }

    if (summary.hasInvalidPrimaryBlockReference) {
      return const DaywellStatusBanner(
        title: 'Primary Progress Block Unavailable',
        message:
            'The selected primary block is missing or archived. Star an active block below to restore headline progress.',
        tone: DaywellStatusTone.warning,
      );
    }

    final primaryMetric = summary.primaryMetric;
    if (primaryMetric == null) {
      final totalItems = totalTasks + totalMilestones;
      final completedItems = completedTasks + completedMilestones;
      final derivedPct = ProgressEngine.calculateProgressPercentage(
        totalTasks: totalTasks,
        completedTasks: completedTasks,
        totalMilestones: totalMilestones,
        completedMilestones: completedMilestones,
        isProjectManuallyCompleted: project.status == 'completed' &&
            totalTasks == 0 &&
            totalMilestones == 0,
      );
      return DaywellCard(
        padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PROJECT COMPLETION',
                        style: textTheme.labelSmall?.copyWith(
                          color: semantic.textMuted,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingXs),
                      Text(
                        totalItems > 0
                            ? 'Tasks & milestones ($completedItems/$totalItems done)'
                            : project.status == 'completed'
                                ? 'Marked complete'
                                : 'No tasks or milestones linked yet',
                        style: textTheme.bodySmall?.copyWith(
                          color: semantic.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$derivedPct%',
                  style: DaywellTypography.numericHero(
                    color: semantic.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
            DaywellProgressBar(
              value: derivedPct / 100.0,
              semanticLabel: 'Derived project completion progress',
            ),
            const SizedBox(height: SharedDesignTokens.spacingXs),
            Text(
              'Star a tracking block below to feature block progress instead.',
              style: textTheme.bodySmall?.copyWith(color: semantic.textMuted),
            ),
          ],
        ),
      );
    }

    final pct = summary.overallPercentage ?? primaryMetric.progressPercent;
    final unit = primaryMetric.unitLabel?.trim().isNotEmpty == true
        ? ' ${primaryMetric.unitLabel!.trim()}'
        : '';
    final cappedCompleted =
        primaryMetric.targetCompletedTotal ?? primaryMetric.loggedTotal;
    final overAmount = primaryMetric.overTargetAmount ?? 0.0;
    final overItems = primaryMetric.overTargetItemCount ?? 0;
    final remaining =
        (primaryMetric.targetValue != null && primaryMetric.targetValue! > 0)
            ? (primaryMetric.targetValue! - cappedCompleted)
                .clamp(0.0, double.infinity)
            : null;

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OVERALL PROGRESS',
                      style: textTheme.labelSmall?.copyWith(
                        color: semantic.textMuted,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    Text(
                      primaryMetric.title,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (primaryMetric.targetValue != null &&
                        primaryMetric.targetValue! > 0) ...[
                      const SizedBox(height: SharedDesignTokens.spacingXs),
                      Text(
                        '${formatProjectNumber(cappedCompleted)} / ${formatProjectNumber(primaryMetric.targetValue!)}$unit · ${primaryMetric.completedCount}/${primaryMetric.totalCount} items',
                        style: DaywellTypography.numericBody(
                          color: semantic.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (pct != null)
                Text(
                  '${pct.round()}%',
                  style: DaywellTypography.numericHero(
                    color: semantic.textPrimary,
                  ),
                ),
            ],
          ),
          if (pct != null) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            DaywellProgressBar(
              value: pct / 100.0,
              semanticLabel: 'Overall project progress',
            ),
          ],
          if (remaining != null ||
              primaryMetric.dailyTargetValue != null ||
              primaryMetric.todayTotal > 0 ||
              (primaryMetric.paceNeededPerDay ?? 0) > 0) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            Text(
              [
                if (remaining != null)
                  'Remaining: ${formatProjectNumber(remaining)}$unit',
                if (primaryMetric.dailyTargetValue != null ||
                    primaryMetric.todayTotal > 0)
                  'Today: ${formatProjectNumber(primaryMetric.todayTotal)}${primaryMetric.dailyTargetValue != null ? ' / ${formatProjectNumber(primaryMetric.dailyTargetValue!)}$unit' : unit}',
                if (primaryMetric.paceNeededPerDay != null &&
                    primaryMetric.paceNeededPerDay! > 0)
                  'Pace needed: ${formatProjectNumber(primaryMetric.paceNeededPerDay!)}/day',
              ].join(' · '),
              style: DaywellTypography.numericBody(
                color: semantic.textSecondary,
              ),
            ),
          ],
          if (overAmount > 0) ...[
            const SizedBox(height: SharedDesignTokens.spacingXs),
            Text(
              'Actual sent: ${formatProjectNumber(primaryMetric.loggedTotal)}$unit (+${formatProjectNumber(overAmount)} beyond ${overItems > 0 ? "$overItems item target${overItems == 1 ? '' : 's'}" : "target"}, excluded from target completion)',
              style: DaywellTypography.numericBody(
                color: semantic.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
