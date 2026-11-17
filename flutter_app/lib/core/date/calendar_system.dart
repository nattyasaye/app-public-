/// Supported first-class civil calendar systems in Daywell.
enum CalendarSystem {
  ethiopian,
  gregorian,
}

/// Fixed application-wide time convention for Daywell: Ethiopia local civil
/// time (UTC+3 / East Africa Time, no daylight saving time).
///
/// Daywell intentionally excludes multi-timezone runtime abstractions, user
/// timezone selection, and travel offset logic.
class EthiopiaClock {
  static const int utcOffsetHours = 3;
  static const Duration utcOffset = Duration(hours: utcOffsetHours);
  static const String timeZoneLabel = 'UTC+3';

  static DateTime Function() _utcNowProvider = () => DateTime.now().toUtc();

  /// Overrides the underlying UTC clock source for deterministic testing.
  static void setClockForTesting(DateTime Function()? provider) {
    _utcNowProvider = provider ?? () => DateTime.now().toUtc();
  }

  /// Returns the current instant strictly in UTC.
  static DateTime nowUtc() => _utcNowProvider().toUtc();

  /// Converts any [DateTime] instant into Ethiopia civil components expressed
  /// as a UTC-backed carrier whose year/month/day/hour/minute/second fields
  /// match Ethiopia wall-clock time (UTC+3).
  static DateTime toEthiopiaWallComponents(DateTime instant) {
    return instant.toUtc().add(utcOffset);
  }

  /// Converts an Ethiopia wall-clock timestamp (UTC+3) to a true UTC instant.
  static DateTime fromEthiopiaWallComponents(
    int year,
    int month,
    int day, [
    int hour = 0,
    int minute = 0,
    int second = 0,
  ]) {
    return DateTime.utc(year, month, day, hour, minute, second)
        .subtract(utcOffset);
  }

  /// Parses an ISO-8601 timestamp string into a canonical UTC [DateTime]
  /// without relying on the host device's OS timezone.
  ///
  /// - Strings with `Z` or `+/-HH:MM` preserve their exact UTC instant.
  /// - Bare timestamps (`YYYY-MM-DDTHH:MM:SS`) and date-only strings resolve as
  ///   fixed Ethiopia civil time (`UTC+3`) converted to UTC.
  static DateTime? tryParseInstantUtc(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final isoMatch = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?)?(Z|[+-]\d{2}:?\d{2})?$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (isoMatch == null) return null;

    final year = int.parse(isoMatch.group(1)!);
    final month = int.parse(isoMatch.group(2)!);
    final day = int.parse(isoMatch.group(3)!);
    final hour = int.tryParse(isoMatch.group(4) ?? '0') ?? 0;
    final minute = int.tryParse(isoMatch.group(5) ?? '0') ?? 0;
    final second = int.tryParse(isoMatch.group(6) ?? '0') ?? 0;
    final zone = isoMatch.group(7);

    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31 ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        second < 0 ||
        second > 59) {
      return null;
    }

    // Validate exact Gregorian calendar days (reject e.g. Feb 30 or Apr 31).
    final probe = DateTime.utc(year, month, day);
    if (probe.year != year || probe.month != month || probe.day != day) {
      return null;
    }

    if (zone != null) {
      if (zone.toUpperCase() != 'Z') {
        final tzDigits = zone.substring(1).replaceAll(':', '');
        final tzHour = int.parse(tzDigits.substring(0, 2));
        final tzMinute = int.parse(tzDigits.substring(2, 4));
        if (tzHour > 23 || tzMinute > 59) {
          return null;
        }
      }
      final parsed = DateTime.tryParse(trimmed);
      return parsed?.toUtc();
    }
    return fromEthiopiaWallComponents(year, month, day, hour, minute, second);
  }

  /// Formats [instant] strictly as a UTC ISO-8601 string ending in `Z`.
  static String toUtcIsoString(DateTime instant) =>
      instant.toUtc().toIso8601String();
}
