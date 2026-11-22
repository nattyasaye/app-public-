import { CalendarDate, EthiopiaClock } from './date';
import { validateTaskForm } from './formValidationAndNavigation';
import {
  SharedTaskRecurrenceConfig,
  SharedTaskStatus,
} from './sharedFoundation';

export type TaskPriority = 'urgent' | 'high' | 'medium' | 'low';
export type TaskStatus = SharedTaskStatus;
export type TaskViewFilter =
  | 'today'
  | 'inbox'
  | 'upcoming'
  | 'all'
  | 'completed'
  | 'archived';
export type TaskSortBy = 'priority' | 'time' | 'title';

export const CANONICAL_TASK_STATUSES: readonly TaskStatus[] = [
  'inbox',
  'not_started',
  'in_progress',
  'completed',
  'cancelled',
] as const;

export const CANONICAL_TASK_PRIORITIES: readonly TaskPriority[] = [
  'urgent',
  'high',
  'medium',
  'low',
] as const;

export const TASK_STATUS_LABELS: Record<TaskStatus, string> = {
  inbox: 'Inbox',
  not_started: 'Not Started',
  in_progress: 'In Progress',
  completed: 'Completed',
  cancelled: 'Cancelled',
};

export const TASK_PRIORITY_LABELS: Record<TaskPriority, string> = {
  urgent: 'Urgent',
  high: 'High',
  medium: 'Medium',
  low: 'Low',
};

export interface TaskSubItemRecord {
  id: string;
  title: string;
  completed: boolean;
}

export interface DaywellTaskRecord {
  id: string;
  title: string;
  description?: string;
  category?: string;
  status?: TaskStatus;
  priority: TaskPriority;
  completed: boolean;
  completedAt?: string;
  dueDate?: string; // YYYY-MM-DD (Hard deadline)
  scheduledDate?: string; // YYYY-MM-DD (Planned date)
  scheduledTime?: string; // HH:MM
  hasReminder: boolean;
  isRecurring?: boolean;
  recurringRule?: 'daily' | 'weekly' | 'monthly';
  recurrenceRule?: string;
  recurrenceConfig?: SharedTaskRecurrenceConfig;
  subtasks: TaskSubItemRecord[];
  labels?: string[];
  isPinned?: boolean;
  isMyDay?: boolean;
  myDayDate?: string;
  isArchived?: boolean;
  sortOrder?: number;
  projectId?: string;
  milestoneId?: string;
  estimatedDurationMinutes?: number;
  projectName?: string;
  createdAt: string;
  updatedAt?: string;
}

export interface CreateTaskInput {
  id?: string;
  title: string;
  description?: string;
  priority?: TaskPriority;
  status?: TaskStatus;
  dueDate?: string;
  scheduledDate?: string;
  scheduledTime?: string;
  projectId?: string;
  milestoneId?: string;
  projectName?: string;
  category?: string;
  hasReminder?: boolean;
  isRecurring?: boolean;
  recurringRule?: 'daily' | 'weekly' | 'monthly';
  recurrenceRule?: string;
  subtasks?: TaskSubItemRecord[];
}

export interface UpdateTaskPatch {
  title?: string;
  description?: string;
  priority?: TaskPriority;
  status?: TaskStatus;
  dueDate?: string;
  scheduledDate?: string;
  scheduledTime?: string;
  projectId?: string;
  milestoneId?: string;
  projectName?: string;
  category?: string;
  hasReminder?: boolean;
  isRecurring?: boolean;
  recurringRule?: 'daily' | 'weekly' | 'monthly';
  recurrenceRule?: string;
  subtasks?: TaskSubItemRecord[];
}

export type TaskMutationResult =
  | { ok: true; task: DaywellTaskRecord }
  | { ok: false; errors: Record<string, string> };

export function normalizeTaskStatus(
  status?: string,
  fallbackCompleted = false
): TaskStatus {
  if (status && (CANONICAL_TASK_STATUSES as readonly string[]).includes(status)) {
    return status as TaskStatus;
  }
  return fallbackCompleted ? 'completed' : 'not_started';
}

