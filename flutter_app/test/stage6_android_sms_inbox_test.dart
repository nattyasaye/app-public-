import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/finance/finance_controller.dart';
import 'package:personal_management_app/core/interfaces/platform_service_interfaces.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/database_persistence_coordinator.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';
import 'package:personal_management_app/ui/app_state.dart';
import 'package:personal_management_app/ui/screens/finance/finance_sms_drafts_sheet.dart';

import 'support/sqlite_test_helper.dart';

class _FakeSmsInboxService implements ISmsInboxService {
  DeviceSmsPermissionStatus status;
  DeviceSmsPermissionStatus permissionAfterRequest;
  DeviceSmsPermissionStatus receiveStatus;
  DeviceSmsPermissionStatus receivePermissionAfterRequest =
      DeviceSmsPermissionStatus.granted;
  List<RawDeviceSmsMessage> inboxMessages;
  bool lockAcquiredResult = true;
  bool dailyScanScheduled = false;
  int requestPermissionCalls = 0;
  int requestReceivePermissionCalls = 0;
  int openAppSettingsCalls = 0;
  int scheduleDailyScanCalls = 0;
  int cancelDailyScanCalls = 0;
  int readInboxCalls = 0;
  DateTime? lastSinceUtc;
  Completer<void>? readGate;

