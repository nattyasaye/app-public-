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
}
