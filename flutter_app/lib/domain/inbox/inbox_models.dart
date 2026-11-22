import '../../core/date/shared_date.dart';

/// Pure domain model for Daywell 1-tap Quick Capture Inbox items.
///
/// Invariants:
/// - Zero dependencies on Flutter widgets or Drift SQLite implementation.
/// - Immutable value objects with copyWith and JSON serialization.

class InboxItemEntity {
  static const List<String> allowedCategories = [
    'task',
    'idea',
    'expense',
    'note',
    'problem',
    'decision',
    'general',
  ];

  final String id;
  final String rawText;
  final String category; // 'task', 'idea', 'expense', 'note', 'general'
  final bool isProcessed;
  final DateTime createdAt;

  InboxItemEntity({
    required this.id,
    required this.rawText,
    String category = 'general',
    this.isProcessed = false,
    DateTime? createdAt,
  })  : category = normalizeCategory(category),
        createdAt = (createdAt ?? EthiopiaClock.nowUtc()).toUtc();

  static String normalizeCategory(String raw) {
    final trimmed = raw.trim().toLowerCase();
    return allowedCategories.contains(trimmed) ? trimmed : 'general';
  }

  InboxItemEntity copyWith({
    String? rawText,
    String? category,
    bool? isProcessed,
  }) {
    return InboxItemEntity(
      id: id,
      rawText: rawText ?? this.rawText,
      category: category ?? this.category,
      isProcessed: isProcessed ?? this.isProcessed,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'rawText': rawText,
        'category': category,
        'isProcessed': isProcessed,
        'createdAt': EthiopiaClock.toUtcIsoString(createdAt),
      };

  factory InboxItemEntity.fromJson(Map<String, dynamic> json) =>
      InboxItemEntity(
        id: json['id'],
        rawText: json['rawText'] ?? '',
        category: json['category'] ?? 'general',
        isProcessed: json['isProcessed'] ?? false,
        createdAt:
            EthiopiaClock.tryParseInstantUtc(json['createdAt']?.toString()),
      );

  /// Prepares an editable Task draft preserving all captured content:
  /// - Single-line <= 120 chars: full text becomes [title], empty [description].
  /// - Multi-line: first non-empty line (up to 120 chars) becomes [title],
  ///   remaining lines (plus full first line if truncated) stay in [description].
  /// - Single-line > 120 chars: truncated [title] + full [rawText] in [description].
  InboxTaskDraft toTaskDraft() {
    final normalized = rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    final initialLabels = category == 'idea' ? const ['idea'] : const <String>[];
    if (normalized.isEmpty) {
      return InboxTaskDraft(
        sourceInboxId: id,
        sourceCategory: category,
        title: '',
        description: '',
        initialLabels: initialLabels,
      );
    }

    final lines = normalized.split('\n');
    if (lines.length == 1) {
      final line = lines.first.trim();
      if (line.length <= 120) {
        return InboxTaskDraft(
          sourceInboxId: id,
          sourceCategory: category,
          title: line,
          description: '',
          initialLabels: initialLabels,
        );
      }
      return InboxTaskDraft(
        sourceInboxId: id,
        sourceCategory: category,
        title: '${line.substring(0, 117).trimRight()}...',
        description: line,
        initialLabels: initialLabels,
      );
    }

    final firstNonEmptyIdx = lines.indexWhere((l) => l.trim().isNotEmpty);
    final pivotIdx = firstNonEmptyIdx >= 0 ? firstNonEmptyIdx : 0;
    final firstLine = lines[pivotIdx].trim();
    final trailingLines = lines.sublist(pivotIdx + 1).join('\n').trim();

    if (firstLine.length <= 120) {
      return InboxTaskDraft(
        sourceInboxId: id,
        sourceCategory: category,
        title: firstLine,
        description: trailingLines,
        initialLabels: initialLabels,
      );
    }

    return InboxTaskDraft(
      sourceInboxId: id,
      sourceCategory: category,
      title: '${firstLine.substring(0, 117).trimRight()}...',
      description:
          trailingLines.isNotEmpty ? '$firstLine\n$trailingLines' : firstLine,
      initialLabels: initialLabels,
    );
  }
}

class InboxTaskDraft {
  final String sourceInboxId;
  final String sourceCategory;
  final String title;
  final String description;
  final List<String> initialLabels;

  const InboxTaskDraft({
    required this.sourceInboxId,
    required this.sourceCategory,
    required this.title,
    required this.description,
    this.initialLabels = const [],
  });
}
