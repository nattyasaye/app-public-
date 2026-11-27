import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  checkArchitectureBoundaries,
  detectForbiddenBrowserGlobals,
  extractDartDirectives,
  extractTypeScriptImports,
  loadAndValidateAllowlist,
  // @ts-ignore - ESM governance script
} from '../../scripts/check_architecture_boundaries.mjs';
import {
  checkMigrationCompatibility,
  // @ts-ignore - ESM governance script
} from '../../scripts/check_migration_compatibility.mjs';
import {
  checkFoundation,
  compareCompatibilityBaselines,
  resolveBaselineGitComparison,
  syncFoundation,
  validateAuthorizedAdrDocument,
  // @ts-ignore - ESM governance script
} from '../../scripts/sync_foundation.mjs';

const REPO_ROOT = process.cwd();

function writeFile(rootDir: string, relPath: string, content: string): void {
  const abs = path.join(rootDir, relPath);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, content, 'utf8');
}

function copyRepoFile(srcRoot: string, destRoot: string, relPath: string): void {
  const src = path.join(srcRoot, relPath);
  const dest = path.join(destRoot, relPath);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}

function runGitCmd(cwd: string, args: string[]): string {
  return execFileSync('git', args, {
    cwd,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

function createMinimalArchitectureRepo({ withAllowlist = false } = {}): string {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'daywell-arch-'));
  writeFile(
    tmpDir,
    'scripts/architecture_allowlist.json',
    JSON.stringify(
      {
        version: '1.0.0',
        exceptions: withAllowlist
          ? [
              {
                source: 'flutter_app/lib/ui/app_state.dart',
                target: 'flutter_app/lib/data/database/app_database.dart',
                rule: 'flutter-ui-no-data',
                responsibleLayer: 'presentation-composition-root',
                reason: 'AppStateManager wiring',
                adrOrDoc: 'docs/architecture/module-boundaries.md',
              },
            ]
          : [],
      },
      null,
      2
    )
  );
  writeFile(tmpDir, 'docs/architecture/module-boundaries.md', '# Module Boundaries\n');
  writeFile(tmpDir, 'flutter_app/pubspec.yaml', 'name: personal_management_app\n');
  return tmpDir;
}

function createMigrationTestRepo(): string {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'daywell-migr-'));
  for (const relPath of [
    'scripts/migration_compatibility_baseline.json',
    'flutter_app/lib/data/database/app_database.dart',
    'flutter_app/lib/data/database/v6_ledger_migrator.dart',
    'flutter_app/lib/data/database/v7_ledger_hardener.dart',
  ]) {
    copyRepoFile(REPO_ROOT, tmpDir, relPath);
  }
  return tmpDir;
}

function createGitFoundationTestRepo(): string {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'daywell-git-base-'));
  for (const relPath of [
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
  ]) {
    copyRepoFile(REPO_ROOT, tmpDir, relPath);
  }
  runGitCmd(tmpDir, ['init']);
  runGitCmd(tmpDir, ['config', 'user.email', 'test@daywell.local']);
  runGitCmd(tmpDir, ['config', 'user.name', 'Daywell Test']);
  runGitCmd(tmpDir, ['add', '.']);
  runGitCmd(tmpDir, ['commit', '-m', 'Base governance snapshot']);
  return tmpDir;
}

