import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/finance/finance_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage 4.6 FinanceController & FinanceModuleState Tests', () {
    late AppDatabase db;
    late DriftFinanceRepository repo;
    late FinanceController controller;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.ensureInitialized();
      repo = DriftFinanceRepository(db);
      controller = FinanceController(repository: repo);
      await controller.loadAll();
    });

    tearDown(() async {
      controller.dispose();
      await db.close();
    });

    test(
      '1. Setup, opening balance update, and direct cashflows unify on double-entry ledger',
      () async {
        expect(controller.state.isSetupCompleted, isFalse);
        expect(controller.state.accounts, isEmpty);

        await controller.completeSetup([
          AccountModel(
            id: 'acc-cbe',
            name: 'CBE Checking',
            type: AccountType.asset,
            subType: AccountSubType.bank,
            openingBalanceCents: 1000000,
            openingBalanceDate: '2026-11-01',
          ),
          AccountModel(
            id: 'acc-vault',
            name: 'Emergency Vault',
            type: AccountType.asset,
            subType: AccountSubType.savingsVault,
            openingBalanceCents: 500000,
            openingBalanceDate: '2026-11-01',
          ),
        ]);

        expect(controller.state.isSetupCompleted, isTrue);
        expect(controller.state.accounts.length, 2);
        expect(controller.state.liquidCashCents, 1000000);
        expect(controller.state.vaultSavingsCents, 500000);
        expect(controller.state.combinedBalanceCents, 1500000);

        final categories = controller.state.activeCategories;
        final expCat = categories.firstWhere((c) => c.type == 'expense');
        final incCat = categories.firstWhere((c) => c.type == 'income');

        await controller.recordDirectIncome(
          accountId: 'acc-cbe',
          categoryId: incCat.id,
          amountCents: 300000,
          date: CalendarDate(year: 2026, month: 11, day: 5),
          description: 'Bonus',
        );
        await controller.recordDirectExpense(
          accountId: 'acc-cbe',
          categoryId: expCat.id,
          amountCents: 120000,
          date: CalendarDate(year: 2026, month: 11, day: 6),
          description: 'Supermarket',
        );

        expect(controller.state.totalIncomeCents, 300000);
        expect(controller.state.totalExpenseCents, 120000);
        expect(controller.state.liquidCashCents, 1180000);

        final spendMap = controller.state.categorySpendForMonth('2026-11');
        expect(spendMap[expCat.id], 120000);

        // Update opening balance syncs ledger cleanly
        await controller.updateAccountOpeningBalance(
          accountId: 'acc-cbe',
          newOpeningBalanceCents: 1100000,
          openingDate: '2026-11-01',
        );
        expect(controller.state.liquidCashCents, 1280000);
      },
    );

    test(
      '2. Debts, settlements, write-offs, commitments, vaults, budgets, and recurring rules stay consistent',
      () async {
        await controller.completeSetup([
          AccountModel(
            id: 'acc-cash',
            name: 'Cash',
            type: AccountType.asset,
            subType: AccountSubType.cash,
            openingBalanceCents: 2000000,
            openingBalanceDate: '2026-11-01',
          ),
          AccountModel(
            id: 'acc-vault',
            name: 'House Vault',
            type: AccountType.asset,
            subType: AccountSubType.savingsVault,
            openingBalanceCents: 0,
            openingBalanceDate: '2026-11-01',
          ),
        ]);

        controller.setPlanningPeriodEnd(
          CalendarDate(year: 2026, month: 11, day: 30),
        );

        final partyId = await controller.ensurePartyId('Dawit');
        final expCat = controller.state.activeCategories
            .firstWhere((c) => c.type == 'expense');

        // Borrow 5,000 ETB due Nov 25 -> LiquidCash = 25,000, DuePayable = 5,000 -> Available = 20,000
        final payableDebt = await controller.borrowMoney(
          partyId: partyId,
          destinationAccountId: 'acc-cash',
          amountCents: 500000,
          date: CalendarDate(year: 2026, month: 11, day: 4),
          dueDate: CalendarDate(year: 2026, month: 11, day: 25),
          description: 'Emergency loan',
        );
        expect(payableDebt, isNotNull);
        expect(controller.state.liquidCashCents, 2500000);
        expect(controller.state.duePayablesCents, 500000);
        expect(controller.state.availableToSpendCents, 2000000);

        // Settle 2,000 ETB -> LiquidCash = 23,000, DuePayable = 3,000 -> Available = 20,000
        await controller.recordDoubleEntrySettlement(
          debt: payableDebt!,
          settlementAssetAccountId: 'acc-cash',
          allocatedCents: 200000,
          settlementDate: '2026-11-10',
          description: 'Repay Dawit',
        );
        expect(controller.state.duePayablesCents, 300000);
        expect(controller.state.availableToSpendCents, 2000000);

        // Add vault goal & fund 4,000 ETB -> LiquidCash = 19,000, Vault = 4,000, Available = 16,000
        await controller.addSavingsGoal(
          SavingsGoalModel(
            id: 'goal-house',
            title: 'House Downpayment',
            targetCents: 1000000,
            linkedAccountId: 'acc-vault',
          ),
        );
        await controller.fundSavingsGoal(
          goalId: 'goal-house',
          deltaCents: 400000,
          sourceAccountId: 'acc-cash',
          date: CalendarDate(year: 2026, month: 11, day: 12),
        );
        expect(controller.state.vaultSavingsCents, 400000);
        expect(controller.state.availableToSpendCents, 1600000);

        // Budget & recurring rule workflows
        await controller.upsertBudget(
          BudgetModel(
            id: 'bud-nov',
            categoryId: expCat.id,
            monthIso: '2026-11',
            limitCents: 300000,
          ),
        );
        expect(controller.state.budgets.length, 1);

        await controller.upsertRecurringRule(
          RecurringRuleModel(
            id: 'rec-rent',
            title: 'Rent',
            ruleType: RecurringRuleType.commitment,
            amountCents: 200000,
            frequency: RecurrenceFrequency.monthly,
            startDate: CalendarDate(year: 2026, month: 11, day: 15),
            nextOccurrenceDate: CalendarDate(year: 2026, month: 11, day: 15),
            accountId: 'acc-cash',
            categoryId: expCat.id,
          ),
        );
        final generated = await controller.processDueRecurringRules(
          asOfDate: CalendarDate(year: 2026, month: 11, day: 20),
        );
        expect(generated, 1);
        expect(controller.state.dueNonDebtCommitmentsCents, 200000);
        expect(controller.state.availableToSpendCents, 1400000);

        // Pay commitment on ledger -> LiquidCash drops by 2,000, dueNonDebtCommitments drops to 0
        final commitId = controller.state.commitments.single.id;
        await controller.markCommitmentPaidWithPosting(
          commitmentId: commitId,
          accountId: 'acc-cash',
          paidDate: CalendarDate(year: 2026, month: 11, day: 15),
        );
        expect(controller.state.dueNonDebtCommitmentsCents, 0);
        expect(controller.state.liquidCashCents, 1700000);
        expect(controller.state.availableToSpendCents, 1400000);
      },
    );

    test(
      '3. Controller propagates errors cleanly into state.errorMessage without losing responsiveness',
      () async {
        await controller.recordDirectExpense(
          accountId: 'nonexistent-acc',
          categoryId: 'nonexistent-cat',
          amountCents: -50,
          date: CalendarDate(year: 2026, month: 11, day: 1),
          description: 'Invalid',
        );
        expect(controller.state.errorMessage, isNotNull);
        expect(controller.state.isLoading, isFalse);
      },
    );

    test(
      '4. Default planningPeriodEnd uses endOfGregorianMonth and Option 1 PrepaidCardCredit flows into AvailableToSpend & NetPosition',
      () async {
        final today = CalendarDate.today();
        expect(
          controller.state.effectivePlanningPeriodEnd,
          today.endOfGregorianMonth,
        );

        await controller.completeSetup([
          AccountModel(
            id: 'acc-cbe',
            name: 'CBE',
            type: AccountType.asset,
            subType: AccountSubType.bank,
            openingBalanceCents: 1000000, // 10,000 ETB
            openingBalanceDate: '2026-11-01',
          ),
          AccountModel(
            id: 'acc-cc',
            name: 'Visa Card',
            type: AccountType.liability,
            subType: AccountSubType.creditCard,
            openingBalanceCents: 0,
            openingBalanceDate: '2026-11-01',
          ),
        ]);

        final expCat = controller.state.activeCategories
            .firstWhere((c) => c.type == 'expense');

        // Spend 1,200 ETB on credit card -> ShortTermCreditOwed = 1,200, Avail = 8,800
        await controller.recordDirectExpense(
          accountId: 'acc-cc',
          categoryId: expCat.id,
          amountCents: 120000,
          date: CalendarDate(year: 2026, month: 11, day: 5),
          description: 'Flight ticket',
        );
        expect(controller.state.shortTermCreditOwedCents, 120000);
        expect(controller.state.prepaidCardCreditCents, 0);
        expect(controller.state.availableToSpendCents, 880000);

        // Repay 1,400 ETB (crossing zero -> -200 ETB prepaid card credit)
        await controller.recordTransfer(
          fromAssetAccountId: 'acc-cbe',
          toAssetAccountId: 'acc-cc',
          amountCents: 140000,
          date: '2026-11-06',
          description: 'Overpay credit card',
        );
        expect(controller.state.liquidCashCents, 860000);
        expect(controller.state.shortTermCreditOwedCents, 0);
        expect(controller.state.prepaidCardCreditCents, 20000);
        // Option 1: PrepaidCardCredit included in AvailableToSpend & NetPosition
        expect(controller.state.availableToSpendCents, 880000);
        expect(controller.state.netFinancialPositionCents, 880000);
      },
    );

    test(
      '5. v7 partial outflow/inflow commitments, releaseAndArchiveSavingsGoal, :rev:n history, voidDebtOrigin, and recurring skip/pause/resume',
      () async {
        await controller.completeSetup([
          AccountModel(
            id: 'acc-bank',
            name: 'Bank',
            type: AccountType.asset,
            subType: AccountSubType.bank,
            openingBalanceCents: 500000,
            openingBalanceDate: '2026-11-01',
          ),
        ]);

        await controller.reviseOpeningBalance(
          accountId: 'acc-bank',
          newOpeningBalanceCents: 600000,
          reason: 'Statement reconciliation',
        );
        final history = await controller.getOpeningBalanceHistory('acc-bank');
        expect(history.length, 2);
        expect(controller.state.liquidCashCents, 600000);

        controller.setPlanningPeriodEnd(
          CalendarDate(year: 2026, month: 11, day: 30),
        );

        final expCat = controller.state.activeCategories
            .firstWhere((c) => c.type == 'expense');
        final incCat = controller.state.activeCategories
            .firstWhere((c) => c.type == 'income');

        // Expected inflow contributes 0 until actually received
        await controller.addCommitment(
          CommitmentModel(
            id: 'com-inc',
            title: 'Freelance Milestone',
            amountCents: 400000,
            dueDate: CalendarDate(year: 2026, month: 11, day: 20),
            direction: CommitmentDirection.inflow,
            linkedAccountId: 'acc-bank',
            categoryId: incCat.id,
          ),
        );
        expect(controller.state.liquidCashCents, 600000);
        expect(controller.state.availableToSpendCents, 600000);
        expect(controller.state.totalIncomeCents, 0);

        final csIn = await controller.recordCommitmentSettlement(
          commitmentId: 'com-inc',
          accountId: 'acc-bank',
          amountCents: 150000,
          settledDate: CalendarDate(year: 2026, month: 11, day: 20),
        );
        expect(csIn, isNotNull);
        expect(controller.state.liquidCashCents, 750000);
        expect(controller.state.totalIncomeCents, 150000);

        // Overfunded virtual goal releases reserve when archived
        await controller.addSavingsGoal(
          SavingsGoalModel(
            id: 'goal-v',
            title: 'Emergency Cash Reserve',
            targetCents: 100000,
            currentAllocatedCents: 150000,
          ),
        );
        expect(controller.state.virtualSavingsReservedCents, 150000);
        await controller.releaseAndArchiveSavingsGoal('goal-v');
        expect(controller.state.virtualSavingsReservedCents, 0);
        expect(controller.state.activeSavingsGoals, isEmpty);
        expect(controller.state.archivedSavingsGoals.length, 1);

        // Debt voidOrigin works when unblocked
        final partyId = await controller.ensurePartyId('Yohannes');
        final debt = await controller.lendMoney(
          partyId: partyId,
          sourceAccountId: 'acc-bank',
          amountCents: 100000,
          date: CalendarDate(year: 2026, month: 11, day: 10),
          description: 'Short loan',
        );
        expect(debt, isNotNull);
        final voidedDebt = await controller.voidDebtOrigin(
          debtId: debt!.id,
          reason: 'Entered in error',
        );
        expect(voidedDebt?.status, DebtStatus.voided);
        expect(controller.state.debtControlAudit?.isTierABalanced, isTrue);

        // Pause, skipNextOccurrence, resume on recurring rule
        await controller.upsertRecurringRule(
          RecurringRuleModel(
            id: 'rec-skip',
            title: 'Water Bill',
            ruleType: RecurringRuleType.commitment,
            amountCents: 30000,
            frequency: RecurrenceFrequency.monthly,
            startDate: CalendarDate(year: 2026, month: 11, day: 1),
            nextOccurrenceDate: CalendarDate(year: 2026, month: 11, day: 1),
            accountId: 'acc-bank',
            categoryId: expCat.id,
          ),
        );
        final skipped = await controller.skipNextOccurrence('rec-skip');
        expect(
          skipped?.nextOccurrenceDate,
          CalendarDate(year: 2026, month: 12, day: 1),
        );
        final paused = await controller.pauseRecurringRule('rec-skip');
        expect(paused?.isActive, isFalse);
        final resumed = await controller.resumeRecurringRule(
          'rec-skip',
          today: CalendarDate(year: 2027, month: 2, day: 15),
        );
        expect(resumed?.isActive, isTrue);
        expect(
          resumed!.nextOccurrenceDate >=
              CalendarDate(year: 2027, month: 2, day: 15),
          isTrue,
        );
      },
    );

    test(
      '2. Stage 2.2 strict ETB-only controller guards block non-ETB account creation and addDoubleEntryDirectExpense',
      () async {
        await controller.completeSetup([
          AccountModel(
            id: 'acc-etb',
            name: 'ETB Bank',
            type: AccountType.asset,
            subType: AccountSubType.bank,
            currencyCode: 'ETB',
            openingBalanceCents: 100000,
          ),
        ]);

        // Persisted non-ETB account injected into SQLite (legacy/imported simulation)
        await db.into(db.accountsTable).insert(
              AccountsTableCompanion.insert(
                id: 'acc-usd-legacy',
                name: 'Legacy USD',
                type: 'asset',
                subType: const Value('bank'),
                currencyCode: const Value('USD'),
                createdAt: DateTime.utc(2026, 11, 1),
              ),
            );
        await controller.loadAll();

        await controller.addAccount(
          name: 'Euro Wallet',
          type: AccountType.asset,
          currencyCode: 'EUR',
        );
        expect(controller.state.errorMessage, contains('ETB'));
        expect(
          controller.state.accounts.any((a) => a.name == 'Euro Wallet'),
          isFalse,
        );

        final beforeEntriesCount = controller.state.journalEntries.length;
        await controller.addDoubleEntryDirectExpense(
          assetAccountId: 'acc-usd-legacy',
          expenseAccountId: SystemControlAccounts.expense,
          amountCents: 5000,
          description: 'USD lunch attempt',
          occurrenceDate: '2026-11-15',
        );
        expect(controller.state.errorMessage, contains('ETB'));
        expect(controller.state.journalEntries.length, beforeEntriesCount);
      },
    );
  });
}
