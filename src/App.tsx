import React, { useState, useEffect, useMemo } from 'react';
import {
  Calendar,
  CheckCircle2,
  Layers,
  Grid2X2,
  Plus,
  SlidersHorizontal,
  ArrowUpRight,
  Clock3,
  Flag,
  Bell,
  Repeat2,
  Landmark,
  HardDrive,
  ChevronRight,
  ChevronLeft,
  Search,
  Check,
  Target,
  NotebookPen,
  Wallet,
  UsersRound,
  ListOrdered,
  Calculator,
  ChartNoAxesColumn,
  SunMoon,
  Send,
  Database,
  Info,
  ShieldCheck,
  Download,
  FolderOpen,
  CloudOff,
  RefreshCw,
  FileQuestion,
  X,
  FileText,
  CalendarDays,
  Inbox as InboxIcon,
  Archive,
  ArrowLeft,
  Smartphone,
  Monitor,
  Eye,
  CheckSquare,
  Sparkles,
  Sun,
} from 'lucide-react';

import { CalendarDate, EthiopiaClock, LocalDateTime, SharedDateFormatter } from './domain/date';
import { formatBirr, formatCentsAsInput } from './domain/financialEngine';
import {
  parseQuickCaptureExpense,
  Account,
  CategoryBudget,
  Debt,
  JournalEntry,
  Posting,
  SettlementAllocation,
  SimpleTransaction,
} from './domain/doubleEntryFinance';
import {
  buildQuickCaptureExpenseEntryV7,
  calculateAvailableToSpendBreakdownV7,
  classifyAllJournalEntries,
  formatCurrencyCents,
  hydrateLedgerFromSimpleTransactions,
  isActiveVerifiedEtbAccount,
  resolveActiveExpenseCategoryIdV7,
  SharedCommitment,
  SharedCommitmentSettlement,
  SharedRecurringRule,
  SharedSavingsGoal,
  TransactionCategory,
} from './domain/financeV7Engine';
import { FinanceComposerPrefill } from './components/finance/financeV7Types';
import { DaywellFinanceModule } from './components/DaywellFinanceModule';
import { DaywellCalendarModule } from './components/DaywellCalendarModule';
import { DaywellTasksModule, DaywellTask, DEFAULT_SAMPLE_TASKS } from './components/DaywellTasksModule';
import { DaywellNotesModule, DaywellNote } from './components/DaywellNotesModule';
import { FirstTimeSetupWizard, UserProfile } from './components/FirstTimeSetupWizard';
import { UnsavedChangesDialog } from './components/UnsavedChangesDialog';
import { SharedStateBridge } from './services/sharedStateBridge';
import { dailyPlanningService } from './services/dailyPlanningService';
import { dailyRhythmService } from './services/dailyRhythmService';
import { dailyRhythmWorkflowService } from './services/dailyRhythmWorkflowService';
import { inboxService } from './services/inboxService';
import { notesService } from './services/notesService';
import { projectsService } from './services/projectsService';
import { normalizeNoteTitle } from './domain/noteHelpers';
import { createQuickCaptureNoteRecord } from './domain/webNotesLifecycle';
import {
  createEmptyDailyRhythmDay,
  DailyRhythmDayRecord,
  evaluateDailyRhythmTimeline,
} from './domain/dailyRhythm';
import {
  taskRemindersService,
  WebNotificationSupportStatus,
  WebTaskReminderAlert,
} from './services/taskRemindersService';
import {
  getProcessedInboxItems,
  getUnprocessedInboxItems,
  INBOX_CATEGORY_LABELS,
} from './domain/inboxOperations';
import { syncTaskCompletionWithDailyPlanning } from './domain/dailyPlanningOperations';
import {
  isTaskCompleted,
  TaskDueDateFilter,
  TaskViewFilter,
} from './domain/taskOperations';
import {
  buildProjectsOverviewSummary,
  buildTaskOverviewSummary,
} from './domain/taskSummaries';
import {
  completeTaskWithRecurrence,
  formatRecurrenceSummary,
  resolveEffectiveRecurrenceConfig,
} from './domain/taskRecurrence';
import {
  SharedDailyPlanningEntry,
  SharedInboxItem,
  SHARED_DESIGN_TOKENS,
} from './domain/sharedFoundation';
import {
  buildDailyRhythmDashboardOverview,
  buildDailyRhythmTaskReviewSnapshot,
  DailyRhythmFaithStep,
  inspectDailyRhythmFinanceDay,
} from './domain/dailyRhythmWorkflows';
import {
  DailyFaithCheckInCard,
  DailyRhythmDashboardCard,
} from './components/daily-rhythm';
import {
  DaywellButton,
  DaywellCard,
  DaywellEmptyState,
  DaywellIconButton,
  DaywellProgressBar,
  DaywellSectionHeader,
  DaywellStatusBadge,
  DaywellStatusBanner,
  DeprecatedPrototypeBanner,
} from './components/ui';

export type ScreenId =
  | 'today'
  | 'tasks'
  | 'calendar'
  | 'projects'
  | 'project_detail'
  | 'goals'
  | 'notes'
  | 'finance'
  | 'relationships'
  | 'priorities'
  | 'tools'
  | 'history'
  | 'more'
  | 'sync_backup';

