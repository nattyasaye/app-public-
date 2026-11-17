import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/domain/finance/double_entry_engine.dart';
import 'package:personal_management_app/domain/finance/finance_models.dart';

void main() {
  group('Stage 4.4 — DoubleEntryEngine & AvailableToSpend(H) V6 Tests', () {
    late AccountModel cbe;
    late AccountModel telebirr;
    late AccountModel cash;
    late AccountModel vault;
    late AccountModel creditCard;
    late AccountModel sysEquity;
    late AccountModel sysIncome;
    late AccountModel sysExpense;
    late AccountModel sysReceivable;
    late AccountModel sysPayable;

    setUp(() {
      cbe = AccountModel(
        id: 'acc-cbe',
        name: 'CBE',
        type: AccountType.asset,
        subType: AccountSubType.bank,
      );
      telebirr = AccountModel(
        id: 'acc-telebirr',
        name: 'Telebirr',
        type: AccountType.asset,
        subType: AccountSubType.mobileMoney,
      );
      cash = AccountModel(
        id: 'acc-cash',
        name: 'Cash',
        type: AccountType.asset,
        subType: AccountSubType.cash,
      );
      vault = AccountModel(
        id: 'acc-vault',
        name: 'Emergency Vault',
        type: AccountType.asset,
        subType: AccountSubType.savingsVault,
      );
      creditCard = AccountModel(
        id: 'acc-cc',
        name: 'Credit Card',
        type: AccountType.liability,
        subType: AccountSubType.creditCard,
      );
      sysEquity = AccountModel(
        id: SystemControlAccounts.equity,
        name: 'Opening Equity',
        type: AccountType.equity,
        subType: AccountSubType.openingEquity,
        isSystem: true,
      );
      sysIncome = AccountModel(
        id: SystemControlAccounts.income,
        name: 'Income Control',
        type: AccountType.income,
        subType: AccountSubType.nominalIncome,
        isSystem: true,
      );
      sysExpense = AccountModel(
        id: SystemControlAccounts.expense,
        name: 'Expense Control',
        type: AccountType.expense,
        subType: AccountSubType.nominalExpense,
        isSystem: true,
      );
      sysReceivable = AccountModel(
        id: SystemControlAccounts.receivable,
        name: 'Receivable Control',
        type: AccountType.asset,
        subType: AccountSubType.receivable,
        isSystem: true,
      );
      sysPayable = AccountModel(
        id: SystemControlAccounts.payable,
        name: 'Payable Control',
        type: AccountType.liability,
        subType: AccountSubType.payable,
        isSystem: true,
      );
    });

    test('All 6 Numerical AvailableToSpend(H) Examples (H = 2026-11-30)', () {
      const periodEnd = '2026-11-30';
      final allAccounts = [
        cbe,
        telebirr,
        cash,
        vault,
        creditCard,
        sysEquity,
        sysIncome,
        sysExpense,
        sysReceivable,
        sysPayable,
      ];

      // 1. Dedicated Savings Vault: CBE 20,000 ETB, Vault 8,000 ETB, goal linked to vault
      final open1 = DoubleEntryEngine.buildOpeningBalance(
        entryId: 'e-open-cbe-1',
        account: cbe,
        overrideAmountCents: 2000000,
        date: '2026-11-01',
      );
      final openVault = DoubleEntryEngine.buildOpeningBalance(
        entryId: 'e-open-vault-1',
        account: vault,
        overrideAmountCents: 800000,
        date: '2026-11-01',
      );
      final vaultGoal = SavingsGoalModel(
        id: 'sg-emerg',
        title: 'Emergency Fund',
        targetCents: 1000000,
        currentAllocatedCents: 800000,
        linkedAccountId: vault.id,
      );
      final ex1 = DoubleEntryEngine.calculateAvailableToSpendBreakdown(
        accounts: allAccounts,
        postings: [
          ...open1['postings'] as List<PostingModel>,
          ...openVault['postings'] as List<PostingModel>,
        ],
        entries: [
          open1['entry'] as JournalEntryModel,
          openVault['entry'] as JournalEntryModel,
        ],
        debts: const [],
        commitments: const [],
        savingsGoals: [vaultGoal],
        periodEndIso: periodEnd,
      );
      expect(ex1.liquidCashCents, 2000000);
      expect(ex1.vaultSavingsCents, 800000);
      expect(ex1.virtualSavingsReservedCents, 0);
      expect(ex1.availableToSpendCents, 2000000);

      // 2. Virtual Earmarked Savings Reservation Inside Checking
      final laptopGoal = SavingsGoalModel(
        id: 'sg-laptop',
        title: 'New Laptop',
        targetCents: 1200000,
        currentAllocatedCents: 600000,
        linkedAccountId: null,
      );
      final ex2 = DoubleEntryEngine.calculateAvailableToSpendBreakdown(
        accounts: allAccounts,
        postings: open1['postings'] as List<PostingModel>,
        entries: [open1['entry'] as JournalEntryModel],
        debts: const [],
        commitments: const [],
        savingsGoals: [laptopGoal],
        periodEndIso: periodEnd,
      );
      expect(ex2.liquidCashCents, 2000000);
      expect(ex2.virtualSavingsReservedCents, 600000);
      expect(ex2.availableToSpendCents, 1400000);

      // 3. Unpaid Commitments: Current Period vs Future Month + Payment invariance
      final openCash = DoubleEntryEngine.buildOpeningBalance(
        entryId: 'e-open-cash',
        account: cash,
        overrideAmountCents: 1500000,
        date: '2026-11-01',
      );
      final rentCommitment = CommitmentModel(
        id: 'com-rent',
        title: 'Rent',
        amountCents: 800000,
        dueDate: CalendarDate(year: 2026, month: 11, day: 28),
        isPaid: false,
        linkedAccountId: cash.id,
      );
      final futureInsurance = CommitmentModel(
        id: 'com-ins',
        title: 'Insurance',
        amountCents: 400000,
        dueDate: CalendarDate(year: 2026, month: 12, day: 15),
        isPaid: false,
      );
      final paidWater = CommitmentModel(
        id: 'com-water',
        title: 'Water',
        amountCents: 50000,
        dueDate: CalendarDate(year: 2026, month: 11, day: 10),
        isPaid: true,
      );
      final ex3Before = DoubleEntryEngine.calculateAvailableToSpendBreakdown(
        accounts: allAccounts,
        postings: openCash['postings'] as List<PostingModel>,
        entries: [openCash['entry'] as JournalEntryModel],
        debts: const [],
        commitments: [rentCommitment, futureInsurance, paidWater],
        savingsGoals: const [],
        periodEndIso: periodEnd,
      );
      expect(ex3Before.dueNonDebtCommitmentsCents, 800000);
      expect(ex3Before.availableToSpendCents, 700000);

      final rentPayment = DoubleEntryEngine.buildCommitmentPayment(
        entryId: 'e-pay-rent',
        paidAccountId: cash.id,
        categoryId: 'cat-rent',
        amountCents: 800000,
        date: '2026-11-20',
        commitmentTitle: 'Rent',
      );
      final ex3After = DoubleEntryEngine.calculateAvailableToSpendBreakdown(
        accounts: allAccounts,
        postings: [
          ...openCash['postings'] as List<PostingModel>,
          ...rentPayment['postings'] as List<PostingModel>,
        ],
        entries: [
          openCash['entry'] as JournalEntryModel,
          rentPayment['entry'] as JournalEntryModel,
        ],
        debts: const [],
        commitments: [
          rentCommitment.copyWith(isPaid: true),
          futureInsurance,
          paidWater,
        ],
        savingsGoals: const [],
        periodEndIso: periodEnd,
      );
      expect(ex3After.liquidCashCents, 700000);
      expect(ex3After.availableToSpendCents, 700000);

      // 4. Payable Debt + Partial Settlement + Linked Debt Reminder
      final openTel = DoubleEntryEngine.buildOpeningBalance(
        entryId: 'e-open-tel',
        account: telebirr,
        overrideAmountCents: 700000,
        date: '2026-11-01',
      );
      final borrowNow = DoubleEntryEngine.buildBorrowMoney(
        entryId: 'e-borrow-due',
        debtId: 'debt-landlord',
        partyId: 'party-landlord',
        destAssetAccountId: telebirr.id,
        payableAccountId: sysPayable.id,
        amountCents: 300000,
        date: '2026-11-02',
        dueDate: '2026-11-25',
        description: 'Borrowed from landlord',
      );
      final futureLoan = DebtModel(
        id: 'debt-future',
        originEntryId: 'e-future',
        partyId: 'party-bank',
        debtType: DebtType.payable,
        principalCents: 500000,
        outstandingCents: 500000,
        dueDate: '2027-02-01',
      );
      final linkedReminder = CommitmentModel(
        id: 'com-debt-rem',
        title: 'Repay landlord',
        amountCents: 300000,
        dueDate: CalendarDate(year: 2026, month: 11, day: 25),
        linkedDebtId: 'debt-landlord',
      );
      final landlordDebt = borrowNow['debt'] as DebtModel;
      final stepA = DoubleEntryEngine.calculateAvailableToSpendBreakdown(
        accounts: allAccounts,
        postings: [
          ...openTel['postings'] as List<PostingModel>,
          ...borrowNow['postings'] as List<PostingModel>,
        ],
        entries: [
          openTel['entry'] as JournalEntryModel,
          borrowNow['entry'] as JournalEntryModel,
        ],
        debts: [landlordDebt, futureLoan],
        commitments: [linkedReminder],
        savingsGoals: const [],
        periodEndIso: periodEnd,
      );
      expect(stepA.liquidCashCents, 1000000);
      expect(stepA.duePayablesCents, 300000);
      expect(stepA.dueNonDebtCommitmentsCents, 0);
      expect(stepA.availableToSpendCents, 700000);

      final settlePartial = DoubleEntryEngine.buildDebtSettlement(
        settlementEntryId: 'e-settle-part',
        debt: landlordDebt,
        settlementAssetAccountId: telebirr.id,
        debtAccountId: sysPayable.id,
        allocatedPrincipalCents: 120000,
        settlementDate: '2026-11-12',
        description: 'Partial settlement',
      );
      final stepB = DoubleEntryEngine.calculateAvailableToSpendBreakdown(
        accounts: allAccounts,
        postings: [
          ...openTel['postings'] as List<PostingModel>,
          ...borrowNow['postings'] as List<PostingModel>,
          ...settlePartial['postings'] as List<PostingModel>,
        ],
        entries: [
          openTel['entry'] as JournalEntryModel,
          borrowNow['entry'] as JournalEntryModel,
          settlePartial['entry'] as JournalEntryModel,
        ],
        debts: [settlePartial['updatedDebt'] as DebtModel, futureLoan],
        commitments: [linkedReminder],
        savingsGoals: const [],
        periodEndIso: periodEnd,
      );
      expect(stepB.liquidCashCents, 880000);
      expect(stepB.duePayablesCents, 180000);
      expect(stepB.availableToSpendCents, 700000);

      // 5. Receivable Debt + Split Expense Strictly Excluded from Safe Harbor
      final cbeOpen12 = DoubleEntryEngine.buildOpeningBalance(
        entryId: 'e-cbe-12',
        account: cbe,
        overrideAmountCents: 1200000,
        date: '2026-11-01',
      );
      final split = DoubleEntryEngine.buildSplitExpense(
        entryId: 'e-split-dinner',
        debtId: 'debt-abebe',
        partyId: 'party-abebe',
        myExpenseAccountId: sysExpense.id,
        receivableAccountId: sysReceivable.id,
        paidAssetAccountId: cbe.id,
        myShareCents: 40000,
        theirShareCents: 60000,
        occurrenceDate: '2026-11-10',
        description: 'Dinner split',
        categoryId: 'cat-food',
      );
      final ex5 = DoubleEntryEngine.calculateAvailableToSpendBreakdown(
        accounts: allAccounts,
        postings: [
          ...cbeOpen12['postings'] as List<PostingModel>,
          ...split['postings'] as List<PostingModel>,
        ],
        entries: [
          cbeOpen12['entry'] as JournalEntryModel,
          split['entry'] as JournalEntryModel,
        ],
        debts: [split['debt'] as DebtModel],
        commitments: const [],
        savingsGoals: const [],
        periodEndIso: periodEnd,
      );
      expect(ex5.liquidCashCents, 1100000);
      expect(ex5.receivablesCents, 60000);
      expect(ex5.availableToSpendCents, 1100000);

      // 6. Credit Card / Liability Account Combined with Bills
      final openCash5 = DoubleEntryEngine.buildOpeningBalance(
        entryId: 'e-open-cash-5',
        account: cash,
        overrideAmountCents: 500000,
        date: '2026-11-01',
      );
      final openBank15 = DoubleEntryEngine.buildOpeningBalance(
        entryId: 'e-open-bank-15',
        account: cbe,
        overrideAmountCents: 1500000,
        date: '2026-11-01',
      );
      final openCard = DoubleEntryEngine.buildOpeningBalance(
        entryId: 'e-open-cc',
        account: creditCard,
        overrideAmountCents: 350000,
        date: '2026-11-01',
      );
      final electricBill = CommitmentModel(
        id: 'com-elec',
        title: 'Electric',
        amountCents: 150000,
        dueDate: CalendarDate(year: 2026, month: 11, day: 20),
        linkedAccountId: cbe.id,
      );
      final ex6 = DoubleEntryEngine.calculateAvailableToSpendBreakdown(
        accounts: allAccounts,
        postings: [
          ...openCash5['postings'] as List<PostingModel>,
          ...openBank15['postings'] as List<PostingModel>,
          ...openCard['postings'] as List<PostingModel>,
        ],
        entries: [
          openCash5['entry'] as JournalEntryModel,
          openBank15['entry'] as JournalEntryModel,
          openCard['entry'] as JournalEntryModel,
        ],
        debts: const [],
        commitments: [electricBill],
        savingsGoals: const [],
        periodEndIso: periodEnd,
      );
      expect(ex6.liquidCashCents, 2000000);
      expect(ex6.shortTermCreditOwedCents, 350000);
      expect(ex6.dueNonDebtCommitmentsCents, 150000);
      expect(ex6.availableToSpendCents, 1500000);
    });

    test(
      'Period Cashflow & Category Spend Rollup exclude transfers, opening equity, '
      'debt principal, and voided entries',
      () {
        final categories = [
          TransactionCategoryModel(
            id: 'cat-food',
            name: 'Food',
            type: 'expense',
          ),
          TransactionCategoryModel(
            id: 'cat-groceries',
            name: 'Groceries',
            type: 'expense',
            parentId: 'cat-food',
          ),
          TransactionCategoryModel(
            id: 'cat-fees',
            name: 'Fees',
            type: 'expense',
          ),
          TransactionCategoryModel(
            id: 'cat-salary',
            name: 'Salary',
            type: 'income',
          ),
        ];
        final allAccounts = [
          cbe,
          cash,
          telebirr,
          sysEquity,
          sysIncome,
          sysExpense,
          sysReceivable,
          sysPayable,
        ];

        final open = DoubleEntryEngine.buildOpeningBalance(
          entryId: 'e-open',
          account: cbe,
          overrideAmountCents: 1000000,
          date: '2026-11-01',
        );
        final inc = DoubleEntryEngine.buildDirectIncome(
          entryId: 'e-inc',
          destAccountId: cbe.id,
          categoryId: 'cat-salary',
          amountCents: 2500000,
          date: '2026-11-03',
          description: 'Monthly salary',
        );
        final exp = DoubleEntryEngine.buildDirectExpense(
          entryId: 'e-exp',
          paidAccountId: cbe.id,
          categoryId: 'cat-groceries',
          amountCents: 45000,
          date: '2026-11-05',
          description: 'Groceries',
        );
        final xferWithFee = DoubleEntryEngine.buildTransfer(
          entryId: 'e-xfer',
          fromAssetAccountId: cbe.id,
          toAssetAccountId: telebirr.id,
          amountCents: 500000,
          transferFeeCents: 1000,
          feeExpenseAccountId: SystemControlAccounts.expense,
          date: '2026-11-06',
          description: 'CBE -> Telebirr',
        );
        // Tag fee posting with cat-fees
        final xferPostings = (xferWithFee['postings'] as List<PostingModel>)
            .map(
              (p) => p.accountId == SystemControlAccounts.expense
                  ? PostingModel(
                      id: p.id,
                      entryId: p.entryId,
                      accountId: p.accountId,
                      amountCents: p.amountCents,
                      direction: p.direction,
                      accountMovementDate: p.accountMovementDate,
                      categoryId: 'cat-fees',
                      note: p.note,
                    )
                  : p,
            )
            .toList();

        final voidedExp = DoubleEntryEngine.buildDirectExpense(
          entryId: 'e-voided',
          paidAccountId: cash.id,
          categoryId: 'cat-food',
          amountCents: 99900,
          date: '2026-11-07',
          description: 'Mistake entry',
        );
        final voidedEntry =
            (voidedExp['entry'] as JournalEntryModel).copyWith(isVoided: true);

        final entries = [
          open['entry'] as JournalEntryModel,
          inc['entry'] as JournalEntryModel,
          exp['entry'] as JournalEntryModel,
          xferWithFee['entry'] as JournalEntryModel,
          voidedEntry,
        ];
        final postings = [
          ...open['postings'] as List<PostingModel>,
          ...inc['postings'] as List<PostingModel>,
          ...exp['postings'] as List<PostingModel>,
          ...xferPostings,
          ...voidedExp['postings'] as List<PostingModel>,
        ];

        final cashflow = DoubleEntryEngine.calculatePeriodCashflowTotals(
          accounts: allAccounts,
          postings: postings,
          entries: entries,
          startDateIso: '2026-11-01',
          endDateIso: '2026-11-30',
        );
        expect(cashflow.incomeCents, 2500000);
        expect(cashflow.expenseCents, 46000); // 45,000 groceries + 1,000 fee
        expect(cashflow.netCashflowCents, 2454000);

        final categoryTotals =
            DoubleEntryEngine.calculateCategorySpendForPeriod(
          postings: postings,
          entries: entries,
          startDateIso: '2026-11-01',
          endDateIso: '2026-11-30',
          categories: categories,
          accounts: allAccounts,
          rollupToParents: true,
        );
        expect(categoryTotals['cat-groceries'], 45000);
        expect(categoryTotals['cat-food'], 45000); // Rolled up from Groceries!
        expect(categoryTotals['cat-fees'], 1000);
      },
    );
  });
}
