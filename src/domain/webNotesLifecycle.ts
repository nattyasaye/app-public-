import { EthiopiaClock } from './date';
import {
  DEFAULT_NOTE_TITLE,
  isNoteActive,
  isNoteArchived,
  isNoteFavoriteActive,
  isNotePinnedActive,
  isNoteTrashed,
  normalizeNoteLinkPair,
  normalizeNoteTags,
  normalizeNoteTitle,
  normalizeWebNoteNotebook,
  NoteSortMode,
  sortNotes,
} from './noteHelpers';
import { TaskNoteRecord } from './taskNotes';

export type WebNotesFilterTab =
  | 'all'
  | 'pinned'
  | 'favorites'
  | 'archived'
  | 'trash'
  | (string & {});

export const DEFAULT_WEB_NOTEBOOKS: readonly string[] = [
  'Personal',
  'Work',
  'Reflections',
  'Finances',
];

export const RESERVED_NOTE_FILTER_TABS: ReadonlySet<string> = new Set([
  'all',
  'pinned',
  'favorites',
  'archived',
  'trash',
]);

export interface WebNoteCounts {
  active: number;
  pinned: number;
  favorites: number;
  archived: number;
  trash: number;
}

export interface WebNoteLifecycleMutationResult<
  T extends TaskNoteRecord = TaskNoteRecord,
> {
  ok: boolean;
  notes: T[];
  updatedNote?: T;
  removedNote?: T;
  error?: string;
}

export interface SaveWebNoteDraftResult<
  T extends TaskNoteRecord = TaskNoteRecord,
> {
  status: 'discarded_empty' | 'unchanged' | 'created' | 'updated';
  notes: T[];
  note?: T;
}

export function resolveDefaultNotebookForTab(activeTab: string): string {
  const trimmed = activeTab.trim();
  if (!trimmed || RESERVED_NOTE_FILTER_TABS.has(trimmed)) {
    return normalizeWebNoteNotebook(undefined);
  }
  return normalizeWebNoteNotebook(trimmed);
}

export function getDisplayNoteTitle(rawTitle: string | null | undefined): string {
  const trimmed = typeof rawTitle === 'string' ? rawTitle.trim() : '';
  return trimmed.length > 0 ? trimmed : DEFAULT_NOTE_TITLE;
}

export function isNoteDraftBlank(draft: {
  title?: string | null;
  content?: string | null;
  tags?: readonly string[] | null;
}): boolean {
  const hasTitle = typeof draft.title === 'string' && draft.title.trim().length > 0;
  const hasContent =
    typeof draft.content === 'string' && draft.content.trim().length > 0;
  const hasTags = Array.isArray(draft.tags) && normalizeNoteTags(draft.tags).length > 0;
  return !hasTitle && !hasContent && !hasTags;
}

export function generateUniqueNoteId(
  existingNotes: readonly Pick<TaskNoteRecord, 'id'>[],
  nowUtc?: Date
): string {
  const now = nowUtc ?? EthiopiaClock.nowUtc();
  const existingIds = new Set(existingNotes.map((n) => n.id));
  const baseId = `note-${now.getTime()}`;
  if (!existingIds.has(baseId)) {
    return baseId;
  }
  let suffix = 2;
  while (existingIds.has(`${baseId}-${suffix}`)) {
    suffix += 1;
  }
  return `${baseId}-${suffix}`;
}

