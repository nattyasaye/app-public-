import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  AUTHENTICATION_FAILURE_MESSAGE,
  BackupValidationError,
  classifyBackupError,
  computeSha256Bytes,
  decryptDatabaseBackup,
  encryptDatabaseBackup,
  validateBackupEnvelopeHeader,
} from './backupCrypto';
import type { LocalDatabaseState } from './backupTypes';
import { CANONICAL_SEED_DATABASE } from './sharedFoundation';
import { SharedStateBridge } from '../services/sharedStateBridge';

function withMockBrowserStorage<T>(
  run: (store: Map<string, string>) => T
): T {
  const prevWindow = (globalThis as any).window;
  const prevLocalStorage = (globalThis as any).localStorage;
  const store = new Map<string, string>();
  const mockLocalStorage = {
    getItem: (key: string) => (store.has(key) ? store.get(key)! : null),
    setItem: (key: string, value: string) => {
      store.set(key, String(value));
    },
    removeItem: (key: string) => {
      store.delete(key);
    },
    clear: () => {
      store.clear();
    },
  };

  (globalThis as any).localStorage = mockLocalStorage;
  (globalThis as any).window = {
    localStorage: mockLocalStorage,
    dispatchEvent: () => true,
    CustomEvent: class CustomEvent {
      type: string;
      detail: any;
      constructor(type: string, init?: { detail?: any }) {
        this.type = type;
        this.detail = init?.detail;
      }
    },
  };

  try {
    return run(store);
  } finally {
    (globalThis as any).window = prevWindow;
    (globalThis as any).localStorage = prevLocalStorage;
  }
}

function seedAllDaywellStores(store: Map<string, string>): Map<string, string> {
  const baselineEntries: Array<[string, string]> = [
    [
      SharedStateBridge.STORAGE_KEY,
      JSON.stringify({ schemaVersion: 5, financeSchemaVersion: 7, marker: 'keep-canonical' }),
    ],
    ['daywell_accounts', JSON.stringify([{ id: 'acc-live', name: 'Live CBE', type: 'asset' }])],
    ['daywell_categories', JSON.stringify([{ id: 'cat-live', name: 'Groceries', type: 'expense' }])],
    [
      'daywell_finance_transactions',
      JSON.stringify([{ id: 'tx-live', amountCents: 12500, transactionDate: '2026-11-10' }]),
    ],
    [
      'daywell_transactions',
      JSON.stringify([{ id: 'tx-live', amountCents: 12500, transactionDate: '2026-11-10' }]),
    ],
    ['daywell_commitments', JSON.stringify([{ id: 'c-live', title: 'Rent', amountCents: 50000 }])],
    ['daywell_commitment_settlements', JSON.stringify([{ id: 'cs-live', amountCents: 50000 }])],
    ['daywell_savings_goals', JSON.stringify([{ id: 'sg-live', title: 'Emergency' }])],
    ['daywell_budgets', JSON.stringify([{ id: 'b-live', limitCents: 90000 }])],
    ['daywell_recurring_rules', JSON.stringify([{ id: 'rr-live', title: 'Internet' }])],
    ['daywell_parties', JSON.stringify([{ id: 'party-live', name: 'Abebe' }])],
    ['daywell_journal_entries', JSON.stringify([{ id: 'je-live', entryType: 'expense' }])],
    ['daywell_postings', JSON.stringify([{ id: 'post-live', amountCents: 12500 }])],
    ['daywell_debts', JSON.stringify([{ id: 'debt-live', principalCents: 20000 }])],
    ['daywell_settlement_allocations', JSON.stringify([{ id: 'sa-live', allocatedCents: 5000 }])],
    ['daywell_tasks', JSON.stringify([{ id: 'task-live', title: 'Keep existing task' }])],
    ['daywell_notes', JSON.stringify([{ id: 'note-live', title: 'Keep existing note' }])],
    [SharedStateBridge.PROJECTS_STORAGE_KEY, JSON.stringify([{ id: 'proj-live', title: 'Live Project' }])],
    [SharedStateBridge.GOALS_STORAGE_KEY, JSON.stringify([{ id: 'goal-live', title: 'Live Goal' }])],
    [SharedStateBridge.INBOX_STORAGE_KEY, JSON.stringify([{ id: 'inbox-live', rawText: 'Live inbox' }])],
    ['daywell_calendar_events', JSON.stringify([{ id: 'evt-live', date: '2026-11-15' }])],
    ['daywell_finance_setup_completed', 'true'],
    ['daywell_reminders_custom', JSON.stringify([{ id: 'rem-live', title: 'Keep Reminder' }])],
    ['daywell_settings_custom', JSON.stringify({ calendarPreference: 'ethiopian' })],
  ];

  store.clear();
  for (const [k, v] of baselineEntries) {
    store.set(k, v);
  }
  return new Map(store);
}

