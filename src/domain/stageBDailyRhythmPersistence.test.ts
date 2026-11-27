import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  CANONICAL_SEED_DATABASE,
  SharedDailyRhythmDay,
} from './sharedFoundation';
import {
  DailyRhythmDayRecord,
  evaluateDailyRhythmTimeline,
} from './dailyRhythm';
import { dailyRhythmService } from '../services/dailyRhythmService';
import { SharedStateBridge } from '../services/sharedStateBridge';

const REPO_ROOT = process.cwd();

function readRepoFile(relPath: string): string {
  return fs.readFileSync(path.join(REPO_ROOT, relPath), 'utf8');
}

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

function buildQualifyingDay(
  dateIso: string,
  financeCloseStatus: 'closed_with_transactions' | 'closed_no_transactions' = 'closed_with_transactions'
): DailyRhythmDayRecord {
  return {
    dateIso,
    bibleStudyDone: true,
    bibleStudyCompletedAt: `${dateIso}T06:00:00.000Z`,
    prayerDone: true,
    prayerCompletedAt: `${dateIso}T06:20:00.000Z`,
    taskReviewConfirmed: true,
    taskReviewedAt: `${dateIso}T18:30:00.000Z`,
    taskReviewEvidence: {
      overdueCount: 0,
      todayCount: 3,
      plannedCount: 3,
      completedTodayCount: 2,
    },
    financeCloseStatus,
    financeClosedAt: `${dateIso}T19:00:00.000Z`,
    updatedAt: `${dateIso}T19:00:00.000Z`,
  };
}

