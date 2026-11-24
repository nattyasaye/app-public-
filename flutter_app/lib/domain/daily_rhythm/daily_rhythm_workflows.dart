import '../../core/date/shared_date.dart';
import '../finance/double_entry_engine.dart';
import '../tasks/daily_planning_engine.dart';
import '../tasks/task_models.dart';
import './daily_rhythm_engine.dart';
import './daily_rhythm_models.dart';

enum DailyRhythmResponsibility {
  faith,
  tasks,
  finance,
}

enum DailyRhythmFaithStep {
  bibleStudy,
  prayer,
}

enum DailyRhythmCalendarDisplayStatus {
  complete,
  partial,
  freezeProtected,
  missed,
  untouched,
  unrecorded,
}

class DailyRhythmDashboardOverview {
  final String todayIso;
  final String todayEthiopianIso;
  final String todayStatus;
  final DailyRhythmDayEntity todayRecord;
  final int completedResponsibilities;
  final int totalResponsibilities;
  final double progressFraction;
  final bool isDayQualified;
  final bool isTodayInProgress;
  final String overallStatusLabel;
  final String overallStatusDescription;
  final DailyRhythmResponsibility? nextIncompleteResponsibility;
  final String nextActionTitle;
  final String nextActionDescription;
  final String nextActionButtonLabel;

  // Faith
  final bool faithComplete;
  final int faithCompletedCount;
  final String faithProgressLabel;
  final bool bibleStudyDone;
  final bool prayerDone;
  final DailyRhythmFaithStep? nextFaithStep;
  final String faithStatusLabel;
  final String faithActionLabel;

  // Tasks
  final bool tasksComplete;
  final String tasksStatusLabel;
  final String tasksContextLabel;
  final String tasksActionLabel;
  final int tasksOverdueCount;
  final int tasksTodayCount;
  final int tasksPlannedCount;
  final int tasksCompletedTodayCount;

  // Finance
  final bool financeComplete;
  final String financeCloseStatus;
  final bool financeNeedsReconfirmation;
  final int financeTodayTransactionCount;
  final String financeStatusLabel;
  final String financeContextLabel;
  final String financeActionLabel;

  // Streaks & freezes
  final int currentStreak;
  final int bestStreak;
  final int totalQualifyingDays;
  final int availableFreezes;
  final int maxFreezes;
  final int qualifyingDaysPerFreeze;
  final int daysTowardNextFreeze;
  final int daysUntilNextFreeze;
  final double nextFreezeProgressFraction;
  final bool provisionalFreezeActive;
  final String? provisionalFreezeDateIso;
  final int finalizedFreezesUsed;
  final String freezeStatusSummary;
  final List<String> freezeRules;

  const DailyRhythmDashboardOverview({
    required this.todayIso,
    required this.todayEthiopianIso,
    required this.todayStatus,
    required this.todayRecord,
    required this.completedResponsibilities,
    required this.totalResponsibilities,
    required this.progressFraction,
    required this.isDayQualified,
    required this.isTodayInProgress,
    required this.overallStatusLabel,
    required this.overallStatusDescription,
    required this.nextIncompleteResponsibility,
    required this.nextActionTitle,
    required this.nextActionDescription,
    required this.nextActionButtonLabel,
    required this.faithComplete,
    required this.faithCompletedCount,
    required this.faithProgressLabel,
    required this.bibleStudyDone,
    required this.prayerDone,
    required this.nextFaithStep,
    required this.faithStatusLabel,
    required this.faithActionLabel,
    required this.tasksComplete,
    required this.tasksStatusLabel,
    required this.tasksContextLabel,
    required this.tasksActionLabel,
    required this.tasksOverdueCount,
    required this.tasksTodayCount,
    required this.tasksPlannedCount,
    required this.tasksCompletedTodayCount,
    required this.financeComplete,
    required this.financeCloseStatus,
    required this.financeNeedsReconfirmation,
    required this.financeTodayTransactionCount,
    required this.financeStatusLabel,
    required this.financeContextLabel,
    required this.financeActionLabel,
    required this.currentStreak,
    required this.bestStreak,
    required this.totalQualifyingDays,
    required this.availableFreezes,
    required this.maxFreezes,
    required this.qualifyingDaysPerFreeze,
    required this.daysTowardNextFreeze,
    required this.daysUntilNextFreeze,
    required this.nextFreezeProgressFraction,
    required this.provisionalFreezeActive,
    required this.provisionalFreezeDateIso,
    required this.finalizedFreezesUsed,
    required this.freezeStatusSummary,
    required this.freezeRules,
  });
}

