import 'calendar_engine.dart';
import 'calendar_metadata.dart';
import 'calendar_system.dart';
import 'ethiopian_date.dart';

/// Canonical, immutable civil calendar day in Daywell.
///
/// Represents a calendar date without time-of-day or timezone ambiguity.
/// Internally stores proleptic Gregorian components (YYYY-MM-DD) and its
/// Julian Day Number ([jdn]) so comparisons, arithmetic, and Ethiopian/Gregorian
/// conversions operate on one mathematical day index.
class CalendarDate implements Comparable<CalendarDate> {
  final int year;
  final int month; // 1..12
  final int day; // 1..31
  final int jdn;

  CalendarDate({
    required this.year,
    required this.month,
    required this.day,
  }) : jdn = CalendarEngine.gregorianToJdn(year, month, day);

  CalendarDate._fromValidatedJdn({
    required this.year,
    required this.month,
    required this.day,
    required this.jdn,
  });

  /// Constructs a [CalendarDate] from a Julian Day Number.
  factory CalendarDate.fromJdn(int jdn) {
    final parts = CalendarEngine.jdnToGregorian(jdn);
    return CalendarDate._fromValidatedJdn(
      year: parts.year,
      month: parts.month,
      day: parts.day,
      jdn: jdn,
    );
  }

  /// Constructs a [CalendarDate] from validated Ethiopian calendar components.
  factory CalendarDate.fromEthiopian(int year, int month, int day) {
    return EthiopianDate(year: year, month: month, day: day).toCalendarDate();
  }

  /// Derives today's civil day under Daywell's Ethiopia UTC+3 convention.
  factory CalendarDate.today() {
    return CalendarDate.fromUtcInstantInEthiopia(EthiopiaClock.nowUtc());
  }

  /// Converts an instant ([DateTime]) into its civil day in Ethiopia (UTC+3).
  factory CalendarDate.fromUtcInstantInEthiopia(DateTime instant) {
    final ethWall = EthiopiaClock.toEthiopiaWallComponents(instant);
    return CalendarDate(
      year: ethWall.year,
      month: ethWall.month,
      day: ethWall.day,
    );
  }

  /// Extracts a [CalendarDate] from a [DateTime] using its literal calendar
  /// components without shifting timezones.
  factory CalendarDate.fromDateComponents(DateTime date) {
    return CalendarDate(year: date.year, month: date.month, day: date.day);
  }

  /// Strictly parses a canonical `YYYY-MM-DD` Gregorian date string.
  factory CalendarDate.parse(String input) {
    final trimmed = input.trim();
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(trimmed);
    if (match == null) {
      throw FormatException(
        'Invalid canonical date string "$input". Expected YYYY-MM-DD.',
      );
    }
    return CalendarDate(
      year: int.parse(match.group(1)!),
      month: int.parse(match.group(2)!),
      day: int.parse(match.group(3)!),
    );
  }

