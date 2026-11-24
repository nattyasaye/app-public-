import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { describe, it } from 'node:test';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { NoteMarkdownPreview } from '../components/notes/NoteMarkdownPreview';
import { applyNoteToolbarFormat } from './noteEditorFormatting';
import {
  extractInternalLinksFromMarkdown,
  findNoteBacklinks,
  NoteLinkCandidateShape,
  normalizeNoteLinkTitleKey,
  resolveNoteInternalLink,
} from './noteLinks';
import {
  markdownToPlainText,
  NoteMarkdownInline,
  parseNoteMarkdownInlines,
} from './noteMarkdown';
import {
  saveWebNoteDraft,
  toggleWebNoteArchive,
  moveWebNoteToTrash,
  restoreWebNoteFromTrash,
} from './webNotesLifecycle';
import type { DaywellNote } from '../components/DaywellNotesModule';

interface SharedInlineCase {
  name: string;
  input: string;
  expectedTypes: string[];
}

interface SharedNormalizeCase {
  input: string;
  expected: string;
}

interface SharedResolutionCase {
  name: string;
  targetTitle: string;
  expectedStatus: 'resolved' | 'ambiguous' | 'missing';
  expectedMatchedIds: string[];
}

interface SharedBacklinkCase {
  name: string;
  targetNoteId: string;
  expectedReferrerIds: string[];
  expectedCounts: number[];
}

interface SharedToolbarCase {
  name: string;
  text: string;
  selectionStart: number;
  selectionEnd: number;
  expectedText: string;
  expectedStart: number;
  expectedEnd: number;
}

interface SharedInternalLinkVectors {
  inlineCases: SharedInlineCase[];
  normalizeTitleCases: SharedNormalizeCase[];
  resolutionCases: SharedResolutionCase[];
  backlinkCases: SharedBacklinkCase[];
  toolbarCases: SharedToolbarCase[];
}

const repoRoot = path.resolve(process.cwd());
const vectorsPath = path.join(
  repoRoot,
  'shared_foundation',
  'fixtures',
  'note_internal_links_vectors.json'
);
const vectors: SharedInternalLinkVectors = JSON.parse(
  fs.readFileSync(vectorsPath, 'utf8')
);

function serializeInline(node: NoteMarkdownInline): string {
  switch (node.type) {
    case 'text':
      return `text:${node.text}`;
    case 'code':
      return `code:${node.code}`;
    case 'link':
      return `link:${node.label}|${node.url}`;
    case 'internalLink':
      return `internalLink:${node.targetTitle}|${node.rawText}`;
    case 'bold':
      return `bold:[${node.children.map(serializeInline).join(',')}]`;
    case 'italic':
      return `italic:[${node.children.map(serializeInline).join(',')}]`;
    case 'strikethrough':
      return `strike:[${node.children.map(serializeInline).join(',')}]`;
  }
}

function buildFixtureNotes(): DaywellNote[] {
  return [
    {
      id: 'n-roadmap',
      title: 'Project Roadmap',
      content: 'Core milestones and [[Project Roadmap]] self-note.',
      notebook: 'Work',
      tags: [],
      isPinned: false,
      isArchived: false,
      isTrashed: false,
      createdAt: '2026-01-01T08:00:00.000Z',
      updatedAt: '2026-01-05T08:00:00.000Z',
    },
    {
      id: 'n-daily',
      title: 'Daily Focus',
      content:
        'Morning check\nReview [[Project Roadmap]] before noon.\nAlso [[  project   roadmap  ]] tonight.\n```\n[[Project Roadmap]]\n```',
      notebook: 'Personal',
      tags: [],
      isPinned: false,
      isArchived: false,
      isTrashed: false,
      createdAt: '2026-01-02T08:00:00.000Z',
      updatedAt: '2026-01-10T09:00:00.000Z',
    },
    {
      id: 'n-ref-checklist',
      title: 'Sprint Checklist',
      content: '- [ ] Confirm milestones on [[Project Roadmap]]',
      notebook: 'Work',
      tags: [],
      isPinned: false,
      isArchived: false,
      isTrashed: false,
      createdAt: '2026-01-03T08:00:00.000Z',
      updatedAt: '2026-01-08T09:00:00.000Z',
    },
    {
      id: 'n-weekly-old',
      title: 'Weekly Review',
      content: 'Older review copy.',
      notebook: 'Reflections',
      tags: [],
      isPinned: false,
      isArchived: false,
      isTrashed: false,
      createdAt: '2026-01-01T08:00:00.000Z',
      updatedAt: '2026-01-04T08:00:00.000Z',
    },
    {
      id: 'n-weekly-new',
      title: '  weekly   review ',
      content: 'Newer review copy.',
      notebook: 'Work',
      tags: [],
      isPinned: false,
      isArchived: false,
      isTrashed: false,
      createdAt: '2026-01-02T08:00:00.000Z',
      updatedAt: '2026-01-09T08:00:00.000Z',
    },
    {
      id: 'n-archived-spec',
      title: 'Archived Spec',
      content: 'Links to [[Project Roadmap]] while archived.',
      notebook: 'Work',
      tags: [],
      isPinned: false,
      isArchived: true,
      isTrashed: false,
      createdAt: '2026-01-01T08:00:00.000Z',
      updatedAt: '2026-01-12T08:00:00.000Z',
    },
    {
      id: 'n-trashed-draft',
      title: 'Trashed Draft',
      content: 'Links to [[Project Roadmap]] from trash.',
      notebook: 'Personal',
      tags: [],
      isPinned: false,
      isArchived: false,
      isTrashed: true,
      createdAt: '2026-01-01T08:00:00.000Z',
      updatedAt: '2026-01-13T08:00:00.000Z',
    },
  ];
}

