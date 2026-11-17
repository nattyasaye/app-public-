import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/domain/finance/double_entry_engine.dart';
import 'package:personal_management_app/domain/finance/finance_models.dart';
import 'package:personal_management_app/domain/finance/financial_engine.dart';
import 'package:personal_management_app/domain/finance/recurring_engine.dart';

void main() {
  group('Stage 4.1 — Stage 4.0.5 V7 Domain Scenarios (Option 1 + ETB)', () {
    late AccountModel cbe;
    late AccountModel cash;
    late AccountModel vault;
    late AccountModel creditCard;
    late AccountModel usdAccount;
    late AccountModel sysEquity;
    late AccountModel sysIncome;
    late AccountModel sysExpense;
    late AccountModel sysReceivable;
    late AccountModel sysPayable;

    setUp(() {
      cbe = AccountModel(
        id: 'acc-cbe',
        name: 'CBE',
        type: AccountType.asset,
        subType: AccountSubType.bank,
        currencyCode: 'ETB',
      );
      cash = AccountModel(
        id: 'acc-cash',
        name: 'Cash',
        type: AccountType.asset,
        subType: AccountSubType.cash,
        currencyCode: 'ETB',
      );
      vault = AccountModel(
        id: 'acc-vault',
        name: 'Emergency Vault',
        type: AccountType.asset,
        subType: AccountSubType.savingsVault,
        currencyCode: 'ETB',
      );
      creditCard = AccountModel(
        id: 'acc-cc',
        name: 'Visa Card',
        type: AccountType.liability,
        subType: AccountSubType.creditCard,
        currencyCode: 'ETB',
      );
      usdAccount = AccountModel(
        id: 'acc-usd',
        name: 'USD Checking',
        type: AccountType.asset,
        subType: AccountSubType.bank,
        currencyCode: 'USD',
      );
      sysEquity = AccountModel(
        id: SystemControlAccounts.equity,
        name: 'Opening Equity',
        type: AccountType.equity,
        subType: AccountSubType.openingEquity,
        isSystem: true,
      );
      sysIncome = AccountModel(
        id: SystemControlAccounts.income,
        name: 'Income Control',
        type: AccountType.income,
        subType: AccountSubType.nominalIncome,
        isSystem: true,
      );
      sysExpense = AccountModel(
        id: SystemControlAccounts.expense,
        name: 'Expense Control',
        type: AccountType.expense,
        subType: AccountSubType.nominalExpense,
        isSystem: true,
      );
      sysReceivable = AccountModel(
        id: SystemControlAccounts.receivable,
        name: 'Receivable Control',
        type: AccountType.asset,
        subType: AccountSubType.receivable,
        isSystem: true,
      );
      sysPayable = AccountModel(
        id: SystemControlAccounts.payable,
        name: 'Payable Control',
        type: AccountType.liability,
        subType: AccountSubType.payable,
        isSystem: true,
      );
    });

    test(
      'Scenarios 7–8 (Option 1): Overpaid credit card prepaid credit IS included '
      'in AvailableToSpend(H) and NetPosition and tracked separately',
      () {
        final openCbe = DoubleEntryEngine.buildOpeningBalance(
          entryId: 'e-open-cbe',
          account: cbe,
          overrideAmountCents: 500000, // 5,000 ETB
          date: '2026-11-01',
        );
        // Credit card overpaid by 1,000 ETB -> openingBalanceCents = -100000
        final openCardOverpaid = DoubleEntryEngine.buildOpeningBalance(
          entryId: 'e-open-cc',
          account: creditCard,
          overrideAmountCents: -100000,
          date: '2026-11-01',
        );

        final accounts = [
          cbe,
          cash,
          creditCard,
          usdAccount,
          sysEquity,
          sysIncome,
          sysExpense,
          sysReceivable,
          sysPayable,
        ];
        final entries = [
          openCbe['entry'] as JournalEntryModel,
          openCardOverpaid['entry'] as JournalEntryModel,
        ];
        final postings = [
          ...openCbe['postings'] as List<PostingModel>,
          ...openCardOverpaid['postings'] as List<PostingModel>,
        ];

        final cardBal = DoubleEntryEngine.calculateAccountBalance(
          account: creditCard,
          postings: postings,
          entries: entries,
        );
        expect(cardBal, -100000);

        final breakdown = DoubleEntryEngine.calculateAvailableToSpendBreakdown(
          accounts: accounts,
          postings: postings,
          entries: entries,
          debts: const [],
          commitments: const [],
          savingsGoals: const [],
          periodEndIso: '2026-11-30',
        );
        expect(breakdown.liquidCashCents, 500000);
        expect(breakdown.prepaidCardCreditCents, 100000);
        expect(breakdown.shortTermCreditOwedCents, 0);
        // Option 1: 5,000 + 1,000 = 6,000 ETB
        expect(breakdown.availableToSpendCents, 600000);
        expect(breakdown.nonEtbAccountCount, 1);

        final netPos = DoubleEntryEngine.calculateNetPosition(
          accounts: accounts,
          postings: postings,
          entries: entries,
        );
        // Net position includes 1,000 ETB prepaid credit -> 6,000 ETB
        expect(netPos, 600000);
      },
    );

    test(
      'Scenario 9–11: Partial outflow commitments, inflow = 0 until received, '
      'legacyPaidUnverified = 0, and archived savings goal = 0 reserve',
      () {
        final openCbe = DoubleEntryEngine.buildOpeningBalance(
          entryId: 'e-open-cbe',
          account: cbe,
          overrideAmountCents: 1000000, // 10,000 ETB
          date: '2026-11-01',
        );
        final accounts = [cbe, vault, sysEquity, sysIncome, sysExpense];
        final entries = [openCbe['entry'] as JournalEntryModel];
        final postings = [...openCbe['postings'] as List<PostingModel>];

        // Partial bill: 2,000 ETB total, 500 ETB already paid -> 1,500 remaining
        final partialOutflow = CommitmentModel(
          id: 'com-partial',
          title: 'Internet Bundle',
          amountCents: 200000,
          verifiedSettledCents: 50000,
          dueDate: CalendarDate(year: 2026, month: 11, day: 20),
          direction: CommitmentDirection.outflow,
          linkedAccountId: cbe.id,
        );
        expect(partialOutflow.status, CommitmentStatus.partial);
        expect(partialOutflow.remainingCents, 150000);

        // Expected inflow: 5,000 ETB -> contributes 0 until received
        final pendingInflow = CommitmentModel(
          id: 'com-inflow',
          title: 'Freelance Milestone',
          amountCents: 500000,
          dueDate: CalendarDate(year: 2026, month: 11, day: 25),
          direction: CommitmentDirection.inflow,
          linkedAccountId: cbe.id,
        );
        expect(pendingInflow.isInflow, isTrue);

        // Legacy unverified paid row: must be excluded from AvailableToSpend
        final legacyPaid = CommitmentModel(
          id: 'com-legacy',
          title: 'Old Water Bill',
          amountCents: 30000,
          dueDate: CalendarDate(year: 2026, month: 11, day: 10),
          isPaid: true,
          legacyPaidUnverified: true,
        );
        expect(legacyPaid.status, CommitmentStatus.legacyUnverifiedPaid);
        expect(legacyPaid.remainingCents, 0);

        // Overfunded active virtual savings (1,200 reserved even if target=1,000)
        // vs archived virtual savings (0 reserved)
        final overfundedVirtual = SavingsGoalModel(
          id: 'sg-over',
          title: 'Overfunded Fund',
          targetCents: 100000,
          currentAllocatedCents: 120000,
          status: SavingsGoalStatus.active,
        );
        final archivedVirtual = SavingsGoalModel(
          id: 'sg-arch',
          title: 'Archived Fund',
          targetCents: 100000,
          currentAllocatedCents: 100000,
          status: SavingsGoalStatus.archived,
        );
        expect(overfundedVirtual.isOverfunded, isTrue);
        expect(archivedVirtual.isArchived, isTrue);

        final breakdown = DoubleEntryEngine.calculateAvailableToSpendBreakdown(
          accounts: accounts,
          postings: postings,
          entries: entries,
          debts: const [],
          commitments: [partialOutflow, pendingInflow, legacyPaid],
          savingsGoals: [overfundedVirtual, archivedVirtual],
          periodEndIso: '2026-11-30',
        );
        expect(breakdown.dueNonDebtCommitmentsCents, 150000);
        expect(breakdown.virtualSavingsReservedCents, 120000);
        expect(breakdown.unverifiedLegacyPaidCount, 1);
        // 10,000 - 1,500 - 1,200 = 7,300 ETB (inflow 5,000 & legacy 300 excluded)
        expect(breakdown.availableToSpendCents, 730000);
      },
    );

    test(
        'ETB-only filter excludes non-ETB account from LiquidCash and NetPosition',
        () {
      final openEtb = DoubleEntryEngine.buildOpeningBalance(
        entryId: 'e-etb',
        account: cash,
        overrideAmountCents: 400000,
        date: '2026-11-01',
      );
      final openUsd = DoubleEntryEngine.buildOpeningBalance(
        entryId: 'e-usd',
        account: usdAccount,
        overrideAmountCents: 900000,
        date: '2026-11-01',
      );
      final accounts = [cash, usdAccount, sysEquity];
      final entries = [
        openEtb['entry'] as JournalEntryModel,
        openUsd['entry'] as JournalEntryModel,
      ];
      final postings = [
        ...openEtb['postings'] as List<PostingModel>,
        ...openUsd['postings'] as List<PostingModel>,
      ];

      expect(
        DoubleEntryEngine.calculateLiquidCash(
          accounts: accounts,
          postings: postings,
          entries: entries,
        ),
        400000,
      );
      expect(
        DoubleEntryEngine.calculateNetPosition(
          accounts: accounts,
          postings: postings,
          entries: entries,
        ),
        400000,
      );
    });

    test('Debt settlement validates over-allocation, inactive status, and fees',
        () {
      final debt = DebtModel(
        id: 'd-1',
        originEntryId: 'e-orig',
        partyId: 'p-1',
        debtType: DebtType.payable,
        principalCents: 100000,
        outstandingCents: 40000,
        status: DebtStatus.active,
      );

      expect(
        () => DoubleEntryEngine.buildDebtSettlement(
          settlementEntryId: 'e-over',
          debt: debt,
          settlementAssetAccountId: cbe.id,
          debtAccountId: SystemControlAccounts.payable,
          allocatedPrincipalCents: 50000,
          settlementDate: '2026-11-10',
          description: 'Overpay',
        ),
        throwsA(isA<DoubleEntryValidationError>()),
      );

      final voidedDebt = debt.copyWith(status: DebtStatus.voided);
      expect(
        () => DoubleEntryEngine.buildDebtSettlement(
          settlementEntryId: 'e-voided',
          debt: voidedDebt,
          settlementAssetAccountId: cbe.id,
          debtAccountId: SystemControlAccounts.payable,
          allocatedPrincipalCents: 10000,
          settlementDate: '2026-11-10',
          description: 'Voided debt',
        ),
        throwsA(isA<DoubleEntryValidationError>()),
      );

      final valid = DoubleEntryEngine.buildDebtSettlement(
        settlementEntryId: 'e-valid',
        debt: debt,
        settlementAssetAccountId: cbe.id,
        debtAccountId: SystemControlAccounts.payable,
        allocatedPrincipalCents: 40000,
        interestCents: 1500,
        interestAccountId: SystemControlAccounts.expense,
        feeCents: 500,
        feeAccountId: SystemControlAccounts.expense,
        settlementDate: '2026-11-10',
        description: 'Payoff with interest and fee',
      );
      final updated = valid['updatedDebt'] as DebtModel;
      expect(updated.status, DebtStatus.settled);
      expect(updated.outstandingCents, 0);
      final postings = valid['postings'] as List<PostingModel>;
      DoubleEntryEngine.validateBalancedEntry(postings);
    });

    test(
        'buildCommitmentReceipt generates balanced asset debit & income credit',
        () {
      final receipt = DoubleEntryEngine.buildCommitmentReceipt(
        entryId: 'e-rcpt-1',
        destAccountId: cbe.id,
        categoryId: 'cat-inc-salary',
        amountCents: 350000,
        date: '2026-11-15',
        commitmentTitle: 'Consulting Retainer',
      );
      final postings = receipt['postings'] as List<PostingModel>;
      DoubleEntryEngine.validateBalancedEntry(postings);
      expect(
        DoubleEntryEngine.calculateAccountBalance(
          account: cbe,
          postings: postings,
        ),
        350000,
      );
    });

    test('RecurringEngine pause/resume >= today and skipNext work cleanly', () {
      final rule = RecurringRuleModel(
        id: 'rec-1',
        title: 'Rent',
        ruleType: RecurringRuleType.commitment,
        amountCents: 800000,
        frequency: RecurrenceFrequency.monthly,
        startDate: CalendarDate(year: 2026, month: 8, day: 1),
        nextOccurrenceDate: CalendarDate(year: 2026, month: 9, day: 1),
        endDate: CalendarDate(year: 2026, month: 12, day: 31),
        isActive: false,
      );

      final resumedDate = RecurringEngine.advanceNextOnOrAfter(
        nextOccurrenceDate: rule.nextOccurrenceDate,
        frequency: rule.frequency,
        today: CalendarDate(year: 2026, month: 11, day: 10),
      );
      expect(resumedDate.toIsoString(), '2026-12-01');

      final skipped = RecurringEngine.skipNext(
        rule: rule.copyWith(isActive: true),
      );
      expect(skipped.nextOccurrenceDate.toIsoString(), '2026-10-01');
      expect(skipped.isActive, isTrue);

      final expireOnSkip = RecurringEngine.skipNext(
        rule: rule.copyWith(
          isActive: true,
          nextOccurrenceDate: CalendarDate(year: 2026, month: 12, day: 1),
        ),
      );
      expect(expireOnSkip.isActive, isFalse);
    });

    test(
        'Stage 2.2: AccountModel.fromJson preserves omitted user currencyCode as empty and FinancialEngine.formatBirr labels tiers cleanly',
        () {
      final userMissingCurrency = AccountModel.fromJson(const {
        'id': 'acc-user-legacy',
        'name': 'Legacy Wallet',
        'type': 'asset',
      });
      expect(userMissingCurrency.isSystem, isFalse);
      expect(userMissingCurrency.currencyCode, '');
      expect(
        DoubleEntryEngine.classifyCurrencyCode(userMissingCurrency.currencyCode),
        CurrencyValidationTier.unverified,
      );

      final sysMissingCurrency = AccountModel.fromJson(const {
        'id': SystemControlAccounts.equity,
        'name': 'Opening Equity',
        'type': 'equity',
      });
      expect(sysMissingCurrency.isSystem, isTrue);
      expect(sysMissingCurrency.currencyCode, 'ETB');

      expect(FinancialEngine.formatBirr(25050), '250.50 ETB');
      expect(
        FinancialEngine.formatBirr(25050, currencyCode: 'etb'),
        '250.50 ETB',
      );
      expect(
        FinancialEngine.formatBirr(25050, currencyCode: 'usd'),
        '250.50 USD',
      );
      expect(
        FinancialEngine.formatBirr(25050, currencyCode: ''),
        '250.50 (Unverified)',
      );
      expect(
        FinancialEngine.formatBirr(25050, currencyCode: 'XYZ'),
        '250.50 (Unverified)',
      );
    });
  });
}
