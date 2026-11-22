import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/projects/projects_controller.dart';
import '../../../application/tasks/tasks_controller.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/projects/project_models.dart';
import '../../../domain/tasks/task_models.dart';
import '../../../domain/tasks/task_recurrence_engine.dart';
import '../../widgets/shared_ui_widgets.dart';
import '../tasks/task_recurrence_widgets.dart';
import 'project_ui_helpers.dart';

class ProjectTasksSectionsWidget extends StatelessWidget {
  final ProjectEntity project;
  final List<ProjectTrackingBlockEntity> blocks;
  final List<ProjectTrackingRecordEntity> records;
  final List<MilestoneEntity> milestones;
  final List<TaskEntity> tasks;
  final TasksController? tasksController;
  final ProjectsController projectsController;

  const ProjectTasksSectionsWidget({
    super.key,
    required this.project,
    required this.blocks,
    required this.records,
    required this.milestones,
    required this.tasks,
    required this.tasksController,
    required this.projectsController,
  });

  static const List<(String, String)> _priorityOptions = [
    ('urgent', 'Urgent'),
    ('high', 'High'),
    ('medium', 'Medium'),
    ('low', 'Low'),
  ];

  static const List<(String, String)> _statusOptions = [
    ('not_started', 'Not Started'),
    ('in_progress', 'In Progress'),
    ('completed', 'Completed'),
    ('inbox', 'Inbox'),
  ];

  ({
    List<ProjectTrackingRecordEntity> sections,
    Map<String, List<TaskEntity>> tasksBySectionId,
    Map<String, String> sectionIdByTaskId,
    List<TaskEntity> unsectionedTasks,
  }) _computeSectionLayout() {
    final activeGroupedBlockIds = blocks
        .where(
          (b) => !b.isArchived && b.blockType == ProjectBlockType.groupedList,
        )
        .map((b) => b.id)
        .toSet();

    final sectionRecords = records
        .where(
          (r) =>
              r.recordType == ProjectRecordType.group &&
              activeGroupedBlockIds.contains(r.blockId),
        )
        .toList()
      ..sort((a, b) {
        final orderCmp = a.sortOrder.compareTo(b.sortOrder);
        if (orderCmp != 0) return orderCmp;
        return a.createdAt.compareTo(b.createdAt);
      });

    final sectionIdSet = sectionRecords.map((s) => s.id).toSet();
    final tasksById = {for (final t in tasks) t.id: t};
    final sectionIdByTaskId = <String, String>{};
    final sortOrderByTaskId = <String, int>{};

    for (final rec in records) {
      if (rec.recordType == ProjectRecordType.groupedItem &&
          activeGroupedBlockIds.contains(rec.blockId) &&
          rec.linkedTaskId != null &&
          rec.parentRecordId != null &&
          sectionIdSet.contains(rec.parentRecordId!) &&
          tasksById.containsKey(rec.linkedTaskId!) &&
          !sectionIdByTaskId.containsKey(rec.linkedTaskId!)) {
        sectionIdByTaskId[rec.linkedTaskId!] = rec.parentRecordId!;
        sortOrderByTaskId[rec.linkedTaskId!] = rec.sortOrder;
      }
    }

    final tasksBySectionId = <String, List<TaskEntity>>{
      for (final section in sectionRecords) section.id: <TaskEntity>[],
    };
    final unsectioned = <TaskEntity>[];

    for (final task in tasks) {
      final secId = sectionIdByTaskId[task.id];
      if (secId != null && tasksBySectionId.containsKey(secId)) {
        tasksBySectionId[secId]!.add(task);
      } else {
        unsectioned.add(task);
      }
    }

    for (final section in sectionRecords) {
      tasksBySectionId[section.id]!.sort(
        (a, b) => (sortOrderByTaskId[a.id] ?? 0)
            .compareTo(sortOrderByTaskId[b.id] ?? 0),
      );
    }

    return (
      sections: sectionRecords,
      tasksBySectionId: tasksBySectionId,
      sectionIdByTaskId: sectionIdByTaskId,
      unsectionedTasks: unsectioned,
    );
  }

