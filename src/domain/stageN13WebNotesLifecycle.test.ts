import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  DEFAULT_NOTE_TITLE,
  getNoteLifecycleState,
  MAX_NOTE_TITLE_LENGTH,
} from './noteHelpers';
import {
  getAvailableNotesToLink,
  getNotesLinkedToTask,
  TaskNoteRecord,
} from './taskNotes';
import {
  createQuickCaptureNoteRecord,
  createWebNoteRecord,
  emptyWebNotesTrash,
  filterAndSortWebNotes,
  getAvailableWebNotebooks,
  getDisplayNoteTitle,
  getWebNoteCounts,
  isNoteDraftBlank,
  moveWebNoteToTrash,
  permanentlyDeleteWebNote,
  resolveDefaultNotebookForTab,
  restoreWebNoteFromTrash,
  saveWebNoteDraft,
  toggleWebNoteArchive,
  toggleWebNoteFavorite,
  toggleWebNotePin,
} from './webNotesLifecycle';
import { notesService } from '../services/notesService';
import { SharedStateBridge } from '../services/sharedStateBridge';

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
    createdAt: overrides.createdAt ?? '2026-11-20T09:00:00.000Z',
    updatedAt: overrides.updatedAt ?? '2026-11-21T09:00:00.000Z',
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

