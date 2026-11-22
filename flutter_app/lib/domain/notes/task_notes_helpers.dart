import '../tasks/task_models.dart';
import 'note_models.dart';

/// Pure domain helpers for Task–Notes relationships.
///
/// Zero dependencies on Flutter widgets or Drift SQLite.
/// Keeps Notes as the sole owner of note records while providing canonical
/// filtering, counting, and draft-note seeding helpers matching Web Stage 7.
class TaskNotesHelper {
  const TaskNotesHelper._();

  static bool isNoteLinkedToTask(NoteEntity note, String taskId) {
    return note.linkedModule == NoteEntity.taskLinkModule &&
        note.linkedId == taskId;
  }

  static List<NoteEntity> getNotesForTask(
    Iterable<NoteEntity> notes,
    String taskId, {
    bool includeTrashed = false,
    bool includeArchived = true,
  }) {
    final matched = notes.where((note) {
      if (!includeTrashed && note.isTrashed) return false;
      if (!includeArchived && note.isArchived) return false;
      return isNoteLinkedToTask(note, taskId);
    }).toList();

    matched.sort((a, b) {
      if (a.isArchived != b.isArchived) {
        return a.isArchived ? 1 : -1;
      }
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return matched;
  }

  static int countNotesForTask(
    Iterable<NoteEntity> notes,
    String taskId,
  ) {
    return getNotesForTask(
      notes,
      taskId,
      includeTrashed: false,
      includeArchived: true,
    ).length;
  }

  static List<NoteEntity> getAvailableNotesForTaskLink(
    Iterable<NoteEntity> notes,
    String taskId, {
    String query = '',
  }) {
    final trimmedQuery = query.trim();
    final candidates = notes.where((note) {
      if (note.isTrashed) return false;
      if (isNoteLinkedToTask(note, taskId)) return false;
      if (trimmedQuery.isNotEmpty && !note.matchesQuery(trimmedQuery)) {
        return false;
      }
      return true;
    }).toList();

    candidates.sort((a, b) {
      if (a.isArchived != b.isArchived) {
        return a.isArchived ? 1 : -1;
      }
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return candidates;
  }

  static String buildDefaultTaskNoteTitle(TaskEntity task) {
    return NoteEntity.clampTitle(task.title);
  }

  static String buildDefaultTaskNoteBody(TaskEntity task) {
    final desc = task.description?.trim() ?? '';
    return desc.isNotEmpty ? desc : '';
  }

  static TaskEntity? findLinkedTask(
    NoteEntity note,
    Iterable<TaskEntity> tasks,
  ) {
    final taskId = note.linkedTaskId;
    if (taskId == null) return null;
    for (final task in tasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }
}
