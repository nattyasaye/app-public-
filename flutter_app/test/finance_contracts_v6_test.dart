import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/domain/finance/finance_contracts.dart';

void main() {
  group('Stage 4.1 V6 Finance Domain Models & Contracts', () {
    test(
        'AccountSubType taxonomy classifies liquid, vault, credit, and system accounts',
        () {
      expect(AccountSubType.cash.isLiquid, isTrue);
      expect(AccountSubType.bank.isLiquid, isTrue);
      expect(AccountSubType.mobileMoney.isLiquid, isTrue);
      expect(AccountSubType.savingsVault.isLiquid, isFalse);
      expect(AccountSubType.savingsVault.isSavingsVault, isTrue);
      expect(AccountSubType.creditCard.isLiquid, isFalse);
      expect(AccountSubType.creditCard.isCreditCard, isTrue);
      expect(AccountSubType.receivable.isSystemControl, isTrue);
      expect(AccountSubType.payable.isSystemControl, isTrue);
      expect(AccountSubType.openingEquity.isSystemControl, isTrue);
      expect(AccountSubType.nominalIncome.isSystemControl, isTrue);
      expect(AccountSubType.nominalExpense.isSystemControl, isTrue);
      expect(AccountSubType.legacyClearing.isSystemControl, isTrue);

      expect(
        AccountSubType.fromDbValue('mobile_money'),
        AccountSubType.mobileMoney,
      );
      expect(
        AccountSubType.fromDbValue('savings_vault'),
        AccountSubType.savingsVault,
      );
      expect(
        AccountSubType.fromDbValue('credit_card'),
        AccountSubType.creditCard,
      );
    });

    test('AccountModel and JournalEntryModel round-trip v6 fields safely', () {
      final sysIncome = AccountModel(
        id: SystemControlAccounts.income,
        name: 'System Income Control',
        type: AccountType.income,
        subType: AccountSubType.nominalIncome,
      );
      expect(sysIncome.isSystem, isTrue);

      final vault = AccountModel(
        id: 'acc-vault-1',
        name: 'Emergency Vault',
        type: AccountType.asset,
        subType: AccountSubType.savingsVault,
      );
      expect(vault.isSystem, isFalse);
      final vaultDecoded = AccountModel.fromJson(vault.toJson());
      expect(vaultDecoded.subType, AccountSubType.savingsVault);
      expect(vaultDecoded.isSystem, isFalse);

      final entry = JournalEntryModel(
        id: 'entry-1',
        entryType: EntryType.standard,
        description: 'Lunch',
        occurrenceDate: '2026-11-15',
        legacySourceTxId: 'tx-legacy-1',
        correctedFromEntryId: 'entry-0',
      );
      final entryDecoded = JournalEntryModel.fromJson(entry.toJson());
      expect(entryDecoded.legacySourceTxId, 'tx-legacy-1');
      expect(entryDecoded.correctedFromEntryId, 'entry-0');
    });

    test(
        'BudgetModel, RecurringRuleModel, CommitmentModel, and SavingsGoalModel serialize cleanly',
        () {
      final category = TransactionCategoryModel(
        id: 'cat-coffee',
        name: 'Coffee & Tea',
        type: 'expense',
        parentId: 'cat-food',
        sortOrder: 2,
      );
      final catDecoded = TransactionCategoryModel.fromJson(category.toJson());
      expect(catDecoded.parentId, 'cat-food');
      expect(catDecoded.sortOrder, 2);

      final commitment = CommitmentModel(
        id: 'com-1',
        title: 'Landlord Loan',
        amountCents: 300000,
        dueDate: CalendarDate(year: 2026, month: 11, day: 25),
        linkedAccountId: 'acc-cbe',
        categoryId: 'cat-housing',
        linkedDebtId: 'debt-1',
        settlementEntryId: 'entry-settle-1',
        recurringRuleId: 'rec-1',
      );
      final comDecoded = CommitmentModel.fromJson(commitment.toJson());
      expect(comDecoded.linkedDebtId, 'debt-1');
      expect(comDecoded.settlementEntryId, 'entry-settle-1');
      expect(comDecoded.recurringRuleId, 'rec-1');

      final goal = SavingsGoalModel(
        id: 'sav-1',
        title: 'Emergency Fund',
        targetCents: 1000000,
        currentAllocatedCents: 250000,
        linkedAccountId: 'acc-vault-1',
      );
      expect(goal.isVaultLinked, isTrue);
      final goalDecoded = SavingsGoalModel.fromJson(goal.toJson());
      expect(goalDecoded.linkedAccountId, 'acc-vault-1');

      final budget = BudgetModel(
        id: 'bud-1',
        categoryId: 'cat-food',
        monthIso: '2026-11',
        limitCents: 500000,
        rolloverEnabled: true,
      );
      final budDecoded = BudgetModel.fromJson(budget.toJson());
      expect(budDecoded.monthIso, '2026-11');
      expect(budDecoded.limitCents, 500000);
      expect(budDecoded.rolloverEnabled, isTrue);

      final rule = RecurringRuleModel(
        id: 'rec-1',
        title: 'Rent',
        ruleType: RecurringRuleType.commitment,
        amountCents: 800000,
        frequency: RecurrenceFrequency.monthly,
        startDate: CalendarDate(year: 2026, month: 11, day: 1),
        nextOccurrenceDate: CalendarDate(year: 2026, month: 12, day: 1),
        accountId: 'acc-cbe',
        categoryId: 'cat-housing',
      );
      final ruleDecoded = RecurringRuleModel.fromJson(rule.toJson());
      expect(ruleDecoded.ruleType, RecurringRuleType.commitment);
      expect(ruleDecoded.frequency, RecurrenceFrequency.monthly);
      expect(ruleDecoded.nextOccurrenceDate.toIsoString(), '2026-12-01');
    });
  });
}
