import {
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
  weekdayFromJdn,
} from './calendarEngine';
import {
  ETHIOPIAN_AMHARIC_MONTHS,
  ETHIOPIAN_ENGLISH_MONTHS,
  GREGORIAN_FULL_MONTHS,
  GREGORIAN_SHORT_MONTHS,
  WEEKDAY_AMHARIC_NAMES,
  WEEKDAY_ENGLISH_NAMES,
  WEEKDAY_SHORT_ENGLISH_NAMES,
} from './calendarMetadata';
import { CalendarSystem, EthiopiaClock } from './calendarSystem';

export class EthiopianDate {
  public readonly year: number;
  public readonly month: number; // 1..13
  public readonly day: number; // 1..30 (1..5/6 for Pagume)
  public readonly jdn: number;

  constructor(year: number, month: number, day: number, prevalidatedJdn?: number) {
    this.year = year;
    this.month = month;
    this.day = day;
    this.jdn = prevalidatedJdn !== undefined ? prevalidatedJdn : ethiopianToJdn(year, month, day);
  }

  public static fromJdn(jdn: number): EthiopianDate {
    const parts = jdnToEthiopian(jdn);
    return new EthiopianDate(parts.year, parts.month, parts.day, jdn);
  }

  public static today(): EthiopianDate {
    return CalendarDate.today().toEthiopian();
  }

  public static parse(input: string): EthiopianDate {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(input.trim());
    if (!match) {
      throw new Error(`Invalid Ethiopian date string "${input}". Expected YYYY-MM-DD.`);
    }
    return new EthiopianDate(
      parseInt(match[1], 10),
      parseInt(match[2], 10),
      parseInt(match[3], 10),
    );
  }

  public get isLeapYear(): boolean {
    return isEthiopianLeapYear(this.year);
  }

  public get daysInMonth(): number {
    return daysInEthiopianMonth(this.year, this.month);
  }

  public get daysInYear(): number {
    return daysInEthiopianYear(this.year);
  }

  public get weekday(): number {
    return weekdayFromJdn(this.jdn);
  }

  public get amharicMonthName(): string {
    return ETHIOPIAN_AMHARIC_MONTHS[this.month - 1];
  }

  public get englishMonthName(): string {
    return ETHIOPIAN_ENGLISH_MONTHS[this.month - 1];
  }

  public get amharicWeekdayName(): string {
    return WEEKDAY_AMHARIC_NAMES[this.weekday - 1];
  }

  public get englishWeekdayName(): string {
    return WEEKDAY_ENGLISH_NAMES[this.weekday - 1];
  }

  public toCalendarDate(): CalendarDate {
    return CalendarDate.fromJdn(this.jdn);
  }

  public toGregorianUtcDate(): Date {
    return this.toCalendarDate().toGregorianUtcMidnight();
  }

  public addDays(days: number): EthiopianDate {
    return EthiopianDate.fromJdn(this.jdn + days);
  }

  public subtractDays(days: number): EthiopianDate {
    return EthiopianDate.fromJdn(this.jdn - days);
  }

  public differenceInDays(other: EthiopianDate): number {
    return this.jdn - other.jdn;
  }

  public nextMonth(): EthiopianDate {
    const nextY = this.month === 13 ? this.year + 1 : this.year;
    const nextM = this.month === 13 ? 1 : this.month + 1;
    const maxD = daysInEthiopianMonth(nextY, nextM);
    return new EthiopianDate(nextY, nextM, Math.min(this.day, maxD));
  }

  public previousMonth(): EthiopianDate {
    const prevY = this.month === 1 ? this.year - 1 : this.year;
    const prevM = this.month === 1 ? 13 : this.month - 1;
    const maxD = daysInEthiopianMonth(prevY, prevM);
    return new EthiopianDate(prevY, prevM, Math.min(this.day, maxD));
  }

  public nextYear(): EthiopianDate {
    const nextY = this.year + 1;
    const maxD = daysInEthiopianMonth(nextY, this.month);
    return new EthiopianDate(nextY, this.month, Math.min(this.day, maxD));
  }

  public previousYear(): EthiopianDate {
    const prevY = this.year - 1;
    const maxD = daysInEthiopianMonth(prevY, this.month);
    return new EthiopianDate(prevY, this.month, Math.min(this.day, maxD));
  }

