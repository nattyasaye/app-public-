import '../../domain/inbox/inbox_models.dart';

/// Immutable state container for the Daywell Quick Capture Inbox module.
class InboxModuleState {
  final List<InboxItemEntity> items;
  final String
      categoryFilter; // 'all', 'task', 'expense', 'note', 'idea', 'general'
  final bool showProcessed;
  final bool isLoading;
  final String? errorMessage;

  const InboxModuleState({
    this.items = const [],
    this.categoryFilter = 'all',
    this.showProcessed = false,
    this.isLoading = false,
    this.errorMessage,
  });

  InboxModuleState copyWith({
    List<InboxItemEntity>? items,
    String? categoryFilter,
    bool? showProcessed,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return InboxModuleState(
      items: items ?? this.items,
      categoryFilter: categoryFilter ?? this.categoryFilter,
      showProcessed: showProcessed ?? this.showProcessed,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  InboxItemEntity? findById(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  // --- Derived Calculations ---

  List<InboxItemEntity> get unprocessedItems =>
      items.where((i) => !i.isProcessed).toList();

  int get unprocessedCount => unprocessedItems.length;

  int get processedCount => items.where((i) => i.isProcessed).length;

  List<InboxItemEntity> get filteredItems {
    final list = items.where((item) {
      if (!showProcessed && item.isProcessed) return false;
      if (categoryFilter != 'all' && item.category != categoryFilter) {
        return false;
      }
      return true;
    }).toList();

    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }
}
