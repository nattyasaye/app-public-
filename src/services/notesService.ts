import { normalizeTaskNoteRecord, TaskNoteRecord } from '../domain/taskNotes';
import { SharedStateBridge } from './sharedStateBridge';

const NOTES_STORAGE_KEY = 'daywell_notes';

function dedupeNotesById<T extends TaskNoteRecord>(items: readonly T[]): T[] {
  const seen = new Set<string>();
  const out: T[] = [];
  for (const item of items) {
    if (!seen.has(item.id)) {
      seen.add(item.id);
      out.push(item);
    }
  }
  return out;
}

function dispatchNotesSync(notes: readonly TaskNoteRecord[]): void {
  if (typeof window === 'undefined') return;
  window.dispatchEvent(
    new CustomEvent(SharedStateBridge.SYNC_EVENT_NAME, {
      detail: { notes },
    })
  );
}

export const notesService = {
  loadNotes(): TaskNoteRecord[] {
    if (typeof localStorage === 'undefined') return [];
    try {
      const raw = localStorage.getItem(NOTES_STORAGE_KEY);
      if (!raw) return [];
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) return [];
      const normalized = parsed
        .map((entry) => normalizeTaskNoteRecord(entry))
        .filter((entry): entry is TaskNoteRecord => entry !== null);
      return dedupeNotesById(normalized);
    } catch {
      return [];
    }
  },

  saveNotes(
    notes: readonly TaskNoteRecord[],
    options?: { emitSync?: boolean }
  ): TaskNoteRecord[] {
    const normalized = dedupeNotesById(
      notes
        .map((entry) => normalizeTaskNoteRecord(entry))
        .filter((entry): entry is TaskNoteRecord => entry !== null)
    );
    if (typeof localStorage !== 'undefined') {
      try {
        localStorage.setItem(NOTES_STORAGE_KEY, JSON.stringify(normalized));
      } catch (err) {
        console.error('[notesService] Failed to save notes:', err);
      }
    }
    if (options?.emitSync !== false) {
      dispatchNotesSync(normalized);
    }
    return normalized;
  },
};
