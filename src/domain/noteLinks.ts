import {
  compareNotes,
  isNoteActive,
  NoteLifecycleShape,
  NoteSortItemShape,
} from './noteHelpers';
import {
  inlinesToPlainText,
  markdownToPlainText,
  NoteMarkdownDocument,
  NoteMarkdownInline,
  parseNoteMarkdown,
} from './noteMarkdown';

export interface NoteLinkCandidateShape
  extends NoteLifecycleShape,
    NoteSortItemShape {
  content: string;
  notebook?: string;
  category?: string;
}

export interface ParsedNoteInternalLink {
  targetTitle: string;
  rawText: string;
  normalizedKey: string;
}

export type NoteInternalLinkResolution<
  T extends NoteLinkCandidateShape = NoteLinkCandidateShape,
> =
  | {
      status: 'resolved';
      targetTitle: string;
      normalizedKey: string;
      note: T;
      matches: T[];
    }
  | {
      status: 'ambiguous';
      targetTitle: string;
      normalizedKey: string;
      note: null;
      matches: T[];
    }
  | {
      status: 'missing';
      targetTitle: string;
      normalizedKey: string;
      note: null;
      matches: [];
    };

export interface NoteBacklinkEntry<
  T extends NoteLinkCandidateShape = NoteLinkCandidateShape,
> {
  note: T;
  snippet: string;
  linkCount: number;
}

const MAX_BACKLINK_SNIPPET_LENGTH = 110;

/**
 * Normalizes a note title or `[[Note Title]]` target for exact deterministic matching.
 * Collapses repeated whitespace and folds case without fuzzy or substring matching.
 */
export function normalizeNoteLinkTitleKey(
  rawTitle: string | null | undefined
): string {
  if (typeof rawTitle !== 'string') return '';
  const trimmed = rawTitle.trim();
  if (!trimmed) return '';
  return trimmed.replace(/\s+/g, ' ').toLowerCase();
}

function collectInternalLinksFromInlines(
  inlines: readonly NoteMarkdownInline[],
  out: ParsedNoteInternalLink[]
): void {
  for (const node of inlines) {
    switch (node.type) {
      case 'internalLink': {
        const normalizedKey = normalizeNoteLinkTitleKey(node.targetTitle);
        if (normalizedKey) {
          out.push({
            targetTitle: node.targetTitle,
            rawText: node.rawText,
            normalizedKey,
          });
        }
        break;
      }
      case 'bold':
      case 'italic':
      case 'strikethrough':
        collectInternalLinksFromInlines(node.children, out);
        break;
      case 'text':
      case 'code':
      case 'link':
        break;
    }
  }
}

function inlineListContainsTargetKey(
  inlines: readonly NoteMarkdownInline[],
  targetKey: string
): boolean {
  const found: ParsedNoteInternalLink[] = [];
  collectInternalLinksFromInlines(inlines, found);
  return found.some((link) => link.normalizedKey === targetKey);
}

/**
 * Extracts all valid `[[Note Title]]` internal links from parsed Markdown outside
 * inline code and fenced code blocks.
 */
export function extractInternalLinksFromMarkdown(
  source: string | null | undefined
): ParsedNoteInternalLink[] {
  const doc = parseNoteMarkdown(source);
  const links: ParsedNoteInternalLink[] = [];

  for (const block of doc.blocks) {
    switch (block.type) {
      case 'heading':
      case 'paragraph':
        collectInternalLinksFromInlines(block.inlines, links);
        break;
      case 'bulletList':
        for (const item of block.items) {
          collectInternalLinksFromInlines(item, links);
        }
        break;
      case 'orderedList':
        for (const item of block.items) {
          collectInternalLinksFromInlines(item.inlines, links);
        }
        break;
      case 'checklist':
        for (const item of block.items) {
          collectInternalLinksFromInlines(item.inlines, links);
        }
        break;
      case 'blockquote':
        for (const line of block.lines) {
          collectInternalLinksFromInlines(line, links);
        }
        break;
      case 'codeBlock':
      case 'horizontalRule':
        break;
    }
  }

  return links;
}

/**
 * Resolves an internal link target dynamically against active notes only
 * (archived and trashed notes are excluded). Multiple active matches return
 * `ambiguous` rather than silently choosing one.
 */
export function resolveNoteInternalLink<T extends NoteLinkCandidateShape>(
  targetTitle: string | null | undefined,
  notes: readonly T[]
): NoteInternalLinkResolution<T> {
  const cleanTitle = typeof targetTitle === 'string' ? targetTitle.trim() : '';
  const normalizedKey = normalizeNoteLinkTitleKey(cleanTitle);
  if (!normalizedKey) {
    return {
      status: 'missing',
      targetTitle: cleanTitle,
      normalizedKey: '',
      note: null,
      matches: [],
    };
  }

  const matched = notes.filter(
    (note) =>
      isNoteActive(note) &&
      normalizeNoteLinkTitleKey(note.title) === normalizedKey
  );

  if (matched.length === 0) {
    return {
      status: 'missing',
      targetTitle: cleanTitle,
      normalizedKey,
      note: null,
      matches: [],
    };
  }

  const sortedMatches = [...matched].sort((a, b) =>
    compareNotes(a, b, { sortBy: 'recent', pinFirst: false })
  );

  if (sortedMatches.length === 1) {
    return {
      status: 'resolved',
      targetTitle: cleanTitle,
      normalizedKey,
      note: sortedMatches[0],
      matches: sortedMatches,
    };
  }

  return {
    status: 'ambiguous',
    targetTitle: cleanTitle,
    normalizedKey,
    note: null,
    matches: sortedMatches,
  };
}