describe('Stage N1.3 — Web Notes Lifecycle Parity & Draft Creation', () => {
  it('1. Enforces Active, Pinned, Favorite, Archived, and Trashed visibility, counts, notebooks, and search isolation', () => {
    const activePlain = makeNote('n-active', 'Morning Plan', {
      notebook: 'Personal',
      tags: ['focus'],
      updatedAt: '2026-11-21T10:00:00.000Z',
    });
    const activePinnedFav = makeNote('n-pin-fav', 'Quarterly Vision', {
      notebook: 'Work',
      isPinned: true,
      isFavorite: true,
      tags: ['vision', 'focus'],
      updatedAt: '2026-11-21T08:00:00.000Z',
    });
    const activeFavOnly = makeNote('n-fav', 'Amharic Proverbs', {
      notebook: 'Reflections',
      isFavorite: true,
      content: 'ሀገር በህዝብ ነው focus',
      updatedAt: '2026-11-21T12:00:00.000Z',
    });
    const archivedNote = makeNote('n-arch', 'Old Sprint Notes', {
      notebook: 'Work',
      isPinned: true,
      isFavorite: true,
      isArchived: true,
      tags: ['focus'],
      updatedAt: '2026-11-22T09:00:00.000Z',
    });
    const trashedActive = makeNote('n-trash-active', 'Discarded Idea', {
      notebook: 'TrashOnlyCustomNotebook',
      isPinned: true,
      isFavorite: true,
      isArchived: false,
      isTrashed: true,
      tags: ['focus'],
      updatedAt: '2026-11-23T09:00:00.000Z',
    });
    const trashedArchived = makeNote('n-trash-arch', 'Deleted Archive', {
      notebook: 'Work',
      isArchived: true,
      isTrashed: true,
      tags: ['focus'],
      updatedAt: '2026-11-23T11:00:00.000Z',
    });

    const input = [
      activePlain,
      activePinnedFav,
      activeFavOnly,
      archivedNote,
      trashedActive,
      trashedArchived,
    ];
    const snapshotBefore = JSON.stringify(input);

    const counts = getWebNoteCounts(input);
    assert.deepStrictEqual(counts, {
      active: 3,
      pinned: 1,
      favorites: 2,
      archived: 1,
      trash: 2,
    });

    // Notebooks exclude custom notebooks that only exist in Trash
    const notebooks = getAvailableWebNotebooks(input);
    assert.strictEqual(notebooks.includes('TrashOnlyCustomNotebook'), false);
    assert.ok(notebooks.includes('Personal'));
    assert.ok(notebooks.includes('Work'));

    // All Notes: active only, pinned first, then updatedAt desc
    assert.deepStrictEqual(
      filterAndSortWebNotes(input, { activeTab: 'all' }).map((n) => n.id),
      ['n-pin-fav', 'n-fav', 'n-active']
    );

    // Pinned: pinned active only (never archived/trashed)
    assert.deepStrictEqual(
      filterAndSortWebNotes(input, { activeTab: 'pinned' }).map((n) => n.id),
      ['n-pin-fav']
    );

    // Favorites: favorite active only (pinned first, never archived/trashed)
    assert.deepStrictEqual(
      filterAndSortWebNotes(input, { activeTab: 'favorites' }).map((n) => n.id),
      ['n-pin-fav', 'n-fav']
    );

    // Archived: archived & NOT trashed
    assert.deepStrictEqual(
      filterAndSortWebNotes(input, { activeTab: 'archived' }).map((n) => n.id),
      ['n-arch']
    );

    // Trash: trashed notes only (both active-trashed and archived-trashed)
    assert.deepStrictEqual(
      filterAndSortWebNotes(input, { activeTab: 'trash' }).map((n) => n.id),
      ['n-trash-arch', 'n-trash-active']
    );

    // Notebook filter: active notes in that notebook only
    assert.deepStrictEqual(
      filterAndSortWebNotes(input, { activeTab: 'Work' }).map((n) => n.id),
      ['n-pin-fav']
    );

    // Search respects lifecycle boundaries ('focus' tag is present on active, archived, and trashed)
    assert.deepStrictEqual(
      filterAndSortWebNotes(input, {
        activeTab: 'all',
        searchQuery: 'focus',
      }).map((n) => n.id),
      ['n-pin-fav', 'n-fav', 'n-active']
    );
    assert.deepStrictEqual(
      filterAndSortWebNotes(input, {
        activeTab: 'favorites',
        searchQuery: 'focus',
      }).map((n) => n.id),
      ['n-pin-fav', 'n-fav']
    );
    assert.deepStrictEqual(
      filterAndSortWebNotes(input, {
        activeTab: 'archived',
        searchQuery: 'focus',
      }).map((n) => n.id),
      ['n-arch']
    );
    assert.deepStrictEqual(
      filterAndSortWebNotes(input, {
        activeTab: 'trash',
        searchQuery: 'focus',
      }).map((n) => n.id),
      ['n-trash-arch', 'n-trash-active']
    );

    // Original array is never mutated
    assert.strictEqual(JSON.stringify(input), snapshotBefore);
  });

  it('2. Preserves metadata across pin, favorite, archive, trash, restore, and permanent delete transitions', () => {
    const base = makeNote('n-meta', 'Architecture Notes', {
      content: 'Important invariant',
      notebook: 'Work',
      tags: ['arch', 'v12'],
      isPinned: false,
      isFavorite: false,
      isArchived: false,
      isTrashed: false,
      projectId: 'proj-1',
      goalId: 'goal-1',
      linkedModule: 'tasks',
      linkedId: 'task-42',
      createdAt: '2026-11-01T08:00:00.000Z',
      updatedAt: '2026-11-02T08:00:00.000Z',
    });

    // Pin & Favorite preserve archive/trash states
    const pinned = toggleWebNotePin(
      [base],
      base.id,
      new Date('2026-11-03T08:00:00.000Z')
    );
    assert.strictEqual(pinned.ok, true);
    assert.strictEqual(pinned.updatedNote?.isPinned, true);
    assert.strictEqual(pinned.updatedNote?.isArchived, false);
    assert.strictEqual(pinned.updatedNote?.isTrashed, false);

    const fav = toggleWebNoteFavorite(
      pinned.notes,
      base.id,
      new Date('2026-11-03T09:00:00.000Z')
    );
    assert.strictEqual(fav.ok, true);
    assert.strictEqual(fav.updatedNote?.isFavorite, true);
    assert.strictEqual(fav.updatedNote?.isPinned, true);
    assert.strictEqual(fav.updatedNote?.isArchived, false);
    assert.strictEqual(fav.updatedNote?.isTrashed, false);

    // Archive preserves pin, favorite, tags, content, links
    const archived = toggleWebNoteArchive(
      fav.notes,
      base.id,
      new Date('2026-11-04T08:00:00.000Z')
    );
    assert.strictEqual(archived.ok, true);
    assert.strictEqual(getNoteLifecycleState(archived.updatedNote!), 'archived');
    assert.strictEqual(archived.updatedNote?.isPinned, true);
    assert.strictEqual(archived.updatedNote?.isFavorite, true);
    assert.strictEqual(archived.updatedNote?.linkedId, 'task-42');
    assert.strictEqual(archived.updatedNote?.projectId, 'proj-1');
    assert.strictEqual(archived.updatedNote?.goalId, 'goal-1');

    // Moving an archived note to Trash preserves isArchived & metadata
    const trashedFromArchive = moveWebNoteToTrash(
      archived.notes,
      base.id,
      new Date('2026-11-05T08:00:00.000Z')
    );
    assert.strictEqual(trashedFromArchive.ok, true);
    assert.strictEqual(
      getNoteLifecycleState(trashedFromArchive.updatedNote!),
      'trashed'
    );
    assert.strictEqual(trashedFromArchive.updatedNote?.isArchived, true);
    assert.strictEqual(trashedFromArchive.updatedNote?.content, 'Important invariant');
    assert.deepStrictEqual(trashedFromArchive.updatedNote?.tags, ['arch', 'v12']);
    assert.strictEqual(trashedFromArchive.updatedNote?.notebook, 'Work');
    assert.strictEqual(trashedFromArchive.updatedNote?.linkedId, 'task-42');

    // Pin / Favorite / Archive mutations refuse while note is in Trash
    assert.strictEqual(toggleWebNotePin(trashedFromArchive.notes, base.id).ok, false);
    assert.strictEqual(
      toggleWebNoteFavorite(trashedFromArchive.notes, base.id).ok,
      false
    );
    assert.strictEqual(
      toggleWebNoteArchive(trashedFromArchive.notes, base.id).ok,
      false
    );

    // Restoring archived-then-trashed note returns cleanly to Archived
    const restoredToArchive = restoreWebNoteFromTrash(
      trashedFromArchive.notes,
      base.id,
      new Date('2026-11-06T08:00:00.000Z')
    );
    assert.strictEqual(restoredToArchive.ok, true);
    assert.strictEqual(
      getNoteLifecycleState(restoredToArchive.updatedNote!),
      'archived'
    );
    assert.strictEqual(restoredToArchive.updatedNote?.isTrashed, false);
    assert.strictEqual(restoredToArchive.updatedNote?.isArchived, true);
    assert.strictEqual(restoredToArchive.updatedNote?.linkedId, 'task-42');

    // Unarchive returns to Active while keeping links/tags/favorite
    const restoredToActive = toggleWebNoteArchive(
      restoredToArchive.notes,
      base.id,
      new Date('2026-11-06T09:00:00.000Z')
    );
    assert.strictEqual(
      getNoteLifecycleState(restoredToActive.updatedNote!),
      'active'
    );

    // Permanent delete refuses active/archived notes unless trashed first
    const blockedDelete = permanentlyDeleteWebNote(restoredToActive.notes, base.id);
    assert.strictEqual(blockedDelete.ok, false);
    assert.strictEqual(blockedDelete.notes.length, 1);

    // Trash active note -> Restore returns to Active -> Trash again -> Permanent delete removes
    const trashedActive = moveWebNoteToTrash(restoredToActive.notes, base.id);
    const restoredActive = restoreWebNoteFromTrash(trashedActive.notes, base.id);
    assert.strictEqual(
      getNoteLifecycleState(restoredActive.updatedNote!),
      'active'
    );

    const trashedFinal = moveWebNoteToTrash(restoredActive.notes, base.id);
    const permDeleted = permanentlyDeleteWebNote(trashedFinal.notes, base.id);
    assert.strictEqual(permDeleted.ok, true);
    assert.strictEqual(permDeleted.notes.length, 0);

    // Empty trash only removes trashed notes
    const activeSurvivor = makeNote('n-keep', 'Keep Me');
    const trashVictim = makeNote('n-gone', 'Delete Me', { isTrashed: true });
    const emptied = emptyWebNotesTrash([activeSurvivor, trashVictim]);
    assert.strictEqual(emptied.deletedCount, 1);
    assert.deepStrictEqual(
      emptied.notes.map((n) => n.id),
      ['n-keep']
    );
  });

  it('3. Handles deferred draft creation, empty draft dismissal, Quick Capture, unique IDs, and 250-char title normalization', () => {
    assert.strictEqual(resolveDefaultNotebookForTab('all'), 'Personal');
    assert.strictEqual(resolveDefaultNotebookForTab('pinned'), 'Personal');
    assert.strictEqual(resolveDefaultNotebookForTab('favorites'), 'Personal');
    assert.strictEqual(resolveDefaultNotebookForTab('archived'), 'Personal');
    assert.strictEqual(resolveDefaultNotebookForTab('trash'), 'Personal');
    assert.strictEqual(resolveDefaultNotebookForTab('Work'), 'Work');

    assert.strictEqual(
      isNoteDraftBlank({ title: '  ', content: '\n\t', tags: [] }),
      true
    );
    assert.strictEqual(
      isNoteDraftBlank({ title: '', content: 'Idea', tags: [] }),
      false
    );
    assert.strictEqual(getDisplayNoteTitle('  '), DEFAULT_NOTE_TITLE);

    // Empty new draft does not pollute persisted notes
    const discarded = saveWebNoteDraft({
      notes: [],
      noteId: null,
      title: '   ',
      content: '',
      notebook: 'Personal',
      tags: [],
    });
    assert.strictEqual(discarded.status, 'discarded_empty');
    assert.strictEqual(discarded.notes.length, 0);

    // Draft with body and blank title persists safely with Untitled Note fallback & unique ID
    const fixedNow = new Date('2026-11-23T10:00:00.000Z');
    const firstSave = saveWebNoteDraft<TaskNoteRecord>({
      notes: [],
      noteId: null,
      title: '',
      content: 'First draft line',
      notebook: 'Reflections',
      tags: ['Draft', 'draft', '#ux'],
      nowUtc: fixedNow,
    });
    assert.strictEqual(firstSave.status, 'created');
    assert.ok(firstSave.note);
    assert.strictEqual(firstSave.note.title, DEFAULT_NOTE_TITLE);
    assert.strictEqual(firstSave.note.notebook, 'Reflections');
    assert.deepStrictEqual(firstSave.note.tags, ['Draft', '#ux']);
    assert.strictEqual(firstSave.note.isArchived, false);
    assert.strictEqual(firstSave.note.isTrashed, false);

    // Subsequent autosave against returned note.id updates the same note (no duplicate)
    const secondSave = saveWebNoteDraft<TaskNoteRecord>({
      notes: firstSave.notes,
      noteId: firstSave.note.id,
      title: 'A'.repeat(280),
      content: 'Updated draft body',
      notebook: 'Reflections',
      tags: ['Draft', '#ux'],
      nowUtc: new Date('2026-11-23T10:01:00.000Z'),
    });
    assert.strictEqual(secondSave.status, 'updated');
    assert.strictEqual(secondSave.notes.length, 1);
    assert.strictEqual(secondSave.note?.title.length, MAX_NOTE_TITLE_LENGTH);
    assert.strictEqual(secondSave.note?.content, 'Updated draft body');

    // Quick Capture note creation rejects empty input, supports full 250-char title, & prevents ID collisions
    const emptyQc = createQuickCaptureNoteRecord({
      existingNotes: secondSave.notes,
      rawText: '   \n ',
      nowUtc: fixedNow,
    });
    assert.strictEqual(emptyQc.ok, false);

    const longFirstLine = 'Ethiopian Calendar Sync Check '.padEnd(275, 'X');
    const qc1 = createQuickCaptureNoteRecord({
      existingNotes: secondSave.notes,
      rawText: `${longFirstLine}\nSecond line details`,
      nowUtc: fixedNow,
    });
    assert.strictEqual(qc1.ok, true);
    assert.strictEqual(qc1.note.title.length, MAX_NOTE_TITLE_LENGTH);
    assert.deepStrictEqual(qc1.note.tags, ['quick_capture']);
    assert.strictEqual(qc1.note.notebook, 'Personal');
    assert.strictEqual(qc1.note.isFavorite, false);
    assert.strictEqual(qc1.note.isTrashed, false);

    const qc2 = createQuickCaptureNoteRecord({
      existingNotes: qc1.notes,
      rawText: 'Second capture in same millisecond',
      nowUtc: fixedNow,
    });
    assert.strictEqual(qc2.ok, true);
    assert.notStrictEqual(qc2.note.id, qc1.note.id);
    assert.strictEqual(qc2.notes.length, 3);

    // Trashed notes are never modified by autosave draft commits
    const trashedNote = moveWebNoteToTrash(qc2.notes, qc2.note.id);
    const blockedEdit = saveWebNoteDraft({
      notes: trashedNote.notes,
      noteId: qc2.note.id,
      title: 'Attempted Edit While Trashed',
      content: 'Should not save',
      notebook: 'Personal',
      tags: [],
    });
    assert.strictEqual(blockedEdit.status, 'unchanged');
  });

  it('4. Preserves lifecycle flags across notesService, SharedStateBridge, and Task–Notes integration', () => {
    withMockBrowserStorage((store) => {
      const favActive = createWebNoteRecord({
        existingNotes: [],
        id: 'note-fav-1',
        title: 'Task Reference',
        content: 'Linked active favorite',
        notebook: 'Work',
        isFavorite: true,
        isPinned: true,
        linkedModule: 'tasks',
        linkedId: 'task-1',
      });
      const trashedLinked = createWebNoteRecord({
        existingNotes: [favActive],
        id: 'note-trash-1',
        title: 'Old Task Draft',
        content: 'Moved to trash',
        notebook: 'Work',
        isArchived: true,
        isTrashed: true,
        linkedModule: 'tasks',
        linkedId: 'task-1',
      });

      const saved = notesService.saveNotes([favActive, trashedLinked]);
      assert.strictEqual(saved.length, 2);

      // Task linking excludes trashed notes while keeping active linked note
      assert.deepStrictEqual(
        getNotesLinkedToTask(saved, 'task-1').map((n) => n.id),
        ['note-fav-1']
      );
      assert.deepStrictEqual(
        getAvailableNotesToLink(saved, 'task-other').map((o) => o.note.id),
        ['note-fav-1']
      );

      // Canonical backup export & restore preserves isFavorite & isTrashed
      const exported = SharedStateBridge.exportToAndroidJson();
      store.clear();
      const imported = SharedStateBridge.importFromAndroidJson(exported);
      assert.strictEqual(imported.success, true, imported.error);

      const reloaded = notesService.loadNotes();
      const reloadedFav = reloaded.find((n) => n.id === 'note-fav-1')!;
      const reloadedTrash = reloaded.find((n) => n.id === 'note-trash-1')!;
      assert.strictEqual(reloadedFav.isFavorite, true);
      assert.strictEqual(reloadedFav.isPinned, true);
      assert.strictEqual(reloadedFav.isTrashed, false);
      assert.strictEqual(reloadedTrash.isTrashed, true);
      assert.strictEqual(reloadedTrash.isArchived, true);
    });
  });

  it('5. Maintains pure Web Notes domain boundaries and canonical UI token hygiene', () => {
    const repoRoot = path.resolve(process.cwd());
    const lifecycleDomain = fs.readFileSync(
      path.join(repoRoot, 'src/domain/webNotesLifecycle.ts'),
      'utf8'
    );
    const webNotesUi = fs.readFileSync(
      path.join(repoRoot, 'src/components/DaywellNotesModule.tsx'),
      'utf8'
    );

    assert.strictEqual(/from ['"]react['"]/.test(lifecycleDomain), false);
    assert.strictEqual(lifecycleDomain.includes('localStorage'), false);
    assert.strictEqual(lifecycleDomain.includes('window.'), false);
    assert.strictEqual(/#[0-9a-fA-F]{3,8}\b/.test(webNotesUi), false);
  });
});