export default function App() {
  // Navigation & Screen View State
  const [currentTab, setCurrentTab] = useState<'today' | 'tasks' | 'calendar' | 'notes' | 'finance' | 'more'>('today');
  const [activeScreen, setActiveScreen] = useState<ScreenId>('today');
  const [screenHistory, setScreenHistory] = useState<ScreenId[]>(['today']);
  const [tasksSubTab, setTasksSubTab] = useState<'tasks' | 'projects'>('tasks');
  const [selectedProjectId, setSelectedProjectId] = useState<string | null>(null);

  // Theme State: 'system' | 'light' | 'dark'
  const [themeMode, setThemeMode] = useState<'system' | 'light' | 'dark'>('system');
  const [effectiveDark, setEffectiveDark] = useState<boolean>(false);

  // User Profile State (Safe Startup: default completed=true to reliably show Home screen)
  const [userProfile, setUserProfile] = useState<UserProfile>(() => {
    try {
      const saved = localStorage.getItem('daywell_user_profile');
      if (saved) {
        const parsed = JSON.parse(saved);
        if (parsed && typeof parsed.name === 'string') {
          return parsed;
        }
      }
    } catch (e) {
      // ignore
    }
    return { name: 'Friend', completed: true };
  });
  const [isEditingProfileName, setIsEditingProfileName] = useState(false);
  const [profileNameInput, setProfileNameInput] = useState('');
  const [isSetupWizardOpen, setIsSetupWizardOpen] = useState(false);

  const handleSetupComplete = (profile: UserProfile, setupAccounts: Account[], setupBudgets: CategoryBudget[]) => {
    setUserProfile(profile);
    setIsSetupWizardOpen(false);
    try {
      localStorage.setItem('daywell_user_profile', JSON.stringify(profile));
      localStorage.setItem('daywell_accounts', JSON.stringify(setupAccounts));
      if (setupBudgets.length > 0) {
        localStorage.setItem('daywell_budgets', JSON.stringify(setupBudgets));
      }
    } catch (e) {
      console.error(e);
    }
  };

  // Quick Capture Modal State (Figma Screen 14)
  const [isQuickCaptureOpen, setIsQuickCaptureOpen] = useState(false);
  const [quickCaptureType, setQuickCaptureType] = useState<'task' | 'idea' | 'note' | 'expense' | 'reminder'>('task');
  const [quickCaptureInput, setQuickCaptureInput] = useState('');
  const [quickCaptureExpenseAccount, setQuickCaptureExpenseAccount] = useState('CBE');
  const [quickCaptureToast, setQuickCaptureToast] = useState<string | null>(null);
  const [quickCaptureError, setQuickCaptureError] = useState<string | null>(null);
  const [showUnsavedQuickCapture, setShowUnsavedQuickCapture] = useState(false);
  const [isSubmittingQuickCapture, setIsSubmittingQuickCapture] = useState(false);
  const [sharedFoundationToast, setSharedFoundationToast] = useState<string | null>(null);
  const [financeComposerPrefill, setFinanceComposerPrefill] =
    useState<FinanceComposerPrefill | null>(null);
  const [financeSyncTick, setFinanceSyncTick] = useState(0);
  const [requestedTasksFilter, setRequestedTasksFilter] = useState<{
    filter: TaskViewFilter;
    dueDateFilter?: TaskDueDateFilter | '';
    planDate?: string;
    nonce: number;
  } | null>(null);
  const [requestedTaskFocus, setRequestedTaskFocus] = useState<{
    taskId: string;
    openMode?: 'details' | 'edit';
    nonce: number;
  } | null>(null);
  const [requestedCalendarFocus, setRequestedCalendarFocus] = useState<{
    dateStr: string;
    nonce: number;
  } | null>(null);
  const [requestedNoteFocus, setRequestedNoteFocus] = useState<{
    noteId: string;
    nonce: number;
  } | null>(null);
  const [requestedFinanceTab, setRequestedFinanceTab] = useState<{
    tab: 'overview' | 'transactions' | 'plan' | 'reports';
    nonce: number;
  } | null>(null);
  const [dueReminderAlerts, setDueReminderAlerts] = useState<WebTaskReminderAlert[]>([]);
  const [isNotificationStatusModalOpen, setIsNotificationStatusModalOpen] = useState(false);
  const [notificationSupportStatus, setNotificationSupportStatus] =
    useState<WebNotificationSupportStatus>(() =>
      taskRemindersService.getWebNotificationSupportStatus()
    );
  const [activeTaskReminderCount, setActiveTaskReminderCount] = useState<number>(() =>
    taskRemindersService.loadTaskReminders().filter((r) => r.isActive).length
  );

  const handleExportSharedFoundation = () => {
    const json = SharedStateBridge.exportToAndroidJson();
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `daywell_canonical_backup_${CalendarDate.today().toIsoString()}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    setSharedFoundationToast('Shared database exported! Compatible with Android.');
    setTimeout(() => setSharedFoundationToast(null), 4000);
  };

  const handleImportSharedFoundation = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (event) => {
      const content = event.target?.result as string;
      if (!content) return;
      const res = SharedStateBridge.importFromAndroidJson(content);
      if (res.success && res.state) {
        setSharedFoundationToast('Shared database restored! Synced with Android state.');
        setTimeout(() => {
          setSharedFoundationToast(null);
          window.location.reload();
        }, 1200);
      } else {
        setSharedFoundationToast(
          `Import rejected (existing data preserved): ${res.error || 'Failed to parse JSON'}`
        );
        setTimeout(() => setSharedFoundationToast(null), 6000);
      }
    };
    reader.readAsText(file);
  };

  // Filter & Search states
  const [taskFilter, setTaskFilter] = useState<'today' | 'inbox' | 'upcoming'>('today');
  const [goalFilter, setGoalFilter] = useState<'all' | 'short' | 'long'>('all');
  const [noteFilter, setNoteFilter] = useState<'recent' | 'inbox' | 'collections'>('recent');
  const [searchQuery, setSearchQuery] = useState('');

  // Viewport View: 'desktop' | 'mobile_frame' | 'side_by_side'
  const [viewMode, setViewMode] = useState<'desktop' | 'mobile_frame' | 'side_by_side'>(() => {
    if (
      typeof window !== 'undefined' &&
      window.innerWidth >= SHARED_DESIGN_TOKENS.breakpoints.expanded
    ) {
      return 'desktop';
    }
    return 'mobile_frame';
  });

  // Application Data State (Persistent Daywell Tasks with subtasks & deadlines)
  const [tasks, setTasks] = useState<DaywellTask[]>(() => {
    try {
      const saved = localStorage.getItem('daywell_tasks');
      if (saved) {
        const parsed = JSON.parse(saved);
        if (Array.isArray(parsed) && parsed.length > 0) return parsed;
      }
    } catch (e) {
      // ignore
    }
    return [];
  });

  const [inboxItems, setInboxItems] = useState<SharedInboxItem[]>(() =>
    inboxService.loadInboxItems()
  );

  const [dailyPlanningEntries, setDailyPlanningEntries] = useState<
    SharedDailyPlanningEntry[]
  >(() => dailyPlanningService.loadDailyPlanningEntries());

  const [notes, setNotes] = useState<DaywellNote[]>(() =>
    notesService.loadNotes()
  );

  const [dailyRhythmDays, setDailyRhythmDays] = useState<DailyRhythmDayRecord[]>(
    () => dailyRhythmService.loadDays()
  );
  const [faithFeedback, setFaithFeedback] = useState<string | null>(null);
  const [faithError, setFaithError] = useState<string | null>(null);

  const handleUpdateInboxItems = (next: SharedInboxItem[]) => {
    const saved = inboxService.saveInboxItems(next);
    setInboxItems(saved);
  };

  const handleUpdateDailyPlanningEntries = (
    next: SharedDailyPlanningEntry[]
  ) => {
    const saved = dailyPlanningService.saveDailyPlanningEntries(next);
    setDailyPlanningEntries(saved);
  };

  const handleUpdateNotes = (
    updater: DaywellNote[] | ((prev: DaywellNote[]) => DaywellNote[])
  ) => {
    setNotes((prev) => {
      const nextRaw = typeof updater === 'function' ? updater(prev) : updater;
      return notesService.saveNotes(nextRaw, { emitSync: false });
    });
  };

  const unprocessedInboxItems = useMemo(
    () => getUnprocessedInboxItems(inboxItems),
    [inboxItems]
  );
  const processedInboxCount = useMemo(
    () => getProcessedInboxItems(inboxItems).length,
    [inboxItems]
  );

  // On initial mount, purge any legacy demonstration records while preserving user records
  useEffect(() => {
    try {
      SharedStateBridge.purgeKnownSeedData();
      setInboxItems(inboxService.loadInboxItems());
      setDailyPlanningEntries(dailyPlanningService.loadDailyPlanningEntries());
      setNotes(notesService.loadNotes());
    } catch (e) {
      console.warn('Seed purge error:', e);
    }
  }, []);

  useEffect(() => {
    try {
      localStorage.setItem('daywell_tasks', JSON.stringify(tasks));
    } catch (e) {
      console.error(e);
    }
    taskRemindersService.syncWebTaskNotifications({ tasks });
    setActiveTaskReminderCount(
      taskRemindersService.loadTaskReminders().filter((r) => r.isActive).length
    );
  }, [tasks]);

  useEffect(() => {
    taskRemindersService.setReminderDueListener((alert) => {
      setDueReminderAlerts((prev) =>
        prev.some(
          (item) =>
            item.reminderId === alert.reminderId &&
            item.triggerTimeUtc === alert.triggerTimeUtc
        )
          ? prev
          : [alert, ...prev]
      );
    });
    return () => {
      taskRemindersService.setReminderDueListener(undefined);
      taskRemindersService.cancelAllWebTaskNotifications();
    };
  }, []);

  useEffect(() => {
    const handleSync = (event: Event) => {
      const detail =
        event instanceof CustomEvent &&
        event.detail &&
        typeof event.detail === 'object'
          ? (event.detail as Record<string, unknown>)
          : null;
      const isDailyPlanningOnly =
        detail !== null &&
        'dailyPlanningEntries' in detail &&
        !('tasks' in detail);
      const isInboxOnly =
        detail !== null &&
        'inboxItems' in detail &&
        !('tasks' in detail);
      const isNotesOnly =
        detail !== null &&
        'notes' in detail &&
        !('tasks' in detail);
      const isDailyRhythmOnly =
        detail !== null &&
        'dailyRhythmDays' in detail &&
        !('tasks' in detail);

      if (
        !isDailyPlanningOnly &&
        !isInboxOnly &&
        !isNotesOnly &&
        !isDailyRhythmOnly
      ) {
        try {
          const saved = localStorage.getItem('daywell_tasks');
          if (saved) {
            const parsed = JSON.parse(saved);
            if (Array.isArray(parsed)) {
              setTasks(parsed);
            }
          }
        } catch (e) {
          // ignore
        }
        setFinanceSyncTick((n) => n + 1);
      }
      if (!isDailyPlanningOnly && !isNotesOnly && !isDailyRhythmOnly) {
        setInboxItems(inboxService.loadInboxItems());
      }
      if (!isInboxOnly && !isNotesOnly && !isDailyRhythmOnly) {
        setDailyPlanningEntries(dailyPlanningService.loadDailyPlanningEntries());
      }
      if (!isDailyPlanningOnly && !isInboxOnly && !isDailyRhythmOnly) {
        setNotes(notesService.loadNotes());
      }
      if (!isDailyPlanningOnly && !isInboxOnly && !isNotesOnly) {
        setDailyRhythmDays(dailyRhythmService.loadDays());
      }
      setActiveTaskReminderCount(
        taskRemindersService.loadTaskReminders().filter((r) => r.isActive).length
      );
      taskRemindersService.syncWebTaskNotifications();
    };
    window.addEventListener(SharedStateBridge.SYNC_EVENT_NAME, handleSync);
    return () => window.removeEventListener(SharedStateBridge.SYNC_EVENT_NAME, handleSync);
  }, []);

  const todayFinanceSummary = useMemo(() => {
    const readArr = <T,>(key: string): T[] => {
      try {
        const raw = localStorage.getItem(key);
        if (!raw) return [];
        const parsed = JSON.parse(raw);
        return Array.isArray(parsed) ? parsed : [];
      } catch {
        return [];
      }
    };
    const rawAccounts = readArr<Account>('daywell_accounts');
    const rawTxs =
      readArr<SimpleTransaction>('daywell_finance_transactions').length > 0
        ? readArr<SimpleTransaction>('daywell_finance_transactions')
        : readArr<SimpleTransaction>('daywell_transactions');
    const rawEntries = readArr<JournalEntry>('daywell_journal_entries');
    const rawPostings = readArr<Posting>('daywell_postings');
    const debts = readArr<Debt>('daywell_debts');
    const allocations = readArr<SettlementAllocation>('daywell_settlement_allocations');
    const hydrated = hydrateLedgerFromSimpleTransactions({
      accounts: rawAccounts,
      transactions: rawTxs,
      entries: rawEntries,
      postings: rawPostings,
    });
    const horizon = localStorage.getItem('daywell_finance_planning_horizon') || undefined;
    const breakdown = calculateAvailableToSpendBreakdownV7({
      accounts: hydrated.accounts,
      postings: hydrated.postings,
      entries: hydrated.entries,
      debts,
      allocations,
      commitments: readArr<SharedCommitment>('daywell_commitments'),
      commitmentSettlements: readArr<SharedCommitmentSettlement>('daywell_commitment_settlements'),
      recurringRules: readArr<SharedRecurringRule>('daywell_recurring_rules'),
      savingsGoals: readArr<SharedSavingsGoal>('daywell_savings_goals'),
      planningPeriodEndIso: horizon,
    });
    const classificationsByEntryId = classifyAllJournalEntries({
      accounts: hydrated.accounts,
      entries: hydrated.entries,
      postings: hydrated.postings,
      debts,
      allocations,
    });
    const accountById = new Map(hydrated.accounts.map((a) => [a.id, a]));
    const postingsByEntry = new Map<string, Posting[]>();
    for (const p of hydrated.postings) {
      const list = postingsByEntry.get(p.entryId) || [];
      list.push(p);
      postingsByEntry.set(p.entryId, list);
    }
    const recentEntries = [...hydrated.entries]
      .sort((a, b) =>
        a.occurrenceDate !== b.occurrenceDate
          ? b.occurrenceDate.localeCompare(a.occurrenceDate)
          : (b.createdAt || '').localeCompare(a.createdAt || '')
      )
      .slice(0, 3)
      .map((entry) => {
        const cls = classificationsByEntryId.get(entry.id);
        const list = postingsByEntry.get(entry.id) || [];
        const maxAmount = list.reduce((m, p) => Math.max(m, p.amountCents), 0);
        const displayCurrency =
          cls?.nativeCurrencyCode
            ? cls.nativeCurrencyCode
            : cls && cls.touchedCurrencies.length === 1
            ? cls.touchedCurrencies[0]
            : cls && cls.touchedCurrencies.length > 1
            ? 'MIXED'
            : cls?.status === 'eligible_etb'
            ? 'ETB'
            : '';
        const nonSystemLegs = list.filter((p) => !accountById.get(p.accountId)?.isSystem);
        const formattedAmount =
          displayCurrency === 'MIXED'
            ? nonSystemLegs.length > 0
              ? nonSystemLegs
                  .map((p) =>
                    formatCurrencyCents(
                      p.amountCents,
                      accountById.get(p.accountId)?.currencyCode || ''
                    )
                  )
                  .join(' / ')
              : `${(maxAmount / 100).toFixed(2)} (${cls!.touchedCurrencies.join('/')})`
            : formatCurrencyCents(
                maxAmount,
                displayCurrency === 'UNVERIFIED'
                  ? ''
                  : displayCurrency ||
                      accountById.get(list.find((p) => !accountById.get(p.accountId)?.isSystem)?.accountId || '')
                        ?.currencyCode ||
                      ''
              );
        return { entry, cls, formattedAmount };
      });
    return { breakdown, recentEntries, entries: hydrated.entries };
  }, [financeSyncTick, activeScreen]);
  const todaySafeHarbor = todayFinanceSummary.breakdown;

  // System Dark Mode Effect
  useEffect(() => {
    const updateTheme = () => {
      let isDark = false;
      if (themeMode === 'system') {
        isDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
      } else {
        isDark = themeMode === 'dark';
      }
      setEffectiveDark(isDark);
      if (isDark) {
        document.documentElement.classList.add('dark');
      } else {
        document.documentElement.classList.remove('dark');
      }
    };

    updateTheme();
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    media.addEventListener('change', updateTheme);
    return () => media.removeEventListener('change', updateTheme);
  }, [themeMode]);

  // Dual Date under Daywell Ethiopia UTC+3 convention
  const todayCal = useMemo(() => CalendarDate.today(), []);
  const dualDate = useMemo(() => SharedDateFormatter.formatDual(todayCal), [todayCal]);

  const taskOverview = useMemo(
    () =>
      buildTaskOverviewSummary({
        tasks,
        dailyPlanningEntries,
        todayIso: todayCal.toIsoString(),
      }),
    [tasks, dailyPlanningEntries, todayCal]
  );

  const dailyRhythmOverview = useMemo(() => {
    const timelineSummary = evaluateDailyRhythmTimeline(dailyRhythmDays, {
      today: todayCal,
    });
    const taskSnapshot = buildDailyRhythmTaskReviewSnapshot({
      tasks,
      dailyPlanningEntries,
      targetDateIso: todayCal.toIsoString(),
      today: todayCal,
    });
    const financeSummary = inspectDailyRhythmFinanceDay({
      entries: todayFinanceSummary.entries,
      targetDateIso: todayCal.toIsoString(),
      today: todayCal,
    });
    return buildDailyRhythmDashboardOverview({
      timelineSummary,
      taskSnapshot,
      financeSummary,
    });
  }, [dailyRhythmDays, tasks, dailyPlanningEntries, todayFinanceSummary.entries, todayCal]);

  const handleCompleteDailyFaithStep = (step: DailyRhythmFaithStep) => {
    const todayIso = todayCal.toIsoString();
    const res = dailyRhythmWorkflowService.updateFaith({
      dateIso: todayIso,
      bibleStudyDone: step === 'bibleStudy' ? true : undefined,
      prayerDone: step === 'prayer' ? true : undefined,
      todayIso,
    });
    setDailyRhythmDays(dailyRhythmService.loadDays());
    if (!res.applied && res.reason !== 'unchanged') {
      setFaithFeedback(null);
      setFaithError("Only today's Faith check-in can be updated.");
      return;
    }
    setFaithError(null);
    const msg =
      res.record.bibleStudyDone && res.record.prayerDone
        ? 'Faith check-in complete for today (2/2).'
        : step === 'bibleStudy'
        ? 'Bible study saved.'
        : 'Prayer saved.';
    setFaithFeedback(msg);
    setTimeout(() => setFaithFeedback((cur) => (cur === msg ? null : cur)), 3000);
  };

  const projectsOverview = useMemo(() => {
    const activeProjects = projectsService.listProjects({ includeArchived: false });
    const trackingSummaries = projectsService.getAllProjectSummaries({
      asOfDate: todayCal,
      includeArchived: false,
    });
    const milestones = projectsService.listAllMilestones();
    return buildProjectsOverviewSummary({
      projects: activeProjects,
      tasks,
      milestones,
      trackingSummaries,
      todayIso: todayCal.toIsoString(),
    });
  }, [tasks, financeSyncTick, activeScreen, todayCal]);

  const activeProjectsCount = projectsOverview.totalProjectsCount;

  const prioritizedDashboardTasks = useMemo(() => {
    const todayIso = todayCal.toIsoString();
    const priorityRank: Record<string, number> = {
      urgent: 0,
      high: 1,
      medium: 2,
      low: 3,
    };
    const pending = tasks.filter(
      (t) => !t.isArchived && !isTaskCompleted(t) && t.status !== 'cancelled'
    );
    return pending.slice().sort((a, b) => {
      const aUrgentOrDue = Boolean(a.dueDate && a.dueDate <= todayIso);
      const bUrgentOrDue = Boolean(b.dueDate && b.dueDate <= todayIso);
      if (aUrgentOrDue !== bUrgentOrDue) return aUrgentOrDue ? -1 : 1;
      const rankA = priorityRank[a.priority] ?? 2;
      const rankB = priorityRank[b.priority] ?? 2;
      if (rankA !== rankB) return rankA - rankB;
      const dueA = a.dueDate ?? '2099-12-31';
      const dueB = b.dueDate ?? '2099-12-31';
      if (dueA !== dueB) return dueA.localeCompare(dueB);
      return a.title.localeCompare(b.title);
    });
  }, [tasks, todayCal]);

  // Navigate Screen Helper
  const navigateTo = (rawScreen: ScreenId) => {
    let screen = rawScreen;
    if (rawScreen === 'projects' || rawScreen === 'project_detail') {
      setTasksSubTab('projects');
      setSelectedProjectId(null);
      screen = 'tasks';
    }
    if (activeScreen === screen) return; // Prevent duplicate navigation stack entries!
    setActiveScreen(screen);
    setScreenHistory((prev) => {
      if (prev.length > 0 && prev[prev.length - 1] === screen) return prev;
      return [...prev, screen];
    });

    // Keep primary tab bar sync
    if (screen === 'today') setCurrentTab('today');
    else if (screen === 'tasks') setCurrentTab('tasks');
    else if (screen === 'calendar') setCurrentTab('calendar');
    else if (screen === 'notes') setCurrentTab('notes');
    else if (screen === 'finance') setCurrentTab('finance');
    else setCurrentTab('more');

    try {
      window.history.pushState({ screen }, '', `#${screen}`);
    } catch {
      // ignore
    }
  };

  const openTasksFromDashboard = (
    filter: TaskViewFilter,
    dueDateFilter: TaskDueDateFilter | '' = '',
    planDate?: string
  ) => {
    setTasksSubTab('tasks');
    setSelectedProjectId(null);
    setRequestedTasksFilter({
      filter,
      dueDateFilter,
      planDate,
      nonce: Date.now(),
    });
    navigateTo('tasks');
  };

  const openProjectsFromDashboard = (projectId: string | null = null) => {
    setTasksSubTab('projects');
    setSelectedProjectId(projectId);
    navigateTo('tasks');
  };

  const handleAttemptCloseQuickCapture = () => {
    if (quickCaptureInput.trim()) {
      setShowUnsavedQuickCapture(true);
    } else {
      setIsQuickCaptureOpen(false);
      setQuickCaptureError(null);
    }
  };

  const handleBack = () => {
    // 1. If Quick Capture modal is open, close it first without popping the underlying screen
    if (isQuickCaptureOpen) {
      handleAttemptCloseQuickCapture();
      return;
    }

    if (screenHistory.length > 1) {
      const newHist = [...screenHistory];
      newHist.pop();
      const prevScreen = newHist[newHist.length - 1];
      setScreenHistory(newHist);
      setActiveScreen(prevScreen);

      if (prevScreen === 'today') setCurrentTab('today');
      else if (prevScreen === 'tasks') setCurrentTab('tasks');
      else if (prevScreen === 'calendar') setCurrentTab('calendar');
      else if (prevScreen === 'notes') setCurrentTab('notes');
      else if (prevScreen === 'finance') setCurrentTab('finance');
      else setCurrentTab('more');
    } else {
      setActiveScreen('today');
      setCurrentTab('today');
      setScreenHistory(['today']);
    }
  };

  // Hardware and browser popstate listener for Android back gesture & browser back button
  useEffect(() => {
    try {
      window.history.replaceState({ screen: 'today' }, '', '#today');
    } catch {
      // ignore
    }

    const onPopState = (e: PopStateEvent) => {
      // Intercept if Quick Capture modal is open
      if (isQuickCaptureOpen) {
        handleAttemptCloseQuickCapture();
        try {
          window.history.pushState({ screen: activeScreen }, '', `#${activeScreen}`);
        } catch {
          // ignore
        }
        return;
      }

      if (e.state && e.state.screen) {
        let target = e.state.screen as ScreenId;
        if (target === 'projects' || target === 'project_detail') {
          setTasksSubTab('projects');
          setSelectedProjectId(null);
          target = 'tasks';
        }
        setActiveScreen(target);
        if (target === 'today') setCurrentTab('today');
        else if (target === 'tasks') setCurrentTab('tasks');
        else if (target === 'calendar') setCurrentTab('calendar');
        else if (target === 'notes') setCurrentTab('notes');
        else if (target === 'finance') setCurrentTab('finance');
        else setCurrentTab('more');

        setScreenHistory((prev) => {
          if (prev.length > 1) {
            const copy = [...prev];
            copy.pop();
            return copy;
          }
          return ['today'];
        });
      } else {
        handleBack();
      }
    };

    window.addEventListener('popstate', onPopState);
    return () => window.removeEventListener('popstate', onPopState);
  }, [isQuickCaptureOpen, activeScreen, quickCaptureInput]);

  // Toggle Task Completion (Recurrence-aware + reconciles reminders & DailyPlanningEntries)
  const toggleTask = (id: string) => {
    const prevTasks = tasks;
    const targetBefore = tasks.find((t) => t.id === id);
    const wasCompleted = targetBefore ? isTaskCompleted(targetBefore) : false;
    const nowUtc = EthiopiaClock.nowUtc();
    const result = completeTaskWithRecurrence(tasks, id, { nowUtc });
    if (!result.updatedTask) return;

    const nextCompleted = isTaskCompleted(result.updatedTask);
    const nextEntries = syncTaskCompletionWithDailyPlanning(
      result.tasks,
      dailyPlanningEntries,
      id,
      nextCompleted,
      { nowUtc }
    );
    if (result.generatedNextTask?.projectId) {
      projectsService.copyTaskSectionLink(
        result.generatedNextTask.projectId,
        id,
        result.generatedNextTask
      );
    }
    const reconciled = taskRemindersService.reconcileAndPersistForTasks({
      tasks: result.tasks,
      previousTasks: prevTasks,
      generatedFromTaskId: !wasCompleted ? id : undefined,
      generatedNextTask: result.generatedNextTask,
      persistTasks: true,
      emitSync: false,
      nowUtc,
    });
    try {
      localStorage.setItem('daywell_tasks', JSON.stringify(reconciled.tasks));
    } catch {
      // ignore storage quota errors; React state will still update
    }
    if (nextCompleted) {
      setDueReminderAlerts((prev) => prev.filter((a) => a.taskId !== id));
    }
    setTasks(reconciled.tasks);
    handleUpdateDailyPlanningEntries(nextEntries);
  };

  // Save Quick Capture (Tasks, Notes, Expenses, Calendar Reminders)
  const handleSaveQuickCapture = (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    const text = quickCaptureInput.trim();
    if (!text) {
      setQuickCaptureError('Please enter something to capture.');
      return;
    }

    if (isSubmittingQuickCapture) return;
    setIsSubmittingQuickCapture(true);
    setQuickCaptureError(null);

    if (quickCaptureType === 'expense') {
      const canonical = SharedStateBridge.loadCanonicalState();
      const built = buildQuickCaptureExpenseEntryV7({
        rawText: text,
        accountHint: quickCaptureExpenseAccount,
        accounts: (canonical.accounts || []) as Account[],
        categories: (canonical.categories || []) as TransactionCategory[],
      });

      if (!built.ok || !built.entry || !built.postings || !built.simpleTransaction || !built.targetAccount) {
        setIsSubmittingQuickCapture(false);
        setQuickCaptureError(
          built.error || 'Could not validate expense capture against active ETB accounts.'
        );
        return;
      }

      try {
        const prevEntries = (canonical.journalEntries || []) as JournalEntry[];
        const prevPostings = (canonical.postings || []) as Posting[];
        const nextEntries = [built.entry, ...prevEntries];
        const nextPostings = [...built.postings, ...prevPostings];
        SharedStateBridge.saveCanonicalState({
          ...canonical,
          isFinanceSetupCompleted: true,
          accounts: (built.accountsWithControls || canonical.accounts) as any,
          journalEntries: nextEntries,
          postings: nextPostings,
          transactions: [built.simpleTransaction as any, ...(canonical.transactions || [])],
        });
        dailyRhythmWorkflowService.notifyFinanceLedgerMutation({
          prevEntries,
          prevPostings,
          nextEntries,
          nextPostings,
        });
      } catch (err) {
        console.error(err);
      }

      setIsSubmittingQuickCapture(false);
      setIsQuickCaptureOpen(false);
      setQuickCaptureInput('');
      setQuickCaptureToast(
        `Recorded ${formatBirr(built.simpleTransaction.amountCents)}: "${built.simpleTransaction.description}" to ${built.targetAccount.name}`
      );
      setTimeout(() => setQuickCaptureToast(null), 3500);
      return;
    }

    if (quickCaptureType === 'note') {
      const firstNonEmptyLine =
        text
          .split(/\r?\n/)
          .map((line) => line.trim())
          .find((line) => line.length > 0) ?? 'Quick Note';
      const previewTitle = normalizeNoteTitle(firstNonEmptyLine, {
        fallbackTitle: 'Quick Note',
      });
      handleUpdateNotes((prev) => {
        const res = createQuickCaptureNoteRecord({
          existingNotes: prev,
          rawText: text,
        });
        return res.ok ? res.notes : prev;
      });
      setIsSubmittingQuickCapture(false);
      setIsQuickCaptureOpen(false);
      setQuickCaptureInput('');
      setQuickCaptureToast(
        `Saved note "${previewTitle.slice(0, 24)}${previewTitle.length > 24 ? '...' : ''}" to Notes`
      );
      setTimeout(() => setQuickCaptureToast(null), 3000);
      return;
    }

    if (quickCaptureType === 'reminder') {
      try {
        const savedEvents = localStorage.getItem('daywell_calendar_events');
        const eventsList = savedEvents ? JSON.parse(savedEvents) : [];
        const newEvent = {
          id: `evt-${Date.now()}`,
          title: text,
          date: CalendarDate.today().toIsoString(),
          isAllDay: true,
          category: 'personal',
          colorHex: SHARED_DESIGN_TOKENS.colors.semantic.info,
          hasReminder: true,
        };
        localStorage.setItem('daywell_calendar_events', JSON.stringify([newEvent, ...eventsList]));
      } catch (err) {
        console.error(err);
      }
      setIsSubmittingQuickCapture(false);
      setIsQuickCaptureOpen(false);
      setQuickCaptureInput('');
      setQuickCaptureToast(`Scheduled reminder "${text.slice(0, 24)}..." on Calendar`);
      setTimeout(() => setQuickCaptureToast(null), 3000);
      return;
    }

    // Default ('task' | 'idea'): Stage in Shared Inbox without auto-creating duplicate Task records
    const captureCategory = quickCaptureType === 'idea' ? 'idea' : 'task';
    const captured = inboxService.captureQuickThought({
      rawText: text,
      category: captureCategory,
    });
    if (!captured.ok) {
      setIsSubmittingQuickCapture(false);
      setQuickCaptureError(captured.error);
      return;
    }
    if (captured.items) {
      setInboxItems(captured.items);
    }
    setIsSubmittingQuickCapture(false);
    setIsQuickCaptureOpen(false);
    setQuickCaptureInput('');
    setQuickCaptureToast(
      `Saved "${text.slice(0, 28)}..." to Inbox — organize in Tasks`
    );
    setTimeout(() => setQuickCaptureToast(null), 3000);
  };

  if (isSetupWizardOpen) {
    return (
      <FirstTimeSetupWizard
        onComplete={handleSetupComplete}
        initialName={userProfile.name === 'Friend' ? '' : userProfile.name}
      />
    );
  }

  return (
    <div className="min-h-screen bg-[var(--dw-surface-subtle)] text-[var(--dw-text-primary)] transition-colors duration-200 flex flex-col font-sans">
      {/* Top Workspace Command Bar */}
      <header className="bg-[var(--dw-card)]/90 backdrop-blur-md border-b border-[var(--dw-border)] px-4 py-3 shrink-0 sticky top-0 z-50">
        <div className="max-w-7xl mx-auto flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-[var(--dw-radius-sm)] bg-[var(--dw-primary-brand)] flex items-center justify-center text-white font-bold text-sm shadow-sm">
              D
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="font-bold text-base tracking-tight text-[var(--dw-text-primary)]">Daywell</span>
                <DaywellStatusBadge
                  tone="success"
                  showIcon={false}
                  label="Canonical Design System"
                />
              </div>
              <p className="text-xs text-[var(--dw-text-muted)]">
                Web Preview · Ethiopian/Gregorian Dual Engine · 100% Offline Local Storage
              </p>
            </div>
          </div>

          {/* Quick Screen Jump Selector & Controls */}
          <div className="flex items-center flex-wrap gap-2">
            <div className="flex items-center gap-1.5 bg-[var(--dw-surface-subtle)] p-1 rounded-[var(--dw-radius-md)] border border-[var(--dw-border)]">
              <span className="text-xs text-[var(--dw-text-muted)] pl-2">Screen:</span>
              <select
                value={
                  activeScreen === 'tasks' && tasksSubTab === 'projects'
                    ? 'projects'
                    : activeScreen
                }
                onChange={(e) => {
                  const next = e.target.value as ScreenId;
                  if (next === 'tasks') {
                    setTasksSubTab('tasks');
                    setSelectedProjectId(null);
                  }
                  navigateTo(next);
                }}
                aria-label="Screen"
                className="bg-transparent text-xs font-semibold py-1 px-2 rounded-[var(--dw-radius-sm)] text-[var(--dw-text-primary)] outline-none cursor-pointer"
              >
                <option value="today">01 · Today Dashboard</option>
                <option value="tasks">02 · Tasks (To-Do)</option>
                <option value="calendar">03 · Calendar (Dual Engine)</option>
                <option value="finance">04 · Finance (Balanced Ledger)</option>
                <option value="notes">05 · Notes & Knowledge</option>
                <option value="projects">06 · Projects (in Tasks)</option>
                <option value="goals">08 · Goals (Deprecated Prototype)</option>
                <option value="relationships">09 · Relationships (Deprecated Prototype)</option>
                <option value="priorities">10 · Priorities (Deprecated Prototype)</option>
                <option value="tools">11 · Calculations & Tools (Deprecated Prototype)</option>
                <option value="history">12 · History & Progress (Deprecated Prototype)</option>
                <option value="more">13 · More / All Areas</option>
                <option value="sync_backup">14 · Sync & Local Export</option>
              </select>
            </div>

            {/* Theme Toggle */}
            <div className="flex items-center bg-[var(--dw-surface-subtle)] p-1 rounded-[var(--dw-radius-md)] border border-[var(--dw-border)]">
              <button
                type="button"
                onClick={() => setThemeMode('light')}
                className={`text-xs px-2.5 py-1 rounded-[var(--dw-radius-sm)] font-medium transition-all cursor-pointer ${
                  themeMode === 'light'
                    ? 'bg-[var(--dw-card)] text-[var(--dw-text-primary)] shadow-sm'
                    : 'text-[var(--dw-text-muted)] hover:text-[var(--dw-text-primary)]'
                }`}
              >
                Light
              </button>
              <button
                type="button"
                onClick={() => setThemeMode('dark')}
                className={`text-xs px-2.5 py-1 rounded-[var(--dw-radius-sm)] font-medium transition-all cursor-pointer ${
                  themeMode === 'dark'
                    ? 'bg-[var(--dw-card)] text-[var(--dw-text-primary)] shadow-sm'
                    : 'text-[var(--dw-text-muted)] hover:text-[var(--dw-text-primary)]'
                }`}
              >
                Dark
              </button>
              <button
                type="button"
                onClick={() => setThemeMode('system')}
                className={`text-xs px-2.5 py-1 rounded-[var(--dw-radius-sm)] font-medium transition-all cursor-pointer ${
                  themeMode === 'system'
                    ? 'bg-[var(--dw-card)] text-[var(--dw-text-primary)] shadow-sm'
                    : 'text-[var(--dw-text-muted)] hover:text-[var(--dw-text-primary)]'
                }`}
              >
                Auto
              </button>
            </div>

            {/* View Mode Toggle */}
            <div className="flex items-center bg-[var(--dw-surface-subtle)] p-1 rounded-[var(--dw-radius-md)] border border-[var(--dw-border)]">
              <button
                type="button"
                onClick={() => setViewMode('desktop')}
                className={`text-xs px-2.5 py-1 rounded-[var(--dw-radius-sm)] font-medium transition-all flex items-center gap-1 cursor-pointer ${
                  viewMode === 'desktop'
                    ? 'bg-[var(--dw-card)] text-[var(--dw-text-primary)] shadow-sm'
                    : 'text-[var(--dw-text-muted)] hover:text-[var(--dw-text-primary)]'
                }`}
              >
                <Monitor className="w-3.5 h-3.5" />
                Desktop
              </button>
              <button
                type="button"
                onClick={() => setViewMode('mobile_frame')}
                className={`text-xs px-2.5 py-1 rounded-[var(--dw-radius-sm)] font-medium transition-all flex items-center gap-1 cursor-pointer ${
                  viewMode === 'mobile_frame'
                    ? 'bg-[var(--dw-card)] text-[var(--dw-text-primary)] shadow-sm'
                    : 'text-[var(--dw-text-muted)] hover:text-[var(--dw-text-primary)]'
                }`}
              >
                <Smartphone className="w-3.5 h-3.5" />
                Phone
              </button>
              <button
                type="button"
                onClick={() => setViewMode('side_by_side')}
                className={`text-xs px-2.5 py-1 rounded-[var(--dw-radius-sm)] font-medium transition-all flex items-center gap-1 cursor-pointer ${
                  viewMode === 'side_by_side'
                    ? 'bg-[var(--dw-card)] text-[var(--dw-text-primary)] shadow-sm'
                    : 'text-[var(--dw-text-muted)] hover:text-[var(--dw-text-primary)]'
                }`}
              >
                <Eye className="w-3.5 h-3.5" />
                Design Match
              </button>
            </div>

            {/* APK & ZIP Downloads */}
            <a
              href="/personal_management_app_flutter.zip"
              download="personal_management_app_flutter.zip"
              className="text-xs bg-[var(--dw-primary-brand)] hover:opacity-90 text-white font-medium px-3 py-1.5 rounded-[var(--dw-radius-md)] transition-all shadow-sm flex items-center gap-1.5 shrink-0"
            >
              <Download className="w-3.5 h-3.5" />
              Flutter .ZIP
            </a>
          </div>
        </div>
      </header>

      {/* Main Preview Container */}
      <main
        className={`flex-1 flex overflow-auto ${
          viewMode === 'desktop'
            ? 'p-3 md:p-6 items-stretch justify-center'
            : 'p-4 md:p-8 items-center justify-center'
        }`}
      >
        <div
          className={`w-full ${
            viewMode === 'desktop'
              ? 'max-w-[1120px] mx-auto flex flex-col'
              : viewMode === 'side_by_side'
              ? 'max-w-6xl grid grid-cols-1 lg:grid-cols-2 gap-8 items-start'
              : 'max-w-md mx-auto'
          }`}
        >
          {/* Side-by-Side Reference PNG (if side-by-side mode is active) */}
          {viewMode === 'side_by_side' && (
            <div className="bg-[var(--dw-card)] rounded-[38px] p-4 shadow-xl border border-[var(--dw-border)] flex flex-col items-center">
              <div className="w-full flex items-center justify-between pb-3 px-2 border-b border-[var(--dw-divider)] mb-3">
                <span className="dw-type-label uppercase tracking-wider text-[var(--dw-text-muted)]">
                  Visual Screen Reference
                </span>
                <span className="text-xs font-semibold text-[var(--dw-primary)]">
                  {effectiveDark ? 'Dark Theme' : 'Light Theme'}
                </span>
              </div>
              <div className="w-full max-w-[375px] rounded-[32px] overflow-hidden shadow-inner border border-[var(--dw-border)] bg-[var(--dw-canvas)]">
                <img
                  src={
                    activeScreen === 'today'
                      ? effectiveDark
                        ? '/screens/today_dashboard___dark.png'
                        : '/screens/today_dashboard___light.png'
                      : activeScreen === 'tasks' && tasksSubTab === 'projects'
                      ? effectiveDark
                        ? '/screens/projects___dark.png'
                        : '/screens/projects___light.png'
                      : activeScreen === 'tasks'
                      ? effectiveDark
                        ? '/screens/tasks___dark.png'
                        : '/screens/tasks___light.png'
                      : activeScreen === 'goals'
                      ? effectiveDark
                        ? '/screens/goals___dark.png'
                        : '/screens/goals___light.png'
                      : activeScreen === 'notes'
                      ? effectiveDark
                        ? '/screens/notes___knowledge___dark.png'
                        : '/screens/notes___knowledge___light.png'
                      : activeScreen === 'finance'
                      ? effectiveDark
                        ? '/screens/finance___dark.png'
                        : '/screens/finance___light.png'
                      : activeScreen === 'relationships'
                      ? effectiveDark
                        ? '/screens/relationships___dark.png'
                        : '/screens/relationships___light.png'
                      : activeScreen === 'priorities'
                      ? effectiveDark
                        ? '/screens/priorities___dark.png'
                        : '/screens/priorities___light.png'
                      : activeScreen === 'tools'
                      ? effectiveDark
                        ? '/screens/calculations___tools___dark.png'
                        : '/screens/calculations___tools___light.png'
                      : activeScreen === 'history'
                      ? effectiveDark
                        ? '/screens/history___progress___dark.png'
                        : '/screens/history___progress___light.png'
                      : activeScreen === 'sync_backup'
                      ? effectiveDark
                        ? '/screens/sync___backup_settings___dark.png'
                        : '/screens/sync___backup_settings___light.png'
                      : effectiveDark
                      ? '/screens/_all_areas___dark.png'
                      : '/screens/_all_areas___light.png'
                  }
                  alt="Daywell Screen Reference"
                  className="w-full h-auto object-cover"
                />
              </div>
            </div>
          )}

          {/* Interactive App Frame (Responsive Desktop Workspace vs Mobile Device Frame) */}
          <div
            className={
              viewMode === 'desktop'
                ? 'relative mx-auto w-full flex-1 min-h-[calc(100vh-8.5rem)] bg-[var(--dw-canvas)] rounded-[var(--dw-radius-xl)] shadow-xl border border-[var(--dw-border)] flex flex-col overflow-hidden text-[var(--dw-text-primary)] transition-colors duration-200'
                : 'relative mx-auto w-full max-w-[390px] h-[820px] bg-[var(--dw-canvas)] rounded-[48px] shadow-2xl border-[10px] border-[var(--dw-border)] flex flex-col overflow-hidden text-[var(--dw-text-primary)] transition-colors duration-200'
            }
          >
            {viewMode !== 'desktop' && (
              <>
                {/* Top Phone Speaker & Camera Notch */}
                <div className="absolute top-2 left-1/2 -translate-x-1/2 w-28 h-4 bg-[var(--dw-border)] rounded-[var(--dw-radius-full)] z-40 pointer-events-none" />

                {/* Mobile System Status Bar (9:05, Wi-Fi, Cellular, Battery) */}
                <div className="pt-3 px-7 pb-1 flex items-center justify-between text-xs font-semibold text-[var(--dw-text-secondary)] select-none z-30 shrink-0">
                  <span>9:05</span>
                  <div className="flex items-center gap-1.5 text-[var(--dw-text-secondary)]">
                    <span className="text-[10px]">5G</span>
                    <div className="w-4 h-2.5 border border-current rounded-sm relative p-0.5">
                      <div className="h-full bg-current rounded-xs w-3/4" />
                    </div>
                  </div>
                </div>
              </>
            )}

            {/* Active Screen Scrollable Body Area */}
            <div
              className={`flex-1 overflow-y-auto pb-24 ${
                viewMode === 'desktop' ? 'px-5 md:px-8 pt-5' : 'px-5 pt-2'
              }`}
            >
              {/* SCREEN 01: TODAY DASHBOARD */}
              {activeScreen === 'today' && (
                <div className="space-y-4">
                  {/* Header */}
                  <div className="flex items-start justify-between pt-1">
                    <div>
                      <div className="dw-type-caption font-bold tracking-wider text-[var(--dw-text-muted)] uppercase">
                        {`${todayCal.englishWeekdayName}, ${todayCal.gregorianShortMonthName} ${todayCal.day}, ${todayCal.year}`}
                      </div>
                      <div className="text-xs font-semibold text-[var(--dw-primary)]">
                        {dualDate.split('(')[0].trim()} ዓ.ም.
                      </div>
                      <h1 className="dw-type-display text-[var(--dw-text-primary)] mt-0.5">
                        Today
                      </h1>
                    </div>
                    <div className="flex items-center gap-1.5">
                      <DaywellIconButton
                        label="Filter options"
                        tone="muted"
                        onClick={() => navigateTo('more')}
                        icon={<SlidersHorizontal className="w-5 h-5" />}
                      />
                      <DaywellIconButton
                        label="Quick capture"
                        tone="primary"
                        onClick={() => setIsQuickCaptureOpen(true)}
                        icon={<Plus className="w-5 h-5 stroke-[2.5]" />}
                      />
                    </div>
                  </div>

                  {/* Hero Greeting */}
                  <div className="pt-1">
                    <h2 className="dw-type-heading text-[var(--dw-text-primary)]">
                      Good morning, {userProfile.name || 'Friend'}
                    </h2>
                    <p className="dw-type-body-compact text-[var(--dw-text-muted)] mt-0.5">
                      A little focus. A little more room.
                    </p>
                  </div>

                  {/* Core 4-Module Quick Launcher */}
                  <div className="grid grid-cols-4 gap-2 pt-1">
                    <button
                      type="button"
                      onClick={() => navigateTo('tasks')}
                      className="p-2.5 bg-[var(--dw-card)] rounded-[var(--dw-radius-lg)] border border-[var(--dw-border)] text-center hover:border-[var(--dw-primary)] transition-all shadow-2xs cursor-pointer"
                    >
                      <CheckCircle2 className="w-4 h-4 text-[var(--dw-income)] mx-auto" />
                      <span className="block text-[11px] font-bold text-[var(--dw-text-primary)] mt-1">To-Do</span>
                      <span className="block text-[9px] text-[var(--dw-text-muted)] dw-type-numeric-body">
                        {taskOverview.remainingCount} remaining
                      </span>
                    </button>

                    <button
                      type="button"
                      onClick={() => navigateTo('calendar')}
                      className="p-2.5 bg-[var(--dw-card)] rounded-[var(--dw-radius-lg)] border border-[var(--dw-border)] text-center hover:border-[var(--dw-primary)] transition-all shadow-2xs cursor-pointer"
                    >
                      <CalendarDays className="w-4 h-4 text-[var(--dw-info)] mx-auto" />
                      <span className="block text-[11px] font-bold text-[var(--dw-text-primary)] mt-1">Calendar</span>
                      <span className="block text-[9px] text-[var(--dw-text-muted)]">Dual view</span>
                    </button>

                    <button
                      type="button"
                      onClick={() => navigateTo('finance')}
                      className="p-2.5 bg-[var(--dw-card)] rounded-[var(--dw-radius-lg)] border border-[var(--dw-border)] text-center hover:border-[var(--dw-primary)] transition-all shadow-2xs cursor-pointer"
                    >
                      <Wallet className="w-4 h-4 text-[var(--dw-warning)] mx-auto" />
                      <span className="block text-[11px] font-bold text-[var(--dw-text-primary)] mt-1">Finance</span>
                      <span className="block text-[9px] text-[var(--dw-text-muted)]">Ledger</span>
                    </button>

                    <button
                      type="button"
                      onClick={() => navigateTo('notes')}
                      className="p-2.5 bg-[var(--dw-card)] rounded-[var(--dw-radius-lg)] border border-[var(--dw-border)] text-center hover:border-[var(--dw-primary)] transition-all shadow-2xs cursor-pointer"
                    >
                      <NotebookPen className="w-4 h-4 text-[var(--dw-primary)] mx-auto" />
                      <span className="block text-[11px] font-bold text-[var(--dw-text-primary)] mt-1">Notes</span>
                      <span className="block text-[9px] text-[var(--dw-text-muted)]">Autosave</span>
                    </button>
                  </div>

                  {/* Central Daily Rhythm Overview */}
                  <DailyRhythmDashboardCard
                    overview={dailyRhythmOverview}
                    errorMessage={faithError}
                    onCompleteFaithStep={handleCompleteDailyFaithStep}
                    onOpenFaith={() => navigateTo('more')}
                    onOpenTasksReview={() => openTasksFromDashboard('active', 'today')}
                    onOpenFinanceReview={() => {
                      setRequestedFinanceTab({ tab: 'transactions', nonce: Date.now() });
                      navigateTo('finance');
                    }}
                    onOpenCalendarHistory={() => {
                      setRequestedCalendarFocus({
                        dateStr: todayCal.toIsoString(),
                        nonce: Date.now(),
                      });
                      navigateTo('calendar');
                    }}
                  />

                  <div
                    className={
                      viewMode === 'desktop'
                        ? 'grid grid-cols-1 lg:grid-cols-12 gap-4 items-start'
                        : 'space-y-4'
                    }
                  >
                    {/* Primary Operational Column: Tasks Overview, Project Progress, Inbox */}
                    <div
                      className={
                        viewMode === 'desktop'
                          ? 'lg:col-span-7 space-y-4 lg:order-2 order-1'
                          : 'space-y-4'
                      }
                    >
                      {/* Live Task Overview, Today's Plan & Priorities */}
                      <div className="space-y-2.5 pt-1">
                        <DaywellSectionHeader
                          title="Tasks Overview"
                          count={taskOverview.remainingCount > 0 ? taskOverview.remainingCount : undefined}
                          actionLabel="Open Tasks"
                          onActionPressed={() => openTasksFromDashboard('active')}
                        />

                        <DaywellCard padding="md" radius="lg" className="space-y-3">
                          <div className="flex items-center justify-between gap-2 text-xs">
                            <span className="font-semibold text-[var(--dw-text-secondary)]">
                              Task completion
                            </span>
                            <span className="font-bold text-[var(--dw-text-primary)] dw-type-numeric-body">
                              {taskOverview.completedCount} / {taskOverview.totalActiveAndCompleted} done
                            </span>
                          </div>
                          <DaywellProgressBar
                            value={taskOverview.completionPercentage}
                            label="Overall task completion"
                          />

                          <div
                            className={`grid gap-1.5 ${
                              viewMode === 'desktop'
                                ? 'grid-cols-3 sm:grid-cols-5'
                                : 'grid-cols-3'
                            }`}
                          >
                            {[
                              {
                                key: 'overdue',
                                label: 'Overdue',
                                count: taskOverview.overdueCount,
                                toneClass:
                                  taskOverview.overdueCount > 0
                                    ? 'bg-[var(--dw-error-container)] text-[var(--dw-on-error-container)] border-[var(--dw-error)]/25'
                                    : 'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-secondary)] border-[var(--dw-border)]',
                                onClick: () => openTasksFromDashboard('overdue'),
                              },
                              {
                                key: 'due_today',
                                label: 'Due Today',
                                count: taskOverview.dueTodayCount,
                                toneClass:
                                  taskOverview.dueTodayCount > 0
                                    ? 'bg-[var(--dw-warning-container)] text-[var(--dw-on-warning-container)] border-[var(--dw-warning)]/25'
                                    : 'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-secondary)] border-[var(--dw-border)]',
                                onClick: () => openTasksFromDashboard('active', 'today'),
                              },
                              {
                                key: 'upcoming',
                                label: 'Upcoming',
                                count: taskOverview.upcomingCount,
                                toneClass:
                                  'bg-[var(--dw-info-container)] text-[var(--dw-on-info-container)] border-[var(--dw-info)]/20',
                                onClick: () => openTasksFromDashboard('upcoming'),
                              },
                              {
                                key: 'completed',
                                label: 'Completed',
                                count: taskOverview.completedCount,
                                toneClass:
                                  'bg-[var(--dw-success-container)] text-[var(--dw-on-success-container)] border-[var(--dw-success)]/20',
                                onClick: () => openTasksFromDashboard('completed'),
                              },
                              {
                                key: 'remaining',
                                label: 'Remaining',
                                count: taskOverview.remainingCount,
                                toneClass:
                                  'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-primary)] border-[var(--dw-border)]',
                                onClick: () => openTasksFromDashboard('active'),
                              },
                            ].map((item) => (
                              <button
                                key={item.key}
                                type="button"
                                onClick={item.onClick}
                                className={`rounded-[var(--dw-radius-md)] border px-1.5 py-2 text-center transition-opacity hover:opacity-90 cursor-pointer ${item.toneClass}`}
                              >
                                <span className="block text-sm font-extrabold dw-type-numeric-body">
                                  {item.count}
                                </span>
                                <span className="block text-[10px] font-semibold leading-tight mt-0.5 truncate">
                                  {item.label}
                                </span>
                              </button>
                            ))}
                          </div>

                          {/* Today's Planned Tasks (My Day) */}
                          <div
                            role="button"
                            tabIndex={0}
                            onClick={() =>
                              openTasksFromDashboard('my_day', '', taskOverview.todayPlan.planDateIso)
                            }
                            onKeyDown={(e) => {
                              if (e.key === 'Enter' || e.key === ' ') {
                                e.preventDefault();
                                openTasksFromDashboard('my_day', '', taskOverview.todayPlan.planDateIso);
                              }
                            }}
                            className="p-2.5 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] hover:border-[var(--dw-primary)] transition-colors cursor-pointer space-y-1.5"
                          >
                            <div className="flex items-center justify-between gap-2">
                              <div className="flex items-center gap-1.5 min-w-0">
                                <Sun className="w-3.5 h-3.5 text-[var(--dw-warning)] shrink-0" />
                                <span className="text-xs font-bold text-[var(--dw-text-primary)] truncate">
                                  Today&apos;s Plan (My Day)
                                </span>
                              </div>
                              <span className="text-[11px] font-semibold text-[var(--dw-primary)] shrink-0">
                                Open My Day
                              </span>
                            </div>
                            {taskOverview.todayPlan.totalPlannedCount === 0 ? (
                              <p className="text-[11px] text-[var(--dw-text-muted)]">
                                No tasks planned for today yet. Tap to choose priorities in My Day.
                              </p>
                            ) : (
                              <>
                                <div className="flex items-center justify-between gap-2 text-[11px] text-[var(--dw-text-secondary)] dw-type-numeric-body">
                                  <span>
                                    {taskOverview.todayPlan.completedCount} completed ·{' '}
                                    {taskOverview.todayPlan.remainingCount} remaining
                                  </span>
                                  <span className="font-bold text-[var(--dw-text-primary)]">
                                    {taskOverview.todayPlan.progressPercentage}%
                                  </span>
                                </div>
                                <DaywellProgressBar
                                  value={taskOverview.todayPlan.progressPercentage}
                                  label="Today's planned tasks progress"
                                />
                              </>
                            )}
                          </div>

                          {/* Compact Pending Priorities */}
                          {taskOverview.totalActiveAndCompleted === 0 ? (
                            taskOverview.archivedCount > 0 ? (
                              <div className="flex items-center justify-between gap-2 text-xs text-[var(--dw-text-muted)] py-1">
                                <span>
                                  All recorded tasks are archived.
                                </span>
                                <DaywellButton
                                  label="View Archived"
                                  variant="text"
                                  size="compact"
                                  onClick={() => openTasksFromDashboard('archived')}
                                />
                              </div>
                            ) : (
                              <p className="text-xs text-[var(--dw-text-muted)] text-center py-1">
                                No active tasks yet. Add one via Quick Capture or To-Do.
                              </p>
                            )
                          ) : prioritizedDashboardTasks.length === 0 ? (
                            <p className="text-xs font-semibold text-[var(--dw-primary)] py-1">
                              All active tasks are completed.
                            </p>
                          ) : (
                            <div className="space-y-1.5 pt-1 border-t border-[var(--dw-divider)]">
                              <div className="flex items-center justify-between text-[11px] text-[var(--dw-text-muted)]">
                                <span className="font-semibold uppercase tracking-wider">
                                  Up Next
                                </span>
                                <span>{prioritizedDashboardTasks.length} remaining</span>
                              </div>
                              {prioritizedDashboardTasks.slice(0, 3).map((item) => {
                                const isOverdue = Boolean(
                                  item.dueDate && item.dueDate < taskOverview.todayIso
                                );
                                return (
                                  <div
                                    key={item.id}
                                    className="flex items-start gap-2.5 py-1.5"
                                  >
                                    <button
                                      type="button"
                                      aria-label={`Toggle ${item.title}`}
                                      onClick={() => toggleTask(item.id)}
                                      className={`w-4 h-4 rounded-[4px] border mt-0.5 flex items-center justify-center shrink-0 cursor-pointer transition-colors ${
                                        isTaskCompleted(item)
                                          ? 'bg-[var(--dw-primary-brand)] border-[var(--dw-primary-brand)] text-white'
                                          : 'border-[var(--dw-border)] bg-transparent hover:border-[var(--dw-primary)]'
                                      }`}
                                    >
                                      {isTaskCompleted(item) && <Check className="w-3 h-3 stroke-[3]" />}
                                    </button>
                                    <div
                                      role="button"
                                      tabIndex={0}
                                      onClick={() => {
                                        setTasksSubTab('tasks');
                                        setRequestedTaskFocus({
                                          taskId: item.id,
                                          openMode: 'details',
                                          nonce: Date.now(),
                                        });
                                        navigateTo('tasks');
                                      }}
                                      onKeyDown={(e) => {
                                        if (e.key === 'Enter' || e.key === ' ') {
                                          e.preventDefault();
                                          setTasksSubTab('tasks');
                                          setRequestedTaskFocus({
                                            taskId: item.id,
                                            openMode: 'details',
                                            nonce: Date.now(),
                                          });
                                          navigateTo('tasks');
                                        }
                                      }}
                                      className="flex-1 min-w-0 cursor-pointer hover:opacity-85"
                                    >
                                      <p className="text-xs font-semibold text-[var(--dw-text-primary)] truncate">
                                        {item.title}
                                      </p>
                                      <div className="flex flex-wrap items-center gap-1.5 text-[11px] text-[var(--dw-text-muted)] mt-0.5">
                                        {(item.priority === 'urgent' || item.priority === 'high') && (
                                          <Flag className="w-3 h-3 text-[var(--dw-warning)]" />
                                        )}
                                        {item.dueDate && (
                                          <span className={isOverdue ? 'text-[var(--dw-error)] font-semibold' : ''}>
                                            {isOverdue ? 'Overdue' : 'Due'} {item.dueDate}
                                          </span>
                                        )}
                                        {!item.dueDate && (
                                          <span>{item.category || item.projectName || 'Personal'}</span>
                                        )}
                                        {(() => {
                                          const rec = resolveEffectiveRecurrenceConfig(item);
                                          if (!rec) return null;
                                          return (
                                            <span className="inline-flex items-center gap-0.5 text-[var(--dw-text-secondary)]">
                                              <Repeat2 className="w-3 h-3 text-[var(--dw-primary)]" />
                                              {formatRecurrenceSummary(rec)}
                                            </span>
                                          );
                                        })()}
                                      </div>
                                    </div>
                                    {item.hasReminder && (
                                      <Bell className="w-3.5 h-3.5 text-[var(--dw-text-muted)] mt-0.5 shrink-0" />
                                    )}
                                  </div>
                                );
                              })}
                              {prioritizedDashboardTasks.length > 3 && (
                                <DaywellButton
                                  label={`+ ${prioritizedDashboardTasks.length - 3} more remaining tasks`}
                                  variant="text"
                                  size="compact"
                                  onClick={() => openTasksFromDashboard('active')}
                                />
                              )}
                            </div>
                          )}
                        </DaywellCard>
                      </div>

                      {/* Live Project Progress Summary */}
                      <div className="space-y-2 pt-1">
                        <DaywellSectionHeader
                          title="Project Progress"
                          count={
                            projectsOverview.totalProjectsCount > 0
                              ? projectsOverview.totalProjectsCount
                              : undefined
                          }
                          actionLabel="All Projects"
                          onActionPressed={() => openProjectsFromDashboard(null)}
                        />
                        {projectsOverview.totalProjectsCount === 0 ? (
                          <DaywellCard padding="md" radius="lg">
                            <DaywellEmptyState
                              icon={<Layers className="w-6 h-6" />}
                              message="No active projects yet"
                              subtitle="Group related tasks and milestones into a project to track completion."
                              actionLabel="Open Projects"
                              onActionPressed={() => openProjectsFromDashboard(null)}
                            />
                          </DaywellCard>
                        ) : (
                          <DaywellCard padding="md" radius="lg" className="space-y-3">
                            <div className="flex flex-wrap items-center justify-between gap-2 text-[11px] text-[var(--dw-text-secondary)] dw-type-numeric-body">
                              <span>
                                {projectsOverview.completedTasks}/{projectsOverview.totalTasks}{' '}
                                {projectsOverview.totalTasks === 1 ? 'task' : 'tasks'} ·{' '}
                                {projectsOverview.remainingTasks} remaining
                              </span>
                              {projectsOverview.totalMilestones > 0 && (
                                <span>
                                  {projectsOverview.completedMilestones}/{projectsOverview.totalMilestones}{' '}
                                  {projectsOverview.totalMilestones === 1 ? 'milestone' : 'milestones'}
                                </span>
                              )}
                            </div>
                            <div className="space-y-2.5">
                              {projectsOverview.projects.slice(0, 4).map((item) => (
                                <div
                                  key={item.project.id}
                                  role="button"
                                  tabIndex={0}
                                  onClick={() => openProjectsFromDashboard(item.project.id)}
                                  onKeyDown={(e) => {
                                    if (e.key === 'Enter' || e.key === ' ') {
                                      e.preventDefault();
                                      openProjectsFromDashboard(item.project.id);
                                    }
                                  }}
                                  className="p-2.5 rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] bg-[var(--dw-surface-subtle)] hover:border-[var(--dw-primary)] transition-colors cursor-pointer space-y-1.5"
                                >
                                  <div className="flex items-center justify-between gap-2">
                                    <div className="flex items-center gap-1.5 min-w-0">
                                      <span className="text-xs font-bold text-[var(--dw-text-primary)] truncate">
                                        {item.project.title}
                                      </span>
                                      {item.project.status !== 'active' && (
                                        <DaywellStatusBadge
                                          label={item.project.status === 'on_hold' ? 'On Hold' : 'Completed'}
                                          tone={item.project.status === 'completed' ? 'success' : 'warning'}
                                          showIcon={false}
                                        />
                                      )}
                                    </div>
                                    <span className="text-xs font-extrabold text-[var(--dw-text-primary)] dw-type-numeric-body shrink-0">
                                      {item.displayPercentage}%
                                    </span>
                                  </div>
                                  <DaywellProgressBar
                                    value={item.displayPercentage}
                                    label={`${item.project.title} progress`}
                                  />
                                  <div className="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
                                    <span>
                                      {item.completedTasks}/{item.totalTasks}{' '}
                                      {item.totalTasks === 1 ? 'task' : 'tasks'} · {item.remainingTasks}{' '}
                                      remaining
                                    </span>
                                    {item.hasMilestones && (
                                      <span>
                                        · {item.completedMilestones}/{item.totalMilestones}{' '}
                                        {item.totalMilestones === 1 ? 'milestone' : 'milestones'}
                                      </span>
                                    )}
                                    {item.overdueTasks > 0 && (
                                      <span className="text-[var(--dw-error)] font-semibold">
                                        · {item.overdueTasks} overdue
                                      </span>
                                    )}
                                    {item.primaryMetricTitle && (
                                      <span>· Tracking: {item.primaryMetricTitle}</span>
                                    )}
                                  </div>
                                </div>
                              ))}
                            </div>
                            {projectsOverview.totalProjectsCount > 4 && (
                              <DaywellButton
                                label={`+ ${projectsOverview.totalProjectsCount - 4} more projects`}
                                variant="text"
                                size="compact"
                                onClick={() => openProjectsFromDashboard(null)}
                              />
                            )}
                          </DaywellCard>
                        )}
                      </div>

                      {/* Shared Quick Capture Inbox Section (Live Store) */}
                      <div className="space-y-2 pt-1">
                        <DaywellSectionHeader
                          title="Inbox Captures"
                          count={unprocessedInboxItems.length > 0 ? unprocessedInboxItems.length : undefined}
                          actionLabel="Review Inbox"
                          onActionPressed={() => {
                            setRequestedTasksFilter({ filter: 'inbox', nonce: Date.now() });
                            setTasksSubTab('tasks');
                            navigateTo('tasks');
                          }}
                        />
                        <DaywellCard padding="compact" className="space-y-2">
                          <div className="flex items-center justify-between gap-2 text-[11px] text-[var(--dw-text-secondary)]">
                            <span>
                              {unprocessedInboxItems.length} unorganized · {processedInboxCount} processed
                            </span>
                            <DaywellButton
                              label="Quick capture"
                              variant="text"
                              size="compact"
                              onClick={() => setIsQuickCaptureOpen(true)}
                            />
                          </div>
                          {inboxItems.length === 0 ? (
                            <p className="text-xs text-[var(--dw-text-muted)] text-center py-1.5">
                              Inbox is clear. Use Quick Capture to save tasks, ideas, notes, or expenses fast.
                            </p>
                          ) : unprocessedInboxItems.length === 0 ? (
                            <p className="text-xs font-semibold text-[var(--dw-primary)] py-1">
                              All captured items have been processed.
                            </p>
                          ) : (
                            <div className="space-y-1.5">
                              {unprocessedInboxItems.slice(0, 3).map((item) => (
                                <div
                                  key={item.id}
                                  onClick={() => {
                                    setRequestedTasksFilter({ filter: 'inbox', nonce: Date.now() });
                                    setTasksSubTab('tasks');
                                    navigateTo('tasks');
                                  }}
                                  className="flex items-start justify-between gap-2 py-1 border-t border-[var(--dw-divider)] first:border-t-0 first:pt-0 cursor-pointer"
                                >
                                  <p className="text-xs font-medium text-[var(--dw-text-primary)] line-clamp-2 flex-1 min-w-0">
                                    {item.rawText}
                                  </p>
                                  <DaywellStatusBadge
                                    tone="info"
                                    showIcon={false}
                                    label={INBOX_CATEGORY_LABELS[item.category].toUpperCase()}
                                  />
                                </div>
                              ))}
                            </div>
                          )}
                        </DaywellCard>
                      </div>
                    </div>

                    {/* Finance & Storage Column */}
                    <div
                      className={
                        viewMode === 'desktop'
                          ? 'lg:col-span-5 space-y-4 lg:order-1 order-2'
                          : 'space-y-4'
                      }
                    >
                      {/* Safe Harbor v7 Hero Snippet (Live Finance Data) */}
                      <DaywellCard padding="md" radius="xl" className="space-y-2">
                        <div className="flex items-center justify-between text-[10px] font-bold tracking-wider uppercase">
                          <span
                            className={
                              todaySafeHarbor.isShortfall
                                ? 'text-[var(--dw-on-expense-container)]'
                                : 'text-[var(--dw-text-muted)]'
                            }
                          >
                            {todaySafeHarbor.isShortfall ? 'SHORTFALL · ' : ''}AVAILABLE TO SPEND (H:{' '}
                            {todaySafeHarbor.planningPeriodEndIso})
                          </span>
                        </div>
                        <div className="flex items-baseline justify-between gap-2 mt-0.5">
                          <span
                            className={`dw-type-numeric-hero ${
                              todaySafeHarbor.isShortfall
                                ? 'text-[var(--dw-on-expense-container)]'
                                : 'text-[var(--dw-text-primary)]'
                            }`}
                          >
                            {(todaySafeHarbor.availableToSpendCents / 100).toLocaleString('en-US', {
                              minimumFractionDigits: 2,
                              maximumFractionDigits: 2,
                            })}{' '}
                            <span className="text-sm font-bold text-[var(--dw-primary)]">
                              ETB
                            </span>
                          </span>
                          <DaywellButton
                            label="View ledger"
                            variant="text"
                            size="compact"
                            trailingIcon={<ChevronRight className="w-3.5 h-3.5" />}
                            onClick={() => navigateTo('finance')}
                          />
                        </div>
                        {(todaySafeHarbor.prepaidCardCreditCents > 0 ||
                          todaySafeHarbor.nonEtbAccountCount > 0 ||
                          (todaySafeHarbor.unverifiedAccountCount || 0) > 0 ||
                          todaySafeHarbor.currencyReviewEntryCount > 0 ||
                          todaySafeHarbor.unverifiedLegacyPaidCount > 0) && (
                          <div className="text-[11px] text-[var(--dw-text-muted)] flex flex-wrap gap-x-3 gap-y-0.5 tabular-nums">
                            {todaySafeHarbor.prepaidCardCreditCents > 0 && (
                              <span className="text-[var(--dw-on-income-container)] font-medium">
                                Includes +{formatBirr(todaySafeHarbor.prepaidCardCreditCents)} Prepaid
                                Credit
                              </span>
                            )}
                            {todaySafeHarbor.nonEtbAccountCount > 0 && (
                              <span>
                                {todaySafeHarbor.nonEtbAccountCount} non-ETB account(s) excluded
                              </span>
                            )}
                            {(todaySafeHarbor.unverifiedAccountCount || 0) > 0 && (
                              <span className="text-[var(--dw-on-warning-container)]">
                                {todaySafeHarbor.unverifiedAccountCount} unverified account(s) excluded
                              </span>
                            )}
                            {todaySafeHarbor.currencyReviewEntryCount > 0 && (
                              <span className="text-[var(--dw-on-expense-container)] font-medium">
                                {todaySafeHarbor.currencyReviewEntryCount} entry review notice(s)
                              </span>
                            )}
                            {todaySafeHarbor.unverifiedLegacyPaidCount > 0 && (
                              <span className="text-[var(--dw-on-warning-container)]">
                                {todaySafeHarbor.unverifiedLegacyPaidCount} unverified legacy bill(s)
                              </span>
                            )}
                          </div>
                        )}
                        {todayFinanceSummary.recentEntries.length > 0 && (
                          <div className="pt-2 space-y-1.5 border-t border-[var(--dw-divider)]">
                            {todayFinanceSummary.recentEntries.map(({ entry, cls, formattedAmount }) => (
                              <div
                                key={entry.id}
                                className={`flex items-center justify-between gap-2 text-[11px] ${
                                  entry.isVoided ? 'opacity-55' : ''
                                }`}
                              >
                                <div className="min-w-0 flex items-center gap-1.5">
                                  <span
                                    className={`truncate font-medium text-[var(--dw-text-primary)] ${
                                      entry.isVoided ? 'line-through' : ''
                                    }`}
                                  >
                                    {entry.description}
                                  </span>
                                  {entry.isVoided ? (
                                    <DaywellStatusBadge tone="neutral" showIcon={false} label="Voided" />
                                  ) : cls?.status === 'excluded_non_etb' ? (
                                    <DaywellStatusBadge
                                      tone="warning"
                                      showIcon={false}
                                      label={`Excluded (${cls.nativeCurrencyCode || cls.touchedCurrencies[0] || 'Non-ETB'})`}
                                    />
                                  ) : cls?.status === 'mixed_or_ambiguous' ? (
                                    <DaywellStatusBadge
                                      tone="error"
                                      showIcon={false}
                                      label="Currency Review"
                                    />
                                  ) : null}
                                </div>
                                <span className="dw-type-mono font-semibold text-[var(--dw-text-secondary)] shrink-0">
                                  {formattedAmount}
                                </span>
                              </div>
                            ))}
                          </div>
                        )}
                      </DaywellCard>

                      {/* Device Storage & Local Export Link */}
                      <DaywellCard
                        padding="compact"
                        onClick={() => navigateTo('sync_backup')}
                        className="flex items-center justify-between text-xs text-[var(--dw-text-secondary)]"
                      >
                        <div className="flex items-center gap-2 min-w-0">
                          <HardDrive className="w-3.5 h-3.5 text-[var(--dw-text-muted)] shrink-0" />
                          <span className="truncate">Saved on this device · Local backup</span>
                        </div>
                        <ChevronRight className="w-3.5 h-3.5 text-[var(--dw-text-muted)] shrink-0" />
                      </DaywellCard>
                    </div>
                  </div>
                </div>
              )}

              {/* SCREEN 02: TASKS & PROJECTS (Preserved State) */}
              <div className={activeScreen === 'tasks' ? 'block' : 'hidden'}>
                <DaywellTasksModule
                  tasks={tasks}
                  onUpdateTasks={setTasks}
                  notes={notes}
                  onUpdateNotes={handleUpdateNotes}
                  inboxItems={inboxItems}
                  onUpdateInboxItems={handleUpdateInboxItems}
                  dailyPlanningEntries={dailyPlanningEntries}
                  onUpdateDailyPlanningEntries={handleUpdateDailyPlanningEntries}
                  requestedFilter={requestedTasksFilter}
                  requestedTaskFocus={requestedTaskFocus}
                  onRequestQuickCapture={() => setIsQuickCaptureOpen(true)}
                  onNavigateToCalendar={(dateStr) => {
                    setRequestedCalendarFocus({ dateStr, nonce: Date.now() });
                    navigateTo('calendar');
                  }}
                  onNavigateToNote={(noteId) => {
                    setRequestedNoteFocus({ noteId, nonce: Date.now() });
                    navigateTo('notes');
                  }}
                  activeSubTab={tasksSubTab}
                  onSubTabChange={setTasksSubTab}
                  selectedProjectId={selectedProjectId}
                  onSelectProjectId={setSelectedProjectId}
                />
              </div>

              {/* SCREEN 03: CALENDAR (Preserved State) */}
              <div className={activeScreen === 'calendar' ? 'block' : 'hidden'}>
                <DaywellCalendarModule
                  tasks={tasks
                    .filter((t) => !t.isArchived && t.status !== 'cancelled')
                    .map((t) => {
                      const rec = resolveEffectiveRecurrenceConfig(t);
                      return {
                        id: t.id,
                        title: t.title,
                        dueDate: t.dueDate,
                        scheduledDate: t.scheduledDate,
                        scheduledTime: t.scheduledTime,
                        estimatedDurationMinutes: t.estimatedDurationMinutes,
                        status: t.status,
                        isArchived: t.isArchived,
                        completed: t.completed,
                        priority: t.priority,
                        isRecurring: t.isRecurring,
                        recurringRule: t.recurringRule,
                        recurrenceRule: t.recurrenceRule,
                        recurrenceConfig: t.recurrenceConfig,
                        recurrenceSummary: rec
                          ? formatRecurrenceSummary(rec)
                          : undefined,
                        projectId: t.projectId,
                        projectName: t.projectName,
                      };
                    })}
                  onToggleTask={toggleTask}
                  onNavigateToTask={(taskId) => {
                    setTasksSubTab('tasks');
                    setRequestedTaskFocus({
                      taskId,
                      openMode: 'details',
                      nonce: Date.now(),
                    });
                    navigateTo('tasks');
                  }}
                  requestedFocusDate={requestedCalendarFocus}
                  dailyRhythmDays={dailyRhythmDays}
                  onRequestQuickCapture={() => setIsQuickCaptureOpen(true)}
                />
              </div>

              {/* SCREEN 05: GOALS (DEPRECATED PROTOTYPE) */}
              {activeScreen === 'goals' && (
                <div className="space-y-4">
                  <div className="flex items-center justify-between pt-1">
                    <div className="flex items-center gap-2">
                      <DaywellIconButton
                        label="Go back"
                        tone="muted"
                        onClick={handleBack}
                        icon={<ArrowLeft className="w-5 h-5" />}
                      />
                      <div>
                        <div className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
                          SMALL STEPS, LASTING CHANGE
                        </div>
                        <h1 className="dw-type-heading text-[var(--dw-text-primary)]">
                          Goals
                        </h1>
                      </div>
                    </div>
                    <DaywellIconButton
                      label="Quick capture"
                      tone="primary"
                      onClick={() => setIsQuickCaptureOpen(true)}
                      icon={<Plus className="w-5 h-5 stroke-[2.5]" />}
                    />
                  </div>

                  <DeprecatedPrototypeBanner areaName="Goals" />

                  <div className="flex items-center gap-2">
                    {[
                      { key: 'all', label: 'All goals' },
                      { key: 'short', label: 'Short term' },
                      { key: 'long', label: 'Long term' },
                    ].map((opt) => (
                      <button
                        key={opt.key}
                        type="button"
                        onClick={() => setGoalFilter(opt.key as 'all' | 'short' | 'long')}
                        className={`text-xs px-3.5 py-1.5 rounded-[var(--dw-radius-full)] font-semibold transition-all cursor-pointer ${
                          goalFilter === opt.key
                            ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)]'
                            : 'bg-[var(--dw-card)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)]'
                        }`}
                      >
                        {opt.label}
                      </button>
                    ))}
                  </div>

                  <DaywellCard padding="md" radius="xl">
                    <DaywellEmptyState
                      icon={<Target className="w-8 h-8" />}
                      message="No active goals yet"
                      subtitle="Define short-term milestones or long-term personal ambitions in Finance Savings Goals."
                      actionLabel="Open Finance Plan"
                      onActionPressed={() => navigateTo('finance')}
                    />
                  </DaywellCard>
                </div>
              )}

              {/* SCREEN 06: NOTES & KNOWLEDGE (Preserved State) */}
              <div className={activeScreen === 'notes' ? 'block' : 'hidden'}>
                <div className="space-y-4">
                  <DaywellNotesModule
                    notes={notes}
                    onUpdateNotes={handleUpdateNotes}
                    tasks={tasks}
                    requestedNoteFocus={requestedNoteFocus}
                    layoutMode={viewMode === 'desktop' ? 'auto' : 'compact'}
                    isActive={activeScreen === 'notes'}
                    onNavigateToTask={(taskId) => {
                      setTasksSubTab('tasks');
                      setRequestedTaskFocus({
                        taskId,
                        openMode: 'details',
                        nonce: Date.now(),
                      });
                      navigateTo('tasks');
                    }}
                    onRequestQuickCapture={() => setIsQuickCaptureOpen(true)}
                    onNavigateToModule={(mod) => navigateTo(mod as ScreenId)}
                  />
                </div>
              </div>

              {/* SCREEN 07: FINANCE (Preserved State) */}
              <div className={activeScreen === 'finance' ? 'block' : 'hidden'}>
                <DaywellFinanceModule
                  effectiveDark={effectiveDark}
                  onOpenQuickCapture={() => setIsQuickCaptureOpen(true)}
                  composerPrefill={financeComposerPrefill}
                  onClearComposerPrefill={() => setFinanceComposerPrefill(null)}
                  requestedTab={requestedFinanceTab}
                />
              </div>

              {/* SCREEN 12: MORE / ALL AREAS */}
              {activeScreen === 'more' && (
                <div className="space-y-4">
                  {/* Header with Back Navigation */}
                  <div className="flex items-center justify-between pt-1">
                    <div className="flex items-center gap-2">
                      <DaywellIconButton
                        label="Go back"
                        tone="muted"
                        onClick={handleBack}
                        icon={<ArrowLeft className="w-5 h-5" />}
                      />
                      <div>
                        <div className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
                          DAYWELL / ALL AREAS
                        </div>
                        <h1 className="dw-type-heading text-[var(--dw-text-primary)]">
                          Your space
                        </h1>
                      </div>
                    </div>
                    <DaywellIconButton
                      label="Quick capture"
                      tone="primary"
                      onClick={() => setIsQuickCaptureOpen(true)}
                      icon={<Plus className="w-5 h-5 stroke-[2.5]" />}
                    />
                  </div>

                  {/* Profile Card */}
                  <DaywellCard padding="compact" className="space-y-2">
                    <div className="flex items-center justify-between gap-2">
                      <div className="flex items-center gap-3 min-w-0">
                        <div className="w-11 h-11 rounded-[var(--dw-radius-full)] bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] font-bold text-sm flex items-center justify-center uppercase shrink-0">
                          {(userProfile.name || 'User').slice(0, 2)}
                        </div>
                        <div className="min-w-0">
                          <h3 className="text-sm font-bold text-[var(--dw-text-primary)] truncate">
                            {userProfile.name || 'Daywell User'}
                          </h3>
                          <p className="text-[11px] text-[var(--dw-text-muted)]">
                            A little more intentional, every day.
                          </p>
                        </div>
                      </div>

                      <div className="flex items-center gap-1 shrink-0">
                        <DaywellButton
                          label="Edit Name"
                          variant="text"
                          size="compact"
                          onClick={() => {
                            setProfileNameInput(userProfile.name || '');
                            setIsEditingProfileName(true);
                          }}
                        />
                        <DaywellButton
                          label="Setup"
                          variant="outlined"
                          size="compact"
                          onClick={() => {
                            setIsSetupWizardOpen(true);
                          }}
                          title="Rerun the first-time setup wizard"
                        />
                      </div>
                    </div>

                    {isEditingProfileName && (
                      <div className="pt-2 border-t border-[var(--dw-divider)] flex items-center gap-2">
                        <input
                          type="text"
                          value={profileNameInput}
                          onChange={(e) => setProfileNameInput(e.target.value)}
                          placeholder="Enter your name"
                          className="flex-1 min-h-[36px] px-2.5 py-1 text-xs bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] rounded-[var(--dw-radius-sm)] text-[var(--dw-text-primary)] focus:outline-none focus:border-[var(--dw-primary)]"
                        />
                        <DaywellButton
                          label="Save"
                          size="compact"
                          onClick={() => {
                            const trimmed = profileNameInput.trim();
                            if (trimmed) {
                              const updated = { ...userProfile, name: trimmed };
                              setUserProfile(updated);
                              localStorage.setItem('daywell_user_profile', JSON.stringify(updated));
                            }
                            setIsEditingProfileName(false);
                          }}
                        />
                        <DaywellButton
                          label="Cancel"
                          variant="text"
                          size="compact"
                          onClick={() => setIsEditingProfileName(false)}
                        />
                      </div>
                    )}
                  </DaywellCard>

                  {/* Built-in Daily Faith Check-In (Bible study & Prayer) */}
                  {(() => {
                    const todayIso = CalendarDate.today().toIsoString();
                    const todayFaithRecord =
                      dailyRhythmDays.find((d) => d.dateIso === todayIso) ??
                      createEmptyDailyRhythmDay(todayIso);
                    return (
                      <DailyFaithCheckInCard
                        dateIso={todayIso}
                        record={todayFaithRecord}
                        isToday={true}
                        statusFeedback={faithFeedback}
                        errorMessage={faithError}
                        onToggleBibleStudy={(nextValue) => {
                          const res = dailyRhythmWorkflowService.updateFaith({
                            dateIso: todayIso,
                            bibleStudyDone: nextValue,
                            todayIso,
                          });
                          setDailyRhythmDays(dailyRhythmService.loadDays());
                          if (!res.applied && res.reason !== 'unchanged') {
                            setFaithFeedback(null);
                            setFaithError('Only today\'s Faith check-in can be updated.');
                            return;
                          }
                          setFaithError(null);
                          const msg = nextValue
                            ? res.record.prayerDone
                              ? 'Faith check-in complete for today (2/2).'
                              : 'Bible study saved.'
                            : 'Bible study unchecked.';
                          setFaithFeedback(msg);
                          setTimeout(() => setFaithFeedback((cur) => (cur === msg ? null : cur)), 3000);
                        }}
                        onTogglePrayer={(nextValue) => {
                          const res = dailyRhythmWorkflowService.updateFaith({
                            dateIso: todayIso,
                            prayerDone: nextValue,
                            todayIso,
                          });
                          setDailyRhythmDays(dailyRhythmService.loadDays());
                          if (!res.applied && res.reason !== 'unchanged') {
                            setFaithFeedback(null);
                            setFaithError('Only today\'s Faith check-in can be updated.');
                            return;
                          }
                          setFaithError(null);
                          const msg = nextValue
                            ? res.record.bibleStudyDone
                              ? 'Faith check-in complete for today (2/2).'
                              : 'Prayer saved.'
                            : 'Prayer unchecked.';
                          setFaithFeedback(msg);
                          setTimeout(() => setFaithFeedback((cur) => (cur === msg ? null : cur)), 3000);
                        }}
                      />
                    );
                  })()}

                  {/* All Areas Grid */}
                  <div className="space-y-2 pt-1">
                    <DaywellSectionHeader title="All areas" />

                    <div className="grid grid-cols-2 gap-2.5">
                      <DaywellCard padding="compact" onClick={() => navigateTo('tasks')} className="space-y-1">
                        <CheckCircle2 className="w-4 h-4 text-[var(--dw-primary)]" />
                        <h4 className="text-xs font-bold text-[var(--dw-text-primary)]">Tasks</h4>
                        <p className="text-[10px] text-[var(--dw-text-muted)]">
                          {tasks.filter((t) => !t.isArchived && !t.completed && t.status !== 'cancelled').length} open tasks
                        </p>
                      </DaywellCard>

                      <DaywellCard padding="compact" onClick={() => navigateTo('notes')} className="space-y-1">
                        <NotebookPen className="w-4 h-4 text-[var(--dw-primary)]" />
                        <h4 className="text-xs font-bold text-[var(--dw-text-primary)]">
                          Notes & knowledge
                        </h4>
                        <p className="text-[10px] text-[var(--dw-text-muted)]">Local notebooks</p>
                      </DaywellCard>

                      <DaywellCard padding="compact" onClick={() => navigateTo('finance')} className="space-y-1">
                        <Wallet className="w-4 h-4 text-[var(--dw-primary)]" />
                        <h4 className="text-xs font-bold text-[var(--dw-text-primary)]">Finance</h4>
                        <p className="text-[10px] text-[var(--dw-text-muted)]">Balanced ETB ledger</p>
                      </DaywellCard>

                      <DaywellCard padding="compact" onClick={() => navigateTo('calendar')} className="space-y-1">
                        <CalendarDays className="w-4 h-4 text-[var(--dw-primary)]" />
                        <h4 className="text-xs font-bold text-[var(--dw-text-primary)]">Calendar</h4>
                        <p className="text-[10px] text-[var(--dw-text-muted)]">Dual Ethiopian & Gregorian</p>
                      </DaywellCard>

                      <DaywellCard padding="compact" onClick={() => navigateTo('projects')} className="space-y-1">
                        <Layers className="w-4 h-4 text-[var(--dw-primary)]" />
                        <h4 className="text-xs font-bold text-[var(--dw-text-primary)]">Projects</h4>
                        <p className="text-[10px] text-[var(--dw-text-muted)] dw-type-numeric-body">
                          {activeProjectsCount} active {activeProjectsCount === 1 ? 'project' : 'projects'}
                        </p>
                      </DaywellCard>

                      <DaywellCard padding="compact" onClick={() => navigateTo('goals')} className="space-y-1">
                        <Target className="w-4 h-4 text-[var(--dw-primary)]" />
                        <h4 className="text-xs font-bold text-[var(--dw-text-primary)]">Goals</h4>
                        <p className="text-[10px] text-[var(--dw-text-muted)]">Deprecated prototype</p>
                      </DaywellCard>

                      <DaywellCard padding="compact" onClick={() => navigateTo('priorities')} className="space-y-1">
                        <ListOrdered className="w-4 h-4 text-[var(--dw-primary)]" />
                        <h4 className="text-xs font-bold text-[var(--dw-text-primary)]">Priorities</h4>
                        <p className="text-[10px] text-[var(--dw-text-muted)]">Deprecated prototype</p>
                      </DaywellCard>

                      <DaywellCard padding="compact" onClick={() => navigateTo('tools')} className="space-y-1">
                        <Calculator className="w-4 h-4 text-[var(--dw-primary)]" />
                        <h4 className="text-xs font-bold text-[var(--dw-text-primary)]">Tools</h4>
                        <p className="text-[10px] text-[var(--dw-text-muted)]">Deprecated prototype</p>
                      </DaywellCard>

                      <DaywellCard padding="compact" onClick={() => navigateTo('history')} className="space-y-1">
                        <ChartNoAxesColumn className="w-4 h-4 text-[var(--dw-primary)]" />
                        <h4 className="text-xs font-bold text-[var(--dw-text-primary)]">History</h4>
                        <p className="text-[10px] text-[var(--dw-text-muted)]">Deprecated prototype</p>
                      </DaywellCard>

                      <DaywellCard padding="compact" onClick={() => navigateTo('relationships')} className="space-y-1">
                        <UsersRound className="w-4 h-4 text-[var(--dw-primary)]" />
                        <h4 className="text-xs font-bold text-[var(--dw-text-primary)]">Relationships</h4>
                        <p className="text-[10px] text-[var(--dw-text-muted)]">Deprecated prototype</p>
                      </DaywellCard>
                    </div>
                  </div>

                  {/* Make it yours */}
                  <div className="space-y-2 pt-1">
                    <DaywellSectionHeader title="Make it yours" />
                    <div className="space-y-1.5">
                      <DaywellCard
                        padding="compact"
                        onClick={() => setThemeMode(effectiveDark ? 'light' : 'dark')}
                        className="flex items-center justify-between"
                      >
                        <div className="flex items-center gap-2.5">
                          <SunMoon className="w-4 h-4 text-[var(--dw-primary)]" />
                          <div>
                            <p className="text-xs font-bold text-[var(--dw-text-primary)]">
                              Appearance
                            </p>
                            <p className="text-[10px] text-[var(--dw-text-muted)]">
                              System · Light / Dark ({effectiveDark ? 'Dark active' : 'Light active'})
                            </p>
                          </div>
                        </div>
                        <ChevronRight className="w-4 h-4 text-[var(--dw-text-muted)]" />
                      </DaywellCard>

                      <DaywellCard
                        padding="compact"
                        onClick={() => {
                          setNotificationSupportStatus(
                            taskRemindersService.getWebNotificationSupportStatus()
                          );
                          setActiveTaskReminderCount(
                            taskRemindersService
                              .loadTaskReminders()
                              .filter((r) => r.isActive).length
                          );
                          setIsNotificationStatusModalOpen(true);
                        }}
                        className="flex items-center justify-between"
                      >
                        <div className="flex items-center gap-2.5">
                          <Bell className="w-4 h-4 text-[var(--dw-primary)]" />
                          <div>
                            <p className="text-xs font-bold text-[var(--dw-text-primary)]">
                              Notifications & reminders
                            </p>
                            <p className="text-[10px] text-[var(--dw-text-muted)]">
                              {activeTaskReminderCount} active task reminder
                              {activeTaskReminderCount === 1 ? '' : 's'} · Web Preview tab alerts
                            </p>
                          </div>
                        </div>
                        <ChevronRight className="w-4 h-4 text-[var(--dw-text-muted)]" />
                      </DaywellCard>
                    </div>
                  </div>

                  {/* Your Data */}
                  <div className="space-y-2 pt-1">
                    <DaywellSectionHeader title="Your data" />
                    <div className="space-y-1.5">
                      <DaywellCard
                        padding="compact"
                        onClick={() => navigateTo('sync_backup')}
                        className="flex items-center justify-between"
                      >
                        <div className="flex items-center gap-2.5">
                          <RefreshCw className="w-4 h-4 text-[var(--dw-primary)]" />
                          <div>
                            <p className="text-xs font-bold text-[var(--dw-text-primary)]">
                              Sync & backup
                            </p>
                            <p className="text-[10px] text-[var(--dw-text-muted)]">
                              Local save, canonical export & restore
                            </p>
                          </div>
                        </div>
                        <ChevronRight className="w-4 h-4 text-[var(--dw-text-muted)]" />
                      </DaywellCard>

                      <DaywellCard
                        padding="compact"
                        onClick={() => navigateTo('sync_backup')}
                        className="flex items-center justify-between"
                      >
                        <div className="flex items-center gap-2.5">
                          <Database className="w-4 h-4 text-[var(--dw-primary)]" />
                          <div>
                            <p className="text-xs font-bold text-[var(--dw-text-primary)]">
                              Data management
                            </p>
                            <p className="text-[10px] text-[var(--dw-text-muted)]">
                              Export & import SharedStateBridge JSON
                            </p>
                          </div>
                        </div>
                        <ChevronRight className="w-4 h-4 text-[var(--dw-text-muted)]" />
                      </DaywellCard>
                    </div>
                  </div>

                  <p className="text-center text-[10px] text-[var(--dw-text-muted)] pt-2 pb-4">
                    Daywell · A considered place for everyday life.
                  </p>
                </div>
              )}

              {/* SCREEN: RELATIONSHIPS (DEPRECATED PROTOTYPE) */}
              {activeScreen === 'relationships' && (
                <div className="space-y-4">
                  <div className="flex items-center justify-between pt-1">
                    <div className="flex items-center gap-2">
                      <DaywellIconButton
                        label="Go back"
                        tone="muted"
                        onClick={handleBack}
                        icon={<ArrowLeft className="w-5 h-5" />}
                      />
                      <div>
                        <div className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
                          INTENTIONAL CONNECTIONS
                        </div>
                        <h1 className="dw-type-heading text-[var(--dw-text-primary)]">
                          Relationships
                        </h1>
                      </div>
                    </div>
                    <DaywellIconButton
                      label="Add connection"
                      tone="primary"
                      onClick={() => setIsQuickCaptureOpen(true)}
                      icon={<Plus className="w-5 h-5 stroke-[2.5]" />}
                    />
                  </div>

                  <DeprecatedPrototypeBanner areaName="Relationships" />

                  <DaywellCard padding="md" radius="xl">
                    <DaywellEmptyState
                      icon={<UsersRound className="w-8 h-8" />}
                      message="No contacts or cadence tracked"
                      subtitle="Prototype area — use Notes & Tasks to record follow-ups for now."
                      actionLabel="Open Notes"
                      onActionPressed={() => navigateTo('notes')}
                    />
                  </DaywellCard>
                </div>
              )}

              {/* SCREEN: PRIORITIES (DEPRECATED PROTOTYPE) */}
              {activeScreen === 'priorities' && (
                <div className="space-y-4">
                  <div className="flex items-center justify-between pt-1">
                    <div className="flex items-center gap-2">
                      <DaywellIconButton
                        label="Go back"
                        tone="muted"
                        onClick={handleBack}
                        icon={<ArrowLeft className="w-5 h-5" />}
                      />
                      <div>
                        <div className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
                          THE ESSENTIAL FEW
                        </div>
                        <h1 className="dw-type-heading text-[var(--dw-text-primary)]">
                          Priorities
                        </h1>
                      </div>
                    </div>
                    <DaywellButton
                      label="Open Tasks"
                      variant="text"
                      size="compact"
                      onClick={() => navigateTo('tasks')}
                    />
                  </div>

                  <DeprecatedPrototypeBanner areaName="Priorities" />

                  <div className="space-y-2.5">
                    {tasks.filter((t) => !t.isArchived).length === 0 ? (
                      <DaywellCard padding="md" radius="xl">
                        <DaywellEmptyState
                          icon={<CheckSquare className="w-8 h-8" />}
                          message="No priority tasks yet"
                          subtitle="Create tasks in the Tasks module to track your daily priorities."
                          actionLabel="Add Task"
                          onActionPressed={() => navigateTo('tasks')}
                        />
                      </DaywellCard>
                    ) : (
                      tasks.filter((t) => !t.isArchived).slice(0, 3).map((item, idx) => (
                        <DaywellCard
                          key={item.id}
                          padding="compact"
                          onClick={() => toggleTask(item.id)}
                          className="flex items-center gap-3"
                        >
                          <div className="w-6 h-6 rounded-[var(--dw-radius-full)] bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] text-xs font-bold flex items-center justify-center shrink-0">
                            {idx + 1}
                          </div>
                          <div className="flex-1 min-w-0">
                            <p className={`text-xs font-bold ${item.completed ? 'line-through text-[var(--dw-text-muted)]' : 'text-[var(--dw-text-primary)]'}`}>
                              {item.title}
                            </p>
                            <p className="text-[10px] text-[var(--dw-text-muted)]">{item.projectName || item.category}</p>
                          </div>
                          <div
                            className={`w-5 h-5 rounded-md border flex items-center justify-center transition-colors ${
                              item.completed
                                ? 'bg-[var(--dw-primary-brand)] border-[var(--dw-primary-brand)] text-white'
                                : 'border-[var(--dw-border)]'
                            }`}
                          >
                            {item.completed && <Check className="w-3.5 h-3.5" />}
                          </div>
                        </DaywellCard>
                      ))
                    )}
                  </div>
                </div>
              )}

              {/* SCREEN: TOOLS (DEPRECATED PROTOTYPE) */}
              {activeScreen === 'tools' && (
                <div className="space-y-4">
                  <div className="flex items-center gap-2 pt-1">
                    <DaywellIconButton
                      label="Go back"
                      tone="muted"
                      onClick={handleBack}
                      icon={<ArrowLeft className="w-5 h-5" />}
                    />
                    <div>
                      <div className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
                        EVERYDAY UTILITIES
                      </div>
                      <h1 className="dw-type-heading text-[var(--dw-text-primary)]">
                        Calculations & tools
                      </h1>
                    </div>
                  </div>

                  <DeprecatedPrototypeBanner areaName="Calculations & Tools" />

                  <div className="space-y-2">
                    <DaywellCard padding="compact" onClick={() => navigateTo('finance')} className="flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        <Wallet className="w-4 h-4 text-[var(--dw-income)]" />
                        <div>
                          <p className="text-xs font-bold text-[var(--dw-text-primary)]">ETB Cents Ledger Calculator</p>
                          <p className="text-[10px] text-[var(--dw-text-muted)]">Open Finance module</p>
                        </div>
                      </div>
                      <ChevronRight className="w-4 h-4 text-[var(--dw-text-muted)]" />
                    </DaywellCard>

                    <DaywellCard padding="compact" onClick={() => navigateTo('calendar')} className="flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        <CalendarDays className="w-4 h-4 text-[var(--dw-info)]" />
                        <div>
                          <p className="text-xs font-bold text-[var(--dw-text-primary)]">Ethiopian & Gregorian Dual Converter</p>
                          <p className="text-[10px] text-[var(--dw-text-muted)]">Open Calendar module</p>
                        </div>
                      </div>
                      <ChevronRight className="w-4 h-4 text-[var(--dw-text-muted)]" />
                    </DaywellCard>

                    <DaywellCard padding="compact" onClick={() => navigateTo('sync_backup')} className="flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        <Download className="w-4 h-4 text-[var(--dw-primary)]" />
                        <div>
                          <p className="text-xs font-bold text-[var(--dw-text-primary)]">Export Canonical Archive</p>
                          <p className="text-[10px] text-[var(--dw-text-muted)]">Open Sync & Backup</p>
                        </div>
                      </div>
                      <ChevronRight className="w-4 h-4 text-[var(--dw-text-muted)]" />
                    </DaywellCard>
                  </div>
                </div>
              )}

              {/* SCREEN: HISTORY (DEPRECATED PROTOTYPE) */}
              {activeScreen === 'history' && (
                <div className="space-y-4">
                  <div className="flex items-center gap-2 pt-1">
                    <DaywellIconButton
                      label="Go back"
                      tone="muted"
                      onClick={handleBack}
                      icon={<ArrowLeft className="w-5 h-5" />}
                    />
                    <div>
                      <div className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
                        JOURNEY & REFLECTION
                      </div>
                      <h1 className="dw-type-heading text-[var(--dw-text-primary)]">
                        History & progress
                      </h1>
                    </div>
                  </div>

                  <DeprecatedPrototypeBanner areaName="History & Progress" />

                  <DaywellCard padding="md" radius="xl" className="space-y-3">
                    <h3 className="text-xs font-bold text-[var(--dw-text-primary)]">Current task snapshot</h3>
                    <div className="grid grid-cols-3 gap-2 text-center pt-1">
                      <div className="p-2.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)]">
                        <span className="text-base font-extrabold text-[var(--dw-primary)] tabular-nums">
                          {tasks.filter((t) => !t.isArchived && t.completed).length}
                        </span>
                        <span className="block text-[9px] text-[var(--dw-text-muted)]">Done</span>
                      </div>
                      <div className="p-2.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)]">
                        <span className="text-base font-extrabold text-[var(--dw-on-info-container)] tabular-nums">
                          {tasks.filter((t) => !t.isArchived && !t.completed && t.status !== 'cancelled').length}
                        </span>
                        <span className="block text-[9px] text-[var(--dw-text-muted)]">Active</span>
                      </div>
                      <div className="p-2.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)]">
                        <span className="text-base font-extrabold text-[var(--dw-on-warning-container)]">100%</span>
                        <span className="block text-[9px] text-[var(--dw-text-muted)]">Offline</span>
                      </div>
                    </div>
                  </DaywellCard>
                </div>
              )}

              {/* SCREEN 13: SYNC & BACKUP */}
              {activeScreen === 'sync_backup' && (
                <div className="space-y-4">
                  <div className="flex items-center justify-between pt-1">
                    <DaywellIconButton
                      label="Go back"
                      tone="muted"
                      onClick={handleBack}
                      icon={<ArrowLeft className="w-5 h-5" />}
                    />
                    <span className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
                      SETTINGS / YOUR DATA
                    </span>
                    <Info className="w-4 h-4 text-[var(--dw-text-muted)]" />
                  </div>

                  <div>
                    <h1 className="dw-type-heading text-[var(--dw-text-primary)]">
                      Sync & backup
                    </h1>
                  </div>

                  {sharedFoundationToast && (
                    <DaywellStatusBanner
                      tone="info"
                      liveRegion
                      message={sharedFoundationToast}
                    />
                  )}

                  {/* Saved on this device Hero Card */}
                  <DaywellCard variant="primaryContainer" padding="md" radius="xl" className="flex items-center gap-3">
                    <div className="w-9 h-9 rounded-[var(--dw-radius-md)] bg-[var(--dw-primary-brand)] text-white flex items-center justify-center shrink-0">
                      <ShieldCheck className="w-5 h-5" />
                    </div>
                    <div>
                      <h4 className="text-xs font-bold text-[var(--dw-on-primary-container)]">
                        Saved on this device
                      </h4>
                      <p className="text-[11px] text-[var(--dw-text-secondary)]">
                        Your work is stored locally on this browser session (Web Preview) or SQLite (Android).
                      </p>
                    </div>
                  </DaywellCard>

                  {/* On This Device (Live Export/Import) */}
                  <div className="space-y-2 pt-1">
                    <DaywellSectionHeader title="On this device" />
                    <p className="text-[11px] text-[var(--dw-text-muted)] leading-relaxed">
                      Export or restore your canonical SharedStateBridge JSON database payload between Web Preview and Android.
                    </p>

                    <div className="space-y-1.5 pt-1">
                      <DaywellCard
                        padding="compact"
                        onClick={handleExportSharedFoundation}
                        className="flex items-center justify-between"
                      >
                        <div className="flex items-center gap-3">
                          <Download className="w-4 h-4 text-[var(--dw-primary)]" />
                          <div>
                            <p className="text-xs font-bold text-[var(--dw-text-primary)]">
                              Create local backup
                            </p>
                            <p className="text-[10px] text-[var(--dw-text-muted)]">
                              Export canonical JSON payload for Android / local backup
                            </p>
                          </div>
                        </div>
                        <ChevronRight className="w-4 h-4 text-[var(--dw-text-muted)]" />
                      </DaywellCard>

                      <label className="block cursor-pointer">
                        <DaywellCard padding="compact" interactive className="flex items-center justify-between">
                          <div className="flex items-center gap-3">
                            <FolderOpen className="w-4 h-4 text-[var(--dw-primary)]" />
                            <div>
                              <p className="text-xs font-bold text-[var(--dw-text-primary)]">
                                Restore from backup
                              </p>
                              <p className="text-[10px] text-[var(--dw-text-muted)]">
                                Load Android / canonical JSON file into Web Preview
                              </p>
                            </div>
                          </div>
                          <ChevronRight className="w-4 h-4 text-[var(--dw-text-muted)]" />
                          <input
                            type="file"
                            accept=".json,.pmbackup"
                            className="hidden"
                            onChange={handleImportSharedFoundation}
                          />
                        </DaywellCard>
                      </label>
                    </div>
                  </div>

                  {/* Shared Foundation Unified Architecture Badge */}
                  <DaywellCard variant="primaryContainer" padding="md" radius="xl" className="space-y-2">
                    <div className="flex items-center justify-between gap-2">
                      <div className="flex items-center gap-2">
                        <Sparkles className="w-4 h-4 text-[var(--dw-on-primary-container)]" />
                        <h4 className="text-xs font-bold text-[var(--dw-on-primary-container)]">
                          Shared Foundation: Single Source of Truth
                        </h4>
                      </div>
                      <DaywellStatusBadge tone="success" showIcon={false} label="Active" />
                    </div>
                    <p className="text-[11px] text-[var(--dw-text-secondary)] leading-relaxed">
                      Web Preview and Flutter Android share canonical design tokens, business rules, financial calculations, and schemas from <code className="text-[10px] bg-[var(--dw-card)] px-1 py-0.5 rounded font-mono">shared_foundation/</code>.
                    </p>
                  </DaywellCard>

                  {/* Deprecated Static Prototype Cards for Future Sync/Telegram */}
                  <div className="space-y-2 pt-1">
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-xs font-bold text-[var(--dw-text-primary)]">Sync & Remote Backup Preview</span>
                      <DaywellStatusBadge
                        tone="warning"
                        showIcon={false}
                        label="Deprecated Prototype"
                      />
                    </div>

                    <DaywellCard padding="md" radius="xl" className="space-y-3">
                      <div className="flex items-center justify-between text-xs">
                        <DaywellStatusBadge
                          tone="neutral"
                          icon={<CloudOff className="w-3 h-3" />}
                          label="Offline"
                        />
                        <span className="text-[var(--dw-text-muted)] font-medium">Prototype status card</span>
                      </div>
                      <p className="text-[11px] text-[var(--dw-text-muted)] leading-relaxed">
                        Cloud sync and Telegram remote destinations are static design mockups in Web Preview. Use Create local backup above for real exports.
                      </p>
                    </DaywellCard>

                    <DaywellCard padding="md" radius="xl" className="space-y-2">
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-2">
                          <Send className="w-4 h-4 text-[var(--dw-primary)]" />
                          <div>
                            <h4 className="text-xs font-bold text-[var(--dw-text-primary)]">
                              Telegram configuration
                            </h4>
                            <p className="text-[10px] text-[var(--dw-text-muted)]">
                              Static prototype only (Android encrypted export runs in native app)
                            </p>
                          </div>
                        </div>
                        <DaywellStatusBadge tone="warning" showIcon={false} label="Mockup" />
                      </div>
                    </DaywellCard>
                  </div>
                </div>
              )}
            </div>

            {/* SCREEN 14: QUICK CAPTURE OVERLAY */}
            {isQuickCaptureOpen && (
              <div
                role="dialog"
                aria-modal="true"
                aria-label="Quick capture"
                className={`absolute inset-0 bg-black/40 backdrop-blur-xs z-50 flex flex-col ${
                  viewMode === 'desktop' ? 'items-center justify-center p-4' : 'justify-end'
                }`}
              >
                <div
                  className={`bg-[var(--dw-elevated)] border border-[var(--dw-border)] p-5 shadow-2xl space-y-4 w-full ${
                    viewMode === 'desktop'
                      ? 'max-w-lg rounded-[var(--dw-radius-xl)]'
                      : 'rounded-t-[32px] border-t'
                  }`}
                >
                  {/* Top Drag Handle & Title */}
                  {viewMode !== 'desktop' && (
                    <div className="w-10 h-1 bg-[var(--dw-border)] rounded-[var(--dw-radius-full)] mx-auto" />
                  )}
                  <div className="flex items-center justify-between pt-1">
                    <h3 className="dw-type-title text-[var(--dw-text-primary)]">Quick capture</h3>
                    <DaywellIconButton
                      label="Close Quick capture"
                      tone="muted"
                      size="compact"
                      onClick={handleAttemptCloseQuickCapture}
                      icon={<X className="w-5 h-5" />}
                    />
                  </div>

                  {/* Type Selector Pills */}
                  <div className="flex flex-wrap items-center gap-2">
                    <button
                      type="button"
                      onClick={() => setQuickCaptureType('task')}
                      className={`text-xs px-3.5 py-1.5 rounded-[var(--dw-radius-full)] font-semibold flex items-center gap-1.5 transition-all cursor-pointer ${
                        quickCaptureType === 'task'
                          ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)]'
                          : 'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-secondary)] border border-transparent'
                      }`}
                    >
                      <CheckSquare className="w-3.5 h-3.5" />
                      Task
                    </button>
                    <button
                      type="button"
                      onClick={() => setQuickCaptureType('idea')}
                      className={`text-xs px-3.5 py-1.5 rounded-[var(--dw-radius-full)] font-semibold flex items-center gap-1.5 transition-all cursor-pointer ${
                        quickCaptureType === 'idea'
                          ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)]'
                          : 'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-secondary)] border border-transparent'
                      }`}
                    >
                      <Sparkles className="w-3.5 h-3.5" />
                      Idea
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setQuickCaptureType('expense');
                        setQuickCaptureInput('450 ETB groceries');
                      }}
                      className={`text-xs px-3.5 py-1.5 rounded-[var(--dw-radius-full)] font-semibold flex items-center gap-1.5 transition-all cursor-pointer ${
                        quickCaptureType === 'expense'
                          ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)]'
                          : 'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-secondary)] border border-transparent'
                      }`}
                    >
                      <Wallet className="w-3.5 h-3.5" />
                      Expense
                    </button>
                    <button
                      type="button"
                      onClick={() => setQuickCaptureType('note')}
                      className={`text-xs px-3.5 py-1.5 rounded-[var(--dw-radius-full)] font-semibold flex items-center gap-1.5 transition-all cursor-pointer ${
                        quickCaptureType === 'note'
                          ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)]'
                          : 'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-secondary)] border border-transparent'
                      }`}
                    >
                      <FileText className="w-3.5 h-3.5" />
                      Note
                    </button>
                    <button
                      type="button"
                      onClick={() => setQuickCaptureType('reminder')}
                      className={`text-xs px-3.5 py-1.5 rounded-[var(--dw-radius-full)] font-semibold flex items-center gap-1.5 transition-all cursor-pointer ${
                        quickCaptureType === 'reminder'
                          ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)]'
                          : 'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-secondary)] border border-transparent'
                      }`}
                    >
                      <Bell className="w-3.5 h-3.5" />
                      Reminder
                    </button>
                  </div>

                  {/* Large Question Input */}
                  <div className="space-y-1">
                    <label
                      htmlFor="quick-capture-input"
                      className="dw-type-caption tracking-wider text-[var(--dw-text-muted)] uppercase"
                    >
                      WHAT'S ON YOUR MIND? <span className="text-[var(--dw-error)]">*</span>
                    </label>
                    <div
                      className={`p-3 bg-[var(--dw-card)] rounded-[var(--dw-radius-lg)] border-2 ${
                        quickCaptureError ? 'border-[var(--dw-error)]' : 'border-[var(--dw-primary)]'
                      } shadow-xs`}
                    >
                      <textarea
                        id="quick-capture-input"
                        rows={2}
                        autoFocus
                        value={quickCaptureInput}
                        onChange={(e) => {
                          setQuickCaptureInput(e.target.value);
                          if (quickCaptureError) setQuickCaptureError(null);
                        }}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' && !e.shiftKey) {
                            e.preventDefault();
                            handleSaveQuickCapture();
                          }
                        }}
                        placeholder="e.g. Ask landlord about move-in time"
                        className="w-full text-sm font-bold text-[var(--dw-text-primary)] bg-transparent outline-none resize-none"
                      />
                    </div>
                    {quickCaptureError && (
                      <DaywellStatusBanner
                        tone="error"
                        message={quickCaptureError}
                        className="mt-2"
                      />
                    )}
                  </div>

                  {/* Primary Save & Expense Composer Handoff */}
                  <div className="flex gap-2">
                    {quickCaptureType === 'expense' && (
                      <DaywellButton
                        label="Open in Composer"
                        variant="outlined"
                        disabled={isSubmittingQuickCapture || !quickCaptureInput.trim()}
                        onClick={() => {
                          const text = quickCaptureInput.trim();
                          if (!text) return;
                          const canonical = SharedStateBridge.loadCanonicalState();
                          const storedAccounts = (canonical.accounts || []) as Account[];
                          const storedCategories = (canonical.categories || []) as TransactionCategory[];
                          const etbAccounts = storedAccounts.filter((a) => isActiveVerifiedEtbAccount(a));
                          const hint = quickCaptureExpenseAccount.trim().toLowerCase();
                          const matchedAccount =
                            etbAccounts.find((a) => a.name.toLowerCase().includes(hint)) ||
                            etbAccounts[0];
                          const parsed = parseQuickCaptureExpense(
                            text,
                            matchedAccount?.id || quickCaptureExpenseAccount,
                            storedAccounts,
                            storedCategories
                          );
                          if (parsed.rejectedCurrency) {
                            setQuickCaptureError(
                              parsed.error ||
                                `Only ETB amounts are supported in Quick Capture (detected ${parsed.rejectedCurrency}).`
                            );
                            return;
                          }
                          const prefillAccountId =
                            etbAccounts.find((a) => a.id === parsed.assetAccountId)?.id ||
                            matchedAccount?.id;
                          const prefillCategoryId = resolveActiveExpenseCategoryIdV7(
                            storedCategories,
                            parsed.categoryId
                          );
                          setFinanceComposerPrefill({
                            nonce: Date.now(),
                            kind: 'expense',
                            amountText: parsed.amountCents > 0 ? formatCentsAsInput(parsed.amountCents) : '',
                            description: parsed.description || text,
                            accountId: prefillAccountId,
                            categoryId: prefillCategoryId,
                          });
                          setIsQuickCaptureOpen(false);
                          setQuickCaptureInput('');
                          setQuickCaptureError(null);
                          navigateTo('finance');
                        }}
                      />
                    )}
                    <DaywellButton
                      label={isSubmittingQuickCapture ? 'Saving...' : 'Save to Inbox'}
                      variant="primary"
                      fullWidth
                      isLoading={isSubmittingQuickCapture}
                      disabled={isSubmittingQuickCapture || !quickCaptureInput.trim()}
                      leadingIcon={!isSubmittingQuickCapture ? <InboxIcon className="w-4 h-4" /> : undefined}
                      onClick={() => handleSaveQuickCapture()}
                    />
                  </div>

                  <p className="text-center text-[10px] text-[var(--dw-text-muted)] pb-1">
                    Capture now. Organize in Inbox later.
                  </p>
                </div>
              </div>
            )}

            {/* Unsaved Changes Protection for Quick Capture */}
            <UnsavedChangesDialog
              isOpen={showUnsavedQuickCapture}
              title="Discard Unsaved Quick Capture?"
              description="You have typed text in Quick Capture that has not been saved yet. Discard changes?"
              onStay={() => setShowUnsavedQuickCapture(false)}
              onDiscard={() => {
                setShowUnsavedQuickCapture(false);
                setIsQuickCaptureOpen(false);
                setQuickCaptureInput('');
                setQuickCaptureError(null);
              }}
            />

            {/* In-App Due Task Reminder Alert Banner */}
            {dueReminderAlerts.length > 0 && (
              <div
                role="alert"
                aria-label="Due task reminder alert"
                className="absolute bottom-20 left-4 right-4 z-50"
              >
                <DaywellCard padding="compact" radius="lg" className="border-[var(--dw-primary)] shadow-lg space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-start gap-2 min-w-0">
                      <Bell className="w-4 h-4 text-[var(--dw-primary)] shrink-0 mt-0.5" />
                      <div className="min-w-0">
                        <div className="text-[10px] font-bold uppercase tracking-wider text-[var(--dw-primary)]">
                          Task Reminder Due
                        </div>
                        <div className="text-xs font-bold text-[var(--dw-text-primary)] truncate">
                          {dueReminderAlerts[0].title}
                        </div>
                        <div className="text-[11px] text-[var(--dw-text-muted)]">
                          {dueReminderAlerts[0].summary}
                          {dueReminderAlerts.length > 1
                            ? ` · +${dueReminderAlerts.length - 1} more`
                            : ''}
                        </div>
                      </div>
                    </div>
                    <DaywellIconButton
                      label="Dismiss reminder alert"
                      size="compact"
                      tone="muted"
                      onClick={() =>
                        setDueReminderAlerts((prev) =>
                          prev.filter((_, idx) => idx !== 0)
                        )
                      }
                      icon={<X className="w-3.5 h-3.5" />}
                    />
                  </div>
                  <div className="flex flex-wrap items-center justify-end gap-1.5">
                    <DaywellButton
                      label="Open Task"
                      variant="outlined"
                      size="compact"
                      onClick={() => {
                        const activeAlert = dueReminderAlerts[0];
                        setDueReminderAlerts((prev) =>
                          prev.filter((item) => item.reminderId !== activeAlert.reminderId)
                        );
                        setTasksSubTab('tasks');
                        navigateTo('tasks');
                        setRequestedTaskFocus({
                          taskId: activeAlert.taskId,
                          openMode: 'details',
                          nonce: Date.now(),
                        });
                      }}
                    />
                    <DaywellButton
                      label="Complete"
                      variant="primary"
                      size="compact"
                      onClick={() => {
                        const activeAlert = dueReminderAlerts[0];
                        toggleTask(activeAlert.taskId);
                        setDueReminderAlerts((prev) =>
                          prev.filter((item) => item.reminderId !== activeAlert.reminderId)
                        );
                      }}
                    />
                  </div>
                </DaywellCard>
              </div>
            )}

            {/* Web Notification Capabilities & Reminder Status Modal */}
            {isNotificationStatusModalOpen && (
              <div
                role="dialog"
                aria-modal="true"
                aria-label="Notifications and reminders"
                className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs"
                onClick={(e) => {
                  if (e.target === e.currentTarget) {
                    setIsNotificationStatusModalOpen(false);
                  }
                }}
              >
                <div className="w-full max-w-md bg-[var(--dw-elevated)] rounded-[var(--dw-radius-xl)] p-5 shadow-2xl border border-[var(--dw-border)] space-y-3.5">
                  <div className="flex items-center justify-between gap-2">
                    <div className="flex items-center gap-2">
                      <Bell className="w-4 h-4 text-[var(--dw-primary)]" />
                      <h2 className="dw-type-title text-[var(--dw-text-primary)]">
                        Notifications & Reminders
                      </h2>
                    </div>
                    <DaywellIconButton
                      label="Close notification status"
                      size="compact"
                      tone="muted"
                      onClick={() => setIsNotificationStatusModalOpen(false)}
                      icon={<X className="w-4 h-4" />}
                    />
                  </div>

                  <div className="p-3 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] space-y-2 text-xs">
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-[var(--dw-text-muted)]">Active task reminders</span>
                      <span className="font-bold text-[var(--dw-text-primary)]">
                        {activeTaskReminderCount}
                      </span>
                    </div>
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-[var(--dw-text-muted)]">Scheduled in-tab timers</span>
                      <span className="font-bold text-[var(--dw-text-primary)]">
                        {taskRemindersService.getActiveScheduledTimerCount()}
                      </span>
                    </div>
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-[var(--dw-text-muted)]">Browser alert permission</span>
                      <DaywellStatusBadge
                        label={
                          notificationSupportStatus.permission === 'granted'
                            ? 'Granted'
                            : notificationSupportStatus.permission === 'denied'
                            ? 'Blocked'
                            : notificationSupportStatus.supported
                            ? 'Not requested'
                            : 'Unavailable'
                        }
                        tone={
                          notificationSupportStatus.permission === 'granted'
                            ? 'success'
                            : notificationSupportStatus.permission === 'denied'
                            ? 'error'
                            : 'neutral'
                        }
                        showIcon={false}
                      />
                    </div>
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-[var(--dw-text-muted)]">Background delivery</span>
                      <span className="font-semibold text-[var(--dw-text-secondary)]">
                        Unsupported in Web Preview
                      </span>
                    </div>
                  </div>

                  <p className="text-xs text-[var(--dw-text-secondary)] leading-relaxed">
                    {notificationSupportStatus.capabilityNote}
                  </p>
                  <p className="text-[11px] text-[var(--dw-text-muted)] leading-relaxed">
                    Daywell task reminders reuse the shared reminder store across Tasks, Projects, Finance commitments, and Android.
                  </p>

                  <div className="flex flex-wrap items-center justify-end gap-2 pt-1">
                    {notificationSupportStatus.supported &&
                      notificationSupportStatus.permission === 'default' && (
                        <DaywellButton
                          label="Allow Browser Alerts"
                          variant="outlined"
                          size="compact"
                          onClick={() => {
                            void (async () => {
                              await taskRemindersService.requestWebNotificationPermission();
                              setNotificationSupportStatus(
                                taskRemindersService.getWebNotificationSupportStatus()
                              );
                            })();
                          }}
                        />
                      )}
                    <DaywellButton
                      label="Open Task Reminders"
                      variant="primary"
                      size="compact"
                      onClick={() => {
                        setIsNotificationStatusModalOpen(false);
                        setTasksSubTab('tasks');
                        navigateTo('tasks');
                      }}
                    />
                  </div>
                </div>
              </div>
            )}

            {/* Toast Notification */}
            {quickCaptureToast && (
              <div
                role="status"
                aria-live="polite"
                className="absolute top-12 left-6 right-6 p-3 bg-[var(--dw-primary-brand)] text-white rounded-[var(--dw-radius-lg)] text-xs font-semibold shadow-lg text-center z-50"
              >
                {quickCaptureToast}
              </div>
            )}

            {/* Fixed Bottom Tab Bar (6 Tabs: Today, To-Do, Calendar, Notes, Finance, More) */}
            <nav
              role="navigation"
              aria-label="Main Navigation"
              className="absolute bottom-0 left-0 right-0 h-16 bg-[var(--dw-card)]/95 backdrop-blur-md border-t border-[var(--dw-border)] px-1 z-40 select-none flex items-center justify-center"
            >
              <div
                className={`w-full grid grid-cols-6 items-center ${
                  viewMode === 'desktop' ? 'max-w-2xl mx-auto' : ''
                }`}
              >
              {[
                { id: 'today' as ScreenId, aria: 'Today Dashboard', label: 'Today', icon: Calendar },
                { id: 'tasks' as ScreenId, aria: 'To-Do Tasks', label: 'To-Do', icon: CheckCircle2 },
                { id: 'calendar' as ScreenId, aria: 'Calendar', label: 'Calendar', icon: CalendarDays },
                { id: 'notes' as ScreenId, aria: 'Notes & Knowledge', label: 'Notes', icon: NotebookPen },
                { id: 'finance' as ScreenId, aria: 'Finance Ledger', label: 'Finance', icon: Wallet },
                { id: 'more' as ScreenId, aria: 'More Areas and Settings', label: 'More', icon: Grid2X2 },
              ].map((tab) => {
                const IconComp = tab.icon;
                const isSelected =
                  tab.id === 'more'
                    ? [
                        'more',
                        'goals',
                        'relationships',
                        'priorities',
                        'tools',
                        'history',
                        'sync_backup',
                      ].includes(activeScreen)
                    : activeScreen === tab.id;
                return (
                  <button
                    key={tab.id}
                    type="button"
                    onClick={() => {
                      if (tab.id === 'tasks' && activeScreen === 'tasks' && selectedProjectId) {
                        setSelectedProjectId(null);
                      } else {
                        navigateTo(tab.id);
                      }
                    }}
                    aria-label={tab.aria}
                    aria-current={isSelected ? 'page' : undefined}
                    className="flex flex-col items-center justify-center min-h-[48px] py-1 group cursor-pointer active:scale-95 transition-transform"
                  >
                    <div
                      className={`px-2 py-1 rounded-[var(--dw-radius-full)] transition-colors ${
                        isSelected
                          ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)]'
                          : 'text-[var(--dw-text-muted)] group-hover:text-[var(--dw-text-primary)]'
                      }`}
                    >
                      <IconComp className="w-4 h-4" />
                    </div>
                    <span
                      className={`text-[9.5px] tracking-tight ${
                        isSelected
                          ? 'font-bold text-[var(--dw-primary)]'
                          : 'font-medium text-[var(--dw-text-muted)] group-hover:text-[var(--dw-text-primary)]'
                      }`}
                    >
                      {tab.label}
                    </span>
                  </button>
                );
              })}
              </div>
            </nav>
          </div>
        </div>
      </main>
    </div>
  );
}
