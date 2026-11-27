/**
 * Daywell Web Preview — Financial SMS Draft Persistence & Review Service (Stage 5)
 *
 * Core Invariants:
 * - Local-only storage (`daywell_finance_sms_drafts`), explicitly excluded from
 *   SharedStateBridge canonical backups/snapshots and DataPortabilityService exports.
 * - SMS messages NEVER create ledger postings automatically.
 * - Ledger mutations occur strictly upon explicit user approval via `approveDraft`.
 */

import { EthiopiaClock } from '../domain/date';
import {
  Account,
  DoubleEntryValidationError,
  JournalEntry,
  Posting,
  SimpleTransaction,
  TransactionCategory,
} from '../domain/doubleEntryFinance';
import {
  SharedSavingsGoal,
  syncVaultSavingsGoalsV7,
} from '../domain/financeV7Engine';
import {
  buildApprovedSmsLedgerEntry,
  FinanceSmsDraft,
  findDuplicateSmsDraft,
  parseFinancialSmsMessage,
  SmsDraftApprovalBuildResult,
  SmsDraftStatus,
  SmsImportBatchSummary,
  SmsProvider,
  SmsSuggestedTransactionType,
} from '../domain/financeSms';

export const FINANCE_SMS_DRAFTS_STORAGE_KEY = 'daywell_finance_sms_drafts';
export const FINANCE_SMS_PENDING_APPROVAL_KEY = 'daywell_finance_sms_pending_approval_v1';

export interface SmsDraftStorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem?(key: string): void;
}

export interface PendingSmsApprovalIntent {
  version: 1;
  draftId: string;
  entryId: string;
  postingIds: string[];
  simpleTxId: string;
  addedFeeCategoryId?: string;
  previousSavingsGoals?: SharedSavingsGoal[];
  previousDraft: FinanceSmsDraft;
  createdAt: string;
}

export interface SmsApprovalRecoveryResult {
  recovered: boolean;
  outcome?: 'rolled_back' | 'finalized_completed';
  draftId?: string;
  entryId?: string;
  postingIds?: string[];
  simpleTxId?: string;
  addedFeeCategoryId?: string;
}

function resolveStorage(storage?: SmsDraftStorageLike): SmsDraftStorageLike | null {
  if (storage) return storage;
  try {
    if (typeof localStorage !== 'undefined') {
      return localStorage;
    }
  } catch {
    // Restricted storage environment
  }
  return null;
}

function clearStorageKey(store: SmsDraftStorageLike, key: string): void {
  if (typeof store.removeItem === 'function') {
    store.removeItem(key);
  } else {
    store.setItem(key, '');
  }
}

function readStoredArraySafe<T>(
  store: SmsDraftStorageLike,
  key: string
): { exists: boolean; items: T[] } {
  const raw = store.getItem(key);
  if (raw === null || raw === '') {
    return { exists: false, items: [] };
  }
  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) {
      return { exists: true, items: parsed as T[] };
    }
  } catch {
    // Ignore malformed collection JSON during recovery inspection
  }
  return { exists: true, items: [] };
}

function isValidPendingIntent(value: unknown): value is PendingSmsApprovalIntent {
  if (!value || typeof value !== 'object') return false;
  const candidate = value as Record<string, unknown>;
  return (
    candidate.version === 1 &&
    typeof candidate.draftId === 'string' &&
    candidate.draftId.length > 0 &&
    typeof candidate.entryId === 'string' &&
    candidate.entryId.length > 0 &&
    Array.isArray(candidate.postingIds) &&
    candidate.postingIds.every((id) => typeof id === 'string' && id.length > 0) &&
    typeof candidate.simpleTxId === 'string' &&
    candidate.simpleTxId.length > 0 &&
    Boolean(
      candidate.previousDraft &&
        typeof candidate.previousDraft === 'object' &&
        typeof (candidate.previousDraft as { id?: unknown }).id === 'string'
    )
  );
}

