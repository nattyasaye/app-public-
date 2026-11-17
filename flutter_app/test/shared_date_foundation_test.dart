import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/domain/calendar/calendar_models.dart';
import 'package:personal_management_app/domain/calendar/ethiopian_calendar.dart';

Map<String, dynamic> _loadSharedVectors() {
  final candidates = [
    File('../shared_foundation/calendar_test_vectors.json'),
    File('shared_foundation/calendar_test_vectors.json'),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) {
      return jsonDecode(candidate.readAsStringSync()) as Map<String, dynamic>;
    }
  }
  throw StateError('Unable to locate shared calendar_test_vectors.json');
}

void main() {
  tearDown(() {
    EthiopiaClock.setClockForTesting(null);
  });

  group('Shared Date Foundation & Dual-Calendar Engine', () {
    test('Matches all shared golden vectors (Ethiopian, Gregorian, weekday)',
        () {
      final fixtures = _loadSharedVectors();
      final vectors = (fixtures['conversionVectors'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      for (final vector in vectors) {
        final gregIso = vector['gregorian'] as String;
        final ethMap = vector['ethiopian'] as Map<String, dynamic>;
        final expectedEthYear = ethMap['year'] as int;
        final expectedEthMonth = ethMap['month'] as int;
        final expectedEthDay = ethMap['day'] as int;
        final expectedWeekday = vector['weekday'] as int;
        final expectedGregLeap = vector['gregorianLeap'] as bool;
        final expectedEthLeap = vector['ethiopianLeap'] as bool;

        final gregDate = CalendarDate.parse(gregIso);
        final ethDate = gregDate.toEthiopian();

        expect(ethDate.year, expectedEthYear, reason: gregIso);
        expect(ethDate.month, expectedEthMonth, reason: gregIso);
        expect(ethDate.day, expectedEthDay, reason: gregIso);
        expect(gregDate.weekday, expectedWeekday, reason: gregIso);
        expect(ethDate.weekday, expectedWeekday, reason: gregIso);
        expect(gregDate.isGregorianLeapYear, expectedGregLeap, reason: gregIso);
        expect(ethDate.isLeapYear, expectedEthLeap, reason: gregIso);

        final roundTrip = CalendarDate.fromEthiopian(
          expectedEthYear,
          expectedEthMonth,
          expectedEthDay,
        );
        expect(roundTrip, gregDate, reason: gregIso);
        expect(roundTrip.toIsoString(), gregIso);
      }

      final arithVectors = (fixtures['arithmeticVectors'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final vector in arithVectors) {
        final start = CalendarDate.parse(vector['startGregorian'] as String);
        final delta = vector['addDays'] as int;
        final moved = start.addDays(delta);
        expect(moved.toIsoString(), vector['expectedGregorian']);

        final expectedEth = vector['expectedEthiopian'] as Map<String, dynamic>;
        final eth = moved.toEthiopian();
        expect(eth.year, expectedEth['year']);
        expect(eth.month, expectedEth['month']);
        expect(eth.day, expectedEth['day']);
      }
    });

    test('Independent historical & century-leap astronomical anchors', () {
      // 1900 was NOT a Gregorian leap year (divisible by 100, not 400)
      final feb281900 = CalendarDate(year: 1900, month: 2, day: 28);
      expect(feb281900.isGregorianLeapYear, isFalse);
      expect(
        feb281900.addDays(1),
        CalendarDate(year: 1900, month: 3, day: 1),
      );
      expect(
        () => CalendarDate(year: 1900, month: 2, day: 29),
        throwsArgumentError,
      );

      // 2000 WAS a Gregorian leap year (divisible by 400)
      final feb292000 = CalendarDate(year: 2000, month: 2, day: 29);
      expect(feb292000.isGregorianLeapYear, isTrue);
      expect(
        feb292000.toEthiopian(),
        EthiopianDate(year: 1992, month: 6, day: 21),
      );

      // Ethiopian Millennium: Meskerem 1, 2000 E.C. == Sep 12, 2007 (after leap 1999 E.C.)
      final ethMillennium = EthiopianDate(year: 2000, month: 1, day: 1);
      expect(
        ethMillennium.toCalendarDate(),
        CalendarDate(year: 2007, month: 9, day: 12),
      );
      expect(
        EthiopianDate(year: 1999, month: 13, day: 6).toCalendarDate(),
        CalendarDate(year: 2007, month: 9, day: 11),
      );
    });

    test('Exhaustive daily JDN & dual-calendar continuity (1890..2120)', () {
      var current = CalendarDate(year: 1890, month: 1, day: 1);
      final end = CalendarDate(year: 2120, month: 12, day: 31);
      var prevJdn = current.jdn - 1;
      var checked = 0;

      while (current <= end) {
        expect(current.jdn, prevJdn + 1);
        final eth = current.toEthiopian();
        expect(eth.jdn, current.jdn);
        expect(eth.toCalendarDate(), current);

        final expectedDaysInEthYear =
            CalendarEngine.isEthiopianLeapYear(eth.year) ? 366 : 365;
        expect(eth.daysInYear, expectedDaysInEthYear);

        if (eth.month < 13) {
          expect(eth.day, inInclusiveRange(1, 30));
        } else {
          final maxPagume =
              CalendarEngine.isEthiopianLeapYear(eth.year) ? 6 : 5;
          expect(eth.day, inInclusiveRange(1, maxPagume));
        }

        prevJdn = current.jdn;
        current = current.addDays(1);
        checked++;
      }

      expect(checked, greaterThan(84000));
    });

    test(
        'Strict validation rejects impossible dates, zones, and malformed strings',
        () {
      final fixtures = _loadSharedVectors();
      final invalidGreg =
          (fixtures['invalidGregorianDates'] as List<dynamic>).cast<String>();
      for (final raw in invalidGreg) {
        expect(
          () => CalendarDate.parse(raw),
          throwsA(anyOf(isFormatException, isArgumentError)),
          reason: 'Should reject Gregorian "$raw"',
        );
        expect(CalendarDate.tryParse(raw), isNull, reason: raw);
      }

      final invalidEth = (fixtures['invalidEthiopianDates'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final item in invalidEth) {
        final y = item['year'] as int;
        final m = item['month'] as int;
        final d = item['day'] as int;
        expect(
          () => EthiopianDate(year: y, month: m, day: d),
          throwsArgumentError,
          reason: 'Should reject Ethiopian $y-$m-$d',
        );
      }

      expect(
        () =>
            CalendarEngine.jdnToEthiopian(CalendarEngine.ethiopianEpochJdn - 1),
        throwsArgumentError,
      );
      expect(
        () => CalendarEngine.jdnToGregorian(
            CalendarEngine.gregorianToJdn(9999, 12, 31) + 1),
        throwsArgumentError,
      );

      expect(
        () => LocalDateTime.parse('2026-02-30T10:00:00Z'),
        throwsArgumentError,
      );
      expect(
        () => LocalDateTime.parse('2026-11-14T10:00:00+25:99'),
        throwsFormatException,
      );
      expect(
        EthiopiaClock.tryParseInstantUtc('2026-11-14T10:00:00+25:99'),
        isNull,
      );

      expect(
        () => DayTimeOfDay(hour: 24, minute: 0),
        throwsArgumentError,
      );
      expect(
        () => DayTimeOfDay(hour: 12, minute: 60),
        throwsArgumentError,
      );
      expect(() => DayTimeOfDay.parse('9:30'), throwsFormatException);
      expect(
        () => DateRange(
          start: CalendarDate(year: 2026, month: 5, day: 10),
          end: CalendarDate(year: 2026, month: 5, day: 9),
        ),
        throwsArgumentError,
      );
    });

    test('Fixed Ethiopia UTC+3 clock boundary and LocalDateTime conversion',
        () {
      // 20:59:59 UTC is 23:59:59 EAT (still same civil day in Ethiopia).
      final beforeMidnightUtc = DateTime.utc(2026, 11, 14, 20, 59, 59);
      EthiopiaClock.setClockForTesting(() => beforeMidnightUtc);
      expect(
        CalendarDate.today(),
        CalendarDate(year: 2026, month: 11, day: 14),
      );
      final beforeLdt = LocalDateTime.now();
      expect(beforeLdt.hour, 23);
      expect(beforeLdt.minute, 59);
      expect(beforeLdt.second, 59);
      expect(beforeLdt.toUtcInstant(), beforeMidnightUtc);
      expect(
        beforeLdt.toEthiopiaIsoString(),
        '2026-11-14T23:59:59+03:00',
      );

      // 21:00:00 UTC is 00:00:00 EAT on the next civil day in Ethiopia.
      final midnightUtc = DateTime.utc(2026, 11, 14, 21, 0, 0);
      EthiopiaClock.setClockForTesting(() => midnightUtc);
      expect(
        CalendarDate.today(),
        CalendarDate(year: 2026, month: 11, day: 15),
      );
      final afterLdt = LocalDateTime.now();
      expect(afterLdt.date, CalendarDate(year: 2026, month: 11, day: 15));
      expect(afterLdt.hour, 0);
      expect(afterLdt.minute, 0);
      expect(afterLdt.toUtcInstant(), midnightUtc);

      final parsedOffset = LocalDateTime.parse('2026-11-14T21:30:00Z');
      expect(parsedOffset.date, CalendarDate(year: 2026, month: 11, day: 15));
      expect(parsedOffset.hour, 0);
      expect(parsedOffset.minute, 30);

      // Bare timestamp stays in Ethiopia wall time without +3h double shift
      final bareLdt = LocalDateTime.parse('2026-11-14T22:15:00');
      expect(bareLdt.date, CalendarDate(year: 2026, month: 11, day: 14));
      expect(bareLdt.hour, 22);
      expect(bareLdt.minute, 15);
    });

    test(
        'Month clamping, bounds, grids, DateRange, CalendarEventEntity, and formatting',
        () {
      final jan31 = CalendarDate(year: 2024, month: 1, day: 31);
      expect(
        jan31.nextGregorianMonth(),
        CalendarDate(year: 2024, month: 2, day: 29),
      );

      final jan31NonLeap = CalendarDate(year: 2025, month: 1, day: 31);
      expect(
        jan31NonLeap.nextGregorianMonth(),
        CalendarDate(year: 2025, month: 2, day: 28),
      );

      final ethNehase30 = EthiopianDate(year: 2015, month: 12, day: 30);
      expect(
        ethNehase30.nextMonth(),
        EthiopianDate(year: 2015, month: 13, day: 6),
      );
      expect(
        EthiopianDate(year: 2015, month: 13, day: 6).nextYear(),
        EthiopianDate(year: 2016, month: 13, day: 5),
      );

      final pagumeBounds = CalendarDate.monthBounds(
        CalendarSystem.ethiopian,
        2015,
        13,
      );
      expect(pagumeBounds.start, CalendarDate(year: 2023, month: 9, day: 6));
      expect(pagumeBounds.end, CalendarDate(year: 2023, month: 9, day: 11));

      final pagumeGrid = CalendarDate.monthDaysGrid(
        CalendarSystem.ethiopian,
        2015,
        13,
      );
      expect(pagumeGrid.length, 6);

      final range = DateRange.forMonth(CalendarSystem.ethiopian, 2015, 13);
      expect(range.lengthInDays, 6);
      expect(
        range.contains(CalendarDate(year: 2023, month: 9, day: 8)),
        isTrue,
      );
      expect(
        range.contains(CalendarDate(year: 2023, month: 9, day: 12)),
        isFalse,
      );

      final sample = CalendarDate(year: 2024, month: 11, day: 7);
      expect(SharedDateFormatter.formatGregorianShort(sample), 'Nov 07, 2024');
      expect(
        SharedDateFormatter.formatDual(sample),
        'ጥቅምት 28, 2017 (Nov 07, 2024)',
      );
      expect(
        EthiopianCalendar.formatDual(DateTime.utc(2024, 11, 7)),
        'ጥቅምት 28, 2017 (Nov 07, 2024)',
      );

      final multiDay = CalendarEventEntity(
        id: 'ev-span',
        title: 'Summit',
        dateIso: '2026-11-14',
        endDateIso: '2026-11-16',
      );
      expect(multiDay.isMultiDay, isTrue);
      expect(multiDay.spanInDays, 3);
      expect(
        multiDay.occursOn(CalendarDate(year: 2026, month: 11, day: 15)),
        isTrue,
      );
      expect(
        multiDay.occursOn(CalendarDate(year: 2026, month: 11, day: 17)),
        isFalse,
      );

      expect(
        () => CalendarEventEntity(
          id: 'ev-bad-range',
          title: 'Invalid Range',
          dateIso: '2026-11-16',
          endDateIso: '2026-11-14',
        ),
        throwsArgumentError,
      );
      expect(
        () => CalendarEventEntity(
          id: 'ev-bad-time',
          title: 'Invalid Same-Day Time',
          dateIso: '2026-11-14',
          startTime: '15:00',
          endTime: '14:00',
        ),
        throwsArgumentError,
      );
    });
  });
}
