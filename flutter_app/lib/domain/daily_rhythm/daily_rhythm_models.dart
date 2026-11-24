import '../../core/date/shared_date.dart';
import '../../core/shared_foundation_core.dart';

/// Canonical Daily Rhythm constants sourced from [SharedDailyRhythmContracts].
class DailyRhythmRules {
  static const int qualifyingDaysPerFreeze =
      SharedDailyRhythmContracts.qualifyingDaysPerFreeze;
  static const int maxStreakFreezes =
      SharedDailyRhythmContracts.maxStreakFreezes;
  static const int maxProtectedGapDays =
      SharedDailyRhythmContracts.maxProtectedGapDays;
  static const String defaultFinanceCloseStatus =
      SharedDailyRhythmContracts.defaultFinanceCloseStatus;
}

class DailyRhythmDayStatuses {
  static const String untouched = 'untouched';
  static const String partial = 'partial';
  static const String complete = 'complete';
  static const String freezeProtected = 'freeze_protected';
  static const String missed = 'missed';

  static List<String> get canonical =>
      SharedDailyRhythmContracts.canonicalDayStatuses;
}

class DailyRhythmFinanceCloseStatuses {
  static const String open = 'open';
  static const String closedWithTransactions = 'closed_with_transactions';
  static const String closedNoTransactions = 'closed_no_transactions';
  static const String needsReconfirmation = 'needs_reconfirmation';

  static List<String> get canonical =>
      SharedDailyRhythmContracts.canonicalFinanceCloseStatuses;

  static String normalize(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (canonical.contains(trimmed)) {
      return trimmed;
    }
    return DailyRhythmRules.defaultFinanceCloseStatus;
  }

  static bool isClosed(String status) {
    return status == closedWithTransactions || status == closedNoTransactions;
  }
}

class DailyRhythmTaskReviewEvidence {
  final int overdueCount;
  final int todayCount;
  final int plannedCount;
  final int completedTodayCount;

  const DailyRhythmTaskReviewEvidence({
    this.overdueCount = 0,
    this.todayCount = 0,
    this.plannedCount = 0,
    this.completedTodayCount = 0,
  });

  factory DailyRhythmTaskReviewEvidence.normalized({
    int overdueCount = 0,
    int todayCount = 0,
    int plannedCount = 0,
    int completedTodayCount = 0,
  }) {
    return DailyRhythmTaskReviewEvidence(
      overdueCount: overdueCount < 0 ? 0 : overdueCount,
      todayCount: todayCount < 0 ? 0 : todayCount,
      plannedCount: plannedCount < 0 ? 0 : plannedCount,
      completedTodayCount: completedTodayCount < 0 ? 0 : completedTodayCount,
    );
  }

  static DailyRhythmTaskReviewEvidence? fromJson(Object? raw) {
    if (raw is! Map) return null;
    int readNonNeg(Object? v) {
      if (v is int) return v < 0 ? 0 : v;
      if (v is num && v.isFinite) {
        final t = v.truncate();
        return t < 0 ? 0 : t;
      }
      return 0;
    }

    return DailyRhythmTaskReviewEvidence(
      overdueCount: readNonNeg(raw['overdueCount']),
      todayCount: readNonNeg(raw['todayCount']),
      plannedCount: readNonNeg(raw['plannedCount']),
      completedTodayCount: readNonNeg(raw['completedTodayCount']),
    );
  }

  Map<String, dynamic> toJson() => {
        'overdueCount': overdueCount,
        'todayCount': todayCount,
        'plannedCount': plannedCount,
        'completedTodayCount': completedTodayCount,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyRhythmTaskReviewEvidence &&
          overdueCount == other.overdueCount &&
          todayCount == other.todayCount &&
          plannedCount == other.plannedCount &&
          completedTodayCount == other.completedTodayCount);

  @override
  int get hashCode => Object.hash(
        overdueCount,
        todayCount,
        plannedCount,
        completedTodayCount,
      );
}

class DailyRhythmDayEntity {
  static const String deterministicEpochIso = '1970-01-01T00:00:00.000Z';

  final String dateIso;
  final bool bibleStudyDone;
  final String? bibleStudyCompletedAt;
  final bool prayerDone;
  final String? prayerCompletedAt;
  final bool taskReviewConfirmed;
  final String? taskReviewedAt;
  final DailyRhythmTaskReviewEvidence? taskReviewEvidence;
  final String financeCloseStatus;
  final String? financeClosedAt;
  final String updatedAt;

  const DailyRhythmDayEntity({
    required this.dateIso,
    this.bibleStudyDone = false,
    this.bibleStudyCompletedAt,
    this.prayerDone = false,
    this.prayerCompletedAt,
    this.taskReviewConfirmed = false,
    this.taskReviewedAt,
    this.taskReviewEvidence,
    this.financeCloseStatus = DailyRhythmFinanceCloseStatuses.open,
    this.financeClosedAt,
    this.updatedAt = deterministicEpochIso,
  });

