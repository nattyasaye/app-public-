import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/domain/calendar/ethiopian_calendar.dart';
import 'package:personal_management_app/domain/calendar/ethiopian_date.dart';

void main() {
  group('EthiopianCalendar Conversion Tests', () {
    test('Converts Ethiopian New Year 2017 (Enkutatash - Sep 11, 2024)', () {
      final sep11 = DateTime.utc(2024, 9, 11);
      final eth = EthiopianCalendar.fromGregorian(sep11);

      expect(eth.year, 2017);
      expect(eth.month, 1); // Meskerem
      expect(eth.day, 1);
      expect(eth.amharicMonthName, 'መስከረም');
    });

    test('Converts Gregorian date (Nov 07, 2024) to Ethiopian Tikimt 28, 2017',
        () {
      final nov7 = DateTime.utc(2024, 11, 7);
      final eth = EthiopianCalendar.fromGregorian(nov7);

      expect(eth.year, 2017);
      expect(eth.month, 2); // Tikimt
      expect(eth.day, 28);
      expect(eth.toAmharicString(includeEra: false), 'ጥቅምት 28, 2017');
    });

    test('Bidirectional round-trip conversion preserves exact dates', () {
      final sampleDates = [
        DateTime.utc(2023, 1, 1),
        DateTime.utc(2024, 2, 29), // Gregorian Leap day
        DateTime.utc(2024, 9, 11), // Ethiopian New year
        DateTime.utc(2025, 9, 10), // Pagumē test
        DateTime.utc(2027, 9, 11),
      ];

      for (final date in sampleDates) {
        final eth = EthiopianCalendar.fromGregorian(date);
        final restoredGregorian = EthiopianCalendar.toGregorian(eth);

        expect(restoredGregorian.year, date.year);
        expect(restoredGregorian.month, date.month);
        expect(restoredGregorian.day, date.day);
      }
    });

    test('Pagumē leap year calculation (Year % 4 == 3 has 6 days)', () {
      // 2015 E.C. was a leap year (2015 % 4 == 3) -> 6 days of Pagumē
      final leapYear = EthiopianDate(year: 2015, month: 13, day: 6);
      expect(leapYear.isLeapYear, isTrue);
      expect(leapYear.daysInMonth, 6);

      // 2016 E.C. regular year -> 5 days
      final regularYear = EthiopianDate(year: 2016, month: 13, day: 5);
      expect(regularYear.isLeapYear, isFalse);
      expect(regularYear.daysInMonth, 5);
    });

    test('Dual calendar display formatting', () {
      final nov7 = DateTime.utc(2024, 11, 7);
      final dual = EthiopianCalendar.formatDual(nov7);
      expect(dual, contains('ጥቅምት 28, 2017'));
      expect(dual, contains('Nov 07, 2024'));
    });
  });
}