export function createWebNoteRecord<T extends TaskNoteRecord = TaskNoteRecord>(params: {
  existingNotes: readonly T[];
  id?: string;
  title?: string | null;
  content?: string;
  notebook?: string | null;
  tags?: Iterable<unknown> | null;
  isPinned?: boolean;
  isFavorite?: boolean;
  isArchived?: boolean;
  isTrashed?: boolean;
  projectId?: string;
  goalId?: string;
  linkedModule?: string | null;
  linkedId?: string | null;
  nowUtc?: Date;
}): T {
  const now = params.nowUtc ?? EthiopiaClock.nowUtc();
  const nowIso = now.toISOString();
  const existingIds = new Set(params.existingNotes.map((n) => n.id));

  let noteId = params.id?.trim() || generateUniqueNoteId(params.existingNotes, now);
  if (existingIds.has(noteId)) {
    let suffix = 2;
    const base = noteId;
    while (existingIds.has(`${base}-${suffix}`)) {
      suffix += 1;
    }
    noteId = `${base}-${suffix}`;
  }

  const linkPair = normalizeNoteLinkPair(params.linkedModule, params.linkedId);
  const projectId =
    typeof params.projectId === 'string' && params.projectId.trim()
      ? params.projectId.trim()
      : undefined;
  const goalId =
    typeof params.goalId === 'string' && params.goalId.trim()
      ? params.goalId.trim()
      : undefined;

  return {
    id: noteId,
    title: normalizeNoteTitle(params.title),
    content: typeof params.content === 'string' ? params.content : '',
    notebook: normalizeWebNoteNotebook(params.notebook),
    tags: normalizeNoteTags(params.tags),
    isPinned: Boolean(params.isPinned),
    isFavorite: Boolean(params.isFavorite),
    isArchived: Boolean(params.isArchived),
    isTrashed: Boolean(params.isTrashed),
    ...(projectId !== undefined ? { projectId } : {}),
    ...(goalId !== undefined ? { goalId } : {}),
    ...(linkPair !== null ? linkPair : {}),
    createdAt: nowIso,
    updatedAt: nowIso,
  } as unknown as T;
}

export function createQuickCaptureNoteRecord<
  T extends TaskNoteRecord = TaskNoteRecord,
>(params: {
  existingNotes: readonly T[];
  rawText: string;
  notebook?: string | null;
  nowUtc?: Date;
}):
  | { ok: true; note: T; notes: T[] }
  | { ok: false; error: string; notes: T[] } {
  const text = params.rawText.trim();
  if (!text) {
    return {
      ok: false,
      error: 'Please enter something to capture.',
      notes: [...params.existingNotes],
    };
  }

  const firstNonEmptyLine =
    text
      .split(/\r?\n/)
      .map((line) => line.trim())
      .find((line) => line.length > 0) ?? 'Quick Note';

  const note = createWebNoteRecord<T>({
    existingNotes: params.existingNotes,
    title: normalizeNoteTitle(firstNonEmptyLine, { fallbackTitle: 'Quick Note' }),
    content: text,
    notebook: params.notebook ?? 'Personal',
    tags: ['quick_capture'],
    isPinned: false,
    isFavorite: false,
    isArchived: false,
    isTrashed: false,
    nowUtc: params.nowUtc,
  });

  return {
    ok: true,
    note,
    notes: [note, ...params.existingNotes],
  };
}

export function getWebNoteCounts(notes: readonly TaskNoteRecord[]): WebNoteCounts {
  let active = 0;
  let pinned = 0;
  let favorites = 0;
  let archived = 0;
  let trash = 0;

  for (const note of notes) {
    if (isNoteTrashed(note)) {
      trash += 1;
    } else if (isNoteArchived(note)) {
      archived += 1;
    } else {
      active += 1;
      if (isNotePinnedActive(note)) pinned += 1;
      if (isNoteFavoriteActive(note)) favorites += 1;
    }
  }

  return { active, pinned, favorites, archived, trash };
}

export function getAvailableWebNotebooks(
  notes: readonly TaskNoteRecord[],
  defaults: readonly string[] = DEFAULT_WEB_NOTEBOOKS
): string[] {
  const set = new Set<string>(defaults);
  for (const note of notes) {
    if (isNoteTrashed(note)) continue;
    const clean = note.notebook.trim();
    if (clean) {
      set.add(clean);
    }
  }
  return Array.from(set);
}

