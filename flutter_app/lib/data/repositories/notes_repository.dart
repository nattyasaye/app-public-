import 'dart:convert';
import 'package:drift/drift.dart';
import '../../core/date/shared_date.dart';
import '../database/app_database.dart';
import '../../domain/notes/note_helpers.dart';
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
      linkedModule: r.linkedModule,
      linkedId: r.linkedId,
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
    String? linkedModule,
    String? linkedId,
    bool includeArchived = false,
    bool includeTrashed = false,
  }) async {
    final query = _db.select(_db.notes);

    if (category != null && category != 'all') {
      query.where((tbl) =>
          tbl.category.lower().equals(NoteEntity.normalizeCategory(category)));
    }
    if (projectId != null) {
      query.where((tbl) => tbl.projectId.equals(projectId));
    }
    if (goalId != null) {
      query.where((tbl) => tbl.goalId.equals(goalId));
    }
    if (linkedModule != null && linkedModule.trim().isNotEmpty) {
      query.where(
        (tbl) => tbl.linkedModule.equals(linkedModule.trim().toLowerCase()),
      );
    }
    if (linkedId != null && linkedId.trim().isNotEmpty) {
      query.where((tbl) => tbl.linkedId.equals(linkedId.trim()));
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
  Future<List<NoteEntity>> getNotesByLink({
    required String linkedModule,
    required String linkedId,
    bool includeArchived = true,
    bool includeTrashed = false,
  }) {
    return getNotes(
      linkedModule: linkedModule,
      linkedId: linkedId,
      includeArchived: includeArchived,
      includeTrashed: includeTrashed,
    );
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
    final safeTitle = NoteEntity.clampTitle(note.title);
    final normalizedCat = NoteEntity.normalizeCategory(note.category);
    final normalizedTags = NoteDomainHelpers.normalizeTags(note.tags);
    final linkPair =
        NoteEntity.normalizeLinkPair(note.linkedModule, note.linkedId);

    await _db.into(_db.notes).insert(
          NotesCompanion.insert(
            id: note.id,
            title: safeTitle,
            content: note.content,
            category: Value(normalizedCat),
            projectId: Value(note.projectId),
            goalId: Value(note.goalId),
            linkedModule: Value(linkPair.$1),
            linkedId: Value(linkPair.$2),
            tagsJson: Value(jsonEncode(normalizedTags)),
            isPinned: Value(note.isPinned),
            isFavorite: Value(note.isFavorite),
            isArchived: Value(note.isArchived),
            isTrashed: Value(note.isTrashed),
            createdAt: note.createdAt,
            updatedAt: now,
          ),
        );

    return note.copyWith(
      title: safeTitle,
      content: note.content,
      category: normalizedCat,
      tags: normalizedTags,
      linkedModule: linkPair.$1,
      linkedId: linkPair.$2,
      clearLink: linkPair.$1 == null,
      updatedAt: now,
    );
  }

  @override
  Future<NoteEntity> updateNote(NoteEntity note) async {
    final now = EthiopiaClock.nowUtc();
    final safeTitle = NoteEntity.clampTitle(note.title);
    final normalizedCat = NoteEntity.normalizeCategory(note.category);
    final normalizedTags = NoteDomainHelpers.normalizeTags(note.tags);
    final linkPair =
        NoteEntity.normalizeLinkPair(note.linkedModule, note.linkedId);

    final updatedRows =
        await (_db.update(_db.notes)..where((tbl) => tbl.id.equals(note.id)))
            .write(
      NotesCompanion(
        title: Value(safeTitle),
        content: Value(note.content),
        category: Value(normalizedCat),
        projectId: Value(note.projectId),
        goalId: Value(note.goalId),
        linkedModule: Value(linkPair.$1),
        linkedId: Value(linkPair.$2),
        tagsJson: Value(jsonEncode(normalizedTags)),
        isPinned: Value(note.isPinned),
        isFavorite: Value(note.isFavorite),
        isArchived: Value(note.isArchived),
        isTrashed: Value(note.isTrashed),
        updatedAt: Value(now),
      ),
    );

    if (updatedRows == 0) {
      throw StateError('Note "${note.id}" not found for update.');
    }

    return note.copyWith(
      title: safeTitle,
      content: note.content,
      category: normalizedCat,
      tags: normalizedTags,
      linkedModule: linkPair.$1,
      linkedId: linkPair.$2,
      clearLink: linkPair.$1 == null,
      updatedAt: now,
    );
  }

  @override
  Future<int> clearLinksForTarget({
    required String linkedModule,
    required String linkedId,
  }) async {
    final pair = NoteEntity.normalizeLinkPair(linkedModule, linkedId);
    if (pair.$1 == null || pair.$2 == null) return 0;
    final now = EthiopiaClock.nowUtc();
    return (_db.update(_db.notes)
          ..where(
            (tbl) =>
                tbl.linkedModule.equals(pair.$1!) &
                tbl.linkedId.equals(pair.$2!),
          ))
        .write(
      NotesCompanion(
        linkedModule: const Value(null),
        linkedId: const Value(null),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> deleteNote(String id) async {
    await (_db.delete(_db.notes)..where((tbl) => tbl.id.equals(id))).go();
  }

  @override
  Future<List<NoteEntity>> searchNotes(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    final candidates = await getNotes(
      includeArchived: true,
      includeTrashed: false,
    );
    final matches =
        candidates.where((note) => note.matchesQuery(clean)).toList();
    matches.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return matches;
  }
}
