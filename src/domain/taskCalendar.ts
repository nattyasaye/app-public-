import { CalendarDate, DateRange } from './date';
import {
  areRecurrenceConfigsEqual,
  computeNextOccurrenceDates,
  formatRecurrenceSummary,
  resolveEffectiveRecurrenceConfig,
} from './taskRecurrence';
import {
  DaywellTaskRecord,
  isTaskCompleted,
  resolveEffectiveTaskStatus,
} from './taskOperations';
import { SharedTaskRecurrenceConfig } from './sharedFoundation';

export type TaskCalendarOccurrenceKind =
  | 'due'
  | 'scheduled'
  | 'due_and_scheduled'
  | 'recurring_preview';

export interface CalendarTaskSource
  extends Pick<
    DaywellTaskRecord,
    | 'id'
    | 'title'
    | 'completed'
    | 'status'
    | 'dueDate'
    | 'scheduledDate'
    | 'scheduledTime'
    | 'estimatedDurationMinutes'
    | 'projectId'
    | 'projectName'
    | 'isArchived'
    | 'isRecurring'
    | 'recurringRule'
    | 'recurrenceRule'
    | 'recurrenceConfig'
  > {
  priority?: DaywellTaskRecord['priority'];
  recurrenceSummary?: string;
}

export interface TaskCalendarOccurrence<
  TTask extends CalendarTaskSource = CalendarTaskSource,
> {
  id: string;
  sourceTaskId: string;
  task: TTask;
  occurrenceDate: string; // YYYY-MM-DD
  kind: TaskCalendarOccurrenceKind;
  isProjectedOccurrence: boolean;
  scheduledTime?: string;
  estimatedDurationMinutes?: number;
  priority: NonNullable<CalendarTaskSource['priority']>;
  completed: boolean;
  recurrenceSummary?: string;
  isCompletionBasedRecurrence: boolean;
  companionDueDate?: string;
  companionScheduledDate?: string;
}

const PRIORITY_RANK: Record<NonNullable<CalendarTaskSource['priority']>, number> = {
  urgent: 0,
  high: 1,
  medium: 2,
  low: 3,
};

const MAX_RECURRENCE_PROJECTION_STEPS = 120;

function isTaskActiveForCalendar(task: CalendarTaskSource): boolean {
  if (task.isArchived) return false;
  if (resolveEffectiveTaskStatus(task) === 'cancelled') return false;
  return true;
}

function isTaskDone(task: CalendarTaskSource): boolean {
  return isTaskCompleted(task);
}

/**
 * Resolves the primary calendar date to jump to when navigating from a task
 * to Calendar: prefers `scheduledDate` (when work is planned), falling back
 * to `dueDate`. Returns null if neither is a valid YYYY-MM-DD date.
 */
export function getTaskPrimaryCalendarDate(
  task: Pick<CalendarTaskSource, 'dueDate' | 'scheduledDate'>
): string | null {
  const scheduled = task.scheduledDate
    ? CalendarDate.tryParse(task.scheduledDate)
    : null;
  if (scheduled) return scheduled.toIsoString();

  const due = task.dueDate ? CalendarDate.tryParse(task.dueDate) : null;
  if (due) return due.toIsoString();

  return null;
}

function buildSeriesKey(
  task: Pick<CalendarTaskSource, 'title' | 'projectId'>
): string {
  return `${task.title.trim().toLowerCase()}::${task.projectId ?? ''}`;
}

function resolveRecurrenceInfo(task: CalendarTaskSource): {
  config?: SharedTaskRecurrenceConfig;
  summary?: string;
} {
  const config = resolveEffectiveRecurrenceConfig(task);
  const summary = config
    ? formatRecurrenceSummary(config)
    : task.recurrenceSummary?.trim() || undefined;
  return { config, summary };
}

