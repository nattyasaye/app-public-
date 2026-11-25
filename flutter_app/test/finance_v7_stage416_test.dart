import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/interfaces/platform_service_interfaces.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/raw_database_recovery_exporter.dart';
import 'package:personal_management_app/domain/finance/double_entry_engine.dart';
import 'package:personal_management_app/ui/app_state.dart';
import 'package:personal_management_app/ui/screens/finance/finance_overview_tab.dart';
import 'package:personal_management_app/ui/screens/finance/finance_reports_tab.dart';
import 'package:personal_management_app/ui/widgets/quick_capture_dialog.dart';

import 'support/sqlite_test_helper.dart';

class _RecordingNotificationService implements INotificationService {
  final List<({String id, String title, String body, String? payload})> calls =
      [];

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> scheduleReminder({
    required String id,
    required String title,
    required String body,
    required DateTime scheduledDateUtc,
    String? payload,
  }) async {
    calls.add((id: id, title: title, body: body, payload: payload));
  }

  @override
  Future<void> cancelReminder(String id) async {}

  @override
  Future<void> cancelAllReminders() async {}
}

Future<void> disposeTestState(
  WidgetTester tester,
  AppStateManager state,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
  var disposed = false;
  final disposeFuture = state.disposeAsync().whenComplete(() {
    disposed = true;
  });
  final stopwatch = Stopwatch()..start();
  while (!disposed && stopwatch.elapsed < const Duration(seconds: 10)) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  if (disposed) {
    await disposeFuture;
  } else {
    await tester.runAsync(
      () => disposeFuture.timeout(const Duration(seconds: 5)),
    );
  }
}

void main() {
  configureSqliteForHostTests();

  group('Stage 4.8 / 4.15 / 4.16 Finance Integration', () {
    test('schedules outflow and inflow commitment due reminders safely',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      final recorder = _RecordingNotificationService();
      final manager = AppStateManager(
        db: db,
        notificationService: recorder,
      );
      await manager.initialize();

      final today = CalendarDate.today();
      await manager.financeController.addCommitment(
        CommitmentModel(
          id: 'comm-out-due',
          title: 'Electricity Bill',
          amountCents: 15000,
          dueDate: today,
          direction: CommitmentDirection.outflow,
        ),
      );
      await manager.financeController.addCommitment(
        CommitmentModel(
          id: 'comm-in-due',
          title: 'Client Retainer',
          amountCents: 250000,
          dueDate: today.addDays(1),
          direction: CommitmentDirection.inflow,
        ),
      );
      await manager.syncFinanceDueReminders(asOfDate: today);

      expect(
        recorder.calls.any(
          (c) =>
              c.id == 'fin_commitment_comm-out-due' &&
              c.title.contains('Bill Due'),
        ),
        isTrue,
      );
      expect(
        recorder.calls.any(
          (c) =>
              c.id == 'fin_commitment_comm-in-due' &&
              c.title.contains('Expected Income Due'),
        ),
        isTrue,
      );

      await manager.disposeAsync();
    });

    testWidgets(
      'QuickCaptureDialog hands off expense text to Finance Composer',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        final manager = AppStateManager(
          db: db,
          notificationService: _RecordingNotificationService(),
        );
        await tester.runAsync(() => manager.initialize());
        addTearDown(() => disposeTestState(tester, manager));

        String? receivedText;
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    showDialog<void>(
                      context: ctx,
                      builder: (_) => QuickCaptureDialog(
                        state: manager,
                        onOpenExpenseComposer: (raw) => receivedText = raw,
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'Coffee 125.50');
        await tester.tap(find.text('Expense'));
        await tester.pumpAndSettle();

        expect(find.text('Open in Composer'), findsOneWidget);
        await tester.tap(find.text('Open in Composer'));
        await tester.pumpAndSettle();

        expect(receivedText, 'Coffee 125.50');
      },
    );

    testWidgets(
      'Overview & Reports display Option 1 Prepaid Card Credit and v7 audit info',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        final manager = AppStateManager(
          db: db,
          notificationService: _RecordingNotificationService(),
        );
        await tester.runAsync(() => manager.initialize());
        addTearDown(() => disposeTestState(tester, manager));

        await tester.runAsync(() async {
          await manager.financeController.addAccount(
            name: 'Prepaid Card',
            type: AccountType.liability,
            subType: AccountSubType.creditCard,
            openingBalanceCents: -30000,
          );
          await db.into(db.accountsTable).insert(
                AccountsTableCompanion.insert(
                  id: 'acc-legacy-usd',
                  name: 'USD Account',
                  type: 'asset',
                  subType: const Value('bank'),
                  currencyCode: const Value('USD'),
                  openingBalanceCents: const Value(10000),
                  createdAt: DateTime.utc(2026, 11, 1),
                ),
              );
          await manager.financeController.loadAll();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: FinanceOverviewTab(controller: manager.financeController),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Prepaid Card Credit'), findsWidgets);
        expect(
            find.textContaining('Non-ETB Accounts Excluded'), findsOneWidget);
        expect(find.text('Breakdown'), findsOneWidget);

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: FinanceReportsTab(controller: manager.financeController),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final reportsScrollable = find.byType(Scrollable).first;
        final auditTitle = find.textContaining('Ledger Integrity & v7 Audit');
        await tester.scrollUntilVisible(
          auditTitle,
          200,
          scrollable: reportsScrollable,
        );
        expect(auditTitle, findsOneWidget);
        final prepaidText = find.textContaining('Prepaid Card Credit');
        await tester.scrollUntilVisible(
          prepaidText,
          -200,
          scrollable: reportsScrollable,
        );
        expect(prepaidText, findsOneWidget);
      },
    );

    test(
        'restoreFromEncryptedBackup uses quarantine swap when builder is present',
        () async {
      final tempDir = Directory.systemTemp.createTempSync('daywell_s416_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final dbFile = File(p.join(tempDir.path, 'live.sqlite'));
      final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
      final supportDir = Directory(p.join(tempDir.path, 'support'))
        ..createSync();

      final manager = AppStateManager(
        databaseBuilder: () => AppDatabase(NativeDatabase(dbFile)),
        recoveryExporter: RawDatabaseRecoveryExporter(
          documentsDirProvider: () async => docsDir,
          supportDirProvider: () async => supportDir,
        ),
        notificationService: _RecordingNotificationService(),
      );
      await manager.initialize();
      await manager.financeController.addAccount(
        name: 'Primary Cash',
        type: AccountType.asset,
        subType: AccountSubType.cash,
        openingBalanceCents: 100000,
      );
      final backupEnvelope = await manager.exportEncryptedBackup('secret123');

      await manager.financeController.addAccount(
        name: 'Extra Cash',
        type: AccountType.asset,
        subType: AccountSubType.cash,
        openingBalanceCents: 50000,
      );
      expect(manager.liquidCashCents, 150000);

      final restored =
          await manager.restoreFromEncryptedBackup(backupEnvelope, 'secret123');
      expect(restored, isTrue);
      expect(manager.liquidCashCents, 100000);
      await manager.disposeAsync();
    });
  });
}
