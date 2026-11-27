import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import {
  checkFoundation,
  syncFoundation,
  validateBusinessRules,
  validateCalendarTestVectors,
  validateCanonicalSeedDatabase,
  validateSchemaContracts,
  // @ts-ignore - ESM script validated dynamically by Node test runner
} from '../../scripts/sync_foundation.mjs';

const REPO_ROOT = process.cwd();

function readRepoJson(relPath: string): any {
  return JSON.parse(fs.readFileSync(path.join(REPO_ROOT, relPath), 'utf8'));
}

function createIsolatedFoundationRoot(): string {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'daywell-stage32-'));
  const filesToCopy = [
    'shared_foundation/design_tokens.json',
    'shared_foundation/business_rules.json',
    'shared_foundation/schema_contracts.json',
    'shared_foundation/canonical_seed_database.json',
    'shared_foundation/calendar_test_vectors.json',
    'scripts/foundation_compatibility_baseline.json',
    'src/domain/sharedFoundation.ts',
    'src/styles/daywellTokens.css',
    'flutter_app/lib/core/shared_foundation_core.dart',
    'flutter_app/lib/core/shared_foundation.dart',
    'flutter_app/lib/data/database/app_database.dart',
    'flutter_app/lib/data/database/tables.dart',
    'flutter_app/lib/domain/finance/double_entry_engine.dart',
    'flutter_app/test/stage344_snapshot_fidelity_restore_test.dart',
    'scripts/sync_foundation.mjs',
    'src/domain/doubleEntryFinance.ts',
    'src/domain/financeV7Engine.ts',
    'src/services/sharedStateBridge.ts',
    'src/components/DaywellFinanceModule.tsx',
    'src/components/finance/FinanceOverviewTab.tsx',
    'src/components/finance/FinanceComposerModal.tsx',
    'src/domain/sharedFoundationParity.test.ts',
    'src/domain/stage4Contracts.test.ts',
    'src/domain/stage32FoundationGovernance.test.ts',
    'src/domain/stage33GovernanceEnforcement.test.ts',
    'src/domain/financeV7WebParity.test.ts',
    'docs/architecture/decisions/ADR-007-mandatory-backward-compatibility.md',
    'docs/architecture/decisions/ADR-008-retire-account-isactive-and-schema-v8.md',
  ];

  for (const relPath of filesToCopy) {
    const src = path.join(REPO_ROOT, relPath);
    const dest = path.join(tmpDir, relPath);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(src, dest);
  }

  return tmpDir;
}

