import { isNoteTrashed, normalizeNoteTitle } from './noteHelpers';

export const NOTE_MARKDOWN_FILE_EXTENSION = '.md';
export const MAX_NOTE_EXPORT_FILENAME_STEM_LENGTH = 80;

export interface NoteMarkdownExportInput {
  id?: string;
  title?: string | null;
  content?: string | null;
  isTrashed?: boolean;
  isArchived?: boolean;
}

export interface NoteMarkdownExportResult {
  ok: boolean;
  resolvedTitle: string;
  filename: string;
  markdownContent: string;
  error?: string;
}

const WINDOWS_RESERVED_STEM_REGEX =
  /^(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$/i;
const ILLEGAL_FILENAME_CHARS_REGEX = /[\\/:*?"<>|\u0000-\u001F\u007F]/g;

function truncateUtf16Safely(value: string, maxLength: number): string {
  if (value.length <= maxLength) return value;
  if (maxLength <= 0) return '';
  let end = maxLength;
  const lastCode = value.charCodeAt(end - 1);
  if (lastCode >= 0xd800 && lastCode <= 0xdbff && end > 1) {
    end -= 1;
  }
  return value.slice(0, end);
}

function stripTrailingMarkdownExtension(stem: string): string {
  let current = stem.replace(/[\s\-]+$/g, '');
  while (current.toLowerCase().endsWith(NOTE_MARKDOWN_FILE_EXTENSION)) {
    current = current
      .slice(0, current.length - NOTE_MARKDOWN_FILE_EXTENSION.length)
      .replace(/[\s.\-]+$/g, '');
  }
  return current.replace(/^[\s.\-]+|[\s.\-]+$/g, '');
}

export function resolveNoteExportTitle(
  rawTitle: string | null | undefined
): string {
  return normalizeNoteTitle(rawTitle);
}

/**
 * Derives a filesystem-safe `.md` filename from a note title while preserving
 * Unicode/non-English characters (e.g. Amharic/Ge'ez) and guarding empty
 * titles, OS-forbidden characters, trailing dots, and reserved device names.
 */
export function buildNoteMarkdownFilename(
  rawTitle: string | null | undefined
): string {
  const baseTitle = resolveNoteExportTitle(rawTitle);

  let stem = baseTitle
    .replace(ILLEGAL_FILENAME_CHARS_REGEX, '-')
    .replace(/\s+/g, ' ')
    .replace(/-{2,}/g, '-');

  stem = stripTrailingMarkdownExtension(stem);

  if (!stem) {
    stem = 'Untitled Note';
  }

  if (WINDOWS_RESERVED_STEM_REGEX.test(stem)) {
    stem = `${stem}-note`;
  }

  stem = truncateUtf16Safely(stem, MAX_NOTE_EXPORT_FILENAME_STEM_LENGTH).replace(
    /[\s.\-]+$/g,
    ''
  );

  if (!stem) {
    stem = 'Untitled Note';
  }

  return `${stem}${NOTE_MARKDOWN_FILE_EXTENSION}`;
}

/**
 * Formats an individual Daywell Note as a standalone `.md` document while
 * failing closed on trashed notes and preserving Markdown checklists,
 * headings, `[[internal links]]`, Unicode text, and whitespace verbatim.
 */
export function buildNoteMarkdownExport(
  note: NoteMarkdownExportInput | null | undefined
): NoteMarkdownExportResult {
  if (!note) {
    return {
      ok: false,
      resolvedTitle: 'Untitled Note',
      filename: 'Untitled Note.md',
      markdownContent: '',
      error: 'Note is unavailable for export.',
    };
  }

  const resolvedTitle = resolveNoteExportTitle(note.title);
  const filename = buildNoteMarkdownFilename(resolvedTitle);

  if (isNoteTrashed({ isTrashed: Boolean(note.isTrashed) })) {
    return {
      ok: false,
      resolvedTitle,
      filename,
      markdownContent: '',
      error: 'Cannot export a note in Trash. Restore it from Trash first.',
    };
  }

  const rawContent = typeof note.content === 'string' ? note.content : '';
  const markdownContent =
    rawContent.length === 0
      ? `# ${resolvedTitle}\n`
      : `# ${resolvedTitle}\n\n${rawContent}`;

  return {
    ok: true,
    resolvedTitle,
    filename,
    markdownContent,
  };
}