  /// Safely parses a canonical `YYYY-MM-DD` string, returning `null` if invalid.
  static CalendarDate? tryParse(String? input) {
    if (input == null) return null;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    try {
      return CalendarDate.parse(trimmed);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// Returns true if [year] is a leap year in the given [system].
  static bool isLeapYearFor(CalendarSystem system, int year) {
    return switch (system) {
      CalendarSystem.ethiopian => CalendarEngine.isEthiopianLeapYear(year),
      CalendarSystem.gregorian => CalendarEngine.isGregorianLeapYear(year),
    };
  }

  /// Returns the number of days in [month] of [year] for [system].
  static int daysInMonthFor(CalendarSystem system, int year, int month) {
    return switch (system) {
      CalendarSystem.ethiopian =>
        CalendarEngine.daysInEthiopianMonth(year, month),
      CalendarSystem.gregorian =>
        CalendarEngine.daysInGregorianMonth(year, month),
    };
  }

  /// Returns the number of days in [year] for [system].
  static int daysInYearFor(CalendarSystem system, int year) {
    return switch (system) {
      CalendarSystem.ethiopian => CalendarEngine.daysInEthiopianYear(year),
      CalendarSystem.gregorian => CalendarEngine.daysInGregorianYear(year),
    };
  }

  /// Generates every [CalendarDate] belonging to [month] of [year] in [system].
  static List<CalendarDate> monthDaysGrid(
    CalendarSystem system,
    int year,
    int month,
  ) {
    final count = daysInMonthFor(system, year, month);
    return switch (system) {
      CalendarSystem.ethiopian => List<CalendarDate>.generate(
          count,
          (i) => CalendarDate.fromEthiopian(year, month, i + 1),
          growable: false,
        ),
      CalendarSystem.gregorian => List<CalendarDate>.generate(
          count,
          (i) => CalendarDate(year: year, month: month, day: i + 1),
          growable: false,
        ),
    };
  }

  /// Returns the inclusive first and last [CalendarDate] of [month] in [system].
  static ({CalendarDate start, CalendarDate end}) monthBounds(
    CalendarSystem system,
    int year,
    int month,
  ) {
    final lastDay = daysInMonthFor(system, year, month);
    return switch (system) {
      CalendarSystem.ethiopian => (
          start: CalendarDate.fromEthiopian(year, month, 1),
          end: CalendarDate.fromEthiopian(year, month, lastDay),
        ),
      CalendarSystem.gregorian => (
          start: CalendarDate(year: year, month: month, day: 1),
          end: CalendarDate(year: year, month: month, day: lastDay),
        ),
    };
  }

  /// Returns the inclusive first and last [CalendarDate] of [year] in [system].
  static ({CalendarDate start, CalendarDate end}) yearBounds(
    CalendarSystem system,
    int year,
  ) {
    return switch (system) {
      CalendarSystem.ethiopian => (
          start: CalendarDate.fromEthiopian(year, 1, 1),
          end: CalendarDate.fromEthiopian(
            year,
            13,
            CalendarEngine.daysInEthiopianMonth(year, 13),
          ),
        ),
      CalendarSystem.gregorian => (
          start: CalendarDate(year: year, month: 1, day: 1),
          end: CalendarDate(year: year, month: 12, day: 31),
        ),
    };
  }

  /// ISO-8601 weekday (1 = Monday .. 7 = Sunday).
  int get weekday => CalendarEngine.weekdayFromJdn(jdn);

  bool get isGregorianLeapYear => CalendarEngine.isGregorianLeapYear(year);

  int get daysInGregorianMonth =>
      CalendarEngine.daysInGregorianMonth(year, month);

  int get daysInGregorianYear => CalendarEngine.daysInGregorianYear(year);

  String get gregorianShortMonthName =>
      CalendarMetadata.gregorianShortMonths[month - 1];

  String get gregorianFullMonthName =>
      CalendarMetadata.gregorianFullMonths[month - 1];

  String get englishWeekdayName =>
      CalendarMetadata.weekdayEnglishNames[weekday - 1];

  String get shortEnglishWeekdayName =>
      CalendarMetadata.weekdayShortEnglishNames[weekday - 1];

  String get amharicWeekdayName =>
      CalendarMetadata.weekdayAmharicNames[weekday - 1];

  /// Converts this civil day to its equivalent [EthiopianDate].
  EthiopianDate toEthiopian() => EthiopianDate.fromJdn(jdn);

  /// Returns a UTC-midnight [DateTime] preserving YYYY-MM-DD components.
  DateTime toGregorianUtcMidnight() => DateTime.utc(year, month, day);

  /// Returns the exact UTC instant corresponding to 00:00:00 in Ethiopia (UTC+3).
  DateTime toEthiopiaMidnightUtc() {
    return EthiopiaClock.fromEthiopiaWallComponents(year, month, day);
  }

  /// Canonical storage string `YYYY-MM-DD`.
  String toIsoString() {
    final y = year.toString().padLeft(4, '0');
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  CalendarDate addDays(int days) => CalendarDate.fromJdn(jdn + days);

  CalendarDate subtractDays(int days) => CalendarDate.fromJdn(jdn - days);

  /// Signed day delta (`this.jdn - other.jdn`).
  int differenceInDays(CalendarDate other) => jdn - other.jdn;

  bool isBefore(CalendarDate other) => jdn < other.jdn;

  bool isAfter(CalendarDate other) => jdn > other.jdn;

  bool isSameDay(CalendarDate other) => jdn == other.jdn;

  bool get isToday => jdn == CalendarDate.today().jdn;

  bool operator <(CalendarDate other) => jdn < other.jdn;

  bool operator <=(CalendarDate other) => jdn <= other.jdn;

  bool operator >(CalendarDate other) => jdn > other.jdn;

  bool operator >=(CalendarDate other) => jdn >= other.jdn;

  CalendarDate nextGregorianMonth() {
    final nextY = month == 12 ? year + 1 : year;
    final nextM = month == 12 ? 1 : month + 1;
    final maxD = CalendarEngine.daysInGregorianMonth(nextY, nextM);
    return CalendarDate(
      year: nextY,
      month: nextM,
      day: day > maxD ? maxD : day,
    );
  }

  CalendarDate previousGregorianMonth() {
    final prevY = month == 1 ? year - 1 : year;
    final prevM = month == 1 ? 12 : month - 1;
    final maxD = CalendarEngine.daysInGregorianMonth(prevY, prevM);
    return CalendarDate(
      year: prevY,
      month: prevM,
      day: day > maxD ? maxD : day,
    );
  }

  CalendarDate nextGregorianYear() {
    final nextY = year + 1;
    final maxD = CalendarEngine.daysInGregorianMonth(nextY, month);
    return CalendarDate(
      year: nextY,
      month: month,
      day: day > maxD ? maxD : day,
    );
  }

  CalendarDate previousGregorianYear() {
    final prevY = year - 1;
    final maxD = CalendarEngine.daysInGregorianMonth(prevY, month);
    return CalendarDate(
      year: prevY,
      month: month,
      day: day > maxD ? maxD : day,
    );
  }

  CalendarDate get startOfGregorianMonth =>
      CalendarDate(year: year, month: month, day: 1);

  CalendarDate get endOfGregorianMonth =>
      CalendarDate(year: year, month: month, day: daysInGregorianMonth);

  CalendarDate get startOfGregorianYear =>
      CalendarDate(year: year, month: 1, day: 1);

  CalendarDate get endOfGregorianYear =>
      CalendarDate(year: year, month: 12, day: 31);

  List<CalendarDate> gregorianMonthDays() =>
      monthDaysGrid(CalendarSystem.gregorian, year, month);

  CalendarDate nextEthiopianMonth() =>
      toEthiopian().nextMonth().toCalendarDate();

  CalendarDate previousEthiopianMonth() =>
      toEthiopian().previousMonth().toCalendarDate();

  CalendarDate nextEthiopianYear() => toEthiopian().nextYear().toCalendarDate();

  CalendarDate previousEthiopianYear() =>
      toEthiopian().previousYear().toCalendarDate();

  CalendarDate get startOfEthiopianMonth =>
      toEthiopian().startOfMonth.toCalendarDate();

  CalendarDate get endOfEthiopianMonth =>
      toEthiopian().endOfMonth.toCalendarDate();

  CalendarDate get startOfEthiopianYear =>
      toEthiopian().startOfYear.toCalendarDate();

  CalendarDate get endOfEthiopianYear =>
      toEthiopian().endOfYear.toCalendarDate();

  List<CalendarDate> ethiopianMonthDays() {
    final eth = toEthiopian();
    return monthDaysGrid(CalendarSystem.ethiopian, eth.year, eth.month);
  }

  @override
  int compareTo(CalendarDate other) => jdn.compareTo(other.jdn);

  @override
  String toString() => toIsoString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is CalendarDate && jdn == other.jdn);

  @override
  int get hashCode => jdn.hashCode;
}
