import {
  confirmDailyRhythmFinanceClose,
  confirmDailyRhythmTaskReview,
  createEmptyDailyRhythmDay,
  DAILY_RHYTHM_MAX_STREAK_FREEZES,
  DAILY_RHYTHM_QUALIFYING_DAYS_PER_FREEZE,
  DailyRhythmDayRecord,
  DailyRhythmDayStatus,
  DailyRhythmEvaluatedDay,
  DailyRhythmFinanceCloseStatus,
  DailyRhythmMutationResult,
  DailyRhythmTaskReviewEvidence,
  DailyRhythmTimelineSummary,
  DailyRhythmTodayOptions,
  resolveDailyRhythmToday,
} from './dailyRhythm';
import {
  findDailyPlanningEntry,
  isTaskPlannedForDate,
} from './dailyPlanningOperations';
import { CalendarDate } from './date';
import { JournalEntry, Posting } from './doubleEntryFinance';
import { SharedDailyPlanningEntry } from './sharedFoundation';
import {
  DaywellTaskRecord,
  isTaskCompleted,
  resolveEffectiveTaskStatus,
  TaskPriority,
} from './taskOperations';

const PRIORITY_RANK: Record<TaskPriority, number> = {
  urgent: 0,
  high: 1,
  medium: 2,
  low: 3,
};

export interface DailyRhythmTaskReviewSnapshot {
  targetDateIso: string;
  todayIso: string;
  evidence: DailyRhythmTaskReviewEvidence;
  overdueTasks: DaywellTaskRecord[];
  todayTasks: DaywellTaskRecord[];
  plannedTasks: DaywellTaskRecord[];
  attentionTasks: DaywellTaskRecord[];
  completedTodayTasks: DaywellTaskRecord[];
  hasRelevantTasks: boolean;
  confirmActionLabel: string;
}

export interface DailyRhythmFinanceDaySummary {
  targetDateIso: string;
  transactionCount: number;
  todayEntries: JournalEntry[];
  hasTransactions: boolean;
  confirmActionLabel: string;
}

function resolveTargetDateIso(
  targetDateIso?: string,
  todayOptions?: DailyRhythmTodayOptions
): { targetIso: string; todayIso: string } {
  const todayIso = resolveDailyRhythmToday(todayOptions).toIsoString();
  if (targetDateIso !== undefined) {
    const parsed = CalendarDate.tryParse(targetDateIso);
    if (parsed) {
      return { targetIso: parsed.toIsoString(), todayIso };
    }
  }
  return { targetIso: todayIso, todayIso };
}

function isTaskCompletedOnDate(
  task: DaywellTaskRecord,
  planningEntries: readonly SharedDailyPlanningEntry[],
  targetIso: string
): boolean {
  if (!isTaskCompleted(task)) return false;
  if (task.completedAt) {
    const parsedMs = Date.parse(task.completedAt);
    if (Number.isFinite(parsedMs)) {
      const completedDate = CalendarDate.fromUtcInstantInEthiopia(
        new Date(parsedMs)
      ).toIsoString();
      if (completedDate === targetIso) return true;
    }
  }
  const entry = findDailyPlanningEntry(planningEntries, task.id, targetIso);
  return entry?.action === 'completed';
}

function compareAttentionTasks(
  a: DaywellTaskRecord,
  b: DaywellTaskRecord,
  targetIso: string,
  plannedIds: ReadonlySet<string>
): number {
  const overdueA = Boolean(a.dueDate && a.dueDate < targetIso) ? 0 : 1;
  const overdueB = Boolean(b.dueDate && b.dueDate < targetIso) ? 0 : 1;
  if (overdueA !== overdueB) return overdueA - overdueB;

  const plannedA = plannedIds.has(a.id) ? 0 : 1;
  const plannedB = plannedIds.has(b.id) ? 0 : 1;
  if (plannedA !== plannedB) return plannedA - plannedB;

  const prioA = PRIORITY_RANK[a.priority] ?? 2;
  const prioB = PRIORITY_RANK[b.priority] ?? 2;
  if (prioA !== prioB) return prioA - prioB;

  const dueA = a.dueDate ?? '9999-12-31';
  const dueB = b.dueDate ?? '9999-12-31';
  if (dueA !== dueB) return dueA.localeCompare(dueB);

  return a.title.localeCompare(b.title);
}

