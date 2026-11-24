import {
  DailyRhythmDayRecord,
  normalizeDailyRhythmDay,
  normalizeDailyRhythmTimeline,
} from '../domain/dailyRhythm';
import { CalendarDate } from '../domain/date';
import { SharedStateBridge } from './sharedStateBridge';

function dispatchSync(days: readonly DailyRhythmDayRecord[]): void {
  if (typeof window === 'undefined') return;
  window.dispatchEvent(
    new CustomEvent(SharedStateBridge.SYNC_EVENT_NAME, {
      detail: { dailyRhythmDays: days },
    })
  );
}

export const dailyRhythmService = {
  loadDays(): DailyRhythmDayRecord[] {
    if (typeof localStorage === 'undefined') return [];
    try {
      const raw = localStorage.getItem(SharedStateBridge.DAILY_RHYTHM_STORAGE_KEY);
      if (raw !== null) {
        const parsed = JSON.parse(raw);
        return Array.isArray(parsed) ? normalizeDailyRhythmTimeline(parsed) : [];
      }

      const canonicalRaw = localStorage.getItem(SharedStateBridge.STORAGE_KEY);
      if (!canonicalRaw) return [];
      const canonical = JSON.parse(canonicalRaw);
      if (canonical && Array.isArray(canonical.dailyRhythmDays)) {
        return normalizeDailyRhythmTimeline(canonical.dailyRhythmDays);
      }
      return [];
    } catch {
      return [];
    }
  },

  getDay(dateIso: string): DailyRhythmDayRecord | null {
    const parsedDate = CalendarDate.tryParse(dateIso);
    if (!parsedDate) return null;
    const canonicalDate = parsedDate.toIsoString();
    return this.loadDays().find((day) => day.dateIso === canonicalDate) ?? null;
  },

  listDays(options?: {
    fromDateIso?: string;
    toDateIso?: string;
  }): DailyRhythmDayRecord[] {
    const fromKey =
      options?.fromDateIso !== undefined
        ? CalendarDate.parse(options.fromDateIso).toIsoString()
        : undefined;
    const toKey =
      options?.toDateIso !== undefined
        ? CalendarDate.parse(options.toDateIso).toIsoString()
        : undefined;

    return this.loadDays().filter((day) => {
      if (fromKey !== undefined && day.dateIso < fromKey) return false;
      if (toKey !== undefined && day.dateIso > toKey) return false;
      return true;
    });
  },

  saveDays(days: readonly DailyRhythmDayRecord[]): DailyRhythmDayRecord[] {
    const normalized = normalizeDailyRhythmTimeline(days);
    if (typeof localStorage !== 'undefined') {
      try {
        localStorage.setItem(
          SharedStateBridge.DAILY_RHYTHM_STORAGE_KEY,
          JSON.stringify(normalized)
        );
      } catch (err) {
        console.error('[dailyRhythmService] Failed to save Daily Rhythm days:', err);
      }
    }
    dispatchSync(normalized);
    return normalized;
  },

  upsertDay(day: DailyRhythmDayRecord): DailyRhythmDayRecord {
    const normalized = normalizeDailyRhythmDay(day);
    if (!normalized) {
      throw new Error(`Invalid Daily Rhythm day record: dateIso="${day?.dateIso ?? ''}".`);
    }
    const existing = this.loadDays().filter(
      (item) => item.dateIso !== normalized.dateIso
    );
    const saved = this.saveDays([...existing, normalized]);
    return (
      saved.find((item) => item.dateIso === normalized.dateIso) ?? normalized
    );
  },

  deleteDay(dateIso: string): boolean {
    const parsedDate = CalendarDate.tryParse(dateIso);
    if (!parsedDate) return false;
    const canonicalDate = parsedDate.toIsoString();
    const existing = this.loadDays();
    const filtered = existing.filter((day) => day.dateIso !== canonicalDate);
    if (filtered.length === existing.length) return false;
    this.saveDays(filtered);
    return true;
  },
};
