import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/finance/finance_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/database_persistence_coordinator.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';
import 'package:personal_management_app/services/export/finance_export_service.dart';
import 'package:personal_management_app/ui/screens/finance/finance_reports_tab.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Finance Stage F4 — Reporting, Exports, Portability & Verification',
      () {
    late AppDatabase db;
    late DriftFinanceRepository repo;
    late FinanceController controller;
    late DatabasePersistenceCoordinator coordinator;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.ensureInitialized();
      repo = DriftFinanceRepository(db);
      controller = FinanceController(repository: repo);
      coordinator = DatabasePersistenceCoordinator(db);
      await controller.completeSetup([
        AccountModel(
          id: 'acc-bank',
          name: 'CBE Checking',
          type: AccountType.asset,
          subType: AccountSubType.bank,
          currencyCode: 'ETB',
          openingBalanceCents: 1000000,
          openingBalanceDate: '2026-01-01',
        ),
        AccountModel(
          id: 'acc-vault',
          name: 'Emergency Vault',
          type: AccountType.asset,
          subType: AccountSubType.savingsVault,
          currencyCode: 'ETB',
          openingBalanceCents: 300000,
          openingBalanceDate: '2026-01-01',
        ),
        AccountModel(
          id: 'acc-card-prepaid',
          name: 'Prepaid Card',
          type: AccountType.liability,
          subType: AccountSubType.creditCard,
          currencyCode: 'ETB',
          openingBalanceCents: -25000, // Prepaid credit per Option 1
          openingBalanceDate: '2026-01-01',
        ),
        AccountModel(
          id: 'acc-card-owed',
          name: 'Revolving Credit',
          type: AccountType.liability,
          subType: AccountSubType.creditCard,
          currencyCode: 'ETB',
          openingBalanceCents: 40000, // Owed balance
          openingBalanceDate: '2026-01-01',
        ),
      ]);
      // Insert non-ETB and unverified accounts directly to test strict ETB isolation.
      await db.into(db.accountsTable).insert(
            AccountsTableCompanion.insert(
              id: 'acc-usd',
              name: 'USD Offshore',
              type: 'asset',
              subType: const Value('bank'),
              currencyCode: const Value('USD'),
              openingBalanceCents: const Value(150000),
              createdAt: DateTime.utc(2026, 1, 1),
            ),
          );
      await db.into(db.accountsTable).insert(
            AccountsTableCompanion.insert(
              id: 'acc-unverified',
              name: 'Legacy Blank Currency',
              type: 'asset',
              subType: const Value('cash'),
              currencyCode: const Value(''),
              openingBalanceCents: const Value(50000),
              createdAt: DateTime.utc(2026, 1, 1),
            ),
          );
      await controller.loadAll();
    });

    tearDown(() async {
      controller.dispose();
      await db.close();
    });

    test(
      'Workflow 1 & 2: Dual-calendar Pagume 5/6 resolution, safe deltas, and Occurrence P&L vs Cash Flow separation',
      () async {
        // Pagume 2018 E.C. (2018 % 4 == 2 -> 5 days) vs 2019 E.C. (2019 % 4 == 3 -> 6 days)
        final nonLeapPagume =
            DoubleEntryEngine.resolveReportPeriodWithComparison(
          mode: ReportPeriodMode.ethiopianMonth,
          ethYear: 2018,
          ethMonth: 13,
          todayIso: '2026-09-08',
        );
        expect(nonLeapPagume.daysInCurrent, 5);
        expect(nonLeapPagume.daysInPrevious, 30);

        final leapPagume = DoubleEntryEngine.resolveReportPeriodWithComparison(
          mode: ReportPeriodMode.ethiopianMonth,
          ethYear: 2019,
          ethMonth: 13,
          todayIso: '2027-09-10',
        );
        expect(leapPagume.daysInCurrent, 6);

        // Record expense occurring in Oct 2026, settled in cash in Nov 2026
        await controller.recordDirectExpense(
          accountId: 'acc-bank',
          categoryId: 'cat-utilities',
          amountCents: 75000,
          date: CalendarDate(year: 2026, month: 10, day: 30),
          movementDate: CalendarDate(year: 2026, month: 11, day: 2),
          description: 'Utility Invoice',
        );
        // Transfer to Vault in Nov must NOT inflate P&L expense
        await controller.recordTransfer(
          fromAssetAccountId: 'acc-bank',
          toAssetAccountId: 'acc-vault',
          amountCents: 100000,
          date: '2026-11-05',
          description: 'Vault Deposit',
        );

        final novPeriod = DoubleEntryEngine.resolveReportPeriodWithComparison(
          mode: ReportPeriodMode.thisMonth,
          todayIso: '2026-11-15',
        );
        final cmp = DoubleEntryEngine.calculatePeriodComparisonReport(
          period: novPeriod,
          accounts: controller.state.accounts,
          entries: controller.state.journalEntries,
          postings: controller.state.postings,
          debts: controller.state.debts,
          allocations: controller.state.settlementAllocations,
        );

        // Oct occurrence has expense; Oct cashflow is 0
        expect(cmp.previousOccurrence.expenseCents, 75000);
        expect(cmp.previousLiquidCash.outflowCents, 0);
        // Nov occurrence has 0 expense; Nov cashflow has 750 + 1000 outflows
        expect(cmp.currentOccurrence.expenseCents, 0);
        expect(cmp.currentLiquidCash.outflowCents, 175000);

        // Safe zero-baseline percentage change verification
        final zeroBasePos =
            DoubleEntryEngine.calculateSafePercentageChange(0, 50000);
        expect(zeroBasePos.percentageDisplay, '+100% (New)');
        final dropToZero =
            DoubleEntryEngine.calculateSafePercentageChange(75000, 0);
        expect(dropToZero.percentageDisplay, '-100.0%');
      },
    );

    test(
      'Workflow 3: Hierarchical category spend, alias matching, cycle safety, void exclusion, and Plan/Report budget parity',
      () async {
        // Insert nested subcategory + cyclic pair + legacy alias category
        await db.into(db.financialCategories).insert(
              FinancialCategoriesCompanion.insert(
                id: 'cat-food-dining',
                name: 'Dining Out',
                type: 'expense',
                parentId: const Value('cat-food'),
                sortOrder: const Value(50),
              ),
            );
        await db.into(db.financialCategories).insert(
              FinancialCategoriesCompanion.insert(
                id: 'cat-food-coffee',
                name: 'Buna & Cafes',
                type: 'expense',
                parentId: const Value('cat-food-dining'),
                sortOrder: const Value(51),
              ),
            );
        await db.into(db.financialCategories).insert(
              FinancialCategoriesCompanion.insert(
                id: 'cat-communication',
                name: 'Legacy Telecom',
                type: 'expense',
                sortOrder: const Value(52),
              ),
            );
        await db.into(db.financialCategories).insert(
              FinancialCategoriesCompanion.insert(
                id: 'cat-cycle-a',
                name: 'Cycle A',
                type: 'expense',
                sortOrder: const Value(53),
              ),
            );
        await db.into(db.financialCategories).insert(
              FinancialCategoriesCompanion.insert(
                id: 'cat-cycle-b',
                name: 'Cycle B',
                type: 'expense',
                parentId: const Value('cat-cycle-a'),
                sortOrder: const Value(54),
              ),
            );
        await (db.update(db.financialCategories)
              ..where((t) => t.id.equals('cat-cycle-a')))
            .write(
          const FinancialCategoriesCompanion(
            parentId: Value('cat-cycle-b'),
          ),
        );

        await controller.recordDirectExpense(
          accountId: 'acc-bank',
          categoryId: 'cat-food-coffee',
          amountCents: 20000,
          date: CalendarDate(year: 2026, month: 11, day: 10),
          description: 'Coffee',
        );
        await controller.recordDirectExpense(
          accountId: 'acc-bank',
          categoryId: 'cat-food',
          amountCents: 50000,
          date: CalendarDate(year: 2026, month: 11, day: 11),
          description: 'Groceries',
        );
        await controller.recordDirectExpense(
          accountId: 'acc-bank',
          categoryId: 'cat-communication',
          amountCents: 15000,
          date: CalendarDate(year: 2026, month: 11, day: 12),
          description: 'Airtime',
        );
        final toVoid = await controller.recordDirectExpense(
          accountId: 'acc-bank',
          categoryId: 'cat-food',
          amountCents: 99900,
          date: CalendarDate(year: 2026, month: 11, day: 12),
          description: 'Voided Spend',
        );
        await controller.voidJournalEntry(toVoid!.id, 'Duplicate');
        await controller.recordDirectExpense(
          accountId: 'acc-bank',
          categoryId: 'cat-cycle-a',
          amountCents: 5000,
          date: CalendarDate(year: 2026, month: 11, day: 13),
          description: 'Cycle Guard',
        );

        await controller.upsertBudget(
          BudgetModel(
            id: 'bud-food-nov',
            categoryId: 'cat-food',
            monthIso: '2026-11',
            limitCents: 60000,
            createdAt: DateTime.utc(2026, 11, 1),
            updatedAt: DateTime.utc(2026, 11, 1),
          ),
        );

        final spend = DoubleEntryEngine.calculateCanonicalCategorySpend(
          entries: controller.state.journalEntries,
          postings: controller.state.postings,
          accounts: controller.state.accounts,
          categories: controller.state.categories,
          debts: controller.state.debts,
          allocations: controller.state.settlementAllocations,
          startDateIso: '2026-11-01',
          endDateIso: '2026-11-30',
        );

        // Total is 200 + 500 + 150 + 50 = 900 ETB (no double counting; voided excluded)
        expect(spend.totalExpenseCents, 90000);
        expect(spend.directSpendByCategoryId['cat-food'], 50000);
        expect(spend.rollupSpendByCategoryId['cat-food'], 70000);

        final budgetReport = DoubleEntryEngine.buildMonthlyBudgetProgressReport(
          budgets: controller.state.budgets,
          categories: controller.state.categories,
          entries: controller.state.journalEntries,
          postings: controller.state.postings,
          accounts: controller.state.accounts,
          debts: controller.state.debts,
          allocations: controller.state.settlementAllocations,
          monthIso: '2026-11',
        );
        final foodItem = budgetReport.items.single;
        expect(foodItem.spentCents, 70000);
        expect(foodItem.isOverBudget, isTrue);
        expect(
          DoubleEntryEngine.getCanonicalBudgetSpentCents(
            spend,
            'cat-food',
            controller.state.categories,
          ),
          foodItem.spentCents,
        );
      },
    );

    test(
      'Workflow 4 & 5: Vaults, Credit Card Option 1, Aligned Balance Sheet & Strict Currency Isolation',
      () async {
        final abebeId = await controller.ensurePartyId('Abebe');
        await controller.lendMoney(
          partyId: abebeId,
          sourceAccountId: 'acc-bank',
          amountCents: 200000,
          date: CalendarDate(year: 2026, month: 11, day: 2),
          dueDate: CalendarDate(year: 2026, month: 11, day: 25),
          description: 'Receivable Loan',
        );
        await controller.borrowMoney(
          partyId: abebeId,
          destinationAccountId: 'acc-bank',
          amountCents: 120000,
          date: CalendarDate(year: 2026, month: 11, day: 3),
          dueDate: CalendarDate(year: 2026, month: 11, day: 28),
          description: 'Payable In Horizon',
        );
        await controller.borrowMoney(
          partyId: abebeId,
          destinationAccountId: 'acc-bank',
          amountCents: 80000,
          date: CalendarDate(year: 2026, month: 11, day: 4),
          dueDate: CalendarDate(year: 2026, month: 12, day: 20),
          description: 'Payable Outside Horizon',
        );
        await controller.addSavingsGoal(
          SavingsGoalModel(
            id: 'sg-vault',
            title: 'Vault Linked Goal',
            targetCents: 900000,
            currentAllocatedCents: 0,
            linkedAccountId: 'acc-vault',
            status: SavingsGoalStatus.active,
          ),
        );

        final balances = DoubleEntryEngine.buildAccountBalancesReport(
          accounts: controller.state.accounts,
          entries: controller.state.journalEntries,
          postings: controller.state.postings,
        );
        expect(balances.liquidTotalCents, 1000000);
        expect(balances.vaultTotalCents, 300000);
        expect(balances.prepaidCardCreditTotalCents, 25000);
        expect(balances.creditCardOwedTotalCents, 40000);
        expect(balances.nonEtbReviewAccounts.length, 2);

        final savings = DoubleEntryEngine.buildSavingsVaultsAndGoalsReport(
          accounts: controller.state.accounts,
          entries: controller.state.journalEntries,
          postings: controller.state.postings,
          savingsGoals: controller.state.savingsGoals,
        );
        expect(savings.goals.single.allocatedCents, 300000);

        final breakdown = controller.state
            .copyWith(
              planningPeriodEnd: CalendarDate(year: 2026, month: 11, day: 30),
            )
            .availableToSpendBreakdown;
        final bs = DoubleEntryEngine.buildAlignedBalanceSheetReport(
          accounts: controller.state.accounts,
          entries: controller.state.journalEntries,
          postings: controller.state.postings,
          debts: controller.state.debts,
          allocations: controller.state.settlementAllocations,
          breakdown: breakdown,
        );
        expect(bs.liquidCashCents, 1000000);
        expect(bs.vaultSavingsCents, 300000);
        expect(bs.receivablesCents, 200000);
        expect(bs.prepaidCardCreditCents, 25000);
        expect(bs.shortTermCreditOwedCents, 40000);
        expect(bs.activePayablesCents, 200000);
        expect(bs.duePayablesCents, 120000);
        expect(bs.netFinancialPositionCents, 1285000);
      },
    );

    test(
      'Workflow 6: All 13 UTF-8 BOM CSVs (Amharic safe) & 13-table SQLite analytical export with topological categories',
      () async {
        await db.into(db.financialCategories).insert(
              FinancialCategoriesCompanion.insert(
                id: 'cat-amharic',
                name: 'ምግብ / ቡና',
                type: 'expense',
                parentId: const Value('cat-food'),
                sortOrder: const Value(77),
              ),
            );
        await controller.recordDirectExpense(
          accountId: 'acc-bank',
          categoryId: 'cat-amharic',
          amountCents: 15000,
          date: CalendarDate(year: 2026, month: 11, day: 12),
          description: 'የምግብ ወጪ',
        );
        await controller.loadAll();

        final st = controller.state;
        final csvOutputs = [
          FinanceExportService.exportAccountsCsv(
            st.accounts,
            st.postings,
            entries: st.journalEntries,
          ),
          FinanceExportService.exportCategoriesCsv(st.categories),
          FinanceExportService.exportPartiesCsv(st.parties),
          FinanceExportService.exportJournalEntriesCsv(
            st.journalEntries,
            postings: st.postings,
            accounts: st.accounts,
          ),
          FinanceExportService.exportPostingsCsv(st.postings),
          FinanceExportService.exportDebtsCsv(
            st.debts,
            entries: st.journalEntries,
            postings: st.postings,
            accounts: st.accounts,
          ),
          FinanceExportService.exportSettlementAllocationsCsv(
            st.settlementAllocations,
          ),
          FinanceExportService.exportCommitmentsCsv(
            st.commitments,
            accounts: st.accounts,
          ),
          FinanceExportService.exportCommitmentSettlementsCsv(
            st.commitmentSettlements,
          ),
          FinanceExportService.exportSavingsGoalsCsv(st.savingsGoals),
          FinanceExportService.exportBudgetsCsv(st.budgets),
          FinanceExportService.exportRecurringRulesCsv(st.recurringRules),
          FinanceExportService.exportTransactionsCsv(
            st.transactions,
            entries: st.journalEntries,
          ),
        ];
        expect(csvOutputs.length, 13);
        for (final csv in csvOutputs) {
          expect(csv.startsWith('\uFEFF'), isTrue);
        }
        expect(csvOutputs[1].contains('ምግብ / ቡና'), isTrue);

        // Reverse categories so child appears before parent in input list
        final reversedCats = st.categories.reversed.toList();
        final sql = FinanceExportService.exportSqliteAnalyticalScript(
          accounts: st.accounts,
          parties: st.parties,
          entries: st.journalEntries,
          postings: st.postings,
          debts: st.debts,
          allocations: st.settlementAllocations,
          categories: reversedCats,
          budgets: st.budgets,
          recurringRules: st.recurringRules,
          commitments: st.commitments,
          commitmentSettlements: st.commitmentSettlements,
          savingsGoals: st.savingsGoals,
          transactions: st.transactions,
        );

        for (final table in const [
          'accounts',
          'categories',
          'parties',
          'journal_entries',
          'postings',
          'debts',
          'settlement_allocations',
          'commitments',
          'commitment_settlements',
          'savings_goals',
          'budgets',
          'recurring_rules',
          'transactions',
        ]) {
          expect(sql.contains('CREATE TABLE IF NOT EXISTS $table'), isTrue);
        }
        expect(sql.contains('a.is_system = 0'), isTrue);
        final parentIdx =
            sql.indexOf("INSERT INTO categories VALUES ('cat-food'");
        final childIdx =
            sql.indexOf("INSERT INTO categories VALUES ('cat-amharic'");
        expect(parentIdx, greaterThan(0));
        expect(childIdx, greaterThan(parentIdx));
      },
    );

    test(
      'Workflow 7 & 8: Finance-only JSON portability preserves non-Finance tables intact, rejects full backups/unbalanced payloads fail-closed, and accepts Web/legacy snapshots',
      () async {
        // Seed non-Finance tables that MUST remain completely untouched across Finance-only restore.
        final nowUtc = DateTime.utc(2026, 11, 1);
        await db.into(db.goals).insert(
              GoalsCompanion.insert(
                id: 'goal-1',
                title: 'Preserve Goal',
                createdAt: nowUtc,
              ),
            );
        await db.into(db.projects).insert(
              ProjectsCompanion.insert(
                id: 'proj-1',
                title: 'Preserve Project',
                createdAt: nowUtc,
              ),
            );
        await db.into(db.projectTrackingBlocks).insert(
              ProjectTrackingBlocksCompanion.insert(
                id: 'blk-1',
                projectId: 'proj-1',
                blockType: 'counter',
                title: 'Emails',
                createdAt: nowUtc,
                updatedAt: nowUtc,
              ),
            );
        await db.into(db.projectTrackingRecords).insert(
              ProjectTrackingRecordsCompanion.insert(
                id: 'rec-1',
                projectId: 'proj-1',
                blockId: 'blk-1',
                recordType: 'progress_log',
                deltaValue: const Value(5),
                createdAt: nowUtc,
                updatedAt: nowUtc,
              ),
            );
        await db.into(db.milestones).insert(
              MilestonesCompanion.insert(
                id: 'ms-1',
                projectId: 'proj-1',
                title: 'Preserve Milestone',
                createdAt: nowUtc,
              ),
            );
        await db.into(db.tasks).insert(
              TasksCompanion.insert(
                id: 'task-1',
                title: 'Preserve Task',
                projectId: const Value('proj-1'),
                createdAt: nowUtc,
                updatedAt: nowUtc,
              ),
            );
        await db.into(db.notes).insert(
              NotesCompanion.insert(
                id: 'note-1',
                title: 'Preserve Note',
                content: 'Keep content',
                createdAt: nowUtc,
                updatedAt: nowUtc,
              ),
            );
        await db.into(db.inboxItems).insert(
              InboxItemsCompanion.insert(
                id: 'inb-1',
                rawText: 'Keep Inbox',
                createdAt: nowUtc,
              ),
            );
        await db.into(db.calendarEvents).insert(
              CalendarEventsCompanion.insert(
                id: 'ev-1',
                title: 'Keep Event',
                dateIso: '2026-11-20',
                createdAt: nowUtc,
                updatedAt: nowUtc,
              ),
            );
        await db.into(db.reminders).insert(
              RemindersCompanion.insert(
                id: 'rem-1',
                targetId: 'task-1',
                targetType: 'task',
                title: const Value('Keep Reminder'),
                triggerTimeUtc: nowUtc,
                createdAt: nowUtc,
              ),
            );
        await db.into(db.appSettings).insert(
              AppSettingsCompanion.insert(
                key: 'theme_mode',
                value: 'dark',
                updatedAt: nowUtc,
              ),
            );

        await controller.recordDirectExpense(
          accountId: 'acc-bank',
          categoryId: 'cat-food',
          amountCents: 18000,
          date: CalendarDate(year: 2026, month: 11, day: 15),
          description: 'Exported Expense',
        );

        final exportedRaw = await controller.exportFinanceOnlyJson();
        final exportedMap = jsonDecode(exportedRaw) as Map<String, dynamic>;
        expect(exportedMap['financeOnly'], isTrue);
        expect(exportedMap['exportScope'], 'finance_only');
        for (final key in const [
          'tasks',
          'notes',
          'projects',
          'projectTrackingBlocks',
          'projectTrackingRecords',
          'milestones',
          'goals',
          'inboxItems',
          'calendarEvents',
          'reminders',
          'appSettings',
        ]) {
          expect(exportedMap.containsKey(key), isFalse);
        }

        // Wipe Finance & restore from Finance-only JSON
        await controller.recordDirectExpense(
          accountId: 'acc-bank',
          categoryId: 'cat-transport',
          amountCents: 22000,
          date: CalendarDate(year: 2026, month: 11, day: 16),
          description: 'Ephemeral Expense Before Restore',
        );
        expect(
          controller.state.journalEntries.any(
            (e) => e.description == 'Ephemeral Expense Before Restore',
          ),
          isTrue,
        );

        final ok = await controller.importFinanceOnlyJson(exportedRaw);
        expect(ok, isTrue);
        expect(controller.state.errorMessage, isNull);
        expect(
          controller.state.journalEntries.any(
            (e) => e.description == 'Ephemeral Expense Before Restore',
          ),
          isFalse,
        );
        expect(
          controller.state.journalEntries.any(
            (e) => e.description == 'Exported Expense',
          ),
          isTrue,
        );

        // Verify ALL non-Finance tables survived intact + foreign keys valid
        expect((await db.select(db.tasks).get()).single.id, 'task-1');
        expect((await db.select(db.notes).get()).single.id, 'note-1');
        expect((await db.select(db.projects).get()).single.id, 'proj-1');
        expect(
          (await db.select(db.projectTrackingBlocks).get()).single.id,
          'blk-1',
        );
        expect(
          (await db.select(db.projectTrackingRecords).get()).single.id,
          'rec-1',
        );
        expect((await db.select(db.milestones).get()).single.id, 'ms-1');
        expect((await db.select(db.goals).get()).single.id, 'goal-1');
        expect((await db.select(db.inboxItems).get()).single.id, 'inb-1');
        expect((await db.select(db.calendarEvents).get()).single.id, 'ev-1');
        expect((await db.select(db.reminders).get()).single.id, 'rem-1');
        final savedTheme = await (db.select(db.appSettings)
              ..where((t) => t.key.equals('theme_mode')))
            .getSingle();
        expect(savedTheme.value, 'dark');
        expect(
          (await db.customSelect('PRAGMA foreign_key_check').get()).isEmpty,
          isTrue,
        );

        // Reject full cross-module backup
        final fullBackup = jsonEncode(await coordinator.exportSnapshot());
        final rejectFull = await controller.importFinanceOnlyJson(fullBackup);
        expect(rejectFull, isFalse);
        expect(controller.state.errorMessage, contains('Settings'));

        // Reject invalid JSON
        expect(await controller.importFinanceOnlyJson('{not json'), isFalse);

        // Reject unbalanced journal entries fail-closed without touching DB
        final unbalancedMap = Map<String, dynamic>.from(exportedMap);
        final rawPostings =
            List<dynamic>.from(exportedMap['postings'] as List<dynamic>);
        unbalancedMap['postings'] = [rawPostings.first];
        expect(
          await controller.importFinanceOnlyJson(jsonEncode(unbalancedMap)),
          isFalse,
        );
        expect(
          controller.state.journalEntries.any(
            (e) => e.description == 'Exported Expense',
          ),
          isTrue,
        );

        // Workflow 8: Accept Web-exported v5 / legacy schemaVersion 4 Finance-only snapshot cleanly
        final legacyWebJson = jsonEncode({
          'financeOnly': true,
          'exportScope': 'finance_only',
          'schemaVersion': 4,
          'isFinanceSetupCompleted': true,
          'openingBalanceCents': 50000,
          'accounts': [
            {
              'id': 'acc-web-etb',
              'name': 'Web Telebirr',
              'type': 'asset',
              'subType': 'mobile_money',
              'currencyCode': 'ETB',
              'openingBalanceCents': 50000,
              'isArchived': false,
              'createdAt': '2026-01-01T00:00:00Z',
            }
          ],
          'categories': [
            {
              'id': 'cat-other-exp',
              'name': 'Other',
              'type': 'expense',
              'colorHex': '#94A3B8',
              'isDefault': true,
            }
          ],
          'transactions': [],
        });
        expect(await controller.importFinanceOnlyJson(legacyWebJson), isTrue);
        expect(
          controller.state.accounts.any((a) => a.id == 'acc-web-etb'),
          isTrue,
        );
      },
    );

    testWidgets(
      'Widget: FinanceReportsTab renders Stage F4 sections cleanly with no overflow',
      (tester) async {
        await controller.recordDirectExpense(
          accountId: 'acc-bank',
          categoryId: 'cat-food',
          amountCents: 25000,
          date: CalendarDate(year: 2026, month: 11, day: 10),
          description: 'Widget Report Expense',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: FinanceReportsTab(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Report Period'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Balance Sheet Snapshot (ETB)'),
          300,
        );
        expect(find.text('Balance Sheet Snapshot (ETB)'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Finance-Only Portability (JSON)'),
          300,
        );
        expect(find.text('Finance-Only Portability (JSON)'), findsOneWidget);
        expect(
          find.text('Analytical SQLite Script (13 Tables)'),
          findsOneWidget,
        );
        expect(
          find.text('Individual Finance CSV Tables (13 UTF-8 BOM)'),
          findsOneWidget,
        );
      },
    );
  });
}
