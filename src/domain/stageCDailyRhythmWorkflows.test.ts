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
    entryType: overrides.entryType ?? 'standard',
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
      assert.equal(pastAttempt.reason, 'past_day_locked');
      assert.equal(dailyRhythmService.getDay('2026-11-22'), null);

      const futureAttempt = dailyRhythmWorkflowService.updateFaith({
        dateIso: '2026-11-24',
        prayerDone: true,
        todayIso: FIXED_TODAY,
      });
      assert.equal(futureAttempt.applied, false);
      assert.equal(futureAttempt.reason, 'future_day_locked');
      assert.equal(dailyRhythmService.getDay('2026-11-24'), null);

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

      const tasksBeforeJson = JSON.stringify(tasks);
      const planningBeforeJson = JSON.stringify(planningEntries);

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
      assert.equal(JSON.stringify(tasks), tasksBeforeJson);
      assert.equal(JSON.stringify(planningEntries), planningBeforeJson);

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

      // Pure confirm helper rejects past & future day confirmation
      const pastAttempt = confirmDailyRhythmTaskReviewFromState({
        tasks,
        dailyPlanningEntries: planningEntries,
        dateIso: '2026-11-20',
        todayIso: FIXED_TODAY,
      });
      assert.equal(pastAttempt.mutation.applied, false);
      assert.equal(pastAttempt.mutation.reason, 'past_day_locked');

      const futureAttempt = confirmDailyRhythmTaskReviewFromState({
        tasks,
        dailyPlanningEntries: planningEntries,
        dateIso: '2026-11-25',
        todayIso: FIXED_TODAY,
      });
      assert.equal(futureAttempt.mutation.applied, false);
      assert.equal(futureAttempt.mutation.reason, 'future_day_locked');
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

      // Inspecting today with active transactions surfaces exact review label
      const todayEntry = makeEntry({ id: 'je-today', occurrenceDate: FIXED_TODAY });
      const todayPosting = makePosting({ id: 'p-today', entryId: 'je-today', accountMovementDate: FIXED_TODAY });
      const activeInspect = inspectDailyRhythmFinanceDay({
        entries: [...histEntries, todayEntry],
        targetDateIso: FIXED_TODAY,
        todayIso: FIXED_TODAY,
      });
      assert.equal(activeInspect.hasTransactions, true);
      assert.equal(activeInspect.transactionCount, 1);
      assert.equal(activeInspect.confirmActionLabel, "I've reviewed today's transactions");

      // Adding a same-day transaction triggers needs_reconfirmation and clears financeClosedAt
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

      // Editing/replacing today's transaction triggers needs_reconfirmation
      const replacementEntry = makeEntry({
        id: 'je-today-rev2',
        occurrenceDate: FIXED_TODAY,
        description: 'Dinner',
        correctedFromEntryId: 'je-today',
      });
      const replacementPosting = makePosting({
        id: 'p-today-rev2',
        entryId: 'je-today-rev2',
        amountCents: 35000,
        accountMovementDate: FIXED_TODAY,
      });
      const editReconfirm = dailyRhythmWorkflowService.notifyFinanceLedgerMutation({
        prevEntries: [...histEntries, todayEntry],
        prevPostings: [...histPostings, todayPosting],
        nextEntries: [...histEntries, todayEntry, replacementEntry],
        nextPostings: [...histPostings, todayPosting, replacementPosting],
        todayIso: FIXED_TODAY,
        nowIso: '2026-11-23T19:05:00.000Z',
      });
      assert.equal(editReconfirm?.applied, true);
      assert.equal(editReconfirm?.record.financeCloseStatus, 'needs_reconfirmation');

      // Reclose after replacement edit, then verify voiding triggers needs_reconfirmation
      dailyRhythmWorkflowService.confirmFinanceClose({
        entries: [...histEntries, replacementEntry],
        dateIso: FIXED_TODAY,
        todayIso: FIXED_TODAY,
        nowIso: '2026-11-23T19:10:00.000Z',
      });
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

      // Reclosing with only voided entries records closed_no_transactions
      const recloseAfterVoid = dailyRhythmWorkflowService.confirmFinanceClose({
        entries: [...histEntries, voidedEntry],
        dateIso: FIXED_TODAY,
        todayIso: FIXED_TODAY,
        nowIso: '2026-11-23T19:20:00.000Z',
      });
      assert.equal(recloseAfterVoid.mutation.record.financeCloseStatus, 'closed_no_transactions');

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

  it('4. Cross-module field preservation, spent-freeze protection on historical edits, future/past locks, and backup/restore round-trip', () => {
    withMockBrowserStorage(() => {
      // Seed 15 qualifying days (earning 1 streak freeze) + 1 freeze-protected missed day (2026-11-21) + qualifying day (2026-11-22)
      for (let day = 6; day <= 20; day++) {
        const dd = String(day).padStart(2, '0');
        dailyRhythmService.upsertDay({
          dateIso: `2026-11-${dd}`,
          bibleStudyDone: true,
          bibleStudyCompletedAt: `2026-11-${dd}T06:00:00.000Z`,
          prayerDone: true,
          prayerCompletedAt: `2026-11-${dd}T06:20:00.000Z`,
          taskReviewConfirmed: true,
          taskReviewedAt: `2026-11-${dd}T18:00:00.000Z`,
          financeCloseStatus: 'closed_with_transactions',
          financeClosedAt: `2026-11-${dd}T19:00:00.000Z`,
          updatedAt: `2026-11-${dd}T19:00:00.000Z`,
        });
      }
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
        nowIso: '2026-11-23T06:30:00.000Z',
      });
      dailyRhythmWorkflowService.confirmTaskReview({
        tasks: [],
        dailyPlanningEntries: [],
        dateIso: FIXED_TODAY,
        todayIso: FIXED_TODAY,
        nowIso: '2026-11-23T17:00:00.000Z',
      });

      let summary = evaluateDailyRhythmTimeline(dailyRhythmService.loadDays(), {
        todayIso: FIXED_TODAY,
      });
      assert.equal(summary.byDate[FIXED_TODAY].qualifies, false);
      assert.equal(summary.todayStatus, 'partial');
      assert.equal(summary.freezesUsedTotal, 1);
      assert.equal(summary.currentStreak, 16);

      // Historical ledger edit on 2026-11-22 does NOT alter historical Daily Rhythm record or claw back spent freeze
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
      summary = evaluateDailyRhythmTimeline(dailyRhythmService.loadDays(), {
        todayIso: FIXED_TODAY,
      });
      assert.equal(summary.freezesUsedTotal, 1);
      assert.equal(summary.currentStreak, 16);

      // Closing Finance for today preserves Faith & Task timestamps and increments streak to 17
      dailyRhythmWorkflowService.confirmFinanceClose({
        entries: [],
        dateIso: FIXED_TODAY,
        todayIso: FIXED_TODAY,
        nowIso: '2026-11-23T18:00:00.000Z',
      });
      const todayAfterFinance = dailyRhythmService.getDay(FIXED_TODAY);
      assert.equal(todayAfterFinance?.bibleStudyDone, true);
      assert.equal(todayAfterFinance?.bibleStudyCompletedAt, '2026-11-23T06:30:00.000Z');
      assert.equal(todayAfterFinance?.prayerDone, true);
      assert.equal(todayAfterFinance?.taskReviewConfirmed, true);
      assert.equal(todayAfterFinance?.taskReviewedAt, '2026-11-23T17:00:00.000Z');
      assert.equal(todayAfterFinance?.financeCloseStatus, 'closed_no_transactions');
      summary = evaluateDailyRhythmTimeline(dailyRhythmService.loadDays(), {
        todayIso: FIXED_TODAY,
      });
      assert.equal(summary.byDate[FIXED_TODAY].qualifies, true);
      assert.equal(summary.currentStreak, 17);

      // Toggling Prayer off & back on preserves Task Review and Finance Close fields
      dailyRhythmWorkflowService.updateFaith({
        dateIso: FIXED_TODAY,
        prayerDone: false,
        todayIso: FIXED_TODAY,
        nowIso: '2026-11-23T18:10:00.000Z',
      });
      const todayAfterUncheck = dailyRhythmService.getDay(FIXED_TODAY);
      assert.equal(todayAfterUncheck?.taskReviewConfirmed, true);
      assert.equal(todayAfterUncheck?.financeCloseStatus, 'closed_no_transactions');

      // Pure helper rejects Finance close on past & future dates
      const pastClose = confirmDailyRhythmFinanceCloseFromState({
        entries: [],
        dateIso: '2026-11-22',
        todayIso: FIXED_TODAY,
      });
      assert.equal(pastClose.mutation.applied, false);
      assert.equal(pastClose.mutation.reason, 'past_day_locked');

      const futureClose = confirmDailyRhythmFinanceCloseFromState({
        entries: [],
        dateIso: '2026-11-24',
        todayIso: FIXED_TODAY,
      });
      assert.equal(futureClose.mutation.applied, false);
      assert.equal(futureClose.mutation.reason, 'future_day_locked');

      // Snapshot export & restore round-trips Stage C check-ins faithfully
      const snapshotJson = SharedStateBridge.exportToAndroidJson();
      dailyRhythmService.saveDays([]);
      assert.equal(dailyRhythmService.loadDays().length, 0);
      const restore = SharedStateBridge.importFromAndroidJson(snapshotJson);
      assert.equal(restore.success, true);
      assert.equal(dailyRhythmService.loadDays().length, 17);
      assert.equal(
        dailyRhythmService.getDay(FIXED_TODAY)?.financeCloseStatus,
        'closed_no_transactions'
      );
    });
  });

  it('5. Stage C UI & cross-platform Dart/TS contract parity hold while keeping Stage D scope unbuilt', () => {
    const appTsx = readRepoFile('src/App.tsx');
    const tasksModuleTsx = readRepoFile('src/components/DaywellTasksModule.tsx');
    const financeTxTsx = readRepoFile('src/components/finance/FinanceTransactionsTab.tsx');
    const workflowsTs = readRepoFile('src/domain/dailyRhythmWorkflows.ts');
    const workflowsDart = readRepoFile('flutter_app/lib/domain/daily_rhythm/daily_rhythm_workflows.dart');
    const drControllerDart = readRepoFile('flutter_app/lib/application/daily_rhythm/daily_rhythm_controller.dart');
    const appStateDart = readRepoFile('flutter_app/lib/ui/app_state.dart');
    const moreViewDart = readRepoFile('flutter_app/lib/ui/screens/more_view.dart');
    const tasksViewDart = readRepoFile('flutter_app/lib/ui/screens/tasks_view.dart');
    const myDayDart = readRepoFile('flutter_app/lib/ui/screens/tasks/my_day_planning_view.dart');
    const financeTxDart = readRepoFile('flutter_app/lib/ui/screens/finance/finance_transactions_tab.dart');
    const drWidgetsDart = readRepoFile('flutter_app/lib/ui/widgets/daily_rhythm_workflow_widgets.dart');

    assert.ok(appTsx.includes('DailyFaithCheckInCard'));
    assert.ok(tasksModuleTsx.includes('DailyTaskReviewCard'));
    assert.ok(financeTxTsx.includes('DailyFinanceCloseCard'));
    assert.ok(moreViewDart.includes('DailyFaithCheckInCard'));
    assert.ok(tasksViewDart.includes('DailyTaskReviewCard'));
    assert.ok(myDayDart.includes('DailyTaskReviewCard'));
    assert.ok(financeTxDart.includes('DailyFinanceCloseCard'));
    assert.ok(appStateDart.includes('handleFinanceLedgerMutation'));
    assert.ok(drControllerDart.includes('confirmTaskReview'));
    assert.ok(drControllerDart.includes('confirmFinanceClose'));

    // Canonical action labels match across Dart & TypeScript workflow engines
    for (const label of [
      'Confirm daily review',
      'Confirm clear day',
      "I've reviewed today's transactions",
      'No transactions today',
    ]) {
      assert.ok(workflowsTs.includes(label), `TS missing ${label}`);
      assert.ok(workflowsDart.includes(label), `Dart missing ${label}`);
    }

    // Ensure More, Finance Transactions, and Daily Rhythm widgets introduce zero raw Color(0x...) or Colors.*
    for (const dartFile of [moreViewDart, financeTxDart, drWidgetsDart]) {
      assert.equal(/\bColor\(0x/i.test(dartFile), false);
      assert.equal(/\bColors\.[a-zA-Z0-9_]+/.test(dartFile), false);
    }
  });
});