export function normalizeTaskPriority(priority?: string): TaskPriority {
  if (
    priority &&
    (CANONICAL_TASK_PRIORITIES as readonly string[]).includes(priority)
  ) {
    return priority as TaskPriority;
  }
  return 'medium';
}

export function resolveEffectiveTaskStatus(
  task: Pick<DaywellTaskRecord, 'status' | 'completed'>
): TaskStatus {
  if (task.completed) {
    return 'completed';
  }
  if (
    task.status &&
    task.status !== 'completed' &&
    (CANONICAL_TASK_STATUSES as readonly string[]).includes(task.status)
  ) {
    return task.status;
  }
  return 'not_started';
}

export function isTaskCompleted(
  task: Pick<DaywellTaskRecord, 'status' | 'completed'>
): boolean {
  return resolveEffectiveTaskStatus(task) === 'completed';
}

export interface SubtaskProgressSummary {
  total: number;
  completed: number;
  ratio: number;
  percentage: number;
}

export type SubtaskListMutationResult =
  | { ok: true; subtasks: TaskSubItemRecord[]; affected?: TaskSubItemRecord }
  | { ok: false; error: string };

export type TaskSubtaskMutationResult =
  | { ok: true; task: DaywellTaskRecord; affected?: TaskSubItemRecord }
  | { ok: false; error: string };

export function computeSubtaskProgress(
  subtasks?: readonly Pick<TaskSubItemRecord, 'completed'>[] | null
): SubtaskProgressSummary {
  if (!Array.isArray(subtasks) || subtasks.length === 0) {
    return { total: 0, completed: 0, ratio: 0, percentage: 0 };
  }
  const total = subtasks.length;
  const completed = subtasks.filter((st) => Boolean(st?.completed)).length;
  const ratio = completed / total;
  return {
    total,
    completed,
    ratio,
    percentage: Math.round(ratio * 100),
  };
}

export function generateNextSubtaskId(
  taskId: string,
  existingSubtasks: readonly Pick<TaskSubItemRecord, 'id'>[]
): string {
  const prefix = (taskId || 'st').trim() || 'st';
  const usedIds = new Set(existingSubtasks.map((s) => s.id));
  let counter = existingSubtasks.length + 1;
  while (usedIds.has(`${prefix}-sub-${counter}`)) {
    counter += 1;
  }
  return `${prefix}-sub-${counter}`;
}

export function normalizeSubtasksList(
  subtasks: readonly (Partial<TaskSubItemRecord> & { done?: boolean })[] | undefined,
  taskId = 'st'
): TaskSubItemRecord[] {
  if (!Array.isArray(subtasks)) return [];
  const normalized: TaskSubItemRecord[] = [];
  const seenIds = new Set<string>();
  for (let i = 0; i < subtasks.length; i++) {
    const raw = subtasks[i];
    if (!raw || typeof raw !== 'object') continue;
    const title = typeof raw.title === 'string' ? raw.title.trim() : '';
    if (!title) continue;
    let id = typeof raw.id === 'string' && raw.id.trim() ? raw.id.trim() : '';
    if (!id || seenIds.has(id)) {
      id = generateNextSubtaskId(taskId, normalized);
    }
    seenIds.add(id);
    normalized.push({
      id,
      title,
      completed: Boolean(raw.done ?? raw.completed),
    });
  }
  return normalized;
}

export function addSubtaskToList(
  subtasks: readonly TaskSubItemRecord[],
  title: string,
  taskId = 'st'
): SubtaskListMutationResult {
  const trimmed = title.trim();
  if (!trimmed) {
    return { ok: false, error: 'Subtask title is required' };
  }
  const added: TaskSubItemRecord = {
    id: generateNextSubtaskId(taskId, subtasks),
    title: trimmed,
    completed: false,
  };
  return {
    ok: true,
    subtasks: [...subtasks, added],
    affected: added,
  };
}

