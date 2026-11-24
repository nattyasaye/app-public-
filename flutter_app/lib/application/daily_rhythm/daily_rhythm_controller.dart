import 'package:flutter/foundation.dart';

import '../../core/date/shared_date.dart';
import '../../domain/daily_rhythm/daily_rhythm_contracts.dart';
import '../../domain/daily_rhythm/daily_rhythm_engine.dart';
import '../../domain/daily_rhythm/daily_rhythm_models.dart';
import '../../domain/daily_rhythm/daily_rhythm_workflows.dart';
import '../../domain/finance/double_entry_engine.dart';
import '../../domain/tasks/task_models.dart';
import './daily_rhythm_state.dart';

class DailyRhythmController extends ChangeNotifier {
  final IDailyRhythmRepository _repository;
  DailyRhythmState _state = DailyRhythmState();
  bool _isDisposed = false;

  DailyRhythmController({
    required IDailyRhythmRepository repository,
  }) : _repository = repository;

  DailyRhythmState get state => _state;

  void _safeNotify() {
    if (!_isDisposed) notifyListeners();
  }

  Future<void> loadAll({
    CalendarDate? today,
    DateTime? todayInstant,
  }) async {
    _state = _state.copyWith(isLoading: true, clearError: true);
    _safeNotify();
    try {
      final loaded = await _repository.listDays();
      final normalized = DailyRhythmEngine.normalizeTimeline(loaded);
      final summary = DailyRhythmEngine.evaluateTimeline(
        normalized,
        today: today,
        todayInstant: todayInstant,
      );
      _state = DailyRhythmState(
        days: normalized,
        summary: summary,
        isLoading: false,
        isSaving: false,
      );
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load Daily Rhythm records: $e',
      );
    }
    _safeNotify();
  }

  Future<DailyRhythmMutationResult> _commitMutation(
    DailyRhythmMutationResult result, {
    CalendarDate? today,
    DateTime? todayInstant,
  }) async {
    if (!result.applied) return result;
    _state = _state.copyWith(isSaving: true, clearError: true);
    _safeNotify();
    try {
      final persisted = await _repository.upsertDay(result.record);
      final nextDays = DailyRhythmEngine.normalizeTimeline([
        ..._state.days.where((d) => d.dateIso != persisted.dateIso),
        persisted,
      ]);
      final summary = DailyRhythmEngine.evaluateTimeline(
        nextDays,
        today: today,
        todayInstant: todayInstant,
      );
      _state = DailyRhythmState(
        days: nextDays,
        summary: summary,
        isLoading: false,
        isSaving: false,
      );
      _safeNotify();
      return DailyRhythmMutationResult(
        applied: true,
        reason: result.reason,
        record: persisted,
      );
    } catch (e) {
      _state = _state.copyWith(
        isSaving: false,
        errorMessage: 'Failed to save Daily Rhythm check-in: $e',
      );
      _safeNotify();
      return DailyRhythmMutationResult(
        applied: false,
        reason: DailyRhythmMutationReason.unchanged,
        record: result.record,
      );
    }
  }

  Future<DailyRhythmMutationResult> updateFaith({
    required String dateIso,
    bool? bibleStudyDone,
    bool? prayerDone,
    String? nowIso,
    CalendarDate? today,
    DateTime? todayInstant,
  }) async {
    final existing = _state.dayFor(dateIso);
    final result = DailyRhythmEngine.updateFaith(
      record: existing,
      dateIso: dateIso,
      bibleStudyDone: bibleStudyDone,
      prayerDone: prayerDone,
      nowIso: nowIso,
      today: today,
      todayInstant: todayInstant,
    );
    return _commitMutation(result, today: today, todayInstant: todayInstant);
  }

  Future<DailyRhythmMutationResult> confirmTaskReview({
    required String dateIso,
    required List<TaskEntity> tasks,
    required List<DailyPlanningEntryEntity> planningEntries,
    String? nowIso,
    CalendarDate? today,
    DateTime? todayInstant,
  }) async {
    final snapshot = DailyRhythmWorkflows.buildTaskReviewSnapshot(
      tasks: tasks,
      planningEntries: planningEntries,
      targetDateIso: dateIso,
      today: today,
      todayInstant: todayInstant,
    );
    final existing = _state.dayFor(snapshot.targetDateIso);
    final result = DailyRhythmEngine.confirmTaskReview(
      record: existing,
      dateIso: snapshot.targetDateIso,
      evidence: snapshot.evidence,
      nowIso: nowIso,
      today: today,
      todayInstant: todayInstant,
    );
    return _commitMutation(result, today: today, todayInstant: todayInstant);
  }

  Future<DailyRhythmMutationResult> confirmFinanceClose({
    required String dateIso,
    required List<JournalEntryModel> entries,
    String? nowIso,
    CalendarDate? today,
    DateTime? todayInstant,
  }) async {
    final summary = DailyRhythmWorkflows.inspectFinanceDay(
      entries: entries,
      targetDateIso: dateIso,
      today: today,
      todayInstant: todayInstant,
    );
    final existing = _state.dayFor(summary.targetDateIso);
    final result = DailyRhythmEngine.confirmFinanceClose(
      record: existing,
      dateIso: summary.targetDateIso,
      hasTransactions: summary.hasTransactions,
      nowIso: nowIso,
      today: today,
      todayInstant: todayInstant,
    );
    return _commitMutation(result, today: today, todayInstant: todayInstant);
  }

  Future<DailyRhythmMutationResult?> handleFinanceLedgerMutation({
    required List<JournalEntryModel> prevEntries,
    required List<PostingModel> prevPostings,
    required List<JournalEntryModel> nextEntries,
    required List<PostingModel> nextPostings,
    String? nowIso,
    CalendarDate? today,
    DateTime? todayInstant,
  }) async {
    final resolvedToday = DailyRhythmEngine.resolveToday(
      today: today,
      todayInstant: todayInstant,
    );
    final todayIso = resolvedToday.toIsoString();
    final affectedToday = DailyRhythmWorkflows.didLedgerChangeAffectDate(
      prevEntries: prevEntries,
      prevPostings: prevPostings,
      nextEntries: nextEntries,
      nextPostings: nextPostings,
      targetDateIso: todayIso,
      today: resolvedToday,
      todayInstant: todayInstant,
    );
    if (!affectedToday) return null;

    final existing = _state.dayFor(todayIso);
    final result = DailyRhythmEngine.applyFinanceLedgerChange(
      record: existing,
      dateIso: todayIso,
      nowIso: nowIso,
      today: resolvedToday,
      todayInstant: todayInstant,
    );
    return _commitMutation(
      result,
      today: resolvedToday,
      todayInstant: todayInstant,
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