describe('STAGE B: DAILY RHYTHM PERSISTENCE & BACKUP/RESTORE (WEB & CROSS-PLATFORM)', () => {
  it('1. Web dailyRhythmService enforces one record per dateIso, survives restart, and handles corrupt/missing localStorage safely', () => {
    withMockBrowserStorage((store) => {
      // Missing storage yields empty array with zero fabricated check-ins
      assert.deepStrictEqual(dailyRhythmService.loadDays(), []);
      assert.strictEqual(dailyRhythmService.getDay('2026-11-22'), null);

      // Corrupt or non-array Daily Rhythm storage degrades cleanly without touching sibling keys
      store.set('daywell_tasks', JSON.stringify([{ id: 'task-keep', title: 'Stay safe' }]));
      store.set(SharedStateBridge.DAILY_RHYTHM_STORAGE_KEY, '{corrupt json');
      assert.deepStrictEqual(dailyRhythmService.loadDays(), []);
      store.set(SharedStateBridge.DAILY_RHYTHM_STORAGE_KEY, JSON.stringify({ not: 'an-array' }));
      assert.deepStrictEqual(dailyRhythmService.loadDays(), []);
      assert.ok(store.get('daywell_tasks')?.includes('task-keep'));

      // Upsert out-of-order dates and overwrite same dateIso without duplicates
      const day22Initial: DailyRhythmDayRecord = {
        dateIso: '2026-11-22',
        bibleStudyDone: true,
        bibleStudyCompletedAt: '2026-11-22T06:00:00.000Z',
        prayerDone: false,
        taskReviewConfirmed: false,
        financeCloseStatus: 'open',
        updatedAt: '2026-11-22T06:00:00.000Z',
      };
      const day20 = buildQualifyingDay('2026-11-20', 'closed_no_transactions');
      dailyRhythmService.upsertDay(day22Initial);
      dailyRhythmService.upsertDay(day20);

      const day22Updated = buildQualifyingDay('2026-11-22', 'closed_with_transactions');
      dailyRhythmService.upsertDay(day22Updated);

      // Verify ascending sort, single record per dateIso, and shared bridge persistence
      const listed = dailyRhythmService.listDays();
      assert.strictEqual(listed.length, 2);
      assert.deepStrictEqual(
        listed.map((d) => d.dateIso),
        ['2026-11-20', '2026-11-22']
      );
      assert.strictEqual(dailyRhythmService.getDay('2026-11-22')?.prayerDone, true);
      assert.strictEqual(
        dailyRhythmService.listDays({ fromDateIso: '2026-11-21', toDateIso: '2026-11-22' }).length,
        1
      );

      // Simulate restart via SharedStateBridge.assembleLiveDatabaseState()
      const liveState = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(liveState.dailyRhythmDays?.length, 2);
      assert.deepStrictEqual(liveState.dailyRhythmDays?.[1], day22Updated);

      // Delete works idempotently and invalid dates fail safely
      assert.strictEqual(dailyRhythmService.deleteDay('2026-11-20'), true);
      assert.strictEqual(dailyRhythmService.deleteDay('2026-11-20'), false);
      assert.strictEqual(dailyRhythmService.loadDays().length, 1);
      assert.throws(() =>
        dailyRhythmService.upsertDay({
          ...day20,
          dateIso: '2026-02-30',
        })
      );
    });
  });

  it('2. Full v12 backup export/restore preserves every DailyRhythmDay canonical field & deterministic streak/freeze timeline', () => {
    withMockBrowserStorage((store) => {
      // Build 15 qualifying days (earning 1 freeze) + 1 protected gap + 1 qualifying recovery day
      const records: DailyRhythmDayRecord[] = [];
      for (let day = 1; day <= 15; day++) {
        const dd = String(day).padStart(2, '0');
        records.push(
          buildQualifyingDay(
            `2026-11-${dd}`,
            day % 2 === 0 ? 'closed_no_transactions' : 'closed_with_transactions'
          )
        );
      }
      // 2026-11-16 missed (protected by earned freeze), 2026-11-17 qualifies, 2026-11-18 partial/needs_reconfirmation
      records.push(buildQualifyingDay('2026-11-17', 'closed_with_transactions'));
      records.push({
        dateIso: '2026-11-18',
        bibleStudyDone: true,
        bibleStudyCompletedAt: '2026-11-18T06:00:00.000Z',
        prayerDone: true,
        prayerCompletedAt: '2026-11-18T06:15:00.000Z',
        taskReviewConfirmed: true,
        taskReviewedAt: '2026-11-18T17:00:00.000Z',
        taskReviewEvidence: {
          overdueCount: 1,
          todayCount: 4,
          plannedCount: 2,
          completedTodayCount: 1,
        },
        financeCloseStatus: 'needs_reconfirmation',
        updatedAt: '2026-11-18T18:00:00.000Z',
      });

      dailyRhythmService.saveDays(records);
      const beforeSummary = evaluateDailyRhythmTimeline(dailyRhythmService.loadDays(), {
        todayIso: '2026-11-18',
      });
      assert.strictEqual(beforeSummary.totalQualifyingDays, 16);
      assert.strictEqual(beforeSummary.freezesUsedTotal, 1);
      assert.strictEqual(beforeSummary.availableFreezes, 0);
      assert.strictEqual(beforeSummary.currentStreak, 16);

      const exportedRaw = SharedStateBridge.exportToAndroidJson();
      const exported = JSON.parse(exportedRaw);
      assert.strictEqual(exported.schemaVersion, 5);
      assert.strictEqual(exported.snapshotFormatVersion, 2);
      assert.strictEqual(exported.databaseSchemaVersion, 13);
      assert.strictEqual(exported.dailyRhythmDays.length, 17);

      // Clear localStorage completely and restore
      store.clear();
      const restoreRes = SharedStateBridge.importFromAndroidJson(exportedRaw);
      assert.strictEqual(restoreRes.success, true, restoreRes.error);
      assert.strictEqual(restoreRes.state?.dailyRhythmDays?.length, 17);

      const restoredDays = dailyRhythmService.loadDays();
      assert.deepStrictEqual(restoredDays, records);
      const afterSummary = evaluateDailyRhythmTimeline(restoredDays, {
        todayIso: '2026-11-18',
      });
      assert.deepStrictEqual(afterSummary, beforeSummary);
    });
  });

  it('3. Backward-compatible v4-v11 backups lacking dailyRhythmDays restore safely with zero fabricated historical check-ins', () => {
    withMockBrowserStorage(() => {
      const olderSnapshots: Array<Record<string, unknown>> = [
        { schemaVersion: 4, accounts: [], transactions: [] },
        { schemaVersion: 5, snapshotFormatVersion: 1, databaseSchemaVersion: 8, accounts: [], transactions: [] },
        { schemaVersion: 5, snapshotFormatVersion: 2, databaseSchemaVersion: 9, accounts: [], transactions: [] },
        { schemaVersion: 5, snapshotFormatVersion: 2, databaseSchemaVersion: 10, accounts: [], transactions: [] },
        { schemaVersion: 5, snapshotFormatVersion: 2, databaseSchemaVersion: 11, accounts: [], transactions: [] },
      ];

      for (const snap of olderSnapshots) {
        const res = SharedStateBridge.importFromAndroidJson(JSON.stringify(snap));
        assert.strictEqual(res.success, true, res.error);
        assert.deepStrictEqual(res.state?.dailyRhythmDays, []);
        assert.deepStrictEqual(dailyRhythmService.loadDays(), []);
      }
    });
  });

  it('4. Fail-closed backup validation rejects malformed DailyRhythmDays and future v13 without mutating existing storage', () => {
    withMockBrowserStorage((store) => {
      const existingDay = buildQualifyingDay('2026-11-21', 'closed_no_transactions');
      dailyRhythmService.upsertDay(existingDay);
      SharedStateBridge.saveCanonicalState(SharedStateBridge.assembleLiveDatabaseState());
      const snapshotBefore = new Map(store);

      const invalidPayloads: Array<{ name: string; payload: Record<string, unknown>; kind: string }> = [
        {
          name: 'duplicate dateIso',
          payload: {
            ...CANONICAL_SEED_DATABASE,
            schemaVersion: 5,
            snapshotFormatVersion: 2,
            databaseSchemaVersion: 12,
            dailyRhythmDays: [
              buildQualifyingDay('2026-11-20'),
              buildQualifyingDay('2026-11-20'),
            ],
          },
          kind: 'invalid_payload',
        },
        {
          name: 'invalid calendar dateIso',
          payload: {
            ...CANONICAL_SEED_DATABASE,
            schemaVersion: 5,
            snapshotFormatVersion: 2,
            databaseSchemaVersion: 12,
            dailyRhythmDays: [
              { dateIso: '2026-02-30', bibleStudyDone: true },
            ],
          },
          kind: 'invalid_payload',
        },
        {
          name: 'invalid financeCloseStatus',
          payload: {
            ...CANONICAL_SEED_DATABASE,
            schemaVersion: 5,
            snapshotFormatVersion: 2,
            databaseSchemaVersion: 12,
            dailyRhythmDays: [
              { dateIso: '2026-11-20', financeCloseStatus: 'bogus_status' },
            ],
          },
          kind: 'invalid_payload',
        },
        {
          name: 'negative taskReviewEvidence count',
          payload: {
            ...CANONICAL_SEED_DATABASE,
            schemaVersion: 5,
            snapshotFormatVersion: 2,
            databaseSchemaVersion: 12,
            dailyRhythmDays: [
              {
                dateIso: '2026-11-20',
                taskReviewConfirmed: true,
                taskReviewEvidence: { overdueCount: -1 },
              },
            ],
          },
          kind: 'invalid_payload',
        },
        {
          name: 'malformed timestamp',
          payload: {
            ...CANONICAL_SEED_DATABASE,
            schemaVersion: 5,
            snapshotFormatVersion: 2,
            databaseSchemaVersion: 12,
            dailyRhythmDays: [
              {
                dateIso: '2026-11-20',
                bibleStudyDone: true,
                bibleStudyCompletedAt: 'not-an-iso-timestamp',
              },
            ],
          },
          kind: 'invalid_payload',
        },
        {
          name: 'future databaseSchemaVersion 14',
          payload: {
            ...CANONICAL_SEED_DATABASE,
            schemaVersion: 5,
            snapshotFormatVersion: 2,
            databaseSchemaVersion: 14,
            dailyRhythmDays: [],
          },
          kind: 'unsupported_future_schema',
        },
      ];

      for (const tc of invalidPayloads) {
        const res = SharedStateBridge.importFromAndroidJson(JSON.stringify(tc.payload));
        assert.strictEqual(res.success, false, `Expected failure for ${tc.name}`);
        assert.strictEqual(res.errorKind, tc.kind, tc.name);
        assert.deepStrictEqual([...store.entries()], [...snapshotBefore.entries()]);
      }
    });
  });

  it('5. Finance-only boundary excludes/rejects dailyRhythmDays and preserves Daily Rhythm history & spent freezes across historical Finance edits', () => {
    withMockBrowserStorage(() => {
      const seedRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          ...CANONICAL_SEED_DATABASE,
          schemaVersion: 5,
          snapshotFormatVersion: 2,
          databaseSchemaVersion: 12,
          accounts: [
            {
              id: 'acc-cash',
              name: 'Wallet',
              type: 'asset',
              subType: 'cash',
              currencyCode: 'ETB',
              openingBalanceCents: 100000,
            },
          ],
          dailyRhythmDays: [
            ...Array.from({ length: 15 }, (_, idx) =>
              buildQualifyingDay(`2026-11-${String(idx + 1).padStart(2, '0')}`)
            ),
            // 2026-11-16 missed (protected by earned freeze), 2026-11-17 qualifies
            buildQualifyingDay('2026-11-17'),
          ] satisfies SharedDailyRhythmDay[],
        })
      );
      assert.strictEqual(seedRes.success, true, seedRes.error);

      const financeExportStr = SharedStateBridge.exportFinanceOnlyJson();
      const financeExport = JSON.parse(financeExportStr);
      assert.strictEqual(financeExport.financeOnly, true);
      assert.strictEqual(financeExport.databaseSchemaVersion, 13);
      assert.strictEqual('dailyRhythmDays' in financeExport, false);

      // Finance-only import rejects contamination with dailyRhythmDays
      const contaminated = {
        ...financeExport,
        dailyRhythmDays: [buildQualifyingDay('2026-11-18')],
      };
      const rejected = SharedStateBridge.importFinanceOnlyJson(JSON.stringify(contaminated));
      assert.strictEqual(rejected.success, false);
      assert.strictEqual(rejected.errorKind, 'invalid_payload');

      // Valid Finance-only import simulating a historical accounting correction leaves Daily Rhythm & spent freeze untouched
      const correctedFin = {
        ...financeExport,
        transactions: [
          {
            id: 'tx-historical-void',
            categoryId: 'cat-food',
            amountCents: 2500,
            type: 'expense',
            transactionDate: '2026-11-03',
            accountId: 'acc-cash',
            isSuperseded: true,
            correctionReason: 'Historical entry voided',
            createdAt: '2026-11-03T12:00:00.000Z',
          },
        ],
      };
      const finImportRes = SharedStateBridge.importFinanceOnlyJson(
        JSON.stringify(correctedFin)
      );
      assert.strictEqual(finImportRes.success, true, finImportRes.error);

      const daysAfter = dailyRhythmService.loadDays();
      assert.strictEqual(daysAfter.length, 16);
      const summaryAfter = evaluateDailyRhythmTimeline(daysAfter, {
        todayIso: '2026-11-17',
      });
      assert.strictEqual(summaryAfter.totalQualifyingDays, 16);
      assert.strictEqual(summaryAfter.freezesUsedTotal, 1);
      assert.strictEqual(summaryAfter.availableFreezes, 0);
      assert.strictEqual(summaryAfter.currentStreak, 16);
    });
  });

  it('6. Flutter Stage B schema v12, Drift repository, version policy, and backup coordinator maintain symmetric contracts without duplicated streak math', () => {
    const tables = readRepoFile('flutter_app/lib/data/database/tables.dart');
    assert.match(tables, /class DailyRhythmDays extends Table/);
    assert.match(tables, /Set<Column> get primaryKey => \{dateIso\};/);

    const appDb = readRepoFile('flutter_app/lib/data/database/app_database.dart');
    assert.match(appDb, /DailyRhythmDays,/);
    assert.match(appDb, /int get schemaVersion => 13;/);
    assert.match(appDb, /if \(from < 12\)/);
    assert.match(appDb, /_createV12DailyRhythmPerformanceIndices\(\)/);
    assert.match(appDb, /idx_daily_rhythm_days_updated_at/);

    const contract = readRepoFile('flutter_app/lib/domain/daily_rhythm/daily_rhythm_contracts.dart');
    assert.doesNotMatch(contract, /package:flutter\//);
    assert.doesNotMatch(contract, /package:drift\//);
    assert.match(contract, /abstract class IDailyRhythmRepository/);

    const repo = readRepoFile('flutter_app/lib/data/repositories/daily_rhythm_repository.dart');
    assert.match(repo, /class DriftDailyRhythmRepository implements IDailyRhythmRepository/);
    assert.match(repo, /insertOnConflictUpdate/);
    assert.doesNotMatch(repo, /evaluateTimeline/);

    const policy = readRepoFile('flutter_app/lib/core/snapshot_version_policy.dart');
    assert.match(policy, /supportedDatabaseSchemaVersion = 13;/);
    assert.match(policy, /maxSupportedDatabaseSchemaVersion = 13;/);

    const enc = readRepoFile('flutter_app/lib/services/backup/encryption_backup_service.dart');
    assert.match(enc, /maxSupportedDatabaseSchemaVersion = 13;/);

    const coord = readRepoFile('flutter_app/lib/data/database/database_persistence_coordinator.dart');
    assert.match(coord, /'dailyRhythmDays':\s*dailyRhythmDays/);
    assert.match(coord, /'dailyRhythmDays',/);
    assert.match(coord, /7a-2\. DailyRhythmDays/);
  });
});
