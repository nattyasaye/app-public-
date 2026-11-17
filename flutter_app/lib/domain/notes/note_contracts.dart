import 'note_models.dart';

/// Domain contract for personal notes, reflections, and reference knowledge persistence.
abstract class INotesRepository {
  Future<List<NoteEntity>> getNotes({
    String? category,
    String? projectId,
    String? goalId,
    bool includeArchived = false,
    bool includeTrashed = false,
  });

  Future<NoteEntity?> getNoteById(String id);
  Future<NoteEntity> createNote(NoteEntity note);
  Future<NoteEntity> updateNote(NoteEntity note);
  Future<void> deleteNote(String id);
  Future<List<NoteEntity>> searchNotes(String query);
}
