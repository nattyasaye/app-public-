import 'package:flutter/foundation.dart';
import '../../core/date/shared_date.dart';
import '../../domain/tasks/task_models.dart';
import '../../domain/tasks/task_contracts.dart';
import 'tasks_state.dart';

/// Module-scoped application controller for Daywell To-Do and Projects.
///
/// Sole owner of Tasks/Projects/Milestones module state, hydrated from and
/// persisted directly to [ITasksRepository] (authoritative Drift SQLite).
class TasksController extends ChangeNotifier {
  final ITasksRepository _repository;
  TasksModuleState _state;
  bool _isDisposed = false;

  TasksController({
    required ITasksRepository repository,
    TasksModuleState? initialState,
  })  : _repository = repository,
        _state = initialState ?? const TasksModuleState();

  TasksModuleState get state => _state;

  // --- Hydration ---

  Future<void> loadAll() async {
    _state = _state.copyWith(isLoading: true, clearError: true);
    notifyListeners();
    try {
      final loadedTasks = await _repository.getTasks();
      final loadedProjects = await _repository.getProjects();
      final loadedMilestones = await _repository.getAllMilestones();

      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(loadedTasks),
        projects: List<ProjectEntity>.unmodifiable(loadedProjects),
        milestones: List<MilestoneEntity>.unmodifiable(loadedMilestones),
        isLoading: false,
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
    notifyListeners();
  }

  // --- Presentation Filter & View Controls ---

  void setViewFilter(String filter) {
    _state = _state.copyWith(viewFilter: filter);
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _state = _state.copyWith(searchQuery: query);
    notifyListeners();
  }

  void setSortBy(String sortBy) {
    _state = _state.copyWith(sortBy: sortBy);
    notifyListeners();
  }

  void setStatusFilter(String? status) {
    if (status == null) {
      _state = _state.copyWith(clearStatusFilter: true);
    } else {
      _state = _state.copyWith(statusFilter: status);
    }
    notifyListeners();
  }

  void setPriorityFilter(String? priority) {
    if (priority == null) {
      _state = _state.copyWith(clearPriorityFilter: true);
    } else {
      _state = _state.copyWith(priorityFilter: priority);
    }
    notifyListeners();
  }

  void setDueDateFilter(String? dueDateFilter) {
    if (dueDateFilter == null) {
      _state = _state.copyWith(clearDueDateFilter: true);
    } else {
      _state = _state.copyWith(dueDateFilter: dueDateFilter);
    }
    notifyListeners();
  }

  void selectProject(String? projectId) {
    if (projectId == null) {
      _state = _state.copyWith(
        clearSelectedProject: true,
        clearSectionFilter: true,
      );
    } else {
      _state = _state.copyWith(
        selectedProjectId: projectId,
        clearSectionFilter: _state.selectedProjectId != projectId,
      );
    }
    notifyListeners();
  }

  void setSectionFilter(String? sectionId) {
    if (sectionId == null || sectionId.trim().isEmpty) {
      _state = _state.copyWith(clearSectionFilter: true);
    } else {
      _state = _state.copyWith(sectionFilter: sectionId.trim());
    }
    notifyListeners();
  }

  void toggleTagFilter(String rawTag) {
    final normalized = TasksModuleState.normalizeLabel(rawTag);
    if (normalized.isEmpty) return;
    final key = normalized.toLowerCase();
    final next = <String>{};
    var removed = false;
    for (final existing in _state.tagFilters) {
      if (existing.toLowerCase() == key) {
        removed = true;
      } else {
        next.add(existing);
      }
    }
    if (!removed) {
      next.add(normalized);
    }
    _state = _state.copyWith(tagFilters: Set<String>.unmodifiable(next));
    notifyListeners();
  }

  void setTagFilters(Set<String> tags) {
    final normalized = TasksModuleState.normalizeLabels(tags).toSet();
    _state = _state.copyWith(tagFilters: Set<String>.unmodifiable(normalized));
    notifyListeners();
  }

  void toggleBoardView() {
    _state = _state.copyWith(isBoardView: !_state.isBoardView);
    notifyListeners();
  }

  void toggleTaskSelection(String taskId) {
    final next = Set<String>.from(_state.selectedTaskIds);
    if (next.contains(taskId)) {
      next.remove(taskId);
    } else {
      next.add(taskId);
    }
    _state = _state.copyWith(selectedTaskIds: next);
    notifyListeners();
  }

  void clearSelection() {
    _state = _state.copyWith(selectedTaskIds: const {});
    notifyListeners();
  }

  void clearFilters({bool resetView = true}) {
    _state = _state.copyWith(
      viewFilter: resetView ? 'today' : _state.viewFilter,
      searchQuery: '',
      sortBy: resetView ? 'due' : _state.sortBy,
      clearStatusFilter: true,
      clearPriorityFilter: true,
      clearDueDateFilter: true,
      clearSelectedProject: true,
      clearSectionFilter: true,
      tagFilters: const {},
      selectedTaskIds: const {},
    );
    notifyListeners();
  }

  // --- Persisted Task Metadata Workflows ---

  Future<void> togglePin(String taskId) async {
    final existing = _state.findTaskById(taskId);
    if (existing == null) return;
    await _persistUpdatedTask(existing.copyWith(isPinned: !existing.isPinned));
  }

  Future<void> toggleMyDay(String taskId) async {
    final existing = _state.findTaskById(taskId);
    if (existing == null) return;
    await _persistUpdatedTask(existing.copyWith(isMyDay: !existing.isMyDay));
  }

  Future<void> updateLabels(String taskId, List<String> labels) async {
    final existing =
        _state.findTaskById(taskId) ?? await _repository.getTaskById(taskId);
    if (existing == null) return;
    final normalized = TasksModuleState.normalizeLabels(labels);
    final nextCustom =
        TasksModuleState.normalizeLabels([..._state.customTags, ...normalized]);
    _state = _state.copyWith(customTags: nextCustom);
    await _persistUpdatedTask(
      existing.copyWith(
        labels: normalized,
        updatedAt: EthiopiaClock.nowUtc(),
      ),
    );
  }

  bool createTag(String rawLabel) {
    final normalized = TasksModuleState.normalizeLabel(rawLabel);
    if (normalized.isEmpty) {
      _state = _state.copyWith(errorMessage: 'Tag name is required');
      notifyListeners();
      return false;
    }
    final alreadyExists = _state.availableTags.any(
      (t) => t.toLowerCase() == normalized.toLowerCase(),
    );
    if (alreadyExists) {
      _state = _state.copyWith(errorMessage: 'Tag "@$normalized" already exists');
      notifyListeners();
      return false;
    }
    final nextCustom =
        TasksModuleState.normalizeLabels([..._state.customTags, normalized]);
    _state = _state.copyWith(customTags: nextCustom, clearError: true);
    notifyListeners();
    return true;
  }

  Future<bool> renameTag(String oldLabel, String newLabel) async {
    final oldNorm = TasksModuleState.normalizeLabel(oldLabel);
    final newNorm = TasksModuleState.normalizeLabel(newLabel);
    if (oldNorm.isEmpty || newNorm.isEmpty) {
      _state = _state.copyWith(errorMessage: 'Tag name is required');
      notifyListeners();
      return false;
    }
    final oldKey = oldNorm.toLowerCase();
    final now = EthiopiaClock.nowUtc();

    try {
      for (final task in _state.tasks) {
        final hasTag = task.labels.any(
          (l) => TasksModuleState.normalizeLabel(l).toLowerCase() == oldKey,
        );
        if (!hasTag) continue;
        final replaced = TasksModuleState.normalizeLabels(
          task.labels.map(
            (l) => TasksModuleState.normalizeLabel(l).toLowerCase() == oldKey
                ? newNorm
                : l,
          ),
        );
        await _repository.updateTask(
          task.copyWith(labels: replaced, updatedAt: now),
        );
      }

      final nextCustom = TasksModuleState.normalizeLabels(
        _state.customTags.map(
          (t) => t.toLowerCase() == oldKey ? newNorm : t,
        ),
      );
      final nextTagFilters = TasksModuleState.normalizeLabels(
        _state.tagFilters.map(
          (t) => TasksModuleState.normalizeLabel(t).toLowerCase() == oldKey
              ? newNorm
              : t,
        ),
      ).toSet();

      final updatedTasks = await _repository.getTasks();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        customTags: nextCustom,
        tagFilters: Set<String>.unmodifiable(nextTagFilters),
        clearError: true,
      );
      notifyListeners();
      return true;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return false;
    }
  }

