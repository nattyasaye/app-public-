import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { matchesNoteSearchQuery } from './noteHelpers';
import {
  filterAndSortWebNotes,
  moveWebNoteToNotebook,
  moveWebNoteToTrash,
  restoreWebNoteFromTrash,
  saveWebNoteDraft,
  toggleWebNoteArchive,
} from './webNotesLifecycle';
import { getAvailableNotesToLink, TaskNoteRecord } from './taskNotes';
import {
  DaywellNotesModule,
  DEFAULT_SAMPLE_NOTES,
} from '../components/DaywellNotesModule';

const REPO_ROOT = process.cwd();

function readRepoFile(relPath: string): string {
  return fs.readFileSync(path.join(REPO_ROOT, relPath), 'utf8');
}

function buildSeedNotes(): TaskNoteRecord[] {
  return [
    {
      id: 'n-active-1',
      title: 'Portfolio Design Notes',
      content:
        '## Narrative\n- **Simplicity** vs *Power* trade-offs.\n- [ ] Verify offline search',
      notebook: 'work_projects',
      tags: ['architecture', 'UX'],
      isPinned: true,
      isArchived: false,
      isFavorite: false,
      isTrashed: false,
      createdAt: '2026-03-01T08:00:00.000Z',
      updatedAt: '2026-03-02T09:00:00.000Z',
    },
    {
      id: 'n-amharic',
      title: 'የዓመት ዕቅድ ማስታወሻ',
      content: 'በየቀኑ 20 ደቂቃ የእግር ጉዞ።',
      notebook: 'Reflections',
      tags: ['ethiopian_calendar'],
      isPinned: false,
      isArchived: false,
      isFavorite: true,
      isTrashed: false,
      createdAt: '2026-03-01T08:00:00.000Z',
      updatedAt: '2026-03-01T10:00:00.000Z',
    },
    {
      id: 'n-archived',
      title: 'Archived Tax Checklist',
      content: 'Annual ETB tax summary',
      notebook: 'Finances',
      tags: ['tax'],
      isPinned: false,
      isArchived: true,
      isFavorite: false,
      isTrashed: false,
      createdAt: '2026-02-20T08:00:00.000Z',
      updatedAt: '2026-02-21T08:00:00.000Z',
    },
    {
      id: 'n-trashed',
      title: 'Trashed Portfolio Secret',
      content: 'Simplicity vs Power inside trash',
      notebook: 'work_projects',
      tags: ['architecture'],
      isPinned: false,
      isArchived: false,
      isFavorite: false,
      isTrashed: true,
      createdAt: '2026-02-15T08:00:00.000Z',
      updatedAt: '2026-02-16T08:00:00.000Z',
    },
  ];
}

