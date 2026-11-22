import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  CANONICAL_SEED_DATABASE,
  KNOWN_SEED_IDS,
  SharedDailyPlanningEntry,
  SharedTask,
  SharedTaskRecurrenceConfig,
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

describe('STAGE 0.2C: CROSS-PLATFORM TASK PERSISTENCE, BACKUP & RESTORE (WEB)', () => {
  it('1. Web Task serialization & SharedStateBridge preserve all 6 v10 fields and normalize legacy subtasks/completedAt safely', () => {
    withMockBrowserStorage((store) => {
      // Simulate existing Web localStorage tasks mixing rich v10 fields, legacy subtasks without IDs,
      // and legacy non-ISO completedAt strings (e.g. "08:50" from earlier DaywellTasksModule sample).
      store.set(
        'daywell_tasks',
        JSON.stringify([
          {
            id: 'task-v10-rich',
            title: 'Monthly Ledger Review',
            description: 'Verify ETB accounts & archive old notes',
            status: 'completed',
            completed: true,
            priority: 'high',
            completedAt: '2026-11-20T14:35:00.000Z',
            dueDate: '2026-11-20',
            scheduledDate: '2026-11-20',
            scheduledTime: '09:30',
            estimatedDurationMinutes: 45,
            projectId: 'proj-ops',
            milestoneId: 'ms-q4',
            subtasks: [
              { id: 'sub-keep-1', title: 'Export CSV', completed: true },
              { title: 'Check balance sheet', completed: false },
            ],
            labels: ['finance', 'monthly'],
            isPinned: true,
            isMyDay: true,
            myDayDate: '2026-11-20',
            recurrenceRule: 'monthly',
            recurrenceConfig: {
              frequency: 'monthly',
              interval: 1,
              startDate: '2026-11-20',
              endDate: '2027-11-20',
              repeatFrom: 'due_date',
            },
            isArchived: true,
            sortOrder: 4,
            createdAt: '2026-11-01T08:00:00.000Z',
            updatedAt: '2026-11-20T14:35:00.000Z',
          },
          {
            id: 'task-legacy-time',
            title: 'Morning Walk',
            completed: true,
            completedAt: '08:50',
            priority: 'low',
            subtasks: [{ title: 'Stretch', completed: true }],
            createdAt: '2026-11-18T05:00:00.000Z',
            updatedAt: '2026-11-18T05:50:00.000Z',
          },
        ])
      );

      const assembled = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(assembled.tasks.length, 2);

      const rich = assembled.tasks[0];
      assert.strictEqual(rich.completedAt, '2026-11-20T14:35:00.000Z');
      assert.strictEqual(rich.scheduledTime, '09:30');
      assert.strictEqual(rich.myDayDate, '2026-11-20');
      assert.deepStrictEqual(rich.recurrenceConfig, {
        frequency: 'monthly',
        interval: 1,
        startDate: '2026-11-20',
        endDate: '2027-11-20',
        repeatFrom: 'due_date',
      });
      assert.strictEqual(rich.isArchived, true);
      assert.strictEqual(rich.sortOrder, 4);
      assert.deepStrictEqual(rich.subtasks, [
        { id: 'sub-keep-1', title: 'Export CSV', done: true },
        { id: 'task-v10-rich-sub-2', title: 'Check balance sheet', done: false },
      ]);

      // Legacy non-ISO completedAt ("08:50") is safely ignored rather than failing or corrupting state
      const legacy = assembled.tasks[1];
      assert.strictEqual(legacy.status, 'completed');
      assert.strictEqual(legacy.completedAt, undefined);
      assert.strictEqual(legacy.isArchived, false);
      assert.strictEqual(legacy.sortOrder, 0);
      assert.deepStrictEqual(legacy.subtasks, [
        { id: 'task-legacy-time-sub-1', title: 'Stretch', done: true },
      ]);
    });
  });

  it('2. DailyPlanningEntries survive export/restore, enforce FKs & composite uniqueness fail-closed, and clean up on task deletion or seed purge', () => {
    withMockBrowserStorage((store) => {
      const task1: SharedTask = {
        id: 'task-dp-1',
        title: 'Prepare Proposal',
        status: 'in_progress',
        priority: 'high',
        isMyDay: true,
        myDayDate: '2026-11-21',
        scheduledTime: '14:15',
        isArchived: false,
        sortOrder: 1,
        createdAt: '2026-11-21T06:00:00.000Z',
        updatedAt: '2026-11-21T06:30:00.000Z',
      };
      const task2: SharedTask = {
        id: 'task-dp-2',
        title: 'Call Contractor',
        status: 'not_started',
        priority: 'medium',
        isArchived: false,
        sortOrder: 2,
        createdAt: '2026-11-21T07:00:00.000Z',
        updatedAt: '2026-11-21T07:00:00.000Z',
      };
      const entries: SharedDailyPlanningEntry[] = [
        {
          id: 'dpe-1',
          planDate: '2026-11-21',
          taskId: 'task-dp-1',
          action: 'planned',
          createdAt: '2026-11-21T06:05:00.000Z',
          updatedAt: '2026-11-21T06:10:00.000Z',
        },
        {
          id: 'dpe-2',
          planDate: '2026-11-20',
          taskId: 'task-dp-1',
          action: 'carried_forward',
          createdAt: '2026-11-20T06:00:00.000Z',
        },
        {
          id: 'dpe-3',
          planDate: '2026-11-21',
          taskId: 'task-dp-2',
          action: 'dismissed',
          createdAt: '2026-11-21T07:05:00.000Z',
          updatedAt: '2026-11-21T07:15:00.000Z',
        },
      ];

      const validPayload = {
        ...CANONICAL_SEED_DATABASE,
        schemaVersion: 5,
        snapshotFormatVersion: 2,
        databaseSchemaVersion: 10,
        tasks: [task1, task2],
        dailyPlanningEntries: entries,
      };
      const importRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify(validPayload)
      );
      assert.strictEqual(importRes.success, true, importRes.error);
      assert.strictEqual(importRes.state?.dailyPlanningEntries?.length, 3);

      const exported = JSON.parse(SharedStateBridge.exportToAndroidJson());
      assert.deepStrictEqual(exported.dailyPlanningEntries, entries);

      // Fail-closed validation checks without mutating existing storage
      const baselineEntries = store.get('daywell_daily_planning_entries');
      const danglingFkRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          ...validPayload,
          dailyPlanningEntries: [
            {
              id: 'dpe-orphan',
              planDate: '2026-11-21',
              taskId: 'missing-task-id',
              action: 'planned',
              createdAt: '2026-11-21T08:00:00.000Z',
            },
          ],
        })
      );
      assert.strictEqual(danglingFkRes.success, false);
      assert.strictEqual(danglingFkRes.errorKind, 'invalid_payload');
      assert.strictEqual(
        store.get('daywell_daily_planning_entries'),
        baselineEntries
      );

      const dupCompositeRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          ...validPayload,
          dailyPlanningEntries: [
            entries[0],
            {
              id: 'dpe-dup-composite',
              planDate: '2026-11-21',
              taskId: 'task-dp-1',
              action: 'completed',
              createdAt: '2026-11-21T09:00:00.000Z',
            },
          ],
        })
      );
      assert.strictEqual(dupCompositeRes.success, false);
      assert.strictEqual(dupCompositeRes.errorKind, 'invalid_payload');
      assert.strictEqual(
        store.get('daywell_daily_planning_entries'),
        baselineEntries
      );

      // Task cascade cleanup helper
      SharedStateBridge.removeDailyPlanningForTask('task-dp-1');
      const afterRemove = SharedStateBridge.assembleLiveDatabaseState();
      assert.deepStrictEqual(
        afterRemove.dailyPlanningEntries?.map((e) => e.id),
        ['dpe-3']
      );

      // Seed purge cleans planning entries targeting KNOWN_SEED_IDS.tasks while leaving user entries intact
      const seedTaskId = KNOWN_SEED_IDS.tasks[0];
      store.set(
        'daywell_tasks',
        JSON.stringify([
          { id: seedTaskId, title: 'Seed', status: 'not_started', priority: 'low' },
          { ...task2, completed: false },
        ])
      );
      store.set(
        'daywell_daily_planning_entries',
        JSON.stringify([
          {
            id: 'dpe-seed',
            planDate: '2026-11-21',
            taskId: seedTaskId,
            action: 'planned',
            createdAt: '2026-11-21T07:00:00.000Z',
          },
          entries[2],
        ])
      );
      SharedStateBridge.purgeKnownSeedData();
      const postPurgeEntries = JSON.parse(
        store.get('daywell_daily_planning_entries')!
      );
      assert.deepStrictEqual(
        postPurgeEntries.map((e: SharedDailyPlanningEntry) => e.id),
        ['dpe-3']
      );
    });
  });

  it('3. Full v10 backup export declares schemaVersion 5, snapshotFormatVersion 2, databaseSchemaVersion 10 and round-trips losslessly', () => {
    withMockBrowserStorage((store) => {
      const recurrenceConfig: SharedTaskRecurrenceConfig = {
        frequency: 'weekly',
        interval: 2,
        weekdays: [1, 3, 5],
        startDate: '2026-11-01',
        endDate: '2027-02-01',
        repeatFrom: 'completion_date',
      };

      const v10Payload = {
        ...CANONICAL_SEED_DATABASE,
        schemaVersion: 5,
        snapshotFormatVersion: 2,
        databaseSchemaVersion: 10,
        projects: [
          {
            id: 'proj-v10',
            title: 'Bridge Engineering',
            status: 'active',
            createdAt: '2026-11-01T08:00:00.000Z',
            updatedAt: '2026-11-01T08:00:00.000Z',
          },
        ],
        tasks: [
          {
            id: 'task-roundtrip',
            title: 'Weekly Team Sync',
            description: 'Review milestones and blockers',
            status: 'completed',
            priority: 'urgent',
            completedAt: '2026-11-21T11:22:33.000Z',
            dueDate: '2026-11-22',
            scheduledDate: '2026-11-21',
            scheduledTime: '16:45',
            estimatedDurationMinutes: 60,
            projectId: 'proj-v10',
            subtasks: [
              { id: 'rt-sub-1', title: 'Draft agenda', done: true },
              { id: 'rt-sub-2', title: 'Send summary', done: false },
            ],
            labels: ['team'],
            isPinned: false,
            isMyDay: true,
            myDayDate: '2026-11-21',
            recurrenceRule: 'weekly',
            recurrenceConfig,
            isArchived: false,
            sortOrder: 7,
            createdAt: '2026-11-01T08:00:00.000Z',
            updatedAt: '2026-11-21T11:22:33.000Z',
          },
        ],
        dailyPlanningEntries: [
          {
            id: 'dpe-rt-1',
            planDate: '2026-11-21',
            taskId: 'task-roundtrip',
            action: 'completed',
            createdAt: '2026-11-21T07:00:00.000Z',
            updatedAt: '2026-11-21T11:22:33.000Z',
          },
        ],
      };

      const importRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify(v10Payload)
      );
      assert.strictEqual(importRes.success, true, importRes.error);

      const exportedRaw = SharedStateBridge.exportToAndroidJson();
      const exported = JSON.parse(exportedRaw);
      assert.strictEqual(exported.schemaVersion, 5);
      assert.strictEqual(exported.snapshotFormatVersion, 2);
      assert.strictEqual(exported.databaseSchemaVersion, 10);
      assert.strictEqual(exported.financeSchemaVersion, 7);

      // Re-import into a completely cleared store
      store.clear();
      const reimportRes = SharedStateBridge.importFromAndroidJson(exportedRaw);
      assert.strictEqual(reimportRes.success, true, reimportRes.error);
      assert.strictEqual(reimportRes.state?.tasks[0].completedAt, '2026-11-21T11:22:33.000Z');
      assert.strictEqual(reimportRes.state?.tasks[0].scheduledTime, '16:45');
      assert.strictEqual(reimportRes.state?.tasks[0].myDayDate, '2026-11-21');
      assert.deepStrictEqual(reimportRes.state?.tasks[0].recurrenceConfig, recurrenceConfig);
      assert.strictEqual(reimportRes.state?.tasks[0].isArchived, false);
      assert.strictEqual(reimportRes.state?.tasks[0].sortOrder, 7);
      assert.deepStrictEqual(reimportRes.state?.dailyPlanningEntries, v10Payload.dailyPlanningEntries);
    });
  });

  it('4 & 5. Older v4-v9 backups (format-1 & format-2 v9) remain restorable with safe defaults for missing v10 fields & legacy subtasks', () => {
    withMockBrowserStorage(() => {
      const legacyVersions = [
        { schemaVersion: 4, snapshotFormatVersion: undefined, databaseSchemaVersion: undefined },
        { schemaVersion: 5, snapshotFormatVersion: 1, databaseSchemaVersion: 5 },
        { schemaVersion: 6, snapshotFormatVersion: 1, databaseSchemaVersion: 6 },
        { schemaVersion: 7, snapshotFormatVersion: 1, databaseSchemaVersion: 7 },
        { schemaVersion: 8, snapshotFormatVersion: 1, databaseSchemaVersion: 8 },
        { schemaVersion: 9, snapshotFormatVersion: 1, databaseSchemaVersion: 9 },
        { schemaVersion: 5, snapshotFormatVersion: 2, databaseSchemaVersion: 9 },
      ];

      for (const ver of legacyVersions) {
        const legacySnap: Record<string, unknown> = {
          schemaVersion: ver.schemaVersion,
          ...(ver.snapshotFormatVersion !== undefined
            ? { snapshotFormatVersion: ver.snapshotFormatVersion }
            : {}),
          ...(ver.databaseSchemaVersion !== undefined
            ? { databaseSchemaVersion: ver.databaseSchemaVersion }
            : {}),
          accounts: [],
          transactions: [],
          projects: [{ id: 'proj-old', title: 'Legacy Project', status: 'active' }],
          tasks: [
            {
              id: 'task-old-1',
              title: 'Legacy Task',
              status: 'not_started',
              priority: 'medium',
              projectId: 'proj-old',
              subtasks: [
                { title: 'Step A', completed: true },
                { id: 'sub-existing', title: 'Step B', done: false },
              ],
              createdAt: '2025-10-01T08:00:00.000Z',
              updatedAt: '2025-10-01T08:00:00.000Z',
            },
          ],
        };

        const res = SharedStateBridge.importFromAndroidJson(JSON.stringify(legacySnap));
        assert.strictEqual(
          res.success,
          true,
          `Legacy version ${JSON.stringify(ver)} failed: ${res.error}`
        );
        const restoredTask = res.state?.tasks[0];
        assert.strictEqual(restoredTask?.id, 'task-old-1');
        assert.strictEqual(restoredTask?.projectId, 'proj-old');
        assert.strictEqual(restoredTask?.isArchived, false);
        assert.strictEqual(restoredTask?.sortOrder, 0);
        assert.strictEqual(restoredTask?.completedAt, undefined);
        assert.strictEqual(restoredTask?.scheduledTime, undefined);
        assert.strictEqual(restoredTask?.myDayDate, undefined);
        assert.strictEqual(restoredTask?.recurrenceConfig, undefined);
        assert.deepStrictEqual(restoredTask?.subtasks, [
          { id: 'task-old-1-sub-1', title: 'Step A', done: true },
          { id: 'sub-existing', title: 'Step B', done: false },
        ]);
        assert.deepStrictEqual(res.state?.dailyPlanningEntries, []);

        // Subsequent export upgrades cleanly to v10
        const upgraded = JSON.parse(SharedStateBridge.exportToAndroidJson());
        assert.strictEqual(upgraded.databaseSchemaVersion, 10);
      }
    });
  });

  it('6. Finance-only export excludes dailyPlanningEntries/tasks and Finance-only import rejects them while preserving stored Task & DailyPlanning state', () => {
    withMockBrowserStorage((store) => {
      const fullPayload = {
        ...CANONICAL_SEED_DATABASE,
        schemaVersion: 5,
        snapshotFormatVersion: 2,
        databaseSchemaVersion: 10,
        accounts: [
          {
            id: 'acc-etb-cash',
            name: 'Wallet Cash',
            type: 'asset',
            subType: 'cash',
            currencyCode: 'ETB',
            balanceCents: 15000,
          },
        ],
        tasks: [
          {
            id: 'task-keep',
            title: 'Keep My Day Task',
            status: 'not_started',
            priority: 'medium',
            myDayDate: '2026-11-21',
            scheduledTime: '10:00',
            isArchived: false,
            sortOrder: 3,
            createdAt: '2026-11-21T06:00:00.000Z',
            updatedAt: '2026-11-21T06:00:00.000Z',
          },
        ],
        dailyPlanningEntries: [
          {
            id: 'dpe-keep',
            planDate: '2026-11-21',
            taskId: 'task-keep',
            action: 'planned',
            createdAt: '2026-11-21T06:00:00.000Z',
          },
        ],
      };

      const seedRes = SharedStateBridge.importFromAndroidJson(JSON.stringify(fullPayload));
      assert.strictEqual(seedRes.success, true, seedRes.error);

      const financeExportStr = SharedStateBridge.exportFinanceOnlyJson();
      const financeExport = JSON.parse(financeExportStr);
      assert.strictEqual(financeExport.financeOnly, true);
      assert.strictEqual(financeExport.databaseSchemaVersion, 10);
      assert.strictEqual('tasks' in financeExport, false);
      assert.strictEqual('dailyPlanningEntries' in financeExport, false);

      // Finance-only import must reject payloads containing dailyPlanningEntries
      const contaminated = {
        ...financeExport,
        dailyPlanningEntries: fullPayload.dailyPlanningEntries,
      };
      const badRes = SharedStateBridge.importFinanceOnlyJson(JSON.stringify(contaminated));
      assert.strictEqual(badRes.success, false);
      assert.strictEqual(badRes.errorKind, 'invalid_payload');

      // Valid Finance-only import preserves existing Tasks and DailyPlanningEntries untouched
      const updatedFin = {
        ...financeExport,
        accounts: [
          {
            ...financeExport.accounts[0],
            name: 'Updated Cash',
          },
        ],
      };
      const finImportRes = SharedStateBridge.importFinanceOnlyJson(
        JSON.stringify(updatedFin)
      );
      assert.strictEqual(finImportRes.success, true, finImportRes.error);
      assert.strictEqual(finImportRes.state?.accounts[0].name, 'Updated Cash');

      const assembled = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(assembled.tasks.length, 1);
      assert.strictEqual(assembled.tasks[0].scheduledTime, '10:00');
      assert.strictEqual(assembled.dailyPlanningEntries?.length, 1);
      assert.strictEqual(assembled.dailyPlanningEntries?.[0].id, 'dpe-keep');
      assert.ok(store.get('daywell_daily_planning_entries')?.includes('dpe-keep'));
    });
  });

  it('7 & 8. Future versions fail closed without mutating storage, and existing Tasks/relationships/modules remain intact', () => {
    withMockBrowserStorage((store) => {
      const initialPayload = {
        ...CANONICAL_SEED_DATABASE,
        schemaVersion: 5,
        snapshotFormatVersion: 2,
        databaseSchemaVersion: 10,
        goals: [
          {
            id: 'goal-1',
            title: 'Launch Studio',
            status: 'active',
            createdAt: '2026-11-01T08:00:00.000Z',
          },
        ],
        projects: [
          {
            id: 'proj-1',
            title: 'Site Build',
            status: 'active',
            goalId: 'goal-1',
            createdAt: '2026-11-01T08:00:00.000Z',
            updatedAt: '2026-11-01T08:00:00.000Z',
          },
        ],
        milestones: [
          {
            id: 'ms-1',
            projectId: 'proj-1',
            title: 'M1',
            isCompleted: false,
            createdAt: '2026-11-01T08:00:00.000Z',
          },
        ],
        tasks: [
          {
            id: 'task-rel',
            title: 'Keep Relations',
            status: 'in_progress',
            priority: 'high',
            projectId: 'proj-1',
            milestoneId: 'ms-1',
            scheduledTime: '11:30',
            myDayDate: '2026-11-21',
            isArchived: false,
            sortOrder: 5,
            createdAt: '2026-11-01T08:00:00.000Z',
            updatedAt: '2026-11-21T08:00:00.000Z',
          },
        ],
        dailyPlanningEntries: [
          {
            id: 'dpe-rel',
            planDate: '2026-11-21',
            taskId: 'task-rel',
            action: 'planned',
            createdAt: '2026-11-21T08:00:00.000Z',
          },
        ],
        notes: [
          {
            id: 'note-1',
            title: 'Spec Note',
            body: 'Preserved',
            projectId: 'proj-1',
            createdAt: '2026-11-01T08:00:00.000Z',
            updatedAt: '2026-11-01T08:00:00.000Z',
          },
        ],
        calendarEvents: [
          {
            id: 'evt-1',
            title: 'Standup',
            date: '2026-11-21',
            createdAt: '2026-11-01T08:00:00.000Z',
          },
        ],
        inboxItems: [
          {
            id: 'inb-1',
            text: 'Follow up',
            isTriaged: false,
            createdAt: '2026-11-01T08:00:00.000Z',
          },
        ],
      };

      const seedRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify(initialPayload)
      );
      assert.strictEqual(seedRes.success, true, seedRes.error);
      const snapshotBefore = new Map(store);

      const futureVersions = [
        { schemaVersion: 10 },
        { snapshotFormatVersion: 3 },
        { snapshotFormatVersion: 2, databaseSchemaVersion: 11 },
        { snapshotFormatVersion: 1, databaseSchemaVersion: 11 },
      ];
      for (const fv of futureVersions) {
        const res = SharedStateBridge.importFromAndroidJson(
          JSON.stringify({
            ...initialPayload,
            ...fv,
          })
        );
        assert.strictEqual(res.success, false);
        assert.strictEqual(res.errorKind, 'unsupported_future_schema');
        assert.deepStrictEqual([...store.entries()], [...snapshotBefore.entries()]);
      }

      // Verify existing task relationships and sibling modules are completely intact
      const finalState = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(finalState.tasks[0].projectId, 'proj-1');
      assert.strictEqual(finalState.tasks[0].milestoneId, 'ms-1');
      assert.strictEqual(finalState.tasks[0].scheduledTime, '11:30');
      assert.strictEqual(finalState.dailyPlanningEntries?.[0].taskId, 'task-rel');
      assert.strictEqual(finalState.notes[0].id, 'note-1');
      assert.strictEqual(finalState.calendarEvents?.[0].id, 'evt-1');
      assert.strictEqual(finalState.inboxItems?.[0].id, 'inb-1');
    });
  });
});