export function filterAndSortWebNotes<T extends TaskNoteRecord>(
  notes: readonly T[],
  options: {
    activeTab: WebNotesFilterTab;
    searchQuery?: string;
    sortBy?: NoteSortMode;
  }
): T[] {
  const tab = options.activeTab || 'all';
  const query = (options.searchQuery ?? '').trim().toLowerCase();

  const filtered = notes.filter((note) => {
    if (tab === 'trash') {
      if (!isNoteTrashed(note)) return false;
    } else if (tab === 'archived') {
      if (!isNoteArchived(note)) return false;
    } else if (tab === 'pinned') {
      if (!isNotePinnedActive(note)) return false;
    } else if (tab === 'favorites') {
      if (!isNoteFavoriteActive(note)) return false;
    } else if (tab === 'all') {
      if (!isNoteActive(note)) return false;
    } else {
      if (!isNoteActive(note) || note.notebook !== tab) return false;
    }

    if (!query) return true;
    return (
      note.title.toLowerCase().includes(query) ||
      note.content.toLowerCase().includes(query) ||
      note.notebook.toLowerCase().includes(query) ||
      note.tags.some((tag) => tag.toLowerCase().includes(query))
    );
  });

  return sortNotes(filtered, {
    sortBy: options.sortBy ?? 'recent',
    pinFirst: tab !== 'archived' && tab !== 'trash',
  });
}