class DailyRhythmCalendarDayInspection {
  final String dateIso;
  final String ethiopianDateIso;
  final bool isToday;
  final bool isFuture;
  final bool isBeforeTrackingStart;
  final bool hasRecordedHistory;
  final DailyRhythmCalendarDisplayStatus calendarStatus;
  final bool isProvisionalFreeze;
  final String shortMarkerGlyph;
  final String statusLabel;
  final String accessibleLabel;
  final String detailSummary;
  final int completedResponsibilities;
  final bool faithComplete;
  final bool bibleStudyDone;
  final String? bibleStudyCompletedAt;
  final bool prayerDone;
  final String? prayerCompletedAt;
  final bool tasksComplete;
  final bool taskReviewConfirmed;
  final String? taskReviewedAt;
  final DailyRhythmTaskReviewEvidence? taskReviewEvidence;
  final bool financeComplete;
  final String financeCloseStatus;
  final String? financeClosedAt;
  final String financeStatusLabel;
  final String? freezeExplanation;
  final String? lockNotice;

  const DailyRhythmCalendarDayInspection({
    required this.dateIso,
    required this.ethiopianDateIso,
    required this.isToday,
    required this.isFuture,
    required this.isBeforeTrackingStart,
    required this.hasRecordedHistory,
    required this.calendarStatus,
    required this.isProvisionalFreeze,
    required this.shortMarkerGlyph,
    required this.statusLabel,
    required this.accessibleLabel,
    required this.detailSummary,
    required this.completedResponsibilities,
    required this.faithComplete,
    required this.bibleStudyDone,
    required this.bibleStudyCompletedAt,
    required this.prayerDone,
    required this.prayerCompletedAt,
    required this.tasksComplete,
    required this.taskReviewConfirmed,
    required this.taskReviewedAt,
    required this.taskReviewEvidence,
    required this.financeComplete,
    required this.financeCloseStatus,
    required this.financeClosedAt,
    required this.financeStatusLabel,
    required this.freezeExplanation,
    required this.lockNotice,
  });
}

class DailyRhythmTaskReviewSnapshot {
  final String targetDateIso;
  final String todayIso;
  final DailyRhythmTaskReviewEvidence evidence;
  final List<TaskEntity> overdueTasks;
  final List<TaskEntity> todayTasks;
  final List<TaskEntity> plannedTasks;
  final List<TaskEntity> attentionTasks;
  final List<TaskEntity> completedTodayTasks;
  final bool hasRelevantTasks;
  final String confirmActionLabel;

  const DailyRhythmTaskReviewSnapshot({
    required this.targetDateIso,
    required this.todayIso,
    required this.evidence,
    required this.overdueTasks,
    required this.todayTasks,
    required this.plannedTasks,
    required this.attentionTasks,
    required this.completedTodayTasks,
    required this.hasRelevantTasks,
    required this.confirmActionLabel,
  });
}

class DailyRhythmFinanceDaySummary {
  final String targetDateIso;
  final int transactionCount;
  final List<JournalEntryModel> todayEntries;
  final bool hasTransactions;
  final String confirmActionLabel;

  const DailyRhythmFinanceDaySummary({
    required this.targetDateIso,
    required this.transactionCount,
    required this.todayEntries,
    required this.hasTransactions,
    required this.confirmActionLabel,
  });
}

/// Pure Daily Rhythm module-workflow helpers aligning Tasks daily review and
/// Finance daily close semantics between Dart and TypeScript.
class DailyRhythmWorkflows {
  static const Map<String, int> _priorityRank = {
    'urgent': 0,
    'high': 1,
    'medium': 2,
    'low': 3,
  };

  static ({CalendarDate target, CalendarDate today}) _resolveTargetDates({
    String? targetDateIso,
    String? todayIso,
    CalendarDate? today,
    DateTime? todayInstant,
  }) {
    final resolvedToday = DailyRhythmEngine.resolveToday(
      todayIso: todayIso,
      today: today,
      todayInstant: todayInstant,
    );
    if (targetDateIso != null) {
      final parsed = CalendarDate.tryParse(targetDateIso);
      if (parsed != null) {
        return (target: parsed, today: resolvedToday);
      }
    }
    return (target: resolvedToday, today: resolvedToday);
  }

