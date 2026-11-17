/// Authoritative Julian Day Number (JDN) conversion and validation engine
/// shared across all Daywell modules.
///
/// Mathematical basis & assumptions:
/// 1. Proleptic Gregorian <-> JDN uses the Fliegel-Van Flandern integer
///    algorithm, preserving exact 4 / 100 / 400 century leap-year rules.
/// 2. Ethiopian (Amete Mihret) <-> JDN anchors Meskerem 1, 1 E.C. to
///    JDN 1724221 (August 29, 8 C.E. Julian).
/// 3. Ethiopian years follow the exact 4-year cycle with zero century
///    exceptions: year Y is a leap year (Pagume has 6 days) iff Y % 4 == 3.
///    All months 1..12 have 30 days; month 13 (Pagume) has 5 or 6 days.
/// 4. ISO-8601 weekday numbering: 1 = Monday .. 7 = Sunday, derived directly
///    from JDN via ((jdn % 7) + 7) % 7 + 1.
class CalendarEngine {
  const CalendarEngine._();

  /// Meskerem 1, 1 E.C. in Julian Day Number.
  static const int ethiopianEpochJdn = 1724221;

  static int _positiveMod(int value, int divisor) {
    final rem = value % divisor;
    return rem < 0 ? rem + divisor : rem;
  }

  static int _floorDiv(int a, int b) {
    return a >= 0 ? a ~/ b : -((-a + b - 1) ~/ b);
  }

  /// True if [year] is a Gregorian leap year (4 / 100 / 400 rule).
  static bool isGregorianLeapYear(int year) {
    if (year % 400 == 0) return true;
    if (year % 100 == 0) return false;
    return year % 4 == 0;
  }

  /// True if [year] is an Ethiopian leap year (`year % 4 == 3`).
  static bool isEthiopianLeapYear(int year) {
    return _positiveMod(year, 4) == 3;
  }

  /// Number of days in Gregorian [month] (1..12) of [year].
  static int daysInGregorianMonth(int year, int month) {
    if (month < 1 || month > 12) {
      throw ArgumentError.value(
        month,
        'month',
        'Gregorian month must be between 1 and 12.',
      );
    }
    switch (month) {
      case 2:
        return isGregorianLeapYear(year) ? 29 : 28;
      case 4:
      case 6:
      case 9:
      case 11:
        return 30;
      default:
        return 31;
    }
  }

  /// Total days in Gregorian [year].
  static int daysInGregorianYear(int year) =>
      isGregorianLeapYear(year) ? 366 : 365;

  /// Number of days in Ethiopian [month] (1..13) of [year].
  static int daysInEthiopianMonth(int year, int month) {
    if (year < 1) {
      throw ArgumentError.value(
        year,
        'year',
        'Ethiopian year must be >= 1.',
      );
    }
    if (month < 1 || month > 13) {
      throw ArgumentError.value(
        month,
        'month',
        'Ethiopian month must be between 1 and 13.',
      );
    }
    if (month == 13) {
      return isEthiopianLeapYear(year) ? 6 : 5;
    }
    return 30;
  }

  /// Total days in Ethiopian [year] (365 ordinary, 366 leap).
  static int daysInEthiopianYear(int year) {
    if (year < 1) {
      throw ArgumentError.value(
        year,
        'year',
        'Ethiopian year must be >= 1.',
      );
    }
    return isEthiopianLeapYear(year) ? 366 : 365;
  }

  /// Validates Gregorian calendar components strictly.
  static void validateGregorian(int year, int month, int day) {
    if (year < 1 || year > 9999) {
      throw ArgumentError.value(
        year,
        'year',
        'Gregorian year must be between 1 and 9999.',
      );
    }
    final maxDays = daysInGregorianMonth(year, month);
    if (day < 1 || day > maxDays) {
      throw ArgumentError.value(
        day,
        'day',
        'Invalid Gregorian day $day for $year-${month.toString().padLeft(2, '0')} '
            '(valid range: 1..$maxDays).',
      );
    }
  }

