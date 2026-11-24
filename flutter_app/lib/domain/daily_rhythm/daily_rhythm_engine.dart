import 'dart:convert';

import '../../core/date/shared_date.dart';
import './daily_rhythm_models.dart';

/// Pure domain engine for Daywell Daily Rhythm streak, freeze, and transition rules.
///
/// Invariants:
/// - Zero dependencies on Flutter UI, application controllers, or Drift SQLite.
/// - Derives streaks, freeze balances, and per-day statuses deterministically from
///   chronological daily check-in records without mutable primary counters.
/// - Uses canonical Ethiopia civil calendar dates ([CalendarDate], UTC+3).
class DailyRhythmEngine {
  static CalendarDate resolveToday({
    String? todayIso,
    CalendarDate? today,
    DateTime? todayInstant,
  }) {
    if (today != null) return today;
    if (todayIso != null) return CalendarDate.parse(todayIso);
    if (todayInstant != null) {
      return CalendarDate.fromUtcInstantInEthiopia(todayInstant);
    }
    return CalendarDate.today();
  }

  static String _resolveNowIso({
    String? nowIso,
    DateTime? todayInstant,
  }) {
    final trimmed = nowIso?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
    if (todayInstant != null) return todayInstant.toUtc().toIso8601String();
    return EthiopiaClock.nowUtc().toIso8601String();
  }

  static int _recordFreshnessEpochMs(DailyRhythmDayEntity record) {
    final parsed = DateTime.tryParse(record.updatedAt);
    return parsed?.millisecondsSinceEpoch ?? 0;
  }

  static int _financeStatusRank(String status) {
    switch (status) {
      case DailyRhythmFinanceCloseStatuses.closedWithTransactions:
        return 3;
      case DailyRhythmFinanceCloseStatuses.closedNoTransactions:
        return 2;
      case DailyRhythmFinanceCloseStatuses.needsReconfirmation:
        return 1;
      case DailyRhythmFinanceCloseStatuses.open:
      default:
        return 0;
    }
  }

  static int _compareRecordTieBreaker(
    DailyRhythmDayEntity candidate,
    DailyRhythmDayEntity existing,
  ) {
    final candidateEpoch = _recordFreshnessEpochMs(candidate);
    final existingEpoch = _recordFreshnessEpochMs(existing);
    if (candidateEpoch != existingEpoch) {
      return candidateEpoch.compareTo(existingEpoch);
    }
    final updatedCmp = candidate.updatedAt.compareTo(existing.updatedAt);
    if (updatedCmp != 0) return updatedCmp;

    final candidateScore = (candidate.bibleStudyDone ? 1 : 0) +
        (candidate.prayerDone ? 1 : 0) +
        (candidate.taskReviewConfirmed ? 1 : 0) +
        _financeStatusRank(candidate.financeCloseStatus);
    final existingScore = (existing.bibleStudyDone ? 1 : 0) +
        (existing.prayerDone ? 1 : 0) +
        (existing.taskReviewConfirmed ? 1 : 0) +
        _financeStatusRank(existing.financeCloseStatus);
    if (candidateScore != existingScore) {
      return candidateScore.compareTo(existingScore);
    }
    return jsonEncode(candidate.toJson())
        .compareTo(jsonEncode(existing.toJson()));
  }

  static DailyRhythmDayEntity? _coerceRecord(Object? raw) {
    if (raw is DailyRhythmDayEntity) {
      return DailyRhythmDayEntity.fromJson(raw.toJson());
    }
    return DailyRhythmDayEntity.fromJson(raw);
  }

