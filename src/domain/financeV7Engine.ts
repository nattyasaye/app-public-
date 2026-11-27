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
import { CalendarDate, EthiopianDate, EthiopiaClock } from './date';
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
  calculateNetPosition,
  calculateSafePercentageChange,
  calculateTotalPayables,
  calculateTotalReceivables,
  CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID,
  CANONICAL_DEFAULT_INCOME_CATEGORY_ID,
  CashFlowReportSummary,
  categoryIdsMatchOrAlias,
  classifyAllJournalEntries,
  classifyCurrencyCode,
  classifyJournalEntryCurrency,
  CurrencyIsolationAudit,
  CurrencyValidationTier,
  Debt,
  DirectExpenseSummary,
  DoubleEntryValidationError,
  EntryCurrencyClassification,
  EntryCurrencyStatus,
  findCategoryByIdOrAlias,
  formatCurrencyCents,
  FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
  FOUNDATION_DEFAULT_INCOME_CATEGORIES,
  generateCashFlowReport,
  generateOccurrenceReport,
  isActiveVerifiedEtbAccount,
  isDebtEligibleEtb,
  isEtbCurrency,
  isExpenseFeePosting,
  isValidCurrencyCode,
  JournalEntry,
  LEGACY_CATEGORY_ID_ALIASES,
  normalizeCurrencyCode,
  OccurrenceReportSummary,
  parseQuickCaptureExpense,
  Party,
  Posting,
  QuickCaptureParsedExpense,
  resolveCanonicalCategoryId,
  resolveCategoryDisplayName,
  resolveCommitmentCurrencyStatus,
  resolveTransferDisplayEndpoints,
  SettlementAllocation,
  SimpleTransaction,
  summarizeDirectExpense,
  TransactionCategory,
  TransferDisplayEndpoints,
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
  const uniqueSuffix = `${Date.now()}-${params.existingSettlements.length + 1}-${Math.random().toString(36).slice(2, 6)}`;
  const entryId = `entry-com-${params.commitment.id}-${uniqueSuffix}`;
  const settlementId = `cset-${params.commitment.id}-${uniqueSuffix}`;
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
 * Returns the target vault account balance for a vault-linked Savings Goal, or
 * its allocated reserve for a virtual goal.
 */
export function getSavingsGoalEffectiveBalanceV7(params: {
  goal: SharedSavingsGoal;
  accounts: Account[];
  entries: JournalEntry[];
  postings: Posting[];
}): number {
  if (!params.goal.linkedAccountId) {
    return Math.max(0, params.goal.currentAllocatedCents);
  }
  const vaultAcc = params.accounts.find((a) => a.id === params.goal.linkedAccountId);
  if (!vaultAcc) {
    return Math.max(0, params.goal.currentAllocatedCents);
  }
  return Math.max(0, calculateV7AccountBalance(vaultAcc, params.postings, params.entries));
}

/**
 * Synchronizes vault-linked SavingsGoal currentAllocatedCents and completion status
 * from the authoritative ledger balance of their linked savings_vault account.
 * Archived goals preserve their archived status and 0 allocation.
 */
export function syncVaultSavingsGoalsV7(params: {
  accounts: Account[];
  entries: JournalEntry[];
  postings: Posting[];
  savingsGoals: SharedSavingsGoal[];
}): SharedSavingsGoal[] {
  const accountById = new Map(params.accounts.map((a) => [a.id, a]));
  return params.savingsGoals.map((goal) => {
    if (!goal.linkedAccountId || goal.status === 'archived') {
      return goal;
    }
    const vaultAcc = accountById.get(goal.linkedAccountId);
    if (!vaultAcc || vaultAcc.subType !== 'savings_vault') {
      return goal;
    }
    const nextAllocated = Math.max(
      0,
      calculateV7AccountBalance(vaultAcc, params.postings, params.entries)
    );
    const nextStatus: SharedSavingsGoal['status'] =
      goal.targetCents > 0 && nextAllocated >= goal.targetCents ? 'completed' : 'active';
    if (
      goal.currentAllocatedCents === nextAllocated &&
      goal.status === nextStatus
    ) {
      return goal;
    }
    return {
      ...goal,
      currentAllocatedCents: nextAllocated,
      status: nextStatus,
    };
  });
}

/**
 * Reconciles every Debt's status and outstandingCents from active journal entries
 * and active SettlementAllocations.
 */
export function reconcileDebtsV7(params: {
  debts: Debt[];
  entries: JournalEntry[];
  allocations: SettlementAllocation[];
}): Debt[] {
  const entryById = new Map(params.entries.map((e) => [e.id, e]));
  const voidedIds = new Set(params.entries.filter((e) => e.isVoided).map((e) => e.id));

  return params.debts.map((debt) => {
    const originEntry = entryById.get(debt.originEntryId);
    if (originEntry?.isVoided) {
      if (debt.status === 'voided' && debt.outstandingCents === 0 && !debt.writeOffEntryId) {
        return debt;
      }
      return {
        ...debt,
        status: 'voided',
        outstandingCents: 0,
        writeOffEntryId: undefined,
      };
    }

    const settledPrincipal = params.allocations
      .filter((a) => a.debtId === debt.id && !voidedIds.has(a.settlementEntryId))
      .reduce((sum, a) => sum + Math.max(0, a.allocatedCents), 0);
    const clampedSettled = Math.min(debt.principalCents, settledPrincipal);
    const remaining = Math.max(0, debt.principalCents - clampedSettled);

    const writeOffId = debt.writeOffEntryId;
    const writeOffEntry = writeOffId ? entryById.get(writeOffId) : undefined;
    const hasActiveLinkedWriteOff =
      Boolean(writeOffEntry) &&
      writeOffEntry!.entryType === 'write_off' &&
      !voidedIds.has(writeOffEntry!.id);
    const isLegacyWrittenOffWithoutLink =
      !writeOffId && debt.status === 'written_off';
    const hasActiveWriteOff = hasActiveLinkedWriteOff || isLegacyWrittenOffWithoutLink;

    if (hasActiveWriteOff) {
      if (debt.status === 'written_off' && debt.outstandingCents === 0) {
        return debt;
      }
      return {
        ...debt,
        status: 'written_off',
        outstandingCents: 0,
      };
    }

    const nextStatus: Debt['status'] = remaining === 0 ? 'settled' : 'active';
    if (
      debt.status === nextStatus &&
      debt.outstandingCents === remaining &&
      debt.writeOffEntryId === undefined
    ) {
      return debt;
    }
    return {
      ...debt,
      writeOffEntryId: undefined,
      outstandingCents: remaining,
      status: nextStatus,
    };
  });
}

/**
 * Prevents archiving a savings_vault account while its ledger balance is nonzero.
 */
export function assertCanArchiveAccountV7(params: {
  account: Account;
  entries: JournalEntry[];
  postings: Posting[];
}): void {
  if (params.account.isArchived) return;
  if (params.account.subType === 'savings_vault') {
    const bal = calculateV7AccountBalance(params.account, params.postings, params.entries);
    if (bal !== 0) {
      throw new DoubleEntryValidationError(
        `Cannot archive savings vault "${params.account.name}" while its balance is nonzero (${formatCurrencyCents(bal, params.account.currencyCode)}). Withdraw or transfer all funds to zero first.`
      );
    }
  }
}

/**
 * Prevents archiving a vault-linked SavingsGoal while its ledger/allocated balance is nonzero.
 */
export function assertCanArchiveSavingsGoalV7(params: {
  goal: SharedSavingsGoal;
  accounts: Account[];
  entries: JournalEntry[];
  postings: Posting[];
}): void {
  if (params.goal.status === 'archived' || !params.goal.linkedAccountId) return;
  const bal = getSavingsGoalEffectiveBalanceV7({
    goal: params.goal,
    accounts: params.accounts,
    entries: params.entries,
    postings: params.postings,
  });
  if (bal > 0) {
    throw new DoubleEntryValidationError(
      `Cannot archive vault-linked savings goal "${params.goal.title}" while its balance is nonzero (${formatCurrencyCents(bal, 'ETB')}). Withdraw all funds back to a liquid account first.`
    );
  }
}

/**
 * Funds or withdraws from a Savings Goal:
 * - Virtual (no linkedAccountId): increments/decrements currentAllocatedCents without touching cash postings.
 * - Vault-linked (linkedAccountId present): builds a balanced transfer between liquid account and vault.
 */
