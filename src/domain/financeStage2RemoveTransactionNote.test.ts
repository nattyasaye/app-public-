import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import {
  Account,
  collectUnambiguousHistoricalPostingNote,
  DEFAULT_ACCOUNTS,
  DEFAULT_EXPENSE_CATEGORIES,
  filterJournalEntries,
  Party,
  Posting,
  resolveDescriptionWithHistoricalNote,
} from './doubleEntryFinance';
import {
  buildDirectExpense,
  buildDirectIncome,
  buildQuickCaptureExpenseEntryV7,
  buildTransfer,
  correctJournalEntryV7,
  FOUNDATION_DEFAULT_INCOME_CATEGORIES,
  hydrateLedgerFromSimpleTransactions,
  recordExpenseRefundV7,
  SimpleTransaction,
} from './financeV7Engine';
import { SYSTEM_CONTROL_ACCOUNT_IDS } from './sharedFoundation';
import { DataPortabilityService } from '../services/dataPortabilityService';
import { SharedStateBridge } from '../services/sharedStateBridge';
import { FinanceComposerModal } from '../components/finance/FinanceComposerModal';
import { FinanceTransactionsTab } from '../components/finance/FinanceTransactionsTab';
import { createWebNoteRecord } from './webNotesLifecycle';
import { matchesNoteSearchQuery } from './noteHelpers';
import { TaskNoteRecord } from './taskNotes';

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

