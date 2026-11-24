import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/date/shared_date.dart';
import '../../domain/daily_rhythm/daily_rhythm_contracts.dart';
import '../../domain/daily_rhythm/daily_rhythm_models.dart';
import '../database/app_database.dart';

/// Drift SQLite implementation of [IDailyRhythmRepository].
///
/// Enforces one record per canonical `YYYY-MM-DD` `dateIso` via the
/// `daily_rhythm_days` primary key without duplicating streak/freeze math.
class DriftDailyRhythmRepository implements IDailyRhythmRepository {
  final AppDatabase _db;

  DriftDailyRhythmRepository(this._db);

  static String _requireCanonicalDateIso(String rawDateIso) {
    return CalendarDate.parse(rawDateIso).toIsoString();
  }

  static DateTime? _parseOptionalUtcInstant(String? raw, String fieldName) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final parsed = EthiopiaClock.tryParseInstantUtc(trimmed);
    if (parsed == null) {
      throw ArgumentError.value(
        raw,
        fieldName,
        'Expected a valid ISO-8601 UTC timestamp.',
      );
    }
    return parsed;
  }

  static DailyRhythmTaskReviewEvidence? _decodeEvidence(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(rawJson);
      return DailyRhythmTaskReviewEvidence.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  static DailyRhythmDayEntity _mapRowToEntity(DailyRhythmDay row) {
    final normalizedStatus =
        DailyRhythmFinanceCloseStatuses.normalize(row.financeCloseStatus);
    final isFinanceClosed =
        DailyRhythmFinanceCloseStatuses.isClosed(normalizedStatus);

    return DailyRhythmDayEntity(
      dateIso: row.dateIso,
      bibleStudyDone: row.bibleStudyDone,
      bibleStudyCompletedAt:
          row.bibleStudyDone && row.bibleStudyCompletedAt != null
              ? EthiopiaClock.toUtcIsoString(row.bibleStudyCompletedAt!)
              : null,
      prayerDone: row.prayerDone,
      prayerCompletedAt: row.prayerDone && row.prayerCompletedAt != null
          ? EthiopiaClock.toUtcIsoString(row.prayerCompletedAt!)
          : null,
      taskReviewConfirmed: row.taskReviewConfirmed,
      taskReviewedAt: row.taskReviewConfirmed && row.taskReviewedAt != null
          ? EthiopiaClock.toUtcIsoString(row.taskReviewedAt!)
          : null,
      taskReviewEvidence: row.taskReviewConfirmed
          ? _decodeEvidence(row.taskReviewEvidenceJson)
          : null,
      financeCloseStatus: normalizedStatus,
      financeClosedAt: isFinanceClosed && row.financeClosedAt != null
          ? EthiopiaClock.toUtcIsoString(row.financeClosedAt!)
          : null,
      updatedAt: EthiopiaClock.toUtcIsoString(row.updatedAt),
    );
  }

  @override
  Future<DailyRhythmDayEntity?> getByDate(String dateIso) async {
    final canonicalDate = _requireCanonicalDateIso(dateIso);
    final query = _db.select(_db.dailyRhythmDays)
      ..where((tbl) => tbl.dateIso.equals(canonicalDate));
    final row = await query.getSingleOrNull();
    return row == null ? null : _mapRowToEntity(row);
  }

  @override
  Future<List<DailyRhythmDayEntity>> listDays({
    String? fromDateIso,
    String? toDateIso,
  }) async {
    final canonicalFrom =
        fromDateIso != null ? _requireCanonicalDateIso(fromDateIso) : null;
    final canonicalTo =
        toDateIso != null ? _requireCanonicalDateIso(toDateIso) : null;

    final query = _db.select(_db.dailyRhythmDays)
      ..orderBy([(tbl) => OrderingTerm.asc(tbl.dateIso)]);

    if (canonicalFrom != null) {
      query.where((tbl) => tbl.dateIso.isBiggerOrEqualValue(canonicalFrom));
    }
    if (canonicalTo != null) {
      query.where((tbl) => tbl.dateIso.isSmallerOrEqualValue(canonicalTo));
    }

    final rows = await query.get();
    return List<DailyRhythmDayEntity>.unmodifiable(rows.map(_mapRowToEntity));
  }

  @override
  Future<DailyRhythmDayEntity> upsertDay(DailyRhythmDayEntity day) async {
    final canonicalDate = _requireCanonicalDateIso(day.dateIso);
    final canonicalStatuses = DailyRhythmFinanceCloseStatuses.canonical;
    if (!canonicalStatuses.contains(day.financeCloseStatus)) {
      throw ArgumentError.value(
        day.financeCloseStatus,
        'financeCloseStatus',
        'Invalid Daily Rhythm financeCloseStatus.',
      );
    }

    final isFinanceClosed =
        DailyRhythmFinanceCloseStatuses.isClosed(day.financeCloseStatus);

    final bibleStudyCompletedAt = day.bibleStudyDone
        ? _parseOptionalUtcInstant(
            day.bibleStudyCompletedAt,
            'bibleStudyCompletedAt',
          )
        : null;
    final prayerCompletedAt = day.prayerDone
        ? _parseOptionalUtcInstant(
            day.prayerCompletedAt,
            'prayerCompletedAt',
          )
        : null;
    final taskReviewedAt = day.taskReviewConfirmed
        ? _parseOptionalUtcInstant(
            day.taskReviewedAt,
            'taskReviewedAt',
          )
        : null;
    final financeClosedAt = isFinanceClosed
        ? _parseOptionalUtcInstant(
            day.financeClosedAt,
            'financeClosedAt',
          )
        : null;
    final updatedAt = day.updatedAt.trim().isNotEmpty
        ? _parseOptionalUtcInstant(day.updatedAt, 'updatedAt')!
        : EthiopiaClock.nowUtc();

    final normalizedEvidence =
        day.taskReviewConfirmed && day.taskReviewEvidence != null
            ? DailyRhythmTaskReviewEvidence.normalized(
                overdueCount: day.taskReviewEvidence!.overdueCount,
                todayCount: day.taskReviewEvidence!.todayCount,
                plannedCount: day.taskReviewEvidence!.plannedCount,
                completedTodayCount:
                    day.taskReviewEvidence!.completedTodayCount,
              )
            : null;

    final encodedEvidence = normalizedEvidence == null
        ? null
        : jsonEncode(normalizedEvidence.toJson());
    final companion = DailyRhythmDaysCompanion(
      dateIso: Value(canonicalDate),
      bibleStudyDone: Value(day.bibleStudyDone),
      bibleStudyCompletedAt: Value(bibleStudyCompletedAt),
      prayerDone: Value(day.prayerDone),
      prayerCompletedAt: Value(prayerCompletedAt),
      taskReviewConfirmed: Value(day.taskReviewConfirmed),
      taskReviewedAt: Value(taskReviewedAt),
      taskReviewEvidenceJson: Value(encodedEvidence),
      financeCloseStatus: Value(day.financeCloseStatus),
      financeClosedAt: Value(financeClosedAt),
      updatedAt: Value(updatedAt),
    );
    await _db.into(_db.dailyRhythmDays).insertOnConflictUpdate(companion);

    return DailyRhythmDayEntity(
      dateIso: canonicalDate,
      bibleStudyDone: day.bibleStudyDone,
      bibleStudyCompletedAt: bibleStudyCompletedAt != null
          ? EthiopiaClock.toUtcIsoString(bibleStudyCompletedAt)
          : null,
      prayerDone: day.prayerDone,
      prayerCompletedAt: prayerCompletedAt != null
          ? EthiopiaClock.toUtcIsoString(prayerCompletedAt)
          : null,
      taskReviewConfirmed: day.taskReviewConfirmed,
      taskReviewedAt: taskReviewedAt != null
          ? EthiopiaClock.toUtcIsoString(taskReviewedAt)
          : null,
      taskReviewEvidence: normalizedEvidence,
      financeCloseStatus: day.financeCloseStatus,
      financeClosedAt: financeClosedAt != null
          ? EthiopiaClock.toUtcIsoString(financeClosedAt)
          : null,
      updatedAt: EthiopiaClock.toUtcIsoString(updatedAt),
    );
  }

  @override
  Future<void> deleteByDate(String dateIso) async {
    final canonicalDate = _requireCanonicalDateIso(dateIso);
    final deleteQuery = _db.delete(_db.dailyRhythmDays)
      ..where((tbl) => tbl.dateIso.equals(canonicalDate));
    await deleteQuery.go();
  }
}