describe('Stage N2.4 — Lightweight Internal Note Links & Backlinks', () => {
  it('matches all shared inlineCases, normalizeTitleCases, resolutionCases, backlinkCases, and toolbarCases identically', () => {
    for (const testCase of vectors.inlineCases) {
      const parsed = parseNoteMarkdownInlines(testCase.input);
      assert.deepEqual(
        parsed.map(serializeInline),
        testCase.expectedTypes,
        `Inline mismatch for "${testCase.name}"`
      );
    }

    for (const testCase of vectors.normalizeTitleCases) {
      assert.equal(
        normalizeNoteLinkTitleKey(testCase.input),
        testCase.expected,
        `Normalization mismatch for "${testCase.input}"`
      );
    }

    const fixtureNotes = buildFixtureNotes();
    for (const testCase of vectors.resolutionCases) {
      const resolution = resolveNoteInternalLink(
        testCase.targetTitle,
        fixtureNotes
      );
      assert.equal(
        resolution.status,
        testCase.expectedStatus,
        `Resolution status mismatch for "${testCase.name}"`
      );
      assert.deepEqual(
        resolution.matches.map((m) => m.id),
        testCase.expectedMatchedIds,
        `Matched IDs mismatch for "${testCase.name}"`
      );
    }

    for (const testCase of vectors.backlinkCases) {
      const target = fixtureNotes.find((n) => n.id === testCase.targetNoteId)!;
      const backlinks = findNoteBacklinks(target, fixtureNotes);
      assert.deepEqual(
        backlinks.map((b) => b.note.id),
        testCase.expectedReferrerIds,
        `Backlink referrer IDs mismatch for "${testCase.name}"`
      );
      assert.deepEqual(
        backlinks.map((b) => b.linkCount),
        testCase.expectedCounts,
        `Backlink counts mismatch for "${testCase.name}"`
      );
    }

    for (const testCase of vectors.toolbarCases) {
      const snapshot = String(testCase.text);
      const edited = applyNoteToolbarFormat(
        testCase.text,
        testCase.selectionStart,
        testCase.selectionEnd,
        'internalLink'
      );
      assert.equal(testCase.text, snapshot);
      assert.equal(edited.text, testCase.expectedText, testCase.name);
      assert.equal(edited.selectionStart, testCase.expectedStart, testCase.name);
      assert.equal(edited.selectionEnd, testCase.expectedEnd, testCase.name);
    }
  });

  it('excludes code blocks, handles renames without breaking Markdown, and dynamically restores resolution & backlinks on restore', () => {
    const initial = buildFixtureNotes();

    // Daily Focus has 2 active links + 1 fenced code block link (excluded)
    const daily = initial.find((n) => n.id === 'n-daily')!;
    const extracted = extractInternalLinksFromMarkdown(daily.content);
    assert.equal(extracted.length, 2);
    assert.equal(
      markdownToPlainText('See [[Project Roadmap]] and `[[Code Only]]`.'),
      'See Project Roadmap and [[Code Only]].'
    );

    // Renaming target note preserves [[Project Roadmap]] source in Daily Focus while resolution turns missing
    const renamedRes = saveWebNoteDraft({
      notes: initial,
      noteId: 'n-roadmap',
      title: 'Q3 Roadmap',
      content: initial[0].content,
      notebook: initial[0].notebook,
      tags: initial[0].tags,
    });
    assert.equal(renamedRes.status, 'updated');
    const afterRenameResolution = resolveNoteInternalLink(
      'Project Roadmap',
      renamedRes.notes
    );
    assert.equal(afterRenameResolution.status, 'missing');
    assert.equal(
      renamedRes.notes.find((n) => n.id === 'n-daily')?.content,
      daily.content
    );
    assert.deepEqual(
      findNoteBacklinks(renamedRes.note!, renamedRes.notes),
      []
    );

    // Unarchiving 'Archived Spec' restores both forward link resolution and its backlink to 'Project Roadmap'
    const unarchived = toggleWebNoteArchive(initial, 'n-archived-spec');
    assert.equal(unarchived.ok, true);
    assert.equal(
      resolveNoteInternalLink('Archived Spec', unarchived.notes).status,
      'resolved'
    );
    const roadmapBacklinksAfterUnarchive = findNoteBacklinks(
      initial[0],
      unarchived.notes
    );
    assert.equal(
      roadmapBacklinksAfterUnarchive.some((b) => b.note.id === 'n-archived-spec'),
      true
    );

    // Moving 'Daily Focus' to Trash removes it from backlinks; restoring brings it back
    const trashed = moveWebNoteToTrash(initial, 'n-daily');
    assert.equal(trashed.ok, true);
    assert.equal(
      findNoteBacklinks(initial[0], trashed.notes).some(
        (b) => b.note.id === 'n-daily'
      ),
      false
    );
    const restored = restoreWebNoteFromTrash(trashed.notes, 'n-daily');
    assert.equal(restored.ok, true);
    assert.equal(
      findNoteBacklinks(initial[0], restored.notes).some(
        (b) => b.note.id === 'n-daily'
      ),
      true
    );
  });

  it('renders resolved buttons, inert missing spans, ambiguous choosers, and unaffected external links in NoteMarkdownPreview', () => {
    const notes = buildFixtureNotes();
    const markdown = [
      'Open [[Project Roadmap]] or pick [[Weekly Review]].',
      'Missing [[Nonexistent Note]] and archived [[Archived Spec]] stay inert.',
      'External [Docs](https://daywell.example) and code `[[Inline Code]]`.',
    ].join('\n');

    const html = renderToStaticMarkup(
      React.createElement(NoteMarkdownPreview, {
        content: markdown,
        notes: notes as readonly NoteLinkCandidateShape[],
        onOpenInternalNote: () => {},
        onOpenAmbiguousInternalLink: () => {},
      })
    );

    // Resolved link renders clickable button
    assert.equal(html.includes('data-testid="internal-note-link-resolved"'), true);
    assert.equal(html.includes('aria-label="Open note: Project Roadmap"'), true);

    // Ambiguous link renders chooser button with match count
    assert.equal(html.includes('data-testid="internal-note-link-ambiguous"'), true);
    assert.equal(html.includes('(2)'), true);

    // Missing & archived links render non-interactive spans
    const missingMatches =
      html.match(/data-testid="internal-note-link-missing"/g) ?? [];
    assert.equal(missingMatches.length, 2);

    // External link & inline code remain untouched
    assert.equal(
      html.includes('href="https://daywell.example"'),
      true
    );
    assert.equal(
      /<code[^>]*>\[\[Inline Code\]\]<\/code>/.test(html),
      true
    );
  });

  it('maintains Web/Flutter UI token hygiene, domain purity, pre-navigation autosave flush, and matching Dart tests', () => {
    const webModule = fs.readFileSync(
      path.join(repoRoot, 'src/components/DaywellNotesModule.tsx'),
      'utf8'
    );
    const webPreview = fs.readFileSync(
      path.join(repoRoot, 'src/components/notes/NoteMarkdownPreview.tsx'),
      'utf8'
    );
    const dartLinks = fs.readFileSync(
      path.join(repoRoot, 'flutter_app/lib/domain/notes/note_links.dart'),
      'utf8'
    );
    const dartPreview = fs.readFileSync(
      path.join(
        repoRoot,
        'flutter_app/lib/ui/widgets/notes/note_markdown_preview.dart'
      ),
      'utf8'
    );
    const dartNotesView = fs.readFileSync(
      path.join(repoRoot, 'flutter_app/lib/ui/screens/notes_view.dart'),
      'utf8'
    );
    const dartTest = fs.readFileSync(
      path.join(
        repoRoot,
        'flutter_app/test/stage_n24_note_internal_links_test.dart'
      ),
      'utf8'
    );

    // Pure domain checks
    assert.equal(dartLinks.includes('package:flutter/'), false);
    assert.equal(dartLinks.includes('package:drift/'), false);

    // Web hygiene & wiring
    assert.equal(/#[0-9A-Fa-f]{3,8}\b/.test(webPreview), false);
    assert.equal(webPreview.includes('dangerouslySetInnerHTML'), false);
    assert.equal(webModule.includes('handleNavigateToInternalNote'), true);
    assert.equal(webModule.includes('commitEditorDraftToNote'), true);
    assert.equal(webModule.includes('note-backlinks-section'), true);
    assert.equal(webModule.includes('ambiguous-note-link-dialog'), true);
    assert.equal(webModule.includes("applyToolbarFormatting('internalLink')"), true);

    // Flutter UI token hygiene & wiring
    assert.equal(/Color\(0x[0-9A-Fa-f]+\)/.test(dartPreview), false);
    assert.equal(/Colors\.[a-zA-Z0-9_]+/.test(dartPreview), false);
    assert.equal(/Color\(0x[0-9A-Fa-f]+\)/.test(dartNotesView), false);
    assert.equal(dartNotesView.includes('_openInternalNote'), true);
    assert.equal(dartNotesView.includes('_openAmbiguousInternalLinkChooser'), true);
    assert.equal(dartNotesView.includes('NoteToolbarFormatAction.internalLink'), true);

    // Dart Stage N2.4 test alignment
    assert.equal(dartTest.includes('note_internal_links_vectors.json'), true);
    assert.equal(dartTest.includes('NoteLinksDomain'), true);
    assert.equal(dartTest.includes('NotesView'), true);
  });
});