describe('GOVERNANCE STAGE 3.2: FOUNDATION FRESHNESS, VALIDATION & COMPATIBILITY GUARDS', () => {
  it('1. --check mode passes on fresh generated files and never writes to disk', () => {
    const tmpDir = createIsolatedFoundationRoot();
    try {
      const generatedFiles = [
        path.join(tmpDir, 'src/domain/sharedFoundation.ts'),
        path.join(tmpDir, 'src/styles/daywellTokens.css'),
        path.join(tmpDir, 'flutter_app/lib/core/shared_foundation_core.dart'),
        path.join(tmpDir, 'flutter_app/lib/core/shared_foundation.dart'),
      ];
      const beforeContents = generatedFiles.map((f) => fs.readFileSync(f, 'utf8'));

      const result = checkFoundation({ rootDir: tmpDir, silent: true });
      assert.strictEqual(result.fresh, true);

      const cliRes = spawnSync(
        process.execPath,
        [path.join(REPO_ROOT, 'scripts/sync_foundation.mjs'), '--check', '--root', tmpDir],
        { encoding: 'utf8' }
      );
      assert.strictEqual(cliRes.status, 0, `Expected exit 0, stderr=${cliRes.stderr}`);

      const afterContents = generatedFiles.map((f) => fs.readFileSync(f, 'utf8'));
      assert.deepStrictEqual(afterContents, beforeContents, '--check must not modify files');
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it('2. --check mode detects stale TS or Dart generated files without overwriting them, and sync-foundation repairs them', () => {
    const tmpDir = createIsolatedFoundationRoot();
    try {
      const tsFile = path.join(tmpDir, 'src/domain/sharedFoundation.ts');
      const dartFile = path.join(tmpDir, 'flutter_app/lib/core/shared_foundation.dart');
      const dartCoreFile = path.join(tmpDir, 'flutter_app/lib/core/shared_foundation_core.dart');

      // Case A: manually modified TS generated file
      const staleTsMarker = '// MANUAL STALE EDIT\n' + fs.readFileSync(tsFile, 'utf8');
      fs.writeFileSync(tsFile, staleTsMarker, 'utf8');

      const cliResTs = spawnSync(
        process.execPath,
        [path.join(REPO_ROOT, 'scripts/sync_foundation.mjs'), '--check', '--root', tmpDir],
        { encoding: 'utf8' }
      );
      assert.notStrictEqual(cliResTs.status, 0, 'CLI --check must exit non-zero when TS output is stale');
      assert.match(cliResTs.stderr, /src\/domain\/sharedFoundation\.ts/);
      assert.match(cliResTs.stderr, /npm run sync-foundation/);
      assert.strictEqual(
        fs.readFileSync(tsFile, 'utf8'),
        staleTsMarker,
        '--check must NOT overwrite stale TS file'
      );

      // Repair via syncFoundation
      syncFoundation({ rootDir: tmpDir, silent: true });
      assert.strictEqual(checkFoundation({ rootDir: tmpDir, silent: true }).fresh, true);

      // Case B: stale Dart generated file and missing Dart core file
      const staleDartContent = fs.readFileSync(dartFile, 'utf8') + '\n// drift';
      fs.writeFileSync(dartFile, staleDartContent, 'utf8');
      fs.rmSync(dartCoreFile);

      const cliResDart = spawnSync(
        process.execPath,
        [path.join(REPO_ROOT, 'scripts/sync_foundation.mjs'), '--check', '--root', tmpDir],
        { encoding: 'utf8' }
      );
      assert.notStrictEqual(cliResDart.status, 0, 'CLI --check must exit non-zero for stale/missing Dart files');
      assert.match(cliResDart.stderr, /shared_foundation\.dart/);
      assert.match(cliResDart.stderr, /shared_foundation_core\.dart \(missing\)/);
      assert.strictEqual(
        fs.readFileSync(dartFile, 'utf8'),
        staleDartContent,
        '--check must NOT overwrite stale Dart file'
      );
      assert.strictEqual(
        fs.existsSync(dartCoreFile),
        false,
        '--check must NOT recreate missing generated file'
      );
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it('3. All 5 canonical Shared Foundation JSON schemas validate cleanly and reject malformed specs with actionable errors', () => {
    const validRules = readRepoJson('shared_foundation/business_rules.json');
    const validContracts = readRepoJson('shared_foundation/schema_contracts.json');
    const validSeed = readRepoJson('shared_foundation/canonical_seed_database.json');
    const validVectors = readRepoJson('shared_foundation/calendar_test_vectors.json');

    assert.ok(validateBusinessRules(validRules));
    assert.ok(validateSchemaContracts(validContracts));
    assert.ok(validateCanonicalSeedDatabase(validSeed));
    assert.ok(validateCalendarTestVectors(validVectors));

    // Malformed business_rules.json
    const badRules = structuredClone(validRules);
    badRules.finance.currencyCode = 'USD';
    assert.throws(
      () => validateBusinessRules(badRules),
      /business_rules\.json field "finance\.currencyCode"/
    );

    const badTaskWeights = structuredClone(validRules);
    badTaskWeights.tasks.priorityWeights.low = 99;
    assert.throws(
      () => validateBusinessRules(badTaskWeights),
      /business_rules\.json field "tasks\.priorityWeights"/
    );

    // Malformed schema_contracts.json
    const badSchemaType = structuredClone(validContracts);
    badSchemaType.entities.Task.fields.title.type = 'float64';
    assert.throws(
      () => validateSchemaContracts(badSchemaType),
      /schema_contracts\.json field "entities\.Task\.fields\.title\.type"/
    );

    const badSchemaDefault = structuredClone(validContracts);
    badSchemaDefault.entities.Task.fields.status.default = 'archived';
    assert.throws(
      () => validateSchemaContracts(badSchemaDefault),
      /schema_contracts\.json field "entities\.Task\.fields\.status\.default"/
    );

    // Malformed canonical_seed_database.json
    const badSeedAccounts = structuredClone(validSeed);
    badSeedAccounts.accounts = [{ id: 'acc-fake' }];
    assert.throws(
      () => validateCanonicalSeedDatabase(badSeedAccounts),
      /canonical_seed_database\.json field "accounts"/
    );

    const badSeedCatColor = structuredClone(validSeed);
    badSeedCatColor.categories[0].colorHex = 'red';
    assert.throws(
      () => validateCanonicalSeedDatabase(badSeedCatColor),
      /canonical_seed_database\.json field "categories\[0\]\.colorHex"/
    );

    // Malformed calendar_test_vectors.json
    const badVectorDate = structuredClone(validVectors);
    badVectorDate.conversionVectors[0].gregorian = '2025-02-29';
    assert.throws(
      () => validateCalendarTestVectors(badVectorDate),
      /calendar_test_vectors\.json field "conversionVectors\[0\]\.gregorian"/
    );

    const badEthLeap = structuredClone(validVectors);
    badEthLeap.conversionVectors[0].ethiopian = { year: 2016, month: 13, day: 6 };
    assert.throws(
      () => validateCalendarTestVectors(badEthLeap),
      /calendar_test_vectors\.json field "conversionVectors\[0\]\.ethiopian\.day"/
    );
  });

  it('4. ADR-007 contract non-regression rejects undocumented removals across tokens, schemas, rules, and control accounts', () => {
    // 4a. Undocumented removal of protected schema field
    const tmpSchemaDir = createIsolatedFoundationRoot();
    try {
      const schemaPath = path.join(tmpSchemaDir, 'shared_foundation/schema_contracts.json');
      const contracts = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
      delete contracts.entities.Account.fields.subType;
      fs.writeFileSync(schemaPath, JSON.stringify(contracts, null, 2), 'utf8');

      assert.throws(
        () => checkFoundation({ rootDir: tmpSchemaDir, silent: true }),
        /ADR-007 contract non-regression[\s\S]*schema_contracts\.entities\.Account\.fields\.subType/
      );
    } finally {
      fs.rmSync(tmpSchemaDir, { recursive: true, force: true });
    }

    // 4b. Undocumented weakening of required field or enum value removal
    const tmpEnumDir = createIsolatedFoundationRoot();
    try {
      const schemaPath = path.join(tmpEnumDir, 'shared_foundation/schema_contracts.json');
      const contracts = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
      contracts.entities.Transaction.fields.type.enum = ['income', 'expense']; // removed 'transfer'
      fs.writeFileSync(schemaPath, JSON.stringify(contracts, null, 2), 'utf8');

      assert.throws(
        () => checkFoundation({ rootDir: tmpEnumDir, silent: true }),
        /schema_contracts\.entities\.Transaction\.fields\.type\.enum\.transfer/
      );
    } finally {
      fs.rmSync(tmpEnumDir, { recursive: true, force: true });
    }

    // 4c. Undocumented design token removal
    const tmpTokenDir = createIsolatedFoundationRoot();
    try {
      const tokensPath = path.join(tmpTokenDir, 'shared_foundation/design_tokens.json');
      const tokens = JSON.parse(fs.readFileSync(tokensPath, 'utf8'));
      delete tokens.spacing.md;
      fs.writeFileSync(tokensPath, JSON.stringify(tokens, null, 2), 'utf8');

      assert.throws(
        () => checkFoundation({ rootDir: tmpTokenDir, silent: true }),
        /Missing required token "spacing\.md"/
      );
    } finally {
      fs.rmSync(tmpTokenDir, { recursive: true, force: true });
    }

    // 4d. Undocumented Dart SystemControlAccounts drift
    const tmpEngineDir = createIsolatedFoundationRoot();
    try {
      const enginePath = path.join(
        tmpEngineDir,
        'flutter_app/lib/domain/finance/double_entry_engine.dart'
      );
      const source = fs.readFileSync(enginePath, 'utf8').replace("'acc-sys-equity'", "'acc-sys-changed'");
      fs.writeFileSync(enginePath, source, 'utf8');

      assert.throws(
        () => checkFoundation({ rootDir: tmpEngineDir, silent: true }),
        /system_control_account_ids\.equity/
      );
    } finally {
      fs.rmSync(tmpEngineDir, { recursive: true, force: true });
    }

    // 4e. Undocumented KnownSeedIds removal across TS & Dart
    const tmpSeedIdDir = createIsolatedFoundationRoot();
    try {
      const baselinePath = path.join(tmpSeedIdDir, 'scripts/foundation_compatibility_baseline.json');
      const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'));
      baseline.protectedKnownSeedIds.accounts.push('acc-retired-seed');
      fs.writeFileSync(baselinePath, JSON.stringify(baseline, null, 2), 'utf8');

      assert.throws(
        () => checkFoundation({ rootDir: tmpSeedIdDir, silent: true }),
        /known_seed_ids\.accounts\.acc-retired-seed/
      );
    } finally {
      fs.rmSync(tmpSeedIdDir, { recursive: true, force: true });
    }
  });

  it('5. ADR-007 accepts explicitly documented intentional removals with valid accepted ADR reference, justification, migration strategy, consumers, and tests', () => {
    const tmpDir = createIsolatedFoundationRoot();
    try {
      const schemaPath = path.join(tmpDir, 'shared_foundation/schema_contracts.json');
      const contracts = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
      delete contracts.entities.Task.fields.milestoneId;
      fs.writeFileSync(schemaPath, JSON.stringify(contracts, null, 2), 'utf8');

      // Copy existing consumer/test paths referenced by the test intentionalRemovals entry
      for (const rel of [
        'flutter_app/lib/data/database/tables.dart',
        'src/domain/sharedFoundationParity.test.ts',
      ]) {
        const dest = path.join(tmpDir, rel);
        fs.mkdirSync(path.dirname(dest), { recursive: true });
        fs.copyFileSync(path.join(REPO_ROOT, rel), dest);
      }

      const baselinePath = path.join(tmpDir, 'scripts/foundation_compatibility_baseline.json');
      const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'));

      // First verify non-existent ADR doc path fails closed
      baseline.intentionalRemovals = [
        {
          target: 'schema_contracts.entities.Task.fields.milestoneId',
          adrOrDoc: 'docs/architecture/decisions/ADR-999-missing.md',
          justification: 'Retiring unused Task.milestoneId in coordinated migration.',
          migrationStrategy: 'Upcaster drops milestoneId after v8 migration.',
          coordinatedConsumers: ['src/domain/sharedFoundation.ts', 'flutter_app/lib/data/database/tables.dart'],
          verificationTests: ['src/domain/sharedFoundationParity.test.ts'],
          approvedBy: 'Test Approval',
        },
      ];
      fs.writeFileSync(baselinePath, JSON.stringify(baseline, null, 2), 'utf8');
      assert.throws(
        () => syncFoundation({ rootDir: tmpDir, silent: true }),
        /does not resolve to an existing file/
      );

      // Now create an accepted ADR with required sections under tmpDir -> syncFoundation & checkFoundation succeed
      const testAdrRel = 'docs/architecture/decisions/ADR-008-test-retirement.md';
      const testAdrAbs = path.join(tmpDir, testAdrRel);
      fs.writeFileSync(
        testAdrAbs,
        `# ADR-008: Retire Task.milestoneId

- **Status:** \`accepted\`

## Justification
Task milestones were superseded by direct project references.

## Migration Strategy
Keep nullable upcaster defaults during import of pre-v8 snapshots.

## Affected Consumers
- \`src/domain/sharedFoundation.ts\`
- \`flutter_app/lib/data/database/tables.dart\`
`,
        'utf8'
      );
      baseline.intentionalRemovals[0].adrOrDoc = testAdrRel;
      fs.writeFileSync(baselinePath, JSON.stringify(baseline, null, 2), 'utf8');

      syncFoundation({ rootDir: tmpDir, silent: true });
      const checkRes = checkFoundation({ rootDir: tmpDir, silent: true });
      assert.strictEqual(checkRes.fresh, true);
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it('6. Schema-version guard aligns AppDatabase.schemaVersion with schema_contracts.json while preserving seed v5 & bridge v5', () => {
    const tmpDir = createIsolatedFoundationRoot();
    try {
      // Confirm canonical_seed_database.json=5 & schema_contracts.json.version="2.0.0" remain valid alongside schemaVersion=13
      const seed = JSON.parse(
        fs.readFileSync(path.join(tmpDir, 'shared_foundation/canonical_seed_database.json'), 'utf8')
      );
      const contracts = JSON.parse(
        fs.readFileSync(path.join(tmpDir, 'shared_foundation/schema_contracts.json'), 'utf8')
      );
      assert.strictEqual(seed.schemaVersion, 5);
      assert.strictEqual(contracts.schemaVersion, 13);
      assert.strictEqual(contracts.version, '2.0.0');
      assert.strictEqual(checkFoundation({ rootDir: tmpDir, silent: true }).fresh, true);

      // Mutate AppDatabase.schemaVersion to 9 -> must fail clearly
      const appDbPath = path.join(tmpDir, 'flutter_app/lib/data/database/app_database.dart');
      const appDbSource = fs
        .readFileSync(appDbPath, 'utf8')
        .replace('int get schemaVersion => 13;', 'int get schemaVersion => 9;');
      fs.writeFileSync(appDbPath, appDbSource, 'utf8');

      assert.throws(
        () => checkFoundation({ rootDir: tmpDir, silent: true }),
        /Schema version mismatch: shared_foundation\/schema_contracts\.json declares schemaVersion=13, while flutter_app\/lib\/data\/database\/app_database\.dart declares schemaVersion=9/
      );
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});
