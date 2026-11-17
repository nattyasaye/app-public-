import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/database_persistence_coordinator.dart';
import 'package:personal_management_app/data/database/raw_database_recovery_exporter.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';
import 'package:personal_management_app/services/backup/encryption_backup_service.dart';
import 'package:personal_management_app/ui/app_state.dart';

import 'support/sqlite_test_helper.dart';

void _createV6Schema(dynamic rawDb) {
  final existing = rawDb.select(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='accounts_table'",
  );
  if (existing.isNotEmpty) return;

  rawDb.execute('''
    CREATE TABLE inbox_items (
      id TEXT NOT NULL PRIMARY KEY,
      raw_text TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT 'general',
      is_processed INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE goals (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL,
      description TEXT,
      target_date TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      created_at INTEGER NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE projects (
      id TEXT NOT NULL PRIMARY KEY,
      goal_id TEXT REFERENCES goals (id) ON DELETE SET NULL,
      title TEXT NOT NULL,
      description TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      target_date TEXT,
      created_at INTEGER NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE milestones (
      id TEXT NOT NULL PRIMARY KEY,
      project_id TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      due_date TEXT,
      is_completed INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE tasks (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL,
      description TEXT,
      status TEXT NOT NULL DEFAULT 'inbox',
      priority TEXT NOT NULL DEFAULT 'medium',
      due_date TEXT,
      scheduled_date TEXT,
      estimated_duration_minutes INTEGER,
      project_id TEXT REFERENCES projects (id) ON DELETE SET NULL,
      milestone_id TEXT REFERENCES milestones (id) ON DELETE SET NULL,
      subtasks_json TEXT NOT NULL DEFAULT '[]',
      labels_json TEXT NOT NULL DEFAULT '[]',
      is_pinned INTEGER NOT NULL DEFAULT 0,
      is_my_day INTEGER NOT NULL DEFAULT 0,
      recurrence_rule TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE notes (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT 'general',
      project_id TEXT REFERENCES projects (id) ON DELETE SET NULL,
      goal_id TEXT REFERENCES goals (id) ON DELETE SET NULL,
      tags_json TEXT NOT NULL DEFAULT '[]',
      is_pinned INTEGER NOT NULL DEFAULT 0,
      is_favorite INTEGER NOT NULL DEFAULT 0,
      is_archived INTEGER NOT NULL DEFAULT 0,
      is_trashed INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE calendar_events (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL,
      date_iso TEXT NOT NULL,
      end_date_iso TEXT,
      start_time TEXT,
      end_time TEXT,
      is_all_day INTEGER NOT NULL DEFAULT 0,
      category TEXT NOT NULL DEFAULT 'personal',
      color_hex TEXT NOT NULL DEFAULT '#1B4D3E',
      has_reminder INTEGER NOT NULL DEFAULT 0,
      notes TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE financial_categories (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      color_hex TEXT NOT NULL DEFAULT '#4CAF50',
      parent_id TEXT,
      sort_order INTEGER NOT NULL DEFAULT 0,
      is_default INTEGER NOT NULL DEFAULT 0,
      is_archived INTEGER NOT NULL DEFAULT 0
    );
  ''');
  rawDb.execute('''
    CREATE TABLE financial_transactions (
      id TEXT NOT NULL PRIMARY KEY,
      category_id TEXT NOT NULL REFERENCES financial_categories (id),
      amount_cents INTEGER NOT NULL,
      type TEXT NOT NULL,
      transaction_date TEXT NOT NULL,
      note TEXT,
      payee TEXT,
      account_id TEXT,
      destination_account_id TEXT,
      is_superseded INTEGER NOT NULL DEFAULT 0,
      corrected_from_id TEXT,
      correction_reason TEXT,
      created_at INTEGER NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE financial_commitments (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL,
      amount_cents INTEGER NOT NULL,
      due_date TEXT NOT NULL,
      is_paid INTEGER NOT NULL DEFAULT 0,
      recurring_rule TEXT,
      linked_account_id TEXT REFERENCES accounts_table (id) ON DELETE SET NULL,
      category_id TEXT REFERENCES financial_categories (id) ON DELETE SET NULL,
      linked_debt_id TEXT REFERENCES debts_table (id) ON DELETE SET NULL,
      settlement_entry_id TEXT REFERENCES journal_entries_table (id) ON DELETE SET NULL,
      recurring_rule_id TEXT,
      created_at INTEGER NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE savings_goals (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL,
      target_cents INTEGER NOT NULL,
      current_allocated_cents INTEGER NOT NULL DEFAULT 0,
      target_date TEXT,
      linked_account_id TEXT REFERENCES accounts_table (id) ON DELETE SET NULL,
      created_at INTEGER NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE reminders (
      id TEXT NOT NULL PRIMARY KEY,
      target_id TEXT NOT NULL,
      target_type TEXT NOT NULL,
      trigger_time_utc INTEGER NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE app_settings (
      key TEXT NOT NULL PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE accounts_table (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      sub_type TEXT NOT NULL DEFAULT 'cash',
      is_system INTEGER NOT NULL DEFAULT 0,
      currency_code TEXT NOT NULL DEFAULT 'ETB',
      opening_balance_cents INTEGER NOT NULL DEFAULT 0,
      opening_balance_date TEXT,
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE parties_table (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      phone TEXT,
      notes TEXT,
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE journal_entries_table (
      id TEXT NOT NULL PRIMARY KEY,
      entry_type TEXT NOT NULL,
      description TEXT NOT NULL,
      occurrence_date TEXT NOT NULL,
      is_voided INTEGER NOT NULL DEFAULT 0,
      void_reason TEXT,
      legacy_source_tx_id TEXT,
      corrected_from_entry_id TEXT,
      created_at INTEGER NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE postings_table (
      id TEXT NOT NULL PRIMARY KEY,
      entry_id TEXT NOT NULL REFERENCES journal_entries_table (id) ON DELETE CASCADE,
      account_id TEXT NOT NULL REFERENCES accounts_table (id),
      amount_cents INTEGER NOT NULL,
      direction TEXT NOT NULL,
      account_movement_date TEXT NOT NULL,
      category_id TEXT REFERENCES financial_categories (id),
      note TEXT
    );
  ''');
  rawDb.execute('''
    CREATE TABLE debts_table (
      id TEXT NOT NULL PRIMARY KEY,
      origin_entry_id TEXT NOT NULL REFERENCES journal_entries_table (id),
      party_id TEXT NOT NULL REFERENCES parties_table (id),
      debt_type TEXT NOT NULL,
      principal_cents INTEGER NOT NULL,
      outstanding_cents INTEGER NOT NULL,
      due_date TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      created_at INTEGER NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE settlement_allocations_table (
      id TEXT NOT NULL PRIMARY KEY,
      settlement_entry_id TEXT NOT NULL REFERENCES journal_entries_table (id),
      debt_id TEXT NOT NULL REFERENCES debts_table (id),
      allocated_cents INTEGER NOT NULL,
      settlement_date TEXT NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE budgets_table (
      id TEXT NOT NULL PRIMARY KEY,
      category_id TEXT NOT NULL REFERENCES financial_categories (id) ON DELETE CASCADE,
      month_iso TEXT NOT NULL,
      limit_cents INTEGER NOT NULL,
      rollover_enabled INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
  ''');
  rawDb.execute('''
    CREATE TABLE recurring_rules_table (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL,
      rule_type TEXT NOT NULL,
      amount_cents INTEGER NOT NULL,
      frequency TEXT NOT NULL,
      interval INTEGER NOT NULL DEFAULT 1,
      start_date TEXT NOT NULL,
      next_occurrence_date TEXT NOT NULL,
      end_date TEXT,
      account_id TEXT REFERENCES accounts_table (id) ON DELETE SET NULL,
      destination_account_id TEXT REFERENCES accounts_table (id) ON DELETE SET NULL,
      category_id TEXT REFERENCES financial_categories (id) ON DELETE SET NULL,
      linked_debt_id TEXT REFERENCES debts_table (id) ON DELETE SET NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      auto_post INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    );
  ''');
}

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage 4.2-4.5 Schema v7, Hardener, Repository & Cold Recovery', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('daywell_v7_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      '1. Enforces SQLite ON DELETE RESTRICT across all finance FKs under PRAGMA foreign_keys = ON',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        final repo = DriftFinanceRepository(db);

        await repo.completeFinanceSetup([
          AccountModel(
            id: 'acc-cbe',
            name: 'CBE',
            type: AccountType.asset,
            subType: AccountSubType.bank,
            openingBalanceCents: 500000,
            openingBalanceDate: '2026-11-01',
          ),
        ]);
        final cats = await repo.getCategories();
        final expCat = cats.firstWhere((c) => c.type == 'expense');
        final subCat = await repo.createCategory(
          id: 'cat-sub-coffee',
          name: 'Coffee',
          type: 'expense',
          parentId: expCat.id,
        );
        final entry = await repo.recordDirectExpense(
          accountId: 'acc-cbe',
          categoryId: subCat.id,
          amountCents: 10000,
          date: CalendarDate(year: 2026, month: 11, day: 5),
          description: 'Macchiato',
        );
        final party = await repo.createParty(
          PartyModel(id: 'party-abebe', name: 'Abebe'),
        );
        final borrow = DoubleEntryEngine.buildBorrowMoney(
          entryId: 'entry-borrow',
          debtId: 'debt-1',
          partyId: party.id,
          destAssetAccountId: 'acc-cbe',
          payableAccountId: SystemControlAccounts.payable,
          amountCents: 200000,
          date: '2026-11-06',
          description: 'Loan',
        );
        await repo.recordDebtWithEntry(
          entry: borrow['entry'] as JournalEntryModel,
          postings: borrow['postings'] as List<PostingModel>,
          debt: borrow['debt'] as DebtModel,
        );
        await repo.upsertBudget(
          BudgetModel(
            id: 'bud-coffee',
            categoryId: subCat.id,
            monthIso: '2026-11',
            limitCents: 50000,
          ),
        );
        await repo.upsertRecurringRule(
          RecurringRuleModel(
            id: 'rec-1',
            title: 'Monthly Loan',
            ruleType: RecurringRuleType.commitment,
            amountCents: 50000,
            frequency: RecurrenceFrequency.monthly,
            startDate: CalendarDate(year: 2026, month: 11, day: 15),
            nextOccurrenceDate: CalendarDate(year: 2026, month: 11, day: 15),
            accountId: 'acc-cbe',
            categoryId: subCat.id,
            linkedDebtId: 'debt-1',
          ),
        );
        await repo.processDueRecurringRules(
          asOfDate: CalendarDate(year: 2026, month: 11, day: 15),
        );
        final com = (await repo.getCommitments()).single;
        await repo.recordCommitmentSettlement(
          commitmentId: com.id,
          accountId: 'acc-cbe',
          amountCents: 25000,
          settledDate: CalendarDate(year: 2026, month: 11, day: 16),
        );

        Future<void> expectRestrictFailure(String sql) async {
          await expectLater(
            db.customStatement(sql),
            throwsA(anything),
          );
        }

        // Raw DELETEs must fail via SQLite RESTRICT (never cascade or null!)
        await expectRestrictFailure(
          "DELETE FROM journal_entries_table WHERE id = '${entry.id}'",
        );
        await expectRestrictFailure(
          "DELETE FROM accounts_table WHERE id = 'acc-cbe'",
        );
        await expectRestrictFailure(
          "DELETE FROM financial_categories WHERE id = '${expCat.id}'",
        );
        await expectRestrictFailure(
          "DELETE FROM financial_categories WHERE id = '${subCat.id}'",
        );
        await expectRestrictFailure(
          "DELETE FROM parties_table WHERE id = 'party-abebe'",
        );
        await expectRestrictFailure(
          "DELETE FROM debts_table WHERE id = 'debt-1'",
        );
        await expectRestrictFailure(
          "DELETE FROM recurring_rules_table WHERE id = 'rec-1'",
        );
        await expectRestrictFailure(
          "DELETE FROM financial_commitments WHERE id = '${com.id}'",
        );

        // Edit-form explicit unlink removes FK link cleanly without deleting
        await repo.updateCategory(subCat.id, clearParentId: true);
        final updatedSub =
            (await repo.getCategories()).firstWhere((c) => c.id == subCat.id);
        expect(updatedSub.parentId, isNull);

        await db.close();
      },
    );

    test(
      '2. Level 0-3 v6->v7 upgrade cleans orphans, recreates indices, preserves DDL without temp names, and produces convergence report',
      () async {
        final dbFile = File(p.join(tempDir.path, 'v6_to_v7_upgrade.sqlite'));
        const ts = 1794304800;

        final db = AppDatabase(
          NativeDatabase(
            dbFile,
            setup: (rawDb) {
              if (rawDb
                  .select(
                    "SELECT name FROM sqlite_master WHERE type='table' AND name='accounts_table'",
                  )
                  .isNotEmpty) {
                return;
              }
              _createV6Schema(rawDb);
              rawDb.execute('''
                INSERT INTO financial_categories (id, name, type, parent_id, color_hex)
                VALUES ('cat-orphan', 'Sub', 'expense', 'missing-parent', '#112233');
                INSERT INTO accounts_table (id, name, type, sub_type, currency_code, opening_balance_cents, opening_balance_date, created_at) VALUES
                  ('acc-cbe', 'CBE', 'asset', 'bank', 'ETB', 400000, '2026-11-01', $ts),
                  ('acc-usd', 'USD Travel', 'asset', 'cash', 'USD', 50000, '2026-11-01', $ts);
                INSERT INTO parties_table (id, name, created_at)
                VALUES ('party-sara', 'Sara', $ts);
                INSERT INTO journal_entries_table (id, entry_type, description, occurrence_date, is_voided, legacy_source_tx_id, created_at) VALUES
                  ('entry-open-acc-cbe', 'adjustment', 'Opening Balance for CBE', '2026-11-01', 0, 'open:acc-cbe', $ts),
                  ('entry-manual-adj', 'adjustment', 'Cash Count Adjustment', '2026-11-02', 0, NULL, ${ts + 1}),
                  ('entry-lend', 'debtIssuance', 'Lent Sara', '2026-11-03', 0, NULL, ${ts + 2}),
                  ('entry-wo', 'writeOff', 'Bad debt write-off', '2026-11-04', 0, NULL, ${ts + 3});
                INSERT INTO accounts_table (id, name, type, sub_type, is_system, currency_code, created_at) VALUES
                  ('acc-sys-equity', 'Opening Balances', 'equity', 'opening_equity', 1, 'ETB', $ts),
                  ('acc-sys-receivable', 'Receivable', 'asset', 'receivable', 1, 'ETB', $ts),
                  ('acc-sys-expense', 'Expense', 'expense', 'nominal_expense', 1, 'ETB', $ts);
                INSERT INTO postings_table (id, entry_id, account_id, amount_cents, direction, account_movement_date) VALUES
                  ('p-o1', 'entry-open-acc-cbe', 'acc-cbe', 400000, 'debit', '2026-11-01'),
                  ('p-o2', 'entry-open-acc-cbe', 'acc-sys-equity', 400000, 'credit', '2026-11-01'),
                  ('p-a1', 'entry-manual-adj', 'acc-cbe', 5000, 'credit', '2026-11-02'),
                  ('p-a2', 'entry-manual-adj', 'acc-sys-expense', 5000, 'debit', '2026-11-02'),
                  ('p-l1', 'entry-lend', 'acc-sys-receivable', 100000, 'debit', '2026-11-03'),
                  ('p-l2', 'entry-lend', 'acc-cbe', 100000, 'credit', '2026-11-03'),
                  ('p-w1', 'entry-wo', 'acc-sys-expense', 100000, 'debit', '2026-11-04'),
                  ('p-w2', 'entry-wo', 'acc-sys-receivable', 100000, 'credit', '2026-11-04');
                INSERT INTO debts_table (id, origin_entry_id, party_id, debt_type, principal_cents, outstanding_cents, status, created_at)
                VALUES ('debt-wo', 'entry-lend', 'party-sara', 'receivable', 100000, 0, 'writtenOff', ${ts + 2});
                INSERT INTO financial_commitments (id, title, amount_cents, due_date, is_paid, settlement_entry_id, recurring_rule_id, created_at)
                VALUES ('com-legacy-paid', 'Legacy Utility', 20000, '2026-11-05', 1, NULL, 'missing-rule', $ts);
              ''');
              rawDb.execute('PRAGMA user_version = 6;');
            },
          ),
        );

        await db.ensureInitialized();

        // Check SQLite DDL free of temporary Drift migration names
        final ddlRows = await db
            .customSelect(
              "SELECT name, sql FROM sqlite_master "
              "WHERE type IN ('table', 'index') AND sql IS NOT NULL",
            )
            .get();
        for (final r in ddlRows) {
          final sql = r.read<String>('sql');
          expect(sql.contains('tmp_for_copy'), isFalse);
          expect(sql.contains('old_'), isFalse);
        }

        // Indices exist
        final idxNames = ddlRows.map((r) => r.read<String>('name')).toSet();
        expect(idxNames.contains('idx_journal_legacy_source'), isTrue);
        expect(idxNames.contains('idx_commitments_direction_paid'), isTrue);
        expect(
            idxNames.contains('idx_commitment_settlements_commitment'), isTrue);

        // Orphan parent/rule links cleaned safely & foreign_key_check empty
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );

        final repo = DriftFinanceRepository(db);
        // Normal manual adjustment must NOT cause opening balance error or duplication!
        final openHist = await repo.getOpeningBalanceHistory('acc-cbe');
        expect(openHist.length, 1);

        // Debt normalized 'writtenOff' -> 'written_off' and linked writeOffEntryId
        final debtWo = (await repo.getDebts()).single;
        expect(debtWo.status, DebtStatus.writtenOff);
        expect(debtWo.writeOffEntryId, 'entry-wo');

        // Voiding write-off restores active debt receivable!
        await repo.voidJournalEntry(
          entryId: 'entry-wo',
          voidReason: 'Sara promised payment',
        );
        final restoredDebt = (await repo.getDebts()).single;
        expect(restoredDebt.status, DebtStatus.active);
        expect(restoredDebt.outstandingCents, 100000);

        // Legacy unverified paid commitment flagged accurately & excluded from cash
        final com = (await repo.getCommitments()).single;
        expect(com.legacyPaidUnverified, isTrue);
        expect(com.recurringRuleId, isNull);
        expect(com.status, CommitmentStatus.legacyUnverifiedPaid);

        // Migration report recorded cleanly without false-positive manual-adj error
        final report = await repo.getLatestMigrationReport();
        expect(report, isNotNull);
        expect(report!.hasErrors, isFalse);
        expect(report.legacyPaidFlaggedCount, 1);
        expect(
          report.warnings
              .any((w) => w.contains('ORPHANED_CATEGORY_PARENT_CLEARED')),
          isTrue,
        );
        expect(
          report.warnings.any((w) => w.contains('NON_ETB_ACCOUNT_FLAGGED')),
          isTrue,
        );

        // Reject writing to non-ETB account
        await expectLater(
          repo.recordDirectExpense(
            accountId: 'acc-usd',
            categoryId: 'cat-orphan',
            amountCents: 100,
            date: CalendarDate(year: 2026, month: 11, day: 10),
            description: 'Coffee USD',
          ),
          throwsA(isA<DoubleEntryValidationError>()),
        );

        await db.close();
      },
    );

    test(
      '3. Misconfigured PRAGMA foreign_keys = ON before v6->v7 upgrade throws LedgerMigrationException cleanly',
      () async {
        final dbFile = File(p.join(tempDir.path, 'fk_pre_enabled.sqlite'));
        final db = AppDatabase(
          NativeDatabase(
            dbFile,
            setup: (rawDb) {
              if (rawDb
                  .select(
                    "SELECT name FROM sqlite_master WHERE type='table' AND name='accounts_table'",
                  )
                  .isEmpty) {
                _createV6Schema(rawDb);
                rawDb.execute('PRAGMA user_version = 6;');
              }
              rawDb.execute('PRAGMA foreign_keys = ON;');
            },
          ),
        );

        await expectLater(
          db.ensureInitialized(),
          throwsA(isA<LedgerMigrationException>()),
        );
        await db.close();
      },
    );

    test(
      '4. Snapshot convergence across v5/v6/v7 + immutable :rev:n 1x balance + voidDebtOrigin guard',
      () async {
        // Test :rev:n create -> rev:2 -> 0 -> rev:3 produces exact 1x counting
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        final repo = DriftFinanceRepository(db);

        await repo.completeFinanceSetup([
          AccountModel(
            id: 'acc-cbe',
            name: 'CBE',
            type: AccountType.asset,
            subType: AccountSubType.bank,
            openingBalanceCents: 100000, // 1,000 ETB
            openingBalanceDate: '2026-11-01',
          ),
        ]);

        // rev:2 -> 1,500 ETB
        await repo.reviseOpeningBalance(
          accountId: 'acc-cbe',
          newOpeningBalanceCents: 150000,
          reason: 'Pass 2',
        );
        // rev -> 0 (voids active entry cleanly)
        await repo.reviseOpeningBalance(
          accountId: 'acc-cbe',
          newOpeningBalanceCents: 0,
          reason: 'Zero out',
        );
        var entries = await repo.getJournalEntries(includeVoided: true);
        var postings = await repo.getPostings();
        var acc = (await repo.getAccounts()).single;
        expect(
          DoubleEntryEngine.calculateAccountBalance(
            account: acc,
            postings: postings,
            entries: entries,
          ),
          0,
        );

        // rev:3 -> 800 ETB
        await repo.reviseOpeningBalance(
          accountId: 'acc-cbe',
          newOpeningBalanceCents: 80000,
          reason: 'Restore 800 ETB',
        );
        entries = await repo.getJournalEntries(includeVoided: true);
        postings = await repo.getPostings();
        acc = (await repo.getAccounts()).single;
        expect(
          DoubleEntryEngine.calculateAccountBalance(
            account: acc,
            postings: postings,
            entries: entries,
          ),
          80000,
        );

        final openChain = await repo.getOpeningBalanceHistory('acc-cbe');
        expect(openChain.length, 3);
        expect(openChain.where((e) => !e.isVoided).single.legacySourceTxId,
            'open:acc-cbe:rev:3');
        expect(openChain.every((e) => e.legacySourceTxId != null), isTrue);

        // Deprecated non-ledger markCommitmentPaid is strictly blocked
        await repo.addCommitment(
          CommitmentModel(
            id: 'com-block',
            title: 'Internet',
            amountCents: 50000,
            dueDate: CalendarDate(year: 2026, month: 11, day: 15),
          ),
        );
        await expectLater(
          // ignore: deprecated_member_use_from_same_package
          repo.markCommitmentPaid('com-block', createExpenseTransaction: false),
          throwsUnsupportedError,
        );

        // Debt voidDebtOrigin blocked while active settlement exists
        final party =
            await repo.createParty(PartyModel(id: 'p-1', name: 'Mulu'));
        final lend = DoubleEntryEngine.buildLendMoney(
          entryId: 'je-lend-1',
          debtId: 'd-1',
          partyId: party.id,
          receivableAccountId: SystemControlAccounts.receivable,
          sourceAssetAccountId: 'acc-cbe',
          amountCents: 50000,
          date: '2026-11-05',
          description: 'Lent Mulu',
        );
        final savedDebt = await repo.recordDebtWithEntry(
          entry: lend['entry'] as JournalEntryModel,
          postings: lend['postings'] as List<PostingModel>,
          debt: lend['debt'] as DebtModel,
        );
        final settle = DoubleEntryEngine.buildDebtSettlement(
          settlementEntryId: 'je-set-1',
          debt: savedDebt,
          settlementAssetAccountId: 'acc-cbe',
          debtAccountId: SystemControlAccounts.receivable,
          allocatedPrincipalCents: 20000,
          settlementDate: '2026-11-06',
          description: 'Partial repay',
        );
        await repo.recordSettlement(
          allocation: settle['allocation'] as SettlementAllocationModel,
          settlementEntry: settle['entry'] as JournalEntryModel,
          settlementPostings: settle['postings'] as List<PostingModel>,
          updatedDebt: settle['updatedDebt'] as DebtModel,
        );

        await expectLater(
          repo.voidDebtOrigin(debtId: 'd-1', reason: 'Try early void'),
          throwsStateError,
        );
        // Once settlement is voided, voidDebtOrigin succeeds
        await repo.voidJournalEntry(
          entryId: 'je-set-1',
          voidReason: 'Undo payment',
        );
        final voidedOrigin = await repo.voidDebtOrigin(
          debtId: 'd-1',
          reason: 'Never happened',
        );
        expect(voidedOrigin.status, DebtStatus.voided);

        // Export + re-import v7 snapshot round-trip preserves exact state
        final coordinator = DatabasePersistenceCoordinator(db);
        final snap = await coordinator.exportSnapshot();
        await coordinator.importSnapshot(snap);
        final reimportedAudit = await repo.auditDebtControlBalances();
        expect(reimportedAudit.isTierABalanced, isTrue);

        await db.close();
      },
    );

    test(
      '5. Cold WAL/SHM recovery closes failed DB first, exports SHA-256 manifest without Drift, handles corruption quarantine & restores backup',
      () async {
        final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
        final supportDir = Directory(p.join(tempDir.path, 'support'))
          ..createSync();
        final dbFile = File(p.join(docsDir.path, 'personal_management.sqlite'));

        // Seed a valid backup encrypted payload first
        final seedDb = AppDatabase(NativeDatabase(dbFile));
        await seedDb.ensureInitialized();
        final seedRepo = DriftFinanceRepository(seedDb);
        await seedRepo.completeFinanceSetup([
          AccountModel(
            id: 'acc-recovered',
            name: 'Recovered CBE',
            type: AccountType.asset,
            subType: AccountSubType.bank,
            openingBalanceCents: 250000,
            openingBalanceDate: '2026-11-01',
          ),
        ]);
        final snapJson = jsonEncode(
            await DatabasePersistenceCoordinator(seedDb).exportSnapshot());
        final encryptedEnvelope =
            await EncryptionBackupService().encryptDatabasePayload(
          rawDatabaseJson: snapJson,
          passphrase: 'recover-password',
          schemaVersion: seedDb.schemaVersion,
        );
        await seedDb.close();

        // Corrupt main sqlite header + leave non-empty WAL/SHM sidecars
        await dbFile.writeAsBytes(List<int>.filled(64, 0xFF), flush: true);
        await File('${dbFile.path}-wal')
            .writeAsBytes(List<int>.filled(32, 0xAA), flush: true);
        await File('${dbFile.path}-shm')
            .writeAsBytes(List<int>.filled(16, 0xBB), flush: true);

        final exporter = RawDatabaseRecoveryExporter(
          documentsDirProvider: () async => docsDir,
          supportDirProvider: () async => supportDir,
        );
        final manager = AppStateManager(
          databaseBuilder: () => AppDatabase(NativeDatabase(dbFile)),
          recoveryExporter: exporter,
        );

        await manager.initialize();

        expect(manager.isInitialized, isFalse);
        expect(manager.startupFailure, isNotNull);
        expect(manager.startupFailure!.isCorruption, isTrue);
        expect(manager.startupFailure!.canRetryUpgrade, isFalse);
        expect(manager.startupFailure!.fileInventory?.walBytes, 32);
        expect(manager.startupFailure!.fileInventory?.shmBytes, 16);

        // Diagnostic file persisted cleanly
        final diagOnDisk = await exporter.readFailureDiagnostic();
        expect(diagOnDisk, isNotNull);
        expect(diagOnDisk!.isCorruption, isTrue);

        // Blind retry on corruption does nothing
        await manager.retryInitialize();
        expect(manager.isInitialized, isFalse);

        // Cold export creates verified SHA-256 bundle including .sqlite, -wal, -shm
        final exportDest = Directory(p.join(tempDir.path, 'exports'))
          ..createSync();
        final bundle = await manager.exportRawRecoveryBundle(exportDest);
        expect(bundle.verified, isTrue);
        expect(
          bundle.entries.map((e) => e.fileName).toSet(),
          containsAll({
            'personal_management.sqlite',
            'personal_management.sqlite-wal',
            'personal_management.sqlite-shm',
            'migration_last_failure.json',
          }),
        );
        expect(File(bundle.manifestPath).existsSync(), isTrue);

        // Wrong passphrase fails BEFORE touching/deleting quarantined data
        await expectLater(
          manager.restoreEncryptedBackupInRecovery(
            encryptedEnvelopeJson: encryptedEnvelope,
            passphrase: 'wrong-passphrase',
          ),
          throwsA(anything),
        );
        expect(manager.isInitialized, isFalse);

        // Valid restore quarantines corrupt files, restores v7 DB, clears diagnostics
        final ok = await manager.restoreEncryptedBackupInRecovery(
          encryptedEnvelopeJson: encryptedEnvelope,
          passphrase: 'recover-password',
        );
        expect(ok, isTrue);
        expect(manager.isInitialized, isTrue);
        expect(manager.startupFailure, isNull);
        expect(await exporter.readFailureDiagnostic(), isNull);
        expect(manager.liquidCashCents, 250000);

        await manager.disposeAsync();
      },
    );
  });
}
