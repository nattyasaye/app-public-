import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import {
  SYSTEM_CONTROL_ACCOUNT_IDS,
  SharedAccount,
  SharedBudget,
  SharedRecurringRule,
  SharedCommitment,
  SharedSavingsGoal,
} from './sharedFoundation';

describe('STAGE 4.1: CANONICAL V6 FINANCE SCHEMA CONTRACTS & CONTROL ACCOUNTS', () => {
  it('1. schema_contracts.json defines v6 entities and AccountSubType taxonomy', () => {
    const schemaPath = path.join(
      process.cwd(),
      'shared_foundation',
      'schema_contracts.json'
    );
    const schema = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));

    assert.strictEqual(schema.schemaVersion, 13);
    assert.ok(schema.entities.Account.fields.subType);
    assert.ok(schema.entities.Account.fields.isSystem);
    assert.strictEqual(schema.entities.Account.fields.openingBalanceCents.minimum, undefined);
    assert.ok(schema.entities.Category.fields.parentId);
    assert.ok(schema.entities.Category.fields.sortOrder);
    assert.ok(schema.entities.Commitment.fields.linkedDebtId);
    assert.ok(schema.entities.Commitment.fields.settlementEntryId);
    assert.ok(schema.entities.Commitment.fields.direction);
    assert.ok(schema.entities.Commitment.fields.legacyPaidUnverified);
    assert.ok(schema.entities.CommitmentSettlement);
    assert.ok(schema.entities.SavingsGoal.fields.linkedAccountId);
    assert.ok(schema.entities.SavingsGoal.fields.status);
    assert.ok(schema.entities.Budget);
    assert.ok(schema.entities.RecurringRule);
    assert.ok(schema.entities.Project.fields.isArchived);
    assert.ok(schema.entities.Project.fields.startDate);
    assert.ok(schema.entities.Project.fields.customFields);
    assert.ok(schema.entities.ProjectTrackingBlock);
    assert.ok(schema.entities.ProjectTrackingRecord);

    const subTypeEnum: string[] = schema.entities.Account.fields.subType.enum;
    for (const requiredSubType of [
      'cash',
      'bank',
      'mobile_money',
      'savings_vault',
      'credit_card',
      'receivable',
      'payable',
      'opening_equity',
      'nominal_income',
      'nominal_expense',
      'legacy_clearing',
    ]) {
      assert.ok(
        subTypeEnum.includes(requiredSubType),
        `Missing subType ${requiredSubType}`
      );
    }
  });

  it('2. System control account IDs and v7 TypeScript contracts match Flutter domain contracts', () => {
    assert.strictEqual(SYSTEM_CONTROL_ACCOUNT_IDS.equity, 'acc-sys-equity');
    assert.strictEqual(SYSTEM_CONTROL_ACCOUNT_IDS.income, 'acc-sys-income');
    assert.strictEqual(SYSTEM_CONTROL_ACCOUNT_IDS.expense, 'acc-sys-expense');
    assert.strictEqual(
      SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
      'acc-sys-receivable'
    );
    assert.strictEqual(SYSTEM_CONTROL_ACCOUNT_IDS.payable, 'acc-sys-payable');
    assert.strictEqual(
      SYSTEM_CONTROL_ACCOUNT_IDS.legacyOffset,
      'acc-sys-legacy-offset'
    );

    const vaultAccount: SharedAccount = {
      id: 'acc-vault-1',
      name: 'Emergency Vault',
      type: 'asset',
      subType: 'savings_vault',
      isSystem: false,
      currencyCode: 'ETB',
      openingBalanceCents: 0,
      isArchived: false,
    };
    const goal: SharedSavingsGoal = {
      id: 'sav-vault-1',
      title: 'Emergency Fund',
      targetCents: 5000000,
      currentAllocatedCents: 800000,
      linkedAccountId: vaultAccount.id,
      status: 'active',
    };
    const commitment: SharedCommitment = {
      id: 'com-rent-1',
      title: 'Apartment Rent',
      amountCents: 800000,
      dueDate: '2026-11-28',
      isPaid: false,
      linkedAccountId: 'acc-cbe',
      categoryId: 'cat-housing',
      direction: 'outflow',
      legacyPaidUnverified: false,
    };
    const budget: SharedBudget = {
      id: 'bud-food-2026-11',
      categoryId: 'cat-food',
      monthIso: '2026-11',
      limitCents: 600000,
      rolloverEnabled: false,
      createdAt: '2026-11-01T00:00:00.000Z',
      updatedAt: '2026-11-01T00:00:00.000Z',
    };
    const recurring: SharedRecurringRule = {
      id: 'rec-rent-1',
      title: 'Monthly Rent',
      ruleType: 'commitment',
      amountCents: 800000,
      frequency: 'monthly',
      interval: 1,
      startDate: '2026-11-01',
      nextOccurrenceDate: '2026-12-01',
      accountId: 'acc-cbe',
      categoryId: 'cat-housing',
      isActive: true,
      autoPost: false,
      createdAt: '2026-11-01T00:00:00.000Z',
    };

    assert.strictEqual(vaultAccount.subType, 'savings_vault');
    assert.strictEqual(goal.linkedAccountId, 'acc-vault-1');
    assert.strictEqual(goal.status, 'active');
    assert.strictEqual(commitment.categoryId, 'cat-housing');
    assert.strictEqual(commitment.direction, 'outflow');
    assert.strictEqual(budget.monthIso, '2026-11');
    assert.strictEqual(recurring.ruleType, 'commitment');
  });
});
