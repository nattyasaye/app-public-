import '../../core/date/shared_date.dart';
import 'task_models.dart';

/// Pure domain engine for recurring Task calculations, occurrence generation,
/// skipping, rescheduling, stopping, and duplicate prevention.
///
/// Mirrors `src/domain/taskRecurrence.ts` without Flutter or SQLite dependencies.
class TaskRecurrenceEngine {
  static const List<String> validFrequencies = <String>[
    'daily',
    'weekly',
    'monthly',
    'yearly',
  ];

  static const List<String> validRepeatFromModes = <String>[
    'due_date',
    'completion_date',
  ];

  static const List<String> _isoShortWeekdays = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static TaskRecurrenceConfig? normalizeConfig(TaskRecurrenceConfig? config) {
    if (config == null) return null;
    final freq = config.frequency.trim().toLowerCase();
    if (!validFrequencies.contains(freq)) return null;

    final rawInterval = config.interval;
    final interval =
        (rawInterval != null && rawInterval >= 1) ? rawInterval : 1;

    List<int>? weekdays;
    if (freq == 'weekly' && config.weekdays != null) {
      final unique = config.weekdays!
          .where((d) => d >= 1 && d <= 7)
          .toSet()
          .toList()
        ..sort();
      if (unique.isNotEmpty) {
        weekdays = List<int>.unmodifiable(unique);
      }
    }

    final rawRepeat = config.repeatFrom?.trim().toLowerCase() ?? '';
    final repeatFrom =
        validRepeatFromModes.contains(rawRepeat) ? rawRepeat : 'due_date';

    return TaskRecurrenceConfig(
      frequency: freq,
      interval: interval,
      weekdays: weekdays,
      startDate: config.startDate,
      endDate: config.endDate,
      repeatFrom: repeatFrom,
    );
  }

  static ({bool isValid, Map<String, String> errors}) validateConfig(
    TaskRecurrenceConfig? config,
  ) {
    final errors = <String, String>{};
    if (config == null) return (isValid: true, errors: errors);

    final freq = config.frequency.trim().toLowerCase();
    if (!validFrequencies.contains(freq)) {
      errors['recurrenceFrequency'] =
          'Recurrence frequency must be daily, weekly, monthly, or yearly';
    }
    if (config.interval != null && config.interval! < 1) {
      errors['recurrenceInterval'] =
          'Repeat interval must be a whole number of at least 1';
    }
    if (config.weekdays != null &&
        config.weekdays!.any((d) => d < 1 || d > 7)) {
      errors['recurrenceWeekdays'] =
          'Weekdays must use ISO days 1 (Mon) through 7 (Sun)';
    }
    if (config.startDate != null &&
        config.endDate != null &&
        config.endDate!.isBefore(config.startDate!)) {
      errors['recurrenceEndDate'] =
          'Recurrence end date cannot precede start date';
    }
    return (isValid: errors.isEmpty, errors: errors);
  }

  static TaskRecurrenceConfig? resolveEffectiveConfig(TaskEntity task) {
    final normalized = normalizeConfig(task.recurrenceConfig);
    if (normalized != null) return normalized;

    final rawRule = task.recurrenceRule?.trim().toLowerCase();
    if (rawRule != null && validFrequencies.contains(rawRule)) {
      return TaskRecurrenceConfig(
        frequency: rawRule,
        interval: 1,
        repeatFrom: 'due_date',
      );
    }
    return null;
  }

