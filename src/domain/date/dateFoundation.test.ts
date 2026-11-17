import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import {
  CalendarDate,
  DateRange,
  DayTimeOfDay,
  EthiopiaClock,
  EthiopianDate,
  LocalDateTime,
  SharedDateFormatter,
  daysInEthiopianMonth,
  daysInEthiopianYear,
  daysInGregorianMonth,
  daysInGregorianYear,
  ethiopianToJdn,
  gregorianToJdn,
  isEthiopianLeapYear,
  isGregorianLeapYear,
  jdnToEthiopian,
  jdnToGregorian,
} from './index';
import {
  fromEthiopiaInstant,
  fromGregorianDate,
  toGregorianDate,
} from '../ethiopianCalendar';
import { isValidDateFormat, isValidTimeFormat, validateCalendarEventForm } from '../formValidationAndNavigation';
import { validateSimpleTransaction, verifyFinancialDataIntegrity } from '../doubleEntryFinance';
import { SharedStateBridge } from '../../services/sharedStateBridge';

interface ConversionVector {
  gregorian: string;
  ethiopian: { year: number; month: number; day: number };
  weekday: number;
  gregorianLeap: boolean;
  ethiopianLeap: boolean;
  label: string;
}

interface ArithmeticVector {
  startGregorian: string;
  addDays: number;
  expectedGregorian: string;
  expectedEthiopian: { year: number; month: number; day: number };
}

interface TestVectorsFile {
  conversionVectors: ConversionVector[];
  invalidGregorianDates: string[];
  invalidEthiopianDates: Array<{ year: number; month: number; day: number }>;
  arithmeticVectors: ArithmeticVector[];
}

const vectorsPath = path.join(process.cwd(), 'shared_foundation', 'calendar_test_vectors.json');
const vectors: TestVectorsFile = JSON.parse(fs.readFileSync(vectorsPath, 'utf8'));

