import {
  CalendarDate,
  EthiopiaClock,
  daysInGregorianMonth,
} from './date';
import {
  SharedTaskRecurrenceConfig,
  SharedTaskRecurrenceFrequency,
} from './sharedFoundation';
import {
  DaywellTaskRecord,
  isTaskCompleted,
  normalizeTaskRecurrenceConfig,
  resolveEffectiveTaskStatus,
  TaskSubItemRecord,
  updateTaskRecord,
} from './taskOperations';

const ISO_SHORT_WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'] as const;

export interface NextOccurrenceDatesResult {
  dueDate?: string;
  scheduledDate?: string;
  primaryDate: string;
}

export interface CompleteRecurringTaskResult {
  tasks: DaywellTaskRecord[];
  updatedTask?: DaywellTaskRecord;
  generatedNextTask?: DaywellTaskRecord;
  seriesEnded: boolean;
  duplicatePrevented: boolean;
}

export interface RecurrenceActionResult {
  ok: boolean;
  error?: string;
  tasks: DaywellTaskRecord[];
  updatedTask?: DaywellTaskRecord;
}

function isSupportedFrequency(
  value?: string | null
): value is SharedTaskRecurrenceFrequency {
  return (
    value === 'daily' ||
    value === 'weekly' ||
    value === 'monthly' ||
    value === 'yearly'
  );
}

/**
 * Resolves the effective normalized recurrence configuration for a task,
 * seamlessly upgrading legacy `recurrenceRule` / `recurringRule` strings.
 */
export function resolveEffectiveRecurrenceConfig(
  task: Pick<
    DaywellTaskRecord,
    'recurrenceConfig' | 'recurrenceRule' | 'recurringRule' | 'isRecurring'
  >
): SharedTaskRecurrenceConfig | undefined {
  const normalized = normalizeTaskRecurrenceConfig(task.recurrenceConfig);
  if (normalized) return normalized;

  const rawRule = (task.recurrenceRule ?? task.recurringRule)?.trim().toLowerCase();
  if (isSupportedFrequency(rawRule)) {
    return {
      frequency: rawRule,
      interval: 1,
      repeatFrom: 'due_date',
    };
  }
  return undefined;
}

export function areRecurrenceConfigsEqual(
  a?: SharedTaskRecurrenceConfig | null,
  b?: SharedTaskRecurrenceConfig | null
): boolean {
  const normA = normalizeTaskRecurrenceConfig(a);
  const normB = normalizeTaskRecurrenceConfig(b);
  if (!normA && !normB) return true;
  if (!normA || !normB) return false;
  if (normA.frequency !== normB.frequency) return false;
  if ((normA.interval ?? 1) !== (normB.interval ?? 1)) return false;
  if ((normA.repeatFrom ?? 'due_date') !== (normB.repeatFrom ?? 'due_date')) {
    return false;
  }
  if ((normA.startDate ?? null) !== (normB.startDate ?? null)) return false;
  if ((normA.endDate ?? null) !== (normB.endDate ?? null)) return false;

  const wdA = normA.weekdays ?? [];
  const wdB = normB.weekdays ?? [];
  if (wdA.length !== wdB.length) return false;
  for (let i = 0; i < wdA.length; i++) {
    if (wdA[i] !== wdB[i]) return false;
  }
  return true;
}

/**
 * Computes the next Gregorian occurrence date strictly following Daywell's
 * recurrence rules (interval, ISO weekdays 1..7, start floor, optional end cap).
 */
