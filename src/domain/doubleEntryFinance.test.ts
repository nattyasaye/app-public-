import test from 'node:test';
import assert from 'node:assert/strict';
import {
  Account,
  Party,
  JournalEntry,
  Posting,
  Debt,
  validateBalancedEntry,
  DoubleEntryValidationError,
  calculateAccountBalance,
  calculateLiquidCash,
  calculatePrepaidCardCredit,
  calculateShortTermCreditOwed,
  calculateAvailableToSpend,
  calculateNetPosition,
  generateOccurrenceReport,
  generateCashFlowReport,
  buildDirectExpense,
  buildThirdPartyPaidExpense,
  buildLendMoney,
  buildBorrowMoney,
  buildSplitExpense,
  buildTransfer,
  buildDebtSettlement,
  buildVoidEntry,
  parseQuickCaptureExpense,
  calculateBudgetStatus,
  filterJournalEntries,
  CategoryBudget,
  TransactionCategory,
} from './doubleEntryFinance';

test('1. Balanced entry validation passes for valid debits == credits', () => {
  const postings: Posting[] = [
    { id: 'p1', entryId: 'e1', accountId: 'acc-exp', amountCents: 50000, direction: 'debit', accountMovementDate: '2026-11-01' },
    { id: 'p2', entryId: 'e1', accountId: 'acc-cbe', amountCents: 50000, direction: 'credit', accountMovementDate: '2026-11-01' },
  ];
  assert.doesNotThrow(() => validateBalancedEntry(postings));
});

test('2. Unbalanced entry throws DoubleEntryValidationError', () => {
  const unbalanced: Posting[] = [
    { id: 'p1', entryId: 'e1', accountId: 'acc-exp', amountCents: 50000, direction: 'debit', accountMovementDate: '2026-11-01' },
    { id: 'p2', entryId: 'e1', accountId: 'acc-cbe', amountCents: 45000, direction: 'credit', accountMovementDate: '2026-11-01' },
  ];
  assert.throws(() => validateBalancedEntry(unbalanced), DoubleEntryValidationError);
});

test('3. Safe Harbor Available to Spend strictly excludes receivables', () => {
  const avail = calculateAvailableToSpend({
    liquidCashCents: 5000000, // 50,000 ETB
    unpaidPayablesDueInPeriodCents: 1500000, // 15,000 ETB
    reservedSavingsCents: 1000000, // 10,000 ETB emergency
  });
  // 50,000 - 15,000 - 10,000 = 25,000 ETB (2,500,000 cents)
  assert.equal(avail, 2500000);
});