  public get startOfMonth(): EthiopianDate {
    return new EthiopianDate(this.year, this.month, 1);
  }

  public get endOfMonth(): EthiopianDate {
    return new EthiopianDate(this.year, this.month, this.daysInMonth);
  }

  public get startOfYear(): EthiopianDate {
    return new EthiopianDate(this.year, 1, 1);
  }

  public get endOfYear(): EthiopianDate {
    return new EthiopianDate(this.year, 13, daysInEthiopianMonth(this.year, 13));
  }

  public monthDays(): EthiopianDate[] {
    const count = this.daysInMonth;
    return Array.from({ length: count }, (_, i) => new EthiopianDate(this.year, this.month, i + 1));
  }

  public toIsoString(): string {
    return `${String(this.year).padStart(4, '0')}-${String(this.month).padStart(2, '0')}-${String(this.day).padStart(2, '0')}`;
  }

  public toAmharicString(includeEra = true): string {
    const era = includeEra ? ' ዓ.ም.' : '';
    return `${this.amharicMonthName} ${this.day}, ${this.year}${era}`;
  }

  public toEnglishString(includeEra = true): string {
    const era = includeEra ? ' E.C.' : '';
    return `${this.englishMonthName} ${this.day}, ${this.year}${era}`;
  }

  public equals(other: EthiopianDate): boolean {
    return this.jdn === other.jdn;
  }

  public toString(): string {
    return this.toIsoString();
  }
}

export class CalendarDate {
  public readonly year: number;
  public readonly month: number; // 1..12
  public readonly day: number; // 1..31
  public readonly jdn: number;

  constructor(year: number, month: number, day: number, prevalidatedJdn?: number) {
    this.year = year;
    this.month = month;
    this.day = day;
    this.jdn = prevalidatedJdn !== undefined ? prevalidatedJdn : gregorianToJdn(year, month, day);
  }

  public static fromJdn(jdn: number): CalendarDate {
    const parts = jdnToGregorian(jdn);
    return new CalendarDate(parts.year, parts.month, parts.day, jdn);
  }

  public static fromEthiopian(year: number, month: number, day: number): CalendarDate {
    return new EthiopianDate(year, month, day).toCalendarDate();
  }

  public static today(): CalendarDate {
    return CalendarDate.fromUtcInstantInEthiopia(EthiopiaClock.nowUtc());
  }

  public static fromUtcInstantInEthiopia(instant: Date): CalendarDate {
    const wall = EthiopiaClock.toEthiopiaWallComponents(instant);
    return new CalendarDate(wall.year, wall.month, wall.day);
  }

  public static fromUtcComponents(date: Date): CalendarDate {
    return new CalendarDate(date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate());
  }

  public static parse(input: string): CalendarDate {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(input.trim());
    if (!match) {
      throw new Error(`Invalid canonical date string "${input}". Expected YYYY-MM-DD.`);
    }
    return new CalendarDate(
      parseInt(match[1], 10),
      parseInt(match[2], 10),
      parseInt(match[3], 10),
    );
  }

  public static tryParse(input?: string | null): CalendarDate | null {
    if (!input) return null;
    const trimmed = input.trim();
    if (!trimmed) return null;
    try {
      return CalendarDate.parse(trimmed);
    } catch {
      return null;
    }
  }

  public static isLeapYearFor(system: CalendarSystem, year: number): boolean {
    return system === 'ethiopian' ? isEthiopianLeapYear(year) : isGregorianLeapYear(year);
  }

  public static daysInMonthFor(system: CalendarSystem, year: number, month: number): number {
    return system === 'ethiopian'
      ? daysInEthiopianMonth(year, month)
      : daysInGregorianMonth(year, month);
  }

  public static daysInYearFor(system: CalendarSystem, year: number): number {
    return system === 'ethiopian' ? daysInEthiopianYear(year) : daysInGregorianYear(year);
  }

  public static monthDaysGrid(system: CalendarSystem, year: number, month: number): CalendarDate[] {
    const count = CalendarDate.daysInMonthFor(system, year, month);
    return system === 'ethiopian'
      ? Array.from({ length: count }, (_, i) => CalendarDate.fromEthiopian(year, month, i + 1))
      : Array.from({ length: count }, (_, i) => new CalendarDate(year, month, i + 1));
  }

