import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/finance/finance_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/interfaces/platform_service_interfaces.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/database_persistence_coordinator.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';
import 'package:personal_management_app/domain/finance/finance_contracts.dart';
import 'package:personal_management_app/ui/app_state.dart';
import 'package:personal_management_app/ui/screens/finance/finance_sms_drafts_sheet.dart';

import 'support/sqlite_test_helper.dart';

class _FakeSmsInboxService implements ISmsInboxService {
  DeviceSmsPermissionStatus status;
  DeviceSmsPermissionStatus permissionAfterRequest;
  List<RawDeviceSmsMessage> inboxMessages;
  bool lockAcquiredResult = true;
  bool dailyScanScheduled = false;
  int requestPermissionCalls = 0;
  int openAppSettingsCalls = 0;
  int scheduleDailyScanCalls = 0;
  int cancelDailyScanCalls = 0;
  int readInboxCalls = 0;
  DateTime? lastSinceUtc;
  Completer<void>? readGate;

  _FakeSmsInboxService({
    this.status = DeviceSmsPermissionStatus.notRequested,
    this.permissionAfterRequest = DeviceSmsPermissionStatus.granted,
    List<RawDeviceSmsMessage>? inboxMessages,
  }) : inboxMessages = inboxMessages ?? <RawDeviceSmsMessage>[];

  @override
  Future<DeviceSmsPermissionStatus> getPermissionStatus() async => status;

  @override
  Future<DeviceSmsPermissionStatus> requestPermission() async {
    requestPermissionCalls++;
    status = permissionAfterRequest;
    return status;
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCalls++;
    return true;
  }