  factory DailyRhythmDayEntity.empty(
    String dateIso, {
    String updatedAt = deterministicEpochIso,
  }) {
    final parsed = CalendarDate.parse(dateIso);
    final trimmedUpdated = updatedAt.trim();
    final effectiveUpdatedAt =
        trimmedUpdated.isNotEmpty ? trimmedUpdated : deterministicEpochIso;
    return DailyRhythmDayEntity(
      dateIso: parsed.toIsoString(),
      financeCloseStatus: DailyRhythmRules.defaultFinanceCloseStatus,
      updatedAt: effectiveUpdatedAt,
    );
  }

  static DailyRhythmDayEntity? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rawDate = raw['dateIso'];
    if (rawDate is! String) return null;
    final parsedDate = CalendarDate.tryParse(rawDate);
    if (parsedDate == null) return null;

    String? optIso(Object? value) {
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isNotEmpty ? trimmed : null;
    }

    final bibleStudyDone = raw['bibleStudyDone'] == true;
    final prayerDone = raw['prayerDone'] == true;
    final taskReviewConfirmed = raw['taskReviewConfirmed'] == true;
    final rawFinanceStatus = raw['financeCloseStatus'];
    final financeStatus = DailyRhythmFinanceCloseStatuses.normalize(
      rawFinanceStatus is String ? rawFinanceStatus : null,
    );

    return DailyRhythmDayEntity(
      dateIso: parsedDate.toIsoString(),
      bibleStudyDone: bibleStudyDone,
      bibleStudyCompletedAt:
          bibleStudyDone ? optIso(raw['bibleStudyCompletedAt']) : null,
      prayerDone: prayerDone,
      prayerCompletedAt: prayerDone ? optIso(raw['prayerCompletedAt']) : null,
      taskReviewConfirmed: taskReviewConfirmed,
      taskReviewedAt:
          taskReviewConfirmed ? optIso(raw['taskReviewedAt']) : null,
      taskReviewEvidence: taskReviewConfirmed
          ? DailyRhythmTaskReviewEvidence.fromJson(raw['taskReviewEvidence'])
          : null,
      financeCloseStatus: financeStatus,
      financeClosedAt: DailyRhythmFinanceCloseStatuses.isClosed(financeStatus)
          ? optIso(raw['financeClosedAt'])
          : null,
      updatedAt: optIso(raw['updatedAt']) ?? deterministicEpochIso,
    );
  }

  CalendarDate get calendarDate => CalendarDate.parse(dateIso);

  bool get isFaithComplete => bibleStudyDone && prayerDone;

  bool get isTasksComplete => taskReviewConfirmed;

  bool get isFinanceComplete =>
      DailyRhythmFinanceCloseStatuses.isClosed(financeCloseStatus);

  int get completedResponsibilities {
    int count = 0;
    if (isFaithComplete) count += 1;
    if (isTasksComplete) count += 1;
    if (isFinanceComplete) count += 1;
    return count;
  }

  bool get qualifies => isFaithComplete && isTasksComplete && isFinanceComplete;

  bool get hasAnyActivity =>
      bibleStudyDone ||
      prayerDone ||
      taskReviewConfirmed ||
      financeCloseStatus != DailyRhythmRules.defaultFinanceCloseStatus;

  DailyRhythmDayEntity copyWith({
    String? dateIso,
    bool? bibleStudyDone,
    String? bibleStudyCompletedAt,
    bool clearBibleStudyCompletedAt = false,
    bool? prayerDone,
    String? prayerCompletedAt,
    bool clearPrayerCompletedAt = false,
    bool? taskReviewConfirmed,
    String? taskReviewedAt,
    bool clearTaskReviewedAt = false,
    DailyRhythmTaskReviewEvidence? taskReviewEvidence,
    bool clearTaskReviewEvidence = false,
    String? financeCloseStatus,
    String? financeClosedAt,
    bool clearFinanceClosedAt = false,
    String? updatedAt,
  }) {
    return DailyRhythmDayEntity(
      dateIso: dateIso ?? this.dateIso,
      bibleStudyDone: bibleStudyDone ?? this.bibleStudyDone,
      bibleStudyCompletedAt: clearBibleStudyCompletedAt
          ? null
          : (bibleStudyCompletedAt ?? this.bibleStudyCompletedAt),
      prayerDone: prayerDone ?? this.prayerDone,
      prayerCompletedAt: clearPrayerCompletedAt
          ? null
          : (prayerCompletedAt ?? this.prayerCompletedAt),
      taskReviewConfirmed: taskReviewConfirmed ?? this.taskReviewConfirmed,
      taskReviewedAt:
          clearTaskReviewedAt ? null : (taskReviewedAt ?? this.taskReviewedAt),
      taskReviewEvidence: clearTaskReviewEvidence
          ? null
          : (taskReviewEvidence ?? this.taskReviewEvidence),
      financeCloseStatus: financeCloseStatus ?? this.financeCloseStatus,
      financeClosedAt: clearFinanceClosedAt
          ? null
          : (financeClosedAt ?? this.financeClosedAt),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'dateIso': dateIso,
        'bibleStudyDone': bibleStudyDone,
        if (bibleStudyCompletedAt != null)
          'bibleStudyCompletedAt': bibleStudyCompletedAt,
        'prayerDone': prayerDone,
        if (prayerCompletedAt != null) 'prayerCompletedAt': prayerCompletedAt,
        'taskReviewConfirmed': taskReviewConfirmed,
        if (taskReviewedAt != null) 'taskReviewedAt': taskReviewedAt,
        if (taskReviewEvidence != null)
          'taskReviewEvidence': taskReviewEvidence!.toJson(),
        'financeCloseStatus': financeCloseStatus,
        if (financeClosedAt != null) 'financeClosedAt': financeClosedAt,
        'updatedAt': updatedAt,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyRhythmDayEntity &&
          dateIso == other.dateIso &&
          bibleStudyDone == other.bibleStudyDone &&
          bibleStudyCompletedAt == other.bibleStudyCompletedAt &&
          prayerDone == other.prayerDone &&
          prayerCompletedAt == other.prayerCompletedAt &&
          taskReviewConfirmed == other.taskReviewConfirmed &&
          taskReviewedAt == other.taskReviewedAt &&
          taskReviewEvidence == other.taskReviewEvidence &&
          financeCloseStatus == other.financeCloseStatus &&
          financeClosedAt == other.financeClosedAt &&
          updatedAt == other.updatedAt);

  @override
  int get hashCode => Object.hash(
        dateIso,
        bibleStudyDone,
        bibleStudyCompletedAt,
        prayerDone,
        prayerCompletedAt,
        taskReviewConfirmed,
        taskReviewedAt,
        taskReviewEvidence,
        financeCloseStatus,
        financeClosedAt,
        updatedAt,
      );
}