  public static monthBounds(
    system: CalendarSystem,
    year: number,
    month: number,
  ): { start: CalendarDate; end: CalendarDate } {
    const lastDay = CalendarDate.daysInMonthFor(system, year, month);
    return system === 'ethiopian'
      ? {
          start: CalendarDate.fromEthiopian(year, month, 1),
          end: CalendarDate.fromEthiopian(year, month, lastDay),
        }
      : {
          start: new CalendarDate(year, month, 1),
          end: new CalendarDate(year, month, lastDay),
        };
  }

  public static yearBounds(
    system: CalendarSystem,
    year: number,
  ): { start: CalendarDate; end: CalendarDate } {
    return system === 'ethiopian'
      ? {
          start: CalendarDate.fromEthiopian(year, 1, 1),
          end: CalendarDate.fromEthiopian(year, 13, daysInEthiopianMonth(year, 13)),
        }
      : {
          start: new CalendarDate(year, 1, 1),
          end: new CalendarDate(year, 12, 31),
        };
  }

  public get weekday(): number {
    return weekdayFromJdn(this.jdn);
  }

  public get isGregorianLeapYear(): boolean {
    return isGregorianLeapYear(this.year);
  }

  public get daysInGregorianMonth(): number {
    return daysInGregorianMonth(this.year, this.month);
  }

  public get daysInGregorianYear(): number {
    return daysInGregorianYear(this.year);
  }

  public get gregorianShortMonthName(): string {
    return GREGORIAN_SHORT_MONTHS[this.month - 1];
  }

  public get gregorianFullMonthName(): string {
    return GREGORIAN_FULL_MONTHS[this.month - 1];
  }

  public get englishWeekdayName(): string {
    return WEEKDAY_ENGLISH_NAMES[this.weekday - 1];
  }

  public get shortEnglishWeekdayName(): string {
    return WEEKDAY_SHORT_ENGLISH_NAMES[this.weekday - 1];
  }

  public get amharicWeekdayName(): string {
    return WEEKDAY_AMHARIC_NAMES[this.weekday - 1];
  }

  public toEthiopian(): EthiopianDate {
    return EthiopianDate.fromJdn(this.jdn);
  }

  public toGregorianUtcMidnight(): Date {
    return new Date(Date.UTC(this.year, this.month - 1, this.day));
  }

  public toEthiopiaMidnightUtc(): Date {
    return EthiopiaClock.fromEthiopiaWallComponents(this.year, this.month, this.day);
  }

  public toIsoString(): string {
    return `${String(this.year).padStart(4, '0')}-${String(this.month).padStart(2, '0')}-${String(this.day).padStart(2, '0')}`;
  }

  public addDays(days: number): CalendarDate {
    return CalendarDate.fromJdn(this.jdn + days);
  }

  public subtractDays(days: number): CalendarDate {
    return CalendarDate.fromJdn(this.jdn - days);
  }

  public differenceInDays(other: CalendarDate): number {
    return this.jdn - other.jdn;
  }

  public isBefore(other: CalendarDate): boolean {
    return this.jdn < other.jdn;
  }

  public isAfter(other: CalendarDate): boolean {
    return this.jdn > other.jdn;
  }

  public isSameDay(other: CalendarDate): boolean {
    return this.jdn === other.jdn;
  }

  public isToday(): boolean {
    return this.jdn === CalendarDate.today().jdn;
  }

  public compareTo(other: CalendarDate): number {
    return this.jdn - other.jdn;
  }

  public nextGregorianMonth(): CalendarDate {
    const nextY = this.month === 12 ? this.year + 1 : this.year;
    const nextM = this.month === 12 ? 1 : this.month + 1;
    const maxD = daysInGregorianMonth(nextY, nextM);
    return new CalendarDate(nextY, nextM, Math.min(this.day, maxD));
  }

  public previousGregorianMonth(): CalendarDate {
    const prevY = this.month === 1 ? this.year - 1 : this.year;
    const prevM = this.month === 1 ? 12 : this.month - 1;
    const maxD = daysInGregorianMonth(prevY, prevM);
    return new CalendarDate(prevY, prevM, Math.min(this.day, maxD));
  }

  public nextGregorianYear(): CalendarDate {
    const nextY = this.year + 1;
    const maxD = daysInGregorianMonth(nextY, this.month);
    return new CalendarDate(nextY, this.month, Math.min(this.day, maxD));
  }

