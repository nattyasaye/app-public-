import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import {
  Account,
  assertEtbPostingAccounts,
  DEFAULT_EXPENSE_CATEGORIES,
  JournalEntry,
  parseQuickCaptureExpense,
  Posting,
} from './doubleEntryFinance';
import {
  buildAccountBalancesReportV7,
  buildAlignedBalanceSheetReportV7,
  buildDirectExpense,
  buildQuickCaptureExpenseEntryV7,
  calculateAvailableToSpendBreakdownV7,
  canCorrectJournalEntryV7,
  FOUNDATION_DEFAULT_INCOME_CATEGORIES,
  getExpenseRefundSummaryV7,
  recordCommitmentSettlementV7,
  SharedCommitment,
  SharedSavingsGoal,
  unvoidJournalEntryGuardedV7,
  verifyFinanceV7Integrity,
} from './financeV7Engine';
import { SYSTEM_CONTROL_ACCOUNT_IDS } from './sharedFoundation';
import { SharedStateBridge } from '../services/sharedStateBridge';
import { FinanceComposerModal } from '../components/finance/FinanceComposerModal';
import { FinanceOverviewTab } from '../components/finance/FinanceOverviewTab';
import { FinanceTransactionsTab } from '../components/finance/FinanceTransactionsTab';
import { FinanceReportsTab } from '../components/finance/FinanceReportsTab';