function assertStoreUnchanged(
  store: Map<string, string>,
  baseline: Map<string, string>,
  label: string
) {
  assert.strictEqual(
    store.size,
    baseline.size,
    `${label}: storage key count changed (${store.size} vs ${baseline.size})`
  );
  for (const [key, expectedValue] of baseline.entries()) {
    assert.strictEqual(
      store.get(key),
      expectedValue,
      `${label}: localStorage key "${key}" mutated despite rejected import`
    );
  }
}

function makeSampleLocalDbState(version = 3): LocalDatabaseState {
  return {
    version,
    inbox: [
      {
        id: 'inb-1',
        rawText: 'Pay electricity bill',
        category: 'task',
        isProcessed: false,
        createdAtUtc: '2026-11-10T08:00:00.000Z',
      },
    ],
    goals: [],
    projects: [],
    milestones: [],
    tasks: [
      {
        id: 't-1',
        title: 'Inspect battery bank',
        status: 'not_started',
        priority: 'high',
        createdAtUtc: '2026-11-10T08:00:00.000Z',
        updatedAtUtc: '2026-11-10T08:00:00.000Z',
      },
    ],
    categories: [
      {
        id: 'cat-1',
        name: 'Utilities',
        type: 'expense',
        colorHex: '#EF4444',
        isDefault: true,
      },
    ],
    transactions: [],
    commitments: [],
    savingsGoals: [],
    notes: [],
    reminders: [],
    backupLogs: [],
    openingBalanceCents: 250000,
    incomesCents: [],
    expensesCents: [],
    savingsAllocationsCents: [],
    budgetPeriod: 'current_month',
    lastSavedUtc: '2026-11-10T08:00:00.000Z',
  };
}

