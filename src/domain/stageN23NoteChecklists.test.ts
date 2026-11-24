import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { describe, it } from 'node:test';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { NoteMarkdownPreview } from '../components/notes/NoteMarkdownPreview';
import {
  getNoteMarkdownChecklistAtSelection,
  parseNoteMarkdown,
  toggleNoteMarkdownChecklistAtLine,
} from './noteMarkdown';
import { saveWebNoteDraft } from './webNotesLifecycle';
import type { DaywellNote } from '../components/DaywellNotesModule';

interface SharedToggleCase {
  name: string;
  source: string;
  lineIndex: number;
  toggled: boolean;
  expectedText?: string;
  expectedChecked?: boolean;
}

interface SharedSelectionCase {
  name: string;
  source: string;
  selectionStart: number;
  selectionEnd: number;
  found: boolean;
  lineIndex?: number;
  checked?: boolean;
}

interface SharedChecklistVectors {
  toggleCases: SharedToggleCase[];
  selectionCases: SharedSelectionCase[];
}

const repoRoot = path.resolve(process.cwd());
const vectorsPath = path.join(
  repoRoot,
  'shared_foundation',
  'fixtures',
  'note_checklist_vectors.json'
);
const vectors: SharedChecklistVectors = JSON.parse(
  fs.readFileSync(vectorsPath, 'utf8')
);