export function updateSubtaskTitleInList(
  subtasks: readonly TaskSubItemRecord[],
  subtaskId: string,
  title: string
): SubtaskListMutationResult {
  const trimmed = title.trim();
  if (!trimmed) {
    return { ok: false, error: 'Subtask title is required' };
  }
  let affected: TaskSubItemRecord | undefined;
  const next = subtasks.map((st) => {
    if (st.id === subtaskId) {
      affected = { ...st, title: trimmed };
      return affected;
    }
    return st;
  });
  return { ok: true, subtasks: next, affected };
}

export function toggleSubtaskInList(
  subtasks: readonly TaskSubItemRecord[],
  subtaskId: string,
  completedOverride?: boolean
): TaskSubItemRecord[] {
  return subtasks.map((st) =>
    st.id === subtaskId
      ? {
          ...st,
          completed:
            completedOverride !== undefined ? completedOverride : !st.completed,
        }
      : st
  );
}

export function deleteSubtaskFromList(
  subtasks: readonly TaskSubItemRecord[],
  subtaskId: string
): { remaining: TaskSubItemRecord[]; deleted?: TaskSubItemRecord } {
  const deleted = subtasks.find((st) => st.id === subtaskId);
  const remaining = subtasks.filter((st) => st.id !== subtaskId);
  return { remaining, deleted };
}

export function reorderSubtasksInList(
  subtasks: readonly TaskSubItemRecord[],
  fromIndex: number,
  toIndex: number
): TaskSubItemRecord[] {
  if (
    fromIndex < 0 ||
    fromIndex >= subtasks.length ||
    toIndex < 0 ||
    toIndex >= subtasks.length ||
    fromIndex === toIndex
  ) {
    return [...subtasks];
  }
  const next = [...subtasks];
  const [moved] = next.splice(fromIndex, 1);
  next.splice(toIndex, 0, moved);
  return next;
}

export function addSubtaskToTask(
  task: DaywellTaskRecord,
  title: string,
  nowUtc?: Date
): TaskSubtaskMutationResult {
  const res = addSubtaskToList(task.subtasks, title, task.id);
  if (!res.ok) return res;
  return {
    ok: true,
    affected: res.affected,
    task: {
      ...task,
      subtasks: res.subtasks,
      updatedAt: (nowUtc ?? EthiopiaClock.nowUtc()).toISOString(),
    },
  };
}

export function updateTaskSubtaskTitle(
  task: DaywellTaskRecord,
  subtaskId: string,
  title: string,
  nowUtc?: Date
): TaskSubtaskMutationResult {
  const res = updateSubtaskTitleInList(task.subtasks, subtaskId, title);
  if (!res.ok) return res;
  return {
    ok: true,
    affected: res.affected,
    task: {
      ...task,
      subtasks: res.subtasks,
      updatedAt: (nowUtc ?? EthiopiaClock.nowUtc()).toISOString(),
    },
  };
}

export function toggleTaskSubtask(
  task: DaywellTaskRecord,
  subtaskId: string,
  nowUtc?: Date
): DaywellTaskRecord {
  return {
    ...task,
    subtasks: toggleSubtaskInList(task.subtasks, subtaskId),
    updatedAt: (nowUtc ?? EthiopiaClock.nowUtc()).toISOString(),
  };
}

export function deleteSubtaskFromTask(
  task: DaywellTaskRecord,
  subtaskId: string,
  nowUtc?: Date
): { task: DaywellTaskRecord; deleted?: TaskSubItemRecord } {
  const { remaining, deleted } = deleteSubtaskFromList(task.subtasks, subtaskId);
  return {
    deleted,
    task: {
      ...task,
      subtasks: remaining,
      updatedAt: (nowUtc ?? EthiopiaClock.nowUtc()).toISOString(),
    },
  };
}

export function reorderTaskSubtasks(
  task: DaywellTaskRecord,
  fromIndex: number,
  toIndex: number,
  nowUtc?: Date
): DaywellTaskRecord {
  return {
    ...task,
    subtasks: reorderSubtasksInList(task.subtasks, fromIndex, toIndex),
    updatedAt: (nowUtc ?? EthiopiaClock.nowUtc()).toISOString(),
  };
}

