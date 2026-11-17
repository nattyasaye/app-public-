import '../../domain/notes/note_models.dart';

/// Immutable state container for the Daywell Notes & Knowledge module.
class NotesModuleState {
  final List<NoteEntity> notes;

  // Presentation / Filter State
  final String searchQuery;
  final String
      categoryFilter; // 'all', 'general', 'reference', 'reflection', 'learning'
  final String
      sectionFilter; // 'active', 'pinned', 'favorites', 'archive', 'trash'
  final String sortBy; // 'recent', 'alpha', 'oldest'
  final bool isGridView;
  final bool isLoading;
  final String? errorMessage;

  const NotesModuleState({
    this.notes = const [],
    this.searchQuery = '',
    this.categoryFilter = 'all',
    this.sectionFilter = 'active',
    this.sortBy = 'recent',
    this.isGridView = false,
    this.isLoading = false,
    this.errorMessage,
  });

  NotesModuleState copyWith({
    List<NoteEntity>? notes,
    String? searchQuery,
    String? categoryFilter,
    String? sectionFilter,
    String? sortBy,
    bool? isGridView,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NotesModuleState(
      notes: notes ?? this.notes,
      searchQuery: searchQuery ?? this.searchQuery,
      categoryFilter: categoryFilter ?? this.categoryFilter,
      sectionFilter: sectionFilter ?? this.sectionFilter,
      sortBy: sortBy ?? this.sortBy,
      isGridView: isGridView ?? this.isGridView,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  NoteEntity? findById(String id) {
    for (final note in notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  // --- Derived Calculations & Filtered Notes ---

  List<NoteEntity> get filteredNotes {
    final list = notes.where((note) {
      if (sectionFilter == 'trash') {
        if (!note.isTrashed) return false;
      } else if (sectionFilter == 'archive') {
        if (!note.isArchived || note.isTrashed) return false;
      } else {
        if (note.isTrashed || note.isArchived) return false;
        if (sectionFilter == 'pinned' && !note.isPinned) return false;
        if (sectionFilter == 'favorites' && !note.isFavorite) return false;
      }

      if (categoryFilter != 'all' && note.category != categoryFilter) {
        return false;
      }

      if (!note.matchesQuery(searchQuery)) {
        return false;
      }

      return true;
    }).toList();

    list.sort((a, b) {
      // Pinned notes bubble to top if not in trash/archive
      if (sectionFilter != 'trash' && sectionFilter != 'archive') {
        final aPin = a.isPinned ? 0 : 1;
        final bPin = b.isPinned ? 0 : 1;
        if (aPin != bPin) return aPin.compareTo(bPin);
      }

      if (sortBy == 'alpha') {
        return a.displayTitle
            .toLowerCase()
            .compareTo(b.displayTitle.toLowerCase());
      } else if (sortBy == 'oldest') {
        return a.createdAt.compareTo(b.createdAt);
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return list;
  }

  int get activeNotesCount =>
      notes.where((n) => !n.isTrashed && !n.isArchived).length;
  int get pinnedNotesCount =>
      notes.where((n) => n.isPinned && !n.isTrashed && !n.isArchived).length;
  int get favoriteNotesCount =>
      notes.where((n) => n.isFavorite && !n.isTrashed && !n.isArchived).length;
  int get archivedNotesCount =>
      notes.where((n) => n.isArchived && !n.isTrashed).length;
  int get trashedNotesCount => notes.where((n) => n.isTrashed).length;

  Set<String> get availableCategories {
    final cats = Set<String>.from(NoteEntity.defaultCategories);
    for (final n in notes) {
      if (n.category.isNotEmpty) cats.add(n.category);
    }
    return cats;
  }
}
