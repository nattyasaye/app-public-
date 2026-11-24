import { CalendarDate, EthiopiaClock, SharedDateFormatter } from './date';
import { markdownToPlainText } from './noteMarkdown';
import {
  CANONICAL_NOTE_LINKED_MODULES,
  SHARED_BUSINESS_RULES,
  SharedNoteLinkedModule,
} from './sharedFoundation';

export const DEFAULT_NOTE_TITLE = 'Untitled Note';
export const MAX_NOTE_TITLE_LENGTH = SHARED_BUSINESS_RULES.notes.maxTitleLength;

export type NoteLifecycleState = 'active' | 'archived' | 'trashed';
export type NoteSortMode = 'recent' | 'created' | 'alpha' | 'oldest';
export type NoteDateFilterMode =
  | 'all'
  | 'updated_7d'
  | 'updated_30d'
  | 'created_7d'
  | 'created_30d';

export interface NoteLifecycleShape {
  isPinned?: boolean;
  isFavorite?: boolean;
  isArchived?: boolean;
  isTrashed?: boolean;
}

export interface NoteLinkShape {
  linkedModule?: string | null;
  linkedId?: string | null;
}

export interface NormalizedNoteLinkPair {
  linkedModule: SharedNoteLinkedModule;
  linkedId: string;
}

