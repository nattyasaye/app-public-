import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  Account,
  assertCanArchiveAccountV7,
  assertCanArchiveSavingsGoalV7,
  buildBorrowMoney,
  buildDebtSettlement,
  buildDebtWriteOff,
  buildDirectExpense,
  buildDirectIncome,
  buildLendMoney,
  buildSplitExpense,
  buildThirdPartyPaidExpense,
  buildTransfer,
  calculateAvailableToSpendBreakdownV7,
  calculateCommitmentSettledCents,
  calculateV7AccountBalance,
  canCorrectJournalEntryV7,
  correctJournalEntryV7,
  Debt,
  ensureSystemControlAccounts,
  fundSavingsGoalV7,
  getCommitmentRemainingCents,
  getExpenseRefundSummaryV7,
  getOpeningBalanceRevisionHistory,
  hydrateLedgerFromSimpleTransactions,
  JournalEntry,
  Party,
  Posting,
  processDueRecurringRulesV7,
  reconcileDebtsV7,
  recordCommitmentSettlementV7,
  recordExpenseRefundV7,
  reviseAccountOpeningBalanceV7,
  SettlementAllocation,
  SharedCommitment,
  SharedCommitmentSettlement,
  SharedRecurringRule,
  SharedSavingsGoal,
  skipNextRecurringOccurrenceV7,
  syncVaultSavingsGoalsV7,
  unvoidJournalEntryGuardedV7,
  verifyFinanceV7Integrity,
  voidCommitmentSettlementV7,
  voidDebtOriginV7,
  voidDebtWriteOffV7,
  voidJournalEntryGuardedV7,
} from './financeV7Engine';
import { DoubleEntryValidationError } from './doubleEntryFinance';
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

  it('Stage B (F1): enforces debt-origin/settlement void guards, unvoid checks, and debt reconciliation', () => {
    const accounts = ensureSystemControlAccounts([
      makeAssetAccount('acc-cbe', 'CBE', 500_000),
    ]);
    const lend = buildLendMoney({
      entryId: 'entry-lend-1',
      debtId: 'debt-rec-1',
      partyId: 'party-1',
      sourceAssetAccountId: 'acc-cbe',
      receivableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      amountCents: 100_000,
      date: '2026-11-05',
      description: 'Loan to friend',
    });
    const partialSettle = buildDebtSettlement({
      settlementEntryId: 'entry-settle-1',
      debt: lend.debt,
      settlementAccountId: 'acc-cbe',
      debtAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      allocatedPrincipalCents: 40_000,
      settlementDate: '2026-11-06',
      description: 'Partial repayment',
    });
    let entries: JournalEntry[] = [lend.entry, partialSettle.entry];
    let postings: Posting[] = [...lend.postings, ...partialSettle.postings];
    let debts: Debt[] = [partialSettle.updatedDebt];
    let allocations: SettlementAllocation[] = [partialSettle.allocation];

    // 1) Cannot void debt origin while active settlement exists
    assert.throws(
      () =>
        voidJournalEntryGuardedV7({
          entryId: 'entry-lend-1',
          reason: 'Mistake',
          accounts,
          entries,
          postings,
          debts,
          allocations,
          commitments: [],
          commitmentSettlements: [],
          savingsGoals: [],
          simpleTransactions: [],
        }),
      DoubleEntryValidationError
    );

    // 2) Void settlement first -> debt reconciles back to 100,000 active
    const afterSettleVoid = voidJournalEntryGuardedV7({
      entryId: 'entry-settle-1',
      reason: 'Bounced transfer',
      accounts,
      entries,
      postings,
      debts,
      allocations,
      commitments: [],
      commitmentSettlements: [],
      savingsGoals: [],
      simpleTransactions: [],
    });
    entries = afterSettleVoid.updatedEntries;
    debts = afterSettleVoid.updatedDebts;
    assert.equal(debts[0].outstandingCents, 100_000);
    assert.equal(debts[0].status, 'active');

    // 3) Now debt origin can be voided -> debt becomes voided (0 outstanding)
    const afterOriginVoid = voidJournalEntryGuardedV7({
      entryId: 'entry-lend-1',
      reason: 'Cancelled loan',
      accounts,
      entries,
      postings,
      debts,
      allocations,
      commitments: [],
      commitmentSettlements: [],
      savingsGoals: [],
      simpleTransactions: [],
    });
    entries = afterOriginVoid.updatedEntries;
    debts = afterOriginVoid.updatedDebts;
    assert.equal(debts[0].status, 'voided');
    assert.equal(debts[0].outstandingCents, 0);

    // 4) Cannot unvoid settlement while debt origin is voided
    assert.throws(
      () =>
        unvoidJournalEntryGuardedV7({
          entryId: 'entry-settle-1',
          accounts,
          entries,
          postings,
          debts,
          allocations,
          commitments: [],
          commitmentSettlements: [],
          savingsGoals: [],
          simpleTransactions: [],
        }),
      DoubleEntryValidationError
    );

    // 5) Unvoid origin then write off -> settlement cannot be voided/unvoided while write-off active
    const afterOriginUnvoid = unvoidJournalEntryGuardedV7({
      entryId: 'entry-lend-1',
      accounts,
      entries,
      postings,
      debts,
      allocations,
      commitments: [],
      commitmentSettlements: [],
      savingsGoals: [],
      simpleTransactions: [],
    });
    entries = afterOriginUnvoid.updatedEntries;
    debts = afterOriginUnvoid.updatedDebts;
    assert.equal(debts[0].status, 'active');
    assert.equal(debts[0].outstandingCents, 100_000);

    const wo = buildDebtWriteOff({
      writeOffEntryId: 'entry-wo-1',
      debt: debts[0],
      debtAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      writeOffAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      writeOffCents: debts[0].outstandingCents,
      date: '2026-11-10',
      reason: 'Uncollectible',
    });
    entries = [...entries, wo.entry];
    postings = [...postings, ...wo.postings];
    debts = [wo.updatedDebt];
    assert.equal(debts[0].status, 'written_off');

    assert.throws(
      () =>
        unvoidJournalEntryGuardedV7({
          entryId: 'entry-settle-1',
          accounts,
          entries,
          postings,
          debts,
          allocations,
          commitments: [],
          commitmentSettlements: [],
          savingsGoals: [],
          simpleTransactions: [],
        }),
      DoubleEntryValidationError
    );
    assert.throws(
      () =>
        voidJournalEntryGuardedV7({
          entryId: 'entry-lend-1',
          reason: 'Try void under writeoff',
          accounts,
          entries,
          postings,
          debts,
          allocations,
          commitments: [],
          commitmentSettlements: [],
          savingsGoals: [],
          simpleTransactions: [],
        }),
      DoubleEntryValidationError
    );

    // Void write-off via voidDebtWriteOffV7 + reconcileDebtsV7 restores active debt
    const voidedWo = voidDebtWriteOffV7({
      debt: debts[0],
      entries,
      allocations,
      reason: 'Recovery resumed',
    });
    const reconciledAfterWoVoid = reconcileDebtsV7({
      debts: [voidedWo.updatedDebt],
      entries: voidedWo.updatedEntries,
      allocations,
    });
    assert.equal(reconciledAfterWoVoid[0].status, 'active');
    assert.equal(reconciledAfterWoVoid[0].outstandingCents, 100_000);
    assert.equal(reconciledAfterWoVoid[0].writeOffEntryId, undefined);
  });

  it('Stage B (F1): blocks unsafe edits/corrections and preserves payee, movementDate, feeCategoryId, and dual-write consistency', () => {
    const accounts = ensureSystemControlAccounts([
      makeAssetAccount('acc-cbe', 'CBE', 500_000),
      makeAssetAccount('acc-cash', 'Wallet', 50_000, { subType: 'cash' }),
    ]);
    const split = buildSplitExpense({
      entryId: 'entry-split-1',
      debtId: 'debt-split-1',
      partyId: 'party-1',
      myExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      receivableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      paidAssetAccountId: 'acc-cbe',
      myShareCents: 15_000,
      theirShareCents: 15_000,
      occurrenceDate: '2026-11-05',
      description: 'Team lunch',
      categoryId: 'cat-food',
    });
    const xfer = buildTransfer({
      id: 'entry-xfer-1',
      fromAssetAccountId: 'acc-cbe',
      toAssetAccountId: 'acc-cash',
      amountCents: 20_000,
      transferFeeCents: 500,
      feeExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      feeCategoryId: 'cat-sys-fees',
      date: '2026-11-05',
      movementDate: '2026-11-06',
      description: 'ATM cash pull',
    });
    const stdExp = buildDirectExpense({
      id: 'entry-exp-1',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-food',
      amountCents: 12_000,
      occurrenceDate: '2026-11-04',
      movementDate: '2026-11-05',
      description: 'Tomoca — Coffee',
      note: 'Morning brew',
    });
    const openRev = reviseAccountOpeningBalanceV7({
      account: accounts.find((a) => a.id === 'acc-cbe')!,
      newOpeningBalanceCents: 520_000,
      newOpeningDateIso: '2026-11-01',
      entries: [],
      postings: [],
    });

    const cmSettlement = recordCommitmentSettlementV7({
      commitment: {
        id: 'com-1',
        title: 'Internet',
        amountCents: 10_000,
        dueDate: '2026-11-10',
        isPaid: false,
        direction: 'outflow',
      },
      accountId: 'acc-cbe',
      amountCents: 6_000,
      settledDateIso: '2026-11-08',
      existingSettlements: [],
      entries: [],
    });

    const allEntries: JournalEntry[] = [
      split.entry,
      xfer.entry,
      stdExp.entry,
      openRev.revisionEntry!,
      cmSettlement.entry,
    ];
    const allPostings: Posting[] = [
      ...split.postings,
      ...xfer.postings,
      ...stdExp.postings,
      ...openRev.updatedPostings,
      ...cmSettlement.postings,
    ];
    const debts: Debt[] = [split.debt];

    // Blocked entry types
    assert.equal(
      canCorrectJournalEntryV7({
        entry: split.entry,
        entries: allEntries,
        postings: allPostings,
        accounts,
        debts,
        allocations: [],
      }).ok,
      false
    );
    assert.equal(
      canCorrectJournalEntryV7({
        entry: openRev.revisionEntry!,
        entries: allEntries,
        postings: allPostings,
        accounts,
        debts,
        allocations: [],
      }).ok,
      false
    );
    assert.equal(
      canCorrectJournalEntryV7({
        entry: cmSettlement.entry,
        entries: allEntries,
        postings: allPostings,
        accounts,
        debts,
        allocations: [],
        commitmentSettlements: [cmSettlement.settlement],
      }).ok,
      false
    );

    // Commitment over-settlement unvoid guard (Guard 7)
    const voidedCm = voidCommitmentSettlementV7({
      settlementId: cmSettlement.settlement.id,
      reason: 'Retry payment',
      commitment: cmSettlement.updatedCommitment,
      settlements: [cmSettlement.settlement],
      entries: allEntries,
    });
    const fullCm = recordCommitmentSettlementV7({
      commitment: voidedCm.updatedCommitment,
      accountId: 'acc-cbe',
      amountCents: 10_000,
      settledDateIso: '2026-11-09',
      existingSettlements: [cmSettlement.settlement],
      entries: voidedCm.updatedEntries,
    });
    assert.throws(
      () =>
        unvoidJournalEntryGuardedV7({
          entryId: cmSettlement.entry.id,
          accounts,
          entries: [...voidedCm.updatedEntries, fullCm.entry],
          postings: [...allPostings, ...fullCm.postings],
          debts,
          allocations: [],
          commitments: [fullCm.updatedCommitment],
          commitmentSettlements: [cmSettlement.settlement, fullCm.settlement],
          savingsGoals: [],
          simpleTransactions: [],
        }),
      DoubleEntryValidationError
    );

    // Supported transfer correction preserves feeCategoryId & movementDate
    assert.equal(
      canCorrectJournalEntryV7({
        entry: xfer.entry,
        entries: allEntries,
        postings: allPostings,
        accounts,
        debts,
        allocations: [],
      }).ok,
      true
    );
    const xferRepl = buildTransfer({
      id: 'entry-xfer-2',
      fromAssetAccountId: 'acc-cbe',
      toAssetAccountId: 'acc-cash',
      amountCents: 25_000,
      transferFeeCents: 500,
      feeExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      feeCategoryId: 'cat-sys-fees',
      date: '2026-11-05',
      movementDate: '2026-11-06',
      description: 'ATM cash pull',
    });
    const corrRes = correctJournalEntryV7({
      originalEntryId: xfer.entry.id,
      replacementEntry: xferRepl.entry,
      replacementPostings: xferRepl.postings,
      correctionReason: 'Updated amount',
      accounts,
      entries: allEntries,
      postings: allPostings,
      debts,
      allocations: [],
      commitments: [],
      commitmentSettlements: [],
      savingsGoals: [],
      simpleTransactions: [
        {
          id: 'tx-xfer-1',
          type: 'transfer',
          amountCents: 20_000,
          accountId: 'acc-cbe',
          destinationAccountId: 'acc-cash',
          description: 'ATM cash pull',
          transactionDate: '2026-11-05',
          createdAt: '2026-11-05T08:00:00Z',
          updatedAt: '2026-11-05T08:00:00Z',
          journalEntryId: xfer.entry.id,
        },
      ],
      replacementSimpleTx: {
        id: 'tx-xfer-2',
        type: 'transfer',
        amountCents: 25_000,
        accountId: 'acc-cbe',
        destinationAccountId: 'acc-cash',
        description: 'ATM cash pull',
        transactionDate: '2026-11-05',
        createdAt: '2026-11-05T08:05:00Z',
        updatedAt: '2026-11-05T08:05:00Z',
        journalEntryId: 'entry-xfer-2',
      },
    });
    const feePost = corrRes.updatedPostings.find(
      (p) => p.entryId === 'entry-xfer-2' && p.accountId === SYSTEM_CONTROL_ACCOUNT_IDS.expense
    );
    const dstPost = corrRes.updatedPostings.find(
      (p) => p.entryId === 'entry-xfer-2' && p.accountId === 'acc-cash'
    );
    assert.equal(feePost?.categoryId, 'cat-sys-fees');
    assert.equal(dstPost?.accountMovementDate, '2026-11-06');
    assert.equal(
      corrRes.updatedSimpleTransactions.find((t) => t.id === 'tx-xfer-1')?.isSuperseded,
      true
    );
    assert.equal(
      corrRes.updatedSimpleTransactions.find((t) => t.id === 'tx-xfer-2')?.isSuperseded,
      undefined
    );

    // Dual-write void & unvoid synchronization on direct expense
    const voidExp = voidJournalEntryGuardedV7({
      entryId: stdExp.entry.id,
      reason: 'Duplicate',
      accounts,
      entries: corrRes.updatedEntries,
      postings: corrRes.updatedPostings,
      debts,
      allocations: [],
      commitments: [],
      commitmentSettlements: [],
      savingsGoals: [],
      simpleTransactions: [
        {
          id: 'tx-exp-1',
          type: 'expense',
          amountCents: 12_000,
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          payee: 'Tomoca',
          description: 'Coffee',
          transactionDate: '2026-11-04',
          createdAt: '2026-11-04T08:00:00Z',
          updatedAt: '2026-11-04T08:00:00Z',
          journalEntryId: stdExp.entry.id,
        },
      ],
    });
    assert.equal(voidExp.updatedSimpleTransactions[0].isSuperseded, true);
    const unvoidExp = unvoidJournalEntryGuardedV7({
      entryId: stdExp.entry.id,
      accounts,
      entries: voidExp.updatedEntries,
      postings: corrRes.updatedPostings,
      debts,
      allocations: [],
      commitments: [],
      commitmentSettlements: [],
      savingsGoals: [],
      simpleTransactions: voidExp.updatedSimpleTransactions,
    });
    assert.equal(unvoidExp.updatedSimpleTransactions[0].isSuperseded, false);
  });

  it('Stage B (F1): synchronizes vault SavingsGoals, blocks nonzero archival, and validates expense refunds', () => {
    const accounts = ensureSystemControlAccounts([
      makeAssetAccount('acc-cbe', 'CBE', 300_000),
      makeAssetAccount('acc-vault', 'Emergency Vault', 25_000, { subType: 'savings_vault' }),
      {
        id: 'acc-card',
        name: 'Abyssinia Card',
        type: 'liability',
        subType: 'credit_card',
        currencyCode: 'ETB',
        openingBalanceCents: 40_000,
        isArchived: false,
        createdAt: '2026-11-01T00:00:00Z',
      },
    ]);
    let vaultGoal: SharedSavingsGoal = {
      id: 'goal-vault',
      title: 'Emergency Vault',
      targetCents: 100_000,
      currentAllocatedCents: 0,
      linkedAccountId: 'acc-vault',
      status: 'active',
    };

    // 1) Opening-balance sync + fund deposit + void/unvoid + withdrawal + archive block
    let syncedGoals = syncVaultSavingsGoalsV7({
      accounts,
      entries: [],
      postings: [],
      savingsGoals: [vaultGoal],
    });
    vaultGoal = syncedGoals[0];
    assert.equal(vaultGoal.currentAllocatedCents, 25_000);

    const fundRes = fundSavingsGoalV7({
      goal: vaultGoal,
      amountCents: 75_000,
      direction: 'deposit',
      sourceAccountId: 'acc-cbe',
      dateIso: '2026-11-05',
      accounts,
      entries: [],
      postings: [],
    });
    let entries: JournalEntry[] = [fundRes.entry!];
    let postings: Posting[] = [...fundRes.postings!];
    assert.equal(fundRes.updatedGoal.currentAllocatedCents, 100_000);
    assert.equal(fundRes.updatedGoal.status, 'completed');

    // Void deposit -> goal returns to active 25,000
    const voidFund = voidJournalEntryGuardedV7({
      entryId: fundRes.entry!.id,
      reason: 'Undo transfer',
      accounts,
      entries,
      postings,
      debts: [],
      allocations: [],
      commitments: [],
      commitmentSettlements: [],
      savingsGoals: [fundRes.updatedGoal],
      simpleTransactions: [],
    });
    assert.equal(voidFund.updatedSavingsGoals[0].currentAllocatedCents, 25_000);
    assert.equal(voidFund.updatedSavingsGoals[0].status, 'active');

    // Unvoid deposit -> back to completed 100,000
    const unvoidFund = unvoidJournalEntryGuardedV7({
      entryId: fundRes.entry!.id,
      accounts,
      entries: voidFund.updatedEntries,
      postings,
      debts: [],
      allocations: [],
      commitments: [],
      commitmentSettlements: [],
      savingsGoals: voidFund.updatedSavingsGoals,
      simpleTransactions: [],
    });
    entries = unvoidFund.updatedEntries;
    vaultGoal = unvoidFund.updatedSavingsGoals[0];
    assert.equal(vaultGoal.currentAllocatedCents, 100_000);
    assert.equal(vaultGoal.status, 'completed');

    // Block archiving nonzero vault goal & vault account
    assert.throws(
      () =>
        assertCanArchiveSavingsGoalV7({
          goal: vaultGoal,
          accounts,
          entries,
          postings,
        }),
      DoubleEntryValidationError
    );
    assert.throws(
      () =>
        assertCanArchiveAccountV7({
          account: accounts.find((a) => a.id === 'acc-vault')!,
          entries,
          postings,
        }),
      DoubleEntryValidationError
    );

    // Withdraw full 100,000 back to liquid -> now archive succeeds
    const withdrawRes = fundSavingsGoalV7({
      goal: vaultGoal,
      amountCents: 100_000,
      direction: 'withdraw',
      sourceAccountId: 'acc-cbe',
      dateIso: '2026-11-06',
      accounts,
      entries,
      postings,
    });
    entries = [withdrawRes.entry!, ...entries];
    postings = [...withdrawRes.postings!, ...postings];
    vaultGoal = withdrawRes.updatedGoal;
    assert.equal(vaultGoal.currentAllocatedCents, 0);
    assert.equal(vaultGoal.status, 'active');
    assertCanArchiveSavingsGoalV7({ goal: vaultGoal, accounts, entries, postings });
    assertCanArchiveAccountV7({
      account: accounts.find((a) => a.id === 'acc-vault')!,
      entries,
      postings,
    });

    // 2) Expense Refund lifecycle (card destination allowed, vault disallowed, partial+full cap, void block)
    const exp = buildDirectExpense({
      id: 'entry-exp-ref-orig',
      assetAccountId: 'acc-cbe',
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: 'cat-shopping',
      amountCents: 50_000,
      occurrenceDate: '2026-11-05',
      movementDate: '2026-11-05',
      description: 'Electronics',
    });
    entries = [exp.entry, ...entries];
    postings = [...exp.postings, ...postings];

    // Disallow vault as refund destination
    assert.throws(
      () =>
        recordExpenseRefundV7({
          originalEntryId: exp.entry.id,
          refundAccountId: 'acc-vault',
          refundCents: 10_000,
          refundDateIso: '2026-11-06',
          entries,
          postings,
          accounts,
        }),
      DoubleEntryValidationError
    );

    // Allow partial refund to active credit card liability
    const r1 = recordExpenseRefundV7({
      refundEntryId: 'entry-ref-1',
      originalEntryId: exp.entry.id,
      refundAccountId: 'acc-card',
      refundCents: 20_000,
      refundDateIso: '2026-11-06',
      entries,
      postings,
      accounts,
    });
    entries = [r1.entry, ...entries];
    postings = [...r1.postings, ...postings];
    assert.equal(r1.updatedSummary.remainingRefundableCents, 30_000);

    // Card owed decreases from 40,000 to 20,000
    assert.equal(
      calculateV7AccountBalance(
        accounts.find((a) => a.id === 'acc-card')!,
        postings,
        entries
      ),
      20_000
    );

    // Block voiding original expense while active refund exists
    assert.throws(
      () =>
        voidJournalEntryGuardedV7({
          entryId: exp.entry.id,
          reason: 'Try void refunded',
          accounts,
          entries,
          postings,
          debts: [],
          allocations: [],
          commitments: [],
          commitmentSettlements: [],
          savingsGoals: [],
          simpleTransactions: [],
        }),
      DoubleEntryValidationError
    );

    // Block correcting refunded original expense or refund entry itself
    assert.equal(
      canCorrectJournalEntryV7({
        entry: exp.entry,
        entries,
        postings,
        accounts,
        debts: [],
        allocations: [],
      }).ok,
      false
    );
    assert.equal(
      canCorrectJournalEntryV7({
        entry: r1.entry,
        entries,
        postings,
        accounts,
        debts: [],
        allocations: [],
      }).ok,
      false
    );

    // Second refund reaches full cap; over-refund fails
    const r2 = recordExpenseRefundV7({
      refundEntryId: 'entry-ref-2',
      originalEntryId: exp.entry.id,
      refundAccountId: 'acc-cbe',
      refundCents: 30_000,
      refundDateIso: '2026-11-07',
      entries,
      postings,
      accounts,
    });
    entries = [r2.entry, ...entries];
    postings = [...r2.postings, ...postings];
    assert.equal(
      getExpenseRefundSummaryV7({
        originalEntryId: exp.entry.id,
        entries,
        postings,
        accounts,
      }).remainingRefundableCents,
      0
    );

    // Void r1, restore r2 not applicable since r2 is active -> cannot unvoid r1 if r2+r1 > 50k; voiding r2 makes r1 restorable
    const voidR1 = voidJournalEntryGuardedV7({
      entryId: 'entry-ref-1',
      reason: 'Cancel',
      accounts,
      entries,
      postings,
      debts: [],
      allocations: [],
      commitments: [],
      commitmentSettlements: [],
      savingsGoals: [],
      simpleTransactions: [],
    });
    // Now r2 is 30k, so remaining refundable is 20k -> r1 (20k) CAN unvoid cleanly, and another 25k refund fails
    assert.throws(
      () =>
        recordExpenseRefundV7({
          originalEntryId: exp.entry.id,
          refundAccountId: 'acc-cbe',
          refundCents: 25_000,
          refundDateIso: '2026-11-08',
          entries: voidR1.updatedEntries,
          postings,
          accounts,
        }),
      DoubleEntryValidationError
    );
  });

  it('Stage B (F1): SharedStateBridge.importFromAndroidJson reconciles stale debt and vault-goal state', () => {
    const store = new Map<string, string>();
    const prevWindow = (globalThis as any).window;
    const prevLocalStorage = (globalThis as any).localStorage;
    (globalThis as any).localStorage = {
      getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
      setItem: (k: string, v: string) => void store.set(k, String(v)),
      removeItem: (k: string) => void store.delete(k),
    };
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
      const payload = {
        schemaVersion: 5,
        financeSchemaVersion: 7,
        accounts: [
          makeAssetAccount('acc-cbe', 'CBE', 100_000),
          makeAssetAccount('acc-vault', 'Emergency Vault', 80_000, { subType: 'savings_vault' }),
        ],
        categories: [],
        transactions: [],
        parties: [
          {
            id: 'party-1',
            name: 'Friend',
            isArchived: false,
            createdAt: '2026-11-01T00:00:00Z',
          },
        ],
        journalEntries: [
          {
            id: 'entry-lend-stale',
            entryType: 'debt_issuance',
            description: 'Voided lend',
            occurrenceDate: '2026-11-02',
            isVoided: true,
            voidReason: 'Voided',
            createdAt: '2026-11-02T00:00:00Z',
          },
        ],
        postings: [],
        debts: [
          {
            id: 'debt-stale',
            originEntryId: 'entry-lend-stale',
            partyId: 'party-1',
            debtType: 'receivable',
            principalCents: 50_000,
            outstandingCents: 50_000,
            status: 'active',
            createdAt: '2026-11-02T00:00:00Z',
          },
        ],
        savingsGoals: [
          {
            id: 'goal-vault-stale',
            title: 'Emergency Vault',
            targetCents: 80_000,
            currentAllocatedCents: 10_000,
            linkedAccountId: 'acc-vault',
            status: 'active',
          },
        ],
      };

      const res = SharedStateBridge.importFromAndroidJson(JSON.stringify(payload));
      assert.equal(res.success, true, res.error);
      const importedDebts = JSON.parse(store.get('daywell_debts')!);
      const importedGoals = JSON.parse(store.get('daywell_savings_goals')!);
      assert.equal(importedDebts[0].status, 'voided');
      assert.equal(importedDebts[0].outstandingCents, 0);
      assert.equal(importedGoals[0].currentAllocatedCents, 80_000);
      assert.equal(importedGoals[0].status, 'completed');
    } finally {
      (globalThis as any).window = prevWindow;
      (globalThis as any).localStorage = prevLocalStorage;
    }
  });
});