export function computeNextRecurrenceDate(
  anchor: CalendarDate,
  config: SharedTaskRecurrenceConfig
): CalendarDate | null {
  const normalized = normalizeTaskRecurrenceConfig(config);
  if (!normalized) return null;

  const interval = normalized.interval ?? 1;
  let candidate: CalendarDate;

  switch (normalized.frequency) {
    case 'daily': {
      candidate = anchor.addDays(interval);
      break;
    }
    case 'weekly': {
      const weekdays =
        normalized.weekdays && normalized.weekdays.length > 0
          ? normalized.weekdays
          : [anchor.weekday];
      const laterSameWeek = weekdays.find((wd) => wd > anchor.weekday);
      if (laterSameWeek !== undefined) {
        candidate = anchor.addDays(laterSameWeek - anchor.weekday);
      } else {
        const mondayOfAnchorWeek = anchor.subtractDays(anchor.weekday - 1);
        const nextCycleMonday = mondayOfAnchorWeek.addDays(7 * interval);
        candidate = nextCycleMonday.addDays(weekdays[0] - 1);
      }
      break;
    }
    case 'monthly': {
      const totalMonths = anchor.year * 12 + (anchor.month - 1) + interval;
      const nextYear = Math.floor(totalMonths / 12);
      const nextMonth = (totalMonths % 12) + 1;
      const maxDay = daysInGregorianMonth(nextYear, nextMonth);
      candidate = new CalendarDate(
        nextYear,
        nextMonth,
        Math.min(anchor.day, maxDay)
      );
      break;
    }
    case 'yearly': {
      const nextYear = anchor.year + interval;
      const maxDay = daysInGregorianMonth(nextYear, anchor.month);
      candidate = new CalendarDate(
        nextYear,
        anchor.month,
        Math.min(anchor.day, maxDay)
      );
      break;
    }
  }

  const startDate = normalized.startDate
    ? CalendarDate.tryParse(normalized.startDate)
    : null;
  if (startDate && candidate.isBefore(startDate)) {
    if (
      normalized.frequency === 'weekly' &&
      normalized.weekdays &&
      normalized.weekdays.length > 0
    ) {
      for (let offset = 0; offset < 7; offset++) {
        const probe = startDate.addDays(offset);
        if (normalized.weekdays.includes(probe.weekday)) {
          candidate = probe;
          break;
        }
      }
    } else {
      candidate = startDate;
    }
  }

  const endDate = normalized.endDate
    ? CalendarDate.tryParse(normalized.endDate)
    : null;
  if (endDate && candidate.isAfter(endDate)) {
    return null;
  }

  return candidate;
}

export function resolveRecurrenceAnchorDate(
  task: Pick<DaywellTaskRecord, 'dueDate' | 'scheduledDate'>,
  config: SharedTaskRecurrenceConfig,
  options?: { forCompletion?: boolean; nowUtc?: Date; todayIso?: string }
): CalendarDate {
  if (options?.forCompletion && config.repeatFrom === 'completion_date') {
    if (options.nowUtc) {
      return CalendarDate.fromUtcInstantInEthiopia(options.nowUtc);
    }
    const parsedToday = options.todayIso
      ? CalendarDate.tryParse(options.todayIso)
      : null;
    return (
      parsedToday ??
      CalendarDate.fromUtcInstantInEthiopia(EthiopiaClock.nowUtc())
    );
  }

  return (
    CalendarDate.tryParse(task.dueDate) ??
    CalendarDate.tryParse(task.scheduledDate) ??
    CalendarDate.tryParse(config.startDate) ??
    (options?.todayIso ? CalendarDate.tryParse(options.todayIso) : null) ??
    (options?.nowUtc
      ? CalendarDate.fromUtcInstantInEthiopia(options.nowUtc)
      : CalendarDate.today())
  );
}

export function computeNextOccurrenceDates(
  task: Pick<DaywellTaskRecord, 'dueDate' | 'scheduledDate'>,
  config: SharedTaskRecurrenceConfig,
  options?: { forCompletion?: boolean; nowUtc?: Date; todayIso?: string }
): NextOccurrenceDatesResult | null {
  const normalized = normalizeTaskRecurrenceConfig(config);
  if (!normalized) return null;

  const anchor = resolveRecurrenceAnchorDate(task, normalized, options);
  const nextDate = computeNextRecurrenceDate(anchor, normalized);
  if (!nextDate) return null;

  const prevDue = CalendarDate.tryParse(task.dueDate);
  const prevScheduled = CalendarDate.tryParse(task.scheduledDate);

  if (prevDue && prevScheduled) {
    const offsetDays = prevScheduled.differenceInDays(prevDue);
    const dueIso = nextDate.toIsoString();
    return {
      dueDate: dueIso,
      scheduledDate: nextDate.addDays(offsetDays).toIsoString(),
      primaryDate: dueIso,
    };
  }
  if (prevDue) {
    const dueIso = nextDate.toIsoString();
    return {
      dueDate: dueIso,
      primaryDate: dueIso,
    };
  }
  if (prevScheduled) {
    const schedIso = nextDate.toIsoString();
    return {
      scheduledDate: schedIso,
      primaryDate: schedIso,
    };
  }

  const dueIso = nextDate.toIsoString();
  return {
    dueDate: dueIso,
    primaryDate: dueIso,
  };
}

