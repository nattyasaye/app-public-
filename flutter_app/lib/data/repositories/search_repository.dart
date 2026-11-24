import 'dart:convert';
import 'package:drift/drift.dart';
import '../database/app_database.dart';

/// Unified search result item across all entities
class SearchResultItem {
  final String id;
  final String title;
  final String? snippet;
  final String
      entityType; // 'inbox'|'task'|'note'|'commitment'|'event'|'account'|'ledger'|'debt'
  final DateTime timestampUtc;

  const SearchResultItem({
    required this.id,
    required this.title,
    this.snippet,
    required this.entityType,
    required this.timestampUtc,
  });
}

/// Abstract contract for offline local search
abstract class ISearchRepository {
  Future<List<SearchResultItem>> searchAll(
    String query, {
    String? entityFilter,
  });
}

/// Drift SQLite implementation of offline local search
class DriftSearchRepository implements ISearchRepository {
  final AppDatabase _db;

  DriftSearchRepository(this._db);

  static List<String> _decodeNoteTags(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((e) => e.toString()).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<SearchResultItem>> searchAll(
    String query, {
    String? entityFilter,
  }) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    final results = <SearchResultItem>[];

    // 1. Search Inbox Items
    if (entityFilter == null || entityFilter == 'inbox') {
      final inboxMatches = await (_db.select(_db.inboxItems)
            ..where((tbl) => tbl.rawText.lower().like('%$cleanQuery%')))
          .get();
      for (final item in inboxMatches) {
        final statusLabel = item.isProcessed ? 'Processed' : 'Unprocessed';
        results.add(
          SearchResultItem(
            id: item.id,
            title: item.rawText,
            snippet: 'Category: ${item.category} • $statusLabel',
            entityType: 'inbox',
            timestampUtc: item.createdAt,
          ),
        );
      }
    }

    // 2. Search Tasks
    if (entityFilter == null || entityFilter == 'task') {
      final taskMatches = await (_db.select(_db.tasks)
            ..where(
              (tbl) =>
                  tbl.title.lower().like('%$cleanQuery%') |
                  (tbl.description.isNotNull() &
                      tbl.description.lower().like('%$cleanQuery%')) |
                  tbl.labelsJson.lower().like('%$cleanQuery%'),
            ))
          .get();
      for (final task in taskMatches) {
        results.add(SearchResultItem(
          id: task.id,
          title: task.title,
          snippet: 'Priority: ${task.priority} • Status: ${task.status}',
          entityType: 'task',
          timestampUtc: task.updatedAt,
        ));
      }
    }

    // 3. Search Notes (excluding soft-trashed notes, literal wildcard-safe match)
    if (entityFilter == null || entityFilter == 'note') {
      final nonTrashedNotes = await (_db.select(_db.notes)
            ..where((tbl) => tbl.isTrashed.equals(false)))
          .get();
      for (final note in nonTrashedNotes) {
        final tags = _decodeNoteTags(note.tagsJson);
        final matches = note.title.toLowerCase().contains(cleanQuery) ||
            note.content.toLowerCase().contains(cleanQuery) ||
            note.category.toLowerCase().contains(cleanQuery) ||
            tags.any((t) => t.toLowerCase().contains(cleanQuery));
        if (!matches) continue;
        final snippet = note.content.length > 80
            ? '${note.content.substring(0, 80)}...'
            : note.content;
        results.add(
          SearchResultItem(
            id: note.id,
            title: note.title,
            snippet: snippet,
            entityType: 'note',
            timestampUtc: note.updatedAt,
          ),
        );
      }
    }

    // 4. Search Commitments
    if (entityFilter == null || entityFilter == 'commitment') {
      final commitMatches = await (_db.select(_db.financialCommitments)
            ..where((tbl) => tbl.title.lower().like('%$cleanQuery%')))
          .get();
      for (final c in commitMatches) {
        results.add(
          SearchResultItem(
            id: c.id,
            title: c.title,
            snippet:
                '${(c.amountCents / 100).toStringAsFixed(2)} ETB • ${c.isPaid ? "Paid" : "Due ${c.dueDate}"}',
            entityType: 'commitment',
            timestampUtc: c.createdAt,
          ),
        );
      }
    }

    // 5. Search Finance Accounts (excluding system control accounts)
    if (entityFilter == null || entityFilter == 'account') {
      final accountMatches = await (_db.select(_db.accountsTable)
            ..where((tbl) =>
                tbl.isSystem.equals(false) &
                (tbl.name.lower().like('%$cleanQuery%') |
                    tbl.subType.lower().like('%$cleanQuery%'))))
          .get();
      for (final acc in accountMatches) {
        results.add(
          SearchResultItem(
            id: acc.id,
            title: acc.name,
            snippet:
                'Account • ${acc.subType} • ${acc.currencyCode}${acc.isArchived ? " (Archived)" : ""}',
            entityType: 'account',
            timestampUtc: acc.createdAt,
          ),
        );
      }
    }

    // 6. Search Double-Entry Journal Entries (excluding voided entries)
    if (entityFilter == null || entityFilter == 'ledger') {
      final entryMatches = await (_db.select(_db.journalEntriesTable)
            ..where((tbl) =>
                tbl.isVoided.equals(false) &
                tbl.description.lower().like('%$cleanQuery%')))
          .get();
      for (final entry in entryMatches) {
        results.add(
          SearchResultItem(
            id: entry.id,
            title: entry.description,
            snippet: 'Ledger (${entry.entryType}) • ${entry.occurrenceDate}',
            entityType: 'ledger',
            timestampUtc: entry.createdAt,
          ),
        );
      }
    }

    // 7. Search Debts & Counterparties
    if (entityFilter == null || entityFilter == 'debt') {
      final parties = await _db.select(_db.partiesTable).get();
      final partyById = {for (final p in parties) p.id: p};
      final debts = await _db.select(_db.debtsTable).get();
      for (final d in debts) {
        final partyName = partyById[d.partyId]?.name ?? 'Unknown Party';
        if (partyName.toLowerCase().contains(cleanQuery) ||
            d.debtType.toLowerCase().contains(cleanQuery) ||
            d.status.toLowerCase().contains(cleanQuery)) {
          results.add(
            SearchResultItem(
              id: d.id,
              title: '$partyName (${d.debtType})',
              snippet:
                  'Outstanding: ${(d.outstandingCents / 100).toStringAsFixed(2)} ETB • ${d.status}',
              entityType: 'debt',
              timestampUtc: d.createdAt,
            ),
          );
        }
      }
    }

    // 8. Search Calendar Events
    if (entityFilter == null || entityFilter == 'event') {
      final eventMatches = await (_db.select(_db.calendarEvents)
            ..where(
              (tbl) =>
                  tbl.title.lower().like('%$cleanQuery%') |
                  (tbl.notes.isNotNull() &
                      tbl.notes.lower().like('%$cleanQuery%')),
            ))
          .get();
      for (final evt in eventMatches) {
        results.add(SearchResultItem(
          id: evt.id,
          title: evt.title,
          snippet: '${evt.dateIso} • ${evt.category}',
          entityType: 'event',
          timestampUtc: evt.updatedAt,
        ));
      }
    }

    results.sort((a, b) => b.timestampUtc.compareTo(a.timestampUtc));
    return results;
  }
}
