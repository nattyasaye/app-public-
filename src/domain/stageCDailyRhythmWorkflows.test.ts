import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  evaluateDailyRhythmTimeline,
  isDailyRhythmDayQualifying,
} from './dailyRhythm';
import {
  buildDailyRhythmTaskReviewSnapshot,
  confirmDailyRhythmFinanceCloseFromState,
  confirmDailyRhythmTaskReviewFromState,
  didFinanceLedgerChangeAffectDate,
  inspectDailyRhythmFinanceDay,
} from './dailyRhythmWorkflows';
import { JournalEntry, Posting } from './doubleEntryFinance';
import { DaywellTaskRecord } from './taskOperations';
import { SharedDailyPlanningEntry } from './sharedFoundation';
import { dailyRhythmService } from '../services/dailyRhythmService';
import { dailyRhythmWorkflowService } from '../services/dailyRhythmWorkflowService';
import { SharedStateBridge } from '../services/sharedStateBridge';

const REPO_ROOT = process.cwd();
const FIXED_TODAY = '2026-11-23';

function readRepoFile(relPath: string): string {
  return fs.readFileSync(path.join(REPO_ROOT, relPath), 'utf8');
}

function withMockBrowserStorage(fn: (store: Map<string, string>) => void): void {
  const store = new Map<string, string>();
  const prevWindow = (globalThis as any).window;
  const prevLocalStorage = (globalThis as any).localStorage;
  const mockStorage = {
    getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
    setItem: (k: string, v: string) => void store.set(k, String(v)),
    removeItem: (k: string) => void store.delete(k),
    clear: () => void store.clear(),
  };

  (globalThis as any).localStorage = mockStorage;
  (globalThis as any).window = {
    dispatchEvent: () => true,
    CustomEvent: class CustomEvent {
      type: string;
      detail: unknown;
      constructor(type: string, init?: { detail?: unknown }) {
        this.type = type;
        this.detail = init?.detail;
      }
    },
  };

  try {
    fn(store);
  } finally {
    (globalThis as any).window = prevWindow;
    (globalThis as any).localStorage = prevLocalStorage;
  }
}

function makeTask(overrides: Partial<DaywellTaskRecord> = {}): DaywellTaskRecord {
  return {
    id: overrides.id ?? 'task-1',
    title: overrides.title ?? 'Sample task',
    priority: overrides.priority ?? 'medium',
    completed: overrides.completed ?? false,
    status: overrides.status ?? (overrides.completed ? 'completed' : 'not_started'),
    hasReminder: overrides.hasReminder ?? false,
    subtasks: overrides.subtasks ?? [],
    createdAt: overrides.createdAt ?? '2026-11-23T05:00:00.000Z',
    ...overrides,
  };
}

function makeEntry(overrides: Partial<JournalEntry> = {}): JournalEntry {
  return {
    id: overrides.id ?? 'je-1',
    entryType: overrides.entryType ?? 'expense',
    description: overrides.description ?? 'Lunch',
    occurrenceDate: overrides.occurrenceDate ?? FIXED_TODAY,
    isVoided: overrides.isVoided ?? false,
    createdAt: overrides.createdAt ?? '2026-11-23T09:00:00.000Z',
    ...overrides,
  };
}

function makePosting(overrides: Partial<Posting> = {}): Posting {
  return {
    id: overrides.id ?? 'post-1',
    entryId: overrides.entryId ?? 'je-1',
    accountId: overrides.accountId ?? 'acc-cash',
    amountCents: overrides.amountCents ?? 25000,
    direction: overrides.direction ?? 'credit',
    accountMovementDate: overrides.accountMovementDate ?? FIXED_TODAY,
    ...overrides,
  };
}