describe('STAGE N4.1 — NOTES INTEGRATION WITH SHARED DAYWELL SEARCH', () => {
  it('1. matchesNoteSearchQuery searches titles, Amharic text, Markdown-spanning content phrases, formatted folders, and #tags', () => {
    const notes = buildSeedNotes();
    const active = notes[0];
    const amharic = notes[1];

    // Title
    assert.strictEqual(matchesNoteSearchQuery(active, 'portfolio design'), true);
    assert.strictEqual(matchesNoteSearchQuery(amharic, 'ዕቅድ'), true);

    // Content phrase across inline Markdown (**Simplicity** vs *Power*)
    assert.strictEqual(
      matchesNoteSearchQuery(active, 'simplicity vs power'),
      true
    );

    // Folder (raw & space-formatted)
    assert.strictEqual(matchesNoteSearchQuery(active, 'work_projects'), true);
    assert.strictEqual(matchesNoteSearchQuery(active, 'Work Projects'), true);

    // Tags (bare & #tag prefix)
    assert.strictEqual(matchesNoteSearchQuery(active, 'architecture'), true);
    assert.strictEqual(matchesNoteSearchQuery(active, '#architecture'), true);
    assert.strictEqual(matchesNoteSearchQuery(active, '#ux'), true);

    // Non-matching query
    assert.strictEqual(matchesNoteSearchQuery(active, 'nonexistent_xyz'), false);
  });

  it('2. filterAndSortWebNotes & getAvailableNotesToLink exclude Trash, preserve Archive visibility, and reflect edits/renames/folder moves immediately', () => {
    let notes = buildSeedNotes();

    // Active tab search matches across title/content/folder/tags while excluding archive & trash
    const activeSearch = filterAndSortWebNotes(notes, {
      activeTab: 'all',
      searchQuery: 'Simplicity vs Power',
    });
    assert.deepStrictEqual(
      activeSearch.map((n) => n.id),
      ['n-active-1']
    );

    const byHashTag = filterAndSortWebNotes(notes, {
      activeTab: 'all',
      searchQuery: '#architecture',
    });
    assert.deepStrictEqual(
      byHashTag.map((n) => n.id),
      ['n-active-1']
    );

    const byFolder = filterAndSortWebNotes(notes, {
      activeTab: 'all',
      searchQuery: 'Work Projects',
    });
    assert.deepStrictEqual(
      byFolder.map((n) => n.id),
      ['n-active-1']
    );

    // Archive tab preserves archived search visibility; ordinary active search excludes archive & trash
    const archivedHits = filterAndSortWebNotes(notes, {
      activeTab: 'archived',
      searchQuery: 'tax checklist',
    });
    assert.deepStrictEqual(
      archivedHits.map((n) => n.id),
      ['n-archived']
    );

    // Task-note linking picker searches folder + #tag while excluding Trash and already-linked notes
    const linkOptions = getAvailableNotesToLink(notes, 'task-9', '#tax');
    assert.deepStrictEqual(
      linkOptions.map((o) => o.note.id),
      ['n-archived']
    );
    assert.strictEqual(
      getAvailableNotesToLink(notes, 'task-9', 'Trashed Portfolio').length,
      0
    );

    // Dynamic rename + folder move + archive + trash + restore
    const renamed = saveWebNoteDraft({
      notes,
      noteId: 'n-active-1',
      title: 'Renamed Architecture Handbook',
      content: notes[0].content,
      notebook: notes[0].notebook,
      tags: ['architecture', 'handbook'],
    });
    assert.strictEqual(renamed.status, 'updated');
    notes = renamed.notes;

    const moved = moveWebNoteToNotebook(notes, 'n-active-1', 'Strategy Docs');
    assert.strictEqual(moved.ok, true);
    notes = moved.notes;

    assert.strictEqual(
      filterAndSortWebNotes(notes, {
        activeTab: 'all',
        searchQuery: 'Portfolio Design Notes',
      }).length,
      0
    );
    assert.deepStrictEqual(
      filterAndSortWebNotes(notes, {
        activeTab: 'all',
        searchQuery: 'Strategy Docs',
      }).map((n) => n.id),
      ['n-active-1']
    );

    const archived = toggleWebNoteArchive(notes, 'n-active-1');
    notes = archived.notes;
    assert.strictEqual(
      filterAndSortWebNotes(notes, {
        activeTab: 'all',
        searchQuery: 'Renamed Architecture',
      }).length,
      0
    );
    assert.deepStrictEqual(
      filterAndSortWebNotes(notes, {
        activeTab: 'archived',
        searchQuery: 'Renamed Architecture',
      }).map((n) => n.id),
      ['n-active-1']
    );

    const trashed = moveWebNoteToTrash(notes, 'n-active-1');
    notes = trashed.notes;
    assert.strictEqual(
      filterAndSortWebNotes(notes, {
        activeTab: 'archived',
        searchQuery: 'Renamed Architecture',
      }).length,
      0
    );

    const restored = restoreWebNoteFromTrash(notes, 'n-active-1');
    notes = restored.notes;
    assert.deepStrictEqual(
      filterAndSortWebNotes(notes, {
        activeTab: 'archived',
        searchQuery: 'Renamed Architecture',
      }).map((n) => n.id),
      ['n-active-1']
    );
  });

  it('3. Web DaywellNotesModule mounts cleanly in SSR (with isActive prop) and enforces deleted-note guard, filter alignment, and tab/search flush contracts', () => {
    const html = renderToStaticMarkup(
      React.createElement(DaywellNotesModule, {
        notes: DEFAULT_SAMPLE_NOTES,
        onUpdateNotes: () => {},
        tasks: [],
        isActive: false,
        layoutMode: 'auto',
      })
    );
    assert.ok(html.includes('Notes &amp; knowledge'));

    const webModule = readRepoFile('src/components/DaywellNotesModule.tsx');
    const webApp = readRepoFile('src/App.tsx');

    // App passes isActive so leaving Notes flushes active editor draft
    assert.ok(webApp.includes("isActive={activeScreen === 'notes'}"));
    assert.ok(webModule.includes('prevIsActiveRef'));
    assert.ok(webModule.includes('if (wasActive && !isActive && isEditorOpen)'));

    // requestedNoteFocus guards missing/deleted notes cleanly & clears conflicting filters
    assert.ok(webModule.includes("'This note is no longer available.'"));
    assert.ok(webModule.includes('matchesNoteSearchQuery(target, searchQuery'));
    assert.ok(
      webModule.includes('autosaveTimeoutRef.current !== null') &&
        webModule.includes('!isCurrentNewDraftBlank')
    );

    // Zero hardcoded hex literals introduced
    assert.strictEqual(/#[0-9a-fA-F]{3,8}\b/.test(webModule), false);
  });

  it('4. Flutter DriftSearchRepository, NotesView, and MainDaywellScreen uphold Stage N4.1 search, snippet, lifecycle, navigation, and flush invariants', () => {
    const searchRepoSrc = readRepoFile(
      'flutter_app/lib/data/repositories/search_repository.dart'
    );
    const notesViewSrc = readRepoFile('flutter_app/lib/ui/screens/notes_view.dart');
    const mainSrc = readRepoFile('flutter_app/lib/main.dart');
    const dartTestSrc = readRepoFile(
      'flutter_app/test/stage_n41_notes_shared_search_test.dart'
    );

    // Shared search uses pure domain matcher, strips Markdown cleanly, labels Notes, excludes Trash
    assert.ok(searchRepoSrc.includes('NoteDomainHelpers.matchesNoteSearchQuery'));
    assert.ok(searchRepoSrc.includes('NoteDomainHelpers.normalizeTitle(note.title)'));
    assert.ok(searchRepoSrc.includes('NoteDomainHelpers.formatFolderLabel(note.category)'));
    assert.ok(searchRepoSrc.includes('NoteMarkdownParser.toPlainText(note.content)'));
    assert.ok(searchRepoSrc.includes('tbl.isTrashed.equals(false)'));
    assert.ok(searchRepoSrc.includes("'Note • \$folderLabel"));

    // NotesView requestedNoteFocus & tab-leave flush & narrow route replacement
    assert.ok(notesViewSrc.includes('onRegisterPendingSaveFlush'));
    assert.ok(notesViewSrc.includes('_flushActiveEditorEdits'));
    assert.ok(notesViewSrc.includes('_handleRequestedNoteFocus'));
    assert.ok(notesViewSrc.includes('This note is no longer available.'));
    assert.ok(notesViewSrc.includes('replaceActiveRoute: true'));
    assert.ok(mainSrc.includes('_onShellNavigationChanged'));
    assert.ok(mainSrc.includes('_flushNotesPendingEdits = handler'));

    // Stage N4.1 Dart test exists covering all scenarios
    assert.ok(dartTestSrc.includes('DriftSearchRepository'));
    assert.ok(dartTestSrc.includes('simplicity vs power'));
    assert.ok(dartTestSrc.includes('#architecture'));
    assert.ok(dartTestSrc.includes('Work Projects'));
    assert.ok(dartTestSrc.includes('Flushed on tab leave'));

    // Zero raw Color(0x...) or disallowed Colors.* in modified Flutter UI files
    for (const src of [notesViewSrc, mainSrc]) {
      assert.strictEqual(/Color\(\s*0x/i.test(src), false);
      const materialColors = (
        src.match(/\bColors\.[a-zA-Z0-9_]+/g) || []
      ).filter((m) => m !== 'Colors.transparent');
      assert.strictEqual(materialColors.length, 0);
    }
  });
});