function hasMatchingStoredOccurrenceOnDate(
  allActiveTasks: readonly CalendarTaskSource[],
  sourceTask: CalendarTaskSource,
  sourceConfig: SharedTaskRecurrenceConfig,
  targetDateIso: string
): boolean {
  const targetKey = buildSeriesKey(sourceTask);
  for (const other of allActiveTasks) {
    if (buildSeriesKey(other) !== targetKey) continue;
    const otherConfig = resolveEffectiveRecurrenceConfig(other);
    if (!otherConfig || !areRecurrenceConfigsEqual(otherConfig, sourceConfig)) {
      continue;
    }
    const otherDue = other.dueDate
      ? CalendarDate.tryParse(other.dueDate)?.toIsoString()
      : null;
    const otherSched = other.scheduledDate
      ? CalendarDate.tryParse(other.scheduledDate)?.toIsoString()
      : null;
    if (otherDue === targetDateIso || otherSched === targetDateIso) {
      return true;
    }
  }
  return false;
}

export function sortTaskCalendarOccurrences<T extends CalendarTaskSource>(
  items: readonly TaskCalendarOccurrence<T>[]
): TaskCalendarOccurrence<T>[] {
  return [...items].sort((a, b) => {
    const dateCmp = a.occurrenceDate.localeCompare(b.occurrenceDate);
    if (dateCmp !== 0) return dateCmp;

    // Stored active/completed tasks before virtual future projections
    if (a.isProjectedOccurrence !== b.isProjectedOccurrence) {
      return a.isProjectedOccurrence ? 1 : -1;
    }

    // Uncompleted before completed
    if (a.completed !== b.completed) {
      return a.completed ? 1 : -1;
    }

    // Timed entries chronologically first
    const timeA = a.scheduledTime ?? '';
    const timeB = b.scheduledTime ?? '';
    if (timeA !== timeB) {
      if (!timeA) return 1;
      if (!timeB) return -1;
      return timeA.localeCompare(timeB);
    }

    const pDiff = PRIORITY_RANK[a.priority] - PRIORITY_RANK[b.priority];
    if (pDiff !== 0) return pDiff;

    return a.task.title.localeCompare(b.task.title);
  });
}

/**
 * Projects stored task dates (`scheduledDate`, `dueDate`) and future recurring
 * occurrences across `[rangeStartIso, rangeEndIso]` inclusive without mutating
 * task lists or creating duplicate calendar event records.
 */
