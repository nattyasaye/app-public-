import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createTaskRecord, DaywellTaskRecord, setTaskArchivedRecord } from './taskOperations';
import {
  buildBoundedTaskNoteTitle,
  countNotesLinkedToTask,
  createNoteForTask,
  getAvailableNotesToLink,
  getLinkedTaskForNote,
  getNotesLinkedToTask,
  linkNoteToTask,
  MAX_NOTE_TITLE_LENGTH,
  TaskNoteRecord,
  unlinkNoteFromTask,
  unlinkNotesForDeletedTask,
} from './taskNotes';
import { notesService } from '../services/notesService';
import { SharedStateBridge } from '../services/sharedStateBridge';

function makeTask(
  id: string,
  title: string,
  overrides: Partial<DaywellTaskRecord> = {}
): DaywellTaskRecord {
  const created = createTaskRecord(
    {
      id,
      title,
      priority: overrides.priority ?? 'medium',
      status: overrides.status ?? 'not_started',
      dueDate: overrides.dueDate,
      scheduledDate: overrides.scheduledDate,
    },
    new Date('2026-11-22T09:00:00.000Z')
  );
  if (!created.ok) {
    throw new Error(
      `Failed to build fixture task ${id}: ${JSON.stringify(created.errors)}`
    );
  }
  return { ...created.task, ...overrides };
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
    isArchived: overrides.isArchived ?? false,
    ...(overrides.isFavorite !== undefined
      ? { isFavorite: overrides.isFavorite }
      : {}),
    ...(overrides.isTrashed !== undefined
      ? { isTrashed: overrides.isTrashed }
      : {}),
    ...(overrides.linkedModule !== undefined
      ? { linkedModule: overrides.linkedModule }
      : {}),
    ...(overrides.linkedId !== undefined ? { linkedId: overrides.linkedId } : {}),
    createdAt: overrides.createdAt ?? '2026-11-20T09:00:00.000Z',
    updatedAt: overrides.updatedAt ?? '2026-11-21T09:00:00.000Z',
  };
}

function withMockBrowserStorage(
  fn: (
    store: Map<string, string>,
    dispatchedEvents: Array<{ type: string; detail: unknown }>
  ) => void
): void {
  const store = new Map<string, string>();
  const dispatchedEvents: Array<{ type: string; detail: unknown }> = [];
  const prevWindow = (globalThis as any).window;
  const prevLocalStorage = (globalThis as any).localStorage;
  const mockStorage = {
    getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
    setItem: (k: string, v: string) => void store.set(k, String(v)),
    removeItem: (k: string) => void store.delete(k),
    clear: () => void store.clear(),
  };

  (globalThis as any).localStorage = mockStorage;
  (globalThis as any).window = {
    dispatchEvent: (evt: { type: string; detail?: unknown }) => {
      dispatchedEvents.push({ type: evt.type, detail: evt.detail });
      return true;
    },
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
    fn(store, dispatchedEvents);
  } finally {
    (globalThis as any).window = prevWindow;
    (globalThis as any).localStorage = prevLocalStorage;
  }
}

