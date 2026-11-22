import '../../core/date/shared_date.dart';
import './task_models.dart';

/// Pure domain engine for Daywell Stage 2 — My Day & Daily Planning.
///
/// Invariants:
/// - Zero dependencies on Flutter widgets, application controllers, or Drift SQLite.
/// - Preserves per-date planning history keyed by (taskId, planDate).
/// - Uses canonical Ethiopia civil calendar dates ([CalendarDate], UTC+3).
class DailyPlanningActions {
  static const String planned = 'planned';
  static const String carriedForward = 'carried_forward';
  static const String completed = 'completed';
  static const String dismissed = 'dismissed';

  static const Set<String> validActions = {
    planned,
    carriedForward,
    completed,
    dismissed,
  };

  static String normalize(String? action) {
    final trimmed = action?.trim() ?? '';
    return validActions.contains(trimmed) ? trimmed : planned;
  }
}

class DailyPlanItem {
  final TaskEntity task;
  final DailyPlanningEntryEntity? entry;
  final CalendarDate planDate;
  final String action;
  final bool isCompletedForDay;
  final bool completedLater;
  final bool isCarriedForward;

  const DailyPlanItem({
    required this.task,
    required this.entry,
    required this.planDate,
    required this.action,
    required this.isCompletedForDay,
    required this.completedLater,
    required this.isCarriedForward,
  });
}

enum DailyPlanSuggestionReason {
  carryForward,
  overdue,
  scheduled,
}

class DailyPlanSuggestion {
  final TaskEntity task;
  final DailyPlanSuggestionReason reason;
  final CalendarDate? sourcePlanDate;

  const DailyPlanSuggestion({
    required this.task,
    required this.reason,
    this.sourcePlanDate,
  });
}

class DailyPlanSnapshot {
  final CalendarDate selectedDate;
  final CalendarDate todayDate;
  final bool isToday;
  final bool isPastDay;
  final bool isFutureDay;
  final List<DailyPlanItem> items;
  final List<DailyPlanItem> remainingItems;
  final List<DailyPlanItem> completedItems;
  final int dismissedCount;
  final int totalPlannedCount;
  final int completedCount;
  final int remainingCount;
  final int progressPercentage;
  final List<DailyPlanSuggestion> carryForwardSuggestions;
  final List<DailyPlanSuggestion> overdueSuggestions;
  final List<DailyPlanSuggestion> scheduledSuggestions;
  final List<TaskEntity> otherActiveTasks;
  final List<CalendarDate> historyDates;

  const DailyPlanSnapshot({
    required this.selectedDate,
    required this.todayDate,
    required this.isToday,
    required this.isPastDay,
    required this.isFutureDay,
    required this.items,
    required this.remainingItems,
    required this.completedItems,
    required this.dismissedCount,
    required this.totalPlannedCount,
    required this.completedCount,
    required this.remainingCount,
    required this.progressPercentage,
    required this.carryForwardSuggestions,
    required this.overdueSuggestions,
    required this.scheduledSuggestions,
    required this.otherActiveTasks,
    required this.historyDates,
  });
}

class DailyPlanningEngine {
  static const Map<String, int> _priorityOrder = {
    'urgent': 0,
    'high': 1,
    'medium': 2,
    'low': 3,
  };

  static String buildEntryId(String taskId, CalendarDate planDate) {
    return 'dpe-${planDate.toIsoString()}-${taskId.trim()}';
  }

  static DailyPlanningEntryEntity? findEntry(
    List<DailyPlanningEntryEntity> entries,
    String taskId,
    CalendarDate planDate,
  ) {
    for (final e in entries) {
      if (e.taskId == taskId && e.planDate == planDate) {
        return e;
      }
    }
    return null;
  }

