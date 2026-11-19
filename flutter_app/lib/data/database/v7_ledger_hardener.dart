import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../core/date/shared_date.dart';
import '../../domain/finance/double_entry_engine.dart';
import 'app_database.dart';
import 'v6_ledger_migrator.dart';

/// Unified Schema v7 convergence, hardening, audit, and invariant verifier.
///
/// Runs identically at the end of installed DB upgrades (`from < 7`) and
/// normalized `v4`/`v5`/`v6` snapshot imports while keeping [V6LedgerMigrator]
/// frozen for pre-v6 transformations.
class V7LedgerHardener {
  static const String v7ReportKey = 'ledger_migration_report_v7';

  static Future<MigrationDiagnosticReport> hardenAndAuditInTransaction(
    AppDatabase db, {
    required int fromVersion,
    List<String> preRebuildWarnings = const [],
  }) async {
    final now = EthiopiaClock.nowUtc();
    final warnings = List<String>.from(preRebuildWarnings);
    final errors = <String>[];
    var entriesCreated = 0;

    await V6LedgerMigrator.ensureSystemControlAccounts(db);

    // 1. Account subtype normalization & non-ETB audit.
    final initialAccounts = await db.select(db.accountsTable).get();
    for (final acc in initialAccounts) {
      final classified = V6LedgerMigrator.inferAccountClassification(
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
      if (!classified.isSystem && !acc.isArchived) {
        final tier = DoubleEntryEngine.classifyCurrencyCode(acc.currencyCode);
        if (tier == CurrencyValidationTier.verifiedNonEtb) {
          warnings.add(
            'NON_ETB_ACCOUNT_FLAGGED: ${acc.id} '
            '(${DoubleEntryEngine.normalizeCurrencyCode(acc.currencyCode)})',
          );
        } else if (tier == CurrencyValidationTier.unverified) {
          warnings.add(
            'UNVERIFIED_ACCOUNT_CURRENCY: ${acc.id} (${acc.currencyCode})',
          );
        }
      }
    }

    // 2. Normalize Debts (writtenOff -> written_off, voided origins, writeOffId).
    await _normalizeAndLinkWriteOffs(db, warnings: warnings);
    await reconcileAllDebtsV7(db);

    // 3. Backfill CommitmentSettlementsTable & flag legacyPaidUnverified.
    final legacyPaidFlaggedCount = await _reconcileCommitmentsV7(
      db,
      warnings: warnings,
    );

    // 4. Normalize SavingsGoals statuses & synchronize vault-linked allocations.
    await _normalizeSavingsGoalStatuses(db);
    await syncVaultSavingsGoalsV7(db);

    // 5. Audit Legacy Clearing Offset usage.
    final clearingPostings = await db.customSelect('''
      SELECT DISTINCT entry_id
      FROM postings_table
      WHERE account_id = ?
    ''', variables: [
      const Variable<String>(SystemControlAccounts.legacyOffset)
    ]).get();
    for (final row in clearingPostings) {
      warnings.add(
        'LEGACY_CLEARING_OFFSET_USED: ${row.read<String>('entry_id')}',
      );
    }

    // 6. 5-Case / 7-Point Opening-Balance Audit.
    entriesCreated += await _auditAndSynthesizeOpeningBalances(
      db,
      warnings: warnings,
    );

    // 7. Audit Tier A/B Debt Control Balances.
    final debtAudit = await computeDebtControlAudit(db);
    if (!debtAudit.isTierABalanced) {
      warnings.add(
        'DEBT_CONTROL_MISMATCH: '
        'arDelta=${debtAudit.receivableDeltaCents}, '
        'apDelta=${debtAudit.payableDeltaCents}',
      );
    }

    // 8. Verify strict post-hardening invariants (aborts cleanly on failure).
    await verifyInvariantsOnly(db);

    final accountsFinal = await db.select(db.accountsTable).get();
    final auditedUserAccounts = accountsFinal.where((a) => !a.isSystem).length;

    final v6MigratedRow = await (db.select(db.appSettings)
          ..where((t) => t.key.equals(V6LedgerMigrator.v6MigratedSentinelKey)))
        .getSingleOrNull();

    final summaryParts = <String>[
      'Hardened ledger from v$fromVersion to v7',
      '$auditedUserAccounts user account(s)',
      '$entriesCreated opening entry(ies) created',
      '$legacyPaidFlaggedCount legacy paid commitment(s) flagged',
      '${warnings.length} warning(s)',
    ];
    if (v6MigratedRow != null) {
      summaryParts.add('v6MigratedAt=${v6MigratedRow.value}');
    }

    final report = MigrationDiagnosticReport(
      fromVersion: fromVersion,
      toVersion: 7,
      migratedAtIso: EthiopiaClock.toUtcIsoString(now),
      accountsAudited: auditedUserAccounts,
      entriesCreated: entriesCreated,
      legacyPaidFlaggedCount: legacyPaidFlaggedCount,
      warnings: warnings,
      errors: errors,
      summary: summaryParts.join(' · '),
    );

    await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: v7ReportKey,
            value: jsonEncode(report.toJson()),
            updatedAt: now,
          ),
        );

