import 'dart:math';

import 'package:drift/drift.dart';

import '../../core/date/shared_date.dart';
import '../../domain/finance/double_entry_engine.dart';
import 'app_database.dart';

/// Atomic, idempotent Schema v5 -> v6 double-entry ledger migrator.
///
/// Guarantees:
/// - Provisions system control accounts (`acc-sys-*`) outside user accounts.
/// - Infers canonical [AccountSubType] values without touching user balances.
/// - Converts legacy `FinancialTransactions` (including null-account and
///   superseded rows) into balanced double-entry [JournalEntriesTable] +
///   [PostingsTable] rows using `legacySourceTxId` for strict 1:1 idempotency.
/// - Deduplicates legacy paired transfers (`tx-*` + `entry-xfer-*`).
/// - Reconciles [DebtsTable.outstandingCents] and status from non-voided
///   settlements.
/// - Retains legacy `FinancialTransactions` read-only for traceability.
class V6LedgerMigrator {
  static const String v6MigratedSentinelKey = 'ledger_v6_migrated_at';

  /// Provisions the 6 system control accounts idempotently (`insertOrIgnore`).
  static Future<void> ensureSystemControlAccounts(AppDatabase db) async {
    final now = EthiopiaClock.nowUtc();
    const specs = <({
      String id,
      String name,
      String type,
      String subType,
    })>[
      (
        id: SystemControlAccounts.equity,
        name: 'Opening & Retained Equity',
        type: 'equity',
        subType: 'opening_equity',
      ),
      (
        id: SystemControlAccounts.income,
        name: 'Income Control',
        type: 'income',
        subType: 'nominal_income',
      ),
      (
        id: SystemControlAccounts.expense,
        name: 'Expense Control',
        type: 'expense',
        subType: 'nominal_expense',
      ),
      (
        id: SystemControlAccounts.receivable,
        name: 'Accounts Receivable Control',
        type: 'asset',
        subType: 'receivable',
      ),
      (
        id: SystemControlAccounts.payable,
        name: 'Accounts Payable Control',
        type: 'liability',
        subType: 'payable',
      ),
      (
        id: SystemControlAccounts.legacyOffset,
        name: 'Legacy Clearing Offset',
        type: 'equity',
        subType: 'legacy_clearing',
      ),
    ];

    for (final spec in specs) {
      await db.into(db.accountsTable).insert(
            AccountsTableCompanion.insert(
              id: spec.id,
              name: spec.name,
              type: spec.type,
              subType: Value(spec.subType),
              isSystem: const Value(true),
              currencyCode: const Value('ETB'),
              openingBalanceCents: const Value(0),
              isArchived: const Value(false),
              createdAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      // Ensure existing row with control ID stays marked isSystem = true.
      await db.customStatement(
        'UPDATE accounts_table '
        'SET is_system = 1, sub_type = ? '
        'WHERE id = ?;',
        [spec.subType, spec.id],
      );
    }
  }

  /// Ensures internal fee/interest categories exist when referenced by UI/migration.
  static Future<void> ensureSystemCategory(
    AppDatabase db, {
    required String categoryId,
    required String name,
    required String type,
    String colorHex = '#64748B',
  }) async {
    await db.into(db.financialCategories).insert(
          FinancialCategoriesCompanion.insert(
            id: categoryId,
            name: name,
            type: type,
            colorHex: Value(colorHex),
            isDefault: const Value(true),
            isArchived: const Value(false),
            sortOrder: const Value(99),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Infers a v6 [AccountSubType] for an existing legacy account row.
  static ({String subType, bool isSystem}) inferAccountClassification({
    required String id,
    required String name,
    required String type,
    String? currentSubType,
    bool currentIsSystem = false,
  }) {
    if (SystemControlAccounts.isSystemControlId(id)) {
      switch (id) {
        case SystemControlAccounts.equity:
          return (subType: 'opening_equity', isSystem: true);
        case SystemControlAccounts.income:
          return (subType: 'nominal_income', isSystem: true);
        case SystemControlAccounts.expense:
          return (subType: 'nominal_expense', isSystem: true);
        case SystemControlAccounts.receivable:
          return (subType: 'receivable', isSystem: true);
        case SystemControlAccounts.payable:
          return (subType: 'payable', isSystem: true);
        case SystemControlAccounts.legacyOffset:
          return (subType: 'legacy_clearing', isSystem: true);
      }
    }

    if (id == 'acc-rec') {
      return (subType: 'receivable', isSystem: true);
    }
    if (id == 'acc-pay') {
      return (subType: 'payable', isSystem: true);
    }

    if (type == 'liability') {
      final explicit = currentSubType;
      if (explicit != null &&
          explicit.isNotEmpty &&
          explicit != 'cash' &&
          AccountSubType.values.any((e) => e.dbValue == explicit)) {
        return (subType: explicit, isSystem: currentIsSystem);
      }
      return (subType: 'credit_card', isSystem: currentIsSystem);
    }
    if (type == 'equity') {
      return (subType: 'opening_equity', isSystem: true);
    }
    if (type == 'income') {
      return (subType: 'nominal_income', isSystem: true);
    }
    if (type == 'expense') {
      return (subType: 'nominal_expense', isSystem: true);
    }

    // Asset account: preserve explicit non-default subtype if already set.
    if (currentSubType != null &&
        currentSubType.isNotEmpty &&
        currentSubType != 'cash' &&
        AccountSubType.values.any((e) => e.dbValue == currentSubType)) {
      return (subType: currentSubType, isSystem: currentIsSystem);
    }

    final lowerName = name.toLowerCase();
    final lowerId = id.toLowerCase();
    if (lowerName.contains('vault') ||
        lowerName.contains('saving') ||
        lowerId.contains('vault')) {
      return (subType: 'savings_vault', isSystem: currentIsSystem);
    }
    if (lowerName.contains('telebirr') ||
        lowerName.contains('mpesa') ||
        lowerName.contains('m-pesa') ||
        lowerName.contains('cbe birr') ||
        lowerName.contains('chapa') ||
        lowerName.contains('mobile') ||
        lowerId.contains('telebirr')) {
      return (subType: 'mobile_money', isSystem: currentIsSystem);
    }
    if (lowerName.contains('bank') ||
        lowerName.contains('cbe') ||
        lowerName.contains('boa') ||
        lowerName.contains('dashen') ||
        lowerName.contains('abyssinia') ||
        lowerName.contains('awash') ||
        lowerName.contains('nib') ||
        lowerName.contains('wegagen') ||
        lowerId.contains('cbe') ||
        lowerId.contains('boa') ||
        lowerId.contains('dashen')) {
      return (subType: 'bank', isSystem: currentIsSystem);
    }
    return (subType: 'cash', isSystem: currentIsSystem);
  }

  /// Runs the complete idempotent v5 -> v6 data migration inside the caller's
  /// active SQLite transaction.
  static Future<void> migrateDataInTransaction(AppDatabase db) async {
    final now = EthiopiaClock.nowUtc();

    // 1. Provision system control accounts first.
    await ensureSystemControlAccounts(db);

    // 2. Normalize existing accounts (subType & isSystem).
    final accountRows = await db.select(db.accountsTable).get();
    final validAccountIds = <String>{};
    for (final acc in accountRows) {
      validAccountIds.add(acc.id);
      final classified = inferAccountClassification(
        id: acc.id,
        name: acc.name,
        type: acc.type,
        currentSubType: acc.subType,
        currentIsSystem: acc.isSystem,
      );
      if (classified.subType != acc.subType ||
          classified.isSystem != acc.isSystem) {
        await db.customStatement(
          'UPDATE accounts_table '
          'SET sub_type = ?, is_system = ? '
          'WHERE id = ?;',
          [classified.subType, classified.isSystem ? 1 : 0, acc.id],
        );
      }
    }

    // 3. Reconcile / create opening balance journal entries without duplication.
    final normalizedAccounts = await db.select(db.accountsTable).get();
    final existingEntries = await db.select(db.journalEntriesTable).get();
    final existingPostings = await db.select(db.postingsTable).get();

    final entriesById = {for (final e in existingEntries) e.id: e};
    final postingsByEntryId = <String, List<PostingsTableData>>{};
    for (final p in existingPostings) {
      postingsByEntryId.putIfAbsent(p.entryId, () => []).add(p);
    }
    final migratedSources = <String>{
      for (final e in existingEntries)
        if (e.legacySourceTxId != null) e.legacySourceTxId!,
    };

    for (final acc in normalizedAccounts) {
      if (acc.isSystem || acc.openingBalanceCents == 0) continue;

      final openSentinel = 'open:${acc.id}';
      if (migratedSources.contains(openSentinel)) continue;

      // Detect pre-v6 opening balance entries created by old FinanceController.
      String? matchedOpenEntryId;
      for (final entry in existingEntries) {
        if (entry.isVoided) continue;
        final isOpenEntry = entry.entryType == 'adjustment' &&
            (entry.description.startsWith('Opening Balance') ||
                entry.id.startsWith('entry-open-'));
        if (!isOpenEntry) continue;
        final entryPostings = postingsByEntryId[entry.id] ?? const [];
        final touchesAcc = entryPostings.any((p) => p.accountId == acc.id);
        if (touchesAcc) {
          matchedOpenEntryId = entry.id;
          break;
        }
      }

      if (matchedOpenEntryId != null) {
        await db.customStatement(
          'UPDATE journal_entries_table '
          'SET legacy_source_tx_id = ? '
          'WHERE id = ? AND legacy_source_tx_id IS NULL;',
          [openSentinel, matchedOpenEntryId],
        );
        migratedSources.add(openSentinel);
        continue;
      }

      final openDate = _resolveCanonicalDate(
        acc.openingBalanceDate,
        fallback: CalendarDate.fromUtcInstantInEthiopia(acc.createdAt),
      );
      final entryId = _uniqueEntryId('entry-open-v6-${acc.id}', entriesById);
      final bal = acc.openingBalanceCents;
      final absBal = bal.abs();
      final isDebitNormal = acc.type == 'asset' || acc.type == 'expense';
      final accountIncreasesByDebit =
          (isDebitNormal && bal > 0) || (!isDebitNormal && bal < 0);

      final accountDir = accountIncreasesByDebit ? 'debit' : 'credit';
      final equityDir = accountIncreasesByDebit ? 'credit' : 'debit';

      await db.into(db.journalEntriesTable).insert(
            JournalEntriesTableCompanion.insert(
              id: entryId,
              entryType: 'adjustment',
              description: 'Opening Balance for ${acc.name}',
              occurrenceDate: openDate,
              isVoided: const Value(false),
              legacySourceTxId: Value(openSentinel),
              createdAt: acc.createdAt,
            ),
          );
      await db.into(db.postingsTable).insert(
            PostingsTableCompanion.insert(
              id: '$entryId-acc',
              entryId: entryId,
              accountId: acc.id,
              amountCents: absBal,
              direction: accountDir,
              accountMovementDate: openDate,
              note: const Value('Migrated opening balance'),
            ),
          );
      await db.into(db.postingsTable).insert(
            PostingsTableCompanion.insert(
              id: '$entryId-eq',
              entryId: entryId,
              accountId: SystemControlAccounts.equity,
              amountCents: absBal,
              direction: equityDir,
              accountMovementDate: openDate,
              note: const Value('Opening balance equity offset'),
            ),
          );
      migratedSources.add(openSentinel);
      entriesById[entryId] = JournalEntriesTableData(
        id: entryId,
        entryType: 'adjustment',
        description: 'Opening Balance for ${acc.name}',
        occurrenceDate: openDate,
        isVoided: false,
        voidReason: null,
        legacySourceTxId: openSentinel,
        correctedFromEntryId: null,
        createdAt: acc.createdAt,
      );
    }

    // 4. Load valid categories and migrate FinancialTransactions idempotently.
    final categoryRows = await db.select(db.financialCategories).get();
    final validCategoryIds = {for (final c in categoryRows) c.id};

    final legacyTxs = await (db.select(db.financialTransactions)
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
        .get();

    // Index existing unlinked transfer entries for deduplication.
    final unlinkedTransferEntries = existingEntries
        .where((e) => e.entryType == 'transfer' && e.legacySourceTxId == null)
        .toList();

    for (final tx in legacyTxs) {
      if (migratedSources.contains(tx.id)) continue;
      if (tx.amountCents <= 0) continue;

      final txDate = _resolveCanonicalDate(
        tx.transactionDate,
        fallback: CalendarDate.fromUtcInstantInEthiopia(tx.createdAt),
      );
      final voidReason = tx.isSuperseded
          ? (tx.correctionReason?.trim().isNotEmpty == true
              ? tx.correctionReason!.trim()
              : 'Superseded legacy transaction ${tx.id}')
          : null;

      if (tx.type == 'transfer') {
        final matched = _findMatchingTransferEntry(
          tx: tx,
          txDate: txDate,
          candidates: unlinkedTransferEntries,
          postingsByEntryId: postingsByEntryId,
          migratedSources: migratedSources,
        );

        if (matched != null) {
          await db.customStatement(
            'UPDATE journal_entries_table '
            'SET legacy_source_tx_id = ?, '
            'is_voided = CASE WHEN ? = 1 THEN 1 ELSE is_voided END, '
            'void_reason = CASE WHEN ? = 1 AND void_reason IS NULL THEN ? ELSE void_reason END '
            'WHERE id = ?;',
            [
              tx.id,
              tx.isSuperseded ? 1 : 0,
              tx.isSuperseded ? 1 : 0,
              voidReason,
              matched.id,
            ],
          );
          migratedSources.add(tx.id);
          unlinkedTransferEntries.removeWhere((e) => e.id == matched.id);
          continue;
        }

        final fromAccountId = _resolveAccountId(tx.accountId, validAccountIds);
        final toAccountId =
            _resolveAccountId(tx.destinationAccountId, validAccountIds);
        final entryId = _uniqueEntryId('entry-mig-${tx.id}', entriesById);
        final desc = _buildLegacyDescription(tx, fallback: 'Account Transfer');

        await db.into(db.journalEntriesTable).insert(
              JournalEntriesTableCompanion.insert(
                id: entryId,
                entryType: 'transfer',
                description: desc,
                occurrenceDate: txDate,
                isVoided: Value(tx.isSuperseded),
                voidReason: Value(voidReason),
                legacySourceTxId: Value(tx.id),
                createdAt: tx.createdAt,
              ),
            );
        await db.into(db.postingsTable).insert(
              PostingsTableCompanion.insert(
                id: '$entryId-dr',
                entryId: entryId,
                accountId: toAccountId,
                amountCents: tx.amountCents,
                direction: 'debit',
                accountMovementDate: txDate,
                note: Value(tx.note),
              ),
            );
        await db.into(db.postingsTable).insert(
              PostingsTableCompanion.insert(
                id: '$entryId-cr',
                entryId: entryId,
                accountId: fromAccountId,
                amountCents: tx.amountCents,
                direction: 'credit',
                accountMovementDate: txDate,
                note: Value(tx.note),
              ),
            );
        migratedSources.add(tx.id);
        continue;
      }

      // Single-entry income or expense transaction.
      final isIncome = tx.type == 'income';
      final cashAccountId = _resolveAccountId(tx.accountId, validAccountIds);
      final controlAccountId = isIncome
          ? SystemControlAccounts.income
          : SystemControlAccounts.expense;
      final catId =
          validCategoryIds.contains(tx.categoryId) ? tx.categoryId : null;
      final entryId = _uniqueEntryId('entry-mig-${tx.id}', entriesById);
      final desc = _buildLegacyDescription(
        tx,
        fallback: isIncome ? 'Income' : 'Expense',
      );

      await db.into(db.journalEntriesTable).insert(
            JournalEntriesTableCompanion.insert(
              id: entryId,
              entryType: 'standard',
              description: desc,
              occurrenceDate: txDate,
              isVoided: Value(tx.isSuperseded),
              voidReason: Value(voidReason),
              legacySourceTxId: Value(tx.id),
              createdAt: tx.createdAt,
            ),
          );

      if (isIncome) {
        await db.into(db.postingsTable).insert(
              PostingsTableCompanion.insert(
                id: '$entryId-dr',
                entryId: entryId,
                accountId: cashAccountId,
                amountCents: tx.amountCents,
                direction: 'debit',
                accountMovementDate: txDate,
                note: Value(tx.note),
              ),
            );
        await db.into(db.postingsTable).insert(
              PostingsTableCompanion.insert(
                id: '$entryId-cr',
                entryId: entryId,
                accountId: controlAccountId,
                amountCents: tx.amountCents,
                direction: 'credit',
                accountMovementDate: txDate,
                categoryId: Value(catId),
                note: Value(tx.note),
              ),
            );
      } else {
        await db.into(db.postingsTable).insert(
              PostingsTableCompanion.insert(
                id: '$entryId-dr',
                entryId: entryId,
                accountId: controlAccountId,
                amountCents: tx.amountCents,
                direction: 'debit',
                accountMovementDate: txDate,
                categoryId: Value(catId),
                note: Value(tx.note),
              ),
            );
        await db.into(db.postingsTable).insert(
              PostingsTableCompanion.insert(
                id: '$entryId-cr',
                entryId: entryId,
                accountId: cashAccountId,
                amountCents: tx.amountCents,
                direction: 'credit',
                accountMovementDate: txDate,
                note: Value(tx.note),
              ),
            );
      }
      migratedSources.add(tx.id);
    }

    // 5. Reconcile DebtsTable outstanding balances from non-voided settlements.
    await reconcileAllDebts(db);

    // 6. Post-migration integrity verification inside transaction.
    await _verifyPostMigrationInvariants(db, legacyTxs);

    // 7. Record v6 migration sentinel.
    await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: v6MigratedSentinelKey,
            value: EthiopiaClock.toUtcIsoString(now),
            updatedAt: now,
          ),
        );
  }

  /// Recomputes [DebtsTable.outstandingCents] and [DebtsTable.status] from
  /// non-voided settlement allocations so void/unvoid or migration never drifts.
  static Future<void> reconcileAllDebts(AppDatabase db) async {
    final debts = await db.select(db.debtsTable).get();
    if (debts.isEmpty) return;

    final entries = await db.select(db.journalEntriesTable).get();
    final voidedEntryIds = {
      for (final e in entries)
        if (e.isVoided) e.id,
    };
    final allocations = await db.select(db.settlementAllocationsTable).get();

    for (final debt in debts) {
      final originVoided = voidedEntryIds.contains(debt.originEntryId);
      final isWrittenOff =
          debt.status == 'writtenOff' || debt.status == 'written_off';
      final actualPaid = (originVoided || isWrittenOff)
          ? 0
          : allocations
              .where(
                (a) =>
                    a.debtId == debt.id &&
                    !voidedEntryIds.contains(a.settlementEntryId),
              )
              .fold<int>(0, (sum, a) => sum + a.allocatedCents);

      final expectedOutstanding = (originVoided || isWrittenOff)
          ? 0
          : max(0, debt.principalCents - actualPaid);
      final String expectedStatus;
      if (originVoided) {
        expectedStatus = 'written_off';
      } else if (isWrittenOff) {
        expectedStatus = debt.status;
      } else {
        expectedStatus = expectedOutstanding == 0 ? 'settled' : 'active';
      }

      if (debt.outstandingCents != expectedOutstanding ||
          debt.status != expectedStatus) {
        await (db.update(db.debtsTable)..where((tbl) => tbl.id.equals(debt.id)))
            .write(
          DebtsTableCompanion(
            outstandingCents: Value(expectedOutstanding),
            status: Value(expectedStatus),
          ),
        );
      }
    }
  }

  static Future<void> _verifyPostMigrationInvariants(
    AppDatabase db,
    List<FinancialTransaction> legacyTxs,
  ) async {
    // A. Every journal entry must have >= 2 postings and Debits == Credits.
    final unbalanced = await db.customSelect('''
      SELECT j.id,
             COALESCE(SUM(CASE WHEN p.direction = 'debit' THEN p.amount_cents ELSE 0 END), 0) AS dr_sum,
             COALESCE(SUM(CASE WHEN p.direction = 'credit' THEN p.amount_cents ELSE 0 END), 0) AS cr_sum,
             COUNT(p.id) AS posting_count
      FROM journal_entries_table j
      LEFT JOIN postings_table p ON p.entry_id = j.id
      GROUP BY j.id
      HAVING dr_sum != cr_sum OR posting_count < 2
    ''').get();

    if (unbalanced.isNotEmpty) {
      final row = unbalanced.first;
      throw StateError(
        'Schema v5->v6 migration aborted: unbalanced journal entry '
        '${row.read<String>('id')} '
        '(dr=${row.read<int>('dr_sum')}, '
        'cr=${row.read<int>('cr_sum')}, '
        'count=${row.read<int>('posting_count')}).',
      );
    }

    // B. Every positive legacy transaction has 1:1 traceability in JournalEntries.
    final expectedLegacyIds = {
      for (final tx in legacyTxs)
        if (tx.amountCents > 0) tx.id,
    };
    if (expectedLegacyIds.isNotEmpty) {
      final migratedRows = await db
          .customSelect(
            'SELECT legacy_source_tx_id, is_voided FROM journal_entries_table '
            'WHERE legacy_source_tx_id IS NOT NULL;',
          )
          .get();
      final migratedMap = {
        for (final r in migratedRows)
          r.read<String>('legacy_source_tx_id'): r.read<int>('is_voided') == 1,
      };
      for (final tx in legacyTxs) {
        if (tx.amountCents <= 0) continue;
        if (!migratedMap.containsKey(tx.id)) {
          throw StateError(
            'Schema v5->v6 migration aborted: legacy transaction ${tx.id} '
            'missing from journal_entries_table.',
          );
        }
        if (tx.isSuperseded && migratedMap[tx.id] != true) {
          throw StateError(
            'Schema v5->v6 migration aborted: superseded transaction ${tx.id} '
            'was not marked is_voided=1.',
          );
        }
      }
    }

    // C. Strict foreign key verification.
    final fkViolations =
        await db.customSelect('PRAGMA foreign_key_check').get();
    if (fkViolations.isNotEmpty) {
      throw StateError(
        'Schema v5->v6 migration aborted due to foreign key violations '
        '(${fkViolations.length} row(s)).',
      );
    }
  }

  static JournalEntriesTableData? _findMatchingTransferEntry({
    required FinancialTransaction tx,
    required String txDate,
    required List<JournalEntriesTableData> candidates,
    required Map<String, List<PostingsTableData>> postingsByEntryId,
    required Set<String> migratedSources,
  }) {
    final suffix = tx.id.startsWith('tx-') ? tx.id.substring(3) : tx.id;
    final directIds = <String>{
      'entry-xfer-$suffix',
      'entry-xfer-${tx.id}',
      'entry-${tx.id}',
    };

    for (final c in candidates) {
      if (migratedSources.contains(tx.id)) continue;
      if (directIds.contains(c.id)) {
        return c;
      }
    }

    for (final c in candidates) {
      if (c.occurrenceDate != txDate) continue;
      final postings = postingsByEntryId[c.id] ?? const [];
      final hasDr = postings.any(
        (p) =>
            p.direction == 'debit' &&
            p.amountCents == tx.amountCents &&
            (tx.destinationAccountId == null ||
                p.accountId == tx.destinationAccountId),
      );
      final hasCr = postings.any(
        (p) =>
            p.direction == 'credit' &&
            p.amountCents >= tx.amountCents &&
            (tx.accountId == null || p.accountId == tx.accountId),
      );
      if (hasDr && hasCr) {
        return c;
      }
    }
    return null;
  }

  static String _resolveAccountId(
    String? accountId,
    Set<String> validAccountIds,
  ) {
    if (accountId != null && validAccountIds.contains(accountId)) {
      return accountId;
    }
    return SystemControlAccounts.legacyOffset;
  }

  static String _resolveCanonicalDate(
    String? raw, {
    required CalendarDate fallback,
  }) {
    if (raw != null && raw.trim().isNotEmpty) {
      final parsed = SharedDateFormatter.tryParseFlexibleToCalendarDate(raw);
      if (parsed != null) return parsed.toIsoString();
    }
    return fallback.toIsoString();
  }

  static String _buildLegacyDescription(
    FinancialTransaction tx, {
    required String fallback,
  }) {
    final payee = tx.payee?.trim();
    final note = tx.note?.trim();
    if (payee != null && payee.isNotEmpty && note != null && note.isNotEmpty) {
      return '$payee — $note';
    }
    if (note != null && note.isNotEmpty) return note;
    if (payee != null && payee.isNotEmpty) return payee;
    return fallback;
  }

  static String _uniqueEntryId(
    String preferred,
    Map<String, JournalEntriesTableData> existing,
  ) {
    if (!existing.containsKey(preferred)) return preferred;
    var index = 1;
    while (existing.containsKey('$preferred-$index')) {
      index++;
    }
    return '$preferred-$index';
  }
}