export function createTaskRecord(
  input: CreateTaskInput,
  nowUtc?: Date
): TaskMutationResult {
  const dueDate = input.dueDate?.trim() || undefined;
  const scheduledDate = input.scheduledDate?.trim() || undefined;
  const scheduledTime = input.scheduledTime?.trim() || undefined;
  const description = input.description?.trim() || undefined;

  const validation = validateTaskForm({
    title: input.title,
    description,
    dueDate,
    scheduledDate,
    scheduledTime,
  });

  if (!validation.isValid) {
    return { ok: false, errors: validation.errors };
  }

  const now = nowUtc ?? EthiopiaClock.nowUtc();
  const nowIso = now.toISOString();
  const id =
    input.id?.trim() || `t-${now.getTime()}-${Math.floor(Math.random() * 10000)}`;
  const status = normalizeTaskStatus(input.status, false);
  const completed = status === 'completed';
  const priority = normalizeTaskPriority(input.priority);
  const projectId = input.projectId?.trim() || undefined;
  const milestoneId = projectId ? (input.milestoneId?.trim() || undefined) : undefined;
  const projectName = input.projectName?.trim() || undefined;
  const isRecurring = Boolean(input.isRecurring);

  const task: DaywellTaskRecord = {
    id,
    title: input.title.trim(),
    description,
    category: input.category?.trim() || projectName,
    status,
    priority,
    completed,
    completedAt: completed ? nowIso : undefined,
    dueDate,
    scheduledDate,
    scheduledTime,
    projectId,
    milestoneId,
    projectName,
    hasReminder: Boolean(input.hasReminder),
    isRecurring,
    recurringRule: isRecurring ? input.recurringRule : undefined,
    ...(isRecurring && (input.recurrenceRule || input.recurringRule)
      ? { recurrenceRule: input.recurrenceRule || input.recurringRule }
      : {}),
    subtasks: normalizeSubtasksList(input.subtasks, id),
    isArchived: false,
    sortOrder: 0,
    createdAt: nowIso,
    updatedAt: nowIso,
  };

  return { ok: true, task };
}