  public previousGregorianYear(): CalendarDate {
    const prevY = this.year - 1;
    const maxD = daysInGregorianMonth(prevY, this.month);
    return new CalendarDate(prevY, this.month, Math.min(this.day, maxD));
  }

  public get startOfGregorianMonth(): CalendarDate {
    return new CalendarDate(this.year, this.month, 1);
  }

  public get endOfGregorianMonth(): CalendarDate {
    return new CalendarDate(this.year, this.month, this.daysInGregorianMonth);
  }

  public get startOfGregorianYear(): CalendarDate {
    return new CalendarDate(this.year, 1, 1);
  }

  public get endOfGregorianYear(): CalendarDate {
    return new CalendarDate(this.year, 12, 31);
  }

  public gregorianMonthDays(): CalendarDate[] {
    return CalendarDate.monthDaysGrid('gregorian', this.year, this.month);
  }

  public nextEthiopianMonth(): CalendarDate {
    return this.toEthiopian().nextMonth().toCalendarDate();
  }

  public previousEthiopianMonth(): CalendarDate {
    return this.toEthiopian().previousMonth().toCalendarDate();
  }

  public nextEthiopianYear(): CalendarDate {
    return this.toEthiopian().nextYear().toCalendarDate();
  }

  public previousEthiopianYear(): CalendarDate {
    return this.toEthiopian().previousYear().toCalendarDate();
  }

  public get startOfEthiopianMonth(): CalendarDate {
    return this.toEthiopian().startOfMonth.toCalendarDate();
  }

  public get endOfEthiopianMonth(): CalendarDate {
    return this.toEthiopian().endOfMonth.toCalendarDate();
  }

  public get startOfEthiopianYear(): CalendarDate {
    return this.toEthiopian().startOfYear.toCalendarDate();
  }

  public get endOfEthiopianYear(): CalendarDate {
    return this.toEthiopian().endOfYear.toCalendarDate();
  }

  public ethiopianMonthDays(): CalendarDate[] {
    const eth = this.toEthiopian();
    return CalendarDate.monthDaysGrid('ethiopian', eth.year, eth.month);
  }

  public equals(other: CalendarDate): boolean {
    return this.jdn === other.jdn;
  }

  public toString(): string {
    return this.toIsoString();
  }
}

export class DayTimeOfDay {
  public readonly hour: number;
  public readonly minute: number;

  constructor(hour: number, minute: number) {
    if (!Number.isInteger(hour) || hour < 0 || hour > 23) {
      throw new RangeError(`Hour must be between 0 and 23 (got ${hour}).`);
    }
    if (!Number.isInteger(minute) || minute < 0 || minute > 59) {
      throw new RangeError(`Minute must be between 0 and 59 (got ${minute}).`);
    }
    this.hour = hour;
    this.minute = minute;
  }

  public static parse(input: string): DayTimeOfDay {
    const match = /^(\d{2}):(\d{2})$/.exec(input.trim());
    if (!match) {
      throw new Error(`Invalid time string "${input}". Expected HH:MM.`);
    }
    return new DayTimeOfDay(parseInt(match[1], 10), parseInt(match[2], 10));
  }

  public static tryParse(input?: string | null): DayTimeOfDay | null {
    if (!input || !input.trim()) return null;
    try {
      return DayTimeOfDay.parse(input);
    } catch {
      return null;
    }
  }

  public get totalMinutes(): number {
    return this.hour * 60 + this.minute;
  }

  public toIsoString(): string {
    return `${String(this.hour).padStart(2, '0')}:${String(this.minute).padStart(2, '0')}`;
  }

  public toDisplay12Hour(): string {
    const period = this.hour >= 12 ? 'PM' : 'AM';
    const h12 = this.hour % 12 === 0 ? 12 : this.hour % 12;
    return `${String(h12).padStart(2, '0')}:${String(this.minute).padStart(2, '0')} ${period}`;
  }

  public compareTo(other: DayTimeOfDay): number {
    return this.totalMinutes - other.totalMinutes;
  }

  public equals(other: DayTimeOfDay): boolean {
    return this.totalMinutes === other.totalMinutes;
  }

  public toString(): string {
    return this.toIsoString();
  }
}

export class LocalDateTime {
  public readonly date: CalendarDate;
  public readonly hour: number;
  public readonly minute: number;
  public readonly second: number;