/**
 * Computes the Daily Rhythm task review snapshot & canonical evidence counts
 * from authoritative Tasks and My Day planning records without mutating tasks.
 */
export function buildDailyRhythmTaskReviewSnapshot(params: {
  tasks: readonly DaywellTaskRecord[];
  dailyPlanningEntries: readonly SharedDailyPlanningEntry[];
  targetDateIso?: string;
} & DailyRhythmTodayOptions): DailyRhythmTaskReviewSnapshot {
  const { targetIso, todayIso } = resolveTargetDateIso(
    params.targetDateIso,
    params
  );

  const overdueTasks: DaywellTaskRecord[] = [];
  const todayTasks: DaywellTaskRecord[] = [];
  const plannedTasks: DaywellTaskRecord[] = [];
  const completedTodayTasks: DaywellTaskRecord[] = [];

  for (const task of params.tasks) {
    if (task.isArchived) continue;
    const status = resolveEffectiveTaskStatus(task);
    if (status === 'cancelled') continue;
    if (status === 'completed') {
      if (isTaskCompletedOnDate(task, params.dailyPlanningEntries, targetIso)) {
        completedTodayTasks.push(task);
      }
      continue;
    }

    if (task.dueDate && task.dueDate < targetIso) {
      overdueTasks.push(task);
    }
    if (task.dueDate === targetIso || task.scheduledDate === targetIso) {
      todayTasks.push(task);
    }
    if (
      isTaskPlannedForDate(
        task,
        params.dailyPlanningEntries,
        targetIso,
        todayIso
      )
    ) {
      plannedTasks.push(task);
    }
  }

  const plannedIds = new Set(plannedTasks.map((t) => t.id));
  const seenAttention = new Set<string>();
  const attentionTasks: DaywellTaskRecord[] = [];
  for (const list of [overdueTasks, plannedTasks, todayTasks]) {
    for (const task of list) {
      if (!seenAttention.has(task.id)) {
        seenAttention.add(task.id);
        attentionTasks.push(task);
      }
    }
  }
  attentionTasks.sort((a, b) =>
    compareAttentionTasks(a, b, targetIso, plannedIds)
  );

  const hasRelevantTasks = attentionTasks.length > 0;

  return {
    targetDateIso: targetIso,
    todayIso,
    evidence: {
      overdueCount: overdueTasks.length,
      todayCount: todayTasks.length,
      plannedCount: plannedTasks.length,
      completedTodayCount: completedTodayTasks.length,
    },
    overdueTasks,
    todayTasks,
    plannedTasks,
    attentionTasks,
    completedTodayTasks,
    hasRelevantTasks,
    confirmActionLabel: hasRelevantTasks
      ? 'Confirm daily review'
      : 'Confirm clear day',
  };
}

/**
 * Pure convenience helper that computes task review evidence from current
 * Tasks + My Day state and confirms the Daily Rhythm task review.
 */
export function confirmDailyRhythmTaskReviewFromState(params: {
  record?: DailyRhythmDayRecord | null;
  tasks: readonly DaywellTaskRecord[];
  dailyPlanningEntries: readonly SharedDailyPlanningEntry[];
  dateIso?: string;
  nowIso?: string;
} & DailyRhythmTodayOptions): {
  snapshot: DailyRhythmTaskReviewSnapshot;
  mutation: DailyRhythmMutationResult;
} {
  const snapshot = buildDailyRhythmTaskReviewSnapshot({
    tasks: params.tasks,
    dailyPlanningEntries: params.dailyPlanningEntries,
    targetDateIso: params.dateIso,
    todayIso: params.todayIso,
    today: params.today,
    todayInstant: params.todayInstant,
  });
  const mutation = confirmDailyRhythmTaskReview({
    record: params.record,
    dateIso: snapshot.targetDateIso,
    evidence: snapshot.evidence,
    nowIso: params.nowIso,
    todayIso: params.todayIso,
    today: params.today,
    todayInstant: params.todayInstant,
  });
  return { snapshot, mutation };
}