describe('STAGE C: DAILY RHYTHM MODULE WORKFLOWS (FAITH, TASKS, FINANCE)', () => {
  it('1. Faith check-in updates Bible study and Prayer independently, locks non-today dates, and creates zero ordinary Tasks', () => {
    withMockBrowserStorage((store) => {
      // Bible study only -> does not complete Faith or qualify day
      const first = dailyRhythmWorkflowService.updateFaith({
        dateIso: FIXED_TODAY,
        bibleStudyDone: true,
        todayIso: FIXED_TODAY,
        nowIso: '2026-11-23T06:10:00.000Z',
      });
      assert.equal(first.applied, true);
      assert.equal(first.record.bibleStudyDone, true);
      assert.equal(first.record.bibleStudyCompletedAt, '2026-11-23T06:10:00.000Z');
      assert.equal(first.record.prayerDone, false);
      assert.equal(first.record.prayerCompletedAt, undefined);
      assert.equal(isDailyRhythmDayQualifying(first.record), false);

      // Prayer independently -> both done, timestamps preserved independently
      const second = dailyRhythmWorkflowService.updateFaith({
        dateIso: FIXED_TODAY,
        prayerDone: true,
        todayIso: FIXED_TODAY,
        nowIso: '2026-11-23T06:40:00.000Z',
      });
      assert.equal(second.applied, true);
      assert.equal(second.record.bibleStudyDone, true);
      assert.equal(second.record.bibleStudyCompletedAt, '2026-11-23T06:10:00.000Z');
      assert.equal(second.record.prayerDone, true);
      assert.equal(second.record.prayerCompletedAt, '2026-11-23T06:40:00.000Z');

      // Past / future check-ins stay locked
      const pastAttempt = dailyRhythmWorkflowService.updateFaith({
        dateIso: '2026-11-22',
        bibleStudyDone: true,
        todayIso: FIXED_TODAY,
      });
      assert.equal(pastAttempt.applied, false);
      assert.equal(pastAttempt.reason, 'locked_non_today');
      assert.equal(dailyRhythmService.getDay('2026-11-22'), null);

      // Zero ordinary tasks created in localStorage
      assert.equal(store.get('daywell_tasks'), undefined);
    });
  });

  it('2. Tasks daily review aggregates overdue/today/planned/completed counts, handles clear day vs active tasks without completing tasks, and locks non-today dates', () => {
    withMockBrowserStorage(() => {
      const tasks: DaywellTaskRecord[] = [
        makeTask({ id: 't-overdue', title: 'Overdue rent', dueDate: '2026-11-21', priority: 'high' }),
        makeTask({ id: 't-today-due', title: 'Due today', dueDate: FIXED_TODAY }),
        makeTask({ id: 't-scheduled', title: 'Scheduled today', scheduledDate: FIXED_TODAY }),
        makeTask({ id: 't-done-today', title: 'Finished earlier', completed: true, completedAt: '2026-11-23T04:00:00.000Z' }),
        makeTask({ id: 't-archived', title: 'Archived', dueDate: FIXED_TODAY, isArchived: true }),
      ];
      const planningEntries: SharedDailyPlanningEntry[] = [
        {
          id: 'plan-1',
          taskId: 't-scheduled',
          planDate: FIXED_TODAY,
          action: 'planned',
          sortOrder: 0,
          createdAt: '2026-11-23T04:00:00.000Z',
          updatedAt: '2026-11-23T04:00:00.000Z',
        },
      ];

      const snapshot = buildDailyRhythmTaskReviewSnapshot({
        tasks,
        dailyPlanningEntries: planningEntries,
        targetDateIso: FIXED_TODAY,
        todayIso: FIXED_TODAY,
      });
      assert.equal(snapshot.hasRelevantTasks, true);
      assert.equal(snapshot.confirmActionLabel, 'Confirm daily review');
      assert.deepStrictEqual(snapshot.evidence, {
        overdueCount: 1,
        todayCount: 2,
        plannedCount: 1,
        completedTodayCount: 1,
      });

      // Confirm review WITHOUT completing or modifying any overdue/today task
      const { mutation } = dailyRhythmWorkflowService.confirmTaskReview({
        tasks,
        dailyPlanningEntries: planningEntries,
        dateIso: FIXED_TODAY,
        todayIso: FIXED_TODAY,
        nowIso: '2026-11-23T17:00:00.000Z',
      });
      assert.equal(mutation.applied, true);
      assert.equal(mutation.record.taskReviewConfirmed, true);
      assert.equal(mutation.record.taskReviewedAt, '2026-11-23T17:00:00.000Z');
      assert.deepStrictEqual(mutation.record.taskReviewEvidence, snapshot.evidence);
      assert.equal(tasks[0].completed, false);

      // Clear day snapshot when zero active attention tasks remain
      const clearSnapshot = buildDailyRhythmTaskReviewSnapshot({
        tasks: [makeTask({ id: 't-done', completed: true, completedAt: '2026-11-23T08:00:00.000Z' })],
        dailyPlanningEntries: [],
        targetDateIso: FIXED_TODAY,
        todayIso: FIXED_TODAY,
      });
      assert.equal(clearSnapshot.hasRelevantTasks, false);
      assert.equal(clearSnapshot.confirmActionLabel, 'Confirm clear day');
      assert.equal(clearSnapshot.evidence.completedTodayCount, 1);

      // Pure confirm helper rejects past day confirmation
      const pastAttempt = confirmDailyRhythmTaskReviewFromState({
        tasks,
        dailyPlanningEntries: planningEntries,
        dateIso: '2026-11-20',
        todayIso: FIXED_TODAY,
      });
      assert.equal(pastAttempt.mutation.applied, false);
      assert.equal(pastAttempt.mutation.reason, 'locked_non_today');
    });
  });

  it('3. Finance daily close distinguishes transactions vs no-transactions, requires explicit confirmation, and sets needs_reconfirmation strictly on same-day ledger changes', () => {
    withMockBrowserStorage(() => {
      // Unreviewed empty day NEVER auto-qualifies
      const emptyInspect = inspectDailyRhythmFinanceDay({
        entries: [makeEntry({ id: 'je-void', isVoided: true })],
        targetDateIso: FIXED_TODAY,
        todayIso: FIXED_TODAY,
      });
      assert.equal(emptyInspect.hasTransactions, false);
      assert.equal(emptyInspect.confirmActionLabel, 'No transactions today');

      // Confirm no transactions today
      const closeEmpty = dailyRhythmWorkflowService.confirmFinanceClose({
        entries: [],
        dateIso: FIXED_TODAY,
        todayIso: FIXED_TODAY,
        nowIso: '2026-11-23T18:00:00.000Z',
      });
      assert.equal(closeEmpty.mutation.applied, true);
      assert.equal(closeEmpty.mutation.record.financeCloseStatus, 'closed_no_transactions');

      // Adding a strictly historical transaction (2026-11-20) does NOT affect today
      const histEntries = [makeEntry({ id: 'je-hist', occurrenceDate: '2026-11-20' })];
      const histPostings = [makePosting({ id: 'p-hist', entryId: 'je-hist', accountMovementDate: '2026-11-20' })];
      const offDayResult = dailyRhythmWorkflowService.notifyFinanceLedgerMutation({
        prevEntries: [],
        prevPostings: [],
        nextEntries: histEntries,
        nextPostings: histPostings,
        todayIso: FIXED_TODAY,
      });
      assert.equal(offDayResult, null);
      assert.equal(
        dailyRhythmService.getDay(FIXED_TODAY)?.financeCloseStatus,
        'closed_no_transactions'
      );

      // Adding a same-day transaction triggers needs_reconfirmation and clears financeClosedAt
      const todayEntry = makeEntry({ id: 'je-today', occurrenceDate: FIXED_TODAY });
      const todayPosting = makePosting({ id: 'p-today', entryId: 'je-today', accountMovementDate: FIXED_TODAY });
      const sameDayResult = dailyRhythmWorkflowService.notifyFinanceLedgerMutation({
        prevEntries: histEntries,
        prevPostings: histPostings,
        nextEntries: [...histEntries, todayEntry],
        nextPostings: [...histPostings, todayPosting],
        todayIso: FIXED_TODAY,
        nowIso: '2026-11-23T18:30:00.000Z',
      });
      assert.equal(sameDayResult?.applied, true);
      assert.equal(sameDayResult?.record.financeCloseStatus, 'needs_reconfirmation');
      assert.equal(sameDayResult?.record.financeClosedAt, undefined);

      // Reconfirm close with today's transaction
      const reclose = dailyRhythmWorkflowService.confirmFinanceClose({
        entries: [...histEntries, todayEntry],
        dateIso: FIXED_TODAY,
        todayIso: FIXED_TODAY,
        nowIso: '2026-11-23T19:00:00.000Z',
      });
      assert.equal(reclose.mutation.record.financeCloseStatus, 'closed_with_transactions');

      // Voiding today's transaction also triggers needs_reconfirmation
      const voidedEntry = makeEntry({ id: 'je-today', occurrenceDate: FIXED_TODAY, isVoided: true });
      const voidReconfirm = dailyRhythmWorkflowService.notifyFinanceLedgerMutation({
        prevEntries: [...histEntries, todayEntry],
        prevPostings: [...histPostings, todayPosting],
        nextEntries: [...histEntries, voidedEntry],
        nextPostings: [...histPostings, todayPosting],
        todayIso: FIXED_TODAY,
        nowIso: '2026-11-23T19:15:00.000Z',
      });
      assert.equal(voidReconfirm?.applied, true);
      assert.equal(voidReconfirm?.record.financeCloseStatus, 'needs_reconfirmation');

      // Pure didFinanceLedgerChangeAffectDate rejects off-day-only diffs & confirms cash-movement-date today diffs
      assert.equal(
        didFinanceLedgerChangeAffectDate({
          prevEntries: [],
          prevPostings: [],
          nextEntries: histEntries,
          nextPostings: histPostings,
          targetDateIso: FIXED_TODAY,
          todayIso: FIXED_TODAY,
        }),
        false
      );
      assert.equal(
        didFinanceLedgerChangeAffectDate({
          prevEntries: histEntries,
          prevPostings: histPostings,
          nextEntries: histEntries,
          nextPostings: [makePosting({ id: 'p-hist', entryId: 'je-hist', accountMovementDate: FIXED_TODAY })],
          targetDateIso: FIXED_TODAY,
          todayIso: FIXED_TODAY,
        }),
        true
      );
    });
  });

  it('4. Cross-module completion rules & historical immutability stay intact through backup/restore', () => {
    withMockBrowserStorage(() => {
      // Seed historical qualifying streak yesterday (2026-11-22)
      dailyRhythmService.upsertDay({
        dateIso: '2026-11-22',
        bibleStudyDone: true,
        bibleStudyCompletedAt: '2026-11-22T06:00:00.000Z',
        prayerDone: true,
        prayerCompletedAt: '2026-11-22T06:20:00.000Z',
        taskReviewConfirmed: true,
        taskReviewedAt: '2026-11-22T18:00:00.000Z',
        financeCloseStatus: 'closed_with_transactions',
        financeClosedAt: '2026-11-22T19:00:00.000Z',
        updatedAt: '2026-11-22T19:00:00.000Z',
      });

      // Completing Faith + Tasks without Finance keeps today partial (non-qualifying)
      dailyRhythmWorkflowService.updateFaith({
        dateIso: FIXED_TODAY,
        bibleStudyDone: true,
        prayerDone: true,
        todayIso: FIXED_TODAY,
      });
      dailyRhythmWorkflowService.confirmTaskReview({
        tasks: [],
        dailyPlanningEntries: [],
        dateIso: FIXED_TODAY,
        todayIso: FIXED_TODAY,
      });

      let summary = evaluateDailyRhythmTimeline(dailyRhythmService.loadDays(), {
        todayIso: FIXED_TODAY,
      });
      assert.equal(summary.todayRecord.qualifies, false);
      assert.equal(summary.todayRecord.status, 'partial');
      assert.equal(summary.currentStreak, 1);

      // Historical ledger edit on 2026-11-22 does NOT alter historical 2026-11-22 Daily Rhythm record
      dailyRhythmWorkflowService.notifyFinanceLedgerMutation({
        prevEntries: [],
        prevPostings: [],
        nextEntries: [makeEntry({ id: 'je-past-fix', occurrenceDate: '2026-11-22' })],
        nextPostings: [makePosting({ id: 'p-past-fix', entryId: 'je-past-fix', accountMovementDate: '2026-11-22' })],
        todayIso: FIXED_TODAY,
      });
      assert.equal(
        dailyRhythmService.getDay('2026-11-22')?.financeCloseStatus,
        'closed_with_transactions'
      );

      // Closing Finance for today completes today -> streak increments to 2
      dailyRhythmWorkflowService.confirmFinanceClose({
        entries: [],
        dateIso: FIXED_TODAY,
        todayIso: FIXED_TODAY,
      });
      summary = evaluateDailyRhythmTimeline(dailyRhythmService.loadDays(), {
        todayIso: FIXED_TODAY,
      });
      assert.equal(summary.todayRecord.qualifies, true);
      assert.equal(summary.currentStreak, 2);

      // Pure helper rejects Finance close on past dates
      const pastClose = confirmDailyRhythmFinanceCloseFromState({
        entries: [],
        dateIso: '2026-11-22',
        todayIso: FIXED_TODAY,
      });
      assert.equal(pastClose.mutation.applied, false);
      assert.equal(pastClose.mutation.reason, 'locked_non_today');

      // Snapshot export & restore round-trips Stage C check-ins faithfully
      const snapshotJson = SharedStateBridge.exportCanonicalSnapshotJson();
      dailyRhythmService.replaceAllDays([]);
      assert.equal(dailyRhythmService.loadDays().length, 0);
      const restore = SharedStateBridge.importCanonicalSnapshotJson(snapshotJson);
      assert.equal(restore.ok, true);
      assert.equal(dailyRhythmService.loadDays().length, 2);
      assert.equal(
        dailyRhythmService.getDay(FIXED_TODAY)?.financeCloseStatus,
        'closed_no_transactions'
      );
    });
  });

  it('5. Stage C UI integrations keep Stage D Dashboard/Calendar scope unbuilt and avoid raw colors', () => {
    const appTsx = readRepoFile('src/App.tsx');
    const moreViewDart = readRepoFile('flutter_app/lib/ui/screens/more_view.dart');
    const tasksViewDart = readRepoFile('flutter_app/lib/ui/screens/tasks_view.dart');
    const financeTxDart = readRepoFile('flutter_app/lib/ui/screens/finance/finance_transactions_tab.dart');

    assert.ok(appTsx.includes('DailyFaithCheckInCard'));
    assert.ok(moreViewDart.includes('DailyFaithCheckInCard'));
    assert.ok(tasksViewDart.includes('DailyTaskReviewCard'));
    assert.ok(financeTxDart.includes('DailyFinanceCloseCard'));

    // Ensure More screen did not introduce any raw Color(0x...) or Colors.*
    assert.equal(/\bColor\(0x/i.test(moreViewDart), false);
    assert.equal(/\bColors\.[a-zA-Z0-9_]+/.test(moreViewDart), false);
    assert.equal(/\bColor\(0x/i.test(financeTxDart), false);
    assert.equal(/\bColors\.[a-zA-Z0-9_]+/.test(financeTxDart), false);
  });
});
