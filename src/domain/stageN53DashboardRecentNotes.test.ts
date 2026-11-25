import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import {
  buildDashboardRecentNotesSummary,
  DEFAULT_DASHBOARD_RECENT_NOTES_LIMIT,
  formatReadableNoteDate,
  getNoteContentPreview,
} from './noteHelpers';
import { TaskNoteRecord } from './taskNotes';
import {
  moveWebNoteToTrash,
  restoreWebNoteFromTrash,
  saveWebNoteDraft,
  toggleWebNoteArchive,
} from './webNotesLifecycle';
import { DashboardRecentNotesSection } from '../components/notes/DashboardRecentNotesSection';

const REPO_ROOT = process.cwd();

function readRepoFile(relPath: string): string {
  return fs.readFileSync(path.join(REPO_ROOT, relPath), 'utf8');
}

function makeNote(
  id: string,
  title: string,
  overrides: Partial<TaskNoteRecord> = {}
): TaskNoteRecord {
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
    ...(overrides.projectId !== undefined
      ? { projectId: overrides.projectId }
      : {}),
    ...(overrides.linkedModule !== undefined
      ? { linkedModule: overrides.linkedModule }
      : {}),
    ...(overrides.linkedId !== undefined
      ? { linkedId: overrides.linkedId }
      : {}),
  };
}

