import 'dart:io';

import 'package:drift/drift.dart' show MigrationStrategy, Migrator, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/interfaces/platform_service_interfaces.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/database_persistence_coordinator.dart';
import 'package:personal_management_app/data/database/raw_database_recovery_exporter.dart';
import 'package:personal_management_app/data/repositories/calendar_repository.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';
import 'package:personal_management_app/data/repositories/inbox_repository.dart';
import 'package:personal_management_app/data/repositories/notes_repository.dart';
import 'package:personal_management_app/data/repositories/tasks_repository.dart';
import 'package:personal_management_app/ui/app_state.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Native SQLite Schema v5 & Non-Destructive Migration Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('daywell_migration_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      '1. Fresh installation creates all 24 v9 tables, indices, '
      'FK enforcement, system control accounts, and 11 starter categories',
      () async {
        final dbFile = File(p.join(tempDir.path, 'fresh_v9.sqlite'));
        final db = AppDatabase(NativeDatabase(dbFile));

        await db.ensureInitialized();

        final versionRows = await db.customSelect('PRAGMA user_version').get();
        expect(versionRows.single.read<int>('user_version'), 9);

        final reminderCols =
            await db.customSelect("PRAGMA table_info('reminders')").get();
        expect(
          reminderCols.map((r) => r.read<String>('name')).toSet(),
          containsAll(<String>[
            'id',
            'target_id',
            'target_type',
            'title',
            'channel_id',
          ]),
        );

        final projectCols =
            await db.customSelect("PRAGMA table_info('projects')").get();
        expect(
          projectCols.map((r) => r.read<String>('name')).toSet(),
          containsAll(<String>[
            'id',
            'goal_id',
            'title',
            'description',
            'status',
            'target_date',
            'is_archived',
            'start_date',
            'custom_fields_json',
            'created_at',
            'updated_at',
          ]),
        );

        final fkRows = await db.customSelect('PRAGMA foreign_keys').get();
        expect(fkRows.single.read<int>('foreign_keys'), 1);

        final tableRows = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' "
              "AND name NOT LIKE 'sqlite_%'",
            )
            .get();
        final tableNames =
            tableRows.map((row) => row.read<String>('name')).toSet();

        expect(
          tableNames,
          containsAll(<String>[
            'inbox_items',
            'goals',
            'projects',
            'milestones',
            'tasks',
            'notes',
            'calendar_events',
            'financial_categories',
            'financial_transactions',
            'financial_commitments',
            'commitment_settlements_table',
            'savings_goals',
            'reminders',
            'app_settings',
            'accounts_table',
            'parties_table',
            'journal_entries_table',
            'postings_table',
            'debts_table',
            'settlement_allocations_table',
            'budgets_table',
            'recurring_rules_table',
            'project_tracking_blocks',
            'project_tracking_records',
          ]),
        );
        expect(tableNames.length, 24);

        final indexRows = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='index' "
              "AND name LIKE 'idx_%'",
            )
            .get();
        final indexNames =
            indexRows.map((row) => row.read<String>('name')).toSet();
        expect(
          indexNames,
          containsAll(<String>[
            'idx_tasks_due_date',
            'idx_tasks_status',
            'idx_transactions_date',
            'idx_inbox_processed',
            'idx_calendar_events_date',
            'idx_postings_entry_id',
            'idx_postings_account_id',
            'idx_journal_entries_date_voided',
            'idx_journal_legacy_source',
            'idx_debts_party_status',
            'idx_commitments_due_paid',
            'idx_commitments_direction_paid',
            'idx_commitment_settlements_commitment',
            'idx_budgets_month_category',
            'idx_project_blocks_project_sort',
            'idx_project_records_project_block',
            'idx_project_records_parent',
            'idx_project_records_recorded_date',
            'idx_project_records_linked_task',
          ]),
        );

        final repo = DriftFinanceRepository(db);
        final categories = await repo.getCategories();
        expect(categories.length, 11);

        // User accounts remain 0 while the 6 system control accounts are provisioned.
        expect(await repo.getAccounts(), isEmpty);
        final allAccounts = await repo.getAccounts(includeSystem: true);
        expect(allAccounts.length, 6);
        expect(allAccounts.every((a) => a.isSystem), isTrue);

        final settings = await repo.getFinanceSettings();
        expect(settings.isSetupCompleted, isFalse);

        final sentinelRow = await (db.select(db.appSettings)
              ..where((tbl) => tbl.key.equals(AppDatabase.seedSentinelKey)))
            .getSingleOrNull();
        expect(sentinelRow?.value, 'true');

        // Re-running ensureInitialized() must remain idempotent with no dupes
        await db.ensureInitialized();
        final categoriesAfterSecondCall = await repo.getCategories();
        expect(categoriesAfterSecondCall.length, 11);
        expect((await repo.getAccounts(includeSystem: true)).length, 6);

        final calCols =
            await db.customSelect("PRAGMA table_info('calendar_events')").get();
        final calColNames =
            calCols.map((row) => row.read<String>('name')).toSet();
        expect(calColNames, contains('end_date_iso'));

        await db.close();
      },
    );

    test(
      '2. Real v3 -> v5 upgrade preserves Finance, Tasks, Notes, and Inbox '
      'records without data loss or duplicates',
      () async {
        final dbFile = File(p.join(tempDir.path, 'legacy_v3.sqlite'));
        const epochSec = 1762732800; // 2025-11-10T00:00:00Z

        final migratedDb = AppDatabase(
          NativeDatabase(
            dbFile,
            setup: (rawDb) {
              final existing = rawDb.select(
                "SELECT name FROM sqlite_master "
                "WHERE type='table' AND name='tasks'",
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
                  target_date INTEGER,
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
                  target_date INTEGER,
                  created_at INTEGER NOT NULL
                );
              ''');

              rawDb.execute('''
                CREATE TABLE milestones (
                  id TEXT NOT NULL PRIMARY KEY,
                  project_id TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
                  title TEXT NOT NULL,
                  due_date INTEGER,
                  is_completed INTEGER NOT NULL DEFAULT 0,
                  created_at INTEGER NOT NULL
                );
              ''');

              // Schema v3 tasks (without v4 subtasks_json/labels_json/is_pinned/is_my_day/recurrence_rule)
              rawDb.execute('''
                CREATE TABLE tasks (
                  id TEXT NOT NULL PRIMARY KEY,
                  title TEXT NOT NULL,
                  description TEXT,
                  status TEXT NOT NULL DEFAULT 'inbox',
                  priority TEXT NOT NULL DEFAULT 'medium',
                  due_date INTEGER,
                  scheduled_date INTEGER,
                  estimated_duration_minutes INTEGER,
                  project_id TEXT REFERENCES projects (id) ON DELETE SET NULL,
                  milestone_id TEXT REFERENCES milestones (id) ON DELETE SET NULL,
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL
                );
              ''');

              // Schema v3 notes (without v4 tags_json/is_pinned/is_favorite/is_archived/is_trashed)
              rawDb.execute('''
                CREATE TABLE notes (
                  id TEXT NOT NULL PRIMARY KEY,
                  title TEXT NOT NULL,
                  content TEXT NOT NULL,
                  category TEXT NOT NULL DEFAULT 'general',
                  project_id TEXT REFERENCES projects (id) ON DELETE SET NULL,
                  goal_id TEXT REFERENCES goals (id) ON DELETE SET NULL,
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL
                );
              ''');

              // Schema v3 financial_categories (without v4 is_archived)
              rawDb.execute('''
                CREATE TABLE financial_categories (
                  id TEXT NOT NULL PRIMARY KEY,
                  name TEXT NOT NULL,
                  type TEXT NOT NULL,
                  color_hex TEXT NOT NULL DEFAULT '#4CAF50',
                  is_default INTEGER NOT NULL DEFAULT 0
                );
              ''');

              // Schema v3 financial_transactions (without v4 account/correction columns)
              rawDb.execute('''
                CREATE TABLE financial_transactions (
                  id TEXT NOT NULL PRIMARY KEY,
                  category_id TEXT NOT NULL REFERENCES financial_categories (id),
                  amount_cents INTEGER NOT NULL,
                  type TEXT NOT NULL,
                  transaction_date INTEGER NOT NULL,
                  note TEXT,
                  payee TEXT,
                  created_at INTEGER NOT NULL
                );
              ''');

              rawDb.execute('''
                CREATE TABLE financial_commitments (
                  id TEXT NOT NULL PRIMARY KEY,
                  title TEXT NOT NULL,
                  amount_cents INTEGER NOT NULL,
                  due_date INTEGER NOT NULL,
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
                  target_date INTEGER,
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

              // Seed pre-existing v3 user data across all modules
              rawDb.execute('''
                INSERT INTO financial_categories (id, name, type, color_hex, is_default)
                VALUES ('cat-v3-sal', 'Salary v3', 'income', '#1B4D3E', 1),
                       ('cat-v3-food', 'Coffee v3', 'expense', '#B45309', 0);
              ''');

              rawDb.execute('''
                INSERT INTO accounts_table (id, name, type, currency_code, opening_balance_cents, opening_balance_date, is_archived, created_at)
                VALUES ('acc-v3-cbe', 'CBE Main', 'asset', 'ETB', 150000, '2025-11-10', 0, $epochSec),
                       ('acc-v3-exp', 'Expense Bucket', 'expense', 'ETB', 0, '2025-11-10', 0, $epochSec);
              ''');

              rawDb.execute('''
                INSERT INTO financial_transactions (id, category_id, amount_cents, type, transaction_date, note, payee, created_at)
                VALUES ('tx-v3-1', 'cat-v3-food', 25000, 'expense', $epochSec, 'Tomoca espresso', 'Tomoca', $epochSec);
              ''');

              rawDb.execute('''
                INSERT INTO journal_entries_table (id, entry_type, description, occurrence_date, is_voided, void_reason, created_at)
                VALUES ('je-v3-1', 'standard', 'Legacy expense entry', '2025-11-10', 0, NULL, $epochSec);
              ''');

              rawDb.execute('''
                INSERT INTO postings_table (id, entry_id, account_id, amount_cents, direction, account_movement_date, category_id, note)
                VALUES ('post-v3-dr', 'je-v3-1', 'acc-v3-exp', 25000, 'debit', '2025-11-10', 'cat-v3-food', 'Coffee'),
                       ('post-v3-cr', 'je-v3-1', 'acc-v3-cbe', 25000, 'credit', '2025-11-10', NULL, 'Cash out');
              ''');

              rawDb.execute('''
                INSERT INTO goals (id, title, description, status, created_at)
                VALUES ('goal-v3-1', 'Financial Clarity', 'Track ETB daily', 'active', $epochSec);
              ''');

              rawDb.execute('''
                INSERT INTO projects (id, goal_id, title, description, status, created_at)
                VALUES ('proj-v3-1', 'goal-v3-1', 'Legacy Project', 'Created under v3', 'active', $epochSec);
              ''');

              rawDb.execute('''
                INSERT INTO milestones (id, project_id, title, is_completed, created_at)
                VALUES ('ms-v3-1', 'proj-v3-1', 'V3 Milestone', 1, $epochSec);
              ''');

              rawDb.execute('''
                INSERT INTO tasks (id, title, description, status, priority, project_id, milestone_id, created_at, updated_at)
                VALUES ('task-v3-1', 'Pay utility bill', 'Keep receipt', 'in_progress', 'high', 'proj-v3-1', 'ms-v3-1', $epochSec, $epochSec);
              ''');

              rawDb.execute('''
                INSERT INTO notes (id, title, content, category, project_id, goal_id, created_at, updated_at)
                VALUES ('note-v3-1', 'የዕለት ማስታወሻ', 'ትኩረት ማድረግ ያለብኝ ጉዳይ', 'reflection', 'proj-v3-1', 'goal-v3-1', $epochSec, $epochSec);
              ''');

              rawDb.execute('''
                INSERT INTO inbox_items (id, raw_text, category, is_processed, created_at)
                VALUES ('inbox-v3-1', 'Call solar technician', 'task', 0, $epochSec);
              ''');

              rawDb.execute('''
                INSERT INTO app_settings (key, value, updated_at)
                VALUES ('opening_balance_cents', '150000', $epochSec),
                       ('is_finance_setup_completed', 'true', $epochSec);
              ''');

              rawDb.execute('PRAGMA user_version = 3;');
            },
          ),
        );

        await migratedDb.ensureInitialized();

        // 1. Upgraded schema version & FK integrity
        final versionRows =
            await migratedDb.customSelect('PRAGMA user_version').get();
        expect(versionRows.single.read<int>('user_version'), 8);

        final fkCheckRows =
            await migratedDb.customSelect('PRAGMA foreign_key_check').get();
        expect(fkCheckRows, isEmpty);

        // 2. Existing user categories preserved (starter seeding skipped)
        final financeRepo = DriftFinanceRepository(migratedDb);
        final categories =
            await financeRepo.getCategories(includeArchived: true);
        expect(categories.length, 2);
        expect(
          categories.map((c) => c.id),
          containsAll(<String>['cat-v3-sal', 'cat-v3-food']),
        );
        expect(categories.every((c) => c.isArchived == false), isTrue);

        final accounts = await financeRepo.getAccounts(includeArchived: true);
        expect(accounts.length, 1);
        expect(
          accounts.firstWhere((a) => a.id == 'acc-v3-cbe').openingBalanceCents,
          150000,
        );
        final allAccountsIncludingSystem = await financeRepo.getAccounts(
          includeArchived: true,
          includeSystem: true,
        );
        expect(
          allAccountsIncludingSystem.map((a) => a.id),
          containsAll(<String>['acc-v3-cbe', 'acc-v3-exp']),
        );

        final txs = await financeRepo.getTransactions();
        expect(txs.length, 1);
        expect(txs.single.id, 'tx-v3-1');
        expect(txs.single.amountCents, 25000);
        expect(
          txs.single.transactionDate,
          CalendarDate(year: 2025, month: 11, day: 10),
        );
        expect(txs.single.isSuperseded, isFalse);
        expect(txs.single.accountId, isNull);

        // Postings include legacy je-v3-1 (2), opening entry for acc-v3-cbe (2),
        // and migrated tx-v3-1 (2).
        final postings = await financeRepo.getPostings();
        expect(postings.length, 6);
        expect(postings.where((p) => p.entryId == 'je-v3-1').length, 2);

        // 3. v3 Task & defaults preserved accurately
        final tasksRepo = DriftTasksRepository(migratedDb);
        final tasks = await tasksRepo.getTasks();
        expect(tasks.length, 1);
        final v3Task = tasks.single;
        expect(v3Task.id, 'task-v3-1');
        expect(v3Task.title, 'Pay utility bill');
        expect(v3Task.projectId, 'proj-v3-1');
        expect(v3Task.milestoneId, 'ms-v3-1');
        expect(v3Task.subtasks, isEmpty);
        expect(v3Task.labels, isEmpty);
        expect(v3Task.isPinned, isFalse);
        expect(v3Task.isMyDay, isFalse);
        expect(v3Task.recurrenceRule, isNull);

        // 4. v3 Note (including Amharic UTF-8) & defaults preserved accurately
        final notesRepo = DriftNotesRepository(migratedDb);
        final notes = await notesRepo.getNotes(
          includeArchived: true,
          includeTrashed: true,
        );
        expect(notes.length, 1);
        final v3Note = notes.single;
        expect(v3Note.id, 'note-v3-1');
        expect(v3Note.title, 'የዕለት ማስታወሻ');
        expect(v3Note.tags, isEmpty);
        expect(v3Note.isPinned, isFalse);
        expect(v3Note.isFavorite, isFalse);
        expect(v3Note.isArchived, isFalse);
        expect(v3Note.isTrashed, isFalse);

        // 5. v3 Inbox item preserved accurately
        final inboxItems = await DriftInboxRepository(migratedDb)
            .getAllInboxItems(includeProcessed: true);
        expect(inboxItems.length, 1);
        expect(inboxItems.single.rawText, 'Call solar technician');
        expect(inboxItems.single.isProcessed, isFalse);

        // 6. Schema PRAGMA table_info defaults check for newly added v4 columns
        final taskCols =
            await migratedDb.customSelect("PRAGMA table_info('tasks')").get();
        final taskColNames =
            taskCols.map((row) => row.read<String>('name')).toSet();
        expect(
          taskColNames,
          containsAll(<String>[
            'subtasks_json',
            'labels_json',
            'is_pinned',
            'is_my_day',
            'recurrence_rule',
          ]),
        );

        final noteCols =
            await migratedDb.customSelect("PRAGMA table_info('notes')").get();
        final noteColNames =
            noteCols.map((row) => row.read<String>('name')).toSet();
        expect(
          noteColNames,
          containsAll(<String>[
            'tags_json',
            'is_pinned',
            'is_favorite',
            'is_archived',
            'is_trashed',
          ]),
        );

        // 7. New v5 CalendarEvents table & index work immediately post-upgrade
        final calendarRepo = DriftCalendarRepository(migratedDb);
        final now = EthiopiaClock.nowUtc();
        await calendarRepo.createEvent(
          CalendarEventEntity(
            id: 'evt-post-v5',
            title: 'Post-Migration Check',
            dateIso: '2026-11-12',
            startTime: '09:00',
            createdAt: now,
            updatedAt: now,
          ),
        );
        await migratedDb.close();

        // 8. Reopen database at schema v5 without running v3 setup script
        final reopenedDb = AppDatabase(NativeDatabase(dbFile));
        await reopenedDb.ensureInitialized();

        final reopenedVersion =
            await reopenedDb.customSelect('PRAGMA user_version').get();
        expect(reopenedVersion.single.read<int>('user_version'), 8);

        final reopenedEvents =
            await DriftCalendarRepository(reopenedDb).getEvents();
        expect(reopenedEvents.length, 1);
        expect(reopenedEvents.single.title, 'Post-Migration Check');
        expect(
          (await DriftTasksRepository(reopenedDb).getTasks()).single.id,
          'task-v3-1',
        );
        expect(
          (await DriftNotesRepository(reopenedDb).getNotes()).single.id,
          'note-v3-1',
        );
        final reopenedTxs =
            await DriftFinanceRepository(reopenedDb).getTransactions();
        expect(reopenedTxs.single.id, 'tx-v3-1');
        expect(
          reopenedTxs.single.transactionDate,
          CalendarDate(year: 2025, month: 11, day: 10),
        );

        await reopenedDb.close();
      },
    );

    test(
      '3. Real v4 -> v5 upgrade converts legacy timestamps under Ethiopia '
      'UTC+3 to canonical YYYY-MM-DD and adds end_date_iso',
      () async {
        final dbFile = File(p.join(tempDir.path, 'legacy_v4.sqlite'));
        // 2026-11-10T22:00:00Z == 2026-11-11 01:00:00 in Ethiopia (UTC+3).
        const utcEveningEpoch = 1794348000;
        // 2026-11-10T10:00:00Z == 2026-11-10 13:00:00 in Ethiopia (UTC+3).
        const utcDaytimeEpoch = 1794304800;

        final migratedDb = AppDatabase(
          NativeDatabase(
            dbFile,
            setup: (rawDb) {
              final existing = rawDb.select(
                "SELECT name FROM sqlite_master "
                "WHERE type='table' AND name='tasks'",
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
                  target_date INTEGER,
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
                  target_date INTEGER,
                  created_at INTEGER NOT NULL
                );
              ''');
              rawDb.execute('''
                CREATE TABLE milestones (
                  id TEXT NOT NULL PRIMARY KEY,
                  project_id TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
                  title TEXT NOT NULL,
                  due_date INTEGER,
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
                  due_date INTEGER,
                  scheduled_date INTEGER,
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
              // v4 calendar_events (without v5 end_date_iso)
              rawDb.execute('''
                CREATE TABLE calendar_events (
                  id TEXT NOT NULL PRIMARY KEY,
                  title TEXT NOT NULL,
                  date_iso TEXT NOT NULL,
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
                  transaction_date INTEGER NOT NULL,
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
                  due_date INTEGER NOT NULL,
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
                  target_date INTEGER,
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

              // Seed v4 rows with boundary timestamps
              rawDb.execute('''
                INSERT INTO financial_categories (id, name, type, color_hex)
                VALUES ('cat-v4-exp', 'Food', 'expense', '#EF4444');
              ''');
              rawDb.execute('''
                INSERT INTO goals (id, title, target_date, created_at)
                VALUES ('goal-v4', 'Save for laptop', $utcEveningEpoch, $utcDaytimeEpoch);
              ''');
              rawDb.execute('''
                INSERT INTO projects (id, goal_id, title, target_date, created_at)
                VALUES ('proj-v4', 'goal-v4', 'v4 Project', $utcDaytimeEpoch, $utcDaytimeEpoch);
              ''');
              rawDb.execute('''
                INSERT INTO milestones (id, project_id, title, due_date, created_at)
                VALUES ('ms-v4', 'proj-v4', 'v4 Milestone', $utcEveningEpoch, $utcDaytimeEpoch);
              ''');
              rawDb.execute('''
                INSERT INTO tasks (id, title, status, priority, due_date, scheduled_date, project_id, milestone_id, created_at, updated_at)
                VALUES ('task-v4', 'Late UTC night task', 'not_started', 'high', $utcEveningEpoch, $utcDaytimeEpoch, 'proj-v4', 'ms-v4', $utcDaytimeEpoch, $utcDaytimeEpoch);
              ''');
              rawDb.execute('''
                INSERT INTO financial_transactions (id, category_id, amount_cents, type, transaction_date, created_at)
                VALUES ('tx-v4-eve', 'cat-v4-exp', 15000, 'expense', $utcEveningEpoch, $utcDaytimeEpoch),
                       ('tx-v4-day', 'cat-v4-exp', 25000, 'expense', $utcDaytimeEpoch, $utcDaytimeEpoch);
              ''');
              rawDb.execute('''
                INSERT INTO financial_commitments (id, title, amount_cents, due_date, created_at)
                VALUES ('com-v4', 'Rent', 800000, $utcEveningEpoch, $utcDaytimeEpoch);
              ''');
              rawDb.execute('''
                INSERT INTO savings_goals (id, title, target_cents, target_date, created_at)
                VALUES ('sav-v4', 'Emergency', 500000, $utcEveningEpoch, $utcDaytimeEpoch);
              ''');
              rawDb.execute('''
                INSERT INTO calendar_events (id, title, date_iso, created_at, updated_at)
                VALUES ('evt-v4', 'Legacy Single Day', '2026-11-10', $utcDaytimeEpoch, $utcDaytimeEpoch);
              ''');
              rawDb.execute('PRAGMA user_version = 4;');
            },
          ),
        );

        await migratedDb.ensureInitialized();

        final versionRows =
            await migratedDb.customSelect('PRAGMA user_version').get();
        expect(versionRows.single.read<int>('user_version'), 8);

        final fkCheck =
            await migratedDb.customSelect('PRAGMA foreign_key_check').get();
        expect(fkCheck, isEmpty);

        // Verify raw SQLite storage is canonical YYYY-MM-DD in Ethiopia UTC+3
        final txRows = await migratedDb
            .customSelect(
              'SELECT id, transaction_date FROM financial_transactions',
            )
            .get();
        final txDateMap = {
          for (final r in txRows)
            r.read<String>('id'): r.read<String>('transaction_date'),
        };
        expect(txDateMap['tx-v4-eve'], '2026-11-11');
        expect(txDateMap['tx-v4-day'], '2026-11-10');

        final tasksRepo = DriftTasksRepository(migratedDb);
        final migratedTask = (await tasksRepo.getTasks()).single;
        expect(
          migratedTask.dueDate,
          CalendarDate(year: 2026, month: 11, day: 11),
        );
        expect(
          migratedTask.scheduledDate,
          CalendarDate(year: 2026, month: 11, day: 10),
        );

        final financeRepo = DriftFinanceRepository(migratedDb);
        final migratedCommit = (await financeRepo.getCommitments()).single;
        expect(
          migratedCommit.dueDate,
          CalendarDate(year: 2026, month: 11, day: 11),
        );
        final migratedGoal = (await financeRepo.getSavingsGoals()).single;
        expect(
          migratedGoal.targetDate,
          CalendarDate(year: 2026, month: 11, day: 11),
        );

        // Verify legacy event preserved with null endDateIso, and new multi-day event persists
        final calRepo = DriftCalendarRepository(migratedDb);
        final legacyEvt = await calRepo.getEventById('evt-v4');
        expect(legacyEvt, isNotNull);
        expect(legacyEvt!.dateIso, '2026-11-10');
        expect(legacyEvt.endDateIso, isNull);

        await calRepo.createEvent(
          CalendarEventEntity(
            id: 'evt-v5-range',
            title: 'Multi-day Summit',
            dateIso: '2026-11-12',
            endDateIso: '2026-11-14',
          ),
        );
        await migratedDb.close();

        final reopenedDb = AppDatabase(NativeDatabase(dbFile));
        await reopenedDb.ensureInitialized();
        final rangeMatches =
            await DriftCalendarRepository(reopenedDb).getEvents(
          dateIso: '2026-11-13',
        );
        expect(rangeMatches.length, 1);
        expect(rangeMatches.single.id, 'evt-v5-range');
        expect(rangeMatches.single.endDateIso, '2026-11-14');

        await reopenedDb.close();
      },
    );

    test(
      '4. Mixed v4 ms-epochs, bare vs zoned ISO strings, empty optional dates, '
      'and DatabasePersistenceCoordinator Goals/goalId round-trip',
      () async {
        final dbFile = File(p.join(tempDir.path, 'mixed_v4_formats.sqlite'));
        const utcEveningMs =
            1794348000000; // 2026-11-10T22:00:00Z -> 2026-11-11 EAT
        const utcDaytimeSec =
            1794304800; // 2026-11-10T10:00:00Z -> 2026-11-10 EAT

        final db = AppDatabase(
          NativeDatabase(
            dbFile,
            setup: (rawDb) {
              final existing = rawDb.select(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='tasks'",
              );
              if (existing.isNotEmpty) return;
              rawDb.execute(
                  'CREATE TABLE inbox_items (id TEXT NOT NULL PRIMARY KEY, raw_text TEXT NOT NULL, category TEXT NOT NULL DEFAULT \'general\', is_processed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);');
              rawDb.execute(
                  'CREATE TABLE goals (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, description TEXT, target_date TEXT, status TEXT NOT NULL DEFAULT \'active\', created_at INTEGER NOT NULL);');
              rawDb.execute(
                  'CREATE TABLE projects (id TEXT NOT NULL PRIMARY KEY, goal_id TEXT REFERENCES goals (id) ON DELETE SET NULL, title TEXT NOT NULL, description TEXT, status TEXT NOT NULL DEFAULT \'active\', target_date TEXT, created_at INTEGER NOT NULL);');
              rawDb.execute(
                  'CREATE TABLE milestones (id TEXT NOT NULL PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE, title TEXT NOT NULL, due_date INTEGER, is_completed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);');
              rawDb.execute(
                  'CREATE TABLE tasks (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, description TEXT, status TEXT NOT NULL DEFAULT \'inbox\', priority TEXT NOT NULL DEFAULT \'medium\', due_date TEXT, scheduled_date TEXT, estimated_duration_minutes INTEGER, project_id TEXT REFERENCES projects (id) ON DELETE SET NULL, milestone_id TEXT REFERENCES milestones (id) ON DELETE SET NULL, subtasks_json TEXT NOT NULL DEFAULT \'[]\', labels_json TEXT NOT NULL DEFAULT \'[]\', is_pinned INTEGER NOT NULL DEFAULT 0, is_my_day INTEGER NOT NULL DEFAULT 0, recurrence_rule TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);');
              rawDb.execute(
                  'CREATE TABLE notes (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL, category TEXT NOT NULL DEFAULT \'general\', project_id TEXT REFERENCES projects (id) ON DELETE SET NULL, goal_id TEXT REFERENCES goals (id) ON DELETE SET NULL, tags_json TEXT NOT NULL DEFAULT \'[]\', is_pinned INTEGER NOT NULL DEFAULT 0, is_favorite INTEGER NOT NULL DEFAULT 0, is_archived INTEGER NOT NULL DEFAULT 0, is_trashed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);');
              rawDb.execute(
                  'CREATE TABLE calendar_events (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, date_iso TEXT NOT NULL, start_time TEXT, end_time TEXT, is_all_day INTEGER NOT NULL DEFAULT 0, category TEXT NOT NULL DEFAULT \'personal\', color_hex TEXT NOT NULL DEFAULT \'#1B4D3E\', has_reminder INTEGER NOT NULL DEFAULT 0, notes TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);');
              rawDb.execute(
                  'CREATE TABLE financial_categories (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, color_hex TEXT NOT NULL DEFAULT \'#4CAF50\', is_default INTEGER NOT NULL DEFAULT 0, is_archived INTEGER NOT NULL DEFAULT 0);');
              rawDb.execute(
                  'CREATE TABLE financial_transactions (id TEXT NOT NULL PRIMARY KEY, category_id TEXT NOT NULL REFERENCES financial_categories (id), amount_cents INTEGER NOT NULL, type TEXT NOT NULL, transaction_date TEXT NOT NULL, note TEXT, payee TEXT, account_id TEXT, destination_account_id TEXT, is_superseded INTEGER NOT NULL DEFAULT 0, corrected_from_id TEXT, correction_reason TEXT, created_at INTEGER NOT NULL);');
              rawDb.execute(
                  'CREATE TABLE financial_commitments (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, amount_cents INTEGER NOT NULL, due_date INTEGER NOT NULL, is_paid INTEGER NOT NULL DEFAULT 0, recurring_rule TEXT, created_at INTEGER NOT NULL);');
              rawDb.execute(
                  'CREATE TABLE savings_goals (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, target_cents INTEGER NOT NULL, current_allocated_cents INTEGER NOT NULL DEFAULT 0, target_date INTEGER, created_at INTEGER NOT NULL);');
              rawDb.execute(
                  'CREATE TABLE reminders (id TEXT NOT NULL PRIMARY KEY, target_id TEXT NOT NULL, target_type TEXT NOT NULL, trigger_time_utc INTEGER NOT NULL, is_active INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL);');
              rawDb.execute(
                  'CREATE TABLE app_settings (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL);');
              rawDb.execute(
                  'CREATE TABLE accounts_table (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, currency_code TEXT NOT NULL DEFAULT \'ETB\', opening_balance_cents INTEGER NOT NULL DEFAULT 0, opening_balance_date TEXT, is_archived INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);');
              rawDb.execute(
                  'CREATE TABLE parties_table (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, phone TEXT, notes TEXT, is_archived INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);');
              rawDb.execute(
                  'CREATE TABLE journal_entries_table (id TEXT NOT NULL PRIMARY KEY, entry_type TEXT NOT NULL, description TEXT NOT NULL, occurrence_date TEXT NOT NULL, is_voided INTEGER NOT NULL DEFAULT 0, void_reason TEXT, created_at INTEGER NOT NULL);');
              rawDb.execute(
                  'CREATE TABLE postings_table (id TEXT NOT NULL PRIMARY KEY, entry_id TEXT NOT NULL REFERENCES journal_entries_table (id) ON DELETE CASCADE, account_id TEXT NOT NULL REFERENCES accounts_table (id), amount_cents INTEGER NOT NULL, direction TEXT NOT NULL, account_movement_date TEXT NOT NULL, category_id TEXT REFERENCES financial_categories (id), note TEXT);');
              rawDb.execute(
                  'CREATE TABLE debts_table (id TEXT NOT NULL PRIMARY KEY, origin_entry_id TEXT NOT NULL REFERENCES journal_entries_table (id), party_id TEXT NOT NULL REFERENCES parties_table (id), debt_type TEXT NOT NULL, principal_cents INTEGER NOT NULL, outstanding_cents INTEGER NOT NULL, due_date TEXT, status TEXT NOT NULL DEFAULT \'active\', created_at INTEGER NOT NULL);');
              rawDb.execute(
                  'CREATE TABLE settlement_allocations_table (id TEXT NOT NULL PRIMARY KEY, settlement_entry_id TEXT NOT NULL REFERENCES journal_entries_table (id), debt_id TEXT NOT NULL REFERENCES debts_table (id), allocated_cents INTEGER NOT NULL, settlement_date TEXT NOT NULL);');

              rawDb.execute(
                  "INSERT INTO financial_categories (id, name, type, color_hex) VALUES ('cat-1', 'Food', 'expense', '#EF4444');");
              rawDb.execute(
                  "INSERT INTO goals (id, title, target_date, status, created_at) VALUES ('goal-ms', 'Ms Epoch Goal', $utcEveningMs, 'active', $utcDaytimeSec);");
              rawDb.execute(
                  "INSERT INTO projects (id, goal_id, title, target_date, created_at) VALUES ('proj-bare', 'goal-ms', 'Bare ISO Project', '2026-11-10T22:00:00', $utcDaytimeSec);");
              rawDb.execute(
                  "INSERT INTO tasks (id, title, due_date, scheduled_date, project_id, created_at, updated_at) VALUES ('task-mixed', 'Empty vs -0500', '', '2026-11-10T22:00:00-0500', 'proj-bare', $utcDaytimeSec, $utcDaytimeSec);");
              rawDb.execute(
                  "INSERT INTO notes (id, title, content, project_id, goal_id, created_at, updated_at) VALUES ('note-goal', 'Linked Note', 'Preserves goalId', 'proj-bare', 'goal-ms', $utcDaytimeSec, $utcDaytimeSec);");
              rawDb.execute(
                  "INSERT INTO calendar_events (id, title, date_iso, created_at, updated_at) VALUES ('evt-zoned', 'Zoned Event', '2026-11-10T22:00:00Z', $utcDaytimeSec, $utcDaytimeSec);");
              rawDb.execute(
                  "INSERT INTO accounts_table (id, name, type, opening_balance_cents, opening_balance_date, created_at) VALUES ('acc-1', 'CBE', 'asset', 1000, '2026-11-10T21:30:00Z', $utcDaytimeSec);");
              rawDb.execute('PRAGMA user_version = 4;');
            },
          ),
        );

        await db.ensureInitialized();

        final goalRow = await (db.select(db.goals)
              ..where((g) => g.id.equals('goal-ms')))
            .getSingle();
        expect(goalRow.targetDate, '2026-11-11');

        final projRow = await (db.select(db.projects)
              ..where((p) => p.id.equals('proj-bare')))
            .getSingle();
        // Bare local timestamp keeps calendar day 2026-11-10 without double-shifting
        expect(projRow.targetDate, '2026-11-10');
        expect(projRow.goalId, 'goal-ms');

        final taskRow = await (db.select(db.tasks)
              ..where((t) => t.id.equals('task-mixed')))
            .getSingle();
        // Intentionally empty optional TEXT becomes NULL (never 1970-01-01)
        expect(taskRow.dueDate, isNull);
        // 22:00-05:00 == 03:00Z == 06:00 EAT on 2026-11-11
        expect(taskRow.scheduledDate, '2026-11-11');

        final evtRow = await (db.select(db.calendarEvents)
              ..where((e) => e.id.equals('evt-zoned')))
            .getSingle();
        expect(evtRow.dateIso, '2026-11-11');

        final accRow = await (db.select(db.accountsTable)
              ..where((a) => a.id.equals('acc-1')))
            .getSingle();
        expect(accRow.openingBalanceDate, '2026-11-11');

        // Snapshot export & restore round-trip must preserve Goals & goalId links
        final coordinator = DatabasePersistenceCoordinator(db);
        final snapshot = await coordinator.exportSnapshot();
        expect((snapshot['goals'] as List).length, 1);

        await coordinator.importSnapshot(snapshot);
        final restoredProj = await (db.select(db.projects)
              ..where((p) => p.id.equals('proj-bare')))
            .getSingle();
        final restoredNote = await (db.select(db.notes)
              ..where((n) => n.id.equals('note-goal')))
            .getSingle();
        expect(restoredProj.goalId, 'goal-ms');
        expect(restoredNote.goalId, 'goal-ms');

        await db.close();
      },
    );

    test(
      '5. v4 -> v5 aborts atomically on corrupt/garbage nullable or required dates, '
      'never silencing to NULL or today and leaving v4 database completely intact',
      () async {
        const utcDaytimeSec = 1794304800;

        for (final badCase in <({String name, String insertSql})>[
          (
            name: 'corrupt_nullable_garbage',
            insertSql:
                "INSERT INTO tasks (id, title, due_date, created_at, updated_at) "
                "VALUES ('t-bad', 'Corrupt Task', '2026-11-10garbage', $utcDaytimeSec, $utcDaytimeSec);",
          ),
          (
            name: 'corrupt_required_invalid',
            insertSql:
                "INSERT INTO financial_transactions (id, category_id, amount_cents, type, transaction_date, created_at) "
                "VALUES ('tx-bad', 'cat-1', 5000, 'expense', 'invalid', $utcDaytimeSec);",
          ),
        ]) {
          final dbFile = File(p.join(tempDir.path, '${badCase.name}.sqlite'));
          final db = AppDatabase(
            NativeDatabase(
              dbFile,
              setup: (rawDb) {
                final existing = rawDb.select(
                  "SELECT name FROM sqlite_master WHERE type='table' AND name='tasks'",
                );
                if (existing.isNotEmpty) return;
                rawDb.execute(
                    'CREATE TABLE inbox_items (id TEXT NOT NULL PRIMARY KEY, raw_text TEXT NOT NULL, category TEXT NOT NULL DEFAULT \'general\', is_processed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);');
                rawDb.execute(
                    'CREATE TABLE goals (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, description TEXT, target_date TEXT, status TEXT NOT NULL DEFAULT \'active\', created_at INTEGER NOT NULL);');
                rawDb.execute(
                    'CREATE TABLE projects (id TEXT NOT NULL PRIMARY KEY, goal_id TEXT REFERENCES goals (id) ON DELETE SET NULL, title TEXT NOT NULL, description TEXT, status TEXT NOT NULL DEFAULT \'active\', target_date TEXT, created_at INTEGER NOT NULL);');
                rawDb.execute(
                    'CREATE TABLE milestones (id TEXT NOT NULL PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE, title TEXT NOT NULL, due_date INTEGER, is_completed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);');
                rawDb.execute(
                    'CREATE TABLE tasks (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, description TEXT, status TEXT NOT NULL DEFAULT \'inbox\', priority TEXT NOT NULL DEFAULT \'medium\', due_date TEXT, scheduled_date TEXT, estimated_duration_minutes INTEGER, project_id TEXT REFERENCES projects (id) ON DELETE SET NULL, milestone_id TEXT REFERENCES milestones (id) ON DELETE SET NULL, subtasks_json TEXT NOT NULL DEFAULT \'[]\', labels_json TEXT NOT NULL DEFAULT \'[]\', is_pinned INTEGER NOT NULL DEFAULT 0, is_my_day INTEGER NOT NULL DEFAULT 0, recurrence_rule TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);');
                rawDb.execute(
                    'CREATE TABLE notes (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL, category TEXT NOT NULL DEFAULT \'general\', project_id TEXT REFERENCES projects (id) ON DELETE SET NULL, goal_id TEXT REFERENCES goals (id) ON DELETE SET NULL, tags_json TEXT NOT NULL DEFAULT \'[]\', is_pinned INTEGER NOT NULL DEFAULT 0, is_favorite INTEGER NOT NULL DEFAULT 0, is_archived INTEGER NOT NULL DEFAULT 0, is_trashed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);');
                rawDb.execute(
                    'CREATE TABLE calendar_events (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, date_iso TEXT NOT NULL, start_time TEXT, end_time TEXT, is_all_day INTEGER NOT NULL DEFAULT 0, category TEXT NOT NULL DEFAULT \'personal\', color_hex TEXT NOT NULL DEFAULT \'#1B4D3E\', has_reminder INTEGER NOT NULL DEFAULT 0, notes TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);');
                rawDb.execute(
                    'CREATE TABLE financial_categories (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, color_hex TEXT NOT NULL DEFAULT \'#4CAF50\', is_default INTEGER NOT NULL DEFAULT 0, is_archived INTEGER NOT NULL DEFAULT 0);');
                rawDb.execute(
                    'CREATE TABLE financial_transactions (id TEXT NOT NULL PRIMARY KEY, category_id TEXT NOT NULL REFERENCES financial_categories (id), amount_cents INTEGER NOT NULL, type TEXT NOT NULL, transaction_date TEXT NOT NULL, note TEXT, payee TEXT, account_id TEXT, destination_account_id TEXT, is_superseded INTEGER NOT NULL DEFAULT 0, corrected_from_id TEXT, correction_reason TEXT, created_at INTEGER NOT NULL);');
                rawDb.execute(
                    'CREATE TABLE financial_commitments (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, amount_cents INTEGER NOT NULL, due_date INTEGER NOT NULL, is_paid INTEGER NOT NULL DEFAULT 0, recurring_rule TEXT, created_at INTEGER NOT NULL);');
                rawDb.execute(
                    'CREATE TABLE savings_goals (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, target_cents INTEGER NOT NULL, current_allocated_cents INTEGER NOT NULL DEFAULT 0, target_date INTEGER, created_at INTEGER NOT NULL);');
                rawDb.execute(
                    'CREATE TABLE reminders (id TEXT NOT NULL PRIMARY KEY, target_id TEXT NOT NULL, target_type TEXT NOT NULL, trigger_time_utc INTEGER NOT NULL, is_active INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL);');
                rawDb.execute(
                    'CREATE TABLE app_settings (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL);');
                rawDb.execute(
                    'CREATE TABLE accounts_table (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, currency_code TEXT NOT NULL DEFAULT \'ETB\', opening_balance_cents INTEGER NOT NULL DEFAULT 0, opening_balance_date TEXT, is_archived INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);');
                rawDb.execute(
                    'CREATE TABLE parties_table (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, phone TEXT, notes TEXT, is_archived INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);');
                rawDb.execute(
                    'CREATE TABLE journal_entries_table (id TEXT NOT NULL PRIMARY KEY, entry_type TEXT NOT NULL, description TEXT NOT NULL, occurrence_date TEXT NOT NULL, is_voided INTEGER NOT NULL DEFAULT 0, void_reason TEXT, created_at INTEGER NOT NULL);');
                rawDb.execute(
                    'CREATE TABLE postings_table (id TEXT NOT NULL PRIMARY KEY, entry_id TEXT NOT NULL REFERENCES journal_entries_table (id) ON DELETE CASCADE, account_id TEXT NOT NULL REFERENCES accounts_table (id), amount_cents INTEGER NOT NULL, direction TEXT NOT NULL, account_movement_date TEXT NOT NULL, category_id TEXT REFERENCES financial_categories (id), note TEXT);');
                rawDb.execute(
                    'CREATE TABLE debts_table (id TEXT NOT NULL PRIMARY KEY, origin_entry_id TEXT NOT NULL REFERENCES journal_entries_table (id), party_id TEXT NOT NULL REFERENCES parties_table (id), debt_type TEXT NOT NULL, principal_cents INTEGER NOT NULL, outstanding_cents INTEGER NOT NULL, due_date TEXT, status TEXT NOT NULL DEFAULT \'active\', created_at INTEGER NOT NULL);');
                rawDb.execute(
                    'CREATE TABLE settlement_allocations_table (id TEXT NOT NULL PRIMARY KEY, settlement_entry_id TEXT NOT NULL REFERENCES journal_entries_table (id), debt_id TEXT NOT NULL REFERENCES debts_table (id), allocated_cents INTEGER NOT NULL, settlement_date TEXT NOT NULL);');
                rawDb.execute(
                    "INSERT INTO financial_categories (id, name, type, color_hex) VALUES ('cat-1', 'Food', 'expense', '#EF4444');");
                rawDb.execute(badCase.insertSql);
                rawDb.execute('PRAGMA user_version = 4;');
              },
            ),
          );

          await expectLater(db.ensureInitialized(), throwsA(isA<StateError>()));
          await db.close();

          final verifyRaw = sqlite3.open(dbFile.path);
          expect(
              verifyRaw.select('PRAGMA user_version;').single['user_version'],
              4);
          verifyRaw.dispose();
        }
      },
    );
  });

  group('Stage 3.4.3 / Projects Stage 1 Forward Database Migration Safety (v9 Baseline)',
      () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('daywell_stage343_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      '1. Baseline v9 database opens cleanly with PRAGMA foreign_keys = ON '
      'and preserves seeded relational user data',
      () async {
        final dbFile = File(p.join(tempDir.path, 'baseline_v9.sqlite'));
        await _seedRealisticV9Database(dbFile);

        final reopened = AppDatabase(NativeDatabase(dbFile));
        await reopened.ensureInitialized();

        final versionRows =
            await reopened.customSelect('PRAGMA user_version').get();
        expect(versionRows.single.read<int>('user_version'), 9);

        final fkRows = await reopened.customSelect('PRAGMA foreign_keys').get();
        expect(fkRows.single.read<int>('foreign_keys'), 1);

        final fkCheck =
            await reopened.customSelect('PRAGMA foreign_key_check').get();
        expect(fkCheck, isEmpty);

        final tasks = await DriftTasksRepository(reopened).getTasks();
        expect(tasks.length, 1);
        expect(tasks.single.id, 'task-v7-1');
        expect(tasks.single.projectId, 'proj-v7-1');
        expect(tasks.single.milestoneId, 'ms-v7-1');

        final notes = await DriftNotesRepository(reopened).getNotes();
        expect(notes.length, 1);
        expect(notes.single.id, 'note-v7-1');
        expect(notes.single.goalId, 'goal-v7-1');

        final events = await DriftCalendarRepository(reopened).getEvents();
        expect(events.length, 1);
        expect(events.single.id, 'evt-v7-1');

        final financeRepo = DriftFinanceRepository(reopened);
        final accounts = await financeRepo.getAccounts();
        expect(accounts.single.id, 'acc-v7-cbe');
        final postings = await financeRepo.getPostings();
        expect(postings.length, 4);

        final reminders = await reopened.select(reopened.reminders).get();
        expect(reminders.length, 1);
        expect(reminders.single.id, 'rem-v7-1');

        final customSetting = await (reopened.select(reopened.appSettings)
              ..where((tbl) => tbl.key.equals('stage343_user_pref')))
            .getSingleOrNull();
        expect(customSetting?.value, 'ethiopian_calendar');

        await reopened.close();
      },
    );

    test(
      '2. Simulated v9 -> v10 upgrade preserves v9 data, applies defaults, '
      'enforces FKs, and reopens idempotently',
      () async {
        final dbFile = File(p.join(tempDir.path, 'forward_v10.sqlite'));
        await _seedRealisticV9Database(dbFile);

        final upgradedDb = _TestForwardV10Database(NativeDatabase(dbFile));
        await upgradedDb.ensureInitialized();

        expect(upgradedDb.v10UpgradeCalls, 1);
        final versionRows =
            await upgradedDb.customSelect('PRAGMA user_version').get();
        expect(versionRows.single.read<int>('user_version'), 10);

        final fkEnabledRows =
            await upgradedDb.customSelect('PRAGMA foreign_keys').get();
        expect(fkEnabledRows.single.read<int>('foreign_keys'), 1);

        final fkCheck =
            await upgradedDb.customSelect('PRAGMA foreign_key_check').get();
        expect(fkCheck, isEmpty);

        final noteMeta = await upgradedDb
            .customSelect(
              'SELECT id, category, review_status '
              "FROM notes WHERE id = 'note-v7-1'",
            )
            .get();
        expect(noteMeta, hasLength(1));
        expect(noteMeta.single.read<String>('category'), 'reflection');
        expect(noteMeta.single.read<String>('review_status'), 'active');

        final taskMeta = await upgradedDb
            .customSelect(
              'SELECT id, title, effort_points '
              "FROM tasks WHERE id = 'task-v7-1'",
            )
            .getSingle();
        expect(taskMeta.read<String>('title'), 'Review ledger integrity');
        expect(taskMeta.readNullable<int>('effort_points'), isNull);

        final checklists = await upgradedDb
            .customSelect('SELECT id, task_id, label FROM task_checklists_v10')
            .get();
        expect(checklists.length, 1);
        expect(checklists.single.read<String>('id'), 'chk-task-v7-1');
        expect(checklists.single.read<String>('task_id'), 'task-v7-1');

        final financeRepo = DriftFinanceRepository(upgradedDb);
        final accounts = await financeRepo.getAccounts();
        expect(accounts.single.openingBalanceCents, 300000);
        final entries = await financeRepo.getJournalEntries();
        final postings = await financeRepo.getPostings();
        final cbeBalance = DoubleEntryEngine.calculateAccountBalance(
          account: accounts.single,
          postings: postings,
          entries: entries,
        );
        expect(cbeBalance, 255000);

        await expectLater(
          upgradedDb.customStatement(
            "INSERT INTO task_checklists_v10 (id, task_id, label, is_done) "
            "VALUES ('chk-bad', 'nonexistent-task', 'Invalid', 0);",
          ),
          throwsA(
            predicate<Object>(
              (e) => e.toString().toLowerCase().contains('foreign key'),
            ),
          ),
        );
        await upgradedDb.customStatement(
          "INSERT INTO tasks (id, title, status, priority, subtasks_json, "
          "labels_json, is_pinned, is_my_day, created_at, updated_at) "
          "VALUES ('task-temp-fk', 'Disposable', 'not_started', 'low', "
          "'[]', '[]', 0, 0, 1794304800, 1794304800);",
        );
        await upgradedDb.customStatement(
          "INSERT INTO task_checklists_v10 (id, task_id, label, is_done) "
          "VALUES ('chk-temp-fk', 'task-temp-fk', 'Cascades out', 0);",
        );
        await upgradedDb.customStatement(
          "DELETE FROM tasks WHERE id = 'task-temp-fk';",
        );
        final remainingTemp = await upgradedDb
            .customSelect(
              "SELECT id FROM task_checklists_v10 WHERE id = 'chk-temp-fk'",
            )
            .get();
        expect(remainingTemp, isEmpty);

        await upgradedDb.close();

        // Reopen existing v10 database: onUpgrade must NOT re-run
        final reopenedV10 = _TestForwardV10Database(NativeDatabase(dbFile));
        await reopenedV10.ensureInitialized();
        expect(reopenedV10.v10UpgradeCalls, 0);
        final reopenedVersion =
            await reopenedV10.customSelect('PRAGMA user_version').get();
        expect(reopenedVersion.single.read<int>('user_version'), 10);
        expect((await DriftTasksRepository(reopenedV10).getTasks()).length, 1);
        expect((await DriftNotesRepository(reopenedV10).getNotes()).length, 1);
        final reopenedChecklists = await reopenedV10
            .customSelect('SELECT id FROM task_checklists_v10')
            .get();
        expect(reopenedChecklists.length, 1);
        await reopenedV10.close();
      },
    );

    test(
      '3. Deliberate mid-migration failure (DDL + DML throw and FK check '
      'failure) rolls back atomically leaving v9 schema and data intact',
      () async {
        for (final mode in <({String name, bool failMid, bool failFk})>[
          (name: 'mid_upgrade_throw', failMid: true, failFk: false),
          (name: 'fk_check_abort', failMid: false, failFk: true),
        ]) {
          final dbFile = File(p.join(tempDir.path, '${mode.name}.sqlite'));
          await _seedRealisticV9Database(dbFile);

          final failingUpgrade = _TestForwardV10Database(
            NativeDatabase(dbFile),
            failMidV10Migration: mode.failMid,
            failForeignKeyCheckInV10: mode.failFk,
          );

          await expectLater(
            failingUpgrade.ensureInitialized(),
            throwsA(isA<StateError>()),
          );
          await failingUpgrade.close();

          final rawDb = sqlite3.open(dbFile.path);
          try {
            expect(
              rawDb.select('PRAGMA user_version;').single['user_version'],
              9,
            );
            final v10Table = rawDb.select(
              "SELECT name FROM sqlite_master "
              "WHERE type='table' AND name='task_checklists_v10';",
            );
            expect(v10Table, isEmpty);

            final noteCols = rawDb
                .select("PRAGMA table_info('notes');")
                .map((r) => r['name'] as String)
                .toSet();
            expect(noteCols, isNot(contains('review_status')));

            final taskCols = rawDb
                .select("PRAGMA table_info('tasks');")
                .map((r) => r['name'] as String)
                .toSet();
            expect(taskCols, isNot(contains('effort_points')));

            final noteRow = rawDb
                .select("SELECT category FROM notes WHERE id = 'note-v7-1';")
                .single;
            expect(noteRow['category'], 'reflection');

            expect(rawDb.select('PRAGMA foreign_key_check;'), isEmpty);
          } finally {
            rawDb.dispose();
          }

          final recoveredV9 = AppDatabase(NativeDatabase(dbFile));
          await recoveredV9.ensureInitialized();
          final recoveredFkRows =
              await recoveredV9.customSelect('PRAGMA foreign_keys').get();
          expect(recoveredFkRows.single.read<int>('foreign_keys'), 1);
          expect(
            (await DriftTasksRepository(recoveredV9).getTasks()).length,
            1,
          );
          expect(
            (await DriftNotesRepository(recoveredV9).getNotes()).length,
            1,
          );
          await recoveredV9.close();
        }
      },
    );

    test(
      '4. Production v9 AppDatabase and AppStateManager fail closed when '
      'opening a v10 database without modifying user data or user_version',
      () async {
        final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
        final supportDir = Directory(p.join(tempDir.path, 'support'))
          ..createSync();
        final dbFile = File(p.join(docsDir.path, 'personal_management.sqlite'));

        await _seedRealisticV9Database(dbFile);
        final v10Prep = _TestForwardV10Database(NativeDatabase(dbFile));
        await v10Prep.ensureInitialized();
        await v10Prep.close();

        final v10BytesBeforeOpen = dbFile.readAsBytesSync();

        final prodDb = AppDatabase(NativeDatabase(dbFile));
        await expectLater(
          prodDb.ensureInitialized(),
          throwsA(
            isA<UnsupportedDatabaseVersionException>()
                .having((e) => e.fromVersion, 'fromVersion', 10)
                .having((e) => e.toVersion, 'toVersion', 9),
          ),
        );
        await prodDb.close();
        expect(dbFile.readAsBytesSync(), equals(v10BytesBeforeOpen));

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
        expect(
          manager.startupFailure!.category,
          DatabaseFailureCategory.unsupportedSchemaVersion,
        );
        expect(manager.startupFailure!.isUnsupportedSchemaVersion, isTrue);
        expect(manager.startupFailure!.isCorruption, isFalse);
        expect(manager.startupFailure!.canRetryUpgrade, isFalse);
        expect(manager.startupFailure!.rawExportRecommended, isTrue);
        expect(manager.startupFailure!.attemptCount, 1);

        final diagOnDisk = await exporter.readFailureDiagnostic();
        expect(diagOnDisk, isNotNull);
        expect(
          diagOnDisk!.category,
          DatabaseFailureCategory.unsupportedSchemaVersion,
        );
        expect(diagOnDisk.canRetryUpgrade, isFalse);

        await manager.retryInitialize();
        expect(manager.isInitialized, isFalse);
        expect(manager.startupFailure!.attemptCount, 1);

        final exportDest = Directory(p.join(tempDir.path, 'raw_export'))
          ..createSync();
        final bundle = await manager.exportRawRecoveryBundle(exportDest);
        expect(bundle.verified, isTrue);
        expect(
          bundle.entries.map((e) => e.fileName).toSet(),
          containsAll(<String>[
            'personal_management.sqlite',
            'migration_last_failure.json',
          ]),
        );

        await manager.disposeAsync();

        expect(dbFile.existsSync(), isTrue);
        expect(dbFile.readAsBytesSync(), equals(v10BytesBeforeOpen));

        final rawCheck = sqlite3.open(dbFile.path);
        try {
          expect(
            rawCheck.select('PRAGMA user_version;').single['user_version'],
            10,
          );
          expect(
            rawCheck.select('SELECT id FROM task_checklists_v10;').length,
            1,
          );
          expect(rawCheck.select('SELECT id FROM tasks;').length, 1);
          expect(rawCheck.select('SELECT id FROM notes;').length, 1);
        } finally {
          rawCheck.dispose();
        }
      },
    );
  });

  group('Stage 3.4.4.1 Schema v8->v9 Migration & Reminder Fidelity', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('daywell_stage3441_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      '1. Real v7 database upgrades to v9 preserving all reminders with null '
      'title/channelId, valid FKs, and idempotent reopen',
      () async {
        final dbFile = File(p.join(tempDir.path, 'real_v7_to_v9.sqlite'));
        _createRawV7Database(dbFile);

        final migratedDb = AppDatabase(NativeDatabase(dbFile));
        await migratedDb.ensureInitialized();

        final versionRows =
            await migratedDb.customSelect('PRAGMA user_version').get();
        expect(versionRows.single.read<int>('user_version'), 9);
        expect(
          (await migratedDb.customSelect('PRAGMA foreign_keys').get())
              .single
              .read<int>('foreign_keys'),
          1,
        );
        expect(
          await migratedDb.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );

        final reminderCols = (await migratedDb
                .customSelect("PRAGMA table_info('reminders')")
                .get())
            .map((r) => r.read<String>('name'))
            .toSet();
        expect(reminderCols, containsAll(<String>['title', 'channel_id']));

        final reminders = await migratedDb.select(migratedDb.reminders).get();
        expect(reminders.length, 2);
        final byId = {for (final r in reminders) r.id: r};
        expect(byId['rem-v7-task']!.targetId, 'task-v7');
        expect(byId['rem-v7-task']!.targetType, 'task');
        expect(byId['rem-v7-task']!.title, isNull);
        expect(byId['rem-v7-task']!.channelId, isNull);
        expect(byId['rem-v7-task']!.isActive, isTrue);

        expect(byId['rem-v7-custom']!.targetId, 'rem-v7-custom');
        expect(byId['rem-v7-custom']!.targetType, 'custom');
        expect(byId['rem-v7-custom']!.title, isNull);
        expect(byId['rem-v7-custom']!.channelId, isNull);
        expect(byId['rem-v7-custom']!.isActive, isFalse);

        final tasks = await DriftTasksRepository(migratedDb).getTasks();
        expect(tasks.single.id, 'task-v7');
        final accounts = await DriftFinanceRepository(migratedDb).getAccounts();
        expect(accounts.single.id, 'acc-v7');
        await migratedDb.close();

        // Idempotent reopen at v9
        final reopened = AppDatabase(NativeDatabase(dbFile));
        await reopened.ensureInitialized();
        expect(
          (await reopened.customSelect('PRAGMA user_version').get())
              .single
              .read<int>('user_version'),
          9,
        );
        expect(
          await reopened.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        expect((await reopened.select(reopened.reminders).get()).length, 2);
        await reopened.close();
      },
    );

    test(
      '2. New Reminder with title and channelId persists across database '
      'reopen and v9 snapshot export/import round-trip',
      () async {
        final dbFile =
            File(p.join(tempDir.path, 'v9_reminder_roundtrip.sqlite'));
        final db = AppDatabase(NativeDatabase(dbFile));
        await db.ensureInitialized();

        final now = DateTime.utc(2026, 11, 16, 10, 0);
        await db.into(db.reminders).insert(
              RemindersCompanion.insert(
                id: 'rem-v8-new',
                targetId: 'rem-v8-new',
                targetType: 'custom',
                title: const Value('Water Plants'),
                channelId: const Value('daily_habits'),
                triggerTimeUtc: DateTime.utc(2026, 11, 17, 7, 30),
                isActive: const Value(true),
                createdAt: now,
              ),
            );
        await db.close();

        final reopened = AppDatabase(NativeDatabase(dbFile));
        await reopened.ensureInitialized();
        final row = await (reopened.select(reopened.reminders)
              ..where((r) => r.id.equals('rem-v8-new')))
            .getSingle();
        expect(row.title, 'Water Plants');
        expect(row.channelId, 'daily_habits');

        final exported =
            await DatabasePersistenceCoordinator(reopened).exportSnapshot();
        expect(exported['schemaVersion'], 9);
        final exportedRems = (exported['reminders'] as List).cast<Map>();
        expect(exportedRems.single['title'], 'Water Plants');
        expect(exportedRems.single['channelId'], 'daily_habits');
        await reopened.close();

        final freshTarget = AppDatabase(NativeDatabase.memory());
        await freshTarget.ensureInitialized();
        addTearDown(freshTarget.close);
        await DatabasePersistenceCoordinator(freshTarget)
            .importSnapshotDetailed(exported);
        final importedRow =
            await (freshTarget.select(freshTarget.reminders)).getSingle();
        expect(importedRow.id, 'rem-v8-new');
        expect(importedRow.title, 'Water Plants');
        expect(importedRow.channelId, 'daily_habits');
      },
    );

    test(
      '3. Multi-hop v4 -> v9 and v6 -> v9 migrations preserve reminders with '
      'null title/channelId and valid FKs without nested-transaction errors',
      () async {
        // 3a. Multi-hop v6 -> v9
        final v6File = File(p.join(tempDir.path, 'multihop_v6.sqlite'));
        _createRawV6Database(v6File);

        final migratedFromV6 = AppDatabase(NativeDatabase(v6File));
        await migratedFromV6.ensureInitialized();
        expect(
          (await migratedFromV6.customSelect('PRAGMA user_version').get())
              .single
              .read<int>('user_version'),
          9,
        );
        expect(
          await migratedFromV6.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        final v6Reminders =
            await migratedFromV6.select(migratedFromV6.reminders).get();
        expect(v6Reminders.single.id, 'rem-v6-1');
        expect(v6Reminders.single.title, isNull);
        expect(v6Reminders.single.channelId, isNull);
        await migratedFromV6.close();

        // 3b. Multi-hop v4 -> v9
        final v4File = File(p.join(tempDir.path, 'multihop_v4.sqlite'));
        _createRawV4DatabaseWithReminder(v4File);
        final migratedFromV4 = AppDatabase(NativeDatabase(v4File));
        await migratedFromV4.ensureInitialized();
        expect(
          (await migratedFromV4.customSelect('PRAGMA user_version').get())
              .single
              .read<int>('user_version'),
          9,
        );
        expect(
          await migratedFromV4.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        final v4Reminders =
            await migratedFromV4.select(migratedFromV4.reminders).get();
        expect(v4Reminders.single.id, 'rem-v4-1');
        expect(v4Reminders.single.title, isNull);
        expect(v4Reminders.single.channelId, isNull);
        await migratedFromV4.close();
      },
    );

    test(
      '4. Deliberately failed v7 -> v8 migration rolls back atomically '
      'leaving v7 reminders schema (no title/channel_id) and data intact',
      () async {
        final dbFile = File(p.join(tempDir.path, 'v7_to_v8_fail.sqlite'));
        _createRawV7Database(dbFile);

        final failingDb = _TestFailingV8FromV7Database(NativeDatabase(dbFile));
        await expectLater(
          failingDb.ensureInitialized(),
          throwsA(isA<StateError>()),
        );
        await failingDb.close();

        final rawCheck = sqlite3.open(dbFile.path);
        try {
          expect(
            rawCheck.select('PRAGMA user_version;').single['user_version'],
            7,
          );
          final cols = rawCheck
              .select("PRAGMA table_info('reminders');")
              .map((r) => r['name'] as String)
              .toSet();
          expect(cols, isNot(contains('title')));
          expect(cols, isNot(contains('channel_id')));
          expect(rawCheck.select('SELECT id FROM reminders;').length, 2);
          expect(rawCheck.select('PRAGMA foreign_key_check;'), isEmpty);
        } finally {
          rawCheck.dispose();
        }

        // Subsequent real v9 open still succeeds cleanly
        final prodDb = AppDatabase(NativeDatabase(dbFile));
        await prodDb.ensureInitialized();
        expect(
          (await prodDb.select(prodDb.reminders).get()).length,
          2,
        );
        await prodDb.close();
      },
    );
  });

  group('Projects Stage 1 Schema v9 Migration & Coordinator Fidelity', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('daywell_projects_v9_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      '1. Real v8 database upgrades to v9 preserving projects with '
      'is_archived=0, custom_fields_json={}, updated_at=created_at, '
      'new tables, FKs, and idempotent reopen',
      () async {
        final dbFile = File(p.join(tempDir.path, 'real_v8_to_v9.sqlite'));
        _createRawV8Database(dbFile);

        final migratedDb = AppDatabase(NativeDatabase(dbFile));
        await migratedDb.ensureInitialized();

        final versionRows =
            await migratedDb.customSelect('PRAGMA user_version').get();
        expect(versionRows.single.read<int>('user_version'), 9);
        expect(
          await migratedDb.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );

        final projectRow = await migratedDb
            .customSelect(
              'SELECT id, title, is_archived, start_date, custom_fields_json, '
              'created_at, updated_at FROM projects WHERE id = \'proj-v8\';',
            )
            .getSingle();
        expect(projectRow.read<String>('title'), 'v8 Project');
        expect(projectRow.read<int>('is_archived'), 0);
        expect(projectRow.readNullable<String>('start_date'), isNull);
        expect(projectRow.read<String>('custom_fields_json'), '{}');
        expect(
          projectRow.readNullable<int>('updated_at'),
          projectRow.read<int>('created_at'),
        );

        final tableNames = (await migratedDb
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='table' "
                  "AND name IN ('project_tracking_blocks', 'project_tracking_records');",
                )
                .get())
            .map((r) => r.read<String>('name'))
            .toSet();
        expect(
          tableNames,
          equals(<String>{
            'project_tracking_blocks',
            'project_tracking_records',
          }),
        );

        await migratedDb.close();

        // Idempotent reopen at v9
        final reopened = AppDatabase(NativeDatabase(dbFile));
        await reopened.ensureInitialized();
        expect(
          (await reopened.customSelect('PRAGMA user_version').get())
              .single
              .read<int>('user_version'),
          9,
        );
        expect(
          await reopened.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        await reopened.close();
      },
    );

    test(
      '2. Deliberately failed v8 -> v9 migration rolls back atomically '
      'leaving v8 projects schema intact',
      () async {
        final dbFile = File(p.join(tempDir.path, 'v8_to_v9_fail.sqlite'));
        _createRawV8Database(dbFile);

        final failingDb = _TestFailingV9FromV8Database(NativeDatabase(dbFile));
        await expectLater(
          failingDb.ensureInitialized(),
          throwsA(isA<StateError>()),
        );
        await failingDb.close();

        final rawCheck = sqlite3.open(dbFile.path);
        try {
          expect(
            rawCheck.select('PRAGMA user_version;').single['user_version'],
            8,
          );
          final projectCols = rawCheck
              .select("PRAGMA table_info('projects');")
              .map((r) => r['name'] as String)
              .toSet();
          expect(projectCols, isNot(contains('is_archived')));
          expect(projectCols, isNot(contains('custom_fields_json')));
          final v9Tables = rawCheck.select(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name IN ('project_tracking_blocks', 'project_tracking_records');",
          );
          expect(v9Tables, isEmpty);
          expect(rawCheck.select('SELECT id FROM projects;').length, 1);
          expect(rawCheck.select('PRAGMA foreign_key_check;'), isEmpty);
        } finally {
          rawCheck.dispose();
        }

        // Subsequent real v9 open succeeds cleanly
        final prodDb = AppDatabase(NativeDatabase(dbFile));
        await prodDb.ensureInitialized();
        expect(
          (await prodDb.customSelect('PRAGMA user_version').get())
              .single
              .read<int>('user_version'),
          9,
        );
        await prodDb.close();
      },
    );

    test(
      '3. DatabasePersistenceCoordinator round-trips v9 tracking blocks & '
      'unordered records/corrections, accepts v8 snapshots, and rejects cycles fail-closed',
      () async {
        final sourceDb = AppDatabase(NativeDatabase.memory());
        await sourceDb.ensureInitialized();
        addTearDown(sourceDb.close);

        final now = DateTime.utc(2026, 11, 17, 9, 0);
        await sourceDb.into(sourceDb.projects).insert(
              ProjectsCompanion.insert(
                id: 'proj-s1',
                title: 'Video Plan',
                isArchived: const Value(false),
                startDate: const Value('2026-11-10'),
                targetDate: const Value('2026-12-10'),
                customFieldsJson: const Value(
                  '{"primaryBlockId":"blk-1","definitions":[{"id":"topic","label":"Topic","type":"text","required":true}],"values":{"topic":"SQLite"}}',
                ),
                createdAt: now,
                updatedAt: Value(now),
              ),
            );
        await sourceDb.into(sourceDb.projectTrackingBlocks).insert(
              ProjectTrackingBlocksCompanion.insert(
                id: 'blk-1',
                projectId: 'proj-s1',
                blockType: 'grouped_list',
                title: 'Modules',
                sortOrder: const Value(0),
                configJson: const Value('{"showGroupTotals":true}'),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await sourceDb.into(sourceDb.projectTrackingRecords).insert(
              ProjectTrackingRecordsCompanion.insert(
                id: 'grp-1',
                projectId: 'proj-s1',
                blockId: 'blk-1',
                recordType: 'group',
                title: const Value('Core'),
                sortOrder: const Value(0),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await sourceDb.into(sourceDb.projectTrackingRecords).insert(
              ProjectTrackingRecordsCompanion.insert(
                id: 'item-1',
                projectId: 'proj-s1',
                blockId: 'blk-1',
                parentRecordId: const Value('grp-1'),
                recordType: 'grouped_item',
                title: const Value('Lesson 1'),
                sortOrder: const Value(1),
                targetValue: const Value(60),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await sourceDb.into(sourceDb.projectTrackingRecords).insert(
              ProjectTrackingRecordsCompanion.insert(
                id: 'log-1',
                projectId: 'proj-s1',
                blockId: 'blk-1',
                parentRecordId: const Value('item-1'),
                recordType: 'progress_log',
                deltaValue: const Value(30),
                recordedDate: const Value('2026-11-17'),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await sourceDb.into(sourceDb.projectTrackingRecords).insert(
              ProjectTrackingRecordsCompanion.insert(
                id: 'corr-1',
                projectId: 'proj-s1',
                blockId: 'blk-1',
                parentRecordId: const Value('item-1'),
                recordType: 'progress_log',
                deltaValue: const Value(-5),
                recordedDate: const Value('2026-11-17'),
                metadataJson: const Value(
                  '{"isCorrection":true,"compensatesRecordId":"log-1","correctionReason":"Adjusted count"}',
                ),
                createdAt: now,
                updatedAt: now,
              ),
            );

        final exported =
            await DatabasePersistenceCoordinator(sourceDb).exportSnapshot();
        expect(exported['schemaVersion'], 9);
        expect(
          (exported['projectTrackingBlocks'] as List).length,
          1,
        );
        expect(
          (exported['projectTrackingRecords'] as List).length,
          4,
        );

        // Reverse record order in snapshot so correction & child appear before target & parent
        final unorderedSnapshot = Map<String, dynamic>.from(exported);
        unorderedSnapshot['projectTrackingRecords'] =
            (exported['projectTrackingRecords'] as List).reversed.toList();

        final targetDb = AppDatabase(NativeDatabase.memory());
        await targetDb.ensureInitialized();
        addTearDown(targetDb.close);
        await DatabasePersistenceCoordinator(targetDb)
            .importSnapshotDetailed(unorderedSnapshot);

        final importedRecords =
            await targetDb.select(targetDb.projectTrackingRecords).get();
        expect(importedRecords.length, 4);
        expect(
          await targetDb.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );

        // Backward compat: v8 snapshot without tracking arrays imports cleanly
        final v8Snapshot = Map<String, dynamic>.from(exported)
          ..['schemaVersion'] = 8
          ..remove('projectTrackingBlocks')
          ..remove('projectTrackingRecords');
        final v8Res = await DatabasePersistenceCoordinator(targetDb)
            .importSnapshotDetailed(v8Snapshot);
        expect(v8Res.snapshotVersion, 8);
        expect(
          await targetDb.select(targetDb.projectTrackingBlocks).get(),
          isEmpty,
        );
        expect(
          await targetDb.select(targetDb.projectTrackingRecords).get(),
          isEmpty,
        );

        // Fail-closed cyclic parentRecordId rejection leaves targetDb untouched
        final cyclicSnapshot = Map<String, dynamic>.from(exported);
        cyclicSnapshot['projectTrackingRecords'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'c-1',
            'projectId': 'proj-s1',
            'blockId': 'blk-1',
            'parentRecordId': 'c-2',
            'recordType': 'grouped_item',
            'title': 'C1',
            'sortOrder': 0,
            'isCompleted': false,
            'metadata': const <String, dynamic>{},
            'createdAt': '2026-11-17T09:00:00.000Z',
            'updatedAt': '2026-11-17T09:00:00.000Z',
          },
          <String, dynamic>{
            'id': 'c-2',
            'projectId': 'proj-s1',
            'blockId': 'blk-1',
            'parentRecordId': 'c-1',
            'recordType': 'grouped_item',
            'title': 'C2',
            'sortOrder': 1,
            'isCompleted': false,
            'metadata': const <String, dynamic>{},
            'createdAt': '2026-11-17T09:00:00.000Z',
            'updatedAt': '2026-11-17T09:00:00.000Z',
          },
        ];
        await expectLater(
          DatabasePersistenceCoordinator(targetDb)
              .importSnapshotDetailed(cyclicSnapshot),
          throwsA(isA<BackupValidationException>()),
        );
        expect(
          (await targetDb.select(targetDb.projects).get()).length,
          1,
        );
      },
    );
  });
}

void _createRawV7Database(File dbFile) {
  final rawDb = sqlite3.open(dbFile.path);
  const ts = 1794304800; // 2026-11-10T10:00:00Z
  try {
    rawDb.execute('PRAGMA foreign_keys = OFF;');
    rawDb.execute('''
      CREATE TABLE inbox_items (
        id TEXT NOT NULL PRIMARY KEY,
        raw_text TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'general',
        is_processed INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE goals (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        target_date TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        created_at INTEGER NOT NULL
      );
      CREATE TABLE projects (
        id TEXT NOT NULL PRIMARY KEY,
        goal_id TEXT REFERENCES goals (id) ON DELETE SET NULL,
        title TEXT NOT NULL,
        description TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        target_date TEXT,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE milestones (
        id TEXT NOT NULL PRIMARY KEY,
        project_id TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        due_date TEXT,
        is_completed INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
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
      CREATE TABLE financial_categories (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        color_hex TEXT NOT NULL DEFAULT '#4CAF50',
        is_default INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        parent_id TEXT REFERENCES financial_categories (id) ON DELETE RESTRICT,
        sort_order INTEGER NOT NULL DEFAULT 0
      );
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
      CREATE TABLE parties_table (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        notes TEXT,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE journal_entries_table (
        id TEXT NOT NULL PRIMARY KEY,
        entry_type TEXT NOT NULL,
        description TEXT NOT NULL,
        occurrence_date TEXT NOT NULL,
        is_voided INTEGER NOT NULL DEFAULT 0,
        void_reason TEXT,
        legacy_source_tx_id TEXT,
        corrected_from_entry_id TEXT REFERENCES journal_entries_table (id) ON DELETE RESTRICT,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE postings_table (
        id TEXT NOT NULL PRIMARY KEY,
        entry_id TEXT NOT NULL REFERENCES journal_entries_table (id) ON DELETE RESTRICT,
        account_id TEXT NOT NULL REFERENCES accounts_table (id) ON DELETE RESTRICT,
        amount_cents INTEGER NOT NULL,
        direction TEXT NOT NULL,
        account_movement_date TEXT NOT NULL,
        category_id TEXT REFERENCES financial_categories (id) ON DELETE RESTRICT,
        note TEXT
      );
      CREATE TABLE debts_table (
        id TEXT NOT NULL PRIMARY KEY,
        origin_entry_id TEXT NOT NULL REFERENCES journal_entries_table (id) ON DELETE RESTRICT,
        party_id TEXT NOT NULL REFERENCES parties_table (id) ON DELETE RESTRICT,
        debt_type TEXT NOT NULL,
        principal_cents INTEGER NOT NULL,
        outstanding_cents INTEGER NOT NULL,
        due_date TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        write_off_entry_id TEXT REFERENCES journal_entries_table (id) ON DELETE RESTRICT,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE settlement_allocations_table (
        id TEXT NOT NULL PRIMARY KEY,
        settlement_entry_id TEXT NOT NULL REFERENCES journal_entries_table (id) ON DELETE RESTRICT,
        debt_id TEXT NOT NULL REFERENCES debts_table (id) ON DELETE RESTRICT,
        allocated_cents INTEGER NOT NULL,
        settlement_date TEXT NOT NULL
      );
      CREATE TABLE budgets_table (
        id TEXT NOT NULL PRIMARY KEY,
        category_id TEXT NOT NULL REFERENCES financial_categories (id) ON DELETE RESTRICT,
        month_iso TEXT NOT NULL,
        limit_cents INTEGER NOT NULL,
        rollover_enabled INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
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
        account_id TEXT REFERENCES accounts_table (id) ON DELETE RESTRICT,
        destination_account_id TEXT REFERENCES accounts_table (id) ON DELETE RESTRICT,
        category_id TEXT REFERENCES financial_categories (id) ON DELETE RESTRICT,
        linked_debt_id TEXT REFERENCES debts_table (id) ON DELETE RESTRICT,
        is_active INTEGER NOT NULL DEFAULT 1,
        auto_post INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE financial_transactions (
        id TEXT NOT NULL PRIMARY KEY,
        category_id TEXT NOT NULL REFERENCES financial_categories (id) ON DELETE RESTRICT,
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
      CREATE TABLE financial_commitments (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        amount_cents INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        is_paid INTEGER NOT NULL DEFAULT 0,
        direction TEXT NOT NULL DEFAULT 'outflow',
        legacy_paid_unverified INTEGER NOT NULL DEFAULT 0,
        recurring_rule TEXT,
        linked_account_id TEXT REFERENCES accounts_table (id) ON DELETE RESTRICT,
        category_id TEXT REFERENCES financial_categories (id) ON DELETE RESTRICT,
        linked_debt_id TEXT REFERENCES debts_table (id) ON DELETE RESTRICT,
        settlement_entry_id TEXT REFERENCES journal_entries_table (id) ON DELETE RESTRICT,
        recurring_rule_id TEXT REFERENCES recurring_rules_table (id) ON DELETE RESTRICT,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE commitment_settlements_table (
        id TEXT NOT NULL PRIMARY KEY,
        commitment_id TEXT NOT NULL REFERENCES financial_commitments (id) ON DELETE RESTRICT,
        entry_id TEXT NOT NULL REFERENCES journal_entries_table (id) ON DELETE RESTRICT,
        amount_cents INTEGER NOT NULL,
        settled_date TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE savings_goals (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        target_cents INTEGER NOT NULL,
        current_allocated_cents INTEGER NOT NULL DEFAULT 0,
        target_date TEXT,
        linked_account_id TEXT REFERENCES accounts_table (id) ON DELETE RESTRICT,
        status TEXT NOT NULL DEFAULT 'active',
        created_at INTEGER NOT NULL
      );
      CREATE TABLE reminders (
        id TEXT NOT NULL PRIMARY KEY,
        target_id TEXT NOT NULL,
        target_type TEXT NOT NULL,
        trigger_time_utc INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE app_settings (
        key TEXT NOT NULL PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    rawDb.execute('''
      INSERT INTO goals (id, title, created_at) VALUES ('goal-v7', 'v7 Goal', $ts);
      INSERT INTO projects (id, goal_id, title, created_at) VALUES ('proj-v7', 'goal-v7', 'v7 Project', $ts);
      INSERT INTO tasks (id, title, project_id, created_at, updated_at) VALUES ('task-v7', 'v7 Task', 'proj-v7', $ts, $ts);
      INSERT INTO financial_categories (id, name, type) VALUES ('cat-other-exp', 'Other Expense', 'expense');
      INSERT INTO accounts_table (id, name, type, sub_type, is_system, opening_balance_cents, opening_balance_date, created_at)
      VALUES ('acc-v7', 'Cash', 'asset', 'cash', 0, 300000, '2026-11-01', $ts),
             ('acc-sys-equity', 'Opening Equity', 'equity', 'opening_equity', 1, 0, NULL, $ts);
      INSERT INTO journal_entries_table (id, entry_type, description, occurrence_date, legacy_source_tx_id, created_at)
      VALUES ('je-open', 'adjustment', 'Opening', '2026-11-01', 'open:acc-v7', $ts);
      INSERT INTO postings_table (id, entry_id, account_id, amount_cents, direction, account_movement_date)
      VALUES ('p-1', 'je-open', 'acc-v7', 300000, 'debit', '2026-11-01'),
             ('p-2', 'je-open', 'acc-sys-equity', 300000, 'credit', '2026-11-01');
      INSERT INTO reminders (id, target_id, target_type, trigger_time_utc, is_active, created_at)
      VALUES ('rem-v7-task', 'task-v7', 'task', $ts, 1, $ts),
             ('rem-v7-custom', 'rem-v7-custom', 'custom', $ts, 0, $ts);
      INSERT INTO app_settings (key, value, updated_at)
      VALUES ('initial_seed_completed', 'true', $ts),
             ('is_finance_setup_completed', 'true', $ts),
             ('opening_balance_cents', '300000', $ts),
             ('v6_ledger_migrated', 'true', $ts);
      PRAGMA user_version = 7;
    ''');
  } finally {
    rawDb.dispose();
  }
}

void _createRawV6Database(File dbFile) {
  final rawDb = sqlite3.open(dbFile.path);
  const ts = 1794304800;
  try {
    rawDb.execute('PRAGMA foreign_keys = OFF;');
    rawDb.execute('''
      CREATE TABLE inbox_items (id TEXT NOT NULL PRIMARY KEY, raw_text TEXT NOT NULL, category TEXT NOT NULL DEFAULT 'general', is_processed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
      CREATE TABLE goals (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, description TEXT, target_date TEXT, status TEXT NOT NULL DEFAULT 'active', created_at INTEGER NOT NULL);
      CREATE TABLE projects (id TEXT NOT NULL PRIMARY KEY, goal_id TEXT REFERENCES goals (id) ON DELETE SET NULL, title TEXT NOT NULL, description TEXT, status TEXT NOT NULL DEFAULT 'active', target_date TEXT, created_at INTEGER NOT NULL);
      CREATE TABLE milestones (id TEXT NOT NULL PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE, title TEXT NOT NULL, due_date TEXT, is_completed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
      CREATE TABLE tasks (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, description TEXT, status TEXT NOT NULL DEFAULT 'inbox', priority TEXT NOT NULL DEFAULT 'medium', due_date TEXT, scheduled_date TEXT, estimated_duration_minutes INTEGER, project_id TEXT REFERENCES projects (id) ON DELETE SET NULL, milestone_id TEXT REFERENCES milestones (id) ON DELETE SET NULL, subtasks_json TEXT NOT NULL DEFAULT '[]', labels_json TEXT NOT NULL DEFAULT '[]', is_pinned INTEGER NOT NULL DEFAULT 0, is_my_day INTEGER NOT NULL DEFAULT 0, recurrence_rule TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE TABLE notes (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL, category TEXT NOT NULL DEFAULT 'general', project_id TEXT REFERENCES projects (id) ON DELETE SET NULL, goal_id TEXT REFERENCES goals (id) ON DELETE SET NULL, tags_json TEXT NOT NULL DEFAULT '[]', is_pinned INTEGER NOT NULL DEFAULT 0, is_favorite INTEGER NOT NULL DEFAULT 0, is_archived INTEGER NOT NULL DEFAULT 0, is_trashed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE TABLE calendar_events (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, date_iso TEXT NOT NULL, end_date_iso TEXT, start_time TEXT, end_time TEXT, is_all_day INTEGER NOT NULL DEFAULT 0, category TEXT NOT NULL DEFAULT 'personal', color_hex TEXT NOT NULL DEFAULT '#1B4D3E', has_reminder INTEGER NOT NULL DEFAULT 0, notes TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE TABLE financial_categories (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, color_hex TEXT NOT NULL DEFAULT '#4CAF50', is_default INTEGER NOT NULL DEFAULT 0, is_archived INTEGER NOT NULL DEFAULT 0, parent_id TEXT, sort_order INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE accounts_table (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, sub_type TEXT NOT NULL DEFAULT 'cash', is_system INTEGER NOT NULL DEFAULT 0, currency_code TEXT NOT NULL DEFAULT 'ETB', opening_balance_cents INTEGER NOT NULL DEFAULT 0, opening_balance_date TEXT, is_archived INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
      CREATE TABLE parties_table (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, phone TEXT, notes TEXT, is_archived INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
      CREATE TABLE journal_entries_table (id TEXT NOT NULL PRIMARY KEY, entry_type TEXT NOT NULL, description TEXT NOT NULL, occurrence_date TEXT NOT NULL, is_voided INTEGER NOT NULL DEFAULT 0, void_reason TEXT, legacy_source_tx_id TEXT, corrected_from_entry_id TEXT, created_at INTEGER NOT NULL);
      CREATE TABLE postings_table (id TEXT NOT NULL PRIMARY KEY, entry_id TEXT NOT NULL REFERENCES journal_entries_table (id) ON DELETE CASCADE, account_id TEXT NOT NULL REFERENCES accounts_table (id), amount_cents INTEGER NOT NULL, direction TEXT NOT NULL, account_movement_date TEXT NOT NULL, category_id TEXT, note TEXT);
      CREATE TABLE debts_table (id TEXT NOT NULL PRIMARY KEY, origin_entry_id TEXT NOT NULL REFERENCES journal_entries_table (id), party_id TEXT NOT NULL REFERENCES parties_table (id), debt_type TEXT NOT NULL, principal_cents INTEGER NOT NULL, outstanding_cents INTEGER NOT NULL, due_date TEXT, status TEXT NOT NULL DEFAULT 'active', created_at INTEGER NOT NULL);
      CREATE TABLE settlement_allocations_table (id TEXT NOT NULL PRIMARY KEY, settlement_entry_id TEXT NOT NULL REFERENCES journal_entries_table (id), debt_id TEXT NOT NULL REFERENCES debts_table (id), allocated_cents INTEGER NOT NULL, settlement_date TEXT NOT NULL);
      CREATE TABLE budgets_table (id TEXT NOT NULL PRIMARY KEY, category_id TEXT NOT NULL, month_iso TEXT NOT NULL, limit_cents INTEGER NOT NULL, rollover_enabled INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE TABLE recurring_rules_table (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, rule_type TEXT NOT NULL, amount_cents INTEGER NOT NULL, frequency TEXT NOT NULL, interval INTEGER NOT NULL DEFAULT 1, start_date TEXT NOT NULL, next_occurrence_date TEXT NOT NULL, end_date TEXT, account_id TEXT, destination_account_id TEXT, category_id TEXT, linked_debt_id TEXT, is_active INTEGER NOT NULL DEFAULT 1, auto_post INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
      CREATE TABLE financial_transactions (id TEXT NOT NULL PRIMARY KEY, category_id TEXT NOT NULL REFERENCES financial_categories (id), amount_cents INTEGER NOT NULL, type TEXT NOT NULL, transaction_date TEXT NOT NULL, note TEXT, payee TEXT, account_id TEXT, destination_account_id TEXT, is_superseded INTEGER NOT NULL DEFAULT 0, corrected_from_id TEXT, correction_reason TEXT, created_at INTEGER NOT NULL);
      CREATE TABLE financial_commitments (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, amount_cents INTEGER NOT NULL, due_date TEXT NOT NULL, is_paid INTEGER NOT NULL DEFAULT 0, recurring_rule TEXT, linked_account_id TEXT, category_id TEXT, linked_debt_id TEXT, settlement_entry_id TEXT, recurring_rule_id TEXT, created_at INTEGER NOT NULL);
      CREATE TABLE savings_goals (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, target_cents INTEGER NOT NULL, current_allocated_cents INTEGER NOT NULL DEFAULT 0, target_date TEXT, linked_account_id TEXT, created_at INTEGER NOT NULL);
      CREATE TABLE reminders (id TEXT NOT NULL PRIMARY KEY, target_id TEXT NOT NULL, target_type TEXT NOT NULL, trigger_time_utc INTEGER NOT NULL, is_active INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL);
      CREATE TABLE app_settings (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL);
      INSERT INTO financial_categories (id, name, type) VALUES ('cat-other-exp', 'Other Expense', 'expense');
      INSERT INTO tasks (id, title, created_at, updated_at) VALUES ('task-v6', 'v6 Task', $ts, $ts);
      INSERT INTO reminders (id, target_id, target_type, trigger_time_utc, is_active, created_at)
      VALUES ('rem-v6-1', 'task-v6', 'task', $ts, 1, $ts);
      INSERT INTO app_settings (key, value, updated_at)
      VALUES ('initial_seed_completed', 'true', $ts),
             ('v6_ledger_migrated', 'true', $ts);
      PRAGMA user_version = 6;
    ''');
  } finally {
    rawDb.dispose();
  }
}

void _createRawV4DatabaseWithReminder(File dbFile) {
  final rawDb = sqlite3.open(dbFile.path);
  const ts = 1794304800;
  try {
    rawDb.execute('PRAGMA foreign_keys = OFF;');
    rawDb.execute('''
      CREATE TABLE inbox_items (id TEXT NOT NULL PRIMARY KEY, raw_text TEXT NOT NULL, category TEXT NOT NULL DEFAULT 'general', is_processed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
      CREATE TABLE goals (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, description TEXT, target_date INTEGER, status TEXT NOT NULL DEFAULT 'active', created_at INTEGER NOT NULL);
      CREATE TABLE projects (id TEXT NOT NULL PRIMARY KEY, goal_id TEXT REFERENCES goals (id) ON DELETE SET NULL, title TEXT NOT NULL, description TEXT, status TEXT NOT NULL DEFAULT 'active', target_date INTEGER, created_at INTEGER NOT NULL);
      CREATE TABLE milestones (id TEXT NOT NULL PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE, title TEXT NOT NULL, due_date INTEGER, is_completed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
      CREATE TABLE tasks (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, description TEXT, status TEXT NOT NULL DEFAULT 'inbox', priority TEXT NOT NULL DEFAULT 'medium', due_date INTEGER, scheduled_date INTEGER, estimated_duration_minutes INTEGER, project_id TEXT REFERENCES projects (id) ON DELETE SET NULL, milestone_id TEXT REFERENCES milestones (id) ON DELETE SET NULL, subtasks_json TEXT NOT NULL DEFAULT '[]', labels_json TEXT NOT NULL DEFAULT '[]', is_pinned INTEGER NOT NULL DEFAULT 0, is_my_day INTEGER NOT NULL DEFAULT 0, recurrence_rule TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE TABLE notes (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL, category TEXT NOT NULL DEFAULT 'general', project_id TEXT REFERENCES projects (id) ON DELETE SET NULL, goal_id TEXT REFERENCES goals (id) ON DELETE SET NULL, tags_json TEXT NOT NULL DEFAULT '[]', is_pinned INTEGER NOT NULL DEFAULT 0, is_favorite INTEGER NOT NULL DEFAULT 0, is_archived INTEGER NOT NULL DEFAULT 0, is_trashed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE TABLE calendar_events (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, date_iso TEXT NOT NULL, start_time TEXT, end_time TEXT, is_all_day INTEGER NOT NULL DEFAULT 0, category TEXT NOT NULL DEFAULT 'personal', color_hex TEXT NOT NULL DEFAULT '#1B4D3E', has_reminder INTEGER NOT NULL DEFAULT 0, notes TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE TABLE financial_categories (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, color_hex TEXT NOT NULL DEFAULT '#4CAF50', is_default INTEGER NOT NULL DEFAULT 0, is_archived INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE financial_transactions (id TEXT NOT NULL PRIMARY KEY, category_id TEXT NOT NULL REFERENCES financial_categories (id), amount_cents INTEGER NOT NULL, type TEXT NOT NULL, transaction_date INTEGER NOT NULL, note TEXT, payee TEXT, account_id TEXT, destination_account_id TEXT, is_superseded INTEGER NOT NULL DEFAULT 0, corrected_from_id TEXT, correction_reason TEXT, created_at INTEGER NOT NULL);
      CREATE TABLE financial_commitments (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, amount_cents INTEGER NOT NULL, due_date INTEGER NOT NULL, is_paid INTEGER NOT NULL DEFAULT 0, recurring_rule TEXT, created_at INTEGER NOT NULL);
      CREATE TABLE savings_goals (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, target_cents INTEGER NOT NULL, current_allocated_cents INTEGER NOT NULL DEFAULT 0, target_date INTEGER, created_at INTEGER NOT NULL);
      CREATE TABLE reminders (id TEXT NOT NULL PRIMARY KEY, target_id TEXT NOT NULL, target_type TEXT NOT NULL, trigger_time_utc INTEGER NOT NULL, is_active INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL);
      CREATE TABLE app_settings (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL);
      CREATE TABLE accounts_table (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, currency_code TEXT NOT NULL DEFAULT 'ETB', opening_balance_cents INTEGER NOT NULL DEFAULT 0, opening_balance_date TEXT, is_archived INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
      CREATE TABLE parties_table (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, phone TEXT, notes TEXT, is_archived INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
      CREATE TABLE journal_entries_table (id TEXT NOT NULL PRIMARY KEY, entry_type TEXT NOT NULL, description TEXT NOT NULL, occurrence_date TEXT NOT NULL, is_voided INTEGER NOT NULL DEFAULT 0, void_reason TEXT, created_at INTEGER NOT NULL);
      CREATE TABLE postings_table (id TEXT NOT NULL PRIMARY KEY, entry_id TEXT NOT NULL REFERENCES journal_entries_table (id) ON DELETE CASCADE, account_id TEXT NOT NULL REFERENCES accounts_table (id), amount_cents INTEGER NOT NULL, direction TEXT NOT NULL, account_movement_date TEXT NOT NULL, category_id TEXT REFERENCES financial_categories (id), note TEXT);
      CREATE TABLE debts_table (id TEXT NOT NULL PRIMARY KEY, origin_entry_id TEXT NOT NULL REFERENCES journal_entries_table (id), party_id TEXT NOT NULL REFERENCES parties_table (id), debt_type TEXT NOT NULL, principal_cents INTEGER NOT NULL, outstanding_cents INTEGER NOT NULL, due_date TEXT, status TEXT NOT NULL DEFAULT 'active', created_at INTEGER NOT NULL);
      CREATE TABLE settlement_allocations_table (id TEXT NOT NULL PRIMARY KEY, settlement_entry_id TEXT NOT NULL REFERENCES journal_entries_table (id), debt_id TEXT NOT NULL REFERENCES debts_table (id), allocated_cents INTEGER NOT NULL, settlement_date TEXT NOT NULL);
      INSERT INTO financial_categories (id, name, type) VALUES ('cat-v4-exp', 'Food', 'expense');
      INSERT INTO tasks (id, title, due_date, created_at, updated_at) VALUES ('task-v4-r', 'v4 Task', $ts, $ts, $ts);
      INSERT INTO reminders (id, target_id, target_type, trigger_time_utc, is_active, created_at) VALUES ('rem-v4-1', 'task-v4-r', 'task', $ts, 1, $ts);
      PRAGMA user_version = 4;
    ''');
  } finally {
    rawDb.dispose();
  }
}

class _TestFailingV8FromV7Database extends AppDatabase {
  _TestFailingV8FromV7Database(super.e);

  @override
  MigrationStrategy get migration {
    final baseStrategy = super.migration;
    return MigrationStrategy(
      onCreate: (Migrator m) => baseStrategy.onCreate(m),
      onUpgrade: (Migrator m, int from, int to) async {
        await transaction(() async {
          await baseStrategy.onUpgrade(m, from, to);
          throw StateError(
            'Simulated v7 -> v8 failure after additive columns.',
          );
        });
      },
      beforeOpen: baseStrategy.beforeOpen,
    );
  }
}

void _createRawV8Database(File dbFile) {
  final rawDb = sqlite3.open(dbFile.path);
  const ts = 1794304800; // 2026-11-10T10:00:00Z
  try {
    rawDb.execute('PRAGMA foreign_keys = OFF;');
    rawDb.execute('''
      CREATE TABLE inbox_items (
        id TEXT NOT NULL PRIMARY KEY,
        raw_text TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'general',
        is_processed INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE goals (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        target_date TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        created_at INTEGER NOT NULL
      );
      CREATE TABLE projects (
        id TEXT NOT NULL PRIMARY KEY,
        goal_id TEXT REFERENCES goals (id) ON DELETE SET NULL,
        title TEXT NOT NULL,
        description TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        target_date TEXT,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE milestones (
        id TEXT NOT NULL PRIMARY KEY,
        project_id TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        due_date TEXT,
        is_completed INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
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
      CREATE TABLE financial_categories (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        color_hex TEXT NOT NULL DEFAULT '#4CAF50',
        is_default INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        parent_id TEXT REFERENCES financial_categories (id) ON DELETE RESTRICT,
        sort_order INTEGER NOT NULL DEFAULT 0
      );
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
      CREATE TABLE parties_table (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        notes TEXT,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE journal_entries_table (
        id TEXT NOT NULL PRIMARY KEY,
        entry_type TEXT NOT NULL,
        description TEXT NOT NULL,
        occurrence_date TEXT NOT NULL,
        is_voided INTEGER NOT NULL DEFAULT 0,
        void_reason TEXT,
        legacy_source_tx_id TEXT,
        corrected_from_entry_id TEXT REFERENCES journal_entries_table (id) ON DELETE RESTRICT,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE postings_table (
        id TEXT NOT NULL PRIMARY KEY,
        entry_id TEXT NOT NULL REFERENCES journal_entries_table (id) ON DELETE RESTRICT,
        account_id TEXT NOT NULL REFERENCES accounts_table (id) ON DELETE RESTRICT,
        amount_cents INTEGER NOT NULL,
        direction TEXT NOT NULL,
        account_movement_date TEXT NOT NULL,
        category_id TEXT REFERENCES financial_categories (id) ON DELETE RESTRICT,
        note TEXT
      );
      CREATE TABLE debts_table (
        id TEXT NOT NULL PRIMARY KEY,
        origin_entry_id TEXT NOT NULL REFERENCES journal_entries_table (id) ON DELETE RESTRICT,
        party_id TEXT NOT NULL REFERENCES parties_table (id) ON DELETE RESTRICT,
        debt_type TEXT NOT NULL,
        principal_cents INTEGER NOT NULL,
        outstanding_cents INTEGER NOT NULL,
        due_date TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        write_off_entry_id TEXT REFERENCES journal_entries_table (id) ON DELETE RESTRICT,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE settlement_allocations_table (
        id TEXT NOT NULL PRIMARY KEY,
        settlement_entry_id TEXT NOT NULL REFERENCES journal_entries_table (id) ON DELETE RESTRICT,
        debt_id TEXT NOT NULL REFERENCES debts_table (id) ON DELETE RESTRICT,
        allocated_cents INTEGER NOT NULL,
        settlement_date TEXT NOT NULL
      );
      CREATE TABLE budgets_table (
        id TEXT NOT NULL PRIMARY KEY,
        category_id TEXT NOT NULL REFERENCES financial_categories (id) ON DELETE RESTRICT,
        month_iso TEXT NOT NULL,
        limit_cents INTEGER NOT NULL,
        rollover_enabled INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
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
        account_id TEXT REFERENCES accounts_table (id) ON DELETE RESTRICT,
        destination_account_id TEXT REFERENCES accounts_table (id) ON DELETE RESTRICT,
        category_id TEXT REFERENCES financial_categories (id) ON DELETE RESTRICT,
        linked_debt_id TEXT REFERENCES debts_table (id) ON DELETE RESTRICT,
        is_active INTEGER NOT NULL DEFAULT 1,
        auto_post INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE financial_transactions (
        id TEXT NOT NULL PRIMARY KEY,
        category_id TEXT NOT NULL REFERENCES financial_categories (id) ON DELETE RESTRICT,
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
      CREATE TABLE financial_commitments (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        amount_cents INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        is_paid INTEGER NOT NULL DEFAULT 0,
        direction TEXT NOT NULL DEFAULT 'outflow',
        legacy_paid_unverified INTEGER NOT NULL DEFAULT 0,
        recurring_rule TEXT,
        linked_account_id TEXT REFERENCES accounts_table (id) ON DELETE RESTRICT,
        category_id TEXT REFERENCES financial_categories (id) ON DELETE RESTRICT,
        linked_debt_id TEXT REFERENCES debts_table (id) ON DELETE RESTRICT,
        settlement_entry_id TEXT REFERENCES journal_entries_table (id) ON DELETE RESTRICT,
        recurring_rule_id TEXT REFERENCES recurring_rules_table (id) ON DELETE RESTRICT,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE commitment_settlements_table (
        id TEXT NOT NULL PRIMARY KEY,
        commitment_id TEXT NOT NULL REFERENCES financial_commitments (id) ON DELETE RESTRICT,
        entry_id TEXT NOT NULL REFERENCES journal_entries_table (id) ON DELETE RESTRICT,
        amount_cents INTEGER NOT NULL,
        settled_date TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE savings_goals (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        target_cents INTEGER NOT NULL,
        current_allocated_cents INTEGER NOT NULL DEFAULT 0,
        target_date TEXT,
        linked_account_id TEXT REFERENCES accounts_table (id) ON DELETE RESTRICT,
        status TEXT NOT NULL DEFAULT 'active',
        created_at INTEGER NOT NULL
      );
      CREATE TABLE reminders (
        id TEXT NOT NULL PRIMARY KEY,
        target_id TEXT NOT NULL,
        target_type TEXT NOT NULL,
        title TEXT,
        channel_id TEXT,
        trigger_time_utc INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE app_settings (
        key TEXT NOT NULL PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
      INSERT INTO goals (id, title, created_at) VALUES ('goal-v8', 'v8 Goal', $ts);
      INSERT INTO projects (id, goal_id, title, created_at) VALUES ('proj-v8', 'goal-v8', 'v8 Project', $ts);
      INSERT INTO financial_categories (id, name, type) VALUES ('cat-other-exp', 'Other Expense', 'expense');
      INSERT INTO accounts_table (id, name, type, sub_type, is_system, opening_balance_cents, opening_balance_date, created_at)
      VALUES ('acc-sys-equity', 'Opening Equity', 'equity', 'opening_equity', 1, 0, NULL, $ts),
             ('acc-sys-income', 'Income Equity', 'equity', 'nominal_income', 1, 0, NULL, $ts),
             ('acc-sys-expense', 'Expense Equity', 'equity', 'nominal_expense', 1, 0, NULL, $ts),
             ('acc-sys-receivable', 'Receivable Control', 'asset', 'receivable', 1, 0, NULL, $ts),
             ('acc-sys-payable', 'Payable Control', 'liability', 'payable', 1, 0, NULL, $ts),
             ('acc-sys-legacy-offset', 'Legacy Offset', 'equity', 'legacy_clearing', 1, 0, NULL, $ts);
      INSERT INTO app_settings (key, value, updated_at)
      VALUES ('initial_seed_completed', 'true', $ts),
             ('v6_ledger_migrated', 'true', $ts);
      PRAGMA user_version = 8;
    ''');
  } finally {
    rawDb.dispose();
  }
}

class _TestFailingV9FromV8Database extends AppDatabase {
  _TestFailingV9FromV8Database(super.e);

  @override
  MigrationStrategy get migration {
    final baseStrategy = super.migration;
    return MigrationStrategy(
      onCreate: (Migrator m) => baseStrategy.onCreate(m),
      onUpgrade: (Migrator m, int from, int to) async {
        await transaction(() async {
          await baseStrategy.onUpgrade(m, from, to);
          throw StateError(
            'Simulated v8 -> v9 failure after additive columns and tables.',
          );
        });
      },
      beforeOpen: baseStrategy.beforeOpen,
    );
  }
}

Future<void> _seedRealisticV9Database(File dbFile) async {
  final db = AppDatabase(NativeDatabase(dbFile));
  await db.ensureInitialized();
  final now = DateTime.utc(2026, 11, 16, 8, 0);

  await db.into(db.goals).insert(
        GoalsCompanion.insert(
          id: 'goal-v7-1',
          title: 'Financial Clarity',
          targetDate: const Value('2026-12-31'),
          createdAt: now,
        ),
      );
  await db.into(db.projects).insert(
        ProjectsCompanion.insert(
          id: 'proj-v7-1',
          goalId: const Value('goal-v7-1'),
          title: 'Stage 343 Project',
          targetDate: const Value('2026-12-15'),
          createdAt: now,
        ),
      );
  await db.into(db.milestones).insert(
        MilestonesCompanion.insert(
          id: 'ms-v7-1',
          projectId: 'proj-v7-1',
          title: 'v9 Baseline',
          dueDate: const Value('2026-11-30'),
          createdAt: now,
        ),
      );

  await DriftTasksRepository(db).createTask(
    TaskEntity(
      id: 'task-v7-1',
      title: 'Review ledger integrity',
      status: 'in_progress',
      priority: 'high',
      dueDate: CalendarDate(year: 2026, month: 11, day: 20),
      projectId: 'proj-v7-1',
      milestoneId: 'ms-v7-1',
      createdAt: now,
      updatedAt: now,
    ),
  );

  await DriftNotesRepository(db).createNote(
    NoteEntity(
      id: 'note-v7-1',
      title: 'የዕለት ማስታወሻ',
      content: 'Stage 3.4.3 forward migration baseline note',
      category: 'reflection',
      projectId: 'proj-v7-1',
      goalId: 'goal-v7-1',
      tags: const ['governance', 'sqlite'],
      createdAt: now,
      updatedAt: now,
    ),
  );

  await DriftCalendarRepository(db).createEvent(
    CalendarEventEntity(
      id: 'evt-v7-1',
      title: 'Migration Audit',
      dateIso: '2026-11-16',
      endDateIso: '2026-11-17',
      createdAt: now,
      updatedAt: now,
    ),
  );

  final financeRepo = DriftFinanceRepository(db);
  await financeRepo.completeFinanceSetup([
    AccountModel(
      id: 'acc-v7-cbe',
      name: 'CBE Main',
      type: AccountType.asset,
      subType: AccountSubType.bank,
      openingBalanceCents: 300000,
      openingBalanceDate: '2026-11-01',
    ),
  ]);
  final categories = await financeRepo.getCategories();
  final expenseCat = categories.firstWhere((c) => c.type == 'expense');
  await financeRepo.recordDirectExpense(
    accountId: 'acc-v7-cbe',
    categoryId: expenseCat.id,
    amountCents: 45000,
    date: CalendarDate(year: 2026, month: 11, day: 15),
    description: 'Bookstore',
  );

  await db.into(db.reminders).insert(
        RemindersCompanion.insert(
          id: 'rem-v7-1',
          targetId: 'task-v7-1',
          targetType: 'task',
          triggerTimeUtc: DateTime.utc(2026, 11, 20, 6, 0),
          createdAt: now,
        ),
      );
  await db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: 'stage343_user_pref',
          value: 'ethiopian_calendar',
          updatedAt: now,
        ),
      );

  await db.close();
}

class _TestForwardV10Database extends AppDatabase {
  final bool failMidV10Migration;
  final bool failForeignKeyCheckInV10;
  int v10UpgradeCalls = 0;

  _TestForwardV10Database(
    super.e, {
    this.failMidV10Migration = false,
    this.failForeignKeyCheckInV10 = false,
  });

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration {
    final baseStrategy = super.migration;
    return MigrationStrategy(
      onCreate: (Migrator m) => baseStrategy.onCreate(m),
      onUpgrade: (Migrator m, int from, int to) async {
        if (from > to) {
          throw UnsupportedDatabaseVersionException(
            fromVersion: from,
            toVersion: to,
          );
        }
        await transaction(() async {
          if (from < 9) {
            await baseStrategy.onUpgrade(m, from, 9);
          }
          if (from < 10) {
            v10UpgradeCalls += 1;
            await customStatement(
              "ALTER TABLE notes ADD COLUMN review_status TEXT NOT NULL "
              "DEFAULT 'active';",
            );
            await customStatement(
              'ALTER TABLE tasks ADD COLUMN effort_points INTEGER;',
            );
            await customStatement(
              'CREATE TABLE task_checklists_v10 ('
              'id TEXT NOT NULL PRIMARY KEY, '
              'task_id TEXT NOT NULL REFERENCES tasks (id) ON DELETE CASCADE, '
              'label TEXT NOT NULL, '
              'is_done INTEGER NOT NULL DEFAULT 0'
              ');',
            );
            await customStatement(
              'CREATE INDEX idx_task_checklists_v10_task '
              'ON task_checklists_v10(task_id);',
            );

            if (failMidV10Migration) {
              await customStatement(
                "UPDATE notes SET category = 'mutated_mid_upgrade' "
                "WHERE id = 'note-v7-1';",
              );
              throw StateError(
                'Simulated v9->v10 failure after partial DDL and DML',
              );
            }

            if (failForeignKeyCheckInV10) {
              await customStatement(
                'INSERT INTO task_checklists_v10 (id, task_id, label, is_done) '
                "VALUES ('chk-orphan', 'missing-task-id', 'Orphan item', 0);",
              );
            } else {
              await customStatement(
                'INSERT INTO task_checklists_v10 (id, task_id, label, is_done) '
                "SELECT 'chk-' || id, id, 'Verify upgraded item', 0 "
                'FROM tasks ORDER BY id LIMIT 1;',
              );
            }

            final fkViolations =
                await customSelect('PRAGMA foreign_key_check').get();
            if (fkViolations.isNotEmpty) {
              throw StateError(
                'Schema v9->v10 migration aborted due to foreign key integrity '
                'violations (${fkViolations.length} row(s)).',
              );
            }
          }
        });
      },
      beforeOpen: (details) async {
        final onBeforeOpen = baseStrategy.beforeOpen;
        if (onBeforeOpen != null) {
          await onBeforeOpen(details);
        }
      },
    );
  }
}
