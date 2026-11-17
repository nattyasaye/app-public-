import 'calendar_models.dart';

/// Domain contract for Calendar event persistence and retrieval.
abstract class ICalendarRepository {
  Future<List<CalendarEventEntity>> getEvents(
      {String? dateIso, String? category});
  Future<CalendarEventEntity?> getEventById(String id);
  Future<CalendarEventEntity> createEvent(CalendarEventEntity event);
  Future<CalendarEventEntity> updateEvent(CalendarEventEntity event);
  Future<void> deleteEvent(String id);
}