enum DailyRhythmMutationReason {
  updated,
  pastDayLocked,
  futureDayLocked,
  unchanged,
  invalidDate,
}

class DailyRhythmMutationResult {
  final bool applied;
  final DailyRhythmMutationReason reason;
  final DailyRhythmDayEntity record;

  const DailyRhythmMutationResult({
    required this.applied,
    required this.reason,
    required this.record,
  });
}

class DailyRhythmEvaluatedDay {
  final String dateIso;
  final String ethiopianDateIso;
  final DailyRhythmDayEntity record;
  final String status;
  final bool faithComplete;
  final bool tasksComplete;
  final bool financeComplete;
  final int completedResponsibilities;
  final bool qualifies;
  final bool isToday;
  final bool isProvisionalFreeze;
  final int streakAfterDay;
  final int bestStreakAfterDay;
  final int totalQualifyingDaysAfterDay;
  final int availableFreezesAfterDay;

  const DailyRhythmEvaluatedDay({
    required this.dateIso,
    required this.ethiopianDateIso,
    required this.record,
    required this.status,
    required this.faithComplete,
    required this.tasksComplete,
    required this.financeComplete,
    required this.completedResponsibilities,
    required this.qualifies,
    required this.isToday,
    required this.isProvisionalFreeze,
    required this.streakAfterDay,
    required this.bestStreakAfterDay,
    required this.totalQualifyingDaysAfterDay,
    required this.availableFreezesAfterDay,
  });
}

class DailyRhythmTimelineSummary {
  final String todayIso;
  final String todayEthiopianIso;
  final String todayStatus;
  final DailyRhythmDayEntity todayRecord;
  final bool todayFaithComplete;
  final bool todayTasksComplete;
  final bool todayFinanceComplete;
  final int todayCompletedResponsibilities;
  final bool isTodayInProgress;
  final int currentStreak;
  final int bestStreak;
  final int totalQualifyingDays;
  final int availableFreezes;
  final int daysTowardNextFreeze;
  final int daysUntilNextFreeze;
  final int freezesEarnedTotal;
  final int freezesUsedTotal;
  final bool provisionalFreezeActive;
  final String? startDateIso;
  final List<DailyRhythmEvaluatedDay> days;
  final Map<String, DailyRhythmEvaluatedDay> byDate;

  const DailyRhythmTimelineSummary({
    required this.todayIso,
    required this.todayEthiopianIso,
    required this.todayStatus,
    required this.todayRecord,
    required this.todayFaithComplete,
    required this.todayTasksComplete,
    required this.todayFinanceComplete,
    required this.todayCompletedResponsibilities,
    required this.isTodayInProgress,
    required this.currentStreak,
    required this.bestStreak,
    required this.totalQualifyingDays,
    required this.availableFreezes,
    required this.daysTowardNextFreeze,
    required this.daysUntilNextFreeze,
    required this.freezesEarnedTotal,
    required this.freezesUsedTotal,
    required this.provisionalFreezeActive,
    required this.startDateIso,
    required this.days,
    required this.byDate,
  });
}
