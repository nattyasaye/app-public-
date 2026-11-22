import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/projects/projects_controller.dart';
import '../../../application/tasks/tasks_controller.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/tasks/task_models.dart';
import '../../widgets/shared_ui_widgets.dart';
import 'project_ui_helpers.dart';

class ProjectMilestonesWidget extends StatelessWidget {
  final ProjectEntity project;
  final List<MilestoneEntity> milestones;
  final List<TaskEntity> tasks;
  final TasksController? tasksController;
  final ProjectsController projectsController;

  const ProjectMilestonesWidget({
    super.key,
    required this.project,
    required this.milestones,
    required this.tasks,
    required this.tasksController,
    required this.projectsController,
  });

  Future<void> _openMilestoneDialog(
    BuildContext context, {
    MilestoneEntity? existing,
  }) async {
    final ctrl = tasksController;
    if (ctrl == null) return;

    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    CalendarDate? dueDate = existing?.dueDate;
    String? titleError;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final semantic = ctx.daywellColors;
          return AlertDialog(
            title: Text(existing == null ? 'New Milestone' : 'Edit Milestone'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DaywellTextField(
                    controller: titleCtrl,
                    autofocus: true,
                    isRequired: true,
                    label: 'Milestone Title',
                    hintText: 'e.g. Architecture sign-off',
                    errorText: titleError,
                    onChanged: (_) {
                      if (titleError != null) {
                        setDialogState(() => titleError = null);
                      }
                    },
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  Text(
                    'Due Date (optional)',
                    style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                          color: semantic.textSecondary,
                        ),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                  Wrap(
                    spacing: SharedDesignTokens.spacingSm,
                    runSpacing: SharedDesignTokens.spacingXs,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.edit_calendar_outlined, size: 16),
                        label: Text(
                          dueDate == null
                              ? 'Pick Date'
                              : SharedDateFormatter.formatDual(
                                  dueDate!,
                                  useAmharic: false,
                                ),
                        ),
                        onPressed: () async {
                          final picked = await pickProjectCalendarDate(
                            ctx,
                            initialDate: dueDate,
                            helpText: 'Milestone Due Date',
                          );
                          if (picked != null && ctx.mounted) {
                            setDialogState(() => dueDate = picked);
                          }
                        },
                      ),
                      if (dueDate != null)
                        ActionChip(
                          avatar: const Icon(Icons.clear, size: 16),
                          label: const Text('Clear'),
                          onPressed: () => setDialogState(() => dueDate = null),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final trimmed = titleCtrl.text.trim();
                  if (trimmed.isEmpty) {
                    setDialogState(
                      () => titleError = 'Milestone title is required.',
                    );
                    return;
                  }
                  if (existing == null) {
                    await ctrl.addMilestone(
                      projectId: project.id,
                      title: trimmed,
                      dueDate: dueDate,
                    );
                  } else {
                    await ctrl.updateMilestone(
                      milestoneId: existing.id,
                      title: trimmed,
                      dueDate: dueDate,
                      clearDueDate: dueDate == null,
                    );
                  }
                  await projectsController.refreshProject(project.id);
                  if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                },
                child: Text(existing == null ? 'Add Milestone' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _toggleMilestone(
    BuildContext context,
    MilestoneEntity milestone,
  ) async {
    final ctrl = tasksController;
    if (ctrl == null) return;
    final nextDone = !milestone.isCompleted;
    await ctrl.toggleMilestone(milestone.id, nextDone);
    await projectsController.refreshProject(project.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nextDone
              ? 'Completed milestone "${milestone.title}"'
              : 'Reopened milestone "${milestone.title}"',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(() async {
              await ctrl.toggleMilestone(milestone.id, !nextDone);
              await projectsController.refreshProject(project.id);
            }());
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _deleteMilestone(
    BuildContext context,
    MilestoneEntity milestone,
  ) async {
    final ctrl = tasksController;
    if (ctrl == null) return;

    final confirmed = await DaywellConfirmationDialog.show(
      context,
      title: 'Delete Milestone?',
      message:
          'Delete milestone "${milestone.title}"? Linked tasks stay safe in this project without a milestone.',
      confirmLabel: 'Delete',
      isDestructive: true,
      icon: Icons.flag_outlined,
    );
    if (!confirmed || !context.mounted) return;

    final detachedTaskIds = await ctrl.deleteMilestone(milestone.id);
    await projectsController.refreshProject(project.id);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted milestone "${milestone.title}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(() async {
              await ctrl.restoreDeletedMilestone(
                milestone,
                restoreTaskIds: detachedTaskIds,
              );
              await projectsController.refreshProject(project.id);
            }());
          },
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final completedCount = milestones.where((m) => m.isCompleted).length;
    final pct = milestones.isEmpty
        ? 0.0
        : (completedCount / milestones.length).clamp(0.0, 1.0);

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.flag_outlined,
                size: DaywellIconSize.sm,
                color: semantic.textSecondary,
              ),
              const SizedBox(width: SharedDesignTokens.spacingXs),
              Expanded(
                child: Text(
                  'Milestones',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$completedCount/${milestones.length} done',
                style: DaywellTypography.numericBody(
                  color: semantic.textSecondary,
                ),
              ),
              if (tasksController != null) ...[
                const SizedBox(width: SharedDesignTokens.spacingSm),
                DaywellButton(
                  label: 'Add',
                  variant: DaywellButtonVariant.outlined,
                  size: DaywellButtonSize.compact,
                  leadingIcon: Icons.add,
                  onPressed: () => _openMilestoneDialog(context),
                ),
              ],
            ],
          ),
          if (milestones.isNotEmpty) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            DaywellProgressBar(
              value: pct,
              semanticLabel: 'Milestones progress',
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
            for (final milestone in milestones) ...[
              Builder(
                builder: (ctx) {
                  final linkedTaskCount = tasks
                      .where((t) => t.milestoneId == milestone.id)
                      .length;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: SharedDesignTokens.spacingXs,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Checkbox(
                          value: milestone.isCompleted,
                          onChanged: tasksController == null
                              ? null
                              : (_) => _toggleMilestone(context, milestone),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                milestone.title,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  decoration: milestone.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: milestone.isCompleted
                                      ? semantic.textMuted
                                      : semantic.textPrimary,
                                ),
                              ),
                              if (milestone.dueDate != null ||
                                  linkedTaskCount > 0) ...[
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    if (milestone.dueDate != null)
                                      'Due ${SharedDateFormatter.formatDual(milestone.dueDate!, useAmharic: false)}',
                                    if (linkedTaskCount > 0)
                                      '$linkedTaskCount ${linkedTaskCount == 1 ? 'task' : 'tasks'}',
                                  ].join(' · '),
                                  style: textTheme.bodySmall?.copyWith(
                                    color: semantic.textMuted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (tasksController != null) ...[
                          DaywellIconButton(
                            icon: Icons.edit_outlined,
                            tooltip: 'Edit milestone ${milestone.title}',
                            onPressed: () => _openMilestoneDialog(
                              context,
                              existing: milestone,
                            ),
                          ),
                          DaywellIconButton(
                            icon: Icons.delete_outline,
                            tooltip: 'Delete milestone ${milestone.title}',
                            isDestructive: true,
                            onPressed: () =>
                                _deleteMilestone(context, milestone),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ] else ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            Text(
              tasksController == null
                  ? 'Milestones appear here once TasksController is connected.'
                  : 'No milestones yet. Add key checkpoints to track major phases.',
              style: textTheme.bodySmall?.copyWith(
                color: semantic.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
