import { CalendarDate, DayTimeOfDay, EthiopiaClock } from './date';
import { SharedReminder } from './sharedFoundation';
import { DaywellTaskRecord, isTaskCompleted } from './taskOperations';

export const TASK_REMINDER_CHANNEL_ID = 'task_reminders_channel';

export const DEFAULT_TASK_REMINDER_HOUR = 9;
export const DEFAULT_TASK_REMINDER_MINUTE = 0;
export const DEFAULT_TASK_REMINDER_TIME = '09:00';

export type TaskReminderPreset =
  | 'at_time'
  | '15m_before'
  | '1h_before'
  | '1d_before'
  | 'custom';

export const TASK_REMINDER_PRESET_LABELS: Record<TaskReminderPreset, string> = {
  at_time: 'At scheduled / due time',
  '15m_before': '15 minutes before',
  '1h_before': '1 hour before',
  '1d_before': '1 day before',
  custom: 'Custom date & time',
};

export interface TaskReminderAnchor {
  dateIso: string;
  time: string;
  source: 'scheduled' | 'due';
  hasExplicitTime: boolean;
  utcIso: string;
  utcMs: number;
}

export interface TaskReminderInputResolution {
  ok: boolean;
  triggerTimeUtc?: string;
  error?: string;
}

export function buildCanonicalTaskReminderId(taskId: string): string {
  return `rem-task-${taskId}`;
}

export function isValidTaskReminderTime(timeStr?: string | null): boolean {
  if (!timeStr) return false;
  return DayTimeOfDay.tryParse(timeStr) !== null;
}

export function ethiopiaWallDateTimeToUtcIso(
  dateIso: string,
  timeStr: string
): string | null {
  const date = CalendarDate.tryParse(dateIso);
  const time = DayTimeOfDay.tryParse(timeStr);
  if (!date || !time) return null;
  const utc = EthiopiaClock.fromEthiopiaWallComponents(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
    0
  );
  return utc.toISOString();
}

export function utcIsoToEthiopiaWallDateTime(triggerTimeUtc: string): {
  dateIso: string;
  date: CalendarDate;
  time: string;
  hour: number;
  minute: number;
} | null {
  const parsedMs = Date.parse(triggerTimeUtc);
  if (!Number.isFinite(parsedMs)) return null;
  const wall = EthiopiaClock.toEthiopiaWallComponents(new Date(parsedMs));
  const date = new CalendarDate(wall.year, wall.month, wall.day);
  const hh = String(wall.hour).padStart(2, '0');
  const mm = String(wall.minute).padStart(2, '0');
  return {
    dateIso: date.toIsoString(),
    date,
    time: `${hh}:${mm}`,
    hour: wall.hour,
    minute: wall.minute,
  };
}

export function isTaskEligibleForActiveReminder(
  task: Pick<DaywellTaskRecord, 'status' | 'completed' | 'isArchived'>
): boolean {
  if (task.isArchived) return false;
  if (isTaskCompleted(task)) return false;
  if (task.status === 'cancelled') return false;
  return true;
}

export function resolveTaskReminderAnchor(
  task: Pick<DaywellTaskRecord, 'scheduledDate' | 'scheduledTime' | 'dueDate'>
): TaskReminderAnchor | null {
  const hasExplicitTime = isValidTaskReminderTime(task.scheduledTime);
  const effectiveTime = hasExplicitTime
    ? DayTimeOfDay.parse(task.scheduledTime!).toIsoString()
    : DEFAULT_TASK_REMINDER_TIME;

  const scheduledDate = CalendarDate.tryParse(task.scheduledDate);
  if (scheduledDate) {
    const utcIso = ethiopiaWallDateTimeToUtcIso(
      scheduledDate.toIsoString(),
      effectiveTime
    )!;
    return {
      dateIso: scheduledDate.toIsoString(),
      time: effectiveTime,
      source: 'scheduled',
      hasExplicitTime,
      utcIso,
      utcMs: Date.parse(utcIso),
    };
  }

  const dueDate = CalendarDate.tryParse(task.dueDate);
  if (dueDate) {
    const utcIso = ethiopiaWallDateTimeToUtcIso(
      dueDate.toIsoString(),
      effectiveTime
    )!;
    return {
      dateIso: dueDate.toIsoString(),
      time: effectiveTime,
      source: 'due',
      hasExplicitTime,
      utcIso,
      utcMs: Date.parse(utcIso),
    };
  }

  return null;
}

