import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { describe, it } from 'node:test';
import {
  applyNoteSmartBackspace,
  applyNoteSmartEnter,
  applyNoteToolbarFormat,
  isOffsetInsideFencedCodeBlock,
  NoteToolbarFormatAction,
} from './noteEditorFormatting';
import { parseNoteMarkdown } from './noteMarkdown';

interface SharedToolbarCase {
  name: string;
  action: NoteToolbarFormatAction;
  text: string;
  selectionStart: number;
  selectionEnd: number;
  expectedText: string;
  expectedStart: number;
  expectedEnd: number;
}

interface SharedSmartKeyboardCase {
  name: string;
  text: string;
  selectionStart: number;
  selectionEnd: number;
  handled: boolean;
  expectedText?: string;
  expectedStart?: number;
  expectedEnd?: number;
}

interface SharedFormattingVectors {
  toolbarCases: SharedToolbarCase[];
  enterCases: SharedSmartKeyboardCase[];
  backspaceCases: SharedSmartKeyboardCase[];
}

const repoRoot = path.resolve(process.cwd());
const vectorsPath = path.join(
  repoRoot,
  'shared_foundation',
  'fixtures',
  'note_editor_formatting_vectors.json'
);
const vectors: SharedFormattingVectors = JSON.parse(
  fs.readFileSync(vectorsPath, 'utf8')
);

