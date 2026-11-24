import '../../core/shared_foundation_core.dart';
import 'note_models.dart';

/// Pure domain helpers for Daywell Notes rules.
///
/// Zero dependencies on Flutter widgets or Drift SQLite.
/// Keeps title bounds, tag normalization, folder/category defaults,
/// lifecycle predicates, polymorphic link validation, and deterministic
/// sorting equivalent to `src/domain/noteHelpers.ts`.
enum NoteLifecycleState {
  active,
  archived,
  trashed,
}

enum NoteSortMode {
  recent,
  alpha,
  oldest,
}

class NoteTitleValidationResult {
  final bool valid;
  final String normalized;
  final String? error;

  const NoteTitleValidationResult({
    required this.valid,
    required this.normalized,
    this.error,
  });
}

class NoteDomainHelpers {
  const NoteDomainHelpers._();

  static const String defaultTitle = 'Untitled Note';
  static const int maxTitleLength = SharedNoteContracts.maxTitleLength;

  static final Set<String> _supportedLinkModules =
      SharedNoteContracts.canonicalLinkedModules.toSet();

  static bool isValidTitle(String? rawTitle) {
    if (rawTitle == null) return false;
    final trimmed = rawTitle.trim();
    return trimmed.isNotEmpty && trimmed.length <= maxTitleLength;
  }

