import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  Account,
  CANONICAL_DEBT_STATUSES,
  CANONICAL_ENTRY_TYPES,
  DEBT_STATUS_LEGACY_ALIASES,
  Debt,
  DebtStatus,
  DoubleEntryValidationError,
  ENTRY_TYPE_LEGACY_ALIASES,
  EntryType,
  JournalEntry,
  Posting,
  assertEtbPostingAccounts,
  assertVerifiedEtbAccount,
  auditCurrencyIsolation,
  buildDirectExpense,
  calculateAvailableToSpend,
  calculateLiquidCash,
  calculateNetPosition,
  calculateTotalReceivables,
  classifyCurrencyCode,
  generateCashFlowReport,
  generateOccurrenceReport,
  normalizeDebtStatus,
  normalizeEntryType,
  parseDebtStatus,
  parseEntryType,
  tryNormalizeDebtStatus,
  tryNormalizeEntryType,
} from './doubleEntryFinance';
import {
  CANONICAL_SEED_DATABASE,
  SYSTEM_CONTROL_ACCOUNT_IDS,
  SharedAccount,
} from './sharedFoundation';
import { SharedStateBridge } from '../services/sharedStateBridge';

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
    if (prevWindow === undefined) {
      delete (globalThis as any).window;
    } else {
      (globalThis as any).window = prevWindow;
    }
    if (prevLocalStorage === undefined) {
      delete (globalThis as any).localStorage;
    } else {
      (globalThis as any).localStorage = prevLocalStorage;
    }
  }
}

function makeAccount(
  id: string,
  name: string,
  currencyCode: string,
  openingBalanceCents = 0,
  opts: Partial<Account> = {}
): Account {
  return {
    id,
    name,
    type: opts.type || 'asset',
    subType: opts.subType || 'bank',
    currencyCode,
    openingBalanceCents,
    openingBalanceDate: '2026-11-01',
    isArchived: false,
    createdAt: '2026-11-01T00:00:00.000Z',
    ...opts,
  };
}