export function toggleWebNotePin<T extends TaskNoteRecord>(
  notes: readonly T[],
  noteId: string,
  nowUtc?: Date
): WebNoteLifecycleMutationResult<T> {
  const target = notes.find((n) => n.id === noteId);
  if (!target) {
    return { ok: false, notes: [...notes], error: 'Note not found.' };
  }
  if (isNoteTrashed(target)) {
    return {
      ok: false,
      notes: [...notes],
      error: 'Restore note from Trash before pinning.',
    };
  }
  const nowIso = (nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const updatedNote: T = {
    ...target,
    isPinned: !target.isPinned,
    updatedAt: nowIso,
  };
  return {
    ok: true,
    notes: notes.map((n) => (n.id === noteId ? updatedNote : n)),
    updatedNote,
  };
}

export function toggleWebNoteFavorite<T extends TaskNoteRecord>(
  notes: readonly T[],
  noteId: string,
  nowUtc?: Date
): WebNoteLifecycleMutationResult<T> {
  const target = notes.find((n) => n.id === noteId);
  if (!target) {
    return { ok: false, notes: [...notes], error: 'Note not found.' };
  }
  if (isNoteTrashed(target)) {
    return {
      ok: false,
      notes: [...notes],
      error: 'Restore note from Trash before updating favorites.',
    };
  }
  const nowIso = (nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const updatedNote: T = {
    ...target,
    isFavorite: !Boolean(target.isFavorite),
    updatedAt: nowIso,
  };
  return {
    ok: true,
    notes: notes.map((n) => (n.id === noteId ? updatedNote : n)),
    updatedNote,
  };
}

export function toggleWebNoteArchive<T extends TaskNoteRecord>(
  notes: readonly T[],
  noteId: string,
  nowUtc?: Date
): WebNoteLifecycleMutationResult<T> {
  const target = notes.find((n) => n.id === noteId);
  if (!target) {
    return { ok: false, notes: [...notes], error: 'Note not found.' };
  }
  if (isNoteTrashed(target)) {
    return {
      ok: false,
      notes: [...notes],
      error: 'Restore note from Trash before archiving or unarchiving.',
    };
  }
  const nowIso = (nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const updatedNote: T = {
    ...target,
    isArchived: !target.isArchived,
    updatedAt: nowIso,
  };
  return {
    ok: true,
    notes: notes.map((n) => (n.id === noteId ? updatedNote : n)),
    updatedNote,
  };
}

export function moveWebNoteToTrash<T extends TaskNoteRecord>(
  notes: readonly T[],
  noteId: string,
  nowUtc?: Date
): WebNoteLifecycleMutationResult<T> {
  const target = notes.find((n) => n.id === noteId);
  if (!target) {
    return { ok: false, notes: [...notes], error: 'Note not found.' };
  }
  if (isNoteTrashed(target)) {
    return { ok: true, notes: [...notes], updatedNote: target };
  }
  const nowIso = (nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const updatedNote: T = {
    ...target,
    isTrashed: true,
    updatedAt: nowIso,
  };
  return {
    ok: true,
    notes: notes.map((n) => (n.id === noteId ? updatedNote : n)),
    updatedNote,
  };
}

export function restoreWebNoteFromTrash<T extends TaskNoteRecord>(
  notes: readonly T[],
  noteId: string,
  nowUtc?: Date
): WebNoteLifecycleMutationResult<T> {
  const target = notes.find((n) => n.id === noteId);
  if (!target) {
    return { ok: false, notes: [...notes], error: 'Note not found.' };
  }
  if (!isNoteTrashed(target)) {
    return { ok: true, notes: [...notes], updatedNote: target };
  }
  const nowIso = (nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const updatedNote: T = {
    ...target,
    isTrashed: false,
    updatedAt: nowIso,
  };
  return {
    ok: true,
    notes: notes.map((n) => (n.id === noteId ? updatedNote : n)),
    updatedNote,
  };
}

export function permanentlyDeleteWebNote<T extends TaskNoteRecord>(
  notes: readonly T[],
  noteId: string
): WebNoteLifecycleMutationResult<T> {
  const target = notes.find((n) => n.id === noteId);
  if (!target) {
    return { ok: false, notes: [...notes], error: 'Note not found.' };
  }
  if (!isNoteTrashed(target)) {
    return {
      ok: false,
      notes: [...notes],
      error: 'Move note to Trash before permanently deleting it.',
    };
  }
  return {
    ok: true,
    notes: notes.filter((n) => n.id !== noteId),
    removedNote: target,
  };
}

export function emptyWebNotesTrash<T extends TaskNoteRecord>(
  notes: readonly T[]
): { notes: T[]; deletedCount: number } {
  const remaining = notes.filter((n) => !isNoteTrashed(n));
  return {
    notes: remaining,
    deletedCount: notes.length - remaining.length,
  };
}

export function saveWebNoteDraft<T extends TaskNoteRecord = TaskNoteRecord>(params: {
  notes: readonly T[];
  noteId: string | null;
  newNoteId?: string;
  title: string;
  content: string;
  notebook: string;
  tags: readonly string[];
  nowUtc?: Date;
}): SaveWebNoteDraftResult<T> {
  const normalizedTags = normalizeNoteTags(params.tags);
  const normalizedNotebook = normalizeWebNoteNotebook(params.notebook);

  if (!params.noteId) {
    if (
      isNoteDraftBlank({
        title: params.title,
        content: params.content,
        tags: normalizedTags,
      })
    ) {
      return { status: 'discarded_empty', notes: [...params.notes] };
    }
    const created = createWebNoteRecord<T>({
      existingNotes: params.notes,
      id: params.newNoteId,
      title: params.title,
      content: params.content,
      notebook: normalizedNotebook,
      tags: normalizedTags,
      isPinned: false,
      isFavorite: false,
      isArchived: false,
      isTrashed: false,
      nowUtc: params.nowUtc,
    });
    return {
      status: 'created',
      notes: [created, ...params.notes],
      note: created,
    };
  }

  const target = params.notes.find((n) => n.id === params.noteId);
  if (!target || isNoteTrashed(target)) {
    return {
      status: 'unchanged',
      notes: [...params.notes],
      note: target,
    };
  }

  const nextTitle = normalizeNoteTitle(params.title);
  const tagsChanged =
    normalizedTags.length !== target.tags.length ||
    normalizedTags.some((t, i) => t !== target.tags[i]);
  const hasFieldChanges =
    nextTitle !== target.title ||
    params.content !== target.content ||
    normalizedNotebook !== target.notebook ||
    tagsChanged;

  if (!hasFieldChanges) {
    return {
      status: 'unchanged',
      notes: [...params.notes],
      note: target,
    };
  }

  const nowIso = (params.nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const updated: T = {
    ...target,
    title: nextTitle,
    content: params.content,
    notebook: normalizedNotebook,
    tags: normalizedTags,
    updatedAt: nowIso,
  };

  return {
    status: 'updated',
    notes: params.notes.map((n) => (n.id === params.noteId ? updated : n)),
    note: updated,
  };
}