  constructor(date: CalendarDate, hour = 0, minute = 0, second = 0) {
    if (!Number.isInteger(hour) || hour < 0 || hour > 23) {
      throw new RangeError(`Hour must be between 0 and 23 (got ${hour}).`);
    }
    if (!Number.isInteger(minute) || minute < 0 || minute > 59) {
      throw new RangeError(`Minute must be between 0 and 59 (got ${minute}).`);
    }
    if (!Number.isInteger(second) || second < 0 || second > 59) {
      throw new RangeError(`Second must be between 0 and 59 (got ${second}).`);
    }
    this.date = date;
    this.hour = hour;
    this.minute = minute;
    this.second = second;
  }

  public static now(): LocalDateTime {
    return LocalDateTime.fromUtcInstant(EthiopiaClock.nowUtc());
  }

  public static fromUtcInstant(instant: Date): LocalDateTime {
    const wall = EthiopiaClock.toEthiopiaWallComponents(instant);
    return new LocalDateTime(
      new CalendarDate(wall.year, wall.month, wall.day),
      wall.hour,
      wall.minute,
      wall.second,
    );
  }

  public static parse(input: string): LocalDateTime {
    const trimmed = input.trim();
    const dateOnly = CalendarDate.tryParse(trimmed);
    if (dateOnly) {
      return new LocalDateTime(dateOnly);
    }
    const match =
      /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(?:(Z)|([+-])(\d{2}):?(\d{2}))?$/i.exec(
        trimmed,
      );
    if (!match) {
      throw new Error(`Invalid timestamp "${input}".`);
    }

    const year = parseInt(match[1], 10);
    const month = parseInt(match[2], 10);
    const day = parseInt(match[3], 10);
    const hour = parseInt(match[4], 10);
    const minute = parseInt(match[5], 10);
    const second = match[6] ? parseInt(match[6], 10) : 0;

    // Strictly validate calendar & time fields BEFORE Date conversion so overflowing
    // dates (e.g. 2026-02-30T10:00:00Z) never silently roll forward to March.
    const validatedDate = new CalendarDate(year, month, day);
    if (hour < 0 || hour > 23) {
      throw new RangeError(`Hour must be between 0 and 23 (got ${hour}).`);
    }
    if (minute < 0 || minute > 59) {
      throw new RangeError(`Minute must be between 0 and 59 (got ${minute}).`);
    }
    if (second < 0 || second > 59) {
      throw new RangeError(`Second must be between 0 and 59 (got ${second}).`);
    }

    if (match[7]) {
      const utcMs = Date.UTC(year, month - 1, day, hour, minute, second);
      return LocalDateTime.fromUtcInstant(new Date(utcMs));
    }

    if (match[8] && match[9] && match[10]) {
      const sign = match[8] === '-' ? -1 : 1;
      const tzHour = parseInt(match[9], 10);
      const tzMinute = parseInt(match[10], 10);
      if (tzHour > 23 || tzMinute > 59) {
        throw new RangeError(`Invalid timezone offset in timestamp "${input}".`);
      }
      const offsetMs = sign * (tzHour * 60 + tzMinute) * 60 * 1000;
      const wallMs = Date.UTC(year, month - 1, day, hour, minute, second);
      return LocalDateTime.fromUtcInstant(new Date(wallMs - offsetMs));
    }

    return new LocalDateTime(validatedDate, hour, minute, second);
  }

  public static tryParse(input?: string | null): LocalDateTime | null {
    if (!input || !input.trim()) return null;
    try {
      return LocalDateTime.parse(input);
    } catch {
      return null;
    }
  }

  public get timeOfDay(): DayTimeOfDay {
    return new DayTimeOfDay(this.hour, this.minute);
  }

  public toUtcInstant(): Date {
    return EthiopiaClock.fromEthiopiaWallComponents(
      this.date.year,
      this.date.month,
      this.date.day,
      this.hour,
      this.minute,
      this.second,
    );
  }

  public toEthiopiaIsoString(): string {
    const h = String(this.hour).padStart(2, '0');
    const m = String(this.minute).padStart(2, '0');
    const s = String(this.second).padStart(2, '0');
    return `${this.date.toIsoString()}T${h}:${m}:${s}+03:00`;
  }

  public compareTo(other: LocalDateTime): number {
    return this.toUtcInstant().getTime() - other.toUtcInstant().getTime();
  }