describe('STAGE 2.6 SHARED CALENDAR FOUNDATION & ETHIOPIAN/GREGORIAN DATE ENGINE', () => {
  afterEach(() => {
    EthiopiaClock.setClockForTesting(null);
  });

  it('1. Shared Golden Test Vectors & Independent Historical Anchors', () => {
    for (const v of vectors.conversionVectors) {
      const greg = CalendarDate.parse(v.gregorian);
      const eth = greg.toEthiopian();

      assert.strictEqual(eth.year, v.ethiopian.year, `${v.label}: year mismatch`);
      assert.strictEqual(eth.month, v.ethiopian.month, `${v.label}: month mismatch`);
      assert.strictEqual(eth.day, v.ethiopian.day, `${v.label}: day mismatch`);
      assert.strictEqual(greg.weekday, v.weekday, `${v.label}: gregorian weekday mismatch`);
      assert.strictEqual(eth.weekday, v.weekday, `${v.label}: ethiopian weekday mismatch`);
      assert.strictEqual(greg.isGregorianLeapYear, v.gregorianLeap, `${v.label}: gregorian leap mismatch`);
      assert.strictEqual(eth.isLeapYear, v.ethiopianLeap, `${v.label}: ethiopian leap mismatch`);

      // Reverse conversion must yield exact same CalendarDate and JDN
      const roundTripGreg = CalendarDate.fromEthiopian(v.ethiopian.year, v.ethiopian.month, v.ethiopian.day);
      assert.strictEqual(roundTripGreg.toIsoString(), v.gregorian, `${v.label}: reverse ISO mismatch`);
      assert.strictEqual(roundTripGreg.jdn, greg.jdn, `${v.label}: JDN mismatch`);
    }

    // Independent Gregorian 100/400 century leap-year & Ethiopian Millennium anchors
    const feb281900 = CalendarDate.parse('1900-02-28');
    assert.strictEqual(feb281900.isGregorianLeapYear, false);
    assert.strictEqual(feb281900.addDays(1).toIsoString(), '1900-03-01');
    assert.throws(() => CalendarDate.parse('1900-02-29'));

    const feb292000 = CalendarDate.parse('2000-02-29');
    assert.strictEqual(feb292000.isGregorianLeapYear, true);
    assert.strictEqual(feb292000.toEthiopian().toIsoString(), '1992-06-21');

    const feb282100 = CalendarDate.parse('2100-02-28');
    assert.strictEqual(feb282100.isGregorianLeapYear, false);
    assert.strictEqual(feb282100.addDays(1).toIsoString(), '2100-03-01');

    // Ethiopian Millennium: Meskerem 1, 2000 E.C. == 2007-09-12 (1999 E.C. was leap with Pagume 6)
    assert.strictEqual(CalendarDate.fromEthiopian(1999, 13, 6).toIsoString(), '2007-09-11');
    assert.strictEqual(CalendarDate.fromEthiopian(2000, 1, 1).toIsoString(), '2007-09-12');
    assert.strictEqual(CalendarDate.parse('1974-09-11').toEthiopian().toIsoString(), '1967-01-01');
  });

  it('2. Exhaustive Continuity Invariant (1890-2120): Every consecutive day increments JDN by 1 in both systems without gaps or drift', () => {
    const startJdn = gregorianToJdn(1890, 1, 1);
    const endJdn = gregorianToJdn(2120, 12, 31);
    let prevEth = jdnToEthiopian(startJdn);
    let prevGreg = jdnToGregorian(startJdn);

    for (let jdn = startJdn + 1; jdn <= endJdn; jdn++) {
      const g = jdnToGregorian(jdn);
      const e = jdnToEthiopian(jdn);

      assert.strictEqual(gregorianToJdn(g.year, g.month, g.day), jdn);
      assert.strictEqual(ethiopianToJdn(e.year, e.month, e.day), jdn);

      // Verify Ethiopian sequential continuity
      if (e.year === prevEth.year && e.month === prevEth.month) {
        assert.strictEqual(e.day, prevEth.day + 1);
      } else if (e.year === prevEth.year) {
        assert.strictEqual(e.month, prevEth.month + 1);
        assert.strictEqual(e.day, 1);
        assert.strictEqual(prevEth.day, daysInEthiopianMonth(prevEth.year, prevEth.month));
      } else {
        assert.strictEqual(e.year, prevEth.year + 1);
        assert.strictEqual(e.month, 1);
        assert.strictEqual(e.day, 1);
        assert.strictEqual(prevEth.month, 13);
        assert.strictEqual(prevEth.day, daysInEthiopianMonth(prevEth.year, 13));
      }

      // Verify Gregorian sequential continuity
      if (g.year === prevGreg.year && g.month === prevGreg.month) {
        assert.strictEqual(g.day, prevGreg.day + 1);
      } else if (g.year === prevGreg.year) {
        assert.strictEqual(g.month, prevGreg.month + 1);
        assert.strictEqual(g.day, 1);
        assert.strictEqual(prevGreg.day, daysInGregorianMonth(prevGreg.year, prevGreg.month));
      } else {
        assert.strictEqual(g.year, prevGreg.year + 1);
        assert.strictEqual(g.month, 1);
        assert.strictEqual(g.day, 1);
        assert.strictEqual(prevGreg.month, 12);
        assert.strictEqual(prevGreg.day, 31);
      }

      prevEth = e;
      prevGreg = g;
    }
  });

  it('3. Ethiopian Leap Year Rules (year % 4 === 3), Pagume Days, JDN Bounds, and Strict Input Validation', () => {
    assert.strictEqual(isEthiopianLeapYear(2015), true);
    assert.strictEqual(isEthiopianLeapYear(2016), false);
    assert.strictEqual(isEthiopianLeapYear(2019), true);
    assert.strictEqual(daysInEthiopianMonth(2015, 13), 6);
    assert.strictEqual(daysInEthiopianMonth(2016, 13), 5);
    assert.strictEqual(daysInEthiopianYear(2015), 366);
    assert.strictEqual(daysInEthiopianYear(2016), 365);

    assert.strictEqual(isGregorianLeapYear(1900), false);
    assert.strictEqual(isGregorianLeapYear(2000), true);
    assert.strictEqual(isGregorianLeapYear(2024), true);
    assert.strictEqual(isGregorianLeapYear(2026), false);
    assert.strictEqual(daysInGregorianYear(2024), 366);
    assert.strictEqual(daysInGregorianYear(2026), 365);

    assert.throws(() => jdnToEthiopian(1724220));
    assert.throws(() => jdnToEthiopian(1724221.5));
    assert.throws(() => jdnToGregorian(gregorianToJdn(9999, 12, 31) + 1));
    assert.throws(() => jdnToGregorian(2460000.5));

    for (const invalidIso of vectors.invalidGregorianDates) {
      assert.throws(() => CalendarDate.parse(invalidIso), `Expected invalid Gregorian rejection for ${invalidIso}`);
      assert.strictEqual(CalendarDate.tryParse(invalidIso), null);
      assert.strictEqual(isValidDateFormat(invalidIso), false);
    }

    for (const invalidEth of vectors.invalidEthiopianDates) {
      assert.throws(
        () => new EthiopianDate(invalidEth.year, invalidEth.month, invalidEth.day),
        `Expected invalid Ethiopian rejection for ${JSON.stringify(invalidEth)}`,
      );
    }

    assert.strictEqual(isValidDateFormat('2026-11-14'), true);
    assert.strictEqual(isValidTimeFormat('00:00'), true);
    assert.strictEqual(isValidTimeFormat('23:59'), true);
    assert.strictEqual(isValidTimeFormat('24:00'), false);
    assert.strictEqual(isValidTimeFormat('12:60'), false);
    assert.strictEqual(isValidTimeFormat('9:30'), false);
  });

  it('4. Date Arithmetic & Calendar-Specific Month/Year Grids and Bounds', () => {
    for (const av of vectors.arithmeticVectors) {
      const start = CalendarDate.parse(av.startGregorian);
      const result = start.addDays(av.addDays);
      assert.strictEqual(result.toIsoString(), av.expectedGregorian);
      const eth = result.toEthiopian();
      assert.strictEqual(eth.year, av.expectedEthiopian.year);
      assert.strictEqual(eth.month, av.expectedEthiopian.month);
      assert.strictEqual(eth.day, av.expectedEthiopian.day);
      assert.strictEqual(result.differenceInDays(start), av.addDays);
    }

    // Month & year bounds across systems
    const pagumeLeap = CalendarDate.monthDaysGrid('ethiopian', 2015, 13);
    assert.strictEqual(pagumeLeap.length, 6);
    assert.strictEqual(pagumeLeap[0].toIsoString(), '2023-09-06');
    assert.strictEqual(pagumeLeap[5].toIsoString(), '2023-09-11');

    const pagumeOrdinary = CalendarDate.monthDaysGrid('ethiopian', 2016, 13);
    assert.strictEqual(pagumeOrdinary.length, 5);
    assert.strictEqual(pagumeOrdinary[4].toIsoString(), '2024-09-10');

    const ethYear2016 = CalendarDate.yearBounds('ethiopian', 2016);
    assert.strictEqual(ethYear2016.start.toIsoString(), '2023-09-12');
    assert.strictEqual(ethYear2016.end.toIsoString(), '2024-09-10');
    assert.strictEqual(ethYear2016.end.differenceInDays(ethYear2016.start) + 1, 365);

    // Month clamping across Meskerem 30 -> Pagume 5/6 and Jan 31 -> Feb 28/29
    const jan31 = CalendarDate.parse('2025-01-31');
    assert.strictEqual(jan31.nextGregorianMonth().toIsoString(), '2025-02-28');
    const leapJan31 = CalendarDate.parse('2024-01-31');
    assert.strictEqual(leapJan31.nextGregorianMonth().toIsoString(), '2024-02-29');

    const nehase30 = CalendarDate.fromEthiopian(2016, 12, 30);
    assert.strictEqual(nehase30.nextEthiopianMonth().toEthiopian().toIsoString(), '2016-13-05');
    assert.strictEqual(
      CalendarDate.fromEthiopian(2015, 12, 30).nextEthiopianMonth().toEthiopian().toIsoString(),
      '2015-13-06',
    );
  });

  it('5. Fixed Ethiopia Civil Time (UTC+3) Midnight Boundary, Strict Timestamp Parsing, and LocalDateTime Separation', () => {
    assert.strictEqual(EthiopiaClock.UTC_OFFSET_HOURS, 3);
    assert.strictEqual(EthiopiaClock.TIME_ZONE_LABEL, 'UTC+3');

    // 20:59:59 UTC is 23:59:59 same civil day in Ethiopia (UTC+3)
    const beforeEthMidnight = new Date('2026-11-10T20:59:59.000Z');
    EthiopiaClock.setClockForTesting(() => beforeEthMidnight);
    assert.strictEqual(CalendarDate.today().toIsoString(), '2026-11-10');
    assert.strictEqual(LocalDateTime.now().toEthiopiaIsoString(), '2026-11-10T23:59:59+03:00');
    assert.strictEqual(SharedDateFormatter.formatEthiopiaTimestamp(beforeEthMidnight), '2026-11-10 23:59 (UTC+3)');

    // 21:00:00 UTC is 00:00:00 NEXT civil day in Ethiopia (UTC+3)
    const atEthMidnight = new Date('2026-11-10T21:00:00.000Z');
    EthiopiaClock.setClockForTesting(() => atEthMidnight);
    assert.strictEqual(CalendarDate.today().toIsoString(), '2026-11-11');
    assert.strictEqual(LocalDateTime.now().toEthiopiaIsoString(), '2026-11-11T00:00:00+03:00');

    // LocalDateTime round-trip to UTC instant and back
    const ldt = new LocalDateTime(CalendarDate.parse('2026-11-14'), 6, 30, 0);
    const utcInstant = ldt.toUtcInstant();
    assert.strictEqual(utcInstant.toISOString(), '2026-11-14T03:30:00.000Z');
    assert.strictEqual(LocalDateTime.fromUtcInstant(utcInstant).toEthiopiaIsoString(), '2026-11-14T06:30:00+03:00');
    assert.ok(ldt.equals(LocalDateTime.fromUtcInstant(utcInstant)));
    assert.strictEqual(ldt.compareTo(LocalDateTime.parse('2026-11-14T07:00:00')) < 0, true);
    assert.strictEqual(ldt.toString(), '2026-11-14T06:30:00+03:00');

    // Strict rejection of invalid dates/zones/trailing garbage even when JS Date would roll over
    assert.throws(() => LocalDateTime.parse('2026-02-30T10:00:00Z'));
    assert.throws(() => LocalDateTime.parse('2025-02-29T10:00:00+03:00'));
    assert.throws(() => LocalDateTime.parse('2026-11-10T10:00:00+25:99'));
    assert.throws(() => LocalDateTime.parse('2026-11-10T10:00:00abc'));
    assert.strictEqual(LocalDateTime.tryParse('2026-02-30T10:00:00Z'), null);

    // Flexible parser handles fractional seconds & colonless zones deterministically
    assert.strictEqual(
      SharedDateFormatter.parseFlexibleToCalendarDate('2026-11-10T21:30:00.000Z').toIsoString(),
      '2026-11-11',
    );
    assert.strictEqual(
      LocalDateTime.parse('2026-11-10T22:00:00-0500').toEthiopiaIsoString(),
      '2026-11-11T06:00:00+03:00',
    );
    assert.strictEqual(
      LocalDateTime.parse('2026-11-10T22:00:00.500').toEthiopiaIsoString(),
      '2026-11-10T22:00:00+03:00',
    );
    // Date-only string stays invariant (not shifted!)
    assert.strictEqual(SharedDateFormatter.parseFlexibleToCalendarDate('2026-11-10').toIsoString(), '2026-11-10');
  });

  it('6. DateRange Parity, Formatting, Legacy Wrappers, and Module Integration Validation', () => {
    const start = CalendarDate.parse('2026-11-10');
    const end = CalendarDate.parse('2026-11-14');
    const range = new DateRange(start, end);

    assert.strictEqual(range.lengthInDays, 5);
    assert.strictEqual(range.contains(CalendarDate.parse('2026-11-12')), true);
    assert.strictEqual(range.contains(CalendarDate.parse('2026-11-15')), false);
    assert.strictEqual(range.days().length, 5);
    assert.strictEqual(range.equals(new DateRange(start, end)), true);
    assert.strictEqual(range.toString(), '2026-11-10..2026-11-14');

    const overlapping = new DateRange(CalendarDate.parse('2026-11-14'), CalendarDate.parse('2026-11-20'));
    const disjoint = new DateRange(CalendarDate.parse('2026-11-15'), CalendarDate.parse('2026-11-20'));
    assert.strictEqual(range.overlaps(overlapping), true);
    assert.strictEqual(range.overlaps(disjoint), false);

    assert.throws(() => new DateRange(end, start));

    const t12 = DayTimeOfDay.parse('14:05');
    assert.strictEqual(t12.toDisplay12Hour(), '02:05 PM');
    assert.strictEqual(DayTimeOfDay.parse('00:15').toDisplay12Hour(), '12:15 AM');
    assert.strictEqual(t12.equals(DayTimeOfDay.parse('14:05')), true);
    assert.strictEqual(t12.toString(), '14:05');

    // Compatibility wrapper checks
    const instant = new Date('2023-09-11T22:00:00.000Z'); // Sept 12 in UTC+3 (Meskerem 1, 2016)
    const ethFromInstant = fromEthiopiaInstant(instant);
    assert.strictEqual(ethFromInstant.year, 2016);
    assert.strictEqual(ethFromInstant.month, 1);
    assert.strictEqual(ethFromInstant.day, 1);

    const gregMidnight = toGregorianDate(2016, 1, 1);
    const ethObj = fromGregorianDate(gregMidnight);
    assert.strictEqual(ethObj.year, 2016);
    assert.strictEqual(ethObj.month, 1);
    assert.strictEqual(ethObj.day, 1);

    // Module integration: calendar form multi-day validation
    const invalidRange = validateCalendarEventForm({
      title: 'Conference',
      date: '2026-11-15',
      endDate: '2026-11-14',
      isAllDay: true,
    });
    assert.strictEqual(invalidRange.isValid, false);
    assert.ok(invalidRange.errors.endDate);

    const validMultiDay = validateCalendarEventForm({
      title: 'Overnight Summit',
      date: '2026-11-14',
      endDate: '2026-11-16',
      isAllDay: false,
      startTime: '22:00',
      endTime: '09:00',
    });
    assert.strictEqual(validMultiDay.isValid, true);

    // Module integration: finance rejects impossible Gregorian dates (Feb 30)
    const txInvalidDate = validateSimpleTransaction(
      'expense',
      10000,
      'acc-1',
      'cat-1',
      undefined,
      '2026-02-30',
    );
    assert.strictEqual(txInvalidDate.isValid, false);
    assert.ok(txInvalidDate.errors.transactionDate);

    const integrity = verifyFinancialDataIntegrity(
      [{ id: 'acc-1', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 0, isArchived: false, createdAt: '2026-01-01T00:00:00Z' }],
      [{ id: 'cat-1', name: 'Food', type: 'expense', colorHex: '#EF4444' }],
      [{ id: 'tx-bad-date', amountCents: 100, type: 'expense', accountId: 'acc-1', categoryId: 'cat-1', transactionDate: '2026-02-30', createdAt: '2026-01-01T00:00:00Z' }],
    );
    assert.strictEqual(integrity.isHealthy, false);
    assert.ok(integrity.errors.some((e) => e.includes('invalid date format')));

    // SharedStateBridge import does NOT fabricate a 1,500,000 cent openingBalanceCents fallback
    const imported = SharedStateBridge.importFromAndroidJson(JSON.stringify({
      accounts: [],
      transactions: [],
    }));
    assert.strictEqual(imported.success, true);
    assert.strictEqual(imported.state?.openingBalanceCents, 0);
  });
});
