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

  void setPriorityFilter(String? priority) {
    if (priority == null) {
      _state = _state.copyWith(clearPriorityFilter: true);
    } else {
      _state = _state.copyWith(priorityFilter: priority);
    }
    notifyListeners();
  }

  void selectProject(String? projectId) {
    if (projectId == null) {
      _state = _state.copyWith(clearSelectedProject: true);
    } else {
      _state = _state.copyWith(selectedProjectId: projectId);
    }
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

  void clearFilters() {
    _state = _state.copyWith(
      viewFilter: 'today',
      searchQuery: '',
      sortBy: 'due',
      clearPriorityFilter: true,
      clearSelectedProject: true,
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
    final existing = _state.findTaskById(taskId);
    if (existing == null) return;
    await _persistUpdatedTask(
        existing.copyWith(labels: List<String>.from(labels)));
  }

  Future<void> addSubtask(String taskId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final existing = _state.findTaskById(taskId);
    if (existing == null) return;
    final nextSubtasks = [...existing.subtasks, (title: trimmed, done: false)];
    await _persistUpdatedTask(existing.copyWith(subtasks: nextSubtasks));
  }

  Future<void> toggleSubtask(String taskId, int index, bool done) async {
    final existing = _state.findTaskById(taskId);
    if (existing == null || index < 0 || index >= existing.subtasks.length) {
      return;
    }
    final nextSubtasks =
        List<({String title, bool done})>.from(existing.subtasks);
    nextSubtasks[index] = (title: nextSubtasks[index].title, done: done);
    await _persistUpdatedTask(existing.copyWith(subtasks: nextSubtasks));
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

  Future<TaskEntity?> createTask({
    String? id,
    required String title,
    String? description,
    String priority = 'medium',
    CalendarDate? dueDate,
    CalendarDate? scheduledDate,
    int? estimatedDurationMinutes,
    String? projectId,
    String? milestoneId,
    List<({String title, bool done})> subtasks = const [],
    List<String> labels = const [],
    bool isPinned = false,
    bool isMyDay = false,
    String? recurrenceRule,
  }) async {
    final now = EthiopiaClock.nowUtc();
    final task = TaskEntity(
      id: id ?? 'task-${now.millisecondsSinceEpoch}',
      title: title.trim(),
      description: description?.trim(),
      priority: priority,
      dueDate: dueDate,
      scheduledDate: scheduledDate,
      estimatedDurationMinutes: estimatedDurationMinutes,
      projectId: projectId,
      milestoneId: milestoneId,
      subtasks: subtasks,
      labels: labels,
      isPinned: isPinned,
      isMyDay: isMyDay,
      recurrenceRule: recurrenceRule,
      status: 'not_started',
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
    final now = EthiopiaClock.nowUtc();
    final milestone = MilestoneEntity(
      id: 'ms-${now.millisecondsSinceEpoch}',
      projectId: projectId,
      title: title.trim(),
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
