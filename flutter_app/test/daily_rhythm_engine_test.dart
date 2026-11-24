import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/shared_foundation_core.dart';
import 'package:personal_management_app/domain/daily_rhythm/daily_rhythm_engine.dart';
import 'package:personal_management_app/domain/daily_rhythm/daily_rhythm_models.dart';

DailyRhythmDayEntity _makeQualifyingDay(
  String dateIso, {
  String financeCloseStatus =
      DailyRhythmFinanceCloseStatuses.closedWithTransactions,
}) {
  return DailyRhythmDayEntity(
    dateIso: dateIso,
    bibleStudyDone: true,
    bibleStudyCompletedAt: '${dateIso}T06:30:00.000Z',
    prayerDone: true,
    prayerCompletedAt: '${dateIso}T07:00:00.000Z',
    taskReviewConfirmed: true,
    taskReviewedAt: '${dateIso}T17:00:00.000Z',
    taskReviewEvidence: const DailyRhythmTaskReviewEvidence(
      overdueCount: 0,
      todayCount: 3,
      plannedCount: 3,
      completedTodayCount: 2,
    ),
    financeCloseStatus: financeCloseStatus,
    financeClosedAt: '${dateIso}T18:00:00.000Z',
    updatedAt: '${dateIso}T18:00:00.000Z',
  );
}

List<DailyRhythmDayEntity> _makeConsecutiveQualifyingDays(
  String startIso,
  int count,
) {
  final start = CalendarDate.parse(startIso);
  return List<DailyRhythmDayEntity>.generate(
    count,
    (idx) => _makeQualifyingDay(start.addDays(idx).toIsoString()),
  );
}

