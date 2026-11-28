import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/finance/finance_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/app_settings_policy.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';
import 'package:personal_management_app/ui/app_state.dart';
import 'package:personal_management_app/ui/screens/finance/finance_composer_sheet.dart';
import 'package:personal_management_app/ui/screens/finance/finance_overview_tab.dart';
import 'package:personal_management_app/ui/screens/finance/finance_reports_tab.dart';
import 'package:personal_management_app/ui/screens/finance/finance_transactions_tab.dart';
import 'package:personal_management_app/ui/widgets/shared_ui_widgets.dart';

import 'support/sqlite_test_helper.dart';

class _Stage3Fixture {
  final AppDatabase db;
  final DriftFinanceRepository repo;
  final FinanceController controller;

  const _Stage3Fixture({
    required this.db,
    required this.repo,
    required this.controller,
  });
}

Future<_Stage3Fixture> _createFixture({bool insertLegacyUsd = false}) async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.ensureInitialized();
  final repo = DriftFinanceRepository(db);
  final controller = FinanceController(repository: repo);
  await controller.completeSetup([
    AccountModel(
      id: 'acc-cbe',
      name: 'CBE Bank',
      type: AccountType.asset,
      subType: AccountSubType.bank,
      currencyCode: 'ETB',
      openingBalanceCents: 250000, // 2,500 ETB
      openingBalanceDate: '2026-11-01',
    ),
  ]);

  if (insertLegacyUsd) {
    final now = DateTime.utc(2026, 10, 15);
    await db.into(db.accountsTable).insert(
          AccountsTableCompanion.insert(
            id: 'acc-usd-legacy',
            name: 'Dollar Cash',
            type: 'asset',
            subType: const Value('cash'),
            currencyCode: const Value('USD'),
            openingBalanceCents: const Value(100000), // 1,000.00 USD
            createdAt: now,
          ),
        );
    await db.into(db.journalEntriesTable).insert(
          JournalEntriesTableCompanion.insert(
            id: 'je-usd-legacy',
            entryType: 'standard',
            description: 'Airport Hotel USD',
            occurrenceDate: '2026-10-15',
            createdAt: now,
          ),
        );
    await db.into(db.postingsTable).insert(
          PostingsTableCompanion.insert(
            id: 'post-usd-dr',
            entryId: 'je-usd-legacy',
            accountId: SystemControlAccounts.expense,
            amountCents: 15000,
            direction: 'debit',
            accountMovementDate: '2026-10-15',
            categoryId: const Value('cat-food'),
          ),
        );
    await db.into(db.postingsTable).insert(
          PostingsTableCompanion.insert(
            id: 'post-usd-cr',
            entryId: 'je-usd-legacy',
            accountId: 'acc-usd-legacy',
            amountCents: 15000,
            direction: 'credit',
            accountMovementDate: '2026-10-15',
          ),
        );
  }

  await controller.loadAll();
  return _Stage3Fixture(db: db, repo: repo, controller: controller);
}

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Finance Stage 3 — ETB-Only Finance Cleanup (Flutter)', () {
    test(
      '1. Quick Capture rejects foreign currency markers and accepts plain ETB inputs cleanly',
      () {
        for (final fx in [
          r'$20 Dinner',
          'Taxi 18 USD',
          'Coffee 12 EUR',
          'Tea £10',
        ]) {
          expect(
            AppStateManager.detectQuickCaptureUnsupportedCurrency(fx),
            isNotNull,
            reason: 'Should detect FX marker in "$fx"',
          );
          expect(
            AppStateManager.parseQuickCaptureExpense(fx),
            isNull,
            reason: 'Must never reinterpret FX amount as ETB for "$fx"',
          );
        }

        final ok = AppStateManager.parseQuickCaptureExpense('Coffee 120 ETB');
        expect(ok, isNotNull);
        expect(ok!.amountCents, 12000);
        expect(ok.description, 'Coffee');
      },
    );

    test(
      '2. Historical non-ETB accounts/entries are preserved read-only, excluded from ETB math, and guarded from mutation',
      () async {
        final fixture = await _createFixture(insertLegacyUsd: true);
        addTearDown(() async {
          fixture.controller.dispose();
          await fixture.db.close();
        });

        final state = fixture.controller.state;
        // Partitioning helpers keep Dollar Cash isolated from normal ETB lists
        expect(state.etbUserAccounts.map((a) => a.id), ['acc-cbe']);
        expect(state.legacyNonEtbAccounts.map((a) => a.id), ['acc-usd-legacy']);
        expect(state.legacyNonEtbEntryCount, 1);
        expect(state.hasLegacyNonEtbRecords, true);

        // ETB Safe Harbor & Net Worth exclude the USD 1,000 balance cleanly (only 2,500 ETB = 250,000 cents)
        expect(state.availableToSpendCents, 250000);
        expect(state.availableToSpendBreakdown.liquidCashCents, 250000);

        // Record ordinary ETB expense
        final created = await fixture.controller.recordDirectExpense(
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          amountCents: 30000,
          date: CalendarDate(year: 2026, month: 11, day: 10),
          description: 'Shoa Groceries',
        );
        expect(created, isNotNull);
        expect(fixture.controller.state.availableToSpendCents, 220000);

        // Legacy USD entry stays untouched and protected from replacement/refund/unvoid
        final canReplace = DoubleEntryEngine.canCorrectEntry(
          entry: fixture.controller.state.journalEntries
              .firstWhere((e) => e.id == 'je-usd-legacy'),
          entries: fixture.controller.state.journalEntries,
          postings: fixture.controller.state.postings,
          accounts: fixture.controller.state.accounts,
        );
        expect(canReplace.ok, false);
        expect(canReplace.error, contains('read-only'));
        expect(canReplace.error!.contains('first-release'), false);

        final refundSummary = DoubleEntryEngine.getExpenseRefundSummary(
          originalEntryId: 'je-usd-legacy',
          entries: fixture.controller.state.journalEntries,
          postings: fixture.controller.state.postings,
          accounts: fixture.controller.state.accounts,
        );
        expect(refundSummary.eligible, false);
        expect(refundSummary.reason!.contains('first-release'), false);

        // Direct non-ETB posting write fails closed
        final badRes = await fixture.controller.recordDirectExpense(
          accountId: 'acc-usd-legacy',
          categoryId: 'cat-food',
          amountCents: 1000,
          date: CalendarDate(year: 2026, month: 11, day: 11),
          description: 'Should fail',
        );
        expect(badRes, isNull);
        expect(fixture.controller.state.errorMessage, isNotNull);
      },
    );

    test(
      '3. One-time legacy notice dismissal persists across controller reloads and is registered in AppSettingsBackupPolicy',
      () async {
        expect(
          AppSettingsBackupPolicy.isExportableUserSetting(
            DriftFinanceRepository.legacyNonEtbNoticeDismissedKey,
          ),
          isTrue,
        );

        final fixture = await _createFixture(insertLegacyUsd: true);
        addTearDown(() async {
          fixture.controller.dispose();
          await fixture.db.close();
        });

        expect(fixture.controller.state.legacyNonEtbNoticeDismissed, isFalse);
        await fixture.controller.dismissLegacyNonEtbNotice();
        expect(fixture.controller.state.legacyNonEtbNoticeDismissed, isTrue);

        // Fresh controller + loadAll reads persisted dismissal from app_settings
        final reloaded = FinanceController(repository: fixture.repo);
        addTearDown(reloaded.dispose);
        await reloaded.loadAll();
        expect(reloaded.state.legacyNonEtbNoticeDismissed, isTrue);
      },
    );

    testWidgets(
      '4. Overview shows dismissible legacy notice & collapsed Legacy Archive only when legacy non-ETB exists, and hides notice permanently once dismissed',
      (tester) async {
        // Pure ETB ledger: no legacy notice or archive card
        final etbFixture = await tester.runAsync(
          () => _createFixture(insertLegacyUsd: false),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          etbFixture!.controller.dispose();
          final closeFuture = etbFixture.db.close();
          await tester.runAsync(
            () => closeFuture.timeout(const Duration(seconds: 10)),
          );
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: FinanceOverviewTab(controller: etbFixture!.controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Historical Non-ETB Records Preserved'),
          findsNothing,
        );
        expect(
          find.textContaining('Legacy Non-ETB Archive (Read-Only)'),
          findsNothing,
        );

        // Mixed ledger: shows dismissible notice and collapsed Legacy Non-ETB Archive
        final mixedFixture = await tester.runAsync(
          () => _createFixture(insertLegacyUsd: true),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          mixedFixture!.controller.dispose();
          final closeFuture = mixedFixture.db.close();
          await tester.runAsync(
            () => closeFuture.timeout(const Duration(seconds: 10)),
          );
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: FinanceOverviewTab(controller: mixedFixture!.controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final noticeFinder =
            find.textContaining('Historical Non-ETB Records Preserved');
        final legacyArchiveFinder =
            find.textContaining('Legacy Non-ETB Archive (Read-Only)');
        expect(noticeFinder, findsOneWidget);

        await tester.scrollUntilVisible(
          legacyArchiveFinder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(legacyArchiveFinder, findsOneWidget);

        // Scroll back to top and tap Dismiss inside DaywellStatusBanner
        await tester.scrollUntilVisible(
          noticeFinder,
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        final dismissBtn = find.descendant(
          of: find.byType(DaywellStatusBanner),
          matching: find.byTooltip('Dismiss'),
        );
        expect(dismissBtn, findsOneWidget);
        await tester.ensureVisible(dismissBtn);
        await tester.pumpAndSettle();
        await tester.tap(dismissBtn);
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();

        expect(noticeFinder, findsNothing);
        expect(
          mixedFixture.controller.state.legacyNonEtbNoticeDismissed,
          isTrue,
        );
        await tester.scrollUntilVisible(
          legacyArchiveFinder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(legacyArchiveFinder, findsOneWidget);
      },
    );

    testWidgets(
      '5. Transactions, Reports, and Composer remove multi-currency filters/selectors/diagnostics while isolating legacy entries',
      (tester) async {
        final fixture = await tester.runAsync(
          () => _createFixture(insertLegacyUsd: true),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          fixture!.controller.dispose();
          final closeFuture = fixture.db.close();
          await tester.runAsync(
            () => closeFuture.timeout(const Duration(seconds: 10)),
          );
        });

        await tester.runAsync(() async {
          await fixture!.controller.recordDirectExpense(
            accountId: 'acc-cbe',
            categoryId: 'cat-food',
            amountCents: 12000,
            date: CalendarDate(year: 2026, month: 11, day: 11),
            description: 'Injera lunch',
          );
        });

        // Transactions tab: isolates USD entry under collapsed Legacy Non-ETB Entries
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: FinanceTransactionsTab(controller: fixture!.controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Injera lunch'), findsOneWidget);
        expect(
          find.textContaining('Legacy Non-ETB Entries (1) · Read-Only'),
          findsOneWidget,
        );
        expect(find.textContaining('All Currencies'), findsNothing);
        expect(find.textContaining('Currency Review'), findsNothing);

        // Reports tab: renders Account Balances (ETB) without ETB Currency Isolation Summary
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: FinanceReportsTab(controller: fixture.controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final accountBalancesFinder = find.text('Account Balances (ETB)');
        await tester.scrollUntilVisible(
          accountBalancesFinder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(accountBalancesFinder, findsOneWidget);
        expect(
          find.textContaining('ETB Currency Isolation Summary'),
          findsNothing,
        );
        expect(find.textContaining('Non-ETB / Review'), findsNothing);

        // Composer sheet: omits Dollar Cash & non-ETB banners
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: FinanceComposerSheet(controller: fixture.controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Dollar Cash'), findsNothing);
        expect(find.textContaining('First-Release'), findsNothing);

        // Source checks across UI screens prevent regression of removed multi-currency labels
        final uiFiles = [
          'lib/ui/screens/finance/finance_overview_tab.dart',
          'lib/ui/screens/finance/finance_transactions_tab.dart',
          'lib/ui/screens/finance/finance_plan_tab.dart',
          'lib/ui/screens/finance/finance_reports_tab.dart',
          'lib/ui/screens/finance/finance_composer_sheet.dart',
          'lib/ui/screens/finance/finance_setup_wizard.dart',
          'lib/ui/screens/dashboard_view.dart',
          'lib/ui/widgets/quick_capture_dialog.dart',
        ];
        final forbidden = [
          'Currency Review',
          'first-release',
          'First-Release',
          'All Currencies',
          'All Currency Statuses',
          'Non-ETB Accounts Excluded',
          'ETB Currency Isolation Summary',
        ];
        for (final rel in uiFiles) {
          final src = File(rel).readAsStringSync();
          for (final marker in forbidden) {
            expect(
              src.contains(marker),
              isFalse,
              reason: '$rel must not contain Stage 3 removed marker "$marker"',
            );
          }
        }
      },
    );
  });
}