  static List<DailyPlanningEntryEntity> normalizeEntries(
    List<DailyPlanningEntryEntity> entries,
  ) {
    final byComposite = <String, DailyPlanningEntryEntity>{};
    for (final raw in entries) {
      final cleanTaskId = raw.taskId.trim();
      if (cleanTaskId.isEmpty) continue;
      final cleanId = raw.id.trim().isNotEmpty
          ? raw.id.trim()
          : buildEntryId(cleanTaskId, raw.planDate);
      final normalized = DailyPlanningEntryEntity(
        id: cleanId,
        planDate: raw.planDate,
        taskId: cleanTaskId,
        action: DailyPlanningActions.normalize(raw.action),
        createdAt: raw.createdAt,
        updatedAt: raw.updatedAt,
      );
      final key = '$cleanTaskId::${raw.planDate.toIsoString()}';
      final existing = byComposite[key];
      if (existing == null) {
        byComposite[key] = normalized;
      } else {
        final existingFreshness = existing.updatedAt ?? existing.createdAt;
        final nextFreshness = normalized.updatedAt ?? normalized.createdAt;
        if (!nextFreshness.isBefore(existingFreshness)) {
          byComposite[key] = normalized;
        }
      }
    }
    final list = byComposite.values.toList(growable: false);
    list.sort((a, b) {
      final dateCmp = a.planDate.compareTo(b.planDate);
      if (dateCmp != 0) return dateCmp;
      return a.createdAt.compareTo(b.createdAt);
    });
    return List<DailyPlanningEntryEntity>.unmodifiable(list);
  }

  static bool isTaskPlannedForDate(
    TaskEntity task,
    List<DailyPlanningEntryEntity> entries,
    CalendarDate planDate, {
    CalendarDate? today,
  }) {
    if (task.isArchived) return false;
    final resolvedToday = today ?? CalendarDate.today();
    final entry = findEntry(entries, task.id, planDate);
    if (entry != null) {
      return entry.action != DailyPlanningActions.dismissed;
    }
    if (!task.isMyDay) return false;
    if (task.myDayDate == null) {
      return planDate == resolvedToday;
    }
    return task.myDayDate == planDate;
  }

  static bool hasPriorPlannedHistory(
    List<DailyPlanningEntryEntity> entries,
    String taskId,
    CalendarDate beforeDate,
  ) {
    return entries.any(
      (e) =>
          e.taskId == taskId &&
          e.planDate.isBefore(beforeDate) &&
          e.action != DailyPlanningActions.dismissed,
    );
  }

  static String nextActionOnReopen(
    List<DailyPlanningEntryEntity> entries,
    String taskId,
    CalendarDate planDate,
  ) {
    return hasPriorPlannedHistory(entries, taskId, planDate)
        ? DailyPlanningActions.carriedForward
        : DailyPlanningActions.planned;
  }

  static int nextSortOrderForPlannedDay(
    List<TaskEntity> tasks,
    List<DailyPlanningEntryEntity> entries,
    CalendarDate planDate, {
    required String excludeTaskId,
    CalendarDate? today,
  }) {
    final resolvedToday = today ?? CalendarDate.today();
    var hasOthers = false;
    var maxOrder = 0;
    for (final t in tasks) {
      if (t.id == excludeTaskId) continue;
      if (!isTaskPlannedForDate(t, entries, planDate, today: resolvedToday)) {
        continue;
      }
      hasOthers = true;
      if (t.sortOrder > maxOrder) {
        maxOrder = t.sortOrder;
      }
    }
    return hasOthers ? maxOrder + 1 : 0;
  }

  static CalendarDate? findTargetPlanDateForCompletion(
    TaskEntity task,
    List<DailyPlanningEntryEntity> entries, {
    CalendarDate? preferredPlanDate,
    CalendarDate? today,
  }) {
    final resolvedToday = today ?? CalendarDate.today();
    final normalized = normalizeEntries(entries);

    if (preferredPlanDate != null &&
        isTaskPlannedForDate(
          task,
          normalized,
          preferredPlanDate,
          today: resolvedToday,
        )) {
      return preferredPlanDate;
    }
    if (isTaskPlannedForDate(task, normalized, resolvedToday,
        today: resolvedToday)) {
      return resolvedToday;
    }
    if (task.myDayDate != null &&
        isTaskPlannedForDate(
          task,
          normalized,
          task.myDayDate!,
          today: resolvedToday,
        )) {
      return task.myDayDate!;
    }
    final activeDates = normalized
        .where(
          (e) =>
              e.taskId == task.id && e.action != DailyPlanningActions.dismissed,
        )
        .map((e) => e.planDate)
        .toList(growable: false);
    if (activeDates.isNotEmpty) {
      return activeDates.last;
    }
    return null;
  }