/**
 * Summarizes non-voided Finance ledger entries occurring on `targetDateIso`.
 */
export function inspectDailyRhythmFinanceDay(params: {
  entries: readonly JournalEntry[];
  targetDateIso?: string;
} & DailyRhythmTodayOptions): DailyRhythmFinanceDaySummary {
  const { targetIso } = resolveTargetDateIso(params.targetDateIso, params);
  const todayEntries = params.entries.filter(
    (entry) => !entry.isVoided && entry.occurrenceDate === targetIso
  );
  const transactionCount = todayEntries.length;
  const hasTransactions = transactionCount > 0;
  return {
    targetDateIso: targetIso,
    transactionCount,
    todayEntries,
    hasTransactions,
    confirmActionLabel: hasTransactions
      ? "I've reviewed today's transactions"
      : 'No transactions today',
  };
}

export function confirmDailyRhythmFinanceCloseFromState(params: {
  record?: DailyRhythmDayRecord | null;
  entries: readonly JournalEntry[];
  dateIso?: string;
  nowIso?: string;
} & DailyRhythmTodayOptions): {
  summary: DailyRhythmFinanceDaySummary;
  mutation: DailyRhythmMutationResult;
} {
  const summary = inspectDailyRhythmFinanceDay({
    entries: params.entries,
    targetDateIso: params.dateIso,
    todayIso: params.todayIso,
    today: params.today,
    todayInstant: params.todayInstant,
  });
  const mutation = confirmDailyRhythmFinanceClose({
    record: params.record ?? createEmptyDailyRhythmDay(summary.targetDateIso),
    dateIso: summary.targetDateIso,
    hasTransactions: summary.hasTransactions,
    nowIso: params.nowIso,
    todayIso: params.todayIso,
    today: params.today,
    todayInstant: params.todayInstant,
  });
  return { summary, mutation };
}

function buildDateLedgerSignatureList(
  entries: readonly JournalEntry[],
  postings: readonly Posting[],
  targetIso: string
): string[] {
  const postingsByEntry = new Map<string, Posting[]>();
  const affectedEntryIds = new Set<string>();

  for (const p of postings) {
    const bucket = postingsByEntry.get(p.entryId) ?? [];
    bucket.push(p);
    postingsByEntry.set(p.entryId, bucket);
    if (p.accountMovementDate === targetIso) {
      affectedEntryIds.add(p.entryId);
    }
  }

  for (const e of entries) {
    if (e.occurrenceDate === targetIso) {
      affectedEntryIds.add(e.id);
    }
  }

  const signatures: string[] = [];
  for (const entry of entries) {
    if (!affectedEntryIds.has(entry.id)) continue;
    const entryPostings = (postingsByEntry.get(entry.id) ?? [])
      .map((p) =>
        [
          p.id,
          p.accountId,
          p.direction,
          String(p.amountCents),
          p.categoryId ?? '',
          p.accountMovementDate,
        ].join('|')
      )
      .sort()
      .join(';');
    signatures.push(
      [
        entry.id,
        entry.entryType,
        entry.isVoided ? '1' : '0',
        entry.occurrenceDate,
        entry.description,
        entry.correctedFromEntryId ?? '',
        entryPostings,
      ].join('::')
    );
  }
  signatures.sort();
  return signatures;
}

/**
 * Returns true strictly when a Finance ledger mutation added, removed,
 * voided, unvoided, replaced, or modified an entry/posting touching `targetDateIso`.
 * Historical edits strictly on earlier dates return false.
 */
export function didFinanceLedgerChangeAffectDate(params: {
  prevEntries: readonly JournalEntry[];
  prevPostings: readonly Posting[];
  nextEntries: readonly JournalEntry[];
  nextPostings: readonly Posting[];
  targetDateIso?: string;
} & DailyRhythmTodayOptions): boolean {
  const { targetIso } = resolveTargetDateIso(params.targetDateIso, params);
  const prevSigs = buildDateLedgerSignatureList(
    params.prevEntries,
    params.prevPostings,
    targetIso
  );
  const nextSigs = buildDateLedgerSignatureList(
    params.nextEntries,
    params.nextPostings,
    targetIso
  );
  if (prevSigs.length !== nextSigs.length) return true;
  for (let i = 0; i < prevSigs.length; i += 1) {
    if (prevSigs[i] !== nextSigs[i]) return true;
  }
  return false;
}

