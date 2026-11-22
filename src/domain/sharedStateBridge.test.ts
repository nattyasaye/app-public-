import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  CANONICAL_SEED_DATABASE,
  SYSTEM_CONTROL_ACCOUNT_IDS,
  SharedGoal,
  SharedInboxItem,
  SharedProject,
} from './sharedFoundation';
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

describe('SHARED STATE BRIDGE: PROJECTS, GOALS & INBOX PERSISTENCE INTEGRITY', () => {
  it('1. User-created Projects survive canonical-state assembly with IDs and goalId relationships', () => {
    withMockBrowserStorage((store) => {
      const userGoals: SharedGoal[] = [
        {
          id: 'goal-user-roof',
          title: 'Energy Independence',
          description: 'Install solar backup system',
          status: 'active',
          targetDate: '2027-01-15',
        },
      ];
      const userProjects: SharedProject[] = [
        {
          id: 'proj-user-solar',
          title: 'Solar Inverter Setup',
          description: 'Mount panels and wire 48V inverter',
          status: 'active',
          targetDate: '2026-12-20',
          goalId: 'goal-user-roof',
        },
      ];

      store.set(SharedStateBridge.GOALS_STORAGE_KEY, JSON.stringify(userGoals));
      store.set(SharedStateBridge.PROJECTS_STORAGE_KEY, JSON.stringify(userProjects));

      const assembled = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(assembled.schemaVersion, 5);
      assert.strictEqual(assembled.financeSchemaVersion, 7);
      assert.strictEqual(assembled.projects.length, 1);
      assert.strictEqual(assembled.projects[0].id, 'proj-user-solar');
      assert.strictEqual(assembled.projects[0].title, 'Solar Inverter Setup');
      assert.strictEqual(assembled.projects[0].description, 'Mount panels and wire 48V inverter');
      assert.strictEqual(assembled.projects[0].status, 'active');
      assert.strictEqual(assembled.projects[0].targetDate, '2026-12-20');
      assert.strictEqual(assembled.projects[0].goalId, 'goal-user-roof');
    });
  });

  it('2. Edited Projects retain their updated fields across assembly', () => {
    withMockBrowserStorage((store) => {
      const initialProject: SharedProject = {
        id: 'proj-user-edit',
        title: 'Original Title',
        description: 'Draft scope',
        status: 'active',
        targetDate: '2026-12-01',
      };
      store.set(SharedStateBridge.PROJECTS_STORAGE_KEY, JSON.stringify([initialProject]));

      const firstAssembly = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(firstAssembly.projects[0].title, 'Original Title');

      const editedProject: SharedProject = {
        ...initialProject,
        title: 'Finalized Portfolio Launch',
        description: 'Updated scope after design review',
        status: 'completed',
        targetDate: '2026-12-10',
        goalId: 'goal-user-career',
      };
      store.set(SharedStateBridge.PROJECTS_STORAGE_KEY, JSON.stringify([editedProject]));

      const secondAssembly = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(secondAssembly.projects.length, 1);
      assert.strictEqual(secondAssembly.projects[0].id, 'proj-user-edit');
      assert.strictEqual(secondAssembly.projects[0].title, 'Finalized Portfolio Launch');
      assert.strictEqual(secondAssembly.projects[0].description, 'Updated scope after design review');
      assert.strictEqual(secondAssembly.projects[0].status, 'completed');
      assert.strictEqual(secondAssembly.projects[0].targetDate, '2026-12-10');
      assert.strictEqual(secondAssembly.projects[0].goalId, 'goal-user-career');
    });
  });

  it('3. User-created Goals survive canonical-state assembly', () => {
    withMockBrowserStorage((store) => {
      const userGoals: SharedGoal[] = [
        {
          id: 'goal-user-emergency',
          title: 'Build 6-Month Emergency Fund',
          description: 'Hold liquid reserves in CBE',
          status: 'active',
          targetDate: '2027-06-01',
        },
        {
          id: 'goal-user-amharic',
          title: 'Read 12 Amharic Books',
          status: 'active',
        },
      ];
      store.set(SharedStateBridge.GOALS_STORAGE_KEY, JSON.stringify(userGoals));

      const assembled = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(assembled.goals.length, 2);
      assert.strictEqual(assembled.goals[0].id, 'goal-user-emergency');
      assert.strictEqual(assembled.goals[0].title, 'Build 6-Month Emergency Fund');
      assert.strictEqual(assembled.goals[1].id, 'goal-user-amharic');
      assert.strictEqual(assembled.goals[1].title, 'Read 12 Amharic Books');
    });
  });

  it('4. Edited Goals retain their updated changes across assembly', () => {
    withMockBrowserStorage((store) => {
      const originalGoal: SharedGoal = {
        id: 'goal-user-health',
        title: 'Run 5km',
        description: 'Morning training',
        status: 'active',
        targetDate: '2026-12-15',
      };
      store.set(SharedStateBridge.GOALS_STORAGE_KEY, JSON.stringify([originalGoal]));

      const updatedGoal: SharedGoal = {
        ...originalGoal,
        title: 'Run 10km Consistently',
        description: 'Three runs per week in Entoto',
        status: 'achieved',
        targetDate: '2027-01-30',
      };
      store.set(SharedStateBridge.GOALS_STORAGE_KEY, JSON.stringify([updatedGoal]));

      const assembled = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(assembled.goals.length, 1);
      assert.strictEqual(assembled.goals[0].id, 'goal-user-health');
      assert.strictEqual(assembled.goals[0].title, 'Run 10km Consistently');
      assert.strictEqual(assembled.goals[0].description, 'Three runs per week in Entoto');
      assert.strictEqual(assembled.goals[0].status, 'achieved');
      assert.strictEqual(assembled.goals[0].targetDate, '2027-01-30');
    });
  });

  it('5. Inbox records survive assembly (primary and legacy inbox stores)', () => {
    withMockBrowserStorage((store) => {
      const liveInbox: SharedInboxItem[] = [
        {
          id: 'inbox-user-1',
          rawText: 'Pay Ethio Telecom fiber bill 1200 ETB',
          category: 'expense',
          isProcessed: false,
          createdAt: '2026-11-15T08:00:00.000Z',
        },
        {
          id: 'inbox-user-2',
          rawText: 'Outline quarterly review priorities',
          category: 'task',
          isProcessed: true,
          createdAt: '2026-11-15T09:15:00.000Z',
        },
      ];
      store.set(SharedStateBridge.INBOX_STORAGE_KEY, JSON.stringify(liveInbox));

      const assembled = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(assembled.inboxItems.length, 2);
      assert.strictEqual(assembled.inboxItems[0].id, 'inbox-user-1');
      assert.strictEqual(assembled.inboxItems[0].category, 'expense');
      assert.strictEqual(assembled.inboxItems[0].isProcessed, false);
      assert.strictEqual(assembled.inboxItems[1].id, 'inbox-user-2');
      assert.strictEqual(assembled.inboxItems[1].isProcessed, true);

      // Legacy key fallback when primary inbox key is absent
      store.delete(SharedStateBridge.INBOX_STORAGE_KEY);
      store.set(SharedStateBridge.LEGACY_INBOX_STORAGE_KEY, JSON.stringify([liveInbox[0]]));
      const assembledLegacy = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(assembledLegacy.inboxItems.length, 1);
      assert.strictEqual(assembledLegacy.inboxItems[0].id, 'inbox-user-1');
    });
  });

  it('6. Deleted records are not silently recreated from seed data or stale canonical storage, and purgeKnownSeedData preserves user records', () => {
    withMockBrowserStorage((store) => {
      // Seed canonical snapshot containing 2 projects, 1 goal, 1 inbox item
      const seededSnapshot = {
        ...SharedStateBridge.assembleLiveDatabaseState(),
        projects: [
          { id: 'proj-user-keep', title: 'Keep Me', status: 'active' as const },
          { id: 'proj-user-del', title: 'Deleted Project', status: 'active' as const },
        ],
        goals: [{ id: 'goal-user-del', title: 'Deleted Goal', status: 'active' as const }],
        inboxItems: [
          {
            id: 'inbox-user-del',
            rawText: 'Deleted capture',
            category: 'note' as const,
            isProcessed: false,
            createdAt: '2026-11-15T08:00:00.000Z',
          },
        ],
      };
      SharedStateBridge.saveCanonicalState(seededSnapshot);

      // Simulate user deleting one project and deleting all goals & inbox items in live stores
      store.set(
        SharedStateBridge.PROJECTS_STORAGE_KEY,
        JSON.stringify([{ id: 'proj-user-keep', title: 'Keep Me', status: 'active' }])
      );
      store.set(SharedStateBridge.GOALS_STORAGE_KEY, JSON.stringify([]));
      store.set(SharedStateBridge.INBOX_STORAGE_KEY, JSON.stringify([]));

      const afterDeletion = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(afterDeletion.projects.length, 1);
      assert.strictEqual(afterDeletion.projects[0].id, 'proj-user-keep');
      assert.strictEqual(afterDeletion.goals.length, 0);
      assert.strictEqual(afterDeletion.inboxItems.length, 0);

      // Simulate mixed seed + user IDs and run purgeKnownSeedData (called on App mount)
      store.set(
        SharedStateBridge.PROJECTS_STORAGE_KEY,
        JSON.stringify([
          { id: 'proj-1', title: 'Seed Demo Project', status: 'active' },
          { id: 'proj-user-keep', title: 'Keep Me', status: 'active' },
        ])
      );
      store.set(
        SharedStateBridge.GOALS_STORAGE_KEY,
        JSON.stringify([
          { id: 'goal-1', title: 'Seed Demo Goal', status: 'active' },
          { id: 'goal-user-keep', title: 'Keep User Goal', status: 'active' },
        ])
      );
      store.set(
        SharedStateBridge.INBOX_STORAGE_KEY,
        JSON.stringify([
          {
            id: 'inbox-1',
            rawText: 'Seed Demo Inbox',
            category: 'expense',
            isProcessed: false,
            createdAt: '2026-11-15T08:00:00.000Z',
          },
          {
            id: 'inbox-user-keep',
            rawText: 'Keep User Thought',
            category: 'idea',
            isProcessed: false,
            createdAt: '2026-11-15T08:30:00.000Z',
          },
        ])
      );

      const purgeRes = SharedStateBridge.purgeKnownSeedData();
      assert.strictEqual(purgeRes.purgedCount, 3);

      const afterPurge = SharedStateBridge.assembleLiveDatabaseState();
      assert.deepStrictEqual(
        afterPurge.projects.map((p) => p.id),
        ['proj-user-keep']
      );
      assert.deepStrictEqual(
        afterPurge.goals.map((g) => g.id),
        ['goal-user-keep']
      );
      assert.deepStrictEqual(
        afterPurge.inboxItems.map((i) => i.id),
        ['inbox-user-keep']
      );
    });
  });

  it('7. Unrelated canonical-state collections and versions remain unchanged', () => {
    withMockBrowserStorage((store) => {
      store.set(
        'daywell_accounts',
        JSON.stringify([
          {
            id: 'acc-user-cbe',
            name: 'My CBE',
            type: 'asset',
            currencyCode: 'ETB',
            openingBalanceCents: 250000,
            isArchived: false,
          },
        ])
      );
      store.set(
        'daywell_tasks',
        JSON.stringify([
          {
            id: 'task-user-1',
            title: 'Submit tax form',
            priority: 'high',
            completed: false,
            createdAt: '2026-11-15T07:00:00.000Z',
          },
        ])
      );
      store.set(
        'daywell_notes',
        JSON.stringify([
          {
            id: 'note-user-1',
            title: 'Architecture Notes',
            content: 'Keep local-first guarantees intact',
            notebook: 'Work',
            tags: ['eng'],
            isPinned: true,
            isArchived: false,
            createdAt: '2026-11-15T07:00:00.000Z',
            updatedAt: '2026-11-15T07:00:00.000Z',
          },
        ])
      );
      store.set(
        'daywell_commitments',
        JSON.stringify([
          {
            id: 'com-user-1',
            title: 'Rent',
            amountCents: 800000,
            dueDate: '2026-11-30',
            isPaid: false,
            direction: 'outflow',
          },
        ])
      );
      store.set(
        SharedStateBridge.PROJECTS_STORAGE_KEY,
        JSON.stringify([{ id: 'proj-u1', title: 'Q4 Audit', status: 'active' }])
      );

      const assembled = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(assembled.schemaVersion, 5);
      assert.strictEqual(assembled.financeSchemaVersion, 7);
      assert.strictEqual(assembled.accounts.length, 1);
      assert.strictEqual(assembled.accounts[0].id, 'acc-user-cbe');
      assert.strictEqual(assembled.tasks.length, 1);
      assert.strictEqual(assembled.tasks[0].id, 'task-user-1');
      assert.strictEqual(assembled.notes.length, 1);
      assert.strictEqual(assembled.notes[0].id, 'note-user-1');
      assert.strictEqual(assembled.commitments?.length, 1);
      assert.strictEqual(assembled.commitments?.[0].id, 'com-user-1');
      assert.strictEqual(assembled.projects.length, 1);
      assert.strictEqual(assembled.projects[0].id, 'proj-u1');
    });
  });

  it('8. Hydration and subsequent assembly do not duplicate records', () => {
    withMockBrowserStorage((store) => {
      const payload = {
        ...CANONICAL_SEED_DATABASE,
        projects: [
          { id: 'proj-dup', title: 'Build Daywell', status: 'active', goalId: 'goal-dup' },
          { id: 'proj-dup', title: 'Build Daywell Duplicate', status: 'completed' },
        ],
        goals: [
          { id: 'goal-dup', title: 'Ship Reliable v7', status: 'active' },
          { id: 'goal-dup', title: 'Ship Reliable v7 Duplicate', status: 'achieved' },
        ],
        inboxItems: [
          {
            id: 'inbox-dup',
            rawText: 'Verify backup encryption',
            category: 'task',
            isProcessed: false,
            createdAt: '2026-11-15T10:00:00.000Z',
          },
          {
            id: 'inbox-dup',
            rawText: 'Verify backup encryption',
            category: 'task',
            isProcessed: false,
            createdAt: '2026-11-15T10:00:00.000Z',
          },
        ],
      };

      const json = JSON.stringify(payload);
      const firstImport = SharedStateBridge.importFromAndroidJson(json);
      assert.strictEqual(firstImport.success, true);
      assert.strictEqual(firstImport.state?.projects.length, 1);
      assert.strictEqual(firstImport.state?.goals.length, 1);
      assert.strictEqual(firstImport.state?.inboxItems.length, 1);

      // Re-assemble and re-import multiple times
      const assembledOnce = SharedStateBridge.assembleLiveDatabaseState();
      SharedStateBridge.saveCanonicalState(assembledOnce);
      const secondImport = SharedStateBridge.importFromAndroidJson(
        SharedStateBridge.exportToAndroidJson()
      );
      assert.strictEqual(secondImport.success, true);

      const assembledTwice = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(assembledTwice.projects.length, 1);
      assert.strictEqual(assembledTwice.goals.length, 1);
      assert.strictEqual(assembledTwice.inboxItems.length, 1);
      assert.strictEqual(assembledTwice.projects[0].goalId, 'goal-dup');

      // Live stores stay synchronized as single non-duplicated arrays
      assert.strictEqual(JSON.parse(store.get(SharedStateBridge.PROJECTS_STORAGE_KEY)!).length, 1);
      assert.strictEqual(JSON.parse(store.get(SharedStateBridge.GOALS_STORAGE_KEY)!).length, 1);
      assert.strictEqual(JSON.parse(store.get(SharedStateBridge.INBOX_STORAGE_KEY)!).length, 1);
    });
  });

  it('9. Empty collections are handled cleanly without inserting demo records', () => {
    withMockBrowserStorage((store) => {
      const freshAssembled = SharedStateBridge.assembleLiveDatabaseState();
      assert.deepStrictEqual(freshAssembled.projects, []);
      assert.deepStrictEqual(freshAssembled.goals, []);
      assert.deepStrictEqual(freshAssembled.inboxItems, []);

      // Explicitly empty stored arrays remain empty
      store.set(SharedStateBridge.PROJECTS_STORAGE_KEY, JSON.stringify([]));
      store.set(SharedStateBridge.GOALS_STORAGE_KEY, JSON.stringify([]));
      store.set(SharedStateBridge.INBOX_STORAGE_KEY, JSON.stringify([]));

      const explicitEmptyAssembled = SharedStateBridge.assembleLiveDatabaseState();
      assert.deepStrictEqual(explicitEmptyAssembled.projects, []);
      assert.deepStrictEqual(explicitEmptyAssembled.goals, []);
      assert.deepStrictEqual(explicitEmptyAssembled.inboxItems, []);
    });
  });

  it('10. Stage 3.4.4: SharedStateBridge round-trips optional reminders and appSettings (including title/channelId & normalized targetId)', () => {
    withMockBrowserStorage((store) => {
      const incoming = {
        ...CANONICAL_SEED_DATABASE,
        schemaVersion: 5,
        financeSchemaVersion: 7,
        reminders: [
          {
            id: 'rem-task-1',
            targetId: 'task-1',
            targetType: 'task',
            triggerTimeUtc: '2026-12-01T06:00:00.000Z',
            isActive: true,
            createdAt: '2026-11-15T08:00:00.000Z',
          },
          {
            id: 'rem-custom-1',
            targetType: 'custom',
            title: 'Evening Reflection',
            channelId: 'daily-check',
            triggerTimeUtc: '2026-12-01T18:00:00.000Z',
            isActive: false,
            createdAtUtc: '2026-11-15T09:00:00.000Z',
          },
        ],
        appSettings: [
          {
            key: 'default_currency',
            value: 'ETB',
            updatedAt: '2026-11-15T08:00:00.000Z',
          },
          {
            key: 'calendar_display_mode',
            value: 'dual',
            updatedAt: '2026-11-15T08:05:00.000Z',
          },
        ],
      };

      const res = SharedStateBridge.importFromAndroidJson(JSON.stringify(incoming));
      assert.strictEqual(res.success, true, res.error);
      assert.strictEqual(res.state?.reminders?.length, 2);
      assert.strictEqual(res.state?.reminders?.[0].targetId, 'task-1');
      assert.strictEqual(res.state?.reminders?.[1].targetId, 'rem-custom-1');
      assert.strictEqual(res.state?.reminders?.[1].title, 'Evening Reflection');
      assert.strictEqual(res.state?.reminders?.[1].channelId, 'daily-check');
      assert.strictEqual(res.state?.reminders?.[1].isActive, false);
      assert.deepStrictEqual(
        res.state?.appSettings?.map((s) => s.key),
        ['calendar_display_mode', 'default_currency']
      );

      // Verify full localStorage + assembleLiveDatabaseState round-trip
      assert.ok(store.has(SharedStateBridge.REMINDERS_STORAGE_KEY));
      assert.ok(store.has(SharedStateBridge.APP_SETTINGS_STORAGE_KEY));
      const assembled = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(assembled.reminders?.length, 2);
      assert.strictEqual(assembled.reminders?.[1].title, 'Evening Reflection');
      assert.strictEqual(assembled.reminders?.[1].channelId, 'daily-check');
      assert.deepStrictEqual(
        assembled.appSettings?.map((s) => `${s.key}=${s.value}`),
        ['calendar_display_mode=dual', 'default_currency=ETB']
      );
    });
  });

  it('11. Stage 3.4.4: Secret/internal keys in appSettings are excluded cleanly and malformed reminders/appSettings fail closed without mutating localStorage', () => {
    withMockBrowserStorage((store) => {
      // Filtered excluded keys on valid import
      const filteredPayload = {
        ...CANONICAL_SEED_DATABASE,
        schemaVersion: 5,
        financeSchemaVersion: 7,
        appSettings: [
          { key: 'calendar_preference', value: 'ethiopian' },
          { key: 'initial_seed_completed', value: 'false' },
          { key: 'ledger_v6_migrated_at', value: '1999-01-01' },
          { key: 'opening_balance_cents', value: '999999' },
          { key: 'secret_backup_key', value: 'super-secret' },
          { key: 'token_refresh', value: 'tok-123' },
          { key: 'push_token', value: 'fcm-123' },
          { key: 'device_install_id', value: 'dev-1' },
          { key: 'transient_ui_banner', value: 'dismissed' },
        ],
      };
      const filteredRes = SharedStateBridge.importFromAndroidJson(JSON.stringify(filteredPayload));
      assert.strictEqual(filteredRes.success, true, filteredRes.error);
      assert.deepStrictEqual(
        filteredRes.state?.appSettings?.map((s) => s.key),
        ['calendar_preference']
      );

      const snapshotBeforeRejection = new Map(store);
      const invalidPayloads = [
        {
          name: 'invalid reminder targetType',
          payload: {
            ...CANONICAL_SEED_DATABASE,
            reminders: [
              {
                id: 'r1',
                targetId: 't1',
                targetType: 'unknown_type',
                triggerTimeUtc: '2026-12-01T08:00:00.000Z',
                createdAt: '2026-11-15T08:00:00.000Z',
              },
            ],
          },
        },
        {
          name: 'entity reminder missing targetId',
          payload: {
            ...CANONICAL_SEED_DATABASE,
            reminders: [
              {
                id: 'r2',
                targetType: 'task',
                triggerTimeUtc: '2026-12-01T08:00:00.000Z',
                createdAt: '2026-11-15T08:00:00.000Z',
              },
            ],
          },
        },
        {
          name: 'duplicate reminder id',
          payload: {
            ...CANONICAL_SEED_DATABASE,
            reminders: [
              {
                id: 'r-dup',
                targetType: 'custom',
                triggerTimeUtc: '2026-12-01T08:00:00.000Z',
                createdAt: '2026-11-15T08:00:00.000Z',
              },
              {
                id: 'r-dup',
                targetType: 'custom',
                triggerTimeUtc: '2026-12-02T08:00:00.000Z',
                createdAt: '2026-11-15T08:00:00.000Z',
              },
            ],
          },
        },
        {
          name: 'invalid appSetting non-string value',
          payload: {
            ...CANONICAL_SEED_DATABASE,
            appSettings: [{ key: 'calendar_preference', value: 123 }],
          },
        },
        {
          name: 'duplicate appSetting key',
          payload: {
            ...CANONICAL_SEED_DATABASE,
            appSettings: [
              { key: 'calendar_preference', value: 'ethiopian' },
              { key: 'calendar_preference', value: 'gregorian' },
            ],
          },
        },
      ];

      for (const tc of invalidPayloads) {
        const res = SharedStateBridge.importFromAndroidJson(JSON.stringify(tc.payload));
        assert.strictEqual(res.success, false, `${tc.name} must fail closed`);
        assert.strictEqual(res.errorKind, 'invalid_payload', tc.name);
        assert.strictEqual(store.size, snapshotBeforeRejection.size, tc.name);
        for (const [k, v] of snapshotBeforeRejection.entries()) {
          assert.strictEqual(store.get(k), v, `${tc.name} mutated ${k}`);
        }
      }
    });
  });

  it('12. Stage 3.4.4: Omitted reminders and appSettings remain optional and backward-compatible with pre-3.4.4 payloads', () => {
    withMockBrowserStorage((store) => {
      const legacyPayload = {
        ...CANONICAL_SEED_DATABASE,
        schemaVersion: 5,
        financeSchemaVersion: 7,
        projects: [{ id: 'proj-leg', title: 'Legacy Project', status: 'active' }],
      };
      const res = SharedStateBridge.importFromAndroidJson(JSON.stringify(legacyPayload));
      assert.strictEqual(res.success, true, res.error);
      assert.strictEqual(res.state?.reminders, undefined);
      assert.strictEqual(res.state?.appSettings, undefined);
      assert.strictEqual(store.has(SharedStateBridge.REMINDERS_STORAGE_KEY), false);
      assert.strictEqual(store.has(SharedStateBridge.APP_SETTINGS_STORAGE_KEY), false);
    });
  });

  it('13. Stage 3.4.4.1: Android v8 snapshot round-trips through Web bridge preserving Reminder title/channelId while emitting schemaVersion 5', () => {
    withMockBrowserStorage(() => {
      const androidV8Payload = {
        ...CANONICAL_SEED_DATABASE,
        schemaVersion: 8,
        financeSchemaVersion: 7,
        accounts: [
          {
            id: 'acc-cbe',
            name: 'CBE Main',
            type: 'asset',
            subType: 'bank',
            currencyCode: 'ETB',
            openingBalanceCents: 100000,
            isArchived: false,
          },
        ],
        categories: [
          {
            id: 'cat-food',
            name: 'Food',
            type: 'expense',
            colorHex: '#EF4444',
          },
        ],
        transactions: [
          {
            id: 'tx-xfer-8',
            amountCents: 5000,
            type: 'transfer',
            accountId: 'acc-cbe',
            destinationAccountId: 'acc-cash',
            categoryId: 'cat-other-exp',
            transactionDate: '2026-11-15',
          },
        ],
        reminders: [
          {
            id: 'rem-v8-1',
            targetId: 'task-1',
            targetType: 'task',
            triggerTimeUtc: '2026-12-01T07:30:00.000Z',
            isActive: true,
            createdAt: '2026-11-15T07:00:00.000Z',
            title: '  Standup Reminder  ',
            channelId: '  work-alerts  ',
          },
          {
            id: 'rem-v8-empty',
            targetId: 'rem-v8-empty',
            targetType: 'custom',
            triggerTimeUtc: '2026-12-01T08:30:00.000Z',
            isActive: true,
            createdAt: '2026-11-15T07:00:00.000Z',
            title: '   ',
            channelId: '',
          },
        ],
      };

      const imported = SharedStateBridge.importFromAndroidJson(JSON.stringify(androidV8Payload));
      assert.strictEqual(imported.success, true, imported.error);
      assert.strictEqual(imported.state?.schemaVersion, 8);
      assert.strictEqual(imported.state?.reminders?.[0].title, 'Standup Reminder');
      assert.strictEqual(imported.state?.reminders?.[0].channelId, 'work-alerts');
      assert.strictEqual(imported.state?.reminders?.[1].title, undefined);
      assert.strictEqual(imported.state?.reminders?.[1].channelId, undefined);

      const exported = JSON.parse(SharedStateBridge.exportToAndroidJson());
      assert.strictEqual(exported.schemaVersion, 5);
      assert.strictEqual(exported.financeSchemaVersion, 7);
      assert.strictEqual(exported.reminders?.[0].title, 'Standup Reminder');
      assert.strictEqual(exported.reminders?.[0].channelId, 'work-alerts');
      assert.strictEqual(exported.reminders?.[1].title, undefined);
      assert.strictEqual(exported.reminders?.[1].channelId, undefined);
    });
  });

  it('14. Stage 3.4.4.1: Enforces Drift string max lengths, strictly positive amounts, and v7+ vs pre-v7 transfer categoryId parity before mutating localStorage', () => {
    withMockBrowserStorage((store) => {
      // Establish baseline storage state to verify no mutation occurs on rejection
      const seedRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          ...CANONICAL_SEED_DATABASE,
          schemaVersion: 5,
          accounts: [
            {
              id: 'acc-seed-keep',
              name: 'Keep Account',
              type: 'asset',
              currencyCode: 'ETB',
              openingBalanceCents: 1000,
              isArchived: false,
            },
          ],
        })
      );
      assert.strictEqual(seedRes.success, true);
      const baselineAccounts = store.get('daywell_accounts');

      // 14a. All 12 Drift withLength bounds reject (max + 1) pre-mutation
      const lengthOverflowCases: Array<{ label: string; patch: Record<string, unknown> }> = [
        {
          label: 'categories.name > 100',
          patch: { categories: [{ id: 'c1', name: 'x'.repeat(101), type: 'expense' }] },
        },
        {
          label: 'accounts.name > 150',
          patch: { accounts: [{ id: 'a1', name: 'x'.repeat(151), type: 'asset' }] },
        },
        {
          label: 'parties.name > 150',
          patch: { parties: [{ id: 'p1', name: 'x'.repeat(151) }] },
        },
        {
          label: 'goals.title > 200',
          patch: { goals: [{ id: 'g1', title: 'x'.repeat(201), status: 'active' }] },
        },
        {
          label: 'projects.title > 200',
          patch: { projects: [{ id: 'pr1', title: 'x'.repeat(201), status: 'active' }] },
        },
        {
          label: 'milestones.title > 200',
          patch: { milestones: [{ id: 'm1', projectId: 'pr1', title: 'x'.repeat(201) }] },
        },
        {
          label: 'tasks.title > 300',
          patch: { tasks: [{ id: 't1', title: 'x'.repeat(301), createdAt: '2026-11-15T00:00:00Z' }] },
        },
        {
          label: 'notes.title > 250',
          patch: { notes: [{ id: 'n1', title: 'x'.repeat(251), body: 'hi', createdAt: '2026-11-15T00:00:00Z', updatedAt: '2026-11-15T00:00:00Z' }] },
        },
        {
          label: 'calendarEvents.title > 250',
          patch: { calendarEvents: [{ id: 'e1', title: 'x'.repeat(251), date: '2026-11-15' }] },
        },
        {
          label: 'savingsGoals.title > 200',
          patch: { savingsGoals: [{ id: 'sg1', title: 'x'.repeat(201), targetCents: 1000 }] },
        },
        {
          label: 'recurringRules.title > 200',
          patch: {
            recurringRules: [
              {
                id: 'rr1',
                title: 'x'.repeat(201),
                ruleType: 'expense',
                amountCents: 100,
                frequency: 'monthly',
                startDate: '2026-11-01',
                nextOccurrenceDate: '2026-12-01',
              },
            ],
          },
        },
        {
          label: 'commitments.title > 200',
          patch: { commitments: [{ id: 'cm1', title: 'x'.repeat(201), amountCents: 100, dueDate: '2026-11-20' }] },
        },
      ];

      for (const tc of lengthOverflowCases) {
        const res = SharedStateBridge.importFromAndroidJson(
          JSON.stringify({
            ...CANONICAL_SEED_DATABASE,
            schemaVersion: 8,
            ...tc.patch,
          })
        );
        assert.strictEqual(res.success, false, `${tc.label} must fail closed`);
        assert.strictEqual(res.errorKind, 'invalid_payload', tc.label);
        assert.strictEqual(store.get('daywell_accounts'), baselineAccounts, `${tc.label} mutated storage`);
      }

      // 14b. Non-positive amounts rejected across finance tables
      const amountCases: Array<{ label: string; patch: Record<string, unknown> }> = [
        {
          label: 'transactions.amountCents = 0',
          patch: {
            transactions: [
              { id: 't0', amountCents: 0, type: 'expense', accountId: 'a1', categoryId: 'c1', transactionDate: '2026-11-15' },
            ],
          },
        },
        {
          label: 'postings.amountCents = 0',
          patch: {
            postings: [
              { id: 'po0', entryId: 'je1', accountId: 'a1', amountCents: 0, direction: 'debit', accountMovementDate: '2026-11-15' },
            ],
          },
        },
        {
          label: 'debts.principalCents = 0',
          patch: { debts: [{ id: 'd0', principalCents: 0 }] },
        },
        {
          label: 'settlementAllocations.allocatedCents = 0',
          patch: {
            settlementAllocations: [{ id: 'sa0', allocatedCents: 0, settlementDate: '2026-11-15' }],
          },
        },
        {
          label: 'savingsGoals.targetCents = 0',
          patch: { savingsGoals: [{ id: 'sg0', title: 'Phone', targetCents: 0 }] },
        },
        {
          label: 'budgets.limitCents = 0',
          patch: { budgets: [{ id: 'b0', categoryId: 'c1', monthIso: '2026-11', limitCents: 0 }] },
        },
        {
          label: 'recurringRules.amountCents = 0',
          patch: {
            recurringRules: [
              {
                id: 'rr0',
                title: 'Gym',
                ruleType: 'expense',
                amountCents: 0,
                frequency: 'monthly',
                startDate: '2026-11-01',
                nextOccurrenceDate: '2026-12-01',
              },
            ],
          },
        },
        {
          label: 'commitments.amountCents = 0',
          patch: { commitments: [{ id: 'cm0', title: 'Bill', amountCents: 0, dueDate: '2026-11-20' }] },
        },
        {
          label: 'commitmentSettlements.amountCents = 0',
          patch: {
            commitmentSettlements: [{ id: 'cs0', amountCents: 0, settledDate: '2026-11-15' }],
          },
        },
      ];

      for (const tc of amountCases) {
        const res = SharedStateBridge.importFromAndroidJson(
          JSON.stringify({
            ...CANONICAL_SEED_DATABASE,
            schemaVersion: 8,
            ...tc.patch,
          })
        );
        assert.strictEqual(res.success, false, `${tc.label} must fail closed`);
        assert.strictEqual(res.errorKind, 'invalid_payload', tc.label);
        assert.strictEqual(store.get('daywell_accounts'), baselineAccounts, `${tc.label} mutated storage`);
      }

      // 14c. Transfer missing categoryId fails closed on v7 & v8, falls back to cat-other-exp on v6
      for (const strictVer of [7, 8]) {
        const strictRes = SharedStateBridge.importFromAndroidJson(
          JSON.stringify({
            ...CANONICAL_SEED_DATABASE,
            schemaVersion: strictVer,
            transactions: [
              {
                id: `tx-missing-cat-v${strictVer}`,
                amountCents: 2500,
                type: 'transfer',
                accountId: 'acc-1',
                destinationAccountId: 'acc-2',
                transactionDate: '2026-11-15',
              },
            ],
          })
        );
        assert.strictEqual(strictRes.success, false, `v${strictVer} transfer missing categoryId must fail closed`);
        assert.strictEqual(strictRes.errorKind, 'invalid_payload');
      }

      const legacyV6Res = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          ...CANONICAL_SEED_DATABASE,
          schemaVersion: 6,
          transactions: [
            {
              id: 'tx-missing-cat-v6',
              amountCents: 2500,
              type: 'transfer',
              accountId: 'acc-1',
              destinationAccountId: 'acc-2',
              transactionDate: '2026-11-15',
            },
          ],
        })
      );
      assert.strictEqual(legacyV6Res.success, true, legacyV6Res.error);
      assert.strictEqual(legacyV6Res.state?.transactions[0].categoryId, 'cat-other-exp');
    });
  });
});