  public equals(other: LocalDateTime): boolean {
    return (
      this.date.equals(other.date) &&
      this.hour === other.hour &&
      this.minute === other.minute &&
      this.second === other.second
    );
  }

  public toString(): string {
    return this.toEthiopiaIsoString();
  }
}

export class DateRange {
  public readonly start: CalendarDate;
  public readonly end: CalendarDate;

  constructor(start: CalendarDate, end: CalendarDate) {
    if (end.isBefore(start)) {
      throw new RangeError(
        `DateRange end (${end.toIsoString()}) cannot precede start (${start.toIsoString()}).`,
      );
    }
    this.start = start;
    this.end = end;
  }

  public static single(day: CalendarDate): DateRange {
    return new DateRange(day, day);
  }

  public static forMonth(system: CalendarSystem, year: number, month: number): DateRange {
    const bounds = CalendarDate.monthBounds(system, year, month);
    return new DateRange(bounds.start, bounds.end);
  }

  public static forYear(system: CalendarSystem, year: number): DateRange {
    const bounds = CalendarDate.yearBounds(system, year);
    return new DateRange(bounds.start, bounds.end);
  }

  public get lengthInDays(): number {
    return this.end.differenceInDays(this.start) + 1;
  }

  public contains(day: CalendarDate): boolean {
    return !day.isBefore(this.start) && !day.isAfter(this.end);
  }

  public overlaps(other: DateRange): boolean {
    return !this.end.isBefore(other.start) && !other.end.isBefore(this.start);
  }

  public days(): CalendarDate[] {
    return Array.from({ length: this.lengthInDays }, (_, i) => this.start.addDays(i));
  }

  public equals(other: DateRange): boolean {
    return this.start.equals(other.start) && this.end.equals(other.end);
  }

  public toString(): string {
    return `${this.start.toIsoString()}..${this.end.toIsoString()}`;
  }
}

export class SharedDateFormatter {
  public static formatGregorianShort(date: CalendarDate): string {
    return `${date.gregorianShortMonthName} ${String(date.day).padStart(2, '0')}, ${date.year}`;
  }

  public static formatGregorianLong(date: CalendarDate): string {
    return `${date.gregorianFullMonthName} ${date.day}, ${date.year}`;
  }

  public static formatEthiopian(
    date: EthiopianDate,
    options: { useAmharic?: boolean; includeEra?: boolean } = {},
  ): string {
    const useAmharic = options.useAmharic ?? true;
    const includeEra = options.includeEra ?? true;
    return useAmharic ? date.toAmharicString(includeEra) : date.toEnglishString(includeEra);
  }

  public static formatForSystem(
    date: CalendarDate,
    system: CalendarSystem,
    options: { useAmharic?: boolean; includeEra?: boolean } = {},
  ): string {
    if (system === 'ethiopian') {
      return SharedDateFormatter.formatEthiopian(date.toEthiopian(), options);
    }
    return SharedDateFormatter.formatGregorianShort(date);
  }

  public static formatDual(date: CalendarDate, useAmharic = true): string {
    const eth = date.toEthiopian();
    const ethStr = useAmharic ? eth.toAmharicString(false) : eth.toEnglishString(false);
    const gregStr = SharedDateFormatter.formatGregorianShort(date);
    return `${ethStr} (${gregStr})`;
  }

  public static formatDualFromInstant(instant: Date, useAmharic = true): string {
    return SharedDateFormatter.formatDual(CalendarDate.fromUtcInstantInEthiopia(instant), useAmharic);
  }

  public static formatEthiopiaTimestamp(instant: Date): string {
    const ldt = LocalDateTime.fromUtcInstant(instant);
    return `${ldt.date.toIsoString()} ${ldt.timeOfDay.toIsoString()} (${EthiopiaClock.TIME_ZONE_LABEL})`;
  }

  public static parseFlexibleToCalendarDate(input: string): CalendarDate {
    const trimmed = input.trim();
    const strict = CalendarDate.tryParse(trimmed);
    if (strict) return strict;

    const ldt = LocalDateTime.parse(trimmed);
    return ldt.date;
  }

  public static tryParseFlexibleToCalendarDate(input?: string | null): CalendarDate | null {
    if (!input || !input.trim()) return null;
    try {
      return SharedDateFormatter.parseFlexibleToCalendarDate(input);
    } catch {
      return null;
    }
  }
}
