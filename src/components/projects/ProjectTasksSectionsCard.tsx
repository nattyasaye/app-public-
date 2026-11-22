import React, { useEffect, useState } from 'react';
import {
  SharedMilestone,
  SharedProjectTrackingRecord,
  SharedReminder,
  SharedTaskRecurrenceConfig,
  SharedTaskRecurrenceFrequency,
  SharedTaskRecurrenceRepeatFrom,
} from '../../domain/sharedFoundation';
import {
  CANONICAL_TASK_PRIORITIES,
  CANONICAL_TASK_STATUSES,
  computeSubtaskProgress,
  DaywellTaskRecord,
  isTaskCompleted,
  resolveEffectiveTaskStatus,
  TASK_PRIORITY_LABELS,
  TASK_STATUS_LABELS,
  TaskPriority,
  TaskStatus,
  validateTaskRecurrenceConfig,
} from '../../domain/taskOperations';
import {
  formatRecurrenceSummary,
  resolveEffectiveRecurrenceConfig,
} from '../../domain/taskRecurrence';
import {
  TaskReminderPreset,
  computeTaskReminderTriggerFromPreset,
  defaultFallbackReminderDateTime,
  findReminderForTask,
  formatTaskReminderSummary,
  inferTaskReminderPreset,
  resolveTaskReminderAnchor,
  utcIsoToEthiopiaWallDateTime,
} from '../../domain/taskReminders';
import {
  ProjectSectionsViewModel,
  projectsService,
} from '../../services/projectsService';
import { taskRemindersService } from '../../services/taskRemindersService';
import {
  Bell,
  Calendar,
  Check,
  CheckSquare,
  Clock,
  Edit3,
  Flag,
  FolderPlus,
  Plus,
  Repeat2,
  Trash2,
  X,
} from 'lucide-react';
import {
  DaywellButton,
  DaywellCard,
  DaywellConfirmationDialog,
  DaywellIconButton,
  DaywellProgressBar,
  DaywellStatusBadge,
} from '../ui';
import {
  TaskReminderDetailsPanel,
  TaskReminderEditorSection,
} from '../tasks/TaskReminderFields';
import {
  TaskRecurrenceDetailsPanel,
  TaskRecurrenceEditorSection,
} from '../tasks/TaskRecurrenceFields';

export interface ProjectTasksSectionsCardProps {
  projectId: string;
  sectionsView: ProjectSectionsViewModel;
  milestones: SharedMilestone[];
  onRefresh: () => void;
  onNotifyUndo?: (message: string, undoAction: () => void) => void;
}

