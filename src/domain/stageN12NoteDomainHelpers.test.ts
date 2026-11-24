import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  compareNotes,
  DEFAULT_NOTE_TITLE,
  getNoteLifecycleState,
  hasValidNoteLink,
  isNoteActive,
  isNoteArchived,
  isNoteFavoriteActive,
  isNotePinnedActive,
  isNoteTrashed,
  isSupportedNoteLinkModule,
  isValidNoteTitle,
  MAX_NOTE_TITLE_LENGTH,
  normalizeExchangeNoteFolder,
  normalizeFlutterNoteCategory,
  normalizeNoteFolder,
  normalizeNoteLinkPair,
  normalizeNoteTags,
  normalizeNoteTitle,
  normalizeWebNoteNotebook,
  parseNoteSortMode,
  sortNotes,
  validateNoteTitle,
} from './noteHelpers';

const REPO_ROOT = process.cwd();
const FIXTURES = JSON.parse(
  fs.readFileSync(
    path.join(REPO_ROOT, 'shared_foundation/fixtures/note_domain_helpers_vectors.json'),
    'utf8'
  )
);

describe('Stage N1.2 — Pure Notes Domain Helpers (TypeScript + Dart Parity)', () => {
  it('1. Title validation and normalization enforce 250-char limit and fallbacks across shared vectors', () => {
    assert.strictEqual(DEFAULT_NOTE_TITLE, 'Untitled Note');
    assert.strictEqual(MAX_NOTE_TITLE_LENGTH, 250);

    for (const tc of FIXTURES.titleCases) {
      const raw =
        typeof tc.repeatChar === 'string'
          ? tc.repeatChar.repeat(tc.repeatCount)
          : tc.raw;
      assert.strictEqual(isValidNoteTitle(raw), tc.expectedValid, tc.name);

      const normalized = normalizeNoteTitle(raw, { fallbackTitle: tc.fallback });
      const validated = validateNoteTitle(raw, { fallbackTitle: tc.fallback });
      assert.strictEqual(validated.valid, tc.expectedValid, tc.name);
      assert.strictEqual(validated.normalized, normalized, tc.name);

      if (tc.expectedNormalized !== undefined) {
        assert.strictEqual(normalized, tc.expectedNormalized, tc.name);
      }
      if (tc.expectedLength !== undefined) {
        assert.strictEqual(normalized.length, tc.expectedLength, tc.name);
      }
      if (!tc.expectedValid) {
        assert.ok(validated.error && validated.error.length > 0, tc.name);
      }
    }

    assert.strictEqual(isValidNoteTitle(null), false);
    assert.strictEqual(isValidNoteTitle(undefined), false);
    assert.strictEqual(normalizeNoteTitle(null), 'Untitled Note');
  });

  it('2. Tag normalization trims whitespace, drops empty entries, and deduplicates case-insensitively without altering first-seen casing', () => {
    for (const tc of FIXTURES.tagCases) {
      assert.deepStrictEqual(normalizeNoteTags(tc.input), tc.expected, tc.name);
    }

    assert.deepStrictEqual(normalizeNoteTags(null), []);
    assert.deepStrictEqual(normalizeNoteTags(undefined), []);
    assert.deepStrictEqual(
      normalizeNoteTags(['  First  ', 123 as unknown as string, null, 'SECOND']),
      ['First', 'SECOND']
    );
  });

  it('3. Folder/category normalization preserves existing custom values and platform-specific defaults', () => {
    for (const tc of FIXTURES.folderCases) {
      assert.strictEqual(
        normalizeNoteFolder(tc.raw, {
          defaultFolder: tc.defaultFolder,
          lowercase: tc.lowercase,
        }),
        tc.expected,
        tc.name
      );
    }

    assert.strictEqual(normalizeFlutterNoteCategory('  Reflection '), 'reflection');
    assert.strictEqual(normalizeFlutterNoteCategory('  '), 'general');
    assert.strictEqual(normalizeWebNoteNotebook('  Finances '), 'Finances');
    assert.strictEqual(normalizeWebNoteNotebook(''), 'Personal');
    assert.strictEqual(normalizeExchangeNoteFolder('  Custom Folder '), 'Custom Folder');
    assert.strictEqual(normalizeExchangeNoteFolder(null), 'General');
  });

  it('4. Lifecycle predicates evaluate active, archived, trashed, pinned-active, and favorite-active consistently', () => {
    for (const tc of FIXTURES.lifecycleCases) {
      const note = {
        isPinned: tc.isPinned,
        isFavorite: tc.isFavorite,
        isArchived: tc.isArchived,
        isTrashed: tc.isTrashed,
      };
      assert.strictEqual(getNoteLifecycleState(note), tc.expectedState, tc.name);
      assert.strictEqual(isNoteActive(note), tc.expectedActive, tc.name);
      assert.strictEqual(isNoteArchived(note), tc.expectedArchived, tc.name);
      assert.strictEqual(isNoteTrashed(note), tc.expectedTrashed, tc.name);
      assert.strictEqual(isNotePinnedActive(note), tc.expectedPinnedActive, tc.name);
      assert.strictEqual(isNoteFavoriteActive(note), tc.expectedFavoriteActive, tc.name);
    }

    // Web notes with omitted optional flags default cleanly to active
    assert.strictEqual(getNoteLifecycleState({ isArchived: false }), 'active');
    assert.strictEqual(isNoteActive({ isArchived: false }), true);
    assert.strictEqual(isNoteTrashed({}), false);
  });

  it('5. Polymorphic link helpers validate supported modules and reject half-links or unsupported targets', () => {
    for (const tc of FIXTURES.linkCases) {
      assert.strictEqual(
        isSupportedNoteLinkModule(tc.rawModule),
        tc.expectedSupportedModule,
        tc.name
      );
      const pair = normalizeNoteLinkPair(tc.rawModule, tc.rawId);
      if (tc.expectedModule === null) {
        assert.strictEqual(pair, null, tc.name);
        assert.strictEqual(
          hasValidNoteLink({ linkedModule: tc.rawModule, linkedId: tc.rawId }),
          false,
          tc.name
        );
      } else {
        assert.deepStrictEqual(
          pair,
          { linkedModule: tc.expectedModule, linkedId: tc.expectedId },
          tc.name
        );
        assert.strictEqual(
          hasValidNoteLink({ linkedModule: tc.rawModule, linkedId: tc.rawId }),
          true,
          tc.name
        );
      }
    }
  });

  it('6. Deterministic sorting produces stable results across recent, alpha, oldest, and pinFirst modes without mutating input', () => {
    const input = FIXTURES.sortFixtureNotes;
    const originalIds = input.map((n: { id: string }) => n.id);

    assert.deepStrictEqual(
      sortNotes(input, { sortBy: 'recent', pinFirst: true }).map((n: { id: string }) => n.id),
      FIXTURES.sortExpectations.recentPinFirst
    );
    assert.deepStrictEqual(
      sortNotes(input, { sortBy: 'recent', pinFirst: false }).map((n: { id: string }) => n.id),
      FIXTURES.sortExpectations.recentNoPin
    );
    assert.deepStrictEqual(
      sortNotes(input, { sortBy: 'alpha', pinFirst: true }).map((n: { id: string }) => n.id),
      FIXTURES.sortExpectations.alphaPinFirst
    );
    assert.deepStrictEqual(
      sortNotes(input, { sortBy: 'oldest', pinFirst: true }).map((n: { id: string }) => n.id),
      FIXTURES.sortExpectations.oldestPinFirst
    );

    // Input array was not mutated
    assert.deepStrictEqual(
      input.map((n: { id: string }) => n.id),
      originalIds
    );
    assert.strictEqual(parseNoteSortMode('ALPHA'), 'alpha');
    assert.strictEqual(parseNoteSortMode('oldest'), 'oldest');
    assert.strictEqual(parseNoteSortMode('unknown'), 'recent');

    // Comparator antisymmetry sanity
    const sorted = sortNotes(input, { sortBy: 'recent', pinFirst: true });
    assert.ok(compareNotes(sorted[0], sorted[1], { sortBy: 'recent', pinFirst: true }) < 0);
  });

  it('7. Dart NoteDomainHelpers and existing Web/Flutter modules stay pure and reuse helpers without duplication', () => {
    const dartHelpers = fs.readFileSync(
      path.join(REPO_ROOT, 'flutter_app/lib/domain/notes/note_helpers.dart'),
      'utf8'
    );
    assert.doesNotMatch(dartHelpers, /package:flutter\//);
    assert.doesNotMatch(dartHelpers, /package:drift\//);
    assert.match(dartHelpers, /class NoteDomainHelpers/);
    assert.match(dartHelpers, /isValidTitle/);
    assert.match(dartHelpers, /normalizeTitle/);
    assert.match(dartHelpers, /validateTitle/);
    assert.match(dartHelpers, /normalizeTags/);
    assert.match(dartHelpers, /normalizeFolder/);
    assert.match(dartHelpers, /isActive/);
    assert.match(dartHelpers, /isArchived/);
    assert.match(dartHelpers, /isTrashed/);
    assert.match(dartHelpers, /getLifecycleState/);
    assert.match(dartHelpers, /isSupportedLinkModule/);
    assert.match(dartHelpers, /normalizeLinkPair/);
    assert.match(dartHelpers, /compareNotes/);
    assert.match(dartHelpers, /sortNotes/);

    const dartModels = fs.readFileSync(
      path.join(REPO_ROOT, 'flutter_app/lib/domain/notes/note_models.dart'),
      'utf8'
    );
    assert.match(dartModels, /NoteDomainHelpers\.normalizeFlutterCategory/);
    assert.match(dartModels, /NoteDomainHelpers\.normalizeLinkPair/);
    assert.match(dartModels, /NoteDomainHelpers\.normalizeTitle/);

    const dartNotesState = fs.readFileSync(
      path.join(REPO_ROOT, 'flutter_app/lib/application/notes/notes_state.dart'),
      'utf8'
    );
    assert.match(dartNotesState, /NoteDomainHelpers\.isActive/);
    assert.match(dartNotesState, /NoteDomainHelpers\.sortNotes/);

    const tsHelpers = fs.readFileSync(
      path.join(REPO_ROOT, 'src/domain/noteHelpers.ts'),
      'utf8'
    );
    assert.doesNotMatch(tsHelpers, /from ['"]react['"]/);
    assert.doesNotMatch(tsHelpers, /localStorage/);

    const dartTestExists = fs.existsSync(
      path.join(REPO_ROOT, 'flutter_app/test/stage_n12_note_domain_helpers_test.dart')
    );
    assert.strictEqual(dartTestExists, true);
  });
});