export function previewNextOccurrenceDate(
  task: Pick<DaywellTaskRecord, 'dueDate' | 'scheduledDate'>,
  config?: SharedTaskRecurrenceConfig | null,
  options?: { nowUtc?: Date; todayIso?: string }
): string | null {
  if (!config) return null;
  const res = computeNextOccurrenceDates(task, config, {
    forCompletion: false,
    ...options,
  });
  return res?.primaryDate ?? null;
}

export function formatRecurrenceSummary(
  config?: SharedTaskRecurrenceConfig | null
): string {
  const normalized = normalizeTaskRecurrenceConfig(config);
  if (!normalized) return '';

  const interval = normalized.interval ?? 1;
  let base: string;
  switch (normalized.frequency) {
    case 'daily':
      base = interval === 1 ? 'Daily' : `Every ${interval} days`;
      break;
    case 'weekly': {
      const baseUnit = interval === 1 ? 'Weekly' : `Every ${interval} weeks`;
      if (normalized.weekdays && normalized.weekdays.length > 0) {
        const names = normalized.weekdays
          .map((d) => ISO_SHORT_WEEKDAYS[d - 1])
          .filter(Boolean)
          .join(', ');
        base = names ? `${baseUnit} (${names})` : baseUnit;
      } else {
        base = baseUnit;
      }
      break;
    }
    case 'monthly':
      base = interval === 1 ? 'Monthly' : `Every ${interval} months`;
      break;
    case 'yearly':
      base = interval === 1 ? 'Yearly' : `Every ${interval} years`;
      break;
  }
  return base;
}

function buildNextOccurrenceId(
  existingTasks: readonly DaywellTaskRecord[],
  now: Date,
  preferredId?: string
): string {
  const usedIds = new Set(existingTasks.map((t) => t.id));
  if (preferredId && preferredId.trim() && !usedIds.has(preferredId.trim())) {
    return preferredId.trim();
  }
  let candidate = `t-${now.getTime()}-${Math.floor(Math.random() * 10000)}`;
  let suffix = 1;
  while (usedIds.has(candidate)) {
    candidate = `t-${now.getTime()}-${suffix}`;
    suffix++;
  }
  return candidate;
}

function cloneResetSubtasks(
  subtasks: readonly TaskSubItemRecord[],
  nextTaskId: string
): TaskSubItemRecord[] {
  return subtasks.map((sub, idx) => ({
    id: `${nextTaskId}-sub-${idx + 1}`,
    title: sub.title,
    completed: false,
  }));
}

export function hasMatchingActiveOrDateOccurrence(
  existingTasks: readonly DaywellTaskRecord[],
  sourceTask: DaywellTaskRecord,
  nextPrimaryDateIso: string,
  effectiveConfig: SharedTaskRecurrenceConfig
): boolean {
  const sourceTitle = sourceTask.title.trim().toLowerCase();
  const sourceProjectId = sourceTask.projectId ?? null;

  return existingTasks.some((other) => {
    if (other.id === sourceTask.id) return false;
    if (other.isArchived) return false;
    if (resolveEffectiveTaskStatus(other) === 'cancelled') return false;
    if (other.title.trim().toLowerCase() !== sourceTitle) return false;
    if ((other.projectId ?? null) !== sourceProjectId) return false;

    const otherConfig = resolveEffectiveRecurrenceConfig(other);
    if (!areRecurrenceConfigsEqual(otherConfig, effectiveConfig)) return false;

    const otherPrimary = other.dueDate ?? other.scheduledDate ?? null;
    if (otherPrimary === nextPrimaryDateIso) return true;
    if (
      !isTaskCompleted(other) &&
      otherPrimary !== null &&
      otherPrimary >= nextPrimaryDateIso
    ) {
      return true;
    }
    return false;
  });
}

/**
 * Marks `taskId` completed (or reopens it if already completed). When a recurring
 * task transitions to completed, spawns the next occurrence unless the series
 * reached its `endDate` or an equivalent occurrence already exists.
 */
