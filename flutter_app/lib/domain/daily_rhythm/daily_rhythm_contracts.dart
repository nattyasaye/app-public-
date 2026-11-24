import 'daily_rhythm_models.dart';

/// Pure domain repository contract for persisting Daily Rhythm daily check-in
/// records (`DailyRhythmDayEntity`), keyed uniquely by canonical `YYYY-MM-DD`
/// [dateIso].
///
/// Streak, freeze balance, and daily qualification rules remain exclusively in
/// `DailyRhythmEngine`; repositories perform persistence only.
abstract class IDailyRhythmRepository {
  Future<DailyRhythmDayEntity?> getByDate(String dateIso);

  Future<List<DailyRhythmDayEntity>> listDays({
    String? fromDateIso,
    String? toDateIso,
  });

  Future<DailyRhythmDayEntity> upsertDay(DailyRhythmDayEntity day);

  Future<void> deleteByDate(String dateIso);
}
