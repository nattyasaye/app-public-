/**
 * Daywell Finance v7 Engine (Web Parity with Flutter Stage 4.1–4.16 Architecture)
 *
 * Implements:
 * - System control accounts (equity, income, expense, receivable, payable, legacy offset)
 * - Opening balance provenance (:rev:{n}) backed by balanced adjustment journal entries
 * - Safe Harbor Available-to-Spend(H) Breakdown with Option 1 Prepaid Card Credit
 * - ETB-only aggregation & non-ETB account exclusion counters
 * - Commitments (outflow + inflow), partial CommitmentSettlements, settlement voiding,
 *   and legacyPaidUnverified isolation ('Record Cash Payment' / 'Mark Unpaid')
 * - Immutable Debt origin voiding (guarded against active settlements/write-offs)
 *   and write-off + void-restore
 * - Savings Goals (virtual earmark vs vault-linked transfer, overfunded retention + release/archive)
 * - Recurring Rules (autoPost defaults false, pause/resume, skipNextOccurrence, due processing)
 * - Synchronization between SimpleTransaction[] (legacy/Quick Capture) and balanced Postings
 */

import {
  SharedAccountSubType,
  SharedBudget,
  SharedCategory,
  SharedCommitment,
  SharedCommitmentSettlement,
  SharedRecurringRule,
  SharedSavingsGoal,
  SYSTEM_CONTROL_ACCOUNT_IDS,
} from './sharedFoundation';
import { CalendarDate, EthiopiaClock } from './date';
import {
  Account,
  AccountSubType,
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
  calculateAccountBalance,
  calculateTotalPayables,
  calculateTotalReceivables,
  classifyAllJournalEntries,
  classifyCurrencyCode,
  classifyJournalEntryCurrency,
  CurrencyIsolationAudit,
  CurrencyValidationTier,
  Debt,
  DoubleEntryValidationError,
  EntryCurrencyClassification,
  EntryCurrencyStatus,
  formatCurrencyCents,
  generateCashFlowReport,
  generateOccurrenceReport,
  isActiveVerifiedEtbAccount,
  isDebtEligibleEtb,
  isEtbCurrency,
  isValidCurrencyCode,
  JournalEntry,
  normalizeCurrencyCode,
  Party,
  Posting,
  resolveCommitmentCurrencyStatus,
  SettlementAllocation,
  SimpleTransaction,
  TransactionCategory,
  validateBalancedEntry,
} from './doubleEntryFinance';

export interface AvailableToSpendBreakdownV7 {
  planningPeriodEndIso: string;
  liquidCashCents: number;
  prepaidCardCreditCents: number;
  shortTermCreditOwedCents: number;
  duePayablesCents: number;
  dueNonDebtCommitmentsCents: number;
  virtualSavingsReservedCents: number;
  vaultSavingsCents: number;
  receivablesCents: number;
  netFinancialPositionCents: number;
  availableToSpendCents: number;
  nonEtbAccountCount: number;
  unverifiedAccountCount: number;
  unverifiedLegacyPaidCount: number;
  excludedNonEtbEntryCount: number;
  currencyReviewEntryCount: number;
  isShortfall: boolean;
}

export interface DebtControlAuditReportV7 {
  receivableControlBalanceCents: number;
  activeReceivableSumCents: number;
  payableControlBalanceCents: number;
  activePayableSumCents: number;
  receivableDeltaCents: number;
  payableDeltaCents: number;
  isTierABalanced: boolean;
  mismatchDetails: string[];
}

export interface FinanceV7IntegrityReport {
  isHealthy: boolean;
  errors: string[];
  warnings: string[];
  debtControlAudit: DebtControlAuditReportV7;
  unbalancedEntriesCount: number;
  totalEntriesCount: number;
  nonEtbAccountCount: number;
  unverifiedAccountCount: number;
  unverifiedLegacyPaidCount: number;
  excludedNonEtbEntryCount: number;
  currencyReviewEntryCount: number;
  excludedNonEtbDebtCount: number;
  excludedNonEtbCommitmentCount: number;
}

export interface OpeningBalanceRevisionItem {
  entryId: string;
  accountId: string;
  amountCents: number;
  dateIso: string;
  description: string;
  isVoided: boolean;
  correctedFromEntryId?: string;
  provenanceKey?: string;
}

export function ensureSystemControlAccounts(accounts: Account[]): Account[] {
  const existingIds = new Set(accounts.map((a) => a.id));
  const now = EthiopiaClock.nowUtc().toISOString();
  const additions: Account[] = [];

  const defs: Array<{
    id: string;
    name: string;
    type: Account['type'];
    subType: AccountSubType;
  }> = [
    {
      id: SYSTEM_CONTROL_ACCOUNT_IDS.equity,
      name: 'Opening Balance Equity',
      type: 'equity',
      subType: 'opening_equity',
    },
    {
      id: SYSTEM_CONTROL_ACCOUNT_IDS.income,
      name: 'Income Control',
      type: 'income',
      subType: 'nominal_income',
    },
    {
      id: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      name: 'Expense Control',
      type: 'expense',
      subType: 'nominal_expense',
    },
    {
      id: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      name: 'Accounts Receivable',
      type: 'asset',
      subType: 'receivable',
    },
    {
      id: SYSTEM_CONTROL_ACCOUNT_IDS.payable,
      name: 'Accounts Payable',
      type: 'liability',
      subType: 'payable',
    },
    {
      id: SYSTEM_CONTROL_ACCOUNT_IDS.legacyOffset,
      name: 'Legacy Clearing Offset',
      type: 'equity',
      subType: 'legacy_clearing',
    },
  ];

  for (const def of defs) {
    if (!existingIds.has(def.id)) {
      additions.push({
        id: def.id,
        name: def.name,
        type: def.type,
        subType: def.subType,
        isSystem: true,
        currencyCode: 'ETB',
        openingBalanceCents: 0,
        isArchived: false,
        createdAt: now,
      });
    }
  }

  return additions.length > 0 ? [...accounts, ...additions] : accounts;
}

export function isLiquidSubType(account: Account): boolean {
  if (account.isSystem || account.isArchived) return false;
  if (account.type !== 'asset') return false;
  if (account.subType === 'savings_vault' || account.subType === 'receivable') return false;
  if (account.name.toLowerCase().includes('receivable')) return false;
  return true;
}

