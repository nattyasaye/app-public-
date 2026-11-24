import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  collectUniqueNoteTags,
  compareNotes,
  isReservedNoteFolderName,
  normalizeNoteTags,
  noteMatchesDateFilter,
  noteMatchesTagFilter,
  parseNoteDateFilterMode,
  parseNoteSortMode,
  resolveReusableNoteTag,
  sortNotes,
} from './noteHelpers';
import { TaskNoteRecord } from './taskNotes';
import {
  createWebCustomFolder,
  DEFAULT_WEB_NOTEBOOKS,
  deleteWebNotebook,
  filterAndSortWebNotes,
  getAvailableWebNotebooks,
  isDefaultWebNotebook,
  moveWebNoteToNotebook,
  renameWebNotebook,
} from './webNotesLifecycle';
import { notesService } from '../services/notesService';

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
    ...(overrides.projectId !== undefined ? { projectId: overrides.projectId } : {}),
    ...(overrides.goalId !== undefined ? { goalId: overrides.goalId } : {}),
    ...(overrides.linkedModule !== undefined
      ? { linkedModule: overrides.linkedModule }
      : {}),
    ...(overrides.linkedId !== undefined ? { linkedId: overrides.linkedId } : {}),
    createdAt: overrides.createdAt ?? '2026-11-10T09:00:00.000Z',
    updatedAt: overrides.updatedAt ?? '2026-11-20T09:00:00.000Z',
  };
}

function withMockBrowserStorage(fn: (store: Map<string, string>) => void): void {
  const store = new Map<string, string>();
  const prevWindow = (globalThis as any).window;
  const prevLocalStorage = (globalThis as any).localStorage;

  (globalThis as any).localStorage = {
    getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
    setItem: (k: string, v: string) => void store.set(k, String(v)),
    removeItem: (k: string) => void store.delete(k),
    clear: () => void store.clear(),
  };
  (globalThis as any).window = {
    dispatchEvent: () => true,
    CustomEvent: class CustomEvent {
      type: string;
      detail: unknown;
      constructor(type: string, init?: { detail?: unknown }) {
        this.type = type;
        this.detail = init?.detail;
      }
    },
  };

  try {
    fn(store);
  } finally {
    (globalThis as any).window = prevWindow;
    (globalThis as any).localStorage = prevLocalStorage;
  }
}

