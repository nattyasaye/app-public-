import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  createEmptyDailyRhythmDay,
  DailyRhythmDayRecord,
  evaluateDailyRhythmTimeline,
} from './dailyRhythm';
import {
  buildDailyRhythmDashboardOverview,
  buildDailyRhythmTaskReviewSnapshot,
  DAILY_RHYTHM_FREEZE_RULES,
  describeDailyRhythmCalendarDay,
  inspectDailyRhythmFinanceDay,
} from './dailyRhythmWorkflows';
import { JournalEntry } from './doubleEntryFinance';
import { SharedDailyPlanningEntry } from './sharedFoundation';
import { DaywellTaskRecord } from './taskOperations';
import { dailyRhythmService } from '../services/dailyRhythmService';

const REPO_ROOT = process.cwd();
const FIXED_TODAY = '2026-11-23';

function readRepoFile(relPath: string): string {
  return fs.readFileSync(path.join(REPO_ROOT, relPath), 'utf8');
}

function makeQualifyingDay(dateIso: string): DailyRhythmDayRecord {
  return {
    dateIso,
    bibleStudyDone: true,
    bibleStudyCompletedAt: `${dateIso}T06:00:00.000Z`,
    prayerDone: true,
    prayerCompletedAt: `${dateIso}T06:15:00.000Z`,
    taskReviewConfirmed: true,
    taskReviewedAt: `${dateIso}T09:00:00.000Z`,
    taskReviewEvidence: {
      overdueCount: 0,
      todayCount: 1,
      plannedCount: 1,
      completedTodayCount: 1,
    },
    financeCloseStatus: 'closed_with_transactions',
    financeClosedAt: `${dateIso}T19:00:00.000Z`,
    updatedAt: `${dateIso}T19:00:00.000Z`,
  };
}

function shiftIso(dateIso: string, offsetDays: number): string {
  const [y, m, d] = dateIso.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d + offsetDays));
  return dt.toISOString().slice(0, 10);
}

function buildTestDashboardOverview(params: {
  days: DailyRhythmDayRecord[];
  tasks: DaywellTaskRecord[];
  dailyPlanningEntries: SharedDailyPlanningEntry[];
  entries: JournalEntry[];
  todayIso: string;
}) {
  const timelineSummary = evaluateDailyRhythmTimeline(params.days, {
    todayIso: params.todayIso,
  });
  const taskSnapshot = buildDailyRhythmTaskReviewSnapshot({
    tasks: params.tasks,
    dailyPlanningEntries: params.dailyPlanningEntries,
    targetDateIso: params.todayIso,
    todayIso: params.todayIso,
  });
  const financeSummary = inspectDailyRhythmFinanceDay({
    entries: params.entries,
    targetDateIso: params.todayIso,
    todayIso: params.todayIso,
  });
  return buildDailyRhythmDashboardOverview({
    timelineSummary,
    taskSnapshot,
    financeSummary,
  });
}

