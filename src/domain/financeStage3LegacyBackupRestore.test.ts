import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import {
  Account,
  classifyAllJournalEntries,
  Debt,
  DEFAULT_EXPENSE_CATEGORIES,
  generateCashFlowReport,
  generateOccurrenceReport,
  JournalEntry,
  Party,
  Posting,
  SettlementAllocation,
  SimpleTransaction,
  TransactionCategory,
} from './doubleEntryFinance';
import {
  buildAccountBalancesReportV7,
  buildAlignedBalanceSheetReportV7,
  buildDirectExpense,
  buildDirectIncome,
  buildMonthlyBudgetProgressReportV7,
  buildSavingsVaultsAndGoalsReportV7,
  calculateAvailableToSpendBreakdownV7,
  calculateCanonicalCategorySpendV7,
  canCorrectJournalEntryV7,
  correctJournalEntryV7,
  FOUNDATION_DEFAULT_INCOME_CATEGORIES,
  fundSavingsGoalV7,
  getExpenseRefundSummaryV7,
  hydrateLedgerFromSimpleTransactions,
  processDueRecurringRulesV7,
  recordCommitmentSettlementV7,
  SharedBudget,
  SharedCommitment,
  SharedCommitmentSettlement,
  SharedRecurringRule,
  SharedSavingsGoal,
  unvoidJournalEntryGuardedV7,
  verifyFinanceV7Integrity,
  voidJournalEntryGuardedV7,
} from './financeV7Engine';
import { SYSTEM_CONTROL_ACCOUNT_IDS } from './sharedFoundation';
import { SharedStateBridge } from '../services/sharedStateBridge';
import {
  decryptDatabaseBackup,
  encryptDatabaseBackup,
  LocalDatabaseState,
} from './backupCrypto';
import { FinanceOverviewTab } from '../components/finance/FinanceOverviewTab';
import { FinanceTransactionsTab } from '../components/finance/FinanceTransactionsTab';
import { FinancePlanTab } from '../components/finance/FinancePlanTab';
import { FinanceReportsTab } from '../components/finance/FinanceReportsTab';

function withMockBrowserStorage(
  fn: (store: Map<string, string>) => Promise<void> | void
): Promise<void> | void {
  const store = new Map<string, string>();
  const prevWindow = (globalThis as any).window;
  const prevLocalStorage = (globalThis as any).localStorage;

  const mockStorage = {
    getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
    setItem: (k: string, v: string) => void store.set(k, String(v)),
    removeItem: (k: string) => void store.delete(k),
    clear: () => void store.clear(),
    key: (idx: number) => Array.from(store.keys())[idx] ?? null,
    get length() {
      return store.size;
    },
  };

  (globalThis as any).localStorage = mockStorage;
  (globalThis as any).window = {
    dispatchEvent: () => true,
    CustomEvent: class CustomEvent {
      type: string;
      detail: unknown;
      constructor(type: string, init?: { detail?: unknown }) {
        this.type = type;
        this.detail = init?.detail;
      }
    },
  };

  const cleanup = () => {
    (globalThis as any).window = prevWindow;
    (globalThis as any).localStorage = prevLocalStorage;
  };

  try {
    const result = fn(store);
    if (result && typeof (result as Promise<void>).then === 'function') {
      return (result as Promise<void>).finally(cleanup);
    }
    cleanup();
  } catch (err) {
    cleanup();
    throw err;
  }
}

function makeSystemAccounts(): Account[] {
  return [
    {
      id: SYSTEM_CONTROL_ACCOUNT_IDS.equity,
      name: 'Opening Balance Equity',
      type: 'equity',
      subType: 'opening_equity',
      currencyCode: 'ETB',
      isSystem: true,
      isArchived: false,
      createdAt: '2026-10-01T00:00:00.000Z',
    },
    {
      id: SYSTEM_CONTROL_ACCOUNT_IDS.income,
      name: 'Income Control',
      type: 'income',
      subType: 'nominal_income',
      currencyCode: 'ETB',
      isSystem: true,
      isArchived: false,
      createdAt: '2026-10-01T00:00:00.000Z',
    },
    {
      id: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      name: 'Expense Control',
      type: 'expense',
      subType: 'nominal_expense',
      currencyCode: 'ETB',
      isSystem: true,
      isArchived: false,
      createdAt: '2026-10-01T00:00:00.000Z',
    },
    {
      id: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      name: 'Receivable Control',
      type: 'asset',
      subType: 'receivable',
      currencyCode: 'ETB',
      isSystem: true,
      isArchived: false,
      createdAt: '2026-10-01T00:00:00.000Z',
    },
    {
      id: SYSTEM_CONTROL_ACCOUNT_IDS.payable,
      name: 'Payable Control',
      type: 'liability',
      subType: 'payable',
      currencyCode: 'ETB',
      isSystem: true,
      isArchived: false,
      createdAt: '2026-10-01T00:00:00.000Z',
    },
  ];
}

