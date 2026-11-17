#!/usr/bin/env node
import fs from 'fs';
import path from 'path';
import { fileURLToPath, pathToFileURL } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const defaultRootDir = path.resolve(__dirname, '..');

const GENERATED_FILES = new Set([
  'src/domain/sharedFoundation.ts',
  'src/styles/daywellTokens.css',
  'flutter_app/lib/core/shared_foundation.dart',
  'flutter_app/lib/core/shared_foundation_core.dart',
]);

const DART_PACKAGE_NAME = 'personal_management_app';
const FORBIDDEN_BROWSER_GLOBALS = new Set([
  'localStorage',
  'sessionStorage',
  'window',
  'document',
]);

function normalizeRelPath(relPath) {
  return relPath.replace(/\\/g, '/').replace(/^\/+/, '');
}

function isWildcardOrBroadPattern(value) {
  return /[*?[\]{}!]/.test(value) || value.endsWith('/');
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

/**
 * Character-level lexer for TypeScript and Dart.
 * Strips single-line and block comments (including Dart nested block comments)
 * WITHOUT modifying or being fooled by string literals.
 * Emits tokens { type: 'ident' | 'string' | 'punct', value, line }.
 */
export function tokenizeSource(source, { language }) {
  const isDart = language === 'dart';
  const tokens = [];
  const len = source.length;
  let i = 0;
  let line = 1;

  // Stack for TS template literal `${ ... }` brace nesting:
  // each entry stores brace depth at which the template expression resumes.
  const templateBraceDepths = [];
  let braceDepth = 0;

  const isIdentStart = (ch) => /[A-Za-z_$]/.test(ch);
  const isIdentPart = (ch) => /[A-Za-z0-9_$]/.test(ch);

  const readQuoted = (quote, { multiline = false, raw = false } = {}) => {
    const startLine = line;
    let value = '';
    while (i < len) {
      if (multiline) {
        if (source.slice(i, i + 3) === quote.repeat(3)) {
          i += 3;
          return { type: 'string', value, line: startLine };
        }
      } else if (source[i] === quote) {
        i += 1;
        return { type: 'string', value, line: startLine };
      }

      const ch = source[i];
      if (!raw && ch === '\\' && i + 1 < len) {
        const next = source[i + 1];
        if (next === '\n') line += 1;
        value += next;
        i += 2;
        continue;
      }
      if (!multiline && (ch === '\n' || ch === '\r')) {
        // Unterminated single-line string; stop safely at line boundary
        return { type: 'string', value, line: startLine };
      }
      if (ch === '\n') line += 1;
      value += ch;
      i += 1;
    }
    return { type: 'string', value, line: startLine };
  };

  const readTsTemplateChunk = (startLine) => {
    let value = '';
    while (i < len) {
      const ch = source[i];
      if (ch === '`') {
        i += 1;
        return { type: 'string', value, line: startLine, terminated: true };
      }
      if (ch === '$' && source[i + 1] === '{') {
        i += 2;
        braceDepth += 1;
        templateBraceDepths.push(braceDepth);
        return { type: 'string', value, line: startLine, terminated: false };
      }
      if (ch === '\\' && i + 1 < len) {
        if (source[i + 1] === '\n') line += 1;
        value += source[i + 1];
        i += 2;
        continue;
      }
      if (ch === '\n') line += 1;
      value += ch;
      i += 1;
    }
    return { type: 'string', value, line: startLine, terminated: true };
  };

  while (i < len) {
    const ch = source[i];

    // Whitespace
    if (ch === ' ' || ch === '\t' || ch === '\r' || ch === '\n') {
      if (ch === '\n') line += 1;
      i += 1;
      continue;
    }

    // Line comment
    if (ch === '/' && source[i + 1] === '/') {
      i += 2;
      while (i < len && source[i] !== '\n') {
        i += 1;
      }
      continue;
    }

    // Block comment (nested in Dart, flat in TS)
    if (ch === '/' && source[i + 1] === '*') {
      i += 2;
      let depth = 1;
      while (i < len && depth > 0) {
        if (isDart && source[i] === '/' && source[i + 1] === '*') {
          depth += 1;
          i += 2;
          continue;
        }
        if (source[i] === '*' && source[i + 1] === '/') {
          depth -= 1;
          i += 2;
          continue;
        }
        if (source[i] === '\n') line += 1;
        i += 1;
      }
      continue;
    }

    // Dart raw strings: r'...', r"...", r'''...''', r"""..."""
    if (isDart && ch === 'r' && (source[i + 1] === "'" || source[i + 1] === '"')) {
      const q = source[i + 1];
      if (source.slice(i + 1, i + 4) === q.repeat(3)) {
        i += 4;
        tokens.push(readQuoted(q, { multiline: true, raw: true }));
      } else {
        i += 2;
        tokens.push(readQuoted(q, { multiline: false, raw: true }));
      }
      continue;
    }

    // Standard / triple strings
    if (ch === "'" || ch === '"') {
      if (isDart && source.slice(i, i + 3) === ch.repeat(3)) {
        i += 3;
        tokens.push(readQuoted(ch, { multiline: true, raw: false }));
      } else {
        i += 1;
        tokens.push(readQuoted(ch, { multiline: false, raw: false }));
      }
      continue;
    }

    // TypeScript template literals
    if (!isDart && ch === '`') {
      const startLine = line;
      i += 1;
      const chunk = readTsTemplateChunk(startLine);
      tokens.push({ type: 'string', value: chunk.value, line: chunk.line });
      continue;
    }

    // Braces (including template literal continuation)
    if (ch === '{') {
      braceDepth += 1;
      tokens.push({ type: 'punct', value: '{', line });
      i += 1;
      continue;
    }
    if (ch === '}') {
      if (
        !isDart &&
        templateBraceDepths.length > 0 &&
        templateBraceDepths[templateBraceDepths.length - 1] === braceDepth
      ) {
        templateBraceDepths.pop();
        braceDepth -= 1;
        i += 1;
        const startLine = line;
        const nextChunk = readTsTemplateChunk(startLine);
        tokens.push({ type: 'string', value: nextChunk.value, line: nextChunk.line });
        continue;
      }
      braceDepth = Math.max(0, braceDepth - 1);
      tokens.push({ type: 'punct', value: '}', line });
      i += 1;
      continue;
    }

    // Identifiers
    if (isIdentStart(ch)) {
      const startLine = line;
      let j = i + 1;
      while (j < len && isIdentPart(source[j])) j += 1;
      tokens.push({ type: 'ident', value: source.slice(i, j), line: startLine });
      i = j;
      continue;
    }

    // Numeric literal (consume cleanly so dots inside floats aren't confused with member access)
    if (/[0-9]/.test(ch)) {
      const startLine = line;
      let j = i + 1;
      while (j < len && /[0-9A-Za-z_.]/.test(source[j])) j += 1;
      tokens.push({ type: 'number', value: source.slice(i, j), line: startLine });
      i = j;
      continue;
    }

    // Punctuation
    tokens.push({ type: 'punct', value: ch, line });
    i += 1;
  }

  return tokens;
}

/**
 * Extracts static imports, re-exports, dynamic import('...'), and require('...') from TypeScript.
 */
export function extractTypeScriptImports(source) {
  const tokens = tokenizeSource(source, { language: 'ts' });
  const imports = [];
  const STATEMENT_BOUNDARIES = new Set([';', '{', '}']);

  const isStatementStart = (idx) => {
    if (idx === 0) return true;
    const prev = tokens[idx - 1];
    return prev.type === 'punct' && STATEMENT_BOUNDARIES.has(prev.value);
  };

  const canStartStatementAfterNewline = (idx) => {
    if (isStatementStart(idx)) return true;
    const prev = tokens[idx - 1];
    // ASI-tolerant in TS: newline before import/export at top-level or block start
    return prev.line < tokens[idx].line && !(prev.type === 'punct' && (prev.value === '.' || prev.value === '(' || prev.value === ','));
  };

  for (let i = 0; i < tokens.length; i += 1) {
    const tok = tokens[i];
    if (tok.type !== 'ident') continue;

    // 1. Dynamic import('...')
    if (
      tok.value === 'import' &&
      tokens[i + 1]?.type === 'punct' &&
      tokens[i + 1].value === '('
    ) {
      // Skip `import.meta` etc. because tokens[i + 1] wouldn't be '('
      if (tokens[i + 2]?.type === 'string') {
        imports.push({ specifier: tokens[i + 2].value, kind: 'dynamic-import', line: tok.line });
      }
      continue;
    }

    // 2. CommonJS require('...')
    if (
      tok.value === 'require' &&
      !(tokens[i - 1]?.type === 'punct' && tokens[i - 1].value === '.') &&
      tokens[i + 1]?.type === 'punct' &&
      tokens[i + 1].value === '(' &&
      tokens[i + 2]?.type === 'string' &&
      tokens[i + 3]?.type === 'punct' &&
      tokens[i + 3].value === ')'
    ) {
      imports.push({ specifier: tokens[i + 2].value, kind: 'require', line: tok.line });
      continue;
    }

    // 3. Static import directive (`import ... from '...'` or `import '...'`)
    if (tok.value === 'import' && canStartStatementAfterNewline(i)) {
      const next = tokens[i + 1];
      if (!next) continue;
      if (next.type === 'punct' && next.value === '.') continue; // import.meta
      if (next.type === 'string') {
        imports.push({ specifier: next.value, kind: 'side-effect-import', line: tok.line });
        continue;
      }

      let braceLevel = 0;
      let foundFrom = null;
      for (let j = i + 1; j < tokens.length; j += 1) {
        const cur = tokens[j];
        if (cur.type === 'punct') {
          if (cur.value === '{') braceLevel += 1;
          else if (cur.value === '}') braceLevel = Math.max(0, braceLevel - 1);
          else if (cur.value === ';' && braceLevel === 0) break;
        } else if (
          braceLevel === 0 &&
          cur.type === 'ident' &&
          cur.value === 'from' &&
          tokens[j + 1]?.type === 'string'
        ) {
          foundFrom = tokens[j + 1].value;
          break;
        }
        // Stop cleanly if malformed statement hits a top-level declaration
        if (
          braceLevel === 0 &&
          cur.type === 'ident' &&
          (cur.value === 'import' || cur.value === 'export' || cur.value === 'function' || cur.value === 'class') &&
          j > i + 1
        ) {
          break;
        }
      }
      if (foundFrom !== null) {
        imports.push({ specifier: foundFrom, kind: 'static-import', line: tok.line });
      }
      continue;
    }

    // 4. Re-export directive (`export ... from '...'`)
    if (tok.value === 'export' && canStartStatementAfterNewline(i)) {
      let nextIdx = i + 1;
      if (tokens[nextIdx]?.type === 'ident' && tokens[nextIdx].value === 'type') {
        nextIdx += 1;
      }
      const next = tokens[nextIdx];
      if (!next || next.type !== 'punct' || (next.value !== '{' && next.value !== '*')) {
        continue;
      }
      let braceLevel = 0;
      for (let j = nextIdx; j < tokens.length; j += 1) {
        const cur = tokens[j];
        if (cur.type === 'punct') {
          if (cur.value === '{') braceLevel += 1;
          else if (cur.value === '}') braceLevel = Math.max(0, braceLevel - 1);
          else if (cur.value === ';' && braceLevel === 0) break;
        } else if (
          braceLevel === 0 &&
          cur.type === 'ident' &&
          cur.value === 'from' &&
          tokens[j + 1]?.type === 'string'
        ) {
          imports.push({ specifier: tokens[j + 1].value, kind: 're-export', line: tok.line });
          break;
        }
      }
    }
  }

  return { imports, tokens };
}

/**
 * Extracts Dart import, export, and part directives (including multiline & conditional URI imports).
 */
export function extractDartDirectives(source) {
  const tokens = tokenizeSource(source, { language: 'dart' });
  const directives = [];

  for (let i = 0; i < tokens.length; i += 1) {
    const tok = tokens[i];
    if (tok.type !== 'ident') continue;
    const isAtDirectiveBoundary =
      i === 0 || (tokens[i - 1]?.type === 'punct' && tokens[i - 1].value === ';');
    if (!isAtDirectiveBoundary) continue;

    if (tok.value !== 'import' && tok.value !== 'export' && tok.value !== 'part') {
      continue;
    }

    // Skip `part of ...;` library-name directives unless URI string is used
    if (tok.value === 'part' && tokens[i + 1]?.type === 'ident' && tokens[i + 1].value === 'of') {
      if (tokens[i + 2]?.type === 'string') {
        directives.push({ specifier: tokens[i + 2].value, kind: 'part-of', line: tok.line });
      }
      continue;
    }

    if (tokens[i + 1]?.type !== 'string') {
      continue;
    }

    // Scan until terminating ';' so conditional imports (`if (dart.library.io) '...'`) are also captured
    for (let j = i + 1; j < tokens.length; j += 1) {
      const cur = tokens[j];
      if (cur.type === 'punct' && cur.value === ';') {
        break;
      }
      if (cur.type === 'string') {
        directives.push({ specifier: cur.value, kind: tok.value, line: tok.line });
      }
    }
  }

  return { directives, tokens };
}

/**
 * Detects direct browser-global usage (localStorage, sessionStorage, window, document)
 * inside non-test Web domain files using tokenized identifiers (no comments/strings).
 */
export function detectForbiddenBrowserGlobals(tokens) {
  const hits = [];
  for (let i = 0; i < tokens.length; i += 1) {
    const tok = tokens[i];
    if (tok.type !== 'ident' || !FORBIDDEN_BROWSER_GLOBALS.has(tok.value)) {
      continue;
    }
    const prev = tokens[i - 1];
    const next = tokens[i + 1];

    // Skip property member reads (`obj.window`)
    if (prev?.type === 'punct' && prev.value === '.') {
      continue;
    }
    // Skip type/object-literal property definitions (`{ window: ... }` or `interface Foo { window?: ... }`)
    const isPropertyKey =
      (next?.type === 'punct' && next.value === ':') ||
      (next?.type === 'punct' &&
        next.value === '?' &&
        tokens[i + 2]?.type === 'punct' &&
        tokens[i + 2].value === ':');
    if (isPropertyKey) {
      continue;
    }
    // Skip local declarations (`const window = ...`? Actually avoid aliasing/shadowing in domain too,
    // wait - allow parameter or interface property, flag actual expression/member use).
    hits.push({ identifier: tok.value, line: tok.line });
  }
  return hits;
}

function resolveTypeScriptImport(sourceRelPath, specifier, rootDir) {
  if (!specifier.startsWith('.')) {
    return { type: 'package', name: specifier };
  }
  const baseDir = path.posix.dirname(sourceRelPath);
  const rawJoined = path.posix.normalize(path.posix.join(baseDir, specifier));
  const candidates = [
    rawJoined,
    `${rawJoined}.ts`,
    `${rawJoined}.tsx`,
    `${rawJoined}.mts`,
    `${rawJoined}.mjs`,
    `${rawJoined}.js`,
    `${rawJoined}/index.ts`,
    `${rawJoined}/index.tsx`,
    `${rawJoined}/index.js`,
  ];
  for (const candidate of candidates) {
    const abs = path.join(rootDir, candidate);
    if (fs.existsSync(abs) && fs.statSync(abs).isFile()) {
      return { type: 'repo-file', path: normalizeRelPath(candidate) };
    }
  }
  return { type: 'repo-file', path: normalizeRelPath(rawJoined) };
}

function resolveDartImport(sourceRelPath, specifier) {
  if (specifier.startsWith('dart:')) {
    return { type: 'sdk', name: specifier };
  }
  if (specifier.startsWith('package:')) {
    const rest = specifier.slice('package:'.length);
    const slashIdx = rest.indexOf('/');
    const pkgName = slashIdx === -1 ? rest : rest.slice(0, slashIdx);
    const innerPath = slashIdx === -1 ? '' : rest.slice(slashIdx + 1);
    if (pkgName === DART_PACKAGE_NAME) {
      return {
        type: 'repo-file',
        path: normalizeRelPath(path.posix.join('flutter_app/lib', innerPath)),
      };
    }
    return { type: 'package', name: specifier, packageName: pkgName };
  }
  const baseDir = path.posix.dirname(sourceRelPath);
  return {
    type: 'repo-file',
    path: normalizeRelPath(path.posix.normalize(path.posix.join(baseDir, specifier))),
  };
}

function listFilesRecursively(dirPath, predicate) {
  if (!fs.existsSync(dirPath)) return [];
  const results = [];
  for (const entry of fs.readdirSync(dirPath, { withFileTypes: true })) {
    const full = path.join(dirPath, entry.name);
    if (entry.isDirectory()) {
      results.push(...listFilesRecursively(full, predicate));
    } else if (predicate(entry.name, full)) {
      results.push(full);
    }
  }
  return results;
}

export function loadAndValidateAllowlist(rootDir, { requireAllowlist = true } = {}) {
  const allowlistPath = path.join(rootDir, 'scripts', 'architecture_allowlist.json');
  if (!fs.existsSync(allowlistPath)) {
    if (requireAllowlist) {
      throw new Error(`Missing architecture allowlist: ${allowlistPath}`);
    }
    return new Map();
  }

  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(allowlistPath, 'utf8'));
  } catch (err) {
    throw new Error(`Invalid JSON in scripts/architecture_allowlist.json: ${err.message}`);
  }

  if (!isPlainObject(parsed) || !Array.isArray(parsed.exceptions)) {
    throw new Error('scripts/architecture_allowlist.json must be an object with an "exceptions" array.');
  }

  const byKey = new Map();
  for (let i = 0; i < parsed.exceptions.length; i += 1) {
    const entry = parsed.exceptions[i];
    const prefix = `exceptions[${i}]`;
    if (!isPlainObject(entry)) {
      throw new Error(`Invalid ${prefix} in scripts/architecture_allowlist.json: expected object.`);
    }
    for (const field of ['source', 'target', 'rule', 'responsibleLayer', 'reason', 'adrOrDoc']) {
      if (typeof entry[field] !== 'string' || entry[field].trim().length === 0) {
        throw new Error(
          `Invalid scripts/architecture_allowlist.json entry "${prefix}.${field}": expected non-empty string.`
        );
      }
    }
    if (isWildcardOrBroadPattern(entry.source) || isWildcardOrBroadPattern(entry.target)) {
      throw new Error(
        `Overly broad or wildcard exception rejected in scripts/architecture_allowlist.json (${prefix}): ` +
          `source="${entry.source}", target="${entry.target}". Exact file/import boundaries are required.`
      );
    }

    const docAbs = path.resolve(rootDir, entry.adrOrDoc);
    const docRel = path.relative(rootDir, docAbs);
    if (docRel.startsWith('..') || path.isAbsolute(docRel) || !fs.existsSync(docAbs)) {
      throw new Error(
        `Invalid ${prefix}.adrOrDoc in scripts/architecture_allowlist.json: ` +
          `"${entry.adrOrDoc}" does not resolve to an existing documentation or ADR file.`
      );
    }

    const sourceNorm = normalizeRelPath(entry.source);
    const targetNorm = normalizeRelPath(entry.target);
    const key = `${entry.rule}::${sourceNorm}::${targetNorm}`;
    if (byKey.has(key)) {
      throw new Error(`Duplicate allowlist entry in scripts/architecture_allowlist.json: ${key}`);
    }
    byKey.set(key, { ...entry, source: sourceNorm, target: targetNorm });
  }

  return byKey;
}