  static bool configsEqual(
    TaskRecurrenceConfig? a,
    TaskRecurrenceConfig? b,
  ) {
    final normA = normalizeConfig(a);
    final normB = normalizeConfig(b);
    if (normA == null && normB == null) return true;
    if (normA == null || normB == null) return false;
    if (normA.frequency != normB.frequency) return false;
    if ((normA.interval ?? 1) != (normB.interval ?? 1)) return false;
    if ((normA.repeatFrom ?? 'due_date') != (normB.repeatFrom ?? 'due_date')) {
      return false;
    }
    if (normA.startDate != normB.startDate) return false;
    if (normA.endDate != normB.endDate) return false;

    final wdA = normA.weekdays ?? const <int>[];
    final wdB = normB.weekdays ?? const <int>[];
    if (wdA.length != wdB.length) return false;
    for (var i = 0; i < wdA.length; i++) {
      if (wdA[i] != wdB[i]) return false;
    }
    return true;
  }

  static CalendarDate? computeNextRecurrenceDate(
    CalendarDate anchor,
    TaskRecurrenceConfig config,
  ) {
    final normalized = normalizeConfig(config);
    if (normalized == null) return null;

    final interval = normalized.interval ?? 1;
    late CalendarDate candidate;

    switch (normalized.frequency) {
      case 'daily':
        candidate = anchor.addDays(interval);
        break;
      case 'weekly':
        final weekdays =
            (normalized.weekdays != null && normalized.weekdays!.isNotEmpty)
                ? normalized.weekdays!
                : <int>[anchor.weekday];
        int? laterSameWeek;
        for (final wd in weekdays) {
          if (wd > anchor.weekday) {
            laterSameWeek = wd;
            break;
          }
        }
        if (laterSameWeek != null) {
          candidate = anchor.addDays(laterSameWeek - anchor.weekday);
        } else {
          final mondayOfAnchorWeek = anchor.subtractDays(anchor.weekday - 1);
          final nextCycleMonday = mondayOfAnchorWeek.addDays(7 * interval);
          candidate = nextCycleMonday.addDays(weekdays.first - 1);
        }
        break;
      case 'monthly':
        final totalMonths = anchor.year * 12 + (anchor.month - 1) + interval;
        final nextYear = totalMonths ~/ 12;
        final nextMonth = (totalMonths % 12) + 1;
        final maxDay = CalendarEngine.daysInGregorianMonth(nextYear, nextMonth);
        candidate = CalendarDate(
          year: nextYear,
          month: nextMonth,
          day: anchor.day > maxDay ? maxDay : anchor.day,
        );
        break;
      case 'yearly':
        final nextYear = anchor.year + interval;
        final maxDay =
            CalendarEngine.daysInGregorianMonth(nextYear, anchor.month);
        candidate = CalendarDate(
          year: nextYear,
          month: anchor.month,
          day: anchor.day > maxDay ? maxDay : anchor.day,
        );
        break;
      default:
        return null;
    }

    final start = normalized.startDate;
    if (start != null && candidate.isBefore(start)) {
      if (normalized.frequency == 'weekly' &&
          normalized.weekdays != null &&
          normalized.weekdays!.isNotEmpty) {
        for (var offset = 0; offset < 7; offset++) {
          final probe = start.addDays(offset);
          if (normalized.weekdays!.contains(probe.weekday)) {
            candidate = probe;
            break;
          }
        }
      } else {
        candidate = start;
      }
    }

    final end = normalized.endDate;
    if (end != null && candidate.isAfter(end)) {
      return null;
    }
    return candidate;
  }

  static CalendarDate resolveRecurrenceAnchorDate(
    TaskEntity task,
    TaskRecurrenceConfig config, {
    bool forCompletion = false,
    DateTime? nowUtc,
    CalendarDate? today,
  }) {
    if (forCompletion && config.repeatFrom == 'completion_date') {
      if (nowUtc != null) {
        return CalendarDate.fromUtcInstantInEthiopia(nowUtc);
      }
      return today ??
          CalendarDate.fromUtcInstantInEthiopia(EthiopiaClock.nowUtc());
    }

    return task.dueDate ??
        task.scheduledDate ??
        config.startDate ??
        today ??
        (nowUtc != null
            ? CalendarDate.fromUtcInstantInEthiopia(nowUtc)
            : CalendarDate.today());
  }

