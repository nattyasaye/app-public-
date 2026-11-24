import {
  applyDailyRhythmFinanceLedgerChange,
  confirmDailyRhythmFinanceClose,
  confirmDailyRhythmTaskReview,
  createEmptyDailyRhythmDay,
  DailyRhythmDayRecord,
  DailyRhythmMutationResult,
  DailyRhythmTodayOptions,
  resolveDailyRhythmToday,
  updateDailyRhythmFaith,
} from '../domain/dailyRhythm';
import {
  buildDailyRhythmTaskReviewSnapshot,
  DailyRhythmFinanceDaySummary,
  DailyRhythmTaskReviewSnapshot,
  didFinanceLedgerChangeAffectDate,
  inspectDailyRhythmFinanceDay,
} from '../domain/dailyRhythmWorkflows';
import { JournalEntry, Posting } from '../domain/doubleEntryFinance';
import { SharedDailyPlanningEntry } from '../domain/sharedFoundation';
import { DaywellTaskRecord } from '../domain/taskOperations';
import { dailyRhythmService } from './dailyRhythmService';

export const dailyRhythmWorkflowService = {
  getDayOrEmpty(
    dateIso?: string,
    todayOptions?: DailyRhythmTodayOptions
  ): DailyRhythmDayRecord {
    const targetIso =
      dateIso ?? resolveDailyRhythmToday(todayOptions).toIsoString();
    return (
      dailyRhythmService.getDay(targetIso) ?? createEmptyDailyRhythmDay(targetIso)
    );
  },

  updateFaith(params: {
    dateIso?: string;
    bibleStudyDone?: boolean;
    prayerDone?: boolean;
    nowIso?: string;
  } & DailyRhythmTodayOptions): DailyRhythmMutationResult {
    const targetIso =
      params.dateIso ?? resolveDailyRhythmToday(params).toIsoString();
    const existing = dailyRhythmService.getDay(targetIso);
    const result = updateDailyRhythmFaith({
      record: existing,
      dateIso: targetIso,
      bibleStudyDone: params.bibleStudyDone,
      prayerDone: params.prayerDone,
      nowIso: params.nowIso,
      todayIso: params.todayIso,
      today: params.today,
      todayInstant: params.todayInstant,
    });
    if (result.applied) {
      dailyRhythmService.upsertDay(result.record);
    }
    return result;
  },

  confirmTaskReview(params: {
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
    const existing = dailyRhythmService.getDay(snapshot.targetDateIso);
    const mutation = confirmDailyRhythmTaskReview({
      record: existing,
      dateIso: snapshot.targetDateIso,
      evidence: snapshot.evidence,
      nowIso: params.nowIso,
      todayIso: params.todayIso,
      today: params.today,
      todayInstant: params.todayInstant,
    });
    if (mutation.applied) {
      dailyRhythmService.upsertDay(mutation.record);
    }
    return { snapshot, mutation };
  },

  confirmFinanceClose(params: {
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
    const existing = dailyRhythmService.getDay(summary.targetDateIso);
    const mutation = confirmDailyRhythmFinanceClose({
      record: existing,
      dateIso: summary.targetDateIso,
      hasTransactions: summary.hasTransactions,
      nowIso: params.nowIso,
      todayIso: params.todayIso,
      today: params.today,
      todayInstant: params.todayInstant,
    });
    if (mutation.applied) {
      dailyRhythmService.upsertDay(mutation.record);
    }
    return { summary, mutation };
  },

  notifyFinanceLedgerMutation(params: {
    prevEntries: readonly JournalEntry[];
    prevPostings: readonly Posting[];
    nextEntries: readonly JournalEntry[];
    nextPostings: readonly Posting[];
    nowIso?: string;
  } & DailyRhythmTodayOptions): DailyRhythmMutationResult | null {
    const todayIso = resolveDailyRhythmToday(params).toIsoString();
    const affectedToday = didFinanceLedgerChangeAffectDate({
      prevEntries: params.prevEntries,
      prevPostings: params.prevPostings,
      nextEntries: params.nextEntries,
      nextPostings: params.nextPostings,
      targetDateIso: todayIso,
      todayIso: params.todayIso,
      today: params.today,
      todayInstant: params.todayInstant,
    });
    if (!affectedToday) return null;

    const existing = dailyRhythmService.getDay(todayIso);
    if (!existing) return null;

    const mutation = applyDailyRhythmFinanceLedgerChange({
      record: existing,
      dateIso: todayIso,
      nowIso: params.nowIso,
      todayIso: params.todayIso,
      today: params.today,
      todayInstant: params.todayInstant,
    });
    if (mutation.applied) {
      dailyRhythmService.upsertDay(mutation.record);
    }
    return mutation;
  },
};
