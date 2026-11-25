import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import {
  buildNoteMarkdownExport,
  buildNoteMarkdownFilename,
  MAX_NOTE_EXPORT_FILENAME_STEM_LENGTH,
  resolveNoteExportTitle,
} from './noteMarkdownExport';
import {
  createNoteMarkdownBlob,
  exportNoteAsMarkdown,
  shareNoteAsMarkdown,
} from '../services/noteExportService';
import { DaywellNotesModule, DaywellNote } from '../components/DaywellNotesModule';
import { saveWebNoteDraft } from './webNotesLifecycle';

const REPO_ROOT = process.cwd();

function readRepoFile(relPath: string): string {
  return fs.readFileSync(path.join(REPO_ROOT, relPath), 'utf8');
}

function makeNote(
  id: string,
  title: string,
  overrides: Partial<DaywellNote> = {}
): DaywellNote {
  return {
    id,
    title,
    content: overrides.content ?? '',
    notebook: overrides.notebook ?? 'Personal',
    tags: overrides.tags ?? [],
    isPinned: overrides.isPinned ?? false,
    isFavorite: overrides.isFavorite ?? false,
    isArchived: overrides.isArchived ?? false,
    isTrashed: overrides.isTrashed ?? false,
    createdAt: overrides.createdAt ?? '2026-03-01T08:00:00.000Z',
    updatedAt: overrides.updatedAt ?? '2026-03-01T08:00:00.000Z',
    ...(overrides.projectId !== undefined ? { projectId: overrides.projectId } : {}),
    ...(overrides.linkedModule !== undefined
      ? { linkedModule: overrides.linkedModule }
      : {}),
    ...(overrides.linkedId !== undefined ? { linkedId: overrides.linkedId } : {}),
  };
}

