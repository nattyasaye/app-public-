import '../../core/date/shared_date.dart';
import 'task_models.dart';

enum TaskReminderPreset {
  atTime,
  fifteenMinutesBefore,
  oneHourBefore,
  oneDayBefore,
  custom,
}

class TaskReminderAnchor {
  final CalendarDate date;
  final DayTimeOfDay time;
  final String source; // 'scheduled' | 'due'
  final bool hasExplicitTime;
  final DateTime utcInstant;

  const TaskReminderAnchor({
    required this.date,
    required this.time,
    required this.source,
    required this.hasExplicitTime,
    required this.utcInstant,
  });
}

/// Pure domain engine for Task Reminder timing, presets, Ethiopia UTC+3
/// formatting, lifecycle reconciliation, and recurrence carry-over.
///
/// Zero Flutter/UI or Drift/SQLite dependencies.
class TaskReminderEngine {
  static const String taskReminderChannelId = 'task_reminders_channel';
  static const int defaultHour = 9;
  static const int defaultMinute = 0;

  static String canonicalReminderId(String taskId) => 'rem-task-$taskId';

  static String presetLabel(TaskReminderPreset preset) {
    switch (preset) {
      case TaskReminderPreset.atTime:
        return 'At scheduled / due time';
      case TaskReminderPreset.fifteenMinutesBefore:
        return '15 minutes before';
      case TaskReminderPreset.oneHourBefore:
        return '1 hour before';
      case TaskReminderPreset.oneDayBefore:
        return '1 day before';
      case TaskReminderPreset.custom:
        return 'Custom date & time';
    }
  }

  static int? _presetOffsetMinutes(TaskReminderPreset preset) {
    switch (preset) {
      case TaskReminderPreset.atTime:
        return 0;
      case TaskReminderPreset.fifteenMinutesBefore:
        return 15;
      case TaskReminderPreset.oneHourBefore:
        return 60;
      case TaskReminderPreset.oneDayBefore:
        return 24 * 60;
      case TaskReminderPreset.custom:
        return null;
    }
  }

  static bool isTaskEligibleForActiveReminder(TaskEntity task) {
    if (task.isArchived) return false;
    if (task.isCompleted) return false;
    if (task.status == 'cancelled') return false;
    return true;
  }

  static TaskReminderAnchor? resolveAnchor(TaskEntity task) {
    final parsedTime = DayTimeOfDay.tryParse(task.scheduledTime);
    final hasExplicitTime = parsedTime != null;
    final effectiveTime = parsedTime ??
        DayTimeOfDay(hour: defaultHour, minute: defaultMinute);

    if (task.scheduledDate != null) {
      final local = LocalDateTime(
        date: task.scheduledDate!,
        hour: effectiveTime.hour,
        minute: effectiveTime.minute,
      );
      return TaskReminderAnchor(
        date: task.scheduledDate!,
        time: effectiveTime,
        source: 'scheduled',
        hasExplicitTime: hasExplicitTime,
        utcInstant: local.toUtcInstant(),
      );
    }

    if (task.dueDate != null) {
      final local = LocalDateTime(
        date: task.dueDate!,
        hour: effectiveTime.hour,
        minute: effectiveTime.minute,
      );
      return TaskReminderAnchor(
        date: task.dueDate!,
        time: effectiveTime,
        source: 'due',
        hasExplicitTime: hasExplicitTime,
        utcInstant: local.toUtcInstant(),
      );
    }

    return null;
  }

  static LocalDateTime defaultFallbackEthiopiaDateTime({DateTime? nowUtc}) {
    final now = (nowUtc ?? EthiopiaClock.nowUtc()).toUtc();
    final today = CalendarDate.fromUtcInstantInEthiopia(now);
    final candidate = LocalDateTime(
      date: today,
      hour: defaultHour,
      minute: defaultMinute,
    );
    if (candidate.toUtcInstant().isAfter(now)) {
      return candidate;
    }
    return LocalDateTime(
      date: today.addDays(1),
      hour: defaultHour,
      minute: defaultMinute,
    );
  }

  static DateTime computeTriggerFromPreset({
    required TaskEntity task,
    required TaskReminderPreset preset,
    CalendarDate? customDate,
    DayTimeOfDay? customTime,
    DateTime? nowUtc,
  }) {
    if (preset == TaskReminderPreset.custom) {
      final fallback = defaultFallbackEthiopiaDateTime(nowUtc: nowUtc);
      final date = customDate ?? fallback.date;
      final time = customTime ?? fallback.timeOfDay;
      return LocalDateTime(
        date: date,
        hour: time.hour,
        minute: time.minute,
      ).toUtcInstant();
    }

    final offsetMinutes = _presetOffsetMinutes(preset) ?? 0;
    final anchor = resolveAnchor(task);
    if (anchor == null) {
      final fallback = defaultFallbackEthiopiaDateTime(nowUtc: nowUtc);
      return fallback
          .toUtcInstant()
          .subtract(Duration(minutes: offsetMinutes));
    }
    return anchor.utcInstant.subtract(Duration(minutes: offsetMinutes));
  }

  static TaskReminderPreset inferPreset(
    TaskEntity task,
    DateTime triggerTimeUtc,
  ) {
    final anchor = resolveAnchor(task);
    if (anchor == null) return TaskReminderPreset.custom;

    final diffMs = anchor.utcInstant.millisecondsSinceEpoch -
        triggerTimeUtc.toUtc().millisecondsSinceEpoch;
    if (diffMs == 0) return TaskReminderPreset.atTime;
    if (diffMs == 15 * 60 * 1000) return TaskReminderPreset.fifteenMinutesBefore;
    if (diffMs == 60 * 60 * 1000) return TaskReminderPreset.oneHourBefore;
    if (diffMs == 24 * 60 * 60 * 1000) return TaskReminderPreset.oneDayBefore;
    return TaskReminderPreset.custom;
  }