  static List<DailyRhythmDayEntity> normalizeTimeline(
    Iterable<Object?> records,
  ) {
    final byDate = <String, DailyRhythmDayEntity>{};
    for (final raw in records) {
      final normalized = _coerceRecord(raw);
      if (normalized == null) continue;
      final existing = byDate[normalized.dateIso];
      if (existing == null ||
          _compareRecordTieBreaker(normalized, existing) > 0) {
        byDate[normalized.dateIso] = normalized;
      }
    }
    final list = byDate.values.toList()
      ..sort((a, b) => a.dateIso.compareTo(b.dateIso));
    return List<DailyRhythmDayEntity>.unmodifiable(list);
  }

  static ({
    bool ok,
    DailyRhythmDayEntity? baseRecord,
    DailyRhythmMutationResult? failureResult,
  }) _validateTodayOnlyMutation({
    required String dateIso,
    DailyRhythmDayEntity? existingRecord,
    String? todayIso,
    CalendarDate? today,
    DateTime? todayInstant,
  }) {
    final targetDate = CalendarDate.tryParse(dateIso);
    final resolvedToday = resolveToday(
      todayIso: todayIso,
      today: today,
      todayInstant: todayInstant,
    );
    if (targetDate == null) {
      final fallback = existingRecord ??
          DailyRhythmDayEntity.empty(resolvedToday.toIsoString());
      return (
        ok: false,
        baseRecord: null,
        failureResult: DailyRhythmMutationResult(
          applied: false,
          reason: DailyRhythmMutationReason.invalidDate,
          record: fallback,
        ),
      );
    }

    final targetIso = targetDate.toIsoString();
    final hasMatchingRecord =
        existingRecord != null && existingRecord.dateIso == targetIso;
    final DailyRhythmDayEntity baseRecord;
    if (hasMatchingRecord) {
      baseRecord = DailyRhythmDayEntity.fromJson(existingRecord.toJson()) ??
          DailyRhythmDayEntity.empty(targetIso);
    } else {
      baseRecord = DailyRhythmDayEntity.empty(targetIso);
    }

    if (targetDate.isBefore(resolvedToday)) {
      return (
        ok: false,
        baseRecord: null,
        failureResult: DailyRhythmMutationResult(
          applied: false,
          reason: DailyRhythmMutationReason.pastDayLocked,
          record: baseRecord,
        ),
      );
    }
    if (targetDate.isAfter(resolvedToday)) {
      return (
        ok: false,
        baseRecord: null,
        failureResult: DailyRhythmMutationResult(
          applied: false,
          reason: DailyRhythmMutationReason.futureDayLocked,
          record: baseRecord,
        ),
      );
    }

    return (ok: true, baseRecord: baseRecord, failureResult: null);
  }

  static DailyRhythmMutationResult updateFaith({
    DailyRhythmDayEntity? record,
    required String dateIso,
    bool? bibleStudyDone,
    bool? prayerDone,
    String? nowIso,
    String? todayIso,
    CalendarDate? today,
    DateTime? todayInstant,
  }) {
    final check = _validateTodayOnlyMutation(
      dateIso: dateIso,
      existingRecord: record,
      todayIso: todayIso,
      today: today,
      todayInstant: todayInstant,
    );
    if (!check.ok) return check.failureResult!;

    final baseRecord = check.baseRecord!;
    final now = _resolveNowIso(nowIso: nowIso, todayInstant: todayInstant);
    final nextBible = bibleStudyDone ?? baseRecord.bibleStudyDone;
    final nextPrayer = prayerDone ?? baseRecord.prayerDone;

    if (nextBible == baseRecord.bibleStudyDone &&
        nextPrayer == baseRecord.prayerDone) {
      return DailyRhythmMutationResult(
        applied: false,
        reason: DailyRhythmMutationReason.unchanged,
        record: baseRecord,
      );
    }

    final String? nextBibleCompletedAt;
    if (!nextBible) {
      nextBibleCompletedAt = null;
    } else if (baseRecord.bibleStudyDone) {
      nextBibleCompletedAt = baseRecord.bibleStudyCompletedAt ?? now;
    } else {
      nextBibleCompletedAt = now;
    }

    final String? nextPrayerCompletedAt;
    if (!nextPrayer) {
      nextPrayerCompletedAt = null;
    } else if (baseRecord.prayerDone) {
      nextPrayerCompletedAt = baseRecord.prayerCompletedAt ?? now;
    } else {
      nextPrayerCompletedAt = now;
    }

    final updated = baseRecord.copyWith(
      bibleStudyDone: nextBible,
      bibleStudyCompletedAt: nextBibleCompletedAt,
      clearBibleStudyCompletedAt: !nextBible,
      prayerDone: nextPrayer,
      prayerCompletedAt: nextPrayerCompletedAt,
      clearPrayerCompletedAt: !nextPrayer,
      updatedAt: now,
    );

    return DailyRhythmMutationResult(
      applied: true,
      reason: DailyRhythmMutationReason.updated,
      record: updated,
    );
  }