export function completeTaskWithRecurrence(
  existingTasks: readonly DaywellTaskRecord[],
  taskId: string,
  options?: {
    nowUtc?: Date;
    todayIso?: string;
    nextTaskId?: string;
  }
): CompleteRecurringTaskResult {
  const target = existingTasks.find((t) => t.id === taskId);
  if (!target) {
    return {
      tasks: [...existingTasks],
      seriesEnded: false,
      duplicatePrevented: false,
    };
  }

  const now = options?.nowUtc ?? EthiopiaClock.nowUtc();
  const nowIso = now.toISOString();
  const wasCompleted = isTaskCompleted(target);

  if (wasCompleted) {
    const reopenedTask: DaywellTaskRecord = {
      ...target,
      completed: false,
      status: 'not_started',
      completedAt: undefined,
      updatedAt: nowIso,
    };
    return {
      tasks: existingTasks.map((t) => (t.id === taskId ? reopenedTask : t)),
      updatedTask: reopenedTask,
      seriesEnded: false,
      duplicatePrevented: false,
    };
  }

  const completedTask: DaywellTaskRecord = {
    ...target,
    completed: true,
    status: 'completed',
    completedAt: target.completedAt ?? nowIso,
    updatedAt: nowIso,
  };
  const updatedList = existingTasks.map((t) =>
    t.id === taskId ? completedTask : t
  );

  const effectiveConfig = resolveEffectiveRecurrenceConfig(target);
  if (!effectiveConfig || target.isArchived) {
    return {
      tasks: updatedList,
      updatedTask: completedTask,
      seriesEnded: false,
      duplicatePrevented: false,
    };
  }

  const nextDates = computeNextOccurrenceDates(target, effectiveConfig, {
    forCompletion: true,
    nowUtc: now,
    todayIso: options?.todayIso,
  });

  if (!nextDates) {
    return {
      tasks: updatedList,
      updatedTask: completedTask,
      seriesEnded: true,
      duplicatePrevented: false,
    };
  }

  if (
    hasMatchingActiveOrDateOccurrence(
      updatedList,
      target,
      nextDates.primaryDate,
      effectiveConfig
    )
  ) {
    return {
      tasks: updatedList,
      updatedTask: completedTask,
      seriesEnded: false,
      duplicatePrevented: true,
    };
  }

  const nextId = buildNextOccurrenceId(updatedList, now, options?.nextTaskId);
  const legacyRule =
    effectiveConfig.frequency === 'daily' ||
    effectiveConfig.frequency === 'weekly' ||
    effectiveConfig.frequency === 'monthly'
      ? effectiveConfig.frequency
      : undefined;

  const generatedNextTask: DaywellTaskRecord = {
    id: nextId,
    title: target.title,
    description: target.description,
    category: target.category ?? target.projectName,
    status: 'not_started',
    priority: target.priority,
    completed: false,
    completedAt: undefined,
    dueDate: nextDates.dueDate,
    scheduledDate: nextDates.scheduledDate,
    scheduledTime: target.scheduledTime,
    estimatedDurationMinutes: target.estimatedDurationMinutes,
    projectId: target.projectId,
    milestoneId: target.milestoneId,
    projectName: target.projectName,
    hasReminder: target.hasReminder,
    isRecurring: true,
    ...(legacyRule !== undefined ? { recurringRule: legacyRule } : {}),
    recurrenceRule: effectiveConfig.frequency,
    recurrenceConfig: effectiveConfig,
    subtasks: cloneResetSubtasks(target.subtasks, nextId),
    ...(target.labels && target.labels.length > 0
      ? { labels: [...target.labels] }
      : {}),
    isPinned: target.isPinned,
    isMyDay: false,
    myDayDate: undefined,
    isArchived: false,
    sortOrder: 0,
    createdAt: nowIso,
    updatedAt: nowIso,
  };

  return {
    tasks: [generatedNextTask, ...updatedList],
    updatedTask: completedTask,
    generatedNextTask,
    seriesEnded: false,
    duplicatePrevented: false,
  };
}

/**
 * Skips the current uncompleted recurring occurrence by advancing its schedule
 * to the next calculated date while preserving the recurrence series.
 */
