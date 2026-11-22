import {
  createInboxItemRecord,
  deleteInboxItemFromList,
  getUnprocessedInboxItems,
  InboxMutationResult,
  markInboxItemProcessed,
  normalizeInboxItemRecord,
  updateInboxItemRecord,
} from '../domain/inboxOperations';
import { SharedInboxItem } from '../domain/sharedFoundation';
import { SharedStateBridge } from './sharedStateBridge';

function dedupeById(items: readonly SharedInboxItem[]): SharedInboxItem[] {
  const seen = new Set<string>();
  const out: SharedInboxItem[] = [];
  for (const item of items) {
    if (!seen.has(item.id)) {
      seen.add(item.id);
      out.push(item);
    }
  }
  return out;
}

function dispatchSync(items: readonly SharedInboxItem[]): void {
  if (typeof window === 'undefined') return;
  window.dispatchEvent(
    new CustomEvent(SharedStateBridge.SYNC_EVENT_NAME, {
      detail: { inboxItems: items },
    })
  );
}

export const inboxService = {
  loadInboxItems(): SharedInboxItem[] {
    if (typeof localStorage === 'undefined') return [];
    try {
      const primaryRaw = localStorage.getItem(SharedStateBridge.INBOX_STORAGE_KEY);
      const raw =
        primaryRaw !== null
          ? primaryRaw
          : localStorage.getItem(SharedStateBridge.LEGACY_INBOX_STORAGE_KEY);
      if (!raw) return [];
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) return [];
      const normalized = parsed
        .map((entry) => normalizeInboxItemRecord(entry))
        .filter((entry): entry is SharedInboxItem => entry !== null);
      return dedupeById(normalized);
    } catch {
      return [];
    }
  },

  loadUnprocessedItems(): SharedInboxItem[] {
    return getUnprocessedInboxItems(this.loadInboxItems());
  },

  saveInboxItems(items: readonly SharedInboxItem[]): SharedInboxItem[] {
    const normalized = dedupeById(
      items
        .map((entry) => normalizeInboxItemRecord(entry))
        .filter((entry): entry is SharedInboxItem => entry !== null)
    );
    if (typeof localStorage !== 'undefined') {
      try {
        localStorage.setItem(
          SharedStateBridge.INBOX_STORAGE_KEY,
          JSON.stringify(normalized)
        );
      } catch (err) {
        console.error('[inboxService] Failed to save inbox items:', err);
      }
    }
    dispatchSync(normalized);
    return normalized;
  },

  captureQuickThought(input: {
    id?: string;
    rawText: string;
    category?: string;
    createdAt?: string;
  }): InboxMutationResult & { items?: SharedInboxItem[] } {
    const created = createInboxItemRecord(input);
    if (!created.ok) return created;
    const existing = this.loadInboxItems().filter(
      (item) => item.id !== created.item.id
    );
    const saved = this.saveInboxItems([created.item, ...existing]);
    return { ok: true, item: created.item, items: saved };
  },

  updateInboxItem(
    id: string,
    patch: { rawText: string; category?: string }
  ): InboxMutationResult & { items?: SharedInboxItem[] } {
    const current = this.loadInboxItems();
    const target = current.find((item) => item.id === id);
    if (!target) {
      return { ok: false, error: 'Inbox item not found.' };
    }
    const updatedRes = updateInboxItemRecord(target, patch);
    if (!updatedRes.ok) return updatedRes;
    const next = current.map((item) => (item.id === id ? updatedRes.item : item));
    const saved = this.saveInboxItems(next);
    return { ok: true, item: updatedRes.item, items: saved };
  },

  markProcessed(
    id: string,
    processed = true
  ): { items: SharedInboxItem[]; updated?: SharedInboxItem } {
    const current = this.loadInboxItems();
    const { items, updated } = markInboxItemProcessed(current, id, processed);
    const saved = this.saveInboxItems(items);
    return { items: saved, updated };
  },

  deleteInboxItem(id: string): {
    items: SharedInboxItem[];
    deleted?: SharedInboxItem;
  } {
    const current = this.loadInboxItems();
    const { remaining, deleted } = deleteInboxItemFromList(current, id);
    const saved = this.saveInboxItems(remaining);
    return { items: saved, deleted };
  },
};