function buildMixedLegacyDataset() {
  const accounts: Account[] = [
    ...makeSystemAccounts(),
    {
      id: 'acc-etb-cbe',
      name: 'CBE Checking',
      type: 'asset',
      subType: 'bank',
      currencyCode: 'ETB',
      openingBalanceCents: 250000, // 2,500.00 ETB
      openingBalanceDate: '2026-11-01',
      isArchived: false,
      createdAt: '2026-11-01T00:00:00.000Z',
    },
    {
      id: 'acc-etb-vault',
      name: 'ETB Savings Vault',
      type: 'asset',
      subType: 'savings_vault',
      currencyCode: 'ETB',
      openingBalanceCents: 100000, // 1,000.00 ETB
      openingBalanceDate: '2026-11-01',
      isArchived: false,
      createdAt: '2026-11-01T00:00:00.000Z',
    },
    {
      id: 'acc-etb-card',
      name: 'ETB Credit Card',
      type: 'liability',
      subType: 'credit_card',
      currencyCode: 'ETB',
      openingBalanceCents: 20000, // 200.00 ETB credit card balance owed
      openingBalanceDate: '2026-11-01',
      isArchived: false,
      createdAt: '2026-11-01T00:00:00.000Z',
    },
    {
      id: 'acc-usd-bank',
      name: 'USD Travel Account',
      type: 'asset',
      subType: 'bank',
      currencyCode: 'USD',
      openingBalanceCents: 100000, // 1,000.00 USD
      openingBalanceDate: '2026-10-01',
      isArchived: false,
      createdAt: '2026-10-01T00:00:00.000Z',
    },
    {
      id: 'acc-usd-vault',
      name: 'USD Reserve Vault',
      type: 'asset',
      subType: 'savings_vault',
      currencyCode: 'USD',
      openingBalanceCents: 40000, // 400.00 USD
      openingBalanceDate: '2026-10-01',
      isArchived: false,
      createdAt: '2026-10-01T00:00:00.000Z',
    },
    {
      id: 'acc-eur-cash',
      name: 'EUR Envelope',
      type: 'asset',
      subType: 'cash',
      currencyCode: 'EUR',
      openingBalanceCents: 60000, // 600.00 EUR
      openingBalanceDate: '2026-10-01',
      isArchived: false,
      createdAt: '2026-10-01T00:00:00.000Z',
    },
    {
      id: 'acc-unclassified',
      name: 'Old Unclassified Pouch',
      type: 'asset',
      subType: 'cash',
      currencyCode: '',
      openingBalanceCents: 50000,
      openingBalanceDate: '2026-10-01',
      isArchived: false,
      createdAt: '2026-10-01T00:00:00.000Z',
    },
  ];

  const categories = [
    ...DEFAULT_EXPENSE_CATEGORIES,
    ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
  ];

  const parties: Party[] = [
    {
      id: 'party-usd-1',
      name: 'Abebe Overseas',
      phone: '+251911000001',
      notes: 'Preserved party note',
      isArchived: false,
      createdAt: '2026-10-01T00:00:00.000Z',
    },
  ];

  // Ordinary ETB activity:
  // Expense 30,000 + 500 fee = -30,500; Refund +10,000; Income +80,000 -> CBE = 309,500
  const etbExp = buildDirectExpense({
    id: 'je-etb-exp',
    assetAccountId: 'acc-etb-cbe',
    expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
    categoryId: 'cat-food',
    amountCents: 30000,
    feeCents: 500,
    feeExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
    feeCategoryId: 'cat-fees',
    occurrenceDate: '2026-11-10',
    movementDate: '2026-11-10',
    description: 'ETB Groceries',
  });

  const etbRefundEntry: JournalEntry = {
    id: 'je-etb-refund',
    entryType: 'standard',
    description: 'Refund: ETB Groceries',
    occurrenceDate: '2026-11-12',
    isVoided: false,
    correctedFromEntryId: 'je-etb-exp',
    createdAt: '2026-11-12T08:00:00.000Z',
  };
  const etbRefundPostings: Posting[] = [
    {
      id: 'post-etb-ref-dr',
      entryId: 'je-etb-refund',
      accountId: 'acc-etb-cbe',
      amountCents: 10000,
      direction: 'debit',
      accountMovementDate: '2026-11-12',
    },
    {
      id: 'post-etb-ref-cr',
      entryId: 'je-etb-refund',
      accountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      amountCents: 10000,
      direction: 'credit',
      accountMovementDate: '2026-11-12',
      categoryId: 'cat-food',
    },
  ];

  const etbInc = buildDirectIncome({
    id: 'je-etb-inc',
    assetAccountId: 'acc-etb-cbe',
    incomeAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.income,
    categoryId: 'cat-salary',
    amountCents: 80000,
    occurrenceDate: '2026-11-14',
    movementDate: '2026-11-14',
    description: 'November ETB Stipend',
  });

  // Historical USD expense with preserved historical posting.note
  const usdExp = buildDirectExpense({
    id: 'je-usd-exp',
    assetAccountId: 'acc-usd-bank',
    expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
    categoryId: 'cat-food',
    amountCents: 15000,
    occurrenceDate: '2026-10-15',
    movementDate: '2026-10-15',
    description: 'Airport Hotel USD',
    note: 'Historical USD lodging note',
  });

  // Historical voided + superseded USD correction chain
  const usdVoidedEntry: JournalEntry = {
    id: 'je-usd-voided',
    entryType: 'standard',
    description: 'Voided USD Shuttle',
    occurrenceDate: '2026-10-16',
    isVoided: true,
    voidReason: 'Duplicate charge',
    createdAt: '2026-10-16T09:00:00.000Z',
  };
  const usdVoidedPostings: Posting[] = [
    {
      id: 'post-usd-v-dr',
      entryId: 'je-usd-voided',
      accountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      amountCents: 2500,
      direction: 'debit',
      accountMovementDate: '2026-10-16',
      categoryId: 'cat-transport',
      note: 'Should stay preserved on voided chain',
    },
    {
      id: 'post-usd-v-cr',
      entryId: 'je-usd-voided',
      accountId: 'acc-usd-bank',
      amountCents: 2500,
      direction: 'credit',
      accountMovementDate: '2026-10-16',
    },
  ];

  const usdCorrectedEntry: JournalEntry = {
    id: 'je-usd-corrected',
    entryType: 'standard',
    description: 'Corrected USD Shuttle',
    occurrenceDate: '2026-10-16',
    isVoided: false,
    correctedFromEntryId: 'je-usd-voided',
    createdAt: '2026-10-16T09:05:00.000Z',
  };
  const usdCorrectedPostings: Posting[] = [
    {
      id: 'post-usd-c-dr',
      entryId: 'je-usd-corrected',
      accountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      amountCents: 2000,
      direction: 'debit',
      accountMovementDate: '2026-10-16',
      categoryId: 'cat-transport',
    },
    {
      id: 'post-usd-c-cr',
      entryId: 'je-usd-corrected',
      accountId: 'acc-usd-bank',
      amountCents: 2000,
      direction: 'credit',
      accountMovementDate: '2026-10-16',
    },
  ];

  // Historical USD receivable debt + partial settlement allocation
  const usdDebtOrigin: JournalEntry = {
    id: 'je-usd-debt-origin',
    entryType: 'debt_issuance',
    description: 'USD Loan to Abebe',
    occurrenceDate: '2026-10-18',
    isVoided: false,
    createdAt: '2026-10-18T10:00:00.000Z',
  };
  const usdDebtOriginPostings: Posting[] = [
    {
      id: 'post-usd-do-dr',
      entryId: 'je-usd-debt-origin',
      accountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      amountCents: 30000,
      direction: 'debit',
      accountMovementDate: '2026-10-18',
    },
    {
      id: 'post-usd-do-cr',
      entryId: 'je-usd-debt-origin',
      accountId: 'acc-usd-bank',
      amountCents: 30000,
      direction: 'credit',
      accountMovementDate: '2026-10-18',
    },
  ];

  const usdDebtSettle: JournalEntry = {
    id: 'je-usd-debt-settle',
    entryType: 'settlement',
    description: 'Partial USD Repayment',
    occurrenceDate: '2026-10-20',
    isVoided: false,
    createdAt: '2026-10-20T10:00:00.000Z',
  };
  const usdDebtSettlePostings: Posting[] = [
    {
      id: 'post-usd-ds-dr',
      entryId: 'je-usd-debt-settle',
      accountId: 'acc-usd-bank',
      amountCents: 10000,
      direction: 'debit',
      accountMovementDate: '2026-10-20',
    },
    {
      id: 'post-usd-ds-cr',
      entryId: 'je-usd-debt-settle',
      accountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      amountCents: 10000,
      direction: 'credit',
      accountMovementDate: '2026-10-20',
    },
  ];

  const debts: Debt[] = [
    {
      id: 'debt-usd-1',
      originEntryId: 'je-usd-debt-origin',
      partyId: 'party-usd-1',
      debtType: 'receivable',
      principalCents: 30000,
      outstandingCents: 20000,
      dueDate: '2026-12-01',
      status: 'active',
      createdAt: '2026-10-18T10:00:00.000Z',
    },
  ];

  const allocations: SettlementAllocation[] = [
    {
      id: 'alloc-usd-1',
      settlementEntryId: 'je-usd-debt-settle',
      debtId: 'debt-usd-1',
      allocatedCents: 10000,
      settlementDate: '2026-10-20',
    },
  ];

  // Historical EUR commitment settlement entry
  const eurSettleEntry: JournalEntry = {
    id: 'je-eur-com-settle',
    entryType: 'standard',
    description: 'Paid EUR Visa Bill',
    occurrenceDate: '2026-10-21',
    isVoided: false,
    createdAt: '2026-10-21T10:00:00.000Z',
  };
  const eurSettlePostings: Posting[] = [
    {
      id: 'post-eur-cs-dr',
      entryId: 'je-eur-com-settle',
      accountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      amountCents: 12000,
      direction: 'debit',
      accountMovementDate: '2026-10-21',
      categoryId: 'cat-other-exp',
    },
    {
      id: 'post-eur-cs-cr',
      entryId: 'je-eur-com-settle',
      accountId: 'acc-eur-cash',
      amountCents: 12000,
      direction: 'credit',
      accountMovementDate: '2026-10-21',
    },
  ];

  // Historical Unclassified ("") entry
  const unclassifiedExp = buildDirectExpense({
    id: 'je-unclassified-exp',
    assetAccountId: 'acc-unclassified',
    expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
    categoryId: 'cat-other-exp',
    amountCents: 7500,
    occurrenceDate: '2026-10-22',
    movementDate: '2026-10-22',
    description: 'Legacy Unclassified Expense',
    note: 'Historical pouch note',
  });

  const commitments: SharedCommitment[] = [
    {
      id: 'com-etb-due',
      title: 'ETB Utility Bill',
      amountCents: 25000,
      dueDate: '2026-11-28',
      isPaid: false,
      linkedAccountId: 'acc-etb-cbe',
      categoryId: 'cat-utilities',
      direction: 'outflow',
    },
    {
      id: 'com-eur-due',
      title: 'EUR Roaming Invoice',
      amountCents: 8500,
      dueDate: '2026-11-25',
      isPaid: false,
      linkedAccountId: 'acc-eur-cash',
      categoryId: 'cat-comm',
      direction: 'outflow',
    },
    {
      id: 'com-eur-paid',
      title: 'EUR Hotel Deposit',
      amountCents: 12000,
      dueDate: '2026-10-21',
      isPaid: true,
      linkedAccountId: 'acc-eur-cash',
      categoryId: 'cat-other-exp',
      settlementEntryId: 'je-eur-com-settle',
      direction: 'outflow',
    },
  ];

  const commitmentSettlements: SharedCommitmentSettlement[] = [
    {
      id: 'cs-eur-1',
      commitmentId: 'com-eur-paid',
      entryId: 'je-eur-com-settle',
      amountCents: 12000,
      settledDate: '2026-10-21',
      createdAt: '2026-10-21T10:00:00.000Z',
    },
  ];

  const savingsGoals: SharedSavingsGoal[] = [
    {
      id: 'goal-etb-vault',
      title: 'ETB Emergency Fund',
      targetCents: 500000,
      currentAllocatedCents: 100000,
      linkedAccountId: 'acc-etb-vault',
      status: 'active',
    },
    {
      id: 'goal-usd-legacy',
      title: 'Legacy USD Travel Fund',
      targetCents: 100000,
      currentAllocatedCents: 40000,
      linkedAccountId: 'acc-usd-vault',
      status: 'active',
    },
  ];

  const budgets: SharedBudget[] = [
    {
      id: 'bud-etb-food-2026-11',
      categoryId: 'cat-food',
      monthIso: '2026-11',
      limitCents: 50000,
      rolloverEnabled: false,
      createdAt: '2026-11-01T00:00:00.000Z',
      updatedAt: '2026-11-01T00:00:00.000Z',
    },
  ];

  const recurringRules: SharedRecurringRule[] = [
    {
      id: 'rule-usd-legacy',
      title: 'Legacy USD Cloud Sub',
      ruleType: 'expense',
      amountCents: 2000,
      frequency: 'monthly',
      interval: 1,
      startDate: '2026-10-01',
      nextOccurrenceDate: '2026-12-01',
      accountId: 'acc-usd-bank',
      categoryId: 'cat-comm',
      isActive: true,
      autoPost: true,
      createdAt: '2026-10-01T00:00:00.000Z',
    },
  ];

  const entries: JournalEntry[] = [
    etbExp.entry,
    etbRefundEntry,
    etbInc.entry,
    usdExp.entry,
    usdVoidedEntry,
    usdCorrectedEntry,
    usdDebtOrigin,
    usdDebtSettle,
    eurSettleEntry,
    unclassifiedExp.entry,
  ];

  const postings: Posting[] = [
    ...etbExp.postings,
    ...etbRefundPostings,
    ...etbInc.postings,
    ...usdExp.postings,
    ...usdVoidedPostings,
    ...usdCorrectedPostings,
    ...usdDebtOriginPostings,
    ...usdDebtSettlePostings,
    ...eurSettlePostings,
    ...unclassifiedExp.postings,
  ];

  const transactions: SimpleTransaction[] = [
    {
      id: 'tx-usd-legacy-hist',
      type: 'expense',
      amountCents: 15000,
      accountId: 'acc-usd-bank',
      categoryId: 'cat-food',
      description: 'Airport Hotel USD',
      transactionDate: '2026-10-15',
      createdAt: '2026-10-15T10:00:00.000Z',
      journalEntryId: 'je-usd-exp',
    },
  ];

  return {
    accounts,
    categories,
    parties,
    entries,
    postings,
    debts,
    allocations,
    commitments,
    commitmentSettlements,
    savingsGoals,
    budgets,
    recurringRules,
    transactions,
  };
}

