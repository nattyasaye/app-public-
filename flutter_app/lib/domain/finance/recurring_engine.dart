import '../../core/date/shared_date.dart';
import 'finance_models.dart';

/// Pure domain engine for advancing recurring financial schedules deterministically.
class RecurringEngine {
  /// Advances [from] by `interval` cycles of [frequency], clamping day-of-month
  /// to the last valid day of shorter Gregorian months (e.g. Jan 31 -> Feb 28/29).
  static CalendarDate computeNextOccurrence({
    required CalendarDate from,
    required RecurrenceFrequency frequency,
    int interval = 1,
  }) {
    final safeInterval = interval < 1 ? 1 : interval;
    switch (frequency) {
      case RecurrenceFrequency.weekly:
        return from.addDays(7 * safeInterval);
      case RecurrenceFrequency.biweekly:
        return from.addDays(14 * safeInterval);
      case RecurrenceFrequency.monthly:
        return _addMonthsClamped(from, 1 * safeInterval);
      case RecurrenceFrequency.quarterly:
        return _addMonthsClamped(from, 3 * safeInterval);
      case RecurrenceFrequency.yearly:
        return _addMonthsClamped(from, 12 * safeInterval);
    }
  }

  /// Collects all scheduled occurrence dates for [rule] <= [asOfDate].
  static List<CalendarDate> collectDueOccurrences({
    required RecurringRuleModel rule,
    required CalendarDate asOfDate,
    int maxInstancesPerRun = 24,
  }) {
    if (!rule.isActive) return const [];
    final results = <CalendarDate>[];
    var cursor = rule.nextOccurrenceDate;

    while (cursor <= asOfDate && results.length < maxInstancesPerRun) {
      if (rule.endDate != null && cursor > rule.endDate!) {
        break;
      }
      results.add(cursor);
      cursor = computeNextOccurrence(
        from: cursor,
        frequency: rule.frequency,
        interval: rule.interval,
      );
    }
    return results;
  }

  /// Advances [nextOccurrenceDate] by full frequency cycles until it is >= [today].
  /// Used when resuming a paused recurring rule without backfilling skipped cycles.
  static CalendarDate advanceNextOnOrAfter({
    required CalendarDate nextOccurrenceDate,
    required RecurrenceFrequency frequency,
    int interval = 1,
    CalendarDate? today,
  }) {
    final effectiveToday = today ?? CalendarDate.today();
    var cursor = nextOccurrenceDate;
    var guard = 0;
    while (cursor < effectiveToday && guard < 1200) {
      cursor = computeNextOccurrence(
        from: cursor,
        frequency: frequency,
        interval: interval,
      );
      guard++;
    }
    return cursor;
  }

  /// Advances a recurring rule's `nextOccurrenceDate` by a single cycle,
  /// deactivating if the new date exceeds `endDate`.
  static RecurringRuleModel skipNext({required RecurringRuleModel rule}) {
    final nextDate = computeNextOccurrence(
      from: rule.nextOccurrenceDate,
      frequency: rule.frequency,
      interval: rule.interval,
    );
    final expired = rule.endDate != null && nextDate > rule.endDate!;
    return rule.copyWith(
      nextOccurrenceDate: nextDate,
      isActive: expired ? false : rule.isActive,
    );
  }

  static CalendarDate _addMonthsClamped(CalendarDate date, int monthsToAdd) {
    final totalMonths = (date.year * 12) + (date.month - 1) + monthsToAdd;
    final targetYear = totalMonths ~/ 12;
    final targetMonth = (totalMonths % 12) + 1;
    final maxDay = _daysInGregorianMonth(targetYear, targetMonth);
    final clampedDay = date.day > maxDay ? maxDay : date.day;
    return CalendarDate(year: targetYear, month: targetMonth, day: clampedDay);
  }

  static int _daysInGregorianMonth(int year, int month) {
    const days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month == 2 &&
        ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0))) {
      return 29;
    }
    return days[month - 1];
  }
}