export function getAccountSubType(account: Account): SharedAccountSubType {
  if (account.subType) return account.subType;
  if (account.type === 'asset') return 'bank';
  if (account.type === 'liability') return 'credit_card';
  if (account.type === 'equity') return 'opening_equity';
  if (account.type === 'income') return 'nominal_income';
  return 'nominal_expense';
}

/**
 * Computes account balance from journal postings when available, OR falls back
 * cleanly to openingBalanceCents + postings so both opening-entry ledgers and
 * legacy openingBalanceCents accounts produce identical results.
 */
export function calculateV7AccountBalance(
  account: Account,
  postings: Posting[],
  entries: JournalEntry[]
): number {
  const voidedIds = new Set(entries.filter((e) => e.isVoided).map((e) => e.id));
  const hasOpeningEntry = entries.some(
    (e) =>
      !e.isVoided &&
      e.legacySourceTxId &&
      (e.legacySourceTxId === `open:${account.id}` ||
        e.legacySourceTxId.startsWith(`open:${account.id}:rev:`))
  );

  // If the opening balance is represented by a ledger adjustment entry, start from 0 to avoid double-counting.
  let balance = hasOpeningEntry ? 0 : account.openingBalanceCents || 0;

  for (const p of postings) {
    if (p.accountId !== account.id) continue;
    if (voidedIds.has(p.entryId)) continue;
    if (account.type === 'asset' || account.type === 'expense') {
      balance += p.direction === 'debit' ? p.amountCents : -p.amountCents;
    } else {
      balance += p.direction === 'credit' ? p.amountCents : -p.amountCents;
    }
  }
  return balance;
}

export function calculateCommitmentSettledCents(
  commitmentId: string,
  settlements: SharedCommitmentSettlement[],
  entries: JournalEntry[]
): number {
  const voidedIds = new Set(entries.filter((e) => e.isVoided).map((e) => e.id));
  return settlements
    .filter((s) => s.commitmentId === commitmentId && !voidedIds.has(s.entryId))
    .reduce((sum, s) => sum + Math.max(0, s.amountCents), 0);
}

export function getCommitmentRemainingCents(
  commitment: SharedCommitment,
  settlements: SharedCommitmentSettlement[],
  entries: JournalEntry[]
): number {
  if (commitment.isPaid) return 0;
  const settled = calculateCommitmentSettledCents(commitment.id, settlements, entries);
  return Math.max(0, commitment.amountCents - settled);
}

/**
 * Authoritative Stage 4.8 / Stage 4.16 Safe Harbor Available-to-Spend(H) Breakdown.
 */
export function calculateAvailableToSpendBreakdownV7(params: {
  accounts: Account[];
  postings: Posting[];
  entries: JournalEntry[];
  debts: Debt[];
  commitments: SharedCommitment[];
  commitmentSettlements: SharedCommitmentSettlement[];
  savingsGoals: SharedSavingsGoal[];
  allocations?: SettlementAllocation[];
  recurringRules?: SharedRecurringRule[];
  planningPeriodEndIso?: string;
}): AvailableToSpendBreakdownV7 {
  const effectiveHorizon =
    params.planningPeriodEndIso && params.planningPeriodEndIso.trim()
      ? params.planningPeriodEndIso
      : CalendarDate.today().endOfGregorianMonth.toIsoString();

  const audit = auditCurrencyIsolation({
    accounts: params.accounts,
    entries: params.entries,
    postings: params.postings,
    debts: params.debts,
    allocations: params.allocations,
    commitments: params.commitments,
    recurringRules: params.recurringRules,
    commitmentSettlements: params.commitmentSettlements,
    savingsGoals: params.savingsGoals,
  });
  const accountById = new Map(params.accounts.map((a) => [a.id, a]));
  const entryById = new Map(params.entries.map((e) => [e.id, e]));
  const debtById = new Map(params.debts.map((d) => [d.id, d]));
  const ruleById = new Map((params.recurringRules || []).map((r) => [r.id, r]));
  const settlementsByCommitmentId = new Map<string, SharedCommitmentSettlement[]>();
  for (const s of params.commitmentSettlements) {
    const list = settlementsByCommitmentId.get(s.commitmentId) || [];
    list.push(s);
    settlementsByCommitmentId.set(s.commitmentId, list);
  }
  const voidedIds = new Set(params.entries.filter((e) => e.isVoided).map((e) => e.id));

  let liquidCashCents = 0;
  let vaultSavingsCents = 0;
  let prepaidCardCreditCents = 0;
  let shortTermCreditOwedCents = 0;
  let totalAssetsEtb = 0;
  let totalLiabilitiesEtb = 0;

  for (const acc of params.accounts) {
    if (acc.isArchived) continue;
    if (!acc.isSystem && !isEtbCurrency(acc.currencyCode)) {
      continue;
    }
    if (acc.subType === 'legacy_clearing') continue;

    let bal: number;
    if (acc.isSystem) {
      bal = acc.openingBalanceCents || 0;
      for (const p of params.postings) {
        if (p.accountId !== acc.id || voidedIds.has(p.entryId)) continue;
        if (!(audit.classificationsByEntryId.get(p.entryId)?.isEligibleEtb ?? false)) {
          continue;
        }
        if (acc.type === 'asset' || acc.type === 'expense') {
          bal += p.direction === 'debit' ? p.amountCents : -p.amountCents;
        } else {
          bal += p.direction === 'credit' ? p.amountCents : -p.amountCents;
        }
      }
    } else {
      bal = calculateV7AccountBalance(acc, params.postings, params.entries);
    }

    if (acc.type === 'asset') {
      totalAssetsEtb += bal;
    } else if (acc.type === 'liability') {
      totalLiabilitiesEtb += bal;
    }

    if (acc.isSystem) continue;

    const sub = getAccountSubType(acc);
    if (acc.type === 'asset') {
      if (sub === 'savings_vault') {
        vaultSavingsCents += bal;
      } else if (sub !== 'receivable' && !acc.name.toLowerCase().includes('receivable')) {
        liquidCashCents += bal;
      }
    } else if (acc.type === 'liability' && sub === 'credit_card') {
      if (bal > 0) {
        shortTermCreditOwedCents += bal;
      } else if (bal < 0) {
        prepaidCardCreditCents += -bal;
      }
    }
  }

  const duePayablesCents = params.debts
    .filter((d) => {
      if (d.debtType !== 'payable' || d.status !== 'active') return false;
      if (d.dueDate && d.dueDate > effectiveHorizon) return false;
      return isDebtEligibleEtb(d, entryById, audit.classificationsByEntryId);
    })
    .reduce((sum, d) => sum + Math.max(0, d.outstandingCents), 0);

  let dueNonDebtCommitmentsCents = 0;
  let unverifiedLegacyPaidCount = 0;
  for (const c of params.commitments) {
    if (c.legacyPaidUnverified) {
      unverifiedLegacyPaidCount += 1;
      continue;
    }
    const direction = c.direction || 'outflow';
    if (direction !== 'outflow') continue;
    if (c.isPaid || c.linkedDebtId) continue;
    if (c.dueDate > effectiveHorizon) continue;
    const cmRes = resolveCommitmentCurrencyStatus({
      commitment: c,
      accountById,
      debtById,
      entryById,
      classificationsByEntryId: audit.classificationsByEntryId,
      ruleById,
      settlementsByCommitmentId,
    });
    if (cmRes.status !== 'eligible_etb') continue;
    dueNonDebtCommitmentsCents += getCommitmentRemainingCents(
      c,
      params.commitmentSettlements,
      params.entries
    );
  }

  const virtualSavingsReservedCents = params.savingsGoals
    .filter((g) => !g.linkedAccountId && g.status !== 'archived')
    .reduce((sum, g) => sum + Math.max(0, g.currentAllocatedCents), 0);

  const receivablesCents = calculateTotalReceivables(params.debts, {
    accounts: params.accounts,
    entries: params.entries,
    postings: params.postings,
    allocations: params.allocations,
  });

  const availableToSpendCents =
    liquidCashCents +
    prepaidCardCreditCents -
    shortTermCreditOwedCents -
    duePayablesCents -
    dueNonDebtCommitmentsCents -
    virtualSavingsReservedCents;

  return {
    planningPeriodEndIso: effectiveHorizon,
    liquidCashCents,
    prepaidCardCreditCents,
    shortTermCreditOwedCents,
    duePayablesCents,
    dueNonDebtCommitmentsCents,
    virtualSavingsReservedCents,
    vaultSavingsCents,
    receivablesCents,
    netFinancialPositionCents: totalAssetsEtb - totalLiabilitiesEtb,
    availableToSpendCents,
    nonEtbAccountCount: audit.nonEtbAccountCount,
    unverifiedAccountCount: audit.unverifiedAccountCount,
    unverifiedLegacyPaidCount,
    excludedNonEtbEntryCount: audit.excludedNonEtbEntryCount,
    currencyReviewEntryCount: audit.currencyReviewEntryCount,
    isShortfall: availableToSpendCents < 0,
  };
}