export function fundSavingsGoalV7(params: {
  goal: SharedSavingsGoal;
  amountCents: number;
  direction?: 'deposit' | 'withdraw';
  sourceAccountId?: string;
  dateIso: string;
  accounts?: Account[];
  entries?: JournalEntry[];
  postings?: Posting[];
}): {
  updatedGoal: SharedSavingsGoal;
  entry?: JournalEntry;
  postings?: Posting[];
  simpleTransaction?: SimpleTransaction;
} {
  const direction = params.direction ?? 'deposit';
  if (!Number.isInteger(params.amountCents) || params.amountCents <= 0) {
    throw new DoubleEntryValidationError('Amount must be a positive integer.');
  }
  if (params.goal.status === 'archived') {
    throw new DoubleEntryValidationError('Cannot modify an archived savings goal.');
  }

  const currentVaultOrAllocatedCents =
    params.goal.linkedAccountId &&
    params.accounts &&
    params.entries &&
    params.postings
      ? getSavingsGoalEffectiveBalanceV7({
          goal: params.goal,
          accounts: params.accounts,
          entries: params.entries,
          postings: params.postings,
        })
      : Math.max(0, params.goal.currentAllocatedCents);

  if (direction === 'withdraw' && params.amountCents > currentVaultOrAllocatedCents) {
    throw new DoubleEntryValidationError(
      `Withdrawal amount (${params.amountCents}) exceeds available savings balance (${currentVaultOrAllocatedCents}).`
    );
  }

  if (params.goal.linkedAccountId) {
    if (!params.sourceAccountId) {
      throw new DoubleEntryValidationError(
        direction === 'withdraw'
          ? 'Destination liquid account is required to withdraw from a vault-linked goal.'
          : 'Source account is required to fund a vault-linked goal.'
      );
    }
    if (params.sourceAccountId === params.goal.linkedAccountId) {
      throw new DoubleEntryValidationError(
        'Liquid account cannot be identical to target vault.'
      );
    }
    if (params.accounts) {
      assertEtbPostingAccounts({
        accounts: params.accounts,
        accountIds: [params.sourceAccountId, params.goal.linkedAccountId],
        roleLabels: [
          direction === 'withdraw' ? 'Destination liquid account' : 'Source account',
          'Savings vault account',
        ],
      });
      const liquidAcc = params.accounts.find((a) => a.id === params.sourceAccountId);
      if (direction === 'withdraw' && (!liquidAcc || !isLiquidSubType(liquidAcc))) {
        throw new DoubleEntryValidationError(
          `Withdrawal destination "${liquidAcc?.name || params.sourceAccountId}" must be an active ETB liquid asset account.`
        );
      }
      const vaultAcc = params.accounts.find((a) => a.id === params.goal.linkedAccountId);
      if (!vaultAcc || vaultAcc.subType !== 'savings_vault') {
        throw new DoubleEntryValidationError(
          `Goal target "${vaultAcc?.name || params.goal.linkedAccountId}" must be an active ETB savings vault account.`
        );
      }
    }
  }

  const signedDelta = direction === 'withdraw' ? -params.amountCents : params.amountCents;
  const nextAllocated = Math.max(0, currentVaultOrAllocatedCents + signedDelta);
  const nextStatus: SharedSavingsGoal['status'] =
    params.goal.targetCents > 0 && nextAllocated >= params.goal.targetCents
      ? 'completed'
      : 'active';
  const updatedGoal: SharedSavingsGoal = {
    ...params.goal,
    currentAllocatedCents: nextAllocated,
    status: nextStatus,
  };

  if (params.goal.linkedAccountId && params.sourceAccountId) {
    const stamp = `${params.goal.id}-${Date.now()}-${Math.random().toString(36).slice(2, 5)}`;
    const entryId = `entry-sav-${stamp}`;
    const isWithdraw = direction === 'withdraw';
    const fromId = isWithdraw ? params.goal.linkedAccountId : params.sourceAccountId;
    const toId = isWithdraw ? params.sourceAccountId : params.goal.linkedAccountId;
    const description = isWithdraw
      ? `Savings Withdrawal: ${params.goal.title}`
      : `Savings Funding: ${params.goal.title}`;

    const built = buildTransfer({
      id: entryId,
      fromAssetAccountId: fromId,
      toAssetAccountId: toId,
      amountCents: params.amountCents,
      date: params.dateIso,
      description,
    });
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const simpleTransaction: SimpleTransaction = {
      id: `tx-sav-${stamp}`,
      type: 'transfer',
      amountCents: params.amountCents,
      accountId: fromId,
      destinationAccountId: toId,
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

export const EXPENSE_REFUND_TAG_PREFIX = 'refund:';

export function extractRefundOriginEntryId(entry: JournalEntry): string | null {
  const tag = entry.legacySourceTxId;
  if (!tag || !tag.startsWith(EXPENSE_REFUND_TAG_PREFIX)) return null;
  const remainder = tag.slice(EXPENSE_REFUND_TAG_PREFIX.length);
  if (!remainder) return null;
  const lastColon = remainder.lastIndexOf(':');
  if (lastColon <= 0) return remainder;
  return remainder.slice(0, lastColon);
}

export function isRefundEntry(entry: JournalEntry): boolean {
  return extractRefundOriginEntryId(entry) !== null;
}

export function isCorrectableEntryTypeV7(entryType: JournalEntry['entryType']): boolean {
  return entryType === 'standard' || entryType === 'transfer';
}

export interface ExpenseRefundSummaryV7 {
  eligible: boolean;
  reason?: string;
  originalAmountCents: number;
  originalFeeCents?: number;
  refundedCents: number;
  remainingRefundableCents: number;
  categoryId?: string;
  originalAccountId?: string;
  originalOccurrenceDate?: string;
}

export function getExpenseRefundSummaryV7(params: {
  originalEntryId: string;
  entries: JournalEntry[];
  postings: Posting[];
  accounts: Account[];
  debts?: Debt[];
  allocations?: SettlementAllocation[];
}): ExpenseRefundSummaryV7 {
  const original = params.entries.find((e) => e.id === params.originalEntryId);
  if (!original) {
    return {
      eligible: false,
      reason: 'Original expense entry not found.',
      originalAmountCents: 0,
      refundedCents: 0,
      remainingRefundableCents: 0,
    };
  }
  if (original.isVoided) {
    return {
      eligible: false,
      reason: 'Voided entries cannot be refunded.',
      originalAmountCents: 0,
      refundedCents: 0,
      remainingRefundableCents: 0,
    };
  }
  if (original.entryType !== 'standard') {
    return {
      eligible: false,
      reason: `Only standard direct expense entries support expense refunds (got ${original.entryType}).`,
      originalAmountCents: 0,
      refundedCents: 0,
      remainingRefundableCents: 0,
    };
  }
  if (isRefundEntry(original) || original.legacySourceTxId?.startsWith('open:')) {
    return {
      eligible: false,
      reason: 'Opening balance adjustments and refund entries cannot themselves be refunded.',
      originalAmountCents: 0,
      refundedCents: 0,
      remainingRefundableCents: 0,
    };
  }

  const accountById = new Map(params.accounts.map((a) => [a.id, a]));
  const origPostings = params.postings.filter((p) => p.entryId === original.id);
  const cls = classifyJournalEntryCurrency({
    entry: original,
    entryPostings: origPostings,
    accountById,
    debts: params.debts,
    allocations: params.allocations,
    allEntries: params.entries,
    allPostings: params.postings,
  });
  if (cls.status !== 'eligible_etb') {
    return {
      eligible: false,
      reason: 'Only active Verified ETB expenses can be refunded in first-release ETB mode.',
      originalAmountCents: 0,
      refundedCents: 0,
      remainingRefundableCents: 0,
    };
  }

  const isExpenseAcc = (accId: string) =>
    accId === SYSTEM_CONTROL_ACCOUNT_IDS.expense ||
    accountById.get(accId)?.type === 'expense';
  const isIncomeOrDebtAcc = (accId: string) => {
    const acc = accountById.get(accId);
    return (
      accId === SYSTEM_CONTROL_ACCOUNT_IDS.income ||
      accId === SYSTEM_CONTROL_ACCOUNT_IDS.receivable ||
      accId === SYSTEM_CONTROL_ACCOUNT_IDS.payable ||
      acc?.type === 'income' ||
      acc?.subType === 'receivable' ||
      acc?.subType === 'payable'
    );
  };

  if (origPostings.some((p) => isIncomeOrDebtAcc(p.accountId))) {
    return {
      eligible: false,
      reason: 'Income and receivable/payable entries cannot be refunded as direct expenses.',
      originalAmountCents: 0,
      refundedCents: 0,
      remainingRefundableCents: 0,
    };
  }

  const expenseDebits = origPostings.filter(
    (p) => p.direction === 'debit' && isExpenseAcc(p.accountId)
  );
  const principalExpenseDebits = expenseDebits.filter((p) => !isExpenseFeePosting(p));
  const originalFeeCents = expenseDebits
    .filter((p) => isExpenseFeePosting(p))
    .reduce((sum, p) => sum + p.amountCents, 0);
  const expenseCredits = origPostings.filter(
    (p) => p.direction === 'credit' && isExpenseAcc(p.accountId)
  );
  const paidCreditPosting = origPostings.find(
    (p) => p.direction === 'credit' && !accountById.get(p.accountId)?.isSystem
  );
  if (principalExpenseDebits.length === 0 || expenseCredits.length > 0 || !paidCreditPosting) {
    return {
      eligible: false,
      reason: 'Entry is not a standard direct expense.',
      originalAmountCents: 0,
      refundedCents: 0,
      remainingRefundableCents: 0,
    };
  }

  const originalAmountCents = principalExpenseDebits.reduce((sum, p) => sum + p.amountCents, 0);
  const activeRefundEntries = params.entries.filter(
    (e) => !e.isVoided && extractRefundOriginEntryId(e) === original.id
  );
  let refundedCents = 0;
  for (const rEntry of activeRefundEntries) {
    const rPostings = params.postings.filter((p) => p.entryId === rEntry.id);
    const creditExp = rPostings
      .filter((p) => p.direction === 'credit' && isExpenseAcc(p.accountId))
      .reduce((s, p) => s + p.amountCents, 0);
    refundedCents += creditExp;
  }

  const remainingRefundableCents = Math.max(0, originalAmountCents - refundedCents);
  const categoryId = principalExpenseDebits.find((p) => p.categoryId)?.categoryId;

  return {
    eligible: true,
    originalAmountCents,
    originalFeeCents,
    refundedCents,
    remainingRefundableCents,
    categoryId,
    originalAccountId: paidCreditPosting.accountId,
    originalOccurrenceDate: original.occurrenceDate,
  };
}

export function canCorrectJournalEntryV7(params: {
  entry: JournalEntry;
  entries: JournalEntry[];
  postings: Posting[];
  accounts: Account[];
  debts?: Debt[];
  allocations?: SettlementAllocation[];
  commitmentSettlements?: SharedCommitmentSettlement[];
}): { ok: boolean; error?: string } {
  const { entry } = params;
  if (entry.isVoided) {
    return { ok: false, error: 'Voided entries cannot be replaced.' };
  }
  const alreadySuperseded = params.entries.some(
    (e) => !e.isVoided && e.correctedFromEntryId === entry.id
  );
  if (alreadySuperseded) {
    return { ok: false, error: 'This entry already has an active replacement.' };
  }
  const accountById = new Map(params.accounts.map((a) => [a.id, a]));
  const entryPostings = params.postings.filter((p) => p.entryId === entry.id);
  const cls = classifyJournalEntryCurrency({
    entry,
    entryPostings,
    accountById,
    debts: params.debts,
    allocations: params.allocations,
    allEntries: params.entries,
    allPostings: params.postings,
  });
  if (cls.status !== 'eligible_etb') {
    return {
      ok: false,
      error:
        'Excluded non-ETB or currency-review entries cannot be replaced in first-release ETB mode.',
    };
  }
  if (!isCorrectableEntryTypeV7(entry.entryType)) {
    return {
      ok: false,
      error: `Cannot replace ${entry.entryType} entries directly. Void the entry safely and record a new transaction instead.`,
    };
  }
  if (entry.legacySourceTxId?.startsWith('open:')) {
    return {
      ok: false,
      error: 'Opening balance adjustments must be revised via the account opening balance editor.',
    };
  }
  if (isRefundEntry(entry)) {
    return {
      ok: false,
      error: 'Expense refund entries cannot be replaced directly. Void the refund and record a new refund if needed.',
    };
  }
  if (params.commitmentSettlements?.some((s) => s.entryId === entry.id)) {
    return {
      ok: false,
      error:
        'Commitment settlement entries cannot be replaced directly. Void the installment in Plan and record a new settlement.',
    };
  }
  const hasActiveRefund = params.entries.some(
    (e) => !e.isVoided && extractRefundOriginEntryId(e) === entry.id
  );
  if (hasActiveRefund) {
    return {
      ok: false,
      error: 'Cannot replace an expense that has active refunds. Void the active refund(s) first.',
    };
  }
  if (params.debts?.some((d) => d.originEntryId === entry.id)) {
    return {
      ok: false,
      error: 'Cannot replace a debt-linked entry directly. Void the debt origin and re-issue.',
    };
  }
  return { ok: true };
}

export function recordExpenseRefundV7(params: {
  refundEntryId?: string;
  originalEntryId: string;
  refundAccountId: string;
  refundCents: number;
  refundDateIso: string;
  note?: string;
  entries: JournalEntry[];
  postings: Posting[];
  accounts: Account[];
  debts?: Debt[];
  allocations?: SettlementAllocation[];
}): {
  entry: JournalEntry;
  postings: Posting[];
  updatedSummary: ExpenseRefundSummaryV7;
} {
  if (!Number.isInteger(params.refundCents) || params.refundCents <= 0) {
    throw new DoubleEntryValidationError('Refund amount must be a positive integer in cents.');
  }
  if (!CalendarDate.tryParse(params.refundDateIso)) {
    throw new DoubleEntryValidationError('Refund date must be a valid YYYY-MM-DD civil date.');
  }

  const summary = getExpenseRefundSummaryV7({
    originalEntryId: params.originalEntryId,
    entries: params.entries,
    postings: params.postings,
    accounts: params.accounts,
    debts: params.debts,
    allocations: params.allocations,
  });
  if (!summary.eligible) {
    throw new DoubleEntryValidationError(summary.reason || 'Original entry is not refundable.');
  }
  if (summary.remainingRefundableCents <= 0) {
    throw new DoubleEntryValidationError('This expense has already been fully refunded.');
  }
  if (params.refundCents > summary.remainingRefundableCents) {
    throw new DoubleEntryValidationError(
      `Refund amount (${params.refundCents}) exceeds remaining refundable balance (${summary.remainingRefundableCents}).`
    );
  }
  if (
    summary.originalOccurrenceDate &&
    params.refundDateIso < summary.originalOccurrenceDate
  ) {
    throw new DoubleEntryValidationError(
      `Refund date (${params.refundDateIso}) cannot precede the original expense date (${summary.originalOccurrenceDate}).`
    );
  }

  assertEtbPostingAccounts({
    accounts: params.accounts,
    accountIds: [params.refundAccountId],
    roleLabels: ['Refund destination account'],
  });
  const destAcc = params.accounts.find((a) => a.id === params.refundAccountId);
  const sub = destAcc ? getAccountSubType(destAcc) : 'bank';
  if (
    !destAcc ||
    sub === 'savings_vault' ||
    sub === 'receivable' ||
    sub === 'payable' ||
    (destAcc.type !== 'asset' && !(destAcc.type === 'liability' && sub === 'credit_card'))
  ) {
    throw new DoubleEntryValidationError(
      'Refunds must return to an active Verified ETB liquid asset or credit card account.'
    );
  }

  const original = params.entries.find((e) => e.id === params.originalEntryId)!;
  const entryId =
    params.refundEntryId ||
    `entry-refund-${Date.now()}-${Math.random().toString(36).slice(2, 5)}`;
  const entry: JournalEntry = {
    id: entryId,
    entryType: 'standard',
    description: `Refund: ${original.description}`,
    occurrenceDate: params.refundDateIso,
    isVoided: false,
    legacySourceTxId: `${EXPENSE_REFUND_TAG_PREFIX}${original.id}:${entryId}`,
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  };

  const refundPostings: Posting[] = [
    {
      id: `${entryId}-post-dr`,
      entryId,
      accountId: params.refundAccountId,
      amountCents: params.refundCents,
      direction: 'debit',
      accountMovementDate: params.refundDateIso,
      note: params.note || `Refund for ${original.description}`,
    },
    {
      id: `${entryId}-post-cr`,
      entryId,
      accountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      amountCents: params.refundCents,
      direction: 'credit',
      accountMovementDate: params.refundDateIso,
      categoryId: summary.categoryId,
      note: params.note || `Refund for ${original.description}`,
    },
  ];
  validateBalancedEntry(refundPostings);

  const nextEntries = [entry, ...params.entries];
  const nextPostings = [...refundPostings, ...params.postings];
  const updatedSummary = getExpenseRefundSummaryV7({
    originalEntryId: original.id,
    entries: nextEntries,
    postings: nextPostings,
    accounts: params.accounts,
    debts: params.debts,
    allocations: params.allocations,
  });

  return { entry, postings: refundPostings, updatedSummary };
}

export function voidJournalEntryGuardedV7(params: {
  entryId: string;
  reason: string;
  accounts: Account[];
  entries: JournalEntry[];
  postings: Posting[];
  debts: Debt[];
  allocations: SettlementAllocation[];
  commitments: SharedCommitment[];
  commitmentSettlements: SharedCommitmentSettlement[];
  savingsGoals: SharedSavingsGoal[];
  simpleTransactions: SimpleTransaction[];
}): {
  updatedEntries: JournalEntry[];
  updatedDebts: Debt[];
  updatedCommitments: SharedCommitment[];
  updatedSavingsGoals: SharedSavingsGoal[];
  updatedSimpleTransactions: SimpleTransaction[];
} {
  const target = params.entries.find((e) => e.id === params.entryId);
  if (!target) {
    throw new DoubleEntryValidationError('Journal entry not found.');
  }
  if (target.isVoided) {
    return {
      updatedEntries: params.entries,
      updatedDebts: params.debts,
      updatedCommitments: params.commitments,
      updatedSavingsGoals: params.savingsGoals,
      updatedSimpleTransactions: params.simpleTransactions,
    };
  }

  const voidedIds = new Set(params.entries.filter((e) => e.isVoided).map((e) => e.id));

  // Guard 1: Debt origin cannot be voided while active settlements or active write-off exist.
  const linkedOriginDebt = params.debts.find((d) => d.originEntryId === target.id);
  if (linkedOriginDebt) {
    const hasActiveSettlement = params.allocations.some(
      (a) => a.debtId === linkedOriginDebt.id && !voidedIds.has(a.settlementEntryId)
    );
    if (hasActiveSettlement) {
      throw new DoubleEntryValidationError(
        'Cannot void a debt-origin entry that has active settlements. Void the settlement entries first.'
      );
    }
    if (linkedOriginDebt.writeOffEntryId && !voidedIds.has(linkedOriginDebt.writeOffEntryId)) {
      throw new DoubleEntryValidationError(
        'Cannot void a debt-origin entry with an active write-off. Void the write-off entry first.'
      );
    }
  }

  // Guard 2: Debt settlement cannot be voided while target debt has an active write-off.
  const targetAllocs = params.allocations.filter((a) => a.settlementEntryId === target.id);
  for (const alloc of targetAllocs) {
    const debt = params.debts.find((d) => d.id === alloc.debtId);
    if (debt?.writeOffEntryId && !voidedIds.has(debt.writeOffEntryId)) {
      throw new DoubleEntryValidationError(
        'Cannot void a settlement while its debt has an active write-off. Void the write-off first.'
      );
    }
  }

  // Guard 3: Standard expense cannot be voided while active refunds reference it.
  const hasActiveRefund = params.entries.some(
    (e) => !e.isVoided && extractRefundOriginEntryId(e) === target.id
  );
  if (hasActiveRefund) {
    throw new DoubleEntryValidationError(
      'Cannot void an expense entry that has active refunds. Void the refund entries first.'
    );
  }

  // Guard 4: Opening-balance adjustment entries must only be changed via opening balance revision.
  if (target.legacySourceTxId?.startsWith('open:')) {
    throw new DoubleEntryValidationError(
      'Opening balance entries cannot be voided directly. Edit the account opening balance instead.'
    );
  }

  const updatedEntries = params.entries.map((e) =>
    e.id === target.id
      ? { ...e, isVoided: true, voidReason: params.reason || 'Voided by user' }
      : e
  );

  // Sync commitments if target was a commitment settlement
  const linkedCmSettlement = params.commitmentSettlements.find((s) => s.entryId === target.id);
  const updatedCommitments = linkedCmSettlement
    ? params.commitments.map((c) => {
        if (c.id !== linkedCmSettlement.commitmentId) return c;
        const remainingSettled = calculateCommitmentSettledCents(
          c.id,
          params.commitmentSettlements,
          updatedEntries
        );
        const nowPaid = remainingSettled >= c.amountCents;
        return {
          ...c,
          isPaid: nowPaid,
          settlementEntryId: nowPaid ? c.settlementEntryId : undefined,
        };
      })
    : params.commitments;

  const updatedDebts = reconcileDebtsV7({
    debts: params.debts,
    entries: updatedEntries,
    allocations: params.allocations,
  });

  const updatedSimpleTransactions = params.simpleTransactions.map((t) =>
    t.journalEntryId === target.id ||
    (target.legacySourceTxId && t.id === target.legacySourceTxId)
      ? { ...t, isSuperseded: true }
      : t
  );

  const updatedSavingsGoals = syncVaultSavingsGoalsV7({
    accounts: params.accounts,
    entries: updatedEntries,
    postings: params.postings,
    savingsGoals: params.savingsGoals,
  });

  return {
    updatedEntries,
    updatedDebts,
    updatedCommitments,
    updatedSavingsGoals,
    updatedSimpleTransactions,
  };
}

export function unvoidJournalEntryGuardedV7(params: {
  entryId: string;
  accounts: Account[];
  entries: JournalEntry[];
  postings: Posting[];
  debts: Debt[];
  allocations: SettlementAllocation[];
  commitments: SharedCommitment[];
  commitmentSettlements: SharedCommitmentSettlement[];
  savingsGoals: SharedSavingsGoal[];
  simpleTransactions: SimpleTransaction[];
}): {
  updatedEntries: JournalEntry[];
  updatedDebts: Debt[];
  updatedCommitments: SharedCommitment[];
  updatedSavingsGoals: SharedSavingsGoal[];
  updatedSimpleTransactions: SimpleTransaction[];
} {
  const target = params.entries.find((e) => e.id === params.entryId);
  if (!target) {
    throw new DoubleEntryValidationError('Journal entry not found.');
  }
  if (!target.isVoided) {
    return {
      updatedEntries: params.entries,
      updatedDebts: params.debts,
      updatedCommitments: params.commitments,
      updatedSavingsGoals: params.savingsGoals,
      updatedSimpleTransactions: params.simpleTransactions,
    };
  }

  const accountById = new Map(params.accounts.map((a) => [a.id, a]));
  const entryPostings = params.postings.filter((p) => p.entryId === target.id);

  // Guard 1: ETB eligibility & no legacy clearing postings
  if (
    entryPostings.some(
      (p) => accountById.get(p.accountId)?.subType === 'legacy_clearing'
    )
  ) {
    throw new DoubleEntryValidationError(
      'Legacy clearing entries cannot be restored in ETB mode.'
    );
  }
  const cls = classifyJournalEntryCurrency({
    entry: target,
    entryPostings,
    accountById,
    debts: params.debts,
    allocations: params.allocations,
    allEntries: params.entries,
    allPostings: params.postings,
    ignoreVoidFlag: true,
  });
  if (cls.status !== 'eligible_etb') {
    throw new DoubleEntryValidationError(
      'Only Verified ETB entries can be restored in first-release ETB mode.'
    );
  }

  // Guard 2: Do not restore an entry that has an active replacement entry.
  const hasActiveReplacement = params.entries.some(
    (e) => !e.isVoided && e.correctedFromEntryId === target.id
  );
  if (hasActiveReplacement) {
    throw new DoubleEntryValidationError(
      'Cannot restore an entry that has an active replacement. Void the replacement entry first.'
    );
  }

  // Guard 3: Opening balance entries must only be changed via reviseAccountOpeningBalanceV7.
  if (target.legacySourceTxId?.startsWith('open:')) {
    throw new DoubleEntryValidationError(
      'Opening balance entries cannot be restored directly. Edit the account opening balance instead.'
    );
  }

  // Guard 4: Write-off entries cannot be unvoided safely without breaking write-off linkage.
  if (target.entryType === 'write_off') {
    throw new DoubleEntryValidationError(
      'Write-off entries cannot be restored directly. Record a new write-off from the debt record if needed.'
    );
  }

  const voidedIds = new Set(params.entries.filter((e) => e.isVoided).map((e) => e.id));

  // Guard 5: If settlement entry, verify target debt origin is active, not written off, and won't over-settle.
  const targetAllocs = params.allocations.filter((a) => a.settlementEntryId === target.id);
  for (const alloc of targetAllocs) {
    const debt = params.debts.find((d) => d.id === alloc.debtId);
    if (!debt) {
      throw new DoubleEntryValidationError(
        'Cannot restore settlement because its debt record no longer exists.'
      );
    }
    const origin = params.entries.find((e) => e.id === debt.originEntryId);
    if (!origin || origin.isVoided || debt.status === 'voided') {
      throw new DoubleEntryValidationError(
        'Cannot restore settlement because the underlying debt origin is voided.'
      );
    }
    if (debt.writeOffEntryId && !voidedIds.has(debt.writeOffEntryId)) {
      throw new DoubleEntryValidationError(
        'Cannot restore settlement while the debt has an active write-off.'
      );
    }
    const currentSettled = params.allocations
      .filter((a) => a.debtId === debt.id && !voidedIds.has(a.settlementEntryId))
      .reduce((sum, a) => sum + a.allocatedCents, 0);
    if (currentSettled + alloc.allocatedCents > debt.principalCents) {
      throw new DoubleEntryValidationError(
        'Cannot restore settlement because total settled principal would exceed the debt principal.'
      );
    }
  }

  // Guard 6: If refund entry, verify original expense is active and remaining refundable covers this refund.
  const refundOriginId = extractRefundOriginEntryId(target);
  if (refundOriginId) {
    const summary = getExpenseRefundSummaryV7({
      originalEntryId: refundOriginId,
      entries: params.entries,
      postings: params.postings,
      accounts: params.accounts,
      debts: params.debts,
      allocations: params.allocations,
    });
    if (!summary.eligible) {
      throw new DoubleEntryValidationError(
        summary.reason ||
          'Cannot restore refund because the original expense is no longer active or eligible.'
      );
    }
    const refundAmount = entryPostings
      .filter(
        (p) =>
          p.direction === 'credit' &&
          (p.accountId === SYSTEM_CONTROL_ACCOUNT_IDS.expense ||
            accountById.get(p.accountId)?.type === 'expense')
      )
      .reduce((sum, p) => sum + p.amountCents, 0);
    if (refundAmount > summary.remainingRefundableCents) {
      throw new DoubleEntryValidationError(
        'Cannot restore refund because total refunded amount would exceed the original expense.'
      );
    }
  }

  // Guard 7: If commitment settlement entry, prevent over-settling the linked commitment.
  const linkedCmSettlementGuard = params.commitmentSettlements.find((s) => s.entryId === target.id);
  if (linkedCmSettlementGuard) {
    const linkedCommitment = params.commitments.find(
      (c) => c.id === linkedCmSettlementGuard.commitmentId
    );
    if (linkedCommitment) {
      const currentSettled = calculateCommitmentSettledCents(
        linkedCommitment.id,
        params.commitmentSettlements,
        params.entries
      );
      if (currentSettled + linkedCmSettlementGuard.amountCents > linkedCommitment.amountCents) {
        throw new DoubleEntryValidationError(
          'Cannot restore commitment installment because total settled amount would exceed the commitment amount.'
        );
      }
    }
  }

  const updatedEntries = params.entries.map((e) =>
    e.id === target.id ? { ...e, isVoided: false, voidReason: undefined } : e
  );

  // Sync commitments if target was a commitment settlement
  const linkedCmSettlement = params.commitmentSettlements.find((s) => s.entryId === target.id);
  const updatedCommitments = linkedCmSettlement
    ? params.commitments.map((c) => {
        if (c.id !== linkedCmSettlement.commitmentId) return c;
        const settled = calculateCommitmentSettledCents(
          c.id,
          params.commitmentSettlements,
          updatedEntries
        );
        const nowPaid = settled >= c.amountCents;
        return {
          ...c,
          isPaid: nowPaid,
          settlementEntryId: nowPaid ? target.id : c.settlementEntryId,
        };
      })
    : params.commitments;

  const updatedDebts = reconcileDebtsV7({
    debts: params.debts,
    entries: updatedEntries,
    allocations: params.allocations,
  });

  const updatedSimpleTransactions = params.simpleTransactions.map((t) =>
    t.journalEntryId === target.id ||
    (target.legacySourceTxId && t.id === target.legacySourceTxId)
      ? { ...t, isSuperseded: false }
      : t
  );

  const updatedSavingsGoals = syncVaultSavingsGoalsV7({
    accounts: params.accounts,
    entries: updatedEntries,
    postings: params.postings,
    savingsGoals: params.savingsGoals,
  });

  return {
    updatedEntries,
    updatedDebts,
    updatedCommitments,
    updatedSavingsGoals,
    updatedSimpleTransactions,
  };
}

export function correctJournalEntryV7(params: {
  originalEntryId: string;
  replacementEntry: JournalEntry;
  replacementPostings: Posting[];
  correctionReason?: string;
  accounts: Account[];
  entries: JournalEntry[];
  postings: Posting[];
  debts: Debt[];
  allocations: SettlementAllocation[];
  commitments: SharedCommitment[];
  commitmentSettlements?: SharedCommitmentSettlement[];
  savingsGoals: SharedSavingsGoal[];
  simpleTransactions: SimpleTransaction[];
  replacementSimpleTx?: SimpleTransaction;
}): {
  updatedEntries: JournalEntry[];
  updatedPostings: Posting[];
  updatedDebts: Debt[];
  updatedCommitments: SharedCommitment[];
  updatedSavingsGoals: SharedSavingsGoal[];
  updatedSimpleTransactions: SimpleTransaction[];
} {
  const original = params.entries.find((e) => e.id === params.originalEntryId);
  if (!original) {
    throw new DoubleEntryValidationError('Original entry to replace was not found.');
  }

  const check = canCorrectJournalEntryV7({
    entry: original,
    entries: params.entries,
    postings: params.postings,
    accounts: params.accounts,
    debts: params.debts,
    allocations: params.allocations,
    commitmentSettlements: params.commitmentSettlements,
  });
  if (!check.ok) {
    throw new DoubleEntryValidationError(check.error || 'Entry cannot be replaced.');
  }
  if (!isCorrectableEntryTypeV7(params.replacementEntry.entryType)) {
    throw new DoubleEntryValidationError(
      `Replacement entry type "${params.replacementEntry.entryType}" is not supported during correction.`
    );
  }
  if (isRefundEntry(params.replacementEntry)) {
    throw new DoubleEntryValidationError(
      'Cannot convert an entry into a refund via correction.'
    );
  }

  const accountById = new Map(params.accounts.map((a) => [a.id, a]));
  const nonSystemAccountIds = Array.from(
    new Set(
      params.replacementPostings
        .map((p) => p.accountId)
        .filter((id) => !accountById.get(id)?.isSystem)
    )
  );
  if (nonSystemAccountIds.length === 0) {
    throw new DoubleEntryValidationError(
      'Replacement entry must include at least one active Verified ETB account.'
    );
  }
  assertEtbPostingAccounts({
    accounts: params.accounts,
    accountIds: nonSystemAccountIds,
    roleLabels: nonSystemAccountIds.map(() => 'Posting account'),
  });
  validateBalancedEntry(params.replacementPostings);

  const replacementWithLink: JournalEntry = {
    ...params.replacementEntry,
    correctedFromEntryId: original.id,
    isVoided: false,
  };

  const updatedEntries = [
    replacementWithLink,
    ...params.entries.map((e) =>
      e.id === original.id
        ? {
            ...e,
            isVoided: true,
            voidReason: params.correctionReason || `Replaced by ${replacementWithLink.id}`,
          }
        : e
    ),
  ];
  const updatedPostings = [...params.replacementPostings, ...params.postings];

  const updatedSimpleTransactionsBase = params.simpleTransactions.map((t) =>
    t.journalEntryId === original.id ||
    (original.legacySourceTxId && t.id === original.legacySourceTxId)
      ? { ...t, isSuperseded: true }
      : t
  );
  const updatedSimpleTransactions = params.replacementSimpleTx
    ? [params.replacementSimpleTx, ...updatedSimpleTransactionsBase]
    : updatedSimpleTransactionsBase;

  const updatedDebts = reconcileDebtsV7({
    debts: params.debts,
    entries: updatedEntries,
    allocations: params.allocations,
  });

  const updatedSavingsGoals = syncVaultSavingsGoalsV7({
    accounts: params.accounts,
    entries: updatedEntries,
    postings: updatedPostings,
    savingsGoals: params.savingsGoals,
  });

  return {
    updatedEntries,
    updatedPostings,
    updatedDebts,
    updatedCommitments: params.commitments,
    updatedSavingsGoals,
    updatedSimpleTransactions,
  };
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

/**
 * Resolves a candidate expense category ID against active non-archived expense categories
 * (or canonical defaults when none exist), supporting legacy alias matching non-destructively.
 */
export function resolveActiveExpenseCategoryIdV7(
  categories: TransactionCategory[],
  candidateCategoryId?: string
): string {
  const effectiveCategories =
    categories.length > 0
      ? categories
      : [...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES, ...FOUNDATION_DEFAULT_INCOME_CATEGORIES];
  const activeExpenses = effectiveCategories.filter(
    (c) => c.type === 'expense' && !c.isArchived
  );

  if (candidateCategoryId) {
    const matched = findCategoryByIdOrAlias(activeExpenses, candidateCategoryId);
    if (matched) return matched.id;
  }

  const canonicalOther =
    activeExpenses.find((c) => c.id === CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID) ||
    activeExpenses.find(
      (c) => resolveCanonicalCategoryId(c.id) === CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID
    );
  if (canonicalOther) return canonicalOther.id;

  const flaggedDefault = activeExpenses.find((c) => c.isDefault);
  if (flaggedDefault) return flaggedDefault.id;

  return activeExpenses[0]?.id || CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID;
}

export interface BuildQuickCaptureExpenseResult {
  ok: boolean;
  error?: string;
  rejectedCurrency?: string;
  entry?: JournalEntry;
  postings?: Posting[];
  simpleTransaction?: SimpleTransaction;
  accountsWithControls?: Account[];
  targetAccount?: Account;
  resolvedCategoryId?: string;
  resolvedCategoryName?: string;
  parsed?: QuickCaptureParsedExpense;
}

/**
 * Pure Quick Capture expense builder shared by Web App Quick Capture and unit tests.
 * Uses live categories (falling back to canonical defaults), builds balanced double-entry postings,
 * keeps SimpleTransaction and debit Posting categoryId identical, and marks isSuperseded: false.
 */
export function buildQuickCaptureExpenseEntryV7(params: {
  rawText: string;
  accountHint?: string;
  accounts: Account[];
  categories: TransactionCategory[];
  occurrenceDateIso?: string;
  nowIso?: string;
  entryId?: string;
  txId?: string;
}): BuildQuickCaptureExpenseResult {
  const text = params.rawText.trim();
  if (!text) {
    return { ok: false, error: 'Please enter something to capture.' };
  }

  const liquidEtbAccounts = params.accounts.filter(
    (a) =>
      isActiveVerifiedEtbAccount(a) &&
      a.type === 'asset' &&
      a.subType !== 'savings_vault' &&
      a.subType !== 'receivable'
  );
  const fallbackEtbAccounts = params.accounts.filter((a) => isActiveVerifiedEtbAccount(a));
  const candidateAccounts = liquidEtbAccounts.length > 0 ? liquidEtbAccounts : fallbackEtbAccounts;

  const hint = (params.accountHint || '').trim().toLowerCase();
  const matchedAccount =
    (hint ? candidateAccounts.find((a) => a.name.toLowerCase().includes(hint)) : undefined) ||
    candidateAccounts[0];

  if (!matchedAccount) {
    return {
      ok: false,
      error:
        'No active Verified ETB account is available. Add or activate an ETB account in Finance before recording expenses.',
    };
  }

  const effectiveCategories =
    params.categories.length > 0
      ? params.categories
      : [...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES, ...FOUNDATION_DEFAULT_INCOME_CATEGORIES];

  const parsed = parseQuickCaptureExpense(
    text,
    matchedAccount.id,
    params.accounts,
    effectiveCategories
  );
  if (parsed.rejectedCurrency) {
    return {
      ok: false,
      rejectedCurrency: parsed.rejectedCurrency,
      parsed,
      error:
        parsed.error ||
        `Only ETB amounts are supported in Quick Capture (detected ${parsed.rejectedCurrency}).`,
    };
  }
  if (!Number.isInteger(parsed.amountCents) || parsed.amountCents <= 0) {
    return {
      ok: false,
      parsed,
      error: 'Enter a valid expense amount greater than 0.',
    };
  }

  const targetAccount =
    candidateAccounts.find((a) => a.id === parsed.assetAccountId) || matchedAccount;

  assertEtbPostingAccounts({
    accounts: params.accounts,
    accountIds: [targetAccount.id],
    roleLabels: ['Posting account'],
  });

  const resolvedCategoryId = resolveActiveExpenseCategoryIdV7(
    effectiveCategories,
    parsed.categoryId
  );
  const resolvedCategoryName =
    resolveCategoryDisplayName(effectiveCategories, resolvedCategoryId) || parsed.categoryName;

  const occurrenceDateIso = params.occurrenceDateIso || CalendarDate.today().toIsoString();
  const nowIso = params.nowIso || EthiopiaClock.nowUtc().toISOString();
  const entryId = params.entryId || `entry-qc-${Date.now()}`;
  const txId = params.txId || `tx-qc-${Date.now()}`;
  const description = (parsed.description || text).trim();

  const accountsWithControls = ensureSystemControlAccounts(params.accounts);
  const { entry, postings } = buildDirectExpense({
    id: entryId,
    assetAccountId: targetAccount.id,
    expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
    categoryId: resolvedCategoryId,
    amountCents: parsed.amountCents,
    occurrenceDate: occurrenceDateIso,
    movementDate: occurrenceDateIso,
    description,
    note: 'Quick capture',
  });
  entry.legacySourceTxId = txId;
  entry.createdAt = nowIso;

  validateBalancedEntry(postings);

  const simpleTransaction: SimpleTransaction = {
    id: txId,
    type: 'expense',
    amountCents: parsed.amountCents,
    accountId: targetAccount.id,
    categoryId: resolvedCategoryId,
    description,
    transactionDate: occurrenceDateIso,
    createdAt: nowIso,
    updatedAt: nowIso,
    journalEntryId: entry.id,
    isSuperseded: false,
  };

  return {
    ok: true,
    entry,
    postings,
    simpleTransaction,
    accountsWithControls,
    targetAccount,
    resolvedCategoryId,
    resolvedCategoryName,
    parsed,
  };
}

/**
 * Upserts a monthly category budget keyed uniquely by (categoryId, monthIso) so saving
 * a category budget in one month never overwrites budgets from another month.
 */
export function upsertMonthlyBudgetV7(params: {
  budgets: SharedBudget[];
  categoryId: string;
  monthIso: string;
  limitCents: number;
  rolloverEnabled: boolean;
  nowIso?: string;
  budgetId?: string;
}): {
  ok: boolean;
  error?: string;
  budgets: SharedBudget[];
  savedBudget?: SharedBudget;
  updatedExisting?: boolean;
} {
  const categoryId = params.categoryId.trim();
  const monthIso = params.monthIso.trim();
  if (!categoryId) {
    return { ok: false, error: 'Category is required for a monthly budget.', budgets: params.budgets };
  }
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(monthIso)) {
    return {
      ok: false,
      error: `Invalid budget month "${monthIso}" (expected YYYY-MM).`,
      budgets: params.budgets,
    };
  }
  if (!Number.isInteger(params.limitCents) || params.limitCents <= 0) {
    return {
      ok: false,
      error: 'Budget limit must be a positive integer in cents.',
      budgets: params.budgets,
    };
  }

  const nowIso = params.nowIso || EthiopiaClock.nowUtc().toISOString();
  const existingIdx = (() => {
    const exact = params.budgets.findIndex(
      (b) => b.monthIso === monthIso && b.categoryId === categoryId
    );
    if (exact >= 0) return exact;
    return params.budgets.findIndex(
      (b) => b.monthIso === monthIso && categoryIdsMatchOrAlias(b.categoryId, categoryId)
    );
  })();

  if (existingIdx >= 0) {
    const existing = params.budgets[existingIdx];
    const savedBudget: SharedBudget = {
      ...existing,
      categoryId,
      monthIso,
      limitCents: params.limitCents,
      rolloverEnabled: params.rolloverEnabled,
      updatedAt: nowIso,
    };
    const nextBudgets = params.budgets.map((b, idx) => (idx === existingIdx ? savedBudget : b));
    return {
      ok: true,
      budgets: nextBudgets,
      savedBudget,
      updatedExisting: true,
    };
  }

  const savedBudget: SharedBudget = {
    id: params.budgetId || `bud-${Date.now()}`,
    categoryId,
    monthIso,
    limitCents: params.limitCents,
    rolloverEnabled: params.rolloverEnabled,
    createdAt: nowIso,
    updatedAt: nowIso,
  };
  return {
    ok: true,
    budgets: [savedBudget, ...params.budgets],
    savedBudget,
    updatedExisting: false,
  };
}

// ============================================================================
// Finance Stage F4: Reporting, Period Comparisons & Canonical Spend Rollup
// ============================================================================

export type ReportPeriodMode =
  | 'thisMonth'
  | 'ethiopianMonth'
  | 'last30Days'
  | 'thisYear'
  | 'custom';

export interface ResolvedReportPeriod {
  mode: ReportPeriodMode;
  currentStart: string;
  currentEnd: string;
  previousStart: string;
  previousEnd: string;
  label: string;
  baselineLabel: string;
  daysInCurrent: number;
  daysInPrevious: number;
}

export interface MetricDeltaV7 {
  currentCents: number;
  previousCents: number;
  deltaCents: number;
  percentageChange: number | null;
  percentageDisplay: string;
  isPositiveOutcome: boolean | null;
}

export interface PeriodComparisonReportV7 {
  period: ResolvedReportPeriod;
  currentOccurrence: OccurrenceReportSummary;
  previousOccurrence: OccurrenceReportSummary;
  currentCashFlow: CashFlowReportSummary;
  previousCashFlow: CashFlowReportSummary;
  occurrenceIncome: MetricDeltaV7;
  occurrenceExpense: MetricDeltaV7;
  occurrenceNet: MetricDeltaV7;
  cashInflow: MetricDeltaV7;
  cashOutflow: MetricDeltaV7;
  cashNet: MetricDeltaV7;
}

export interface CategorySpendRowV7 {
  categoryId: string;
  categoryName: string;
  parentId?: string;
  directCents: number;
  rollupCents: number;
  sharePercent: number;
  exactShareRatio: number;
  isArchived: boolean;
  isSyntheticControl?: boolean;
  children: CategorySpendRowV7[];
}

export interface CanonicalCategorySpendReportV7 {
  startDate: string;
  endDate: string;
  totalExpenseCents: number;
  directSpendByCategoryId: Record<string, number>;
  rollupSpendByCategoryId: Record<string, number>;
  rows: CategorySpendRowV7[];
}

export interface AccountBalanceReportItemV7 {
  accountId: string;
  name: string;
  type: Account['type'];
  subType: SharedAccountSubType;
  currencyCode: string;
  balanceCents: number;
  owedCents: number;
  prepaidCents: number;
  isArchived: boolean;
  currencyTier: CurrencyValidationTier;
}

export interface AccountBalancesReportV7 {
  liquidAccounts: AccountBalanceReportItemV7[];
  vaultAccounts: AccountBalanceReportItemV7[];
  creditCardAccounts: AccountBalanceReportItemV7[];
  nonEtbReviewAccounts: AccountBalanceReportItemV7[];
  archivedCount: number;
  liquidTotalCents: number;
  vaultTotalCents: number;
  creditCardOwedTotalCents: number;
  prepaidCardCreditTotalCents: number;
}

export interface SavingsGoalReportItemV7 {
  goalId: string;
  title: string;
  targetCents: number;
  allocatedCents: number;
  remainingCents: number;
  percentComplete: number;
  targetDate?: string;
  status: NonNullable<SharedSavingsGoal['status']>;
  linkedAccountId?: string;
  linkedAccountName?: string;
  isVaultLinked: boolean;
  isExcludedNonEtbVault: boolean;
}

export interface SavingsVaultsReportV7 {
  vaults: AccountBalanceReportItemV7[];
  goals: SavingsGoalReportItemV7[];
  totalVaultBalanceCents: number;
  totalGoalTargetCents: number;
  totalGoalAllocatedCents: number;
}

export interface MonthlyBudgetReportItemV7 {
  budgetId: string;
  categoryId: string;
  categoryName: string;
  monthIso: string;
  limitCents: number;
  spentCents: number;
  remainingCents: number;
  percentUsed: number;
  isOverBudget: boolean;
  rolloverEnabled: boolean;
}

export interface MonthlyBudgetProgressReportV7 {
  monthIso: string;
  totalLimitCents: number;
  totalSpentCents: number;
  items: MonthlyBudgetReportItemV7[];
}

export interface AlignedBalanceSheetReportV7 {
  planningPeriodEndIso: string;
  liquidCashCents: number;
  vaultSavingsCents: number;
  receivablesCents: number;
  prepaidCardCreditCents: number;
  shortTermCreditOwedCents: number;
  activePayablesCents: number;
  duePayablesCents: number;
  netFinancialPositionCents: number;
}

export function resolveReportPeriodWithComparisonV7(params: {
  mode: ReportPeriodMode;
  todayIso?: string;
  ethYear?: number;
  ethMonth?: number;
  customStartIso?: string;
  customEndIso?: string;
}): ResolvedReportPeriod {
  const today = CalendarDate.tryParse(params.todayIso) || CalendarDate.today();

  if (params.mode === 'thisMonth') {
    const currStart = today.startOfGregorianMonth;
    const currEnd = today.endOfGregorianMonth;
    const prevRef = today.previousGregorianMonth();
    const prevStart = prevRef.startOfGregorianMonth;
    const prevEnd = prevRef.endOfGregorianMonth;
    return {
      mode: 'thisMonth',
      currentStart: currStart.toIsoString(),
      currentEnd: currEnd.toIsoString(),
      previousStart: prevStart.toIsoString(),
      previousEnd: prevEnd.toIsoString(),
      label: `${today.gregorianFullMonthName} ${today.year}`,
      baselineLabel: `${prevRef.gregorianFullMonthName} ${prevRef.year}`,
      daysInCurrent: currEnd.differenceInDays(currStart) + 1,
      daysInPrevious: prevEnd.differenceInDays(prevStart) + 1,
    };
  }

  if (params.mode === 'ethiopianMonth') {
    const ethToday = today.toEthiopian();
    const y = params.ethYear ?? ethToday.year;
    const m = Math.min(13, Math.max(1, params.ethMonth ?? ethToday.month));
    const ethStart = new EthiopianDate(y, m, 1);
    const ethEnd = ethStart.endOfMonth;
    const prevEthStart = ethStart.previousMonth().startOfMonth;
    const prevEthEnd = prevEthStart.endOfMonth;
    const currStartCal = ethStart.toCalendarDate();
    const currEndCal = ethEnd.toCalendarDate();
    const prevStartCal = prevEthStart.toCalendarDate();
    const prevEndCal = prevEthEnd.toCalendarDate();
    return {
      mode: 'ethiopianMonth',
      currentStart: currStartCal.toIsoString(),
      currentEnd: currEndCal.toIsoString(),
      previousStart: prevStartCal.toIsoString(),
      previousEnd: prevEndCal.toIsoString(),
      label: `${ethStart.englishMonthName} (${ethStart.amharicMonthName}) ${y} E.C.`,
      baselineLabel: `${prevEthStart.englishMonthName} ${prevEthStart.year} E.C.`,
      daysInCurrent: ethStart.daysInMonth,
      daysInPrevious: prevEthStart.daysInMonth,
    };
  }

  if (params.mode === 'last30Days') {
    const currStart = today.subtractDays(29);
    const currEnd = today;
    const prevEnd = currStart.subtractDays(1);
    const prevStart = prevEnd.subtractDays(29);
    return {
      mode: 'last30Days',
      currentStart: currStart.toIsoString(),
      currentEnd: currEnd.toIsoString(),
      previousStart: prevStart.toIsoString(),
      previousEnd: prevEnd.toIsoString(),
      label: `Last 30 Days (${currStart.toIsoString()} - ${currEnd.toIsoString()})`,
      baselineLabel: `Prior 30 Days (${prevStart.toIsoString()} - ${prevEnd.toIsoString()})`,
      daysInCurrent: 30,
      daysInPrevious: 30,
    };
  }

  if (params.mode === 'thisYear') {
    const currStart = new CalendarDate(today.year, 1, 1);
    const currEnd = new CalendarDate(today.year, 12, 31);
    const prevStart = new CalendarDate(today.year - 1, 1, 1);
    const prevEnd = new CalendarDate(today.year - 1, 12, 31);
    return {
      mode: 'thisYear',
      currentStart: currStart.toIsoString(),
      currentEnd: currEnd.toIsoString(),
      previousStart: prevStart.toIsoString(),
      previousEnd: prevEnd.toIsoString(),
      label: `Gregorian Year ${today.year}`,
      baselineLabel: `Gregorian Year ${today.year - 1}`,
      daysInCurrent: currEnd.differenceInDays(currStart) + 1,
      daysInPrevious: prevEnd.differenceInDays(prevStart) + 1,
    };
  }

  const parsedStart = CalendarDate.tryParse(params.customStartIso) || today.subtractDays(29);
  const parsedEnd = CalendarDate.tryParse(params.customEndIso) || today;
  const startCal = parsedStart.isAfter(parsedEnd) ? parsedEnd : parsedStart;
  const endCal = parsedStart.isAfter(parsedEnd) ? parsedStart : parsedEnd;
  const nDays = endCal.differenceInDays(startCal) + 1;
  const prevEnd = startCal.subtractDays(1);
  const prevStart = prevEnd.subtractDays(nDays - 1);

  return {
    mode: 'custom',
    currentStart: startCal.toIsoString(),
    currentEnd: endCal.toIsoString(),
    previousStart: prevStart.toIsoString(),
    previousEnd: prevEnd.toIsoString(),
    label: `${startCal.toIsoString()} to ${endCal.toIsoString()}`,
    baselineLabel: `Prior ${nDays}d (${prevStart.toIsoString()} - ${prevEnd.toIsoString()})`,
    daysInCurrent: nDays,
    daysInPrevious: nDays,
  };
}

function buildMetricDelta(
  previousCents: number,
  currentCents: number,
  higherIsBetter: boolean
): MetricDeltaV7 {
  const deltaCents = currentCents - previousCents;
  const pct = calculateSafePercentageChange(previousCents, currentCents);
  let isPositiveOutcome: boolean | null = null;
  if (deltaCents !== 0) {
    isPositiveOutcome = higherIsBetter ? deltaCents > 0 : deltaCents < 0;
  }
  return {
    currentCents,
    previousCents,
    deltaCents,
    percentageChange: pct.percentageChange,
    percentageDisplay: pct.percentageDisplay,
    isPositiveOutcome,
  };
}

export function calculatePeriodComparisonReportV7(params: {
  period: ResolvedReportPeriod;
  accounts: Account[];
  categories: TransactionCategory[];
  entries: JournalEntry[];
  postings: Posting[];
  debts?: Debt[];
  allocations?: SettlementAllocation[];
}): PeriodComparisonReportV7 {
  const currentOccurrence = generateOccurrenceReport({
    entries: params.entries,
    postings: params.postings,
    accounts: params.accounts,
    categories: params.categories,
    debts: params.debts,
    allocations: params.allocations,
    startDate: params.period.currentStart,
    endDate: params.period.currentEnd,
  });
  const previousOccurrence = generateOccurrenceReport({
    entries: params.entries,
    postings: params.postings,
    accounts: params.accounts,
    categories: params.categories,
    debts: params.debts,
    allocations: params.allocations,
    startDate: params.period.previousStart,
    endDate: params.period.previousEnd,
  });
  const currentCashFlow = generateCashFlowReport({
    entries: params.entries,
    postings: params.postings,
    accounts: params.accounts,
    debts: params.debts,
    allocations: params.allocations,
    startDate: params.period.currentStart,
    endDate: params.period.currentEnd,
  });
  const previousCashFlow = generateCashFlowReport({
    entries: params.entries,
    postings: params.postings,
    accounts: params.accounts,
    debts: params.debts,
    allocations: params.allocations,
    startDate: params.period.previousStart,
    endDate: params.period.previousEnd,
  });

  return {
    period: params.period,
    currentOccurrence,
    previousOccurrence,
    currentCashFlow,
    previousCashFlow,
    occurrenceIncome: buildMetricDelta(
      previousOccurrence.totalIncomeCents,
      currentOccurrence.totalIncomeCents,
      true
    ),
    occurrenceExpense: buildMetricDelta(
      previousOccurrence.totalExpenseCents,
      currentOccurrence.totalExpenseCents,
      false
    ),
    occurrenceNet: buildMetricDelta(
      previousOccurrence.netSavingsCents,
      currentOccurrence.netSavingsCents,
      true
    ),
    cashInflow: buildMetricDelta(
      previousCashFlow.totalCashInflowCents,
      currentCashFlow.totalCashInflowCents,
      true
    ),
    cashOutflow: buildMetricDelta(
      previousCashFlow.totalCashOutflowCents,
      currentCashFlow.totalCashOutflowCents,
      false
    ),
    cashNet: buildMetricDelta(
      previousCashFlow.netCashFlowCents,
      currentCashFlow.netCashFlowCents,
      true
    ),
  };
}

export function calculateCanonicalCategorySpendV7(params: {
  entries: JournalEntry[];
  postings: Posting[];
  accounts: Account[];
  categories: TransactionCategory[];
  debts?: Debt[];
  allocations?: SettlementAllocation[];
  startDate: string;
  endDate: string;
}): CanonicalCategorySpendReportV7 {
  const accountMap = new Map(params.accounts.map((a) => [a.id, a]));
  const entryMap = new Map(params.entries.map((e) => [e.id, e]));
  const classifications = classifyAllJournalEntries({
    accounts: params.accounts,
    entries: params.entries,
    postings: params.postings,
    debts: params.debts,
    allocations: params.allocations,
  });

  const directSpend: Record<string, number> = {};
  const categoryMeta = new Map<string, TransactionCategory>();
  const registerCategory = (c: TransactionCategory) => {
    categoryMeta.set(c.id, c);
  };
  for (const c of FOUNDATIONAL_CATEGORIES_WITH_DEFAULTS(params.categories)) {
    registerCategory(c);
  }

  for (const p of params.postings) {
    const entry = entryMap.get(p.entryId);
    if (!entry || entry.isVoided) continue;
    if (!(classifications.get(entry.id)?.isEligibleEtb ?? false)) continue;
    if (entry.occurrenceDate < params.startDate || entry.occurrenceDate > params.endDate) {
      continue;
    }
    const acc = accountMap.get(p.accountId);
    if (!acc || acc.type !== 'expense') continue;

    const netExpense = p.direction === 'debit' ? p.amountCents : -p.amountCents;
    const rawCatId = p.categoryId || CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID;
    const matched = findCategoryByIdOrAlias(params.categories, rawCatId);
    const bucketId = matched ? matched.id : resolveCanonicalCategoryId(rawCatId);
    directSpend[bucketId] = (directSpend[bucketId] || 0) + netExpense;
  }

  // Non-double-counted total expense equals the sum of all direct postings across buckets.
  const totalExpenseCents = Object.values(directSpend).reduce((sum, v) => sum + v, 0);

  // Build parent -> resolved canonical parent mapping with cycle safety
  const resolveParentCanonicalId = (catId: string): string | undefined => {
    const cat = categoryMeta.get(catId) || findCategoryByIdOrAlias(params.categories, catId);
    if (!cat?.parentId) return undefined;
    const matchedParent = findCategoryByIdOrAlias(params.categories, cat.parentId);
    return matchedParent ? matchedParent.id : resolveCanonicalCategoryId(cat.parentId);
  };

  const rollupSpend: Record<string, number> = { ...directSpend };
  for (const [catId, directAmount] of Object.entries(directSpend)) {
    if (directAmount === 0) continue;
    const visited = new Set<string>([catId]);
    let currParentId = resolveParentCanonicalId(catId);
    while (currParentId && !visited.has(currParentId)) {
      visited.add(currParentId);
      rollupSpend[currParentId] = (rollupSpend[currParentId] || 0) + directAmount;
      currParentId = resolveParentCanonicalId(currParentId);
    }
  }

  // Build hierarchical display rows (only categories with rollup > 0 or children > 0)
  const childrenByParent = new Map<string, string[]>();
  const allBucketIds = new Set<string>([
    ...Object.keys(directSpend),
    ...Object.keys(rollupSpend),
  ]);

  for (const id of allBucketIds) {
    if ((rollupSpend[id] || 0) <= 0 && (directSpend[id] || 0) <= 0) continue;
    const parentId = resolveParentCanonicalId(id);
    if (parentId && allBucketIds.has(parentId) && parentId !== id) {
      const list = childrenByParent.get(parentId) || [];
      list.push(id);
      childrenByParent.set(parentId, list);
    }
  }

  const denominator = Math.max(0, totalExpenseCents);
  const buildRow = (id: string, depth: number, seen: Set<string>): CategorySpendRowV7 => {
    const cat = categoryMeta.get(id) || findCategoryByIdOrAlias(params.categories, id);
    const parentId = resolveParentCanonicalId(id);
    const direct = directSpend[id] || 0;
    const rollup = rollupSpend[id] || direct;
    const ratio = denominator > 0 ? Math.max(0, rollup / denominator) : 0;
    const childIds = !seen.has(id) && depth < 4 ? childrenByParent.get(id) || [] : [];
    const nextSeen = new Set(seen);
    nextSeen.add(id);
    const children = childIds
      .map((cid) => buildRow(cid, depth + 1, nextSeen))
      .filter((c) => c.rollupCents > 0)
      .sort((a, b) => b.rollupCents - a.rollupCents);
    return {
      categoryId: id,
      categoryName: cat?.name || resolveCategoryDisplayName(params.categories, id),
      ...(parentId ? { parentId } : {}),
      directCents: direct,
      rollupCents: rollup,
      sharePercent: denominator > 0 ? Math.round(ratio * 100) : 0,
      exactShareRatio: ratio,
      isArchived: Boolean(cat?.isArchived),
      children,
    };
  };

  const topRows: CategorySpendRowV7[] = [];
  for (const id of allBucketIds) {
    const rollup = rollupSpend[id] || 0;
    if (rollup <= 0) continue;
    const parentId = resolveParentCanonicalId(id);
    // Emit as top-level if no parent or parent is missing/cyclic
    if (!parentId || parentId === id || !allBucketIds.has(parentId) || (rollupSpend[parentId] || 0) <= 0) {
      topRows.push(buildRow(id, 0, new Set<string>()));
    }
  }
  topRows.sort((a, b) => b.rollupCents - a.rollupCents);

  return {
    startDate: params.startDate,
    endDate: params.endDate,
    totalExpenseCents,
    directSpendByCategoryId: directSpend,
    rollupSpendByCategoryId: rollupSpend,
    rows: topRows,
  };
}

function FOUNDATIONAL_CATEGORIES_WITH_DEFAULTS(
  categories: TransactionCategory[]
): TransactionCategory[] {
  const byId = new Map<string, TransactionCategory>();
  for (const c of [
    ...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
    ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
  ]) {
    byId.set(c.id, c);
  }
  for (const c of categories) {
    byId.set(c.id, c);
  }
  return Array.from(byId.values());
}

export function getCanonicalBudgetSpentCentsV7(
  spendReport: CanonicalCategorySpendReportV7,
  budgetCategoryId: string,
  categories: TransactionCategory[]
): number {
  const matched = findCategoryByIdOrAlias(categories, budgetCategoryId);
  const resolvedId = matched ? matched.id : resolveCanonicalCategoryId(budgetCategoryId);
  return (
    spendReport.rollupSpendByCategoryId[resolvedId] ??
    spendReport.directSpendByCategoryId[resolvedId] ??
    0
  );
}

export function buildAccountBalancesReportV7(params: {
  accounts: Account[];
  entries: JournalEntry[];
  postings: Posting[];
}): AccountBalancesReportV7 {
  const liquidAccounts: AccountBalanceReportItemV7[] = [];
  const vaultAccounts: AccountBalanceReportItemV7[] = [];
  const creditCardAccounts: AccountBalanceReportItemV7[] = [];
  const nonEtbReviewAccounts: AccountBalanceReportItemV7[] = [];
  let archivedCount = 0;

  for (const acc of params.accounts) {
    if (acc.isSystem) continue;
    if (acc.isArchived) {
      archivedCount += 1;
      continue;
    }
    const subType = getAccountSubType(acc);
    const tier = classifyCurrencyCode(acc.currencyCode);
    const bal = calculateV7AccountBalance(acc, params.postings, params.entries);
    const item: AccountBalanceReportItemV7 = {
      accountId: acc.id,
      name: acc.name,
      type: acc.type,
      subType,
      currencyCode: normalizeCurrencyCode(acc.currencyCode) || 'UNVERIFIED',
      balanceCents: bal,
      owedCents: acc.type === 'liability' && bal > 0 ? bal : 0,
      prepaidCents: acc.type === 'liability' && bal < 0 ? -bal : 0,
      isArchived: Boolean(acc.isArchived),
      currencyTier: tier,
    };

    if (tier !== 'verified_etb') {
      nonEtbReviewAccounts.push(item);
      continue;
    }

    if (acc.type === 'asset') {
      if (subType === 'savings_vault') {
        vaultAccounts.push(item);
      } else if (subType !== 'receivable' && !acc.name.toLowerCase().includes('receivable')) {
        liquidAccounts.push(item);
      }
    } else if (acc.type === 'liability' && subType === 'credit_card') {
      creditCardAccounts.push(item);
    }
  }

  return {
    liquidAccounts,
    vaultAccounts,
    creditCardAccounts,
    nonEtbReviewAccounts,
    archivedCount,
    liquidTotalCents: liquidAccounts.reduce((s, a) => s + a.balanceCents, 0),
    vaultTotalCents: vaultAccounts.reduce((s, a) => s + a.balanceCents, 0),
    creditCardOwedTotalCents: creditCardAccounts.reduce((s, a) => s + a.owedCents, 0),
    prepaidCardCreditTotalCents: creditCardAccounts.reduce((s, a) => s + a.prepaidCents, 0),
  };
}

export function buildSavingsVaultsAndGoalsReportV7(params: {
  accounts: Account[];
  entries: JournalEntry[];
  postings: Posting[];
  savingsGoals: SharedSavingsGoal[];
}): SavingsVaultsReportV7 {
  const accountById = new Map(params.accounts.map((a) => [a.id, a]));
  const balances = buildAccountBalancesReportV7({
    accounts: params.accounts,
    entries: params.entries,
    postings: params.postings,
  });

  const goals: SavingsGoalReportItemV7[] = params.savingsGoals.map((g) => {
    const linkedAcc = g.linkedAccountId ? accountById.get(g.linkedAccountId) : undefined;
    const isVaultLinked = Boolean(g.linkedAccountId);
    const isExcludedNonEtbVault =
      isVaultLinked &&
      (!linkedAcc ||
        !isActiveVerifiedEtbAccount(linkedAcc) ||
        linkedAcc.subType !== 'savings_vault');
    const allocatedCents = getSavingsGoalEffectiveBalanceV7({
      goal: g,
      accounts: params.accounts,
      entries: params.entries,
      postings: params.postings,
    });
    const remainingCents = Math.max(0, g.targetCents - allocatedCents);
    const percentComplete =
      g.targetCents > 0 ? Math.min(100, Math.round((allocatedCents / g.targetCents) * 100)) : 0;
    return {
      goalId: g.id,
      title: g.title,
      targetCents: g.targetCents,
      allocatedCents,
      remainingCents,
      percentComplete,
      ...(g.targetDate ? { targetDate: g.targetDate } : {}),
      status: g.status || 'active',
      ...(g.linkedAccountId ? { linkedAccountId: g.linkedAccountId } : {}),
      ...(linkedAcc ? { linkedAccountName: linkedAcc.name } : {}),
      isVaultLinked,
      isExcludedNonEtbVault,
    };
  });

  const activeNonExcluded = goals.filter(
    (g) => g.status !== 'archived' && !g.isExcludedNonEtbVault
  );

  return {
    vaults: balances.vaultAccounts,
    goals,
    totalVaultBalanceCents: balances.vaultTotalCents,
    totalGoalTargetCents: activeNonExcluded.reduce((s, g) => s + g.targetCents, 0),
    totalGoalAllocatedCents: activeNonExcluded.reduce((s, g) => s + g.allocatedCents, 0),
  };
}

export function resolveActiveReportMonthIsoV7(params: {
  mode: ReportPeriodMode;
  startDateIso: string;
  endDateIso: string;
  todayIso?: string;
}): string {
  const todayIso = params.todayIso || CalendarDate.today().toIsoString();
  if (
    params.mode === 'thisMonth' ||
    (params.startDateIso.length >= 7 &&
      params.endDateIso.length >= 7 &&
      params.startDateIso.slice(0, 7) === params.endDateIso.slice(0, 7))
  ) {
    return params.startDateIso.slice(0, 7);
  }
  return todayIso.slice(0, 7);
}

export function buildMonthlyBudgetProgressReportV7(params: {
  budgets: SharedBudget[];
  categories: TransactionCategory[];
  entries: JournalEntry[];
  postings: Posting[];
  accounts: Account[];
  debts?: Debt[];
  allocations?: SettlementAllocation[];
  monthIso: string;
}): MonthlyBudgetProgressReportV7 {
  const monthMatch = /^(\d{4})-(\d{2})$/.exec(params.monthIso.trim());
  const y = monthMatch ? parseInt(monthMatch[1], 10) : CalendarDate.today().year;
  const m = monthMatch ? parseInt(monthMatch[2], 10) : CalendarDate.today().month;
  const bounds = CalendarDate.monthBounds('gregorian', y, Math.min(12, Math.max(1, m)));

  const spendReport = calculateCanonicalCategorySpendV7({
    entries: params.entries,
    postings: params.postings,
    accounts: params.accounts,
    categories: params.categories,
    debts: params.debts,
    allocations: params.allocations,
    startDate: bounds.start.toIsoString(),
    endDate: bounds.end.toIsoString(),
  });

  const matchingBudgets = params.budgets.filter((b) => b.monthIso === params.monthIso);
  const items: MonthlyBudgetReportItemV7[] = matchingBudgets.map((b) => {
    const spentCents = getCanonicalBudgetSpentCentsV7(
      spendReport,
      b.categoryId,
      params.categories
    );
    const remainingCents = b.limitCents - spentCents;
    const percentUsed =
      b.limitCents > 0 ? Math.min(100, Math.round((spentCents / b.limitCents) * 100)) : 0;
    return {
      budgetId: b.id,
      categoryId: b.categoryId,
      categoryName: resolveCategoryDisplayName(params.categories, b.categoryId),
      monthIso: b.monthIso,
      limitCents: b.limitCents,
      spentCents,
      remainingCents,
      percentUsed,
      isOverBudget: spentCents > b.limitCents,
      rolloverEnabled: Boolean(b.rolloverEnabled),
    };
  });

  return {
    monthIso: params.monthIso,
    totalLimitCents: items.reduce((s, i) => s + i.limitCents, 0),
    totalSpentCents: items.reduce((s, i) => s + i.spentCents, 0),
    items,
  };
}

export function buildAlignedBalanceSheetReportV7(params: {
  accounts: Account[];
  entries: JournalEntry[];
  postings: Posting[];
  debts: Debt[];
  allocations?: SettlementAllocation[];
  breakdown: AvailableToSpendBreakdownV7;
}): AlignedBalanceSheetReportV7 {
  const activePayablesCents = calculateTotalPayables(params.debts, {
    accounts: params.accounts,
    entries: params.entries,
    postings: params.postings,
    allocations: params.allocations,
  });
  const netFinancialPositionCents = calculateNetPosition(
    params.accounts,
    params.postings,
    params.debts,
    params.entries,
    params.allocations
  );
  return {
    planningPeriodEndIso: params.breakdown.planningPeriodEndIso,
    liquidCashCents: params.breakdown.liquidCashCents,
    vaultSavingsCents: params.breakdown.vaultSavingsCents,
    receivablesCents: params.breakdown.receivablesCents,
    prepaidCardCreditCents: params.breakdown.prepaidCardCreditCents,
    shortTermCreditOwedCents: params.breakdown.shortTermCreditOwedCents,
    activePayablesCents,
    duePayablesCents: params.breakdown.duePayablesCents,
    netFinancialPositionCents,
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
  calculateNetPosition,
  calculateSafePercentageChange,
  calculateTotalPayables,
  calculateTotalReceivables,
  CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID,
  CANONICAL_DEFAULT_INCOME_CATEGORY_ID,
  categoryIdsMatchOrAlias,
  classifyAllJournalEntries,
  classifyCurrencyCode,
  classifyJournalEntryCurrency,
  findCategoryByIdOrAlias,
  formatCurrencyCents,
  FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
  FOUNDATION_DEFAULT_INCOME_CATEGORIES,
  generateCashFlowReport,
  generateOccurrenceReport,
  isActiveVerifiedEtbAccount,
  isDebtEligibleEtb,
  isEtbCurrency,
  isExpenseFeePosting,
  isValidCurrencyCode,
  LEGACY_CATEGORY_ID_ALIASES,
  normalizeCurrencyCode,
  parseQuickCaptureExpense,
  resolveCanonicalCategoryId,
  resolveCategoryDisplayName,
  resolveCommitmentCurrencyStatus,
  resolveTransferDisplayEndpoints,
  summarizeDirectExpense,
};
export type {
  Account,
  AccountSubType,
  CashFlowReportSummary,
  CurrencyIsolationAudit,
  CurrencyValidationTier,
  Debt,
  DirectExpenseSummary,
  EntryCurrencyClassification,
  EntryCurrencyStatus,
  JournalEntry,
  OccurrenceReportSummary,
  Party,
  Posting,
  QuickCaptureParsedExpense,
  SettlementAllocation,
  SimpleTransaction,
  TransactionCategory,
  TransferDisplayEndpoints,
  SharedBudget,
  SharedCategory,
  SharedCommitment,
  SharedCommitmentSettlement,
  SharedRecurringRule,
  SharedSavingsGoal,
};
