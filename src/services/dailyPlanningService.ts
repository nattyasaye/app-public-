import { normalizeDailyPlanningEntriesList } from '../domain/dailyPlanningOperations';
import { SharedDailyPlanningEntry } from '../domain/sharedFoundation';
import { SharedStateBridge } from './sharedStateBridge';

function dispatchSync(entries: readonly SharedDailyPlanningEntry[]): void {
  if (typeof window === 'undefined') return;
  window.dispatchEvent(
    new CustomEvent(SharedStateBridge.SYNC_EVENT_NAME, {
      detail: { dailyPlanningEntries: entries },
    })
  );
}

export const dailyPlanningService = {
  loadDailyPlanningEntries(): SharedDailyPlanningEntry[] {
    if (typeof localStorage === 'undefined') return [];
    try {
      const raw = localStorage.getItem(
        SharedStateBridge.DAILY_PLANNING_STORAGE_KEY
      );
      if (raw !== null) {
        const parsed = JSON.parse(raw);
        return normalizeDailyPlanningEntriesList(
          Array.isArray(parsed) ? parsed : []
        );
      }

      const canonicalRaw = localStorage.getItem('daywell_canonical_database_v3');
      if (!canonicalRaw) return [];
      const canonical = JSON.parse(canonicalRaw);
      if (canonical && Array.isArray(canonical.dailyPlanningEntries)) {
        return normalizeDailyPlanningEntriesList(
          canonical.dailyPlanningEntries
        );
      }
      return [];
    } catch {
      return [];
    }
  },

  saveDailyPlanningEntries(
    entries: readonly SharedDailyPlanningEntry[]
  ): SharedDailyPlanningEntry[] {
    const normalized = normalizeDailyPlanningEntriesList(entries);
    if (typeof localStorage !== 'undefined') {
      try {
        localStorage.setItem(
          SharedStateBridge.DAILY_PLANNING_STORAGE_KEY,
          JSON.stringify(normalized)
        );
      } catch (err) {
        console.error(
          '[dailyPlanningService] Failed to save daily planning entries:',
          err
        );
      }
    }
    dispatchSync(normalized);
    return normalized;
  },
};