/**
 * Opening balance provenance (`open:{accountId}:rev:{n}`) backed by balanced
 * adjustment entries against `acc-sys-equity`.
 */
export function reviseAccountOpeningBalanceV7(params: {
  account: Account;
  newOpeningBalanceCents: number;
  newOpeningDateIso?: string;
  entries: JournalEntry[];
  postings: Posting[];
  allowLegacyNonEtb?: boolean;
}): {
  updatedAccount: Account;
  updatedEntries: JournalEntry[];
  updatedPostings: Posting[];
  revisionEntry?: JournalEntry;
} {
  if (!Number.isInteger(params.newOpeningBalanceCents)) {
    throw new DoubleEntryValidationError('Opening balance must be an integer in cents.');
  }
  if (!params.allowLegacyNonEtb) {
    assertVerifiedEtbAccount(params.account, 'Account');
  }
  const effectiveDate =
    params.newOpeningDateIso ||
    params.account.openingBalanceDate ||
    CalendarDate.today().toIsoString();

  const provenancePrefix = `open:${params.account.id}`;
  const matchingEntries = params.entries.filter(
    (e) =>
      e.legacySourceTxId === provenancePrefix ||
      (e.legacySourceTxId?.startsWith(`${provenancePrefix}:rev:`) ?? false)
  );

  const activeMatching = matchingEntries.filter((e) => !e.isVoided);
  const previousActive = activeMatching[activeMatching.length - 1];

  let nextEntries = params.entries.map((e) => {
    if (activeMatching.some((a) => a.id === e.id)) {
      return {
        ...e,
        isVoided: true,
        voidReason: 'Superseded by opening balance revision',
      };
    }
    return e;
  });

  let nextPostings = [...params.postings];
  let revisionEntry: JournalEntry | undefined;

  if (params.newOpeningBalanceCents !== 0) {
    const maxRev = matchingEntries.reduce((max, e) => {
      const m = /:rev:(\d+)$/.exec(e.legacySourceTxId || '');
      return m ? Math.max(max, parseInt(m[1], 10)) : Math.max(max, 0);
    }, 0);
    const revNum = matchingEntries.length === 0 ? 0 : maxRev + 1;
    const provenanceKey = revNum === 0 ? provenancePrefix : `${provenancePrefix}:rev:${revNum}`;
    const entryId = `entry-open-${params.account.id}-r${revNum}-${Date.now()}`;
    const absAmount = Math.abs(params.newOpeningBalanceCents);
    const isDebitNormal =
      params.account.type === 'asset' || params.account.type === 'expense';
    const accountDebit =
      (isDebitNormal && params.newOpeningBalanceCents > 0) ||
      (!isDebitNormal && params.newOpeningBalanceCents < 0);

    revisionEntry = {
      id: entryId,
      entryType: 'adjustment',
      description:
        revNum === 0
          ? `Opening Balance for ${params.account.name}`
          : `Opening Balance Revision #${revNum} for ${params.account.name}`,
      occurrenceDate: effectiveDate,
      isVoided: false,
      legacySourceTxId: provenanceKey,
      correctedFromEntryId: previousActive?.id,
      createdAt: EthiopiaClock.nowUtc().toISOString(),
    };

    const newPostings: Posting[] = [
      {
        id: `${entryId}-acc`,
        entryId,
        accountId: params.account.id,
        amountCents: absAmount,
        direction: accountDebit ? 'debit' : 'credit',
        accountMovementDate: effectiveDate,
        note: `Opening balance (${provenanceKey})`,
      },
      {
        id: `${entryId}-eq`,
        entryId,
        accountId: SYSTEM_CONTROL_ACCOUNT_IDS.equity,
        amountCents: absAmount,
        direction: accountDebit ? 'credit' : 'debit',
        accountMovementDate: effectiveDate,
        note: 'Opening equity offset',
      },
    ];
    validateBalancedEntry(newPostings);
    nextEntries = [revisionEntry, ...nextEntries];
    nextPostings = [...newPostings, ...nextPostings];
  }

  return {
    updatedAccount: {
      ...params.account,
      openingBalanceCents: params.newOpeningBalanceCents,
      openingBalanceDate: effectiveDate,
      updatedAt: EthiopiaClock.nowUtc().toISOString(),
    },
    updatedEntries: nextEntries,
    updatedPostings: nextPostings,
    revisionEntry,
  };
}