describe('GOVERNANCE STAGE 3.3: ARCHITECTURE BOUNDARIES, MIGRATION COMPATIBILITY & CI BASELINE GUARD', () => {
  it('1. Live repository passes architecture boundary, migration compatibility, and foundation checks', () => {
    const archRes = checkArchitectureBoundaries({ rootDir: REPO_ROOT, silent: true });
    assert.strictEqual(archRes.passed, true);
    assert.ok(archRes.checkedDartFiles > 50);
    assert.ok(archRes.checkedTsFiles > 10);

    const migRes = checkMigrationCompatibility({ rootDir: REPO_ROOT, silent: true });
    assert.strictEqual(migRes.passed, true);
    assert.strictEqual(migRes.schemaVersion, 13);
    assert.deepStrictEqual(migRes.upgradeSteps, [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]);
    assert.strictEqual(migRes.downgradeMode, 'on-upgrade-explicit-throw-fail-closed');

    const foundRes = checkFoundation({ rootDir: REPO_ROOT, silent: true });
    assert.strictEqual(foundRes.fresh, true);
  });

  it('2. TS and Dart directive parsers ignore comments and string literals without false positives while catching multiline/re-export/package directives', () => {
    const tsSample = `
      // import { Fake } from '../data/localDatabase';
      /*
        import * as Hidden from 'react';
        export { Secret } from '../data/localDatabase';
      */
      const doc = "import { InString } from '../data/localDatabase';";
      const tmpl = \`header \${"import('../components/App')"} import { AlsoFake } from '../services/x';\`;
      import {
        Alpha,
        Beta,
      } from '../domain/alpha';
      export type { Gamma } from './gamma';
      export * from './delta';
      const mod = () => import('../data/dynamicTarget');
      const cjs = require('../services/legacy');
    `;
    const tsParsed = extractTypeScriptImports(tsSample);
    assert.deepStrictEqual(
      tsParsed.imports.map((i: any) => `${i.kind}:${i.specifier}`),
      [
        'static-import:../domain/alpha',
        're-export:./gamma',
        're-export:./delta',
        'dynamic-import:../data/dynamicTarget',
        'require:../services/legacy',
      ]
    );

    const dartSample = `
      // import 'package:drift/drift.dart';
      /* outer /* nested import 'package:flutter/material.dart'; */ still comment */
      const fake = r'''import '../data/database/app_database.dart';''';
      const fake2 = "export 'package:personal_management_app/ui/home.dart';";
      import
        'package:personal_management_app/domain/models.dart'
        if (dart.library.io) '../data/io_impl.dart';
      export 'src/part_a.dart';
      part 'src/part_b.dart';
    `;
    const dartParsed = extractDartDirectives(dartSample);
    assert.deepStrictEqual(
      dartParsed.directives.map((d: any) => `${d.kind}:${d.specifier}`),
      [
        'import:package:personal_management_app/domain/models.dart',
        'import:../data/io_impl.dart',
        'export:src/part_a.dart',
        'part:src/part_b.dart',
      ]
    );
  });

  it('3. Architecture checker catches forbidden Flutter & Web boundary crossings, pubspec leaks, and domain browser globals while avoiding comment/string/member false positives', () => {
    // 3a. Valid layers + comments/strings containing fake imports pass cleanly
    const cleanDir = createMinimalArchitectureRepo({ withAllowlist: true });
    try {
      writeFile(
        cleanDir,
        'flutter_app/lib/domain/entity.dart',
        `
        // import 'package:drift/drift.dart';
        const sample = "import '../data/database/app_database.dart';";
        class Entity {}
        `
      );
      writeFile(
        cleanDir,
        'flutter_app/lib/ui/app_state.dart',
        `import 'package:personal_management_app/data/database/app_database.dart';`
      );
      writeFile(
        cleanDir,
        'src/domain/pureRule.ts',
        `
        // localStorage.getItem('x'); window.alert('hi');
        const info = "localStorage.setItem('a', 'b'); document.cookie";
        export interface Box { window?: string; document: string; }
        export function readWindow(box: Box): string | undefined {
          return box.window;
        }
        `
      );
      const res = checkArchitectureBoundaries({ rootDir: cleanDir, silent: true });
      assert.strictEqual(res.passed, true);
    } finally {
      fs.rmSync(cleanDir, { recursive: true, force: true });
    }

    // 3b. Flutter domain -> drift/data/UI via multiline package directive rejected
    const badFlutterDir = createMinimalArchitectureRepo();
    try {
      writeFile(
        badFlutterDir,
        'flutter_app/lib/domain/bad_rule.dart',
        `
        import
          'package:personal_management_app/data/database/app_database.dart';
        `
      );
      assert.throws(
        () => checkArchitectureBoundaries({ rootDir: badFlutterDir, silent: true }),
        /flutter-domain-purity/
      );
    } finally {
      fs.rmSync(badFlutterDir, { recursive: true, force: true });
    }

    // 3c. Unallowlisted Flutter UI -> data rejected
    const badUiDir = createMinimalArchitectureRepo({ withAllowlist: true });
    try {
      writeFile(
        badUiDir,
        'flutter_app/lib/ui/finance/ledger_screen.dart',
        `import '../../data/database/app_database.dart';`
      );
      assert.throws(
        () => checkArchitectureBoundaries({ rootDir: badUiDir, silent: true }),
        /flutter-ui-no-data/
      );
    } finally {
      fs.rmSync(badUiDir, { recursive: true, force: true });
    }

    // 3d. Web domain -> src/data re-export & direct browser globals caught
    const badWebDir = createMinimalArchitectureRepo();
    try {
      writeFile(
        badWebDir,
        'src/domain/leaky.ts',
        `
        export * from '../data/localDatabase';
        export function getSaved(): string | null {
          return localStorage.getItem('k') ?? window.name ?? document.title;
        }
        `
      );
      assert.throws(
        () => checkArchitectureBoundaries({ rootDir: badWebDir, silent: true }),
        /web-domain-purity[\s\S]*web-domain-no-browser-globals/
      );

      const { tokens } = extractTypeScriptImports(
        `
        // window.location
        const s = "localStorage";
        const ok = cfg.window;
        const prop = { document: 1 };
        const bad = localStorage.getItem('x');
        `
      );
      const globals = detectForbiddenBrowserGlobals(tokens);
      assert.deepStrictEqual(
        globals.map((g: any) => g.identifier),
        ['localStorage']
      );
    } finally {
      fs.rmSync(badWebDir, { recursive: true, force: true });
    }

    // 3e. Flutter pubspec referencing src/ fails
    const badPubspecDir = createMinimalArchitectureRepo();
    try {
      writeFile(
        badPubspecDir,
        'flutter_app/pubspec.yaml',
        `
        name: personal_management_app
        flutter:
          assets:
            - ../src/data/mock.json
        `
      );
      assert.throws(
        () => checkArchitectureBoundaries({ rootDir: badPubspecDir, silent: true }),
        /flutter-cross-platform-isolation/
      );
    } finally {
      fs.rmSync(badPubspecDir, { recursive: true, force: true });
    }

    // 3f. Broad wildcard allowlist entry fails closed
    const badAllowDir = createMinimalArchitectureRepo();
    try {
      writeFile(
        badAllowDir,
        'scripts/architecture_allowlist.json',
        JSON.stringify({
          exceptions: [
            {
              source: 'flutter_app/lib/ui/*',
              target: 'flutter_app/lib/data/*',
              rule: 'flutter-ui-no-data',
              responsibleLayer: 'presentation',
              reason: 'Wildcard attempt',
              adrOrDoc: 'docs/architecture/module-boundaries.md',
            },
          ],
        })
      );
      assert.throws(
        () => loadAndValidateAllowlist(badAllowDir),
        /Overly broad or wildcard exception rejected/
      );
    } finally {
      fs.rmSync(badAllowDir, { recursive: true, force: true });
    }
  });

  it('4. Migration compatibility checker rejects version decreases, missing/reordered/renumbered steps, destructive fallbacks, silent downgrades, and missing next-step upgrades', () => {
    // 4a. Decreased schemaVersion -> fail
    const decDir = createMigrationTestRepo();
    try {
      const dbPath = path.join(decDir, 'flutter_app/lib/data/database/app_database.dart');
      fs.writeFileSync(
        dbPath,
        fs.readFileSync(dbPath, 'utf8').replace('int get schemaVersion => 13;', 'int get schemaVersion => 12;'),
        'utf8'
      );
      assert.throws(
        () => checkMigrationCompatibility({ rootDir: decDir, silent: true }),
        /below minimumSchemaVersion=13/
      );
    } finally {
      fs.rmSync(decDir, { recursive: true, force: true });
    }

    // 4b. Removed historical branch `from < 5` -> fail
    const missingBranchDir = createMigrationTestRepo();
    try {
      const dbPath = path.join(missingBranchDir, 'flutter_app/lib/data/database/app_database.dart');
      const src = fs.readFileSync(dbPath, 'utf8');
      const startIdx = src.indexOf('        if (from < 5) {');
      const endIdx = src.indexOf('        if (from < 6) {');
      assert.ok(startIdx !== -1 && endIdx > startIdx);
      fs.writeFileSync(dbPath, src.slice(0, startIdx) + src.slice(endIdx), 'utf8');
      assert.throws(
        () => checkMigrationCompatibility({ rootDir: missingBranchDir, silent: true }),
        /Missing released schema migration branch "if \(from < 5\)"/
      );
    } finally {
      fs.rmSync(missingBranchDir, { recursive: true, force: true });
    }

    // 4c. Out-of-order branches (`from < 3` reordered after `from < 4` or duplicated) -> fail
    const orderDir = createMigrationTestRepo();
    try {
      const dbPath = path.join(orderDir, 'flutter_app/lib/data/database/app_database.dart');
      const src = fs
        .readFileSync(dbPath, 'utf8')
        .replace('if (from < 2) {', 'if (from < 4) {\n        }\n        if (from < 2) {');
      fs.writeFileSync(dbPath, src, 'utf8');
      assert.throws(
        () => checkMigrationCompatibility({ rootDir: orderDir, silent: true }),
        /Out-of-order migration branch/
      );
    } finally {
      fs.rmSync(orderDir, { recursive: true, force: true });
    }

    // 4d. Bumping schemaVersion => 14 without `if (from < 14)` fails, and adding `if (from < 14)` passes
    const bumpDir = createMigrationTestRepo();
    try {
      const dbPath = path.join(bumpDir, 'flutter_app/lib/data/database/app_database.dart');
      const orig = fs.readFileSync(dbPath, 'utf8');
      fs.writeFileSync(
        dbPath,
        orig.replace('int get schemaVersion => 13;', 'int get schemaVersion => 14;'),
        'utf8'
      );
      assert.throws(
        () => checkMigrationCompatibility({ rootDir: bumpDir, silent: true }),
        /missing required sequential upgrade branch "if \(from < 14\)"/
      );

      fs.writeFileSync(
        dbPath,
        orig
          .replace('int get schemaVersion => 13;', 'int get schemaVersion => 14;')
          .replace(
            '        }\n      },\n      beforeOpen: (details) async {',
            '        }\n        if (from < 14) {\n          await customStatement("SELECT 1;");\n        }\n      },\n      beforeOpen: (details) async {'
          ),
        'utf8'
      );
      const res = checkMigrationCompatibility({ rootDir: bumpDir, silent: true });
      assert.strictEqual(res.schemaVersion, 14);
      assert.deepStrictEqual(res.upgradeSteps, [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]);
    } finally {
      fs.rmSync(bumpDir, { recursive: true, force: true });
    }

    // 4e. fallbackToDestructiveMigration rejected in code, ignored in comments
    const destructiveDir = createMigrationTestRepo();
    try {
      const dbPath = path.join(destructiveDir, 'flutter_app/lib/data/database/app_database.dart');
      const orig = fs.readFileSync(dbPath, 'utf8');
      fs.writeFileSync(
        dbPath,
        `// fallbackToDestructiveMigration mentioned only in comment\n${orig}`,
        'utf8'
      );
      assert.strictEqual(checkMigrationCompatibility({ rootDir: destructiveDir, silent: true }).passed, true);

      fs.writeFileSync(
        dbPath,
        orig.replace('beforeOpen: (details) async {', 'fallbackToDestructiveMigration: true,\n      beforeOpen: (details) async {'),
        'utf8'
      );
      assert.throws(
        () => checkMigrationCompatibility({ rootDir: destructiveDir, silent: true }),
        /forbidden by ADR-007/
      );
    } finally {
      fs.rmSync(destructiveDir, { recursive: true, force: true });
    }

    // 4f. Removing, silencing, or misordering `if (from > to)` in onUpgrade (or adding nonexistent onDowngrade) fails closed
    const dgDir = createMigrationTestRepo();
    try {
      const dbPath = path.join(dgDir, 'flutter_app/lib/data/database/app_database.dart');
      const orig = fs.readFileSync(dbPath, 'utf8');

      // Removing `if (from > to)` -> fail
      const withoutGuard = orig.replace(
        /if\s*\(\s*from\s*>\s*to\s*\)\s*\{[\s\S]*?\}\s*(?=if\s*\(\s*from\s*<\s*2\s*\))/,
        ''
      );
      fs.writeFileSync(dbPath, withoutGuard, 'utf8');
      assert.throws(
        () => checkMigrationCompatibility({ rootDir: dgDir, silent: true }),
        /must begin with an explicit fail-closed "if \(from > to\)/
      );

      // Silent `return;` in `if (from > to)` -> fail
      const silentGuard = orig.replace(
        /if\s*\(\s*from\s*>\s*to\s*\)\s*\{[\s\S]*?\}\s*(?=if\s*\(\s*from\s*<\s*2\s*\))/,
        'if (from > to) {\n          return;\n        }\n        '
      );
      fs.writeFileSync(dbPath, silentGuard, 'utf8');
      assert.throws(
        () => checkMigrationCompatibility({ rootDir: dgDir, silent: true }),
        /must fail closed with an explicit throw/
      );

      // Reordering `if (from > to)` after `if (from < 2)` -> fail
      const misorderedGuard = withoutGuard.replace(
        'if (from < 3) {',
        'if (from > to) {\n          throw StateError("Too late");\n        }\n        if (from < 3) {'
      );
      fs.writeFileSync(dbPath, misorderedGuard, 'utf8');
      assert.throws(
        () => checkMigrationCompatibility({ rootDir: dgDir, silent: true }),
        /must appear before all "if \(from < N\)" branches/
      );

      // Nonexistent `onDowngrade` callback on Drift MigrationStrategy -> fail
      fs.writeFileSync(
        dbPath,
        orig.replace(
          'beforeOpen: (details) async {',
          'onDowngrade: (m, from, to) async {\n        throw StateError("Unsupported");\n      },\n      beforeOpen: (details) async {'
        ),
        'utf8'
      );
      assert.throws(
        () => checkMigrationCompatibility({ rootDir: dgDir, silent: true }),
        /does not support an onDowngrade callback/
      );

      // Restoring live guarded source passes with explicit mode
      fs.writeFileSync(dbPath, orig, 'utf8');
      const res = checkMigrationCompatibility({ rootDir: dgDir, silent: true });
      assert.strictEqual(res.downgradeMode, 'on-upgrade-explicit-throw-fail-closed');
    } finally {
      fs.rmSync(dgDir, { recursive: true, force: true });
    }
  });

  it('5. Git base compatibility diff allows unchanged or additive baselines while blocking unauthorized baseline deletions or weakenings', () => {
    const gitDir = createGitFoundationTestRepo();
    try {
      // 5a. Additive change in working tree against base commit HEAD -> passes
      const schemaPath = path.join(gitDir, 'shared_foundation/schema_contracts.json');
      const contracts = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
      contracts.entities.Task.fields.stage33Note = { type: 'string', required: false };
      fs.writeFileSync(schemaPath, JSON.stringify(contracts, null, 2), 'utf8');

      const baselinePath = path.join(gitDir, 'scripts/foundation_compatibility_baseline.json');
      const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'));
      baseline.protectedSchemaContracts.Task.fields.stage33Note = { type: 'string' };
      fs.writeFileSync(baselinePath, JSON.stringify(baseline, null, 2), 'utf8');
      syncFoundation({ rootDir: gitDir, baseRev: 'HEAD', requireGitBase: true, silent: true });
      assert.strictEqual(
        checkFoundation({ rootDir: gitDir, baseRev: 'HEAD', requireGitBase: true, silent: true }).baselineDiffStatus,
        'compared'
      );

      // 5b. Removing a protected field from BOTH schema_contracts.json AND baseline fails against base commit HEAD
      const regressedContracts = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
      delete regressedContracts.entities.Task.fields.milestoneId;
      fs.writeFileSync(schemaPath, JSON.stringify(regressedContracts, null, 2), 'utf8');

      const regressedBaseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'));
      delete regressedBaseline.protectedSchemaContracts.Task.fields.milestoneId;
      fs.writeFileSync(baselinePath, JSON.stringify(regressedBaseline, null, 2), 'utf8');

      assert.throws(
        () => checkFoundation({ rootDir: gitDir, baseRev: 'HEAD', requireGitBase: true, silent: true }),
        /ADR-007 compatibility baseline modification\/removal blocked against base revision[\s\S]*schema_contracts\.entities\.Task\.fields\.milestoneId/
      );

      // 5c. Weakening required:true -> false in baseline blocked even without removal
      const weakenedBaseline = JSON.parse(JSON.stringify(baseline));
      weakenedBaseline.protectedSchemaContracts.Note.fields.title.required = false;
      assert.throws(
        () => compareCompatibilityBaselines(JSON.parse(runGitCmd(gitDir, ['show', 'HEAD:scripts/foundation_compatibility_baseline.json'])), weakenedBaseline),
        /schema_contracts\.entities\.Note\.fields\.title\.required/
      );
    } finally {
      fs.rmSync(gitDir, { recursive: true, force: true });
    }
  });

  it('6. Authorizing ADRs require explicit accepted status, Justification, Migration Strategy, Affected Consumers, and existing consumer/test files', () => {
    const gitDir = createGitFoundationTestRepo();
    try {
      const schemaPath = path.join(gitDir, 'shared_foundation/schema_contracts.json');
      const contracts = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
      delete contracts.entities.Task.fields.milestoneId;
      fs.writeFileSync(schemaPath, JSON.stringify(contracts, null, 2), 'utf8');

      const baselinePath = path.join(gitDir, 'scripts/foundation_compatibility_baseline.json');
      const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'));
      delete baseline.protectedSchemaContracts.Task.fields.milestoneId;

      const adrRel = 'docs/architecture/decisions/ADR-009-retire-milestone.md';
      baseline.intentionalRemovals = [
        {
          target: 'schema_contracts.entities.Task.fields.milestoneId',
          adrOrDoc: adrRel,
          justification: 'Retire legacy milestoneId field.',
          migrationStrategy: 'Upcast pre-v8 snapshots cleanly.',
          coordinatedConsumers: ['src/domain/sharedFoundation.ts', 'flutter_app/lib/data/database/tables.dart'],
          verificationTests: ['src/domain/sharedFoundationParity.test.ts'],
          approvedBy: 'Architecture Governance Approval',
        },
      ];
      fs.writeFileSync(baselinePath, JSON.stringify(baseline, null, 2), 'utf8');

      // Case A: proposed ADR -> fail
      writeFile(
        gitDir,
        adrRel,
        `# ADR-009\n\n- **Status:** \`proposed\`\n\n## Justification\nYes\n\n## Migration Strategy\nUpcast\n\n## Affected Consumers\n- ts\n`
      );
      assert.throws(
        () => validateAuthorizedAdrDocument(adrRel, gitDir),
        /is not accepted \(found status="proposed"\)/
      );

      // Case B: superseded ADR -> fail
      writeFile(
        gitDir,
        adrRel,
        `# ADR-009\n\n- **Status:** \`superseded\`\n\n## Justification\nYes\n\n## Migration Strategy\nUpcast\n\n## Affected Consumers\n- ts\n`
      );
      assert.throws(
        () => validateAuthorizedAdrDocument(adrRel, gitDir),
        /is not accepted \(found status="superseded"\)/
      );

      // Case C: accepted ADR missing Migration Strategy section -> fail
      writeFile(
        gitDir,
        adrRel,
        `# ADR-009\n\n- **Status:** \`accepted\`\n\n## Justification\nYes\n\n## Affected Consumers\n- ts\n`
      );
      assert.throws(
        () => validateAuthorizedAdrDocument(adrRel, gitDir),
        /must contain a non-empty "## Migration Strategy" section/
      );

      // Case D: non-ADR markdown path -> fail
      assert.throws(
        () => validateAuthorizedAdrDocument('docs/architecture/shared-foundation.md', gitDir),
        /must reference an ADR markdown file under docs\/architecture\/decisions\/ADR-\*\.md/
      );

      // Case E: complete accepted ADR passes + checkFoundation passes against Git base HEAD!
      writeFile(
        gitDir,
        adrRel,
        `# ADR-009\n\n- **Status:** \`accepted\`\n\n## Justification\nMilestone links migrated.\n\n## Migration Strategy\nUpcaster strips field safely.\n\n## Affected Consumers\n- src/domain/sharedFoundation.ts\n- flutter_app/lib/data/database/tables.dart\n`
      );
      syncFoundation({ rootDir: gitDir, baseRev: 'HEAD', requireGitBase: true, silent: true });
      const passed = checkFoundation({
        rootDir: gitDir,
        baseRev: 'HEAD',
        requireGitBase: true,
        silent: true,
      });
      assert.strictEqual(passed.fresh, true);
      assert.strictEqual(passed.baselineDiffStatus, 'compared');

      // Case F: non-existent verificationTests file fails closed
      baseline.intentionalRemovals[0].verificationTests = ['src/domain/nonExistent.test.ts'];
      fs.writeFileSync(baselinePath, JSON.stringify(baseline, null, 2), 'utf8');
      assert.throws(
        () => checkFoundation({ rootDir: gitDir, baseRev: 'HEAD', requireGitBase: true, silent: true }),
        /verificationTests.*does not resolve to an existing file/
      );
    } finally {
      fs.rmSync(gitDir, { recursive: true, force: true });
    }
  });

  it('7. CI Git base resolution fails closed when base revision is unavailable or caller attempts --base-rev override', () => {
    const gitDir = createGitFoundationTestRepo();
    const tmpEventDir = fs.mkdtempSync(path.join(os.tmpdir(), 'daywell-ci-event-'));
    try {
      const baseSha = runGitCmd(gitDir, ['rev-parse', 'HEAD']);
      // Add second commit so push `before` differs from `HEAD`
      const readmePath = path.join(gitDir, 'CI_MARKER.txt');
      fs.writeFileSync(readmePath, 'second commit\n', 'utf8');
      runGitCmd(gitDir, ['add', 'CI_MARKER.txt']);
      runGitCmd(gitDir, ['commit', '-m', 'Second commit']);
      const headSha = runGitCmd(gitDir, ['rev-parse', 'HEAD']);

      const prEventFile = path.join(tmpEventDir, 'pr_event.json');
      fs.writeFileSync(
        prEventFile,
        JSON.stringify({ pull_request: { base: { sha: baseSha } } }),
        'utf8'
      );

      // 7a. Pull request event in CI resolves baseSha and passes
      const prCli = spawnSync(
        process.execPath,
        [path.join(REPO_ROOT, 'scripts/sync_foundation.mjs'), '--check', '--ci', '--root', gitDir],
        {
          encoding: 'utf8',
          env: {
            ...process.env,
            GITHUB_ACTIONS: 'true',
            GITHUB_EVENT_NAME: 'pull_request',
            GITHUB_EVENT_PATH: prEventFile,
          },
        }
      );
      assert.strictEqual(prCli.status, 0, `Expected exit 0 on valid PR CI event, stderr=${prCli.stderr}`);

      // 7b. Caller attempting to spoof `--base-rev HEAD` in CI fails closed!
      const overrideCli = spawnSync(
        process.execPath,
        [
          path.join(REPO_ROOT, 'scripts/sync_foundation.mjs'),
          '--check',
          '--ci',
          '--root',
          gitDir,
          '--base-rev',
          headSha,
        ],
        {
          encoding: 'utf8',
          env: {
            ...process.env,
            GITHUB_ACTIONS: 'true',
            GITHUB_EVENT_NAME: 'pull_request',
            GITHUB_EVENT_PATH: prEventFile,
          },
        }
      );
      assert.notStrictEqual(overrideCli.status, 0);
      assert.match(overrideCli.stderr, /cannot override CI event base revision/);

      // 7c. Missing/unreachable SHA in shallow CI checkout fails closed!
      const missingShaEventFile = path.join(tmpEventDir, 'missing_sha_event.json');
      fs.writeFileSync(
        missingShaEventFile,
        JSON.stringify({ pull_request: { base: { sha: 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef' } } }),
        'utf8'
      );
      const shallowCli = spawnSync(
        process.execPath,
        [path.join(REPO_ROOT, 'scripts/sync_foundation.mjs'), '--check', '--ci', '--root', gitDir],
        {
          encoding: 'utf8',
          env: {
            ...process.env,
            GITHUB_ACTIONS: 'true',
            GITHUB_EVENT_NAME: 'pull_request',
            GITHUB_EVENT_PATH: missingShaEventFile,
          },
        }
      );
      assert.notStrictEqual(shallowCli.status, 0);
      assert.match(shallowCli.stderr, /authoritative base revision .* is unavailable in Git history/);

      // 7d. Non-git directory with requireGitBase: true fails closed!
      const nonGitDir = fs.mkdtempSync(path.join(os.tmpdir(), 'daywell-no-git-'));
      try {
        assert.throws(
          () => resolveBaselineGitComparison({ rootDir: nonGitDir, requireGitBase: true }),
          /is not inside a Git repository/
        );
      } finally {
        fs.rmSync(nonGitDir, { recursive: true, force: true });
      }
    } finally {
      fs.rmSync(gitDir, { recursive: true, force: true });
      fs.rmSync(tmpEventDir, { recursive: true, force: true });
    }
  });
});
