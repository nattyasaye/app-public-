import 'package:drift/drift.dart';

import '../../core/date/shared_date.dart';
import '../../domain/calendar/calendar_contracts.dart';
import '../../domain/calendar/calendar_models.dart';
import '../../domain/notes/note_models.dart';
import '../database/app_database.dart';

export '../../domain/calendar/calendar_contracts.dart';
export '../../domain/calendar/calendar_models.dart';

/// Drift SQLite implementation of [ICalendarRepository].
class DriftCalendarRepository implements ICalendarRepository {
  final AppDatabase _db;

  DriftCalendarRepository(this._db);

  CalendarEventEntity _mapRowToEntity(CalendarEvent r) {
    return CalendarEventEntity(
      id: r.id,
      title: r.title,
      dateIso: r.dateIso,
      endDateIso: r.endDateIso,
      startTime: r.startTime,
      endTime: r.endTime,
      isAllDay: r.isAllDay,
      category: r.category,
      colorHex: r.colorHex,
      hasReminder: r.hasReminder,
      notes: r.notes,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    );
  }

  @override
  Future<List<CalendarEventEntity>> getEvents({
    String? dateIso,
    String? category,
  }) async {
    final query = _db.select(_db.calendarEvents);
    if (category != null && category != 'all') {
      query.where((tbl) => tbl.category.equals(category));
    }
    query.orderBy([
      (tbl) => OrderingTerm.asc(tbl.dateIso),
      (tbl) => OrderingTerm.asc(tbl.startTime),
    ]);
    final rows = await query.get();
    final entities = rows.map(_mapRowToEntity);
    if (dateIso != null) {
      final targetDay = CalendarDate.parse(dateIso);
      return entities.where((e) => e.occursOn(targetDay)).toList();
    }
    return entities.toList();
  }

  @override
  Future<CalendarEventEntity?> getEventById(String id) async {
    final row = await (_db.select(_db.calendarEvents)
          ..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
    return row != null ? _mapRowToEntity(row) : null;
  }

  @override
  Future<CalendarEventEntity> createEvent(CalendarEventEntity event) async {
    final now = EthiopiaClock.nowUtc();
    final trimmedTitle = event.title.trim();
    await _db.into(_db.calendarEvents).insert(
          CalendarEventsCompanion.insert(
            id: event.id,
            title: trimmedTitle.isEmpty ? 'Untitled Event' : trimmedTitle,
            dateIso: event.dateIso,
            endDateIso: Value(event.endDateIso),
            startTime: Value(event.startTime),
            endTime: Value(event.endTime),
            isAllDay: Value(event.isAllDay),
            category: Value(event.category),
            colorHex: Value(event.colorHex),
            hasReminder: Value(event.hasReminder),
            notes: Value(event.notes?.trim()),
            createdAt: event.createdAt,
            updatedAt: now,
          ),
        );
    return event.copyWith(
      title: trimmedTitle.isEmpty ? 'Untitled Event' : trimmedTitle,
      updatedAt: now,
    );
  }

  @override
  Future<CalendarEventEntity> updateEvent(CalendarEventEntity event) async {
    final now = EthiopiaClock.nowUtc();
    final trimmedTitle = event.title.trim();
    await (_db.update(_db.calendarEvents)
          ..where((tbl) => tbl.id.equals(event.id)))
        .write(
      CalendarEventsCompanion(
        title: Value(trimmedTitle.isEmpty ? 'Untitled Event' : trimmedTitle),
        dateIso: Value(event.dateIso),
        endDateIso: Value(event.endDateIso),
        startTime: Value(event.startTime),
        endTime: Value(event.endTime),
        isAllDay: Value(event.isAllDay),
        category: Value(event.category),
        colorHex: Value(event.colorHex),
        hasReminder: Value(event.hasReminder),
        notes: Value(event.notes?.trim()),
        updatedAt: Value(now),
      ),
    );
    return event.copyWith(
      title: trimmedTitle.isEmpty ? 'Untitled Event' : trimmedTitle,
      updatedAt: now,
    );
  }

  @override
  Future<void> deleteEvent(String id) async {
    final now = EthiopiaClock.nowUtc();
    await _db.transaction(() async {
      await (_db.update(_db.notes)
            ..where(
              (tbl) =>
                  tbl.linkedModule.equals(NoteEntity.calendarLinkModule) &
                  tbl.linkedId.equals(id),
            ))
          .write(
        NotesCompanion(
          linkedModule: const Value(null),
          linkedId: const Value(null),
          updatedAt: Value(now),
        ),
      );
      await (_db.delete(_db.calendarEvents)..where((tbl) => tbl.id.equals(id)))
          .go();
    });
  }
}