describe('Stage N2.3 — Interactive Checklists', () => {
  it('matches all shared toggleCases vectors identically without mutating input', () => {
    for (const testCase of vectors.toggleCases) {
      const snapshot = String(testCase.source);
      const result = toggleNoteMarkdownChecklistAtLine(
        testCase.source,
        testCase.lineIndex
      );
      assert.equal(testCase.source, snapshot, `Input mutated on ${testCase.name}`);
      if (!testCase.toggled) {
        assert.equal(
          result,
          null,
          `Expected null (non-toggleable) for "${testCase.name}"`
        );
      } else {
        assert.notEqual(result, null, `Expected toggle for "${testCase.name}"`);
        assert.equal(result!.text, testCase.expectedText, testCase.name);
        assert.equal(result!.checked, testCase.expectedChecked, testCase.name);
        assert.equal(result!.lineIndex, testCase.lineIndex, testCase.name);
      }
    }
  });

  it('matches all shared selectionCases vectors identically for Write-mode checklist recognition', () => {
    for (const testCase of vectors.selectionCases) {
      const result = getNoteMarkdownChecklistAtSelection(
        testCase.source,
        testCase.selectionStart,
        testCase.selectionEnd
      );
      if (!testCase.found) {
        assert.equal(result, null, `Expected null for "${testCase.name}"`);
      } else {
        assert.notEqual(result, null, `Expected match for "${testCase.name}"`);
        assert.equal(result!.lineIndex, testCase.lineIndex, testCase.name);
        assert.equal(result!.checked, testCase.checked, testCase.name);
      }
    }
  });

  it('toggles multiple independent checklist items, handles rapid repeated toggles, and preserves surrounding Markdown & whitespace', () => {
    const source = [
      '# Morning Prep',
      '',
      'Intro   with   spaces',
      '',
      '- [ ] First item',
      '- [x] Second item',
      '- Plain bullet stays plain',
      '',
      '- [ ] **Bold** third item',
      '',
      '```markdown',
      '- [ ] In fence stays untouched',
      '```',
      '',
      '- [] Malformed stays inert',
      '- [y] Malformed char stays inert',
      '- [x]NoSpace stays inert',
    ].join('\n');

    const doc = parseNoteMarkdown(source);
    const checklistBlocks = doc.blocks.filter((b) => b.type === 'checklist');
    assert.equal(checklistBlocks.length, 2);
    assert.equal(checklistBlocks[0].items.length, 2);
    assert.equal(checklistBlocks[1].items.length, 1);

    // First checklist block items point to lines 4 and 5; second block item points to line 8
    const lineFirst = checklistBlocks[0].items[0].lineIndex;
    const lineSecond = checklistBlocks[0].items[1].lineIndex;
    const lineThird = checklistBlocks[1].items[0].lineIndex;
    assert.equal(lineFirst, 4);
    assert.equal(lineSecond, 5);
    assert.equal(lineThird, 8);

    // Rapid sequential toggles on first item + independent toggles on second and third
    let current = source;
    current = toggleNoteMarkdownChecklistAtLine(current, lineFirst)!.text; // check 1
    current = toggleNoteMarkdownChecklistAtLine(current, lineFirst)!.text; // uncheck 1
    current = toggleNoteMarkdownChecklistAtLine(current, lineFirst)!.text; // check 1 again
    current = toggleNoteMarkdownChecklistAtLine(current, lineSecond)!.text; // uncheck 2
    current = toggleNoteMarkdownChecklistAtLine(current, lineThird)!.text; // check 3

    const expected = [
      '# Morning Prep',
      '',
      'Intro   with   spaces',
      '',
      '- [x] First item',
      '- [ ] Second item',
      '- Plain bullet stays plain',
      '',
      '- [x] **Bold** third item',
      '',
      '```markdown',
      '- [ ] In fence stays untouched',
      '```',
      '',
      '- [] Malformed stays inert',
      '- [y] Malformed char stays inert',
      '- [x]NoSpace stays inert',
    ].join('\n');
    assert.equal(current, expected);

    // Ordinary bullet, fenced checklist, and malformed lines remain untoggleable
    assert.equal(toggleNoteMarkdownChecklistAtLine(current, 6), null);
    assert.equal(toggleNoteMarkdownChecklistAtLine(current, 11), null);
    assert.equal(toggleNoteMarkdownChecklistAtLine(current, 14), null);
    assert.equal(toggleNoteMarkdownChecklistAtLine(current, 15), null);
    assert.equal(toggleNoteMarkdownChecklistAtLine(current, 16), null);

    // Persisting via saveWebNoteDraft keeps exact toggled Markdown without rewriting/trimming
    const seeded: DaywellNote[] = [
      {
        id: 'note-chk-1',
        title: 'Prep',
        content: source,
        notebook: 'Personal',
        tags: [],
        isPinned: false,
        isArchived: false,
        createdAt: '2026-01-01T00:00:00.000Z',
        updatedAt: '2026-01-01T00:00:00.000Z',
      },
    ];
    const saved = saveWebNoteDraft({
      notes: seeded,
      noteId: 'note-chk-1',
      title: 'Prep',
      content: current,
      notebook: 'Personal',
      tags: [],
    });
    assert.equal(saved.status, 'updated');
    assert.equal(saved.note?.content, expected);
  });

  it('renders accessible keyboard-focusable checkboxes in Preview only for valid checklists, never for ordinary bullets or malformed syntax', () => {
    const markdown = [
      '- [ ] Open task',
      '- [x] Done task',
      '- Ordinary bullet',
      '- [] Broken box',
      '- [y] Invalid state',
      '',
      '```ts',
      '- [ ] Code block item',
      '```',
    ].join('\n');

    const interactiveHtml = renderToStaticMarkup(
      React.createElement(NoteMarkdownPreview, {
        content: markdown,
        onToggleChecklistItem: () => {},
      })
    );

    // Exactly two interactive checkboxes rendered (Open task + Done task)
    const checkboxMatches = interactiveHtml.match(/type="checkbox"/g) ?? [];
    assert.equal(checkboxMatches.length, 2);
    assert.equal(
      interactiveHtml.includes('aria-label="Mark item complete: Open task"'),
      true
    );
    assert.equal(
      interactiveHtml.includes('aria-label="Mark item incomplete: Done task"'),
      true
    );
    assert.equal(interactiveHtml.includes('checked=""'), true);

    // Ordinary bullet and malformed lines are still rendered as normal bullet list items, not checkboxes
    assert.equal(interactiveHtml.includes('Ordinary bullet'), true);
    assert.equal(interactiveHtml.includes('[] Broken box'), true);
    assert.equal(interactiveHtml.includes('[y] Invalid state'), true);
    assert.equal(interactiveHtml.includes('- [ ] Code block item'), true);

    // Non-interactive preview (no callback) preserves N2.1 read-only semantics cleanly
    const readOnlyHtml = renderToStaticMarkup(
      React.createElement(NoteMarkdownPreview, { content: markdown })
    );
    assert.equal(readOnlyHtml.includes('type="checkbox"'), false);
    assert.equal(readOnlyHtml.includes('Open item: '), true);
    assert.equal(readOnlyHtml.includes('Completed item: '), true);
  });

  it('wires Web and Flutter interactive checklist controls, keyboard/semantic labels, synchronous rapid-toggle refs, and Dart purity cleanly', () => {
    const webModule = fs.readFileSync(
      path.join(repoRoot, 'src/components/DaywellNotesModule.tsx'),
      'utf8'
    );
    const webPreview = fs.readFileSync(
      path.join(repoRoot, 'src/components/notes/NoteMarkdownPreview.tsx'),
      'utf8'
    );
    const dartParser = fs.readFileSync(
      path.join(repoRoot, 'flutter_app/lib/domain/notes/note_markdown.dart'),
      'utf8'
    );
    const dartPreview = fs.readFileSync(
      path.join(
        repoRoot,
        'flutter_app/lib/ui/widgets/notes/note_markdown_preview.dart'
      ),
      'utf8'
    );
    const flutterNotesView = fs.readFileSync(
      path.join(repoRoot, 'flutter_app/lib/ui/screens/notes_view.dart'),
      'utf8'
    );
    const flutterTest = fs.readFileSync(
      path.join(repoRoot, 'flutter_app/test/stage_n23_note_checklists_test.dart'),
      'utf8'
    );

    // Web synchronous ref protection + Preview & Write-mode wiring
    assert.equal(webModule.includes('handleToggleChecklistLine'), true);
    assert.equal(webModule.includes('draftFieldsRef.current.content = toggled.text'), true);
    assert.equal(webModule.includes('onToggleChecklistItem={handleToggleChecklistLine}'), true);
    assert.equal(webModule.includes('activeWriteChecklist'), true);
    assert.equal(webPreview.includes("e.key === 'Enter'"), true);
    assert.equal(webPreview.includes('Mark item complete'), true);
    assert.equal(webPreview.includes('Mark item incomplete'), true);

    // Dart purity & token hygiene
    assert.equal(dartParser.includes('package:flutter/'), false);
    assert.equal(dartParser.includes('package:drift/'), false);
    assert.equal(/Color\(0x[0-9A-Fa-f]+\)/.test(dartPreview), false);
    assert.equal(/Colors\.[a-zA-Z0-9_]+/.test(dartPreview), false);

    // Flutter preview & editor wiring
    assert.equal(dartPreview.includes('onToggleChecklistItem'), true);
    assert.equal(dartPreview.includes('Mark item complete'), true);
    assert.equal(dartPreview.includes('Mark item incomplete'), true);
    assert.equal(flutterNotesView.includes('_handleToggleChecklistLine'), true);
    assert.equal(flutterNotesView.includes('_activeWriteChecklist'), true);

    // Matching Flutter test covers vectors & NotesView widget interactions
    assert.equal(flutterTest.includes('note_checklist_vectors.json'), true);
    assert.equal(flutterTest.includes('NoteMarkdownPreview'), true);
    assert.equal(flutterTest.includes('NotesView'), true);
  });
});
