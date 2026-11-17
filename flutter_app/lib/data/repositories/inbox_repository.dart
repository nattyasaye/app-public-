import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../core/date/shared_date.dart';
import '../database/app_database.dart';
import '../../domain/inbox/inbox_models.dart';
import '../../domain/inbox/inbox_contracts.dart';

export '../../domain/inbox/inbox_models.dart';
export '../../domain/inbox/inbox_contracts.dart';

/// Drift SQLite implementation of [IInboxRepository].
///
/// Encapsulates fast capture (<3s), raw ingress records, and triage lifecycle
/// over SQLite.
class DriftInboxRepository implements IInboxRepository {
  final AppDatabase _db;
  final Uuid _uuid = const Uuid();

  DriftInboxRepository(this._db);

  InboxItemEntity _mapRowToEntity(InboxItem r) {
    return InboxItemEntity(
      id: r.id,
      rawText: r.rawText,
      category: r.category,
      isProcessed: r.isProcessed,
      createdAt: r.createdAt,
    );
  }

  @override
  Future<List<InboxItemEntity>> getAllInboxItems(
      {bool includeProcessed = false}) async {
    final query = _db.select(_db.inboxItems);
    if (!includeProcessed) {
      query.where((tbl) => tbl.isProcessed.equals(false));
    }
    query.orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);
    final rows = await query.get();
    return rows.map(_mapRowToEntity).toList();
  }

  @override
  Stream<List<InboxItemEntity>> watchUnprocessedItems() {
    return (_db.select(_db.inboxItems)
          ..where((tbl) => tbl.isProcessed.equals(false))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .watch()
        .map((rows) => rows.map(_mapRowToEntity).toList());
  }

  @override
  Future<InboxItemEntity> captureQuickThought(String rawText,
      {String category = 'general'}) async {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Captured thought cannot be empty.');
    }

    final id = _uuid.v4();
    final now = EthiopiaClock.nowUtc();
    final normalizedCategory = InboxItemEntity.normalizeCategory(category);

    await _db.into(_db.inboxItems).insert(
          InboxItemsCompanion.insert(
            id: id,
            rawText: trimmed,
            category: Value(normalizedCategory),
            isProcessed: const Value(false),
            createdAt: now,
          ),
        );

    return InboxItemEntity(
      id: id,
      rawText: trimmed,
      category: normalizedCategory,
      isProcessed: false,
      createdAt: now,
    );
  }

  @override
  Future<void> markProcessed(String id) async {
    await (_db.update(_db.inboxItems)..where((tbl) => tbl.id.equals(id))).write(
      const InboxItemsCompanion(isProcessed: Value(true)),
    );
  }

  @override
  Future<void> deleteItem(String id) async {
    await (_db.delete(_db.inboxItems)..where((tbl) => tbl.id.equals(id))).go();
  }

  @override
  Future<void> updateItemText(String id, String newText,
      {String? category}) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Inbox item text cannot be empty.');
    }

    await (_db.update(_db.inboxItems)..where((tbl) => tbl.id.equals(id))).write(
      InboxItemsCompanion(
        rawText: Value(trimmed),
        category: category != null
            ? Value(InboxItemEntity.normalizeCategory(category))
            : const Value.absent(),
      ),
    );
  }
}