export function getOpeningBalanceRevisionHistory(
  accountId: string,
  entries: JournalEntry[],
  postings: Posting[]
): OpeningBalanceRevisionItem[] {
  const prefix = `open:${accountId}`;
  return entries
    .filter(
      (e) =>
        e.legacySourceTxId === prefix ||
        (e.legacySourceTxId?.startsWith(`${prefix}:rev:`) ?? false)
    )
    .map((e) => {
      const accPosting = postings.find((p) => p.entryId === e.id && p.accountId === accountId);
      const signed = accPosting
        ? accPosting.direction === 'debit'
          ? accPosting.amountCents
          : -accPosting.amountCents
        : 0;
      return {
        entryId: e.id,
        accountId,
        amountCents: signed,
        dateIso: e.occurrenceDate,
        description: e.description,
        isVoided: e.isVoided,
        correctedFromEntryId: e.correctedFromEntryId,
        provenanceKey: e.legacySourceTxId,
      };
    });
}

/**
 * Records a full or partial installment settlement against an outflow or inflow commitment.
 */
export function recordCommitmentSettlementV7(params: {
  commitment: SharedCommitment;
  accountId: string;
  amountCents: number;
  settledDateIso: string;
  note?: string;
  existingSettlements: SharedCommitmentSettlement[];
  entries: JournalEntry[];
  accounts?: Account[];
  postings?: Posting[];
  debts?: Debt[];
  allocations?: SettlementAllocation[];
  recurringRules?: SharedRecurringRule[];
}): {
  updatedCommitment: SharedCommitment;
  settlement: SharedCommitmentSettlement;
  entry: JournalEntry;
  postings: Posting[];
  simpleTransaction: SimpleTransaction;
} {
  if (!Number.isInteger(params.amountCents) || params.amountCents <= 0) {
    throw new DoubleEntryValidationError('Settlement amount must be a positive integer.');
  }
  if (params.accounts) {
    assertEtbPostingAccounts({
      accounts: params.accounts,
      accountIds: [params.accountId],
      roleLabels: ['Settlement account'],
    });
    const accountById = new Map(params.accounts.map((a) => [a.id, a]));
    const classificationsByEntryId = classifyAllJournalEntries({
      accounts: params.accounts,
      entries: params.entries,
      postings: params.postings || [],
      debts: params.debts,
      allocations: params.allocations,
    });
    const cmStatus = resolveCommitmentCurrencyStatus({
      commitment: params.commitment,
      accountById,
      debtById: params.debts ? new Map(params.debts.map((d) => [d.id, d])) : undefined,
      entryById: new Map(params.entries.map((e) => [e.id, e])),
      classificationsByEntryId,
      ruleById: params.recurringRules
        ? new Map(params.recurringRules.map((r) => [r.id, r]))
        : undefined,
      settlementsByCommitmentId: new Map([[params.commitment.id, params.existingSettlements]]),
    });
    if (cmStatus.status !== 'eligible_etb') {
      throw new DoubleEntryValidationError(
        'Cannot settle a non-ETB or currency-review commitment in first-release ETB mode.'
      );
    }
  }

  const remaining = getCommitmentRemainingCents(
    params.commitment,
    params.existingSettlements,
    params.entries
  );
  if (params.amountCents > remaining && !params.commitment.legacyPaidUnverified) {
    throw new DoubleEntryValidationError(
      `Settlement amount (${params.amountCents}) exceeds remaining commitment balance (${remaining}).`
    );
  }

  const direction = params.commitment.direction || 'outflow';
  const entryId = `entry-com-${params.commitment.id}-${Date.now()}`;
  const settlementId = `cset-${params.commitment.id}-${Date.now()}`;
  const categoryId =
    params.commitment.categoryId || (direction === 'inflow' ? 'cat-other-inc' : 'cat-other-exp');

  const built =
    direction === 'inflow'
      ? buildDirectIncome({
          id: entryId,
          assetAccountId: params.accountId,
          incomeAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.income,
          categoryId,
          amountCents: params.amountCents,
          occurrenceDate: params.settledDateIso,
          movementDate: params.settledDateIso,
          description: `Income Received: ${params.commitment.title}`,
          note: params.note,
        })
      : buildDirectExpense({
          id: entryId,
          assetAccountId: params.accountId,
          expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
          categoryId,
          amountCents: params.amountCents,
          occurrenceDate: params.settledDateIso,
          movementDate: params.settledDateIso,
          description: `Commitment Paid: ${params.commitment.title}`,
          note: params.note,
        });

  const alreadySettled = calculateCommitmentSettledCents(
    params.commitment.id,
    params.existingSettlements,
    params.entries
  );
  const newSettled = alreadySettled + params.amountCents;
  const isNowPaid = newSettled >= params.commitment.amountCents;

  const settlement: SharedCommitmentSettlement = {
    id: settlementId,
    commitmentId: params.commitment.id,
    entryId,
    amountCents: params.amountCents,
    settledDate: params.settledDateIso,
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  };

  const updatedCommitment: SharedCommitment = {
    ...params.commitment,
    linkedAccountId: params.accountId,
    isPaid: isNowPaid,
    settlementEntryId: isNowPaid ? entryId : params.commitment.settlementEntryId,
    legacyPaidUnverified: false,
  };

  const nowIso = EthiopiaClock.nowUtc().toISOString();
  const simpleTransaction: SimpleTransaction = {
    id: `tx-com-${settlementId}`,
    type: direction === 'inflow' ? 'income' : 'expense',
    amountCents: params.amountCents,
    accountId: params.accountId,
    categoryId,
    description: built.entry.description,
    transactionDate: params.settledDateIso,
    createdAt: nowIso,
    updatedAt: nowIso,
    journalEntryId: entryId,
  };

  return {
    updatedCommitment,
    settlement,
    entry: built.entry,
    postings: built.postings,
    simpleTransaction,
  };
}