function truncateSnippet(raw: string): string {
  const collapsed = raw.replace(/\s+/g, ' ').trim();
  if (!collapsed) return '';
  if (collapsed.length <= MAX_BACKLINK_SNIPPET_LENGTH) {
    return collapsed;
  }
  return `${collapsed.slice(0, MAX_BACKLINK_SNIPPET_LENGTH - 3).trimEnd()}...`;
}

function extractMatchingLineSnippet(
  doc: NoteMarkdownDocument,
  targetKey: string,
  fallbackContent: string
): string {
  const candidateInlineLists: NoteMarkdownInline[][] = [];
  for (const block of doc.blocks) {
    switch (block.type) {
      case 'heading':
      case 'paragraph':
        candidateInlineLists.push(block.inlines);
        break;
      case 'bulletList':
        for (const item of block.items) {
          candidateInlineLists.push(item);
        }
        break;
      case 'orderedList':
        for (const item of block.items) {
          candidateInlineLists.push(item.inlines);
        }
        break;
      case 'checklist':
        for (const item of block.items) {
          candidateInlineLists.push(item.inlines);
        }
        break;
      case 'blockquote':
        for (const line of block.lines) {
          candidateInlineLists.push(line);
        }
        break;
      case 'codeBlock':
      case 'horizontalRule':
        break;
    }
  }

  for (const inlineList of candidateInlineLists) {
    if (!inlineListContainsTargetKey(inlineList, targetKey)) continue;
    const plain = inlinesToPlainText(inlineList);
    const subLines = plain
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line.length > 0);
    for (const subLine of subLines) {
      if (subLine.replace(/\s+/g, ' ').toLowerCase().includes(targetKey)) {
        return truncateSnippet(subLine);
      }
    }
    const truncated = truncateSnippet(plain);
    if (truncated) return truncated;
  }

  return truncateSnippet(markdownToPlainText(fallbackContent));
}

/**
 * Finds active notes containing at least one valid `[[Note Title]]` internal
 * link pointing to `targetNote`. Excludes self-links, archived notes, and
 * trashed notes, and returns no backlinks when `targetNote` itself is
 * archived, trashed, or untitled.
 */
export function findNoteBacklinks<T extends NoteLinkCandidateShape>(
  targetNote: Pick<
    NoteLinkCandidateShape,
    'id' | 'title' | 'isArchived' | 'isTrashed'
  > | null | undefined,
  notes: readonly T[]
): NoteBacklinkEntry<T>[] {
  if (!targetNote || !isNoteActive(targetNote)) {
    return [];
  }
  const targetKey = normalizeNoteLinkTitleKey(targetNote.title);
  if (!targetKey) {
    return [];
  }

  const backlinks: NoteBacklinkEntry<T>[] = [];
  const seenIds = new Set<string>();

  for (const candidate of notes) {
    if (candidate.id === targetNote.id) continue;
    if (seenIds.has(candidate.id)) continue;
    if (!isNoteActive(candidate)) continue;

    const doc = parseNoteMarkdown(candidate.content);
    const links: ParsedNoteInternalLink[] = [];
    for (const block of doc.blocks) {
      switch (block.type) {
        case 'heading':
        case 'paragraph':
          collectInternalLinksFromInlines(block.inlines, links);
          break;
        case 'bulletList':
          for (const item of block.items) {
            collectInternalLinksFromInlines(item, links);
          }
          break;
        case 'orderedList':
          for (const item of block.items) {
            collectInternalLinksFromInlines(item.inlines, links);
          }
          break;
        case 'checklist':
          for (const item of block.items) {
            collectInternalLinksFromInlines(item.inlines, links);
          }
          break;
        case 'blockquote':
          for (const line of block.lines) {
            collectInternalLinksFromInlines(line, links);
          }
          break;
        case 'codeBlock':
        case 'horizontalRule':
          break;
      }
    }

    const matchingCount = links.filter(
      (link) => link.normalizedKey === targetKey
    ).length;
    if (matchingCount === 0) continue;

    seenIds.add(candidate.id);
    backlinks.push({
      note: candidate,
      snippet: extractMatchingLineSnippet(doc, targetKey, candidate.content),
      linkCount: matchingCount,
    });
  }

  backlinks.sort((a, b) =>
    compareNotes(a.note, b.note, { sortBy: 'recent', pinFirst: false })
  );
  return backlinks;
}