export function defaultFallbackReminderDateTime(nowUtc?: Date): {
  dateIso: string;
  time: string;
  triggerTimeUtc: string;
} {
  const effectiveNow = nowUtc ?? EthiopiaClock.nowUtc();
  const today = CalendarDate.fromUtcInstantInEthiopia(effectiveNow);
  const todayDefaultIso = ethiopiaWallDateTimeToUtcIso(
    today.toIsoString(),
    DEFAULT_TASK_REMINDER_TIME
  )!;
  if (Date.parse(todayDefaultIso) > effectiveNow.getTime()) {
    return {
      dateIso: today.toIsoString(),
      time: DEFAULT_TASK_REMINDER_TIME,
      triggerTimeUtc: todayDefaultIso,
    };
  }
  const tomorrow = today.addDays(1);
  return {
    dateIso: tomorrow.toIsoString(),
    time: DEFAULT_TASK_REMINDER_TIME,
    triggerTimeUtc: ethiopiaWallDateTimeToUtcIso(
      tomorrow.toIsoString(),
      DEFAULT_TASK_REMINDER_TIME
    )!,
  };
}

function presetOffsetMinutes(preset: Exclude<TaskReminderPreset, 'custom'>): number {
  switch (preset) {
    case 'at_time':
      return 0;
    case '15m_before':
      return 15;
    case '1h_before':
      return 60;
    case '1d_before':
      return 24 * 60;
  }
}

export function computeTaskReminderTriggerFromPreset(options: {
  task: Pick<DaywellTaskRecord, 'scheduledDate' | 'scheduledTime' | 'dueDate'>;
  preset: TaskReminderPreset;
  customDateIso?: string;
  customTime?: string;
  nowUtc?: Date;
}): TaskReminderInputResolution {
  const { task, preset, customDateIso, customTime, nowUtc } = options;

  if (preset === 'custom') {
    const parsedDate = CalendarDate.tryParse(customDateIso);
    if (!parsedDate) {
      return {
        ok: false,
        error: 'Choose a valid reminder date (YYYY-MM-DD).',
      };
    }
    const parsedTime = DayTimeOfDay.tryParse(customTime);
    if (!parsedTime) {
      return {
        ok: false,
        error: 'Choose a valid reminder time (HH:MM).',
      };
    }
    const triggerTimeUtc = ethiopiaWallDateTimeToUtcIso(
      parsedDate.toIsoString(),
      parsedTime.toIsoString()
    );
    if (!triggerTimeUtc) {
      return {
        ok: false,
        error: 'Unable to compute reminder timestamp.',
      };
    }
    return { ok: true, triggerTimeUtc };
  }

  const anchor = resolveTaskReminderAnchor(task);
  if (!anchor) {
    const fallback = defaultFallbackReminderDateTime(nowUtc);
    const offsetMs = presetOffsetMinutes(preset) * 60_000;
    return {
      ok: true,
      triggerTimeUtc: new Date(
        Date.parse(fallback.triggerTimeUtc) - offsetMs
      ).toISOString(),
    };
  }

  const offsetMs = presetOffsetMinutes(preset) * 60_000;
  return {
    ok: true,
    triggerTimeUtc: new Date(anchor.utcMs - offsetMs).toISOString(),
  };
}

