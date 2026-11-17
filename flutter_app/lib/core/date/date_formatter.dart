import 'calendar_date.dart';
import 'calendar_system.dart';
import 'ethiopian_date.dart';
import 'local_date_time.dart';

/// Shared date formatting and strict/migration parsing helpers across Daywell.
class SharedDateFormatter {
  const SharedDateFormatter._();

  /// Formats a [CalendarDate] in short Gregorian style (e.g. `Nov 07, 2024`).
  static String formatGregorianShort(CalendarDate date) {
    final dayPadded = date.day.toString().padLeft(2, '0');
    return '${date.gregorianShortMonthName} $dayPadded, ${date.year}';
  }

  /// Formats a [CalendarDate] in full Gregorian style (e.g. `November 7, 2024`).
  static String formatGregorianLong(CalendarDate date) {
    return '${date.gregorianFullMonthName} ${date.day}, ${date.year}';
  }

  /// Formats an [EthiopianDate] in Amharic or English transliteration.
  static String formatEthiopian(
    EthiopianDate date, {
    bool useAmharic = true,
    bool includeEra = true,
  }) {
    return useAmharic
        ? date.toAmharicString(includeEra: includeEra)
        : date.toEnglishString(includeEra: includeEra);
  }

  /// Formats [date] for the requested primary [CalendarSystem].
  static String formatForSystem(
    CalendarDate date,
    CalendarSystem system, {
    bool useAmharic = true,
    bool includeEra = true,
  }) {
    return switch (system) {
      CalendarSystem.ethiopian => formatEthiopian(
          date.toEthiopian(),
          useAmharic: useAmharic,
          includeEra: includeEra,
        ),
      CalendarSystem.gregorian => formatGregorianShort(date),
    };
  }

  /// Formats a [CalendarDate] into Daywell's dual-calendar label:
  /// e.g. `ጥቅምት 28, 2017 (Nov 07, 2024)`.
  static String formatDual(CalendarDate date, {bool useAmharic = true}) {
    final eth = date.toEthiopian();
    final ethStr = useAmharic
        ? eth.toAmharicString(includeEra: false)
        : eth.toEnglishString(includeEra: false);
    final gregStr = formatGregorianShort(date);
    return '$ethStr ($gregStr)';
  }

  /// Formats an instant ([DateTime]) under Ethiopia UTC+3 as a dual label.
  static String formatDualFromInstant(
    DateTime instant, {
    bool useAmharic = true,
  }) {
    return formatDual(
      CalendarDate.fromUtcInstantInEthiopia(instant),
      useAmharic: useAmharic,
    );
  }

  /// Formats an instant in Ethiopia civil time (`YYYY-MM-DD HH:MM (UTC+3)`).
  static String formatEthiopiaTimestamp(DateTime instant) {
    final ldt = LocalDateTime.fromUtcInstant(instant);
    return '${ldt.date.toIsoString()} ${ldt.timeOfDay.toIsoString()} '
        '(${EthiopiaClock.timeZoneLabel})';
  }

  /// Formats a canonical date string (`YYYY-MM-DD`).
  static String formatIsoDate(CalendarDate date) => date.toIsoString();

  /// Strictly parses a canonical `YYYY-MM-DD` string.
  static CalendarDate parseCanonicalDate(String input) =>
      CalendarDate.parse(input);

  /// Parses canonical `YYYY-MM-DD` strings strictly, and also supports legacy
  /// ISO-8601 timestamp snapshots by normalizing instants with explicit offsets
  /// to Ethiopia UTC+3 civil days while rejecting overflowing calendar components.
  static CalendarDate parseFlexibleToCalendarDate(String input) {
    final trimmed = input.trim();
    final strict = CalendarDate.tryParse(trimmed);
    if (strict != null) return strict;

    return LocalDateTime.parse(trimmed).date;
  }

  /// Safe version of [parseFlexibleToCalendarDate] returning `null` if invalid.
  static CalendarDate? tryParseFlexibleToCalendarDate(String? input) {
    if (input == null) return null;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    try {
      return parseFlexibleToCalendarDate(trimmed);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}