function withMockBrowserStorage(
  fn: (store: Map<string, string>) => void
): void {
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

function makeMixedCurrencyAccounts(): Account[] {
  return [
    {
      id: 'acc-cbe',
      name: 'CBE Bank',
      type: 'asset',
      subType: 'bank',
      currencyCode: 'ETB',
      openingBalanceCents: 250000, // 2,500 ETB
      isArchived: false,
      createdAt: '2026-11-01T00:00:00Z',
    },
    {
      id: 'acc-usd-legacy',
      name: 'Dollar Cash',
      type: 'asset',
      subType: 'cash',
      currencyCode: 'USD',
      openingBalanceCents: 100000, // 1,000.00 USD — must NEVER add to ETB totals
      isArchived: false,
      createdAt: '2026-10-01T00:00:00Z',
    },
    {
      id: 'acc-unverified-legacy',
      name: 'Unclassified Vault',
      type: 'asset',
      subType: 'bank',
      currencyCode: '',
      openingBalanceCents: 50000,
      isArchived: false,
      createdAt: '2026-10-01T00:00:00Z',
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

function makeLegacyUsdEntry(): { entry: JournalEntry; postings: Posting[] } {
  const entry: JournalEntry = {
    id: 'je-legacy-usd-1',
    entryType: 'standard',
    description: 'Airport Hotel USD',
    occurrenceDate: '2026-10-15',
    isVoided: false,
    createdAt: '2026-10-15T10:00:00Z',
  };
  const postings: Posting[] = [
    {
      id: 'post-usd-1-dr',
      entryId: entry.id,
      accountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      amountCents: 15000,
      direction: 'debit',
      accountMovementDate: '2026-10-15',
      categoryId: 'cat-food',
    },
    {
      id: 'post-usd-1-cr',
      entryId: entry.id,
      accountId: 'acc-usd-legacy',
      amountCents: 15000,
      direction: 'credit',
      accountMovementDate: '2026-10-15',
    },
  ];
  return { entry, postings };
}

describe('Finance Stage 3 — ETB-Only Finance Cleanup (Web)', () => {
  it('1. Enforces ETB-only postings and rejects FX tokens in Quick Capture cleanly', () => {
    const accounts = makeMixedCurrencyAccounts();

    // Non-ETB / unverified accounts cannot be used for new postings
    assert.throws(() =>
      assertEtbPostingAccounts({
        accounts,
        accountIds: ['acc-usd-legacy'],
        roleLabels: ['Paid account'],
      })
    );
    assert.throws(() =>
      assertEtbPostingAccounts({
        accounts,
        accountIds: ['acc-unverified-legacy'],
        roleLabels: ['Paid account'],
      })
    );

    // Quick Capture rejects FX tokens with clean ETB-only message
    for (const fxText of ['$25 Dinner', 'Taxi 18 USD', 'Hotel 40 EUR', 'Tea £10']) {
      const parsed = parseQuickCaptureExpense(
        fxText,
        'acc-cbe',
        accounts,
        DEFAULT_EXPENSE_CATEGORIES
      );
      assert.ok(parsed.rejectedCurrency, `Should detect FX token in "${fxText}"`);
      assert.match(
        parsed.error || '',
        /Daywell Finance supports ETB only\. Please enter this amount in ETB/,
        `Unexpected FX message: ${parsed.error}`
      );

      const built = buildQuickCaptureExpenseEntryV7({
        rawText: fxText,
        accounts,
        categories: DEFAULT_EXPENSE_CATEGORIES,
        occurrenceDateIso: '2026-11-12',
      });
      assert.equal(built.ok, false);
      assert.ok(!built.error?.includes('first-release'));
      assert.match(
        built.error || '',
        /Daywell Finance supports ETB only\. Please enter this amount in ETB/
      );
    }

    // Valid ETB quick captures succeed normally
    const etbRes = buildQuickCaptureExpenseEntryV7({
      rawText: 'Coffee 120 ETB',
      accounts,
      categories: DEFAULT_EXPENSE_CATEGORIES,
      occurrenceDateIso: '2026-11-12',
    });
    assert.equal(etbRes.ok, true);
    assert.ok((etbRes.entry?.description || '').includes('Coffee'));
    assert.equal(etbRes.simpleTransaction?.amountCents, 12000);
  });

  it('2. Preserves historical non-ETB records safely without deletion, 1:1 conversion, or ETB math contamination', () => {
    const accounts = makeMixedCurrencyAccounts();
    const usd = makeLegacyUsdEntry();
    const etb = buildDirectExpense({
      id: 'je-etb-1',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 50000, // 500 ETB
      occurrenceDate: '2026-11-10',
      movementDate: '2026-11-10',
      description: 'Shoa Groceries',
    });

    const entries = [etb.entry, usd.entry];
    const postings = [...etb.postings, ...usd.postings];

    // ETB CBE balance = 2,500 - 500 = 2,000 ETB (200,000 cents). USD (850.00 USD) & unverified (500) must be excluded.
    const breakdown = calculateAvailableToSpendBreakdownV7({
      accounts,
      entries,
      postings,
      debts: [],
      commitments: [],
      commitmentSettlements: [],
      savingsGoals: [],
    });
    assert.equal(breakdown.liquidCashCents, 200000);
    assert.equal(breakdown.availableToSpendCents, 200000);

    const balanceSheet = buildAlignedBalanceSheetReportV7({
      accounts,
      entries,
      postings,
      debts: [],
      breakdown,
    });
    assert.equal(balanceSheet.liquidCashCents, 200000);
    assert.equal(balanceSheet.netFinancialPositionCents, 200000);

    const balanceReport = buildAccountBalancesReportV7({
      accounts,
      postings,
      entries,
    });
    // Only Verified ETB user account is in normal Account Balances report; USD & unverified stay isolated
    assert.deepEqual(
      balanceReport.liquidAccounts.map((r) => r.accountId),
      ['acc-cbe']
    );
    assert.deepEqual(
      balanceReport.nonEtbReviewAccounts.map((r) => r.accountId).sort(),
      ['acc-unverified-legacy', 'acc-usd-legacy']
    );

    // Legacy USD entries are protected from refund, replacement, unvoid, or commitment settlement
    const refundSummary = getExpenseRefundSummaryV7({
      originalEntryId: usd.entry.id,
      entries,
      postings,
      accounts,
    });
    assert.equal(refundSummary.eligible, false);
    assert.ok(!refundSummary.reason?.includes('first-release'));
    assert.ok(!refundSummary.reason?.includes('currency-review'));

    const correctCheck = canCorrectJournalEntryV7({
      entry: usd.entry,
      entries,
      postings,
      accounts,
    });
    assert.equal(correctCheck.ok, false);
    assert.ok(!correctCheck.error?.includes('first-release'));
    assert.ok(!correctCheck.error?.includes('currency-review'));

    const voidedUsd: JournalEntry = { ...usd.entry, isVoided: true };
    assert.throws(
      () =>
        unvoidJournalEntryGuardedV7({
          entryId: voidedUsd.id,
          accounts,
          entries: [etb.entry, voidedUsd],
          postings,
          debts: [],
          allocations: [],
          commitments: [],
          commitmentSettlements: [],
          savingsGoals: [],
          simpleTransactions: [],
        }),
      (err: Error) =>
        !err.message.includes('first-release') &&
        err.message.includes('read-only')
    );

    const legacyCommitment: SharedCommitment = {
      id: 'cm-usd-legacy',
      title: 'USD Subscription',
      amountCents: 2000,
      dueDate: '2026-11-20',
      categoryId: 'cat-other-exp',
      linkedAccountId: 'acc-usd-legacy',
      direction: 'outflow',
      isPaid: false,
    };
    assert.throws(
      () =>
        recordCommitmentSettlementV7({
          commitment: legacyCommitment,
          accountId: 'acc-cbe',
          amountCents: 2000,
          settledDateIso: '2026-11-12',
          accounts,
          entries,
          postings,
          existingSettlements: [],
        }),
      (err: Error) =>
        !err.message.includes('first-release') &&
        !err.message.includes('currency-review') &&
        err.message.includes('read-only')
    );

    // Backup/restore preserves historical USD account & USD entry intact without conversion
    withMockBrowserStorage(() => {
      const payload = {
        schemaVersion: 5,
        snapshotFormatVersion: 2,
        databaseSchemaVersion: 12,
        financeSchemaVersion: 7,
        appVersion: '2.0.0',
        exportedAt: '2026-11-12T10:00:00Z',
        isFinanceSetupCompleted: true,
        openingBalanceCents: 250000,
        accounts,
        categories: DEFAULT_EXPENSE_CATEGORIES,
        parties: [],
        transactions: [],
        journalEntries: entries,
        postings,
        debts: [],
        settlementAllocations: [],
        commitments: [legacyCommitment],
        commitmentSettlements: [],
        savingsGoals: [],
        budgets: [],
        recurringRules: [],
        tasks: [],
        dailyPlanningEntries: [],
        dailyRhythmDays: [],
        notes: [],
        projects: [],
        projectTrackingBlocks: [],
        projectTrackingRecords: [],
        milestones: [],
        goals: [],
        inboxItems: [],
        calendarEvents: [],
        reminders: [],
      };
      const imp = SharedStateBridge.importFromAndroidJson(JSON.stringify(payload));
      assert.equal(imp.success, true, imp.error);
      const restoredUsdAcc = imp.state?.accounts?.find(
        (a) => a.id === 'acc-usd-legacy'
      );
      assert.equal(restoredUsdAcc?.currencyCode, 'USD');
      assert.equal(restoredUsdAcc?.openingBalanceCents, 100000);
      const restoredUsdEntry = imp.state?.journalEntries?.find(
        (e) => e.id === 'je-legacy-usd-1'
      );
      assert.equal(restoredUsdEntry?.description, 'Airport Hotel USD');
    });
  });

  it('3. FinanceOverviewTab isolates historical non-ETB accounts, shows dismissible one-time notice only when legacy records exist, and removes multi-currency inputs', () => {
    const allAccounts = makeMixedCurrencyAccounts();
    const etbOnlyAccounts = allAccounts.filter((a) => a.currencyCode === 'ETB');
    const usd = makeLegacyUsdEntry();
    const breakdown = calculateAvailableToSpendBreakdownV7({
      accounts: allAccounts,
      entries: [usd.entry],
      postings: usd.postings,
      debts: [],
      commitments: [],
      commitmentSettlements: [],
      savingsGoals: [],
    });

    const baseOverviewProps = {
      categories: DEFAULT_EXPENSE_CATEGORIES,
      simpleTransactions: [],
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
    };

    const etbOnlyBreakdown = calculateAvailableToSpendBreakdownV7({
      accounts: etbOnlyAccounts,
      entries: [],
      postings: [],
      debts: [],
      commitments: [],
      commitmentSettlements: [],
      savingsGoals: [],
    });

    // Pure ETB ledger: no legacy notice and no legacy archive card
    const pureEtbHtml = renderToStaticMarkup(
      React.createElement(FinanceOverviewTab, {
        ...baseOverviewProps,
        accounts: etbOnlyAccounts,
        entries: [],
        postings: [],
        breakdown: etbOnlyBreakdown,
        legacyNoticeDismissed: false,
        onDismissLegacyNotice: () => {},
      })
    );
    assert.ok(!pureEtbHtml.includes('Historical Non-ETB Records Preserved'));
    assert.ok(!pureEtbHtml.includes('Legacy Non-ETB Archive'));
    assert.ok(!pureEtbHtml.includes('Currency Review'));
    assert.ok(!pureEtbHtml.includes('First-Release'));

    // Mixed ledger with notice NOT dismissed: renders one-time dismissible notice & Legacy Archive
    const mixedWithNoticeHtml = renderToStaticMarkup(
      React.createElement(FinanceOverviewTab, {
        ...baseOverviewProps,
        accounts: allAccounts,
        entries: [usd.entry],
        postings: usd.postings,
        breakdown,
        legacyNoticeDismissed: false,
        onDismissLegacyNotice: () => {},
      })
    );
    assert.ok(mixedWithNoticeHtml.includes('Historical Non-ETB Records Preserved'));
    assert.ok(mixedWithNoticeHtml.includes('Legacy Non-ETB Archive (Read-Only)'));

    // Mixed ledger AFTER notice dismissed: hides notice while keeping Legacy Archive
    const mixedDismissedHtml = renderToStaticMarkup(
      React.createElement(FinanceOverviewTab, {
        ...baseOverviewProps,
        accounts: allAccounts,
        entries: [usd.entry],
        postings: usd.postings,
        breakdown,
        legacyNoticeDismissed: true,
        onDismissLegacyNotice: () => {},
      })
    );
    assert.ok(!mixedDismissedHtml.includes('Historical Non-ETB Records Preserved'));
    assert.ok(mixedDismissedHtml.includes('Legacy Non-ETB Archive (Read-Only)'));
  });

  it('4. Transactions, Reports, and Composer remove multi-currency filters, diagnostics, and currency selectors', () => {
    const accounts = makeMixedCurrencyAccounts();
    const usd = makeLegacyUsdEntry();
    const etb = buildDirectExpense({
      id: 'je-etb-ui',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 12000,
      occurrenceDate: '2026-11-11',
      movementDate: '2026-11-11',
      description: 'Injera lunch',
    });
    const entries = [etb.entry, usd.entry];
    const postings = [...etb.postings, ...usd.postings];

    const txHtml = renderToStaticMarkup(
      React.createElement(FinanceTransactionsTab, {
        entries,
        postings,
        accounts,
        categories: DEFAULT_EXPENSE_CATEGORIES,
        onOpenComposer: () => {},
        onVoidEntry: () => ({ ok: true }),
        onRestoreEntry: () => ({ ok: true }),
        onRequestConfirm: () => {},
      })
    );
    assert.ok(txHtml.includes('Injera lunch'));
    assert.ok(txHtml.includes('Legacy Non-ETB Entries (1) · Read-Only'));
    assert.ok(!txHtml.includes('All Currency Statuses'));
    assert.ok(!txHtml.includes('Currency Review'));
    assert.ok(!txHtml.includes('Excluded (Non-ETB)'));

    const breakdown = calculateAvailableToSpendBreakdownV7({
      accounts,
      entries,
      postings,
      debts: [],
      commitments: [],
      commitmentSettlements: [],
      savingsGoals: [],
    });
    const integrity = verifyFinanceV7Integrity({
      accounts,
      entries,
      postings,
      debts: [],
      allocations: [],
      commitments: [],
      commitmentSettlements: [],
      savingsGoals: [] as SharedSavingsGoal[],
    });
    const reportsHtml = renderToStaticMarkup(
      React.createElement(FinanceReportsTab, {
        accounts,
        categories: DEFAULT_EXPENSE_CATEGORIES,
        entries,
        postings,
        debts: [],
        commitments: [],
        breakdown,
        integrityReport: integrity,
        onRefreshState: () => {},
      })
    );
    assert.ok(reportsHtml.includes('Account Balances (ETB)'));
    assert.ok(!reportsHtml.includes('ETB Currency Isolation Summary'));
    assert.ok(!reportsHtml.includes('Non-ETB / Review'));

    const allCategories = [
      ...DEFAULT_EXPENSE_CATEGORIES,
      ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
    ];
    for (const kind of ['expense', 'income', 'transfer'] as const) {
      const composerHtml = renderToStaticMarkup(
        React.createElement(FinanceComposerModal, {
          isOpen: true,
          prefill: { nonce: 1, kind },
          accounts,
          categories: allCategories,
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
      assert.ok(!composerHtml.includes('Currency (First-Release ETB)'));
      assert.ok(!composerHtml.includes('First-Release'));
      // USD legacy account must not appear as selectable option in normal ETB composer
      assert.ok(!composerHtml.includes('Dollar Cash'));
    }
  });

  it('5. Static inspection confirms zero obsolete multi-currency UI controls remain in Web Finance or Today Dashboard', () => {
    const filesToCheck = [
      'src/App.tsx',
      'src/components/DaywellFinanceModule.tsx',
      'src/components/finance/FinanceOverviewTab.tsx',
      'src/components/finance/FinanceTransactionsTab.tsx',
      'src/components/finance/FinancePlanTab.tsx',
      'src/components/finance/FinanceReportsTab.tsx',
      'src/components/finance/FinanceComposerModal.tsx',
    ];
    const forbidden = [
      'Currency Review',
      'first-release',
      'First-Release',
      'All Currency Statuses',
      'All Currencies',
      'Non-ETB Accounts Excluded',
      'ETB Currency Isolation Summary',
      'Currency (First-Release ETB)',
    ];
    for (const rel of filesToCheck) {
      const src = fs.readFileSync(path.join(process.cwd(), rel), 'utf8');
      for (const marker of forbidden) {
        assert.ok(
          !src.includes(marker),
          `${rel} must not contain removed Stage 3 marker "${marker}"`
        );
      }
    }

    const appSource = fs.readFileSync(path.join(process.cwd(), 'src/App.tsx'), 'utf8');
    assert.ok(
      appSource.includes('classifyAllJournalEntries'),
      'Today Dashboard Recent Activity should filter to ETB-eligible entries'
    );
    const moduleSource = fs.readFileSync(
      path.join(process.cwd(), 'src/components/DaywellFinanceModule.tsx'),
      'utf8'
    );
    assert.ok(
      moduleSource.includes('daywell_finance_legacy_non_etb_notice_dismissed_v1'),
      'DaywellFinanceModule must persist dismissible legacy non-ETB notice key'
    );
  });
});