export function ProjectTasksSectionsCard({
  projectId,
  sectionsView,
  milestones,
  onRefresh,
  onNotifyUndo,
}: ProjectTasksSectionsCardProps) {
  const [isAddingSection, setIsAddingSection] = useState(false);
  const [newSectionTitle, setNewSectionTitle] = useState('');
  const [sectionError, setSectionError] = useState<string | null>(null);

  const [renamingSectionId, setRenamingSectionId] = useState<string | null>(
    null
  );
  const [renameTitle, setRenameTitle] = useState('');
  const [renameError, setRenameError] = useState<string | null>(null);

  const [pendingDeleteSection, setPendingDeleteSection] =
    useState<SharedProjectTrackingRecord | null>(null);

  // Task Modal (Create or Edit inside Project Details)
  const [isTaskModalOpen, setIsTaskModalOpen] = useState(false);
  const [editingTask, setEditingTask] = useState<DaywellTaskRecord | null>(null);
  const [taskTitle, setTaskTitle] = useState('');
  const [taskDescription, setTaskDescription] = useState('');
  const [taskPriority, setTaskPriority] = useState<TaskPriority>('medium');
  const [taskStatus, setTaskStatus] = useState<TaskStatus>('not_started');
  const [taskDueDate, setTaskDueDate] = useState('');
  const [taskScheduledDate, setTaskScheduledDate] = useState('');
  const [taskScheduledTime, setTaskScheduledTime] = useState('');
  const [taskSectionId, setTaskSectionId] = useState('');
  const [taskMilestoneId, setTaskMilestoneId] = useState('');
  const [taskReminderEnabled, setTaskReminderEnabled] = useState(false);
  const [taskReminderPreset, setTaskReminderPreset] =
    useState<TaskReminderPreset>('at_time');
  const [taskReminderCustomDate, setTaskReminderCustomDate] = useState('');
  const [taskReminderCustomTime, setTaskReminderCustomTime] = useState('');
  const [taskReminderError, setTaskReminderError] = useState<string | undefined>();
  const [taskIsRecurring, setTaskIsRecurring] = useState(false);
  const [taskRecFrequency, setTaskRecFrequency] =
    useState<SharedTaskRecurrenceFrequency>('weekly');
  const [taskRecInterval, setTaskRecInterval] = useState(1);
  const [taskRecWeekdays, setTaskRecWeekdays] = useState<number[]>([]);
  const [taskRecStartDate, setTaskRecStartDate] = useState('');
  const [taskRecEndDate, setTaskRecEndDate] = useState('');
  const [taskRecRepeatFrom, setTaskRecRepeatFrom] =
    useState<SharedTaskRecurrenceRepeatFrom>('due_date');
  const [taskFormError, setTaskFormError] = useState<string | null>(null);
  const [taskRecurrenceErrors, setTaskRecurrenceErrors] = useState<
    Record<string, string>
  >({});

  const [pendingDeleteTask, setPendingDeleteTask] =
    useState<DaywellTaskRecord | null>(null);
  const [detailsTaskId, setDetailsTaskId] = useState<string | null>(null);
  const [detailsRecurrenceError, setDetailsRecurrenceError] = useState('');
  const [reminders, setReminders] = useState<SharedReminder[]>(() =>
    taskRemindersService.loadAllReminders()
  );

  useEffect(() => {
    setReminders(taskRemindersService.loadAllReminders());
  }, [sectionsView]);

  const allTasks = [
    ...sectionsView.sections.flatMap((s) => s.tasks),
    ...sectionsView.unsectionedTasks,
  ];
  const detailsTask = detailsTaskId
    ? allTasks.find((t) => t.id === detailsTaskId) ?? null
    : null;
  const completedTasksCount = allTasks.filter((t) => isTaskCompleted(t)).length;
  const tasksPct =
    allTasks.length > 0
      ? Math.round((completedTasksCount / allTasks.length) * 100)
      : 0;

  const milestoneById = new Map(milestones.map((m) => [m.id, m]));
  const taskToSectionId = new Map<string, string>();
  for (const sec of sectionsView.sections) {
    for (const t of sec.tasks) {
      taskToSectionId.set(t.id, sec.record.id);
    }
  }

  const handleCreateSection = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = newSectionTitle.trim();
    if (!trimmed) {
      setSectionError('Section name is required.');
      return;
    }
    try {
      projectsService.createProjectSection(projectId, trimmed);
      setNewSectionTitle('');
      setSectionError(null);
      setIsAddingSection(false);
      onRefresh();
    } catch (err) {
      setSectionError(
        err instanceof Error ? err.message : 'Unable to create section.'
      );
    }
  };

  const handleSaveRenameSection = (sectionId: string) => {
    const trimmed = renameTitle.trim();
    if (!trimmed) {
      setRenameError('Section name is required.');
      return;
    }
    try {
      projectsService.renameProjectSection(sectionId, trimmed);
      setRenamingSectionId(null);
      setRenameTitle('');
      setRenameError(null);
      onRefresh();
    } catch (err) {
      setRenameError(
        err instanceof Error ? err.message : 'Unable to rename section.'
      );
    }
  };

  const handleConfirmDeleteSection = () => {
    if (!pendingDeleteSection) return;
    const target = pendingDeleteSection;
    const { deletedGroup, detachedTaskIds } =
      projectsService.deleteProjectSection(projectId, target.id);
    setPendingDeleteSection(null);
    onRefresh();
    if (deletedGroup) {
      onNotifyUndo?.(
        `Removed section "${deletedGroup.title ?? 'Section'}"`,
        () => {
          projectsService.restoreProjectSection(
            projectId,
            deletedGroup,
            detachedTaskIds
          );
          onRefresh();
        }
      );
    }
  };

  const openCreateTask = (defaultSectionId = '') => {
    const fallbackReminderDt = defaultFallbackReminderDateTime();
    setEditingTask(null);
    setTaskTitle('');
    setTaskDescription('');
    setTaskPriority('medium');
    setTaskStatus('not_started');
    setTaskDueDate('');
    setTaskScheduledDate('');
    setTaskScheduledTime('');
    setTaskSectionId(defaultSectionId);
    setTaskMilestoneId('');
    setTaskReminderEnabled(false);
    setTaskReminderPreset('at_time');
    setTaskReminderCustomDate(fallbackReminderDt.dateIso);
    setTaskReminderCustomTime(fallbackReminderDt.time);
    setTaskReminderError(undefined);
    setTaskIsRecurring(false);
    setTaskRecFrequency('weekly');
    setTaskRecInterval(1);
    setTaskRecWeekdays([]);
    setTaskRecStartDate('');
    setTaskRecEndDate('');
    setTaskRecRepeatFrom('due_date');
    setTaskRecurrenceErrors({});
    setTaskFormError(null);
    setIsTaskModalOpen(true);
  };

  const openEditTask = (task: DaywellTaskRecord) => {
    const rec = resolveEffectiveRecurrenceConfig(task);
    const liveReminders = taskRemindersService.loadAllReminders();
    const existingReminder = findReminderForTask(liveReminders, task.id);
    const existingWall = existingReminder
      ? utcIsoToEthiopiaWallDateTime(existingReminder.triggerTimeUtc)
      : null;
    const anchor = resolveTaskReminderAnchor(task);
    const fallbackReminderDt = defaultFallbackReminderDateTime();

    setEditingTask(task);
    setTaskTitle(task.title);
    setTaskDescription(task.description ?? '');
    setTaskPriority(task.priority);
    setTaskStatus(resolveEffectiveTaskStatus(task));
    setTaskDueDate(task.dueDate ?? '');
    setTaskScheduledDate(task.scheduledDate ?? '');
    setTaskScheduledTime(task.scheduledTime ?? '');
    setTaskSectionId(taskToSectionId.get(task.id) ?? '');
    setTaskMilestoneId(task.milestoneId ?? '');
    setTaskReminderEnabled(Boolean(existingReminder || task.hasReminder));
    setTaskReminderPreset(
      existingReminder
        ? inferTaskReminderPreset(task, existingReminder.triggerTimeUtc)
        : 'at_time'
    );
    setTaskReminderCustomDate(
      existingWall?.dateIso ?? anchor?.dateIso ?? fallbackReminderDt.dateIso
    );
    setTaskReminderCustomTime(
      existingWall?.time ?? anchor?.time ?? fallbackReminderDt.time
    );
    setTaskReminderError(undefined);
    setTaskIsRecurring(Boolean(rec));
    setTaskRecFrequency(rec?.frequency ?? 'weekly');
    setTaskRecInterval(rec?.interval ?? 1);
    setTaskRecWeekdays(rec?.weekdays ? [...rec.weekdays] : []);
    setTaskRecStartDate(rec?.startDate ?? '');
    setTaskRecEndDate(rec?.endDate ?? '');
    setTaskRecRepeatFrom(rec?.repeatFrom ?? 'due_date');
    setTaskRecurrenceErrors({});
    setTaskFormError(null);
    setIsTaskModalOpen(true);
  };

  const openTaskDetails = (task: DaywellTaskRecord) => {
    setDetailsRecurrenceError('');
    setReminders(taskRemindersService.loadAllReminders());
    setDetailsTaskId(task.id);
  };

  const handleSaveDetailsReminder = (task: DaywellTaskRecord, triggerTimeUtc: string) => {
    const prevReminders = taskRemindersService.loadAllReminders();
    const prevTasks = [...allTasks];
    const { reminder, reminders: nextReminders } =
      taskRemindersService.setTaskReminder(task, triggerTimeUtc, {
        emitSync: true,
        syncTaskHasReminder: true,
      });
    setReminders(nextReminders);
    onRefresh();
    onNotifyUndo?.(
      `Reminder set for "${task.title}" (${formatTaskReminderSummary(reminder.triggerTimeUtc)})`,
      () => {
        projectsService.restoreTasksSnapshot(
          prevTasks,
          undefined,
          undefined,
          undefined,
          prevReminders
        );
        setReminders(prevReminders);
        onRefresh();
      }
    );
  };

  const handleRemoveDetailsReminder = (task: DaywellTaskRecord) => {
    const prevReminders = taskRemindersService.loadAllReminders();
    const prevTasks = [...allTasks];
    const nextReminders = taskRemindersService.removeTaskReminder(task.id, {
      emitSync: true,
      syncTaskHasReminder: true,
    });
    setReminders(nextReminders);
    onRefresh();
    onNotifyUndo?.(`Removed reminder for "${task.title}"`, () => {
      projectsService.restoreTasksSnapshot(
        prevTasks,
        undefined,
        undefined,
        undefined,
        prevReminders
      );
      setReminders(prevReminders);
      onRefresh();
    });
  };

  const handleSkipDetailsRecurrence = (taskId: string) => {
    const res = projectsService.skipTaskRecurrenceInProject(taskId);
    if (!res.ok || !res.updated) {
      setDetailsRecurrenceError(res.error ?? 'Unable to skip occurrence.');
      return;
    }
    setDetailsRecurrenceError('');
    setReminders(taskRemindersService.loadAllReminders());
    onRefresh();
    const nextDate = res.updated.dueDate ?? res.updated.scheduledDate;
    onNotifyUndo?.(
      `Skipped to next occurrence${nextDate ? ` (${nextDate})` : ''}`,
      () => {
        projectsService.restoreTasksSnapshot(
          res.previousTasks,
          undefined,
          undefined,
          res.previousEntries,
          res.previousReminders
        );
        setReminders(res.previousReminders);
        onRefresh();
      }
    );
  };

  const handleRescheduleDetailsRecurrence = (
    taskId: string,
    newDateIso: string
  ) => {
    const res = projectsService.rescheduleTaskOccurrenceInProject(
      taskId,
      newDateIso
    );
    if (!res.ok || !res.updated) {
      setDetailsRecurrenceError(
        res.error ?? 'Unable to reschedule occurrence.'
      );
      return;
    }
    setDetailsRecurrenceError('');
    setReminders(taskRemindersService.loadAllReminders());
    onRefresh();
    onNotifyUndo?.(
      `Rescheduled "${res.updated.title}" to ${newDateIso}`,
      () => {
        projectsService.restoreTasksSnapshot(
          res.previousTasks,
          undefined,
          undefined,
          res.previousEntries,
          res.previousReminders
        );
        setReminders(res.previousReminders);
        onRefresh();
      }
    );
  };

  const handleStopDetailsRecurrence = (taskId: string) => {
    const res = projectsService.stopTaskRecurrenceInProject(taskId);
    if (!res.ok || !res.updated) {
      setDetailsRecurrenceError(res.error ?? 'Unable to stop recurrence.');
      return;
    }
    setDetailsRecurrenceError('');
    setReminders(taskRemindersService.loadAllReminders());
    onRefresh();
    onNotifyUndo?.(`Stopped recurrence for "${res.updated.title}"`, () => {
      projectsService.restoreTasksSnapshot(
        res.previousTasks,
        undefined,
        undefined,
        res.previousEntries,
        res.previousReminders
      );
      setReminders(res.previousReminders);
      onRefresh();
    });
  };

  const handleSaveTaskModal = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = taskTitle.trim();
    if (!trimmed) {
      setTaskFormError('Task title is required.');
      return;
    }
    let computedReminderTriggerUtc: string | undefined;
    if (taskReminderEnabled) {
      const remCheck = computeTaskReminderTriggerFromPreset({
        task: {
          dueDate: taskDueDate.trim() || undefined,
          scheduledDate: taskScheduledDate.trim() || undefined,
          scheduledTime: taskScheduledTime.trim() || undefined,
        },
        preset: taskReminderPreset,
        customDateIso: taskReminderCustomDate,
        customTime: taskReminderCustomTime,
      });
      if (!remCheck.ok || !remCheck.triggerTimeUtc) {
        const msg = remCheck.error ?? 'Choose a valid reminder date and time.';
        setTaskReminderError(msg);
        setTaskFormError(msg);
        return;
      }
      computedReminderTriggerUtc = remCheck.triggerTimeUtc;
    }
    setTaskReminderError(undefined);

    const recConfig: SharedTaskRecurrenceConfig | undefined = taskIsRecurring
      ? {
          frequency: taskRecFrequency,
          interval: taskRecInterval,
          ...(taskRecFrequency === 'weekly' && taskRecWeekdays.length > 0
            ? { weekdays: taskRecWeekdays }
            : {}),
          ...(taskRecStartDate.trim()
            ? { startDate: taskRecStartDate.trim() }
            : {}),
          ...(taskRecEndDate.trim() ? { endDate: taskRecEndDate.trim() } : {}),
          repeatFrom: taskRecRepeatFrom,
        }
      : undefined;
    if (recConfig) {
      const recCheck = validateTaskRecurrenceConfig(recConfig);
      if (!recCheck.isValid) {
        setTaskRecurrenceErrors(recCheck.errors);
        setTaskFormError(
          Object.values(recCheck.errors)[0] ?? 'Invalid recurrence settings.'
        );
        return;
      }
    }
    setTaskRecurrenceErrors({});

    try {
      if (editingTask) {
        const prevSectionId = taskToSectionId.get(editingTask.id);
        const editRes = projectsService.updateTaskInProjectWithRecurrence(
          editingTask.id,
          {
            title: trimmed,
            description: taskDescription,
            priority: taskPriority,
            status: taskStatus,
            dueDate: taskDueDate,
            scheduledDate: taskScheduledDate,
            scheduledTime: taskScheduledTime,
            milestoneId: taskMilestoneId || '',
            sectionId: taskSectionId || null,
            ...(taskReminderEnabled && computedReminderTriggerUtc
              ? { reminderTriggerUtc: computedReminderTriggerUtc }
              : { clearReminder: true }),
            ...(recConfig
              ? { recurrenceConfig: recConfig }
              : { clearRecurrenceConfig: true }),
          }
        );
        setIsTaskModalOpen(false);
        setTaskFormError(null);
        setReminders(taskRemindersService.loadAllReminders());
        onRefresh();
        if (editRes.generatedNextTask || editRes.seriesEnded) {
          const nextDate =
            editRes.generatedNextTask?.dueDate ??
            editRes.generatedNextTask?.scheduledDate;
          const msg = editRes.generatedNextTask
            ? `Completed "${trimmed}" · Next: ${nextDate ?? 'scheduled'}`
            : `Completed "${trimmed}" · Recurrence series ended`;
          onNotifyUndo?.(msg, () => {
            projectsService.restoreTasksSnapshot(
              editRes.previousTasks,
              prevSectionId
                ? {
                    projectId,
                    taskId: editingTask.id,
                    sectionId: prevSectionId,
                  }
                : undefined,
              editRes.generatedNextTask?.id,
              editRes.previousEntries,
              editRes.previousReminders
            );
            setReminders(editRes.previousReminders);
            onRefresh();
          });
        }
      } else {
        projectsService.createTaskInProject({
          projectId,
          title: trimmed,
          description: taskDescription,
          priority: taskPriority,
          status: taskStatus,
          dueDate: taskDueDate || undefined,
          scheduledDate: taskScheduledDate || undefined,
          scheduledTime: taskScheduledTime || undefined,
          milestoneId: taskMilestoneId || undefined,
          sectionId: taskSectionId || undefined,
          recurrenceConfig: recConfig,
          reminderTriggerUtc: computedReminderTriggerUtc,
        });
        setIsTaskModalOpen(false);
        setTaskFormError(null);
        setReminders(taskRemindersService.loadAllReminders());
        onRefresh();
      }
    } catch (err) {
      setTaskFormError(
        err instanceof Error ? err.message : 'Unable to save task.'
      );
    }
  };

  const handleToggleTask = (task: DaywellTaskRecord) => {
    const wasDone = isTaskCompleted(task);
    const prevSectionId = taskToSectionId.get(task.id);
    const { previousTasks, previousReminders, generatedNextTask } =
      projectsService.toggleTaskCompletionInProject(task.id);
    setReminders(taskRemindersService.loadAllReminders());
    onRefresh();
    const nextDate = generatedNextTask?.dueDate ?? generatedNextTask?.scheduledDate;
    const message = wasDone
      ? `Reopened "${task.title}"`
      : generatedNextTask
        ? `Completed "${task.title}" · Next: ${nextDate ?? 'scheduled'}`
        : `Completed "${task.title}"`;
    onNotifyUndo?.(message, () => {
      projectsService.restoreTasksSnapshot(
        previousTasks,
        prevSectionId
          ? { projectId, taskId: task.id, sectionId: prevSectionId }
          : undefined,
        generatedNextTask?.id,
        undefined,
        previousReminders
      );
      setReminders(previousReminders);
      onRefresh();
    });
  };

  const handleMoveTaskSection = (task: DaywellTaskRecord, nextSectionId: string) => {
    projectsService.assignTaskToProjectSection(
      projectId,
      task.id,
      nextSectionId || null
    );
    onRefresh();
  };

  const handleConfirmDeleteTask = () => {
    if (!pendingDeleteTask) return;
    const target = pendingDeleteTask;
    const { previousTasks, previousReminders, deleted, previousSection } =
      projectsService.deleteTaskInProject(target.id);
    setPendingDeleteTask(null);
    setIsTaskModalOpen(false);
    setReminders(taskRemindersService.loadAllReminders());
    onRefresh();
    if (deleted) {
      onNotifyUndo?.(`Deleted "${deleted.title}"`, () => {
        projectsService.restoreTasksSnapshot(
          previousTasks,
          previousSection
            ? {
                projectId: previousSection.projectId,
                taskId: deleted.id,
                sectionId: previousSection.sectionId,
              }
            : undefined,
          undefined,
          undefined,
          previousReminders
        );
        setReminders(previousReminders);
        onRefresh();
      });
    }
  };

  const renderTaskRow = (task: DaywellTaskRecord) => {
    const completed = isTaskCompleted(task);
    const subProg = computeSubtaskProgress(task.subtasks);
    const milestone = task.milestoneId
      ? milestoneById.get(task.milestoneId)
      : undefined;
    const currentSectionId = taskToSectionId.get(task.id) ?? '';

    return (
      <div
        key={task.id}
        className="p-2.5 bg-[var(--dw-card)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] flex items-start justify-between gap-2.5"
      >
        <div className="flex items-start gap-2.5 min-w-0 flex-1">
          <button
            type="button"
            aria-label={
              completed ? `Reopen ${task.title}` : `Complete ${task.title}`
            }
            onClick={() => handleToggleTask(task)}
            className={`w-4 h-4 mt-0.5 rounded-[var(--dw-radius-sm)] border flex items-center justify-center shrink-0 cursor-pointer transition-colors ${
              completed
                ? 'bg-[var(--dw-primary)] border-[var(--dw-primary)] text-[var(--dw-on-primary)]'
                : 'border-[var(--dw-border)] bg-[var(--dw-surface-subtle)] hover:border-[var(--dw-primary)]'
            }`}
          >
            {completed && <Check className="w-3 h-3 stroke-[3]" />}
          </button>

          <div
            role="button"
            tabIndex={0}
            onClick={() => openTaskDetails(task)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                openTaskDetails(task);
              }
            }}
            className="min-w-0 flex-1 space-y-1 cursor-pointer"
          >
            <p
              className={`text-xs font-semibold leading-snug ${
                completed
                  ? 'line-through text-[var(--dw-text-muted)]'
                  : 'text-[var(--dw-text-primary)]'
              }`}
            >
              {task.title}
            </p>
            <div className="flex flex-wrap items-center gap-2 text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
              <span
                className={`flex items-center gap-0.5 font-semibold ${
                  task.priority === 'urgent'
                    ? 'text-[var(--dw-error)]'
                    : task.priority === 'high'
                    ? 'text-[var(--dw-warning)]'
                    : 'text-[var(--dw-text-muted)]'
                }`}
              >
                <Flag className="w-3 h-3" />
                {TASK_PRIORITY_LABELS[task.priority]}
              </span>
              {milestone && (
                <DaywellStatusBadge
                  tone={milestone.isCompleted ? 'success' : 'info'}
                  showIcon={false}
                  label={milestone.title}
                />
              )}
              {subProg.total > 0 && (
                <span>
                  {subProg.completed}/{subProg.total} subtasks
                </span>
              )}
              {task.dueDate && (
                <span className="flex items-center gap-0.5 text-[var(--dw-primary)]">
                  <Calendar className="w-3 h-3" />
                  Due {task.dueDate}
                </span>
              )}
              {task.scheduledTime && (
                <span className="flex items-center gap-0.5 text-[var(--dw-text-secondary)]">
                  <Clock className="w-3 h-3" />
                  {task.scheduledTime}
                </span>
              )}
              {(() => {
                const rec = resolveEffectiveRecurrenceConfig(task);
                if (!rec) return null;
                return (
                  <span className="flex items-center gap-0.5 text-[var(--dw-text-secondary)]">
                    <Repeat2 className="w-3 h-3 text-[var(--dw-primary)]" />
                    {formatRecurrenceSummary(rec)}
                  </span>
                );
              })()}
              {(() => {
                const taskRem = findReminderForTask(reminders, task.id);
                if (!task.hasReminder && (!taskRem || !taskRem.isActive)) {
                  return null;
                }
                const remSummary = taskRem
                  ? formatTaskReminderSummary(taskRem.triggerTimeUtc)
                  : 'Reminder set';
                return (
                  <span
                    className="flex items-center gap-0.5 text-[var(--dw-primary)] font-medium"
                    title={remSummary}
                  >
                    <Bell className="w-3 h-3" />
                    {remSummary}
                  </span>
                );
              })()}
            </div>
          </div>
        </div>

        <div className="flex items-center gap-1 shrink-0">
          {sectionsView.sections.length > 0 && (
            <select
              aria-label={`Section for ${task.title}`}
              value={currentSectionId}
              onChange={(e) => handleMoveTaskSection(task, e.target.value)}
              className="max-w-[110px] min-h-[30px] px-2 py-0.5 bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] rounded-[var(--dw-radius-sm)] text-[11px] text-[var(--dw-text-secondary)] outline-none focus:border-[var(--dw-primary)]"
            >
              <option value="">General</option>
              {sectionsView.sections.map((s) => (
                <option key={s.record.id} value={s.record.id}>
                  {s.record.title}
                </option>
              ))}
            </select>
          )}
          <DaywellIconButton
            label={`Edit task ${task.title}`}
            size="compact"
            tone="muted"
            onClick={() => openEditTask(task)}
            icon={<Edit3 className="w-3.5 h-3.5" />}
          />
          <DaywellIconButton
            label={`Delete task ${task.title}`}
            size="compact"
            tone="danger"
            onClick={() => setPendingDeleteTask(task)}
            icon={<Trash2 className="w-3.5 h-3.5" />}
          />
        </div>
      </div>
    );
  };

  return (
    <DaywellCard padding="md" radius="lg" className="space-y-3">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div className="flex items-center gap-2">
          <CheckSquare className="w-4 h-4 text-[var(--dw-primary)]" />
          <div>
            <h2 className="text-xs font-bold uppercase tracking-wider text-[var(--dw-text-primary)]">
              Tasks & Sections
            </h2>
            <p className="text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
              {allTasks.length > 0
                ? `${completedTasksCount}/${allTasks.length} tasks done (${tasksPct}%)`
                : 'Organize actionable tasks into project sections'}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-1.5">
          <DaywellButton
            label={isAddingSection ? 'Cancel Section' : 'Add Section'}
            variant="outlined"
            size="compact"
            leadingIcon={<FolderPlus className="w-3.5 h-3.5" />}
            onClick={() => {
              setIsAddingSection((v) => !v);
              setSectionError(null);
            }}
          />
          <DaywellButton
            label="Add Task"
            variant="tonal"
            size="compact"
            leadingIcon={<Plus className="w-3.5 h-3.5" />}
            onClick={() => openCreateTask()}
          />
        </div>
      </div>

      {allTasks.length > 0 && (
        <DaywellProgressBar
          value={tasksPct}
          label="Project tasks completion"
        />
      )}

      {isAddingSection && (
        <form
          onSubmit={handleCreateSection}
          className="p-3 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] space-y-2"
        >
          <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)]">
            New Section Name *
          </label>
          <div className="flex items-center gap-2">
            <input
              aria-label="New section name"
              type="text"
              placeholder="e.g. Research & Design"
              value={newSectionTitle}
              onChange={(e) => {
                setNewSectionTitle(e.target.value);
                if (sectionError) setSectionError(null);
              }}
              className="flex-1 min-h-[38px] px-3 py-1.5 bg-[var(--dw-card)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
            />
            <DaywellButton
              type="submit"
              label="Create"
              variant="primary"
              size="compact"
            />
          </div>
          {sectionError && (
            <p className="text-[11px] text-[var(--dw-error)]">{sectionError}</p>
          )}
        </form>
      )}

      {allTasks.length === 0 && sectionsView.sections.length === 0 && !isAddingSection ? (
        <p className="text-xs text-[var(--dw-text-muted)] italic">
          No tasks linked yet. Add a task or create sections to organize this project&apos;s work.
        </p>
      ) : (
        <div className="space-y-3">
          {sectionsView.sections.map((sectionGroup) => {
            const sec = sectionGroup.record;
            const secDone = sectionGroup.tasks.filter((t) =>
              isTaskCompleted(t)
            ).length;
            const isRenaming = renamingSectionId === sec.id;

            return (
              <div
                key={sec.id}
                className="p-3 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] space-y-2"
              >
                {isRenaming ? (
                  <div className="space-y-1.5">
                    <div className="flex items-center gap-1.5">
                      <input
                        aria-label={`Rename section ${sec.title ?? ''}`}
                        type="text"
                        value={renameTitle}
                        onChange={(e) => {
                          setRenameTitle(e.target.value);
                          if (renameError) setRenameError(null);
                        }}
                        className="flex-1 min-h-[34px] px-2.5 py-1 bg-[var(--dw-card)] rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                      />
                      <DaywellIconButton
                        label="Save section name"
                        size="compact"
                        tone="primary"
                        onClick={() => handleSaveRenameSection(sec.id)}
                        icon={<Check className="w-3.5 h-3.5" />}
                      />
                      <DaywellIconButton
                        label="Cancel rename section"
                        size="compact"
                        tone="muted"
                        onClick={() => {
                          setRenamingSectionId(null);
                          setRenameError(null);
                        }}
                        icon={<X className="w-3.5 h-3.5" />}
                      />
                    </div>
                    {renameError && (
                      <p className="text-[11px] text-[var(--dw-error)]">
                        {renameError}
                      </p>
                    )}
                  </div>
                ) : (
                  <div className="flex items-center justify-between gap-2">
                    <div className="flex items-center gap-2 min-w-0">
                      <span className="text-xs font-bold text-[var(--dw-text-primary)] truncate">
                        {sec.title}
                      </span>
                      <span className="text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
                        ({secDone}/{sectionGroup.tasks.length})
                      </span>
                    </div>
                    <div className="flex items-center gap-0.5 shrink-0">
                      <DaywellIconButton
                        label={`Add task to ${sec.title ?? 'section'}`}
                        size="compact"
                        tone="primary"
                        onClick={() => openCreateTask(sec.id)}
                        icon={<Plus className="w-3.5 h-3.5" />}
                      />
                      <DaywellIconButton
                        label={`Rename section ${sec.title ?? ''}`}
                        size="compact"
                        tone="muted"
                        onClick={() => {
                          setRenamingSectionId(sec.id);
                          setRenameTitle(sec.title ?? '');
                          setRenameError(null);
                        }}
                        icon={<Edit3 className="w-3.5 h-3.5" />}
                      />
                      <DaywellIconButton
                        label={`Delete section ${sec.title ?? ''}`}
                        size="compact"
                        tone="danger"
                        onClick={() => setPendingDeleteSection(sec)}
                        icon={<Trash2 className="w-3.5 h-3.5" />}
                      />
                    </div>
                  </div>
                )}

                {sectionGroup.tasks.length === 0 ? (
                  <p className="text-[11px] text-[var(--dw-text-muted)] italic">
                    No tasks in this section yet.
                  </p>
                ) : (
                  <div className="space-y-1.5">
                    {sectionGroup.tasks.map((t) => renderTaskRow(t))}
                  </div>
                )}
              </div>
            );
          })}

          {sectionsView.unsectionedTasks.length > 0 && (
            <div className="space-y-1.5">
              {sectionsView.sections.length > 0 && (
                <div className="flex items-center justify-between px-0.5">
                  <span className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
                    General ({sectionsView.unsectionedTasks.length})
                  </span>
                </div>
              )}
              {sectionsView.unsectionedTasks.map((t) => renderTaskRow(t))}
            </div>
          )}
        </div>
      )}

      {/* Task Create/Edit Modal Scoped to Project */}
      {isTaskModalOpen && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={editingTask ? 'Edit Project Task' : 'Add Project Task'}
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs"
          onClick={(e) => {
            if (e.target === e.currentTarget) setIsTaskModalOpen(false);
          }}
        >
          <div className="w-full max-w-md bg-[var(--dw-elevated)] rounded-[var(--dw-radius-xl)] p-5 shadow-2xl border border-[var(--dw-border)] space-y-3.5 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <h3 className="dw-type-title text-[var(--dw-text-primary)]">
                {editingTask ? 'Edit Project Task' : 'New Project Task'}
              </h3>
              <DaywellIconButton
                label="Close project task modal"
                size="compact"
                tone="muted"
                onClick={() => setIsTaskModalOpen(false)}
                icon={<X className="w-4 h-4" />}
              />
            </div>

            <form onSubmit={handleSaveTaskModal} className="space-y-3">
              <div>
                <label className="block dw-type-caption uppercase text-[var(--dw-text-secondary)] mb-1">
                  Task Title *
                </label>
                <input
                  aria-label="Project task title"
                  type="text"
                  placeholder="e.g. Draft onboarding copy"
                  value={taskTitle}
                  onChange={(e) => {
                    setTaskTitle(e.target.value);
                    if (taskFormError) setTaskFormError(null);
                  }}
                  className="w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                />
              </div>

              <div>
                <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                  Description (Optional)
                </label>
                <textarea
                  rows={2}
                  value={taskDescription}
                  onChange={(e) => setTaskDescription(e.target.value)}
                  className="w-full px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                />
              </div>

              <div className="grid grid-cols-2 gap-2.5">
                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Priority
                  </label>
                  <select
                    aria-label="Project task priority"
                    value={taskPriority}
                    onChange={(e) =>
                      setTaskPriority(e.target.value as TaskPriority)
                    }
                    className="w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  >
                    {CANONICAL_TASK_PRIORITIES.map((p) => (
                      <option key={p} value={p}>
                        {TASK_PRIORITY_LABELS[p]}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Status
                  </label>
                  <select
                    aria-label="Project task status"
                    value={taskStatus}
                    onChange={(e) => setTaskStatus(e.target.value as TaskStatus)}
                    className="w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  >
                    {CANONICAL_TASK_STATUSES.map((s) => (
                      <option key={s} value={s}>
                        {TASK_STATUS_LABELS[s]}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-2.5">
                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Section
                  </label>
                  <select
                    aria-label="Project task section"
                    value={taskSectionId}
                    onChange={(e) => setTaskSectionId(e.target.value)}
                    className="w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  >
                    <option value="">General / Unassigned</option>
                    {sectionsView.sections.map((s) => (
                      <option key={s.record.id} value={s.record.id}>
                        {s.record.title}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Milestone
                  </label>
                  <select
                    aria-label="Project task milestone"
                    value={taskMilestoneId}
                    onChange={(e) => setTaskMilestoneId(e.target.value)}
                    className="w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  >
                    <option value="">None</option>
                    {milestones.map((m) => (
                      <option key={m.id} value={m.id}>
                        {m.title}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-2.5">
                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Scheduled Date
                  </label>
                  <input
                    aria-label="Project task scheduled date"
                    type="date"
                    value={taskScheduledDate}
                    onChange={(e) => setTaskScheduledDate(e.target.value)}
                    className="w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  />
                </div>
                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Due Date
                  </label>
                  <input
                    aria-label="Project task due date"
                    type="date"
                    value={taskDueDate}
                    onChange={(e) => setTaskDueDate(e.target.value)}
                    className="w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  />
                </div>
              </div>

              <div>
                <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                  Scheduled Time (Optional)
                </label>
                <input
                  aria-label="Project task scheduled time"
                  type="time"
                  value={taskScheduledTime}
                  onChange={(e) => setTaskScheduledTime(e.target.value)}
                  className="w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                />
              </div>

              <TaskReminderEditorSection
                compact
                enabled={taskReminderEnabled}
                onToggle={(next) => {
                  setTaskReminderEnabled(next);
                  setTaskReminderError(undefined);
                }}
                preset={taskReminderPreset}
                onChangePreset={(next) => {
                  setTaskReminderPreset(next);
                  setTaskReminderError(undefined);
                }}
                customDate={taskReminderCustomDate}
                onChangeCustomDate={(next) => {
                  setTaskReminderCustomDate(next);
                  setTaskReminderError(undefined);
                }}
                customTime={taskReminderCustomTime}
                onChangeCustomTime={(next) => {
                  setTaskReminderCustomTime(next);
                  setTaskReminderError(undefined);
                }}
                dueDate={taskDueDate}
                scheduledDate={taskScheduledDate}
                scheduledTime={taskScheduledTime}
                error={taskReminderError}
              />

              <TaskRecurrenceEditorSection
                compact
                isRecurring={taskIsRecurring}
                onToggleRecurring={setTaskIsRecurring}
                frequency={taskRecFrequency}
                onChangeFrequency={setTaskRecFrequency}
                interval={taskRecInterval}
                onChangeInterval={setTaskRecInterval}
                weekdays={taskRecWeekdays}
                onChangeWeekdays={setTaskRecWeekdays}
                startDate={taskRecStartDate}
                onChangeStartDate={setTaskRecStartDate}
                endDate={taskRecEndDate}
                onChangeEndDate={setTaskRecEndDate}
                repeatFrom={taskRecRepeatFrom}
                onChangeRepeatFrom={setTaskRecRepeatFrom}
                dueDate={taskDueDate}
                scheduledDate={taskScheduledDate}
                errors={taskRecurrenceErrors}
              />

              {taskFormError && (
                <p className="text-[11px] text-[var(--dw-error)] font-medium">
                  {taskFormError}
                </p>
              )}

              <div className="flex items-center justify-between pt-2">
                {editingTask ? (
                  <DaywellButton
                    label="Delete Task"
                    variant="text"
                    size="compact"
                    onClick={() => setPendingDeleteTask(editingTask)}
                    className="!text-[var(--dw-error)]"
                  />
                ) : (
                  <div />
                )}
                <div className="flex items-center gap-2">
                  <DaywellButton
                    label="Cancel"
                    variant="outlined"
                    size="compact"
                    onClick={() => setIsTaskModalOpen(false)}
                  />
                  <DaywellButton
                    type="submit"
                    label={editingTask ? 'Save Changes' : 'Add Task'}
                    variant="primary"
                    size="compact"
                  />
                </div>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Project Task Details Modal (Recurrence Controls & Metadata) */}
      {detailsTask && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Project Task Details"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs"
          onClick={(e) => {
            if (e.target === e.currentTarget) setDetailsTaskId(null);
          }}
        >
          <div className="w-full max-w-md bg-[var(--dw-elevated)] rounded-[var(--dw-radius-xl)] p-5 shadow-2xl border border-[var(--dw-border)] space-y-3.5 max-h-[90vh] overflow-y-auto">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0 space-y-1">
                <h3 className="dw-type-title text-[var(--dw-text-primary)]">
                  {detailsTask.title}
                </h3>
                <div className="flex flex-wrap items-center gap-1.5">
                  <DaywellStatusBadge
                    tone={isTaskCompleted(detailsTask) ? 'success' : 'neutral'}
                    showIcon={false}
                    label={
                      TASK_STATUS_LABELS[resolveEffectiveTaskStatus(detailsTask)]
                    }
                  />
                  <DaywellStatusBadge
                    tone={
                      detailsTask.priority === 'urgent'
                        ? 'error'
                        : detailsTask.priority === 'high'
                        ? 'warning'
                        : 'neutral'
                    }
                    showIcon={false}
                    label={TASK_PRIORITY_LABELS[detailsTask.priority]}
                  />
                  {detailsTask.milestoneId &&
                    milestoneById.get(detailsTask.milestoneId) && (
                      <DaywellStatusBadge
                        tone={
                          milestoneById.get(detailsTask.milestoneId)!.isCompleted
                            ? 'success'
                            : 'info'
                        }
                        showIcon={false}
                        label={milestoneById.get(detailsTask.milestoneId)!.title}
                      />
                    )}
                </div>
              </div>
              <DaywellIconButton
                label="Close project task details"
                size="compact"
                tone="muted"
                onClick={() => setDetailsTaskId(null)}
                icon={<X className="w-4 h-4" />}
              />
            </div>

            {detailsTask.description ? (
              <p className="text-xs text-[var(--dw-text-secondary)] whitespace-pre-wrap">
                {detailsTask.description}
              </p>
            ) : (
              <p className="text-xs italic text-[var(--dw-text-muted)]">
                No description added.
              </p>
            )}

            <div className="p-3 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] space-y-1 text-xs">
              <div className="flex items-center justify-between gap-2">
                <span className="text-[var(--dw-text-muted)]">Scheduled</span>
                <span className="font-semibold text-[var(--dw-text-primary)]">
                  {detailsTask.scheduledDate || 'Not set'}
                  {detailsTask.scheduledTime ? ` · ${detailsTask.scheduledTime}` : ''}
                </span>
              </div>
              <div className="flex items-center justify-between gap-2">
                <span className="text-[var(--dw-text-muted)]">Due Date</span>
                <span className="font-semibold text-[var(--dw-primary)]">
                  {detailsTask.dueDate || 'Not set'}
                </span>
              </div>
              {detailsTask.subtasks.length > 0 && (
                <div className="flex items-center justify-between gap-2">
                  <span className="text-[var(--dw-text-muted)]">Subtasks</span>
                  <span className="font-semibold text-[var(--dw-text-primary)]">
                    {computeSubtaskProgress(detailsTask.subtasks).completed}/
                    {computeSubtaskProgress(detailsTask.subtasks).total}
                  </span>
                </div>
              )}
              {detailsTask.completedAt && (
                <div className="flex items-center justify-between gap-2">
                  <span className="text-[var(--dw-text-muted)]">Completed</span>
                  <span className="font-semibold text-[var(--dw-text-primary)]">
                    {detailsTask.completedAt.slice(0, 10)}
                  </span>
                </div>
              )}
            </div>

            <TaskReminderDetailsPanel
              compact
              task={detailsTask}
              reminder={findReminderForTask(reminders, detailsTask.id)}
              onSaveReminder={(triggerTimeUtc) =>
                handleSaveDetailsReminder(detailsTask, triggerTimeUtc)
              }
              onRemoveReminder={() => handleRemoveDetailsReminder(detailsTask)}
            />

            <TaskRecurrenceDetailsPanel
              task={detailsTask}
              onSkipOccurrence={() => handleSkipDetailsRecurrence(detailsTask.id)}
              onRescheduleOccurrence={(nextIso) =>
                handleRescheduleDetailsRecurrence(detailsTask.id, nextIso)
              }
              onEditRecurrence={() => {
                setDetailsTaskId(null);
                openEditTask(detailsTask);
              }}
              onStopRecurrence={() => handleStopDetailsRecurrence(detailsTask.id)}
              actionError={detailsRecurrenceError}
            />

            <div className="flex items-center justify-between gap-2 pt-1">
              <DaywellButton
                label="Delete"
                variant="text"
                size="compact"
                onClick={() => {
                  const target = detailsTask;
                  setDetailsTaskId(null);
                  setPendingDeleteTask(target);
                }}
                className="!text-[var(--dw-error)]"
              />
              <div className="flex items-center gap-2">
                <DaywellButton
                  label="Edit Task"
                  variant="outlined"
                  size="compact"
                  onClick={() => {
                    const target = detailsTask;
                    setDetailsTaskId(null);
                    openEditTask(target);
                  }}
                />
                <DaywellButton
                  label="Done"
                  variant="primary"
                  size="compact"
                  onClick={() => setDetailsTaskId(null)}
                />
              </div>
            </div>
          </div>
        </div>
      )}

      <DaywellConfirmationDialog
        isOpen={Boolean(pendingDeleteSection)}
        title={`Remove section "${pendingDeleteSection?.title ?? ''}"?`}
        description="Tasks inside this section remain safely attached to your project under General."
        confirmLabel="Remove Section"
        destructive
        onCancel={() => setPendingDeleteSection(null)}
        onConfirm={handleConfirmDeleteSection}
      />

      <DaywellConfirmationDialog
        isOpen={Boolean(pendingDeleteTask)}
        title={`Delete task "${pendingDeleteTask?.title ?? ''}"?`}
        description="This permanently removes the task. You can undo immediately afterward."
        confirmLabel="Delete Task"
        destructive
        onCancel={() => setPendingDeleteTask(null)}
        onConfirm={handleConfirmDeleteTask}
      />
    </DaywellCard>
  );
}
