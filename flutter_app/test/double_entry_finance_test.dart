import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/domain/finance/double_entry_engine.dart';

void main() {
  group('Double-Entry Finance Engine - 17 Critical Scenarios', () {
    late AccountModel cbeAccount;
    late AccountModel cashWallet;
    late AccountModel telebirrAccount;
    late AccountModel receivableAccount;
    late AccountModel payableAccount;
    late AccountModel foodExpenseAccount;
    late AccountModel salaryIncomeAccount;
    late AccountModel interestIncomeAccount;
    late PartyModel abebeParty;
    late PartyModel landlordParty;

    setUp(() {
      cbeAccount = AccountModel(
          id: 'acc-cbe', name: 'CBE Bank Account', type: AccountType.asset);
      cashWallet = AccountModel(
          id: 'acc-cash', name: 'Cash Wallet', type: AccountType.asset);
      telebirrAccount = AccountModel(
          id: 'acc-telebirr', name: 'Telebirr', type: AccountType.asset);
      receivableAccount = AccountModel(
          id: 'acc-rec', name: 'Accounts Receivable', type: AccountType.asset);
      payableAccount = AccountModel(
          id: 'acc-pay', name: 'Accounts Payable', type: AccountType.liability);
      foodExpenseAccount = AccountModel(
          id: 'acc-exp-food',
          name: 'Expense: Dining & Food',
          type: AccountType.expense);
      salaryIncomeAccount = AccountModel(
          id: 'acc-inc-salary',
          name: 'Income: Salary',
          type: AccountType.income);
      interestIncomeAccount = AccountModel(
          id: 'acc-inc-interest',
          name: 'Income: Interest',
          type: AccountType.income);

      abebeParty = PartyModel(
          id: 'party-abebe', name: 'Abebe Kebede', phone: '+251911223344');
      landlordParty =
          PartyModel(id: 'party-landlord', name: 'Landlord Ato Tadesse');
    });

    test('Scenario 1 & 2: Boundary Test (Jan 30 Expense, Feb 2 Repayment)', () {
      final postings = <PostingModel>[];

      // Day 1 (Jan 30): Colleague Abebe pays 1,000 ETB (100,000 cents) for my dinner
      final day1 = DoubleEntryEngine.buildThirdPartyPaidExpense(
        entryId: 'entry-jan-30',
        debtId: 'debt-abebe-1',
        partyId: abebeParty.id,
        expenseAccountId: foodExpenseAccount.id,
        payableAccountId: payableAccount.id,
        amountCents: 100000,
        occurrenceDate: '2026-01-30',
        description: 'Dinner paid by Abebe',
      );
      postings.addAll(day1['postings'] as List<PostingModel>);
      final debt = day1['debt'] as DebtModel;

      // Verify Jan 30: Expense is recorded, but CBE Bank balance is UNCHANGED (0)
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: cbeAccount, postings: postings),
          equals(0));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: foodExpenseAccount, postings: postings),
          equals(100000));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: payableAccount, postings: postings),
          equals(100000));

      // Day 5 (Feb 2): Repay Abebe 1,000 ETB from CBE Bank
      final day5 = DoubleEntryEngine.buildDebtSettlement(
        settlementEntryId: 'entry-feb-02',
        debt: debt,
        settlementAssetAccountId: cbeAccount.id,
        debtAccountId: payableAccount.id,
        allocatedPrincipalCents: 100000,
        settlementDate: '2026-02-02',
        description: 'Repaid Abebe for dinner',
      );
      postings.addAll(day5['postings'] as List<PostingModel>);
      final updatedDebt = day5['updatedDebt'] as DebtModel;

      // Verify Feb 2: Debt is settled, Bank decreased, Expense did NOT increase again in Feb
      expect(updatedDebt.status, equals(DebtStatus.settled));
      expect(updatedDebt.outstandingCents, equals(0));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: payableAccount, postings: postings),
          equals(0));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: cbeAccount, postings: postings),
          equals(-100000));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: foodExpenseAccount, postings: postings),
          equals(100000));
    });

    test('Scenario 3: Direct Income and Direct Expense Recording', () {
      final postings = <PostingModel>[];

      // Income: 50,000 ETB salary into CBE
      postings.addAll([
        PostingModel(
            id: 'p1',
            entryId: 'e1',
            accountId: cbeAccount.id,
            amountCents: 5000000,
            direction: PostingDirection.debit,
            accountMovementDate: '2026-03-01'),
        PostingModel(
            id: 'p2',
            entryId: 'e1',
            accountId: salaryIncomeAccount.id,
            amountCents: 5000000,
            direction: PostingDirection.credit,
            accountMovementDate: '2026-03-01'),
      ]);
      DoubleEntryEngine.validateBalancedEntry(postings);

      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: cbeAccount, postings: postings),
          equals(5000000));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: salaryIncomeAccount, postings: postings),
          equals(5000000));

      // Expense: 2,500 ETB groceries from CBE
      final expPostings = [
        PostingModel(
            id: 'p3',
            entryId: 'e2',
            accountId: foodExpenseAccount.id,
            amountCents: 250000,
            direction: PostingDirection.debit,
            accountMovementDate: '2026-03-02'),
        PostingModel(
            id: 'p4',
            entryId: 'e2',
            accountId: cbeAccount.id,
            amountCents: 250000,
            direction: PostingDirection.credit,
            accountMovementDate: '2026-03-02'),
      ];
      DoubleEntryEngine.validateBalancedEntry(expPostings);
      postings.addAll(expPostings);

      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: cbeAccount, postings: postings),
          equals(4750000));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: foodExpenseAccount, postings: postings),
          equals(250000));
    });

    test('Scenario 4: Account Transfer creates Zero Income and Zero Expense',
        () {
      final transferPostings = [
        PostingModel(
            id: 't1',
            entryId: 'te1',
            accountId: telebirrAccount.id,
            amountCents: 500000,
            direction: PostingDirection.debit,
            accountMovementDate: '2026-03-05'),
        PostingModel(
            id: 't2',
            entryId: 'te1',
            accountId: cbeAccount.id,
            amountCents: 500000,
            direction: PostingDirection.credit,
            accountMovementDate: '2026-03-05'),
      ];
      DoubleEntryEngine.validateBalancedEntry(transferPostings);

      // Verify neither salary income nor food expense were touched
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: telebirrAccount, postings: transferPostings),
          equals(500000));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: cbeAccount, postings: transferPostings),
          equals(-500000));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: salaryIncomeAccount, postings: transferPostings),
          equals(0));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: foodExpenseAccount, postings: transferPostings),
          equals(0));
    });

    test('Scenario 5 & 6: Lending Money and Collecting Repayment', () {
      final postings = <PostingModel>[];

      // Day 1: Lend 1,000 ETB cash to Abebe
      final lendResult = DoubleEntryEngine.buildLendMoney(
        entryId: 'e-lend-1',
        debtId: 'debt-lend-1',
        partyId: abebeParty.id,
        receivableAccountId: receivableAccount.id,
        sourceAssetAccountId: cashWallet.id,
        amountCents: 100000,
        date: '2026-03-10',
        description: 'Lent cash to Abebe',
      );
      postings.addAll(lendResult['postings'] as List<PostingModel>);
      final debt = lendResult['debt'] as DebtModel;

      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: cashWallet, postings: postings),
          equals(-100000));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: receivableAccount, postings: postings),
          equals(100000));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: foodExpenseAccount, postings: postings),
          equals(0));

      // Day 10: Abebe repays 1,000 ETB in cash
      final settleResult = DoubleEntryEngine.buildDebtSettlement(
        settlementEntryId: 'e-repay-1',
        debt: debt,
        settlementAssetAccountId: cashWallet.id,
        debtAccountId: receivableAccount.id,
        allocatedPrincipalCents: 100000,
        settlementDate: '2026-03-20',
        description: 'Abebe repaid cash',
      );
      postings.addAll(settleResult['postings'] as List<PostingModel>);
      final updatedDebt = settleResult['updatedDebt'] as DebtModel;

      expect(updatedDebt.status, equals(DebtStatus.settled));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: cashWallet, postings: postings),
          equals(0));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: receivableAccount, postings: postings),
          equals(0));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: salaryIncomeAccount, postings: postings),
          equals(0));
    });

    test('Scenario 7 & 8: Borrowing Money and Repaying Loan', () {
      final postings = <PostingModel>[];

      // Day 1: Borrow 2,000 ETB from Landlord into Telebirr
      final borrowResult = DoubleEntryEngine.buildBorrowMoney(
        entryId: 'e-borrow-1',
        debtId: 'debt-borrow-1',
        partyId: landlordParty.id,
        destAssetAccountId: telebirrAccount.id,
        payableAccountId: payableAccount.id,
        amountCents: 200000,
        date: '2026-03-01',
        description: 'Borrowed from landlord',
      );
      postings.addAll(borrowResult['postings'] as List<PostingModel>);
      final debt = borrowResult['debt'] as DebtModel;

      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: telebirrAccount, postings: postings),
          equals(200000));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: payableAccount, postings: postings),
          equals(200000));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: salaryIncomeAccount, postings: postings),
          equals(0));

      // Partial Repayment: Repay 500 ETB
      final partRepay = DoubleEntryEngine.buildDebtSettlement(
        settlementEntryId: 'e-repay-part',
        debt: debt,
        settlementAssetAccountId: telebirrAccount.id,
        debtAccountId: payableAccount.id,
        allocatedPrincipalCents: 50000,
        settlementDate: '2026-03-05',
        description: 'Partial repayment to landlord',
      );
      postings.addAll(partRepay['postings'] as List<PostingModel>);
      final midDebt = partRepay['updatedDebt'] as DebtModel;

      expect(midDebt.status, equals(DebtStatus.active));
      expect(midDebt.outstandingCents, equals(150000));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: payableAccount, postings: postings),
          equals(150000));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: telebirrAccount, postings: postings),
          equals(150000));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: foodExpenseAccount, postings: postings),
          equals(0));
    });

    test(
        'Scenario 10: Split Expense (Dinner 1,000 ETB, My share 400 ETB, Colleague owes 600 ETB)',
        () {
      final splitResult = DoubleEntryEngine.buildSplitExpense(
        entryId: 'e-split-1',
        debtId: 'debt-split-1',
        partyId: abebeParty.id,
        myExpenseAccountId: foodExpenseAccount.id,
        receivableAccountId: receivableAccount.id,
        paidAssetAccountId: cbeAccount.id,
        myShareCents: 40000,
        theirShareCents: 60000,
        occurrenceDate: '2026-03-12',
        description: 'Dinner bill split with Abebe',
      );

      final postings = splitResult['postings'] as List<PostingModel>;
      final debt = splitResult['debt'] as DebtModel;

      expect(debt.outstandingCents, equals(60000));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: cbeAccount, postings: postings),
          equals(-100000));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: foodExpenseAccount, postings: postings),
          equals(40000));
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: receivableAccount, postings: postings),
          equals(60000));
    });

    test('Scenario 12: Interest separated from Principal', () {
      final debt = DebtModel(
        id: 'debt-with-interest',
        originEntryId: 'e-init',
        partyId: abebeParty.id,
        debtType: DebtType.receivable,
        principalCents: 100000, // 1,000 ETB
        outstandingCents: 100000,
      );

      // Repaid 1,000 ETB principal + 50 ETB interest (5,000 cents)
      final settleResult = DoubleEntryEngine.buildDebtSettlement(
        settlementEntryId: 'e-settle-interest',
        debt: debt,
        settlementAssetAccountId: cashWallet.id,
        debtAccountId: receivableAccount.id,
        allocatedPrincipalCents: 100000,
        interestCents: 5000,
        interestAccountId: interestIncomeAccount.id,
        settlementDate: '2026-03-15',
        description: 'Principal + Interest collected',
      );

      final postings = settleResult['postings'] as List<PostingModel>;
      // Cash increases by 1,050 ETB
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: cashWallet, postings: postings),
          equals(105000));
      // Receivable decreases by 1,000 ETB
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: receivableAccount, postings: postings),
          equals(-100000));
      // Interest income is 50 ETB
      expect(
          DoubleEntryEngine.calculateAccountBalance(
              account: interestIncomeAccount, postings: postings),
          equals(5000));
    });

    test('Scenario 13: Invariant Rejection on Unbalanced Entries', () {
      final unbalancedPostings = [
        PostingModel(
            id: 'u1',
            entryId: 'eu',
            accountId: cbeAccount.id,
            amountCents: 1000,
            direction: PostingDirection.debit,
            accountMovementDate: '2026-03-01'),
        PostingModel(
            id: 'u2',
            entryId: 'eu',
            accountId: foodExpenseAccount.id,
            amountCents: 900,
            direction: PostingDirection.credit,
            accountMovementDate: '2026-03-01'),
      ];

      expect(() => DoubleEntryEngine.validateBalancedEntry(unbalancedPostings),
          throwsStateError);
    });

    test(
        'Scenario 14 & 15: Net Financial Position & Available to Spend Formula',
        () {
      final accounts = [
        cbeAccount,
        telebirrAccount,
        receivableAccount,
        payableAccount
      ];
      final postings = [
        // Cash: 10,000 ETB
        PostingModel(
            id: 'p1',
            entryId: 'e1',
            accountId: cbeAccount.id,
            amountCents: 1000000,
            direction: PostingDirection.debit,
            accountMovementDate: '2026-03-01'),
        // Receivable: 3,000 ETB
        PostingModel(
            id: 'p2',
            entryId: 'e1',
            accountId: receivableAccount.id,
            amountCents: 300000,
            direction: PostingDirection.debit,
            accountMovementDate: '2026-03-01'),
        // Payable: 2,000 ETB
        PostingModel(
            id: 'p3',
            entryId: 'e1',
            accountId: payableAccount.id,
            amountCents: 200000,
            direction: PostingDirection.credit,
            accountMovementDate: '2026-03-01'),
        // Balancing equity
        PostingModel(
            id: 'p4',
            entryId: 'e1',
            accountId: cbeAccount.id,
            amountCents: 1100000,
            direction: PostingDirection.credit,
            accountMovementDate: '2026-03-01'),
      ];

      final liquidCash = DoubleEntryEngine.calculateLiquidCash(
          accounts: accounts, postings: postings);
      expect(liquidCash, equals(-100000)); // (10,000 - 11,000)

      // Test Available to Spend:
      // Receivables are STRICTLY EXCLUDED.
      final avail = DoubleEntryEngine.calculateAvailableToSpend(
        liquidCashCents: 5000000, // 50,000 ETB liquid
        unpaidPayablesDueInPeriodCents: 1500000, // 15,000 ETB payables due
        reservedSavingsCents: 1000000, // 10,000 ETB emergency fund
      );
      expect(avail, equals(2500000)); // 25,000 ETB available
    });

    test('Scenario 18: Transfer with Bank Service Fee', () {
      final feeExpenseAccount = AccountModel(
          id: 'acc-exp-fees',
          name: 'Expense: Bank Fees',
          type: AccountType.expense);
      // Transfer 5,000 ETB from CBE to Telebirr with a 10 ETB transfer fee
      final transferResult = DoubleEntryEngine.buildTransfer(
        entryId: 'entry-xfer-fee',
        fromAssetAccountId: cbeAccount.id,
        toAssetAccountId: telebirrAccount.id,
        amountCents: 500000, // 5,000 ETB
        transferFeeCents: 1000, // 10 ETB
        feeExpenseAccountId: feeExpenseAccount.id,
        date: '2026-11-09',
        description: 'Transfer CBE to Telebirr',
      );

      final transferPostings = transferResult['postings'] as List<PostingModel>;
      // Verify balanced
      DoubleEntryEngine.validateBalancedEntry(transferPostings);

      // Verify balances
      final telebirrBal = DoubleEntryEngine.calculateAccountBalance(
          account: telebirrAccount, postings: transferPostings);
      final cbeBal = DoubleEntryEngine.calculateAccountBalance(
          account: cbeAccount, postings: transferPostings);
      final feeBal = DoubleEntryEngine.calculateAccountBalance(
          account: feeExpenseAccount, postings: transferPostings);

      expect(telebirrBal, equals(500000)); // +5,000 ETB
      expect(cbeBal, equals(-501000)); // -5,010 ETB (principal + fee)
      expect(feeBal, equals(1000)); // +10 ETB expense
    });

    test(
        'Scenario 19: Voided Transaction Strictly Excluded from Account Balances and Net Position',
        () {
      final entry1 = JournalEntryModel(
        id: 'e-valid',
        entryType: EntryType.standard,
        description: 'Valid Income',
        occurrenceDate: '2026-11-01',
      );
      final entry2 = JournalEntryModel(
        id: 'e-voided',
        entryType: EntryType.standard,
        description: 'Accidental Duplicate',
        occurrenceDate: '2026-11-02',
        isVoided: true,
        voidReason: 'User mistake duplicate entry',
      );

      final testPostings = [
        PostingModel(
            id: 'p1-dr',
            entryId: entry1.id,
            accountId: cbeAccount.id,
            amountCents: 100000,
            direction: PostingDirection.debit,
            accountMovementDate: '2026-11-01'),
        PostingModel(
            id: 'p1-cr',
            entryId: entry1.id,
            accountId: salaryIncomeAccount.id,
            amountCents: 100000,
            direction: PostingDirection.credit,
            accountMovementDate: '2026-11-01'),
        PostingModel(
            id: 'p2-dr',
            entryId: entry2.id,
            accountId: cbeAccount.id,
            amountCents: 900000,
            direction: PostingDirection.debit,
            accountMovementDate: '2026-11-02'),
        PostingModel(
            id: 'p2-cr',
            entryId: entry2.id,
            accountId: salaryIncomeAccount.id,
            amountCents: 900000,
            direction: PostingDirection.credit,
            accountMovementDate: '2026-11-02'),
      ];

      // Reconstructed CBE balance ignoring voided entries must be 1,000 ETB, NOT 10,000 ETB
      final balanceWithoutVoid = DoubleEntryEngine.calculateAccountBalance(
        account: cbeAccount,
        postings: testPostings,
        entries: [entry1, entry2],
      );
      expect(balanceWithoutVoid, equals(100000));

      final liquidCash = DoubleEntryEngine.calculateLiquidCash(
        accounts: [cbeAccount],
        postings: testPostings,
        entries: [entry1, entry2],
      );
      expect(liquidCash, equals(100000));
    });

    test('AccountModel and PartyModel copyWith produces clean immutable copies',
        () {
      final archivedAcc = cbeAccount.copyWith(isArchived: true);
      expect(archivedAcc.id, equals(cbeAccount.id));
      expect(archivedAcc.name, equals(cbeAccount.name));
      expect(archivedAcc.isArchived, isTrue);
      expect(cbeAccount.isArchived, isFalse);

      final updatedParty = abebeParty.copyWith(phone: '+251999887766');
      expect(updatedParty.id, equals(abebeParty.id));
      expect(updatedParty.name, equals(abebeParty.name));
      expect(updatedParty.phone, equals('+251999887766'));
    });
  });
}