  @override
  Future<List<RawDeviceSmsMessage>> readInboxMessages({
    DateTime? sinceUtc,
    int limit = 500,
  }) async {
    readInboxCalls++;
    lastSinceUtc = sinceUtc;
    if (readGate != null && !readGate!.isCompleted) {
      await readGate!.future;
    }
    return inboxMessages
        .where(
          (m) => sinceUtc == null || !m.receivedAtUtc.isBefore(sinceUtc),
        )
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<void> scheduleDailyScan() async {
    scheduleDailyScanCalls++;
    dailyScanScheduled = true;
  }

  @override
  Future<void> cancelDailyScan() async {
    cancelDailyScanCalls++;
    dailyScanScheduled = false;
  }

  @override
  Future<bool> isDailyScanScheduled() async => dailyScanScheduled;

  @override
  Future<bool> tryAcquireScanLock() async => lockAcquiredResult;

  @override
  Future<void> releaseScanLock() async {}
}

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage 6 — Android SMS Reading & Daily Scheduled Scanning', () {
    test(
      '1. Pure domain scanner: 7-day lookback, 20m overlap, catch-up rules, sender filtering & failed/OTP exclusion',
      () {
        final now = DateTime.utc(2026, 11, 27, 12, 0, 0);

        // Initial lookback (no checkpoint) -> 7 days
        expect(
          FinanceSmsInboxScanner.computeInboxReadWindowStartUtc(nowUtc: now),
          now.subtract(const Duration(days: 7)),
        );

        // Incremental checkpoint -> 20-minute overlap
        final checkpoint = DateTime.utc(2026, 11, 27, 8, 30, 0);
        expect(
          FinanceSmsInboxScanner.computeInboxReadWindowStartUtc(
            checkpointUtc: checkpoint,
            nowUtc: now,
          ),
          DateTime.utc(2026, 11, 27, 8, 10, 0),
        );

        // Catch-up conditions
        expect(
          FinanceSmsInboxScanner.shouldRunForegroundCatchUp(
            isPermissionGranted: false,
            checkpoint: const SmsScanCheckpointState(),
            nowUtc: now,
          ),
          isFalse,
        );
        expect(
          FinanceSmsInboxScanner.shouldRunForegroundCatchUp(
            isPermissionGranted: true,
            checkpoint: const SmsScanCheckpointState(dailyScanEnabled: false),
            nowUtc: now,
          ),
          isTrue,
        );
        expect(
          FinanceSmsInboxScanner.shouldRunForegroundCatchUp(
            isPermissionGranted: true,
            checkpoint: const SmsScanCheckpointState(lastSuccessUtc: null),
            nowUtc: now,
          ),
          isTrue,
        );
        expect(
          FinanceSmsInboxScanner.shouldRunForegroundCatchUp(
            isPermissionGranted: true,
            checkpoint: SmsScanCheckpointState(
              lastSuccessUtc: now.subtract(const Duration(hours: 24)),
            ),
            nowUtc: now,
          ),
          isFalse,
        );
        expect(
          FinanceSmsInboxScanner.shouldRunForegroundCatchUp(
            isPermissionGranted: true,
            checkpoint: SmsScanCheckpointState(
              lastSuccessUtc: now.subtract(const Duration(hours: 26)),
              lastScanAttemptUtc: now.subtract(const Duration(minutes: 2)),
            ),
            nowUtc: now,
          ),
          isFalse, // Still in 5-minute attempt cooldown
        );
        expect(
          FinanceSmsInboxScanner.shouldRunForegroundCatchUp(
            isPermissionGranted: true,
            checkpoint: SmsScanCheckpointState(
              lastSuccessUtc: now.subtract(const Duration(hours: 26)),
              lastScanAttemptUtc: now.subtract(const Duration(minutes: 6)),
            ),
            nowUtc: now,
          ),
          isTrue,
        );

        // Sender & body classification
        final personalMsg = SmsInboxMessage(
          deviceMessageId: '1',
          senderAddress: '+251911223344',
          body: 'Hey, I sent you ETB 500.00 earlier today.',
          receivedAtUtc: now,
        );
        expect(
          FinanceSmsInboxScanner.evaluateInboxMessage(personalMsg)
              .isIgnoredNonTransactional,
          isTrue,
        );

        // Explicit user alias enables a custom/numeric sender
        final aliasedPersonal = FinanceSmsInboxScanner.evaluateInboxMessage(
          SmsInboxMessage(
            deviceMessageId: '2',
            senderAddress: '+251911223344',
            body:
                'Your account 1****4321 was debited with ETB 350.00 for Lunch. Available Balance: ETB 12,000.00.',
            receivedAtUtc: now,
          ),
          userAliases: const {'+251911223344': SmsProvider.boa},
        );
        expect(aliasedPersonal.isIgnoredNonTransactional, isFalse);
        expect(aliasedPersonal.draft?.provider, SmsProvider.boa);
        expect(aliasedPersonal.draft?.principalCents, 35000);

        // Unknown bank named sender rejected cleanly
        final otherBank = FinanceSmsInboxScanner.evaluateInboxMessage(
          SmsInboxMessage(
            deviceMessageId: '3',
            senderAddress: 'DashenBank',
            body: 'Your account 1****1111 was debited with ETB 200.00.',
            receivedAtUtc: now,
          ),
        );
        expect(otherBank.isIgnoredNonTransactional, isTrue);

        // Failed / declined / insufficient-balance excluded
        final declined = FinanceSmsInboxScanner.evaluateInboxMessage(
          SmsInboxMessage(
            deviceMessageId: '4',
            senderAddress: 'Telebirr',
            body:
                'Your Telebirr transaction failed due to insufficient balance for ETB 900.00.',
            receivedAtUtc: now,
          ),
        );
        expect(declined.isIgnoredNonTransactional, isTrue);

        // Conflicting sender vs body provider rejected cleanly
        final conflict = FinanceSmsInboxScanner.evaluateInboxMessage(
          SmsInboxMessage(
            deviceMessageId: '5',
            senderAddress: 'Telebirr',
            body:
                'You have successfully transferred ETB 1,000.00. https://apps.cbe.com.et:100/?id=FT26326X1',
            receivedAtUtc: now,
          ),
        );
        expect(conflict.isIgnoredNonTransactional, isTrue);

        // BOA POS lock stays non-ledger unrecognized notice (never an expense)
        final boaPosLock = FinanceSmsInboxScanner.evaluateInboxMessage(
          SmsInboxMessage(
            deviceMessageId: '6',
            senderAddress: 'BOA',
            body:
                'ETB 240.00 is Locked From Your Account 1****4321 Due to POS TRANSACTION at KALDIS COFFEE. Your Available Balance is ETB 14,309.50.',
            receivedAtUtc: now,
          ),
        );
        expect(boaPosLock.isIgnoredNonTransactional, isFalse);
        expect(boaPosLock.draft?.status, SmsDraftStatus.unrecognized);
        expect(boaPosLock.draft?.isNonLedgerNotice, isTrue);
        expect(boaPosLock.draft?.canApprove, isFalse);

        // Varied target senders (CBE_Alert, BOA_SMS, Telebirr_ET) & CBE debit without URL
        final cbeAlertMsg = FinanceSmsInboxScanner.evaluateInboxMessage(
          SmsInboxMessage(
            deviceMessageId: '7',
            senderAddress: 'CBE_Alert',
            body:
                'Your account 1****5678 was debited with ETB 250.00. Current balance is ETB 19,750.00.',
            receivedAtUtc: now,
          ),
        );
        expect(cbeAlertMsg.isIgnoredNonTransactional, isFalse);
        expect(cbeAlertMsg.draft?.provider, SmsProvider.cbe);
        expect(cbeAlertMsg.draft?.principalCents, 25000);
        expect(
          cbeAlertMsg.draft?.suggestedType,
          SmsSuggestedTransactionType.expense,
        );

        final boaSmsMsg = FinanceSmsInboxScanner.evaluateInboxMessage(
          SmsInboxMessage(
            deviceMessageId: '8',
            senderAddress: 'BOA_SMS',
            body:
                'Your account 1****4321 was credited with ETB 900.00 by Mekdes. Available Balance: ETB 15,209.50.',
            receivedAtUtc: now,
          ),
        );
        expect(boaSmsMsg.isIgnoredNonTransactional, isFalse);
        expect(boaSmsMsg.draft?.provider, SmsProvider.boa);
        expect(boaSmsMsg.draft?.principalCents, 90000);

        final carrierExplicitBrand =
            FinanceSmsInboxScanner.evaluateInboxMessage(
          SmsInboxMessage(
            deviceMessageId: '9',
            senderAddress: 'BankAlert',
            body:
                'Your account 1****5678 was debited with ETB 120.00. https://apps.cbe.com.et:100/?id=FT26331BRAND',
            receivedAtUtc: now,
          ),
        );
        expect(carrierExplicitBrand.isIgnoredNonTransactional, isFalse);
        expect(carrierExplicitBrand.draft?.provider, SmsProvider.cbe);

        // Excluded competing wallets/banks, amount-only texts, and OTPs
        final cbeBirrExcluded = FinanceSmsInboxScanner.evaluateInboxMessage(
          SmsInboxMessage(
            deviceMessageId: '10',
            senderAddress: 'CBEBirr',
            body: 'Your account 1****1111 was debited with ETB 100.00.',
            receivedAtUtc: now,
          ),
        );
        expect(cbeBirrExcluded.isIgnoredNonTransactional, isTrue);

        final amountOnlyExcluded = FinanceSmsInboxScanner.evaluateInboxMessage(
          SmsInboxMessage(
            deviceMessageId: '11',
            senderAddress: '9900',
            body: 'ETB 500.00',
            receivedAtUtc: now,
          ),
        );
        expect(amountOnlyExcluded.isIgnoredNonTransactional, isTrue);

        final otpExcluded = FinanceSmsInboxScanner.evaluateInboxMessage(
          SmsInboxMessage(
            deviceMessageId: '12',
            senderAddress: 'Telebirr_ET',
            body:
                'Telebirr: Your One Time Password OTP is 654321. Do not share your OTP.',
            receivedAtUtc: now,
          ),
        );
        expect(otpExcluded.isIgnoredNonTransactional, isTrue);
      },
    );

