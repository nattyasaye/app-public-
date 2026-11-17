#!/usr/bin/env node
import fs from 'fs';
import path from 'path';
import { fileURLToPath, pathToFileURL } from 'url';
import { tokenizeSource } from './check_architecture_boundaries.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const defaultRootDir = path.resolve(__dirname, '..');

function findMatchingBraceTokenIndex(tokens, openBraceIdx) {
  let depth = 0;
  for (let i = openBraceIdx; i < tokens.length; i += 1) {
    if (tokens[i].type === 'punct' && tokens[i].value === '{') {
      depth += 1;
    } else if (tokens[i].type === 'punct' && tokens[i].value === '}') {
      depth -= 1;
      if (depth === 0) {
        return i;
      }
    }
  }
  return -1;
}

function findMatchingParenTokenIndex(tokens, openParenIdx) {
  let depth = 0;
  for (let i = openParenIdx; i < tokens.length; i += 1) {
    if (tokens[i].type === 'punct' && tokens[i].value === '(') {
      depth += 1;
    } else if (tokens[i].type === 'punct' && tokens[i].value === ')') {
      depth -= 1;
      if (depth === 0) {
        return i;
      }
    }
  }
  return -1;
}

function tokensToComparableText(tokens) {
  let out = '';
  for (let i = 0; i < tokens.length; i += 1) {
    const cur = tokens[i];
    const prev = tokens[i - 1];
    if (
      prev &&
      cur.type === 'ident' &&
      (prev.type === 'ident' || prev.type === 'number')
    ) {
      out += ' ';
    }
    if (cur.type === 'string') {
      out += `'${cur.value}'`;
    } else {
      out += cur.value;
    }
  }
  return out;
}

function extractMigrationStrategyRange(tokens) {
  for (let i = 0; i <= tokens.length - 4; i += 1) {
    if (
      tokens[i].type === 'ident' &&
      tokens[i].value === 'MigrationStrategy' &&
      tokens[i + 1]?.type === 'ident' &&
      tokens[i + 1].value === 'get' &&
      tokens[i + 2]?.type === 'ident' &&
      tokens[i + 2].value === 'migration'
    ) {
      // Arrow form: MigrationStrategy get migration => MigrationStrategy(...);
      if (
        tokens[i + 3]?.type === 'punct' &&
        tokens[i + 3].value === '=' &&
        tokens[i + 4]?.type === 'punct' &&
        tokens[i + 4].value === '>'
      ) {
        if (
          tokens[i + 5]?.type === 'ident' &&
          tokens[i + 5].value === 'MigrationStrategy' &&
          tokens[i + 6]?.type === 'punct' &&
          tokens[i + 6].value === '('
        ) {
          const closeIdx = findMatchingParenTokenIndex(tokens, i + 6);
          if (closeIdx === -1) {
            throw new Error(
              'Unterminated MigrationStrategy(...) block in MigrationStrategy get migration.'
            );
          }
          return { startIdx: i + 5, endIdx: closeIdx };
        }
      }

      // Block form: MigrationStrategy get migration { ... return MigrationStrategy(...); }
      if (tokens[i + 3]?.type === 'punct' && tokens[i + 3].value === '{') {
        const getterEnd = findMatchingBraceTokenIndex(tokens, i + 3);
        if (getterEnd === -1) {
          throw new Error('Unterminated "MigrationStrategy get migration" getter block in app_database.dart.');
        }
        for (let j = i + 4; j < getterEnd - 1; j += 1) {
          if (
            tokens[j].type === 'ident' &&
            tokens[j].value === 'MigrationStrategy' &&
            tokens[j + 1]?.type === 'punct' &&
            tokens[j + 1].value === '('
          ) {
            const closeIdx = findMatchingParenTokenIndex(tokens, j + 1);
            if (closeIdx === -1 || closeIdx > getterEnd) {
              throw new Error(
                'Unterminated MigrationStrategy(...) block inside MigrationStrategy get migration.'
              );
            }
            return { startIdx: j, endIdx: closeIdx };
          }
        }
        throw new Error(
          'MigrationStrategy get migration must construct and return MigrationStrategy(...) directly without bypassing onUpgrade.'
        );
      }
    }
  }
  throw new Error('Missing "MigrationStrategy get migration" getter in app_database.dart.');
}

