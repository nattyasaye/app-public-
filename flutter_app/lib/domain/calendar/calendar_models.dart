import '../../core/date/shared_date.dart';

/// Pure domain model for a Daywell Calendar event.
///
/// Invariants:
/// - Zero dependencies on Flutter widgets or Drift SQLite implementation.
/// - Validated [dateIso] and optional [endDateIso] backed by [CalendarDate]
///   and [DateRange].
class CalendarEventEntity {
  final String id;
  final String title;
  final String dateIso; // Canonical YYYY-MM-DD
  final String? endDateIso; // Optional canonical YYYY-MM-DD for multi-day span
  final String? startTime; // HH:mm
  final String? endTime; // HH:mm
  final bool isAllDay;
  final String category; // 'work', 'personal', 'health', 'finance', 'holiday'
  final String colorHex;
  final bool hasReminder;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  CalendarEventEntity({
    required this.id,
    required this.title,
    required String dateIso,
    String? endDateIso,
    String? startTime,
    String? endTime,
    this.isAllDay = false,
    this.category = 'personal',
    this.colorHex = '#1B4D3E',
    this.hasReminder = false,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : dateIso = CalendarDate.parse(dateIso).toIsoString(),
        endDateIso = _validateEndDateIso(dateIso, endDateIso),
        startTime = _validateOptionalTime(startTime),
        endTime = _validateOptionalTime(endTime),
        createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc(),
        updatedAt = (updatedAt ?? EthiopiaClock.nowUtc()).toUtc() {
    if (!isAllDay &&
        !isMultiDay &&
        this.startTime != null &&
        this.endTime != null) {
      final startTod = DayTimeOfDay.parse(this.startTime!);
      final endTod = DayTimeOfDay.parse(this.endTime!);
      if (endTod < startTod) {
        throw ArgumentError(
          'CalendarEventEntity endTime (${this.endTime}) cannot precede '
          'startTime (${this.startTime}) on the same day.',
        );
      }
    }
  }

  static String? _validateEndDateIso(String startIso, String? endIso) {
    if (endIso == null || endIso.trim().isEmpty) return null;
    final start = CalendarDate.parse(startIso);
    final end = CalendarDate.parse(endIso);
    if (end.isBefore(start)) {
      throw ArgumentError(
        'CalendarEventEntity endDateIso (${end.toIsoString()}) cannot precede '
        'dateIso (${start.toIsoString()}).',
      );
    }
    return end.toIsoString();
  }

  static String? _validateOptionalTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return DayTimeOfDay.parse(raw).toIsoString();
  }

  CalendarDate get startDate => CalendarDate.parse(dateIso);

  CalendarDate? get endDate =>
      endDateIso != null ? CalendarDate.parse(endDateIso!) : null;

  DateRange get dateRange =>
      DateRange(start: startDate, end: endDate ?? startDate);

  EthiopianDate get ethiopianStartDate => startDate.toEthiopian();

  bool get isMultiDay => endDateIso != null && endDateIso != dateIso;

  int get spanInDays => dateRange.lengthInDays;

  bool occursOn(CalendarDate day) => dateRange.contains(day);

  CalendarEventEntity copyWith({
    String? title,
    String? dateIso,
    String? endDateIso,
    bool clearEndDate = false,
    String? startTime,
    String? endTime,
    bool? isAllDay,
    String? category,
    String? colorHex,
    bool? hasReminder,
    String? notes,
    DateTime? updatedAt,
  }) {
    return CalendarEventEntity(
      id: id,
      title: title ?? this.title,
      dateIso: dateIso ?? this.dateIso,
      endDateIso: clearEndDate ? null : (endDateIso ?? this.endDateIso),
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isAllDay: isAllDay ?? this.isAllDay,
      category: category ?? this.category,
      colorHex: colorHex ?? this.colorHex,
      hasReminder: hasReminder ?? this.hasReminder,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? EthiopiaClock.nowUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'dateIso': dateIso,
        'endDateIso': endDateIso,
        'startTime': startTime,
        'endTime': endTime,
        'isAllDay': isAllDay,
        'category': category,
        'colorHex': colorHex,
        'hasReminder': hasReminder,
        'notes': notes,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
        'updatedAt': EthiopiaClock.toUtcIsoString(updatedAt),
      };

  factory CalendarEventEntity.fromJson(Map<String, dynamic> json) {
    final rawDate = (json['dateIso'] ?? json['date'])?.toString() ?? '';
    final parsedDate = SharedDateFormatter.parseFlexibleToCalendarDate(rawDate);
    final rawEnd = (json['endDateIso'] ?? json['endDate'])?.toString().trim();
    final parsedEndIso = rawEnd != null && rawEnd.isNotEmpty
        ? SharedDateFormatter.parseFlexibleToCalendarDate(rawEnd).toIsoString()
        : null;

    return CalendarEventEntity(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      dateIso: parsedDate.toIsoString(),
      endDateIso: parsedEndIso,
      startTime: json['startTime'] as String?,
      endTime: json['endTime'] as String?,
      isAllDay: (json['isAllDay'] as bool?) ?? false,
      category: (json['category'] as String?) ?? 'personal',
      colorHex: (json['colorHex'] as String?) ?? '#1B4D3E',
      hasReminder: (json['hasReminder'] as bool?) ?? false,
      notes: json['notes'] as String?,
      createdAt:
          EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString()),
      updatedAt:
          EthiopiaClock.tryParseInstantUtc(json['updatedAt']?.toString()),
    );
  }
}