    test(
      '2. SQLite atomic per-message checkpoint rollback, retry deduplication, and backup privacy exclusion',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        final repo = DriftFinanceRepository(db);
        addTearDown(() async => await db.close());

        await repo.completeFinanceSetup([
          AccountModel(
            id: 'acc-cbe',
            name: 'CBE Checking 5678',
            type: AccountType.asset,
            subType: AccountSubType.bank,
            openingBalanceCents: 2000000,
            openingBalanceDate: '2026-11-01',
          ),
        ]);

        // Empty inbox scan writes lastSuccessUtc without fabricating checkpoint
        final emptySuccessUtc = DateTime.utc(2026, 11, 27, 7, 30, 0);
        final emptyRes = await repo.importInboxSmsBatchWithCheckpoint(
          messages: const <SmsInboxMessage>[],
          completedAtUtc: emptySuccessUtc,
        );
        expect(emptyRes.batch.importedCount, 0);
        expect(emptyRes.updatedCheckpointUtc, isNull);
        final cpAfterEmpty = await repo.getSmsScanCheckpointState();
        expect(cpAfterEmpty.lastProcessedReceivedAtUtc, isNull);
        expect(cpAfterEmpty.lastSuccessUtc, emptySuccessUtc);

        final t1 = DateTime.utc(2026, 11, 27, 8, 0, 0);
        final t2 = DateTime.utc(2026, 11, 27, 9, 0, 0);
        final t3 = DateTime.utc(2026, 11, 27, 10, 0, 0);

        final msgsOutOfOrder = <SmsInboxMessage>[
          SmsInboxMessage(
            deviceMessageId: '30',
            senderAddress: 'CBE',
            body:
                'Your account 1****5678 was credited with ETB 750.00 by Hanna. Available Balance: ETB 20,750.00. https://apps.cbe.com.et:100/?id=FT26331C3',
            receivedAtUtc: t3,
          ),
          SmsInboxMessage(
            deviceMessageId: '10',
            senderAddress: 'CBE',
            body:
                'Your account 1****5678 was debited with ETB 150.00. Current balance is ETB 19,850.00. https://apps.cbe.com.et:100/?id=FT26331C1',
            receivedAtUtc: t1,
          ),
          SmsInboxMessage(
            deviceMessageId: '20',
            senderAddress: 'Telebirr',
            body:
                'You have paid ETB 200.00 to Cafe (251911223344) on 27/11/2026 12:00:00. Your transaction number is TB26331T2. Your current E-Money Account balance is ETB 800.00.',
            receivedAtUtc: t2,
          ),
        ];

        // Inject failure inside tx on index 1 (message t2) after chronological sort
        repo.onBeforeCommitInboxMessageForTesting = (msg, idx) async {
          if (idx == 1) {
            throw StateError('Simulated SQLite crash mid-batch');
          }
        };

        await expectLater(
          () => repo.importInboxSmsBatchWithCheckpoint(
            messages: msgsOutOfOrder,
            completedAtUtc: DateTime.utc(2026, 11, 27, 10, 5, 0),
          ),
          throwsStateError,
        );

        // Message 1 committed cleanly; Message 2 rolled back; checkpoint stayed at t1; lastSuccess is null
        final afterPartialFailDrafts = await repo.getSmsDrafts();
        expect(afterPartialFailDrafts.length, 1);
        expect(afterPartialFailDrafts.single.transactionReference, 'FT26331C1');
        final cpAfterFail = await repo.getSmsScanCheckpointState();
        expect(cpAfterFail.lastProcessedReceivedAtUtc, t1);
        expect(cpAfterFail.lastSuccessUtc, isNull);

        // Clear fault and retry full overlap window -> Stage 5 dedup skips t1, commits t2 & t3, sets t3 & lastSuccessUtc
        repo.onBeforeCommitInboxMessageForTesting = null;
        final retryResult = await repo.importInboxSmsBatchWithCheckpoint(
          messages: msgsOutOfOrder,
          completedAtUtc: DateTime.utc(2026, 11, 27, 10, 10, 0),
        );
        expect(retryResult.batch.importedCount, 2);
        expect(retryResult.batch.duplicateCount, 1);
        expect(retryResult.updatedCheckpointUtc, t3);

        final allDrafts = await repo.getSmsDrafts();
        expect(allDrafts.length, 3);
        expect(
          allDrafts.where((d) => d.provider == SmsProvider.cbe).length,
          2,
        );
        final cpAfterRetry = await repo.getSmsScanCheckpointState();
        expect(cpAfterRetry.lastProcessedReceivedAtUtc, t3);
        expect(
          cpAfterRetry.lastSuccessUtc,
          DateTime.utc(2026, 11, 27, 10, 10, 0),
        );

        // Same-timestamp messages must all import in deterministic ID order without skipping
        final tSame = DateTime.utc(2026, 11, 27, 11, 0, 0);
        final sameTsRes = await repo.importInboxSmsBatchWithCheckpoint(
          messages: <SmsInboxMessage>[
            SmsInboxMessage(
              deviceMessageId: '102',
              senderAddress: 'Telebirr',
              body:
                  'You have paid ETB 60.00 to Tea Shop (251911000002) on 27/11/2026 14:00:00. Your transaction number is TB26331SAME2. Your current E-Money Account balance is ETB 740.00.',
              receivedAtUtc: tSame,
            ),
            SmsInboxMessage(
              deviceMessageId: '101',
              senderAddress: 'BOA',
              body:
                  'Your account 1****4321 was debited with ETB 80.00 for Bakery. Available Balance: ETB 9,000.00. https://cs.bankofabyssinia.com/slip/?trx=FT26331SAME1',
              receivedAtUtc: tSame,
            ),
          ],
          completedAtUtc: DateTime.utc(2026, 11, 27, 11, 5, 0),
        );
        expect(sameTsRes.batch.importedCount, 2);
        expect(sameTsRes.updatedCheckpointUtc, tSame);
        expect((await repo.getSmsDrafts()).length, 5);

        // Privacy check: device_sms_* keys and smsDrafts excluded from canonical snapshot & finance-only export
        await repo.saveSmsSenderAliases(const {'cbe-alt': SmsProvider.cbe});
        final coordinator = DatabasePersistenceCoordinator(db);
        final snapshotJson = jsonEncode(await coordinator.exportSnapshot());
        expect(snapshotJson.contains('device_sms_'), isFalse);
        expect(snapshotJson.contains('FT26331C1'), isFalse);

        final financeOnly = await repo.exportFinanceOnlyJson();
        expect(financeOnly.contains('device_sms_'), isFalse);
        expect(financeOnly.contains('TB26331T2'), isFalse);
      },
    );

    test(
      '3. FinanceController lifecycle: denial, permission grant, WorkManager reconciliation, catch-up, lock serialization, headless scan & zero ledger mutation',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        final repo = DriftFinanceRepository(db);
        var currentNow = DateTime.utc(2026, 11, 27, 12, 0, 0);

        final fakeService = _FakeSmsInboxService(
          status: DeviceSmsPermissionStatus.notRequested,
          permissionAfterRequest: DeviceSmsPermissionStatus.denied,
          inboxMessages: <RawDeviceSmsMessage>[
            RawDeviceSmsMessage(
              deviceMessageId: 'm1',
              senderAddress: 'CBE',
              body:
                  'Your account 1****5678 was debited with ETB 400.00. Current balance is ETB 19,600.00. https://apps.cbe.com.et:100/?id=FT26331SCAN1',
              receivedAtUtc: DateTime.utc(2026, 11, 26, 12, 0, 0),
            ),
            RawDeviceSmsMessage(
              deviceMessageId: 'm-old',
              senderAddress: 'CBE',
              body:
                  'Your account 1****5678 was debited with ETB 99.00. https://apps.cbe.com.et:100/?id=FT_TOO_OLD',
              receivedAtUtc: DateTime.utc(2026, 11, 10, 12, 0, 0), // > 7d old
            ),
          ],
        );

        final controller = FinanceController(
          repository: repo,
          smsInboxService: fakeService,
          nowUtcProvider: () => currentNow,
        );
        addTearDown(() async {
          controller.dispose();
          await db.close();
        });

        await controller.completeSetup([
          AccountModel(
            id: 'acc-cbe',
            name: 'CBE Checking 5678',
            type: AccountType.asset,
            subType: AccountSubType.bank,
            openingBalanceCents: 2000000,
            openingBalanceDate: '2026-11-01',
          ),
        ]);

        // 3a. Graceful denial: cancels worker, never breaks Finance or manual paste
        final deniedRes = await controller.requestSmsPermissionAndScan();
        expect(deniedRes.skippedBecausePermission, isTrue);
        expect(fakeService.cancelDailyScanCalls, greaterThanOrEqualTo(1));
        expect(controller.state.smsScanCheckpoint.permissionAsked, isTrue);
        expect(controller.state.smsPermissionStatus, DeviceSmsPermissionStatus.denied);

        // Foreground catch-up after denial NEVER prompts again
        final catchUpAfterDeny = await controller.runForegroundCatchUpSmsScanIfNeeded();
        expect(catchUpAfterDeny.skippedBecausePermission, isTrue);
        expect(fakeService.requestPermissionCalls, 1);

        // 3b. Grant permission -> schedules daily worker + performs 7-day bounded scan (excludes 17-day-old SMS)
        fakeService.permissionAfterRequest = DeviceSmsPermissionStatus.granted;
        final grantRes = await controller.requestSmsPermissionAndScan();
        expect(grantRes.executed, isTrue);
        expect(grantRes.importedCount, 1);
        expect(fakeService.dailyScanScheduled, isTrue);
        expect(controller.state.smsDrafts.length, 1);
        expect(controller.state.smsDrafts.single.transactionReference, 'FT26331SCAN1');

        // Zero ledger/balance mutation before explicit user approval
        expect(controller.state.liquidCashCents, 2000000);
        expect(
          controller.state.journalEntries.where((e) => e.entryType == EntryType.standard),
          isEmpty,
        );

        // 3c. Fresh scan skips foreground catch-up; stale (>= 25h) triggers catch-up with 20m overlap
        currentNow = currentNow.add(const Duration(hours: 2));
        final freshCatchUp = await controller.runForegroundCatchUpSmsScanIfNeeded();
        expect(freshCatchUp.skippedBecauseFresh, isTrue);

        currentNow = currentNow.add(const Duration(hours: 24)); // total +26h
        fakeService.inboxMessages.add(
          RawDeviceSmsMessage(
            deviceMessageId: 'm2',
            senderAddress: 'Telebirr',
            body:
                'You have paid ETB 250.00 to Cafe Two (251911223344) on 28/11/2026 10:00:00. Your transaction number is TB26332TWO. Your current E-Money Account balance is ETB 750.00.',
            receivedAtUtc: DateTime.utc(2026, 11, 28, 7, 0, 0),
          ),
        );
        final staleCatchUp = await controller.runForegroundCatchUpSmsScanIfNeeded();
        expect(staleCatchUp.executed, isTrue);
        expect(staleCatchUp.importedCount, 1);
        expect(staleCatchUp.duplicateCount, 1); // m1 falls within 20m overlap window and is deduplicated cleanly
        expect(controller.state.smsDrafts.length, 2);

        // 3d. Concurrent native/in-flight lock guard prevents overlapping scans
        fakeService.lockAcquiredResult = false;
        final lockedRes = await controller.scanSmsInboxNow();
        expect(lockedRes.skippedBecauseLocked, isTrue);
        fakeService.lockAcquiredResult = true;

        // 3e. Disabling daily toggle cancels WorkManager ONLY; manual scan & foreground catch-up still work,
        // and background worker skips without calling scheduleDailyScan().
        await controller.setSmsDailyScanEnabled(false);
        expect(fakeService.dailyScanScheduled, isFalse);

        final scheduleCallsBeforeWorkerDisabled =
            fakeService.scheduleDailyScanCalls;
        final workerSkippedWhenDisabled =
            await controller.runBackgroundWorkerSmsScan();
        expect(workerSkippedWhenDisabled, isTrue);
        expect(fakeService.dailyScanScheduled, isFalse);
        expect(
          fakeService.scheduleDailyScanCalls,
          scheduleCallsBeforeWorkerDisabled,
        );

        currentNow = currentNow.add(const Duration(hours: 26));
        fakeService.inboxMessages.add(
          RawDeviceSmsMessage(
            deviceMessageId: 'm2b',
            senderAddress: 'CBE',
            body:
                'Your account 1****5678 was credited with ETB 300.00 by Selam. Current balance is ETB 19,900.00. https://apps.cbe.com.et:100/?id=FT26332CATCHUP',
            receivedAtUtc: DateTime.utc(2026, 11, 28, 9, 0, 0),
          ),
        );
        final catchUpWhileToggleOff =
            await controller.runForegroundCatchUpSmsScanIfNeeded();
        expect(catchUpWhileToggleOff.executed, isTrue);
        expect(catchUpWhileToggleOff.importedCount, 1);
        expect(fakeService.dailyScanScheduled, isFalse);

        await controller.setSmsDailyScanEnabled(true);
        expect(fakeService.dailyScanScheduled, isTrue);

        // Background worker scan runs cleanly without calling scheduleDailyScan() redundantly
        final scheduleCallsBeforeWorker = fakeService.scheduleDailyScanCalls;
        final workerOk = await controller.runBackgroundWorkerSmsScan();
        expect(workerOk, isTrue);
        expect(fakeService.scheduleDailyScanCalls, scheduleCallsBeforeWorker);

        fakeService.status = DeviceSmsPermissionStatus.denied;
        currentNow = currentNow.add(const Duration(hours: 30));
        final revokedRes = await controller.runForegroundCatchUpSmsScanIfNeeded();
        expect(revokedRes.skippedBecausePermission, isTrue);
        expect(fakeService.dailyScanScheduled, isFalse);

        // 3f. Headless WorkManager worker entrypoint runs against fresh SQLite & never re-schedules
        fakeService.status = DeviceSmsPermissionStatus.granted;
        fakeService.inboxMessages.add(
          RawDeviceSmsMessage(
            deviceMessageId: 'm3',
            senderAddress: 'BOA',
            body:
                'Your account 1****4321 was credited with ETB 1,200.00. Available Balance: ETB 2,000.00. https://cs.bankofabyssinia.com/slip/?trx=FT26333HEADLESS',
            receivedAtUtc: DateTime.utc(2026, 11, 28, 12, 0, 0),
          ),
        );
        final memHeadlessDb = AppDatabase(NativeDatabase.memory());
        await memHeadlessDb.ensureInitialized();
        final scheduleCallsBeforeHeadless = fakeService.scheduleDailyScanCalls;
        final headlessOk = await AppStateManager.runHeadlessBackgroundSmsScan(
          databaseBuilder: () => memHeadlessDb,
          smsInboxService: fakeService,
          nowUtcProvider: () => DateTime.utc(2026, 11, 28, 13, 0, 0),
        );
        expect(headlessOk, isTrue);
        expect(fakeService.scheduleDailyScanCalls, scheduleCallsBeforeHeadless);

        // 3g. Real-file SQLite persistence across closed foreground -> headless worker -> reopened foreground
        final tempDir =
            Directory.systemTemp.createTempSync('daywell_stage6_headless_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final dbFile = File('${tempDir.path}/personal_management.sqlite');
        final fgDb = AppDatabase(NativeDatabase(dbFile));
        await fgDb.ensureInitialized();
        final fgRepo = DriftFinanceRepository(fgDb);
        await fgRepo.completeFinanceSetup([
          AccountModel(
            id: 'acc-cbe',
            name: 'CBE Checking 5678',
            type: AccountType.asset,
            subType: AccountSubType.bank,
            openingBalanceCents: 2000000,
            openingBalanceDate: '2026-11-01',
          ),
        ]);
        await fgDb.close();

        final fileHeadlessService = _FakeSmsInboxService(
          status: DeviceSmsPermissionStatus.granted,
          inboxMessages: <RawDeviceSmsMessage>[
            RawDeviceSmsMessage(
              deviceMessageId: 'file-1',
              senderAddress: 'CBE',
              body:
                  'Your account 1****5678 was debited with ETB 650.00 for Internet. Current balance is ETB 19,350.00. https://apps.cbe.com.et:100/?id=FT26333FILE',
              receivedAtUtc: DateTime.utc(2026, 11, 28, 14, 0, 0),
            ),
          ],
        );
        final fileHeadlessOk =
            await AppStateManager.runHeadlessBackgroundSmsScan(
          databaseBuilder: () => AppDatabase(NativeDatabase(dbFile)),
          smsInboxService: fileHeadlessService,
          nowUtcProvider: () => DateTime.utc(2026, 11, 28, 15, 0, 0),
        );
        expect(fileHeadlessOk, isTrue);
        expect(fileHeadlessService.scheduleDailyScanCalls, 0);

        final reopenedDb = AppDatabase(NativeDatabase(dbFile));
        await reopenedDb.ensureInitialized();
        final reopenedController = FinanceController(
          repository: DriftFinanceRepository(reopenedDb),
          smsInboxService: fileHeadlessService,
        );
        await reopenedController.loadAll();
        expect(reopenedController.state.smsDrafts.length, 1);
        expect(
          reopenedController.state.smsDrafts.single.transactionReference,
          'FT26333FILE',
        );
        expect(
          reopenedController.state.smsDrafts.single.provider,
          SmsProvider.cbe,
        );
        expect(
          reopenedController.state.smsScanCheckpoint.lastProcessedReceivedAtUtc,
          DateTime.utc(2026, 11, 28, 14, 0, 0),
        );
        expect(reopenedController.state.liquidCashCents, 2000000);
        expect(
          reopenedController.state.journalEntries
              .where((e) => e.entryType == EntryType.standard),
          isEmpty,
        );
        reopenedController.dispose();
        await reopenedDb.close();
      },
    );

    testWidgets(
      '4. FinanceSmsDraftsSheet displays Android permission flow, daily toggle, and preserves manual paste',
      (WidgetTester tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        final repo = DriftFinanceRepository(db);
        final fakeService = _FakeSmsInboxService(
          status: DeviceSmsPermissionStatus.notRequested,
          permissionAfterRequest: DeviceSmsPermissionStatus.granted,
          inboxMessages: <RawDeviceSmsMessage>[
            RawDeviceSmsMessage(
              deviceMessageId: 'w1',
              senderAddress: 'Telebirr',
              body:
                  'You have paid ETB 120.00 to Coffee (251911223344) on 27/11/2026 09:00:00. Your transaction number is TB26331UI1. Your current E-Money Account balance is ETB 880.00.',
              receivedAtUtc: DateTime.utc(2026, 11, 27, 6, 0, 0),
            ),
          ],
        );
        final controller = FinanceController(
          repository: repo,
          smsInboxService: fakeService,
          nowUtcProvider: () => DateTime.utc(2026, 11, 27, 7, 0, 0),
        );
        await controller.completeSetup([
          AccountModel(
            id: 'acc-tb',
            name: 'Telebirr Wallet',
            type: AccountType.asset,
            subType: AccountSubType.mobileMoney,
            openingBalanceCents: 100000,
            openingBalanceDate: '2026-11-01',
          ),
        ]);
        addTearDown(() async {
          controller.dispose();
          await db.close();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: FinanceSmsDraftsSheet(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Android SMS Inbox Scanning'), findsOneWidget);
        expect(find.text('Allow SMS Inbox Reading'), findsOneWidget);
        expect(find.text('Import as Drafts'), findsOneWidget);

        await tester.tap(find.text('Allow SMS Inbox Reading'));
        await tester.pumpAndSettle();

        expect(fakeService.requestPermissionCalls, 1);
        expect(find.text('Scan Inbox Now'), findsOneWidget);
        expect(find.text('Daily background scan (~24h)'), findsOneWidget);
        expect(controller.state.smsDrafts.length, 1);
      },
    );
  });
}
