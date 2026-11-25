import { EthiopiaClock } from './date';
import {
  compareNotes,
  isNoteTrashed,
  matchesNoteSearchQuery,
  MAX_NOTE_TITLE_LENGTH,
  normalizeNoteTitle,
  normalizeWebNoteNotebook,
} from './noteHelpers';
import { markdownToPlainText } from './noteMarkdown';
import { NoteLinkedModule, TaskNoteRecord } from './taskNotes';

export { MAX_NOTE_TITLE_LENGTH };

export interface CalendarEventNoteTarget {
  id: string;
  title: string;
  date: string;
  endDate?: string;
  startTime?: string;
  endTime?: string;
  isAllDay?: boolean;
  category?: string;
  location?: string;
}

export interface AvailableCalendarEventNoteOption<
  T extends TaskNoteRecord = TaskNoteRecord,
> {
  note: T;
  linkedEventId?: string;
  linkedTaskId?: string;
  isLinkedToOtherModule: boolean;
  hasExistingPrimaryLink: boolean;
}

export interface CalendarNoteLinkMutationResult<
  T extends TaskNoteRecord = TaskNoteRecord,
> {
  ok: boolean;
  notes: T[];
  updatedNote?: T;
  previousLinkedModule?: NoteLinkedModule;
  previousLinkedId?: string;
  error?: string;
}

export interface CreateNoteForCalendarEventResult<
  T extends TaskNoteRecord = TaskNoteRecord,
> {
  ok: boolean;
  notes: T[];
  note?: T;
  error?: string;
}

export interface UnlinkDeletedCalendarEventNotesResult<
  T extends TaskNoteRecord = TaskNoteRecord,
> {
  notes: T[];
  unlinkedCount: number;
  unlinkedNoteIds: string[];
}

export function buildBoundedCalendarEventNoteTitle(
  rawTitle?: string | null
): string {
  return normalizeNoteTitle(rawTitle, { fallbackTitle: 'Event Note' });
}

export function getCalendarEventNotePreview(
  content: string,
  maxLength = 140
): string {
  const plain = markdownToPlainText(content).replace(/\s+/g, ' ').trim();
  if (!plain) return '';
  if (plain.length <= maxLength) return plain;
  return `${plain.slice(0, Math.max(1, maxLength - 1)).trimEnd()}…`;
}

export function isNoteLinkedToCalendarEvent(
  note: Pick<TaskNoteRecord, 'linkedModule' | 'linkedId' | 'isTrashed'>,
  eventId: string
): boolean {
  const cleanEventId = eventId.trim();
  if (!cleanEventId || isNoteTrashed(note)) return false;
  return note.linkedModule === 'calendar' && note.linkedId === cleanEventId;
}

export function getNotesLinkedToCalendarEvent<T extends TaskNoteRecord>(
  notes: readonly T[],
  eventId: string,
  options?: {
    includeArchived?: boolean;
    includeTrashed?: boolean;
  }
): T[] {
  const cleanEventId = eventId.trim();
  if (!cleanEventId) return [];
  const includeArchived = options?.includeArchived ?? true;
  const includeTrashed = options?.includeTrashed ?? false;

  return notes
    .filter((note) => {
      if (!includeTrashed && isNoteTrashed(note)) return false;
      if (note.linkedModule !== 'calendar' || note.linkedId !== cleanEventId) {
        return false;
      }
      if (!includeArchived && note.isArchived && !isNoteTrashed(note)) {
        return false;
      }
      return true;
    })
    .slice()
    .sort((a, b) => {
      const aArchived = Boolean(a.isArchived);
      const bArchived = Boolean(b.isArchived);
      if (aArchived !== bArchived) return aArchived ? 1 : -1;
      return compareNotes(a, b, { sortBy: 'recent', pinFirst: true });
    });
}

