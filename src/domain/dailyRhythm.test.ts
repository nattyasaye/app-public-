import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { CalendarDate, EthiopianDate } from './date';
import {
  applyDailyRhythmFinanceLedgerChange,
  CANONICAL_DAILY_RHYTHM_DAY_STATUSES,
  CANONICAL_DAILY_RHYTHM_FINANCE_CLOSE_STATUSES,
  confirmDailyRhythmFinanceClose,
  confirmDailyRhythmTaskReview,
  createEmptyDailyRhythmDay,
  DAILY_RHYTHM_MAX_STREAK_FREEZES,
  DAILY_RHYTHM_QUALIFYING_DAYS_PER_FREEZE,
  DailyRhythmDayRecord,
  DailyRhythmFinanceCloseStatus,
  evaluateDailyRhythmTimeline,
  isDailyRhythmDayQualifying,
  normalizeDailyRhythmTimeline,
  reopenDailyRhythmFinanceDay,
  updateDailyRhythmFaith,
} from './dailyRhythm';

function makeQualifyingDay(
  dateIso: string,
  financeCloseStatus: DailyRhythmFinanceCloseStatus = 'closed_with_transactions'
): DailyRhythmDayRecord {
  return {
    dateIso,
    bibleStudyDone: true,
    bibleStudyCompletedAt: `${dateIso}T06:30:00.000Z`,
    prayerDone: true,
    prayerCompletedAt: `${dateIso}T07:00:00.000Z`,
    taskReviewConfirmed: true,
    taskReviewedAt: `${dateIso}T17:00:00.000Z`,
    taskReviewEvidence: {
      overdueCount: 0,
      todayCount: 3,
      plannedCount: 3,
      completedTodayCount: 2,
    },
    financeCloseStatus,
    financeClosedAt: `${dateIso}T18:00:00.000Z`,
    updatedAt: `${dateIso}T18:00:00.000Z`,
  };
}

function makeConsecutiveQualifyingDays(
  startIso: string,
  count: number
): DailyRhythmDayRecord[] {
  const start = CalendarDate.parse(startIso);
  return Array.from({ length: count }, (_, idx) =>
    makeQualifyingDay(start.addDays(idx).toIsoString())
  );
}

