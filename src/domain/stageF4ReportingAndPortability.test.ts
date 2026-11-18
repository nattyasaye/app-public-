import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import JSZip from 'jszip';
import * as XLSX from 'xlsx';
import {
  Account,
  buildBorrowMoney,
  buildDirectExpense,
  buildDirectIncome,
  buildLendMoney,
  buildTransfer,
  calculateAccountBalance,
  CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID,
  Debt,
  FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
  FOUNDATION_DEFAULT_INCOME_CATEGORIES,
  JournalEntry,
  Party,
  Posting,
  TransactionCategory,
} from './doubleEntryFinance';
import {
  buildAccountBalancesReportV7,
  buildAlignedBalanceSheetReportV7,
  buildMonthlyBudgetProgressReportV7,
  buildSavingsVaultsAndGoalsReportV7,
  calculateAvailableToSpendBreakdownV7,
  calculateCanonicalCategorySpendV7,
  calculatePeriodComparisonReportV7,
  ensureSystemControlAccounts,
  getCanonicalBudgetSpentCentsV7,
  resolveActiveReportMonthIsoV7,
  resolveReportPeriodWithComparisonV7,
  verifyFinanceV7Integrity,
} from './financeV7Engine';
import {
  SharedBudget,
  SharedCommitment,
  SharedCommitmentSettlement,
  SharedRecurringRule,
  SharedSavingsGoal,
  SYSTEM_CONTROL_ACCOUNT_IDS,
} from './sharedFoundation';
import { DataPortabilityService, ExportDataPayload } from '../services/dataPortabilityService';
import { SharedStateBridge } from '../services/sharedStateBridge';
import { EthiopianDate } from './date';

function withMockBrowserStorage(
  fn: (store: Map<string, string>, events: Array<{ type: string; detail: unknown }>) => void
): void {
  const store = new Map<string, string>();
  const events: Array<{ type: string; detail: unknown }> = [];
  const prevWindow = (globalThis as any).window;
  const prevLocalStorage = (globalThis as any).localStorage;

  const mockStorage = {
    getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
    setItem: (k: string, v: string) => void store.set(k, String(v)),
    removeItem: (k: string) => void store.delete(k),
    clear: () => void store.clear(),
  };

  (globalThis as any).localStorage = mockStorage;
  (globalThis as any).window = {
    dispatchEvent: (ev: { type: string; detail: unknown }) => {
      events.push({ type: ev.type, detail: ev.detail });
      return true;
    },
    CustomEvent: class CustomEvent {
      type: string;
      detail: unknown;
      constructor(type: string, init?: { detail?: unknown }) {
        this.type = type;
        this.detail = init?.detail;
      }
    },
  };

  try {
    fn(store, events);
  } finally {
    (globalThis as any).window = prevWindow;
    (globalThis as any).localStorage = prevLocalStorage;
  }
}

function makeBaseAccounts(): Account[] {
  return ensureSystemControlAccounts([
    {
      id: 'acc-cbe',
      name: 'CBE Checking',
      type: 'asset',
      subType: 'bank',
      currencyCode: 'ETB',
      openingBalanceCents: 1000000,
      openingBalanceDate: '2026-01-01',
      isArchived: false,
      createdAt: '2026-01-01T00:00:00Z',
    },
    {
      id: 'acc-vault',
      name: 'House Vault',
      type: 'asset',
      subType: 'savings_vault',
      currencyCode: 'ETB',
      openingBalanceCents: 300000,
      openingBalanceDate: '2026-01-01',
      isArchived: false,
      createdAt: '2026-01-01T00:00:00Z',
    },
    {
      id: 'acc-card-prepaid',
      name: 'Prepaid Visa ETB',
      type: 'liability',
      subType: 'credit_card',
      currencyCode: 'ETB',
      openingBalanceCents: -25000, // Overpaid by 250 ETB (prepaid credit per Option 1)
      openingBalanceDate: '2026-01-01',
      isArchived: false,
      createdAt: '2026-01-01T00:00:00Z',
    },
    {
      id: 'acc-card-owed',
      name: 'Revolving Credit ETB',
      type: 'liability',
      subType: 'credit_card',
      currencyCode: 'ETB',
      openingBalanceCents: 40000, // 400 ETB owed
      openingBalanceDate: '2026-01-01',
      isArchived: false,
      createdAt: '2026-01-01T00:00:00Z',
    },
    {
      id: 'acc-usd',
      name: 'USD Travel Card',
      type: 'asset',
      subType: 'bank',
      currencyCode: 'USD',
      openingBalanceCents: 150000, // $1,500.00 isolated
      openingBalanceDate: '2026-01-01',
      isArchived: false,
      createdAt: '2026-01-01T00:00:00Z',
    },
  ]);
}

