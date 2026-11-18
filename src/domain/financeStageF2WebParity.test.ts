import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  Account,
  buildDirectExpense,
  CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID,
  CANONICAL_DEFAULT_INCOME_CATEGORY_ID,
  categoryIdsMatchOrAlias,
  DEFAULT_EXPENSE_CATEGORIES,
  DEFAULT_INCOME_CATEGORIES,
  filterJournalEntries,
  findCategoryByIdOrAlias,
  FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
  FOUNDATION_DEFAULT_INCOME_CATEGORIES,
  generateOccurrenceReport,
  LEGACY_CATEGORY_ID_ALIASES,
  parseQuickCaptureExpense,
  resolveCanonicalCategoryId,
  resolveCategoryDisplayName,
  TransactionCategory,
  validateBalancedEntry,
  validateSimpleTransaction,
} from './doubleEntryFinance';
import {
  buildQuickCaptureExpenseEntryV7,
  hydrateLedgerFromSimpleTransactions,
  resolveActiveExpenseCategoryIdV7,
  upsertMonthlyBudgetV7,
} from './financeV7Engine';
import { CANONICAL_SEED_DATABASE, SharedBudget } from './sharedFoundation';
import { SharedStateBridge } from '../services/sharedStateBridge';

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

describe('FINANCE STAGE F2 — WEB QUICK CAPTURE, CANONICAL CATEGORIES & MONTHLY BUDGETS', () => {
  it('1. Web default category IDs match CANONICAL_SEED_DATABASE exactly', () => {
    const seedIds = new Set<string>(CANONICAL_SEED_DATABASE.categories.map((c) => c.id));
    for (const cat of [
      ...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
      ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
    ]) {
      assert.ok(seedIds.has(cat.id), `Expected ${cat.id} to exist in CANONICAL_SEED_DATABASE`);
    }

    assert.ok(
      FOUNDATION_DEFAULT_EXPENSE_CATEGORIES.some(
        (c) => c.id === CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID && c.isDefault === true
      )
    );
    assert.ok(
      FOUNDATION_DEFAULT_INCOME_CATEGORIES.some(
        (c) =>
          c.id === CANONICAL_DEFAULT_INCOME_CATEGORY_ID &&
          c.isDefault === true &&
          c.name === 'Other'
      )
    );
    assert.ok(DEFAULT_EXPENSE_CATEGORIES.some((c) => c.id === 'cat-comm'));
    assert.ok(DEFAULT_EXPENSE_CATEGORIES.some((c) => c.id === 'cat-other-exp' && c.isDefault));
    assert.ok(DEFAULT_INCOME_CATEGORIES.some((c) => c.id === 'cat-other-inc' && c.isDefault));

    for (const legacyId of Object.keys(LEGACY_CATEGORY_ID_ALIASES)) {
      assert.strictEqual(
        [...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES, ...FOUNDATION_DEFAULT_INCOME_CATEGORIES].some(
          (c) => c.id === legacyId
        ),
        false,
        `Legacy ID ${legacyId} must not appear in FOUNDATION_DEFAULT_* arrays`
      );
    }
  });

  it('2. Legacy category IDs resolve non-destructively across lookup, validation, filter, and reports', () => {
    assert.strictEqual(resolveCanonicalCategoryId('cat-other'), 'cat-other-exp');
    assert.strictEqual(resolveCanonicalCategoryId('cat-misc'), 'cat-other-exp');
    assert.strictEqual(resolveCanonicalCategoryId('cat-inc-other'), 'cat-other-inc');
    assert.strictEqual(resolveCanonicalCategoryId('cat-from-asaye'), 'cat-asaye');
    assert.strictEqual(resolveCanonicalCategoryId('cat-communication'), 'cat-comm');
    assert.strictEqual(categoryIdsMatchOrAlias('cat-communication', 'cat-comm'), true);
    assert.strictEqual(categoryIdsMatchOrAlias('cat-other', 'cat-misc'), true);

    const canonicalCategories: TransactionCategory[] = [
      ...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
      ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
    ];

    const txValidation = validateSimpleTransaction(
      'expense',
      50000,
      'acc-cbe',
      'cat-communication',
      undefined,
      '2026-11-15',
      [],
      canonicalCategories
    );
    assert.strictEqual(txValidation.isValid, true);

    const incomeValidation = validateSimpleTransaction(
      'income',
      100000,
      'acc-cbe',
      'cat-from-asaye',
      undefined,
      '2026-11-15',
      [],
      canonicalCategories
    );
    assert.strictEqual(incomeValidation.isValid, true);

    assert.strictEqual(resolveCategoryDisplayName(canonicalCategories, 'cat-other'), 'Other');
    assert.strictEqual(
      resolveCategoryDisplayName(canonicalCategories, 'cat-communication'),
      'Communication'
    );
    assert.strictEqual(
      resolveCategoryDisplayName(canonicalCategories, 'cat-from-asaye'),
      'From Asaye'
    );

    const accounts: Account[] = [
      {
        id: 'acc-cbe',
        name: 'CBE',
        type: 'asset',
        currencyCode: 'ETB',
        isArchived: false,
        createdAt: '2026-11-01T00:00:00Z',
      },
      {
        id: 'acc-sys-expense',
        name: 'Expense Control',
        type: 'expense',
        currencyCode: 'ETB',
        isSystem: true,
        isArchived: false,
        createdAt: '2026-11-01T00:00:00Z',
      },
    ];
    const { entry, postings } = buildDirectExpense({
      id: 'entry-legacy-1',
      assetAccountId: 'acc-cbe',
      expenseAccountId: 'acc-sys-expense',
      categoryId: 'cat-communication',
      amountCents: 25000,
      occurrenceDate: '2026-11-12',
      movementDate: '2026-11-12',
      description: 'Legacy telecom topup',
    });

    // Stored posting preserves original legacy ID without mutation
    assert.strictEqual(postings[0].categoryId, 'cat-communication');

    const report = generateOccurrenceReport({
      entries: [entry],
      postings,
      accounts,
      categories: canonicalCategories,
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    });
    assert.strictEqual(report.totalExpenseCents, 25000);
    assert.strictEqual(report.categoryBreakdown['Communication'], 25000);

    const filtered = filterJournalEntries([entry], postings, { categoryId: 'cat-comm' });
    assert.strictEqual(filtered.length, 1);
  });

  it('3. Quick Capture parses live active expense categories cleanly and falls back to cat-other-exp', () => {
    const accounts: Account[] = [
      {
        id: 'acc-cbe',
        name: 'CBE',
        type: 'asset',
        currencyCode: 'ETB',
        isArchived: false,
        createdAt: '2026-11-01T00:00:00Z',
      },
    ];

    // Canonical defaults when live categories array is empty
    const unmatchedDefault = parseQuickCaptureExpense('950 notebook', 'acc-cbe', accounts, []);
    assert.strictEqual(unmatchedDefault.categoryId, 'cat-other-exp');
    assert.strictEqual(unmatchedDefault.categoryName, 'Other');

    const airtimeDefault = parseQuickCaptureExpense('120 airtime CBE', 'acc-cbe', accounts, []);
    assert.strictEqual(airtimeDefault.categoryId, 'cat-comm');

    const powerDefault = parseQuickCaptureExpense('450 electric bill', 'acc-cbe', accounts, []);
    assert.strictEqual(powerDefault.categoryId, 'cat-utilities');

    // FX rejection uses cat-other-exp fallback, never cat-misc
    const fxRejected = parseQuickCaptureExpense('$25 coffee', 'acc-cbe', accounts, []);
    assert.strictEqual(fxRejected.rejectedCurrency, 'USD ($)');
    assert.strictEqual(fxRejected.categoryId, 'cat-other-exp');

    // Archived or income categories must be ignored; active custom categories matched
    const liveCategories: TransactionCategory[] = [
      { id: 'cat-food-archived', name: 'Food', type: 'expense', colorHex: '#EF4444', isArchived: true },
      { id: 'cat-salary', name: 'Dinner Stipend', type: 'income', colorHex: '#10B981' },
      { id: 'cat-custom-cafe', name: 'Cafe & Drinks', type: 'expense', colorHex: '#84CC16' },
      { id: 'cat-other-exp', name: 'Other', type: 'expense', colorHex: '#94A3B8', isDefault: true },
    ];
    const cafeMatch = parseQuickCaptureExpense('180 cafe latte', 'acc-cbe', accounts, liveCategories);
    assert.strictEqual(cafeMatch.categoryId, 'cat-custom-cafe');

    // Archived food category is skipped -> falls back to cat-other-exp instead of choosing archived Food or income Dinner Stipend
    const skippedArchived = parseQuickCaptureExpense(
      '300 dinner CBE',
      'acc-cbe',
      accounts,
      liveCategories
    );
    assert.strictEqual(skippedArchived.categoryId, 'cat-other-exp');
    assert.strictEqual(resolveActiveExpenseCategoryIdV7(liveCategories, 'cat-food-archived'), 'cat-other-exp');
  });

  it('4. buildQuickCaptureExpenseEntryV7 builds balanced postings matching SimpleTransaction and does not double-hydrate', () => {
    const accounts: Account[] = [
      {
        id: 'acc-cbe',
        name: 'CBE',
        type: 'asset',
        subType: 'bank',
        currencyCode: 'ETB',
        openingBalanceCents: 100000,
        isArchived: false,
        createdAt: '2026-11-01T00:00:00Z',
      },
      {
        id: 'acc-telebirr',
        name: 'Telebirr',
        type: 'asset',
        subType: 'mobile_money',
        currencyCode: 'ETB',
        openingBalanceCents: 50000,
        isArchived: false,
        createdAt: '2026-11-01T00:00:00Z',
      },
    ];
    const categories: TransactionCategory[] = [
      ...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
      ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
    ];

    const built = buildQuickCaptureExpenseEntryV7({
      rawText: '240 taxi telebirr',
      accountHint: 'CBE',
      accounts,
      categories,
      occurrenceDateIso: '2026-11-18',
      nowIso: '2026-11-18T10:00:00Z',
      entryId: 'entry-qc-1',
      txId: 'tx-qc-1',
    });

    assert.strictEqual(built.ok, true);
    assert.ok(built.entry && built.postings && built.simpleTransaction);
    assert.strictEqual(built.targetAccount?.id, 'acc-telebirr');
    assert.strictEqual(built.resolvedCategoryId, 'cat-transport');
    assert.strictEqual(built.simpleTransaction.categoryId, 'cat-transport');
    assert.strictEqual(built.simpleTransaction.isSuperseded, false);
    assert.strictEqual(built.simpleTransaction.journalEntryId, 'entry-qc-1');
    assert.strictEqual(built.entry.legacySourceTxId, 'tx-qc-1');

    validateBalancedEntry(built.postings);
    const debitPosting = built.postings.find((p) => p.direction === 'debit')!;
    const creditPosting = built.postings.find((p) => p.direction === 'credit')!;
    assert.strictEqual(debitPosting.categoryId, built.simpleTransaction.categoryId);
    assert.strictEqual(debitPosting.amountCents, 24000);
    assert.strictEqual(creditPosting.accountId, 'acc-telebirr');

    // Hydrating immediately afterwards must remain idempotent (zero duplicate tx migration or entry duplication)
    const hydrated = hydrateLedgerFromSimpleTransactions({
      accounts: built.accountsWithControls!,
      transactions: [built.simpleTransaction],
      entries: [built.entry],
      postings: built.postings,
    });
    assert.strictEqual(hydrated.migratedCount, 0);
    assert.strictEqual(
      hydrated.entries.filter((e) => e.id === 'entry-qc-1' || e.legacySourceTxId === 'tx-qc-1').length,
      1
    );
    const secondPass = hydrateLedgerFromSimpleTransactions({
      accounts: hydrated.accounts,
      transactions: [built.simpleTransaction],
      entries: hydrated.entries,
      postings: hydrated.postings,
    });
    assert.strictEqual(secondPass.migratedCount, 0);
    assert.strictEqual(secondPass.entries.length, hydrated.entries.length);
  });

  it('5. SharedStateBridge round-trips Quick Capture expenses atomically across canonical DB & module stores', () => {
    withMockBrowserStorage((store, events) => {
      const seededAccounts: Account[] = [
        {
          id: 'acc-cbe',
          name: 'CBE',
          type: 'asset',
          subType: 'bank',
          currencyCode: 'ETB',
          openingBalanceCents: 200000,
          openingBalanceDate: '2026-11-01',
          isArchived: false,
          createdAt: '2026-11-01T00:00:00Z',
        },
      ];
      store.set('daywell_accounts', JSON.stringify(seededAccounts));
      store.set('daywell_finance_setup_completed', 'true');

      const canonicalBefore = SharedStateBridge.loadCanonicalState();
      const built = buildQuickCaptureExpenseEntryV7({
        rawText: '750 stationery',
        accountHint: 'CBE',
        accounts: canonicalBefore.accounts as Account[],
        categories: canonicalBefore.categories as TransactionCategory[],
        occurrenceDateIso: '2026-11-18',
        nowIso: '2026-11-18T11:00:00Z',
        entryId: 'entry-qc-bridge-1',
        txId: 'tx-qc-bridge-1',
      });
      assert.strictEqual(built.ok, true);
      assert.strictEqual(built.resolvedCategoryId, 'cat-other-exp');

      SharedStateBridge.saveCanonicalState({
        ...canonicalBefore,
        isFinanceSetupCompleted: true,
        accounts: built.accountsWithControls as any,
        journalEntries: [built.entry!, ...(canonicalBefore.journalEntries || [])],
        postings: [...built.postings!, ...(canonicalBefore.postings || [])],
        transactions: [built.simpleTransaction as any, ...(canonicalBefore.transactions || [])],
      });

      assert.strictEqual(
        events.filter((e) => e.type === SharedStateBridge.SYNC_EVENT_NAME).length,
        1
      );

      const canonicalRaw = JSON.parse(store.get('daywell_canonical_database_v3') || '{}');
      const financeTxs = JSON.parse(store.get('daywell_finance_transactions') || '[]');
      const entriesStored = JSON.parse(store.get('daywell_journal_entries') || '[]');
      const postingsStored = JSON.parse(store.get('daywell_postings') || '[]');

      assert.strictEqual(canonicalRaw.transactions.length, 1);
      assert.strictEqual(canonicalRaw.transactions[0].categoryId, 'cat-other-exp');
      assert.strictEqual(canonicalRaw.transactions[0].isSuperseded, false);
      assert.strictEqual(financeTxs.length, 1);
      assert.strictEqual(financeTxs[0].categoryId, 'cat-other-exp');
      assert.strictEqual(entriesStored.length, 1);
      assert.strictEqual(postingsStored.length, 2);

      // Exported canonical JSON passes strict snapshot import validation
      const exported = SharedStateBridge.exportToAndroidJson();
      const imported = SharedStateBridge.importFromAndroidJson(exported);
      assert.strictEqual(imported.success, true);
      assert.strictEqual(imported.state?.transactions[0].categoryId, 'cat-other-exp');
    });
  });

  it('6. Monthly budget upsert keys uniquely on (categoryId, monthIso) without overwriting other months', () => {
    const octSave = upsertMonthlyBudgetV7({
      budgets: [],
      categoryId: 'cat-food',
      monthIso: '2026-10',
      limitCents: 300000,
      rolloverEnabled: false,
      budgetId: 'bud-oct-food',
    });
    assert.strictEqual(octSave.ok, true);
    assert.strictEqual(octSave.budgets.length, 1);

    // Saving same category for November keeps October intact
    const novSave = upsertMonthlyBudgetV7({
      budgets: octSave.budgets,
      categoryId: 'cat-food',
      monthIso: '2026-11',
      limitCents: 450000,
      rolloverEnabled: true,
      budgetId: 'bud-nov-food',
    });
    assert.strictEqual(novSave.ok, true);
    assert.strictEqual(novSave.budgets.length, 2);
    const octAfterNov = novSave.budgets.find((b) => b.monthIso === '2026-10');
    const novAfterNov = novSave.budgets.find((b) => b.monthIso === '2026-11');
    assert.strictEqual(octAfterNov?.limitCents, 300000);
    assert.strictEqual(novAfterNov?.limitCents, 450000);
    assert.strictEqual(novAfterNov?.rolloverEnabled, true);

    // Updating November leaves October untouched
    const novUpdate = upsertMonthlyBudgetV7({
      budgets: novSave.budgets,
      categoryId: 'cat-food',
      monthIso: '2026-11',
      limitCents: 500000,
      rolloverEnabled: false,
    });
    assert.strictEqual(novUpdate.ok, true);
    assert.strictEqual(novUpdate.updatedExisting, true);
    assert.strictEqual(novUpdate.budgets.length, 2);
    assert.strictEqual(
      novUpdate.budgets.find((b) => b.monthIso === '2026-10')?.limitCents,
      300000
    );
    assert.strictEqual(
      novUpdate.budgets.find((b) => b.monthIso === '2026-11')?.limitCents,
      500000
    );

    // Same-month alias upsert merges cleanly without creating duplicate canonical entries
    const legacyOtherOct: SharedBudget = {
      id: 'bud-oct-legacy',
      categoryId: 'cat-other',
      monthIso: '2026-10',
      limitCents: 100000,
      rolloverEnabled: false,
      createdAt: '2026-10-01T00:00:00Z',
      updatedAt: '2026-10-01T00:00:00Z',
    };
    const canonicalOctUpdate = upsertMonthlyBudgetV7({
      budgets: [legacyOtherOct],
      categoryId: 'cat-other-exp',
      monthIso: '2026-10',
      limitCents: 150000,
      rolloverEnabled: true,
    });
    assert.strictEqual(canonicalOctUpdate.ok, true);
    assert.strictEqual(canonicalOctUpdate.updatedExisting, true);
    assert.strictEqual(canonicalOctUpdate.budgets.length, 1);
    assert.strictEqual(canonicalOctUpdate.budgets[0].categoryId, 'cat-other-exp');
    assert.strictEqual(canonicalOctUpdate.budgets[0].limitCents, 150000);

    // Active-month filtering selects only active month budgets
    const novOnly = novUpdate.budgets.filter((b) => b.monthIso === '2026-11');
    assert.strictEqual(novOnly.length, 1);
    assert.strictEqual(novOnly[0].limitCents, 500000);

    // Unused import guard check
    assert.ok(findCategoryByIdOrAlias(FOUNDATION_DEFAULT_EXPENSE_CATEGORIES, 'cat-other'));
  });
});
