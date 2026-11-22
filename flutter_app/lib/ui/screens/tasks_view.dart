import 'dart:async';
import 'package:flutter/material.dart';
import '../../application/inbox/inbox_controller.dart';
import '../../application/projects/projects_controller.dart';
import '../../application/projects/projects_state.dart';
import '../../application/tasks/tasks_controller.dart';
import '../../application/tasks/tasks_state.dart';
import '../../core/date/shared_date.dart';
import '../../core/shared_foundation.dart';
import '../../core/theme/daywell_theme.dart';
import '../../domain/inbox/inbox_models.dart';
import '../../domain/projects/project_models.dart';
import '../../domain/tasks/daily_planning_engine.dart';
import '../../domain/tasks/task_models.dart';
import '../../domain/tasks/task_recurrence_engine.dart';
import '../app_state.dart';
import '../widgets/shared_ui_widgets.dart';
import 'projects/project_form_sheet.dart';
import 'projects/projects_workspace_tab.dart';
import 'tasks/my_day_planning_view.dart';
import 'tasks/task_recurrence_widgets.dart';

class TasksView extends StatefulWidget {
  final AppStateManager? state;
  final TasksController? controller;
  final ProjectsController? projectsController;
  final InboxController? inboxController;

  const TasksView({
    super.key,
    this.state,
    this.controller,
    this.projectsController,
    this.inboxController,
  }) : assert(
          state != null || controller != null,
          'Either state or controller must be provided to TasksView',
        );

  TasksController get effectiveController =>
      controller ?? state!.tasksController;

  ProjectsController? get effectiveProjectsController =>
      projectsController ?? state?.projectsController;

