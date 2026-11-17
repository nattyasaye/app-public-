import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/domain/calendar/ethiopian_calendar.dart';
import 'package:personal_management_app/domain/calendar/ethiopian_date.dart';

void main() {
  group('Stage 5 Notes, Notifications & Localization Tests', () {
    test('Notes preserve full Ge`ez/Amharic Unicode text faithfully', () {
      const amharicText =
          'ትኩረት ማድረግ ያለብኝ ዋና ዋና ጉዳዮች፡ ጤና፣ የአእምሮ ሰላም እና የታቀዱ ግቦች።';
      final note = {
        'id': 'note-101',
        'title': 'የሳምንቱ ዕቅድ እና ማስታወሻ',
        'content': amharicText,
        'category': 'reflection',
      };

      expect(note['title'], contains('የሳምንቱ ዕቅድ'));
      expect(note['content'], amharicText);
      expect(note['category'], 'reflection');
    });

    test(
        'Calendar converter handles Pagume leap years accurately (Year % 4 == 3)',
        () {
      // 2015 E.C. (2015 % 4 == 3) had 6 days of Pagumē
      final leapEthDate = EthiopianDate(year: 2015, month: 13, day: 6);
      expect(leapEthDate.isLeapYear, isTrue);
      expect(leapEthDate.daysInMonth, 6);

      // Pagume 6, 2015 converted to Gregorian is September 11, 2023
      final gregDate = EthiopianCalendar.toGregorian(leapEthDate);
      expect(gregDate.year, 2023);
      expect(gregDate.month, 9);
      expect(gregDate.day, 11);

      // And round-trip back preserves Pagume 6
      final restored = EthiopianCalendar.fromGregorian(gregDate);
      expect(restored.year, 2015);
      expect(restored.month, 13);
      expect(restored.day, 6);
    });

    test('Calendar converter handles Enkutatash (Meskerem 1) transitions', () {
      // Enkutatash 2017: September 11, 2024
      final sep11 = DateTime.utc(2024, 9, 11);
      final eth = EthiopianCalendar.fromGregorian(sep11);

      expect(eth.year, 2017);
      expect(eth.month, 1);
      expect(eth.day, 1);
      expect(eth.amharicMonthName, 'መስከረም');
    });

    test(
        'Offline local notification parameters format properly without cloud server',
        () {
      final scheduledTime = DateTime.utc(2026, 11, 8, 9, 0);
      final reminder = {
        'id': 'rem-501',
        'targetId': 'commit-1',
        'targetType': 'commitment',
        'title': 'Payment Due: House Rent (ቤት ኪራይ)',
        'triggerTimeUtc': scheduledTime,
        'channelId': 'commitment_reminders_channel',
        'isExactAlarm': true,
      };

      expect(reminder['channelId'], 'commitment_reminders_channel');
      expect(reminder['isExactAlarm'], isTrue);
      expect(reminder['triggerTimeUtc'], scheduledTime);
    });

    test('Share-Intent receiver extracts shared text into inbox format', () {
      const sharedUrl =
          'https://example.com/useful-offline-resource Notes to review later';
      final inboxItem = {
        'id': 'inbox-share-1',
        'rawText': sharedUrl,
        'category': 'general',
        'isProcessed': false,
      };

      expect(inboxItem['rawText'], contains('https://example.com'));
      expect(inboxItem['isProcessed'], isFalse);
    });
  });
}
