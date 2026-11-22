import { EthiopiaClock } from './date';
import { SharedInboxItem } from './sharedFoundation';

export type InboxItemCategory = SharedInboxItem['category'];

export const CANONICAL_INBOX_CATEGORIES: readonly InboxItemCategory[] = [
  'task',
  'idea',
  'note',
  'expense',
  'problem',
  'decision',
  'general',
] as const;

export const INBOX_CATEGORY_LABELS: Record<InboxItemCategory, string> = {
  task: 'Task',
  idea: 'Idea',
  note: 'Note',
  expense: 'Expense',
  problem: 'Problem',
  decision: 'Decision',
  general: 'General',
};

export interface InboxTaskDraft {
  sourceInboxId: string;
  sourceCategory: InboxItemCategory;
  title: string;
  description: string;
  initialLabels: string[];
}

export type InboxMutationResult =
  | { ok: true; item: SharedInboxItem }
  | { ok: false; error: string };

export function normalizeInboxCategory(raw?: string | null): InboxItemCategory {
  const trimmed = (raw ?? '').trim().toLowerCase();
  if ((CANONICAL_INBOX_CATEGORIES as readonly string[]).includes(trimmed)) {
    return trimmed as InboxItemCategory;
  }
  return 'general';
}

export function normalizeInboxItemRecord(raw: unknown): SharedInboxItem | null {
  if (!raw || typeof raw !== 'object') return null;
  const obj = raw as Record<string, unknown>;
  const id = typeof obj.id === 'string' ? obj.id.trim() : '';
  const textRaw =
    typeof obj.rawText === 'string'
      ? obj.rawText
      : typeof obj.text === 'string'
        ? obj.text
        : '';
  const rawText = textRaw.trim();
  if (!id || !rawText) return null;

  const category = normalizeInboxCategory(
    typeof obj.category === 'string' ? obj.category : undefined
  );
  const createdAtRaw =
    typeof obj.createdAt === 'string' && obj.createdAt.trim()
      ? obj.createdAt.trim()
      : typeof obj.createdAtUtc === 'string' && obj.createdAtUtc.trim()
        ? obj.createdAtUtc.trim()
        : EthiopiaClock.nowUtc().toISOString();

  return {
    id,
    rawText,
    category,
    isProcessed: Boolean(obj.isProcessed),
    createdAt: createdAtRaw,
  };
}

export function createInboxItemRecord(
  input: {
    id?: string;
    rawText: string;
    category?: string;
    createdAt?: string;
  },
  nowUtc?: Date
): InboxMutationResult {
  const trimmed = input.rawText.trim();
  if (!trimmed) {
    return { ok: false, error: 'Captured thought cannot be empty.' };
  }

  const now = nowUtc ?? EthiopiaClock.nowUtc();
  const id =
    input.id && input.id.trim()
      ? input.id.trim()
      : `inbox-${now.getTime()}-${Math.random().toString(36).slice(2, 7)}`;

  return {
    ok: true,
    item: {
      id,
      rawText: trimmed,
      category: normalizeInboxCategory(input.category),
      isProcessed: false,
      createdAt:
        input.createdAt && input.createdAt.trim()
          ? input.createdAt.trim()
          : now.toISOString(),
    },
  };
}

export function updateInboxItemRecord(
  existing: SharedInboxItem,
  patch: {
    rawText: string;
    category?: string;
  }
): InboxMutationResult {
  const trimmed = patch.rawText.trim();
  if (!trimmed) {
    return { ok: false, error: 'Inbox item text cannot be empty.' };
  }

  return {
    ok: true,
    item: {
      ...existing,
      rawText: trimmed,
      category:
        patch.category !== undefined
          ? normalizeInboxCategory(patch.category)
          : existing.category,
    },
  };
}

export function markInboxItemProcessedRecord(
  item: SharedInboxItem,
  processed = true
): SharedInboxItem {
  return {
    ...item,
    isProcessed: processed,
  };
}

