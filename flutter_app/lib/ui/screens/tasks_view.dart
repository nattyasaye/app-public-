import 'dart:async';
import 'package:flutter/material.dart';
import '../../application/projects/projects_controller.dart';
import '../../application/tasks/tasks_controller.dart';
import '../../application/tasks/tasks_state.dart';
import '../../core/date/shared_date.dart';
import '../../core/shared_foundation.dart';
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

  void _toggleCompleteWithUndo(TaskEntity task, TasksController controller) {
    final wasCompleted = task.isCompleted;
    unawaited(controller.toggleTaskStatus(task.id));
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
          onPressed: () => unawaited(controller.toggleTaskStatus(task.id)),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showQuickAddModal() {
    final controller = widget.effectiveController;
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    int priority = 4;
    String? selectedProjectId;
    CalendarDate? dueDate =
        controller.state.viewFilter == 'today' ? CalendarDate.today() : null;
    String recurrence = 'none';
    final List<String> labels = [];
    final labelCtrl = TextEditingController();
    final projects = controller.state.projects;

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) => Padding(
            padding: EdgeInsets.only(
              top: 20,
              left: 20,
              right: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Quick Add Task',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Submit report tomorrow',
                      labelText: 'Task Title *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.today, size: 16),
                        label: const Text('Today'),
                        onPressed: () =>
                            setModalState(() => dueDate = CalendarDate.today()),
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
                      if (dueDate != null)
                        ActionChip(
                          avatar: const Icon(Icons.clear, size: 16),
                          label: const Text('Clear Date'),
                          onPressed: () => setModalState(() => dueDate = null),
                        ),
                    ],
                  ),
                  if (dueDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Due: ${SharedDateFormatter.formatDual(dueDate!, useAmharic: false)}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: SharedDesignTokens.primaryEmerald,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: priority,
                          decoration: const InputDecoration(
                              labelText: 'Priority',
                              border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(
                                value: 1, child: Text('P1 Urgent')),
                            DropdownMenuItem(value: 2, child: Text('P2 High')),
                            DropdownMenuItem(
                                value: 3, child: Text('P3 Medium')),
                            DropdownMenuItem(
                                value: 4, child: Text('P4 Normal')),
                          ],
                          onChanged: (v) {
                            if (v != null) setModalState(() => priority = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: recurrence,
                          decoration: const InputDecoration(
                              labelText: 'Repeat',
                              border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(
                                value: 'none', child: Text('No Repeat')),
                            DropdownMenuItem(
                                value: 'daily', child: Text('Daily')),
                            DropdownMenuItem(
                                value: 'weekly', child: Text('Weekly')),
                            DropdownMenuItem(
                                value: 'monthly', child: Text('Monthly')),
                          ],
                          onChanged: (v) {
                            if (v != null) setModalState(() => recurrence = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (projects.isNotEmpty)
                    DropdownButtonFormField<String?>(
                      value: selectedProjectId,
                      decoration: const InputDecoration(
                          labelText: 'Project (Inbox if none)',
                          border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Inbox')),
                        ...projects.map((p) => DropdownMenuItem<String?>(
                            value: p.id, child: Text(p.title))),
                      ],
                      onChanged: (v) =>
                          setModalState(() => selectedProjectId = v),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: labelCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Add @label (e.g. work)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () {
                          final lbl = labelCtrl.text.trim().replaceAll('@', '');
                          if (lbl.isNotEmpty && !labels.contains(lbl)) {
                            setModalState(() => labels.add(lbl));
                            labelCtrl.clear();
                          }
                        },
                      ),
                    ],
                  ),
                  if (labels.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      children: labels
                          .map((l) => Chip(
                                label: Text('@$l',
                                    style: const TextStyle(fontSize: 11)),
                                onDeleted: () =>
                                    setModalState(() => labels.remove(l)),
                              ))
                          .toList(),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final title = titleCtrl.text.trim();
                        if (title.isEmpty) return;
                        final priorityStr = priority == 1
                            ? 'urgent'
                            : priority == 2
                                ? 'high'
                                : priority == 3
                                    ? 'medium'
                                    : 'low';
                        await controller.createTask(
                          title: title,
                          description: descCtrl.text.trim().isEmpty
                              ? null
                              : descCtrl.text.trim(),
                          priority: priorityStr,
                          dueDate: dueDate,
                          projectId: selectedProjectId,
                          labels: List<String>.from(labels),
                          isMyDay: controller.state.viewFilter == 'my_day',
                          recurrenceRule:
                              recurrence == 'none' ? null : recurrence,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Save Task'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showTaskDetails(TaskEntity initialTask, TasksController controller) {
    final subtaskCtrl = TextEditingController();
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final task =
                controller.state.findTaskById(initialTask.id) ?? initialTask;
            final subs = task.subtasks;

            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(task.title,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                        IconButton(
                          icon: Icon(task.isPinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined),
                          tooltip: 'Pin Task',
                          onPressed: () =>
                              unawaited(controller.togglePin(task.id)),
                        ),
                        IconButton(
                          icon: Icon(
                            task.isMyDay
                                ? Icons.wb_sunny
                                : Icons.wb_sunny_outlined,
                            color: task.isMyDay ? Colors.amber : null,
                          ),
                          tooltip: 'Add to My Day',
                          onPressed: () =>
                              unawaited(controller.toggleMyDay(task.id)),
                        ),
                      ],
                    ),
                    if (task.description != null &&
                        task.description!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(task.description!,
                          style: TextStyle(color: Colors.grey.shade700)),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        Chip(
                          label: Text(task.priority.toUpperCase(),
                              style: const TextStyle(fontSize: 11)),
                          avatar: Icon(
                            Icons.flag,
                            size: 14,
                            color: task.priority == 'urgent'
                                ? Colors.red
                                : task.priority == 'high'
                                    ? Colors.orange
                                    : Colors.blue,
                          ),
                        ),
                        if (task.recurrenceRule != null &&
                            task.recurrenceRule!.isNotEmpty)
                          Chip(
                            label: Text('Repeats ${task.recurrenceRule}',
                                style: const TextStyle(fontSize: 11)),
                            avatar: const Icon(Icons.repeat, size: 14),
                          ),
                        for (final lbl in task.labels)
                          Chip(
                            label: Text('@$lbl',
                                style: const TextStyle(fontSize: 11)),
                          ),
                      ],
                    ),
                    const Divider(height: 24),
                    const Text('Subtasks',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    for (int i = 0; i < subs.length; i++)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: subs[i].done,
                        title: Text(
                          subs[i].title,
                          style: TextStyle(
                            decoration: subs[i].done
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        onChanged: (v) => unawaited(
                          controller.toggleSubtask(task.id, i, v ?? false),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: subtaskCtrl,
                            decoration: const InputDecoration(
                              hintText: 'Add a subtask...',
                              isDense: true,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            final txt = subtaskCtrl.text.trim();
                            if (txt.isNotEmpty) {
                              unawaited(controller.addSubtask(task.id, txt));
                              subtaskCtrl.clear();
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            unawaited(controller.deleteTask(task.id));
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          label: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                        FilledButton(
                          onPressed: () {
                            _toggleCompleteWithUndo(task, controller);
                            Navigator.pop(ctx);
                          },
                          child: Text(
                            task.isCompleted ? 'Reopen Task' : 'Complete Task',
                          ),
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
            foregroundColor: isDark ? Colors.black : Colors.white,
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
                          ('my_day', 'My Day'),
                          ('completed', 'Completed'),
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
                                : 'No tasks in ${moduleState.viewFilter}',
                            actionLabel: 'Add Task',
                            onActionPressed: _showQuickAddModal,
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

    return Dismissible(
      key: ValueKey(task.id),
      background: Container(
        color: Colors.green,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.check, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          _toggleCompleteWithUndo(task, controller);
          return false;
        }
        await controller.deleteTask(task.id);
        return true;
      },
      child: Card(
        elevation: 0,
        color: isSelected ? SharedDesignTokens.secondaryMint : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
          side: BorderSide(color: Colors.grey.withOpacity(0.2)),
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
            activeColor: SharedDesignTokens.primaryEmerald,
            side: BorderSide(
              color: task.priority == 'urgent'
                  ? Colors.red
                  : task.priority == 'high'
                      ? Colors.orange
                      : Colors.grey,
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
                const Icon(Icons.push_pin_rounded,
                    size: 15, color: SharedDesignTokens.primaryEmerald),
            ],
          ),
          subtitle: Wrap(
            spacing: 8,
            children: [
              if (task.dueDate != null)
                Text(
                  SharedDateFormatter.formatEthiopian(
                    task.dueDate!.toEthiopian(),
                    useAmharic: false,
                    includeEra: false,
                  ),
                  style: const TextStyle(
                      fontSize: 11, color: SharedDesignTokens.primaryEmerald),
                ),
              if (subs.isNotEmpty)
                Text('$doneSubs/${subs.length} subtasks',
                    style: const TextStyle(fontSize: 11)),
              for (final l in task.labels)
                Text('@$l',
                    style: const TextStyle(fontSize: 11, color: Colors.teal)),
            ],
          ),
        ),
      ),
    );
  }

}