    return report;
  }

  /// Recomputes all debt statuses (`active`, `settled`, `written_off`,
  /// `voided`) and outstanding cents deterministically.
  static Future<void> reconcileAllDebtsV7(AppDatabase db) async {
    final debts = await db.select(db.debtsTable).get();
    if (debts.isEmpty) return;

    final entries = await db.select(db.journalEntriesTable).get();
    final voidedEntryIds = {
      for (final e in entries)
        if (e.isVoided) e.id,
    };
    final entryById = {for (final e in entries) e.id: e};
    final allocations = await db.select(db.settlementAllocationsTable).get();

    for (final debt in debts) {
      final originVoided = voidedEntryIds.contains(debt.originEntryId);
      final normalizedRawStatus =
          DebtStatus.tryParse(debt.status)?.dbValue ?? debt.status;

      final linkedWriteOffId = debt.writeOffEntryId;
      final writeOffEntry =
          linkedWriteOffId == null ? null : entryById[linkedWriteOffId];
      final writeOffActive = writeOffEntry != null && !writeOffEntry.isVoided;
      final writeOffWasVoided =
          linkedWriteOffId != null && (writeOffEntry?.isVoided ?? true);

      final isLegacyWrittenOffWithoutLink =
          linkedWriteOffId == null && normalizedRawStatus == 'written_off';
      final isWrittenOff = writeOffActive || isLegacyWrittenOffWithoutLink;

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
        expectedStatus = 'voided';
      } else if (isWrittenOff) {
        expectedStatus = 'written_off';
      } else {
        expectedStatus = expectedOutstanding == 0 ? 'settled' : 'active';
      }

      final clearWriteOff = writeOffWasVoided;
      if (debt.outstandingCents != expectedOutstanding ||
          debt.status != expectedStatus ||
          clearWriteOff) {
        await (db.update(db.debtsTable)..where((tbl) => tbl.id.equals(debt.id)))
            .write(
          DebtsTableCompanion(
            outstandingCents: Value(expectedOutstanding),
            status: Value(expectedStatus),
            writeOffEntryId:
                clearWriteOff ? const Value(null) : const Value.absent(),
          ),
        );
      }
    }
  }

  /// Tier A / B audit comparing AR/AP control account balances against active
  /// tracked debt records.
  static Future<DebtControlAuditReport> computeDebtControlAudit(
    AppDatabase db,
  ) async {
    final accounts = await db.select(db.accountsTable).get();
    final entries = await db.select(db.journalEntriesTable).get();
    final postings = await db.select(db.postingsTable).get();
    final debts = await db.select(db.debtsTable).get();
    final allocations = await db.select(db.settlementAllocationsTable).get();

    final mappedAccounts = accounts
        .map(
          (a) => AccountModel(
            id: a.id,
            name: a.name,
            type: AccountType.values.firstWhere(
              (t) => t.name == a.type,
              orElse: () => AccountType.asset,
            ),
            subType: AccountSubType.fromDbValue(a.subType),
            isSystem: a.isSystem,
            currencyCode: a.currencyCode,
            isArchived: a.isArchived,
            openingBalanceCents: a.openingBalanceCents,
            openingBalanceDate: a.openingBalanceDate,
            createdAt: a.createdAt,
          ),
        )
        .toList();

    final mappedEntries = entries
        .map(
          (e) => JournalEntryModel(
            id: e.id,
            entryType: EntryType.fromDbValue(e.entryType),
            description: e.description,
            occurrenceDate: e.occurrenceDate,
            isVoided: e.isVoided,
            voidReason: e.voidReason,
            legacySourceTxId: e.legacySourceTxId,
            correctedFromEntryId: e.correctedFromEntryId,
            createdAt: e.createdAt,
          ),
        )
        .toList();

    final mappedPostings = postings
        .map(
          (p) => PostingModel(
            id: p.id,
            entryId: p.entryId,
            accountId: p.accountId,
            amountCents: p.amountCents,
            direction: p.direction == 'debit'
                ? PostingDirection.debit
                : PostingDirection.credit,
            accountMovementDate: p.accountMovementDate,
            categoryId: p.categoryId,
            note: p.note,
          ),
        )
        .toList();

    final mappedDebts = debts
        .map(
          (d) => DebtModel(
            id: d.id,
            originEntryId: d.originEntryId,
            partyId: d.partyId,
            debtType: d.debtType == 'receivable'
                ? DebtType.receivable
                : DebtType.payable,
            principalCents: d.principalCents,
            outstandingCents: d.outstandingCents,
            dueDate: d.dueDate,
            status: DebtStatus.fromDbValue(d.status),
            writeOffEntryId: d.writeOffEntryId,
            createdAt: d.createdAt,
          ),
        )
        .toList();

    final mappedAllocations = allocations
        .map(
          (a) => SettlementAllocationModel(
            id: a.id,
            settlementEntryId: a.settlementEntryId,
            debtId: a.debtId,
            allocatedCents: a.allocatedCents,
            settlementDate: a.settlementDate,
          ),
        )
        .toList();

    final classifications = DoubleEntryEngine.classifyAllEntries(
      accounts: mappedAccounts,
      entries: mappedEntries,
      postings: mappedPostings,
      debts: mappedDebts,
      allocations: mappedAllocations,
    );

    bool isEligibleEtbEntry(String entryId) =>
        classifications[entryId]?.isEligibleEtb ?? false;

    var arControlBal = 0;
    var apControlBal = 0;

    for (final p in postings) {
      if (!isEligibleEtbEntry(p.entryId)) continue;
      if (p.accountId == SystemControlAccounts.receivable ||
          p.accountId == 'acc-rec') {
        arControlBal += p.direction == 'debit' ? p.amountCents : -p.amountCents;
      } else if (p.accountId == SystemControlAccounts.payable ||
          p.accountId == 'acc-pay') {
        apControlBal +=
            p.direction == 'credit' ? p.amountCents : -p.amountCents;
      }
    }

    // Fallback check for custom receivable/payable typed accounts if any.
    for (final a in accounts) {
      if (SystemControlAccounts.isSystemControlId(a.id) ||
          a.id == 'acc-rec' ||
          a.id == 'acc-pay') {
        continue;
      }
      if (a.subType == 'receivable') {
        for (final p in postings) {
          if (p.accountId == a.id && isEligibleEtbEntry(p.entryId)) {
            arControlBal +=
                p.direction == 'debit' ? p.amountCents : -p.amountCents;
          }
        }
      } else if (a.subType == 'payable') {
        for (final p in postings) {
          if (p.accountId == a.id && isEligibleEtbEntry(p.entryId)) {
            apControlBal +=
                p.direction == 'credit' ? p.amountCents : -p.amountCents;
          }
        }
      }
    }

    final activeRecSum = debts
        .where(
          (d) =>
              d.debtType == 'receivable' &&
              d.status == 'active' &&
              isEligibleEtbEntry(d.originEntryId),
        )
        .fold<int>(0, (sum, d) => sum + max(0, d.outstandingCents));
    final activePaySum = debts
        .where(
          (d) =>
              d.debtType == 'payable' &&
              d.status == 'active' &&
              isEligibleEtbEntry(d.originEntryId),
        )
        .fold<int>(0, (sum, d) => sum + max(0, d.outstandingCents));

    final mismatches = <String>[];
    if (arControlBal != activeRecSum) {
      mismatches.add(
        'Receivable control ($arControlBal c) != '
        'active receivables ($activeRecSum c)',
      );
    }
    if (apControlBal != activePaySum) {
      mismatches.add(
        'Payable control ($apControlBal c) != '
        'active payables ($activePaySum c)',
      );
    }

    return DebtControlAuditReport(
      receivableControlBalanceCents: arControlBal,
      activeReceivableSumCents: activeRecSum,
      payableControlBalanceCents: apControlBal,
      activePayableSumCents: activePaySum,
      mismatchDetails: mismatches,
    );
  }

  /// Validates core double-entry, account, canonical date, and FK invariants.
  /// Throws [LedgerMigrationException] on any violation.
  static Future<void> verifyInvariantsOnly(AppDatabase db) async {
    // A. Balanced entry check (>= 2 postings, SUM Dr == SUM Cr, > 0 amounts).
    final unbalanced = await db.customSelect('''
      SELECT j.id,
             COALESCE(
               SUM(CASE WHEN p.direction = 'debit'
                        THEN p.amount_cents ELSE 0 END),
               0
             ) AS dr_sum,
             COALESCE(
               SUM(CASE WHEN p.direction = 'credit'
                        THEN p.amount_cents ELSE 0 END),
               0
             ) AS cr_sum,
             COUNT(p.id) AS posting_count
      FROM journal_entries_table j
      LEFT JOIN postings_table p ON p.entry_id = j.id
      GROUP BY j.id
      HAVING dr_sum != cr_sum OR posting_count < 2
    ''').get();

    if (unbalanced.isNotEmpty) {
      final row = unbalanced.first;
      throw LedgerMigrationException(
        'Unbalanced or incomplete journal entry ${row.read<String>('id')} '
        '(dr=${row.read<int>('dr_sum')}, cr=${row.read<int>('cr_sum')}, '
        'count=${row.read<int>('posting_count')}).',
      );
    }

    // B. Canonical YYYY-MM-DD checks on core ledger tables.
    final badDates = await db.customSelect('''
      SELECT 'journal_entries_table' AS tbl, id, occurrence_date AS dt
      FROM journal_entries_table
      WHERE occurrence_date NOT GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
      UNION ALL
      SELECT 'postings_table' AS tbl, id, account_movement_date AS dt
      FROM postings_table
      WHERE account_movement_date
            NOT GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
      UNION ALL
      SELECT 'financial_commitments' AS tbl, id, due_date AS dt
      FROM financial_commitments
      WHERE due_date NOT GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
      LIMIT 1
    ''').get();
    if (badDates.isNotEmpty) {
      final row = badDates.first;
      throw LedgerMigrationException(
        'Invalid canonical date in ${row.read<String>('tbl')} '
        '(id=${row.read<String>('id')}, value=${row.read<String>('dt')}).',
      );
    }

    // C. Foreign-key check.
    final fkViolations =
        await db.customSelect('PRAGMA foreign_key_check').get();
    if (fkViolations.isNotEmpty) {
      throw LedgerMigrationException(
        'Foreign key invariant violation (${fkViolations.length} row(s)).',
      );
    }
  }

  static Future<void> _normalizeAndLinkWriteOffs(
    AppDatabase db, {
    required List<String> warnings,
  }) async {
    await db.customStatement(
      "UPDATE debts_table SET status = 'written_off' "
      "WHERE status = 'writtenOff';",
    );
    await db.customStatement(
      "UPDATE debts_table SET status = 'active' "
      "WHERE status = 'partially_settled';",
    );
    await db.customStatement(
      "UPDATE journal_entries_table SET entry_type = 'debt_issuance' "
      "WHERE entry_type IN ('debtIssuance', 'debt_origin');",
    );
    await db.customStatement(
      "UPDATE journal_entries_table SET entry_type = 'split_expense' "
      "WHERE entry_type = 'splitExpense';",
    );
    await db.customStatement(
      "UPDATE journal_entries_table SET entry_type = 'write_off' "
      "WHERE entry_type = 'writeOff';",
    );
    await db.customStatement(
      "UPDATE journal_entries_table SET entry_type = 'settlement' "
      "WHERE entry_type = 'debt_settlement';",
    );
    await db.customStatement(
      "UPDATE journal_entries_table SET entry_type = 'adjustment' "
      "WHERE entry_type IN "
      "('opening_balance', 'opening', 'correction', 'void_reversal');",
    );

    final debts = await db.select(db.debtsTable).get();
    final entries = await db.select(db.journalEntriesTable).get();
    final postings = await db.select(db.postingsTable).get();
    final allocations = await db.select(db.settlementAllocationsTable).get();

    final voidedEntryIds = {
      for (final e in entries)
        if (e.isVoided) e.id,
    };
    final postingsByEntry = <String, List<PostingsTableData>>{};
    for (final p in postings) {
      postingsByEntry.putIfAbsent(p.entryId, () => []).add(p);
    }

    final claimedWriteOffIds = {
      for (final d in debts)
        if (d.writeOffEntryId != null) d.writeOffEntryId!,
    };
    final activeWriteOffEntries = entries
        .where(
          (e) =>
              (e.entryType == EntryType.writeOff.dbValue ||
                  e.entryType == 'writeOff') &&
              !e.isVoided,
        )
        .toList();

    for (final debt in debts) {
      if (voidedEntryIds.contains(debt.originEntryId)) {
        await (db.update(db.debtsTable)..where((tbl) => tbl.id.equals(debt.id)))
            .write(
          const DebtsTableCompanion(
            status: Value('voided'),
            outstandingCents: Value(0),
          ),
        );
        continue;
      }

      if (debt.status != 'written_off' || debt.writeOffEntryId != null) {
        continue;
      }

      final settledBefore = allocations
          .where(
            (a) =>
                a.debtId == debt.id &&
                !voidedEntryIds.contains(a.settlementEntryId),
          )
          .fold<int>(0, (sum, a) => sum + a.allocatedCents);
      final expectedWriteOffCents = max(0, debt.principalCents - settledBefore);
      if (expectedWriteOffCents <= 0) continue;

      final matches = <String>[];
      for (final entry in activeWriteOffEntries) {
        if (claimedWriteOffIds.contains(entry.id)) continue;
        final ps = postingsByEntry[entry.id] ?? const [];
        final matchingControl = ps.any((p) {
          if (p.amountCents != expectedWriteOffCents) return false;
          if (debt.debtType == 'receivable') {
            return p.direction == 'credit' &&
                (p.accountId == SystemControlAccounts.receivable ||
                    p.accountId == 'acc-rec');
          } else {
            return p.direction == 'debit' &&
                (p.accountId == SystemControlAccounts.payable ||
                    p.accountId == 'acc-pay');
          }
        });
        if (matchingControl) {
          matches.add(entry.id);
        }
      }

      if (matches.length == 1) {
        final matchedId = matches.single;
        claimedWriteOffIds.add(matchedId);
        await (db.update(db.debtsTable)..where((tbl) => tbl.id.equals(debt.id)))
            .write(
          DebtsTableCompanion(
            writeOffEntryId: Value(matchedId),
            outstandingCents: const Value(0),
          ),
        );
      } else {
        warnings.add('UNLINKED_LEGACY_WRITEOFF: debt=${debt.id}');
      }
    }
  }

  static Future<int> _reconcileCommitmentsV7(
    AppDatabase db, {
    required List<String> warnings,
  }) async {
    final commitments = await db.select(db.financialCommitments).get();
    final entries = await db.select(db.journalEntriesTable).get();
    final entryById = {for (final e in entries) e.id: e};
    final existingSettlements =
        await db.select(db.commitmentSettlementsTable).get();

    for (final c in commitments) {
      final settleEntryId = c.settlementEntryId;
      if (settleEntryId != null) {
        final entry = entryById[settleEntryId];
        final alreadyLinked = existingSettlements.any(
          (s) => s.commitmentId == c.id && s.entryId == settleEntryId,
        );
        if (entry != null && !entry.isVoided && !alreadyLinked) {
          await db.into(db.commitmentSettlementsTable).insert(
                CommitmentSettlementsTableCompanion.insert(
                  id: 'cs-mig-${c.id}',
                  commitmentId: c.id,
                  entryId: settleEntryId,
                  amountCents: max(1, c.amountCents),
                  settledDate: entry.occurrenceDate,
                  createdAt: entry.createdAt,
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
      }
    }

    final updatedSettlements =
        await db.select(db.commitmentSettlementsTable).get();
    var legacyPaidFlaggedCount = 0;

    for (final c in commitments) {
      final direction = c.direction == 'inflow' ? 'inflow' : 'outflow';
      final verifiedSettled = updatedSettlements
          .where((s) =>
              s.commitmentId == c.id && entryById[s.entryId]?.isVoided == false)
          .fold<int>(0, (sum, s) => sum + s.amountCents);

      if (verifiedSettled > 0) {
        final nextPaid = verifiedSettled >= c.amountCents;
        if (c.isPaid != nextPaid ||
            c.legacyPaidUnverified ||
            c.direction != direction) {
          await (db.update(db.financialCommitments)
                ..where((tbl) => tbl.id.equals(c.id)))
              .write(
            FinancialCommitmentsCompanion(
              isPaid: Value(nextPaid),
              legacyPaidUnverified: const Value(false),
              direction: Value(direction),
            ),
          );
        }
      } else if ((c.isPaid && c.settlementEntryId == null) ||
          c.legacyPaidUnverified) {
        // Pre-v7 isPaid without any valid verified ledger settlement.
        legacyPaidFlaggedCount++;
        warnings.add('LEGACY_UNVERIFIED_PAID_COMMITMENT: ${c.id}');
        if (!c.legacyPaidUnverified || !c.isPaid || c.direction != direction) {
          await (db.update(db.financialCommitments)
                ..where((tbl) => tbl.id.equals(c.id)))
              .write(
            FinancialCommitmentsCompanion(
              isPaid: const Value(true),
              legacyPaidUnverified: const Value(true),
              direction: Value(direction),
              settlementEntryId: const Value(null),
            ),
          );
        }
      } else if (c.isPaid && c.settlementEntryId != null) {
        // Linked entry is voided; restore unpaid state safely.
        await (db.update(db.financialCommitments)
              ..where((tbl) => tbl.id.equals(c.id)))
            .write(
          FinancialCommitmentsCompanion(
            isPaid: const Value(false),
            legacyPaidUnverified: const Value(false),
            direction: Value(direction),
            settlementEntryId: const Value(null),
          ),
        );
      } else if (c.direction != direction) {
        await (db.update(db.financialCommitments)
              ..where((tbl) => tbl.id.equals(c.id)))
            .write(FinancialCommitmentsCompanion(direction: Value(direction)));
      }
    }

    return legacyPaidFlaggedCount;
  }

  static Future<void> _normalizeSavingsGoalStatuses(AppDatabase db) async {
    await db.customStatement(
      "UPDATE savings_goals SET status = 'active' "
      "WHERE status IS NULL OR status NOT IN ('active', 'completed', 'archived');",
    );
  }

  /// Synchronizes active/completed vault-linked SavingsGoals (`currentAllocatedCents`
  /// and `status`) against live ledger balances of their linked Savings Vaults.
  static Future<void> syncVaultSavingsGoalsV7(AppDatabase db) async {
    final goals = await db.select(db.savingsGoals).get();
    final vaultGoals = goals
        .where(
          (g) =>
              g.status != 'archived' &&
              g.linkedAccountId != null &&
              g.linkedAccountId!.trim().isNotEmpty,
        )
        .toList();
    if (vaultGoals.isEmpty) return;

    final accounts = await db.select(db.accountsTable).get();
    final accountById = <String, AccountModel>{};
    for (final a in accounts) {
      final accountType = AccountType.values.firstWhere(
        (t) => t.name == a.type,
        orElse: () => AccountType.asset,
      );
      accountById[a.id] = AccountModel(
        id: a.id,
        name: a.name,
        type: accountType,
        subType: AccountSubType.fromDbValue(
          a.subType,
          fallbackType: accountType,
        ),
        isSystem: a.isSystem,
        currencyCode: a.currencyCode,
        isArchived: a.isArchived,
        openingBalanceCents: a.openingBalanceCents,
        openingBalanceDate: a.openingBalanceDate,
        createdAt: a.createdAt,
      );
    }

    final entryRows = await db.select(db.journalEntriesTable).get();
    final mappedEntries = entryRows
        .map(
          (e) => JournalEntryModel(
            id: e.id,
            entryType: EntryType.fromDbValue(e.entryType),
            description: e.description,
            occurrenceDate: e.occurrenceDate,
            isVoided: e.isVoided,
            voidReason: e.voidReason,
            legacySourceTxId: e.legacySourceTxId,
            correctedFromEntryId: e.correctedFromEntryId,
            createdAt: e.createdAt,
          ),
        )
        .toList();

    final postingRows = await db.select(db.postingsTable).get();
    final mappedPostings = postingRows
        .map(
          (p) => PostingModel(
            id: p.id,
            entryId: p.entryId,
            accountId: p.accountId,
            amountCents: p.amountCents,
            direction: p.direction == 'debit'
                ? PostingDirection.debit
                : PostingDirection.credit,
            accountMovementDate: p.accountMovementDate,
            categoryId: p.categoryId,
            note: p.note,
          ),
        )
        .toList();

    for (final goal in vaultGoals) {
      final acc = accountById[goal.linkedAccountId!.trim()];
      if (acc == null) continue;
      final balance = max(
        0,
        DoubleEntryEngine.calculateAccountBalance(
          account: acc,
          postings: mappedPostings,
          entries: mappedEntries,
        ),
      );
      final nextStatus = (goal.targetCents > 0 && balance >= goal.targetCents)
          ? 'completed'
          : 'active';
      if (goal.currentAllocatedCents != balance || goal.status != nextStatus) {
        await (db.update(db.savingsGoals)
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

  static Future<int> _auditAndSynthesizeOpeningBalances(
    AppDatabase db, {
    required List<String> warnings,
  }) async {
    var created = 0;
    final accounts = await db.select(db.accountsTable).get();
    final entries = await db.select(db.journalEntriesTable).get();
    final postings = await db.select(db.postingsTable).get();

    final postingsByEntry = <String, List<PostingsTableData>>{};
    for (final p in postings) {
      postingsByEntry.putIfAbsent(p.entryId, () => []).add(p);
    }

    final existingSources = <String, String>{
      for (final e in entries)
        if (e.legacySourceTxId != null) e.legacySourceTxId!: e.id,
    };
    final usedEntryIds = {for (final e in entries) e.id};

    for (final acc in accounts) {
      if (acc.isSystem) continue;

      final openTag = 'open:${acc.id}';
      final openRevPrefix = '$openTag:rev:';

      bool isOpenTagged(String? tag) =>
          tag == openTag || (tag != null && tag.startsWith(openRevPrefix));

      bool touchesAcc(String entryId) =>
          (postingsByEntry[entryId] ?? const []).any(
            (p) => p.accountId == acc.id,
          );

      // Identify all plausible opening-balance candidates for acc.
      final plausible = <JournalEntriesTableData>[];
      JournalEntriesTableData? conflictingLink;
      for (final e in entries) {
        final isPlausibleShape = e.entryType == 'adjustment' &&
            (e.id.startsWith('entry-open-') ||
                e.description.startsWith('Opening Balance') ||
                isOpenTagged(e.legacySourceTxId));
        final belongsToAcc =
            touchesAcc(e.id) || isOpenTagged(e.legacySourceTxId);
        if (e.legacySourceTxId == openTag && !isPlausibleShape) {
          conflictingLink = e;
        } else if (isPlausibleShape &&
            belongsToAcc &&
            e.legacySourceTxId != null &&
            !isOpenTagged(e.legacySourceTxId)) {
          conflictingLink = e;
        }
        if (isPlausibleShape && belongsToAcc) {
          plausible.add(e);
        }
      }

      if (conflictingLink != null) {
        warnings.add(
          'OPENING_CONFLICTING_LEGACY_LINK: '
          'account=${acc.id}, entry=${conflictingLink.id}',
        );
        continue;
      }

      // Recognize superseded revision history so historical voided `:rev:n`
      // or zeroed opening entries don't raise false errors.
      final activeCorrectedFrom = {
        for (final e in plausible)
          if (!e.isVoided && e.correctedFromEntryId != null)
            e.correctedFromEntryId!,
      };
      final nonSuperseded = plausible.where((e) {
        if (!e.isVoided) return true;
        if (activeCorrectedFrom.contains(e.id)) return false;
        if (acc.openingBalanceCents == 0 &&
            e.voidReason == 'Updated opening balance') {
          return false;
        }
        return true;
      }).toList();

      final validCandidates = <JournalEntriesTableData>[];
      var hasFailingCandidate = false;

      for (final cand in nonSuperseded) {
        final failures = _evaluateSevenCriteria(
          acc: acc,
          entry: cand,
          postings: postingsByEntry[cand.id] ?? const [],
          openTag: openTag,
          openRevPrefix: openRevPrefix,
        );
        if (failures.isEmpty) {
          validCandidates.add(cand);
        } else {
          hasFailingCandidate = true;
          warnings.add(
            'OPENING_INCONSISTENT_CANDIDATE: account=${acc.id}, '
            'entry=${cand.id}, failed=[${failures.join(',')}]',
          );
        }
      }

      if (hasFailingCandidate) {
        // Case 5: Preserve untouched without synthesizing a duplicate.
        continue;
      }

      if (validCandidates.length >= 2) {
        // Case 4: Preserve all untouched & warn.
        warnings.add(
          'OPENING_MULTIPLE_CANDIDATES: account=${acc.id}, '
          'count=${validCandidates.length}',
        );
        continue;
      }

      if (validCandidates.length == 1) {
        // Case 3: Matched idempotently. Backfill tag only if safely unassigned.
        final matched = validCandidates.single;
        if (matched.legacySourceTxId == null &&
            !existingSources.containsKey(openTag)) {
          await (db.update(db.journalEntriesTable)
                ..where((tbl) => tbl.id.equals(matched.id)))
              .write(
            JournalEntriesTableCompanion(legacySourceTxId: Value(openTag)),
          );
          existingSources[openTag] = matched.id;
        }
        continue;
      }

      // Case 2: Zero active non-superseded candidates.
      if (acc.openingBalanceCents != 0 &&
          !existingSources.containsKey(openTag)) {
        var entryId = 'entry-open-v7-${acc.id}';
        var suffix = 1;
        while (usedEntryIds.contains(entryId)) {
          entryId = 'entry-open-v7-${acc.id}-$suffix';
          suffix++;
        }
        usedEntryIds.add(entryId);

        final openDate = acc.openingBalanceDate != null &&
                SharedDateFormatter.tryParseFlexibleToCalendarDate(
                      acc.openingBalanceDate,
                    ) !=
                    null
            ? SharedDateFormatter.parseFlexibleToCalendarDate(
                acc.openingBalanceDate!,
              ).toIsoString()
            : CalendarDate.fromUtcInstantInEthiopia(acc.createdAt)
                .toIsoString();

        final built = DoubleEntryEngine.buildOpeningBalance(
          entryId: entryId,
          account: AccountModel(
            id: acc.id,
            name: acc.name,
            type: AccountType.values.firstWhere(
              (t) => t.name == acc.type,
              orElse: () => AccountType.asset,
            ),
            subType: AccountSubType.fromDbValue(acc.subType),
            isSystem: acc.isSystem,
            currencyCode: acc.currencyCode,
            isArchived: acc.isArchived,
            openingBalanceCents: acc.openingBalanceCents,
            openingBalanceDate: openDate,
            createdAt: acc.createdAt,
          ),
          date: openDate,
          legacySourceTxId: openTag,
        );

        final entry = built['entry'] as JournalEntryModel;
        final builtPostings = built['postings'] as List<PostingModel>;
        DoubleEntryEngine.validateBalancedEntry(builtPostings);

        await db.into(db.journalEntriesTable).insert(
              JournalEntriesTableCompanion.insert(
                id: entry.id,
                entryType: entry.entryType.dbValue,
                description: entry.description,
                occurrenceDate: entry.occurrenceDate,
                isVoided: Value(entry.isVoided),
                legacySourceTxId: Value(entry.legacySourceTxId),
                createdAt: acc.createdAt,
              ),
            );
        for (final p in builtPostings) {
          await db.into(db.postingsTable).insert(
                PostingsTableCompanion.insert(
                  id: p.id,
                  entryId: p.entryId,
                  accountId: p.accountId,
                  amountCents: p.amountCents,
                  direction: p.direction.name,
                  accountMovementDate: p.accountMovementDate,
                  note: Value(p.note),
                ),
              );
        }
        existingSources[openTag] = entry.id;
        created++;
      }
    }

    return created;
  }

  static List<String> _evaluateSevenCriteria({
    required AccountsTableData acc,
    required JournalEntriesTableData entry,
    required List<PostingsTableData> postings,
    required String openTag,
    required String openRevPrefix,
  }) {
    final failed = <String>[];

    // C5: Not voided.
    if (entry.isVoided) failed.add('C5_VOIDED');

    // C4: At least 2 postings and Debits == Credits.
    final drSum = postings
        .where((p) => p.direction == 'debit')
        .fold<int>(0, (sum, p) => sum + p.amountCents);
    final crSum = postings
        .where((p) => p.direction == 'credit')
        .fold<int>(0, (sum, p) => sum + p.amountCents);
    if (postings.length < 2 || drSum != crSum) {
      failed.add('C4_UNBALANCED');
    }

    // C1 & C2: Exact signed balance & Dr/Cr direction on acc.id.
    final isDebitNormal = acc.type == 'asset' || acc.type == 'expense';
    final accPostings = postings.where((p) => p.accountId == acc.id).toList();
    final accSigned = accPostings.fold<int>(0, (sum, p) {
      if (isDebitNormal) {
        return sum + (p.direction == 'debit' ? p.amountCents : -p.amountCents);
      }
      return sum + (p.direction == 'credit' ? p.amountCents : -p.amountCents);
    });
    if (accSigned != acc.openingBalanceCents) {
      failed.add('C1_BALANCE_MISMATCH');
    }
    final expectedAccDir = ((isDebitNormal && acc.openingBalanceCents > 0) ||
            (!isDebitNormal && acc.openingBalanceCents < 0))
        ? 'debit'
        : 'credit';
    final directionOk = acc.openingBalanceCents != 0 &&
        accPostings.isNotEmpty &&
        accPostings.every((p) => p.direction == expectedAccDir);
    if (!directionOk) {
      failed.add('C2_DIRECTION_MISMATCH');
    }

    // C3: Exact abs amount & equity offset.
    final expectedEquityDir = expectedAccDir == 'debit' ? 'credit' : 'debit';
    final equityOffsetSum = postings
        .where(
          (p) =>
              (p.accountId == SystemControlAccounts.equity ||
                  p.accountId == 'acc-equity') &&
              p.direction == expectedEquityDir,
        )
        .fold<int>(0, (sum, p) => sum + p.amountCents);
    if (equityOffsetSum != acc.openingBalanceCents.abs()) {
      failed.add('C3_EQUITY_OFFSET_MISMATCH');
    }

    // C6: Valid opening type / marker.
    final validMarker = entry.entryType == 'adjustment' &&
        (entry.id.startsWith('entry-open-') ||
            entry.description.startsWith('Opening Balance') ||
            entry.legacySourceTxId == openTag ||
            (entry.legacySourceTxId?.startsWith(openRevPrefix) ?? false));
    if (!validMarker) failed.add('C6_INVALID_MARKER');

    // C7: Clean provenance tag or null.
    final tag = entry.legacySourceTxId;
    final tagOk =
        tag == null || tag == openTag || tag.startsWith(openRevPrefix);
    if (!tagOk) failed.add('C7_TAG_MISMATCH');

    return failed;
  }
}