export interface NoteSortItemShape {
  id: string;
  title: string;
  isPinned?: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface NoteTitleValidationResult {
  valid: boolean;
  normalized: string;
  error?: string;
}

const SUPPORTED_NOTE_LINK_MODULES: ReadonlySet<string> = new Set(
  CANONICAL_NOTE_LINKED_MODULES
);

/**
 * Validates whether a note title is non-empty after trimming and within the
 * canonical 250-character limit.
 */
export function isValidNoteTitle(rawTitle: string | null | undefined): boolean {
  if (typeof rawTitle !== 'string') return false;
  const trimmed = rawTitle.trim();
  return trimmed.length > 0 && trimmed.length <= MAX_NOTE_TITLE_LENGTH;
}

/**
 * Normalizes a note title by trimming surrounding whitespace, applying a
 * safe fallback when empty, and clamping to MAX_NOTE_TITLE_LENGTH (250).
 */
export function normalizeNoteTitle(
  rawTitle: string | null | undefined,
  options?: { fallbackTitle?: string }
): string {
  const trimmed = typeof rawTitle === 'string' ? rawTitle.trim() : '';
  if (trimmed.length > 0) {
    return trimmed.slice(0, MAX_NOTE_TITLE_LENGTH);
  }
  const rawFallback = options?.fallbackTitle?.trim() ?? '';
  const safeFallback =
    rawFallback.length > 0 ? rawFallback : DEFAULT_NOTE_TITLE;
  return safeFallback.slice(0, MAX_NOTE_TITLE_LENGTH);
}

/**
 * Validates a note title and returns both validity status and bounded normalized
 * output without discarding user input.
 */
export function validateNoteTitle(
  rawTitle: string | null | undefined,
  options?: { fallbackTitle?: string }
): NoteTitleValidationResult {
  const trimmed = typeof rawTitle === 'string' ? rawTitle.trim() : '';
  if (trimmed.length === 0) {
    return {
      valid: false,
      normalized: normalizeNoteTitle(rawTitle, options),
      error: 'Note title cannot be empty.',
    };
  }
  if (trimmed.length > MAX_NOTE_TITLE_LENGTH) {
    return {
      valid: false,
      normalized: trimmed.slice(0, MAX_NOTE_TITLE_LENGTH),
      error: `Note title cannot exceed ${MAX_NOTE_TITLE_LENGTH} characters.`,
    };
  }
  return {
    valid: true,
    normalized: trimmed,
  };
}

/**
 * Trims tags, removes empty entries, and deduplicates case-insensitively while
 * preserving the first occurrence's original casing and order.
 */
export function normalizeNoteTags(rawTags: Iterable<unknown> | null | undefined): string[] {
  if (!rawTags) return [];
  const seenLower = new Set<string>();
  const normalized: string[] = [];
  for (const entry of rawTags) {
    if (typeof entry !== 'string') continue;
    const trimmed = entry.trim();
    if (!trimmed) continue;
    const key = trimmed.toLowerCase();
    if (seenLower.has(key)) continue;
    seenLower.add(key);
    normalized.push(trimmed);
  }
  return normalized;
}

export const RESERVED_NOTE_FOLDER_NAMES: ReadonlySet<string> = new Set([
  'all',
  'pinned',
  'favorites',
  'archive',
  'archived',
  'trash',
]);

export function normalizeFolderComparisonKey(
  rawFolder: string | null | undefined
): string {
  return typeof rawFolder === 'string' ? rawFolder.trim().toLowerCase() : '';
}

export function isReservedNoteFolderName(
  rawFolder: string | null | undefined
): boolean {
  const key = normalizeFolderComparisonKey(rawFolder);
  return key.length > 0 && RESERVED_NOTE_FOLDER_NAMES.has(key);
}

export function matchesFolderSearchQuery(
  rawFolder: string | null | undefined,
  cleanQuery: string
): boolean {
  const folderLower =
    typeof rawFolder === 'string' ? rawFolder.trim().toLowerCase() : '';
  if (!folderLower) return false;
  if (folderLower.includes(cleanQuery)) return true;
  const spaceNormalized = folderLower
    .replace(/[_-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return spaceNormalized.includes(cleanQuery);
}

export function matchesNoteTagsSearchQuery(
  tags: readonly string[] | null | undefined,
  cleanQuery: string
): boolean {
  if (!tags || tags.length === 0) return false;
  for (const rawTag of tags) {
    const lowerTag =
      typeof rawTag === 'string' ? rawTag.trim().toLowerCase() : '';
    if (!lowerTag) continue;
    if (lowerTag.includes(cleanQuery) || `#${lowerTag}`.includes(cleanQuery)) {
      return true;
    }
  }
  return false;
}

export function matchesNoteSearchQuery(
  note: {
    title: string;
    content: string;
    notebook: string;
    tags?: readonly string[];
  },
  rawQuery: string,
  options?: {
    projectTitle?: string | null;
  }
): boolean {
  const query = rawQuery.trim().toLowerCase();
  if (!query) return true;
  if (note.title.toLowerCase().includes(query)) return true;
  if (note.content.toLowerCase().includes(query)) return true;
  const plainContent = markdownToPlainText(note.content)
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
  if (plainContent.includes(query)) return true;
  if (matchesFolderSearchQuery(note.notebook, query)) return true;
  if (matchesNoteTagsSearchQuery(note.tags, query)) return true;
  const projectTitle =
    typeof options?.projectTitle === 'string'
      ? options.projectTitle.trim().toLowerCase()
      : '';
  return projectTitle.length > 0 && projectTitle.includes(query);
}

/**
 * Collects unique tags across notes case-insensitively (preserving first-seen
 * casing) and returns them sorted alphabetically.
 */
export function collectUniqueNoteTags(
  notes: readonly {
    tags?: readonly string[];
    isArchived?: boolean;
    isTrashed?: boolean;
  }[],
  options?: {
    includeArchived?: boolean;
    includeTrashed?: boolean;
  }
): string[] {
  const includeArchived = options?.includeArchived ?? true;
  const includeTrashed = options?.includeTrashed ?? false;
  const seen = new Map<string, string>();
  for (const note of notes) {
    if (!includeTrashed && note.isTrashed) continue;
    if (!includeArchived && note.isArchived && !note.isTrashed) continue;
    for (const rawTag of note.tags ?? []) {
      const trimmed = typeof rawTag === 'string' ? rawTag.trim() : '';
      if (!trimmed) continue;
      const key = trimmed.toLowerCase();
      if (!seen.has(key)) {
        seen.set(key, trimmed);
      }
    }
  }
  return Array.from(seen.values()).sort((a, b) =>
    a.toLowerCase().localeCompare(b.toLowerCase())
  );
}

/**
 * Cleans a candidate tag (trims whitespace and leading `#`) and reuses the
 * canonical existing casing from `availableTags` when a case-insensitive match
 * exists. Returns `null` when blank.
 */
export function resolveReusableNoteTag(
  rawCandidate: string | null | undefined,
  availableTags: readonly string[]
): string | null {
  const cleaned = (typeof rawCandidate === 'string' ? rawCandidate : '')
    .trim()
    .replace(/^#+/, '')
    .trim();
  if (!cleaned) return null;
  const lower = cleaned.toLowerCase();
  for (const existing of availableTags) {
    const trimmedExisting = typeof existing === 'string' ? existing.trim() : '';
    if (trimmedExisting && trimmedExisting.toLowerCase() === lower) {
      return trimmedExisting;
    }
  }
  return cleaned;
}

export function noteMatchesTagFilter(
  noteTags: readonly string[] | undefined,
  tagFilter: string | null | undefined
): boolean {
  const cleanFilter = typeof tagFilter === 'string' ? tagFilter.trim() : '';
  if (!cleanFilter || cleanFilter.toLowerCase() === 'all') return true;
  const targetLower = cleanFilter.toLowerCase();
  return (noteTags ?? []).some((t) => t.trim().toLowerCase() === targetLower);
}

/**
 * Normalizes a folder/category/notebook string while preserving existing custom
 * values and platform-specific defaults when empty.
 */
export function normalizeNoteFolder(
  rawFolder: string | null | undefined,
  options?: {
    defaultFolder?: string;
    lowercase?: boolean;
  }
): string {
  const rawDefault = options?.defaultFolder?.trim() ?? '';
  const safeDefault =
    rawDefault.length > 0
      ? rawDefault
      : SHARED_BUSINESS_RULES.notes.defaultExchangeFolder;
  const trimmed = typeof rawFolder === 'string' ? rawFolder.trim() : '';
  if (!trimmed) {
    return options?.lowercase ? safeDefault.toLowerCase() : safeDefault;
  }
  return options?.lowercase ? trimmed.toLowerCase() : trimmed;
}

export function normalizeFlutterNoteCategory(
  rawCategory: string | null | undefined
): string {
  return normalizeNoteFolder(rawCategory, {
    defaultFolder: SHARED_BUSINESS_RULES.notes.defaultFlutterCategory,
    lowercase: true,
  });
}

export function normalizeWebNoteNotebook(
  rawNotebook: string | null | undefined
): string {
  return normalizeNoteFolder(rawNotebook, {
    defaultFolder: SHARED_BUSINESS_RULES.notes.defaultWebNotebook,
    lowercase: false,
  });
}

export function normalizeExchangeNoteFolder(
  rawFolder: string | null | undefined
): string {
  return normalizeNoteFolder(rawFolder, {
    defaultFolder: SHARED_BUSINESS_RULES.notes.defaultExchangeFolder,
    lowercase: false,
  });
}

/**
 * Lifecycle predicates (trash takes precedence over archive).
 */
export function isNoteTrashed(note: Pick<NoteLifecycleShape, 'isTrashed'>): boolean {
  return Boolean(note.isTrashed);
}

export function isNoteArchived(
  note: Pick<NoteLifecycleShape, 'isArchived' | 'isTrashed'>
): boolean {
  return Boolean(note.isArchived) && !Boolean(note.isTrashed);
}

export function isNoteActive(
  note: Pick<NoteLifecycleShape, 'isArchived' | 'isTrashed'>
): boolean {
  return !Boolean(note.isTrashed) && !Boolean(note.isArchived);
}

export function isNotePinnedActive(
  note: Pick<NoteLifecycleShape, 'isPinned' | 'isArchived' | 'isTrashed'>
): boolean {
  return isNoteActive(note) && Boolean(note.isPinned);
}

export function isNoteFavoriteActive(
  note: Pick<NoteLifecycleShape, 'isFavorite' | 'isArchived' | 'isTrashed'>
): boolean {
  return isNoteActive(note) && Boolean(note.isFavorite);
}

export function getNoteLifecycleState(
  note: Pick<NoteLifecycleShape, 'isArchived' | 'isTrashed'>
): NoteLifecycleState {
  if (isNoteTrashed(note)) return 'trashed';
  if (isNoteArchived(note)) return 'archived';
  return 'active';
}

/**
 * Polymorphic link validation & normalization (`tasks` | `finance` | `calendar`).
 */
export function isSupportedNoteLinkModule(
  rawModule: string | null | undefined
): rawModule is SharedNoteLinkedModule {
  if (typeof rawModule !== 'string') return false;
  const normalized = rawModule.trim().toLowerCase();
  return normalized.length > 0 && SUPPORTED_NOTE_LINK_MODULES.has(normalized);
}

export function normalizeNoteLinkPair(
  rawModule: string | null | undefined,
  rawId: string | null | undefined
): NormalizedNoteLinkPair | null {
  if (typeof rawModule !== 'string' || typeof rawId !== 'string') return null;
  const mod = rawModule.trim().toLowerCase();
  const id = rawId.trim();
  if (!mod || !SUPPORTED_NOTE_LINK_MODULES.has(mod) || !id) {
    return null;
  }
  return {
    linkedModule: mod as SharedNoteLinkedModule,
    linkedId: id,
  };
}

export function hasValidNoteLink(note: NoteLinkShape): boolean {
  return normalizeNoteLinkPair(note.linkedModule, note.linkedId) !== null;
}

function parseUtcTimestampMs(rawIso: string): number {
  const parsed = Date.parse(rawIso);
  return Number.isFinite(parsed) ? parsed : 0;
}

function compareCodeUnits(a: string, b: string): number {
  if (a < b) return -1;
  if (a > b) return 1;
  return 0;
}

export function parseNoteDateFilterMode(
  rawFilter: string | null | undefined
): NoteDateFilterMode {
  const normalized =
    typeof rawFilter === 'string' ? rawFilter.trim().toLowerCase() : '';
  if (normalized === 'updated_7d') return 'updated_7d';
  if (normalized === 'updated_30d') return 'updated_30d';
  if (normalized === 'created_7d') return 'created_7d';
  if (normalized === 'created_30d') return 'created_30d';
  return 'all';
}

export function noteMatchesDateFilter(
  note: Pick<NoteSortItemShape, 'createdAt' | 'updatedAt'>,
  filter: NoteDateFilterMode,
  nowUtc?: Date
): boolean {
  if (filter === 'all') return true;
  const today = CalendarDate.fromUtcInstantInEthiopia(
    nowUtc ?? EthiopiaClock.nowUtc()
  );
  const windowDays =
    filter === 'updated_7d' || filter === 'created_7d' ? 7 : 30;
  const cutoff = today.subtractDays(windowDays - 1);
  const targetRaw =
    filter === 'created_7d' || filter === 'created_30d'
      ? note.createdAt
      : note.updatedAt;
  const targetDate = SharedDateFormatter.tryParseFlexibleToCalendarDate(targetRaw);
  if (!targetDate) return false;
  return targetDate.jdn >= cutoff.jdn;
}

export function parseNoteSortMode(rawSort: string | null | undefined): NoteSortMode {
  const normalized = typeof rawSort === 'string' ? rawSort.trim().toLowerCase() : '';
  if (normalized === 'created') return 'created';
  if (normalized === 'alpha') return 'alpha';
  if (normalized === 'oldest') return 'oldest';
  return 'recent';
}

/**
 * Deterministic cross-platform Note comparator.
 * - Optional pinFirst priority (active/pinned views vs archive/trash).
 * - Mode-specific comparison (`recent`, `created`, `alpha`, `oldest`) with deterministic tie-breakers.
 */
export function compareNotes<T extends NoteSortItemShape>(
  a: T,
  b: T,
  options?: {
    sortBy?: NoteSortMode;
    pinFirst?: boolean;
  }
): number {
  const sortBy = options?.sortBy ?? 'recent';
  const pinFirst = options?.pinFirst ?? true;

  if (pinFirst) {
    const aPinned = Boolean(a.isPinned);
    const bPinned = Boolean(b.isPinned);
    if (aPinned !== bPinned) {
      return aPinned ? -1 : 1;
    }
  }

  if (sortBy === 'alpha') {
    const titleCmp = compareCodeUnits(
      normalizeNoteTitle(a.title).toLowerCase(),
      normalizeNoteTitle(b.title).toLowerCase()
    );
    if (titleCmp !== 0) return titleCmp;
    const updatedCmp =
      parseUtcTimestampMs(b.updatedAt) - parseUtcTimestampMs(a.updatedAt);
    if (updatedCmp !== 0) return updatedCmp;
    return compareCodeUnits(a.id, b.id);
  }

  if (sortBy === 'created') {
    const createdCmp =
      parseUtcTimestampMs(b.createdAt) - parseUtcTimestampMs(a.createdAt);
    if (createdCmp !== 0) return createdCmp;
    const updatedCmp =
      parseUtcTimestampMs(b.updatedAt) - parseUtcTimestampMs(a.updatedAt);
    if (updatedCmp !== 0) return updatedCmp;
    return compareCodeUnits(a.id, b.id);
  }

  if (sortBy === 'oldest') {
    const createdCmp =
      parseUtcTimestampMs(a.createdAt) - parseUtcTimestampMs(b.createdAt);
    if (createdCmp !== 0) return createdCmp;
    const updatedCmp =
      parseUtcTimestampMs(a.updatedAt) - parseUtcTimestampMs(b.updatedAt);
    if (updatedCmp !== 0) return updatedCmp;
    return compareCodeUnits(a.id, b.id);
  }

  const updatedCmp =
    parseUtcTimestampMs(b.updatedAt) - parseUtcTimestampMs(a.updatedAt);
  if (updatedCmp !== 0) return updatedCmp;
  const createdCmp =
    parseUtcTimestampMs(b.createdAt) - parseUtcTimestampMs(a.createdAt);
  if (createdCmp !== 0) return createdCmp;
  return compareCodeUnits(a.id, b.id);
}

export function sortNotes<T extends NoteSortItemShape>(
  notes: readonly T[],
  options?: {
    sortBy?: NoteSortMode;
    pinFirst?: boolean;
  }
): T[] {
  return [...notes].sort((a, b) => compareNotes(a, b, options));
}
