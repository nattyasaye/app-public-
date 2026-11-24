import '../../domain/notes/note_helpers.dart';
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
        if (!NoteDomainHelpers.isTrashed(note)) return false;
      } else if (sectionFilter == 'archive') {
        if (!NoteDomainHelpers.isArchived(note)) return false;
      } else {
        if (!NoteDomainHelpers.isActive(note)) return false;
        if (sectionFilter == 'pinned' && !note.isPinned) return false;
        if (sectionFilter == 'favorites' && !note.isFavorite) return false;
      }

      if (categoryFilter != 'all' &&
          note.category !=
              NoteDomainHelpers.normalizeFlutterCategory(categoryFilter)) {
        return false;
      }

      if (!note.matchesQuery(searchQuery)) {
        return false;
      }

      return true;
    });

    return NoteDomainHelpers.sortNotes(
      list,
      sortBy: NoteDomainHelpers.parseSortMode(sortBy),
      pinFirst: sectionFilter != 'trash' && sectionFilter != 'archive',
    );
  }

  int get activeNotesCount =>
      notes.where(NoteDomainHelpers.isActive).length;
  int get pinnedNotesCount =>
      notes.where(NoteDomainHelpers.isPinnedActive).length;
  int get favoriteNotesCount =>
      notes.where(NoteDomainHelpers.isFavoriteActive).length;
  int get archivedNotesCount =>
      notes.where(NoteDomainHelpers.isArchived).length;
  int get trashedNotesCount => notes.where(NoteDomainHelpers.isTrashed).length;

  Set<String> get availableCategories {
    final cats = Set<String>.from(NoteEntity.defaultCategories);
    for (final n in notes) {
      if (!n.isTrashed && n.category.isNotEmpty) {
        cats.add(n.category);
      }
    }
    return cats;
  }

  Set<String> get availableAllCategories {
    final cats = Set<String>.from(NoteEntity.defaultCategories);
    for (final n in notes) {
      if (n.category.isNotEmpty) {
        cats.add(n.category);
      }
    }
    return cats;
  }
}
