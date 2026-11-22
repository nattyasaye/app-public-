import 'note_models.dart';

/// Domain contract for personal notes, reflections, and reference knowledge persistence.
abstract class INotesRepository {
  Future<List<NoteEntity>> getNotes({
    String? category,
    String? projectId,
    String? goalId,
    String? linkedModule,
    String? linkedId,
    bool includeArchived = false,
    bool includeTrashed = false,
  });

  Future<List<NoteEntity>> getNotesByLink({
    required String linkedModule,
    required String linkedId,
    bool includeArchived = true,
    bool includeTrashed = false,
  });

  Future<NoteEntity?> getNoteById(String id);
  Future<NoteEntity> createNote(NoteEntity note);
  Future<NoteEntity> updateNote(NoteEntity note);
  Future<int> clearLinksForTarget({
    required String linkedModule,
    required String linkedId,
  });
  Future<void> deleteNote(String id);
  Future<List<NoteEntity>> searchNotes(String query);
}
