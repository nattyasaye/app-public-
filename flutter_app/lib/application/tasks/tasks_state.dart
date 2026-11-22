import '../../core/date/shared_date.dart';
import '../../domain/tasks/daily_planning_engine.dart';
import '../../domain/tasks/task_models.dart';
import '../../domain/projects/progress_engine.dart';

/// Immutable state container for the Daywell To-Do and Projects module.
class TasksModuleState {
  final List<TaskEntity> tasks;
  final List<ProjectEntity> projects;
  final List<MilestoneEntity> milestones;
  final List<DailyPlanningEntryEntity> dailyPlanningEntries;
  final List<TaskReminderEntity> reminders;
  final CalendarDate? selectedPlanDate;

  // Presentation / Filter State
  final String
      viewFilter; // 'today', 'inbox', 'upcoming', 'active', 'overdue', 'all', 'my_day', 'completed', 'archived'
  final String searchQuery;
  final String sortBy; // 'due', 'priority', 'created', 'alpha'
  final String? statusFilter; // null = all
  final String? priorityFilter; // null = all, 'low', 'medium', 'high', 'urgent'
  final String?
      dueDateFilter; // null = all, 'overdue', 'today', 'upcoming', 'no_due_date'
  final String? selectedProjectId;
  final String? sectionFilter; // null = all, sectionId or '__unsectioned__'
  final Set<String> tagFilters;
  final List<String> customTags;
  final Set<String> selectedTaskIds;
  final bool isBoardView;
  final bool isLoading;
  final String? errorMessage;

  const TasksModuleState({
    this.tasks = const [],
    this.projects = const [],
    this.milestones = const [],
    this.dailyPlanningEntries = const [],
    this.reminders = const [],
    this.selectedPlanDate,
    this.viewFilter = 'today',
    this.searchQuery = '',
    this.sortBy = 'due',
    this.statusFilter,
    this.priorityFilter,
    this.dueDateFilter,
    this.selectedProjectId,
    this.sectionFilter,
    this.tagFilters = const {},
    this.customTags = const [],
    this.selectedTaskIds = const {},
    this.isBoardView = false,
    this.isLoading = false,
    this.errorMessage,
  });

  static String normalizeLabel(String raw) {
    final collapsed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    return collapsed.replaceFirst(RegExp(r'^[@#]+'), '').trim();
  }

  static List<String> normalizeLabels(Iterable<String> rawLabels) {
    final result = <String>[];
    final seenLower = <String>{};
    for (final raw in rawLabels) {
      final normalized = normalizeLabel(raw);
      if (normalized.isEmpty) continue;
      final key = normalized.toLowerCase();
      if (seenLower.add(key)) {
        result.add(normalized);
      }
    }
    return List<String>.unmodifiable(result);
  }

  static List<String> extractAvailableLabels(
    List<TaskEntity> tasks, {
    Iterable<String> extraLabels = const [],
  }) {
    final byKey = <String, String>{};
    void record(String raw) {
      final normalized = normalizeLabel(raw);
      if (normalized.isEmpty) return;
      final key = normalized.toLowerCase();
      byKey.putIfAbsent(key, () => normalized);
    }

    for (final extra in extraLabels) {
      record(extra);
    }
    for (final task in tasks) {
      for (final lbl in task.labels) {
        record(lbl);
      }
    }
    final list = byKey.values.toList(growable: false);
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return List<String>.unmodifiable(list);
  }

  bool get isSelectionMode => selectedTaskIds.isNotEmpty;

  List<String> get availableTags =>
      extractAvailableLabels(tasks, extraLabels: customTags);

  bool get hasActiveFilters =>
      searchQuery.trim().isNotEmpty ||
      statusFilter != null ||
      priorityFilter != null ||
      dueDateFilter != null ||
      selectedProjectId != null ||
      sectionFilter != null ||
      tagFilters.isNotEmpty;

  int get activeFilterCount {
    var count = 0;
    if (statusFilter != null) count += 1;
    if (priorityFilter != null) count += 1;
    if (dueDateFilter != null) count += 1;
    if (selectedProjectId != null) count += 1;
    if (sectionFilter != null) count += 1;
    count += tagFilters.length;
    return count;
  }

  CalendarDate get effectivePlanDate => selectedPlanDate ?? CalendarDate.today();

  Set<String> get pinnedTaskIds =>
      tasks.where((t) => !t.isArchived && t.isPinned).map((t) => t.id).toSet();

