import 'package:flutter/foundation.dart';
import '../../core/date/shared_date.dart';
import '../../domain/notes/note_models.dart';
import '../../domain/notes/note_contracts.dart';
import 'notes_state.dart';

/// Module-scoped application controller for Daywell Notes & Knowledge management.
///
/// Sole runtime owner of Notes module state. Coordinates authoritative
/// SQLite persistence via [INotesRepository], including tags, pins,
/// favorites, archive, and soft-trash flags.
class NotesController extends ChangeNotifier {
  final INotesRepository _repository;
  NotesModuleState _state;
  bool _isDisposed = false;

  NotesController({
    required INotesRepository repository,
    NotesModuleState? initialState,
  })  : _repository = repository,
        _state = initialState ?? const NotesModuleState();

  NotesModuleState get state => _state;

  // --- Presentation / Filter Controls ---

  void setSearchQuery(String query) {
    _state = _state.copyWith(searchQuery: query);
    notifyListeners();
  }

  void setCategoryFilter(String category) {
    _state = _state.copyWith(categoryFilter: category);
    notifyListeners();
  }

  void setSectionFilter(String section) {
    _state = _state.copyWith(sectionFilter: section);
    notifyListeners();
  }

  void setSortBy(String sortBy) {
    _state = _state.copyWith(sortBy: sortBy);
    notifyListeners();
  }

  void toggleGridView() {
    _state = _state.copyWith(isGridView: !_state.isGridView);
    notifyListeners();
  }

  void clearFilters() {
    _state = _state.copyWith(
      searchQuery: '',
      categoryFilter: 'all',
      sectionFilter: 'active',
      sortBy: 'recent',
    );
    notifyListeners();
  }

  // --- Loading & Initialization ---