function extractCallbackBlock(tokens, rangeStart, rangeEnd, callbackName) {
  let parenDepth = 0;
  for (let i = rangeStart; i <= rangeEnd; i += 1) {
    const tok = tokens[i];
    if (tok.type === 'punct' && tok.value === '(') parenDepth += 1;
    else if (tok.type === 'punct' && tok.value === ')') parenDepth = Math.max(0, parenDepth - 1);

    // Inside MigrationStrategy(...) top arguments have parenDepth === 1
    if (
      parenDepth === 1 &&
      tok.type === 'ident' &&
      tok.value === callbackName &&
      tokens[i + 1]?.type === 'punct' &&
      tokens[i + 1].value === ':'
    ) {
      // Find opening '{' or '=>'
      for (let j = i + 2; j <= rangeEnd; j += 1) {
        if (tokens[j].type === 'punct' && tokens[j].value === '(') {
          const paramsEnd = findMatchingParenTokenIndex(tokens, j);
          if (paramsEnd === -1) break;
          j = paramsEnd;
          continue;
        }
        if (tokens[j].type === 'punct' && tokens[j].value === '{') {
          const closeBrace = findMatchingBraceTokenIndex(tokens, j);
          if (closeBrace === -1 || closeBrace > rangeEnd) {
            throw new Error(`Unterminated ${callbackName} { ... } body in MigrationStrategy.`);
          }
          return { kind: 'block', startIdx: j + 1, endIdx: closeBrace - 1 };
        }
        if (
          tokens[j].type === 'punct' &&
          tokens[j].value === '=' &&
          tokens[j + 1]?.type === 'punct' &&
          tokens[j + 1].value === '>'
        ) {
          // Arrow expression up to top-level ',' or ')' of MigrationStrategy
          let innerDepth = 0;
          let k = j + 2;
          for (; k <= rangeEnd; k += 1) {
            const t = tokens[k];
            if (t.type === 'punct' && (t.value === '(' || t.value === '{' || t.value === '[')) {
              innerDepth += 1;
            } else if (t.type === 'punct' && (t.value === ')' || t.value === '}' || t.value === ']')) {
              if (innerDepth === 0 && t.value === ')') break;
              innerDepth = Math.max(0, innerDepth - 1);
            } else if (innerDepth === 0 && t.type === 'punct' && t.value === ',') {
              break;
            }
          }
          return { kind: 'arrow', startIdx: j + 2, endIdx: k - 1 };
        }
      }
      throw new Error(`Unable to parse ${callbackName} callback in MigrationStrategy.`);
    }
  }
  return null;
}

function extractUpgradeBranches(tokens, bodyStart, bodyEnd) {
  const branches = [];
  let braceDepth = 0;
  for (let i = bodyStart; i <= bodyEnd; i += 1) {
    const tok = tokens[i];
    if (tok.type === 'punct' && tok.value === '{') {
      braceDepth += 1;
      continue;
    }
    if (tok.type === 'punct' && tok.value === '}') {
      braceDepth = Math.max(0, braceDepth - 1);
      continue;
    }

    // Match top-level `if (from < N) { ... }` inside onUpgrade
    if (
      braceDepth === 0 &&
      tok.type === 'ident' &&
      tok.value === 'if' &&
      tokens[i + 1]?.type === 'punct' &&
      tokens[i + 1].value === '(' &&
      tokens[i + 2]?.type === 'ident' &&
      tokens[i + 2].value === 'from' &&
      tokens[i + 3]?.type === 'punct' &&
      tokens[i + 3].value === '<' &&
      tokens[i + 4]?.type === 'number' &&
      tokens[i + 5]?.type === 'punct' &&
      tokens[i + 5].value === ')' &&
      tokens[i + 6]?.type === 'punct' &&
      tokens[i + 6].value === '{'
    ) {
      const targetVersion = Number(tokens[i + 4].value);
      const blockStart = i + 6;
      const blockEnd = findMatchingBraceTokenIndex(tokens, blockStart);
      if (blockEnd === -1 || blockEnd > bodyEnd) {
        throw new Error(`Unterminated migration block "if (from < ${tokens[i + 4].value})".`);
      }
      const blockText = tokensToComparableText(tokens.slice(blockStart + 1, blockEnd));
      branches.push({
        targetVersion,
        line: tok.line,
        startIdx: i,
        blockText,
      });
      i = blockEnd;
    }
  }
  return branches;
}

