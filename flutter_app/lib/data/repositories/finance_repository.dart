import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/date/shared_date.dart';
import '../../core/interfaces/platform_service_interfaces.dart';
import '../../domain/finance/finance_contracts.dart';
import '../../domain/finance/recurring_engine.dart';
import '../database/app_database.dart';
import '../database/database_persistence_coordinator.dart';
import '../database/v6_ledger_migrator.dart';
import '../database/v7_ledger_hardener.dart';

export '../../domain/finance/finance_contracts.dart';

/// Drift SQLite implementation of [IFinanceRepository].
///
/// Authoritative persistence unit for double-entry ledger entries, accounts,
/// categories, commitments, savings goals, debts, budgets, and recurring rules.
class DriftFinanceRepository implements IFinanceRepository {
  final AppDatabase _db;
  final Uuid _uuid = const Uuid();

  DriftFinanceRepository(this._db);

  // ==========================================================================
  // Settings & Setup Persistence
  // ==========================================================================

  @override
  Future<({bool isSetupCompleted, int openingBalanceCents})>
      getFinanceSettings() async {
    final setupRow = await (_db.select(_db.appSettings)
          ..where((tbl) => tbl.key.equals(AppDatabase.financeSetupKey)))
        .getSingleOrNull();
    final openRow = await (_db.select(_db.appSettings)
          ..where((tbl) => tbl.key.equals(AppDatabase.openingBalanceKey)))
        .getSingleOrNull();
    final existingAccounts = await (_db.select(_db.accountsTable)
          ..where((tbl) => tbl.isSystem.equals(false))
          ..limit(1))
        .get();

    final isSetupCompleted = setupRow != null
        ? setupRow.value == 'true'
        : existingAccounts.isNotEmpty;
    final openingBalanceCents = int.tryParse(openRow?.value ?? '') ?? 0;

    return (
      isSetupCompleted: isSetupCompleted,
      openingBalanceCents: openingBalanceCents,
    );
  }