  static ({
    CalendarDate? dueDate,
    CalendarDate? scheduledDate,
    CalendarDate primaryDate,
  })? computeNextOccurrenceDates(
    TaskEntity task,
    TaskRecurrenceConfig config, {
    bool forCompletion = false,
    DateTime? nowUtc,
    CalendarDate? today,
  }) {
    final normalized = normalizeConfig(config);
    if (normalized == null) return null;

    final anchor = resolveRecurrenceAnchorDate(
      task,
      normalized,
      forCompletion: forCompletion,
      nowUtc: nowUtc,
      today: today,
    );
    final nextDate = computeNextRecurrenceDate(anchor, normalized);
    if (nextDate == null) return null;

    final prevDue = task.dueDate;
    final prevScheduled = task.scheduledDate;

    if (prevDue != null && prevScheduled != null) {
      final offsetDays = prevScheduled.differenceInDays(prevDue);
      return (
        dueDate: nextDate,
        scheduledDate: nextDate.addDays(offsetDays),
        primaryDate: nextDate,
      );
    }
    if (prevDue != null) {
      return (
        dueDate: nextDate,
        scheduledDate: null,
        primaryDate: nextDate,
      );
    }
    if (prevScheduled != null) {
      return (
        dueDate: null,
        scheduledDate: nextDate,
        primaryDate: nextDate,
      );
    }
    return (
      dueDate: nextDate,
      scheduledDate: null,
      primaryDate: nextDate,
    );
  }

  static CalendarDate? previewNextOccurrenceDate(
    TaskEntity task,
    TaskRecurrenceConfig? config, {
    DateTime? nowUtc,
    CalendarDate? today,
  }) {
    if (config == null) return null;
    return computeNextOccurrenceDates(
      task,
      config,
      forCompletion: false,
      nowUtc: nowUtc,
      today: today,
    )?.primaryDate;
  }

  static String formatSummary(TaskRecurrenceConfig? config) {
    final normalized = normalizeConfig(config);
    if (normalized == null) return '';
    final interval = normalized.interval ?? 1;

    switch (normalized.frequency) {
      case 'daily':
        return interval == 1 ? 'Daily' : 'Every $interval days';
      case 'weekly':
        final baseUnit = interval == 1 ? 'Weekly' : 'Every $interval weeks';
        if (normalized.weekdays != null && normalized.weekdays!.isNotEmpty) {
          final names = normalized.weekdays!
              .where((d) => d >= 1 && d <= 7)
              .map((d) => _isoShortWeekdays[d - 1])
              .join(', ');
          return names.isNotEmpty ? '$baseUnit ($names)' : baseUnit;
        }
        return baseUnit;
      case 'monthly':
        return interval == 1 ? 'Monthly' : 'Every $interval months';
      case 'yearly':
        return interval == 1 ? 'Yearly' : 'Every $interval years';
      default:
        return '';
    }
  }

  static String _buildNextOccurrenceId(
    List<TaskEntity> existingTasks,
    DateTime now, {
    String? preferredId,
  }) {
    final used = existingTasks.map((t) => t.id).toSet();
    if (preferredId != null &&
        preferredId.trim().isNotEmpty &&
        !used.contains(preferredId.trim())) {
      return preferredId.trim();
    }
    var candidate = 'task-${now.microsecondsSinceEpoch}';
    var suffix = 1;
    while (used.contains(candidate)) {
      candidate = 'task-${now.microsecondsSinceEpoch}-$suffix';
      suffix++;
    }
    return candidate;
  }

  static List<TaskSubtask> _cloneResetSubtasks(
    List<TaskSubtask> subtasks,
    String nextTaskId,
  ) {
    return List<TaskSubtask>.unmodifiable([
      for (var i = 0; i < subtasks.length; i++)
        TaskSubtask(
          id: '$nextTaskId-sub-${i + 1}',
          title: subtasks[i].title,
          done: false,
        ),
    ]);
  }

