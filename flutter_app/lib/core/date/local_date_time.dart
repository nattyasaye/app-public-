import 'calendar_date.dart';
import 'calendar_system.dart';

/// Immutable time-of-day value (`00:00` .. `23:59`) with strict validation.
class DayTimeOfDay implements Comparable<DayTimeOfDay> {
  final int hour; // 0..23
  final int minute; // 0..59

  DayTimeOfDay({required this.hour, required this.minute}) {
    if (hour < 0 || hour > 23) {
      throw ArgumentError.value(hour, 'hour', 'Hour must be between 0 and 23.');
    }
    if (minute < 0 || minute > 59) {
      throw ArgumentError.value(
        minute,
        'minute',
        'Minute must be between 0 and 59.',
      );
    }
  }

  /// Strictly parses a `HH:MM` 24-hour time string.
  factory DayTimeOfDay.parse(String input) {
    final trimmed = input.trim();
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(trimmed);
    if (match == null) {
      throw FormatException(
        'Invalid time string "$input". Expected HH:MM.',
      );
    }
    return DayTimeOfDay(
      hour: int.parse(match.group(1)!),
      minute: int.parse(match.group(2)!),
    );
  }

  /// Safely parses `HH:MM`, returning `null` if [input] is null or invalid.
  static DayTimeOfDay? tryParse(String? input) {
    if (input == null) return null;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    try {
      return DayTimeOfDay.parse(trimmed);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  int get totalMinutes => hour * 60 + minute;

  /// Canonical `HH:MM` 24-hour string.
  String toIsoString() {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// 12-hour formatted display string (e.g. `09:30 AM`).
  String toDisplay12Hour() {
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '${h12.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')} $period';
  }

  bool operator <(DayTimeOfDay other) => totalMinutes < other.totalMinutes;

  bool operator <=(DayTimeOfDay other) => totalMinutes <= other.totalMinutes;

  bool operator >(DayTimeOfDay other) => totalMinutes > other.totalMinutes;

  bool operator >=(DayTimeOfDay other) => totalMinutes >= other.totalMinutes;

  @override
  int compareTo(DayTimeOfDay other) =>
      totalMinutes.compareTo(other.totalMinutes);

  @override
  String toString() => toIsoString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DayTimeOfDay && hour == other.hour && minute == other.minute);

  @override
  int get hashCode => Object.hash(hour, minute);
}

/// Immutable civil date-and-time under Daywell's fixed Ethiopia UTC+3
/// convention (no DST, no arbitrary timezone offset overrides).
class LocalDateTime implements Comparable<LocalDateTime> {
  final CalendarDate date;
  final int hour; // 0..23
  final int minute; // 0..59
  final int second; // 0..59

  LocalDateTime({
    required this.date,
    this.hour = 0,
    this.minute = 0,
    this.second = 0,
  }) {
    if (hour < 0 || hour > 23) {
      throw ArgumentError.value(hour, 'hour', 'Hour must be between 0 and 23.');
    }
    if (minute < 0 || minute > 59) {
      throw ArgumentError.value(
        minute,
        'minute',
        'Minute must be between 0 and 59.',
      );
    }
    if (second < 0 || second > 59) {
      throw ArgumentError.value(
        second,
        'second',
        'Second must be between 0 and 59.',
      );
    }
  }

  /// Current Ethiopia local civil date and time (UTC+3).
  factory LocalDateTime.now() =>
      LocalDateTime.fromUtcInstant(EthiopiaClock.nowUtc());

  /// Converts an instant to Ethiopia local civil date and time (UTC+3).
  factory LocalDateTime.fromUtcInstant(DateTime instant) {
    final wall = EthiopiaClock.toEthiopiaWallComponents(instant);
    return LocalDateTime(
      date: CalendarDate(year: wall.year, month: wall.month, day: wall.day),
      hour: wall.hour,
      minute: wall.minute,
      second: wall.second,
    );
  }

