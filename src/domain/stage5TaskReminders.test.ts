import { afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { SharedReminder } from './sharedFoundation';
import { createTaskRecord, DaywellTaskRecord } from './taskOperations';
import {
  completeTaskWithRecurrence,
  rescheduleRecurrenceOccurrence,
  skipRecurrenceOccurrence,
} from './taskRecurrence';
import {
  buildCanonicalTaskReminderId,
  buildTaskReminderRecord,
  computeTaskReminderTriggerFromPreset,
  defaultFallbackReminderDateTime,
  ethiopiaWallDateTimeToUtcIso,
  findReminderForTask,
  formatTaskReminderSummary,
  inferTaskReminderPreset,
  isTaskReminderOverdue,
  recomputeReminderTriggerOnTaskUpdate,
  reconcileTaskRemindersWithTasks,
  resolveTaskReminderAnchor,
  TASK_REMINDER_CHANNEL_ID,
} from './taskReminders';
import { taskRemindersService, WebTaskReminderAlert } from '../services/taskRemindersService';
import { SharedStateBridge } from '../services/sharedStateBridge';

function installMockBrowserGlobals() {
  const store = new Map<string, string>();
  const events: string[] = [];

  (globalThis as unknown as { localStorage: Storage }).localStorage = {
    get length() {
      return store.size;
    },
    clear() {
      store.clear();
    },
    getItem(key: string) {
      return store.has(key) ? store.get(key)! : null;
    },
    key(index: number) {
      return Array.from(store.keys())[index] ?? null;
    },
    removeItem(key: string) {
      store.delete(key);
    },
    setItem(key: string, value: string) {
      store.set(key, String(value));
    },
  };

  (globalThis as unknown as { window: Record<string, unknown> }).window = {
    dispatchEvent(evt: { type?: string }) {
      if (evt?.type) events.push(evt.type);
      return true;
    },
  };

  return { store, events };
}

function makeTask(
  id: string,
  title: string,
  overrides: Partial<DaywellTaskRecord> = {}
): DaywellTaskRecord {
  const res = createTaskRecord(
    {
      id,
      title,
      priority: overrides.priority ?? 'medium',
      status: overrides.status ?? 'not_started',
      dueDate: overrides.dueDate,
      scheduledDate: overrides.scheduledDate,
      scheduledTime: overrides.scheduledTime,
      recurrenceRule: overrides.recurrenceRule,
      recurrenceConfig: overrides.recurrenceConfig,
    },
    new Date('2026-11-20T06:00:00.000Z')
  );
  if (!res.ok) {
    throw new Error(`Fixture task failed: ${JSON.stringify(res.errors)}`);
  }
  return { ...res.task, ...overrides };
}

describe('Stage 5 — Task Reminders & Notifications (Web Domain, Service, Sync & UI)', () => {
  beforeEach(() => {
    installMockBrowserGlobals();
    taskRemindersService.resetSchedulerStateForTesting();
  });

  afterEach(() => {
    taskRemindersService.resetSchedulerStateForTesting();
  });

  it('1. Resolves reminder anchors cleanly in Ethiopia UTC+3 (scheduled > due, explicit time > 09:00 default)', () => {
    const bothSet = makeTask('t-both', 'Prepare briefing', {
      scheduledDate: '2026-11-23',
      scheduledTime: '14:30',
      dueDate: '2026-11-25',
    });
    const anchor1 = resolveTaskReminderAnchor(bothSet);
    assert.ok(anchor1);
    assert.strictEqual(anchor1.source, 'scheduled');
    assert.strictEqual(anchor1.dateIso, '2026-11-23');
    assert.strictEqual(anchor1.time, '14:30');
    assert.strictEqual(anchor1.hasExplicitTime, true);
    // 14:30 EAT == 11:30 UTC
    assert.strictEqual(anchor1.utcIso, '2026-11-23T11:30:00.000Z');

    const dueOnly = makeTask('t-due', 'Submit tax forms', {
      dueDate: '2026-11-26',
    });
    const anchor2 = resolveTaskReminderAnchor(dueOnly);
    assert.ok(anchor2);
    assert.strictEqual(anchor2.source, 'due');
    assert.strictEqual(anchor2.dateIso, '2026-11-26');
    assert.strictEqual(anchor2.time, '09:00');
    assert.strictEqual(anchor2.hasExplicitTime, false);
    // 09:00 EAT == 06:00 UTC
    assert.strictEqual(anchor2.utcIso, '2026-11-26T06:00:00.000Z');

    const undated = makeTask('t-none', 'Quick thought');
    assert.strictEqual(resolveTaskReminderAnchor(undated), null);
    // 07:00 UTC == 10:00 EAT -> fallback rolls to tomorrow 09:00 EAT (06:00 UTC)
    const fallback = defaultFallbackReminderDateTime(
      new Date('2026-11-20T07:00:00.000Z')
    );
    assert.strictEqual(fallback.dateIso, '2026-11-21');
    assert.strictEqual(fallback.time, '09:00');
    assert.strictEqual(fallback.triggerTimeUtc, '2026-11-21T06:00:00.000Z');
  });

  it('2. Computes all 5 timing presets, infers presets back cleanly, and rejects invalid custom inputs', () => {
    const task = makeTask('t-preset', 'Team sync', {
      scheduledDate: '2026-11-24',
      scheduledTime: '10:00',
    });

    const atTime = computeTaskReminderTriggerFromPreset({ task, preset: 'at_time' });
    const m15 = computeTaskReminderTriggerFromPreset({ task, preset: '15m_before' });
    const h1 = computeTaskReminderTriggerFromPreset({ task, preset: '1h_before' });
    const d1 = computeTaskReminderTriggerFromPreset({ task, preset: '1d_before' });
    const custom = computeTaskReminderTriggerFromPreset({
      task,
      preset: 'custom',
      customDateIso: '2026-11-24',
      customTime: '08:15',
    });
    const invalidCustom = computeTaskReminderTriggerFromPreset({
      task,
      preset: 'custom',
      customDateIso: 'not-a-date',
      customTime: '25:99',
    });

    assert.strictEqual(atTime.triggerTimeUtc, '2026-11-24T07:00:00.000Z');
    assert.strictEqual(m15.triggerTimeUtc, '2026-11-24T06:45:00.000Z');
    assert.strictEqual(h1.triggerTimeUtc, '2026-11-24T06:00:00.000Z');
    assert.strictEqual(d1.triggerTimeUtc, '2026-11-23T07:00:00.000Z');
    assert.strictEqual(custom.triggerTimeUtc, '2026-11-24T05:15:00.000Z');
    assert.strictEqual(invalidCustom.ok, false);

    assert.strictEqual(inferTaskReminderPreset(task, atTime.triggerTimeUtc!), 'at_time');
    assert.strictEqual(inferTaskReminderPreset(task, m15.triggerTimeUtc!), '15m_before');
    assert.strictEqual(inferTaskReminderPreset(task, h1.triggerTimeUtc!), '1h_before');
    assert.strictEqual(inferTaskReminderPreset(task, d1.triggerTimeUtc!), '1d_before');
    assert.strictEqual(inferTaskReminderPreset(task, custom.triggerTimeUtc!), 'custom');
  });

  it('3. Reconciles reminders across completion, reopening, archiving, deletion, date shifts, and Finance non-interference', () => {
    const tOpen = makeTask('t-1', 'Pay internet bill', {
      dueDate: '2026-11-25',
      scheduledDate: '2026-11-25',
      scheduledTime: '11:00',
    });
    const tCompletedSoon = makeTask('t-2', 'Stale alert task', {
      dueDate: '2026-11-18',
      status: 'completed',
      completed: true,
    });
    const financeReminder: SharedReminder = {
      id: 'fin-rem-1',
      targetId: 'commit-rent',
      targetType: 'commitment',
      title: 'House Rent',
      channelId: 'commitment_reminders_channel',
      triggerTimeUtc: '2026-11-25T06:00:00.000Z',
      isActive: true,
      createdAt: '2026-11-20T06:00:00.000Z',
    };
    const rem1 = buildTaskReminderRecord({
      task: tOpen,
      triggerTimeUtc: ethiopiaWallDateTimeToUtcIso('2026-11-25', '10:00')!, // 1h before
    });
    const remOrphan: SharedReminder = {
      id: 'rem-task-deleted',
      targetId: 'deleted-id',
      targetType: 'task',
      title: 'Orphan',
      channelId: TASK_REMINDER_CHANNEL_ID,
      triggerTimeUtc: '2026-11-25T06:00:00.000Z',
      isActive: true,
      createdAt: '2026-11-20T06:00:00.000Z',
    };
    const rem2: SharedReminder = {
      id: buildCanonicalTaskReminderId(tCompletedSoon.id),
      targetId: tCompletedSoon.id,
      targetType: 'task',
      title: tCompletedSoon.title,
      channelId: TASK_REMINDER_CHANNEL_ID,
      triggerTimeUtc: '2026-11-18T06:00:00.000Z',
      isActive: false,
      createdAt: '2026-11-17T06:00:00.000Z',
    };

    // Shifting date/time updates preset-based trigger automatically
    const shiftedTask: DaywellTaskRecord = {
      ...tOpen,
      scheduledDate: '2026-11-27',
      scheduledTime: '15:00',
    };
    const shiftedRes = reconcileTaskRemindersWithTasks({
      tasks: [shiftedTask, tCompletedSoon],
      previousTasks: [tOpen, tCompletedSoon],
      reminders: [financeReminder, rem1, rem2, remOrphan],
      nowUtc: new Date('2026-11-20T06:00:00.000Z'),
    });
    // Finance reminder preserved untouched; orphan pruned
    assert.strictEqual(shiftedRes.reminders.length, 3);
    assert.ok(shiftedRes.reminders.some((r) => r.id === 'fin-rem-1'));
    assert.ok(!shiftedRes.reminders.some((r) => r.id === 'rem-task-deleted'));
    const updatedRem1 = findReminderForTask(shiftedRes.reminders, 't-1')!;
    // 1h before 15:00 EAT on Nov 27 => 14:00 EAT => 11:00 UTC
    assert.strictEqual(updatedRem1.triggerTimeUtc, '2026-11-27T11:00:00.000Z');
    assert.strictEqual(updatedRem1.isActive, true);
    assert.strictEqual(shiftedRes.tasks[0].hasReminder, true);

    // Completing pauses reminder; reopening future reminder re-arms it; reopening overdue reminder stays paused
    const completedTask: DaywellTaskRecord = {
      ...shiftedTask,
      status: 'completed',
      completed: true,
    };
    const afterComplete = reconcileTaskRemindersWithTasks({
      tasks: [completedTask, tCompletedSoon],
      previousTasks: [shiftedTask, tCompletedSoon],
      reminders: shiftedRes.reminders,
      nowUtc: new Date('2026-11-20T06:00:00.000Z'),
    });
    assert.strictEqual(findReminderForTask(afterComplete.reminders, 't-1')!.isActive, false);
    assert.strictEqual(afterComplete.tasks[0].hasReminder, false);

    const reopenedFuture: DaywellTaskRecord = {
      ...completedTask,
      status: 'not_started',
      completed: false,
    };
    const reopenedOverdue: DaywellTaskRecord = {
      ...tCompletedSoon,
      status: 'not_started',
      completed: false,
    };
    const afterReopen = reconcileTaskRemindersWithTasks({
      tasks: [reopenedFuture, reopenedOverdue],
      previousTasks: [completedTask, tCompletedSoon],
      reminders: afterComplete.reminders,
      nowUtc: new Date('2026-11-20T06:00:00.000Z'),
    });
    assert.strictEqual(findReminderForTask(afterReopen.reminders, 't-1')!.isActive, true);
    assert.strictEqual(findReminderForTask(afterReopen.reminders, 't-2')!.isActive, false);

    // Archiving also deactivates active reminder
    const archivedTask: DaywellTaskRecord = {
      ...reopenedFuture,
      isArchived: true,
    };
    const afterArchive = reconcileTaskRemindersWithTasks({
      tasks: [archivedTask, reopenedOverdue],
      previousTasks: [reopenedFuture, reopenedOverdue],
      reminders: afterReopen.reminders,
      nowUtc: new Date('2026-11-20T06:00:00.000Z'),
    });
    assert.strictEqual(findReminderForTask(afterArchive.reminders, 't-1')!.isActive, false);
  });

  it('4. Carries over reminders cleanly on recurring task completion & skip without duplicating occurrences', () => {
    const recurringTask = makeTask('rec-1', 'Weekly review', {
      scheduledDate: '2026-11-20',
      scheduledTime: '16:00',
      dueDate: '2026-11-20',
      hasReminder: true,
      recurrenceConfig: {
        frequency: 'weekly',
        interval: 1,
        weekdays: [5], // Friday
        repeatFrom: 'due_date',
      },
    });
    // 15m before 16:00 EAT => 15:45 EAT => 12:45 UTC
    const parentReminder = buildTaskReminderRecord({
      task: recurringTask,
      triggerTimeUtc: '2026-11-20T12:45:00.000Z',
    });

    const completion = completeTaskWithRecurrence(
      [recurringTask],
      recurringTask.id,
      { nowUtc: new Date('2026-11-20T13:00:00.000Z') }
    );
    assert.ok(completion.generatedNextTask);
    assert.strictEqual(completion.generatedNextTask.dueDate, '2026-11-27');

    const carried = reconcileTaskRemindersWithTasks({
      tasks: completion.tasks,
      previousTasks: [recurringTask],
      reminders: [parentReminder],
      generatedFromTaskId: recurringTask.id,
      generatedNextTask: completion.generatedNextTask,
      nowUtc: new Date('2026-11-20T13:00:00.000Z'),
    });

    const completedParentRem = findReminderForTask(carried.reminders, 'rec-1');
    const nextOccRem = findReminderForTask(
      carried.reminders,
      completion.generatedNextTask.id
    );
    assert.ok(completedParentRem);
    assert.strictEqual(completedParentRem.isActive, false);
    assert.ok(nextOccRem);
    assert.strictEqual(nextOccRem.isActive, true);
    assert.strictEqual(nextOccRem.triggerTimeUtc, '2026-11-27T12:45:00.000Z');
    assert.strictEqual(
      carried.tasks.filter((t) => t.id === completion.generatedNextTask!.id).length,
      1
    );

    // Rescheduling an occurrence shifts a custom trigger by the same day delta
    const rescheduled = rescheduleRecurrenceOccurrence(
      [completion.generatedNextTask],
      completion.generatedNextTask.id,
      '2026-11-30'
    );
    assert.ok(rescheduled.ok && rescheduled.updatedTask);
    const customShiftedTrigger = recomputeReminderTriggerOnTaskUpdate({
      previousTask: completion.generatedNextTask,
      nextTask: rescheduled.updatedTask,
      existingTriggerUtc: '2026-11-26T17:00:00.000Z', // 20:00 EAT day before
      shiftCustomOnDateShift: true,
    });
    assert.strictEqual(customShiftedTrigger, '2026-11-29T17:00:00.000Z');

    const skipped = skipRecurrenceOccurrence(
      [completion.generatedNextTask],
      completion.generatedNextTask.id,
      { nowUtc: new Date('2026-11-27T08:00:00.000Z') }
    );
    assert.ok(skipped.ok && skipped.updatedTask);
    assert.strictEqual(skipped.updatedTask.dueDate, '2026-12-04');
  });

  it('5. Service persists reminders, exposes honest Web preview capabilities, schedules foreground timers, and preserves Finance reminders', () => {
    const task = makeTask('svc-1', 'Call supplier', {
      scheduledDate: '2026-11-28',
      scheduledTime: '10:00',
    });
    const financeReminder: SharedReminder = {
      id: 'fin-1',
      targetId: 'bill-1',
      targetType: 'commitment',
      title: 'Electricity Bill',
      channelId: 'commitment_reminders_channel',
      triggerTimeUtc: '2026-11-28T06:00:00.000Z',
      isActive: true,
      createdAt: '2026-11-20T06:00:00.000Z',
    };
    localStorage.setItem('daywell_tasks', JSON.stringify([task]));
    taskRemindersService.saveAllReminders([financeReminder], { emitSync: false });

    const support = taskRemindersService.getWebNotificationSupportStatus();
    assert.strictEqual(support.backgroundDeliverySupported, false);
    assert.strictEqual(support.permission, 'unsupported');
    assert.ok(support.capabilityNote.includes('while this tab remains open'));

    const futureTrigger = new Date(Date.now() + 60 * 60 * 1000).toISOString();
    const setRes = taskRemindersService.setTaskReminder(task, futureTrigger, {
      nowUtc: new Date(),
    });
    assert.strictEqual(setRes.reminder.channelId, TASK_REMINDER_CHANNEL_ID);
    assert.strictEqual(taskRemindersService.getActiveScheduledTimerCount(), 1);

    const persistedTasks = JSON.parse(localStorage.getItem('daywell_tasks')!) as DaywellTaskRecord[];
    assert.strictEqual(persistedTasks[0].hasReminder, true);

    // Due within 2-minute grace window fires in-app listener once (deduped)
    const dueAlerts: WebTaskReminderAlert[] = [];
    taskRemindersService.setReminderDueListener((a) => dueAlerts.push(a));
    const justDueIso = new Date(Date.now() - 10_000).toISOString();
    taskRemindersService.setTaskReminder(task, justDueIso, {
      nowUtc: new Date(),
    });
    assert.strictEqual(dueAlerts.length, 1);
    assert.strictEqual(dueAlerts[0].taskId, 'svc-1');
    assert.strictEqual(dueAlerts[0].deliveredViaBrowserNotification, false);

    // Repeating sync does NOT double-fire the same due timestamp
    taskRemindersService.syncWebTaskNotifications({
      tasks: [{ ...task, hasReminder: true }],
      nowUtc: new Date(),
    });
    assert.strictEqual(dueAlerts.length, 1);

    // Removing task reminder keeps Finance reminder intact and cancels timers
    const afterRemove = taskRemindersService.removeTaskReminder('svc-1');
    assert.strictEqual(afterRemove.length, 1);
    assert.strictEqual(afterRemove[0].id, 'fin-1');
    assert.strictEqual(taskRemindersService.getActiveScheduledTimerCount(), 0);
  });

  it('6. SharedStateBridge export & import preserves Task Reminders, scheduledTime, and formats summaries in Ethiopia UTC+3', () => {
    const task = makeTask('exp-1', 'Renew passport', {
      scheduledDate: '2026-11-30',
      scheduledTime: '09:30',
      hasReminder: true,
    });
    localStorage.setItem('daywell_tasks', JSON.stringify([task]));
    taskRemindersService.setTaskReminder(
      task,
      ethiopiaWallDateTimeToUtcIso('2026-11-30', '08:30')!,
      { emitSync: false }
    );

    const exportedJson = SharedStateBridge.exportToAndroidJson();
    const exported = JSON.parse(exportedJson) as {
      reminders: SharedReminder[];
      tasks: DaywellTaskRecord[];
    };
    assert.strictEqual(exported.reminders.length, 1);
    assert.strictEqual(exported.reminders[0].channelId, TASK_REMINDER_CHANNEL_ID);
    assert.strictEqual(exported.reminders[0].targetId, 'exp-1');
    assert.strictEqual(exported.reminders[0].isActive, true);
    assert.strictEqual(exported.tasks[0].scheduledTime, '09:30');

    // Clear storage, import canonical payload back, verify restoration
    localStorage.clear();
    const importRes = SharedStateBridge.importFromAndroidJson(exportedJson);
    assert.strictEqual(importRes.success, true);
    const restoredReminders = taskRemindersService.loadAllReminders();
    assert.strictEqual(restoredReminders.length, 1);
    assert.strictEqual(restoredReminders[0].targetId, 'exp-1');
    assert.strictEqual(restoredReminders[0].isActive, true);

    const summary = formatTaskReminderSummary('2026-11-30T05:30:00.000Z');
    assert.ok(summary.includes('08:30 EAT'));
    assert.strictEqual(
      isTaskReminderOverdue(restoredReminders[0], new Date('2026-11-30T06:00:00.000Z')),
      true
    );
  });

  it('7. Verifies Web UI entry points (Tasks, Project Tasks, App shell) wire shared reminder editors, undo & notification limits cleanly', () => {
    const tasksModulePath = path.resolve(
      process.cwd(),
      'src/components/DaywellTasksModule.tsx'
    );
    const projectSectionsPath = path.resolve(
      process.cwd(),
      'src/components/projects/ProjectTasksSectionsCard.tsx'
    );
    const appPath = path.resolve(process.cwd(), 'src/App.tsx');

    const tasksSrc = fs.readFileSync(tasksModulePath, 'utf8');
    const projectSrc = fs.readFileSync(projectSectionsPath, 'utf8');
    const appSrc = fs.readFileSync(appPath, 'utf8');

    assert.ok(tasksSrc.includes('TaskReminderEditorSection'));
    assert.ok(tasksSrc.includes('TaskReminderDetailsPanel'));
    assert.ok(tasksSrc.includes('taskRemindersService.reconcileAndPersistForTasks'));
    assert.ok(tasksSrc.includes('taskRemindersService.restoreRemindersSnapshot'));

    assert.ok(projectSrc.includes('TaskReminderEditorSection'));
    assert.ok(projectSrc.includes('TaskReminderDetailsPanel'));
    assert.ok(projectSrc.includes('taskScheduledTime'));

    assert.ok(appSrc.includes('taskRemindersService.syncWebTaskNotifications'));
    assert.ok(appSrc.includes('setReminderDueListener'));
    assert.ok(appSrc.includes('Unsupported in Web Preview'));
    assert.ok(appSrc.includes('isNotificationStatusModalOpen'));
  });
});