  Future<void> _openSectionDialog(
    BuildContext context, {
    ProjectTrackingRecordEntity? existing,
  }) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    String? titleError;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'New Section' : 'Rename Section'),
          content: DaywellTextField(
            controller: titleCtrl,
            autofocus: true,
            isRequired: true,
            label: 'Section Name',
            hintText: 'e.g. Planning, Build, Launch',
            errorText: titleError,
            onChanged: (_) {
              if (titleError != null) {
                setDialogState(() => titleError = null);
              }
            },
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
                    () => titleError = 'Section title is required.',
                  );
                  return;
                }
                if (existing == null) {
                  await projectsController.createProjectSection(
                    project.id,
                    trimmed,
                  );
                } else {
                  await projectsController.renameProjectSection(
                    project.id,
                    existing.id,
                    trimmed,
                  );
                }
                if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
              },
              child: Text(existing == null ? 'Create' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSection(
    BuildContext context,
    ProjectTrackingRecordEntity section,
  ) async {
    final confirmed = await DaywellConfirmationDialog.show(
      context,
      title: 'Delete Section?',
      message:
          'Delete section "${section.title ?? 'Section'}"? Tasks inside it stay safely in General.',
      confirmLabel: 'Delete Section',
      isDestructive: true,
      icon: Icons.folder_delete_outlined,
    );
    if (!confirmed || !context.mounted) return;

    final result = await projectsController.deleteProjectSection(
      project.id,
      section.id,
    );
    if (!context.mounted || result.deletedGroup == null) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted section "${section.title ?? 'Section'}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(
              projectsController.restoreProjectSection(
                project.id,
                result.deletedGroup!,
                result.detachedTaskIds,
                tasks: tasks,
              ),
            );
          },
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _openTaskDialog(
    BuildContext context, {
    required List<ProjectTrackingRecordEntity> sections,
    required Map<String, String> sectionIdByTaskId,
    TaskEntity? existingTask,
    String? initialSectionId,
  }) async {
    final ctrl = tasksController;
    if (ctrl == null) return;

    final titleCtrl = TextEditingController(text: existingTask?.title ?? '');
    final descCtrl =
        TextEditingController(text: existingTask?.description ?? '');
    String priority = existingTask?.priority ?? 'medium';
    String status = existingTask?.status ?? 'not_started';
    String? selectedSectionId = existingTask != null
        ? sectionIdByTaskId[existingTask.id]
        : initialSectionId;
    String? selectedMilestoneId = existingTask?.milestoneId;
    CalendarDate? scheduledDate = existingTask?.scheduledDate;
    CalendarDate? dueDate = existingTask?.dueDate;
    final existingRecurrence = existingTask != null
        ? TaskRecurrenceEngine.resolveEffectiveConfig(existingTask)
        : null;
    bool isRecurring = existingRecurrence != null;
    String recFrequency = existingRecurrence?.frequency ?? 'weekly';
    int recInterval = existingRecurrence?.interval ?? 1;
    List<int> recWeekdays =
        List<int>.from(existingRecurrence?.weekdays ?? const <int>[]);
    CalendarDate? recStartDate = existingRecurrence?.startDate;
    CalendarDate? recEndDate = existingRecurrence?.endDate;
    String recRepeatFrom = existingRecurrence?.repeatFrom ?? 'due_date';
    String? recError;
    String? titleError;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final semantic = ctx.daywellColors;
          return AlertDialog(
            title: Text(existingTask == null ? 'New Project Task' : 'Edit Task'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DaywellTextField(
                    controller: titleCtrl,
                    autofocus: true,
                    isRequired: true,
                    label: 'Task Title',
                    hintText: 'What needs to be done?',
                    errorText: titleError,
                    onChanged: (_) {
                      if (titleError != null) {
                        setDialogState(() => titleError = null);
                      }
                    },
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellTextField(
                    controller: descCtrl,
                    label: 'Description (optional)',
                    hintText: 'Notes or context...',
                    maxLines: 2,
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  Row(
                    children: [
                      Expanded(
                        child: DaywellDropdownField<String>(
                          label: 'Priority',
                          value: priority,
                          items: [
                            for (final p in _priorityOptions)
                              DropdownMenuItem(value: p.$1, child: Text(p.$2)),
                          ],
                          onChanged: (v) {
                            if (v != null) setDialogState(() => priority = v);
                          },
                        ),
                      ),
                      const SizedBox(width: SharedDesignTokens.spacingSm),
                      Expanded(
                        child: DaywellDropdownField<String>(
                          label: 'Status',
                          value: _statusOptions.any((s) => s.$1 == status)
                              ? status
                              : 'not_started',
                          items: [
                            for (final s in _statusOptions)
                              DropdownMenuItem(value: s.$1, child: Text(s.$2)),
                          ],
                          onChanged: (v) {
                            if (v != null) setDialogState(() => status = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (sections.isNotEmpty) ...[
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    DaywellDropdownField<String?>(
                      label: 'Section',
                      value: sections.any((s) => s.id == selectedSectionId)
                          ? selectedSectionId
                          : null,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('General'),
                        ),
                        for (final s in sections)
                          DropdownMenuItem<String?>(
                            value: s.id,
                            child: Text(s.title ?? 'Section'),
                          ),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => selectedSectionId = v),
                    ),
                  ],
                  if (milestones.isNotEmpty) ...[
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    DaywellDropdownField<String?>(
                      label: 'Milestone (optional)',
                      value: milestones.any((m) => m.id == selectedMilestoneId)
                          ? selectedMilestoneId
                          : null,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('No milestone'),
                        ),
                        for (final m in milestones)
                          DropdownMenuItem<String?>(
                            value: m.id,
                            child: Text(m.title),
                          ),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => selectedMilestoneId = v),
                    ),
                  ],
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  Text(
                    'Dates',
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
                        avatar: const Icon(Icons.event_available_outlined, size: 16),
                        label: Text(
                          scheduledDate == null
                              ? 'Schedule'
                              : 'Sched: ${scheduledDate!.toIsoString()}',
                        ),
                        onPressed: () async {
                          final picked = await pickProjectCalendarDate(
                            ctx,
                            initialDate: scheduledDate,
                            helpText: 'Scheduled Date',
                          );
                          if (picked != null && ctx.mounted) {
                            setDialogState(() => scheduledDate = picked);
                          }
                        },
                      ),
                      if (scheduledDate != null)
                        ActionChip(
                          avatar: const Icon(Icons.clear, size: 16),
                          label: const Text('Clear Sched'),
                          onPressed: () =>
                              setDialogState(() => scheduledDate = null),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.edit_calendar_outlined, size: 16),
                        label: Text(
                          dueDate == null
                              ? 'Due Date'
                              : 'Due: ${dueDate!.toIsoString()}',
                        ),
                        onPressed: () async {
                          final picked = await pickProjectCalendarDate(
                            ctx,
                            initialDate: dueDate,
                            helpText: 'Due Date',
                          );
                          if (picked != null && ctx.mounted) {
                            setDialogState(() => dueDate = picked);
                          }
                        },
                      ),
                      if (dueDate != null)
                        ActionChip(
                          avatar: const Icon(Icons.clear, size: 16),
                          label: const Text('Clear Due'),
                          onPressed: () => setDialogState(() => dueDate = null),
                        ),
                    ],
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  TaskRecurrenceEditorSection(
                    isRecurring: isRecurring,
                    onToggleRecurring: (enabled) => setDialogState(() {
                      isRecurring = enabled;
                      recError = null;
                      if (enabled && recStartDate == null) {
                        recStartDate = scheduledDate ?? dueDate;
                      }
                    }),
                    frequency: recFrequency,
                    onFrequencyChanged: (freq) => setDialogState(() {
                      recFrequency = freq;
                      recError = null;
                    }),
                    interval: recInterval,
                    onIntervalChanged: (next) => setDialogState(() {
                      recInterval = next < 1 ? 1 : next;
                      recError = null;
                    }),
                    weekdays: recWeekdays,
                    onWeekdaysChanged: (days) => setDialogState(() {
                      recWeekdays = days;
                      recError = null;
                    }),
                    startDate: recStartDate,
                    onStartDateChanged: (d) => setDialogState(() {
                      recStartDate = d;
                      recError = null;
                    }),
                    endDate: recEndDate,
                    onEndDateChanged: (d) => setDialogState(() {
                      recEndDate = d;
                      recError = null;
                    }),
                    repeatFrom: recRepeatFrom,
                    onRepeatFromChanged: (mode) => setDialogState(() {
                      recRepeatFrom = mode;
                    }),
                    onPickDate: (current) => pickProjectCalendarDate(
                      ctx,
                      initialDate: current,
                      helpText: 'Select Recurrence Date',
                    ),
                    dueDate: dueDate,
                    scheduledDate: scheduledDate,
                    errorText: recError,
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
                      () => titleError = 'Task title is required.',
                    );
                    return;
                  }
                  final trimmedDesc = descCtrl.text.trim();
                  final TaskRecurrenceConfig? recConfig = isRecurring
                      ? TaskRecurrenceConfig(
                          frequency: recFrequency,
                          interval: recInterval,
                          weekdays: recFrequency == 'weekly' &&
                                  recWeekdays.isNotEmpty
                              ? List<int>.unmodifiable(recWeekdays)
                              : null,
                          startDate: recStartDate,
                          endDate: recEndDate,
                          repeatFrom: recRepeatFrom,
                        )
                      : null;
                  if (recConfig != null) {
                    final validation =
                        TaskRecurrenceEngine.validateConfig(recConfig);
                    if (!validation.isValid) {
                      setDialogState(
                        () => recError = validation.errors.values.first,
                      );
                      return;
                    }
                  }

                  if (existingTask == null) {
                    final created = await ctrl.createTask(
                      title: trimmed,
                      description: trimmedDesc.isEmpty ? null : trimmedDesc,
                      priority: priority,
                      status: status,
                      scheduledDate: scheduledDate,
                      dueDate: dueDate,
                      projectId: project.id,
                      milestoneId: selectedMilestoneId,
                      recurrenceRule: recConfig?.frequency,
                      recurrenceConfig: recConfig,
                    );
                    if (created != null) {
                      await projectsController.assignTaskToProjectSection(
                        projectId: project.id,
                        taskId: created.id,
                        taskTitle: created.title,
                        taskCompleted: created.isCompleted,
                        sectionRecordId: selectedSectionId,
                      );
                    }
                  } else {
                    final updateRes = await ctrl.updateTaskWithRecurrence(
                      id: existingTask.id,
                      title: trimmed,
                      description: trimmedDesc.isEmpty ? null : trimmedDesc,
                      clearDescription: trimmedDesc.isEmpty,
                      priority: priority,
                      status: status,
                      scheduledDate: scheduledDate,
                      clearScheduledDate: scheduledDate == null,
                      dueDate: dueDate,
                      clearDueDate: dueDate == null,
                      projectId: project.id,
                      milestoneId: selectedMilestoneId,
                      clearMilestone: selectedMilestoneId == null,
                      recurrenceRule: recConfig?.frequency,
                      clearRecurrenceRule: !isRecurring,
                      recurrenceConfig: recConfig,
                      clearRecurrenceConfig: !isRecurring,
                    );
                    final updated = updateRes.updatedTask;
                    if (updated != null) {
                      await projectsController.assignTaskToProjectSection(
                        projectId: project.id,
                        taskId: updated.id,
                        taskTitle: updated.title,
                        taskCompleted: updated.isCompleted,
                        sectionRecordId: selectedSectionId,
                      );
                    }
                    if (updateRes.generatedNextTask != null) {
                      await projectsController.copyTaskSectionLink(
                        project.id,
                        existingTask.id,
                        updateRes.generatedNextTask!,
                      );
                    }
                    if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                    if (context.mounted &&
                        (updateRes.generatedNextTask != null ||
                            updateRes.seriesEnded)) {
                      final nextDate = updateRes.generatedNextTask?.dueDate ??
                          updateRes.generatedNextTask?.scheduledDate;
                      final msg = updateRes.generatedNextTask != null
                          ? 'Completed "$trimmed" · Next: ${nextDate?.toIsoString() ?? 'scheduled'}'
                          : 'Completed "$trimmed" · Recurrence series ended';
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(msg),
                          action: SnackBarAction(
                            label: 'Undo',
                            onPressed: () => unawaited(() async {
                              if (updateRes.generatedNextTask != null) {
                                await projectsController
                                    .detachTaskFromProjectSections(
                                  project.id,
                                  updateRes.generatedNextTask!.id,
                                );
                              }
                              await ctrl.undoGeneratedRecurrenceCompletion(
                                previousTask: existingTask,
                                generatedNextTaskId:
                                    updateRes.generatedNextTask?.id,
                              );
                              await projectsController.syncTaskSectionLink(
                                project.id,
                                existingTask,
                              );
                            }()),
                          ),
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }
                    return;
                  }
                  if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                },
                child: Text(existingTask == null ? 'Create Task' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openTaskDetailsDialog(
    BuildContext hostContext, {
    required TaskEntity initialTask,
    required List<ProjectTrackingRecordEntity> sections,
    required Map<String, String> sectionIdByTaskId,
    required Map<String, MilestoneEntity> milestonesById,
  }) async {
    final ctrl = tasksController;
    if (ctrl == null) return;

    await showDialog<void>(
      context: hostContext,
      builder: (dialogCtx) => AnimatedBuilder(
        animation: ctrl,
        builder: (animCtx, _) {
          final task = ctrl.state.findTaskById(initialTask.id) ?? initialTask;
          final semantic = animCtx.daywellColors;
          final colorScheme = Theme.of(animCtx).colorScheme;
          final textTheme = Theme.of(animCtx).textTheme;
          final milestone =
              task.milestoneId != null ? milestonesById[task.milestoneId!] : null;

          return AlertDialog(
            title: Text(task.title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: SharedDesignTokens.spacingSm,
                    runSpacing: SharedDesignTokens.spacingXs,
                    children: [
                      DaywellStatusBadge(
                        label: task.isCompleted ? 'Completed' : 'Active',
                        tone: task.isCompleted
                            ? DaywellStatusTone.success
                            : DaywellStatusTone.neutral,
                        showIcon: false,
                      ),
                      DaywellStatusBadge(
                        label: task.priority[0].toUpperCase() +
                            task.priority.substring(1),
                        tone: task.priority == 'urgent'
                            ? DaywellStatusTone.error
                            : task.priority == 'high'
                                ? DaywellStatusTone.warning
                                : DaywellStatusTone.neutral,
                        showIcon: false,
                      ),
                      if (milestone != null)
                        DaywellStatusBadge(
                          label: milestone.title,
                          tone: milestone.isCompleted
                              ? DaywellStatusTone.success
                              : DaywellStatusTone.info,
                          showIcon: false,
                        ),
                    ],
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  if (task.description != null && task.description!.isNotEmpty)
                    Text(
                      task.description!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    )
                  else
                    Text(
                      'No description added.',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellCard(
                    padding: const EdgeInsets.all(
                      SharedDesignTokens.spacingCompact,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scheduled: ${task.scheduledDate != null ? SharedDateFormatter.formatDual(task.scheduledDate!, useAmharic: false) : 'Not set'}',
                          style: textTheme.bodySmall?.copyWith(
                            color: semantic.textPrimary,
                          ),
                        ),
                        const SizedBox(height: SharedDesignTokens.spacingXs),
                        Text(
                          'Due Date: ${task.dueDate != null ? SharedDateFormatter.formatDual(task.dueDate!, useAmharic: false) : 'Not set'}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                          ),
                        ),
                        if (task.subtasks.isNotEmpty) ...[
                          const SizedBox(height: SharedDesignTokens.spacingXs),
                          Text(
                            'Subtasks: ${task.completedSubtaskCount}/${task.totalSubtaskCount}',
                            style: textTheme.bodySmall?.copyWith(
                              color: semantic.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (TaskRecurrenceEngine.resolveEffectiveConfig(task) !=
                      null) ...[
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    TaskRecurrenceDetailsSection(
                      task: task,
                      onSkipOccurrence: () {
                        final prevSnapshot = task;
                        unawaited(() async {
                          final skipped =
                              await ctrl.skipRecurrenceOccurrence(task.id);
                          if (!hostContext.mounted) return;
                          if (skipped == null) {
                            final err = ctrl.state.errorMessage;
                            if (err != null) {
                              ScaffoldMessenger.of(hostContext).showSnackBar(
                                SnackBar(content: Text(err)),
                              );
                            }
                            return;
                          }
                          await projectsController.syncTaskSectionLink(
                            project.id,
                            skipped,
                          );
                          if (!hostContext.mounted) return;
                          final nextDate =
                              skipped.dueDate ?? skipped.scheduledDate;
                          ScaffoldMessenger.of(hostContext).clearSnackBars();
                          ScaffoldMessenger.of(hostContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Skipped to ${nextDate?.toIsoString() ?? 'next occurrence'}',
                              ),
                              action: SnackBarAction(
                                label: 'Undo',
                                onPressed: () => unawaited(() async {
                                  await ctrl.restoreTaskSnapshot(prevSnapshot);
                                  await projectsController.syncTaskSectionLink(
                                    project.id,
                                    prevSnapshot,
                                  );
                                }()),
                              ),
                            ),
                          );
                        }());
                      },
                      onRescheduleOccurrence: () {
                        final prevSnapshot = task;
                        unawaited(() async {
                          final picked = await pickProjectCalendarDate(
                            animCtx,
                            initialDate: task.dueDate ?? task.scheduledDate,
                            helpText: 'Reschedule Occurrence',
                          );
                          if (picked == null) return;
                          final updated = await ctrl.rescheduleTaskOccurrence(
                            task.id,
                            picked,
                          );
                          if (!hostContext.mounted) return;
                          if (updated == null) {
                            final err = ctrl.state.errorMessage;
                            if (err != null) {
                              ScaffoldMessenger.of(hostContext).showSnackBar(
                                SnackBar(content: Text(err)),
                              );
                            }
                            return;
                          }
                          await projectsController.syncTaskSectionLink(
                            project.id,
                            updated,
                          );
                          if (!hostContext.mounted) return;
                          ScaffoldMessenger.of(hostContext).clearSnackBars();
                          ScaffoldMessenger.of(hostContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Rescheduled "${updated.title}" to ${picked.toIsoString()}',
                              ),
                              action: SnackBarAction(
                                label: 'Undo',
                                onPressed: () => unawaited(() async {
                                  await ctrl.restoreTaskSnapshot(prevSnapshot);
                                  await projectsController.syncTaskSectionLink(
                                    project.id,
                                    prevSnapshot,
                                  );
                                }()),
                              ),
                            ),
                          );
                        }());
                      },
                      onEditRecurrence: () {
                        Navigator.of(dialogCtx).pop();
                        if (hostContext.mounted) {
                          unawaited(
                            _openTaskDialog(
                              hostContext,
                              sections: sections,
                              sectionIdByTaskId: sectionIdByTaskId,
                              existingTask: task,
                            ),
                          );
                        }
                      },
                      onStopRecurrence: () {
                        final prevSnapshot = task;
                        unawaited(() async {
                          final stopped =
                              await ctrl.stopTaskRecurrence(task.id);
                          if (!hostContext.mounted) return;
                          if (stopped == null) {
                            final err = ctrl.state.errorMessage;
                            if (err != null) {
                              ScaffoldMessenger.of(hostContext).showSnackBar(
                                SnackBar(content: Text(err)),
                              );
                            }
                            return;
                          }
                          await projectsController.syncTaskSectionLink(
                            project.id,
                            stopped,
                          );
                          if (!hostContext.mounted) return;
                          ScaffoldMessenger.of(hostContext).clearSnackBars();
                          ScaffoldMessenger.of(hostContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Stopped recurrence for "${stopped.title}"',
                              ),
                              action: SnackBarAction(
                                label: 'Undo',
                                onPressed: () => unawaited(() async {
                                  await ctrl.restoreTaskSnapshot(prevSnapshot);
                                  await projectsController.syncTaskSectionLink(
                                    project.id,
                                    prevSnapshot,
                                  );
                                }()),
                              ),
                            ),
                          );
                        }());
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  if (hostContext.mounted) {
                    unawaited(
                      _openTaskDialog(
                        hostContext,
                        sections: sections,
                        sectionIdByTaskId: sectionIdByTaskId,
                        existingTask: task,
                      ),
                    );
                  }
                },
                child: const Text('Edit'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _toggleTask(BuildContext context, TaskEntity task) async {
    final ctrl = tasksController;
    if (ctrl == null) return;
    final wasCompleted = task.isCompleted;
    final previousSnapshot = task;
    final res = await ctrl.toggleTaskWithRecurrence(task.id);
    if (res.updatedTask != null) {
      await projectsController.syncTaskSectionLink(
        project.id,
        res.updatedTask!,
      );
    }
    if (res.generatedNextTask != null) {
      await projectsController.copyTaskSectionLink(
        project.id,
        task.id,
        res.generatedNextTask!,
      );
    }
    if (!context.mounted) return;
    final nextDate =
        res.generatedNextTask?.dueDate ?? res.generatedNextTask?.scheduledDate;
    final message = wasCompleted
        ? 'Reopened "${task.title}"'
        : res.generatedNextTask != null
            ? 'Completed "${task.title}" · Next: ${nextDate?.toIsoString() ?? 'scheduled'}'
            : 'Completed "${task.title}"';
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(() async {
              if (res.generatedNextTask != null) {
                await projectsController.detachTaskFromProjectSections(
                  project.id,
                  res.generatedNextTask!.id,
                );
              }
              await ctrl.undoGeneratedRecurrenceCompletion(
                previousTask: previousSnapshot,
                generatedNextTaskId: res.generatedNextTask?.id,
              );
              await projectsController.syncTaskSectionLink(
                project.id,
                previousSnapshot,
              );
            }());
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _deleteTask(
    BuildContext context,
    TaskEntity task,
    String? previousSectionId,
  ) async {
    final ctrl = tasksController;
    if (ctrl == null) return;
    final confirmed = await DaywellConfirmationDialog.show(
      context,
      title: 'Delete Task?',
      message: 'Delete "${task.title}"? You can undo immediately after deleting.',
      confirmLabel: 'Delete Task',
      isDestructive: true,
      icon: Icons.delete_outline,
    );
    if (!confirmed || !context.mounted) return;

    await projectsController.detachTaskFromProjectSections(project.id, task.id);
    await ctrl.deleteTask(task.id);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted "${task.title}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(() async {
              await ctrl.restoreDeletedTask(task);
              if (previousSectionId != null) {
                await projectsController.assignTaskToProjectSection(
                  projectId: project.id,
                  taskId: task.id,
                  taskTitle: task.title,
                  taskCompleted: task.isCompleted,
                  sectionRecordId: previousSectionId,
                );
              }
            }());
          },
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Widget _buildTaskRow(
    BuildContext context, {
    required TaskEntity task,
    required List<ProjectTrackingRecordEntity> sections,
    required Map<String, String> sectionIdByTaskId,
    required Map<String, MilestoneEntity> milestonesById,
  }) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final currentSectionId = sectionIdByTaskId[task.id];
    final milestone =
        task.milestoneId != null ? milestonesById[task.milestoneId!] : null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: SharedDesignTokens.spacingXs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: task.isCompleted,
            onChanged: tasksController == null
                ? null
                : (_) => _toggleTask(context, task),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
              onTap: tasksController == null
                  ? null
                  : () => _openTaskDetailsDialog(
                        context,
                        initialTask: task,
                        sections: sections,
                        sectionIdByTaskId: sectionIdByTaskId,
                        milestonesById: milestonesById,
                      ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration:
                          task.isCompleted ? TextDecoration.lineThrough : null,
                      color: task.isCompleted
                          ? semantic.textMuted
                          : semantic.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: SharedDesignTokens.spacingSm,
                    runSpacing: 2,
                    children: [
                      Text(
                        task.priority[0].toUpperCase() +
                            task.priority.substring(1),
                        style: textTheme.bodySmall?.copyWith(
                          color: task.priority == 'urgent'
                              ? semantic.error
                              : task.priority == 'high'
                                  ? semantic.warning
                                  : semantic.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (milestone != null)
                        Text(
                          'Milestone: ${milestone.title}',
                          style: textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      if (task.dueDate != null)
                        Text(
                          'Due ${SharedDateFormatter.formatDual(task.dueDate!, useAmharic: false)}',
                          style: textTheme.bodySmall?.copyWith(
                            color: semantic.textMuted,
                          ),
                        ),
                      if (TaskRecurrenceEngine.resolveEffectiveConfig(task) !=
                          null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.repeat,
                              size: 12,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              TaskRecurrenceEngine.formatSummary(
                                TaskRecurrenceEngine.resolveEffectiveConfig(
                                  task,
                                ),
                              ),
                              style: textTheme.bodySmall?.copyWith(
                                color: semantic.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      if (task.subtasks.isNotEmpty)
                        Text(
                          '${task.completedSubtaskCount}/${task.totalSubtaskCount} subtasks',
                          style: textTheme.bodySmall?.copyWith(
                            color: semantic.textMuted,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (sections.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.drive_file_move_outline, size: 18),
              tooltip: 'Move to section',
              onSelected: (value) {
                unawaited(
                  projectsController.assignTaskToProjectSection(
                    projectId: project.id,
                    taskId: task.id,
                    taskTitle: task.title,
                    taskCompleted: task.isCompleted,
                    sectionRecordId: value == '__general__' ? null : value,
                  ),
                );
              },
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  value: '__general__',
                  child: Row(
                    children: [
                      if (currentSectionId == null)
                        const Icon(Icons.check, size: 16)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 8),
                      const Text('General'),
                    ],
                  ),
                ),
                for (final sec in sections)
                  PopupMenuItem<String>(
                    value: sec.id,
                    child: Row(
                      children: [
                        if (currentSectionId == sec.id)
                          const Icon(Icons.check, size: 16)
                        else
                          const SizedBox(width: 16),
                        const SizedBox(width: 8),
                        Text(sec.title ?? 'Section'),
                      ],
                    ),
                  ),
              ],
            ),
          if (tasksController != null) ...[
            DaywellIconButton(
              icon: Icons.edit_outlined,
              tooltip: 'Edit task ${task.title}',
              onPressed: () => _openTaskDialog(
                context,
                sections: sections,
                sectionIdByTaskId: sectionIdByTaskId,
                existingTask: task,
              ),
            ),
            DaywellIconButton(
              icon: Icons.delete_outline,
              tooltip: 'Delete task ${task.title}',
              isDestructive: true,
              onPressed: () =>
                  _deleteTask(context, task, currentSectionId),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final layout = _computeSectionLayout();
    final milestonesById = {for (final m in milestones) m.id: m};
    final completedTasks = tasks.where((t) => t.isCompleted).length;

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: SharedDesignTokens.spacingSm,
            runSpacing: SharedDesignTokens.spacingXs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                Icons.checklist_outlined,
                size: DaywellIconSize.sm,
                color: semantic.textSecondary,
              ),
              Text(
                'Tasks & Sections',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$completedTasks/${tasks.length} done',
                style: DaywellTypography.numericBody(
                  color: semantic.textSecondary,
                ),
              ),
              DaywellButton(
                label: 'Section',
                variant: DaywellButtonVariant.outlined,
                size: DaywellButtonSize.compact,
                leadingIcon: Icons.create_new_folder_outlined,
                onPressed: () => _openSectionDialog(context),
              ),
              if (tasksController != null)
                DaywellButton(
                  label: 'Task',
                  variant: DaywellButtonVariant.primary,
                  size: DaywellButtonSize.compact,
                  leadingIcon: Icons.add,
                  onPressed: () => _openTaskDialog(
                    context,
                    sections: layout.sections,
                    sectionIdByTaskId: layout.sectionIdByTaskId,
                  ),
                ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          for (final section in layout.sections) ...[
            Builder(
              builder: (ctx) {
                final secTasks =
                    layout.tasksBySectionId[section.id] ?? const <TaskEntity>[];
                return Padding(
                  padding: const EdgeInsets.only(
                    bottom: SharedDesignTokens.spacingCompact,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${section.title ?? 'Section'} (${secTasks.length})',
                              style: textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: semantic.textPrimary,
                              ),
                            ),
                          ),
                          if (tasksController != null)
                            DaywellIconButton(
                              icon: Icons.add_task_outlined,
                              tooltip:
                                  'Add task to ${section.title ?? 'Section'}',
                              onPressed: () => _openTaskDialog(
                                context,
                                sections: layout.sections,
                                sectionIdByTaskId: layout.sectionIdByTaskId,
                                initialSectionId: section.id,
                              ),
                            ),
                          DaywellIconButton(
                            icon: Icons.edit_outlined,
                            tooltip:
                                'Rename section ${section.title ?? 'Section'}',
                            onPressed: () => _openSectionDialog(
                              context,
                              existing: section,
                            ),
                          ),
                          DaywellIconButton(
                            icon: Icons.delete_outline,
                            tooltip:
                                'Delete section ${section.title ?? 'Section'}',
                            isDestructive: true,
                            onPressed: () => _deleteSection(context, section),
                          ),
                        ],
                      ),
                      const Divider(height: 1),
                      if (secTasks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: SharedDesignTokens.spacingSm,
                          ),
                          child: Text(
                            'No tasks in this section yet.',
                            style: textTheme.bodySmall?.copyWith(
                              color: semantic.textMuted,
                            ),
                          ),
                        )
                      else
                        for (final task in secTasks)
                          _buildTaskRow(
                            context,
                            task: task,
                            sections: layout.sections,
                            sectionIdByTaskId: layout.sectionIdByTaskId,
                            milestonesById: milestonesById,
                          ),
                    ],
                  ),
                );
              },
            ),
          ],
          if (layout.sections.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'General (${layout.unsectionedTasks.length})',
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: semantic.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
          ],
          if (layout.unsectionedTasks.isEmpty && layout.sections.isEmpty)
            Text(
              tasksController == null
                  ? 'Tasks appear here once TasksController is connected.'
                  : 'No tasks linked to this project yet. Add a Task or create Sections to organize work.',
              style: textTheme.bodySmall?.copyWith(color: semantic.textMuted),
            )
          else if (layout.unsectionedTasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: SharedDesignTokens.spacingSm,
              ),
              child: Text(
                'All project tasks are assigned to sections.',
                style: textTheme.bodySmall?.copyWith(color: semantic.textMuted),
              ),
            )
          else
            for (final task in layout.unsectionedTasks)
              _buildTaskRow(
                context,
                task: task,
                sections: layout.sections,
                sectionIdByTaskId: layout.sectionIdByTaskId,
                milestonesById: milestonesById,
              ),
        ],
      ),
    );
  }
}
