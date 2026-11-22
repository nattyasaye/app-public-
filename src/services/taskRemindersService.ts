import { EthiopiaClock } from '../domain/date';
import { SharedReminder } from '../domain/sharedFoundation';
import { DaywellTaskRecord } from '../domain/taskOperations';
import {
  buildTaskReminderRecord,
  formatTaskReminderSummary,
  isTaskEligibleForActiveReminder,
  reconcileTaskRemindersWithTasks,
} from '../domain/taskReminders';
import { SharedStateBridge } from './sharedStateBridge';

const TASKS_STORAGE_KEY = 'daywell_tasks';
const MAX_JS_TIMEOUT_MS = 2_147_000_000; // ~24.8 days
const OVERDUE_GRACE_WINDOW_MS = 2 * 60 * 1000;

export type WebNotificationPermissionState =
  | 'granted'
  | 'denied'
  | 'default'
  | 'unsupported';

export interface WebNotificationSupportStatus {
  supported: boolean;
  permission: WebNotificationPermissionState;
  backgroundDeliverySupported: false;
  capabilityNote: string;
}

export interface WebTaskReminderAlert {
  reminderId: string;
  taskId: string;
  title: string;
  triggerTimeUtc: string;
  summary: string;
  deliveredViaBrowserNotification: boolean;
}

type TimeoutHandle = ReturnType<typeof setTimeout>;

class TaskRemindersService {
  private scheduledTimers = new Map<string, TimeoutHandle>();
  private scheduledMeta = new Map<string, { triggerMs: number; title: string }>();
  private deliveredKeys = new Set<string>();
  private activeDueListener: ((alert: WebTaskReminderAlert) => void) | undefined;

