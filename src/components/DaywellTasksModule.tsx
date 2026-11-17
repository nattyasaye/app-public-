import React, { useState, useMemo, useRef } from 'react';
import { CalendarDate, EthiopiaClock, LocalDateTime } from '../domain/date';
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
} from 'lucide-react';
import { validateTaskForm, isFormDirty } from '../domain/formValidationAndNavigation';
import { UnsavedChangesDialog } from './UnsavedChangesDialog';
import {
  DaywellButton,
  DaywellCard,
  DaywellEmptyState,
  DaywellIconButton,
  DaywellProgressBar,
  DaywellSearchField,
  DaywellStatusBadge,
  DaywellStatusBanner,
} from './ui';

export interface TaskSubItem {
  id: string;
  title: string;
  completed: boolean;
}

export interface DaywellTask {
  id: string;
  title: string;
  description?: string;
  category?: string;
  priority: 'urgent' | 'high' | 'medium' | 'low';
  completed: boolean;
  completedAt?: string;
  dueDate?: string; // YYYY-MM-DD (Hard deadline)
  scheduledDate?: string; // YYYY-MM-DD (When you plan to work on it)
  scheduledTime?: string; // HH:MM
  hasReminder: boolean;
  isRecurring?: boolean;
  recurringRule?: 'daily' | 'weekly' | 'monthly';
  subtasks: TaskSubItem[];
  projectName?: string;
  createdAt: string;
}

