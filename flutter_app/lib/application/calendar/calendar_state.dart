import '../../core/date/shared_date.dart';
import '../../domain/calendar/calendar_models.dart';

/// Immutable state container for the Daywell Calendar module.
class CalendarModuleState {
  final List<CalendarEventEntity> events;
  final CalendarDate selectedCalendarDate;
  final String viewMode; // 'month', 'week', 'day'
  final bool isLoading;
  final String? errorMessage;

  CalendarModuleState({
    this.events = const [],
    CalendarDate? selectedCalendarDate,
    DateTime? selectedDate,
    this.viewMode = 'month',
    this.isLoading = false,
    this.errorMessage,
  }) : selectedCalendarDate = selectedCalendarDate ??
            (selectedDate != null
                ? (selectedDate.isUtc
                    ? CalendarDate.fromUtcInstantInEthiopia(selectedDate)
                    : CalendarDate.fromDateComponents(selectedDate))
                : CalendarDate.today());

  /// UTC-midnight carrier kept for existing callers expecting [DateTime].
  DateTime get selectedDate => selectedCalendarDate.toGregorianUtcMidnight();

  CalendarModuleState copyWith({
    List<CalendarEventEntity>? events,
    CalendarDate? selectedCalendarDate,
    DateTime? selectedDate,
    String? viewMode,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    final resolvedDate = selectedCalendarDate ??
        (selectedDate != null
            ? (selectedDate.isUtc
                ? CalendarDate.fromUtcInstantInEthiopia(selectedDate)
                : CalendarDate.fromDateComponents(selectedDate))
            : this.selectedCalendarDate);
    return CalendarModuleState(
      events: events ?? this.events,
      selectedCalendarDate: resolvedDate,
      viewMode: viewMode ?? this.viewMode,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  List<CalendarEventEntity> eventsForCalendarDate(CalendarDate date) {
    return events.where((e) => e.occursOn(date)).toList(growable: false);
  }

  List<CalendarEventEntity> eventsForDate(DateTime date) {
    final target = date.isUtc
        ? CalendarDate.fromUtcInstantInEthiopia(date)
        : CalendarDate.fromDateComponents(date);
    return eventsForCalendarDate(target);
  }
}