  private readRemindersRaw(): { exists: boolean; items: SharedReminder[] } {
    try {
      if (typeof localStorage === 'undefined') {
        return { exists: false, items: [] };
      }
      const raw = localStorage.getItem(SharedStateBridge.REMINDERS_STORAGE_KEY);
      if (raw === null) return { exists: false, items: [] };
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) return { exists: true, items: [] };
      return {
        exists: true,
        items: parsed.filter(
          (item): item is SharedReminder =>
            Boolean(item) &&
            typeof item === 'object' &&
            typeof (item as SharedReminder).id === 'string' &&
            typeof (item as SharedReminder).targetId === 'string' &&
            typeof (item as SharedReminder).targetType === 'string' &&
            typeof (item as SharedReminder).triggerTimeUtc === 'string'
        ),
      };
    } catch {
      return { exists: false, items: [] };
    }
  }

  private readTasksRaw(): DaywellTaskRecord[] {
    try {
      if (typeof localStorage === 'undefined') return [];
      const raw = localStorage.getItem(TASKS_STORAGE_KEY);
      if (!raw) return [];
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? (parsed as DaywellTaskRecord[]) : [];
    } catch {
      return [];
    }
  }

  private writeRemindersRaw(
    reminders: SharedReminder[],
    emitSync = true
  ): void {
    try {
      if (typeof localStorage === 'undefined') return;
      if (
        reminders.length === 0 &&
        localStorage.getItem(SharedStateBridge.REMINDERS_STORAGE_KEY) === null
      ) {
        return;
      }
      localStorage.setItem(
        SharedStateBridge.REMINDERS_STORAGE_KEY,
        JSON.stringify(reminders)
      );
      if (emitSync && typeof window !== 'undefined') {
        window.dispatchEvent(new CustomEvent(SharedStateBridge.SYNC_EVENT_NAME));
      }
    } catch {
      // Ignore storage quota errors cleanly
    }
  }

  private writeTasksRaw(tasks: DaywellTaskRecord[]): void {
    try {
      if (typeof localStorage === 'undefined') return;
      localStorage.setItem(TASKS_STORAGE_KEY, JSON.stringify(tasks));
    } catch {
      // Ignore storage quota errors
    }
  }

  public loadAllReminders(): SharedReminder[] {
    return this.readRemindersRaw().items;
  }

  public loadTaskReminders(): SharedReminder[] {
    return this.loadAllReminders().filter((r) => r.targetType === 'task');
  }

  public getReminderForTask(taskId: string): SharedReminder | undefined {
    const matches = this.loadAllReminders().filter(
      (r) => r.targetType === 'task' && r.targetId === taskId
    );
    if (matches.length === 0) return undefined;
    return (
      matches.find((r) => r.isActive) ??
      matches.find((r) => r.id === `rem-task-${taskId}`) ??
      matches[0]
    );
  }

  public saveAllReminders(
    reminders: SharedReminder[],
    options?: { emitSync?: boolean }
  ): void {
    this.writeRemindersRaw(reminders, options?.emitSync ?? true);
  }

  public setTaskReminder(
    task: DaywellTaskRecord,
    triggerTimeUtc: string,
    options?: {
      emitSync?: boolean;
      syncTaskHasReminder?: boolean;
      nowUtc?: Date;
    }
  ): { reminder: SharedReminder; reminders: SharedReminder[] } {
    const existingAll = this.loadAllReminders();
    const existingForTask = existingAll.find(
      (r) => r.targetType === 'task' && r.targetId === task.id
    );
    const built = buildTaskReminderRecord({
      task,
      triggerTimeUtc,
      existingReminder: existingForTask,
      nowUtc: options?.nowUtc,
    });

    const nonTaskOrOther = existingAll.filter(
      (r) => !(r.targetType === 'task' && r.targetId === task.id)
    );
    const nextReminders = [...nonTaskOrOther, built];
    this.writeRemindersRaw(nextReminders, false);

    let tasksForSync = this.readTasksRaw();
    if (options?.syncTaskHasReminder !== false && tasksForSync.length > 0) {
      let changed = false;
      tasksForSync = tasksForSync.map((t) => {
        if (t.id !== task.id) return t;
        if (t.hasReminder === built.isActive) return t;
        changed = true;
        return { ...t, hasReminder: built.isActive };
      });
      if (changed) {
        this.writeTasksRaw(tasksForSync);
      }
    }

    if (options?.emitSync !== false && typeof window !== 'undefined') {
      window.dispatchEvent(new CustomEvent(SharedStateBridge.SYNC_EVENT_NAME));
    }

    this.syncWebTaskNotifications({
      tasks: tasksForSync.length > 0 ? tasksForSync : [task],
      reminders: nextReminders,
      nowUtc: options?.nowUtc,
    });

    return { reminder: built, reminders: nextReminders };
  }

  public removeTaskReminder(
    taskId: string,
    options?: {
      emitSync?: boolean;
      syncTaskHasReminder?: boolean;
      nowUtc?: Date;
    }
  ): SharedReminder[] {
    const existingAll = this.loadAllReminders();
    const removed = existingAll.filter(
      (r) => r.targetType === 'task' && r.targetId === taskId
    );
    for (const r of removed) {
      this.cancelScheduledTimer(r.id);
    }
    this.cancelScheduledTimer(`rem-task-${taskId}`);

    const nextReminders = existingAll.filter(
      (r) => !(r.targetType === 'task' && r.targetId === taskId)
    );
    this.writeRemindersRaw(nextReminders, false);

    let tasksForSync = this.readTasksRaw();
    if (options?.syncTaskHasReminder !== false && tasksForSync.length > 0) {
      let changed = false;
      tasksForSync = tasksForSync.map((t) => {
        if (t.id !== taskId || !t.hasReminder) return t;
        changed = true;
        return { ...t, hasReminder: false };
      });
      if (changed) {
        this.writeTasksRaw(tasksForSync);
      }
    }

    if (options?.emitSync !== false && typeof window !== 'undefined') {
      window.dispatchEvent(new CustomEvent(SharedStateBridge.SYNC_EVENT_NAME));
    }

    return nextReminders;
  }

  public reconcileAndPersistForTasks(options: {
    tasks: DaywellTaskRecord[];
    previousTasks?: readonly DaywellTaskRecord[];
    generatedFromTaskId?: string;
    generatedNextTask?: DaywellTaskRecord;
    pruneOrphans?: boolean;
    shiftCustomOnDateShift?: boolean;
    persistTasks?: boolean;
    emitSync?: boolean;
    nowUtc?: Date;
  }): { reminders: SharedReminder[]; tasks: DaywellTaskRecord[] } {
    const raw = this.readRemindersRaw();
    const hasCarryOverFlag = Boolean(
      options.generatedFromTaskId &&
        options.generatedNextTask &&
        (options.previousTasks?.find((t) => t.id === options.generatedFromTaskId)
          ?.hasReminder ||
          raw.items.some(
            (r) =>
              r.targetType === 'task' &&
              r.targetId === options.generatedFromTaskId
          ))
    );

    if (!raw.exists && !hasCarryOverFlag) {
      const sanitizedTasks = options.tasks.map((t) =>
        t.hasReminder ? { ...t, hasReminder: false } : t
      );
      if (options.persistTasks !== false) {
        this.writeTasksRaw(sanitizedTasks);
      }
      this.syncWebTaskNotifications({
        tasks: sanitizedTasks,
        reminders: [],
        nowUtc: options.nowUtc,
      });
      return { reminders: [], tasks: sanitizedTasks };
    }

    const reconciled = reconcileTaskRemindersWithTasks({
      tasks: options.tasks,
      reminders: raw.items,
      previousTasks: options.previousTasks,
      generatedFromTaskId: options.generatedFromTaskId,
      generatedNextTask: options.generatedNextTask,
      pruneOrphans: options.pruneOrphans ?? true,
      shiftCustomOnDateShift: options.shiftCustomOnDateShift ?? false,
      nowUtc: options.nowUtc,
    });

    this.writeRemindersRaw(reconciled.reminders, false);
    if (options.persistTasks !== false) {
      this.writeTasksRaw(reconciled.tasks);
    }
    if (options.emitSync !== false && typeof window !== 'undefined') {
      window.dispatchEvent(new CustomEvent(SharedStateBridge.SYNC_EVENT_NAME));
    }

    this.syncWebTaskNotifications({
      tasks: reconciled.tasks,
      reminders: reconciled.reminders,
      nowUtc: options.nowUtc,
    });

    return reconciled;
  }

  public restoreRemindersSnapshot(
    remindersSnapshot: SharedReminder[],
    options?: { tasks?: DaywellTaskRecord[]; emitSync?: boolean; nowUtc?: Date }
  ): void {
    this.writeRemindersRaw(remindersSnapshot, false);
    const tasks = options?.tasks ?? this.readTasksRaw();
    this.syncWebTaskNotifications({
      tasks,
      reminders: remindersSnapshot,
      nowUtc: options?.nowUtc,
    });
    if (options?.emitSync !== false && typeof window !== 'undefined') {
      window.dispatchEvent(new CustomEvent(SharedStateBridge.SYNC_EVENT_NAME));
    }
  }

  // --------------------------------------------------------------------------
  // Web Notification Capabilities & Honest Foreground Scheduler
  // --------------------------------------------------------------------------

  public getWebNotificationSupportStatus(): WebNotificationSupportStatus {
    const supported =
      typeof Notification !== 'undefined' &&
      typeof Notification === 'function';
    const permission: WebNotificationPermissionState = supported
      ? (Notification.permission as WebNotificationPermissionState)
      : 'unsupported';

    return {
      supported,
      permission,
      backgroundDeliverySupported: false,
      capabilityNote: supported
        ? permission === 'granted'
          ? 'Browser alerts active while this tab remains open. Background delivery after closing the tab is unsupported in Web Preview.'
          : permission === 'denied'
          ? 'Browser notifications blocked in browser settings; in-app alerts still appear while this tab is open.'
          : 'Enable browser notifications for desktop/tab popups while this tab stays open.'
        : 'Browser Notification API unavailable here; in-app alerts display while this tab remains open.',
    };
  }

  public async requestWebNotificationPermission(): Promise<WebNotificationPermissionState> {
    if (
      typeof Notification === 'undefined' ||
      typeof Notification.requestPermission !== 'function'
    ) {
      return 'unsupported';
    }
    try {
      const result = await Notification.requestPermission();
      return result as WebNotificationPermissionState;
    } catch {
      return (Notification.permission as WebNotificationPermissionState) ?? 'default';
    }
  }

  public setReminderDueListener(
    listener: ((alert: WebTaskReminderAlert) => void) | undefined
  ): void {
    this.activeDueListener = listener;
  }

  private cancelScheduledTimer(reminderId: string): void {
    const handle = this.scheduledTimers.get(reminderId);
    if (handle !== undefined) {
      clearTimeout(handle);
      this.scheduledTimers.delete(reminderId);
    }
    this.scheduledMeta.delete(reminderId);
  }

  public cancelAllWebTaskNotifications(): void {
    for (const handle of this.scheduledTimers.values()) {
      clearTimeout(handle);
    }
    this.scheduledTimers.clear();
    this.scheduledMeta.clear();
  }

  private deliverDueAlert(
    reminder: SharedReminder,
    taskTitle: string,
    onReminderDue?: (alert: WebTaskReminderAlert) => void
  ): void {
    const triggerMs = Date.parse(reminder.triggerTimeUtc);
    const dedupKey = `${reminder.id}:${Number.isFinite(triggerMs) ? triggerMs : reminder.triggerTimeUtc}`;
    if (this.deliveredKeys.has(dedupKey)) return;
    this.deliveredKeys.add(dedupKey);

    let deliveredViaBrowserNotification = false;
    if (
      typeof Notification !== 'undefined' &&
      Notification.permission === 'granted'
    ) {
      try {
        new Notification('Daywell Task Reminder', {
          body: taskTitle,
          tag: reminder.id,
        });
        deliveredViaBrowserNotification = true;
      } catch {
        deliveredViaBrowserNotification = false;
      }
    }

    const alert: WebTaskReminderAlert = {
      reminderId: reminder.id,
      taskId: reminder.targetId,
      title: taskTitle,
      triggerTimeUtc: reminder.triggerTimeUtc,
      summary: formatTaskReminderSummary(reminder.triggerTimeUtc),
      deliveredViaBrowserNotification,
    };

    (onReminderDue ?? this.activeDueListener)?.(alert);
  }

  private armTimeoutStep(
    reminder: SharedReminder,
    taskTitle: string,
    targetMs: number,
    onReminderDue?: (alert: WebTaskReminderAlert) => void
  ): void {
    const nowMs = EthiopiaClock.nowUtc().getTime();
    const remainingMs = targetMs - nowMs;
    if (remainingMs <= 0) {
      this.scheduledTimers.delete(reminder.id);
      this.scheduledMeta.delete(reminder.id);
      this.deliverDueAlert(reminder, taskTitle, onReminderDue);
      return;
    }

    const delayMs = Math.min(remainingMs, MAX_JS_TIMEOUT_MS);
    const handle = setTimeout(() => {
      this.scheduledTimers.delete(reminder.id);
      if (remainingMs > MAX_JS_TIMEOUT_MS) {
        this.armTimeoutStep(reminder, taskTitle, targetMs, onReminderDue);
      } else {
        this.scheduledMeta.delete(reminder.id);
        this.deliverDueAlert(reminder, taskTitle, onReminderDue);
      }
    }, delayMs);

    this.scheduledTimers.set(reminder.id, handle);
    this.scheduledMeta.set(reminder.id, { triggerMs: targetMs, title: taskTitle });
  }

  public syncWebTaskNotifications(options?: {
    tasks?: readonly DaywellTaskRecord[];
    reminders?: readonly SharedReminder[];
    onReminderDue?: (alert: WebTaskReminderAlert) => void;
    nowUtc?: Date;
  }): number {
    if (options?.onReminderDue) {
      this.activeDueListener = options.onReminderDue;
    }
    const tasks = options?.tasks ?? this.readTasksRaw();
    const reminders = options?.reminders ?? this.loadAllReminders();
    const nowMs = (options?.nowUtc ?? EthiopiaClock.nowUtc()).getTime();
    const pastCutoffMs = nowMs - OVERDUE_GRACE_WINDOW_MS;

    const taskById = new Map(tasks.map((t) => [t.id, t] as const));
    const eligibleById = new Map<
      string,
      { reminder: SharedReminder; title: string; triggerMs: number }
    >();

    for (const r of reminders) {
      if (r.targetType !== 'task' || !r.isActive) continue;
      const task = taskById.get(r.targetId);
      if (!task || !isTaskEligibleForActiveReminder(task)) continue;
      const triggerMs = Date.parse(r.triggerTimeUtc);
      if (!Number.isFinite(triggerMs)) continue;
      eligibleById.set(r.id, {
        reminder: r,
        title: task.title.trim() || r.title || 'Task Reminder',
        triggerMs,
      });
    }

    for (const trackedId of Array.from(this.scheduledTimers.keys())) {
      if (!eligibleById.has(trackedId)) {
        this.cancelScheduledTimer(trackedId);
      }
    }

    let activeTimerCount = 0;
    for (const item of eligibleById.values()) {
      const { reminder, title, triggerMs } = item;
      if (triggerMs < pastCutoffMs) {
        this.cancelScheduledTimer(reminder.id);
        continue;
      }

      if (triggerMs <= nowMs) {
        this.cancelScheduledTimer(reminder.id);
        this.deliverDueAlert(reminder, title, options?.onReminderDue);
        continue;
      }

      const existingMeta = this.scheduledMeta.get(reminder.id);
      if (
        existingMeta &&
        existingMeta.triggerMs === triggerMs &&
        existingMeta.title === title &&
        this.scheduledTimers.has(reminder.id)
      ) {
        activeTimerCount += 1;
        continue;
      }

      this.cancelScheduledTimer(reminder.id);
      this.armTimeoutStep(reminder, title, triggerMs, options?.onReminderDue);
      activeTimerCount += 1;
    }

    return activeTimerCount;
  }

  public getActiveScheduledTimerCount(): number {
    return this.scheduledTimers.size;
  }

  public resetSchedulerStateForTesting(): void {
    this.cancelAllWebTaskNotifications();
    this.deliveredKeys.clear();
    this.activeDueListener = undefined;
  }
}

export const taskRemindersService = new TaskRemindersService();
