import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  CANONICAL_INBOX_CATEGORIES,
  createInboxItemRecord,
  deleteInboxItemFromList,
  getProcessedInboxItems,
  getUnprocessedInboxItems,
  markInboxItemProcessed,
  markInboxItemProcessedRecord,
  normalizeInboxCategory,
  normalizeInboxItemRecord,
  prepareTaskDraftFromInboxItem,
  updateInboxItemRecord,
} from './inboxOperations';
import { createTaskRecord, normalizeTaskLabels } from './taskOperations';
import { SharedInboxItem } from './sharedFoundation';
import { inboxService } from '../services/inboxService';
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
    (globalThis as any).window = prevWindow;
    (globalThis as any).localStorage = prevLocalStorage;
  }
}

describe('Stage 1.5 — Shared Inbox & Quick Capture Integration (Web Domain, Service & Bridge)', () => {
  it('1. Domain inboxOperations: captures, normalizes, edits, marks processed, deletes, and rejects empty text', () => {
    assert.deepStrictEqual([...CANONICAL_INBOX_CATEGORIES], [
      'task',
      'idea',
      'note',
      'expense',
      'problem',
      'decision',
      'general',
    ]);
    assert.strictEqual(normalizeInboxCategory(' IDEA '), 'idea');
    assert.strictEqual(normalizeInboxCategory('unknown-kind'), 'general');

    const emptyCreate = createInboxItemRecord({ rawText: '   \n\t  ' });
    assert.strictEqual(emptyCreate.ok, false);

    const created = createInboxItemRecord(
      {
        id: 'inbox-stage15-1',
        rawText: '  Submit Q4 tax declaration  ',
        category: 'task',
      },
      new Date('2026-11-22T09:00:00.000Z')
    );
    assert.strictEqual(created.ok, true);
    if (!created.ok) return;
    assert.strictEqual(created.item.id, 'inbox-stage15-1');
    assert.strictEqual(created.item.rawText, 'Submit Q4 tax declaration');
    assert.strictEqual(created.item.category, 'task');
    assert.strictEqual(created.item.isProcessed, false);
    assert.strictEqual(created.item.createdAt, '2026-11-22T09:00:00.000Z');

    // Empty edit fails closed
    const badEdit = updateInboxItemRecord(created.item, { rawText: '   ' });
    assert.strictEqual(badEdit.ok, false);

    // Valid edit + recategorization preserves ID and createdAt
    const edited = updateInboxItemRecord(created.item, {
      rawText: 'File Q4 VAT return with accountant',
      category: 'idea',
    });
    assert.strictEqual(edited.ok, true);
    if (!edited.ok) return;
    assert.strictEqual(edited.item.rawText, 'File Q4 VAT return with accountant');
    assert.strictEqual(edited.item.category, 'idea');
    assert.strictEqual(edited.item.isProcessed, false);

    // Mark processed transitions cleanly without mutating original object
    const processed = markInboxItemProcessedRecord(edited.item, true);
    assert.strictEqual(processed.isProcessed, true);
    assert.strictEqual(edited.item.isProcessed, false);

    const secondItem = normalizeInboxItemRecord({
      id: 'inbox-stage15-2',
      rawText: 'Call landlord',
      category: 'general',
      isProcessed: true,
      createdAt: '2026-11-22T08:00:00.000Z',
    });
    assert.ok(secondItem);
    const list: SharedInboxItem[] = [edited.item, secondItem];
    assert.strictEqual(getUnprocessedInboxItems(list).length, 1);
    assert.strictEqual(getProcessedInboxItems(list).length, 1);

    const afterMark = markInboxItemProcessed(list, 'inbox-stage15-1', true).items;
    assert.strictEqual(getUnprocessedInboxItems(afterMark).length, 0);
    assert.strictEqual(getProcessedInboxItems(afterMark).length, 2);

    const afterDelete = deleteInboxItemFromList(afterMark, 'inbox-stage15-2').remaining;
    assert.deepStrictEqual(
      afterDelete.map((i) => i.id),
      ['inbox-stage15-1']
    );
  });

  it('2. Lossless Task draft conversion: single-line, multi-line, >120 chars, and idea category prefill', () => {
    const shortTask = normalizeInboxItemRecord({
      id: 'inbox-draft-1',
      rawText: 'Renew passport',
      category: 'task',
      isProcessed: false,
      createdAt: '2026-11-22T09:00:00.000Z',
    })!;
    const shortDraft = prepareTaskDraftFromInboxItem(shortTask);
    assert.strictEqual(shortDraft.title, 'Renew passport');
    assert.strictEqual(shortDraft.description, '');
    assert.deepStrictEqual(shortDraft.initialLabels, []);

    const multiLineIdea = normalizeInboxItemRecord({
      id: 'inbox-draft-2',
      rawText: '  Build weekend checklist app\nInclude offline sync\nAdd Ethiopian calendar dates  ',
      category: 'idea',
      isProcessed: false,
      createdAt: '2026-11-22T09:05:00.000Z',
    })!;
    const multiDraft = prepareTaskDraftFromInboxItem(multiLineIdea);
    assert.strictEqual(multiDraft.title, 'Build weekend checklist app');
    assert.strictEqual(
      multiDraft.description,
      'Include offline sync\nAdd Ethiopian calendar dates'
    );
    assert.deepStrictEqual(multiDraft.initialLabels, ['idea']);

    const longLineText =
      'Audit all monthly recurring utility subscriptions across electricity, mobile internet, cloud storage, and office lease renewals before Friday';
    const longItem = normalizeInboxItemRecord({
      id: 'inbox-draft-3',
      rawText: longLineText,
      category: 'task',
      isProcessed: false,
      createdAt: '2026-11-22T09:10:00.000Z',
    })!;
    const longDraft = prepareTaskDraftFromInboxItem(longItem);
    assert.strictEqual(longDraft.title.endsWith('...'), true);
    assert.ok(longDraft.title.length <= 120);
    assert.strictEqual(longDraft.description, longLineText);
  });

  it('3. Shared Inbox service & SharedStateBridge: quick capture stages in daywell_inbox_items without premature Task creation, converts without duplicates, and round-trips offline', () => {
    withMockBrowserStorage((store) => {
      // Seed nothing in daywell_tasks first
      assert.strictEqual(store.get('daywell_tasks'), undefined);

      // Capture a task and an idea via inboxService
      const capTask = inboxService.captureQuickThought({
        id: 'inbox-web-1',
        rawText: 'Review architectural contract\nCheck milestones & deliverables',
        category: 'task',
        createdAt: '2026-11-22T10:00:00.000Z',
      });
      assert.strictEqual(capTask.ok, true);
      if (!capTask.ok) return;

      const capIdea = inboxService.captureQuickThought({
        id: 'inbox-web-2',
        rawText: 'Explore solar battery backup',
        category: 'idea',
        createdAt: '2026-11-22T10:01:00.000Z',
      });
      assert.strictEqual(capIdea.ok, true);
      if (!capIdea.ok) return;

      // Crucial Stage 1.5 invariant: capturing does NOT auto-create Task rows prematurely
      assert.strictEqual(store.get('daywell_tasks'), undefined);
      assert.strictEqual(inboxService.loadUnprocessedItems().length, 2);

      // Edit & recategorize second item before conversion
      const edited = inboxService.updateInboxItem('inbox-web-2', {
        rawText: 'Request 2 solar battery quotes',
        category: 'task',
      });
      assert.strictEqual(edited.ok, true);
      assert.strictEqual(
        inboxService.loadUnprocessedItems().find((i) => i.id === 'inbox-web-2')?.rawText,
        'Request 2 solar battery quotes'
      );

      // Convert first item into an actual Task and mark Inbox item processed
      const draft = prepareTaskDraftFromInboxItem(capTask.item);
      const taskResult = createTaskRecord(
        {
          id: 'task-from-inbox-1',
          title: draft.title,
          description: draft.description,
          priority: 'high',
          dueDate: '2026-11-25',
          projectId: 'proj-contract',
          labels: normalizeTaskLabels([...draft.initialLabels, 'legal']),
        },
        new Date('2026-11-22T10:05:00.000Z')
      );
      assert.strictEqual(taskResult.ok, true);
      if (!taskResult.ok) return;

      store.set('daywell_tasks', JSON.stringify([taskResult.task]));
      const marked = inboxService.markProcessed('inbox-web-1', true);
      assert.strictEqual(marked.updated?.isProcessed, true);

      // Processed item no longer appears in unprocessed Inbox queue
      const activeInbox = inboxService.loadUnprocessedItems();
      assert.deepStrictEqual(
        activeInbox.map((i) => i.id),
        ['inbox-web-2']
      );

      // Canonical JSON export -> import preserves converted Task + unprocessed Inbox item + processed history distinctly
      const assembled = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(assembled.tasks.length, 1);
      assert.strictEqual(assembled.tasks[0].id, 'task-from-inbox-1');
      assert.strictEqual(
        assembled.tasks[0].description,
        'Check milestones & deliverables'
      );
      assert.strictEqual(assembled.inboxItems.length, 2);
      assert.strictEqual(
        assembled.inboxItems.find((i) => i.id === 'inbox-web-1')?.isProcessed,
        true
      );
      assert.strictEqual(
        assembled.inboxItems.find((i) => i.id === 'inbox-web-2')?.isProcessed,
        false
      );

      const exportedJson = SharedStateBridge.exportToAndroidJson();
      store.clear();
      assert.strictEqual(inboxService.loadInboxItems().length, 0);

      SharedStateBridge.importFromAndroidJson(exportedJson);
      const reloadedUnprocessed = inboxService.loadUnprocessedItems();
      assert.deepStrictEqual(
        reloadedUnprocessed.map((i) => i.id),
        ['inbox-web-2']
      );
      const reloadedAll = inboxService.loadInboxItems();
      assert.strictEqual(reloadedAll.length, 2);
      assert.strictEqual(
        reloadedAll.find((i) => i.id === 'inbox-web-1')?.isProcessed,
        true
      );
    });
  });

  it('4. Backward compatibility: inboxService loads legacy daywell_inbox storage key if daywell_inbox_items is absent', () => {
    withMockBrowserStorage((store) => {
      store.set(
        SharedStateBridge.LEGACY_INBOX_STORAGE_KEY,
        JSON.stringify([
          {
            id: 'legacy-inbox-1',
            rawText: 'Legacy thought captured offline',
            category: 'idea',
            isProcessed: false,
            createdAt: '2026-10-01T12:00:00.000Z',
          },
        ])
      );

      const loaded = inboxService.loadInboxItems();
      assert.strictEqual(loaded.length, 1);
      assert.strictEqual(loaded[0].id, 'legacy-inbox-1');
      assert.strictEqual(loaded[0].category, 'idea');
      assert.strictEqual(loaded[0].isProcessed, false);
    });
  });

  it('5. Architecture & UI governance: domain stays pure and Web Quick Capture/Tasks wiring preserves shared Inbox contracts & zero hexes', () => {
    const domainSrc = fs.readFileSync(
      path.resolve('src/domain/inboxOperations.ts'),
      'utf8'
    );
    for (const forbidden of [
      'react',
      'react-dom',
      'localStorage',
      'window.',
      'document.',
      '../services/',
      '../components/',
    ]) {
      assert.strictEqual(
        domainSrc.includes(forbidden),
        false,
        `src/domain/inboxOperations.ts must not reference "${forbidden}"`
      );
    }

    const appSrc = fs.readFileSync(path.resolve('src/App.tsx'), 'utf8');
    assert.strictEqual(appSrc.includes('inboxService.captureQuickThought'), true);
    assert.strictEqual(appSrc.includes('Inbox Captures'), true);
    assert.strictEqual(appSrc.includes('Review Inbox'), true);

    const tasksModuleSrc = fs.readFileSync(
      path.resolve('src/components/DaywellTasksModule.tsx'),
      'utf8'
    );
    assert.strictEqual(tasksModuleSrc.includes('Captured Inbox Items'), true);
    assert.strictEqual(tasksModuleSrc.includes('Convert to Task'), true);
    assert.strictEqual(tasksModuleSrc.includes('Mark Processed'), true);
    assert.strictEqual(tasksModuleSrc.includes('prepareTaskDraftFromInboxItem'), true);

    for (const file of [
      'src/domain/inboxOperations.ts',
      'src/services/inboxService.ts',
      'src/App.tsx',
      'src/components/DaywellTasksModule.tsx',
    ]) {
      const content = fs.readFileSync(path.resolve(file), 'utf8');
      assert.strictEqual(
        /#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\b/.test(content),
        false,
        `${file} must not contain hardcoded hex colors`
      );
    }
  });
});
