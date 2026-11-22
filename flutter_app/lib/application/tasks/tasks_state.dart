import '../../core/date/shared_date.dart';
import '../../domain/tasks/task_models.dart';
import '../../domain/projects/progress_engine.dart';

/// Immutable state container for the Daywell To-Do and Projects module.
class TasksModuleState {
  final List<TaskEntity> tasks;
  final List<ProjectEntity> projects;
  final List<MilestoneEntity> milestones;

  // Presentation / Filter State
  final String
      viewFilter; // 'today', 'inbox', 'upcoming', 'all', 'my_day', 'completed', 'archived'
  final String searchQuery;
  final String sortBy; // 'due', 'priority', 'alpha'
  final String? priorityFilter; // null = all, 'low', 'medium', 'high', 'urgent'
  final String? selectedProjectId;
  final Set<String> selectedTaskIds;
  final bool isBoardView;
  final bool isLoading;
  final String? errorMessage;

  const TasksModuleState({
    this.tasks = const [],
    this.projects = const [],
    this.milestones = const [],
    this.viewFilter = 'today',
    this.searchQuery = '',
    this.sortBy = 'due',
    this.priorityFilter,
    this.selectedProjectId,
    this.selectedTaskIds = const {},
    this.isBoardView = false,
    this.isLoading = false,
    this.errorMessage,
  });

  bool get isSelectionMode => selectedTaskIds.isNotEmpty;

  Set<String> get pinnedTaskIds =>
      tasks.where((t) => !t.isArchived && t.isPinned).map((t) => t.id).toSet();

  Set<String> get myDayTaskIds =>
      tasks.where((t) => !t.isArchived && t.isMyDay).map((t) => t.id).toSet();

