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

  static const String customFoldersSettingKey = 'notes_custom_folders';

  final INotesRepository _repository;
  final Future<List<String>> Function()? _loadCustomFolders;
  final Future<void> Function(List<String> folders)? _saveCustomFolders;
  NotesModuleState _state;
  Future<void> _mutationQueue = Future<void>.value();
  bool _isDisposed = false;

  NotesController({
    required INotesRepository repository,
    NotesModuleState? initialState,
    Future<List<String>> Function()? loadCustomFolders,
    Future<void> Function(List<String> folders)? saveCustomFolders,
  })  : _repository = repository,
        _loadCustomFolders = loadCustomFolders,
        _saveCustomFolders = saveCustomFolders,
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

  void setTagFilter(String tag) {
    final trimmed = tag.trim();
    final normalized =
        (trimmed.isEmpty || trimmed.toLowerCase() == 'all') ? 'all' : trimmed;
    _state = _state.copyWith(tagFilter: normalized);
    notifyListeners();
  }

  void setDateFilter(String dateFilter) {
    final parsed = NoteDomainHelpers.parseDateFilterMode(dateFilter);
    _state = _state.copyWith(
      dateFilter: NoteDomainHelpers.dateFilterKey(parsed),
    );
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
      tagFilter: 'all',
      dateFilter: 'all',
      sectionFilter: 'active',
      sortBy: 'recent',
    );
    notifyListeners();
  }

  // --- Loading & Initialization ---

  List<String> _normalizeFolderList(Iterable<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final entry in raw) {
      final trimmed = entry.trim();
      if (trimmed.isEmpty) continue;
      final norm = NoteDomainHelpers.normalizeFlutterCategory(trimmed);
      if (NoteEntity.defaultCategories.contains(norm)) continue;
      if (seen.add(norm)) {
        out.add(norm);
      }
    }
    return List<String>.unmodifiable(out);
  }

  Future<void> loadNotes() {
    return _enqueue(() async {
      _state = _state.copyWith(isLoading: true, clearError: true);
      notifyListeners();
      try {
        final persisted = await _repository.getNotes(
          includeArchived: true,
          includeTrashed: true,
        );
        var loadedCustomFolders = _state.customFolders;
        if (_loadCustomFolders != null) {
          try {
            loadedCustomFolders = _normalizeFolderList(
              await _loadCustomFolders!(),
            );
          } catch (_) {
            // Keep existing folders if optional settings lookup is unavailable.
          }
        }
        _state = _state.copyWith(
          notes: List<NoteEntity>.unmodifiable(persisted),
          customFolders: loadedCustomFolders,
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

  Future<({bool saved, String? errorMessage})> updateNote({
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
      if (existing == null || NoteDomainHelpers.isTrashed(existing)) {
        final reason = existing == null
            ? 'Note no longer exists and could not be updated.'
            : 'Cannot update a trashed note. Restore it from Trash first.';
        _state = _state.copyWith(errorMessage: reason);
        notifyListeners();
        return (saved: false, errorMessage: reason);
      }

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
        notifyListeners();
        return (saved: true, errorMessage: null);
      } catch (e) {
        final reason = e.toString();
        _state = _state.copyWith(errorMessage: reason);
        notifyListeners();
        return (saved: false, errorMessage: reason);
      }
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

  Future<({bool saved, String? errorMessage})> moveNoteToFolder(
    String id,
    String targetFolder,
  ) {
    return _enqueue(() async {
      final existing = _state.findById(id);
      if (existing == null || NoteDomainHelpers.isTrashed(existing)) {
        final reason = existing == null
            ? 'Note no longer exists.'
            : 'Restore note from Trash before moving folders.';
        _state = _state.copyWith(errorMessage: reason);
        notifyListeners();
        return (saved: false, errorMessage: reason);
      }
      final normalizedTarget =
          NoteDomainHelpers.normalizeFlutterCategory(targetFolder);
      if (existing.category == normalizedTarget) {
        return (saved: true, errorMessage: null);
      }
      final updated = existing.copyWith(
        category: normalizedTarget,
        updatedAt: EthiopiaClock.nowUtc(),
      );
      try {
        final saved = await _repository.updateNote(updated);
        _upsertInState(saved);
        notifyListeners();
        return (saved: true, errorMessage: null);
      } catch (e) {
        final reason = e.toString();
        _state = _state.copyWith(errorMessage: reason);
        notifyListeners();
        return (saved: false, errorMessage: reason);
      }
    });
  }

  Future<({bool ok, String? folder, String? errorMessage})> createFolder(
    String rawName,
  ) {
    return _enqueue(() async {
      final trimmed = rawName.trim();
      if (trimmed.isEmpty) {
        return (
          ok: false,
          folder: null,
          errorMessage: 'Folder name cannot be empty.',
        );
      }
      if (NoteDomainHelpers.isReservedFolderName(trimmed)) {
        return (
          ok: false,
          folder: null,
          errorMessage: '"$trimmed" is a reserved view name.',
        );
      }
      final normalized = NoteDomainHelpers.normalizeFlutterCategory(trimmed);
      if (_state.availableAllCategories.contains(normalized)) {
        return (
          ok: false,
          folder: null,
          errorMessage: 'Folder "$trimmed" already exists.',
        );
      }
      final nextCustomFolders =
          _normalizeFolderList([..._state.customFolders, normalized]);
      try {
        if (_saveCustomFolders != null) {
          await _saveCustomFolders!(nextCustomFolders);
        }
        _state = _state.copyWith(
          customFolders: nextCustomFolders,
          clearError: true,
        );
        notifyListeners();
        return (ok: true, folder: normalized, errorMessage: null);
      } catch (e) {
        final reason = e.toString();
        _state = _state.copyWith(errorMessage: reason);
        notifyListeners();
        return (ok: false, folder: null, errorMessage: reason);
      }
    });
  }

  Future<({bool ok, String? folder, int affectedCount, String? errorMessage})>
      renameFolder(String oldName, String newName) {
    return _enqueue(() async {
      final oldNorm = NoteDomainHelpers.normalizeFlutterCategory(oldName);
      if (NoteEntity.defaultCategories.contains(oldNorm)) {
        return (
          ok: false,
          folder: null,
          affectedCount: 0,
          errorMessage: 'Built-in folders cannot be renamed.',
        );
      }
      final trimmedNew = newName.trim();
      if (trimmedNew.isEmpty) {
        return (
          ok: false,
          folder: null,
          affectedCount: 0,
          errorMessage: 'Folder name cannot be empty.',
        );
      }
      if (NoteDomainHelpers.isReservedFolderName(trimmedNew)) {
        return (
          ok: false,
          folder: null,
          affectedCount: 0,
          errorMessage: '"$trimmedNew" is a reserved view name.',
        );
      }
      final newNorm = NoteDomainHelpers.normalizeFlutterCategory(trimmedNew);
      if (newNorm == oldNorm) {
        return (
          ok: true,
          folder: newNorm,
          affectedCount: 0,
          errorMessage: null,
        );
      }
      if (_state.availableAllCategories.contains(newNorm)) {
        return (
          ok: false,
          folder: null,
          affectedCount: 0,
          errorMessage: 'Folder "$trimmedNew" already exists.',
        );
      }

      var renamedCount = 0;
      final updatedById = <String, NoteEntity>{};
      try {
        for (final note in _state.notes) {
          if (NoteDomainHelpers.isTrashed(note)) continue;
          if (note.category != oldNorm) continue;
          final saved = await _repository.updateNote(
            note.copyWith(
              category: newNorm,
              updatedAt: EthiopiaClock.nowUtc(),
            ),
          );
          updatedById[saved.id] = saved;
          renamedCount++;
        }

        final nextNotes = _state.notes
            .map((n) => updatedById[n.id] ?? n)
            .toList(growable: false);
        final nextCustomFolders = _normalizeFolderList([
          for (final f in _state.customFolders)
            if (f != oldNorm) f,
          newNorm,
        ]);
        if (_saveCustomFolders != null) {
          await _saveCustomFolders!(nextCustomFolders);
        }
        _state = _state.copyWith(
          notes: List<NoteEntity>.unmodifiable(nextNotes),
          customFolders: nextCustomFolders,
          categoryFilter:
              _state.categoryFilter == oldNorm ? newNorm : _state.categoryFilter,
          clearError: true,
        );
        notifyListeners();
        return (
          ok: true,
          folder: newNorm,
          affectedCount: renamedCount,
          errorMessage: null,
        );
      } catch (e) {
        final reason = e.toString();
        _state = _state.copyWith(errorMessage: reason);
        notifyListeners();
        return (
          ok: false,
          folder: null,
          affectedCount: renamedCount,
          errorMessage: reason,
        );
      }
    });
  }

  Future<
      ({
        bool ok,
        int movedCount,
        String destinationFolder,
        String? errorMessage,
      })> deleteFolder(
    String folderName, {
    String destinationFolder = 'general',
  }) {
    return _enqueue(() async {
      final targetNorm = NoteDomainHelpers.normalizeFlutterCategory(folderName);
      if (NoteEntity.defaultCategories.contains(targetNorm)) {
        return (
          ok: false,
          movedCount: 0,
          destinationFolder: 'general',
          errorMessage: 'Built-in folders cannot be deleted.',
        );
      }
      final candidateDest = destinationFolder.trim().isEmpty
          ? 'general'
          : NoteDomainHelpers.normalizeFlutterCategory(destinationFolder);
      final safeDest = candidateDest == targetNorm ? 'general' : candidateDest;

      var movedCount = 0;
      final updatedById = <String, NoteEntity>{};
      try {
        for (final note in _state.notes) {
          if (NoteDomainHelpers.isTrashed(note)) continue;
          if (note.category != targetNorm) continue;
          final saved = await _repository.updateNote(
            note.copyWith(
              category: safeDest,
              updatedAt: EthiopiaClock.nowUtc(),
            ),
          );
          updatedById[saved.id] = saved;
          movedCount++;
        }

        final nextNotes = _state.notes
            .map((n) => updatedById[n.id] ?? n)
            .toList(growable: false);
        final nextCustomFolders = _normalizeFolderList(
          _state.customFolders.where((f) => f != targetNorm),
        );
        if (_saveCustomFolders != null) {
          await _saveCustomFolders!(nextCustomFolders);
        }
        _state = _state.copyWith(
          notes: List<NoteEntity>.unmodifiable(nextNotes),
          customFolders: nextCustomFolders,
          categoryFilter:
              _state.categoryFilter == targetNorm ? 'all' : _state.categoryFilter,
          clearError: true,
        );
        notifyListeners();
        return (
          ok: true,
          movedCount: movedCount,
          destinationFolder: safeDest,
          errorMessage: null,
        );
      } catch (e) {
        final reason = e.toString();
        _state = _state.copyWith(errorMessage: reason);
        notifyListeners();
        return (
          ok: false,
          movedCount: movedCount,
          destinationFolder: safeDest,
          errorMessage: reason,
        );
      }
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
