import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { CalendarDate } from './date';
import {
  CANONICAL_TASK_PRIORITIES,
  CANONICAL_TASK_STATUSES,
  computeTaskTabCounts,
  createTaskRecord,
  DaywellTaskRecord,
  deleteTaskFromList,
  filterTasksForView,
  resolveEffectiveTaskStatus,
  setTaskArchivedRecord,
  toggleTaskCompletionRecord,
  updateTaskRecord,
} from './taskOperations';
import { SharedStateBridge } from '../services/sharedStateBridge';

describe('Stage 1.1 — Core Task Management (Web Domain & Workflows)', () => {
  const fixedNow = new Date('2026-11-21T12:00:00.000Z');
  const todayIso = CalendarDate.today().toIsoString();
  const tomorrowIso = CalendarDate.today().addDays(1).toIsoString();
  const yesterdayIso = CalendarDate.today().addDays(-1).toIsoString();

  it('1. Create Task: validates required title/dates and creates canonical task record with scheduled/due dates, priority, and status', () => {
    const emptyTitle = createTaskRecord({ title: '   ' }, fixedNow);
    assert.strictEqual(emptyTitle.ok, false);
    if (!emptyTitle.ok) {
      assert.strictEqual(emptyTitle.errors.title, 'Task title is required');
    }

    const badDate = createTaskRecord(
      { title: 'Valid title', scheduledDate: '2026-99-99' },
      fixedNow
    );
    assert.strictEqual(badDate.ok, false);
    if (!badDate.ok) {
      assert.ok(badDate.errors.scheduledDate);
    }

    const created = createTaskRecord(
      {
        id: 'task-1',
        title: '  Prepare Q4 filing  ',
        description: '  Gather receipts and statements  ',
        priority: 'urgent',
        status: 'in_progress',
        scheduledDate: todayIso,
        dueDate: tomorrowIso,
        scheduledTime: '09:30',
        projectName: 'Finance',
      },
      fixedNow
    );

    assert.strictEqual(created.ok, true);
    if (created.ok) {
      assert.strictEqual(created.task.title, 'Prepare Q4 filing');
      assert.strictEqual(created.task.description, 'Gather receipts and statements');
      assert.strictEqual(created.task.priority, 'urgent');
      assert.strictEqual(created.task.status, 'in_progress');
      assert.strictEqual(created.task.completed, false);
      assert.strictEqual(created.task.completedAt, undefined);
      assert.strictEqual(created.task.scheduledDate, todayIso);
      assert.strictEqual(created.task.dueDate, tomorrowIso);
      assert.strictEqual(created.task.scheduledTime, '09:30');
      assert.strictEqual(created.task.isArchived, false);
      assert.strictEqual(created.task.createdAt, fixedNow.toISOString());
    }

    const createdDone = createTaskRecord(
      {
        id: 'task-done',
        title: 'Already done task',
        status: 'completed',
      },
      fixedNow
    );
    assert.strictEqual(createdDone.ok, true);
    if (createdDone.ok) {
      assert.strictEqual(createdDone.task.completed, true);
      assert.strictEqual(createdDone.task.completedAt, fixedNow.toISOString());
    }
  });

  it('2 & 3 & 4 & 5. Edit Task + Priority/Status + Scheduled/Due Dates: updates fields, clears optional fields, syncs completedAt, and preserves untouched metadata', () => {
    const existing: DaywellTaskRecord = {
      id: 'task-edit-1',
      title: 'Original title',
      description: 'Original notes',
      priority: 'low',
      status: 'not_started',
      completed: false,
      dueDate: tomorrowIso,
      scheduledDate: todayIso,
      scheduledTime: '14:00',
      hasReminder: true,
      isRecurring: false,
      subtasks: [{ id: 'sub-1', title: 'Keep subtask', completed: true }],
      labels: ['tax', 'personal'],
      isPinned: true,
      isMyDay: true,
      myDayDate: todayIso,
      recurrenceRule: 'weekly',
      recurrenceConfig: { frequency: 'weekly', interval: 1 },
      isArchived: false,
      sortOrder: 7,
      milestoneId: 'ms-9',
      estimatedDurationMinutes: 45,
      createdAt: '2026-11-20T08:00:00.000Z',
      updatedAt: '2026-11-20T08:00:00.000Z',
    };

    const editTime = new Date('2026-11-21T15:00:00.000Z');
    const updatedRes = updateTaskRecord(
      existing,
      {
        title: 'Updated title',
        description: '',
        priority: 'high',
        status: 'completed',
        scheduledDate: '',
        dueDate: todayIso,
      },
      editTime
    );

    assert.strictEqual(updatedRes.ok, true);
    if (updatedRes.ok) {
      const t = updatedRes.task;
      assert.strictEqual(t.title, 'Updated title');
      assert.strictEqual(t.description, undefined);
      assert.strictEqual(t.priority, 'high');
      assert.strictEqual(t.status, 'completed');
      assert.strictEqual(t.completed, true);
      assert.strictEqual(t.completedAt, editTime.toISOString());
      assert.strictEqual(t.scheduledDate, undefined);
      assert.strictEqual(t.dueDate, todayIso);
      assert.strictEqual(t.scheduledTime, '14:00');
      // Preserved non-Stage-1.1 metadata
      assert.deepStrictEqual(t.subtasks, existing.subtasks);
      assert.deepStrictEqual(t.labels, existing.labels);
      assert.strictEqual(t.isPinned, true);
      assert.strictEqual(t.isMyDay, true);
      assert.strictEqual(t.myDayDate, todayIso);
      assert.deepStrictEqual(t.recurrenceConfig, existing.recurrenceConfig);
      assert.strictEqual(t.sortOrder, 7);
      assert.strictEqual(t.milestoneId, 'ms-9');
      assert.strictEqual(t.estimatedDurationMinutes, 45);
      assert.strictEqual(t.createdAt, existing.createdAt);
      assert.strictEqual(t.updatedAt, editTime.toISOString());

      // Reopen via status change clears completedAt
      const reopenedRes = updateTaskRecord(t, { status: 'in_progress' }, fixedNow);
      assert.strictEqual(reopenedRes.ok, true);
      if (reopenedRes.ok) {
        assert.strictEqual(reopenedRes.task.completed, false);
        assert.strictEqual(reopenedRes.task.status, 'in_progress');
        assert.strictEqual(reopenedRes.task.completedAt, undefined);
      }
    }

    // All canonical statuses and priorities are supported
    assert.deepStrictEqual(CANONICAL_TASK_STATUSES, [
      'inbox',
      'not_started',
      'in_progress',
      'completed',
      'cancelled',
    ]);
    assert.deepStrictEqual(CANONICAL_TASK_PRIORITIES, [
      'urgent',
      'high',
      'medium',
      'low',
    ]);
  });

  it('6. Complete and Reopen Tasks: toggles completed flag, canonical status, and completedAt cleanly', () => {
    const base = createTaskRecord(
      { id: 't-toggle', title: 'Walk 30 minutes', priority: 'medium' },
      fixedNow
    );
    assert.strictEqual(base.ok, true);
    if (!base.ok) return;

    const completeTime = new Date('2026-11-21T16:00:00.000Z');
    const completed = toggleTaskCompletionRecord(base.task, completeTime);
    assert.strictEqual(completed.completed, true);
    assert.strictEqual(completed.status, 'completed');
    assert.strictEqual(completed.completedAt, completeTime.toISOString());
    assert.strictEqual(resolveEffectiveTaskStatus(completed), 'completed');

    const reopenTime = new Date('2026-11-21T16:05:00.000Z');
    const reopened = toggleTaskCompletionRecord(completed, reopenTime);
    assert.strictEqual(reopened.completed, false);
    assert.strictEqual(reopened.status, 'not_started');
    assert.strictEqual(reopened.completedAt, undefined);
    assert.strictEqual(resolveEffectiveTaskStatus(reopened), 'not_started');
  });

  it('7. Archive and Restore Tasks: isolates archived tasks from active/completed views and surfaces them in Archived view', () => {
    const tToday: DaywellTaskRecord = {
      id: 't-today',
      title: 'Today task',
      priority: 'high',
      status: 'not_started',
      completed: false,
      scheduledDate: todayIso,
      hasReminder: false,
      subtasks: [],
      isArchived: false,
      createdAt: fixedNow.toISOString(),
    };
    const tInbox: DaywellTaskRecord = {
      id: 't-inbox',
      title: 'Inbox task',
      priority: 'medium',
      status: 'inbox',
      completed: false,
      hasReminder: false,
      subtasks: [],
      isArchived: false,
      createdAt: fixedNow.toISOString(),
    };
    const tUpcoming: DaywellTaskRecord = {
      id: 't-upcoming',
      title: 'Upcoming task',
      priority: 'low',
      status: 'in_progress',
      completed: false,
      dueDate: tomorrowIso,
      hasReminder: false,
      subtasks: [],
      isArchived: false,
      createdAt: fixedNow.toISOString(),
    };
    const tCancelled: DaywellTaskRecord = {
      id: 't-cancelled',
      title: 'Cancelled task',
      priority: 'low',
      status: 'cancelled',
      completed: false,
      dueDate: todayIso,
      hasReminder: false,
      subtasks: [],
      isArchived: false,
      createdAt: fixedNow.toISOString(),
    };
    const tOverdueScheduled: DaywellTaskRecord = {
      id: 't-overdue',
      title: 'Overdue scheduled task',
      priority: 'urgent',
      status: 'not_started',
      completed: false,
      scheduledDate: yesterdayIso,
      hasReminder: false,
      subtasks: [],
      isArchived: false,
      createdAt: fixedNow.toISOString(),
    };

    const all = [tToday, tInbox, tUpcoming, tCancelled, tOverdueScheduled];
    const archivedToday = setTaskArchivedRecord(tToday, true, fixedNow);
    const listWithArchived = [
      archivedToday,
      tInbox,
      tUpcoming,
      tCancelled,
      tOverdueScheduled,
    ];

    const counts = computeTaskTabCounts(listWithArchived, todayIso);
    assert.strictEqual(counts.todayCount, 1); // tOverdueScheduled only (tToday archived, tCancelled excluded)
    assert.strictEqual(counts.inboxCount, 1); // tInbox
    assert.strictEqual(counts.upcomingCount, 1); // tUpcoming
    assert.strictEqual(counts.allCount, 4); // all non-archived (includes tCancelled)
    assert.strictEqual(counts.completedCount, 0);
    assert.strictEqual(counts.archivedCount, 1);
    assert.strictEqual(counts.activePendingCount, 3); // excludes archived & cancelled

    assert.deepStrictEqual(
      filterTasksForView(listWithArchived, { viewFilter: 'today', todayIso }).map((t) => t.id),
      ['t-overdue']
    );
    assert.deepStrictEqual(
      filterTasksForView(listWithArchived, { viewFilter: 'archived', todayIso }).map((t) => t.id),
      ['t-today']
    );
    assert.deepStrictEqual(
      filterTasksForView(listWithArchived, { viewFilter: 'all', todayIso }).map((t) => t.id),
      ['t-overdue', 't-inbox', 't-cancelled', 't-upcoming']
    );

    const restoredToday = setTaskArchivedRecord(archivedToday, false, fixedNow);
    const listRestored = [restoredToday, tInbox, tUpcoming, tCancelled, tOverdueScheduled];
    const countsAfter = computeTaskTabCounts(listRestored, todayIso);
    assert.strictEqual(countsAfter.archivedCount, 0);
    assert.strictEqual(countsAfter.todayCount, 2);
    assert.strictEqual(countsAfter.allCount, 5);
  });

  it('8. Delete Task + DailyPlanningEntries cascade + Canonical Bridge preservation', () => {
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

    const t1 = createTaskRecord(
      {
        id: 't-del-1',
        title: 'Task to delete',
        priority: 'high',
        status: 'in_progress',
        scheduledDate: todayIso,
        dueDate: tomorrowIso,
      },
      fixedNow
    );
    const t2 = createTaskRecord(
      {
        id: 't-keep-1',
        title: 'Task to archive and keep',
        priority: 'medium',
        status: 'inbox',
      },
      fixedNow
    );
    assert.ok(t1.ok && t2.ok);

    const archivedT2 = setTaskArchivedRecord(t2.task, true, fixedNow);
    storage.set(
      'daywell_tasks',
      JSON.stringify([t1.task, archivedT2])
    );
    storage.set(
      SharedStateBridge.DAILY_PLANNING_STORAGE_KEY,
      JSON.stringify([
        {
          id: 'dp-1',
          planDate: todayIso,
          taskId: 't-del-1',
          action: 'planned',
          createdAt: fixedNow.toISOString(),
        },
        {
          id: 'dp-2',
          planDate: todayIso,
          taskId: 't-keep-1',
          action: 'planned',
          createdAt: fixedNow.toISOString(),
        },
      ])
    );

    const { remaining, deleted } = deleteTaskFromList([t1.task, archivedT2], 't-del-1');
    assert.strictEqual(deleted?.id, 't-del-1');
    assert.strictEqual(remaining.length, 1);
    storage.set('daywell_tasks', JSON.stringify(remaining));
    SharedStateBridge.removeDailyPlanningForTask('t-del-1');

    const exported = SharedStateBridge.loadCanonicalState();
    assert.strictEqual(exported.tasks.length, 1);
    assert.strictEqual(exported.tasks[0].id, 't-keep-1');
    assert.strictEqual(exported.tasks[0].isArchived, true);
    assert.strictEqual(exported.tasks[0].status, 'inbox');
    assert.strictEqual((exported.dailyPlanningEntries ?? []).length, 1);
    assert.strictEqual(exported.dailyPlanningEntries?.[0].taskId, 't-keep-1');
  });

  it('9. Web DaywellTasksModule exposes Details, Edit, Status, Scheduled Date, Archive/Restore, and Safe Delete UI without React/DOM leakage in taskOperations.ts', () => {
    const domainPath = path.join(process.cwd(), 'src', 'domain', 'taskOperations.ts');
    const domainSrc = fs.readFileSync(domainPath, 'utf8');
    assert.strictEqual(domainSrc.includes("from 'react'"), false);
    assert.strictEqual(domainSrc.includes('document.'), false);

    const modulePath = path.join(process.cwd(), 'src', 'components', 'DaywellTasksModule.tsx');
    const moduleSrc = fs.readFileSync(modulePath, 'utf8');
    assert.strictEqual(moduleSrc.includes('aria-label="Task Details"'), true);
    assert.strictEqual(moduleSrc.includes('aria-label="Scheduled Date"'), true);
    assert.strictEqual(moduleSrc.includes('aria-label="Due Date"'), true);
    assert.strictEqual(moduleSrc.includes('aria-label="Status"'), true);
    assert.strictEqual(moduleSrc.includes('DaywellConfirmationDialog'), true);
    assert.strictEqual(moduleSrc.includes('Archived ('), true);
    assert.strictEqual(moduleSrc.includes('All ('), true);
  });
});