  static DailyRhythmMutationResult confirmTaskReview({
    DailyRhythmDayEntity? record,
    required String dateIso,
    DailyRhythmTaskReviewEvidence? evidence,
    String? nowIso,
    String? todayIso,
    CalendarDate? today,
    DateTime? todayInstant,
  }) {
    final check = _validateTodayOnlyMutation(
      dateIso: dateIso,
      existingRecord: record,
      todayIso: todayIso,
      today: today,
      todayInstant: todayInstant,
    );
    if (!check.ok) return check.failureResult!;

    final baseRecord = check.baseRecord!;
    final now = _resolveNowIso(nowIso: nowIso, todayInstant: todayInstant);
    final normalizedEvidence = evidence != null
        ? DailyRhythmTaskReviewEvidence.normalized(
            overdueCount: evidence.overdueCount,
            todayCount: evidence.todayCount,
            plannedCount: evidence.plannedCount,
            completedTodayCount: evidence.completedTodayCount,
          )
        : baseRecord.taskReviewEvidence;

    final updated = baseRecord.copyWith(
      taskReviewConfirmed: true,
      taskReviewedAt: now,
      taskReviewEvidence: normalizedEvidence,
      updatedAt: now,
    );

    return DailyRhythmMutationResult(
      applied: true,
      reason: DailyRhythmMutationReason.updated,
      record: updated,
    );
  }

  static DailyRhythmMutationResult confirmFinanceClose({
    DailyRhythmDayEntity? record,
    required String dateIso,
    required bool hasTransactions,
    String? nowIso,
    String? todayIso,
    CalendarDate? today,
    DateTime? todayInstant,
  }) {
    final check = _validateTodayOnlyMutation(
      dateIso: dateIso,
      existingRecord: record,
      todayIso: todayIso,
      today: today,
      todayInstant: todayInstant,
    );
    if (!check.ok) return check.failureResult!;

    final baseRecord = check.baseRecord!;
    final now = _resolveNowIso(nowIso: nowIso, todayInstant: todayInstant);
    final nextStatus = hasTransactions
        ? DailyRhythmFinanceCloseStatuses.closedWithTransactions
        : DailyRhythmFinanceCloseStatuses.closedNoTransactions;

    final updated = baseRecord.copyWith(
      financeCloseStatus: nextStatus,
      financeClosedAt: now,
      updatedAt: now,
    );

    return DailyRhythmMutationResult(
      applied: true,
      reason: DailyRhythmMutationReason.updated,
      record: updated,
    );
  }