describe('Stage N3.2 — Notes Organization and Filtering', () => {
  it('1. Folder creation validates empty, reserved, built-in, and case-insensitive duplicates while preserving custom casing', () => {
    assert.strictEqual(isReservedNoteFolderName('All'), true);
    assert.strictEqual(isReservedNoteFolderName('  TRASH '), true);
    assert.strictEqual(isReservedNoteFolderName('Research'), false);

    assert.strictEqual(isDefaultWebNotebook('personal'), true);
    assert.strictEqual(isDefaultWebNotebook('Work'), true);
    assert.strictEqual(isDefaultWebNotebook('Research'), false);

    const emptyRes = createWebCustomFolder({
      existingFolders: [],
      folderName: '   ',
    });
    assert.strictEqual(emptyRes.ok, false);

    const reservedRes = createWebCustomFolder({
      existingFolders: [],
      folderName: 'Favorites',
    });
    assert.strictEqual(reservedRes.ok, false);

    const builtinDup = createWebCustomFolder({
      existingFolders: [],
      folderName: 'work',
    });
    assert.strictEqual(builtinDup.ok, false);

    const created = createWebCustomFolder({
      existingFolders: [],
      folderName: '  Deep Research  ',
      knownFolders: ['Travel_Logs'],
    });
    assert.strictEqual(created.ok, true);
    assert.strictEqual(created.folder, 'Deep Research');
    assert.deepStrictEqual(created.customFolders, ['Deep Research']);

    const caseDup = createWebCustomFolder({
      existingFolders: created.customFolders,
      folderName: 'deep research',
    });
    assert.strictEqual(caseDup.ok, false);

    const knownDup = createWebCustomFolder({
      existingFolders: created.customFolders,
      folderName: 'travel_logs',
      knownFolders: ['Travel_Logs'],
    });
    assert.strictEqual(knownDup.ok, false);

    const available = getAvailableWebNotebooks(
      [
        makeNote('n1', 'Custom Historical', { notebook: 'FieldNotes' }),
        makeNote('n2', 'Trashed Ignored', {
          notebook: 'TrashedOnlyFolder',
          isTrashed: true,
        }),
      ],
      DEFAULT_WEB_NOTEBOOKS,
      created.customFolders
    );
    assert.ok(available.includes('Deep Research'));
    assert.ok(available.includes('FieldNotes'));
    assert.strictEqual(available.includes('TrashedOnlyFolder'), false);
  });

  it('2. Folder rename updates active & archived notes safely, rejects built-ins/conflicts, and leaves trashed notes untouched', () => {
    const activeNote = makeNote('n1', 'Active Research', {
      notebook: 'Research',
      linkedModule: 'tasks',
      linkedId: 'task-42',
    });
    const archivedNote = makeNote('n2', 'Archived Research', {
      notebook: 'research',
      isArchived: true,
    });
    const trashedNote = makeNote('n3', 'Trashed Research', {
      notebook: 'Research',
      isTrashed: true,
    });
    const otherNote = makeNote('n4', 'Personal Log', { notebook: 'Personal' });

    const builtinBlocked = renameWebNotebook({
      notes: [activeNote],
      customFolders: ['Research'],
      oldName: 'Work',
      newName: 'Projects',
    });
    assert.strictEqual(builtinBlocked.ok, false);

    const conflictBlocked = renameWebNotebook({
      notes: [activeNote],
      customFolders: ['Research', 'Study'],
      oldName: 'Research',
      newName: 'study',
    });
    assert.strictEqual(conflictBlocked.ok, false);

    const now = new Date('2026-11-24T12:00:00.000Z');
    const renamed = renameWebNotebook({
      notes: [activeNote, archivedNote, trashedNote, otherNote],
      customFolders: ['Research', 'Reading'],
      oldName: 'Research',
      newName: 'Science Lab',
      nowUtc: now,
    });
    assert.strictEqual(renamed.ok, true);
    assert.strictEqual(renamed.folder, 'Science Lab');
    assert.strictEqual(renamed.affectedCount, 2);
    assert.deepStrictEqual(renamed.customFolders, ['Science Lab', 'Reading']);
    assert.strictEqual(renamed.notes.find((n) => n.id === 'n1')?.notebook, 'Science Lab');
    assert.strictEqual(renamed.notes.find((n) => n.id === 'n1')?.linkedId, 'task-42');
    assert.strictEqual(renamed.notes.find((n) => n.id === 'n2')?.notebook, 'Science Lab');
    assert.strictEqual(renamed.notes.find((n) => n.id === 'n2')?.isArchived, true);
    assert.strictEqual(renamed.notes.find((n) => n.id === 'n3')?.notebook, 'Research');
    assert.strictEqual(renamed.notes.find((n) => n.id === 'n4')?.notebook, 'Personal');
  });

  it('3. Deleting a folder NEVER deletes notes — reassigns non-trashed notes safely to Personal (or safe destination) and leaves Trash intact', () => {
    const n1 = makeNote('n1', 'Note 1', { notebook: 'Reading', tags: ['books'] });
    const n2 = makeNote('n2', 'Note 2', { notebook: 'reading', isArchived: true });
    const nTrashed = makeNote('n3', 'Trashed', { notebook: 'Reading', isTrashed: true });
    const nWork = makeNote('n4', 'Work Note', { notebook: 'Work' });

    const builtinBlocked = deleteWebNotebook({
      notes: [nWork],
      customFolders: ['Reading'],
      folderName: 'Personal',
    });
    assert.strictEqual(builtinBlocked.ok, false);

    const deleted = deleteWebNotebook({
      notes: [n1, n2, nTrashed, nWork],
      customFolders: ['Reading', 'Travel'],
      folderName: 'Reading',
      nowUtc: new Date('2026-11-24T13:00:00.000Z'),
    });

    assert.strictEqual(deleted.ok, true);
    assert.strictEqual(deleted.notes.length, 4);
    assert.strictEqual(deleted.affectedCount, 2);
    assert.strictEqual(deleted.destinationNotebook, 'Personal');
    assert.deepStrictEqual(deleted.customFolders, ['Travel']);
    assert.strictEqual(deleted.notes.find((n) => n.id === 'n1')?.notebook, 'Personal');
    assert.deepStrictEqual(deleted.notes.find((n) => n.id === 'n1')?.tags, ['books']);
    assert.strictEqual(deleted.notes.find((n) => n.id === 'n2')?.notebook, 'Personal');
    assert.strictEqual(deleted.notes.find((n) => n.id === 'n2')?.isArchived, true);
    assert.strictEqual(deleted.notes.find((n) => n.id === 'n3')?.notebook, 'Reading');
    assert.strictEqual(deleted.notes.find((n) => n.id === 'n4')?.notebook, 'Work');

    // Deleting a folder with destination pointing at itself falls back safely to Personal
    const selfDestDeleted = deleteWebNotebook({
      notes: [makeNote('n5', 'Self', { notebook: 'Temp' })],
      customFolders: ['Temp'],
      folderName: 'Temp',
      destinationNotebook: 'Temp',
    });
    assert.strictEqual(selfDestDeleted.ok, true);
    assert.strictEqual(selfDestDeleted.destinationNotebook, 'Personal');
    assert.strictEqual(selfDestDeleted.notes[0].notebook, 'Personal');
  });

  it('4. Moving notes between folders updates active/archived notes while blocking trashed notes', () => {
    const active = makeNote('n1', 'Move Me', {
      notebook: 'Personal',
      tags: ['focus'],
      linkedModule: 'tasks',
      linkedId: 't-1',
    });
    const trashed = makeNote('n2', 'Trashed', {
      notebook: 'Personal',
      isTrashed: true,
    });

    const moved = moveWebNoteToNotebook(
      [active, trashed],
      'n1',
      'Research',
      new Date('2026-11-24T14:00:00.000Z')
    );
    assert.strictEqual(moved.ok, true);
    assert.strictEqual(moved.updatedNote?.notebook, 'Research');
    assert.strictEqual(moved.updatedNote?.linkedId, 't-1');
    assert.deepStrictEqual(moved.updatedNote?.tags, ['focus']);

    const blocked = moveWebNoteToNotebook([active, trashed], 'n2', 'Work');
    assert.strictEqual(blocked.ok, false);
    assert.ok(blocked.error?.includes('Restore note from Trash'));
  });

  it('5. Tag collection, reuse, duplicate prevention, and tag filtering preserve original canonical casing', () => {
    const notes = [
      makeNote('n1', 'Alpha', { tags: ['Architecture', 'etb'] }),
      makeNote('n2', 'Beta', { tags: ['architecture', 'Focus'] }),
      makeNote('n3', 'Archived', { tags: ['History'], isArchived: true }),
      makeNote('n4', 'Trashed', { tags: ['DeadTag'], isTrashed: true }),
    ];

    const activeAndArchivedTags = collectUniqueNoteTags(notes);
    assert.deepStrictEqual(activeAndArchivedTags, [
      'Architecture',
      'etb',
      'Focus',
      'History',
    ]);
    assert.strictEqual(activeAndArchivedTags.includes('DeadTag'), false);

    const activeOnlyTags = collectUniqueNoteTags(notes, { includeArchived: false });
    assert.strictEqual(activeOnlyTags.includes('History'), false);

    // Reuse preserves existing canonical casing & strips # / whitespace
    assert.strictEqual(
      resolveReusableNoteTag('  #architecture  ', activeAndArchivedTags),
      'Architecture'
    );
    assert.strictEqual(
      resolveReusableNoteTag('#NewTag', activeAndArchivedTags),
      'NewTag'
    );
    assert.strictEqual(resolveReusableNoteTag('  ###  ', activeAndArchivedTags), null);

    // Case-insensitive duplicate prevention
    assert.deepStrictEqual(
      normalizeNoteTags(['Architecture', 'architecture', '  Focus ', 'FOCUS']),
      ['Architecture', 'Focus']
    );

    assert.strictEqual(noteMatchesTagFilter(notes[0].tags, 'all'), true);
    assert.strictEqual(noteMatchesTagFilter(notes[0].tags, 'ARCHITECTURE'), true);
    assert.strictEqual(noteMatchesTagFilter(notes[0].tags, 'Focus'), false);
  });

  it('6. Date filters (Ethiopia UTC+3), sorting modes (recent, created, alpha, oldest), and combined orthogonal filters work predictably', () => {
    const nowUtc = new Date('2026-11-24T12:00:00.000Z');
    assert.strictEqual(parseNoteDateFilterMode('CREATED_7D'), 'created_7d');
    assert.strictEqual(parseNoteDateFilterMode('unknown'), 'all');
    assert.strictEqual(parseNoteSortMode('created'), 'created');
    assert.strictEqual(parseNoteSortMode('alpha'), 'alpha');

    // Ethiopia UTC+3 boundary: 2026-11-18 in Ethiopia includes 2026-11-17T21:30:00Z (00:30 EAT on Nov 18)
    const inside7d = makeNote('n-in7', 'Zebra Note', {
      notebook: 'Work',
      tags: ['Roadmap', 'etb'],
      isPinned: true,
      isFavorite: true,
      createdAt: '2026-11-17T21:30:00.000Z',
      updatedAt: '2026-11-24T08:00:00.000Z',
    });
    const inside30d = makeNote('n-in30', 'Alpha Plan', {
      notebook: 'Work',
      tags: ['roadmap'],
      isPinned: false,
      isFavorite: true,
      createdAt: '2026-11-23T08:00:00.000Z', // newer creation, older update
      updatedAt: '2026-11-23T09:00:00.000Z',
    });
    const olderNote = makeNote('n-old', 'Beta Legacy', {
      notebook: 'Work',
      tags: ['roadmap'],
      isFavorite: false,
      createdAt: '2026-10-01T08:00:00.000Z',
      updatedAt: '2026-10-10T08:00:00.000Z',
    });
    const archivedMatch = makeNote('n-arch', 'Archived Work Roadmap', {
      notebook: 'Work',
      tags: ['roadmap'],
      isFavorite: true,
      isArchived: true,
      createdAt: '2026-11-24T08:00:00.000Z',
      updatedAt: '2026-11-24T09:00:00.000Z',
    });
    const trashedMatch = makeNote('n-trash', 'Trashed Work Roadmap', {
      notebook: 'Work',
      tags: ['roadmap'],
      isFavorite: true,
      isTrashed: true,
      createdAt: '2026-11-24T08:00:00.000Z',
      updatedAt: '2026-11-24T09:00:00.000Z',
    });

    assert.strictEqual(noteMatchesDateFilter(inside7d, 'created_7d', nowUtc), true);
    assert.strictEqual(noteMatchesDateFilter(olderNote, 'updated_30d', nowUtc), false);
    assert.strictEqual(noteMatchesDateFilter(olderNote, 'all', nowUtc), true);

    const all = [inside30d, olderNote, inside7d, archivedMatch, trashedMatch];

    // Combined: active + favorites + Work + #roadmap + updated_7d -> excludes olderNote, archived, trashed
    const combined = filterAndSortWebNotes(all, {
      activeTab: 'favorites',
      notebookFilter: 'Work',
      tagFilter: 'roadmap',
      dateFilter: 'updated_7d',
      nowUtc,
    });
    assert.deepStrictEqual(
      combined.map((n) => n.id),
      ['n-in7', 'n-in30']
    );

    // Search composes with folder/tag/date filters
    const searched = filterAndSortWebNotes(all, {
      activeTab: 'all',
      notebookFilter: 'Work',
      tagFilter: 'roadmap',
      searchQuery: 'beta',
      nowUtc,
    });
    assert.deepStrictEqual(
      searched.map((n) => n.id),
      ['n-old']
    );

    // Sorting: created with pinFirst=false shows n-in30 (Nov 23) ahead of n-in7 (Nov 18)
    const createdSorted = sortNotes([inside7d, inside30d, olderNote], {
      sortBy: 'created',
      pinFirst: false,
    });
    assert.deepStrictEqual(
      createdSorted.map((n) => n.id),
      ['n-in30', 'n-in7', 'n-old']
    );

    // Sorting: alpha with pinFirst=true keeps pinned n-in7 first, then Alpha Plan, Beta Legacy
    const alphaPinnedSorted = sortNotes([olderNote, inside30d, inside7d], {
      sortBy: 'alpha',
      pinFirst: true,
    });
    assert.deepStrictEqual(
      alphaPinnedSorted.map((n) => n.id),
      ['n-in7', 'n-in30', 'n-old']
    );

    // Comparator determinism when pinned differs
    assert.ok(compareNotes(inside7d, inside30d, { sortBy: 'alpha', pinFirst: true }) < 0);
  });

  it('7. notesService persists custom folders safely with case-insensitive deduplication', () => {
    withMockBrowserStorage((store) => {
      const saved = notesService.saveCustomFolders([
        '  Research ',
        'research',
        '',
        'Travel',
      ]);
      assert.deepStrictEqual(saved, ['Research', 'Travel']);
      assert.deepStrictEqual(notesService.loadCustomFolders(), ['Research', 'Travel']);

      // Corrupt storage fails closed to empty list
      store.set('daywell_note_folders', '{broken');
      assert.deepStrictEqual(notesService.loadCustomFolders(), []);
    });
  });

  it('8. Web and Flutter UI modules expose symmetric Stage N3.2 organization controls without token violations', () => {
    const webModule = readRepoFile('src/components/DaywellNotesModule.tsx');
    const flutterNotesView = readRepoFile('flutter_app/lib/ui/screens/notes_view.dart');
    const flutterController = readRepoFile(
      'flutter_app/lib/application/notes/notes_controller.dart'
    );
    const flutterState = readRepoFile(
      'flutter_app/lib/application/notes/notes_state.dart'
    );

    // Web UI Stage N3.2 controls & zero hex literals
    assert.ok(webModule.includes('New Folder'));
    assert.ok(webModule.includes('Rename'));
    assert.ok(webModule.includes('Delete Folder?'));
    assert.ok(webModule.includes('All Tags'));
    assert.ok(webModule.includes('Sort: Recently created'));
    assert.ok(webModule.includes('Clear filters'));
    assert.ok(webModule.includes('No notes in'));
    assert.ok(webModule.includes('Reuse tag:'));
    assert.strictEqual(/#[0-9a-fA-F]{3,8}\b/.test(webModule), false);

    // Flutter UI Stage N3.2 controls & zero Color(0x...) / Material Colors.*
    assert.ok(flutterNotesView.includes('New Folder'));
    assert.ok(flutterNotesView.includes('Delete Folder'));
    assert.ok(flutterNotesView.includes('Move to Folder'));
    assert.ok(flutterNotesView.includes('All Tags'));
    assert.ok(flutterNotesView.includes('Recently Created'));
    assert.ok(flutterNotesView.includes('Existing tags'));
    assert.ok(flutterNotesView.includes('initialCategory'));
    assert.strictEqual(/Color\(\s*0x/i.test(flutterNotesView), false);
    const flutterMaterialColors = (
      flutterNotesView.match(/\bColors\.[a-zA-Z0-9_]+/g) || []
    ).filter((m) => m !== 'Colors.transparent');
    assert.strictEqual(flutterMaterialColors.length, 0);

    // Flutter state/controller N3.2 methods
    assert.ok(flutterController.includes('createFolder'));
    assert.ok(flutterController.includes('renameFolder'));
    assert.ok(flutterController.includes('deleteFolder'));
    assert.ok(flutterController.includes('moveNoteToFolder'));
    assert.ok(flutterController.includes('setTagFilter'));
    assert.ok(flutterController.includes('setDateFilter'));
    assert.ok(flutterState.includes('availableTags'));
    assert.ok(flutterState.includes('customFolders'));
  });
});
