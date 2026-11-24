import {
  confirmDailyRhythmFinanceClose,
  confirmDailyRhythmTaskReview,
  createEmptyDailyRhythmDay,
  DailyRhythmDayRecord,
  DailyRhythmMutationResult,
  DailyRhythmTaskReviewEvidence,
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
    ...params,
  });
  const mutation = confirmDailyRhythmTaskReview({
    record: params.record,
    dateIso: snapshot.targetDateIso,
    evidence: snapshot.evidence,
    nowIso: params.nowIso,
    ...params,
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
    ...params,
  });
  const mutation = confirmDailyRhythmFinanceClose({
    record: params.record ?? createEmptyDailyRhythmDay(summary.targetDateIso),
    dateIso: summary.targetDateIso,
    hasTransactions: summary.hasTransactions,
    nowIso: params.nowIso,
    ...params,
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
