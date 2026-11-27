import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/interfaces/platform_service_interfaces.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/database_persistence_coordinator.dart';
import 'package:personal_management_app/data/repositories/daily_rhythm_repository.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';
import 'package:personal_management_app/domain/daily_rhythm/daily_rhythm_contracts.dart';
import 'package:personal_management_app/domain/daily_rhythm/daily_rhythm_engine.dart';
import 'package:personal_management_app/domain/daily_rhythm/daily_rhythm_models.dart';
import 'package:personal_management_app/services/backup/encryption_backup_service.dart';

import 'support/sqlite_test_helper.dart';

DailyRhythmDayEntity _qualifyingDay(
  String dateIso, {
  String financeStatus = DailyRhythmFinanceCloseStatuses.closedWithTransactions,
}) {
  return DailyRhythmDayEntity(
    dateIso: dateIso,
    bibleStudyDone: true,
    bibleStudyCompletedAt: '${dateIso}T06:00:00.000Z',
    prayerDone: true,
    prayerCompletedAt: '${dateIso}T06:25:00.000Z',
    taskReviewConfirmed: true,
    taskReviewedAt: '${dateIso}T18:15:00.000Z',
    taskReviewEvidence: const DailyRhythmTaskReviewEvidence(
      overdueCount: 0,
      todayCount: 3,
      plannedCount: 3,
      completedTodayCount: 2,
    ),
    financeCloseStatus: financeStatus,
    financeClosedAt: '${dateIso}T19:05:00.000Z',
    updatedAt: '${dateIso}T19:05:00.000Z',
  );
}

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage B — Flutter Daily Rhythm Persistence & Backup/Restore', () {
    test(
      '1. DriftDailyRhythmRepository enforces 1 record per dateIso, validates fields, lists chronologically, and deletes cleanly',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final IDailyRhythmRepository repo = DriftDailyRhythmRepository(db);
        expect(await repo.listDays(), isEmpty);
        expect(await repo.getByDate('2026-11-22'), isNull);

        await repo.upsertDay(
          const DailyRhythmDayEntity(
            dateIso: '2026-11-22',
            bibleStudyDone: true,
            bibleStudyCompletedAt: '2026-11-22T06:00:00.000Z',
            updatedAt: '2026-11-22T06:00:00.000Z',
          ),
        );
        await repo.upsertDay(
          _qualifyingDay(
            '2026-11-20',
            financeStatus: DailyRhythmFinanceCloseStatuses.closedNoTransactions,
          ),
        );

        // Upsert on same dateIso updates existing row rather than inserting duplicate
        await repo.upsertDay(_qualifyingDay('2026-11-22'));

        final rows = await repo.listDays();
        expect(
          rows.map((r) => r.dateIso).toList(),
          ['2026-11-20', '2026-11-22'],
        );
        final nov22 = await repo.getByDate('2026-11-22');
        expect(nov22?.qualifies, isTrue);
        expect(nov22?.taskReviewEvidence?.plannedCount, 3);

        final rangeRows = await repo.listDays(
          fromDateIso: '2026-11-21',
          toDateIso: '2026-11-22',
        );
        expect(rangeRows.map((r) => r.dateIso).toList(), ['2026-11-22']);

        await expectLater(
          () => repo.upsertDay(
            const DailyRhythmDayEntity(dateIso: '2026-02-30'),
          ),
          throwsArgumentError,
        );
        await expectLater(
          () => repo.upsertDay(
            const DailyRhythmDayEntity(
              dateIso: '2026-11-21',
              financeCloseStatus: 'invalid_status',
            ),
          ),
          throwsArgumentError,
        );

        await repo.deleteByDate('2026-11-20');
        expect((await repo.listDays()).map((r) => r.dateIso), ['2026-11-22']);
      },
    );

    test(
      '2. Full v12 snapshot + .daywell encrypted backup preserves every canonical DailyRhythmDay field and streak/freeze state losslessly',
      () async {
        final sourceDb = AppDatabase(NativeDatabase.memory());
        await sourceDb.ensureInitialized();
        addTearDown(sourceDb.close);

        final sourceRepo = DriftDailyRhythmRepository(sourceDb);
        for (var d = 1; d <= 15; d++) {
          final dd = d.toString().padLeft(2, '0');
          await sourceRepo.upsertDay(
            _qualifyingDay(
              '2026-11-$dd',
              financeStatus: d.isEven
                  ? DailyRhythmFinanceCloseStatuses.closedNoTransactions
                  : DailyRhythmFinanceCloseStatuses.closedWithTransactions,
            ),
          );
        }
        // 2026-11-16 missed (protected by freeze), 2026-11-17 qualifies, 2026-11-18 partial/reconfirm
        await sourceRepo.upsertDay(_qualifyingDay('2026-11-17'));
        await sourceRepo.upsertDay(
          const DailyRhythmDayEntity(
            dateIso: '2026-11-18',
            bibleStudyDone: true,
            bibleStudyCompletedAt: '2026-11-18T06:00:00.000Z',
            prayerDone: true,
            prayerCompletedAt: '2026-11-18T06:20:00.000Z',
            taskReviewConfirmed: true,
            taskReviewedAt: '2026-11-18T17:00:00.000Z',
            taskReviewEvidence: DailyRhythmTaskReviewEvidence(
              overdueCount: 1,
              todayCount: 4,
              plannedCount: 2,
              completedTodayCount: 1,
            ),
            financeCloseStatus:
                DailyRhythmFinanceCloseStatuses.needsReconfirmation,
            updatedAt: '2026-11-18T18:00:00.000Z',
          ),
        );

        final beforeDays = await sourceRepo.listDays();
        final beforeSummary = DailyRhythmEngine.evaluateTimeline(
          beforeDays,
          todayIso: '2026-11-18',
        );
        expect(beforeSummary.totalQualifyingDays, 16);
        expect(beforeSummary.freezesUsedTotal, 1);
        expect(beforeSummary.availableFreezes, 0);
        expect(beforeSummary.currentStreak, 16);

        final coordinator = DatabasePersistenceCoordinator(sourceDb);
        final exported = await coordinator.exportSnapshot();
        expect(exported['schemaVersion'], 5);
        expect(exported['snapshotFormatVersion'], 2);
        expect(exported['databaseSchemaVersion'], 13);
        expect((exported['dailyRhythmDays'] as List).length, 17);

        final backupService = EncryptionBackupService();
        final envelope = await backupService.encryptDatabasePayload(
          rawDatabaseJson: jsonEncode(exported),
          passphrase: 'StageB#DailyRhythm2026',
          schemaVersion: exported['schemaVersion'] as int,
        );
        final decryptedMap = jsonDecode(
          await backupService.decryptDatabasePayload(
            encryptedEnvelopeJson: envelope,
            passphrase: 'StageB#DailyRhythm2026',
          ),
        ) as Map<String, dynamic>;

        final targetDb = AppDatabase(NativeDatabase.memory());
        await targetDb.ensureInitialized();
        addTearDown(targetDb.close);

        final report = await DatabasePersistenceCoordinator(targetDb)
            .importSnapshotDetailed(decryptedMap);
        expect(report.diagnostics, isEmpty);
        expect(report.restoredRecordCounts['dailyRhythmDays'], 17);

        final targetRepo = DriftDailyRhythmRepository(targetDb);
        final restoredDays = await targetRepo.listDays();
        expect(restoredDays, equals(beforeDays));
        final afterSummary = DailyRhythmEngine.evaluateTimeline(
          restoredDays,
          todayIso: '2026-11-18',
        );
        expect(afterSummary.currentStreak, beforeSummary.currentStreak);
        expect(afterSummary.bestStreak, beforeSummary.bestStreak);
        expect(
          afterSummary.totalQualifyingDays,
          beforeSummary.totalQualifyingDays,
        );
        expect(afterSummary.availableFreezes, beforeSummary.availableFreezes);
        expect(afterSummary.freezesUsedTotal, beforeSummary.freezesUsedTotal);
      },
    );

    test(
      '3. Backward compatibility: v4-v11 snapshots lacking dailyRhythmDays restore safely with zero fabricated historical check-ins',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final legacyPayloads = <Map<String, dynamic>>[
          {
            'schemaVersion': 4,
            'accounts': const [],
            'transactions': const [],
          },
          {
            'schemaVersion': 5,
            'snapshotFormatVersion': 2,
            'databaseSchemaVersion': 10,
            'accounts': const [],
            'transactions': const [],
          },
          {
            'schemaVersion': 5,
            'snapshotFormatVersion': 2,
            'databaseSchemaVersion': 11,
            'accounts': const [],
            'transactions': const [],
          },
        ];

        final coordinator = DatabasePersistenceCoordinator(db);
        for (final snap in legacyPayloads) {
          final report = await coordinator.importSnapshotDetailed(snap);
          expect(report.restoredRecordCounts['dailyRhythmDays'], 0);
          expect(await DriftDailyRhythmRepository(db).listDays(), isEmpty);
        }
      },
    );

    test(
      '4. Fail-closed validation, merge/replace atomicity, and unsupported future v13 rejection protect existing Daily Rhythm data',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final repo = DriftDailyRhythmRepository(db);
        await repo.upsertDay(_qualifyingDay('2026-11-20'));
        final coordinator = DatabasePersistenceCoordinator(db);

        // Duplicate dateIso, bad date, bad financeCloseStatus, future v13 fail closed
        final invalidSnapshots =
            <({Map<String, dynamic> snap, BackupFailureKind kind})>[
          (
            snap: {
              'schemaVersion': 5,
              'snapshotFormatVersion': 2,
              'databaseSchemaVersion': 12,
              'accounts': const [],
              'transactions': const [],
              'dailyRhythmDays': [
                {'dateIso': '2026-11-21'},
                {'dateIso': '2026-11-21'},
              ],
            },
            kind: BackupFailureKind.invalidPayload,
          ),
          (
            snap: {
              'schemaVersion': 5,
              'snapshotFormatVersion': 2,
              'databaseSchemaVersion': 12,
              'accounts': const [],
              'transactions': const [],
              'dailyRhythmDays': [
                {'dateIso': '2026-02-30'},
              ],
            },
            kind: BackupFailureKind.invalidPayload,
          ),
          (
            snap: {
              'schemaVersion': 5,
              'snapshotFormatVersion': 2,
              'databaseSchemaVersion': 12,
              'accounts': const [],
              'transactions': const [],
              'dailyRhythmDays': [
                {'dateIso': '2026-11-21', 'financeCloseStatus': 'bad_status'},
              ],
            },
            kind: BackupFailureKind.invalidPayload,
          ),
          (
            snap: {
              'schemaVersion': 5,
              'snapshotFormatVersion': 2,
              'databaseSchemaVersion': 14,
              'accounts': const [],
              'transactions': const [],
            },
            kind: BackupFailureKind.unsupportedFutureSchema,
          ),
        ];

        for (final tc in invalidSnapshots) {
          await expectLater(
            () => coordinator.importSnapshotDetailed(tc.snap),
            throwsA(
              isA<BackupValidationException>().having(
                (e) => e.kind,
                'kind',
                tc.kind,
              ),
            ),
          );
          expect((await repo.listDays()).map((d) => d.dateIso), ['2026-11-20']);
        }

        // Merge import preserves non-overlapping 2026-11-20 and upserts 2026-11-21
        await coordinator.importSnapshotDetailed(
          {
            'schemaVersion': 5,
            'snapshotFormatVersion': 2,
            'databaseSchemaVersion': 12,
            'accounts': const [],
            'transactions': const [],
            'dailyRhythmDays': [
              _qualifyingDay('2026-11-21').toJson(),
            ],
          },
          clearExisting: false,
        );
        expect(
          (await repo.listDays()).map((d) => d.dateIso).toList(),
          ['2026-11-20', '2026-11-21'],
        );
      },
    );

    test(
      '5. Finance-only export/import excludes dailyRhythmDays and historical Finance corrections keep persisted Daily Rhythm & spent freezes untouched',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final finRepo = DriftFinanceRepository(db);
        await finRepo.completeFinanceSetup([
          AccountModel(
            id: 'acc-cash',
            name: 'Cash',
            type: AccountType.asset,
            subType: AccountSubType.cash,
            openingBalanceCents: 100000,
          ),
        ]);
        final expenseCat = (await finRepo.getCategories())
            .firstWhere((c) => c.type == 'expense');
        await finRepo.recordDirectExpense(
          accountId: 'acc-cash',
          categoryId: expenseCat.id,
          amountCents: 5000,
          date: CalendarDate(year: 2026, month: 11, day: 5),
          description: 'Lunch',
        );

        final rhythmRepo = DriftDailyRhythmRepository(db);
        for (var d = 1; d <= 15; d++) {
          await rhythmRepo.upsertDay(
            _qualifyingDay('2026-11-${d.toString().padLeft(2, '0')}'),
          );
        }
        // 2026-11-16 missed (protected by earned freeze), 2026-11-17 qualifies
        await rhythmRepo.upsertDay(_qualifyingDay('2026-11-17'));

        final coordinator = DatabasePersistenceCoordinator(db);
        final finExport = await coordinator.exportFinanceOnlySnapshot();
        expect(finExport['financeOnly'], isTrue);
        expect(finExport['databaseSchemaVersion'], 13);
        expect(finExport.containsKey('dailyRhythmDays'), isFalse);

        // Finance-only import must reject payloads carrying dailyRhythmDays
        final contaminated = Map<String, dynamic>.from(finExport)
          ..['dailyRhythmDays'] = const [];
        await expectLater(
          () => coordinator.importFinanceOnlySnapshot(contaminated),
          throwsA(
            isA<BackupValidationException>().having(
              (e) => e.kind,
              'kind',
              BackupFailureKind.invalidPayload,
            ),
          ),
        );

        // Clean Finance-only import + historical voiding correction leaves Daily Rhythm & spent freeze intact
        await coordinator.importFinanceOnlySnapshot(finExport);
        final entries = await finRepo.getJournalEntries();
        final lunch = entries.firstWhere((e) => e.description == 'Lunch');
        await finRepo.voidJournalEntry(
          entryId: lunch.id,
          voidReason: 'Historical accounting fix',
        );

        final daysAfter = await rhythmRepo.listDays();
        expect(daysAfter.length, 16);
        final summaryAfter = DailyRhythmEngine.evaluateTimeline(
          daysAfter,
          todayIso: '2026-11-17',
        );
        expect(summaryAfter.totalQualifyingDays, 16);
        expect(summaryAfter.freezesUsedTotal, 1);
        expect(summaryAfter.availableFreezes, 0);
        expect(summaryAfter.currentStreak, 16);
      },
    );
  });
}