  /// Validates Ethiopian calendar components strictly (rejects Pagume 6
  /// in ordinary years, Pagume >= 7, month > 13, day > 30, etc.).
  static void validateEthiopian(int year, int month, int day) {
    if (year < 1 || year > 9999) {
      throw ArgumentError.value(
        year,
        'year',
        'Ethiopian year must be between 1 and 9999.',
      );
    }
    final maxDays = daysInEthiopianMonth(year, month);
    if (day < 1 || day > maxDays) {
      throw ArgumentError.value(
        day,
        'day',
        'Invalid Ethiopian day $day for $year-${month.toString().padLeft(2, '0')} '
            '(valid range: 1..$maxDays).',
      );
    }
  }

  /// Converts validated Gregorian date components to Julian Day Number (JDN).
  static int gregorianToJdn(int year, int month, int day) {
    validateGregorian(year, month, day);
    final a = (14 - month) ~/ 12;
    final y = year + 4800 - a;
    final m = month + 12 * a - 3;
    return day +
        ((153 * m + 2) ~/ 5) +
        365 * y +
        (y ~/ 4) -
        (y ~/ 100) +
        (y ~/ 400) -
        32045;
  }

  /// Converts Julian Day Number (JDN) to Gregorian calendar components.
  static ({int year, int month, int day}) jdnToGregorian(int jdn) {
    final a = jdn + 32044;
    final b = _floorDiv(4 * a + 3, 146097);
    final c = a - _floorDiv(146097 * b, 4);
    final d = _floorDiv(4 * c + 3, 1461);
    final e = c - _floorDiv(1461 * d, 4);
    final m = _floorDiv(5 * e + 2, 153);

    final day = e - _floorDiv(153 * m + 2, 5) + 1;
    final month = m + 3 - 12 * _floorDiv(m, 10);
    final year = 100 * b + d - 4800 + _floorDiv(m, 10);
    if (year < 1 || year > 9999) {
      throw ArgumentError.value(
        jdn,
        'jdn',
        'Julian Day Number $jdn resolves outside Gregorian range 0001..9999 '
            '(got year $year).',
      );
    }
    return (year: year, month: month, day: day);
  }

  /// Converts validated Ethiopian date components to Julian Day Number (JDN).
  static int ethiopianToJdn(int year, int month, int day) {
    validateEthiopian(year, month, day);
    final y0 = year - 1;
    final leapDays = _floorDiv(y0 + 1, 4);
    return ethiopianEpochJdn +
        365 * y0 +
        leapDays +
        (month - 1) * 30 +
        (day - 1);
  }

  /// Converts Julian Day Number (JDN) to Ethiopian calendar components.
  ///
  /// Throws [ArgumentError] for JDN values prior to Meskerem 1, 1 E.C.
  /// (`ethiopianEpochJdn` = 1724221 / proleptic Gregorian 0008-08-27).
  static ({int year, int month, int day}) jdnToEthiopian(int jdn) {
    if (jdn < ethiopianEpochJdn) {
      throw ArgumentError.value(
        jdn,
        'jdn',
        'Julian Day Number $jdn precedes Meskerem 1, 1 E.C. '
            '($ethiopianEpochJdn).',
      );
    }
    final days = jdn - ethiopianEpochJdn;
    var y0 = _floorDiv(4 * days, 1461);

    while (days < 365 * y0 + _floorDiv(y0 + 1, 4)) {
      y0--;
    }
    while (days >= 365 * (y0 + 1) + _floorDiv(y0 + 2, 4)) {
      y0++;
    }

    final year = y0 + 1;
    final dayOfYear = days - (365 * y0 + _floorDiv(y0 + 1, 4));
    var month = (dayOfYear ~/ 30) + 1;
    final day = (dayOfYear % 30) + 1;
    if (month > 13) {
      month = 13;
    }
    return (year: year, month: month, day: day);
  }

  /// ISO-8601 weekday (1 = Monday .. 7 = Sunday) from Julian Day Number.
  static int weekdayFromJdn(int jdn) => _positiveMod(jdn, 7) + 1;
}