  Future<int> deleteTag(String targetLabel) async {
    final targetNorm = TasksModuleState.normalizeLabel(targetLabel);
    if (targetNorm.isEmpty) return 0;
    final targetKey = targetNorm.toLowerCase();
    final now = EthiopiaClock.nowUtc();
    var affectedTasks = 0;

    try {
      for (final task in _state.tasks) {
        final existing = TasksModuleState.normalizeLabels(task.labels);
        final filtered = existing
            .where((l) => l.toLowerCase() != targetKey)
            .toList(growable: false);
        if (filtered.length == existing.length) continue;
        affectedTasks += 1;
        await _repository.updateTask(
          task.copyWith(labels: filtered, updatedAt: now),
        );
      }

      final nextCustom = _state.customTags
          .where((t) => t.toLowerCase() != targetKey)
          .toList(growable: false);
      final nextTagFilters = _state.tagFilters
          .where((t) => TasksModuleState.normalizeLabel(t).toLowerCase() != targetKey)
          .toSet();

      final updatedTasks = await _repository.getTasks();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        customTags: List<String>.unmodifiable(nextCustom),
        tagFilters: Set<String>.unmodifiable(nextTagFilters),
        clearError: true,
      );
      notifyListeners();
      return affectedTasks;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return 0;
    }
  }

  Future<void> restoreTasksLabelsSnapshot(
    List<TaskEntity> previousTasks, {
    List<String>? previousCustomTags,
    Set<String>? previousTagFilters,
  }) async {
    try {
      for (final prevTask in previousTasks) {
        final current = await _repository.getTaskById(prevTask.id);
        if (current != null) {
          await _repository.updateTask(
            current.copyWith(
              labels: prevTask.labels,
              updatedAt: EthiopiaClock.nowUtc(),
            ),
          );
        }
      }
      final updatedTasks = await _repository.getTasks();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        customTags: previousCustomTags ?? _state.customTags,
        tagFilters: previousTagFilters ?? _state.tagFilters,
        clearError: true,
      );
      notifyListeners();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> addSubtask(String taskId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      _state = _state.copyWith(errorMessage: 'Subtask title is required');
      notifyListeners();
      return;
    }
    final existing =
        _state.findTaskById(taskId) ?? await _repository.getTaskById(taskId);
    if (existing == null) return;
    final nextSubtasks = [
      ...existing.subtasks,
      TaskSubtask(
        id: TaskSubtask.nextId(taskId, existing.subtasks),
        title: trimmed,
        done: false,
      ),
    ];
    await _persistUpdatedTask(
      existing.copyWith(
        subtasks: nextSubtasks,
        updatedAt: EthiopiaClock.nowUtc(),
      ),
    );
  }

  Future<void> toggleSubtask(String taskId, int index, bool done) async {
    final existing =
        _state.findTaskById(taskId) ?? await _repository.getTaskById(taskId);
    if (existing == null || index < 0 || index >= existing.subtasks.length) {
      return;
    }
    final nextSubtasks = List<TaskSubtask>.from(existing.subtasks);
    nextSubtasks[index] = nextSubtasks[index].copyWith(done: done);
    await _persistUpdatedTask(
      existing.copyWith(
        subtasks: nextSubtasks,
        updatedAt: EthiopiaClock.nowUtc(),
      ),
    );
  }

  Future<void> toggleSubtaskById(String taskId, String subtaskId) async {
    final existing =
        _state.findTaskById(taskId) ?? await _repository.getTaskById(taskId);
    if (existing == null) return;
    final nextSubtasks = [
      for (final st in existing.subtasks)
        if (st.id == subtaskId) st.copyWith(done: !st.done) else st,
    ];
    await _persistUpdatedTask(
      existing.copyWith(
        subtasks: nextSubtasks,
        updatedAt: EthiopiaClock.nowUtc(),
      ),
    );
  }

  Future<bool> editSubtaskTitle(
    String taskId,
    String subtaskId,
    String newTitle,
  ) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) {
      _state = _state.copyWith(errorMessage: 'Subtask title is required');
      notifyListeners();
      return false;
    }
    final existing =
        _state.findTaskById(taskId) ?? await _repository.getTaskById(taskId);
    if (existing == null) return false;
    final nextSubtasks = [
      for (final st in existing.subtasks)
        if (st.id == subtaskId) st.copyWith(title: trimmed) else st,
    ];
    await _persistUpdatedTask(
      existing.copyWith(
        subtasks: nextSubtasks,
        updatedAt: EthiopiaClock.nowUtc(),
      ),
    );
    return true;
  }

  Future<void> deleteSubtask(String taskId, String subtaskId) async {
    final existing =
        _state.findTaskById(taskId) ?? await _repository.getTaskById(taskId);
    if (existing == null) return;
    final nextSubtasks = existing.subtasks
        .where((st) => st.id != subtaskId)
        .toList(growable: false);
    await _persistUpdatedTask(
      existing.copyWith(
        subtasks: nextSubtasks,
        updatedAt: EthiopiaClock.nowUtc(),
      ),
    );
  }

  Future<void> restoreSubtasks(
    String taskId,
    List<TaskSubtask> previousSubtasks,
  ) async {
    final existing =
        _state.findTaskById(taskId) ?? await _repository.getTaskById(taskId);
    if (existing == null) return;
    await _persistUpdatedTask(
      existing.copyWith(
        subtasks: TaskSubtask.normalizeList(previousSubtasks, taskId: taskId),
        updatedAt: EthiopiaClock.nowUtc(),
      ),
    );
  }

  Future<void> moveSubtask(String taskId, int fromIndex, int toIndex) async {
    final existing =
        _state.findTaskById(taskId) ?? await _repository.getTaskById(taskId);
    if (existing == null) return;
    if (fromIndex < 0 ||
        fromIndex >= existing.subtasks.length ||
        toIndex < 0 ||
        toIndex >= existing.subtasks.length ||
        fromIndex == toIndex) {
      return;
    }
    final reordered = TaskSubtask.reorderList(
      existing.subtasks,
      fromIndex,
      toIndex,
    );
    await _persistUpdatedTask(
      existing.copyWith(
        subtasks: reordered,
        updatedAt: EthiopiaClock.nowUtc(),
      ),
    );
  }

  Future<void> updateRecurrence(String taskId, String? recurrenceRule) async {
    final existing = _state.findTaskById(taskId);
    if (existing == null) return;
    await _persistUpdatedTask(
        existing.copyWith(recurrenceRule: recurrenceRule));
  }

  Future<void> _persistUpdatedTask(TaskEntity updated) async {
    try {
      await _repository.updateTask(updated);
      final updatedTasks = await _repository.getTasks();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  // --- Task Workflow Orchestration ---

  static const Set<String> _validStatuses = {
    'inbox',
    'not_started',
    'in_progress',
    'completed',
    'cancelled',
  };

  static const Set<String> _validPriorities = {
    'low',
    'medium',
    'high',
    'urgent',
  };

  Future<TaskEntity?> createTask({
    String? id,
    required String title,
    String? description,
    String priority = 'medium',
    String status = 'not_started',
    CalendarDate? dueDate,
    CalendarDate? scheduledDate,
    String? scheduledTime,
    int? estimatedDurationMinutes,
    String? projectId,
    String? milestoneId,
    List<TaskSubtask> subtasks = const [],
    List<String> labels = const [],
    bool isPinned = false,
    bool isMyDay = false,
    CalendarDate? myDayDate,
    String? recurrenceRule,
    TaskRecurrenceConfig? recurrenceConfig,
    bool isArchived = false,
    int sortOrder = 0,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      _state = _state.copyWith(errorMessage: 'Task title is required');
      notifyListeners();
      return null;
    }

    final normalizedStatus =
        _validStatuses.contains(status) ? status : 'not_started';
    final normalizedPriority =
        _validPriorities.contains(priority) ? priority : 'medium';
    final trimmedDescription = description?.trim();

    final now = EthiopiaClock.nowUtc();
    final resolvedTaskId = id ?? 'task-${now.millisecondsSinceEpoch}';
    final task = TaskEntity(
      id: resolvedTaskId,
      title: trimmedTitle,
      description:
          (trimmedDescription == null || trimmedDescription.isEmpty)
              ? null
              : trimmedDescription,
      priority: normalizedPriority,
      status: normalizedStatus,
      completedAt: normalizedStatus == 'completed' ? now : null,
      dueDate: dueDate,
      scheduledDate: scheduledDate,
      scheduledTime: scheduledTime,
      estimatedDurationMinutes: estimatedDurationMinutes,
      projectId: projectId,
      milestoneId: milestoneId,
      subtasks: TaskSubtask.normalizeList(subtasks, taskId: resolvedTaskId),
      labels: TasksModuleState.normalizeLabels(labels),
      isPinned: isPinned,
      isMyDay: isMyDay,
      myDayDate: myDayDate,
      recurrenceRule: recurrenceRule,
      recurrenceConfig: recurrenceConfig,
      isArchived: isArchived,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );

    try {
      final created = await _repository.createTask(task);
      final updatedTasks = await _repository.getTasks();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        clearError: true,
      );
      notifyListeners();
      return created;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<TaskEntity?> updateTask({
    required String id,
    required String title,
    String? description,
    bool clearDescription = false,
    String? priority,
    String? status,
    CalendarDate? dueDate,
    bool clearDueDate = false,
    CalendarDate? scheduledDate,
    bool clearScheduledDate = false,
    String? scheduledTime,
    bool clearScheduledTime = false,
    String? projectId,
    bool clearProject = false,
    String? milestoneId,
    bool clearMilestone = false,
    List<TaskSubtask>? subtasks,
    List<String>? labels,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      _state = _state.copyWith(errorMessage: 'Task title is required');
      notifyListeners();
      return null;
    }

    final existing =
        _state.findTaskById(id) ?? await _repository.getTaskById(id);
    if (existing == null) return null;

    final now = EthiopiaClock.nowUtc();
    final nextStatus = status != null && _validStatuses.contains(status)
        ? status
        : existing.status;
    final nextPriority = priority != null && _validPriorities.contains(priority)
        ? priority
        : existing.priority;
    final nextCompletedAt =
        nextStatus == 'completed' ? (existing.completedAt ?? now) : null;
    final trimmedDesc = description?.trim();
    final shouldClearDesc =
        clearDescription || (description != null && trimmedDesc!.isEmpty);
    final nextProjectId = clearProject ? null : (projectId ?? existing.projectId);
    final projectChanged = nextProjectId != existing.projectId;
    final shouldClearMilestone =
        clearProject || clearMilestone || (projectChanged && milestoneId == null);

    final updated = existing.copyWith(
      title: trimmedTitle,
      description: shouldClearDesc ? null : trimmedDesc,
      clearDescription: shouldClearDesc,
      priority: nextPriority,
      status: nextStatus,
      completedAt: nextCompletedAt,
      clearCompletedAt: nextStatus != 'completed',
      dueDate: dueDate,
      clearDueDate: clearDueDate,
      scheduledDate: scheduledDate,
      clearScheduledDate: clearScheduledDate,
      scheduledTime: scheduledTime,
      clearScheduledTime: clearScheduledTime,
      projectId: projectId,
      clearProject: clearProject,
      milestoneId: shouldClearMilestone ? null : milestoneId,
      clearMilestone: shouldClearMilestone,
      subtasks: subtasks != null
          ? TaskSubtask.normalizeList(subtasks, taskId: existing.id)
          : null,
      labels:
          labels != null ? TasksModuleState.normalizeLabels(labels) : null,
      updatedAt: now,
    );

    try {
      final persisted = await _repository.updateTask(updated);
      final updatedTasks = await _repository.getTasks();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        clearError: true,
      );
      notifyListeners();
      return persisted;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<void> archiveTask(String id) async {
    final existing =
        _state.findTaskById(id) ?? await _repository.getTaskById(id);
    if (existing == null) return;
    await _persistUpdatedTask(
      existing.copyWith(
        isArchived: true,
        updatedAt: EthiopiaClock.nowUtc(),
      ),
    );
  }

  Future<void> restoreTask(String id) async {
    final existing =
        _state.findTaskById(id) ?? await _repository.getTaskById(id);
    if (existing == null) return;
    await _persistUpdatedTask(
      existing.copyWith(
        isArchived: false,
        updatedAt: EthiopiaClock.nowUtc(),
      ),
    );
  }

  Future<void> restoreDeletedTask(TaskEntity snapshot) async {
    try {
      await _repository.createTask(snapshot);
      final updatedTasks = await _repository.getTasks();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> toggleTaskStatus(String id) async {
    final task = _state.findTaskById(id);
    if (task == null) return;
    final nextStatus = task.isCompleted ? 'not_started' : 'completed';
    await updateTaskStatus(id, nextStatus);
  }

  Future<void> updateTaskStatus(String id, String newStatus) async {
    try {
      await _repository.updateTaskStatus(id, newStatus);
      final updatedTasks = await _repository.getTasks();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> rescheduleTask(String id, CalendarDate? newDueDate) async {
    try {
      await _repository.rescheduleTask(id, newDueDate);
      final updatedTasks = await _repository.getTasks();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> postponeTaskDays(String id, int days) async {
    try {
      await _repository.postponeTaskDays(id, days);
      final updatedTasks = await _repository.getTasks();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> deleteTask(String id) async {
    try {
      await _repository.deleteTask(id);
      final updatedTasks = await _repository.getTasks();
      final nextSelection = Set<String>.from(_state.selectedTaskIds)
        ..remove(id);
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        selectedTaskIds: nextSelection,
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> batchToggleSelected() async {
    final ids = _state.selectedTaskIds.toList(growable: false);
    if (ids.isEmpty) return;
    try {
      for (final id in ids) {
        final task = _state.findTaskById(id);
        if (task != null) {
          final nextStatus = task.isCompleted ? 'not_started' : 'completed';
          await _repository.updateTaskStatus(id, nextStatus);
        }
      }
      final updatedTasks = await _repository.getTasks();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        selectedTaskIds: const {},
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> batchDeleteSelected() async {
    final ids = _state.selectedTaskIds.toList(growable: false);
    if (ids.isEmpty) return;
    try {
      for (final id in ids) {
        await _repository.deleteTask(id);
      }
      final updatedTasks = await _repository.getTasks();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        selectedTaskIds: const {},
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> cancelTask(String id) async {
    await updateTaskStatus(id, 'cancelled');
  }

  // --- Project Workflow Orchestration ---

  Future<ProjectEntity?> createProject({
    required String title,
    String? description,
    CalendarDate? targetDate,
    String? goalId,
  }) async {
    final now = EthiopiaClock.nowUtc();
    final project = ProjectEntity(
      id: 'proj-${now.millisecondsSinceEpoch}',
      title: title.trim(),
      description: description?.trim(),
      targetDate: targetDate,
      goalId: goalId,
      status: 'active',
      createdAt: now,
    );

    try {
      final created = await _repository.createProject(project);
      final updatedProjects = await _repository.getProjects();
      _state = _state.copyWith(
        projects: List<ProjectEntity>.unmodifiable(updatedProjects),
        clearError: true,
      );
      notifyListeners();
      return created;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<void> updateProjectStatus(String id, String status) async {
    final project = _state.projects.firstWhere(
      (p) => p.id == id,
      orElse: () => ProjectEntity(id: id, title: ''),
    );
    if (project.title.isEmpty) return;
    try {
      final updated = project.copyWith(status: status);
      await _repository.updateProject(updated);
      final updatedProjects = await _repository.getProjects();
      _state = _state.copyWith(
        projects: List<ProjectEntity>.unmodifiable(updatedProjects),
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> deleteProject(String id) async {
    try {
      await _repository.deleteProject(id);
      final updatedProjects = await _repository.getProjects();
      final updatedTasks = await _repository.getTasks();
      final updatedMilestones = await _repository.getAllMilestones();

      _state = _state.copyWith(
        projects: List<ProjectEntity>.unmodifiable(updatedProjects),
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        milestones: List<MilestoneEntity>.unmodifiable(updatedMilestones),
        clearSelectedProject: _state.selectedProjectId == id,
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  // --- Milestone Workflow Orchestration ---

  Future<MilestoneEntity?> addMilestone({
    required String projectId,
    required String title,
    CalendarDate? dueDate,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      _state = _state.copyWith(errorMessage: 'Milestone title is required');
      notifyListeners();
      return null;
    }
    final now = EthiopiaClock.nowUtc();
    final milestone = MilestoneEntity(
      id: 'ms-${now.microsecondsSinceEpoch}',
      projectId: projectId,
      title: trimmed,
      dueDate: dueDate,
      isCompleted: false,
      createdAt: now,
    );

    try {
      final created = await _repository.createMilestone(milestone);
      final updatedMilestones = await _repository.getAllMilestones();
      _state = _state.copyWith(
        milestones: List<MilestoneEntity>.unmodifiable(updatedMilestones),
        clearError: true,
      );
      notifyListeners();
      return created;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<MilestoneEntity?> updateMilestone({
    required String milestoneId,
    required String title,
    CalendarDate? dueDate,
    bool clearDueDate = false,
    bool? isCompleted,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      _state = _state.copyWith(errorMessage: 'Milestone title is required');
      notifyListeners();
      return null;
    }
    MilestoneEntity? existing;
    for (final m in _state.milestones) {
      if (m.id == milestoneId) {
        existing = m;
        break;
      }
    }
    if (existing == null) return null;

    try {
      final updated = await _repository.updateMilestone(
        existing.copyWith(
          title: trimmed,
          dueDate: dueDate,
          clearDueDate: clearDueDate,
          isCompleted: isCompleted,
        ),
      );
      final updatedMilestones = await _repository.getAllMilestones();
      _state = _state.copyWith(
        milestones: List<MilestoneEntity>.unmodifiable(updatedMilestones),
        clearError: true,
      );
      notifyListeners();
      return updated;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<void> toggleMilestone(String milestoneId, bool isCompleted) async {
    try {
      await _repository.toggleMilestone(milestoneId, isCompleted);
      final updatedMilestones = await _repository.getAllMilestones();
      _state = _state.copyWith(
        milestones: List<MilestoneEntity>.unmodifiable(updatedMilestones),
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<List<String>> deleteMilestone(String milestoneId) async {
    final detachedTaskIds = _state.tasks
        .where((t) => t.milestoneId == milestoneId)
        .map((t) => t.id)
        .toList(growable: false);
    try {
      await _repository.deleteMilestone(milestoneId);
      final updatedMilestones = await _repository.getAllMilestones();
      final updatedTasks = await _repository.getTasks();
      _state = _state.copyWith(
        milestones: List<MilestoneEntity>.unmodifiable(updatedMilestones),
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        clearError: true,
      );
      notifyListeners();
      return detachedTaskIds;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return const [];
    }
  }

  Future<void> restoreDeletedMilestone(
    MilestoneEntity snapshot, {
    List<String> restoreTaskIds = const [],
  }) async {
    try {
      await _repository.createMilestone(snapshot);
      if (restoreTaskIds.isNotEmpty) {
        final targetIds = restoreTaskIds.toSet();
        final currentTasks = await _repository.getTasks();
        for (final task in currentTasks) {
          if (targetIds.contains(task.id) &&
              task.projectId == snapshot.projectId) {
            await _repository.updateTask(
              task.copyWith(
                milestoneId: snapshot.id,
                updatedAt: EthiopiaClock.nowUtc(),
              ),
            );
          }
        }
      }
      final updatedMilestones = await _repository.getAllMilestones();
      final updatedTasks = await _repository.getTasks();
      _state = _state.copyWith(
        milestones: List<MilestoneEntity>.unmodifiable(updatedMilestones),
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    super.dispose();
  }
}
