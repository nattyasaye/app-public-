import '../calendar/calendar_models.dart';
import 'note_helpers.dart';
import 'note_markdown.dart';
import 'note_models.dart';

class CalendarNoteLinkCandidate {
  final NoteEntity note;
  final String? linkedEventId;
  final String? linkedTaskId;
  final bool isLinkedToOtherModule;
  final bool hasExistingPrimaryLink;

  const CalendarNoteLinkCandidate({
    required this.note,
    this.linkedEventId,
    this.linkedTaskId,
    required this.isLinkedToOtherModule,
    required this.hasExistingPrimaryLink,
  });
}

/// Pure-Dart domain helpers for Calendar Event–Notes relationships reusing
/// `linkedModule = 'calendar'` and `linkedId`.
abstract final class CalendarNotesHelper {
  static bool isNoteLinkedToEvent(NoteEntity note, String eventId) {
    final cleanEventId = eventId.trim();
    if (cleanEventId.isEmpty || note.isTrashed) return false;
    return note.linkedModule == NoteEntity.calendarLinkModule &&
        note.linkedId == cleanEventId;
  }

  static List<NoteEntity> getNotesForEvent(
    Iterable<NoteEntity> notes,
    String eventId, {
    bool includeArchived = true,
    bool includeTrashed = false,
  }) {
    final cleanEventId = eventId.trim();
    if (cleanEventId.isEmpty) return const <NoteEntity>[];

    final matched = notes.where((note) {
      if (!includeTrashed && note.isTrashed) return false;
      if (note.linkedModule != NoteEntity.calendarLinkModule ||
          note.linkedId != cleanEventId) {
        return false;
      }
      if (!includeArchived && note.isArchived && !note.isTrashed) return false;
      return true;
    }).toList();

    matched.sort((a, b) {
      if (a.isArchived != b.isArchived) {
        return a.isArchived ? 1 : -1;
      }
      return NoteDomainHelpers.compareNotes(
        a,
        b,
        sortBy: NoteSortMode.recent,
        pinFirst: true,
      );
    });
    return List<NoteEntity>.unmodifiable(matched);
  }

  static int countNotesForEvent(
    Iterable<NoteEntity> notes,
    String eventId, {
    bool includeArchived = true,
  }) {
    return getNotesForEvent(
      notes,
      eventId,
      includeArchived: includeArchived,
      includeTrashed: false,
    ).length;
  }

  static List<CalendarNoteLinkCandidate> getAvailableNotesForEventLink(
    Iterable<NoteEntity> notes,
    String eventId, {
    String query = '',
  }) {
    final cleanEventId = eventId.trim();
    final trimmedQuery = query.trim();

    final filtered = notes.where((note) {
      if (note.isTrashed) return false;
      if (isNoteLinkedToEvent(note, cleanEventId)) return false;
      if (trimmedQuery.isNotEmpty && !note.matchesQuery(trimmedQuery)) {
        return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      final aHasLink = a.linkedModule != null && a.linkedId != null;
      final bHasLink = b.linkedModule != null && b.linkedId != null;
      if (aHasLink != bHasLink) return aHasLink ? 1 : -1;
      if (a.isArchived != b.isArchived) return a.isArchived ? 1 : -1;
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return List<CalendarNoteLinkCandidate>.unmodifiable(
      filtered.map((note) {
        final hasLink = note.linkedModule != null && note.linkedId != null;
        return CalendarNoteLinkCandidate(
          note: note,
          linkedEventId: note.linkedCalendarEventId,
          linkedTaskId: note.linkedTaskId,
          isLinkedToOtherModule: note.linkedModule != null &&
              note.linkedModule != NoteEntity.calendarLinkModule &&
              note.linkedId != null,
          hasExistingPrimaryLink: hasLink,
        );
      }),
    );
  }

  static CalendarEventEntity? findLinkedEvent(
    NoteEntity note,
    Iterable<CalendarEventEntity> events,
  ) {
    final eventId = note.linkedCalendarEventId;
    if (eventId == null) return null;
    for (final ev in events) {
      if (ev.id == eventId) return ev;
    }
    return null;
  }

  static Map<String, String> buildEventTitlesById(
    Iterable<CalendarEventEntity> events,
  ) {
    final map = <String, String>{};
    for (final ev in events) {
      final cleanId = ev.id.trim();
      final cleanTitle = ev.title.trim();
      if (cleanId.isNotEmpty && cleanTitle.isNotEmpty) {
        map[cleanId] = cleanTitle;
      }
    }
    return Map<String, String>.unmodifiable(map);
  }

  static String buildDefaultEventNoteTitle(CalendarEventEntity event) {
    final cleanTitle = event.title.trim();
    if (cleanTitle.isEmpty) return 'Event Note';
    return NoteEntity.clampTitle('$cleanTitle — Notes');
  }

  static String buildContentPreview(String content, {int maxLength = 140}) {
    final plain = NoteMarkdownParser.toPlainText(content)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (plain.isEmpty) return '';
    if (plain.length <= maxLength) return plain;
    final safeLimit = maxLength <= 1 ? 1 : maxLength - 1;
    return '${plain.substring(0, safeLimit).trimRight()}…';
  }
}