function sortDraftsDesc(drafts: FinanceSmsDraft[]): FinanceSmsDraft[] {
  return [...drafts].sort((a, b) => {
    const recCmp = b.receivedAtUtc.localeCompare(a.receivedAtUtc);
    if (recCmp !== 0) return recCmp;
    return b.createdAt.localeCompare(a.createdAt);
  });
}

/**
 * Splits a multi-message paste block into individual SMS messages.
 * Supports explicit `---` separators or blank-line paragraph breaks.
 */
export function splitSmsBatchInput(rawInput: string): string[] {
  const normalized = rawInput.replace(/\r\n?/g, '\n').trim();
  if (!normalized) return [];

  const chunks = normalized.split(/\n\s*---+\s*\n|\n\s*\n+/g);
  return chunks.map((chunk) => chunk.trim()).filter((chunk) => chunk.length > 0);
}

export class FinanceSmsService {
  public static readonly STORAGE_KEY = FINANCE_SMS_DRAFTS_STORAGE_KEY;
  public static readonly PENDING_APPROVAL_KEY = FINANCE_SMS_PENDING_APPROVAL_KEY;

  /**
   * Checks for an interrupted SMS approval write-ahead intent (`daywell_finance_sms_pending_approval_v1`).
   * - If all ledger records and the `approved` draft status were completely committed (only intent cleanup
   *   was interrupted), finalizes by clearing the intent key without undoing the valid transaction.
   * - If the approval was interrupted mid-commit (partial ledger keys or missing `approved` draft status),
   *   idempotently rolls back any partial ledger records and restores the draft to its pre-approval state
   *   before clearing the intent key.
   */
  public static recoverPendingApproval(
    storage?: SmsDraftStorageLike
  ): SmsApprovalRecoveryResult {
    const store = resolveStorage(storage);
    if (!store) return { recovered: false };

    let rawIntent: string | null = null;
    try {
      rawIntent = store.getItem(FINANCE_SMS_PENDING_APPROVAL_KEY);
    } catch {
      return { recovered: false };
    }
    if (!rawIntent || !rawIntent.trim()) {
      return { recovered: false };
    }

    let parsedIntent: unknown;
    try {
      parsedIntent = JSON.parse(rawIntent);
    } catch {
      clearStorageKey(store, FINANCE_SMS_PENDING_APPROVAL_KEY);
      return { recovered: false };
    }

    if (!isValidPendingIntent(parsedIntent)) {
      clearStorageKey(store, FINANCE_SMS_PENDING_APPROVAL_KEY);
      return { recovered: false };
    }

    const intent = parsedIntent;
    const postingIdSet = new Set(intent.postingIds);

    const storedEntries = readStoredArraySafe<JournalEntry>(store, 'daywell_journal_entries');
    const storedPostings = readStoredArraySafe<Posting>(store, 'daywell_postings');
    const storedFinanceTxs = readStoredArraySafe<SimpleTransaction>(
      store,
      'daywell_finance_transactions'
    );
    const storedLegacyTxs = readStoredArraySafe<SimpleTransaction>(store, 'daywell_transactions');
    const storedDrafts = readStoredArraySafe<FinanceSmsDraft>(
      store,
      FINANCE_SMS_DRAFTS_STORAGE_KEY
    );

    const hasEntry = storedEntries.items.some((e) => e && e.id === intent.entryId);
    const entryPostings = storedPostings.items.filter(
      (p) => p && p.entryId === intent.entryId
    );
    const hasAllPostings =
      intent.postingIds.length > 0 &&
      intent.postingIds.every((pid) => entryPostings.some((p) => p.id === pid));
    const hasFinanceTx = storedFinanceTxs.items.some(
      (t) => t && (t.id === intent.simpleTxId || t.journalEntryId === intent.entryId)
    );
    const hasLegacyTx = storedLegacyTxs.items.some(
      (t) => t && (t.id === intent.simpleTxId || t.journalEntryId === intent.entryId)
    );
    const currentDraft = storedDrafts.items.find((d) => d && d.id === intent.draftId);
    const isDraftApproved = Boolean(
      currentDraft &&
        currentDraft.status === 'approved' &&
        currentDraft.approvedEntryId === intent.entryId
    );

    if (hasEntry && hasAllPostings && hasFinanceTx && hasLegacyTx && isDraftApproved) {
      clearStorageKey(store, FINANCE_SMS_PENDING_APPROVAL_KEY);
      return {
        recovered: true,
        outcome: 'finalized_completed',
        draftId: intent.draftId,
        entryId: intent.entryId,
      };
    }

    // Interrupted mid-commit: idempotently roll back draft first, then partial ledger records,
    // resync savings goals, and clear the pending approval intent LAST.
    if (storedDrafts.exists) {
      const draftIdx = storedDrafts.items.findIndex((d) => d && d.id === intent.draftId);
      if (draftIdx !== -1) {
        const existingDraft = storedDrafts.items[draftIdx];
        const needsDraftRestore =
          existingDraft.status !== intent.previousDraft.status ||
          existingDraft.approvedEntryId !== intent.previousDraft.approvedEntryId ||
          existingDraft.updatedAt !== intent.previousDraft.updatedAt;
        if (needsDraftRestore) {
          const restoredDrafts = [...storedDrafts.items];
          restoredDrafts[draftIdx] = intent.previousDraft;
          store.setItem(
            FINANCE_SMS_DRAFTS_STORAGE_KEY,
            JSON.stringify(sortDraftsDesc(restoredDrafts))
          );
        }
      }
    }

    let cleanedFinanceTxs = storedFinanceTxs.items;
    if (storedFinanceTxs.exists) {
      cleanedFinanceTxs = storedFinanceTxs.items.filter(
        (t) => t && t.id !== intent.simpleTxId && t.journalEntryId !== intent.entryId
      );
      if (cleanedFinanceTxs.length !== storedFinanceTxs.items.length) {
        store.setItem('daywell_finance_transactions', JSON.stringify(cleanedFinanceTxs));
      }
    }

    if (storedLegacyTxs.exists) {
      const cleanedLegacyTxs = storedLegacyTxs.items.filter(
        (t) => t && t.id !== intent.simpleTxId && t.journalEntryId !== intent.entryId
      );
      if (cleanedLegacyTxs.length !== storedLegacyTxs.items.length) {
        store.setItem('daywell_transactions', JSON.stringify(cleanedLegacyTxs));
      }
    }

    let cleanedPostings = storedPostings.items;
    if (storedPostings.exists) {
      cleanedPostings = storedPostings.items.filter(
        (p) => p && p.entryId !== intent.entryId && !postingIdSet.has(p.id)
      );
      if (cleanedPostings.length !== storedPostings.items.length) {
        store.setItem('daywell_postings', JSON.stringify(cleanedPostings));
      }
    }

    let cleanedEntries = storedEntries.items;
    if (storedEntries.exists) {
      cleanedEntries = storedEntries.items.filter((e) => e && e.id !== intent.entryId);
      if (cleanedEntries.length !== storedEntries.items.length) {
        store.setItem('daywell_journal_entries', JSON.stringify(cleanedEntries));
      }
    }

    if (intent.addedFeeCategoryId) {
      const storedCategories = readStoredArraySafe<TransactionCategory>(
        store,
        'daywell_categories'
      );
      if (storedCategories.exists) {
        const stillReferenced =
          cleanedPostings.some((p) => p.categoryId === intent.addedFeeCategoryId) ||
          cleanedFinanceTxs.some((t) => t.categoryId === intent.addedFeeCategoryId);
        if (!stillReferenced) {
          const cleanedCategories = storedCategories.items.filter(
            (c) => c && c.id !== intent.addedFeeCategoryId
          );
          if (cleanedCategories.length !== storedCategories.items.length) {
            store.setItem('daywell_categories', JSON.stringify(cleanedCategories));
          }
        }
      }
    }

    const storedGoals = readStoredArraySafe<SharedSavingsGoal>(store, 'daywell_savings_goals');
    if (storedGoals.exists) {
      const storedAccounts = readStoredArraySafe<Account>(store, 'daywell_accounts');
      let restoredGoals: SharedSavingsGoal[] | null = null;
      if (storedAccounts.exists && storedAccounts.items.length > 0) {
        restoredGoals = syncVaultSavingsGoalsV7({
          accounts: storedAccounts.items,
          entries: cleanedEntries,
          postings: cleanedPostings,
          savingsGoals: storedGoals.items,
        });
      } else if (Array.isArray(intent.previousSavingsGoals)) {
        restoredGoals = intent.previousSavingsGoals;
      }
      if (
        restoredGoals &&
        JSON.stringify(restoredGoals) !== JSON.stringify(storedGoals.items)
      ) {
        store.setItem('daywell_savings_goals', JSON.stringify(restoredGoals));
      }
    }

    clearStorageKey(store, FINANCE_SMS_PENDING_APPROVAL_KEY);
    return {
      recovered: true,
      outcome: 'rolled_back',
      draftId: intent.draftId,
      entryId: intent.entryId,
      postingIds: intent.postingIds,
      simpleTxId: intent.simpleTxId,
      ...(intent.addedFeeCategoryId ? { addedFeeCategoryId: intent.addedFeeCategoryId } : {}),
    };
  }

