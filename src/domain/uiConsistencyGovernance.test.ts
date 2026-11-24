import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { SHARED_DESIGN_TOKENS } from './sharedFoundation';
// @ts-ignore - ESM script validated dynamically by Node test runner
import { checkUiConsistency } from '../../scripts/check_ui_consistency.mjs';

const REPO_ROOT = process.cwd();

function copyMinimalUiFixtureRepo(tmpRoot: string): void {
  const dirsToCopy = [
    path.join('src', 'components', 'ui'),
    path.join('flutter_app', 'lib', 'ui', 'widgets'),
  ];

  const filesToCopy = [
    path.join('shared_foundation', 'design_tokens.json'),
    path.join('scripts', 'ui_consistency_allowlist.json'),
    path.join('src', 'styles', 'daywellTokens.css'),
    path.join('src', 'index.css'),
    path.join('src', 'App.tsx'),
    path.join('src', 'domain', 'sharedFoundation.ts'),
    path.join('flutter_app', 'lib', 'core', 'shared_foundation.dart'),
    path.join('flutter_app', 'lib', 'ui', 'screens', 'more_view.dart'),
    path.join('flutter_app', 'lib', 'ui', 'screens', 'dashboard_view.dart'),
    path.join('flutter_app', 'lib', 'ui', 'screens', 'tasks_view.dart'),
    path.join('flutter_app', 'lib', 'ui', 'screens', 'notes_view.dart'),
    path.join('flutter_app', 'lib', 'ui', 'screens', 'backup_view.dart'),
    path.join('flutter_app', 'lib', 'ui', 'screens', 'finance', 'finance_overview_tab.dart'),
  ];

  for (const relDir of dirsToCopy) {
    fs.cpSync(path.join(REPO_ROOT, relDir), path.join(tmpRoot, relDir), { recursive: true });
  }
  for (const relFile of filesToCopy) {
    const src = path.join(REPO_ROOT, relFile);
    const dest = path.join(tmpRoot, relFile);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(src, dest);
  }
}