  Set<String> get myDayTaskIds {
    final planDate = effectivePlanDate;
    return tasks
        .where(
          (t) => DailyPlanningEngine.isTaskPlannedForDate(
            t,
            dailyPlanningEntries,
            planDate,
          ),
        )
        .map((t) => t.id)
        .toSet();
  }

  int get myDayCount => myDayTaskIds.length;

  DailyPlanSnapshot buildDailyPlanSnapshot({
    CalendarDate? date,
    CalendarDate? today,
  }) {
    return DailyPlanningEngine.buildSnapshot(
      tasks: tasks,
      entries: dailyPlanningEntries,
      selectedDate: date ?? effectivePlanDate,
      today: today,
    );
  }

  TaskEntity? findTaskById(String id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  TaskReminderEntity? findReminderForTask(String taskId) {
    TaskReminderEntity? fallback;
    for (final r in reminders) {
      if (r.targetType == 'task' && r.targetId == taskId) {
        if (r.isActive) return r;
        fallback ??= r;
      }
    }
    return fallback;
  }

  int get activeReminderCount =>
      reminders.where((r) => r.targetType == 'task' && r.isActive).length;

  TasksModuleState copyWith({
    List<TaskEntity>? tasks,
    List<ProjectEntity>? projects,
    List<MilestoneEntity>? milestones,
    List<DailyPlanningEntryEntity>? dailyPlanningEntries,
    List<TaskReminderEntity>? reminders,
    CalendarDate? selectedPlanDate,
    bool clearSelectedPlanDate = false,
    String? viewFilter,
    String? searchQuery,
    String? sortBy,
    String? statusFilter,
    bool clearStatusFilter = false,
    String? priorityFilter,
    bool clearPriorityFilter = false,
    String? dueDateFilter,
    bool clearDueDateFilter = false,
    String? selectedProjectId,
    bool clearSelectedProject = false,
    String? sectionFilter,
    bool clearSectionFilter = false,
    Set<String>? tagFilters,
    List<String>? customTags,
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
      dailyPlanningEntries: dailyPlanningEntries ?? this.dailyPlanningEntries,
      reminders: reminders ?? this.reminders,
      selectedPlanDate: clearSelectedPlanDate
          ? null
          : (selectedPlanDate ?? this.selectedPlanDate),
      viewFilter: viewFilter ?? this.viewFilter,
      searchQuery: searchQuery ?? this.searchQuery,
      sortBy: sortBy ?? this.sortBy,
      statusFilter:
          clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
      priorityFilter:
          clearPriorityFilter ? null : (priorityFilter ?? this.priorityFilter),
      dueDateFilter:
          clearDueDateFilter ? null : (dueDateFilter ?? this.dueDateFilter),
      selectedProjectId: clearSelectedProject
          ? null
          : (selectedProjectId ?? this.selectedProjectId),
      sectionFilter:
          clearSectionFilter ? null : (sectionFilter ?? this.sectionFilter),
      tagFilters: tagFilters ?? this.tagFilters,
      customTags: customTags ?? this.customTags,
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

  bool _matchesTagFilters(TaskEntity t) {
    if (tagFilters.isEmpty) return true;
    final taskKeys = t.labels
        .map((l) => normalizeLabel(l).toLowerCase())
        .where((l) => l.isNotEmpty)
        .toSet();
    for (final requiredTag in tagFilters) {
      final key = normalizeLabel(requiredTag).toLowerCase();
      if (key.isEmpty || !taskKeys.contains(key)) {
        return false;
      }
    }
    return true;
  }

  List<TaskEntity> get filteredTasks => filterTasks();

  List<TaskEntity> filterTasks({Set<String>? sectionTaskIds}) {
    final today = CalendarDate.today();
    final query = searchQuery.trim().toLowerCase();
    final projectTitlesById = <String, String>{
      for (final p in projects) p.id: p.title.toLowerCase(),
    };

    final list = tasks.where((t) {
      if (viewFilter == 'archived') {
        if (!t.isArchived) return false;
      } else {
        if (t.isArchived) return false;

        if (viewFilter == 'completed') {
          if (!t.isCompleted) return false;
        } else if (viewFilter == 'all') {
          // Includes all non-archived tasks across statuses.
        } else if (viewFilter == 'overdue') {
          if (!t.isOverdue) return false;
        } else {
          if (t.isCompleted || t.status == 'cancelled') return false;
          if (viewFilter == 'today') {
            if (!_isInToday(t, today)) return false;
          } else if (viewFilter == 'inbox') {
            if (!_isInInbox(t)) return false;
          } else if (viewFilter == 'upcoming') {
            if (!_isInUpcoming(t, today)) return false;
          } else if (viewFilter == 'active') {
            // Non-archived and neither completed nor cancelled.
          } else if (viewFilter == 'my_day') {
            if (!DailyPlanningEngine.isTaskPlannedForDate(
              t,
              dailyPlanningEntries,
              effectivePlanDate,
              today: today,
            )) {
              return false;
            }
          }
        }
      }

      if (statusFilter != null && t.status != statusFilter) {
        return false;
      }

      if (priorityFilter != null && t.priority != priorityFilter) {
        return false;
      }

      if (dueDateFilter != null) {
        switch (dueDateFilter) {
          case 'overdue':
            if (!t.isOverdue) return false;
            break;
          case 'today':
            if (t.dueDate == null || t.dueDate != today) return false;
            break;
          case 'upcoming':
            if (t.dueDate == null || !t.dueDate!.isAfter(today)) return false;
            break;
          case 'no_due_date':
            if (t.dueDate != null) return false;
            break;
        }
      }

      if (selectedProjectId != null && t.projectId != selectedProjectId) {
        return false;
      }

      if (sectionFilter != null &&
          sectionTaskIds != null &&
          !sectionTaskIds.contains(t.id)) {
        return false;
      }

      if (!_matchesTagFilters(t)) {
        return false;
      }

      if (query.isNotEmpty) {
        final labelsStr = t.labels.join(' ').toLowerCase();
        final projectTitle =
            t.projectId != null ? (projectTitlesById[t.projectId!] ?? '') : '';
        final match = t.title.toLowerCase().contains(query) ||
            (t.description ?? '').toLowerCase().contains(query) ||
            labelsStr.contains(query) ||
            projectTitle.contains(query);
        if (!match) return false;
      }

      return true;
    }).toList();

    const priorityOrder = {'urgent': 0, 'high': 1, 'medium': 2, 'low': 3};
    final farFuture = CalendarDate(year: 2099, month: 12, day: 31);

    list.sort((a, b) {
      if (viewFilter == 'my_day') {
        final orderCmp = a.sortOrder.compareTo(b.sortOrder);
        if (orderCmp != 0) return orderCmp;
      }

      final aPin = a.isPinned ? 0 : 1;
      final bPin = b.isPinned ? 0 : 1;
      if (aPin != bPin) return aPin.compareTo(bPin);

      if (sortBy == 'priority') {
        final pA = priorityOrder[a.priority] ?? 2;
        final pB = priorityOrder[b.priority] ?? 2;
        if (pA != pB) return pA.compareTo(pB);
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      } else if (sortBy == 'created') {
        final createdCmp = b.createdAt.compareTo(a.createdAt);
        if (createdCmp != 0) return createdCmp;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      } else if (sortBy == 'alpha') {
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }

      final aDue = a.dueDate ?? farFuture;
      final bDue = b.dueDate ?? farFuture;
      final dueCmp = aDue.compareTo(bDue);
      if (dueCmp != 0) return dueCmp;

      final aSched = a.scheduledDate ?? farFuture;
      final bSched = b.scheduledDate ?? farFuture;
      final schedCmp = aSched.compareTo(bSched);
      if (schedCmp != 0) return schedCmp;

      final pA = priorityOrder[a.priority] ?? 2;
      final pB = priorityOrder[b.priority] ?? 2;
      if (pA != pB) return pA.compareTo(pB);

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
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

  int get activeCount => pendingTasks.length;

  int get overdueCount =>
      tasks.where((t) => !t.isArchived && t.isOverdue).length;

  int get allCount => tasks.where((t) => !t.isArchived).length;

  int get completedCount =>
      tasks.where((t) => !t.isArchived && t.isCompleted).length;

  int get archivedCount => tasks.where((t) => t.isArchived).length;

  int getProjectProgress(String projectId) {
    final projectTasks = tasks
        .where(
          (t) =>
              t.projectId == projectId &&
              !t.isArchived &&
              t.status != 'cancelled',
        )
        .toList();
    final projectMilestones =
        milestones.where((m) => m.projectId == projectId).toList();

    final completedTasks =
        projectTasks.where((t) => t.isCompleted || t.status == 'completed').length;
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
      isProjectManuallyCompleted: project.status == 'completed' &&
          projectTasks.isEmpty &&
          projectMilestones.isEmpty,
    );
  }
}
