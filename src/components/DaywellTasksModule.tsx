import React, { useState, useEffect, useMemo, useRef } from 'react';
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
  Tag,
  SlidersHorizontal,
  Inbox as InboxIcon,
  ArrowRight,
  Sun,
} from 'lucide-react';
import {
  buildDailyPlanSnapshot,
  carryForwardUnfinishedTasks,
  isTaskPlannedForDate,
  movePlannedTaskOrder,
  planTaskForDate,
  removeTaskFromPlannedDay,
  syncTaskCompletionWithDailyPlanning,
} from '../domain/dailyPlanningOperations';
import { isFormDirty } from '../domain/formValidationAndNavigation';
import {
  CANONICAL_INBOX_CATEGORIES,
  deleteInboxItemFromList,
  getUnprocessedInboxItems,
  INBOX_CATEGORY_LABELS,
  InboxItemCategory,
  markInboxItemProcessed,
  prepareTaskDraftFromInboxItem,
  updateInboxItemRecord,
} from '../domain/inboxOperations';
import {
  SharedDailyPlanningEntry,
  SharedInboxItem,
  SharedMilestone,
  SharedProject,
  SharedTaskRecurrenceConfig,
  SharedTaskRecurrenceFrequency,
  SharedTaskRecurrenceRepeatFrom,
  SharedTaskStatus,
} from '../domain/sharedFoundation';
import {
  addSubtaskToList,
  addSubtaskToTask,
  assignLabelToTask,
  CANONICAL_TASK_PRIORITIES,
  CANONICAL_TASK_STATUSES,
  computeSubtaskProgress,
  computeTaskTabCounts,
  createTaskRecord,
  DaywellTaskRecord,
  deleteSubtaskFromList,
  deleteSubtaskFromTask,
  deleteTaskFromList,
  extractAvailableTaskLabels,
  filterTasksForView,
  hasActiveTaskOrganizationFilters,
  isTaskCompleted,
  normalizeTaskLabel,
  normalizeTaskLabels,
  removeLabelFromAllTasks,
  removeLabelFromTask,
  renameLabelAcrossTasks,
  reorderSubtasksInList,
  reorderTaskSubtasks,
  resolveEffectiveTaskStatus,
  setTaskArchivedRecord,
  TASK_DUE_DATE_FILTER_LABELS,
  TASK_PRIORITY_LABELS,
  TASK_STATUS_LABELS,
  TaskDueDateFilter,
  TaskSortBy,
  TaskSubItemRecord,
  TaskViewFilter,
  toggleSubtaskInList,
  toggleTaskSubtask,
  updateSubtaskTitleInList,
  updateTaskRecord,
  updateTaskSubtaskTitle,
} from '../domain/taskOperations';
import {
  completeTaskWithRecurrence,
  formatRecurrenceSummary,
  rescheduleRecurrenceOccurrence,
  resolveEffectiveRecurrenceConfig,
  skipRecurrenceOccurrence,
  stopTaskRecurrence,
} from '../domain/taskRecurrence';
import { getTaskPrimaryCalendarDate } from '../domain/taskCalendar';
import { dailyPlanningService } from '../services/dailyPlanningService';
import { inboxService } from '../services/inboxService';
import { projectsService } from '../services/projectsService';
import { SharedStateBridge } from '../services/sharedStateBridge';
import { ProjectsWorkspaceView } from './projects';
import { MyDayPlanningView } from './tasks/MyDayPlanningView';
import {
  TaskRecurrenceDetailsPanel,
  TaskRecurrenceEditorSection,
} from './tasks/TaskRecurrenceFields';
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
  inboxItems?: SharedInboxItem[];
  onUpdateInboxItems?: (updated: SharedInboxItem[]) => void;
  dailyPlanningEntries?: SharedDailyPlanningEntry[];
  onUpdateDailyPlanningEntries?: (updated: SharedDailyPlanningEntry[]) => void;
  requestedFilter?: { filter: TaskViewFilter; nonce: number } | null;
  requestedTaskFocus?: {
    taskId: string;
    openMode?: 'details' | 'edit';
    nonce: number;
  } | null;
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
  inboxItems: controlledInboxItems,
  onUpdateInboxItems,
  dailyPlanningEntries: controlledDailyPlanningEntries,
  onUpdateDailyPlanningEntries,
  requestedFilter,
  requestedTaskFocus,
  onRequestQuickCapture,
  onNavigateToCalendar,
  activeSubTab: controlledSubTab,
  onSubTabChange,
  selectedProjectId: controlledProjectId,
  onSelectProjectId,
}: DaywellTasksModuleProps) {
  const [internalSubTab, setInternalSubTab] = useState<'tasks' | 'projects'>('tasks');
  const [internalProjectId, setInternalProjectId] = useState<string | null>(null);
  const [projectCreateTrigger, setProjectCreateTrigger] = useState(0);
  const [internalInboxItems, setInternalInboxItems] = useState<SharedInboxItem[]>(() =>
    inboxService.loadInboxItems()
  );
  const [internalDailyPlanningEntries, setInternalDailyPlanningEntries] =
    useState<SharedDailyPlanningEntry[]>(() =>
      dailyPlanningService.loadDailyPlanningEntries()
    );

  useEffect(() => {
    if (
      (controlledInboxItems !== undefined &&
        controlledDailyPlanningEntries !== undefined) ||
      typeof window === 'undefined'
    ) {
      return;
    }
    const handleSync = () => {
      if (controlledInboxItems === undefined) {
        setInternalInboxItems(inboxService.loadInboxItems());
      }
      if (controlledDailyPlanningEntries === undefined) {
        setInternalDailyPlanningEntries(
          dailyPlanningService.loadDailyPlanningEntries()
        );
      }
    };
    window.addEventListener(SharedStateBridge.SYNC_EVENT_NAME, handleSync);
    return () => window.removeEventListener(SharedStateBridge.SYNC_EVENT_NAME, handleSync);
  }, [controlledInboxItems, controlledDailyPlanningEntries]);

  const effectiveInboxItems = controlledInboxItems ?? internalInboxItems;
  const applyInboxUpdate = (next: SharedInboxItem[]) => {
    if (onUpdateInboxItems) {
      onUpdateInboxItems(next);
    } else {
      const saved = inboxService.saveInboxItems(next);
      setInternalInboxItems(saved);
    }
  };

  const effectiveDailyPlanningEntries =
    controlledDailyPlanningEntries ?? internalDailyPlanningEntries;
  const applyDailyPlanningUpdate = (next: SharedDailyPlanningEntry[]) => {
    if (onUpdateDailyPlanningEntries) {
      onUpdateDailyPlanningEntries(next);
    } else {
      const saved = dailyPlanningService.saveDailyPlanningEntries(next);
      setInternalDailyPlanningEntries(saved);
    }
  };

  const commitTasksAndDailyPlanning = (
    nextTasks: DaywellTask[],
    nextEntries: SharedDailyPlanningEntry[]
  ) => {
    if (typeof localStorage !== 'undefined') {
      try {
        localStorage.setItem('daywell_tasks', JSON.stringify(nextTasks));
      } catch {}
    }
    onUpdateTasks(nextTasks);
    applyDailyPlanningUpdate(nextEntries);
  };

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

  // Filter tab: 'today' | 'my_day' | 'inbox' | 'upcoming' | 'active' | 'overdue' | 'all' | 'completed' | 'archived'
  const [activeFilter, setActiveFilter] = useState<TaskViewFilter>('today');

  useEffect(() => {
    if (requestedFilter?.filter) {
      setSubTab('tasks');
      setActiveFilter(requestedFilter.filter);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [requestedFilter?.nonce]);

  useEffect(() => {
    if (!requestedTaskFocus?.taskId) return;
    const target = tasks.find((t) => t.id === requestedTaskFocus.taskId);
    if (!target) return;
    setSubTab('tasks');
    if (requestedTaskFocus.openMode === 'edit') {
      handleOpenEdit(target);
    } else {
      openTaskDetails(target.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [requestedTaskFocus?.nonce]);

  // Search, Multi-Criteria Filters & Sorting
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState<TaskSortBy>('priority');
  const [showFilterPanel, setShowFilterPanel] = useState(false);
  const [statusFilter, setStatusFilter] = useState<SharedTaskStatus | ''>('');
  const [priorityFilter, setPriorityFilter] = useState<DaywellTask['priority'] | ''>('');
  const [dueDateFilter, setDueDateFilter] = useState<TaskDueDateFilter | ''>('');
  const [projectFilter, setProjectFilter] = useState<string>('');
  const [sectionFilter, setSectionFilter] = useState<string>('');
  const [tagFilters, setTagFilters] = useState<string[]>([]);

  // Tag Catalog & Tag Manager Modal
  const [customTagCatalog, setCustomTagCatalog] = useState<string[]>([]);
  const [isTagManagerOpen, setIsTagManagerOpen] = useState(false);
  const [newGlobalTagInput, setNewGlobalTagInput] = useState('');
  const [globalTagError, setGlobalTagError] = useState('');
  const [editingGlobalTag, setEditingGlobalTag] = useState<string | null>(null);
  const [editingGlobalTagTitle, setEditingGlobalTagTitle] = useState('');
  const [editingGlobalTagError, setEditingGlobalTagError] = useState('');

  // Shared Inbox Triage State
  const [convertingInboxItem, setConvertingInboxItem] = useState<SharedInboxItem | null>(null);
  const [editingInboxId, setEditingInboxId] = useState<string | null>(null);
  const [editingInboxText, setEditingInboxText] = useState('');
  const [editingInboxCategory, setEditingInboxCategory] = useState<InboxItemCategory>('task');
  const [editingInboxError, setEditingInboxError] = useState('');
  const [pendingDeleteInboxItem, setPendingDeleteInboxItem] = useState<SharedInboxItem | null>(null);

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
  const [formLabels, setFormLabels] = useState<string[]>([]);
  const [newFormLabelInput, setNewFormLabelInput] = useState('');
  const [formLabelError, setFormLabelError] = useState('');
  const [formHasReminder, setFormHasReminder] = useState<boolean>(false);
  const [formIsRecurring, setFormIsRecurring] = useState<boolean>(false);
  const [formRecurrenceFrequency, setFormRecurrenceFrequency] =
    useState<SharedTaskRecurrenceFrequency>('weekly');
  const [formRecurrenceInterval, setFormRecurrenceInterval] = useState<number>(1);
  const [formRecurrenceWeekdays, setFormRecurrenceWeekdays] = useState<number[]>([]);
  const [formRecurrenceStartDate, setFormRecurrenceStartDate] = useState<string>('');
  const [formRecurrenceEndDate, setFormRecurrenceEndDate] = useState<string>('');
  const [formRecurrenceRepeatFrom, setFormRecurrenceRepeatFrom] =
    useState<SharedTaskRecurrenceRepeatFrom>('due_date');
  const [formSubtasks, setFormSubtasks] = useState<TaskSubItem[]>([]);
  const [newSubtaskInput, setNewSubtaskInput] = useState('');
  const [formSubtaskError, setFormSubtaskError] = useState('');
  const [editingFormSubtaskId, setEditingFormSubtaskId] = useState<string | null>(null);
  const [editingFormSubtaskTitle, setEditingFormSubtaskTitle] = useState('');
  const [editingFormSubtaskError, setEditingFormSubtaskError] = useState('');

  // Task Details inline subtask, recurrence & tag controls
  const [detailSubtaskInput, setDetailSubtaskInput] = useState('');
  const [detailSubtaskError, setDetailSubtaskError] = useState('');
  const [editingDetailSubtaskId, setEditingDetailSubtaskId] = useState<string | null>(null);
  const [editingDetailSubtaskTitle, setEditingDetailSubtaskTitle] = useState('');
  const [editingDetailSubtaskError, setEditingDetailSubtaskError] = useState('');
  const [detailTagInput, setDetailTagInput] = useState('');
  const [detailTagError, setDetailTagError] = useState('');
  const [detailRecurrenceError, setDetailRecurrenceError] = useState('');

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
    setDetailTagInput('');
    setDetailTagError('');
    setDetailRecurrenceError('');
  };

  const allActiveProjects: SharedProject[] = useMemo(
    () => projectsService.listProjects({ includeArchived: false }),
    // Re-read whenever tasks/subtab/modals change so project filter stays in sync
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [tasks, subTab, isModalOpen]
  );

  const availableProjects: SharedProject[] = useMemo(() => {
    if (!isModalOpen) return [];
    return allActiveProjects;
  }, [isModalOpen, allActiveProjects]);

  const availableMilestones: SharedMilestone[] = useMemo(() => {
    if (!isModalOpen || !formProjectId.trim()) return [];
    return projectsService.listMilestones(formProjectId.trim());
  }, [isModalOpen, formProjectId]);

  const effectiveProjectFilter = useMemo(
    () =>
      projectFilter && allActiveProjects.some((p) => p.id === projectFilter)
        ? projectFilter
        : '',
    [projectFilter, allActiveProjects]
  );

  const availableSectionsForFilter = useMemo(() => {
    if (!effectiveProjectFilter) return [];
    return projectsService.getProjectSectionsViewModel(effectiveProjectFilter).sections;
  }, [effectiveProjectFilter, tasks, subTab]);

  const effectiveSectionFilter = useMemo(() => {
    if (!effectiveProjectFilter || !sectionFilter) return '';
    if (
      sectionFilter === '__unsectioned__' ||
      availableSectionsForFilter.some((s) => s.record.id === sectionFilter)
    ) {
      return sectionFilter;
    }
    return '';
  }, [effectiveProjectFilter, sectionFilter, availableSectionsForFilter]);

  const sectionTaskIdsForFilter = useMemo(() => {
    if (!effectiveProjectFilter || !effectiveSectionFilter) return undefined;
    return projectsService.getProjectSectionTaskIds(
      effectiveProjectFilter,
      effectiveSectionFilter
    );
  }, [effectiveProjectFilter, effectiveSectionFilter, tasks]);

  const availableLabels = useMemo(
    () => extractAvailableTaskLabels(tasks, customTagCatalog),
    [tasks, customTagCatalog]
  );

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

  const hasActiveFilters = useMemo(
    () =>
      hasActiveTaskOrganizationFilters({
        searchQuery,
        statusFilter: statusFilter || undefined,
        priorityFilter: priorityFilter || undefined,
        dueDateFilter: dueDateFilter || undefined,
        projectIdFilter: effectiveProjectFilter || undefined,
        sectionIdFilter: effectiveSectionFilter || undefined,
        tagFilters,
      }),
    [
      searchQuery,
      statusFilter,
      priorityFilter,
      dueDateFilter,
      effectiveProjectFilter,
      effectiveSectionFilter,
      tagFilters,
    ]
  );

  const activeAttributeFilterCount = useMemo(() => {
    let count = 0;
    if (statusFilter) count += 1;
    if (priorityFilter) count += 1;
    if (dueDateFilter) count += 1;
    if (effectiveProjectFilter) count += 1;
    if (effectiveSectionFilter) count += 1;
    count += tagFilters.length;
    return count;
  }, [
    statusFilter,
    priorityFilter,
    dueDateFilter,
    effectiveProjectFilter,
    effectiveSectionFilter,
    tagFilters,
  ]);

  const handleClearFilters = () => {
    setSearchQuery('');
    setStatusFilter('');
    setPriorityFilter('');
    setDueDateFilter('');
    setProjectFilter('');
    setSectionFilter('');
    setTagFilters([]);
  };

  const openTagManager = () => {
    setNewGlobalTagInput('');
    setGlobalTagError('');
    setEditingGlobalTag(null);
    setEditingGlobalTagTitle('');
    setEditingGlobalTagError('');
    setIsTagManagerOpen(true);
  };

  const toggleFilterTag = (label: string) => {
    const normalized = normalizeTaskLabel(label);
    if (!normalized) return;
    const key = normalized.toLowerCase();
    setTagFilters((prev) =>
      prev.some((t) => t.toLowerCase() === key)
        ? prev.filter((t) => t.toLowerCase() !== key)
        : [...prev, normalized]
    );
  };

  // Filter tasks
  const filteredTasks = useMemo(
    () =>
      filterTasksForView(tasks, {
        viewFilter: activeFilter,
        searchQuery,
        sortBy,
        todayIso: todayStr,
        statusFilter: statusFilter || undefined,
        priorityFilter: priorityFilter || undefined,
        dueDateFilter: dueDateFilter || undefined,
        projectIdFilter: effectiveProjectFilter || undefined,
        sectionTaskIds: sectionTaskIdsForFilter,
        tagFilters,
      }),
    [
      tasks,
      activeFilter,
      searchQuery,
      sortBy,
      todayStr,
      statusFilter,
      priorityFilter,
      dueDateFilter,
      effectiveProjectFilter,
      sectionTaskIdsForFilter,
      tagFilters,
    ]
  );

  // Counts for tabs
  const tabCounts = useMemo(
    () => computeTaskTabCounts(tasks, todayStr),
    [tasks, todayStr]
  );

  const [selectedPlanDate, setSelectedPlanDate] = useState<string>(todayStr);

  const myDaySnapshot = useMemo(
    () =>
      buildDailyPlanSnapshot(
        tasks,
        effectiveDailyPlanningEntries,
        selectedPlanDate,
        todayStr
      ),
    [tasks, effectiveDailyPlanningEntries, selectedPlanDate, todayStr]
  );

  const myDayBadgeCount = useMemo(() => {
    const activePlanDate = activeFilter === 'my_day' ? selectedPlanDate : todayStr;
    return tasks.filter((t) =>
      isTaskPlannedForDate(
        t,
        effectiveDailyPlanningEntries,
        activePlanDate,
        todayStr
      )
    ).length;
  }, [tasks, effectiveDailyPlanningEntries, activeFilter, selectedPlanDate, todayStr]);

  const unprocessedInboxItems = useMemo(
    () => getUnprocessedInboxItems(effectiveInboxItems),
    [effectiveInboxItems]
  );

  // Inbox Triage Handlers
  const handleStartEditInbox = (item: SharedInboxItem) => {
    setEditingInboxId(item.id);
    setEditingInboxText(item.rawText);
    setEditingInboxCategory(item.category);
    setEditingInboxError('');
  };

  const handleSaveEditInbox = (item: SharedInboxItem) => {
    const res = updateInboxItemRecord(item, {
      rawText: editingInboxText,
      category: editingInboxCategory,
    });
    if (!res.ok) {
      setEditingInboxError(res.error);
      return;
    }
    const next = effectiveInboxItems.map((entry) =>
      entry.id === item.id ? res.item : entry
    );
    applyInboxUpdate(next);
    setEditingInboxId(null);
    setEditingInboxText('');
    setEditingInboxError('');
  };

  const handleMarkInboxProcessed = (item: SharedInboxItem) => {
    const prevInbox = [...effectiveInboxItems];
    const { items: nextInbox } = markInboxItemProcessed(
      effectiveInboxItems,
      item.id,
      true
    );
    applyInboxUpdate(nextInbox);
    if (editingInboxId === item.id) {
      setEditingInboxId(null);
      setEditingInboxText('');
      setEditingInboxError('');
    }
    triggerUndo('Marked Inbox item as processed', () => applyInboxUpdate(prevInbox));
  };

  const executeDeleteInboxItem = (inboxId: string) => {
    const prevInbox = [...effectiveInboxItems];
    const { remaining } = deleteInboxItemFromList(effectiveInboxItems, inboxId);
    applyInboxUpdate(remaining);
    setPendingDeleteInboxItem(null);
    if (editingInboxId === inboxId) {
      setEditingInboxId(null);
      setEditingInboxText('');
      setEditingInboxError('');
    }
    triggerUndo('Deleted Inbox item', () => applyInboxUpdate(prevInbox));
  };

  // Toggle Task Completion (Complete / Reopen with Recurrence + Undo + DailyPlanningEntries sync)
  const toggleTask = (taskId: string) => {
    const prev = [...tasks];
    const prevEntries = [...effectiveDailyPlanningEntries];
    const target = tasks.find((t) => t.id === taskId);
    if (!target) return;

    const wasCompleted = isTaskCompleted(target);
    const result = completeTaskWithRecurrence(tasks, taskId, {
      todayIso: todayStr,
    });
    if (!result.updatedTask) return;

    const nextCompleted = isTaskCompleted(result.updatedTask);
    const nextEntries = syncTaskCompletionWithDailyPlanning(
      result.tasks,
      effectiveDailyPlanningEntries,
      taskId,
      nextCompleted,
      {
        preferredPlanDateIso:
          activeFilter === 'my_day' ? selectedPlanDate : undefined,
        todayIso: todayStr,
      }
    );

    if (result.generatedNextTask?.projectId) {
      projectsService.copyTaskSectionLink(
        result.generatedNextTask.projectId,
        taskId,
        result.generatedNextTask
      );
    }

    commitTasksAndDailyPlanning(result.tasks, nextEntries);
    const nextDate =
      result.generatedNextTask?.dueDate ??
      result.generatedNextTask?.scheduledDate;
    const message = wasCompleted
      ? `Reopened "${target.title}"`
      : result.generatedNextTask
        ? `Completed "${target.title}" · Next: ${nextDate ?? 'scheduled'}`
        : result.seriesEnded
          ? `Completed "${target.title}" · Recurrence series ended`
          : `Completed "${target.title}"`;
    triggerUndo(message, () => {
      if (result.generatedNextTask?.id) {
        projectsService.cleanupSectionLinksForTask(result.generatedNextTask.id);
      }
      commitTasksAndDailyPlanning(prev, prevEntries);
    });
  };

  // Skip Current Recurring Occurrence without losing the series
  const handleSkipRecurrence = (taskId: string) => {
    const prev = [...tasks];
    const prevEntries = [...effectiveDailyPlanningEntries];
    const existingTask = prev.find((t) => t.id === taskId);
    const res = skipRecurrenceOccurrence(tasks, taskId, { todayIso: todayStr });
    if (!res.ok || !res.updatedTask) {
      setDetailRecurrenceError(res.error ?? 'Unable to skip occurrence.');
      return;
    }
    setDetailRecurrenceError('');
    const targetPlanDate =
      existingTask?.myDayDate ??
      (activeFilter === 'my_day' ? selectedPlanDate : todayStr);
    const nextEntries =
      res.updatedTask.isMyDay === false && prevEntries.some((e) => e.taskId === taskId)
        ? removeTaskFromPlannedDay(res.tasks, prevEntries, taskId, targetPlanDate).entries
        : prevEntries;
    commitTasksAndDailyPlanning(res.tasks, nextEntries);
    const nextDate = res.updatedTask.dueDate ?? res.updatedTask.scheduledDate;
    triggerUndo(
      `Skipped to next occurrence${nextDate ? ` (${nextDate})` : ''}`,
      () => commitTasksAndDailyPlanning(prev, prevEntries)
    );
  };

  // Reschedule Current Recurring Occurrence without losing the series
  const handleRescheduleRecurrence = (taskId: string, newDateIso: string) => {
    const prev = [...tasks];
    const prevEntries = [...effectiveDailyPlanningEntries];
    const res = rescheduleRecurrenceOccurrence(tasks, taskId, newDateIso);
    if (!res.ok || !res.updatedTask) {
      setDetailRecurrenceError(res.error ?? 'Unable to reschedule occurrence.');
      return;
    }
    setDetailRecurrenceError('');
    commitTasksAndDailyPlanning(res.tasks, prevEntries);
    triggerUndo(`Rescheduled "${res.updatedTask.title}" to ${newDateIso}`, () =>
      commitTasksAndDailyPlanning(prev, prevEntries)
    );
  };

  // Stop Future Recurrence while preserving task history
  const handleStopRecurrence = (taskId: string) => {
    const prev = [...tasks];
    const prevEntries = [...effectiveDailyPlanningEntries];
    const res = stopTaskRecurrence(tasks, taskId);
    if (!res.ok || !res.updatedTask) {
      setDetailRecurrenceError(res.error ?? 'Unable to stop recurrence.');
      return;
    }
    setDetailRecurrenceError('');
    commitTasksAndDailyPlanning(res.tasks, prevEntries);
    triggerUndo(`Stopped recurrence for "${res.updatedTask.title}"`, () =>
      commitTasksAndDailyPlanning(prev, prevEntries)
    );
  };

  // My Day & Daily Planning Handlers
  const handleSelectPlanDate = (isoDate: string) => {
    const parsed = CalendarDate.tryParse(isoDate);
    if (!parsed) return;
    setSelectedPlanDate(parsed.toIsoString());
  };

  const handleStepPlanDate = (deltaDays: number) => {
    const parsed = CalendarDate.tryParse(selectedPlanDate) ?? CalendarDate.today();
    setSelectedPlanDate(parsed.addDays(deltaDays).toIsoString());
  };

  const handleAddTaskToDay = (
    taskId: string,
    action: 'planned' | 'carried_forward' = 'planned',
    targetDateIso?: string
  ) => {
    const dateIso = targetDateIso ?? selectedPlanDate;
    const prevTasks = [...tasks];
    const prevEntries = [...effectiveDailyPlanningEntries];
    const res = planTaskForDate(
      tasks,
      effectiveDailyPlanningEntries,
      taskId,
      dateIso,
      { action, todayIso: todayStr }
    );
    commitTasksAndDailyPlanning(res.tasks, res.entries);
    const target = tasks.find((t) => t.id === taskId);
    if (target) {
      triggerUndo(`Added "${target.title}" to ${dateIso === todayStr ? 'My Day' : dateIso}`, () =>
        commitTasksAndDailyPlanning(prevTasks, prevEntries)
      );
    }
  };

  const handleRemoveTaskFromDay = (taskId: string, targetDateIso?: string) => {
    const dateIso = targetDateIso ?? selectedPlanDate;
    const prevTasks = [...tasks];
    const prevEntries = [...effectiveDailyPlanningEntries];
    const res = removeTaskFromPlannedDay(
      tasks,
      effectiveDailyPlanningEntries,
      taskId,
      dateIso,
      { todayIso: todayStr }
    );
    commitTasksAndDailyPlanning(res.tasks, res.entries);
    const target = tasks.find((t) => t.id === taskId);
    if (target) {
      triggerUndo(
        `Removed "${target.title}" from My Day (task kept in Tasks)`,
        () => commitTasksAndDailyPlanning(prevTasks, prevEntries)
      );
    }
  };

  const handleToggleMyDay = (taskId: string) => {
    const targetDateIso =
      activeFilter === 'my_day' ? selectedPlanDate : todayStr;
    const target = tasks.find((t) => t.id === taskId);
    if (!target) return;
    const planned = isTaskPlannedForDate(
      target,
      effectiveDailyPlanningEntries,
      targetDateIso,
      todayStr
    );
    if (planned) {
      handleRemoveTaskFromDay(taskId, targetDateIso);
    } else {
      handleAddTaskToDay(taskId, 'planned', targetDateIso);
    }
  };

  const handleMovePlannedOrder = (taskId: string, direction: 'up' | 'down') => {
    const nextTasks = movePlannedTaskOrder(
      tasks,
      effectiveDailyPlanningEntries,
      selectedPlanDate,
      taskId,
      direction,
      { todayIso: todayStr }
    );
    if (typeof localStorage !== 'undefined') {
      try {
        localStorage.setItem('daywell_tasks', JSON.stringify(nextTasks));
      } catch {}
    }
    onUpdateTasks(nextTasks);
  };

  const handleCarryForwardAll = () => {
    const prevTasks = [...tasks];
    const prevEntries = [...effectiveDailyPlanningEntries];
    const res = carryForwardUnfinishedTasks(
      tasks,
      effectiveDailyPlanningEntries,
      {
        toDateIso: selectedPlanDate,
        todayIso: todayStr,
      }
    );
    if (res.carriedCount === 0) return;
    commitTasksAndDailyPlanning(res.tasks, res.entries);
    triggerUndo(
      `Carried forward ${res.carriedCount} task(s) to ${selectedPlanDate === todayStr ? 'Today' : selectedPlanDate}`,
      () => commitTasksAndDailyPlanning(prevTasks, prevEntries)
    );
  };

  const handleCarryPastRemainingToToday = () => {
    const prevTasks = [...tasks];
    const prevEntries = [...effectiveDailyPlanningEntries];
    const res = carryForwardUnfinishedTasks(
      tasks,
      effectiveDailyPlanningEntries,
      {
        fromDateIso: selectedPlanDate,
        toDateIso: todayStr,
        todayIso: todayStr,
      }
    );
    if (res.carriedCount === 0) return;
    commitTasksAndDailyPlanning(res.tasks, res.entries);
    triggerUndo(
      `Carried ${res.carriedCount} unfinished task(s) to Today`,
      () => commitTasksAndDailyPlanning(prevTasks, prevEntries)
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

  // Tag Management Handlers
  const handleAddFormLabel = (rawValue?: string) => {
    const normalized = normalizeTaskLabel(rawValue ?? newFormLabelInput);
    if (!normalized) {
      setFormLabelError('Tag name is required');
      return;
    }
    setFormLabels((prev) => normalizeTaskLabels([...prev, normalized]));
    setCustomTagCatalog((prev) => normalizeTaskLabels([...prev, normalized]));
    if (!rawValue) {
      setNewFormLabelInput('');
    }
    setFormLabelError('');
  };

  const handleToggleFormLabel = (label: string) => {
    const key = normalizeTaskLabel(label).toLowerCase();
    setFormLabels((prev) =>
      prev.some((l) => l.toLowerCase() === key)
        ? prev.filter((l) => l.toLowerCase() !== key)
        : normalizeTaskLabels([...prev, label])
    );
  };

  const handleAddDetailTag = (taskId: string, rawLabel?: string) => {
    const target = tasks.find((t) => t.id === taskId);
    if (!target) return;
    const res = assignLabelToTask(target, rawLabel ?? detailTagInput);
    if (!res.ok) {
      setDetailTagError(res.error);
      return;
    }
    const normalized = normalizeTaskLabel(rawLabel ?? detailTagInput);
    if (normalized) {
      setCustomTagCatalog((prev) => normalizeTaskLabels([...prev, normalized]));
    }
    onUpdateTasks(tasks.map((t) => (t.id === taskId ? res.task : t)));
    if (!rawLabel) setDetailTagInput('');
    setDetailTagError('');
  };

  const handleRemoveDetailTag = (taskId: string, label: string) => {
    const prev = [...tasks];
    const target = tasks.find((t) => t.id === taskId);
    if (!target) return;
    const updatedTask = removeLabelFromTask(target, label);
    onUpdateTasks(tasks.map((t) => (t.id === taskId ? updatedTask : t)));
    triggerUndo(`Removed tag "@${label}"`, () => onUpdateTasks(prev));
  };

  const handleCreateGlobalTag = () => {
    const normalized = normalizeTaskLabel(newGlobalTagInput);
    if (!normalized) {
      setGlobalTagError('Tag name is required');
      return;
    }
    const alreadyExists = availableLabels.some(
      (l) => l.toLowerCase() === normalized.toLowerCase()
    );
    if (alreadyExists) {
      setGlobalTagError(`Tag "@${normalized}" already exists`);
      return;
    }
    setCustomTagCatalog((prev) => normalizeTaskLabels([...prev, normalized]));
    setNewGlobalTagInput('');
    setGlobalTagError('');
  };

  const handleSaveGlobalTagRename = (oldLabel: string) => {
    const nextLabel = normalizeTaskLabel(editingGlobalTagTitle);
    if (!nextLabel) {
      setEditingGlobalTagError('Tag name is required');
      return;
    }
    if (nextLabel === normalizeTaskLabel(oldLabel)) {
      setEditingGlobalTag(null);
      setEditingGlobalTagTitle('');
      setEditingGlobalTagError('');
      return;
    }
    const prevTasks = [...tasks];
    const prevCatalog = [...customTagCatalog];
    const prevFilters = [...tagFilters];
    const res = renameLabelAcrossTasks(tasks, oldLabel, nextLabel);
    if (!res.ok) {
      setEditingGlobalTagError(res.error);
      return;
    }
    const oldKey = normalizeTaskLabel(oldLabel).toLowerCase();
    setCustomTagCatalog((cur) =>
      normalizeTaskLabels(
        cur.map((c) => (c.toLowerCase() === oldKey ? nextLabel : c))
      )
    );
    setTagFilters((cur) =>
      normalizeTaskLabels(
        cur.map((c) => (c.toLowerCase() === oldKey ? nextLabel : c))
      )
    );
    onUpdateTasks(res.tasks);
    setEditingGlobalTag(null);
    setEditingGlobalTagTitle('');
    setEditingGlobalTagError('');
    triggerUndo(`Renamed "@${oldLabel}" to "@${nextLabel}"`, () => {
      onUpdateTasks(prevTasks);
      setCustomTagCatalog(prevCatalog);
      setTagFilters(prevFilters);
    });
  };

  const handleDeleteGlobalTag = (label: string) => {
    const prevTasks = [...tasks];
    const prevCatalog = [...customTagCatalog];
    const prevFilters = [...tagFilters];
    const { tasks: nextTasks } = removeLabelFromAllTasks(tasks, label);
    const targetKey = normalizeTaskLabel(label).toLowerCase();
    setCustomTagCatalog((cur) =>
      cur.filter((c) => c.toLowerCase() !== targetKey)
    );
    setTagFilters((cur) => cur.filter((c) => c.toLowerCase() !== targetKey));
    onUpdateTasks(nextTasks);
    if (editingGlobalTag === label) {
      setEditingGlobalTag(null);
      setEditingGlobalTagTitle('');
      setEditingGlobalTagError('');
    }
    triggerUndo(`Removed tag "@${label}"`, () => {
      onUpdateTasks(prevTasks);
      setCustomTagCatalog(prevCatalog);
      setTagFilters(prevFilters);
    });
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
    labels: formLabels,
    hasReminder: formHasReminder,
    isRecurring: formIsRecurring,
    recurrenceFrequency: formRecurrenceFrequency,
    recurrenceInterval: formRecurrenceInterval,
    recurrenceWeekdays: formRecurrenceWeekdays,
    recurrenceStartDate: formRecurrenceStartDate,
    recurrenceEndDate: formRecurrenceEndDate,
    recurrenceRepeatFrom: formRecurrenceRepeatFrom,
    subtasks: formSubtasks,
  });

  const handleAttemptClose = () => {
    if (initialTaskValues && isFormDirty(initialTaskValues, getCurrentTaskValues())) {
      setShowUnsavedPrompt(true);
    } else {
      setIsModalOpen(false);
      setConvertingInboxItem(null);
      setFormErrors({});
    }
  };

  // Open Create Modal
  const handleOpenCreate = () => {
    setEditingTaskId(null);
    setConvertingInboxItem(null);
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
    const initLabels = tagFilters.length > 0 ? [...tagFilters] : [];
    setFormLabels(initLabels);
    setNewFormLabelInput('');
    setFormLabelError('');
    setFormHasReminder(false);
    setFormIsRecurring(false);
    setFormRecurrenceFrequency('weekly');
    setFormRecurrenceInterval(1);
    setFormRecurrenceWeekdays([]);
    setFormRecurrenceStartDate('');
    setFormRecurrenceEndDate('');
    setFormRecurrenceRepeatFrom('due_date');
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
      labels: initLabels,
      hasReminder: false,
      isRecurring: false,
      recurrenceFrequency: 'weekly',
      recurrenceInterval: 1,
      recurrenceWeekdays: [],
      recurrenceStartDate: '',
      recurrenceEndDate: '',
      recurrenceRepeatFrom: 'due_date',
      subtasks: [],
    });

    setIsModalOpen(true);
    setTimeout(() => {
      titleInputRef.current?.focus();
    }, 60);
  };

  // Open Convert Inbox Item Modal (preserves full captured content)
  const handleOpenConvertInboxItem = (item: SharedInboxItem) => {
    const draft = prepareTaskDraftFromInboxItem(item);
    const initLabels = normalizeTaskLabels([
      ...tagFilters,
      ...draft.initialLabels,
    ]);
    setDetailTaskId(null);
    setEditingTaskId(null);
    setConvertingInboxItem(item);
    setFormTitle(draft.title);
    setFormDescription(draft.description);
    setFormPriority('medium');
    setFormStatus('not_started');
    setFormDueDate('');
    setFormScheduledDate('');
    setFormScheduledTime('');
    setFormProject('Personal');
    setFormProjectId('');
    setFormMilestoneId('');
    setFormLabels(initLabels);
    setNewFormLabelInput('');
    setFormLabelError('');
    setFormHasReminder(false);
    setFormIsRecurring(false);
    setFormRecurrenceFrequency('weekly');
    setFormRecurrenceInterval(1);
    setFormRecurrenceWeekdays([]);
    setFormRecurrenceStartDate('');
    setFormRecurrenceEndDate('');
    setFormRecurrenceRepeatFrom('due_date');
    setFormSubtasks([]);
    setNewSubtaskInput('');
    setFormSubtaskError('');
    setEditingFormSubtaskId(null);
    setEditingFormSubtaskTitle('');
    setEditingFormSubtaskError('');
    setFormErrors({});
    setIsSubmitting(false);

    setInitialTaskValues({
      title: draft.title,
      description: draft.description,
      priority: 'medium',
      status: 'not_started',
      dueDate: '',
      scheduledDate: '',
      scheduledTime: '',
      projectName: 'Personal',
      projectId: '',
      milestoneId: '',
      labels: initLabels,
      hasReminder: false,
      isRecurring: false,
      recurrenceFrequency: 'weekly',
      recurrenceInterval: 1,
      recurrenceWeekdays: [],
      recurrenceStartDate: '',
      recurrenceEndDate: '',
      recurrenceRepeatFrom: 'due_date',
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
    const effectiveRec = resolveEffectiveRecurrenceConfig(task);
    const initFreq = effectiveRec?.frequency ?? 'weekly';
    const initInterval = effectiveRec?.interval ?? 1;
    const initWeekdays = effectiveRec?.weekdays ? [...effectiveRec.weekdays] : [];
    const initRecStart = effectiveRec?.startDate ?? '';
    const initRecEnd = effectiveRec?.endDate ?? '';
    const initRepeatFrom = effectiveRec?.repeatFrom ?? 'due_date';

    setDetailTaskId(null);
    setConvertingInboxItem(null);
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
    const labelsCopy = normalizeTaskLabels(task.labels);
    setFormLabels(labelsCopy);
    setNewFormLabelInput('');
    setFormLabelError('');
    setFormHasReminder(task.hasReminder);
    setFormIsRecurring(Boolean(effectiveRec));
    setFormRecurrenceFrequency(initFreq);
    setFormRecurrenceInterval(initInterval);
    setFormRecurrenceWeekdays(initWeekdays);
    setFormRecurrenceStartDate(initRecStart);
    setFormRecurrenceEndDate(initRecEnd);
    setFormRecurrenceRepeatFrom(initRepeatFrom);
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
      labels: labelsCopy,
      hasReminder: task.hasReminder,
      isRecurring: Boolean(effectiveRec),
      recurrenceFrequency: initFreq,
      recurrenceInterval: initInterval,
      recurrenceWeekdays: initWeekdays,
      recurrenceStartDate: initRecStart,
      recurrenceEndDate: initRecEnd,
      recurrenceRepeatFrom: initRepeatFrom,
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

    const recurrenceConfigPayload: SharedTaskRecurrenceConfig | undefined =
      formIsRecurring
        ? {
            frequency: formRecurrenceFrequency,
            interval: formRecurrenceInterval,
            ...(formRecurrenceFrequency === 'weekly' &&
            formRecurrenceWeekdays.length > 0
              ? { weekdays: formRecurrenceWeekdays }
              : {}),
            ...(formRecurrenceStartDate.trim()
              ? { startDate: formRecurrenceStartDate.trim() }
              : {}),
            ...(formRecurrenceEndDate.trim()
              ? { endDate: formRecurrenceEndDate.trim() }
              : {}),
            repeatFrom: formRecurrenceRepeatFrom,
          }
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
        ...(recurrenceConfigPayload
          ? { recurrenceConfig: recurrenceConfigPayload }
          : { clearRecurrenceConfig: true }),
        subtasks: formSubtasks,
        labels: formLabels,
      });

      if (!result.ok) {
        setFormErrors(result.errors);
        if (result.errors.title) titleInputRef.current?.focus();
        return;
      }

      setIsSubmitting(true);
      const prevEntries = [...effectiveDailyPlanningEntries];
      let updated = tasks.map((t) =>
        t.id === editingTaskId ? result.task : t
      );
      let spawnedTaskId: string | undefined;

      const transitionedToCompleted =
        !isTaskCompleted(existing) && isTaskCompleted(result.task);
      if (transitionedToCompleted && resolveEffectiveRecurrenceConfig(result.task)) {
        const tempOpen: DaywellTaskRecord = {
          ...result.task,
          status: 'not_started',
          completed: false,
          completedAt: undefined,
        };
        const recResult = completeTaskWithRecurrence(
          tasks.map((t) => (t.id === editingTaskId ? tempOpen : t)),
          editingTaskId,
          { todayIso: todayStr }
        );
        updated = recResult.tasks;
        spawnedTaskId = recResult.generatedNextTask?.id;
        if (recResult.generatedNextTask?.projectId) {
          projectsService.copyTaskSectionLink(
            recResult.generatedNextTask.projectId,
            editingTaskId,
            recResult.generatedNextTask
          );
        }
      }

      if (isTaskCompleted(existing) !== isTaskCompleted(result.task)) {
        const nextEntries = syncTaskCompletionWithDailyPlanning(
          updated,
          effectiveDailyPlanningEntries,
          existing.id,
          isTaskCompleted(result.task),
          {
            preferredPlanDateIso:
              activeFilter === 'my_day' ? selectedPlanDate : undefined,
            todayIso: todayStr,
          }
        );
        commitTasksAndDailyPlanning(updated, nextEntries);
      } else {
        onUpdateTasks(updated);
      }
      if (existing.projectId && existing.projectId !== cleanProjectId) {
        projectsService.cleanupSectionLinksForTask(existing.id);
      }
      setIsSubmitting(false);
      setIsModalOpen(false);
      setFormErrors({});
      triggerUndo(
        spawnedTaskId ? 'Task completed · Next occurrence scheduled' : 'Task updated',
        () => {
          if (spawnedTaskId) {
            projectsService.cleanupSectionLinksForTask(spawnedTaskId);
          }
          commitTasksAndDailyPlanning(prev, prevEntries);
        }
      );
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
        recurrenceConfig: recurrenceConfigPayload,
        subtasks: formSubtasks,
        labels: formLabels,
        isMyDay: activeFilter === 'my_day',
        myDayDate: activeFilter === 'my_day' ? selectedPlanDate : undefined,
      });

      if (!result.ok) {
        setFormErrors(result.errors);
        if (result.errors.title) titleInputRef.current?.focus();
        return;
      }

      setIsSubmitting(true);
      const prevEntries = [...effectiveDailyPlanningEntries];
      let nextTasks = [result.task, ...tasks];
      let nextEntries = effectiveDailyPlanningEntries;
      if (activeFilter === 'my_day') {
        const planned = planTaskForDate(
          nextTasks,
          effectiveDailyPlanningEntries,
          result.task.id,
          selectedPlanDate,
          { todayIso: todayStr }
        );
        nextTasks = planned.tasks;
        nextEntries = planned.entries;
        commitTasksAndDailyPlanning(nextTasks, nextEntries);
      } else {
        onUpdateTasks(nextTasks);
      }
      if (convertingInboxItem) {
        const prevInbox = [...effectiveInboxItems];
        const sourceId = convertingInboxItem.id;
        const { items: nextInbox } = markInboxItemProcessed(
          effectiveInboxItems,
          sourceId,
          true
        );
        applyInboxUpdate(nextInbox);
        setConvertingInboxItem(null);
        setIsSubmitting(false);
        setIsModalOpen(false);
        setFormErrors({});
        triggerUndo(`Converted "${result.task.title}" to Task`, () => {
          commitTasksAndDailyPlanning(prev, prevEntries);
          applyInboxUpdate(prevInbox);
        });
        return;
      }
      setIsSubmitting(false);
      setIsModalOpen(false);
      setFormErrors({});
      triggerUndo(`Added "${result.task.title}"`, () =>
        commitTasksAndDailyPlanning(prev, prevEntries)
      );
    }
  };

  // Delete Task (confirmed safely, with Undo + DailyPlanningEntries cleanup)
  const executeDeleteTask = (taskId: string) => {
    const prev = [...tasks];
    const prevEntries = [...effectiveDailyPlanningEntries];
    const { remaining, deleted } = deleteTaskFromList(tasks, taskId);
    const nextEntries = prevEntries.filter((e) => e.taskId !== taskId);
    commitTasksAndDailyPlanning(remaining, nextEntries);
    SharedStateBridge.removeDailyPlanningForTask(taskId);
    projectsService.cleanupSectionLinksForTask(taskId);
    setPendingDeleteTask(null);
    setDetailTaskId(null);
    setIsModalOpen(false);
    triggerUndo(`Deleted "${deleted?.title || 'task'}"`, () =>
      commitTasksAndDailyPlanning(prev, prevEntries)
    );
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
          {/* Search Bar, Filters Trigger, Tag Manager & Sorter */}
          <div className="flex flex-wrap items-center gap-2">
            <DaywellSearchField
              value={searchQuery}
              onChange={setSearchQuery}
              placeholder="Search tasks by title, description, or @tags..."
              ariaLabel="Search tasks and projects"
              className="flex-1 min-w-[180px]"
            />
            <DaywellButton
              label={
                activeAttributeFilterCount > 0
                  ? `Filters (${activeAttributeFilterCount})`
                  : 'Filters'
              }
              variant={showFilterPanel || activeAttributeFilterCount > 0 ? 'tonal' : 'outlined'}
              size="compact"
              leadingIcon={<SlidersHorizontal className="w-3.5 h-3.5" />}
              onClick={() => setShowFilterPanel((cur) => !cur)}
            />
            <DaywellIconButton
              label="Manage Tags"
              size="compact"
              tone="muted"
              onClick={openTagManager}
              icon={<Tag className="w-4 h-4" />}
            />
            <select
              aria-label="Sort tasks by"
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value as TaskSortBy)}
              className="min-h-[42px] text-xs bg-[var(--dw-card)] border border-[var(--dw-border)] rounded-[var(--dw-radius-md)] px-3 py-2 text-[var(--dw-text-secondary)] outline-none focus:border-[var(--dw-primary)]"
            >
              <option value="priority">Sort: Priority</option>
              <option value="due">Sort: Due Date</option>
              <option value="created">Sort: Creation Date</option>
              <option value="title">Sort: Title (A–Z)</option>
              <option value="time">Sort: Scheduled Time</option>
            </select>
          </div>

          {/* Collapsible Multi-Criteria Filter Panel */}
          {showFilterPanel && (
            <DaywellCard
              padding="sm"
              radius="lg"
              aria-label="Task filters"
              className="space-y-3 bg-[var(--dw-surface-subtle)]"
            >
              <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Status
                  </label>
                  <select
                    aria-label="Filter by status"
                    value={statusFilter}
                    onChange={(e) =>
                      setStatusFilter(e.target.value as SharedTaskStatus | '')
                    }
                    className="w-full min-h-[36px] text-xs bg-[var(--dw-card)] border border-[var(--dw-border)] rounded-[var(--dw-radius-md)] px-2.5 py-1.5 text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  >
                    <option value="">All Statuses</option>
                    {CANONICAL_TASK_STATUSES.map((s) => (
                      <option key={s} value={s}>
                        {TASK_STATUS_LABELS[s]}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Priority
                  </label>
                  <select
                    aria-label="Filter by priority"
                    value={priorityFilter}
                    onChange={(e) =>
                      setPriorityFilter(
                        e.target.value as DaywellTask['priority'] | ''
                      )
                    }
                    className="w-full min-h-[36px] text-xs bg-[var(--dw-card)] border border-[var(--dw-border)] rounded-[var(--dw-radius-md)] px-2.5 py-1.5 text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  >
                    <option value="">All Priorities</option>
                    {CANONICAL_TASK_PRIORITIES.map((p) => (
                      <option key={p} value={p}>
                        {TASK_PRIORITY_LABELS[p]}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Due Date
                  </label>
                  <select
                    aria-label="Filter by due date"
                    value={dueDateFilter}
                    onChange={(e) =>
                      setDueDateFilter(e.target.value as TaskDueDateFilter | '')
                    }
                    className="w-full min-h-[36px] text-xs bg-[var(--dw-card)] border border-[var(--dw-border)] rounded-[var(--dw-radius-md)] px-2.5 py-1.5 text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  >
                    <option value="">Any Due Date</option>
                    {(
                      Object.keys(TASK_DUE_DATE_FILTER_LABELS) as TaskDueDateFilter[]
                    ).map((key) => (
                      <option key={key} value={key}>
                        {TASK_DUE_DATE_FILTER_LABELS[key]}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Project
                  </label>
                  <select
                    aria-label="Filter by project"
                    value={effectiveProjectFilter}
                    onChange={(e) => {
                      setProjectFilter(e.target.value);
                      setSectionFilter('');
                    }}
                    className="w-full min-h-[36px] text-xs bg-[var(--dw-card)] border border-[var(--dw-border)] rounded-[var(--dw-radius-md)] px-2.5 py-1.5 text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  >
                    <option value="">All Projects</option>
                    {allActiveProjects.map((proj) => (
                      <option key={proj.id} value={proj.id}>
                        {proj.title}
                      </option>
                    ))}
                  </select>
                </div>

                {effectiveProjectFilter && (
                  <div>
                    <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                      Section
                    </label>
                    <select
                      aria-label="Filter by section"
                      value={effectiveSectionFilter}
                      onChange={(e) => setSectionFilter(e.target.value)}
                      className="w-full min-h-[36px] text-xs bg-[var(--dw-card)] border border-[var(--dw-border)] rounded-[var(--dw-radius-md)] px-2.5 py-1.5 text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                    >
                      <option value="">All Sections</option>
                      {availableSectionsForFilter.map((sec) => (
                        <option key={sec.record.id} value={sec.record.id}>
                          {sec.record.title}
                        </option>
                      ))}
                      <option value="__unsectioned__">Unsectioned</option>
                    </select>
                  </div>
                )}
              </div>

              {availableLabels.length > 0 && (
                <div className="space-y-1.5">
                  <div className="flex items-center justify-between">
                    <span className="dw-type-caption uppercase text-[var(--dw-text-muted)]">
                      Filter by Tags
                    </span>
                    <button
                      type="button"
                      onClick={openTagManager}
                      className="text-[11px] font-semibold text-[var(--dw-primary)] hover:underline cursor-pointer"
                    >
                      Manage tags
                    </button>
                  </div>
                  <div className="flex flex-wrap gap-1.5" role="group" aria-label="Filter by tags">
                    {availableLabels.map((lbl) => {
                      const selected = tagFilters.some(
                        (f) => f.toLowerCase() === lbl.toLowerCase()
                      );
                      return (
                        <button
                          key={lbl}
                          type="button"
                          onClick={() => toggleFilterTag(lbl)}
                          aria-pressed={selected}
                          className={`min-h-[30px] text-[11px] px-2.5 py-1 rounded-[var(--dw-radius-full)] font-semibold transition-colors cursor-pointer ${
                            selected
                              ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)]'
                              : 'bg-[var(--dw-card)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)] hover:border-[var(--dw-primary)]'
                          }`}
                        >
                          @{lbl}
                        </button>
                      );
                    })}
                  </div>
                </div>
              )}
            </DaywellCard>
          )}

          {/* Filter Tabs */}
          <div className="flex items-center gap-1.5 overflow-x-auto pb-0.5" role="tablist" aria-label="Task views">
            {(
              [
                { id: 'today', label: `Today (${tabCounts.todayCount})` },
                { id: 'my_day', label: `My Day (${myDayBadgeCount})` },
                {
                  id: 'inbox',
                  label:
                    unprocessedInboxItems.length > 0
                      ? `Inbox (${unprocessedInboxItems.length} · ${tabCounts.inboxCount})`
                      : `Inbox (${tabCounts.inboxCount})`,
                },
                { id: 'upcoming', label: `Upcoming (${tabCounts.upcomingCount})` },
                { id: 'active', label: `Active (${tabCounts.activePendingCount})` },
                { id: 'overdue', label: `Overdue (${tabCounts.overdueCount})` },
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

          {activeFilter !== 'inbox' && unprocessedInboxItems.length > 0 && (
            <DaywellStatusBanner
              tone="info"
              message={`${unprocessedInboxItems.length} Quick Capture item(s) waiting in Inbox`}
              actionLabel="Review Inbox"
              onActionPressed={() => setActiveFilter('inbox')}
            />
          )}

          {/* Active Filters Summary + Clear Action */}
          {hasActiveFilters && (
            <div className="flex flex-wrap items-center justify-between gap-2 px-3 py-2 bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] rounded-[var(--dw-radius-md)]">
              <div className="flex flex-wrap items-center gap-1.5 text-[11px] text-[var(--dw-text-secondary)]">
                <span className="font-semibold text-[var(--dw-text-primary)]">
                  Showing {filteredTasks.length} matching tasks
                </span>
                {statusFilter && (
                  <DaywellStatusBadge
                    tone="info"
                    showIcon={false}
                    label={`Status: ${TASK_STATUS_LABELS[statusFilter]}`}
                  />
                )}
                {priorityFilter && (
                  <DaywellStatusBadge
                    tone="warning"
                    showIcon={false}
                    label={`Priority: ${TASK_PRIORITY_LABELS[priorityFilter]}`}
                  />
                )}
                {dueDateFilter && (
                  <DaywellStatusBadge
                    tone="neutral"
                    showIcon={false}
                    label={TASK_DUE_DATE_FILTER_LABELS[dueDateFilter]}
                  />
                )}
                {effectiveProjectFilter && (
                  <DaywellStatusBadge
                    tone="neutral"
                    showIcon={false}
                    label={`Project: ${allActiveProjects.find((p) => p.id === effectiveProjectFilter)?.title ?? effectiveProjectFilter}`}
                  />
                )}
                {effectiveSectionFilter && (
                  <DaywellStatusBadge
                    tone="neutral"
                    showIcon={false}
                    label={`Section: ${
                      effectiveSectionFilter === '__unsectioned__'
                        ? 'Unsectioned'
                        : availableSectionsForFilter.find(
                            (s) => s.record.id === effectiveSectionFilter
                          )?.record.title ?? effectiveSectionFilter
                    }`}
                  />
                )}
                {tagFilters.map((lbl) => (
                  <DaywellStatusBadge
                    key={lbl}
                    tone="info"
                    showIcon={false}
                    label={`@${lbl}`}
                  />
                ))}
              </div>
              <DaywellButton
                label="Clear filters"
                variant="text"
                size="compact"
                onClick={handleClearFilters}
              />
            </div>
          )}

          {/* Status Progress Header (omitted in My Day, which shows per-day progress) */}
          {activeFilter !== 'my_day' && (
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
          )}

          {/* Shared Quick Capture Inbox Triage Section (Inbox view only) */}
          {activeFilter === 'inbox' && (
            <DaywellCard padding="sm" radius="lg" className="space-y-3">
              <div className="flex items-center justify-between gap-2">
                <div className="flex items-center gap-2 min-w-0">
                  <InboxIcon className="w-4 h-4 text-[var(--dw-primary)] shrink-0" />
                  <div className="min-w-0">
                    <h2 className="text-xs font-bold text-[var(--dw-text-primary)]">
                      Captured Inbox Items ({unprocessedInboxItems.length})
                    </h2>
                    <p className="text-[11px] text-[var(--dw-text-muted)]">
                      Unprocessed Quick Captures stay separate from Tasks until converted or dismissed.
                    </p>
                  </div>
                </div>
                {onRequestQuickCapture && (
                  <DaywellButton
                    label="Quick capture"
                    variant="tonal"
                    size="compact"
                    leadingIcon={<Plus className="w-3.5 h-3.5" />}
                    onClick={onRequestQuickCapture}
                  />
                )}
              </div>

              {unprocessedInboxItems.length === 0 ? (
                <p className="text-[11px] text-[var(--dw-text-muted)]">
                  No unprocessed Quick Capture items waiting right now.
                </p>
              ) : (
                <div className="space-y-2">
                  {unprocessedInboxItems.map((item) => {
                    const isEditingItem = editingInboxId === item.id;
                    const createdDate =
                      CalendarDate.fromUtcInstantInEthiopia(
                        new Date(item.createdAt || Date.now())
                      );
                    return (
                      <div
                        key={item.id}
                        className="p-3 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] space-y-2"
                      >
                        {isEditingItem ? (
                          <div className="space-y-2">
                            <textarea
                              aria-label="Edit captured text"
                              rows={2}
                              value={editingInboxText}
                              onChange={(e) => {
                                setEditingInboxText(e.target.value);
                                if (editingInboxError) setEditingInboxError('');
                              }}
                              className="w-full px-3 py-2 bg-[var(--dw-card)] rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                            />
                            {editingInboxError && (
                              <p className="text-[11px] text-[var(--dw-error)]">
                                {editingInboxError}
                              </p>
                            )}
                            <div className="flex flex-wrap items-center justify-between gap-2">
                              <select
                                aria-label="Inbox item category"
                                value={editingInboxCategory}
                                onChange={(e) =>
                                  setEditingInboxCategory(e.target.value as InboxItemCategory)
                                }
                                className="min-h-[34px] px-2.5 py-1 bg-[var(--dw-card)] rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                              >
                                {CANONICAL_INBOX_CATEGORIES.filter((c) => c !== 'expense').map(
                                  (cat) => (
                                    <option key={cat} value={cat}>
                                      {INBOX_CATEGORY_LABELS[cat]}
                                    </option>
                                  )
                                )}
                              </select>
                              <div className="flex items-center gap-1.5">
                                <DaywellButton
                                  label="Cancel"
                                  variant="text"
                                  size="compact"
                                  onClick={() => {
                                    setEditingInboxId(null);
                                    setEditingInboxError('');
                                  }}
                                />
                                <DaywellButton
                                  label="Save"
                                  variant="primary"
                                  size="compact"
                                  onClick={() => handleSaveEditInbox(item)}
                                />
                              </div>
                            </div>
                          </div>
                        ) : (
                          <>
                            <div className="flex items-start justify-between gap-2">
                              <p className="text-xs font-semibold text-[var(--dw-text-primary)] whitespace-pre-wrap break-words flex-1 min-w-0">
                                {item.rawText}
                              </p>
                              <DaywellStatusBadge
                                tone="info"
                                showIcon={false}
                                label={INBOX_CATEGORY_LABELS[item.category].toUpperCase()}
                              />
                            </div>
                            <p className="text-[10px] text-[var(--dw-text-muted)]">
                              Captured: {SharedDateFormatter.formatDual(createdDate, false)}
                            </p>
                            <div className="flex flex-wrap items-center gap-1.5 pt-0.5">
                              <DaywellButton
                                label="Convert to Task"
                                variant="primary"
                                size="compact"
                                leadingIcon={<ArrowRight className="w-3.5 h-3.5" />}
                                onClick={() => handleOpenConvertInboxItem(item)}
                              />
                              <DaywellButton
                                label="Edit"
                                variant="outlined"
                                size="compact"
                                leadingIcon={<Edit3 className="w-3 h-3" />}
                                onClick={() => handleStartEditInbox(item)}
                              />
                              <DaywellButton
                                label="Mark Processed"
                                variant="text"
                                size="compact"
                                onClick={() => handleMarkInboxProcessed(item)}
                              />
                              <DaywellIconButton
                                label={`Delete inbox item ${item.rawText}`}
                                size="compact"
                                tone="danger"
                                onClick={() => setPendingDeleteInboxItem(item)}
                                icon={<Trash2 className="w-3.5 h-3.5" />}
                              />
                            </div>
                          </>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
            </DaywellCard>
          )}

      {activeFilter === 'my_day' ? (
        <MyDayPlanningView
          snapshot={myDaySnapshot}
          tasks={tasks}
          entries={effectiveDailyPlanningEntries}
          selectedDate={selectedPlanDate}
          todayDate={todayStr}
          searchQuery={searchQuery}
          onSelectDate={handleSelectPlanDate}
          onStepDate={handleStepPlanDate}
          onJumpToToday={() => setSelectedPlanDate(todayStr)}
          onToggleTask={toggleTask}
          onOpenTaskDetails={(id) => setDetailTaskId(id)}
          onMoveTaskOrder={handleMovePlannedOrder}
          onRemoveFromDay={(id) => handleRemoveTaskFromDay(id)}
          onAddToDay={(id, action) => handleAddTaskToDay(id, action)}
          onCarryForwardAll={handleCarryForwardAll}
          onCarryPastRemainingToToday={handleCarryPastRemainingToToday}
          onCreateTaskForDay={handleOpenCreate}
        />
      ) : (
        <>
      {/* Task List */}
      <div className="space-y-2 pt-1">
        {activeFilter === 'inbox' && (filteredTasks.length > 0 || unprocessedInboxItems.length > 0) && (
          <div className="flex items-center justify-between px-0.5">
            <h3 className="text-xs font-bold text-[var(--dw-text-secondary)]">
              Unassigned Tasks ({filteredTasks.length})
            </h3>
          </div>
        )}
        {filteredTasks.length === 0 ? (
          activeFilter === 'inbox' && unprocessedInboxItems.length > 0 ? (
            <DaywellCard padding="compact" radius="lg">
              <p className="text-[11px] text-[var(--dw-text-muted)] text-center py-2">
                No unassigned Task records in Inbox yet. Convert a capture above or add a task anytime.
              </p>
            </DaywellCard>
          ) : (
            <DaywellEmptyState
              icon={<CheckCircle2 className="w-8 h-8" />}
              message={
                hasActiveFilters
                  ? 'No tasks match active filters'
                  : activeFilter === 'archived'
                    ? 'No archived tasks'
                    : 'No tasks in this view'
              }
              subtitle={
                hasActiveFilters
                  ? 'Try clearing or adjusting your search query, tags, or task filters.'
                  : activeFilter === 'today'
                    ? "You're all caught up for today! Plan tomorrow or capture a new task."
                    : activeFilter === 'archived'
                      ? 'Tasks you archive appear here so you can restore or remove them anytime.'
                      : 'Nothing to display for this filter.'
              }
              actionLabel={
                hasActiveFilters
                  ? 'Clear filters'
                  : activeFilter === 'archived'
                    ? undefined
                    : 'Add Task'
              }
              onActionPressed={
                hasActiveFilters
                  ? handleClearFilters
                  : activeFilter === 'archived'
                    ? undefined
                    : handleOpenCreate
              }
            />
          )
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

                      {(() => {
                        const effectiveRec = resolveEffectiveRecurrenceConfig(task);
                        if (!effectiveRec && !task.isRecurring) return null;
                        const summary = effectiveRec
                          ? formatRecurrenceSummary(effectiveRec)
                          : 'Recurring';
                        return (
                          <span
                            className="inline-flex items-center gap-0.5 text-[var(--dw-text-secondary)] font-medium"
                            title={summary}
                          >
                            <Repeat2 className="w-3 h-3 text-[var(--dw-primary)]" />
                            <span>{summary}</span>
                          </span>
                        );
                      })()}

                      {(task.labels ?? []).map((lbl) => (
                        <span
                          key={lbl}
                          className="inline-flex items-center px-2 py-0.5 rounded-[var(--dw-radius-full)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[10px] font-semibold text-[var(--dw-text-secondary)]"
                        >
                          @{lbl}
                        </span>
                      ))}
                    </div>
                  </div>

                  {/* Badges & Quick Actions */}
                  <div className="flex items-center gap-1 text-[var(--dw-text-muted)] shrink-0">
                    {task.hasReminder && <Bell className="w-3.5 h-3.5" aria-label="Has reminder" />}
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
                      <>
                        <DaywellIconButton
                          label={
                            isTaskPlannedForDate(
                              task,
                              effectiveDailyPlanningEntries,
                              todayStr,
                              todayStr
                            )
                              ? `Remove ${task.title} from My Day`
                              : `Add ${task.title} to My Day`
                          }
                          size="compact"
                          tone={
                            isTaskPlannedForDate(
                              task,
                              effectiveDailyPlanningEntries,
                              todayStr,
                              todayStr
                            )
                              ? 'primary'
                              : 'muted'
                          }
                          onClick={() => handleToggleMyDay(task.id)}
                          icon={<Sun className="w-3.5 h-3.5" />}
                        />
                        <DaywellIconButton
                          label={`Edit ${task.title}`}
                          size="compact"
                          tone="muted"
                          onClick={() => handleOpenEdit(task)}
                          icon={<Edit3 className="w-3.5 h-3.5" />}
                        />
                      </>
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
        </>
      )}

      {/* TASK MODAL (Create, Convert from Inbox, & Edit) */}
      {isModalOpen && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={
            editingTaskId
              ? 'Edit Task'
              : convertingInboxItem
                ? 'Convert Inbox Item to Task'
                : 'Create New Task'
          }
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs"
          onClick={(e) => {
            if (e.target === e.currentTarget) handleAttemptClose();
          }}
        >
          <div className="w-full max-w-md bg-[var(--dw-elevated)] rounded-[var(--dw-radius-xl)] p-5 shadow-2xl border border-[var(--dw-border)] space-y-4 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <h2 className="dw-type-title text-[var(--dw-text-primary)]">
                {editingTaskId
                  ? 'Edit Task'
                  : convertingInboxItem
                    ? 'Convert Inbox Item to Task'
                    : 'Create New Task'}
              </h2>
              <DaywellIconButton
                label="Close task dialog"
                size="compact"
                tone="muted"
                onClick={handleAttemptClose}
                icon={<X className="w-4 h-4" />}
              />
            </div>

            {convertingInboxItem && (
              <DaywellStatusBanner
                tone="info"
                title={`From Quick Capture (${INBOX_CATEGORY_LABELS[convertingInboxItem.category]})`}
                message="Assign a project, priority, tags, or schedule below. Saving converts this item into a Task and marks the Inbox capture processed."
              />
            )}

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

              {/* Tags / Labels editor */}
              <div className="space-y-2 pt-2 border-t border-[var(--dw-divider)]">
                <div className="flex items-center justify-between gap-2">
                  <label className="block dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
                    Tags / Labels (Optional)
                  </label>
                  <button
                    type="button"
                    onClick={() => setIsTagManagerOpen(true)}
                    className="text-[11px] font-semibold text-[var(--dw-primary)] hover:underline cursor-pointer"
                  >
                    Manage all tags
                  </button>
                </div>

                {formLabels.length > 0 && (
                  <div className="flex flex-wrap gap-1.5">
                    {formLabels.map((lbl) => (
                      <span
                        key={lbl}
                        className="inline-flex items-center gap-1 px-2.5 py-1 rounded-[var(--dw-radius-full)] bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)] text-[11px] font-semibold"
                      >
                        <span>@{lbl}</span>
                        <button
                          type="button"
                          aria-label={`Remove tag ${lbl}`}
                          onClick={() => handleToggleFormLabel(lbl)}
                          className="hover:opacity-75 cursor-pointer"
                        >
                          <X className="w-3 h-3" />
                        </button>
                      </span>
                    ))}
                  </div>
                )}

                <div className="flex items-center gap-2">
                  <input
                    aria-label="Add task tag"
                    type="text"
                    placeholder="Add tag (e.g. work, finance)..."
                    value={newFormLabelInput}
                    onChange={(e) => {
                      setNewFormLabelInput(e.target.value);
                      if (formLabelError) setFormLabelError('');
                    }}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        e.preventDefault();
                        handleAddFormLabel();
                      }
                    }}
                    className={`flex-1 min-h-[38px] px-3 py-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)] ${
                      formLabelError ? 'border-[var(--dw-error)]' : 'border-[var(--dw-border)]'
                    }`}
                  />
                  <DaywellButton
                    label="Add"
                    variant="tonal"
                    size="compact"
                    onClick={() => handleAddFormLabel()}
                  />
                </div>
                {formLabelError && (
                  <p className="text-[11px] text-[var(--dw-error)]">{formLabelError}</p>
                )}

                {availableLabels.length > 0 && (
                  <div className="flex flex-wrap gap-1">
                    {availableLabels
                      .filter(
                        (lbl) =>
                          !formLabels.some(
                            (cur) => cur.toLowerCase() === lbl.toLowerCase()
                          )
                      )
                      .map((lbl) => (
                        <button
                          key={lbl}
                          type="button"
                          onClick={() => handleAddFormLabel(lbl)}
                          className="text-[11px] px-2 py-0.5 rounded-[var(--dw-radius-full)] bg-[var(--dw-card)] border border-[var(--dw-border)] text-[var(--dw-text-secondary)] hover:border-[var(--dw-primary)] cursor-pointer"
                        >
                          + @{lbl}
                        </button>
                      ))}
                  </div>
                )}
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

              {/* Options, Reminders & Recurrence */}
              <div className="space-y-2.5 pt-1">
                <label className="flex items-center gap-2 p-2.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formHasReminder}
                    onChange={(e) => setFormHasReminder(e.target.checked)}
                    className="w-4 h-4 accent-[var(--dw-primary)]"
                  />
                  <span className="text-xs font-semibold text-[var(--dw-text-secondary)]">Set Reminder</span>
                </label>

                <TaskRecurrenceEditorSection
                  isRecurring={formIsRecurring}
                  onToggleRecurring={setFormIsRecurring}
                  frequency={formRecurrenceFrequency}
                  onChangeFrequency={setFormRecurrenceFrequency}
                  interval={formRecurrenceInterval}
                  onChangeInterval={setFormRecurrenceInterval}
                  weekdays={formRecurrenceWeekdays}
                  onChangeWeekdays={setFormRecurrenceWeekdays}
                  startDate={formRecurrenceStartDate}
                  onChangeStartDate={setFormRecurrenceStartDate}
                  endDate={formRecurrenceEndDate}
                  onChangeEndDate={setFormRecurrenceEndDate}
                  repeatFrom={formRecurrenceRepeatFrom}
                  onChangeRepeatFrom={setFormRecurrenceRepeatFrom}
                  dueDate={formDueDate}
                  scheduledDate={formScheduledDate}
                  errors={formErrors}
                />
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
                    label={
                      isSubmitting
                        ? 'Saving...'
                        : editingTaskId
                          ? 'Save Changes'
                          : convertingInboxItem
                            ? 'Convert to Task'
                            : 'Create Task'
                    }
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
                  <div className="flex items-center gap-1 shrink-0">
                    {!detailTask.isArchived && (
                      <DaywellIconButton
                        label={
                          isTaskPlannedForDate(
                            detailTask,
                            effectiveDailyPlanningEntries,
                            activeFilter === 'my_day'
                              ? selectedPlanDate
                              : todayStr,
                            todayStr
                          )
                            ? 'Remove from My Day'
                            : 'Add to My Day'
                        }
                        size="compact"
                        tone={
                          isTaskPlannedForDate(
                            detailTask,
                            effectiveDailyPlanningEntries,
                            activeFilter === 'my_day'
                              ? selectedPlanDate
                              : todayStr,
                            todayStr
                          )
                            ? 'primary'
                            : 'muted'
                        }
                        onClick={() => handleToggleMyDay(detailTask.id)}
                        icon={<Sun className="w-4 h-4" />}
                      />
                    )}
                    <DaywellIconButton
                      label="Close task details"
                      size="compact"
                      tone="muted"
                      onClick={() => setDetailTaskId(null)}
                      icon={<X className="w-4 h-4" />}
                    />
                  </div>
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
                  {isTaskPlannedForDate(
                    detailTask,
                    effectiveDailyPlanningEntries,
                    activeFilter === 'my_day' ? selectedPlanDate : todayStr,
                    todayStr
                  ) && (
                    <DaywellStatusBadge
                      tone="success"
                      icon={<Sun className="w-3 h-3" />}
                      label={
                        activeFilter === 'my_day' && selectedPlanDate !== todayStr
                          ? `Planned · ${selectedPlanDate}`
                          : 'In My Day'
                      }
                    />
                  )}
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
                    {onNavigateToCalendar && parsedScheduled ? (
                      <button
                        type="button"
                        onClick={() => {
                          setDetailTaskId(null);
                          onNavigateToCalendar(parsedScheduled.toIsoString());
                        }}
                        className="font-semibold text-[var(--dw-primary)] hover:underline cursor-pointer text-right"
                      >
                        {SharedDateFormatter.formatDual(parsedScheduled, false)}
                        {detailTask.scheduledTime ? ` · ${detailTask.scheduledTime}` : ''}
                      </button>
                    ) : (
                      <span className="font-semibold text-[var(--dw-text-primary)]">
                        {parsedScheduled
                          ? SharedDateFormatter.formatDual(parsedScheduled, false)
                          : detailTask.scheduledDate || 'Not set'}
                        {detailTask.scheduledTime ? ` · ${detailTask.scheduledTime}` : ''}
                      </span>
                    )}
                  </div>
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-[var(--dw-text-muted)]">Due Date</span>
                    {onNavigateToCalendar && parsedDue ? (
                      <button
                        type="button"
                        onClick={() => {
                          setDetailTaskId(null);
                          onNavigateToCalendar(parsedDue.toIsoString());
                        }}
                        className="font-semibold text-[var(--dw-primary)] hover:underline cursor-pointer text-right"
                      >
                        {SharedDateFormatter.formatDual(parsedDue, false)}
                      </button>
                    ) : (
                      <span className="font-semibold text-[var(--dw-text-primary)]">
                        {parsedDue
                          ? SharedDateFormatter.formatDual(parsedDue, false)
                          : detailTask.dueDate || 'Not set'}
                      </span>
                    )}
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

                {/* Recurrence Series & Actions */}
                <TaskRecurrenceDetailsPanel
                  task={detailTask}
                  actionError={detailRecurrenceError}
                  onSkipOccurrence={() => handleSkipRecurrence(detailTask.id)}
                  onRescheduleOccurrence={(newDateIso) =>
                    handleRescheduleRecurrence(detailTask.id, newDateIso)
                  }
                  onEditRecurrence={() => handleOpenEdit(detailTask)}
                  onStopRecurrence={() => handleStopRecurrence(detailTask.id)}
                />

                {/* Tags / Labels Section inside Task Details */}
                <div className="space-y-2 p-3 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)]">
                  <div className="flex items-center justify-between gap-2">
                    <span className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-secondary)]">
                      Tags
                    </span>
                    <button
                      type="button"
                      onClick={() => setIsTagManagerOpen(true)}
                      className="text-[11px] font-semibold text-[var(--dw-primary)] hover:underline cursor-pointer"
                    >
                      Manage tags
                    </button>
                  </div>
                  {(detailTask.labels ?? []).length > 0 ? (
                    <div className="flex flex-wrap gap-1.5">
                      {(detailTask.labels ?? []).map((lbl) => (
                        <span
                          key={lbl}
                          className="inline-flex items-center gap-1 px-2.5 py-1 rounded-[var(--dw-radius-full)] bg-[var(--dw-card)] border border-[var(--dw-border)] text-[11px] font-semibold text-[var(--dw-text-primary)]"
                        >
                          <span>@{lbl}</span>
                          <button
                            type="button"
                            aria-label={`Remove tag ${lbl} from task`}
                            onClick={() => handleRemoveDetailTag(detailTask.id, lbl)}
                            className="text-[var(--dw-text-muted)] hover:text-[var(--dw-error)] cursor-pointer"
                          >
                            <X className="w-3 h-3" />
                          </button>
                        </span>
                      ))}
                    </div>
                  ) : (
                    <p className="text-[11px] text-[var(--dw-text-muted)] italic">
                      No tags assigned yet.
                    </p>
                  )}

                  <div className="flex items-center gap-2 pt-0.5">
                    <input
                      aria-label="Assign tag to task"
                      type="text"
                      placeholder="Add tag..."
                      value={detailTagInput}
                      onChange={(e) => {
                        setDetailTagInput(e.target.value);
                        if (detailTagError) setDetailTagError('');
                      }}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') {
                          e.preventDefault();
                          handleAddDetailTag(detailTask.id);
                        }
                      }}
                      className={`flex-1 min-h-[36px] px-3 py-1 bg-[var(--dw-card)] rounded-[var(--dw-radius-md)] border text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)] ${
                        detailTagError ? 'border-[var(--dw-error)]' : 'border-[var(--dw-border)]'
                      }`}
                    />
                    <DaywellButton
                      label="Add"
                      variant="tonal"
                      size="compact"
                      onClick={() => handleAddDetailTag(detailTask.id)}
                    />
                  </div>
                  {detailTagError && (
                    <p className="text-[11px] text-[var(--dw-error)]">{detailTagError}</p>
                  )}

                  {availableLabels.some(
                    (lbl) =>
                      !(detailTask.labels ?? []).some(
                        (assigned) => assigned.toLowerCase() === lbl.toLowerCase()
                      )
                  ) && (
                    <div className="flex flex-wrap gap-1">
                      {availableLabels
                        .filter(
                          (lbl) =>
                            !(detailTask.labels ?? []).some(
                              (assigned) =>
                                assigned.toLowerCase() === lbl.toLowerCase()
                            )
                        )
                        .map((lbl) => (
                          <button
                            key={lbl}
                            type="button"
                            onClick={() => handleAddDetailTag(detailTask.id, lbl)}
                            className="text-[11px] px-2 py-0.5 rounded-[var(--dw-radius-full)] bg-[var(--dw-card)] border border-[var(--dw-border)] text-[var(--dw-text-secondary)] hover:border-[var(--dw-primary)] cursor-pointer"
                          >
                            + @{lbl}
                          </button>
                        ))}
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
                  <div className="flex flex-wrap items-center gap-2">
                    {onNavigateToCalendar &&
                      (() => {
                        const primaryCalDate =
                          getTaskPrimaryCalendarDate(detailTask);
                        if (!primaryCalDate) return null;
                        return (
                          <DaywellButton
                            label="View in Calendar"
                            variant="outlined"
                            size="compact"
                            leadingIcon={<Calendar className="w-3.5 h-3.5" />}
                            onClick={() => {
                              setDetailTaskId(null);
                              onNavigateToCalendar(primaryCalDate);
                            }}
                          />
                        );
                      })()}
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

      {/* Manage Tags Modal */}
      {isTagManagerOpen && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Manage Tags"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs"
          onClick={(e) => {
            if (e.target === e.currentTarget) setIsTagManagerOpen(false);
          }}
        >
          <div className="w-full max-w-md bg-[var(--dw-elevated)] rounded-[var(--dw-radius-xl)] p-5 shadow-2xl border border-[var(--dw-border)] space-y-4 max-h-[85vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <div>
                <span className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
                  Task Organization
                </span>
                <h2 className="dw-type-title text-[var(--dw-text-primary)]">
                  Manage Tags
                </h2>
              </div>
              <DaywellIconButton
                label="Close manage tags"
                size="compact"
                tone="muted"
                onClick={() => setIsTagManagerOpen(false)}
                icon={<X className="w-4 h-4" />}
              />
            </div>

            <div className="space-y-1.5">
              <div className="flex items-center gap-2">
                <input
                  aria-label="New tag name"
                  type="text"
                  placeholder="Create new tag (e.g. urgent-ops)..."
                  value={newGlobalTagInput}
                  onChange={(e) => {
                    setNewGlobalTagInput(e.target.value);
                    if (globalTagError) setGlobalTagError('');
                  }}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      e.preventDefault();
                      handleCreateGlobalTag();
                    }
                  }}
                  className={`flex-1 min-h-[38px] px-3 py-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)] ${
                    globalTagError ? 'border-[var(--dw-error)]' : 'border-[var(--dw-border)]'
                  }`}
                />
                <DaywellButton
                  label="Create"
                  variant="primary"
                  size="compact"
                  onClick={handleCreateGlobalTag}
                />
              </div>
              {globalTagError && (
                <p className="text-[11px] text-[var(--dw-error)]">{globalTagError}</p>
              )}
            </div>

            {availableLabels.length === 0 ? (
              <p className="text-xs text-[var(--dw-text-muted)] italic py-2">
                No tags created yet. Add one above or attach tags directly inside any task.
              </p>
            ) : (
              <div className="space-y-1.5">
                {availableLabels.map((lbl) => {
                  const taskCount = tasks.filter((t) =>
                    (t.labels ?? []).some(
                      (item) => item.toLowerCase() === lbl.toLowerCase()
                    )
                  ).length;
                  const isEditingThis = editingGlobalTag === lbl;
                  return (
                    <div
                      key={lbl}
                      className="p-2.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] space-y-1.5"
                    >
                      {isEditingThis ? (
                        <div className="space-y-1">
                          <div className="flex items-center gap-1.5">
                            <input
                              aria-label={`Rename tag ${lbl}`}
                              type="text"
                              value={editingGlobalTagTitle}
                              onChange={(e) => {
                                setEditingGlobalTagTitle(e.target.value);
                                if (editingGlobalTagError) setEditingGlobalTagError('');
                              }}
                              onKeyDown={(e) => {
                                if (e.key === 'Enter') {
                                  e.preventDefault();
                                  handleSaveGlobalTagRename(lbl);
                                } else if (e.key === 'Escape') {
                                  setEditingGlobalTag(null);
                                  setEditingGlobalTagTitle('');
                                  setEditingGlobalTagError('');
                                }
                              }}
                              className="flex-1 min-h-[34px] px-2.5 py-1 bg-[var(--dw-card)] rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                            />
                            <DaywellIconButton
                              label={`Save tag ${lbl}`}
                              size="compact"
                              tone="primary"
                              onClick={() => handleSaveGlobalTagRename(lbl)}
                              icon={<Check className="w-3.5 h-3.5" />}
                            />
                            <DaywellIconButton
                              label="Cancel rename tag"
                              size="compact"
                              tone="muted"
                              onClick={() => {
                                setEditingGlobalTag(null);
                                setEditingGlobalTagTitle('');
                                setEditingGlobalTagError('');
                              }}
                              icon={<X className="w-3.5 h-3.5" />}
                            />
                          </div>
                          {editingGlobalTagError && (
                            <p className="text-[11px] text-[var(--dw-error)]">
                              {editingGlobalTagError}
                            </p>
                          )}
                        </div>
                      ) : (
                        <div className="flex items-center justify-between gap-2">
                          <div className="min-w-0">
                            <span className="text-xs font-semibold text-[var(--dw-text-primary)]">
                              @{lbl}
                            </span>
                            <span className="ml-2 text-[11px] text-[var(--dw-text-muted)]">
                              ({taskCount} {taskCount === 1 ? 'task' : 'tasks'})
                            </span>
                          </div>
                          <div className="flex items-center gap-1 shrink-0">
                            <DaywellIconButton
                              label={`Rename tag ${lbl}`}
                              size="compact"
                              tone="muted"
                              onClick={() => {
                                setEditingGlobalTag(lbl);
                                setEditingGlobalTagTitle(lbl);
                                setEditingGlobalTagError('');
                              }}
                              icon={<Edit3 className="w-3.5 h-3.5" />}
                            />
                            <DaywellIconButton
                              label={`Remove tag ${lbl}`}
                              size="compact"
                              tone="danger"
                              onClick={() => handleDeleteGlobalTag(lbl)}
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
          </div>
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

      {/* Safe Delete Inbox Item Confirmation Dialog */}
      <DaywellConfirmationDialog
        isOpen={Boolean(pendingDeleteInboxItem)}
        title="Delete Inbox item?"
        description={
          pendingDeleteInboxItem
            ? `Remove "${pendingDeleteInboxItem.rawText}" from your Inbox? You can undo immediately afterward.`
            : ''
        }
        confirmLabel="Delete Item"
        cancelLabel="Cancel"
        destructive
        onCancel={() => setPendingDeleteInboxItem(null)}
        onConfirm={() => {
          if (pendingDeleteInboxItem) {
            executeDeleteInboxItem(pendingDeleteInboxItem.id);
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
          setConvertingInboxItem(null);
          setFormErrors({});
        }}
      />
    </div>
  );
}
export { DEFAULT_SAMPLE_TASKS };
