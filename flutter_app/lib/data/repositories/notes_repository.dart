import 'dart:convert';
import 'package:drift/drift.dart';
import '../../core/date/shared_date.dart';
import '../database/app_database.dart';
import '../../domain/notes/note_models.dart';
import '../../domain/notes/note_contracts.dart';

export '../../domain/notes/note_models.dart';
export '../../domain/notes/note_contracts.dart';

/// Drift SQLite implementation of [INotesRepository].
///
/// Authoritative persistent owner for personal notes, tags, pins, favorites,
/// archive status, soft-trash status, and full Unicode search under Drift SQLite schema v8.
class DriftNotesRepository implements INotesRepository {
  final AppDatabase _db;

  DriftNotesRepository(this._db);

  static List<String> _decodeTags(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((e) => e.toString()).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  NoteEntity _mapRowToEntity(Note r) {
    return NoteEntity(
      id: r.id,
      title: r.title,
      content: r.content,
      category: r.category,
      projectId: r.projectId,
      goalId: r.goalId,
      tags: _decodeTags(r.tagsJson),
      isPinned: r.isPinned,
      isFavorite: r.isFavorite,
      isArchived: r.isArchived,
      isTrashed: r.isTrashed,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    );
  }

  @override
  Future<List<NoteEntity>> getNotes({
    String? category,
    String? projectId,
    String? goalId,
    bool includeArchived = false,
    bool includeTrashed = false,
  }) async {
    final query = _db.select(_db.notes);

    if (category != null && category != 'all') {
      query.where(
          (tbl) => tbl.category.equals(NoteEntity.normalizeCategory(category)));
    }
    if (projectId != null) {
      query.where((tbl) => tbl.projectId.equals(projectId));
    }
    if (goalId != null) {
      query.where((tbl) => tbl.goalId.equals(goalId));
    }
    if (!includeArchived) {
      query.where((tbl) => tbl.isArchived.equals(false));
    }
    if (!includeTrashed) {
      query.where((tbl) => tbl.isTrashed.equals(false));
    }

    query.orderBy([
      (tbl) => OrderingTerm.desc(tbl.isPinned),
      (tbl) => OrderingTerm.desc(tbl.updatedAt),
    ]);
    final rows = await query.get();
    return rows.map(_mapRowToEntity).toList();
  }

  @override
  Future<NoteEntity?> getNoteById(String id) async {
    final query = _db.select(_db.notes)..where((tbl) => tbl.id.equals(id));
    final r = await query.getSingleOrNull();
    if (r == null) return null;
    return _mapRowToEntity(r);
  }

  @override
  Future<NoteEntity> createNote(NoteEntity note) async {
    final now = EthiopiaClock.nowUtc();
    final trimmedTitle = note.title.trim();
    final trimmedContent = note.content.trim();
    final normalizedCat = NoteEntity.normalizeCategory(note.category);

    await _db.into(_db.notes).insert(
          NotesCompanion.insert(
            id: note.id,
            title: trimmedTitle.isEmpty ? 'Untitled Note' : trimmedTitle,
            content: trimmedContent,
            category: Value(normalizedCat),
            projectId: Value(note.projectId),
            goalId: Value(note.goalId),
            tagsJson: Value(jsonEncode(note.tags)),
            isPinned: Value(note.isPinned),
            isFavorite: Value(note.isFavorite),
            isArchived: Value(note.isArchived),
            isTrashed: Value(note.isTrashed),
            createdAt: note.createdAt,
            updatedAt: now,
          ),
        );

    return note.copyWith(
      title: trimmedTitle.isEmpty ? 'Untitled Note' : trimmedTitle,
      content: trimmedContent,
      category: normalizedCat,
      updatedAt: now,
    );
  }

  @override
  Future<NoteEntity> updateNote(NoteEntity note) async {
    final now = EthiopiaClock.nowUtc();
    final trimmedTitle = note.title.trim();
    final trimmedContent = note.content.trim();
    final normalizedCat = NoteEntity.normalizeCategory(note.category);

    await (_db.update(_db.notes)..where((tbl) => tbl.id.equals(note.id))).write(
      NotesCompanion(
        title: Value(trimmedTitle.isEmpty ? 'Untitled Note' : trimmedTitle),
        content: Value(trimmedContent),
        category: Value(normalizedCat),
        projectId: Value(note.projectId),
        goalId: Value(note.goalId),
        tagsJson: Value(jsonEncode(note.tags)),
        isPinned: Value(note.isPinned),
        isFavorite: Value(note.isFavorite),
        isArchived: Value(note.isArchived),
        isTrashed: Value(note.isTrashed),
        updatedAt: Value(now),
      ),
    );

    return note.copyWith(
      title: trimmedTitle.isEmpty ? 'Untitled Note' : trimmedTitle,
      content: trimmedContent,
      category: normalizedCat,
      updatedAt: now,
    );
  }

  @override
  Future<void> deleteNote(String id) async {
    await (_db.delete(_db.notes)..where((tbl) => tbl.id.equals(id))).go();
  }

  @override
  Future<List<NoteEntity>> searchNotes(String query) async {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return [];

    final rows = await (_db.select(_db.notes)
          ..where((tbl) =>
              tbl.isTrashed.equals(false) &
              (tbl.title.lower().like('%$clean%') |
                  tbl.content.lower().like('%$clean%') |
                  tbl.tagsJson.lower().like('%$clean%')))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)]))
        .get();

    return rows.map(_mapRowToEntity).toList();
  }
}