  TaskEntity? findTaskById(String id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  TasksModuleState copyWith({
    List<TaskEntity>? tasks,
    List<ProjectEntity>? projects,
    List<MilestoneEntity>? milestones,
    String? viewFilter,
    String? searchQuery,
    String? sortBy,
    String? priorityFilter,
    bool clearPriorityFilter = false,
    String? selectedProjectId,
    bool clearSelectedProject = false,
    Set<String>? selectedTaskIds,
    bool? isBoardView,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return TasksModuleState(
      tasks: tasks ?? this.tasks,
      projects: projects ?? this.projects,
      milestones: milestones ?? this.milestones,
      viewFilter: viewFilter ?? this.viewFilter,
      searchQuery: searchQuery ?? this.searchQuery,
      sortBy: sortBy ?? this.sortBy,
      priorityFilter:
          clearPriorityFilter ? null : (priorityFilter ?? this.priorityFilter),
      selectedProjectId: clearSelectedProject
          ? null
          : (selectedProjectId ?? this.selectedProjectId),
      selectedTaskIds: selectedTaskIds ?? this.selectedTaskIds,
      isBoardView: isBoardView ?? this.isBoardView,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  // --- Derived Calculations & Filtered Tasks ---

  bool _isInToday(TaskEntity t, CalendarDate today) {
    final dueMatch = t.dueDate != null && !t.dueDate!.isAfter(today);
    final scheduledMatch =
        t.scheduledDate != null && !t.scheduledDate!.isAfter(today);
    return dueMatch || scheduledMatch;
  }

  bool _isInUpcoming(TaskEntity t, CalendarDate today) {
    final dueMatch = t.dueDate != null && t.dueDate!.isAfter(today);
    final scheduledMatch =
        t.scheduledDate != null && t.scheduledDate!.isAfter(today);
    return dueMatch || scheduledMatch;
  }

  bool _isInInbox(TaskEntity t) {
    return t.status == 'inbox' ||
        (t.projectId == null || t.projectId!.isEmpty);
  }

  List<TaskEntity> get filteredTasks {
    final today = CalendarDate.today();
    final query = searchQuery.trim().toLowerCase();

    final list = tasks.where((t) {
      if (viewFilter == 'archived') {
        if (!t.isArchived) return false;
      } else {
        if (t.isArchived) return false;

        if (viewFilter == 'completed') {
          if (!t.isCompleted) return false;
        } else if (viewFilter == 'all') {
          // Includes all non-archived tasks across statuses.
        } else {
          if (t.isCompleted || t.status == 'cancelled') return false;
          if (viewFilter == 'today') {
            if (!_isInToday(t, today)) return false;
          } else if (viewFilter == 'inbox') {
            if (!_isInInbox(t)) return false;
          } else if (viewFilter == 'upcoming') {
            if (!_isInUpcoming(t, today)) return false;
          } else if (viewFilter == 'my_day') {
            if (!t.isMyDay) return false;
          }
        }
      }

      if (priorityFilter != null && t.priority != priorityFilter) {
        return false;
      }

      if (selectedProjectId != null && t.projectId != selectedProjectId) {
        return false;
      }

      if (query.isNotEmpty) {
        final labelsStr = t.labels.join(' ').toLowerCase();
        final match = t.title.toLowerCase().contains(query) ||
            (t.description ?? '').toLowerCase().contains(query) ||
            labelsStr.contains(query);
        if (!match) return false;
      }

      return true;
    }).toList();

    list.sort((a, b) {
      final aPin = a.isPinned ? 0 : 1;
      final bPin = b.isPinned ? 0 : 1;
      if (aPin != bPin) return aPin.compareTo(bPin);

      if (sortBy == 'priority') {
        const priorityOrder = {'urgent': 0, 'high': 1, 'medium': 2, 'low': 3};
        final pA = priorityOrder[a.priority] ?? 2;
        final pB = priorityOrder[b.priority] ?? 2;
        return pA.compareTo(pB);
      } else if (sortBy == 'alpha') {
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
      final aDue =
          a.dueDate ?? a.scheduledDate ?? CalendarDate(year: 2099, month: 12, day: 31);
      final bDue =
          b.dueDate ?? b.scheduledDate ?? CalendarDate(year: 2099, month: 12, day: 31);
      return aDue.compareTo(bDue);
    });

    return list;
  }

  List<TaskEntity> get pendingTasks => tasks
      .where((t) => !t.isArchived && !t.isCompleted && t.status != 'cancelled')
      .toList(growable: false);

  List<TaskEntity> get urgentTasks => pendingTasks
      .where((t) => t.priority == 'urgent' || t.priority == 'high')
      .toList(growable: false);

  int get todayCount {
    final today = CalendarDate.today();
    return tasks.where((t) {
      if (t.isArchived || t.isCompleted || t.status == 'cancelled') {
        return false;
      }
      return _isInToday(t, today);
    }).length;
  }

  int get inboxCount {
    return tasks
        .where((t) =>
            !t.isArchived &&
            !t.isCompleted &&
            t.status != 'cancelled' &&
            _isInInbox(t))
        .length;
  }

  int get upcomingCount {
    final today = CalendarDate.today();
    return tasks.where((t) {
      if (t.isArchived || t.isCompleted || t.status == 'cancelled') {
        return false;
      }
      return _isInUpcoming(t, today);
    }).length;
  }

  int get allCount => tasks.where((t) => !t.isArchived).length;

  int get completedCount =>
      tasks.where((t) => !t.isArchived && t.isCompleted).length;

  int get archivedCount => tasks.where((t) => t.isArchived).length;

  int getProjectProgress(String projectId) {
    final projectTasks = tasks.where((t) => t.projectId == projectId).toList();
    final projectMilestones =
        milestones.where((m) => m.projectId == projectId).toList();

    final completedTasks = projectTasks.where((t) => t.isCompleted).length;
    final completedMilestones =
        projectMilestones.where((m) => m.isCompleted).length;

    final project = projects.firstWhere(
      (p) => p.id == projectId,
      orElse: () => ProjectEntity(id: projectId, title: ''),
    );

    return ProgressEngine.calculateProgressPercentage(
      totalTasks: projectTasks.length,
      completedTasks: completedTasks,
      totalMilestones: projectMilestones.length,
      completedMilestones: completedMilestones,
      isProjectManuallyCompleted: project.status == 'completed',
    );
  }
}