describe('Stage N5.3 — Dashboard Recent Notes Integration', () => {
  it('1. Orders recent notes strictly by updatedAt descending (never letting older pinned notes jump ahead) and limits count cleanly', () => {
    const notes: TaskNoteRecord[] = [
      makeNote('n-old-pin', 'Older Pinned Note', {
        isPinned: true,
        updatedAt: '2026-03-10T09:00:00.000Z',
        content: 'Pinned earlier in the month',
      }),
      makeNote('n-1', 'Latest Note', {
        updatedAt: '2026-03-18T15:00:00.000Z',
        content: 'Most recent edit',
      }),
      makeNote('n-2', 'Second Most Recent', {
        updatedAt: '2026-03-17T12:00:00.000Z',
        content: 'Second edit',
      }),
      makeNote('n-3', 'Third Recent', {
        updatedAt: '2026-03-15T10:00:00.000Z',
        content: 'Third edit',
      }),
      makeNote('n-4', 'Fourth Recent', {
        updatedAt: '2026-03-12T10:00:00.000Z',
        content: 'Fourth edit',
      }),
    ];

    const summary = buildDashboardRecentNotesSummary(notes);
    assert.equal(summary.totalActiveCount, 5);
    assert.equal(summary.archivedCount, 0);
    assert.equal(
      summary.recentNotes.length,
      DEFAULT_DASHBOARD_RECENT_NOTES_LIMIT
    );
    assert.deepEqual(
      summary.recentNotes.map((n) => n.id),
      ['n-1', 'n-2', 'n-3', 'n-4']
    );
  });

  it('2. Excludes trashed and archived notes consistently while tracking archivedCount and deduplicating duplicate IDs', () => {
    const notes: TaskNoteRecord[] = [
      makeNote('n-dup', 'Stale Copy', {
        updatedAt: '2026-03-02T08:00:00.000Z',
        content: 'Old copy',
      }),
      makeNote('n-dup', 'Fresh Copy', {
        updatedAt: '2026-03-19T11:00:00.000Z',
        content: 'Newest copy should win',
      }),
      makeNote('n-trashed', 'Deleted Note', {
        isTrashed: true,
        updatedAt: '2026-03-20T12:00:00.000Z',
        content: 'Should never appear',
      }),
      makeNote('n-trashed-arch', 'Trashed & Archived Note', {
        isArchived: true,
        isTrashed: true,
        updatedAt: '2026-03-21T12:00:00.000Z',
      }),
      makeNote('n-archived', 'Archived Summary', {
        isArchived: true,
        updatedAt: '2026-03-22T12:00:00.000Z',
      }),
      makeNote('n-active', 'Active Brief', {
        updatedAt: '2026-03-14T08:00:00.000Z',
      }),
    ];

    const summary = buildDashboardRecentNotesSummary(notes);
    assert.equal(summary.totalActiveCount, 2);
    assert.equal(summary.archivedCount, 1);
    assert.deepEqual(
      summary.recentNotes.map((n) => ({ id: n.id, title: n.title })),
      [
        { id: 'n-dup', title: 'Fresh Copy' },
        { id: 'n-active', title: 'Active Brief' },
      ]
    );
  });

  it('3. Strips Markdown formatting for previews and formats readable Ethiopia-civil dates', () => {
    const preview = getNoteContentPreview(
      '# Weekly Review\n- [x] Shipped **N5.3** preview\n- Follow up on [[Design Tokens]]\n\nExtra   whitespace',
      120
    );
    assert.ok(!preview.includes('# '));
    assert.ok(!preview.includes('**'));
    assert.ok(preview.includes('Weekly Review'));
    assert.ok(preview.includes('Shipped N5.3 preview'));

    const truncated = getNoteContentPreview('A'.repeat(200), 60);
    assert.ok(truncated.length <= 60);
    assert.ok(truncated.endsWith('…'));

    assert.equal(
      formatReadableNoteDate(
        '2026-03-15T10:00:00.000Z',
        new Date('2026-03-20T09:00:00.000Z')
      ),
      'Mar 15'
    );
    assert.equal(
      formatReadableNoteDate(
        '2025-11-04T10:00:00.000Z',
        new Date('2026-03-20T09:00:00.000Z')
      ),
      'Nov 4, 2025'
    );
  });

  it('4. Renders DashboardRecentNotesSection with Recent Notes cards, stripped previews, Updated date, All Notes CTA, and overflow CTA', () => {
    const notes: TaskNoteRecord[] = [
      makeNote('n-1', 'Spring Planning', {
        isPinned: true,
        notebook: 'Work',
        content: '## Goals\nAlign **Milestones** with team.',
        updatedAt: '2026-03-19T14:00:00.000Z',
      }),
      makeNote('n-2', 'Reading List', {
        notebook: 'Study',
        content: '',
        updatedAt: '2026-03-18T10:00:00.000Z',
      }),
      makeNote('n-3', 'Grocery Checklist', {
        content: '- [ ] Coffee\n- [x] Milk',
        updatedAt: '2026-03-17T10:00:00.000Z',
      }),
      makeNote('n-4', 'Idea Scratchpad', {
        content: 'Offline-first sync notes',
        updatedAt: '2026-03-16T10:00:00.000Z',
      }),
      makeNote('n-5', 'Overflow Fifth Note', {
        content: 'Should trigger + 1 more note',
        updatedAt: '2026-03-15T10:00:00.000Z',
      }),
      makeNote('n-arch', 'Hidden Archived Note', {
        isArchived: true,
        updatedAt: '2026-03-20T10:00:00.000Z',
      }),
      makeNote('n-trash', 'Hidden Trashed Note', {
        isTrashed: true,
        updatedAt: '2026-03-21T10:00:00.000Z',
      }),
    ];

    const html = renderToStaticMarkup(
      React.createElement(DashboardRecentNotesSection, {
        notes,
        onOpenNote: () => {},
        onOpenAllNotes: () => {},
      })
    );

    assert.match(html, /Recent Notes/);
    assert.match(html, /All Notes/);
    assert.match(html, /Spring Planning/);
    assert.match(html, /Goals Align Milestones with team\./);
    assert.match(html, /Updated /);
    assert.match(html, /Work/);
    assert.match(html, /\+ 1 more note/);
    assert.ok(!html.includes('Overflow Fifth Note'));
    assert.ok(!html.includes('Hidden Archived Note'));
    assert.ok(!html.includes('Hidden Trashed Note'));
  });

  it('5. Renders useful empty states for empty Notes collections and Archive-only Notes collections', () => {
    const emptyHtml = renderToStaticMarkup(
      React.createElement(DashboardRecentNotesSection, {
        notes: [],
        onOpenNote: () => {},
        onOpenAllNotes: () => {},
      })
    );
    assert.match(emptyHtml, /Recent Notes/);
    assert.match(emptyHtml, /No active notes yet/);
    assert.match(emptyHtml, /Open Notes/);
    assert.match(emptyHtml, /Capture ideas, references, and reflections in Notes\./);

    const archiveOnlyHtml = renderToStaticMarkup(
      React.createElement(DashboardRecentNotesSection, {
        notes: [
          makeNote('n-arch', 'Only Archived', {
            isArchived: true,
            updatedAt: '2026-03-20T09:00:00.000Z',
          }),
        ],
        onOpenNote: () => {},
        onOpenAllNotes: () => {},
      })
    );
    assert.match(archiveOnlyHtml, /No active notes yet/);
    assert.match(
      archiveOnlyHtml,
      /All recorded notes are archived\. Open Notes to view your Archive\./
    );
  });

  it('6. Reflects live note lifecycle changes (create, edit, archive, unarchive, trash, restore) immediately', () => {
    let notes: TaskNoteRecord[] = [];
    assert.equal(buildDashboardRecentNotesSummary(notes).recentNotes.length, 0);

    // Create two notes
    const create1 = saveWebNoteDraft({
      notes,
      noteId: null,
      title: 'Alpha Note',
      content: 'First draft',
      notebook: 'Personal',
      tags: [],
      nowUtc: new Date('2026-03-10T09:00:00.000Z'),
    });
    assert.equal(create1.status, 'created');
    notes = create1.notes;
    const alphaId = create1.note!.id;

    const create2 = saveWebNoteDraft({
      notes,
      noteId: null,
      title: 'Beta Note',
      content: 'Newer note',
      notebook: 'Work',
      tags: [],
      nowUtc: new Date('2026-03-11T09:00:00.000Z'),
    });
    assert.equal(create2.status, 'created');
    notes = create2.notes;
    const betaId = create2.note!.id;

    assert.deepEqual(
      buildDashboardRecentNotesSummary(notes).recentNotes.map((n) => n.id),
      [betaId, alphaId]
    );

    // Editing Alpha bumps it ahead of Beta with updated title & preview
    const editAlpha = saveWebNoteDraft({
      notes,
      noteId: alphaId,
      title: 'Alpha Note Revised',
      content: '**Updated** insights ready',
      notebook: 'Personal',
      tags: [],
      nowUtc: new Date('2026-03-12T09:00:00.000Z'),
    });
    assert.equal(editAlpha.status, 'updated');
    notes = editAlpha.notes;
    const afterEdit = buildDashboardRecentNotesSummary(notes);
    assert.deepEqual(
      afterEdit.recentNotes.map((n) => n.id),
      [alphaId, betaId]
    );
    assert.equal(afterEdit.recentNotes[0].title, 'Alpha Note Revised');
    assert.equal(
      getNoteContentPreview(afterEdit.recentNotes[0].content),
      'Updated insights ready'
    );

    // Archiving Alpha hides it from active Recent Notes; unarchiving brings it back
    notes = toggleWebNoteArchive(
      notes,
      alphaId,
      new Date('2026-03-13T09:00:00.000Z')
    ).notes;
    assert.deepEqual(
      buildDashboardRecentNotesSummary(notes).recentNotes.map((n) => n.id),
      [betaId]
    );
    assert.equal(buildDashboardRecentNotesSummary(notes).archivedCount, 1);

    notes = toggleWebNoteArchive(
      notes,
      alphaId,
      new Date('2026-03-14T09:00:00.000Z')
    ).notes;
    assert.deepEqual(
      buildDashboardRecentNotesSummary(notes).recentNotes.map((n) => n.id),
      [alphaId, betaId]
    );

    // Trashing Alpha hides it; restoring brings it back
    notes = moveWebNoteToTrash(
      notes,
      alphaId,
      new Date('2026-03-15T09:00:00.000Z')
    ).notes;
    assert.deepEqual(
      buildDashboardRecentNotesSummary(notes).recentNotes.map((n) => n.id),
      [betaId]
    );

    notes = restoreWebNoteFromTrash(
      notes,
      alphaId,
      new Date('2026-03-16T09:00:00.000Z')
    ).notes;
    assert.deepEqual(
      buildDashboardRecentNotesSummary(notes).recentNotes.map((n) => n.id),
      [alphaId, betaId]
    );
  });

  it('7. Verifies Web & Flutter direct-navigation wiring, pending-edit flushing, and Daywell UI token compliance', () => {
    const webSection = readRepoFile(
      'src/components/notes/DashboardRecentNotesSection.tsx'
    );
    const appTsx = readRepoFile('src/App.tsx');
    const notesModule = readRepoFile('src/components/DaywellNotesModule.tsx');
    const flutterDashboard = readRepoFile(
      'flutter_app/lib/ui/screens/dashboard_view.dart'
    );
    const flutterMain = readRepoFile('flutter_app/lib/main.dart');
    const flutterHelpers = readRepoFile(
      'flutter_app/lib/domain/notes/note_helpers.dart'
    );

    // Web: zero hardcoded hexes, wires onOpenNote -> setRequestedNoteFocus + navigateTo('notes')
    assert.equal(/#[0-9a-fA-F]{3,8}\b/.test(webSection), false);
    assert.match(appTsx, /<DashboardRecentNotesSection/);
    assert.match(appTsx, /setRequestedNoteFocus\(\{\s*noteId,\s*nonce:/);
    assert.match(appTsx, /navigateTo\('notes'\)/);

    // Web DaywellNotesModule flushes edits on requestedNoteFocus & isActive transitions
    assert.match(notesModule, /requestedNoteFocus/);
    assert.match(notesModule, /commitEditorDraftToNote/);

    // Flutter: parity helpers, recency summary, direct note opening, zero Colors.* / Color(0x...)
    assert.match(flutterHelpers, /buildDashboardRecentNotesSummary/);
    assert.match(flutterHelpers, /buildContentPreview/);
    assert.match(
      flutterDashboard,
      /NoteDomainHelpers\.buildDashboardRecentNotesSummary/
    );
    assert.match(flutterDashboard, /onOpenNote!\(recentNotes\[i\]\.id\)/);
    assert.equal(/\bColors\./.test(flutterDashboard), false);
    assert.equal(/\bColor\(0x/i.test(flutterDashboard), false);
    assert.match(flutterMain, /case DaywellTabId\.today:[\s\S]*onOpenNote:/);
    assert.match(flutterMain, /_flushNotesPendingEdits/);
  });
});
