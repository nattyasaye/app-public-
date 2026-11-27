import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import {
  Account,
  buildDirectExpense,
  buildTransfer,
  calculateAccountBalance,
  calculateCanonicalCategorySpendV7,
  correctJournalEntryV7,
  FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
  FOUNDATION_DEFAULT_INCOME_CATEGORIES,
  generateCashFlowReport,
  generateOccurrenceReport,
  getExpenseRefundSummaryV7,
  hydrateLedgerFromSimpleTransactions,
  JournalEntry,
  Posting,
  recordExpenseRefundV7,
  resolveCategoryDisplayName,
  resolveTransferDisplayEndpoints,
  SimpleTransaction,
  summarizeDirectExpense,
  TransactionCategory,
  unvoidJournalEntryGuardedV7,
  voidJournalEntryGuardedV7,
} from './financeV7Engine';
import {
  DEFAULT_ACCOUNTS,
  DEFAULT_EXPENSE_CATEGORIES,
  DoubleEntryValidationError,
  validateBalancedEntry,
} from './doubleEntryFinance';
import { SYSTEM_CONTROL_ACCOUNT_IDS } from './sharedFoundation';
import { FinanceTransactionsTab } from '../components/finance/FinanceTransactionsTab';
import { FinanceComposerModal } from '../components/finance/FinanceComposerModal';

function makeEtbAccounts(): Account[] {
  return [
    {
      id: 'acc-cbe',
      name: 'CBE',
      type: 'asset',
      subType: 'bank',
      currencyCode: 'ETB',
      openingBalanceCents: 500000, // 5,000 ETB
      isArchived: false,
      createdAt: '2026-11-01T00:00:00Z',
    },
    {
      id: 'acc-telebirr',
      name: 'Telebirr',
      type: 'asset',
      subType: 'mobile_money',
      currencyCode: 'ETB',
      openingBalanceCents: 100000, // 1,000 ETB
      isArchived: false,
      createdAt: '2026-11-01T00:00:00Z',
    },
    {
      id: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      name: 'Expense Control',
      type: 'expense',
      subType: 'nominal_expense',
      currencyCode: 'ETB',
      isSystem: true,
      isArchived: false,
      createdAt: '2026-11-01T00:00:00Z',
    },
    {
      id: SYSTEM_CONTROL_ACCOUNT_IDS.income,
      name: 'Income Control',
      type: 'income',
      subType: 'nominal_income',
      currencyCode: 'ETB',
      isSystem: true,
      isArchived: false,
      createdAt: '2026-11-01T00:00:00Z',
    },
    {
      id: SYSTEM_CONTROL_ACCOUNT_IDS.equity,
      name: 'Opening Balance Equity',
      type: 'equity',
      subType: 'opening_equity',
      currencyCode: 'ETB',
      isSystem: true,
      isArchived: false,
      createdAt: '2026-11-01T00:00:00Z',
    },
  ];
}

