import '../../core/date/shared_date.dart';
import '../finance/double_entry_engine.dart';
import '../tasks/daily_planning_engine.dart';
import '../tasks/task_models.dart';
import './daily_rhythm_engine.dart';
import './daily_rhythm_models.dart';

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
}
