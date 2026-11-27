import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/finance/finance_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/shared_foundation.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';
import 'package:personal_management_app/domain/finance/double_entry_engine.dart';
import 'package:personal_management_app/ui/screens/finance/finance_composer_sheet.dart';
import 'package:personal_management_app/ui/screens/finance/finance_transactions_tab.dart';
import 'package:personal_management_app/ui/widgets/shared_ui_widgets.dart';

import 'support/sqlite_test_helper.dart';

class _Stage1Fixture {
  final AppDatabase db;
  final DriftFinanceRepository repo;
  final FinanceController controller;

  const _Stage1Fixture({
    required this.db,
    required this.repo,
    required this.controller,
  });
}

Future<_Stage1Fixture> _createFixture() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.ensureInitialized();
  final repo = DriftFinanceRepository(db);
  final controller = FinanceController(repository: repo);
  await controller.completeSetup([
    AccountModel(
      id: 'acc-cbe',
      name: 'CBE',
      type: AccountType.asset,
      subType: AccountSubType.bank,
      currencyCode: 'ETB',
      openingBalanceCents: 500000, // 5,000 ETB
      openingBalanceDate: '2026-11-01',
    ),
    AccountModel(
      id: 'acc-telebirr',
      name: 'Telebirr',
      type: AccountType.asset,
      subType: AccountSubType.mobileMoney,
      currencyCode: 'ETB',
      openingBalanceCents: 100000, // 1,000 ETB
      openingBalanceDate: '2026-11-01',
    ),
  ]);
  await controller.loadAll();
  return _Stage1Fixture(db: db, repo: repo, controller: controller);
}

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Finance Stage 1 — Transfer Display Direction & Optional Expense Fees',
      () {
    late AppDatabase db;
    late DriftFinanceRepository repo;
    late FinanceController controller;

    setUp(() async {
      final fixture = await _createFixture();
      db = fixture.db;
      repo = fixture.repo;
      controller = fixture.controller;
    });

    tearDown(() async {
      controller.dispose();
      await db.close();
    });

    test(
      '1. resolveTransferDisplayEndpoints resolves CBE -> Telebirr and Telebirr -> CBE regardless of posting order and excludes system postings',
      () {
        final built = DoubleEntryEngine.buildTransfer(
          entryId: 'xfer-1',
          fromAssetAccountId: 'acc-cbe',
          toAssetAccountId: 'acc-telebirr',
          amountCents: 25000,
          transferFeeCents: 500,
          feeExpenseAccountId: SystemControlAccounts.expense,
          feeCategoryId: SystemControlAccounts.feeCategoryId,
          date: '2026-11-10',
          description: 'Wallet Topup',
        );
        final postings = (built['postings'] as List<PostingModel>);
        final accounts = controller.state.accounts;

        final normal = DoubleEntryEngine.resolveTransferDisplayEndpoints(
          postings: postings,
          accounts: accounts,
        );
        expect(normal.isUnambiguous, true);
        expect(normal.sourceName, 'CBE');
        expect(normal.destinationName, 'Telebirr');

        // Reversed insertion order (debit destination and system fee before credit source)
        final reversedOrder = postings.reversed.toList();
        final reversedRes = DoubleEntryEngine.resolveTransferDisplayEndpoints(
          postings: reversedOrder,
          accounts: accounts,
        );
        expect(reversedRes.isUnambiguous, true);
        expect(reversedRes.sourceName, 'CBE');
        expect(reversedRes.destinationName, 'Telebirr');

        // Opposite direction: Telebirr -> CBE
        final opposite = DoubleEntryEngine.buildTransfer(
          entryId: 'xfer-2',
          fromAssetAccountId: 'acc-telebirr',
          toAssetAccountId: 'acc-cbe',
          amountCents: 10000,
          date: '2026-11-11',
          description: 'Return to bank',
        );
        final oppositeRes = DoubleEntryEngine.resolveTransferDisplayEndpoints(
          postings: (opposite['postings'] as List<PostingModel>).reversed.toList(),
          accounts: accounts,
        );
        expect(oppositeRes.isUnambiguous, true);
        expect(oppositeRes.sourceName, 'Telebirr');
        expect(oppositeRes.destinationName, 'CBE');

        // Missing destination leg -> does not invent direction
        final missingDest = DoubleEntryEngine.resolveTransferDisplayEndpoints(
          postings: [
            PostingModel(
              id: 'p1',
              entryId: 'x-missing',
              accountId: 'acc-cbe',
              amountCents: 10000,
              direction: PostingDirection.credit,
              accountMovementDate: '2026-11-10',
            ),
            PostingModel(
              id: 'p2',
              entryId: 'x-missing',
              accountId: SystemControlAccounts.expense,
              amountCents: 10000,
              direction: PostingDirection.debit,
              accountMovementDate: '2026-11-10',
            ),
          ],
          accounts: accounts,
        );
        expect(missingDest.isUnambiguous, false);
        expect(missingDest.fallbackAccountNames, ['CBE']);
      },
    );

    test(
      '2. Expense with 0 fee creates no fee posting; nonzero fee (1,000 + 15 ETB) creates balanced cat-fees leg without duplicates',
      () async {
        // Negative fee rejected
        expect(
          () => DoubleEntryEngine.buildDirectExpense(
            entryId: 'exp-neg',
            paidAccountId: 'acc-cbe',
            categoryId: 'cat-food',
            amountCents: 100000,
            feeCents: -1,
            date: '2026-11-12',
            description: 'Invalid fee',
          ),
          throwsA(isA<DoubleEntryValidationError>()),
        );

        // Zero fee -> 2 postings only
        final zeroEntry = await controller.recordDirectExpense(
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          amountCents: 50000,
          feeCents: 0,
          date: CalendarDate(year: 2026, month: 11, day: 12),
          description: 'Zero fee meal',
        );
        expect(zeroEntry, isNotNull);
        final zeroPostings = await repo.getPostings(entryId: zeroEntry!.id);
        expect(zeroPostings.length, 2);

        // Nonzero fee: Principal 1,000 ETB + Fee 15 ETB = 1,015 ETB outflow
        final feeEntry = await controller.recordDirectExpense(
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          amountCents: 100000,
          feeCents: 1500,
          feeCategoryId: SystemControlAccounts.feeCategoryId,
          date: CalendarDate(year: 2026, month: 11, day: 13),
          description: 'Groceries with fee',
        );
        expect(feeEntry, isNotNull);

        final feePostings = await repo.getPostings(entryId: feeEntry!.id);
        expect(feePostings.length, 3);
        DoubleEntryEngine.validateBalancedEntry(feePostings);

        final summary = DoubleEntryEngine.summarizeDirectExpense(
          entry: feeEntry,
          postings: feePostings,
          accounts: controller.state.accounts,
        );
        expect(summary.isDirectExpense, true);
        expect(summary.principalCents, 100000);
        expect(summary.feeCents, 1500);
        expect(summary.totalOutflowCents, 101500);
        expect(summary.primaryCategoryId, 'cat-food');
        expect(summary.feeCategoryId, SystemControlAccounts.feeCategoryId);

        // No duplicate cat-fees rows created
        final categories = await repo.getCategories();
        expect(
          categories.where((c) => c.id == SystemControlAccounts.feeCategoryId).length,
          1,
        );

        // CBE balance = 5,000 - 500 - 1,015 = 3,485 ETB
        final cbe = controller.state.accounts.firstWhere((a) => a.id == 'acc-cbe');
        expect(controller.state.getAccountBalanceCents(cbe), 348500);

        // Legacy mirror row stores principal (1,000 ETB) and merchant category (cat-food)
        final mirrorTxs = await repo.getTransactions();
        final feeMirror = mirrorTxs.firstWhere((t) => t.id == feeEntry.legacySourceTxId);
        expect(feeMirror.amountCents, 100000);
        expect(feeMirror.categoryId, 'cat-food');
      },
    );

    test(
      '3. Expense refund excludes bank fee (capped at 1,000 ETB), and reports/category totals avoid double counting',
      () async {
        final exp = await controller.recordDirectExpense(
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          amountCents: 100000,
          feeCents: 1500,
          feeCategoryId: SystemControlAccounts.feeCategoryId,
          date: CalendarDate(year: 2026, month: 11, day: 12),
          description: 'Merchant purchase',
        );
        expect(exp, isNotNull);

        final refundSummary = DoubleEntryEngine.getExpenseRefundSummary(
          originalEntryId: exp!.id,
          entries: controller.state.journalEntries,
          postings: controller.state.postings,
          accounts: controller.state.accounts,
        );
        expect(refundSummary.eligible, true);
        expect(refundSummary.originalAmountCents, 100000);
        expect(refundSummary.originalFeeCents, 1500);
        expect(refundSummary.remainingRefundableCents, 100000);

        // Attempting to refund principal + fee (1,015 ETB) must fail
        await expectLater(
          repo.recordExpenseRefund(
            originalEntryId: exp.id,
            refundAccountId: 'acc-cbe',
            refundCents: 101500,
            date: CalendarDate(year: 2026, month: 11, day: 13),
          ),
          throwsA(isA<DoubleEntryValidationError>()),
        );

        // Refunding principal (1,000 ETB) succeeds
        final refunded = await controller.recordExpenseRefund(
          originalEntryId: exp.id,
          refundAccountId: 'acc-cbe',
          refundCents: 100000,
          date: CalendarDate(year: 2026, month: 11, day: 13),
        );
        expect(refunded, isNotNull);

        // Category spend report shows 0 net Food spend and 15 ETB Financial Fees without double-counting
        final catSpend = DoubleEntryEngine.calculateCanonicalCategorySpend(
          entries: controller.state.journalEntries,
          postings: controller.state.postings,
          accounts: controller.state.accounts,
          categories: controller.state.categories,
          startDateIso: '2026-11-01',
          endDateIso: '2026-11-30',
        );
        expect(catSpend.directSpendByCategoryId['cat-food'], 0);
        expect(catSpend.directSpendByCategoryId['cat-fees'], 1500);
        expect(catSpend.totalExpenseCents, 1500);
      },
    );

    test(
      '4. Editing, correctTransaction, void, and unvoid preserve expense fees and keep mirrors synchronized',
      () async {
        final orig = await controller.recordDirectExpense(
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          amountCents: 100000,
          feeCents: 1500,
          feeCategoryId: SystemControlAccounts.feeCategoryId,
          date: CalendarDate(year: 2026, month: 11, day: 12),
          description: 'Groceries',
        );
        expect(orig, isNotNull);

        // Replace via correctJournalEntry with updated fee 20 ETB and principal 1,200 ETB
        final builtRepl = DoubleEntryEngine.buildDirectExpense(
          entryId: 'entry-repl-1',
          paidAccountId: 'acc-cbe',
          categoryId: 'cat-food',
          amountCents: 120000,
          feeCents: 2000,
          feeCategoryId: SystemControlAccounts.feeCategoryId,
          date: '2026-11-12',
          description: 'Groceries revised',
          correctedFromEntryId: orig!.id,
        );
        final repl = await controller.correctJournalEntry(
          originalEntryId: orig.id,
          replacementEntry: builtRepl['entry'] as JournalEntryModel,
          replacementPostings: builtRepl['postings'] as List<PostingModel>,
          correctionReason: 'Adjusted receipt',
        );
        expect(repl, isNotNull);

        final cbe = controller.state.accounts.firstWhere((a) => a.id == 'acc-cbe');
        expect(controller.state.getAccountBalanceCents(cbe), 378000); // 5000 - 1220

        // Mirror row for replacement stores principal (1,200 ETB) and merchant category (cat-food)
        final replMirror = (await repo.getTransactions())
            .firstWhere((t) => t.id == repl!.legacySourceTxId);
        expect(replMirror.amountCents, 120000);
        expect(replMirror.categoryId, 'cat-food');

        // Void & unvoid preserve principal mirror + full fee balance
        await controller.voidJournalEntry(repl!.id, 'Duplicate');
        expect(
          controller.state.getAccountBalanceCents(
            controller.state.accounts.firstWhere((a) => a.id == 'acc-cbe'),
          ),
          500000,
        );
        await controller.unvoidJournalEntry(repl.id);
        expect(
          controller.state.getAccountBalanceCents(
            controller.state.accounts.firstWhere((a) => a.id == 'acc-cbe'),
          ),
          378000,
        );
        final restoredMirror = (await repo.getTransactions())
            .firstWhere((t) => t.id == repl.legacySourceTxId);
        expect(restoredMirror.amountCents, 120000);
        expect(restoredMirror.categoryId, 'cat-food');
      },
    );

    testWidgets(
      '5. Widget: FinanceTransactionsTab displays CBE → Telebirr and expense fee totals cleanly',
      (tester) async {
        final fixture = await tester.runAsync(_createFixture);
        final localDb = fixture!.db;
        final localCtrl = fixture.controller;

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 20));
          localCtrl.dispose();
          await localDb.close();
        });

        await tester.runAsync(() async {
          await localCtrl.recordTransfer(
            fromAssetAccountId: 'acc-cbe',
            toAssetAccountId: 'acc-telebirr',
            amountCents: 20000,
            transferFeeCents: 500,
            feeCategoryId: SystemControlAccounts.feeCategoryId,
            date: '2026-11-10',
            description: 'Wallet Topup',
          );
          await localCtrl.recordDirectExpense(
            accountId: 'acc-cbe',
            categoryId: 'cat-food',
            amountCents: 100000,
            feeCents: 1500,
            feeCategoryId: SystemControlAccounts.feeCategoryId,
            date: CalendarDate(year: 2026, month: 11, day: 11),
            description: 'Market Purchase',
          );
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: FinanceTransactionsTab(controller: localCtrl),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('CBE → Telebirr'), findsOneWidget);
        expect(find.text('-1,015.00 ETB'), findsOneWidget);
        expect(find.textContaining('Includes 15.00 ETB fee'), findsWidgets);
        expect(find.textContaining('Principal 1,000.00 ETB'), findsOneWidget);
      },
    );

    testWidgets(
      '6. Widget: FinanceComposerSheet supports optional expense fee (0 default), hides fee on Income, and prefills principal + fee on Edit',
      (tester) async {
        final fixture = await tester.runAsync(_createFixture);
        final localDb = fixture!.db;
        final localCtrl = fixture.controller;

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 20));
          localCtrl.dispose();
          await localDb.close();
        });

        Finder fieldByLabel(String exactLabel) => find.descendant(
              of: find.widgetWithText(DaywellTextField, exactLabel),
              matching: find.byType(TextFormField),
            );

        JournalEntryModel? existingExpense;
        await tester.runAsync(() async {
          existingExpense = await localCtrl.recordDirectExpense(
            accountId: 'acc-cbe',
            categoryId: 'cat-food',
            amountCents: 100000,
            feeCents: 1500,
            feeCategoryId: SystemControlAccounts.feeCategoryId,
            date: CalendarDate(year: 2026, month: 11, day: 11),
            description: 'Groceries',
          );
        });

        // Open new composer: Expense mode shows fee field defaulting to 0; Income hides fee field
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: FinanceComposerSheet(controller: localCtrl),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.widgetWithText(DaywellTextField, 'Bank / Service Fee (ETB, optional)'),
          findsOneWidget,
        );
        final feeTextField = tester.widget<TextFormField>(
          fieldByLabel('Bank / Service Fee (ETB, optional)'),
        );
        expect(feeTextField.controller?.text, '0');

        // Switch to Income -> fee field must be hidden
        await tester.tap(find.widgetWithText(ChoiceChip, 'Income'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(DaywellTextField, 'Bank / Service Fee (ETB, optional)'),
          findsNothing,
        );

        // Open composer in editing mode for existing expense -> prefills principal 1000.00 & fee 15.00
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: FinanceComposerSheet(
                controller: localCtrl,
                editingEntry: existingExpense,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final amountCtrlText = tester
            .widget<TextFormField>(fieldByLabel('Amount (ETB) *'))
            .controller
            ?.text;
        final editFeeText = tester
            .widget<TextFormField>(
              fieldByLabel('Bank / Service Fee (ETB, optional)'),
            )
            .controller
            ?.text;
        expect(amountCtrlText, '1000.00');
        expect(editFeeText, '15.00');
        expect(find.textContaining('Total deduction: 1,015.00 ETB'), findsOneWidget);
      },
    );
  });
}