  static bool _isTaskCompletedOnDate(
    TaskEntity task,
    List<DailyPlanningEntryEntity> planningEntries,
    CalendarDate targetDate,
  ) {
    if (!task.isCompleted) return false;
    if (task.completedAt != null) {
      final completedDate = CalendarDate.fromUtcInstantInEthiopia(
        task.completedAt!,
      );
      if (completedDate == targetDate) return true;
    }
    final entry =
        DailyPlanningEngine.findEntry(planningEntries, task.id, targetDate);
    return entry?.action == DailyPlanningActions.completed;
  }

  static int _compareAttentionTasks(
    TaskEntity a,
    TaskEntity b,
    CalendarDate targetDate,
    Set<String> plannedIds,
  ) {
    final overdueA = (a.dueDate != null && a.dueDate!.isBefore(targetDate))
        ? 0
        : 1;
    final overdueB = (b.dueDate != null && b.dueDate!.isBefore(targetDate))
        ? 0
        : 1;
    if (overdueA != overdueB) return overdueA.compareTo(overdueB);

    final plannedA = plannedIds.contains(a.id) ? 0 : 1;
    final plannedB = plannedIds.contains(b.id) ? 0 : 1;
    if (plannedA != plannedB) return plannedA.compareTo(plannedB);

    final prioA = _priorityRank[a.priority] ?? 2;
    final prioB = _priorityRank[b.priority] ?? 2;
    if (prioA != prioB) return prioA.compareTo(prioB);

    final dueA = a.dueDate?.toIsoString() ?? '9999-12-31';
    final dueB = b.dueDate?.toIsoString() ?? '9999-12-31';
    if (dueA != dueB) return dueA.compareTo(dueB);

    return a.title.compareTo(b.title);
  }

  static DailyRhythmTaskReviewSnapshot buildTaskReviewSnapshot({
    required List<TaskEntity> tasks,
    required List<DailyPlanningEntryEntity> planningEntries,
    String? targetDateIso,
    String? todayIso,
    CalendarDate? today,
    DateTime? todayInstant,
  }) {
    final dates = _resolveTargetDates(
      targetDateIso: targetDateIso,
      todayIso: todayIso,
      today: today,
      todayInstant: todayInstant,
    );
    final targetDate = dates.target;
    final resolvedToday = dates.today;

    final overdueTasks = <TaskEntity>[];
    final todayTasks = <TaskEntity>[];
    final plannedTasks = <TaskEntity>[];
    final completedTodayTasks = <TaskEntity>[];

    for (final task in tasks) {
      if (task.isArchived || task.status == 'cancelled') continue;
      if (task.isCompleted) {
        if (_isTaskCompletedOnDate(task, planningEntries, targetDate)) {
          completedTodayTasks.add(task);
        }
        continue;
      }

      if (task.dueDate != null && task.dueDate!.isBefore(targetDate)) {
        overdueTasks.add(task);
      }
      if (task.dueDate == targetDate || task.scheduledDate == targetDate) {
        todayTasks.add(task);
      }
      if (DailyPlanningEngine.isTaskPlannedForDate(
        task,
        planningEntries,
        targetDate,
        today: resolvedToday,
      )) {
        plannedTasks.add(task);
      }
    }

    final plannedIds = {for (final t in plannedTasks) t.id};
    final seenIds = <String>{};
    final attentionTasks = <TaskEntity>[];
    for (final list in [overdueTasks, plannedTasks, todayTasks]) {
      for (final task in list) {
        if (seenIds.add(task.id)) {
          attentionTasks.add(task);
        }
      }
    }
    attentionTasks.sort(
      (a, b) => _compareAttentionTasks(a, b, targetDate, plannedIds),
    );

    final hasRelevantTasks = attentionTasks.isNotEmpty;

    return DailyRhythmTaskReviewSnapshot(
      targetDateIso: targetDate.toIsoString(),
      todayIso: resolvedToday.toIsoString(),
      evidence: DailyRhythmTaskReviewEvidence.normalized(
        overdueCount: overdueTasks.length,
        todayCount: todayTasks.length,
        plannedCount: plannedTasks.length,
        completedTodayCount: completedTodayTasks.length,
      ),
      overdueTasks: List<TaskEntity>.unmodifiable(overdueTasks),
      todayTasks: List<TaskEntity>.unmodifiable(todayTasks),
      plannedTasks: List<TaskEntity>.unmodifiable(plannedTasks),
      attentionTasks: List<TaskEntity>.unmodifiable(attentionTasks),
      completedTodayTasks: List<TaskEntity>.unmodifiable(completedTodayTasks),
      hasRelevantTasks: hasRelevantTasks,
      confirmActionLabel:
          hasRelevantTasks ? 'Confirm daily review' : 'Confirm clear day',
    );
  }

