import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../core/date/shared_date.dart';
import '../../core/interfaces/platform_service_interfaces.dart';
import '../../core/shared_foundation_core.dart';
import '../../domain/finance/double_entry_engine.dart';
import 'tables.dart';
import 'v6_ledger_migrator.dart';
import 'v7_ledger_hardener.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  InboxItems,
  Goals,
  Projects,
  Milestones,
  Tasks,
  Notes,
  CalendarEvents,
  FinancialCategories,
  FinancialTransactions,
  FinancialCommitments,
  CommitmentSettlementsTable,
  SavingsGoals,
  Reminders,
  AppSettings,
  AccountsTable,
  PartiesTable,
  JournalEntriesTable,
  PostingsTable,
  DebtsTable,
  SettlementAllocationsTable,
  BudgetsTable,
  RecurringRulesTable,
  ProjectTrackingBlocks,
  ProjectTrackingRecords,
  DailyPlanningEntries,
])
class AppDatabase extends _$AppDatabase {
  static const String seedSentinelKey = 'initial_seed_completed';
  static const String financeSetupKey = 'is_finance_setup_completed';
  static const String openingBalanceKey = 'opening_balance_cents';

  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration {
    final strategy = MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        await createPerformanceIndices();
        await seedDefaultsIfFirstRun();
        await V6LedgerMigrator.ensureSystemControlAccounts(this);
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from > to) {
          throw UnsupportedDatabaseVersionException(
            fromVersion: from,
            toVersion: to,
          );
        }
        if (from < 2) {
          // Schema v1 -> v2: Add double-entry accounting tables
          await m.createTable(accountsTable);
          await m.createTable(partiesTable);
          await m.createTable(journalEntriesTable);
          await m.createTable(postingsTable);
          await m.createTable(debtsTable);
          await m.createTable(settlementAllocationsTable);
        }
        if (from < 3) {
          // Schema v2 -> v3: Safe non-destructive column additions for starting balances
          await _addColumnIfMissing(
            table: 'accounts_table',
            column: 'opening_balance_cents',
            addFn: () => m.addColumn(
              accountsTable,
              accountsTable.openingBalanceCents,
            ),
          );
          await _addColumnIfMissing(
            table: 'accounts_table',
            column: 'opening_balance_date',
            addFn: () => m.addColumn(
              accountsTable,
              accountsTable.openingBalanceDate,
            ),
          );
        }
        if (from < 4) {
          // Schema v3 -> v4: Non-destructive column additions & CalendarEvents table
          await m.addColumn(tasks, tasks.subtasksJson);
          await m.addColumn(tasks, tasks.labelsJson);
          await m.addColumn(tasks, tasks.isPinned);
          await m.addColumn(tasks, tasks.isMyDay);
          await m.addColumn(tasks, tasks.recurrenceRule);

          await m.addColumn(notes, notes.tagsJson);
          await m.addColumn(notes, notes.isPinned);
          await m.addColumn(notes, notes.isFavorite);
          await m.addColumn(notes, notes.isArchived);
          await m.addColumn(notes, notes.isTrashed);

          await m.addColumn(
              financialCategories, financialCategories.isArchived);

          await m.addColumn(
              financialTransactions, financialTransactions.accountId);
          await m.addColumn(financialTransactions,
              financialTransactions.destinationAccountId);
          await m.addColumn(
              financialTransactions, financialTransactions.isSuperseded);
          await m.addColumn(
              financialTransactions, financialTransactions.correctedFromId);
          await m.addColumn(
              financialTransactions, financialTransactions.correctionReason);

          await m.createTable(calendarEvents);
        }
        if (from < 5) {
          // Schema v4 -> v5:
          final calendarCols = await customSelect(
            "PRAGMA table_info('calendar_events')",
          ).get();
          final hasEndDateIso = calendarCols.any(
            (row) => row.read<String>('name') == 'end_date_iso',
          );

          // 1. Atomic pre-flight validation BEFORE mutating any schema or rows:
          //    Rejects corrupt/ambiguous/overflowing dates cleanly so SQLite rolls
          //    back to v4 intact instead of silently nulled or overwritten dates.
          await _validateLegacyDatesBeforeV5Migration(
            hasEndDateIso: hasEndDateIso,
          );

          // 2. Add nullable end_date_iso column to calendar_events if absent.
          if (!hasEndDateIso) {
            await m.addColumn(calendarEvents, calendarEvents.endDateIso);
          }

          // 3. Non-destructively convert legacy DateTimeColumn date-only fields
          //    to canonical YYYY-MM-DD strings under Ethiopia UTC+3 civil time.
          await m.alterTable(
            TableMigration(
              goals,
              columnTransformer: {
                goals.targetDate: _nullableDateToIsoSql('target_date'),
              },
            ),
          );
          final existingProjectCols = await _existingTableColumns('projects');
          final projectNewCols = <GeneratedColumn>[
            for (final col in projects.$columns)
              if (!existingProjectCols.contains(col.$name)) col,
          ];
          await m.alterTable(
            TableMigration(
              projects,
              newColumns: projectNewCols,
              columnTransformer: {
                projects.targetDate: _nullableDateToIsoSql('target_date'),
                if (!existingProjectCols.contains('is_archived'))
                  projects.isArchived: const Constant(false),
                if (!existingProjectCols.contains('custom_fields_json'))
                  projects.customFieldsJson: const Constant('{}'),
                if (!existingProjectCols.contains('updated_at'))
                  projects.updatedAt: projects.createdAt,
              },
            ),
          );
          await m.alterTable(
            TableMigration(
              milestones,
              columnTransformer: {
                milestones.dueDate: _nullableDateToIsoSql('due_date'),
              },
            ),
          );
          final existingTaskCols = await _existingTableColumns('tasks');
          final taskNewCols = <GeneratedColumn>[
            for (final col in tasks.$columns)
              if (!existingTaskCols.contains(col.$name)) col,
          ];
          await m.alterTable(
            TableMigration(
              tasks,
              newColumns: taskNewCols,
              columnTransformer: {
                tasks.dueDate: _nullableDateToIsoSql('due_date'),
                tasks.scheduledDate: _nullableDateToIsoSql('scheduled_date'),
                if (!existingTaskCols.contains('is_archived'))
                  tasks.isArchived: const Constant(false),
                if (!existingTaskCols.contains('sort_order'))
                  tasks.sortOrder: const Constant(0),
              },
            ),
          );
          await m.alterTable(
            TableMigration(
              financialTransactions,
              columnTransformer: {
                financialTransactions.transactionDate:
                    _requiredDateToIsoSql('transaction_date'),
              },
            ),
          );
          final existingCommitmentCols =
              await _existingTableColumns('financial_commitments');
          final commitmentNewCols = <GeneratedColumn>[
            for (final col in financialCommitments.$columns)
              if (!existingCommitmentCols.contains(col.$name)) col,
          ];
          await m.alterTable(
            TableMigration(
              financialCommitments,
              newColumns: commitmentNewCols,
              columnTransformer: {
                financialCommitments.dueDate: _requiredDateToIsoSql('due_date'),
                if (!existingCommitmentCols.contains('direction'))
                  financialCommitments.direction: const Constant('outflow'),
                if (!existingCommitmentCols.contains('legacy_paid_unverified'))
                  financialCommitments.legacyPaidUnverified:
                      const Constant(false),
              },
            ),
          );
          final existingSavingsCols =
              await _existingTableColumns('savings_goals');
          final savingsNewCols = <GeneratedColumn>[
            for (final col in savingsGoals.$columns)
              if (!existingSavingsCols.contains(col.$name)) col,
          ];
          await m.alterTable(
            TableMigration(
              savingsGoals,
              newColumns: savingsNewCols,
              columnTransformer: {
                savingsGoals.targetDate: _nullableDateToIsoSql('target_date'),
                if (!existingSavingsCols.contains('status'))
                  savingsGoals.status: const Constant('active'),
              },
            ),
          );

          // 4. Normalize any pre-v5 ISO timestamps or epochs stored inside
          //    existing TEXT date columns to canonical YYYY-MM-DD strings.
          await customStatement(
            'UPDATE calendar_events SET date_iso = '
            "${requiredDateToIsoSqlExpression('date_iso')}, "
            'end_date_iso = '
            "${nullableDateToIsoSqlExpression('end_date_iso')};",
          );
          await customStatement(
            'UPDATE accounts_table SET opening_balance_date = '
            "${nullableDateToIsoSqlExpression('opening_balance_date')};",
          );
          await customStatement(
            'UPDATE journal_entries_table SET occurrence_date = '
            "${requiredDateToIsoSqlExpression('occurrence_date')};",
          );
          await customStatement(
            'UPDATE postings_table SET account_movement_date = '
            "${requiredDateToIsoSqlExpression('account_movement_date')};",
          );
          await customStatement(
            'UPDATE debts_table SET due_date = '
            "${nullableDateToIsoSqlExpression('due_date')};",
          );
          await customStatement(
            'UPDATE settlement_allocations_table SET settlement_date = '
            "${requiredDateToIsoSqlExpression('settlement_date')};",
          );

          final fkViolations = await customSelect(
            'PRAGMA foreign_key_check',
          ).get();
          if (fkViolations.isNotEmpty) {
            throw StateError(
              'Schema v4->v5 migration aborted due to foreign key integrity '
              'violations after table rebuild (${fkViolations.length} row(s)).',
            );
          }
        }
        if (from < 6) {
          await _addColumnIfMissing(
            table: 'financial_categories',
            column: 'parent_id',
            addFn: () => m.addColumn(
              financialCategories,
              financialCategories.parentId,
            ),
          );
          await _addColumnIfMissing(
            table: 'financial_categories',
            column: 'sort_order',
            addFn: () => m.addColumn(
              financialCategories,
              financialCategories.sortOrder,
            ),
          );
          await _addColumnIfMissing(
            table: 'accounts_table',
            column: 'sub_type',
            addFn: () => m.addColumn(accountsTable, accountsTable.subType),
          );
          await _addColumnIfMissing(
            table: 'accounts_table',
            column: 'is_system',
            addFn: () => m.addColumn(accountsTable, accountsTable.isSystem),
          );
          await _addColumnIfMissing(
            table: 'journal_entries_table',
            column: 'legacy_source_tx_id',
            addFn: () => m.addColumn(
              journalEntriesTable,
              journalEntriesTable.legacySourceTxId,
            ),
          );
          await _addColumnIfMissing(
            table: 'journal_entries_table',
            column: 'corrected_from_entry_id',
            addFn: () => m.addColumn(
              journalEntriesTable,
              journalEntriesTable.correctedFromEntryId,
            ),
          );
          await _addColumnIfMissing(
            table: 'financial_commitments',
            column: 'linked_account_id',
            addFn: () => m.addColumn(
              financialCommitments,
              financialCommitments.linkedAccountId,
            ),
          );
          await _addColumnIfMissing(
            table: 'financial_commitments',
            column: 'category_id',
            addFn: () => m.addColumn(
              financialCommitments,
              financialCommitments.categoryId,
            ),
          );
          await _addColumnIfMissing(
            table: 'financial_commitments',
            column: 'linked_debt_id',
            addFn: () => m.addColumn(
              financialCommitments,
              financialCommitments.linkedDebtId,
            ),
          );
          await _addColumnIfMissing(
            table: 'financial_commitments',
            column: 'settlement_entry_id',
            addFn: () => m.addColumn(
              financialCommitments,
              financialCommitments.settlementEntryId,
            ),
          );
          await _addColumnIfMissing(
            table: 'financial_commitments',
            column: 'recurring_rule_id',
            addFn: () => m.addColumn(
              financialCommitments,
              financialCommitments.recurringRuleId,
            ),
          );
          await _addColumnIfMissing(
            table: 'savings_goals',
            column: 'linked_account_id',
            addFn: () => m.addColumn(
              savingsGoals,
              savingsGoals.linkedAccountId,
            ),
          );

          await _createTableIfMissing(
            table: 'budgets_table',
            createFn: () => m.createTable(budgetsTable),
          );
          await _createTableIfMissing(
            table: 'recurring_rules_table',
            createFn: () => m.createTable(recurringRulesTable),
          );

          await _createPreV7PerformanceIndices();
          await V6LedgerMigrator.migrateDataInTransaction(this);
        }
        if (from < 7) {
          // 1. Verify PRAGMA foreign_keys == 0 before TableMigration rebuilds.
          final fkRows = await customSelect('PRAGMA foreign_keys').get();
          final fkEnabled =
              fkRows.isNotEmpty && fkRows.first.read<int>('foreign_keys') != 0;
          if (fkEnabled) {
            throw const LedgerMigrationException(
              'Schema v7 upgrade requires PRAGMA foreign_keys = 0 during '
              'TableMigration rebuilds; disable pre-open FK PRAGMAs.',
            );
          }

          // 2. Clean pre-v7 un-FK'd orphans deterministically and log IDs.
          final orphanWarnings = await _cleanPreV7Orphans();

          // 3. Rebuild Finance tables in strict Level 0 -> Level 3 topological
          //    order (parents before children) enforcing ON DELETE RESTRICT.
          // Level 0: Root & self-referencing parent tables
          await m.alterTable(TableMigration(financialCategories));
          await m.alterTable(TableMigration(accountsTable));
          await m.alterTable(TableMigration(partiesTable));
          await m.alterTable(TableMigration(journalEntriesTable));

          // Level 1: Direct dependents on Level 0
          await m.alterTable(TableMigration(postingsTable));
          await m.alterTable(
            TableMigration(
              debtsTable,
              newColumns: [debtsTable.writeOffEntryId],
            ),
          );
          await m.alterTable(
            TableMigration(
              savingsGoals,
              newColumns: [savingsGoals.status],
              columnTransformer: {
                savingsGoals.status: const Constant('active'),
              },
            ),
          );
          await m.alterTable(TableMigration(budgetsTable));
          await m.alterTable(TableMigration(financialTransactions));

          // Level 2: Dependents on Level 0 + Level 1
          await m.alterTable(TableMigration(settlementAllocationsTable));
          await m.alterTable(TableMigration(recurringRulesTable));
          await m.alterTable(
            TableMigration(
              financialCommitments,
              newColumns: [
                financialCommitments.direction,
                financialCommitments.legacyPaidUnverified,
              ],
              columnTransformer: {
                financialCommitments.direction: const Constant('outflow'),
                financialCommitments.legacyPaidUnverified:
                    const Constant(false),
              },
            ),
          );

          // Level 3: New v7 commitment settlements table
          await _createTableIfMissing(
            table: 'commitment_settlements_table',
            createFn: () => m.createTable(commitmentSettlementsTable),
          );

          // 4. Recreate indices dropped by TableMigration + add v7 indices.
          await createPerformanceIndices();

          // 5. Run unified v7 hardening, repairs, audit & invariant checks.
          await V7LedgerHardener.hardenAndAuditInTransaction(
            this,
            fromVersion: from,
            preRebuildWarnings: orphanWarnings,
          );

          // 6. Confirm zero FK violations before commit.
          final fkViolations =
              await customSelect('PRAGMA foreign_key_check').get();
          if (fkViolations.isNotEmpty) {
            throw LedgerMigrationException(
              'Schema v7 upgrade aborted due to foreign key violations '
              '(${fkViolations.length} row(s)).',
            );
          }
        } else {
          await createPerformanceIndices();
        }
        if (from < 8) {
          // Schema v7 -> v8: Additive nullable reminder metadata columns
          await _addColumnIfMissing(
            table: 'reminders',
            column: 'title',
            addFn: () => m.addColumn(reminders, reminders.title),
          );
          await _addColumnIfMissing(
            table: 'reminders',
            column: 'channel_id',
            addFn: () => m.addColumn(reminders, reminders.channelId),
          );

          final fkViolations =
              await customSelect('PRAGMA foreign_key_check').get();
          if (fkViolations.isNotEmpty) {
            throw LedgerMigrationException(
              'Schema v8 upgrade aborted due to foreign key violations '
              '(${fkViolations.length} row(s)).',
            );
          }
        }
        if (from < 9) {
          // Schema v8 -> v9: Additive Projects metadata and tracking tables
          await _addColumnIfMissing(
            table: 'projects',
            column: 'is_archived',
            addFn: () => m.addColumn(projects, projects.isArchived),
          );
          await _addColumnIfMissing(
            table: 'projects',
            column: 'start_date',
            addFn: () => m.addColumn(projects, projects.startDate),
          );
          await _addColumnIfMissing(
            table: 'projects',
            column: 'custom_fields_json',
            addFn: () => m.addColumn(projects, projects.customFieldsJson),
          );
          await _addColumnIfMissing(
            table: 'projects',
            column: 'updated_at',
            addFn: () => m.addColumn(projects, projects.updatedAt),
          );
          await customStatement(
            'UPDATE projects SET updated_at = created_at WHERE updated_at IS NULL;',
          );

          await _createTableIfMissing(
            table: 'project_tracking_blocks',
            createFn: () => m.createTable(projectTrackingBlocks),
          );
          await _createTableIfMissing(
            table: 'project_tracking_records',
            createFn: () => m.createTable(projectTrackingRecords),
          );
          await _createV9ProjectPerformanceIndices();

          final fkViolations =
              await customSelect('PRAGMA foreign_key_check').get();
          if (fkViolations.isNotEmpty) {
            throw LedgerMigrationException(
              'Schema v9 upgrade aborted due to foreign key violations '
              '(${fkViolations.length} row(s)).',
            );
          }
        }
        if (from < 10) {
          // Schema v9 -> v10: Non-destructive Tasks v10 fields & DailyPlanningEntries
          await _addColumnIfMissing(
            table: 'tasks',
            column: 'completed_at',
            addFn: () => m.addColumn(tasks, tasks.completedAt),
          );
          await _addColumnIfMissing(
            table: 'tasks',
            column: 'scheduled_time',
            addFn: () => m.addColumn(tasks, tasks.scheduledTime),
          );
          await _addColumnIfMissing(
            table: 'tasks',
            column: 'my_day_date',
            addFn: () => m.addColumn(tasks, tasks.myDayDate),
          );
          await _addColumnIfMissing(
            table: 'tasks',
            column: 'recurrence_config_json',
            addFn: () => m.addColumn(tasks, tasks.recurrenceConfigJson),
          );
          await _addColumnIfMissing(
            table: 'tasks',
            column: 'is_archived',
            addFn: () => m.addColumn(tasks, tasks.isArchived),
          );
          await _addColumnIfMissing(
            table: 'tasks',
            column: 'sort_order',
            addFn: () => m.addColumn(tasks, tasks.sortOrder),
          );

          await _createTableIfMissing(
            table: 'daily_planning_entries',
            createFn: () => m.createTable(dailyPlanningEntries),
          );
          await _createV10TaskPerformanceIndices();

          final fkViolations =
              await customSelect('PRAGMA foreign_key_check').get();
          if (fkViolations.isNotEmpty) {
            throw LedgerMigrationException(
              'Schema v10 upgrade aborted due to foreign key violations '
              '(${fkViolations.length} row(s)).',
            );
          }
        }
      },
      beforeOpen: (details) async {
        // Enforce foreign key constraints in SQLite
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
    return _withTransactionalUpgrade(strategy);
  }

  MigrationStrategy _withTransactionalUpgrade(MigrationStrategy strategy) {
    return MigrationStrategy(
      onCreate: strategy.onCreate,
      onUpgrade: (Migrator m, int from, int to) async {
        if (from > to) {
          throw UnsupportedDatabaseVersionException(
            fromVersion: from,
            toVersion: to,
          );
        }
        await transaction(() async {
          await strategy.onUpgrade(m, from, to);
        });
      },
      beforeOpen: strategy.beforeOpen,
    );
  }

  Future<List<String>> _cleanPreV7Orphans() async {
    final warnings = <String>[];

    Future<void> cleanNullableRef({
      required String table,
      required String column,
      required String targetTable,
      required String warningCode,
      bool disallowSelf = false,
    }) async {
      final selfCond = disallowSelf ? ' OR $column = id' : '';
      final rows = await customSelect(
        'SELECT id FROM $table '
        'WHERE $column IS NOT NULL '
        'AND ($column NOT IN (SELECT id FROM $targetTable)$selfCond);',
      ).get();
      if (rows.isEmpty) return;
      for (final r in rows) {
        warnings.add('$warningCode: ${r.read<String>('id')}');
      }
      await customStatement(
        'UPDATE $table SET $column = NULL '
        'WHERE $column IS NOT NULL '
        'AND ($column NOT IN (SELECT id FROM $targetTable)$selfCond);',
      );
    }

    await cleanNullableRef(
      table: 'financial_categories',
      column: 'parent_id',
      targetTable: 'financial_categories',
      warningCode: 'ORPHANED_CATEGORY_PARENT_CLEARED',
      disallowSelf: true,
    );
    await cleanNullableRef(
      table: 'journal_entries_table',
      column: 'corrected_from_entry_id',
      targetTable: 'journal_entries_table',
      warningCode: 'ORPHANED_CORRECTED_ENTRY_CLEARED',
      disallowSelf: true,
    );
    await cleanNullableRef(
      table: 'financial_commitments',
      column: 'recurring_rule_id',
      targetTable: 'recurring_rules_table',
      warningCode: 'ORPHANED_RECURRING_RULE_LINK_CLEARED',
    );
    await cleanNullableRef(
      table: 'financial_commitments',
      column: 'linked_account_id',
      targetTable: 'accounts_table',
      warningCode: 'ORPHANED_COMMITMENT_ACCOUNT_CLEARED',
    );
    await cleanNullableRef(
      table: 'financial_commitments',
      column: 'category_id',
      targetTable: 'financial_categories',
      warningCode: 'ORPHANED_COMMITMENT_CATEGORY_CLEARED',
    );
    await cleanNullableRef(
      table: 'financial_commitments',
      column: 'linked_debt_id',
      targetTable: 'debts_table',
      warningCode: 'ORPHANED_COMMITMENT_DEBT_CLEARED',
    );
    await cleanNullableRef(
      table: 'financial_commitments',
      column: 'settlement_entry_id',
      targetTable: 'journal_entries_table',
      warningCode: 'ORPHANED_COMMITMENT_ENTRY_CLEARED',
    );
    await cleanNullableRef(
      table: 'savings_goals',
      column: 'linked_account_id',
      targetTable: 'accounts_table',
      warningCode: 'ORPHANED_GOAL_ACCOUNT_CLEARED',
    );
    await cleanNullableRef(
      table: 'recurring_rules_table',
      column: 'account_id',
      targetTable: 'accounts_table',
      warningCode: 'ORPHANED_RULE_ACCOUNT_CLEARED',
    );
    await cleanNullableRef(
      table: 'recurring_rules_table',
      column: 'destination_account_id',
      targetTable: 'accounts_table',
      warningCode: 'ORPHANED_RULE_DEST_ACCOUNT_CLEARED',
    );
    await cleanNullableRef(
      table: 'recurring_rules_table',
      column: 'category_id',
      targetTable: 'financial_categories',
      warningCode: 'ORPHANED_RULE_CATEGORY_CLEARED',
    );
    await cleanNullableRef(
      table: 'recurring_rules_table',
      column: 'linked_debt_id',
      targetTable: 'debts_table',
      warningCode: 'ORPHANED_RULE_DEBT_CLEARED',
    );
    await cleanNullableRef(
      table: 'postings_table',
      column: 'category_id',
      targetTable: 'financial_categories',
      warningCode: 'ORPHANED_POSTING_CATEGORY_CLEARED',
    );

    return warnings;
  }

  Future<Set<String>> _existingTableColumns(String table) async {
    final cols = await customSelect("PRAGMA table_info('$table')").get();
    return {for (final row in cols) row.read<String>('name')};
  }

  Future<void> _addColumnIfMissing({
    required String table,
    required String column,
    required Future<void> Function() addFn,
  }) async {
    final cols = await _existingTableColumns(table);
    if (!cols.contains(column)) {
      await addFn();
    }
  }

  Future<void> _createTableIfMissing({
    required String table,
    required Future<void> Function() createFn,
  }) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      variables: [Variable<String>(table)],
    ).get();
    if (rows.isEmpty) {
      await createFn();
    }
  }

  /// Ensures Drift opens the database, applies any pending migrations,
  /// creates indices, and performs idempotent first-run-only seeding.
  Future<void> ensureInitialized() async {
    await (select(appSettings)..limit(1)).get();
    await createPerformanceIndices();
    await seedDefaultsIfFirstRun();
    await V6LedgerMigrator.ensureSystemControlAccounts(this);
  }

  /// Seeds default settings and canonical starter categories ONLY on first run
  /// when [seedSentinelKey] is not yet recorded and without overwriting user rows.
  Future<void> seedDefaultsIfFirstRun() async {
    final existingSentinel = await (select(appSettings)
          ..where((tbl) => tbl.key.equals(seedSentinelKey)))
        .getSingleOrNull();
    if (existingSentinel != null && existingSentinel.value == 'true') {
      return;
    }

    final now = EthiopiaClock.nowUtc();

    await transaction(() async {
      // Seed default settings safely with insertOrIgnore
      await into(appSettings).insert(
        AppSettingsCompanion.insert(
          key: 'calendar_display_mode',
          value: 'dual',
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );
      await into(appSettings).insert(
        AppSettingsCompanion.insert(
          key: 'default_currency',
          value: SharedBusinessRules.currencyCode,
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );
      await into(appSettings).insert(
        AppSettingsCompanion.insert(
          key: openingBalanceKey,
          value: '${CanonicalSeedDatabase.state['openingBalanceCents'] ?? 0}',
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );

      final existingAccounts = await (select(accountsTable)
            ..where((tbl) => tbl.isSystem.equals(false))
            ..limit(1))
          .get();
      await into(appSettings).insert(
        AppSettingsCompanion.insert(
          key: financeSetupKey,
          value: existingAccounts.isNotEmpty ? 'true' : 'false',
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );

      // Seed canonical starter categories only if table is empty (never overwrite user edits)
      final existingCategories =
          await (select(financialCategories)..limit(1)).get();
      if (existingCategories.isEmpty) {
        final rawCategories =
            CanonicalSeedDatabase.state['categories'] as List<dynamic>? ??
                const [];
        for (final item in rawCategories) {
          final cat = item as Map<String, dynamic>;
          await into(financialCategories).insert(
            FinancialCategoriesCompanion.insert(
              id: cat['id'] as String,
              name: cat['name'] as String,
              type: cat['type'] as String,
              colorHex: Value((cat['colorHex'] as String?) ?? '#1B4D3E'),
              isDefault: Value((cat['isDefault'] as bool?) ?? false),
              isArchived: Value((cat['isArchived'] as bool?) ?? false),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      }

      await into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: seedSentinelKey,
          value: 'true',
          updatedAt: now,
        ),
      );
    });
  }

  /// Pre-v7 schema performance indices (safe to run before v7 columns/tables)
  Future<void> _createPreV7PerformanceIndices() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(due_date);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_transactions_date ON financial_transactions(transaction_date);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_inbox_processed ON inbox_items(is_processed);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_calendar_events_date ON calendar_events(date_iso);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_postings_entry_id ON postings_table(entry_id);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_postings_account_id ON postings_table(account_id);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_journal_entries_date_voided ON journal_entries_table(occurrence_date, is_voided);',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_journal_legacy_source '
      'ON journal_entries_table(legacy_source_tx_id) '
      'WHERE legacy_source_tx_id IS NOT NULL;',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_debts_party_status ON debts_table(party_id, status);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_commitments_due_paid '
      'ON financial_commitments(due_date, is_paid);',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_budgets_month_category '
      'ON budgets_table(month_iso, category_id);',
    );
  }

  /// Schema performance indices (including v7, v9, and v10 tables/columns)
  Future<void> createPerformanceIndices() async {
    await _createPreV7PerformanceIndices();
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_commitments_direction_paid '
      'ON financial_commitments(direction, is_paid);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_commitment_settlements_commitment '
      'ON commitment_settlements_table(commitment_id);',
    );
    final blockTableRows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name = 'project_tracking_blocks';",
    ).get();
    final recordTableRows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name = 'project_tracking_records';",
    ).get();
    if (blockTableRows.isNotEmpty && recordTableRows.isNotEmpty) {
      await _createV9ProjectPerformanceIndices();
    }
    final dailyPlanTableRows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name = 'daily_planning_entries';",
    ).get();
    final taskCols = await _existingTableColumns('tasks');
    if (dailyPlanTableRows.isNotEmpty &&
        taskCols.contains('my_day_date') &&
        taskCols.contains('is_archived') &&
        taskCols.contains('sort_order')) {
      await _createV10TaskPerformanceIndices();
    }
  }

  Future<void> _createV9ProjectPerformanceIndices() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_project_blocks_project_sort '
      'ON project_tracking_blocks(project_id, sort_order);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_project_records_project_block '
      'ON project_tracking_records(project_id, block_id);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_project_records_parent '
      'ON project_tracking_records(parent_record_id);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_project_records_recorded_date '
      'ON project_tracking_records(recorded_date);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_project_records_linked_task '
      'ON project_tracking_records(linked_task_id);',
    );
  }

  Future<void> _createV10TaskPerformanceIndices() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_planning_task_date '
      'ON daily_planning_entries(task_id, plan_date);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_daily_planning_plan_date '
      'ON daily_planning_entries(plan_date);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_my_day_date '
      'ON tasks(my_day_date);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_archived_sort '
      'ON tasks(is_archived, sort_order);',
    );
  }

  Future<void> _validateLegacyDatesBeforeV5Migration({
    required bool hasEndDateIso,
  }) async {
    const requiredColumns = <({String table, String column})>[
      (table: 'financial_transactions', column: 'transaction_date'),
      (table: 'financial_commitments', column: 'due_date'),
      (table: 'calendar_events', column: 'date_iso'),
      (table: 'journal_entries_table', column: 'occurrence_date'),
      (table: 'postings_table', column: 'account_movement_date'),
      (table: 'settlement_allocations_table', column: 'settlement_date'),
    ];
    final nullableColumns = <({String table, String column})>[
      (table: 'goals', column: 'target_date'),
      (table: 'projects', column: 'target_date'),
      (table: 'milestones', column: 'due_date'),
      (table: 'tasks', column: 'due_date'),
      (table: 'tasks', column: 'scheduled_date'),
      (table: 'savings_goals', column: 'target_date'),
      if (hasEndDateIso) (table: 'calendar_events', column: 'end_date_iso'),
      (table: 'accounts_table', column: 'opening_balance_date'),
      (table: 'debts_table', column: 'due_date'),
    ];

    final failures = <String>[];

    for (final spec in requiredColumns) {
      final expr = nullableDateToIsoSqlExpression(spec.column);
      final badRows = await customSelect(
        "SELECT id, COALESCE(CAST(${spec.column} AS TEXT), '<NULL>') AS raw_val "
        'FROM ${spec.table} '
        'WHERE ${spec.column} IS NULL '
        "OR trim(CAST(${spec.column} AS TEXT)) = '' "
        'OR ($expr) IS NULL '
        'LIMIT 3',
      ).get();
      if (badRows.isNotEmpty) {
        final sample = badRows.first;
        failures.add(
          '${spec.table}.${spec.column} '
          "(id=${sample.read<String>('id')}, "
          "value=${sample.read<String>('raw_val')})",
        );
      }
    }

    for (final spec in nullableColumns) {
      final expr = nullableDateToIsoSqlExpression(spec.column);
      final badRows = await customSelect(
        'SELECT id, CAST(${spec.column} AS TEXT) AS raw_val '
        'FROM ${spec.table} '
        'WHERE ${spec.column} IS NOT NULL '
        "AND trim(CAST(${spec.column} AS TEXT)) != '' "
        'AND ($expr) IS NULL '
        'LIMIT 3',
      ).get();
      if (badRows.isNotEmpty) {
        final sample = badRows.first;
        failures.add(
          '${spec.table}.${spec.column} '
          "(id=${sample.read<String>('id')}, "
          "value=${sample.read<String>('raw_val')})",
        );
      }
    }

    if (failures.isNotEmpty) {
      throw StateError(
        'Schema v4->v5 migration aborted cleanly to prevent silent data loss '
        'or today-date corruption. Uninterpretable date value(s) detected in: '
        "${failures.join('; ')}.",
      );
    }
  }

  static String _validatedCanonicalDateSql(String dateExpr) {
    return 'CASE '
        "WHEN ($dateExpr) GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' "
        "AND ($dateExpr) >= '0001-01-01' "
        "AND ($dateExpr) <= '9999-12-31' "
        'THEN ($dateExpr) '
        'ELSE NULL '
        'END';
  }

  static String _isBareTimestampSql(String expr) {
    final prefixDate = 'substr($expr, 1, 10)';
    return '('
        'date($prefixDate) = $prefixDate '
        "AND $prefixDate >= '0001-01-01' "
        "AND $prefixDate <= '9999-12-31' "
        'AND ('
        "($expr GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][T ][0-9][0-9]:[0-9][0-9]' AND length($expr) = 16) "
        "OR ($expr GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][T ][0-9][0-9]:[0-9][0-9]:[0-9][0-9]' AND length($expr) = 19) "
        "OR ($expr GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][T ][0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9]*' AND length($expr) >= 21 AND substr($expr, 21) NOT GLOB '*[^0-9]*')"
        ') '
        'AND datetime($expr) IS NOT NULL'
        ')';
  }

  /// Strict SQLite expression normalizing legacy numeric epochs (seconds or
  /// milliseconds) and ISO-8601 strings to canonical `YYYY-MM-DD` under
  /// Ethiopia UTC+3. Returns `NULL` for empty/null or uninterpretable/overflowing
  /// values without truncating trailing garbage or synthesizing fallback dates.
  static String nullableDateToIsoSqlExpression(String colName) {
    final trimmed = 'trim(CAST($colName AS TEXT))';
    final upperTrimmed = 'upper($trimmed)';
    final unsignedDigits =
        "CASE WHEN substr($trimmed, 1, 1) = '-' THEN substr($trimmed, 2) ELSE $trimmed END";
    final colonZoneNormalized =
        "substr($upperTrimmed, 1, length($upperTrimmed) - 2) || ':' || substr($upperTrimmed, length($upperTrimmed) - 1)";

    return 'CASE '
        "WHEN $colName IS NULL OR $trimmed = '' THEN NULL "
        "WHEN typeof($colName) IN ('integer', 'real') THEN "
        'CASE '
        'WHEN abs($colName) >= 100000000000 '
        "THEN ${_validatedCanonicalDateSql("date($colName / 1000.0, 'unixepoch', '+3 hours')")} "
        "ELSE ${_validatedCanonicalDateSql("date($colName, 'unixepoch', '+3 hours')")} "
        'END '
        "WHEN $unsignedDigits GLOB '[0-9]*' "
        "AND $unsignedDigits NOT GLOB '*[^0-9.]*' "
        "AND $unsignedDigits NOT GLOB '*.*.*' "
        "AND $unsignedDigits GLOB '*[0-9]*' "
        "AND substr($unsignedDigits, 1, 1) != '.' "
        "AND substr($unsignedDigits, length($unsignedDigits), 1) != '.' "
        'THEN '
        'CASE '
        "WHEN abs(CAST($trimmed AS REAL)) >= 100000000000 "
        "THEN ${_validatedCanonicalDateSql("date(CAST($trimmed AS REAL) / 1000.0, 'unixepoch', '+3 hours')")} "
        "ELSE ${_validatedCanonicalDateSql("date(CAST($trimmed AS REAL), 'unixepoch', '+3 hours')")} "
        'END '
        "WHEN $upperTrimmed GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*' THEN "
        'CASE '
        "WHEN length($upperTrimmed) = 10 "
        "AND date($upperTrimmed) = $upperTrimmed "
        "AND $upperTrimmed >= '0001-01-01' "
        "AND $upperTrimmed <= '9999-12-31' "
        'THEN $upperTrimmed '
        "WHEN length($upperTrimmed) >= 17 "
        "AND substr($upperTrimmed, length($upperTrimmed)) = 'Z' "
        "AND ${_isBareTimestampSql("substr($upperTrimmed, 1, length($upperTrimmed) - 1)")} "
        "THEN ${_validatedCanonicalDateSql("date($upperTrimmed, '+3 hours')")} "
        "WHEN length($upperTrimmed) >= 22 "
        "AND substr($upperTrimmed, length($upperTrimmed) - 5) GLOB '[+-][0-9][0-9]:[0-9][0-9]' "
        "AND ${_isBareTimestampSql("substr($upperTrimmed, 1, length($upperTrimmed) - 6)")} "
        "AND CAST(substr($upperTrimmed, length($upperTrimmed) - 4, 2) AS INTEGER) <= 23 "
        "AND CAST(substr($upperTrimmed, length($upperTrimmed) - 1, 2) AS INTEGER) <= 59 "
        "THEN ${_validatedCanonicalDateSql("date($upperTrimmed, '+3 hours')")} "
        "WHEN length($upperTrimmed) >= 21 "
        "AND substr($upperTrimmed, length($upperTrimmed) - 4) GLOB '[+-][0-9][0-9][0-9][0-9]' "
        "AND ${_isBareTimestampSql("substr($upperTrimmed, 1, length($upperTrimmed) - 5)")} "
        "AND CAST(substr($upperTrimmed, length($upperTrimmed) - 3, 2) AS INTEGER) <= 23 "
        "AND CAST(substr($upperTrimmed, length($upperTrimmed) - 1, 2) AS INTEGER) <= 59 "
        "THEN ${_validatedCanonicalDateSql("date($colonZoneNormalized, '+3 hours')")} "
        "WHEN ${_isBareTimestampSql(upperTrimmed)} "
        "THEN substr($upperTrimmed, 1, 10) "
        'ELSE NULL '
        'END '
        'ELSE NULL '
        'END';
  }

  /// Strict non-null normalization expression for required date columns.
  /// Never synthesizes today's date on bad inputs; combined with pre-flight
  /// validation and NOT NULL constraints, corrupt rows abort cleanly.
  static String requiredDateToIsoSqlExpression(String colName) {
    return nullableDateToIsoSqlExpression(colName);
  }

  static CustomExpression<String> _nullableDateToIsoSql(String colName) =>
      CustomExpression<String>(nullableDateToIsoSqlExpression(colName));

  static CustomExpression<String> _requiredDateToIsoSql(String colName) =>
      CustomExpression<String>(requiredDateToIsoSqlExpression(colName));
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'personal_management.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