export function inferTaskReminderPreset(
  task: Pick<DaywellTaskRecord, 'scheduledDate' | 'scheduledTime' | 'dueDate'>,
  triggerTimeUtc: string
): TaskReminderPreset {
  const anchor = resolveTaskReminderAnchor(task);
  if (!anchor) return 'custom';
  const triggerMs = Date.parse(triggerTimeUtc);
  if (!Number.isFinite(triggerMs)) return 'custom';

  const diffMs = anchor.utcMs - triggerMs;
  if (diffMs === 0) return 'at_time';
  if (diffMs === 15 * 60_000) return '15m_before';
  if (diffMs === 60 * 60_000) return '1h_before';
  if (diffMs === 24 * 60 * 60_000) return '1d_before';
  return 'custom';
}

export function recomputeReminderTriggerOnTaskUpdate(options: {
  previousTask: Pick<
    DaywellTaskRecord,
    'scheduledDate' | 'scheduledTime' | 'dueDate'
  >;
  nextTask: Pick<
    DaywellTaskRecord,
    'scheduledDate' | 'scheduledTime' | 'dueDate'
  >;
  existingTriggerUtc: string;
  shiftCustomOnDateShift?: boolean;
}): string {
  const {
    previousTask,
    nextTask,
    existingTriggerUtc,
    shiftCustomOnDateShift = false,
  } = options;
  const preset = inferTaskReminderPreset(previousTask, existingTriggerUtc);

  if (preset !== 'custom') {
    const nextAnchor = resolveTaskReminderAnchor(nextTask);
    if (!nextAnchor) {
      return existingTriggerUtc;
    }
    const offsetMs = presetOffsetMinutes(preset) * 60_000;
    return new Date(nextAnchor.utcMs - offsetMs).toISOString();
  }

  if (shiftCustomOnDateShift) {
    const prevPrimary =
      CalendarDate.tryParse(previousTask.scheduledDate) ??
      CalendarDate.tryParse(previousTask.dueDate);
    const nextPrimary =
      CalendarDate.tryParse(nextTask.scheduledDate) ??
      CalendarDate.tryParse(nextTask.dueDate);
    const existingWall = utcIsoToEthiopiaWallDateTime(existingTriggerUtc);
    if (prevPrimary && nextPrimary && existingWall) {
      const deltaDays = nextPrimary.jdn - prevPrimary.jdn;
      if (deltaDays !== 0) {
        const shiftedDate = existingWall.date.addDays(deltaDays);
        const shiftedIso = ethiopiaWallDateTimeToUtcIso(
          shiftedDate.toIsoString(),
          existingWall.time
        );
        if (shiftedIso) return shiftedIso;
      }
    }
  }

  return existingTriggerUtc;
}

export function findReminderForTask(
  reminders: readonly SharedReminder[],
  taskId: string
): SharedReminder | undefined {
  const matches = reminders.filter(
    (r) => r.targetType === 'task' && r.targetId === taskId
  );
  if (matches.length === 0) return undefined;
  const canonicalId = buildCanonicalTaskReminderId(taskId);
  return (
    matches.find((r) => r.id === canonicalId && r.isActive) ??
    matches.find((r) => r.isActive) ??
    matches.find((r) => r.id === canonicalId) ??
    matches[0]
  );
}

export function deduplicateTaskReminders(
  reminders: readonly SharedReminder[]
): SharedReminder[] {
  const seenTaskIds = new Set<string>();
  const taskBest = new Map<string, SharedReminder>();

  for (const r of reminders) {
    if (r.targetType !== 'task') continue;
    const prev = taskBest.get(r.targetId);
    if (!prev) {
      taskBest.set(r.targetId, r);
      continue;
    }
    const canonicalId = buildCanonicalTaskReminderId(r.targetId);
    const preferCandidate =
      (r.isActive && !prev.isActive) ||
      (r.isActive === prev.isActive &&
        r.id === canonicalId &&
        prev.id !== canonicalId);
    if (preferCandidate) {
      taskBest.set(r.targetId, r);
    }
  }

  const result: SharedReminder[] = [];
  for (const r of reminders) {
    if (r.targetType !== 'task') {
      result.push(r);
      continue;
    }
    if (seenTaskIds.has(r.targetId)) continue;
    const chosen = taskBest.get(r.targetId);
    if (chosen) {
      seenTaskIds.add(r.targetId);
      result.push(chosen);
    }
  }
  return result;
}