export type DailyRhythmResponsibility = 'faith' | 'tasks' | 'finance';
export type DailyRhythmFaithStep = 'bibleStudy' | 'prayer';
export type DailyRhythmCalendarDisplayStatus =
  | DailyRhythmDayStatus
  | 'unrecorded';

export const DAILY_RHYTHM_FREEZE_RULES: readonly string[] = [
  'A freeze protects one isolated missed day between qualifying days.',
  'A protected day preserves streak continuity but does not count as a qualifying day.',
  'Multiple consecutive missed days cannot be protected.',
  'Incomplete responsibilities today do not mean today has already been missed.',
  'Provisional freeze protection finalizes only if today qualifies; otherwise the day reverts to missed.',
];

export interface DailyRhythmDashboardOverview {
  todayIso: string;
  todayEthiopianIso: string;
  todayStatus: DailyRhythmDayStatus;
  todayRecord: DailyRhythmDayRecord;
  completedResponsibilities: number;
  totalResponsibilities: number;
  progressPercent: number;
  isDayQualified: boolean;
  isTodayInProgress: boolean;
  overallStatusLabel: string;
  overallStatusDescription: string;
  nextIncompleteResponsibility: DailyRhythmResponsibility | null;
  nextActionTitle: string;
  nextActionDescription: string;
  nextActionButtonLabel: string;

  // Faith
  faithComplete: boolean;
  faithCompletedCount: number;
  faithProgressLabel: string;
  bibleStudyDone: boolean;
  prayerDone: boolean;
  nextFaithStep: DailyRhythmFaithStep | null;
  faithStatusLabel: string;
  faithActionLabel: string;

  // Tasks
  tasksComplete: boolean;
  tasksStatusLabel: string;
  tasksContextLabel: string;
  tasksActionLabel: string;
  tasksOverdueCount: number;
  tasksTodayCount: number;
  tasksPlannedCount: number;
  tasksCompletedTodayCount: number;

  // Finance
  financeComplete: boolean;
  financeCloseStatus: DailyRhythmFinanceCloseStatus;
  financeNeedsReconfirmation: boolean;
  financeTodayTransactionCount: number;
  financeStatusLabel: string;
  financeContextLabel: string;
  financeActionLabel: string;

  // Streaks & freezes
  currentStreak: number;
  bestStreak: number;
  totalQualifyingDays: number;
  availableFreezes: number;
  maxFreezes: number;
  qualifyingDaysPerFreeze: number;
  daysTowardNextFreeze: number;
  daysUntilNextFreeze: number;
  nextFreezeProgressPercent: number;
  provisionalFreezeActive: boolean;
  provisionalFreezeDateIso?: string;
  finalizedFreezesUsed: number;
  freezeStatusSummary: string;
  freezeRules: readonly string[];
}

export interface DailyRhythmCalendarDayInspection {
  dateIso: string;
  ethiopianDateIso: string;
  isToday: boolean;
  isFuture: boolean;
  isBeforeTrackingStart: boolean;
  hasRecordedHistory: boolean;
  calendarStatus: DailyRhythmCalendarDisplayStatus;
  isProvisionalFreeze: boolean;
  shortMarkerGlyph: string;
  statusLabel: string;
  accessibleLabel: string;
  detailSummary: string;
  completedResponsibilities: number;
  faithComplete: boolean;
  bibleStudyDone: boolean;
  bibleStudyCompletedAt?: string;
  prayerDone: boolean;
  prayerCompletedAt?: string;
  tasksComplete: boolean;
  taskReviewConfirmed: boolean;
  taskReviewedAt?: string;
  taskReviewEvidence?: DailyRhythmTaskReviewEvidence;
  financeComplete: boolean;
  financeCloseStatus: DailyRhythmFinanceCloseStatus;
  financeClosedAt?: string;
  financeStatusLabel: string;
  freezeExplanation?: string;
  lockNotice?: string;
}

