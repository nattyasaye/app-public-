import 'inbox_models.dart';

/// Domain contract for Quick Capture Inbox persistence and operations.
abstract class IInboxRepository {
  Future<List<InboxItemEntity>> getAllInboxItems(
      {bool includeProcessed = false});
  Stream<List<InboxItemEntity>> watchUnprocessedItems();
  Future<InboxItemEntity> captureQuickThought(String rawText,
      {String category = 'general'});
  Future<void> markProcessed(String id);
  Future<void> deleteItem(String id);
  Future<void> updateItemText(String id, String newText, {String? category});
}