void main() {
  group(
    'Stage A — Daily Rhythm Contracts, Qualification, Streak & Freeze Engine',
    () {
      test('canonical constants and defaults match Stage A rules', () {
        expect(SharedDailyRhythmContracts.canonicalDayStatuses, [
          'untouched',
          'partial',
          'complete',
          'freeze_protected',
          'missed',
        ]);
        expect(SharedDailyRhythmContracts.canonicalFinanceCloseStatuses, [
          'open',
          'closed_with_transactions',
          'closed_no_transactions',
          'needs_reconfirmation',
        ]);
        expect(DailyRhythmRules.qualifyingDaysPerFreeze, 15);
        expect(DailyRhythmRules.maxStreakFreezes, 2);
      });

      test(
        '1. Day with all three responsibilities complete qualifies and increments streak',
        () {
          const todayIso = '2026-10-01';
          final day = _makeQualifyingDay(todayIso);
          expect(day.qualifies, isTrue);

          final summary = DailyRhythmEngine.evaluateTimeline(
            [day],
            todayIso: todayIso,
          );
          expect(summary.todayStatus, DailyRhythmDayStatuses.complete);
          expect(summary.isTodayInProgress, isFalse);
          expect(summary.currentStreak, 1);
          expect(summary.bestStreak, 1);
          expect(summary.totalQualifyingDays, 1);
          expect(summary.daysTowardNextFreeze, 1);
          expect(summary.availableFreezes, 0);
        },
      );

      test('2. Each individual missing responsibility prevents qualification',
          () {
        const todayIso = '2026-10-05';
        final base = _makeQualifyingDay(todayIso);

        final missingBible = base.copyWith(bibleStudyDone: false);
        final missingPrayer = base.copyWith(prayerDone: false);
        final missingTaskReview = base.copyWith(taskReviewConfirmed: false);
        final openFinance = base.copyWith(
          financeCloseStatus: DailyRhythmFinanceCloseStatuses.open,
        );

        for (final candidate in [
          missingBible,
          missingPrayer,
          missingTaskReview,
          openFinance,
        ]) {
          expect(candidate.qualifies, isFalse);
          final summary = DailyRhythmEngine.evaluateTimeline(
            [candidate],
            todayIso: todayIso,
          );
          expect(summary.todayStatus, DailyRhythmDayStatuses.partial);
          expect(summary.currentStreak, 0);
          expect(summary.totalQualifyingDays, 0);
        }
      });

      test(
        '3. Partial daily progress during today reports partial and in-progress without breaking prior streak',
        () {
          final prior = _makeConsecutiveQualifyingDays('2026-10-01', 3);
          const todayIso = '2026-10-04';
          final partialToday = DailyRhythmDayEntity.empty(todayIso).copyWith(
            bibleStudyDone: true,
            prayerDone: true,
            updatedAt: '${todayIso}T08:00:00.000Z',
          );

          final summary = DailyRhythmEngine.evaluateTimeline(
            [...prior, partialToday],
            todayIso: todayIso,
          );
          expect(summary.todayStatus, DailyRhythmDayStatuses.partial);
          expect(summary.todayFaithComplete, isTrue);
          expect(summary.todayTasksComplete, isFalse);
          expect(summary.todayFinanceComplete, isFalse);
          expect(summary.todayCompletedResponsibilities, 1);
          expect(summary.isTodayInProgress, isTrue);
          expect(summary.currentStreak, 3);
          expect(summary.totalQualifyingDays, 3);
        },
      );

      test(
        '4. Empty Finance day explicitly confirmed with closed_no_transactions qualifies',
        () {
          const todayIso = '2026-10-10';
          var rec = DailyRhythmDayEntity.empty(todayIso);
          rec = DailyRhythmEngine.updateFaith(
            record: rec,
            dateIso: todayIso,
            bibleStudyDone: true,
            prayerDone: true,
            todayIso: todayIso,
          ).record;
          rec = DailyRhythmEngine.confirmTaskReview(
            record: rec,
            dateIso: todayIso,
            evidence: const DailyRhythmTaskReviewEvidence(),
            todayIso: todayIso,
          ).record;
          rec = DailyRhythmEngine.confirmFinanceClose(
            record: rec,
            dateIso: todayIso,
            hasTransactions: false,
            todayIso: todayIso,
          ).record;

          expect(
            rec.financeCloseStatus,
            DailyRhythmFinanceCloseStatuses.closedNoTransactions,
          );
          expect(rec.qualifies, isTrue);
          final summary = DailyRhythmEngine.evaluateTimeline(
            [rec],
            todayIso: todayIso,
          );
          expect(summary.todayStatus, DailyRhythmDayStatuses.complete);
          expect(summary.currentStreak, 1);
        },
      );

      test(
        '5. Empty Finance day left open or needs_reconfirmation does not qualify',
        () {
          const todayIso = '2026-10-11';
          final openDay = _makeQualifyingDay(
            todayIso,
            financeCloseStatus: DailyRhythmFinanceCloseStatuses.open,
          );
          final reconfirmDay = _makeQualifyingDay(
            todayIso,
            financeCloseStatus:
                DailyRhythmFinanceCloseStatuses.needsReconfirmation,
          );

          expect(openDay.qualifies, isFalse);
          expect(reconfirmDay.qualifies, isFalse);
          expect(
            DailyRhythmEngine.evaluateTimeline([openDay], todayIso: todayIso)
                .todayStatus,
            DailyRhythmDayStatuses.partial,
          );
          expect(
            DailyRhythmEngine.evaluateTimeline(
              [reconfirmDay],
              todayIso: todayIso,
            ).todayStatus,
            DailyRhythmDayStatuses.partial,
          );
        },
      );

      test('6. Fifteen cumulative qualifying days earn 1 streak freeze', () {
        final records = _makeConsecutiveQualifyingDays('2026-09-01', 15);
        final day14Summary = DailyRhythmEngine.evaluateTimeline(
          records.take(14),
          todayIso: '2026-09-14',
        );
        expect(day14Summary.availableFreezes, 0);
        expect(day14Summary.daysTowardNextFreeze, 14);
        expect(day14Summary.daysUntilNextFreeze, 1);

        final day15Summary = DailyRhythmEngine.evaluateTimeline(
          records,
          todayIso: '2026-09-15',
        );
        expect(day15Summary.currentStreak, 15);
        expect(day15Summary.totalQualifyingDays, 15);
        expect(day15Summary.availableFreezes, 1);
        expect(day15Summary.freezesEarnedTotal, 1);
        expect(day15Summary.daysTowardNextFreeze, 0);
        expect(day15Summary.daysUntilNextFreeze, 15);
      });

      test(
        '7. Freeze balance is strictly capped at 2 even at 45+ qualifying days',
        () {
          final days30 = _makeConsecutiveQualifyingDays('2026-08-01', 30);
          final summary30 = DailyRhythmEngine.evaluateTimeline(
            days30,
            todayIso: '2026-08-30',
          );
          expect(summary30.totalQualifyingDays, 30);
          expect(summary30.availableFreezes, 2);

          final days45 = _makeConsecutiveQualifyingDays('2026-08-01', 45);
          final summary45 = DailyRhythmEngine.evaluateTimeline(
            days45,
            todayIso: '2026-09-14',
          );
          expect(summary45.totalQualifyingDays, 45);
          expect(summary45.availableFreezes, 2);
          expect(summary45.freezesEarnedTotal, 2);
        },
      );

      test(
        '8. Single missed day is protected with freeze, preserving streak without inflating qualifying count',
        () {
          final first15 = _makeConsecutiveQualifyingDays('2026-09-01', 15);
          final day17 = _makeQualifyingDay('2026-09-17');

          final morningCheck = DailyRhythmEngine.evaluateTimeline(
            first15,
            todayIso: '2026-09-17',
          );
          expect(
            morningCheck.byDate['2026-09-16']?.status,
            DailyRhythmDayStatuses.freezeProtected,
          );
          expect(
            morningCheck.byDate['2026-09-16']?.isProvisionalFreeze,
            isTrue,
          );
          expect(morningCheck.provisionalFreezeActive, isTrue);
          expect(morningCheck.currentStreak, 15);
          expect(morningCheck.availableFreezes, 0);
          expect(morningCheck.todayStatus, DailyRhythmDayStatuses.untouched);

          final completedSummary = DailyRhythmEngine.evaluateTimeline(
            [...first15, day17],
            todayIso: '2026-09-17',
          );
          expect(
            completedSummary.byDate['2026-09-16']?.status,
            DailyRhythmDayStatuses.freezeProtected,
          );
          expect(
            completedSummary.byDate['2026-09-16']?.isProvisionalFreeze,
            isFalse,
          );
          expect(completedSummary.currentStreak, 16);
          expect(completedSummary.bestStreak, 16);
          expect(completedSummary.totalQualifyingDays, 16);
          expect(completedSummary.availableFreezes, 0);
          expect(completedSummary.freezesUsedTotal, 1);
          expect(completedSummary.daysTowardNextFreeze, 1);
        },
      );

      test(
        '9. Multiple consecutive missed days break streak and never waste freezes',
        () {
          final first15 = _makeConsecutiveQualifyingDays('2026-09-01', 15);
          final day18 = _makeQualifyingDay('2026-09-18');

          final sep18Morning = DailyRhythmEngine.evaluateTimeline(
            first15,
            todayIso: '2026-09-18',
          );
          expect(
            sep18Morning.byDate['2026-09-16']?.status,
            DailyRhythmDayStatuses.missed,
          );
          expect(
            sep18Morning.byDate['2026-09-17']?.status,
            DailyRhythmDayStatuses.missed,
          );
          expect(sep18Morning.currentStreak, 0);
          expect(sep18Morning.bestStreak, 15);
          expect(sep18Morning.availableFreezes, 1);
          expect(sep18Morning.freezesUsedTotal, 0);
          expect(sep18Morning.provisionalFreezeActive, isFalse);

          final sep18Done = DailyRhythmEngine.evaluateTimeline(
            [...first15, day18],
            todayIso: '2026-09-18',
          );
          expect(sep18Done.currentStreak, 1);
          expect(sep18Done.bestStreak, 15);
          expect(sep18Done.totalQualifyingDays, 16);
          expect(sep18Done.availableFreezes, 1);
          expect(sep18Done.freezesUsedTotal, 0);
        },
      );

      test('10. Missed day with zero available freezes resets streak to zero',
          () {
        final days10 = _makeConsecutiveQualifyingDays('2026-10-01', 10);
        final oct12 = _makeQualifyingDay('2026-10-12');

        final summary = DailyRhythmEngine.evaluateTimeline(
          [...days10, oct12],
          todayIso: '2026-10-12',
        );
        expect(
          summary.byDate['2026-10-11']?.status,
          DailyRhythmDayStatuses.missed,
        );
        expect(summary.currentStreak, 1);
        expect(summary.bestStreak, 10);
        expect(summary.totalQualifyingDays, 11);
        expect(summary.availableFreezes, 0);
      });

      test(
        '11. Today still in progress is never marked missed and never consumes a freeze',
        () {
          final first15 = _makeConsecutiveQualifyingDays('2026-09-01', 15);
          final summary = DailyRhythmEngine.evaluateTimeline(
            first15,
            todayIso: '2026-09-16',
          );

          expect(summary.todayStatus, DailyRhythmDayStatuses.untouched);
          expect(summary.isTodayInProgress, isTrue);
          expect(summary.currentStreak, 15);
          expect(summary.availableFreezes, 1);
          expect(summary.freezesUsedTotal, 0);
          expect(summary.provisionalFreezeActive, isFalse);
        },
      );

      test(
        '12. Deterministic replay across unsorted and duplicate records matches canonical order',
        () {
          final ordered = [
            ..._makeConsecutiveQualifyingDays('2026-09-01', 15),
            _makeQualifyingDay('2026-09-17'),
            _makeQualifyingDay('2026-09-18'),
          ];
          final olderDuplicateSep10 = DailyRhythmDayEntity.empty(
            '2026-09-10',
            updatedAt: '2026-09-10T05:00:00.000Z',
          ).copyWith(bibleStudyDone: true);

          final scrambled = [
            ordered[16],
            ordered[4],
            olderDuplicateSep10,
            ordered[0],
            ordered[15],
            ordered[9],
            ...ordered.sublist(1, 4),
            ...ordered.sublist(5, 9),
            ...ordered.sublist(10, 15),
          ];

          final normalizedA = DailyRhythmEngine.normalizeTimeline(ordered);
          final normalizedB = DailyRhythmEngine.normalizeTimeline(scrambled);
          expect(normalizedB, equals(normalizedA));

          final summaryA = DailyRhythmEngine.evaluateTimeline(
            ordered,
            todayIso: '2026-09-18',
          );
          final summaryB = DailyRhythmEngine.evaluateTimeline(
            scrambled,
            todayIso: '2026-09-18',
          );
          expect(summaryB.currentStreak, summaryA.currentStreak);
          expect(summaryB.bestStreak, summaryA.bestStreak);
          expect(summaryB.totalQualifyingDays, summaryA.totalQualifyingDays);
          expect(summaryB.availableFreezes, summaryA.availableFreezes);
          expect(summaryB.freezesUsedTotal, summaryA.freezesUsedTotal);
          expect(summaryB.currentStreak, 17);
          expect(summaryB.availableFreezes, 0);
          expect(summaryB.freezesUsedTotal, 1);
        },
      );

      test(
        '13. Historical locking & finance correction rules preserve finalized history and spent freezes',
        () {
          final first15 = _makeConsecutiveQualifyingDays('2026-09-01', 15);
          final day17 = _makeQualifyingDay('2026-09-17');
          final day18 = _makeQualifyingDay('2026-09-18');
          final day19 = _makeQualifyingDay('2026-09-19');
          const todayIso = '2026-09-20';
          final day20 = _makeQualifyingDay(todayIso);
          final timeline = [...first15, day17, day18, day19, day20];

          final pastFaith = DailyRhythmEngine.updateFaith(
            record: timeline[4],
            dateIso: '2026-09-05',
            bibleStudyDone: false,
            todayIso: todayIso,
          );
          expect(pastFaith.applied, isFalse);
          expect(pastFaith.reason, DailyRhythmMutationReason.pastDayLocked);
          expect(pastFaith.record.bibleStudyDone, isTrue);

          final pastTask = DailyRhythmEngine.confirmTaskReview(
            record: timeline[4],
            dateIso: '2026-09-05',
            todayIso: todayIso,
          );
          expect(pastTask.applied, isFalse);
          expect(pastTask.reason, DailyRhythmMutationReason.pastDayLocked);

          final futureFaith = DailyRhythmEngine.updateFaith(
            dateIso: '2026-09-21',
            bibleStudyDone: true,
            todayIso: todayIso,
          );
          expect(futureFaith.applied, isFalse);
          expect(futureFaith.reason, DailyRhythmMutationReason.futureDayLocked);

          final pastFinanceEdit = DailyRhythmEngine.applyFinanceLedgerChange(
            record: timeline[4],
            dateIso: '2026-09-05',
            todayIso: todayIso,
          );
          expect(pastFinanceEdit.applied, isFalse);
          expect(
            pastFinanceEdit.reason,
            DailyRhythmMutationReason.pastDayLocked,
          );
          expect(
            pastFinanceEdit.record.financeCloseStatus,
            DailyRhythmFinanceCloseStatuses.closedWithTransactions,
          );

          final replayed = DailyRhythmEngine.evaluateTimeline(
            timeline.map(
              (d) => d.dateIso == '2026-09-05' ? pastFinanceEdit.record : d,
            ),
            todayIso: todayIso,
          );
          expect(
            replayed.byDate['2026-09-16']?.status,
            DailyRhythmDayStatuses.freezeProtected,
          );
          expect(replayed.freezesUsedTotal, 1);
          expect(replayed.currentStreak, 19);

          final sameDayEdit = DailyRhythmEngine.applyFinanceLedgerChange(
            record: day20,
            dateIso: todayIso,
            todayIso: todayIso,
            nowIso: '2026-09-20T19:00:00.000Z',
          );
          expect(sameDayEdit.applied, isTrue);
          expect(sameDayEdit.reason, DailyRhythmMutationReason.updated);
          expect(
            sameDayEdit.record.financeCloseStatus,
            DailyRhythmFinanceCloseStatuses.needsReconfirmation,
          );
          expect(sameDayEdit.record.financeClosedAt, isNull);

          final reopened = DailyRhythmEngine.reopenFinanceDay(
            record: sameDayEdit.record,
            dateIso: todayIso,
            todayIso: todayIso,
          );
          expect(reopened.applied, isTrue);
          expect(
            reopened.record.financeCloseStatus,
            DailyRhythmFinanceCloseStatuses.open,
          );
        },
      );

      test(
        '14. Ethiopia UTC+3 day boundary and Ethiopian Pagume leap/year rollover behave consistently',
        () {
          final beforeEatMidnight = DateTime.utc(2026, 9, 10, 20, 59, 59);
          final atEatMidnight = DateTime.utc(2026, 9, 10, 21, 0, 0);

          final pagume5 = _makeQualifyingDay('2026-09-10');
          final summaryBefore = DailyRhythmEngine.evaluateTimeline(
            [pagume5],
            todayInstant: beforeEatMidnight,
          );
          expect(summaryBefore.todayIso, '2026-09-10');
          expect(summaryBefore.todayEthiopianIso, '2018-13-05');
          expect(summaryBefore.todayStatus, DailyRhythmDayStatuses.complete);
          expect(summaryBefore.currentStreak, 1);

          final summaryAfter = DailyRhythmEngine.evaluateTimeline(
            [pagume5],
            todayInstant: atEatMidnight,
          );
          expect(summaryAfter.todayIso, '2026-09-11');
          expect(summaryAfter.todayEthiopianIso, '2019-01-01');
          expect(summaryAfter.todayStatus, DailyRhythmDayStatuses.untouched);
          expect(summaryAfter.isTodayInProgress, isTrue);
          expect(summaryAfter.currentStreak, 1);

          final pagume6Greg =
              EthiopianDate(year: 2019, month: 13, day: 6).toCalendarDate();
          expect(pagume6Greg.toIsoString(), '2027-09-11');
          final summaryPagume6 = DailyRhythmEngine.evaluateTimeline(
            [_makeQualifyingDay(pagume6Greg.toIsoString())],
            today: pagume6Greg,
          );
          expect(summaryPagume6.todayEthiopianIso, '2019-13-06');
          expect(summaryPagume6.currentStreak, 1);
        },
      );
    },
  );
}