  @override
  Future<void> completeFinanceSetup(List<AccountModel> setupAccounts) async {
    final now = EthiopiaClock.nowUtc();
    await _db.transaction(() async {
      await V6LedgerMigrator.ensureSystemControlAccounts(_db);

      for (final acc in setupAccounts) {
        final isProtectedSystem =
            SystemControlAccounts.isSystemControlId(acc.id) || acc.isSystem;
        if (!isProtectedSystem && !DoubleEntryEngine.isEtb(acc.currencyCode)) {
          throw DoubleEntryValidationError(
            'First-release reporting supports ETB accounts only; account '
            '"${acc.name}" (${acc.currencyCode}) cannot be created.',
          );
        }
        final normalizedCurrency = isProtectedSystem ? acc.currencyCode : 'ETB';
        final normalizedAcc = isProtectedSystem
            ? acc
            : acc.copyWith(currencyCode: normalizedCurrency);

        await _db.into(_db.accountsTable).insertOnConflictUpdate(
              AccountsTableCompanion.insert(
                id: normalizedAcc.id,
                name: normalizedAcc.name.trim(),
                type: normalizedAcc.type.name,
                subType: Value(normalizedAcc.subType.dbValue),
                isSystem: Value(normalizedAcc.isSystem),
                currencyCode: Value(normalizedCurrency),
                openingBalanceCents: Value(normalizedAcc.openingBalanceCents),
                openingBalanceDate: Value(normalizedAcc.openingBalanceDate),
                isArchived: Value(normalizedAcc.isArchived),
                createdAt: normalizedAcc.createdAt,
              ),
            );

        if (!isProtectedSystem && normalizedAcc.openingBalanceCents != 0) {
          await _syncOpeningBalanceEntryInTx(normalizedAcc);
        }
      }

      await _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: AppDatabase.financeSetupKey,
              value: 'true',
              updatedAt: now,
            ),
          );
    });
  }

  @override
  Future<void> setFinanceSetupCompleted(bool completed) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppDatabase.financeSetupKey,
            value: completed ? 'true' : 'false',
            updatedAt: EthiopiaClock.nowUtc(),
          ),
        );
  }

  @override
  Future<String> exportFinanceOnlyJson() async {
    final map =
        await DatabasePersistenceCoordinator(_db).exportFinanceOnlySnapshot();
    return jsonEncode(map);
  }

  @override
  Future<void> importFinanceOnlyJson(String rawJson) async {
    dynamic decoded;
    try {
      decoded = jsonDecode(rawJson);
    } catch (_) {
      throw const BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid Finance JSON payload.',
      );
    }
    if (decoded is! Map) {
      throw const BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Finance-only snapshot payload must be a JSON object.',
      );
    }
    final stateMap = decoded.map((k, v) => MapEntry(k.toString(), v));
    await DatabasePersistenceCoordinator(_db)
        .importFinanceOnlySnapshot(stateMap);
  }

  // ==========================================================================
  // IAccountRepositoryContract
  // ==========================================================================

  @override
  Future<List<AccountModel>> getAccounts({
    bool includeArchived = false,
    bool includeSystem = false,
  }) async {
    final query = _db.select(_db.accountsTable);
    if (!includeArchived) {
      query.where((tbl) => tbl.isArchived.equals(false));
    }
    if (!includeSystem) {
      query.where((tbl) => tbl.isSystem.equals(false));
    }
    query.orderBy([(tbl) => OrderingTerm.asc(tbl.name)]);
    final rows = await query.get();

    return rows.map(_mapAccountRow).toList();
  }

  @override
  Future<AccountModel?> getAccountById(String id) async {
    final query = _db.select(_db.accountsTable)
      ..where((tbl) => tbl.id.equals(id));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return _mapAccountRow(row);
  }

  @override
  Future<AccountModel> createAccount(AccountModel account) async {
    late AccountModel saved;
    await _db.transaction(() async {
      await V6LedgerMigrator.ensureSystemControlAccounts(_db);
      final isProtectedSystem =
          SystemControlAccounts.isSystemControlId(account.id) ||
              account.isSystem;
      if (!isProtectedSystem &&
          !DoubleEntryEngine.isEtb(account.currencyCode)) {
        throw DoubleEntryValidationError(
          'First-release reporting supports ETB accounts only; account '
          '"${account.name}" (${account.currencyCode}) cannot be created.',
        );
      }
      final normalizedCurrency =
          isProtectedSystem ? account.currencyCode : 'ETB';
      saved = isProtectedSystem
          ? account
          : account.copyWith(currencyCode: normalizedCurrency);

      await _db.into(_db.accountsTable).insertOnConflictUpdate(
            AccountsTableCompanion.insert(
              id: saved.id,
              name: saved.name.trim(),
              type: saved.type.name,
              subType: Value(saved.subType.dbValue),
              isSystem: Value(saved.isSystem),
              currencyCode: Value(normalizedCurrency),
              openingBalanceCents: Value(saved.openingBalanceCents),
              openingBalanceDate: Value(saved.openingBalanceDate),
              isArchived: Value(saved.isArchived),
              createdAt: saved.createdAt,
            ),
          );

      if (!isProtectedSystem && saved.openingBalanceCents != 0) {
        await _syncOpeningBalanceEntryInTx(saved);
      }
      await _syncVaultGoalsInTx();
    });
    return saved;
  }

  @override
  Future<AccountModel> updateAccount(AccountModel account) async {
    late AccountModel saved;
    await _db.transaction(() async {
      await V6LedgerMigrator.ensureSystemControlAccounts(_db);
      final existing = await (_db.select(_db.accountsTable)
            ..where((tbl) => tbl.id.equals(account.id)))
          .getSingleOrNull();
      final isProtectedSystem =
          SystemControlAccounts.isSystemControlId(account.id) ||
              account.isSystem ||
              (existing?.isSystem ?? false);

      if (!isProtectedSystem && existing != null) {
        final existingIsEtb = DoubleEntryEngine.isEtb(existing.currencyCode);
        final nextNormCurrency =
            DoubleEntryEngine.normalizeCurrencyCode(account.currencyCode);
        final prevNormCurrency =
            DoubleEntryEngine.normalizeCurrencyCode(existing.currencyCode);

        if (!existingIsEtb) {
          // Legacy non-ETB or unverified account: allow safe name/subType/archive
          // updates ONLY without altering currencyCode or opening balances/dates.
          if (nextNormCurrency != prevNormCurrency ||
              account.openingBalanceCents != existing.openingBalanceCents ||
              account.openingBalanceDate != existing.openingBalanceDate) {
            throw DoubleEntryValidationError(
              'First-release reporting supports ETB writes only; historical '
              'non-ETB or unverified account opening balances and currencies '
              'cannot be modified.',
            );
          }

          if (!existing.isArchived && account.isArchived) {
            await _assertVaultZeroBalanceBeforeArchiveInTx(existing);
          }

          await (_db.update(_db.accountsTable)
                ..where((tbl) => tbl.id.equals(account.id)))
              .write(
            AccountsTableCompanion(
              name: Value(account.name.trim()),
              subType: Value(account.subType.dbValue),
              isArchived: Value(account.isArchived),
            ),
          );
          saved = _mapAccountRow(existing).copyWith(
            name: account.name.trim(),
            subType: account.subType,
            isArchived: account.isArchived,
          );
          return;
        }

        if (!DoubleEntryEngine.isEtb(account.currencyCode)) {
          throw DoubleEntryValidationError(
            'Cannot change an ETB account currency to '
            '"${account.currencyCode}" in first-release ETB mode.',
          );
        }
        if (!existing.isArchived && account.isArchived) {
          await _assertVaultZeroBalanceBeforeArchiveInTx(existing);
        }
      } else if (!isProtectedSystem &&
          !DoubleEntryEngine.isEtb(account.currencyCode)) {
        throw DoubleEntryValidationError(
          'First-release reporting supports ETB accounts only.',
        );
      }

      final normalizedCurrency =
          isProtectedSystem ? account.currencyCode : 'ETB';
      saved = isProtectedSystem
          ? account
          : account.copyWith(currencyCode: normalizedCurrency);

      await (_db.update(_db.accountsTable)
            ..where((tbl) => tbl.id.equals(account.id)))
          .write(
        AccountsTableCompanion(
          name: Value(saved.name.trim()),
          type: Value(saved.type.name),
          subType: Value(saved.subType.dbValue),
          isSystem: Value(isProtectedSystem),
          currencyCode: Value(normalizedCurrency),
          openingBalanceCents: Value(saved.openingBalanceCents),
          openingBalanceDate: Value(saved.openingBalanceDate),
          isArchived: Value(saved.isArchived),
        ),
      );

      final openingChanged = existing == null ||
          saved.openingBalanceCents != existing.openingBalanceCents ||
          saved.openingBalanceDate != existing.openingBalanceDate;
      if (!isProtectedSystem && openingChanged) {
        await _syncOpeningBalanceEntryInTx(saved);
      }
      await _syncVaultGoalsInTx();
    });
    return saved;
  }

  @override
  Future<AccountModel> reviseOpeningBalance({
    required String accountId,
    required int newOpeningBalanceCents,
    required String reason,
    CalendarDate? effectiveDate,
  }) async {
    late AccountModel updated;
    await _db.transaction(() async {
      await V6LedgerMigrator.ensureSystemControlAccounts(_db);
      final row = await (_db.select(_db.accountsTable)
            ..where((tbl) => tbl.id.equals(accountId)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('Account not found: $accountId');
      }
      if (row.isSystem) {
        throw StateError('Cannot revise opening balance on system account.');
      }
      await _assertEtbAccountsInTx([accountId]);

      final mapped = _mapAccountRow(row);
      final nextDate =
          effectiveDate?.toIsoString() ?? mapped.openingBalanceDate;
      updated = mapped.copyWith(
        openingBalanceCents: newOpeningBalanceCents,
        openingBalanceDate: nextDate,
      );

      await (_db.update(_db.accountsTable)
            ..where((tbl) => tbl.id.equals(accountId)))
          .write(
        AccountsTableCompanion(
          openingBalanceCents: Value(newOpeningBalanceCents),
          openingBalanceDate: Value(nextDate),
        ),
      );

      await _syncOpeningBalanceEntryInTx(
        updated,
        reason:
            reason.trim().isEmpty ? 'Updated opening balance' : reason.trim(),
      );
      await _syncVaultGoalsInTx();
    });
    return updated;
  }

  @override
  Future<List<JournalEntryModel>> getOpeningBalanceHistory(
    String accountId,
  ) async {
    final openTag = 'open:$accountId';
    final openRevPrefix = '$openTag:rev:%';
    final rows = await (_db.select(_db.journalEntriesTable)
          ..where((tbl) =>
              tbl.legacySourceTxId.equals(openTag) |
              tbl.legacySourceTxId.like(openRevPrefix))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .get();
    return rows.map(_mapJournalEntryRow).toList();
  }

  @override
  Future<void> archiveAccount(String id) async {
    if (SystemControlAccounts.isSystemControlId(id)) return;
    await _db.transaction(() async {
      final row = await (_db.select(_db.accountsTable)
            ..where((tbl) => tbl.id.equals(id)))
          .getSingleOrNull();
      if (row == null || row.isSystem) return;

      await _assertVaultZeroBalanceBeforeArchiveInTx(row);

      await (_db.update(_db.accountsTable)..where((tbl) => tbl.id.equals(id)))
          .write(
        const AccountsTableCompanion(isArchived: Value(true)),
      );
    });
  }

  @override
  Future<void> unarchiveAccount(String id) async {
    await (_db.update(_db.accountsTable)..where((tbl) => tbl.id.equals(id)))
        .write(
      const AccountsTableCompanion(isArchived: Value(false)),
    );
  }

  @override
  Future<bool> deleteAccount(String id) async {
    if (SystemControlAccounts.isSystemControlId(id)) return false;
    final accRow = await (_db.select(_db.accountsTable)
          ..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
    if (accRow == null || accRow.isSystem) return false;

    final hasPostings = await (_db.select(_db.postingsTable)
          ..where((tbl) => tbl.accountId.equals(id))
          ..limit(1))
        .getSingleOrNull();

    final hasTx = await (_db.select(_db.financialTransactions)
          ..where((tbl) =>
              tbl.isSuperseded.equals(false) &
              (tbl.accountId.equals(id) | tbl.destinationAccountId.equals(id)))
          ..limit(1))
        .getSingleOrNull();

    final hasCommitments = await (_db.select(_db.financialCommitments)
          ..where((tbl) => tbl.linkedAccountId.equals(id))
          ..limit(1))
        .getSingleOrNull();

    final hasGoals = await (_db.select(_db.savingsGoals)
          ..where((tbl) => tbl.linkedAccountId.equals(id))
          ..limit(1))
        .getSingleOrNull();

    final hasRules = await (_db.select(_db.recurringRulesTable)
          ..where((tbl) =>
              tbl.accountId.equals(id) | tbl.destinationAccountId.equals(id))
          ..limit(1))
        .getSingleOrNull();

    if (hasPostings != null ||
        hasTx != null ||
        hasCommitments != null ||
        hasGoals != null ||
        hasRules != null) {
      return false;
    }

    final deletedCount = await (_db.delete(_db.accountsTable)
          ..where((tbl) => tbl.id.equals(id)))
        .go();
    return deletedCount > 0;
  }

  // ==========================================================================
  // ICategoryRepositoryContract
  // ==========================================================================

  @override
  Future<List<TransactionCategoryModel>> getCategories({
    bool includeArchived = false,
  }) async {
    final query = _db.select(_db.financialCategories);
    if (!includeArchived) {
      query.where((tbl) => tbl.isArchived.equals(false));
    }
    query.orderBy([
      (tbl) => OrderingTerm.asc(tbl.sortOrder),
      (tbl) => OrderingTerm.asc(tbl.name),
    ]);
    final rows = await query.get();
    return rows.map(_mapCategoryRow).toList();
  }

  @override
  Future<TransactionCategoryModel> createCategory({
    String? id,
    required String name,
    required String type,
    String colorHex = '#1B4D3E',
    String? parentId,
    int sortOrder = 0,
    bool isDefault = false,
  }) async {
    final categoryId = id ?? _uuid.v4();
    final cleanName = name.trim();
    await _db.into(_db.financialCategories).insertOnConflictUpdate(
          FinancialCategoriesCompanion.insert(
            id: categoryId,
            name: cleanName,
            type: type,
            colorHex: Value(colorHex),
            parentId: Value(parentId),
            sortOrder: Value(sortOrder),
            isDefault: Value(isDefault),
            isArchived: const Value(false),
          ),
        );
    return TransactionCategoryModel(
      id: categoryId,
      name: cleanName,
      type: type,
      colorHex: colorHex,
      parentId: parentId,
      sortOrder: sortOrder,
      isDefault: isDefault,
      isArchived: false,
    );
  }

  @override
  Future<void> updateCategory(
    String id, {
    String? name,
    String? colorHex,
    String? parentId,
    bool clearParentId = false,
    int? sortOrder,
  }) async {
    if (!clearParentId && parentId != null && parentId == id) {
      throw ArgumentError('A category cannot be its own parent.');
    }
    await (_db.update(_db.financialCategories)
          ..where((tbl) => tbl.id.equals(id)))
        .write(
      FinancialCategoriesCompanion(
        name: name != null ? Value(name.trim()) : const Value.absent(),
        colorHex: colorHex != null ? Value(colorHex) : const Value.absent(),
        parentId: clearParentId
            ? const Value(null)
            : (parentId != null ? Value(parentId) : const Value.absent()),
        sortOrder: sortOrder != null ? Value(sortOrder) : const Value.absent(),
      ),
    );
  }

  @override
  Future<void> toggleArchiveCategory(String id) async {
    final current = await (_db.select(_db.financialCategories)
          ..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
    if (current == null) return;
    await (_db.update(_db.financialCategories)
          ..where((tbl) => tbl.id.equals(id)))
        .write(
      FinancialCategoriesCompanion(isArchived: Value(!current.isArchived)),
    );
  }

  @override
  Future<void> archiveCategory(String id) async {
    await (_db.update(_db.financialCategories)
          ..where((tbl) => tbl.id.equals(id)))
        .write(
      const FinancialCategoriesCompanion(isArchived: Value(true)),
    );
  }

  @override
  Future<bool> deleteCategory(String id) async {
    final hasPostings = await (_db.select(_db.postingsTable)
          ..where((tbl) => tbl.categoryId.equals(id))
          ..limit(1))
        .getSingleOrNull();

    final hasTx = await (_db.select(_db.financialTransactions)
          ..where((tbl) =>
              tbl.categoryId.equals(id) & tbl.isSuperseded.equals(false))
          ..limit(1))
        .getSingleOrNull();

    final hasCommitments = await (_db.select(_db.financialCommitments)
          ..where((tbl) => tbl.categoryId.equals(id))
          ..limit(1))
        .getSingleOrNull();

    final hasBudgets = await (_db.select(_db.budgetsTable)
          ..where((tbl) => tbl.categoryId.equals(id))
          ..limit(1))
        .getSingleOrNull();

    final hasRules = await (_db.select(_db.recurringRulesTable)
          ..where((tbl) => tbl.categoryId.equals(id))
          ..limit(1))
        .getSingleOrNull();

    final hasChildren = await (_db.select(_db.financialCategories)
          ..where((tbl) => tbl.parentId.equals(id))
          ..limit(1))
        .getSingleOrNull();

    if (hasPostings != null ||
        hasTx != null ||
        hasCommitments != null ||
        hasBudgets != null ||
        hasRules != null ||
        hasChildren != null) {
      return false;
    }

    final count = await (_db.delete(_db.financialCategories)
          ..where((tbl) => tbl.id.equals(id)))
        .go();
    return count > 0;
  }

  // ==========================================================================
  // ITransactionRepositoryContract (Double-Entry Authoritative Ledger)
  // ==========================================================================

  @override
  Future<List<JournalEntryModel>> getJournalEntries({
    String? startDate,
    String? endDate,
    bool includeVoided = true,
  }) async {
    final query = _db.select(_db.journalEntriesTable);
    if (!includeVoided) {
      query.where((tbl) => tbl.isVoided.equals(false));
    }
    if (startDate != null) {
      query.where((tbl) => tbl.occurrenceDate.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((tbl) => tbl.occurrenceDate.isSmallerOrEqualValue(endDate));
    }
    query.orderBy([
      (tbl) => OrderingTerm.desc(tbl.occurrenceDate),
      (tbl) => OrderingTerm.desc(tbl.createdAt),
    ]);
    final rows = await query.get();
    return rows.map(_mapJournalEntryRow).toList();
  }

  @override
  Future<List<PostingModel>> getPostings({
    String? accountId,
    String? entryId,
    String? startDate,
    String? endDate,
  }) async {
    final query = _db.select(_db.postingsTable);
    if (accountId != null) {
      query.where((tbl) => tbl.accountId.equals(accountId));
    }
    if (entryId != null) {
      query.where((tbl) => tbl.entryId.equals(entryId));
    }
    if (startDate != null) {
      query.where(
          (tbl) => tbl.accountMovementDate.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where(
          (tbl) => tbl.accountMovementDate.isSmallerOrEqualValue(endDate));
    }
    final rows = await query.get();

    return rows.map((r) {
      final direction = r.direction == 'debit'
          ? PostingDirection.debit
          : PostingDirection.credit;
      return PostingModel(
        id: r.id,
        entryId: r.entryId,
        accountId: r.accountId,
        amountCents: r.amountCents,
        direction: direction,
        accountMovementDate: r.accountMovementDate,
        categoryId: r.categoryId,
        note: r.note,
      );
    }).toList();
  }

  @override
  Future<JournalEntryModel> recordJournalEntry({
    required JournalEntryModel entry,
    required List<PostingModel> postings,
  }) async {
    DoubleEntryEngine.validateBalancedEntry(postings);

    await _db.transaction(() async {
      await _insertEntryAndPostingsInTx(entry, postings);
      await _syncVaultGoalsInTx();
    });

    return entry;
  }

  @override
  Future<JournalEntryModel> recordDirectExpense({
    required String accountId,
    required String categoryId,
    required int amountCents,
    required CalendarDate date,
    CalendarDate? movementDate,
    required String description,
    String? payee,
    String? note,
  }) async {
    if (amountCents <= 0) {
      throw ArgumentError('Expense amount must be strictly greater than 0.');
    }
    final cleanDesc = _formatDescription(description, payee: payee);
    final entryId = 'entry-${_uuid.v4()}';
    final txId = 'tx-$entryId';
    final cleanNote =
        (note != null && note.trim().isNotEmpty) ? note.trim() : null;
    final cleanPayee =
        (payee != null && payee.trim().isNotEmpty) ? payee.trim() : null;
    final built = DoubleEntryEngine.buildDirectExpense(
      entryId: entryId,
      paidAccountId: accountId,
      categoryId: categoryId,
      amountCents: amountCents,
      date: date.toIsoString(),
      movementDate: movementDate?.toIsoString(),
      description: cleanDesc,
      note: cleanNote,
    );
    final entry =
        (built['entry'] as JournalEntryModel).copyWith(legacySourceTxId: txId);
    final postings = built['postings'] as List<PostingModel>;
    DoubleEntryEngine.validateBalancedEntry(postings);

    await _db.transaction(() async {
      await V6LedgerMigrator.ensureSystemControlAccounts(_db);
      await _assertSpendableEtbAccountsInTx(
        [accountId],
        roleLabel: 'Paid account',
      );
      await _ensureCategoryExists(
        categoryId,
        DoubleEntryEngine.canonicalCategoryNameForSeed(categoryId),
        'expense',
      );
      await _insertEntryAndPostingsInTx(entry, postings);
      await _db.into(_db.financialTransactions).insertOnConflictUpdate(
            FinancialTransactionsCompanion.insert(
              id: txId,
              categoryId: categoryId,
              amountCents: amountCents,
              type: 'expense',
              transactionDate: date.toIsoString(),
              note: Value(cleanNote),
              payee: Value(cleanPayee),
              accountId: Value(accountId),
              isSuperseded: const Value(false),
              createdAt: entry.createdAt,
            ),
          );
      await _syncVaultGoalsInTx();
    });
    return entry;
  }

  @override
  Future<JournalEntryModel> recordDirectIncome({
    required String accountId,
    required String categoryId,
    required int amountCents,
    required CalendarDate date,
    CalendarDate? movementDate,
    required String description,
    String? payee,
    String? note,
  }) async {
    if (amountCents <= 0) {
      throw ArgumentError('Income amount must be strictly greater than 0.');
    }
    final cleanDesc = _formatDescription(description, payee: payee);
    final entryId = 'entry-${_uuid.v4()}';
    final txId = 'tx-$entryId';
    final cleanNote =
        (note != null && note.trim().isNotEmpty) ? note.trim() : null;
    final cleanPayee =
        (payee != null && payee.trim().isNotEmpty) ? payee.trim() : null;
    final built = DoubleEntryEngine.buildDirectIncome(
      entryId: entryId,
      destAccountId: accountId,
      categoryId: categoryId,
      amountCents: amountCents,
      date: date.toIsoString(),
      movementDate: movementDate?.toIsoString(),
      description: cleanDesc,
      note: cleanNote,
    );
    final entry =
        (built['entry'] as JournalEntryModel).copyWith(legacySourceTxId: txId);
    final postings = built['postings'] as List<PostingModel>;
    DoubleEntryEngine.validateBalancedEntry(postings);

    await _db.transaction(() async {
      await V6LedgerMigrator.ensureSystemControlAccounts(_db);
      await _assertSpendableEtbAccountsInTx(
        [accountId],
        roleLabel: 'Deposit account',
      );
      await _ensureCategoryExists(
        categoryId,
        DoubleEntryEngine.canonicalCategoryNameForSeed(categoryId),
        'income',
      );
      await _insertEntryAndPostingsInTx(entry, postings);
      await _db.into(_db.financialTransactions).insertOnConflictUpdate(
            FinancialTransactionsCompanion.insert(
              id: txId,
              categoryId: categoryId,
              amountCents: amountCents,
              type: 'income',
              transactionDate: date.toIsoString(),
              note: Value(cleanNote),
              payee: Value(cleanPayee),
              accountId: Value(accountId),
              isSuperseded: const Value(false),
              createdAt: entry.createdAt,
            ),
          );
      await _syncVaultGoalsInTx();
    });
    return entry;
  }

  @override
  Future<JournalEntryModel> recordAccountTransfer({
    required String fromAccountId,
    required String toAccountId,
    required int amountCents,
    int transferFeeCents = 0,
    String? feeCategoryId,
    required CalendarDate date,
    CalendarDate? movementDate,
    required String description,
    String? note,
  }) async {
    if (fromAccountId == toAccountId) {
      throw ArgumentError('Source and destination accounts must be distinct.');
    }
    if (amountCents <= 0) {
      throw ArgumentError('Transfer amount must be strictly greater than 0.');
    }
    if (transferFeeCents < 0) {
      throw ArgumentError('Transfer fee cannot be negative.');
    }

    final entryId = 'entry-xfer-${_uuid.v4()}';
    final txId = 'tx-$entryId';
    final dateIso = date.toIsoString();
    final effectiveFeeCatId = transferFeeCents > 0
        ? ((feeCategoryId != null && feeCategoryId.trim().isNotEmpty)
            ? feeCategoryId.trim()
            : SystemControlAccounts.feeCategoryId)
        : null;
    final cleanNote =
        (note != null && note.trim().isNotEmpty) ? note.trim() : null;

    final built = DoubleEntryEngine.buildTransfer(
      entryId: entryId,
      fromAssetAccountId: fromAccountId,
      toAssetAccountId: toAccountId,
      amountCents: amountCents,
      date: dateIso,
      movementDate: movementDate?.toIsoString(),
      description:
          description.trim().isEmpty ? 'Account Transfer' : description.trim(),
      transferFeeCents: transferFeeCents,
      feeExpenseAccountId:
          transferFeeCents > 0 ? SystemControlAccounts.expense : null,
      feeCategoryId: effectiveFeeCatId,
      note: cleanNote,
    );

    final entry =
        (built['entry'] as JournalEntryModel).copyWith(legacySourceTxId: txId);
    final postings = built['postings'] as List<PostingModel>;

    DoubleEntryEngine.validateBalancedEntry(postings);

    await _db.transaction(() async {
      await V6LedgerMigrator.ensureSystemControlAccounts(_db);
      await _assertTransferEtbAccountsInTx([fromAccountId, toAccountId]);
      final mirrorCategoryId = await _resolveTransferMirrorCategoryIdInTx(
        feeCategoryId: effectiveFeeCatId,
      );
      await _insertEntryAndPostingsInTx(entry, postings);
      await _db.into(_db.financialTransactions).insertOnConflictUpdate(
            FinancialTransactionsCompanion.insert(
              id: txId,
              categoryId: mirrorCategoryId,
              amountCents: amountCents,
              type: 'transfer',
              transactionDate: dateIso,
              note: Value(cleanNote),
              accountId: Value(fromAccountId),
              destinationAccountId: Value(toAccountId),
              isSuperseded: const Value(false),
              createdAt: entry.createdAt,
            ),
          );
      await _syncVaultGoalsInTx();
    });
    return entry;
  }

  @override
  Future<JournalEntryModel> recordSplitExpense({
    required String paidAccountId,
    required String myCategoryId,
    required int myShareCents,
    required int theirShareCents,
    required String partyId,
    required CalendarDate date,
    CalendarDate? movementDate,
    CalendarDate? dueDate,
    required String description,
    String? note,
  }) async {
    if (myShareCents <= 0 || theirShareCents <= 0) {
      throw ArgumentError(
        'Both myShareCents and theirShareCents must be greater than 0.',
      );
    }

    final entryId = 'entry-split-${_uuid.v4()}';
    final debtId = 'debt-split-${_uuid.v4()}';
    final dateIso = date.toIsoString();
    final cleanNote =
        (note != null && note.trim().isNotEmpty) ? note.trim() : null;
    final built = DoubleEntryEngine.buildSplitExpense(
      entryId: entryId,
      debtId: debtId,
      partyId: partyId,
      myExpenseAccountId: SystemControlAccounts.expense,
      receivableAccountId: SystemControlAccounts.receivable,
      paidAssetAccountId: paidAccountId,
      myShareCents: myShareCents,
      theirShareCents: theirShareCents,
      occurrenceDate: dateIso,
      movementDate: movementDate?.toIsoString(),
      dueDate: dueDate?.toIsoString(),
      description: description.trim(),
      categoryId: myCategoryId,
      note: cleanNote,
    );

    final entry = built['entry'] as JournalEntryModel;
    final postings = built['postings'] as List<PostingModel>;
    final debt = built['debt'] as DebtModel;

    DoubleEntryEngine.validateBalancedEntry(postings);

    await _db.transaction(() async {
      await V6LedgerMigrator.ensureSystemControlAccounts(_db);
      await _assertSpendableEtbAccountsInTx(
        [paidAccountId],
        roleLabel: 'Paid account',
      );
      await _ensureCategoryExists(
        myCategoryId,
        DoubleEntryEngine.canonicalCategoryNameForSeed(myCategoryId),
        'expense',
      );
      await _insertEntryAndPostingsInTx(entry, postings);
      await _db.into(_db.debtsTable).insert(
            DebtsTableCompanion.insert(
              id: debt.id,
              originEntryId: debt.originEntryId,
              partyId: debt.partyId,
              debtType: debt.debtType.name,
              principalCents: debt.principalCents,
              outstandingCents: debt.outstandingCents,
              dueDate: Value(debt.dueDate),
              status: Value(debt.status.dbValue),
              writeOffEntryId: Value(debt.writeOffEntryId),
              createdAt: debt.createdAt,
            ),
          );
      await _syncVaultGoalsInTx();
    });
    return entry;
  }

  @override
  Future<JournalEntryModel> recordExpenseRefund({
    required String originalEntryId,
    required String refundAccountId,
    required int refundCents,
    required CalendarDate date,
    String? note,
  }) async {
    late JournalEntryModel created;
    await _db.transaction(() async {
      await V6LedgerMigrator.ensureSystemControlAccounts(_db);
      final accounts =
          await getAccounts(includeArchived: true, includeSystem: true);
      final entries = await getJournalEntries(includeVoided: true);
      final postings = await getPostings();
      final debts = await getDebts();
      final allocations = await getSettlementAllocations();

      final refundEntryId = 'entry-refund-${_uuid.v4()}';
      final built = DoubleEntryEngine.buildExpenseRefund(
        refundEntryId: refundEntryId,
        originalEntryId: originalEntryId,
        refundAccountId: refundAccountId,
        refundCents: refundCents,
        refundDateIso: date.toIsoString(),
        note: note,
        entries: entries,
        postings: postings,
        accounts: accounts,
        debts: debts,
        allocations: allocations,
      );
      created = built['entry'] as JournalEntryModel;
      final refundPostings = built['postings'] as List<PostingModel>;
      await _insertEntryAndPostingsInTx(created, refundPostings);
      await _syncVaultGoalsInTx();
    });
    return created;
  }

  @override
  Future<JournalEntryModel> correctJournalEntry({
    required String originalEntryId,
    required JournalEntryModel replacementEntry,
    required List<PostingModel> replacementPostings,
    required String correctionReason,
  }) async {
    DoubleEntryEngine.validateBalancedEntry(replacementPostings);
    if (!DoubleEntryEngine.isCorrectableEntryType(replacementEntry.entryType)) {
      throw DoubleEntryValidationError(
        'Replacement entry type "${replacementEntry.entryType.dbValue}" is '
        'not supported during correction.',
      );
    }
    if (DoubleEntryEngine.isRefundEntry(replacementEntry)) {
      throw DoubleEntryValidationError(
        'Cannot convert an entry into a refund via correction.',
      );
    }
    final linkedEntry = replacementEntry.copyWith(
      correctedFromEntryId: originalEntryId,
      isVoided: false,
    );
    var returnedEntry = linkedEntry;

    await _db.transaction(() async {
      final accounts =
          await getAccounts(includeArchived: true, includeSystem: true);
      final entries = await getJournalEntries(includeVoided: true);
      final postings = await getPostings();
      final debts = await getDebts();
      final allocations = await getSettlementAllocations();
      final cmSettlements = await getCommitmentSettlements();

      final origMatches = entries.where((e) => e.id == originalEntryId);
      if (origMatches.isEmpty) {
        throw DoubleEntryValidationError(
          'Original journal entry "$originalEntryId" not found.',
        );
      }
      final original = origMatches.first;
      final check = DoubleEntryEngine.canCorrectEntry(
        entry: original,
        entries: entries,
        postings: postings,
        accounts: accounts,
        debts: debts,
        allocations: allocations,
        commitmentSettlements: cmSettlements,
      );
      if (!check.ok) {
        throw DoubleEntryValidationError(
          check.error ?? 'Entry cannot be replaced.',
        );
      }

      final nonSystemReplacementIds = replacementPostings
          .map((p) => p.accountId)
          .where((id) => !SystemControlAccounts.isSystemControlId(id));
      if (linkedEntry.entryType == EntryType.transfer) {
        await _assertTransferEtbAccountsInTx(nonSystemReplacementIds);
      } else {
        await _assertSpendableEtbAccountsInTx(nonSystemReplacementIds);
      }

      final origCandidateIds = <String>{
        original.id,
        if (original.id.startsWith('entry-tx-'))
          original.id.substring('entry-tx-'.length),
        if (original.id.startsWith('entry-'))
          original.id.substring('entry-'.length),
        if (original.legacySourceTxId != null &&
            original.legacySourceTxId!.trim().isNotEmpty)
          original.legacySourceTxId!.trim(),
      }.toList();
      final origTxRows = origCandidateIds.isEmpty
          ? const []
          : await (_db.select(_db.financialTransactions)
                ..where((tbl) => tbl.id.isIn(origCandidateIds))
                ..limit(1))
              .get();
      final origTxRow = origTxRows.isEmpty ? null : origTxRows.first;

      await (_db.update(_db.journalEntriesTable)
            ..where((tbl) => tbl.id.equals(originalEntryId)))
          .write(
        JournalEntriesTableCompanion(
          isVoided: const Value(true),
          voidReason: Value('Corrected: ${correctionReason.trim()}'),
        ),
      );
      await _syncDualWriteSupersededInTx(
        entryId: original.id,
        legacySourceTxId: original.legacySourceTxId,
        isSuperseded: true,
      );
      await _syncCommitmentsForEntryInTx(originalEntryId);

      // Ensure any referenced fee/expense/income category exists safely.
      for (final p in replacementPostings) {
        final catId = p.categoryId?.trim();
        if (catId != null && catId.isNotEmpty) {
          final isIncomeControl = p.accountId == SystemControlAccounts.income &&
              p.direction == PostingDirection.credit;
          await _ensureCategoryExists(
            catId,
            DoubleEntryEngine.canonicalCategoryNameForSeed(catId),
            isIncomeControl ? 'income' : 'expense',
          );
        }
      }

      var entryToInsert = linkedEntry;
      if (origTxRow != null) {
        final newTxId = (linkedEntry.legacySourceTxId != null &&
                linkedEntry.legacySourceTxId!.trim().isNotEmpty)
            ? linkedEntry.legacySourceTxId!.trim()
            : 'tx-${linkedEntry.id}';
        final isTransfer = linkedEntry.entryType == EntryType.transfer;
        final isIncome = !isTransfer &&
            replacementPostings.any(
              (p) =>
                  p.accountId == SystemControlAccounts.income &&
                  p.direction == PostingDirection.credit,
            );

        late String txType;
        late int txAmountCents;
        late String txCategoryId;
        String? txAccountId;
        String? txDestAccountId;
        String? txNote;
        String? txPayee;

        if (isTransfer) {
          txType = 'transfer';
          PostingModel? src;
          PostingModel? dst;
          PostingModel? fee;
          for (final p in replacementPostings) {
            if (p.accountId == SystemControlAccounts.expense) {
              fee ??= p;
              continue;
            }
            if (p.direction == PostingDirection.credit &&
                !SystemControlAccounts.isSystemControlId(p.accountId)) {
              src ??= p;
            } else if (p.direction == PostingDirection.debit &&
                !SystemControlAccounts.isSystemControlId(p.accountId)) {
              dst ??= p;
            }
          }
          txAmountCents =
              dst?.amountCents ?? src?.amountCents ?? origTxRow.amountCents;
          txCategoryId = await _resolveTransferMirrorCategoryIdInTx(
            feeCategoryId: fee?.categoryId,
            preferredFallbackId: origTxRow.categoryId,
          );
          txAccountId = src?.accountId ?? origTxRow.accountId;
          txDestAccountId = dst?.accountId ?? origTxRow.destinationAccountId;
          txNote = dst?.note ?? src?.note;
        } else if (isIncome) {
          txType = 'income';
          PostingModel? accDr;
          PostingModel? incCr;
          for (final p in replacementPostings) {
            if (p.accountId == SystemControlAccounts.income &&
                p.direction == PostingDirection.credit) {
              incCr ??= p;
            } else if (p.direction == PostingDirection.debit &&
                !SystemControlAccounts.isSystemControlId(p.accountId)) {
              accDr ??= p;
            }
          }
          txAmountCents =
              accDr?.amountCents ?? incCr?.amountCents ?? origTxRow.amountCents;
          txCategoryId = incCr?.categoryId ?? origTxRow.categoryId;
          txAccountId = accDr?.accountId ?? origTxRow.accountId;
          txNote = accDr?.note ?? incCr?.note;
          final sepIdx = linkedEntry.description.indexOf(' — ');
          txPayee = sepIdx > 0
              ? linkedEntry.description.substring(0, sepIdx).trim()
              : null;
        } else {
          txType = 'expense';
          PostingModel? expDr;
          PostingModel? accCr;
          for (final p in replacementPostings) {
            if (p.accountId == SystemControlAccounts.expense &&
                p.direction == PostingDirection.debit) {
              expDr ??= p;
            } else if (p.direction == PostingDirection.credit &&
                !SystemControlAccounts.isSystemControlId(p.accountId)) {
              accCr ??= p;
            }
          }
          txAmountCents =
              expDr?.amountCents ?? accCr?.amountCents ?? origTxRow.amountCents;
          txCategoryId = expDr?.categoryId ?? origTxRow.categoryId;
          txAccountId = accCr?.accountId ?? origTxRow.accountId;
          txNote = expDr?.note ?? accCr?.note;
          final sepIdx = linkedEntry.description.indexOf(' — ');
          txPayee = sepIdx > 0
              ? linkedEntry.description.substring(0, sepIdx).trim()
              : null;
        }

        if (txType != 'transfer') {
          await _ensureCategoryExists(
            txCategoryId,
            DoubleEntryEngine.canonicalCategoryNameForSeed(txCategoryId),
            txType,
          );
        }

        await _db.into(_db.financialTransactions).insertOnConflictUpdate(
              FinancialTransactionsCompanion.insert(
                id: newTxId,
                categoryId: txCategoryId,
                amountCents: txAmountCents.abs(),
                type: txType,
                transactionDate: linkedEntry.occurrenceDate,
                note: Value(txNote?.trim()),
                payee: Value(txPayee),
                accountId: Value(txAccountId),
                destinationAccountId: Value(txDestAccountId),
                isSuperseded: const Value(false),
                correctedFromId: Value(origTxRow.id),
                correctionReason: Value(correctionReason.trim()),
                createdAt: linkedEntry.createdAt,
              ),
            );
        entryToInsert = linkedEntry.copyWith(legacySourceTxId: newTxId);
      }

      await _insertEntryAndPostingsInTx(entryToInsert, replacementPostings);
      await V7LedgerHardener.reconcileAllDebtsV7(_db);
      await _syncVaultGoalsInTx();
      returnedEntry = entryToInsert;
    });
    return returnedEntry;
  }

  @override
  Future<JournalEntryModel> voidJournalEntry({
    required String entryId,
    required String voidReason,
  }) async {
    late JournalEntryModel updated;
    await _db.transaction(() async {
      updated = await _voidEntryInternalInTx(entryId, voidReason);
    });
    return updated;
  }

  @override
  Future<void> unvoidJournalEntry(String entryId) async {
    await _db.transaction(() async {
      await _unvoidEntryInternalInTx(entryId);
    });
  }

  @override
  Future<List<TransactionModel>> getTransactions({
    CalendarDate? startDate,
    CalendarDate? endDate,
  }) async {
    final categories = await _db.select(_db.financialCategories).get();
    final accounts = await _db.select(_db.accountsTable).get();
    final catNames = {for (final c in categories) c.id: c.name};
    final accNames = {for (final a in accounts) a.id: a.name};

    final query = _db.select(_db.financialTransactions);
    if (startDate != null) {
      query.where(
        (tbl) =>
            tbl.transactionDate.isBiggerOrEqualValue(startDate.toIsoString()),
      );
    }
    if (endDate != null) {
      query.where(
        (tbl) =>
            tbl.transactionDate.isSmallerOrEqualValue(endDate.toIsoString()),
      );
    }
    query.orderBy([(tbl) => OrderingTerm.desc(tbl.transactionDate)]);
    final rows = await query.get();

    return rows.map((r) {
      return TransactionModel(
        id: r.id,
        categoryId: r.categoryId,
        categoryName: r.type == 'transfer'
            ? 'Transfer'
            : (catNames[r.categoryId] ?? 'General'),
        amountCents: r.amountCents,
        type: r.type,
        transactionDate: SharedDateFormatter.parseFlexibleToCalendarDate(
          r.transactionDate,
        ),
        note: r.note,
        payee: r.payee,
        isSuperseded: r.isSuperseded,
        correctedFromId: r.correctedFromId,
        correctionReason: r.correctionReason,
        accountId: r.accountId,
        accountName: r.accountId != null ? accNames[r.accountId!] : null,
        destinationAccountId: r.destinationAccountId,
        destinationAccountName: r.destinationAccountId != null
            ? accNames[r.destinationAccountId!]
            : null,
      );
    }).toList();
  }

  Future<void> _ensureCategoryExists(
    String categoryId,
    String categoryName,
    String type,
  ) async {
    final existing = await (_db.select(_db.financialCategories)
          ..where((tbl) => tbl.id.equals(categoryId)))
        .getSingleOrNull();
    if (existing != null) return;

    if (categoryId == SystemControlAccounts.feeCategoryId) {
      await V6LedgerMigrator.ensureSystemCategory(
        _db,
        categoryId: SystemControlAccounts.feeCategoryId,
        name: categoryName.trim().isEmpty || categoryName.trim() == 'General'
            ? 'Financial Fees'
            : categoryName.trim(),
        type: 'expense',
      );
      return;
    }

    final resolvedName =
        (categoryName.trim().isEmpty || categoryName.trim() == 'General')
            ? DoubleEntryEngine.canonicalCategoryNameForSeed(
                categoryId,
                fallback: 'General',
              )
            : categoryName.trim();

    await _db.into(_db.financialCategories).insertOnConflictUpdate(
          FinancialCategoriesCompanion.insert(
            id: categoryId,
            name: resolvedName,
            type: type == 'income' ? 'income' : 'expense',
            colorHex: const Value('#64748B'),
            isDefault: const Value(false),
            isArchived: const Value(false),
          ),
        );
  }

  Future<String> _resolveTransferMirrorCategoryIdInTx({
    String? feeCategoryId,
    String? preferredFallbackId,
  }) async {
    final cleanFee = feeCategoryId?.trim();
    if (cleanFee != null && cleanFee.isNotEmpty) {
      await _ensureCategoryExists(
        cleanFee,
        DoubleEntryEngine.canonicalCategoryNameForSeed(cleanFee),
        'expense',
      );
      return cleanFee;
    }
    final cleanPreferred = preferredFallbackId?.trim();
    if (cleanPreferred != null && cleanPreferred.isNotEmpty) {
      final preferredRow = await (_db.select(_db.financialCategories)
            ..where((tbl) => tbl.id.equals(cleanPreferred)))
          .getSingleOrNull();
      if (preferredRow != null) return preferredRow.id;
    }
    final allCats = await _db.select(_db.financialCategories).get();
    for (final id in [
      SystemControlAccounts.canonicalDefaultExpenseCategoryId,
      SystemControlAccounts.feeCategoryId,
    ]) {
      if (allCats.any((c) => c.id == id)) return id;
    }
    final firstExpense =
        allCats.where((c) => c.type == 'expense').toList(growable: false);
    if (firstExpense.isNotEmpty) return firstExpense.first.id;
    const fallbackId = SystemControlAccounts.canonicalDefaultExpenseCategoryId;
    await _ensureCategoryExists(fallbackId, 'Other', 'expense');
    return fallbackId;
  }

  @override
  Future<TransactionModel> recordTransaction(TransactionModel tx) async {
    final now = EthiopiaClock.nowUtc();
    await _db.transaction(() async {
      await V6LedgerMigrator.ensureSystemControlAccounts(_db);
      await _ensureCategoryExists(tx.categoryId, tx.categoryName, tx.type);

      String? effectiveAccountId = tx.accountId?.trim();
      if (effectiveAccountId != null && effectiveAccountId.isNotEmpty) {
        await _assertEtbAccountsInTx([effectiveAccountId]);
      } else if (tx.type == 'transfer') {
        throw DoubleEntryValidationError(
          'Transfer requires both source and destination ETB accounts.',
        );
      } else {
        final activeAssets = await (_db.select(_db.accountsTable)
              ..where((tbl) =>
                  tbl.isSystem.equals(false) &
                  tbl.isArchived.equals(false) &
                  tbl.type.equals('asset')))
            .get();
        final firstEtb = activeAssets.where(
          (a) => DoubleEntryEngine.isEtb(a.currencyCode),
        );
        if (firstEtb.isEmpty) {
          throw DoubleEntryValidationError(
            'An active ETB account is required to record a transaction.',
          );
        }
        effectiveAccountId = firstEtb.first.id;
      }

      if (tx.type == 'transfer') {
        final destId = tx.destinationAccountId?.trim();
        if (destId == null || destId.isEmpty) {
          throw DoubleEntryValidationError(
            'Destination ETB account is required for transfer.',
          );
        }
        await _assertEtbAccountsInTx([effectiveAccountId, destId]);
      }

      await _db.into(_db.financialTransactions).insertOnConflictUpdate(
            FinancialTransactionsCompanion.insert(
              id: tx.id,
              categoryId: tx.categoryId,
              amountCents: tx.amountCents.abs(),
              type: tx.type,
              transactionDate: tx.transactionDate.toIsoString(),
              note: Value(tx.note?.trim()),
              payee: Value(tx.payee?.trim()),
              accountId: Value(effectiveAccountId),
              destinationAccountId: Value(tx.destinationAccountId),
              isSuperseded: Value(tx.isSuperseded),
              correctedFromId: Value(tx.correctedFromId),
              correctionReason: Value(tx.correctionReason),
              createdAt: now,
            ),
          );

      final existingLedger = await (_db.select(_db.journalEntriesTable)
            ..where((tbl) => tbl.legacySourceTxId.equals(tx.id))
            ..limit(1))
          .getSingleOrNull();
      if (existingLedger == null && tx.amountCents > 0) {
        final dateIso = tx.transactionDate.toIsoString();
        final desc = _formatDescription(
          tx.note?.trim().isNotEmpty == true ? tx.note! : tx.categoryName,
          payee: tx.payee,
        );
        final entryId = 'entry-tx-${tx.id}';
        late JournalEntryModel entry;
        late List<PostingModel> postings;

        if (tx.type == 'transfer') {
          final built = DoubleEntryEngine.buildTransfer(
            entryId: entryId,
            fromAssetAccountId: effectiveAccountId,
            toAssetAccountId: tx.destinationAccountId!,
            amountCents: tx.amountCents.abs(),
            date: dateIso,
            description: desc,
            note: tx.note?.trim(),
          );
          entry = (built['entry'] as JournalEntryModel).copyWith(
            legacySourceTxId: tx.id,
            isVoided: tx.isSuperseded,
          );
          postings = built['postings'] as List<PostingModel>;
        } else if (tx.type == 'income') {
          final built = DoubleEntryEngine.buildDirectIncome(
            entryId: entryId,
            destAccountId: effectiveAccountId,
            categoryId: tx.categoryId,
            amountCents: tx.amountCents.abs(),
            date: dateIso,
            description: desc,
            note: tx.note?.trim(),
          );
          entry = (built['entry'] as JournalEntryModel).copyWith(
            legacySourceTxId: tx.id,
            isVoided: tx.isSuperseded,
          );
          postings = built['postings'] as List<PostingModel>;
        } else {
          final built = DoubleEntryEngine.buildDirectExpense(
            entryId: entryId,
            paidAccountId: effectiveAccountId,
            categoryId: tx.categoryId,
            amountCents: tx.amountCents.abs(),
            date: dateIso,
            description: desc,
            note: tx.note?.trim(),
          );
          entry = (built['entry'] as JournalEntryModel).copyWith(
            legacySourceTxId: tx.id,
            isVoided: tx.isSuperseded,
          );
          postings = built['postings'] as List<PostingModel>;
        }
        DoubleEntryEngine.validateBalancedEntry(postings);
        await _insertEntryAndPostingsInTx(entry, postings);
      }
      await _syncVaultGoalsInTx();
    });
    return tx;
  }

  @override
  Future<TransactionModel> correctTransaction({
    required String originalId,
    required int newAmountCents,
    required String newCategoryId,
    required String newCategoryName,
    required String correctionReason,
    String? newNote,
    String? newPayee,
  }) async {
    late TransactionModel result;

    await _db.transaction(() async {
      await V6LedgerMigrator.ensureSystemControlAccounts(_db);
      final original = await (_db.select(_db.financialTransactions)
            ..where((tbl) => tbl.id.equals(originalId)))
          .getSingle();

      if (original.isSuperseded) {
        throw DoubleEntryValidationError(
          'This transaction has already been superseded and cannot be replaced again.',
        );
      }
      if (original.accountId == null || original.accountId!.trim().isEmpty) {
        throw DoubleEntryValidationError(
          'Legacy unlinked transactions cannot be corrected in ETB mode.',
        );
      }
      if (original.type == 'transfer') {
        final destId = original.destinationAccountId?.trim();
        if (destId == null ||
            destId.isEmpty ||
            destId == original.accountId!.trim()) {
          throw DoubleEntryValidationError(
            'Transfer replacement requires distinct source and destination ETB accounts.',
          );
        }
      }
      await _assertEtbAccountsInTx([
        original.accountId!,
        if (original.destinationAccountId != null)
          original.destinationAccountId!,
      ]);

      final originalLedgerPreCheck = await (_db.select(_db.journalEntriesTable)
            ..where((tbl) =>
                tbl.legacySourceTxId.equals(originalId) |
                tbl.id.equals(originalId) |
                tbl.id.equals('entry-$originalId') |
                tbl.id.equals('entry-tx-$originalId'))
            ..limit(1))
          .getSingleOrNull();
      var origEntryPostings = const <PostingModel>[];
      if (originalLedgerPreCheck != null) {
        final accounts =
            await getAccounts(includeArchived: true, includeSystem: true);
        final entries = await getJournalEntries(includeVoided: true);
        final postings = await getPostings();
        final debts = await getDebts();
        final allocations = await getSettlementAllocations();
        final cmSettlements = await getCommitmentSettlements();
        final check = DoubleEntryEngine.canCorrectEntry(
          entry: _mapJournalEntryRow(originalLedgerPreCheck),
          entries: entries,
          postings: postings,
          accounts: accounts,
          debts: debts,
          allocations: allocations,
          commitmentSettlements: cmSettlements,
        );
        if (!check.ok) {
          throw DoubleEntryValidationError(
            check.error ?? 'Only active ETB transactions can be corrected.',
          );
        }
        origEntryPostings = postings
            .where((p) => p.entryId == originalLedgerPreCheck.id)
            .toList();
      }

      final now = EthiopiaClock.nowUtc();
      final newId = 'tx-${now.millisecondsSinceEpoch}';
      final prefixLen = original.id.length < 8 ? original.id.length : 8;
      final newPrefixLen = newId.length < 8 ? newId.length : 8;

      if (original.type != 'transfer') {
        await _ensureCategoryExists(
          newCategoryId,
          newCategoryName,
          original.type,
        );
      }

      final correctionNote =
          '[Corrected from ${original.id.substring(0, prefixLen)}: $correctionReason] ${newNote ?? original.note ?? ''}';

      await _db.into(_db.financialTransactions).insert(
            FinancialTransactionsCompanion.insert(
              id: newId,
              categoryId: newCategoryId,
              amountCents: newAmountCents.abs(),
              type: original.type,
              transactionDate: original.transactionDate,
              note: Value(correctionNote.trim()),
              payee: Value(newPayee ?? original.payee),
              accountId: Value(original.accountId),
              destinationAccountId: Value(original.destinationAccountId),
              isSuperseded: const Value(false),
              correctedFromId: Value(original.id),
              correctionReason: Value(correctionReason),
              createdAt: now,
            ),
          );

      await (_db.update(_db.financialTransactions)
            ..where((tbl) => tbl.id.equals(original.id)))
          .write(
        FinancialTransactionsCompanion(
          isSuperseded: const Value(true),
          note: Value(
              '[Superseded by ${newId.substring(0, newPrefixLen)}] ${original.note ?? ''}'),
        ),
      );

      final originalLedger = originalLedgerPreCheck;
      if (originalLedger != null) {
        await (_db.update(_db.journalEntriesTable)
              ..where((tbl) => tbl.id.equals(originalLedger.id)))
            .write(
          JournalEntriesTableCompanion(
            isVoided: const Value(true),
            voidReason: Value('Corrected: $correctionReason'),
          ),
        );
        await _syncCommitmentsForEntryInTx(originalLedger.id);
      }

      if (newAmountCents.abs() > 0) {
        final effectiveAccountId = original.accountId!;
        final replacementId = 'entry-tx-$newId';
        final desc = _formatDescription(
          correctionNote.trim(),
          payee: newPayee ?? original.payee,
        );
        final sameOccurrenceDate = originalLedger != null &&
            original.transactionDate == originalLedger.occurrenceDate;
        late Map<String, dynamic> built;
        if (original.type == 'transfer') {
          PostingModel? feePosting;
          PostingModel? dstPosting;
          PostingModel? srcPosting;
          for (final p in origEntryPostings) {
            if (p.accountId == SystemControlAccounts.expense) {
              feePosting ??= p;
            } else if (p.direction == PostingDirection.debit &&
                !SystemControlAccounts.isSystemControlId(p.accountId)) {
              dstPosting ??= p;
            } else if (p.direction == PostingDirection.credit &&
                !SystemControlAccounts.isSystemControlId(p.accountId)) {
              srcPosting ??= p;
            }
          }
          final preservedFeeCents = feePosting?.amountCents ?? 0;
          final preservedFeeCategoryId =
              preservedFeeCents > 0 ? feePosting?.categoryId : null;
          final preservedMovementDate = sameOccurrenceDate
              ? (dstPosting?.accountMovementDate ??
                  srcPosting?.accountMovementDate ??
                  original.transactionDate)
              : original.transactionDate;
          built = DoubleEntryEngine.buildTransfer(
            entryId: replacementId,
            fromAssetAccountId: effectiveAccountId,
            toAssetAccountId: original.destinationAccountId!,
            amountCents: newAmountCents.abs(),
            transferFeeCents: preservedFeeCents,
            feeExpenseAccountId:
                preservedFeeCents > 0 ? SystemControlAccounts.expense : null,
            feeCategoryId: preservedFeeCategoryId,
            date: original.transactionDate,
            movementDate: preservedMovementDate,
            description: desc,
            note: correctionNote.trim(),
          );
          final rawEntry = built['entry'] as JournalEntryModel;
          built['entry'] = rawEntry.copyWith(
            correctedFromEntryId: originalLedger?.id,
          );
        } else if (original.type == 'income') {
          PostingModel? drAcc;
          for (final p in origEntryPostings) {
            if (p.direction == PostingDirection.debit &&
                !SystemControlAccounts.isSystemControlId(p.accountId)) {
              drAcc ??= p;
            }
          }
          final preservedMovementDate = sameOccurrenceDate
              ? (drAcc?.accountMovementDate ?? original.transactionDate)
              : original.transactionDate;
          built = DoubleEntryEngine.buildDirectIncome(
            entryId: replacementId,
            destAccountId: effectiveAccountId,
            categoryId: newCategoryId,
            amountCents: newAmountCents.abs(),
            date: original.transactionDate,
            movementDate: preservedMovementDate,
            description: desc,
            note: correctionNote.trim(),
            correctedFromEntryId: originalLedger?.id,
          );
        } else {
          PostingModel? crAcc;
          for (final p in origEntryPostings) {
            if (p.direction == PostingDirection.credit &&
                !SystemControlAccounts.isSystemControlId(p.accountId)) {
              crAcc ??= p;
            }
          }
          final preservedMovementDate = sameOccurrenceDate
              ? (crAcc?.accountMovementDate ?? original.transactionDate)
              : original.transactionDate;
          built = DoubleEntryEngine.buildDirectExpense(
            entryId: replacementId,
            paidAccountId: effectiveAccountId,
            categoryId: newCategoryId,
            amountCents: newAmountCents.abs(),
            date: original.transactionDate,
            movementDate: preservedMovementDate,
            description: desc,
            note: correctionNote.trim(),
            correctedFromEntryId: originalLedger?.id,
          );
        }
        final replacementEntry = (built['entry'] as JournalEntryModel).copyWith(
          legacySourceTxId: newId,
        );
        final replacementPostings = built['postings'] as List<PostingModel>;
        DoubleEntryEngine.validateBalancedEntry(replacementPostings);
        await _insertEntryAndPostingsInTx(
            replacementEntry, replacementPostings);
      }

      await V7LedgerHardener.reconcileAllDebtsV7(_db);
      await _syncVaultGoalsInTx();

      result = TransactionModel(
        id: newId,
        categoryId: newCategoryId,
        categoryName: newCategoryName,
        amountCents: newAmountCents.abs(),
        type: original.type,
        transactionDate: SharedDateFormatter.parseFlexibleToCalendarDate(
          original.transactionDate,
        ),
        note: correctionNote.trim(),
        payee: newPayee ?? original.payee,
        isSuperseded: false,
        correctedFromId: original.id,
        correctionReason: correctionReason,
        accountId: original.accountId,
        destinationAccountId: original.destinationAccountId,
      );
    });

    return result;
  }

  @override
  Future<void> deleteTransaction(String id) async {
    await _db.transaction(() async {
      final linkedEntries = await (_db.select(_db.journalEntriesTable)
            ..where((tbl) =>
                tbl.id.equals(id) |
                tbl.id.equals('entry-$id') |
                tbl.id.equals('entry-tx-$id') |
                tbl.legacySourceTxId.equals(id)))
          .get();
      for (final linked in linkedEntries) {
        await _voidEntryInternalInTx(linked.id, 'Deleted via Finance UI');
      }
      await (_db.delete(_db.financialTransactions)
            ..where((tbl) => tbl.id.equals(id)))
          .go();
      await V7LedgerHardener.reconcileAllDebtsV7(_db);
      await _syncVaultGoalsInTx();
    });
  }

  @override
  Future<void> restoreTransaction(TransactionModel tx) async {
    await _db.transaction(() async {
      final acctId = tx.accountId?.trim();
      if (acctId == null || acctId.isEmpty) {
        throw DoubleEntryValidationError(
          'Legacy unlinked transactions cannot be restored in ETB mode.',
        );
      }
      final destId = tx.destinationAccountId?.trim();
      await _assertEtbAccountsInTx([
        acctId,
        if (destId != null && destId.isNotEmpty) destId,
      ]);

      final existingLinked = await (_db.select(_db.journalEntriesTable)
            ..where((tbl) =>
                tbl.id.equals(tx.id) |
                tbl.id.equals('entry-${tx.id}') |
                tbl.id.equals('entry-tx-${tx.id}') |
                tbl.legacySourceTxId.equals(tx.id)))
          .get();
      for (final linked in existingLinked) {
        await _unvoidEntryInternalInTx(linked.id);
      }

      await recordTransaction(tx.copyWith(isSuperseded: false));
      await V7LedgerHardener.reconcileAllDebtsV7(_db);
      await _syncVaultGoalsInTx();
    });
  }

  // ==========================================================================
  // IDebtRepositoryContract (Debts, Parties, Settlements, Commitments, Savings)
  // ==========================================================================

  @override
  Future<List<DebtModel>> getDebts({DebtType? type, DebtStatus? status}) async {
    final query = _db.select(_db.debtsTable);
    if (type != null) {
      query.where((tbl) => tbl.debtType.equals(type.name));
    }
    if (status != null) {
      query.where((tbl) => tbl.status.equals(status.dbValue));
    }
    query.orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);
    final rows = await query.get();
    return rows.map(_mapDebtRow).toList();
  }

  @override
  Future<List<PartyModel>> getParties({bool includeArchived = false}) async {
    final query = _db.select(_db.partiesTable);
    if (!includeArchived) {
      query.where((tbl) => tbl.isArchived.equals(false));
    }
    query.orderBy([(tbl) => OrderingTerm.asc(tbl.name)]);
    final rows = await query.get();

    return rows
        .map((r) => PartyModel(
              id: r.id,
              name: r.name,
              phone: r.phone,
              notes: r.notes,
              isArchived: r.isArchived,
              createdAt: r.createdAt,
            ))
        .toList();
  }

  @override
  Future<PartyModel> createParty(PartyModel party) async {
    await _db.into(_db.partiesTable).insertOnConflictUpdate(
          PartiesTableCompanion.insert(
            id: party.id,
            name: party.name.trim(),
            phone: Value(party.phone),
            notes: Value(party.notes),
            isArchived: Value(party.isArchived),
            createdAt: party.createdAt,
          ),
        );
    return party;
  }

  @override
  Future<PartyModel> updateParty(PartyModel party) async {
    await (_db.update(_db.partiesTable)
          ..where((tbl) => tbl.id.equals(party.id)))
        .write(
      PartiesTableCompanion(
        name: Value(party.name.trim()),
        phone: Value(party.phone),
        notes: Value(party.notes),
        isArchived: Value(party.isArchived),
      ),
    );
    return party;
  }

  @override
  Future<void> archiveParty(String id) async {
    await (_db.update(_db.partiesTable)..where((tbl) => tbl.id.equals(id)))
        .write(const PartiesTableCompanion(isArchived: Value(true)));
  }

  @override
  Future<List<SettlementAllocationModel>> getSettlementAllocations() async {
    final rows = await _db.select(_db.settlementAllocationsTable).get();
    return rows
        .map((r) => SettlementAllocationModel(
              id: r.id,
              settlementEntryId: r.settlementEntryId,
              debtId: r.debtId,
              allocatedCents: r.allocatedCents,
              settlementDate: r.settlementDate,
            ))
        .toList();
  }

  @override
  Future<DebtModel> recordDebt(DebtModel debt) async {
    await _db.into(_db.debtsTable).insert(
          DebtsTableCompanion.insert(
            id: debt.id,
            originEntryId: debt.originEntryId,
            partyId: debt.partyId,
            debtType: debt.debtType.name,
            principalCents: debt.principalCents,
            outstandingCents: debt.outstandingCents,
            dueDate: Value(debt.dueDate),
            status: Value(debt.status.dbValue),
            writeOffEntryId: Value(debt.writeOffEntryId),
            createdAt: debt.createdAt,
          ),
        );
    return debt;
  }

  @override
  Future<DebtModel> recordDebtWithEntry({
    required JournalEntryModel entry,
    required List<PostingModel> postings,
    required DebtModel debt,
  }) async {
    DoubleEntryEngine.validateBalancedEntry(postings);

    await _db.transaction(() async {
      await V6LedgerMigrator.ensureSystemControlAccounts(_db);
      await _assertSpendableEtbAccountsInTx(
        postings.map((p) => p.accountId),
        roleLabel: 'Debt account',
      );
      await _insertEntryAndPostingsInTx(entry, postings);
      await _db.into(_db.debtsTable).insert(
            DebtsTableCompanion.insert(
              id: debt.id,
              originEntryId: debt.originEntryId,
              partyId: debt.partyId,
              debtType: debt.debtType.name,
              principalCents: debt.principalCents,
              outstandingCents: debt.outstandingCents,
              dueDate: Value(debt.dueDate),
              status: Value(debt.status.dbValue),
              writeOffEntryId: Value(debt.writeOffEntryId),
              createdAt: debt.createdAt,
            ),
          );
    });
    return debt;
  }

  @override
  Future<SettlementAllocationModel> recordSettlement({
    required SettlementAllocationModel allocation,
    required JournalEntryModel settlementEntry,
    required List<PostingModel> settlementPostings,
    required DebtModel updatedDebt,
  }) async {
    DoubleEntryEngine.validateBalancedEntry(settlementPostings);

    await _db.transaction(() async {
      await V6LedgerMigrator.ensureSystemControlAccounts(_db);
      await _assertEtbDebtInTx(allocation.debtId);
      await _assertSpendableEtbAccountsInTx(
        settlementPostings.map((p) => p.accountId),
        roleLabel: 'Settlement account',
      );
      await _insertEntryAndPostingsInTx(settlementEntry, settlementPostings);

      await _db.into(_db.settlementAllocationsTable).insert(
            SettlementAllocationsTableCompanion.insert(
              id: allocation.id,
              settlementEntryId: allocation.settlementEntryId,
              debtId: allocation.debtId,
              allocatedCents: allocation.allocatedCents,
              settlementDate: allocation.settlementDate,
            ),
          );

      await (_db.update(_db.debtsTable)
            ..where((tbl) => tbl.id.equals(updatedDebt.id)))
          .write(
        DebtsTableCompanion(
          outstandingCents: Value(updatedDebt.outstandingCents),
          status: Value(updatedDebt.status.dbValue),
        ),
      );
    });

    return allocation;
  }

  @override
  Future<DebtModel> writeOffDebt({
    required String debtId,
    required String reason,
    required CalendarDate date,
  }) async {
    late DebtModel result;

    await _db.transaction(() async {
      await V6LedgerMigrator.ensureSystemControlAccounts(_db);
      final row = await (_db.select(_db.debtsTable)
            ..where((tbl) => tbl.id.equals(debtId)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('Debt record not found: $debtId');
      }

      final mapped = _mapDebtRow(row);
      if (mapped.status != DebtStatus.active ||
          mapped.outstandingCents <= 0 ||
          mapped.writeOffEntryId != null) {
        throw DoubleEntryValidationError(
          'Only active debts with positive balance can be written off.',
        );
      }
      await _assertEtbDebtInTx(debtId, debtOverride: mapped);

      final dateIso = date.toIsoString();
      final entryId = 'entry-wo-${_uuid.v4()}';
      final cleanReason = reason.trim().isEmpty ? 'Written off' : reason.trim();
      final writeOffEntry = JournalEntryModel(
        id: entryId,
        entryType: EntryType.writeOff,
        description: 'Debt Write-Off: $cleanReason',
        occurrenceDate: dateIso,
      );

      final List<PostingModel> postings;
      if (mapped.debtType == DebtType.receivable) {
        postings = [
          PostingModel(
            id: '$entryId-dr-exp',
            entryId: entryId,
            accountId: SystemControlAccounts.expense,
            amountCents: mapped.outstandingCents,
            direction: PostingDirection.debit,
            accountMovementDate: dateIso,
            note: cleanReason,
          ),
          PostingModel(
            id: '$entryId-cr-rec',
            entryId: entryId,
            accountId: SystemControlAccounts.receivable,
            amountCents: mapped.outstandingCents,
            direction: PostingDirection.credit,
            accountMovementDate: dateIso,
            note: cleanReason,
          ),
        ];
      } else {
        postings = [
          PostingModel(
            id: '$entryId-dr-pay',
            entryId: entryId,
            accountId: SystemControlAccounts.payable,
            amountCents: mapped.outstandingCents,
            direction: PostingDirection.debit,
            accountMovementDate: dateIso,
            note: cleanReason,
          ),
          PostingModel(
            id: '$entryId-cr-inc',
            entryId: entryId,
            accountId: SystemControlAccounts.income,
            amountCents: mapped.outstandingCents,
            direction: PostingDirection.credit,
            accountMovementDate: dateIso,
            note: cleanReason,
          ),
        ];
      }

      DoubleEntryEngine.validateBalancedEntry(postings);
      await _insertEntryAndPostingsInTx(writeOffEntry, postings);

      await (_db.update(_db.debtsTable)..where((tbl) => tbl.id.equals(debtId)))
          .write(
        DebtsTableCompanion(
          outstandingCents: const Value(0),
          status: Value(DebtStatus.writtenOff.dbValue),
          writeOffEntryId: Value(entryId),
        ),
      );

      result = mapped.copyWith(
        outstandingCents: 0,
        status: DebtStatus.writtenOff,
        writeOffEntryId: entryId,
      );
    });

    return result;
  }

  @override
  Future<DebtModel> voidDebtOrigin({
    required String debtId,
    required String reason,
  }) async {
    late DebtModel result;
    await _db.transaction(() async {
      final row = await (_db.select(_db.debtsTable)
            ..where((tbl) => tbl.id.equals(debtId)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('Debt record not found: $debtId');
      }
      final allocations = await (_db.select(_db.settlementAllocationsTable)
            ..where((tbl) => tbl.debtId.equals(debtId)))
          .get();
      final entries = await _db.select(_db.journalEntriesTable).get();
      final entryMap = {for (final e in entries) e.id: e};

      final hasActiveSettlements = allocations.any(
        (a) => entryMap[a.settlementEntryId]?.isVoided == false,
      );
      if (hasActiveSettlements) {
        throw StateError(
          'Void active debt settlements before voiding the debt origin.',
        );
      }
      if (row.writeOffEntryId != null &&
          entryMap[row.writeOffEntryId!]?.isVoided == false) {
        throw StateError(
          'Void the debt write-off entry before voiding the debt origin.',
        );
      }

      final cleanReason =
          reason.trim().isEmpty ? 'Voided debt origin' : reason.trim();
      await _voidEntryInternalInTx(row.originEntryId, cleanReason);

      final updatedRow = await (_db.select(_db.debtsTable)
            ..where((tbl) => tbl.id.equals(debtId)))
          .getSingle();
      result = _mapDebtRow(updatedRow);
    });
    return result;
  }

  @override
  Future<List<CommitmentModel>> getCommitments({bool? isPaid}) async {
    final query = _db.select(_db.financialCommitments);
    if (isPaid != null) {
      query.where((tbl) => tbl.isPaid.equals(isPaid));
    }
    query.orderBy([(tbl) => OrderingTerm.asc(tbl.dueDate)]);
    final rows = await query.get();
    if (rows.isEmpty) return const [];

    final settlements = await _db.select(_db.commitmentSettlementsTable).get();
    final entries = await _db.select(_db.journalEntriesTable).get();
    final activeEntryIds = {
      for (final e in entries)
        if (!e.isVoided) e.id,
    };

    final verifiedByCommitment = <String, int>{};
    for (final s in settlements) {
      if (activeEntryIds.contains(s.entryId)) {
        verifiedByCommitment[s.commitmentId] =
            (verifiedByCommitment[s.commitmentId] ?? 0) + s.amountCents;
      }
    }

    return rows
        .map(
          (row) => _mapCommitmentRow(
            row,
            verifiedSettledCents: verifiedByCommitment[row.id] ?? 0,
          ),
        )
        .toList();
  }

  @override
  Future<List<CommitmentSettlementModel>> getCommitmentSettlements({
    String? commitmentId,
  }) async {
    final query = _db.select(_db.commitmentSettlementsTable);
    if (commitmentId != null) {
      query.where((tbl) => tbl.commitmentId.equals(commitmentId));
    }
    query.orderBy([
      (tbl) => OrderingTerm.desc(tbl.settledDate),
      (tbl) => OrderingTerm.desc(tbl.createdAt),
    ]);
    final rows = await query.get();
    if (rows.isEmpty) return const [];

    final entries = await _db.select(_db.journalEntriesTable).get();
    final activeEntryIds = {
      for (final e in entries)
        if (!e.isVoided) e.id,
    };

    return rows
        .where((r) => activeEntryIds.contains(r.entryId))
        .map(
          (r) => CommitmentSettlementModel(
            id: r.id,
            commitmentId: r.commitmentId,
            entryId: r.entryId,
            amountCents: r.amountCents,
            settledDate:
                SharedDateFormatter.parseFlexibleToCalendarDate(r.settledDate),
            createdAt: r.createdAt,
          ),
        )
        .toList();
  }

  @override
  Future<CommitmentModel> addCommitment(CommitmentModel commitment) async {
    await _db.transaction(() async {
      final linkedAccId = commitment.linkedAccountId?.trim();
      final linkedDebtId = commitment.linkedDebtId?.trim();
      if (linkedAccId != null && linkedAccId.isNotEmpty) {
        await _assertEtbAccountsInTx([linkedAccId]);
      }
      if (linkedDebtId != null && linkedDebtId.isNotEmpty) {
        await _assertEtbDebtInTx(linkedDebtId);
      }
      await _db.into(_db.financialCommitments).insertOnConflictUpdate(
            FinancialCommitmentsCompanion.insert(
              id: commitment.id,
              title: commitment.title.trim(),
              amountCents: commitment.amountCents.abs(),
              dueDate: commitment.dueDate.toIsoString(),
              isPaid: Value(commitment.isPaid),
              direction: Value(commitment.direction.name),
              legacyPaidUnverified: Value(commitment.legacyPaidUnverified),
              recurringRule: Value(commitment.recurringRule),
              linkedAccountId: Value(
                (linkedAccId != null && linkedAccId.isNotEmpty)
                    ? linkedAccId
                    : null,
              ),
              categoryId: Value(commitment.categoryId),
              linkedDebtId: Value(
                (linkedDebtId != null && linkedDebtId.isNotEmpty)
                    ? linkedDebtId
                    : null,
              ),
              settlementEntryId: Value(commitment.settlementEntryId),
              recurringRuleId: Value(commitment.recurringRuleId),
              createdAt: EthiopiaClock.nowUtc(),
            ),
          );
    });
    return commitment;
  }

  @override
  Future<CommitmentModel> updateCommitment(CommitmentModel commitment) async {
    await _db.transaction(() async {
      final linkedAccId = commitment.linkedAccountId?.trim();
      final linkedDebtId = commitment.linkedDebtId?.trim();
      if (linkedAccId != null && linkedAccId.isNotEmpty) {
        await _assertEtbAccountsInTx([linkedAccId]);
      }
      if (linkedDebtId != null && linkedDebtId.isNotEmpty) {
        await _assertEtbDebtInTx(linkedDebtId);
      }
      await (_db.update(_db.financialCommitments)
            ..where((tbl) => tbl.id.equals(commitment.id)))
          .write(
        FinancialCommitmentsCompanion(
          title: Value(commitment.title.trim()),
          amountCents: Value(commitment.amountCents.abs()),
          dueDate: Value(commitment.dueDate.toIsoString()),
          isPaid: Value(commitment.isPaid),
          direction: Value(commitment.direction.name),
          legacyPaidUnverified: Value(commitment.legacyPaidUnverified),
          recurringRule: Value(commitment.recurringRule),
          linkedAccountId: Value(
            (linkedAccId != null && linkedAccId.isNotEmpty)
                ? linkedAccId
                : null,
          ),
          categoryId: Value(commitment.categoryId),
          linkedDebtId: Value(
            (linkedDebtId != null && linkedDebtId.isNotEmpty)
                ? linkedDebtId
                : null,
          ),
          settlementEntryId: Value(commitment.settlementEntryId),
          recurringRuleId: Value(commitment.recurringRuleId),
        ),
      );
    });
    return commitment;
  }

  @override
  Future<CommitmentModel> linkCommitmentToEtbAccount({
    required String commitmentId,
    required String accountId,
  }) async {
    late CommitmentModel updated;
    await _db.transaction(() async {
      final trimmedAccId = accountId.trim();
      if (trimmedAccId.isEmpty) {
        throw DoubleEntryValidationError(
          'Select an active Verified ETB account to link.',
        );
      }
      await _assertEtbAccountsInTx([trimmedAccId]);
      final existing = await (_db.select(_db.financialCommitments)
            ..where((tbl) => tbl.id.equals(commitmentId)))
          .getSingleOrNull();
      if (existing == null) {
        throw StateError('Commitment not found: $commitmentId');
      }
      await (_db.update(_db.financialCommitments)
            ..where((tbl) => tbl.id.equals(commitmentId)))
          .write(
        FinancialCommitmentsCompanion(
          linkedAccountId: Value(trimmedAccId),
        ),
      );
      updated = _mapCommitmentRow(existing).copyWith(
        linkedAccountId: trimmedAccId,
      );
    });
    return updated;
  }

  @override
  Future<void> deleteCommitment(String commitmentId) async {
    await _db.transaction(() async {
      final row = await (_db.select(_db.financialCommitments)
            ..where((tbl) => tbl.id.equals(commitmentId)))
          .getSingleOrNull();
      if (row == null) return;

      final existingSettlements =
          await (_db.select(_db.commitmentSettlementsTable)
                ..where((tbl) => tbl.commitmentId.equals(commitmentId))
                ..limit(1))
              .get();
      if (existingSettlements.isNotEmpty || row.legacyPaidUnverified) {
        throw StateError(
          'Cannot delete a commitment with settlement history; '
          'void its settlements first.',
        );
      }

      await (_db.delete(_db.reminders)
            ..where((tbl) =>
                tbl.targetId.equals(commitmentId) &
                tbl.targetType.equals('commitment')))
          .go();
      await (_db.delete(_db.financialCommitments)
            ..where((tbl) => tbl.id.equals(commitmentId)))
          .go();
    });
  }

  @override
  Future<CommitmentSettlementModel> recordCommitmentSettlement({
    required String commitmentId,
    required String accountId,
    required int amountCents,
    String? categoryId,
    CalendarDate? settledDate,
    String? note,
  }) async {
    if (amountCents <= 0) {
      throw ArgumentError('Settlement amount must be greater than 0.');
    }
    late CommitmentSettlementModel createdSettlement;

    await _db.transaction(() async {
      await V6LedgerMigrator.ensureSystemControlAccounts(_db);
      await _assertEtbAccountsInTx([accountId]);

      final commitment = await (_db.select(_db.financialCommitments)
            ..where((tbl) => tbl.id.equals(commitmentId)))
          .getSingleOrNull();
      if (commitment == null) {
        throw StateError('Commitment not found: $commitmentId');
      }
      await _assertEtbCommitmentInTx(commitment);
      if (commitment.legacyPaidUnverified) {
        throw StateError(
          'Convert legacy unverified commitment to unpaid before recording '
          'new ledger settlements.',
        );
      }

      final currentSettled =
          await _verifiedCommitmentSettledCentsInTx(commitmentId);
      final remaining = commitment.amountCents - currentSettled;
      if (remaining <= 0) {
        throw DoubleEntryValidationError(
          'Commitment "${commitment.title}" is already fully settled.',
        );
      }
      if (amountCents > remaining) {
        throw DoubleEntryValidationError(
          'Settlement $amountCents exceeds remaining $remaining cents.',
        );
      }

      final effectiveDate = (settledDate ?? CalendarDate.today()).toIsoString();
      final effectiveCategoryId = categoryId ?? commitment.categoryId;
      final entryId = 'entry-commit-${_uuid.v4()}';
      final settlementId = 'cs-${_uuid.v4()}';
      final now = EthiopiaClock.nowUtc();

      var postedViaDebt = false;
      if (commitment.linkedDebtId != null) {
        final debtRow = await (_db.select(_db.debtsTable)
              ..where((tbl) => tbl.id.equals(commitment.linkedDebtId!)))
            .getSingleOrNull();
        if (debtRow != null) {
          final debtModel = _mapDebtRow(debtRow);
          if (debtModel.status == DebtStatus.active &&
              debtModel.outstandingCents > 0) {
            postedViaDebt = true;
            final principalPart = min(amountCents, debtModel.outstandingCents);
            final excessCents = max(0, amountCents - principalPart);
            final debtControlId = debtModel.debtType == DebtType.payable
                ? SystemControlAccounts.payable
                : SystemControlAccounts.receivable;
            final built = DoubleEntryEngine.buildDebtSettlement(
              settlementEntryId: entryId,
              debt: debtModel,
              settlementAssetAccountId: accountId,
              debtAccountId: debtControlId,
              allocatedPrincipalCents: principalPart,
              interestCents: excessCents,
              interestAccountId: excessCents > 0
                  ? (debtModel.debtType == DebtType.payable
                      ? SystemControlAccounts.expense
                      : SystemControlAccounts.income)
                  : null,
              settlementDate: effectiveDate,
              description: 'Commitment Settled: ${commitment.title}',
            );
            final entry = built['entry'] as JournalEntryModel;
            final postings = built['postings'] as List<PostingModel>;
            final allocation = built['allocation'] as SettlementAllocationModel;
            final updatedDebt = built['updatedDebt'] as DebtModel;

            await _insertEntryAndPostingsInTx(entry, postings);
            await _db.into(_db.settlementAllocationsTable).insert(
                  SettlementAllocationsTableCompanion.insert(
                    id: allocation.id,
                    settlementEntryId: allocation.settlementEntryId,
                    debtId: allocation.debtId,
                    allocatedCents: allocation.allocatedCents,
                    settlementDate: allocation.settlementDate,
                  ),
                );
            await (_db.update(_db.debtsTable)
                  ..where((tbl) => tbl.id.equals(updatedDebt.id)))
                .write(
              DebtsTableCompanion(
                outstandingCents: Value(updatedDebt.outstandingCents),
                status: Value(updatedDebt.status.dbValue),
              ),
            );
          }
        }
      }

      if (!postedViaDebt) {
        final built = commitment.direction == 'inflow'
            ? DoubleEntryEngine.buildCommitmentReceipt(
                entryId: entryId,
                destAccountId: accountId,
                categoryId: effectiveCategoryId,
                amountCents: amountCents,
                date: effectiveDate,
                commitmentTitle: commitment.title,
                note: note?.trim(),
              )
            : DoubleEntryEngine.buildCommitmentPayment(
                entryId: entryId,
                paidAccountId: accountId,
                categoryId: effectiveCategoryId,
                amountCents: amountCents,
                date: effectiveDate,
                commitmentTitle: commitment.title,
                note: note?.trim(),
              );
        await _insertEntryAndPostingsInTx(
          built['entry'] as JournalEntryModel,
          built['postings'] as List<PostingModel>,
        );
      }

      await _db.into(_db.commitmentSettlementsTable).insert(
            CommitmentSettlementsTableCompanion.insert(
              id: settlementId,
              commitmentId: commitmentId,
              entryId: entryId,
              amountCents: amountCents,
              settledDate: effectiveDate,
              createdAt: now,
            ),
          );

      final nextVerified = currentSettled + amountCents;
      final nextIsPaid = nextVerified >= commitment.amountCents;

      await (_db.update(_db.financialCommitments)
            ..where((tbl) => tbl.id.equals(commitmentId)))
          .write(
        FinancialCommitmentsCompanion(
          isPaid: Value(nextIsPaid),
          legacyPaidUnverified: const Value(false),
          linkedAccountId: Value(accountId),
          categoryId: Value(effectiveCategoryId),
          settlementEntryId: Value(entryId),
        ),
      );

      createdSettlement = CommitmentSettlementModel(
        id: settlementId,
        commitmentId: commitmentId,
        entryId: entryId,
        amountCents: amountCents,
        settledDate:
            SharedDateFormatter.parseFlexibleToCalendarDate(effectiveDate),
        createdAt: now,
      );
    });

    return createdSettlement;
  }

  @override
  Future<void> voidCommitmentSettlement({
    required String settlementId,
    required String reason,
  }) async {
    await _db.transaction(() async {
      final row = await (_db.select(_db.commitmentSettlementsTable)
            ..where((tbl) => tbl.id.equals(settlementId)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('Commitment settlement not found: $settlementId');
      }
      await _voidEntryInternalInTx(row.entryId, reason);
    });
  }

  @override
  Future<CommitmentModel> markLegacyCommitmentUnpaid(
    String commitmentId,
  ) async {
    late CommitmentModel updated;
    await _db.transaction(() async {
      final row = await (_db.select(_db.financialCommitments)
            ..where((tbl) => tbl.id.equals(commitmentId)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('Commitment not found: $commitmentId');
      }
      final verified = await _verifiedCommitmentSettledCentsInTx(commitmentId);
      if (verified > 0) {
        throw StateError(
          'Commitment has verified ledger settlements; void them individually.',
        );
      }
      await (_db.update(_db.financialCommitments)
            ..where((tbl) => tbl.id.equals(commitmentId)))
          .write(
        const FinancialCommitmentsCompanion(
          isPaid: Value(false),
          legacyPaidUnverified: Value(false),
          settlementEntryId: Value(null),
        ),
      );
      final refreshed = await (_db.select(_db.financialCommitments)
            ..where((tbl) => tbl.id.equals(commitmentId)))
          .getSingle();
      updated = _mapCommitmentRow(refreshed, verifiedSettledCents: 0);
    });
    return updated;
  }

  @override
  Future<CommitmentModel> markCommitmentPaidWithPosting({
    required String commitmentId,
    required String accountId,
    String? categoryId,
    CalendarDate? paidDate,
    String? note,
  }) async {
    late CommitmentModel result;

    await _db.transaction(() async {
      final row = await (_db.select(_db.financialCommitments)
            ..where((tbl) => tbl.id.equals(commitmentId)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('Commitment not found: $commitmentId');
      }
      final currentSettled =
          await _verifiedCommitmentSettledCentsInTx(commitmentId);
      if (row.isPaid &&
          !row.legacyPaidUnverified &&
          currentSettled >= row.amountCents) {
        result = _mapCommitmentRow(row, verifiedSettledCents: currentSettled);
        return;
      }

      if (row.legacyPaidUnverified) {
        await (_db.update(_db.financialCommitments)
              ..where((tbl) => tbl.id.equals(commitmentId)))
            .write(
          const FinancialCommitmentsCompanion(
            isPaid: Value(false),
            legacyPaidUnverified: Value(false),
          ),
        );
      }

      final remaining = max(1, row.amountCents - currentSettled);
      await recordCommitmentSettlement(
        commitmentId: commitmentId,
        accountId: accountId,
        amountCents: remaining,
        categoryId: categoryId,
        settledDate: paidDate,
        note: note,
      );

      final refreshed = await (_db.select(_db.financialCommitments)
            ..where((tbl) => tbl.id.equals(commitmentId)))
          .getSingle();
      final totalSettled =
          await _verifiedCommitmentSettledCentsInTx(commitmentId);
      result = _mapCommitmentRow(
        refreshed,
        verifiedSettledCents: totalSettled,
      );
    });

    return result;
  }

  @override
  Future<void> markCommitmentPaid(
    String commitmentId, {
    bool createExpenseTransaction = false,
  }) async {
    if (!createExpenseTransaction) {
      throw UnsupportedError(
        'Non-ledger paid flags are disabled in Schema v7; use '
        'recordCommitmentSettlement or markCommitmentPaidWithPosting.',
      );
    }

    await _db.transaction(() async {
      final commitment = await (_db.select(_db.financialCommitments)
            ..where((tbl) => tbl.id.equals(commitmentId)))
          .getSingleOrNull();
      if (commitment == null) return;

      var accountId = commitment.linkedAccountId;
      if (accountId == null) {
        final activeAssets = await (_db.select(_db.accountsTable)
              ..where((tbl) =>
                  tbl.isSystem.equals(false) &
                  tbl.isArchived.equals(false) &
                  tbl.type.equals('asset')))
            .get();
        final etbAssets = activeAssets.where(
          (a) => DoubleEntryEngine.isEtb(a.currencyCode),
        );
        if (etbAssets.isEmpty) {
          throw StateError(
            'No active ETB asset account available for commitment settlement.',
          );
        }
        accountId = etbAssets.first.id;
      }

      var categoryId = commitment.categoryId;
      if (categoryId == null) {
        final targetType =
            commitment.direction == 'inflow' ? 'income' : 'expense';
        final defaultCat = await (_db.select(_db.financialCategories)
              ..where((tbl) => tbl.type.equals(targetType))
              ..limit(1))
            .getSingleOrNull();
        categoryId = defaultCat?.id;
      }

      await markCommitmentPaidWithPosting(
        commitmentId: commitmentId,
        accountId: accountId,
        categoryId: categoryId,
        paidDate: CalendarDate.today(),
      );
    });
  }

  @override
  Future<List<SavingsGoalModel>> getSavingsGoals({
    bool includeArchived = false,
  }) async {
    final query = _db.select(_db.savingsGoals);
    if (!includeArchived) {
      query.where((tbl) => tbl.status.isNotValue('archived'));
    }
    final rows = await query.get();
    return rows.map(_mapSavingsGoalRow).toList();
  }

  @override
  Future<SavingsGoalModel> createSavingsGoal(SavingsGoalModel goal) async {
    late SavingsGoalModel saved;
    await _db.transaction(() async {
      final vaultId = goal.linkedAccountId?.trim();
      final effectiveVaultId =
          (vaultId != null && vaultId.isNotEmpty) ? vaultId : null;
      if (effectiveVaultId != null) {
        await _assertEtbVaultAccountInTx(effectiveVaultId);
      }
      final targetCents = goal.targetCents.abs();
      final allocated = goal.currentAllocatedCents.abs();
      final initialStatus = goal.status == SavingsGoalStatus.archived
          ? 'archived'
          : ((targetCents > 0 && allocated >= targetCents)
              ? 'completed'
              : 'active');
      await _db.into(_db.savingsGoals).insertOnConflictUpdate(
            SavingsGoalsCompanion.insert(
              id: goal.id,
              title: goal.title.trim(),
              targetCents: targetCents,
              currentAllocatedCents: Value(allocated),
              targetDate: Value(goal.targetDate?.toIsoString()),
              linkedAccountId: Value(effectiveVaultId),
              status: Value(initialStatus),
              createdAt: EthiopiaClock.nowUtc(),
            ),
          );
      await _syncVaultGoalsInTx();
      final row = await (_db.select(_db.savingsGoals)
            ..where((tbl) => tbl.id.equals(goal.id)))
          .getSingle();
      saved = _mapSavingsGoalRow(row);
    });
    return saved;
  }

  @override
  Future<SavingsGoalModel> updateSavingsGoal(SavingsGoalModel goal) async {
    late SavingsGoalModel updated;
    await _db.transaction(() async {
      final existing = await (_db.select(_db.savingsGoals)
            ..where((tbl) => tbl.id.equals(goal.id)))
          .getSingleOrNull();
      final vaultId = goal.linkedAccountId?.trim();
      final effectiveVaultId =
          (vaultId != null && vaultId.isNotEmpty) ? vaultId : null;
      if (existing != null &&
          existing.linkedAccountId != null &&
          effectiveVaultId == null &&
          existing.currentAllocatedCents > 0) {
        throw StateError(
          'Withdraw vault balance to 0 before unlinking this savings goal.',
        );
      }
      if (effectiveVaultId != null) {
        await _assertEtbVaultAccountInTx(effectiveVaultId);
      }
      if (goal.status == SavingsGoalStatus.archived &&
          existing?.status != 'archived' &&
          effectiveVaultId != null) {
        await _syncVaultGoalsInTx();
        final accounts =
            await getAccounts(includeArchived: true, includeSystem: true);
        AccountModel? vaultAcc;
        for (final a in accounts) {
          if (a.id == effectiveVaultId) {
            vaultAcc = a;
            break;
          }
        }
        if (vaultAcc != null) {
          final vaultPostings = await getPostings(accountId: effectiveVaultId);
          final allEntries = await getJournalEntries(includeVoided: true);
          final liveBalance = DoubleEntryEngine.calculateAccountBalance(
            account: vaultAcc,
            postings: vaultPostings,
            entries: allEntries,
          );
          if (liveBalance > 0) {
            throw DoubleEntryValidationError(
              'Withdraw vault funds back to a liquid account before archiving.',
            );
          }
        }
      }
      final targetCents = goal.targetCents.abs();
      final allocated = goal.currentAllocatedCents.abs();
      final nextStatus = goal.status == SavingsGoalStatus.archived ||
              existing?.status == 'archived'
          ? goal.status.name
          : ((targetCents > 0 && allocated >= targetCents)
              ? 'completed'
              : 'active');
      await (_db.update(_db.savingsGoals)
            ..where((tbl) => tbl.id.equals(goal.id)))
          .write(
        SavingsGoalsCompanion(
          title: Value(goal.title.trim()),
          targetCents: Value(targetCents),
          currentAllocatedCents: Value(allocated),
          targetDate: Value(goal.targetDate?.toIsoString()),
          linkedAccountId: Value(effectiveVaultId),
          status: Value(nextStatus),
        ),
      );
      await _syncVaultGoalsInTx();
      final row = await (_db.select(_db.savingsGoals)
            ..where((tbl) => tbl.id.equals(goal.id)))
          .getSingle();
      updated = _mapSavingsGoalRow(row);
    });
    return updated;
  }

  @override
  Future<void> deleteSavingsGoal(String goalId) async {
    final row = await (_db.select(_db.savingsGoals)
          ..where((tbl) => tbl.id.equals(goalId)))
        .getSingleOrNull();
    if (row == null) return;
    if (row.linkedAccountId != null || row.currentAllocatedCents > 0) {
      throw StateError(
        'Cannot delete a funded or vault-linked savings goal; withdraw and '
        'release to archive instead.',
      );
    }
    await (_db.delete(_db.savingsGoals)..where((tbl) => tbl.id.equals(goalId)))
        .go();
  }

  @override
  Future<SavingsGoalModel> releaseAndArchiveSavingsGoal(String goalId) async {
    late SavingsGoalModel result;
    await _db.transaction(() async {
      await _syncVaultGoalsInTx();
      final row = await (_db.select(_db.savingsGoals)
            ..where((tbl) => tbl.id.equals(goalId)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('Savings goal not found: $goalId');
      }
      if (row.linkedAccountId != null && row.currentAllocatedCents > 0) {
        throw StateError(
          'Withdraw vault funds back to a liquid account before archiving.',
        );
      }
      await (_db.update(_db.savingsGoals)
            ..where((tbl) => tbl.id.equals(goalId)))
          .write(
        const SavingsGoalsCompanion(
          currentAllocatedCents: Value(0),
          status: Value('archived'),
        ),
      );
      result = _mapSavingsGoalRow(row).copyWith(
        currentAllocatedCents: 0,
        status: SavingsGoalStatus.archived,
      );
    });
    return result;
  }

  @override
  Future<void> updateSavingsAllocation(
    String goalId,
    int newAllocatedCents,
  ) async {
    await (_db.update(_db.savingsGoals)..where((tbl) => tbl.id.equals(goalId)))
        .write(
      SavingsGoalsCompanion(
        currentAllocatedCents: Value(newAllocatedCents.abs()),
      ),
    );
  }

  @override
  Future<SavingsGoalModel> fundSavingsGoal({
    required String goalId,
    required int deltaCents,
    String? sourceAccountId,
    CalendarDate? date,
    String? note,
  }) async {
    late SavingsGoalModel result;

    await _db.transaction(() async {
      final row = await (_db.select(_db.savingsGoals)
            ..where((tbl) => tbl.id.equals(goalId)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('Savings goal not found: $goalId');
      }
      if (row.status == 'archived') {
        throw StateError('Cannot fund or withdraw from an archived goal.');
      }

      if (deltaCents == 0) {
        result = _mapSavingsGoalRow(row);
        return;
      }

      final linkedVaultId = row.linkedAccountId?.trim();
      final isVault = linkedVaultId != null && linkedVaultId.isNotEmpty;

      if (isVault) {
        if (sourceAccountId == null || sourceAccountId.trim().isEmpty) {
          throw ArgumentError(
            'sourceAccountId is required to transfer funds for a vault-linked '
            'goal.',
          );
        }
        if (sourceAccountId == linkedVaultId) {
          throw ArgumentError(
            'Source account and vault account must be distinct.',
          );
        }

        await V6LedgerMigrator.ensureSystemControlAccounts(_db);
        await _assertEtbAccountsInTx([sourceAccountId]);
        await _assertEtbVaultAccountInTx(linkedVaultId);

        final liquidAccRow = await (_db.select(_db.accountsTable)
              ..where((tbl) => tbl.id.equals(sourceAccountId)))
            .getSingle();
        final liquidAcc = _mapAccountRow(liquidAccRow);
        if (liquidAcc.type != AccountType.asset ||
            !liquidAcc.subType.isLiquid) {
          throw DoubleEntryValidationError(
            'Vault transfers must use an active Verified ETB liquid asset '
            'account (Cash, Bank, or Mobile Money).',
          );
        }

        final vaultAccRow = await (_db.select(_db.accountsTable)
              ..where((tbl) => tbl.id.equals(linkedVaultId)))
            .getSingle();
        final vaultAcc = _mapAccountRow(vaultAccRow);
        final vaultPostingsBefore = await getPostings(accountId: linkedVaultId);
        final entriesBefore = await getJournalEntries(includeVoided: true);
        final vaultBalanceBefore = max(
          0,
          DoubleEntryEngine.calculateAccountBalance(
            account: vaultAcc,
            postings: vaultPostingsBefore,
            entries: entriesBefore,
          ),
        );

        if (deltaCents < 0 && deltaCents.abs() > vaultBalanceBefore) {
          throw DoubleEntryValidationError(
            'Cannot withdraw ${deltaCents.abs()} cents from vault '
            '"${vaultAcc.name}": available balance is $vaultBalanceBefore cents.',
          );
        }

        final entryId = 'entry-sav-${_uuid.v4()}';
        final dateIso = (date ?? CalendarDate.today()).toIsoString();
        final built = deltaCents > 0
            ? DoubleEntryEngine.buildVaultTransfer(
                entryId: entryId,
                fromAccountId: sourceAccountId,
                vaultAccountId: linkedVaultId,
                amountCents: deltaCents,
                date: dateIso,
                goalTitle: row.title,
                note: note?.trim(),
              )
            : DoubleEntryEngine.buildTransfer(
                entryId: entryId,
                fromAssetAccountId: linkedVaultId,
                toAssetAccountId: sourceAccountId,
                amountCents: deltaCents.abs(),
                date: dateIso,
                description: 'Savings Withdrawal: ${row.title}',
                note: note?.trim(),
              );

        await _insertEntryAndPostingsInTx(
          built['entry'] as JournalEntryModel,
          built['postings'] as List<PostingModel>,
        );
        await _syncVaultGoalsInTx();

        final updatedRow = await (_db.select(_db.savingsGoals)
              ..where((tbl) => tbl.id.equals(goalId)))
            .getSingle();
        result = _mapSavingsGoalRow(updatedRow);
      } else {
        if (deltaCents < 0 && deltaCents.abs() > row.currentAllocatedCents) {
          throw DoubleEntryValidationError(
            'Cannot release more than the currently allocated reserve '
            '(${row.currentAllocatedCents} cents).',
          );
        }
        final nextAllocated = max(0, row.currentAllocatedCents + deltaCents);
        final nextStatus =
            (row.targetCents > 0 && nextAllocated >= row.targetCents)
                ? 'completed'
                : 'active';
        await (_db.update(_db.savingsGoals)
              ..where((tbl) => tbl.id.equals(goalId)))
            .write(
          SavingsGoalsCompanion(
            currentAllocatedCents: Value(nextAllocated),
            status: Value(nextStatus),
          ),
        );
        result = _mapSavingsGoalRow(row).copyWith(
          currentAllocatedCents: nextAllocated,
          status: nextStatus == 'completed'
              ? SavingsGoalStatus.completed
              : SavingsGoalStatus.active,
        );
      }
    });

    return result;
  }

  // ==========================================================================
  // IBudgetRepositoryContract
  // ==========================================================================

  @override
  Future<List<BudgetModel>> getBudgets({String? monthIso}) async {
    final query = _db.select(_db.budgetsTable);
    if (monthIso != null && monthIso.trim().isNotEmpty) {
      query.where((tbl) => tbl.monthIso.equals(monthIso.trim()));
    }
    query.orderBy([
      (tbl) => OrderingTerm.desc(tbl.monthIso),
      (tbl) => OrderingTerm.asc(tbl.categoryId),
    ]);
    final rows = await query.get();
    return rows.map(_mapBudgetRow).toList();
  }

  @override
  Future<BudgetModel> upsertBudget(BudgetModel budget) async {
    if (budget.limitCents <= 0) {
      throw ArgumentError('Budget limit must be strictly greater than 0.');
    }
    final now = EthiopiaClock.nowUtc();
    late BudgetModel result;

    await _db.transaction(() async {
      final existing = await (_db.select(_db.budgetsTable)
            ..where((tbl) =>
                tbl.id.equals(budget.id) |
                (tbl.monthIso.equals(budget.monthIso) &
                    tbl.categoryId.equals(budget.categoryId)))
            ..limit(1))
          .getSingleOrNull();

      if (existing != null) {
        await (_db.update(_db.budgetsTable)
              ..where((tbl) => tbl.id.equals(existing.id)))
            .write(
          BudgetsTableCompanion(
            categoryId: Value(budget.categoryId),
            monthIso: Value(budget.monthIso),
            limitCents: Value(budget.limitCents),
            rolloverEnabled: Value(budget.rolloverEnabled),
            updatedAt: Value(now),
          ),
        );
        result = BudgetModel(
          id: existing.id,
          categoryId: budget.categoryId,
          monthIso: budget.monthIso,
          limitCents: budget.limitCents,
          rolloverEnabled: budget.rolloverEnabled,
          createdAt: existing.createdAt,
          updatedAt: now,
        );
      } else {
        await _db.into(_db.budgetsTable).insert(
              BudgetsTableCompanion.insert(
                id: budget.id,
                categoryId: budget.categoryId,
                monthIso: budget.monthIso,
                limitCents: budget.limitCents,
                rolloverEnabled: Value(budget.rolloverEnabled),
                createdAt: budget.createdAt,
                updatedAt: now,
              ),
            );
        result = budget.copyWith(updatedAt: now);
      }
    });

    return result;
  }

  @override
  Future<void> deleteBudget(String budgetId) async {
    await (_db.delete(_db.budgetsTable)
          ..where((tbl) => tbl.id.equals(budgetId)))
        .go();
  }

  // ==========================================================================
  // IRecurringRuleRepositoryContract
  // ==========================================================================

  @override
  Future<List<RecurringRuleModel>> getRecurringRules({
    bool activeOnly = false,
  }) async {
    final query = _db.select(_db.recurringRulesTable);
    if (activeOnly) {
      query.where((tbl) => tbl.isActive.equals(true));
    }
    query.orderBy([(tbl) => OrderingTerm.asc(tbl.nextOccurrenceDate)]);
    final rows = await query.get();
    return rows.map(_mapRecurringRuleRow).toList();
  }

  @override
  Future<RecurringRuleModel> upsertRecurringRule(
    RecurringRuleModel rule,
  ) async {
    if (rule.amountCents <= 0) {
      throw ArgumentError('Recurring amount must be strictly greater than 0.');
    }
    if (rule.interval < 1) {
      throw ArgumentError('Recurring interval must be at least 1.');
    }
    final accId = rule.accountId?.trim();
    final destId = rule.destinationAccountId?.trim();
    final debtId = rule.linkedDebtId?.trim();

    if (rule.ruleType != RecurringRuleType.commitment &&
        (accId == null || accId.isEmpty)) {
      throw DoubleEntryValidationError(
        'Recurring ${rule.ruleType.name} rule must specify an active Verified ETB account.',
      );
    }
    if (rule.ruleType == RecurringRuleType.transfer) {
      if (destId == null || destId.isEmpty) {
        throw DoubleEntryValidationError(
          'Recurring transfer rule must specify a destination ETB account.',
        );
      }
      if (accId == destId) {
        throw DoubleEntryValidationError(
          'Recurring transfer source and destination accounts must be distinct.',
        );
      }
    }

    await _db.transaction(() async {
      final accCheck = <String>[
        if (accId != null && accId.isNotEmpty) accId,
        if (destId != null && destId.isNotEmpty) destId,
      ];
      if (accCheck.isNotEmpty) {
        await _assertEtbAccountsInTx(accCheck);
      }
      if (debtId != null && debtId.isNotEmpty) {
        await _assertEtbDebtInTx(debtId);
      }
      await _db.into(_db.recurringRulesTable).insertOnConflictUpdate(
            RecurringRulesTableCompanion.insert(
              id: rule.id,
              title: rule.title.trim(),
              ruleType: rule.ruleType.name,
              amountCents: rule.amountCents,
              frequency: rule.frequency.name,
              interval: Value(rule.interval),
              startDate: rule.startDate.toIsoString(),
              nextOccurrenceDate: rule.nextOccurrenceDate.toIsoString(),
              endDate: Value(rule.endDate?.toIsoString()),
              accountId: Value(
                (accId != null && accId.isNotEmpty) ? accId : null,
              ),
              destinationAccountId: Value(
                (destId != null && destId.isNotEmpty) ? destId : null,
              ),
              categoryId: Value(rule.categoryId),
              linkedDebtId: Value(
                (debtId != null && debtId.isNotEmpty) ? debtId : null,
              ),
              isActive: Value(rule.isActive),
              autoPost: Value(rule.autoPost),
              createdAt: rule.createdAt,
            ),
          );
    });
    return rule;
  }

  @override
  Future<RecurringRuleModel> pauseRecurringRule(String ruleId) async {
    final row = await (_db.select(_db.recurringRulesTable)
          ..where((tbl) => tbl.id.equals(ruleId)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Recurring rule not found: $ruleId');
    }
    await (_db.update(_db.recurringRulesTable)
          ..where((tbl) => tbl.id.equals(ruleId)))
        .write(const RecurringRulesTableCompanion(isActive: Value(false)));
    return _mapRecurringRuleRow(row).copyWith(isActive: false);
  }

  @override
  Future<RecurringRuleModel> resumeRecurringRule(
    String ruleId, {
    CalendarDate? today,
  }) async {
    late RecurringRuleModel updated;
    await _db.transaction(() async {
      final row = await (_db.select(_db.recurringRulesTable)
            ..where((tbl) => tbl.id.equals(ruleId)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('Recurring rule not found: $ruleId');
      }
      final mapped = _mapRecurringRuleRow(row);
      final effectiveToday = today ?? CalendarDate.today();
      final nextDate = RecurringEngine.advanceNextOnOrAfter(
        nextOccurrenceDate: mapped.nextOccurrenceDate,
        frequency: mapped.frequency,
        interval: mapped.interval,
        today: effectiveToday,
      );
      final expired = mapped.endDate != null && nextDate > mapped.endDate!;
      await (_db.update(_db.recurringRulesTable)
            ..where((tbl) => tbl.id.equals(ruleId)))
          .write(
        RecurringRulesTableCompanion(
          nextOccurrenceDate: Value(nextDate.toIsoString()),
          isActive: Value(!expired),
        ),
      );
      updated = mapped.copyWith(
        nextOccurrenceDate: nextDate,
        isActive: !expired,
      );
    });
    return updated;
  }

  @override
  Future<RecurringRuleModel> skipNextOccurrence(String ruleId) async {
    late RecurringRuleModel updated;
    await _db.transaction(() async {
      final row = await (_db.select(_db.recurringRulesTable)
            ..where((tbl) => tbl.id.equals(ruleId)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('Recurring rule not found: $ruleId');
      }
      final mapped = _mapRecurringRuleRow(row);
      updated = RecurringEngine.skipNext(rule: mapped);
      await (_db.update(_db.recurringRulesTable)
            ..where((tbl) => tbl.id.equals(ruleId)))
          .write(
        RecurringRulesTableCompanion(
          nextOccurrenceDate: Value(updated.nextOccurrenceDate.toIsoString()),
          isActive: Value(updated.isActive),
        ),
      );
    });
    return updated;
  }

  @override
  Future<void> deleteRecurringRule(String ruleId) async {
    await _db.transaction(() async {
      final hasCommitments = await (_db.select(_db.financialCommitments)
            ..where((tbl) => tbl.recurringRuleId.equals(ruleId))
            ..limit(1))
          .getSingleOrNull();
      final hasPostedEntries = await (_db.select(_db.journalEntriesTable)
            ..where((tbl) => tbl.legacySourceTxId.like('rec:$ruleId:%'))
            ..limit(1))
          .getSingleOrNull();
      if (hasCommitments != null || hasPostedEntries != null) {
        throw StateError(
          'Recurring rules with generated commitments or posted entries cannot '
          'be deleted; pause them instead.',
        );
      }
      await (_db.delete(_db.recurringRulesTable)
            ..where((tbl) => tbl.id.equals(ruleId)))
          .go();
    });
  }

  @override
  Future<int> processDueRecurringRules({required CalendarDate asOfDate}) async {
    var processedCount = 0;

    await _db.transaction(() async {
      await V6LedgerMigrator.ensureSystemControlAccounts(_db);
      final now = EthiopiaClock.nowUtc();
      final activeRows = await (_db.select(_db.recurringRulesTable)
            ..where((tbl) => tbl.isActive.equals(true)))
          .get();

      for (final row in activeRows) {
        final rule = _mapRecurringRuleRow(row);
        final dueDates = RecurringEngine.collectDueOccurrences(
          rule: rule,
          asOfDate: asOfDate,
          maxInstancesPerRun: 24,
        );

        if (dueDates.isEmpty) {
          if (rule.endDate != null && rule.nextOccurrenceDate > rule.endDate!) {
            await (_db.update(_db.recurringRulesTable)
                  ..where((tbl) => tbl.id.equals(rule.id)))
                .write(
              const RecurringRulesTableCompanion(isActive: Value(false)),
            );
          }
          continue;
        }

        for (final occDate in dueDates) {
          final occIso = occDate.toIsoString();
          final recSourceKey = 'rec:${rule.id}:$occIso';

          var canAutoPost = rule.autoPost &&
              rule.ruleType != RecurringRuleType.commitment &&
              ((rule.ruleType == RecurringRuleType.transfer &&
                      rule.accountId != null &&
                      rule.destinationAccountId != null &&
                      rule.accountId != rule.destinationAccountId) ||
                  (rule.ruleType != RecurringRuleType.transfer &&
                      rule.accountId != null &&
                      rule.categoryId != null));

          if (canAutoPost) {
            var etbValidForAutoPost = true;
            try {
              final idsToCheck = <String>[
                if (rule.accountId != null) rule.accountId!,
                if (rule.destinationAccountId != null)
                  rule.destinationAccountId!,
              ];
              await _assertEtbAccountsInTx(idsToCheck);
              if (rule.linkedDebtId != null &&
                  rule.linkedDebtId!.trim().isNotEmpty) {
                await _assertEtbDebtInTx(rule.linkedDebtId!.trim());
              }
            } catch (_) {
              etbValidForAutoPost = false;
            }
            if (!etbValidForAutoPost) {
              await (_db.update(_db.recurringRulesTable)
                    ..where((tbl) => tbl.id.equals(rule.id)))
                  .write(const RecurringRulesTableCompanion(
                autoPost: Value(false),
              ));
              canAutoPost = false;
              continue;
            }
            final existingEntry = await (_db.select(_db.journalEntriesTable)
                  ..where((tbl) => tbl.legacySourceTxId.equals(recSourceKey))
                  ..limit(1))
                .getSingleOrNull();
            if (existingEntry == null) {
              final entryId = 'entry-rec-${_uuid.v4()}';
              late JournalEntryModel entry;
              late List<PostingModel> postings;

              if (rule.ruleType == RecurringRuleType.expense) {
                final built = DoubleEntryEngine.buildDirectExpense(
                  entryId: entryId,
                  paidAccountId: rule.accountId!,
                  categoryId: rule.categoryId!,
                  amountCents: rule.amountCents,
                  date: occIso,
                  description: rule.title,
                  note: 'Recurring ${rule.frequency.name}',
                );
                entry = (built['entry'] as JournalEntryModel)
                    .copyWith(legacySourceTxId: recSourceKey);
                postings = built['postings'] as List<PostingModel>;
              } else if (rule.ruleType == RecurringRuleType.income) {
                final built = DoubleEntryEngine.buildDirectIncome(
                  entryId: entryId,
                  destAccountId: rule.accountId!,
                  categoryId: rule.categoryId!,
                  amountCents: rule.amountCents,
                  date: occIso,
                  description: rule.title,
                  note: 'Recurring ${rule.frequency.name}',
                );
                entry = (built['entry'] as JournalEntryModel)
                    .copyWith(legacySourceTxId: recSourceKey);
                postings = built['postings'] as List<PostingModel>;
              } else {
                final built = DoubleEntryEngine.buildTransfer(
                  entryId: entryId,
                  fromAssetAccountId: rule.accountId!,
                  toAssetAccountId: rule.destinationAccountId!,
                  amountCents: rule.amountCents,
                  date: occIso,
                  description: rule.title,
                  note: 'Recurring ${rule.frequency.name}',
                );
                entry = (built['entry'] as JournalEntryModel)
                    .copyWith(legacySourceTxId: recSourceKey);
                postings = built['postings'] as List<PostingModel>;
              }

              DoubleEntryEngine.validateBalancedEntry(postings);
              await _insertEntryAndPostingsInTx(entry, postings);
              processedCount++;
            }
          } else {
            final commitmentId = 'com-rec-${rule.id}-$occIso';
            final existingCommitment =
                await (_db.select(_db.financialCommitments)
                      ..where((tbl) => tbl.id.equals(commitmentId))
                      ..limit(1))
                    .getSingleOrNull();
            if (existingCommitment == null) {
              final commitmentDirection =
                  rule.ruleType == RecurringRuleType.income
                      ? 'inflow'
                      : 'outflow';
              await _db.into(_db.financialCommitments).insert(
                    FinancialCommitmentsCompanion.insert(
                      id: commitmentId,
                      title: rule.title,
                      amountCents: rule.amountCents,
                      dueDate: occIso,
                      isPaid: const Value(false),
                      direction: Value(commitmentDirection),
                      recurringRule: Value(rule.frequency.name),
                      linkedAccountId: Value(rule.accountId),
                      categoryId: Value(rule.categoryId),
                      linkedDebtId: Value(rule.linkedDebtId),
                      recurringRuleId: Value(rule.id),
                      createdAt: now,
                    ),
                    mode: InsertMode.insertOrIgnore,
                  );
              processedCount++;
            }
          }
        }

        final nextDate = RecurringEngine.computeNextOccurrence(
          from: dueDates.last,
          frequency: rule.frequency,
          interval: rule.interval,
        );
        final stillActive = rule.endDate == null || nextDate <= rule.endDate!;

        await (_db.update(_db.recurringRulesTable)
              ..where((tbl) => tbl.id.equals(rule.id)))
            .write(
          RecurringRulesTableCompanion(
            nextOccurrenceDate: Value(nextDate.toIsoString()),
            isActive: Value(stillActive),
          ),
        );
      }
      if (processedCount > 0) {
        await _syncVaultGoalsInTx();
      }
    });

    return processedCount;
  }

  // ==========================================================================
  // Migration Diagnostics & Debt Control Audits (Stage 4.0.5)
  // ==========================================================================

  @override
  Future<MigrationDiagnosticReport?> getLatestMigrationReport() async {
    final row = await (_db.select(_db.appSettings)
          ..where((tbl) => tbl.key.equals(V7LedgerHardener.v7ReportKey)))
        .getSingleOrNull();
    if (row == null || row.value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(row.value);
      if (decoded is Map<String, dynamic>) {
        return MigrationDiagnosticReport.fromJson(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  @override
  Future<DebtControlAuditReport> auditDebtControlBalances() async {
    return V7LedgerHardener.computeDebtControlAudit(_db);
  }

  // ==========================================================================
  // Financial Snapshot (Authoritative Double-Entry Projection)
  // ==========================================================================

  @override
  Future<FinancialSnapshot> getFinancialSnapshot({
    required int openingBalanceCents,
    required CalendarDate periodStart,
    required CalendarDate periodEnd,
    required List<int> expectedFutureIncomeCents,
  }) async {
    final accounts = await getAccounts(
      includeArchived: true,
      includeSystem: true,
    );
    final entries = await getJournalEntries(includeVoided: true);
    final postings = await getPostings();
    final debts = await getDebts();
    final allocations = await getSettlementAllocations();
    final commitments = await getCommitments();
    final commitmentSettlements = await getCommitmentSettlements();
    final recurringRules = await getRecurringRules();
    final savingsGoals = await getSavingsGoals(includeArchived: true);

    final breakdown = DoubleEntryEngine.calculateAvailableToSpendBreakdown(
      accounts: accounts,
      postings: postings,
      entries: entries,
      debts: debts,
      allocations: allocations,
      commitments: commitments,
      commitmentSettlements: commitmentSettlements,
      recurringRules: recurringRules,
      savingsGoals: savingsGoals,
      periodEndIso: periodEnd.toIsoString(),
    );

    final cashflow = DoubleEntryEngine.calculatePeriodCashflowTotals(
      accounts: accounts,
      postings: postings,
      entries: entries,
      debts: debts,
      allocations: allocations,
      startDateIso: periodStart.toIsoString(),
      endDateIso: periodEnd.toIsoString(),
    );

    final expectedTotal =
        expectedFutureIncomeCents.fold<int>(0, (sum, val) => sum + val);

    return FinancialSnapshot(
      openingBalanceCents: openingBalanceCents,
      totalIncomeCents: cashflow.incomeCents,
      totalExpensesCents: cashflow.expenseCents,
      recordedBalanceCents:
          breakdown.liquidCashCents + breakdown.vaultSavingsCents,
      unpaidCommitmentsCents: breakdown.totalDueObligationsCents,
      savingsReservedCents: breakdown.virtualSavingsReservedCents,
      expectedFutureIncomeCents: expectedTotal,
      availableToSpendCents: breakdown.availableToSpendCents,
    );
  }

  // ==========================================================================
  // Private Helpers & Row Mappers
  // ==========================================================================

  Future<Map<String, EntryCurrencyClassification>>
      _classifyAllEntriesInTx() async {
    final accountRows = await _db.select(_db.accountsTable).get();
    final entryRows = await _db.select(_db.journalEntriesTable).get();
    final postingRows = await _db.select(_db.postingsTable).get();
    final debtRows = await _db.select(_db.debtsTable).get();
    final allocRows = await _db.select(_db.settlementAllocationsTable).get();

    return DoubleEntryEngine.classifyAllEntries(
      accounts: accountRows.map(_mapAccountRow).toList(),
      entries: entryRows.map(_mapJournalEntryRow).toList(),
      postings: postingRows
          .map(
            (r) => PostingModel(
              id: r.id,
              entryId: r.entryId,
              accountId: r.accountId,
              amountCents: r.amountCents,
              direction: r.direction == 'debit'
                  ? PostingDirection.debit
                  : PostingDirection.credit,
              accountMovementDate: r.accountMovementDate,
              categoryId: r.categoryId,
              note: r.note,
            ),
          )
          .toList(),
      debts: debtRows.map(_mapDebtRow).toList(),
      allocations: allocRows
          .map(
            (r) => SettlementAllocationModel(
              id: r.id,
              settlementEntryId: r.settlementEntryId,
              debtId: r.debtId,
              allocatedCents: r.allocatedCents,
              settlementDate: r.settlementDate,
            ),
          )
          .toList(),
    );
  }

  Future<void> _assertEtbDebtInTx(
    String debtId, {
    DebtModel? debtOverride,
  }) async {
    final row = debtOverride == null
        ? await (_db.select(_db.debtsTable)
              ..where((tbl) => tbl.id.equals(debtId)))
            .getSingleOrNull()
        : null;
    final debt = debtOverride ?? (row != null ? _mapDebtRow(row) : null);
    if (debt == null) {
      throw DoubleEntryValidationError('Referenced debt "$debtId" not found.');
    }
    final classifications = await _classifyAllEntriesInTx();
    final originClass = classifications[debt.originEntryId];
    if (originClass == null || !originClass.isEligibleEtb) {
      throw DoubleEntryValidationError(
        'Cannot settle, link, or write off a non-ETB or currency-review '
        'debt in first-release ETB mode.',
      );
    }
  }

  Future<void> _assertEtbCommitmentInTx(FinancialCommitment row) async {
    final accountRows = await _db.select(_db.accountsTable).get();
    final entryRows = await _db.select(_db.journalEntriesTable).get();
    final debtRows = await _db.select(_db.debtsTable).get();
    final ruleRows = await _db.select(_db.recurringRulesTable).get();
    final settleRows = await (_db.select(_db.commitmentSettlementsTable)
          ..where((tbl) => tbl.commitmentId.equals(row.id)))
        .get();
    final classifications = await _classifyAllEntriesInTx();

    final mappedCommitment = _mapCommitmentRow(row);
    final res = DoubleEntryEngine.resolveCommitmentCurrencyStatus(
      commitment: mappedCommitment,
      accountById: {
        for (final a in accountRows) a.id: _mapAccountRow(a),
      },
      debtById: {
        for (final d in debtRows) d.id: _mapDebtRow(d),
      },
      entryById: {
        for (final e in entryRows) e.id: _mapJournalEntryRow(e),
      },
      classificationsByEntryId: classifications,
      ruleById: {
        for (final r in ruleRows) r.id: _mapRecurringRuleRow(r),
      },
      settlementsByCommitmentId: {
        row.id: settleRows
            .map(
              (s) => CommitmentSettlementModel(
                id: s.id,
                commitmentId: s.commitmentId,
                entryId: s.entryId,
                amountCents: s.amountCents,
                settledDate: SharedDateFormatter.parseFlexibleToCalendarDate(
                  s.settledDate,
                ),
                createdAt: s.createdAt,
              ),
            )
            .toList(),
      },
    );

    if (res.status != CommitmentCurrencyStatus.eligibleEtb) {
      throw DoubleEntryValidationError(
        res.reason ??
            'Cannot settle a non-ETB or currency-review commitment in '
                'first-release ETB mode.',
      );
    }
  }

  Future<void> _assertEtbAccountsInTx(Iterable<String> accountIds) async {
    final uniqueIds = accountIds
        .where((id) => !SystemControlAccounts.isSystemControlId(id))
        .toSet();
    if (uniqueIds.isEmpty) return;

    final rows = await (_db.select(_db.accountsTable)
          ..where((tbl) => tbl.id.isIn(uniqueIds.toList())))
        .get();
    final byId = {for (final r in rows) r.id: r};

    for (final id in uniqueIds) {
      final r = byId[id];
      if (r == null) {
        throw DoubleEntryValidationError(
          'Account "$id" not found for ledger posting.',
        );
      }
      if (r.isArchived) {
        throw DoubleEntryValidationError(
          'Archived account "${r.name}" cannot receive new ledger postings.',
        );
      }
      if (!r.isSystem && !DoubleEntryEngine.isEtb(r.currencyCode)) {
        final tier = DoubleEntryEngine.classifyCurrencyCode(r.currencyCode);
        final codeLabel = tier == CurrencyValidationTier.verifiedNonEtb
            ? DoubleEntryEngine.normalizeCurrencyCode(r.currencyCode)
            : 'Unverified';
        throw DoubleEntryValidationError(
          'First-release reporting supports ETB writes only; account '
          '"${r.name}" ($codeLabel) cannot receive new ledger postings.',
        );
      }
    }
  }

  Future<void> _assertSpendableEtbAccountsInTx(
    Iterable<String> accountIds, {
    String roleLabel = 'Account',
  }) async {
    await _assertEtbAccountsInTx(accountIds);
    final uniqueIds = accountIds
        .where((id) => !SystemControlAccounts.isSystemControlId(id))
        .toSet();
    if (uniqueIds.isEmpty) return;

    final rows = await (_db.select(_db.accountsTable)
          ..where((tbl) => tbl.id.isIn(uniqueIds.toList())))
        .get();
    for (final r in rows) {
      if (r.isSystem) continue;
      final isSpendable = r.subType != AccountSubType.savingsVault.dbValue &&
          r.subType != AccountSubType.receivable.dbValue &&
          r.subType != AccountSubType.payable.dbValue &&
          (r.type == AccountType.asset.name ||
              (r.type == AccountType.liability.name &&
                  r.subType == AccountSubType.creditCard.dbValue));
      if (!isSpendable) {
        throw DoubleEntryValidationError(
          '$roleLabel "${r.name}" cannot be used for this transaction; select an active Verified ETB liquid or credit card account (Savings Vaults are allowed in Transfers only).',
        );
      }
    }
  }

  Future<void> _assertTransferEtbAccountsInTx(
    Iterable<String> accountIds,
  ) async {
    await _assertEtbAccountsInTx(accountIds);
    final uniqueIds = accountIds
        .where((id) => !SystemControlAccounts.isSystemControlId(id))
        .toSet();
    if (uniqueIds.isEmpty) return;

    final rows = await (_db.select(_db.accountsTable)
          ..where((tbl) => tbl.id.isIn(uniqueIds.toList())))
        .get();
    for (final r in rows) {
      if (r.isSystem) continue;
      final isTransferable = r.subType != AccountSubType.receivable.dbValue &&
          r.subType != AccountSubType.payable.dbValue &&
          (r.type == AccountType.asset.name ||
              (r.type == AccountType.liability.name &&
                  r.subType == AccountSubType.creditCard.dbValue));
      if (!isTransferable) {
        throw DoubleEntryValidationError(
          'Account "${r.name}" cannot participate in an ETB transfer.',
        );
      }
    }
  }

  Future<void> _assertEtbVaultAccountInTx(String accountId) async {
    await _assertEtbAccountsInTx([accountId]);
    final row = await (_db.select(_db.accountsTable)
          ..where((tbl) => tbl.id.equals(accountId)))
        .getSingleOrNull();
    if (row == null ||
        row.isSystem ||
        row.isArchived ||
        row.subType != AccountSubType.savingsVault.dbValue) {
      throw DoubleEntryValidationError(
        'Vault-linked savings goals must link to an active Verified ETB '
        'Savings Vault account.',
      );
    }
  }

  Future<void> _insertEntryAndPostingsInTx(
    JournalEntryModel entry,
    List<PostingModel> postings,
  ) async {
    if (!entry.isVoided) {
      if (postings
          .any((p) => p.accountId == SystemControlAccounts.legacyOffset)) {
        throw DoubleEntryValidationError(
          'New ledger postings cannot reference the legacy clearing offset account.',
        );
      }
      final nonSystemIds = postings
          .map((p) => p.accountId)
          .where((id) => !SystemControlAccounts.isSystemControlId(id))
          .toSet();
      if (nonSystemIds.isEmpty && entry.entryType != EntryType.writeOff) {
        throw DoubleEntryValidationError(
          'New ledger entries must involve at least one active ETB account.',
        );
      }
      await _assertEtbAccountsInTx(postings.map((p) => p.accountId));
    }

    await _db.into(_db.journalEntriesTable).insert(
          JournalEntriesTableCompanion.insert(
            id: entry.id,
            entryType: entry.entryType.dbValue,
            description: entry.description,
            occurrenceDate: entry.occurrenceDate,
            isVoided: Value(entry.isVoided),
            voidReason: Value(entry.voidReason),
            legacySourceTxId: Value(entry.legacySourceTxId),
            correctedFromEntryId: Value(entry.correctedFromEntryId),
            createdAt: entry.createdAt,
          ),
        );

    for (final p in postings) {
      await _db.into(_db.postingsTable).insert(
            PostingsTableCompanion.insert(
              id: p.id,
              entryId: p.entryId,
              accountId: p.accountId,
              amountCents: p.amountCents,
              direction: p.direction.name,
              accountMovementDate: p.accountMovementDate,
              categoryId: Value(p.categoryId),
              note: Value(p.note),
            ),
          );
    }
  }

  Future<void> _assertVaultZeroBalanceBeforeArchiveInTx(
    AccountsTableData row,
  ) async {
    final mapped = _mapAccountRow(row);
    if (!mapped.subType.isSavingsVault) return;
    final accountPostings = await getPostings(accountId: row.id);
    final entries = await getJournalEntries(includeVoided: true);
    final balanceCents = DoubleEntryEngine.calculateAccountBalance(
      account: mapped,
      postings: accountPostings,
      entries: entries,
    );
    if (balanceCents != 0) {
      throw DoubleEntryValidationError(
        'Cannot archive Savings Vault "${row.name}" while its balance is '
        'non-zero (${(balanceCents / 100).toStringAsFixed(2)} ETB). '
        'Withdraw remaining funds first.',
      );
    }
  }

  Future<void> _syncVaultGoalsInTx() async {
    final goals = await _db.select(_db.savingsGoals).get();
    final vaultGoals = goals
        .where(
          (g) =>
              g.status != 'archived' &&
              g.linkedAccountId != null &&
              g.linkedAccountId!.trim().isNotEmpty,
        )
        .toList();
    if (vaultGoals.isEmpty) return;

    final accounts =
        await getAccounts(includeArchived: true, includeSystem: true);
    final accountById = {for (final a in accounts) a.id: a};
    final postings = await getPostings();
    final entries = await getJournalEntries(includeVoided: true);

    for (final goal in vaultGoals) {
      final acc = accountById[goal.linkedAccountId!.trim()];
      if (acc == null) continue;
      final balance = max(
        0,
        DoubleEntryEngine.calculateAccountBalance(
          account: acc,
          postings: postings,
          entries: entries,
        ),
      );
      final nextStatus =
          (goal.targetCents > 0 && balance >= goal.targetCents)
              ? 'completed'
              : 'active';
      if (goal.currentAllocatedCents != balance || goal.status != nextStatus) {
        await (_db.update(_db.savingsGoals)
              ..where((tbl) => tbl.id.equals(goal.id)))
            .write(
          SavingsGoalsCompanion(
            currentAllocatedCents: Value(balance),
            status: Value(nextStatus),
          ),
        );
      }
    }
  }

  Future<void> _syncDualWriteSupersededInTx({
    required String entryId,
    String? legacySourceTxId,
    required bool isSuperseded,
  }) async {
    final candidateIds = <String>{
      entryId,
      if (entryId.startsWith('entry-tx-'))
        entryId.substring('entry-tx-'.length),
      if (entryId.startsWith('entry-')) entryId.substring('entry-'.length),
      if (legacySourceTxId != null && legacySourceTxId.trim().isNotEmpty)
        legacySourceTxId.trim(),
    }.toList();
    if (candidateIds.isEmpty) return;
    await (_db.update(_db.financialTransactions)
          ..where((tbl) => tbl.id.isIn(candidateIds)))
        .write(
      FinancialTransactionsCompanion(isSuperseded: Value(isSuperseded)),
    );
  }

  Future<JournalEntryModel> _voidEntryInternalInTx(
    String entryId,
    String voidReason,
  ) async {
    final targetRow = await (_db.select(_db.journalEntriesTable)
          ..where((tbl) => tbl.id.equals(entryId)))
        .getSingleOrNull();
    if (targetRow == null) {
      throw DoubleEntryValidationError('Journal entry "$entryId" not found.');
    }
    if (targetRow.isVoided) {
      return _mapJournalEntryRow(targetRow);
    }

    final allEntries = await _db.select(_db.journalEntriesTable).get();
    final voidedEntryIds = {
      for (final e in allEntries)
        if (e.isVoided) e.id,
    };

    // Guard 1: Debt-origin entries cannot be voided while active settlements or active write-off exist.
    final linkedOriginDebts = await (_db.select(_db.debtsTable)
          ..where((tbl) => tbl.originEntryId.equals(entryId)))
        .get();
    for (final debt in linkedOriginDebts) {
      final allocs = await (_db.select(_db.settlementAllocationsTable)
            ..where((tbl) => tbl.debtId.equals(debt.id)))
          .get();
      if (allocs.any((a) => !voidedEntryIds.contains(a.settlementEntryId))) {
        throw DoubleEntryValidationError(
          'Cannot void a debt-origin entry that has active settlements. '
          'Void the settlement entries first.',
        );
      }
      if (debt.writeOffEntryId != null &&
          !voidedEntryIds.contains(debt.writeOffEntryId!)) {
        throw DoubleEntryValidationError(
          'Cannot void a debt-origin entry with an active write-off. '
          'Void the write-off entry first.',
        );
      }
    }

    // Guard 2: Settlements cannot be voided while target debt has an active write-off.
    final targetAllocs = await (_db.select(_db.settlementAllocationsTable)
          ..where((tbl) => tbl.settlementEntryId.equals(entryId)))
        .get();
    for (final alloc in targetAllocs) {
      final debt = await (_db.select(_db.debtsTable)
            ..where((tbl) => tbl.id.equals(alloc.debtId)))
          .getSingleOrNull();
      if (debt?.writeOffEntryId != null &&
          !voidedEntryIds.contains(debt!.writeOffEntryId!)) {
        throw DoubleEntryValidationError(
          'Cannot void a settlement while its debt has an active write-off. '
          'Void the write-off first.',
        );
      }
    }

    // Guard 3: Standard expense cannot be voided while active refunds reference it.
    final hasActiveRefund = allEntries.any(
      (e) =>
          !e.isVoided &&
          DoubleEntryEngine.extractRefundOriginEntryId(
                _mapJournalEntryRow(e),
              ) ==
              entryId,
    );
    if (hasActiveRefund) {
      throw DoubleEntryValidationError(
        'Cannot void an expense entry that has active refunds. '
        'Void the refund entries first.',
      );
    }

    // Guard 4: Opening-balance entries must be revised via reviseOpeningBalance.
    if (targetRow.legacySourceTxId?.startsWith('open:') ?? false) {
      throw DoubleEntryValidationError(
        'Opening balance entries cannot be voided directly. '
        'Edit the account opening balance instead.',
      );
    }

    await (_db.update(_db.journalEntriesTable)
          ..where((tbl) => tbl.id.equals(entryId)))
        .write(
      JournalEntriesTableCompanion(
        isVoided: const Value(true),
        voidReason: Value(voidReason),
      ),
    );

    await _syncDualWriteSupersededInTx(
      entryId: targetRow.id,
      legacySourceTxId: targetRow.legacySourceTxId,
      isSuperseded: true,
    );
    await _syncCommitmentsForEntryInTx(entryId);
    await V7LedgerHardener.reconcileAllDebtsV7(_db);
    await _syncVaultGoalsInTx();

    final row = await (_db.select(_db.journalEntriesTable)
          ..where((tbl) => tbl.id.equals(entryId)))
        .getSingle();
    return _mapJournalEntryRow(row);
  }

  Future<void> _unvoidEntryInternalInTx(String entryId) async {
    final entryRow = await (_db.select(_db.journalEntriesTable)
          ..where((tbl) => tbl.id.equals(entryId)))
        .getSingleOrNull();
    if (entryRow == null) {
      throw DoubleEntryValidationError(
        'Journal entry "$entryId" not found.',
      );
    }

    final mappedTarget = _mapJournalEntryRow(entryRow);
    final entryPostings = await getPostings(entryId: entryId);
    if (entryPostings
        .any((p) => p.accountId == SystemControlAccounts.legacyOffset)) {
      throw DoubleEntryValidationError(
        'Legacy clearing offset entries cannot be restored in first-release ETB mode.',
      );
    }
    await _assertEtbAccountsInTx(entryPostings.map((p) => p.accountId));

    if (!entryRow.isVoided) {
      await _syncDualWriteSupersededInTx(
        entryId: entryRow.id,
        legacySourceTxId: entryRow.legacySourceTxId,
        isSuperseded: false,
      );
      return;
    }

    final allEntries = await _db.select(_db.journalEntriesTable).get();
    final voidedEntryIds = {
      for (final e in allEntries)
        if (e.isVoided) e.id,
    };

    // Guard: Do not restore an entry that already has an active replacement.
    final hasActiveReplacement = allEntries.any(
      (e) => !e.isVoided && e.correctedFromEntryId == entryId,
    );
    if (hasActiveReplacement) {
      throw DoubleEntryValidationError(
        'Cannot restore an entry that has an active replacement. '
        'Void the replacement entry first.',
      );
    }

    // Guard: Opening balance entries must use reviseOpeningBalance.
    if (entryRow.legacySourceTxId?.startsWith('open:') ?? false) {
      throw DoubleEntryValidationError(
        'Opening balance entries cannot be restored directly. '
        'Edit the account opening balance instead.',
      );
    }

    // Guard: Write-off entries cannot be unvoided directly.
    if (mappedTarget.entryType == EntryType.writeOff) {
      throw DoubleEntryValidationError(
        'Write-off entries cannot be restored directly. '
        'Record a new write-off from the debt record if needed.',
      );
    }

    // Guard: If settlement entry, verify target debt origin is active, not written off, and won't over-settle.
    final targetAllocs = await (_db.select(_db.settlementAllocationsTable)
          ..where((tbl) => tbl.settlementEntryId.equals(entryId)))
        .get();
    for (final alloc in targetAllocs) {
      final debt = await (_db.select(_db.debtsTable)
            ..where((tbl) => tbl.id.equals(alloc.debtId)))
          .getSingleOrNull();
      if (debt == null) {
        throw DoubleEntryValidationError(
          'Cannot restore settlement because its debt record no longer exists.',
        );
      }
      final originMatches = allEntries.where((e) => e.id == debt.originEntryId);
      final origin = originMatches.isEmpty ? null : originMatches.first;
      if (origin == null || origin.isVoided || debt.status == 'voided') {
        throw DoubleEntryValidationError(
          'Cannot restore settlement because the underlying debt origin is voided.',
        );
      }
      if (debt.writeOffEntryId != null &&
          !voidedEntryIds.contains(debt.writeOffEntryId!)) {
        throw DoubleEntryValidationError(
          'Cannot restore settlement while the debt has an active write-off.',
        );
      }
      final debtAllocs = await (_db.select(_db.settlementAllocationsTable)
            ..where((tbl) => tbl.debtId.equals(debt.id)))
          .get();
      final currentSettled = debtAllocs
          .where((a) => !voidedEntryIds.contains(a.settlementEntryId))
          .fold<int>(0, (sum, a) => sum + a.allocatedCents);
      if (currentSettled + alloc.allocatedCents > debt.principalCents) {
        throw DoubleEntryValidationError(
          'Cannot restore settlement because total settled principal would '
          'exceed the debt principal.',
        );
      }
    }

    // Guard: If refund entry, verify original expense is active and remaining refundable covers this refund.
    final refundOriginId =
        DoubleEntryEngine.extractRefundOriginEntryId(mappedTarget);
    if (refundOriginId != null) {
      final accounts =
          await getAccounts(includeArchived: true, includeSystem: true);
      final mappedEntries = allEntries.map(_mapJournalEntryRow).toList();
      final postings = await getPostings();
      final debts = await getDebts();
      final allocations = await getSettlementAllocations();
      final summary = DoubleEntryEngine.getExpenseRefundSummary(
        originalEntryId: refundOriginId,
        entries: mappedEntries,
        postings: postings,
        accounts: accounts,
        debts: debts,
        allocations: allocations,
      );
      if (!summary.eligible) {
        throw DoubleEntryValidationError(
          summary.reason ??
              'Cannot restore refund because the original expense is no longer active or eligible.',
        );
      }
      final accountById = {for (final a in accounts) a.id: a};
      final refundAmount = entryPostings
          .where(
            (p) =>
                p.direction == PostingDirection.credit &&
                (p.accountId == SystemControlAccounts.expense ||
                    accountById[p.accountId]?.type == AccountType.expense),
          )
          .fold<int>(0, (sum, p) => sum + p.amountCents);
      if (refundAmount > summary.remainingRefundableCents) {
        throw DoubleEntryValidationError(
          'Cannot restore refund because total refunded amount would exceed '
          'the original expense.',
        );
      }
    }

    // Guard 7: Commitment settlement cannot be restored if doing so would over-settle its commitment.
    final cmQuery = _db.select(_db.commitmentSettlementsTable)
      ..where((tbl) => tbl.entryId.equals(entryId));
    final targetCmSettlements = await cmQuery.get();
    for (final cs in targetCmSettlements) {
      final commitment = await (_db.select(_db.financialCommitments)
            ..where((tbl) => tbl.id.equals(cs.commitmentId)))
          .getSingleOrNull();
      if (commitment == null) continue;
      final currentSettled =
          await _verifiedCommitmentSettledCentsInTx(cs.commitmentId);
      if (currentSettled + cs.amountCents > commitment.amountCents) {
        throw DoubleEntryValidationError(
          'Cannot restore commitment settlement because total settled amount '
          'would exceed the commitment amount.',
        );
      }
    }

    await (_db.update(_db.journalEntriesTable)
          ..where((tbl) => tbl.id.equals(entryId)))
        .write(
      const JournalEntriesTableCompanion(
        isVoided: Value(false),
        voidReason: Value(null),
      ),
    );

    final classifications = await _classifyAllEntriesInTx();
    final cls = classifications[entryId];
    if (cls == null || !cls.isEligibleEtb) {
      throw DoubleEntryValidationError(
        cls?.reason ??
            'Restored journal entry must be verified ETB in first-release mode.',
      );
    }

    await _syncDualWriteSupersededInTx(
      entryId: entryRow.id,
      legacySourceTxId: entryRow.legacySourceTxId,
      isSuperseded: false,
    );

    // If a dual-written legacySourceTxId row was hard-deleted via deleteTransaction
    // and is now restored via unvoidJournalEntry, recreate the FinancialTransactions
    // mirror row so both stores remain consistent.
    final legacyId = entryRow.legacySourceTxId?.trim();
    if (legacyId != null &&
        legacyId.isNotEmpty &&
        !legacyId.startsWith('open:') &&
        (mappedTarget.entryType == EntryType.standard ||
            mappedTarget.entryType == EntryType.transfer) &&
        !DoubleEntryEngine.isRefundEntry(mappedTarget)) {
      final existingDualTx = await (_db.select(_db.financialTransactions)
            ..where((tbl) => tbl.id.equals(legacyId)))
          .getSingleOrNull();
      final linkedOriginDebt = await (_db.select(_db.debtsTable)
            ..where((tbl) => tbl.originEntryId.equals(entryId))
            ..limit(1))
          .getSingleOrNull();
      if (existingDualTx == null &&
          targetAllocs.isEmpty &&
          linkedOriginDebt == null) {
        final isTransfer = mappedTarget.entryType == EntryType.transfer;
        final isIncome = !isTransfer &&
            entryPostings.any(
              (p) =>
                  p.accountId == SystemControlAccounts.income &&
                  p.direction == PostingDirection.credit,
            );
        late String txType;
        late int txAmount;
        late String txCategoryId;
        String? txAccountId;
        String? txDestAccountId;
        String? txNote;
        String? txPayee;

        if (isTransfer) {
          txType = 'transfer';
          PostingModel? src;
          PostingModel? dst;
          PostingModel? fee;
          for (final p in entryPostings) {
            if (p.accountId == SystemControlAccounts.expense) {
              fee ??= p;
              continue;
            }
            if (p.direction == PostingDirection.credit &&
                !SystemControlAccounts.isSystemControlId(p.accountId)) {
              src ??= p;
            } else if (p.direction == PostingDirection.debit &&
                !SystemControlAccounts.isSystemControlId(p.accountId)) {
              dst ??= p;
            }
          }
          txAmount = dst?.amountCents ?? src?.amountCents ?? 0;
          txCategoryId = await _resolveTransferMirrorCategoryIdInTx(
            feeCategoryId: fee?.categoryId,
          );
          txAccountId = src?.accountId;
          txDestAccountId = dst?.accountId;
          txNote = dst?.note ?? src?.note;
        } else if (isIncome) {
          txType = 'income';
          PostingModel? drAcc;
          PostingModel? crInc;
          for (final p in entryPostings) {
            if (p.accountId == SystemControlAccounts.income &&
                p.direction == PostingDirection.credit) {
              crInc ??= p;
            } else if (p.direction == PostingDirection.debit &&
                !SystemControlAccounts.isSystemControlId(p.accountId)) {
              drAcc ??= p;
            }
          }
          txAmount = drAcc?.amountCents ?? crInc?.amountCents ?? 0;
          txCategoryId = crInc?.categoryId ??
              SystemControlAccounts.canonicalDefaultIncomeCategoryId;
          txAccountId = drAcc?.accountId;
          txNote = drAcc?.note ?? crInc?.note;
          final sepIdx = mappedTarget.description.indexOf(' — ');
          if (sepIdx > 0) {
            txPayee = mappedTarget.description.substring(0, sepIdx).trim();
          }
        } else {
          txType = 'expense';
          PostingModel? drExp;
          PostingModel? crAcc;
          for (final p in entryPostings) {
            if (p.accountId == SystemControlAccounts.expense &&
                p.direction == PostingDirection.debit) {
              drExp ??= p;
            } else if (p.direction == PostingDirection.credit &&
                !SystemControlAccounts.isSystemControlId(p.accountId)) {
              crAcc ??= p;
            }
          }
          txAmount = drExp?.amountCents ?? crAcc?.amountCents ?? 0;
          txCategoryId = drExp?.categoryId ??
              SystemControlAccounts.canonicalDefaultExpenseCategoryId;
          txAccountId = crAcc?.accountId;
          txNote = drExp?.note ?? crAcc?.note;
          final sepIdx = mappedTarget.description.indexOf(' — ');
          if (sepIdx > 0) {
            txPayee = mappedTarget.description.substring(0, sepIdx).trim();
          }
        }

        if (txAmount > 0 && txAccountId != null) {
          if (txType != 'transfer') {
            await _ensureCategoryExists(
              txCategoryId,
              DoubleEntryEngine.canonicalCategoryNameForSeed(txCategoryId),
              txType,
            );
          }
          await _db.into(_db.financialTransactions).insertOnConflictUpdate(
                FinancialTransactionsCompanion.insert(
                  id: legacyId,
                  categoryId: txCategoryId,
                  amountCents: txAmount.abs(),
                  type: txType,
                  transactionDate: mappedTarget.occurrenceDate,
                  note: Value(txNote?.trim()),
                  payee: Value(txPayee),
                  accountId: Value(txAccountId),
                  destinationAccountId: Value(txDestAccountId),
                  isSuperseded: const Value(false),
                  correctedFromId: const Value(null),
                  correctionReason: const Value(null),
                  createdAt: mappedTarget.createdAt,
                ),
              );
        }
      }
    }

    await _syncCommitmentsForEntryInTx(entryId);
    await V7LedgerHardener.reconcileAllDebtsV7(_db);
    await _syncVaultGoalsInTx();
  }

  Future<int> _verifiedCommitmentSettledCentsInTx(String commitmentId) async {
    final settlements = await (_db.select(_db.commitmentSettlementsTable)
          ..where((tbl) => tbl.commitmentId.equals(commitmentId)))
        .get();
    if (settlements.isEmpty) return 0;

    final entryIds = settlements.map((s) => s.entryId).toSet().toList();
    final entries = await (_db.select(_db.journalEntriesTable)
          ..where((tbl) => tbl.id.isIn(entryIds)))
        .get();
    final activeIds = {
      for (final e in entries)
        if (!e.isVoided) e.id,
    };
    return settlements
        .where((s) => activeIds.contains(s.entryId))
        .fold<int>(0, (sum, s) => sum + s.amountCents);
  }

  Future<void> _syncCommitmentsForEntryInTx(String entryId) async {
    final linkedSettlements = await (_db.select(_db.commitmentSettlementsTable)
          ..where((tbl) => tbl.entryId.equals(entryId)))
        .get();
    final legacyMatchedCommitments = await (_db.select(_db.financialCommitments)
          ..where((tbl) => tbl.settlementEntryId.equals(entryId)))
        .get();

    final touchedCommitmentIds = <String>{
      for (final s in linkedSettlements) s.commitmentId,
      for (final c in legacyMatchedCommitments) c.id,
    };

    for (final commitmentId in touchedCommitmentIds) {
      final commitment = await (_db.select(_db.financialCommitments)
            ..where((tbl) => tbl.id.equals(commitmentId)))
          .getSingleOrNull();
      if (commitment == null) continue;

      final allSettlements = await (_db.select(_db.commitmentSettlementsTable)
            ..where((tbl) => tbl.commitmentId.equals(commitmentId))
            ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
          .get();

      if (allSettlements.isEmpty) {
        await (_db.update(_db.financialCommitments)
              ..where((tbl) => tbl.id.equals(commitmentId)))
            .write(
          const FinancialCommitmentsCompanion(
            isPaid: Value(false),
            settlementEntryId: Value(null),
          ),
        );
        continue;
      }

      final entryRows = await (_db.select(_db.journalEntriesTable)
            ..where(
              (tbl) => tbl.id.isIn(
                allSettlements.map((s) => s.entryId).toSet().toList(),
              ),
            ))
          .get();
      final activeIds = {
        for (final e in entryRows)
          if (!e.isVoided) e.id,
      };
      final activeSettlements =
          allSettlements.where((s) => activeIds.contains(s.entryId)).toList();
      final verifiedTotal = activeSettlements.fold<int>(
        0,
        (sum, s) => sum + s.amountCents,
      );
      final latestActiveEntryId =
          activeSettlements.isEmpty ? null : activeSettlements.first.entryId;

      await (_db.update(_db.financialCommitments)
            ..where((tbl) => tbl.id.equals(commitmentId)))
          .write(
        FinancialCommitmentsCompanion(
          isPaid: Value(verifiedTotal >= commitment.amountCents),
          settlementEntryId: Value(latestActiveEntryId),
        ),
      );
    }
  }

  /// Immutable `:rev:{n}` opening-balance revision chain (never clears `legacySourceTxId`).
  Future<void> _syncOpeningBalanceEntryInTx(
    AccountModel account, {
    String reason = 'Updated opening balance',
  }) async {
    final openTag = 'open:${account.id}';
    final openRevPrefix = '$openTag:rev:%';

    final allHistory = await (_db.select(_db.journalEntriesTable)
          ..where((tbl) =>
              tbl.legacySourceTxId.equals(openTag) |
              tbl.legacySourceTxId.like(openRevPrefix))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .get();

    final activeExisting = allHistory.where((e) => !e.isVoided).toList();
    final primaryActive = activeExisting.isEmpty ? null : activeExisting.first;

    if (primaryActive != null) {
      final postings = await (_db.select(_db.postingsTable)
            ..where((tbl) => tbl.entryId.equals(primaryActive.id)))
          .get();
      final currentAccountBal = postings
          .where((p) => p.accountId == account.id)
          .fold<int>(0, (sum, p) {
        final isDebitNormal = account.type == AccountType.asset ||
            account.type == AccountType.expense;
        if (isDebitNormal) {
          return sum +
              (p.direction == 'debit' ? p.amountCents : -p.amountCents);
        }
        return sum + (p.direction == 'credit' ? p.amountCents : -p.amountCents);
      });

      if (currentAccountBal == account.openingBalanceCents &&
          primaryActive.occurrenceDate == account.openingBalanceDate) {
        return;
      }

      // Mark active opening entry voided WITHOUT clearing `legacySourceTxId`.
      for (final active in activeExisting) {
        await (_db.update(_db.journalEntriesTable)
              ..where((tbl) => tbl.id.equals(active.id)))
            .write(
          JournalEntriesTableCompanion(
            isVoided: const Value(true),
            voidReason: Value(reason),
          ),
        );
      }
    }

    if (account.openingBalanceCents == 0) return;

    var maxRev = 0;
    for (final h in allHistory) {
      final tag = h.legacySourceTxId ?? '';
      if (tag == openTag && maxRev < 1) {
        maxRev = 1;
      } else if (tag.startsWith('$openTag:rev:')) {
        final revNum = int.tryParse(tag.substring('$openTag:rev:'.length)) ?? 1;
        if (revNum > maxRev) maxRev = revNum;
      }
    }
    final nextTag = maxRev == 0 ? openTag : '$openTag:rev:${maxRev + 1}';
    final prevEntryId =
        primaryActive?.id ?? (allHistory.isEmpty ? null : allHistory.first.id);

    final entryId = 'entry-open-${_uuid.v4()}';
    final built = DoubleEntryEngine.buildOpeningBalance(
      entryId: entryId,
      account: account,
      legacySourceTxId: nextTag,
      correctedFromEntryId: prevEntryId,
    );
    final entry = built['entry'] as JournalEntryModel;
    final postings = built['postings'] as List<PostingModel>;
    DoubleEntryEngine.validateBalancedEntry(postings);
    await _insertEntryAndPostingsInTx(entry, postings);
  }

  String _formatDescription(String description, {String? payee}) {
    final cleanDesc = description.trim();
    final cleanPayee = payee?.trim();
    if (cleanPayee != null && cleanPayee.isNotEmpty) {
      if (cleanDesc.isEmpty) return cleanPayee;
      if (cleanDesc.toLowerCase().contains(cleanPayee.toLowerCase())) {
        return cleanDesc;
      }
      return '$cleanPayee — $cleanDesc';
    }
    return cleanDesc.isEmpty ? 'Transaction' : cleanDesc;
  }

  AccountModel _mapAccountRow(AccountsTableData row) {
    final accountType = AccountType.values.firstWhere(
      (e) => e.name == row.type,
      orElse: () => AccountType.asset,
    );
    final subType = AccountSubType.fromDbValue(
      row.subType,
      fallbackType: accountType,
    );
    return AccountModel(
      id: row.id,
      name: row.name,
      type: accountType,
      subType: subType,
      isSystem: row.isSystem,
      currencyCode: row.currencyCode,
      isArchived: row.isArchived,
      openingBalanceCents: row.openingBalanceCents,
      openingBalanceDate: row.openingBalanceDate,
      createdAt: row.createdAt.toUtc(),
    );
  }

  TransactionCategoryModel _mapCategoryRow(FinancialCategory row) {
    return TransactionCategoryModel(
      id: row.id,
      name: row.name,
      type: row.type,
      colorHex: row.colorHex,
      parentId: row.parentId,
      sortOrder: row.sortOrder,
      isDefault: row.isDefault,
      isArchived: row.isArchived,
    );
  }

  JournalEntryModel _mapJournalEntryRow(JournalEntriesTableData row) {
    final entryType = EntryType.fromDbValue(row.entryType);
    return JournalEntryModel(
      id: row.id,
      entryType: entryType,
      description: row.description,
      occurrenceDate: row.occurrenceDate,
      isVoided: row.isVoided,
      voidReason: row.voidReason,
      legacySourceTxId: row.legacySourceTxId,
      correctedFromEntryId: row.correctedFromEntryId,
      createdAt: row.createdAt,
    );
  }

  DebtModel _mapDebtRow(DebtsTableData row) {
    final debtType =
        row.debtType == 'receivable' ? DebtType.receivable : DebtType.payable;
    return DebtModel(
      id: row.id,
      originEntryId: row.originEntryId,
      partyId: row.partyId,
      debtType: debtType,
      principalCents: row.principalCents,
      outstandingCents: row.outstandingCents,
      dueDate: row.dueDate,
      status: DebtStatus.fromDbValue(row.status),
      writeOffEntryId: row.writeOffEntryId,
      createdAt: row.createdAt,
    );
  }

  CommitmentModel _mapCommitmentRow(
    FinancialCommitment row, {
    int? verifiedSettledCents,
  }) {
    final direction = row.direction == 'inflow'
        ? CommitmentDirection.inflow
        : CommitmentDirection.outflow;
    final settled = verifiedSettledCents ??
        ((row.isPaid &&
                !row.legacyPaidUnverified &&
                row.settlementEntryId != null)
            ? row.amountCents
            : 0);
    return CommitmentModel(
      id: row.id,
      title: row.title,
      amountCents: row.amountCents,
      dueDate: SharedDateFormatter.parseFlexibleToCalendarDate(row.dueDate),
      isPaid: row.isPaid,
      direction: direction,
      legacyPaidUnverified: row.legacyPaidUnverified,
      verifiedSettledCents: settled,
      recurringRule: row.recurringRule,
      linkedAccountId: row.linkedAccountId,
      categoryId: row.categoryId,
      linkedDebtId: row.linkedDebtId,
      settlementEntryId: row.settlementEntryId,
      recurringRuleId: row.recurringRuleId,
    );
  }

  SavingsGoalModel _mapSavingsGoalRow(SavingsGoal row) {
    final status = SavingsGoalStatus.values.firstWhere(
      (s) => s.name == row.status,
      orElse: () => SavingsGoalStatus.active,
    );
    return SavingsGoalModel(
      id: row.id,
      title: row.title,
      targetCents: row.targetCents,
      currentAllocatedCents: row.currentAllocatedCents,
      targetDate:
          SharedDateFormatter.tryParseFlexibleToCalendarDate(row.targetDate),
      linkedAccountId: row.linkedAccountId,
      status: status,
    );
  }

  BudgetModel _mapBudgetRow(BudgetsTableData row) {
    return BudgetModel(
      id: row.id,
      categoryId: row.categoryId,
      monthIso: row.monthIso,
      limitCents: row.limitCents,
      rolloverEnabled: row.rolloverEnabled,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  RecurringRuleModel _mapRecurringRuleRow(RecurringRulesTableData row) {
    return RecurringRuleModel(
      id: row.id,
      title: row.title,
      ruleType: RecurringRuleType.values.firstWhere(
        (e) => e.name == row.ruleType,
        orElse: () => RecurringRuleType.commitment,
      ),
      amountCents: row.amountCents,
      frequency: RecurrenceFrequency.values.firstWhere(
        (e) => e.name == row.frequency,
        orElse: () => RecurrenceFrequency.monthly,
      ),
      interval: row.interval,
      startDate: SharedDateFormatter.parseFlexibleToCalendarDate(row.startDate),
      nextOccurrenceDate: SharedDateFormatter.parseFlexibleToCalendarDate(
        row.nextOccurrenceDate,
      ),
      endDate: SharedDateFormatter.tryParseFlexibleToCalendarDate(row.endDate),
      accountId: row.accountId,
      destinationAccountId: row.destinationAccountId,
      categoryId: row.categoryId,
      linkedDebtId: row.linkedDebtId,
      isActive: row.isActive,
      autoPost: row.autoPost,
      createdAt: row.createdAt,
    );
  }
}
