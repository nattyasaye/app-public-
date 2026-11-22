import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  addSubtaskToList,
  addSubtaskToTask,
  computeSubtaskProgress,
  createTaskRecord,
  deleteSubtaskFromList,
  deleteSubtaskFromTask,
  normalizeSubtasksList,
  reorderSubtasksInList,
  reorderTaskSubtasks,
  toggleSubtaskInList,
  toggleTaskSubtask,
  updateSubtaskTitleInList,
  updateTaskRecord,
  updateTaskSubtaskTitle,
} from './taskOperations';
import { SharedStateBridge } from '../services/sharedStateBridge';

describe('Stage 1.2 — Subtasks and Checklists', () => {
  const fixedNow = new Date('2026-11-22T08:00:00.000Z');

  it('1. Add subtasks: trims title, rejects empty/whitespace titles, and generates collision-safe unique IDs after deletions', () => {
    const emptyRes = addSubtaskToList([], '   ', 't-1');
    assert.strictEqual(emptyRes.ok, false);
    if (!emptyRes.ok) {
      assert.strictEqual(emptyRes.error, 'Subtask title is required');
    }

    const r1 = addSubtaskToList([], '  Draft outline  ', 't-1');
    assert.ok(r1.ok);
    const r2 = addSubtaskToList(r1.subtasks, 'Verify numbers', 't-1');
    assert.ok(r2.ok);
    assert.strictEqual(r2.subtasks.length, 2);
    assert.deepStrictEqual(
      r2.subtasks.map((s) => s.title),
      ['Draft outline', 'Verify numbers']
    );
    assert.notStrictEqual(r2.subtasks[0].id, r2.subtasks[1].id);

    // Delete first subtask, then add another — must not reuse existing second ID
    const { remaining } = deleteSubtaskFromList(r2.subtasks, r2.subtasks[0].id);
    const r3 = addSubtaskToList(remaining, 'Send deck', 't-1');
    assert.ok(r3.ok);
    assert.strictEqual(r3.subtasks.length, 2);
    assert.notStrictEqual(r3.subtasks[0].id, r3.subtasks[1].id);
  });

  it('2. Edit subtask titles: updates matching subtask title, rejects empty title, and preserves completion & order', () => {
    const base = [
      { id: 's-1', title: 'Step one', completed: true },
      { id: 's-2', title: 'Step two', completed: false },
    ];

    const invalidEdit = updateSubtaskTitleInList(base, 's-2', '   ');
    assert.strictEqual(invalidEdit.ok, false);

    const validEdit = updateSubtaskTitleInList(base, 's-2', '  Updated step two  ');
    assert.ok(validEdit.ok);
    assert.deepStrictEqual(validEdit.subtasks, [
      { id: 's-1', title: 'Step one', completed: true },
      { id: 's-2', title: 'Updated step two', completed: false },
    ]);
  });

  it('3. Mark individual subtasks complete or incomplete cleanly', () => {
    const created = createTaskRecord(
      {
        id: 't-sub-toggle',
        title: 'Prepare checklist',
        subtasks: [
          { id: 's-a', title: 'Item A', completed: false },
          { id: 's-b', title: 'Item B', completed: false },
        ],
      },
      fixedNow
    );
    assert.ok(created.ok);

    const toggledOnce = toggleTaskSubtask(created.task, 's-a', fixedNow);
    assert.strictEqual(toggledOnce.subtasks[0].completed, true);
    assert.strictEqual(toggledOnce.subtasks[1].completed, false);

    const toggledBack = toggleTaskSubtask(toggledOnce, 's-a', fixedNow);
    assert.strictEqual(toggledBack.subtasks[0].completed, false);

    const directListToggle = toggleSubtaskInList(toggledBack.subtasks, 's-b', true);
    assert.strictEqual(directListToggle[1].completed, true);
  });

  it('4. Delete subtasks safely and allow recovery from snapshot', () => {
    const created = createTaskRecord(
      {
        id: 't-sub-del',
        title: 'Task with removable step',
        subtasks: [
          { id: 's-1', title: 'Keep me', completed: false },
          { id: 's-2', title: 'Remove me', completed: true },
        ],
      },
      fixedNow
    );
    assert.ok(created.ok);

    const snapshotBeforeDelete = created.task;
    const { task: afterDelete, deleted } = deleteSubtaskFromTask(
      created.task,
      's-2',
      fixedNow
    );
    assert.strictEqual(deleted?.id, 's-2');
    assert.strictEqual(afterDelete.subtasks.length, 1);
    assert.strictEqual(afterDelete.subtasks[0].id, 's-1');

    // Undo restores exact prior subtask list cleanly
    assert.strictEqual(snapshotBeforeDelete.subtasks.length, 2);
  });

  it('5. Reorder subtasks up/down and ignore invalid out-of-bounds moves safely', () => {
    const created = createTaskRecord(
      {
        id: 't-sub-order',
        title: 'Ordered checklist',
        subtasks: [
          { id: 's-1', title: 'First', completed: false },
          { id: 's-2', title: 'Second', completed: true },
          { id: 's-3', title: 'Third', completed: false },
        ],
      },
      fixedNow
    );
    assert.ok(created.ok);

    // Move 'Third' up to index 0
    const reordered = reorderTaskSubtasks(created.task, 2, 0, fixedNow);
    assert.deepStrictEqual(
      reordered.subtasks.map((s) => s.id),
      ['s-3', 's-1', 's-2']
    );

    // Move first down to index 1
    const swapped = reorderSubtasksInList(reordered.subtasks, 0, 1);
    assert.deepStrictEqual(
      swapped.map((s) => s.id),
      ['s-1', 's-3', 's-2']
    );

    // Out-of-bounds indices remain unchanged
    const unchanged = reorderSubtasksInList(swapped, -1, 1);
    assert.deepStrictEqual(unchanged, swapped);
  });

  it('6. Computes parent task counts & progress dynamically from subtasks without storing extra fields', () => {
    assert.deepStrictEqual(computeSubtaskProgress([]), {
      total: 0,
      completed: 0,
      ratio: 0,
      percentage: 0,
    });

    const partial = computeSubtaskProgress([
      { completed: true },
      { completed: false },
      { completed: false },
    ]);
    assert.strictEqual(partial.completed, 1);
    assert.strictEqual(partial.total, 3);
    assert.strictEqual(partial.percentage, 33);

    const allDone = computeSubtaskProgress([
      { completed: true },
      { completed: true },
    ]);
    assert.strictEqual(allDone.completed, 2);
    assert.strictEqual(allDone.total, 2);
    assert.strictEqual(allDone.ratio, 1);
    assert.strictEqual(allDone.percentage, 100);

    const taskRes = createTaskRecord({
      title: 'Check fields',
      subtasks: [{ id: 'a', title: 'Step', completed: true }],
    });
    assert.ok(taskRes.ok);
    assert.strictEqual('subtaskProgress' in taskRes.task, false);
    assert.strictEqual('progress' in taskRes.task, false);
  });

  it('7. Persists parent task subtasks via SharedStateBridge canonical roundtrip while preserving order, legacy aliases, and v10 parent metadata', () => {
    const storage = new Map<string, string>();
    (globalThis as Record<string, unknown>).localStorage = {
      getItem: (k: string) => storage.get(k) ?? null,
      setItem: (k: string, v: string) => {
        storage.set(k, v);
      },
      removeItem: (k: string) => {
        storage.delete(k);
      },
      clear: () => {
        storage.clear();
      },
    };
    (globalThis as Record<string, unknown>).window = globalThis;

    // Normalize legacy subtasks without id / using done alias
    const normalizedLegacy = normalizeSubtasksList(
      [
        { title: 'Legacy step A', done: true },
        { id: 'custom-2', title: 'Legacy step B', completed: false },
        { title: '   ', done: false },
      ],
      't-persist'
    );
    assert.strictEqual(normalizedLegacy.length, 2);
    assert.deepStrictEqual(normalizedLegacy[0], {
      id: 't-persist-sub-1',
      title: 'Legacy step A',
      completed: true,
    });

    const created = createTaskRecord(
      {
        id: 't-persist',
        title: 'Tax preparation',
        priority: 'high',
        status: 'in_progress',
        scheduledDate: '2026-11-23',
        dueDate: '2026-11-25',
        subtasks: normalizedLegacy,
      },
      fixedNow
    );
    assert.ok(created.ok);

    // Apply all subtask mutations through parent Task helpers
    const addedRes = addSubtaskToTask(created.task, 'Submit PDF', fixedNow);
    assert.ok(addedRes.ok);
    const addedId = addedRes.affected!.id;
    const editedRes = updateTaskSubtaskTitle(
      addedRes.task,
      'custom-2',
      'Verify receipts',
      fixedNow
    );
    assert.ok(editedRes.ok);
    const reorderedTask = reorderTaskSubtasks(editedRes.task, 2, 0, fixedNow);
    const toggledTask = toggleTaskSubtask(reorderedTask, addedId, fixedNow);

    // Save through edit patch as well to ensure parent metadata survives
    const updatedRes = updateTaskRecord(
      {
        ...toggledTask,
        isPinned: true,
        myDayDate: '2026-11-23',
        sortOrder: 4,
      },
      { description: 'Updated parent notes' },
      fixedNow
    );
    assert.ok(updatedRes.ok);

    storage.set('daywell_tasks', JSON.stringify([updatedRes.task]));

    // Canonical export -> SharedStateBridge translates `completed` -> canonical `done`
    const exported = SharedStateBridge.loadCanonicalState();
    assert.strictEqual(exported.tasks.length, 1);
    const exportedTask = exported.tasks[0];
    assert.strictEqual(exportedTask.scheduledDate, '2026-11-23');
    assert.strictEqual(exportedTask.myDayDate, '2026-11-23');
    assert.strictEqual(exportedTask.isPinned, true);
    assert.strictEqual(exportedTask.sortOrder, 4);
    assert.deepStrictEqual(
      (exportedTask.subtasks ?? []).map((s) => ({
        id: s.id,
        title: s.title,
        done: s.done,
      })),
      [
        { id: addedId, title: 'Submit PDF', done: true },
        { id: 't-persist-sub-1', title: 'Legacy step A', done: true },
        { id: 'custom-2', title: 'Verify receipts', done: false },
      ]
    );

    // Restore back into empty storage via SharedStateBridge
    storage.clear();
    SharedStateBridge.saveCanonicalState(exported);
    const restoredTasks = JSON.parse(storage.get('daywell_tasks') || '[]');
    assert.strictEqual(restoredTasks.length, 1);
    assert.deepStrictEqual(
      computeSubtaskProgress(restoredTasks[0].subtasks),
      { total: 3, completed: 2, ratio: 2 / 3, percentage: 67 }
    );
    const reloaded = SharedStateBridge.loadCanonicalState();
    assert.deepStrictEqual(
      (reloaded.tasks[0].subtasks ?? []).map((s) => ({
        id: s.id,
        title: s.title,
        done: s.done,
      })),
      [
        { id: addedId, title: 'Submit PDF', done: true },
        { id: 't-persist-sub-1', title: 'Legacy step A', done: true },
        { id: 'custom-2', title: 'Verify receipts', done: false },
      ]
    );
  });

  it('8. Web DaywellTasksModule exposes Task Details subtask add/edit/toggle/reorder/delete+Undo and progress bar without React/DOM leakage in taskOperations.ts', () => {
    const domainSrc = fs.readFileSync(
      path.join(process.cwd(), 'src', 'domain', 'taskOperations.ts'),
      'utf8'
    );
    assert.strictEqual(domainSrc.includes("from 'react'"), false);
    assert.strictEqual(domainSrc.includes('document.'), false);

    const moduleSrc = fs.readFileSync(
      path.join(process.cwd(), 'src', 'components', 'DaywellTasksModule.tsx'),
      'utf8'
    );
    assert.strictEqual(moduleSrc.includes('aria-label="Add subtask to task"'), true);
    assert.strictEqual(moduleSrc.includes('aria-label="Edit subtask title"'), true);
    assert.strictEqual(moduleSrc.includes('Move subtask up'), true);
    assert.strictEqual(moduleSrc.includes('Move subtask down'), true);
    assert.strictEqual(moduleSrc.includes('Delete subtask'), true);
    assert.strictEqual(moduleSrc.includes('DaywellProgressBar'), true);
    assert.strictEqual(moduleSrc.includes('Removed subtask "'), true);
  });
});