function seedMixedDatasetIntoBrowserStorage(
  store: Map<string, string>,
  dataset: ReturnType<typeof buildMixedLegacyDataset>,
  dismissLegacyNotice = true
) {
  store.set('daywell_finance_setup_completed', 'true');
  store.set('daywell_accounts', JSON.stringify(dataset.accounts));
  store.set('daywell_categories', JSON.stringify(dataset.categories));
  store.set('daywell_parties', JSON.stringify(dataset.parties));
  store.set('daywell_journal_entries', JSON.stringify(dataset.entries));
  store.set('daywell_postings', JSON.stringify(dataset.postings));
  store.set('daywell_debts', JSON.stringify(dataset.debts));
  store.set('daywell_settlement_allocations', JSON.stringify(dataset.allocations));
  store.set('daywell_commitments', JSON.stringify(dataset.commitments));
  store.set(
    'daywell_commitment_settlements',
    JSON.stringify(dataset.commitmentSettlements)
  );
  store.set('daywell_savings_goals', JSON.stringify(dataset.savingsGoals));
  store.set('daywell_budgets', JSON.stringify(dataset.budgets));
  store.set('daywell_recurring_rules', JSON.stringify(dataset.recurringRules));
  store.set('daywell_finance_transactions', JSON.stringify(dataset.transactions));
  store.set(
    'daywell_tasks',
    JSON.stringify([
      {
        id: 'task-keep-1',
        title: 'Keep existing task across Finance-only restore',
        status: 'not_started',
        priority: 'medium',
        createdAt: '2026-11-01T00:00:00.000Z',
        updatedAt: '2026-11-01T00:00:00.000Z',
      },
    ])
  );
  store.set(
    'daywell_notes',
    JSON.stringify([
      {
        id: 'note-keep-1',
        title: 'Keep existing note across Finance-only restore',
        content: 'Personal note content must survive Finance restore',
        category: 'general',
        createdAt: '2026-11-01T00:00:00.000Z',
        updatedAt: '2026-11-01T00:00:00.000Z',
      },
    ])
  );
  if (dismissLegacyNotice) {
    store.set(SharedStateBridge.LEGACY_NON_ETB_NOTICE_DISMISSED_SETTING_KEY, 'true');
  }
}

function normalizeRestoredFinanceState(
  raw: ReturnType<typeof SharedStateBridge.assembleLiveDatabaseState>
) {
  return {
    ...raw,
    accounts: (raw.accounts || []) as unknown as Account[],
    categories: (raw.categories || []) as unknown as TransactionCategory[],
    parties: (raw.parties || []) as Party[],
    journalEntries: (raw.journalEntries || []) as JournalEntry[],
    postings: (raw.postings || []) as Posting[],
    debts: (raw.debts || []) as Debt[],
    settlementAllocations: (raw.settlementAllocations || []) as SettlementAllocation[],
    commitments: (raw.commitments || []) as SharedCommitment[],
    commitmentSettlements: (raw.commitmentSettlements || []) as SharedCommitmentSettlement[],
    savingsGoals: (raw.savingsGoals || []) as SharedSavingsGoal[],
    budgets: (raw.budgets || []) as SharedBudget[],
    recurringRules: (raw.recurringRules || []) as SharedRecurringRule[],
    transactions: (raw.transactions || []) as unknown as SimpleTransaction[],
  };
}

