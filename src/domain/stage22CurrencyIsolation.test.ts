import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import JSZip from 'jszip';
import * as XLSX from 'xlsx';
import {
  Account,
  AccountSubType,
  DoubleEntryValidationError,
  JournalEntry,
  Party,
  Posting,
  assertEtbDebtEligible,
  assertEtbPostingAccounts,
  assertVerifiedEtbAccount,
  auditCurrencyIsolation,
  buildBorrowMoney,
  buildDebtSettlement,
  buildDebtWriteOff,
  buildDirectExpense,
  buildDirectIncome,
  buildLendMoney,
  buildSplitExpense,
  buildThirdPartyPaidExpense,
  buildTransfer,
  buildVoidEntry,
  calculateAccountBalance,
  calculateAvailableToSpend,
  calculateBudgetStatus,
  calculateLiquidCash,
  calculateNetPosition,
  calculatePrepaidCardCredit,
  calculateShortTermCreditOwed,
  calculateTotalPayables,
  calculateTotalReceivables,
  calculateVaultSavingsTotal,
  classifyAllJournalEntries,
  classifyCurrencyCode,
  classifyJournalEntryCurrency,
  generateCashFlowReport,
  generateOccurrenceReport,
  isDebtEligibleEtb,
  resolveCommitmentCurrencyStatus,
  validateSimpleTransaction,
} from './doubleEntryFinance';
import {
  calculateAvailableToSpendBreakdownV7,
  ensureSystemControlAccounts,
  fundSavingsGoalV7,
  processDueRecurringRulesV7,
  recordCommitmentSettlementV7,
  reviseAccountOpeningBalanceV7,
  verifyFinanceV7Integrity,
} from './financeV7Engine';
import { CalendarDate } from './date';
import {
  SYSTEM_CONTROL_ACCOUNT_IDS,
  SharedCommitment,
  SharedRecurringRule,
  SharedSavingsGoal,
} from './sharedFoundation';
import { DataPortabilityService } from '../services/dataPortabilityService';
import { SharedStateBridge } from '../services/sharedStateBridge';

function makeAccount(
  id: string,
  name: string,
  currencyCode: string,
  openingBalanceCents = 0,
  opts: Partial<Account> = {}
): Account {
  const type = opts.type || 'asset';
  const subType: AccountSubType =
    opts.subType || (type === 'liability' ? 'credit_card' : 'bank');
  return {
    id,
    name,
    type,
    subType,
    currencyCode,
    openingBalanceCents,
    openingBalanceDate: '2026-11-01',
    isArchived: false,
    createdAt: '2026-11-01T00:00:00Z',
    ...opts,
  };
}

function makeParty(id: string, name = 'Abebe'): Party {
  return {
    id,
    name,
    isArchived: false,
    createdAt: '2026-11-01T00:00:00Z',
  };
}

function withMockBrowserStorage(fn: (store: Map<string, string>) => void): void {
  const store = new Map<string, string>();
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

  try {
    fn(store);
  } finally {
    (globalThis as any).window = prevWindow;
    (globalThis as any).localStorage = prevLocalStorage;
  }
}

