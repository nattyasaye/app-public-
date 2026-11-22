import 'package:flutter/foundation.dart';
import '../../core/date/shared_date.dart';
import '../../domain/tasks/daily_planning_engine.dart';
import '../../domain/tasks/task_models.dart';
import '../../domain/tasks/task_contracts.dart';
import '../../domain/tasks/task_recurrence_engine.dart';
import 'tasks_state.dart';

/// Module-scoped application controller for Daywell To-Do and Projects.
///
/// Sole owner of Tasks/Projects/Milestones/DailyPlanning module state, hydrated
/// from and persisted directly to [ITasksRepository] (authoritative Drift SQLite).
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
      final loadedEntries = await _repository.getDailyPlanningEntries();

      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(loadedTasks),
        projects: List<ProjectEntity>.unmodifiable(loadedProjects),
        milestones: List<MilestoneEntity>.unmodifiable(loadedMilestones),
        dailyPlanningEntries: DailyPlanningEngine.normalizeEntries(loadedEntries),
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

  // --- Daily Planning & My Day Orchestration (Stage 2) ---

  void setSelectedPlanDate(CalendarDate date) {
    _state = _state.copyWith(selectedPlanDate: date);
    notifyListeners();
  }

  void resetPlanDateToToday() {
    _state = _state.copyWith(clearSelectedPlanDate: true);
    notifyListeners();
  }

  Future<void> toggleMyDay(String taskId, {CalendarDate? date}) async {
    final targetDate = date ?? _state.effectivePlanDate;
    final existing =
        _state.findTaskById(taskId) ?? await _repository.getTaskById(taskId);
    if (existing == null) return;
    final entries = await _repository.getDailyPlanningEntries();
    final isPlanned = DailyPlanningEngine.isTaskPlannedForDate(
      existing,
      entries,
      targetDate,
    );
    if (isPlanned) {
      await removeTaskFromPlannedDay(taskId, date: targetDate);
    } else {
      await planTaskForDate(taskId, date: targetDate);
    }
  }

  Future<void> planTaskForDate(
    String taskId, {
    CalendarDate? date,
    String action = DailyPlanningActions.planned,
  }) async {
    final targetDate = date ?? _state.effectivePlanDate;
    final today = CalendarDate.today();
    final existing =
        _state.findTaskById(taskId) ?? await _repository.getTaskById(taskId);
    if (existing == null || existing.isArchived) return;

    try {
      final currentTasks = await _repository.getTasks();
      final currentEntries = await _repository.getDailyPlanningEntries();
      final alreadyActive = DailyPlanningEngine.isTaskPlannedForDate(
        existing,
        currentEntries,
        targetDate,
        today: today,
      );
      final nextSortOrder = alreadyActive
          ? existing.sortOrder
          : DailyPlanningEngine.nextSortOrderForPlannedDay(
              currentTasks,
              currentEntries,
              targetDate,
              excludeTaskId: taskId,
              today: today,
            );
      final desiredAction = existing.isCompleted
          ? DailyPlanningActions.completed
          : DailyPlanningActions.normalize(action);
      final existingEntry = DailyPlanningEngine.findEntry(
        currentEntries,
        taskId,
        targetDate,
      );
      final now = EthiopiaClock.nowUtc();

      await _repository.upsertDailyPlanningEntry(
        DailyPlanningEntryEntity(
          id: existingEntry?.id ??
              DailyPlanningEngine.buildEntryId(taskId, targetDate),
          planDate: targetDate,
          taskId: taskId,
          action: desiredAction,
          createdAt: existingEntry?.createdAt ?? now,
          updatedAt: now,
        ),
      );

      final shouldPointMyDay = existing.myDayDate == null ||
          !targetDate.isBefore(existing.myDayDate!) ||
          targetDate == today;
      await _repository.updateTask(
        existing.copyWith(
          isMyDay: shouldPointMyDay ? true : existing.isMyDay,
          myDayDate: shouldPointMyDay ? targetDate : existing.myDayDate,
          sortOrder: nextSortOrder,
          updatedAt: now,
        ),
      );

      final updatedTasks = await _repository.getTasks();
      final updatedEntries = await _repository.getDailyPlanningEntries();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        dailyPlanningEntries:
            DailyPlanningEngine.normalizeEntries(updatedEntries),
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> removeTaskFromPlannedDay(
    String taskId, {
    CalendarDate? date,
  }) async {
    final targetDate = date ?? _state.effectivePlanDate;
    final today = CalendarDate.today();
    final existing =
        _state.findTaskById(taskId) ?? await _repository.getTaskById(taskId);
    if (existing == null) return;

    try {
      final currentEntries = await _repository.getDailyPlanningEntries();
      final existingEntry = DailyPlanningEngine.findEntry(
        currentEntries,
        taskId,
        targetDate,
      );
      final now = EthiopiaClock.nowUtc();

      await _repository.upsertDailyPlanningEntry(
        DailyPlanningEntryEntity(
          id: existingEntry?.id ??
              DailyPlanningEngine.buildEntryId(taskId, targetDate),
          planDate: targetDate,
          taskId: taskId,
          action: DailyPlanningActions.dismissed,
          createdAt: existingEntry?.createdAt ?? now,
          updatedAt: now,
        ),
      );

      final updatedEntriesAfter = await _repository.getDailyPlanningEntries();
      final normalizedEntries =
          DailyPlanningEngine.normalizeEntries(updatedEntriesAfter);

      final touchesTaskMyDay = existing.isMyDay &&
          (existing.myDayDate == targetDate ||
              (existing.myDayDate == null && targetDate == today));
      if (touchesTaskMyDay) {
        final fallbackDates = normalizedEntries
            .where(
              (e) =>
                  e.taskId == taskId &&
                  e.action != DailyPlanningActions.dismissed &&
                  !e.planDate.isBefore(today),
            )
            .map((e) => e.planDate)
            .toList(growable: false)
          ..sort();
        final fallbackDate =
            fallbackDates.isNotEmpty ? fallbackDates.last : null;
        await _repository.updateTask(
          existing.copyWith(
            isMyDay: fallbackDate != null,
            myDayDate: fallbackDate,
            clearMyDayDate: fallbackDate == null,
            updatedAt: now,
          ),
        );
      }

      final updatedTasks = await _repository.getTasks();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        dailyPlanningEntries: normalizedEntries,
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> reorderPlannedTasks(List<String> orderedTaskIds) async {
    if (orderedTaskIds.isEmpty) return;
    try {
      final now = EthiopiaClock.nowUtc();
      for (var i = 0; i < orderedTaskIds.length; i++) {
        final taskId = orderedTaskIds[i];
        final existing =
            _state.findTaskById(taskId) ?? await _repository.getTaskById(taskId);
        if (existing != null && existing.sortOrder != i) {
          await _repository.updateTask(
            existing.copyWith(sortOrder: i, updatedAt: now),
          );
        }
      }
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

  Future<void> movePlannedTaskOrder(
    String taskId, {
    required int delta,
    CalendarDate? date,
  }) async {
    final targetDate = date ?? _state.effectivePlanDate;
    final snapshot = _state.buildDailyPlanSnapshot(date: targetDate);
    final ids =
        snapshot.remainingItems.map((item) => item.task.id).toList();
    final idx = ids.indexOf(taskId);
    if (idx == -1) return;
    final targetIdx = idx + delta;
    if (targetIdx < 0 || targetIdx >= ids.length) return;
    final moved = ids.removeAt(idx);
    ids.insert(targetIdx, moved);
    await reorderPlannedTasks(ids);
  }

  Future<int> carryForwardUnfinishedTasks({
    CalendarDate? fromDate,
    CalendarDate? toDate,
    List<String>? taskIds,
  }) async {
    final resolvedToDate = toDate ?? CalendarDate.today();
    final today = CalendarDate.today();

    try {
      final currentTasks = await _repository.getTasks();
      final currentEntries = DailyPlanningEngine.normalizeEntries(
        await _repository.getDailyPlanningEntries(),
      );

      final candidateIds = <String>{};
      if (taskIds != null && taskIds.isNotEmpty) {
        candidateIds.addAll(taskIds.where((id) => id.trim().isNotEmpty));
      } else if (fromDate != null) {
        for (final t in currentTasks) {
          if (DailyPlanningEngine.isTaskPlannedForDate(
            t,
            currentEntries,
            fromDate,
            today: today,
          )) {
            candidateIds.add(t.id);
          }
        }
      } else {
        for (final entry in currentEntries) {
          if (entry.planDate.isBefore(resolvedToDate) &&
              entry.action != DailyPlanningActions.dismissed) {
            candidateIds.add(entry.taskId);
          }
        }
        for (final t in currentTasks) {
          if (t.isMyDay &&
              t.myDayDate != null &&
              t.myDayDate!.isBefore(resolvedToDate)) {
            candidateIds.add(t.id);
          }
        }
      }

      var carriedCount = 0;
      for (final id in candidateIds) {
        final task = currentTasks.cast<TaskEntity?>().firstWhere(
              (t) => t?.id == id,
              orElse: () => null,
            );
        if (task == null ||
            task.isArchived ||
            task.isCompleted ||
            task.status == 'cancelled') {
          continue;
        }
        final latestEntries = DailyPlanningEngine.normalizeEntries(
          await _repository.getDailyPlanningEntries(),
        );
        if (DailyPlanningEngine.isTaskPlannedForDate(
          task,
          latestEntries,
          resolvedToDate,
          today: today,
        )) {
          continue;
        }
        await planTaskForDate(
          id,
          date: resolvedToDate,
          action: DailyPlanningActions.carriedForward,
        );
        carriedCount += 1;
      }
      return carriedCount;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return 0;
    }
  }

  Future<void> _syncCompletionWithDailyPlanning(
    String taskId,
    bool isCompleted, {
    CalendarDate? preferredPlanDate,
  }) async {
    final task = await _repository.getTaskById(taskId) ?? _state.findTaskById(taskId);
    if (task == null) return;
    final entries = DailyPlanningEngine.normalizeEntries(
      await _repository.getDailyPlanningEntries(),
    );
    final targetDate = DailyPlanningEngine.findTargetPlanDateForCompletion(
      task,
      entries,
      preferredPlanDate: preferredPlanDate ?? _state.effectivePlanDate,
    );
    if (targetDate == null) return;

    final existing = DailyPlanningEngine.findEntry(entries, taskId, targetDate);
    final nextAction = isCompleted
        ? DailyPlanningActions.completed
        : DailyPlanningEngine.nextActionOnReopen(entries, taskId, targetDate);
    final now = EthiopiaClock.nowUtc();

    await _repository.upsertDailyPlanningEntry(
      DailyPlanningEntryEntity(
        id: existing?.id ?? DailyPlanningEngine.buildEntryId(taskId, targetDate),
        planDate: targetDate,
        taskId: taskId,
        action: nextAction,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
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

  Future<TaskEntity?> _persistUpdatedTask(TaskEntity updated) async {
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

    final normalizedConfig =
        TaskRecurrenceEngine.normalizeConfig(recurrenceConfig);
    if (recurrenceConfig != null) {
      final recValidation =
          TaskRecurrenceEngine.validateConfig(recurrenceConfig);
      if (!recValidation.isValid) {
        _state = _state.copyWith(
          errorMessage: recValidation.errors.values.first,
        );
        notifyListeners();
        return null;
      }
    }
    final rawRule = recurrenceRule?.trim().toLowerCase();
    final effectiveRule = normalizedConfig?.frequency ??
        (rawRule != null &&
                TaskRecurrenceEngine.validFrequencies.contains(rawRule)
            ? rawRule
            : null);

    final now = EthiopiaClock.nowUtc();
    final resolvedTaskId = id ?? 'task-${now.millisecondsSinceEpoch}';
    final resolvedMyDayDate =
        isMyDay ? (myDayDate ?? CalendarDate.today()) : null;
    final effectiveSortOrder = isMyDay && sortOrder == 0
        ? DailyPlanningEngine.nextSortOrderForPlannedDay(
            _state.tasks,
            _state.dailyPlanningEntries,
            resolvedMyDayDate!,
            excludeTaskId: resolvedTaskId,
          )
        : sortOrder;

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
      myDayDate: resolvedMyDayDate,
      recurrenceRule: effectiveRule,
      recurrenceConfig: normalizedConfig,
      isArchived: isArchived,
      sortOrder: effectiveSortOrder,
      createdAt: now,
      updatedAt: now,
    );

    try {
      final created = await _repository.createTask(task);
      if (isMyDay && resolvedMyDayDate != null) {
        await _repository.upsertDailyPlanningEntry(
          DailyPlanningEntryEntity(
            id: DailyPlanningEngine.buildEntryId(
              created.id,
              resolvedMyDayDate,
            ),
            planDate: resolvedMyDayDate,
            taskId: created.id,
            action: created.isCompleted
                ? DailyPlanningActions.completed
                : DailyPlanningActions.planned,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      final updatedTasks = await _repository.getTasks();
      final updatedEntries = await _repository.getDailyPlanningEntries();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        dailyPlanningEntries:
            DailyPlanningEngine.normalizeEntries(updatedEntries),
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
    String? recurrenceRule,
    bool clearRecurrenceRule = false,
    TaskRecurrenceConfig? recurrenceConfig,
    bool clearRecurrenceConfig = false,
  }) async {
    final result = await updateTaskWithRecurrence(
      id: id,
      title: title,
      description: description,
      clearDescription: clearDescription,
      priority: priority,
      status: status,
      dueDate: dueDate,
      clearDueDate: clearDueDate,
      scheduledDate: scheduledDate,
      clearScheduledDate: clearScheduledDate,
      scheduledTime: scheduledTime,
      clearScheduledTime: clearScheduledTime,
      projectId: projectId,
      clearProject: clearProject,
      milestoneId: milestoneId,
      clearMilestone: clearMilestone,
      subtasks: subtasks,
      labels: labels,
      recurrenceRule: recurrenceRule,
      clearRecurrenceRule: clearRecurrenceRule,
      recurrenceConfig: recurrenceConfig,
      clearRecurrenceConfig: clearRecurrenceConfig,
    );
    return result.updatedTask;
  }

  Future<({TaskEntity? updatedTask, TaskEntity? generatedNextTask})>
      updateTaskWithRecurrence({
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
    String? recurrenceRule,
    bool clearRecurrenceRule = false,
    TaskRecurrenceConfig? recurrenceConfig,
    bool clearRecurrenceConfig = false,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      _state = _state.copyWith(errorMessage: 'Task title is required');
      notifyListeners();
      return (updatedTask: null, generatedNextTask: null);
    }

    final existing =
        _state.findTaskById(id) ?? await _repository.getTaskById(id);
    if (existing == null) return (updatedTask: null, generatedNextTask: null);

    if (!clearRecurrenceConfig && recurrenceConfig != null) {
      final recValidation =
          TaskRecurrenceEngine.validateConfig(recurrenceConfig);
      if (!recValidation.isValid) {
        _state = _state.copyWith(
          errorMessage: recValidation.errors.values.first,
        );
        notifyListeners();
        return (updatedTask: null, generatedNextTask: null);
      }
    }

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

    final TaskRecurrenceConfig? nextRecurrenceConfig = clearRecurrenceConfig
        ? null
        : (recurrenceConfig != null
            ? TaskRecurrenceEngine.normalizeConfig(recurrenceConfig)
            : existing.recurrenceConfig);
    final shouldClearRule = clearRecurrenceRule || clearRecurrenceConfig;
    final String? nextRecurrenceRule = shouldClearRule
        ? null
        : (nextRecurrenceConfig?.frequency ??
            (recurrenceRule?.trim().toLowerCase() ?? existing.recurrenceRule));

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
      recurrenceRule: nextRecurrenceRule,
      clearRecurrenceRule: shouldClearRule,
      recurrenceConfig: nextRecurrenceConfig,
      clearRecurrenceConfig: clearRecurrenceConfig,
      updatedAt: now,
    );

    try {
      final persisted = await _repository.updateTask(updated);
      TaskEntity? generatedNextTask;
      final transitionedToCompleted =
          !existing.isCompleted && updated.isCompleted;
      if (transitionedToCompleted &&
          TaskRecurrenceEngine.resolveEffectiveConfig(updated) != null) {
        final currentTasks = _state.tasks.isNotEmpty
            ? _state.tasks
            : await _repository.getTasks();
        final tempOpen = updated.copyWith(
          status: 'not_started',
          clearCompletedAt: true,
        );
        final simList = currentTasks
            .map((t) => t.id == existing.id ? tempOpen : t)
            .toList(growable: false);
        final recResult = TaskRecurrenceEngine.completeTaskWithRecurrence(
          simList,
          existing.id,
          nowUtc: now,
        );
        if (recResult.generatedNextTask != null) {
          generatedNextTask =
              await _repository.createTask(recResult.generatedNextTask!);
        }
      }
      if (existing.isCompleted != updated.isCompleted) {
        await _syncCompletionWithDailyPlanning(
          updated.id,
          updated.isCompleted,
        );
      }
      final updatedTasks = await _repository.getTasks();
      final updatedEntries = await _repository.getDailyPlanningEntries();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        dailyPlanningEntries:
            DailyPlanningEngine.normalizeEntries(updatedEntries),
        clearError: true,
      );
      notifyListeners();
      return (updatedTask: persisted, generatedNextTask: generatedNextTask);
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return (updatedTask: null, generatedNextTask: null);
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

  Future<void> restoreDeletedTask(
    TaskEntity snapshot, {
    List<DailyPlanningEntryEntity> restorePlanningEntries = const [],
  }) async {
    try {
      await _repository.createTask(snapshot);
      for (final entry in restorePlanningEntries) {
        await _repository.upsertDailyPlanningEntry(entry);
      }
      final updatedTasks = await _repository.getTasks();
      final updatedEntries = await _repository.getDailyPlanningEntries();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        dailyPlanningEntries:
            DailyPlanningEngine.normalizeEntries(updatedEntries),
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<
      ({
        TaskEntity? updatedTask,
        TaskEntity? generatedNextTask,
        bool seriesEnded,
        bool duplicatePrevented,
      })> toggleTaskWithRecurrence(
    String id, {
    DateTime? nowUtc,
  }) async {
    try {
      final currentTasks = _state.tasks.isNotEmpty
          ? _state.tasks
          : await _repository.getTasks();
      final result = TaskRecurrenceEngine.completeTaskWithRecurrence(
        currentTasks,
        id,
        nowUtc: nowUtc,
      );
      if (result.updatedTask == null) {
        return (
          updatedTask: null,
          generatedNextTask: null,
          seriesEnded: false,
          duplicatePrevented: false,
        );
      }
      final persisted = await _repository.updateTask(result.updatedTask!);
      TaskEntity? spawned;
      if (result.generatedNextTask != null) {
        spawned = await _repository.createTask(result.generatedNextTask!);
      }
      await _syncCompletionWithDailyPlanning(id, persisted.isCompleted);

      final updatedTasks = await _repository.getTasks();
      final updatedEntries = await _repository.getDailyPlanningEntries();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        dailyPlanningEntries:
            DailyPlanningEngine.normalizeEntries(updatedEntries),
        clearError: true,
      );
      notifyListeners();
      return (
        updatedTask: persisted,
        generatedNextTask: spawned,
        seriesEnded: result.seriesEnded,
        duplicatePrevented: result.duplicatePrevented,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return (
        updatedTask: null,
        generatedNextTask: null,
        seriesEnded: false,
        duplicatePrevented: false,
      );
    }
  }

  Future<void> toggleTaskStatus(String id) async {
    await toggleTaskWithRecurrence(id);
  }

  Future<void> updateTaskStatus(String id, String newStatus) async {
    try {
      final existing =
          _state.findTaskById(id) ?? await _repository.getTaskById(id);
      if (existing != null &&
          newStatus == 'completed' &&
          !existing.isCompleted &&
          TaskRecurrenceEngine.resolveEffectiveConfig(existing) != null) {
        await toggleTaskWithRecurrence(id);
        return;
      }

      await _repository.updateTaskStatus(id, newStatus);
      await _syncCompletionWithDailyPlanning(id, newStatus == 'completed');
      final updatedTasks = await _repository.getTasks();
      final updatedEntries = await _repository.getDailyPlanningEntries();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        dailyPlanningEntries:
            DailyPlanningEngine.normalizeEntries(updatedEntries),
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<TaskEntity?> skipRecurrenceOccurrence(
    String taskId, {
    DateTime? nowUtc,
  }) async {
    final existing =
        _state.findTaskById(taskId) ?? await _repository.getTaskById(taskId);
    if (existing == null) return null;

    final skipped =
        TaskRecurrenceEngine.skipOccurrence(existing, nowUtc: nowUtc);
    if (!skipped.ok || skipped.updatedTask == null) {
      _state = _state.copyWith(errorMessage: skipped.error);
      notifyListeners();
      return null;
    }

    try {
      final persisted = await _repository.updateTask(skipped.updatedTask!);
      if (existing.isMyDay && !persisted.isMyDay && existing.myDayDate != null) {
        await removeTaskFromPlannedDay(taskId, date: existing.myDayDate!);
      }
      final updatedTasks = await _repository.getTasks();
      final updatedEntries = await _repository.getDailyPlanningEntries();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        dailyPlanningEntries:
            DailyPlanningEngine.normalizeEntries(updatedEntries),
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

  Future<TaskEntity?> rescheduleTaskOccurrence(
    String taskId,
    CalendarDate newDate, {
    DateTime? nowUtc,
  }) async {
    final existing =
        _state.findTaskById(taskId) ?? await _repository.getTaskById(taskId);
    if (existing == null) return null;

    final updated = TaskRecurrenceEngine.rescheduleOccurrence(
      existing,
      newDate,
      nowUtc: nowUtc,
    );
    return _persistUpdatedTask(updated);
  }

  Future<TaskEntity?> stopTaskRecurrence(
    String taskId, {
    DateTime? nowUtc,
  }) async {
    final existing =
        _state.findTaskById(taskId) ?? await _repository.getTaskById(taskId);
    if (existing == null) return null;

    final updated = TaskRecurrenceEngine.stopRecurrence(
      existing,
      nowUtc: nowUtc,
    );
    return _persistUpdatedTask(updated);
  }

  Future<void> restoreTaskSnapshot(TaskEntity snapshot) async {
    await _persistUpdatedTask(snapshot);
  }

  Future<void> undoGeneratedRecurrenceCompletion({
    required TaskEntity previousTask,
    String? generatedNextTaskId,
  }) async {
    try {
      await _repository.updateTask(previousTask);
      if (generatedNextTaskId != null && generatedNextTaskId.trim().isNotEmpty) {
        await _repository.deleteTask(generatedNextTaskId);
      }
      await _syncCompletionWithDailyPlanning(
        previousTask.id,
        previousTask.isCompleted,
      );
      final updatedTasks = await _repository.getTasks();
      final updatedEntries = await _repository.getDailyPlanningEntries();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        dailyPlanningEntries:
            DailyPlanningEngine.normalizeEntries(updatedEntries),
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
      final updatedEntries = await _repository.getDailyPlanningEntries();
      final nextSelection = Set<String>.from(_state.selectedTaskIds)
        ..remove(id);
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        dailyPlanningEntries:
            DailyPlanningEngine.normalizeEntries(updatedEntries),
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
      var runningTasks = List<TaskEntity>.from(_state.tasks);
      for (final id in ids) {
        final task = _state.findTaskById(id);
        if (task == null) continue;
        final result = TaskRecurrenceEngine.completeTaskWithRecurrence(
          runningTasks,
          id,
        );
        if (result.updatedTask != null) {
          await _repository.updateTask(result.updatedTask!);
          if (result.generatedNextTask != null) {
            await _repository.createTask(result.generatedNextTask!);
          }
          await _syncCompletionWithDailyPlanning(
            id,
            result.updatedTask!.isCompleted,
          );
          runningTasks = List<TaskEntity>.from(result.tasks);
        }
      }
      final updatedTasks = await _repository.getTasks();
      final updatedEntries = await _repository.getDailyPlanningEntries();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        dailyPlanningEntries:
            DailyPlanningEngine.normalizeEntries(updatedEntries),
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
      final updatedEntries = await _repository.getDailyPlanningEntries();
      _state = _state.copyWith(
        tasks: List<TaskEntity>.unmodifiable(updatedTasks),
        dailyPlanningEntries:
            DailyPlanningEngine.normalizeEntries(updatedEntries),
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