  static DailyRhythmFinanceDaySummary inspectFinanceDay({
    required List<JournalEntryModel> entries,
    String? targetDateIso,
    String? todayIso,
    CalendarDate? today,
    DateTime? todayInstant,
  }) {
    final dates = _resolveTargetDates(
      targetDateIso: targetDateIso,
      todayIso: todayIso,
      today: today,
      todayInstant: todayInstant,
    );
    final targetIso = dates.target.toIsoString();
    final todayEntries = entries
        .where((e) => !e.isVoided && e.occurrenceDate == targetIso)
        .toList(growable: false);
    final hasTransactions = todayEntries.isNotEmpty;
    return DailyRhythmFinanceDaySummary(
      targetDateIso: targetIso,
      transactionCount: todayEntries.length,
      todayEntries: List<JournalEntryModel>.unmodifiable(todayEntries),
      hasTransactions: hasTransactions,
      confirmActionLabel: hasTransactions
          ? "I've reviewed today's transactions"
          : 'No transactions today',
    );
  }

  static List<String> _buildDateLedgerSignatures(
    List<JournalEntryModel> entries,
    List<PostingModel> postings,
    String targetIso,
  ) {
    final postingsByEntry = <String, List<PostingModel>>{};
    final affectedIds = <String>{};

    for (final p in postings) {
      postingsByEntry.putIfAbsent(p.entryId, () => []).add(p);
      if (p.accountMovementDate == targetIso) {
        affectedIds.add(p.entryId);
      }
    }

    for (final e in entries) {
      if (e.occurrenceDate == targetIso) {
        affectedIds.add(e.id);
      }
    }

    final signatures = <String>[];
    for (final entry in entries) {
      if (!affectedIds.contains(entry.id)) continue;
      final postingSigs = (postingsByEntry[entry.id] ?? const <PostingModel>[])
          .map(
            (p) => [
              p.id,
              p.accountId,
              p.direction.name,
              p.amountCents.toString(),
              p.categoryId ?? '',
              p.accountMovementDate,
            ].join('|'),
          )
          .toList()
        ..sort();
      signatures.add(
        [
          entry.id,
          entry.entryType.dbValue,
          entry.isVoided ? '1' : '0',
          entry.occurrenceDate,
          entry.description,
          entry.correctedFromEntryId ?? '',
          postingSigs.join(';'),
        ].join('::'),
      );
    }
    signatures.sort();
    return signatures;
  }

  /// Returns true strictly when a Finance ledger mutation added, removed,
  /// voided, unvoided, replaced, or modified an entry or posting touching [targetDateIso].
  static bool didLedgerChangeAffectDate({
    required List<JournalEntryModel> prevEntries,
    required List<PostingModel> prevPostings,
    required List<JournalEntryModel> nextEntries,
    required List<PostingModel> nextPostings,
    String? targetDateIso,
    String? todayIso,
    CalendarDate? today,
    DateTime? todayInstant,
  }) {
    final dates = _resolveTargetDates(
      targetDateIso: targetDateIso,
      todayIso: todayIso,
      today: today,
      todayInstant: todayInstant,
    );
    final targetIso = dates.target.toIsoString();
    final prevSigs =
        _buildDateLedgerSignatures(prevEntries, prevPostings, targetIso);
    final nextSigs =
        _buildDateLedgerSignatures(nextEntries, nextPostings, targetIso);
    if (prevSigs.length != nextSigs.length) return true;
    for (var i = 0; i < prevSigs.length; i += 1) {
      if (prevSigs[i] != nextSigs[i]) return true;
    }
    return false;
  }

  static const List<String> freezeRules = <String>[
    'A freeze protects one isolated missed day between qualifying days.',
    'A protected day preserves streak continuity but does not count as a qualifying day.',
    'Multiple consecutive missed days cannot be protected.',
    'Incomplete responsibilities today do not mean today has already been missed.',
    'Provisional freeze protection finalizes only if today qualifies; otherwise the day reverts to missed.',
  ];

