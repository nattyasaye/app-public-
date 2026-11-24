import { EthiopiaClock } from './date';
import {
  compareNotes,
  isNoteTrashed,
  MAX_NOTE_TITLE_LENGTH,
  normalizeNoteTitle,
  normalizeWebNoteNotebook,
} from './noteHelpers';
import { markdownToPlainText } from './noteMarkdown';
import { SharedProject } from './sharedFoundation';
import { TaskNoteRecord } from './taskNotes';

export type ProjectNoteTarget = Pick<
  SharedProject,
  'id' | 'title' | 'isArchived' | 'status'
>;

export interface ProjectNoteMutationResult<
  T extends TaskNoteRecord = TaskNoteRecord,
> {
  ok: boolean;
  notes: T[];
  updatedNote?: T;
  previousProjectId?: string;
  error?: string;
}

export interface CreateNoteForProjectResult<
  T extends TaskNoteRecord = TaskNoteRecord,
> {
  ok: boolean;
  notes: T[];
  note?: T;
  error?: string;
}

export interface UnlinkDeletedProjectNotesResult<
  T extends TaskNoteRecord = TaskNoteRecord,
> {
  notes: T[];
  unlinkedCount: number;
  unlinkedNoteIds: string[];
}

export function normalizeNoteProjectId(
  rawProjectId?: string | null
): string | undefined {
  if (typeof rawProjectId !== 'string') return undefined;
  const trimmed = rawProjectId.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

export function buildBoundedProjectNoteTitle(
  rawTitle?: string | null
): string {
  return normalizeNoteTitle(rawTitle, {
    fallbackTitle: 'Project Note',
  });
}

export function isNoteLinkedToProject(
  note: Pick<TaskNoteRecord, 'projectId' | 'isTrashed'>,
  projectId: string
): boolean {
  const cleanProjectId = projectId.trim();
  if (!cleanProjectId || isNoteTrashed(note)) return false;
  return normalizeNoteProjectId(note.projectId) === cleanProjectId;
}

export function getNotesForProject<T extends TaskNoteRecord>(
  notes: readonly T[],
  projectId: string,
  options?: {
    includeArchived?: boolean;
    includeTrashed?: boolean;
  }
): T[] {
  const cleanProjectId = projectId.trim();
  if (!cleanProjectId) return [];
  const includeArchived = options?.includeArchived ?? true;
  const includeTrashed = options?.includeTrashed ?? false;

  return notes
    .filter((note) => {
      if (!includeTrashed && isNoteTrashed(note)) return false;
      if (normalizeNoteProjectId(note.projectId) !== cleanProjectId) {
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

export function countNotesForProject(
  notes: readonly TaskNoteRecord[],
  projectId: string,
  options?: { includeArchived?: boolean }
): number {
  return getNotesForProject(notes, projectId, {
    includeArchived: options?.includeArchived ?? true,
    includeTrashed: false,
  }).length;
}

export function getProjectForNote<P extends Pick<SharedProject, 'id'>>(
  note: Pick<TaskNoteRecord, 'projectId'>,
  projects: readonly P[]
): P | null {
  const cleanProjectId = normalizeNoteProjectId(note.projectId);
  if (!cleanProjectId) return null;
  return projects.find((project) => project.id === cleanProjectId) ?? null;
}

export function buildProjectTitlesById(
  projects: readonly Pick<SharedProject, 'id' | 'title'>[]
): Map<string, string> {
  const map = new Map<string, string>();
  for (const project of projects) {
    const cleanId = project.id.trim();
    const cleanTitle = project.title.trim();
    if (cleanId && cleanTitle) {
      map.set(cleanId, cleanTitle);
    }
  }
  return map;
}

export function getNoteContentPreview(
  content: string,
  maxLength = 140
): string {
  const plain = markdownToPlainText(content)
    .replace(/\s+/g, ' ')
    .trim();
  if (!plain) return '';
  if (plain.length <= maxLength) return plain;
  return `${plain.slice(0, Math.max(1, maxLength - 1)).trimEnd()}…`;
}

export function setNoteProject<T extends TaskNoteRecord = TaskNoteRecord>(
  notes: readonly T[],
  noteId: string,
  projectId: string | null | undefined,
  nowUtc?: Date
): ProjectNoteMutationResult<T> {
  const cleanNoteId = noteId.trim();
  const target = notes.find((n) => n.id === cleanNoteId);
  if (!target) {
    return { ok: false, notes: [...notes], error: 'Note not found.' };
  }
  if (isNoteTrashed(target)) {
    return {
      ok: false,
      notes: [...notes],
      error: 'Restore note from Trash before changing its project.',
    };
  }

  const nextProjectId = normalizeNoteProjectId(projectId);
  const previousProjectId = normalizeNoteProjectId(target.projectId);
  if (previousProjectId === nextProjectId) {
    return {
      ok: true,
      notes: [...notes],
      updatedNote: target,
      previousProjectId,
    };
  }

  const nowIso = (nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const updated: T = { ...target, updatedAt: nowIso };
  if (nextProjectId !== undefined) {
    updated.projectId = nextProjectId;
  } else {
    delete updated.projectId;
  }

  return {
    ok: true,
    notes: notes.map((n) => (n.id === cleanNoteId ? updated : n)),
    updatedNote: updated,
    previousProjectId,
  };
}

export function clearNoteProject<T extends TaskNoteRecord = TaskNoteRecord>(
  notes: readonly T[],
  noteId: string,
  nowUtc?: Date
): ProjectNoteMutationResult<T> {
  return setNoteProject(notes, noteId, undefined, nowUtc);
}

export function unlinkNotesForDeletedProject<
  T extends TaskNoteRecord = TaskNoteRecord,
>(
  notes: readonly T[],
  deletedProjectId: string,
  nowUtc?: Date
): UnlinkDeletedProjectNotesResult<T> {
  const cleanProjectId = deletedProjectId.trim();
  if (!cleanProjectId) {
    return { notes: [...notes], unlinkedCount: 0, unlinkedNoteIds: [] };
  }

  const nowIso = (nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const unlinkedNoteIds: string[] = [];

  const nextNotes = notes.map((note) => {
    if (normalizeNoteProjectId(note.projectId) !== cleanProjectId) {
      return note;
    }
    unlinkedNoteIds.push(note.id);
    const copy: T = { ...note, updatedAt: nowIso };
    delete copy.projectId;
    return copy;
  });

  return {
    notes: nextNotes,
    unlinkedCount: unlinkedNoteIds.length,
    unlinkedNoteIds,
  };
}

export function createNoteForProject<T extends TaskNoteRecord = TaskNoteRecord>(
  params: {
    notes: readonly T[];
    project: Pick<SharedProject, 'id' | 'title'>;
    id?: string;
    title?: string;
    content?: string;
    notebook?: string;
    nowUtc?: Date;
  }
): CreateNoteForProjectResult<T> {
  const cleanProjectId = params.project.id.trim();
  if (!cleanProjectId) {
    return {
      ok: false,
      notes: [...params.notes],
      error: 'Project ID is required to create a project note.',
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
  const defaultTitle = params.project.title.trim()
    ? `${params.project.title.trim()} — Note`
    : 'Project Note';
  const noteTitle = buildBoundedProjectNoteTitle(
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
    projectId: cleanProjectId,
    createdAt: nowIso,
    updatedAt: nowIso,
  } as unknown as T;

  return {
    ok: true,
    notes: [created, ...params.notes],
    note: created,
  };
}
