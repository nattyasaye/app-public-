import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/database_persistence_coordinator.dart';
import 'package:personal_management_app/data/database/v6_ledger_migrator.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';

import 'support/sqlite_test_helper.dart';

void _createV5Schema(dynamic rawDb) {
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
}

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage 4.3 — Schema v5 -> v6 Double-Entry Ledger Migration Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('daywell_v6_mig_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'Fixture 1 (Mixed v5 DB): converts opening balances, 15 income/expense '
      'rows, and 2 paired transfers without duplication or balance drift',
      () async {
        final dbFile = File(p.join(tempDir.path, 'fixture1_v5.sqlite'));
        const ts = 1794304800;

        final db = AppDatabase(
          NativeDatabase(
            dbFile,
            setup: (rawDb) {
              final existing = rawDb.select(
                "SELECT name FROM sqlite_master "
                "WHERE type='table' AND name='accounts_table'",
              );
              if (existing.isNotEmpty) return;
              _createV5Schema(rawDb);

              rawDb.execute('''
                INSERT INTO financial_categories (id, name, type, color_hex) VALUES
                  ('cat-sal', 'Salary', 'income', '#10B981'),
                  ('cat-food', 'Food', 'expense', '#EF4444'),
                  ('cat-xfer', 'Transfer', 'expense', '#0D9488');
              ''');

              // 3 accounts with opening balances and 0 equity journal entries
              rawDb.execute('''
                INSERT INTO accounts_table (id, name, type, opening_balance_cents, opening_balance_date, created_at) VALUES
                  ('acc-cbe', 'Commercial Bank of Ethiopia', 'asset', 1000000, '2026-11-01', $ts),
                  ('acc-telebirr', 'Telebirr Wallet', 'asset', 200000, '2026-11-01', $ts),
                  ('acc-cash', 'Pocket Cash', 'asset', 50000, '2026-11-01', $ts);
              ''');

              // 15 single-entry transactions: 3 incomes (+900,000 to CBE), 12 expenses (-300,000 CBE, -100,000 Telebirr, -20,000 Cash)
              for (int i = 1; i <= 3; i++) {
                rawDb.execute('''
                  INSERT INTO financial_transactions (id, category_id, amount_cents, type, transaction_date, account_id, note, created_at)
                  VALUES ('tx-inc-$i', 'cat-sal', 300000, 'income', '2026-11-0$i', 'acc-cbe', 'Salary batch $i', ${ts + i});
                ''');
              }
              for (int i = 1; i <= 6; i++) {
                rawDb.execute('''
                  INSERT INTO financial_transactions (id, category_id, amount_cents, type, transaction_date, account_id, note, created_at)
                  VALUES ('tx-cbe-exp-$i', 'cat-food', 50000, 'expense', '2026-11-1$i', 'acc-cbe', 'CBE meal $i', ${ts + 10 + i});
                ''');
              }
              for (int i = 1; i <= 4; i++) {
                rawDb.execute('''
                  INSERT INTO financial_transactions (id, category_id, amount_cents, type, transaction_date, account_id, note, created_at)
                  VALUES ('tx-tel-exp-$i', 'cat-food', 25000, 'expense', '2026-11-1$i', 'acc-telebirr', 'Telebirr spend $i', ${ts + 20 + i});
                ''');
              }
              for (int i = 1; i <= 2; i++) {
                rawDb.execute('''
                  INSERT INTO financial_transactions (id, category_id, amount_cents, type, transaction_date, account_id, note, created_at)
                  VALUES ('tx-cash-exp-$i', 'cat-food', 10000, 'expense', '2026-11-2$i', 'acc-cash', 'Coffee $i', ${ts + 30 + i});
                ''');
              }

              // 2 paired transfers: CBE -> Telebirr (150,000), Telebirr -> Cash (30,000)
              rawDb.execute('''
                INSERT INTO financial_transactions (id, category_id, amount_cents, type, transaction_date, account_id, destination_account_id, note, created_at) VALUES
                  ('tx-1001', 'cat-xfer', 150000, 'transfer', '2026-11-15', 'acc-cbe', 'acc-telebirr', 'Top up Telebirr', ${ts + 40}),
                  ('tx-1002', 'cat-xfer', 30000, 'transfer', '2026-11-16', 'acc-telebirr', 'acc-cash', 'ATM cash out', ${ts + 41});
              ''');
              rawDb.execute('''
                INSERT INTO journal_entries_table (id, entry_type, description, occurrence_date, is_voided, created_at) VALUES
                  ('entry-xfer-1001', 'transfer', 'Top up Telebirr', '2026-11-15', 0, ${ts + 40}),
                  ('entry-xfer-1002', 'transfer', 'ATM cash out', '2026-11-16', 0, ${ts + 41});
              ''');
              rawDb.execute('''
                INSERT INTO postings_table (id, entry_id, account_id, amount_cents, direction, account_movement_date) VALUES
                  ('px-1-dr', 'entry-xfer-1001', 'acc-telebirr', 150000, 'debit', '2026-11-15'),
                  ('px-1-cr', 'entry-xfer-1001', 'acc-cbe', 150000, 'credit', '2026-11-15'),
                  ('px-2-dr', 'entry-xfer-1002', 'acc-cash', 30000, 'debit', '2026-11-16'),
                  ('px-2-cr', 'entry-xfer-1002', 'acc-telebirr', 30000, 'credit', '2026-11-16');
              ''');

              rawDb.execute('PRAGMA user_version = 5;');
            },
          ),
        );

        await db.ensureInitialized();

        final repo = DriftFinanceRepository(db);
        final accounts = await repo.getAccounts();
        final entries = await repo.getJournalEntries(includeVoided: true);
        final postings = await repo.getPostings();

        // Expected ledger balances:
        // CBE:      1,000,000 + 900,000 - 300,000 - 150,000 = 1,450,000
        // Telebirr:   200,000 - 100,000 + 150,000 -  30,000 =   220,000
        // Cash:        50,000 -  20,000 +  30,000           =    60,000
        int ledgerBalance(String accountId) {
          final acc = accounts.firstWhere((a) => a.id == accountId);
          return DoubleEntryEngine.calculateAccountBalance(
            account: acc,
            postings: postings,
            entries: entries,
          );
        }

        expect(ledgerBalance('acc-cbe'), 1450000);
        expect(ledgerBalance('acc-telebirr'), 220000);
        expect(ledgerBalance('acc-cash'), 60000);

        // Subtypes inferred properly
        expect(
          accounts.firstWhere((a) => a.id == 'acc-cbe').subType,
          AccountSubType.bank,
        );
        expect(
          accounts.firstWhere((a) => a.id == 'acc-telebirr').subType,
          AccountSubType.mobileMoney,
        );
        expect(
          accounts.firstWhere((a) => a.id == 'acc-cash').subType,
          AccountSubType.cash,
        );

        // No duplicate transfers: only 2 transfer entries exist
        final transferEntries =
            entries.where((e) => e.entryType == EntryType.transfer).toList();
        expect(transferEntries.length, 2);

        // Legacy transactions retained read-only for traceability
        final legacyTxs = await repo.getTransactions();
        expect(legacyTxs.length, 17);

        await db.close();
      },
    );

    test(
      'Fixture 2 (Inconsistent Legacy DB): deduplicates entry-open-*, isolates '
      'null-account payments to acc-sys-legacy-offset, voids superseded chains, '
      'and recalculates stale debt balances',
      () async {
        final dbFile = File(p.join(tempDir.path, 'fixture2_v5.sqlite'));
        const ts = 1794304800;

        final db = AppDatabase(
          NativeDatabase(
            dbFile,
            setup: (rawDb) {
              final existing = rawDb.select(
                "SELECT name FROM sqlite_master "
                "WHERE type='table' AND name='accounts_table'",
              );
              if (existing.isNotEmpty) return;
              _createV5Schema(rawDb);

              rawDb.execute('''
                INSERT INTO financial_categories (id, name, type, color_hex) VALUES
                  ('cat-food', 'Food', 'expense', '#EF4444'),
                  ('cat-xfer', 'Transfer', 'expense', '#0D9488');
              ''');

              // Account with an existing entry-open-* + opening equity account
              rawDb.execute('''
                INSERT INTO accounts_table (id, name, type, opening_balance_cents, opening_balance_date, created_at) VALUES
                  ('acc-cbe', 'CBE Main', 'asset', 500000, '2026-11-01', $ts),
                  ('acc-eq', 'Opening Equity', 'equity', 0, '2026-11-01', $ts),
                  ('acc-rec', 'Receivable Control', 'asset', 0, '2026-11-01', $ts);
              ''');
              rawDb.execute('''
                INSERT INTO journal_entries_table (id, entry_type, description, occurrence_date, is_voided, created_at) VALUES
                  ('entry-open-acc-cbe', 'adjustment', 'Opening Balance for CBE Main', '2026-11-01', 0, $ts);
              ''');
              rawDb.execute('''
                INSERT INTO postings_table (id, entry_id, account_id, amount_cents, direction, account_movement_date) VALUES
                  ('p-open-dr', 'entry-open-acc-cbe', 'acc-cbe', 500000, 'debit', '2026-11-01'),
                  ('p-open-cr', 'entry-open-acc-cbe', 'acc-eq', 500000, 'credit', '2026-11-01');
              ''');

              // Null-account commitment payment (old markCommitmentPaid defect)
              rawDb.execute('''
                INSERT INTO financial_transactions (id, category_id, amount_cents, type, transaction_date, account_id, note, created_at)
                VALUES ('tx-null-com', 'cat-food', 75000, 'expense', '2026-11-05', NULL, 'Paid commitment: Internet', ${ts + 1});
              ''');

              // Partially recorded transfer missing entry-xfer-*, destination null
              rawDb.execute('''
                INSERT INTO financial_transactions (id, category_id, amount_cents, type, transaction_date, account_id, destination_account_id, note, created_at)
                VALUES ('tx-partial-xfer', 'cat-xfer', 40000, 'transfer', '2026-11-06', 'acc-cbe', NULL, 'Unlinked transfer', ${ts + 2});
              ''');

              // 3-step superseded correction chain (tx-1 -> tx-2 -> tx-3 active)
              rawDb.execute('''
                INSERT INTO financial_transactions (id, category_id, amount_cents, type, transaction_date, account_id, is_superseded, corrected_from_id, correction_reason, created_at) VALUES
                  ('tx-chain-1', 'cat-food', 10000, 'expense', '2026-11-07', 'acc-cbe', 1, NULL, 'Wrong amount', ${ts + 3}),
                  ('tx-chain-2', 'cat-food', 12000, 'expense', '2026-11-07', 'acc-cbe', 1, 'tx-chain-1', 'Still wrong', ${ts + 4}),
                  ('tx-chain-3', 'cat-food', 15000, 'expense', '2026-11-07', 'acc-cbe', 0, 'tx-chain-2', 'Final amount', ${ts + 5});
              ''');

              // Stale Debt whose settlement entry was voided
              rawDb.execute('''
                INSERT INTO parties_table (id, name, created_at) VALUES ('party-1', 'Abebe', $ts);
                INSERT INTO journal_entries_table (id, entry_type, description, occurrence_date, is_voided, created_at) VALUES
                  ('entry-lend-1', 'debtIssuance', 'Lent cash', '2026-11-02', 0, $ts),
                  ('entry-settle-1', 'settlement', 'Voided settlement', '2026-11-04', 1, ${ts + 1});
                INSERT INTO postings_table (id, entry_id, account_id, amount_cents, direction, account_movement_date) VALUES
                  ('p-l-dr', 'entry-lend-1', 'acc-rec', 100000, 'debit', '2026-11-02'),
                  ('p-l-cr', 'entry-lend-1', 'acc-cbe', 100000, 'credit', '2026-11-02'),
                  ('p-s-dr', 'entry-settle-1', 'acc-cbe', 100000, 'debit', '2026-11-04'),
                  ('p-s-cr', 'entry-settle-1', 'acc-rec', 100000, 'credit', '2026-11-04');
                INSERT INTO debts_table (id, origin_entry_id, party_id, debt_type, principal_cents, outstanding_cents, status, created_at)
                VALUES ('debt-stale-1', 'entry-lend-1', 'party-1', 'receivable', 100000, 0, 'settled', $ts);
                INSERT INTO settlement_allocations_table (id, settlement_entry_id, debt_id, allocated_cents, settlement_date)
                VALUES ('alloc-voided-1', 'entry-settle-1', 'debt-stale-1', 100000, '2026-11-04');
              ''');

              rawDb.execute('PRAGMA user_version = 5;');
            },
          ),
        );

        await db.ensureInitialized();

        final repo = DriftFinanceRepository(db);
        final allAccounts = await repo.getAccounts(includeSystem: true);
        final cbe = allAccounts.firstWhere((a) => a.id == 'acc-cbe');
        final offsetAcc = allAccounts
            .firstWhere((a) => a.id == SystemControlAccounts.legacyOffset);
        final entries = await repo.getJournalEntries(includeVoided: true);
        final postings = await repo.getPostings();

        // CBE balance must NOT include duplicate opening balance or null-account tx or superseded txs:
        // +500,000 (open) - 40,000 (partial xfer out) - 15,000 (active tx-chain-3) - 100,000 (lend) = 345,000
        expect(
          DoubleEntryEngine.calculateAccountBalance(
            account: cbe,
            postings: postings,
            entries: entries,
          ),
          345000,
        );

        // Null-account tx-null-com (75,000) & partial transfer destination (40,000) routed to legacy offset cleanly
        final legacyOffsetPostings = postings
            .where((p) => p.accountId == SystemControlAccounts.legacyOffset)
            .toList();
        expect(legacyOffsetPostings.length, 2);
        expect(
          DoubleEntryEngine.calculateAccountBalance(
            account: offsetAcc,
            postings: postings,
            entries: entries,
          ),
          isNotNull,
        );

        // Superseded txs marked voided
        final chain1 =
            entries.firstWhere((e) => e.legacySourceTxId == 'tx-chain-1');
        final chain2 =
            entries.firstWhere((e) => e.legacySourceTxId == 'tx-chain-2');
        final chain3 =
            entries.firstWhere((e) => e.legacySourceTxId == 'tx-chain-3');
        expect(chain1.isVoided, isTrue);
        expect(chain2.isVoided, isTrue);
        expect(chain3.isVoided, isFalse);

        // Stale debt repaired from voided settlement
        final repairedDebt =
            (await repo.getDebts()).firstWhere((d) => d.id == 'debt-stale-1');
        expect(repairedDebt.outstandingCents, 100000);
        expect(repairedDebt.status, DebtStatus.active);

        await db.close();
      },
    );

    test(
      'Fixture 3: Idempotency, Atomic Rollback on Corrupt Posting, & v5 Backup Import Round-Trip',
      () async {
        // Part A: Re-running migrateDataInTransaction is strictly idempotent
        final idempFile = File(p.join(tempDir.path, 'fixture3_idemp.sqlite'));
        final db = AppDatabase(NativeDatabase(idempFile));
        await db.ensureInitialized();

        await db.into(db.accountsTable).insert(
              AccountsTableCompanion.insert(
                id: 'acc-user-1',
                name: 'Dashen Bank',
                type: 'asset',
                openingBalanceCents: const Value(250000),
                createdAt: DateTime.utc(2026, 11, 1),
              ),
            );
        await db.transaction(() async {
          await V6LedgerMigrator.migrateDataInTransaction(db);
        });
        final firstEntriesCount =
            (await db.select(db.journalEntriesTable).get()).length;
        final firstPostingsCount =
            (await db.select(db.postingsTable).get()).length;

        await db.transaction(() async {
          await V6LedgerMigrator.migrateDataInTransaction(db);
        });
        expect(
          (await db.select(db.journalEntriesTable).get()).length,
          firstEntriesCount,
        );
        expect(
          (await db.select(db.postingsTable).get()).length,
          firstPostingsCount,
        );
        await db.close();

        // Part B: Unbalanced posting rolls back v5 -> v6 atomically leaving v5 intact
        final rollbackFile =
            File(p.join(tempDir.path, 'fixture3_rollback.sqlite'));
        const ts = 1794304800;
        final badDb = AppDatabase(
          NativeDatabase(
            rollbackFile,
            setup: (rawDb) {
              final existing = rawDb.select(
                "SELECT name FROM sqlite_master "
                "WHERE type='table' AND name='accounts_table'",
              );
              if (existing.isNotEmpty) return;
              _createV5Schema(rawDb);
              rawDb.execute('''
                INSERT INTO accounts_table (id, name, type, created_at)
                VALUES ('acc-1', 'Cash', 'asset', $ts), ('acc-2', 'Exp', 'expense', $ts);
                INSERT INTO journal_entries_table (id, entry_type, description, occurrence_date, created_at)
                VALUES ('je-unbalanced', 'standard', 'Corrupt entry', '2026-11-10', $ts);
                INSERT INTO postings_table (id, entry_id, account_id, amount_cents, direction, account_movement_date)
                VALUES ('p-bad-1', 'je-unbalanced', 'acc-1', 5000, 'credit', '2026-11-10');
              ''');
              rawDb.execute('PRAGMA user_version = 5;');
            },
          ),
        );
        await expectLater(
            badDb.ensureInitialized(), throwsA(isA<StateError>()));
        await badDb.close();

        final rawVerify = sqlite3.open(rollbackFile.path);
        expect(
            rawVerify.select('PRAGMA user_version;').single['user_version'], 5);
        rawVerify.dispose();

        // Part C: Importing a v5 JSON backup into a fresh v6 DB auto-upgrades to v6 ledger
        final backupFile = File(p.join(tempDir.path, 'fixture3_backup.sqlite'));
        final targetDb = AppDatabase(NativeDatabase(backupFile));
        await targetDb.ensureInitialized();

        final coordinator = DatabasePersistenceCoordinator(targetDb);
        await coordinator.importSnapshot({
          'schemaVersion': 5,
          'isFinanceSetupCompleted': true,
          'accounts': [
            {
              'id': 'acc-v5-cash',
              'name': 'Cash Drawer',
              'type': 'asset',
              'openingBalanceCents': 300000,
              'openingBalanceDate': '2026-11-01',
              'createdAt': '2026-11-01T00:00:00.000Z',
            },
          ],
          'categories': [
            {
              'id': 'cat-food',
              'name': 'Food',
              'type': 'expense',
              'colorHex': '#EF4444',
            },
          ],
          'transactions': [
            {
              'id': 'tx-v5-1',
              'categoryId': 'cat-food',
              'amountCents': 50000,
              'type': 'expense',
              'transactionDate': '2026-11-05',
              'accountId': 'acc-v5-cash',
              'note': 'Dinner',
            },
          ],
        });

        final restoredRepo = DriftFinanceRepository(targetDb);
        final restoredAccs = await restoredRepo.getAccounts();
        final restoredEntries =
            await restoredRepo.getJournalEntries(includeVoided: true);
        final restoredPostings = await restoredRepo.getPostings();

        expect(restoredAccs.single.id, 'acc-v5-cash');
        expect(
          DoubleEntryEngine.calculateAccountBalance(
            account: restoredAccs.single,
            postings: restoredPostings,
            entries: restoredEntries,
          ),
          250000,
        );
        await targetDb.close();
      },
    );
  });
}