  static List<CalendarDate> extractHistoryDates(
    List<TaskEntity> tasks,
    List<DailyPlanningEntryEntity> entries, {
    CalendarDate? today,
  }) {
    final resolvedToday = today ?? CalendarDate.today();
    final dates = <CalendarDate>{};
    for (final e in entries) {
      if (e.action != DailyPlanningActions.dismissed) {
        dates.add(e.planDate);
      }
    }
    for (final t in tasks) {
      if (t.isMyDay && !t.isArchived) {
        dates.add(t.myDayDate ?? resolvedToday);
      }
    }
    final sorted = dates.toList(growable: false);
    sorted.sort((a, b) => b.compareTo(a));
    return List<CalendarDate>.unmodifiable(sorted);
  }

  static int compareTasksForDailyPlan(TaskEntity a, TaskEntity b) {
    final orderCmp = a.sortOrder.compareTo(b.sortOrder);
    if (orderCmp != 0) return orderCmp;

    final pinA = a.isPinned ? 0 : 1;
    final pinB = b.isPinned ? 0 : 1;
    if (pinA != pinB) return pinA.compareTo(pinB);

    final prioA = _priorityOrder[a.priority] ?? 2;
    final prioB = _priorityOrder[b.priority] ?? 2;
    if (prioA != prioB) return prioA.compareTo(prioB);

    final farFuture = CalendarDate(year: 2099, month: 12, day: 31);
    final dueCmp = (a.dueDate ?? farFuture).compareTo(b.dueDate ?? farFuture);
    if (dueCmp != 0) return dueCmp;

    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  static DailyPlanSnapshot buildSnapshot({
    required List<TaskEntity> tasks,
    required List<DailyPlanningEntryEntity> entries,
    required CalendarDate selectedDate,
    CalendarDate? today,
  }) {
    final resolvedToday = today ?? CalendarDate.today();
    final normalizedEntries = normalizeEntries(entries);

    final items = <DailyPlanItem>[];
    final plannedTaskIds = <String>{};
    var dismissedCount = 0;

    for (final task in tasks) {
      if (task.isArchived) continue;
      final entry = findEntry(normalizedEntries, task.id, selectedDate);
      if (entry != null && entry.action == DailyPlanningActions.dismissed) {
        dismissedCount += 1;
        continue;
      }
      if (!isTaskPlannedForDate(
        task,
        normalizedEntries,
        selectedDate,
        today: resolvedToday,
      )) {
        continue;
      }

      plannedTaskIds.add(task.id);
      final completedForDay = entry != null
          ? (entry.action == DailyPlanningActions.completed ||
              (!selectedDate.isBefore(resolvedToday) && task.isCompleted))
          : task.isCompleted;
      final completedLater = entry != null &&
          entry.action != DailyPlanningActions.completed &&
          selectedDate.isBefore(resolvedToday) &&
          task.isCompleted;
      final action = completedForDay
          ? DailyPlanningActions.completed
          : (entry?.action ?? DailyPlanningActions.planned);

      items.add(
        DailyPlanItem(
          task: task,
          entry: entry,
          planDate: selectedDate,
          action: action,
          isCompletedForDay: completedForDay,
          completedLater: completedLater,
          isCarriedForward: action == DailyPlanningActions.carriedForward,
        ),
      );
    }

    items.sort((a, b) => compareTasksForDailyPlan(a.task, b.task));

    final remainingItems =
        items.where((i) => !i.isCompletedForDay).toList(growable: false);
    final completedItems =
        items.where((i) => i.isCompletedForDay).toList(growable: false);
    final totalCount = items.length;
    final completedCount = completedItems.length;
    final remainingCount = remainingItems.length;
    final progressPct =
        totalCount == 0 ? 0 : ((completedCount / totalCount) * 100).round();

    final latestPriorPlanByTask = <String, CalendarDate>{};
    for (final e in normalizedEntries) {
      if (e.planDate.isBefore(selectedDate) &&
          e.action != DailyPlanningActions.dismissed) {
        final existing = latestPriorPlanByTask[e.taskId];
        if (existing == null || e.planDate.isAfter(existing)) {
          latestPriorPlanByTask[e.taskId] = e.planDate;
        }
      }
    }
    for (final t in tasks) {
      if (t.isMyDay &&
          t.myDayDate != null &&
          t.myDayDate!.isBefore(selectedDate)) {
        final existing = latestPriorPlanByTask[t.id];
        if (existing == null || t.myDayDate!.isAfter(existing)) {
          latestPriorPlanByTask[t.id] = t.myDayDate!;
        }
      }
    }

    final carryForwardSuggestions = <DailyPlanSuggestion>[];
    final overdueSuggestions = <DailyPlanSuggestion>[];
    final scheduledSuggestions = <DailyPlanSuggestion>[];
    final otherActiveTasks = <TaskEntity>[];

    for (final task in tasks) {
      if (task.isArchived || plannedTaskIds.contains(task.id)) continue;
      if (task.isCompleted || task.status == 'cancelled') continue;

      final priorDate = latestPriorPlanByTask[task.id];
      if (priorDate != null) {
        carryForwardSuggestions.add(
          DailyPlanSuggestion(
            task: task,
            reason: DailyPlanSuggestionReason.carryForward,
            sourcePlanDate: priorDate,
          ),
        );
      }

      final isOverdue =
          task.dueDate != null && task.dueDate!.isBefore(resolvedToday);
      final isScheduledForSelected =
          task.dueDate == selectedDate || task.scheduledDate == selectedDate;

      if (isOverdue) {
        overdueSuggestions.add(
          DailyPlanSuggestion(
            task: task,
            reason: DailyPlanSuggestionReason.overdue,
          ),
        );
      } else if (isScheduledForSelected) {
        scheduledSuggestions.add(
          DailyPlanSuggestion(
            task: task,
            reason: DailyPlanSuggestionReason.scheduled,
          ),
        );
      } else if (priorDate == null) {
        otherActiveTasks.add(task);
      }
    }

    carryForwardSuggestions.sort(
      (a, b) => compareTasksForDailyPlan(a.task, b.task),
    );
    overdueSuggestions.sort(
      (a, b) => compareTasksForDailyPlan(a.task, b.task),
    );
    scheduledSuggestions.sort(
      (a, b) => compareTasksForDailyPlan(a.task, b.task),
    );
    otherActiveTasks.sort(compareTasksForDailyPlan);

    return DailyPlanSnapshot(
      selectedDate: selectedDate,
      todayDate: resolvedToday,
      isToday: selectedDate == resolvedToday,
      isPastDay: selectedDate.isBefore(resolvedToday),
      isFutureDay: selectedDate.isAfter(resolvedToday),
      items: List<DailyPlanItem>.unmodifiable(items),
      remainingItems: List<DailyPlanItem>.unmodifiable(remainingItems),
      completedItems: List<DailyPlanItem>.unmodifiable(completedItems),
      dismissedCount: dismissedCount,
      totalPlannedCount: totalCount,
      completedCount: completedCount,
      remainingCount: remainingCount,
      progressPercentage: progressPct,
      carryForwardSuggestions:
          List<DailyPlanSuggestion>.unmodifiable(carryForwardSuggestions),
      overdueSuggestions:
          List<DailyPlanSuggestion>.unmodifiable(overdueSuggestions),
      scheduledSuggestions:
          List<DailyPlanSuggestion>.unmodifiable(scheduledSuggestions),
      otherActiveTasks: List<TaskEntity>.unmodifiable(otherActiveTasks),
      historyDates: extractHistoryDates(
        tasks,
        normalizedEntries,
        today: resolvedToday,
      ),
    );
  }
}