export function updateTaskRecord(
  existing: DaywellTaskRecord,
  patch: UpdateTaskPatch,
  nowUtc?: Date
): TaskMutationResult {
  const hasOwn = (key: keyof UpdateTaskPatch) =>
    Object.prototype.hasOwnProperty.call(patch, key);

  const nextTitle = hasOwn('title') ? (patch.title ?? '') : existing.title;
  const nextDescription = hasOwn('description')
    ? patch.description?.trim() || undefined
    : existing.description;
  const nextDueDate = hasOwn('dueDate')
    ? patch.dueDate?.trim() || undefined
    : existing.dueDate;
  const nextScheduledDate = hasOwn('scheduledDate')
    ? patch.scheduledDate?.trim() || undefined
    : existing.scheduledDate;
  const nextScheduledTime = hasOwn('scheduledTime')
    ? patch.scheduledTime?.trim() || undefined
    : existing.scheduledTime;

  const validation = validateTaskForm({
    title: nextTitle,
    description: nextDescription,
    dueDate: nextDueDate,
    scheduledDate: nextScheduledDate,
    scheduledTime: nextScheduledTime,
  });

  if (!validation.isValid) {
    return { ok: false, errors: validation.errors };
  }

  const nowIso = (nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  const nextStatus = hasOwn('status')
    ? normalizeTaskStatus(patch.status, false)
    : resolveEffectiveTaskStatus(existing);
  const nextCompleted = nextStatus === 'completed';
  const nextCompletedAt = nextCompleted
    ? existing.completedAt ?? nowIso
    : undefined;
  const nextPriority = hasOwn('priority')
    ? normalizeTaskPriority(patch.priority)
    : existing.priority;
  const nextProjectId = hasOwn('projectId')
    ? patch.projectId?.trim() || undefined
    : existing.projectId;
  const nextMilestoneId = hasOwn('milestoneId')
    ? !nextProjectId
      ? undefined
      : patch.milestoneId?.trim() || undefined
    : hasOwn('projectId') && nextProjectId !== existing.projectId
      ? undefined
      : existing.milestoneId;
  const nextProjectName = hasOwn('projectName')
    ? patch.projectName?.trim() || undefined
    : existing.projectName;
  const nextIsRecurring = hasOwn('isRecurring')
    ? Boolean(patch.isRecurring)
    : existing.isRecurring;
  const nextRecurringRule = nextIsRecurring
    ? hasOwn('recurringRule')
      ? patch.recurringRule
      : existing.recurringRule
    : undefined;
  const nextRecurrenceRule = nextIsRecurring
    ? hasOwn('recurrenceRule')
      ? patch.recurrenceRule
      : existing.recurrenceRule ?? nextRecurringRule
    : existing.recurringRule
      ? undefined
      : existing.recurrenceRule;

  const updated: DaywellTaskRecord = {
    ...existing,
    title: nextTitle.trim(),
    description: nextDescription,
    status: nextStatus,
    completed: nextCompleted,
    completedAt: nextCompletedAt,
    priority: nextPriority,
    dueDate: nextDueDate,
    scheduledDate: nextScheduledDate,
    scheduledTime: nextScheduledTime,
    projectId: nextProjectId,
    milestoneId: nextMilestoneId,
    projectName: nextProjectName,
    category: hasOwn('category') ? patch.category?.trim() || undefined : existing.category,
    hasReminder: hasOwn('hasReminder')
      ? Boolean(patch.hasReminder)
      : existing.hasReminder,
    isRecurring: nextIsRecurring,
    recurringRule: nextRecurringRule,
    recurrenceRule: nextRecurrenceRule,
    subtasks:
      hasOwn('subtasks') && patch.subtasks
        ? normalizeSubtasksList(patch.subtasks, existing.id)
        : existing.subtasks,
    updatedAt: nowIso,
  };

  return { ok: true, task: updated };
}

export function toggleTaskCompletionRecord(
  task: DaywellTaskRecord,
  nowUtc?: Date
): DaywellTaskRecord {
  const nextCompleted = !isTaskCompleted(task);
  const nowIso = (nowUtc ?? EthiopiaClock.nowUtc()).toISOString();

  return {
    ...task,
    completed: nextCompleted,
    status: nextCompleted ? 'completed' : 'not_started',
    completedAt: nextCompleted ? nowIso : undefined,
    updatedAt: nowIso,
  };
}

export function setTaskArchivedRecord(
  task: DaywellTaskRecord,
  archived: boolean,
  nowUtc?: Date
): DaywellTaskRecord {
  const nowIso = (nowUtc ?? EthiopiaClock.nowUtc()).toISOString();
  return {
    ...task,
    isArchived: archived,
    updatedAt: nowIso,
  };
}

export function deleteTaskFromList<T extends { id: string }>(
  tasks: readonly T[],
  taskId: string
): { remaining: T[]; deleted?: T } {
  const deleted = tasks.find((t) => t.id === taskId);
  const remaining = tasks.filter((t) => t.id !== taskId);
  return { remaining, deleted };
}

function isTaskInTodayView(
  task: DaywellTaskRecord,
  todayIso: string
): boolean {
  if (task.isArchived) return false;
  const status = resolveEffectiveTaskStatus(task);
  if (status === 'completed' || status === 'cancelled') return false;
  const dueTodayOrOverdue = Boolean(task.dueDate && task.dueDate <= todayIso);
  const scheduledTodayOrOverdue = Boolean(
    task.scheduledDate && task.scheduledDate <= todayIso
  );
  return dueTodayOrOverdue || scheduledTodayOrOverdue;
}

function isTaskInInboxView(task: DaywellTaskRecord): boolean {
  if (task.isArchived) return false;
  const status = resolveEffectiveTaskStatus(task);
  if (status === 'completed' || status === 'cancelled') return false;
  if (status === 'inbox') return true;
  return !task.dueDate && !task.scheduledDate && !task.projectId;
}

function isTaskInUpcomingView(
  task: DaywellTaskRecord,
  todayIso: string
): boolean {
  if (task.isArchived) return false;
  const status = resolveEffectiveTaskStatus(task);
  if (status === 'completed' || status === 'cancelled') return false;
  const dueLater = Boolean(task.dueDate && task.dueDate > todayIso);
  const scheduledLater = Boolean(
    task.scheduledDate && task.scheduledDate > todayIso
  );
  return dueLater || scheduledLater;
}

export interface TaskTabCounts {
  todayCount: number;
  inboxCount: number;
  upcomingCount: number;
  allCount: number;
  completedCount: number;
  archivedCount: number;
  activePendingCount: number;
}

export function computeTaskTabCounts(
  tasks: readonly DaywellTaskRecord[],
  todayIso?: string
): TaskTabCounts {
  const today = todayIso ?? CalendarDate.today().toIsoString();
  let todayCount = 0;
  let inboxCount = 0;
  let upcomingCount = 0;
  let allCount = 0;
  let completedCount = 0;
  let archivedCount = 0;
  let activePendingCount = 0;

  for (const t of tasks) {
    if (t.isArchived) {
      archivedCount += 1;
      continue;
    }
    allCount += 1;
    const status = resolveEffectiveTaskStatus(t);
    if (status === 'completed') {
      completedCount += 1;
      continue;
    }
    if (status !== 'cancelled') {
      activePendingCount += 1;
    }
    if (isTaskInTodayView(t, today)) todayCount += 1;
    if (isTaskInInboxView(t)) inboxCount += 1;
    if (isTaskInUpcomingView(t, today)) upcomingCount += 1;
  }

  return {
    todayCount,
    inboxCount,
    upcomingCount,
    allCount,
    completedCount,
    archivedCount,
    activePendingCount,
  };
}

export function filterTasksForView(
  tasks: readonly DaywellTaskRecord[],
  options: {
    viewFilter: TaskViewFilter;
    searchQuery?: string;
    sortBy?: TaskSortBy;
    todayIso?: string;
  }
): DaywellTaskRecord[] {
  const today = options.todayIso ?? CalendarDate.today().toIsoString();
  const sortBy = options.sortBy ?? 'priority';
  const query = options.searchQuery?.trim().toLowerCase() ?? '';

  let list = tasks.filter((t) => {
    if (options.viewFilter === 'archived') {
      return Boolean(t.isArchived);
    }
    if (t.isArchived) return false;

    switch (options.viewFilter) {
      case 'today':
        return isTaskInTodayView(t, today);
      case 'inbox':
        return isTaskInInboxView(t);
      case 'upcoming':
        return isTaskInUpcomingView(t, today);
      case 'completed':
        return isTaskCompleted(t);
      case 'all':
      default:
        return true;
    }
  });

  if (query.length > 0) {
    list = list.filter((t) => {
      const labelMatch = (t.labels ?? []).some((lbl) =>
        lbl.toLowerCase().includes(query)
      );
      return (
        t.title.toLowerCase().includes(query) ||
        (t.description && t.description.toLowerCase().includes(query)) ||
        (t.projectName && t.projectName.toLowerCase().includes(query)) ||
        (t.category && t.category.toLowerCase().includes(query)) ||
        labelMatch
      );
    });
  }

  const priorityOrder: Record<TaskPriority, number> = {
    urgent: 0,
    high: 1,
    medium: 2,
    low: 3,
  };

  return [...list].sort((a, b) => {
    if (sortBy === 'priority') {
      const pa = priorityOrder[a.priority] ?? 2;
      const pb = priorityOrder[b.priority] ?? 2;
      if (pa !== pb) return pa - pb;
      return a.title.localeCompare(b.title);
    }
    if (sortBy === 'time') {
      const timeA = a.scheduledTime || '23:59';
      const timeB = b.scheduledTime || '23:59';
      if (timeA !== timeB) return timeA.localeCompare(timeB);
      return a.title.localeCompare(b.title);
    }
    return a.title.localeCompare(b.title);
  });
}