describe('Governance Stage 3.4.2: Web Fail-Closed Version Bounds & Backup Validation', () => {
  it('1. SharedStateBridge accepts canonical schemaVersion 4..9 (+ financeSchemaVersion 7) and omitted legacy default 5', () => {
    withMockBrowserStorage(() => {
      for (const version of [4, 5, 6, 7, 8, 9]) {
        const res = SharedStateBridge.importFromAndroidJson(
          JSON.stringify({
            schemaVersion: version,
            financeSchemaVersion: 7,
            accounts: [],
            transactions: [],
          })
        );
        assert.strictEqual(res.success, true, `schemaVersion ${version} should be accepted: ${res.error}`);
        assert.strictEqual(res.state?.schemaVersion, version);
        assert.strictEqual(res.state?.financeSchemaVersion, 7);
      }

      const omittedVersion = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          accounts: [],
          transactions: [],
        })
      );
      assert.strictEqual(omittedVersion.success, true);
      assert.strictEqual(omittedVersion.state?.schemaVersion, 5);
      assert.strictEqual(omittedVersion.state?.snapshotFormatVersion, 1);
    });
  });

  it('1b. SharedStateBridge validates separated snapshotFormatVersion (1..2, omitted->1) and optional databaseSchemaVersion (1..9) fail-closed before mutating localStorage', () => {
    withMockBrowserStorage((store) => {
      for (const fmtVersion of [1, 2]) {
        const res = SharedStateBridge.importFromAndroidJson(
          JSON.stringify({
            schemaVersion: 5,
            snapshotFormatVersion: fmtVersion,
            databaseSchemaVersion: 9,
            financeSchemaVersion: 7,
            accounts: [],
            transactions: [],
          })
        );
        assert.strictEqual(res.success, true, `snapshotFormatVersion ${fmtVersion} rejected: ${res.error}`);
        assert.strictEqual(res.state?.snapshotFormatVersion, fmtVersion);
        assert.strictEqual(res.state?.databaseSchemaVersion, 9);
      }

      const rejectedMetadataCases: Array<{
        name: string;
        overrides: Record<string, unknown>;
        expectedKind: string;
      }> = [
        {
          name: 'future snapshotFormatVersion 3',
          overrides: { snapshotFormatVersion: 3 },
          expectedKind: 'unsupported_future_schema',
        },
        {
          name: 'lower snapshotFormatVersion 0',
          overrides: { snapshotFormatVersion: 0 },
          expectedKind: 'invalid_snapshot_version',
        },
        {
          name: 'negative snapshotFormatVersion -1',
          overrides: { snapshotFormatVersion: -1 },
          expectedKind: 'invalid_snapshot_version',
        },
        {
          name: 'float snapshotFormatVersion 1.5',
          overrides: { snapshotFormatVersion: 1.5 },
          expectedKind: 'invalid_snapshot_version',
        },
        {
          name: 'string snapshotFormatVersion "2"',
          overrides: { snapshotFormatVersion: '2' },
          expectedKind: 'invalid_snapshot_version',
        },
        {
          name: 'null snapshotFormatVersion',
          overrides: { snapshotFormatVersion: null },
          expectedKind: 'invalid_snapshot_version',
        },
        {
          name: 'future databaseSchemaVersion 10',
          overrides: { snapshotFormatVersion: 2, databaseSchemaVersion: 10 },
          expectedKind: 'unsupported_future_schema',
        },
        {
          name: 'lower databaseSchemaVersion 0',
          overrides: { databaseSchemaVersion: 0 },
          expectedKind: 'invalid_snapshot_version',
        },
        {
          name: 'negative databaseSchemaVersion -1',
          overrides: { databaseSchemaVersion: -1 },
          expectedKind: 'invalid_snapshot_version',
        },
        {
          name: 'float databaseSchemaVersion 9.5',
          overrides: { databaseSchemaVersion: 9.5 },
          expectedKind: 'invalid_snapshot_version',
        },
        {
          name: 'string databaseSchemaVersion "9"',
          overrides: { databaseSchemaVersion: '9' },
          expectedKind: 'invalid_snapshot_version',
        },
        {
          name: 'null databaseSchemaVersion',
          overrides: { databaseSchemaVersion: null },
          expectedKind: 'invalid_snapshot_version',
        },
      ];

      for (const tc of rejectedMetadataCases) {
        const baseline = seedAllDaywellStores(store);
        const res = SharedStateBridge.importFromAndroidJson(
          JSON.stringify({
            schemaVersion: 5,
            financeSchemaVersion: 7,
            accounts: [],
            transactions: [],
            ...tc.overrides,
          })
        );
        assert.strictEqual(res.success, false, `${tc.name} should be rejected`);
        assert.strictEqual(
          res.errorKind,
          tc.expectedKind,
          `${tc.name} produced wrong errorKind (${res.errorKind}): ${res.error}`
        );
        assertStoreUnchanged(store, baseline, tc.name);
      }
    });
  });

  it('2. SharedStateBridge rejects unsupported future (> 9), legacy v3 (< 4), contradictory, invalid, and malformed payloads before mutating localStorage', () => {
    const rejectedCases: Array<{
      name: string;
      payload: string;
      expectedKind: string;
    }> = [
      {
        name: 'future schemaVersion 10',
        payload: JSON.stringify({ ...CANONICAL_SEED_DATABASE, schemaVersion: 10 }),
        expectedKind: 'unsupported_future_schema',
      },
      {
        name: 'future schemaVersion 99',
        payload: JSON.stringify({ ...CANONICAL_SEED_DATABASE, schemaVersion: 99 }),
        expectedKind: 'unsupported_future_schema',
      },
      {
        name: 'future financeSchemaVersion 8',
        payload: JSON.stringify({
          ...CANONICAL_SEED_DATABASE,
          schemaVersion: 5,
          financeSchemaVersion: 8,
        }),
        expectedKind: 'unsupported_future_schema',
      },
      {
        name: 'future financeSchemaVersion 99',
        payload: JSON.stringify({
          ...CANONICAL_SEED_DATABASE,
          schemaVersion: 5,
          financeSchemaVersion: 99,
        }),
        expectedKind: 'unsupported_future_schema',
      },
      {
        name: 'legacy LocalDatabaseState v3',
        payload: JSON.stringify({
          version: 3,
          accounts: [],
          transactions: [],
        }),
        expectedKind: 'invalid_snapshot_version',
      },
      {
        name: 'out-of-bounds lower schemaVersion 2',
        payload: JSON.stringify({ ...CANONICAL_SEED_DATABASE, schemaVersion: 2 }),
        expectedKind: 'invalid_snapshot_version',
      },
      {
        name: 'lower financeSchemaVersion 6',
        payload: JSON.stringify({
          ...CANONICAL_SEED_DATABASE,
          schemaVersion: 5,
          financeSchemaVersion: 6,
        }),
        expectedKind: 'invalid_snapshot_version',
      },
      {
        name: 'negative schemaVersion -1',
        payload: JSON.stringify({ ...CANONICAL_SEED_DATABASE, schemaVersion: -1 }),
        expectedKind: 'invalid_snapshot_version',
      },
      {
        name: 'float schemaVersion 5.5',
        payload: JSON.stringify({ ...CANONICAL_SEED_DATABASE, schemaVersion: 5.5 }),
        expectedKind: 'invalid_snapshot_version',
      },
      {
        name: 'string schemaVersion "5"',
        payload: JSON.stringify({ ...CANONICAL_SEED_DATABASE, schemaVersion: '5' }),
        expectedKind: 'invalid_snapshot_version',
      },
      {
        name: 'explicit null schemaVersion',
        payload: JSON.stringify({ ...CANONICAL_SEED_DATABASE, schemaVersion: null }),
        expectedKind: 'invalid_snapshot_version',
      },
      {
        name: 'explicit null financeSchemaVersion',
        payload: JSON.stringify({
          ...CANONICAL_SEED_DATABASE,
          schemaVersion: 5,
          financeSchemaVersion: null,
        }),
        expectedKind: 'invalid_snapshot_version',
      },
      {
        name: 'contradictory schemaVersion and version',
        payload: JSON.stringify({
          ...CANONICAL_SEED_DATABASE,
          schemaVersion: 5,
          version: 7,
        }),
        expectedKind: 'invalid_snapshot_version',
      },
      {
        name: 'non-object root array',
        payload: JSON.stringify([1, 2, 3]),
        expectedKind: 'invalid_payload',
      },
      {
        name: 'malformed optional collection tasks="not-an-array"',
        payload: JSON.stringify({
          schemaVersion: 5,
          accounts: [],
          transactions: [],
          tasks: 'not-an-array',
        }),
        expectedKind: 'invalid_payload',
      },
      {
        name: 'invalid date inside later transaction leaves earlier stores untouched',
        payload: JSON.stringify({
          schemaVersion: 5,
          accounts: [{ id: 'acc-new', name: 'New', type: 'asset' }],
          transactions: [
            {
              id: 'tx-bad',
              amountCents: 100,
              transactionDate: 'not-a-valid-date',
            },
          ],
        }),
        expectedKind: 'invalid_payload',
      },
    ];

    withMockBrowserStorage((store) => {
      for (const tc of rejectedCases) {
        const baseline = seedAllDaywellStores(store);
        const res = SharedStateBridge.importFromAndroidJson(tc.payload);
        assert.strictEqual(res.success, false, `${tc.name} should be rejected`);
        assert.strictEqual(
          res.errorKind,
          tc.expectedKind,
          `${tc.name} produced wrong errorKind (${res.errorKind}): ${res.error}`
        );
        assert.ok(res.error && res.error.length > 0);
        assertStoreUnchanged(store, baseline, tc.name);
      }
    });
  });

  it('3. Encrypted backup validation accepts format_version 1, PBKDF2 100000 rounds, and LocalDatabaseState v3', async () => {
    const state = makeSampleLocalDbState(3);
    const envelopeJson = await encryptDatabaseBackup(state, 'StrongPassphrase!2026');

    const validated = validateBackupEnvelopeHeader(envelopeJson);
    assert.strictEqual(validated.envelope.header.format_version, 1);
    assert.strictEqual(validated.envelope.header.kdf, 'PBKDF2-HMAC-SHA256');
    assert.strictEqual(validated.envelope.header.iterations, 100000);
    assert.strictEqual(validated.envelope.header.schema_version, 3);

    const decrypted = await decryptDatabaseBackup(envelopeJson, 'StrongPassphrase!2026');
    assert.strictEqual(decrypted.state.version, 3);
    assert.strictEqual(decrypted.state.tasks[0].title, 'Inspect battery bank');
  });

  it('4. Encrypted backup reader rejects invalid headers, format_version, KDF, iterations, future schemas, and non-v3 inner versions fail-closed', async () => {
    const validState = makeSampleLocalDbState(3);
    const validEnvelopeJson = await encryptDatabaseBackup(validState, 'Secret#123');
    const validObj = JSON.parse(validEnvelopeJson);

    const headerFailureCases: Array<{
      name: string;
      mutate: (env: any) => any;
      expectedKind: string;
    }> = [
      {
        name: 'wrong format identifier',
        mutate: (e) => {
          e.header.format = 'other_app_backup';
          return e;
        },
        expectedKind: 'invalid_backup_header',
      },
      {
        name: 'missing format identifier',
        mutate: (e) => {
          delete e.header.format;
          return e;
        },
        expectedKind: 'invalid_backup_header',
      },
      {
        name: 'unsupported format_version 2',
        mutate: (e) => {
          e.header.format_version = 2;
          return e;
        },
        expectedKind: 'unsupported_format_version',
      },
      {
        name: 'unsupported format_version 99',
        mutate: (e) => {
          e.header.format_version = 99;
          return e;
        },
        expectedKind: 'unsupported_format_version',
      },
      {
        name: 'missing format_version',
        mutate: (e) => {
          delete e.header.format_version;
          return e;
        },
        expectedKind: 'invalid_backup_header',
      },
      {
        name: 'unknown KDF',
        mutate: (e) => {
          e.header.kdf = 'Argon2id';
          return e;
        },
        expectedKind: 'unsupported_kdf',
      },
      {
        name: 'missing KDF',
        mutate: (e) => {
          delete e.header.kdf;
          return e;
        },
        expectedKind: 'unsupported_kdf',
      },
      {
        name: 'iterations 99999 (< 100000)',
        mutate: (e) => {
          e.header.iterations = 99999;
          return e;
        },
        expectedKind: 'unsupported_kdf',
      },
      {
        name: 'iterations 100001 (> 100000)',
        mutate: (e) => {
          e.header.iterations = 100001;
          return e;
        },
        expectedKind: 'unsupported_kdf',
      },
      {
        name: 'missing iterations',
        mutate: (e) => {
          delete e.header.iterations;
          return e;
        },
        expectedKind: 'unsupported_kdf',
      },
      {
        name: 'unsupported future header schema_version 4',
        mutate: (e) => {
          e.header.schema_version = 4;
          return e;
        },
        expectedKind: 'unsupported_future_schema',
      },
      {
        name: 'unsupported future header schema_version 7',
        mutate: (e) => {
          e.header.schema_version = 7;
          return e;
        },
        expectedKind: 'unsupported_future_schema',
      },
      {
        name: 'unsupported lower header schema_version 2',
        mutate: (e) => {
          e.header.schema_version = 2;
          return e;
        },
        expectedKind: 'invalid_snapshot_version',
      },
      {
        name: 'invalid salt length',
        mutate: (e) => {
          e.header.salt_base64 = btoa('short');
          return e;
        },
        expectedKind: 'invalid_backup_header',
      },
      {
        name: 'invalid nonce length',
        mutate: (e) => {
          e.header.nonce_base64 = btoa('badnonce');
          return e;
        },
        expectedKind: 'invalid_backup_header',
      },
      {
        name: 'invalid checksum hex',
        mutate: (e) => {
          e.header.checksum_sha256 = 'not-a-sha256-digest';
          return e;
        },
        expectedKind: 'invalid_backup_header',
      },
    ];

    for (const tc of headerFailureCases) {
      const mutated = tc.mutate(structuredClone(validObj));
      await assert.rejects(
        () => decryptDatabaseBackup(JSON.stringify(mutated), 'Secret#123'),
        (err: unknown) => {
          assert.ok(err instanceof BackupValidationError, `${tc.name} threw non-BackupValidationError`);
          assert.strictEqual(err.kind, tc.expectedKind, `${tc.name}: expected ${tc.expectedKind}, got ${err.kind}`);
          return true;
        }
      );
    }
  });

  it('5. Encrypted backup distinguishes authentication_failure, integrity_failure, invalid_payload, and Web legacy v3 inner-version rules', async () => {
    const validState = makeSampleLocalDbState(3);
    const validEnvelopeJson = await encryptDatabaseBackup(validState, 'CorrectPass#2026');

    // Empty passphrase -> authentication_failure with neutral message
    await assert.rejects(
      () => decryptDatabaseBackup(validEnvelopeJson, '   '),
      (err: unknown) => {
        assert.ok(err instanceof BackupValidationError);
        assert.strictEqual(err.kind, 'authentication_failure');
        assert.strictEqual(err.message, AUTHENTICATION_FAILURE_MESSAGE);
        return true;
      }
    );

    // Wrong passphrase -> authentication_failure with neutral message
    await assert.rejects(
      () => decryptDatabaseBackup(validEnvelopeJson, 'WrongPass#2026'),
      (err: unknown) => {
        assert.ok(err instanceof BackupValidationError);
        assert.strictEqual(err.kind, 'authentication_failure');
        assert.strictEqual(err.message, AUTHENTICATION_FAILURE_MESSAGE);
        return true;
      }
    );

    // Tampered ciphertext -> authentication_failure (AES-GCM auth failure, identical neutral message)
    const tamperedCipher = JSON.parse(validEnvelopeJson);
    const cipherBytes = Buffer.from(tamperedCipher.ciphertext_base64, 'base64');
    cipherBytes[0] = cipherBytes[0] ^ 0xff;
    tamperedCipher.ciphertext_base64 = cipherBytes.toString('base64');
    await assert.rejects(
      () => decryptDatabaseBackup(JSON.stringify(tamperedCipher), 'CorrectPass#2026'),
      (err: unknown) => {
        assert.ok(err instanceof BackupValidationError);
        assert.strictEqual(err.kind, 'authentication_failure');
        assert.strictEqual(err.message, AUTHENTICATION_FAILURE_MESSAGE);
        return true;
      }
    );

    // Tampered MAC tag -> authentication_failure with neutral message
    const tamperedMac = JSON.parse(validEnvelopeJson);
    const macBytes = Buffer.from(tamperedMac.header.mac_base64, 'base64');
    macBytes[0] = macBytes[0] ^ 0xff;
    tamperedMac.header.mac_base64 = macBytes.toString('base64');
    await assert.rejects(
      () => decryptDatabaseBackup(JSON.stringify(tamperedMac), 'CorrectPass#2026'),
      (err: unknown) => {
        assert.ok(err instanceof BackupValidationError);
        assert.strictEqual(err.kind, 'authentication_failure');
        assert.strictEqual(err.message, AUTHENTICATION_FAILURE_MESSAGE);
        return true;
      }
    );

    // Tampered SHA-256 checksum -> integrity_failure (even if AES-GCM auth tag passes)
    const tamperedChecksum = JSON.parse(validEnvelopeJson);
    tamperedChecksum.header.checksum_sha256 = '0'.repeat(64);
    await assert.rejects(
      () => decryptDatabaseBackup(JSON.stringify(tamperedChecksum), 'CorrectPass#2026'),
      (err: unknown) => {
        assert.ok(err instanceof BackupValidationError);
        assert.strictEqual(err.kind, 'integrity_failure');
        return true;
      }
    );

    // Helper: create a cryptographically valid envelope wrapping raw plaintext bytes
    const encryptCustomInnerBytes = async (
      plaintextBytes: Uint8Array,
      headerSchemaVersion = 3
    ): Promise<string> => {
      const enc = new TextEncoder();
      const salt = crypto.getRandomValues(new Uint8Array(16));
      const iv = crypto.getRandomValues(new Uint8Array(12));
      const baseKey = await crypto.subtle.importKey(
        'raw',
        enc.encode('InnerTestPass'),
        { name: 'PBKDF2' },
        false,
        ['deriveKey']
      );
      const aesKey = await crypto.subtle.deriveKey(
        { name: 'PBKDF2', salt, iterations: 100000, hash: 'SHA-256' },
        baseKey,
        { name: 'AES-GCM', length: 256 },
        false,
        ['encrypt']
      );
      const buf = new Uint8Array(
        await crypto.subtle.encrypt(
          { name: 'AES-GCM', iv, tagLength: 128 },
          aesKey,
          plaintextBytes.buffer as ArrayBuffer
        )
      );
      const ciphertext = buf.slice(0, buf.length - 16);
      const mac = buf.slice(buf.length - 16);
      return JSON.stringify({
        header: {
          format: 'personal_mgmt_encrypted_backup',
          format_version: 1,
          app_version: '1.0.0',
          schema_version: headerSchemaVersion,
          created_at_utc: '2026-11-10T08:00:00.000Z',
          kdf: 'PBKDF2-HMAC-SHA256',
          iterations: 100000,
          salt_base64: Buffer.from(salt).toString('base64'),
          nonce_base64: Buffer.from(iv).toString('base64'),
          mac_base64: Buffer.from(mac).toString('base64'),
          checksum_sha256: await computeSha256Bytes(plaintextBytes),
        },
        ciphertext_base64: Buffer.from(ciphertext).toString('base64'),
      });
    };

    const encryptCustomInner = (plaintext: string, headerSchemaVersion = 3) =>
      encryptCustomInnerBytes(new TextEncoder().encode(plaintext), headerSchemaVersion);

    // Authenticated & SHA-256-matched invalid UTF-8 bytes -> invalid_payload (not integrity_failure)
    const invalidUtf8Envelope = await encryptCustomInnerBytes(new Uint8Array([0xff, 0xfe, 0xfd]));
    await assert.rejects(
      () => decryptDatabaseBackup(invalidUtf8Envelope, 'InnerTestPass'),
      (err: unknown) => {
        assert.ok(err instanceof BackupValidationError);
        assert.strictEqual(err.kind, 'invalid_payload');
        return true;
      }
    );

    // Inner non-JSON payload -> invalid_payload
    const innerBadJsonEnvelope = await encryptCustomInner('not-valid-json{{{');
    await assert.rejects(
      () => decryptDatabaseBackup(innerBadJsonEnvelope, 'InnerTestPass'),
      (err: unknown) => {
        assert.ok(err instanceof BackupValidationError);
        assert.strictEqual(err.kind, 'invalid_payload');
        return true;
      }
    );

    // Inner JSON array (non-object) -> invalid_payload
    const innerArrayEnvelope = await encryptCustomInner('[1, 2, 3]');
    await assert.rejects(
      () => decryptDatabaseBackup(innerArrayEnvelope, 'InnerTestPass'),
      (err: unknown) => {
        assert.ok(err instanceof BackupValidationError);
        assert.strictEqual(err.kind, 'invalid_payload');
        return true;
      }
    );

    // Preserve Web legacy contract: omitted inner version is rejected (NOT defaulted to Flutter's 5)
    const omittedVersionEnvelope = await encryptCustomInner(JSON.stringify({ tasks: [] }), 3);
    await assert.rejects(
      () => decryptDatabaseBackup(omittedVersionEnvelope, 'InnerTestPass'),
      (err: unknown) => {
        assert.ok(err instanceof BackupValidationError);
        assert.strictEqual(err.kind, 'invalid_snapshot_version');
        return true;
      }
    );

    // Preserve Web legacy contract: header schema_version 5 + inner version 5 rejected as unsupported_future_schema
    const v5Envelope = await encryptCustomInner(JSON.stringify({ version: 5, tasks: [] }), 5);
    await assert.rejects(
      () => decryptDatabaseBackup(v5Envelope, 'InnerTestPass'),
      (err: unknown) => {
        assert.ok(err instanceof BackupValidationError);
        assert.strictEqual(err.kind, 'unsupported_future_schema');
        return true;
      }
    );

    // Inner future version 7 -> unsupported_future_schema
    const innerV7Envelope = await encryptCustomInner(JSON.stringify({ version: 7, tasks: [] }), 3);
    await assert.rejects(
      () => decryptDatabaseBackup(innerV7Envelope, 'InnerTestPass'),
      (err: unknown) => {
        assert.ok(err instanceof BackupValidationError);
        assert.strictEqual(err.kind, 'unsupported_future_schema');
        return true;
      }
    );

    // Inner lower version 2 -> invalid_snapshot_version
    const innerV2Envelope = await encryptCustomInner(JSON.stringify({ version: 2, tasks: [] }), 3);
    await assert.rejects(
      () => decryptDatabaseBackup(innerV2Envelope, 'InnerTestPass'),
      (err: unknown) => {
        assert.ok(err instanceof BackupValidationError);
        assert.strictEqual(err.kind, 'invalid_snapshot_version');
        return true;
      }
    );

    const classified = classifyBackupError(
      new BackupValidationError('unsupported_kdf', 'Bad KDF')
    );
    assert.strictEqual(classified.kind, 'unsupported_kdf');
    assert.strictEqual(classified.message, 'Bad KDF');
  });
});
