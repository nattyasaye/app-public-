import 'dart:async';
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
  AppStateManager state, {
  Directory? tempDir,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  if (!state.isDisposed) {
    await tester.runAsync(
      () => state.disposeAsync().timeout(const Duration(seconds: 10)),
    );
  }
  if (tempDir != null && tempDir.existsSync()) {
    tempDir.deleteSync(recursive: true);
  }
}

({AppStateManager manager, Directory tempDir}) _createIsolatedManager(
  AppDatabase db, {
  _RecordingNotificationService? recorder,
}) {
  final tempDir = Directory.systemTemp.createTempSync('daywell_s416_state_');
  final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
  final supportDir = Directory(p.join(tempDir.path, 'support'))..createSync();
  final manager = AppStateManager(
    db: db,
    recoveryExporter: RawDatabaseRecoveryExporter(
      documentsDirProvider: () async => docsDir,
      supportDirProvider: () async => supportDir,
    ),
    notificationService: recorder ?? _RecordingNotificationService(),
  );
  return (manager: manager, tempDir: tempDir);
}

class _IsolatedWidgetState {
  final AppDatabase db;
  final AppStateManager manager;
  final Directory tempDir;

  const _IsolatedWidgetState({
    required this.db,
    required this.manager,
    required this.tempDir,
  });
}

Future<_IsolatedWidgetState> _initializeIsolatedWidgetState(
  WidgetTester tester,
) async {
  final result = await tester.runAsync(() async {
    final db = AppDatabase(NativeDatabase.memory());
    final isolated = _createIsolatedManager(db);
    final manager = isolated.manager;
    final tempDir = isolated.tempDir;
    try {
      await db.ensureInitialized().timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException(
              'db.ensureInitialized() timed out after 15s',
            ),
          );
      await manager.initialize().timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException(
              'manager.initialize() timed out after 15s',
            ),
          );
      return _IsolatedWidgetState(
        db: db,
        manager: manager,
        tempDir: tempDir,
      );
    } catch (_) {
      try {
        if (!manager.isDisposed) {
          await manager.disposeAsync().timeout(const Duration(seconds: 3));
        }
      } catch (_) {}
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      rethrow;
    }
  });
  return result!;
}

void main() {
  configureSqliteForHostTests();

  group('Stage 4.8 / 4.15 / 4.16 Finance Integration', () {
    test('schedules outflow and inflow commitment due reminders safely',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      final recorder = _RecordingNotificationService();
      final isolated = _createIsolatedManager(db, recorder: recorder);
      final manager = isolated.manager;
      final tempDir = isolated.tempDir;
      addTearDown(() async {
        if (!manager.isDisposed) {
          await manager.disposeAsync().timeout(const Duration(seconds: 10));
        }
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      await manager.initialize().timeout(const Duration(seconds: 15));

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

      await manager.disposeAsync().timeout(const Duration(seconds: 10));
    });

    testWidgets(
      'QuickCaptureDialog hands off expense text to Finance Composer',
      (tester) async {
        final setup = await _initializeIsolatedWidgetState(tester);
        final manager = setup.manager;
        final tempDir = setup.tempDir;
        addTearDown(() => disposeTestState(tester, manager, tempDir: tempDir));

        Future<void> settle() => tester.pumpAndSettle(
              const Duration(milliseconds: 100),
              EnginePhase.sendSemanticsUpdate,
              const Duration(seconds: 5),
            );

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
        await settle();

        await tester.enterText(find.byType(TextField), 'Coffee 125.50');
        await tester.tap(find.text('Expense'));
        await settle();

        expect(find.text('Open in Composer'), findsOneWidget);
        await tester.tap(find.text('Open in Composer'));
        await settle();

        expect(receivedText, 'Coffee 125.50');
        await disposeTestState(tester, manager, tempDir: tempDir);
      },
    );

    testWidgets(
      'Overview & Reports display Option 1 Prepaid Card Credit and v7 audit info',
      (tester) async {
        final setup = await _initializeIsolatedWidgetState(tester);
        final db = setup.db;
        final manager = setup.manager;
        final tempDir = setup.tempDir;
        addTearDown(() => disposeTestState(tester, manager, tempDir: tempDir));

        Future<void> settle() => tester.pumpAndSettle(
              const Duration(milliseconds: 100),
              EnginePhase.sendSemanticsUpdate,
              const Duration(seconds: 5),
            );

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
        await settle();
        expect(find.textContaining('Prepaid Card Credit'), findsWidgets);
        expect(
          find.textContaining('Historical Non-ETB Records Preserved'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Legacy Non-ETB Archive (Read-Only)'),
          findsOneWidget,
        );
        expect(find.text('Breakdown'), findsOneWidget);

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: FinanceReportsTab(controller: manager.financeController),
            ),
          ),
        );
        await settle();
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
        await disposeTestState(tester, manager, tempDir: tempDir);
      },
    );

    test(
        'restoreFromEncryptedBackup uses quarantine swap when builder is present',
        () async {
      final tempDir = Directory.systemTemp.createTempSync('daywell_s416_');
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
      addTearDown(() async {
        if (!manager.isDisposed) {
          await manager.disposeAsync().timeout(const Duration(seconds: 10));
        }
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      await manager.initialize().timeout(const Duration(seconds: 15));
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
      await manager.disposeAsync().timeout(const Duration(seconds: 10));
    });
  });
}
