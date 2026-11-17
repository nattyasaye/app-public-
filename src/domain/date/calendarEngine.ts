/**
 * Authoritative Julian Day Number (JDN) conversion and validation engine
 * mirrored 1:1 with `flutter_app/lib/core/date/calendar_engine.dart`.
 */

export const ETHIOPIAN_EPOCH_JDN = 1724221;

function positiveMod(value: number, divisor: number): number {
  const rem = value % divisor;
  return rem < 0 ? rem + divisor : rem;
}

export function isGregorianLeapYear(year: number): boolean {
  if (!Number.isInteger(year)) return false;
  if (year % 400 === 0) return true;
  if (year % 100 === 0) return false;
  return year % 4 === 0;
}

export function isEthiopianLeapYear(year: number): boolean {
  if (!Number.isInteger(year)) return false;
  return positiveMod(year, 4) === 3;
}

export function daysInGregorianMonth(year: number, month: number): number {
  if (!Number.isInteger(month) || month < 1 || month > 12) {
    throw new RangeError(`Gregorian month must be between 1 and 12 (got ${month}).`);
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

export function daysInGregorianYear(year: number): number {
  return isGregorianLeapYear(year) ? 366 : 365;
}

export function daysInEthiopianMonth(year: number, month: number): number {
  if (!Number.isInteger(year) || year < 1) {
    throw new RangeError(`Ethiopian year must be >= 1 (got ${year}).`);
  }
  if (!Number.isInteger(month) || month < 1 || month > 13) {
    throw new RangeError(`Ethiopian month must be between 1 and 13 (got ${month}).`);
  }
  if (month === 13) {
    return isEthiopianLeapYear(year) ? 6 : 5;
  }
  return 30;
}

export function daysInEthiopianYear(year: number): number {
  if (!Number.isInteger(year) || year < 1) {
    throw new RangeError(`Ethiopian year must be >= 1 (got ${year}).`);
  }
  return isEthiopianLeapYear(year) ? 366 : 365;
}

export function validateGregorian(year: number, month: number, day: number): void {
  if (!Number.isInteger(year) || year < 1 || year > 9999) {
    throw new RangeError(`Gregorian year must be between 1 and 9999 (got ${year}).`);
  }
  const maxDays = daysInGregorianMonth(year, month);
  if (!Number.isInteger(day) || day < 1 || day > maxDays) {
    throw new RangeError(
      `Invalid Gregorian day ${day} for ${year}-${String(month).padStart(2, '0')} (valid range: 1..${maxDays}).`,
    );
  }
}

export function validateEthiopian(year: number, month: number, day: number): void {
  if (!Number.isInteger(year) || year < 1 || year > 9999) {
    throw new RangeError(`Ethiopian year must be between 1 and 9999 (got ${year}).`);
  }
  const maxDays = daysInEthiopianMonth(year, month);
  if (!Number.isInteger(day) || day < 1 || day > maxDays) {
    throw new RangeError(
      `Invalid Ethiopian day ${day} for ${year}-${String(month).padStart(2, '0')} (valid range: 1..${maxDays}).`,
    );
  }
}

export function gregorianToJdn(year: number, month: number, day: number): number {
  validateGregorian(year, month, day);
  const a = Math.floor((14 - month) / 12);
  const y = year + 4800 - a;
  const m = month + 12 * a - 3;
  return (
    day +
    Math.floor((153 * m + 2) / 5) +
    365 * y +
    Math.floor(y / 4) -
    Math.floor(y / 100) +
    Math.floor(y / 400) -
    32045
  );
}

export function jdnToGregorian(jdn: number): { year: number; month: number; day: number } {
  if (!Number.isInteger(jdn)) {
    throw new RangeError(`Julian Day Number must be an integer (got ${jdn}).`);
  }
  const a = jdn + 32044;
  const b = Math.floor((4 * a + 3) / 146097);
  const c = a - Math.floor((146097 * b) / 4);
  const d = Math.floor((4 * c + 3) / 1461);
  const e = c - Math.floor((1461 * d) / 4);
  const m = Math.floor((5 * e + 2) / 153);

  const day = e - Math.floor((153 * m + 2) / 5) + 1;
  const month = m + 3 - 12 * Math.floor(m / 10);
  const year = 100 * b + d - 4800 + Math.floor(m / 10);

  if (year < 1 || year > 9999) {
    throw new RangeError(`Julian Day Number ${jdn} resolves outside supported Gregorian range 0001..9999 (got year ${year}).`);
  }
  return { year, month, day };
}

export function ethiopianToJdn(year: number, month: number, day: number): number {
  validateEthiopian(year, month, day);
  const y0 = year - 1;
  const leapDays = Math.floor((y0 + 1) / 4);
  return ETHIOPIAN_EPOCH_JDN + 365 * y0 + leapDays + (month - 1) * 30 + (day - 1);
}

export function jdnToEthiopian(jdn: number): { year: number; month: number; day: number } {
  if (!Number.isInteger(jdn)) {
    throw new RangeError(`Julian Day Number must be an integer (got ${jdn}).`);
  }
  if (jdn < ETHIOPIAN_EPOCH_JDN) {
    throw new RangeError(
      `Julian Day Number ${jdn} precedes Meskerem 1, 1 E.C. (${ETHIOPIAN_EPOCH_JDN}).`,
    );
  }
  const days = jdn - ETHIOPIAN_EPOCH_JDN;
  let y0 = Math.floor((4 * days) / 1461);

  while (days < 365 * y0 + Math.floor((y0 + 1) / 4)) {
    y0--;
  }
  while (days >= 365 * (y0 + 1) + Math.floor((y0 + 2) / 4)) {
    y0++;
  }

  const year = y0 + 1;
  const dayOfYear = days - (365 * y0 + Math.floor((y0 + 1) / 4));
  let month = Math.floor(dayOfYear / 30) + 1;
  const day = (dayOfYear % 30) + 1;
  if (month > 13) {
    month = 13;
  }
  return { year, month, day };
}

/**
 * ISO-8601 weekday (1 = Monday .. 7 = Sunday) from Julian Day Number.
 */
export function weekdayFromJdn(jdn: number): number {
  return positiveMod(jdn, 7) + 1;
}