describe('PERMANENT UI CONSISTENCY & CROSS-PLATFORM DESIGN GOVERNANCE', () => {
  it('1. Live repository passes checkUiConsistency with zero Web hexes, zero raw Color(0x...), and full primitive parity', () => {
    const result = checkUiConsistency({ rootDir: REPO_ROOT, silent: true });
    assert.strictEqual(result.passed, true);
    assert.ok(result.checkedWebFiles >= 8, 'Expected App.tsx, index.css, and Web UI components to be scanned');
    assert.ok(result.checkedFlutterFiles >= 20, 'Expected Flutter UI files to be scanned');
    assert.strictEqual(result.flutterAllowlistCount, 4);
  });

  it('2. Enforces zero hardcoded hex colors in Web UI (fails closed on unallowlisted #RGB/#RRGGBB)', () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'daywell-ui-gov-webhex-'));
    try {
      copyMinimalUiFixtureRepo(tmpRoot);
      assert.strictEqual(checkUiConsistency({ rootDir: tmpRoot, silent: true }).passed, true);

      const appPath = path.join(tmpRoot, 'src', 'App.tsx');
      fs.appendFileSync(appPath, '\nconst forbiddenColor = "#123456";\n', 'utf8');

      assert.throws(
        () => checkUiConsistency({ rootDir: tmpRoot, silent: true }),
        /\[web-hardcoded-hex\] src\/App\.tsx:.*#123456/
      );
    } finally {
      fs.rmSync(tmpRoot, { recursive: true, force: true });
    }
  });

  it('3. Enforces canonical CSS token parity and index.css import (fails closed on token drift)', () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'daywell-ui-gov-cssdrift-'));
    try {
      copyMinimalUiFixtureRepo(tmpRoot);

      const cssPath = path.join(tmpRoot, 'src', 'styles', 'daywellTokens.css');
      const originalCss = fs.readFileSync(cssPath, 'utf8');
      fs.writeFileSync(
        cssPath,
        originalCss.replace('--dw-primary: #1B4D3E;', '--dw-primary: #111111;'),
        'utf8'
      );

      assert.throws(
        () => checkUiConsistency({ rootDir: tmpRoot, silent: true }),
        /\[token-drift\] src\/styles\/daywellTokens\.css :root --dw-primary/
      );

      fs.writeFileSync(cssPath, originalCss, 'utf8');
      const indexCssPath = path.join(tmpRoot, 'src', 'index.css');
      fs.writeFileSync(indexCssPath, '@import "tailwindcss";\n', 'utf8');

      assert.throws(
        () => checkUiConsistency({ rootDir: tmpRoot, silent: true }),
        /\[token-drift\] src\/index\.css must @import/
      );
    } finally {
      fs.rmSync(tmpRoot, { recursive: true, force: true });
    }
  });

  it('4. Enforces Flutter UI compliance: rejects raw Color(0x...), unallowlisted Colors.*, and allowlist growth', () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'daywell-ui-gov-flutter-'));
    try {
      copyMinimalUiFixtureRepo(tmpRoot);

      // (a) Raw Color(0x...) literal fails closed
      const moreViewPath = path.join(tmpRoot, 'flutter_app', 'lib', 'ui', 'screens', 'more_view.dart');
      const originalMore = fs.readFileSync(moreViewPath, 'utf8');
      fs.writeFileSync(moreViewPath, `${originalMore}\n// test\nfinal _badHex = Color(0xFF123456);\n`, 'utf8');

      assert.throws(
        () => checkUiConsistency({ rootDir: tmpRoot, silent: true }),
        /\[flutter-raw-color-hex\] flutter_app\/lib\/ui\/screens\/more_view\.dart:/
      );

      // (b) Unallowlisted Colors.* on migrated screen fails closed
      fs.writeFileSync(moreViewPath, `${originalMore}\nfinal _badMat = Colors.red;\n`, 'utf8');
      assert.throws(
        () => checkUiConsistency({ rootDir: tmpRoot, silent: true }),
        /\[flutter-unallowlisted-colors\] flutter_app\/lib\/ui\/screens\/more_view\.dart/
      );

      // (c) Overflowing pre-existing allowlist maxCount fails closed
      fs.writeFileSync(moreViewPath, originalMore, 'utf8');
      const tasksViewPath = path.join(tmpRoot, 'flutter_app', 'lib', 'ui', 'screens', 'tasks_view.dart');
      fs.appendFileSync(tasksViewPath, '\nfinal _extraLegacyColor = Colors.amber;\n', 'utf8');
      assert.throws(
        () => checkUiConsistency({ rootDir: tmpRoot, silent: true }),
        /\[flutter-allowlist-overflow\] flutter_app\/lib\/ui\/screens\/tasks_view\.dart/
      );
    } finally {
      fs.rmSync(tmpRoot, { recursive: true, force: true });
    }
  });

  it('5. Enforces cross-platform shared UI primitive symbol parity between Flutter widgets and Web components', () => {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'daywell-ui-gov-parity-'));
    try {
      copyMinimalUiFixtureRepo(tmpRoot);

      const webBtnPath = path.join(tmpRoot, 'src', 'components', 'ui', 'DaywellButton.tsx');
      const originalBtn = fs.readFileSync(webBtnPath, 'utf8');
      fs.writeFileSync(
        webBtnPath,
        originalBtn.replace('export function DaywellButton', 'export function LegacyRenamedButton'),
        'utf8'
      );

      assert.throws(
        () => checkUiConsistency({ rootDir: tmpRoot, silent: true }),
        /\[primitive-parity\] Missing Web shared UI primitive "export function DaywellButton"/
      );
    } finally {
      fs.rmSync(tmpRoot, { recursive: true, force: true });
    }
  });

  it('6. Migrated Flutter MoreView, DashboardView, and NotesView contain zero raw Colors.* or Color(0x...) literals', () => {
    const moreSource = fs.readFileSync(
      path.join(REPO_ROOT, 'flutter_app', 'lib', 'ui', 'screens', 'more_view.dart'),
      'utf8'
    );
    const dashboardSource = fs.readFileSync(
      path.join(REPO_ROOT, 'flutter_app', 'lib', 'ui', 'screens', 'dashboard_view.dart'),
      'utf8'
    );
    const notesSource = fs.readFileSync(
      path.join(REPO_ROOT, 'flutter_app', 'lib', 'ui', 'screens', 'notes_view.dart'),
      'utf8'
    );

    for (const [name, src] of [
      ['more_view.dart', moreSource],
      ['dashboard_view.dart', dashboardSource],
      ['notes_view.dart', notesSource],
    ] as const) {
      assert.strictEqual(/Color\(\s*0x/i.test(src), false, `${name} must contain zero Color(0x...) literals`);
      const materialColors = (src.match(/\bColors\.[a-zA-Z0-9_]+/g) || []).filter(
        (m) => m !== 'Colors.transparent'
      );
      assert.strictEqual(
        materialColors.length,
        0,
        `${name} must contain zero Material Colors.* literals, found: ${materialColors.join(', ')}`
      );
    }

    assert.ok(moreSource.includes('DaywellCard'), 'MoreView must use DaywellCard');
    assert.ok(moreSource.includes('DaywellSectionHeader'), 'MoreView must use DaywellSectionHeader');
    assert.ok(moreSource.includes('context.daywellColors'), 'MoreView must use context.daywellColors');
    assert.ok(moreSource.includes('DaywellTypography'), 'MoreView must use DaywellTypography');
    assert.ok(notesSource.includes('DaywellCard'), 'NotesView must use DaywellCard');
    assert.ok(notesSource.includes('DaywellSearchFilterBar'), 'NotesView must use DaywellSearchFilterBar');
    assert.ok(notesSource.includes('DaywellConfirmationDialog'), 'NotesView must use DaywellConfirmationDialog');
    assert.ok(notesSource.includes('context.daywellColors'), 'NotesView must use context.daywellColors');
    assert.ok(notesSource.includes('DaywellTypography'), 'NotesView must use DaywellTypography');
  });

  it('7. Design tokens JSON, TypeScript, CSS variables, and Dart constants match on primary, surface, spacing, radii, and breakpoints', () => {
    const cssSource = fs.readFileSync(path.join(REPO_ROOT, 'src', 'styles', 'daywellTokens.css'), 'utf8');
    const dartSource = fs.readFileSync(
      path.join(REPO_ROOT, 'flutter_app', 'lib', 'core', 'shared_foundation.dart'),
      'utf8'
    );

    assert.ok(cssSource.includes(`--dw-primary: ${SHARED_DESIGN_TOKENS.colors.primary.emerald};`));
    assert.ok(cssSource.includes(`--dw-canvas: ${SHARED_DESIGN_TOKENS.colors.surface.canvasLight};`));
    assert.ok(cssSource.includes(`--dw-canvas: ${SHARED_DESIGN_TOKENS.colors.surface.canvasDark};`));
    assert.ok(cssSource.includes(`--dw-space-md: ${SHARED_DESIGN_TOKENS.spacing.md}px;`));
    assert.ok(cssSource.includes(`--dw-radius-lg: ${SHARED_DESIGN_TOKENS.radii.lg}px;`));
    assert.ok(
      cssSource.includes(`--dw-max-content-width: ${SHARED_DESIGN_TOKENS.breakpoints.maxContentWidth}px;`)
    );
    assert.ok(
      dartSource.includes(`breakpointMaxContentWidth = ${SHARED_DESIGN_TOKENS.breakpoints.maxContentWidth}.0;`)
    );
  });

  it('8. Web App shell removes Figma prototype header pill and explicitly labels static mockups Deprecated Prototype', () => {
    const appSource = fs.readFileSync(path.join(REPO_ROOT, 'src', 'App.tsx'), 'utf8');
    assert.strictEqual(appSource.includes('Figma Approved UI'), false, 'Legacy Figma badge must be removed');
    assert.ok(appSource.includes('Canonical Design System'), 'Canonical Design System badge must be present');
    assert.ok(appSource.includes('DeprecatedPrototypeBanner'), 'Static mockup screens must use DeprecatedPrototypeBanner');
    assert.ok(appSource.includes('Deprecated Prototype'), 'Static prototype cards must be labeled Deprecated Prototype');
  });
});
