import 'calendar_date.dart';
import 'calendar_engine.dart';
import 'calendar_metadata.dart';

/// Immutable, strictly validated date in the Ethiopian Calendar
/// (13 months: 12 x 30 days + Pagume 5/6 days).
///
/// Rejects invalid dates (such as Pagume 6 in an ordinary year) on
/// construction instead of silently overflowing into Meskerem.
class EthiopianDate implements Comparable<EthiopianDate> {
  final int year;
  final int month; // 1..13
  final int day; // 1..30 (or 1..5 / 1..6 in Pagume)
  final int jdn;

  EthiopianDate({
    required this.year,
    required this.month,
    required this.day,
  }) : jdn = CalendarEngine.ethiopianToJdn(year, month, day);

  EthiopianDate._fromValidatedJdn({
    required this.year,
    required this.month,
    required this.day,
    required this.jdn,
  });

  /// Constructs an [EthiopianDate] from a Julian Day Number.
  factory EthiopianDate.fromJdn(int jdn) {
    final parts = CalendarEngine.jdnToEthiopian(jdn);
    return EthiopianDate._fromValidatedJdn(
      year: parts.year,
      month: parts.month,
      day: parts.day,
      jdn: jdn,
    );
  }

  /// Derives today's [EthiopianDate] under Daywell's Ethiopia UTC+3 convention.
  factory EthiopianDate.today() => CalendarDate.today().toEthiopian();

  /// Parses an Ethiopian date string formatted as `YYYY-MM-DD` (month 01..13).
  factory EthiopianDate.parse(String input) {
    final trimmed = input.trim();
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(trimmed);
    if (match == null) {
      throw FormatException(
        'Invalid Ethiopian date string "$input". Expected YYYY-MM-DD.',
      );
    }
    return EthiopianDate(
      year: int.parse(match.group(1)!),
      month: int.parse(match.group(2)!),
      day: int.parse(match.group(3)!),
    );
  }

  /// Static Amharic month list kept for compatibility with existing callers.
  static List<String> get amharicMonths =>
      CalendarMetadata.ethiopianAmharicMonths;

  /// Static English month list kept for compatibility with existing callers.
  static List<String> get englishMonths =>
      CalendarMetadata.ethiopianEnglishMonths;

  bool get isLeapYear => CalendarEngine.isEthiopianLeapYear(year);

  int get daysInMonth => CalendarEngine.daysInEthiopianMonth(year, month);

  int get daysInYear => CalendarEngine.daysInEthiopianYear(year);

  /// ISO-8601 weekday (1 = Monday .. 7 = Sunday).
  int get weekday => CalendarEngine.weekdayFromJdn(jdn);

  String get amharicMonthName =>
      CalendarMetadata.ethiopianAmharicMonths[month - 1];

  String get englishMonthName =>
      CalendarMetadata.ethiopianEnglishMonths[month - 1];

  String get amharicWeekdayName =>
      CalendarMetadata.weekdayAmharicNames[weekday - 1];

  String get englishWeekdayName =>
      CalendarMetadata.weekdayEnglishNames[weekday - 1];

  /// Converts to the canonical underlying civil day ([CalendarDate]).
  CalendarDate toCalendarDate() => CalendarDate.fromJdn(jdn);

  /// Converts to a UTC-midnight Gregorian [DateTime] for widget interop.
  DateTime toGregorianDateTime() => toCalendarDate().toGregorianUtcMidnight();

  EthiopianDate addDays(int days) => EthiopianDate.fromJdn(jdn + days);

  EthiopianDate subtractDays(int days) => EthiopianDate.fromJdn(jdn - days);

  int differenceInDays(EthiopianDate other) => jdn - other.jdn;

  EthiopianDate nextMonth() {
    final nextY = month == 13 ? year + 1 : year;
    final nextM = month == 13 ? 1 : month + 1;
    final maxD = CalendarEngine.daysInEthiopianMonth(nextY, nextM);
    return EthiopianDate(
        year: nextY, month: nextM, day: day > maxD ? maxD : day);
  }

  EthiopianDate previousMonth() {
    final prevY = month == 1 ? year - 1 : year;
    final prevM = month == 1 ? 13 : month - 1;
    final maxD = CalendarEngine.daysInEthiopianMonth(prevY, prevM);
    return EthiopianDate(
        year: prevY, month: prevM, day: day > maxD ? maxD : day);
  }

  EthiopianDate nextYear() {
    final nextY = year + 1;
    final maxD = CalendarEngine.daysInEthiopianMonth(nextY, month);
    return EthiopianDate(
        year: nextY, month: month, day: day > maxD ? maxD : day);
  }

  EthiopianDate previousYear() {
    final prevY = year - 1;
    final maxD = CalendarEngine.daysInEthiopianMonth(prevY, month);
    return EthiopianDate(
        year: prevY, month: month, day: day > maxD ? maxD : day);
  }

  EthiopianDate get startOfMonth =>
      EthiopianDate(year: year, month: month, day: 1);

  EthiopianDate get endOfMonth =>
      EthiopianDate(year: year, month: month, day: daysInMonth);

  EthiopianDate get startOfYear => EthiopianDate(year: year, month: 1, day: 1);

  EthiopianDate get endOfYear => EthiopianDate(
        year: year,
        month: 13,
        day: CalendarEngine.daysInEthiopianMonth(year, 13),
      );

  /// All dates belonging to this Ethiopian month in chronological order.
  List<EthiopianDate> monthDays() {
    final count = daysInMonth;
    return List<EthiopianDate>.generate(
      count,
      (i) => EthiopianDate(year: year, month: month, day: i + 1),
      growable: false,
    );
  }

  String toIsoString() {
    final y = year.toString().padLeft(4, '0');
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String toAmharicString({bool includeEra = true}) {
    final era = includeEra ? ' ዓ.ም.' : '';
    return '$amharicMonthName $day, $year$era';
  }

  String toEnglishString({bool includeEra = true}) {
    final era = includeEra ? ' E.C.' : '';
    return '$englishMonthName $day, $year$era';
  }

  @override
  int compareTo(EthiopianDate other) => jdn.compareTo(other.jdn);

  @override
  String toString() => toIsoString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is EthiopianDate && jdn == other.jdn);

  @override
  int get hashCode => jdn.hashCode;
}