export function formatDailyRhythmFinanceCloseLabel(
  status: DailyRhythmFinanceCloseStatus
): string {
  switch (status) {
    case 'closed_with_transactions':
      return 'Reviewed transactions';
    case 'closed_no_transactions':
      return 'Confirmed no transactions';
    case 'needs_reconfirmation':
      return 'Needs reconfirmation';
    case 'open':
    default:
      return 'Unreviewed today';
  }
}

export function buildDailyRhythmDashboardOverview(params: {
  timelineSummary: DailyRhythmTimelineSummary;
  taskSnapshot: DailyRhythmTaskReviewSnapshot;
  financeSummary: DailyRhythmFinanceDaySummary;
}): DailyRhythmDashboardOverview {
  const { timelineSummary, taskSnapshot, financeSummary } = params;
  const todayRecord = timelineSummary.todayRecord;
  const completed = timelineSummary.todayCompletedResponsibilities;
  const isQualified = timelineSummary.todayStatus === 'complete';

  const faithCompletedCount =
    (todayRecord.bibleStudyDone ? 1 : 0) + (todayRecord.prayerDone ? 1 : 0);
  const nextFaithStep: DailyRhythmFaithStep | null = !todayRecord.bibleStudyDone
    ? 'bibleStudy'
    : !todayRecord.prayerDone
    ? 'prayer'
    : null;

  const faithStatusLabel = timelineSummary.todayFaithComplete
    ? '2/2 Complete'
    : `${faithCompletedCount}/2 complete`;
  const faithActionLabel =
    nextFaithStep === 'bibleStudy'
      ? 'Complete Bible study'
      : nextFaithStep === 'prayer'
      ? 'Complete prayer'
      : 'Open Faith';

  const ev = taskSnapshot.evidence;
  const tasksStatusLabel = timelineSummary.todayTasksComplete
    ? 'Daily review confirmed'
    : 'Needs daily review';
  const tasksContextParts: string[] = [];
  if (ev.overdueCount > 0) tasksContextParts.push(`${ev.overdueCount} overdue`);
  if (ev.todayCount > 0) tasksContextParts.push(`${ev.todayCount} due/scheduled`);
  if (ev.plannedCount > 0) tasksContextParts.push(`${ev.plannedCount} My Day`);
  const tasksContextLabel =
    tasksContextParts.length > 0
      ? tasksContextParts.join(' · ')
      : ev.completedTodayCount > 0
      ? `${ev.completedTodayCount} completed today`
      : 'Clear day · no urgent tasks';
  const tasksActionLabel = timelineSummary.todayTasksComplete
    ? 'View review'
    : 'Open daily review';

  const financeNeedsReconfirmation =
    todayRecord.financeCloseStatus === 'needs_reconfirmation';
  const financeStatusLabel = formatDailyRhythmFinanceCloseLabel(
    todayRecord.financeCloseStatus
  );
  const financeContextLabel = financeSummary.hasTransactions
    ? `${financeSummary.transactionCount} active entry(s) today`
    : 'No active transactions today';
  const financeActionLabel = financeNeedsReconfirmation
    ? 'Reconfirm review'
    : timelineSummary.todayFinanceComplete
    ? 'View Finance'
    : 'Review & close';

  const nextIncompleteResponsibility: DailyRhythmResponsibility | null =
    !timelineSummary.todayFaithComplete
      ? 'faith'
      : !timelineSummary.todayTasksComplete
      ? 'tasks'
      : !timelineSummary.todayFinanceComplete
      ? 'finance'
      : null;

  let overallStatusLabel: string;
  let overallStatusDescription: string;
  if (isQualified) {
    overallStatusLabel = 'Day qualified · 3/3';
    overallStatusDescription =
      'All three daily responsibilities are complete for today.';
  } else if (financeNeedsReconfirmation) {
    overallStatusLabel = `Needs reconfirmation · ${completed}/3`;
    overallStatusDescription =
      "Today's Finance ledger changed after closing. Reconfirm Finance alongside your remaining checks; partial progress does not qualify today yet.";
  } else if (completed > 0 || todayRecord.bibleStudyDone || todayRecord.prayerDone) {
    overallStatusLabel = `In progress · ${completed}/3`;
    overallStatusDescription =
      'Partial progress is saved. Complete all three responsibilities for today to qualify.';
  } else {
    overallStatusLabel = 'Open · 0/3';
    overallStatusDescription =
      'Today is open and still in progress — incomplete steps do not mean today has been missed.';
  }

  let nextActionTitle: string;
  let nextActionDescription: string;
  let nextActionButtonLabel: string;
  if (nextIncompleteResponsibility === 'faith') {
    nextActionTitle =
      nextFaithStep === 'bibleStudy'
        ? 'Next: Bible study'
        : 'Next: Prayer';
    nextActionDescription =
      faithCompletedCount === 1
        ? 'One Faith step left so Faith counts toward today (2/2).'
        : 'Complete Bible study and prayer independently to qualify Faith.';
    nextActionButtonLabel = faithActionLabel;
  } else if (nextIncompleteResponsibility === 'tasks') {
    nextActionTitle = 'Next: Daily task review';
    nextActionDescription = `${tasksContextLabel}. Confirm your review in Tasks without needing to finish every task.`;
    nextActionButtonLabel = tasksActionLabel;
  } else if (nextIncompleteResponsibility === 'finance') {
    nextActionTitle = financeNeedsReconfirmation
      ? 'Next: Reconfirm Finance close'
      : 'Next: Daily Finance review';
    nextActionDescription = financeNeedsReconfirmation
      ? "Today's transactions changed after closing. Reconfirm in Finance."
      : `${financeContextLabel}. Explicit confirmation closes Finance for today.`;
    nextActionButtonLabel = financeActionLabel;
  } else {
    nextActionTitle = 'Today is complete';
    nextActionDescription =
      'Faith, Daily Task Review, and Daily Finance Close are all confirmed for today.';
    nextActionButtonLabel = 'Review history';
  }

  const provisionalDay = timelineSummary.days.find(
    (d) => d.status === 'freeze_protected' && d.isProvisionalFreeze
  );
  const finalizedFreezesUsed = timelineSummary.days.filter(
    (d) => d.status === 'freeze_protected' && !d.isProvisionalFreeze
  ).length;

  const freezeStatusSummary = timelineSummary.provisionalFreezeActive
    ? `Provisional freeze active on ${
        provisionalDay?.dateIso ?? 'yesterday'
      }: your streak stays intact while today is in progress. Qualify today to finalize that spent freeze, or it becomes missed tomorrow.`
    : timelineSummary.availableFreezes > 0
    ? `${timelineSummary.availableFreezes} freeze(s) ready (max ${DAILY_RHYTHM_MAX_STREAK_FREEZES}). Earn 1 every ${DAILY_RHYTHM_QUALIFYING_DAYS_PER_FREEZE} qualifying days (${timelineSummary.daysTowardNextFreeze}/${DAILY_RHYTHM_QUALIFYING_DAYS_PER_FREEZE} toward next).`
    : finalizedFreezesUsed > 0
    ? `0 freezes available (${finalizedFreezesUsed} spent on past single-day gaps). ${timelineSummary.daysTowardNextFreeze}/${DAILY_RHYTHM_QUALIFYING_DAYS_PER_FREEZE} qualifying days toward your next freeze.`
    : `${timelineSummary.daysTowardNextFreeze}/${DAILY_RHYTHM_QUALIFYING_DAYS_PER_FREEZE} qualifying days toward your first freeze (max ${DAILY_RHYTHM_MAX_STREAK_FREEZES}).`;

  return {
    todayIso: timelineSummary.todayIso,
    todayEthiopianIso: timelineSummary.todayEthiopianIso,
    todayStatus: timelineSummary.todayStatus,
    todayRecord,
    completedResponsibilities: completed,
    totalResponsibilities: 3,
    progressPercent: Math.round((completed / 3) * 100),
    isDayQualified: isQualified,
    isTodayInProgress: timelineSummary.isTodayInProgress,
    overallStatusLabel,
    overallStatusDescription,
    nextIncompleteResponsibility,
    nextActionTitle,
    nextActionDescription,
    nextActionButtonLabel,
    faithComplete: timelineSummary.todayFaithComplete,
    faithCompletedCount,
    faithProgressLabel: `${faithCompletedCount}/2`,
    bibleStudyDone: todayRecord.bibleStudyDone,
    prayerDone: todayRecord.prayerDone,
    nextFaithStep,
    faithStatusLabel,
    faithActionLabel,
    tasksComplete: timelineSummary.todayTasksComplete,
    tasksStatusLabel,
    tasksContextLabel,
    tasksActionLabel,
    tasksOverdueCount: ev.overdueCount,
    tasksTodayCount: ev.todayCount,
    tasksPlannedCount: ev.plannedCount,
    tasksCompletedTodayCount: ev.completedTodayCount,
    financeComplete: timelineSummary.todayFinanceComplete,
    financeCloseStatus: todayRecord.financeCloseStatus,
    financeNeedsReconfirmation,
    financeTodayTransactionCount: financeSummary.transactionCount,
    financeStatusLabel,
    financeContextLabel,
    financeActionLabel,
    currentStreak: timelineSummary.currentStreak,
    bestStreak: timelineSummary.bestStreak,
    totalQualifyingDays: timelineSummary.totalQualifyingDays,
    availableFreezes: timelineSummary.availableFreezes,
    maxFreezes: DAILY_RHYTHM_MAX_STREAK_FREEZES,
    qualifyingDaysPerFreeze: DAILY_RHYTHM_QUALIFYING_DAYS_PER_FREEZE,
    daysTowardNextFreeze: timelineSummary.daysTowardNextFreeze,
    daysUntilNextFreeze: timelineSummary.daysUntilNextFreeze,
    nextFreezeProgressPercent: Math.round(
      (timelineSummary.daysTowardNextFreeze /
        DAILY_RHYTHM_QUALIFYING_DAYS_PER_FREEZE) *
        100
    ),
    provisionalFreezeActive: timelineSummary.provisionalFreezeActive,
    provisionalFreezeDateIso: provisionalDay?.dateIso,
    finalizedFreezesUsed,
    freezeStatusSummary,
    freezeRules: DAILY_RHYTHM_FREEZE_RULES,
  };
}