function getFlutterLayer(relPath) {
  if (relPath === 'flutter_app/lib/main.dart') return 'entry';
  if (relPath.startsWith('flutter_app/lib/domain/')) return 'domain';
  if (relPath.startsWith('flutter_app/lib/application/')) return 'application';
  if (relPath.startsWith('flutter_app/lib/data/')) return 'data';
  if (relPath.startsWith('flutter_app/lib/services/')) return 'services';
  if (relPath.startsWith('flutter_app/lib/ui/')) return 'presentation';
  if (relPath.startsWith('flutter_app/lib/core/theme/')) return 'core-theme';
  if (relPath.startsWith('flutter_app/lib/core/')) return 'core';
  return 'other';
}

function getWebLayer(relPath) {
  if (relPath === 'src/App.tsx' || relPath === 'src/main.tsx') return 'app-shell';
  if (relPath.startsWith('src/domain/')) return 'domain';
  if (relPath.startsWith('src/data/')) return 'data';
  if (relPath.startsWith('src/services/')) return 'services';
  if (relPath.startsWith('src/components/')) return 'presentation';
  return 'other';
}

function isExcludedWebFile(relPath) {
  if (GENERATED_FILES.has(relPath)) return true;
  if (relPath.endsWith('.test.ts') || relPath.endsWith('.test.tsx')) return true;
  if (relPath.includes('/__tests__/')) return true;
  return false;
}