export function buildTaskReminderRecord(options: {
  task: Pick<
    DaywellTaskRecord,
    'id' | 'title' | 'status' | 'completed' | 'isArchived'
  >;
  triggerTimeUtc: string;
  existingReminder?: SharedReminder;
  nowUtc?: Date;
  forceActive?: boolean;
}): SharedReminder {
  const { task, triggerTimeUtc, existingReminder, nowUtc, forceActive } = options;
  const nowIso = (nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const eligible = isTaskEligibleForActiveReminder(task);
  const isActive = eligible ? (forceActive ?? true) : false;

  return {
    id: existingReminder?.id ?? buildCanonicalTaskReminderId(task.id),
    targetId: task.id,
    targetType: 'task',
    title: task.title.trim() || existingReminder?.title || 'Task Reminder',
    channelId: TASK_REMINDER_CHANNEL_ID,
    triggerTimeUtc: new Date(Date.parse(triggerTimeUtc)).toISOString(),
    isActive,
    createdAt: existingReminder?.createdAt ?? nowIso,
  };
}

export function reconcileTaskRemindersWithTasks(options: {
  tasks: readonly DaywellTaskRecord[];
  reminders: readonly SharedReminder[];
  previousTasks?: readonly DaywellTaskRecord[];
  generatedFromTaskId?: string;
  generatedNextTask?: DaywellTaskRecord;
  pruneOrphans?: boolean;
  shiftCustomOnDateShift?: boolean;
  nowUtc?: Date;
}): {
  reminders: SharedReminder[];
  tasks: DaywellTaskRecord[];
} {
  const {
    tasks,
    reminders,
    previousTasks,
    generatedFromTaskId,
    generatedNextTask,
    pruneOrphans = true,
    shiftCustomOnDateShift = false,
    nowUtc,
  } = options;

  const effectiveNow = nowUtc ?? EthiopiaClock.nowUtc();
  const taskById = new Map(tasks.map((t) => [t.id, t] as const));
  const prevById = new Map(
    (previousTasks ?? []).map((t) => [t.id, t] as const)
  );

  const nonTaskReminders: SharedReminder[] = [];
  const rawTaskRemindersByTarget = new Map<string, SharedReminder>();

  const deduped = deduplicateTaskReminders(reminders);
  for (const r of deduped) {
    if (r.targetType !== 'task') {
      nonTaskReminders.push(r);
      continue;
    }
    if (pruneOrphans && !taskById.has(r.targetId)) {
      continue;
    }
    rawTaskRemindersByTarget.set(r.targetId, r);
  }

  for (const task of tasks) {
    const existingReminder = rawTaskRemindersByTarget.get(task.id);
    if (!existingReminder) continue;

    const prevTask = prevById.get(task.id);
    const nextTriggerUtc = prevTask
      ? recomputeReminderTriggerOnTaskUpdate({
          previousTask: prevTask,
          nextTask: task,
          existingTriggerUtc: existingReminder.triggerTimeUtc,
          shiftCustomOnDateShift,
        })
      : existingReminder.triggerTimeUtc;

    const wasEligible = prevTask
      ? isTaskEligibleForActiveReminder(prevTask)
      : existingReminder.isActive;
    const isNowEligible = isTaskEligibleForActiveReminder(task);

    let nextActive: boolean;
    if (!isNowEligible) {
      nextActive = false;
    } else if (!wasEligible && isNowEligible) {
      // Reopening or unarchiving a task re-arms only if trigger is still upcoming
      nextActive = Date.parse(nextTriggerUtc) > effectiveNow.getTime();
    } else {
      nextActive = existingReminder.isActive;
    }

    rawTaskRemindersByTarget.set(
      task.id,
      buildTaskReminderRecord({
        task,
        triggerTimeUtc: nextTriggerUtc,
        existingReminder,
        nowUtc: effectiveNow,
        forceActive: nextActive,
      })
    );
  }

  // Carry over reminder cleanly to a spawned recurring occurrence
  if (
    generatedNextTask &&
    generatedFromTaskId &&
    !rawTaskRemindersByTarget.has(generatedNextTask.id)
  ) {
    const parentPrev = prevById.get(generatedFromTaskId);
    const parentCurr = taskById.get(generatedFromTaskId);
    const parentReminder =
      deduped.find(
        (r) => r.targetType === 'task' && r.targetId === generatedFromTaskId
      ) ?? rawTaskRemindersByTarget.get(generatedFromTaskId);
    const referenceParent = parentPrev ?? parentCurr;

    if (parentReminder && referenceParent) {
      const nextTriggerUtc = recomputeReminderTriggerOnTaskUpdate({
        previousTask: referenceParent,
        nextTask: generatedNextTask,
        existingTriggerUtc: parentReminder.triggerTimeUtc,
        shiftCustomOnDateShift: true,
      });
      rawTaskRemindersByTarget.set(
        generatedNextTask.id,
        buildTaskReminderRecord({
          task: generatedNextTask,
          triggerTimeUtc: nextTriggerUtc,
          nowUtc: effectiveNow,
          forceActive: isTaskEligibleForActiveReminder(generatedNextTask),
        })
      );
    } else if (referenceParent?.hasReminder) {
      const computed = computeTaskReminderTriggerFromPreset({
        task: generatedNextTask,
        preset: 'at_time',
        nowUtc: effectiveNow,
      });
      if (computed.ok && computed.triggerTimeUtc) {
        rawTaskRemindersByTarget.set(
          generatedNextTask.id,
          buildTaskReminderRecord({
            task: generatedNextTask,
            triggerTimeUtc: computed.triggerTimeUtc,
            nowUtc: effectiveNow,
            forceActive: isTaskEligibleForActiveReminder(generatedNextTask),
          })
        );
      }
    }
  }

  const nextTaskReminders = Array.from(rawTaskRemindersByTarget.values());
  const nextReminders = [...nonTaskReminders, ...nextTaskReminders];
  const syncedTasks = tasks.map((t) => {
    const reminder = rawTaskRemindersByTarget.get(t.id);
    const shouldHaveReminder = Boolean(reminder?.isActive);
    if (t.hasReminder === shouldHaveReminder) return t;
    return {
      ...t,
      hasReminder: shouldHaveReminder,
    };
  });

  return {
    reminders: nextReminders,
    tasks: syncedTasks,
  };
}

export function formatTaskReminderSummary(
  triggerTimeUtc: string,
  options?: { today?: CalendarDate }
): string {
  const wall = utcIsoToEthiopiaWallDateTime(triggerTimeUtc);
  if (!wall) return triggerTimeUtc;
  const today = options?.today ?? CalendarDate.today();
  const tomorrow = today.addDays(1);
  const yesterday = today.subtractDays(1);

  let dayLabel: string;
  if (wall.date.equals(today)) {
    dayLabel = 'Today';
  } else if (wall.date.equals(tomorrow)) {
    dayLabel = 'Tomorrow';
  } else if (wall.date.equals(yesterday)) {
    dayLabel = 'Yesterday';
  } else if (wall.date.year === today.year) {
    dayLabel = `${wall.date.gregorianShortMonthName} ${wall.date.day}`;
  } else {
    dayLabel = `${wall.date.gregorianShortMonthName} ${wall.date.day}, ${wall.date.year}`;
  }
  return `${dayLabel} · ${wall.time} EAT`;
}

export function isTaskReminderOverdue(
  reminder: SharedReminder,
  nowUtc?: Date
): boolean {
  if (!reminder.isActive) return false;
  const nowMs = (nowUtc ?? EthiopiaClock.nowUtc()).getTime();
  return Date.parse(reminder.triggerTimeUtc) <= nowMs;
}