  static DailyRhythmMutationResult reopenFinanceDay({
    DailyRhythmDayEntity? record,
    required String dateIso,
    String? nowIso,
    String? todayIso,
    CalendarDate? today,
    DateTime? todayInstant,
  }) {
    final check = _validateTodayOnlyMutation(
      dateIso: dateIso,
      existingRecord: record,
      todayIso: todayIso,
      today: today,
      todayInstant: todayInstant,
    );
    if (!check.ok) return check.failureResult!;

    final baseRecord = check.baseRecord!;
    if (baseRecord.financeCloseStatus == DailyRhythmFinanceCloseStatuses.open) {
      return DailyRhythmMutationResult(
        applied: false,
        reason: DailyRhythmMutationReason.unchanged,
        record: baseRecord,
      );
    }

    final now = _resolveNowIso(nowIso: nowIso, todayInstant: todayInstant);
    final updated = baseRecord.copyWith(
      financeCloseStatus: DailyRhythmFinanceCloseStatuses.open,
      clearFinanceClosedAt: true,
      updatedAt: now,
    );

    return DailyRhythmMutationResult(
      applied: true,
      reason: DailyRhythmMutationReason.updated,
      record: updated,
    );
  }

  /// Reacts to a Finance ledger change (create, edit, or void) on [dateIso].
  ///
  /// Only same-day ledger edits invalidate a closed status (`closed_* -> needs_reconfirmation`).
  /// Historical ledger edits (`dateIso < today`) never rewrite finalized check-ins.
  static DailyRhythmMutationResult applyFinanceLedgerChange({
    DailyRhythmDayEntity? record,
    required String dateIso,
    String? nowIso,
    String? todayIso,
    CalendarDate? today,
    DateTime? todayInstant,
  }) {
    final check = _validateTodayOnlyMutation(
      dateIso: dateIso,
      existingRecord: record,
      todayIso: todayIso,
      today: today,
      todayInstant: todayInstant,
    );
    if (!check.ok) return check.failureResult!;

    final baseRecord = check.baseRecord!;
    final currentFinanceStatus = baseRecord.financeCloseStatus;
    if (!DailyRhythmFinanceCloseStatuses.isClosed(currentFinanceStatus)) {
      return DailyRhythmMutationResult(
        applied: false,
        reason: DailyRhythmMutationReason.unchanged,
        record: baseRecord,
      );
    }

    final now = _resolveNowIso(nowIso: nowIso, todayInstant: todayInstant);
    final updated = baseRecord.copyWith(
      financeCloseStatus: DailyRhythmFinanceCloseStatuses.needsReconfirmation,
      clearFinanceClosedAt: true,
      updatedAt: now,
    );

    return DailyRhythmMutationResult(
      applied: true,
      reason: DailyRhythmMutationReason.updated,
      record: updated,
    );
  }

  static DailyRhythmEvaluatedDay _buildEvaluatedDay({
    required CalendarDate date,
    required DailyRhythmDayEntity record,
    required String status,
    required bool qualifies,
    required bool isToday,
    required bool isProvisionalFreeze,
    required int streakAfterDay,
    required int bestStreakAfterDay,
    required int totalQualifyingDaysAfterDay,
    required int availableFreezesAfterDay,
  }) {
    return DailyRhythmEvaluatedDay(
      dateIso: date.toIsoString(),
      ethiopianDateIso: date.toEthiopian().toIsoString(),
      record: record,
      status: status,
      faithComplete: record.isFaithComplete,
      tasksComplete: record.isTasksComplete,
      financeComplete: record.isFinanceComplete,
      completedResponsibilities: record.completedResponsibilities,
      qualifies: qualifies,
      isToday: isToday,
      isProvisionalFreeze: isProvisionalFreeze,
      streakAfterDay: streakAfterDay,
      bestStreakAfterDay: bestStreakAfterDay,
      totalQualifyingDaysAfterDay: totalQualifyingDaysAfterDay,
      availableFreezesAfterDay: availableFreezesAfterDay,
    );
  }