export function voidCommitmentSettlementV7(params: {
  settlementId: string;
  reason: string;
  commitment: SharedCommitment;
  settlements: SharedCommitmentSettlement[];
  entries: JournalEntry[];
}): {
  updatedCommitment: SharedCommitment;
  updatedEntries: JournalEntry[];
} {
  const target = params.settlements.find((s) => s.id === params.settlementId);
  if (!target) {
    throw new DoubleEntryValidationError('Settlement record not found.');
  }

  const updatedEntries = params.entries.map((e) =>
    e.id === target.entryId ? { ...e, isVoided: true, voidReason: params.reason } : e
  );
  const remainingSettled = calculateCommitmentSettledCents(
    params.commitment.id,
    params.settlements,
    updatedEntries
  );

  return {
    updatedCommitment: {
      ...params.commitment,
      isPaid: remainingSettled >= params.commitment.amountCents,
      settlementEntryId:
        remainingSettled >= params.commitment.amountCents
          ? params.commitment.settlementEntryId
          : undefined,
    },
    updatedEntries,
  };
}

/**
 * Debt Origin Voiding (only if zero active settlements and zero active write-off).
 */
export function voidDebtOriginV7(params: {
  debt: Debt;
  reason: string;
  allocations: SettlementAllocation[];
  entries: JournalEntry[];
}): {
  updatedDebt: Debt;
  updatedEntries: JournalEntry[];
} {
  const voidedIds = new Set(params.entries.filter((e) => e.isVoided).map((e) => e.id));
  const hasActiveSettlement = params.allocations.some(
    (a) => a.debtId === params.debt.id && !voidedIds.has(a.settlementEntryId)
  );
  if (hasActiveSettlement) {
    throw new DoubleEntryValidationError(
      'Cannot void debt with active settlements. Void the settlement entries first.'
    );
  }
  if (params.debt.writeOffEntryId && !voidedIds.has(params.debt.writeOffEntryId)) {
    throw new DoubleEntryValidationError(
      'Cannot void debt with an active write-off. Void the write-off entry first.'
    );
  }

  const updatedEntries = params.entries.map((e) =>
    e.id === params.debt.originEntryId ? { ...e, isVoided: true, voidReason: params.reason } : e
  );

  return {
    updatedDebt: {
      ...params.debt,
      status: 'voided',
      outstandingCents: 0,
    },
    updatedEntries,
  };
}

/**
 * Restores a written-off debt when its writeOffEntryId journal entry is voided.
 */
export function voidDebtWriteOffV7(params: {
  debt: Debt;
  reason: string;
  allocations: SettlementAllocation[];
  entries: JournalEntry[];
}): {
  updatedDebt: Debt;
  updatedEntries: JournalEntry[];
} {
  if (!params.debt.writeOffEntryId) {
    throw new DoubleEntryValidationError('Debt does not have a recorded write-off entry.');
  }

  const updatedEntries = params.entries.map((e) =>
    e.id === params.debt.writeOffEntryId ? { ...e, isVoided: true, voidReason: params.reason } : e
  );
  const voidedIds = new Set(updatedEntries.filter((e) => e.isVoided).map((e) => e.id));
  const settledPrincipal = params.allocations
    .filter((a) => a.debtId === params.debt.id && !voidedIds.has(a.settlementEntryId))
    .reduce((sum, a) => sum + a.allocatedCents, 0);
  const restoredOutstanding = Math.max(0, params.debt.principalCents - settledPrincipal);

  return {
    updatedDebt: {
      ...params.debt,
      writeOffEntryId: undefined,
      outstandingCents: restoredOutstanding,
      status: restoredOutstanding === 0 ? 'settled' : 'active',
    },
    updatedEntries,
  };
}

/**
 * Funds a Savings Goal:
 * - Virtual (no linkedAccountId): increments currentAllocatedCents without touching cash postings.
 * - Vault-linked (linkedAccountId present): builds a balanced vault transfer (Dr Vault / Cr Source).
 */
export function fundSavingsGoalV7(params: {
  goal: SharedSavingsGoal;
  amountCents: number;
  sourceAccountId?: string;
  dateIso: string;
  accounts?: Account[];
}): {
  updatedGoal: SharedSavingsGoal;
  entry?: JournalEntry;
  postings?: Posting[];
  simpleTransaction?: SimpleTransaction;
} {
  if (!Number.isInteger(params.amountCents) || params.amountCents <= 0) {
    throw new DoubleEntryValidationError('Funding amount must be a positive integer.');
  }

  if (params.goal.linkedAccountId) {
    if (!params.sourceAccountId) {
      throw new DoubleEntryValidationError('Source account is required to fund a vault-linked goal.');
    }
    if (params.sourceAccountId === params.goal.linkedAccountId) {
      throw new DoubleEntryValidationError('Source account cannot be identical to target vault.');
    }
    if (params.accounts) {
      assertEtbPostingAccounts({
        accounts: params.accounts,
        accountIds: [params.sourceAccountId, params.goal.linkedAccountId],
        roleLabels: ['Source account', 'Savings vault account'],
      });
      const vaultAcc = params.accounts.find((a) => a.id === params.goal.linkedAccountId);
      if (!vaultAcc || vaultAcc.subType !== 'savings_vault') {
        throw new DoubleEntryValidationError(
          `Goal target "${vaultAcc?.name || params.goal.linkedAccountId}" must be an active ETB savings vault account.`
        );
      }
    }
  }

  const nextAllocated = params.goal.currentAllocatedCents + params.amountCents;
  const nextStatus = nextAllocated >= params.goal.targetCents ? 'completed' : 'active';
  const updatedGoal: SharedSavingsGoal = {
    ...params.goal,
    currentAllocatedCents: nextAllocated,
    status: nextStatus,
  };

  if (params.goal.linkedAccountId && params.sourceAccountId) {
    const entryId = `entry-sav-${params.goal.id}-${Date.now()}`;
    const built = buildTransfer({
      id: entryId,
      fromAssetAccountId: params.sourceAccountId,
      toAssetAccountId: params.goal.linkedAccountId,
      amountCents: params.amountCents,
      date: params.dateIso,
      description: `Savings Funding: ${params.goal.title}`,
    });
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const simpleTransaction: SimpleTransaction = {
      id: `tx-sav-${Date.now()}`,
      type: 'transfer',
      amountCents: params.amountCents,
      accountId: params.sourceAccountId,
      destinationAccountId: params.goal.linkedAccountId,
      description: built.entry.description,
      transactionDate: params.dateIso,
      createdAt: nowIso,
      updatedAt: nowIso,
      journalEntryId: entryId,
    };
    return { updatedGoal, entry: built.entry, postings: built.postings, simpleTransaction };
  }

  return { updatedGoal };
}

