import React, { useState, useMemo, useRef } from 'react';
import { CalendarDate, EthiopiaClock, SharedDateFormatter } from '../domain/date';
import {
  Check,
  Plus,
  Flag,
  Bell,
  Repeat2,
  Calendar,
  Clock,
  Edit3,
  X,
  CheckCircle2,
  AlertTriangle,
  Loader2,
  Archive,
  RotateCcw,
  Trash2,
  ArrowUp,
  ArrowDown,
} from 'lucide-react';
import { isFormDirty } from '../domain/formValidationAndNavigation';
import {
  SharedMilestone,
  SharedProject,
  SharedTaskStatus,
} from '../domain/sharedFoundation';
import {
  addSubtaskToList,
  addSubtaskToTask,
  CANONICAL_TASK_PRIORITIES,
  CANONICAL_TASK_STATUSES,
  computeSubtaskProgress,
  computeTaskTabCounts,
  createTaskRecord,
  DaywellTaskRecord,
  deleteSubtaskFromList,
  deleteSubtaskFromTask,
  deleteTaskFromList,
  filterTasksForView,
  isTaskCompleted,
  reorderSubtasksInList,
  reorderTaskSubtasks,
  resolveEffectiveTaskStatus,
  setTaskArchivedRecord,
  TASK_PRIORITY_LABELS,
  TASK_STATUS_LABELS,
  TaskSortBy,
  TaskSubItemRecord,
  TaskViewFilter,
  toggleSubtaskInList,
  toggleTaskCompletionRecord,
  toggleTaskSubtask,
  updateSubtaskTitleInList,
  updateTaskRecord,
  updateTaskSubtaskTitle,
} from '../domain/taskOperations';
import { projectsService } from '../services/projectsService';
import { SharedStateBridge } from '../services/sharedStateBridge';
import { ProjectsWorkspaceView } from './projects';
import { UnsavedChangesDialog } from './UnsavedChangesDialog';
import {
  DaywellButton,
  DaywellCard,
  DaywellConfirmationDialog,
  DaywellEmptyState,
  DaywellIconButton,
  DaywellProgressBar,
  DaywellSearchField,
  DaywellStatusBadge,
  DaywellStatusBanner,
  DaywellStatusTone,
} from './ui';

export type TaskSubItem = TaskSubItemRecord;
export type DaywellTask = DaywellTaskRecord;

interface DaywellTasksModuleProps {
  tasks: DaywellTask[];
  onUpdateTasks: (updated: DaywellTask[]) => void;
  onRequestQuickCapture?: () => void;
  onNavigateToCalendar?: (dateStr: string) => void;
  activeSubTab?: 'tasks' | 'projects';
  onSubTabChange?: (tab: 'tasks' | 'projects') => void;
  selectedProjectId?: string | null;
  onSelectProjectId?: (projectId: string | null) => void;
}

const DEFAULT_SAMPLE_TASKS: DaywellTask[] = [
  {
    id: 't-1',
    title: 'Review portfolio case study & submit deck',
    description: 'Ensure metrics on onboarding friction and retention are highlighted.',
    category: 'Portfolio refresh',
    priority: 'urgent',
    completed: false,
    dueDate: CalendarDate.today().toIsoString(),
    scheduledDate: CalendarDate.today().toIsoString(),
    scheduledTime: '10:00',
    hasReminder: true,
    projectName: 'Portfolio refresh',
    subtasks: [
      { id: 'st-1', title: 'Export high-res Figma frames', completed: true },
      { id: 'st-2', title: 'Proofread Amharic & English translations', completed: false },
      { id: 'st-3', title: 'Upload final PDF to drive', completed: false },
    ],
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  },
  {
    id: 't-2',
    title: 'Book annual dental checkup',
    description: 'Call clinic around Bole Medhanialem for morning appointment.',
    category: 'Health first',
    priority: 'high',
    completed: false,
    dueDate: CalendarDate.today().toIsoString(),
    hasReminder: false,
    projectName: 'Personal',
    subtasks: [],
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  },
  {
    id: 't-3',
    title: 'Call Mom & check on family',
    description: 'Weekly video call.',
    category: 'Relationships',
    priority: 'medium',
    completed: false,
    dueDate: CalendarDate.today().toIsoString(),
    scheduledTime: '18:00',
    hasReminder: true,
    isRecurring: true,
    recurringRule: 'weekly',
    projectName: 'Relationships',
    subtasks: [],
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  },
  {
    id: 't-4',
    title: 'Read 20 pages of architecture handbook',
    description: 'Chapter 4: Event-driven local-first architectures.',
    category: 'Learning',
    priority: 'low',
    completed: false,
    scheduledDate: CalendarDate.today().toIsoString(),
    scheduledTime: '21:00',
    hasReminder: true,
    isRecurring: true,
    recurringRule: 'daily',
    projectName: 'Reading 2025',
    subtasks: [],
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  },
  {
    id: 't-5',
    title: 'Clear weekend communication inbox',
    category: 'Personal',
    status: 'completed',
    priority: 'medium',
    completed: true,
    completedAt: EthiopiaClock.nowUtc().toISOString(),
    dueDate: CalendarDate.today().toIsoString(),
    hasReminder: false,
    projectName: 'Personal',
    subtasks: [],
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  },
  {
    id: 't-6',
    title: 'Reconcile Ethiopian Birr bank statements',
    description: 'Check CBE and Telebirr balances against Daywell ledger.',
    category: 'Finance',
    priority: 'high',
    completed: false,
    dueDate: CalendarDate.today().addDays(2).toIsoString(),
    hasReminder: true,
    projectName: 'Financial Peace',
    subtasks: [
      { id: 'st-4', title: 'Export CBE Mobile Statement', completed: false },
      { id: 'st-5', title: 'Verify active loan repayments', completed: false },
    ],
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  },
  {
    id: 't-7',
    title: 'Ask landlord about water supply schedule',
    description: 'Captured in inbox — need to assign date.',
    priority: 'medium',
    completed: false,
    hasReminder: false,
    subtasks: [],
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  },
];

