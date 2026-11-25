import {
  buildNoteMarkdownExport,
  NoteMarkdownExportInput,
} from '../domain/noteMarkdownExport';
import { DataPortabilityService } from './dataPortabilityService';

export interface NoteMarkdownActionResult {
  ok: boolean;
  filename: string;
  markdownContent: string;
  method: 'download' | 'web_share' | 'download_fallback' | 'none';
  cancelled?: boolean;
  error?: string;
}

export interface NoteMarkdownDownloadOptions {
  downloadFile?: (filename: string, markdownContent: string) => void;
}

export interface NoteMarkdownShareOptions extends NoteMarkdownDownloadOptions {
  shareFile?: (params: {
    file: File;
    title: string;
    filename: string;
    markdownContent: string;
  }) => Promise<void>;
  canShareFile?: (file: File) => boolean;
}

export function createNoteMarkdownBlob(markdownContent: string): Blob {
  return new Blob([markdownContent], {
    type: 'text/markdown;charset=utf-8',
  });
}

export function downloadNoteMarkdownFile(
  filename: string,
  markdownContent: string
): void {
  const blob = createNoteMarkdownBlob(markdownContent);
  DataPortabilityService.triggerDownload(blob, filename);
}

function isAbortError(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'name' in error &&
    (error as { name?: unknown }).name === 'AbortError'
  );
}

function getErrorMessage(error: unknown, fallback: string): string {
  if (error instanceof Error && error.message.trim().length > 0) {
    return error.message;
  }
  return fallback;
}

export function exportNoteAsMarkdown(
  note: NoteMarkdownExportInput | null | undefined,
  options?: NoteMarkdownDownloadOptions
): NoteMarkdownActionResult {
  const prepared = buildNoteMarkdownExport(note);
  if (!prepared.ok) {
    return {
      ok: false,
      filename: prepared.filename,
      markdownContent: '',
      method: 'none',
      error: prepared.error || 'Unable to export note as Markdown.',
    };
  }

  const downloader = options?.downloadFile ?? downloadNoteMarkdownFile;
  try {
    downloader(prepared.filename, prepared.markdownContent);
    return {
      ok: true,
      filename: prepared.filename,
      markdownContent: prepared.markdownContent,
      method: 'download',
    };
  } catch (error) {
    return {
      ok: false,
      filename: prepared.filename,
      markdownContent: prepared.markdownContent,
      method: 'none',
      error: getErrorMessage(error, `Unable to download "${prepared.filename}".`),
    };
  }
}

export async function shareNoteAsMarkdown(
  note: NoteMarkdownExportInput | null | undefined,
  options?: NoteMarkdownShareOptions
): Promise<NoteMarkdownActionResult> {
  const prepared = buildNoteMarkdownExport(note);
  if (!prepared.ok) {
    return {
      ok: false,
      filename: prepared.filename,
      markdownContent: '',
      method: 'none',
      error: prepared.error || 'Unable to share note as Markdown.',
    };
  }

  const downloader = options?.downloadFile ?? downloadNoteMarkdownFile;
  const hasCustomSharer = typeof options?.shareFile === 'function';
  const hasNativeShare =
    typeof navigator !== 'undefined' && typeof navigator.share === 'function';

  if ((hasCustomSharer || hasNativeShare) && typeof File !== 'undefined') {
    const file = new File([prepared.markdownContent], prepared.filename, {
      type: 'text/markdown;charset=utf-8',
    });

    const canShare =
      typeof options?.canShareFile === 'function'
        ? options.canShareFile(file)
        : hasCustomSharer
          ? true
          : typeof navigator.canShare === 'function'
            ? navigator.canShare({ files: [file] })
            : false;

    if (canShare) {
      try {
        if (options?.shareFile) {
          await options.shareFile({
            file,
            title: prepared.resolvedTitle,
            filename: prepared.filename,
            markdownContent: prepared.markdownContent,
          });
        } else {
          await navigator.share({
            files: [file],
            title: prepared.resolvedTitle,
          });
        }
        return {
          ok: true,
          filename: prepared.filename,
          markdownContent: prepared.markdownContent,
          method: 'web_share',
        };
      } catch (error) {
        if (isAbortError(error)) {
          return {
            ok: false,
            filename: prepared.filename,
            markdownContent: prepared.markdownContent,
            method: 'web_share',
            cancelled: true,
          };
        }
      }
    }
  }

  try {
    downloader(prepared.filename, prepared.markdownContent);
    return {
      ok: true,
      filename: prepared.filename,
      markdownContent: prepared.markdownContent,
      method: 'download_fallback',
    };
  } catch (error) {
    return {
      ok: false,
      filename: prepared.filename,
      markdownContent: prepared.markdownContent,
      method: 'none',
      error: getErrorMessage(error, `Unable to share "${prepared.filename}".`),
    };
  }
}