  static String formatFinanceCloseLabel(String status) {
    switch (status) {
      case DailyRhythmFinanceCloseStatuses.closedWithTransactions:
        return 'Reviewed transactions';
      case DailyRhythmFinanceCloseStatuses.closedNoTransactions:
        return 'Confirmed no transactions';
      case DailyRhythmFinanceCloseStatuses.needsReconfirmation:
        return 'Needs reconfirmation';
      case DailyRhythmFinanceCloseStatuses.open:
      default:
        return 'Unreviewed today';
    }
  }

  static DailyRhythmDashboardOverview buildDashboardOverview({
    required DailyRhythmTimelineSummary timelineSummary,
    required DailyRhythmTaskReviewSnapshot taskSnapshot,
    required DailyRhythmFinanceDaySummary financeSummary,
  }) {
    final todayRecord = timelineSummary.todayRecord;
    final completed = timelineSummary.todayCompletedResponsibilities;
    final isQualified =
        timelineSummary.todayStatus == DailyRhythmDayStatuses.complete;

    final faithCompletedCount =
        (todayRecord.bibleStudyDone ? 1 : 0) + (todayRecord.prayerDone ? 1 : 0);
    final DailyRhythmFaithStep? nextFaithStep;
    if (!todayRecord.bibleStudyDone) {
      nextFaithStep = DailyRhythmFaithStep.bibleStudy;
    } else if (!todayRecord.prayerDone) {
      nextFaithStep = DailyRhythmFaithStep.prayer;
    } else {
      nextFaithStep = null;
    }

    final faithStatusLabel = timelineSummary.todayFaithComplete
        ? '2/2 Complete'
        : '$faithCompletedCount/2 complete';
    final faithActionLabel = switch (nextFaithStep) {
      DailyRhythmFaithStep.bibleStudy => 'Complete Bible study',
      DailyRhythmFaithStep.prayer => 'Complete prayer',
      null => 'Open Faith',
    };

    final ev = taskSnapshot.evidence;
    final tasksStatusLabel = timelineSummary.todayTasksComplete
        ? 'Daily review confirmed'
        : 'Needs daily review';
    final tasksContextParts = <String>[];
    if (ev.overdueCount > 0) {
      tasksContextParts.add('${ev.overdueCount} overdue');
    }
    if (ev.todayCount > 0) {
      tasksContextParts.add('${ev.todayCount} due/scheduled');
    }
    if (ev.plannedCount > 0) {
      tasksContextParts.add('${ev.plannedCount} My Day');
    }
    final String tasksContextLabel;
    if (tasksContextParts.isNotEmpty) {
      tasksContextLabel = tasksContextParts.join(' · ');
    } else if (ev.completedTodayCount > 0) {
      tasksContextLabel = '${ev.completedTodayCount} completed today';
    } else {
      tasksContextLabel = 'Clear day · no urgent tasks';
    }
    final tasksActionLabel = timelineSummary.todayTasksComplete
        ? 'View review'
        : 'Open daily review';

    final financeNeedsReconfirmation = todayRecord.financeCloseStatus ==
        DailyRhythmFinanceCloseStatuses.needsReconfirmation;
    final financeStatusLabel =
        formatFinanceCloseLabel(todayRecord.financeCloseStatus);
    final financeContextLabel = financeSummary.hasTransactions
        ? '${financeSummary.transactionCount} active entry(s) today'
        : 'No active transactions today';
    final String financeActionLabel;
    if (financeNeedsReconfirmation) {
      financeActionLabel = 'Reconfirm review';
    } else if (timelineSummary.todayFinanceComplete) {
      financeActionLabel = 'View Finance';
    } else {
      financeActionLabel = 'Review & close';
    }

    final DailyRhythmResponsibility? nextIncompleteResponsibility;
    if (!timelineSummary.todayFaithComplete) {
      nextIncompleteResponsibility = DailyRhythmResponsibility.faith;
    } else if (!timelineSummary.todayTasksComplete) {
      nextIncompleteResponsibility = DailyRhythmResponsibility.tasks;
    } else if (!timelineSummary.todayFinanceComplete) {
      nextIncompleteResponsibility = DailyRhythmResponsibility.finance;
    } else {
      nextIncompleteResponsibility = null;
    }

    final String overallStatusLabel;
    final String overallStatusDescription;
    if (isQualified) {
      overallStatusLabel = 'Day qualified · 3/3';
      overallStatusDescription =
          'All three daily responsibilities are complete for today.';
    } else if (financeNeedsReconfirmation) {
      overallStatusLabel = 'Needs reconfirmation · $completed/3';
      overallStatusDescription =
          "Today's Finance ledger changed after closing. Reconfirm Finance alongside your remaining checks; partial progress does not qualify today yet.";
    } else if (completed > 0 ||
        todayRecord.bibleStudyDone ||
        todayRecord.prayerDone) {
      overallStatusLabel = 'In progress · $completed/3';
      overallStatusDescription =
          'Partial progress is saved. Complete all three responsibilities for today to qualify.';
    } else {
      overallStatusLabel = 'Open · 0/3';
      overallStatusDescription =
          'Today is open and still in progress — incomplete steps do not mean today has been missed.';
    }

    final String nextActionTitle;
    final String nextActionDescription;
    final String nextActionButtonLabel;
    switch (nextIncompleteResponsibility) {
      case DailyRhythmResponsibility.faith:
        nextActionTitle = nextFaithStep == DailyRhythmFaithStep.bibleStudy
            ? 'Next: Bible study'
            : 'Next: Prayer';
        nextActionDescription = faithCompletedCount == 1
            ? 'One Faith step left so Faith counts toward today (2/2).'
            : 'Complete Bible study and prayer independently to qualify Faith.';
        nextActionButtonLabel = faithActionLabel;
        break;
      case DailyRhythmResponsibility.tasks:
        nextActionTitle = 'Next: Daily task review';
        nextActionDescription =
            '$tasksContextLabel. Confirm your review in Tasks without needing to finish every task.';
        nextActionButtonLabel = tasksActionLabel;
        break;
      case DailyRhythmResponsibility.finance:
        nextActionTitle = financeNeedsReconfirmation
            ? 'Next: Reconfirm Finance close'
            : 'Next: Daily Finance review';
        nextActionDescription = financeNeedsReconfirmation
            ? "Today's transactions changed after closing. Reconfirm in Finance."
            : '$financeContextLabel. Explicit confirmation closes Finance for today.';
        nextActionButtonLabel = financeActionLabel;
        break;
      case null:
        nextActionTitle = 'Today is complete';
        nextActionDescription =
            'Faith, Daily Task Review, and Daily Finance Close are all confirmed for today.';
        nextActionButtonLabel = 'Review history';
        break;
    }

    DailyRhythmEvaluatedDay? provisionalDay;
    var finalizedFreezesUsed = 0;
    for (final day in timelineSummary.days) {
      if (day.status == DailyRhythmDayStatuses.freezeProtected) {
        if (day.isProvisionalFreeze) {
          provisionalDay ??= day;
        } else {
          finalizedFreezesUsed += 1;
        }
      }
    }

    final String freezeStatusSummary;
    if (timelineSummary.provisionalFreezeActive) {
      freezeStatusSummary =
          'Provisional freeze active on ${provisionalDay?.dateIso ?? 'yesterday'}: your streak stays intact while today is in progress. Qualify today to finalize that spent freeze, or it becomes missed tomorrow.';
    } else if (timelineSummary.availableFreezes > 0) {
      freezeStatusSummary =
          '${timelineSummary.availableFreezes} freeze(s) ready (max ${DailyRhythmRules.maxStreakFreezes}). Earn 1 every ${DailyRhythmRules.qualifyingDaysPerFreeze} qualifying days (${timelineSummary.daysTowardNextFreeze}/${DailyRhythmRules.qualifyingDaysPerFreeze} toward next).';
    } else if (finalizedFreezesUsed > 0) {
      freezeStatusSummary =
          '0 freezes available ($finalizedFreezesUsed spent on past single-day gaps). ${timelineSummary.daysTowardNextFreeze}/${DailyRhythmRules.qualifyingDaysPerFreeze} qualifying days toward your next freeze.';
    } else {
      freezeStatusSummary =
          '${timelineSummary.daysTowardNextFreeze}/${DailyRhythmRules.qualifyingDaysPerFreeze} qualifying days toward your first freeze (max ${DailyRhythmRules.maxStreakFreezes}).';
    }

    final freezeRatio = timelineSummary.daysTowardNextFreeze /
        DailyRhythmRules.qualifyingDaysPerFreeze;
    final nextFreezeProgressFraction = freezeRatio.clamp(0.0, 1.0);

    return DailyRhythmDashboardOverview(
      todayIso: timelineSummary.todayIso,
      todayEthiopianIso: timelineSummary.todayEthiopianIso,
      todayStatus: timelineSummary.todayStatus,
      todayRecord: todayRecord,
      completedResponsibilities: completed,
      totalResponsibilities: 3,
      progressFraction: (completed / 3.0).clamp(0.0, 1.0),
      isDayQualified: isQualified,
      isTodayInProgress: timelineSummary.isTodayInProgress,
      overallStatusLabel: overallStatusLabel,
      overallStatusDescription: overallStatusDescription,
      nextIncompleteResponsibility: nextIncompleteResponsibility,
      nextActionTitle: nextActionTitle,
      nextActionDescription: nextActionDescription,
      nextActionButtonLabel: nextActionButtonLabel,
      faithComplete: timelineSummary.todayFaithComplete,
      faithCompletedCount: faithCompletedCount,
      faithProgressLabel: '$faithCompletedCount/2',
      bibleStudyDone: todayRecord.bibleStudyDone,
      prayerDone: todayRecord.prayerDone,
      nextFaithStep: nextFaithStep,
      faithStatusLabel: faithStatusLabel,
      faithActionLabel: faithActionLabel,
      tasksComplete: timelineSummary.todayTasksComplete,
      tasksStatusLabel: tasksStatusLabel,
      tasksContextLabel: tasksContextLabel,
      tasksActionLabel: tasksActionLabel,
      tasksOverdueCount: ev.overdueCount,
      tasksTodayCount: ev.todayCount,
      tasksPlannedCount: ev.plannedCount,
      tasksCompletedTodayCount: ev.completedTodayCount,
      financeComplete: timelineSummary.todayFinanceComplete,
      financeCloseStatus: todayRecord.financeCloseStatus,
      financeNeedsReconfirmation: financeNeedsReconfirmation,
      financeTodayTransactionCount: financeSummary.transactionCount,
      financeStatusLabel: financeStatusLabel,
      financeContextLabel: financeContextLabel,
      financeActionLabel: financeActionLabel,
      currentStreak: timelineSummary.currentStreak,
      bestStreak: timelineSummary.bestStreak,
      totalQualifyingDays: timelineSummary.totalQualifyingDays,
      availableFreezes: timelineSummary.availableFreezes,
      maxFreezes: DailyRhythmRules.maxStreakFreezes,
      qualifyingDaysPerFreeze: DailyRhythmRules.qualifyingDaysPerFreeze,
      daysTowardNextFreeze: timelineSummary.daysTowardNextFreeze,
      daysUntilNextFreeze: timelineSummary.daysUntilNextFreeze,
      nextFreezeProgressFraction: nextFreezeProgressFraction,
      provisionalFreezeActive: timelineSummary.provisionalFreezeActive,
      provisionalFreezeDateIso: provisionalDay?.dateIso,
      finalizedFreezesUsed: finalizedFreezesUsed,
      freezeStatusSummary: freezeStatusSummary,
      freezeRules: freezeRules,
    );
  }

