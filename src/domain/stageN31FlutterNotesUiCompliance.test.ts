import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';

const REPO_ROOT = process.cwd();

function readRepoFile(relPath: string): string {
  return fs.readFileSync(path.join(REPO_ROOT, relPath), 'utf8');
}

describe('STAGE N3.1 — FLUTTER NOTES UI DESIGN-SYSTEM COMPLIANCE', () => {
  const notesViewPath = 'flutter_app/lib/ui/screens/notes_view.dart';
  const markdownPreviewPath = 'flutter_app/lib/ui/widgets/notes/note_markdown_preview.dart';
  const allowlistPath = 'scripts/ui_consistency_allowlist.json';
  const flutterTestPath = 'flutter_app/test/stage_n31_notes_ui_compliance_test.dart';

  it('1. NotesView and NoteMarkdownPreview contain zero raw Color(0x...) and zero Material Colors.* literals', () => {
    for (const relPath of [notesViewPath, markdownPreviewPath]) {
      const src = readRepoFile(relPath);
      assert.strictEqual(
        /Color\(\s*0x/i.test(src),
        false,
        `${relPath} must not contain raw Color(0x...) literals`
      );
      const materialColors = (src.match(/\bColors\.[a-zA-Z0-9_]+/g) || []).filter(
        (m) => m !== 'Colors.transparent'
      );
      assert.strictEqual(
        materialColors.length,
        0,
        `${relPath} must contain zero Material Colors.* literals, found: ${materialColors.join(', ')}`
      );
    }
  });

  it('2. NotesView is retired from rawColorsAllowlist into forbiddenAllowlistFiles', () => {
    const allowlist = JSON.parse(readRepoFile(allowlistPath));
    assert.ok(
      allowlist.flutter.forbiddenAllowlistFiles.includes(notesViewPath),
      'notes_view.dart must be in forbiddenAllowlistFiles'
    );
    assert.strictEqual(
      Object.prototype.hasOwnProperty.call(allowlist.flutter.rawColorsAllowlist, notesViewPath),
      false,
      'notes_view.dart must be removed from rawColorsAllowlist'
    );
  });

  it('3. NotesView consumes canonical Daywell shared primitives and design tokens', () => {
    const src = readRepoFile(notesViewPath);
    const requiredTokensAndPrimitives = [
      'DaywellSearchFilterBar',
      'DaywellCard',
      'DaywellEmptyState',
      'DaywellLoadingIndicator',
      'DaywellStatusBanner',
      'DaywellStatusBadge',
      'DaywellConfirmationDialog',
      'DaywellButton',
      'DaywellIconButton',
      'DaywellTextField',
      'DaywellTypography',
      'context.daywellColors',
      'SharedDesignTokens.breakpointMaxWideWidth',
      'SharedDesignTokens.breakpointMaxContentWidth',
      'SharedDesignTokens.breakpointExpanded',
      'SharedDesignTokens.spacingMd',
      'SharedDesignTokens.radiusLg',
    ];
    const normalized = src.replace(/\s+/g, '');
    for (const symbol of requiredTokensAndPrimitives) {
      assert.ok(normalized.includes(symbol), `notes_view.dart must consume ${symbol}`);
    }

    // Ensure raw hardcoded light-only palette constants are not left in NotesView
    assert.strictEqual(
      src.includes('SharedDesignTokens.primaryEmerald'),
      false,
      'notes_view.dart must use Theme colorScheme.primary instead of light-only primaryEmerald'
    );
    assert.strictEqual(
      src.includes('SharedDesignTokens.secondaryMint'),
      false,
      'notes_view.dart must use Theme colorScheme.primaryContainer instead of light-only secondaryMint'
    );
  });

  it('4. NoteMarkdownPreview uses canonical tokens, tabular figures for ordered lists, and padded checklist targets', () => {
    const src = readRepoFile(markdownPreviewPath);
    assert.ok(src.includes('DaywellTypography'), 'NoteMarkdownPreview must use DaywellTypography');
    assert.ok(src.includes('context.daywellColors'), 'NoteMarkdownPreview must use context.daywellColors');
    assert.ok(src.includes('FontFeature.tabularFigures()'), 'Ordered list markers should use tabular figures');
    assert.ok(
      src.includes('MaterialTapTargetSize.padded'),
      'Interactive checklist checkboxes must retain padded tap targets'
    );
  });

  it('5. Stage N3.1 Flutter compliance widget test suite covers theme modes, viewports, text scaling, and primitives', () => {
    const flutterTestSrc = readRepoFile(flutterTestPath);
    assert.ok(flutterTestSrc.includes('DaywellTheme.light'));
    assert.ok(flutterTestSrc.includes('DaywellTheme.dark'));
    assert.ok(flutterTestSrc.includes('TextScaler.linear(1.6)'));
    assert.ok(flutterTestSrc.includes('Size(320, 720)'));
    assert.ok(flutterTestSrc.includes('Size(960, 800)'));
    assert.ok(flutterTestSrc.includes('DaywellConfirmationDialog'));
    assert.ok(flutterTestSrc.includes('DaywellSearchFilterBar'));
    assert.ok(flutterTestSrc.includes('DaywellLoadingIndicator'));
    assert.ok(flutterTestSrc.includes('DaywellEmptyState'));
  });
});