  static bool hasMatchingActiveOrDateOccurrence(
    List<TaskEntity> existingTasks,
    TaskEntity sourceTask,
    CalendarDate nextPrimaryDate,
    TaskRecurrenceConfig effectiveConfig,
  ) {
    final sourceTitle = sourceTask.title.trim().toLowerCase();
    final sourceProjectId = sourceTask.projectId;

    for (final other in existingTasks) {
      if (other.id == sourceTask.id) continue;
      if (other.isArchived) continue;
      if (other.status == 'cancelled') continue;
      if (other.title.trim().toLowerCase() != sourceTitle) continue;
      if (other.projectId != sourceProjectId) continue;

      final otherConfig = resolveEffectiveConfig(other);
      if (!configsEqual(otherConfig, effectiveConfig)) continue;

      final otherPrimary = other.dueDate ?? other.scheduledDate;
      if (otherPrimary == null) continue;
      if (otherPrimary == nextPrimaryDate) return true;
      if (!other.isCompleted && !otherPrimary.isBefore(nextPrimaryDate)) {
        return true;
      }
    }
    return false;
  }

  static ({
    List<TaskEntity> tasks,
    TaskEntity? updatedTask,
    TaskEntity? generatedNextTask,
    bool seriesEnded,
    bool duplicatePrevented,
  }) completeTaskWithRecurrence(
    List<TaskEntity> existingTasks,
    String taskId, {
    DateTime? nowUtc,
    CalendarDate? today,
    String? nextTaskId,
  }) {
    TaskEntity? target;
    for (final t in existingTasks) {
      if (t.id == taskId) {
        target = t;
        break;
      }
    }
    if (target == null) {
      return (
        tasks: List<TaskEntity>.from(existingTasks),
        updatedTask: null,
        generatedNextTask: null,
        seriesEnded: false,
        duplicatePrevented: false,
      );
    }

    final now = (nowUtc ?? EthiopiaClock.nowUtc()).toUtc();
    if (target.isCompleted) {
      final reopened = target.copyWith(
        status: 'not_started',
        clearCompletedAt: true,
        updatedAt: now,
      );
      return (
        tasks: existingTasks
            .map((t) => t.id == taskId ? reopened : t)
            .toList(growable: false),
        updatedTask: reopened,
        generatedNextTask: null,
        seriesEnded: false,
        duplicatePrevented: false,
      );
    }

    final completedTask = target.copyWith(
      status: 'completed',
      completedAt: target.completedAt ?? now,
      updatedAt: now,
    );
    final updatedList = existingTasks
        .map((t) => t.id == taskId ? completedTask : t)
        .toList(growable: false);

    final effectiveConfig = resolveEffectiveConfig(target);
    if (effectiveConfig == null || target.isArchived) {
      return (
        tasks: updatedList,
        updatedTask: completedTask,
        generatedNextTask: null,
        seriesEnded: false,
        duplicatePrevented: false,
      );
    }

    final nextDates = computeNextOccurrenceDates(
      target,
      effectiveConfig,
      forCompletion: true,
      nowUtc: now,
      today: today,
    );

    if (nextDates == null) {
      return (
        tasks: updatedList,
        updatedTask: completedTask,
        generatedNextTask: null,
        seriesEnded: true,
        duplicatePrevented: false,
      );
    }

    if (hasMatchingActiveOrDateOccurrence(
      updatedList,
      target,
      nextDates.primaryDate,
      effectiveConfig,
    )) {
      return (
        tasks: updatedList,
        updatedTask: completedTask,
        generatedNextTask: null,
        seriesEnded: false,
        duplicatePrevented: true,
      );
    }

    final nextId = _buildNextOccurrenceId(
      updatedList,
      now,
      preferredId: nextTaskId,
    );
    final generatedNextTask = TaskEntity(
      id: nextId,
      title: target.title,
      description: target.description,
      status: 'not_started',
      priority: target.priority,
      completedAt: null,
      dueDate: nextDates.dueDate,
      scheduledDate: nextDates.scheduledDate,
      scheduledTime: target.scheduledTime,
      estimatedDurationMinutes: target.estimatedDurationMinutes,
      projectId: target.projectId,
      milestoneId: target.milestoneId,
      subtasks: _cloneResetSubtasks(target.subtasks, nextId),
      labels: List<String>.unmodifiable(target.labels),
      isPinned: target.isPinned,
      isMyDay: false,
      myDayDate: null,
      recurrenceRule: effectiveConfig.frequency,
      recurrenceConfig: effectiveConfig,
      isArchived: false,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    );

    return (
      tasks: <TaskEntity>[generatedNextTask, ...updatedList],
      updatedTask: completedTask,
      generatedNextTask: generatedNextTask,
      seriesEnded: false,
      duplicatePrevented: false,
    );
  }