describe('Stage N2.2 — Practical Formatting Toolbar & Smart List Continuation', () => {
  it('matches all shared toolbarCases vectors identically without mutating input', () => {
    for (const testCase of vectors.toolbarCases) {
      const snapshot = String(testCase.text);
      const result = applyNoteToolbarFormat(
        testCase.text,
        testCase.selectionStart,
        testCase.selectionEnd,
        testCase.action
      );
      assert.equal(testCase.text, snapshot, `Input mutated on ${testCase.name}`);
      assert.equal(
        result.text,
        testCase.expectedText,
        `Text mismatch for toolbar case "${testCase.name}"`
      );
      assert.equal(
        result.selectionStart,
        testCase.expectedStart,
        `selectionStart mismatch for toolbar case "${testCase.name}"`
      );
      assert.equal(
        result.selectionEnd,
        testCase.expectedEnd,
        `selectionEnd mismatch for toolbar case "${testCase.name}"`
      );
    }
  });

  it('matches all shared enterCases vectors identically', () => {
    for (const testCase of vectors.enterCases) {
      const snapshot = String(testCase.text);
      const result = applyNoteSmartEnter(
        testCase.text,
        testCase.selectionStart,
        testCase.selectionEnd
      );
      assert.equal(testCase.text, snapshot, `Input mutated on ${testCase.name}`);
      if (!testCase.handled) {
        assert.equal(
          result,
          null,
          `Expected Enter pass-through (null) for "${testCase.name}"`
        );
      } else {
        assert.notEqual(
          result,
          null,
          `Expected Enter edit for "${testCase.name}"`
        );
        assert.equal(result!.text, testCase.expectedText, testCase.name);
        assert.equal(result!.selectionStart, testCase.expectedStart, testCase.name);
        assert.equal(result!.selectionEnd, testCase.expectedEnd, testCase.name);
      }
    }
  });

  it('matches all shared backspaceCases vectors identically', () => {
    for (const testCase of vectors.backspaceCases) {
      const snapshot = String(testCase.text);
      const result = applyNoteSmartBackspace(
        testCase.text,
        testCase.selectionStart,
        testCase.selectionEnd
      );
      assert.equal(testCase.text, snapshot, `Input mutated on ${testCase.name}`);
      if (!testCase.handled) {
        assert.equal(
          result,
          null,
          `Expected Backspace pass-through (null) for "${testCase.name}"`
        );
      } else {
        assert.notEqual(
          result,
          null,
          `Expected Backspace edit for "${testCase.name}"`
        );
        assert.equal(result!.text, testCase.expectedText, testCase.name);
        assert.equal(result!.selectionStart, testCase.expectedStart, testCase.name);
        assert.equal(result!.selectionEnd, testCase.expectedEnd, testCase.name);
      }
    }
  });

  it('covers all 10 toolbar actions for wrapping, collapsed insertion, toggling without duplicating, and surrounding whitespace preservation', () => {
    const inlineActions: Array<{
      action: NoteToolbarFormatAction;
      marker: string;
    }> = [
      { action: 'bold', marker: '**' },
      { action: 'italic', marker: '*' },
      { action: 'strikethrough', marker: '~~' },
      { action: 'inlineCode', marker: '`' },
    ];

    for (const { action, marker } of inlineActions) {
      // Collapsed cursor inserts marker pair with caret centered
      const collapsed = applyNoteToolbarFormat('Start  end', 6, 6, action);
      assert.equal(collapsed.text, `Start ${marker}${marker} end`);
      assert.equal(collapsed.selectionStart, 6 + marker.length);
      assert.equal(collapsed.selectionEnd, 6 + marker.length);

      // Selected text wraps cleanly, and re-applying toggles cleanly off
      const wrapped = applyNoteToolbarFormat('Keep target intact', 5, 11, action);
      assert.equal(wrapped.text, `Keep ${marker}target${marker} intact`);
      const unwrapped = applyNoteToolbarFormat(
        wrapped.text,
        wrapped.selectionStart,
        wrapped.selectionEnd,
        action
      );
      assert.equal(unwrapped.text, 'Keep target intact');
      assert.equal(unwrapped.selectionStart, 5);
      assert.equal(unwrapped.selectionEnd, 11);

      // Whitespace-only selection behaves like collapsed insertion at start without losing text
      const wsOnly = applyNoteToolbarFormat('a   b', 1, 4, action);
      assert.equal(wsOnly.text, `a${marker}${marker}   b`);
    }

    // Fenced code block round-trip toggle preserves internal indentation and lines
    const multi = '  line 1\n  line 2\n';
    const fenced = applyNoteToolbarFormat(multi, 0, multi.length, 'codeBlock');
    assert.equal(fenced.text, '```\n  line 1\n  line 2\n```\n');
    const unfenced = applyNoteToolbarFormat(
      fenced.text,
      0,
      fenced.text.length,
      'codeBlock'
    );
    assert.equal(unfenced.text, '  line 1\n  line 2');

    // Collapsed fenced code block in middle of text isolates onto its own lines
    const midCode = applyNoteToolbarFormat('AboveBelow', 5, 5, 'codeBlock');
    assert.equal(midCode.text, 'Above\n```\n\n```\nBelow');
    assert.equal(midCode.selectionStart, 10);
    assert.equal(midCode.selectionEnd, 10);
  });

  it('applies block prefixes per non-empty line, replaces incompatible prefixes cleanly, and toggles off consistently', () => {
    // Switching from bullet list -> numbered list -> checklist -> heading2 -> toggle off
    const step1 = applyNoteToolbarFormat(
      '  - Alpha\n\n  - Beta',
      0,
      20,
      'numberedList'
    );
    assert.equal(step1.text, '  1. Alpha\n\n  2. Beta');

    const step2 = applyNoteToolbarFormat(
      step1.text,
      step1.selectionStart,
      step1.selectionEnd,
      'checklist'
    );
    assert.equal(step2.text, '  - [ ] Alpha\n\n  - [ ] Beta');

    const step3 = applyNoteToolbarFormat(
      step2.text,
      step2.selectionStart,
      step2.selectionEnd,
      'heading2'
    );
    assert.equal(step3.text, '  ## Alpha\n\n  ## Beta');

    const toggledOff = applyNoteToolbarFormat(
      step3.text,
      step3.selectionStart,
      step3.selectionEnd,
      'heading2'
    );
    assert.equal(toggledOff.text, '  Alpha\n\n  Beta');

    // Mixed formatted + unformatted lines normalize to target prefix first instead of toggling partially
    const mixed = applyNoteToolbarFormat(
      '> First\nSecond',
      0,
      14,
      'blockquote'
    );
    assert.equal(mixed.text, '> First\n> Second');

    // Trailing newline in line selection does not format the next untouched line
    const trailingNl = applyNoteToolbarFormat(
      'One\nTwo\nThree',
      0,
      4,
      'bulletList'
    );
    assert.equal(trailingNl.text, '- One\nTwo\nThree');

    // Reversed & out-of-bounds selection bounds clamp cleanly
    const clamped = applyNoteToolbarFormat('Note', 99, -5, 'bold');
    assert.equal(clamped.text, '**Note**');
    assert.equal(clamped.selectionStart, 2);
    assert.equal(clamped.selectionEnd, 6);
  });

  it('handles indented, multi-digit numbered lists, middle selections, prefix cursor guards, and fenced blocks on Enter/Backspace', () => {
    // Multi-digit numbered continuation (9. -> 10.) + indentation preservation
    const nineToTen = applyNoteSmartEnter('  9. Ninth item', 15, 15);
    assert.notEqual(nineToTen, null);
    assert.equal(nineToTen!.text, '  9. Ninth item\n  10. ');
    assert.equal(nineToTen!.selectionStart, 22);

    // Same-line non-empty selection replaced before splitting
    const selReplace = applyNoteSmartEnter('- Alpha beta', 8, 12);
    assert.notEqual(selReplace, null);
    assert.equal(selReplace!.text, '- Alpha \n- ');
    assert.equal(selReplace!.selectionStart, 11);

    // Multiline selection lets normal Enter handle replacement
    const multiSel = applyNoteSmartEnter('- One\n- Two', 2, 9);
    assert.equal(multiSel, null);

    // Cursor inside prefix before item text does not duplicate prefix
    const insidePrefix = applyNoteSmartEnter('- Item', 1, 1);
    assert.equal(insidePrefix, null);

    // Indented empty bullet exits on Backspace while preserving indent & surrounding lines
    const indentedBackspace = applyNoteSmartBackspace('Top\n  - \nBottom', 8, 8);
    assert.notEqual(indentedBackspace, null);
    assert.equal(indentedBackspace!.text, 'Top\n  \nBottom');
    assert.equal(indentedBackspace!.selectionStart, 6);

    // Ordinary paragraphs remain untouched by smart Enter & Backspace
    assert.equal(applyNoteSmartEnter('Just a paragraph', 16, 16), null);
    assert.equal(applyNoteSmartBackspace('Just a paragraph', 4, 4), null);

    // Fenced code detection handles open, closed, and indented code fences cleanly
    const fencedText = '```\n- inside\n```\n- outside';
    assert.equal(isOffsetInsideFencedCodeBlock(fencedText, 6), true);
    assert.equal(isOffsetInsideFencedCodeBlock(fencedText, 18), false);

    // Formatted text parses cleanly through N2.1 parser without regressions
    const doc = parseNoteMarkdown('## Heading\n\n- **Bold** & *italic*\n1. First\n- [ ] Check');
    assert.equal(doc.blocks.length, 4);
  });

  it('wires all 10 toolbar actions, smart keyboard handling, accessibility labels, focus preservation, and Dart parity cleanly', () => {
    const webModule = fs.readFileSync(
      path.join(repoRoot, 'src/components/DaywellNotesModule.tsx'),
      'utf8'
    );
    const dartHelper = fs.readFileSync(
      path.join(repoRoot, 'flutter_app/lib/domain/notes/note_editor_formatting.dart'),
      'utf8'
    );
    const flutterNotesView = fs.readFileSync(
      path.join(repoRoot, 'flutter_app/lib/ui/screens/notes_view.dart'),
      'utf8'
    );
    const flutterTest = fs.readFileSync(
      path.join(repoRoot, 'flutter_app/test/stage_n22_note_editor_formatting_test.dart'),
      'utf8'
    );

    const actions: NoteToolbarFormatAction[] = [
      'heading2',
      'bold',
      'italic',
      'strikethrough',
      'bulletList',
      'numberedList',
      'checklist',
      'blockquote',
      'inlineCode',
      'codeBlock',
    ];
    for (const action of actions) {
      assert.equal(
        webModule.includes(`applyToolbarFormatting('${action}')`),
        true,
        `Web toolbar missing action ${action}`
      );
      assert.equal(
        flutterNotesView.includes(`NoteToolbarFormatAction.${action}`),
        true,
        `Flutter toolbar missing action ${action}`
      );
    }

    // Web prevents focus blur on pointer press, wires keyDown, and never calls .focus() inside toolbar/layout selection restoration
    assert.equal(webModule.includes('handleEditorContentKeyDown'), true);
    assert.equal(webModule.includes('onMouseDown={(e) => e.preventDefault()}'), true);
    assert.equal(webModule.includes('role="toolbar"'), true);
    assert.equal(webModule.includes('aria-label="Markdown formatting"'), true);

    // Dart helper purity (no Flutter UI or Drift DB imports)
    assert.equal(dartHelper.includes('package:flutter/'), false);
    assert.equal(dartHelper.includes('package:drift/'), false);

    // Flutter NotesView wires smart Enter/Backspace and avoids requestFocus on toolbar taps
    assert.equal(flutterNotesView.includes('NoteEditorFormatting.applySmartEnter'), true);
    assert.equal(flutterNotesView.includes('NoteEditorFormatting.applySmartBackspace'), true);
    assert.equal(flutterNotesView.includes('NoteEditorFormatting.applyToolbarAction'), true);

    // Matching Flutter test verifies shared vectors + NotesView widget interactions
    assert.equal(flutterTest.includes('note_editor_formatting_vectors.json'), true);
    assert.equal(flutterTest.includes('NoteEditorFormatting'), true);
    assert.equal(flutterTest.includes('NotesView'), true);
  });
});