export function skipRecurrenceOccurrence(
  existingTasks: readonly DaywellTaskRecord[],
  taskId: string,
  options?: { nowUtc?: Date; todayIso?: string }
): RecurrenceActionResult {
  const target = existingTasks.find((t) => t.id === taskId);
  if (!target) {
    return { ok: false, error: 'Task not found.', tasks: [...existingTasks] };
  }
  if (isTaskCompleted(target)) {
    return {
      ok: false,
      error: 'Completed tasks cannot be skipped.',
      tasks: [...existingTasks],
    };
  }
  const effectiveConfig = resolveEffectiveRecurrenceConfig(target);
  if (!effectiveConfig) {
    return {
      ok: false,
      error: 'This task does not have an active recurrence rule.',
      tasks: [...existingTasks],
    };
  }

  const nextDates = computeNextOccurrenceDates(target, effectiveConfig, {
    forCompletion: false,
    nowUtc: options?.nowUtc,
    todayIso: options?.todayIso,
  });
  if (!nextDates) {
    return {
      ok: false,
      error: 'Recurrence end date reached; no upcoming occurrence.',
      tasks: [...existingTasks],
    };
  }

  const clearMyDayForNewDate =
    Boolean(target.myDayDate) && target.myDayDate !== nextDates.primaryDate;
  const nowIso = (options?.nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const updatedTask: DaywellTaskRecord = {
    ...target,
    dueDate: nextDates.dueDate,
    scheduledDate: nextDates.scheduledDate,
    ...(clearMyDayForNewDate ? { isMyDay: false, myDayDate: undefined } : {}),
    updatedAt: nowIso,
  };

  return {
    ok: true,
    tasks: existingTasks.map((t) => (t.id === taskId ? updatedTask : t)),
    updatedTask,
  };
}

/**
 * Reschedules an occurrence to a specific YYYY-MM-DD date without losing its
 * recurrence series or lead-time offset between due and scheduled dates.
 */
export function rescheduleRecurrenceOccurrence(
  existingTasks: readonly DaywellTaskRecord[],
  taskId: string,
  newDateIso: string,
  options?: { nowUtc?: Date }
): RecurrenceActionResult {
  const target = existingTasks.find((t) => t.id === taskId);
  if (!target) {
    return { ok: false, error: 'Task not found.', tasks: [...existingTasks] };
  }
  const parsedDate = CalendarDate.tryParse(newDateIso);
  if (!parsedDate) {
    return {
      ok: false,
      error: 'Please choose a valid YYYY-MM-DD date.',
      tasks: [...existingTasks],
    };
  }

  const prevDue = CalendarDate.tryParse(target.dueDate);
  const prevScheduled = CalendarDate.tryParse(target.scheduledDate);
  let nextDueDate: string | undefined;
  let nextScheduledDate: string | undefined;

  if (prevDue && prevScheduled) {
    const offsetDays = prevScheduled.differenceInDays(prevDue);
    nextDueDate = parsedDate.toIsoString();
    nextScheduledDate = parsedDate.addDays(offsetDays).toIsoString();
  } else if (prevScheduled && !prevDue) {
    nextScheduledDate = parsedDate.toIsoString();
  } else {
    nextDueDate = parsedDate.toIsoString();
  }

  const res = updateTaskRecord(
    target,
    {
      dueDate: nextDueDate,
      scheduledDate: nextScheduledDate,
    },
    options?.nowUtc
  );

  if (!res.ok) {
    const firstErr = Object.values(res.errors)[0] ?? 'Unable to reschedule task.';
    return { ok: false, error: firstErr, tasks: [...existingTasks] };
  }

  return {
    ok: true,
    tasks: existingTasks.map((t) => (t.id === taskId ? res.task : t)),
    updatedTask: res.task,
  };
}

/**
 * Stops future recurrence on a task while preserving completion history and all
 * non-recurrence fields.
 */
export function stopTaskRecurrence(
  existingTasks: readonly DaywellTaskRecord[],
  taskId: string,
  options?: { nowUtc?: Date }
): RecurrenceActionResult {
  const target = existingTasks.find((t) => t.id === taskId);
  if (!target) {
    return { ok: false, error: 'Task not found.', tasks: [...existingTasks] };
  }
  const res = updateTaskRecord(
    target,
    {
      isRecurring: false,
      clearRecurrenceConfig: true,
    },
    options?.nowUtc
  );
  if (!res.ok) {
    const firstErr = Object.values(res.errors)[0] ?? 'Unable to stop recurrence.';
    return { ok: false, error: firstErr, tasks: [...existingTasks] };
  }
  return {
    ok: true,
    tasks: existingTasks.map((t) => (t.id === taskId ? res.task : t)),
    updatedTask: res.task,
  };
}