  static DailyRhythmCalendarDayInspection describeCalendarDay({
    required String dateIso,
    required DailyRhythmTimelineSummary timelineSummary,
  }) {
    final parsed = CalendarDate.tryParse(dateIso);
    final canonicalIso = parsed?.toIsoString() ?? dateIso;
    final ethDate = parsed?.toEthiopian();
    final ethiopianDateIso = ethDate != null
        ? '${ethDate.year}-${ethDate.month.toString().padLeft(2, '0')}-${ethDate.day.toString().padLeft(2, '0')}'
        : '';

    final evaluated = timelineSummary.byDate[canonicalIso];
    final isToday = canonicalIso == timelineSummary.todayIso;
    final isFuture = canonicalIso.compareTo(timelineSummary.todayIso) > 0;
    final isBeforeTrackingStart = !isToday &&
        !isFuture &&
        (timelineSummary.startDateIso == null ||
            canonicalIso.compareTo(timelineSummary.startDateIso!) < 0);

    if (evaluated == null) {
      final empty = DailyRhythmDayEntity.empty(canonicalIso);
      final String detailSummary;
      if (isFuture) {
        detailSummary =
            'Future date — Daily Rhythm check-ins open when this day arrives.';
      } else if (timelineSummary.startDateIso != null) {
        detailSummary =
            'No Daily Rhythm activity recorded prior to ${timelineSummary.startDateIso}.';
      } else {
        detailSummary = 'No Daily Rhythm history recorded yet.';
      }
      return DailyRhythmCalendarDayInspection(
        dateIso: canonicalIso,
        ethiopianDateIso: ethiopianDateIso,
        isToday: isToday,
        isFuture: isFuture,
        isBeforeTrackingStart: isBeforeTrackingStart,
        hasRecordedHistory: false,
        calendarStatus: DailyRhythmCalendarDisplayStatus.unrecorded,
        isProvisionalFreeze: false,
        shortMarkerGlyph: '',
        statusLabel: isFuture ? 'Upcoming' : 'No record',
        accessibleLabel: isFuture
            ? '$canonicalIso: Upcoming date, no Daily Rhythm record'
            : '$canonicalIso: No Daily Rhythm record',
        detailSummary: detailSummary,
        completedResponsibilities: 0,
        faithComplete: false,
        bibleStudyDone: false,
        bibleStudyCompletedAt: null,
        prayerDone: false,
        prayerCompletedAt: null,
        tasksComplete: false,
        taskReviewConfirmed: false,
        taskReviewedAt: null,
        taskReviewEvidence: null,
        financeComplete: false,
        financeCloseStatus: empty.financeCloseStatus,
        financeClosedAt: null,
        financeStatusLabel: 'No record',
        freezeExplanation: null,
        lockNotice: isFuture
            ? 'Future dates are locked and cannot be checked in early.'
            : 'Historical dates without records remain empty and are never fabricated.',
      );
    }

    final rec = evaluated.record;
    final DailyRhythmCalendarDisplayStatus displayStatus;
    final String shortMarkerGlyph;
    final String statusLabel;
    final String detailSummary;
    String? freezeExplanation;

    switch (evaluated.status) {
      case DailyRhythmDayStatuses.complete:
        displayStatus = DailyRhythmCalendarDisplayStatus.complete;
        shortMarkerGlyph = '✓';
        statusLabel = 'Complete · Qualified';
        detailSummary =
            'All three responsibilities qualified on this day (3/3).';
        break;
      case DailyRhythmDayStatuses.freezeProtected:
        displayStatus = DailyRhythmCalendarDisplayStatus.freezeProtected;
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
      case DailyRhythmDayStatuses.partial:
        displayStatus = DailyRhythmCalendarDisplayStatus.partial;
        shortMarkerGlyph = '◐';
        statusLabel = isToday
            ? 'In progress · ${evaluated.completedResponsibilities}/3'
            : 'Partial · ${evaluated.completedResponsibilities}/3';
        detailSummary = isToday
            ? 'Today has partial progress; complete all three responsibilities to qualify.'
            : 'Partial check-in recorded; day did not reach all three qualifying responsibilities.';
        break;
      case DailyRhythmDayStatuses.missed:
        displayStatus = DailyRhythmCalendarDisplayStatus.missed;
        shortMarkerGlyph = '✕';
        statusLabel = 'Missed';
        detailSummary =
            'Did not qualify (requires Faith 2/2, Task review, and Finance close) and was not freeze-protected.';
        break;
      case DailyRhythmDayStatuses.untouched:
      default:
        displayStatus = DailyRhythmCalendarDisplayStatus.untouched;
        shortMarkerGlyph = isToday ? '·' : '✕';
        statusLabel = isToday ? 'Open today · 0/3' : 'Untouched';
        detailSummary = isToday
            ? 'Today has not started yet and has not been missed.'
            : 'No responsibilities completed on this date.';
        break;
    }

    final lockNotice =
        isToday ? null : 'Past Daily Rhythm history is read-only and locked.';

    return DailyRhythmCalendarDayInspection(
      dateIso: canonicalIso,
      ethiopianDateIso: ethiopianDateIso,
      isToday: isToday,
      isFuture: isFuture,
      isBeforeTrackingStart: false,
      hasRecordedHistory: true,
      calendarStatus: displayStatus,
      isProvisionalFreeze: evaluated.isProvisionalFreeze,
      shortMarkerGlyph: shortMarkerGlyph,
      statusLabel: statusLabel,
      accessibleLabel: '$canonicalIso: Daily Rhythm $statusLabel',
      detailSummary: detailSummary,
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
      financeStatusLabel: formatFinanceCloseLabel(rec.financeCloseStatus),
      freezeExplanation: freezeExplanation,
      lockNotice: lockNotice,
    );
  }
}
