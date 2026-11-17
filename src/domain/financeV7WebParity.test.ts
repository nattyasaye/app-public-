import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  Account,
  buildBorrowMoney,
  buildDebtSettlement,
  buildDebtWriteOff,
  buildDirectExpense,
  buildLendMoney,
  buildSplitExpense,
  buildThirdPartyPaidExpense,
  calculateAvailableToSpendBreakdownV7,
  calculateCommitmentSettledCents,
  calculateV7AccountBalance,
  Debt,
  ensureSystemControlAccounts,
  fundSavingsGoalV7,
  getCommitmentRemainingCents,
  getOpeningBalanceRevisionHistory,
  hydrateLedgerFromSimpleTransactions,
  JournalEntry,
  Party,
  Posting,
  processDueRecurringRulesV7,
  recordCommitmentSettlementV7,
  reviseAccountOpeningBalanceV7,
  SettlementAllocation,
  SharedCommitment,
  SharedCommitmentSettlement,
  SharedRecurringRule,
  SharedSavingsGoal,
  skipNextRecurringOccurrenceV7,
  verifyFinanceV7Integrity,
  voidCommitmentSettlementV7,
  voidDebtOriginV7,
  voidDebtWriteOffV7,
} from './financeV7Engine';
import { SYSTEM_CONTROL_ACCOUNT_IDS } from './sharedFoundation';
import { SharedStateBridge } from '../services/sharedStateBridge';

function makeAssetAccount(
  id: string,
  name: string,
  openingBalanceCents: number,
  opts: Partial<Account> = {}
): Account {
  return {
    id,
    name,
    type: 'asset',
    subType: opts.subType || 'bank',
    currencyCode: opts.currencyCode || 'ETB',
    openingBalanceCents,
    openingBalanceDate: '2026-11-01',
    isArchived: false,
    createdAt: '2026-11-01T00:00:00Z',
    ...opts,
  };
}