  static DailyRhythmTimelineSummary evaluateTimeline(
    Iterable<Object?> records, {
    String? todayIso,
    CalendarDate? today,
    DateTime? todayInstant,
  }) {
    final resolvedToday = resolveToday(
      todayIso: todayIso,
      today: today,
      todayInstant: todayInstant,
    );
    final resolvedTodayIso = resolvedToday.toIsoString();
    final todayEthiopianIso = resolvedToday.toEthiopian().toIsoString();
    final normalizedList = normalizeTimeline(records);

    final byDateInput = <String, DailyRhythmDayEntity>{};
    CalendarDate? startDate;

    for (final rec in normalizedList) {
      final recDate = rec.calendarDate;
      if (recDate.isAfter(resolvedToday)) continue;
      byDateInput[rec.dateIso] = rec;
      if (startDate == null && rec.hasAnyActivity) {
        startDate = recDate;
      }
    }

    final todayRecord = byDateInput[resolvedTodayIso] ??
        DailyRhythmDayEntity.empty(resolvedTodayIso);

    if (startDate == null) {
      final todayQualifies = todayRecord.qualifies;
      final todayStatus = todayQualifies
          ? DailyRhythmDayStatuses.complete
          : (todayRecord.hasAnyActivity
              ? DailyRhythmDayStatuses.partial
              : DailyRhythmDayStatuses.untouched);
      final evaluatedToday = _buildEvaluatedDay(
        date: resolvedToday,
        record: todayRecord,
        status: todayStatus,
        qualifies: todayQualifies,
        isToday: true,
        isProvisionalFreeze: false,
        streakAfterDay: 0,
        bestStreakAfterDay: 0,
        totalQualifyingDaysAfterDay: 0,
        availableFreezesAfterDay: 0,
      );
      return DailyRhythmTimelineSummary(
        todayIso: resolvedTodayIso,
        todayEthiopianIso: todayEthiopianIso,
        todayStatus: todayStatus,
        todayRecord: todayRecord,
        todayFaithComplete: evaluatedToday.faithComplete,
        todayTasksComplete: evaluatedToday.tasksComplete,
        todayFinanceComplete: evaluatedToday.financeComplete,
        todayCompletedResponsibilities:
            evaluatedToday.completedResponsibilities,
        isTodayInProgress: !todayQualifies,
        currentStreak: 0,
        bestStreak: 0,
        totalQualifyingDays: 0,
        availableFreezes: 0,
        daysTowardNextFreeze: 0,
        daysUntilNextFreeze: DailyRhythmRules.qualifyingDaysPerFreeze,
        freezesEarnedTotal: 0,
        freezesUsedTotal: 0,
        provisionalFreezeActive: false,
        startDateIso: null,
        days: List<DailyRhythmEvaluatedDay>.unmodifiable([evaluatedToday]),
        byDate: Map<String, DailyRhythmEvaluatedDay>.unmodifiable({
          resolvedTodayIso: evaluatedToday,
        }),
      );
    }

    final totalDays = resolvedToday.differenceInDays(startDate) + 1;
    final evaluatedDays = <DailyRhythmEvaluatedDay>[];
    final evaluatedByDate = <String, DailyRhythmEvaluatedDay>{};

    int currentStreak = 0;
    int bestStreak = 0;
    int totalQualifyingDays = 0;
    int availableFreezes = 0;
    int freezesEarnedTotal = 0;
    int freezesUsedTotal = 0;
    bool provisionalFreezeActive = false;

    for (int offset = 0; offset < totalDays; offset++) {
      final dayDate = startDate.addDays(offset);
      final dayIso = dayDate.toIsoString();
      final record = byDateInput[dayIso] ?? DailyRhythmDayEntity.empty(dayIso);
      final qualifies = record.qualifies;
      final isToday = dayDate.isSameDay(resolvedToday);

      String status;
      bool isProvisionalFreeze = false;

      if (qualifies) {
        status = DailyRhythmDayStatuses.complete;
        currentStreak += 1;
        totalQualifyingDays += 1;
        if (currentStreak > bestStreak) {
          bestStreak = currentStreak;
        }
        const perFreeze = DailyRhythmRules.qualifyingDaysPerFreeze;
        if (totalQualifyingDays % perFreeze == 0) {
          if (availableFreezes < DailyRhythmRules.maxStreakFreezes) {
            availableFreezes += 1;
            freezesEarnedTotal += 1;
          }
        }
      } else if (isToday) {
        status = record.hasAnyActivity
            ? DailyRhythmDayStatuses.partial
            : DailyRhythmDayStatuses.untouched;
      } else {
        // Finished past day (dayDate < resolvedToday) that did not qualify.
        if (currentStreak <= 0) {
          status = DailyRhythmDayStatuses.missed;
          currentStreak = 0;
        } else {
          final nextDay = dayDate.addDays(1);
          final nextIsToday = nextDay.isSameDay(resolvedToday);
          if (nextIsToday) {
            final todayQualifies = todayRecord.qualifies;
            if (availableFreezes > 0) {
              status = DailyRhythmDayStatuses.freezeProtected;
              if (!todayQualifies) {
                isProvisionalFreeze = true;
                provisionalFreezeActive = true;
              }
              availableFreezes -= 1;
              freezesUsedTotal += 1;
            } else {
              status = DailyRhythmDayStatuses.missed;
              currentStreak = 0;
            }
          } else {
            final nextIso = nextDay.toIsoString();
            final nextRecord = byDateInput[nextIso];
            final nextQualifies = nextRecord != null && nextRecord.qualifies;
            if (nextQualifies && availableFreezes > 0) {
              status = DailyRhythmDayStatuses.freezeProtected;
              availableFreezes -= 1;
              freezesUsedTotal += 1;
            } else {
              status = DailyRhythmDayStatuses.missed;
              currentStreak = 0;
            }
          }
        }
      }

      final evaluated = _buildEvaluatedDay(
        date: dayDate,
        record: record,
        status: status,
        qualifies: qualifies,
        isToday: isToday,
        isProvisionalFreeze: isProvisionalFreeze,
        streakAfterDay: currentStreak,
        bestStreakAfterDay: bestStreak,
        totalQualifyingDaysAfterDay: totalQualifyingDays,
        availableFreezesAfterDay: availableFreezes,
      );
      evaluatedDays.add(evaluated);
      evaluatedByDate[dayIso] = evaluated;
    }

    final evaluatedToday = evaluatedByDate[resolvedTodayIso]!;
    final daysTowardNextFreeze =
        totalQualifyingDays % DailyRhythmRules.qualifyingDaysPerFreeze;
    final daysUntilNextFreeze =
        DailyRhythmRules.qualifyingDaysPerFreeze - daysTowardNextFreeze;

    final unmodifiableDays =
        List<DailyRhythmEvaluatedDay>.unmodifiable(evaluatedDays);
    final unmodifiableByDate =
        Map<String, DailyRhythmEvaluatedDay>.unmodifiable(evaluatedByDate);

    return DailyRhythmTimelineSummary(
      todayIso: resolvedTodayIso,
      todayEthiopianIso: todayEthiopianIso,
      todayStatus: evaluatedToday.status,
      todayRecord: evaluatedToday.record,
      todayFaithComplete: evaluatedToday.faithComplete,
      todayTasksComplete: evaluatedToday.tasksComplete,
      todayFinanceComplete: evaluatedToday.financeComplete,
      todayCompletedResponsibilities: evaluatedToday.completedResponsibilities,
      isTodayInProgress: !evaluatedToday.qualifies,
      currentStreak: currentStreak,
      bestStreak: bestStreak,
      totalQualifyingDays: totalQualifyingDays,
      availableFreezes: availableFreezes,
      daysTowardNextFreeze: daysTowardNextFreeze,
      daysUntilNextFreeze: daysUntilNextFreeze,
      freezesEarnedTotal: freezesEarnedTotal,
      freezesUsedTotal: freezesUsedTotal,
      provisionalFreezeActive: provisionalFreezeActive,
      startDateIso: startDate.toIsoString(),
      days: unmodifiableDays,
      byDate: unmodifiableByDate,
    );
  }
}
