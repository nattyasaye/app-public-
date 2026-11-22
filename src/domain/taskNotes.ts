import { EthiopiaClock } from './date';
import { DaywellTaskRecord } from './taskOperations';

export const MAX_NOTE_TITLE_LENGTH = 250;

export type NoteLinkedModule = 'tasks' | 'finance' | 'calendar';

export interface TaskNoteRecord {
  id: string;
  title: string;
  content: string;
  notebook: string;
  tags: string[];
  isPinned: boolean;
  isArchived: boolean;
  isFavorite?: boolean;
  isTrashed?: boolean;
  projectId?: string;
  goalId?: string;
  linkedModule?: NoteLinkedModule;
  linkedId?: string;
  createdAt: string;
  updatedAt: string;
}

export interface AvailableTaskNoteOption<T extends TaskNoteRecord = TaskNoteRecord> {
  note: T;
  linkedTaskId?: string;
  isLinkedToOtherModule: boolean;
}

export interface LinkNoteMutationResult<T extends TaskNoteRecord = TaskNoteRecord> {
  ok: boolean;
  notes: T[];
  updatedNote?: T;
  previousLinkedModule?: NoteLinkedModule;
  previousLinkedId?: string;
  error?: string;
}

export interface CreateNoteForTaskResult<T extends TaskNoteRecord = TaskNoteRecord> {
  ok: boolean;
  notes: T[];
  note?: T;
  error?: string;
}

export interface UnlinkDeletedTaskNotesResult<
  T extends TaskNoteRecord = TaskNoteRecord,
> {
  notes: T[];
  unlinkedCount: number;
  unlinkedNoteIds: string[];
}

export function buildBoundedTaskNoteTitle(rawTitle?: string | null): string {
  const trimmed = (rawTitle ?? '').trim();
  if (!trimmed) return 'Task Note';
  return trimmed.slice(0, MAX_NOTE_TITLE_LENGTH);
}

export function normalizeTaskNoteRecord(raw: unknown): TaskNoteRecord | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;
  const id = typeof r.id === 'string' ? r.id.trim() : '';
  if (!id) return null;

  const titleRaw = typeof r.title === 'string' ? r.title.trim() : '';
  const content =
    typeof r.content === 'string'
      ? r.content
      : typeof r.body === 'string'
        ? r.body
        : '';
  const notebookRaw =
    typeof r.notebook === 'string' && r.notebook.trim()
      ? r.notebook.trim()
      : typeof r.folder === 'string' && r.folder.trim()
        ? r.folder.trim()
        : typeof r.category === 'string' && r.category.trim()
          ? r.category.trim()
          : 'Personal';
  const tags = Array.isArray(r.tags)
    ? r.tags
        .filter((t): t is string => typeof t === 'string' && t.trim().length > 0)
        .map((t) => t.trim())
    : [];
  const createdAt =
    typeof r.createdAt === 'string' && r.createdAt.trim()
      ? r.createdAt.trim()
      : EthiopiaClock.nowUtc().toISOString();
  const updatedAt =
    typeof r.updatedAt === 'string' && r.updatedAt.trim()
      ? r.updatedAt.trim()
      : createdAt;

  const linkedModule =
    r.linkedModule === 'tasks' ||
    r.linkedModule === 'finance' ||
    r.linkedModule === 'calendar'
      ? r.linkedModule
      : undefined;
  const linkedId =
    typeof r.linkedId === 'string' && r.linkedId.trim()
      ? r.linkedId.trim()
      : undefined;
  const projectId =
    typeof r.projectId === 'string' && r.projectId.trim()
      ? r.projectId.trim()
      : undefined;
  const goalId =
    typeof r.goalId === 'string' && r.goalId.trim()
      ? r.goalId.trim()
      : undefined;

  return {
    id,
    title: (titleRaw || 'Untitled Note').slice(0, MAX_NOTE_TITLE_LENGTH),
    content,
    notebook: notebookRaw,
    tags,
    isPinned: Boolean(r.isPinned),
    isArchived: Boolean(r.isArchived),
    ...(r.isFavorite !== undefined ? { isFavorite: Boolean(r.isFavorite) } : {}),
    ...(r.isTrashed !== undefined ? { isTrashed: Boolean(r.isTrashed) } : {}),
    ...(projectId !== undefined ? { projectId } : {}),
    ...(goalId !== undefined ? { goalId } : {}),
    ...(linkedModule !== undefined && linkedId !== undefined
      ? { linkedModule, linkedId }
      : {}),
    createdAt,
    updatedAt,
  };
}

export function isNoteLinkedToTask(
  note: Pick<TaskNoteRecord, 'linkedModule' | 'linkedId' | 'isTrashed'>,
  taskId: string
): boolean {
  const cleanTaskId = taskId.trim();
  if (!cleanTaskId || note.isTrashed) return false;
  return note.linkedModule === 'tasks' && note.linkedId === cleanTaskId;
}

