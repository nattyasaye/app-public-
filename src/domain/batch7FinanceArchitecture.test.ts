import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';

describe('DAYWELL FINANCE MODULE ARCHITECTURE & BOUNDARIES AUDIT (PROMPT 2.3)', () => {
  const rootDir = process.cwd();
  const libDir = path.join(rootDir, 'flutter_app', 'lib');
  const domainFinanceDir = path.join(libDir, 'domain', 'finance');
  const appFinanceDir = path.join(libDir, 'application', 'finance');
  const repoFinancePath = path.join(libDir, 'data', 'repositories', 'finance_repository.dart');

  it('1. Domain Layer Isolation: domain/finance/ contains zero Drift, SQLite, or Flutter widget imports', () => {
    assert.strictEqual(fs.existsSync(domainFinanceDir), true, 'domain/finance directory must exist');

    const domainFiles = fs.readdirSync(domainFinanceDir).filter((f) => f.endsWith('.dart'));
    assert.strictEqual(domainFiles.length >= 3, true, 'Must have at least contracts, double_entry, and financial_engine');

    for (const f of domainFiles) {
      const fullPath = path.join(domainFinanceDir, f);
      const content = fs.readFileSync(fullPath, 'utf8');

      // Domain must not depend on Drift or SQLite
      assert.strictEqual(
        content.includes('package:drift'),
        false,
        `Domain file ${f} must NOT import Drift`
      );
      assert.strictEqual(
        content.includes('package:flutter/material.dart') || content.includes('package:flutter/widgets.dart'),
        false,
        `Domain file ${f} must NOT import Flutter UI widgets`
      );
      assert.strictEqual(
        content.includes('package:sqflite'),
        false,
        `Domain file ${f} must NOT import sqflite`
      );
    }
  });

  it('2. Repository Contract Decomposition: finance_contracts.dart defines cohesive sub-contracts and unified IFinanceRepository', () => {
    const contractsPath = path.join(domainFinanceDir, 'finance_contracts.dart');
    assert.strictEqual(fs.existsSync(contractsPath), true, 'finance_contracts.dart must exist in domain layer');
    const content = fs.readFileSync(contractsPath, 'utf8');

    // Sub-contracts
    assert.strictEqual(content.includes('abstract class IAccountRepositoryContract'), true);
    assert.strictEqual(content.includes('abstract class ICategoryRepositoryContract'), true);
    assert.strictEqual(content.includes('abstract class ITransactionRepositoryContract'), true);
    assert.strictEqual(content.includes('abstract class IDebtRepositoryContract'), true);

    // Unified interface implementing all sub-contracts
    assert.strictEqual(content.includes('abstract class IFinanceRepository'), true);
    assert.strictEqual(content.includes('implements'), true);
    assert.strictEqual(content.includes('IAccountRepositoryContract'), true);
    assert.strictEqual(content.includes('ITransactionRepositoryContract'), true);
  });

  it('3. Data Layer Implementation: DriftFinanceRepository implements IFinanceRepository with atomic transactions and safety guards', () => {
    assert.strictEqual(fs.existsSync(repoFinancePath), true, 'finance_repository.dart must exist in data layer');
    const content = fs.readFileSync(repoFinancePath, 'utf8');

    // Implements IFinanceRepository
    assert.strictEqual(content.includes('class DriftFinanceRepository implements IFinanceRepository'), true);

    // Queries double-entry tables
    assert.strictEqual(content.includes('_db.accountsTable'), true);
    assert.strictEqual(content.includes('_db.journalEntriesTable'), true);
    assert.strictEqual(content.includes('_db.postingsTable'), true);
    assert.strictEqual(content.includes('_db.debtsTable'), true);
    assert.strictEqual(content.includes('_db.settlementAllocationsTable'), true);

    // Enforces atomic database transactions
    assert.strictEqual(content.includes('_db.transaction('), true);

    // Invariant validation: Debits == Credits
    assert.strictEqual(content.includes('DoubleEntryEngine.validateBalancedEntry'), true);

    // Safe deletion guards
    assert.strictEqual(content.includes('hasPostings != null'), true);
  });

  it('4. Application Layer Encapsulation: FinanceController and FinanceModuleState decouple workflows from UI', () => {
    const controllerPath = path.join(appFinanceDir, 'finance_controller.dart');
    const statePath = path.join(appFinanceDir, 'finance_state.dart');

    assert.strictEqual(fs.existsSync(controllerPath), true, 'finance_controller.dart must exist');
    assert.strictEqual(fs.existsSync(statePath), true, 'finance_state.dart must exist');

    const controllerContent = fs.readFileSync(controllerPath, 'utf8');
    const stateContent = fs.readFileSync(statePath, 'utf8');

    // Controller depends on IFinanceRepository abstraction, not Drift
    assert.strictEqual(contentIncludesAny(controllerContent, ['IFinanceRepository']), true);
    assert.strictEqual(controllerContent.includes('package:drift'), false, 'Controller must NOT import Drift directly');

    // State is immutable and exposes domain calculations
    assert.strictEqual(stateContent.includes('class FinanceModuleState'), true);
    assert.strictEqual(stateContent.includes('liquidCashCents'), true);
    assert.strictEqual(stateContent.includes('netFinancialPositionCents'), true);
    assert.strictEqual(stateContent.includes('availableToSpendCents'), true);
  });

  it('5. AppStateManager Integration: Composes and hydrates FinanceController from SQLite without sync bridges', () => {
    const appStatePath = path.join(libDir, 'ui', 'app_state.dart');
    const content = fs.readFileSync(appStatePath, 'utf8');

    assert.strictEqual(
      content.includes('late final FinanceController financeController;') ||
        content.includes('late FinanceController financeController;'),
      true
    );
    assert.strictEqual(content.includes('financeController = FinanceController('), true);
    assert.strictEqual(content.includes('financeController.loadAll()'), true);
    assert.strictEqual(content.includes('_syncFinanceController'), false);
    assert.strictEqual(content.includes('List<AccountModel> accounts = []'), false);
  });

  it('6. Presentation Layer: FinanceView supports direct FinanceController injection', () => {
    const viewPath = path.join(libDir, 'ui', 'screens', 'finance_view.dart');
    const content = fs.readFileSync(viewPath, 'utf8');

    assert.strictEqual(content.includes('final FinanceController? controller;'), true);
    assert.strictEqual(content.includes('FinanceController get effectiveController'), true);
  });
});

function contentIncludesAny(content: string, patterns: string[]): boolean {
  return patterns.some((p) => content.includes(p));
}
