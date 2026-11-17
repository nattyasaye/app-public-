import '../../core/date/shared_date.dart';

/// Backward-compatible facade over the authoritative shared date foundation.
///
/// All JDN math, leap-year validation, and Ethiopia UTC+3 clock resolution live
/// in `lib/core/date/`.
class EthiopianCalendar {
  /// Converts a Gregorian [DateTime] to [EthiopianDate] using its civil date
  /// components when given a date-only carrier, or its Ethiopia UTC+3 day when
  /// given an explicit UTC instant.
  static EthiopianDate fromGregorian(DateTime gregorian) {
    final calendarDate = gregorian.isUtc
        ? CalendarDate.fromUtcInstantInEthiopia(gregorian)
        : CalendarDate.fromDateComponents(gregorian);
    return calendarDate.toEthiopian();
  }

  /// Converts an [EthiopianDate] back to a UTC-midnight Gregorian [DateTime].
  static DateTime toGregorian(EthiopianDate ethiopian) {
    return ethiopian.toGregorianDateTime();
  }

  /// Formats a Gregorian [DateTime] into a dual-calendar string representation.
  /// Example output: `ጥቅምት 28, 2017 (Nov 07, 2024)`
  static String formatDual(DateTime date, {bool useAmharic = true}) {
    final calendarDate = date.isUtc
        ? CalendarDate.fromUtcInstantInEthiopia(date)
        : CalendarDate.fromDateComponents(date);
    return SharedDateFormatter.formatDual(
      calendarDate,
      useAmharic: useAmharic,
    );
  }

  /// Returns today's [EthiopianDate] under Ethiopia UTC+3 time.
  static EthiopianDate now() => EthiopianDate.today();
}