test('4. Boundary Test: Jan 30 third-party paid meal repaid on Feb 2', () => {
  const accounts: Account[] = [
    { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', isArchived: false, createdAt: '2026-01-01' },
    { id: 'acc-exp-dining', name: 'Expense: Dining', type: 'expense', currencyCode: 'ETB', isArchived: false, createdAt: '2026-01-01' },
    { id: 'acc-pay', name: 'Accounts Payable', type: 'liability', currencyCode: 'ETB', isArchived: false, createdAt: '2026-01-01' },
  ];

  // Day 1 (Jan 30): Colleague Abebe pays 1,000 ETB dinner for me
  const { entry: entry1, postings: post1, debt } = buildThirdPartyPaidExpense({
    entryId: 'e-jan-30',
    debtId: 'd-1',
    partyId: 'party-abebe',
    expenseAccountId: 'acc-exp-dining',
    payableAccountId: 'acc-pay',
    amountCents: 100000,
    occurrenceDate: '2026-01-30',
    description: 'Dinner paid by Abebe',
  });

  // Day 5 (Feb 02): I repay Abebe 1,000 ETB from CBE
  const { entry: entry2, postings: post2, updatedDebt } = buildDebtSettlement({
    settlementEntryId: 'e-feb-02',
    debt,
    settlementAccountId: 'acc-cbe',
    debtAccountId: 'acc-pay',
    allocatedPrincipalCents: 100000,
    settlementDate: '2026-02-02',
    description: 'Repaid Abebe for dinner',
  });

  const allEntries = [entry1, entry2];
  const allPostings = [...post1, ...post2];

  // Verify Jan occurrence P&L includes 1,000 ETB expense
  const janReport = generateOccurrenceReport({
    entries: allEntries,
    postings: allPostings,
    accounts,
    categories: [],
    startDate: '2026-01-01',
    endDate: '2026-01-31',
  });
  assert.equal(janReport.totalExpenseCents, 100000);

  // Verify Jan cash flow is 0 (no bank money moved in Jan)
  const janCashFlow = generateCashFlowReport({
    entries: allEntries,
    postings: allPostings,
    accounts,
    startDate: '2026-01-01',
    endDate: '2026-01-31',
  });
  assert.equal(janCashFlow.totalCashOutflowCents, 0);

  // Verify Feb occurrence P&L has 0 expense
  const febReport = generateOccurrenceReport({
    entries: allEntries,
    postings: allPostings,
    accounts,
    categories: [],
    startDate: '2026-02-01',
    endDate: '2026-02-28',
  });
  assert.equal(febReport.totalExpenseCents, 0);

  // Verify Feb cash flow has 1,000 ETB outflow
  const febCashFlow = generateCashFlowReport({
    entries: allEntries,
    postings: allPostings,
    accounts,
    startDate: '2026-02-01',
    endDate: '2026-02-28',
  });
  assert.equal(febCashFlow.totalCashOutflowCents, 100000);
  assert.equal(updatedDebt.status, 'settled');
});

test('5. Transfer with Bank Fee records balanced postings without false income/expense on principal', () => {
  const { entry, postings } = buildTransfer({
    id: 'e-xfer',
    fromAssetAccountId: 'acc-cbe',
    toAssetAccountId: 'acc-telebirr',
    amountCents: 500000, // 5,000 ETB
    transferFeeCents: 1000, // 10 ETB
    feeExpenseAccountId: 'acc-exp-fees',
    date: '2026-11-09',
    description: 'CBE to Telebirr transfer',
  });

  assert.equal(entry.entryType, 'transfer');
  assert.equal(postings.length, 3);
  // Source credit must equal principal + fee
  const sourceCr = postings.find((p) => p.accountId === 'acc-cbe');
  assert.equal(sourceCr?.amountCents, 501000);
});

test('6. Voided transactions are strictly excluded from balance reconstruction', () => {
  const cbeAcc: Account = { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', isArchived: false, createdAt: '2026-01-01' };
  const entryValid: JournalEntry = { id: 'e-1', entryType: 'standard', description: 'Real salary', occurrenceDate: '2026-11-01', isVoided: false, createdAt: '2026-11-01' };
  const entryVoided: JournalEntry = { id: 'e-2', entryType: 'standard', description: 'Mistake deposit', occurrenceDate: '2026-11-02', isVoided: true, voidReason: 'Duplicate', createdAt: '2026-11-02' };

  const postings: Posting[] = [
    { id: 'p1', entryId: 'e-1', accountId: 'acc-cbe', amountCents: 100000, direction: 'debit', accountMovementDate: '2026-11-01' },
    { id: 'p2', entryId: 'e-2', accountId: 'acc-cbe', amountCents: 900000, direction: 'debit', accountMovementDate: '2026-11-02' },
  ];

  const bal = calculateAccountBalance(cbeAcc, postings, undefined, [entryValid, entryVoided]);
  assert.equal(bal, 100000); // 1,000 ETB, NOT 10,000 ETB
});

test('7. Quick capture expense text parser extracts amounts, keywords, and categories', () => {
  const accounts: Account[] = [
    { id: 'acc-telebirr', name: 'Telebirr (ቴሌብር)', type: 'asset', currencyCode: 'ETB', isArchived: false, createdAt: '2026-01-01' },
    { id: 'acc-cbe', name: 'CBE Bank', type: 'asset', currencyCode: 'ETB', isArchived: false, createdAt: '2026-01-01' },
  ];
  const categories: TransactionCategory[] = [
    { id: 'cat-dining', name: 'ምግብ ቤት (Dining)', type: 'expense', colorHex: '#E65100', isDefault: false },
    { id: 'cat-groceries', name: 'ምግብና ሸቀጥ (Groceries)', type: 'expense', colorHex: '#1B4D3E', isDefault: true },
  ];

  const parsed = parseQuickCaptureExpense('150 lunch telebirr', 'acc-cbe', accounts, categories);
  assert.equal(parsed.amountCents, 15000); // 150 ETB
  assert.equal(parsed.assetAccountId, 'acc-telebirr');
  assert.equal(parsed.categoryId, 'cat-dining');
});

test('8. Category budget status triggers warning at 80% and over-budget above 100%', () => {
  const budgets: CategoryBudget[] = [
    { categoryId: 'cat-groceries', categoryName: 'Groceries', limitCents: 1000000 }, // 10,000 ETB limit
  ];

  // 8,500 ETB spent (85% -> warning)
  const report85: any = { categoryBreakdown: { Groceries: 850000 } };
  const status85 = calculateBudgetStatus(budgets, report85);
  assert.equal(status85[0].percentageUsed, 85);
  assert.equal(status85[0].isWarning, true);
  assert.equal(status85[0].isOverBudget, false);

  // 10,500 ETB spent (105% -> over-budget)
  const report105: any = { categoryBreakdown: { Groceries: 1050000 } };
  const status105 = calculateBudgetStatus(budgets, report105);
  assert.equal(status105[0].percentageUsed, 105);
  assert.equal(status105[0].isOverBudget, true);
});

test('9. Option 1 Prepaid Card Credit + ETB-only isolation in Cash/NetPosition', () => {
  const accounts: Account[] = [
    { id: 'acc-cbe', name: 'CBE', type: 'asset', subType: 'bank', currencyCode: 'ETB', openingBalanceCents: 500000, isArchived: false, createdAt: '2026-01-01' },
    { id: 'acc-usd', name: 'USD Checking', type: 'asset', subType: 'bank', currencyCode: 'USD', openingBalanceCents: 999900, isArchived: false, createdAt: '2026-01-01' },
    { id: 'acc-cc', name: 'Card', type: 'liability', subType: 'credit_card', currencyCode: 'ETB', openingBalanceCents: -100000, isArchived: false, createdAt: '2026-01-01' },
  ];

  const liquidCash = calculateLiquidCash(accounts, []);
  const prepaid = calculatePrepaidCardCredit(accounts, []);
  const owed = calculateShortTermCreditOwed(accounts, []);
  const net = calculateNetPosition(accounts, [], []);
  const avail = calculateAvailableToSpend({
    liquidCashCents: liquidCash,
    prepaidCardCreditCents: prepaid,
    shortTermCreditOwedCents: owed,
    unpaidPayablesDueInPeriodCents: 0,
    reservedSavingsCents: 0,
  });

  // 5,000 ETB CBE + 1,000 ETB prepaid credit = 6,000 ETB (USD excluded!)
  assert.equal(liquidCash, 500000);
  assert.equal(prepaid, 100000);
  assert.equal(owed, 0);
  assert.equal(avail, 600000);
  assert.equal(net, 600000);
});

test('10. buildDebtSettlement rejects over-allocation and records fees properly', () => {
  const debt: Debt = {
    id: 'd-test',
    originEntryId: 'e-orig',
    partyId: 'p-1',
    debtType: 'payable',
    principalCents: 100000,
    outstandingCents: 50000,
    status: 'active',
    createdAt: '2026-01-01',
  };

  assert.throws(
    () =>
      buildDebtSettlement({
        settlementEntryId: 'e-over',
        debt,
        settlementAccountId: 'acc-cbe',
        debtAccountId: 'acc-sys-payable',
        allocatedPrincipalCents: 60000,
        settlementDate: '2026-02-01',
        description: 'Overpay',
      }),
    DoubleEntryValidationError
  );

  const ok = buildDebtSettlement({
    settlementEntryId: 'e-ok',
    debt,
    settlementAccountId: 'acc-cbe',
    debtAccountId: 'acc-sys-payable',
    allocatedPrincipalCents: 50000,
    interestCents: 2500,
    interestAccountId: 'acc-sys-expense',
    feeCents: 500,
    feeAccountId: 'acc-sys-expense',
    settlementDate: '2026-02-01',
    description: 'Full repay with interest and fee',
  });
  assert.equal(ok.updatedDebt.status, 'settled');
  assert.equal(ok.postings.reduce((s, p) => (p.direction === 'credit' ? s + p.amountCents : s), 0), 53000);
});
