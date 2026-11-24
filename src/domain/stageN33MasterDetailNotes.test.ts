import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import {
  DaywellNotesModule,
  DEFAULT_SAMPLE_NOTES,
} from '../components/DaywellNotesModule';

const REPO_ROOT = process.cwd();

function readRepoFile(relPath: string): string {
  return fs.readFileSync(path.join(REPO_ROOT, relPath), 'utf8');
}

describe('STAGE N3.3 — RESPONSIVE MASTER-DETAIL NOTES EXPERIENCE', () => {
  const webModulePath = 'src/components/DaywellNotesModule.tsx';
  const webAppPath = 'src/App.tsx';
  const flutterNotesPath = 'flutter_app/lib/ui/screens/notes_view.dart';
  const flutterTestPath =
    'flutter_app/test/stage_n33_master_detail_notes_test.dart';

  it('1. Web DaywellNotesModule implements responsive master-detail gating via ResizeObserver & compact layoutMode override without hardcoded hex literals', () => {
    const webModule = readRepoFile(webModulePath);
    const webApp = readRepoFile(webAppPath);

    // Compact override from App.tsx keeps Phone / Side-by-Side (390px) single-pane
    assert.ok(webModule.includes("layoutMode?: 'auto' | 'compact'"));
    assert.ok(
      webApp.includes("layoutMode={viewMode === 'desktop' ? 'auto' : 'compact'}")
    );

    // Uses canonical 840px expanded breakpoint & 720px detail max-width
    assert.ok(
      webModule.includes('SHARED_DESIGN_TOKENS.breakpoints.expanded')
    );
    assert.ok(webModule.includes('ResizeObserver'));
    assert.ok(webModule.includes('max-w-[720px]'));
    assert.ok(webModule.includes('notes-master-detail-layout'));
    assert.ok(webModule.includes('notes-detail-empty-state'));
    assert.ok(webModule.includes('Select a note to read or edit'));

    // Single shared editor panel (not duplicated JSX) & selected-card highlight
    const titleInputMatches =
      webModule.match(/placeholder="Note Title"/g) ?? [];
    assert.strictEqual(titleInputMatches.length, 1);
    assert.ok(webModule.includes('data-selected={isCardSelected'));
    assert.ok(webModule.includes("variant={isCardSelected ? 'primaryContainer' : 'default'}"));

    // Zero hardcoded hex literals
    assert.strictEqual(/#[0-9a-fA-F]{3,8}\b/.test(webModule), false);
  });

  it('2. Web DaywellNotesModule enforces pre-switch draft flush, same-note guard, filter preservation, and deletion cleanup', () => {
    const webModule = readRepoFile(webModulePath);

    // openEditor checks same-note re-click and flushes pending draft before switching
    const openEditorMatch = webModule.match(
      /const openEditor = \([\s\S]*?\n  \};/
    );
    assert.ok(openEditorMatch, 'openEditor handler must exist');
    const openEditorSrc = openEditorMatch[0];
    assert.ok(
      openEditorSrc.includes('selectedNoteIdRef.current === note.id')
    );
    assert.ok(openEditorSrc.includes('commitEditorDraftToNote()'));

    // handleCreateNote flushes unsaved edits on existing open note before starting a new draft
    const createMatch = webModule.match(
      /const handleCreateNote = \(\) => \{[\s\S]*?\n  \};/
    );
    assert.ok(createMatch, 'handleCreateNote handler must exist');
    assert.ok(createMatch[0].includes('commitEditorDraftToNote()'));
    assert.ok(createMatch[0].includes('isCurrentNewDraftBlank'));

    // Internal link navigation flushes dirty draft & preserves active filters (no searchQuery wipe)
    const internalNavMatch = webModule.match(
      /const handleNavigateToInternalNote = \([\s\S]*?\n  \};/
    );
    assert.ok(internalNavMatch, 'handleNavigateToInternalNote must exist');
    assert.ok(internalNavMatch[0].includes('commitEditorDraftToNote()'));
    assert.strictEqual(
      internalNavMatch[0].includes("setSearchQuery('')"),
      false,
      'Internal link navigation must preserve active search/folder/tag filters'
    );

    // Card folder move syncs active editor notebook; permanent delete & empty trash clear dead selection
    const moveMatch = webModule.match(
      /const handleMoveCardNoteToFolder = \([\s\S]*?\n  \};/
    );
    assert.ok(moveMatch && moveMatch[0].includes('setEditNotebook(targetNotebook)'));

    const permDeleteMatch = webModule.match(
      /const handleConfirmPermanentDeleteNote = \(\) => \{[\s\S]*?\n  \};/
    );
    assert.ok(
      permDeleteMatch &&
        permDeleteMatch[0].includes('selectedNoteIdRef.current === target.id')
    );
  });

  it('3. Web DaywellNotesModule mounts cleanly in SSR under both auto and compact layout modes', () => {
    for (const mode of ['auto', 'compact'] as const) {
      const html = renderToStaticMarkup(
        React.createElement(DaywellNotesModule, {
          notes: DEFAULT_SAMPLE_NOTES,
          onUpdateNotes: () => {},
          tasks: [],
          layoutMode: mode,
        })
      );
      assert.ok(html.includes('Notes &amp; knowledge'));
      assert.ok(
        html.includes(DEFAULT_SAMPLE_NOTES[0].title.replaceAll('&', '&amp;'))
      );
    }
  });

  it('4. Flutter NotesView implements canonical responsive master-detail, single shared _NoteEditorSurface, serialized flush on switch, and clean design tokens', () => {
    const dartSrc = readRepoFile(flutterNotesPath);

    // Responsive threshold & wide container constraints
    assert.ok(dartSrc.includes('SharedDesignTokens.breakpointExpanded'));
    assert.ok(dartSrc.includes('SharedDesignTokens.breakpointMaxWideWidth'));
    assert.ok(dartSrc.includes('SharedDesignTokens.breakpointMaxContentWidth'));
    assert.ok(dartSrc.includes('_buildWideDetailPane'));
    assert.ok(dartSrc.includes('Select a note to read or edit'));

    // Single shared editor implementation + narrow PopScope preservation
    assert.ok(dartSrc.includes('class _NoteEditorScreen extends StatelessWidget'));
    assert.ok(dartSrc.includes('class _NoteEditorSurface extends StatefulWidget'));
    assert.ok(dartSrc.includes('PopScope<Object?>'));
    const markdownEditorHints =
      dartSrc.match(/Start writing \(English & Amharic/g) ?? [];
    assert.strictEqual(markdownEditorHints.length, 1);

    // Serialized selection queue with pre-switch flush, internal-link callback, and selected highlight
    assert.ok(dartSrc.includes('_selectWideDetailTarget'));
    assert.ok(dartSrc.includes('_selectionOperationQueue'));
    assert.ok(dartSrc.includes('flushPendingSaves()'));
    assert.ok(dartSrc.includes('onSelectInternalNote'));
    assert.ok(dartSrc.includes('onNoteCreated'));
    assert.ok(dartSrc.includes('onCloseEmbedded'));
    assert.ok(dartSrc.includes('Icons.arrow_right_rounded'));

    // Zero raw Color(0x...) or Material Colors.*
    assert.strictEqual(/Color\(\s*0x/i.test(dartSrc), false);
    const materialColors = (
      dartSrc.match(/\bColors\.[a-zA-Z0-9_]+/g) || []
    ).filter((m) => m !== 'Colors.transparent');
    assert.strictEqual(materialColors.length, 0);
  });

  it('5. Flutter Stage N3.3 widget test suite covers narrow, wide, draft-flush, internal links, lifecycle actions, Dark mode, and 1.6x text scaling', () => {
    const dartTest = readRepoFile(flutterTestPath);
    assert.ok(dartTest.includes('Size(390, 800)'));
    assert.ok(dartTest.includes('Size(960, 800)'));
    assert.ok(dartTest.includes('Size(840, 720)'));
    assert.ok(dartTest.includes('BackButton'));
    assert.ok(dartTest.includes('Select a note to read or edit'));
    assert.ok(
      dartTest.includes('TextScaler.linear(1.6)') ||
        (dartTest.includes('TextScaler.linear(textScale)') &&
          dartTest.includes('textScale: 1.6'))
    );
    assert.ok(dartTest.includes('DaywellTheme.dark()'));
    assert.ok(dartTest.includes('requestedNoteFocus'));
  });
});
