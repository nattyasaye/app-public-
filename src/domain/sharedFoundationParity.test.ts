import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  SHARED_DESIGN_TOKENS,
  SHARED_BUSINESS_RULES,
  CANONICAL_SEED_DATABASE,
  SharedAccount,
  SharedTransaction,
  calculateSharedAccountBalance,
  calculateSharedCombinedBalance,
  calculateSharedTotalIncome,
  calculateSharedTotalExpense,
  canDeleteSharedAccount,
  canDeleteSharedCategory,
  validateSharedTransfer,
} from './sharedFoundation';
import { SharedStateBridge } from '../services/sharedStateBridge';
import {
  calculateSimpleAccountBalance,
  calculateSimpleCombinedBalance,
  calculateSimpleTotalIncome,
  calculateSimpleTotalExpense,
  canDeleteSimpleAccount,
  canDeleteSimpleCategory,
} from './doubleEntryFinance';
// @ts-ignore - ESM script validated dynamically by Node test runner
import { validateDesignTokens, syncFoundation } from '../../scripts/sync_foundation.mjs';

function relativeLuminance(hex: string): number {
  const [r, g, b] = [1, 3, 5]
    .map((idx) => parseInt(hex.slice(idx, idx + 2), 16) / 255)
    .map((c) => (c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrastRatio(fgHex: string, bgHex: string): number {
  const l1 = relativeLuminance(fgHex);
  const l2 = relativeLuminance(bgHex);
  return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
}

describe('SHARED FOUNDATION ARCHITECTURE & CROSS-PLATFORM PARITY (ITERATION 2)', () => {
  it('1. Design Tokens: Canonical identity and complete foundation groups match specification', () => {
    assert.strictEqual(SHARED_DESIGN_TOKENS.version, '1.1.0');
    assert.strictEqual(SHARED_DESIGN_TOKENS.colors.primary.emerald, '#1B4D3E');
    assert.strictEqual(SHARED_DESIGN_TOKENS.colors.primary.darkMode, '#81C784');
    assert.strictEqual(SHARED_DESIGN_TOKENS.colors.secondary.mint, '#E0EFE8');
    assert.strictEqual(SHARED_DESIGN_TOKENS.colors.secondary.mintDark, '#1D382E');
    assert.strictEqual(SHARED_DESIGN_TOKENS.colors.surface.canvasLight, '#FAF9F5');
    assert.strictEqual(SHARED_DESIGN_TOKENS.colors.surface.canvasDark, '#121816');
    assert.strictEqual(SHARED_DESIGN_TOKENS.colors.surface.cardLight, '#FFFFFF');
    assert.strictEqual(SHARED_DESIGN_TOKENS.colors.surface.cardDark, '#1A2320');
    assert.strictEqual(SHARED_DESIGN_TOKENS.colors.semantic.income, '#10B981');
    assert.strictEqual(SHARED_DESIGN_TOKENS.colors.semantic.expense, '#EF4444');
    assert.strictEqual(SHARED_DESIGN_TOKENS.colors.semantic.transfer, '#0D9488');
    assert.strictEqual(SHARED_DESIGN_TOKENS.colors.semantic.success, '#15803D');
    assert.strictEqual(SHARED_DESIGN_TOKENS.colors.semantic.error, '#DC2626');
    assert.strictEqual(SHARED_DESIGN_TOKENS.colors.semantic.warning, '#F59E0B');
    assert.strictEqual(SHARED_DESIGN_TOKENS.colors.semantic.info, '#3B82F6');
  });

  it('2. Canonical Seed Database & Reconciliation Engine: Production seed is clean and ledger math reconciles identically', () => {
    // Stage 2 Verification: Production CanonicalSeedDatabase starts clean with 0 fake accounts and 11 default categories
    assert.strictEqual(CANONICAL_SEED_DATABASE.accounts.length, 0);
    assert.strictEqual(CANONICAL_SEED_DATABASE.transactions.length, 0);
    assert.strictEqual(CANONICAL_SEED_DATABASE.tasks.length, 0);
    assert.strictEqual(CANONICAL_SEED_DATABASE.notes.length, 0);
    assert.strictEqual(CANONICAL_SEED_DATABASE.categories.length, 11);
    assert.strictEqual(CANONICAL_SEED_DATABASE.isFinanceSetupCompleted, false);

    // Isolated test fixture to verify dual-engine balance reconciliation math
    const testAccounts: SharedAccount[] = [
      { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 1500000, isArchived: false },
      { id: 'acc-boa', name: 'BOA', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 500000, isArchived: false },
      { id: 'acc-dashen', name: 'Dashen Bank', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 350000, isArchived: false },
      { id: 'acc-telebirr', name: 'Telebirr', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 100000, isArchived: false },
      { id: 'acc-cash', name: 'Cash', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 50000, isArchived: false },
    ];

    const testTxs: SharedTransaction[] = [
      { id: 'tx-test-1', amountCents: 125000, type: 'expense', accountId: 'acc-cbe', transactionDate: '2026-11-08' },
      { id: 'tx-test-2', amountCents: 45000, type: 'expense', accountId: 'acc-telebirr', transactionDate: '2026-11-09' },
      { id: 'tx-test-3', amountCents: 200000, type: 'transfer', accountId: 'acc-cbe', destinationAccountId: 'acc-telebirr', transactionDate: '2026-11-10' },
    ];

    const cbeAcc = testAccounts.find((a) => a.id === 'acc-cbe')!;
    const telebirrAcc = testAccounts.find((a) => a.id === 'acc-telebirr')!;
    const boaAcc = testAccounts.find((a) => a.id === 'acc-boa')!;
    const dashenAcc = testAccounts.find((a) => a.id === 'acc-dashen')!;
    const cashAcc = testAccounts.find((a) => a.id === 'acc-cash')!;

    // CBE = 15,000 - 1,250 - 2,000 = 11,750 ETB (1,175,000 cents)
    assert.strictEqual(calculateSharedAccountBalance(cbeAcc, testTxs), 1175000);

    // Telebirr = 1,000 - 450 + 2,000 = 2,550 ETB (255,000 cents)
    assert.strictEqual(calculateSharedAccountBalance(telebirrAcc, testTxs), 255000);

    // Untouched accounts
    assert.strictEqual(calculateSharedAccountBalance(boaAcc, testTxs), 500000);
    assert.strictEqual(calculateSharedAccountBalance(dashenAcc, testTxs), 350000);
    assert.strictEqual(calculateSharedAccountBalance(cashAcc, testTxs), 50000);

    // Combined Balance = 11,750 + 2,550 + 5,000 + 3,500 + 500 = 23,300 ETB (2,330,000 cents)
    assert.strictEqual(calculateSharedCombinedBalance(testAccounts, testTxs), 2330000);
  });

  it('3. Business Rules: Finance math invariant (Account Balance = Opening + Inflows - Outflows + Transfers)', () => {
    const acc: SharedAccount = {
      id: 'acc-cbe',
      name: 'CBE',
      type: 'asset',
      currencyCode: 'ETB',
      openingBalanceCents: 1000000, // 10,000.00 ETB
      openingBalanceDate: '2026-11-01',
      isArchived: false,
    };

    const txs: SharedTransaction[] = [
      {
        id: 'tx-1',
        amountCents: 250000, // +2,500 ETB income
        type: 'income',
        accountId: 'acc-cbe',
        transactionDate: '2026-11-02T10:00:00Z',
      },
      {
        id: 'tx-2',
        amountCents: 100000, // -1,000 ETB expense
        type: 'expense',
        accountId: 'acc-cbe',
        transactionDate: '2026-11-03T11:00:00Z',
      },
      {
        id: 'tx-3',
        amountCents: 50000, // -500 ETB transfer out to BOA
        type: 'transfer',
        accountId: 'acc-cbe',
        destinationAccountId: 'acc-boa',
        transactionDate: '2026-11-04T12:00:00Z',
      },
      {
        id: 'tx-4',
        amountCents: 150000, // +1,500 ETB transfer in from Cash
        type: 'transfer',
        accountId: 'acc-cash',
        destinationAccountId: 'acc-cbe',
        transactionDate: '2026-11-05T13:00:00Z',
      },
    ];

    // Expected = 10,000 + 2,500 - 1,000 - 500 + 1,500 = 12,500.00 ETB (1,250,000 cents)
    const computedBal = calculateSharedAccountBalance(acc, txs);
    assert.strictEqual(computedBal, 1250000);

    // Parity check: doubleEntryFinance delegation produces the exact same value
    assert.strictEqual(calculateSimpleAccountBalance(acc as any, txs as any), 1250000);
  });

  it('4. Business Rules: Transfer strictly preserves Combined Balance across all asset accounts', () => {
    const acc1: SharedAccount = {
      id: 'acc-1',
      name: 'CBE',
      type: 'asset',
      currencyCode: 'ETB',
      openingBalanceCents: 500000, // 5,000 ETB
      isArchived: false,
    };
    const acc2: SharedAccount = {
      id: 'acc-2',
      name: 'Telebirr',
      type: 'asset',
      currencyCode: 'ETB',
      openingBalanceCents: 200000, // 2,000 ETB
      isArchived: false,
    };

    const initialCombined = calculateSharedCombinedBalance([acc1, acc2], []);
    assert.strictEqual(initialCombined, 700000); // 7,000 ETB

    const transferTx: SharedTransaction = {
      id: 'tx-xfer-1',
      amountCents: 150000, // 1,500 ETB from CBE to Telebirr
      type: 'transfer',
      accountId: 'acc-1',
      destinationAccountId: 'acc-2',
      transactionDate: '2026-11-06T10:00:00Z',
    };

    const combinedAfterTransfer = calculateSharedCombinedBalance([acc1, acc2], [transferTx]);
    assert.strictEqual(combinedAfterTransfer, 700000, 'Transfer must not alter total combined balance');
    assert.strictEqual(calculateSharedAccountBalance(acc1, [transferTx]), 350000);
    assert.strictEqual(calculateSharedAccountBalance(acc2, [transferTx]), 350000);

    // Parity check with doubleEntryFinance
    assert.strictEqual(calculateSimpleCombinedBalance([acc1, acc2] as any, [transferTx] as any), 700000);
  });

  it('5. Business Rules: Total Income & Total Expense correctly sum without transfer distortion', () => {
    const txs: SharedTransaction[] = [
      { id: '1', amountCents: 500000, type: 'income', accountId: 'acc-cbe', transactionDate: '2026-11-01' },
      { id: '2', amountCents: 150000, type: 'expense', accountId: 'acc-cbe', transactionDate: '2026-11-02' },
      { id: '3', amountCents: 200000, type: 'transfer', accountId: 'acc-cbe', destinationAccountId: 'acc-boa', transactionDate: '2026-11-03' },
      { id: '4', amountCents: 300000, type: 'income', accountId: 'acc-boa', transactionDate: '2026-11-04' },
      { id: '5', amountCents: 50000, type: 'expense', accountId: 'acc-boa', transactionDate: '2026-11-05' },
    ];

    // Total income = 500000 + 300000 = 800000 cents
    assert.strictEqual(calculateSharedTotalIncome(txs), 800000);
    assert.strictEqual(calculateSimpleTotalIncome(txs as any), 800000);

    // Total expense = 150000 + 50000 = 200000 cents
    assert.strictEqual(calculateSharedTotalExpense(txs), 200000);
    assert.strictEqual(calculateSimpleTotalExpense(txs as any), 200000);

    // Account-specific income & expense
    assert.strictEqual(calculateSharedTotalIncome(txs, 'acc-cbe'), 500000);
    assert.strictEqual(calculateSharedTotalExpense(txs, 'acc-cbe'), 150000);
  });

  it('6. Business Rules: Safe deletion guards block deletion of accounts or categories with history', () => {
    const txs: SharedTransaction[] = [
      {
        id: 'tx-used',
        amountCents: 50000,
        type: 'expense',
        accountId: 'acc-cbe',
        categoryId: 'cat-groceries',
        categoryName: 'Groceries',
        transactionDate: '2026-11-07T10:00:00Z',
      },
    ];

    assert.strictEqual(canDeleteSharedAccount('acc-cbe', txs), false, 'Must block deleting account with transactions');
    assert.strictEqual(canDeleteSharedAccount('acc-unused', txs), true, 'Must allow deleting unused account');

    assert.strictEqual(canDeleteSharedCategory('cat-groceries', 'Groceries', txs), false, 'Must block deleting category in use');
    assert.strictEqual(canDeleteSharedCategory('cat-unused', 'Unused', txs), true, 'Must allow deleting unused category');

    // Parity check with doubleEntryFinance
    assert.strictEqual(canDeleteSimpleAccount('acc-cbe', txs as any).canDelete, false);
    assert.strictEqual(canDeleteSimpleAccount('acc-unused', txs as any).canDelete, true);
    assert.strictEqual(canDeleteSimpleCategory('cat-groceries', txs as any).canDelete, false);
    assert.strictEqual(canDeleteSimpleCategory('cat-unused', txs as any).canDelete, true);
  });

  it('7. Transfer Validation rejects identical source and destination accounts or invalid amounts', () => {
    const res1 = validateSharedTransfer('acc-1', 'acc-1', 1000);
    assert.strictEqual(res1.valid, false);
    assert.match(res1.error || '', /cannot be identical/);

    const res2 = validateSharedTransfer('acc-1', 'acc-2', 0);
    assert.strictEqual(res2.valid, false);

    const res3 = validateSharedTransfer('acc-1', 'acc-2', -500);
    assert.strictEqual(res3.valid, false);

    const res4 = validateSharedTransfer('acc-1', 'acc-2', 5000);
    assert.strictEqual(res4.valid, true);
  });

  it('8. Shared State Bridge: Live database state assembly and cross-module synchronization', () => {
    // Test live state assembly fallback to canonical seed when storage is fresh
    const assembled = SharedStateBridge.assembleLiveDatabaseState();
    assert.strictEqual(assembled.schemaVersion, 5);
    assert.strictEqual(assembled.accounts.length, CANONICAL_SEED_DATABASE.accounts.length);
    assert.strictEqual(assembled.categories.length, CANONICAL_SEED_DATABASE.categories.length);
    assert.strictEqual(assembled.transactions.length, CANONICAL_SEED_DATABASE.transactions.length);
    assert.strictEqual(assembled.tasks.length, CANONICAL_SEED_DATABASE.tasks.length);
    assert.strictEqual(assembled.notes.length, CANONICAL_SEED_DATABASE.notes.length);

    // Test round-trip export & import with a populated state
    const testState = {
      ...assembled,
      accounts: [
        {
          id: 'acc-user-1',
          name: 'My CBE Account',
          type: 'asset' as const,
          currencyCode: 'ETB',
          openingBalanceCents: 1500000,
          isArchived: false,
        },
      ],
      transactions: [],
    };
    const exportedJson = SharedStateBridge.exportToAndroidJson(testState);
    assert.ok(exportedJson.length > 200);

    const importResult = SharedStateBridge.importFromAndroidJson(exportedJson);
    assert.strictEqual(importResult.success, true);
    assert.strictEqual(importResult.state?.schemaVersion, 5);
    assert.strictEqual(importResult.state?.accounts[0].name, 'My CBE Account');
    assert.strictEqual(importResult.state?.accounts[0].openingBalanceCents, 1500000);
  });

  it('9. Design Token Cross-Platform Parity: JSON, TypeScript, and Dart expose identical values with zero duplicates', () => {
    const rootDir = process.cwd();
    const jsonTokens = JSON.parse(
      fs.readFileSync(path.join(rootDir, 'shared_foundation', 'design_tokens.json'), 'utf8')
    );
    const dartSource = fs.readFileSync(
      path.join(rootDir, 'flutter_app', 'lib', 'core', 'shared_foundation.dart'),
      'utf8'
    );

    assert.deepStrictEqual(SHARED_DESIGN_TOKENS, jsonTokens, 'TS SHARED_DESIGN_TOKENS must match design_tokens.json');

    // Ensure no duplicate static const names inside SharedDesignTokens
    const sharedDesignTokensBodyMatch = dartSource.match(/class SharedDesignTokens \{([\s\S]*?)\n\}/);
    assert.ok(sharedDesignTokensBodyMatch, 'SharedDesignTokens class must exist in Dart output');
    const dartClassBody = sharedDesignTokensBodyMatch[1];
    const normalizedDartClassBody = dartClassBody.replace(/\s+/g, ' ');
    const declaredFieldNames = Array.from(
      dartClassBody.matchAll(/static const [A-Za-z0-9_<>]+\s+([A-Za-z0-9_]+)\s*=/g),
      (m) => m[1]
    );
    assert.strictEqual(
      new Set(declaredFieldNames).size,
      declaredFieldNames.length,
      'SharedDesignTokens must not declare duplicate field names'
    );

    assert.strictEqual(
      normalizedDartClassBody.includes(`static const String tokenVersion = '${jsonTokens.version}';`),
      true,
      'Missing or mismatched Dart tokenVersion'
    );

    const expectDartColor = (fieldName: string, hex: string) => {
      const expected = `static const Color ${fieldName} = Color(0xFF${hex.slice(1).toUpperCase()});`;
      assert.strictEqual(
        normalizedDartClassBody.includes(expected),
        true,
        `Missing or mismatched Dart color ${fieldName}: expected "${expected}"`
      );
    };

    const expectDartDouble = (fieldName: string, numValue: number) => {
      const expectedNum = Number.isInteger(numValue) ? `${numValue}.0` : `${numValue}`;
      const expected = `static const double ${fieldName} = ${expectedNum};`;
      assert.strictEqual(
        normalizedDartClassBody.includes(expected),
        true,
        `Missing or mismatched Dart double ${fieldName}: expected "${expected}"`
      );
    };

    const { primary, secondary, surface, text, semantic } = jsonTokens.colors;

    // Brand Primary
    expectDartColor('primaryEmerald', primary.emerald);
    expectDartColor('primaryEmeraldDark', primary.emeraldDark);
    expectDartColor('primaryEmeraldLight', primary.emeraldLight);
    expectDartColor('primaryDarkMode', primary.darkMode);
    expectDartColor('onPrimaryLight', primary.onLight);
    expectDartColor('onPrimaryDark', primary.onDark);

    // Brand Secondary
    expectDartColor('secondaryMint', secondary.mint);
    expectDartColor('secondaryMintDark', secondary.mintDark);
    expectDartColor('secondaryMintLight', secondary.mintLight);
    expectDartColor('onSecondaryLight', secondary.onLight);
    expectDartColor('onSecondaryDark', secondary.onDark);

    // Surfaces & Borders
    expectDartColor('canvasLight', surface.canvasLight);
    expectDartColor('canvasDark', surface.canvasDark);
    expectDartColor('surfaceSubtleLight', surface.subtleLight);
    expectDartColor('surfaceSubtleDark', surface.subtleDark);
    expectDartColor('cardLight', surface.cardLight);
    expectDartColor('cardDark', surface.cardDark);
    expectDartColor('elevatedLight', surface.elevatedLight);
    expectDartColor('elevatedDark', surface.elevatedDark);
    expectDartColor('borderLight', surface.borderLight);
    expectDartColor('borderDark', surface.borderDark);
    expectDartColor('dividerLight', surface.dividerLight);
    expectDartColor('dividerDark', surface.dividerDark);

    // Text Hierarchy
    expectDartColor('textPrimaryLight', text.primaryLight);
    expectDartColor('textPrimaryDark', text.primaryDark);
    expectDartColor('textSecondaryLight', text.secondaryLight);
    expectDartColor('textSecondaryDark', text.secondaryDark);
    expectDartColor('textMutedLight', text.mutedLight);
    expectDartColor('textMutedDark', text.mutedDark);
    expectDartColor('textDisabledLight', text.disabledLight);
    expectDartColor('textDisabledDark', text.disabledDark);

    // Semantic Roles
    for (const role of ['income', 'expense', 'transfer', 'success', 'error', 'warning', 'info'] as const) {
      const cap = role.charAt(0).toUpperCase() + role.slice(1);
      expectDartColor(`semantic${cap}`, semantic[role]);
      expectDartColor(`onSemantic${cap}`, semantic[`on${cap}`]);
      expectDartColor(`semantic${cap}ContainerLight`, semantic[`${role}ContainerLight`]);
      expectDartColor(`onSemantic${cap}ContainerLight`, semantic[`on${cap}ContainerLight`]);
      expectDartColor(`semantic${cap}ContainerDark`, semantic[`${role}ContainerDark`]);
      expectDartColor(`onSemantic${cap}ContainerDark`, semantic[`on${cap}ContainerDark`]);
    }

    // Font Families (whitespace normalized above to support dart-formatted wrapping)
    assert.strictEqual(
      normalizedDartClassBody.includes(
        `static const String fontFamilySerif = '${jsonTokens.typography.fontFamilySerif}';`
      ),
      true
    );
    assert.strictEqual(
      normalizedDartClassBody.includes(
        `static const String fontFamilySans = '${jsonTokens.typography.fontFamilySans}';`
      ),
      true
    );
    assert.strictEqual(
      normalizedDartClassBody.includes(
        `static const String fontFamilyMono = '${jsonTokens.typography.fontFamilyMono}';`
      ),
      true
    );

    // Typography Scale (whitespace and optional trailing comma normalized)
    const normalizedForBlocks = normalizedDartClassBody.replace(/,\s*\)/g, ')');
    for (const [role, entry] of Object.entries<any>(jsonTokens.typography.scale)) {
      const cap = role.charAt(0).toUpperCase() + role.slice(1);
      const fontSize = Number.isInteger(entry.fontSize) ? `${entry.fontSize}.0` : `${entry.fontSize}`;
      const lineHeight = Number.isInteger(entry.lineHeight) ? `${entry.lineHeight}.0` : `${entry.lineHeight}`;
      const letterSpacing = Number.isInteger(entry.letterSpacing)
        ? `${entry.letterSpacing}.0`
        : `${entry.letterSpacing}`;
      const expectedBlock = `static const SharedTextStyleToken type${cap} = SharedTextStyleToken( fontSize: ${fontSize}, lineHeight: ${lineHeight}, fontWeight: FontWeight.w${entry.fontWeight}, letterSpacing: ${letterSpacing}, fontFamilyRole: '${entry.fontFamily}', tabularFigures: ${entry.tabularFigures})`;
      assert.strictEqual(
        normalizedForBlocks.includes(expectedBlock),
        true,
        `Missing or mismatched Dart typography token type${cap}`
      );
    }

    // Spacing, Radii, Elevation, Breakpoints
    for (const [k, v] of Object.entries<number>(jsonTokens.spacing)) {
      expectDartDouble(`spacing${k.charAt(0).toUpperCase() + k.slice(1)}`, v);
    }
    for (const [k, v] of Object.entries<number>(jsonTokens.radii)) {
      expectDartDouble(`radius${k.charAt(0).toUpperCase() + k.slice(1)}`, v);
    }
    for (const [k, v] of Object.entries<number>(jsonTokens.elevation)) {
      expectDartDouble(`elevation${k.charAt(0).toUpperCase() + k.slice(1)}`, v);
    }
    for (const [k, v] of Object.entries<number>(jsonTokens.breakpoints)) {
      expectDartDouble(`breakpoint${k.charAt(0).toUpperCase() + k.slice(1)}`, v);
    }
  });

  it('10. Design Token Integrity: Semantic distinctions, monotonic scales, and WCAG AA contrast ratios hold', () => {
    const { primary, secondary, surface, text, semantic } = SHARED_DESIGN_TOKENS.colors;

    // Light vs Dark mode distinction
    assert.notStrictEqual(primary.emerald, primary.darkMode);
    assert.notStrictEqual(primary.onLight, primary.onDark);
    assert.notStrictEqual(surface.canvasLight, surface.canvasDark);
    assert.notStrictEqual(surface.cardLight, surface.cardDark);
    assert.notStrictEqual(surface.borderLight, surface.borderDark);
    assert.notStrictEqual(surface.dividerLight, surface.dividerDark);

    // Text hierarchy values are strictly distinct per theme brightness
    assert.strictEqual(
      new Set([text.primaryLight, text.secondaryLight, text.mutedLight, text.disabledLight]).size,
      4,
      'Light text hierarchy levels must be distinct'
    );
    assert.strictEqual(
      new Set([text.primaryDark, text.secondaryDark, text.mutedDark, text.disabledDark]).size,
      4,
      'Dark text hierarchy levels must be distinct'
    );

    // Financial polarity & system feedback semantic base colors are distinct
    assert.strictEqual(
      new Set([
        semantic.income,
        semantic.expense,
        semantic.transfer,
        semantic.success,
        semantic.error,
        semantic.warning,
        semantic.info,
      ]).size,
      7,
      'All 7 semantic base colors must be distinct'
    );

    // Dark surface elevation luminance progression: canvasDark < subtleDark < cardDark < elevatedDark
    assert.ok(relativeLuminance(surface.canvasDark) < relativeLuminance(surface.subtleDark));
    assert.ok(relativeLuminance(surface.subtleDark) < relativeLuminance(surface.cardDark));
    assert.ok(relativeLuminance(surface.cardDark) < relativeLuminance(surface.elevatedDark));

    // Monotonic numeric scales
    const sp = SHARED_DESIGN_TOKENS.spacing;
    assert.ok(sp.xs < sp.sm && sp.sm < sp.compact && sp.compact < sp.md && sp.md < sp.lg && sp.lg < sp.xl);
    const rd = SHARED_DESIGN_TOKENS.radii;
    assert.ok(rd.sm < rd.md && rd.md < rd.lg && rd.lg < rd.xl && rd.xl < rd.sheet && rd.sheet < rd.full);
    const el = SHARED_DESIGN_TOKENS.elevation;
    assert.ok(el.none < el.low && el.low < el.medium && el.medium < el.high);
    const bp = SHARED_DESIGN_TOKENS.breakpoints;
    assert.ok(bp.medium < bp.expanded && bp.maxContentWidth < bp.maxWideWidth);

    // WCAG AA (>= 4.5:1) contrast checks on paired foreground/background tokens
    const wcagPairs: Array<[string, string, string]> = [
      ['primary.onLight / primary.emerald', primary.onLight, primary.emerald],
      ['primary.onDark / primary.darkMode', primary.onDark, primary.darkMode],
      ['secondary.onLight / secondary.mint', secondary.onLight, secondary.mint],
      ['secondary.onLight / secondary.mintLight', secondary.onLight, secondary.mintLight],
      ['secondary.onDark / secondary.mintDark', secondary.onDark, secondary.mintDark],
      ['text.primaryLight / surface.canvasLight', text.primaryLight, surface.canvasLight],
      ['text.secondaryLight / surface.canvasLight', text.secondaryLight, surface.canvasLight],
      ['text.mutedLight / surface.canvasLight', text.mutedLight, surface.canvasLight],
      ['text.primaryLight / surface.cardLight', text.primaryLight, surface.cardLight],
      ['text.primaryDark / surface.canvasDark', text.primaryDark, surface.canvasDark],
      ['text.secondaryDark / surface.canvasDark', text.secondaryDark, surface.canvasDark],
      ['text.mutedDark / surface.cardDark', text.mutedDark, surface.cardDark],
      ['semantic.onIncome / semantic.income', semantic.onIncome, semantic.income],
      ['semantic.onExpense / semantic.expense', semantic.onExpense, semantic.expense],
      ['semantic.onTransfer / semantic.transfer', semantic.onTransfer, semantic.transfer],
      ['semantic.onSuccess / semantic.success', semantic.onSuccess, semantic.success],
      ['semantic.onError / semantic.error', semantic.onError, semantic.error],
      ['semantic.onWarning / semantic.warning', semantic.onWarning, semantic.warning],
      ['semantic.onInfo / semantic.info', semantic.onInfo, semantic.info],
      ['incomeContainerLight', semantic.onIncomeContainerLight, semantic.incomeContainerLight],
      ['incomeContainerDark', semantic.onIncomeContainerDark, semantic.incomeContainerDark],
      ['expenseContainerLight', semantic.onExpenseContainerLight, semantic.expenseContainerLight],
      ['expenseContainerDark', semantic.onExpenseContainerDark, semantic.expenseContainerDark],
      ['transferContainerLight', semantic.onTransferContainerLight, semantic.transferContainerLight],
      ['transferContainerDark', semantic.onTransferContainerDark, semantic.transferContainerDark],
      ['successContainerLight', semantic.onSuccessContainerLight, semantic.successContainerLight],
      ['successContainerDark', semantic.onSuccessContainerDark, semantic.successContainerDark],
      ['errorContainerLight', semantic.onErrorContainerLight, semantic.errorContainerLight],
      ['errorContainerDark', semantic.onErrorContainerDark, semantic.errorContainerDark],
      ['warningContainerLight', semantic.onWarningContainerLight, semantic.warningContainerLight],
      ['warningContainerDark', semantic.onWarningContainerDark, semantic.warningContainerDark],
      ['infoContainerLight', semantic.onInfoContainerLight, semantic.infoContainerLight],
      ['infoContainerDark', semantic.onInfoContainerDark, semantic.infoContainerDark],
    ];

    for (const [label, fg, bg] of wcagPairs) {
      const ratio = contrastRatio(fg, bg);
      assert.ok(ratio >= 4.5, `WCAG AA contrast failure for ${label}: ${ratio.toFixed(2)}:1 (< 4.5:1)`);
    }
  });

  it('11. Generator Idempotence: Re-running sync_foundation.mjs produces byte-for-byte identical TS and Dart outputs', () => {
    const rootDir = process.cwd();
    const tsFile = path.join(rootDir, 'src', 'domain', 'sharedFoundation.ts');
    const dartFile = path.join(rootDir, 'flutter_app', 'lib', 'core', 'shared_foundation.dart');
    const dartCoreFile = path.join(rootDir, 'flutter_app', 'lib', 'core', 'shared_foundation_core.dart');

    const initialTs = fs.readFileSync(tsFile, 'utf8');
    const initialDart = fs.readFileSync(dartFile, 'utf8');
    const initialDartCore = fs.readFileSync(dartCoreFile, 'utf8');

    execFileSync(process.execPath, [path.join(rootDir, 'scripts', 'sync_foundation.mjs')], {
      cwd: rootDir,
      stdio: 'pipe',
    });

    assert.strictEqual(fs.readFileSync(tsFile, 'utf8'), initialTs, 'TS generated file must be idempotent');
    assert.strictEqual(fs.readFileSync(dartFile, 'utf8'), initialDart, 'Dart UI tokens file must be idempotent');
    assert.strictEqual(fs.readFileSync(dartCoreFile, 'utf8'), initialDartCore, 'Dart pure-core file must be idempotent');
  });

  it('11b. Layer Isolation: Pure-Dart core foundation and domain/application/data layers do not import Flutter UI', () => {
    const rootDir = process.cwd();
    const dartCoreFile = path.join(rootDir, 'flutter_app', 'lib', 'core', 'shared_foundation_core.dart');
    const dartCoreSource = fs.readFileSync(dartCoreFile, 'utf8');

    assert.strictEqual(dartCoreSource.includes('package:flutter/'), false, 'shared_foundation_core.dart must not import Flutter');
    assert.strictEqual(dartCoreSource.includes('dart:ui'), false, 'shared_foundation_core.dart must not import dart:ui');
    assert.strictEqual(dartCoreSource.includes('class SharedBusinessRules'), true);
    assert.strictEqual(dartCoreSource.includes('class CanonicalSeedDatabase'), true);

    const scanDartFiles = (dir: string): string[] => {
      let files: string[] = [];
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) files = files.concat(scanDartFiles(full));
        else if (entry.name.endsWith('.dart')) files.push(full);
      }
      return files;
    };

    for (const layer of ['domain', 'application', 'data']) {
      const layerDir = path.join(rootDir, 'flutter_app', 'lib', layer);
      for (const filePath of scanDartFiles(layerDir)) {
        const content = fs.readFileSync(filePath, 'utf8');
        assert.strictEqual(
          content.includes('shared_foundation.dart'),
          false,
          `${filePath} must import shared_foundation_core.dart instead of UI-coupled shared_foundation.dart`
        );
        assert.strictEqual(
          content.includes('package:flutter/material.dart') || content.includes('dart:ui'),
          false,
          `${filePath} must not import Flutter Material/UI libraries`
        );
      }
    }
  });

  it('12. Generator Validation: Invalid JSON or malformed token schemas fail clearly without silent drift', () => {
    const rootDir = process.cwd();
    const canonical = JSON.parse(
      fs.readFileSync(path.join(rootDir, 'shared_foundation', 'design_tokens.json'), 'utf8')
    );

    // Wrong hex color format
    const badColor = structuredClone(canonical);
    badColor.colors.primary.emerald = 'emerald-green';
    assert.throws(() => validateDesignTokens(badColor), /Invalid color token "colors\.primary\.emerald"/);

    // Wrong spacing token type
    const badSpacing = structuredClone(canonical);
    badSpacing.spacing.md = '16px';
    assert.throws(() => validateDesignTokens(badSpacing), /Invalid token "spacing\.md"/);

    // Missing required semantic token
    const missingSemantic = structuredClone(canonical);
    delete missingSemantic.colors.semantic.onSuccess;
    assert.throws(() => validateDesignTokens(missingSemantic), /Missing required color token "colors\.semantic\.onSuccess"/);

    // CLI fails cleanly with non-zero exit when design_tokens.json contains invalid JSON
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'daywell-sync-test-'));
    try {
      const sfDir = path.join(tmpDir, 'shared_foundation');
      fs.mkdirSync(sfDir, { recursive: true });
      fs.copyFileSync(
        path.join(rootDir, 'shared_foundation', 'schema_contracts.json'),
        path.join(sfDir, 'schema_contracts.json')
      );
      fs.copyFileSync(
        path.join(rootDir, 'shared_foundation', 'business_rules.json'),
        path.join(sfDir, 'business_rules.json')
      );
      fs.copyFileSync(
        path.join(rootDir, 'shared_foundation', 'canonical_seed_database.json'),
        path.join(sfDir, 'canonical_seed_database.json')
      );
      fs.writeFileSync(path.join(sfDir, 'design_tokens.json'), '{ invalid json', 'utf8');

      const res = spawnSync(
        process.execPath,
        [path.join(rootDir, 'scripts', 'sync_foundation.mjs'), '--root', tmpDir],
        { encoding: 'utf8' }
      );
      assert.notStrictEqual(res.status, 0, 'CLI must exit non-zero on invalid JSON');
      assert.match(res.stderr, /Invalid JSON in design_tokens\.json/);
      assert.throws(() => syncFoundation({ rootDir: tmpDir, silent: true }), /Invalid JSON in design_tokens\.json/);
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});