export function countNotesLinkedToCalendarEvent(
  notes: readonly TaskNoteRecord[],
  eventId: string,
  options?: { includeArchived?: boolean }
): number {
  return getNotesLinkedToCalendarEvent(notes, eventId, {
    includeArchived: options?.includeArchived ?? true,
    includeTrashed: false,
  }).length;
}

export function getLinkedCalendarEventForNote<
  TEvent extends Pick<CalendarEventNoteTarget, 'id'>,
>(
  note: Pick<TaskNoteRecord, 'linkedModule' | 'linkedId'>,
  events: readonly TEvent[]
): TEvent | null {
  if (note.linkedModule !== 'calendar') return null;
  const cleanId = (note.linkedId ?? '').trim();
  if (!cleanId) return null;
  return events.find((e) => e.id === cleanId) ?? null;
}

export function buildCalendarEventTitlesById(
  events: readonly Pick<CalendarEventNoteTarget, 'id' | 'title'>[]
): Map<string, string> {
  const map = new Map<string, string>();
  for (const ev of events) {
    const cleanId = ev.id.trim();
    const cleanTitle = ev.title.trim();
    if (cleanId && cleanTitle) {
      map.set(cleanId, cleanTitle);
    }
  }
  return map;
}

export function getAvailableNotesToLinkToCalendarEvent<
  T extends TaskNoteRecord,
>(
  notes: readonly T[],
  eventId: string,
  searchQuery = ''
): AvailableCalendarEventNoteOption<T>[] {
  const cleanEventId = eventId.trim();
  const q = searchQuery.trim().toLowerCase();

  return notes
    .filter((note) => {
      if (isNoteTrashed(note)) return false;
      if (isNoteLinkedToCalendarEvent(note, cleanEventId)) return false;
      if (!q) return true;
      return matchesNoteSearchQuery(note, q);
    })
    .slice()
    .sort((a, b) => {
      const aHasLink = Boolean(a.linkedModule && a.linkedId);
      const bHasLink = Boolean(b.linkedModule && b.linkedId);
      if (aHasLink !== bHasLink) return aHasLink ? 1 : -1;
      if (a.isArchived !== b.isArchived) return a.isArchived ? 1 : -1;
      return b.updatedAt.localeCompare(a.updatedAt);
    })
    .map((note) => {
      const hasPrimaryLink = Boolean(note.linkedModule && note.linkedId);
      return {
        note,
        linkedEventId:
          note.linkedModule === 'calendar' && note.linkedId
            ? note.linkedId
            : undefined,
        linkedTaskId:
          note.linkedModule === 'tasks' && note.linkedId
            ? note.linkedId
            : undefined,
        isLinkedToOtherModule: Boolean(
          note.linkedModule && note.linkedModule !== 'calendar' && note.linkedId
        ),
        hasExistingPrimaryLink: hasPrimaryLink,
      };
    });
}