export function markInboxItemProcessed(
  items: readonly SharedInboxItem[],
  inboxId: string,
  processed = true
): { items: SharedInboxItem[]; updated?: SharedInboxItem } {
  let updated: SharedInboxItem | undefined;
  const next = items.map((item) => {
    if (item.id === inboxId) {
      updated = markInboxItemProcessedRecord(item, processed);
      return updated;
    }
    return item;
  });
  return { items: next, updated };
}

export function deleteInboxItemFromList(
  items: readonly SharedInboxItem[],
  inboxId: string
): { remaining: SharedInboxItem[]; deleted?: SharedInboxItem } {
  const deleted = items.find((i) => i.id === inboxId);
  const remaining = items.filter((i) => i.id !== inboxId);
  return { remaining, deleted };
}

function compareCreatedAtDesc(a: SharedInboxItem, b: SharedInboxItem): number {
  const ta = Date.parse(a.createdAt || '');
  const tb = Date.parse(b.createdAt || '');
  if (Number.isFinite(ta) && Number.isFinite(tb) && ta !== tb) {
    return tb - ta;
  }
  return (b.createdAt || '').localeCompare(a.createdAt || '');
}

export function getUnprocessedInboxItems(
  items: readonly SharedInboxItem[]
): SharedInboxItem[] {
  return items.filter((item) => !item.isProcessed).sort(compareCreatedAtDesc);
}

export function getProcessedInboxItems(
  items: readonly SharedInboxItem[]
): SharedInboxItem[] {
  return items.filter((item) => item.isProcessed).sort(compareCreatedAtDesc);
}

/**
 * Prepares a Task draft from an InboxItem without losing any captured content:
 * - Single-line <= 120 chars: uses the full text as title and leaves description empty.
 * - Multi-line: uses the first non-empty line (up to 120 chars) as title; if the first
 *   line exceeds 120 chars, preserves the complete text in description alongside trailing lines.
 * - Single-line > 120 chars: truncates title cleanly with '...' while preserving the full
 *   rawText in description.
 */
export function prepareTaskDraftFromInboxItem(
  item: SharedInboxItem
): InboxTaskDraft {
  const normalized = item.rawText.replace(/\r\n?/g, '\n').trim();
  const initialLabels = item.category === 'idea' ? ['idea'] : [];

  if (!normalized) {
    return {
      sourceInboxId: item.id,
      sourceCategory: item.category,
      title: '',
      description: '',
      initialLabels,
    };
  }

  const lines = normalized.split('\n');
  if (lines.length === 1) {
    const line = lines[0].trim();
    if (line.length <= 120) {
      return {
        sourceInboxId: item.id,
        sourceCategory: item.category,
        title: line,
        description: '',
        initialLabels,
      };
    }
    return {
      sourceInboxId: item.id,
      sourceCategory: item.category,
      title: `${line.slice(0, 117).trimEnd()}...`,
      description: line,
      initialLabels,
    };
  }

  const firstNonEmptyIdx = lines.findIndex((l) => l.trim().length > 0);
  const firstLine = (firstNonEmptyIdx >= 0 ? lines[firstNonEmptyIdx] : lines[0]).trim();
  const trailingLines = lines
    .slice(firstNonEmptyIdx >= 0 ? firstNonEmptyIdx + 1 : 1)
    .join('\n')
    .trim();

  if (firstLine.length <= 120) {
    return {
      sourceInboxId: item.id,
      sourceCategory: item.category,
      title: firstLine,
      description: trailingLines,
      initialLabels,
    };
  }

  return {
    sourceInboxId: item.id,
    sourceCategory: item.category,
    title: `${firstLine.slice(0, 117).trimEnd()}...`,
    description: trailingLines ? `${firstLine}\n${trailingLines}` : firstLine,
    initialLabels,
  };
}