function addGregorianMonthsClamped(cal: CalendarDate, monthsToAdd: number): CalendarDate {
  const zeroBasedMonth = cal.month - 1 + monthsToAdd;
  const targetYear = cal.year + Math.floor(zeroBasedMonth / 12);
  const targetMonth = (((zeroBasedMonth % 12) + 12) % 12) + 1;
  const maxDay = CalendarDate.daysInMonthFor('gregorian', targetYear, targetMonth);
  return new CalendarDate(targetYear, targetMonth, Math.min(cal.day, maxDay));
}

export function advanceRecurringDate(
  dateIso: string,
  frequency: SharedRecurringRule['frequency'],
  interval: number = 1
): string {
  const step = Math.max(1, interval || 1);
  const cal = CalendarDate.parse(dateIso);
  switch (frequency) {
    case 'weekly':
      return cal.addDays(7 * step).toIsoString();
    case 'biweekly':
      return cal.addDays(14 * step).toIsoString();
    case 'monthly':
      return addGregorianMonthsClamped(cal, step).toIsoString();
    case 'quarterly':
      return addGregorianMonthsClamped(cal, 3 * step).toIsoString();
    case 'yearly':
      return addGregorianMonthsClamped(cal, 12 * step).toIsoString();
  }
}

export function skipNextRecurringOccurrenceV7(rule: SharedRecurringRule): SharedRecurringRule {
  const nextDate = advanceRecurringDate(rule.nextOccurrenceDate, rule.frequency, rule.interval);
  const expired = Boolean(rule.endDate && nextDate > rule.endDate);
  return {
    ...rule,
    nextOccurrenceDate: nextDate,
    isActive: expired ? false : rule.isActive,
  };
}

export function processDueRecurringRulesV7(params: {
  rules: SharedRecurringRule[];
  todayIso?: string;
  accounts?: Account[];
  debts?: Debt[];
  entries?: JournalEntry[];
  postings?: Posting[];
  allocations?: SettlementAllocation[];
}): {
  updatedRules: SharedRecurringRule[];
  createdEntries: JournalEntry[];
  createdPostings: Posting[];
  createdCommitments: SharedCommitment[];
  createdSimpleTransactions: SimpleTransaction[];
  skippedRuleIds: string[];
  warnings: string[];
} {
  const todayIso = params.todayIso || CalendarDate.today().toIsoString();
  const createdEntries: JournalEntry[] = [];
  const createdPostings: Posting[] = [];
  const createdCommitments: SharedCommitment[] = [];
  const createdSimpleTransactions: SimpleTransaction[] = [];
  const skippedRuleIds: string[] = [];
  const warnings: string[] = [];

  const accountById = params.accounts
    ? new Map(params.accounts.map((a) => [a.id, a]))
    : undefined;
  const entryById = params.entries
    ? new Map(params.entries.map((e) => [e.id, e]))
    : undefined;
  const classifications =
    params.accounts && params.entries && params.postings
      ? classifyAllJournalEntries({
          accounts: params.accounts,
          entries: params.entries,
          postings: params.postings,
          debts: params.debts,
          allocations: params.allocations,
        })
      : undefined;
  const debtById = params.debts
    ? new Map(params.debts.map((d) => [d.id, d]))
    : undefined;

  const updatedRules = params.rules.map((rule) => {
    if (!rule.isActive || !rule.autoPost) return rule;

    if (accountById) {
      const ruleAccountIds = [rule.accountId, rule.destinationAccountId].filter(
        (id): id is string => Boolean(id)
      );
      const invalidAccount = ruleAccountIds.some(
        (id) => !isActiveVerifiedEtbAccount(accountById.get(id))
      );
      const linkedDebtInvalid = (() => {
        if (!rule.linkedDebtId || !debtById) return false;
        const debt = debtById.get(rule.linkedDebtId);
        if (!debt) return true;
        return !isDebtEligibleEtb(debt, entryById, classifications);
      })();

      if (invalidAccount || linkedDebtInvalid) {
        skippedRuleIds.push(rule.id);
        warnings.push(
          `Paused recurring rule "${rule.title}": references non-ETB, archived, or unverified account/debt.`
        );
        return { ...rule, autoPost: false };
      }
    }

    let current = { ...rule };
    let safety = 0;

    while (
      current.isActive &&
      current.nextOccurrenceDate <= todayIso &&
      (!current.endDate || current.nextOccurrenceDate <= current.endDate) &&
      safety < 24
    ) {
      safety += 1;
      const occDate = current.nextOccurrenceDate;
      const stamp = `${current.id}-${occDate}-${safety}`;
      const nowIso = EthiopiaClock.nowUtc().toISOString();

      if (current.ruleType === 'commitment') {
        createdCommitments.push({
          id: `com-rec-${stamp}`,
          title: current.title,
          amountCents: current.amountCents,
          dueDate: occDate,
          isPaid: false,
          linkedAccountId: current.accountId,
          categoryId: current.categoryId,
          linkedDebtId: current.linkedDebtId,
          recurringRuleId: current.id,
          direction: 'outflow',
          legacyPaidUnverified: false,
        });
      } else if (current.ruleType === 'expense' && current.accountId) {
        const entryId = `entry-rec-${stamp}`;
        const built = buildDirectExpense({
          id: entryId,
          assetAccountId: current.accountId,
          expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
          categoryId: current.categoryId || 'cat-other-exp',
          amountCents: current.amountCents,
          occurrenceDate: occDate,
          movementDate: occDate,
          description: `Recurring: ${current.title}`,
        });
        createdEntries.push(built.entry);
        createdPostings.push(...built.postings);
        createdSimpleTransactions.push({
          id: `tx-rec-${stamp}`,
          type: 'expense',
          amountCents: current.amountCents,
          accountId: current.accountId,
          categoryId: current.categoryId || 'cat-other-exp',
          description: `Recurring: ${current.title}`,
          transactionDate: occDate,
          createdAt: nowIso,
          updatedAt: nowIso,
          journalEntryId: entryId,
        });
      } else if (current.ruleType === 'income' && current.accountId) {
        const entryId = `entry-rec-${stamp}`;
        const built = buildDirectIncome({
          id: entryId,
          assetAccountId: current.accountId,
          incomeAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.income,
          categoryId: current.categoryId || 'cat-other-inc',
          amountCents: current.amountCents,
          occurrenceDate: occDate,
          movementDate: occDate,
          description: `Recurring: ${current.title}`,
        });
        createdEntries.push(built.entry);
        createdPostings.push(...built.postings);
        createdSimpleTransactions.push({
          id: `tx-rec-${stamp}`,
          type: 'income',
          amountCents: current.amountCents,
          accountId: current.accountId,
          categoryId: current.categoryId || 'cat-other-inc',
          description: `Recurring: ${current.title}`,
          transactionDate: occDate,
          createdAt: nowIso,
          updatedAt: nowIso,
          journalEntryId: entryId,
        });
      } else if (
        current.ruleType === 'transfer' &&
        current.accountId &&
        current.destinationAccountId &&
        current.accountId !== current.destinationAccountId
      ) {
        const entryId = `entry-rec-${stamp}`;
        const built = buildTransfer({
          id: entryId,
          fromAssetAccountId: current.accountId,
          toAssetAccountId: current.destinationAccountId,
          amountCents: current.amountCents,
          date: occDate,
          description: `Recurring Transfer: ${current.title}`,
        });
        createdEntries.push(built.entry);
        createdPostings.push(...built.postings);
        createdSimpleTransactions.push({
          id: `tx-rec-${stamp}`,
          type: 'transfer',
          amountCents: current.amountCents,
          accountId: current.accountId,
          destinationAccountId: current.destinationAccountId,
          description: `Recurring Transfer: ${current.title}`,
          transactionDate: occDate,
          createdAt: nowIso,
          updatedAt: nowIso,
          journalEntryId: entryId,
        });
      }

      const nextDate = advanceRecurringDate(occDate, current.frequency, current.interval);
      const expired = Boolean(current.endDate && nextDate > current.endDate);
      current = {
        ...current,
        nextOccurrenceDate: nextDate,
        isActive: expired ? false : current.isActive,
      };
    }

    return current;
  });

  return {
    updatedRules,
    createdEntries,
    createdPostings,
    createdCommitments,
    createdSimpleTransactions,
    skippedRuleIds,
    warnings,
  };
}