  static String normalizeTitle(
    String? rawTitle, {
    String fallbackTitle = defaultTitle,
  }) {
    final trimmed = rawTitle?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      return trimmed.length <= maxTitleLength
          ? trimmed
          : trimmed.substring(0, maxTitleLength);
    }
    final rawFallback = fallbackTitle.trim();
    final safeFallback = rawFallback.isNotEmpty ? rawFallback : defaultTitle;
    return safeFallback.length <= maxTitleLength
        ? safeFallback
        : safeFallback.substring(0, maxTitleLength);
  }

  static NoteTitleValidationResult validateTitle(
    String? rawTitle, {
    String fallbackTitle = defaultTitle,
  }) {
    final trimmed = rawTitle?.trim() ?? '';
    if (trimmed.isEmpty) {
      return NoteTitleValidationResult(
        valid: false,
        normalized: normalizeTitle(rawTitle, fallbackTitle: fallbackTitle),
        error: 'Note title cannot be empty.',
      );
    }
    if (trimmed.length > maxTitleLength) {
      return NoteTitleValidationResult(
        valid: false,
        normalized: trimmed.substring(0, maxTitleLength),
        error: 'Note title cannot exceed $maxTitleLength characters.',
      );
    }
    return NoteTitleValidationResult(
      valid: true,
      normalized: trimmed,
    );
  }

  static List<String> normalizeTags(Iterable<String>? rawTags) {
    if (rawTags == null) return const <String>[];
    final seenLower = <String>{};
    final normalized = <String>[];
    for (final entry in rawTags) {
      final trimmed = entry.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (!seenLower.add(key)) continue;
      normalized.add(trimmed);
    }
    return List<String>.unmodifiable(normalized);
  }

  static String normalizeFolder(
    String? rawFolder, {
    String defaultFolder = SharedNoteContracts.defaultExchangeFolder,
    bool lowercase = false,
  }) {
    final rawDefault = defaultFolder.trim();
    final safeDefault = rawDefault.isNotEmpty
        ? rawDefault
        : SharedNoteContracts.defaultExchangeFolder;
    final trimmed = rawFolder?.trim() ?? '';
    if (trimmed.isEmpty) {
      return lowercase ? safeDefault.toLowerCase() : safeDefault;
    }
    return lowercase ? trimmed.toLowerCase() : trimmed;
  }

  static String normalizeFlutterCategory(String? rawCategory) {
    return normalizeFolder(
      rawCategory,
      defaultFolder: SharedNoteContracts.defaultFlutterCategory,
      lowercase: true,
    );
  }

  static String normalizeWebNotebook(String? rawNotebook) {
    return normalizeFolder(
      rawNotebook,
      defaultFolder: SharedNoteContracts.defaultWebNotebook,
      lowercase: false,
    );
  }

  static String normalizeExchangeFolder(String? rawFolder) {
    return normalizeFolder(
      rawFolder,
      defaultFolder: SharedNoteContracts.defaultExchangeFolder,
      lowercase: false,
    );
  }

  static bool isTrashed(NoteEntity note) => note.isTrashed;

  static bool isArchived(NoteEntity note) =>
      note.isArchived && !note.isTrashed;

  static bool isActive(NoteEntity note) =>
      !note.isTrashed && !note.isArchived;

  static bool isPinnedActive(NoteEntity note) =>
      isActive(note) && note.isPinned;

  static bool isFavoriteActive(NoteEntity note) =>
      isActive(note) && note.isFavorite;

  static NoteLifecycleState getLifecycleState(NoteEntity note) {
    if (isTrashed(note)) return NoteLifecycleState.trashed;
    if (isArchived(note)) return NoteLifecycleState.archived;
    return NoteLifecycleState.active;
  }

  static bool isSupportedLinkModule(String? rawModule) {
    if (rawModule == null) return false;
    final normalized = rawModule.trim().toLowerCase();
    return normalized.isNotEmpty && _supportedLinkModules.contains(normalized);
  }

  static (String?, String?) normalizeLinkPair(
    String? rawModule,
    String? rawId,
  ) {
    final mod = rawModule?.trim().toLowerCase();
    final id = rawId?.trim();
    if (mod == null ||
        mod.isEmpty ||
        !_supportedLinkModules.contains(mod) ||
        id == null ||
        id.isEmpty) {
      return (null, null);
    }
    return (mod, id);
  }

  static bool hasValidLink(NoteEntity note) {
    final pair = normalizeLinkPair(note.linkedModule, note.linkedId);
    return pair.$1 != null && pair.$2 != null;
  }

  static NoteSortMode parseSortMode(String? rawSort) {
    final normalized = rawSort?.trim().toLowerCase() ?? '';
    if (normalized == 'alpha') return NoteSortMode.alpha;
    if (normalized == 'oldest') return NoteSortMode.oldest;
    return NoteSortMode.recent;
  }

  static int compareNotes(
    NoteEntity a,
    NoteEntity b, {
    NoteSortMode sortBy = NoteSortMode.recent,
    bool pinFirst = true,
  }) {
    if (pinFirst && a.isPinned != b.isPinned) {
      return a.isPinned ? -1 : 1;
    }

    if (sortBy == NoteSortMode.alpha) {
      final titleCmp = normalizeTitle(a.title)
          .toLowerCase()
          .compareTo(normalizeTitle(b.title).toLowerCase());
      if (titleCmp != 0) return titleCmp;
      final updatedCmp = b.updatedAt
          .toUtc()
          .millisecondsSinceEpoch
          .compareTo(a.updatedAt.toUtc().millisecondsSinceEpoch);
      if (updatedCmp != 0) return updatedCmp;
      return a.id.compareTo(b.id);
    }

    if (sortBy == NoteSortMode.oldest) {
      final createdCmp = a.createdAt
          .toUtc()
          .millisecondsSinceEpoch
          .compareTo(b.createdAt.toUtc().millisecondsSinceEpoch);
      if (createdCmp != 0) return createdCmp;
      final updatedCmp = a.updatedAt
          .toUtc()
          .millisecondsSinceEpoch
          .compareTo(b.updatedAt.toUtc().millisecondsSinceEpoch);
      if (updatedCmp != 0) return updatedCmp;
      return a.id.compareTo(b.id);
    }

    final updatedCmp = b.updatedAt
        .toUtc()
        .millisecondsSinceEpoch
        .compareTo(a.updatedAt.toUtc().millisecondsSinceEpoch);
    if (updatedCmp != 0) return updatedCmp;
    final createdCmp = b.createdAt
        .toUtc()
        .millisecondsSinceEpoch
        .compareTo(a.createdAt.toUtc().millisecondsSinceEpoch);
    if (createdCmp != 0) return createdCmp;
    return a.id.compareTo(b.id);
  }

  static List<NoteEntity> sortNotes(
    Iterable<NoteEntity> notes, {
    NoteSortMode sortBy = NoteSortMode.recent,
    bool pinFirst = true,
  }) {
    final sorted = notes.toList();
    sorted.sort(
      (a, b) => compareNotes(
        a,
        b,
        sortBy: sortBy,
        pinFirst: pinFirst,
      ),
    );
    return List<NoteEntity>.unmodifiable(sorted);
  }
}