describe('STAGE D: DAILY RHYTHM DASHBOARD OVERVIEW & CALENDAR HISTORY', () => {
  it('1. Untouched today shows 0/3 open status, does not count as missed, and highlights Faith first', () => {
    const overview = buildTestDashboardOverview({
      days: [],
      tasks: [],
      dailyPlanningEntries: [],
      entries: [],
      todayIso: FIXED_TODAY,
    });

    assert.equal(overview.completedResponsibilities, 0);
    assert.equal(overview.totalResponsibilities, 3);
    assert.equal(overview.progressPercent, 0);
    assert.equal(overview.isDayQualified, false);
    assert.equal(overview.overallStatusLabel, 'Open · 0/3');
    assert.match(overview.overallStatusDescription, /do not mean today has been missed/i);
    assert.equal(overview.nextIncompleteResponsibility, 'faith');
    assert.equal(overview.nextFaithStep, 'bibleStudy');
    assert.equal(overview.faithProgressLabel, '0/2');
    assert.equal(overview.currentStreak, 0);
    assert.equal(overview.bestStreak, 0);
    assert.equal(overview.availableFreezes, 0);
    assert.equal(overview.maxFreezes, 2);
    assert.equal(overview.daysTowardNextFreeze, 0);
    assert.equal(overview.qualifyingDaysPerFreeze, 15);
  });

  it('2. Partial progress (Faith 1/2, Task review done, Finance open) never masquerades as a qualifying day', () => {
    const tasks: DaywellTaskRecord[] = [
      {
        id: 't1',
        title: 'Overdue bill',
        dueDate: '2026-11-21',
        priority: 'high',
        completed: false,
        status: 'not_started',
        hasReminder: false,
        subtasks: [],
        createdAt: '2026-11-20T05:00:00.000Z',
      },
      {
        id: 't2',
        title: 'Today task',
        dueDate: FIXED_TODAY,
        priority: 'medium',
        completed: false,
        status: 'not_started',
        hasReminder: false,
        subtasks: [],
        createdAt: '2026-11-23T05:00:00.000Z',
      },
    ];
    const planning: SharedDailyPlanningEntry[] = [
      {
        id: 'p1',
        taskId: 't2',
        planDate: FIXED_TODAY,
        action: 'planned',
        createdAt: '2026-11-23T05:00:00.000Z',
        updatedAt: '2026-11-23T05:00:00.000Z',
      },
    ];

    const partialDay: DailyRhythmDayRecord = {
      ...createEmptyDailyRhythmDay(FIXED_TODAY),
      bibleStudyDone: true,
      bibleStudyCompletedAt: `${FIXED_TODAY}T06:00:00.000Z`,
      taskReviewConfirmed: true,
      taskReviewedAt: `${FIXED_TODAY}T08:30:00.000Z`,
    };

    const overview = buildTestDashboardOverview({
      days: [partialDay],
      tasks,
      dailyPlanningEntries: planning,
      entries: [],
      todayIso: FIXED_TODAY,
    });

    assert.equal(overview.completedResponsibilities, 1);
    assert.equal(overview.isDayQualified, false);
    assert.equal(overview.isTodayInProgress, true);
    assert.equal(overview.faithComplete, false);
    assert.equal(overview.faithProgressLabel, '1/2');
    assert.equal(overview.nextFaithStep, 'prayer');
    assert.equal(overview.faithActionLabel, 'Complete prayer');
    assert.equal(overview.tasksComplete, true);
    assert.equal(overview.tasksOverdueCount, 1);
    assert.equal(overview.tasksTodayCount, 1);
    assert.equal(overview.tasksPlannedCount, 1);
    assert.match(overview.tasksContextLabel, /1 overdue/);
    assert.equal(overview.nextIncompleteResponsibility, 'faith');
  });

  it('3. Distinguishes all four Finance close statuses on Dashboard overview', () => {
    const entries: JournalEntry[] = [
      {
        id: 'je-1',
        entryType: 'standard',
        description: 'Lunch',
        occurrenceDate: FIXED_TODAY,
        isVoided: false,
        createdAt: `${FIXED_TODAY}T09:00:00.000Z`,
      },
    ];

    const baseDay: DailyRhythmDayRecord = {
      ...createEmptyDailyRhythmDay(FIXED_TODAY),
      bibleStudyDone: true,
      prayerDone: true,
      taskReviewConfirmed: true,
    };

    const openOverview = buildTestDashboardOverview({
      days: [{ ...baseDay, financeCloseStatus: 'open' }],
      tasks: [],
      dailyPlanningEntries: [],
      entries,
      todayIso: FIXED_TODAY,
    });
    assert.equal(openOverview.financeStatusLabel, 'Unreviewed today');
    assert.equal(openOverview.financeTodayTransactionCount, 1);
    assert.equal(openOverview.nextIncompleteResponsibility, 'finance');

    const reconfirmOverview = buildTestDashboardOverview({
      days: [{ ...baseDay, financeCloseStatus: 'needs_reconfirmation' }],
      tasks: [],
      dailyPlanningEntries: [],
      entries,
      todayIso: FIXED_TODAY,
    });
    assert.equal(reconfirmOverview.financeNeedsReconfirmation, true);
    assert.equal(reconfirmOverview.financeStatusLabel, 'Needs reconfirmation');
    assert.equal(reconfirmOverview.financeActionLabel, 'Reconfirm review');
    assert.equal(reconfirmOverview.isDayQualified, false);
    assert.match(reconfirmOverview.overallStatusLabel, /Needs reconfirmation/);

    const reviewedOverview = buildTestDashboardOverview({
      days: [{ ...baseDay, financeCloseStatus: 'closed_with_transactions' }],
      tasks: [],
      dailyPlanningEntries: [],
      entries,
      todayIso: FIXED_TODAY,
    });
    assert.equal(reviewedOverview.financeStatusLabel, 'Reviewed transactions');
    assert.equal(reviewedOverview.isDayQualified, true);
    assert.equal(reviewedOverview.completedResponsibilities, 3);
    assert.equal(reviewedOverview.overallStatusLabel, 'Day qualified · 3/3');

    const noTxOverview = buildTestDashboardOverview({
      days: [{ ...baseDay, financeCloseStatus: 'closed_no_transactions' }],
      tasks: [],
      dailyPlanningEntries: [],
      entries: [],
      todayIso: FIXED_TODAY,
    });
    assert.equal(noTxOverview.financeStatusLabel, 'Confirmed no transactions');
    assert.equal(noTxOverview.isDayQualified, true);
    assert.equal(noTxOverview.nextIncompleteResponsibility, null);
  });

  it('4. Correctly surfaces earned freezes (max 2), provisional freeze protection, and finalized spent freezes', () => {
    // 15 consecutive qualifying days ending 2 days ago (1 earned freeze), yesterday missed (provisional freeze), today untouched.
    const days: DailyRhythmDayRecord[] = [];
    for (let offset = -16; offset <= -2; offset += 1) {
      days.push(makeQualifyingDay(shiftIso(FIXED_TODAY, offset)));
    }
    const yesterdayIso = shiftIso(FIXED_TODAY, -1);

    const provisionalOverview = buildTestDashboardOverview({
      days,
      tasks: [],
      dailyPlanningEntries: [],
      entries: [],
      todayIso: FIXED_TODAY,
    });

    assert.equal(provisionalOverview.provisionalFreezeActive, true);
    assert.equal(provisionalOverview.provisionalFreezeDateIso, yesterdayIso);
    assert.equal(provisionalOverview.currentStreak, 15);
    assert.equal(provisionalOverview.availableFreezes, 0);
    assert.match(provisionalOverview.freezeStatusSummary, /Provisional freeze/);

    // Complete today -> provisional freeze finalizes as spent freeze
    const finalizedOverview = buildTestDashboardOverview({
      days: [...days, makeQualifyingDay(FIXED_TODAY)],
      tasks: [],
      dailyPlanningEntries: [],
      entries: [],
      todayIso: FIXED_TODAY,
    });

    assert.equal(finalizedOverview.provisionalFreezeActive, false);
    assert.equal(finalizedOverview.finalizedFreezesUsed, 1);
    assert.equal(finalizedOverview.currentStreak, 16);
    assert.equal(finalizedOverview.availableFreezes, 0);

    // Calendar inspections clearly distinguish provisional vs finalized freezes
    const provisionalCalSummary = evaluateDailyRhythmTimeline(days, {
      todayIso: FIXED_TODAY,
    });
    const provisionalInspection = describeDailyRhythmCalendarDay({
      dateIso: yesterdayIso,
      timelineSummary: provisionalCalSummary,
    });
    assert.equal(provisionalInspection.calendarStatus, 'freeze_protected');
    assert.equal(provisionalInspection.isProvisionalFreeze, true);
    assert.equal(provisionalInspection.shortMarkerGlyph, '❄?');
    assert.match(provisionalInspection.statusLabel, /provisional/i);
    assert.match(provisionalInspection.freezeExplanation ?? '', /Provisional freeze/);

    const finalizedCalSummary = evaluateDailyRhythmTimeline(
      [...days, makeQualifyingDay(FIXED_TODAY)],
      { todayIso: FIXED_TODAY }
    );
    const finalizedInspection = describeDailyRhythmCalendarDay({
      dateIso: yesterdayIso,
      timelineSummary: finalizedCalSummary,
    });
    assert.equal(finalizedInspection.calendarStatus, 'freeze_protected');
    assert.equal(finalizedInspection.isProvisionalFreeze, false);
    assert.equal(finalizedInspection.shortMarkerGlyph, '❄');
    assert.match(finalizedInspection.statusLabel, /finalized/i);
    assert.match(finalizedInspection.freezeExplanation ?? '', /Finalized spent freeze/);

    // Max 2 freezes cap when 30 consecutive qualifying days exist
    const thirtyDays: DailyRhythmDayRecord[] = [];
    for (let offset = -29; offset <= 0; offset += 1) {
      thirtyDays.push(makeQualifyingDay(shiftIso(FIXED_TODAY, offset)));
    }
    const cappedOverview = buildTestDashboardOverview({
      days: thirtyDays,
      tasks: [],
      dailyPlanningEntries: [],
      entries: [],
      todayIso: FIXED_TODAY,
    });
    assert.equal(cappedOverview.availableFreezes, 2);
    assert.equal(cappedOverview.maxFreezes, 2);
  });

  it('5. Calendar detail inspection stays strictly read-only and never fabricates unrecorded historical days', () => {
    const startDay = shiftIso(FIXED_TODAY, -3);
    const missedDay = shiftIso(FIXED_TODAY, -2);
    const partialPast = shiftIso(FIXED_TODAY, -1);
    const beforeHistory = shiftIso(FIXED_TODAY, -10);
    const futureDay = shiftIso(FIXED_TODAY, 2);

    const days: DailyRhythmDayRecord[] = [
      makeQualifyingDay(startDay),
      {
        ...createEmptyDailyRhythmDay(partialPast),
        bibleStudyDone: true,
        bibleStudyCompletedAt: `${partialPast}T07:00:00.000Z`,
      },
    ];

    const summary = evaluateDailyRhythmTimeline(days, { todayIso: FIXED_TODAY });

    const qualifiedInfo = describeDailyRhythmCalendarDay({
      dateIso: startDay,
      timelineSummary: summary,
    });
    assert.equal(qualifiedInfo.calendarStatus, 'complete');
    assert.equal(qualifiedInfo.hasRecordedHistory, true);
    assert.equal(qualifiedInfo.completedResponsibilities, 3);
    assert.ok(qualifiedInfo.lockNotice);

    const missedInfo = describeDailyRhythmCalendarDay({
      dateIso: missedDay,
      timelineSummary: summary,
    });
    assert.equal(missedInfo.calendarStatus, 'missed');
    assert.equal(missedInfo.completedResponsibilities, 0);

    const partialInfo = describeDailyRhythmCalendarDay({
      dateIso: partialPast,
      timelineSummary: summary,
    });
    assert.equal(partialInfo.calendarStatus, 'missed');
    assert.equal(partialInfo.hasRecordedHistory, true);
    assert.equal(partialInfo.bibleStudyDone, true);
    assert.equal(partialInfo.prayerDone, false);

    const unrecordedInfo = describeDailyRhythmCalendarDay({
      dateIso: beforeHistory,
      timelineSummary: summary,
    });
    assert.equal(unrecordedInfo.calendarStatus, 'unrecorded');
    assert.equal(unrecordedInfo.isFuture, false);
    assert.equal(unrecordedInfo.hasRecordedHistory, false);
    assert.match(unrecordedInfo.detailSummary, /No Daily Rhythm activity recorded prior to/);
    assert.match(unrecordedInfo.lockNotice ?? '', /never fabricated/i);

    const futureInfo = describeDailyRhythmCalendarDay({
      dateIso: futureDay,
      timelineSummary: summary,
    });
    assert.equal(futureInfo.calendarStatus, 'unrecorded');
    assert.equal(futureInfo.isFuture, true);
    assert.equal(futureInfo.hasRecordedHistory, false);
    assert.match(futureInfo.lockNotice ?? '', /Future dates are locked/i);

    // Confirm localStorage-backed Daily Rhythm state is completely untouched by read-only calendar inspection
    const store = new Map<string, string>();
    const prevLocalStorage = (globalThis as any).localStorage;
    (globalThis as any).localStorage = {
      getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
      setItem: (k: string, v: string) => void store.set(k, String(v)),
      removeItem: (k: string) => void store.delete(k),
      clear: () => void store.clear(),
    };
    try {
      const before = dailyRhythmService.loadDays();
      assert.deepEqual(before, []);
      assert.equal(store.size, 0);
    } finally {
      (globalThis as any).localStorage = prevLocalStorage;
    }
  });

  it('6. Cross-platform TS/Dart Stage D freeze rules, UI integration, and token governance hold', () => {
    const dartWorkflows = readRepoFile(
      'flutter_app/lib/domain/daily_rhythm/daily_rhythm_workflows.dart'
    );
    for (const rule of DAILY_RHYTHM_FREEZE_RULES) {
      assert.equal(
        dartWorkflows.includes(rule),
        true,
        `Dart DailyRhythmWorkflows.freezeRules missing rule: ${rule}`
      );
    }

    const appTsx = readRepoFile('src/App.tsx');
    assert.equal(appTsx.includes('<DailyRhythmDashboardCard'), true);
    assert.equal(appTsx.includes('A little later'), false);
    assert.equal(appTsx.includes('YOUR NEXT RIGHT THING'), false);

    const calendarTsx = readRepoFile('src/components/DaywellCalendarModule.tsx');
    assert.equal(calendarTsx.includes('<DailyRhythmCalendarDetailCard'), true);
    assert.equal(calendarTsx.includes('Daily Rhythm calendar legend'), true);

    const uiFilesToCheck = [
      'src/components/daily-rhythm/DailyRhythmDashboardCard.tsx',
      'src/components/daily-rhythm/DailyRhythmCalendarDetailCard.tsx',
      'src/components/DaywellCalendarModule.tsx',
      'src/App.tsx',
    ];
    for (const rel of uiFilesToCheck) {
      const content = readRepoFile(rel);
      assert.equal(
        /#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})\b/.test(content),
        false,
        `Unexpected hardcoded hex color in ${rel}`
      );
    }

    const flutterStageDFiles = [
      'flutter_app/lib/ui/widgets/daily_rhythm_dashboard_widgets.dart',
      'flutter_app/lib/ui/screens/dashboard_view.dart',
      'flutter_app/lib/ui/screens/calendar_view.dart',
    ];
    for (const rel of flutterStageDFiles) {
      const content = readRepoFile(rel);
      assert.equal(
        /Color\(0x/i.test(content),
        false,
        `Unexpected Color(0x...) literal in ${rel}`
      );
      assert.equal(
        /\bColors\.[a-zA-Z0-9_]+/.test(content),
        false,
        `Unexpected Material Colors.* reference in ${rel}`
      );
    }
  });
});