function isExcludedDartFile(relPath) {
  if (GENERATED_FILES.has(relPath)) return true;
  if (relPath.endsWith('_test.dart') || relPath.endsWith('.g.dart')) return true;
  return false;
}

export function checkArchitectureBoundaries({
  rootDir = defaultRootDir,
  silent = false,
  requireAllowlist = true,
} = {}) {
  const allowlist = loadAndValidateAllowlist(rootDir, { requireAllowlist });
  const violations = [];
  let checkedDartFiles = 0;
  let checkedTsFiles = 0;

  const recordViolation = ({ rule, source, target, line, message }) => {
    const key = `${rule}::${normalizeRelPath(source)}::${normalizeRelPath(target)}`;
    if (allowlist.has(key)) {
      return;
    }
    violations.push(`[${rule}] ${source}:${line} -> ${target}: ${message}`);
  };

  // 1. Flutter boundary analysis
  const flutterLibDir = path.join(rootDir, 'flutter_app', 'lib');
  const dartFiles = listFilesRecursively(flutterLibDir, (name) => name.endsWith('.dart'));
  for (const absPath of dartFiles) {
    const relPath = normalizeRelPath(path.relative(rootDir, absPath));
    if (isExcludedDartFile(relPath)) continue;
    checkedDartFiles += 1;

    const layer = getFlutterLayer(relPath);
    const source = fs.readFileSync(absPath, 'utf8');
    const { directives } = extractDartDirectives(source);

    for (const dir of directives) {
      const resolved = resolveDartImport(relPath, dir.specifier);
      const targetStr = resolved.type === 'repo-file' ? resolved.path : dir.specifier;

      // Global Flutter isolation: never import Web src/ or design_assets/
      if (
        (resolved.type === 'repo-file' &&
          (resolved.path.startsWith('src/') || resolved.path.startsWith('design_assets/'))) ||
        dir.specifier.includes('/src/') ||
        dir.specifier.includes('/design_assets/')
      ) {
        recordViolation({
          rule: 'flutter-cross-platform-isolation',
          source: relPath,
          target: targetStr,
          line: dir.line,
          message: 'Flutter library code must never import Web src/ or design_assets/.',
        });
        continue;
      }

      if (layer === 'domain') {
        const isForbiddenSdk = dir.specifier === 'dart:ui';
        const isForbiddenPkg =
          dir.specifier.startsWith('package:flutter/') ||
          dir.specifier.startsWith('package:drift/') ||
          dir.specifier.startsWith('package:sqflite/') ||
          dir.specifier.startsWith('package:sqlite3/');
        const isForbiddenRepo =
          resolved.type === 'repo-file' &&
          (resolved.path.startsWith('flutter_app/lib/ui/') ||
            resolved.path.startsWith('flutter_app/lib/application/') ||
            resolved.path.startsWith('flutter_app/lib/data/') ||
            resolved.path.startsWith('flutter_app/lib/services/') ||
            resolved.path === 'flutter_app/lib/core/shared_foundation.dart' ||
            resolved.path === 'flutter_app/lib/core/shared_foundation_bridge.dart' ||
            resolved.path.startsWith('flutter_app/lib/core/theme/'));
        if (isForbiddenSdk || isForbiddenPkg || isForbiddenRepo) {
          recordViolation({
            rule: 'flutter-domain-purity',
            source: relPath,
            target: targetStr,
            line: dir.line,
            message:
              'Flutter domain code must not depend on UI frameworks, Drift/SQLite, presentation, application, data, or services.',
          });
        }
      } else if (layer === 'application') {
        const isForbiddenUiPkg =
          dir.specifier === 'dart:ui' ||
          dir.specifier === 'package:flutter/material.dart' ||
          dir.specifier === 'package:flutter/cupertino.dart' ||
          dir.specifier === 'package:flutter/widgets.dart';
        const isForbiddenDbPkg =
          dir.specifier.startsWith('package:drift/') ||
          dir.specifier.startsWith('package:sqflite/') ||
          dir.specifier.startsWith('package:sqlite3/');
        const isForbiddenRepo =
          resolved.type === 'repo-file' &&
          (resolved.path.startsWith('flutter_app/lib/ui/') ||
            resolved.path.startsWith('flutter_app/lib/data/') ||
            resolved.path.startsWith('flutter_app/lib/services/') ||
            resolved.path === 'flutter_app/lib/core/shared_foundation.dart' ||
            resolved.path === 'flutter_app/lib/core/shared_foundation_bridge.dart' ||
            resolved.path.startsWith('flutter_app/lib/core/theme/'));
        if (isForbiddenUiPkg || isForbiddenDbPkg || isForbiddenRepo) {
          recordViolation({
            rule: 'flutter-application-boundary',
            source: relPath,
            target: targetStr,
            line: dir.line,
            message:
              'Flutter application controllers must not depend on presentation UI, AppStateManager, or database implementations.',
          });
        }
      } else if (layer === 'data' || layer === 'services') {
        const isForbiddenUiPkg =
          dir.specifier === 'package:flutter/material.dart' ||
          dir.specifier === 'package:flutter/cupertino.dart' ||
          dir.specifier === 'package:flutter/widgets.dart';
        const isForbiddenRepo =
          resolved.type === 'repo-file' &&
          (resolved.path.startsWith('flutter_app/lib/ui/') ||
            resolved.path.startsWith('flutter_app/lib/application/') ||
            resolved.path === 'flutter_app/lib/core/shared_foundation.dart' ||
            resolved.path.startsWith('flutter_app/lib/core/theme/'));
        if (isForbiddenUiPkg || isForbiddenRepo) {
          recordViolation({
            rule: `flutter-${layer}-boundary`,
            source: relPath,
            target: targetStr,
            line: dir.line,
            message: `Flutter ${layer} layer must not depend on UI widgets, presentation, or application controllers.`,
          });
        }
      } else if (layer === 'presentation' || layer === 'entry') {
        const isForbiddenDbPkg =
          dir.specifier.startsWith('package:drift/') ||
          dir.specifier.startsWith('package:sqflite/') ||
          dir.specifier.startsWith('package:sqlite3/');
        const isForbiddenData =
          resolved.type === 'repo-file' && resolved.path.startsWith('flutter_app/lib/data/');
        if (isForbiddenDbPkg || isForbiddenData) {
          recordViolation({
            rule: 'flutter-ui-no-data',
            source: relPath,
            target: targetStr,
            line: dir.line,
            message:
              'Presentation layer must use controllers/contracts rather than importing Drift or data/ directly (outside narrow composition-root allowlist).',
          });
        }
      } else if (layer === 'core' || layer === 'core-theme') {
        const isForbiddenRepo =
          resolved.type === 'repo-file' &&
          (resolved.path.startsWith('flutter_app/lib/ui/') ||
            resolved.path.startsWith('flutter_app/lib/application/') ||
            resolved.path.startsWith('flutter_app/lib/data/') ||
            resolved.path.startsWith('flutter_app/lib/services/') ||
            resolved.path.startsWith('flutter_app/lib/domain/'));
        if (isForbiddenRepo) {
          recordViolation({
            rule: 'flutter-core-isolation',
            source: relPath,
            target: targetStr,
            line: dir.line,
            message: 'Flutter core layer must remain independent of UI, application, data, services, and domain.',
          });
        }
      }
    }
  }

  // Check flutter_app/pubspec.yaml does not bundle src/ or design_assets/
  const pubspecPath = path.join(rootDir, 'flutter_app', 'pubspec.yaml');
  if (fs.existsSync(pubspecPath)) {
    const pubspecLines = fs.readFileSync(pubspecPath, 'utf8').split('\n');
    for (let idx = 0; idx < pubspecLines.length; idx += 1) {
      const lineText = pubspecLines[idx].replace(/#.*$/, '');
      if (/(^|\s|['"])(\.\.\/)?(src|design_assets)\//.test(lineText)) {
        recordViolation({
          rule: 'flutter-cross-platform-isolation',
          source: 'flutter_app/pubspec.yaml',
          target: lineText.trim(),
          line: idx + 1,
          message: 'flutter_app/pubspec.yaml must never bundle src/ or design_assets/.',
        });
      }
    }
  }

  // 2. Web Preview boundary analysis
  const webSrcDir = path.join(rootDir, 'src');
  const tsFiles = listFilesRecursively(webSrcDir, (name) => name.endsWith('.ts') || name.endsWith('.tsx'));
  for (const absPath of tsFiles) {
    const relPath = normalizeRelPath(path.relative(rootDir, absPath));
    if (isExcludedWebFile(relPath)) continue;
    checkedTsFiles += 1;

    const layer = getWebLayer(relPath);
    const source = fs.readFileSync(absPath, 'utf8');
    const { imports, tokens } = extractTypeScriptImports(source);

    for (const imp of imports) {
      const resolved = resolveTypeScriptImport(relPath, imp.specifier, rootDir);
      const targetStr = resolved.type === 'repo-file' ? resolved.path : imp.specifier;

      // Ensure Web src never imports flutter_app/
      if (
        (resolved.type === 'repo-file' && resolved.path.startsWith('flutter_app/')) ||
        imp.specifier.includes('flutter_app/')
      ) {
        recordViolation({
          rule: 'web-no-flutter-import',
          source: relPath,
          target: targetStr,
          line: imp.line,
          message: 'Web source must not import flutter_app runtime files directly.',
        });
        continue;
      }

      if (layer === 'domain') {
        const isForbiddenPkg =
          imp.specifier === 'react' ||
          imp.specifier.startsWith('react/') ||
          imp.specifier === 'react-dom' ||
          imp.specifier.startsWith('react-dom/') ||
          imp.specifier === 'lucide-react' ||
          imp.specifier === 'motion' ||
          imp.specifier.startsWith('motion/');
        const isForbiddenRepo =
          resolved.type === 'repo-file' &&
          (resolved.path.startsWith('src/data/') ||
            resolved.path.startsWith('src/services/') ||
            resolved.path.startsWith('src/components/') ||
            resolved.path === 'src/App.tsx' ||
            resolved.path === 'src/main.tsx');
        if (isForbiddenPkg || isForbiddenRepo) {
          recordViolation({
            rule: 'web-domain-purity',
            source: relPath,
            target: targetStr,
            line: imp.line,
            message:
              'Web domain code must remain pure and must not import src/data/, src/services/, UI components, or React.',
          });
        }
      } else if (layer === 'services') {
        const isForbiddenPkg =
          imp.specifier === 'react' ||
          imp.specifier.startsWith('react/') ||
          imp.specifier === 'react-dom' ||
          imp.specifier.startsWith('react-dom/');
        const isForbiddenRepo =
          resolved.type === 'repo-file' &&
          (resolved.path.startsWith('src/components/') ||
            resolved.path === 'src/App.tsx' ||
            resolved.path === 'src/main.tsx');
        if (isForbiddenPkg || isForbiddenRepo) {
          recordViolation({
            rule: 'web-services-boundary',
            source: relPath,
            target: targetStr,
            line: imp.line,
            message: 'Web services must not import React or presentation components.',
          });
        }
      } else if (layer === 'presentation' || layer === 'app-shell') {
        const isForbiddenData =
          resolved.type === 'repo-file' && resolved.path.startsWith('src/data/');
        if (isForbiddenData) {
          recordViolation({
            rule: 'web-ui-no-data',
            source: relPath,
            target: targetStr,
            line: imp.line,
            message:
              'Web presentation components and App shell must consume domain contracts and services rather than importing src/data/ directly.',
          });
        }
      } else if (layer === 'data') {
        const isForbiddenPkg =
          imp.specifier === 'react' ||
          imp.specifier.startsWith('react/') ||
          imp.specifier === 'react-dom' ||
          imp.specifier.startsWith('react-dom/');
        const isForbiddenUi =
          resolved.type === 'repo-file' &&
          (resolved.path.startsWith('src/components/') ||
            resolved.path === 'src/App.tsx' ||
            resolved.path === 'src/main.tsx');
        if (isForbiddenPkg || isForbiddenUi) {
          recordViolation({
            rule: 'web-data-boundary',
            source: relPath,
            target: targetStr,
            line: imp.line,
            message: 'Web data layer must not depend on React or UI components.',
          });
        }
      }
    }

    if (layer === 'domain') {
      const browserHits = detectForbiddenBrowserGlobals(tokens);
      for (const hit of browserHits) {
        recordViolation({
          rule: 'web-domain-no-browser-globals',
          source: relPath,
          target: hit.identifier,
          line: hit.line,
          message: `Web domain code must not reference browser global "${hit.identifier}".`,
        });
      }
    }
  }

  if (violations.length > 0) {
    throw new Error(
      `Architecture dependency-boundary violation(s) detected (${violations.length}):\n  - ${violations.join('\n  - ')}`
    );
  }

  if (!silent) {
    console.log(
      `[check_architecture_boundaries] Passed (${checkedDartFiles} Dart files, ${checkedTsFiles} TS/TSX files checked, ${allowlist.size} documented allowlist edges).`
    );
  }

  return {
    passed: true,
    checkedDartFiles,
    checkedTsFiles,
    allowlistCount: allowlist.size,
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
    checkArchitectureBoundaries({ rootDir: cliRootDir });
  } catch (err) {
    console.error(`[check_architecture_boundaries] ERROR: ${err.message}`);
    process.exit(1);
  }
}
