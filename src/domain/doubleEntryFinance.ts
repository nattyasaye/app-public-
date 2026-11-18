/**
 * Daywell Double-Entry Accounting Engine
 *
 * Core Principles:
 * 1. Balanced Ledger Invariant: Sum of Debits == Sum of Credits for every journal entry.
 * 2. Strict Integer Minor Units: 1 ETB = 100 cents (ሳንቲም). Floating-point math is banned.
 * 3. 3-Date Model:
 *    - occurrenceDate: Economic date (used in Occurrence P&L)
 *    - accountMovementDate: Physical cash movement date (used in Cash-Flow Report)
 *    - settlementDate: Debt allocation settlement date
 * 4. Zero Distortion:
 *    - Transfers are never income or expense.
 *    - Borrowing principal is never income; repayment is never expense.
 *    - Lending principal is never expense; repayment received is never income.
 *    - Interest is classified strictly into separate interest income / expense accounts.
 */

import {
  CANONICAL_DEBT_STATUSES,
  CANONICAL_ENTRY_TYPES,
  calculateSharedAccountBalance,
  calculateSharedCombinedBalance,
  calculateSharedTotalIncome,
  calculateSharedTotalExpense,
  canDeleteSharedAccount,
  canDeleteSharedCategory,
  validateSharedTransfer,
  SYSTEM_CONTROL_ACCOUNT_IDS,
  SharedCommitment,
  SharedCommitmentSettlement,
  SharedDebtStatus,
  SharedEntryType,
  SharedRecurringRule,
  SharedSavingsGoal,
} from './sharedFoundation';
import { CalendarDate, DateRange, EthiopiaClock } from './date';
import {
  CurrencyValidationTier,
  normalizeCurrencyCode,
  classifyCurrencyCode,
  isValidCurrencyCode,
  isEtbCurrency,
  formatCurrencyCents,
  formatCentsAsInput,
  parseDecimalToCentsStrict,
} from './financialEngine';

export {
  CANONICAL_DEBT_STATUSES,
  CANONICAL_ENTRY_TYPES,
  type CurrencyValidationTier,
  normalizeCurrencyCode,
  classifyCurrencyCode,
  isValidCurrencyCode,
  isEtbCurrency,
  formatCurrencyCents,
  formatCentsAsInput,
  parseDecimalToCentsStrict,
};

export type AccountType = 'asset' | 'liability' | 'equity' | 'income' | 'expense';
export type EntryType = SharedEntryType;
export type Direction = 'debit' | 'credit';
export type DebtType = 'receivable' | 'payable';
export type DebtStatus = SharedDebtStatus;