/**
 * Synchronizes SimpleTransaction[] (including Quick Capture entries written from App.tsx)
 * into balanced JournalEntries & Postings idempotently so Double-Entry reports and Safe Harbor
 * totals always agree with the transactions list.
 */
export function hydrateLedgerFromSimpleTransactions(params: {
  accounts: Account[];
  transactions: SimpleTransaction[];
  entries: JournalEntry[];
  postings: Posting[];
}): {
  accounts: Account[];
  entries: JournalEntry[];
  postings: Posting[];
  migratedCount: number;
} {
  const accountsWithControls = ensureSystemControlAccounts(params.accounts);
  const existingEntryIds = new Set(params.entries.map((e) => e.id));
  const existingLegacyTxIds = new Set(
    params.entries.map((e) => e.legacySourceTxId).filter((id): id is string => Boolean(id))
  );

  // Ensure every non-zero openingBalanceCents has an opening balance ledger entry if none exists yet
  let nextEntries = [...params.entries];
  let nextPostings = [...params.postings];
  let migratedCount = 0;

  for (const acc of accountsWithControls) {
    if (acc.isSystem) continue;
    if ((acc.openingBalanceCents || 0) === 0) continue;
    const prefix = `open:${acc.id}`;
    const hasOpen = nextEntries.some(
      (e) =>
        e.legacySourceTxId === prefix ||
        (e.legacySourceTxId?.startsWith(`${prefix}:rev:`) ?? false)
    );
    if (!hasOpen) {
      const res = reviseAccountOpeningBalanceV7({
        account: acc,
        newOpeningBalanceCents: acc.openingBalanceCents || 0,
        newOpeningDateIso: acc.openingBalanceDate,
        entries: nextEntries,
        postings: nextPostings,
        allowLegacyNonEtb: true,
      });
      nextEntries = res.updatedEntries;
      nextPostings = res.updatedPostings;
    }
  }

  for (const tx of params.transactions) {
    if (tx.journalEntryId && existingEntryIds.has(tx.journalEntryId)) continue;
    if (existingLegacyTxIds.has(tx.id)) continue;
    if (!Number.isInteger(tx.amountCents) || tx.amountCents <= 0) continue;

    const entryId = `entry-sync-${tx.id}`;
    if (existingEntryIds.has(entryId)) continue;

    try {
      let built: { entry: JournalEntry; postings: Posting[] } | null = null;
      if (tx.type === 'expense') {
        built = buildDirectExpense({
          id: entryId,
          assetAccountId: tx.accountId,
          expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
          categoryId: tx.categoryId || 'cat-other-exp',
          amountCents: tx.amountCents,
          occurrenceDate: tx.transactionDate,
          movementDate: tx.transactionDate,
          description: tx.description || 'Expense',
        });
      } else if (tx.type === 'income') {
        built = buildDirectIncome({
          id: entryId,
          assetAccountId: tx.accountId,
          incomeAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.income,
          categoryId: tx.categoryId || 'cat-other-inc',
          amountCents: tx.amountCents,
          occurrenceDate: tx.transactionDate,
          movementDate: tx.transactionDate,
          description: tx.description || 'Income',
        });
      } else if (
        tx.type === 'transfer' &&
        tx.destinationAccountId &&
        tx.destinationAccountId !== tx.accountId
      ) {
        built = buildTransfer({
          id: entryId,
          fromAssetAccountId: tx.accountId,
          toAssetAccountId: tx.destinationAccountId,
          amountCents: tx.amountCents,
          date: tx.transactionDate,
          description: tx.description || 'Transfer',
        });
      }
      if (built) {
        built.entry.legacySourceTxId = tx.id;
        built.entry.isVoided = Boolean(tx.isSuperseded);
        nextEntries.unshift(built.entry);
        nextPostings.unshift(...built.postings);
        existingEntryIds.add(entryId);
        existingLegacyTxIds.add(tx.id);
        migratedCount += 1;
      }
    } catch {
      // Skip malformed legacy item without crashing UI
    }
  }

  return {
    accounts: accountsWithControls,
    entries: nextEntries,
    postings: nextPostings,
    migratedCount,
  };
}

