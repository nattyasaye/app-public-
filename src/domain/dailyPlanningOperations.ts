import { CalendarDate, EthiopiaClock } from './date';
import {
  CANONICAL_DAILY_PLANNING_ACTIONS,
  SharedDailyPlanningAction,
  SharedDailyPlanningEntry,
} from './sharedFoundation';
import {
  DaywellTaskRecord,
  isTaskCompleted,
  resolveEffectiveTaskStatus,
  TaskPriority,
} from './taskOperations';

export { CANONICAL_DAILY_PLANNING_ACTIONS };

const PRIORITY_ORDER: Record<TaskPriority, number> = {
  urgent: 0,
  high: 1,
  medium: 2,
  low: 3,
};

export interface DailyPlanItem {
  task: DaywellTaskRecord;
  entry?: SharedDailyPlanningEntry;
  planDate: string;
  action: SharedDailyPlanningAction;
  isCompletedForDay: boolean;
  completedLater: boolean;
  isCarriedForward: boolean;
}

export interface DailyPlanSuggestion {
  task: DaywellTaskRecord;
  reason: 'carry_forward' | 'overdue' | 'scheduled';
  sourcePlanDate?: string;
}

export interface DailyPlanSnapshot {
  selectedDate: string;
  todayDate: string;
  isToday: boolean;
  isPastDay: boolean;
  isFutureDay: boolean;
  items: DailyPlanItem[];
  remainingItems: DailyPlanItem[];
  completedItems: DailyPlanItem[];
  dismissedCount: number;
  totalPlannedCount: number;
  completedCount: number;
  remainingCount: number;
  progressPercentage: number;
  carryForwardSuggestions: DailyPlanSuggestion[];
  overdueSuggestions: DailyPlanSuggestion[];
  scheduledSuggestions: DailyPlanSuggestion[];
  otherActiveTasks: DaywellTaskRecord[];
  historyDates: string[];
}

export function buildDailyPlanningEntryId(
  taskId: string,
  planDateIso: string
): string {
  return `dpe-${planDateIso.trim()}-${taskId.trim()}`;
}

export function normalizeDailyPlanningAction(
  action?: string | null
): SharedDailyPlanningAction {
  const trimmed = typeof action === 'string' ? action.trim() : '';
  if (
    (CANONICAL_DAILY_PLANNING_ACTIONS as readonly string[]).includes(trimmed)
  ) {
    return trimmed as SharedDailyPlanningAction;
  }
  return 'planned';
}

export function normalizeDailyPlanningEntry(
  raw: unknown
): SharedDailyPlanningEntry | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const e = raw as Record<string, unknown>;
  const taskId = typeof e.taskId === 'string' ? e.taskId.trim() : '';
  const planDateRaw = typeof e.planDate === 'string' ? e.planDate.trim() : '';
  const parsedDate = CalendarDate.tryParse(planDateRaw);
  if (!taskId || !parsedDate) return null;
  const planDate = parsedDate.toIsoString();
  const idRaw = typeof e.id === 'string' ? e.id.trim() : '';
  const id = idRaw || buildDailyPlanningEntryId(taskId, planDate);
  const action = normalizeDailyPlanningAction(
    typeof e.action === 'string' ? e.action : null
  );
  const createdAt =
    typeof e.createdAt === 'string' && e.createdAt.trim()
      ? e.createdAt.trim()
      : EthiopiaClock.nowUtc().toISOString();
  const updatedAt =
    typeof e.updatedAt === 'string' && e.updatedAt.trim()
      ? e.updatedAt.trim()
      : undefined;

  return {
    id,
    planDate,
    taskId,
    action,
    createdAt,
    ...(updatedAt !== undefined ? { updatedAt } : {}),
  };
}

function entryFreshnessEpoch(entry: SharedDailyPlanningEntry): number {
  const updatedMs = entry.updatedAt ? Date.parse(entry.updatedAt) : Number.NaN;
  if (Number.isFinite(updatedMs)) return updatedMs;
  const createdMs = Date.parse(entry.createdAt);
  return Number.isFinite(createdMs) ? createdMs : 0;
}

