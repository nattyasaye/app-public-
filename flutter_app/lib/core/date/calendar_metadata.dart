/// Static calendar display metadata kept separate from mathematical calculations.
class CalendarMetadata {
  const CalendarMetadata._();

  /// Names of the 13 Ethiopian months in Amharic (Ge'ez) script.
  static const List<String> ethiopianAmharicMonths = [
    'መስከረም', // 1: Meskerem
    'ጥቅምት', // 2: Tikimt
    'ኅዳር', // 3: Hidar
    'ታኅሣሥ', // 4: Tahsas
    'ጥር', // 5: Tir
    'የካቲት', // 6: Yekatit
    'መጋቢት', // 7: Megabit
    'ሚያዝያ', // 8: Miyazya
    'ግንቦት', // 9: Ginbot
    'ሰኔ', // 10: Sene
    'ሐምሌ', // 11: Hamle
    'ነሐሴ', // 12: Nehase
    'ጳጉሜ', // 13: Pagume
  ];

  /// Phonetic transliterations of the 13 Ethiopian months in English.
  static const List<String> ethiopianEnglishMonths = [
    'Meskerem',
    'Tikimt',
    'Hidar',
    'Tahsas',
    'Tir',
    'Yekatit',
    'Megabit',
    'Miyazya',
    'Ginbot',
    'Sene',
    'Hamle',
    'Nehase',
    'Pagume',
  ];

  /// Short Gregorian month names (1 = Jan .. 12 = Dec).
  static const List<String> gregorianShortMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Full Gregorian month names (1 = January .. 12 = December).
  static const List<String> gregorianFullMonths = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// ISO-8601 weekday names in English (1 = Monday .. 7 = Sunday).
  static const List<String> weekdayEnglishNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// Short weekday names in English (1 = Mon .. 7 = Sun).
  static const List<String> weekdayShortEnglishNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// Traditional Ethiopian weekday names in Amharic (1 = Monday/ሰኞ .. 7 = Sunday).
  static const List<String> weekdayAmharicNames = [
    'ሰኞ', // Monday
    'ማክሰኞ', // Tuesday
    'ረቡዕ', // Wednesday
    'ሐሙስ', // Thursday
    'ዓርብ', // Friday
    'ቅዳሜ', // Saturday
    'እሑድ', // Sunday
  ];
}