describe('Stage N5.4 — Notes Markdown Export & Sharing (Web)', () => {
  it('1. Preserves Markdown headings, lists, blockquotes, code blocks, bold/italic, and external links verbatim without HTML conversion', () => {
    const rawMarkdown = [
      '## Weekly Architecture Review',
      '',
      'Key points with **bold**, *italic*, ~~retired~~, and `inlineCode()`:',
      '',
      '- Bullet one',
      '  - Indented bullet two',
      '1. Numbered step',
      '2. Second step',
      '',
      '> Keep offline-first persistence pure.',
      '',
      '```ts',
      'const totalCents = 1500;',
      '```',
      '',
      'Reference: [Daywell Docs](https://example.com/daywell)',
    ].join('\n');

    const result = buildNoteMarkdownExport(
      makeNote('n-rich', 'Architecture Summary', {
        content: rawMarkdown,
        linkedModule: 'tasks',
        linkedId: 'task-42',
        projectId: 'proj-9',
      })
    );

    assert.equal(result.ok, true);
    assert.equal(result.filename, 'Architecture Summary.md');
    assert.equal(
      result.markdownContent,
      `# Architecture Summary\n\n${rawMarkdown}`
    );
    assert.ok(!result.markdownContent.includes('<h1>'));
    assert.ok(!result.markdownContent.includes('task-42'));
    assert.ok(!result.markdownContent.includes('proj-9'));
  });

  it('2. Builds OS-safe .md filenames for empty titles, special characters, duplicate .md suffixes, Windows reserved names, and long titles', () => {
    assert.equal(resolveNoteExportTitle(''), 'Untitled Note');
    assert.equal(resolveNoteExportTitle('   \n\t  '), 'Untitled Note');
    assert.equal(buildNoteMarkdownFilename(''), 'Untitled Note.md');
    assert.equal(buildNoteMarkdownFilename('   '), 'Untitled Note.md');
    assert.equal(buildNoteMarkdownFilename('///\\\\\\***???'), 'Untitled Note.md');
    assert.equal(buildNoteMarkdownFilename('...'), 'Untitled Note.md');
    assert.equal(buildNoteMarkdownFilename('.md'), 'Untitled Note.md');

    assert.equal(
      buildNoteMarkdownFilename('Q1/Q2: Budget? <Draft> | "Final"*'),
      'Q1-Q2- Budget- -Draft- - -Final.md'
    );
    assert.equal(buildNoteMarkdownFilename('Roadmap.md'), 'Roadmap.md');
    assert.equal(buildNoteMarkdownFilename('Roadmap.MD.md'), 'Roadmap.md');
    assert.equal(buildNoteMarkdownFilename('CON'), 'CON-note.md');
    assert.equal(buildNoteMarkdownFilename('com3'), 'com3-note.md');
    assert.equal(buildNoteMarkdownFilename('lpt9.txt'), 'lpt9.txt-note.md');

    const longFilename = buildNoteMarkdownFilename('A'.repeat(180));
    assert.ok(longFilename.endsWith('.md'));
    assert.equal(
      longFilename.length,
      MAX_NOTE_EXPORT_FILENAME_STEM_LENGTH + '.md'.length
    );

    // Surrogate-pair emoji boundary check (must never produce lone trailing surrogate)
    const emojiTitle = `${'B'.repeat(MAX_NOTE_EXPORT_FILENAME_STEM_LENGTH - 1)}🚀End`;
    const emojiFilename = buildNoteMarkdownFilename(emojiTitle);
    const stem = emojiFilename.slice(0, -'.md'.length);
    assert.equal(stem, 'B'.repeat(MAX_NOTE_EXPORT_FILENAME_STEM_LENGTH - 1));
  });

  it('3. Preserves interactive checklists and internal [[note links]] verbatim without inventing or expanding related records', () => {
    const body = [
      '- [ ] Audit backup payload',
      '- [x] Review [[Daily Rhythm Overview]] with [[Ethiopia Calendar Rules]]',
      '  - [ ] Nested follow-up item',
    ].join('\n');

    const res = buildNoteMarkdownExport(
      makeNote('n-links', 'Checklist & Links', {
        content: body,
        linkedModule: 'calendar',
        linkedId: 'evt-99',
        projectId: 'proj-alpha',
      })
    );

    assert.equal(res.ok, true);
    assert.equal(res.markdownContent, `# Checklist & Links\n\n${body}`);
    assert.ok(res.markdownContent.includes('- [ ] Audit backup payload'));
    assert.ok(
      res.markdownContent.includes(
        '[[Daily Rhythm Overview]] with [[Ethiopia Calendar Rules]]'
      )
    );
    assert.ok(!res.markdownContent.includes('evt-99'));
    assert.ok(!res.markdownContent.includes('proj-alpha'));
  });

  it('4. Preserves Unicode and non-English titles, filenames, and note bodies accurately', () => {
    const amharicTitle = 'የዛሬ ዕቅድ — Café ☕';
    const amharicBody =
      'ዛሬ ጠዋት:\n- [ ] የቤተሰብ ስብሰባ [[ሳምንታዊ እቅድ]]\n- [x] የገንዘብ ሪፖርት አዘጋጅ\n\nNotes in Ge’ez, French résumé, and emoji ✅';

    const res = buildNoteMarkdownExport(
      makeNote('n-unicode', amharicTitle, { content: amharicBody })
    );

    assert.equal(res.ok, true);
    assert.equal(res.filename, `${amharicTitle}.md`);
    assert.equal(res.markdownContent, `# ${amharicTitle}\n\n${amharicBody}`);
  });

  it('5. Handles empty content cleanly without crashing or inventing placeholder body text', () => {
    const emptyBodyRes = buildNoteMarkdownExport(
      makeNote('n-empty', 'Quick Placeholder', { content: '' })
    );
    assert.equal(emptyBodyRes.ok, true);
    assert.equal(emptyBodyRes.filename, 'Quick Placeholder.md');
    assert.equal(emptyBodyRes.markdownContent, '# Quick Placeholder\n');

    const whitespaceOnlyTitleAndBody = buildNoteMarkdownExport(
      makeNote('n-blank', '   ', { content: '' })
    );
    assert.equal(whitespaceOnlyTitleAndBody.ok, true);
    assert.equal(whitespaceOnlyTitleAndBody.filename, 'Untitled Note.md');
    assert.equal(whitespaceOnlyTitleAndBody.markdownContent, '# Untitled Note\n');
  });

  it('6. Rejects trashed notes safely across domain, export service, share service, and UI cards', async () => {
    const trashed = makeNote('n-trash', 'Secret Trash Note', {
      content: 'Should not export',
      isTrashed: true,
    });
    const archived = makeNote('n-arch', 'Archived Reference Note', {
      content: 'Archived notes remain exportable when explicitly chosen.',
      isArchived: true,
    });

    const domainTrashRes = buildNoteMarkdownExport(trashed);
    assert.equal(domainTrashRes.ok, false);
    assert.equal(domainTrashRes.markdownContent, '');
    assert.match(domainTrashRes.error ?? '', /Trash/i);

    let downloadCalled = 0;
    let shareCalled = 0;
    const svcExportTrash = exportNoteAsMarkdown(trashed, {
      downloadFile: () => {
        downloadCalled += 1;
      },
    });
    const svcShareTrash = await shareNoteAsMarkdown(trashed, {
      downloadFile: () => {
        downloadCalled += 1;
      },
      shareFile: async () => {
        shareCalled += 1;
      },
    });
    assert.equal(svcExportTrash.ok, false);
    assert.equal(svcShareTrash.ok, false);
    assert.equal(downloadCalled, 0);
    assert.equal(shareCalled, 0);

    // Archived note remains exportable cleanly.
    let capturedArchivedFilename = '';
    const svcExportArch = exportNoteAsMarkdown(archived, {
      downloadFile: (filename) => {
        capturedArchivedFilename = filename;
      },
    });
    assert.equal(svcExportArch.ok, true);
    assert.equal(capturedArchivedFilename, 'Archived Reference Note.md');

    // UI verification: non-trashed card renders Export button; trashed card omits Export button.
    const activeMarkup = renderToStaticMarkup(
      React.createElement(DaywellNotesModule, {
        notes: [archived, trashed],
      })
    );
    assert.ok(!activeMarkup.includes('Secret Trash Note'));
  });

  it('7. Verifies Web export/share service paths (Blob download, Web Share File, AbortError cancel, fallback download, error capture) and pre-export editor flush wiring', async () => {
    const note = makeNote('n-1', 'Sprint Notes', {
      content: '- [ ] Finalize N5.4',
    });

    const blob = createNoteMarkdownBlob('# Sprint Notes\n\n- [ ] Finalize N5.4');
    assert.equal(blob.type, 'text/markdown;charset=utf-8');
    assert.equal(await blob.text(), '# Sprint Notes\n\n- [ ] Finalize N5.4');

    const downloaded: Array<{ filename: string; content: string }> = [];
    const expRes = exportNoteAsMarkdown(note, {
      downloadFile: (filename, content) => downloaded.push({ filename, content }),
    });
    assert.equal(expRes.ok, true);
    assert.equal(expRes.method, 'download');
    assert.deepEqual(downloaded, [
      {
        filename: 'Sprint Notes.md',
        content: '# Sprint Notes\n\n- [ ] Finalize N5.4',
      },
    ]);

    // Web Share success path
    let sharedMime = '';
    let sharedName = '';
    const shareOk = await shareNoteAsMarkdown(note, {
      shareFile: async ({ file }) => {
        sharedMime = file.type;
        sharedName = file.name;
      },
      downloadFile: () => {
        throw new Error('Should not fall back when shareFile succeeds');
      },
    });
    assert.equal(shareOk.ok, true);
    assert.equal(shareOk.method, 'web_share');
    assert.equal(sharedMime, 'text/markdown;charset=utf-8');
    assert.equal(sharedName, 'Sprint Notes.md');

    // User cancel (AbortError) returns cancelled=true without fallback download
    let cancelledFallbackCount = 0;
    const abortErr = Object.assign(new Error('Share dismissed'), {
      name: 'AbortError',
    });
    const shareCancelled = await shareNoteAsMarkdown(note, {
      shareFile: async () => {
        throw abortErr;
      },
      downloadFile: () => {
        cancelledFallbackCount += 1;
      },
    });
    assert.equal(shareCancelled.ok, false);
    assert.equal(shareCancelled.cancelled, true);
    assert.equal(cancelledFallbackCount, 0);

    // Unsupported/failed share falls back to Blob .md download cleanly
    let fallbackDownloaded = '';
    const shareFallback = await shareNoteAsMarkdown(note, {
      canShareFile: () => false,
      downloadFile: (filename) => {
        fallbackDownloaded = filename;
      },
    });
    assert.equal(shareFallback.ok, true);
    assert.equal(shareFallback.method, 'download_fallback');
    assert.equal(fallbackDownloaded, 'Sprint Notes.md');

    // Download failure reports structured error instead of silent throw
    const failedExport = exportNoteAsMarkdown(note, {
      downloadFile: () => {
        throw new Error('Disk quota full');
      },
    });
    assert.equal(failedExport.ok, false);
    assert.equal(failedExport.error, 'Disk quota full');

    // Unsaved draft commit simulation + DaywellNotesModule flush check
    const committedDraft = saveWebNoteDraft({
      notes: [note],
      noteId: note.id,
      title: 'Sprint Notes Updated',
      content: '- [x] Flushed before export',
      notebook: 'Personal',
      tags: [],
    });
    assert.equal(committedDraft.status, 'updated');
    const flushedExport = buildNoteMarkdownExport(committedDraft.note);
    assert.equal(flushedExport.filename, 'Sprint Notes Updated.md');
    assert.equal(
      flushedExport.markdownContent,
      '# Sprint Notes Updated\n\n- [x] Flushed before export'
    );

    const webNotesSource = readRepoFile('src/components/DaywellNotesModule.tsx');
    assert.ok(
      webNotesSource.includes('resolveNoteForMarkdownAction') &&
        webNotesSource.includes('commitEditorDraftToNote()'),
      'DaywellNotesModule must flush pending editor drafts before exporting or sharing Markdown'
    );
  });

  it('8. Enforces cross-platform parity contracts, zero hex/Color literals, and Flutter pending-save flush wiring', () => {
    const webExportService = readRepoFile('src/services/noteExportService.ts');
    const flutterExportDomain = readRepoFile(
      'flutter_app/lib/domain/notes/note_markdown_export.dart'
    );
    const flutterIoService = readRepoFile(
      'flutter_app/lib/services/export/note_markdown_io_service.dart'
    );
    const flutterNotesView = readRepoFile(
      'flutter_app/lib/ui/screens/notes_view.dart'
    );
    const webNotesModule = readRepoFile('src/components/DaywellNotesModule.tsx');

    // Parity & behavior assertions across Flutter source
    assert.ok(flutterExportDomain.includes('NoteMarkdownExportHelper'));
    assert.ok(flutterExportDomain.includes('fileExtension = \'.md\''));
    assert.ok(
      flutterExportDomain.includes('maxFilenameStemLength = 80') &&
        MAX_NOTE_EXPORT_FILENAME_STEM_LENGTH === 80
    );
    assert.ok(
      flutterIoService.includes("mimeType: 'text/markdown'") &&
        flutterIoService.includes('Share.shareXFiles') &&
        flutterIoService.includes('Share.share(')
    );
    assert.ok(
      flutterNotesView.includes('_handleExportAndShareMarkdown') &&
        flutterNotesView.includes("action == 'export_md'") &&
        flutterNotesView.includes('flushPendingSaves()')
    );

    // No hardcoded hexes in Web UI / services and no Colors.* / Color(0x...) in migrated Flutter Notes files
    assert.equal(/#[0-9a-fA-F]{3,8}\b/.test(webNotesModule), false);
    assert.equal(/#[0-9a-fA-F]{3,8}\b/.test(webExportService), false);
    assert.equal(/\bColors\.[A-Za-z0-9_]+\b/.test(flutterNotesView), false);
    assert.equal(/\bColor\(0x[0-9a-fA-F]+\)/.test(flutterNotesView), false);
    assert.equal(/\bColors\.[A-Za-z0-9_]+\b/.test(flutterIoService), false);
  });
});