describe('Finance Stage A — Cross-Platform Enum Unification & Safe Legacy Backup/Restore', () => {
  it('1. Every canonical EntryType value round-trips identically through domain parsers and SharedStateBridge', () => {
    const expectedCanonical: readonly EntryType[] = [
      'standard',
      'transfer',
      'debt_issuance',
      'settlement',
      'split_expense',
      'adjustment',
      'write_off',
    ];
    assert.deepStrictEqual(CANONICAL_ENTRY_TYPES, expectedCanonical);

    for (const value of expectedCanonical) {
      assert.strictEqual(tryNormalizeEntryType(value), value);
      assert.strictEqual(normalizeEntryType(value), value);
      assert.strictEqual(parseEntryType(value), value);
    }

    withMockBrowserStorage((store) => {
      const journalEntries = expectedCanonical.map((entryType, idx) => ({
        id: `je-canon-${idx + 1}`,
        entryType,
        description: `Canonical ${entryType}`,
        occurrenceDate: '2026-11-15',
        isVoided: false,
        createdAt: '2026-11-15T08:00:00.000Z',
      }));

      const importRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          ...CANONICAL_SEED_DATABASE,
          schemaVersion: 5,
          financeSchemaVersion: 7,
          accounts: [
            {
              id: 'acc-etb',
              name: 'CBE',
              type: 'asset',
              subType: 'bank',
              currencyCode: 'ETB',
            },
          ],
          journalEntries,
        })
      );
      assert.strictEqual(importRes.success, true, importRes.error);
      assert.deepStrictEqual(
        importRes.state?.journalEntries?.map((j) => j.entryType),
        expectedCanonical
      );

      const exportedJson = SharedStateBridge.exportToAndroidJson();
      const exported = JSON.parse(exportedJson);
      assert.deepStrictEqual(
        exported.journalEntries.map((j: any) => j.entryType),
        expectedCanonical
      );

      store.clear();
      const reimportRes = SharedStateBridge.importFromAndroidJson(exportedJson);
      assert.strictEqual(reimportRes.success, true, reimportRes.error);
      assert.deepStrictEqual(
        reimportRes.state?.journalEntries?.map((j) => j.entryType),
        expectedCanonical
      );
    });
  });

  it('2. Every canonical DebtStatus value round-trips identically through domain parsers and SharedStateBridge', () => {
    const expectedCanonical: readonly DebtStatus[] = [
      'active',
      'settled',
      'written_off',
      'voided',
    ];
    assert.deepStrictEqual(CANONICAL_DEBT_STATUSES, expectedCanonical);

    for (const value of expectedCanonical) {
      assert.strictEqual(tryNormalizeDebtStatus(value), value);
      assert.strictEqual(normalizeDebtStatus(value), value);
      assert.strictEqual(parseDebtStatus(value), value);
    }

    withMockBrowserStorage((store) => {
      const debts = expectedCanonical.map((status, idx) => ({
        id: `debt-canon-${idx + 1}`,
        originEntryId: 'je-origin',
        partyId: 'party-1',
        debtType: 'receivable',
        principalCents: 10000,
        outstandingCents: status === 'active' ? 5000 : 0,
        status,
        createdAt: '2026-11-15T08:00:00.000Z',
      }));

      const importRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          ...CANONICAL_SEED_DATABASE,
          schemaVersion: 5,
          financeSchemaVersion: 7,
          parties: [{ id: 'party-1', name: 'Dawit' }],
          journalEntries: [
            {
              id: 'je-origin',
              entryType: 'debt_issuance',
              occurrenceDate: '2026-11-15',
            },
          ],
          debts,
        })
      );
      assert.strictEqual(importRes.success, true, importRes.error);
      assert.deepStrictEqual(
        importRes.state?.debts?.map((d) => d.status),
        expectedCanonical
      );

      const exportedJson = SharedStateBridge.exportToAndroidJson();
      const exported = JSON.parse(exportedJson);
      assert.deepStrictEqual(
        exported.debts.map((d: any) => d.status),
        expectedCanonical
      );

      store.clear();
      const reimportRes = SharedStateBridge.importFromAndroidJson(exportedJson);
      assert.strictEqual(reimportRes.success, true, reimportRes.error);
      assert.deepStrictEqual(
        reimportRes.state?.debts?.map((d) => d.status),
        expectedCanonical
      );
    });
  });

  it('3. All documented legacy EntryType & DebtStatus aliases normalize cleanly to canonical snake_case', () => {
    const expectedEntryAliases: Record<string, EntryType> = {
      debtIssuance: 'debt_issuance',
      splitExpense: 'split_expense',
      writeOff: 'write_off',
      debt_origin: 'debt_issuance',
      debt_settlement: 'settlement',
      opening_balance: 'adjustment',
      opening: 'adjustment',
      correction: 'adjustment',
      void_reversal: 'adjustment',
    };
    assert.deepStrictEqual(ENTRY_TYPE_LEGACY_ALIASES, expectedEntryAliases);

    const expectedDebtAliases: Record<string, DebtStatus> = {
      partially_settled: 'active',
      writtenOff: 'written_off',
    };
    assert.deepStrictEqual(DEBT_STATUS_LEGACY_ALIASES, expectedDebtAliases);

    for (const [alias, canonical] of Object.entries(expectedEntryAliases)) {
      assert.strictEqual(normalizeEntryType(alias), canonical, alias);
      assert.strictEqual(parseEntryType(` ${alias} `), canonical, alias);
    }
    for (const [alias, canonical] of Object.entries(expectedDebtAliases)) {
      assert.strictEqual(normalizeDebtStatus(alias), canonical, alias);
      assert.strictEqual(parseDebtStatus(` ${alias} `), canonical, alias);
    }

    withMockBrowserStorage(() => {
      const importRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          ...CANONICAL_SEED_DATABASE,
          schemaVersion: 7,
          parties: [{ id: 'pa-alias', name: 'Selam' }],
          journalEntries: Object.keys(expectedEntryAliases).map((alias, idx) => ({
            id: `je-alias-${idx + 1}`,
            entryType: alias,
            occurrenceDate: '2026-11-10',
          })),
          debts: Object.keys(expectedDebtAliases).map((alias, idx) => ({
            id: `debt-alias-${idx + 1}`,
            originEntryId: 'je-alias-1',
            partyId: 'pa-alias',
            debtType: 'payable',
            principalCents: 25000,
            outstandingCents: alias === 'partially_settled' ? 12000 : 0,
            status: alias,
          })),
        })
      );
      assert.strictEqual(importRes.success, true, importRes.error);

      const exported = JSON.parse(SharedStateBridge.exportToAndroidJson());
      assert.deepStrictEqual(
        exported.journalEntries.map((j: any) => j.entryType),
        Object.values(expectedEntryAliases)
      );
      assert.deepStrictEqual(
        exported.debts.map((d: any) => d.status),
        ['active', 'written_off']
      );
    });
  });

  it('4. Web, Flutter, and shared_foundation schema_contracts.json define identical canonical enum contracts', () => {
    const repoRoot = path.resolve(import.meta.dirname, '../..');
    const schemaContracts = JSON.parse(
      fs.readFileSync(path.join(repoRoot, 'shared_foundation/schema_contracts.json'), 'utf8')
    );
    const dartCore = fs.readFileSync(
      path.join(repoRoot, 'flutter_app/lib/core/shared_foundation_core.dart'),
      'utf8'
    );
    const dartEngine = fs.readFileSync(
      path.join(repoRoot, 'flutter_app/lib/domain/finance/double_entry_engine.dart'),
      'utf8'
    );

    const jeSchemaEnum: string[] = schemaContracts.entities.JournalEntry.fields.entryType.enum;
    const debtSchemaEnum: string[] = schemaContracts.entities.Debt.fields.status.enum;
    assert.deepStrictEqual([...CANONICAL_ENTRY_TYPES], jeSchemaEnum);
    assert.deepStrictEqual([...CANONICAL_DEBT_STATUSES], debtSchemaEnum);

    for (const value of CANONICAL_ENTRY_TYPES) {
      assert.ok(
        dartCore.includes(`'${value}'`),
        `Flutter shared_foundation_core.dart missing EntryType '${value}'`
      );
      assert.ok(
        dartEngine.includes(`'${value}'`),
        `Flutter double_entry_engine.dart missing EntryType '${value}'`
      );
    }
    for (const value of CANONICAL_DEBT_STATUSES) {
      assert.ok(
        dartCore.includes(`'${value}'`),
        `Flutter shared_foundation_core.dart missing DebtStatus '${value}'`
      );
      assert.ok(
        dartEngine.includes(`'${value}'`),
        `Flutter double_entry_engine.dart missing DebtStatus '${value}'`
      );
    }
    for (const alias of Object.keys(ENTRY_TYPE_LEGACY_ALIASES)) {
      assert.ok(
        dartEngine.includes(`'${alias}'`),
        `Flutter double_entry_engine.dart missing EntryType legacy alias '${alias}'`
      );
    }
    for (const alias of Object.keys(DEBT_STATUS_LEGACY_ALIASES)) {
      assert.ok(
        dartEngine.includes(`'${alias}'`),
        `Flutter double_entry_engine.dart missing DebtStatus legacy alias '${alias}'`
      );
    }
  });

  it('5. Unknown, blank, and non-string enum values fail closed safely without corrupting persisted storage', () => {
    for (const badValue of ['', '   ', 'expense', 'unknown_entry', 'cancelled', 'partially_voided']) {
      assert.strictEqual(tryNormalizeEntryType(badValue), null);
      assert.strictEqual(tryNormalizeDebtStatus(badValue), null);
      assert.throws(() => normalizeEntryType(badValue), DoubleEntryValidationError);
      assert.throws(() => normalizeDebtStatus(badValue), DoubleEntryValidationError);
      assert.throws(() => parseEntryType(badValue), DoubleEntryValidationError);
      assert.throws(() => parseDebtStatus(badValue), DoubleEntryValidationError);
    }
    assert.throws(() => parseEntryType(42), DoubleEntryValidationError);
    assert.throws(() => parseDebtStatus(true), DoubleEntryValidationError);

    withMockBrowserStorage((store) => {
      const seedRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          ...CANONICAL_SEED_DATABASE,
          schemaVersion: 5,
          accounts: [
            { id: 'acc-keep', name: 'Keep', type: 'asset', currencyCode: 'ETB' },
          ],
        })
      );
      assert.strictEqual(seedRes.success, true);
      const baseline = new Map(store);

      const invalidPayloads: Array<{ label: string; patch: Record<string, unknown> }> = [
        {
          label: 'unknown entryType string',
          patch: {
            journalEntries: [
              { id: 'je-bad', entryType: 'mystery_type', occurrenceDate: '2026-11-15' },
            ],
          },
        },
        {
          label: 'blank entryType string',
          patch: {
            journalEntries: [
              { id: 'je-blank', entryType: '  ', occurrenceDate: '2026-11-15' },
            ],
          },
        },
        {
          label: 'non-string entryType',
          patch: {
            journalEntries: [
              { id: 'je-num', entryType: 99, occurrenceDate: '2026-11-15' },
            ],
          },
        },
        {
          label: 'unknown debt status string',
          patch: {
            parties: [{ id: 'pa-bad', name: 'P' }],
            journalEntries: [
              { id: 'je-ok', entryType: 'debt_issuance', occurrenceDate: '2026-11-15' },
            ],
            debts: [
              {
                id: 'debt-bad',
                originEntryId: 'je-ok',
                partyId: 'pa-bad',
                principalCents: 1000,
                status: 'archived_forever',
              },
            ],
          },
        },
        {
          label: 'blank debt status string',
          patch: {
            parties: [{ id: 'pa-blank', name: 'P' }],
            journalEntries: [
              { id: 'je-ok-2', entryType: 'debt_issuance', occurrenceDate: '2026-11-15' },
            ],
            debts: [
              {
                id: 'debt-blank',
                originEntryId: 'je-ok-2',
                partyId: 'pa-blank',
                principalCents: 1000,
                status: '',
              },
            ],
          },
        },
      ];

      for (const tc of invalidPayloads) {
        const res = SharedStateBridge.importFromAndroidJson(
          JSON.stringify({
            schemaVersion: 8,
            accounts: [{ id: 'acc-1', name: 'CBE', type: 'asset', currencyCode: 'ETB' }],
            ...tc.patch,
          })
        );
        assert.strictEqual(res.success, false, `${tc.label} must fail closed`);
        assert.strictEqual(res.errorKind, 'invalid_payload', tc.label);
        assert.deepStrictEqual(
          Array.from(store.entries()),
          Array.from(baseline.entries()),
          `Store mutated after failed ${tc.label}`
        );
      }
    });
  });

  it('6 & 7. v7/v8 and canonical format-2 snapshots preserve isolated non-ETB and empty-currency accounts with full ledger relationships across round-trips', () => {
    const configs: Array<{ label: string; header: Record<string, number> }> = [
      { label: 'v7 format-1', header: { schemaVersion: 7, financeSchemaVersion: 7 } },
      { label: 'v8 format-1', header: { schemaVersion: 8, financeSchemaVersion: 7 } },
      {
        label: 'format-2 web',
        header: { schemaVersion: 5, snapshotFormatVersion: 2, financeSchemaVersion: 7 },
      },
      {
        label: 'format-2 android db v9',
        header: { schemaVersion: 5, snapshotFormatVersion: 2, databaseSchemaVersion: 9, financeSchemaVersion: 7 },
      },
    ];
    for (const cfg of configs) {
      withMockBrowserStorage((store) => {
        const snapshot = {
          ...cfg.header,
          isFinanceSetupCompleted: true,
          openingBalanceCents: 100000,
          accounts: [
            {
              id: 'acc-etb',
              name: 'CBE Birr',
              type: 'asset',
              subType: 'bank',
              isSystem: false,
              currencyCode: 'ETB',
              openingBalanceCents: 100000,
              openingBalanceDate: '2026-11-01',
              isArchived: false,
              createdAt: '2026-11-01T08:00:00.000Z',
            },
            {
              id: 'acc-usd',
              name: 'Remote USD',
              type: 'asset',
              subType: 'bank',
              isSystem: false,
              currencyCode: 'usd',
              openingBalanceCents: 250000,
              openingBalanceDate: '2026-11-01',
              isArchived: false,
              createdAt: '2026-11-01T08:00:00.000Z',
            },
            {
              id: 'acc-unv',
              name: 'Legacy Pocket',
              type: 'asset',
              subType: 'cash',
              isSystem: false,
              currencyCode: '',
              openingBalanceCents: 40000,
              openingBalanceDate: '2026-11-01',
              isArchived: false,
              createdAt: '2026-11-01T08:00:00.000Z',
            },
            {
              id: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
              name: 'System Expense',
              type: 'expense',
              subType: 'nominal_expense',
              isSystem: true,
              currencyCode: 'ETB',
              openingBalanceCents: 0,
              isArchived: false,
              createdAt: '2026-11-01T08:00:00.000Z',
            },
            {
              id: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
              name: 'System Receivable',
              type: 'asset',
              subType: 'receivable',
              isSystem: true,
              currencyCode: 'ETB',
              openingBalanceCents: 0,
              isArchived: false,
              createdAt: '2026-11-01T08:00:00.000Z',
            },
          ],
          categories: [
            { id: 'cat-food', name: 'Food', type: 'expense', sortOrder: 1 },
          ],
          transactions: [
            {
              id: 'tx-etb-1',
              amountCents: 5000,
              type: 'expense',
              categoryId: 'cat-food',
              accountId: 'acc-etb',
              transactionDate: '2026-11-10',
              createdAt: '2026-11-10T08:00:00.000Z',
            },
            {
              id: 'tx-usd-1',
              amountCents: 12000,
              type: 'expense',
              categoryId: 'cat-food',
              accountId: 'acc-usd',
              transactionDate: '2026-11-11',
              createdAt: '2026-11-11T08:00:00.000Z',
            },
            {
              id: 'tx-unv-1',
              amountCents: 3000,
              type: 'expense',
              categoryId: 'cat-food',
              accountId: 'acc-unv',
              transactionDate: '2026-11-12',
              createdAt: '2026-11-12T08:00:00.000Z',
            },
          ],
          parties: [
            { id: 'party-usd', name: 'Foreign Client', isArchived: false },
          ],
          journalEntries: [
            {
              id: 'je-usd-exp',
              entryType: 'standard',
              description: 'Software USD',
              occurrenceDate: '2026-11-11',
              isVoided: false,
              createdAt: '2026-11-11T08:00:00.000Z',
            },
            {
              id: 'je-usd-debt',
              entryType: 'debt_origin',
              description: 'USD Receivable',
              occurrenceDate: '2026-11-12',
              isVoided: false,
              createdAt: '2026-11-12T08:00:00.000Z',
            },
          ],
          postings: [
            {
              id: 'p-u1',
              entryId: 'je-usd-exp',
              accountId: 'acc-usd',
              amountCents: 12000,
              direction: 'credit',
              categoryId: 'cat-food',
              accountMovementDate: '2026-11-11',
            },
            {
              id: 'p-u2',
              entryId: 'je-usd-exp',
              accountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
              amountCents: 12000,
              direction: 'debit',
              categoryId: 'cat-food',
              accountMovementDate: '2026-11-11',
            },
            {
              id: 'p-d1',
              entryId: 'je-usd-debt',
              accountId: 'acc-usd',
              amountCents: 50000,
              direction: 'credit',
              accountMovementDate: '2026-11-12',
            },
            {
              id: 'p-d2',
              entryId: 'je-usd-debt',
              accountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
              amountCents: 50000,
              direction: 'debit',
              accountMovementDate: '2026-11-12',
            },
          ],
          debts: [
            {
              id: 'debt-usd-1',
              originEntryId: 'je-usd-debt',
              partyId: 'party-usd',
              debtType: 'receivable',
              principalCents: 50000,
              outstandingCents: 50000,
              status: 'partially_settled',
              createdAt: '2026-11-12T08:00:00.000Z',
            },
          ],
        };

        const import1 = SharedStateBridge.importFromAndroidJson(JSON.stringify(snapshot));
        assert.strictEqual(import1.success, true, `${cfg.label} import failed: ${import1.error}`);

        const exportedJson1 = SharedStateBridge.exportToAndroidJson();
        const exported1 = JSON.parse(exportedJson1);

        // Round-trip via empty storage preserves accounts, amounts, currencies, and links
        store.clear();
        const import2 = SharedStateBridge.importFromAndroidJson(exportedJson1);
        assert.strictEqual(import2.success, true, `${cfg.label} re-import failed: ${import2.error}`);
        const exported2 = JSON.parse(SharedStateBridge.exportToAndroidJson());

        const { exportedAt: _a, ...cmp1 } = exported1;
        const { exportedAt: _b, ...cmp2 } = exported2;
        assert.deepStrictEqual(cmp2, cmp1);

        const accountsById = new Map<string, SharedAccount>(
          exported2.accounts.map((a: SharedAccount) => [a.id, a])
        );
        assert.strictEqual(accountsById.get('acc-etb')?.currencyCode, 'ETB');
        assert.strictEqual(accountsById.get('acc-usd')?.currencyCode, 'USD');
        assert.strictEqual(accountsById.get('acc-usd')?.openingBalanceCents, 250000);
        assert.strictEqual(accountsById.get('acc-unv')?.currencyCode, '');
        assert.strictEqual(accountsById.get('acc-unv')?.openingBalanceCents, 40000);

        assert.deepStrictEqual(
          exported2.transactions.map((t: any) => [t.id, t.accountId, t.amountCents]),
          [
            ['tx-etb-1', 'acc-etb', 5000],
            ['tx-usd-1', 'acc-usd', 12000],
            ['tx-unv-1', 'acc-unv', 3000],
          ]
        );
        assert.deepStrictEqual(
          exported2.journalEntries.map((j: JournalEntry) => [j.id, j.entryType]),
          [
            ['je-usd-exp', 'standard'],
            ['je-usd-debt', 'debt_issuance'],
          ]
        );
        assert.strictEqual(exported2.postings.length, 4);
        assert.strictEqual(exported2.debts[0].id, 'debt-usd-1');
        assert.strictEqual(exported2.debts[0].partyId, 'party-usd');
        assert.strictEqual(exported2.debts[0].status, 'active');
      });
    }
  });

  it('8. Preserved non-ETB and empty-currency accounts stay isolated from ETB totals and reject normal ETB writes', () => {
    const etbAcc = makeAccount('acc-etb', 'CBE Birr', 'ETB', 100000);
    const usdAcc = makeAccount('acc-usd', 'USD Bank', 'USD', 250000);
    const unvAcc = makeAccount('acc-unv', 'Legacy Cash', '', 40000);
    const sysExp = makeAccount(SYSTEM_CONTROL_ACCOUNT_IDS.expense, 'Expense', 'ETB', 0, {
      type: 'expense',
      subType: 'nominal_expense',
      isSystem: true,
    });
    const sysRec = makeAccount(SYSTEM_CONTROL_ACCOUNT_IDS.receivable, 'Receivable', 'ETB', 0, {
      type: 'asset',
      subType: 'receivable',
      isSystem: true,
    });

    const etbExp = buildDirectExpense({
      id: 'je-exp-etb',
      assetAccountId: 'acc-etb',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      amountCents: 15000,
      occurrenceDate: '2026-11-05',
      movementDate: '2026-11-05',
      description: 'Groceries',
      categoryId: 'cat-food',
    });

    // Pre-existing preserved USD & unverified ledger entries imported from legacy snapshot
    const usdEntry: JournalEntry = {
      id: 'je-usd',
      entryType: 'standard',
      description: 'USD expense',
      occurrenceDate: '2026-11-06',
      isVoided: false,
      createdAt: '2026-11-06T08:00:00.000Z',
    };
    const usdDebtEntry: JournalEntry = {
      id: 'je-usd-debt',
      entryType: 'debt_issuance',
      description: 'USD loan',
      occurrenceDate: '2026-11-07',
      isVoided: false,
      createdAt: '2026-11-07T08:00:00.000Z',
    };
    const unvEntry: JournalEntry = {
      id: 'je-unv',
      entryType: 'standard',
      description: 'Unverified cash spend',
      occurrenceDate: '2026-11-08',
      isVoided: false,
      createdAt: '2026-11-08T08:00:00.000Z',
    };
    const postings: Posting[] = [
      ...etbExp.postings,
      {
        id: 'p-usd-1',
        entryId: 'je-usd',
        accountId: 'acc-usd',
        amountCents: 20000,
        direction: 'credit',
        accountMovementDate: '2026-11-06',
      },
      {
        id: 'p-usd-2',
        entryId: 'je-usd',
        accountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
        amountCents: 20000,
        direction: 'debit',
        accountMovementDate: '2026-11-06',
      },
      {
        id: 'p-usdd-1',
        entryId: 'je-usd-debt',
        accountId: 'acc-usd',
        amountCents: 30000,
        direction: 'credit',
        accountMovementDate: '2026-11-07',
      },
      {
        id: 'p-usdd-2',
        entryId: 'je-usd-debt',
        accountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
        amountCents: 30000,
        direction: 'debit',
        accountMovementDate: '2026-11-07',
      },
      {
        id: 'p-unv-1',
        entryId: 'je-unv',
        accountId: 'acc-unv',
        amountCents: 5000,
        direction: 'credit',
        accountMovementDate: '2026-11-08',
      },
      {
        id: 'p-unv-2',
        entryId: 'je-unv',
        accountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
        amountCents: 5000,
        direction: 'debit',
        accountMovementDate: '2026-11-08',
      },
    ];
    const entries = [etbExp.entry, usdEntry, usdDebtEntry, unvEntry];
    const debts: Debt[] = [
      {
        id: 'debt-usd',
        originEntryId: 'je-usd-debt',
        partyId: 'party-1',
        debtType: 'receivable',
        principalCents: 30000,
        outstandingCents: 30000,
        status: 'active',
        createdAt: '2026-11-07T08:00:00.000Z',
      },
    ];
    const accounts = [etbAcc, usdAcc, unvAcc, sysExp, sysRec];

    assert.strictEqual(classifyCurrencyCode(usdAcc.currencyCode), 'verified_non_etb');
    assert.strictEqual(classifyCurrencyCode(unvAcc.currencyCode), 'unverified');

    const audit = auditCurrencyIsolation({ accounts, entries, postings, debts });
    assert.strictEqual(audit.nonEtbAccountCount, 2);
    assert.strictEqual(audit.unverifiedAccountCount, 1);
    assert.strictEqual(audit.excludedNonEtbEntryCount, 2);
    assert.strictEqual(audit.currencyReviewEntryCount, 1);
    assert.strictEqual(audit.excludedNonEtbDebtCount, 1);

    // ETB totals reflect ONLY CBE Birr (100,000 - 15,000 = 85,000)
    const liquidCash = calculateLiquidCash(accounts, postings, entries);
    assert.strictEqual(liquidCash, 85000);
    assert.strictEqual(
      calculateAvailableToSpend({
        liquidCashCents: liquidCash,
        unpaidPayablesDueInPeriodCents: 0,
        reservedSavingsCents: 0,
      }),
      85000
    );
    assert.strictEqual(
      calculateTotalReceivables(debts, { accounts, entries, postings }),
      0
    );
    assert.strictEqual(
      calculateNetPosition(accounts, postings, debts, entries),
      85000
    );

    const pnl = generateOccurrenceReport({
      accounts,
      entries,
      postings,
      categories: [{ id: 'cat-food', name: 'Food', type: 'expense', colorHex: '#1B4D3E' }],
      debts,
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    });
    assert.strictEqual(pnl.totalExpenseCents, 15000);

    const cashFlow = generateCashFlowReport({
      accounts,
      entries,
      postings,
      debts,
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    });
    assert.strictEqual(cashFlow.totalCashOutflowCents, 15000);

    // Normal ETB ledger writes remain blocked for non-ETB and unverified accounts
    assert.throws(() => assertVerifiedEtbAccount(usdAcc, 'Account'), DoubleEntryValidationError);
    assert.throws(() => assertVerifiedEtbAccount(unvAcc, 'Account'), DoubleEntryValidationError);
    assert.throws(
      () => assertEtbPostingAccounts({ accounts, accountIds: [usdAcc.id] }),
      DoubleEntryValidationError
    );
    assert.throws(
      () => assertEtbPostingAccounts({ accounts, accountIds: [unvAcc.id] }),
      DoubleEntryValidationError
    );
  });
});
