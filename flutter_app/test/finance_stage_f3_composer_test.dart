import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/finance/finance_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';
import 'package:personal_management_app/domain/finance/double_entry_engine.dart';
import 'package:personal_management_app/domain/finance/finance_models.dart';
import 'package:personal_management_app/ui/screens/finance/finance_composer_sheet.dart';
import 'package:personal_management_app/ui/screens/finance/finance_formatters.dart';
import 'package:personal_management_app/ui/widgets/shared_ui_widgets.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Finance Stage F3 — Composer Parity, Ledger Workflows & Validation',
      () {
    late AppDatabase db;
    late DriftFinanceRepository repo;
    late FinanceController controller;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.ensureInitialized();
      repo = DriftFinanceRepository(db);
      controller = FinanceController(repository: repo);
      await controller.completeSetup([
        AccountModel(
          id: 'acc-bank',
          name: 'CBE Checking',
          type: AccountType.asset,
          subType: AccountSubType.bank,
          currencyCode: 'ETB',
          openingBalanceCents: 1000000,
          openingBalanceDate: '2026-11-01',
        ),
        AccountModel(
          id: 'acc-cash',
          name: 'Cash Wallet',
          type: AccountType.asset,
          subType: AccountSubType.cash,
          currencyCode: 'ETB',
          openingBalanceCents: 300000,
          openingBalanceDate: '2026-11-01',
        ),
        AccountModel(
          id: 'acc-vault',
          name: 'Emergency Vault',
          type: AccountType.asset,
          subType: AccountSubType.savingsVault,
          currencyCode: 'ETB',
          openingBalanceCents: 500000,
          openingBalanceDate: '2026-11-01',
        ),
      ]);
      // Insert non-ETB and archived accounts directly to verify strict filtering.
      await db.into(db.accountsTable).insert(
            AccountsTableCompanion.insert(
              id: 'acc-usd',
              name: 'USD Offshore',
              type: 'asset',
              subType: const Value('bank'),
              currencyCode: const Value('USD'),
              openingBalanceCents: const Value(25000),
              createdAt: DateTime.utc(2026, 11, 1),
            ),
          );
      await db.into(db.accountsTable).insert(
            AccountsTableCompanion.insert(
              id: 'acc-archived',
              name: 'Old Archived Bank',
              type: 'asset',
              subType: const Value('bank'),
              currencyCode: const Value('ETB'),
              isArchived: const Value(true),
              createdAt: DateTime.utc(2026, 11, 1),
            ),
          );
      await controller.loadAll();
    });

    tearDown(() async {
      controller.dispose();
      await db.close();
    });

    test(
      '1. Income & expense creation with separate movement dates and dual-write mirrors',
      () async {
        final occExpense = CalendarDate(year: 2026, month: 11, day: 10);
        final movExpense = CalendarDate(year: 2026, month: 11, day: 12);
        final expEntry = await controller.recordDirectExpense(
          accountId: 'acc-bank',
          categoryId: 'cat-food',
          amountCents: 45000,
          date: occExpense,
          movementDate: movExpense,
          description: 'Team lunch',
          payee: 'Tomoca',
          note: 'Receipt #42',
        );
        expect(expEntry, isNotNull);
        expect(controller.state.errorMessage, isNull);
        expect(expEntry!.occurrenceDate, '2026-11-10');
        expect(expEntry.description, 'Tomoca — Team lunch');

        final expPostings = controller.state.postings
            .where((p) => p.entryId == expEntry.id)
            .toList();
        expect(expPostings.length, 2);
        expect(
          expPostings.every((p) => p.accountMovementDate == '2026-11-12'),
          isTrue,
        );

        final occIncome = CalendarDate(year: 2026, month: 11, day: 14);
        final movIncome = CalendarDate(year: 2026, month: 11, day: 15);
        final incEntry = await controller.recordDirectIncome(
          accountId: 'acc-cash',
          categoryId: 'cat-salary',
          amountCents: 120000,
          date: occIncome,
          movementDate: movIncome,
          description: 'Consulting Stipend',
          payee: 'Client A',
          note: 'Cash envelope',
        );
        expect(incEntry, isNotNull);
        expect(controller.state.errorMessage, isNull);

        final expMirror = controller.state.transactions
            .firstWhere((t) => t.id == 'tx-${expEntry.id}');
        final incMirror = controller.state.transactions
            .firstWhere((t) => t.id == 'tx-${incEntry!.id}');
        expect(expMirror.type, TransactionType.expense);
        expect(expMirror.amountCents, 45000);
        expect(expMirror.payee, 'Tomoca');
        expect(expMirror.isSuperseded, isFalse);
        expect(incMirror.type, TransactionType.income);
        expect(incMirror.amountCents, 120000);
        expect(incMirror.payee, 'Client A');
        expect(incMirror.isSuperseded, isFalse);
      },
    );

    test(
      '2. Transfers support Savings Vaults, custom fee category, movement date, and valid dual-write mirror',
      () async {
        await controller.recordTransfer(
          fromAssetAccountId: 'acc-bank',
          toAssetAccountId: 'acc-vault',
          amountCents: 200000,
          transferFeeCents: 2500,
          feeCategoryId: 'cat-comm',
          date: '2026-11-11',
          movementDate: '2026-11-12',
          description: 'Monthly Vault Top-up',
          note: 'App transfer',
        );
        expect(controller.state.errorMessage, isNull);

        final transferEntry = controller.state.journalEntries.firstWhere(
          (e) => e.entryType == EntryType.transfer && !e.isVoided,
        );
        final tPostings = controller.state.postings
            .where((p) => p.entryId == transferEntry.id)
            .toList();
        expect(tPostings.length, 3);
        expect(
          tPostings.every((p) => p.accountMovementDate == '2026-11-12'),
          isTrue,
        );
        final feePosting = tPostings.firstWhere(
          (p) => p.accountId == SystemControlAccounts.expense,
        );
        expect(feePosting.amountCents, 2500);
        expect(feePosting.categoryId, 'cat-comm');

        final bank =
            controller.state.accounts.firstWhere((a) => a.id == 'acc-bank');
        final vault =
            controller.state.accounts.firstWhere((a) => a.id == 'acc-vault');
        expect(controller.state.getAccountBalanceCents(bank), 797500);
        expect(controller.state.getAccountBalanceCents(vault), 700000);

        final mirror = controller.state.transactions
            .firstWhere((t) => t.id == 'tx-${transferEntry.id}');
        expect(mirror.type, TransactionType.transfer);
        expect(mirror.accountId, 'acc-bank');
        expect(mirror.toAccountId, 'acc-vault');
        expect(mirror.categoryId, isNot('cat-transfer'));
      },
    );

    test(
      '3. Lend, borrow, settlement, split expense, and expense refunds work end-to-end',
      () async {
        final abebeId = await controller.ensurePartyId('Abebe');

        // Lend
        final receivable = await controller.lendMoney(
          partyId: abebeId,
          sourceAccountId: 'acc-bank',
          amountCents: 100000,
          date: CalendarDate(year: 2026, month: 11, day: 5),
          movementDate: CalendarDate(year: 2026, month: 11, day: 6),
          dueDate: CalendarDate(year: 2026, month: 11, day: 20),
          description: 'Emergency Bridge',
          note: 'Bank transfer ref',
        );
        expect(receivable, isNotNull);
        expect(receivable!.outstandingCents, 100000);
        final lendPostings = controller.state.postings
            .where((p) => p.entryId == receivable.originEntryId)
            .toList();
        expect(
          lendPostings.every((p) => p.accountMovementDate == '2026-11-06'),
          isTrue,
        );

        // Borrow
        final payable = await controller.borrowMoney(
          partyId: abebeId,
          destinationAccountId: 'acc-cash',
          amountCents: 50000,
          date: CalendarDate(year: 2026, month: 11, day: 7),
          movementDate: CalendarDate(year: 2026, month: 11, day: 7),
          description: 'Cash float',
        );
        expect(payable, isNotNull);
        expect(payable!.debtType, DebtType.payable);

        // Partial Settlement
        await controller.recordDoubleEntrySettlement(
          debt: receivable,
          settlementAssetAccountId: 'acc-bank',
          allocatedCents: 40000,
          settlementDate: '2026-11-12',
          description: 'Partial repayment',
        );
        expect(controller.state.errorMessage, isNull);
        final updatedRec =
            controller.state.debts.firstWhere((d) => d.id == receivable.id);
        expect(updatedRec.outstandingCents, 60000);

        // Split Expense
        final splitEntry = await controller.recordSplitExpense(
          paidAccountId: 'acc-bank',
          myCategoryId: 'cat-food',
          myShareCents: 30000,
          theirShareCents: 20000,
          partyId: abebeId,
          date: CalendarDate(year: 2026, month: 11, day: 13),
          movementDate: CalendarDate(year: 2026, month: 11, day: 14),
          dueDate: CalendarDate(year: 2026, month: 11, day: 28),
          description: 'Shared Dinner',
          note: '60/40 split',
        );
        expect(splitEntry, isNotNull);
        expect(
          controller.state.debts.any(
            (d) =>
                d.originEntryId == splitEntry!.id && d.principalCents == 20000,
          ),
          isTrue,
        );
        final splitMirror = controller.state.transactions
            .firstWhere((t) => t.id == 'tx-${splitEntry!.id}');
        expect(splitMirror.amountCents, 30000);

        // Expense Refund
        final exp = await controller.recordDirectExpense(
          accountId: 'acc-cash',
          categoryId: 'cat-food',
          amountCents: 20000,
          date: CalendarDate(year: 2026, month: 11, day: 14),
          description: 'Hardware purchase',
        );
        expect(exp, isNotNull);
        final refund = await controller.recordExpenseRefund(
          originalEntryId: exp!.id,
          refundAccountId: 'acc-cash',
          refundCents: 8000,
          date: CalendarDate(year: 2026, month: 11, day: 15),
          note: 'Returned adapter',
        );
        expect(refund, isNotNull);
        expect(DoubleEntryEngine.isRefundEntry(refund!), isTrue);
      },
    );

    test(
      '4. Corrections preserve metadata (payee removal, category, fee, fee category, distinct movement date) and dual-write supersede chain',
      () async {
        final orig = await controller.recordDirectExpense(
          accountId: 'acc-bank',
          categoryId: 'cat-food',
          amountCents: 50000,
          date: CalendarDate(year: 2026, month: 11, day: 8),
          movementDate: CalendarDate(year: 2026, month: 11, day: 9),
          description: 'Groceries',
          payee: 'Shoa',
          note: 'Original receipt',
        );
        expect(orig, isNotNull);

        final built = DoubleEntryEngine.buildDirectExpense(
          entryId: 'entry-corr-1',
          paidAccountId: 'acc-cash',
          categoryId: 'cat-transport',
          amountCents: 55000,
          date: '2026-11-08',
          movementDate: '2026-11-10',
          description: 'Ride Home',
          note: 'Corrected receipt',
          correctedFromEntryId: orig!.id,
        );
        final replacement = await controller.correctJournalEntry(
          originalEntryId: orig.id,
          replacementEntry: built['entry'] as JournalEntryModel,
          replacementPostings: built['postings'] as List<PostingModel>,
          correctionReason: 'Wrong account and category',
        );
        expect(replacement, isNotNull);
        expect(replacement!.correctedFromEntryId, orig.id);

        final oldOrig =
            controller.state.journalEntries.firstWhere((e) => e.id == orig.id);
        expect(oldOrig.isVoided, isTrue);

        final repPostings = controller.state.postings
            .where((p) => p.entryId == replacement.id)
            .toList();
        expect(
          repPostings.every((p) => p.accountMovementDate == '2026-11-10'),
          isTrue,
        );

        final oldMirror = controller.state.transactions
            .firstWhere((t) => t.id == 'tx-${orig.id}');
        final newMirror = controller.state.transactions
            .firstWhere((t) => t.id == 'tx-${replacement.id}');
        expect(oldMirror.isSuperseded, isTrue);
        expect(newMirror.isSuperseded, isFalse);
        expect(newMirror.payee, isNull);
        expect(newMirror.categoryId, 'cat-transport');
      },
    );

    test(
      '5. Category aliases resolve cleanly without rewriting historical ledger records',
      () async {
        // Insert a historical posting directly with legacy alias 'cat-communication'.
        await db.into(db.financialCategoriesTable).insert(
              FinancialCategoriesTableCompanion.insert(
                id: 'cat-communication',
                name: 'Telecom Legacy',
                type: 'expense',
                sortOrder: const Value(99),
              ),
            );
        final categories = await repo.getAllCategories();
        final byId = {for (final c in categories) c.id: c};
        // Remove legacy row from lookup map to simulate alias-only historical posting.
        final canonicalOnlyMap =
            Map<String, TransactionCategoryModel>.from(byId)
              ..remove('cat-communication');

        expect(
          FinanceUiFormatters.formatCategoryBreadcrumb(
            'cat-communication',
            canonicalOnlyMap,
          ),
          'Communication',
        );
        expect(
          FinanceUiFormatters.formatCategoryBreadcrumb(
            'cat-inc-other',
            canonicalOnlyMap,
          ),
          'Other Income',
        );
        expect(
          FinanceUiFormatters.resolveCategorySelectionValue(
            'cat-inc-other',
            categories,
            type: 'income',
          ),
          'cat-other-inc',
        );
      },
    );

    test(
      '6. Rejects Vaults outside Transfers, rejects non-ETB/archived accounts and invalid amounts, and clears stale errors',
      () async {
        // Vault rejected on expense
        final vaultExp = await controller.recordDirectExpense(
          accountId: 'acc-vault',
          categoryId: 'cat-food',
          amountCents: 10000,
          date: CalendarDate(year: 2026, month: 11, day: 10),
          description: 'Invalid Vault Expense',
        );
        expect(vaultExp, isNull);
        expect(controller.state.errorMessage, isNotNull);

        // Subsequent valid action clears stale errorMessage
        final validExp = await controller.recordDirectExpense(
          accountId: 'acc-bank',
          categoryId: 'cat-food',
          amountCents: 10000,
          date: CalendarDate(year: 2026, month: 11, day: 10),
          description: 'Valid Lunch',
        );
        expect(validExp, isNotNull);
        expect(controller.state.errorMessage, isNull);

        // Vault rejected on Lend & Settlement
        final abebeId = await controller.ensurePartyId('Abebe');
        final vaultLend = await controller.lendMoney(
          partyId: abebeId,
          sourceAccountId: 'acc-vault',
          amountCents: 5000,
          date: CalendarDate(year: 2026, month: 11, day: 10),
          description: 'Invalid Vault Loan',
        );
        expect(vaultLend, isNull);
        expect(controller.state.errorMessage, isNotNull);

        // USD and archived accounts rejected
        final usdInc = await controller.recordDirectIncome(
          accountId: 'acc-usd',
          categoryId: 'cat-salary',
          amountCents: 5000,
          date: CalendarDate(year: 2026, month: 11, day: 10),
          description: 'USD Income',
        );
        expect(usdInc, isNull);
        expect(controller.state.errorMessage, isNotNull);

        final archivedExp = await controller.recordDirectExpense(
          accountId: 'acc-archived',
          categoryId: 'cat-food',
          amountCents: 5000,
          date: CalendarDate(year: 2026, month: 11, day: 10),
          description: 'Archived Expense',
        );
        expect(archivedExp, isNull);
        expect(controller.state.errorMessage, isNotNull);

        // Zero and negative amounts rejected
        expect(FinanceUiFormatters.parseEtbToCents('12.345'), isNull);
        final zeroLend = await controller.lendMoney(
          partyId: abebeId,
          sourceAccountId: 'acc-bank',
          amountCents: 0,
          date: CalendarDate(year: 2026, month: 11, day: 10),
          description: 'Zero loan',
        );
        expect(zeroLend, isNull);
        expect(controller.state.errorMessage, isNotNull);
      },
    );

    testWidgets(
      '7. Widget: FinanceComposerSheet enforces 6 modes, Vault-in-Transfer-only filtering, conditional Fee Category, synced Movement Date, validation, and Lend submission',
      (tester) async {
        Finder fieldByLabel(String exactLabel) => find.descendant(
              of: find.widgetWithText(DaywellTextField, exactLabel),
              matching: find.byType(TextFormField),
            );

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: ElevatedButton(
                    onPressed: () => FinanceComposerSheet.show(
                      ctx,
                      controller: controller,
                    ),
                    child: const Text('Open Composer'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open Composer'));
        await tester.pumpAndSettle();

        // All 6 mode chips are present.
        for (final label in const [
          'Expense',
          'Income',
          'Transfer',
          'Split Expense',
          'Lend',
          'Borrow',
        ]) {
          expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
        }

        // Synced Cash Movement Date by default, expandable on tap.
        expect(
          find.textContaining('Cash Movement Date: Same as occurrence date'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Separate Movement Date'));
        await tester.tap(find.text('Separate Movement Date'));
        await tester.pumpAndSettle();
        expect(find.text('Pick Movement Date'), findsOneWidget);
        expect(find.text('Sync to Occurrence'), findsOneWidget);

        // Submitting empty amount displays validation banner without closing.
        await tester.ensureVisible(find.text('Post Expense'));
        await tester.tap(find.text('Post Expense'));
        await tester.pumpAndSettle();
        expect(find.byType(FinanceComposerSheet), findsOneWidget);
        expect(find.byType(DaywellStatusBanner), findsWidgets);
        expect(find.textContaining('valid ETB amount'), findsOneWidget);

        // Vault is excluded in Expense mode.
        expect(find.textContaining('Emergency Vault'), findsNothing);

        // Switch to Transfer -> Vault is available and Fee Category appears ONLY when fee > 0.
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Transfer'));
        await tester.tap(find.widgetWithText(ChoiceChip, 'Transfer'));
        await tester.pumpAndSettle();
        expect(find.text('Fee Category'), findsNothing);

        final feeField = fieldByLabel('Bank / Service Fee (ETB, optional)');
        await tester.ensureVisible(feeField);
        await tester.enterText(feeField, '15.50');
        await tester.pumpAndSettle();
        expect(find.text('Fee Category'), findsOneWidget);
        expect(find.text('Financial Fees'), findsOneWidget);

        // Switch to Lend and verify Vault & Fee Category are hidden.
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Lend'));
        await tester.tap(find.widgetWithText(ChoiceChip, 'Lend'));
        await tester.pumpAndSettle();
        expect(find.text('Source Account'), findsOneWidget);
        expect(find.text('Fee Category'), findsNothing);

        await tester.enterText(fieldByLabel('Amount (ETB) *'), '250.00');
        final partyField = fieldByLabel('New Person / Party Name *');
        await tester.ensureVisible(partyField);
        await tester.enterText(partyField, 'Dawit');
        final descField = fieldByLabel('Description');
        await tester.ensureVisible(descField);
        await tester.enterText(descField, 'Taxi loan');

        await tester.ensureVisible(find.text('Post Loan Out'));
        await tester.runAsync(() async {
          await tester.tap(find.text('Post Loan Out'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();

        expect(find.byType(FinanceComposerSheet), findsNothing);
        expect(controller.state.debts.length, 1);
        expect(controller.state.debts.first.principalCents, 25000);
        expect(controller.state.debts.first.debtType, DebtType.receivable);
      },
    );
  });
}
