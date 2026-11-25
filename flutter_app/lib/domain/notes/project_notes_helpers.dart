import '../tasks/task_models.dart';
import 'note_helpers.dart';
import 'note_markdown.dart';
import 'note_models.dart';

/// Pure-Dart helpers for Project–Notes relationships reusing `NoteEntity.projectId`.
abstract final class ProjectNotesHelper {
  static String? normalizeProjectId(String? rawProjectId) {
    final trimmed = rawProjectId?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static bool isNoteLinkedToProject(NoteEntity note, String projectId) {
    final cleanProjectId = projectId.trim();
    if (cleanProjectId.isEmpty || note.isTrashed) return false;
    return normalizeProjectId(note.projectId) == cleanProjectId;
  }

  static List<NoteEntity> getNotesForProject(
    Iterable<NoteEntity> notes,
    String projectId, {
    bool includeArchived = true,
    bool includeTrashed = false,
  }) {
    final cleanProjectId = projectId.trim();
    if (cleanProjectId.isEmpty) return const <NoteEntity>[];

    final matched = notes.where((note) {
      if (!includeTrashed && note.isTrashed) return false;
      if (normalizeProjectId(note.projectId) != cleanProjectId) return false;
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

  static int countNotesForProject(
    Iterable<NoteEntity> notes,
    String projectId, {
    bool includeArchived = true,
  }) {
    return getNotesForProject(
      notes,
      projectId,
      includeArchived: includeArchived,
      includeTrashed: false,
    ).length;
  }

  static ProjectEntity? findLinkedProject(
    NoteEntity note,
    Iterable<ProjectEntity> projects,
  ) {
    final cleanProjectId = normalizeProjectId(note.projectId);
    if (cleanProjectId == null) return null;
    for (final project in projects) {
      if (project.id == cleanProjectId) return project;
    }
    return null;
  }

  static Map<String, String> buildProjectTitlesById(
    Iterable<ProjectEntity> projects,
  ) {
    final map = <String, String>{};
    for (final project in projects) {
      final cleanId = project.id.trim();
      final cleanTitle = project.title.trim();
      if (cleanId.isNotEmpty && cleanTitle.isNotEmpty) {
        map[cleanId] = cleanTitle;
      }
    }
    return Map<String, String>.unmodifiable(map);
  }

  static String buildDefaultProjectNoteTitle(ProjectEntity project) {
    final cleanTitle = project.title.trim();
    if (cleanTitle.isEmpty) return 'Project Note';
    return NoteEntity.clampTitle('$cleanTitle — Note');
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