export const ENTRY_TYPE_LEGACY_ALIASES: Readonly<Record<string, EntryType>> = {
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

export const DEBT_STATUS_LEGACY_ALIASES: Readonly<Record<string, DebtStatus>> = {
  partially_settled: 'active',
  writtenOff: 'written_off',
};

const CANONICAL_ENTRY_TYPE_SET = new Set<string>(CANONICAL_ENTRY_TYPES);
const CANONICAL_DEBT_STATUS_SET = new Set<string>(CANONICAL_DEBT_STATUSES);

export function tryNormalizeEntryType(raw: string | null | undefined): EntryType | null {
  if (raw == null) return null;
  const trimmed = raw.trim();
  if (!trimmed) return null;
  if (CANONICAL_ENTRY_TYPE_SET.has(trimmed)) {
    return trimmed as EntryType;
  }
  return ENTRY_TYPE_LEGACY_ALIASES[trimmed] ?? null;
}

export function normalizeEntryType(
  raw: unknown,
  options?: { defaultIfOmitted?: EntryType }
): EntryType {
  if (raw === undefined || raw === null) {
    if (options?.defaultIfOmitted !== undefined) {
      return options.defaultIfOmitted;
    }
    throw new DoubleEntryValidationError('Invalid entryType: expected a non-empty string.');
  }
  if (typeof raw !== 'string') {
    throw new DoubleEntryValidationError(
      `Invalid entryType: expected string, got ${typeof raw}.`
    );
  }
  const normalized = tryNormalizeEntryType(raw);
  if (!normalized) {
    throw new DoubleEntryValidationError(
      `Unsupported entryType "${raw.trim()}".`
    );
  }
  return normalized;
}

export function parseEntryType(raw: unknown): EntryType {
  return normalizeEntryType(raw);
}

export function tryNormalizeDebtStatus(raw: string | null | undefined): DebtStatus | null {
  if (raw == null) return null;
  const trimmed = raw.trim();
  if (!trimmed) return null;
  if (CANONICAL_DEBT_STATUS_SET.has(trimmed)) {
    return trimmed as DebtStatus;
  }
  return DEBT_STATUS_LEGACY_ALIASES[trimmed] ?? null;
}

export function normalizeDebtStatus(
  raw: unknown,
  options?: { defaultIfOmitted?: DebtStatus }
): DebtStatus {
  if (raw === undefined || raw === null) {
    if (options?.defaultIfOmitted !== undefined) {
      return options.defaultIfOmitted;
    }
    throw new DoubleEntryValidationError('Invalid debt status: expected a non-empty string.');
  }
  if (typeof raw !== 'string') {
    throw new DoubleEntryValidationError(
      `Invalid debt status: expected string, got ${typeof raw}.`
    );
  }
  const normalized = tryNormalizeDebtStatus(raw);
  if (!normalized) {
    throw new DoubleEntryValidationError(
      `Unsupported debt status "${raw.trim()}".`
    );
  }
  return normalized;
}

export function parseDebtStatus(raw: unknown): DebtStatus {
  return normalizeDebtStatus(raw);
}
export type AccountSubType =
  | 'cash'
  | 'bank'
  | 'mobile_money'
  | 'savings_vault'
  | 'credit_card'
  | 'receivable'
  | 'payable'
  | 'opening_equity'
  | 'nominal_income'
  | 'nominal_expense'
  | 'legacy_clearing';

export interface Account {
  id: string;
  name: string;
  type: AccountType;
  subType?: AccountSubType;
  isSystem?: boolean;
  currencyCode: string; // 'ETB', 'USD', etc. Strict single currency per account
  openingBalanceCents?: number;
  openingBalanceDate?: string;
  isArchived: boolean;
  createdAt: string; // ISO 8601
  updatedAt?: string;
}

export interface Party {
  id: string;
  name: string;
  phone?: string;
  notes?: string;
  isArchived: boolean;
  createdAt: string;
}

export interface JournalEntry {
  id: string;
  entryType: EntryType;
  description: string;
  occurrenceDate: string; // YYYY-MM-DD
  isVoided: boolean;
  voidReason?: string;
  correctedFromEntryId?: string;
  legacySourceTxId?: string;
  createdAt: string;
}

export interface Posting {
  id: string;
  entryId: string;
  accountId: string;
  amountCents: number; // Positive integer > 0
  direction: Direction;
  accountMovementDate: string; // YYYY-MM-DD
  categoryId?: string;
  note?: string;
}

export interface Debt {
  id: string;
  originEntryId: string;
  partyId: string;
  debtType: DebtType; // 'receivable' (they owe me) | 'payable' (I owe them)
  principalCents: number;
  outstandingCents: number;
  dueDate?: string; // YYYY-MM-DD
  status: DebtStatus;
  writeOffEntryId?: string;
  createdAt: string;
}

export interface SettlementAllocation {
  id: string;
  settlementEntryId: string;
  debtId: string;
  allocatedCents: number;
  settlementDate: string; // YYYY-MM-DD
}

export interface TransactionCategory {
  id: string;
  name: string;
  type: 'income' | 'expense';
  colorHex: string;
  isDefault?: boolean;
  isArchived?: boolean;
  subcategories?: string[];
}

export const CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID = 'cat-other-exp';
export const CANONICAL_DEFAULT_INCOME_CATEGORY_ID = 'cat-other-inc';

export const LEGACY_CATEGORY_ID_ALIASES: Readonly<Record<string, string>> = {
  'cat-other': CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID,
  'cat-misc': CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID,
  'cat-inc-other': CANONICAL_DEFAULT_INCOME_CATEGORY_ID,
  'cat-from-asaye': 'cat-asaye',
  'cat-communication': 'cat-comm',
};

export function resolveCanonicalCategoryId(categoryId: string): string {
  return LEGACY_CATEGORY_ID_ALIASES[categoryId] ?? categoryId;
}

export function categoryIdsMatchOrAlias(a?: string, b?: string): boolean {
  if (!a || !b) return false;
  if (a === b) return true;
  return resolveCanonicalCategoryId(a) === resolveCanonicalCategoryId(b);
}

export function findCategoryByIdOrAlias(
  categories: TransactionCategory[],
  categoryId?: string
): TransactionCategory | undefined {
  if (!categoryId) return undefined;
  const exact = categories.find((c) => c.id === categoryId);
  if (exact) return exact;
  const canonicalId = resolveCanonicalCategoryId(categoryId);
  const canonicalMatch = categories.find((c) => c.id === canonicalId);
  if (canonicalMatch) return canonicalMatch;
  return categories.find((c) => resolveCanonicalCategoryId(c.id) === canonicalId);
}

export function resolveCategoryDisplayName(
  categories: TransactionCategory[],
  categoryId?: string
): string {
  if (!categoryId) return '';
  const found = findCategoryByIdOrAlias(categories, categoryId);
  if (found) return found.name;
  const canonicalDefaults = [
    ...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
    ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
  ];
  const fallback = findCategoryByIdOrAlias(canonicalDefaults, categoryId);
  return fallback?.name || categoryId;
}

export const DEFAULT_EXPENSE_CATEGORIES: TransactionCategory[] = [
  { id: 'cat-food', name: 'Food', type: 'expense', colorHex: '#EF4444' },
  { id: 'cat-transport', name: 'Transport', type: 'expense', colorHex: '#F97316' },
  { id: 'cat-housing', name: 'Housing', type: 'expense', colorHex: '#F59E0B' },
  { id: 'cat-utilities', name: 'Utilities', type: 'expense', colorHex: '#EAB308' },
  { id: 'cat-comm', name: 'Communication', type: 'expense', colorHex: '#84CC16' },
  { id: 'cat-clothing', name: 'Clothing', type: 'expense', colorHex: '#10B981' },
  { id: 'cat-personal-care', name: 'Personal Care', type: 'expense', colorHex: '#06B6D4' },
  { id: 'cat-hygiene', name: 'Hygiene', type: 'expense', colorHex: '#3B82F6' },
  { id: 'cat-education', name: 'Education', type: 'expense', colorHex: '#6366F1' },
  { id: 'cat-health', name: 'Health', type: 'expense', colorHex: '#8B5CF6' },
  { id: 'cat-family', name: 'Family', type: 'expense', colorHex: '#EC4899' },
  { id: 'cat-social', name: 'Social', type: 'expense', colorHex: '#F43F5E' },
  { id: 'cat-entertainment', name: 'Entertainment', type: 'expense', colorHex: '#A855F7' },
  { id: 'cat-shopping', name: 'Shopping', type: 'expense', colorHex: '#14B8A6' },
  { id: 'cat-fees', name: 'Financial Fees', type: 'expense', colorHex: '#64748B' },
  { id: 'cat-other-exp', name: 'Other', type: 'expense', colorHex: '#94A3B8', isDefault: true },
];

export const DEFAULT_INCOME_CATEGORIES: TransactionCategory[] = [
  { id: 'cat-inc-salary', name: 'Salary', type: 'income', colorHex: '#10B981', isDefault: true },
  { id: 'cat-inc-freelance', name: 'Freelance', type: 'income', colorHex: '#06B6D4' },
  { id: 'cat-inc-business', name: 'Business', type: 'income', colorHex: '#3B82F6' },
  { id: 'cat-inc-family-support', name: 'Family Support', type: 'income', colorHex: '#8B5CF6' },
  { id: 'cat-inc-gifts', name: 'Gifts', type: 'income', colorHex: '#EC4899' },
  { id: 'cat-inc-investment', name: 'Investment', type: 'income', colorHex: '#F59E0B' },
  { id: 'cat-other-inc', name: 'Other', type: 'income', colorHex: '#64748B', isDefault: true },
];

export const DEFAULT_ACCOUNTS: Account[] = [
  { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 0, isArchived: false, createdAt: '2026-11-01T00:00:00Z' },
  { id: 'acc-boa', name: 'BOA', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 0, isArchived: false, createdAt: '2026-11-01T00:00:00Z' },
  { id: 'acc-dashen', name: 'Dashen Bank', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 0, isArchived: false, createdAt: '2026-11-01T00:00:00Z' },
  { id: 'acc-telebirr', name: 'Telebirr', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 0, isArchived: false, createdAt: '2026-11-01T00:00:00Z' },
  { id: 'acc-cash', name: 'Cash', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 0, isArchived: false, createdAt: '2026-11-01T00:00:00Z' },
];

// -------------------------------------------------------------
// Validation & Balancing Rules
// -------------------------------------------------------------

export class DoubleEntryValidationError extends Error {
  constructor(message: string) {
    super(`[DoubleEntryValidation] ${message}`);
    this.name = 'DoubleEntryValidationError';
  }
}

export function validateBalancedEntry(postings: Posting[]): void {
  if (postings.length < 2) {
    throw new DoubleEntryValidationError(
      `Journal entry must contain at least 2 postings, got ${postings.length}`
    );
  }

  let totalDebits = 0;
  let totalCredits = 0;

  for (const p of postings) {
    if (p.amountCents <= 0 || !Number.isInteger(p.amountCents)) {
      throw new DoubleEntryValidationError(
        `Posting amount must be a positive integer, got ${p.amountCents}`
      );
    }

    if (p.direction === 'debit') {
      totalDebits += p.amountCents;
    } else if (p.direction === 'credit') {
      totalCredits += p.amountCents;
    } else {
      throw new DoubleEntryValidationError(`Invalid posting direction: ${p.direction}`);
    }
  }

  if (totalDebits !== totalCredits) {
    throw new DoubleEntryValidationError(
      `Ledger out of balance: Total Debits (${totalDebits} cents) != Total Credits (${totalCredits} cents). Difference: ${Math.abs(
        totalDebits - totalCredits
      )} cents`
    );
  }
}

export function isActiveVerifiedEtbAccount(account: Account | undefined): boolean {
  if (!account) return false;
  if (account.isSystem || account.isArchived) return false;
  if (
    account.subType === 'legacy_clearing' ||
    account.subType === 'receivable' ||
    account.subType === 'payable' ||
    account.subType === 'opening_equity' ||
    account.subType === 'nominal_income' ||
    account.subType === 'nominal_expense'
  ) {
    return false;
  }
  return isEtbCurrency(account.currencyCode);
}

export function assertVerifiedEtbAccount(
  account: Account | undefined,
  roleLabel: string = 'Account'
): void {
  if (!account) {
    throw new DoubleEntryValidationError(`${roleLabel} not found.`);
  }
  if (account.isArchived) {
    throw new DoubleEntryValidationError(`${roleLabel} "${account.name}" is archived or inactive.`);
  }
  if (account.isSystem || SYSTEM_CONTROL_ID_SET.has(account.id)) {
    throw new DoubleEntryValidationError(`${roleLabel} "${account.name}" is a system control account.`);
  }
  const tier = classifyCurrencyCode(account.currencyCode);
  if (tier !== 'verified_etb') {
    const codeLabel =
      tier === 'verified_non_etb'
        ? normalizeCurrencyCode(account.currencyCode)
        : 'Unverified';
    throw new DoubleEntryValidationError(
      `First-release reporting supports ETB writes only; ${roleLabel.toLowerCase()} "${account.name}" (${codeLabel}) cannot receive new postings.`
    );
  }
}

export function assertEtbPostingAccounts(params: {
  accounts: Account[];
  accountIds: Array<string | undefined | null>;
  roleLabels?: string[];
}): void {
  const byId = new Map(params.accounts.map((a) => [a.id, a]));
  params.accountIds.forEach((id, idx) => {
    if (!id) return;
    const acc = byId.get(id);
    if (isLegacyClearingAccount(acc, id)) {
      throw new DoubleEntryValidationError(
        'Legacy clearing offset account (acc-sys-legacy-offset) cannot receive new postings.'
      );
    }
    if (SYSTEM_CONTROL_ID_SET.has(id)) return;
    assertVerifiedEtbAccount(acc, params.roleLabels?.[idx] || 'Account');
  });
}

export function assertEtbDebtEligible(params: {
  debt: Debt;
  accounts: Account[];
  entries: JournalEntry[];
  postings: Posting[];
  allocations?: SettlementAllocation[];
}): void {
  const classifications = classifyAllJournalEntries({
    accounts: params.accounts,
    entries: params.entries,
    postings: params.postings,
    debts: [params.debt],
    allocations: params.allocations,
  });
  const originClass = classifications.get(params.debt.originEntryId);
  if (!originClass || !originClass.isEligibleEtb) {
    throw new DoubleEntryValidationError(
      'Cannot settle or write off a non-ETB or currency-review debt in first-release ETB mode.'
    );
  }
}

// -------------------------------------------------------------
// Core Financial Balance Formulas
// -------------------------------------------------------------

export function calculateAccountBalance(
  account: Account,
  postings: Posting[],
  asOfDate?: string,
  entries?: JournalEntry[]
): number {
  const voidedEntryIds = new Set<string>(
    entries ? entries.filter((e) => e.isVoided).map((e) => e.id) : []
  );

  let balance = account.openingBalanceCents || 0;
  for (const p of postings) {
    if (p.accountId !== account.id) continue;
    if (voidedEntryIds.has(p.entryId)) continue;
    if (asOfDate && p.accountMovementDate > asOfDate) continue;

    // Normal debit balance accounts: Asset, Expense
    // Normal credit balance accounts: Liability, Equity, Income
    if (account.type === 'asset' || account.type === 'expense') {
      balance += p.direction === 'debit' ? p.amountCents : -p.amountCents;
    } else {
      balance += p.direction === 'credit' ? p.amountCents : -p.amountCents;
    }
  }
  return balance;
}

export type EntryCurrencyStatus =
  | 'eligible_etb'
  | 'excluded_non_etb'
  | 'mixed_or_ambiguous'
  | 'inactive_or_voided';

export interface EntryCurrencyClassification {
  entryId: string;
  status: EntryCurrencyStatus;
  nativeCurrencyCode?: string;
  touchedCurrencies: string[];
  reason?: string;
  isEligibleEtb: boolean;
  isExcludedNonEtb: boolean;
  needsCurrencyReview: boolean;
  isInactiveOrVoided: boolean;
}

export interface CurrencyIsolationAudit {
  classificationsByEntryId: Map<string, EntryCurrencyClassification>;
  nonEtbAccountCount: number;
  unverifiedAccountCount: number;
  excludedNonEtbEntryCount: number;
  currencyReviewEntryCount: number;
  excludedNonEtbDebtCount: number;
  excludedNonEtbCommitmentCount: number;
  excludedVaultGoalCount?: number;
  warnings: string[];
}

const SYSTEM_CONTROL_ID_SET = new Set<string>(Object.values(SYSTEM_CONTROL_ACCOUNT_IDS));

function isLegacyClearingAccount(acc: Account | undefined, accountId: string): boolean {
  return (
    acc?.subType === 'legacy_clearing' ||
    accountId === SYSTEM_CONTROL_ACCOUNT_IDS.legacyOffset
  );
}

function isSystemNominalOrControlAccount(acc: Account | undefined, accountId: string): boolean {
  if (isLegacyClearingAccount(acc, accountId)) return false;
  if (!acc) return SYSTEM_CONTROL_ID_SET.has(accountId);
  if (SYSTEM_CONTROL_ID_SET.has(acc.id)) return true;
  if (
    acc.subType === 'nominal_income' ||
    acc.subType === 'nominal_expense' ||
    acc.subType === 'opening_equity' ||
    acc.subType === 'receivable' ||
    acc.subType === 'payable'
  ) {
    return true;
  }
  if (
    acc.isSystem &&
    (acc.type === 'income' || acc.type === 'expense' || acc.type === 'equity')
  ) {
    return true;
  }
  return false;
}

function buildEntryClassification(
  entryId: string,
  status: EntryCurrencyStatus,
  touchedCurrencies: string[],
  nativeCurrencyCode?: string,
  reason?: string
): EntryCurrencyClassification {
  return {
    entryId,
    status,
    nativeCurrencyCode,
    touchedCurrencies,
    reason,
    isEligibleEtb: status === 'eligible_etb',
    isExcludedNonEtb: status === 'excluded_non_etb',
    needsCurrencyReview: status === 'mixed_or_ambiguous',
    isInactiveOrVoided: status === 'inactive_or_voided',
  };
}

function collectFinancialCurrenciesForEntry(
  entryPostings: Posting[],
  accountById: Map<string, Account>
): {
  financialLegCount: number;
  financialCurrencies: string[];
  hasUnverifiedFinancial: boolean;
  touchesLegacyClearing: boolean;
  missingAccountId?: string;
} {
  let financialLegCount = 0;
  const currencySet = new Set<string>();
  let hasUnverifiedFinancial = false;
  let touchesLegacyClearing = false;
  let missingAccountId: string | undefined;

  for (const p of entryPostings) {
    const acc = accountById.get(p.accountId);
    if (isLegacyClearingAccount(acc, p.accountId)) {
      touchesLegacyClearing = true;
      continue;
    }
    if (isSystemNominalOrControlAccount(acc, p.accountId)) {
      continue;
    }
    if (!acc) {
      missingAccountId = missingAccountId || p.accountId;
      continue;
    }
    financialLegCount += 1;
    const tier = classifyCurrencyCode(acc.currencyCode);
    if (tier === 'unverified') {
      hasUnverifiedFinancial = true;
      currencySet.add('UNVERIFIED');
    } else {
      currencySet.add(normalizeCurrencyCode(acc.currencyCode));
    }
  }

  return {
    financialLegCount,
    financialCurrencies: Array.from(currencySet).sort(),
    hasUnverifiedFinancial,
    touchesLegacyClearing,
    missingAccountId,
  };
}

function classifyJournalEntryCurrencyInternal(params: {
  entry: JournalEntry;
  postingsByEntry: Map<string, Posting[]>;
  accountById: Map<string, Account>;
  entryById?: Map<string, JournalEntry>;
  debtById?: Map<string, Debt>;
  debtByOriginEntryId?: Map<string, Debt>;
  debtByWriteOffEntryId?: Map<string, Debt>;
  allocationsBySettlementEntryId?: Map<string, SettlementAllocation[]>;
  allocationsByDebtId?: Map<string, SettlementAllocation[]>;
  cache?: Map<string, EntryCurrencyClassification>;
  visiting: Set<string>;
  ignoreVoidFlag?: boolean;
}): EntryCurrencyClassification {
  const { entry, postingsByEntry, accountById, visiting } = params;

  if (!params.ignoreVoidFlag && params.cache?.has(entry.id)) {
    return params.cache.get(entry.id)!;
  }

  const entryPostings = postingsByEntry.get(entry.id) || [];

  // [1] Voided entry priority (skipped only when resolving lineage targets that were voided upon replacement)
  if (!params.ignoreVoidFlag && entry.isVoided) {
    const scanned = collectFinancialCurrenciesForEntry(entryPostings, accountById);
    const singleNative =
      !scanned.hasUnverifiedFinancial && scanned.financialCurrencies.length === 1
        ? scanned.financialCurrencies[0]
        : undefined;
    const res = buildEntryClassification(
      entry.id,
      'inactive_or_voided',
      scanned.financialCurrencies,
      singleNative,
      entry.voidReason ? `Voided: ${entry.voidReason}` : 'Voided journal entry.'
    );
    params.cache?.set(entry.id, res);
    return res;
  }

  // Cycle guard
  if (visiting.has(entry.id)) {
    return buildEntryClassification(
      entry.id,
      'mixed_or_ambiguous',
      [],
      undefined,
      'Cyclic entry lineage detected.'
    );
  }
  const nextVisiting = new Set(visiting);
  nextVisiting.add(entry.id);

  // [2] Structural integrity: < 2 postings, missing non-system account, or legacy clearing
  if (entryPostings.length < 2) {
    const res = buildEntryClassification(
      entry.id,
      'mixed_or_ambiguous',
      [],
      undefined,
      'Entry has fewer than 2 postings.'
    );
    if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
    return res;
  }

  const scanned = collectFinancialCurrenciesForEntry(entryPostings, accountById);
  if (scanned.touchesLegacyClearing) {
    const res = buildEntryClassification(
      entry.id,
      'mixed_or_ambiguous',
      scanned.financialCurrencies,
      undefined,
      'References legacy clearing offset account.'
    );
    if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
    return res;
  }

  if (scanned.missingAccountId) {
    const res = buildEntryClassification(
      entry.id,
      'mixed_or_ambiguous',
      scanned.financialCurrencies,
      undefined,
      `References missing or unknown account "${scanned.missingAccountId}".`
    );
    if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
    return res;
  }

  // [3A] Has real financial account leg(s)
  if (scanned.financialLegCount >= 1) {
    if (scanned.hasUnverifiedFinancial) {
      const res = buildEntryClassification(
        entry.id,
        'mixed_or_ambiguous',
        scanned.financialCurrencies,
        undefined,
        'References financial account with missing or unverified currency code.'
      );
      if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
      return res;
    }

    if (scanned.financialCurrencies.length > 1) {
      const res = buildEntryClassification(
        entry.id,
        'mixed_or_ambiguous',
        scanned.financialCurrencies,
        undefined,
        `Cross-currency entry (${scanned.financialCurrencies.join(' / ')}).`
      );
      if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
      return res;
    }

    const primaryCurrency = scanned.financialCurrencies[0];

    // Verify debt settlement lineage consistency if debt context is present
    if (entry.entryType === 'settlement' && params.allocationsBySettlementEntryId && params.debtById) {
      const allocs = params.allocationsBySettlementEntryId.get(entry.id) || [];
      for (const alloc of allocs) {
        const debt = params.debtById.get(alloc.debtId);
        if (!debt) {
          const res = buildEntryClassification(
            entry.id,
            'mixed_or_ambiguous',
            scanned.financialCurrencies,
            undefined,
            'Settlement references missing debt record.'
          );
          if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
          return res;
        }
        const originEntry = params.entryById?.get(debt.originEntryId);
        if (!originEntry || originEntry.isVoided) {
          const res = buildEntryClassification(
            entry.id,
            'mixed_or_ambiguous',
            scanned.financialCurrencies,
            undefined,
            'Settlement references debt with missing or voided origin entry.'
          );
          if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
          return res;
        }
        const originClass = classifyJournalEntryCurrencyInternal({
          ...params,
          entry: originEntry,
          visiting: nextVisiting,
          ignoreVoidFlag: false,
        });
        if (
          originClass.status === 'mixed_or_ambiguous' ||
          originClass.status === 'inactive_or_voided' ||
          !originClass.nativeCurrencyCode
        ) {
          const res = buildEntryClassification(
            entry.id,
            'mixed_or_ambiguous',
            scanned.financialCurrencies,
            undefined,
            'Settlement linked to debt with ambiguous origin currency.'
          );
          if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
          return res;
        }
        if (originClass.nativeCurrencyCode !== primaryCurrency) {
          const res = buildEntryClassification(
            entry.id,
            'mixed_or_ambiguous',
            Array.from(new Set([primaryCurrency, originClass.nativeCurrencyCode])).sort(),
            undefined,
            `Cross-currency debt settlement: settled in ${primaryCurrency} for ${originClass.nativeCurrencyCode} debt.`
          );
          if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
          return res;
        }
      }
    }

    const res =
      primaryCurrency === 'ETB'
        ? buildEntryClassification(entry.id, 'eligible_etb', ['ETB'], 'ETB')
        : buildEntryClassification(
            entry.id,
            'excluded_non_etb',
            [primaryCurrency],
            primaryCurrency,
            `Non-ETB (${primaryCurrency}) native transaction.`
          );
    if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
    return res;
  }

  // [3B] System-only entry (financialLegCount === 0)
  // 1) Write-off entry -> inherit Debt.originEntryId
  const writeOffDebt = params.debtByWriteOffEntryId?.get(entry.id);
  if (entry.entryType === 'write_off' || writeOffDebt) {
    if (!writeOffDebt || !params.entryById) {
      const res = buildEntryClassification(
        entry.id,
        'mixed_or_ambiguous',
        [],
        undefined,
        'Write-off entry has no verifiable linked debt.'
      );
      if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
      return res;
    }
    const originEntry = params.entryById.get(writeOffDebt.originEntryId);
    if (!originEntry || originEntry.isVoided) {
      const res = buildEntryClassification(
        entry.id,
        'mixed_or_ambiguous',
        [],
        undefined,
        'Write-off references debt with missing or voided origin entry.'
      );
      if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
      return res;
    }
    const originClass = classifyJournalEntryCurrencyInternal({
      ...params,
      entry: originEntry,
      visiting: nextVisiting,
      ignoreVoidFlag: false,
    });
    const res =
      originClass.status === 'eligible_etb'
        ? buildEntryClassification(entry.id, 'eligible_etb', ['ETB'], 'ETB')
        : originClass.status === 'excluded_non_etb' && originClass.nativeCurrencyCode
          ? buildEntryClassification(
              entry.id,
              'excluded_non_etb',
              [originClass.nativeCurrencyCode],
              originClass.nativeCurrencyCode,
              `Write-off for ${originClass.nativeCurrencyCode} debt.`
            )
          : buildEntryClassification(
              entry.id,
              'mixed_or_ambiguous',
              originClass.touchedCurrencies,
              undefined,
              'Write-off inherits ambiguous debt origin currency.'
            );
    if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
    return res;
  }

  // 2) Corrected replacement entry -> inherit original entry's economic legs (ignoring its voided marker)
  if (entry.correctedFromEntryId) {
    const original = params.entryById?.get(entry.correctedFromEntryId);
    if (!original) {
      const res = buildEntryClassification(
        entry.id,
        'mixed_or_ambiguous',
        [],
        undefined,
        'Correction entry references missing original entry.'
      );
      if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
      return res;
    }
    const origClass = classifyJournalEntryCurrencyInternal({
      ...params,
      entry: original,
      visiting: nextVisiting,
      ignoreVoidFlag: true,
    });
    const res =
      origClass.status === 'eligible_etb'
        ? buildEntryClassification(entry.id, 'eligible_etb', ['ETB'], 'ETB')
        : origClass.status === 'excluded_non_etb' && origClass.nativeCurrencyCode
          ? buildEntryClassification(
              entry.id,
              'excluded_non_etb',
              [origClass.nativeCurrencyCode],
              origClass.nativeCurrencyCode,
              `Inherited from ${origClass.nativeCurrencyCode} entry.`
            )
          : buildEntryClassification(
              entry.id,
              'mixed_or_ambiguous',
              origClass.touchedCurrencies,
              undefined,
              origClass.reason || 'Correction inherits ambiguous currency.'
            );
    if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
    return res;
  }

  // 3) Third-party-paid expense backed by Debt(originEntryId == entry.id)
  const originDebt = params.debtByOriginEntryId?.get(entry.id);
  if (originDebt && entry.entryType === 'debt_issuance') {
    const linkedAllocs = params.allocationsByDebtId?.get(originDebt.id) || [];
    const settlementCurrencies = new Set<string>();
    for (const alloc of linkedAllocs) {
      const settleEntry = params.entryById?.get(alloc.settlementEntryId);
      if (!settleEntry || settleEntry.isVoided) continue;
      const settlePostings = postingsByEntry.get(settleEntry.id) || [];
      const settleScan = collectFinancialCurrenciesForEntry(settlePostings, accountById);
      if (
        settleScan.touchesLegacyClearing ||
        settleScan.missingAccountId ||
        settleScan.hasUnverifiedFinancial ||
        settleScan.financialCurrencies.length !== 1
      ) {
        const res = buildEntryClassification(
          entry.id,
          'mixed_or_ambiguous',
          settleScan.financialCurrencies,
          undefined,
          'Third-party expense has ambiguous settlement currency.'
        );
        if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
        return res;
      }
      settlementCurrencies.add(settleScan.financialCurrencies[0]);
    }

    if (settlementCurrencies.size > 1) {
      const list = Array.from(settlementCurrencies).sort();
      const res = buildEntryClassification(
        entry.id,
        'mixed_or_ambiguous',
        list,
        undefined,
        `Third-party expense has conflicting settlement currencies (${list.join(' / ')}).`
      );
      if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
      return res;
    }

    if (settlementCurrencies.size === 1) {
      const sc = Array.from(settlementCurrencies)[0];
      const res =
        sc === 'ETB'
          ? buildEntryClassification(entry.id, 'eligible_etb', ['ETB'], 'ETB')
          : buildEntryClassification(
              entry.id,
              'excluded_non_etb',
              [sc],
              sc,
              `Third-party expense settled in ${sc}.`
            );
      if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
      return res;
    }

    // Unsettled debt-backed third-party expense has 0 financial legs and no
    // currency_code column in Schema v7 -> Currency Review until settled.
    const res = buildEntryClassification(
      entry.id,
      'mixed_or_ambiguous',
      [],
      undefined,
      'Unsettled third-party entry requires Currency Review.'
    );
    if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
    return res;
  }

  // 4) Unlinked system-only entry -> NEVER default blindly to ETB
  const res = buildEntryClassification(
    entry.id,
    'mixed_or_ambiguous',
    [],
    undefined,
    'Unlinked system-only entry without financial account leg.'
  );
  if (!params.ignoreVoidFlag) params.cache?.set(entry.id, res);
  return res;
}

export function classifyJournalEntryCurrency(params: {
  entry: JournalEntry;
  entryPostings: Posting[];
  accountById: Map<string, Account>;
  debts?: Debt[];
  allocations?: SettlementAllocation[];
  allEntries?: JournalEntry[];
  allPostings?: Posting[];
  ignoreVoidFlag?: boolean;
}): EntryCurrencyClassification {
  const { entry, entryPostings, accountById } = params;
  const postingsByEntry = new Map<string, Posting[]>();
  if (params.allPostings) {
    for (const p of params.allPostings) {
      const list = postingsByEntry.get(p.entryId) || [];
      list.push(p);
      postingsByEntry.set(p.entryId, list);
    }
  }
  if (!postingsByEntry.has(entry.id)) {
    postingsByEntry.set(entry.id, entryPostings);
  }

  const entryById = params.allEntries
    ? new Map(params.allEntries.map((e) => [e.id, e]))
    : new Map([[entry.id, entry]]);
  const debtById = params.debts ? new Map(params.debts.map((d) => [d.id, d])) : undefined;
  const debtByOriginEntryId = params.debts
    ? new Map(params.debts.map((d) => [d.originEntryId, d]))
    : undefined;
  const debtByWriteOffEntryId = params.debts
    ? new Map(
        params.debts
          .filter((d): d is Debt & { writeOffEntryId: string } => Boolean(d.writeOffEntryId))
          .map((d) => [d.writeOffEntryId, d])
      )
    : undefined;
  const allocationsBySettlementEntryId = params.allocations
    ? (() => {
        const m = new Map<string, SettlementAllocation[]>();
        for (const a of params.allocations) {
          const list = m.get(a.settlementEntryId) || [];
          list.push(a);
          m.set(a.settlementEntryId, list);
        }
        return m;
      })()
    : undefined;
  const allocationsByDebtId = params.allocations
    ? (() => {
        const m = new Map<string, SettlementAllocation[]>();
        for (const a of params.allocations) {
          const list = m.get(a.debtId) || [];
          list.push(a);
          m.set(a.debtId, list);
        }
        return m;
      })()
    : undefined;

  return classifyJournalEntryCurrencyInternal({
    entry,
    postingsByEntry,
    accountById,
    entryById,
    debtById,
    debtByOriginEntryId,
    debtByWriteOffEntryId,
    allocationsBySettlementEntryId,
    allocationsByDebtId,
    visiting: new Set<string>(),
    ignoreVoidFlag: params.ignoreVoidFlag,
  });
}

export function classifyAllJournalEntries(params: {
  accounts: Account[];
  entries: JournalEntry[];
  postings: Posting[];
  debts?: Debt[];
  allocations?: SettlementAllocation[];
}): Map<string, EntryCurrencyClassification> {
  const accountById = new Map(params.accounts.map((a) => [a.id, a]));
  const entryById = new Map(params.entries.map((e) => [e.id, e]));
  const postingsByEntry = new Map<string, Posting[]>();
  for (const p of params.postings) {
    const list = postingsByEntry.get(p.entryId) || [];
    list.push(p);
    postingsByEntry.set(p.entryId, list);
  }

  const debtById = params.debts ? new Map(params.debts.map((d) => [d.id, d])) : undefined;
  const debtByOriginEntryId = params.debts
    ? new Map(params.debts.map((d) => [d.originEntryId, d]))
    : undefined;
  const debtByWriteOffEntryId = params.debts
    ? new Map(
        params.debts
          .filter((d): d is Debt & { writeOffEntryId: string } => Boolean(d.writeOffEntryId))
          .map((d) => [d.writeOffEntryId, d])
      )
    : undefined;
  const allocationsBySettlementEntryId = params.allocations
    ? (() => {
        const m = new Map<string, SettlementAllocation[]>();
        for (const a of params.allocations) {
          const list = m.get(a.settlementEntryId) || [];
          list.push(a);
          m.set(a.settlementEntryId, list);
        }
        return m;
      })()
    : undefined;
  const allocationsByDebtId = params.allocations
    ? (() => {
        const m = new Map<string, SettlementAllocation[]>();
        for (const a of params.allocations) {
          const list = m.get(a.debtId) || [];
          list.push(a);
          m.set(a.debtId, list);
        }
        return m;
      })()
    : undefined;

  const cache = new Map<string, EntryCurrencyClassification>();
  for (const entry of params.entries) {
    classifyJournalEntryCurrencyInternal({
      entry,
      postingsByEntry,
      accountById,
      entryById,
      debtById,
      debtByOriginEntryId,
      debtByWriteOffEntryId,
      allocationsBySettlementEntryId,
      allocationsByDebtId,
      cache,
      visiting: new Set<string>(),
    });
  }
  return cache;
}

export interface CommitmentCurrencyResolution {
  status: 'eligible_etb' | 'excluded_non_etb' | 'needs_review';
  currencyCode?: string;
  isUnlinkedAssumedEtb: boolean;
  reason?: string;
}

export function resolveCommitmentCurrencyStatus(params: {
  commitment: Pick<
    SharedCommitment,
    'id' | 'isPaid' | 'legacyPaidUnverified' | 'linkedAccountId' | 'linkedDebtId' | 'recurringRuleId'
  >;
  accountById: Map<string, Account>;
  debtById?: Map<string, Debt>;
  entryById?: Map<string, JournalEntry>;
  classificationsByEntryId?: Map<string, EntryCurrencyClassification>;
  ruleById?: Map<string, SharedRecurringRule>;
  settlementsByCommitmentId?: Map<string, SharedCommitmentSettlement[]>;
}): CommitmentCurrencyResolution {
  const { commitment: cm, accountById } = params;

  // (1) Direct linkedAccountId
  if (cm.linkedAccountId) {
    const acc = accountById.get(cm.linkedAccountId);
    if (!acc) {
      return {
        status: 'needs_review',
        isUnlinkedAssumedEtb: false,
        reason: 'References missing account.',
      };
    }
    const tier = classifyCurrencyCode(acc.currencyCode);
    if (tier === 'verified_etb') {
      return { status: 'eligible_etb', currencyCode: 'ETB', isUnlinkedAssumedEtb: false };
    }
    if (tier === 'verified_non_etb') {
      return {
        status: 'excluded_non_etb',
        currencyCode: normalizeCurrencyCode(acc.currencyCode),
        isUnlinkedAssumedEtb: false,
        reason: `Linked to ${normalizeCurrencyCode(acc.currencyCode)} account.`,
      };
    }
    return {
      status: 'needs_review',
      isUnlinkedAssumedEtb: false,
      reason: 'Linked to account with unverified currency.',
    };
  }

  // (2) Linked Debt
  if (cm.linkedDebtId && params.debtById && params.classificationsByEntryId && params.entryById) {
    const debt = params.debtById.get(cm.linkedDebtId);
    if (!debt || !params.entryById.has(debt.originEntryId)) {
      return {
        status: 'needs_review',
        isUnlinkedAssumedEtb: false,
        reason: 'Linked debt or origin entry is missing.',
      };
    }
    const cls = params.classificationsByEntryId.get(debt.originEntryId);
    if (!cls || cls.needsCurrencyReview || cls.isInactiveOrVoided) {
      return {
        status: 'needs_review',
        isUnlinkedAssumedEtb: false,
        reason: 'Linked debt requires currency review.',
      };
    }
    if (cls.isExcludedNonEtb) {
      return {
        status: 'excluded_non_etb',
        currencyCode: cls.nativeCurrencyCode,
        isUnlinkedAssumedEtb: false,
        reason: `Linked to ${cls.nativeCurrencyCode || 'non-ETB'} debt.`,
      };
    }
    return { status: 'eligible_etb', currencyCode: 'ETB', isUnlinkedAssumedEtb: false };
  }

  // (3) Recurring Rule
  if (cm.recurringRuleId && params.ruleById) {
    const rule = params.ruleById.get(cm.recurringRuleId);
    if (rule) {
      const ruleAccIds = [rule.accountId, rule.destinationAccountId].filter(
        (id): id is string => Boolean(id && id.trim())
      );
      if (ruleAccIds.length > 0) {
        let foreignCode: string | undefined;
        for (const accId of ruleAccIds) {
          const acc = accountById.get(accId);
          if (!acc) {
            return {
              status: 'needs_review',
              isUnlinkedAssumedEtb: false,
              reason: 'Linked recurring rule references missing account.',
            };
          }
          const tier = classifyCurrencyCode(acc.currencyCode);
          if (tier === 'unverified') {
            return {
              status: 'needs_review',
              isUnlinkedAssumedEtb: false,
              reason: 'Linked recurring rule references unverified account currency.',
            };
          }
          if (tier === 'verified_non_etb') {
            const code = normalizeCurrencyCode(acc.currencyCode);
            if (foreignCode && foreignCode !== code) {
              return {
                status: 'needs_review',
                isUnlinkedAssumedEtb: false,
                reason: 'Linked recurring rule spans conflicting currencies.',
              };
            }
            foreignCode = code;
          }
        }
        if (foreignCode) {
          return {
            status: 'excluded_non_etb',
            currencyCode: foreignCode,
            isUnlinkedAssumedEtb: false,
            reason: `Linked to ${foreignCode} recurring rule.`,
          };
        }
        return { status: 'eligible_etb', currencyCode: 'ETB', isUnlinkedAssumedEtb: false };
      }
      if (rule.linkedDebtId && params.debtById && params.classificationsByEntryId && params.entryById) {
        const debt = params.debtById.get(rule.linkedDebtId);
        if (!debt || !params.entryById.has(debt.originEntryId)) {
          return {
            status: 'needs_review',
            isUnlinkedAssumedEtb: false,
            reason: 'Linked recurring debt is missing.',
          };
        }
        const cls = params.classificationsByEntryId.get(debt.originEntryId);
        if (!cls || cls.needsCurrencyReview || cls.isInactiveOrVoided) {
          return {
            status: 'needs_review',
            isUnlinkedAssumedEtb: false,
            reason: 'Linked recurring debt requires currency review.',
          };
        }
        if (cls.isExcludedNonEtb) {
          return {
            status: 'excluded_non_etb',
            currencyCode: cls.nativeCurrencyCode,
            isUnlinkedAssumedEtb: false,
            reason: `Linked recurring rule references ${cls.nativeCurrencyCode || 'non-ETB'} debt.`,
          };
        }
        return { status: 'eligible_etb', currencyCode: 'ETB', isUnlinkedAssumedEtb: false };
      }
    }
  }

  // (4) Non-voided CommitmentSettlement entries
  if (params.settlementsByCommitmentId && params.classificationsByEntryId) {
    const sets = params.settlementsByCommitmentId.get(cm.id) || [];
    const seen = new Set<string>();
    for (const s of sets) {
      const cls = params.classificationsByEntryId.get(s.entryId);
      if (!cls || cls.isInactiveOrVoided) continue;
      if (cls.needsCurrencyReview) {
        return {
          status: 'needs_review',
          isUnlinkedAssumedEtb: false,
          reason: 'Commitment settlement requires currency review.',
        };
      }
      seen.add(cls.nativeCurrencyCode || 'ETB');
    }
    if (seen.size > 1) {
      return {
        status: 'needs_review',
        isUnlinkedAssumedEtb: false,
        reason: 'Commitment has conflicting settlement currencies.',
      };
    }
    if (seen.size === 1) {
      const code = Array.from(seen)[0];
      if (code !== 'ETB') {
        return {
          status: 'excluded_non_etb',
          currencyCode: code,
          isUnlinkedAssumedEtb: false,
          reason: `Partially settled in ${code}.`,
        };
      }
      return { status: 'eligible_etb', currencyCode: 'ETB', isUnlinkedAssumedEtb: false };
    }
  }

  // (5) Unlinked commitment cannot assume ETB silently under Stage 2.2
  return {
    status: 'needs_review',
    isUnlinkedAssumedEtb: false,
    reason:
      'Unlinked commitment has no verified currency source; link an active ETB account to include in ETB Safe Harbor.',
  };
}

export function auditCurrencyIsolation(params: {
  accounts: Account[];
  entries: JournalEntry[];
  postings: Posting[];
  debts?: Debt[];
  allocations?: SettlementAllocation[];
  commitments?: Array<{
    id?: string;
    isPaid: boolean;
    legacyPaidUnverified?: boolean;
    linkedAccountId?: string;
    linkedDebtId?: string;
    recurringRuleId?: string;
  }>;
  recurringRules?: SharedRecurringRule[];
  commitmentSettlements?: SharedCommitmentSettlement[];
  savingsGoals?: SharedSavingsGoal[];
}): CurrencyIsolationAudit {
  const classifications = classifyAllJournalEntries({
    accounts: params.accounts,
    entries: params.entries,
    postings: params.postings,
    debts: params.debts,
    allocations: params.allocations,
  });
  const accountById = new Map(params.accounts.map((a) => [a.id, a]));
  const entryById = new Map(params.entries.map((e) => [e.id, e]));
  const debtById = new Map((params.debts || []).map((d) => [d.id, d]));
  const ruleById = new Map((params.recurringRules || []).map((r) => [r.id, r]));
  const settlementsByCommitmentId = new Map<string, SharedCommitmentSettlement[]>();
  for (const s of params.commitmentSettlements || []) {
    const list = settlementsByCommitmentId.get(s.commitmentId) || [];
    list.push(s);
    settlementsByCommitmentId.set(s.commitmentId, list);
  }

  let excludedNonEtbEntryCount = 0;
  let currencyReviewEntryCount = 0;
  for (const entry of params.entries) {
    if (entry.isVoided) continue;
    const c = classifications.get(entry.id);
    if (!c || c.isInactiveOrVoided) continue;
    if (c.isExcludedNonEtb) excludedNonEtbEntryCount += 1;
    if (c.needsCurrencyReview) currencyReviewEntryCount += 1;
  }

  let excludedNonEtbDebtCount = 0;
  for (const d of params.debts || []) {
    if (d.status !== 'active') continue;
    if (!entryById.has(d.originEntryId)) {
      excludedNonEtbDebtCount += 1;
      continue;
    }
    const c = classifications.get(d.originEntryId);
    if (!c || !c.isEligibleEtb) excludedNonEtbDebtCount += 1;
  }

  let excludedNonEtbCommitmentCount = 0;
  for (const cm of params.commitments || []) {
    if (cm.isPaid || cm.legacyPaidUnverified) continue;
    const res = resolveCommitmentCurrencyStatus({
      commitment: {
        id: cm.id || '',
        isPaid: cm.isPaid,
        legacyPaidUnverified: cm.legacyPaidUnverified,
        linkedAccountId: cm.linkedAccountId,
        linkedDebtId: cm.linkedDebtId,
        recurringRuleId: cm.recurringRuleId,
      },
      accountById,
      debtById,
      entryById,
      classificationsByEntryId: classifications,
      ruleById,
      settlementsByCommitmentId,
    });
    if (res.status !== 'eligible_etb') {
      excludedNonEtbCommitmentCount += 1;
    }
  }

  let verifiedNonEtbAccountCount = 0;
  let unverifiedAccountCount = 0;
  for (const acc of params.accounts) {
    if (acc.isSystem || acc.isArchived) continue;
    const tier = classifyCurrencyCode(acc.currencyCode);
    if (tier === 'verified_non_etb') verifiedNonEtbAccountCount += 1;
    else if (tier === 'unverified') unverifiedAccountCount += 1;
  }
  const nonEtbAccountCount = verifiedNonEtbAccountCount + unverifiedAccountCount;

  const excludedVaultGoalsCount = (params.savingsGoals || []).filter((g) => {
    if (!g.linkedAccountId || g.status === 'archived') return false;
    const acc = accountById.get(g.linkedAccountId);
    return !isActiveVerifiedEtbAccount(acc) || acc?.subType !== 'savings_vault';
  }).length;

  const warnings: string[] = [];
  if (verifiedNonEtbAccountCount > 0) {
    warnings.push(
      `${verifiedNonEtbAccountCount} non-ETB account(s) are excluded from ETB Safe Harbor, P&L, and Net Worth totals.`
    );
  }
  if (unverifiedAccountCount > 0) {
    warnings.push(
      `${unverifiedAccountCount} account(s) have missing or unverified currency metadata and are excluded under Currency Review.`
    );
  }
  if (excludedNonEtbEntryCount > 0) {
    warnings.push(
      `${excludedNonEtbEntryCount} non-ETB transaction(s) are excluded from ETB P&L, cashflow, and budgets.`
    );
  }
  if (currencyReviewEntryCount > 0) {
    warnings.push(
      `${currencyReviewEntryCount} mixed-currency or ambiguous entry(ies) require currency review and are excluded from ETB reports.`
    );
  }
  if (excludedNonEtbDebtCount > 0) {
    warnings.push(
      `${excludedNonEtbDebtCount} non-ETB, mixed, or missing-origin debt(s) are excluded from ETB Safe Harbor receivables/payables.`
    );
  }
  if (excludedNonEtbCommitmentCount > 0) {
    warnings.push(
      `${excludedNonEtbCommitmentCount} commitment(s) linked to non-ETB, unverified, or missing references are excluded from ETB Safe Harbor.`
    );
  }
  if (excludedVaultGoalsCount > 0) {
    warnings.push(
      `${excludedVaultGoalsCount} vault-linked savings goal(s) reference non-ETB, archived, or missing vault accounts and are excluded from ETB totals.`
    );
  }

  return {
    classificationsByEntryId: classifications,
    nonEtbAccountCount,
    unverifiedAccountCount,
    excludedNonEtbEntryCount,
    currencyReviewEntryCount,
    excludedNonEtbDebtCount,
    excludedNonEtbCommitmentCount,
    excludedVaultGoalCount: excludedVaultGoalsCount,
    warnings,
  };
}

export function calculateLiquidCash(
  accounts: Account[],
  postings: Posting[],
  entries?: JournalEntry[]
): number {
  const liquidAssetAccounts = accounts.filter(
    (a) =>
      a.type === 'asset' &&
      !a.isArchived &&
      !a.isSystem &&
      a.subType !== 'savings_vault' &&
      a.subType !== 'receivable' &&
      isEtbCurrency(a.currencyCode) &&
      !a.name.toLowerCase().includes('receivable')
  );
  return liquidAssetAccounts.reduce(
    (sum, acc) => sum + calculateAccountBalance(acc, postings, undefined, entries),
    0
  );
}

export function calculateVaultSavingsTotal(
  accounts: Account[],
  postings: Posting[],
  entries?: JournalEntry[]
): number {
  return accounts
    .filter(
      (a) =>
        a.type === 'asset' &&
        !a.isArchived &&
        !a.isSystem &&
        a.subType === 'savings_vault' &&
        isEtbCurrency(a.currencyCode)
    )
    .reduce(
      (sum, acc) => sum + calculateAccountBalance(acc, postings, undefined, entries),
      0
    );
}

export function calculateShortTermCreditOwed(
  accounts: Account[],
  postings: Posting[],
  entries?: JournalEntry[]
): number {
  let sum = 0;
  for (const acc of accounts) {
    if (
      acc.type !== 'liability' ||
      acc.isArchived ||
      acc.isSystem ||
      (acc.subType && acc.subType !== 'credit_card') ||
      !isEtbCurrency(acc.currencyCode)
    ) {
      continue;
    }
    const bal = calculateAccountBalance(acc, postings, undefined, entries);
    if (bal > 0) sum += bal;
  }
  return sum;
}

/**
 * Option 1 (Approved Stage 4.0.5):
 * Overpaid credit card balance (< 0 on credit_card liability) creates PrepaidCardCredit,
 * which IS INCLUDED in AvailableToSpend(H) and NetFinancialPosition and displayed separately.
 */
export function calculatePrepaidCardCredit(
  accounts: Account[],
  postings: Posting[],
  entries?: JournalEntry[]
): number {
  let sum = 0;
  for (const acc of accounts) {
    if (
      acc.type !== 'liability' ||
      acc.isArchived ||
      acc.isSystem ||
      (acc.subType && acc.subType !== 'credit_card') ||
      !isEtbCurrency(acc.currencyCode)
    ) {
      continue;
    }
    const bal = calculateAccountBalance(acc, postings, undefined, entries);
    if (bal < 0) sum += -bal;
  }
  return sum;
}

export function isDebtEligibleEtb(
  debt: Debt,
  entryById?: Map<string, JournalEntry>,
  classifications?: Map<string, EntryCurrencyClassification>
): boolean {
  if (!entryById || !classifications) return true;
  if (!entryById.has(debt.originEntryId)) return false;
  return classifications.get(debt.originEntryId)?.isEligibleEtb ?? false;
}

export function calculateTotalReceivables(
  debts: Debt[],
  context?: {
    accounts?: Account[];
    entries?: JournalEntry[];
    postings?: Posting[];
    allocations?: SettlementAllocation[];
  }
): number {
  const hasCtx = Boolean(context?.accounts && context?.entries && context?.postings);
  const entryById = hasCtx ? new Map(context!.entries!.map((e) => [e.id, e])) : undefined;
  const classifications = hasCtx
    ? classifyAllJournalEntries({
        accounts: context!.accounts!,
        entries: context!.entries!,
        postings: context!.postings!,
        debts,
        allocations: context!.allocations,
      })
    : undefined;
  return debts
    .filter(
      (d) =>
        d.debtType === 'receivable' &&
        d.status === 'active' &&
        isDebtEligibleEtb(d, entryById, classifications)
    )
    .reduce((sum, d) => sum + Math.max(0, d.outstandingCents), 0);
}

export function calculateTotalPayables(
  debts: Debt[],
  context?: {
    accounts?: Account[];
    entries?: JournalEntry[];
    postings?: Posting[];
    allocations?: SettlementAllocation[];
  }
): number {
  const hasCtx = Boolean(context?.accounts && context?.entries && context?.postings);
  const entryById = hasCtx ? new Map(context!.entries!.map((e) => [e.id, e])) : undefined;
  const classifications = hasCtx
    ? classifyAllJournalEntries({
        accounts: context!.accounts!,
        entries: context!.entries!,
        postings: context!.postings!,
        debts,
        allocations: context!.allocations,
      })
    : undefined;
  return debts
    .filter(
      (d) =>
        d.debtType === 'payable' &&
        d.status === 'active' &&
        isDebtEligibleEtb(d, entryById, classifications)
    )
    .reduce((sum, d) => sum + Math.max(0, d.outstandingCents), 0);
}

export function calculateNetPosition(
  accounts: Account[],
  postings: Posting[],
  _debts: Debt[],
  entries?: JournalEntry[],
  allocations?: SettlementAllocation[]
): number {
  // ETB-only Net Financial Position:
  // Total Active ETB Assets - Total Active ETB Liabilities
  // Note: negative credit card liability (-bal) already reduces totalLiabilities
  // equivalently to adding PrepaidCardCredit = max(0, -bal).
  const voidedEntryIds = new Set<string>(
    entries ? entries.filter((e) => e.isVoided).map((e) => e.id) : []
  );
  const classifications = entries
    ? classifyAllJournalEntries({
        accounts,
        entries,
        postings,
        debts: _debts,
        allocations,
      })
    : undefined;

  const computeBalanceForNet = (acc: Account): number => {
    if (acc.isSystem && classifications) {
      let bal = acc.openingBalanceCents || 0;
      for (const p of postings) {
        if (p.accountId !== acc.id) continue;
        if (voidedEntryIds.has(p.entryId)) continue;
        if (!(classifications.get(p.entryId)?.isEligibleEtb ?? false)) continue;
        if (acc.type === 'asset' || acc.type === 'expense') {
          bal += p.direction === 'debit' ? p.amountCents : -p.amountCents;
        } else {
          bal += p.direction === 'credit' ? p.amountCents : -p.amountCents;
        }
      }
      return bal;
    }
    return calculateAccountBalance(acc, postings, undefined, entries);
  };

  const totalAssets = accounts
    .filter(
      (a) =>
        a.type === 'asset' &&
        !a.isArchived &&
        a.subType !== 'legacy_clearing' &&
        isEtbCurrency(a.currencyCode)
    )
    .reduce((sum, acc) => sum + computeBalanceForNet(acc), 0);

  const totalLiabilities = accounts
    .filter(
      (a) =>
        a.type === 'liability' &&
        !a.isArchived &&
        a.subType !== 'legacy_clearing' &&
        isEtbCurrency(a.currencyCode)
    )
    .reduce((sum, acc) => sum + computeBalanceForNet(acc), 0);

  return totalAssets - totalLiabilities;
}

export function calculateAvailableToSpend(params: {
  liquidCashCents: number;
  prepaidCardCreditCents?: number;
  shortTermCreditOwedCents?: number;
  unpaidPayablesDueInPeriodCents: number;
  reservedSavingsCents: number;
}): number {
  // Approved Option 1 Formula:
  // AvailableToSpend(H) = LiquidCash + PrepaidCardCredit - ShortTermCreditOwed
  //                     - Unpaid Payables Due in Period - Reserved Savings
  // Receivables & pending inflow commitments are STRICTLY EXCLUDED.
  return (
    params.liquidCashCents +
    (params.prepaidCardCreditCents || 0) -
    (params.shortTermCreditOwedCents || 0) -
    params.unpaidPayablesDueInPeriodCents -
    params.reservedSavingsCents
  );
}

// -------------------------------------------------------------
// Occurrence-Based Reporting (Economic P&L) vs. Cash-Flow Reporting
// -------------------------------------------------------------

export interface OccurrenceReportSummary {
  startDate: string;
  endDate: string;
  totalIncomeCents: number;
  totalExpenseCents: number;
  netSavingsCents: number;
  categoryBreakdown: { [categoryName: string]: number };
}

export interface CashFlowReportSummary {
  startDate: string;
  endDate: string;
  totalCashInflowCents: number;
  totalCashOutflowCents: number;
  netCashFlowCents: number;
  accountBreakdown: { [accountName: string]: { inflow: number; outflow: number } };
}

export function generateOccurrenceReport(params: {
  entries: JournalEntry[];
  postings: Posting[];
  accounts: Account[];
  categories: TransactionCategory[];
  debts?: Debt[];
  allocations?: SettlementAllocation[];
  startDate: string; // YYYY-MM-DD
  endDate: string; // YYYY-MM-DD
}): OccurrenceReportSummary {
  const accountMap = new Map(params.accounts.map((a) => [a.id, a]));
  const entryMap = new Map(params.entries.map((e) => [e.id, e]));
  const classifications = classifyAllJournalEntries({
    accounts: params.accounts,
    entries: params.entries,
    postings: params.postings,
    debts: params.debts,
    allocations: params.allocations,
  });

  let totalIncome = 0;
  let totalExpense = 0;
  const breakdown: { [cat: string]: number } = {};

  for (const p of params.postings) {
    const entry = entryMap.get(p.entryId);
    if (!entry || entry.isVoided) continue;
    if (!(classifications.get(entry.id)?.isEligibleEtb ?? false)) continue;

    // Filter STRICTLY by occurrenceDate
    if (entry.occurrenceDate < params.startDate || entry.occurrenceDate > params.endDate) {
      continue;
    }

    const acc = accountMap.get(p.accountId);
    if (!acc) continue;

    if (acc.type === 'expense') {
      const netExpense = p.direction === 'debit' ? p.amountCents : -p.amountCents;
      totalExpense += netExpense;
      const catName =
        (p.categoryId && findCategoryByIdOrAlias(params.categories, p.categoryId)?.name) ||
        acc.name;
      breakdown[catName] = (breakdown[catName] || 0) + netExpense;
    } else if (acc.type === 'income') {
      const netIncome = p.direction === 'credit' ? p.amountCents : -p.amountCents;
      totalIncome += netIncome;
      const catName =
        (p.categoryId && findCategoryByIdOrAlias(params.categories, p.categoryId)?.name) ||
        acc.name;
      breakdown[catName] = (breakdown[catName] || 0) + netIncome;
    }
  }

  return {
    startDate: params.startDate,
    endDate: params.endDate,
    totalIncomeCents: totalIncome,
    totalExpenseCents: totalExpense,
    netSavingsCents: totalIncome - totalExpense,
    categoryBreakdown: breakdown,
  };
}

export function generateCashFlowReport(params: {
  entries: JournalEntry[];
  postings: Posting[];
  accounts: Account[];
  debts?: Debt[];
  allocations?: SettlementAllocation[];
  startDate: string; // YYYY-MM-DD
  endDate: string; // YYYY-MM-DD
}): CashFlowReportSummary {
  const accountMap = new Map(params.accounts.map((a) => [a.id, a]));
  const entryMap = new Map(params.entries.map((e) => [e.id, e]));
  const classifications = classifyAllJournalEntries({
    accounts: params.accounts,
    entries: params.entries,
    postings: params.postings,
    debts: params.debts,
    allocations: params.allocations,
  });

  let totalInflow = 0;
  let totalOutflow = 0;
  const breakdown: { [acc: string]: { inflow: number; outflow: number } } = {};

  for (const p of params.postings) {
    const entry = entryMap.get(p.entryId);
    if (!entry || entry.isVoided) continue;
    if (!(classifications.get(entry.id)?.isEligibleEtb ?? false)) continue;

    // Filter STRICTLY by accountMovementDate
    if (p.accountMovementDate < params.startDate || p.accountMovementDate > params.endDate) {
      continue;
    }

    const acc = accountMap.get(p.accountId);
    // Cash flow only tracks active ETB liquid Asset accounts (Cash, Bank, Mobile Money; excludes vaults & receivables)
    if (
      !isActiveVerifiedEtbAccount(acc) ||
      acc!.type !== 'asset' ||
      acc!.subType === 'savings_vault' ||
      acc!.subType === 'receivable' ||
      acc!.name.toLowerCase().includes('receivable')
    ) {
      continue;
    }

    const assetAcc = acc!;
    if (!breakdown[assetAcc.name]) {
      breakdown[assetAcc.name] = { inflow: 0, outflow: 0 };
    }

    // Debit to asset is an inflow of funds into the account
    // Credit to asset is an outflow of funds leaving the account
    if (p.direction === 'debit') {
      totalInflow += p.amountCents;
      breakdown[assetAcc.name].inflow += p.amountCents;
    } else if (p.direction === 'credit') {
      totalOutflow += p.amountCents;
      breakdown[assetAcc.name].outflow += p.amountCents;
    }
  }

  return {
    startDate: params.startDate,
    endDate: params.endDate,
    totalCashInflowCents: totalInflow,
    totalCashOutflowCents: totalOutflow,
    netCashFlowCents: totalInflow - totalOutflow,
    accountBreakdown: breakdown,
  };
}

// -------------------------------------------------------------
// Transaction Builders (Natural UX -> Balanced Postings)
// -------------------------------------------------------------

export function buildDirectExpense(params: {
  id: string;
  assetAccountId: string;
  expenseAccountId: string;
  categoryId?: string;
  amountCents: number;
  occurrenceDate: string;
  movementDate: string;
  description: string;
  note?: string;
}): { entry: JournalEntry; postings: Posting[] } {
  const entry: JournalEntry = {
    id: params.id,
    entryType: 'standard',
    description: params.description,
    occurrenceDate: params.occurrenceDate,
    isVoided: false,
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  };

  const postings: Posting[] = [
    {
      id: `${params.id}-post-dr`,
      entryId: params.id,
      accountId: params.expenseAccountId,
      amountCents: params.amountCents,
      direction: 'debit',
      accountMovementDate: params.occurrenceDate,
      categoryId: params.categoryId,
      note: params.note,
    },
    {
      id: `${params.id}-post-cr`,
      entryId: params.id,
      accountId: params.assetAccountId,
      amountCents: params.amountCents,
      direction: 'credit',
      accountMovementDate: params.movementDate,
      note: params.note,
    },
  ];

  validateBalancedEntry(postings);
  return { entry, postings };
}

export function buildDirectIncome(params: {
  id: string;
  assetAccountId: string;
  incomeAccountId: string;
  categoryId?: string;
  amountCents: number;
  occurrenceDate: string;
  movementDate: string;
  description: string;
  note?: string;
}): { entry: JournalEntry; postings: Posting[] } {
  const entry: JournalEntry = {
    id: params.id,
    entryType: 'standard',
    description: params.description,
    occurrenceDate: params.occurrenceDate,
    isVoided: false,
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  };

  const postings: Posting[] = [
    {
      id: `${params.id}-post-dr`,
      entryId: params.id,
      accountId: params.assetAccountId,
      amountCents: params.amountCents,
      direction: 'debit',
      accountMovementDate: params.movementDate,
      note: params.note,
    },
    {
      id: `${params.id}-post-cr`,
      entryId: params.id,
      accountId: params.incomeAccountId,
      amountCents: params.amountCents,
      direction: 'credit',
      accountMovementDate: params.occurrenceDate,
      categoryId: params.categoryId,
      note: params.note,
    },
  ];

  validateBalancedEntry(postings);
  return { entry, postings };
}

export function buildTransfer(params: {
  id: string;
  fromAssetAccountId: string;
  toAssetAccountId: string;
  amountCents: number;
  date: string;
  movementDate?: string;
  description: string;
  transferFeeCents?: number;
  feeExpenseAccountId?: string;
  feeCategoryId?: string;
  note?: string;
}): { entry: JournalEntry; postings: Posting[] } {
  const fee = params.transferFeeCents || 0;
  const effectiveMovementDate = params.movementDate || params.date;
  const entry: JournalEntry = {
    id: params.id,
    entryType: 'transfer',
    description: fee > 0 ? `${params.description} (Fee: ${formatCentsAsInput(fee)} ETB)` : params.description,
    occurrenceDate: params.date,
    isVoided: false,
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  };

  const postings: Posting[] = [
    {
      id: `${params.id}-post-dr-dest`,
      entryId: params.id,
      accountId: params.toAssetAccountId,
      amountCents: params.amountCents,
      direction: 'debit',
      accountMovementDate: effectiveMovementDate,
      note: params.note,
    },
  ];

  if (fee > 0 && params.feeExpenseAccountId) {
    postings.push({
      id: `${params.id}-post-dr-fee`,
      entryId: params.id,
      accountId: params.feeExpenseAccountId,
      amountCents: fee,
      direction: 'debit',
      accountMovementDate: params.date,
      categoryId: params.feeCategoryId,
      note: 'Transfer service fee',
    });
  }

  postings.push({
    id: `${params.id}-post-cr-source`,
    entryId: params.id,
    accountId: params.fromAssetAccountId,
    amountCents: params.amountCents + fee,
    direction: 'credit',
    accountMovementDate: effectiveMovementDate,
    note: params.note,
  });

  validateBalancedEntry(postings);
  return { entry, postings };
}

export function buildVoidEntry(
  targetEntry: JournalEntry,
  reason: string
): { updatedEntry: JournalEntry } {
  return {
    updatedEntry: {
      ...targetEntry,
      isVoided: true,
      voidReason: reason,
    },
  };
}

/**
 * Example A: Someone pays my expense on Day 1.
 * Day 1: Debit Expense, Credit Liability (Payable).
 * Day 5 (Settlement): Debit Liability (Payable), Credit Asset (e.g. CBE).
 */
export function buildThirdPartyPaidExpense(params: {
  entryId: string;
  debtId: string;
  partyId: string;
  expenseAccountId: string;
  payableAccountId: string;
  categoryId?: string;
  amountCents: number;
  occurrenceDate: string; // Day 1
  dueDate?: string;
  description: string;
}): { entry: JournalEntry; postings: Posting[]; debt: Debt } {
  const entry: JournalEntry = {
    id: params.entryId,
    entryType: 'debt_issuance',
    description: params.description,
    occurrenceDate: params.occurrenceDate,
    isVoided: false,
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  };

  const postings: Posting[] = [
    {
      id: `${params.entryId}-post-dr`,
      entryId: params.entryId,
      accountId: params.expenseAccountId,
      amountCents: params.amountCents,
      direction: 'debit',
      accountMovementDate: params.occurrenceDate,
      categoryId: params.categoryId,
    },
    {
      id: `${params.entryId}-post-cr`,
      entryId: params.entryId,
      accountId: params.payableAccountId,
      amountCents: params.amountCents,
      direction: 'credit',
      accountMovementDate: params.occurrenceDate,
    },
  ];

  validateBalancedEntry(postings);

  const debt: Debt = {
    id: params.debtId,
    originEntryId: params.entryId,
    partyId: params.partyId,
    debtType: 'payable',
    principalCents: params.amountCents,
    outstandingCents: params.amountCents,
    dueDate: params.dueDate,
    status: 'active',
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  };

  return { entry, postings, debt };
}

/**
 * Example B: I lend money
 * Debit Asset (Accounts Receivable), Credit Asset (Cash)
 * No expense is created!
 */
export function buildLendMoney(params: {
  entryId: string;
  debtId: string;
  partyId: string;
  receivableAccountId: string;
  sourceAssetAccountId: string;
  amountCents: number;
  date: string;
  dueDate?: string;
  description: string;
}): { entry: JournalEntry; postings: Posting[]; debt: Debt } {
  const entry: JournalEntry = {
    id: params.entryId,
    entryType: 'debt_issuance',
    description: params.description,
    occurrenceDate: params.date,
    isVoided: false,
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  };

  const postings: Posting[] = [
    {
      id: `${params.entryId}-post-dr`,
      entryId: params.entryId,
      accountId: params.receivableAccountId,
      amountCents: params.amountCents,
      direction: 'debit',
      accountMovementDate: params.date,
    },
    {
      id: `${params.entryId}-post-cr`,
      entryId: params.entryId,
      accountId: params.sourceAssetAccountId,
      amountCents: params.amountCents,
      direction: 'credit',
      accountMovementDate: params.date,
    },
  ];

  validateBalancedEntry(postings);

  const debt: Debt = {
    id: params.debtId,
    originEntryId: params.entryId,
    partyId: params.partyId,
    debtType: 'receivable',
    principalCents: params.amountCents,
    outstandingCents: params.amountCents,
    dueDate: params.dueDate,
    status: 'active',
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  };

  return { entry, postings, debt };
}

/**
 * Example C: I borrow money
 * Debit Asset (Telebirr / Cash), Credit Liability (Accounts Payable)
 * No income is created!
 */
export function buildBorrowMoney(params: {
  entryId: string;
  debtId: string;
  partyId: string;
  destAssetAccountId: string;
  payableAccountId: string;
  amountCents: number;
  date: string;
  dueDate?: string;
  description: string;
}): { entry: JournalEntry; postings: Posting[]; debt: Debt } {
  const entry: JournalEntry = {
    id: params.entryId,
    entryType: 'debt_issuance',
    description: params.description,
    occurrenceDate: params.date,
    isVoided: false,
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  };

  const postings: Posting[] = [
    {
      id: `${params.entryId}-post-dr`,
      entryId: params.entryId,
      accountId: params.destAssetAccountId,
      amountCents: params.amountCents,
      direction: 'debit',
      accountMovementDate: params.date,
    },
    {
      id: `${params.entryId}-post-cr`,
      entryId: params.entryId,
      accountId: params.payableAccountId,
      amountCents: params.amountCents,
      direction: 'credit',
      accountMovementDate: params.date,
    },
  ];

  validateBalancedEntry(postings);

  const debt: Debt = {
    id: params.debtId,
    originEntryId: params.entryId,
    partyId: params.partyId,
    debtType: 'payable',
    principalCents: params.amountCents,
    outstandingCents: params.amountCents,
    dueDate: params.dueDate,
    status: 'active',
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  };

  return { entry, postings, debt };
}

/**
 * Example D: Split expense (e.g. Dinner bill 1,000 ETB, my share 400 ETB, colleague owes 600 ETB)
 * Debit Expense: 400 ETB
 * Debit Receivable (Colleague): 600 ETB
 * Credit CBE Bank: 1,000 ETB
 */
export function buildSplitExpense(params: {
  entryId: string;
  debtId: string;
  partyId: string;
  myExpenseAccountId: string;
  receivableAccountId: string;
  paidAssetAccountId: string;
  myShareCents: number;
  theirShareCents: number;
  categoryId?: string;
  occurrenceDate: string;
  dueDate?: string;
  description: string;
}): { entry: JournalEntry; postings: Posting[]; debt: Debt } {
  const totalPaidCents = params.myShareCents + params.theirShareCents;

  const entry: JournalEntry = {
    id: params.entryId,
    entryType: 'split_expense',
    description: params.description,
    occurrenceDate: params.occurrenceDate,
    isVoided: false,
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  };

  const postings: Posting[] = [
    {
      id: `${params.entryId}-post-dr-exp`,
      entryId: params.entryId,
      accountId: params.myExpenseAccountId,
      amountCents: params.myShareCents,
      direction: 'debit',
      accountMovementDate: params.occurrenceDate,
      categoryId: params.categoryId,
    },
    {
      id: `${params.entryId}-post-dr-rec`,
      entryId: params.entryId,
      accountId: params.receivableAccountId,
      amountCents: params.theirShareCents,
      direction: 'debit',
      accountMovementDate: params.occurrenceDate,
    },
    {
      id: `${params.entryId}-post-cr-asset`,
      entryId: params.entryId,
      accountId: params.paidAssetAccountId,
      amountCents: totalPaidCents,
      direction: 'credit',
      accountMovementDate: params.occurrenceDate,
    },
  ];

  validateBalancedEntry(postings);

  const debt: Debt = {
    id: params.debtId,
    originEntryId: params.entryId,
    partyId: params.partyId,
    debtType: 'receivable',
    principalCents: params.theirShareCents,
    outstandingCents: params.theirShareCents,
    dueDate: params.dueDate,
    status: 'active',
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  };

  return { entry, postings, debt };
}

/**
 * Example E: Debt Settlement (with optional separated interest).
 * Handles:
 * - Repaying our payable (we pay money)
 * - Collecting repayment of our receivable (they pay us)
 * - Multiple debts settled in one transaction
 */
export function buildDebtSettlement(params: {
  settlementEntryId: string;
  debt: Debt;
  settlementAccountId: string; // The liquid cash/bank account
  debtAccountId: string; // Accounts Receivable (Asset) or Accounts Payable (Liability)
  allocatedPrincipalCents: number;
  interestCents?: number; // Optional interest
  interestAccountId?: string; // Interest Income or Interest Expense account
  feeCents?: number; // Optional transfer/settlement fee (Expense)
  feeAccountId?: string;
  settlementDate: string;
  description: string;
}): {
  entry: JournalEntry;
  postings: Posting[];
  allocation: SettlementAllocation;
  updatedDebt: Debt;
} {
  if (params.debt.status !== 'active') {
    throw new DoubleEntryValidationError(
      `Cannot settle debt in status "${params.debt.status}".`
    );
  }
  if (
    !Number.isInteger(params.allocatedPrincipalCents) ||
    params.allocatedPrincipalCents <= 0
  ) {
    throw new DoubleEntryValidationError(
      `Allocated principal must be positive, got ${params.allocatedPrincipalCents}.`
    );
  }
  if (params.allocatedPrincipalCents > params.debt.outstandingCents) {
    throw new DoubleEntryValidationError(
      `Over-allocation rejected: ${params.allocatedPrincipalCents} exceeds outstanding ${params.debt.outstandingCents}.`
    );
  }

  const interest = params.interestCents || 0;
  const fee = params.feeCents || 0;
  if (interest < 0 || fee < 0) {
    throw new DoubleEntryValidationError('Interest and fee cents must be non-negative.');
  }
  if (interest > 0 && !params.interestAccountId) {
    throw new DoubleEntryValidationError('interestAccountId is required when interestCents > 0.');
  }
  if (fee > 0 && !params.feeAccountId) {
    throw new DoubleEntryValidationError('feeAccountId is required when feeCents > 0.');
  }

  const isPayable = params.debt.debtType === 'payable';

  const entry: JournalEntry = {
    id: params.settlementEntryId,
    entryType: 'settlement',
    description: params.description,
    occurrenceDate: params.settlementDate,
    isVoided: false,
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  };

  const postings: Posting[] = [];

  if (isPayable) {
    postings.push({
      id: `${params.settlementEntryId}-dr-payable`,
      entryId: params.settlementEntryId,
      accountId: params.debtAccountId,
      amountCents: params.allocatedPrincipalCents,
      direction: 'debit',
      accountMovementDate: params.settlementDate,
    });

    if (interest > 0 && params.interestAccountId) {
      postings.push({
        id: `${params.settlementEntryId}-dr-interest`,
        entryId: params.settlementEntryId,
        accountId: params.interestAccountId,
        amountCents: interest,
        direction: 'debit',
        accountMovementDate: params.settlementDate,
      });
    }

    if (fee > 0 && params.feeAccountId) {
      postings.push({
        id: `${params.settlementEntryId}-dr-fee`,
        entryId: params.settlementEntryId,
        accountId: params.feeAccountId,
        amountCents: fee,
        direction: 'debit',
        accountMovementDate: params.settlementDate,
      });
    }

    postings.push({
      id: `${params.settlementEntryId}-cr-asset`,
      entryId: params.settlementEntryId,
      accountId: params.settlementAccountId,
      amountCents: params.allocatedPrincipalCents + interest + fee,
      direction: 'credit',
      accountMovementDate: params.settlementDate,
    });
  } else {
    postings.push({
      id: `${params.settlementEntryId}-dr-asset`,
      entryId: params.settlementEntryId,
      accountId: params.settlementAccountId,
      amountCents: params.allocatedPrincipalCents + interest,
      direction: 'debit',
      accountMovementDate: params.settlementDate,
    });

    postings.push({
      id: `${params.settlementEntryId}-cr-receivable`,
      entryId: params.settlementEntryId,
      accountId: params.debtAccountId,
      amountCents: params.allocatedPrincipalCents,
      direction: 'credit',
      accountMovementDate: params.settlementDate,
    });

    if (interest > 0 && params.interestAccountId) {
      postings.push({
        id: `${params.settlementEntryId}-cr-interest`,
        entryId: params.settlementEntryId,
        accountId: params.interestAccountId,
        amountCents: interest,
        direction: 'credit',
        accountMovementDate: params.settlementDate,
      });
    }

    if (fee > 0 && params.feeAccountId) {
      postings.push({
        id: `${params.settlementEntryId}-dr-fee`,
        entryId: params.settlementEntryId,
        accountId: params.feeAccountId,
        amountCents: fee,
        direction: 'debit',
        accountMovementDate: params.settlementDate,
      });
      postings.push({
        id: `${params.settlementEntryId}-cr-fee-asset`,
        entryId: params.settlementEntryId,
        accountId: params.settlementAccountId,
        amountCents: fee,
        direction: 'credit',
        accountMovementDate: params.settlementDate,
      });
    }
  }

  validateBalancedEntry(postings);

  const allocation: SettlementAllocation = {
    id: `alloc-${params.settlementEntryId}`,
    settlementEntryId: params.settlementEntryId,
    debtId: params.debt.id,
    allocatedCents: params.allocatedPrincipalCents,
    settlementDate: params.settlementDate,
  };

  const newOutstanding = Math.max(0, params.debt.outstandingCents - params.allocatedPrincipalCents);
  const updatedDebt: Debt = {
    ...params.debt,
    outstandingCents: newOutstanding,
    status: newOutstanding === 0 ? 'settled' : 'active',
  };

  return { entry, postings, allocation, updatedDebt };
}

/**
 * Debt Forgiveness / Write-Off
 */
export function buildDebtWriteOff(params: {
  writeOffEntryId: string;
  debt: Debt;
  debtAccountId: string;
  writeOffAccountId: string; // Expense: Bad Debt (if receivable) OR Income: Forgiveness (if payable)
  writeOffCents: number;
  date: string;
  reason: string;
}): {
  entry: JournalEntry;
  postings: Posting[];
  updatedDebt: Debt;
} {
  const isPayable = params.debt.debtType === 'payable';

  const entry: JournalEntry = {
    id: params.writeOffEntryId,
    entryType: 'write_off',
    description: `Debt Write-off / Forgiveness: ${params.reason}`,
    occurrenceDate: params.date,
    isVoided: false,
    createdAt: EthiopiaClock.nowUtc().toISOString(),
  };

  const postings: Posting[] = [];

  if (isPayable) {
    // Lender forgave what I owed
    // Debit Liability: Payable
    postings.push({
      id: `${params.writeOffEntryId}-dr-payable`,
      entryId: params.writeOffEntryId,
      accountId: params.debtAccountId,
      amountCents: params.writeOffCents,
      direction: 'debit',
      accountMovementDate: params.date,
    });
    // Credit Income: Debt Forgiveness
    postings.push({
      id: `${params.writeOffEntryId}-cr-income`,
      entryId: params.writeOffEntryId,
      accountId: params.writeOffAccountId,
      amountCents: params.writeOffCents,
      direction: 'credit',
      accountMovementDate: params.date,
    });
  } else {
    // I forgive borrower's debt
    // Debit Expense: Bad Debt
    postings.push({
      id: `${params.writeOffEntryId}-dr-expense`,
      entryId: params.writeOffEntryId,
      accountId: params.writeOffAccountId,
      amountCents: params.writeOffCents,
      direction: 'debit',
      accountMovementDate: params.date,
    });
    // Credit Asset: Receivable
    postings.push({
      id: `${params.writeOffEntryId}-cr-receivable`,
      entryId: params.writeOffEntryId,
      accountId: params.debtAccountId,
      amountCents: params.writeOffCents,
      direction: 'credit',
      accountMovementDate: params.date,
    });
  }

  validateBalancedEntry(postings);

  const newOutstanding = Math.max(0, params.debt.outstandingCents - params.writeOffCents);
  const updatedDebt: Debt = {
    ...params.debt,
    outstandingCents: newOutstanding,
    status: newOutstanding === 0 ? 'written_off' : 'active',
    writeOffEntryId: newOutstanding === 0 ? params.writeOffEntryId : params.debt.writeOffEntryId,
  };

  return { entry, postings, updatedDebt };
}

// -------------------------------------------------------------
// Category Budgets & Spending Limits
// -------------------------------------------------------------

export interface CategoryBudget {
  categoryId: string;
  categoryName: string;
  limitCents: number;
}

export interface BudgetStatus {
  categoryId: string;
  categoryName: string;
  limitCents: number;
  spentCents: number;
  remainingCents: number;
  percentageUsed: number;
  isOverBudget: boolean;
  isWarning: boolean; // >= 80%
}

export function calculateBudgetStatus(
  budgets: CategoryBudget[],
  occurrenceReport: OccurrenceReportSummary
): BudgetStatus[] {
  return budgets.map((b) => {
    // Look up spent amount by category name in occurrence report
    const spentCents = occurrenceReport.categoryBreakdown[b.categoryName] || 0;
    const remainingCents = b.limitCents - spentCents;
    const percentageUsed = b.limitCents > 0 ? Math.round((spentCents / b.limitCents) * 100) : 0;
    return {
      categoryId: b.categoryId,
      categoryName: b.categoryName,
      limitCents: b.limitCents,
      spentCents,
      remainingCents,
      percentageUsed,
      isOverBudget: spentCents > b.limitCents,
      isWarning: percentageUsed >= 80 && spentCents <= b.limitCents,
    };
  });
}

// -------------------------------------------------------------
// Quick Capture Text Parser for Expenses (<3 seconds)
// -------------------------------------------------------------

export interface QuickCaptureParsedExpense {
  amountCents: number;
  description: string;
  assetAccountId: string;
  categoryId: string;
  categoryName: string;
  rejectedCurrency?: string;
  error?: string;
}

const UNSAFE_FOREIGN_SYMBOL_REGEX = /([$€£¥₹₦₩₽₺₴₫₱₪฿₵₮])/;
const UNAMBIGUOUS_FX_CODE_REGEX =
  /\b(USD|EUR|GBP|KES|KSH|AED|SAR|JPY|CNY|RMB|CHF|CAD|AUD|ZAR|INR|UGX|TZS|RWF|ERN|DJF|SDG|SOS|EGP|NGN|GHS|USDT|USDC)\b/i;
const ADJACENT_UPPER_ISO_REGEX =
  /(?:(?:\d[\d,]*(?:\.\d{1,2})?\s*([A-Z]{3}))|(?:([A-Z]{3})\s*\d[\d,]*(?:\.\d{1,2})?))\b/g;

export function detectUnsupportedCurrencyToken(rawText: string): string | null {
  const text = rawText.trim();
  if (!text) return null;

  const symbolMatch = UNSAFE_FOREIGN_SYMBOL_REGEX.exec(text);
  if (symbolMatch) {
    if (symbolMatch[1] === '$') return 'USD ($)';
    if (symbolMatch[1] === '€') return 'EUR (€)';
    if (symbolMatch[1] === '£') return 'GBP (£)';
    return symbolMatch[1];
  }

  const fxMatch = UNAMBIGUOUS_FX_CODE_REGEX.exec(text);
  if (fxMatch) {
    return fxMatch[1].toUpperCase();
  }

  let adjMatch: RegExpExecArray | null;
  ADJACENT_UPPER_ISO_REGEX.lastIndex = 0;
  while ((adjMatch = ADJACENT_UPPER_ISO_REGEX.exec(text)) !== null) {
    const code = (adjMatch[1] || adjMatch[2] || '').trim();
    if (code && code !== 'ETB' && classifyCurrencyCode(code) === 'verified_non_etb') {
      return code;
    }
  }

  return null;
}

export function parseQuickCaptureExpense(
  rawText: string,
  defaultAssetAccountId: string = 'acc-cbe',
  accounts: Account[] = [],
  categories: TransactionCategory[] = []
): QuickCaptureParsedExpense {
  const text = rawText.trim();
  const rawExpenseCategories = (
    categories.length > 0 ? categories : FOUNDATION_DEFAULT_EXPENSE_CATEGORIES
  ).filter((c) => c.type === 'expense' && !c.isArchived);
  const activeCategories: TransactionCategory[] =
    rawExpenseCategories.length > 0
      ? rawExpenseCategories
      : FOUNDATION_DEFAULT_EXPENSE_CATEGORIES;
  const fallbackCategory: TransactionCategory =
    activeCategories.find((c) => c.id === CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID) ||
    activeCategories.find((c) => resolveCanonicalCategoryId(c.id) === CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID) ||
    activeCategories.find((c) => c.isDefault) ||
    activeCategories[0] || {
      id: CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID,
      name: 'Other',
      type: 'expense',
      colorHex: '#94A3B8',
      isDefault: true,
    };

  const rejectedCurrency = detectUnsupportedCurrencyToken(text);
  if (rejectedCurrency) {
    return {
      amountCents: 0,
      description: text,
      assetAccountId: '',
      categoryId: fallbackCategory.id,
      categoryName: fallbackCategory.name,
      rejectedCurrency,
      error: `Only ETB amounts are supported in Quick Capture (detected ${rejectedCurrency}).`,
    };
  }

  // Regex to extract initial or embedded amount (e.g. "150 lunch telebirr", "coffee 45 cbe", "1,200.50 rent")
  const amountMatch = text.match(/(?:ETB\s*)?(\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)/i);

  let amountCents = 0;
  let remainingText = text;

  if (amountMatch) {
    const numStr = amountMatch[1].replace(/,/g, '');
    const parsed = parseDecimalToCentsStrict(numStr);
    amountCents = parsed.valid ? parsed.cents : 0;
    remainingText = text.replace(amountMatch[0], '').trim();
  }

  // Restrict quick-capture target detection strictly to active Verified ETB accounts
  const fallbackAccounts: Account[] = [
    { id: 'acc-cbe', name: 'CBE Bank Account', type: 'asset' as const, currencyCode: 'ETB', isArchived: false, createdAt: '' },
    { id: 'acc-telebirr', name: 'Telebirr Mobile Wallet', type: 'asset' as const, currencyCode: 'ETB', isArchived: false, createdAt: '' },
    { id: 'acc-cash', name: 'Cash on Hand Wallet', type: 'asset' as const, currencyCode: 'ETB', isArchived: false, createdAt: '' },
  ];
  const activeAccounts =
    accounts.length > 0
      ? accounts.filter((a) => isActiveVerifiedEtbAccount(a))
      : fallbackAccounts;

  // Detect account from keywords
  const lower = remainingText.toLowerCase();
  const defaultIsValid = activeAccounts.some((a) => a.id === defaultAssetAccountId);
  let matchedAccountId = defaultIsValid
    ? defaultAssetAccountId
    : activeAccounts[0]?.id || defaultAssetAccountId;

  for (const acc of activeAccounts) {
    const accLower = acc.name.toLowerCase();
    if (
      (accLower.includes('telebirr') && (lower.includes('telebirr') || lower.includes('tele'))) ||
      (accLower.includes('cbe') && (lower.includes('cbe') || lower.includes('ንግድ'))) ||
      (accLower.includes('cash') && (lower.includes('cash') || lower.includes('ጥሬ'))) ||
      (accLower.includes('dashen') && (lower.includes('dashen') || lower.includes('ዳሽን'))) ||
      (accLower.includes('abyssinia') && (lower.includes('boa') || lower.includes('abyssinia')))
    ) {
      matchedAccountId = acc.id;
      break;
    }
  }

  // Clean matched account keywords from description
  let cleanedDesc = remainingText
    .replace(/\b(telebirr|cbe|cash|boa|dashen)\b/gi, '')
    .trim();
  if (!cleanedDesc) cleanedDesc = 'Quick expense';

  // Detect active non-archived expense category using canonical keywords + custom category names
  let matchedCategoryId = fallbackCategory.id;
  let matchedCategoryName = fallbackCategory.name;
  const dLower = cleanedDesc.toLowerCase();

  const findCat = (predicate: (c: TransactionCategory, cLower: string) => boolean) =>
    activeCategories.find((c) => predicate(c, c.name.toLowerCase()));

  let matchedCat: TransactionCategory | undefined;
  if (
    dLower.includes('lunch') ||
    dLower.includes('dinner') ||
    dLower.includes('food') ||
    dLower.includes('dining') ||
    dLower.includes('coffee') ||
    dLower.includes('breakfast') ||
    dLower.includes('ሻይ') ||
    dLower.includes('ምግብ')
  ) {
    matchedCat =
      findCat((_, cl) => cl.includes('dining')) ||
      findCat((c, cl) => c.id === 'cat-food' || cl.includes('food') || cl.includes('ምግብ'));
  } else if (
    dLower.includes('grocery') ||
    dLower.includes('groceries') ||
    dLower.includes('market') ||
    dLower.includes('teff') ||
    dLower.includes('ዘይት') ||
    dLower.includes('ሽንኩርት')
  ) {
    matchedCat =
      findCat((_, cl) => cl.includes('grocer') || cl.includes('ሸቀጥ')) ||
      findCat((c, cl) => c.id === 'cat-food' || cl.includes('food') || cl.includes('ምግብ'));
  } else if (
    dLower.includes('rent') ||
    dLower.includes('housing') ||
    dLower.includes('house') ||
    dLower.includes('ቤት') ||
    dLower.includes('ኪራይ')
  ) {
    matchedCat = findCat(
      (c, cl) =>
        c.id === 'cat-housing' ||
        cl.includes('housing') ||
        cl.includes('rent') ||
        cl.includes('ኪራይ')
    );
  } else if (
    dLower.includes('transport') ||
    dLower.includes('taxi') ||
    dLower.includes('ride') ||
    dLower.includes('fuel') ||
    dLower.includes('bajaj') ||
    dLower.includes('ነዳጅ') ||
    dLower.includes('ታክሲ')
  ) {
    matchedCat = findCat(
      (c, cl) => c.id === 'cat-transport' || cl.includes('transport') || cl.includes('ነዳጅ')
    );
  } else if (
    dLower.includes('electric') ||
    dLower.includes('water') ||
    dLower.includes('utility') ||
    dLower.includes('utilities') ||
    dLower.includes('power') ||
    dLower.includes('ውሃ') ||
    dLower.includes('መብራት')
  ) {
    matchedCat = findCat((c, cl) => c.id === 'cat-utilities' || cl.includes('utilit'));
  } else if (
    dLower.includes('internet') ||
    dLower.includes('airtime') ||
    dLower.includes('telecom') ||
    dLower.includes('ethio') ||
    dLower.includes('data') ||
    dLower.includes('phone') ||
    dLower.includes('wifi') ||
    dLower.includes('ካርድ') ||
    dLower.includes('ስልክ')
  ) {
    matchedCat = findCat(
      (c, cl) => c.id === 'cat-comm' || cl.includes('comm') || cl.includes('telecom')
    );
  }

  if (!matchedCat) {
    matchedCat = activeCategories.find((c) => {
      if (
        c.isDefault ||
        resolveCanonicalCategoryId(c.id) === CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID
      ) {
        return false;
      }
      const tokens = c.name
        .toLowerCase()
        .split(/[^a-z0-9\u1200-\u137f]+/)
        .filter((t) => t.length >= 3);
      return tokens.some((token) => dLower.includes(token));
    });
  }

  if (matchedCat) {
    matchedCategoryId = matchedCat.id;
    matchedCategoryName = matchedCat.name;
  }

  return {
    amountCents,
    description: cleanedDesc,
    assetAccountId: matchedAccountId,
    categoryId: matchedCategoryId,
    categoryName: matchedCategoryName,
  };
}

// -------------------------------------------------------------
// Transaction Filtering & Search
// -------------------------------------------------------------

export interface TransactionFilterParams {
  query?: string;
  accountId?: string;
  categoryId?: string;
  entryType?: EntryType;
  startDate?: string;
  endDate?: string;
  minAmountCents?: number;
  maxAmountCents?: number;
}

export function filterJournalEntries(
  entries: JournalEntry[],
  postings: Posting[],
  params: TransactionFilterParams
): JournalEntry[] {
  const entryPostingsMap = new Map<string, Posting[]>();
  for (const p of postings) {
    const list = entryPostingsMap.get(p.entryId) || [];
    list.push(p);
    entryPostingsMap.set(p.entryId, list);
  }

  return entries.filter((entry) => {
    // Text search query
    if (params.query) {
      const q = params.query.toLowerCase();
      const matchDesc = entry.description.toLowerCase().includes(q);
      const postMatch = (entryPostingsMap.get(entry.id) || []).some(
        (p) => p.note?.toLowerCase().includes(q)
      );
      if (!matchDesc && !postMatch) return false;
    }

    // Date range
    if (params.startDate && entry.occurrenceDate < params.startDate) return false;
    if (params.endDate && entry.occurrenceDate > params.endDate) return false;

    // Entry type
    if (params.entryType && entry.entryType !== params.entryType) return false;

    // Postings-level checks (Account, Category, Amount)
    const entryPostings = entryPostingsMap.get(entry.id) || [];

    if (params.accountId) {
      const hasAccount = entryPostings.some((p) => p.accountId === params.accountId);
      if (!hasAccount) return false;
    }

    if (params.categoryId) {
      const hasCategory = entryPostings.some((p) =>
        categoryIdsMatchOrAlias(p.categoryId, params.categoryId)
      );
      if (!hasCategory) return false;
    }

    if (params.minAmountCents != null) {
      const maxPosting = Math.max(...entryPostings.map((p) => p.amountCents), 0);
      if (maxPosting < params.minAmountCents) return false;
    }

    if (params.maxAmountCents != null) {
      const minPosting = Math.min(...entryPostings.map((p) => p.amountCents), Infinity);
      if (minPosting > params.maxAmountCents) return false;
    }

    return true;
  });
}

// -------------------------------------------------------------
// Period Comparison & Financial Analytics Engine (Section 7)
// -------------------------------------------------------------

export interface MetricComparison {
  previous: number;
  current: number;
  difference: number;
  percentageChange: number | null;
  percentageDisplay: string;
}

export interface CategoryComparisonItem {
  categoryId: string;
  categoryName: string;
  categoryType: 'income' | 'expense';
  previousCents: number;
  currentCents: number;
  differenceCents: number;
  percentageChange: number | null;
  percentageDisplay: string;
}

export interface PeriodComparisonResult {
  periodLabel: string;
  previousPeriodLabel: string;
  currentDateRange: { start: string; end: string };
  previousDateRange: { start: string; end: string };
  daysInCurrentPeriod: number;
  daysInPreviousPeriod: number;
  totalIncome: MetricComparison;
  totalExpenses: MetricComparison;
  netCashFlow: MetricComparison;
  transactionCount: MetricComparison;
  averageDailySpending: MetricComparison;
  categories: CategoryComparisonItem[];
  selectedCategoryResult?: CategoryComparisonItem;
}

/**
 * Calculates percentage change safely preventing division by zero or NaN
 */
export function calculateSafePercentageChange(
  previous: number,
  current: number
): { percentageChange: number | null; percentageDisplay: string } {
  if (previous === 0 && current === 0) {
    return { percentageChange: 0, percentageDisplay: '0.0%' };
  }
  if (previous === 0) {
    if (current > 0) {
      return { percentageChange: 100, percentageDisplay: '+100% (New)' };
    } else {
      return { percentageChange: -100, percentageDisplay: '-100%' };
    }
  }

  const change = ((current - previous) / Math.abs(previous)) * 100;
  const sign = change > 0 ? '+' : '';
  return {
    percentageChange: Math.round(change * 10) / 10,
    percentageDisplay: `${sign}${change.toFixed(1)}%`,
  };
}

/**
 * Generates exact Gregorian/Ethiopian equivalent comparison date ranges.
 * Uses Monday as the start of the week per Section 7.1.
 */
export function getComparisonDateRanges(
  type: 'daily' | 'weekly' | 'monthly' | 'yearly',
  baseDate?: Date
): {
  currentStart: string;
  currentEnd: string;
  previousStart: string;
  previousEnd: string;
  periodLabel: string;
  previousPeriodLabel: string;
} {
  const baseCal = baseDate
    ? CalendarDate.fromUtcInstantInEthiopia(baseDate)
    : CalendarDate.today();

  if (type === 'daily') {
    const yesterday = baseCal.subtractDays(1);
    return {
      currentStart: baseCal.toIsoString(),
      currentEnd: baseCal.toIsoString(),
      previousStart: yesterday.toIsoString(),
      previousEnd: yesterday.toIsoString(),
      periodLabel: 'Today',
      previousPeriodLabel: 'Yesterday',
    };
  }

  if (type === 'weekly') {
    // Monday (weekday 1) as start of week -> 0..6 offset
    const dayOfWeek = baseCal.weekday - 1;
    const currentMon = baseCal.subtractDays(dayOfWeek);
    const prevMon = currentMon.subtractDays(7);
    const prevEquivalentDay = prevMon.addDays(dayOfWeek);

    return {
      currentStart: currentMon.toIsoString(),
      currentEnd: baseCal.toIsoString(),
      previousStart: prevMon.toIsoString(),
      previousEnd: prevEquivalentDay.toIsoString(),
      periodLabel: 'This Week (Mon-Today)',
      previousPeriodLabel: 'Last Week (Equivalent Days)',
    };
  }

  if (type === 'monthly') {
    const currentStart = baseCal.startOfGregorianMonth;
    const prevRef = baseCal.previousGregorianMonth();
    const prevStart = prevRef.startOfGregorianMonth;

    return {
      currentStart: currentStart.toIsoString(),
      currentEnd: baseCal.toIsoString(),
      previousStart: prevStart.toIsoString(),
      previousEnd: prevRef.toIsoString(),
      periodLabel: 'This Month to Date',
      previousPeriodLabel: 'Last Month to Date',
    };
  }

  // Yearly
  const currentStart = baseCal.startOfGregorianYear;
  const prevEnd = baseCal.previousGregorianYear();
  const prevStart = prevEnd.startOfGregorianYear;

  return {
    currentStart: currentStart.toIsoString(),
    currentEnd: baseCal.toIsoString(),
    previousStart: prevStart.toIsoString(),
    previousEnd: prevEnd.toIsoString(),
    periodLabel: 'This Year to Date',
    previousPeriodLabel: 'Last Year to Date',
  };
}

/**
 * Calculates Period Comparison and category spending analytics
 */
export function calculatePeriodComparison(params: {
  currentStart: string;
  currentEnd: string;
  previousStart: string;
  previousEnd: string;
  periodLabel?: string;
  previousPeriodLabel?: string;
  entries: JournalEntry[];
  postings: Posting[];
  accounts: Account[];
  categories: TransactionCategory[];
  debts?: Debt[];
  allocations?: SettlementAllocation[];
  selectedCategoryId?: string;
}): PeriodComparisonResult {
  const voidedEntryIds = new Set(params.entries.filter((e) => e.isVoided).map((e) => e.id));
  const entryDateMap = new Map(params.entries.map((e) => [e.id, e.occurrenceDate]));
  const classifications = classifyAllJournalEntries({
    accounts: params.accounts,
    entries: params.entries,
    postings: params.postings,
    debts: params.debts,
    allocations: params.allocations,
  });

  // Account type map
  const accountTypeMap = new Map(params.accounts.map((a) => [a.id, a.type]));

  // Helper to aggregate ETB-eligible postings in date range
  const aggregate = (start: string, end: string) => {
    let incomeCents = 0;
    let expenseCents = 0;
    const activeEntryIds = new Set<string>();
    const categoryTotals = new Map<string, number>();

    for (const p of params.postings) {
      if (voidedEntryIds.has(p.entryId)) continue;
      if (!(classifications.get(p.entryId)?.isEligibleEtb ?? false)) continue;
      const occDate = entryDateMap.get(p.entryId) || p.accountMovementDate;
      if (occDate < start || occDate > end) continue;

      activeEntryIds.add(p.entryId);
      const accType = accountTypeMap.get(p.accountId);

      if (accType === 'expense') {
        const netExpense = p.direction === 'debit' ? p.amountCents : -p.amountCents;
        expenseCents += netExpense;
        const catId = p.categoryId || CANONICAL_DEFAULT_EXPENSE_CATEGORY_ID;
        categoryTotals.set(catId, (categoryTotals.get(catId) || 0) + netExpense);
      } else if (accType === 'income') {
        const netIncome = p.direction === 'credit' ? p.amountCents : -p.amountCents;
        incomeCents += netIncome;
        const catId = p.categoryId || CANONICAL_DEFAULT_INCOME_CATEGORY_ID;
        categoryTotals.set(catId, (categoryTotals.get(catId) || 0) + netIncome);
      }
    }

    const startCal = CalendarDate.tryParse(start);
    const endCal = CalendarDate.tryParse(end);
    const days =
      startCal && endCal && !endCal.isBefore(startCal)
        ? new DateRange(startCal, endCal).lengthInDays
        : 1;

    return {
      incomeCents,
      expenseCents,
      netCashFlowCents: incomeCents - expenseCents,
      txCount: activeEntryIds.size,
      days,
      averageDailySpendingCents: Math.round(expenseCents / days),
      categoryTotals,
    };
  };

  const curr = aggregate(params.currentStart, params.currentEnd);
  const prev = aggregate(params.previousStart, params.previousEnd);

  const makeMetric = (prevVal: number, currVal: number): MetricComparison => {
    const diff = currVal - prevVal;
    const pct = calculateSafePercentageChange(prevVal, currVal);
    return {
      previous: prevVal,
      current: currVal,
      difference: diff,
      percentageChange: pct.percentageChange,
      percentageDisplay: pct.percentageDisplay,
    };
  };

  // Compare categories
  const allCategoryIds = new Set([
    ...params.categories.map((c) => c.id),
    ...curr.categoryTotals.keys(),
    ...prev.categoryTotals.keys(),
  ]);

  const catComparisons: CategoryComparisonItem[] = [];

  for (const catId of allCategoryIds) {
    const catObj = findCategoryByIdOrAlias(params.categories, catId);
    const catName = catObj ? catObj.name : catId;
    const catType = catObj ? catObj.type : 'expense';

    const pCents = prev.categoryTotals.get(catId) || 0;
    const cCents = curr.categoryTotals.get(catId) || 0;
    if (pCents === 0 && cCents === 0) continue; // Skip unused categories

    const diff = cCents - pCents;
    const pct = calculateSafePercentageChange(pCents, cCents);

    catComparisons.push({
      categoryId: catId,
      categoryName: catName,
      categoryType: catType,
      previousCents: pCents,
      currentCents: cCents,
      differenceCents: diff,
      percentageChange: pct.percentageChange,
      percentageDisplay: pct.percentageDisplay,
    });
  }

  catComparisons.sort((a, b) => b.currentCents - a.currentCents);

  let selectedCategoryResult: CategoryComparisonItem | undefined;
  if (params.selectedCategoryId) {
    selectedCategoryResult = catComparisons.find((c) =>
      categoryIdsMatchOrAlias(c.categoryId, params.selectedCategoryId)
    );
    if (!selectedCategoryResult) {
      const catObj = findCategoryByIdOrAlias(params.categories, params.selectedCategoryId);
      const catName = catObj ? catObj.name : params.selectedCategoryId;
      const catType = catObj ? catObj.type : 'expense';
      const pCents = prev.categoryTotals.get(params.selectedCategoryId) || 0;
      const cCents = curr.categoryTotals.get(params.selectedCategoryId) || 0;
      const diff = cCents - pCents;
      const pct = calculateSafePercentageChange(pCents, cCents);

      selectedCategoryResult = {
        categoryId: params.selectedCategoryId,
        categoryName: catName,
        categoryType: catType,
        previousCents: pCents,
        currentCents: cCents,
        differenceCents: diff,
        percentageChange: pct.percentageChange,
        percentageDisplay: pct.percentageDisplay,
      };
    }
  }

  return {
    periodLabel: params.periodLabel || `${params.currentStart} to ${params.currentEnd}`,
    previousPeriodLabel: params.previousPeriodLabel || `${params.previousStart} to ${params.previousEnd}`,
    currentDateRange: { start: params.currentStart, end: params.currentEnd },
    previousDateRange: { start: params.previousStart, end: params.previousEnd },
    daysInCurrentPeriod: curr.days,
    daysInPreviousPeriod: prev.days,
    totalIncome: makeMetric(prev.incomeCents, curr.incomeCents),
    totalExpenses: makeMetric(prev.expenseCents, curr.expenseCents),
    netCashFlow: makeMetric(prev.netCashFlowCents, curr.netCashFlowCents),
    transactionCount: makeMetric(prev.txCount, curr.txCount),
    averageDailySpending: makeMetric(prev.averageDailySpendingCents, curr.averageDailySpendingCents),
    categories: catComparisons,
    selectedCategoryResult,
  };
}

// -------------------------------------------------------------
// Remembered Descriptions & Category Suggestions (Section 4.4)
// -------------------------------------------------------------

export interface RememberedDescriptionEntry {
  description: string;
  categoryId: string;
  count: number;
  lastUsedAt: string;
}

export class RememberedDescriptionsService {
  /**
   * Records a description and its category pairing.
   */
  static recordUsage(
    map: Record<string, RememberedDescriptionEntry>,
    description: string,
    categoryId: string
  ): Record<string, RememberedDescriptionEntry> {
    const trimmed = description.trim();
    if (!trimmed || !categoryId) return map;

    const key = trimmed.toLowerCase();
    const existing = map[key];

    return {
      ...map,
      [key]: {
        description: trimmed,
        categoryId: categoryId,
        count: (existing?.count || 0) + 1,
        lastUsedAt: EthiopiaClock.nowUtc().toISOString(),
      },
    };
  }

  /**
   * Suggests previous category for a given description.
   */
  static getSuggestedCategory(
    map: Record<string, RememberedDescriptionEntry>,
    description: string
  ): string | undefined {
    const key = description.trim().toLowerCase();
    return map[key]?.categoryId;
  }

  /**
   * Returns matching description suggestions for auto-complete while typing.
   */
  static getMatchingDescriptions(
    map: Record<string, RememberedDescriptionEntry>,
    query: string,
    limit: number = 5
  ): RememberedDescriptionEntry[] {
    const q = query.trim().toLowerCase();
    if (!q) return [];

    return Object.values(map)
      .filter((item) => item.description.toLowerCase().includes(q))
      .sort((a, b) => b.count - a.count)
      .slice(0, limit);
  }
}

// ============================================================================
// SIMPLIFIED FOUNDATION FOR TASKS 21–25
// ============================================================================

export type SimpleTransactionType = 'expense' | 'income' | 'transfer';

export interface SimpleTransaction {
  id: string;
  type: SimpleTransactionType;
  amountCents: number;
  accountId: string; // source / affected account
  categoryId?: string; // mandatory for expense and income
  destinationAccountId?: string; // mandatory for transfer
  description?: string; // optional
  payee?: string; // optional
  transactionDate: string; // YYYY-MM-DD
  createdAt: string; // ISO 8601
  updatedAt?: string;
  journalEntryId?: string;
  isSuperseded?: boolean;
}

/**
 * Task 23.4 Default Categories
 */
export const FOUNDATION_DEFAULT_EXPENSE_CATEGORIES: TransactionCategory[] = [
  { id: 'cat-food', name: 'Food', type: 'expense', colorHex: '#EF4444' },
  { id: 'cat-transport', name: 'Transport', type: 'expense', colorHex: '#F97316' },
  { id: 'cat-housing', name: 'Housing', type: 'expense', colorHex: '#F59E0B' },
  { id: 'cat-utilities', name: 'Utilities', type: 'expense', colorHex: '#EAB308' },
  { id: 'cat-comm', name: 'Communication', type: 'expense', colorHex: '#84CC16' },
  { id: 'cat-other-exp', name: 'Other', type: 'expense', colorHex: '#94A3B8', isDefault: true },
];

export const FOUNDATION_DEFAULT_INCOME_CATEGORIES: TransactionCategory[] = [
  { id: 'cat-salary', name: 'Salary', type: 'income', colorHex: '#10B981' },
  { id: 'cat-freelance', name: 'Freelance & Business', type: 'income', colorHex: '#06B6D4' },
  { id: 'cat-asaye', name: 'From Asaye', type: 'income', colorHex: '#3B82F6' },
  { id: 'cat-invest', name: 'Investments & Returns', type: 'income', colorHex: '#8B5CF6' },
  { id: 'cat-other-inc', name: 'Other', type: 'income', colorHex: '#64748B', isDefault: true },
];

/**
 * Task 21.2 Default Accounts
 */
export const FOUNDATION_DEFAULT_ACCOUNTS: Account[] = [
  { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 0, openingBalanceDate: '2026-11-10', isArchived: false, createdAt: '2026-11-10T00:00:00Z' },
  { id: 'acc-boa', name: 'BOA', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 0, openingBalanceDate: '2026-11-10', isArchived: false, createdAt: '2026-11-10T00:00:00Z' },
  { id: 'acc-dashen', name: 'Dashen Bank', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 0, openingBalanceDate: '2026-11-10', isArchived: false, createdAt: '2026-11-10T00:00:00Z' },
  { id: 'acc-telebirr', name: 'Telebirr', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 0, openingBalanceDate: '2026-11-10', isArchived: false, createdAt: '2026-11-10T00:00:00Z' },
  { id: 'acc-cash', name: 'Cash', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 0, openingBalanceDate: '2026-11-10', isArchived: false, createdAt: '2026-11-10T00:00:00Z' },
];

/**
 * Task 22.5: Account Balance = Opening Balance + Income - Expenses + Incoming Transfers - Outgoing Transfers
 */
export function calculateSimpleAccountBalance(
  account: Account,
  transactions: SimpleTransaction[]
): number {
  return calculateSharedAccountBalance(account as any, transactions as any);
}

/**
 * Task 22.5: Combined Balance = Sum of All Active Account Balances
 */
export function calculateSimpleCombinedBalance(
  accounts: Account[],
  transactions: SimpleTransaction[]
): number {
  return calculateSharedCombinedBalance(accounts as any, transactions as any);
}

/**
 * Total income strictly from income transactions (excluding transfers and opening balances)
 */
export function calculateSimpleTotalIncome(
  transactions: SimpleTransaction[],
  accountId?: string
): number {
  return calculateSharedTotalIncome(transactions as any, accountId);
}

/**
 * Total expenses strictly from expense transactions (excluding transfers)
 */
export function calculateSimpleTotalExpense(
  transactions: SimpleTransaction[],
  accountId?: string
): number {
  return calculateSharedTotalExpense(transactions as any, accountId);
}

/**
 * Task 23.2: Transaction Validation
 */
export interface SimpleTransactionValidationResult {
  isValid: boolean;
  errors: {
    amount?: string;
    category?: string;
    account?: string;
    destinationAccount?: string;
    transactionDate?: string;
  };
}

export function validateSimpleTransaction(
  type: SimpleTransactionType,
  amountCents: number,
  accountId: string,
  categoryId?: string,
  destinationAccountId?: string,
  transactionDate?: string,
  availableAccounts: Account[] = [],
  availableCategories: TransactionCategory[] = []
): SimpleTransactionValidationResult {
  const errors: SimpleTransactionValidationResult['errors'] = {};

  if (!amountCents || amountCents <= 0 || !Number.isInteger(amountCents)) {
    errors.amount = 'Amount must be greater than zero.';
  }

  const accountById = new Map(availableAccounts.map((a) => [a.id, a]));

  if (!accountId) {
    errors.account = 'Please select a valid active ETB account.';
  } else if (availableAccounts.length > 0) {
    const src = accountById.get(accountId);
    if (!src || src.isArchived || src.isSystem) {
      errors.account = 'Please select a valid active account.';
    } else if (!isEtbCurrency(src.currencyCode)) {
      errors.account = `First-release ETB mode only supports posting to ETB accounts (${src.name} is ${classifyCurrencyCode(src.currencyCode) === 'verified_non_etb' ? normalizeCurrencyCode(src.currencyCode) : 'Unverified'}).`;
    }
  }

  if (type === 'transfer') {
    if (!destinationAccountId) {
      errors.destinationAccount = 'Please select a valid destination ETB account.';
    } else if (availableAccounts.length > 0) {
      const dst = accountById.get(destinationAccountId);
      if (!dst || dst.isArchived || dst.isSystem) {
        errors.destinationAccount = 'Please select a valid destination account.';
      } else if (!isEtbCurrency(dst.currencyCode)) {
        errors.destinationAccount = `Destination account "${dst.name}" must be ETB.`;
      } else if (accountId && destinationAccountId === accountId) {
        errors.destinationAccount = 'Source and destination accounts must be different.';
      }
    } else if (accountId && destinationAccountId === accountId) {
      errors.destinationAccount = 'Source and destination accounts must be different.';
    }
  } else {
    if (!categoryId) {
      errors.category = 'Category is required.';
    } else if (availableCategories.length > 0) {
      const cat = findCategoryByIdOrAlias(availableCategories, categoryId);
      if (!cat) {
        errors.category = 'Selected category does not exist.';
      } else if (cat.type !== type) {
        errors.category = `Selected category is for ${cat.type}s, but transaction is an ${type}.`;
      }
    }
  }

  if (transactionDate && !CalendarDate.tryParse(transactionDate)) {
    errors.transactionDate = 'Invalid calendar date (must be valid YYYY-MM-DD).';
  }

  return {
    isValid: Object.keys(errors).length === 0,
    errors,
  };
}

/**
 * Task 22.4: Safe account deletion check
 */
export function canDeleteSimpleAccount(
  accountId: string,
  transactions: SimpleTransaction[]
): { canDelete: boolean; reason?: string } {
  const allowed = canDeleteSharedAccount(accountId, transactions as any);
  if (!allowed) {
    return {
      canDelete: false,
      reason: 'This account has recorded transactions and cannot be deleted permanently. You can archive it instead to keep historical records intact.',
    };
  }
  return { canDelete: true };
}

/**
 * Task 23.5: Safe category deletion check
 */
export function canDeleteSimpleCategory(
  categoryId: string,
  transactions: SimpleTransaction[]
): { canDelete: boolean; reason?: string } {
  const allowed = canDeleteSharedCategory(categoryId, '', transactions as any);
  if (!allowed) {
    return {
      canDelete: false,
      reason: 'This category is used by existing transactions and cannot be deleted. You can archive it instead to keep past records accurate.',
    };
  }
  return { canDelete: true };
}

/**
 * Task 23.5: Duplicate category name check
 */
export function isDuplicateCategoryName(
  name: string,
  type: 'expense' | 'income',
  categories: TransactionCategory[],
  excludeCategoryId?: string
): boolean {
  const normalized = name.trim().toLowerCase();
  return categories.some(
    (c) =>
      c.type === type &&
      c.id !== excludeCategoryId &&
      c.name.trim().toLowerCase() === normalized
  );
}

/**
 * Factory for creating transactions
 */
export function createSimpleFinanceTransaction(params: {
  type: SimpleTransactionType;
  amountCents: number;
  accountId: string;
  categoryId?: string;
  destinationAccountId?: string;
  description?: string;
  transactionDate?: string;
}): SimpleTransaction {
  const now = EthiopiaClock.nowUtc().toISOString();
  return {
    id: `tx-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
    type: params.type,
    amountCents: params.amountCents,
    accountId: params.accountId,
    categoryId: params.categoryId,
    destinationAccountId: params.destinationAccountId,
    description: params.description?.trim() || undefined,
    transactionDate: params.transactionDate || CalendarDate.today().toIsoString(),
    createdAt: now,
    updatedAt: now,
  };
}

// ============================================================================
// BATCH 6 EXTENSIONS (TASKS 26–30)
// ============================================================================

// -------------------------------------------------------------
// Task 26: Account Details & Account Movements
// -------------------------------------------------------------

export type AccountMovementDirection = 'inflow' | 'outflow';
export type AccountMovementDisplayType = 'income' | 'expense' | 'transfer_in' | 'transfer_out';

export interface AccountMovement {
  transaction: SimpleTransaction;
  direction: AccountMovementDirection;
  displayType: AccountMovementDisplayType;
  signedAmountCents: number; // positive for inflow, negative for outflow
  counterpartAccountId?: string;
  counterpartAccountName?: string;
  categoryName?: string;
}

/**
 * Task 26.2 & 26.3: Get all financial movements affecting a specific account,
 * sorted reverse-chronologically with clear directional attribution.
 */
export function getAccountMovements(
  account: Account,
  transactions: SimpleTransaction[],
  accounts: Account[],
  categories: TransactionCategory[]
): AccountMovement[] {
  const accountMap = new Map(accounts.map((a) => [a.id, a.name]));
  const categoryMap = new Map(categories.map((c) => [c.id, c.name]));

  const sorted = sortTransactionsDescending(transactions);
  const movements: AccountMovement[] = [];

  for (const tx of sorted) {
    if (tx.type === 'income' && tx.accountId === account.id) {
      movements.push({
        transaction: tx,
        direction: 'inflow',
        displayType: 'income',
        signedAmountCents: tx.amountCents,
        categoryName: tx.categoryId ? categoryMap.get(tx.categoryId) || 'Income' : 'Income',
      });
    } else if (tx.type === 'expense' && tx.accountId === account.id) {
      movements.push({
        transaction: tx,
        direction: 'outflow',
        displayType: 'expense',
        signedAmountCents: -tx.amountCents,
        categoryName: tx.categoryId ? categoryMap.get(tx.categoryId) || 'Expense' : 'Expense',
      });
    } else if (tx.type === 'transfer') {
      if (tx.destinationAccountId === account.id) {
        // Money transferred INTO this account from source account
        movements.push({
          transaction: tx,
          direction: 'inflow',
          displayType: 'transfer_in',
          signedAmountCents: tx.amountCents,
          counterpartAccountId: tx.accountId,
          counterpartAccountName: accountMap.get(tx.accountId) || 'Unknown Account',
        });
      } else if (tx.accountId === account.id) {
        // Money transferred OUT OF this account to destination account
        movements.push({
          transaction: tx,
          direction: 'outflow',
          displayType: 'transfer_out',
          signedAmountCents: -tx.amountCents,
          counterpartAccountId: tx.destinationAccountId,
          counterpartAccountName: tx.destinationAccountId
            ? accountMap.get(tx.destinationAccountId) || 'Unknown Account'
            : 'Unknown Account',
        });
      }
    }
  }

  return movements;
}

/**
 * Task 26.4: Account balance reconciliation breakdown
 */
export function verifyAccountBalanceConsistency(
  account: Account,
  transactions: SimpleTransaction[]
): {
  isConsistent: boolean;
  openingBalanceCents: number;
  totalInflowsCents: number;
  totalOutflowsCents: number;
  calculatedBalanceCents: number;
} {
  let inflows = 0;
  let outflows = 0;

  for (const tx of transactions) {
    if (tx.type === 'income' && tx.accountId === account.id) {
      inflows += tx.amountCents;
    } else if (tx.type === 'expense' && tx.accountId === account.id) {
      outflows += tx.amountCents;
    } else if (tx.type === 'transfer') {
      if (tx.destinationAccountId === account.id) {
        inflows += tx.amountCents;
      }
      if (tx.accountId === account.id) {
        outflows += tx.amountCents;
      }
    }
  }

  const opening = account.openingBalanceCents || 0;
  const calculated = opening + inflows - outflows;
  const standardCalc = calculateSimpleAccountBalance(account, transactions);

  return {
    isConsistent: calculated === standardCalc,
    openingBalanceCents: opening,
    totalInflowsCents: inflows,
    totalOutflowsCents: outflows,
    calculatedBalanceCents: calculated,
  };
}

// -------------------------------------------------------------
// Task 27: Transaction History Organization & Grouping
// -------------------------------------------------------------

/**
 * Task 27.1: Sort transactions reverse-chronologically (newest first)
 */
export function sortTransactionsDescending(transactions: SimpleTransaction[]): SimpleTransaction[] {
  return [...transactions].sort((a, b) => {
    if (a.transactionDate !== b.transactionDate) {
      return b.transactionDate.localeCompare(a.transactionDate);
    }
    return (b.createdAt || '').localeCompare(a.createdAt || '');
  });
}

export interface TransactionDateGroup {
  dateKey: string; // YYYY-MM-DD
  label: string; // "Today", "Yesterday", or formatted date
  transactions: SimpleTransaction[];
  totalInflowCents: number;
  totalOutflowCents: number;
}

/**
 * Task 27.2: Group transactions by date with readable labels
 */
export function groupTransactionsByDate(
  transactions: SimpleTransaction[],
  referenceTodayStr?: string
): TransactionDateGroup[] {
  const sorted = sortTransactionsDescending(transactions);
  const todayCal = referenceTodayStr
    ? CalendarDate.parse(referenceTodayStr)
    : CalendarDate.today();
  const todayStr = todayCal.toIsoString();
  const yesterdayStr = todayCal.subtractDays(1).toIsoString();

  const groupsMap = new Map<string, SimpleTransaction[]>();

  for (const tx of sorted) {
    const key = tx.transactionDate || todayStr;
    const list = groupsMap.get(key) || [];
    list.push(tx);
    groupsMap.set(key, list);
  }

  const result: TransactionDateGroup[] = [];

  for (const [dateKey, list] of groupsMap.entries()) {
    let label: string;
    if (dateKey === todayStr) {
      label = 'Today';
    } else if (dateKey === yesterdayStr) {
      label = 'Yesterday';
    } else {
      const cal = CalendarDate.tryParse(dateKey);
      label = cal
        ? `${cal.shortEnglishWeekdayName}, ${cal.gregorianShortMonthName} ${cal.day}, ${cal.year}`
        : dateKey;
    }

    let totalInflowCents = 0;
    let totalOutflowCents = 0;
    for (const tx of list) {
      if (tx.type === 'income') {
        totalInflowCents += tx.amountCents;
      } else if (tx.type === 'expense') {
        totalOutflowCents += tx.amountCents;
      }
    }

    result.push({
      dateKey,
      label,
      transactions: list,
      totalInflowCents,
      totalOutflowCents,
    });
  }

  return result;
}

// -------------------------------------------------------------
// Task 28: Opening Balance Corrections
// -------------------------------------------------------------

/**
 * Task 28.1–28.4: Correct opening balance and opening balance date.
 * Crucially, does NOT create any synthetic income/expense transactions or alter history.
 */
export function correctAccountOpeningBalance(
  account: Account,
  newOpeningBalanceCents: number,
  newOpeningBalanceDate?: string
): Account {
  if (!Number.isInteger(newOpeningBalanceCents)) {
    throw new Error('Opening balance must be an integer in cents.');
  }

  const now = EthiopiaClock.nowUtc().toISOString();
  return {
    ...account,
    openingBalanceCents: newOpeningBalanceCents,
    openingBalanceDate: newOpeningBalanceDate || account.openingBalanceDate || CalendarDate.today().toIsoString(),
    updatedAt: now,
  };
}

// -------------------------------------------------------------
// Task 29: Transaction Search and Multi-Filtering
// -------------------------------------------------------------

export type DateFilterPreset = 'all' | 'today' | 'yesterday' | 'this_week' | 'this_month' | 'custom';

export interface TransactionFilterOptions {
  query?: string;
  type?: 'all' | SimpleTransactionType;
  accountId?: string; // 'all' or specific account id
  datePreset?: DateFilterPreset;
  customStartDate?: string; // YYYY-MM-DD
  customEndDate?: string; // YYYY-MM-DD
  referenceDateStr?: string; // YYYY-MM-DD for testing
}

/**
 * Task 29.1–29.5: Search and filter transactions across multiple dimensions
 */
export function searchAndFilterTransactions(
  transactions: SimpleTransaction[],
  accounts: Account[],
  categories: TransactionCategory[],
  options: TransactionFilterOptions
): SimpleTransaction[] {
  const accountNameMap = new Map(accounts.map((a) => [a.id, a.name.toLowerCase()]));
  const categoryNameMap = new Map(categories.map((c) => [c.id, c.name.toLowerCase()]));

  const queryTrimmed = options.query?.trim().toLowerCase();
  const todayCal = options.referenceDateStr
    ? CalendarDate.parse(options.referenceDateStr)
    : CalendarDate.today();
  const todayStr = todayCal.toIsoString();
  const yesterdayStr = todayCal.subtractDays(1).toIsoString();

  // Week start (Monday) and end (Sunday)
  const dayOfWeek = todayCal.weekday - 1; // 0 = Mon, 6 = Sun
  const weekStartStr = todayCal.subtractDays(dayOfWeek).toIsoString();
  const weekEndStr = todayCal.addDays(6 - dayOfWeek).toIsoString();

  // Month start and end
  const monthStartStr = todayCal.startOfGregorianMonth.toIsoString();
  const monthEndStr = todayCal.endOfGregorianMonth.toIsoString();

  return transactions.filter((tx) => {
    // 1. Type Filter
    if (options.type && options.type !== 'all' && tx.type !== options.type) {
      return false;
    }

    // 2. Account Filter (matches source or destination)
    if (options.accountId && options.accountId !== 'all') {
      if (tx.accountId !== options.accountId && tx.destinationAccountId !== options.accountId) {
        return false;
      }
    }

    // 3. Date Preset Filter
    if (options.datePreset && options.datePreset !== 'all') {
      const txDate = tx.transactionDate;
      if (options.datePreset === 'today') {
        if (txDate !== todayStr) return false;
      } else if (options.datePreset === 'yesterday') {
        if (txDate !== yesterdayStr) return false;
      } else if (options.datePreset === 'this_week') {
        if (txDate < weekStartStr || txDate > weekEndStr) return false;
      } else if (options.datePreset === 'this_month') {
        if (txDate < monthStartStr || txDate > monthEndStr) return false;
      } else if (options.datePreset === 'custom') {
        if (options.customStartDate && txDate < options.customStartDate) return false;
        if (options.customEndDate && txDate > options.customEndDate) return false;
      }
    }

    // 4. Text Query Filter
    if (queryTrimmed) {
      const descMatch = tx.description ? tx.description.toLowerCase().includes(queryTrimmed) : false;
      const catName = tx.categoryId ? categoryNameMap.get(tx.categoryId) || '' : '';
      const catMatch = catName.includes(queryTrimmed);
      const accName = accountNameMap.get(tx.accountId) || '';
      const accMatch = accName.includes(queryTrimmed);
      const destAccName = tx.destinationAccountId ? accountNameMap.get(tx.destinationAccountId) || '' : '';
      const destAccMatch = destAccName.includes(queryTrimmed);

      if (!descMatch && !catMatch && !accMatch && !destAccMatch) {
        return false;
      }
    }

    return true;
  });
}

// -------------------------------------------------------------
// Task 30: Financial Data Integrity & Reconciliation
// -------------------------------------------------------------

export interface AccountReconciliationAudit {
  accountId: string;
  accountName: string;
  isArchived: boolean;
  isActive: boolean;
  openingBalanceCents: number;
  inflowsCents: number;
  outflowsCents: number;
  calculatedBalanceCents: number;
  transactionCount: number;
}

export interface FinancialIntegrityReport {
  isHealthy: boolean;
  errors: string[];
  warnings: string[];
  accountReconciliations: AccountReconciliationAudit[];
  activeAccountsCombinedBalanceCents: number;
  totalActiveAccounts: number;
  totalArchivedAccounts: number;
  totalTransactions: number;
}

/**
 * Task 30.1–30.6: Comprehensive verification engine that audits ledger integrity,
 * verifies account balances, validates references, and ensures zero discrepancies.
 */
export function verifyFinancialDataIntegrity(
  accounts: Account[],
  categories: TransactionCategory[],
  transactions: SimpleTransaction[]
): FinancialIntegrityReport {
  const errors: string[] = [];
  const warnings: string[] = [];

  const accountIdMap = new Map(accounts.map((a) => [a.id, a]));
  const categoryIdMap = new Map(categories.map((c) => [c.id, c]));
  const seenTxIds = new Set<string>();

  // Check 1: Validate transactions
  for (const tx of transactions) {
    if (!tx.id) {
      errors.push('Found transaction with missing ID.');
    } else if (seenTxIds.has(tx.id)) {
      errors.push(`Duplicate transaction ID detected: ${tx.id}.`);
    } else {
      seenTxIds.add(tx.id);
    }

    if (!Number.isInteger(tx.amountCents) || tx.amountCents <= 0) {
      errors.push(`Transaction ${tx.id} has invalid amount: ${tx.amountCents} cents.`);
    }

    if (!accountIdMap.has(tx.accountId)) {
      errors.push(`Transaction ${tx.id} references missing source account ID: ${tx.accountId}.`);
    }

    if (tx.type === 'transfer') {
      if (!tx.destinationAccountId) {
        errors.push(`Transfer transaction ${tx.id} is missing a destination account.`);
      } else if (!accountIdMap.has(tx.destinationAccountId)) {
        errors.push(`Transfer transaction ${tx.id} references missing destination account ID: ${tx.destinationAccountId}.`);
      } else if (tx.accountId === tx.destinationAccountId) {
        errors.push(`Transfer transaction ${tx.id} has identical source and destination account (${tx.accountId}).`);
      }
    } else {
      // Income or Expense requires valid category
      if (!tx.categoryId) {
        warnings.push(`Transaction ${tx.id} (${tx.type}) has no category.`);
      } else if (!categoryIdMap.has(tx.categoryId)) {
        warnings.push(`Transaction ${tx.id} references category ID ${tx.categoryId} which is not found in categories list.`);
      }
    }

    if (!tx.transactionDate || !CalendarDate.tryParse(tx.transactionDate)) {
      errors.push(`Transaction ${tx.id} has invalid date format: ${tx.transactionDate}.`);
    }
  }

  // Check 2: Account opening balances and reconciliations
  const accountReconciliations: AccountReconciliationAudit[] = [];
  let combinedActiveBalanceCents = 0;
  let activeAccountCount = 0;
  let archivedAccountCount = 0;

  for (const acc of accounts) {
    if (!Number.isInteger(acc.openingBalanceCents)) {
      errors.push(`Account ${acc.name} (${acc.id}) has non-integer opening balance: ${acc.openingBalanceCents}.`);
    }

    const audit = verifyAccountBalanceConsistency(acc, transactions);
    const txCount = transactions.filter(
      (tx) => tx.accountId === acc.id || tx.destinationAccountId === acc.id
    ).length;

    accountReconciliations.push({
      accountId: acc.id,
      accountName: acc.name,
      isArchived: !!acc.isArchived,
      isActive: !acc.isArchived,
      openingBalanceCents: acc.openingBalanceCents || 0,
      inflowsCents: audit.totalInflowsCents,
      outflowsCents: audit.totalOutflowsCents,
      calculatedBalanceCents: audit.calculatedBalanceCents,
      transactionCount: txCount,
    });

    if (!acc.isArchived) {
      if (!acc.isSystem && acc.type === 'asset' && isEtbCurrency(acc.currencyCode)) {
        combinedActiveBalanceCents += audit.calculatedBalanceCents;
      } else if (!acc.isSystem && !isEtbCurrency(acc.currencyCode)) {
        warnings.push(
          `Account "${acc.name}" (${classifyCurrencyCode(acc.currencyCode) === 'verified_non_etb' ? normalizeCurrencyCode(acc.currencyCode) : 'Unverified'}) is excluded from combined ETB balance.`
        );
      }
      activeAccountCount++;
    } else {
      archivedAccountCount++;
    }
  }

  // Check combined balance matches calculateSimpleCombinedBalance (ETB active assets)
  const directCombined = calculateSimpleCombinedBalance(accounts, transactions);
  if (directCombined !== combinedActiveBalanceCents) {
    errors.push(
      `Combined active balance mismatch: calculated ${combinedActiveBalanceCents} cents vs direct ${directCombined} cents.`
    );
  }

  return {
    isHealthy: errors.length === 0,
    errors,
    warnings,
    accountReconciliations,
    activeAccountsCombinedBalanceCents: combinedActiveBalanceCents,
    totalActiveAccounts: activeAccountCount,
    totalArchivedAccounts: archivedAccountCount,
    totalTransactions: transactions.length,
  };
}