  Future<void> loadNotes() async {
    _state = _state.copyWith(isLoading: true, clearError: true);
    notifyListeners();
    try {
      final persisted = await _repository.getNotes(
        includeArchived: true,
        includeTrashed: true,
      );
      _state = _state.copyWith(
        notes: List<NoteEntity>.unmodifiable(persisted),
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

  /// Replaces the controller's in-memory list immediately after database
  /// restore or seed purge if needed by tests.
  void replaceNotes(List<NoteEntity> notes) {
    _state = _state.copyWith(
      notes: List<NoteEntity>.unmodifiable(notes),
      clearError: true,
    );
    notifyListeners();
  }

  void _upsertInState(NoteEntity note) {
    final idx = _state.notes.indexWhere((n) => n.id == note.id);
    final next = List<NoteEntity>.from(_state.notes);
    if (idx == -1) {
      next.insert(0, note);
    } else {
      next[idx] = note;
    }
    _state = _state.copyWith(
        notes: List<NoteEntity>.unmodifiable(next), clearError: true);
  }

  // --- Note Workflow Orchestration ---

  Future<NoteEntity> createNote({
    String? id,
    required String title,
    required String content,
    String category = 'general',
    String? projectId,
    String? goalId,
    String? linkedModule,
    String? linkedId,
    List<String> tags = const [],
    bool isPinned = false,
    bool isFavorite = false,
  }) async {
    final now = EthiopiaClock.nowUtc();
    final safeTitle = NoteEntity.clampTitle(title);
    final linkPair = NoteEntity.normalizeLinkPair(linkedModule, linkedId);
    final note = NoteEntity(
      id: id ?? 'note-${now.millisecondsSinceEpoch}',
      title: safeTitle,
      content: content.trim(),
      category: category,
      projectId: projectId,
      goalId: goalId,
      linkedModule: linkPair.$1,
      linkedId: linkPair.$2,
      tags: tags,
      isPinned: isPinned,
      isFavorite: isFavorite,
      isArchived: false,
      isTrashed: false,
      createdAt: now,
      updatedAt: now,
    );

    try {
      final created = await _repository.createNote(note);
      _upsertInState(created);
      notifyListeners();
      return created;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return note;
    }
  }

  Future<void> updateNote({
    required String id,
    required String title,
    required String content,
    String? category,
    List<String>? tags,
    String? linkedModule,
    String? linkedId,
    bool clearLink = false,
  }) async {
    final existing = _state.findById(id);
    if (existing == null) return;

    final safeTitle = NoteEntity.clampTitle(title);
    final updated = existing.copyWith(
      title: safeTitle,
      content: content.trim(),
      category: category ?? existing.category,
      tags: tags ?? existing.tags,
      linkedModule: linkedModule,
      linkedId: linkedId,
      clearLink: clearLink,
      updatedAt: EthiopiaClock.nowUtc(),
    );

    try {
      final saved = await _repository.updateNote(updated);
      _upsertInState(saved);
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<NoteEntity?> duplicateNote(String id) async {
    final existing = _state.findById(id);
    if (existing == null) return null;
    return createNote(
      title: '${existing.displayTitle} (Copy)',
      content: existing.content,
      category: existing.category,
      projectId: existing.projectId,
      goalId: existing.goalId,
      tags: existing.tags,
    );
  }

  Future<void> updateTags(String id, List<String> tags) async {
    final existing = _state.findById(id);
    if (existing == null) return;

    final updated = existing.copyWith(
      tags: List<String>.from(tags),
      updatedAt: EthiopiaClock.nowUtc(),
    );

    try {
      final saved = await _repository.updateNote(updated);
      _upsertInState(saved);
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<NoteEntity?> linkNoteToEntity(
    String id, {
    required String module,
    required String entityId,
  }) async {
    final existing = _state.findById(id);
    if (existing == null) return null;
    final pair = NoteEntity.normalizeLinkPair(module, entityId);
    if (pair.$1 == null || pair.$2 == null) return existing;

    final updated = existing.copyWith(
      linkedModule: pair.$1,
      linkedId: pair.$2,
      updatedAt: EthiopiaClock.nowUtc(),
    );

    try {
      final saved = await _repository.updateNote(updated);
      _upsertInState(saved);
      notifyListeners();
      return saved;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<NoteEntity?> unlinkNote(String id) async {
    final existing = _state.findById(id);
    if (existing == null) return null;
    if (existing.linkedModule == null && existing.linkedId == null) {
      return existing;
    }

    final updated = existing.copyWith(
      clearLink: true,
      updatedAt: EthiopiaClock.nowUtc(),
    );

    try {
      final saved = await _repository.updateNote(updated);
      _upsertInState(saved);
      notifyListeners();
      return saved;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<void> clearLinksForTarget({
    required String module,
    required String targetId,
  }) async {
    final pair = NoteEntity.normalizeLinkPair(module, targetId);
    if (pair.$1 == null || pair.$2 == null) return;
    try {
      await _repository.clearLinksForTarget(
        linkedModule: pair.$1!,
        linkedId: pair.$2!,
      );
      final now = EthiopiaClock.nowUtc();
      final next = _state.notes.map((n) {
        if (n.linkedModule == pair.$1 && n.linkedId == pair.$2) {
          return n.copyWith(clearLink: true, updatedAt: now);
        }
        return n;
      }).toList(growable: false);
      _state = _state.copyWith(
        notes: List<NoteEntity>.unmodifiable(next),
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> togglePin(String id) async {
    final existing = _state.findById(id);
    if (existing == null) return;

    final updated = existing.copyWith(isPinned: !existing.isPinned);
    try {
      final saved = await _repository.updateNote(updated);
      _upsertInState(saved);
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> toggleFavorite(String id) async {
    final existing = _state.findById(id);
    if (existing == null) return;

    final updated = existing.copyWith(isFavorite: !existing.isFavorite);
    try {
      final saved = await _repository.updateNote(updated);
      _upsertInState(saved);
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> toggleArchive(String id) async {
    final existing = _state.findById(id);
    if (existing == null) return;

    final updated = existing.copyWith(isArchived: !existing.isArchived);
    try {
      final saved = await _repository.updateNote(updated);
      _upsertInState(saved);
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> deleteNote(String id) async {
    final existing = _state.findById(id);
    if (existing == null) return;

    if (existing.isTrashed) {
      await permanentlyDeleteNote(id);
      return;
    }

    final trashed = existing.copyWith(isTrashed: true);
    try {
      final saved = await _repository.updateNote(trashed);
      _upsertInState(saved);
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> permanentlyDeleteNote(String id) async {
    try {
      await _repository.deleteNote(id);
      final remaining = _state.notes.where((n) => n.id != id).toList();
      _state = _state.copyWith(
        notes: List<NoteEntity>.unmodifiable(remaining),
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> restoreFromTrash(String id) async {
    final existing = _state.findById(id);
    if (existing == null) return;

    final restored = existing.copyWith(isTrashed: false);
    try {
      final saved = await _repository.updateNote(restored);
      _upsertInState(saved);
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> emptyTrash() async {
    final trashedIds =
        _state.notes.where((n) => n.isTrashed).map((n) => n.id).toList();
    try {
      for (final id in trashedIds) {
        await _repository.deleteNote(id);
      }
      final remaining = _state.notes.where((n) => !n.isTrashed).toList();
      _state = _state.copyWith(
        notes: List<NoteEntity>.unmodifiable(remaining),
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
