import '../../core/date/shared_date.dart';
import 'task_models.dart';
import 'task_recurrence_engine.dart';

/// Pure domain engine projecting stored Task dates (`scheduledDate`, `dueDate`)
/// and future recurring occurrences onto Calendar date ranges without mutating
/// tasks or duplicating calendar event rows.
///
/// Mirrors `src/domain/taskCalendar.ts` with zero Flutter/SQLite dependencies.
enum TaskCalendarOccurrenceKind {
  due,
  scheduled,
  dueAndScheduled,
  recurringPreview,
}

class TaskCalendarOccurrence {
  final String id;
  final String sourceTaskId;
  final TaskEntity task;
  final CalendarDate occurrenceDate;
  final TaskCalendarOccurrenceKind kind;
  final bool isProjectedOccurrence;
  final String? scheduledTime;
  final int? estimatedDurationMinutes;
  final String priority;
  final bool completed;
  final String? recurrenceSummary;
  final bool isCompletionBasedRecurrence;
  final CalendarDate? companionDueDate;
  final CalendarDate? companionScheduledDate;

  const TaskCalendarOccurrence({
    required this.id,
    required this.sourceTaskId,
    required this.task,
    required this.occurrenceDate,
    required this.kind,
    required this.isProjectedOccurrence,
    this.scheduledTime,
    this.estimatedDurationMinutes,
    required this.priority,
    required this.completed,
    this.recurrenceSummary,
    required this.isCompletionBasedRecurrence,
    this.companionDueDate,
    this.companionScheduledDate,
  });

  String get occurrenceDateIso => occurrenceDate.toIsoString();
}

class TaskCalendarEngine {
  static const int _maxProjectionSteps = 120;

  static const Map<String, int> _priorityRank = <String, int>{
    'urgent': 0,
    'high': 1,
    'medium': 2,
    'low': 3,
  };

  /// Resolves the primary calendar date to jump to when navigating from a Task
  /// to Calendar: prefers `scheduledDate`, falling back to `dueDate`.
  static CalendarDate? getTaskPrimaryCalendarDate(TaskEntity task) {
    return task.scheduledDate ?? task.dueDate;
  }

  static bool _isTaskActiveForCalendar(TaskEntity task) {
    if (task.isArchived) return false;
    if (task.status == 'cancelled') return false;
    return true;
  }

  static String _buildSeriesKey(TaskEntity task) {
    return '${task.title.trim().toLowerCase()}::${task.projectId ?? ''}';
  }

  static bool _hasMatchingStoredOccurrenceOnDate(
    List<TaskEntity> activeTasks,
    TaskEntity sourceTask,
    TaskRecurrenceConfig sourceConfig,
    CalendarDate targetDate,
  ) {
    final targetKey = _buildSeriesKey(sourceTask);
    for (final other in activeTasks) {
      if (_buildSeriesKey(other) != targetKey) continue;
      final otherConfig = TaskRecurrenceEngine.resolveEffectiveConfig(other);
      if (otherConfig == null ||
          !TaskRecurrenceEngine.configsEqual(otherConfig, sourceConfig)) {
        continue;
      }
      if (other.dueDate == targetDate || other.scheduledDate == targetDate) {
        return true;
      }
    }
    return false;
  }

  static List<TaskCalendarOccurrence> sortOccurrences(
    List<TaskCalendarOccurrence> items,
  ) {
    final sorted = List<TaskCalendarOccurrence>.from(items);
    sorted.sort((a, b) {
      final dateCmp = a.occurrenceDate.compareTo(b.occurrenceDate);
      if (dateCmp != 0) return dateCmp;

      if (a.isProjectedOccurrence != b.isProjectedOccurrence) {
        return a.isProjectedOccurrence ? 1 : -1;
      }
      if (a.completed != b.completed) {
        return a.completed ? 1 : -1;
      }

      final timeA = a.scheduledTime ?? '';
      final timeB = b.scheduledTime ?? '';
      if (timeA != timeB) {
        if (timeA.isEmpty) return 1;
        if (timeB.isEmpty) return -1;
        return timeA.compareTo(timeB);
      }

      final rankA = _priorityRank[a.priority] ?? 2;
      final rankB = _priorityRank[b.priority] ?? 2;
      if (rankA != rankB) return rankA.compareTo(rankB);

      return a.task.title.compareTo(b.task.title);
    });
    return List<TaskCalendarOccurrence>.unmodifiable(sorted);
  }