function extractDowngradeGuard(tokens, bodyStart, bodyEnd) {
  let braceDepth = 0;
  for (let i = bodyStart; i <= bodyEnd; i += 1) {
    const tok = tokens[i];
    if (tok.type === 'punct' && tok.value === '{') {
      braceDepth += 1;
      continue;
    }
    if (tok.type === 'punct' && tok.value === '}') {
      braceDepth = Math.max(0, braceDepth - 1);
      continue;
    }

    if (
      braceDepth === 0 &&
      tok.type === 'ident' &&
      tok.value === 'if' &&
      tokens[i + 1]?.type === 'punct' &&
      tokens[i + 1].value === '(' &&
      tokens[i + 2]?.type === 'ident' &&
      tokens[i + 3]?.type === 'punct' &&
      tokens[i + 4]?.type === 'ident' &&
      tokens[i + 5]?.type === 'punct' &&
      tokens[i + 5].value === ')' &&
      tokens[i + 6]?.type === 'punct' &&
      tokens[i + 6].value === '{'
    ) {
      const lhs = tokens[i + 2].value;
      const op = tokens[i + 3].value;
      const rhs = tokens[i + 4].value;
      const isDowngradeCondition =
        (lhs === 'from' && op === '>' && rhs === 'to') ||
        (lhs === 'to' && op === '<' && rhs === 'from');
      if (!isDowngradeCondition) continue;

      const blockStart = i + 6;
      const blockEnd = findMatchingBraceTokenIndex(tokens, blockStart);
      if (blockEnd === -1 || blockEnd > bodyEnd) {
        throw new Error('Unterminated downgrade guard "if (from > to)" in onUpgrade.');
      }
      return {
        line: tok.line,
        startIdx: i,
        blockStart,
        blockEnd,
        blockTokens: tokens.slice(blockStart + 1, blockEnd),
      };
    }
  }
  return null;
}