export function normalizeDailyPlanningEntriesList(
  entries: readonly unknown[]
): SharedDailyPlanningEntry[] {
  if (!Array.isArray(entries)) return [];
  const byComposite = new Map<string, SharedDailyPlanningEntry>();
  for (const raw of entries) {
    const normalized = normalizeDailyPlanningEntry(raw);
    if (!normalized) continue;
    const composite = `${normalized.taskId}::${normalized.planDate}`;
    const existing = byComposite.get(composite);
    if (
      !existing ||
      entryFreshnessEpoch(normalized) >= entryFreshnessEpoch(existing)
    ) {
      byComposite.set(composite, normalized);
    }
  }
  return Array.from(byComposite.values()).sort((a, b) => {
    const dateCmp = a.planDate.localeCompare(b.planDate);
    if (dateCmp !== 0) return dateCmp;
    return a.createdAt.localeCompare(b.createdAt);
  });
}

function sortDailyPlanItems(
  a: { task: DaywellTaskRecord; entry?: SharedDailyPlanningEntry },
  b: { task: DaywellTaskRecord; entry?: SharedDailyPlanningEntry }
): number {
  const orderA = a.task.sortOrder ?? 0;
  const orderB = b.task.sortOrder ?? 0;
  if (orderA !== orderB) return orderA - orderB;

  const pinA = a.task.isPinned ? 0 : 1;
  const pinB = b.task.isPinned ? 0 : 1;
  if (pinA !== pinB) return pinA - pinB;

  const prioA = PRIORITY_ORDER[a.task.priority] ?? 2;
  const prioB = PRIORITY_ORDER[b.task.priority] ?? 2;
  if (prioA !== prioB) return prioA - prioB;

  const dueA = a.task.dueDate ?? '9999-12-31';
  const dueB = b.task.dueDate ?? '9999-12-31';
  if (dueA !== dueB) return dueA.localeCompare(dueB);

  return a.task.title.localeCompare(b.task.title);
}

export function findDailyPlanningEntry(
  entries: readonly SharedDailyPlanningEntry[],
  taskId: string,
  planDateIso: string
): SharedDailyPlanningEntry | undefined {
  return entries.find(
    (e) => e.taskId === taskId && e.planDate === planDateIso
  );
}

export function isTaskPlannedForDate(
  task: DaywellTaskRecord,
  entries: readonly SharedDailyPlanningEntry[],
  planDateIso: string,
  todayIso?: string
): boolean {
  if (task.isArchived) return false;
  const today = todayIso ?? CalendarDate.today().toIsoString();
  const entry = findDailyPlanningEntry(entries, task.id, planDateIso);
  if (entry) {
    return entry.action !== 'dismissed';
  }
  if (!task.isMyDay) return false;
  if (!task.myDayDate) {
    return planDateIso === today;
  }
  return task.myDayDate === planDateIso;
}

export function hasPriorPlannedHistory(
  entries: readonly SharedDailyPlanningEntry[],
  taskId: string,
  beforeDateIso: string
): boolean {
  return entries.some(
    (e) =>
      e.taskId === taskId &&
      e.planDate < beforeDateIso &&
      e.action !== 'dismissed'
  );
}

function nextActionOnReopen(
  entries: readonly SharedDailyPlanningEntry[],
  taskId: string,
  planDateIso: string
): 'planned' | 'carried_forward' {
  return hasPriorPlannedHistory(entries, taskId, planDateIso)
    ? 'carried_forward'
    : 'planned';
}