export function describeDailyRhythmCalendarDay(params: {
  dateIso: string;
  timelineSummary: DailyRhythmTimelineSummary;
}): DailyRhythmCalendarDayInspection {
  const parsed = CalendarDate.tryParse(params.dateIso);
  const dateIso = parsed?.toIsoString() ?? params.dateIso;
  const ethDate = parsed?.toEthiopian();
  const ethiopianDateIso = ethDate
    ? `${ethDate.year}-${String(ethDate.month).padStart(2, '0')}-${String(
        ethDate.day
      ).padStart(2, '0')}`
    : '';
  const summary = params.timelineSummary;
  const evaluated: DailyRhythmEvaluatedDay | undefined =
    summary.byDate[dateIso];
  const isToday = dateIso === summary.todayIso;
  const isFuture = dateIso > summary.todayIso;
  const isBeforeTrackingStart =
    !isToday &&
    !isFuture &&
    (summary.startDateIso === undefined || dateIso < summary.startDateIso);

  if (!evaluated) {
    const empty = createEmptyDailyRhythmDay(dateIso);
    const detailSummary = isFuture
      ? 'Future date — Daily Rhythm check-ins open when this day arrives.'
      : summary.startDateIso
      ? `No Daily Rhythm activity recorded prior to ${summary.startDateIso}.`
      : 'No Daily Rhythm history recorded yet.';
    return {
      dateIso,
      ethiopianDateIso,
      isToday,
      isFuture,
      isBeforeTrackingStart,
      hasRecordedHistory: false,
      calendarStatus: 'unrecorded',
      isProvisionalFreeze: false,
      shortMarkerGlyph: '',
      statusLabel: isFuture ? 'Upcoming' : 'No record',
      accessibleLabel: isFuture
        ? `${dateIso}: Upcoming date, no Daily Rhythm record`
        : `${dateIso}: No Daily Rhythm record`,
      detailSummary,
      completedResponsibilities: 0,
      faithComplete: false,
      bibleStudyDone: false,
      prayerDone: false,
      tasksComplete: false,
      taskReviewConfirmed: false,
      financeComplete: false,
      financeCloseStatus: empty.financeCloseStatus,
      financeStatusLabel: 'No record',
      lockNotice: isFuture
        ? 'Future dates are locked and cannot be checked in early.'
        : 'Historical dates without records remain empty and are never fabricated.',
    };
  }

  const rec = evaluated.record;
  let shortMarkerGlyph = '·';
  let statusLabel = 'Open';
  let detailSummary =
    'Today is still in progress. Complete Faith, Tasks, and Finance to qualify.';
  let freezeExplanation: string | undefined;

  switch (evaluated.status) {
    case 'complete':
      shortMarkerGlyph = '✓';
      statusLabel = 'Complete · Qualified';
      detailSummary =
        'All three responsibilities qualified on this day (3/3).';
      break;
    case 'freeze_protected':
      if (evaluated.isProvisionalFreeze) {
        shortMarkerGlyph = '❄?';
        statusLabel = 'Freeze protected (provisional)';
        detailSummary =
          'Missed day provisionally protected by a streak freeze while today is still in progress.';
        freezeExplanation =
          'Provisional freeze: does not count as a qualifying day. Complete all 3 today to finalize this spent freeze, or this day becomes missed tomorrow.';
      } else {
        shortMarkerGlyph = '❄';
        statusLabel = 'Freeze protected (finalized)';
        detailSummary =
          'Missed day protected by a finalized spent streak freeze between qualifying days.';
        freezeExplanation =
          'Finalized spent freeze: preserved streak continuity without counting as a qualifying day.';
      }
      break;
    case 'partial':
      shortMarkerGlyph = '◐';
      statusLabel = isToday
        ? `In progress · ${evaluated.completedResponsibilities}/3`
        : `Partial · ${evaluated.completedResponsibilities}/3`;
      detailSummary = isToday
        ? 'Today has partial progress; complete all three responsibilities to qualify.'
        : 'Partial check-in recorded; day did not reach all three qualifying responsibilities.';
      break;
    case 'missed':
      shortMarkerGlyph = '✕';
      statusLabel = 'Missed';
      detailSummary =
        'Did not qualify (requires Faith 2/2, Task review, and Finance close) and was not freeze-protected.';
      break;
    case 'untouched':
    default:
      shortMarkerGlyph = isToday ? '·' : '✕';
      statusLabel = isToday ? 'Open today · 0/3' : 'Untouched';
      detailSummary = isToday
        ? 'Today has not started yet and has not been missed.'
        : 'No responsibilities completed on this date.';
      break;
  }

  const financeStatusLabel = formatDailyRhythmFinanceCloseLabel(
    rec.financeCloseStatus
  );

  return {
    dateIso,
    ethiopianDateIso,
    isToday,
    isFuture,
    isBeforeTrackingStart: false,
    hasRecordedHistory: true,
    calendarStatus: evaluated.status,
    isProvisionalFreeze: evaluated.isProvisionalFreeze,
    shortMarkerGlyph,
    statusLabel,
    accessibleLabel: `${dateIso}: Daily Rhythm ${statusLabel}`,
    detailSummary,
    completedResponsibilities: evaluated.completedResponsibilities,
    faithComplete: evaluated.faithComplete,
    bibleStudyDone: rec.bibleStudyDone,
    bibleStudyCompletedAt: rec.bibleStudyCompletedAt,
    prayerDone: rec.prayerDone,
    prayerCompletedAt: rec.prayerCompletedAt,
    tasksComplete: evaluated.tasksComplete,
    taskReviewConfirmed: rec.taskReviewConfirmed,
    taskReviewedAt: rec.taskReviewedAt,
    taskReviewEvidence: rec.taskReviewEvidence,
    financeComplete: evaluated.financeComplete,
    financeCloseStatus: rec.financeCloseStatus,
    financeClosedAt: rec.financeClosedAt,
    financeStatusLabel,
    freezeExplanation,
    lockNotice: !isToday
      ? 'Past Daily Rhythm history is read-only and locked.'
      : undefined,
  };
}