export function checkMigrationCompatibility({ rootDir = defaultRootDir, silent = false } = {}) {
  const baselinePath = path.join(rootDir, 'scripts', 'migration_compatibility_baseline.json');
  if (!fs.existsSync(baselinePath)) {
    throw new Error(`Missing migration compatibility baseline: ${baselinePath}`);
  }
  let baseline;
  try {
    baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'));
  } catch (err) {
    throw new Error(`Invalid JSON in scripts/migration_compatibility_baseline.json: ${err.message}`);
  }

  const appDbRel = baseline.appDatabasePath || 'flutter_app/lib/data/database/app_database.dart';
  const appDbAbs = path.join(rootDir, appDbRel);
  if (!fs.existsSync(appDbAbs)) {
    throw new Error(`Missing AppDatabase file: ${appDbAbs}`);
  }

  const appDbSource = fs.readFileSync(appDbAbs, 'utf8');
  const tokens = tokenizeSource(appDbSource, { language: 'dart' });

  // 1. Parse schemaVersion from comment-stripped tokens (`int get schemaVersion => <N>;`)
  let declaredSchemaVersion = null;
  for (let i = 0; i <= tokens.length - 6; i += 1) {
    if (
      tokens[i].type === 'ident' &&
      tokens[i].value === 'int' &&
      tokens[i + 1].type === 'ident' &&
      tokens[i + 1].value === 'get' &&
      tokens[i + 2].type === 'ident' &&
      tokens[i + 2].value === 'schemaVersion' &&
      tokens[i + 3].type === 'punct' &&
      tokens[i + 3].value === '=' &&
      tokens[i + 4].type === 'punct' &&
      tokens[i + 4].value === '>' &&
      tokens[i + 5].type === 'number'
    ) {
      declaredSchemaVersion = Number(tokens[i + 5].value);
      break;
    }
  }
  if (!Number.isInteger(declaredSchemaVersion) || declaredSchemaVersion < 1) {
    throw new Error(`Unable to parse AppDatabase.schemaVersion from ${appDbRel}.`);
  }

  if (declaredSchemaVersion < baseline.minimumSchemaVersion) {
    throw new Error(
      `Schema version regression in ${appDbRel}: schemaVersion=${declaredSchemaVersion} is below minimumSchemaVersion=${baseline.minimumSchemaVersion} under ADR-007.`
    );
  }

  // 2. Forbid destructive migration fallbacks in non-comment tokens
  for (const forbiddenIdent of baseline.forbiddenDestructivePatterns ?? ['fallbackToDestructiveMigration']) {
    const hit = tokens.find((t) => t.type === 'ident' && t.value === forbiddenIdent);
    if (hit) {
      throw new Error(
        `Destructive Drift migration API "${forbiddenIdent}" is forbidden by ADR-007 (${appDbRel}:${hit.line}).`
      );
    }
  }

  // 3. Locate MigrationStrategy, onUpgrade, and onDowngrade
  const strategyRange = extractMigrationStrategyRange(tokens);
  const onUpgradeRange = extractCallbackBlock(
    tokens,
    strategyRange.startIdx,
    strategyRange.endIdx,
    'onUpgrade'
  );
  if (!onUpgradeRange || onUpgradeRange.kind !== 'block') {
    throw new Error(`AppDatabase.migration must define an onUpgrade block body in ${appDbRel}.`);
  }

  const branches = extractUpgradeBranches(tokens, onUpgradeRange.startIdx, onUpgradeRange.endIdx);
  const seenVersions = new Set();
  let previousVersion = 0;
  for (const branch of branches) {
    if (seenVersions.has(branch.targetVersion)) {
      throw new Error(
        `Duplicate migration branch "if (from < ${branch.targetVersion})" at ${appDbRel}:${branch.line}.`
      );
    }
    if (branch.targetVersion <= previousVersion) {
      throw new Error(
        `Out-of-order migration branch "if (from < ${branch.targetVersion})" after "from < ${previousVersion}" at ${appDbRel}:${branch.line}. ` +
          `Drift onUpgrade steps must execute in strictly ascending schema version order.`
      );
    }
    seenVersions.add(branch.targetVersion);
    previousVersion = branch.targetVersion;
  }

  // 4. Verify all previously released upgrade steps remain present & preserve core markers
  const branchByVersion = new Map(branches.map((b) => [b.targetVersion, b]));
  for (const step of baseline.releasedUpgradeSteps ?? []) {
    const branch = branchByVersion.get(step.version);
    if (!branch) {
      throw new Error(
        `Missing released schema migration branch "if (from < ${step.version})" in ${appDbRel} (required by ADR-007).`
      );
    }
    for (const marker of step.requiredMarkers ?? []) {
      const normalizedMarker = marker.replace(/\s+/g, '');
      const normalizedBlock = branch.blockText.replace(/\s+/g, '');
      if (!normalizedBlock.includes(normalizedMarker)) {
        throw new Error(
          `Released migration branch "if (from < ${step.version})" in ${appDbRel} is missing expected historical migration step "${marker}".`
        );
      }
    }
  }

  // 5. Any schemaVersion > minimumSchemaVersion must define sequential `if (from < v)` steps up to schemaVersion
  for (let v = baseline.minimumSchemaVersion + 1; v <= declaredSchemaVersion; v += 1) {
    if (!branchByVersion.has(v)) {
      throw new Error(
        `AppDatabase.schemaVersion=${declaredSchemaVersion} is missing required sequential upgrade branch "if (from < ${v})" in ${appDbRel}.`
      );
    }
  }

  // 6. Downgrade policy: Drift has no onDowngrade callback and routes from > to into onUpgrade.
  // Require an explicit fail-closed `if (from > to) { throw ...; }` guard before all `if (from < N)` branches.
  const onDowngradeRange = extractCallbackBlock(
    tokens,
    strategyRange.startIdx,
    strategyRange.endIdx,
    'onDowngrade'
  );
  if (onDowngradeRange) {
    throw new Error(
      `Drift MigrationStrategy in ${appDbRel} does not support an onDowngrade callback; ` +
        `enforce fail-closed downgrade protection with an explicit "if (from > to)" guard at the top of onUpgrade.`
    );
  }

  const downgradeGuard = extractDowngradeGuard(tokens, onUpgradeRange.startIdx, onUpgradeRange.endIdx);
  if (!downgradeGuard) {
    throw new Error(
      `AppDatabase.migration.onUpgrade in ${appDbRel} must begin with an explicit fail-closed ` +
        `"if (from > to) { throw ...; }" guard before all upgrade branches.`
    );
  }
  if (branches.length > 0 && downgradeGuard.startIdx > branches[0].startIdx) {
    throw new Error(
      `Downgrade guard "if (from > to)" at ${appDbRel}:${downgradeGuard.line} must appear before all ` +
        `"if (from < N)" branches in onUpgrade.`
    );
  }
  const hasDeleteEverything = downgradeGuard.blockTokens.some(
    (t) => t.type === 'ident' && (t.value === 'deleteEverything' || t.value === 'createAll')
  );
  if (hasDeleteEverything) {
    throw new Error(
      `Downgrade guard in ${appDbRel}:${downgradeGuard.line} must not wipe or recreate user data; unsupported downgrades must fail closed.`
    );
  }
  const hasThrow = downgradeGuard.blockTokens.some((t) => t.type === 'ident' && t.value === 'throw');
  if (!hasThrow) {
    throw new Error(
      `Downgrade guard "if (from > to)" in ${appDbRel}:${downgradeGuard.line} must fail closed with an explicit throw.`
    );
  }
  const downgradeMode = 'on-upgrade-explicit-throw-fail-closed';

  // 7. Required migration delegate files/classes exist
  for (const delegate of baseline.requiredDelegates ?? []) {
    const delegateAbs = path.join(rootDir, delegate.file);
    if (!fs.existsSync(delegateAbs)) {
      throw new Error(`Missing required migration delegate file: ${delegate.file}`);
    }
    const delegateTokens = tokenizeSource(fs.readFileSync(delegateAbs, 'utf8'), { language: 'dart' });
    const hasClass = delegateTokens.some((t) => t.type === 'ident' && t.value === delegate.className);
    const hasMethod = delegateTokens.some(
      (t) => t.type === 'ident' && t.value === delegate.requiredMethod
    );
    if (!hasClass || !hasMethod) {
      throw new Error(
        `Migration delegate ${delegate.file} is missing expected ${delegate.className}.${delegate.requiredMethod}.`
      );
    }
  }

  if (!silent) {
    console.log(
      `[check_migration_compatibility] Passed (schemaVersion=${declaredSchemaVersion}, ${branches.length} ascending upgrade steps, downgrade=${downgradeMode}).`
    );
  }

  return {
    passed: true,
    schemaVersion: declaredSchemaVersion,
    upgradeSteps: branches.map((b) => b.targetVersion),
    downgradeMode,
  };
}

const isCliEntry =
  Boolean(process.argv[1]) &&
  pathToFileURL(fs.realpathSync(process.argv[1])).href === pathToFileURL(fs.realpathSync(__filename)).href;

if (isCliEntry) {
  try {
    const rootFlagIdx = process.argv.indexOf('--root');
    const cliRootDir =
      rootFlagIdx !== -1 && process.argv[rootFlagIdx + 1]
        ? path.resolve(process.argv[rootFlagIdx + 1])
        : defaultRootDir;
    checkMigrationCompatibility({ rootDir: cliRootDir });
  } catch (err) {
    console.error(`[check_migration_compatibility] ERROR: ${err.message}`);
    process.exit(1);
  }
}
