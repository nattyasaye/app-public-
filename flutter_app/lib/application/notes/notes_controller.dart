import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../core/date/shared_date.dart';
import '../../domain/notes/note_helpers.dart';
import '../../domain/notes/note_models.dart';
import '../../domain/notes/note_contracts.dart';
import 'notes_state.dart';

/// Module-scoped application controller for Daywell Notes & Knowledge management.
///
/// Sole runtime owner of Notes module state. Coordinates authoritative
/// SQLite persistence via [INotesRepository], including tags, pins,
/// favorites, archive, and soft-trash flags.
class NotesController extends ChangeNotifier {
  static const Uuid _uuid = Uuid();

  final INotesRepository _repository;
  NotesModuleState _state;
  Future<void> _mutationQueue = Future<void>.value();
  bool _isDisposed = false;

  NotesController({
    required INotesRepository repository,
    NotesModuleState? initialState,
  })  : _repository = repository,
        _state = initialState ?? const NotesModuleState();

  NotesModuleState get state => _state;

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _mutationQueue = _mutationQueue.catchError((Object _) {}).then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  // --- Presentation / Filter Controls ---

  void setSearchQuery(String query) {
    _state = _state.copyWith(searchQuery: query);
    notifyListeners();
  }

  void setCategoryFilter(String category) {
    final normalized = category == 'all'
        ? 'all'
        : NoteDomainHelpers.normalizeFlutterCategory(category);
    _state = _state.copyWith(categoryFilter: normalized);
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

  Future<void> loadNotes() {
    return _enqueue(() async {
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
    });
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
  }) {
    return _enqueue(() async {
      final now = EthiopiaClock.nowUtc();
      final safeTitle = NoteEntity.clampTitle(title);
      final linkPair = NoteEntity.normalizeLinkPair(linkedModule, linkedId);
      final normalizedTags = NoteDomainHelpers.normalizeTags(tags);
      final note = NoteEntity(
        id: id ?? 'note-${_uuid.v4()}',
        title: safeTitle,
        content: content,
        category: category,
        projectId: projectId,
        goalId: goalId,
        linkedModule: linkPair.$1,
        linkedId: linkPair.$2,
        tags: normalizedTags,
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
    });
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
  }) {
    return _enqueue(() async {
      final existing = _state.findById(id);
      if (existing == null || NoteDomainHelpers.isTrashed(existing)) return;

      final safeTitle = NoteEntity.clampTitle(title);
      final normalizedTags = tags != null
          ? NoteDomainHelpers.normalizeTags(tags)
          : existing.tags;
      final updated = existing.copyWith(
        title: safeTitle,
        content: content,
        category: category ?? existing.category,
        tags: normalizedTags,
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
    });
  }

  Future<NoteEntity?> duplicateNote(String id) {
    return _enqueue(() async {
      final existing = _state.findById(id);
      if (existing == null || NoteDomainHelpers.isTrashed(existing)) {
        return null;
      }
      final now = EthiopiaClock.nowUtc();
      final safeTitle = NoteEntity.clampTitle('${existing.displayTitle} (Copy)');
      final note = NoteEntity(
        id: 'note-${_uuid.v4()}',
        title: safeTitle,
        content: existing.content,
        category: existing.category,
        projectId: existing.projectId,
        goalId: existing.goalId,
        tags: NoteDomainHelpers.normalizeTags(existing.tags),
        isPinned: false,
        isFavorite: false,
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
    });
  }

  Future<void> updateTags(String id, List<String> tags) {
    return _enqueue(() async {
      final existing = _state.findById(id);
      if (existing == null || NoteDomainHelpers.isTrashed(existing)) return;

      final updated = existing.copyWith(
        tags: NoteDomainHelpers.normalizeTags(tags),
        updatedAt: EthiopiaClock.nowUtc(),
      );

      try {
        final saved = await _repository.updateNote(updated);
        _upsertInState(saved);
      } catch (e) {
        _state = _state.copyWith(errorMessage: e.toString());
      }
      notifyListeners();
    });
  }

  Future<NoteEntity?> linkNoteToEntity(
    String id, {
    required String module,
    required String entityId,
  }) {
    return _enqueue(() async {
      final existing = _state.findById(id);
      if (existing == null || NoteDomainHelpers.isTrashed(existing)) {
        return null;
      }
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
    });
  }

  Future<NoteEntity?> unlinkNote(String id) {
    return _enqueue(() async {
      final existing = _state.findById(id);
      if (existing == null || NoteDomainHelpers.isTrashed(existing)) {
        return null;
      }
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
    });
  }

  Future<void> clearLinksForTarget({
    required String module,
    required String targetId,
  }) {
    return _enqueue(() async {
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
    });
  }

  Future<void> togglePin(String id) {
    return _enqueue(() async {
      final existing = _state.findById(id);
      if (existing == null || NoteDomainHelpers.isTrashed(existing)) return;

      final updated = existing.copyWith(isPinned: !existing.isPinned);
      try {
        final saved = await _repository.updateNote(updated);
        _upsertInState(saved);
      } catch (e) {
        _state = _state.copyWith(errorMessage: e.toString());
      }
      notifyListeners();
    });
  }

  Future<void> toggleFavorite(String id) {
    return _enqueue(() async {
      final existing = _state.findById(id);
      if (existing == null || NoteDomainHelpers.isTrashed(existing)) return;

      final updated = existing.copyWith(isFavorite: !existing.isFavorite);
      try {
        final saved = await _repository.updateNote(updated);
        _upsertInState(saved);
      } catch (e) {
        _state = _state.copyWith(errorMessage: e.toString());
      }
      notifyListeners();
    });
  }

  Future<void> toggleArchive(String id) {
    return _enqueue(() async {
      final existing = _state.findById(id);
      if (existing == null || NoteDomainHelpers.isTrashed(existing)) return;

      final updated = existing.copyWith(isArchived: !existing.isArchived);
      try {
        final saved = await _repository.updateNote(updated);
        _upsertInState(saved);
      } catch (e) {
        _state = _state.copyWith(errorMessage: e.toString());
      }
      notifyListeners();
    });
  }

  Future<void> deleteNote(String id) {
    return _enqueue(() async {
      final existing = _state.findById(id);
      if (existing == null || NoteDomainHelpers.isTrashed(existing)) return;

      final trashed = existing.copyWith(isTrashed: true);
      try {
        final saved = await _repository.updateNote(trashed);
        _upsertInState(saved);
      } catch (e) {
        _state = _state.copyWith(errorMessage: e.toString());
      }
      notifyListeners();
    });
  }

  Future<void> permanentlyDeleteNote(String id) {
    return _enqueue(() async {
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
    });
  }

  Future<void> restoreFromTrash(String id) {
    return _enqueue(() async {
      final existing = _state.findById(id);
      if (existing == null || !NoteDomainHelpers.isTrashed(existing)) return;

      final restored = existing.copyWith(isTrashed: false);
      try {
        final saved = await _repository.updateNote(restored);
        _upsertInState(saved);
      } catch (e) {
        _state = _state.copyWith(errorMessage: e.toString());
      }
      notifyListeners();
    });
  }

  Future<void> emptyTrash() {
    return _enqueue(() async {
      final trashedIds =
          _state.notes.where((n) => n.isTrashed).map((n) => n.id).toList();
      if (trashedIds.isEmpty) return;
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
    });
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