describe('FINANCE STAGE F4 — REPORTING, EXPORT & FINANCE-ONLY PORTABILITY (WORKFLOWS 1-8)', () => {
  it('Workflow 1: Dual-calendar period comparison (Ethiopian Pagume 5 non-leap vs Pagume 6 leap) and safe zero-baseline deltas', () => {
    // 2018 E.C. is non-leap (2018 % 4 === 2 => Pagume has 5 days: 2026-09-06..2026-09-10)
    const pagumeNonLeap = resolveReportPeriodWithComparisonV7({
      mode: 'ethiopianMonth',
      ethYear: 2018,
      ethMonth: 13,
      todayIso: '2026-09-08',
    });
    assert.strictEqual(pagumeNonLeap.daysInCurrent, 5);
    assert.strictEqual(pagumeNonLeap.daysInPrevious, 30); // Nehase 2018 E.C.
    assert.strictEqual(
      pagumeNonLeap.currentStart,
      new EthiopianDate(2018, 13, 1).toCalendarDate().toIsoString()
    );
    assert.strictEqual(
      pagumeNonLeap.currentEnd,
      new EthiopianDate(2018, 13, 5).toCalendarDate().toIsoString()
    );

    // 2019 E.C. is Ethiopian leap year (2019 % 4 === 3 => Pagume has 6 days)
    const pagumeLeap = resolveReportPeriodWithComparisonV7({
      mode: 'ethiopianMonth',
      ethYear: 2019,
      ethMonth: 13,
      todayIso: '2027-09-10',
    });
    assert.strictEqual(pagumeLeap.daysInCurrent, 6);
    assert.strictEqual(
      pagumeLeap.currentEnd,
      new EthiopianDate(2019, 13, 6).toCalendarDate().toIsoString()
    );

    // Meskerem 1 compare against Pagume 2018 E.C. (5 days) + zero-baseline deltas
    const meskerem2019 = resolveReportPeriodWithComparisonV7({
      mode: 'ethiopianMonth',
      ethYear: 2019,
      ethMonth: 1,
      todayIso: '2026-09-15',
    });
    assert.strictEqual(meskerem2019.daysInCurrent, 30);
    assert.strictEqual(meskerem2019.daysInPrevious, 5);

    const accounts = makeBaseAccounts();
    const categories = [
      ...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
      ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
    ];
    const inc = buildDirectIncome({
      id: 'e-meskerem-inc',
      assetAccountId: 'acc-cbe',
      incomeAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.income,
      categoryId: 'cat-salary',
      amountCents: 200000,
      occurrenceDate: meskerem2019.currentStart,
      movementDate: meskerem2019.currentStart,
      description: 'Meskerem Salary',
    });
    const prevExp = buildDirectExpense({
      id: 'e-pagume-exp',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 50000,
      occurrenceDate: meskerem2019.previousStart,
      movementDate: meskerem2019.previousStart,
      description: 'Pagume Coffee',
    });

    const comparison = calculatePeriodComparisonReportV7({
      period: meskerem2019,
      accounts,
      categories,
      entries: [inc.entry, prevExp.entry],
      postings: [...inc.postings, ...prevExp.postings],
    });
    assert.strictEqual(comparison.occurrenceIncome.previousCents, 0);
    assert.strictEqual(comparison.occurrenceIncome.currentCents, 200000);
    assert.strictEqual(comparison.occurrenceIncome.percentageDisplay, '+100% (New)');
    assert.strictEqual(comparison.occurrenceIncome.isPositiveOutcome, true);
    // Expense dropped from 500 ETB in Pagume to 0 in Meskerem -> -100% & positive outcome (less spend)
    assert.strictEqual(comparison.occurrenceExpense.currentCents, 0);
    assert.strictEqual(comparison.occurrenceExpense.previousCents, 50000);
    assert.strictEqual(comparison.occurrenceExpense.percentageDisplay, '-100.0%');
    assert.strictEqual(comparison.occurrenceExpense.isPositiveOutcome, true);
  });

  it('Workflow 2: Occurrence P&L separates from Liquid Cash Flow across months and excludes Vault/Card internal transfers from P&L', () => {
    const accounts = makeBaseAccounts();
    const categories = [
      ...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
      ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
    ];

    // Expense incurred in Oct (occurrence 2026-10-30), cash paid in Nov (movement 2026-11-02)
    const octOccNovCash = buildDirectExpense({
      id: 'e-split-month',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-utilities',
      amountCents: 75000,
      occurrenceDate: '2026-10-30',
      movementDate: '2026-11-02',
      description: 'Deferred Utility Invoice',
    });

    // Liquid -> Vault transfer in Nov must NOT inflate Occurrence Expense/Income P&L,
    // and vault account is excluded from Cash Flow inflows/outflows (asset liquid cash moved out of CBE)
    const vaultTransfer = buildTransfer({
      id: 'e-vault-xfer',
      fromAssetAccountId: 'acc-cbe',
      toAssetAccountId: 'acc-vault',
      amountCents: 100000,
      date: '2026-11-05',
      description: 'Monthly Vault Deposit',
    });

    const novPeriod = resolveReportPeriodWithComparisonV7({
      mode: 'thisMonth',
      todayIso: '2026-11-15',
    });
    assert.strictEqual(novPeriod.currentStart, '2026-11-01');
    assert.strictEqual(novPeriod.currentEnd, '2026-11-30');
    assert.strictEqual(novPeriod.previousStart, '2026-10-01');
    assert.strictEqual(novPeriod.previousEnd, '2026-10-31');

    const cmp = calculatePeriodComparisonReportV7({
      period: novPeriod,
      accounts,
      categories,
      entries: [octOccNovCash.entry, vaultTransfer.entry],
      postings: [...octOccNovCash.postings, ...vaultTransfer.postings],
    });

    // Oct Occurrence sees 750 ETB expense; Oct Cash Flow sees 0 outflow
    assert.strictEqual(cmp.previousOccurrence.totalExpenseCents, 75000);
    assert.strictEqual(cmp.previousCashFlow.totalCashOutflowCents, 0);

    // Nov Occurrence sees 0 expense (transfer isn't expense!); Nov Cash Flow sees 750 + 1000 liquid CBE outflow
    assert.strictEqual(cmp.currentOccurrence.totalExpenseCents, 0);
    assert.strictEqual(cmp.currentCashFlow.totalCashOutflowCents, 175000);
    assert.strictEqual(cmp.currentCashFlow.totalCashInflowCents, 0);
  });

  it('Workflow 3: Hierarchical category spend, alias resolution, cycle safety, voided/correction exclusion, and Plan vs Reports bit-for-bit parity', () => {
    const accounts = makeBaseAccounts();
    const categories: TransactionCategory[] = [
      ...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
      ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
      {
        id: 'cat-food-dining',
        name: 'Dining Out',
        type: 'expense',
        colorHex: '#EF4444',
        parentId: 'cat-food',
      },
      {
        id: 'cat-food-coffee',
        name: 'Buna & Cafes',
        type: 'expense',
        colorHex: '#F97316',
        parentId: 'cat-food-dining',
      },
      // Cyclic pair (must not infinite loop!)
      {
        id: 'cat-cycle-a',
        name: 'Cycle A',
        type: 'expense',
        colorHex: '#64748B',
        parentId: 'cat-cycle-b',
      },
      {
        id: 'cat-cycle-b',
        name: 'Cycle B',
        type: 'expense',
        colorHex: '#64748B',
        parentId: 'cat-cycle-a',
      },
    ];

    const e1 = buildDirectExpense({
      id: 'e-coffee',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food-coffee',
      amountCents: 20000, // 200 ETB leaf -> rolls up to Dining Out -> Food
      occurrenceDate: '2026-11-10',
      movementDate: '2026-11-10',
      description: 'Tomoca',
    });
    const e2 = buildDirectExpense({
      id: 'e-groceries',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 50000, // 500 ETB direct on parent Food
      occurrenceDate: '2026-11-11',
      movementDate: '2026-11-11',
      description: 'Groceries',
    });
    const e3Alias = buildDirectExpense({
      id: 'e-legacy-comm',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-communication', // Legacy alias -> cat-comm
      amountCents: 15000,
      occurrenceDate: '2026-11-12',
      movementDate: '2026-11-12',
      description: 'Ethio Telecom',
    });
    const e4Voided = buildDirectExpense({
      id: 'e-voided',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 99900,
      occurrenceDate: '2026-11-12',
      movementDate: '2026-11-12',
      description: 'Voided Duplicate',
    });
    e4Voided.entry.isVoided = true;
    const e5Replacement = buildDirectExpense({
      id: 'e-replacement',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-cycle-a',
      amountCents: 5000,
      occurrenceDate: '2026-11-14',
      movementDate: '2026-11-14',
      description: 'Cyclic Category Safe Expense',
    });
    e5Replacement.entry.correctedFromEntryId = e4Voided.entry.id;

    const entries = [
      e1.entry,
      e2.entry,
      e3Alias.entry,
      e4Voided.entry,
      e5Replacement.entry,
    ];
    const postings = [
      ...e1.postings,
      ...e2.postings,
      ...e3Alias.postings,
      ...e4Voided.postings,
      ...e5Replacement.postings,
    ];

    const spend = calculateCanonicalCategorySpendV7({
      entries,
      postings,
      accounts,
      categories,
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    });

    // Total expense must NOT double count hierarchy: 200 + 500 + 150 + 50 = 900 ETB (voided 999 excluded)
    assert.strictEqual(spend.totalExpenseCents, 90000);
    assert.strictEqual(spend.directSpendByCategoryId['cat-food'], 50000);
    assert.strictEqual(spend.rollupSpendByCategoryId['cat-food-coffee'], 20000);
    assert.strictEqual(spend.rollupSpendByCategoryId['cat-food-dining'], 20000);
    assert.strictEqual(spend.rollupSpendByCategoryId['cat-food'], 70000);
    assert.strictEqual(spend.rollupSpendByCategoryId['cat-comm'], 15000);

    // Budget progress for Plan & Reports must match bit-for-bit using alias & hierarchy
    const budgets: SharedBudget[] = [
      {
        id: 'bud-food',
        categoryId: 'cat-food',
        monthIso: '2026-11',
        limitCents: 60000, // 600 ETB -> Over budget since rollup spend is 700 ETB
        rolloverEnabled: false,
        createdAt: '2026-11-01T00:00:00Z',
        updatedAt: '2026-11-01T00:00:00Z',
      },
      {
        id: 'bud-comm-legacy',
        categoryId: 'cat-communication', // Legacy alias budget ID
        monthIso: '2026-11',
        limitCents: 20000,
        rolloverEnabled: false,
        createdAt: '2026-11-01T00:00:00Z',
        updatedAt: '2026-11-01T00:00:00Z',
      },
    ];

    const budgetReport = buildMonthlyBudgetProgressReportV7({
      budgets,
      categories,
      entries,
      postings,
      accounts,
      monthIso: '2026-11',
    });

    const foodBudgetItem = budgetReport.items.find((i) => i.budgetId === 'bud-food')!;
    const commBudgetItem = budgetReport.items.find((i) => i.budgetId === 'bud-comm-legacy')!;
    assert.strictEqual(foodBudgetItem.spentCents, 70000);
    assert.strictEqual(foodBudgetItem.isOverBudget, true);
    assert.strictEqual(commBudgetItem.spentCents, 15000);
    assert.strictEqual(commBudgetItem.categoryName, 'Communication');

    // Exact match against FinancePlanTab helper
    assert.strictEqual(
      getCanonicalBudgetSpentCentsV7(spend, 'cat-food', categories),
      foodBudgetItem.spentCents
    );
    assert.strictEqual(
      getCanonicalBudgetSpentCentsV7(spend, 'cat-communication', categories),
      commBudgetItem.spentCents
    );

    const activeMonth = resolveActiveReportMonthIsoV7({
      mode: 'thisMonth',
      startDateIso: '2026-11-01',
      endDateIso: '2026-11-30',
      todayIso: '2026-12-05',
    });
    assert.strictEqual(activeMonth, '2026-11');
  });

  it('Workflow 4 & 5: Savings Vaults, Credit Card Option 1, Aligned Balance Sheet, and Strict USD/Unverified Currency Isolation', () => {
    const baseAccounts = makeBaseAccounts();
    const unverifiedAccount: Account = {
      id: 'acc-unv',
      name: 'Legacy Unverified Cash',
      type: 'asset',
      subType: 'cash',
      currencyCode: '',
      openingBalanceCents: 88000,
      openingBalanceDate: '2026-01-01',
      isArchived: false,
      createdAt: '2026-01-01T00:00:00Z',
    };
    const archivedAcc: Account = {
      id: 'acc-arch',
      name: 'Archived Bank',
      type: 'asset',
      subType: 'bank',
      currencyCode: 'ETB',
      openingBalanceCents: 0,
      isArchived: true,
      createdAt: '2026-01-01T00:00:00Z',
    };
    const accounts = [...baseAccounts, unverifiedAccount, archivedAcc];

    const party: Party = {
      id: 'party-abebe',
      name: 'Abebe',
      isArchived: false,
      createdAt: '2026-11-01T00:00:00Z',
    };
    const lend = buildLendMoney({
      entryId: 'e-lend',
      debtId: 'debt-rec-1',
      partyId: party.id,
      sourceAssetAccountId: 'acc-cbe',
      receivableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      amountCents: 200000,
      date: '2026-11-02',
      dueDate: '2026-11-25',
      description: 'Loan to Abebe',
    });
    const borrowInHorizon = buildBorrowMoney({
      entryId: 'e-borrow-1',
      debtId: 'debt-pay-in',
      partyId: party.id,
      destAssetAccountId: 'acc-cbe',
      payableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.payable,
      amountCents: 120000,
      date: '2026-11-03',
      dueDate: '2026-11-28',
      description: 'Short-term payable inside horizon',
    });
    const borrowAfterHorizon = buildBorrowMoney({
      entryId: 'e-borrow-2',
      debtId: 'debt-pay-out',
      partyId: party.id,
      destAssetAccountId: 'acc-cbe',
      payableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.payable,
      amountCents: 80000,
      date: '2026-11-04',
      dueDate: '2026-12-20',
      description: 'Long-term payable outside horizon',
    });
    // Excluded USD expense — must never pollute ETB balances or ETB reports
    const usdExpense = buildDirectExpense({
      id: 'e-usd-coffee',
      assetAccountId: 'acc-usd',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 500, // $5.00
      occurrenceDate: '2026-11-10',
      movementDate: '2026-11-10',
      description: 'USD Airport Snack',
    });

    const entries: JournalEntry[] = [
      lend.entry,
      borrowInHorizon.entry,
      borrowAfterHorizon.entry,
      usdExpense.entry,
    ];
    const postings: Posting[] = [
      ...lend.postings,
      ...borrowInHorizon.postings,
      ...borrowAfterHorizon.postings,
      ...usdExpense.postings,
    ];
    const debts: Debt[] = [lend.debt, borrowInHorizon.debt, borrowAfterHorizon.debt];

    const savingsGoals: SharedSavingsGoal[] = [
      {
        id: 'goal-vault',
        title: 'Down Payment Vault Goal',
        targetCents: 1000000,
        currentAllocatedCents: 50000, // Stale cache -> report must read live vault balance (300,000)
        linkedAccountId: 'acc-vault',
        status: 'active',
      },
      {
        id: 'goal-virtual',
        title: 'Holiday Virtual Earmark',
        targetCents: 200000,
        currentAllocatedCents: 100000,
        status: 'active',
      },
    ];

    const balances = buildAccountBalancesReportV7({ accounts, entries, postings });
    assert.strictEqual(balances.liquidTotalCents, 1000000); // CBE = 1000000 - 200000 + 120000 + 80000 = 1000000
    assert.strictEqual(balances.vaultTotalCents, 300000);
    assert.strictEqual(balances.prepaidCardCreditTotalCents, 25000);
    assert.strictEqual(balances.creditCardOwedTotalCents, 40000);
    assert.strictEqual(balances.archivedCount, 1);
    assert.strictEqual(balances.nonEtbReviewAccounts.length, 2); // USD & UNVERIFIED

    const savingsReport = buildSavingsVaultsAndGoalsReportV7({
      accounts,
      entries,
      postings,
      savingsGoals,
    });
    const vaultGoalRow = savingsReport.goals.find((g) => g.goalId === 'goal-vault')!;
    assert.strictEqual(vaultGoalRow.isVaultLinked, true);
    assert.strictEqual(vaultGoalRow.allocatedCents, 300000);
    assert.strictEqual(savingsReport.totalVaultBalanceCents, 300000);

    const breakdown = calculateAvailableToSpendBreakdownV7({
      accounts,
      postings,
      entries,
      debts,
      commitments: [],
      commitmentSettlements: [],
      savingsGoals,
      planningPeriodEndIso: '2026-11-30',
    });

    const bs = buildAlignedBalanceSheetReportV7({
      accounts,
      entries,
      postings,
      debts,
      breakdown,
    });
    assert.strictEqual(bs.liquidCashCents, 1000000);
    assert.strictEqual(bs.vaultSavingsCents, 300000);
    assert.strictEqual(bs.receivablesCents, 200000);
    assert.strictEqual(bs.prepaidCardCreditCents, 25000);
    assert.strictEqual(bs.shortTermCreditOwedCents, 40000);
    assert.strictEqual(bs.activePayablesCents, 200000); // Both payables total
    assert.strictEqual(bs.duePayablesCents, 120000); // Only <= 2026-11-30
    // Net Financial Position = (1000000 + 300000 + 200000 + 25000) - (40000 + 200000) = 1285000
    assert.strictEqual(bs.netFinancialPositionCents, 1285000);

    const integrity = verifyFinanceV7Integrity({
      accounts,
      entries,
      postings,
      debts,
      commitments: [],
      savingsGoals,
    });
    assert.strictEqual(integrity.nonEtbAccountCount, 2); // acc-usd + acc-unv
    assert.strictEqual(integrity.unverifiedAccountCount, 1);
    assert.strictEqual(integrity.excludedNonEtbEntryCount, 1);
    assert.strictEqual(
      calculateAccountBalance(
        accounts.find((a) => a.id === 'acc-usd')!,
        postings,
        undefined,
        entries
      ),
      149500
    );
  });

  it('Workflow 6: All 13 UTF-8 BOM CSVs (Amharic safe), 13-table SQLite .sql script, 7-sheet .xlsx, and SHA-256 ZIP bundle', async () => {
    const accounts = makeBaseAccounts();
    const categories: TransactionCategory[] = [
      ...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
      ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
      {
        id: 'cat-amharic-child',
        name: 'ምግብ / ቡና',
        type: 'expense',
        colorHex: '#EF4444',
        parentId: 'cat-food',
      },
    ];
    // Put child BEFORE parent intentionally to prove SQL topological sorting puts cat-food first
    const unorderedCategories: TransactionCategory[] = [
      categories[categories.length - 1],
      ...categories.slice(0, categories.length - 1),
    ];
    const parties: Party[] = [
      { id: 'party-1', name: 'ዳዊት', isArchived: false, createdAt: '2026-11-01T00:00:00Z' },
    ];
    const exp = buildDirectExpense({
      id: 'entry-export-1',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-amharic-child',
      amountCents: 12500,
      occurrenceDate: '2026-11-12',
      movementDate: '2026-11-12',
      description: 'ምግብ እና የቤት ኪራይ',
    });
    const commitments: SharedCommitment[] = [
      {
        id: 'cm-1',
        title: 'የቤት ኪራይ',
        amountCents: 500000,
        dueDate: '2026-11-30',
        isPaid: false,
        linkedAccountId: 'acc-cbe',
        categoryId: 'cat-housing',
        direction: 'outflow',
      },
    ];
    const commitmentSettlements: SharedCommitmentSettlement[] = [
      {
        id: 'cs-1',
        commitmentId: 'cm-1',
        entryId: exp.entry.id,
        amountCents: 12500,
        settledDate: '2026-11-12',
        createdAt: '2026-11-12T00:00:00Z',
      },
    ];
    const savingsGoals: SharedSavingsGoal[] = [
      {
        id: 'sg-1',
        title: 'Emergency Vault Goal',
        targetCents: 500000,
        currentAllocatedCents: 300000,
        linkedAccountId: 'acc-vault',
        status: 'active',
      },
    ];
    const budgets: SharedBudget[] = [
      {
        id: 'bud-1',
        categoryId: 'cat-food',
        monthIso: '2026-11',
        limitCents: 200000,
        rolloverEnabled: false,
        createdAt: '2026-11-01T00:00:00Z',
        updatedAt: '2026-11-01T00:00:00Z',
      },
    ];
    const recurringRules: SharedRecurringRule[] = [
      {
        id: 'rr-1',
        title: 'Monthly Rent',
        ruleType: 'commitment',
        amountCents: 500000,
        frequency: 'monthly',
        interval: 1,
        startDate: '2026-11-01',
        nextOccurrenceDate: '2026-12-01',
        accountId: 'acc-cbe',
        categoryId: 'cat-housing',
        isActive: true,
        autoPost: false,
        createdAt: '2026-11-01T00:00:00Z',
      },
    ];
    const transactions = [
      {
        id: 'tx-export-1',
        type: 'expense' as const,
        amountCents: 12500,
        accountId: 'acc-cbe',
        categoryId: 'cat-amharic-child',
        description: 'ምግብ እና የቤት ኪራይ',
        transactionDate: '2026-11-12',
        journalEntryId: exp.entry.id,
        isSuperseded: false,
        createdAt: '2026-11-12T00:00:00Z',
      },
    ];

    const payload: ExportDataPayload = {
      accounts,
      parties,
      entries: [exp.entry],
      postings: exp.postings,
      debts: [],
      settlementAllocations: [],
      categories: unorderedCategories,
      reservedSavingsCents: 0,
      commitments,
      commitmentSettlements,
      savingsGoals,
      budgets,
      recurringRules,
      transactions,
      planningPeriodEndIso: '2026-11-30',
    };

    const { blob, fileName } = await DataPortabilityService.createExportZipBundle(payload);
    assert.ok(fileName.startsWith('daywell_finance_export_') && fileName.endsWith('.zip'));

    const zip = await JSZip.loadAsync(await blob.arrayBuffer());
    const expectedCsvFiles = [
      'csv/accounts.csv',
      'csv/categories.csv',
      'csv/parties.csv',
      'csv/journal_entries.csv',
      'csv/postings.csv',
      'csv/debts.csv',
      'csv/settlement_allocations.csv',
      'csv/commitments.csv',
      'csv/commitment_settlements.csv',
      'csv/savings_goals.csv',
      'csv/budgets.csv',
      'csv/recurring_rules.csv',
      'csv/transactions.csv',
    ];
    for (const csvPath of expectedCsvFiles) {
      const content = await zip.file(csvPath)?.async('string');
      assert.ok(content && content.startsWith('\uFEFF'), `Expected UTF-8 BOM in ${csvPath}`);
    }
    const categoriesCsv = (await zip.file('csv/categories.csv')!.async('string'))!;
    assert.ok(categoriesCsv.includes('ምግብ / ቡና'));

    const sql = (await zip.file('sqlite/finance_export.sql')!.async('string'))!;
    const expectedTables = [
      'accounts',
      'parties',
      'journal_entries',
      'postings',
      'debts',
      'settlement_allocations',
      'categories',
      'commitments',
      'commitment_settlements',
      'savings_goals',
      'budgets',
      'recurring_rules',
      'transactions',
    ];
    for (const t of expectedTables) {
      assert.ok(sql.includes(`CREATE TABLE IF NOT EXISTS ${t}`), `Missing table DDL: ${t}`);
    }
    // Topological category insert verification: parent cat-food inserted BEFORE cat-amharic-child
    const parentPos = sql.indexOf("INSERT INTO categories (id, name, type, color_hex, parent_id, sort_order, is_default, is_archived) VALUES ('cat-food'");
    const childPos = sql.indexOf("INSERT INTO categories (id, name, type, color_hex, parent_id, sort_order, is_default, is_archived) VALUES ('cat-amharic-child'");
    assert.ok(parentPos > 0 && childPos > 0 && parentPos < childPos, 'Parent category must be inserted before child category in SQL');
    assert.ok(sql.includes('AND a.is_system = 0'));

    const xlsxBytes = await zip.file('excel/finance_workbook.xlsx')!.async('uint8array');
    const wb = XLSX.read(xlsxBytes, { type: 'array' });
    assert.deepStrictEqual(wb.SheetNames, [
      'Executive_Summary',
      'Accounts_and_Balances',
      'Cash_Flow_Ledger',
      'Occurrence_PnL',
      'Debts_and_Receivables',
      'Commitments_and_Goals',
      'Budgets_and_Recurring',
    ]);

    const manifestRaw = await zip.file('manifest.json')!.async('string');
    const manifest = JSON.parse(manifestRaw);
    assert.strictEqual(manifest.exportScope, 'finance_only');
    assert.strictEqual(Object.keys(manifest.fileChecksums).length, 15);
  });

  it('Workflow 7 & 8: Finance-only JSON exports 13 Finance tables cleanly, preserves all non-Finance modules on import, and rejects full backups & legacy regressions fail-closed', () => {
    withMockBrowserStorage((store) => {
      // Seed non-Finance modules that MUST survive untouched across Finance-only import
      const preservedTasks = [{ id: 'task-1', title: 'Preserve Task', status: 'in_progress', priority: 'high', subtasks: [], labels: [], isPinned: false, isMyDay: false, createdAt: '2026-11-01T00:00:00Z', updatedAt: '2026-11-01T00:00:00Z' }];
      const preservedNotes = [{ id: 'note-1', title: 'Preserve Note', body: 'Amharic ማስታወሻ', folder: 'general', tags: [], isPinned: true, isFavorite: false, isArchived: false, isTrashed: false, createdAt: '2026-11-01T00:00:00Z', updatedAt: '2026-11-01T00:00:00Z' }];
      const preservedProjects = [{ id: 'proj-1', title: 'Preserve Project', status: 'active', isArchived: false, createdAt: '2026-11-01T00:00:00Z' }];
      const preservedBlocks = [{ id: 'blk-1', projectId: 'proj-1', blockType: 'counter', title: 'Emails', sortOrder: 0, configJson: '{}', isArchived: false, createdAt: '2026-11-01T00:00:00Z', updatedAt: '2026-11-01T00:00:00Z' }];
      const preservedRecords = [{ id: 'rec-1', projectId: 'proj-1', blockId: 'blk-1', recordType: 'progress_log', deltaValue: 10, isCompleted: false, metadataJson: '{}', createdAt: '2026-11-01T00:00:00Z', updatedAt: '2026-11-01T00:00:00Z' }];
      const preservedMilestones = [{ id: 'ms-1', projectId: 'proj-1', title: 'Milestone 1', isCompleted: false, createdAt: '2026-11-01T00:00:00Z' }];
      const preservedGoals = [{ id: 'g-1', title: 'Life Goal', status: 'active', createdAt: '2026-11-01T00:00:00Z' }];
      const preservedInbox = [{ id: 'inb-1', rawText: 'Keep Inbox Item', category: 'idea', isProcessed: false, createdAt: '2026-11-01T00:00:00Z' }];
      const preservedEvents = [{ id: 'ev-1', title: 'Keep Event', dateIso: '2026-11-20', isAllDay: true, category: 'personal', colorHex: '#1B4D3E', hasReminder: false, createdAt: '2026-11-01T00:00:00Z', updatedAt: '2026-11-01T00:00:00Z' }];
      const preservedReminders = [{ id: 'rem-1', targetId: 'task-1', targetType: 'task', title: 'Keep Reminder', triggerTimeUtc: '2026-11-20T09:00:00Z', isActive: true, createdAt: '2026-11-01T00:00:00Z' }];
      const preservedSettings = [{ key: 'theme_mode', value: 'dark', updatedAt: '2026-11-01T00:00:00Z' }];

      const nonFinanceCanonical = {
        schemaVersion: 5,
        snapshotFormatVersion: 2,
        appVersion: '1.0.2+3',
        exportedAt: '2026-11-18T10:00:00+03:00',
        isFinanceSetupCompleted: false,
        openingBalanceCents: 0,
        accounts: [],
        categories: [...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES],
        transactions: [],
        commitments: [],
        commitmentSettlements: [],
        savingsGoals: [],
        budgets: [],
        recurringRules: [],
        tasks: preservedTasks,
        notes: preservedNotes,
        projects: preservedProjects,
        projectTrackingBlocks: preservedBlocks,
        projectTrackingRecords: preservedRecords,
        milestones: preservedMilestones,
        goals: preservedGoals,
        inboxItems: preservedInbox,
        calendarEvents: preservedEvents,
        reminders: preservedReminders,
        appSettings: preservedSettings,
      };
      store.set(SharedStateBridge.STORAGE_KEY, JSON.stringify(nonFinanceCanonical));
      store.set('daywell_tasks', JSON.stringify(preservedTasks));
      store.set('daywell_notes', JSON.stringify(preservedNotes));
      store.set(SharedStateBridge.PROJECTS_STORAGE_KEY, JSON.stringify(preservedProjects));
      store.set(SharedStateBridge.PROJECT_TRACKING_BLOCKS_STORAGE_KEY, JSON.stringify(preservedBlocks));
      store.set(SharedStateBridge.PROJECT_TRACKING_RECORDS_STORAGE_KEY, JSON.stringify(preservedRecords));
      store.set(SharedStateBridge.MILESTONES_STORAGE_KEY, JSON.stringify(preservedMilestones));
      store.set(SharedStateBridge.GOALS_STORAGE_KEY, JSON.stringify(preservedGoals));
      store.set(SharedStateBridge.INBOX_STORAGE_KEY, JSON.stringify(preservedInbox));
      store.set('daywell_calendar_events', JSON.stringify(preservedEvents));
      store.set(SharedStateBridge.REMINDERS_STORAGE_KEY, JSON.stringify(preservedReminders));
      store.set(SharedStateBridge.APP_SETTINGS_STORAGE_KEY, JSON.stringify(preservedSettings));

      // Export Finance-only JSON from another ledger state containing valid double-entry + USD isolation
      const accounts = makeBaseAccounts();
      const exp = buildDirectExpense({
        id: 'entry-imp-1',
        assetAccountId: 'acc-cbe',
        expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
        categoryId: CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID,
        amountCents: 35000,
        occurrenceDate: '2026-11-15',
        movementDate: '2026-11-15',
        description: 'Restored Ledger Expense',
      });
      const financeOnlyRaw = SharedStateBridge.exportFinanceOnlyJson({
        schemaVersion: 5,
        snapshotFormatVersion: 2,
        financeSchemaVersion: 7,
        appVersion: '1.0.2+3',
        exportedAt: '2026-11-18T11:00:00+03:00',
        isFinanceSetupCompleted: true,
        openingBalanceCents: 1000000,
        accounts: accounts as any,
        categories: [...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES] as any,
        parties: [],
        journalEntries: [exp.entry],
        postings: exp.postings,
        debts: [],
        settlementAllocations: [],
        transactions: [
          {
            id: 'tx-imp-1',
            type: 'expense',
            amountCents: 35000,
            accountId: 'acc-cbe',
            categoryId: CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID,
            description: 'Restored Ledger Expense',
            transactionDate: '2026-11-15',
            journalEntryId: exp.entry.id,
            isSuperseded: false,
            createdAt: '2026-11-15T00:00:00Z',
          } as any,
        ],
        commitments: [],
        commitmentSettlements: [],
        savingsGoals: [],
        budgets: [],
        recurringRules: [],
        tasks: preservedTasks as any,
        notes: preservedNotes as any,
        projects: preservedProjects as any,
        goals: preservedGoals as any,
        inboxItems: preservedInbox as any,
        calendarEvents: preservedEvents as any,
      });

      const parsedExport = JSON.parse(financeOnlyRaw);
      assert.strictEqual(parsedExport.financeOnly, true);
      assert.strictEqual(parsedExport.exportScope, 'finance_only');
      for (const nonFinKey of [
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
        assert.strictEqual(
          Object.prototype.hasOwnProperty.call(parsedExport, nonFinKey),
          false,
          `Finance-only export must omit ${nonFinKey}`
        );
      }

      // Import Finance-only JSON and verify non-Finance modules stay untouched
      const impResult = SharedStateBridge.importFinanceOnlyJson(financeOnlyRaw);
      assert.strictEqual(impResult.success, true);
      assert.strictEqual(impResult.state?.accounts.some((a) => a.id === 'acc-cbe'), true);
      assert.strictEqual(impResult.state?.accounts.some((a) => a.id === 'acc-usd'), true);
      assert.strictEqual(impResult.state?.journalEntries?.length, 1);

      const afterCanonical = JSON.parse(store.get(SharedStateBridge.STORAGE_KEY)!);
      assert.strictEqual(afterCanonical.tasks.length, 1);
      assert.strictEqual(afterCanonical.tasks[0].id, 'task-1');
      assert.strictEqual(afterCanonical.notes.length, 1);
      assert.strictEqual(afterCanonical.notes[0].id, 'note-1');
      assert.strictEqual(afterCanonical.projects.length, 1);
      assert.strictEqual(afterCanonical.projects[0].id, 'proj-1');
      assert.strictEqual(afterCanonical.projectTrackingBlocks.length, 1);
      assert.strictEqual(afterCanonical.projectTrackingRecords.length, 1);
      assert.strictEqual(afterCanonical.milestones.length, 1);
      assert.strictEqual(afterCanonical.goals.length, 1);
      assert.strictEqual(afterCanonical.inboxItems.length, 1);
      assert.strictEqual(afterCanonical.calendarEvents.length, 1);
      assert.strictEqual(afterCanonical.reminders.length, 1);
      assert.strictEqual(afterCanonical.appSettings.length, 1);
      // Verify raw per-module localStorage keys were never overwritten or deleted
      assert.deepStrictEqual(JSON.parse(store.get('daywell_tasks')!), preservedTasks);
      assert.deepStrictEqual(JSON.parse(store.get('daywell_notes')!), preservedNotes);
      assert.deepStrictEqual(JSON.parse(store.get(SharedStateBridge.PROJECTS_STORAGE_KEY)!), preservedProjects);
      assert.deepStrictEqual(JSON.parse(store.get(SharedStateBridge.PROJECT_TRACKING_BLOCKS_STORAGE_KEY)!), preservedBlocks);
      assert.deepStrictEqual(JSON.parse(store.get(SharedStateBridge.PROJECT_TRACKING_RECORDS_STORAGE_KEY)!), preservedRecords);
      assert.deepStrictEqual(JSON.parse(store.get(SharedStateBridge.MILESTONES_STORAGE_KEY)!), preservedMilestones);
      assert.deepStrictEqual(JSON.parse(store.get(SharedStateBridge.GOALS_STORAGE_KEY)!), preservedGoals);
      assert.deepStrictEqual(JSON.parse(store.get(SharedStateBridge.INBOX_STORAGE_KEY)!), preservedInbox);
      assert.deepStrictEqual(JSON.parse(store.get('daywell_calendar_events')!), preservedEvents);
      assert.deepStrictEqual(JSON.parse(store.get(SharedStateBridge.REMINDERS_STORAGE_KEY)!), preservedReminders);
      assert.deepStrictEqual(JSON.parse(store.get(SharedStateBridge.APP_SETTINGS_STORAGE_KEY)!), preservedSettings);

      // Rejection 1: Full cross-module backup rejected with actionable Settings guidance
      const fullBackupJson = SharedStateBridge.exportToAndroidJson();
      const rejectFull = SharedStateBridge.importFinanceOnlyJson(fullBackupJson);
      assert.strictEqual(rejectFull.success, false);
      assert.match(rejectFull.error || '', /Settings/i);

      // Rejection 2: Finance-only payload poisoned with forbidden non-Finance key rejected
      const poisoned = JSON.stringify({ ...parsedExport, tasks: [] });
      const rejectPoison = SharedStateBridge.importFinanceOnlyJson(poisoned);
      assert.strictEqual(rejectPoison.success, false);
      assert.match(rejectPoison.error || '', /tasks/);

      // Rejection 3: Unsupported future version rejected without touching live store
      const futureVer = JSON.stringify({ ...parsedExport, schemaVersion: 99 });
      const rejectFuture = SharedStateBridge.importFinanceOnlyJson(futureVer);
      assert.strictEqual(rejectFuture.success, false);
      assert.strictEqual(rejectFuture.errorKind, 'unsupported_future_schema');

      // Rejection 4: Unbalanced journal entry rejected fail-closed
      const unbalanced = JSON.stringify({
        ...parsedExport,
        postings: [exp.postings[0]], // Missing balancing leg
      });
      const rejectUnbalanced = SharedStateBridge.importFinanceOnlyJson(unbalanced);
      assert.strictEqual(rejectUnbalanced.success, false);

      // Ensure live store still contains restored Finance data intact after failed imports
      const stillIntact = JSON.parse(store.get('daywell_finance_transactions')!);
      assert.strictEqual(stillIntact.length, 1);
      assert.strictEqual(stillIntact[0].id, 'tx-imp-1');

      // Workflow 8: Backward compatibility — legacy formatVersion 1 / schemaVersion 4 Finance-only import succeeds cleanly
      const legacyCompatPayload = JSON.stringify({
        financeOnly: true,
        schemaVersion: 4,
        isFinanceSetupCompleted: true,
        openingBalanceCents: 100000,
        accounts: [
          {
            id: 'acc-legacy-etb',
            name: 'Legacy ETB Bank',
            type: 'asset',
            subType: 'bank',
            currencyCode: 'ETB',
            openingBalanceCents: 100000,
            isArchived: false,
            createdAt: '2025-01-01T00:00:00Z',
          },
        ],
        categories: [{ id: 'cat-other-exp', name: 'Other', type: 'expense', colorHex: '#94A3B8', isDefault: true }],
        transactions: [],
      });
      const legacyImport = SharedStateBridge.importFinanceOnlyJson(legacyCompatPayload);
      assert.strictEqual(legacyImport.success, true);
      assert.strictEqual(legacyImport.state?.accounts.some((a) => a.id === 'acc-legacy-etb'), true);
    });
  });
});
