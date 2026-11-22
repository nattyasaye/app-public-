import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { CalendarDate } from './date';
import { planTaskForDate } from './dailyPlanningOperations';
import {
  createTaskRecord,
  DaywellTaskRecord,
  updateTaskRecord,
  validateTaskRecurrenceConfig,
} from './taskOperations';
import {
  completeTaskWithRecurrence,
  computeNextOccurrenceDates,
  computeNextRecurrenceDate,
  formatRecurrenceSummary,
  rescheduleRecurrenceOccurrence,
  resolveEffectiveRecurrenceConfig,
  skipRecurrenceOccurrence,
  stopTaskRecurrence,
} from './taskRecurrence';
import { projectsService } from '../services/projectsService';
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
      dueDate: overrides.dueDate,
      scheduledDate: overrides.scheduledDate,
      recurrenceRule: overrides.recurrenceRule,
      recurrenceConfig: overrides.recurrenceConfig,
      projectId: overrides.projectId,
      milestoneId: overrides.milestoneId,
      subtasks: overrides.subtasks,
      isMyDay: overrides.isMyDay,
      myDayDate: overrides.myDayDate,
      isArchived: overrides.isArchived,
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

describe('Stage 3 — Task Recurrence System (Web Domain, Services, Bridge & UI)', () => {
  it('1. Computes Daily, Weekly (selected ISO weekdays), Every-N intervals, Monthly clamping, Yearly leap clamping, and Start/End date bounds', () => {
    // Daily interval 1 & interval 3
    assert.strictEqual(
      computeNextRecurrenceDate(CalendarDate.parse('2026-11-22'), {
        frequency: 'daily',
        interval: 1,
      })?.toIsoString(),
      '2026-11-23'
    );
    assert.strictEqual(
      computeNextRecurrenceDate(CalendarDate.parse('2026-11-22'), {
        frequency: 'daily',
        interval: 3,
      })?.toIsoString(),
      '2026-11-25'
    );

    // Weekly with selected ISO weekdays Mon(1), Wed(3), Fri(5) every 2 weeks:
    // Mon 2026-11-23 -> Wed 2026-11-25 (same cycle)
    assert.strictEqual(
      computeNextRecurrenceDate(CalendarDate.parse('2026-11-23'), {
        frequency: 'weekly',
        interval: 2,
        weekdays: [1, 3, 5],
      })?.toIsoString(),
      '2026-11-25'
    );
    // Fri 2026-11-27 -> wraps by 2 weeks to Mon 2026-12-07
    assert.strictEqual(
      computeNextRecurrenceDate(CalendarDate.parse('2026-11-27'), {
        frequency: 'weekly',
        interval: 2,
        weekdays: [1, 3, 5],
      })?.toIsoString(),
      '2026-12-07'
    );

    // Monthly clamping Jan 31 -> Feb 28 (non-leap 2026) and Feb 29 (leap 2024)
    assert.strictEqual(
      computeNextRecurrenceDate(CalendarDate.parse('2026-01-31'), {
        frequency: 'monthly',
        interval: 1,
      })?.toIsoString(),
      '2026-02-28'
    );
    assert.strictEqual(
      computeNextRecurrenceDate(CalendarDate.parse('2024-01-31'), {
        frequency: 'monthly',
        interval: 1,
      })?.toIsoString(),
      '2024-02-29'
    );

    // Yearly leap-day clamping 2024-02-29 -> 2025-02-28
    assert.strictEqual(
      computeNextRecurrenceDate(CalendarDate.parse('2024-02-29'), {
        frequency: 'yearly',
        interval: 1,
      })?.toIsoString(),
      '2025-02-28'
    );

    // Start date floor & end date cap
    assert.strictEqual(
      computeNextRecurrenceDate(CalendarDate.parse('2026-11-20'), {
        frequency: 'daily',
        interval: 1,
        startDate: '2026-11-28',
      })?.toIsoString(),
      '2026-11-28'
    );
    assert.strictEqual(
      computeNextRecurrenceDate(CalendarDate.parse('2026-11-28'), {
        frequency: 'daily',
        interval: 2,
        endDate: '2026-11-29',
      }),
      null
    );

    // Config validation rejects endDate before startDate and negative interval
    const invalid = validateTaskRecurrenceConfig({
      frequency: 'weekly',
      interval: 0,
      startDate: '2026-12-10',
      endDate: '2026-12-01',
    });
    assert.strictEqual(invalid.isValid, false);
    assert.ok(invalid.errors.recurrenceInterval);
    assert.ok(invalid.errors.recurrenceEndDate);

    assert.strictEqual(
      formatRecurrenceSummary({
        frequency: 'weekly',
        interval: 2,
        weekdays: [5, 1],
      }),
      'Every 2 weeks (Mon, Fri)'
    );
  });

  it('2. Supports repeatFrom due_date vs completion_date (Ethiopia UTC+3) and preserves scheduled-to-due lead time', () => {
    const taskDueMode = makeTask('t-due-mode', 'Weekly finance close', {
      scheduledDate: '2026-11-18',
      dueDate: '2026-11-20',
      recurrenceConfig: {
        frequency: 'weekly',
        interval: 1,
        repeatFrom: 'due_date',
      },
    });
    const nextFromDue = computeNextOccurrenceDates(
      taskDueMode,
      taskDueMode.recurrenceConfig!,
      {
        forCompletion: true,
        // 2026-11-22T22:00:00Z = 2026-11-23T01:00+03:00 in Addis Ababa
        nowUtc: new Date('2026-11-22T22:00:00.000Z'),
      }
    );
    assert.deepStrictEqual(nextFromDue, {
      dueDate: '2026-11-27',
      scheduledDate: '2026-11-25',
      primaryDate: '2026-11-27',
    });

    const taskCompletionMode = makeTask('t-comp-mode', 'Water plants', {
      scheduledDate: '2026-11-19',
      dueDate: '2026-11-20',
      recurrenceConfig: {
        frequency: 'daily',
        interval: 3,
        repeatFrom: 'completion_date',
      },
    });
    const nextFromCompletion = computeNextOccurrenceDates(
      taskCompletionMode,
      taskCompletionMode.recurrenceConfig!,
      {
        forCompletion: true,
        // 2026-11-22T22:00:00Z -> Ethiopia civil date 2026-11-23
        nowUtc: new Date('2026-11-22T22:00:00.000Z'),
      }
    );
    assert.deepStrictEqual(nextFromCompletion, {
      dueDate: '2026-11-26',
      scheduledDate: '2026-11-25',
      primaryDate: '2026-11-26',
    });
  });

  it('3. Completing generates next occurrence, resets subtasks, clears My Day on spawned task, preserves completed history, and prevents duplicates', () => {
    const task = makeTask('rec-1', 'Submit weekly invoice', {
      dueDate: '2026-11-22',
      scheduledDate: '2026-11-21',
      isMyDay: true,
      myDayDate: '2026-11-22',
      projectId: 'proj-1',
      milestoneId: 'ms-1',
      subtasks: [
        { id: 'rec-1-sub-1', title: 'Collect hours', completed: true },
        { id: 'rec-1-sub-2', title: 'Send PDF', completed: true },
      ],
      recurrenceConfig: {
        frequency: 'weekly',
        interval: 1,
        repeatFrom: 'due_date',
      },
    });

    const completionTime = new Date('2026-11-22T10:00:00.000Z');
    const firstComplete = completeTaskWithRecurrence([task], 'rec-1', {
      nowUtc: completionTime,
      nextTaskId: 'rec-2',
    });
    assert.strictEqual(firstComplete.tasks.length, 2);
    assert.strictEqual(firstComplete.updatedTask?.completed, true);
    assert.strictEqual(firstComplete.updatedTask?.status, 'completed');
    assert.strictEqual(
      firstComplete.updatedTask?.subtasks.every((s) => s.completed),
      true
    );

    const next = firstComplete.generatedNextTask!;
    assert.ok(next);
    assert.strictEqual(next.id, 'rec-2');
    assert.strictEqual(next.completed, false);
    assert.strictEqual(next.status, 'not_started');
    assert.strictEqual(next.dueDate, '2026-11-29');
    assert.strictEqual(next.scheduledDate, '2026-11-28');
    assert.strictEqual(next.isMyDay, false);
    assert.strictEqual(next.myDayDate, undefined);
    assert.strictEqual(next.projectId, 'proj-1');
    assert.strictEqual(next.milestoneId, 'ms-1');
    assert.deepStrictEqual(
      next.subtasks.map((s) => ({ title: s.title, completed: s.completed })),
      [
        { title: 'Collect hours', completed: false },
        { title: 'Send PDF', completed: false },
      ]
    );

    // Reopen rec-1 and complete again -> duplicate prevention must NOT spawn a 3rd task
    const reopened = completeTaskWithRecurrence(firstComplete.tasks, 'rec-1', {
      nowUtc: new Date('2026-11-22T10:05:00.000Z'),
    });
    assert.strictEqual(reopened.updatedTask?.completed, false);
    assert.strictEqual(reopened.tasks.length, 2);

    const secondComplete = completeTaskWithRecurrence(reopened.tasks, 'rec-1', {
      nowUtc: new Date('2026-11-22T10:06:00.000Z'),
    });
    assert.strictEqual(secondComplete.generatedNextTask, undefined);
    assert.strictEqual(secondComplete.duplicatePrevented, true);
    assert.strictEqual(secondComplete.tasks.length, 2);

    // Series end date stops spawning cleanly while keeping completed task
    const endingTask = makeTask('rec-end', 'Final sprint check', {
      dueDate: '2026-11-29',
      recurrenceConfig: {
        frequency: 'weekly',
        interval: 1,
        endDate: '2026-12-01',
        repeatFrom: 'due_date',
      },
    });
    const endedRes = completeTaskWithRecurrence([endingTask], 'rec-end', {
      nowUtc: completionTime,
    });
    assert.strictEqual(endedRes.seriesEnded, true);
    assert.strictEqual(endedRes.generatedNextTask, undefined);
    assert.strictEqual(endedRes.tasks.length, 1);
    assert.strictEqual(endedRes.updatedTask?.completed, true);

    // Archived recurring task does not spawn new active occurrences
    const archivedTask = makeTask('rec-arch', 'Old recurring item', {
      dueDate: '2026-11-22',
      isArchived: true,
      recurrenceConfig: {
        frequency: 'daily',
        interval: 1,
      },
    });
    const archRes = completeTaskWithRecurrence([archivedTask], 'rec-arch', {
      nowUtc: completionTime,
    });
    assert.strictEqual(archRes.generatedNextTask, undefined);
    assert.strictEqual(archRes.tasks.length, 1);
  });

  it('4. Supports skipping, rescheduling, editing, and stopping recurrence without losing series or completion history', () => {
    const task = makeTask('rec-ops', 'Team standup notes', {
      scheduledDate: '2026-11-22',
      dueDate: '2026-11-23',
      isMyDay: true,
      myDayDate: '2026-11-23',
      recurrenceConfig: {
        frequency: 'daily',
        interval: 2,
        repeatFrom: 'due_date',
      },
    });

    // Skip occurrence advances due/scheduled dates and detaches old My Day date
    const skipped = skipRecurrenceOccurrence([task], 'rec-ops', {
      nowUtc: new Date('2026-11-22T09:00:00.000Z'),
    });
    assert.strictEqual(skipped.ok, true);
    assert.strictEqual(skipped.updatedTask?.dueDate, '2026-11-25');
    assert.strictEqual(skipped.updatedTask?.scheduledDate, '2026-11-24');
    assert.strictEqual(skipped.updatedTask?.isMyDay, false);
    assert.strictEqual(
      resolveEffectiveRecurrenceConfig(skipped.updatedTask!)?.interval,
      2
    );

    // Reschedule preserves lead time and recurrence config
    const rescheduled = rescheduleRecurrenceOccurrence(
      skipped.tasks,
      'rec-ops',
      '2026-11-30'
    );
    assert.strictEqual(rescheduled.ok, true);
    assert.strictEqual(rescheduled.updatedTask?.dueDate, '2026-11-30');
    assert.strictEqual(rescheduled.updatedTask?.scheduledDate, '2026-11-29');
    assert.strictEqual(
      resolveEffectiveRecurrenceConfig(rescheduled.updatedTask!)?.frequency,
      'daily'
    );

    // Edit recurrence rule to Monthly every 1 month
    const edited = updateTaskRecord(rescheduled.updatedTask!, {
      recurrenceConfig: {
        frequency: 'monthly',
        interval: 1,
        repeatFrom: 'completion_date',
      },
    });
    assert.strictEqual(edited.ok, true);
    if (edited.ok) {
      assert.strictEqual(edited.task.recurrenceRule, 'monthly');
      assert.strictEqual(edited.task.recurrenceConfig?.repeatFrom, 'completion_date');
    }

    // Stop recurrence removes rule while preserving dates & task record
    const stopped = stopTaskRecurrence(
      edited.ok ? [edited.task] : rescheduled.tasks,
      'rec-ops'
    );
    assert.strictEqual(stopped.ok, true);
    assert.strictEqual(stopped.updatedTask?.isRecurring, false);
    assert.strictEqual(stopped.updatedTask?.recurrenceRule, undefined);
    assert.strictEqual(stopped.updatedTask?.recurrenceConfig, undefined);
    assert.strictEqual(stopped.updatedTask?.dueDate, '2026-11-30');
  });

  it('5. Integrates recurring Tasks with Projects, Sections, My Day, and SharedStateBridge backup/restore roundtrip', () => {
    withMockBrowserStorage(() => {
      const project = projectsService.createProjectWithBlocks({
        title: 'Operations Retainer',
        status: 'active',
        startDate: '2026-11-01',
        blocks: [],
      });
      const section = projectsService.createProjectSection(project.id, 'Weekly Cadence');
      const task = projectsService.createTaskInProject({
        projectId: project.id,
        sectionId: section.id,
        title: 'Send client report',
        dueDate: '2026-11-22',
        recurrenceConfig: {
          frequency: 'weekly',
          interval: 1,
          weekdays: [7],
          repeatFrom: 'due_date',
        },
      });

      // Add to My Day for 2026-11-22
      const loadedTasks = JSON.parse(
        localStorage.getItem('daywell_tasks') ?? '[]'
      ) as DaywellTaskRecord[];
      const planned = planTaskForDate(loadedTasks, [], task.id, '2026-11-22', {
        todayIso: '2026-11-22',
      });
      localStorage.setItem('daywell_tasks', JSON.stringify(planned.tasks));
      localStorage.setItem(
        'daywell_daily_planning_entries',
        JSON.stringify(planned.entries)
      );

      // Completing task inside project spawns next task AND copies section link
      const completionRes = projectsService.toggleTaskCompletionInProject(task.id);
      assert.strictEqual(completionRes.updated?.completed, true);
      assert.ok(completionRes.generatedNextTask);
      assert.strictEqual(
        completionRes.generatedNextTask?.dueDate,
        '2026-11-29'
      );

      const sectionsVm = projectsService.getProjectSectionsViewModel(project.id);
      const weeklySection = sectionsVm.sections.find(
        (s) => s.record.id === section.id
      );
      assert.ok(weeklySection);
      const linkedTaskIds = weeklySection!.tasks.map((t) => t.id);
      assert.ok(linkedTaskIds.includes(task.id));
      assert.ok(linkedTaskIds.includes(completionRes.generatedNextTask!.id));

      // Export & restore canonical JSON roundtrips recurrenceConfig & history losslessly
      const exportedJson = SharedStateBridge.exportToAndroidJson();
      localStorage.clear();
      const restored = SharedStateBridge.importFromAndroidJson(exportedJson);
      assert.strictEqual(restored.success, true);

      const tasksAfterRestore = JSON.parse(
        localStorage.getItem('daywell_tasks') ?? '[]'
      ) as DaywellTaskRecord[];
      const restoredNext = tasksAfterRestore.find(
        (t) => t.id === completionRes.generatedNextTask!.id
      );
      assert.ok(restoredNext);
      assert.strictEqual(restoredNext?.recurrenceConfig?.frequency, 'weekly');
      assert.deepStrictEqual(restoredNext?.recurrenceConfig?.weekdays, [7]);
    });
  });

  it('6. Static Web domain/UI boundaries keep taskRecurrence pure and TaskRecurrenceFields free of hardcoded hexes', () => {
    const repoRoot = path.resolve(process.cwd());
    const domainSrc = fs.readFileSync(
      path.join(repoRoot, 'src/domain/taskRecurrence.ts'),
      'utf8'
    );
    const uiSrc = fs.readFileSync(
      path.join(repoRoot, 'src/components/tasks/TaskRecurrenceFields.tsx'),
      'utf8'
    );
    const tasksModuleSrc = fs.readFileSync(
      path.join(repoRoot, 'src/components/DaywellTasksModule.tsx'),
      'utf8'
    );

    assert.strictEqual(/from ['"]react['"]/.test(domainSrc), false);
    assert.strictEqual(domainSrc.includes('localStorage'), false);
    assert.strictEqual(/#[0-9a-fA-F]{3,8}\b/.test(uiSrc), false);
    assert.ok(tasksModuleSrc.includes('TaskRecurrenceEditorSection'));
    assert.ok(tasksModuleSrc.includes('TaskRecurrenceDetailsPanel'));
  });
});
