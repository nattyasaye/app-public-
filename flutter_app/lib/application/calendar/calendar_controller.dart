import 'package:flutter/foundation.dart';

import '../../core/date/shared_date.dart';
import '../../domain/calendar/calendar_contracts.dart';
import '../../domain/calendar/calendar_models.dart';
import 'calendar_state.dart';

/// Module-scoped application controller for Daywell Calendar events.
class CalendarController extends ChangeNotifier {
  final ICalendarRepository _repository;
  final Future<void> Function(String eventId)? _onEventDeleted;
  CalendarModuleState _state;
  bool _isDisposed = false;

  CalendarController({
    required ICalendarRepository repository,
    CalendarModuleState? initialState,
    Future<void> Function(String eventId)? onEventDeleted,
  })  : _repository = repository,
        _onEventDeleted = onEventDeleted,
        _state = initialState ?? CalendarModuleState();

  CalendarModuleState get state => _state;

  void setSelectedCalendarDate(CalendarDate date) {
    _state = _state.copyWith(selectedCalendarDate: date);
    notifyListeners();
  }

  void setSelectedDate(DateTime date) {
    _state = _state.copyWith(selectedDate: date);
    notifyListeners();
  }

  void setViewMode(String mode) {
    _state = _state.copyWith(viewMode: mode);
    notifyListeners();
  }

  Future<void> loadAll() async {
    _state = _state.copyWith(isLoading: true, clearError: true);
    notifyListeners();
    try {
      final loaded = await _repository.getEvents();
      _state = _state.copyWith(
        events: List<CalendarEventEntity>.unmodifiable(loaded),
        isLoading: false,
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
    notifyListeners();
  }

  Future<CalendarEventEntity?> createEvent({
    required String title,
    required String dateIso,
    String? endDateIso,
    String? startTime,
    String? endTime,
    bool isAllDay = false,
    String category = 'personal',
    String colorHex = '#1B4D3E',
    bool hasReminder = false,
    String? notes,
  }) async {
    final now = EthiopiaClock.nowUtc();
    try {
      final event = CalendarEventEntity(
        id: 'evt-${now.millisecondsSinceEpoch}',
        title: title.trim(),
        dateIso: dateIso,
        endDateIso: endDateIso,
        startTime: startTime,
        endTime: endTime,
        isAllDay: isAllDay,
        category: category,
        colorHex: colorHex,
        hasReminder: hasReminder,
        notes: notes?.trim(),
        createdAt: now,
        updatedAt: now,
      );

      final created = await _repository.createEvent(event);
      final updated = await _repository.getEvents();
      _state = _state.copyWith(
        events: List<CalendarEventEntity>.unmodifiable(updated),
        clearError: true,
      );
      notifyListeners();
      return created;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<void> updateEvent(CalendarEventEntity event) async {
    try {
      await _repository.updateEvent(event);
      final updated = await _repository.getEvents();
      _state = _state.copyWith(
        events: List<CalendarEventEntity>.unmodifiable(updated),
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> deleteEvent(String id) async {
    try {
      await _repository.deleteEvent(id);
      if (_onEventDeleted != null) {
        await _onEventDeleted!(id);
      }
      final remaining = _state.events.where((e) => e.id != id).toList();
      _state = _state.copyWith(
        events: List<CalendarEventEntity>.unmodifiable(remaining),
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    super.dispose();
  }
}