export function verifyFinanceV7Integrity(params: {
  accounts: Account[];
  entries: JournalEntry[];
  postings: Posting[];
  debts: Debt[];
  commitments: SharedCommitment[];
  allocations?: SettlementAllocation[];
  recurringRules?: SharedRecurringRule[];
  commitmentSettlements?: SharedCommitmentSettlement[];
  savingsGoals?: SharedSavingsGoal[];
}): FinanceV7IntegrityReport {
  const errors: string[] = [];
  const warnings: string[] = [];
  let unbalancedEntriesCount = 0;

  const postingsByEntry = new Map<string, Posting[]>();
  for (const p of params.postings) {
    const list = postingsByEntry.get(p.entryId) || [];
    list.push(p);
    postingsByEntry.set(p.entryId, list);
  }

  for (const entry of params.entries) {
    if (entry.isVoided) continue;
    const list = postingsByEntry.get(entry.id) || [];
    try {
      validateBalancedEntry(list);
    } catch (e: any) {
      unbalancedEntriesCount += 1;
      errors.push(`Entry ${entry.id} ("${entry.description}"): ${e?.message || 'Unbalanced'}`);
    }
  }

  const currencyAudit = auditCurrencyIsolation({
    accounts: params.accounts,
    entries: params.entries,
    postings: params.postings,
    debts: params.debts,
    allocations: params.allocations,
    commitments: params.commitments,
    recurringRules: params.recurringRules,
    commitmentSettlements: params.commitmentSettlements,
    savingsGoals: params.savingsGoals,
  });

  const voidedEntryIds = new Set(params.entries.filter((e) => e.isVoided).map((e) => e.id));
  const computeEtbControlBalance = (acc: Account | undefined): number => {
    if (!acc) return 0;
    let bal = acc.openingBalanceCents || 0;
    for (const p of params.postings) {
      if (p.accountId !== acc.id || voidedEntryIds.has(p.entryId)) continue;
      if (!(currencyAudit.classificationsByEntryId.get(p.entryId)?.isEligibleEtb ?? false)) {
        continue;
      }
      if (acc.type === 'asset' || acc.type === 'expense') {
        bal += p.direction === 'debit' ? p.amountCents : -p.amountCents;
      } else {
        bal += p.direction === 'credit' ? p.amountCents : -p.amountCents;
      }
    }
    return bal;
  };

  const recAcc = params.accounts.find((a) => a.id === SYSTEM_CONTROL_ACCOUNT_IDS.receivable);
  const payAcc = params.accounts.find((a) => a.id === SYSTEM_CONTROL_ACCOUNT_IDS.payable);

  const receivableControlBalanceCents = computeEtbControlBalance(recAcc);
  const payableControlBalanceCents = computeEtbControlBalance(payAcc);

  const activeReceivableSumCents = calculateTotalReceivables(params.debts, {
    accounts: params.accounts,
    entries: params.entries,
    postings: params.postings,
    allocations: params.allocations,
  });
  const activePayableSumCents = calculateTotalPayables(params.debts, {
    accounts: params.accounts,
    entries: params.entries,
    postings: params.postings,
    allocations: params.allocations,
  });

  const mismatchDetails: string[] = [];
  if (receivableControlBalanceCents !== activeReceivableSumCents) {
    mismatchDetails.push(
      `Receivable control (${receivableControlBalanceCents}) != active ETB receivables sum (${activeReceivableSumCents})`
    );
  }
  if (payableControlBalanceCents !== activePayableSumCents) {
    mismatchDetails.push(
      `Payable control (${payableControlBalanceCents}) != active ETB payables sum (${activePayableSumCents})`
    );
  }

  const unverifiedLegacyPaidCount = params.commitments.filter((c) => c.legacyPaidUnverified).length;

  warnings.push(...currencyAudit.warnings);
  if (unverifiedLegacyPaidCount > 0) {
    warnings.push(
      `${unverifiedLegacyPaidCount} legacy paid commitment(s) need verification (Record Cash Payment or Mark Unpaid).`
    );
  }

  return {
    isHealthy: errors.length === 0 && mismatchDetails.length === 0,
    errors,
    warnings,
    debtControlAudit: {
      receivableControlBalanceCents,
      activeReceivableSumCents,
      payableControlBalanceCents,
      activePayableSumCents,
      receivableDeltaCents: receivableControlBalanceCents - activeReceivableSumCents,
      payableDeltaCents: payableControlBalanceCents - activePayableSumCents,
      isTierABalanced: mismatchDetails.length === 0,
      mismatchDetails,
    },
    unbalancedEntriesCount,
    totalEntriesCount: params.entries.length,
    nonEtbAccountCount: currencyAudit.nonEtbAccountCount,
    unverifiedAccountCount: currencyAudit.unverifiedAccountCount,
    unverifiedLegacyPaidCount,
    excludedNonEtbEntryCount: currencyAudit.excludedNonEtbEntryCount,
    currencyReviewEntryCount: currencyAudit.currencyReviewEntryCount,
    excludedNonEtbDebtCount: currencyAudit.excludedNonEtbDebtCount,
    excludedNonEtbCommitmentCount: currencyAudit.excludedNonEtbCommitmentCount,
  };
}

export {
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
  calculateAccountBalance,
  classifyAllJournalEntries,
  classifyCurrencyCode,
  classifyJournalEntryCurrency,
  formatCurrencyCents,
  generateCashFlowReport,
  generateOccurrenceReport,
  isActiveVerifiedEtbAccount,
  isDebtEligibleEtb,
  isEtbCurrency,
  isValidCurrencyCode,
  normalizeCurrencyCode,
  resolveCommitmentCurrencyStatus,
};
export type {
  Account,
  AccountSubType,
  CurrencyIsolationAudit,
  CurrencyValidationTier,
  Debt,
  EntryCurrencyClassification,
  EntryCurrencyStatus,
  JournalEntry,
  Party,
  Posting,
  SettlementAllocation,
  SimpleTransaction,
  TransactionCategory,
  SharedBudget,
  SharedCategory,
  SharedCommitment,
  SharedCommitmentSettlement,
  SharedRecurringRule,
  SharedSavingsGoal,
};
