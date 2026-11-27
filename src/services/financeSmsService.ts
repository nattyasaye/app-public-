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

export interface SmsDraftStorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem?(key: string): void;
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

  public static loadDrafts(storage?: SmsDraftStorageLike): FinanceSmsDraft[] {
    const store = resolveStorage(storage);
    if (!store) return [];
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
   * Atomically builds, validates, and commits both the authoritative ledger keys
   * and the `approved` SMS draft status into localStorage in a single rollback-guarded
   * transaction. If any validation or persistence step fails, every modified key is
   * restored to its pre-approval snapshot so neither ledger nor draft is half-updated.
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

    const nextCategories =
      result.feeCategoryToAdd &&
      !params.categories.some((c) => c.id === result.feeCategoryToAdd!.id)
        ? [...params.categories, result.feeCategoryToAdd]
        : params.categories;
    const nextEntries = [result.entry, ...params.entries];
    const nextPostings = [...result.postings, ...params.postings];
    const nextSimpleTransactions = [result.simpleTx, ...params.simpleTransactions];
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
      const writtenKeys: string[] = [];
      try {
        for (const [key, serialized] of stagedWrites) {
          store.setItem(key, serialized);
          writtenKeys.push(key);
        }
      } catch (err) {
        for (const key of writtenKeys.reverse()) {
          const prev = previousValues.get(key) ?? null;
          try {
            if (prev === null) {
              store.removeItem?.(key);
            } else {
              store.setItem(key, prev);
            }
          } catch {
            // Best-effort rollback on storage fault
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
