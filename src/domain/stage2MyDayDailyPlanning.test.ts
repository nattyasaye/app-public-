import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  buildDailyPlanSnapshot,
  carryForwardUnfinishedTasks,
  findDailyPlanningEntry,
  isTaskPlannedForDate,
  movePlannedTaskOrder,
  planTaskForDate,
  removeTaskFromPlannedDay,
  reorderPlannedTasks,
  syncTaskCompletionWithDailyPlanning,
} from './dailyPlanningOperations';
import { createTaskRecord, DaywellTaskRecord } from './taskOperations';
import { dailyPlanningService } from '../services/dailyPlanningService';
import { SharedStateBridge } from '../services/sharedStateBridge';

function withMockBrowserStorage(fn: (store: Map<string, string>) => void): void {
  const store = new Map<string, string>();
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

function makeTask(
  id: string,
  title: string,
  overrides: Partial<DaywellTaskRecord> = {}
): DaywellTaskRecord {
  const created = createTaskRecord(
    {
      id,
      title,
      priority: 'medium',
      status: 'not_started',
      ...overrides,
    },
    new Date('2026-11-20T09:00:00.000Z')
  );
  if (!created.ok) {
    throw new Error(
      `Failed to create fixture task ${id}: ${JSON.stringify(created.errors)}`
    );
  }
  return { ...created.task, ...overrides };
}

describe('Stage 2 — My Day and Daily Planning (Web Domain, Service, Bridge & UI)', () => {
  it('1. Plans tasks for a selected day and removes them from My Day without deleting the underlying Task', () => {
    const today = '2026-11-22';
    const taskA = makeTask('t-a', 'Review weekly budget');
    const taskB = makeTask('t-b', 'Call client');

    const plannedA = planTaskForDate([taskA, taskB], [], 't-a', today, {
      todayIso: today,
    });
    assert.strictEqual(plannedA.tasks.length, 2);
    assert.strictEqual(plannedA.entries.length, 1);
    assert.strictEqual(plannedA.entries[0].action, 'planned');
    assert.strictEqual(
      isTaskPlannedForDate(
        plannedA.tasks.find((t) => t.id === 't-a')!,
        plannedA.entries,
        today,
        today
      ),
      true
    );

    // Removing from My Day dismisses the plan entry without deleting task-a
    const removed = removeTaskFromPlannedDay(
      plannedA.tasks,
      plannedA.entries,
      't-a',
      today,
      { todayIso: today }
    );
    assert.strictEqual(removed.tasks.length, 2);
    const underlyingA = removed.tasks.find((t) => t.id === 't-a')!;
    assert.ok(underlyingA);
    assert.strictEqual(underlyingA.isMyDay, false);
    assert.strictEqual(
      findDailyPlanningEntry(removed.entries, 't-a', today)?.action,
      'dismissed'
    );
    assert.strictEqual(
      isTaskPlannedForDate(underlyingA, removed.entries, today, today),
      false
    );

    const snapshot = buildDailyPlanSnapshot(
      removed.tasks,
      removed.entries,
      today,
      today
    );
    assert.strictEqual(snapshot.totalPlannedCount, 0);
    assert.strictEqual(snapshot.dismissedCount, 1);
    assert.ok(snapshot.otherActiveTasks.some((t) => t.id === 't-a'));
  });

  it('2. Reorders planned tasks cleanly via movePlannedTaskOrder & reorderPlannedTasks', () => {
    const today = '2026-11-22';
    const t1 = makeTask('t-1', 'First', { sortOrder: 0 });
    const t2 = makeTask('t-2', 'Second', { sortOrder: 1 });
    const t3 = makeTask('t-3', 'Third', { sortOrder: 2 });

    let state = planTaskForDate([t1, t2, t3], [], 't-1', today, {
      todayIso: today,
    });
    state = planTaskForDate(state.tasks, state.entries, 't-2', today, {
      todayIso: today,
    });
    state = planTaskForDate(state.tasks, state.entries, 't-3', today, {
      todayIso: today,
    });

    const before = buildDailyPlanSnapshot(
      state.tasks,
      state.entries,
      today,
      today
    );
    assert.deepStrictEqual(
      before.remainingItems.map((i) => i.task.id),
      ['t-1', 't-2', 't-3']
    );

    // Move t-3 up one slot
    const movedUp = movePlannedTaskOrder(
      state.tasks,
      state.entries,
      today,
      't-3',
      'up',
      { todayIso: today }
    );
    const afterUp = buildDailyPlanSnapshot(
      movedUp,
      state.entries,
      today,
      today
    );
    assert.deepStrictEqual(
      afterUp.remainingItems.map((i) => i.task.id),
      ['t-1', 't-3', 't-2']
    );

    // Explicit reorder sequence
    const reordered = reorderPlannedTasks(movedUp, ['t-2', 't-1', 't-3']);
    const afterReorder = buildDailyPlanSnapshot(
      reordered,
      state.entries,
      today,
      today
    );
    assert.deepStrictEqual(
      afterReorder.remainingItems.map((i) => i.task.id),
      ['t-2', 't-1', 't-3']
    );
  });

  it('3. Surfaces overdue, scheduled, and carry-forward suggestions and prevents duplicate entries when carrying forward', () => {
    const yesterday = '2026-11-21';
    const today = '2026-11-22';

    const unfinishedPrior = makeTask('t-prior', 'Unfinished from yesterday', {
      dueDate: '2026-11-20',
    });
    const overdueOnly = makeTask('t-overdue', 'Overdue tax receipt', {
      dueDate: '2026-11-19',
    });
    const scheduledToday = makeTask('t-sched', 'Submit status email', {
      scheduledDate: today,
    });
    const completedPrior = makeTask('t-done', 'Completed yesterday', {
      completed: true,
      status: 'completed',
    });

    // Seed yesterday plan entries
    let state = planTaskForDate(
      [unfinishedPrior, overdueOnly, scheduledToday, completedPrior],
      [],
      't-prior',
      yesterday,
      { todayIso: today }
    );
    state = planTaskForDate(state.tasks, state.entries, 't-done', yesterday, {
      todayIso: today,
    });

    const todaySnapshotBefore = buildDailyPlanSnapshot(
      state.tasks,
      state.entries,
      today,
      today
    );
    assert.deepStrictEqual(
      todaySnapshotBefore.carryForwardSuggestions.map((s) => s.task.id),
      ['t-prior']
    );
    assert.deepStrictEqual(
      todaySnapshotBefore.overdueSuggestions.map((s) => s.task.id),
      ['t-overdue', 't-prior']
    );
    assert.deepStrictEqual(
      todaySnapshotBefore.scheduledSuggestions.map((s) => s.task.id),
      ['t-sched']
    );

    // Carry unfinished tasks forward to today
    const carried = carryForwardUnfinishedTasks(state.tasks, state.entries, {
      toDateIso: today,
      todayIso: today,
    });
    assert.strictEqual(carried.carriedCount, 1);
    assert.deepStrictEqual(carried.carriedTaskIds, ['t-prior']);
    assert.strictEqual(
      findDailyPlanningEntry(carried.entries, 't-prior', today)?.action,
      'carried_forward'
    );
    // Completed task was NOT carried forward, and yesterday's entry remains intact
    assert.strictEqual(
      findDailyPlanningEntry(carried.entries, 't-done', today),
      undefined
    );
    assert.strictEqual(
      findDailyPlanningEntry(carried.entries, 't-prior', yesterday)?.action,
      'planned'
    );

    // Repeating carry forward creates ZERO duplicates
    const carriedAgain = carryForwardUnfinishedTasks(
      carried.tasks,
      carried.entries,
      { toDateIso: today, todayIso: today }
    );
    assert.strictEqual(carriedAgain.carriedCount, 0);
    assert.strictEqual(
      carriedAgain.entries.filter(
        (e) => e.taskId === 't-prior' && e.planDate === today
      ).length,
      1
    );
  });

  it('4. Completing & reopening a carried-forward Task updates Today without losing prior-day planning history', () => {
    const yesterday = '2026-11-21';
    const today = '2026-11-22';

    const task = makeTask('t-hist', 'Finish quarterly summary');
    let state = planTaskForDate([task], [], 't-hist', yesterday, {
      todayIso: today,
    });
    const carried = carryForwardUnfinishedTasks(state.tasks, state.entries, {
      toDateIso: today,
      todayIso: today,
    });

    // Complete task today
    const completedTasks = carried.tasks.map((t) =>
      t.id === 't-hist'
        ? { ...t, completed: true, status: 'completed' as const }
        : t
    );
    const entriesAfterComplete = syncTaskCompletionWithDailyPlanning(
      completedTasks,
      carried.entries,
      't-hist',
      true,
      { todayIso: today }
    );

    assert.strictEqual(
      findDailyPlanningEntry(entriesAfterComplete, 't-hist', today)?.action,
      'completed'
    );
    assert.strictEqual(
      findDailyPlanningEntry(entriesAfterComplete, 't-hist', yesterday)?.action,
      'planned'
    );

    // Reviewing Today shows completed item
    const todaySnapDone = buildDailyPlanSnapshot(
      completedTasks,
      entriesAfterComplete,
      today,
      today
    );
    assert.strictEqual(todaySnapDone.completedCount, 1);
    assert.strictEqual(todaySnapDone.remainingCount, 0);
    assert.strictEqual(todaySnapDone.progressPercentage, 100);

    // Reviewing Yesterday preserves planned action + marks completedLater: true
    const yesterdaySnap = buildDailyPlanSnapshot(
      completedTasks,
      entriesAfterComplete,
      yesterday,
      today
    );
    assert.strictEqual(yesterdaySnap.items.length, 1);
    assert.strictEqual(yesterdaySnap.items[0].isCompletedForDay, false);
    assert.strictEqual(yesterdaySnap.items[0].completedLater, true);
    assert.ok(yesterdaySnap.historyDates.includes(yesterday));
    assert.ok(yesterdaySnap.historyDates.includes(today));

    // Reopening restores 'carried_forward' on Today because prior day history exists
    const reopenedTasks = completedTasks.map((t) =>
      t.id === 't-hist'
        ? { ...t, completed: false, status: 'not_started' as const }
        : t
    );
    const entriesAfterReopen = syncTaskCompletionWithDailyPlanning(
      reopenedTasks,
      entriesAfterComplete,
      't-hist',
      false,
      { todayIso: today }
    );
    assert.strictEqual(
      findDailyPlanningEntry(entriesAfterReopen, 't-hist', today)?.action,
      'carried_forward'
    );
  });

  it('5. Persists daily planning entries offline via dailyPlanningService & SharedStateBridge canonical snapshot', () => {
    withMockBrowserStorage(() => {
      const today = '2026-11-22';
      const yesterday = '2026-11-21';
      const task = makeTask('t-offline', 'Backup check');

      let state = planTaskForDate([task], [], 't-offline', yesterday, {
        todayIso: today,
      });
      state = carryForwardUnfinishedTasks(state.tasks, state.entries, {
        toDateIso: today,
        todayIso: today,
      });

      localStorage.setItem('daywell_tasks', JSON.stringify(state.tasks));
      dailyPlanningService.saveDailyPlanningEntries(state.entries);

      const loadedEntries = dailyPlanningService.loadDailyPlanningEntries();
      assert.strictEqual(loadedEntries.length, 2);

      // Export & import canonical bridge preserves dailyPlanningEntries & history
      const exported = SharedStateBridge.exportToAndroidJson();
      localStorage.clear();
      const imported = SharedStateBridge.importFromAndroidJson(exported);
      assert.strictEqual(imported.success, true);

      const restoredEntries = dailyPlanningService.loadDailyPlanningEntries();
      assert.strictEqual(restoredEntries.length, 2);
      assert.strictEqual(
        findDailyPlanningEntry(restoredEntries, 't-offline', yesterday)?.action,
        'planned'
      );
      assert.strictEqual(
        findDailyPlanningEntry(restoredEntries, 't-offline', today)?.action,
        'carried_forward'
      );
    });
  });

  it('6. Static Web module & boundary guardrails verify My Day UI controls, pure domain separation, and zero hex literals', () => {
    const repoRoot = path.resolve(process.cwd());
    const moduleSrc = fs.readFileSync(
      path.join(repoRoot, 'src/components/DaywellTasksModule.tsx'),
      'utf8'
    );
    const myDayViewSrc = fs.readFileSync(
      path.join(repoRoot, 'src/components/tasks/MyDayPlanningView.tsx'),
      'utf8'
    );
    const domainSrc = fs.readFileSync(
      path.join(repoRoot, 'src/domain/dailyPlanningOperations.ts'),
      'utf8'
    );

    assert.ok(moduleSrc.includes('MyDayPlanningView'));
    assert.ok(moduleSrc.includes('syncTaskCompletionWithDailyPlanning'));
    assert.ok(moduleSrc.includes('carryForwardUnfinishedTasks'));
    assert.ok(moduleSrc.includes('commitTasksAndDailyPlanning'));

    assert.ok(myDayViewSrc.includes('Daily Planning History'));
    assert.ok(myDayViewSrc.includes('Remaining for This Day'));
    assert.ok(myDayViewSrc.includes('Completed for This Day'));
    assert.ok(myDayViewSrc.includes('Carry Forward from Previous Days'));

    // Domain engine stays free of React/DOM imports and storage calls
    assert.strictEqual(/from ['"]react['"]/.test(domainSrc), false);
    assert.strictEqual(domainSrc.includes('localStorage'), false);

    // Zero raw hex literals in MyDayPlanningView.tsx
    assert.strictEqual(/#[0-9a-fA-F]{3,8}\b/.test(myDayViewSrc), false);
  });
});