export function planTaskForDate(
  tasks: readonly DaywellTaskRecord[],
  entries: readonly SharedDailyPlanningEntry[],
  taskId: string,
  planDateIso: string,
  options?: {
    action?: 'planned' | 'carried_forward';
    todayIso?: string;
    nowUtc?: Date;
  }
): {
  tasks: DaywellTaskRecord[];
  entries: SharedDailyPlanningEntry[];
  entry?: SharedDailyPlanningEntry;
} {
  const parsedDate = CalendarDate.tryParse(planDateIso);
  if (!parsedDate) {
    return { tasks: [...tasks], entries: [...entries] };
  }
  const normalizedDate = parsedDate.toIsoString();
  const today = options?.todayIso ?? CalendarDate.today().toIsoString();
  const now = options?.nowUtc ?? EthiopiaClock.nowUtc();
  const nowIso = now.toISOString();

  const targetTask = tasks.find((t) => t.id === taskId);
  if (!targetTask || targetTask.isArchived) {
    return { tasks: [...tasks], entries: [...entries] };
  }

  const normalizedEntries = normalizeDailyPlanningEntriesList(entries);
  const existingEntry = findDailyPlanningEntry(
    normalizedEntries,
    taskId,
    normalizedDate
  );

  const alreadyActiveOnDate = isTaskPlannedForDate(
    targetTask,
    normalizedEntries,
    normalizedDate,
    today
  );

  let assignedSortOrder = targetTask.sortOrder ?? 0;
  if (!alreadyActiveOnDate) {
    const otherPlannedTasks = tasks.filter(
      (t) =>
        t.id !== taskId &&
        isTaskPlannedForDate(t, normalizedEntries, normalizedDate, today)
    );
    if (otherPlannedTasks.length > 0) {
      const maxOrder = otherPlannedTasks.reduce(
        (max, t) => Math.max(max, t.sortOrder ?? 0),
        0
      );
      assignedSortOrder = maxOrder + 1;
    }
  }

  const desiredAction: SharedDailyPlanningAction = isTaskCompleted(targetTask)
    ? 'completed'
    : options?.action ?? 'planned';

  const nextEntry: SharedDailyPlanningEntry = existingEntry
    ? {
        ...existingEntry,
        action: desiredAction,
        updatedAt: nowIso,
      }
    : {
        id: buildDailyPlanningEntryId(taskId, normalizedDate),
        planDate: normalizedDate,
        taskId,
        action: desiredAction,
        createdAt: nowIso,
        updatedAt: nowIso,
      };

  const nextEntries = existingEntry
    ? normalizedEntries.map((e) =>
        e.taskId === taskId && e.planDate === normalizedDate ? nextEntry : e
      )
    : normalizeDailyPlanningEntriesList([...normalizedEntries, nextEntry]);

  const shouldPointMyDay =
    !targetTask.myDayDate ||
    normalizedDate >= targetTask.myDayDate ||
    normalizedDate === today;

  const nextTasks = tasks.map((t) =>
    t.id === taskId
      ? {
          ...t,
          isMyDay: shouldPointMyDay ? true : t.isMyDay,
          myDayDate: shouldPointMyDay ? normalizedDate : t.myDayDate,
          sortOrder: assignedSortOrder,
          updatedAt: nowIso,
        }
      : t
  );

  return { tasks: nextTasks, entries: nextEntries, entry: nextEntry };
}