  static ({bool ok, String? error, TaskEntity? updatedTask}) skipOccurrence(
    TaskEntity target, {
    DateTime? nowUtc,
    CalendarDate? today,
  }) {
    if (target.isCompleted) {
      return (
        ok: false,
        error: 'Completed tasks cannot be skipped.',
        updatedTask: null,
      );
    }
    final effectiveConfig = resolveEffectiveConfig(target);
    if (effectiveConfig == null) {
      return (
        ok: false,
        error: 'This task does not have an active recurrence rule.',
        updatedTask: null,
      );
    }
    final nextDates = computeNextOccurrenceDates(
      target,
      effectiveConfig,
      forCompletion: false,
      nowUtc: nowUtc,
      today: today,
    );
    if (nextDates == null) {
      return (
        ok: false,
        error: 'Recurrence end date reached; no upcoming occurrence.',
        updatedTask: null,
      );
    }

    final clearMyDayForNewDate =
        target.myDayDate != null && target.myDayDate != nextDates.primaryDate;
    final updated = target.copyWith(
      dueDate: nextDates.dueDate,
      clearDueDate: nextDates.dueDate == null,
      scheduledDate: nextDates.scheduledDate,
      clearScheduledDate: nextDates.scheduledDate == null,
      isMyDay: clearMyDayForNewDate ? false : target.isMyDay,
      clearMyDayDate: clearMyDayForNewDate,
      updatedAt: (nowUtc ?? EthiopiaClock.nowUtc()).toUtc(),
    );
    return (ok: true, error: null, updatedTask: updated);
  }

  static TaskEntity rescheduleOccurrence(
    TaskEntity target,
    CalendarDate newDate, {
    DateTime? nowUtc,
  }) {
    final prevDue = target.dueDate;
    final prevScheduled = target.scheduledDate;
    CalendarDate? nextDue;
    CalendarDate? nextScheduled;

    if (prevDue != null && prevScheduled != null) {
      final offset = prevScheduled.differenceInDays(prevDue);
      nextDue = newDate;
      nextScheduled = newDate.addDays(offset);
    } else if (prevScheduled != null && prevDue == null) {
      nextScheduled = newDate;
      nextDue = null;
    } else {
      nextDue = newDate;
      nextScheduled = null;
    }

    return target.copyWith(
      dueDate: nextDue,
      clearDueDate: nextDue == null,
      scheduledDate: nextScheduled,
      clearScheduledDate: nextScheduled == null,
      updatedAt: (nowUtc ?? EthiopiaClock.nowUtc()).toUtc(),
    );
  }

  static TaskEntity stopRecurrence(
    TaskEntity target, {
    DateTime? nowUtc,
  }) {
    return target.copyWith(
      clearRecurrenceRule: true,
      clearRecurrenceConfig: true,
      updatedAt: (nowUtc ?? EthiopiaClock.nowUtc()).toUtc(),
    );
  }
}
