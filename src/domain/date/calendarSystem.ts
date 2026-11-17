/**
 * Supported first-class civil calendar systems in Daywell.
 */
export type CalendarSystem = 'ethiopian' | 'gregorian';

export interface WallClockComponents {
  year: number;
  month: number; // 1..12
  day: number; // 1..31
  hour: number; // 0..23
  minute: number; // 0..59
  second: number; // 0..59
}

/**
 * Fixed application-wide time convention for Daywell: Ethiopia local civil
 * time (UTC+3 / East Africa Time, no daylight saving time).
 *
 * Daywell intentionally excludes multi-timezone runtime abstractions, user
 * timezone selection, and travel offset logic.
 */
export class EthiopiaClock {
  public static readonly UTC_OFFSET_HOURS = 3;
  public static readonly UTC_OFFSET_MINUTES = 180;
  public static readonly UTC_OFFSET_MS = 3 * 60 * 60 * 1000;
  public static readonly TIME_ZONE_LABEL = 'UTC+3';

  private static _utcNowProvider: () => Date = () => new Date();

  /**
   * Overrides the underlying UTC clock source for deterministic testing.
   */
  public static setClockForTesting(provider: (() => Date) | null): void {
    EthiopiaClock._utcNowProvider = provider ?? (() => new Date());
  }

  /**
   * Returns the current instant as a JS Date.
   */
  public static nowUtc(): Date {
    return new Date(EthiopiaClock._utcNowProvider().getTime());
  }

  /**
   * Converts any instant into Ethiopia UTC+3 civil wall-clock components.
   */
  public static toEthiopiaWallComponents(instant: Date): WallClockComponents {
    const shifted = new Date(instant.getTime() + EthiopiaClock.UTC_OFFSET_MS);
    return {
      year: shifted.getUTCFullYear(),
      month: shifted.getUTCMonth() + 1,
      day: shifted.getUTCDate(),
      hour: shifted.getUTCHours(),
      minute: shifted.getUTCMinutes(),
      second: shifted.getUTCSeconds(),
    };
  }

  /**
   * Converts Ethiopia UTC+3 wall-clock components to a true UTC JS Date instant.
   */
  public static fromEthiopiaWallComponents(
    year: number,
    month: number,
    day: number,
    hour = 0,
    minute = 0,
    second = 0,
  ): Date {
    const wallUtcMs = Date.UTC(year, month - 1, day, hour, minute, second);
    return new Date(wallUtcMs - EthiopiaClock.UTC_OFFSET_MS);
  }
}