describe('Finance v7 Web Engine & Cross-Platform Parity', () => {
  it('computes AvailableToSpend(H) with Option 1 PrepaidCardCredit, Non-ETB exclusion, and Horizon H filtering', () => {
    const accounts: Account[] = ensureSystemControlAccounts([
      makeAssetAccount('acc-cbe', 'CBE', 87_000), // 870 ETB opening + 130 ETB borrowed = 1,000 ETB liquid
      makeAssetAccount('acc-vault', 'Emergency Vault', 50_000, { subType: 'savings_vault' }), // 500 ETB vault
      makeAssetAccount('acc-usd', 'USD Travel', 20_000, { currencyCode: 'USD' }), // excluded non-ETB
      {
        id: 'acc-card',
        name: 'Prepaid / Credit Card',
        type: 'liability',
        subType: 'credit_card',
        currencyCode: 'ETB',
        openingBalanceCents: -15_000, // negative liability = 150 ETB Prepaid Credit (Option 1)
        isArchived: false,
        createdAt: '2026-11-01T00:00:00Z',
      },
    ]);

    const commitments: SharedCommitment[] = [
      {
        id: 'com-due',
        title: 'Internet Bill',
        amountCents: 20_000,
        dueDate: '2026-11-15',
        isPaid: false,
        direction: 'outflow',
        linkedAccountId: 'acc-cbe',
      },
      {
        id: 'com-future',
        title: 'Next Month Insurance',
        amountCents: 30_000,
        dueDate: '2026-12-10',
        isPaid: false,
        direction: 'outflow',
        linkedAccountId: 'acc-cbe',
      },
      {
        id: 'com-inflow',
        title: 'Client Invoice',
        amountCents: 50_000,
        dueDate: '2026-11-18',
        isPaid: false,
        direction: 'inflow', // Pending inflow MUST contribute 0 until settled
        linkedAccountId: 'acc-cbe',
      },
      {
        id: 'com-legacy',
        title: 'Legacy Paid Bill',
        amountCents: 25_000,
        dueDate: '2026-11-10',
        isPaid: true,
        legacyPaidUnverified: true,
      },
    ];

    const savingsGoals: SharedSavingsGoal[] = [
      {
        id: 'sav-virt',
        title: 'Laptop Virtual',
        targetCents: 100_000,
        currentAllocatedCents: 10_000,
        status: 'active',
      },
    ];

    const d1Built = buildBorrowMoney({
      entryId: 'entry-d1',
      debtId: 'debt-pay-due',
      partyId: 'party-1',
      destAssetAccountId: 'acc-cbe',
      payableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.payable,
      amountCents: 5_000,
      date: '2026-11-01',
      dueDate: '2026-11-20',
      description: 'Due loan into CBE',
    });
    const d2Built = buildBorrowMoney({
      entryId: 'entry-d2',
      debtId: 'debt-pay-later',
      partyId: 'party-1',
      destAssetAccountId: 'acc-cbe',
      payableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.payable,
      amountCents: 8_000,
      date: '2026-11-01',
      dueDate: '2026-12-20',
      description: 'Later loan into CBE',
    });
    const unsettledThirdParty = buildThirdPartyPaidExpense({
      entryId: 'entry-d3-ambig',
      debtId: 'debt-pay-ambig',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      payableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.payable,
      categoryId: 'cat-other-exp',
      partyId: 'party-1',
      amountCents: 9_000,
      occurrenceDate: '2026-11-01',
      dueDate: '2026-11-12',
      description: 'Legacy unsettled third-party expense',
    });
    const debts: Debt[] = [d1Built.debt, d2Built.debt, unsettledThirdParty.debt];
    const originEntries: JournalEntry[] = [d1Built.entry, d2Built.entry, unsettledThirdParty.entry];
    const originPostings: Posting[] = [
      ...d1Built.postings,
      ...d2Built.postings,
      ...unsettledThirdParty.postings,
    ];

    const hNov = calculateAvailableToSpendBreakdownV7({
      accounts,
      postings: originPostings,
      entries: originEntries,
      debts,
      commitments,
      commitmentSettlements: [],
      savingsGoals,
      planningPeriodEndIso: '2026-11-30',
    });

    // liquid 100,000 + prepaid 15,000 - cardOwed 0 - duePayable 5,000 (unsettled third-party excluded) - dueCommitment 20,000 - virtualSavings 10,000 = 80,000
    assert.equal(hNov.liquidCashCents, 100_000);
    assert.equal(hNov.prepaidCardCreditCents, 15_000);
    assert.equal(hNov.vaultSavingsCents, 50_000);
    assert.equal(hNov.duePayablesCents, 5_000);
    assert.equal(hNov.dueNonDebtCommitmentsCents, 20_000);
    assert.equal(hNov.virtualSavingsReservedCents, 10_000);
    assert.equal(hNov.availableToSpendCents, 80_000);
    assert.equal(hNov.nonEtbAccountCount, 1);
    assert.equal(hNov.unverifiedLegacyPaidCount, 1);
    // Net Financial Position = (liquid 100,000 + vault 50,000) - liability (-15,000) - active ETB payables (13,000) = 152,000 (USD & ambiguous excluded)
    assert.equal(hNov.netFinancialPositionCents, 152_000);
    assert.equal(hNov.isShortfall, false);

    // Horizon H extended to 2026-12-31 includes December commitment (30,000) & December payable (8,000)
    const hDec = calculateAvailableToSpendBreakdownV7({
      accounts,
      postings: originPostings,
      entries: originEntries,
      debts,
      commitments,
      commitmentSettlements: [],
      savingsGoals,
      planningPeriodEndIso: '2026-12-31',
    });
    assert.equal(hDec.availableToSpendCents, 42_000);
  });

  it('tracks opening balance :rev:{n} provenance cleanly without double counting', () => {
    const acc = makeAssetAccount('acc-cbe', 'CBE', 0);
    const r0 = reviseAccountOpeningBalanceV7({
      account: acc,
      newOpeningBalanceCents: 100_000,
      newOpeningDateIso: '2026-11-01',
      entries: [],
      postings: [],
    });
    assert.equal(r0.revisionEntry?.legacySourceTxId, 'open:acc-cbe');
    assert.equal(calculateV7AccountBalance(r0.updatedAccount, r0.updatedPostings, r0.updatedEntries), 100_000);

    const r1 = reviseAccountOpeningBalanceV7({
      account: r0.updatedAccount,
      newOpeningBalanceCents: 150_000,
      newOpeningDateIso: '2026-11-02',
      entries: r0.updatedEntries,
      postings: r0.updatedPostings,
    });
    assert.equal(r1.revisionEntry?.legacySourceTxId, 'open:acc-cbe:rev:1');
    assert.equal(r1.revisionEntry?.correctedFromEntryId, r0.revisionEntry?.id);
    assert.equal(calculateV7AccountBalance(r1.updatedAccount, r1.updatedPostings, r1.updatedEntries), 150_000);

    const history = getOpeningBalanceRevisionHistory('acc-cbe', r1.updatedEntries, r1.updatedPostings);
    assert.equal(history.length, 2);
    assert.equal(history.filter((h) => !h.isVoided).length, 1);
  });

  it('supports partial commitment settlements (outflow & inflow) and settlement void reversal', () => {
    let entries: JournalEntry[] = [];
    let postings: Posting[] = [];
    let settlements: SharedCommitmentSettlement[] = [];

    let outflow: SharedCommitment = {
      id: 'com-rent',
      title: 'Rent',
      amountCents: 100_000,
      dueDate: '2026-11-15',
      isPaid: false,
      direction: 'outflow',
    };

    const s1 = recordCommitmentSettlementV7({
      commitment: outflow,
      accountId: 'acc-cbe',
      amountCents: 40_000,
      settledDateIso: '2026-11-10',
      existingSettlements: settlements,
      entries,
    });
    outflow = s1.updatedCommitment;
    settlements = [s1.settlement, ...settlements];
    entries = [s1.entry, ...entries];
    postings = [...s1.postings, ...postings];

    assert.equal(outflow.isPaid, false);
    assert.equal(calculateCommitmentSettledCents(outflow.id, settlements, entries), 40_000);
    assert.equal(getCommitmentRemainingCents(outflow, settlements, entries), 60_000);

    const voidRes = voidCommitmentSettlementV7({
      settlementId: s1.settlement.id,
      reason: 'Wrong amount',
      commitment: outflow,
      settlements,
      entries,
    });
    assert.equal(voidRes.updatedCommitment.isPaid, false);
    assert.equal(
      calculateCommitmentSettledCents(outflow.id, settlements, voidRes.updatedEntries),
      0
    );

    // Test inflow commitment settlement posts Direct Income
    const inflow: SharedCommitment = {
      id: 'com-inc',
      title: 'Retainer',
      amountCents: 50_000,
      dueDate: '2026-11-20',
      isPaid: false,
      direction: 'inflow',
    };
    const incRes = recordCommitmentSettlementV7({
      commitment: inflow,
      accountId: 'acc-cbe',
      amountCents: 50_000,
      settledDateIso: '2026-11-15',
      existingSettlements: [],
      entries: [],
    });
    assert.equal(incRes.updatedCommitment.isPaid, true);
    assert.equal(incRes.simpleTransaction.type, 'income');
  });

  it('enforces debt origin voiding guards, write-off + void-restore, and Tier A control balance parity', () => {
    const accounts = ensureSystemControlAccounts([makeAssetAccount('acc-cbe', 'CBE', 200_000)]);
    const split = buildSplitExpense({
      entryId: 'entry-split-1',
      debtId: 'debt-split-1',
      paidAssetAccountId: 'acc-cbe',
      myExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      receivableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      categoryId: 'cat-food',
      partyId: 'party-selam',
      myShareCents: 60_000,
      theirShareCents: 40_000,
      occurrenceDate: '2026-11-10',
      description: 'Dinner split',
    });

    const entries: JournalEntry[] = [split.entry];
    const postings: Posting[] = [...split.postings];
    let debt: Debt = split.debt;
    const allocations: SettlementAllocation[] = [];

    // Partial settle 10,000 -> outstanding 30,000
    const dset = buildDebtSettlement({
      settlementEntryId: 'entry-dset-1',
      debt,
      settlementAccountId: 'acc-cbe',
      debtAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      interestAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.income,
      feeAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      allocatedPrincipalCents: 10_000,
      interestCents: 500,
      settlementDate: '2026-11-12',
      description: 'Partial settlement',
    });
    entries.push(dset.entry);
    postings.push(...dset.postings);
    allocations.push(dset.allocation);
    debt = { ...debt, outstandingCents: 30_000 };

    // Origin void MUST throw while active settlement exists
    assert.throws(() =>
      voidDebtOriginV7({ debt, reason: 'Try void', allocations, entries })
    );

    // Tier A check before write-off
    const auditBeforeWo = verifyFinanceV7Integrity({
      accounts,
      entries,
      postings,
      debts: [debt],
      commitments: [],
    });
    assert.equal(auditBeforeWo.isHealthy, true);
    assert.equal(auditBeforeWo.debtControlAudit.isTierABalanced, true);

    // Write-off remaining 30,000
    const wo = buildDebtWriteOff({
      writeOffEntryId: 'entry-wo-1',
      debt,
      debtAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      writeOffAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      writeOffCents: 30_000,
      date: '2026-11-14',
      reason: 'Forgiven',
    });
    entries.push(wo.entry);
    postings.push(...wo.postings);
    debt = { ...debt, status: 'written_off', outstandingCents: 0, writeOffEntryId: wo.entry.id };

    const auditAfterWo = verifyFinanceV7Integrity({
      accounts,
      entries,
      postings,
      debts: [debt],
      commitments: [],
    });
    assert.equal(auditAfterWo.debtControlAudit.isTierABalanced, true);

    // Void write-off restores 30,000 outstanding balance
    const restored = voidDebtWriteOffV7({
      debt,
      reason: 'Recovered',
      allocations,
      entries,
    });
    assert.equal(restored.updatedDebt.status, 'active');
    assert.equal(restored.updatedDebt.outstandingCents, 30_000);
    assert.equal(restored.updatedDebt.writeOffEntryId, undefined);
  });

  it('handles savings goals overfunding retention, recurring skip/due processing, and SimpleTransaction hydration', () => {
    const goal: SharedSavingsGoal = {
      id: 'sav-1',
      title: 'Phone',
      targetCents: 50_000,
      currentAllocatedCents: 40_000,
      status: 'active',
    };
    const overfunded = fundSavingsGoalV7({
      goal,
      amountCents: 20_000,
      dateIso: '2026-11-15',
    });
    assert.equal(overfunded.updatedGoal.status, 'completed');
    assert.equal(overfunded.updatedGoal.currentAllocatedCents, 60_000);

    const rules: SharedRecurringRule[] = [
      {
        id: 'rec-manual',
        title: 'Manual Rent',
        ruleType: 'commitment',
        amountCents: 100_000,
        frequency: 'monthly',
        interval: 1,
        startDate: '2026-10-01',
        nextOccurrenceDate: '2026-11-01',
        autoPost: false,
        isActive: true,
        createdAt: '2026-10-01T00:00:00Z',
      },
      {
        id: 'rec-auto',
        title: 'Gym',
        ruleType: 'expense',
        amountCents: 15_000,
        accountId: 'acc-cbe',
        categoryId: 'cat-other-exp',
        frequency: 'monthly',
        interval: 1,
        startDate: '2026-10-05',
        nextOccurrenceDate: '2026-11-05',
        autoPost: true,
        isActive: true,
        createdAt: '2026-10-01T00:00:00Z',
      },
    ];

    const skipped = skipNextRecurringOccurrenceV7(rules[0]);
    assert.equal(skipped.nextOccurrenceDate, '2026-12-01');

    const processed = processDueRecurringRulesV7({
      rules: [skipped, rules[1]],
      todayIso: '2026-11-15',
    });
    assert.equal(processed.createdCommitments.length, 0);
    assert.equal(processed.createdEntries.length, 1);
    assert.equal(processed.updatedRules[1].nextOccurrenceDate, '2026-12-05');

    // Legacy SimpleTransaction hydration
    const hydrated = hydrateLedgerFromSimpleTransactions({
      accounts: [makeAssetAccount('acc-cbe', 'CBE', 100_000)],
      transactions: [
        {
          id: 'tx-legacy-1',
          type: 'expense',
          amountCents: 25_000,
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          description: 'Coffee',
          transactionDate: '2026-11-15',
          createdAt: '2026-11-15T10:00:00Z',
          updatedAt: '2026-11-15T10:00:00Z',
        },
      ],
      entries: [],
      postings: [],
    });
    const cbe = hydrated.accounts.find((a) => a.id === 'acc-cbe')!;
    assert.equal(calculateV7AccountBalance(cbe, hydrated.postings, hydrated.entries), 75_000);
  });

  it('preserves v7 finance tables across SharedStateBridge JSON export and import while retaining schemaVersion 5', () => {
    const store = new Map<string, string>();
    const prevWindow = (globalThis as any).window;
    const prevLocalStorage = (globalThis as any).localStorage;
    const mockStorage = {
      getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
      setItem: (k: string, v: string) => void store.set(k, String(v)),
      removeItem: (k: string) => void store.delete(k),
    };
    (globalThis as any).localStorage = mockStorage;
    (globalThis as any).window = {
      dispatchEvent: () => true,
      CustomEvent: class CustomEvent {
        type: string;
        constructor(type: string) {
          this.type = type;
        }
      },
    };

    try {
      store.set(
        'daywell_commitments',
        JSON.stringify([
          {
            id: 'com-x',
            title: 'Consulting Inflow',
            amountCents: 75_000,
            dueDate: '2026-11-25',
            isPaid: false,
            direction: 'inflow',
          },
        ])
      );
      store.set(
        'daywell_parties',
        JSON.stringify([{ id: 'party-1', name: 'Abebe', createdAt: '2026-11-01T00:00:00Z' }])
      );

      const exportedJson = SharedStateBridge.exportToAndroidJson();
      const parsed = JSON.parse(exportedJson);
      assert.equal(parsed.schemaVersion, 5);
      assert.equal(parsed.financeSchemaVersion, 7);
      assert.equal(parsed.commitments.length, 1);
      assert.equal(parsed.parties.length, 1);

      store.clear();
      const imported = SharedStateBridge.importFromAndroidJson(exportedJson);
      assert.equal(imported.success, true);
      assert.equal(JSON.parse(store.get('daywell_commitments')!)[0].direction, 'inflow');
      assert.equal(JSON.parse(store.get('daywell_parties')!)[0].name, 'Abebe');
    } finally {
      (globalThis as any).window = prevWindow;
      (globalThis as any).localStorage = prevLocalStorage;
    }
  });
});
