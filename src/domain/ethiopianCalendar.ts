import {
  CalendarDate,
  ETHIOPIAN_AMHARIC_MONTHS,
  ETHIOPIAN_ENGLISH_MONTHS,
  EthiopianDate,
  SharedDateFormatter,
  ethiopianToJdn as engineEthiopianToJdn,
  gregorianToJdn as engineGregorianToJdn,
  isEthiopianLeapYear,
  jdnToEthiopian as engineJdnToEthiopian,
  jdnToGregorian as engineJdnToGregorian,
} from './date';

export interface EthiopianDateObj {
  year: number;
  month: number; // 1 to 13
  day: number; // 1 to 30 (1 to 5 or 6 for Pagume)
  amharicMonth: string;
  englishMonth: string;
  isLeapYear: boolean;
  daysInMonth: number;
}

export const AMHARIC_MONTHS = [...ETHIOPIAN_AMHARIC_MONTHS];
export const ENGLISH_MONTHS = [...ETHIOPIAN_ENGLISH_MONTHS];

export function gregorianToJdn(year: number, month: number, day: number): number {
  return engineGregorianToJdn(year, month, day);
}

export function jdnToGregorian(jdn: number): { year: number; month: number; day: number } {
  return engineJdnToGregorian(jdn);
}

function toObj(eth: EthiopianDate): EthiopianDateObj {
  return {
    year: eth.year,
    month: eth.month,
    day: eth.day,
    amharicMonth: eth.amharicMonthName,
    englishMonth: eth.englishMonthName,
    isLeapYear: isEthiopianLeapYear(eth.year),
    daysInMonth: eth.daysInMonth,
  };
}

export function jdnToEthiopian(jdn: number): EthiopianDateObj {
  return toObj(EthiopianDate.fromJdn(jdn));
}

export function ethiopianToJdn(year: number, month: number, day: number): number {
  return engineEthiopianToJdn(year, month, day);
}

export function fromGregorianDate(date: Date): EthiopianDateObj {
  const { year, month, day } = {
    year: date.getUTCFullYear(),
    month: date.getUTCMonth() + 1,
    day: date.getUTCDate(),
  };
  const parts = engineJdnToGregorian(engineGregorianToJdn(year, month, day));
  return toObj(new CalendarDate(parts.year, parts.month, parts.day).toEthiopian());
}

export function fromEthiopiaInstant(instant: Date): EthiopianDateObj {
  return toObj(CalendarDate.fromUtcInstantInEthiopia(instant).toEthiopian());
}

export function toGregorianDate(year: number, month: number, day: number): Date {
  return new EthiopianDate(year, month, day).toGregorianUtcDate();
}

export function formatDualDate(date: Date): string {
  const calendarDate = CalendarDate.fromUtcComponents(date);
  return SharedDateFormatter.formatDual(calendarDate, true);
}