describe('Stage A — Daily Rhythm Contracts, Qualification, Streak & Freeze Engine', () => {
  it('canonical constants and defaults match Stage A rules', () => {
    assert.deepEqual(CANONICAL_DAILY_RHYTHM_DAY_STATUSES, [
      'untouched',
      'partial',
      'complete',
      'freeze_protected',
      'missed',
    ]);
    assert.deepEqual(CANONICAL_DAILY_RHYTHM_FINANCE_CLOSE_STATUSES, [
      'open',
      'closed_with_transactions',
      'closed_no_transactions',
      'needs_reconfirmation',
    ]);
    assert.strictEqual(DAILY_RHYTHM_QUALIFYING_DAYS_PER_FREEZE, 15);
    assert.strictEqual(DAILY_RHYTHM_MAX_STREAK_FREEZES, 2);
  });

  it('1. Day with all three responsibilities complete qualifies and increments streak', () => {
    const todayIso = '2026-10-01';
    const day = makeQualifyingDay(todayIso);
    assert.strictEqual(isDailyRhythmDayQualifying(day), true);

    const summary = evaluateDailyRhythmTimeline([day], { todayIso });
    assert.strictEqual(summary.todayStatus, 'complete');
    assert.strictEqual(summary.isTodayInProgress, false);
    assert.strictEqual(summary.currentStreak, 1);
    assert.strictEqual(summary.bestStreak, 1);
    assert.strictEqual(summary.totalQualifyingDays, 1);
    assert.strictEqual(summary.daysTowardNextFreeze, 1);
    assert.strictEqual(summary.availableFreezes, 0);
  });

  it('2. Each individual missing responsibility prevents qualification', () => {
    const todayIso = '2026-10-05';
    const base = makeQualifyingDay(todayIso);

    const missingBible: DailyRhythmDayRecord = { ...base, bibleStudyDone: false };
    const missingPrayer: DailyRhythmDayRecord = { ...base, prayerDone: false };
    const missingTaskReview: DailyRhythmDayRecord = {
      ...base,
      taskReviewConfirmed: false,
    };
    const openFinance: DailyRhythmDayRecord = {
      ...base,
      financeCloseStatus: 'open',
    };

    for (const candidate of [
      missingBible,
      missingPrayer,
      missingTaskReview,
      openFinance,
    ]) {
      assert.strictEqual(isDailyRhythmDayQualifying(candidate), false);
      const summary = evaluateDailyRhythmTimeline([candidate], { todayIso });
      assert.strictEqual(summary.todayStatus, 'partial');
      assert.strictEqual(summary.currentStreak, 0);
      assert.strictEqual(summary.totalQualifyingDays, 0);
    }
  });

  it('3. Partial daily progress during today reports partial and in-progress without breaking prior streak', () => {
    const prior = makeConsecutiveQualifyingDays('2026-10-01', 3); // Oct 1..3
    const todayIso = '2026-10-04';
    const partialToday: DailyRhythmDayRecord = {
      ...createEmptyDailyRhythmDay(todayIso),
      bibleStudyDone: true,
      prayerDone: true,
      updatedAt: `${todayIso}T08:00:00.000Z`,
    };

    const summary = evaluateDailyRhythmTimeline([...prior, partialToday], {
      todayIso,
    });
    assert.strictEqual(summary.todayStatus, 'partial');
    assert.strictEqual(summary.todayFaithComplete, true);
    assert.strictEqual(summary.todayTasksComplete, false);
    assert.strictEqual(summary.todayFinanceComplete, false);
    assert.strictEqual(summary.todayCompletedResponsibilities, 1);
    assert.strictEqual(summary.isTodayInProgress, true);
    assert.strictEqual(summary.currentStreak, 3);
    assert.strictEqual(summary.totalQualifyingDays, 3);
  });

  it('4. Empty Finance day explicitly confirmed with closed_no_transactions qualifies', () => {
    const todayIso = '2026-10-10';
    let rec = createEmptyDailyRhythmDay(todayIso);
    rec = updateDailyRhythmFaith({
      record: rec,
      dateIso: todayIso,
      bibleStudyDone: true,
      prayerDone: true,
      todayIso,
    }).record;
    rec = confirmDailyRhythmTaskReview({
      record: rec,
      dateIso: todayIso,
      evidence: {
        overdueCount: 0,
        todayCount: 0,
        plannedCount: 0,
        completedTodayCount: 0,
      },
      todayIso,
    }).record;
    rec = confirmDailyRhythmFinanceClose({
      record: rec,
      dateIso: todayIso,
      hasTransactions: false,
      todayIso,
    }).record;

    assert.strictEqual(rec.financeCloseStatus, 'closed_no_transactions');
    assert.strictEqual(isDailyRhythmDayQualifying(rec), true);
    const summary = evaluateDailyRhythmTimeline([rec], { todayIso });
    assert.strictEqual(summary.todayStatus, 'complete');
    assert.strictEqual(summary.currentStreak, 1);
  });

  it('5. Empty Finance day left open or needs_reconfirmation does not qualify', () => {
    const todayIso = '2026-10-11';
    const openDay = {
      ...makeQualifyingDay(todayIso),
      financeCloseStatus: 'open' as const,
    };
    const reconfirmDay = {
      ...makeQualifyingDay(todayIso),
      financeCloseStatus: 'needs_reconfirmation' as const,
    };

    assert.strictEqual(isDailyRhythmDayQualifying(openDay), false);
    assert.strictEqual(isDailyRhythmDayQualifying(reconfirmDay), false);
    assert.strictEqual(
      evaluateDailyRhythmTimeline([openDay], { todayIso }).todayStatus,
      'partial'
    );
    assert.strictEqual(
      evaluateDailyRhythmTimeline([reconfirmDay], { todayIso }).todayStatus,
      'partial'
    );
  });

  it('6. Fifteen cumulative qualifying days earn 1 streak freeze', () => {
    const records = makeConsecutiveQualifyingDays('2026-09-01', 15);
    const day14Summary = evaluateDailyRhythmTimeline(records.slice(0, 14), {
      todayIso: '2026-09-14',
    });
    assert.strictEqual(day14Summary.availableFreezes, 0);
    assert.strictEqual(day14Summary.daysTowardNextFreeze, 14);
    assert.strictEqual(day14Summary.daysUntilNextFreeze, 1);

    const day15Summary = evaluateDailyRhythmTimeline(records, {
      todayIso: '2026-09-15',
    });
    assert.strictEqual(day15Summary.currentStreak, 15);
    assert.strictEqual(day15Summary.totalQualifyingDays, 15);
    assert.strictEqual(day15Summary.availableFreezes, 1);
    assert.strictEqual(day15Summary.freezesEarnedTotal, 1);
    assert.strictEqual(day15Summary.daysTowardNextFreeze, 0);
    assert.strictEqual(day15Summary.daysUntilNextFreeze, 15);
  });

  it('7. Freeze balance is strictly capped at 2 even at 45+ qualifying days', () => {
    const days30 = makeConsecutiveQualifyingDays('2026-08-01', 30);
    const summary30 = evaluateDailyRhythmTimeline(days30, {
      todayIso: '2026-08-30',
    });
    assert.strictEqual(summary30.totalQualifyingDays, 30);
    assert.strictEqual(summary30.availableFreezes, 2);

    const days45 = makeConsecutiveQualifyingDays('2026-08-01', 45);
    const summary45 = evaluateDailyRhythmTimeline(days45, {
      todayIso: '2026-09-14',
    });
    assert.strictEqual(summary45.totalQualifyingDays, 45);
    assert.strictEqual(summary45.availableFreezes, 2);
    assert.strictEqual(summary45.freezesEarnedTotal, 2);
  });

  it('8. Single missed day is protected with freeze, preserving streak without inflating qualifying count', () => {
    // Sep 1..15 qualify (15 days -> 1 freeze).
    // Sep 16 missed. Sep 17 qualifies.
    const first15 = makeConsecutiveQualifyingDays('2026-09-01', 15);
    const day17 = makeQualifyingDay('2026-09-17');

    // Morning check on Sep 17 while today is untouched: Sep 16 is provisionally protected.
    const morningCheck = evaluateDailyRhythmTimeline(first15, {
      todayIso: '2026-09-17',
    });
    assert.strictEqual(morningCheck.byDate['2026-09-16'].status, 'freeze_protected');
    assert.strictEqual(morningCheck.byDate['2026-09-16'].isProvisionalFreeze, true);
    assert.strictEqual(morningCheck.provisionalFreezeActive, true);
    assert.strictEqual(morningCheck.currentStreak, 15);
    assert.strictEqual(morningCheck.availableFreezes, 0);
    assert.strictEqual(morningCheck.todayStatus, 'untouched');

    // Once Sep 17 qualifies, Sep 16 protection is finalized, streak becomes 16, freeze spent.
    const completedSummary = evaluateDailyRhythmTimeline([...first15, day17], {
      todayIso: '2026-09-17',
    });
    assert.strictEqual(
      completedSummary.byDate['2026-09-16'].status,
      'freeze_protected'
    );
    assert.strictEqual(
      completedSummary.byDate['2026-09-16'].isProvisionalFreeze,
      false
    );
    assert.strictEqual(completedSummary.currentStreak, 16);
    assert.strictEqual(completedSummary.bestStreak, 16);
    assert.strictEqual(completedSummary.totalQualifyingDays, 16);
    assert.strictEqual(completedSummary.availableFreezes, 0);
    assert.strictEqual(completedSummary.freezesUsedTotal, 1);
    assert.strictEqual(completedSummary.daysTowardNextFreeze, 1);
  });

  it('9. Multiple consecutive missed days break streak and never waste freezes', () => {
    // Sep 1..15 qualify (1 freeze earned).
    // Sep 16 & Sep 17 BOTH missed.
    // Even if provisional check held on Sep 17 morning, by Sep 18 both revert cleanly.
    const first15 = makeConsecutiveQualifyingDays('2026-09-01', 15);
    const day18 = makeQualifyingDay('2026-09-18');

    const sep18Morning = evaluateDailyRhythmTimeline(first15, {
      todayIso: '2026-09-18',
    });
    assert.strictEqual(sep18Morning.byDate['2026-09-16'].status, 'missed');
    assert.strictEqual(sep18Morning.byDate['2026-09-17'].status, 'missed');
    assert.strictEqual(sep18Morning.currentStreak, 0);
    assert.strictEqual(sep18Morning.bestStreak, 15);
    assert.strictEqual(sep18Morning.availableFreezes, 1);
    assert.strictEqual(sep18Morning.freezesUsedTotal, 0);
    assert.strictEqual(sep18Morning.provisionalFreezeActive, false);

    const sep18Done = evaluateDailyRhythmTimeline([...first15, day18], {
      todayIso: '2026-09-18',
    });
    assert.strictEqual(sep18Done.currentStreak, 1);
    assert.strictEqual(sep18Done.bestStreak, 15);
    assert.strictEqual(sep18Done.totalQualifyingDays, 16);
    assert.strictEqual(sep18Done.availableFreezes, 1);
    assert.strictEqual(sep18Done.freezesUsedTotal, 0);
  });

  it('10. Missed day with zero available freezes resets streak to zero', () => {
    const days10 = makeConsecutiveQualifyingDays('2026-10-01', 10); // Oct 1..10, 0 freezes
    const oct12 = makeQualifyingDay('2026-10-12'); // Oct 11 missed

    const summary = evaluateDailyRhythmTimeline([...days10, oct12], {
      todayIso: '2026-10-12',
    });
    assert.strictEqual(summary.byDate['2026-10-11'].status, 'missed');
    assert.strictEqual(summary.currentStreak, 1);
    assert.strictEqual(summary.bestStreak, 10);
    assert.strictEqual(summary.totalQualifyingDays, 11);
    assert.strictEqual(summary.availableFreezes, 0);
  });

  it('11. Today still in progress is never marked missed and never consumes a freeze', () => {
    const first15 = makeConsecutiveQualifyingDays('2026-09-01', 15); // Sep 1..15
    const summary = evaluateDailyRhythmTimeline(first15, {
      todayIso: '2026-09-16',
    });

    assert.strictEqual(summary.todayStatus, 'untouched');
    assert.strictEqual(summary.isTodayInProgress, true);
    assert.strictEqual(summary.currentStreak, 15);
    assert.strictEqual(summary.availableFreezes, 1);
    assert.strictEqual(summary.freezesUsedTotal, 0);
    assert.strictEqual(summary.provisionalFreezeActive, false);
  });

  it('12. Deterministic replay across unsorted and duplicate records matches canonical order', () => {
    const ordered = [
      ...makeConsecutiveQualifyingDays('2026-09-01', 15),
      makeQualifyingDay('2026-09-17'),
      makeQualifyingDay('2026-09-18'),
    ];
    const olderDuplicateSep10: DailyRhythmDayRecord = {
      ...createEmptyDailyRhythmDay('2026-09-10'),
      bibleStudyDone: true,
      updatedAt: '2026-09-10T05:00:00.000Z',
    };
    const scrambled = [
      ordered[16],
      ordered[4],
      olderDuplicateSep10,
      ordered[0],
      ordered[15],
      ordered[9],
      ...ordered.slice(1, 4),
      ...ordered.slice(5, 9),
      ...ordered.slice(10, 15),
    ];

    const normalizedA = normalizeDailyRhythmTimeline(ordered);
    const normalizedB = normalizeDailyRhythmTimeline(scrambled);
    assert.deepEqual(normalizedB, normalizedA);

    const summaryA = evaluateDailyRhythmTimeline(ordered, {
      todayIso: '2026-09-18',
    });
    const summaryB = evaluateDailyRhythmTimeline(scrambled, {
      todayIso: '2026-09-18',
    });
    assert.deepEqual(summaryB, summaryA);
    assert.strictEqual(summaryB.currentStreak, 17);
    assert.strictEqual(summaryB.availableFreezes, 0);
    assert.strictEqual(summaryB.freezesUsedTotal, 1);
  });

  it('13. Historical locking & finance correction rules preserve finalized history and spent freezes', () => {
    const first15 = makeConsecutiveQualifyingDays('2026-09-01', 15);
    const day17 = makeQualifyingDay('2026-09-17');
    const day18 = makeQualifyingDay('2026-09-18');
    const day19 = makeQualifyingDay('2026-09-19');
    const todayIso = '2026-09-20';
    const day20 = makeQualifyingDay(todayIso);
    const timeline = [...first15, day17, day18, day19, day20];

    // Past Faith and Task Review mutations are locked after day ends
    const pastFaith = updateDailyRhythmFaith({
      record: timeline[4], // 2026-09-05
      dateIso: '2026-09-05',
      bibleStudyDone: false,
      todayIso,
    });
    assert.strictEqual(pastFaith.applied, false);
    assert.strictEqual(pastFaith.reason, 'past_day_locked');
    assert.strictEqual(pastFaith.record.bibleStudyDone, true);

    const pastTask = confirmDailyRhythmTaskReview({
      record: timeline[4],
      dateIso: '2026-09-05',
      todayIso,
    });
    assert.strictEqual(pastTask.applied, false);
    assert.strictEqual(pastTask.reason, 'past_day_locked');

    // Future dates are rejected
    const futureFaith = updateDailyRhythmFaith({
      dateIso: '2026-09-21',
      bibleStudyDone: true,
      todayIso,
    });
    assert.strictEqual(futureFaith.applied, false);
    assert.strictEqual(futureFaith.reason, 'future_day_locked');

    // Historical Finance ledger correction on 2026-09-05 MUST NOT un-qualify past day or undo spent freeze
    const pastFinanceEdit = applyDailyRhythmFinanceLedgerChange({
      record: timeline[4],
      dateIso: '2026-09-05',
      todayIso,
    });
    assert.strictEqual(pastFinanceEdit.applied, false);
    assert.strictEqual(pastFinanceEdit.reason, 'past_day_locked');
    assert.strictEqual(
      pastFinanceEdit.record.financeCloseStatus,
      'closed_with_transactions'
    );

    const replayedAfterHistoricalEdit = evaluateDailyRhythmTimeline(
      timeline.map((d) => (d.dateIso === '2026-09-05' ? pastFinanceEdit.record : d)),
      { todayIso }
    );
    assert.strictEqual(replayedAfterHistoricalEdit.byDate['2026-09-16'].status, 'freeze_protected');
    assert.strictEqual(replayedAfterHistoricalEdit.freezesUsedTotal, 1);
    assert.strictEqual(replayedAfterHistoricalEdit.currentStreak, 19);

    // Same-day Finance ledger correction DOES transition today to needs_reconfirmation
    const sameDayEdit = applyDailyRhythmFinanceLedgerChange({
      record: day20,
      dateIso: todayIso,
      todayIso,
      nowIso: '2026-09-20T19:00:00.000Z',
    });
    assert.strictEqual(sameDayEdit.applied, true);
    assert.strictEqual(sameDayEdit.reason, 'updated');
    assert.strictEqual(
      sameDayEdit.record.financeCloseStatus,
      'needs_reconfirmation'
    );
    assert.strictEqual(sameDayEdit.record.financeClosedAt, undefined);

    const reopened = reopenDailyRhythmFinanceDay({
      record: sameDayEdit.record,
      dateIso: todayIso,
      todayIso,
    });
    assert.strictEqual(reopened.applied, true);
    assert.strictEqual(reopened.record.financeCloseStatus, 'open');
  });

  it('14. Ethiopia UTC+3 day boundary and Ethiopian Pagume leap/year rollover behave consistently', () => {
    // 2026-09-10T20:59:59Z is 2026-09-10 23:59:59 EAT (Pagume 5, 2018 E.C. - non-leap)
    // 2026-09-10T21:00:00Z is 2026-09-11 00:00:00 EAT (Meskerem 1, 2019 E.C.)
    const beforeEatMidnight = new Date('2026-09-10T20:59:59.000Z');
    const atEatMidnight = new Date('2026-09-10T21:00:00.000Z');

    const pagume5 = makeQualifyingDay('2026-09-10');
    const summaryBefore = evaluateDailyRhythmTimeline([pagume5], {
      todayInstant: beforeEatMidnight,
    });
    assert.strictEqual(summaryBefore.todayIso, '2026-09-10');
    assert.strictEqual(summaryBefore.todayEthiopianIso, '2018-13-05');
    assert.strictEqual(summaryBefore.todayStatus, 'complete');
    assert.strictEqual(summaryBefore.currentStreak, 1);

    const summaryAfter = evaluateDailyRhythmTimeline([pagume5], {
      todayInstant: atEatMidnight,
    });
    assert.strictEqual(summaryAfter.todayIso, '2026-09-11');
    assert.strictEqual(summaryAfter.todayEthiopianIso, '2019-01-01');
    assert.strictEqual(summaryAfter.todayStatus, 'untouched');
    assert.strictEqual(summaryAfter.isTodayInProgress, true);
    assert.strictEqual(summaryAfter.currentStreak, 1);

    // Ethiopian leap year 2019 (2019 % 4 == 3) has Pagume 6 (2027-09-11 Gregorian)
    const pagume6Greg = new EthiopianDate(2019, 13, 6).toCalendarDate();
    assert.strictEqual(pagume6Greg.toIsoString(), '2027-09-11');
    const summaryPagume6 = evaluateDailyRhythmTimeline(
      [makeQualifyingDay(pagume6Greg.toIsoString())],
      { today: pagume6Greg }
    );
    assert.strictEqual(summaryPagume6.todayEthiopianIso, '2019-13-06');
    assert.strictEqual(summaryPagume6.currentStreak, 1);
  });
});