describe('Finance Stage 3 Follow-Up — Legacy Currency Backup & Restore Verification (Web)', () => {
  it('Points 1-5: Full & encrypted backup export/restore preserves historical USD, EUR, and unclassified records read-only without perturbing ETB balances', async () => {
    await withMockBrowserStorage(async (store) => {
      const dataset = buildMixedLegacyDataset();
      seedMixedDatasetIntoBrowserStorage(store, dataset, true);

      // Compute pre-export authoritative ETB expectations
      const preBreakdown = calculateAvailableToSpendBreakdownV7({
        accounts: dataset.accounts,
        entries: dataset.entries,
        postings: dataset.postings,
        debts: dataset.debts,
        commitments: dataset.commitments,
        commitmentSettlements: dataset.commitmentSettlements,
        savingsGoals: dataset.savingsGoals,
        recurringRules: dataset.recurringRules,
        planningPeriodEndIso: '2026-11-30',
      });
      // ETB CBE = 250,000 - 30,500 + 10,000 + 80,000 = 309,500
      // ETB Card = 20,000 owed; ETB Vault = 100,000; ETB due obligation = 25,000
      // Available to spend = 309,500 - 20,000 - 25,000 = 264,500
      assert.equal(preBreakdown.liquidCashCents, 309500);
      assert.equal(preBreakdown.shortTermCreditOwedCents, 20000);
      assert.equal(preBreakdown.prepaidCardCreditCents, 0);
      assert.equal(preBreakdown.vaultSavingsCents, 100000);
      assert.equal(preBreakdown.dueNonDebtCommitmentsCents, 25000);
      assert.equal(preBreakdown.availableToSpendCents, 264500);
      assert.equal(preBreakdown.nonEtbAccountCount, 4); // 3 verified (USD bank, USD vault, EUR envelope) + 1 unverified
      assert.equal(preBreakdown.unverifiedAccountCount, 1); // unclassified pouch

      // Point 1 & 2: Export canonical full JSON + Finance-only JSON
      const fullBackupJson = SharedStateBridge.exportToAndroidJson();
      const fullParsed = JSON.parse(fullBackupJson);

      assert.equal(fullParsed.accounts.find((a: any) => a.id === 'acc-usd-bank')?.currencyCode, 'USD');
      assert.equal(fullParsed.accounts.find((a: any) => a.id === 'acc-usd-bank')?.openingBalanceCents, 100000);
      assert.equal(fullParsed.accounts.find((a: any) => a.id === 'acc-usd-vault')?.currencyCode, 'USD');
      assert.equal(fullParsed.accounts.find((a: any) => a.id === 'acc-usd-vault')?.openingBalanceCents, 40000);
      assert.equal(fullParsed.accounts.find((a: any) => a.id === 'acc-eur-cash')?.currencyCode, 'EUR');
      assert.equal(fullParsed.accounts.find((a: any) => a.id === 'acc-eur-cash')?.openingBalanceCents, 60000);
      assert.equal(fullParsed.accounts.find((a: any) => a.id === 'acc-unclassified')?.currencyCode, '');
      assert.equal(fullParsed.accounts.find((a: any) => a.id === 'acc-unclassified')?.openingBalanceCents, 50000);

      // Historical relationships & notes remain intact
      const exportedUsdPost = fullParsed.postings.find((p: any) => p.entryId === 'je-usd-exp' && p.direction === 'debit');
      assert.equal(exportedUsdPost?.note, 'Historical USD lodging note');
      assert.equal(
        fullParsed.journalEntries.find((e: any) => e.id === 'je-usd-corrected')?.correctedFromEntryId,
        'je-usd-voided'
      );
      assert.equal(
        fullParsed.journalEntries.find((e: any) => e.id === 'je-usd-voided')?.voidReason,
        'Duplicate charge'
      );
      assert.equal(fullParsed.debts[0].id, 'debt-usd-1');
      assert.equal(fullParsed.debts[0].originEntryId, 'je-usd-debt-origin');
      assert.equal(fullParsed.debts[0].outstandingCents, 20000);
      assert.equal(fullParsed.settlementAllocations[0].debtId, 'debt-usd-1');
      assert.equal(fullParsed.commitmentSettlements[0].commitmentId, 'com-eur-paid');
      assert.equal(fullParsed.savingsGoals.find((g: any) => g.id === 'goal-usd-legacy')?.linkedAccountId, 'acc-usd-vault');
      assert.equal(fullParsed.recurringRules[0].accountId, 'acc-usd-bank');
      assert.equal(
        fullParsed.appSettings.find(
          (s: any) => s.key === SharedStateBridge.LEGACY_NON_ETB_NOTICE_DISMISSED_SETTING_KEY
        )?.value,
        'true'
      );

      // Finance-only export omits appSettings intentionally
      const financeOnlyJson = SharedStateBridge.exportFinanceOnlyJson();
      const financeOnlyParsed = JSON.parse(financeOnlyJson);
      assert.equal(financeOnlyParsed.appSettings, undefined);
      assert.equal(
        financeOnlyParsed.accounts.find((a: any) => a.id === 'acc-eur-cash')?.openingBalanceCents,
        60000
      );

      // Encrypted .daywell Web local envelope v3 preserves historical foreign-currency transaction note & amounts
      const localDbV3: LocalDatabaseState = {
        version: 3,
        inbox: [],
        goals: [],
        projects: [],
        milestones: [],
        tasks: [],
        categories: [
          { id: 'cat-food', name: 'Food', type: 'expense', colorHex: '#EF4444', isDefault: true },
        ],
        transactions: [
          {
            id: 'legacy-v3-usd',
            categoryId: 'cat-food',
            amountCents: 15000,
            type: 'expense',
            transactionDateUtc: '2026-10-15T10:00:00.000Z',
            note: 'Historical USD v3 note',
            payee: 'Airport Hotel USD',
            createdAtUtc: '2026-10-15T10:00:00.000Z',
          },
        ],
        commitments: [],
        savingsGoals: [],
        notes: [],
        reminders: [],
        backupLogs: [],
        openingBalanceCents: 250000,
        incomesCents: [80000],
        expensesCents: [30500],
        savingsAllocationsCents: [100000],
        budgetPeriod: 'current_month',
        lastSavedUtc: '2026-11-15T00:00:00.000Z',
      };
      const encryptedDaywell = await encryptDatabaseBackup(localDbV3, 'DaywellLegacy#2026');
      const decryptedDaywell = await decryptDatabaseBackup(encryptedDaywell, 'DaywellLegacy#2026');
      assert.equal(decryptedDaywell.state.transactions[0].amountCents, 15000);
      assert.equal(decryptedDaywell.state.transactions[0].note, 'Historical USD v3 note');

      // Point 3: Wipe browser storage completely, then restore canonical full backup
      store.clear();
      const fullImportRes = SharedStateBridge.importFromAndroidJson(fullBackupJson);
      assert.equal(fullImportRes.success, true, fullImportRes.error);
      assert.equal(
        store.get(SharedStateBridge.LEGACY_NON_ETB_NOTICE_DISMISSED_SETTING_KEY),
        'true'
      );

      const restored = normalizeRestoredFinanceState(
        SharedStateBridge.assembleLiveDatabaseState()
      );
      assert.equal(restored.accounts.length, dataset.accounts.length);
      assert.equal(restored.journalEntries.length, dataset.entries.length);
      assert.equal(restored.postings.length, dataset.postings.length);
      assert.equal(restored.debts.length, 1);
      assert.equal(restored.settlementAllocations.length, 1);
      assert.equal(restored.commitments.length, 3);
      assert.equal(restored.commitmentSettlements.length, 1);
      assert.equal(restored.savingsGoals.length, 2);
      assert.equal(restored.recurringRules.length, 1);
      assert.equal(
        restored.accounts.find((a) => a.id === 'acc-usd-bank')?.openingBalanceCents,
        100000
      );
      assert.equal(
        restored.accounts.find((a) => a.id === 'acc-usd-bank')?.currencyCode,
        'USD'
      );
      assert.equal(
        restored.accounts.find((a) => a.id === 'acc-eur-cash')?.currencyCode,
        'EUR'
      );
      assert.equal(
        restored.accounts.find((a) => a.id === 'acc-unclassified')?.currencyCode,
        ''
      );
      assert.equal(
        restored.postings.find((p) => p.id === 'post-usd-v-dr')?.note,
        'Should stay preserved on voided chain'
      );

      // Point 4 & 5: Restored records stay in read-only archive, excluded from ALL ETB reports/calculations, and ETB totals match identically
      const postBreakdown = calculateAvailableToSpendBreakdownV7({
        accounts: restored.accounts,
        entries: restored.journalEntries,
        postings: restored.postings,
        debts: restored.debts,
        commitments: restored.commitments,
        commitmentSettlements: restored.commitmentSettlements,
        savingsGoals: restored.savingsGoals,
        recurringRules: restored.recurringRules,
        planningPeriodEndIso: '2026-11-30',
      });
      assert.deepEqual(postBreakdown, preBreakdown);

      const balancesReport = buildAccountBalancesReportV7({
        accounts: restored.accounts,
        entries: restored.journalEntries,
        postings: restored.postings,
      });
      assert.deepEqual(
        balancesReport.liquidAccounts.map((x) => [x.accountId, x.balanceCents]),
        [['acc-etb-cbe', 309500]]
      );
      assert.deepEqual(
        balancesReport.vaultAccounts.map((x) => [x.accountId, x.balanceCents]),
        [['acc-etb-vault', 100000]]
      );
      assert.deepEqual(
        balancesReport.creditCardAccounts.map((x) => [x.accountId, x.balanceCents]),
        [['acc-etb-card', 20000]]
      );
      assert.equal(balancesReport.nonEtbReviewAccounts.length, 4);
      // Verify native minor-unit balances on USD/EUR/unclassified accounts:
      // USD bank = 100,000 - 15,000 (exp) - 2,000 (corr) - 30,000 (loan) + 10,000 (repay) = 63,000
      assert.equal(
        balancesReport.nonEtbReviewAccounts.find((x) => x.accountId === 'acc-usd-bank')?.balanceCents,
        63000
      );
      // EUR cash = 60,000 - 12,000 = 48,000
      assert.equal(
        balancesReport.nonEtbReviewAccounts.find((x) => x.accountId === 'acc-eur-cash')?.balanceCents,
        48000
      );
      // Unclassified = 50,000 - 7,500 = 42,500
      assert.equal(
        balancesReport.nonEtbReviewAccounts.find((x) => x.accountId === 'acc-unclassified')?.balanceCents,
        42500
      );

      const sheet = buildAlignedBalanceSheetReportV7({
        accounts: restored.accounts,
        entries: restored.journalEntries,
        postings: restored.postings,
        debts: restored.debts,
        allocations: restored.settlementAllocations,
        breakdown: postBreakdown,
      });
      // Net financial position ETB = 309,500 + 100,000 - 20,000 = 389,500 (USD debt excluded)
      assert.equal(sheet.netFinancialPositionCents, 389500);
      assert.equal(sheet.receivablesCents, 0);

      const vaultReport = buildSavingsVaultsAndGoalsReportV7({
        accounts: restored.accounts,
        entries: restored.journalEntries,
        postings: restored.postings,
        savingsGoals: restored.savingsGoals,
      });
      assert.equal(vaultReport.totalVaultBalanceCents, 100000);
      assert.equal(vaultReport.totalGoalAllocatedCents, 100000);
      assert.equal(vaultReport.goals.length, 2);
      assert.equal(
        vaultReport.goals.find((g) => g.goalId === 'goal-usd-legacy')?.isExcludedNonEtbVault,
        true
      );

      // ETB food spend in Nov 2026 = 30,000 - 10,000 refund = 20,000 (USD Oct food 15,000 excluded)
      const foodSpendAll = calculateCanonicalCategorySpendV7({
        accounts: restored.accounts,
        entries: restored.journalEntries,
        postings: restored.postings,
        categories: restored.categories,
        startDate: '2026-01-01',
        endDate: '2026-12-31',
      });
      assert.equal(foodSpendAll.rollupSpendByCategoryId['cat-food'], 20000);

      const budgetProgress = buildMonthlyBudgetProgressReportV7({
        budgets: restored.budgets,
        categories: restored.categories,
        entries: restored.journalEntries,
        postings: restored.postings,
        accounts: restored.accounts,
        debts: restored.debts,
        allocations: restored.settlementAllocations,
        monthIso: '2026-11',
      });
      assert.equal(budgetProgress.totalSpentCents, 20000);

      const occReport = generateOccurrenceReport({
        entries: restored.journalEntries,
        postings: restored.postings,
        accounts: restored.accounts,
        categories: restored.categories,
        debts: restored.debts,
        allocations: restored.settlementAllocations,
        startDate: '2026-01-01',
        endDate: '2026-12-31',
      });
      // ETB Income = 80,000; ETB Net Expense = 20,500 (30,000 + 500 fee - 10,000 refund)
      assert.equal(occReport.totalIncomeCents, 80000);
      assert.equal(occReport.totalExpenseCents, 20500);

      const cfReport = generateCashFlowReport({
        entries: restored.journalEntries,
        postings: restored.postings,
        accounts: restored.accounts,
        debts: restored.debts,
        allocations: restored.settlementAllocations,
        startDate: '2026-01-01',
        endDate: '2026-12-31',
      });
      assert.equal(cfReport.totalCashInflowCents, 90000); // 80,000 salary + 10,000 refund
      assert.equal(cfReport.totalCashOutflowCents, 30500); // 30,000 + 500 fee

      const integrity = verifyFinanceV7Integrity({
        accounts: restored.accounts,
        entries: restored.journalEntries,
        postings: restored.postings,
        debts: restored.debts,
        allocations: restored.settlementAllocations,
        commitments: restored.commitments,
        commitmentSettlements: restored.commitmentSettlements,
        savingsGoals: restored.savingsGoals,
        recurringRules: restored.recurringRules,
      });
      assert.equal(integrity.isHealthy, true);
      assert.equal(integrity.excludedNonEtbEntryCount, 5);
      assert.equal(integrity.currencyReviewEntryCount, 1);

      // Mutation guards remain fail-closed on restored legacy records
      assert.equal(
        getExpenseRefundSummaryV7({
          originalEntryId: 'je-usd-exp',
          entries: restored.journalEntries,
          postings: restored.postings,
          accounts: restored.accounts,
        }).eligible,
        false
      );
      const canReplaceUsd = canCorrectJournalEntryV7({
        entry: restored.journalEntries.find((e) => e.id === 'je-usd-exp')!,
        entries: restored.journalEntries,
        postings: restored.postings,
        accounts: restored.accounts,
        debts: restored.debts,
        allocations: restored.settlementAllocations,
        commitmentSettlements: restored.commitmentSettlements,
      });
      assert.equal(canReplaceUsd.ok, false);
      assert.throws(() =>
        correctJournalEntryV7({
          originalEntryId: 'je-usd-exp',
          replacementEntry: {
            id: 'je-bad-replace',
            entryType: 'standard',
            description: 'Should fail',
            occurrenceDate: '2026-11-15',
            isVoided: false,
            createdAt: '2026-11-15T00:00:00.000Z',
          },
          replacementPostings: [],
          accounts: restored.accounts,
          entries: restored.journalEntries,
          postings: restored.postings,
          debts: restored.debts,
          allocations: restored.settlementAllocations,
          commitments: restored.commitments,
          commitmentSettlements: restored.commitmentSettlements,
          savingsGoals: restored.savingsGoals,
          simpleTransactions: restored.transactions,
        })
      );
      assert.throws(() =>
        unvoidJournalEntryGuardedV7({
          entryId: 'je-usd-voided',
          accounts: restored.accounts,
          entries: restored.journalEntries,
          postings: restored.postings,
          debts: restored.debts,
          allocations: restored.settlementAllocations,
          commitments: restored.commitments,
          commitmentSettlements: restored.commitmentSettlements,
          savingsGoals: restored.savingsGoals,
          simpleTransactions: restored.transactions,
        })
      );
      for (const legacyEntryId of [
        'je-usd-exp',
        'je-eur-com-settle',
        'je-unclassified-exp',
      ]) {
        assert.throws(
          () =>
            voidJournalEntryGuardedV7({
              entryId: legacyEntryId,
              reason: 'Should fail on read-only legacy record',
              accounts: restored.accounts,
              entries: restored.journalEntries,
              postings: restored.postings,
              debts: restored.debts,
              allocations: restored.settlementAllocations,
              commitments: restored.commitments,
              commitmentSettlements: restored.commitmentSettlements,
              savingsGoals: restored.savingsGoals,
              simpleTransactions: restored.transactions,
            }),
          (err: Error) => err.message.includes('read-only')
        );
      }
      // Ordinary ETB entry remains cleanly voidable & restorable
      const voidEtbInc = voidJournalEntryGuardedV7({
        entryId: 'je-etb-inc',
        reason: 'Regression check void',
        accounts: restored.accounts,
        entries: restored.journalEntries,
        postings: restored.postings,
        debts: restored.debts,
        allocations: restored.settlementAllocations,
        commitments: restored.commitments,
        commitmentSettlements: restored.commitmentSettlements,
        savingsGoals: restored.savingsGoals,
        simpleTransactions: restored.transactions,
      });
      assert.equal(
        voidEtbInc.updatedEntries.find((e) => e.id === 'je-etb-inc')?.isVoided,
        true
      );
      const restoreEtbInc = unvoidJournalEntryGuardedV7({
        entryId: 'je-etb-inc',
        accounts: restored.accounts,
        entries: voidEtbInc.updatedEntries,
        postings: restored.postings,
        debts: voidEtbInc.updatedDebts,
        allocations: restored.settlementAllocations,
        commitments: voidEtbInc.updatedCommitments,
        commitmentSettlements: restored.commitmentSettlements,
        savingsGoals: voidEtbInc.updatedSavingsGoals,
        simpleTransactions: voidEtbInc.updatedSimpleTransactions,
      });
      assert.equal(
        restoreEtbInc.updatedEntries.find((e) => e.id === 'je-etb-inc')?.isVoided,
        false
      );

      // Restored due legacy recurring rule pauses autoPost without generating entries/commitments or advancing nextOccurrenceDate
      const recProcessRes = processDueRecurringRulesV7({
        rules: restored.recurringRules,
        todayIso: '2026-12-05',
        accounts: restored.accounts,
        debts: restored.debts,
        entries: restored.journalEntries,
        postings: restored.postings,
        allocations: restored.settlementAllocations,
      });
      assert.equal(recProcessRes.createdEntries.length, 0);
      assert.equal(recProcessRes.createdCommitments.length, 0);
      const pausedUsdRule = recProcessRes.updatedRules.find(
        (r) => r.id === 'rule-usd-legacy'
      );
      assert.equal(pausedUsdRule?.autoPost, false);
      assert.equal(pausedUsdRule?.isActive, true);
      assert.equal(pausedUsdRule?.nextOccurrenceDate, '2026-12-01');
      assert.throws(() =>
        recordCommitmentSettlementV7({
          commitment: restored.commitments.find((c) => c.id === 'com-eur-due')!,
          accountId: 'acc-eur-cash',
          amountCents: 8500,
          settledDateIso: '2026-11-15',
          existingSettlements: restored.commitmentSettlements,
          entries: restored.journalEntries,
          accounts: restored.accounts,
          postings: restored.postings,
          debts: restored.debts,
          allocations: restored.settlementAllocations,
          recurringRules: restored.recurringRules,
        })
      );
      assert.throws(() =>
        fundSavingsGoalV7({
          goal: restored.savingsGoals.find((g) => g.id === 'goal-usd-legacy')!,
          amountCents: 5000,
          direction: 'deposit',
          sourceAccountId: 'acc-etb-cbe',
          dateIso: '2026-11-15',
          accounts: restored.accounts,
          entries: restored.journalEntries,
          postings: restored.postings,
        })
      );

      // SSR check on restored state: notice remains dismissed, Legacy Archive remains read-only
      const overviewHtml = renderToStaticMarkup(
        React.createElement(FinanceOverviewTab, {
          accounts: restored.accounts,
          categories: restored.categories,
          entries: restored.journalEntries,
          postings: restored.postings,
          simpleTransactions: restored.transactions,
          breakdown: postBreakdown,
          planningPeriodEnd: null,
          onChangePlanningPeriodEnd: () => {},
          onOpenComposer: () => {},
          onSaveAccount: () => ({ ok: true }),
          onToggleArchiveAccount: () => ({ ok: true }),
          onDeleteAccount: () => ({ ok: true }),
          onSaveCategory: () => ({ ok: true }),
          onToggleArchiveCategory: () => {},
          onDeleteCategory: () => ({ ok: true }),
          onNavigateTab: () => {},
          onRequestConfirm: () => {},
          hasIntegrityNotices: false,
          legacyNoticeDismissed:
            store.get(SharedStateBridge.LEGACY_NON_ETB_NOTICE_DISMISSED_SETTING_KEY) === 'true',
          onDismissLegacyNotice: () => {},
        })
      );
      assert.ok(!overviewHtml.includes('Historical Non-ETB Records Preserved'));
      assert.ok(overviewHtml.includes('Legacy Non-ETB Archive (Read-Only)'));
      assert.ok(!overviewHtml.includes('USD Travel Account'));
      assert.ok(!overviewHtml.includes('EUR Envelope'));
      assert.ok(!overviewHtml.includes('Old Unclassified Pouch'));

      const txHtml = renderToStaticMarkup(
        React.createElement(FinanceTransactionsTab, {
          entries: restored.journalEntries,
          postings: restored.postings,
          accounts: restored.accounts,
          categories: restored.categories,
          onOpenComposer: () => {},
          onVoidEntry: () => ({ ok: true }),
          onRestoreEntry: () => ({ ok: true }),
          onRequestConfirm: () => {},
        })
      );
      assert.ok(txHtml.includes('Legacy Non-ETB Entries ('));

      const planHtml = renderToStaticMarkup(
        React.createElement(FinancePlanTab, {
          accounts: restored.accounts,
          categories: restored.categories,
          parties: restored.parties,
          entries: restored.journalEntries,
          postings: restored.postings,
          debts: restored.debts,
          allocations: restored.settlementAllocations,
          commitments: restored.commitments,
          commitmentSettlements: restored.commitmentSettlements,
          savingsGoals: restored.savingsGoals,
          budgets: restored.budgets,
          recurringRules: restored.recurringRules,
          availableLiquidCashCents: postBreakdown.availableToSpendCents,
          onAddCommitment: () => ({ ok: true }),
          onRecordCommitmentSettlement: () => ({ ok: true }),
          onVoidCommitmentSettlement: () => ({ ok: true }),
          onMarkLegacyUnpaid: () => {},
          onOpenComposer: () => {},
          onSettleDebt: () => ({ ok: true }),
          onWriteOffDebt: () => {},
          onVoidDebtWriteOff: () => ({ ok: true }),
          onVoidDebtOrigin: () => ({ ok: true }),
          onAddSavingsGoal: () => ({ ok: true }),
          onFundSavingsGoal: () => ({ ok: true }),
          onReleaseAndArchiveGoal: () => ({ ok: true }),
          onUpsertBudget: () => {},
          onAddRecurringRule: () => ({ ok: true }),
          onToggleRecurringActive: () => {},
          onToggleRecurringAutoPost: () => {},
          onSkipNextRecurring: () => {},
          onProcessDueRules: () => 0,
          onRequestConfirm: () => {},
        })
      );
      assert.ok(planHtml.includes('Legacy USD Travel Fund'));

      const reportsHtml = renderToStaticMarkup(
        React.createElement(FinanceReportsTab, {
          accounts: restored.accounts,
          categories: restored.categories,
          entries: restored.journalEntries,
          postings: restored.postings,
          debts: restored.debts,
          commitments: restored.commitments,
          breakdown: postBreakdown,
          integrityReport: integrity,
          onRefreshState: () => {},
        })
      );
      assert.ok(reportsHtml.includes('Account Balances (ETB)'));

      // Finance-only restore preserves non-Finance Tasks/Notes & local notice flag, and backfills blank descriptions
      const finOnlyPayloadObj = JSON.parse(financeOnlyJson);
      finOnlyPayloadObj.journalEntries = finOnlyPayloadObj.journalEntries.map((e: any) =>
        e.id === 'je-usd-exp' || e.id === 'je-usd-voided' ? { ...e, description: '' } : e
      );
      const finOnlyRes = SharedStateBridge.importFinanceOnlyJson(
        JSON.stringify(finOnlyPayloadObj)
      );
      assert.equal(finOnlyRes.success, true, finOnlyRes.error);
      assert.equal(JSON.parse(store.get('daywell_tasks') || '[]')[0].id, 'task-keep-1');
      assert.equal(JSON.parse(store.get('daywell_notes') || '[]')[0].id, 'note-keep-1');
      assert.equal(
        store.get(SharedStateBridge.LEGACY_NON_ETB_NOTICE_DISMISSED_SETTING_KEY),
        'true'
      );
      const postFinOnlyEntries = JSON.parse(
        store.get('daywell_journal_entries') || '[]'
      ) as JournalEntry[];
      assert.equal(
        postFinOnlyEntries.find((e) => e.id === 'je-usd-exp')?.description,
        'Airport Hotel USD'
      );
      assert.equal(
        postFinOnlyEntries.find((e) => e.id === 'je-usd-voided')?.description,
        'Should stay preserved on voided chain'
      );
    });
  });

  it('Point 6: Older backups without Stage 3 archive behavior (pre-v6 transactions-only, schemaVersion 6, isActive:false, omitted currencyCode/appSettings) restore safely', () => {
    withMockBrowserStorage((store) => {
      // Pre-existing notice dismissal should be preserved when an older backup omits appSettings
      store.set(SharedStateBridge.LEGACY_NON_ETB_NOTICE_DISMISSED_SETTING_KEY, 'true');

      // 6a. Pre-v6 schemaVersion 4 backup (transactions-only, no journalEntries/postings, omitted currencyCode & isArchived, isActive:false)
      const legacyV4Snapshot = {
        schemaVersion: 4,
        isFinanceSetupCompleted: true,
        openingBalanceCents: 120000,
        accounts: [
          {
            id: 'acc-etb-main',
            name: 'Main ETB Cash',
            type: 'asset',
            currencyCode: 'ETB',
            openingBalanceCents: 120000,
            createdAt: '2026-09-01T00:00:00.000Z',
          },
          {
            id: 'acc-old-usd',
            name: 'Archived Dollar Card',
            type: 'asset',
            currencyCode: 'USD',
            openingBalanceCents: 75000,
            isActive: false,
            createdAt: '2026-09-01T00:00:00.000Z',
          },
          {
            id: 'acc-old-untyped',
            name: 'Legacy No-Currency Pouch',
            type: 'asset',
            openingBalanceCents: 45000,
            createdAt: '2026-09-01T00:00:00.000Z',
          },
        ],
        categories: [
          { id: 'cat-food', name: 'Food', type: 'expense', colorHex: '#EF4444' },
        ],
        transactions: [
          {
            id: 'tx-v4-etb',
            type: 'expense',
            amountCents: 20000,
            accountId: 'acc-etb-main',
            categoryId: 'cat-food',
            description: 'ETB Market',
            transactionDate: '2026-09-05',
            createdAt: '2026-09-05T10:00:00.000Z',
          },
          {
            id: 'tx-v4-usd',
            type: 'expense',
            amountCents: 12000,
            accountId: 'acc-old-usd',
            categoryId: 'cat-food',
            description: 'USD Duty Free',
            transactionDate: '2026-09-06',
            createdAt: '2026-09-06T10:00:00.000Z',
          },
          {
            id: 'tx-v4-untyped',
            type: 'expense',
            amountCents: 5000,
            accountId: 'acc-old-untyped',
            categoryId: 'cat-food',
            description: 'Untyped Cash Spend',
            transactionDate: '2026-09-07',
            createdAt: '2026-09-07T10:00:00.000Z',
          },
        ],
        tasks: [],
        projects: [],
        milestones: [],
        goals: [],
        notes: [],
        inboxItems: [],
        calendarEvents: [],
        commitments: [],
        savingsGoals: [],
      };

      const v4Res = SharedStateBridge.importFromAndroidJson(JSON.stringify(legacyV4Snapshot));
      assert.equal(v4Res.success, true, v4Res.error);
      assert.equal(
        store.get(SharedStateBridge.LEGACY_NON_ETB_NOTICE_DISMISSED_SETTING_KEY),
        'true',
        'Older backup without appSettings must not erase existing notice dismissal'
      );

      const v4Restored = normalizeRestoredFinanceState(
        SharedStateBridge.assembleLiveDatabaseState()
      );
      assert.equal(
        v4Restored.accounts.find((a) => a.id === 'acc-old-usd')?.isArchived,
        true,
        'Legacy isActive:false must map to isArchived:true'
      );
      assert.equal(
        v4Restored.accounts.find((a) => a.id === 'acc-old-untyped')?.currencyCode,
        '',
        'Omitted currencyCode must stay unclassified rather than silently becoming ETB'
      );

      // Hydrate v4 simple transactions into v7 ledger without failing on non-ETB accounts
      const hydrated = hydrateLedgerFromSimpleTransactions({
        transactions: v4Restored.transactions,
        accounts: v4Restored.accounts,
        entries: v4Restored.journalEntries,
        postings: v4Restored.postings,
      });
      const v4Breakdown = calculateAvailableToSpendBreakdownV7({
        accounts: hydrated.accounts,
        entries: hydrated.entries,
        postings: hydrated.postings,
        debts: [],
        commitments: [],
        commitmentSettlements: [],
        savingsGoals: [],
      });
      // ETB liquid cash = 120,000 - 20,000 = 100,000; USD & untyped excluded (opening + expense)
      assert.equal(v4Breakdown.liquidCashCents, 100000);
      assert.equal(v4Breakdown.currencyReviewEntryCount, 2);

      // 6b. SchemaVersion 6 snapshotFormatVersion: 1 with blank description + historical posting note + explicit appSettings omitting notice key
      const legacyV6Snapshot = {
        schemaVersion: 6,
        snapshotFormatVersion: 1,
        isFinanceSetupCompleted: true,
        openingBalanceCents: 50000,
        accounts: [
          ...makeSystemAccounts(),
          {
            id: 'acc-etb-v6',
            name: 'ETB V6 Bank',
            type: 'asset',
            subType: 'bank',
            currencyCode: 'ETB',
            openingBalanceCents: 50000,
            isArchived: false,
            createdAt: '2026-10-01T00:00:00.000Z',
          },
          {
            id: 'acc-usd-v6',
            name: 'USD V6 Bank',
            type: 'asset',
            subType: 'bank',
            currencyCode: 'USD',
            openingBalanceCents: 30000,
            isActive: false,
            createdAt: '2026-10-01T00:00:00.000Z',
          },
        ],
        categories: DEFAULT_EXPENSE_CATEGORIES,
        journalEntries: [
          {
            id: 'je-v6-usd',
            entryType: 'standard',
            description: '',
            occurrenceDate: '2026-10-10',
            isVoided: false,
            createdAt: '2026-10-10T00:00:00.000Z',
          },
        ],
        postings: [
          {
            id: 'p-v6-1',
            entryId: 'je-v6-usd',
            accountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
            amountCents: 4000,
            direction: 'debit',
            accountMovementDate: '2026-10-10',
            categoryId: 'cat-food',
            note: 'Historical V6 USD Diner',
          },
          {
            id: 'p-v6-2',
            entryId: 'je-v6-usd',
            accountId: 'acc-usd-v6',
            amountCents: 4000,
            direction: 'credit',
            accountMovementDate: '2026-10-10',
          },
        ],
        transactions: [],
        tasks: [],
        projects: [],
        milestones: [],
        goals: [],
        notes: [],
        inboxItems: [],
        calendarEvents: [],
        commitments: [],
        savingsGoals: [],
        appSettings: [],
      };

      const v6Res = SharedStateBridge.importFromAndroidJson(JSON.stringify(legacyV6Snapshot));
      assert.equal(v6Res.success, true, v6Res.error);
      assert.equal(
        localStorage.getItem(SharedStateBridge.LEGACY_NON_ETB_NOTICE_DISMISSED_SETTING_KEY),
        null,
        'Explicit empty appSettings from clean older backup resets notice dismissal cleanly'
      );
      const v6Restored = normalizeRestoredFinanceState(
        SharedStateBridge.assembleLiveDatabaseState()
      );
      assert.equal(
        v6Restored.journalEntries.find((e) => e.id === 'je-v6-usd')?.description,
        'Historical V6 USD Diner'
      );
      assert.equal(
        v6Restored.accounts.find((a) => a.id === 'acc-usd-v6')?.isArchived,
        true
      );
      const v6Breakdown = calculateAvailableToSpendBreakdownV7({
        accounts: v6Restored.accounts,
        entries: v6Restored.journalEntries,
        postings: v6Restored.postings,
        debts: [],
        commitments: [],
        commitmentSettlements: [],
        savingsGoals: [],
      });
      assert.equal(v6Breakdown.liquidCashCents, 50000);
      assert.equal(
        v6Restored.accounts.find((a) => a.id === 'acc-usd-v6')?.currencyCode,
        'USD'
      );
    });
  });

  it('Pre-v6 unlinked SimpleTransaction records (no accountId / unknown accountId) hydrate into acc-sys-legacy-offset, stay visible read-only in Legacy Archive without ETB interpretation, and never affect ETB calculations', () => {
    withMockBrowserStorage((store) => {
      const legacyV4UnlinkedSnapshot = {
        schemaVersion: 4,
        isFinanceSetupCompleted: true,
        openingBalanceCents: 150000,
        accounts: [
          {
            id: 'acc-etb-main',
            name: 'Main ETB Bank',
            type: 'asset',
            subType: 'bank',
            currencyCode: 'ETB',
            openingBalanceCents: 150000,
            createdAt: '2026-08-01T00:00:00.000Z',
          },
        ],
        categories: [
          ...DEFAULT_EXPENSE_CATEGORIES,
          ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
        ],
        transactions: [
          {
            id: 'tx-etb-valid',
            type: 'expense',
            amountCents: 25000,
            accountId: 'acc-etb-main',
            categoryId: 'cat-food',
            description: 'ETB Lunch',
            transactionDate: '2026-08-10',
            createdAt: '2026-08-10T12:00:00.000Z',
          },
          {
            id: 'tx-v4-no-account-exp',
            type: 'expense',
            amountCents: 18500,
            categoryId: 'cat-food',
            description: 'Unlinked Old Diner',
            transactionDate: '2026-08-12',
            createdAt: '2026-08-12T18:30:00.000Z',
          },
          {
            id: 'tx-v4-no-account-inc',
            type: 'income',
            amountCents: 42000,
            categoryId: 'cat-salary',
            payee: 'Former Client',
            note: 'Historical cash retainer',
            transactionDate: '2026-08-14',
            createdAt: '2026-08-14T09:15:00.000Z',
          },
          {
            id: 'tx-v4-no-account-xfer',
            type: 'transfer',
            amountCents: 9000,
            description: 'Unlinked Old Transfer',
            transactionDate: '2026-08-15',
            createdAt: '2026-08-15T11:00:00.000Z',
          },
          {
            id: 'tx-v4-missing-acc-exp',
            type: 'expense',
            amountCents: 6500,
            accountId: 'acc-deleted-pre-v6',
            categoryId: 'cat-transport',
            description: 'Deleted Account Cab',
            transactionDate: '2026-08-16',
            createdAt: '2026-08-16T07:45:00.000Z',
          },
        ],
        tasks: [],
        projects: [],
        milestones: [],
        goals: [],
        notes: [],
        inboxItems: [],
        calendarEvents: [],
        commitments: [],
        savingsGoals: [],
      };

      const importRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify(legacyV4UnlinkedSnapshot)
      );
      assert.equal(importRes.success, true, importRes.error);

      const restored = normalizeRestoredFinanceState(
        SharedStateBridge.assembleLiveDatabaseState()
      );
      // Raw unlinked transactions stay preserved in transactions array without inventing an accountId
      assert.equal(restored.transactions.length, 5);
      const rawNoAccExp = restored.transactions.find((t) => t.id === 'tx-v4-no-account-exp');
      assert.ok(rawNoAccExp);
      assert.equal(rawNoAccExp.accountId, undefined);
      assert.equal(rawNoAccExp.amountCents, 18500);
      assert.equal(rawNoAccExp.transactionDate, '2026-08-12');

      // Hydrate into double-entry ledger (as DaywellFinanceModule / App.tsx do on restore)
      const hydrated = hydrateLedgerFromSimpleTransactions({
        accounts: restored.accounts,
        transactions: restored.transactions,
        entries: restored.journalEntries,
        postings: restored.postings,
      });
      assert.equal(hydrated.migratedCount, 5);
      assert.ok(
        hydrated.accounts.some(
          (a) =>
            a.id === SYSTEM_CONTROL_ACCOUNT_IDS.legacyOffset &&
            a.subType === 'legacy_clearing'
        )
      );

      // Re-hydrating is strictly idempotent
      const secondPass = hydrateLedgerFromSimpleTransactions({
        accounts: hydrated.accounts,
        transactions: restored.transactions,
        entries: hydrated.entries,
        postings: hydrated.postings,
      });
      assert.equal(secondPass.migratedCount, 0);
      assert.equal(secondPass.entries.length, hydrated.entries.length);

      // Verify preserved identifiers, amounts, descriptions, dates, and legacy_clearing postings
      const expEntry = hydrated.entries.find(
        (e) => e.legacySourceTxId === 'tx-v4-no-account-exp'
      );
      assert.ok(expEntry);
      assert.equal(expEntry.description, 'Unlinked Old Diner');
      assert.equal(expEntry.occurrenceDate, '2026-08-12');
      assert.equal(expEntry.createdAt, '2026-08-12T18:30:00.000Z');
      const expPostings = hydrated.postings.filter((p) => p.entryId === expEntry.id);
      assert.equal(expPostings.length, 2);
      assert.ok(
        expPostings.some(
          (p) =>
            p.accountId === SYSTEM_CONTROL_ACCOUNT_IDS.legacyOffset &&
            p.direction === 'credit' &&
            p.amountCents === 18500
        )
      );
      assert.ok(
        expPostings.some(
          (p) =>
            p.accountId === SYSTEM_CONTROL_ACCOUNT_IDS.expense &&
            p.direction === 'debit' &&
            p.categoryId === 'cat-food' &&
            p.amountCents === 18500
        )
      );

      const incEntry = hydrated.entries.find(
        (e) => e.legacySourceTxId === 'tx-v4-no-account-inc'
      );
      assert.ok(incEntry);
      assert.equal(incEntry.description, 'Former Client — Historical cash retainer');
      assert.equal(incEntry.occurrenceDate, '2026-08-14');
      assert.ok(
        hydrated.postings.some(
          (p) =>
            p.entryId === incEntry.id &&
            p.accountId === SYSTEM_CONTROL_ACCOUNT_IDS.legacyOffset &&
            p.amountCents === 42000
        )
      );

      const xferEntry = hydrated.entries.find(
        (e) => e.legacySourceTxId === 'tx-v4-no-account-xfer'
      );
      assert.ok(xferEntry);
      assert.equal(xferEntry.entryType, 'transfer');
      assert.equal(xferEntry.description, 'Unlinked Old Transfer');
      assert.equal(
        hydrated.postings.filter(
          (p) =>
            p.entryId === xferEntry.id &&
            p.accountId === SYSTEM_CONTROL_ACCOUNT_IDS.legacyOffset
        ).length,
        2
      );

      const deletedAccEntry = hydrated.entries.find(
        (e) => e.legacySourceTxId === 'tx-v4-missing-acc-exp'
      );
      assert.ok(deletedAccEntry);
      assert.equal(deletedAccEntry.description, 'Deleted Account Cab');

      // Classifications exclude all 4 unlinked records from ETB
      const classifications = classifyAllJournalEntries({
        accounts: hydrated.accounts,
        entries: hydrated.entries,
        postings: hydrated.postings,
      });
      for (const unlinkedEntry of [expEntry, incEntry, xferEntry, deletedAccEntry]) {
        const cls = classifications.get(unlinkedEntry.id);
        assert.equal(cls?.status, 'mixed_or_ambiguous');
        assert.equal(cls?.isEligibleEtb, false);
        assert.equal(cls?.nativeCurrencyCode, undefined);
      }

      // ETB balances, Safe Harbor, P&L, Cash Flow, Category Spend, Budgets, and Integrity exclude all 4 unlinked entries
      const breakdown = calculateAvailableToSpendBreakdownV7({
        accounts: hydrated.accounts,
        entries: hydrated.entries,
        postings: hydrated.postings,
        debts: [],
        commitments: [],
        commitmentSettlements: [],
        savingsGoals: [],
        planningPeriodEndIso: '2026-08-31',
      });
      assert.equal(breakdown.liquidCashCents, 125000); // 150,000 - 25,000 ETB only
      assert.equal(breakdown.availableToSpendCents, 125000);
      assert.equal(breakdown.netFinancialPositionCents, 125000);
      assert.equal(breakdown.currencyReviewEntryCount, 4);

      const balances = buildAccountBalancesReportV7({
        accounts: hydrated.accounts,
        entries: hydrated.entries,
        postings: hydrated.postings,
      });
      assert.deepEqual(
        balances.liquidAccounts.map((a) => [a.accountId, a.balanceCents]),
        [['acc-etb-main', 125000]]
      );
      assert.equal(balances.nonEtbReviewAccounts.length, 0);

      const occ = generateOccurrenceReport({
        entries: hydrated.entries,
        postings: hydrated.postings,
        accounts: hydrated.accounts,
        categories: restored.categories,
        startDate: '2026-08-01',
        endDate: '2026-08-31',
      });
      assert.equal(occ.totalIncomeCents, 0);
      assert.equal(occ.totalExpenseCents, 25000);

      const cf = generateCashFlowReport({
        entries: hydrated.entries,
        postings: hydrated.postings,
        accounts: hydrated.accounts,
        startDate: '2026-08-01',
        endDate: '2026-08-31',
      });
      assert.equal(cf.totalCashInflowCents, 0);
      assert.equal(cf.totalCashOutflowCents, 25000);

      const catSpend = calculateCanonicalCategorySpendV7({
        accounts: hydrated.accounts,
        entries: hydrated.entries,
        postings: hydrated.postings,
        categories: restored.categories,
        startDate: '2026-08-01',
        endDate: '2026-08-31',
      });
      assert.equal(catSpend.rollupSpendByCategoryId['cat-food'], 25000);
      assert.equal(catSpend.rollupSpendByCategoryId['cat-transport'] ?? 0, 0);

      const budgetProgress = buildMonthlyBudgetProgressReportV7({
        budgets: [
          {
            id: 'bud-aug-food',
            categoryId: 'cat-food',
            monthIso: '2026-08',
            limitCents: 50000,
            rolloverEnabled: false,
            createdAt: '2026-08-01T00:00:00.000Z',
            updatedAt: '2026-08-01T00:00:00.000Z',
          },
        ],
        categories: restored.categories,
        entries: hydrated.entries,
        postings: hydrated.postings,
        accounts: hydrated.accounts,
        debts: [],
        allocations: [],
        monthIso: '2026-08',
      });
      assert.equal(budgetProgress.totalSpentCents, 25000);

      const integrity = verifyFinanceV7Integrity({
        accounts: hydrated.accounts,
        entries: hydrated.entries,
        postings: hydrated.postings,
        debts: [],
        commitments: [],
      });
      assert.equal(integrity.isHealthy, true);
      assert.equal(integrity.currencyReviewEntryCount, 4);

      // Mutating guards remain fail-closed on legacy_clearing entries
      assert.equal(
        canCorrectJournalEntryV7({
          entry: expEntry,
          entries: hydrated.entries,
          postings: hydrated.postings,
          accounts: hydrated.accounts,
        }).ok,
        false
      );
      assert.equal(
        getExpenseRefundSummaryV7({
          originalEntryId: expEntry.id,
          entries: hydrated.entries,
          postings: hydrated.postings,
          accounts: hydrated.accounts,
        }).eligible,
        false
      );
      assert.throws(
        () =>
          voidJournalEntryGuardedV7({
            entryId: expEntry.id,
            reason: 'Cannot void legacy clearing',
            accounts: hydrated.accounts,
            entries: hydrated.entries,
            postings: hydrated.postings,
            debts: [],
            allocations: [],
            commitments: [],
            commitmentSettlements: [],
            savingsGoals: [],
            simpleTransactions: restored.transactions,
          }),
        (err: Error) => err.message.includes('read-only')
      );

      // Persist hydrated ledger & verify full SharedStateBridge export/restore round-trip succeeds cleanly
      const rawCanonical = SharedStateBridge.assembleLiveDatabaseState();
      SharedStateBridge.saveCanonicalState({
        ...rawCanonical,
        accounts: hydrated.accounts as unknown as typeof rawCanonical.accounts,
        journalEntries: hydrated.entries,
        postings: hydrated.postings,
      });
      const reExportJson = SharedStateBridge.exportToAndroidJson();
      store.clear();
      const reImportRes = SharedStateBridge.importFromAndroidJson(reExportJson);
      assert.equal(reImportRes.success, true, reImportRes.error);
      const afterRoundTrip = normalizeRestoredFinanceState(
        SharedStateBridge.assembleLiveDatabaseState()
      );
      // 1 opening balance adjustment (open:acc-etb-main) + 1 ETB expense + 4 unlinked legacy clearing entries = 6
      assert.equal(afterRoundTrip.journalEntries.length, 6);
      assert.equal(afterRoundTrip.transactions.length, 5);

      // UI visibility: Overview exposes Legacy Archive; Transactions places unlinked records in Read-Only Legacy section without ETB label
      const overviewHtml = renderToStaticMarkup(
        React.createElement(FinanceOverviewTab, {
          accounts: afterRoundTrip.accounts,
          categories: afterRoundTrip.categories,
          entries: afterRoundTrip.journalEntries,
          postings: afterRoundTrip.postings,
          simpleTransactions: afterRoundTrip.transactions,
          breakdown,
          planningPeriodEnd: '2026-08-31',
          onChangePlanningPeriodEnd: () => {},
          onOpenComposer: () => {},
          onSaveAccount: () => ({ ok: true }),
          onToggleArchiveAccount: () => ({ ok: true }),
          onDeleteAccount: () => ({ ok: true }),
          onSaveCategory: () => ({ ok: true }),
          onToggleArchiveCategory: () => {},
          onDeleteCategory: () => ({ ok: true }),
          onNavigateTab: () => {},
          onRequestConfirm: () => {},
          hasIntegrityNotices: false,
          legacyNoticeDismissed: false,
          onDismissLegacyNotice: () => {},
        })
      );
      assert.ok(overviewHtml.includes('Legacy Non-ETB Archive (Read-Only)'));
      assert.ok(overviewHtml.includes('4 ledger entry(ies) preserved separately from ETB totals'));

      const txHtml = renderToStaticMarkup(
        React.createElement(FinanceTransactionsTab, {
          entries: afterRoundTrip.journalEntries,
          postings: afterRoundTrip.postings,
          accounts: afterRoundTrip.accounts,
          categories: afterRoundTrip.categories,
          onOpenComposer: () => {},
          onVoidEntry: () => ({ ok: true }),
          onRestoreEntry: () => ({ ok: true }),
          onRequestConfirm: () => {},
        })
      );
      assert.ok(txHtml.includes('ETB Lunch'));
      assert.ok(txHtml.includes('Legacy Non-ETB Entries (4) · Read-Only'));
    });
  });
});