  /// Strictly parses an ISO timestamp string, converting any explicit offset
  /// or `Z` to Ethiopia UTC+3 or interpreting a bare timestamp as Ethiopia
  /// wall time. Rejects overflowing dates/times like `Feb 30` or `25:00:00`.
  factory LocalDateTime.parse(String input) {
    final trimmed = input.trim();
    final dateOnly = CalendarDate.tryParse(trimmed);
    if (dateOnly != null) {
      return LocalDateTime(date: dateOnly);
    }
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match == null) {
      throw FormatException('Invalid timestamp string "$input".');
    }

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6) ?? '0');
    final zone = match.group(7);

    // Strictly validates Gregorian calendar bounds & time bounds before parse.
    final validatedDate = CalendarDate(year: year, month: month, day: day);
    if (hour < 0 || hour > 23) {
      throw ArgumentError.value(hour, 'hour', 'Hour must be between 0 and 23.');
    }
    if (minute < 0 || minute > 59) {
      throw ArgumentError.value(
        minute,
        'minute',
        'Minute must be between 0 and 59.',
      );
    }
    if (second < 0 || second > 59) {
      throw ArgumentError.value(
        second,
        'second',
        'Second must be between 0 and 59.',
      );
    }

    if (zone != null) {
      if (zone.toUpperCase() != 'Z') {
        final tzDigits = zone.substring(1).replaceAll(':', '');
        final tzHour = int.parse(tzDigits.substring(0, 2));
        final tzMinute = int.parse(tzDigits.substring(2, 4));
        if (tzHour > 23 || tzMinute > 59) {
          throw FormatException('Invalid timezone offset "$zone" in "$input".');
        }
      }
      final parsed = DateTime.parse(trimmed);
      return LocalDateTime.fromUtcInstant(parsed.toUtc());
    }
    return LocalDateTime(
      date: validatedDate,
      hour: hour,
      minute: minute,
      second: second,
    );
  }

  /// Safely parses an ISO timestamp or `YYYY-MM-DD` under Ethiopia UTC+3.
  static LocalDateTime? tryParse(String? input) {
    if (input == null) return null;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    try {
      return LocalDateTime.parse(trimmed);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  DayTimeOfDay get timeOfDay => DayTimeOfDay(hour: hour, minute: minute);

  /// Converts this Ethiopia wall-clock timestamp back to a UTC [DateTime].
  DateTime toUtcInstant() {
    return EthiopiaClock.fromEthiopiaWallComponents(
      date.year,
      date.month,
      date.day,
      hour,
      minute,
      second,
    );
  }

  /// Canonical ISO-8601 timestamp in Ethiopia `+03:00`.
  String toEthiopiaIsoString() {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    final s = second.toString().padLeft(2, '0');
    return '${date.toIsoString()}T$h:$m:$s+03:00';
  }

  @override
  int compareTo(LocalDateTime other) =>
      toUtcInstant().compareTo(other.toUtcInstant());

  @override
  String toString() => toEthiopiaIsoString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalDateTime &&
          date == other.date &&
          hour == other.hour &&
          minute == other.minute &&
          second == other.second);

  @override
  int get hashCode => Object.hash(date, hour, minute, second);
}

/// Immutable inclusive span `[start, end]` of canonical [CalendarDate] days.
class DateRange {
  final CalendarDate start;
  final CalendarDate end;

  DateRange({required this.start, required this.end}) {
    if (end.isBefore(start)) {
      throw ArgumentError(
        'DateRange end (${end.toIsoString()}) cannot precede '
        'start (${start.toIsoString()}).',
      );
    }
  }

  /// Single-day range `[day, day]`.
  factory DateRange.single(CalendarDate day) => DateRange(start: day, end: day);

  /// Full calendar month range in [system].
  factory DateRange.forMonth(CalendarSystem system, int year, int month) {
    final bounds = CalendarDate.monthBounds(system, year, month);
    return DateRange(start: bounds.start, end: bounds.end);
  }

  /// Full calendar year range in [system].
  factory DateRange.forYear(CalendarSystem system, int year) {
    final bounds = CalendarDate.yearBounds(system, year);
    return DateRange(start: bounds.start, end: bounds.end);
  }

  /// Inclusive number of calendar days in this range.
  int get lengthInDays => end.differenceInDays(start) + 1;

  bool contains(CalendarDate day) => !day.isBefore(start) && !day.isAfter(end);

  bool overlaps(DateRange other) =>
      !end.isBefore(other.start) && !other.end.isBefore(start);

  /// Enumerates every [CalendarDate] in this range in chronological order.
  List<CalendarDate> days() {
    return List<CalendarDate>.generate(
      lengthInDays,
      (i) => start.addDays(i),
      growable: false,
    );
  }

  @override
  String toString() => '${start.toIsoString()}..${end.toIsoString()}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DateRange && start == other.start && end == other.end);

  @override
  int get hashCode => Object.hash(start, end);
}
