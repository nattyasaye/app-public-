import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  Account,
  TransactionCategory,
  SimpleTransaction,
  calculateSimpleAccountBalance,
  calculateSimpleCombinedBalance,
  createSimpleFinanceTransaction,
  getAccountMovements,
  verifyAccountBalanceConsistency,
  sortTransactionsDescending,
  groupTransactionsByDate,
  correctAccountOpeningBalance,
  searchAndFilterTransactions,
  verifyFinancialDataIntegrity,
  FOUNDATION_DEFAULT_ACCOUNTS,
  FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
  FOUNDATION_DEFAULT_INCOME_CATEGORIES,
} from './doubleEntryFinance';

describe('BATCH 6 — TASKS 26–30: FINANCE ACCOUNT HISTORY, ORGANIZATION, CORRECTIONS, SEARCH & INTEGRITY', () => {
  const baseAccounts: Account[] = [
    {
      id: 'acc-cbe',
      name: 'CBE',
      type: 'asset',
      currencyCode: 'ETB',
      openingBalanceCents: 1000000, // 10,000 ETB
      openingBalanceDate: '2026-11-01',
      isArchived: false,
      createdAt: '2026-11-01T00:00:00Z',
    },
    {
      id: 'acc-boa',
      name: 'BOA',
      type: 'asset',
      currencyCode: 'ETB',
      openingBalanceCents: 500000, // 5,000 ETB
      openingBalanceDate: '2026-11-01',
      isArchived: false,
      createdAt: '2026-11-01T00:00:00Z',
    },
    {
      id: 'acc-telebirr',
      name: 'Telebirr',
      type: 'asset',
      currencyCode: 'ETB',
      openingBalanceCents: 200000, // 2,000 ETB
      openingBalanceDate: '2026-11-01',
      isArchived: false,
      createdAt: '2026-11-01T00:00:00Z',
    },
  ];

  const categories: TransactionCategory[] = [
    ...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
    ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
  ];

  // -------------------------------------------------------------
  // TASK 26: Account Details & Account Transaction History
  // -------------------------------------------------------------
  describe('Task 26 — Account Details & Account-Specific History', () => {
    it('26.1 & 26.2: getAccountMovements isolates transactions for a specific account', () => {
      const txs: SimpleTransaction[] = [
        createSimpleFinanceTransaction({
          type: 'income',
          amountCents: 50000, // 500 ETB into CBE
          accountId: 'acc-cbe',
          categoryId: 'cat-salary',
          description: 'Consulting gig',
          transactionDate: '2026-11-05',
        }),
        createSimpleFinanceTransaction({
          type: 'expense',
          amountCents: 20000, // 200 ETB from CBE
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          description: 'Dinner with client',
          transactionDate: '2026-11-06',
        }),
        createSimpleFinanceTransaction({
          type: 'expense',
          amountCents: 15000, // 150 ETB from BOA (unrelated to CBE)
          accountId: 'acc-boa',
          categoryId: 'cat-transport',
          description: 'Fuel',
          transactionDate: '2026-11-07',
        }),
      ];

      const cbeMovements = getAccountMovements(baseAccounts[0], txs, baseAccounts, categories);
      assert.equal(cbeMovements.length, 2, 'CBE must only show the 2 transactions affecting CBE');
    });

    it('26.3: Clearly distinguishes income (+), expense (-), transfer in (+), and transfer out (-)', () => {
      const txs: SimpleTransaction[] = [
        createSimpleFinanceTransaction({
          type: 'income',
          amountCents: 50000, // 500 ETB into CBE
          accountId: 'acc-cbe',
          categoryId: 'cat-salary',
          transactionDate: '2026-11-05',
        }),
        createSimpleFinanceTransaction({
          type: 'expense',
          amountCents: 20000, // 200 ETB from CBE
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          transactionDate: '2026-11-06',
        }),
        createSimpleFinanceTransaction({
          type: 'transfer',
          amountCents: 100000, // 1,000 ETB from BOA to CBE
          accountId: 'acc-boa',
          destinationAccountId: 'acc-cbe',
          description: 'Top up CBE from BOA',
          transactionDate: '2026-11-08',
        }),
        createSimpleFinanceTransaction({
          type: 'transfer',
          amountCents: 30000, // 300 ETB from CBE to Telebirr
          accountId: 'acc-cbe',
          destinationAccountId: 'acc-telebirr',
          description: 'Telebirr topup',
          transactionDate: '2026-11-09',
        }),
      ];

      const cbeMovements = getAccountMovements(baseAccounts[0], txs, baseAccounts, categories);
      assert.equal(cbeMovements.length, 4);

      // Verify transfer in from BOA
      const transferIn = cbeMovements.find((m) => m.displayType === 'transfer_in');
      assert.ok(transferIn, 'Must identify incoming transfer');
      assert.equal(transferIn.direction, 'inflow');
      assert.equal(transferIn.signedAmountCents, 100000);
      assert.equal(transferIn.counterpartAccountName, 'BOA');
      assert.notEqual(transferIn.displayType, 'income', 'Transfer must NOT be classified as income');

      // Verify transfer out to Telebirr
      const transferOut = cbeMovements.find((m) => m.displayType === 'transfer_out');
      assert.ok(transferOut, 'Must identify outgoing transfer');
      assert.equal(transferOut.direction, 'outflow');
      assert.equal(transferOut.signedAmountCents, -30000);
      assert.equal(transferOut.counterpartAccountName, 'Telebirr');
      assert.notEqual(transferOut.displayType, 'expense', 'Transfer must NOT be classified as expense');

      // Verify income
      const inc = cbeMovements.find((m) => m.displayType === 'income');
      assert.ok(inc);
      assert.equal(inc.direction, 'inflow');
      assert.equal(inc.signedAmountCents, 50000);

      // Verify expense
      const exp = cbeMovements.find((m) => m.displayType === 'expense');
      assert.ok(exp);
      assert.equal(exp.direction, 'outflow');
      assert.equal(exp.signedAmountCents, -20000);
    });

    it('26.4: Balance consistency: Account Balance = Opening Balance + All Inflows - All Outflows', () => {
      const cbe = baseAccounts[0]; // opening 10,000 ETB (1,000,000 cents)
      const txs: SimpleTransaction[] = [
        createSimpleFinanceTransaction({
          type: 'income',
          amountCents: 50000, // +500
          accountId: cbe.id,
          categoryId: 'cat-salary',
        }),
        createSimpleFinanceTransaction({
          type: 'expense',
          amountCents: 20000, // -200
          accountId: cbe.id,
          categoryId: 'cat-food',
        }),
        createSimpleFinanceTransaction({
          type: 'transfer',
          amountCents: 100000, // +1,000 into CBE
          accountId: 'acc-boa',
          destinationAccountId: cbe.id,
        }),
        createSimpleFinanceTransaction({
          type: 'transfer',
          amountCents: 30000, // -300 out of CBE
          accountId: cbe.id,
          destinationAccountId: 'acc-telebirr',
        }),
      ];

      const breakdown = verifyAccountBalanceConsistency(cbe, txs);
      assert.equal(breakdown.isConsistent, true);
      assert.equal(breakdown.openingBalanceCents, 1000000);
      assert.equal(breakdown.totalInflowsCents, 150000); // 50,000 + 100,000
      assert.equal(breakdown.totalOutflowsCents, 50000); // 20,000 + 30,000
      // Expected = 1,000,000 + 150,000 - 50,000 = 1,100,000 cents (11,000 ETB)
      assert.equal(breakdown.calculatedBalanceCents, 1100000);
      assert.equal(calculateSimpleAccountBalance(cbe, txs), 1100000);
    });
  });

  // -------------------------------------------------------------
  // TASK 27: Transaction Organization & Navigation
  // -------------------------------------------------------------
  describe('Task 27 — Transaction History Organization & Grouping', () => {
    it('27.1: Sorts transactions in strict reverse-chronological order', () => {
      const tx1 = { ...createSimpleFinanceTransaction({ type: 'income', amountCents: 100, accountId: 'acc-cbe', categoryId: 'cat-salary', transactionDate: '2026-11-01' }), createdAt: '2026-11-01T10:00:00Z' };
      const tx2 = { ...createSimpleFinanceTransaction({ type: 'income', amountCents: 100, accountId: 'acc-cbe', categoryId: 'cat-salary', transactionDate: '2026-11-05' }), createdAt: '2026-11-05T12:00:00Z' };
      const tx3 = { ...createSimpleFinanceTransaction({ type: 'income', amountCents: 100, accountId: 'acc-cbe', categoryId: 'cat-salary', transactionDate: '2026-11-05' }), createdAt: '2026-11-05T15:00:00Z' };
      const tx4 = { ...createSimpleFinanceTransaction({ type: 'income', amountCents: 100, accountId: 'acc-cbe', categoryId: 'cat-salary', transactionDate: '2026-11-03' }), createdAt: '2026-11-03T09:00:00Z' };

      const sorted = sortTransactionsDescending([tx1, tx2, tx3, tx4]);
      assert.equal(sorted[0].id, tx3.id, 'Newest date + newest time first');
      assert.equal(sorted[1].id, tx2.id);
      assert.equal(sorted[2].id, tx4.id);
      assert.equal(sorted[3].id, tx1.id);
    });

    it('27.2: Groups transactions by date with Today and Yesterday labels', () => {
      const refToday = '2026-11-10';
      const txToday = createSimpleFinanceTransaction({ type: 'income', amountCents: 2000, accountId: 'acc-cbe', categoryId: 'cat-salary', transactionDate: '2026-11-10' });
      const txYesterday = createSimpleFinanceTransaction({ type: 'expense', amountCents: 1000, accountId: 'acc-cbe', categoryId: 'cat-food', transactionDate: '2026-11-09' });
      const txEarlier = createSimpleFinanceTransaction({ type: 'expense', amountCents: 500, accountId: 'acc-cbe', categoryId: 'cat-transport', transactionDate: '2026-11-02' });

      const groups = groupTransactionsByDate([txToday, txYesterday, txEarlier], refToday);
      assert.equal(groups.length, 3);
      assert.equal(groups[0].label, 'Today');
      assert.equal(groups[0].transactions.length, 1);
      assert.equal(groups[0].totalInflowCents, 2000);

      assert.equal(groups[1].label, 'Yesterday');
      assert.equal(groups[1].transactions.length, 1);
      assert.equal(groups[1].totalOutflowCents, 1000);

      assert.ok(groups[2].label.includes('2026'));
      assert.equal(groups[2].totalOutflowCents, 500);
    });

    it('27.6: Empty transactions list returns empty group array gracefully', () => {
      const groups = groupTransactionsByDate([]);
      assert.equal(groups.length, 0);
    });
  });

  // -------------------------------------------------------------
  // TASK 28: Correcting Opening Balances & Account Starting Info
  // -------------------------------------------------------------
  describe('Task 28 — Correcting Opening Balances & History Protection', () => {
    it('28.1 & 28.2: Correcting opening balance updates account balance and combined balance', () => {
      const initialAccount: Account = {
        id: 'acc-cbe',
        name: 'CBE',
        type: 'asset',
        currencyCode: 'ETB',
        openingBalanceCents: 100000, // 1,000 ETB initially
        openingBalanceDate: '2026-11-01',
        isArchived: false,
        createdAt: '2026-11-01T00:00:00Z',
      };

      const txs: SimpleTransaction[] = [
        createSimpleFinanceTransaction({
          type: 'income',
          amountCents: 20000, // +200 ETB
          accountId: 'acc-cbe',
          categoryId: 'cat-salary',
        }),
        createSimpleFinanceTransaction({
          type: 'expense',
          amountCents: 5000, // -50 ETB
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
        }),
      ];

      // Before correction: 1,000 + 200 - 50 = 1,150 ETB (115,000 cents)
      assert.equal(calculateSimpleAccountBalance(initialAccount, txs), 115000);

      // User corrects opening balance to 2,500 ETB (250,000 cents) and updates date to '2026-10-31'
      const updatedAccount = correctAccountOpeningBalance(initialAccount, 250000, '2026-10-31');

      assert.equal(updatedAccount.openingBalanceCents, 250000);
      assert.equal(updatedAccount.openingBalanceDate, '2026-10-31');

      // After correction: 2,500 + 200 - 50 = 2,650 ETB (265,000 cents)
      const newBalance = calculateSimpleAccountBalance(updatedAccount, txs);
      assert.equal(newBalance, 265000);

      // Combined balance reflects the updated opening balance
      const combined = calculateSimpleCombinedBalance([updatedAccount], txs);
      assert.equal(combined, 265000);
    });

    it('28.3: History protection: zero historical transactions are altered or created', () => {
      const initialTxs: SimpleTransaction[] = [
        createSimpleFinanceTransaction({
          type: 'income',
          amountCents: 20000,
          accountId: 'acc-cbe',
          categoryId: 'cat-salary',
        }),
      ];
      const origId = initialTxs[0].id;
      const origAmount = initialTxs[0].amountCents;

      const updatedAccount = correctAccountOpeningBalance(baseAccounts[0], 5000000);
      assert.equal(updatedAccount.openingBalanceCents, 5000000);

      // Transactions array is completely untouched
      assert.equal(initialTxs.length, 1);
      assert.equal(initialTxs[0].id, origId);
      assert.equal(initialTxs[0].amountCents, origAmount);
      assert.equal(initialTxs[0].type, 'income');
    });

    it('28.4: Rejects non-integer cents opening balances', () => {
      assert.throws(() => {
        correctAccountOpeningBalance(baseAccounts[0], 123.45);
      }, /integer/i);
    });
  });

  // -------------------------------------------------------------
  // TASK 29: Transaction Search and Multi-Filtering
  // -------------------------------------------------------------
  describe('Task 29 — Search and Multi-Filtering', () => {
    const txList: SimpleTransaction[] = [
      createSimpleFinanceTransaction({
        type: 'expense',
        amountCents: 35000, // 350 ETB
        accountId: 'acc-cbe',
        categoryId: 'cat-food',
        description: 'Supermarket Grocery shopping',
        transactionDate: '2026-11-10', // Today
      }),
      createSimpleFinanceTransaction({
        type: 'expense',
        amountCents: 15000, // 150 ETB
        accountId: 'acc-telebirr',
        categoryId: 'cat-transport',
        description: 'Ride fare to office',
        transactionDate: '2026-11-09', // Yesterday
      }),
      createSimpleFinanceTransaction({
        type: 'income',
        amountCents: 800000, // 8,000 ETB
        accountId: 'acc-boa',
        categoryId: 'cat-salary',
        description: 'Monthly payroll salary',
        transactionDate: '2026-11-05', // This week / month
      }),
      createSimpleFinanceTransaction({
        type: 'transfer',
        amountCents: 200000, // 2,000 ETB
        accountId: 'acc-boa',
        destinationAccountId: 'acc-cbe',
        description: 'Fund transfer to CBE',
        transactionDate: '2026-11-08',
      }),
    ];

    it('29.1: Text search matches description, category name, or account name case-insensitively', () => {
      // By description keyword "grocery"
      const res1 = searchAndFilterTransactions(txList, baseAccounts, categories, {
        query: 'grocery',
      });
      assert.equal(res1.length, 1);
      assert.equal(res1[0].categoryId, 'cat-food');

      // By category name "transport"
      const res2 = searchAndFilterTransactions(txList, baseAccounts, categories, {
        query: 'Transport',
      });
      assert.equal(res2.length, 1);
      assert.equal(res2[0].accountId, 'acc-telebirr');

      // By account name "Telebirr"
      const res3 = searchAndFilterTransactions(txList, baseAccounts, categories, {
        query: 'telebirr',
      });
      assert.equal(res3.length, 1);

      // By transfer destination account name "CBE"
      const res4 = searchAndFilterTransactions(txList, baseAccounts, categories, {
        query: 'cbe',
      });
      // Matches grocery (acc-cbe) and transfer (destination: acc-cbe)
      assert.equal(res4.length, 2);
    });

    it('29.2: Date preset filters (today, yesterday, this_week, this_month, custom)', () => {
      const refToday = '2026-11-10'; // Tuesday

      // Today
      const todayResults = searchAndFilterTransactions(txList, baseAccounts, categories, {
        datePreset: 'today',
        referenceDateStr: refToday,
      });
      assert.equal(todayResults.length, 1);
      assert.equal(todayResults[0].transactionDate, '2026-11-10');

      // Yesterday
      const yestResults = searchAndFilterTransactions(txList, baseAccounts, categories, {
        datePreset: 'yesterday',
        referenceDateStr: refToday,
      });
      assert.equal(yestResults.length, 1);
      assert.equal(yestResults[0].transactionDate, '2026-11-09');

      // This Month (November 2026)
      const monthResults = searchAndFilterTransactions(txList, baseAccounts, categories, {
        datePreset: 'this_month',
        referenceDateStr: refToday,
      });
      assert.equal(monthResults.length, 4, 'All 4 transactions were in November 2026');

      // Custom Range
      const customResults = searchAndFilterTransactions(txList, baseAccounts, categories, {
        datePreset: 'custom',
        customStartDate: '2026-11-07',
        customEndDate: '2026-11-09',
      });
      assert.equal(customResults.length, 2); // transfer (08) and transport (09)
    });

    it('29.3: Synergistic multi-filtering (Type + Account + Search Query)', () => {
      const results = searchAndFilterTransactions(txList, baseAccounts, categories, {
        type: 'expense',
        accountId: 'acc-cbe',
        query: 'Supermarket',
      });
      assert.equal(results.length, 1);
      assert.equal(results[0].accountId, 'acc-cbe');
      assert.equal(results[0].type, 'expense');

      // Mismatched criteria returns empty
      const emptyRes = searchAndFilterTransactions(txList, baseAccounts, categories, {
        type: 'income',
        accountId: 'acc-cbe',
      });
      assert.equal(emptyRes.length, 0);
    });

    it('29.6: Clearing filters returns all transactions', () => {
      const all = searchAndFilterTransactions(txList, baseAccounts, categories, {
        type: 'all',
        accountId: 'all',
        datePreset: 'all',
        query: '',
      });
      assert.equal(all.length, txList.length);
    });
  });

  // -------------------------------------------------------------
  // TASK 30: Financial Data Integrity, Reconciliation, and Recovery
  // -------------------------------------------------------------
  describe('Task 30 — Financial Data Integrity, Reconciliation, and Recovery', () => {
    it('30.1: Health audit passes for consistent ledger and computes accurate per-account reconciliation', () => {
      const txs: SimpleTransaction[] = [
        createSimpleFinanceTransaction({
          type: 'income',
          amountCents: 50000,
          accountId: 'acc-cbe',
          categoryId: 'cat-salary',
          transactionDate: '2026-11-05',
        }),
        createSimpleFinanceTransaction({
          type: 'expense',
          amountCents: 15000,
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          transactionDate: '2026-11-06',
        }),
        createSimpleFinanceTransaction({
          type: 'transfer',
          amountCents: 100000,
          accountId: 'acc-boa',
          destinationAccountId: 'acc-cbe',
          transactionDate: '2026-11-08',
        }),
      ];

      const report = verifyFinancialDataIntegrity(baseAccounts, categories, txs);
      assert.equal(report.isHealthy, true);
      assert.equal(report.errors.length, 0);
      assert.equal(report.accountReconciliations.length, 3);

      const cbeAudit = report.accountReconciliations.find((a) => a.accountId === 'acc-cbe');
      assert.ok(cbeAudit);
      assert.equal(cbeAudit.openingBalanceCents, 1000000);
      assert.equal(cbeAudit.inflowsCents, 150000); // 50k salary + 100k transfer in
      assert.equal(cbeAudit.outflowsCents, 15000); // 15k food
      assert.equal(cbeAudit.calculatedBalanceCents, 1135000); // 1,000,000 + 150,000 - 15,000

      // Combined balance matches
      assert.equal(
        report.activeAccountsCombinedBalanceCents,
        calculateSimpleCombinedBalance(baseAccounts, txs)
      );
    });

    it('30.3 & 30.4: Detects missing account reference, missing category, and identical transfer accounts', () => {
      const badTxs: SimpleTransaction[] = [
        {
          id: 'tx-bad-1',
          type: 'transfer',
          amountCents: 1000,
          accountId: 'acc-cbe',
          destinationAccountId: 'acc-cbe', // IDENTICAL ACCOUNTS
          transactionDate: '2026-11-10',
          createdAt: new Date().toISOString(),
        },
        {
          id: 'tx-bad-2',
          type: 'expense',
          amountCents: 2000,
          accountId: 'acc-nonexistent', // MISSING ACCOUNT
          categoryId: 'cat-food',
          transactionDate: '2026-11-10',
          createdAt: new Date().toISOString(),
        },
        {
          id: 'tx-bad-3',
          type: 'income',
          amountCents: 5000,
          accountId: 'acc-cbe',
          categoryId: 'cat-missing-cat', // UNKNOWN CATEGORY
          transactionDate: '2026-11-10',
          createdAt: new Date().toISOString(),
        },
      ];

      const report = verifyFinancialDataIntegrity(baseAccounts, categories, badTxs);
      assert.equal(report.isHealthy, false);
      assert.ok(report.errors.some((e) => e.includes('identical source and destination')));
      assert.ok(report.errors.some((e) => e.includes('missing source account ID: acc-nonexistent')));
      assert.ok(report.warnings.some((w) => w.includes('cat-missing-cat')));
    });

    it('30.5 & 30.6: Detects duplicate transaction IDs and invalid transaction amounts', () => {
      const corruptedTxs: SimpleTransaction[] = [
        {
          id: 'dup-id',
          type: 'expense',
          amountCents: -500, // NEGATIVE AMOUNT
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          transactionDate: '2026-11-10',
          createdAt: new Date().toISOString(),
        },
        {
          id: 'dup-id', // DUPLICATE ID
          type: 'expense',
          amountCents: 1000,
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          transactionDate: '2026-11-10',
          createdAt: new Date().toISOString(),
        },
      ];

      const report = verifyFinancialDataIntegrity(baseAccounts, categories, corruptedTxs);
      assert.equal(report.isHealthy, false);
      assert.ok(report.errors.some((e) => e.includes('Duplicate transaction ID')));
      assert.ok(report.errors.some((e) => e.includes('invalid amount: -500')));
    });
  });
});