export function DaywellTasksModule({
  tasks,
  onUpdateTasks,
  activeSubTab: controlledSubTab,
  onSubTabChange,
  selectedProjectId: controlledProjectId,
  onSelectProjectId,
}: DaywellTasksModuleProps) {
  const [internalSubTab, setInternalSubTab] = useState<'tasks' | 'projects'>('tasks');
  const [internalProjectId, setInternalProjectId] = useState<string | null>(null);
  const [projectCreateTrigger, setProjectCreateTrigger] = useState(0);

  const subTab = controlledSubTab ?? internalSubTab;
  const setSubTab = (next: 'tasks' | 'projects') => {
    if (onSubTabChange) onSubTabChange(next);
    else setInternalSubTab(next);
  };

  const selectedProjectId =
    controlledProjectId !== undefined ? controlledProjectId : internalProjectId;
  const setSelectedProjectId = (next: string | null) => {
    if (onSelectProjectId) onSelectProjectId(next);
    else setInternalProjectId(next);
  };

  // Filter tab: 'today' | 'inbox' | 'upcoming' | 'all' | 'completed' | 'archived'
  const [activeFilter, setActiveFilter] = useState<TaskViewFilter>('today');

  // Search & Sorting
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState<TaskSortBy>('priority');

  // Task Details & Form Modals (View Details, Create, Edit, Safe Delete Confirm)
  const [detailTaskId, setDetailTaskId] = useState<string | null>(null);
  const [pendingDeleteTask, setPendingDeleteTask] = useState<DaywellTask | null>(null);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingTaskId, setEditingTaskId] = useState<string | null>(null);

  // Form Fields
  const [formTitle, setFormTitle] = useState('');
  const [formDescription, setFormDescription] = useState('');
  const [formPriority, setFormPriority] = useState<DaywellTask['priority']>('medium');
  const [formStatus, setFormStatus] = useState<SharedTaskStatus>('not_started');
  const [formDueDate, setFormDueDate] = useState<string>('');
  const [formScheduledDate, setFormScheduledDate] = useState<string>('');
  const [formScheduledTime, setFormScheduledTime] = useState<string>('');
  const [formProject, setFormProject] = useState<string>('Personal');
  const [formProjectId, setFormProjectId] = useState<string>('');
  const [formMilestoneId, setFormMilestoneId] = useState<string>('');
  const [formHasReminder, setFormHasReminder] = useState<boolean>(false);
  const [formIsRecurring, setFormIsRecurring] = useState<boolean>(false);
  const [formRecurringRule, setFormRecurringRule] = useState<'daily' | 'weekly' | 'monthly'>('daily');
  const [formSubtasks, setFormSubtasks] = useState<TaskSubItem[]>([]);
  const [newSubtaskInput, setNewSubtaskInput] = useState('');
  const [formSubtaskError, setFormSubtaskError] = useState('');
  const [editingFormSubtaskId, setEditingFormSubtaskId] = useState<string | null>(null);
  const [editingFormSubtaskTitle, setEditingFormSubtaskTitle] = useState('');
  const [editingFormSubtaskError, setEditingFormSubtaskError] = useState('');

  // Task Details inline subtask controls
  const [detailSubtaskInput, setDetailSubtaskInput] = useState('');
  const [detailSubtaskError, setDetailSubtaskError] = useState('');
  const [editingDetailSubtaskId, setEditingDetailSubtaskId] = useState<string | null>(null);
  const [editingDetailSubtaskTitle, setEditingDetailSubtaskTitle] = useState('');
  const [editingDetailSubtaskError, setEditingDetailSubtaskError] = useState('');

  // Form Validation & Dirty State
  const [formErrors, setFormErrors] = useState<Record<string, string>>({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [showUnsavedPrompt, setShowUnsavedPrompt] = useState(false);
  const [initialTaskValues, setInitialTaskValues] = useState<Record<string, unknown> | null>(null);
  const titleInputRef = useRef<HTMLInputElement>(null);

  const openTaskDetails = (taskId: string) => {
    setDetailTaskId(taskId);
    setDetailSubtaskInput('');
    setDetailSubtaskError('');
    setEditingDetailSubtaskId(null);
    setEditingDetailSubtaskTitle('');
    setEditingDetailSubtaskError('');
  };

  const availableProjects: SharedProject[] = useMemo(() => {
    if (!isModalOpen) return [];
    return projectsService.listProjects({ includeArchived: false });
  }, [isModalOpen]);

  const availableMilestones: SharedMilestone[] = useMemo(() => {
    if (!isModalOpen || !formProjectId.trim()) return [];
    return projectsService.listMilestones(formProjectId.trim());
  }, [isModalOpen, formProjectId]);

  const detailTask = useMemo(
    () => (detailTaskId ? tasks.find((t) => t.id === detailTaskId) ?? null : null),
    [detailTaskId, tasks]
  );

  const detailMilestoneTitle = useMemo(() => {
    if (!detailTask?.projectId || !detailTask?.milestoneId) return null;
    return (
      projectsService
        .listMilestones(detailTask.projectId)
        .find((m) => m.id === detailTask.milestoneId)?.title ?? null
    );
  }, [detailTask?.projectId, detailTask?.milestoneId]);

  // Undo Toast state
  const [undoToast, setUndoToast] = useState<{ message: string; undoAction: () => void } | null>(null);

  const triggerUndo = (message: string, undoAction: () => void) => {
    setUndoToast({ message, undoAction });
    setTimeout(() => {
      setUndoToast((cur) => (cur?.message === message ? null : cur));
    }, 5000);
  };

  const todayStr = useMemo(() => CalendarDate.today().toIsoString(), []);

  // Filter tasks
  const filteredTasks = useMemo(
    () =>
      filterTasksForView(tasks, {
        viewFilter: activeFilter,
        searchQuery,
        sortBy,
        todayIso: todayStr,
      }),
    [tasks, activeFilter, searchQuery, sortBy, todayStr]
  );

  // Counts for tabs
  const tabCounts = useMemo(
    () => computeTaskTabCounts(tasks, todayStr),
    [tasks, todayStr]
  );

  // Toggle Task Completion (Complete / Reopen with Undo)
  const toggleTask = (taskId: string) => {
    const prev = [...tasks];
    const target = tasks.find((t) => t.id === taskId);
    if (!target) return;

    const wasCompleted = isTaskCompleted(target);
    const updated = tasks.map((t) =>
      t.id === taskId ? toggleTaskCompletionRecord(t) : t
    );

    onUpdateTasks(updated);
    triggerUndo(
      wasCompleted ? `Reopened "${target.title}"` : `Completed "${target.title}"`,
      () => onUpdateTasks(prev)
    );
  };

  // Archive / Restore Task with Undo
  const handleToggleArchive = (task: DaywellTask) => {
    const prev = [...tasks];
    const nextArchived = !task.isArchived;
    const updated = tasks.map((t) =>
      t.id === task.id ? setTaskArchivedRecord(t, nextArchived) : t
    );
    onUpdateTasks(updated);
    if (nextArchived && detailTaskId === task.id) {
      setDetailTaskId(null);
    }
    triggerUndo(
      nextArchived ? `Archived "${task.title}"` : `Restored "${task.title}"`,
      () => onUpdateTasks(prev)
    );
  };

  // Subtask workflows on persisted tasks (Task Card & Task Details)
  const toggleSubtask = (taskId: string, subtaskId: string) => {
    const updated = tasks.map((t) =>
      t.id === taskId ? toggleTaskSubtask(t, subtaskId) : t
    );
    onUpdateTasks(updated);
  };

  const handleAddDetailSubtask = (taskId: string) => {
    const target = tasks.find((t) => t.id === taskId);
    if (!target) return;
    const res = addSubtaskToTask(target, detailSubtaskInput);
    if (!res.ok) {
      setDetailSubtaskError(res.error);
      return;
    }
    onUpdateTasks(tasks.map((t) => (t.id === taskId ? res.task : t)));
    setDetailSubtaskInput('');
    setDetailSubtaskError('');
  };

  const handleSaveDetailSubtaskEdit = (taskId: string, subtaskId: string) => {
    const target = tasks.find((t) => t.id === taskId);
    if (!target) return;
    const res = updateTaskSubtaskTitle(target, subtaskId, editingDetailSubtaskTitle);
    if (!res.ok) {
      setEditingDetailSubtaskError(res.error);
      return;
    }
    onUpdateTasks(tasks.map((t) => (t.id === taskId ? res.task : t)));
    setEditingDetailSubtaskId(null);
    setEditingDetailSubtaskTitle('');
    setEditingDetailSubtaskError('');
  };

  const handleReorderDetailSubtask = (
    taskId: string,
    fromIndex: number,
    toIndex: number
  ) => {
    const target = tasks.find((t) => t.id === taskId);
    if (!target) return;
    const nextTask = reorderTaskSubtasks(target, fromIndex, toIndex);
    onUpdateTasks(tasks.map((t) => (t.id === taskId ? nextTask : t)));
  };

  const handleDeleteDetailSubtask = (taskId: string, subtaskId: string) => {
    const prev = [...tasks];
    const target = tasks.find((t) => t.id === taskId);
    if (!target) return;
    const { task: nextTask, deleted } = deleteSubtaskFromTask(target, subtaskId);
    onUpdateTasks(tasks.map((t) => (t.id === taskId ? nextTask : t)));
    if (editingDetailSubtaskId === subtaskId) {
      setEditingDetailSubtaskId(null);
      setEditingDetailSubtaskTitle('');
      setEditingDetailSubtaskError('');
    }
    if (deleted) {
      triggerUndo(`Removed subtask "${deleted.title}"`, () => onUpdateTasks(prev));
    }
  };

  const getCurrentTaskValues = () => ({
    title: formTitle,
    description: formDescription,
    priority: formPriority,
    status: formStatus,
    dueDate: formDueDate,
    scheduledDate: formScheduledDate,
    scheduledTime: formScheduledTime,
    projectName: formProject,
    projectId: formProjectId,
    milestoneId: formMilestoneId,
    hasReminder: formHasReminder,
    isRecurring: formIsRecurring,
    recurringRule: formRecurringRule,
    subtasks: formSubtasks,
  });

  const handleAttemptClose = () => {
    if (initialTaskValues && isFormDirty(initialTaskValues, getCurrentTaskValues())) {
      setShowUnsavedPrompt(true);
    } else {
      setIsModalOpen(false);
      setFormErrors({});
    }
  };

  // Open Create Modal
  const handleOpenCreate = () => {
    setEditingTaskId(null);
    setFormTitle('');
    setFormDescription('');
    setFormPriority('medium');
    const initStatus: SharedTaskStatus =
      activeFilter === 'inbox' ? 'inbox' : 'not_started';
    const initDueDate = activeFilter === 'today' ? todayStr : '';
    const initScheduledDate = activeFilter === 'today' ? todayStr : '';
    setFormStatus(initStatus);
    setFormDueDate(initDueDate);
    setFormScheduledDate(initScheduledDate);
    setFormScheduledTime('');
    setFormProject('Personal');
    setFormProjectId('');
    setFormMilestoneId('');
    setFormHasReminder(false);
    setFormIsRecurring(false);
    setFormRecurringRule('daily');
    setFormSubtasks([]);
    setNewSubtaskInput('');
    setFormSubtaskError('');
    setEditingFormSubtaskId(null);
    setEditingFormSubtaskTitle('');
    setEditingFormSubtaskError('');
    setFormErrors({});
    setIsSubmitting(false);

    setInitialTaskValues({
      title: '',
      description: '',
      priority: 'medium',
      status: initStatus,
      dueDate: initDueDate,
      scheduledDate: initScheduledDate,
      scheduledTime: '',
      projectName: 'Personal',
      projectId: '',
      milestoneId: '',
      hasReminder: false,
      isRecurring: false,
      recurringRule: 'daily',
      subtasks: [],
    });

    setIsModalOpen(true);
    setTimeout(() => {
      titleInputRef.current?.focus();
    }, 60);
  };

  // Open Edit Modal
  const handleOpenEdit = (task: DaywellTask) => {
    const effectiveStatus = resolveEffectiveTaskStatus(task);
    setDetailTaskId(null);
    setEditingTaskId(task.id);
    setFormTitle(task.title);
    setFormDescription(task.description || '');
    setFormPriority(task.priority);
    setFormStatus(effectiveStatus);
    setFormDueDate(task.dueDate || '');
    setFormScheduledDate(task.scheduledDate || '');
    setFormScheduledTime(task.scheduledTime || '');
    setFormProject(task.projectName || 'Personal');
    setFormProjectId(task.projectId || '');
    setFormMilestoneId(task.milestoneId || '');
    setFormHasReminder(task.hasReminder);
    setFormIsRecurring(task.isRecurring || false);
    setFormRecurringRule(task.recurringRule || 'daily');
    const subtasksCopy = [...task.subtasks];
    setFormSubtasks(subtasksCopy);
    setNewSubtaskInput('');
    setFormSubtaskError('');
    setEditingFormSubtaskId(null);
    setEditingFormSubtaskTitle('');
    setEditingFormSubtaskError('');
    setFormErrors({});
    setIsSubmitting(false);

    setInitialTaskValues({
      title: task.title,
      description: task.description || '',
      priority: task.priority,
      status: effectiveStatus,
      dueDate: task.dueDate || '',
      scheduledDate: task.scheduledDate || '',
      scheduledTime: task.scheduledTime || '',
      projectName: task.projectName || 'Personal',
      projectId: task.projectId || '',
      milestoneId: task.milestoneId || '',
      hasReminder: task.hasReminder,
      isRecurring: task.isRecurring || false,
      recurringRule: task.recurringRule || 'daily',
      subtasks: subtasksCopy,
    });

    setIsModalOpen(true);
    setTimeout(() => {
      titleInputRef.current?.focus();
    }, 60);
  };

  // Save Task (Create or Update)
  const handleSaveTask = (e: React.FormEvent) => {
    e.preventDefault();
    if (isSubmitting) return;

    const prev = [...tasks];
    const cleanProjectId = formProjectId.trim() || undefined;
    const matchedProject = cleanProjectId
      ? projectsService.getProject(cleanProjectId)
      : undefined;
    const resolvedProjectName =
      matchedProject?.title ?? (formProject.trim() || 'Personal');

    const cleanMilestoneId = cleanProjectId
      ? formMilestoneId.trim() || undefined
      : undefined;

    if (editingTaskId) {
      const existing = tasks.find((t) => t.id === editingTaskId);
      if (!existing) return;

      const result = updateTaskRecord(existing, {
        title: formTitle,
        description: formDescription,
        priority: formPriority,
        status: formStatus,
        dueDate: formDueDate,
        scheduledDate: formScheduledDate,
        scheduledTime: formScheduledTime,
        projectId: cleanProjectId,
        milestoneId: cleanMilestoneId,
        projectName: resolvedProjectName,
        hasReminder: formHasReminder,
        isRecurring: formIsRecurring,
        recurringRule: formIsRecurring ? formRecurringRule : undefined,
        recurrenceRule: formIsRecurring ? formRecurringRule : undefined,
        subtasks: formSubtasks,
      });

      if (!result.ok) {
        setFormErrors(result.errors);
        if (result.errors.title) titleInputRef.current?.focus();
        return;
      }

      setIsSubmitting(true);
      const updated = tasks.map((t) =>
        t.id === editingTaskId ? result.task : t
      );
      onUpdateTasks(updated);
      if (existing.projectId && existing.projectId !== cleanProjectId) {
        projectsService.cleanupSectionLinksForTask(existing.id);
      }
      setIsSubmitting(false);
      setIsModalOpen(false);
      setFormErrors({});
      triggerUndo('Task updated', () => onUpdateTasks(prev));
    } else {
      const result = createTaskRecord({
        title: formTitle,
        description: formDescription,
        priority: formPriority,
        status: formStatus,
        dueDate: formDueDate,
        scheduledDate: formScheduledDate,
        scheduledTime: formScheduledTime,
        projectId: cleanProjectId,
        milestoneId: cleanMilestoneId,
        projectName: resolvedProjectName,
        category: resolvedProjectName,
        hasReminder: formHasReminder,
        isRecurring: formIsRecurring,
        recurringRule: formIsRecurring ? formRecurringRule : undefined,
        recurrenceRule: formIsRecurring ? formRecurringRule : undefined,
        subtasks: formSubtasks,
      });

      if (!result.ok) {
        setFormErrors(result.errors);
        if (result.errors.title) titleInputRef.current?.focus();
        return;
      }

      setIsSubmitting(true);
      onUpdateTasks([result.task, ...tasks]);
      setIsSubmitting(false);
      setIsModalOpen(false);
      setFormErrors({});
      triggerUndo(`Added "${result.task.title}"`, () => onUpdateTasks(prev));
    }
  };

  // Delete Task (confirmed safely, with Undo + DailyPlanningEntries cleanup)
  const executeDeleteTask = (taskId: string) => {
    const prev = [...tasks];
    const { remaining, deleted } = deleteTaskFromList(tasks, taskId);
    const prevDailyPlanningRaw =
      typeof window !== 'undefined'
        ? localStorage.getItem(SharedStateBridge.DAILY_PLANNING_STORAGE_KEY)
        : null;
    onUpdateTasks(remaining);
    SharedStateBridge.removeDailyPlanningForTask(taskId);
    projectsService.cleanupSectionLinksForTask(taskId);
    setPendingDeleteTask(null);
    setDetailTaskId(null);
    setIsModalOpen(false);
    triggerUndo(`Deleted "${deleted?.title || 'task'}"`, () => {
      if (prevDailyPlanningRaw !== null && typeof window !== 'undefined') {
        try {
          localStorage.setItem(
            SharedStateBridge.DAILY_PLANNING_STORAGE_KEY,
            prevDailyPlanningRaw
          );
        } catch {}
      }
      onUpdateTasks(prev);
    });
  };

  // Subtask builder helpers (Create / Edit modal)
  const handleAddSubtask = () => {
    const res = addSubtaskToList(
      formSubtasks,
      newSubtaskInput,
      editingTaskId || 'draft'
    );
    if (!res.ok) {
      setFormSubtaskError(res.error);
      return;
    }
    setFormSubtasks(res.subtasks);
    setNewSubtaskInput('');
    setFormSubtaskError('');
  };

  const handleToggleFormSubtask = (stId: string) => {
    setFormSubtasks(toggleSubtaskInList(formSubtasks, stId));
  };

  const handleSaveFormSubtaskEdit = (stId: string) => {
    const res = updateSubtaskTitleInList(
      formSubtasks,
      stId,
      editingFormSubtaskTitle
    );
    if (!res.ok) {
      setEditingFormSubtaskError(res.error);
      return;
    }
    setFormSubtasks(res.subtasks);
    setEditingFormSubtaskId(null);
    setEditingFormSubtaskTitle('');
    setEditingFormSubtaskError('');
  };

  const handleReorderFormSubtask = (fromIndex: number, toIndex: number) => {
    setFormSubtasks(reorderSubtasksInList(formSubtasks, fromIndex, toIndex));
  };

  const handleRemoveSubtask = (stId: string) => {
    const { remaining } = deleteSubtaskFromList(formSubtasks, stId);
    setFormSubtasks(remaining);
    if (editingFormSubtaskId === stId) {
      setEditingFormSubtaskId(null);
      setEditingFormSubtaskTitle('');
      setEditingFormSubtaskError('');
    }
  };

  return (
    <div className="space-y-4">
      {/* Undo Toast */}
      {undoToast && (
        <div
          role="status"
          aria-live="polite"
          className="fixed bottom-20 left-1/2 -translate-x-1/2 z-50 flex items-center gap-3 px-4 py-2.5 bg-[var(--dw-elevated)] text-[var(--dw-text-primary)] border border-[var(--dw-border)] text-xs rounded-[var(--dw-radius-lg)] shadow-xl"
        >
          <span>{undoToast.message}</span>
          <DaywellButton
            label="Undo"
            variant="text"
            size="compact"
            onClick={() => {
              undoToast.undoAction();
              setUndoToast(null);
            }}
            className="uppercase tracking-wider"
          />
        </div>
      )}

      {/* Top Bar & Segmented Switcher (hidden while drilled into a specific ProjectDetailView) */}
      {!(subTab === 'projects' && selectedProjectId) && (
        <>
          <div className="flex items-start justify-between pt-1">
            <div>
              <div className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
                {subTab === 'projects'
                  ? 'MAKE ROOM FOR THE MEANINGFUL'
                  : 'A CLEAR NEXT STEP'}
              </div>
              <h1 className="dw-type-display text-[var(--dw-text-primary)]">
                {subTab === 'projects' ? 'Projects' : 'Tasks'}
              </h1>
            </div>
            <DaywellIconButton
              label={subTab === 'projects' ? 'New Project' : 'Add New Task'}
              tone="primary"
              onClick={() => {
                if (subTab === 'projects') {
                  setProjectCreateTrigger((n) => n + 1);
                } else {
                  handleOpenCreate();
                }
              }}
              icon={<Plus className="w-5 h-5 stroke-[2.5]" />}
              className="bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] hover:opacity-90"
            />
          </div>

          <div
            role="tablist"
            aria-label="Tasks module sections"
            className="grid grid-cols-2 gap-1 p-1 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)]"
          >
            {(
              [
                { id: 'tasks', label: 'Tasks' },
                { id: 'projects', label: 'Projects' },
              ] as const
            ).map((tab) => {
              const active = subTab === tab.id;
              return (
                <button
                  key={tab.id}
                  type="button"
                  role="tab"
                  aria-selected={active}
                  onClick={() => {
                    setSubTab(tab.id);
                    if (tab.id === 'tasks') setSelectedProjectId(null);
                  }}
                  className={`min-h-[38px] text-xs font-bold rounded-[var(--dw-radius-sm)] transition-all cursor-pointer ${
                    active
                      ? 'bg-[var(--dw-card)] text-[var(--dw-text-primary)] shadow-xs border border-[var(--dw-border)]'
                      : 'text-[var(--dw-text-secondary)] hover:text-[var(--dw-text-primary)]'
                  }`}
                >
                  {tab.label}
                </button>
              );
            })}
          </div>
        </>
      )}

      {subTab === 'projects' ? (
        <ProjectsWorkspaceView
          selectedProjectId={selectedProjectId}
          onSelectProjectId={setSelectedProjectId}
          externalCreateTrigger={projectCreateTrigger}
        />
      ) : (
        <>
          {/* Search Bar & Sorter */}
          <div className="flex items-center gap-2">
            <DaywellSearchField
              value={searchQuery}
              onChange={setSearchQuery}
              placeholder="Search your tasks and projects..."
              ariaLabel="Search tasks and projects"
              className="flex-1"
            />
            <select
              aria-label="Sort tasks by"
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value as 'priority' | 'time' | 'title')}
              className="min-h-[42px] text-xs bg-[var(--dw-card)] border border-[var(--dw-border)] rounded-[var(--dw-radius-md)] px-3 py-2 text-[var(--dw-text-secondary)] outline-none focus:border-[var(--dw-primary)]"
            >
              <option value="priority">Priority</option>
              <option value="time">Time</option>
              <option value="title">Alphabetical</option>
            </select>
          </div>

          {/* Filter Tabs */}
          <div className="flex items-center gap-1.5 overflow-x-auto pb-0.5" role="tablist" aria-label="Task views">
            {(
              [
                { id: 'today', label: `Today (${tabCounts.todayCount})` },
                { id: 'inbox', label: `Inbox (${tabCounts.inboxCount})` },
                { id: 'upcoming', label: `Upcoming (${tabCounts.upcomingCount})` },
                { id: 'all', label: `All (${tabCounts.allCount})` },
                { id: 'completed', label: `Completed (${tabCounts.completedCount})` },
                { id: 'archived', label: `Archived (${tabCounts.archivedCount})` },
              ] as const
            ).map((tab) => {
              const active = activeFilter === tab.id;
              return (
                <button
                  key={tab.id}
                  type="button"
                  role="tab"
                  aria-selected={active}
                  onClick={() => setActiveFilter(tab.id)}
                  className={`min-h-[36px] text-xs px-3.5 py-1.5 rounded-[var(--dw-radius-full)] font-semibold transition-all shrink-0 cursor-pointer ${
                    active
                      ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)] font-bold'
                      : 'bg-[var(--dw-card)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)] hover:bg-[var(--dw-surface-subtle)]'
                  }`}
                >
                  {tab.label}
                </button>
              );
            })}
          </div>

          {/* Status Progress Header */}
          <div className="flex items-center justify-between pt-1">
            <div>
              <span className="dw-type-numeric-body text-xl font-bold text-[var(--dw-text-primary)]">
                {tabCounts.completedCount} of {tabCounts.allCount}
              </span>
              <p className="dw-type-label text-[var(--dw-text-muted)]">active tasks completed</p>
            </div>
            <DaywellStatusBadge
              tone="neutral"
              showIcon={false}
              label={`${activeFilter.toUpperCase()} · ${filteredTasks.length} ITEMS`}
            />
          </div>

      {/* Task List */}
      <div className="space-y-2 pt-1">
        {filteredTasks.length === 0 ? (
          <DaywellEmptyState
            icon={<CheckCircle2 className="w-8 h-8" />}
            message={activeFilter === 'archived' ? 'No archived tasks' : 'No tasks in this view'}
            subtitle={
              activeFilter === 'today'
                ? "You're all caught up for today! Plan tomorrow or capture a new task."
                : activeFilter === 'archived'
                  ? 'Tasks you archive appear here so you can restore or remove them anytime.'
                  : 'Nothing to display for this filter.'
            }
            actionLabel={activeFilter === 'archived' ? undefined : 'Add Task'}
            onActionPressed={activeFilter === 'archived' ? undefined : handleOpenCreate}
          />
        ) : (
          filteredTasks.map((task) => {
            const subProgress = computeSubtaskProgress(task.subtasks);
            const hasSubtasks = subProgress.total > 0;
            const effectiveStatus = resolveEffectiveTaskStatus(task);
            const taskCompleted = effectiveStatus === 'completed';

            return (
              <DaywellCard
                key={task.id}
                padding="sm"
                radius="lg"
                className="hover:border-[var(--dw-primary)]/40 transition-all space-y-2.5 group"
              >
                <div className="flex items-start gap-3">
                  {/* Complete Checkbox */}
                  <button
                    type="button"
                    aria-label={taskCompleted ? `Reopen ${task.title}` : `Complete ${task.title}`}
                    onClick={() => toggleTask(task.id)}
                    className={`w-5 h-5 rounded-[var(--dw-radius-sm)] border mt-0.5 flex items-center justify-center transition-colors shrink-0 cursor-pointer ${
                      taskCompleted
                        ? 'bg-[var(--dw-primary)] border-[var(--dw-primary)] text-[var(--dw-on-primary)]'
                        : 'border-[var(--dw-border)] hover:border-[var(--dw-primary)]'
                    }`}
                  >
                    {taskCompleted && <Check className="w-3.5 h-3.5 stroke-[3]" />}
                  </button>

                  {/* Task Content — opens Task Details */}
                  <div
                    role="button"
                    tabIndex={0}
                    onClick={() => openTaskDetails(task.id)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter' || e.key === ' ') {
                        e.preventDefault();
                        openTaskDetails(task.id);
                      }
                    }}
                    className="flex-1 min-w-0 cursor-pointer"
                  >
                    <p
                      className={`text-xs font-semibold leading-snug ${
                        taskCompleted
                          ? 'line-through text-[var(--dw-text-disabled)]'
                          : 'text-[var(--dw-text-primary)] group-hover:text-[var(--dw-primary)]'
                      }`}
                    >
                      {task.title}
                    </p>

                    {task.description && (
                      <p className="text-[11px] text-[var(--dw-text-muted)] line-clamp-1 mt-0.5">
                        {task.description}
                      </p>
                    )}

                    <div className="flex items-center flex-wrap gap-2 text-[11px] text-[var(--dw-text-muted)] mt-1">
                      {task.priority && (
                        <span
                          className={`flex items-center gap-1 font-bold ${
                            task.priority === 'urgent'
                              ? 'text-[var(--dw-error)]'
                              : task.priority === 'high'
                              ? 'text-[var(--dw-warning)]'
                              : 'text-[var(--dw-text-muted)]'
                          }`}
                        >
                          <Flag className="w-3 h-3" />
                          <span>{TASK_PRIORITY_LABELS[task.priority]}</span>
                        </span>
                      )}

                      {(effectiveStatus === 'in_progress' ||
                        effectiveStatus === 'cancelled' ||
                        effectiveStatus === 'inbox') && (
                        <DaywellStatusBadge
                          tone={
                            effectiveStatus === 'in_progress'
                              ? 'info'
                              : effectiveStatus === 'cancelled'
                                ? 'error'
                                : 'neutral'
                          }
                          showIcon={false}
                          label={TASK_STATUS_LABELS[effectiveStatus]}
                        />
                      )}

                      {task.isArchived && (
                        <DaywellStatusBadge
                          tone="warning"
                          showIcon={false}
                          label="Archived"
                        />
                      )}

                      {task.projectName && (
                        <span className="font-semibold text-[var(--dw-text-secondary)]">
                          {task.projectName}
                        </span>
                      )}

                      {task.scheduledDate && (
                        <span className="flex items-center gap-0.5 text-[var(--dw-text-secondary)]">
                          <Calendar className="w-3 h-3" />
                          Plan: {task.scheduledDate}
                        </span>
                      )}

                      {task.scheduledTime && (
                        <span className="flex items-center gap-0.5 text-[var(--dw-text-secondary)]">
                          <Clock className="w-3 h-3" />
                          {task.scheduledTime}
                        </span>
                      )}

                      {task.dueDate && (
                        <span className="flex items-center gap-0.5 text-[var(--dw-primary)] font-medium">
                          <Calendar className="w-3 h-3" />
                          Due: {task.dueDate}
                        </span>
                      )}
                    </div>
                  </div>

                  {/* Badges & Quick Actions */}
                  <div className="flex items-center gap-1 text-[var(--dw-text-muted)] shrink-0">
                    {task.hasReminder && <Bell className="w-3.5 h-3.5" aria-label="Has reminder" />}
                    {task.isRecurring && <Repeat2 className="w-3.5 h-3.5" aria-label="Recurring task" />}
                    {task.isArchived ? (
                      <>
                        <DaywellIconButton
                          label={`Restore ${task.title}`}
                          size="compact"
                          tone="primary"
                          onClick={() => handleToggleArchive(task)}
                          icon={<RotateCcw className="w-3.5 h-3.5" />}
                        />
                        <DaywellIconButton
                          label={`Delete ${task.title}`}
                          size="compact"
                          tone="danger"
                          onClick={() => setPendingDeleteTask(task)}
                          icon={<Trash2 className="w-3.5 h-3.5" />}
                        />
                      </>
                    ) : (
                      <DaywellIconButton
                        label={`Edit ${task.title}`}
                        size="compact"
                        tone="muted"
                        onClick={() => handleOpenEdit(task)}
                        icon={<Edit3 className="w-3.5 h-3.5" />}
                      />
                    )}
                  </div>
                </div>

                {/* Subtask checklist progress & items */}
                {hasSubtasks && (
                  <div className="pl-8 pt-1.5 space-y-1.5 border-t border-[var(--dw-divider)]">
                    <div className="flex items-center justify-between gap-3 text-[10px] text-[var(--dw-text-muted)]">
                      <span>
                        Checklist: {subProgress.completed} of {subProgress.total} done ({subProgress.percentage}%)
                      </span>
                      <DaywellProgressBar
                        value={subProgress.percentage}
                        label={`Subtask progress for ${task.title}`}
                        className="!w-24"
                      />
                    </div>
                    {task.subtasks.map((st) => (
                      <div
                        key={st.id}
                        onClick={() => toggleSubtask(task.id, st.id)}
                        className="flex items-center gap-2 text-xs text-[var(--dw-text-secondary)] cursor-pointer hover:text-[var(--dw-text-primary)]"
                      >
                        <div
                          className={`w-3.5 h-3.5 rounded border flex items-center justify-center ${
                            st.completed
                              ? 'bg-[var(--dw-primary)] border-[var(--dw-primary)] text-[var(--dw-on-primary)]'
                              : 'border-[var(--dw-border)]'
                          }`}
                        >
                          {st.completed && <Check className="w-2.5 h-2.5 stroke-[3]" />}
                        </div>
                        <span className={st.completed ? 'line-through text-[var(--dw-text-disabled)]' : ''}>
                          {st.title}
                        </span>
                      </div>
                    ))}
                  </div>
                )}
              </DaywellCard>
            );
          })
        )}
      </div>

      {/* Tip Card */}
      <DaywellStatusBanner
        tone="success"
        title="Capture first. Organize later."
        message="Your Inbox holds unorganized thoughts. Assign projects, due dates, and checklist items when you are ready to focus."
      />
        </>
      )}

      {/* TASK MODAL (Create & Edit) */}
      {isModalOpen && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={editingTaskId ? 'Edit Task' : 'Create New Task'}
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs"
          onClick={(e) => {
            if (e.target === e.currentTarget) handleAttemptClose();
          }}
        >
          <div className="w-full max-w-md bg-[var(--dw-elevated)] rounded-[var(--dw-radius-xl)] p-5 shadow-2xl border border-[var(--dw-border)] space-y-4 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <h2 className="dw-type-title text-[var(--dw-text-primary)]">
                {editingTaskId ? 'Edit Task' : 'Create New Task'}
              </h2>
              <DaywellIconButton
                label="Close task dialog"
                size="compact"
                tone="muted"
                onClick={handleAttemptClose}
                icon={<X className="w-4 h-4" />}
              />
            </div>

            <form onSubmit={handleSaveTask} className="space-y-3.5">
              <div>
                <label className="block dw-type-caption uppercase tracking-wider text-[var(--dw-text-secondary)] mb-1">
                  Task Title <span className="text-[var(--dw-error)]">*</span>
                </label>
                <input
                  ref={titleInputRef}
                  type="text"
                  placeholder="e.g. Prepare monthly tax receipts"
                  value={formTitle}
                  onChange={(e) => {
                    setFormTitle(e.target.value);
                    if (formErrors.title) {
                      setFormErrors((prev) => ({ ...prev, title: '' }));
                    }
                  }}
                  className={`w-full min-h-[42px] px-3.5 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)] transition-colors ${
                    formErrors.title ? 'border-[var(--dw-error)]' : 'border-[var(--dw-border)]'
                  }`}
                />
                {formErrors.title && (
                  <p className="text-[11px] text-[var(--dw-error)] font-medium mt-1 flex items-center gap-1">
                    <AlertTriangle className="w-3 h-3 shrink-0" />
                    <span>{formErrors.title}</span>
                  </p>
                )}
              </div>

              <div>
                <label className="block dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)] mb-1">
                  Description / Notes (Optional)
                </label>
                <textarea
                  rows={2}
                  placeholder="Additional context, sub-points or references..."
                  value={formDescription}
                  onChange={(e) => setFormDescription(e.target.value)}
                  className="w-full px-3.5 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                />
              </div>

              <div className="grid grid-cols-2 gap-2.5">
                <div>
                  <label className="block dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)] mb-1">
                    Priority
                  </label>
                  <select
                    aria-label="Priority"
                    value={formPriority}
                    onChange={(e) => setFormPriority(e.target.value as DaywellTask['priority'])}
                    className="w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  >
                    {CANONICAL_TASK_PRIORITIES.map((p) => (
                      <option key={p} value={p}>
                        {TASK_PRIORITY_LABELS[p]}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)] mb-1">
                    Status
                  </label>
                  <select
                    aria-label="Status"
                    value={formStatus}
                    onChange={(e) => setFormStatus(e.target.value as SharedTaskStatus)}
                    className="w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  >
                    {CANONICAL_TASK_STATUSES.map((s) => (
                      <option key={s} value={s}>
                        {TASK_STATUS_LABELS[s]}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div>
                <label className="block dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)] mb-1">
                  {availableProjects.length > 0 ? 'Linked Project (Optional)' : 'Project / Area (Optional)'}
                </label>
                {availableProjects.length > 0 ? (
                  <select
                    aria-label="Linked Project"
                    value={formProjectId}
                    onChange={(e) => {
                      const nextId = e.target.value;
                      setFormProjectId(nextId);
                      setFormMilestoneId('');
                      const found = availableProjects.find((p) => p.id === nextId);
                      setFormProject(found ? found.title : 'Personal');
                    }}
                    className="w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  >
                    <option value="">Personal / Inbox</option>
                    {availableProjects.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.title}
                      </option>
                    ))}
                  </select>
                ) : (
                  <input
                    type="text"
                    value={formProject}
                    onChange={(e) => setFormProject(e.target.value)}
                    placeholder="e.g. Portfolio refresh"
                    className="w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  />
                )}
              </div>

              {formProjectId && availableMilestones.length > 0 && (
                <div>
                  <label className="block dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)] mb-1">
                    Milestone (Optional)
                  </label>
                  <select
                    aria-label="Milestone"
                    value={formMilestoneId}
                    onChange={(e) => setFormMilestoneId(e.target.value)}
                    className="w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  >
                    <option value="">No milestone</option>
                    {availableMilestones.map((m) => (
                      <option key={m.id} value={m.id}>
                        {m.title}
                      </option>
                    ))}
                  </select>
                </div>
              )}

              <div className="grid grid-cols-2 gap-2.5">
                <div>
                  <div className="flex items-center justify-between mb-1">
                    <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)]">
                      Scheduled Date
                    </label>
                    {formScheduledDate && (
                      <button
                        type="button"
                        onClick={() => setFormScheduledDate('')}
                        className="text-[10px] font-semibold text-[var(--dw-primary)] hover:underline cursor-pointer"
                      >
                        Clear
                      </button>
                    )}
                  </div>
                  <input
                    aria-label="Scheduled Date"
                    type="date"
                    value={formScheduledDate}
                    onChange={(e) => {
                      setFormScheduledDate(e.target.value);
                      if (formErrors.scheduledDate) {
                        setFormErrors((prev) => ({ ...prev, scheduledDate: '' }));
                      }
                    }}
                    className={`w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)] ${
                      formErrors.scheduledDate ? 'border-[var(--dw-error)]' : 'border-[var(--dw-border)]'
                    }`}
                  />
                  {formErrors.scheduledDate && (
                    <p className="text-[11px] text-[var(--dw-error)] mt-1">{formErrors.scheduledDate}</p>
                  )}
                </div>
                <div>
                  <div className="flex items-center justify-between mb-1">
                    <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)]">
                      Due Date
                    </label>
                    {formDueDate && (
                      <button
                        type="button"
                        onClick={() => setFormDueDate('')}
                        className="text-[10px] font-semibold text-[var(--dw-primary)] hover:underline cursor-pointer"
                      >
                        Clear
                      </button>
                    )}
                  </div>
                  <input
                    aria-label="Due Date"
                    type="date"
                    value={formDueDate}
                    onChange={(e) => {
                      setFormDueDate(e.target.value);
                      if (formErrors.dueDate) {
                        setFormErrors((prev) => ({ ...prev, dueDate: '' }));
                      }
                    }}
                    className={`w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)] ${
                      formErrors.dueDate ? 'border-[var(--dw-error)]' : 'border-[var(--dw-border)]'
                    }`}
                  />
                  {formErrors.dueDate && (
                    <p className="text-[11px] text-[var(--dw-error)] mt-1">{formErrors.dueDate}</p>
                  )}
                </div>
              </div>

              <div>
                <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                  Scheduled Time (Optional)
                </label>
                <input
                  aria-label="Scheduled Time"
                  type="time"
                  value={formScheduledTime}
                  onChange={(e) => setFormScheduledTime(e.target.value)}
                  className="w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                />
              </div>

              {/* Subtasks checklist builder */}
              <div className="space-y-2 pt-2 border-t border-[var(--dw-divider)]">
                <div className="flex items-center justify-between gap-2">
                  <label className="block dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
                    Checklist / Subtasks (Optional)
                  </label>
                  {formSubtasks.length > 0 && (() => {
                    const draftProg = computeSubtaskProgress(formSubtasks);
                    return (
                      <span className="text-[11px] font-semibold text-[var(--dw-text-secondary)]">
                        {draftProg.completed} of {draftProg.total} done ({draftProg.percentage}%)
                      </span>
                    );
                  })()}
                </div>
                {formSubtasks.length > 0 && (
                  <DaywellProgressBar
                    value={computeSubtaskProgress(formSubtasks).percentage}
                    label="Draft subtask progress"
                  />
                )}
                <div className="flex items-center gap-2">
                  <input
                    aria-label="Add draft subtask"
                    type="text"
                    placeholder="Add subtask..."
                    value={newSubtaskInput}
                    onChange={(e) => {
                      setNewSubtaskInput(e.target.value);
                      if (formSubtaskError) setFormSubtaskError('');
                    }}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        e.preventDefault();
                        handleAddSubtask();
                      }
                    }}
                    className={`flex-1 min-h-[38px] px-3 py-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)] ${
                      formSubtaskError ? 'border-[var(--dw-error)]' : 'border-[var(--dw-border)]'
                    }`}
                  />
                  <DaywellButton
                    label="Add"
                    variant="tonal"
                    size="compact"
                    onClick={handleAddSubtask}
                  />
                </div>
                {formSubtaskError && (
                  <p className="text-[11px] text-[var(--dw-error)]">{formSubtaskError}</p>
                )}

                {formSubtasks.length > 0 && (
                  <div className="space-y-1.5 max-h-44 overflow-y-auto">
                    {formSubtasks.map((st, idx) => {
                      const isEditingSub = editingFormSubtaskId === st.id;
                      return (
                        <div
                          key={st.id}
                          className="p-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] space-y-1"
                        >
                          {isEditingSub ? (
                            <div className="space-y-1">
                              <div className="flex items-center gap-1.5">
                                <input
                                  aria-label={`Edit draft subtask ${st.title}`}
                                  type="text"
                                  value={editingFormSubtaskTitle}
                                  onChange={(e) => {
                                    setEditingFormSubtaskTitle(e.target.value);
                                    if (editingFormSubtaskError) setEditingFormSubtaskError('');
                                  }}
                                  onKeyDown={(e) => {
                                    if (e.key === 'Enter') {
                                      e.preventDefault();
                                      handleSaveFormSubtaskEdit(st.id);
                                    } else if (e.key === 'Escape') {
                                      e.preventDefault();
                                      setEditingFormSubtaskId(null);
                                      setEditingFormSubtaskTitle('');
                                      setEditingFormSubtaskError('');
                                    }
                                  }}
                                  className="flex-1 min-h-[32px] px-2.5 py-1 bg-[var(--dw-card)] rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                                />
                                <DaywellIconButton
                                  label={`Save draft subtask ${st.title}`}
                                  size="compact"
                                  tone="primary"
                                  onClick={() => handleSaveFormSubtaskEdit(st.id)}
                                  icon={<Check className="w-3.5 h-3.5" />}
                                />
                                <DaywellIconButton
                                  label="Cancel editing draft subtask"
                                  size="compact"
                                  tone="muted"
                                  onClick={() => {
                                    setEditingFormSubtaskId(null);
                                    setEditingFormSubtaskTitle('');
                                    setEditingFormSubtaskError('');
                                  }}
                                  icon={<X className="w-3.5 h-3.5" />}
                                />
                              </div>
                              {editingFormSubtaskError && (
                                <p className="text-[11px] text-[var(--dw-error)]">
                                  {editingFormSubtaskError}
                                </p>
                              )}
                            </div>
                          ) : (
                            <div className="flex items-center justify-between gap-2 text-xs">
                              <div className="flex items-center gap-2 flex-1 min-w-0">
                                <button
                                  type="button"
                                  aria-label={`Toggle draft subtask ${st.title}`}
                                  onClick={() => handleToggleFormSubtask(st.id)}
                                  className={`w-4 h-4 rounded border flex items-center justify-center shrink-0 cursor-pointer ${
                                    st.completed
                                      ? 'bg-[var(--dw-primary)] border-[var(--dw-primary)] text-[var(--dw-on-primary)]'
                                      : 'border-[var(--dw-border)] bg-[var(--dw-card)]'
                                  }`}
                                >
                                  {st.completed && <Check className="w-3 h-3 stroke-[3]" />}
                                </button>
                                <span
                                  className={`truncate ${
                                    st.completed
                                      ? 'line-through text-[var(--dw-text-disabled)]'
                                      : 'text-[var(--dw-text-primary)]'
                                  }`}
                                >
                                  {st.title}
                                </span>
                              </div>
                              <div className="flex items-center gap-0.5 shrink-0">
                                <DaywellIconButton
                                  label={`Move draft subtask up ${st.title}`}
                                  size="compact"
                                  tone="muted"
                                  disabled={idx === 0}
                                  onClick={() => handleReorderFormSubtask(idx, idx - 1)}
                                  icon={<ArrowUp className="w-3.5 h-3.5" />}
                                />
                                <DaywellIconButton
                                  label={`Move draft subtask down ${st.title}`}
                                  size="compact"
                                  tone="muted"
                                  disabled={idx === formSubtasks.length - 1}
                                  onClick={() => handleReorderFormSubtask(idx, idx + 1)}
                                  icon={<ArrowDown className="w-3.5 h-3.5" />}
                                />
                                <DaywellIconButton
                                  label={`Edit draft subtask ${st.title}`}
                                  size="compact"
                                  tone="muted"
                                  onClick={() => {
                                    setEditingFormSubtaskId(st.id);
                                    setEditingFormSubtaskTitle(st.title);
                                    setEditingFormSubtaskError('');
                                  }}
                                  icon={<Edit3 className="w-3.5 h-3.5" />}
                                />
                                <DaywellIconButton
                                  label={`Remove subtask ${st.title}`}
                                  size="compact"
                                  tone="danger"
                                  onClick={() => handleRemoveSubtask(st.id)}
                                  icon={<X className="w-3.5 h-3.5" />}
                                />
                              </div>
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>

              {/* Options & Reminders */}
              <div className="grid grid-cols-2 gap-2 pt-1">
                <label className="flex items-center gap-2 p-2.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formHasReminder}
                    onChange={(e) => setFormHasReminder(e.target.checked)}
                    className="w-4 h-4 accent-[var(--dw-primary)]"
                  />
                  <span className="text-xs font-semibold text-[var(--dw-text-secondary)]">Set Reminder</span>
                </label>
                <label className="flex items-center gap-2 p-2.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formIsRecurring}
                    onChange={(e) => setFormIsRecurring(e.target.checked)}
                    className="w-4 h-4 accent-[var(--dw-primary)]"
                  />
                  <span className="text-xs font-semibold text-[var(--dw-text-secondary)]">Recurring Task</span>
                </label>
              </div>

              {/* Action Buttons */}
              <div className="flex items-center justify-between pt-2">
                {editingTaskId ? (
                  <DaywellButton
                    label="Delete Task"
                    variant="text"
                    size="compact"
                    onClick={() => {
                      const target = tasks.find((t) => t.id === editingTaskId);
                      if (target) setPendingDeleteTask(target);
                    }}
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
                    onClick={handleAttemptClose}
                  />
                  <DaywellButton
                    type="submit"
                    variant="primary"
                    size="compact"
                    disabled={isSubmitting || !formTitle.trim()}
                    leadingIcon={isSubmitting ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : undefined}
                    label={isSubmitting ? 'Saving...' : editingTaskId ? 'Save Changes' : 'Create Task'}
                  />
                </div>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* TASK DETAILS MODAL */}
      {detailTask && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Task Details"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs"
          onClick={(e) => {
            if (e.target === e.currentTarget) setDetailTaskId(null);
          }}
        >
          {(() => {
            const effectiveStatus = resolveEffectiveTaskStatus(detailTask);
            const completed = effectiveStatus === 'completed';
            const statusTone: DaywellStatusTone =
              effectiveStatus === 'completed'
                ? 'success'
                : effectiveStatus === 'in_progress'
                  ? 'info'
                  : effectiveStatus === 'cancelled'
                    ? 'error'
                    : 'neutral';
            const priorityTone: DaywellStatusTone =
              detailTask.priority === 'urgent'
                ? 'error'
                : detailTask.priority === 'high'
                  ? 'warning'
                  : 'neutral';
            const parsedScheduled = detailTask.scheduledDate
              ? CalendarDate.tryParse(detailTask.scheduledDate)
              : null;
            const parsedDue = detailTask.dueDate
              ? CalendarDate.tryParse(detailTask.dueDate)
              : null;

            return (
              <div className="w-full max-w-md bg-[var(--dw-elevated)] rounded-[var(--dw-radius-xl)] p-5 shadow-2xl border border-[var(--dw-border)] space-y-4 max-h-[90vh] overflow-y-auto">
                <div className="flex items-start justify-between gap-2">
                  <div className="space-y-1 flex-1 min-w-0">
                    <span className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
                      Task Details
                    </span>
                    <h2
                      className={`dw-type-title ${
                        completed
                          ? 'line-through text-[var(--dw-text-muted)]'
                          : 'text-[var(--dw-text-primary)]'
                      }`}
                    >
                      {detailTask.title}
                    </h2>
                  </div>
                  <DaywellIconButton
                    label="Close task details"
                    size="compact"
                    tone="muted"
                    onClick={() => setDetailTaskId(null)}
                    icon={<X className="w-4 h-4" />}
                  />
                </div>

                <div className="flex flex-wrap items-center gap-1.5">
                  <DaywellStatusBadge
                    tone={statusTone}
                    label={TASK_STATUS_LABELS[effectiveStatus]}
                  />
                  <DaywellStatusBadge
                    tone={priorityTone}
                    icon={<Flag className="w-3 h-3" />}
                    label={`${TASK_PRIORITY_LABELS[detailTask.priority]} Priority`}
                  />
                  {detailTask.isArchived && (
                    <DaywellStatusBadge
                      tone="warning"
                      icon={<Archive className="w-3 h-3" />}
                      label="Archived"
                    />
                  )}
                </div>

                {detailTask.description ? (
                  <div className="p-3 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)]">
                    <p className="text-xs text-[var(--dw-text-primary)] whitespace-pre-wrap leading-relaxed">
                      {detailTask.description}
                    </p>
                  </div>
                ) : (
                  <p className="text-xs text-[var(--dw-text-muted)] italic">
                    No description added.
                  </p>
                )}

                <div className="grid grid-cols-1 gap-2 text-xs bg-[var(--dw-card)] p-3 rounded-[var(--dw-radius-md)] border border-[var(--dw-border)]">
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-[var(--dw-text-muted)]">Scheduled Date</span>
                    <span className="font-semibold text-[var(--dw-text-primary)]">
                      {parsedScheduled
                        ? SharedDateFormatter.formatDual(parsedScheduled, false)
                        : detailTask.scheduledDate || 'Not set'}
                      {detailTask.scheduledTime ? ` · ${detailTask.scheduledTime}` : ''}
                    </span>
                  </div>
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-[var(--dw-text-muted)]">Due Date</span>
                    <span className="font-semibold text-[var(--dw-text-primary)]">
                      {parsedDue
                        ? SharedDateFormatter.formatDual(parsedDue, false)
                        : detailTask.dueDate || 'Not set'}
                    </span>
                  </div>
                  {detailTask.projectName && (
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-[var(--dw-text-muted)]">Project / Area</span>
                      <span className="font-semibold text-[var(--dw-text-primary)]">
                        {detailTask.projectName}
                      </span>
                    </div>
                  )}
                  {detailMilestoneTitle && (
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-[var(--dw-text-muted)]">Milestone</span>
                      <span className="font-semibold text-[var(--dw-text-primary)]">
                        {detailMilestoneTitle}
                      </span>
                    </div>
                  )}
                  {detailTask.completedAt && (
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-[var(--dw-text-muted)]">Completed At</span>
                      <span className="font-medium text-[var(--dw-text-secondary)]">
                        {detailTask.completedAt.slice(0, 10)}
                      </span>
                    </div>
                  )}
                </div>

                {/* Interactive Subtasks & Progress Section inside Task Details */}
                {(() => {
                  const detailProgress = computeSubtaskProgress(detailTask.subtasks);
                  return (
                    <div className="space-y-2.5 p-3 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)]">
                      <div className="flex items-center justify-between gap-2">
                        <span className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-secondary)]">
                          Subtasks
                        </span>
                        <span className="text-[11px] font-semibold text-[var(--dw-text-secondary)]">
                          {detailProgress.total > 0
                            ? `${detailProgress.completed} of ${detailProgress.total} done (${detailProgress.percentage}%)`
                            : '0 subtasks'}
                        </span>
                      </div>

                      {detailProgress.total > 0 ? (
                        <DaywellProgressBar
                          value={detailProgress.percentage}
                          label={`Parent task subtask progress for ${detailTask.title}`}
                        />
                      ) : (
                        <p className="text-[11px] text-[var(--dw-text-muted)] italic">
                          No subtasks yet. Break this task into smaller steps below.
                        </p>
                      )}

                      {detailTask.subtasks.length > 0 && (
                        <div className="space-y-1.5 max-h-52 overflow-y-auto">
                          {detailTask.subtasks.map((st, idx) => {
                            const isEditingSub = editingDetailSubtaskId === st.id;
                            return (
                              <div
                                key={st.id}
                                className="p-2 bg-[var(--dw-card)] rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] space-y-1"
                              >
                                {isEditingSub ? (
                                  <div className="space-y-1">
                                    <div className="flex items-center gap-1.5">
                                      <input
                                        aria-label="Edit subtask title"
                                        type="text"
                                        value={editingDetailSubtaskTitle}
                                        onChange={(e) => {
                                          setEditingDetailSubtaskTitle(e.target.value);
                                          if (editingDetailSubtaskError) {
                                            setEditingDetailSubtaskError('');
                                          }
                                        }}
                                        onKeyDown={(e) => {
                                          if (e.key === 'Enter') {
                                            e.preventDefault();
                                            handleSaveDetailSubtaskEdit(detailTask.id, st.id);
                                          } else if (e.key === 'Escape') {
                                            e.preventDefault();
                                            setEditingDetailSubtaskId(null);
                                            setEditingDetailSubtaskTitle('');
                                            setEditingDetailSubtaskError('');
                                          }
                                        }}
                                        className="flex-1 min-h-[34px] px-2.5 py-1 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                                      />
                                      <DaywellIconButton
                                        label={`Save subtask ${st.title}`}
                                        size="compact"
                                        tone="primary"
                                        onClick={() =>
                                          handleSaveDetailSubtaskEdit(detailTask.id, st.id)
                                        }
                                        icon={<Check className="w-3.5 h-3.5" />}
                                      />
                                      <DaywellIconButton
                                        label="Cancel editing subtask"
                                        size="compact"
                                        tone="muted"
                                        onClick={() => {
                                          setEditingDetailSubtaskId(null);
                                          setEditingDetailSubtaskTitle('');
                                          setEditingDetailSubtaskError('');
                                        }}
                                        icon={<X className="w-3.5 h-3.5" />}
                                      />
                                    </div>
                                    {editingDetailSubtaskError && (
                                      <p className="text-[11px] text-[var(--dw-error)]">
                                        {editingDetailSubtaskError}
                                      </p>
                                    )}
                                  </div>
                                ) : (
                                  <div className="flex items-center justify-between gap-2 text-xs">
                                    <div className="flex items-center gap-2 flex-1 min-w-0">
                                      <button
                                        type="button"
                                        aria-label={`Toggle subtask ${st.title}`}
                                        onClick={() => toggleSubtask(detailTask.id, st.id)}
                                        className={`w-4 h-4 rounded border flex items-center justify-center shrink-0 cursor-pointer ${
                                          st.completed
                                            ? 'bg-[var(--dw-primary)] border-[var(--dw-primary)] text-[var(--dw-on-primary)]'
                                            : 'border-[var(--dw-border)] bg-[var(--dw-surface-subtle)]'
                                        }`}
                                      >
                                        {st.completed && <Check className="w-3 h-3 stroke-[3]" />}
                                      </button>
                                      <span
                                        className={`truncate ${
                                          st.completed
                                            ? 'line-through text-[var(--dw-text-disabled)]'
                                            : 'text-[var(--dw-text-primary)]'
                                        }`}
                                      >
                                        {st.title}
                                      </span>
                                    </div>
                                    <div className="flex items-center gap-0.5 shrink-0">
                                      <DaywellIconButton
                                        label={`Move subtask up ${st.title}`}
                                        size="compact"
                                        tone="muted"
                                        disabled={idx === 0}
                                        onClick={() =>
                                          handleReorderDetailSubtask(detailTask.id, idx, idx - 1)
                                        }
                                        icon={<ArrowUp className="w-3.5 h-3.5" />}
                                      />
                                      <DaywellIconButton
                                        label={`Move subtask down ${st.title}`}
                                        size="compact"
                                        tone="muted"
                                        disabled={idx === detailTask.subtasks.length - 1}
                                        onClick={() =>
                                          handleReorderDetailSubtask(detailTask.id, idx, idx + 1)
                                        }
                                        icon={<ArrowDown className="w-3.5 h-3.5" />}
                                      />
                                      <DaywellIconButton
                                        label={`Edit subtask ${st.title}`}
                                        size="compact"
                                        tone="muted"
                                        onClick={() => {
                                          setEditingDetailSubtaskId(st.id);
                                          setEditingDetailSubtaskTitle(st.title);
                                          setEditingDetailSubtaskError('');
                                        }}
                                        icon={<Edit3 className="w-3.5 h-3.5" />}
                                      />
                                      <DaywellIconButton
                                        label={`Delete subtask ${st.title}`}
                                        size="compact"
                                        tone="danger"
                                        onClick={() =>
                                          handleDeleteDetailSubtask(detailTask.id, st.id)
                                        }
                                        icon={<Trash2 className="w-3.5 h-3.5" />}
                                      />
                                    </div>
                                  </div>
                                )}
                              </div>
                            );
                          })}
                        </div>
                      )}

                      <div className="space-y-1 pt-1">
                        <div className="flex items-center gap-2">
                          <input
                            aria-label="Add subtask to task"
                            type="text"
                            placeholder="Add a subtask..."
                            value={detailSubtaskInput}
                            onChange={(e) => {
                              setDetailSubtaskInput(e.target.value);
                              if (detailSubtaskError) setDetailSubtaskError('');
                            }}
                            onKeyDown={(e) => {
                              if (e.key === 'Enter') {
                                e.preventDefault();
                                handleAddDetailSubtask(detailTask.id);
                              }
                            }}
                            className={`flex-1 min-h-[38px] px-3 py-1.5 bg-[var(--dw-card)] rounded-[var(--dw-radius-md)] border text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)] ${
                              detailSubtaskError
                                ? 'border-[var(--dw-error)]'
                                : 'border-[var(--dw-border)]'
                            }`}
                          />
                          <DaywellButton
                            label="Add"
                            variant="tonal"
                            size="compact"
                            onClick={() => handleAddDetailSubtask(detailTask.id)}
                          />
                        </div>
                        {detailSubtaskError && (
                          <p className="text-[11px] text-[var(--dw-error)]">
                            {detailSubtaskError}
                          </p>
                        )}
                      </div>
                    </div>
                  );
                })()}

                <div className="flex flex-wrap items-center justify-between gap-2 pt-2 border-t border-[var(--dw-divider)]">
                  <div className="flex items-center gap-1.5">
                    <DaywellButton
                      label={detailTask.isArchived ? 'Restore' : 'Archive'}
                      variant="outlined"
                      size="compact"
                      leadingIcon={
                        detailTask.isArchived ? (
                          <RotateCcw className="w-3.5 h-3.5" />
                        ) : (
                          <Archive className="w-3.5 h-3.5" />
                        )
                      }
                      onClick={() => handleToggleArchive(detailTask)}
                    />
                    <DaywellButton
                      label="Delete"
                      variant="text"
                      size="compact"
                      leadingIcon={<Trash2 className="w-3.5 h-3.5" />}
                      onClick={() => setPendingDeleteTask(detailTask)}
                      className="!text-[var(--dw-error)]"
                    />
                  </div>
                  <div className="flex items-center gap-2">
                    <DaywellButton
                      label="Edit"
                      variant="tonal"
                      size="compact"
                      leadingIcon={<Edit3 className="w-3.5 h-3.5" />}
                      onClick={() => handleOpenEdit(detailTask)}
                    />
                    <DaywellButton
                      label={completed ? 'Reopen' : 'Complete'}
                      variant="primary"
                      size="compact"
                      leadingIcon={<Check className="w-3.5 h-3.5" />}
                      onClick={() => toggleTask(detailTask.id)}
                    />
                  </div>
                </div>
              </div>
            );
          })()}
        </div>
      )}

      {/* Safe Delete Confirmation Dialog */}
      <DaywellConfirmationDialog
        isOpen={Boolean(pendingDeleteTask)}
        title="Delete task?"
        description={
          pendingDeleteTask
            ? `Delete "${pendingDeleteTask.title}"? You can undo immediately afterward.`
            : ''
        }
        confirmLabel="Delete Task"
        cancelLabel="Cancel"
        destructive
        onCancel={() => setPendingDeleteTask(null)}
        onConfirm={() => {
          if (pendingDeleteTask) {
            executeDeleteTask(pendingDeleteTask.id);
          }
        }}
      />

      {/* Unsaved Changes Dialog */}
      <UnsavedChangesDialog
        isOpen={showUnsavedPrompt}
        onContinueEditing={() => setShowUnsavedPrompt(false)}
        onDiscardChanges={() => {
          setShowUnsavedPrompt(false);
          setIsModalOpen(false);
          setFormErrors({});
        }}
      />
    </div>
  );
}
export { DEFAULT_SAMPLE_TASKS };