describe('Finance Stage 1 — Transfer Display Direction & Optional Expense Fees (Web)', () => {
  it('1. Resolves CBE -> Telebirr and Telebirr -> CBE strictly from posting direction regardless of insertion order', () => {
    const accounts = makeEtbAccounts();
    const accountById = new Map(accounts.map((a) => [a.id, a]));

    const builtCbeToTelebirr = buildTransfer({
      id: 'xfer-1',
      fromAssetAccountId: 'acc-cbe',
      toAssetAccountId: 'acc-telebirr',
      amountCents: 25000,
      transferFeeCents: 500,
      feeExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      feeCategoryId: 'cat-fees',
      date: '2026-11-10',
      description: 'Top up wallet',
    });

    // Normal order
    const forward = resolveTransferDisplayEndpoints(
      builtCbeToTelebirr.postings,
      accountById
    );
    assert.equal(forward.isUnambiguous, true);
    assert.equal(forward.sourceName, 'CBE');
    assert.equal(forward.destinationName, 'Telebirr');
    assert.equal(forward.displayLabel, 'CBE → Telebirr');

    // Reversed posting insertion order + system posting first
    const reversedOrderPostings = [...builtCbeToTelebirr.postings].reverse();
    const reversedOrderResult = resolveTransferDisplayEndpoints(
      reversedOrderPostings,
      accountById
    );
    assert.equal(reversedOrderResult.isUnambiguous, true);
    assert.equal(reversedOrderResult.displayLabel, 'CBE → Telebirr');
    assert.ok(!reversedOrderResult.displayLabel.includes('Expense Control'));

    // Opposite transfer direction (Telebirr -> CBE)
    const builtTelebirrToCbe = buildTransfer({
      id: 'xfer-2',
      fromAssetAccountId: 'acc-telebirr',
      toAssetAccountId: 'acc-cbe',
      amountCents: 10000,
      date: '2026-11-11',
      description: 'Cash back to bank',
    });
    const reverseDir = resolveTransferDisplayEndpoints(
      [...builtTelebirrToCbe.postings].reverse(),
      accountById
    );
    assert.equal(reverseDir.isUnambiguous, true);
    assert.equal(reverseDir.displayLabel, 'Telebirr → CBE');
  });

  it('2. Handles missing or ambiguous transfer postings safely without inventing a direction', () => {
    const accounts = makeEtbAccounts();
    const accountById = new Map(accounts.map((a) => [a.id, a]));

    // Only one non-system posting (missing destination)
    const missingDest = resolveTransferDisplayEndpoints(
      [
        {
          id: 'p1',
          entryId: 'x-missing',
          accountId: 'acc-cbe',
          amountCents: 10000,
          direction: 'credit',
          accountMovementDate: '2026-11-10',
        },
        {
          id: 'p2',
          entryId: 'x-missing',
          accountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
          amountCents: 10000,
          direction: 'debit',
          accountMovementDate: '2026-11-10',
        },
      ],
      accountById
    );
    assert.equal(missingDest.isUnambiguous, false);
    assert.ok(!missingDest.displayLabel.includes('→'));
    assert.equal(missingDest.displayLabel, 'CBE');

    // Ambiguous: two distinct credit postings
    const ambiguous = resolveTransferDisplayEndpoints(
      [
        {
          id: 'p1',
          entryId: 'x-ambig',
          accountId: 'acc-cbe',
          amountCents: 5000,
          direction: 'credit',
          accountMovementDate: '2026-11-10',
        },
        {
          id: 'p2',
          entryId: 'x-ambig',
          accountId: 'acc-telebirr',
          amountCents: 5000,
          direction: 'debit',
          accountMovementDate: '2026-11-10',
        },
        {
          id: 'p3',
          entryId: 'x-ambig',
          accountId: 'acc-cash',
          amountCents: 5000,
          direction: 'credit',
          accountMovementDate: '2026-11-10',
        },
      ],
      accountById
    );
    assert.equal(ambiguous.isUnambiguous, false);
    assert.ok(!ambiguous.displayLabel.includes('→'));
  });

  it('3. FinanceTransactionsTab renders both CBE → Telebirr and Telebirr → CBE cleanly regardless of posting order', () => {
    const accounts = makeEtbAccounts();
    const t1 = buildTransfer({
      id: 'xfer-forward',
      fromAssetAccountId: 'acc-cbe',
      toAssetAccountId: 'acc-telebirr',
      amountCents: 20000,
      transferFeeCents: 500,
      feeExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      feeCategoryId: 'cat-fees',
      date: '2026-11-10',
      description: 'Wallet Topup',
    });
    const t2 = buildTransfer({
      id: 'xfer-back',
      fromAssetAccountId: 'acc-telebirr',
      toAssetAccountId: 'acc-cbe',
      amountCents: 15000,
      date: '2026-11-11',
      description: 'Bank Sweep',
    });

    const html = renderToStaticMarkup(
      React.createElement(FinanceTransactionsTab, {
        entries: [t1.entry, t2.entry],
        postings: [...t1.postings].reverse().concat([...t2.postings].reverse()),
        accounts,
        categories: DEFAULT_EXPENSE_CATEGORIES,
        onOpenComposer: () => {},
        onVoidEntry: () => ({ ok: true }),
        onRestoreEntry: () => ({ ok: true }),
        onRequestConfirm: () => {},
      })
    );

    assert.ok(html.includes('CBE → Telebirr'), 'Should render CBE → Telebirr');
    assert.ok(html.includes('Telebirr → CBE'), 'Should render Telebirr → CBE');
    assert.ok(!html.includes('Expense Control'), 'System account must not appear as transfer endpoint');
  });

  it('4. Expense with 0 fee creates no unnecessary fee posting and historical expenses report feeCents = 0', () => {
    const accounts = makeEtbAccounts();
    const accountById = new Map(accounts.map((a) => [a.id, a]));

    const res = buildDirectExpense({
      id: 'exp-zero-fee',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 100000,
      feeCents: 0,
      occurrenceDate: '2026-11-12',
      movementDate: '2026-11-12',
      description: 'Lunch',
    });

    assert.equal(res.postings.length, 2);
    assert.doesNotThrow(() => validateBalancedEntry(res.postings));
    const summary = summarizeDirectExpense({
      entry: res.entry,
      postings: res.postings,
      accountById,
    });
    assert.equal(summary.isDirectExpense, true);
    assert.equal(summary.principalCents, 100000);
    assert.equal(summary.feeCents, 0);
    assert.equal(summary.totalOutflowCents, 100000);
    assert.equal(summary.primaryCategoryId, 'cat-food');

    // Legacy historical expense without feeCents parameter
    const legacy = buildDirectExpense({
      id: 'exp-legacy',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-transport',
      amountCents: 25000,
      occurrenceDate: '2026-11-05',
      movementDate: '2026-11-05',
      description: 'Historical taxi',
    });
    const legacySummary = summarizeDirectExpense({
      entry: legacy.entry,
      postings: legacy.postings,
      accountById,
    });
    assert.equal(legacySummary.feeCents, 0);
    assert.equal(legacySummary.principalCents, 25000);
    assert.equal(legacySummary.totalOutflowCents, 25000);
  });

  it('5. Expense with principal 1,000 ETB and fee 15 ETB builds balanced postings using cat-fees, deducts 1,015 ETB, and blocks negative fees', () => {
    const accounts = makeEtbAccounts();
    const accountById = new Map(accounts.map((a) => [a.id, a]));

    assert.throws(
      () =>
        buildDirectExpense({
          id: 'exp-neg-fee',
          assetAccountId: 'acc-cbe',
          expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
          categoryId: 'cat-food',
          amountCents: 100000,
          feeCents: -100,
          occurrenceDate: '2026-11-12',
          movementDate: '2026-11-12',
          description: 'Invalid fee',
        }),
      DoubleEntryValidationError
    );

    const res = buildDirectExpense({
      id: 'exp-with-fee',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 100000, // 1,000 ETB
      feeCents: 1500, // 15 ETB
      feeExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      feeCategoryId: 'cat-fees',
      occurrenceDate: '2026-11-12',
      movementDate: '2026-11-12',
      description: 'Groceries with bank fee',
    });

    assert.equal(res.postings.length, 3);
    assert.doesNotThrow(() => validateBalancedEntry(res.postings));

    const drPrincipal = res.postings.find((p) => p.id === 'exp-with-fee-post-dr');
    const drFee = res.postings.find((p) => p.id === 'exp-with-fee-post-dr-fee');
    const crAccount = res.postings.find((p) => p.id === 'exp-with-fee-post-cr');
    assert.equal(drPrincipal?.amountCents, 100000);
    assert.equal(drPrincipal?.categoryId, 'cat-food');
    assert.equal(drFee?.amountCents, 1500);
    assert.equal(drFee?.categoryId, 'cat-fees');
    assert.equal(crAccount?.amountCents, 101500);
    assert.equal(crAccount?.accountId, 'acc-cbe');

    const cbeBalance = calculateAccountBalance(
      accounts[0],
      res.postings,
      undefined,
      [res.entry]
    );
    // Opening 5,000 ETB - 1,015 ETB = 3,985 ETB
    assert.equal(cbeBalance, 398500);

    const summary = summarizeDirectExpense({
      entry: res.entry,
      postings: res.postings,
      accountById,
    });
    assert.equal(summary.principalCents, 100000);
    assert.equal(summary.feeCents, 1500);
    assert.equal(summary.totalOutflowCents, 101500);
    assert.equal(summary.primaryCategoryId, 'cat-food');
    assert.equal(summary.feeCategoryId, 'cat-fees');
  });

  it('6. Expense fee refund caps at principal (1,000 ETB) excluding 15 ETB fee, and reports/category totals avoid double counting', () => {
    const accounts = makeEtbAccounts();
    const exp = buildDirectExpense({
      id: 'exp-1000-fee-15',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 100000,
      feeCents: 1500,
      feeExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      feeCategoryId: 'cat-fees',
      occurrenceDate: '2026-11-12',
      movementDate: '2026-11-12',
      description: 'Merchant purchase',
    });

    const entries = [exp.entry];
    const postings = [...exp.postings];

    // Check foundation-only categories still resolve cat-fees to Financial Fees
    const foundationCats: TransactionCategory[] = [
      ...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
      ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
    ];
    assert.equal(resolveCategoryDisplayName(foundationCats, 'cat-fees'), 'Financial Fees');

    // Reports check before refund
    const pnlBefore = generateOccurrenceReport({
      entries,
      postings,
      accounts,
      categories: foundationCats,
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    });
    assert.equal(pnlBefore.totalExpenseCents, 101500);

    const catSpendBefore = calculateCanonicalCategorySpendV7({
      entries,
      postings,
      accounts,
      categories: foundationCats,
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    });
    assert.equal(catSpendBefore.totalExpenseCents, 101500);
    assert.equal(catSpendBefore.directSpendByCategoryId['cat-food'], 100000);
    assert.equal(catSpendBefore.directSpendByCategoryId['cat-fees'], 1500);
    const feeRow = catSpendBefore.rows.find((r) => r.categoryId === 'cat-fees');
    assert.equal(feeRow?.categoryName, 'Financial Fees');

    const cashFlow = generateCashFlowReport({
      entries,
      postings,
      accounts,
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    });
    assert.equal(cashFlow.totalCashOutflowCents, 101500);

    // Refund validation: principal only (1,000 ETB), rejecting 1,015 ETB
    const refundSummary = getExpenseRefundSummaryV7({
      originalEntryId: exp.entry.id,
      entries,
      postings,
      accounts,
    });
    assert.equal(refundSummary.eligible, true);
    assert.equal(refundSummary.originalAmountCents, 100000);
    assert.equal(refundSummary.originalFeeCents, 1500);
    assert.equal(refundSummary.remainingRefundableCents, 100000);

    assert.throws(
      () =>
        recordExpenseRefundV7({
          originalEntryId: exp.entry.id,
          refundAccountId: 'acc-cbe',
          refundCents: 101500,
          refundDateIso: '2026-11-13',
          entries,
          postings,
          accounts,
        }),
      DoubleEntryValidationError
    );

    const refundRes = recordExpenseRefundV7({
      refundEntryId: 'refund-1',
      originalEntryId: exp.entry.id,
      refundAccountId: 'acc-cbe',
      refundCents: 100000,
      refundDateIso: '2026-11-13',
      entries,
      postings,
      accounts,
    });
    assert.equal(refundRes.updatedSummary.remainingRefundableCents, 0);

    const afterRefundEntries = [refundRes.entry, ...entries];
    const afterRefundPostings = [...refundRes.postings, ...postings];
    const catSpendAfter = calculateCanonicalCategorySpendV7({
      entries: afterRefundEntries,
      postings: afterRefundPostings,
      accounts,
      categories: foundationCats,
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    });
    // Principal refunded (1000 - 1000 = 0), bank fee remains 15 ETB!
    assert.equal(catSpendAfter.directSpendByCategoryId['cat-food'], 0);
    assert.equal(catSpendAfter.directSpendByCategoryId['cat-fees'], 1500);
    assert.equal(catSpendAfter.totalExpenseCents, 1500);
  });

  it('7. Editing/replacement, void/unvoid, and simple-transaction hydration keep principal and fee consistent without double-counting', () => {
    const accounts = makeEtbAccounts();
    const orig = buildDirectExpense({
      id: 'exp-orig',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 100000,
      feeCents: 1500,
      feeExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      feeCategoryId: 'cat-fees',
      occurrenceDate: '2026-11-12',
      movementDate: '2026-11-12',
      description: 'Groceries',
    });
    const origSimpleTx: SimpleTransaction = {
      id: 'tx-exp-orig',
      type: 'expense',
      amountCents: 100000,
      accountId: 'acc-cbe',
      categoryId: 'cat-food',
      description: 'Groceries',
      transactionDate: '2026-11-12',
      createdAt: orig.entry.createdAt,
      updatedAt: orig.entry.createdAt,
      journalEntryId: orig.entry.id,
    };

    // Hydrating from simpleTransactions must not overwrite or duplicate journal entry with fee
    const hydrated = hydrateLedgerFromSimpleTransactions({
      transactions: [origSimpleTx],
      entries: [orig.entry],
      postings: orig.postings,
      accounts,
    });
    assert.equal(hydrated.migratedCount, 0);
    assert.equal(hydrated.entries.filter((e) => e.entryType === 'standard').length, 1);
    assert.equal(hydrated.entries.find((e) => e.id === orig.entry.id)?.id, orig.entry.id);
    assert.equal(
      hydrated.postings.filter((p) => p.entryId === orig.entry.id).length,
      3
    );

    // Replace with revised principal 1,200 ETB and fee 20 ETB
    const replacement = buildDirectExpense({
      id: 'exp-repl',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 120000,
      feeCents: 2000,
      feeExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      feeCategoryId: 'cat-fees',
      occurrenceDate: '2026-11-12',
      movementDate: '2026-11-12',
      description: 'Groceries updated',
      correctedFromEntryId: orig.entry.id,
    });
    const replSimpleTx: SimpleTransaction = {
      id: 'tx-exp-repl',
      type: 'expense',
      amountCents: 120000,
      accountId: 'acc-cbe',
      categoryId: 'cat-food',
      description: 'Groceries updated',
      transactionDate: '2026-11-12',
      createdAt: replacement.entry.createdAt,
      updatedAt: replacement.entry.createdAt,
      journalEntryId: replacement.entry.id,
    };

    const corrected = correctJournalEntryV7({
      originalEntryId: orig.entry.id,
      replacementEntry: replacement.entry,
      replacementPostings: replacement.postings,
      correctionReason: 'Updated receipt and bank fee',
      accounts,
      entries: [orig.entry],
      postings: orig.postings,
      debts: [],
      allocations: [],
      commitments: [],
      commitmentSettlements: [],
      savingsGoals: [],
      simpleTransactions: [origSimpleTx],
      replacementSimpleTx: replSimpleTx,
    });

    // Balance reflects ONLY replacement (5,000 - 1,220 = 3,780 ETB)
    const balAfterReplace = calculateAccountBalance(
      accounts[0],
      corrected.updatedPostings,
      undefined,
      corrected.updatedEntries
    );
    assert.equal(balAfterReplace, 378000);
    assert.equal(corrected.updatedSimpleTransactions.find((t) => t.id === 'tx-exp-orig')?.isSuperseded, true);

    // Voiding replacement restores opening balance 5,000 ETB; unvoiding restores 3,780 ETB
    const voided = voidJournalEntryGuardedV7({
      entryId: replacement.entry.id,
      reason: 'Cancelled order',
      accounts,
      entries: corrected.updatedEntries,
      postings: corrected.updatedPostings,
      debts: corrected.updatedDebts,
      allocations: [],
      commitments: corrected.updatedCommitments,
      commitmentSettlements: [],
      savingsGoals: corrected.updatedSavingsGoals,
      simpleTransactions: corrected.updatedSimpleTransactions,
    });
    assert.equal(
      calculateAccountBalance(
        accounts[0],
        corrected.updatedPostings,
        undefined,
        voided.updatedEntries
      ),
      500000
    );

    const restored = unvoidJournalEntryGuardedV7({
      entryId: replacement.entry.id,
      accounts,
      entries: voided.updatedEntries,
      postings: corrected.updatedPostings,
      debts: voided.updatedDebts,
      allocations: [],
      commitments: voided.updatedCommitments,
      commitmentSettlements: [],
      savingsGoals: voided.updatedSavingsGoals,
      simpleTransactions: voided.updatedSimpleTransactions,
    });
    assert.equal(
      calculateAccountBalance(
        accounts[0],
        corrected.updatedPostings,
        undefined,
        restored.updatedEntries
      ),
      378000
    );
  });

  it('8. FinanceTransactionsTab and FinanceComposerModal UI render expense fee total, fee details, optional expense fee input, and exclude income fees', () => {
    const accounts = makeEtbAccounts();
    const exp = buildDirectExpense({
      id: 'exp-ui',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 100000,
      feeCents: 1500,
      feeExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      feeCategoryId: 'cat-fees',
      occurrenceDate: '2026-11-12',
      movementDate: '2026-11-12',
      description: 'Supermarket',
    });

    const txHtml = renderToStaticMarkup(
      React.createElement(FinanceTransactionsTab, {
        entries: [exp.entry],
        postings: exp.postings,
        accounts,
        categories: DEFAULT_EXPENSE_CATEGORIES,
        onOpenComposer: () => {},
        onVoidEntry: () => ({ ok: true }),
        onRestoreEntry: () => ({ ok: true }),
        onRequestConfirm: () => {},
      })
    );
    assert.ok(txHtml.includes('-1,015.00 ETB'), 'Main amount should show total deduction -1,015.00 ETB');
    assert.ok(txHtml.includes('Includes 15.00 ETB fee'), 'Should display fee breakdown');
    assert.ok(txHtml.includes('Principal 1,000.00 ETB'), 'Should identify principal expense');
    assert.ok(txHtml.includes('Food'), 'Primary category should display merchant category Food');

    // Composer in Expense mode defaults fee input to 0
    const newExpenseComposerHtml = renderToStaticMarkup(
      React.createElement(FinanceComposerModal, {
        isOpen: true,
        prefill: {
          nonce: 0,
          kind: 'expense',
        },
        accounts: DEFAULT_ACCOUNTS,
        categories: DEFAULT_EXPENSE_CATEGORIES,
        parties: [],
        onClose: () => {},
        onCreateParty: (name: string) => ({
          id: 'p-1',
          name,
          isArchived: false,
          createdAt: '2026-11-12T00:00:00Z',
        }),
        onSubmit: () => ({ ok: true }),
      })
    );
    assert.ok(newExpenseComposerHtml.includes('Bank / Service Fee (ETB, optional)'));
    assert.ok(newExpenseComposerHtml.includes('value="0"'));

    // Composer in Expense edit mode prefills principal (1000.00) & fee (15.00) and displays total deduction
    const editExpenseComposerHtml = renderToStaticMarkup(
      React.createElement(FinanceComposerModal, {
        isOpen: true,
        prefill: {
          nonce: 1,
          kind: 'expense',
          amountText: '1000.00',
          feeText: '15.00',
          feeCategoryId: 'cat-fees',
        },
        accounts: DEFAULT_ACCOUNTS,
        categories: DEFAULT_EXPENSE_CATEGORIES,
        parties: [],
        onClose: () => {},
        onCreateParty: (name: string) => ({
          id: 'p-1',
          name,
          isArchived: false,
          createdAt: '2026-11-12T00:00:00Z',
        }),
        onSubmit: () => ({ ok: true }),
      })
    );
    assert.ok(editExpenseComposerHtml.includes('value="1000.00"'));
    assert.ok(editExpenseComposerHtml.includes('value="15.00"'));
    assert.ok(editExpenseComposerHtml.includes('Total deduction: 1,015.00 ETB'));

    // Composer in Income mode must NOT show fee input
    const incomeComposerHtml = renderToStaticMarkup(
      React.createElement(FinanceComposerModal, {
        isOpen: true,
        prefill: { nonce: 2, kind: 'income' },
        accounts: DEFAULT_ACCOUNTS,
        categories: [
          ...DEFAULT_EXPENSE_CATEGORIES,
          ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
        ],
        parties: [],
        onClose: () => {},
        onCreateParty: (name: string) => ({
          id: 'p-1',
          name,
          isArchived: false,
          createdAt: '2026-11-12T00:00:00Z',
        }),
        onSubmit: () => ({ ok: true }),
      })
    );
    assert.ok(!incomeComposerHtml.includes('Bank / Service Fee'));
    assert.ok(!incomeComposerHtml.includes('Bank / Transfer Fee'));
  });
});