interface DaywellTasksModuleProps {
  tasks: DaywellTask[];
  onUpdateTasks: (updated: DaywellTask[]) => void;
  onRequestQuickCapture?: () => void;
  onNavigateToCalendar?: (dateStr: string) => void;
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
    priority: 'medium',
    completed: true,
    completedAt: '08:50',
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
}: DaywellTasksModuleProps) {
  // Filter tab: 'today' | 'inbox' | 'upcoming' | 'completed'
  const [activeFilter, setActiveFilter] = useState<'today' | 'inbox' | 'upcoming' | 'completed'>('today');

  // Search & Sorting
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState<'priority' | 'time' | 'title'>('priority');

  // Task Modal (Create & Edit)
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingTaskId, setEditingTaskId] = useState<string | null>(null);

  // Form Fields
  const [formTitle, setFormTitle] = useState('');
  const [formDescription, setFormDescription] = useState('');
  const [formPriority, setFormPriority] = useState<DaywellTask['priority']>('medium');
  const [formDueDate, setFormDueDate] = useState<string>('');
  const [formScheduledDate, setFormScheduledDate] = useState<string>('');
  const [formScheduledTime, setFormScheduledTime] = useState<string>('');
  const [formProject, setFormProject] = useState<string>('Personal');
  const [formHasReminder, setFormHasReminder] = useState<boolean>(false);
  const [formIsRecurring, setFormIsRecurring] = useState<boolean>(false);
  const [formRecurringRule, setFormRecurringRule] = useState<'daily' | 'weekly' | 'monthly'>('daily');
  const [formSubtasks, setFormSubtasks] = useState<TaskSubItem[]>([]);
  const [newSubtaskInput, setNewSubtaskInput] = useState('');

  // Form Validation & Dirty State
  const [formErrors, setFormErrors] = useState<Record<string, string>>({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [showUnsavedPrompt, setShowUnsavedPrompt] = useState(false);
  const [initialTaskValues, setInitialTaskValues] = useState<Record<string, unknown> | null>(null);
  const titleInputRef = useRef<HTMLInputElement>(null);

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
  const filteredTasks = useMemo(() => {
    let list = [...tasks];

    if (activeFilter === 'today') {
      list = list.filter((t) => !t.completed && (t.dueDate === todayStr || t.scheduledDate === todayStr || (!t.dueDate && !t.scheduledDate)));
    } else if (activeFilter === 'inbox') {
      list = list.filter((t) => !t.completed && !t.dueDate && !t.scheduledDate);
    } else if (activeFilter === 'upcoming') {
      list = list.filter((t) => !t.completed && ((t.dueDate && t.dueDate > todayStr) || (t.scheduledDate && t.scheduledDate > todayStr)));
    } else if (activeFilter === 'completed') {
      list = list.filter((t) => t.completed);
    }

    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      list = list.filter(
        (t) =>
          t.title.toLowerCase().includes(q) ||
          (t.description && t.description.toLowerCase().includes(q)) ||
          (t.projectName && t.projectName.toLowerCase().includes(q))
      );
    }

    list.sort((a, b) => {
      if (sortBy === 'priority') {
        const priorityOrder: Record<DaywellTask['priority'], number> = {
          urgent: 0,
          high: 1,
          medium: 2,
          low: 3,
        };
        return priorityOrder[a.priority] - priorityOrder[b.priority];
      }
      if (sortBy === 'time') {
        const timeA = a.scheduledTime || '23:59';
        const timeB = b.scheduledTime || '23:59';
        return timeA.localeCompare(timeB);
      }
      return a.title.localeCompare(b.title);
    });

    return list;
  }, [tasks, activeFilter, searchQuery, sortBy, todayStr]);

  // Counts for tabs
  const tabCounts = useMemo(() => {
    const todayCount = tasks.filter((t) => !t.completed && (t.dueDate === todayStr || t.scheduledDate === todayStr || (!t.dueDate && !t.scheduledDate))).length;
    const inboxCount = tasks.filter((t) => !t.completed && !t.dueDate && !t.scheduledDate).length;
    const upcomingCount = tasks.filter((t) => !t.completed && ((t.dueDate && t.dueDate > todayStr) || (t.scheduledDate && t.scheduledDate > todayStr))).length;
    const completedCount = tasks.filter((t) => t.completed).length;
    return { todayCount, inboxCount, upcomingCount, completedCount };
  }, [tasks, todayStr]);

  // Toggle Task Completion
  const toggleTask = (taskId: string) => {
    const prev = [...tasks];
    const target = tasks.find((t) => t.id === taskId);
    if (!target) return;

    const nextCompleted = !target.completed;
    const timeFormatted = LocalDateTime.now().timeOfDay.toIsoString();

    const updated = tasks.map((t) =>
      t.id === taskId
        ? {
            ...t,
            completed: nextCompleted,
            completedAt: nextCompleted ? timeFormatted : undefined,
          }
        : t
    );

    onUpdateTasks(updated);
    triggerUndo(
      nextCompleted ? `Completed "${target.title}"` : `Reopened "${target.title}"`,
      () => onUpdateTasks(prev)
    );
  };

  // Toggle Subtask
  const toggleSubtask = (taskId: string, subtaskId: string) => {
    const updated = tasks.map((t) => {
      if (t.id === taskId) {
        return {
          ...t,
          subtasks: t.subtasks.map((st) => (st.id === subtaskId ? { ...st, completed: !st.completed } : st)),
        };
      }
      return t;
    });
    onUpdateTasks(updated);
  };

  const getCurrentTaskValues = () => ({
    title: formTitle,
    description: formDescription,
    priority: formPriority,
    dueDate: formDueDate,
    scheduledDate: formScheduledDate,
    scheduledTime: formScheduledTime,
    projectName: formProject,
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
    const initDueDate = activeFilter === 'today' ? todayStr : '';
    const initScheduledDate = activeFilter === 'today' ? todayStr : '';
    setFormDueDate(initDueDate);
    setFormScheduledDate(initScheduledDate);
    setFormScheduledTime('');
    setFormProject('Personal');
    setFormHasReminder(false);
    setFormIsRecurring(false);
    setFormRecurringRule('daily');
    setFormSubtasks([]);
    setNewSubtaskInput('');
    setFormErrors({});
    setIsSubmitting(false);

    setInitialTaskValues({
      title: '',
      description: '',
      priority: 'medium',
      dueDate: initDueDate,
      scheduledDate: initScheduledDate,
      scheduledTime: '',
      projectName: 'Personal',
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
    setEditingTaskId(task.id);
    setFormTitle(task.title);
    setFormDescription(task.description || '');
    setFormPriority(task.priority);
    setFormDueDate(task.dueDate || '');
    setFormScheduledDate(task.scheduledDate || '');
    setFormScheduledTime(task.scheduledTime || '');
    setFormProject(task.projectName || 'Personal');
    setFormHasReminder(task.hasReminder);
    setFormIsRecurring(task.isRecurring || false);
    setFormRecurringRule(task.recurringRule || 'daily');
    const subtasksCopy = [...task.subtasks];
    setFormSubtasks(subtasksCopy);
    setNewSubtaskInput('');
    setFormErrors({});
    setIsSubmitting(false);

    setInitialTaskValues({
      title: task.title,
      description: task.description || '',
      priority: task.priority,
      dueDate: task.dueDate || '',
      scheduledDate: task.scheduledDate || '',
      scheduledTime: task.scheduledTime || '',
      projectName: task.projectName || 'Personal',
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

    const validation = validateTaskForm({
      title: formTitle,
      description: formDescription,
      dueDate: formDueDate,
      scheduledDate: formScheduledDate,
      scheduledTime: formScheduledTime,
    });

    if (!validation.isValid) {
      setFormErrors(validation.errors);
      if (validation.errors.title) {
        titleInputRef.current?.focus();
      }
      return;
    }

    if (isSubmitting) return;
    setIsSubmitting(true);

    const prev = [...tasks];

    if (editingTaskId) {
      const updated = tasks.map((t) =>
        t.id === editingTaskId
          ? {
              ...t,
              title: formTitle.trim(),
              description: formDescription.trim() || undefined,
              priority: formPriority,
              dueDate: formDueDate || undefined,
              scheduledDate: formScheduledDate || undefined,
              scheduledTime: formScheduledTime || undefined,
              projectName: formProject.trim() || 'Personal',
              hasReminder: formHasReminder,
              isRecurring: formIsRecurring,
              recurringRule: formIsRecurring ? formRecurringRule : undefined,
              subtasks: formSubtasks,
            }
          : t
      );
      onUpdateTasks(updated);
      setIsSubmitting(false);
      setIsModalOpen(false);
      setFormErrors({});
      triggerUndo('Task updated', () => onUpdateTasks(prev));
    } else {
      const newTask: DaywellTask = {
        id: `t-${Date.now()}`,
        title: formTitle.trim(),
        description: formDescription.trim() || undefined,
        category: formProject.trim() || 'Personal',
        priority: formPriority,
        completed: false,
        dueDate: formDueDate || undefined,
        scheduledDate: formScheduledDate || undefined,
        scheduledTime: formScheduledTime || undefined,
        projectName: formProject.trim() || 'Personal',
        hasReminder: formHasReminder,
        isRecurring: formIsRecurring,
        recurringRule: formIsRecurring ? formRecurringRule : undefined,
        subtasks: formSubtasks,
        createdAt: EthiopiaClock.nowUtc().toISOString(),
      };
      onUpdateTasks([newTask, ...tasks]);
      setIsSubmitting(false);
      setIsModalOpen(false);
      setFormErrors({});
      triggerUndo(`Added "${newTask.title}"`, () => onUpdateTasks(prev));
    }
  };

  // Delete Task
  const handleDeleteTask = (taskId: string) => {
    const prev = [...tasks];
    const target = tasks.find((t) => t.id === taskId);
    onUpdateTasks(tasks.filter((t) => t.id !== taskId));
    setIsModalOpen(false);
    triggerUndo(`Deleted "${target?.title || 'task'}"`, () => onUpdateTasks(prev));
  };

  // Subtask helper
  const handleAddSubtask = () => {
    if (!newSubtaskInput.trim()) return;
    const newSt: TaskSubItem = {
      id: `st-${Date.now()}`,
      title: newSubtaskInput.trim(),
      completed: false,
    };
    setFormSubtasks([...formSubtasks, newSt]);
    setNewSubtaskInput('');
  };

  const handleRemoveSubtask = (stId: string) => {
    setFormSubtasks(formSubtasks.filter((st) => st.id !== stId));
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

      {/* Top Bar */}
      <div className="flex items-start justify-between pt-1">
        <div>
          <div className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
            A CLEAR NEXT STEP
          </div>
          <h1 className="dw-type-display text-[var(--dw-text-primary)]">
            Tasks
          </h1>
        </div>
        <DaywellIconButton
          label="Add New Task"
          tone="primary"
          onClick={handleOpenCreate}
          icon={<Plus className="w-5 h-5 stroke-[2.5]" />}
          className="bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] hover:opacity-90"
        />
      </div>

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
            { id: 'completed', label: `Completed (${tabCounts.completedCount})` },
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
            {tabCounts.completedCount} of {tasks.length}
          </span>
          <p className="dw-type-label text-[var(--dw-text-muted)]">total tasks completed</p>
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
            message="No tasks in this view"
            subtitle={
              activeFilter === 'today'
                ? "You're all caught up for today! Plan tomorrow or capture a new task."
                : 'Nothing to display for this filter.'
            }
            actionLabel="Add Task"
            onActionPressed={handleOpenCreate}
          />
        ) : (
          filteredTasks.map((task) => {
            const hasSubtasks = task.subtasks && task.subtasks.length > 0;
            const completedSubtasks = task.subtasks ? task.subtasks.filter((s) => s.completed).length : 0;
            const pct = hasSubtasks ? (completedSubtasks / task.subtasks.length) * 100 : 0;

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
                    aria-label={task.completed ? `Reopen ${task.title}` : `Complete ${task.title}`}
                    onClick={() => toggleTask(task.id)}
                    className={`w-5 h-5 rounded-[var(--dw-radius-sm)] border mt-0.5 flex items-center justify-center transition-colors shrink-0 cursor-pointer ${
                      task.completed
                        ? 'bg-[var(--dw-primary)] border-[var(--dw-primary)] text-[var(--dw-on-primary)]'
                        : 'border-[var(--dw-border)] hover:border-[var(--dw-primary)]'
                    }`}
                  >
                    {task.completed && <Check className="w-3.5 h-3.5 stroke-[3]" />}
                  </button>

                  {/* Task Content */}
                  <div
                    onClick={() => handleOpenEdit(task)}
                    className="flex-1 min-w-0 cursor-pointer"
                  >
                    <p
                      className={`text-xs font-semibold leading-snug ${
                        task.completed
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
                          <span className="capitalize">{task.priority}</span>
                        </span>
                      )}

                      {task.projectName && (
                        <span className="font-semibold text-[var(--dw-text-secondary)]">
                          {task.projectName}
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

                  {/* Badges & Edit Action */}
                  <div className="flex items-center gap-1 text-[var(--dw-text-muted)] shrink-0">
                    {task.hasReminder && <Bell className="w-3.5 h-3.5" aria-label="Has reminder" />}
                    {task.isRecurring && <Repeat2 className="w-3.5 h-3.5" aria-label="Recurring task" />}
                    <DaywellIconButton
                      label={`Edit ${task.title}`}
                      size="compact"
                      tone="muted"
                      onClick={() => handleOpenEdit(task)}
                      icon={<Edit3 className="w-3.5 h-3.5" />}
                    />
                  </div>
                </div>

                {/* Subtask checklist progress & items */}
                {hasSubtasks && (
                  <div className="pl-8 pt-1.5 space-y-1.5 border-t border-[var(--dw-divider)]">
                    <div className="flex items-center justify-between gap-3 text-[10px] text-[var(--dw-text-muted)]">
                      <span>Checklist: {completedSubtasks} of {task.subtasks.length} done</span>
                      <DaywellProgressBar
                        value={pct}
                        label={`Subtask progress for ${task.title}`}
                        className="!w-20"
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
                    value={formPriority}
                    onChange={(e) => setFormPriority(e.target.value as DaywellTask['priority'])}
                    className="w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  >
                    <option value="urgent">Urgent</option>
                    <option value="high">High</option>
                    <option value="medium">Medium</option>
                    <option value="low">Low</option>
                  </select>
                </div>

                <div>
                  <label className="block dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)] mb-1">
                    Project / Area (Optional)
                  </label>
                  <input
                    type="text"
                    value={formProject}
                    onChange={(e) => setFormProject(e.target.value)}
                    placeholder="e.g. Portfolio refresh"
                    className="w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-2.5">
                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Hard Due Date (Optional)
                  </label>
                  <input
                    type="date"
                    value={formDueDate}
                    onChange={(e) => setFormDueDate(e.target.value)}
                    className="w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  />
                </div>
                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Scheduled Time (Optional)
                  </label>
                  <input
                    type="time"
                    value={formScheduledTime}
                    onChange={(e) => setFormScheduledTime(e.target.value)}
                    className="w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  />
                </div>
              </div>

              {/* Subtasks checklist builder */}
              <div className="space-y-2 pt-2 border-t border-[var(--dw-divider)]">
                <label className="block dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
                  Checklist / Subtasks (Optional)
                </label>
                <div className="flex items-center gap-2">
                  <input
                    type="text"
                    placeholder="Add subtask..."
                    value={newSubtaskInput}
                    onChange={(e) => setNewSubtaskInput(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        e.preventDefault();
                        handleAddSubtask();
                      }
                    }}
                    className="flex-1 min-h-[38px] px-3 py-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  />
                  <DaywellButton
                    label="Add"
                    variant="tonal"
                    size="compact"
                    onClick={handleAddSubtask}
                  />
                </div>

                {formSubtasks.length > 0 && (
                  <div className="space-y-1 max-h-32 overflow-y-auto">
                    {formSubtasks.map((st) => (
                      <div
                        key={st.id}
                        className="flex items-center justify-between p-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-sm)] text-xs"
                      >
                        <span className="text-[var(--dw-text-primary)]">{st.title}</span>
                        <DaywellIconButton
                          label={`Remove subtask ${st.title}`}
                          size="compact"
                          tone="danger"
                          onClick={() => handleRemoveSubtask(st.id)}
                          icon={<X className="w-3.5 h-3.5" />}
                        />
                      </div>
                    ))}
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
                    onClick={() => handleDeleteTask(editingTaskId)}
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