  _FakeSmsInboxService({
    this.status = DeviceSmsPermissionStatus.notRequested,
    this.permissionAfterRequest = DeviceSmsPermissionStatus.granted,
    this.receiveStatus = DeviceSmsPermissionStatus.notRequested,
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
  Future<DeviceSmsPermissionStatus> getReceivePermissionStatus() async =>
      receiveStatus;

  @override
  Future<DeviceSmsPermissionStatus> requestReceivePermission() async {
    requestReceivePermissionCalls++;
    receiveStatus = receivePermissionAfterRequest;
    return receiveStatus;
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
        expect(
          controller.state.smsPermissionStatus,
          DeviceSmsPermissionStatus.denied,
        );

        // Foreground catch-up after denial NEVER prompts again
        final catchUpAfterDeny =
            await controller.runForegroundCatchUpSmsScanIfNeeded();
        expect(catchUpAfterDeny.skippedBecausePermission, isTrue);
        expect(fakeService.requestPermissionCalls, 1);

        // 3b. Grant permission -> schedules daily worker + performs 7-day bounded scan (excludes 17-day-old SMS)
        fakeService.permissionAfterRequest = DeviceSmsPermissionStatus.granted;
        final grantRes = await controller.requestSmsPermissionAndScan();
        expect(grantRes.executed, isTrue);
        expect(grantRes.importedCount, 1);
        expect(fakeService.dailyScanScheduled, isTrue);
        expect(controller.state.smsDrafts.length, 1);
        expect(
          controller.state.smsDrafts.single.transactionReference,
          'FT26331SCAN1',
        );

        // Zero ledger/balance mutation before explicit user approval
        expect(controller.state.liquidCashCents, 2000000);
        expect(
          controller.state.journalEntries
              .where((e) => e.entryType == EntryType.standard),
          isEmpty,
        );

        // 3c. Fresh scan skips foreground catch-up; stale (>= 25h) triggers catch-up with 20m overlap
        currentNow = currentNow.add(const Duration(hours: 2));
        final freshCatchUp =
            await controller.runForegroundCatchUpSmsScanIfNeeded();
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
        final staleCatchUp =
            await controller.runForegroundCatchUpSmsScanIfNeeded();
        expect(staleCatchUp.executed, isTrue);
        expect(staleCatchUp.importedCount, 1);
        // m1 falls within 20m overlap window and is deduplicated cleanly
        expect(staleCatchUp.duplicateCount, 1);
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
        final revokedRes =
            await controller.runForegroundCatchUpSmsScanIfNeeded();
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

        // Request RECEIVE_SMS independently without re-triggering READ_SMS scan.
        expect(find.text('Allow Immediate Incoming SMS'), findsOneWidget);
        await tester.tap(find.text('Allow Immediate Incoming SMS'));
        await tester.pumpAndSettle();

        expect(fakeService.requestReceivePermissionCalls, 1);
        expect(find.text('Active'), findsOneWidget);
        expect(
          controller.state.smsReceivePermissionStatus,
          DeviceSmsPermissionStatus.granted,
        );
        expect(find.text('Import as Drafts'), findsOneWidget);
      },
    );
  });

  group('Stage 6 — Immediate Incoming SMS Detection (SMS_RECEIVED)', () {
    test(
      '5. Immediate incoming SMS processes CBE, Telebirr, and BOA while rejecting unknown/unrelated alerts without ledger or periodic schedule mutations',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        final repo = DriftFinanceRepository(db);
        final now = DateTime.utc(2026, 11, 27, 10, 0, 0);

        final fakeService = _FakeSmsInboxService(
          status: DeviceSmsPermissionStatus.denied,
          receiveStatus: DeviceSmsPermissionStatus.granted,
        );
        final controller = FinanceController(
          repository: repo,
          smsInboxService: fakeService,
          nowUtcProvider: () => now,
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
          AccountModel(
            id: 'acc-tb',
            name: 'Telebirr Wallet',
            type: AccountType.asset,
            subType: AccountSubType.mobileMoney,
            openingBalanceCents: 100000,
            openingBalanceDate: '2026-11-01',
          ),
        ]);

        // READ_SMS is denied, yet RECEIVE_SMS direct broadcast payloads succeed without touching inbox or daily schedule.
        final cbeRes = await controller.processIncomingSmsEvent(
          message: RawDeviceSmsMessage(
            deviceMessageId: 'b-cbe',
            senderAddress: 'CBE',
            body:
                'Your account 1****5678 was debited with ETB 300.00 for Groceries. Current balance is ETB 19,700.00. https://apps.cbe.com.et:100/?id=FT26331IMM_CBE',
            receivedAtUtc: now,
          ),
        );
        expect(cbeRes.trigger, SmsScanTrigger.incomingBroadcast);
        expect(cbeRes.executed, isTrue);
        expect(cbeRes.importedCount, 1);

        final tbRes = await controller.processIncomingSmsEvent(
          message: RawDeviceSmsMessage(
            deviceMessageId: 'b-tb',
            senderAddress: 'Telebirr',
            body:
                'You have paid ETB 150.00 to Cafe (251911223344) on 27/11/2026 13:00:00. Your transaction number is TB26331IMM_TB. Your current E-Money Account balance is ETB 850.00.',
            receivedAtUtc: now.add(const Duration(minutes: 1)),
          ),
        );
        expect(tbRes.executed, isTrue);
        expect(tbRes.importedCount, 1);

        final boaRes = await controller.processIncomingSmsEvent(
          message: RawDeviceSmsMessage(
            deviceMessageId: 'b-boa',
            senderAddress: 'BOA',
            body:
                'Your account 1****4321 was credited with ETB 900.00 by Yohannes. Available Balance: ETB 15,000.00. https://cs.bankofabyssinia.com/slip/?trx=FT26331IMM_BOA',
            receivedAtUtc: now.add(const Duration(minutes: 2)),
          ),
        );
        expect(boaRes.executed, isTrue);
        expect(boaRes.importedCount, 1);

        // Unknown sender, personal number, and OTP alerts are rejected cleanly.
        final unknownBankRes = await controller.processIncomingSmsEvent(
          message: RawDeviceSmsMessage(
            deviceMessageId: 'b-unk',
            senderAddress: 'DashenBank',
            body: 'Your account 1****1111 was debited with ETB 500.00.',
            receivedAtUtc: now.add(const Duration(minutes: 3)),
          ),
        );
        expect(unknownBankRes.executed, isTrue);
        expect(unknownBankRes.importedCount, 0);
        expect(unknownBankRes.ignoredCount, 1);

        final personalRes = await controller.processIncomingSmsEvent(
          message: RawDeviceSmsMessage(
            deviceMessageId: 'b-pers',
            senderAddress: '+251911223344',
            body: 'Sent ETB 400.00 to your CBE account.',
            receivedAtUtc: now.add(const Duration(minutes: 4)),
          ),
        );
        expect(personalRes.importedCount, 0);
        expect(personalRes.ignoredCount, 1);

        final otpRes = await controller.processIncomingSmsEvent(
          message: RawDeviceSmsMessage(
            deviceMessageId: 'b-otp',
            senderAddress: 'Telebirr',
            body:
                'Telebirr: Your One Time Password OTP is 123456. Do not share.',
            receivedAtUtc: now.add(const Duration(minutes: 5)),
          ),
        );
        expect(otpRes.importedCount, 0);
        expect(otpRes.ignoredCount, 1);

        expect(controller.state.smsDrafts.length, 3);
        expect(fakeService.readInboxCalls, 0);
        expect(fakeService.scheduleDailyScanCalls, 0);
        expect(fakeService.dailyScanScheduled, isFalse);

        // Immediate events never advance the inbox full-scan checkpoint or post ledger entries.
        final cp = await repo.getSmsScanCheckpointState();
        expect(cp.lastProcessedReceivedAtUtc, isNull);
        expect(cp.lastSuccessUtc, isNull);
        expect(controller.state.liquidCashCents, 2100000);
        expect(
          controller.state.journalEntries
              .where((e) => e.entryType == EntryType.standard),
          isEmpty,
        );
      },
    );

    test(
      '6. Coexistence & deduplication: immediate event at 10:00 AM + earlier missed 09:00 AM SMS discovered by daily scan & foreground catch-up without duplicates',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        final repo = DriftFinanceRepository(db);
        var nowUtc = DateTime.utc(2026, 11, 27, 10, 0, 0);

        final missedNineAm = RawDeviceSmsMessage(
          deviceMessageId: 'inbox-9am',
          senderAddress: 'Telebirr',
          body:
              'You have paid ETB 80.00 to Tea Shop (251911000001) on 27/11/2026 09:00:00. Your transaction number is TB26331MISSED9. Your current E-Money Account balance is ETB 920.00.',
          receivedAtUtc: DateTime.utc(2026, 11, 27, 6, 0, 0),
        );
        final tenAmBroadcast = RawDeviceSmsMessage(
          deviceMessageId: 'broadcast-10am',
          senderAddress: 'CBE',
          body:
              'Your account 1****5678 was debited with ETB 250.00 for Market. Current balance is ETB 19,750.00. https://apps.cbe.com.et:100/?id=FT26331COEX10',
          receivedAtUtc: DateTime.utc(2026, 11, 27, 7, 0, 0),
        );
        final tenAmInboxRow = RawDeviceSmsMessage(
          deviceMessageId: 'inbox-10am',
          senderAddress: 'CBE',
          body: tenAmBroadcast.body,
          receivedAtUtc: tenAmBroadcast.receivedAtUtc,
        );

        final fakeService = _FakeSmsInboxService(
          status: DeviceSmsPermissionStatus.granted,
          receiveStatus: DeviceSmsPermissionStatus.granted,
          inboxMessages: <RawDeviceSmsMessage>[missedNineAm, tenAmInboxRow],
        );

        final controller = FinanceController(
          repository: repo,
          smsInboxService: fakeService,
          nowUtcProvider: () => nowUtc,
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

        // 10:00 AM immediate event arrives before any daily scan has run.
        final immRes = await controller.processIncomingSmsEvent(
          message: tenAmBroadcast,
        );
        expect(immRes.executed, isTrue);
        expect(immRes.importedCount, 1);
        expect(controller.state.smsDrafts.length, 1);

        // Daily WorkManager backup scan runs later at 10:30 AM.
        // Because immediate event left checkpoint untouched, 7-day lookback discovers missed 09:00 AM SMS
        // and deduplicates the 10:00 AM CBE SMS without creating a duplicate draft.
        nowUtc = DateTime.utc(2026, 11, 27, 7, 30, 0);
        final dailyOk = await controller.runBackgroundWorkerSmsScan();
        expect(dailyOk, isTrue);
        expect(controller.state.smsDrafts.length, 2);
        expect(
          controller.state.smsDrafts
              .where((d) => d.transactionReference == 'FT26331COEX10')
              .length,
          1,
        );
        expect(
          controller.state.smsDrafts
              .where((d) => d.transactionReference == 'TB26331MISSED9')
              .length,
          1,
        );

        // Now another immediate BOA SMS arrives, followed 26 hours later by foreground catch-up.
        final elevenAmBoa = RawDeviceSmsMessage(
          deviceMessageId: 'broadcast-11am',
          senderAddress: 'BOA',
          body:
              'Your account 1****4321 was debited with ETB 175.00 for Pharmacy. Available Balance: ETB 12,000.00. https://cs.bankofabyssinia.com/slip/?trx=FT26331CATCH11',
          receivedAtUtc: DateTime.utc(2026, 11, 27, 8, 0, 0),
        );
        fakeService.inboxMessages.add(
          RawDeviceSmsMessage(
            deviceMessageId: 'inbox-11am',
            senderAddress: 'BOA',
            body: elevenAmBoa.body,
            receivedAtUtc: elevenAmBoa.receivedAtUtc,
          ),
        );
        final immBoaRes = await controller.processIncomingSmsEvent(
          message: elevenAmBoa,
        );
        expect(immBoaRes.executed, isTrue);
        expect(immBoaRes.importedCount, 1);
        expect(controller.state.smsDrafts.length, 3);

        nowUtc = nowUtc.add(const Duration(hours: 26));
        final catchUpRes =
            await controller.runForegroundCatchUpSmsScanIfNeeded();
        expect(catchUpRes.executed, isTrue);
        expect(catchUpRes.importedCount, 0);
        expect(catchUpRes.duplicateCount, greaterThanOrEqualTo(1));
        expect(controller.state.smsDrafts.length, 3);
      },
    );

    test(
      '7. Late inbox materialization, fallback window closeness to checkpoint, and repository failure retry',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        final repo = DriftFinanceRepository(db);
        var nowUtc = DateTime.utc(2026, 11, 27, 10, 0, 0);

        final priorCheckpointTime = DateTime.utc(2026, 11, 27, 9, 55, 0);
        final priorInboxSms = RawDeviceSmsMessage(
          deviceMessageId: 'm-prior',
          senderAddress: 'CBE',
          body:
              'Your account 1****5678 was debited with ETB 100.00. Current balance is ETB 19,900.00. https://apps.cbe.com.et:100/?id=FT26331PRIOR',
          receivedAtUtc: priorCheckpointTime,
        );
        final fakeService = _FakeSmsInboxService(
          status: DeviceSmsPermissionStatus.granted,
          receiveStatus: DeviceSmsPermissionStatus.granted,
          inboxMessages: <RawDeviceSmsMessage>[priorInboxSms],
        );
        final controller = FinanceController(
          repository: repo,
          smsInboxService: fakeService,
          nowUtcProvider: () => nowUtc,
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

        // Establish a recent inbox checkpoint at 09:55 AM.
        await controller.scanSmsInboxNow();
        expect(controller.state.smsDrafts.length, 1);

        // Domain fallback window helper covers event timestamp close to checkpoint.
        final eventArrival = DateTime.utc(2026, 11, 27, 10, 0, 0);
        final fallbackWindow =
            FinanceSmsInboxScanner.computeIncomingEventFallbackWindowStartUtc(
          eventReceivedAtUtc: eventArrival,
          checkpointUtc: priorCheckpointTime,
        );
        expect(fallbackWindow.isBefore(priorCheckpointTime), isTrue);
        expect(fallbackWindow.isBefore(eventArrival), isTrue);

        // Case A: fallbackToInbox=true when Android inbox provider hasn't inserted the 10:00 AM SMS yet.
        // Note: inbox still contains the 09:55 AM SMS inside the overlap window, so we check recency near eventArrival!
        final missingAttempt = await controller.processIncomingSmsEvent(
          fallbackEventReceivedAtUtc: eventArrival,
          fallbackToInbox: true,
        );
        expect(missingAttempt.executed, isFalse);
        expect(missingAttempt.errorMessage, isNotNull);
        expect(controller.state.smsDrafts.length, 1);

        // Headless fallback retry also returns false (WorkManager Result.retry()) until SMS appears.
        final headlessMissing =
            await AppStateManager.runHeadlessIncomingSmsProcess(
          databaseBuilder: () => db,
          smsInboxService: fakeService,
          nowUtcProvider: () => nowUtc,
          fallbackEventReceivedAtUtc: eventArrival,
          fallbackToInbox: true,
        );
        expect(headlessMissing, isFalse);

        // SMS finishes inserting into Android Telephony.Sms.Inbox -> retry succeeds!
        fakeService.inboxMessages.add(
          RawDeviceSmsMessage(
            deviceMessageId: 'm-new-10am',
            senderAddress: 'Telebirr',
            body:
                'You have paid ETB 220.00 to Bookshop (251911223344) on 27/11/2026 13:00:00. Your transaction number is TB26331LATE10. Your current E-Money Account balance is ETB 780.00.',
            receivedAtUtc: eventArrival,
          ),
        );
        final retrySuccess = await controller.processIncomingSmsEvent(
          fallbackEventReceivedAtUtc: eventArrival,
          fallbackToInbox: true,
        );
        expect(retrySuccess.executed, isTrue);
        expect(retrySuccess.errorMessage, isNull);
        expect(retrySuccess.importedCount, 1);
        expect(controller.state.smsDrafts.length, 2);

        // Case B: Event-triggered repository failure triggers safe retry recovery without duplicates.
        repo.onBeforeCommitInboxMessageForTesting = (msg, idx) async {
          throw StateError('Simulated SQLite transient write error');
        };
        final failingBroadcast = RawDeviceSmsMessage(
          deviceMessageId: 'b-fail-retry',
          senderAddress: 'CBE',
          body:
              'Your account 1****5678 was debited with ETB 450.00. Current balance is ETB 19,450.00. https://apps.cbe.com.et:100/?id=FT26331RETRY_FAIL',
          receivedAtUtc: DateTime.utc(2026, 11, 27, 10, 15, 0),
        );
        final failRes = await controller.processIncomingSmsEvent(
          message: failingBroadcast,
        );
        expect(failRes.executed, isFalse);
        expect(failRes.errorMessage, isNotNull);
        expect(controller.state.smsDrafts.length, 2);

        repo.onBeforeCommitInboxMessageForTesting = null;
        final recoveredRes = await controller.processIncomingSmsEvent(
          message: failingBroadcast,
        );
        expect(recoveredRes.executed, isTrue);
        expect(recoveredRes.errorMessage, isNull);
        expect(recoveredRes.importedCount, 1);
        expect(controller.state.smsDrafts.length, 3);
      },
    );

    test(
      '8. Independent permission grant/denial/revocation & headless RECEIVE_SMS isolation',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        final repo = DriftFinanceRepository(db);
        final nowUtc = DateTime.utc(2026, 11, 27, 12, 0, 0);

        final fakeService = _FakeSmsInboxService(
          status: DeviceSmsPermissionStatus.granted,
          receiveStatus: DeviceSmsPermissionStatus.denied,
          inboxMessages: <RawDeviceSmsMessage>[
            RawDeviceSmsMessage(
              deviceMessageId: 'm-read-only',
              senderAddress: 'CBE',
              body:
                  'Your account 1****5678 was debited with ETB 120.00. Current balance is ETB 19,880.00. https://apps.cbe.com.et:100/?id=FT26331READONLY',
              receivedAtUtc: nowUtc.subtract(const Duration(minutes: 10)),
            ),
          ],
        );

        final controller = FinanceController(
          repository: repo,
          smsInboxService: fakeService,
          nowUtcProvider: () => nowUtc,
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
        await controller.setSmsDailyScanEnabled(true);
        expect(fakeService.dailyScanScheduled, isTrue);

        // When RECEIVE_SMS is denied, incoming broadcast processing skips cleanly without cancelling READ_SMS daily scan.
        final incomingSkipped = await controller.processIncomingSmsEvent(
          message: RawDeviceSmsMessage(
            deviceMessageId: 'b-denied',
            senderAddress: 'Telebirr',
            body:
                'You have paid ETB 50.00 to Cafe (251911223344) on 27/11/2026 12:00:00. Your transaction number is TB26331DENIED. Your current E-Money Account balance is ETB 950.00.',
            receivedAtUtc: nowUtc,
          ),
        );
        expect(incomingSkipped.skippedBecausePermission, isTrue);
        expect(controller.state.smsDrafts, isEmpty);
        expect(fakeService.dailyScanScheduled, isTrue);

        // READ_SMS daily/manual scan continues working even while RECEIVE_SMS is denied.
        final manualRes = await controller.scanSmsInboxNow();
        expect(manualRes.executed, isTrue);
        expect(manualRes.importedCount, 1);

        // Grant RECEIVE_SMS -> immediate processing succeeds and leaves dailyScan untouched.
        fakeService.receiveStatus = DeviceSmsPermissionStatus.granted;
        final scheduleBefore = fakeService.scheduleDailyScanCalls;
        final headlessBroadcastOk =
            await AppStateManager.runHeadlessIncomingSmsProcess(
          databaseBuilder: () => db,
          smsInboxService: fakeService,
          nowUtcProvider: () => nowUtc,
          incomingMessage: RawDeviceSmsMessage(
            deviceMessageId: 'b-headless-1',
            senderAddress: 'BOA',
            body:
                'Your account 1****4321 was credited with ETB 700.00. Available Balance: ETB 12,700.00. https://cs.bankofabyssinia.com/slip/?trx=FT26331HEADLESS_IMM',
            receivedAtUtc: nowUtc.add(const Duration(minutes: 1)),
          ),
        );
        expect(headlessBroadcastOk, isTrue);
        expect(fakeService.scheduleDailyScanCalls, scheduleBefore);

        // Revoke READ_SMS later while RECEIVE_SMS stays granted -> daily scan is cancelled, but immediate incoming broadcast STILL works!
        fakeService.status = DeviceSmsPermissionStatus.denied;
        await controller.refreshSmsInboxStatus();
        expect(fakeService.dailyScanScheduled, isFalse);

        final immAfterReadRevoke = await controller.processIncomingSmsEvent(
          message: RawDeviceSmsMessage(
            deviceMessageId: 'b-after-read-revoke',
            senderAddress: 'CBE',
            body:
                'Your account 1****5678 was debited with ETB 90.00. Current balance is ETB 19,790.00. https://apps.cbe.com.et:100/?id=FT26331IMM_ONLY',
            receivedAtUtc: nowUtc.add(const Duration(minutes: 2)),
          ),
        );
        expect(immAfterReadRevoke.executed, isTrue);
        expect(immAfterReadRevoke.importedCount, 1);

        // Revoke RECEIVE_SMS later -> stops immediately & silently without error or retry loop.
        fakeService.receiveStatus = DeviceSmsPermissionStatus.denied;
        final afterReceiveRevoke = await controller.processIncomingSmsEvent(
          message: RawDeviceSmsMessage(
            deviceMessageId: 'b-after-rec-revoke',
            senderAddress: 'CBE',
            body:
                'Your account 1****5678 was debited with ETB 45.00. Current balance is ETB 19,745.00. https://apps.cbe.com.et:100/?id=FT26331SHOULD_SKIP',
            receivedAtUtc: nowUtc.add(const Duration(minutes: 3)),
          ),
        );
        expect(afterReceiveRevoke.skippedBecausePermission, isTrue);
        expect(afterReceiveRevoke.errorMessage, isNull);
        expect(
          await AppStateManager.runHeadlessIncomingSmsProcess(
            databaseBuilder: () => db,
            smsInboxService: fakeService,
            nowUtcProvider: () => nowUtc,
            incomingMessage: RawDeviceSmsMessage(
              deviceMessageId: 'b-hl-revoked',
              senderAddress: 'CBE',
              body:
                  'Your account 1****5678 was debited with ETB 45.00. Current balance is ETB 19,745.00. https://apps.cbe.com.et:100/?id=FT26331SHOULD_SKIP',
              receivedAtUtc: nowUtc.add(const Duration(minutes: 3)),
            ),
          ),
          isTrue,
        );

        // If permanently denied, requestReceiveSmsPermission never prompts again.
        fakeService.receiveStatus = DeviceSmsPermissionStatus.permanentlyDenied;
        final reqAfterPermDeny = await controller.requestReceiveSmsPermission();
        expect(reqAfterPermDeny, DeviceSmsPermissionStatus.permanentlyDenied);
        expect(fakeService.requestReceivePermissionCalls, 0);
      },
    );

    test(
      '9. Android manifest, BroadcastReceiver, one-time WorkManager, ProGuard, and permission-safety structural contract',
      () {
        final manifestFile = File('android/app/src/main/AndroidManifest.xml');
        final receiverFile = File(
          'android/app/src/main/kotlin/com/example/personalmanagement/SmsReceivedBroadcastReceiver.kt',
        );
        final immediateWorkerFile = File(
          'android/app/src/main/kotlin/com/example/personalmanagement/SmsImmediateScanWorker.kt',
        );
        final bridgeFile = File(
          'android/app/src/main/kotlin/com/example/personalmanagement/SmsInboxBridge.kt',
        );
        final proguardFile = File('android/app/proguard-rules.pro');

        expect(manifestFile.existsSync(), isTrue);
        expect(receiverFile.existsSync(), isTrue);
        expect(immediateWorkerFile.existsSync(), isTrue);
        expect(bridgeFile.existsSync(), isTrue);
        expect(proguardFile.existsSync(), isTrue);

        final manifest = manifestFile.readAsStringSync();
        expect(manifest, contains('android.permission.READ_SMS'));
        expect(manifest, contains('android.permission.RECEIVE_SMS'));
        expect(manifest, contains('.SmsReceivedBroadcastReceiver'));
        expect(manifest, contains('android.permission.BROADCAST_SMS'));
        expect(manifest, contains('android.provider.Telephony.SMS_RECEIVED'));
        expect(manifest, isNot(contains('BIND_NOTIFICATION_LISTENER_SERVICE')));
        expect(manifest, isNot(contains('android.permission.SEND_SMS')));
        expect(manifest, isNot(contains('android.permission.WRITE_SMS')));

        final receiverSrc = receiverFile.readAsStringSync();
        expect(receiverSrc, contains('BroadcastReceiver'));
        expect(receiverSrc, contains('SMS_RECEIVED_ACTION'));
        expect(receiverSrc, contains('enqueueImmediateSmsProcessing'));
        expect(receiverSrc, isNot(contains('scheduleDailyScan')));
        expect(receiverSrc, isNot(contains('AppDatabase')));

        final workerSrc = immediateWorkerFile.readAsStringSync();
        expect(workerSrc, contains('Worker('));
        expect(workerSrc, contains('Result.retry()'));
        expect(workerSrc, contains('MAX_IMMEDIATE_RETRY_ATTEMPTS'));
        expect(workerSrc, contains('tryAcquireScanLock()'));
        expect(workerSrc, contains('smsBackgroundImmediateProcessMain'));
        expect(workerSrc, isNot(contains('scheduleDailyScan')));

        final bridgeSrc = bridgeFile.readAsStringSync();
        expect(
          bridgeSrc,
          contains('OneTimeWorkRequestBuilder<SmsImmediateScanWorker>'),
        );
        expect(bridgeSrc, contains('ExistingWorkPolicy.APPEND_OR_REPLACE'));
        expect(bridgeSrc, contains('UNIQUE_IMMEDIATE_WORK_NAME'));

        final proguard = proguardFile.readAsStringSync();
        expect(proguard, contains('SmsReceivedBroadcastReceiver'));
        expect(proguard, contains('SmsImmediateScanWorker'));
      },
    );

    test(
      '10. Multiple incoming SMS arriving concurrently or during an active inbox scan are serialized without drops or duplicate drafts',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        final repo = DriftFinanceRepository(db);
        final nowUtc = DateTime.utc(2026, 11, 27, 14, 0, 0);

        final readGate = Completer<void>();
        final fakeService = _FakeSmsInboxService(
          status: DeviceSmsPermissionStatus.granted,
          receiveStatus: DeviceSmsPermissionStatus.granted,
          inboxMessages: <RawDeviceSmsMessage>[
            RawDeviceSmsMessage(
              deviceMessageId: 'inbox-existing',
              senderAddress: 'CBE',
              body:
                  'Your account 1****5678 was debited with ETB 50.00. Current balance is ETB 19,950.00. https://apps.cbe.com.et:100/?id=FT26331BURST0',
              receivedAtUtc: nowUtc.subtract(const Duration(minutes: 10)),
            ),
          ],
        )..readGate = readGate;

        final controller = FinanceController(
          repository: repo,
          smsInboxService: fakeService,
          nowUtcProvider: () => nowUtc,
        );
        addTearDown(() async {
          if (!readGate.isCompleted) {
            readGate.complete();
          }
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

        // Start a manual inbox scan that pauses on readGate, then fire 3 close incoming SMS bursts.
        final activeInboxScan = controller.scanSmsInboxNow();
        await Future<void>.delayed(Duration.zero);

        final burst1 = controller.processIncomingSmsEvent(
          message: RawDeviceSmsMessage(
            deviceMessageId: 'burst-1',
            senderAddress: 'CBE',
            body:
                'Your account 1****5678 was debited with ETB 110.00. Current balance is ETB 19,840.00. https://apps.cbe.com.et:100/?id=FT26331BURST1',
            receivedAtUtc: nowUtc,
          ),
        );
        final burst2 = controller.processIncomingSmsEvent(
          message: RawDeviceSmsMessage(
            deviceMessageId: 'burst-2',
            senderAddress: 'Telebirr',
            body:
                'You have paid ETB 75.00 to Store (251911223344) on 27/11/2026 17:00:00. Your transaction number is TB26331BURST2. Your current E-Money Account balance is ETB 925.00.',
            receivedAtUtc: nowUtc,
          ),
        );
        final burst3 = controller.processIncomingSmsEvent(
          message: RawDeviceSmsMessage(
            deviceMessageId: 'burst-3',
            senderAddress: 'BOA',
            body:
                'Your account 1****4321 was credited with ETB 600.00. Available Balance: ETB 13,000.00. https://cs.bankofabyssinia.com/slip/?trx=FT26331BURST3',
            receivedAtUtc: nowUtc.add(const Duration(seconds: 1)),
          ),
        );

        readGate.complete();
        final results = await Future.wait<SmsInboxScanResult>([
          activeInboxScan,
          burst1,
          burst2,
          burst3,
        ]);

        for (final res in results) {
          expect(res.executed, isTrue);
          expect(res.errorMessage, isNull);
        }
        expect(controller.state.smsDrafts.length, 4);
      },
    );
  });
}