describe('Stage 7 — Task and Notes Integration (Web Domain, Bridge & Governance)', () => {
  it('1. Associates an existing note with a task, queries linked/available notes, and preserves existing note metadata', () => {
    const t1 = makeTask('task-1', 'Prepare architecture review');
    const t2 = makeTask('task-2', 'Book flights');

    const n1 = makeNote('note-1', 'Architecture decisions', {
      content: 'Use single source of truth.',
      notebook: 'Work',
      tags: ['arch'],
      isPinned: true,
      updatedAt: '2026-11-21T10:00:00.000Z',
    });
    const n2 = makeNote('note-2', 'Flight checklist', {
      linkedModule: 'tasks',
      linkedId: t2.id,
      updatedAt: '2026-11-21T12:00:00.000Z',
    });
    const trashed = makeNote('note-trash', 'Discarded draft', {
      isTrashed: true,
      linkedModule: 'tasks',
      linkedId: t1.id,
    });

    const availBefore = getAvailableNotesToLink([n1, n2, trashed], t1.id);
    assert.deepStrictEqual(
      availBefore.map((o) => o.note.id),
      ['note-1', 'note-2']
    );
    assert.strictEqual(availBefore[0].linkedTaskId, undefined);
    assert.strictEqual(availBefore[1].linkedTaskId, t2.id);

    const linkedRes = linkNoteToTask(
      [n1, n2, trashed],
      n1.id,
      t1.id,
      new Date('2026-11-22T11:00:00.000Z')
    );
    assert.strictEqual(linkedRes.ok, true);
    assert.strictEqual(linkedRes.updatedNote?.linkedModule, 'tasks');
    assert.strictEqual(linkedRes.updatedNote?.linkedId, t1.id);
    assert.strictEqual(linkedRes.updatedNote?.content, 'Use single source of truth.');
    assert.deepStrictEqual(linkedRes.updatedNote?.tags, ['arch']);
    assert.strictEqual(linkedRes.updatedNote?.isPinned, true);

    const linkedForT1 = getNotesLinkedToTask(linkedRes.notes, t1.id);
    assert.strictEqual(linkedForT1.length, 1);
    assert.strictEqual(linkedForT1[0].id, 'note-1');
    assert.strictEqual(countNotesLinkedToTask(linkedRes.notes, t1.id), 1);

    const availAfter = getAvailableNotesToLink(linkedRes.notes, t1.id, 'flight');
    assert.deepStrictEqual(
      availAfter.map((o) => o.note.id),
      ['note-2']
    );

    const invalidRes = linkNoteToTask(linkedRes.notes, 'missing-note', t1.id);
    assert.strictEqual(invalidRes.ok, false);
  });

  it('2. Creates a new note from a task with unique IDs and bounded <=250-char titles', () => {
    const longTitle = 'A'.repeat(295);
    const task = {
      ...makeTask('task-long', 'Architecture audit follow-up'),
      title: longTitle,
    };
    const fixedNow = new Date('2026-11-22T12:00:00.000Z');

    assert.strictEqual(
      buildBoundedTaskNoteTitle(longTitle).length,
      MAX_NOTE_TITLE_LENGTH
    );

    const first = createNoteForTask<TaskNoteRecord>({
      notes: [],
      task,
      nowUtc: fixedNow,
    });
    assert.strictEqual(first.ok, true);
    assert.ok(first.note);
    assert.strictEqual(first.note.title.length, MAX_NOTE_TITLE_LENGTH);
    assert.strictEqual(first.note.linkedModule, 'tasks');
    assert.strictEqual(first.note.linkedId, task.id);

    // Rapid second note creation with the same timestamp produces a distinct ID
    const second = createNoteForTask({
      notes: first.notes,
      task,
      nowUtc: fixedNow,
    });
    assert.strictEqual(second.ok, true);
    assert.ok(second.note);
    assert.notStrictEqual(second.note.id, first.note.id);
    assert.strictEqual(countNotesLinkedToTask(second.notes, task.id), 2);
  });

  it('3. Resolves relationships bidirectionally and keeps Notes intact on unlink, archive, and task deletion', () => {
    const task = makeTask('task-keep', 'Quarterly finance check');
    const archivedTask = setTaskArchivedRecord(
      makeTask('task-arch', 'Archived task'),
      true
    );
    const noteA = makeNote('note-a', 'CBE reconciliation steps', {
      content: 'Important checklist content',
      tags: ['finance'],
      linkedModule: 'tasks',
      linkedId: task.id,
    });
    const noteB = makeNote('note-b', 'Archived note for archived task', {
      content: 'Historical audit note',
      isArchived: true,
      linkedModule: 'tasks',
      linkedId: archivedTask.id,
    });
    const unrelatedNote = makeNote('note-c', 'Unrelated calendar note', {
      linkedModule: 'calendar',
      linkedId: 'evt-7',
    });

    // Bidirectional lookup works for active and archived tasks/notes
    assert.strictEqual(
      getLinkedTaskForNote(noteA, [task, archivedTask])?.id,
      task.id
    );
    assert.strictEqual(
      getLinkedTaskForNote(noteB, [task, archivedTask])?.id,
      archivedTask.id
    );
    assert.strictEqual(
      getNotesLinkedToTask([noteA, noteB], archivedTask.id).length,
      1
    );
    assert.strictEqual(
      getNotesLinkedToTask([noteA, noteB], archivedTask.id, {
        includeArchived: false,
      }).length,
      0
    );

    // Manual unlink preserves the note record while clearing link fields
    const unlinked = unlinkNoteFromTask(
      [noteA, noteB, unrelatedNote],
      noteA.id,
      task.id
    );
    assert.strictEqual(unlinked.ok, true);
    assert.strictEqual(unlinked.notes.length, 3);
    const noteAAfterUnlink = unlinked.notes.find((n) => n.id === noteA.id)!;
    assert.strictEqual(noteAAfterUnlink.content, 'Important checklist content');
    assert.strictEqual(noteAAfterUnlink.linkedModule, undefined);
    assert.strictEqual(noteAAfterUnlink.linkedId, undefined);

    // Deleting a task NEVER deletes linked notes; only unlinks task link safely
    const onDelete = unlinkNotesForDeletedTask(
      [noteA, noteB, unrelatedNote],
      task.id
    );
    assert.strictEqual(onDelete.unlinkedCount, 1);
    assert.deepStrictEqual(onDelete.unlinkedNoteIds, [noteA.id]);
    assert.strictEqual(onDelete.notes.length, 3);
    const preservedNote = onDelete.notes.find((n) => n.id === noteA.id)!;
    assert.strictEqual(preservedNote.title, 'CBE reconciliation steps');
    assert.strictEqual(preservedNote.content, 'Important checklist content');
    assert.deepStrictEqual(preservedNote.tags, ['finance']);
    assert.strictEqual(preservedNote.linkedModule, undefined);
    assert.strictEqual(preservedNote.linkedId, undefined);
    // Unrelated links remain untouched
    const calNote = onDelete.notes.find((n) => n.id === unrelatedNote.id)!;
    assert.strictEqual(calNote.linkedModule, 'calendar');
    assert.strictEqual(calNote.linkedId, 'evt-7');
  });

  it('4. Preserves Task–Notes links across notesService and SharedStateBridge canonical backup export & restore', () => {
    withMockBrowserStorage((store, events) => {
      const task = makeTask('task-backup', 'Renew residence permit', {
        dueDate: '2026-12-05',
      });
      const secondTask = makeTask('task-long-backup', 'L'.repeat(240));

      store.set('daywell_tasks', JSON.stringify([task, secondTask]));

      const createdFirst = createNoteForTask<TaskNoteRecord>({
        notes: [],
        task,
        id: 'note-backup-1',
        content: 'Bring passport copy and 2 photos.',
      });
      const createdSecond = createNoteForTask({
        notes: createdFirst.notes,
        task: secondTask,
        id: 'note-backup-2',
        title: 'L'.repeat(280),
        content: 'Long task note stays valid for 250-char backup limit.',
      });

      const saved = notesService.saveNotes(createdSecond.notes);
      assert.strictEqual(saved.length, 2);
      assert.strictEqual(events.length, 1);
      assert.strictEqual(events[0].type, SharedStateBridge.SYNC_EVENT_NAME);

      const exportedJson = SharedStateBridge.exportToAndroidJson();
      const parsedExport = JSON.parse(exportedJson);
      const exportedNote1 = parsedExport.notes.find(
        (n: any) => n.id === 'note-backup-1'
      );
      assert.strictEqual(exportedNote1.linkedModule, 'tasks');
      assert.strictEqual(exportedNote1.linkedId, 'task-backup');

      // Wipe storage and restore from canonical backup JSON
      store.clear();
      const restored = SharedStateBridge.importFromAndroidJson(exportedJson);
      assert.strictEqual(restored.success, true, restored.error);

      const loadedNotes = notesService.loadNotes();
      assert.strictEqual(loadedNotes.length, 2);
      const restoredNote1 = loadedNotes.find((n) => n.id === 'note-backup-1')!;
      assert.strictEqual(restoredNote1.linkedModule, 'tasks');
      assert.strictEqual(restoredNote1.linkedId, 'task-backup');
      assert.strictEqual(restoredNote1.content, 'Bring passport copy and 2 photos.');

      const restoredNote2 = loadedNotes.find((n) => n.id === 'note-backup-2')!;
      assert.strictEqual(restoredNote2.title.length, MAX_NOTE_TITLE_LENGTH);
      assert.strictEqual(restoredNote2.linkedModule, 'tasks');
      assert.strictEqual(restoredNote2.linkedId, 'task-long-backup');

      // Backward compatibility: legacy v4 backup note without linkedModule/linkedId still imports safely
      const { snapshotFormatVersion: _legacyFormat, ...legacyBase } = parsedExport;
      const legacyPayload = {
        ...legacyBase,
        schemaVersion: 4,
        snapshotFormatVersion: 1,
        notes: [
          {
            id: 'note-legacy',
            title: 'Legacy Unlinked Note',
            body: 'Created before Stage 7',
            folder: 'Personal',
            tags: [],
            isPinned: false,
            isArchived: false,
            createdAt: '2026-10-01T08:00:00.000Z',
            updatedAt: '2026-10-01T08:00:00.000Z',
          },
        ],
      };
      const legacyRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify(legacyPayload)
      );
      assert.strictEqual(legacyRes.success, true, legacyRes.error);
      const legacyLoaded = notesService.loadNotes();
      assert.strictEqual(legacyLoaded.length, 1);
      assert.strictEqual(legacyLoaded[0].linkedModule, undefined);
      assert.strictEqual(legacyLoaded[0].linkedId, undefined);
    });
  });

  it('5. Enforces Web architectural boundaries, single Notes owner, and canonical UI token hygiene', () => {
    const repoRoot = path.resolve(process.cwd());
    const taskNotesDomain = fs.readFileSync(
      path.join(repoRoot, 'src/domain/taskNotes.ts'),
      'utf8'
    );
    const webTasks = fs.readFileSync(
      path.join(repoRoot, 'src/components/DaywellTasksModule.tsx'),
      'utf8'
    );
    const webNotes = fs.readFileSync(
      path.join(repoRoot, 'src/components/DaywellNotesModule.tsx'),
      'utf8'
    );
    const webApp = fs.readFileSync(path.join(repoRoot, 'src/App.tsx'), 'utf8');

    // Pure domain layer stays free of React/DOM/localStorage
    assert.strictEqual(/from ['"]react['"]/.test(taskNotesDomain), false);
    assert.strictEqual(taskNotesDomain.includes('localStorage'), false);

    // Tasks delegates to Notes instead of implementing a duplicate note editor
    assert.strictEqual(webTasks.includes('note-content-editor'), false);
    assert.ok(webTasks.includes('getNotesLinkedToTask'));
    assert.ok(webTasks.includes('createNoteForTask'));
    assert.ok(webTasks.includes('linkNoteToTask'));
    assert.ok(webTasks.includes('unlinkNoteFromTask'));
    assert.ok(webTasks.includes('unlinkNotesForDeletedTask'));
    assert.ok(webTasks.includes('onNavigateToNote'));

    // Notes owns editing & supports bidirectional navigation back to Task details
    assert.ok(webNotes.includes('getLinkedTaskForNote'));
    assert.ok(webNotes.includes('requestedNoteFocus'));
    assert.ok(webNotes.includes('onNavigateToTask'));

    // App shell synchronizes notes state across both modules
    assert.ok(webApp.includes('requestedNoteFocus'));
    assert.ok(webApp.includes('onNavigateToNote'));
    assert.ok(webApp.includes('onNavigateToTask'));

    // Zero hardcoded hex colors in modified Web modules
    assert.strictEqual(/#[0-9a-fA-F]{3,8}\b/.test(webTasks), false);
    assert.strictEqual(/#[0-9a-fA-F]{3,8}\b/.test(webNotes), false);
  });
});