describe('Governance Stage 3.4.5: SharedStateBridge Compatibility & Round-Trip Fidelity', () => {
  it('1. Full multi-module export -> import -> export round-trip preserves normalized data across all 22 collections', () => {
    withMockBrowserStorage((store) => {
      const fullPayload = {
        schemaVersion: 8,
        financeSchemaVersion: 7,
        appVersion: '1.2.0+8',
        exportedAt: '2026-11-15T12:00:00.000Z',
        isFinanceSetupCompleted: true,
        openingBalanceCents: 550000,
        ledgerMigrationReportV7: '{"migratedCount":1}',
        accounts: [
          {
            id: 'acc-cbe-1',
            name: 'CBE Checking',
            type: 'asset',
            subType: 'bank',
            isSystem: false,
            currencyCode: 'etb',
            openingBalanceCents: 400000,
            openingBalanceDate: '2026-01-01',
            isArchived: false,
          },
          {
            id: 'acc-vault-1',
            name: 'House Vault',
            type: 'asset',
            subType: 'savings_vault',
            isSystem: false,
            currencyCode: 'ETB',
            openingBalanceCents: 150000,
            isArchived: false,
          },
        ],
        categories: [
          {
            id: 'cat-root-exp',
            name: 'Living',
            type: 'expense',
            colorHex: '#1B4D3E',
            sortOrder: 1,
            isDefault: false,
            isArchived: false,
          },
          {
            id: 'cat-groceries',
            name: 'Groceries',
            type: 'expense',
            colorHex: '#EF4444',
            parentId: 'cat-root-exp',
            sortOrder: 2,
            isDefault: false,
            isArchived: false,
          },
          {
            id: 'cat-sal',
            name: 'Salary',
            type: 'income',
            colorHex: '#10B981',
            sortOrder: 3,
            isDefault: false,
            isArchived: false,
          },
        ],
        transactions: [
          {
            id: 'tx-orig-1',
            amountCents: 12000,
            type: 'expense',
            categoryId: 'cat-groceries',
            accountId: 'acc-cbe-1',
            transactionDate: '2026-11-10',
            note: 'Merkato spice run',
            payee: 'Addis Market',
            isSuperseded: true,
            createdAt: '2026-11-10T08:00:00.000Z',
          },
          {
            id: 'tx-corr-1',
            amountCents: 12500,
            type: 'expense',
            categoryId: 'cat-groceries',
            accountId: 'acc-cbe-1',
            transactionDate: '2026-11-10',
            note: 'Corrected spice run',
            payee: 'Addis Market',
            isSuperseded: false,
            correctedFromId: 'tx-orig-1',
            createdAt: '2026-11-10T09:00:00.000Z',
          },
          {
            id: 'tx-xfer-1',
            amountCents: 50000,
            type: 'transfer',
            categoryId: 'cat-other-exp',
            accountId: 'acc-cbe-1',
            destinationAccountId: 'acc-vault-1',
            transactionDate: '2026-11-11',
            createdAt: '2026-11-11T10:00:00.000Z',
          },
        ],
        parties: [
          {
            id: 'party-selam',
            name: 'Selamawit Bekele',
            phone: '+251911000111',
            notes: 'Contractor',
            isArchived: false,
            createdAt: '2026-11-01T08:00:00.000Z',
          },
        ],
        journalEntries: [
          {
            id: 'je-origin-1',
            entryType: 'debt_origin',
            description: 'Advance loan',
            occurrenceDate: '2026-11-05',
            isVoided: false,
            legacySourceTxId: 'tx-corr-1',
            createdAt: '2026-11-05T08:00:00.000Z',
          },
          {
            id: 'je-settle-1',
            entryType: 'debt_settlement',
            description: 'Partial repayment',
            occurrenceDate: '2026-11-12',
            isVoided: false,
            correctedFromEntryId: 'je-origin-1',
            createdAt: '2026-11-12T08:00:00.000Z',
          },
        ],
        postings: [
          {
            id: 'post-1',
            entryId: 'je-origin-1',
            accountId: 'acc-cbe-1',
            amountCents: 30000,
            direction: 'credit',
            accountMovementDate: '2026-11-05',
          },
          {
            id: 'post-2',
            entryId: 'je-origin-1',
            accountId: 'acc-sys-receivable',
            amountCents: 30000,
            direction: 'debit',
            categoryId: 'cat-groceries',
            accountMovementDate: '2026-11-05',
          },
          {
            id: 'post-3',
            entryId: 'je-settle-1',
            accountId: 'acc-cbe-1',
            amountCents: 10000,
            direction: 'debit',
            accountMovementDate: '2026-11-12',
          },
          {
            id: 'post-4',
            entryId: 'je-settle-1',
            accountId: 'acc-sys-receivable',
            amountCents: 10000,
            direction: 'credit',
            accountMovementDate: '2026-11-12',
          },
        ],
        debts: [
          {
            id: 'debt-1',
            originEntryId: 'je-origin-1',
            partyId: 'party-selam',
            debtType: 'receivable',
            principalCents: 30000,
            outstandingCents: 20000,
            dueDate: '2026-12-05',
            status: 'partially_settled',
            writeOffEntryId: 'je-settle-1',
            createdAt: '2026-11-05T08:00:00.000Z',
          },
        ],
        settlementAllocations: [
          {
            id: 'sa-1',
            settlementEntryId: 'je-settle-1',
            debtId: 'debt-1',
            allocatedCents: 10000,
            settlementDate: '2026-11-12',
          },
        ],
        recurringRules: [
          {
            id: 'rr-1',
            title: 'Monthly Fiber',
            ruleType: 'expense',
            amountCents: 150000,
            frequency: 'monthly',
            interval: 1,
            startDate: '2026-01-01',
            nextOccurrenceDate: '2026-12-01',
            endDate: '2027-12-01',
            accountId: 'acc-cbe-1',
            categoryId: 'cat-groceries',
            linkedDebtId: 'debt-1',
            isActive: true,
            autoPost: false,
            createdAt: '2026-11-01T08:00:00.000Z',
          },
        ],
        commitments: [
          {
            id: 'com-rent-1',
            title: 'Apartment Lease',
            amountCents: 2500000,
            dueDate: '2026-11-30',
            isPaid: true,
            direction: 'outflow',
            legacyPaidUnverified: false,
            recurringRule: 'monthly',
            linkedAccountId: 'acc-cbe-1',
            categoryId: 'cat-root-exp',
            linkedDebtId: 'debt-1',
            settlementEntryId: 'je-settle-1',
            recurringRuleId: 'rr-1',
          },
        ],
        commitmentSettlements: [
          {
            id: 'cs-1',
            commitmentId: 'com-rent-1',
            entryId: 'je-settle-1',
            amountCents: 2500000,
            settledDate: '2026-11-12',
            createdAt: '2026-11-12T08:00:00.000Z',
          },
        ],
        savingsGoals: [
          {
            id: 'sg-solar-1',
            title: 'Solar Backup',
            targetCents: 5000000,
            currentAllocatedCents: 150000,
            targetDate: '2027-06-01',
            linkedAccountId: 'acc-vault-1',
            status: 'active',
          },
        ],
        budgets: [
          {
            id: 'bgt-1',
            categoryId: 'cat-groceries',
            monthIso: '2026-11',
            limitCents: 600000,
            rolloverEnabled: true,
            createdAt: '2026-11-01T00:00:00.000Z',
            updatedAt: '2026-11-10T00:00:00.000Z',
          },
        ],
        goals: [
          {
            id: 'goal-10',
            title: 'Launch Consulting Practice',
            description: 'Independent fintech design',
            status: 'active',
            targetDate: '2027-03-01',
          },
        ],
        projects: [
          {
            id: 'proj-10',
            title: 'Portfolio Website v2',
            description: 'Dual-calendar showcase',
            status: 'active',
            targetDate: '2026-12-20',
            goalId: 'goal-10',
          },
        ],
        milestones: [
          {
            id: 'ms-10',
            projectId: 'proj-10',
            title: 'Complete Figma Case Studies',
            dueDate: '2026-12-05',
            isCompleted: false,
            createdAt: '2026-11-10T08:00:00.000Z',
          },
        ],
        tasks: [
          {
            id: 'task-10',
            title: 'Ship responsive grid',
            description: 'Verify mobile + desktop breakpoints',
            status: 'in_progress',
            priority: 'urgent',
            dueDate: '2026-12-04',
            scheduledDate: '2026-12-01',
            projectId: 'proj-10',
            milestoneId: 'ms-10',
            estimatedDurationMinutes: 90,
            subtasks: [
              { id: 'st-a', title: 'Audit tokens', done: true },
              { id: 'st-b', title: 'Verify spacing', done: false },
            ],
            labels: ['design', 'ui'],
            isPinned: true,
            isMyDay: true,
            recurrenceRule: 'weekly',
            createdAt: '2026-11-10T09:00:00.000Z',
            updatedAt: '2026-11-15T10:00:00.000Z',
          },
        ],
        notes: [
          {
            id: 'note-10',
            title: 'Design Token Notes',
            body: 'Keep emerald #1B4D3E canonical across platforms.',
            folder: 'Architecture',
            tags: ['tokens', 'parity'],
            isPinned: true,
            isFavorite: true,
            isArchived: false,
            isTrashed: false,
            projectId: 'proj-10',
            goalId: 'goal-10',
            linkedModule: 'tasks',
            linkedId: 'task-10',
            createdAt: '2026-11-10T09:30:00.000Z',
            updatedAt: '2026-11-15T10:30:00.000Z',
          },
        ],
        inboxItems: [
          {
            id: 'inbox-10',
            rawText: 'Follow up with studio print vendor',
            category: 'decision',
            isProcessed: false,
            createdAt: '2026-11-15T07:45:00.000Z',
          },
        ],
        calendarEvents: [
          {
            id: 'evt-10',
            title: 'Client Sign-Off Call',
            date: '2026-12-04',
            endDate: '2026-12-04',
            startTime: '14:00',
            endTime: '15:00',
            isAllDay: false,
            category: 'work',
            colorHex: '#1B4D3E',
            hasReminder: true,
            notes: 'Bring Q4 timeline',
            description: 'Milestone review',
            location: 'Bole Atlas',
            recurrence: 'none',
            linkedTaskId: 'task-10',
            createdAt: '2026-11-12T08:00:00.000Z',
            updatedAt: '2026-11-15T08:00:00.000Z',
          },
        ],
        reminders: [
          {
            id: 'rem-10',
            targetId: 'task-10',
            targetType: 'task',
            triggerTimeUtc: '2026-12-04T06:00:00.000Z',
            isActive: true,
            title: 'Grid ship reminder',
            channelId: 'tasks-high',
            createdAt: '2026-11-15T08:00:00.000Z',
          },
        ],
        appSettings: [
          { key: 'theme_mode', value: 'dark', updatedAt: '2026-11-15T08:00:00.000Z' },
          { key: 'calendar_display_mode', value: 'dual', updatedAt: '2026-11-15T08:00:00.000Z' },
        ],
      };

      const import1 = SharedStateBridge.importFromAndroidJson(JSON.stringify(fullPayload));
      assert.strictEqual(import1.success, true, import1.error);
      const exportedJson1 = SharedStateBridge.exportToAndroidJson();
      const exported1 = JSON.parse(exportedJson1);

      // Re-import exported v5 snapshot into a wiped localStorage and export again
      store.clear();
      const import2 = SharedStateBridge.importFromAndroidJson(exportedJson1);
      assert.strictEqual(import2.success, true, import2.error);
      const exported2 = JSON.parse(SharedStateBridge.exportToAndroidJson());

      assert.strictEqual(exported1.schemaVersion, 5);
      assert.strictEqual(exported1.financeSchemaVersion, 7);
      assert.strictEqual(exported2.schemaVersion, 5);
      assert.strictEqual(exported2.financeSchemaVersion, 7);

      const { exportedAt: _e1, ...comparable1 } = exported1;
      const { exportedAt: _e2, ...comparable2 } = exported2;
      assert.deepStrictEqual(comparable2, comparable1);

      // Spot-check normalized fields across modules
      assert.strictEqual(exported1.openingBalanceCents, 550000);
      assert.strictEqual(exported1.ledgerMigrationReportV7, '{"migratedCount":1}');
      assert.strictEqual(exported1.accounts[0].currencyCode, 'ETB');
      assert.strictEqual(Object.prototype.hasOwnProperty.call(exported1.accounts[0], 'isActive'), false);
      assert.deepStrictEqual(
        exported1.journalEntries.map((j: any) => j.entryType),
        ['debt_issuance', 'settlement']
      );
      assert.strictEqual(exported1.debts[0].status, 'active');
      assert.strictEqual(exported1.categories[1].parentId, 'cat-root-exp');
      assert.strictEqual(exported1.milestones[0].projectId, 'proj-10');
      assert.strictEqual(exported1.tasks[0].milestoneId, 'ms-10');
      assert.strictEqual(exported1.notes[0].linkedModule, 'tasks');
      assert.strictEqual(exported1.calendarEvents[0].linkedTaskId, 'task-10');
      assert.strictEqual(exported1.reminders[0].channelId, 'tasks-high');
      assert.deepStrictEqual(
        exported1.appSettings.map((s: any) => s.key),
        ['calendar_display_mode', 'theme_mode']
      );
    });
  });

  it('2. Explicitly empty collections stay empty without resurrecting starter categories or stale settings', () => {
    withMockBrowserStorage((store) => {
      // Seed prior reminders & appSettings first
      const priorImport = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          ...CANONICAL_SEED_DATABASE,
          schemaVersion: 5,
          reminders: [
            {
              id: 'rem-stale',
              targetType: 'custom',
              triggerTimeUtc: '2026-12-01T08:00:00.000Z',
              createdAt: '2026-11-15T08:00:00.000Z',
            },
          ],
          appSettings: [{ key: 'theme_mode', value: 'dark' }],
        })
      );
      assert.strictEqual(priorImport.success, true);
      assert.ok(store.has(SharedStateBridge.APP_SETTINGS_STORAGE_KEY));

      // Now import a completely empty snapshot with reminders & appSettings set to []
      const emptyPayload = {
        schemaVersion: 5,
        financeSchemaVersion: 7,
        appVersion: '1.0.2+3',
        isFinanceSetupCompleted: false,
        openingBalanceCents: 0,
        accounts: [],
        categories: [],
        transactions: [],
        commitments: [],
        commitmentSettlements: [],
        savingsGoals: [],
        budgets: [],
        recurringRules: [],
        parties: [],
        journalEntries: [],
        postings: [],
        debts: [],
        settlementAllocations: [],
        milestones: [],
        tasks: [],
        notes: [],
        projects: [],
        goals: [],
        inboxItems: [],
        calendarEvents: [],
        reminders: [],
        appSettings: [],
      };

      const res = SharedStateBridge.importFromAndroidJson(JSON.stringify(emptyPayload));
      assert.strictEqual(res.success, true, res.error);
      const assembled = SharedStateBridge.assembleLiveDatabaseState();
      const exported = JSON.parse(SharedStateBridge.exportToAndroidJson());

      for (const state of [assembled, exported]) {
        assert.deepStrictEqual(state.accounts, []);
        assert.deepStrictEqual(state.categories, []);
        assert.deepStrictEqual(state.transactions, []);
        assert.deepStrictEqual(state.commitments, []);
        assert.deepStrictEqual(state.commitmentSettlements, []);
        assert.deepStrictEqual(state.savingsGoals, []);
        assert.deepStrictEqual(state.budgets, []);
        assert.deepStrictEqual(state.recurringRules, []);
        assert.deepStrictEqual(state.parties, []);
        assert.deepStrictEqual(state.journalEntries, []);
        assert.deepStrictEqual(state.postings, []);
        assert.deepStrictEqual(state.debts, []);
        assert.deepStrictEqual(state.settlementAllocations, []);
        assert.deepStrictEqual(state.milestones, []);
        assert.deepStrictEqual(state.tasks, []);
        assert.deepStrictEqual(state.notes, []);
        assert.deepStrictEqual(state.projects, []);
        assert.deepStrictEqual(state.goals, []);
        assert.deepStrictEqual(state.inboxItems, []);
        assert.deepStrictEqual(state.calendarEvents, []);
        assert.deepStrictEqual(state.reminders, []);
        assert.deepStrictEqual(state.appSettings, []);
      }

      // Importing a snapshot that omits reminders & appSettings clears stale localStorage keys
      const omittedRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          schemaVersion: 5,
          accounts: [],
          categories: [],
          transactions: [],
        })
      );
      assert.strictEqual(omittedRes.success, true, omittedRes.error);
      assert.strictEqual(store.has(SharedStateBridge.REMINDERS_STORAGE_KEY), false);
      assert.strictEqual(store.has(SharedStateBridge.APP_SETTINGS_STORAGE_KEY), false);
      const assembledOmitted = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(assembledOmitted.reminders, undefined);
      assert.strictEqual(assembledOmitted.appSettings, undefined);
      assert.deepStrictEqual(assembledOmitted.categories, []);
    });
  });

  it('3. Records with missing optional fields normalize cleanly without undefined leaks', () => {
    withMockBrowserStorage(() => {
      const minimalPayload = {
        schemaVersion: 5,
        accounts: [{ id: 'acc-min', name: 'Wallet' }],
        categories: [{ id: 'cat-min', name: 'Misc', type: 'expense' }],
        transactions: [
          {
            id: 'tx-min',
            amountCents: 500,
            type: 'expense',
            categoryId: 'cat-min',
            accountId: 'acc-min',
            transactionDate: '2026-11-15',
          },
        ],
        tasks: [{ id: 'task-min', title: 'Minimal task' }],
        notes: [{ id: 'note-min', title: 'Minimal note' }],
        projects: [{ id: 'proj-min', title: 'Minimal project' }],
        goals: [{ id: 'goal-min', title: 'Minimal goal' }],
        milestones: [{ id: 'ms-min', projectId: 'proj-min', title: 'Minimal milestone' }],
        inboxItems: [{ id: 'inb-min', rawText: 'Quick capture' }],
        calendarEvents: [{ id: 'evt-min', title: 'Doctor', date: '2026-11-20' }],
        commitments: [
          { id: 'com-min', title: 'Water', amountCents: 2500, dueDate: '2026-11-25' },
        ],
        savingsGoals: [{ id: 'sg-min', title: 'Emergency', targetCents: 100000 }],
        parties: [{ id: 'party-min', name: 'Abebe' }],
        reminders: [
          {
            id: 'rem-min',
            targetType: 'custom',
            triggerTimeUtc: '2026-12-01T08:00:00.000Z',
            createdAt: '2026-11-15T08:00:00.000Z',
          },
        ],
        appSettings: [{ key: 'first_day_of_week', value: 'monday' }],
      };

      const res = SharedStateBridge.importFromAndroidJson(JSON.stringify(minimalPayload));
      assert.strictEqual(res.success, true, res.error);
      const exported = JSON.parse(SharedStateBridge.exportToAndroidJson());

      // Stage 2.2: pre-v7 legacy snapshots with omitted currencyCode preserve ''
      // (unverified) rather than silently coercing user accounts to 'ETB'.
      assert.strictEqual(exported.accounts[0].currencyCode, '');
      assert.strictEqual(exported.accounts[0].openingBalanceCents, 0);
      assert.strictEqual(exported.accounts[0].isArchived, false);
      assert.strictEqual(exported.tasks[0].status, 'not_started');
      assert.strictEqual(exported.tasks[0].priority, 'medium');
      assert.deepStrictEqual(exported.tasks[0].subtasks, []);
      assert.deepStrictEqual(exported.tasks[0].labels, []);
      assert.strictEqual(exported.tasks[0].isPinned, false);
      assert.strictEqual(exported.tasks[0].isMyDay, false);
      assert.strictEqual(exported.notes[0].body, '');
      assert.strictEqual(exported.notes[0].folder, 'General');
      assert.deepStrictEqual(exported.notes[0].tags, []);
      assert.strictEqual(exported.calendarEvents[0].isAllDay, false);
      assert.strictEqual(exported.calendarEvents[0].category, 'personal');
      assert.strictEqual(exported.reminders[0].targetId, 'rem-min');
      assert.strictEqual(exported.appSettings[0].updatedAt, undefined);
    });
  });

  it('4. Full Task and Note metadata survives bridge persistence and Web UI compatibility shapes', () => {
    withMockBrowserStorage((store) => {
      const payload = {
        ...CANONICAL_SEED_DATABASE,
        goals: [{ id: 'g-meta', title: 'Career', status: 'active' }],
        projects: [{ id: 'p-meta', title: 'Portfolio', status: 'active', goalId: 'g-meta' }],
        milestones: [{ id: 'm-meta', projectId: 'p-meta', title: 'Draft 1', isCompleted: false }],
        tasks: [
          {
            id: 'task-rich',
            title: 'Cancelled quarterly deck',
            description: 'Keep all audit attachments',
            status: 'cancelled',
            priority: 'high',
            dueDate: '2026-12-10',
            scheduledDate: '2026-12-03',
            projectId: 'p-meta',
            projectName: 'Wrong UI Label Should Not Overwrite ProjectId',
            milestoneId: 'm-meta',
            estimatedDurationMinutes: 45,
            subtasks: [
              { id: 'sub-1', title: 'Check tables', done: true },
              { title: 'Send PDF', completed: false },
            ],
            labels: ['ops', 'q4'],
            isPinned: true,
            isMyDay: false,
            recurrenceRule: 'FREQ=MONTHLY;BYMONTHDAY=1',
            createdAt: '2026-11-10T08:00:00.000Z',
            updatedAt: '2026-11-15T12:00:00.000Z',
          },
          {
            id: 'task-inbox-flag',
            title: 'Inbox status preserved',
            status: 'inbox',
            priority: 'low',
            createdAt: '2026-11-10T08:00:00.000Z',
          },
        ],
        notes: [
          {
            id: 'note-rich',
            title: 'Engineering Log',
            content: 'Imported via Android content field',
            category: 'Engineering',
            tags: ['sqlite', 'drift'],
            isPinned: true,
            isFavorite: true,
            isArchived: true,
            isTrashed: false,
            projectId: 'p-meta',
            goalId: 'g-meta',
            linkedModule: 'calendar',
            linkedId: 'evt-99',
            createdAt: '2026-11-01T10:00:00.000Z',
            updatedAt: '2026-11-15T14:00:00.000Z',
          },
        ],
      };

      const res = SharedStateBridge.importFromAndroidJson(JSON.stringify(payload));
      assert.strictEqual(res.success, true, res.error);

      // Inspect persisted Web module stores directly
      const storedWebTasks = JSON.parse(store.get('daywell_tasks')!);
      assert.strictEqual(storedWebTasks[0].completed, false);
      assert.strictEqual(storedWebTasks[0].status, 'cancelled');
      assert.strictEqual(storedWebTasks[0].projectId, 'p-meta');
      assert.strictEqual(storedWebTasks[0].subtasks[0].id, 'sub-1');
      assert.strictEqual(storedWebTasks[0].subtasks[0].completed, true);
      assert.strictEqual(storedWebTasks[0].subtasks[1].completed, false);

      const storedWebNotes = JSON.parse(store.get('daywell_notes')!);
      assert.strictEqual(storedWebNotes[0].content, 'Imported via Android content field');
      assert.strictEqual(storedWebNotes[0].notebook, 'Engineering');
      assert.strictEqual(storedWebNotes[0].isFavorite, true);
      assert.strictEqual(storedWebNotes[0].isArchived, true);

      // Re-assemble and verify canonical round-trip without losing any metadata
      const assembled = SharedStateBridge.assembleLiveDatabaseState();
      assert.deepStrictEqual(assembled.tasks[0], {
        id: 'task-rich',
        title: 'Cancelled quarterly deck',
        description: 'Keep all audit attachments',
        status: 'cancelled',
        priority: 'high',
        dueDate: '2026-12-10',
        scheduledDate: '2026-12-03',
        projectId: 'p-meta',
        milestoneId: 'm-meta',
        estimatedDurationMinutes: 45,
        subtasks: [
          { id: 'sub-1', title: 'Check tables', done: true },
          { id: 'task-rich-sub-2', title: 'Send PDF', done: false },
        ],
        labels: ['ops', 'q4'],
        isPinned: true,
        isMyDay: false,
        isArchived: false,
        sortOrder: 0,
        recurrenceRule: 'FREQ=MONTHLY;BYMONTHDAY=1',
        createdAt: '2026-11-10T08:00:00.000Z',
        updatedAt: '2026-11-15T12:00:00.000Z',
      });
      assert.strictEqual(assembled.tasks[1].status, 'inbox');

      assert.deepStrictEqual(assembled.notes[0], {
        id: 'note-rich',
        title: 'Engineering Log',
        body: 'Imported via Android content field',
        folder: 'Engineering',
        tags: ['sqlite', 'drift'],
        isPinned: true,
        isFavorite: true,
        isArchived: true,
        isTrashed: false,
        projectId: 'p-meta',
        goalId: 'g-meta',
        linkedModule: 'calendar',
        linkedId: 'evt-99',
        createdAt: '2026-11-01T10:00:00.000Z',
        updatedAt: '2026-11-15T14:00:00.000Z',
      });
    });
  });

  it('5. Reminders & AppSettings preserve full contracts and reject case-insensitive duplicate keys', () => {
    withMockBrowserStorage((store) => {
      const base = SharedStateBridge.assembleLiveDatabaseState();
      const snapshotBefore = new Map(store);
      const dupCase = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          ...base,
          appSettings: [
            { key: 'Theme_Mode', value: 'dark' },
            { key: 'theme_mode', value: 'light' },
          ],
        })
      );
      assert.strictEqual(dupCase.success, false);
      assert.strictEqual(dupCase.errorKind, 'invalid_payload');
      assert.strictEqual(store.size, snapshotBefore.size);

      // Valid import across all 5 reminder targetTypes + secret/internal filtering
      const valid = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          ...base,
          reminders: [
            {
              id: 'r1',
              targetId: 't1',
              targetType: 'task',
              triggerTimeUtc: '2026-12-01T08:00:00.000Z',
              createdAt: '2026-11-15T08:00:00.000Z',
            },
            {
              id: 'r2',
              targetId: 'c1',
              targetType: 'commitment',
              triggerTimeUtc: '2026-12-02T08:00:00.000Z',
              createdAt: '2026-11-15T08:00:00.000Z',
            },
            {
              id: 'r3',
              targetId: 'e1',
              targetType: 'calendar_event',
              triggerTimeUtc: '2026-12-03T08:00:00.000Z',
              createdAt: '2026-11-15T08:00:00.000Z',
            },
            {
              id: 'r4',
              targetId: 'n1',
              targetType: 'note',
              triggerTimeUtc: '2026-12-04T08:00:00.000Z',
              createdAt: '2026-11-15T08:00:00.000Z',
            },
            {
              id: 'r5',
              targetType: 'custom',
              title: 'Water',
              channelId: 'hydration',
              triggerTimeUtc: '2026-12-05T08:00:00.000Z',
              createdAtUtc: '2026-11-15T08:00:00.000Z',
              isActive: false,
            },
          ],
          appSettings: [
            { key: 'zeta_pref', value: 'z' },
            { key: 'alpha_pref', value: 'a', updatedAt: '2026-11-15T09:00:00.000Z' },
            { key: 'AUTH_session', value: 'strip-case-insensitive' },
            { key: 'passphrase_salt', value: 'strip' },
            { key: 'local_cache_ver', value: 'strip' },
          ],
        })
      );
      assert.strictEqual(valid.success, true, valid.error);
      const assembled = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(assembled.reminders?.length, 5);
      assert.strictEqual(assembled.reminders?.[4].targetId, 'r5');
      assert.strictEqual(assembled.reminders?.[4].title, 'Water');
      assert.strictEqual(assembled.reminders?.[4].channelId, 'hydration');
      assert.strictEqual(assembled.reminders?.[4].isActive, false);
      assert.deepStrictEqual(assembled.appSettings, [
        { key: 'alpha_pref', value: 'a', updatedAt: '2026-11-15T09:00:00.000Z' },
        { key: 'zeta_pref', value: 'z' },
      ]);
    });
  });

  it('6. System seed vs user data: purgeKnownSeedData cleans all seed collections and preserves user data and absent keys', () => {
    withMockBrowserStorage((store) => {
      // Fresh uninitialized store seeds canonical categories
      const fresh = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(fresh.categories.length, CANONICAL_SEED_DATABASE.categories.length);

      // Populate mix of seed and user data across extended stores, leaving milestones/reminders unset
      store.set(
        'daywell_accounts',
        JSON.stringify([
          { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 0, isArchived: false },
          { id: 'acc-boa', name: 'BoA', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 0, isArchived: false },
          { id: 'acc-user-personal', name: 'Personal Cash', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 5000, isArchived: false },
        ])
      );
      store.set(
        'daywell_finance_transactions',
        JSON.stringify([
          { id: 'tx-seed-1', amountCents: 100, type: 'expense', accountId: 'acc-boa', categoryId: 'cat-food', transactionDate: '2026-11-10' },
          { id: 'tx-user-keep', amountCents: 2500, type: 'expense', accountId: 'acc-cbe', categoryId: 'cat-food', transactionDate: '2026-11-14' },
        ])
      );
      store.set(
        'daywell_calendar_events',
        JSON.stringify([
          { id: 'evt-1', title: 'Seed event', date: '2026-11-15' },
          { id: 'evt-user-1', title: 'User event', date: '2026-11-16' },
        ])
      );
      store.set(
        'daywell_commitments',
        JSON.stringify([
          { id: 'com-1', title: 'Seed commitment', amountCents: 1000, dueDate: '2026-11-20', isPaid: false },
          { id: 'com-user-1', title: 'User commitment', amountCents: 2000, dueDate: '2026-11-21', isPaid: false },
        ])
      );
      store.set(
        'daywell_savings_goals',
        JSON.stringify([
          { id: 'sav-1', title: 'Seed sav', targetCents: 5000, currentAllocatedCents: 0 },
          { id: 'sav-user-1', title: 'User sav', targetCents: 9000, currentAllocatedCents: 0 },
        ])
      );
      store.set(
        'daywell_parties',
        JSON.stringify([
          { id: 'party-abebe', name: 'Abebe', isArchived: false, createdAt: '2026-11-01T00:00:00.000Z' },
          { id: 'party-user-1', name: 'Mekdes', isArchived: false, createdAt: '2026-11-01T00:00:00.000Z' },
        ])
      );

      const purge = SharedStateBridge.purgeKnownSeedData();
      // Removed: tx-seed-1 (1) + acc-boa (1, acc-cbe kept for tx-user-keep!) + evt-1 (1) + com-1 (1) + sav-1 (1) + party-abebe (1) = 6
      assert.strictEqual(purge.purgedCount, 6);

      assert.deepStrictEqual(
        JSON.parse(store.get('daywell_accounts')!).map((a: any) => a.id),
        ['acc-cbe', 'acc-user-personal']
      );
      assert.deepStrictEqual(
        JSON.parse(store.get('daywell_finance_transactions')!).map((t: any) => t.id),
        ['tx-user-keep']
      );
      assert.deepStrictEqual(
        JSON.parse(store.get('daywell_calendar_events')!).map((e: any) => e.id),
        ['evt-user-1']
      );
      assert.deepStrictEqual(
        JSON.parse(store.get('daywell_commitments')!).map((c: any) => c.id),
        ['com-user-1']
      );
      assert.deepStrictEqual(
        JSON.parse(store.get('daywell_savings_goals')!).map((s: any) => s.id),
        ['sav-user-1']
      );
      assert.deepStrictEqual(
        JSON.parse(store.get('daywell_parties')!).map((p: any) => p.id),
        ['party-user-1']
      );

      // Unset keys were never materialized as []
      assert.strictEqual(store.has('daywell_tasks'), false);
      assert.strictEqual(store.has('daywell_notes'), false);
      assert.strictEqual(store.has(SharedStateBridge.MILESTONES_STORAGE_KEY), false);
    });
  });

  it('7. Relationships & foreign keys: preserves valid graph links while clearing dangling Tier-2 refs and breaking multi-node cycles', () => {
    withMockBrowserStorage(() => {
      const res = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          ...CANONICAL_SEED_DATABASE,
          categories: [
            { id: 'cat-c1', name: 'C1', type: 'expense', parentId: 'cat-c2' },
            { id: 'cat-c2', name: 'C2', type: 'expense', parentId: 'cat-c1' },
            { id: 'cat-orphan', name: 'Orphan', type: 'expense', parentId: 'cat-missing' },
          ],
          accounts: [
            { id: 'acc-1', name: 'Bank', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 10000, isArchived: false },
          ],
          transactions: [
            { id: 'tx-1', amountCents: 1000, type: 'expense', categoryId: 'cat-c1', accountId: 'acc-1', transactionDate: '2026-11-10', correctedFromId: 'tx-2' },
            { id: 'tx-2', amountCents: 1000, type: 'expense', categoryId: 'cat-c1', accountId: 'acc-1', transactionDate: '2026-11-10', correctedFromId: 'tx-1' },
          ],
          goals: [{ id: 'g-valid', title: 'Valid Goal', status: 'active' }],
          projects: [
            { id: 'p-valid', title: 'Valid Project', status: 'active', goalId: 'g-valid' },
            { id: 'p-dangling', title: 'Dangling Goal Project', status: 'active', goalId: 'g-missing' },
          ],
          milestones: [{ id: 'ms-valid', projectId: 'p-valid', title: 'Valid MS', isCompleted: false }],
          tasks: [
            {
              id: 't-dangling',
              title: 'Task with bad project and milestone',
              projectId: 'p-missing',
              milestoneId: 'ms-missing',
              createdAt: '2026-11-15T08:00:00.000Z',
            },
          ],
          notes: [
            {
              id: 'n-dangling',
              title: 'Note with bad refs',
              body: 'Check cleanup',
              projectId: 'p-missing',
              goalId: 'g-missing',
              createdAt: '2026-11-15T08:00:00.000Z',
              updatedAt: '2026-11-15T08:00:00.000Z',
            },
          ],
          commitments: [
            {
              id: 'c-dangling',
              title: 'Commitment bad links',
              amountCents: 500,
              dueDate: '2026-11-25',
              linkedAccountId: 'acc-missing',
              categoryId: 'cat-missing',
              linkedDebtId: 'debt-missing',
              settlementEntryId: 'je-missing',
              recurringRuleId: 'rr-missing',
            },
          ],
          savingsGoals: [
            {
              id: 'sg-dangling',
              title: 'Savings bad link',
              targetCents: 10000,
              linkedAccountId: 'acc-missing',
            },
          ],
        })
      );

      assert.strictEqual(res.success, true, res.error);
      const exported = JSON.parse(SharedStateBridge.exportToAndroidJson());

      // Cycle broken on categories & transactions, orphan cleared
      assert.strictEqual(exported.categories[2].parentId, undefined);
      assert.notStrictEqual(
        exported.categories[0].parentId && exported.categories[1].parentId,
        'cat-c1'
      );
      assert.ok(!(exported.transactions[0].correctedFromId && exported.transactions[1].correctedFromId));

      // Tier-2 valid kept, dangling cleared
      assert.strictEqual(exported.projects[0].goalId, 'g-valid');
      assert.strictEqual(exported.projects[1].goalId, undefined);
      assert.strictEqual(exported.tasks[0].projectId, undefined);
      assert.strictEqual(exported.tasks[0].milestoneId, undefined);
      assert.strictEqual(exported.notes[0].projectId, undefined);
      assert.strictEqual(exported.notes[0].goalId, undefined);
      assert.strictEqual(exported.commitments[0].linkedAccountId, undefined);
      assert.strictEqual(exported.commitments[0].categoryId, undefined);
      assert.strictEqual(exported.commitments[0].linkedDebtId, undefined);
      assert.strictEqual(exported.commitments[0].settlementEntryId, undefined);
      assert.strictEqual(exported.commitments[0].recurringRuleId, undefined);
      assert.strictEqual(exported.savingsGoals[0].linkedAccountId, undefined);
    });
  });

  it('8. Repeated imports of the same snapshot remain idempotent with zero duplication', () => {
    withMockBrowserStorage(() => {
      const payload = {
        ...CANONICAL_SEED_DATABASE,
        schemaVersion: 5,
        accounts: [
          { id: 'acc-r1', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 20000, isArchived: false },
        ],
        transactions: [
          { id: 'tx-r1', amountCents: 1200, type: 'expense', categoryId: 'cat-food', accountId: 'acc-r1', transactionDate: '2026-11-15' },
        ],
        goals: [{ id: 'g-r1', title: 'Goal', status: 'active' }],
        projects: [{ id: 'p-r1', title: 'Proj', status: 'active', goalId: 'g-r1' }],
        milestones: [{ id: 'ms-r1', projectId: 'p-r1', title: 'MS', isCompleted: false }],
        tasks: [{ id: 't-r1', title: 'Task', projectId: 'p-r1', milestoneId: 'ms-r1', createdAt: '2026-11-15T08:00:00.000Z' }],
        notes: [{ id: 'n-r1', title: 'Note', body: 'Hello', createdAt: '2026-11-15T08:00:00.000Z', updatedAt: '2026-11-15T08:00:00.000Z' }],
        calendarEvents: [{ id: 'e-r1', title: 'Event', date: '2026-11-18' }],
        reminders: [{ id: 'rem-r1', targetId: 't-r1', targetType: 'task', triggerTimeUtc: '2026-11-18T08:00:00.000Z', createdAt: '2026-11-15T08:00:00.000Z' }],
        appSettings: [{ key: 'language', value: 'am' }],
      };

      assert.strictEqual(SharedStateBridge.importFromAndroidJson(JSON.stringify(payload)).success, true);
      const export1 = SharedStateBridge.exportToAndroidJson();
      assert.strictEqual(SharedStateBridge.importFromAndroidJson(export1).success, true);
      const export2 = SharedStateBridge.exportToAndroidJson();
      assert.strictEqual(SharedStateBridge.importFromAndroidJson(export2).success, true);
      const export3 = SharedStateBridge.exportToAndroidJson();

      const { exportedAt: _a, ...p1 } = JSON.parse(export1);
      const { exportedAt: _b, ...p3 } = JSON.parse(export3);
      assert.deepStrictEqual(p3, p1);
    });
  });

  it('9. Malformed records and invalid Tier-1 references fail closed pre-mutation across all collections', () => {
    withMockBrowserStorage((store) => {
      const validBaseline = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          ...CANONICAL_SEED_DATABASE,
          accounts: [
            { id: 'acc-keep', name: 'Keep Bank', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 10000, isArchived: false },
          ],
          projects: [{ id: 'proj-keep', title: 'Keep Project', status: 'active' }],
          parties: [{ id: 'party-keep', name: 'Keep Party' }],
          journalEntries: [
            { id: 'je-keep', entryType: 'standard', occurrenceDate: '2026-11-10', createdAt: '2026-11-10T08:00:00.000Z' },
          ],
        })
      );
      assert.strictEqual(validBaseline.success, true);
      const baselineStoreSnapshot = new Map(store);

      const basePayload = {
        ...CANONICAL_SEED_DATABASE,
        schemaVersion: 5,
        financeSchemaVersion: 7,
        accounts: [{ id: 'a1', name: 'Bank', type: 'asset', currencyCode: 'ETB' }],
        categories: [{ id: 'c1', name: 'Food', type: 'expense' }],
        transactions: [],
        projects: [{ id: 'p1', title: 'Proj', status: 'active' }],
        parties: [{ id: 'pa1', name: 'Party' }],
        journalEntries: [
          { id: 'je1', entryType: 'standard', occurrenceDate: '2026-11-10' },
          { id: 'je2', entryType: 'debt_settlement', occurrenceDate: '2026-11-12' },
        ],
        debts: [
          { id: 'd1', originEntryId: 'je1', partyId: 'pa1', debtType: 'payable', principalCents: 1000 },
        ],
        commitments: [
          { id: 'cm1', title: 'Rent', amountCents: 1000, dueDate: '2026-11-30' },
        ],
      };

      const invalidCases: Array<{ label: string; patch: Record<string, unknown> }> = [
        {
          label: 'duplicate milestone id',
          patch: {
            milestones: [
              { id: 'm1', projectId: 'p1', title: 'A' },
              { id: 'm1', projectId: 'p1', title: 'B' },
            ],
          },
        },
        {
          label: 'dangling Tier-1 milestone.projectId',
          patch: {
            milestones: [{ id: 'm1', projectId: 'missing-proj', title: 'Orphan MS' }],
          },
        },
        {
          label: 'dangling Tier-1 budget.categoryId',
          patch: {
            budgets: [{ id: 'b1', categoryId: 'missing-cat', monthIso: '2026-11', limitCents: 1000 }],
          },
        },
        {
          label: 'duplicate budget composite (monthIso, categoryId)',
          patch: {
            budgets: [
              { id: 'b1', categoryId: 'c1', monthIso: '2026-11', limitCents: 1000 },
              { id: 'b2', categoryId: 'c1', monthIso: '2026-11', limitCents: 2000 },
            ],
          },
        },
        {
          label: 'duplicate journalEntries.legacySourceTxId',
          patch: {
            journalEntries: [
              { id: 'je1', entryType: 'standard', occurrenceDate: '2026-11-10', legacySourceTxId: 'tx-dup' },
              { id: 'je2', entryType: 'standard', occurrenceDate: '2026-11-11', legacySourceTxId: 'tx-dup' },
            ],
          },
        },
        {
          label: 'dangling Tier-1 posting.entryId',
          patch: {
            postings: [
              { id: 'po1', entryId: 'missing-je', accountId: 'a1', amountCents: 100, direction: 'debit', accountMovementDate: '2026-11-10' },
            ],
          },
        },
        {
          label: 'dangling Tier-1 posting.accountId',
          patch: {
            postings: [
              { id: 'po1', entryId: 'je1', accountId: 'missing-acc', amountCents: 100, direction: 'debit', accountMovementDate: '2026-11-10' },
            ],
          },
        },
        {
          label: 'unbalanced postings on journal entry',
          patch: {
            postings: [
              { id: 'po1', entryId: 'je1', accountId: 'a1', amountCents: 500, direction: 'debit', accountMovementDate: '2026-11-10' },
              { id: 'po2', entryId: 'je1', accountId: 'acc-sys-income', amountCents: 400, direction: 'credit', accountMovementDate: '2026-11-10' },
            ],
          },
        },
        {
          label: 'dangling Tier-1 debt.originEntryId',
          patch: {
            debts: [{ id: 'd1', originEntryId: 'missing-je', partyId: 'pa1', principalCents: 100 }],
          },
        },
        {
          label: 'dangling Tier-1 debt.partyId',
          patch: {
            debts: [{ id: 'd1', originEntryId: 'je1', partyId: 'missing-party', principalCents: 100 }],
          },
        },
        {
          label: 'dangling Tier-1 settlementAllocation.settlementEntryId',
          patch: {
            settlementAllocations: [
              { id: 'sa1', settlementEntryId: 'missing-je', debtId: 'd1', allocatedCents: 100, settlementDate: '2026-11-12' },
            ],
          },
        },
        {
          label: 'dangling Tier-1 settlementAllocation.debtId',
          patch: {
            settlementAllocations: [
              { id: 'sa1', settlementEntryId: 'je2', debtId: 'missing-debt', allocatedCents: 100, settlementDate: '2026-11-12' },
            ],
          },
        },
        {
          label: 'dangling Tier-1 commitmentSettlement.commitmentId',
          patch: {
            commitmentSettlements: [
              { id: 'cs1', commitmentId: 'missing-com', entryId: 'je2', amountCents: 100, settledDate: '2026-11-12' },
            ],
          },
        },
        {
          label: 'dangling Tier-1 commitmentSettlement.entryId',
          patch: {
            commitmentSettlements: [
              { id: 'cs1', commitmentId: 'cm1', entryId: 'missing-je', amountCents: 100, settledDate: '2026-11-12' },
            ],
          },
        },
        {
          label: 'dangling Tier-1 transaction.categoryId',
          patch: {
            transactions: [
              { id: 't1', amountCents: 100, type: 'expense', categoryId: 'nonexistent-cat', accountId: 'a1', transactionDate: '2026-11-10' },
            ],
          },
        },
        {
          label: 'malformed task.subtasks (non-array)',
          patch: { tasks: [{ id: 't1', title: 'Bad subtasks', subtasks: 'not-array' }] },
        },
        {
          label: 'malformed notes.tags (non-string item)',
          patch: { notes: [{ id: 'n1', title: 'Bad tags', tags: [123] }] },
        },
        {
          label: 'calendar event endDate before start date',
          patch: {
            calendarEvents: [{ id: 'e1', title: 'Bad range', date: '2026-11-20', endDate: '2026-11-18' }],
          },
        },
        {
          label: 'invalid top-level isFinanceSetupCompleted scalar',
          patch: { isFinanceSetupCompleted: 'yes' },
        },
        {
          label: 'invalid top-level openingBalanceCents non-integer',
          patch: { openingBalanceCents: 12.5 },
        },
      ];

      for (const tc of invalidCases) {
        const res = SharedStateBridge.importFromAndroidJson(
          JSON.stringify({ ...basePayload, ...tc.patch })
        );
        assert.strictEqual(res.success, false, `${tc.label} must fail closed`);
        assert.strictEqual(res.errorKind, 'invalid_payload', tc.label);
        assert.strictEqual(store.size, baselineStoreSnapshot.size, `${tc.label} changed key count`);
        for (const [k, v] of baselineStoreSnapshot.entries()) {
          assert.strictEqual(store.get(k), v, `${tc.label} mutated key ${k}`);
        }
      }
    });
  });

  it('10. Legacy v4-v8 Android snapshots, schema aliases, and Web legacy v3 rejection behave per contract', () => {
    withMockBrowserStorage(() => {
      // Legacy v4 with savings-shaped goal inside goals[], legacy account.isActive: false, omitted reminders/appSettings
      const v4Res = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          schemaVersion: 4,
          accounts: [
            { id: 'acc-legacy', name: 'Old Bank', type: 'asset', openingBalanceCents: 3000, isActive: false },
          ],
          categories: [{ id: 'cat-v4', name: 'Food', type: 'expense' }],
          transactions: [
            { id: 'tx-v4', amountCents: 200, type: 'expense', accountId: 'acc-legacy', transactionDate: '2026-11-10' },
          ],
          goals: [
            { id: 'goal-real', title: 'Health', status: 'active' },
            { id: 'sav-from-goal', title: 'Emergency Jar', targetCents: 50000, currentAllocatedCents: 10000 },
          ],
          journalEntries: [
            { id: 'je-open', entryType: 'opening', occurrenceDate: '2026-11-01' },
            { id: 'je-adj', entryType: 'adjustment', occurrenceDate: '2026-11-02' },
          ],
          parties: [{ id: 'pa-v4', name: 'Friend' }],
          debts: [
            { id: 'd-v4', originEntryId: 'je-open', partyId: 'pa-v4', principalCents: 1000, status: 'writtenOff' },
          ],
          calendarEvents: [
            { id: 'evt-v4', title: 'Clinic', dateIso: '2026-11-22', endDateIso: '2026-11-23' },
          ],
          inboxItems: [
            { id: 'inb-v4', text: 'Call mom', createdAtUtc: '2026-11-10T08:00:00.000Z' },
          ],
        })
      );
      assert.strictEqual(v4Res.success, true, v4Res.error);
      const exported = JSON.parse(SharedStateBridge.exportToAndroidJson());
      assert.strictEqual(exported.schemaVersion, 5);
      assert.strictEqual(exported.accounts[0].isArchived, true);
      assert.strictEqual(Object.prototype.hasOwnProperty.call(exported.accounts[0], 'isActive'), false);
      assert.strictEqual(exported.transactions[0].categoryId, 'cat-other-exp');
      assert.deepStrictEqual(exported.goals.map((g: any) => g.id), ['goal-real']);
      assert.deepStrictEqual(exported.savingsGoals.map((s: any) => s.id), ['sav-from-goal']);
      assert.deepStrictEqual(
        exported.journalEntries.map((j: any) => j.entryType),
        ['adjustment', 'adjustment']
      );
      assert.strictEqual(exported.debts[0].status, 'written_off');
      assert.strictEqual(exported.calendarEvents[0].date, '2026-11-22');
      assert.strictEqual(exported.calendarEvents[0].endDate, '2026-11-23');
      assert.strictEqual(exported.inboxItems[0].rawText, 'Call mom');
      assert.strictEqual(exported.reminders, undefined);
      assert.strictEqual(exported.appSettings, undefined);

      // Omitted schemaVersion defaults cleanly to canonical exchange 5
      const omittedVerRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          accounts: [],
          transactions: [],
        })
      );
      assert.strictEqual(omittedVerRes.success, true, omittedVerRes.error);
      assert.strictEqual(omittedVerRes.state?.schemaVersion, 5);

      // Web legacy LocalDatabaseState v3 is cleanly rejected by SharedStateBridge
      const v3Res = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          version: 3,
          accounts: [],
          transactions: [],
        })
      );
      assert.strictEqual(v3Res.success, false);
      assert.strictEqual(v3Res.errorKind, 'invalid_snapshot_version');
    });
  });

  it('7. Finance Stage A preserves valid non-ETB & unverified legacy accounts across all snapshots while rejecting malformed currencies pre-mutation', () => {
    withMockBrowserStorage((store) => {
      const seedRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          ...CANONICAL_SEED_DATABASE,
          accounts: [],
          transactions: [],
        })
      );
      assert.strictEqual(seedRes.success, true, seedRes.error);
      const baselineSnapshot = new Map(store);

      const invalidAccountPayloads: Array<{ label: string; payload: Record<string, unknown> }> = [
        {
          label: 'unrecognized XYZ currency code',
          payload: {
            schemaVersion: 7,
            accounts: [{ id: 'acc-xyz', name: 'Unknown', type: 'asset', currencyCode: 'XYZ' }],
            transactions: [],
          },
        },
        {
          label: 'numeric/invalid BAD123 currency code',
          payload: {
            schemaVersion: 8,
            accounts: [{ id: 'acc-bad123', name: 'Malformed', type: 'asset', currencyCode: 'BAD123' }],
            transactions: [],
          },
        },
        {
          label: 'non-string currencyCode',
          payload: {
            schemaVersion: 7,
            accounts: [{ id: 'acc-num', name: 'Numeric', type: 'asset', currencyCode: 840 }],
            transactions: [],
          },
        },
        {
          label: 'system account with non-ETB currency',
          payload: {
            schemaVersion: 7,
            accounts: [
              {
                id: SYSTEM_CONTROL_ACCOUNT_IDS.equity,
                name: 'System Equity',
                type: 'equity',
                isSystem: true,
                currencyCode: 'USD',
              },
            ],
            transactions: [],
          },
        },
      ];

      for (const tc of invalidAccountPayloads) {
        const res = SharedStateBridge.importFromAndroidJson(JSON.stringify(tc.payload));
        assert.strictEqual(res.success, false, `Expected failure for ${tc.label}`);
        assert.strictEqual(res.errorKind, 'invalid_payload', tc.label);
        assert.match(res.error ?? '', /ETB|currency/i, tc.label);
        assert.deepStrictEqual(
          Array.from(store.entries()),
          Array.from(baselineSnapshot.entries()),
          `Store mutated after failed ${tc.label}`
        );
      }

      // Valid non-ETB ISO codes, empty/whitespace currencyCode, omitted currencyCode,
      // and lowercase 'etb' are normalized/preserved cleanly across v5 and v7+ snapshots.
      const preservedRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          schemaVersion: 7,
          accounts: [
            { id: 'acc-etb-lower', name: 'Birr Cash', type: 'asset', currencyCode: ' etb ' },
            { id: 'acc-usd', name: 'USD Wallet', type: 'asset', currencyCode: ' usd ' },
            { id: 'acc-eur', name: 'Euro Bank', type: 'asset', currencyCode: 'EUR' },
            { id: 'acc-blank', name: 'Blank', type: 'asset', currencyCode: '   ' },
            { id: 'acc-omitted', name: 'Legacy Cash', type: 'asset' },
          ],
          transactions: [],
        })
      );
      assert.strictEqual(preservedRes.success, true, preservedRes.error);
      assert.deepStrictEqual(
        preservedRes.state?.accounts.map((a) => [a.id, a.currencyCode]),
        [
          ['acc-etb-lower', 'ETB'],
          ['acc-usd', 'USD'],
          ['acc-eur', 'EUR'],
          ['acc-blank', ''],
          ['acc-omitted', ''],
        ]
      );
    });
  });
});

