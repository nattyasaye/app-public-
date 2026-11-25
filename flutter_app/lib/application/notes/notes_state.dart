import '../../domain/notes/note_helpers.dart';
import '../../domain/notes/note_models.dart';

/// Immutable state container for the Daywell Notes & Knowledge module.
class NotesModuleState {
  final List<NoteEntity> notes;
  final List<String> customFolders;

  // Presentation / Filter State
  final String searchQuery;
  final String
      categoryFilter; // 'all', 'general', 'reference', 'reflection', 'learning', or custom folder
  final String tagFilter; // 'all' or tag name
  final String
      dateFilter; // 'all', 'updated_7d', 'updated_30d', 'created_7d', 'created_30d'
  final String
      sectionFilter; // 'active', 'pinned', 'favorites', 'archive', 'trash'
  final String sortBy; // 'recent', 'created', 'alpha', 'oldest'
  final bool isGridView;
  final bool isLoading;
  final String? errorMessage;

  const NotesModuleState({
    this.notes = const [],
    this.customFolders = const [],
    this.searchQuery = '',
    this.categoryFilter = 'all',
    this.tagFilter = 'all',
    this.dateFilter = 'all',
    this.sectionFilter = 'active',
    this.sortBy = 'recent',
    this.isGridView = false,
    this.isLoading = false,
    this.errorMessage,
  });

  NotesModuleState copyWith({
    List<NoteEntity>? notes,
    List<String>? customFolders,
    String? searchQuery,
    String? categoryFilter,
    String? tagFilter,
    String? dateFilter,
    String? sectionFilter,
    String? sortBy,
    bool? isGridView,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NotesModuleState(
      notes: notes ?? this.notes,
      customFolders: customFolders ?? this.customFolders,
      searchQuery: searchQuery ?? this.searchQuery,
      categoryFilter: categoryFilter ?? this.categoryFilter,
      tagFilter: tagFilter ?? this.tagFilter,
      dateFilter: dateFilter ?? this.dateFilter,
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

  List<NoteEntity> get filteredNotes => filterNotes();

  List<NoteEntity> filterNotes({
    Map<String, String>? projectTitlesById,
    Map<String, String>? eventTitlesById,
  }) {
    final parsedDateFilter = NoteDomainHelpers.parseDateFilterMode(dateFilter);
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

      if (!NoteDomainHelpers.matchesTagFilter(note.tags, tagFilter)) {
        return false;
      }

      if (!NoteDomainHelpers.matchesDateFilter(note, parsedDateFilter)) {
        return false;
      }

      final projectTitle =
          note.projectId != null ? projectTitlesById?[note.projectId!] : null;
      final linkedEventTitle = note.linkedCalendarEventId != null
          ? eventTitlesById?[note.linkedCalendarEventId!]
          : null;
      if (!note.matchesQuery(
        searchQuery,
        projectTitle: projectTitle,
        linkedEventTitle: linkedEventTitle,
      )) {
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

  List<String> get availableTags => NoteDomainHelpers.collectUniqueTags(
        notes,
        includeArchived: true,
        includeTrashed: sectionFilter == 'trash',
      );

  Set<String> get availableCategories {
    final cats = Set<String>.from(NoteEntity.defaultCategories);
    for (final folder in customFolders) {
      if (folder.trim().isNotEmpty) {
        cats.add(NoteDomainHelpers.normalizeFlutterCategory(folder));
      }
    }
    for (final n in notes) {
      if (!n.isTrashed && n.category.isNotEmpty) {
        cats.add(n.category);
      }
    }
    return cats;
  }

  Set<String> get availableAllCategories {
    final cats = Set<String>.from(NoteEntity.defaultCategories);
    for (final folder in customFolders) {
      if (folder.trim().isNotEmpty) {
        cats.add(NoteDomainHelpers.normalizeFlutterCategory(folder));
      }
    }
    for (final n in notes) {
      if (n.category.isNotEmpty) {
        cats.add(n.category);
      }
    }
    return cats;
  }
}