export function projectTasksForDateRange<T extends CalendarTaskSource>(
  tasks: readonly T[],
  rangeStartIso: string,
  rangeEndIso: string
): TaskCalendarOccurrence<T>[] {
  const start = CalendarDate.tryParse(rangeStartIso);
  const end = CalendarDate.tryParse(rangeEndIso);
  if (!start || !end || end.isBefore(start)) {
    return [];
  }

  const range = new DateRange(start, end);
  const activeTasks = tasks.filter(isTaskActiveForCalendar);
  const occurrences: TaskCalendarOccurrence<T>[] = [];
  const emittedKeys = new Set<string>();

  for (const task of activeTasks) {
    const dueParsed = task.dueDate ? CalendarDate.tryParse(task.dueDate) : null;
    const scheduledParsed = task.scheduledDate
      ? CalendarDate.tryParse(task.scheduledDate)
      : null;
    const dueIso = dueParsed?.toIsoString();
    const scheduledIso = scheduledParsed?.toIsoString();
    const done = isTaskDone(task);
    const priority = task.priority ?? 'medium';
    const { config: recConfig, summary: recSummary } =
      resolveRecurrenceInfo(task);
    const isCompletionBased = recConfig?.repeatFrom === 'completion_date';

    if (scheduledParsed && dueParsed && scheduledIso === dueIso) {
      if (range.contains(dueParsed) && dueIso) {
        emittedKeys.add(`${task.id}::${dueIso}`);
        occurrences.push({
          id: `${task.id}::${dueIso}`,
          sourceTaskId: task.id,
          task,
          occurrenceDate: dueIso,
          kind: 'due_and_scheduled',
          isProjectedOccurrence: false,
          scheduledTime: task.scheduledTime,
          estimatedDurationMinutes: task.estimatedDurationMinutes,
          priority,
          completed: done,
          recurrenceSummary: recSummary,
          isCompletionBasedRecurrence: isCompletionBased,
        });
      }
    } else {
      if (scheduledParsed && scheduledIso && range.contains(scheduledParsed)) {
        emittedKeys.add(`${task.id}::${scheduledIso}`);
        occurrences.push({
          id: `${task.id}::${scheduledIso}`,
          sourceTaskId: task.id,
          task,
          occurrenceDate: scheduledIso,
          kind: 'scheduled',
          isProjectedOccurrence: false,
          scheduledTime: task.scheduledTime,
          estimatedDurationMinutes: task.estimatedDurationMinutes,
          priority,
          completed: done,
          recurrenceSummary: recSummary,
          isCompletionBasedRecurrence: isCompletionBased,
          companionDueDate: dueIso,
        });
      }

      if (dueParsed && dueIso && range.contains(dueParsed)) {
        emittedKeys.add(`${task.id}::${dueIso}`);
        occurrences.push({
          id: `${task.id}::${dueIso}`,
          sourceTaskId: task.id,
          task,
          occurrenceDate: dueIso,
          kind: 'due',
          isProjectedOccurrence: false,
          scheduledTime: scheduledParsed ? undefined : task.scheduledTime,
          estimatedDurationMinutes: scheduledParsed
            ? undefined
            : task.estimatedDurationMinutes,
          priority,
          completed: done,
          recurrenceSummary: recSummary,
          isCompletionBasedRecurrence: isCompletionBased,
          companionScheduledDate: scheduledIso,
        });
      }
    }

    // Project upcoming occurrences strictly for uncompleted recurring tasks
    // that have an explicit anchor date (dueDate, scheduledDate, or recurrence startDate).
    if (
      !done &&
      recConfig &&
      (dueIso !== undefined ||
        scheduledIso !== undefined ||
        Boolean(recConfig.startDate))
    ) {
      let cursorDue = dueIso;
      let cursorScheduled = scheduledIso;
      const seenProjected = new Set<string>();

      for (let step = 0; step < MAX_RECURRENCE_PROJECTION_STEPS; step++) {
        const nextDates = computeNextOccurrenceDates(
          {
            dueDate: cursorDue,
            scheduledDate: cursorScheduled,
          },
          recConfig,
          { forCompletion: false }
        );
        if (!nextDates) break;

        const nextDate = CalendarDate.tryParse(nextDates.primaryDate);
        if (!nextDate) break;
        const nextIso = nextDate.toIsoString();

        if (seenProjected.has(nextIso)) break;
        seenProjected.add(nextIso);

        if (nextDate.isAfter(end)) break;

        if (
          range.contains(nextDate) &&
          !emittedKeys.has(`${task.id}::${nextIso}`) &&
          !hasMatchingStoredOccurrenceOnDate(activeTasks, task, recConfig, nextIso)
        ) {
          emittedKeys.add(`${task.id}::${nextIso}`);
          occurrences.push({
            id: `${task.id}::preview::${nextIso}`,
            sourceTaskId: task.id,
            task,
            occurrenceDate: nextIso,
            kind: 'recurring_preview',
            isProjectedOccurrence: true,
            scheduledTime: task.scheduledTime,
            estimatedDurationMinutes: task.estimatedDurationMinutes,
            priority,
            completed: false,
            recurrenceSummary: recSummary,
            isCompletionBasedRecurrence: isCompletionBased,
          });
        }

        cursorDue = nextDates.dueDate;
        cursorScheduled = nextDates.scheduledDate;
      }
    }
  }

  return sortTaskCalendarOccurrences(occurrences);
}

export function projectTasksForDate<T extends CalendarTaskSource>(
  tasks: readonly T[],
  dateIso: string
): TaskCalendarOccurrence<T>[] {
  return projectTasksForDateRange(tasks, dateIso, dateIso);
}