  static DateTime recomputeTriggerOnTaskUpdate({
    required TaskEntity previousTask,
    required TaskEntity nextTask,
    required DateTime existingTriggerUtc,
    bool shiftCustomOnDateShift = false,
  }) {
    final normalizedExisting = existingTriggerUtc.toUtc();
    final preset = inferPreset(previousTask, normalizedExisting);

    if (preset != TaskReminderPreset.custom) {
      final nextAnchor = resolveAnchor(nextTask);
      if (nextAnchor == null) {
        return normalizedExisting;
      }
      final offsetMinutes = _presetOffsetMinutes(preset) ?? 0;
      return nextAnchor.utcInstant.subtract(Duration(minutes: offsetMinutes));
    }

    if (shiftCustomOnDateShift) {
      final prevPrimary = previousTask.scheduledDate ?? previousTask.dueDate;
      final nextPrimary = nextTask.scheduledDate ?? nextTask.dueDate;
      if (prevPrimary != null && nextPrimary != null) {
        final deltaDays = nextPrimary.jdn - prevPrimary.jdn;
        if (deltaDays != 0) {
          final existingWall =
              LocalDateTime.fromUtcInstant(normalizedExisting);
          final shifted = LocalDateTime(
            date: existingWall.date.addDays(deltaDays),
            hour: existingWall.hour,
            minute: existingWall.minute,
            second: 0,
          );
          return shifted.toUtcInstant();
        }
      }
    }

    return normalizedExisting;
  }

  static TaskReminderEntity buildReminder({
    required TaskEntity task,
    required DateTime triggerTimeUtc,
    TaskReminderEntity? existingReminder,
    DateTime? nowUtc,
    bool? forceActive,
  }) {
    final now = (nowUtc ?? EthiopiaClock.nowUtc()).toUtc();
    final eligible = isTaskEligibleForActiveReminder(task);
    final isActive = eligible ? (forceActive ?? true) : false;

    return TaskReminderEntity(
      id: existingReminder?.id ?? canonicalReminderId(task.id),
      targetId: task.id,
      targetType: 'task',
      title: task.title.trim().isEmpty
          ? (existingReminder?.title ?? 'Task Reminder')
          : task.title.trim(),
      channelId: taskReminderChannelId,
      triggerTimeUtc: triggerTimeUtc.toUtc(),
      isActive: isActive,
      createdAt: existingReminder?.createdAt ?? now,
    );
  }

  static TaskReminderEntity? reconcileForUpdatedTask({
    required TaskEntity previousTask,
    required TaskEntity nextTask,
    required TaskReminderEntity? existingReminder,
    DateTime? nowUtc,
    bool shiftCustomOnDateShift = false,
  }) {
    if (existingReminder == null) return null;
    final now = (nowUtc ?? EthiopiaClock.nowUtc()).toUtc();
    final nextTrigger = recomputeTriggerOnTaskUpdate(
      previousTask: previousTask,
      nextTask: nextTask,
      existingTriggerUtc: existingReminder.triggerTimeUtc,
      shiftCustomOnDateShift: shiftCustomOnDateShift,
    );

    final wasEligible = isTaskEligibleForActiveReminder(previousTask);
    final isNowEligible = isTaskEligibleForActiveReminder(nextTask);

    final bool nextActive;
    if (!isNowEligible) {
      nextActive = false;
    } else if (!wasEligible && isNowEligible) {
      nextActive = nextTrigger.isAfter(now);
    } else {
      nextActive = existingReminder.isActive;
    }

    return buildReminder(
      task: nextTask,
      triggerTimeUtc: nextTrigger,
      existingReminder: existingReminder,
      nowUtc: now,
      forceActive: nextActive,
    );
  }

  static TaskReminderEntity? buildCarryOverForGeneratedOccurrence({
    required TaskEntity previousParentTask,
    required TaskEntity generatedNextTask,
    required TaskReminderEntity? parentReminder,
    DateTime? nowUtc,
  }) {
    if (parentReminder == null) return null;
    final now = (nowUtc ?? EthiopiaClock.nowUtc()).toUtc();
    final nextTrigger = recomputeTriggerOnTaskUpdate(
      previousTask: previousParentTask,
      nextTask: generatedNextTask,
      existingTriggerUtc: parentReminder.triggerTimeUtc,
      shiftCustomOnDateShift: true,
    );
    return buildReminder(
      task: generatedNextTask,
      triggerTimeUtc: nextTrigger,
      nowUtc: now,
      forceActive: isTaskEligibleForActiveReminder(generatedNextTask),
    );
  }

  static String formatReminderSummary(
    DateTime triggerTimeUtc, {
    CalendarDate? today,
  }) {
    final wall = LocalDateTime.fromUtcInstant(triggerTimeUtc.toUtc());
    final effectiveToday = today ?? CalendarDate.today();
    final tomorrow = effectiveToday.addDays(1);
    final yesterday = effectiveToday.subtractDays(1);

    final String dayLabel;
    if (wall.date == effectiveToday) {
      dayLabel = 'Today';
    } else if (wall.date == tomorrow) {
      dayLabel = 'Tomorrow';
    } else if (wall.date == yesterday) {
      dayLabel = 'Yesterday';
    } else if (wall.date.year == effectiveToday.year) {
      dayLabel = '${wall.date.gregorianShortMonthName} ${wall.date.day}';
    } else {
      dayLabel =
          '${wall.date.gregorianShortMonthName} ${wall.date.day}, ${wall.date.year}';
    }

    return '$dayLabel · ${wall.timeOfDay.toIsoString()} EAT';
  }
}