describe('Recovery Stage 2.2: Strict ETB Currency Isolation (Cases #1-#25)', () => {
  it('Case #1: Currency tier normalization classifies etb/ETB, USD/EUR, and blank/invalid/unrecognized', () => {
    assert.equal(classifyCurrencyCode('etb'), 'verified_etb');
    assert.equal(classifyCurrencyCode(' ETB '), 'verified_etb');
    assert.equal(classifyCurrencyCode('usd'), 'verified_non_etb');
    assert.equal(classifyCurrencyCode('EUR'), 'verified_non_etb');
    assert.equal(classifyCurrencyCode(''), 'unverified');
    assert.equal(classifyCurrencyCode(null), 'unverified');
    assert.equal(classifyCurrencyCode(undefined), 'unverified');
    assert.equal(classifyCurrencyCode('XYZ'), 'unverified');
    assert.equal(classifyCurrencyCode('ETHB'), 'unverified');
  });

  it('Cases #2 & #3: USD expense & USD income vs ETB nominal accounts classify as excluded_non_etb(USD) under Decision D', () => {
    const accounts = ensureSystemControlAccounts([
      makeAccount('acc-cbe', 'CBE', 'ETB', 100_000),
      makeAccount('acc-usd', 'USD Cash', 'USD', 50_000, { subType: 'cash' }),
    ]);
    const exp = buildDirectExpense({
      id: 'e-usd-exp',
      assetAccountId: 'acc-usd',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 4_000,
      occurrenceDate: '2026-11-05',
      movementDate: '2026-11-05',
      description: 'USD Coffee',
    });
    const inc = buildDirectIncome({
      id: 'e-usd-inc',
      assetAccountId: 'acc-usd',
      incomeAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.income,
      categoryId: 'cat-salary',
      amountCents: 12_000,
      occurrenceDate: '2026-11-06',
      movementDate: '2026-11-06',
      description: 'USD Freelance',
    });

    const entries = [exp.entry, inc.entry];
    const postings = [...exp.postings, ...inc.postings];
    const cls = classifyAllJournalEntries({ accounts, entries, postings });

    assert.equal(cls.get('e-usd-exp')?.status, 'excluded_non_etb');
    assert.equal(cls.get('e-usd-exp')?.nativeCurrencyCode, 'USD');
    assert.equal(cls.get('e-usd-inc')?.status, 'excluded_non_etb');
    assert.equal(cls.get('e-usd-inc')?.nativeCurrencyCode, 'USD');

    // acc-usd native balance reflects USD activity cleanly: 500 - 40 + 120 = 580 USD
    const usdAcc = accounts.find((a) => a.id === 'acc-usd')!;
    assert.equal(calculateAccountBalance(usdAcc, postings, undefined, entries), 58_000);

    // ETB liquid cash and ETB P&L/Cashflow remain strictly isolated
    assert.equal(calculateLiquidCash(accounts, postings, entries), 100_000);
    const occ = generateOccurrenceReport({
      accounts,
      entries,
      postings,
      categories: [],
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    });
    assert.equal(occ.totalExpenseCents, 0);
    assert.equal(occ.totalIncomeCents, 0);
    const cf = generateCashFlowReport({
      accounts,
      entries,
      postings,
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    });
    assert.equal(cf.totalCashInflowCents, 0);
    assert.equal(cf.totalCashOutflowCents, 0);
  });

  it('Case #4: Cross-currency transfer (ETB -> USD) classifies as mixed_or_ambiguous and is excluded from ETB P&L/Cashflow', () => {
    const accounts = ensureSystemControlAccounts([
      makeAccount('acc-cbe', 'CBE', 'ETB', 200_000),
      makeAccount('acc-usd', 'USD Travel', 'USD', 0),
    ]);
    const fx = buildTransfer({
      id: 'e-fx-xfer',
      fromAssetAccountId: 'acc-cbe',
      toAssetAccountId: 'acc-usd',
      amountCents: 12_000,
      date: '2026-11-07',
      description: 'Legacy FX transfer',
    });
    const accountById = new Map(accounts.map((a) => [a.id, a]));
    const cls = classifyJournalEntryCurrency({
      entry: fx.entry,
      entryPostings: fx.postings,
      accountById,
      allEntries: [fx.entry],
      allPostings: fx.postings,
    });
    assert.equal(cls.status, 'mixed_or_ambiguous');
    assert.deepEqual([...cls.touchedCurrencies].sort(), ['ETB', 'USD']);

    const audit = auditCurrencyIsolation({
      accounts,
      entries: [fx.entry],
      postings: fx.postings,
    });
    assert.equal(audit.currencyReviewEntryCount, 1);

    const cf = generateCashFlowReport({
      accounts,
      entries: [fx.entry],
      postings: fx.postings,
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    });
    assert.equal(cf.totalCashOutflowCents, 0);
    assert.equal(cf.totalCashInflowCents, 0);
  });

  it('Cases #5, #6 & #7: Unverified currency account, <2 postings / missing account, and acc-sys-legacy-offset classify as mixed_or_ambiguous and contribute 0 to ETB', () => {
    const accounts = ensureSystemControlAccounts([
      makeAccount('acc-cbe', 'CBE', 'ETB', 50_000),
      makeAccount('acc-legacy-unv', 'Legacy Blank Currency', '', 100_000),
    ]);
    const accountById = new Map(accounts.map((a) => [a.id, a]));

    const unvExp = buildDirectExpense({
      id: 'e-unv',
      assetAccountId: 'acc-legacy-unv',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      amountCents: 10_000,
      occurrenceDate: '2026-11-05',
      movementDate: '2026-11-05',
      description: 'Legacy expense',
    });
    const onePostingEntry: JournalEntry = {
      id: 'e-one-leg',
      entryType: 'standard',
      description: 'Corrupt 1 leg',
      occurrenceDate: '2026-11-05',
      isVoided: false,
      createdAt: '2026-11-05T00:00:00Z',
    };
    const onePosting: Posting = {
      id: 'p-one-leg',
      entryId: 'e-one-leg',
      accountId: 'acc-cbe',
      amountCents: 5_000,
      direction: 'credit',
      accountMovementDate: '2026-11-05',
    };
    const missingAccEntry: JournalEntry = {
      id: 'e-missing-acc',
      entryType: 'standard',
      description: 'Missing account leg',
      occurrenceDate: '2026-11-05',
      isVoided: false,
      createdAt: '2026-11-05T00:00:00Z',
    };
    const missingAccPostings: Posting[] = [
      {
        id: 'p-miss-1',
        entryId: 'e-missing-acc',
        accountId: 'acc-deleted',
        amountCents: 5_000,
        direction: 'credit',
        accountMovementDate: '2026-11-05',
      },
      {
        id: 'p-miss-2',
        entryId: 'e-missing-acc',
        accountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
        amountCents: 5_000,
        direction: 'debit',
        accountMovementDate: '2026-11-05',
      },
    ];
    const legacyOffsetEntry: JournalEntry = {
      id: 'e-legacy-offset',
      entryType: 'adjustment',
      description: 'Legacy offset clearing',
      occurrenceDate: '2026-11-05',
      isVoided: false,
      createdAt: '2026-11-05T00:00:00Z',
    };
    const legacyOffsetPostings: Posting[] = [
      {
        id: 'p-off-1',
        entryId: 'e-legacy-offset',
        accountId: 'acc-cbe',
        amountCents: 50_000,
        direction: 'debit',
        accountMovementDate: '2026-11-05',
      },
      {
        id: 'p-off-2',
        entryId: 'e-legacy-offset',
        accountId: SYSTEM_CONTROL_ACCOUNT_IDS.legacyOffset,
        amountCents: 50_000,
        direction: 'credit',
        accountMovementDate: '2026-11-05',
      },
    ];

    const entries = [unvExp.entry, onePostingEntry, missingAccEntry, legacyOffsetEntry];
    const postings = [
      ...unvExp.postings,
      onePosting,
      ...missingAccPostings,
      ...legacyOffsetPostings,
    ];

    assert.equal(
      classifyJournalEntryCurrency({
        entry: unvExp.entry,
        entryPostings: unvExp.postings,
        accountById,
      }).status,
      'mixed_or_ambiguous'
    );
    assert.equal(
      classifyJournalEntryCurrency({
        entry: onePostingEntry,
        entryPostings: [onePosting],
        accountById,
      }).status,
      'mixed_or_ambiguous'
    );
    assert.equal(
      classifyJournalEntryCurrency({
        entry: missingAccEntry,
        entryPostings: missingAccPostings,
        accountById,
      }).status,
      'mixed_or_ambiguous'
    );
    assert.equal(
      classifyJournalEntryCurrency({
        entry: legacyOffsetEntry,
        entryPostings: legacyOffsetPostings,
        accountById,
      }).status,
      'mixed_or_ambiguous'
    );

    const audit = auditCurrencyIsolation({ accounts, entries, postings });
    assert.equal(audit.unverifiedAccountCount, 1);
    assert.equal(audit.currencyReviewEntryCount, 4);

    // acc-legacy-unv (100,000) excluded from ETB liquid cash and Net Position
    assert.equal(calculateLiquidCash(accounts, [], []), 50_000);
    assert.equal(calculateNetPosition(accounts, [], [], [], []), 50_000);

    // Cash flow & Occurrence exclude all 4
    const cf = generateCashFlowReport({
      accounts,
      entries,
      postings,
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    });
    assert.equal(cf.totalCashInflowCents, 0);
    assert.equal(cf.totalCashOutflowCents, 0);

    // New writes referencing acc-sys-legacy-offset rejected
    assert.throws(
      () =>
        assertEtbPostingAccounts({
          accounts,
          accountIds: [SYSTEM_CONTROL_ACCOUNT_IDS.legacyOffset],
        }),
      DoubleEntryValidationError
    );
  });

  it('Cases #8 & #9: Option 1 Prepaid Card Credit & Owed Card Debt include ETB cards and exclude USD cards', () => {
    const accountsPrepaid = ensureSystemControlAccounts([
      makeAccount('acc-cbe', 'CBE', 'ETB', 100_000),
      makeAccount('acc-card-etb', 'ETB Card', 'ETB', -15_000, {
        type: 'liability',
        subType: 'credit_card',
      }),
      makeAccount('acc-card-usd', 'USD Card', 'USD', -20_000, {
        type: 'liability',
        subType: 'credit_card',
      }),
    ]);

    const liquidPrepaid = calculateLiquidCash(accountsPrepaid, [], []);
    const prepaidCredit = calculatePrepaidCardCredit(accountsPrepaid, [], []);
    const cardOwedPrepaid = calculateShortTermCreditOwed(accountsPrepaid, [], []);
    assert.equal(liquidPrepaid, 100_000);
    assert.equal(prepaidCredit, 15_000);
    assert.equal(cardOwedPrepaid, 0);
    assert.equal(calculateNetPosition(accountsPrepaid, [], [], [], []), 115_000);
    assert.equal(
      calculateAvailableToSpend({
        liquidCashCents: liquidPrepaid,
        prepaidCardCreditCents: prepaidCredit,
        shortTermCreditOwedCents: cardOwedPrepaid,
        unpaidPayablesDueInPeriodCents: 0,
        reservedSavingsCents: 0,
      }),
      115_000
    );

    const accountsOwed = ensureSystemControlAccounts([
      makeAccount('acc-cbe', 'CBE', 'ETB', 100_000),
      makeAccount('acc-card-etb', 'ETB Card', 'ETB', 30_000, {
        type: 'liability',
        subType: 'credit_card',
      }),
      makeAccount('acc-card-usd', 'USD Card', 'USD', 10_000, {
        type: 'liability',
        subType: 'credit_card',
      }),
    ]);

    const liquidOwed = calculateLiquidCash(accountsOwed, [], []);
    const prepaidOwedCase = calculatePrepaidCardCredit(accountsOwed, [], []);
    const cardOwed = calculateShortTermCreditOwed(accountsOwed, [], []);
    assert.equal(prepaidOwedCase, 0);
    assert.equal(cardOwed, 30_000);
    assert.equal(calculateNetPosition(accountsOwed, [], [], [], []), 70_000);
    assert.equal(
      calculateAvailableToSpend({
        liquidCashCents: liquidOwed,
        prepaidCardCreditCents: prepaidOwedCase,
        shortTermCreditOwedCents: cardOwed,
        unpaidPayablesDueInPeriodCents: 0,
        reservedSavingsCents: 0,
      }),
      70_000
    );
  });

  it('Case #10: ETB split expense contributes to ETB expense & receivable while USD split expense is excluded', () => {
    const accounts = ensureSystemControlAccounts([
      makeAccount('acc-cbe', 'CBE', 'ETB', 100_000),
      makeAccount('acc-usd', 'USD Bank', 'USD', 50_000),
    ]);
    const splitEtb = buildSplitExpense({
      entryId: 'e-split-etb',
      debtId: 'd-split-etb',
      partyId: 'p-1',
      myExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      receivableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      paidAssetAccountId: 'acc-cbe',
      myShareCents: 10_000,
      theirShareCents: 20_000,
      categoryId: 'cat-food',
      occurrenceDate: '2026-11-05',
      description: 'ETB Dinner Split',
    });
    const splitUsd = buildSplitExpense({
      entryId: 'e-split-usd',
      debtId: 'd-split-usd',
      partyId: 'p-1',
      myExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      receivableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      paidAssetAccountId: 'acc-usd',
      myShareCents: 5_000,
      theirShareCents: 10_000,
      categoryId: 'cat-food',
      occurrenceDate: '2026-11-05',
      description: 'USD Dinner Split',
    });

    const entries = [splitEtb.entry, splitUsd.entry];
    const postings = [...splitEtb.postings, ...splitUsd.postings];
    const debts = [splitEtb.debt, splitUsd.debt];
    const cls = classifyAllJournalEntries({ accounts, entries, postings, debts });

    assert.equal(cls.get('e-split-etb')?.status, 'eligible_etb');
    assert.equal(cls.get('e-split-usd')?.status, 'excluded_non_etb');
    assert.equal(cls.get('e-split-usd')?.nativeCurrencyCode, 'USD');

    const occ = generateOccurrenceReport({
      accounts,
      entries,
      postings,
      debts,
      categories: [],
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    });
    assert.equal(occ.totalExpenseCents, 10_000);
    assert.equal(
      calculateTotalReceivables(debts, { accounts, entries, postings }),
      20_000
    );

    const audit = auditCurrencyIsolation({ accounts, entries, postings, debts });
    assert.equal(audit.excludedNonEtbDebtCount, 1);
  });

  it('Cases #11, #12 & #13: Unsettled system-only third_party classifies as mixed_or_ambiguous, and reverses to ETB or USD upon verified settlement', () => {
    const accounts = ensureSystemControlAccounts([
      makeAccount('acc-cbe', 'CBE', 'ETB', 100_000),
      makeAccount('acc-usd', 'USD Bank', 'USD', 50_000),
    ]);
    const thirdParty = buildThirdPartyPaidExpense({
      entryId: 'e-tp-jan30',
      debtId: 'd-tp-jan30',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      payableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.payable,
      categoryId: 'cat-food',
      partyId: 'p-friend',
      amountCents: 50_000,
      occurrenceDate: '2026-01-30',
      dueDate: '2026-02-10',
      description: 'Friend covered bill',
    });

    // Case #11: Unsettled -> mixed_or_ambiguous, 0 ETB expense & 0 DuePayables
    const clsUnsettled = classifyAllJournalEntries({
      accounts,
      entries: [thirdParty.entry],
      postings: thirdParty.postings,
      debts: [thirdParty.debt],
    });
    assert.equal(clsUnsettled.get('e-tp-jan30')?.status, 'mixed_or_ambiguous');
    assert.equal(
      generateOccurrenceReport({
        accounts,
        entries: [thirdParty.entry],
        postings: thirdParty.postings,
        debts: [thirdParty.debt],
        categories: [],
        startDate: '2026-01-01',
        endDate: '2026-01-31',
      }).totalExpenseCents,
      0
    );
    assert.equal(
      calculateAvailableToSpendBreakdownV7({
        accounts,
        postings: thirdParty.postings,
        entries: [thirdParty.entry],
        debts: [thirdParty.debt],
        commitments: [],
        commitmentSettlements: [],
        savingsGoals: [],
        planningPeriodEndIso: '2026-02-28',
      }).duePayablesCents,
      0
    );
    const auditUnsettled = auditCurrencyIsolation({
      accounts,
      entries: [thirdParty.entry],
      postings: thirdParty.postings,
      debts: [thirdParty.debt],
    });
    assert.equal(auditUnsettled.currencyReviewEntryCount, 1);
    assert.equal(auditUnsettled.excludedNonEtbDebtCount, 1);

    // Case #12: Settled in ETB (partial 20,000) -> origin flips to eligible_etb, Tier A matches 30,000
    const etbSettle = buildDebtSettlement({
      settlementEntryId: 'e-tp-settle-etb',
      debt: thirdParty.debt,
      settlementAccountId: 'acc-cbe',
      debtAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.payable,
      allocatedPrincipalCents: 20_000,
      settlementDate: '2026-02-02',
      description: 'Partial ETB repayment',
    });
    const etbEntries = [thirdParty.entry, etbSettle.entry];
    const etbPostings = [...thirdParty.postings, ...etbSettle.postings];
    const etbDebts = [etbSettle.updatedDebt];
    const etbAllocs = [etbSettle.allocation];

    const clsEtb = classifyAllJournalEntries({
      accounts,
      entries: etbEntries,
      postings: etbPostings,
      debts: etbDebts,
      allocations: etbAllocs,
    });
    assert.equal(clsEtb.get('e-tp-jan30')?.status, 'eligible_etb');
    assert.equal(clsEtb.get('e-tp-settle-etb')?.status, 'eligible_etb');
    assert.equal(
      generateOccurrenceReport({
        accounts,
        entries: etbEntries,
        postings: etbPostings,
        debts: etbDebts,
        allocations: etbAllocs,
        categories: [],
        startDate: '2026-01-01',
        endDate: '2026-01-31',
      }).totalExpenseCents,
      50_000
    );
    const v7Check = verifyFinanceV7Integrity({
      accounts,
      entries: etbEntries,
      postings: etbPostings,
      debts: etbDebts,
      commitments: [],
      allocations: etbAllocs,
    });
    assert.equal(v7Check.debtControlAudit.activePayableSumCents, 30_000);
    assert.equal(v7Check.debtControlAudit.payableControlBalanceCents, 30_000);
    assert.equal(v7Check.debtControlAudit.isTierABalanced, true);

    // Case #13: Settled in USD -> origin flips to excluded_non_etb('USD'), 0 ETB expense & 0 ETB payable
    const usdSettle = buildDebtSettlement({
      settlementEntryId: 'e-tp-settle-usd',
      debt: thirdParty.debt,
      settlementAccountId: 'acc-usd',
      debtAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.payable,
      allocatedPrincipalCents: 20_000,
      settlementDate: '2026-02-02',
      description: 'USD repayment',
    });
    const usdEntries = [thirdParty.entry, usdSettle.entry];
    const usdPostings = [...thirdParty.postings, ...usdSettle.postings];
    const usdDebts = [usdSettle.updatedDebt];
    const usdAllocs = [usdSettle.allocation];

    const clsUsd = classifyAllJournalEntries({
      accounts,
      entries: usdEntries,
      postings: usdPostings,
      debts: usdDebts,
      allocations: usdAllocs,
    });
    assert.equal(clsUsd.get('e-tp-jan30')?.status, 'excluded_non_etb');
    assert.equal(clsUsd.get('e-tp-jan30')?.nativeCurrencyCode, 'USD');
    assert.equal(clsUsd.get('e-tp-settle-usd')?.status, 'excluded_non_etb');
    assert.equal(clsUsd.get('e-tp-settle-usd')?.nativeCurrencyCode, 'USD');
    assert.equal(
      generateOccurrenceReport({
        accounts,
        entries: usdEntries,
        postings: usdPostings,
        debts: usdDebts,
        allocations: usdAllocs,
        categories: [],
        startDate: '2026-01-01',
        endDate: '2026-01-31',
      }).totalExpenseCents,
      0
    );
    assert.equal(
      calculateTotalPayables(usdDebts, {
        accounts,
        entries: usdEntries,
        postings: usdPostings,
        allocations: usdAllocs,
      }),
      0
    );
  });

  it('Case #14: Cross-currency debt settlement (USD debt settled on ETB account) is blocked on write and flagged mixed_or_ambiguous if imported', () => {
    const accounts = ensureSystemControlAccounts([
      makeAccount('acc-cbe', 'CBE', 'ETB', 100_000),
      makeAccount('acc-usd', 'USD Bank', 'USD', 50_000),
    ]);
    const lendUsd = buildLendMoney({
      entryId: 'e-lend-usd',
      debtId: 'd-usd-rec',
      partyId: 'p-1',
      receivableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      sourceAssetAccountId: 'acc-usd',
      amountCents: 10_000,
      date: '2026-11-01',
      description: 'USD Loan',
    });

    assert.throws(
      () =>
        assertEtbDebtEligible({
          debt: lendUsd.debt,
          accounts,
          entries: [lendUsd.entry],
          postings: lendUsd.postings,
        }),
      DoubleEntryValidationError
    );

    // Imported cross-currency settlement
    const badSettle = buildDebtSettlement({
      settlementEntryId: 'e-bad-fx-settle',
      debt: lendUsd.debt,
      settlementAccountId: 'acc-cbe',
      debtAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      allocatedPrincipalCents: 10_000,
      settlementDate: '2026-11-05',
      description: 'Cross-currency settlement',
    });

    const entries = [lendUsd.entry, badSettle.entry];
    const postings = [...lendUsd.postings, ...badSettle.postings];
    const debts = [badSettle.updatedDebt];
    const allocs = [badSettle.allocation];

    const cls = classifyAllJournalEntries({
      accounts,
      entries,
      postings,
      debts,
      allocations: allocs,
    });
    assert.equal(cls.get('e-lend-usd')?.status, 'excluded_non_etb');
    assert.equal(cls.get('e-bad-fx-settle')?.status, 'mixed_or_ambiguous');
    assert.equal(isDebtEligibleEtb(badSettle.updatedDebt, new Map(entries.map((e) => [e.id, e])), cls), false);
  });

  it('Cases #15 & #16: Voided USD entry, system-only correction chain, and USD write-off inherit USD and never leak into ETB', () => {
    const accounts = ensureSystemControlAccounts([
      makeAccount('acc-cbe', 'CBE', 'ETB', 100_000),
      makeAccount('acc-usd', 'USD Bank', 'USD', 50_000),
    ]);

    const origUsd = buildDirectExpense({
      id: 'e-orig-usd',
      assetAccountId: 'acc-usd',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      amountCents: 5_000,
      occurrenceDate: '2026-11-02',
      movementDate: '2026-11-02',
      description: 'Voided USD expense',
    });
    const voidedOrig = buildVoidEntry(origUsd.entry, 'Superseded').updatedEntry;
    const systemOnlyCorrection: JournalEntry = {
      id: 'e-sys-corr',
      entryType: 'adjustment',
      description: 'System correction',
      occurrenceDate: '2026-11-02',
      isVoided: false,
      correctedFromEntryId: voidedOrig.id,
      createdAt: '2026-11-02T01:00:00Z',
    };
    const corrPostings: Posting[] = [
      {
        id: 'p-corr-1',
        entryId: 'e-sys-corr',
        accountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
        amountCents: 5_000,
        direction: 'debit',
        accountMovementDate: '2026-11-02',
      },
      {
        id: 'p-corr-2',
        entryId: 'e-sys-corr',
        accountId: SYSTEM_CONTROL_ACCOUNT_IDS.equity,
        amountCents: 5_000,
        direction: 'credit',
        accountMovementDate: '2026-11-02',
      },
    ];

    // Case #16: USD debt write-off
    const usdLoan = buildLendMoney({
      entryId: 'e-usd-loan',
      debtId: 'd-usd-wo',
      partyId: 'p-1',
      receivableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      sourceAssetAccountId: 'acc-usd',
      amountCents: 8_000,
      date: '2026-11-01',
      description: 'USD loan',
    });
    const usdWriteOff = buildDebtWriteOff({
      writeOffEntryId: 'e-usd-wo',
      debt: usdLoan.debt,
      debtAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      writeOffAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      writeOffCents: 8_000,
      date: '2026-11-05',
      reason: 'Uncollectible',
    });

    const entries = [voidedOrig, systemOnlyCorrection, usdLoan.entry, usdWriteOff.entry];
    const postings = [
      ...origUsd.postings,
      ...corrPostings,
      ...usdLoan.postings,
      ...usdWriteOff.postings,
    ];
    const debts = [usdWriteOff.updatedDebt];

    const cls = classifyAllJournalEntries({ accounts, entries, postings, debts });
    assert.equal(cls.get('e-orig-usd')?.status, 'inactive_or_voided');
    assert.equal(cls.get('e-orig-usd')?.nativeCurrencyCode, 'USD');
    assert.equal(cls.get('e-sys-corr')?.status, 'excluded_non_etb');
    assert.equal(cls.get('e-sys-corr')?.nativeCurrencyCode, 'USD');
    assert.equal(cls.get('e-usd-wo')?.status, 'excluded_non_etb');
    assert.equal(cls.get('e-usd-wo')?.nativeCurrencyCode, 'USD');

    const occ = generateOccurrenceReport({
      accounts,
      entries,
      postings,
      debts,
      categories: [],
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    });
    assert.equal(occ.totalExpenseCents, 0);
    assert.equal(calculateNetPosition(accounts, postings, debts, entries, []), 100_000);

    assert.throws(
      () =>
        assertEtbDebtEligible({
          debt: usdLoan.debt,
          accounts,
          entries,
          postings,
        }),
      DoubleEntryValidationError
    );
  });

  it('Cases #17, #18 & #19: Unlinked commitments, recurring rule commitments, and expected inflows obey Decisions E/F & 5D', () => {
    const accounts = ensureSystemControlAccounts([
      makeAccount('acc-cbe', 'CBE', 'ETB', 100_000),
    ]);
    const accountById = new Map(accounts.map((a) => [a.id, a]));
    const rules: SharedRecurringRule[] = [
      {
        id: 'r-empty',
        title: 'Unlinked Recurring',
        ruleType: 'expense',
        amountCents: 15_000,
        frequency: 'monthly',
        interval: 1,
        startDate: '2026-11-01',
        nextOccurrenceDate: '2026-11-10',
        autoPost: false,
        isActive: true,
        createdAt: '2026-11-01T00:00:00Z',
      },
      {
        id: 'r-cbe',
        title: 'CBE Recurring',
        ruleType: 'expense',
        amountCents: 20_000,
        accountId: 'acc-cbe',
        frequency: 'monthly',
        interval: 1,
        startDate: '2026-11-01',
        nextOccurrenceDate: '2026-11-10',
        autoPost: false,
        isActive: true,
        createdAt: '2026-11-01T00:00:00Z',
      },
    ];
    const ruleById = new Map(rules.map((r) => [r.id, r]));

    const cUnlinked: SharedCommitment = {
      id: 'c-unlinked',
      title: 'Historical Rent',
      amountCents: 40_000,
      dueDate: '2026-11-12',
      isPaid: false,
      direction: 'outflow',
    };
    const cEmptyRule: SharedCommitment = {
      id: 'c-rule-empty',
      title: 'Unlinked Rule Bill',
      amountCents: 15_000,
      dueDate: '2026-11-12',
      isPaid: false,
      direction: 'outflow',
      recurringRuleId: 'r-empty',
    };
    const cEtbRule: SharedCommitment = {
      id: 'c-rule-cbe',
      title: 'CBE Rule Bill',
      amountCents: 20_000,
      dueDate: '2026-11-12',
      isPaid: false,
      direction: 'outflow',
      recurringRuleId: 'r-cbe',
    };
    const cInflow: SharedCommitment = {
      id: 'c-inflow',
      title: 'Expected Salary Bonus',
      amountCents: 500_000,
      dueDate: '2026-11-15',
      isPaid: false,
      direction: 'inflow',
      linkedAccountId: 'acc-cbe',
    };

    const resUnlinked = resolveCommitmentCurrencyStatus({ commitment: cUnlinked, accountById, ruleById });
    const resEmptyRule = resolveCommitmentCurrencyStatus({ commitment: cEmptyRule, accountById, ruleById });
    const resEtbRule = resolveCommitmentCurrencyStatus({ commitment: cEtbRule, accountById, ruleById });
    const resInflow = resolveCommitmentCurrencyStatus({ commitment: cInflow, accountById, ruleById });

    assert.equal(resUnlinked.status, 'needs_review');
    assert.equal(resUnlinked.isUnlinkedAssumedEtb, false);
    assert.equal(resEmptyRule.status, 'needs_review');
    assert.equal(resEtbRule.status, 'eligible_etb');
    assert.equal(resInflow.status, 'eligible_etb');

    const beforeSettle = calculateAvailableToSpendBreakdownV7({
      accounts,
      postings: [],
      entries: [],
      debts: [],
      commitments: [cUnlinked, cEmptyRule, cEtbRule, cInflow],
      commitmentSettlements: [],
      recurringRules: rules,
      savingsGoals: [],
      planningPeriodEndIso: '2026-11-30',
    });
    assert.equal(beforeSettle.dueNonDebtCommitmentsCents, 20_000);
    assert.equal(beforeSettle.liquidCashCents, 100_000);
    assert.equal(beforeSettle.availableToSpendCents, 80_000);
    assert.equal(beforeSettle.netFinancialPositionCents, 100_000);

    // Settling expected inflow increases cash & income
    const settledInflow = recordCommitmentSettlementV7({
      commitment: cInflow,
      accountId: 'acc-cbe',
      amountCents: 500_000,
      settledDateIso: '2026-11-15',
      existingSettlements: [],
      entries: [],
      accounts,
    });
    assert.equal(
      calculateLiquidCash(accounts, settledInflow.postings, [settledInflow.entry]),
      600_000
    );
    assert.equal(
      generateOccurrenceReport({
        accounts,
        entries: [settledInflow.entry],
        postings: settledInflow.postings,
        categories: [],
        startDate: '2026-11-01',
        endDate: '2026-11-30',
      }).totalIncomeCents,
      500_000
    );
  });

  it('Case #20: Vault-linked ETB goal vs USD vault goal vs virtual savings goal', () => {
    const accounts = ensureSystemControlAccounts([
      makeAccount('acc-cbe', 'CBE', 'ETB', 100_000),
      makeAccount('acc-vault-etb', 'ETB Vault', 'ETB', 50_000, { subType: 'savings_vault' }),
      makeAccount('acc-vault-usd', 'USD Vault', 'USD', 20_000, { subType: 'savings_vault' }),
    ]);
    const goals: SharedSavingsGoal[] = [
      {
        id: 'sav-etb',
        title: 'ETB Vault Goal',
        targetCents: 100_000,
        currentAllocatedCents: 50_000,
        linkedAccountId: 'acc-vault-etb',
        status: 'active',
      },
      {
        id: 'sav-usd',
        title: 'USD Vault Goal',
        targetCents: 100_000,
        currentAllocatedCents: 20_000,
        linkedAccountId: 'acc-vault-usd',
        status: 'active',
      },
      {
        id: 'sav-virtual',
        title: 'Virtual Goal',
        targetCents: 50_000,
        currentAllocatedCents: 10_000,
        status: 'active',
      },
    ];

    const breakdown = calculateAvailableToSpendBreakdownV7({
      accounts,
      postings: [],
      entries: [],
      debts: [],
      commitments: [],
      commitmentSettlements: [],
      savingsGoals: goals,
      planningPeriodEndIso: '2026-11-30',
    });
    assert.equal(breakdown.liquidCashCents, 100_000);
    assert.equal(breakdown.vaultSavingsCents, 50_000);
    assert.equal(breakdown.virtualSavingsReservedCents, 10_000);
    assert.equal(breakdown.availableToSpendCents, 90_000);

    // USD vault goal funding is rejected
    assert.throws(
      () =>
        fundSavingsGoalV7({
          goal: goals[1],
          amountCents: 5_000,
          sourceAccountId: 'acc-cbe',
          dateIso: '2026-11-10',
          accounts,
        }),
      DoubleEntryValidationError
    );
  });

  it('Cases #21 & #22: Occurrence Date vs Account Movement Date separation and Ethiopian Calendar month + Horizon H filtering', () => {
    const accounts = ensureSystemControlAccounts([
      makeAccount('acc-cbe', 'CBE', 'ETB', 100_000),
    ]);
    const categories = [
      { id: 'cat-food', name: 'Food', type: 'expense' as const, colorHex: '#00AA00', isDefault: true },
    ];
    const delayedCashExpense = buildDirectExpense({
      id: 'e-oct-occ-nov-mov',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 10_000,
      occurrenceDate: '2026-10-28',
      movementDate: '2026-11-02',
      description: 'Oct bill debited Nov 2',
    });

    // Case #21: Oct P&L and Budget include it; Nov P&L excludes it; Nov Cash Flow includes it; Oct Cash Flow excludes it
    const octOcc = generateOccurrenceReport({
      accounts,
      entries: [delayedCashExpense.entry],
      postings: delayedCashExpense.postings,
      categories,
      startDate: '2026-10-01',
      endDate: '2026-10-31',
    });
    const novOcc = generateOccurrenceReport({
      accounts,
      entries: [delayedCashExpense.entry],
      postings: delayedCashExpense.postings,
      categories,
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    });
    assert.equal(octOcc.totalExpenseCents, 10_000);
    assert.equal(novOcc.totalExpenseCents, 0);

    const octBudget = calculateBudgetStatus(
      [{ categoryId: 'cat-food', categoryName: 'Food', limitCents: 20_000 }],
      octOcc
    );
    const novBudget = calculateBudgetStatus(
      [{ categoryId: 'cat-food', categoryName: 'Food', limitCents: 20_000 }],
      novOcc
    );
    assert.equal(octBudget[0].spentCents, 10_000);
    assert.equal(novBudget[0].spentCents, 0);

    const octCf = generateCashFlowReport({
      accounts,
      entries: [delayedCashExpense.entry],
      postings: delayedCashExpense.postings,
      startDate: '2026-10-01',
      endDate: '2026-10-31',
    });
    const novCf = generateCashFlowReport({
      accounts,
      entries: [delayedCashExpense.entry],
      postings: delayedCashExpense.postings,
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    });
    assert.equal(octCf.totalCashOutflowCents, 0);
    assert.equal(novCf.totalCashOutflowCents, 10_000);

    // Case #22: Ethiopian Calendar Meskerem 2019 bounds + Horizon H filtering
    const meskeremStart = CalendarDate.fromEthiopian(2019, 1, 1);
    const meskeremEnd = meskeremStart.endOfEthiopianMonth;
    const meskeremExpense = buildDirectExpense({
      id: 'e-meskerem',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      amountCents: 7_500,
      occurrenceDate: meskeremStart.toIsoString(),
      movementDate: meskeremStart.toIsoString(),
      description: 'Meskerem 1 Expense',
    });
    const meskeremOcc = generateOccurrenceReport({
      accounts,
      entries: [meskeremExpense.entry],
      postings: meskeremExpense.postings,
      categories: [],
      startDate: meskeremStart.toIsoString(),
      endDate: meskeremEnd.toIsoString(),
    });
    assert.equal(meskeremOcc.totalExpenseCents, 7_500);

    const commitments: SharedCommitment[] = [
      {
        id: 'cm-nov',
        title: 'Nov Bill',
        amountCents: 20_000,
        dueDate: '2026-11-20',
        isPaid: false,
        direction: 'outflow',
        linkedAccountId: 'acc-cbe',
      },
      {
        id: 'cm-dec',
        title: 'Dec Bill',
        amountCents: 30_000,
        dueDate: '2026-12-10',
        isPaid: false,
        direction: 'outflow',
        linkedAccountId: 'acc-cbe',
      },
    ];
    const hNov = calculateAvailableToSpendBreakdownV7({
      accounts,
      postings: [],
      entries: [],
      debts: [],
      commitments,
      commitmentSettlements: [],
      savingsGoals: [],
      planningPeriodEndIso: '2026-11-30',
    });
    const hDec = calculateAvailableToSpendBreakdownV7({
      accounts,
      postings: [],
      entries: [],
      debts: [],
      commitments,
      commitmentSettlements: [],
      savingsGoals: [],
      planningPeriodEndIso: '2026-12-31',
    });
    assert.equal(hNov.availableToSpendCents, 80_000);
    assert.equal(hDec.availableToSpendCents, 50_000);
  });

  it('Case #23: Decision A write validation locks block non-ETB, unverified, archived accounts, cross-currency debts, unlinked commitments, USD goals & auto-downgrade USD recurring rules', () => {
    const accounts = ensureSystemControlAccounts([
      makeAccount('acc-cbe', 'CBE', 'ETB', 100_000),
      makeAccount('acc-usd', 'USD Account', 'USD', 50_000),
      makeAccount('acc-unv', 'Unverified Account', '', 10_000),
      makeAccount('acc-arch', 'Archived ETB', 'ETB', 20_000, { isArchived: true }),
      makeAccount('acc-vault-usd', 'USD Vault', 'USD', 30_000, { subType: 'savings_vault' }),
    ]);

    assert.throws(() => assertVerifiedEtbAccount(accounts.find((a) => a.id === 'acc-usd')), DoubleEntryValidationError);
    assert.throws(() => assertVerifiedEtbAccount(accounts.find((a) => a.id === 'acc-unv')), DoubleEntryValidationError);
    assert.throws(() => assertVerifiedEtbAccount(accounts.find((a) => a.id === 'acc-arch')), DoubleEntryValidationError);
    assert.throws(
      () =>
        assertEtbPostingAccounts({
          accounts,
          accountIds: ['acc-cbe', 'acc-usd'],
        }),
      DoubleEntryValidationError
    );

    // Simple transaction validation blocks USD account
    const simpleRes = validateSimpleTransaction(
      'expense',
      1_000,
      'acc-usd',
      'cat-food',
      undefined,
      '2026-11-10',
      accounts
    );
    assert.equal(simpleRes.isValid, false);

    // Opening balance revision blocks USD account unless legacy override is explicitly passed
    const usdAcc = accounts.find((a) => a.id === 'acc-usd')!;
    assert.throws(
      () =>
        reviseAccountOpeningBalanceV7({
          account: usdAcc,
          newOpeningBalanceCents: 99_000,
          newOpeningDateIso: '2026-11-01',
          entries: [],
          postings: [],
        }),
      DoubleEntryValidationError
    );

    // Unlinked commitment settlement blocked
    assert.throws(
      () =>
        recordCommitmentSettlementV7({
          commitment: {
            id: 'c-unlinked',
            title: 'Unlinked',
            amountCents: 5_000,
            dueDate: '2026-11-10',
            isPaid: false,
            direction: 'outflow',
          },
          accountId: 'acc-cbe',
          amountCents: 5_000,
          settledDateIso: '2026-11-10',
          existingSettlements: [],
          entries: [],
          accounts,
        }),
      DoubleEntryValidationError
    );

    // Non-ETB debt settlement / write-off eligibility check throws
    const usdLoan = buildLendMoney({
      entryId: 'e-loan-usd',
      debtId: 'd-loan-usd',
      partyId: 'p-1',
      receivableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      sourceAssetAccountId: 'acc-usd',
      amountCents: 5_000,
      date: '2026-11-01',
      description: 'USD loan',
    });
    assert.throws(
      () =>
        assertEtbDebtEligible({
          debt: usdLoan.debt,
          accounts,
          entries: [usdLoan.entry],
          postings: usdLoan.postings,
        }),
      DoubleEntryValidationError
    );

    // Legacy USD recurring rule auto-downgraded during due processing
    const usdRule: SharedRecurringRule = {
      id: 'r-usd-legacy',
      title: 'USD Subscription',
      ruleType: 'expense',
      amountCents: 1_500,
      accountId: 'acc-usd',
      frequency: 'monthly',
      interval: 1,
      startDate: '2026-11-01',
      nextOccurrenceDate: '2026-11-01',
      autoPost: true,
      isActive: true,
      createdAt: '2026-11-01T00:00:00Z',
    };
    const recRes = processDueRecurringRulesV7({
      rules: [usdRule],
      todayIso: '2026-11-10',
      accounts,
    });
    assert.equal(recRes.createdEntries.length, 0);
    assert.deepEqual(recRes.skippedRuleIds, ['r-usd-legacy']);
    assert.equal(recRes.updatedRules[0].autoPost, false);
    assert.ok(recRes.warnings.length >= 1);
  });

  it('Case #24: Export workbook, ZIP SQLite views/CSVs, and SharedStateBridge ETB opening balance enforce strict isolation', async () => {
    const accounts = ensureSystemControlAccounts([
      makeAccount('acc-cbe', 'CBE ETB', 'ETB', 100_000),
      makeAccount('acc-card-etb', 'Prepaid Card', 'ETB', -15_000, {
        type: 'liability',
        subType: 'credit_card',
      }),
      makeAccount('acc-usd', 'USD Account', 'USD', 50_000),
    ]);
    const usdExp = buildDirectExpense({
      id: 'e-exp-usd',
      assetAccountId: 'acc-usd',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      amountCents: 4_000,
      occurrenceDate: '2026-11-05',
      movementDate: '2026-11-05',
      description: 'USD expense',
    });
    const unsettledTp = buildThirdPartyPaidExpense({
      entryId: 'e-tp-unsettled',
      debtId: 'd-tp-unsettled',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      payableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.payable,
      partyId: 'p-1',
      amountCents: 6_000,
      occurrenceDate: '2026-11-06',
      description: 'Unsettled third-party',
    });
    const unlinkedCommitment: SharedCommitment = {
      id: 'cm-unlinked',
      title: 'Unlinked Bill',
      amountCents: 20_000,
      dueDate: '2026-11-15',
      isPaid: false,
      direction: 'outflow',
    };

    const payload = {
      accounts,
      parties: [makeParty('p-1')],
      entries: [usdExp.entry, unsettledTp.entry],
      postings: [...usdExp.postings, ...unsettledTp.postings],
      debts: [unsettledTp.debt],
      settlementAllocations: [],
      categories: [],
      reservedSavingsCents: 0,
      commitments: [unlinkedCommitment],
      planningPeriodEndIso: '2026-11-30',
    };

    const excelBytes = DataPortabilityService.generateExcelWorkbook(payload);
    const wb = XLSX.read(excelBytes, { type: 'array' });
    const summaryRows = XLSX.utils.sheet_to_json<Record<string, any>>(
      wb.Sheets['Executive_Summary'],
      {
        header: 1,
      }
    ) as any[][];
    const availRow = summaryRows.find((r) => String(r[0]).includes('Available-to-Spend (ETB Option 1)'));
    assert.ok(availRow, 'Expected Option 1 Available-to-Spend row in Excel Summary');
    assert.equal(availRow[1], 115_000);

    const { blob } = await DataPortabilityService.createExportZipBundle(payload);
    const zip = await JSZip.loadAsync(await blob.arrayBuffer());
    const sqlText = await zip.file('sqlite/finance_export.sql')!.async('string');
    assert.ok(sqlText.includes("acc-sys-legacy-offset"));
    assert.ok(sqlText.includes("UPPER(TRIM(COALESCE(ax.currency_code, ''))) != 'ETB'"));

    const entriesCsv = await zip.file('csv/journal_entries.csv')!.async('string');
    assert.ok(entriesCsv.includes('EXCLUDED_USD'));
    assert.ok(entriesCsv.includes('CURRENCY_REVIEW'));

    const debtsCsv = await zip.file('csv/debts.csv')!.async('string');
    assert.ok(debtsCsv.includes('CURRENCY_REVIEW'));

    withMockBrowserStorage((store) => {
      store.set(
        'daywell_accounts',
        JSON.stringify([
          makeAccount('acc-cbe', 'CBE', 'ETB', 100_000),
          makeAccount('acc-usd', 'USD', 'USD', 50_000),
        ])
      );
      const liveState = SharedStateBridge.assembleLiveDatabaseState();
      assert.equal(liveState.openingBalanceCents, 100_000);
      const exported = JSON.parse(SharedStateBridge.exportToAndroidJson(liveState));
      assert.equal(exported.openingBalanceCents, 100_000);
    });
  });

  it('Case #25: Cross-Platform Canonical Parity Fixture matches exact 8 breakdown fields, Net Worth, P&L, and audit counters', () => {
    const accounts = ensureSystemControlAccounts([
      makeAccount('acc-cbe', 'CBE', 'ETB', 90_000),
      makeAccount('acc-vault-etb', 'ETB Vault', 'ETB', 50_000, { subType: 'savings_vault' }),
      makeAccount('acc-card-etb', 'ETB Card', 'ETB', -15_000, {
        type: 'liability',
        subType: 'credit_card',
      }),
      makeAccount('acc-usd', 'USD Travel', 'USD', 20_000),
    ]);
    const expEtb = buildDirectExpense({
      id: 'e-par-exp',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      amountCents: 10_000,
      occurrenceDate: '2026-11-05',
      movementDate: '2026-11-05',
      description: 'Groceries',
    });
    const incEtb = buildDirectIncome({
      id: 'e-par-inc',
      assetAccountId: 'acc-cbe',
      incomeAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.income,
      amountCents: 20_000,
      occurrenceDate: '2026-11-06',
      movementDate: '2026-11-06',
      description: 'Bonus',
    });
    // CBE ending balance = 90,000 - 10,000 + 20,000 = 100,000
    const expUsd = buildDirectExpense({
      id: 'e-par-usd',
      assetAccountId: 'acc-usd',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      amountCents: 3_000,
      occurrenceDate: '2026-11-07',
      movementDate: '2026-11-07',
      description: 'USD SaaS',
    });
    const unsettledTp = buildThirdPartyPaidExpense({
      entryId: 'e-par-tp',
      debtId: 'd-par-tp',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      payableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.payable,
      partyId: 'p-1',
      amountCents: 8_000,
      occurrenceDate: '2026-11-08',
      dueDate: '2026-11-20',
      description: 'Ambiguous TP',
    });
    const etbBorrow = buildBorrowMoney({
      entryId: 'e-par-borrow',
      debtId: 'd-par-etb',
      partyId: 'p-1',
      destAssetAccountId: 'acc-cbe',
      payableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.payable,
      amountCents: 5_000,
      date: '2026-11-09',
      dueDate: '2026-11-25',
      description: 'ETB short loan',
    });
    // CBE ending = 100,000 + 5,000 = 105,000
    const commitments: SharedCommitment[] = [
      {
        id: 'cm-par-etb',
        title: 'Rent',
        amountCents: 20_000,
        dueDate: '2026-11-15',
        isPaid: false,
        direction: 'outflow',
        linkedAccountId: 'acc-cbe',
      },
      {
        id: 'cm-par-unlinked',
        title: 'Unlinked Legacy',
        amountCents: 12_000,
        dueDate: '2026-11-16',
        isPaid: false,
        direction: 'outflow',
      },
      {
        id: 'cm-par-inflow',
        title: 'Expected Inflow',
        amountCents: 40_000,
        dueDate: '2026-11-18',
        isPaid: false,
        direction: 'inflow',
        linkedAccountId: 'acc-cbe',
      },
    ];
    const savingsGoals: SharedSavingsGoal[] = [
      {
        id: 'sav-par-virt',
        title: 'Virtual Reserve',
        targetCents: 50_000,
        currentAllocatedCents: 10_000,
        status: 'active',
      },
    ];

    const entries = [
      expEtb.entry,
      incEtb.entry,
      expUsd.entry,
      unsettledTp.entry,
      etbBorrow.entry,
    ];
    const postings = [
      ...expEtb.postings,
      ...incEtb.postings,
      ...expUsd.postings,
      ...unsettledTp.postings,
      ...etbBorrow.postings,
    ];
    const debts = [unsettledTp.debt, etbBorrow.debt];

    const b = calculateAvailableToSpendBreakdownV7({
      accounts,
      postings,
      entries,
      debts,
      commitments,
      commitmentSettlements: [],
      savingsGoals,
      planningPeriodEndIso: '2026-11-30',
    });

    assert.equal(b.liquidCashCents, 105_000);
    assert.equal(b.prepaidCardCreditCents, 15_000);
    assert.equal(b.shortTermCreditOwedCents, 0);
    assert.equal(b.vaultSavingsCents, 50_000);
    assert.equal(b.duePayablesCents, 5_000);
    assert.equal(b.dueNonDebtCommitmentsCents, 20_000);
    assert.equal(b.virtualSavingsReservedCents, 10_000);
    // 105,000 + 15,000 - 0 - 5,000 - 20,000 - 10,000 = 85,000
    assert.equal(b.availableToSpendCents, 85_000);
    // (105,000 + 50,000) - (-15,000) - 5,000 = 165,000
    assert.equal(b.netFinancialPositionCents, 165_000);
    assert.equal(b.nonEtbAccountCount, 1);

    const occ = generateOccurrenceReport({
      accounts,
      entries,
      postings,
      debts,
      categories: [],
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    });
    assert.equal(occ.totalIncomeCents, 20_000);
    assert.equal(occ.totalExpenseCents, 10_000);

    const audit = auditCurrencyIsolation({
      accounts,
      entries,
      postings,
      debts,
      commitments,
      savingsGoals,
    });
    assert.equal(audit.excludedNonEtbEntryCount, 1);
    assert.equal(audit.currencyReviewEntryCount, 1);
    assert.equal(audit.excludedNonEtbDebtCount, 1);
    assert.equal(audit.excludedNonEtbCommitmentCount, 1);
  });

  it('Case #26: Quick Capture expense parser rejects explicit foreign currency tokens while keeping ordinary descriptions valid', async () => {
    const {
      detectUnsupportedCurrencyToken,
      parseQuickCaptureExpense,
    } = await import('./doubleEntryFinance');

    const etbAccounts: Account[] = [
      makeAccount('acc-cbe', 'CBE Bank', 'ETB', 50_000, { subType: 'bank' }),
      makeAccount('acc-usd', 'Travel USD', 'USD', 20_000, { subType: 'bank' }),
    ];

    // Foreign symbols and unambiguous FX codes are rejected
    for (const sample of [
      'Coffee $15',
      '15.50 USD lunch',
      'Flight €120',
      '£40 taxi',
      'Hotel 2500 KES',
      'AED 300 sim',
      '200 PEN groceries',
    ]) {
      assert.ok(
        detectUnsupportedCurrencyToken(sample) !== null,
        `Expected FX rejection for "${sample}"`
      );
      const parsed = parseQuickCaptureExpense(sample, 'acc-cbe', etbAccounts);
      assert.ok(parsed.rejectedCurrency, `Expected rejectedCurrency for "${sample}"`);
      assert.ok(parsed.error, `Expected error message for "${sample}"`);
      assert.equal(parsed.amountCents, 0);
    }

    // Ordinary lowercase words matching ISO codes or ETB inputs must parse cleanly
    for (const valid of ['200 pen notebook', '150 cup tea', '450.50 ETB lunch', 'Lunch 19.99']) {
      assert.equal(
        detectUnsupportedCurrencyToken(valid),
        null,
        `Did not expect FX rejection for "${valid}"`
      );
      const parsed = parseQuickCaptureExpense(valid, 'acc-cbe', etbAccounts);
      assert.equal(parsed.rejectedCurrency, undefined);
      assert.ok(parsed.amountCents > 0);
      assert.equal(parsed.assetAccountId, 'acc-cbe');
    }

    // Verify transfer fee description uses exact integer formatting (e.g. 19.99 -> 1999 cents)
    const cashAcc = makeAccount('acc-cash', 'Cash', 'ETB', 10_000, { subType: 'cash' });
    assert.ok(cashAcc.id);
    const xfer = buildTransfer({
      id: 'xfer-fee-fmt',
      fromAssetAccountId: 'acc-cbe',
      toAssetAccountId: 'acc-cash',
      amountCents: 1999,
      transferFeeCents: 1999,
      feeExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      date: '2026-11-15',
      description: 'Test transfer',
    });
    assert.ok(xfer.entry.description.includes('(Fee: 19.99 ETB)'));
  });

  it('Case #27: Strict decimal minor-unit parser avoids floating-point rounding drift and rejects malformed fractions', async () => {
    const {
      formatCentsAsInput,
      parseBirrToCents,
      parseDecimalToCentsStrict,
    } = await import('./financialEngine');

    const exactCases: Array<[string, number]> = [
      ['0', 0],
      ['0.01', 1],
      ['19.99', 1999],
      ['1.15', 115],
      ['100.1', 10010],
      ['1,250.75', 125075],
      ['.5', 50],
      ['99999999.99', 9999999999],
    ];
    for (const [input, expected] of exactCases) {
      const strict = parseDecimalToCentsStrict(input);
      assert.equal(strict.valid, true, input);
      assert.equal(strict.cents, expected, input);
      assert.equal(parseBirrToCents(input), expected, input);
    }

    assert.equal(formatCentsAsInput(1999), '19.99');
    assert.equal(formatCentsAsInput(5), '0.05');
    assert.equal(formatCentsAsInput(-115), '-1.15');

    for (const bad of ['', 'abc', '12.345', '12.3.4', 'USD 50']) {
      assert.equal(parseDecimalToCentsStrict(bad).valid, false, bad);
    }
    assert.equal(parseDecimalToCentsStrict('-10.25').valid, false);
    assert.deepEqual(
      parseDecimalToCentsStrict('-10.25', { allowNegative: true }),
      { valid: true, cents: -1025 }
    );
  });
});