  InboxController? get effectiveInboxController =>
      inboxController ?? state?.inboxController;

  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _searchController;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    final ctrl = widget.effectiveController;
    _searchController = TextEditingController(
      text: ctrl.state.searchQuery,
    );
    ctrl.addListener(_syncSearchControllerWithState);
  }

  @override
  void didUpdateWidget(covariant TasksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effectiveController != widget.effectiveController) {
      oldWidget.effectiveController.removeListener(_syncSearchControllerWithState);
      widget.effectiveController.addListener(_syncSearchControllerWithState);
      _syncSearchControllerWithState();
    }
  }

  void _syncSearchControllerWithState() {
    final nextQuery = widget.effectiveController.state.searchQuery;
    if (_searchController.text != nextQuery) {
      _searchController.value = TextEditingValue(
        text: nextQuery,
        selection: TextSelection.collapsed(offset: nextQuery.length),
      );
    }
  }

  @override
  void dispose() {
    widget.effectiveController.removeListener(_syncSearchControllerWithState);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  static const List<(String, String)> _statusOptions = [
    ('inbox', 'Inbox'),
    ('not_started', 'Not Started'),
    ('in_progress', 'In Progress'),
    ('completed', 'Completed'),
    ('cancelled', 'Cancelled'),
  ];

  static const List<(String, String)> _priorityOptions = [
    ('urgent', 'Urgent'),
    ('high', 'High'),
    ('medium', 'Medium'),
    ('low', 'Low'),
  ];

  static const List<(String, String)> _dueDateFilterOptions = [
    ('overdue', 'Overdue'),
    ('today', 'Due Today'),
    ('upcoming', 'Upcoming Due'),
    ('no_due_date', 'No Due Date'),
  ];

  String _statusLabel(String status) {
    for (final item in _statusOptions) {
      if (item.$1 == status) return item.$2;
    }
    return 'Not Started';
  }

  String _priorityLabel(String priority) {
    for (final item in _priorityOptions) {
      if (item.$1 == priority) return item.$2;
    }
    return 'Medium';
  }

  DaywellStatusTone _statusTone(String status) {
    switch (status) {
      case 'completed':
        return DaywellStatusTone.success;
      case 'in_progress':
        return DaywellStatusTone.info;
      case 'cancelled':
        return DaywellStatusTone.error;
      default:
        return DaywellStatusTone.info;
    }
  }

  DaywellStatusTone _priorityTone(String priority) {
    switch (priority) {
      case 'urgent':
        return DaywellStatusTone.error;
      case 'high':
        return DaywellStatusTone.warning;
      default:
        return DaywellStatusTone.info;
    }
  }

  Future<void> _toggleCompleteWithUndo(
    TaskEntity task,
    TasksController controller,
  ) async {
    final wasCompleted = task.isCompleted;
    final previousSnapshot = task;
    final projectsCtrl = widget.effectiveProjectsController;
    final res = await controller.toggleTaskWithRecurrence(task.id);
    if (res.updatedTask != null &&
        projectsCtrl != null &&
        res.updatedTask!.projectId != null) {
      await projectsCtrl.syncTaskSectionLink(
        res.updatedTask!.projectId!,
        res.updatedTask!,
      );
    }
    if (res.generatedNextTask != null &&
        projectsCtrl != null &&
        res.generatedNextTask!.projectId != null) {
      await projectsCtrl.copyTaskSectionLink(
        res.generatedNextTask!.projectId!,
        task.id,
        res.generatedNextTask!,
      );
    }
    if (!mounted) return;
    final nextDate =
        res.generatedNextTask?.dueDate ?? res.generatedNextTask?.scheduledDate;
    final message = wasCompleted
        ? 'Reopened "${task.title}"'
        : res.generatedNextTask != null
            ? 'Completed "${task.title}" · Next: ${nextDate?.toIsoString() ?? 'scheduled'}'
            : res.seriesEnded
                ? 'Completed "${task.title}" · Series ended'
                : 'Completed "${task.title}"';
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(() async {
              if (res.generatedNextTask != null &&
                  projectsCtrl != null &&
                  res.generatedNextTask!.projectId != null) {
                await projectsCtrl.detachTaskFromProjectSections(
                  res.generatedNextTask!.projectId!,
                  res.generatedNextTask!.id,
                );
              }
              await controller.undoGeneratedRecurrenceCompletion(
                previousTask: previousSnapshot,
                generatedNextTaskId: res.generatedNextTask?.id,
              );
              if (projectsCtrl != null && previousSnapshot.projectId != null) {
                await projectsCtrl.syncTaskSectionLink(
                  previousSnapshot.projectId!,
                  previousSnapshot,
                );
              }
            }());
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _toggleArchiveWithUndo(TaskEntity task, TasksController controller) {
    final willArchive = !task.isArchived;
    unawaited(
      willArchive
          ? controller.archiveTask(task.id)
          : controller.restoreTask(task.id),
    );
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          willArchive
              ? 'Archived "${task.title}"'
              : 'Restored "${task.title}"',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => unawaited(
            willArchive
                ? controller.restoreTask(task.id)
                : controller.archiveTask(task.id),
          ),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _removeTaskFromDayWithUndo(
    TaskEntity task,
    TasksController controller,
    CalendarDate planDate,
  ) async {
    await controller.removeTaskFromPlannedDay(task.id, date: planDate);
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Removed "${task.title}" from My Day (${planDate.toIsoString()})',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => unawaited(
            controller.planTaskForDate(task.id, date: planDate),
          ),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<bool> _confirmAndDeleteTask(
    TaskEntity task,
    TasksController controller,
  ) async {
    final confirmed = await DaywellConfirmationDialog.show(
      context,
      title: 'Delete task?',
      message:
          'Delete "${task.title}"? You can undo immediately after deleting.',
      confirmLabel: 'Delete Task',
      cancelLabel: 'Cancel',
      isDestructive: true,
      icon: Icons.delete_outline,
    );
    if (!confirmed || !mounted) return false;
    final previousPlanningEntries = controller.state.dailyPlanningEntries
        .where((e) => e.taskId == task.id)
        .toList(growable: false);
    final projectsCtrl = widget.effectiveProjectsController;
    String? previousSectionId;
    if (projectsCtrl != null && task.projectId != null) {
      previousSectionId = await projectsCtrl.detachTaskFromProjectSections(
        task.projectId!,
        task.id,
      );
    }
    await controller.deleteTask(task.id);
    if (!mounted) return true;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted "${task.title}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(() async {
              await controller.restoreDeletedTask(
                task,
                restorePlanningEntries: previousPlanningEntries,
              );
              if (projectsCtrl != null &&
                  task.projectId != null &&
                  previousSectionId != null) {
                await projectsCtrl.assignTaskToProjectSection(
                  projectId: task.projectId!,
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
    return true;
  }

  Future<CalendarDate?> _pickCalendarDate(CalendarDate? current) async {
    final initial = current ?? CalendarDate.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked == null) return null;
    return CalendarDate(
      year: picked.year,
      month: picked.month,
      day: picked.day,
    );
  }

  void _showQuickAddModal() => _showTaskFormModal();

  void _showTaskFormModal({
    TaskEntity? existingTask,
    InboxItemEntity? sourceInboxItem,
  }) {
    final controller = widget.effectiveController;
    final isEditing = existingTask != null;
    final isConvertingInbox = sourceInboxItem != null && !isEditing;
    final InboxTaskDraft? inboxDraft =
        isConvertingInbox ? sourceInboxItem.toTaskDraft() : null;
    final titleCtrl = TextEditingController(
      text: existingTask?.title ?? inboxDraft?.title ?? '',
    );
    final descCtrl = TextEditingController(
      text: existingTask?.description ?? inboxDraft?.description ?? '',
    );
    String priority = existingTask?.priority ?? 'medium';
    String status = existingTask?.status ??
        (isConvertingInbox
            ? 'not_started'
            : (controller.state.viewFilter == 'inbox'
                ? 'inbox'
                : 'not_started'));
    String? selectedProjectId = existingTask?.projectId;
    String? selectedMilestoneId = existingTask?.milestoneId;
    CalendarDate? scheduledDate = existingTask != null
        ? existingTask.scheduledDate
        : (isConvertingInbox
            ? null
            : (controller.state.viewFilter == 'today'
                ? CalendarDate.today()
                : null));
    CalendarDate? dueDate = existingTask != null
        ? existingTask.dueDate
        : (isConvertingInbox
            ? null
            : (controller.state.viewFilter == 'today'
                ? CalendarDate.today()
                : null));
    String? titleError;
    final sourceProjects =
        widget.effectiveProjectsController?.state.projects ??
            controller.state.projects;
    final projects = sourceProjects
        .where((p) => !p.isArchived || p.id == selectedProjectId)
        .toList(growable: false);
    var modalLabels = TasksModuleState.normalizeLabels([
      ...(existingTask?.labels ?? controller.state.tagFilters),
      ...(inboxDraft?.initialLabels ?? const <String>[]),
    ]).toList();
    final modalTagAddCtrl = TextEditingController();
    String? modalTagError;
    var modalSubtasks = List<TaskSubtask>.from(existingTask?.subtasks ?? const []);
    final modalSubtaskAddCtrl = TextEditingController();
    final modalSubtaskEditCtrl = TextEditingController();
    String? modalSubtaskAddError;
    String? editingModalSubtaskId;
    String? modalSubtaskEditError;
    final existingRecurrence = existingTask != null
        ? TaskRecurrenceEngine.resolveEffectiveConfig(existingTask)
        : null;
    bool modalIsRecurring = existingRecurrence != null;
    String modalRecFrequency = existingRecurrence?.frequency ?? 'weekly';
    int modalRecInterval = existingRecurrence?.interval ?? 1;
    List<int> modalRecWeekdays =
        List<int>.from(existingRecurrence?.weekdays ?? const <int>[]);
    CalendarDate? modalRecStartDate = existingRecurrence?.startDate;
    CalendarDate? modalRecEndDate = existingRecurrence?.endDate;
    String modalRecRepeatFrom =
        existingRecurrence?.repeatFrom ?? 'due_date';
    String? modalRecError;

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SharedDesignTokens.radiusSheet),
          ),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (modalContext, setModalState) {
            final semantic = modalContext.daywellColors;
            return Padding(
              padding: EdgeInsets.only(
                top: SharedDesignTokens.spacingMd,
                left: SharedDesignTokens.spacingMd,
                right: SharedDesignTokens.spacingMd,
                bottom: MediaQuery.of(modalContext).viewInsets.bottom +
                    SharedDesignTokens.spacingMd,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEditing
                          ? 'Edit Task'
                          : isConvertingInbox
                              ? 'Convert Inbox Item to Task'
                              : 'New Task',
                      style: Theme.of(modalContext).textTheme.titleLarge,
                    ),
                    if (isConvertingInbox) ...[
                      const SizedBox(height: SharedDesignTokens.spacingSm),
                      DaywellStatusBanner(
                        tone: DaywellStatusTone.info,
                        title:
                            'From Quick Capture (${sourceInboxItem.category.toUpperCase()})',
                        message:
                            'Adjust details, project, tags, or schedule below. Saving converts this item into a Task and marks it processed in Inbox.',
                      ),
                    ],
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    DaywellTextField(
                      controller: titleCtrl,
                      autofocus: true,
                      isRequired: true,
                      label: 'Task Title',
                      hintText: 'e.g. Submit monthly report',
                      errorText: titleError,
                      onChanged: (_) {
                        if (titleError != null) {
                          setModalState(() => titleError = null);
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
                                DropdownMenuItem(
                                  value: p.$1,
                                  child: Text(p.$2),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setModalState(() => priority = v);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: SharedDesignTokens.spacingSm),
                        Expanded(
                          child: DaywellDropdownField<String>(
                            label: 'Status',
                            value: status,
                            items: [
                              for (final s in _statusOptions)
                                DropdownMenuItem(
                                  value: s.$1,
                                  child: Text(s.$2),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setModalState(() => status = v);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    if (projects.isNotEmpty) ...[
                      const SizedBox(height: SharedDesignTokens.spacingCompact),
                      DaywellDropdownField<String?>(
                        label: 'Project (Inbox if none)',
                        value: projects.any((p) => p.id == selectedProjectId)
                            ? selectedProjectId
                            : null,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Inbox'),
                          ),
                          ...projects.map(
                            (p) => DropdownMenuItem<String?>(
                              value: p.id,
                              child: Text(p.title),
                            ),
                          ),
                        ],
                        onChanged: (v) => setModalState(() {
                          selectedProjectId = v;
                          selectedMilestoneId = null;
                        }),
                      ),
                      Builder(
                        builder: (_) {
                          final projectMilestones = selectedProjectId == null
                              ? const <MilestoneEntity>[]
                              : controller.state.milestones
                                  .where((m) => m.projectId == selectedProjectId)
                                  .toList(growable: false);
                          if (projectMilestones.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          final validMilestoneId = projectMilestones
                                  .any((m) => m.id == selectedMilestoneId)
                              ? selectedMilestoneId
                              : null;
                          return Padding(
                            padding: const EdgeInsets.only(
                              top: SharedDesignTokens.spacingCompact,
                            ),
                            child: DaywellDropdownField<String?>(
                              label: 'Milestone (optional)',
                              value: validMilestoneId,
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('No milestone'),
                                ),
                                ...projectMilestones.map(
                                  (m) => DropdownMenuItem<String?>(
                                    value: m.id,
                                    child: Text(m.title),
                                  ),
                                ),
                              ],
                              onChanged: (v) =>
                                  setModalState(() => selectedMilestoneId = v),
                            ),
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    Text(
                      'Scheduled Date',
                      style: Theme.of(modalContext).textTheme.labelMedium?.copyWith(
                            color: semantic.textSecondary,
                          ),
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    Wrap(
                      spacing: SharedDesignTokens.spacingSm,
                      runSpacing: SharedDesignTokens.spacingXs,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.today, size: 16),
                          label: const Text('Today'),
                          onPressed: () => setModalState(
                            () => scheduledDate = CalendarDate.today(),
                          ),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.wb_sunny_outlined, size: 16),
                          label: const Text('Tomorrow'),
                          onPressed: () => setModalState(
                            () => scheduledDate =
                                CalendarDate.today().addDays(1),
                          ),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.edit_calendar, size: 16),
                          label: const Text('Pick Date'),
                          onPressed: () async {
                            final picked =
                                await _pickCalendarDate(scheduledDate);
                            if (picked != null && ctx.mounted) {
                              setModalState(() => scheduledDate = picked);
                            }
                          },
                        ),
                        if (scheduledDate != null)
                          ActionChip(
                            avatar: const Icon(Icons.clear, size: 16),
                            label: const Text('Clear Scheduled'),
                            onPressed: () =>
                                setModalState(() => scheduledDate = null),
                          ),
                      ],
                    ),
                    if (scheduledDate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Scheduled: ${SharedDateFormatter.formatDual(scheduledDate!, useAmharic: false)}',
                          style: DaywellTypography.label(
                            color: semantic.textSecondary,
                          ),
                        ),
                      ),
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    Text(
                      'Due Date',
                      style: Theme.of(modalContext).textTheme.labelMedium?.copyWith(
                            color: semantic.textSecondary,
                          ),
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    Wrap(
                      spacing: SharedDesignTokens.spacingSm,
                      runSpacing: SharedDesignTokens.spacingXs,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.today, size: 16),
                          label: const Text('Today'),
                          onPressed: () => setModalState(
                            () => dueDate = CalendarDate.today(),
                          ),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.wb_sunny_outlined, size: 16),
                          label: const Text('Tomorrow'),
                          onPressed: () => setModalState(
                            () => dueDate = CalendarDate.today().addDays(1),
                          ),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.date_range, size: 16),
                          label: const Text('Next Week'),
                          onPressed: () => setModalState(
                            () => dueDate = CalendarDate.today().addDays(7),
                          ),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.edit_calendar, size: 16),
                          label: const Text('Pick Date'),
                          onPressed: () async {
                            final picked = await _pickCalendarDate(dueDate);
                            if (picked != null && ctx.mounted) {
                              setModalState(() => dueDate = picked);
                            }
                          },
                        ),
                        if (dueDate != null)
                          ActionChip(
                            avatar: const Icon(Icons.clear, size: 16),
                            label: const Text('Clear Due'),
                            onPressed: () => setModalState(() => dueDate = null),
                          ),
                      ],
                    ),
                    if (dueDate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Due: ${SharedDateFormatter.formatDual(dueDate!, useAmharic: false)}',
                          style: DaywellTypography.label(
                            color: Theme.of(modalContext).colorScheme.primary,
                          ),
                        ),
                      ),
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    TaskRecurrenceEditorSection(
                      isRecurring: modalIsRecurring,
                      onToggleRecurring: (val) => setModalState(() {
                        modalIsRecurring = val;
                        modalRecError = null;
                      }),
                      frequency: modalRecFrequency,
                      onFrequencyChanged: (val) => setModalState(() {
                        modalRecFrequency = val;
                        modalRecError = null;
                      }),
                      interval: modalRecInterval,
                      onIntervalChanged: (val) => setModalState(() {
                        modalRecInterval = val;
                        modalRecError = null;
                      }),
                      weekdays: modalRecWeekdays,
                      onWeekdaysChanged: (val) => setModalState(() {
                        modalRecWeekdays = val;
                        modalRecError = null;
                      }),
                      startDate: modalRecStartDate,
                      onStartDateChanged: (val) => setModalState(() {
                        modalRecStartDate = val;
                        modalRecError = null;
                      }),
                      endDate: modalRecEndDate,
                      onEndDateChanged: (val) => setModalState(() {
                        modalRecEndDate = val;
                        modalRecError = null;
                      }),
                      repeatFrom: modalRecRepeatFrom,
                      onRepeatFromChanged: (val) => setModalState(() {
                        modalRecRepeatFrom = val;
                        modalRecError = null;
                      }),
                      onPickDate: _pickCalendarDate,
                      dueDate: dueDate,
                      scheduledDate: scheduledDate,
                      errorText: modalRecError,
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    DaywellCard(
                      padding: const EdgeInsets.all(
                        SharedDesignTokens.spacingCompact,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Tags / Labels',
                                style: Theme.of(modalContext)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: semantic.textPrimary,
                                    ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _showManageTagsDialog(controller),
                                child: const Text('Manage tags'),
                              ),
                            ],
                          ),
                          if (modalLabels.isNotEmpty) ...[
                            const SizedBox(height: SharedDesignTokens.spacingXs),
                            Wrap(
                              spacing: SharedDesignTokens.spacingXs,
                              runSpacing: SharedDesignTokens.spacingXs,
                              children: [
                                for (final lbl in modalLabels)
                                  InputChip(
                                    label: Text('@$lbl'),
                                    onDeleted: () => setModalState(() {
                                      modalLabels = modalLabels
                                          .where(
                                            (l) =>
                                                l.toLowerCase() !=
                                                lbl.toLowerCase(),
                                          )
                                          .toList();
                                    }),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: SharedDesignTokens.spacingSm),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: modalTagAddCtrl,
                                  decoration: InputDecoration(
                                    hintText: 'Add a tag (e.g. work)...',
                                    errorText: modalTagError,
                                    isDense: true,
                                  ),
                                  onChanged: (_) {
                                    if (modalTagError != null) {
                                      setModalState(() => modalTagError = null);
                                    }
                                  },
                                  onSubmitted: (raw) {
                                    final normalized =
                                        TasksModuleState.normalizeLabel(raw);
                                    if (normalized.isEmpty) {
                                      setModalState(
                                        () => modalTagError =
                                            'Tag name is required',
                                      );
                                      return;
                                    }
                                    setModalState(() {
                                      modalLabels =
                                          TasksModuleState.normalizeLabels([
                                        ...modalLabels,
                                        normalized,
                                      ]).toList();
                                      modalTagAddCtrl.clear();
                                      modalTagError = null;
                                    });
                                  },
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add),
                                tooltip: 'Add tag',
                                onPressed: () {
                                  final normalized =
                                      TasksModuleState.normalizeLabel(
                                    modalTagAddCtrl.text,
                                  );
                                  if (normalized.isEmpty) {
                                    setModalState(
                                      () => modalTagError =
                                          'Tag name is required',
                                    );
                                    return;
                                  }
                                  setModalState(() {
                                    modalLabels =
                                        TasksModuleState.normalizeLabels([
                                      ...modalLabels,
                                      normalized,
                                    ]).toList();
                                    modalTagAddCtrl.clear();
                                    modalTagError = null;
                                  });
                                },
                              ),
                            ],
                          ),
                          if (controller.state.availableTags.any(
                            (tag) => !modalLabels.any(
                              (cur) => cur.toLowerCase() == tag.toLowerCase(),
                            ),
                          )) ...[
                            const SizedBox(height: SharedDesignTokens.spacingXs),
                            Wrap(
                              spacing: SharedDesignTokens.spacingXs,
                              runSpacing: SharedDesignTokens.spacingXs,
                              children: [
                                for (final tag in controller.state.availableTags)
                                  if (!modalLabels.any(
                                    (cur) =>
                                        cur.toLowerCase() == tag.toLowerCase(),
                                  ))
                                    ActionChip(
                                      label: Text('+ @$tag'),
                                      onPressed: () => setModalState(() {
                                        modalLabels =
                                            TasksModuleState.normalizeLabels([
                                          ...modalLabels,
                                          tag,
                                        ]).toList();
                                      }),
                                    ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    _SubtasksChecklistSection(
                      subtasks: modalSubtasks,
                      progress: modalSubtasks.isEmpty
                          ? 0.0
                          : modalSubtasks.where((s) => s.done).length /
                              modalSubtasks.length,
                      completedCount:
                          modalSubtasks.where((s) => s.done).length,
                      addController: modalSubtaskAddCtrl,
                      addErrorText: modalSubtaskAddError,
                      editingSubtaskId: editingModalSubtaskId,
                      editController: modalSubtaskEditCtrl,
                      editErrorText: modalSubtaskEditError,
                      onAdd: () {
                        final txt = modalSubtaskAddCtrl.text.trim();
                        if (txt.isEmpty) {
                          setModalState(
                            () => modalSubtaskAddError =
                                'Subtask title is required',
                          );
                          return;
                        }
                        setModalState(() {
                          final prefixId = existingTask?.id ?? 'draft';
                          modalSubtasks = [
                            ...modalSubtasks,
                            TaskSubtask(
                              id: TaskSubtask.nextId(prefixId, modalSubtasks),
                              title: txt,
                              done: false,
                            ),
                          ];
                          modalSubtaskAddCtrl.clear();
                          modalSubtaskAddError = null;
                        });
                      },
                      onAddTextChanged: () {
                        if (modalSubtaskAddError != null) {
                          setModalState(() => modalSubtaskAddError = null);
                        }
                      },
                      onToggle: (index, done) {
                        setModalState(() {
                          final copy = List<TaskSubtask>.from(modalSubtasks);
                          copy[index] = copy[index].copyWith(done: done);
                          modalSubtasks = copy;
                        });
                      },
                      onMove: (fromIdx, toIdx) {
                        setModalState(() {
                          modalSubtasks = TaskSubtask.reorderList(
                            modalSubtasks,
                            fromIdx,
                            toIdx,
                          );
                        });
                      },
                      onStartEdit: (item) {
                        setModalState(() {
                          editingModalSubtaskId = item.id;
                          modalSubtaskEditCtrl.text = item.title;
                          modalSubtaskEditError = null;
                        });
                      },
                      onSaveEdit: (subtaskId) {
                        final trimmed = modalSubtaskEditCtrl.text.trim();
                        if (trimmed.isEmpty) {
                          setModalState(
                            () => modalSubtaskEditError =
                                'Subtask title is required',
                          );
                          return;
                        }
                        setModalState(() {
                          modalSubtasks = [
                            for (final item in modalSubtasks)
                              if (item.id == subtaskId)
                                item.copyWith(title: trimmed)
                              else
                                item,
                          ];
                          editingModalSubtaskId = null;
                          modalSubtaskEditCtrl.clear();
                          modalSubtaskEditError = null;
                        });
                      },
                      onCancelEdit: () {
                        setModalState(() {
                          editingModalSubtaskId = null;
                          modalSubtaskEditCtrl.clear();
                          modalSubtaskEditError = null;
                        });
                      },
                      onEditTextChanged: () {
                        if (modalSubtaskEditError != null) {
                          setModalState(() => modalSubtaskEditError = null);
                        }
                      },
                      onDelete: (subtaskId) {
                        setModalState(() {
                          modalSubtasks = modalSubtasks
                              .where((s) => s.id != subtaskId)
                              .toList();
                          if (editingModalSubtaskId == subtaskId) {
                            editingModalSubtaskId = null;
                            modalSubtaskEditCtrl.clear();
                            modalSubtaskEditError = null;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingMd),
                    DaywellButton(
                      label: isEditing
                          ? 'Save Changes'
                          : isConvertingInbox
                              ? 'Convert to Task'
                              : 'Save Task',
                      leadingIcon: Icons.check,
                      fullWidth: true,
                      onPressed: () async {
                        final title = titleCtrl.text.trim();
                        if (title.isEmpty) {
                          setModalState(
                            () => titleError = 'Task title is required',
                          );
                          return;
                        }
                        final desc = descCtrl.text.trim();
                        final TaskRecurrenceConfig? recConfig = modalIsRecurring
                            ? TaskRecurrenceConfig(
                                frequency: modalRecFrequency,
                                interval: modalRecInterval,
                                weekdays: modalRecFrequency == 'weekly' &&
                                        modalRecWeekdays.isNotEmpty
                                    ? List<int>.unmodifiable(modalRecWeekdays)
                                    : null,
                                startDate: modalRecStartDate,
                                endDate: modalRecEndDate,
                                repeatFrom: modalRecRepeatFrom,
                              )
                            : null;
                        if (recConfig != null) {
                          final recValidation =
                              TaskRecurrenceEngine.validateConfig(recConfig);
                          if (!recValidation.isValid) {
                            setModalState(
                              () => modalRecError =
                                  recValidation.errors.values.first,
                            );
                            return;
                          }
                        }
                        final resolvedMilestoneId =
                            selectedProjectId != null ? selectedMilestoneId : null;
                        final projectsCtrl = widget.effectiveProjectsController;
                        if (isEditing) {
                          final updateRes =
                              await controller.updateTaskWithRecurrence(
                            id: existingTask.id,
                            title: title,
                            description: desc.isEmpty ? null : desc,
                            clearDescription: desc.isEmpty,
                            priority: priority,
                            status: status,
                            dueDate: dueDate,
                            clearDueDate: dueDate == null,
                            scheduledDate: scheduledDate,
                            clearScheduledDate: scheduledDate == null,
                            projectId: selectedProjectId,
                            clearProject: selectedProjectId == null,
                            milestoneId: resolvedMilestoneId,
                            clearMilestone: resolvedMilestoneId == null,
                            subtasks: modalSubtasks,
                            labels: modalLabels,
                            recurrenceRule: recConfig?.frequency,
                            clearRecurrenceRule: !modalIsRecurring,
                            recurrenceConfig: recConfig,
                            clearRecurrenceConfig: !modalIsRecurring,
                          );
                          final updated = updateRes.updatedTask;
                          if (projectsCtrl != null &&
                              existingTask.projectId != null &&
                              existingTask.projectId != selectedProjectId) {
                            await projectsCtrl.detachTaskFromProjectSections(
                              existingTask.projectId!,
                              existingTask.id,
                            );
                          } else if (projectsCtrl != null &&
                              updated != null &&
                              selectedProjectId != null) {
                            await projectsCtrl.syncTaskSectionLink(
                              selectedProjectId!,
                              updated,
                            );
                          }
                          if (updateRes.generatedNextTask != null &&
                              projectsCtrl != null &&
                              updateRes.generatedNextTask!.projectId != null) {
                            await projectsCtrl.copyTaskSectionLink(
                              updateRes.generatedNextTask!.projectId!,
                              existingTask.id,
                              updateRes.generatedNextTask!,
                            );
                          }
                        } else {
                          final createdTask = await controller.createTask(
                            title: title,
                            description: desc.isEmpty ? null : desc,
                            priority: priority,
                            status: status,
                            dueDate: dueDate,
                            scheduledDate: scheduledDate,
                            projectId: selectedProjectId,
                            milestoneId: resolvedMilestoneId,
                            subtasks: modalSubtasks,
                            labels: modalLabels,
                            recurrenceRule: recConfig?.frequency,
                            recurrenceConfig: recConfig,
                            isMyDay: controller.state.viewFilter == 'my_day',
                            myDayDate: controller.state.viewFilter == 'my_day'
                                ? controller.state.effectivePlanDate
                                : null,
                          );
                          if (createdTask != null) {
                            if (projectsCtrl != null &&
                                selectedProjectId != null) {
                              await projectsCtrl.syncTaskSectionLink(
                                selectedProjectId!,
                                createdTask,
                              );
                            }
                            if (sourceInboxItem != null) {
                              await widget.effectiveInboxController
                                  ?.markProcessed(sourceInboxItem.id);
                              if (mounted) {
                                ScaffoldMessenger.of(context).clearSnackBars();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Converted "${createdTask.title}" to Task',
                                    ),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            }
                          }
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showSubtaskDeletedUndo(
    String taskId,
    String deletedTitle,
    List<TaskSubtask> previousList,
    TasksController controller,
  ) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed subtask "$deletedTitle"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              unawaited(controller.restoreSubtasks(taskId, previousList)),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showTaskDetails(TaskEntity initialTask, TasksController controller) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SharedDesignTokens.radiusSheet),
          ),
        ),
        builder: (ctx) => AnimatedBuilder(
          animation: controller,
          builder: (modalContext, _) {
            final task =
                controller.state.findTaskById(initialTask.id) ?? initialTask;
            final semantic = modalContext.daywellColors;
            final colorScheme = Theme.of(modalContext).colorScheme;
            final activePlanDate = controller.state.effectivePlanDate;
            final isInMyDay = DailyPlanningEngine.isTaskPlannedForDate(
              task,
              controller.state.dailyPlanningEntries,
              activePlanDate,
            );

            return Padding(
              padding: EdgeInsets.only(
                top: SharedDesignTokens.spacingMd,
                left: SharedDesignTokens.spacingMd,
                right: SharedDesignTokens.spacingMd,
                bottom: MediaQuery.of(modalContext).viewInsets.bottom +
                    SharedDesignTokens.spacingMd,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            style: Theme.of(modalContext)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  decoration: task.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            task.isPinned
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                          ),
                          tooltip: 'Pin Task',
                          onPressed: () =>
                              unawaited(controller.togglePin(task.id)),
                        ),
                        IconButton(
                          icon: Icon(
                            isInMyDay
                                ? Icons.wb_sunny
                                : Icons.wb_sunny_outlined,
                            color: isInMyDay ? semantic.warning : null,
                          ),
                          tooltip: isInMyDay
                              ? 'Remove from My Day'
                              : 'Add to My Day',
                          onPressed: () => unawaited(
                            controller.toggleMyDay(
                              task.id,
                              date: activePlanDate,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingSm),
                    Wrap(
                      spacing: SharedDesignTokens.spacingSm,
                      runSpacing: SharedDesignTokens.spacingXs,
                      children: [
                        DaywellStatusBadge(
                          label: _statusLabel(task.status),
                          tone: _statusTone(task.status),
                        ),
                        DaywellStatusBadge(
                          label: '${_priorityLabel(task.priority)} Priority',
                          tone: _priorityTone(task.priority),
                          icon: Icons.flag,
                        ),
                        if (isInMyDay)
                          const DaywellStatusBadge(
                            label: 'In My Day',
                            tone: DaywellStatusTone.info,
                            icon: Icons.wb_sunny_outlined,
                          ),
                        if (task.isArchived)
                          const DaywellStatusBadge(
                            label: 'Archived',
                            tone: DaywellStatusTone.warning,
                            icon: Icons.archive_outlined,
                          ),
                        for (final lbl in task.labels)
                          Chip(
                            label: Text('@$lbl',
                                style: const TextStyle(fontSize: 11)),
                          ),
                      ],
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    if (task.description != null &&
                        task.description!.isNotEmpty)
                      Text(
                        task.description!,
                        style: Theme.of(modalContext)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: semantic.textSecondary),
                      )
                    else
                      Text(
                        'No description added.',
                        style: Theme.of(modalContext)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
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
                            'Scheduled Date: ${task.scheduledDate != null ? SharedDateFormatter.formatDual(task.scheduledDate!, useAmharic: false) : 'Not set'}',
                            style: Theme.of(modalContext)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: semantic.textPrimary),
                          ),
                          const SizedBox(height: SharedDesignTokens.spacingXs),
                          Text(
                            'Due Date: ${task.dueDate != null ? SharedDateFormatter.formatDual(task.dueDate!, useAmharic: false) : 'Not set'}',
                            style: Theme.of(modalContext)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: colorScheme.primary),
                          ),
                          if (task.projectId != null) ...[
                            Builder(
                              builder: (_) {
                                ProjectEntity? linkedProject;
                                for (final p in controller.state.projects) {
                                  if (p.id == task.projectId) {
                                    linkedProject = p;
                                    break;
                                  }
                                }
                                if (linkedProject == null) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    top: SharedDesignTokens.spacingXs,
                                  ),
                                  child: Text(
                                    'Project: ${linkedProject.title}',
                                    style: Theme.of(modalContext)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: semantic.textPrimary),
                                  ),
                                );
                              },
                            ),
                          ],
                          if (task.milestoneId != null) ...[
                            Builder(
                              builder: (_) {
                                MilestoneEntity? linkedMilestone;
                                for (final m in controller.state.milestones) {
                                  if (m.id == task.milestoneId) {
                                    linkedMilestone = m;
                                    break;
                                  }
                                }
                                if (linkedMilestone == null) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    top: SharedDesignTokens.spacingXs,
                                  ),
                                  child: Text(
                                    'Milestone: ${linkedMilestone.title}',
                                    style: Theme.of(modalContext)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: semantic.textPrimary),
                                  ),
                                );
                              },
                            ),
                          ],
                          if (task.completedAt != null) ...[
                            const SizedBox(height: SharedDesignTokens.spacingXs),
                            Text(
                              'Completed: ${EthiopiaClock.toUtcIsoString(task.completedAt!).substring(0, 10)}',
                              style: Theme.of(modalContext)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: semantic.textMuted),
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
                            final skipped = await controller
                                .skipRecurrenceOccurrence(task.id);
                            if (!mounted) return;
                            if (skipped == null) {
                              final err = controller.state.errorMessage;
                              if (err != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(err)),
                                );
                              }
                              return;
                            }
                            final nextDate =
                                skipped.dueDate ?? skipped.scheduledDate;
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Skipped to ${nextDate?.toIsoString() ?? 'next occurrence'}',
                                ),
                                action: SnackBarAction(
                                  label: 'Undo',
                                  onPressed: () => unawaited(
                                    controller
                                        .restoreTaskSnapshot(prevSnapshot),
                                  ),
                                ),
                              ),
                            );
                          }());
                        },
                        onRescheduleOccurrence: () {
                          final prevSnapshot = task;
                          unawaited(() async {
                            final picked = await _pickCalendarDate(
                              task.dueDate ?? task.scheduledDate,
                            );
                            if (picked == null) return;
                            final updated = await controller
                                .rescheduleTaskOccurrence(task.id, picked);
                            if (!mounted) return;
                            if (updated == null) {
                              final err = controller.state.errorMessage;
                              if (err != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(err)),
                                );
                              }
                              return;
                            }
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Rescheduled "${updated.title}" to ${picked.toIsoString()}',
                                ),
                                action: SnackBarAction(
                                  label: 'Undo',
                                  onPressed: () => unawaited(
                                    controller
                                        .restoreTaskSnapshot(prevSnapshot),
                                  ),
                                ),
                              ),
                            );
                          }());
                        },
                        onEditRecurrence: () {
                          Navigator.pop(ctx);
                          _showTaskFormModal(existingTask: task);
                        },
                        onStopRecurrence: () {
                          final prevSnapshot = task;
                          unawaited(() async {
                            final stopped =
                                await controller.stopTaskRecurrence(task.id);
                            if (!mounted) return;
                            if (stopped == null) {
                              final err = controller.state.errorMessage;
                              if (err != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(err)),
                                );
                              }
                              return;
                            }
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Stopped recurrence for "${stopped.title}"',
                                ),
                                action: SnackBarAction(
                                  label: 'Undo',
                                  onPressed: () => unawaited(
                                    controller
                                        .restoreTaskSnapshot(prevSnapshot),
                                  ),
                                ),
                              ),
                            );
                          }());
                        },
                      ),
                    ],
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    _TaskDetailsTagsPanel(
                      task: task,
                      controller: controller,
                      onOpenManageTags: () => _showManageTagsDialog(controller),
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    _TaskDetailsSubtasksPanel(
                      task: task,
                      controller: controller,
                      onDeletedWithUndo: (deletedTitle, previousList) =>
                          _showSubtaskDeletedUndo(
                        task.id,
                        deletedTitle,
                        previousList,
                        controller,
                      ),
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingMd),
                    Wrap(
                      spacing: SharedDesignTokens.spacingSm,
                      runSpacing: SharedDesignTokens.spacingSm,
                      children: [
                        DaywellButton(
                          label: 'Edit',
                          variant: DaywellButtonVariant.secondary,
                          size: DaywellButtonSize.compact,
                          leadingIcon: Icons.edit_outlined,
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showTaskFormModal(existingTask: task);
                          },
                        ),
                        DaywellButton(
                          label: task.isArchived ? 'Restore' : 'Archive',
                          variant: DaywellButtonVariant.outlined,
                          size: DaywellButtonSize.compact,
                          leadingIcon: task.isArchived
                              ? Icons.restore
                              : Icons.archive_outlined,
                          onPressed: () {
                            _toggleArchiveWithUndo(task, controller);
                            Navigator.pop(ctx);
                          },
                        ),
                        DaywellButton(
                          label: task.isCompleted
                              ? 'Reopen Task'
                              : 'Complete Task',
                          variant: DaywellButtonVariant.primary,
                          size: DaywellButtonSize.compact,
                          leadingIcon: Icons.check,
                          onPressed: () {
                            _toggleCompleteWithUndo(task, controller);
                            Navigator.pop(ctx);
                          },
                        ),
                        DaywellButton(
                          label: 'Delete',
                          variant: DaywellButtonVariant.text,
                          size: DaywellButtonSize.compact,
                          leadingIcon: Icons.delete_outline,
                          onPressed: () async {
                            final deleted =
                                await _confirmAndDeleteTask(task, controller);
                            if (deleted && ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showAddProjectModal(TasksController controller) {
    final nameCtrl = TextEditingController();
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('New Project'),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'e.g. Master\'s Research',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isNotEmpty) {
                  await controller.createProject(title: name);
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showManageTagsDialog(TasksController controller) {
    final newTagCtrl = TextEditingController();
    final editTagCtrl = TextEditingController();
    String? createError;
    String? editingTag;
    String? editError;

    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AnimatedBuilder(
            animation: controller,
            builder: (_, __) {
              final semantic = dialogContext.daywellColors;
              final allTags = controller.state.availableTags;
              final allTasks = controller.state.tasks;

              return AlertDialog(
                title: const Text('Manage Tags'),
                content: SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: newTagCtrl,
                                decoration: InputDecoration(
                                  hintText: 'Create new tag...',
                                  errorText: createError,
                                  isDense: true,
                                ),
                                onChanged: (_) {
                                  if (createError != null) {
                                    setDialogState(() => createError = null);
                                  }
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add),
                              tooltip: 'Create Tag',
                              onPressed: () {
                                final normalized =
                                    TasksModuleState.normalizeLabel(
                                  newTagCtrl.text,
                                );
                                if (normalized.isEmpty) {
                                  setDialogState(
                                    () => createError = 'Tag name is required',
                                  );
                                  return;
                                }
                                final ok = controller.createTag(normalized);
                                if (ok) {
                                  newTagCtrl.clear();
                                  setDialogState(() => createError = null);
                                } else {
                                  setDialogState(
                                    () => createError =
                                        controller.state.errorMessage,
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: SharedDesignTokens.spacingMd),
                        if (allTags.isEmpty)
                          Text(
                            'No tags created yet.',
                            style: Theme.of(dialogContext)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: semantic.textMuted,
                                  fontStyle: FontStyle.italic,
                                ),
                          )
                        else
                          for (final lbl in allTags) ...[
                            Container(
                              margin: const EdgeInsets.only(
                                bottom: SharedDesignTokens.spacingXs,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: SharedDesignTokens.spacingSm,
                                vertical: SharedDesignTokens.spacingXs,
                              ),
                              decoration: BoxDecoration(
                                color: semantic.surfaceSubtle,
                                borderRadius: BorderRadius.circular(
                                  SharedDesignTokens.radiusSm,
                                ),
                                border: Border.all(color: semantic.border),
                              ),
                              child: editingTag == lbl
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                controller: editTagCtrl,
                                                autofocus: true,
                                                decoration:
                                                    const InputDecoration(
                                                  isDense: true,
                                                  hintText: 'Rename tag...',
                                                ),
                                                onChanged: (_) {
                                                  if (editError != null) {
                                                    setDialogState(
                                                      () => editError = null,
                                                    );
                                                  }
                                                },
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.check,
                                                  size: 18),
                                              tooltip: 'Save tag name',
                                              onPressed: () async {
                                                final nextName =
                                                    TasksModuleState
                                                        .normalizeLabel(
                                                  editTagCtrl.text,
                                                );
                                                if (nextName.isEmpty) {
                                                  setDialogState(
                                                    () => editError =
                                                        'Tag name is required',
                                                  );
                                                  return;
                                                }
                                                if (nextName == lbl) {
                                                  setDialogState(() {
                                                    editingTag = null;
                                                    editTagCtrl.clear();
                                                    editError = null;
                                                  });
                                                  return;
                                                }
                                                final prevTasks =
                                                    List<TaskEntity>.from(
                                                        controller.state.tasks);
                                                final prevCustom =
                                                    List<String>.from(controller
                                                        .state.customTags);
                                                final prevFilters =
                                                    Set<String>.from(controller
                                                        .state.tagFilters);
                                                final ok =
                                                    await controller.renameTag(
                                                  lbl,
                                                  nextName,
                                                );
                                                if (!ok) {
                                                  if (dialogContext.mounted) {
                                                    setDialogState(
                                                      () => editError =
                                                          controller.state
                                                                  .errorMessage ??
                                                              'Unable to rename tag',
                                                    );
                                                  }
                                                  return;
                                                }
                                                if (!dialogContext.mounted) {
                                                  return;
                                                }
                                                setDialogState(() {
                                                  editingTag = null;
                                                  editTagCtrl.clear();
                                                  editError = null;
                                                });
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .clearSnackBars();
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Renamed "@$lbl" to "@$nextName"',
                                                      ),
                                                      action: SnackBarAction(
                                                        label: 'Undo',
                                                        onPressed: () =>
                                                            unawaited(
                                                          controller
                                                              .restoreTasksLabelsSnapshot(
                                                            prevTasks,
                                                            previousCustomTags:
                                                                prevCustom,
                                                            previousTagFilters:
                                                                prevFilters,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.close,
                                                  size: 18),
                                              tooltip: 'Cancel tag rename',
                                              onPressed: () {
                                                setDialogState(() {
                                                  editingTag = null;
                                                  editTagCtrl.clear();
                                                  editError = null;
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                        if (editError != null)
                                          Text(
                                            editError!,
                                            style: DaywellTypography.caption(
                                              color: semantic.error,
                                            ),
                                          ),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '@$lbl (${allTasks.where((t) => t.labels.any((x) => TasksModuleState.normalizeLabel(x).toLowerCase() == lbl.toLowerCase())).length})',
                                            style: Theme.of(dialogContext)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: semantic.textPrimary,
                                                ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined,
                                              size: 18),
                                          tooltip: 'Rename tag $lbl',
                                          onPressed: () {
                                            setDialogState(() {
                                              editingTag = lbl;
                                              editTagCtrl.text = lbl;
                                              editError = null;
                                            });
                                          },
                                        ),
                                        IconButton(
                                          icon: Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: semantic.error,
                                          ),
                                          tooltip: 'Delete tag $lbl',
                                          onPressed: () async {
                                            final prevTasks =
                                                List<TaskEntity>.from(
                                                    controller.state.tasks);
                                            final prevCustom =
                                                List<String>.from(
                                                    controller.state.customTags);
                                            final prevFilters =
                                                Set<String>.from(
                                                    controller.state.tagFilters);
                                            await controller.deleteTag(lbl);
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .clearSnackBars();
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Removed tag "@$lbl"',
                                                ),
                                                action: SnackBarAction(
                                                  label: 'Undo',
                                                  onPressed: () => unawaited(
                                                    controller
                                                        .restoreTasksLabelsSnapshot(
                                                      prevTasks,
                                                      previousCustomTags:
                                                          prevCustom,
                                                      previousTagFilters:
                                                          prevFilters,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                            ),
                          ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFilterControls(
    BuildContext context,
    TasksController controller,
    TasksModuleState moduleState,
    ProjectsModuleState? projectsState,
  ) {
    final sourceProjects = projectsState?.projects ?? moduleState.projects;
    final activeProjects = sourceProjects
        .where((p) => !p.isArchived)
        .toList(growable: false);
    final selectedProjectId = moduleState.selectedProjectId;
    final List<ProjectTrackingRecordEntity> sections =
        (selectedProjectId != null && projectsState != null)
            ? projectsState.sectionsForProject(selectedProjectId)
            : const [];
    final availableTags = moduleState.availableTags;

    return [
      SizedBox(
        width: 156,
        child: DaywellDropdownField<String?>(
          label: 'Status',
          value: moduleState.statusFilter,
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All Statuses'),
            ),
            for (final s in _statusOptions)
              DropdownMenuItem<String?>(
                value: s.$1,
                child: Text(s.$2),
              ),
          ],
          onChanged: controller.setStatusFilter,
        ),
      ),
      SizedBox(
        width: 148,
        child: DaywellDropdownField<String?>(
          label: 'Priority',
          value: moduleState.priorityFilter,
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All Priorities'),
            ),
            for (final p in _priorityOptions)
              DropdownMenuItem<String?>(
                value: p.$1,
                child: Text(p.$2),
              ),
          ],
          onChanged: controller.setPriorityFilter,
        ),
      ),
      SizedBox(
        width: 162,
        child: DaywellDropdownField<String?>(
          label: 'Due Date',
          value: moduleState.dueDateFilter,
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Any Due Date'),
            ),
            for (final d in _dueDateFilterOptions)
              DropdownMenuItem<String?>(
                value: d.$1,
                child: Text(d.$2),
              ),
          ],
          onChanged: controller.setDueDateFilter,
        ),
      ),
      if (activeProjects.isNotEmpty)
        SizedBox(
          width: 170,
          child: DaywellDropdownField<String?>(
            label: 'Project',
            value: activeProjects.any((p) => p.id == selectedProjectId)
                ? selectedProjectId
                : null,
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All Projects'),
              ),
              for (final p in activeProjects)
                DropdownMenuItem<String?>(
                  value: p.id,
                  child: Text(p.title),
                ),
            ],
            onChanged: controller.selectProject,
          ),
        ),
      if (selectedProjectId != null && projectsState != null)
        SizedBox(
          width: 170,
          child: DaywellDropdownField<String?>(
            label: 'Section',
            value: (moduleState.sectionFilter == '__unsectioned__' ||
                    sections.any((s) => s.id == moduleState.sectionFilter))
                ? moduleState.sectionFilter
                : null,
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All Sections'),
              ),
              for (final sec in sections)
                DropdownMenuItem<String?>(
                  value: sec.id,
                  child: Text(sec.title),
                ),
              const DropdownMenuItem<String?>(
                value: '__unsectioned__',
                child: Text('Unsectioned'),
              ),
            ],
            onChanged: controller.setSectionFilter,
          ),
        ),
      for (final tag in availableTags)
        FilterChip(
          label: Text('@$tag'),
          selected: moduleState.tagFilters
              .any((selected) => selected.toLowerCase() == tag.toLowerCase()),
          onSelected: (_) => controller.toggleTagFilter(tag),
        ),
    ];
  }

  Future<void> _showEditInboxItemDialog(
    InboxItemEntity item,
    InboxController inboxCtrl,
  ) async {
    final textCtrl = TextEditingController(text: item.rawText);
    String selectedCategory = item.category;
    String? errorText;
    const categoryChoices = [
      ('task', 'Task'),
      ('idea', 'Idea'),
      ('note', 'Note'),
      ('problem', 'Problem'),
      ('decision', 'Decision'),
      ('general', 'General'),
    ];

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Edit Inbox Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DaywellTextField(
                  controller: textCtrl,
                  autofocus: true,
                  isRequired: true,
                  label: 'Captured Note / Thought',
                  errorText: errorText,
                  maxLines: 4,
                  onChanged: (_) {
                    if (errorText != null) {
                      setDialogState(() => errorText = null);
                    }
                  },
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellDropdownField<String>(
                  label: 'Category',
                  value: categoryChoices.any((c) => c.$1 == selectedCategory)
                      ? selectedCategory
                      : 'general',
                  items: [
                    for (final c in categoryChoices)
                      DropdownMenuItem(value: c.$1, child: Text(c.$2)),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() => selectedCategory = v);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final trimmed = textCtrl.text.trim();
                if (trimmed.isEmpty) {
                  setDialogState(() => errorText = 'Inbox text is required');
                  return;
                }
                await inboxCtrl.updateItemText(
                  item.id,
                  trimmed,
                  category: selectedCategory,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _dismissInboxItem(
    InboxItemEntity item,
    InboxController inboxCtrl,
  ) async {
    await inboxCtrl.markProcessed(item.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Marked Inbox item as processed'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmAndDeleteInboxItem(
    InboxItemEntity item,
    InboxController inboxCtrl,
  ) async {
    final confirmed = await DaywellConfirmationDialog.show(
      context,
      title: 'Delete Inbox item?',
      message: 'Remove "${item.rawText}" from your Inbox?',
      confirmLabel: 'Delete Item',
      cancelLabel: 'Cancel',
      isDestructive: true,
      icon: Icons.delete_outline,
    );
    if (!confirmed || !mounted) return;
    await inboxCtrl.deleteItem(item.id);
  }

  Widget _buildInboxCapturesSection(
    BuildContext context,
    InboxController inboxCtrl,
    List<InboxItemEntity> unprocessed,
  ) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final sorted = List<InboxItemEntity>.from(unprocessed)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Captured Inbox Items (${sorted.length})',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: semantic.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Unprocessed Quick Captures stay here until you convert them into Tasks or dismiss them.',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              DaywellStatusBadge(
                label: '${sorted.length} Pending',
                tone: sorted.isNotEmpty
                    ? DaywellStatusTone.info
                    : DaywellStatusTone.neutral,
              ),
            ],
          ),
          if (sorted.isEmpty) ...[
            const SizedBox(height: SharedDesignTokens.spacingCompact),
            Text(
              'No unprocessed Quick Capture items right now.',
              style: textTheme.bodySmall?.copyWith(
                color: semantic.textSecondary,
              ),
            ),
          ] else ...[
            const SizedBox(height: SharedDesignTokens.spacingCompact),
            for (final item in sorted)
              Padding(
                padding: const EdgeInsets.only(
                  bottom: SharedDesignTokens.spacingSm,
                ),
                child: DaywellCard(
                  padding: const EdgeInsets.all(
                    SharedDesignTokens.spacingCompact,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.rawText,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: semantic.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: SharedDesignTokens.spacingSm),
                          DaywellStatusBadge(
                            label: item.category.toUpperCase(),
                            tone: DaywellStatusTone.info,
                          ),
                        ],
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingXs),
                      Text(
                        'Captured: ${SharedDateFormatter.formatDual(CalendarDate.fromUtcInstantInEthiopia(item.createdAt), useAmharic: false)}',
                        style: textTheme.bodySmall?.copyWith(
                          color: semantic.textMuted,
                        ),
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingSm),
                      Wrap(
                        spacing: SharedDesignTokens.spacingSm,
                        runSpacing: SharedDesignTokens.spacingXs,
                        children: [
                          DaywellButton(
                            label: 'Convert to Task',
                            size: DaywellButtonSize.compact,
                            leadingIcon: Icons.task_alt,
                            onPressed: () =>
                                _showTaskFormModal(sourceInboxItem: item),
                          ),
                          DaywellButton(
                            label: 'Edit',
                            variant: DaywellButtonVariant.outlined,
                            size: DaywellButtonSize.compact,
                            leadingIcon: Icons.edit_outlined,
                            onPressed: () =>
                                _showEditInboxItemDialog(item, inboxCtrl),
                          ),
                          DaywellButton(
                            label: 'Mark Processed',
                            variant: DaywellButtonVariant.text,
                            size: DaywellButtonSize.compact,
                            onPressed: () =>
                                _dismissInboxItem(item, inboxCtrl),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: semantic.error,
                            ),
                            tooltip: 'Delete Inbox item',
                            onPressed: () =>
                                _confirmAndDeleteInboxItem(item, inboxCtrl),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.effectiveController;
    final projectsCtrl = widget.effectiveProjectsController;
    final inboxCtrl = widget.effectiveInboxController;
    final colorScheme = Theme.of(context).colorScheme;
    final listenables = <Listenable>[
      controller,
      if (projectsCtrl != null) projectsCtrl,
      if (inboxCtrl != null) inboxCtrl,
    ];
    final Listenable listenable =
        listenables.length == 1 ? controller : Listenable.merge(listenables);

    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final moduleState = controller.state;
        final projectsState = projectsCtrl?.state;
        final unprocessedInbox =
            inboxCtrl?.state.unprocessedItems ?? const <InboxItemEntity>[];
        Set<String>? sectionTaskIds;
        if (moduleState.selectedProjectId != null &&
            moduleState.sectionFilter != null &&
            projectsState != null) {
          sectionTaskIds = projectsState.taskIdsForSection(
            moduleState.selectedProjectId!,
            moduleState.sectionFilter!,
            allTasks: moduleState.tasks,
          );
        }
        final tasks = moduleState.filterTasks(sectionTaskIds: sectionTaskIds);

        return Scaffold(
          appBar: AppBar(
            title: moduleState.isSelectionMode
                ? Text('${moduleState.selectedTaskIds.length} selected')
                : const Text('Tasks',
                    style: TextStyle(fontWeight: FontWeight.bold)),
            actions: moduleState.isSelectionMode
                ? [
                    IconButton(
                      icon: const Icon(Icons.check_circle_outline),
                      onPressed: controller.batchToggleSelected,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: controller.batchDeleteSelected,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: controller.clearSelection,
                    ),
                  ]
                : [
                    IconButton(
                      icon: Icon(moduleState.isBoardView
                          ? Icons.view_list_rounded
                          : Icons.view_kanban_outlined),
                      tooltip:
                          moduleState.isBoardView ? 'List View' : 'Board View',
                      onPressed: controller.toggleBoardView,
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.sort_rounded),
                      tooltip: 'Sort tasks',
                      onSelected: controller.setSortBy,
                      itemBuilder: (_) => [
                        CheckedPopupMenuItem<String>(
                          value: 'due',
                          checked: moduleState.sortBy == 'due',
                          child: const Text('Sort by Due Date'),
                        ),
                        CheckedPopupMenuItem<String>(
                          value: 'priority',
                          checked: moduleState.sortBy == 'priority',
                          child: const Text('Sort by Priority'),
                        ),
                        CheckedPopupMenuItem<String>(
                          value: 'created',
                          checked: moduleState.sortBy == 'created',
                          child: const Text('Sort by Creation Date'),
                        ),
                        CheckedPopupMenuItem<String>(
                          value: 'alpha',
                          checked: moduleState.sortBy == 'alpha',
                          child: const Text('Sort Alphabetically'),
                        ),
                      ],
                    ),
                  ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Tasks'),
                Tab(text: 'Projects'),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _tabController.index == 1
                ? () {
                    if (projectsCtrl != null) {
                      unawaited(
                        ProjectFormSheet.show(
                          context,
                          projectsController: projectsCtrl,
                          tasksController: controller,
                        ),
                      );
                    } else {
                      _showAddProjectModal(controller);
                    }
                  }
                : _showQuickAddModal,
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            icon: const Icon(Icons.add),
            label: Text(_tabController.index == 1 ? 'New Project' : 'Add Task'),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              Column(
                children: [
                  DaywellSearchFilterBar(
                    searchController: _searchController,
                    searchHintText:
                        'Search tasks by title, description, or @tags...',
                    onSearchChanged: controller.setSearchQuery,
                    onSearchCleared: () {
                      _searchController.clear();
                      controller.setSearchQuery('');
                    },
                    trailingAction: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _showFilters || moduleState.activeFilterCount > 0
                                ? Icons.filter_alt
                                : Icons.filter_alt_outlined,
                          ),
                          tooltip: 'Toggle Filters',
                          onPressed: () =>
                              setState(() => _showFilters = !_showFilters),
                        ),
                        IconButton(
                          icon: const Icon(Icons.label_outline),
                          tooltip: 'Manage Tags',
                          onPressed: () => _showManageTagsDialog(controller),
                        ),
                      ],
                    ),
                    filterControls: _showFilters
                        ? _buildFilterControls(
                            context,
                            controller,
                            moduleState,
                            projectsState,
                          )
                        : const [],
                    hasActiveFilters: moduleState.hasActiveFilters,
                    activeSummary: moduleState.hasActiveFilters
                        ? '${tasks.length} matching tasks'
                        : null,
                    onClearFilters: () {
                      _searchController.clear();
                      controller.clearFilters(resetView: false);
                    },
                    showBottomDivider: false,
                    padding: const EdgeInsets.fromLTRB(
                      SharedDesignTokens.spacingMd,
                      SharedDesignTokens.spacingSm,
                      SharedDesignTokens.spacingMd,
                      SharedDesignTokens.spacingXs,
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final f in [
                          ('today', 'Today'),
                          (
                            'inbox',
                            unprocessedInbox.isNotEmpty
                                ? 'Inbox (${unprocessedInbox.length})'
                                : 'Inbox'
                          ),
                          ('upcoming', 'Upcoming'),
                          ('active', 'Active'),
                          ('overdue', 'Overdue'),
                          ('all', 'All'),
                          (
                            'my_day',
                            moduleState.myDayCount > 0
                                ? 'My Day (${moduleState.myDayCount})'
                                : 'My Day'
                          ),
                          ('completed', 'Completed'),
                          ('archived', 'Archived'),
                        ])
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(f.$2,
                                  style: const TextStyle(fontSize: 12)),
                              selected: moduleState.viewFilter == f.$1,
                              onSelected: (_) => controller.setViewFilter(f.$1),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (inboxCtrl != null &&
                      moduleState.viewFilter != 'inbox' &&
                      unprocessedInbox.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        SharedDesignTokens.spacingMd,
                        SharedDesignTokens.spacingSm,
                        SharedDesignTokens.spacingMd,
                        SharedDesignTokens.spacingXs,
                      ),
                      child: DaywellStatusBanner(
                        tone: DaywellStatusTone.info,
                        message:
                            '${unprocessedInbox.length} Quick Capture item(s) waiting in Inbox',
                        actionLabel: 'Review',
                        onActionPressed: () =>
                            controller.setViewFilter('inbox'),
                      ),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: moduleState.viewFilter == 'my_day'
                        ? MyDayPlanningView(
                            moduleState: moduleState,
                            snapshot: moduleState.buildDailyPlanSnapshot(),
                            onSelectDate: controller.setSelectedPlanDate,
                            onStepDate: (delta) =>
                                controller.setSelectedPlanDate(
                              moduleState.effectivePlanDate.addDays(delta),
                            ),
                            onPickDate: () async {
                              final picked = await _pickCalendarDate(
                                moduleState.effectivePlanDate,
                              );
                              if (picked != null && mounted) {
                                controller.setSelectedPlanDate(picked);
                              }
                            },
                            onJumpToToday: controller.resetPlanDateToToday,
                            onToggleTask: (task) =>
                                _toggleCompleteWithUndo(task, controller),
                            onOpenTaskDetails: (task) =>
                                _showTaskDetails(task, controller),
                            onMoveTaskOrder: (taskId, delta) => unawaited(
                              controller.movePlannedTaskOrder(
                                taskId,
                                delta: delta,
                                date: moduleState.effectivePlanDate,
                              ),
                            ),
                            onRemoveFromDay: (task) => unawaited(
                              _removeTaskFromDayWithUndo(
                                task,
                                controller,
                                moduleState.effectivePlanDate,
                              ),
                            ),
                            onAddToDay: (taskId, action) => unawaited(
                              controller.planTaskForDate(
                                taskId,
                                date: moduleState.effectivePlanDate,
                                action: action,
                              ),
                            ),
                            onCarryForwardAll: () async {
                              final targetDate = moduleState.effectivePlanDate;
                              final carriedCount = await controller
                                  .carryForwardUnfinishedTasks(
                                toDate: targetDate,
                              );
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    carriedCount > 0
                                        ? 'Carried forward $carriedCount unfinished task(s) to ${targetDate.toIsoString()}'
                                        : 'All unfinished tasks are already planned for ${targetDate.toIsoString()}',
                                  ),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            },
                            onCarryPastRemainingToToday: () async {
                              final fromDate = moduleState.effectivePlanDate;
                              final today = CalendarDate.today();
                              final carriedCount = await controller
                                  .carryForwardUnfinishedTasks(
                                fromDate: fromDate,
                                toDate: today,
                              );
                              controller.setSelectedPlanDate(today);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    carriedCount > 0
                                        ? 'Carried $carriedCount unfinished task(s) from ${fromDate.toIsoString()} to Today'
                                        : 'Remaining tasks from ${fromDate.toIsoString()} are already in Today',
                                  ),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            },
                            onCreateTaskForDay: _showQuickAddModal,
                          )
                        : moduleState.viewFilter == 'inbox' &&
                                inboxCtrl != null
                            ? (unprocessedInbox.isEmpty && tasks.isEmpty)
                                ? DaywellEmptyState(
                                    icon: Icons.inbox_outlined,
                                    message: moduleState.hasActiveFilters
                                        ? 'No tasks match active filters'
                                        : 'Inbox is clear',
                                    actionLabel: moduleState.hasActiveFilters
                                        ? 'Clear filters'
                                        : 'Add Task',
                                    onActionPressed: moduleState.hasActiveFilters
                                        ? () {
                                            _searchController.clear();
                                            controller.clearFilters(
                                              resetView: false,
                                            );
                                          }
                                        : () => _showQuickAddModal(),
                                  )
                                : ListView(
                                    padding: const EdgeInsets.all(12),
                                    children: [
                                      _buildInboxCapturesSection(
                                        context,
                                        inboxCtrl,
                                        unprocessedInbox,
                                      ),
                                      const SizedBox(
                                        height: SharedDesignTokens.spacingMd,
                                      ),
                                      if (tasks.isNotEmpty) ...[
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom:
                                                SharedDesignTokens.spacingSm,
                                          ),
                                          child: Text(
                                            'Unassigned Tasks (${tasks.length})',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                        for (final t in tasks)
                                          _buildTaskTile(
                                            t,
                                            controller,
                                            moduleState,
                                          ),
                                      ],
                                    ],
                                  )
                            : tasks.isEmpty
                                ? DaywellEmptyState(
                                    icon: Icons.check_circle_outline,
                                    message: moduleState.hasActiveFilters
                                        ? 'No tasks match active filters'
                                        : moduleState.viewFilter == 'archived'
                                            ? 'No archived tasks'
                                            : 'No tasks in ${moduleState.viewFilter}',
                                    actionLabel: moduleState.hasActiveFilters
                                        ? 'Clear filters'
                                        : moduleState.viewFilter == 'archived'
                                            ? null
                                            : 'Add Task',
                                    onActionPressed:
                                        moduleState.hasActiveFilters
                                            ? () {
                                                _searchController.clear();
                                                controller.clearFilters(
                                                  resetView: false,
                                                );
                                              }
                                            : moduleState.viewFilter ==
                                                    'archived'
                                                ? null
                                                : () => _showQuickAddModal(),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.all(12),
                                    itemCount: tasks.length,
                                    itemBuilder: (_, i) => _buildTaskTile(
                                        tasks[i], controller, moduleState),
                                  ),
                  ),
                ],
              ),
              ProjectsWorkspaceTab(
                projectsController: projectsCtrl,
                tasksController: controller,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTaskTile(TaskEntity task, TasksController controller,
      TasksModuleState moduleState) {
    final isSelected = moduleState.selectedTaskIds.contains(task.id);
    final subs = task.subtasks;
    final doneSubs = subs.where((s) => s.done).length;
    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey(task.id),
      background: Container(
        color: semantic.success,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: Icon(Icons.check, color: semantic.onSuccess),
      ),
      secondaryBackground: Container(
        color: semantic.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete, color: semantic.onError),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          unawaited(_toggleCompleteWithUndo(task, controller));
          return false;
        }
        return _confirmAndDeleteTask(task, controller);
      },
      child: Card(
        elevation: 0,
        color: isSelected ? colorScheme.primaryContainer : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
          side: BorderSide(color: semantic.border),
        ),
        child: ListTile(
          onLongPress: () => controller.toggleTaskSelection(task.id),
          onTap: () {
            if (moduleState.isSelectionMode) {
              controller.toggleTaskSelection(task.id);
            } else {
              _showTaskDetails(task, controller);
            }
          },
          leading: Checkbox(
            value: task.isCompleted,
            activeColor: colorScheme.primary,
            side: BorderSide(
              color: task.priority == 'urgent'
                  ? semantic.error
                  : task.priority == 'high'
                      ? semantic.warning
                      : semantic.textMuted,
              width: 2,
            ),
            onChanged: (_) =>
                unawaited(_toggleCompleteWithUndo(task, controller)),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration:
                        task.isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (task.isPinned)
                Icon(
                  Icons.push_pin_rounded,
                  size: 15,
                  color: colorScheme.primary,
                ),
            ],
          ),
          trailing: task.isArchived
              ? DaywellIconButton(
                  icon: Icons.restore,
                  tooltip: 'Restore ${task.title}',
                  onPressed: () => _toggleArchiveWithUndo(task, controller),
                )
              : Builder(
                  builder: (_) {
                    final isPlanned = DailyPlanningEngine.isTaskPlannedForDate(
                      task,
                      moduleState.dailyPlanningEntries,
                      moduleState.effectivePlanDate,
                    );
                    return DaywellIconButton(
                      icon:
                          isPlanned ? Icons.wb_sunny : Icons.wb_sunny_outlined,
                      foregroundColor:
                          isPlanned ? semantic.warning : semantic.textMuted,
                      tooltip: isPlanned
                          ? 'Remove ${task.title} from My Day'
                          : 'Add ${task.title} to My Day',
                      onPressed: () => unawaited(
                        controller.toggleMyDay(
                          task.id,
                          date: moduleState.effectivePlanDate,
                        ),
                      ),
                    );
                  },
                ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    _priorityLabel(task.priority),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: task.priority == 'urgent'
                          ? semantic.error
                          : task.priority == 'high'
                              ? semantic.warning
                              : semantic.textMuted,
                    ),
                  ),
                  if (task.status != 'not_started' &&
                      task.status != 'completed')
                    Text(
                      _statusLabel(task.status),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: task.status == 'cancelled'
                            ? semantic.error
                            : semantic.info,
                      ),
                    ),
                  if (task.scheduledDate != null)
                    Text(
                      'Plan: ${SharedDateFormatter.formatEthiopian(task.scheduledDate!.toEthiopian(), useAmharic: false, includeEra: false)}',
                      style:
                          TextStyle(fontSize: 11, color: semantic.textSecondary),
                    ),
                  if (task.dueDate != null)
                    Text(
                      'Due: ${SharedDateFormatter.formatEthiopian(task.dueDate!.toEthiopian(), useAmharic: false, includeEra: false)}',
                      style: TextStyle(fontSize: 11, color: colorScheme.primary),
                    ),
                  if (TaskRecurrenceEngine.resolveEffectiveConfig(task) != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.repeat,
                          size: 12,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          TaskRecurrenceEngine.formatSummary(
                            TaskRecurrenceEngine.resolveEffectiveConfig(task),
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            color: semantic.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  if (subs.isNotEmpty)
                    Text(
                      '$doneSubs of ${subs.length} subtasks (${task.subtaskProgressPercentage}%)',
                      style: TextStyle(
                        fontSize: 11,
                        color: semantic.textSecondary,
                      ),
                    ),
                  for (final l in task.labels)
                    Text(
                      '@$l',
                      style: TextStyle(fontSize: 11, color: semantic.transfer),
                    ),
                ],
              ),
              if (subs.isNotEmpty) ...[
                const SizedBox(height: SharedDesignTokens.spacingXs),
                DaywellProgressBar(
                  value: task.subtaskProgress,
                  minHeight: 5,
                  semanticLabel: 'Checklist progress for ${task.title}',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskDetailsSubtasksPanel extends StatefulWidget {
  final TaskEntity task;
  final TasksController controller;
  final void Function(String deletedTitle, List<TaskSubtask> previousList)
      onDeletedWithUndo;

  const _TaskDetailsSubtasksPanel({
    required this.task,
    required this.controller,
    required this.onDeletedWithUndo,
  });

  @override
  State<_TaskDetailsSubtasksPanel> createState() =>
      _TaskDetailsSubtasksPanelState();
}

class _TaskDetailsSubtasksPanelState extends State<_TaskDetailsSubtasksPanel> {
  final TextEditingController _addCtrl = TextEditingController();
  final TextEditingController _editCtrl = TextEditingController();
  String? _addError;
  String? _editingSubtaskId;
  String? _editError;

  @override
  void dispose() {
    _addCtrl.dispose();
    _editCtrl.dispose();
    super.dispose();
  }

  void _handleAdd() {
    final trimmed = _addCtrl.text.trim();
    if (trimmed.isEmpty) {
      setState(() => _addError = 'Subtask title is required');
      return;
    }
    unawaited(widget.controller.addSubtask(widget.task.id, trimmed));
    _addCtrl.clear();
    setState(() => _addError = null);
  }

  Future<void> _handleSaveEdit(String subtaskId) async {
    final trimmed = _editCtrl.text.trim();
    if (trimmed.isEmpty) {
      setState(() => _editError = 'Subtask title is required');
      return;
    }
    final ok = await widget.controller
        .editSubtaskTitle(widget.task.id, subtaskId, trimmed);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _editingSubtaskId = null;
        _editCtrl.clear();
        _editError = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return _SubtasksChecklistSection(
      subtasks: task.subtasks,
      progress: task.subtaskProgress,
      completedCount: task.completedSubtaskCount,
      addController: _addCtrl,
      addErrorText: _addError,
      editingSubtaskId: _editingSubtaskId,
      editController: _editCtrl,
      editErrorText: _editError,
      onAdd: _handleAdd,
      onAddTextChanged: () {
        if (_addError != null) setState(() => _addError = null);
      },
      onToggle: (index, done) =>
          unawaited(widget.controller.toggleSubtask(task.id, index, done)),
      onMove: (fromIdx, toIdx) =>
          unawaited(widget.controller.moveSubtask(task.id, fromIdx, toIdx)),
      onStartEdit: (item) {
        setState(() {
          _editingSubtaskId = item.id;
          _editCtrl.text = item.title;
          _editError = null;
        });
      },
      onSaveEdit: (subtaskId) => unawaited(_handleSaveEdit(subtaskId)),
      onCancelEdit: () {
        setState(() {
          _editingSubtaskId = null;
          _editCtrl.clear();
          _editError = null;
        });
      },
      onEditTextChanged: () {
        if (_editError != null) setState(() => _editError = null);
      },
      onDelete: (subtaskId) {
        final previousList = List<TaskSubtask>.from(task.subtasks);
        final deletedItem = task.subtasks.firstWhere(
          (s) => s.id == subtaskId,
          orElse: () => const TaskSubtask(id: '', title: 'subtask'),
        );
        unawaited(widget.controller.deleteSubtask(task.id, subtaskId));
        if (_editingSubtaskId == subtaskId) {
          setState(() {
            _editingSubtaskId = null;
            _editCtrl.clear();
            _editError = null;
          });
        }
        widget.onDeletedWithUndo(deletedItem.title, previousList);
      },
    );
  }
}

class _SubtasksChecklistSection extends StatelessWidget {
  final List<TaskSubtask> subtasks;
  final double progress;
  final int completedCount;
  final TextEditingController addController;
  final String? addErrorText;
  final String? editingSubtaskId;
  final TextEditingController editController;
  final String? editErrorText;
  final VoidCallback onAdd;
  final VoidCallback onAddTextChanged;
  final void Function(int index, bool done) onToggle;
  final void Function(int fromIndex, int toIndex) onMove;
  final void Function(TaskSubtask item) onStartEdit;
  final void Function(String subtaskId) onSaveEdit;
  final VoidCallback onCancelEdit;
  final VoidCallback onEditTextChanged;
  final void Function(String subtaskId) onDelete;

  const _SubtasksChecklistSection({
    required this.subtasks,
    required this.progress,
    required this.completedCount,
    required this.addController,
    required this.addErrorText,
    required this.editingSubtaskId,
    required this.editController,
    required this.editErrorText,
    required this.onAdd,
    required this.onAddTextChanged,
    required this.onToggle,
    required this.onMove,
    required this.onStartEdit,
    required this.onSaveEdit,
    required this.onCancelEdit,
    required this.onEditTextChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final pct = (progress * 100).round();

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Subtasks',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: semantic.textPrimary,
                    ),
              ),
              Text(
                subtasks.isNotEmpty
                    ? '$completedCount of ${subtasks.length} done ($pct%)'
                    : '0 subtasks',
                style: DaywellTypography.label(
                  color: semantic.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          if (subtasks.isNotEmpty) ...[
            DaywellProgressBar(
              value: progress,
              minHeight: 6,
              semanticLabel: 'Parent task subtask progress',
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
            for (int i = 0; i < subtasks.length; i++) ...[
              Container(
                margin: const EdgeInsets.only(bottom: SharedDesignTokens.spacingXs),
                padding: const EdgeInsets.symmetric(
                  horizontal: SharedDesignTokens.spacingXs,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: semantic.surfaceSubtle,
                  borderRadius:
                      BorderRadius.circular(SharedDesignTokens.radiusSm),
                  border: Border.all(color: semantic.border),
                ),
                child: editingSubtaskId == subtasks[i].id
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: editController,
                                  autofocus: true,
                                  decoration: const InputDecoration(
                                    hintText: 'Edit subtask title...',
                                    isDense: true,
                                    border: InputBorder.none,
                                  ),
                                  onChanged: (_) => onEditTextChanged(),
                                  onSubmitted: (_) => onSaveEdit(subtasks[i].id),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.check, size: 18),
                                tooltip: 'Save subtask',
                                onPressed: () => onSaveEdit(subtasks[i].id),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                tooltip: 'Cancel edit',
                                onPressed: onCancelEdit,
                              ),
                            ],
                          ),
                          if (editErrorText != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 4,
                                bottom: 4,
                              ),
                              child: Text(
                                editErrorText!,
                                style: DaywellTypography.caption(
                                  color: semantic.error,
                                ),
                              ),
                            ),
                        ],
                      )
                    : Row(
                        children: [
                          Checkbox(
                            value: subtasks[i].done,
                            onChanged: (v) => onToggle(i, v ?? false),
                          ),
                          Expanded(
                            child: Text(
                              subtasks[i].title,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: subtasks[i].done
                                        ? semantic.textMuted
                                        : semantic.textPrimary,
                                    decoration: subtasks[i].done
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_upward, size: 16),
                            tooltip: 'Move up',
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed:
                                i == 0 ? null : () => onMove(i, i - 1),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_downward, size: 16),
                            tooltip: 'Move down',
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: i == subtasks.length - 1
                                ? null
                                : () => onMove(i, i + 1),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            tooltip: 'Edit subtask',
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: () => onStartEdit(subtasks[i]),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: semantic.error,
                            ),
                            tooltip: 'Delete subtask',
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: () => onDelete(subtasks[i].id),
                          ),
                        ],
                      ),
              ),
            ],
          ] else ...[
            Text(
              'No subtasks yet. Add smaller steps below.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: semantic.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: addController,
                  decoration: InputDecoration(
                    hintText: 'Add a subtask...',
                    errorText: addErrorText,
                    isDense: true,
                  ),
                  onChanged: (_) => onAddTextChanged(),
                  onSubmitted: (_) => onAdd(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add subtask',
                onPressed: onAdd,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskDetailsTagsPanel extends StatefulWidget {
  final TaskEntity task;
  final TasksController controller;
  final VoidCallback onOpenManageTags;

  const _TaskDetailsTagsPanel({
    required this.task,
    required this.controller,
    required this.onOpenManageTags,
  });

  @override
  State<_TaskDetailsTagsPanel> createState() => _TaskDetailsTagsPanelState();
}

class _TaskDetailsTagsPanelState extends State<_TaskDetailsTagsPanel> {
  final TextEditingController _tagCtrl = TextEditingController();
  String? _tagError;

  @override
  void dispose() {
    _tagCtrl.dispose();
    super.dispose();
  }

  void _addTag([String? rawOverride]) {
    final normalized =
        TasksModuleState.normalizeLabel(rawOverride ?? _tagCtrl.text);
    if (normalized.isEmpty) {
      setState(() => _tagError = 'Tag name is required');
      return;
    }
    final nextLabels = TasksModuleState.normalizeLabels([
      ...widget.task.labels,
      normalized,
    ]);
    unawaited(widget.controller.updateLabels(widget.task.id, nextLabels));
    if (rawOverride == null) {
      _tagCtrl.clear();
    }
    setState(() => _tagError = null);
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final assigned = widget.task.labels;
    final suggestions = widget.controller.state.availableTags
        .where(
          (tag) => !assigned.any(
            (cur) =>
                TasksModuleState.normalizeLabel(cur).toLowerCase() ==
                tag.toLowerCase(),
          ),
        )
        .toList(growable: false);

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tags',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: semantic.textPrimary,
                    ),
              ),
              TextButton(
                onPressed: widget.onOpenManageTags,
                child: const Text('Manage tags'),
              ),
            ],
          ),
          if (assigned.isNotEmpty) ...[
            const SizedBox(height: SharedDesignTokens.spacingXs),
            Wrap(
              spacing: SharedDesignTokens.spacingXs,
              runSpacing: SharedDesignTokens.spacingXs,
              children: [
                for (final lbl in assigned)
                  InputChip(
                    label: Text('@$lbl'),
                    onDeleted: () {
                      final next = assigned
                          .where(
                            (x) =>
                                TasksModuleState.normalizeLabel(x)
                                    .toLowerCase() !=
                                TasksModuleState.normalizeLabel(lbl)
                                    .toLowerCase(),
                          )
                          .toList(growable: false);
                      unawaited(
                        widget.controller.updateLabels(widget.task.id, next),
                      );
                    },
                  ),
              ],
            ),
          ] else ...[
            const SizedBox(height: SharedDesignTokens.spacingXs),
            Text(
              'No tags assigned yet.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: semantic.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ],
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tagCtrl,
                  decoration: InputDecoration(
                    hintText: 'Add tag...',
                    errorText: _tagError,
                    isDense: true,
                  ),
                  onChanged: (_) {
                    if (_tagError != null) setState(() => _tagError = null);
                  },
                  onSubmitted: (_) => _addTag(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add tag',
                onPressed: () => _addTag(),
              ),
            ],
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: SharedDesignTokens.spacingXs),
            Wrap(
              spacing: SharedDesignTokens.spacingXs,
              runSpacing: SharedDesignTokens.spacingXs,
              children: [
                for (final tag in suggestions)
                  ActionChip(
                    label: Text('+ @$tag'),
                    onPressed: () => _addTag(tag),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