function makeEtbAccounts(): Account[] {
  return [
    {
      id: 'acc-cbe',
      name: 'CBE',
      type: 'asset',
      subType: 'bank',
      currencyCode: 'ETB',
      openingBalanceCents: 500000,
      isArchived: false,
      createdAt: '2026-11-01T00:00:00Z',
    },
    {
      id: 'acc-telebirr',
      name: 'Telebirr',
      type: 'asset',
      subType: 'mobile_money',
      currencyCode: 'ETB',
      openingBalanceCents: 100000,
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

describe('Finance Stage 2 — Remove Transaction-Level Note Functionality (Web)', () => {
  it('1. Finance composer, transaction forms, and prefill types no longer expose a transaction Note field while Description remains', () => {
    const allCategories = [
      ...DEFAULT_EXPENSE_CATEGORIES,
      ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
    ];

    for (const kind of ['expense', 'income', 'transfer', 'split', 'lend', 'borrow'] as const) {
      const html = renderToStaticMarkup(
        React.createElement(FinanceComposerModal, {
          isOpen: true,
          prefill: { nonce: 1, kind },
          accounts: DEFAULT_ACCOUNTS,
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

      assert.ok(
        html.includes('>Description<'),
        `${kind} composer should render Description label`
      );
      assert.ok(
        !html.includes('Notes (Optional)'),
        `${kind} composer must not expose Notes (Optional)`
      );
      assert.ok(
        !html.includes('Note (Optional)'),
        `${kind} composer must not expose Note (Optional)`
      );
    }

    const txTabSource = fs.readFileSync(
      path.join(process.cwd(), 'src/components/finance/FinanceTransactionsTab.tsx'),
      'utf8'
    );
    const typesSource = fs.readFileSync(
      path.join(process.cwd(), 'src/components/finance/financeV7Types.ts'),
      'utf8'
    );
    const moduleSource = fs.readFileSync(
      path.join(process.cwd(), 'src/components/DaywellFinanceModule.tsx'),
      'utf8'
    );

    assert.ok(!txTabSource.includes('refundNote'));
    assert.ok(!txTabSource.includes('Note (Optional)'));
    assert.ok(!typesSource.includes('note?: string'));
    assert.ok(!moduleSource.includes('refundNote'));
  });

  it('2. Creating, editing/replacing, refunding, and quick-capturing transactions preserve Description without writing new transaction notes', () => {
    const accounts = makeEtbAccounts();

    const expense = buildDirectExpense({
      id: 'exp-1',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 100000,
      feeCents: 1500,
      feeExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      feeCategoryId: 'cat-fees',
      occurrenceDate: '2026-11-12',
      movementDate: '2026-11-12',
      description: 'Groceries at Shoa',
    });
    assert.equal(expense.entry.description, 'Groceries at Shoa');
    assert.equal(
      expense.postings.find((p) => p.id === 'exp-1-post-dr')?.note,
      undefined
    );
    assert.equal(
      expense.postings.find((p) => p.id === 'exp-1-post-cr')?.note,
      undefined
    );

    const income = buildDirectIncome({
      id: 'inc-1',
      assetAccountId: 'acc-cbe',
      incomeAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.income,
      categoryId: 'cat-salary',
      amountCents: 500000,
      occurrenceDate: '2026-11-12',
      movementDate: '2026-11-12',
      description: 'Monthly salary',
    });
    assert.equal(income.entry.description, 'Monthly salary');
    assert.ok(income.postings.every((p) => p.note === undefined));

    const transfer = buildTransfer({
      id: 'xfer-1',
      fromAssetAccountId: 'acc-cbe',
      toAssetAccountId: 'acc-telebirr',
      amountCents: 25000,
      date: '2026-11-12',
      description: 'Top up Telebirr',
    });
    assert.equal(transfer.entry.description, 'Top up Telebirr');
    assert.ok(transfer.postings.every((p) => p.note === undefined));

    // Edit/replace via correctJournalEntryV7 preserves new Description
    const replacement = buildDirectExpense({
      id: 'exp-2',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 120000,
      occurrenceDate: '2026-11-12',
      movementDate: '2026-11-12',
      description: 'Groceries updated',
      correctedFromEntryId: expense.entry.id,
    });
    const corrected = correctJournalEntryV7({
      originalEntryId: expense.entry.id,
      replacementEntry: replacement.entry,
      replacementPostings: replacement.postings,
      correctionReason: 'Receipt correction',
      accounts,
      entries: [expense.entry],
      postings: expense.postings,
      debts: [],
      allocations: [],
      commitments: [],
      commitmentSettlements: [],
      savingsGoals: [],
      simpleTransactions: [],
    });
    const replEntry = corrected.updatedEntries.find((e) => e.id === 'exp-2');
    assert.equal(replEntry?.description, 'Groceries updated');

    // Refund stops writing redundant "Refund for ..." posting note
    const refund = recordExpenseRefundV7({
      refundEntryId: 'ref-1',
      originalEntryId: expense.entry.id,
      refundAccountId: 'acc-cbe',
      refundCents: 40000,
      refundDateIso: '2026-11-13',
      entries: [expense.entry],
      postings: expense.postings,
      accounts,
    });
    assert.equal(refund.entry.description, 'Refund: Groceries at Shoa');
    assert.ok(refund.postings.every((p) => p.note === undefined));

    // Quick Capture uses description cleanly without writing note: 'Quick capture'
    const qc = buildQuickCaptureExpenseEntryV7({
      rawText: 'Coffee 120 ETB',
      accounts,
      categories: DEFAULT_EXPENSE_CATEGORIES,
      occurrenceDateIso: '2026-11-13',
    });
    assert.equal(qc.ok, true);
    if (qc.ok && qc.simpleTransaction && qc.postings) {
      assert.equal(
        (qc.simpleTransaction as SimpleTransaction & { note?: string }).note,
        undefined
      );
      assert.ok((qc.simpleTransaction.description || '').toLowerCase().includes('coffee'));
      assert.ok(qc.postings.every((p) => p.note === undefined));
    }
  });

  it('3. Description remains searchable and transaction Note-specific search clauses are removed', () => {
    const accounts = makeEtbAccounts();
    const exp = buildDirectExpense({
      id: 'exp-search',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 15000,
      occurrenceDate: '2026-11-12',
      movementDate: '2026-11-12',
      description: 'Bakery croissant',
    });
    const legacyPostingsWithNote: Posting[] = exp.postings.map((p, idx) =>
      idx === 0 ? { ...p, note: 'hidden-legacy-posting-note' } : p
    );

    const byDescription = filterJournalEntries(
      [exp.entry],
      legacyPostingsWithNote,
      { query: 'croissant' }
    );
    assert.equal(byDescription.length, 1);

    const byLegacyPostingNote = filterJournalEntries(
      [exp.entry],
      legacyPostingsWithNote,
      { query: 'hidden-legacy-posting-note' }
    );
    assert.equal(
      byLegacyPostingNote.length,
      0,
      'Search must not match transaction posting.note values'
    );

    // UI search also searches resolved description (including legacy note safely copied into blank description), not separate p.note
    const blankDescEntry = { ...exp.entry, id: 'exp-blank', description: '' };
    const blankDescPostings = legacyPostingsWithNote.map((p) => ({
      ...p,
      entryId: 'exp-blank',
    }));
    const listHtmlHiddenNote = renderToStaticMarkup(
      React.createElement(FinanceTransactionsTab, {
        entries: [exp.entry],
        postings: legacyPostingsWithNote,
        accounts,
        categories: DEFAULT_EXPENSE_CATEGORIES,
        onOpenComposer: () => {},
        onVoidEntry: () => ({ ok: true }),
        onRestoreEntry: () => ({ ok: true }),
        onRequestConfirm: () => {},
      })
    );
    assert.ok(!listHtmlHiddenNote.includes('hidden-legacy-posting-note'));

    const listHtmlMigratedTitle = renderToStaticMarkup(
      React.createElement(FinanceTransactionsTab, {
        entries: [blankDescEntry],
        postings: blankDescPostings,
        accounts,
        categories: DEFAULT_EXPENSE_CATEGORIES,
        onOpenComposer: () => {},
        onVoidEntry: () => ({ ok: true }),
        onRestoreEntry: () => ({ ok: true }),
        onRequestConfirm: () => {},
      })
    );
    assert.ok(listHtmlMigratedTitle.includes('hidden-legacy-posting-note'));
  });

  it('4. Postings CSV export removes the transaction note column while Parties CSV and other export fields remain intact', () => {
    const exp = buildDirectExpense({
      id: 'exp-csv',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 25000,
      occurrenceDate: '2026-11-12',
      movementDate: '2026-11-12',
      description: 'Lunch',
    });
    const postingsWithHistoricalNote: Posting[] = exp.postings.map((p) => ({
      ...p,
      note: 'Historical posting memo',
    }));

    const postingsCsv = DataPortabilityService.exportPostingsCsv(
      postingsWithHistoricalNote
    ).replace(/^\uFEFF/, '');
    const headerLine = postingsCsv.split(/\r?\n/)[0];
    assert.equal(
      headerLine,
      '"id","entryId","accountId","amountCents","amount_decimal","direction","accountMovementDate","categoryId"'
    );
    assert.ok(!postingsCsv.includes('Historical posting memo'));

    // Parties notes CSV stays completely intact
    const parties: Party[] = [
      {
        id: 'party-1',
        name: 'Abebe',
        phone: '+251911000000',
        notes: 'Colleague from work',
        isArchived: false,
        createdAt: '2026-11-01T00:00:00Z',
      },
    ];
    const partiesCsv = DataPortabilityService.exportPartiesCsv(parties);
    assert.ok(partiesCsv.includes('"notes"'));
    assert.ok(partiesCsv.includes('Colleague from work'));

    // Transactions CSV preserves non-empty description and safely maps blank description -> historical tx.note
    const txBlankDesc = {
      id: 'tx-1',
      type: 'expense' as const,
      amountCents: 5000,
      accountId: 'acc-cbe',
      categoryId: 'cat-food',
      description: '',
      note: 'Legacy tea bill',
      transactionDate: '2026-11-10',
      createdAt: '2026-11-10T00:00:00Z',
      updatedAt: '2026-11-10T00:00:00Z',
    };
    const txBoth = {
      ...txBlankDesc,
      id: 'tx-2',
      description: 'Official coffee receipt',
      note: 'Legacy note stays separate',
    };
    const txCsv = DataPortabilityService.exportTransactionsCsv([
      txBlankDesc,
      txBoth,
    ]);
    assert.ok(txCsv.includes('Legacy tea bill'));
    assert.ok(txCsv.includes('Official coffee receipt'));
    assert.ok(!txCsv.includes('Official coffee receipt — Legacy note stays separate'));
  });

  it('5. Historical note values are preserved, unambiguously copied into empty Descriptions only, and never overwrite or duplicate non-empty Descriptions', () => {
    // Domain helpers: ignore system markers, avoid ambiguity on conflicting notes
    assert.equal(
      collectUnambiguousHistoricalPostingNote([
        {
          id: 'p1',
          note: 'Bank / transaction fee',
        },
        {
          id: 'p2',
          note: 'Old taxi receipt',
        },
      ]),
      'Old taxi receipt'
    );
    assert.equal(
      collectUnambiguousHistoricalPostingNote([
        {
          id: 'p1',
          note: 'Note A',
        },
        {
          id: 'p2',
          note: 'Note B',
        },
      ]),
      undefined
    );

    assert.equal(
      resolveDescriptionWithHistoricalNote({
        description: '',
        legacyNote: 'Historical note only',
      }),
      'Historical note only'
    );
    assert.equal(
      resolveDescriptionWithHistoricalNote({
        description: 'Existing description',
        legacyNote: 'Old historical note',
      }),
      'Existing description'
    );

    // SimpleTransaction hydration preserves original note and copies into blank description safely
    const accounts = makeEtbAccounts();
    const legacyTxs: (SimpleTransaction & { note?: string })[] = [
      {
        id: 'legacy-blank-desc',
        type: 'expense',
        amountCents: 8000,
        accountId: 'acc-cbe',
        categoryId: 'cat-food',
        description: '   ',
        note: 'Dinner at Bole',
        transactionDate: '2026-11-05',
        createdAt: '2026-11-05T10:00:00Z',
        updatedAt: '2026-11-05T10:00:00Z',
      },
      {
        id: 'legacy-both',
        type: 'expense',
        amountCents: 4000,
        accountId: 'acc-cbe',
        categoryId: 'cat-transport',
        description: 'Ride to office',
        note: 'Bajaj driver',
        transactionDate: '2026-11-06',
        createdAt: '2026-11-06T10:00:00Z',
        updatedAt: '2026-11-06T10:00:00Z',
      },
    ];
    const hydrated = hydrateLedgerFromSimpleTransactions({
      transactions: legacyTxs,
      entries: [],
      postings: [],
      accounts,
    });
    const migratedBlank = hydrated.entries.find(
      (e) => e.legacySourceTxId === 'legacy-blank-desc'
    );
    const migratedBoth = hydrated.entries.find(
      (e) => e.legacySourceTxId === 'legacy-both'
    );
    assert.equal(migratedBlank?.description, 'Dinner at Bole');
    assert.equal(migratedBoth?.description, 'Ride to office');
    // Historical posting note remains intact for legacy record preservation
    assert.ok(
      hydrated.postings
        .filter((p) => p.entryId === migratedBoth?.id)
        .some((p) => p.note === 'Bajaj driver')
    );

    // SharedStateBridge import preserves historical posting.note & tx.note while filling blank descriptions only
    withMockBrowserStorage((store) => {
      const payload = {
        schemaVersion: 5,
        snapshotFormatVersion: 2,
        databaseSchemaVersion: 12,
        financeSchemaVersion: 7,
        appVersion: '2.0.0',
        exportedAt: '2026-11-12T10:00:00Z',
        isFinanceSetupCompleted: true,
        openingBalanceCents: 500000,
        accounts: [
          {
            id: 'acc-cbe',
            name: 'CBE',
            type: 'asset',
            subType: 'bank',
            currencyCode: 'ETB',
            openingBalanceCents: 500000,
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
            id: SYSTEM_CONTROL_ACCOUNT_IDS.equity,
            name: 'Opening Balance Equity',
            type: 'equity',
            subType: 'opening_equity',
            currencyCode: 'ETB',
            isSystem: true,
            isArchived: false,
            createdAt: '2026-11-01T00:00:00Z',
          },
        ],
        categories: DEFAULT_EXPENSE_CATEGORIES,
        parties: [],
        transactions: [],
        journalEntries: [
          {
            id: 'je-blank',
            entryType: 'standard',
            description: '',
            occurrenceDate: '2026-11-10',
            isVoided: false,
            createdAt: '2026-11-10T10:00:00Z',
          },
          {
            id: 'je-described',
            entryType: 'standard',
            description: 'Supermarket groceries',
            occurrenceDate: '2026-11-11',
            isVoided: false,
            createdAt: '2026-11-11T10:00:00Z',
          },
        ],
        postings: [
          {
            id: 'p-b-1',
            entryId: 'je-blank',
            accountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
            amountCents: 5000,
            direction: 'debit',
            accountMovementDate: '2026-11-10',
            categoryId: 'cat-food',
            note: 'Copied legacy note',
          },
          {
            id: 'p-b-2',
            entryId: 'je-blank',
            accountId: 'acc-cbe',
            amountCents: 5000,
            direction: 'credit',
            accountMovementDate: '2026-11-10',
          },
          {
            id: 'p-d-1',
            entryId: 'je-described',
            accountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
            amountCents: 9000,
            direction: 'debit',
            accountMovementDate: '2026-11-11',
            categoryId: 'cat-food',
            note: 'Historical receipt note',
          },
          {
            id: 'p-d-2',
            entryId: 'je-described',
            accountId: 'acc-cbe',
            amountCents: 9000,
            direction: 'credit',
            accountMovementDate: '2026-11-11',
          },
        ],
        debts: [],
        settlementAllocations: [],
        commitments: [],
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

      const res = SharedStateBridge.importFromAndroidJson(JSON.stringify(payload));
      assert.equal(res.success, true, res.error);
      assert.equal(
        res.state?.journalEntries?.find((e) => e.id === 'je-blank')?.description,
        'Copied legacy note'
      );
      assert.equal(
        res.state?.journalEntries?.find((e) => e.id === 'je-described')?.description,
        'Supermarket groceries'
      );
      // Original historical notes remain preserved on postings in storage
      const storedPostings = JSON.parse(store.get('daywell_postings') || '[]') as Posting[];
      assert.equal(
        storedPostings.find((p) => p.id === 'p-b-1')?.note,
        'Copied legacy note'
      );
      assert.equal(
        storedPostings.find((p) => p.id === 'p-d-1')?.note,
        'Historical receipt note'
      );
    });
  });

  it('6. Separate Daywell Notes module continues to work normally', () => {
    const saved = createWebNoteRecord<TaskNoteRecord>({
      existingNotes: [],
      title: 'Meeting reflection',
      content: 'Unrelated standalone note content stays untouched',
      notebook: 'Personal',
      tags: ['journal'],
    });
    assert.equal(saved.title, 'Meeting reflection');
    assert.equal(
      matchesNoteSearchQuery(saved, 'standalone note content'),
      true
    );
  });
});
