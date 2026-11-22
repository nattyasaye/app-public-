import 'dart:async';
import 'package:flutter/material.dart';
import '../../application/projects/projects_controller.dart';
import '../../application/tasks/tasks_controller.dart';
import '../../application/tasks/tasks_state.dart';
import '../../core/date/shared_date.dart';
import '../../core/shared_foundation.dart';
import '../../core/theme/daywell_theme.dart';
import '../../domain/tasks/task_models.dart';
import '../app_state.dart';
import '../widgets/shared_ui_widgets.dart';
import 'projects/project_form_sheet.dart';
import 'projects/projects_workspace_tab.dart';

class TasksView extends StatefulWidget {
  final AppStateManager? state;
  final TasksController? controller;
  final ProjectsController? projectsController;

  const TasksView({
    super.key,
    this.state,
    this.controller,
    this.projectsController,
  }) : assert(
          state != null || controller != null,
          'Either state or controller must be provided to TasksView',
        );

  TasksController get effectiveController =>
      controller ?? state!.tasksController;

  ProjectsController? get effectiveProjectsController =>
      projectsController ?? state?.projectsController;

  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _searchController = TextEditingController(
      text: widget.effectiveController.state.searchQuery,
    );
  }

  @override
  void dispose() {
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

  void _toggleCompleteWithUndo(TaskEntity task, TasksController controller) {
    final wasCompleted = task.isCompleted;
    final projectsCtrl = widget.effectiveProjectsController;
    unawaited(() async {
      await controller.toggleTaskStatus(task.id);
      final updated = controller.state.findTaskById(task.id);
      if (projectsCtrl != null &&
          updated != null &&
          updated.projectId != null) {
        await projectsCtrl.syncTaskSectionLink(updated.projectId!, updated);
      }
    }());
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasCompleted
              ? 'Reopened "${task.title}"'
              : 'Completed "${task.title}"',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(() async {
              await controller.toggleTaskStatus(task.id);
              final reverted = controller.state.findTaskById(task.id);
              if (projectsCtrl != null &&
                  reverted != null &&
                  reverted.projectId != null) {
                await projectsCtrl.syncTaskSectionLink(
                  reverted.projectId!,
                  reverted,
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
              await controller.restoreDeletedTask(task);
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

  void _showTaskFormModal({TaskEntity? existingTask}) {
    final controller = widget.effectiveController;
    final isEditing = existingTask != null;
    final titleCtrl = TextEditingController(text: existingTask?.title ?? '');
    final descCtrl =
        TextEditingController(text: existingTask?.description ?? '');
    String priority = existingTask?.priority ?? 'medium';
    String status = existingTask?.status ??
        (controller.state.viewFilter == 'inbox' ? 'inbox' : 'not_started');
    String? selectedProjectId = existingTask?.projectId;
    String? selectedMilestoneId = existingTask?.milestoneId;
    CalendarDate? scheduledDate = existingTask != null
        ? existingTask.scheduledDate
        : (controller.state.viewFilter == 'today'
            ? CalendarDate.today()
            : null);
    CalendarDate? dueDate = existingTask != null
        ? existingTask.dueDate
        : (controller.state.viewFilter == 'today'
            ? CalendarDate.today()
            : null);
    String? titleError;
    final projects = controller.state.projects;
    var modalSubtasks = List<TaskSubtask>.from(existingTask?.subtasks ?? const []);
    final modalSubtaskAddCtrl = TextEditingController();
    final modalSubtaskEditCtrl = TextEditingController();
    String? modalSubtaskAddError;
    String? editingModalSubtaskId;
    String? modalSubtaskEditError;

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
                      isEditing ? 'Edit Task' : 'New Task',
                      style: Theme.of(modalContext).textTheme.titleLarge,
                    ),
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
                      label: isEditing ? 'Save Changes' : 'Save Task',
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
                        final resolvedMilestoneId =
                            selectedProjectId != null ? selectedMilestoneId : null;
                        final projectsCtrl = widget.effectiveProjectsController;
                        if (isEditing) {
                          final updated = await controller.updateTask(
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
                          );
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
                        } else {
                          await controller.createTask(
                            title: title,
                            description: desc.isEmpty ? null : desc,
                            priority: priority,
                            status: status,
                            dueDate: dueDate,
                            scheduledDate: scheduledDate,
                            projectId: selectedProjectId,
                            milestoneId: resolvedMilestoneId,
                            subtasks: modalSubtasks,
                            isMyDay: controller.state.viewFilter == 'my_day',
                          );
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
                            task.isMyDay
                                ? Icons.wb_sunny
                                : Icons.wb_sunny_outlined,
                            color: task.isMyDay ? semantic.warning : null,
                          ),
                          tooltip: 'Add to My Day',
                          onPressed: () =>
                              unawaited(controller.toggleMyDay(task.id)),
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

  @override
  Widget build(BuildContext context) {
    final controller = widget.effectiveController;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark
        ? SharedDesignTokens.primaryDarkMode
        : SharedDesignTokens.primaryEmerald;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final moduleState = controller.state;
        final tasks = moduleState.filteredTasks;

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
                      onSelected: controller.setSortBy,
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'due', child: Text('Sort by Due Date')),
                        PopupMenuItem(
                            value: 'priority', child: Text('Sort by Priority')),
                        PopupMenuItem(
                            value: 'alpha', child: Text('Sort Alphabetically')),
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
                    final projectsCtrl = widget.effectiveProjectsController;
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
            backgroundColor: primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            icon: const Icon(Icons.add),
            label: Text(_tabController.index == 1 ? 'New Project' : 'Add Task'),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search tasks or @labels...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: moduleState.searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  controller.setSearchQuery('');
                                },
                              )
                            : null,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                      onChanged: controller.setSearchQuery,
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
                          ('inbox', 'Inbox'),
                          ('upcoming', 'Upcoming'),
                          ('all', 'All'),
                          ('my_day', 'My Day'),
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
                  const Divider(height: 1),
                  Expanded(
                    child: tasks.isEmpty
                        ? DaywellEmptyState(
                            icon: Icons.check_circle_outline,
                            message: moduleState.searchQuery.isNotEmpty
                                ? 'No tasks match "${moduleState.searchQuery}"'
                                : moduleState.viewFilter == 'archived'
                                    ? 'No archived tasks'
                                    : 'No tasks in ${moduleState.viewFilter}',
                            actionLabel: moduleState.viewFilter == 'archived'
                                ? null
                                : 'Add Task',
                            onActionPressed: moduleState.viewFilter == 'archived'
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
                projectsController: widget.effectiveProjectsController,
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
          _toggleCompleteWithUndo(task, controller);
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
            onChanged: (_) => _toggleCompleteWithUndo(task, controller),
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
              : null,
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
