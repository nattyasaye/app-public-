import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createTaskRecord, DaywellTaskRecord } from './taskOperations';
import { completeTaskWithRecurrence } from './taskRecurrence';
import {
  getTaskPrimaryCalendarDate,
  projectTasksForDate,
  projectTasksForDateRange,
} from './taskCalendar';

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
      scheduledTime: overrides.scheduledTime,
      recurrenceRule: overrides.recurrenceRule,
      recurrenceConfig: overrides.recurrenceConfig,
      projectId: overrides.projectId,
      projectName: overrides.projectName,
      milestoneId: overrides.milestoneId,
      subtasks: overrides.subtasks,
      isMyDay: overrides.isMyDay,
      myDayDate: overrides.myDayDate,
    },
    new Date('2026-11-20T09:00:00.000Z')
  );
  if (!created.ok) {
    throw new Error(
      `Failed to build fixture task ${id}: ${JSON.stringify(created.errors)}`
    );
  }
  return { ...created.task, ...overrides };
}

describe('Stage 4 — Task and Calendar Integration (Web Domain & Parity)', () => {
  it('1. Resolves primary Calendar navigation date cleanly (scheduledDate over dueDate)', () => {
    assert.strictEqual(
      getTaskPrimaryCalendarDate({
        scheduledDate: '2026-11-23',
        dueDate: '2026-11-26',
      }),
      '2026-11-23'
    );
    assert.strictEqual(
      getTaskPrimaryCalendarDate({
        dueDate: '2026-11-26',
      }),
      '2026-11-26'
    );
    assert.strictEqual(getTaskPrimaryCalendarDate({}), null);
    assert.strictEqual(
      getTaskPrimaryCalendarDate({
        scheduledDate: 'invalid-date',
        dueDate: '2026-11-29',
      }),
      '2026-11-29'
    );
  });

  it('2. Separates scheduled vs. due dates, collapses same-day pairs, excludes archived/cancelled tasks, and preserves companion date metadata', () => {
    const splitTask = makeTask('t-split', 'Prepare board memo', {
      scheduledDate: '2026-11-23',
      scheduledTime: '09:30',
      estimatedDurationMinutes: 45,
      dueDate: '2026-11-25',
      priority: 'high',
    });
    const combinedTask = makeTask('t-same', 'Pay electricity bill', {
      scheduledDate: '2026-11-24',
      scheduledTime: '14:00',
      dueDate: '2026-11-24',
      priority: 'urgent',
    });
    const archivedTask = makeTask('t-arch', 'Archived reminder', {
      dueDate: '2026-11-24',
      isArchived: true,
    });
    const cancelledTask = makeTask('t-canc', 'Cancelled meeting prep', {
      scheduledDate: '2026-11-24',
      status: 'cancelled',
    });

    const occurrences = projectTasksForDateRange(
      [splitTask, combinedTask, archivedTask, cancelledTask],
      '2026-11-22',
      '2026-11-26'
    );

    assert.strictEqual(occurrences.length, 3);

    const onNov23 = occurrences.filter((o) => o.occurrenceDate === '2026-11-23');
    assert.strictEqual(onNov23.length, 1);
    assert.strictEqual(onNov23[0].kind, 'scheduled');
    assert.strictEqual(onNov23[0].scheduledTime, '09:30');
    assert.strictEqual(onNov23[0].estimatedDurationMinutes, 45);
    assert.strictEqual(onNov23[0].companionDueDate, '2026-11-25');
    assert.strictEqual(onNov23[0].isProjectedOccurrence, false);

    const onNov24 = occurrences.filter((o) => o.occurrenceDate === '2026-11-24');
    assert.strictEqual(onNov24.length, 1);
    assert.strictEqual(onNov24[0].sourceTaskId, 't-same');
    assert.strictEqual(onNov24[0].kind, 'due_and_scheduled');
    assert.strictEqual(onNov24[0].scheduledTime, '14:00');

    const onNov25 = occurrences.filter((o) => o.occurrenceDate === '2026-11-25');
    assert.strictEqual(onNov25.length, 1);
    assert.strictEqual(onNov25[0].kind, 'due');
    assert.strictEqual(onNov25[0].companionScheduledDate, '2026-11-23');
    assert.strictEqual(onNov25[0].scheduledTime, undefined);
  });

  it('3. Projects future recurring task occurrences accurately without creating duplicate calendar entries alongside stored history or spawned tasks', () => {
    const recurring = makeTask('rec-cal-1', 'Weekly team sync notes', {
      dueDate: '2026-11-22',
      scheduledDate: '2026-11-22',
      scheduledTime: '08:30',
      projectId: 'proj-ops',
      recurrenceConfig: {
        frequency: 'weekly',
        interval: 1,
        weekdays: [7],
        endDate: '2026-12-10',
        repeatFrom: 'due_date',
      },
    });

    // Before completion: Nov 22 stored, Nov 29 & Dec 06 projected, Dec 13 omitted (past endDate)
    const before = projectTasksForDateRange(
      [recurring],
      '2026-11-20',
      '2026-12-20'
    );
    assert.deepStrictEqual(
      before.map((o) => ({
        date: o.occurrenceDate,
        kind: o.kind,
        projected: o.isProjectedOccurrence,
      })),
      [
        {
          date: '2026-11-22',
          kind: 'due_and_scheduled',
          projected: false,
        },
        {
          date: '2026-11-29',
          kind: 'recurring_preview',
          projected: true,
        },
        {
          date: '2026-12-06',
          kind: 'recurring_preview',
          projected: true,
        },
      ]
    );

    // Complete Nov 22 -> produces completed historical row + spawned Nov 29 active task
    const result = completeTaskWithRecurrence([recurring], 'rec-cal-1', {
      nowUtc: new Date('2026-11-22T09:00:00.000Z'),
    });
    assert.ok(result.generatedNextTask);
    assert.strictEqual(result.generatedNextTask?.dueDate, '2026-11-29');

    const after = projectTasksForDateRange(
      result.tasks,
      '2026-11-20',
      '2026-12-20'
    );
    // Nov 22 completed stored once, Nov 29 active stored once (NOT duplicated with preview), Dec 06 projected once
    assert.deepStrictEqual(
      after.map((o) => ({
        date: o.occurrenceDate,
        kind: o.kind,
        completed: o.completed,
        projected: o.isProjectedOccurrence,
      })),
      [
        {
          date: '2026-11-22',
          kind: 'due_and_scheduled',
          completed: true,
          projected: false,
        },
        {
          date: '2026-11-29',
          kind: 'due_and_scheduled',
          completed: false,
          projected: false,
        },
        {
          date: '2026-12-06',
          kind: 'recurring_preview',
          completed: false,
          projected: true,
        },
      ]
    );
  });

  it('4. Marks completion-based recurring previews clearly and returns empty array for invalid ranges', () => {
    const completionTask = makeTask('rec-comp-cal', 'Replace water filter', {
      dueDate: '2026-11-22',
      recurrenceConfig: {
        frequency: 'daily',
        interval: 5,
        repeatFrom: 'completion_date',
      },
    });

    const onNov27 = projectTasksForDate([completionTask], '2026-11-27');
    assert.strictEqual(onNov27.length, 1);
    assert.strictEqual(onNov27[0].kind, 'recurring_preview');
    assert.strictEqual(onNov27[0].isCompletionBasedRecurrence, true);

    assert.deepStrictEqual(
      projectTasksForDateRange([completionTask], '2026-12-10', '2026-12-01'),
      []
    );
    assert.deepStrictEqual(
      projectTasksForDateRange([completionTask], 'invalid', '2026-12-01'),
      []
    );
  });

  it('5. Enforces pure domain isolation and cross-platform Calendar <-> Tasks UI wiring on Web and Flutter', () => {
    const repoRoot = process.cwd();
    const webDomain = fs.readFileSync(
      path.join(repoRoot, 'src/domain/taskCalendar.ts'),
      'utf8'
    );
    const webCalendar = fs.readFileSync(
      path.join(repoRoot, 'src/components/DaywellCalendarModule.tsx'),
      'utf8'
    );
    const webTasks = fs.readFileSync(
      path.join(repoRoot, 'src/components/DaywellTasksModule.tsx'),
      'utf8'
    );
    const webApp = fs.readFileSync(path.join(repoRoot, 'src/App.tsx'), 'utf8');

    assert.strictEqual(/from ['"]react['"]/.test(webDomain), false);
    assert.strictEqual(webDomain.includes('localStorage'), false);
    assert.ok(webCalendar.includes('projectTasksForDateRange'));
    assert.ok(webCalendar.includes('onNavigateToTask'));
    assert.ok(webCalendar.includes('requestedFocusDate'));
    assert.ok(webTasks.includes('getTaskPrimaryCalendarDate'));
    assert.ok(webTasks.includes('requestedTaskFocus'));
    assert.ok(webTasks.includes('onNavigateToCalendar'));
    assert.ok(webTasks.includes('View in Calendar'));
    assert.ok(webApp.includes('requestedTaskFocus'));
    assert.ok(webApp.includes('requestedCalendarFocus'));

    const flutterDomain = fs.readFileSync(
      path.join(
        repoRoot,
        'flutter_app/lib/domain/tasks/task_calendar_engine.dart'
      ),
      'utf8'
    );
    const flutterCalendar = fs.readFileSync(
      path.join(repoRoot, 'flutter_app/lib/ui/screens/calendar_view.dart'),
      'utf8'
    );
    const flutterTasks = fs.readFileSync(
      path.join(repoRoot, 'flutter_app/lib/ui/screens/tasks_view.dart'),
      'utf8'
    );
    const flutterMain = fs.readFileSync(
      path.join(repoRoot, 'flutter_app/lib/main.dart'),
      'utf8'
    );

    assert.strictEqual(flutterDomain.includes('package:flutter'), false);
    assert.strictEqual(flutterDomain.includes('package:drift'), false);
    assert.strictEqual(/\bColors\./.test(flutterCalendar), false);
    assert.strictEqual(/Color\s*\(\s*0x/i.test(flutterCalendar), false);
    assert.ok(flutterCalendar.includes('TaskCalendarEngine'));
    assert.ok(flutterCalendar.includes('toggleTaskWithRecurrence'));
    assert.ok(flutterCalendar.includes('onOpenTask'));
    assert.ok(flutterTasks.includes('TaskCalendarEngine'));
    assert.ok(flutterTasks.includes('requestedTaskFocus'));
    assert.ok(flutterTasks.includes('onOpenCalendarDate'));
    assert.ok(flutterTasks.includes('View in Calendar'));
    assert.ok(flutterMain.includes('CalendarView('));
    assert.ok(flutterMain.includes('onOpenCalendarDate:'));
    assert.ok(flutterMain.includes('onOpenTask:'));
  });
});
