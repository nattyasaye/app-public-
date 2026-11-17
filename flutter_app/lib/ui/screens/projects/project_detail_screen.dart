import 'package:flutter/material.dart';

import '../../../application/projects/projects_controller.dart';
import '../../../application/tasks/tasks_controller.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/projects/project_models.dart';
import '../../../domain/tasks/task_models.dart';
import '../../widgets/shared_ui_widgets.dart';
import 'project_form_sheet.dart';
import 'project_progress_history_widget.dart';
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

        final blocks = state.blocksForProject(project.id, includeArchived: true);
        final records = state.recordsForProject(project.id);
        final summary = state.summaryForProject(project.id);
        final linkedTasks = (tasksController?.state.tasks ?? const <TaskEntity>[])
            .where((t) => t.projectId == project.id && t.status != 'cancelled')
            .toList(growable: false);

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
                      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
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
                            const SizedBox(height: SharedDesignTokens.spacingSm),
                            Text(
                              'Linked Goal: ${project.goalId!}',
                              style: textTheme.bodySmall?.copyWith(
                                color: semantic.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    _buildOverallProgressCard(context, summary),
                    if (linkedTasks.isNotEmpty) ...[
                      const SizedBox(height: SharedDesignTokens.spacingCompact),
                      _buildLinkedTasksCard(context, linkedTasks),
                    ],
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
    BuildContext context,
    ProjectProgressSummary? summary,
  ) {
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
      return DaywellCard(
        padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
        child: Row(
          children: [
            Icon(
              Icons.insights_outlined,
              size: DaywellIconSize.md,
              color: semantic.textMuted,
            ),
            const SizedBox(width: SharedDesignTokens.spacingSm),
            Expanded(
              child: Text(
                'Each tracking block calculates its own progress independently. Star a block below to feature it as headline progress.',
                style: textTheme.bodySmall?.copyWith(
                  color: semantic.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final pct = summary.overallPercentage ?? primaryMetric.progressPercent;
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
        ],
      ),
    );
  }

  Widget _buildLinkedTasksCard(
    BuildContext context,
    List<TaskEntity> linkedTasks,
  ) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final completed = linkedTasks
        .where((t) => t.isCompleted || t.status == 'completed')
        .length;

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Linked Tasks',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$completed / ${linkedTasks.length} done',
                style: DaywellTypography.numericBody(
                  color: semantic.textSecondary,
                ).copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          for (final task in linkedTasks.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: SharedDesignTokens.spacingXs,
              ),
              child: Row(
                children: [
                  Icon(
                    task.isCompleted
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: DaywellIconSize.sm,
                    color: task.isCompleted
                        ? Theme.of(context).colorScheme.primary
                        : semantic.textMuted,
                  ),
                  const SizedBox(width: SharedDesignTokens.spacingSm),
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        decoration: task.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (linkedTasks.length > 5)
            Text(
              '+${linkedTasks.length - 5} more in Tasks tab',
              style: textTheme.bodySmall?.copyWith(color: semantic.textMuted),
            ),
        ],
      ),
    );
  }
}
