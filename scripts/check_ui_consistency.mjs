#!/usr/bin/env node
import fs from 'fs';
import path from 'path';
import { fileURLToPath, pathToFileURL } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const defaultRootDir = path.resolve(__dirname, '..');

function normalizeRelPath(relPath) {
  return relPath.replace(/\\/g, '/').replace(/^\/+/, '');
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
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

/**
 * Strips comments while preserving line numbers (replacing comment characters with spaces,
 * preserving newlines) and preserving string literals verbatim so Tailwind classes or
 * Dart code patterns inside strings/templates are still scanned cleanly.
 */
function stripCommentsPreservingStringsAndLines(source, { language }) {
  const isDart = language === 'dart';
  const len = source.length;
  let out = '';
  let i = 0;

  while (i < len) {
    const ch = source[i];

    // Line comment (TS/Dart; CSS uses /* ... */ only)
    if (!language.startsWith('css') && ch === '/' && source[i + 1] === '/') {
      out += '  ';
      i += 2;
      while (i < len && source[i] !== '\n') {
        out += ' ';
        i += 1;
      }
      continue;
    }

    // Block comment
    if (ch === '/' && source[i + 1] === '*') {
      out += '  ';
      i += 2;
      let depth = 1;
      while (i < len && depth > 0) {
        if (isDart && source[i] === '/' && source[i + 1] === '*') {
          depth += 1;
          out += '  ';
          i += 2;
          continue;
        }
        if (source[i] === '*' && source[i + 1] === '/') {
          depth -= 1;
          out += '  ';
          i += 2;
          continue;
        }
        out += source[i] === '\n' ? '\n' : ' ';
        i += 1;
      }
      continue;
    }

    // Preserve string quotes so comments inside strings don't look like code comments
    if (ch === "'" || ch === '"' || (!isDart && !language.startsWith('css') && ch === '`')) {
      const quote = ch;
      const isTripleDart = isDart && source.slice(i, i + 3) === quote.repeat(3);
      if (isTripleDart) {
        out += quote.repeat(3);
        i += 3;
        while (i < len) {
          if (source.slice(i, i + 3) === quote.repeat(3)) {
            out += quote.repeat(3);
            i += 3;
            break;
          }
          if (source[i] === '\\' && i + 1 < len) {
            out += source[i] + source[i + 1];
            i += 2;
            continue;
          }
          out += source[i];
          i += 1;
        }
        continue;
      }

      out += quote;
      i += 1;
      while (i < len) {
        const sc = source[i];
        if (sc === '\\' && i + 1 < len) {
          out += sc + source[i + 1];
          i += 2;
          continue;
        }
        out += sc;
        i += 1;
        if (sc === quote) break;
      }
      continue;
    }

    out += ch;
    i += 1;
  }

  return out;
}

function loadAllowlist(rootDir) {
  const allowlistPath = path.join(rootDir, 'scripts', 'ui_consistency_allowlist.json');
  if (!fs.existsSync(allowlistPath)) {
    throw new Error(`Missing UI consistency allowlist: ${allowlistPath}`);
  }
  const parsed = JSON.parse(fs.readFileSync(allowlistPath, 'utf8'));
  if (!isPlainObject(parsed) || !isPlainObject(parsed.web) || !isPlainObject(parsed.flutter)) {
    throw new Error('scripts/ui_consistency_allowlist.json must contain "web" and "flutter" objects.');
  }
  const webFiles = new Set();
  for (const rel of parsed.web.files || []) {
    if (typeof rel !== 'string' || /[*?[\]{}!]/.test(rel)) {
      throw new Error(`Invalid wildcard/entry in ui_consistency_allowlist.json web.files: ${rel}`);
    }
    webFiles.add(normalizeRelPath(rel));
  }
  const forbiddenAllowlist = new Set(
    (parsed.flutter.forbiddenAllowlistFiles || []).map((f) => normalizeRelPath(f))
  );
  const rawColorsAllowlist = new Map();
  for (const [rel, meta] of Object.entries(parsed.flutter.rawColorsAllowlist || {})) {
    const norm = normalizeRelPath(rel);
    if (/[*?[\]{}!]/.test(norm)) {
      throw new Error(`Invalid wildcard in ui_consistency_allowlist.json flutter.rawColorsAllowlist: ${rel}`);
    }
    if (forbiddenAllowlist.has(norm)) {
      throw new Error(
        `Migrated screen "${norm}" is forbidden from ui_consistency_allowlist.json flutter.rawColorsAllowlist.`
      );
    }
    if (!isPlainObject(meta) || typeof meta.maxCount !== 'number' || meta.maxCount < 0) {
      throw new Error(`Invalid allowlist maxCount for "${norm}" in ui_consistency_allowlist.json.`);
    }
    rawColorsAllowlist.set(norm, meta);
  }
  return {
    webFiles,
    exemptColorsTransparent: Boolean(parsed.flutter.exemptColorsTransparent),
    rawColorsAllowlist,
  };
}

function parseCssScopes(cssText) {
  const rootMatch = cssText.match(/:root\s*\{([\s\S]*?)\}/);
  const darkMatch = cssText.match(/\.dark\s*\{([\s\S]*?)\}/);
  const extractVars = (block) => {
    const map = new Map();
    if (!block) return map;
    const re = /(--dw-[a-z0-9-]+)\s*:\s*([^;]+);/gi;
    let m;
    while ((m = re.exec(block)) !== null) {
      map.set(m[1], m[2].trim());
    }
    return map;
  };
  return {
    rootVars: extractVars(rootMatch ? rootMatch[1] : ''),
    darkVars: extractVars(darkMatch ? darkMatch[1] : ''),
  };
}

function verifyDesignTokenParity(rootDir, errors) {
  const tokensJsonPath = path.join(rootDir, 'shared_foundation', 'design_tokens.json');
  const cssPath = path.join(rootDir, 'src', 'styles', 'daywellTokens.css');
  const indexCssPath = path.join(rootDir, 'src', 'index.css');
  const tsTokensPath = path.join(rootDir, 'src', 'domain', 'sharedFoundation.ts');
  const dartTokensPath = path.join(rootDir, 'flutter_app', 'lib', 'core', 'shared_foundation.dart');

  for (const p of [tokensJsonPath, cssPath, indexCssPath, tsTokensPath, dartTokensPath]) {
    if (!fs.existsSync(p)) {
      errors.push(`[token-drift] Missing required design token file: ${normalizeRelPath(path.relative(rootDir, p))}`);
      return;
    }
  }

  const tokens = JSON.parse(fs.readFileSync(tokensJsonPath, 'utf8'));
  const cssText = fs.readFileSync(cssPath, 'utf8');
  const indexCssText = fs.readFileSync(indexCssPath, 'utf8');
  const tsText = fs.readFileSync(tsTokensPath, 'utf8');
  const dartText = fs.readFileSync(dartTokensPath, 'utf8');

  if (!/@import\s+["']\.\/styles\/daywellTokens\.css["']\s*;/.test(indexCssText)) {
    errors.push('[token-drift] src/index.css must @import "./styles/daywellTokens.css".');
  }

  const { rootVars, darkVars } = parseCssScopes(cssText);
  const expectedRoot = {
    '--dw-primary': tokens.colors.primary.emerald,
    '--dw-primary-hover': tokens.colors.primary.emeraldDark,
    '--dw-primary-brand': tokens.colors.primary.emerald,
    '--dw-on-primary': tokens.colors.primary.onLight,
    '--dw-primary-container': tokens.colors.secondary.mint,
    '--dw-on-primary-container': tokens.colors.secondary.onLight,
    '--dw-canvas': tokens.colors.surface.canvasLight,
    '--dw-surface-subtle': tokens.colors.surface.subtleLight,
    '--dw-card': tokens.colors.surface.cardLight,
    '--dw-elevated': tokens.colors.surface.elevatedLight,
    '--dw-border': tokens.colors.surface.borderLight,
    '--dw-divider': tokens.colors.surface.dividerLight,
    '--dw-text-primary': tokens.colors.text.primaryLight,
    '--dw-text-secondary': tokens.colors.text.secondaryLight,
    '--dw-text-muted': tokens.colors.text.mutedLight,
    '--dw-text-disabled': tokens.colors.text.disabledLight,
    '--dw-income': tokens.colors.semantic.income,
    '--dw-income-container': tokens.colors.semantic.incomeContainerLight,
    '--dw-on-income-container': tokens.colors.semantic.onIncomeContainerLight,
    '--dw-expense': tokens.colors.semantic.expense,
    '--dw-expense-container': tokens.colors.semantic.expenseContainerLight,
    '--dw-on-expense-container': tokens.colors.semantic.onExpenseContainerLight,
    '--dw-transfer': tokens.colors.semantic.transfer,
    '--dw-transfer-container': tokens.colors.semantic.transferContainerLight,
    '--dw-on-transfer-container': tokens.colors.semantic.onTransferContainerLight,
    '--dw-success': tokens.colors.semantic.success,
    '--dw-success-container': tokens.colors.semantic.successContainerLight,
    '--dw-on-success-container': tokens.colors.semantic.onSuccessContainerLight,
    '--dw-error': tokens.colors.semantic.error,
    '--dw-error-container': tokens.colors.semantic.errorContainerLight,
    '--dw-on-error-container': tokens.colors.semantic.onErrorContainerLight,
    '--dw-warning': tokens.colors.semantic.warning,
    '--dw-warning-container': tokens.colors.semantic.warningContainerLight,
    '--dw-on-warning-container': tokens.colors.semantic.onWarningContainerLight,
    '--dw-info': tokens.colors.semantic.info,
    '--dw-info-container': tokens.colors.semantic.infoContainerLight,
    '--dw-on-info-container': tokens.colors.semantic.onInfoContainerLight,
    '--dw-space-xs': `${tokens.spacing.xs}px`,
    '--dw-space-sm': `${tokens.spacing.sm}px`,
    '--dw-space-compact': `${tokens.spacing.compact}px`,
    '--dw-space-md': `${tokens.spacing.md}px`,
    '--dw-space-lg': `${tokens.spacing.lg}px`,
    '--dw-space-xl': `${tokens.spacing.xl}px`,
    '--dw-radius-sm': `${tokens.radii.sm}px`,
    '--dw-radius-md': `${tokens.radii.md}px`,
    '--dw-radius-lg': `${tokens.radii.lg}px`,
    '--dw-radius-xl': `${tokens.radii.xl}px`,
    '--dw-radius-sheet': `${tokens.radii.sheet}px`,
    '--dw-radius-full': `${tokens.radii.full}px`,
    '--dw-breakpoint-medium': `${tokens.breakpoints.medium}px`,
    '--dw-breakpoint-expanded': `${tokens.breakpoints.expanded}px`,
  };

  const expectedDark = {
    '--dw-primary': tokens.colors.primary.darkMode,
    '--dw-primary-brand': tokens.colors.primary.emeraldLight,
    '--dw-on-primary': tokens.colors.primary.onDark,
    '--dw-primary-container': tokens.colors.secondary.mintDark,
    '--dw-on-primary-container': tokens.colors.secondary.onDark,
    '--dw-canvas': tokens.colors.surface.canvasDark,
    '--dw-surface-subtle': tokens.colors.surface.subtleDark,
    '--dw-card': tokens.colors.surface.cardDark,
    '--dw-elevated': tokens.colors.surface.elevatedDark,
    '--dw-border': tokens.colors.surface.borderDark,
    '--dw-divider': tokens.colors.surface.dividerDark,
    '--dw-text-primary': tokens.colors.text.primaryDark,
    '--dw-text-secondary': tokens.colors.text.secondaryDark,
    '--dw-text-muted': tokens.colors.text.mutedDark,
    '--dw-text-disabled': tokens.colors.text.disabledDark,
  };

  for (const [k, expectedVal] of Object.entries(expectedRoot)) {
    const actual = rootVars.get(k);
    if (!actual || actual.toUpperCase() !== String(expectedVal).toUpperCase()) {
      errors.push(
        `[token-drift] src/styles/daywellTokens.css :root ${k} expected "${expectedVal}", found "${actual ?? 'MISSING'}".`
      );
    }
  }
  for (const [k, expectedVal] of Object.entries(expectedDark)) {
    const actual = darkVars.get(k);
    if (!actual || actual.toUpperCase() !== String(expectedVal).toUpperCase()) {
      errors.push(
        `[token-drift] src/styles/daywellTokens.css .dark ${k} expected "${expectedVal}", found "${actual ?? 'MISSING'}".`
      );
    }
  }

  // Spot-check Dart & TS generated outputs remain aligned to design_tokens.json
  const primaryHexNoHash = tokens.colors.primary.emerald.slice(1).toUpperCase();
  if (!dartText.toUpperCase().includes(`0XFF${primaryHexNoHash}`)) {
    errors.push(`[token-drift] flutter_app/lib/core/shared_foundation.dart is missing primary emerald 0xFF${primaryHexNoHash}.`);
  }
  if (!tsText.toUpperCase().includes(tokens.colors.primary.emerald.toUpperCase())) {
    errors.push(`[token-drift] src/domain/sharedFoundation.ts is missing primary emerald ${tokens.colors.primary.emerald}.`);
  }
}

function verifyWebUiHexCompliance(rootDir, allowlist, errors) {
  const candidates = [];
  const appTsx = path.join(rootDir, 'src', 'App.tsx');
  const indexCss = path.join(rootDir, 'src', 'index.css');
  if (fs.existsSync(appTsx)) candidates.push(appTsx);
  if (fs.existsSync(indexCss)) candidates.push(indexCss);

  const compDir = path.join(rootDir, 'src', 'components');
  candidates.push(
    ...listFilesRecursively(compDir, (name) => name.endsWith('.ts') || name.endsWith('.tsx'))
  );

  let checkedCount = 0;
  const hexRegex = /#[0-9a-fA-F]{3,8}\b/g;

  for (const absPath of candidates) {
    const relPath = normalizeRelPath(path.relative(rootDir, absPath));
    if (relPath.endsWith('.test.ts') || relPath.endsWith('.test.tsx') || relPath === 'src/styles/daywellTokens.css') {
      continue;
    }
    checkedCount += 1;
    if (allowlist.webFiles.has(relPath)) continue;

    const raw = fs.readFileSync(absPath, 'utf8');
    const stripped = stripCommentsPreservingStringsAndLines(raw, {
      language: relPath.endsWith('.css') ? 'css' : 'ts',
    });
    const lines = stripped.split('\n');
    for (let idx = 0; idx < lines.length; idx += 1) {
      const matches = lines[idx].match(hexRegex);
      if (matches && matches.length > 0) {
        errors.push(
          `[web-hardcoded-hex] ${relPath}:${idx + 1} contains unallowlisted hex color literal(s): ${matches.join(', ')}. Use --dw-* CSS variables or SHARED_DESIGN_TOKENS.`
        );
      }
    }
  }

  return checkedCount;
}

function verifyFlutterUiColorCompliance(rootDir, allowlist, errors) {
  const uiDir = path.join(rootDir, 'flutter_app', 'lib', 'ui');
  const dartFiles = listFilesRecursively(uiDir, (name) => name.endsWith('.dart'));
  let checkedCount = 0;

  const rawColorHexRe = /Color\(\s*0x[0-9a-fA-F]+\s*\)/g;
  const materialColorsRe = /\bColors\.[a-zA-Z0-9_]+/g;

  for (const absPath of dartFiles) {
    const relPath = normalizeRelPath(path.relative(rootDir, absPath));
    if (relPath.endsWith('.g.dart') || relPath.endsWith('_test.dart')) continue;
    checkedCount += 1;

    const raw = fs.readFileSync(absPath, 'utf8');
    const stripped = stripCommentsPreservingStringsAndLines(raw, { language: 'dart' });
    const lines = stripped.split('\n');

    let materialColorHits = [];
    for (let idx = 0; idx < lines.length; idx += 1) {
      const hexHits = lines[idx].match(rawColorHexRe);
      if (hexHits && hexHits.length > 0) {
        errors.push(
          `[flutter-raw-color-hex] ${relPath}:${idx + 1} contains forbidden raw Color(0x...) literal: ${hexHits.join(', ')}. Use SharedDesignTokens or context.daywellColors.`
        );
      }
      const colorsHits = lines[idx].match(materialColorsRe) || [];
      for (const hit of colorsHits) {
        if (allowlist.exemptColorsTransparent && hit === 'Colors.transparent') {
          continue;
        }
        materialColorHits.push({ hit, line: idx + 1 });
      }
    }

    const allowedEntry = allowlist.rawColorsAllowlist.get(relPath);
    if (!allowedEntry) {
      if (materialColorHits.length > 0) {
        const preview = materialColorHits.slice(0, 4).map((m) => `${m.hit}@L${m.line}`).join(', ');
        errors.push(
          `[flutter-unallowlisted-colors] ${relPath} uses ${materialColorHits.length} unallowlisted Material Colors.* literal(s) (${preview}). Use Theme.of(context).colorScheme or context.daywellColors.`
        );
      }
    } else if (materialColorHits.length > allowedEntry.maxCount) {
      errors.push(
        `[flutter-allowlist-overflow] ${relPath} has ${materialColorHits.length} Material Colors.* literal(s), exceeding allowlist maxCount=${allowedEntry.maxCount}. Do not introduce new Colors.* literals.`
      );
    }
  }

  return checkedCount;
}

function verifyCrossPlatformPrimitiveParity(rootDir, errors) {
  const flutterWidgetsDir = path.join(rootDir, 'flutter_app', 'lib', 'ui', 'widgets');
  const webUiDir = path.join(rootDir, 'src', 'components', 'ui');
  const flutterBarrelPath = path.join(flutterWidgetsDir, 'shared_ui_widgets.dart');
  const webBarrelPath = path.join(webUiDir, 'index.ts');

  if (!fs.existsSync(flutterBarrelPath)) {
    errors.push('[primitive-parity] Missing Flutter barrel flutter_app/lib/ui/widgets/shared_ui_widgets.dart.');
    return;
  }
  if (!fs.existsSync(webBarrelPath)) {
    errors.push('[primitive-parity] Missing Web UI barrel src/components/ui/index.ts.');
    return;
  }

  const readCombined = (dir) =>
    listFilesRecursively(dir, (n) => n.endsWith('.dart') || n.endsWith('.ts') || n.endsWith('.tsx'))
      .map((f) => fs.readFileSync(f, 'utf8'))
      .join('\n');

  const flutterCombined = readCombined(flutterWidgetsDir);
  const webCombined = readCombined(webUiDir);

  const requiredSharedFamilies = [
    { name: 'Button', flutterSymbol: 'class DaywellButton', webSymbol: 'export function DaywellButton' },
    { name: 'IconButton', flutterSymbol: 'class DaywellIconButton', webSymbol: 'export function DaywellIconButton' },
    { name: 'Card', flutterSymbol: 'class DaywellCard', webSymbol: 'export function DaywellCard' },
    { name: 'SectionHeader', flutterSymbol: 'class DaywellSectionHeader', webSymbol: 'export function DaywellSectionHeader' },
    { name: 'EmptyState', flutterSymbol: 'class DaywellEmptyState', webSymbol: 'export function DaywellEmptyState' },
    { name: 'StatusTone', flutterSymbol: 'enum DaywellStatusTone', webSymbol: 'export type DaywellStatusTone' },
    { name: 'StatusBadge', flutterSymbol: 'class DaywellStatusBadge', webSymbol: 'export function DaywellStatusBadge' },
    { name: 'StatusBanner', flutterSymbol: 'class DaywellStatusBanner', webSymbol: 'export function DaywellStatusBanner' },
    { name: 'LoadingIndicator', flutterSymbol: 'class DaywellLoadingIndicator', webSymbol: 'export function DaywellLoadingIndicator' },
    { name: 'ProgressBar', flutterSymbol: 'class DaywellProgressBar', webSymbol: 'export function DaywellProgressBar' },
    { name: 'TextField', flutterSymbol: 'class DaywellTextField', webSymbol: 'export function DaywellTextField' },
    { name: 'SearchField', flutterSymbol: 'class DaywellSearchField', webSymbol: 'export function DaywellSearchField' },
    { name: 'SelectOrDropdown', flutterSymbol: 'class DaywellDropdownField', webSymbol: 'export function DaywellSelectField' },
    { name: 'SectionContainer', flutterSymbol: 'class DaywellSectionContainer', webSymbol: 'export function DaywellSectionContainer' },
    { name: 'ContentState', flutterSymbol: 'class DaywellContentState', webSymbol: 'export function DaywellContentState' },
    { name: 'ConfirmationDialog', flutterSymbol: 'class DaywellConfirmationDialog', webSymbol: 'export function DaywellConfirmationDialog' },
  ];

  for (const fam of requiredSharedFamilies) {
    if (!flutterCombined.includes(fam.flutterSymbol)) {
      errors.push(`[primitive-parity] Missing Flutter shared UI primitive "${fam.flutterSymbol}" for family ${fam.name}.`);
    }
    if (!webCombined.includes(fam.webSymbol)) {
      errors.push(`[primitive-parity] Missing Web shared UI primitive "${fam.webSymbol}" for family ${fam.name}.`);
    }
  }
}

export function checkUiConsistency({ rootDir = defaultRootDir, silent = false } = {}) {
  const allowlist = loadAllowlist(rootDir);
  const errors = [];

  verifyDesignTokenParity(rootDir, errors);
  const checkedWebFiles = verifyWebUiHexCompliance(rootDir, allowlist, errors);
  const checkedFlutterFiles = verifyFlutterUiColorCompliance(rootDir, allowlist, errors);
  verifyCrossPlatformPrimitiveParity(rootDir, errors);

  if (errors.length > 0) {
    throw new Error(
      `UI design-system consistency check failed (${errors.length} violation(s)):\n  - ${errors.join('\n  - ')}`
    );
  }

  if (!silent) {
    console.log(
      `[check_ui_consistency] Passed (${checkedWebFiles} Web UI files [0 hardcoded hexes], ${checkedFlutterFiles} Flutter UI files [0 Color(0x...)], ${allowlist.rawColorsAllowlist.size} bounded legacy Flutter Colors.* allowlist entries, full primitive parity).`
    );
  }

  return {
    passed: true,
    checkedWebFiles,
    checkedFlutterFiles,
    flutterAllowlistCount: allowlist.rawColorsAllowlist.size,
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
    checkUiConsistency({ rootDir: cliRootDir });
  } catch (err) {
    console.error(`[check_ui_consistency] ERROR: ${err.message}`);
    process.exit(1);
  }
}
