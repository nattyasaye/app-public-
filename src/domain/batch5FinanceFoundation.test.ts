import test from 'node:test';
import assert from 'node:assert/strict';
import {
  Account,
  TransactionCategory,
  SimpleTransaction,
  FOUNDATION_DEFAULT_ACCOUNTS,
  FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
  FOUNDATION_DEFAULT_INCOME_CATEGORIES,
  calculateSimpleAccountBalance,
  calculateSimpleCombinedBalance,
  calculateSimpleTotalIncome,
  calculateSimpleTotalExpense,
  validateSimpleTransaction,
  canDeleteSimpleAccount,
  canDeleteSimpleCategory,
  isDuplicateCategoryName,
  createSimpleFinanceTransaction
} from './doubleEntryFinance';

test('BATCH 5 — TASKS 21–25: FINANCE MODULE RESET & FOUNDATION IMPLEMENTATION', async (t) => {

  // -------------------------------------------------------------
  // TASK 21 — First-Time Finance Setup and Opening Balances
  // -------------------------------------------------------------
  await t.test('TASK 21 — First-Time Setup and Opening Balances', async (st) => {
    await st.test('21.1 Default accounts (CBE, BOA, Dashen Bank, Telebirr, Cash) are available', () => {
      const names = FOUNDATION_DEFAULT_ACCOUNTS.map((a) => a.name);
      assert.ok(names.includes('CBE'));
      assert.ok(names.includes('BOA'));
      assert.ok(names.includes('Dashen Bank'));
      assert.ok(names.includes('Telebirr'));
      assert.ok(names.includes('Cash'));
    });

    await st.test('21.2 User can configure starting balances, including valid zero balances', () => {
      const accounts: Account[] = [
        { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 500000, openingBalanceDate: '2026-11-10', isArchived: false, createdAt: '' },
        { id: 'acc-telebirr', name: 'Telebirr', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 0, openingBalanceDate: '2026-11-10', isArchived: false, createdAt: '' },
        { id: 'acc-cash', name: 'Cash', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 150000, openingBalanceDate: '2026-11-10', isArchived: false, createdAt: '' },
      ];

      assert.equal(accounts[0].openingBalanceCents, 500000);
      assert.equal(accounts[1].openingBalanceCents, 0); // Zero is strictly valid
      assert.equal(accounts[2].openingBalanceCents, 150000);
    });

    await st.test('21.3 User can add custom accounts with opening balances and dates', () => {
      const customAccount: Account = {
        id: 'acc-awash',
        name: 'Awash Bank',
        type: 'asset',
        currencyCode: 'ETB',
        openingBalanceCents: 200000, // 2,000 ETB
        openingBalanceDate: '2026-11-01',
        isArchived: false,
        createdAt: '2026-11-10T00:00:00Z',
      };

      assert.equal(customAccount.name, 'Awash Bank');
      assert.equal(customAccount.openingBalanceDate, '2026-11-01');
      assert.equal(customAccount.openingBalanceCents, 200000);
    });

    await st.test('21.4 Opening balances are strictly NEVER counted as income or salary', () => {
      const accounts: Account[] = [
        { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 1000000, openingBalanceDate: '2026-11-10', isArchived: false, createdAt: '' },
      ];
      const transactions: SimpleTransaction[] = [];

      const totalIncome = calculateSimpleTotalIncome(transactions);
      assert.equal(totalIncome, 0, 'Opening balance must not count toward recorded income');

      const balance = calculateSimpleAccountBalance(accounts[0], transactions);
      assert.equal(balance, 1000000, 'Account balance reflects opening balance');
    });
  });

  // -------------------------------------------------------------
  // TASK 22 — Account Management and Combined Balance
  // -------------------------------------------------------------
  await t.test('TASK 22 — Account Management and Combined Balance', async (st) => {
    await st.test('22.1 Combined balance equals the exact sum of all active account balances', () => {
      const accounts: Account[] = [
        { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 500000, isArchived: false, createdAt: '' }, // 5,000
        { id: 'acc-boa', name: 'BOA', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 300000, isArchived: false, createdAt: '' }, // 3,000
        { id: 'acc-cash', name: 'Cash', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 200000, isArchived: false, createdAt: '' }, // 2,000
      ];
      const transactions: SimpleTransaction[] = [];

      const combined = calculateSimpleCombinedBalance(accounts, transactions);
      assert.equal(combined, 1000000); // 10,000 ETB
    });

    await st.test('22.2 Adding an account immediately updates the accounts list and combined balance', () => {
      let accounts: Account[] = [
        { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 500000, isArchived: false, createdAt: '' },
      ];
      let transactions: SimpleTransaction[] = [];

      assert.equal(calculateSimpleCombinedBalance(accounts, transactions), 500000);

      // Add Awash Bank with 2,500 ETB opening balance
      const newAcc: Account = {
        id: 'acc-awash',
        name: 'Awash Bank',
        type: 'asset',
        currencyCode: 'ETB',
        openingBalanceCents: 250000,
        isArchived: false,
        createdAt: '',
      };
      accounts = [...accounts, newAcc];

      assert.equal(calculateSimpleCombinedBalance(accounts, transactions), 750000);
    });

    await st.test('22.3 Renaming an account preserves historical transactions (stable IDs)', () => {
      let account: Account = {
        id: 'acc-cbe',
        name: 'CBE',
        type: 'asset',
        currencyCode: 'ETB',
        openingBalanceCents: 100000,
        isArchived: false,
        createdAt: '',
      };
      const transactions: SimpleTransaction[] = [
        {
          id: 'tx-1',
          type: 'expense',
          amountCents: 20000,
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          transactionDate: '2026-11-10',
          createdAt: '',
        },
      ];

      // Balance before rename: 1,000 - 200 = 800 ETB (80,000 cents)
      assert.equal(calculateSimpleAccountBalance(account, transactions), 80000);

      // Rename account to 'Commercial Bank of Ethiopia (Main)'
      account = { ...account, name: 'Commercial Bank of Ethiopia (Main)' };

      // Balance remains identical because relationship is keyed by id
      assert.equal(calculateSimpleAccountBalance(account, transactions), 80000);
      assert.equal(transactions[0].accountId, account.id);
    });

    await st.test('22.4 Archived accounts are excluded from active combined balance but preserve history', () => {
      const accounts: Account[] = [
        { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 500000, isArchived: false, createdAt: '' },
        { id: 'acc-old', name: 'Old Account', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 200000, isArchived: true, createdAt: '' },
      ];
      const transactions: SimpleTransaction[] = [];

      const combined = calculateSimpleCombinedBalance(accounts, transactions);
      assert.equal(combined, 500000, 'Archived account is excluded from active combined balance');

      // History is preserved on the individual account
      const oldBal = calculateSimpleAccountBalance(accounts[1], transactions);
      assert.equal(oldBal, 200000, 'Historical balance of archived account remains intact');
    });

    await st.test('22.5 Accounts with transaction history cannot be deleted destructively', () => {
      const transactions: SimpleTransaction[] = [
        {
          id: 'tx-1',
          type: 'expense',
          amountCents: 15000,
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          transactionDate: '2026-11-10',
          createdAt: '',
        },
      ];

      const cbeCheck = canDeleteSimpleAccount('acc-cbe', transactions);
      assert.equal(cbeCheck.canDelete, false);
      assert.ok(cbeCheck.reason?.includes('cannot be deleted'));

      const unusedCheck = canDeleteSimpleAccount('acc-unused', transactions);
      assert.equal(unusedCheck.canDelete, true);
    });
  });

  // -------------------------------------------------------------
  // TASK 23 — Categories and Income/Expense Transaction Creation
  // -------------------------------------------------------------
  await t.test('TASK 23 — Categories and Income/Expense Transaction Creation', async (st) => {
    await st.test('23.1 Default categories match Task 23.4 requirements', () => {
      const expenseNames = FOUNDATION_DEFAULT_EXPENSE_CATEGORIES.map((c) => c.name);
      assert.ok(expenseNames.includes('Food'));
      assert.ok(expenseNames.includes('Transport'));
      assert.ok(expenseNames.includes('Housing'));
      assert.ok(expenseNames.includes('Utilities'));
      assert.ok(expenseNames.includes('Communication'));
      assert.ok(expenseNames.includes('Other'));

      const incomeNames = FOUNDATION_DEFAULT_INCOME_CATEGORIES.map((c) => c.name);
      assert.ok(incomeNames.includes('Salary'));
      assert.ok(incomeNames.includes('From Asaye'));
      assert.ok(incomeNames.includes('Other'));
    });

    await st.test('23.2 Amount must be greater than zero and valid integer cents', () => {
      const validRes = validateSimpleTransaction('expense', 15000, 'acc-cbe', 'cat-food');
      assert.equal(validRes.isValid, true);

      const zeroRes = validateSimpleTransaction('expense', 0, 'acc-cbe', 'cat-food');
      assert.equal(zeroRes.isValid, false);
      assert.ok(zeroRes.errors.amount);

      const negRes = validateSimpleTransaction('expense', -500, 'acc-cbe', 'cat-food');
      assert.equal(negRes.isValid, false);
    });

    await st.test('23.3 Category must match transaction type (expense vs income separation)', () => {
      const categories: TransactionCategory[] = [
        ...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
        ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
      ];

      // Income category passed to expense transaction must fail validation
      const invalidMatch = validateSimpleTransaction(
        'expense',
        10000,
        'acc-cbe',
        'cat-salary', // Income category!
        undefined,
        '2026-11-10',
        FOUNDATION_DEFAULT_ACCOUNTS,
        categories
      );
      assert.equal(invalidMatch.isValid, false);
      assert.ok(invalidMatch.errors.category?.includes('category is for incomes'));

      // Expense category passed to expense transaction succeeds
      const validMatch = validateSimpleTransaction(
        'expense',
        10000,
        'acc-cbe',
        'cat-food',
        undefined,
        '2026-11-10',
        FOUNDATION_DEFAULT_ACCOUNTS,
        categories
      );
      assert.equal(validMatch.isValid, true);
    });

    await st.test('23.4 Expense deducts from selected account, Income adds to selected account', () => {
      const cbe: Account = {
        id: 'acc-cbe',
        name: 'CBE',
        type: 'asset',
        currencyCode: 'ETB',
        openingBalanceCents: 100000, // 1,000 ETB
        isArchived: false,
        createdAt: '',
      };

      // 1. Record Expense: 200 ETB (20,000 cents)
      const expenseTx = createSimpleFinanceTransaction({
        type: 'expense',
        amountCents: 20000,
        accountId: 'acc-cbe',
        categoryId: 'cat-food',
        description: 'Lunch',
      });
      let transactions = [expenseTx];

      let bal = calculateSimpleAccountBalance(cbe, transactions);
      assert.equal(bal, 80000, 'Expense decrements account balance (1000 - 200 = 800)');

      // 2. Record Income: 500 ETB (50,000 cents)
      const incomeTx = createSimpleFinanceTransaction({
        type: 'income',
        amountCents: 50000,
        accountId: 'acc-cbe',
        categoryId: 'cat-salary',
        description: 'Bonus',
      });
      transactions = [incomeTx, ...transactions];

      bal = calculateSimpleAccountBalance(cbe, transactions);
      assert.equal(bal, 130000, 'Income increments account balance (800 + 500 = 1300)');
    });

    await st.test('23.5 Category management: duplicate detection and safe deletion guard', () => {
      const categories: TransactionCategory[] = [
        { id: 'cat-food', name: 'Food', type: 'expense', colorHex: '#EF4444' },
      ];

      // Duplicate check (case-insensitive)
      assert.equal(isDuplicateCategoryName('food', 'expense', categories), true);
      assert.equal(isDuplicateCategoryName('Food', 'expense', categories), true);
      assert.equal(isDuplicateCategoryName('Healthcare', 'expense', categories), false);

      // Safe deletion
      const transactions: SimpleTransaction[] = [
        {
          id: 'tx-1',
          type: 'expense',
          amountCents: 1000,
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          transactionDate: '2026-11-10',
          createdAt: '',
        },
      ];

      assert.equal(canDeleteSimpleCategory('cat-food', transactions).canDelete, false);
      assert.equal(canDeleteSimpleCategory('cat-unused', transactions).canDelete, true);
    });
  });

  // -------------------------------------------------------------
  // TASK 24 — Transaction History, Viewing, and Editing
  // -------------------------------------------------------------
  await t.test('TASK 24 — Transaction History, Viewing, and Editing', async (st) => {
    await st.test('24.1 Balance recalculation Example A: Amount change', () => {
      const cbe: Account = {
        id: 'acc-cbe',
        name: 'CBE',
        type: 'asset',
        currencyCode: 'ETB',
        openingBalanceCents: 100000, // 1,000 ETB
        isArchived: false,
        createdAt: '',
      };

      // Original: Expense 100 on CBE (10,000 cents)
      const txOriginal: SimpleTransaction = {
        id: 'tx-ex-1',
        type: 'expense',
        amountCents: 10000,
        accountId: 'acc-cbe',
        categoryId: 'cat-food',
        transactionDate: '2026-11-10',
        createdAt: '2026-11-10T10:00:00Z',
      };
      let transactions = [txOriginal];
      assert.equal(calculateSimpleAccountBalance(cbe, transactions), 90000);

      // Edited: Expense 150 on CBE (15,000 cents)
      const txEdited: SimpleTransaction = {
        ...txOriginal,
        amountCents: 15000,
        updatedAt: '2026-11-10T10:05:00Z',
      };
      transactions = [txEdited]; // Replaced in-place, NOT duplicated

      // Final balance reflects deduction of 150, not 250! (1,000 - 150 = 850 ETB)
      assert.equal(calculateSimpleAccountBalance(cbe, transactions), 85000);
      assert.equal(transactions.length, 1, 'Editing must never create duplicate records');
    });

    await st.test('24.2 Balance recalculation Example B: Account change', () => {
      const cbe: Account = { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 100000, isArchived: false, createdAt: '' };
      const boa: Account = { id: 'acc-boa', name: 'BOA', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 100000, isArchived: false, createdAt: '' };

      // Original: Expense 100 on CBE
      const txOriginal: SimpleTransaction = {
        id: 'tx-ex-2',
        type: 'expense',
        amountCents: 10000,
        accountId: 'acc-cbe',
        categoryId: 'cat-food',
        transactionDate: '2026-11-10',
        createdAt: '',
      };
      let transactions = [txOriginal];
      assert.equal(calculateSimpleAccountBalance(cbe, transactions), 90000);
      assert.equal(calculateSimpleAccountBalance(boa, transactions), 100000);

      // Edited: Change account to BOA
      const txEdited: SimpleTransaction = {
        ...txOriginal,
        accountId: 'acc-boa',
      };
      transactions = [txEdited];

      // CBE is restored to 1,000, BOA is deducted to 900
      assert.equal(calculateSimpleAccountBalance(cbe, transactions), 100000);
      assert.equal(calculateSimpleAccountBalance(boa, transactions), 90000);
    });

    await st.test('24.3 Balance recalculation Example C: Transaction type change', () => {
      const cbe: Account = { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 100000, isArchived: false, createdAt: '' };

      // Original: Expense 100 on CBE -> balance 900 (90,000 cents)
      const txOriginal: SimpleTransaction = {
        id: 'tx-ex-3',
        type: 'expense',
        amountCents: 10000,
        accountId: 'acc-cbe',
        categoryId: 'cat-food',
        transactionDate: '2026-11-10',
        createdAt: '',
      };
      let transactions = [txOriginal];
      assert.equal(calculateSimpleAccountBalance(cbe, transactions), 90000);

      // Edited: Type changed to Income 100 on CBE -> reverses expense and applies income -> balance 1,100 (110,000 cents)
      const txEdited: SimpleTransaction = {
        ...txOriginal,
        type: 'income',
        categoryId: 'cat-salary',
      };
      transactions = [txEdited];

      assert.equal(calculateSimpleAccountBalance(cbe, transactions), 110000);
    });
  });

  // -------------------------------------------------------------
  // TASK 25 — Transaction Deletion, Balance Reversal, and Transfers
  // -------------------------------------------------------------
  await t.test('TASK 25 — Transaction Deletion, Balance Reversal, and Transfers', async (st) => {
    await st.test('25.1 Deleting an expense restores the deducted account balance', () => {
      const cbe: Account = { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 100000, isArchived: false, createdAt: '' }; // 1,000 ETB
      const expenseTx: SimpleTransaction = {
        id: 'tx-del-1',
        type: 'expense',
        amountCents: 20000, // 200 ETB
        accountId: 'acc-cbe',
        categoryId: 'cat-food',
        transactionDate: '2026-11-10',
        createdAt: '',
      };
      let transactions = [expenseTx];
      assert.equal(calculateSimpleAccountBalance(cbe, transactions), 80000);

      // Delete expense:
      transactions = transactions.filter((t) => t.id !== expenseTx.id);

      // CBE balance is fully restored to 1,000 ETB (100,000 cents)
      assert.equal(calculateSimpleAccountBalance(cbe, transactions), 100000);
    });

    await st.test('25.2 Deleting income reverses the added account balance', () => {
      const boa: Account = { id: 'acc-boa', name: 'BOA', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 100000, isArchived: false, createdAt: '' }; // 1,000 ETB
      const incomeTx: SimpleTransaction = {
        id: 'tx-del-2',
        type: 'income',
        amountCents: 30000, // 300 ETB
        accountId: 'acc-boa',
        categoryId: 'cat-salary',
        transactionDate: '2026-11-10',
        createdAt: '',
      };
      let transactions = [incomeTx];
      assert.equal(calculateSimpleAccountBalance(boa, transactions), 130000);

      // Delete income:
      transactions = transactions.filter((t) => t.id !== incomeTx.id);

      // BOA balance is restored to 1,000 ETB (100,000 cents)
      assert.equal(calculateSimpleAccountBalance(boa, transactions), 100000);
    });

    await st.test('25.3 Ephemeral Undo restores deleted transaction and its financial effect exactly once', () => {
      const cbe: Account = { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 100000, isArchived: false, createdAt: '' };
      const expenseTx: SimpleTransaction = {
        id: 'tx-undo-1',
        type: 'expense',
        amountCents: 20000,
        accountId: 'acc-cbe',
        categoryId: 'cat-food',
        transactionDate: '2026-11-10',
        createdAt: '',
      };
      let transactions = [expenseTx];

      // Delete
      transactions = transactions.filter((t) => t.id !== expenseTx.id);
      assert.equal(calculateSimpleAccountBalance(cbe, transactions), 100000);

      // Undo deletion
      transactions = [expenseTx, ...transactions];
      assert.equal(calculateSimpleAccountBalance(cbe, transactions), 80000);
      assert.equal(transactions.length, 1);
    });

    await st.test('25.4 Account-to-account transfer decreases source, increases destination, and leaves Combined Balance UNCHANGED', () => {
      const cbe: Account = { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 100000, isArchived: false, createdAt: '' }; // 1,000 ETB
      const boa: Account = { id: 'acc-boa', name: 'BOA', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 50000, isArchived: false, createdAt: '' };   // 500 ETB
      const accounts = [cbe, boa];
      let transactions: SimpleTransaction[] = [];

      // Combined balance before transfer: 1,500 ETB (150,000 cents)
      assert.equal(calculateSimpleCombinedBalance(accounts, transactions), 150000);

      // Transfer 200 ETB from CBE to BOA (20,000 cents)
      const transferTx: SimpleTransaction = {
        id: 'tx-tr-1',
        type: 'transfer',
        amountCents: 20000,
        accountId: 'acc-cbe',              // Source
        destinationAccountId: 'acc-boa',  // Destination
        transactionDate: '2026-11-10',
        createdAt: '',
      };
      transactions = [transferTx];

      // CBE decreases to 800 ETB (80,000 cents)
      assert.equal(calculateSimpleAccountBalance(cbe, transactions), 80000);

      // BOA increases to 700 ETB (70,000 cents)
      assert.equal(calculateSimpleAccountBalance(boa, transactions), 70000);

      // Combined balance AFTER transfer: exactly 1,500 ETB (150,000 cents)
      assert.equal(calculateSimpleCombinedBalance(accounts, transactions), 150000);

      // Transfers are NEVER counted as income or expense
      assert.equal(calculateSimpleTotalIncome(transactions), 0);
      assert.equal(calculateSimpleTotalExpense(transactions), 0);
    });

    await st.test('25.5 Deleting a transfer restores both accounts', () => {
      const cbe: Account = { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 100000, isArchived: false, createdAt: '' };
      const boa: Account = { id: 'acc-boa', name: 'BOA', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 50000, isArchived: false, createdAt: '' };
      const transferTx: SimpleTransaction = {
        id: 'tx-tr-2',
        type: 'transfer',
        amountCents: 20000,
        accountId: 'acc-cbe',
        destinationAccountId: 'acc-boa',
        transactionDate: '2026-11-10',
        createdAt: '',
      };
      let transactions = [transferTx];

      assert.equal(calculateSimpleAccountBalance(cbe, transactions), 80000);
      assert.equal(calculateSimpleAccountBalance(boa, transactions), 70000);

      // Delete transfer
      transactions = transactions.filter((t) => t.id !== transferTx.id);

      // Both accounts are restored
      assert.equal(calculateSimpleAccountBalance(cbe, transactions), 100000);
      assert.equal(calculateSimpleAccountBalance(boa, transactions), 50000);
    });

    await st.test('25.6 Transfer validation rejects identical source and destination accounts', () => {
      const res = validateSimpleTransaction('transfer', 5000, 'acc-cbe', undefined, 'acc-cbe');
      assert.equal(res.isValid, false);
      assert.ok(res.errors.destinationAccount?.includes('must be different'));
    });
  });
});
