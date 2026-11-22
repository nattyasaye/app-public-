import '../../core/date/shared_date.dart';

/// Pure domain models for the Daywell Notes module.
///
/// Invariants:
/// - Zero dependencies on Flutter widgets or Drift SQLite implementation.
/// - Immutable value objects with copyWith and JSON serialization.

class NoteEntity {
  static const String taskLinkModule = 'tasks';
  static const Set<String> allowedLinkedModules = <String>{
    'tasks',
    'finance',
    'calendar',
  };
  static const int maxTitleLength = 250;

  static const List<String> defaultCategories = [
    'general',
    'reference',
    'reflection',
    'learning',
  ];

  final String id;
  final String title;
  final String content; // Full Unicode support for Amharic / Ge'ez
  final String category; // 'general', 'reference', 'reflection', 'learning'
  final String? projectId;
  final String? goalId;
  final String? linkedModule;
  final String? linkedId;
  final List<String> tags;
  final bool isPinned;
  final bool isFavorite;
  final bool isArchived;
  final bool isTrashed;
  final DateTime createdAt;
  final DateTime updatedAt;

  NoteEntity({
    required this.id,
    required this.title,
    required this.content,
    String category = 'general',
    this.projectId,
    this.goalId,
    String? linkedModule,
    String? linkedId,
    List<String> tags = const [],
    this.isPinned = false,
    this.isFavorite = false,
    this.isArchived = false,
    this.isTrashed = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : category = normalizeCategory(category),
        linkedModule = normalizeLinkPair(linkedModule, linkedId).$1,
        linkedId = normalizeLinkPair(linkedModule, linkedId).$2,
        tags = List<String>.unmodifiable(tags),
        createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc(),
        updatedAt = (updatedAt ?? EthiopiaClock.nowUtc()).toUtc();

  static String normalizeCategory(String raw) {
    final trimmed = raw.trim().toLowerCase();
    return trimmed.isEmpty ? 'general' : trimmed;
  }

  static (String?, String?) normalizeLinkPair(
    String? rawModule,
    String? rawId,
  ) {
    final mod = rawModule?.trim().toLowerCase();
    final id = rawId?.trim();
    if (mod == null ||
        mod.isEmpty ||
        !allowedLinkedModules.contains(mod) ||
        id == null ||
        id.isEmpty) {
      return (null, null);
    }
    return (mod, id);
  }

  static String clampTitle(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Untitled Note';
    if (trimmed.length <= maxTitleLength) return trimmed;
    return trimmed.substring(0, maxTitleLength);
  }

  bool get isLinkedToTask =>
      linkedModule == taskLinkModule &&
      linkedId != null &&
      linkedId!.isNotEmpty;

  String? get linkedTaskId => isLinkedToTask ? linkedId : null;

  String get displayTitle => title.trim().isEmpty ? 'Untitled Note' : title;

  bool matchesQuery(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    final tagsStr = tags.join(' ').toLowerCase();
    return title.toLowerCase().contains(query) ||
        content.toLowerCase().contains(query) ||
        category.toLowerCase().contains(query) ||
        tagsStr.contains(query);
  }

  NoteEntity copyWith({
    String? title,
    String? content,
    String? category,
    String? projectId,
    String? goalId,
    String? linkedModule,
    String? linkedId,
    bool clearProjectId = false,
    bool clearGoalId = false,
    bool clearLink = false,
    List<String>? tags,
    bool? isPinned,
    bool? isFavorite,
    bool? isArchived,
    bool? isTrashed,
    DateTime? updatedAt,
  }) {
    final nextModule = clearLink ? null : (linkedModule ?? this.linkedModule);
    final nextId = clearLink ? null : (linkedId ?? this.linkedId);
    return NoteEntity(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      projectId: clearProjectId ? null : (projectId ?? this.projectId),
      goalId: clearGoalId ? null : (goalId ?? this.goalId),
      linkedModule: nextModule,
      linkedId: nextId,
      tags: tags ?? this.tags,
      isPinned: isPinned ?? this.isPinned,
      isFavorite: isFavorite ?? this.isFavorite,
      isArchived: isArchived ?? this.isArchived,
      isTrashed: isTrashed ?? this.isTrashed,
      createdAt: createdAt,
      updatedAt: updatedAt ?? EthiopiaClock.nowUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'category': category,
        'projectId': projectId,
        'goalId': goalId,
        'linkedModule': linkedModule,
        'linkedId': linkedId,
        'tags': tags,
        'isPinned': isPinned,
        'isFavorite': isFavorite,
        'isArchived': isArchived,
        'isTrashed': isTrashed,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
        'updatedAt': EthiopiaClock.toUtcIsoString(updatedAt),
      };

  factory NoteEntity.fromJson(Map<String, dynamic> json) {
    final rawLinkedModule = json['linkedModule']?.toString();
    final rawLinkedId = json['linkedId']?.toString();
    final legacyTaskId = json['taskId']?.toString();
    final normalizedPair = (rawLinkedModule != null || rawLinkedId != null)
        ? normalizeLinkPair(rawLinkedModule, rawLinkedId)
        : normalizeLinkPair(
            legacyTaskId != null && legacyTaskId.trim().isNotEmpty
                ? taskLinkModule
                : null,
            legacyTaskId,
          );

    return NoteEntity(
      id: json['id'],
      title: json['title'] ?? '',
      content: json['content'] ?? json['body'] ?? '',
      category: json['category'] ?? json['folder'] ?? 'general',
      projectId: json['projectId'],
      goalId: json['goalId'],
      linkedModule: normalizedPair.$1,
      linkedId: normalizedPair.$2,
      tags: json['tags'] is List
          ? (json['tags'] as List).map((e) => e.toString()).toList()
          : const [],
      isPinned: json['isPinned'] ?? false,
      isFavorite: json['isFavorite'] ?? false,
      isArchived: json['isArchived'] ?? false,
      isTrashed: json['isTrashed'] ?? false,
      createdAt:
          EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString()),
      updatedAt:
          EthiopiaClock.tryParseInstantUtc(json['updatedAt']?.toString()),
    );
  }
}
