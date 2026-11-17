import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage 4.5 DriftFinanceRepository Integration Tests', () {
    late AppDatabase db;
    late DriftFinanceRepository repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.ensureInitialized();
      repo = DriftFinanceRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> seedStandardAccounts() async {
      await repo.completeFinanceSetup([
        AccountModel(
          id: 'acc-bank',
          name: 'CBE Bank',
          type: AccountType.asset,
          subType: AccountSubType.bank,
          openingBalanceCents: 1000000, // 10,000 ETB
          openingBalanceDate: '2026-11-01',
        ),
        AccountModel(
          id: 'acc-cash',
          name: 'Cash Wallet',
          type: AccountType.asset,
          subType: AccountSubType.cash,
          openingBalanceCents: 200000, // 2,000 ETB
          openingBalanceDate: '2026-11-01',
        ),
        AccountModel(
          id: 'acc-vault',
          name: 'Emergency Vault',
          type: AccountType.asset,
          subType: AccountSubType.savingsVault,
          openingBalanceCents: 500000, // 5,000 ETB
          openingBalanceDate: '2026-11-01',
        ),
      ]);
    }

    test(
      '1. Setup, direct income/expense, and transfer with fee maintain balanced ledger',
      () async {
        await seedStandardAccounts();
        final categories = await repo.getCategories();
        final expCat = categories.firstWhere((c) => c.type == 'expense');
        final incCat = categories.firstWhere((c) => c.type == 'income');

        await repo.recordDirectIncome(
          accountId: 'acc-bank',
          categoryId: incCat.id,
          amountCents: 400000, // +4,000 ETB
          date: CalendarDate(year: 2026, month: 11, day: 5),
          description: 'Monthly Salary',
        );

        await repo.recordDirectExpense(
          accountId: 'acc-cash',
          categoryId: expCat.id,
          amountCents: 50000, // -500 ETB
          date: CalendarDate(year: 2026, month: 11, day: 6),
          description: 'Groceries',
          payee: 'Shoa Market',
        );

        await repo.recordAccountTransfer(
          fromAccountId: 'acc-bank',
          toAccountId: 'acc-cash',
          amountCents: 100000, // 1,000 ETB
          transferFeeCents: 1500, // 15 ETB fee
          date: CalendarDate(year: 2026, month: 11, day: 7),
          description: 'ATM Withdrawal',
        );

        final accounts = await repo.getAccounts(includeSystem: true);
        final entries = await repo.getJournalEntries();
        final postings = await repo.getPostings();

        final bankBal = DoubleEntryEngine.calculateAccountBalance(
          account: accounts.firstWhere((a) => a.id == 'acc-bank'),
          postings: postings,
          entries: entries,
        );
        final cashBal = DoubleEntryEngine.calculateAccountBalance(
          account: accounts.firstWhere((a) => a.id == 'acc-cash'),
          postings: postings,
          entries: entries,
        );

        // Bank: 10,000 + 4,000 - 1,000 - 15 = 12,985 ETB
        expect(bankBal, 1298500);
        // Cash: 2,000 - 500 + 1,000 = 2,500 ETB
        expect(cashBal, 250000);

        final allCats = await repo.getCategories();
        expect(
          allCats.any((c) => c.id == SystemControlAccounts.feeCategoryId),
          isTrue,
        );

        final cashflow = DoubleEntryEngine.calculatePeriodCashflowTotals(
          accounts: accounts,
          postings: postings,
          entries: entries,
          startDateIso: '2026-11-01',
          endDateIso: '2026-11-30',
        );
        expect(cashflow.incomeCents, 400000);
        expect(cashflow.expenseCents, 51500); // 500 expense + 15 fee
      },
    );

    test(
      '2. Split expense creates balanced 3-leg entry and receivable debt atomically',
      () async {
        await seedStandardAccounts();
        final categories = await repo.getCategories();
        final expCat = categories.firstWhere((c) => c.type == 'expense');
        final party = await repo.createParty(
          PartyModel(id: 'party-sara', name: 'Sara'),
        );

        final entry = await repo.recordSplitExpense(
          paidAccountId: 'acc-bank',
          myCategoryId: expCat.id,
          myShareCents: 60000,
          theirShareCents: 40000,
          partyId: party.id,
          date: CalendarDate(year: 2026, month: 11, day: 8),
          dueDate: CalendarDate(year: 2026, month: 11, day: 20),
          description: 'Shared Dinner',
        );

        final postings = await repo.getPostings(entryId: entry.id);
        expect(postings.length, 3);
        DoubleEntryEngine.validateBalancedEntry(postings);

        final debts = await repo.getDebts(type: DebtType.receivable);
        expect(debts.length, 1);
        expect(debts.single.originEntryId, entry.id);
        expect(debts.single.outstandingCents, 40000);
      },
    );

    test(
      '3. Void, unvoid, correct entry, and write-off maintain debt & commitment consistency',
      () async {
        await seedStandardAccounts();
        final party = await repo.createParty(
          PartyModel(id: 'party-bekele', name: 'Bekele'),
        );

        final borrowPayload = DoubleEntryEngine.buildBorrowMoney(
          entryId: 'entry-borrow-1',
          debtId: 'debt-payable-1',
          partyId: party.id,
          destAssetAccountId: 'acc-cash',
          payableAccountId: SystemControlAccounts.payable,
          amountCents: 100000,
          date: '2026-11-05',
          dueDate: '2026-11-15',
          description: 'Borrowed from Bekele',
        );

        final debt = await repo.recordDebtWithEntry(
          entry: borrowPayload['entry'] as JournalEntryModel,
          postings: borrowPayload['postings'] as List<PostingModel>,
          debt: borrowPayload['debt'] as DebtModel,
        );

        final settlementPayload = DoubleEntryEngine.buildDebtSettlement(
          settlementEntryId: 'entry-settle-1',
          debt: debt,
          settlementAssetAccountId: 'acc-cash',
          debtAccountId: SystemControlAccounts.payable,
          allocatedPrincipalCents: 40000,
          settlementDate: '2026-11-10',
          description: 'Partial repayment',
        );

        await repo.recordSettlement(
          allocation:
              settlementPayload['allocation'] as SettlementAllocationModel,
          settlementEntry: settlementPayload['entry'] as JournalEntryModel,
          settlementPostings:
              settlementPayload['postings'] as List<PostingModel>,
          updatedDebt: settlementPayload['updatedDebt'] as DebtModel,
        );

        var currentDebt = (await repo.getDebts()).single;
        expect(currentDebt.outstandingCents, 60000);

        // Voiding settlement must restore outstanding to 100,000
        await repo.voidJournalEntry(
          entryId: 'entry-settle-1',
          voidReason: 'Entered wrong date',
        );
        currentDebt = (await repo.getDebts()).single;
        expect(currentDebt.outstandingCents, 100000);
        expect(currentDebt.status, DebtStatus.active);

        // Unvoiding settlement restores outstanding to 60,000
        await repo.unvoidJournalEntry('entry-settle-1');
        currentDebt = (await repo.getDebts()).single;
        expect(currentDebt.outstandingCents, 60000);

        // Write off remaining 60,000 payable
        final writtenOff = await repo.writeOffDebt(
          debtId: debt.id,
          reason: 'Debt forgiven',
          date: CalendarDate(year: 2026, month: 11, day: 12),
        );
        expect(writtenOff.outstandingCents, 0);
        expect(writtenOff.status, DebtStatus.writtenOff);

        final writeOffEntries = (await repo.getJournalEntries())
            .where((e) => e.entryType == EntryType.writeOff)
            .toList();
        expect(writeOffEntries.length, 1);

        // Correction entry voids original and sets correctedFromEntryId
        final categories = await repo.getCategories();
        final expCat = categories.firstWhere((c) => c.type == 'expense');
        final origExp = await repo.recordDirectExpense(
          accountId: 'acc-cash',
          categoryId: expCat.id,
          amountCents: 30000,
          date: CalendarDate(year: 2026, month: 11, day: 13),
          description: 'Wrong coffee amount',
        );
        final replacementBuilt = DoubleEntryEngine.buildDirectExpense(
          entryId: 'entry-corr-1',
          paidAccountId: 'acc-cash',
          categoryId: expCat.id,
          amountCents: 25000,
          date: '2026-11-13',
          description: 'Corrected coffee amount',
        );
        final corrected = await repo.correctJournalEntry(
          originalEntryId: origExp.id,
          replacementEntry: replacementBuilt['entry'] as JournalEntryModel,
          replacementPostings:
              replacementBuilt['postings'] as List<PostingModel>,
          correctionReason: 'Typo in receipt',
        );
        expect(corrected.correctedFromEntryId, origExp.id);

        final allEntries = await repo.getJournalEntries();
        final origAfter = allEntries.firstWhere((e) => e.id == origExp.id);
        expect(origAfter.isVoided, isTrue);
      },
    );

    test(
      '4. Commitment payment supports both expense bills and linked debt settlements, and unmarks on void',
      () async {
        await seedStandardAccounts();
        final categories = await repo.getCategories();
        final expCat = categories.firstWhere((c) => c.type == 'expense');
        final party = await repo.createParty(
          PartyModel(id: 'party-landlord', name: 'Landlord'),
        );

        final rentCommitment = await repo.addCommitment(
          CommitmentModel(
            id: 'com-rent',
            title: 'Monthly Rent',
            amountCents: 150000,
            dueDate: CalendarDate(year: 2026, month: 11, day: 15),
            linkedAccountId: 'acc-bank',
            categoryId: expCat.id,
          ),
        );

        final paidRent = await repo.markCommitmentPaidWithPosting(
          commitmentId: rentCommitment.id,
          accountId: 'acc-bank',
          paidDate: CalendarDate(year: 2026, month: 11, day: 15),
        );
        expect(paidRent.isPaid, isTrue);
        expect(paidRent.settlementEntryId, isNotNull);

        // Voiding settlement entry unmarks the commitment as paid
        await repo.voidJournalEntry(
          entryId: paidRent.settlementEntryId!,
          voidReason: 'Payment bounced',
        );
        final revertedRent = (await repo.getCommitments())
            .firstWhere((c) => c.id == rentCommitment.id);
        expect(revertedRent.isPaid, isFalse);
        expect(revertedRent.settlementEntryId, isNull);

        // Linked debt commitment settlement
        final borrowPayload = DoubleEntryEngine.buildBorrowMoney(
          entryId: 'entry-borrow-com',
          debtId: 'debt-com',
          partyId: party.id,
          destAssetAccountId: 'acc-cash',
          payableAccountId: SystemControlAccounts.payable,
          amountCents: 80000,
          date: '2026-11-02',
          dueDate: '2026-11-20',
          description: 'Short-term loan',
        );
        await repo.recordDebtWithEntry(
          entry: borrowPayload['entry'] as JournalEntryModel,
          postings: borrowPayload['postings'] as List<PostingModel>,
          debt: borrowPayload['debt'] as DebtModel,
        );

        final debtCommitment = await repo.addCommitment(
          CommitmentModel(
            id: 'com-debt',
            title: 'Repay Short-term Loan',
            amountCents: 80000,
            dueDate: CalendarDate(year: 2026, month: 11, day: 20),
            linkedDebtId: 'debt-com',
          ),
        );

        await repo.markCommitmentPaidWithPosting(
          commitmentId: debtCommitment.id,
          accountId: 'acc-bank',
          paidDate: CalendarDate(year: 2026, month: 11, day: 18),
        );
        final settledDebt =
            (await repo.getDebts()).firstWhere((d) => d.id == 'debt-com');
        expect(settledDebt.outstandingCents, 0);
        expect(settledDebt.status, DebtStatus.settled);
      },
    );

    test(
      '5. Vault-linked vs virtual savings goals sync vault ledger balance without double-counting',
      () async {
        await seedStandardAccounts();

        final vaultGoal = await repo.createSavingsGoal(
          SavingsGoalModel(
            id: 'goal-vault',
            title: 'Emergency Reserve',
            targetCents: 1000000,
            currentAllocatedCents: 500000,
            linkedAccountId: 'acc-vault',
          ),
        );
        final virtualGoal = await repo.createSavingsGoal(
          SavingsGoalModel(
            id: 'goal-virtual',
            title: 'New Laptop',
            targetCents: 300000,
            currentAllocatedCents: 50000,
          ),
        );

        // Fund vault goal by transferring 1,000 ETB from CBE Bank to Emergency Vault
        final updatedVaultGoal = await repo.fundSavingsGoal(
          goalId: vaultGoal.id,
          deltaCents: 100000,
          sourceAccountId: 'acc-bank',
          date: CalendarDate(year: 2026, month: 11, day: 9),
        );
        expect(updatedVaultGoal.currentAllocatedCents, 600000);

        // Virtual goal adjusts earmark without moving cash between accounts
        final updatedVirtualGoal = await repo.fundSavingsGoal(
          goalId: virtualGoal.id,
          deltaCents: 25000,
        );
        expect(updatedVirtualGoal.currentAllocatedCents, 75000);

        final snapshot = await repo.getFinancialSnapshot(
          openingBalanceCents: 0,
          periodStart: CalendarDate(year: 2026, month: 11, day: 1),
          periodEnd: CalendarDate(year: 2026, month: 11, day: 30),
          expectedFutureIncomeCents: const [],
        );
        // Liquid = Bank (10,000 - 1,000) + Cash (2,000) = 11,000 ETB (1,100,000)
        // Virtual Reserve = 750 ETB (75,000)
        // Vault (6,000 ETB) is NOT subtracted from Liquid
        // Available = 1,100,000 - 75,000 = 1,025,000 cents
        expect(snapshot.availableToSpendCents, 1025000);
      },
    );

    test(
      '6. Budgets upsert enforces unique (month, category) and recurring rules process idempotently',
      () async {
        await seedStandardAccounts();
        final categories = await repo.getCategories();
        final expCat = categories.firstWhere((c) => c.type == 'expense');

        final b1 = await repo.upsertBudget(
          BudgetModel(
            id: 'bud-1',
            categoryId: expCat.id,
            monthIso: '2026-11',
            limitCents: 200000,
          ),
        );
        expect(b1.limitCents, 200000);

        // Upsert different ID for same month+category updates existing row cleanly
        final b2 = await repo.upsertBudget(
          BudgetModel(
            id: 'bud-duplicate-id',
            categoryId: expCat.id,
            monthIso: '2026-11',
            limitCents: 250000,
            rolloverEnabled: true,
          ),
        );
        final budgets = await repo.getBudgets(monthIso: '2026-11');
        expect(budgets.length, 1);
        expect(budgets.single.limitCents, 250000);
        expect(budgets.single.rolloverEnabled, isTrue);
        expect(b2.id, b1.id);

        // Recurring rule 1: monthly autoPost expense starting Jan 31 clamped to Feb 28
        await repo.upsertRecurringRule(
          RecurringRuleModel(
            id: 'rec-auto',
            title: 'Internet Plan',
            ruleType: RecurringRuleType.expense,
            amountCents: 99000,
            frequency: RecurrenceFrequency.monthly,
            startDate: CalendarDate(year: 2026, month: 1, day: 31),
            nextOccurrenceDate: CalendarDate(year: 2026, month: 1, day: 31),
            endDate: CalendarDate(year: 2026, month: 2, day: 28),
            accountId: 'acc-bank',
            categoryId: expCat.id,
            autoPost: true,
          ),
        );

        // Recurring rule 2: weekly bill commitment (non-autoPost)
        await repo.upsertRecurringRule(
          RecurringRuleModel(
            id: 'rec-com',
            title: 'Weekly Market',
            ruleType: RecurringRuleType.commitment,
            amountCents: 50000,
            frequency: RecurrenceFrequency.weekly,
            startDate: CalendarDate(year: 2026, month: 2, day: 1),
            nextOccurrenceDate: CalendarDate(year: 2026, month: 2, day: 1),
            endDate: CalendarDate(year: 2026, month: 2, day: 10),
            accountId: 'acc-cash',
            categoryId: expCat.id,
            autoPost: false,
          ),
        );

        final firstRun = await repo.processDueRecurringRules(
          asOfDate: CalendarDate(year: 2026, month: 2, day: 28),
        );
        // 2 expense postings (Jan 31, Feb 28) + 2 commitments (Feb 1, Feb 8) = 4
        expect(firstRun, 4);

        // Running again is strictly idempotent
        final secondRun = await repo.processDueRecurringRules(
          asOfDate: CalendarDate(year: 2026, month: 2, day: 28),
        );
        expect(secondRun, 0);

        final rules = await repo.getRecurringRules();
        final autoRule = rules.firstWhere((r) => r.id == 'rec-auto');
        expect(autoRule.isActive, isFalse);

        final commitments = await repo.getCommitments();
        expect(commitments.length, 2);
      },
    );

    test(
      '7. Delete protection blocks deleting referenced accounts, categories, or system accounts',
      () async {
        await seedStandardAccounts();
        final categories = await repo.getCategories();
        final expCat = categories.firstWhere((c) => c.type == 'expense');

        // System accounts cannot be deleted or archived
        expect(
          await repo.deleteAccount(SystemControlAccounts.expense),
          isFalse,
        );
        await repo.archiveAccount(SystemControlAccounts.expense);
        final sysExpense =
            await repo.getAccountById(SystemControlAccounts.expense);
        expect(sysExpense?.isArchived, isFalse);

        // Account with postings cannot be deleted
        expect(await repo.deleteAccount('acc-bank'), isFalse);

        // Unused category with budget cannot be deleted
        final tempCat = await repo.createCategory(
          id: 'cat-temp',
          name: 'Temp Cat',
          type: 'expense',
        );
        await repo.upsertBudget(
          BudgetModel(
            id: 'bud-temp',
            categoryId: tempCat.id,
            monthIso: '2026-11',
            limitCents: 10000,
          ),
        );
        expect(await repo.deleteCategory(tempCat.id), isFalse);

        await repo.deleteBudget('bud-temp');
        expect(await repo.deleteCategory(tempCat.id), isTrue);

        // Expense category with child cannot be deleted
        final subCat = await repo.createCategory(
          id: 'cat-child',
          name: 'Coffee',
          type: 'expense',
          parentId: expCat.id,
        );
        expect(await repo.deleteCategory(expCat.id), isFalse);
        expect(await repo.deleteCategory(subCat.id), isTrue);
      },
    );

    test(
      '8. Stage 2.2 unvoidJournalEntry rejects excluded non-ETB/legacyOffset entries and markCommitmentPaid handles lowercase etb',
      () async {
        // Insert a legacy USD account and a voided USD journal entry
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
        await repo.recordJournalEntry(
          entry: JournalEntryModel(
            id: 'je-voided-usd',
            entryType: EntryType.standard,
            description: 'Voided USD expense',
            occurrenceDate: '2026-11-10',
            isVoided: true,
            voidReason: 'Excluded',
          ),
          postings: [
            PostingModel(
              id: 'p-vusd-1',
              entryId: 'je-voided-usd',
              accountId: SystemControlAccounts.expense,
              amountCents: 2500,
              direction: PostingDirection.debit,
              accountMovementDate: '2026-11-10',
            ),
            PostingModel(
              id: 'p-vusd-2',
              entryId: 'je-voided-usd',
              accountId: 'acc-usd-legacy',
              amountCents: 2500,
              direction: PostingDirection.credit,
              accountMovementDate: '2026-11-10',
            ),
          ],
        );

        await expectLater(
          repo.unvoidJournalEntry('je-voided-usd'),
          throwsA(isA<DoubleEntryValidationError>()),
        );

        // Lowercase 'etb' active asset account must be recognized by markCommitmentPaid
        // while unlinked commitments remain blocked under Stage 2.2 rules.
        await db.into(db.accountsTable).insert(
              AccountsTableCompanion.insert(
                id: 'acc-etb-lower',
                name: 'Lowercase ETB Cash',
                type: 'asset',
                subType: const Value('cash'),
                currencyCode: const Value('etb'),
                createdAt: DateTime.utc(2026, 11, 1),
              ),
            );
        await repo.addCommitment(
          CommitmentModel(
            id: 'com-unlinked-stage22',
            title: 'Unlinked Historical Bill',
            amountCents: 15000,
            dueDate: CalendarDate(year: 2026, month: 11, day: 15),
            direction: CommitmentDirection.outflow,
          ),
        );
        await expectLater(
          repo.markCommitmentPaid(
            'com-unlinked-stage22',
            createExpenseTransaction: true,
          ),
          throwsA(isA<DoubleEntryValidationError>()),
        );

        await repo.upsertRecurringRule(
          RecurringRuleModel(
            id: 'rec-lower-etb',
            title: 'Monthly Phone Bill',
            ruleType: RecurringRuleType.commitment,
            amountCents: 15000,
            frequency: RecurrenceFrequency.monthly,
            startDate: CalendarDate(year: 2026, month: 11, day: 1),
            nextOccurrenceDate: CalendarDate(year: 2026, month: 11, day: 15),
            accountId: 'acc-etb-lower',
          ),
        );
        await repo.addCommitment(
          CommitmentModel(
            id: 'com-lower-etb',
            title: 'Phone Bill',
            amountCents: 15000,
            dueDate: CalendarDate(year: 2026, month: 11, day: 15),
            direction: CommitmentDirection.outflow,
            recurringRuleId: 'rec-lower-etb',
          ),
        );
        await repo.markCommitmentPaid(
          'com-lower-etb',
          createExpenseTransaction: true,
        );
        final settled =
            await repo.getCommitmentSettlements(commitmentId: 'com-lower-etb');
        expect(settled.length, 1);
      },
    );

    test(
      '9. Stage 2.2 restoreTransaction rejects unlinked, non-ETB, and '
      'legacy clearing-offset records before writing',
      () async {
        await seedStandardAccounts();
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
        final categories = await repo.getCategories();
        final expCat = categories.firstWhere((c) => c.type == 'expense');

        // 1) Unlinked pre-v7 transaction (accountId == null) must fail closed
        // without creating a fallback ETB transaction or journal entry.
        await expectLater(
          repo.restoreTransaction(
            TransactionModel(
              id: 'tx-unlinked-restore',
              categoryId: expCat.id,
              categoryName: expCat.name,
              amountCents: 4500,
              type: 'expense',
              transactionDate: CalendarDate(year: 2026, month: 11, day: 12),
              note: 'Unlinked legacy',
            ),
          ),
          throwsA(isA<DoubleEntryValidationError>()),
        );
        final unlinkedRow = await (db.select(db.financialTransactions)
              ..where((t) => t.id.equals('tx-unlinked-restore')))
            .getSingleOrNull();
        expect(unlinkedRow, isNull);

        // 2) Non-ETB account transaction must fail closed.
        await expectLater(
          repo.restoreTransaction(
            TransactionModel(
              id: 'tx-usd-restore',
              categoryId: expCat.id,
              categoryName: expCat.name,
              amountCents: 3000,
              type: 'expense',
              transactionDate: CalendarDate(year: 2026, month: 11, day: 12),
              accountId: 'acc-usd-legacy',
              note: 'USD expense',
            ),
          ),
          throwsA(isA<DoubleEntryValidationError>()),
        );

        // 3) Existing voided entry touching acc-sys-legacy-offset must fail.
        await repo.recordJournalEntry(
          entry: JournalEntryModel(
            id: 'entry-tx-clearing-restore',
            entryType: EntryType.standard,
            description: 'Legacy clearing entry',
            occurrenceDate: '2026-11-12',
            isVoided: true,
            voidReason: 'Deleted',
            legacySourceTxId: 'tx-clearing-restore',
          ),
          postings: [
            PostingModel(
              id: 'p-clr-1',
              entryId: 'entry-tx-clearing-restore',
              accountId: SystemControlAccounts.legacyOffset,
              amountCents: 2000,
              direction: PostingDirection.debit,
              accountMovementDate: '2026-11-12',
            ),
            PostingModel(
              id: 'p-clr-2',
              entryId: 'entry-tx-clearing-restore',
              accountId: 'acc-bank',
              amountCents: 2000,
              direction: PostingDirection.credit,
              accountMovementDate: '2026-11-12',
            ),
          ],
        );
        await expectLater(
          repo.restoreTransaction(
            TransactionModel(
              id: 'tx-clearing-restore',
              categoryId: expCat.id,
              categoryName: expCat.name,
              amountCents: 2000,
              type: 'expense',
              transactionDate: CalendarDate(year: 2026, month: 11, day: 12),
              accountId: 'acc-bank',
              note: 'Cleared item',
            ),
          ),
          throwsA(isA<DoubleEntryValidationError>()),
        );

        // 4) Valid deleted ETB transaction restores cleanly and unvoids entry.
        final validTx = TransactionModel(
          id: 'tx-etb-restore',
          categoryId: expCat.id,
          categoryName: expCat.name,
          amountCents: 5000,
          type: 'expense',
          transactionDate: CalendarDate(year: 2026, month: 11, day: 12),
          accountId: 'acc-bank',
          note: 'Groceries',
        );
        await repo.recordTransaction(validTx);
        await repo.deleteTransaction('tx-etb-restore');
        await repo.restoreTransaction(validTx);
        final restoredRow = await (db.select(db.financialTransactions)
              ..where((t) => t.id.equals('tx-etb-restore')))
            .getSingleOrNull();
        expect(restoredRow, isNotNull);
        final restoredEntry = await (db.select(db.journalEntriesTable)
              ..where((e) => e.legacySourceTxId.equals('tx-etb-restore')))
            .getSingle();
        expect(restoredEntry.isVoided, isFalse);
      },
    );
  });
}