export function getNotesLinkedToTask<T extends TaskNoteRecord>(
  notes: readonly T[],
  taskId: string,
  options?: { includeArchived?: boolean }
): T[] {
  const includeArchived = options?.includeArchived ?? true;
  return notes
    .filter((note) => {
      if (!isNoteLinkedToTask(note, taskId)) return false;
      if (!includeArchived && note.isArchived) return false;
      return true;
    })
    .slice()
    .sort((a, b) => {
      if (a.isPinned !== b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt.localeCompare(a.updatedAt);
    });
}

export function countNotesLinkedToTask(
  notes: readonly TaskNoteRecord[],
  taskId: string
): number {
  return getNotesLinkedToTask(notes, taskId, { includeArchived: true }).length;
}

export function getLinkedTaskForNote<
  TTask extends Pick<DaywellTaskRecord, 'id' | 'title' | 'status' | 'completed' | 'isArchived'>,
>(
  note: Pick<TaskNoteRecord, 'linkedModule' | 'linkedId'>,
  tasks: readonly TTask[]
): TTask | null {
  if (note.linkedModule !== 'tasks') return null;
  const cleanId = (note.linkedId ?? '').trim();
  if (!cleanId) return null;
  return tasks.find((t) => t.id === cleanId) ?? null;
}

export function getAvailableNotesToLink<T extends TaskNoteRecord>(
  notes: readonly T[],
  taskId: string,
  searchQuery = ''
): AvailableTaskNoteOption<T>[] {
  const cleanTaskId = taskId.trim();
  const q = searchQuery.trim().toLowerCase();

  return notes
    .filter((note) => {
      if (note.isTrashed) return false;
      if (isNoteLinkedToTask(note, cleanTaskId)) return false;
      if (!q) return true;
      return (
        note.title.toLowerCase().includes(q) ||
        note.content.toLowerCase().includes(q) ||
        note.notebook.toLowerCase().includes(q) ||
        note.tags.some((tag) => tag.toLowerCase().includes(q))
      );
    })
    .slice()
    .sort((a, b) => {
      const aHasLink = Boolean(a.linkedModule && a.linkedId);
      const bHasLink = Boolean(b.linkedModule && b.linkedId);
      if (aHasLink !== bHasLink) return aHasLink ? 1 : -1;
      if (a.isArchived !== b.isArchived) return a.isArchived ? 1 : -1;
      return b.updatedAt.localeCompare(a.updatedAt);
    })
    .map((note) => ({
      note,
      linkedTaskId:
        note.linkedModule === 'tasks' && note.linkedId
          ? note.linkedId
          : undefined,
      isLinkedToOtherModule: Boolean(
        note.linkedModule && note.linkedModule !== 'tasks' && note.linkedId
      ),
    }));
}

export function linkNoteToTask<T extends TaskNoteRecord>(
  notes: readonly T[],
  noteId: string,
  taskId: string,
  nowUtc?: Date
): LinkNoteMutationResult<T> {
  const cleanNoteId = noteId.trim();
  const cleanTaskId = taskId.trim();
  if (!cleanNoteId || !cleanTaskId) {
    return {
      ok: false,
      notes: [...notes],
      error: 'Note ID and Task ID are required to create a link.',
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

  const updatedIso = (nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const updatedNote: T = {
    ...target,
    linkedModule: 'tasks',
    linkedId: cleanTaskId,
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

export function unlinkNoteFromTask<T extends TaskNoteRecord>(
  notes: readonly T[],
  noteId: string,
  expectedTaskId?: string,
  nowUtc?: Date
): LinkNoteMutationResult<T> {
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

  if (target.linkedModule !== 'tasks') {
    return {
      ok: false,
      notes: [...notes],
      error: 'This note is not linked to a task.',
    };
  }

  if (expectedTaskId && target.linkedId !== expectedTaskId.trim()) {
    return {
      ok: false,
      notes: [...notes],
      error: 'This note is linked to a different task.',
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

export function unlinkNotesForDeletedTask<T extends TaskNoteRecord>(
  notes: readonly T[],
  deletedTaskId: string,
  nowUtc?: Date
): UnlinkDeletedTaskNotesResult<T> {
  const cleanTaskId = deletedTaskId.trim();
  if (!cleanTaskId) {
    return { notes: [...notes], unlinkedCount: 0, unlinkedNoteIds: [] };
  }

  const updatedIso = (nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const unlinkedNoteIds: string[] = [];

  const next = notes.map((note) => {
    if (note.linkedModule === 'tasks' && note.linkedId === cleanTaskId) {
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

export function createNoteForTask<T extends TaskNoteRecord = TaskNoteRecord>(params: {
  notes: readonly T[];
  task: Pick<DaywellTaskRecord, 'id' | 'title'>;
  id?: string;
  title?: string;
  content?: string;
  notebook?: string;
  nowUtc?: Date;
}): CreateNoteForTaskResult<T> {
  const cleanTaskId = params.task.id.trim();
  if (!cleanTaskId) {
    return {
      ok: false,
      notes: [...params.notes],
      error: 'Task ID is required to create a linked note.',
    };
  }

  const now = params.nowUtc ?? EthiopiaClock.nowUtc();
  const nowIso = now.toISOString();
  const existingIds = new Set(params.notes.map((n) => n.id));
  let noteId = params.id?.trim() || `note-${now.getTime()}`;
  let suffix = 1;
  while (existingIds.has(noteId)) {
    suffix += 1;
    noteId = `note-${now.getTime()}-${suffix}`;
  }

  const notebook = params.notebook?.trim() || 'Personal';
  const noteTitle = buildBoundedTaskNoteTitle(params.title ?? params.task.title);

  const created = {
    id: noteId,
    title: noteTitle,
    content: params.content ?? '',
    notebook,
    tags: [],
    isPinned: false,
    isArchived: false,
    linkedModule: 'tasks',
    linkedId: cleanTaskId,
    createdAt: nowIso,
    updatedAt: nowIso,
  } as unknown as T;

  return {
    ok: true,
    notes: [created, ...params.notes],
    note: created,
  };
}