export function linkNoteToCalendarEvent<T extends TaskNoteRecord>(
  notes: readonly T[],
  noteId: string,
  eventId: string,
  nowUtc?: Date,
  options?: { allowReassign?: boolean }
): CalendarNoteLinkMutationResult<T> {
  const cleanNoteId = noteId.trim();
  const cleanEventId = eventId.trim();
  if (!cleanNoteId || !cleanEventId) {
    return {
      ok: false,
      notes: [...notes],
      error: 'Note ID and Calendar event ID are required to create a link.',
    };
  }

  const target = notes.find((n) => n.id === cleanNoteId);
  if (!target) {
    return {
      ok: false,
      notes: [...notes],
      error: 'Selected note was not found.',
    };
  }

  if (isNoteTrashed(target)) {
    return {
      ok: false,
      notes: [...notes],
      error: 'Restore note from Trash before linking it to a Calendar event.',
    };
  }

  if (target.linkedModule === 'calendar' && target.linkedId === cleanEventId) {
    return {
      ok: true,
      notes: [...notes],
      updatedNote: target,
      previousLinkedModule: target.linkedModule,
      previousLinkedId: target.linkedId,
    };
  }

  const hasConflictingPrimaryLink = Boolean(
    target.linkedModule &&
      target.linkedId &&
      !(target.linkedModule === 'calendar' && target.linkedId === cleanEventId)
  );
  if (hasConflictingPrimaryLink && options?.allowReassign !== true) {
    return {
      ok: false,
      notes: [...notes],
      error:
        target.linkedModule === 'tasks'
          ? 'This note is already linked to a task. Confirm link replacement or unlink the task first.'
          : target.linkedModule === 'calendar'
            ? 'This note is already linked to another Calendar event. Confirm link replacement first.'
            : `This note is already linked to ${target.linkedModule}. Confirm link replacement first.`,
    };
  }

  const updatedIso = (nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const updatedNote: T = {
    ...target,
    linkedModule: 'calendar',
    linkedId: cleanEventId,
    updatedAt: updatedIso,
  };

  return {
    ok: true,
    notes: notes.map((n) => (n.id === cleanNoteId ? updatedNote : n)),
    updatedNote,
    previousLinkedModule: target.linkedModule,
    previousLinkedId: target.linkedId,
  };
}

export function undoCalendarEventNoteLink<T extends TaskNoteRecord>(params: {
  notes: readonly T[];
  noteId: string;
  appliedEventId: string;
  previousLinkedModule?: NoteLinkedModule;
  previousLinkedId?: string;
  previousTargetExists?: boolean;
  nowUtc?: Date;
}): CalendarNoteLinkMutationResult<T> {
  const cleanNoteId = params.noteId.trim();
  const cleanAppliedEventId = params.appliedEventId.trim();
  if (!cleanNoteId || !cleanAppliedEventId) {
    return {
      ok: false,
      notes: [...params.notes],
      error: 'Undo skipped: invalid note or Calendar event identifier.',
    };
  }

  const target = params.notes.find((n) => n.id === cleanNoteId);
  if (!target || isNoteTrashed(target)) {
    return {
      ok: false,
      notes: [...params.notes],
      error: 'Undo skipped: note is no longer available.',
    };
  }

  if (
    target.linkedModule !== 'calendar' ||
    target.linkedId !== cleanAppliedEventId
  ) {
    return {
      ok: false,
      notes: [...params.notes],
      error: 'Undo skipped: note relationship changed.',
    };
  }

  const hasPreviousPair = Boolean(
    params.previousLinkedModule &&
      params.previousLinkedId &&
      params.previousLinkedId.trim().length > 0
  );
  if (hasPreviousPair && params.previousTargetExists === false) {
    return {
      ok: false,
      notes: [...params.notes],
      error: 'Undo skipped: previous linked target is no longer available.',
    };
  }

  const updatedIso = (params.nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const { linkedModule: _lm, linkedId: _li, ...rest } = target;
  const updatedNote = (
    hasPreviousPair
      ? {
          ...rest,
          linkedModule: params.previousLinkedModule,
          linkedId: params.previousLinkedId!.trim(),
          updatedAt: updatedIso,
        }
      : {
          ...rest,
          updatedAt: updatedIso,
        }
  ) as T;

  return {
    ok: true,
    notes: params.notes.map((n) => (n.id === cleanNoteId ? updatedNote : n)),
    updatedNote,
    previousLinkedModule: target.linkedModule,
    previousLinkedId: target.linkedId,
  };
}

export function unlinkNoteFromCalendarEvent<T extends TaskNoteRecord>(
  notes: readonly T[],
  noteId: string,
  expectedEventId?: string,
  nowUtc?: Date
): CalendarNoteLinkMutationResult<T> {
  const cleanNoteId = noteId.trim();
  if (!cleanNoteId) {
    return {
      ok: false,
      notes: [...notes],
      error: 'Note ID is required to unlink.',
    };
  }

  const target = notes.find((n) => n.id === cleanNoteId);
  if (!target) {
    return {
      ok: false,
      notes: [...notes],
      error: 'Selected note was not found.',
    };
  }

  if (target.linkedModule !== 'calendar') {
    return {
      ok: false,
      notes: [...notes],
      error: 'This note is not linked to a Calendar event.',
    };
  }

  if (expectedEventId && target.linkedId !== expectedEventId.trim()) {
    return {
      ok: false,
      notes: [...notes],
      error: 'This note is linked to a different Calendar event.',
    };
  }

  const updatedIso = (nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const { linkedModule: prevMod, linkedId: prevId, ...rest } = target;
  const updatedNote = {
    ...rest,
    updatedAt: updatedIso,
  } as T;

  return {
    ok: true,
    notes: notes.map((n) => (n.id === cleanNoteId ? updatedNote : n)),
    updatedNote,
    previousLinkedModule: prevMod,
    previousLinkedId: prevId,
  };
}

export function unlinkNotesForDeletedCalendarEvent<T extends TaskNoteRecord>(
  notes: readonly T[],
  deletedEventId: string,
  nowUtc?: Date
): UnlinkDeletedCalendarEventNotesResult<T> {
  const cleanEventId = deletedEventId.trim();
  if (!cleanEventId) {
    return { notes: [...notes], unlinkedCount: 0, unlinkedNoteIds: [] };
  }

  const updatedIso = (nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const unlinkedNoteIds: string[] = [];

  const next = notes.map((note) => {
    if (note.linkedModule === 'calendar' && note.linkedId === cleanEventId) {
      unlinkedNoteIds.push(note.id);
      const { linkedModule: _lm, linkedId: _li, ...rest } = note;
      return {
        ...rest,
        updatedAt: updatedIso,
      } as T;
    }
    return note;
  });

  return {
    notes: next,
    unlinkedCount: unlinkedNoteIds.length,
    unlinkedNoteIds,
  };
}

export function createNoteForCalendarEvent<
  T extends TaskNoteRecord = TaskNoteRecord,
>(params: {
  notes: readonly T[];
  event: Pick<CalendarEventNoteTarget, 'id' | 'title'>;
  id?: string;
  title?: string;
  content?: string;
  notebook?: string;
  nowUtc?: Date;
}): CreateNoteForCalendarEventResult<T> {
  const cleanEventId = params.event.id.trim();
  if (!cleanEventId) {
    return {
      ok: false,
      notes: [...params.notes],
      error: 'Event ID is required to create a linked note.',
    };
  }

  const now = params.nowUtc ?? EthiopiaClock.nowUtc();
  const nowIso = now.toISOString();
  const existingIds = new Set(params.notes.map((n) => n.id));
  let noteId = params.id?.trim() || `note-${now.getTime()}`;
  if (existingIds.has(noteId)) {
    let suffix = 2;
    const base = noteId;
    while (existingIds.has(`${base}-${suffix}`)) {
      suffix += 1;
    }
    noteId = `${base}-${suffix}`;
  }

  const notebook = normalizeWebNoteNotebook(params.notebook);
  const defaultTitle = params.event.title.trim()
    ? `${params.event.title.trim()} — Notes`
    : 'Event Note';
  const noteTitle = buildBoundedCalendarEventNoteTitle(
    params.title !== undefined && params.title.trim().length > 0
      ? params.title
      : defaultTitle
  );

  const created = {
    id: noteId,
    title: noteTitle,
    content: params.content ?? '',
    notebook,
    tags: [],
    isPinned: false,
    isFavorite: false,
    isArchived: false,
    isTrashed: false,
    linkedModule: 'calendar',
    linkedId: cleanEventId,
    createdAt: nowIso,
    updatedAt: nowIso,
  } as unknown as T;

  return {
    ok: true,
    notes: [created, ...params.notes],
    note: created,
  };
}
