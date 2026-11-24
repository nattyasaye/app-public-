import '../../core/date/shared_date.dart';
import '../../domain/daily_rhythm/daily_rhythm_engine.dart';
import '../../domain/daily_rhythm/daily_rhythm_models.dart';

class DailyRhythmState {
  final List<DailyRhythmDayEntity> days;
  final DailyRhythmTimelineSummary summary;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  DailyRhythmState({
    this.days = const [],
    DailyRhythmTimelineSummary? summary,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
  }) : summary = summary ?? DailyRhythmEngine.evaluateTimeline(days);

  DailyRhythmDayEntity dayFor(String dateIso) {
    final parsed = CalendarDate.tryParse(dateIso);
    final canonical = parsed?.toIsoString() ?? dateIso;
    for (final day in days) {
      if (day.dateIso == canonical) return day;
    }
    if (summary.todayIso == canonical) {
      return summary.todayRecord;
    }
    return parsed != null
        ? DailyRhythmDayEntity.empty(canonical)
        : summary.todayRecord;
  }

  DailyRhythmDayEntity get todayRecord => summary.todayRecord;

  DailyRhythmState copyWith({
    List<DailyRhythmDayEntity>? days,
    DailyRhythmTimelineSummary? summary,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
  }) {
    final nextDays = days ?? this.days;
    return DailyRhythmState(
      days: nextDays,
      summary: summary ?? DailyRhythmEngine.evaluateTimeline(nextDays),
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