  static List<TaskCalendarOccurrence> projectTasksForDateRange(
    List<TaskEntity> tasks,
    DateRange range,
  ) {
    final activeTasks =
        tasks.where(_isTaskActiveForCalendar).toList(growable: false);
    final occurrences = <TaskCalendarOccurrence>[];
    final emittedKeys = <String>{};

    for (final task in activeTasks) {
      final due = task.dueDate;
      final scheduled = task.scheduledDate;
      final done = task.isCompleted;
      final recConfig = TaskRecurrenceEngine.resolveEffectiveConfig(task);
      final recSummary = recConfig != null
          ? TaskRecurrenceEngine.formatSummary(recConfig)
          : null;
      final normalizedSummary =
          (recSummary != null && recSummary.trim().isNotEmpty)
              ? recSummary
              : null;
      final isCompletionBased = recConfig?.repeatFrom == 'completion_date';

      if (scheduled != null && due != null && scheduled == due) {
        if (range.contains(due)) {
          final iso = due.toIsoString();
          emittedKeys.add('${task.id}::$iso');
          occurrences.add(
            TaskCalendarOccurrence(
              id: '${task.id}::$iso',
              sourceTaskId: task.id,
              task: task,
              occurrenceDate: due,
              kind: TaskCalendarOccurrenceKind.dueAndScheduled,
              isProjectedOccurrence: false,
              scheduledTime: task.scheduledTime,
              estimatedDurationMinutes: task.estimatedDurationMinutes,
              priority: task.priority,
              completed: done,
              recurrenceSummary: normalizedSummary,
              isCompletionBasedRecurrence: isCompletionBased,
            ),
          );
        }
      } else {
        if (scheduled != null && range.contains(scheduled)) {
          final iso = scheduled.toIsoString();
          emittedKeys.add('${task.id}::$iso');
          occurrences.add(
            TaskCalendarOccurrence(
              id: '${task.id}::$iso',
              sourceTaskId: task.id,
              task: task,
              occurrenceDate: scheduled,
              kind: TaskCalendarOccurrenceKind.scheduled,
              isProjectedOccurrence: false,
              scheduledTime: task.scheduledTime,
              estimatedDurationMinutes: task.estimatedDurationMinutes,
              priority: task.priority,
              completed: done,
              recurrenceSummary: normalizedSummary,
              isCompletionBasedRecurrence: isCompletionBased,
              companionDueDate: due,
            ),
          );
        }

        if (due != null && range.contains(due)) {
          final iso = due.toIsoString();
          emittedKeys.add('${task.id}::$iso');
          occurrences.add(
            TaskCalendarOccurrence(
              id: '${task.id}::$iso',
              sourceTaskId: task.id,
              task: task,
              occurrenceDate: due,
              kind: TaskCalendarOccurrenceKind.due,
              isProjectedOccurrence: false,
              scheduledTime: scheduled != null ? null : task.scheduledTime,
              estimatedDurationMinutes:
                  scheduled != null ? null : task.estimatedDurationMinutes,
              priority: task.priority,
              completed: done,
              recurrenceSummary: normalizedSummary,
              isCompletionBasedRecurrence: isCompletionBased,
              companionScheduledDate: scheduled,
            ),
          );
        }
      }

      if (!done &&
          recConfig != null &&
          (due != null || scheduled != null || recConfig.startDate != null)) {
        var cursor = task;
        final seenProjected = <String>{};

        for (var step = 0; step < _maxProjectionSteps; step++) {
          final nextDates = TaskRecurrenceEngine.computeNextOccurrenceDates(
            cursor,
            recConfig,
            forCompletion: false,
          );
          if (nextDates == null) break;

          final nextDate = nextDates.primaryDate;
          final nextIso = nextDate.toIsoString();
          if (seenProjected.contains(nextIso)) break;
          seenProjected.add(nextIso);

          if (nextDate.isAfter(range.end)) break;

          if (range.contains(nextDate) &&
              !emittedKeys.contains('${task.id}::$nextIso') &&
              !_hasMatchingStoredOccurrenceOnDate(
                activeTasks,
                task,
                recConfig,
                nextDate,
              )) {
            emittedKeys.add('${task.id}::$nextIso');
            occurrences.add(
              TaskCalendarOccurrence(
                id: '${task.id}::preview::$nextIso',
                sourceTaskId: task.id,
                task: task,
                occurrenceDate: nextDate,
                kind: TaskCalendarOccurrenceKind.recurringPreview,
                isProjectedOccurrence: true,
                scheduledTime: task.scheduledTime,
                estimatedDurationMinutes: task.estimatedDurationMinutes,
                priority: task.priority,
                completed: false,
                recurrenceSummary: normalizedSummary,
                isCompletionBasedRecurrence: isCompletionBased,
              ),
            );
          }

          cursor = TaskEntity(
            id: cursor.id,
            title: cursor.title,
            dueDate: nextDates.dueDate,
            scheduledDate: nextDates.scheduledDate,
            createdAt: cursor.createdAt,
            updatedAt: cursor.updatedAt,
          );
        }
      }
    }

    return sortOccurrences(occurrences);
  }

  static List<TaskCalendarOccurrence> projectTasksForDate(
    List<TaskEntity> tasks,
    CalendarDate date,
  ) {
    return projectTasksForDateRange(
      tasks,
      DateRange(start: date, end: date),
    );
  }

  static List<TaskCalendarOccurrence> occurrencesOnDate(
    List<TaskCalendarOccurrence> occurrences,
    CalendarDate date,
  ) {
    return occurrences
        .where((o) => o.occurrenceDate == date)
        .toList(growable: false);
  }
}