export function removeTaskFromPlannedDay(
  tasks: readonly DaywellTaskRecord[],
  entries: readonly SharedDailyPlanningEntry[],
  taskId: string,
  planDateIso: string,
  options?: {
    todayIso?: string;
    nowUtc?: Date;
  }
): {
  tasks: DaywellTaskRecord[];
  entries: SharedDailyPlanningEntry[];
} {
  const parsedDate = CalendarDate.tryParse(planDateIso);
  if (!parsedDate) {
    return { tasks: [...tasks], entries: [...entries] };
  }
  const normalizedDate = parsedDate.toIsoString();
  const today = options?.todayIso ?? CalendarDate.today().toIsoString();
  const nowIso = (options?.nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const normalizedEntries = normalizeDailyPlanningEntriesList(entries);

  const existingEntry = findDailyPlanningEntry(
    normalizedEntries,
    taskId,
    normalizedDate
  );

  const nextEntries: SharedDailyPlanningEntry[] = existingEntry
    ? normalizedEntries.map((e) =>
        e.taskId === taskId && e.planDate === normalizedDate
          ? { ...e, action: 'dismissed', updatedAt: nowIso }
          : e
      )
    : [
        ...normalizedEntries,
        {
          id: buildDailyPlanningEntryId(taskId, normalizedDate),
          planDate: normalizedDate,
          taskId,
          action: 'dismissed',
          createdAt: nowIso,
          updatedAt: nowIso,
        },
      ];

  const remainingFutureOrTodayDates = nextEntries
    .filter(
      (e) =>
        e.taskId === taskId &&
        e.action !== 'dismissed' &&
        e.planDate >= today
    )
    .map((e) => e.planDate)
    .sort();

  const nextTasks = tasks.map((t) => {
    if (t.id !== taskId) return t;
    const touchesTaskMyDay =
      t.isMyDay &&
      (t.myDayDate === normalizedDate ||
        (!t.myDayDate && normalizedDate === today));
    if (!touchesTaskMyDay) return t;

    const fallbackDate =
      remainingFutureOrTodayDates.length > 0
        ? remainingFutureOrTodayDates[remainingFutureOrTodayDates.length - 1]
        : undefined;

    return {
      ...t,
      isMyDay: fallbackDate !== undefined,
      myDayDate: fallbackDate,
      updatedAt: nowIso,
    };
  });

  return {
    tasks: nextTasks,
    entries: normalizeDailyPlanningEntriesList(nextEntries),
  };
}

export function reorderPlannedTasks(
  tasks: readonly DaywellTaskRecord[],
  orderedTaskIds: readonly string[],
  nowUtc?: Date
): DaywellTaskRecord[] {
  if (orderedTaskIds.length === 0) return [...tasks];
  const nowIso = (nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const orderById = new Map<string, number>();
  orderedTaskIds.forEach((id, index) => {
    if (!orderById.has(id)) {
      orderById.set(id, index);
    }
  });

  return tasks.map((t) => {
    const nextOrder = orderById.get(t.id);
    if (nextOrder === undefined || t.sortOrder === nextOrder) {
      return t;
    }
    return {
      ...t,
      sortOrder: nextOrder,
      updatedAt: nowIso,
    };
  });
}

export function movePlannedTaskOrder(
  tasks: readonly DaywellTaskRecord[],
  entries: readonly SharedDailyPlanningEntry[],
  planDateIso: string,
  taskId: string,
  direction: 'up' | 'down',
  options?: {
    todayIso?: string;
    nowUtc?: Date;
  }
): DaywellTaskRecord[] {
  const snapshot = buildDailyPlanSnapshot(
    tasks,
    entries,
    planDateIso,
    options?.todayIso
  );
  const currentIds = snapshot.remainingItems.map((item) => item.task.id);
  const idx = currentIds.indexOf(taskId);
  if (idx === -1) return [...tasks];
  const targetIdx = direction === 'up' ? idx - 1 : idx + 1;
  if (targetIdx < 0 || targetIdx >= currentIds.length) return [...tasks];
  const reordered = [...currentIds];
  const [moved] = reordered.splice(idx, 1);
  reordered.splice(targetIdx, 0, moved);
  return reorderPlannedTasks(tasks, reordered, options?.nowUtc);
}

export function syncTaskCompletionWithDailyPlanning(
  tasks: readonly DaywellTaskRecord[],
  entries: readonly SharedDailyPlanningEntry[],
  taskId: string,
  completed: boolean,
  options?: {
    preferredPlanDateIso?: string;
    todayIso?: string;
    nowUtc?: Date;
  }
): SharedDailyPlanningEntry[] {
  const targetTask = tasks.find((t) => t.id === taskId);
  if (!targetTask) return [...entries];

  const today = options?.todayIso ?? CalendarDate.today().toIsoString();
  const nowIso = (options?.nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const normalizedEntries = normalizeDailyPlanningEntriesList(entries);

  let targetPlanDate: string | undefined;
  const preferred = options?.preferredPlanDateIso
    ? CalendarDate.tryParse(options.preferredPlanDateIso)?.toIsoString()
    : undefined;

  if (
    preferred &&
    isTaskPlannedForDate(targetTask, normalizedEntries, preferred, today)
  ) {
    targetPlanDate = preferred;
  } else if (
    isTaskPlannedForDate(targetTask, normalizedEntries, today, today)
  ) {
    targetPlanDate = today;
  } else if (
    targetTask.myDayDate &&
    isTaskPlannedForDate(
      targetTask,
      normalizedEntries,
      targetTask.myDayDate,
      today
    )
  ) {
    targetPlanDate = targetTask.myDayDate;
  } else {
    const activeEntriesForTask = normalizedEntries
      .filter((e) => e.taskId === taskId && e.action !== 'dismissed')
      .map((e) => e.planDate)
      .sort();
    if (activeEntriesForTask.length > 0) {
      targetPlanDate = activeEntriesForTask[activeEntriesForTask.length - 1];
    }
  }

  if (!targetPlanDate) {
    return normalizedEntries;
  }

  const existing = findDailyPlanningEntry(
    normalizedEntries,
    taskId,
    targetPlanDate
  );

  const nextAction: SharedDailyPlanningAction = completed
    ? 'completed'
    : nextActionOnReopen(normalizedEntries, taskId, targetPlanDate);

  const nextEntry: SharedDailyPlanningEntry = existing
    ? {
        ...existing,
        action: nextAction,
        updatedAt: nowIso,
      }
    : {
        id: buildDailyPlanningEntryId(taskId, targetPlanDate),
        planDate: targetPlanDate,
        taskId,
        action: nextAction,
        createdAt: nowIso,
        updatedAt: nowIso,
      };

  const nextEntries = existing
    ? normalizedEntries.map((e) =>
        e.taskId === taskId && e.planDate === targetPlanDate ? nextEntry : e
      )
    : [...normalizedEntries, nextEntry];

  return normalizeDailyPlanningEntriesList(nextEntries);
}

export function carryForwardUnfinishedTasks(
  tasks: readonly DaywellTaskRecord[],
  entries: readonly SharedDailyPlanningEntry[],
  options: {
    toDateIso: string;
    fromDateIso?: string;
    taskIds?: readonly string[];
    todayIso?: string;
    nowUtc?: Date;
  }
): {
  tasks: DaywellTaskRecord[];
  entries: SharedDailyPlanningEntry[];
  carriedCount: number;
  carriedTaskIds: string[];
} {
  const parsedTo = CalendarDate.tryParse(options.toDateIso);
  if (!parsedTo) {
    return {
      tasks: [...tasks],
      entries: [...entries],
      carriedCount: 0,
      carriedTaskIds: [],
    };
  }
  const toDate = parsedTo.toIsoString();
  const today = options.todayIso ?? CalendarDate.today().toIsoString();
  const fromDate = options.fromDateIso
    ? CalendarDate.tryParse(options.fromDateIso)?.toIsoString()
    : undefined;

  let currentTasks = [...tasks];
  let currentEntries = normalizeDailyPlanningEntriesList(entries);

  const candidateIds = new Set<string>();
  if (options.taskIds && options.taskIds.length > 0) {
    for (const id of options.taskIds) {
      if (id.trim()) candidateIds.add(id.trim());
    }
  } else if (fromDate) {
    for (const t of currentTasks) {
      if (isTaskPlannedForDate(t, currentEntries, fromDate, today)) {
        candidateIds.add(t.id);
      }
    }
  } else {
    for (const entry of currentEntries) {
      if (entry.planDate < toDate && entry.action !== 'dismissed') {
        candidateIds.add(entry.taskId);
      }
    }
    for (const t of currentTasks) {
      if (t.isMyDay && t.myDayDate && t.myDayDate < toDate) {
        candidateIds.add(t.id);
      }
    }
  }

  const carriedTaskIds: string[] = [];
  for (const taskId of candidateIds) {
    const task = currentTasks.find((t) => t.id === taskId);
    if (!task || task.isArchived) continue;
    const status = resolveEffectiveTaskStatus(task);
    if (status === 'completed' || status === 'cancelled') continue;
    if (isTaskPlannedForDate(task, currentEntries, toDate, today)) {
      continue;
    }

    const planned = planTaskForDate(
      currentTasks,
      currentEntries,
      taskId,
      toDate,
      {
        action: 'carried_forward',
        todayIso: today,
        nowUtc: options.nowUtc,
      }
    );
    currentTasks = planned.tasks;
    currentEntries = planned.entries;
    carriedTaskIds.push(taskId);
  }

  return {
    tasks: currentTasks,
    entries: currentEntries,
    carriedCount: carriedTaskIds.length,
    carriedTaskIds,
  };
}

export function extractDailyPlanningHistoryDates(
  tasks: readonly DaywellTaskRecord[],
  entries: readonly SharedDailyPlanningEntry[],
  todayIso?: string
): string[] {
  const today = todayIso ?? CalendarDate.today().toIsoString();
  const dates = new Set<string>();
  for (const e of entries) {
    if (e.action !== 'dismissed') {
      dates.add(e.planDate);
    }
  }
  for (const t of tasks) {
    if (t.isMyDay && !t.isArchived) {
      dates.add(t.myDayDate || today);
    }
  }
  return Array.from(dates).sort((a, b) => b.localeCompare(a));
}

export function buildDailyPlanSnapshot(
  tasks: readonly DaywellTaskRecord[],
  entries: readonly SharedDailyPlanningEntry[],
  selectedDateIso: string,
  todayIso?: string
): DailyPlanSnapshot {
  const today = todayIso ?? CalendarDate.today().toIsoString();
  const selectedDate =
    CalendarDate.tryParse(selectedDateIso)?.toIsoString() ?? today;
  const normalizedEntries = normalizeDailyPlanningEntriesList(entries);

  const items: DailyPlanItem[] = [];
  const plannedTaskIds = new Set<string>();
  let dismissedCount = 0;

  for (const task of tasks) {
    if (task.isArchived) continue;
    const entry = findDailyPlanningEntry(
      normalizedEntries,
      task.id,
      selectedDate
    );
    if (entry && entry.action === 'dismissed') {
      dismissedCount += 1;
      continue;
    }
    const isPlanned = isTaskPlannedForDate(
      task,
      normalizedEntries,
      selectedDate,
      today
    );
    if (!isPlanned) continue;

    plannedTaskIds.add(task.id);
    const taskCompleted = isTaskCompleted(task);
    const completedForDay = entry
      ? entry.action === 'completed' || (selectedDate >= today && taskCompleted)
      : taskCompleted;
    const completedLater = Boolean(
      entry &&
        entry.action !== 'completed' &&
        selectedDate < today &&
        taskCompleted
    );
    const action: SharedDailyPlanningAction = completedForDay
      ? 'completed'
      : entry?.action ?? 'planned';

    items.push({
      task,
      entry,
      planDate: selectedDate,
      action,
      isCompletedForDay: completedForDay,
      completedLater,
      isCarriedForward: action === 'carried_forward',
    });
  }

  items.sort(sortDailyPlanItems);

  const remainingItems = items.filter((item) => !item.isCompletedForDay);
  const completedItems = items.filter((item) => item.isCompletedForDay);
  const totalPlannedCount = items.length;
  const completedCount = completedItems.length;
  const remainingCount = remainingItems.length;
  const progressPercentage =
    totalPlannedCount === 0
      ? 0
      : Math.round((completedCount / totalPlannedCount) * 100);

  // Suggestions from prior unfinished planned days, overdue deadlines, and day's scheduled/due tasks.
  const latestPriorPlanByTask = new Map<string, string>();
  for (const e of normalizedEntries) {
    if (e.planDate < selectedDate && e.action !== 'dismissed') {
      const existing = latestPriorPlanByTask.get(e.taskId);
      if (!existing || e.planDate > existing) {
        latestPriorPlanByTask.set(e.taskId, e.planDate);
      }
    }
  }
  for (const t of tasks) {
    if (t.isMyDay && t.myDayDate && t.myDayDate < selectedDate) {
      const existing = latestPriorPlanByTask.get(t.id);
      if (!existing || t.myDayDate > existing) {
        latestPriorPlanByTask.set(t.id, t.myDayDate);
      }
    }
  }

  const carryForwardSuggestions: DailyPlanSuggestion[] = [];
  const overdueSuggestions: DailyPlanSuggestion[] = [];
  const scheduledSuggestions: DailyPlanSuggestion[] = [];
  const otherActiveTasks: DaywellTaskRecord[] = [];

  for (const task of tasks) {
    if (task.isArchived || plannedTaskIds.has(task.id)) continue;
    const status = resolveEffectiveTaskStatus(task);
    if (status === 'completed' || status === 'cancelled') continue;

    const priorDate = latestPriorPlanByTask.get(task.id);
    if (priorDate) {
      carryForwardSuggestions.push({
        task,
        reason: 'carry_forward',
        sourcePlanDate: priorDate,
      });
    }

    const isOverdue = Boolean(task.dueDate && task.dueDate < today);
    const isScheduledForSelected =
      task.dueDate === selectedDate || task.scheduledDate === selectedDate;

    if (isOverdue) {
      overdueSuggestions.push({ task, reason: 'overdue' });
    } else if (isScheduledForSelected) {
      scheduledSuggestions.push({ task, reason: 'scheduled' });
    } else if (!priorDate) {
      otherActiveTasks.push(task);
    }
  }

  const byTaskPriorityAndTitle = (
    a: { task: DaywellTaskRecord },
    b: { task: DaywellTaskRecord }
  ) => sortDailyPlanItems(a, b);

  carryForwardSuggestions.sort(byTaskPriorityAndTitle);
  overdueSuggestions.sort(byTaskPriorityAndTitle);
  scheduledSuggestions.sort(byTaskPriorityAndTitle);
  otherActiveTasks.sort((a, b) => sortDailyPlanItems({ task: a }, { task: b }));

  return {
    selectedDate,
    todayDate: today,
    isToday: selectedDate === today,
    isPastDay: selectedDate < today,
    isFutureDay: selectedDate > today,
    items,
    remainingItems,
    completedItems,
    dismissedCount,
    totalPlannedCount,
    completedCount,
    remainingCount,
    progressPercentage,
    carryForwardSuggestions,
    overdueSuggestions,
    scheduledSuggestions,
    otherActiveTasks,
    historyDates: extractDailyPlanningHistoryDates(
      tasks,
      normalizedEntries,
      today
    ),
  };
}