  public static loadDrafts(storage?: SmsDraftStorageLike): FinanceSmsDraft[] {
    const store = resolveStorage(storage);
    if (!store) return [];
    this.recoverPendingApproval(store);
    try {
      const raw = store.getItem(FINANCE_SMS_DRAFTS_STORAGE_KEY);
      if (!raw) return [];
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) return [];
      return sortDraftsDesc(
        parsed.filter(
          (item): item is FinanceSmsDraft =>
            Boolean(item && typeof item === 'object' && typeof item.id === 'string')
        )
      );
    } catch {
      return [];
    }
  }

  public static saveDrafts(
    drafts: FinanceSmsDraft[],
    storage?: SmsDraftStorageLike
  ): FinanceSmsDraft[] {
    const sorted = sortDraftsDesc(drafts);
    const store = resolveStorage(storage);
    if (store) {
      try {
        store.setItem(FINANCE_SMS_DRAFTS_STORAGE_KEY, JSON.stringify(sorted));
      } catch (e) {
        console.error('Failed to persist SMS drafts locally:', e);
      }
    }
    return sorted;
  }

  public static importSmsMessages(params: {
    rawMessages: string[];
    providerHint?: SmsProvider;
    receivedAtUtc?: string;
    accounts: Account[];
    categories: TransactionCategory[];
    storage?: SmsDraftStorageLike;
  }): { drafts: FinanceSmsDraft[]; summary: SmsImportBatchSummary } {
    const existing = this.loadDrafts(params.storage);
    const known = [...existing];
    const effectiveReceivedAt =
      params.receivedAtUtc ?? EthiopiaClock.nowUtc().toISOString();

    let importedCount = 0;
    let unrecognizedCount = 0;
    let duplicateCount = 0;
    let ignoredCount = 0;
    const importedDrafts: FinanceSmsDraft[] = [];
    const duplicateMatches: Array<{
      reference?: string;
      existingStatus: SmsDraftStatus;
    }> = [];
    const ignoredReasons: string[] = [];

    for (const rawMsg of params.rawMessages) {
      const outcome = parseFinancialSmsMessage(rawMsg, {
        providerHint: params.providerHint,
        receivedAtUtc: effectiveReceivedAt,
        accounts: params.accounts,
        categories: params.categories,
      });

      if (outcome.kind === 'ignored_non_transactional' || !outcome.draft) {
        ignoredCount += 1;
        if (outcome.reason) ignoredReasons.push(outcome.reason);
        continue;
      }

      const candidate = outcome.draft;
      const dup = findDuplicateSmsDraft(candidate, known);
      if (dup.isDuplicate) {
        duplicateCount += 1;
        duplicateMatches.push({
          reference: candidate.transactionReference ?? dup.existingDraft?.transactionReference,
          existingStatus: dup.existingDraft?.status ?? candidate.status,
        });
        continue;
      }

      known.push(candidate);
      importedDrafts.push(candidate);
      if (candidate.status === 'unrecognized') {
        unrecognizedCount += 1;
      } else {
        importedCount += 1;
      }
    }

    const saved = this.saveDrafts(known, params.storage);
    return {
      drafts: saved,
      summary: {
        importedCount,
        unrecognizedCount,
        duplicateCount,
        ignoredCount,
        importedDrafts,
        duplicateMatches,
        ignoredReasons,
      },
    };
  }

  public static updateDraftReview(params: {
    draftId: string;
    suggestedType?: SmsSuggestedTransactionType;
    suggestedAccountId?: string;
    clearSuggestedAccountId?: boolean;
    suggestedCategoryId?: string;
    clearSuggestedCategoryId?: boolean;
    parseNotes?: string;
    storage?: SmsDraftStorageLike;
  }): { drafts: FinanceSmsDraft[]; updatedDraft: FinanceSmsDraft } {
    const existing = this.loadDrafts(params.storage);
    const idx = existing.findIndex((d) => d.id === params.draftId);
    if (idx === -1) {
      throw new DoubleEntryValidationError(`SMS draft "${params.draftId}" not found.`);
    }
    const current = existing[idx];
    if (current.status === 'approved') {
      throw new DoubleEntryValidationError('Approved SMS drafts cannot be modified.');
    }

    const updatedDraft: FinanceSmsDraft = {
      ...current,
      ...(params.suggestedType ? { suggestedType: params.suggestedType } : {}),
      suggestedAccountId: params.clearSuggestedAccountId
        ? undefined
        : params.suggestedAccountId !== undefined
          ? params.suggestedAccountId
          : current.suggestedAccountId,
      suggestedCategoryId: params.clearSuggestedCategoryId
        ? undefined
        : params.suggestedCategoryId !== undefined
          ? params.suggestedCategoryId
          : current.suggestedCategoryId,
      ...(params.parseNotes !== undefined ? { parseNotes: params.parseNotes } : {}),
      updatedAt: EthiopiaClock.nowUtc().toISOString(),
    };

    const next = [...existing];
    next[idx] = updatedDraft;
    const saved = this.saveDrafts(next, params.storage);
    return { drafts: saved, updatedDraft };
  }

  public static dismissDraft(params: {
    draftId: string;
    storage?: SmsDraftStorageLike;
  }): { drafts: FinanceSmsDraft[]; updatedDraft: FinanceSmsDraft } {
    const existing = this.loadDrafts(params.storage);
    const idx = existing.findIndex((d) => d.id === params.draftId);
    if (idx === -1) {
      throw new DoubleEntryValidationError(`SMS draft "${params.draftId}" not found.`);
    }
    const current = existing[idx];
    if (current.status === 'approved') {
      throw new DoubleEntryValidationError('Approved SMS drafts cannot be dismissed.');
    }

    const updatedDraft: FinanceSmsDraft = {
      ...current,
      status: 'dismissed',
      updatedAt: EthiopiaClock.nowUtc().toISOString(),
    };
    const next = [...existing];
    next[idx] = updatedDraft;
    const saved = this.saveDrafts(next, params.storage);
    return { drafts: saved, updatedDraft };
  }

  public static approveDraft(params: {
    draftId: string;
    finalType: 'expense' | 'income' | 'transfer';
    accountId: string;
    destinationAccountId?: string;
    categoryId?: string;
    feeCategoryId?: string;
    occurrenceDate: string;
    movementDate?: string;
    description: string;
    payee?: string;
    accounts: Account[];
    categories: TransactionCategory[];
    entryId?: string;
    storage?: SmsDraftStorageLike;
  }): { drafts: FinanceSmsDraft[]; result: SmsDraftApprovalBuildResult } {
    const existing = this.loadDrafts(params.storage);
    const idx = existing.findIndex((d) => d.id === params.draftId);
    if (idx === -1) {
      throw new DoubleEntryValidationError(`SMS draft "${params.draftId}" not found.`);
    }
    const current = existing[idx];
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const entryId =
      params.entryId ??
      `entry-sms-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;

    const result = buildApprovedSmsLedgerEntry({
      draft: current,
      finalType: params.finalType,
      accountId: params.accountId,
      destinationAccountId: params.destinationAccountId,
      categoryId: params.categoryId,
      feeCategoryId: params.feeCategoryId,
      occurrenceDate: params.occurrenceDate,
      movementDate: params.movementDate,
      description: params.description,
      payee: params.payee,
      entryId,
      accounts: params.accounts,
      categories: params.categories,
      nowIso,
    });

    const next = [...existing];
    next[idx] = result.updatedDraft;
    const saved = this.saveDrafts(next, params.storage);
    return { drafts: saved, result };
  }

  /**
   * Builds, validates, and commits the ledger records and `approved` SMS draft status
   * to localStorage using:
   * 1. A single-key write-ahead pending approval intent (`daywell_finance_sms_pending_approval_v1`)
   *    persisted before any target ledger/draft key is mutated so abrupt tab/browser/device
   *    termination mid-commit is deterministically recovered on restart or retry; and
   * 2. Synchronous exception rollback across written keys when a storage write throws.
   *
   * Note: Browser localStorage has no multi-key native transaction; the single-key intent
   * record provides crash-recovery consistency across multi-key commits without a second
   * competing persistence engine.
   */
  public static approveDraftAtomically(params: {
    draftId: string;
    finalType: 'expense' | 'income' | 'transfer';
    accountId: string;
    destinationAccountId?: string;
    categoryId?: string;
    feeCategoryId?: string;
    occurrenceDate: string;
    movementDate?: string;
    description: string;
    payee?: string;
    accounts: Account[];
    categories: TransactionCategory[];
    entries: JournalEntry[];
    postings: Posting[];
    simpleTransactions: SimpleTransaction[];
    savingsGoals: SharedSavingsGoal[];
    entryId?: string;
    storage?: SmsDraftStorageLike;
  }): {
    drafts: FinanceSmsDraft[];
    result: SmsDraftApprovalBuildResult;
    categories: TransactionCategory[];
    entries: JournalEntry[];
    postings: Posting[];
    simpleTransactions: SimpleTransaction[];
    savingsGoals: SharedSavingsGoal[];
  } {
    const recovery = this.recoverPendingApproval(params.storage);
    const baseEntries =
      recovery.recovered && recovery.outcome === 'rolled_back' && recovery.entryId
        ? params.entries.filter((e) => e.id !== recovery.entryId)
        : params.entries;
    const basePostings =
      recovery.recovered && recovery.outcome === 'rolled_back' && recovery.entryId
        ? params.postings.filter(
            (p) =>
              p.entryId !== recovery.entryId &&
              !(recovery.postingIds?.includes(p.id) ?? false)
          )
        : params.postings;
    const baseSimpleTransactions =
      recovery.recovered && recovery.outcome === 'rolled_back' && recovery.entryId
        ? params.simpleTransactions.filter(
            (t) =>
              t.id !== recovery.simpleTxId && t.journalEntryId !== recovery.entryId
          )
        : params.simpleTransactions;

    const existing = this.loadDrafts(params.storage);
    const idx = existing.findIndex((d) => d.id === params.draftId);
    if (idx === -1) {
      throw new DoubleEntryValidationError(`SMS draft "${params.draftId}" not found.`);
    }
    const current = existing[idx];
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const entryId =
      params.entryId ??
      `entry-sms-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;

    if (baseEntries.some((e) => e.id === entryId)) {
      throw new DoubleEntryValidationError(
        `Journal entry "${entryId}" already exists in the ledger.`
      );
    }

    const result = buildApprovedSmsLedgerEntry({
      draft: current,
      finalType: params.finalType,
      accountId: params.accountId,
      destinationAccountId: params.destinationAccountId,
      categoryId: params.categoryId,
      feeCategoryId: params.feeCategoryId,
      occurrenceDate: params.occurrenceDate,
      movementDate: params.movementDate,
      description: params.description,
      payee: params.payee,
      entryId,
      accounts: params.accounts,
      categories: params.categories,
      nowIso,
    });

    const addedFeeCategoryId =
      result.feeCategoryToAdd &&
      !params.categories.some((c) => c.id === result.feeCategoryToAdd!.id)
        ? result.feeCategoryToAdd.id
        : undefined;
    const nextCategories = addedFeeCategoryId
      ? [...params.categories, result.feeCategoryToAdd!]
      : params.categories;
    const nextEntries = [result.entry, ...baseEntries];
    const nextPostings = [...result.postings, ...basePostings];
    const nextSimpleTransactions = [result.simpleTx, ...baseSimpleTransactions];
    const nextSavingsGoals = syncVaultSavingsGoalsV7({
      accounts: params.accounts,
      entries: nextEntries,
      postings: nextPostings,
      savingsGoals: params.savingsGoals,
    });

    const nextDrafts = [...existing];
    nextDrafts[idx] = result.updatedDraft;
    const sortedDrafts = sortDraftsDesc(nextDrafts);

    const store = resolveStorage(params.storage);
    if (store) {
      const stagedWrites: Array<[string, string]> = [
        ['daywell_categories', JSON.stringify(nextCategories)],
        ['daywell_journal_entries', JSON.stringify(nextEntries)],
        ['daywell_postings', JSON.stringify(nextPostings)],
        ['daywell_finance_transactions', JSON.stringify(nextSimpleTransactions)],
        ['daywell_transactions', JSON.stringify(nextSimpleTransactions)],
        ['daywell_savings_goals', JSON.stringify(nextSavingsGoals)],
        [FINANCE_SMS_DRAFTS_STORAGE_KEY, JSON.stringify(sortedDrafts)],
      ];
      const previousValues = new Map<string, string | null>();
      for (const [key] of stagedWrites) {
        previousValues.set(key, store.getItem(key));
      }

      const savingsGoalsChanged =
        JSON.stringify(nextSavingsGoals) !== JSON.stringify(params.savingsGoals);
      const intent: PendingSmsApprovalIntent = {
        version: 1,
        draftId: current.id,
        entryId: result.entry.id,
        postingIds: result.postings.map((p) => p.id),
        simpleTxId: result.simpleTx.id,
        ...(addedFeeCategoryId ? { addedFeeCategoryId } : {}),
        ...(savingsGoalsChanged ? { previousSavingsGoals: params.savingsGoals } : {}),
        previousDraft: current,
        createdAt: nowIso,
      };
      store.setItem(FINANCE_SMS_PENDING_APPROVAL_KEY, JSON.stringify(intent));

      const writtenKeys: string[] = [];
      try {
        for (const [key, serialized] of stagedWrites) {
          store.setItem(key, serialized);
          writtenKeys.push(key);
        }
        clearStorageKey(store, FINANCE_SMS_PENDING_APPROVAL_KEY);
      } catch (err) {
        let rollbackClean = true;
        for (const key of writtenKeys.reverse()) {
          const prev = previousValues.get(key) ?? null;
          try {
            if (prev === null) {
              clearStorageKey(store, key);
            } else {
              store.setItem(key, prev);
            }
          } catch {
            rollbackClean = false;
          }
        }
        if (rollbackClean) {
          try {
            clearStorageKey(store, FINANCE_SMS_PENDING_APPROVAL_KEY);
          } catch {
            // Keep pending approval intent if cleanup fails so startup recovery cleans up
          }
        }
        throw err instanceof Error
          ? err
          : new Error('Atomic SMS draft approval storage commit failed.');
      }
    }

    return {
      drafts: sortedDrafts,
      result,
      categories: nextCategories,
      entries: nextEntries,
      postings: nextPostings,
      simpleTransactions: nextSimpleTransactions,
      savingsGoals: nextSavingsGoals,
    };
  }
}
