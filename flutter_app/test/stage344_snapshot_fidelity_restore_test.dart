import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_management_app/core/interfaces/platform_service_interfaces.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/app_settings_policy.dart';
import 'package:personal_management_app/data/database/database_persistence_coordinator.dart';
import 'package:personal_management_app/data/database/raw_database_recovery_exporter.dart';
import 'package:personal_management_app/data/database/v6_ledger_migrator.dart';
import 'package:personal_management_app/data/database/v7_ledger_hardener.dart';
import 'package:personal_management_app/data/repositories/finance_repository.dart';
import 'package:personal_management_app/services/backup/encryption_backup_service.dart';
import 'package:personal_management_app/ui/app_state.dart';

import 'support/sqlite_test_helper.dart';

class _NoOpNotificationService implements INotificationService {
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
  }) async {}

  @override
  Future<void> cancelReminder(String id) async {}

  @override
  Future<void> cancelAllReminders() async {}
}

class _ThrowingNotificationService implements INotificationService {
  @override
  Future<void> initialize() async {
    throw StateError('Simulated missing OS notification plugin binding.');
  }

  @override
  Future<bool> requestPermissions() async => false;

  @override
  Future<void> scheduleReminder({
    required String id,
    required String title,
    required String body,
    required DateTime scheduledDateUtc,
    String? payload,
  }) async {
    throw StateError('Simulated schedule failure.');
  }

  @override
  Future<void> cancelReminder(String id) async {}

  @override
  Future<void> cancelAllReminders() async {}
}

class _ThrowingCleanupRecoveryExporter extends RawDatabaseRecoveryExporter {
  _ThrowingCleanupRecoveryExporter({
    required super.documentsDirProvider,
    required super.supportDirProvider,
  });

  @override
  Future<void> deleteQuarantine(QuarantineResult quarantine) async {
    throw const FileSystemException('Simulated quarantine cleanup failure');
  }

  @override
  Future<void> clearFailureDiagnostic() async {
    throw const FileSystemException('Simulated diagnostic cleanup failure');
  }
}

Map<String, dynamic> _baseV7Snapshot({
  int schemaVersion = 7,
  List<Map<String, dynamic>>? categories,
  List<Map<String, dynamic>>? accounts,
  List<Map<String, dynamic>>? parties,
  List<Map<String, dynamic>>? goals,
  List<Map<String, dynamic>>? projects,
  List<Map<String, dynamic>>? milestones,
  List<Map<String, dynamic>>? tasks,
  List<Map<String, dynamic>>? notes,
  List<Map<String, dynamic>>? calendarEvents,
  List<Map<String, dynamic>>? commitments,
  List<Map<String, dynamic>>? transactions,
  List<Map<String, dynamic>>? journalEntries,
  List<Map<String, dynamic>>? postings,
  List<Map<String, dynamic>>? debts,
  List<Map<String, dynamic>>? settlementAllocations,
  List<Map<String, dynamic>>? commitmentSettlements,
  List<Map<String, dynamic>>? savingsGoals,
  List<Map<String, dynamic>>? budgets,
  List<Map<String, dynamic>>? recurringRules,
  List<Map<String, dynamic>>? reminders,
  bool includeReminders = true,
  List<Map<String, dynamic>>? appSettings,
  bool includeAppSettings = true,
  Object? openingBalanceCents = 100000,
  Object? isFinanceSetupCompleted = true,
  Object? ledgerMigrationReportV7,
  bool includeReport = false,
}) {
  return <String, dynamic>{
    'schemaVersion': schemaVersion,
    'isFinanceSetupCompleted': isFinanceSetupCompleted,
    'openingBalanceCents': openingBalanceCents,
    if (includeReport) 'ledgerMigrationReportV7': ledgerMigrationReportV7,
    'accounts': accounts ??
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'acc-cash',
            'name': 'Wallet Cash',
            'type': 'asset',
            'subType': 'cash',
            'isSystem': false,
            'currencyCode': 'ETB',
            'isArchived': false,
            'openingBalanceCents': 100000,
            'openingBalanceDate': '2026-11-01',
            'createdAt': '2026-11-01T00:00:00.000Z',
          },
        ],
    'categories': categories ??
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'cat-other-exp',
            'name': 'Other Expense',
            'type': 'expense',
            'colorHex': '#64748B',
            'isDefault': true,
            'isArchived': false,
          },
        ],
    'parties': parties ?? <Map<String, dynamic>>[],
    'goals': goals ?? <Map<String, dynamic>>[],
    'projects': projects ?? <Map<String, dynamic>>[],
    'milestones': milestones ?? <Map<String, dynamic>>[],
    'tasks': tasks ?? <Map<String, dynamic>>[],
    'notes': notes ?? <Map<String, dynamic>>[],
    'inboxItems': <Map<String, dynamic>>[],
    'calendarEvents': calendarEvents ?? <Map<String, dynamic>>[],
    'commitments': commitments ?? <Map<String, dynamic>>[],
    'transactions': transactions ?? <Map<String, dynamic>>[],
    'journalEntries': journalEntries ??
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'je-open-cash',
            'entryType': 'adjustment',
            'description': 'Opening Balance',
            'occurrenceDate': '2026-11-01',
            'isVoided': false,
            'legacySourceTxId': 'open:acc-cash',
            'createdAt': '2026-11-01T00:00:00.000Z',
          },
        ],
    'postings': postings ??
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'p-open-1',
            'entryId': 'je-open-cash',
            'accountId': 'acc-cash',
            'amountCents': 100000,
            'direction': 'debit',
            'accountMovementDate': '2026-11-01',
          },
          <String, dynamic>{
            'id': 'p-open-2',
            'entryId': 'je-open-cash',
            'accountId': 'acc-sys-equity',
            'amountCents': 100000,
            'direction': 'credit',
            'accountMovementDate': '2026-11-01',
          },
        ],
    'debts': debts ?? <Map<String, dynamic>>[],
    'settlementAllocations': settlementAllocations ?? <Map<String, dynamic>>[],
    'commitmentSettlements': commitmentSettlements ?? <Map<String, dynamic>>[],
    'savingsGoals': savingsGoals ?? <Map<String, dynamic>>[],
    'budgets': budgets ?? <Map<String, dynamic>>[],
    'recurringRules': recurringRules ?? <Map<String, dynamic>>[],
    if (includeReminders) 'reminders': reminders ?? <Map<String, dynamic>>[],
    if (includeAppSettings)
      'appSettings': appSettings ?? <Map<String, dynamic>>[],
  };
}

Matcher _throwsValidationKind(BackupFailureKind kind) {
  return throwsA(
    isA<BackupValidationException>().having((e) => e.kind, 'kind', kind),
  );
}

void main() {
  configureSqliteForHostTests();

  group('Stage 3.4.4 — 1. Reminders Round-Trip & Soft-Link Policy', () {
    test(
      'Export/import preserves valid task, commitment, calendar_event, and '
      'custom reminders with exact UTC triggerTimeUtc, isActive, and createdAt',
      () async {
        final db1 = AppDatabase(NativeDatabase.memory());
        await db1.ensureInitialized();
        addTearDown(db1.close);

        final db2 = AppDatabase(NativeDatabase.memory());
        await db2.ensureInitialized();
        addTearDown(db2.close);

        final snapshot = _baseV7Snapshot(
          tasks: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'task-r1',
              'title': 'Pay rent',
              'createdAt': '2026-11-01T08:00:00.000Z',
            },
          ],
          commitments: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'com-r1',
              'title': 'Electric bill',
              'amountCents': 50000,
              'dueDate': '2026-11-25',
            },
          ],
          calendarEvents: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'evt-r1',
              'title': 'Dentist',
              'dateIso': '2026-11-26',
            },
          ],
          reminders: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'rem-task',
              'targetId': 'task-r1',
              'targetType': 'task',
              'triggerTimeUtc': '2026-11-24T06:30:00.000Z',
              'isActive': true,
              'createdAt': '2026-11-01T09:00:00.000Z',
            },
            <String, dynamic>{
              'id': 'rem-com',
              'targetId': 'com-r1',
              'targetType': 'commitment',
              'triggerTimeUtc': '2026-11-25T07:00:00.000Z',
              'isActive': false,
              'createdAt': '2026-11-02T10:00:00.000Z',
            },
            <String, dynamic>{
              'id': 'rem-evt',
              'targetId': 'evt-r1',
              'targetType': 'calendar_event',
              'triggerTimeUtc': '2026-11-26T05:45:00.000Z',
              'isActive': true,
              'createdAt': '2026-11-03T11:00:00.000Z',
            },
            <String, dynamic>{
              'id': 'rem-custom',
              'targetType': 'custom',
              'title': 'Breathe',
              'channelId': 'mindfulness',
              'triggerTimeUtc': '2026-11-27T18:00:00.000Z',
              'isActive': true,
              'createdAtUtc': '2026-11-04T12:00:00.000Z',
            },
          ],
        );

        final report1 =
            await DatabasePersistenceCoordinator(db1).importSnapshotDetailed(
          snapshot,
        );
        expect(report1.restoredRecordCounts['reminders'], 4);

        final exported =
            await DatabasePersistenceCoordinator(db1).exportSnapshot();
        expect((exported['reminders'] as List).length, 4);

        final report2 =
            await DatabasePersistenceCoordinator(db2).importSnapshotDetailed(
          exported,
        );
        expect(report2.warnings, isEmpty);

        final rows = await db2.select(db2.reminders).get();
        expect(rows.length, 4);
        final byId = {for (final r in rows) r.id: r};
        expect(
          byId['rem-task']!.triggerTimeUtc.toUtc().toIso8601String(),
          '2026-11-24T06:30:00.000Z',
        );
        expect(byId['rem-task']!.title, isNull);
        expect(byId['rem-task']!.channelId, isNull);
        expect(byId['rem-com']!.isActive, isFalse);
        expect(byId['rem-evt']!.targetType, 'calendar_event');
        expect(byId['rem-custom']!.targetId, 'rem-custom');
        expect(byId['rem-custom']!.title, 'Breathe');
        expect(byId['rem-custom']!.channelId, 'mindfulness');
        expect(
          byId['rem-custom']!.createdAt.toUtc().toIso8601String(),
          '2026-11-04T12:00:00.000Z',
        );
      },
    );

    test(
      'Dangling entity reminders warn-skip while custom/valid reminders '
      'persist; omitted reminders clears on replace; invalid reminder scalars '
      'fail closed',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final coordinator = DatabasePersistenceCoordinator(db);

        // 1. Dangling task/note reminders skipped with
        // ORPHANED_REMINDER_SKIPPED
        final danglingSnap = _baseV7Snapshot(
          reminders: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'rem-dangling-task',
              'targetId': 'missing-task-99',
              'targetType': 'task',
              'triggerTimeUtc': '2026-11-20T09:00:00.000Z',
              'createdAt': '2026-11-01T09:00:00.000Z',
            },
            <String, dynamic>{
              'id': 'rem-valid-custom',
              'targetId': 'custom-alert',
              'targetType': 'custom',
              'triggerTimeUtc': '2026-11-21T09:00:00.000Z',
              'createdAt': '2026-11-01T09:00:00.000Z',
            },
          ],
        );

        final report = await coordinator.importSnapshotDetailed(danglingSnap);
        expect(
          report.diagnostics.any((d) => d.code == 'ORPHANED_REMINDER_SKIPPED'),
          isTrue,
        );
        expect(
          report.warnings.any((w) => w.contains('ORPHANED_REMINDER_SKIPPED')),
          isTrue,
        );
        final persisted = await db.select(db.reminders).get();
        expect(
          persisted.map((r) => r.id).toList(),
          <String>['rem-valid-custom'],
        );

        // 2. Malformed reminder fails closed without clearing rem-valid-custom
        final badReminderSnap = _baseV7Snapshot(
          reminders: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'rem-bad-date',
              'targetId': 'x',
              'targetType': 'custom',
              'triggerTimeUtc': 'not-an-iso-timestamp',
              'createdAt': '2026-11-01T09:00:00.000Z',
            },
          ],
        );
        await expectLater(
          () => coordinator.importSnapshotDetailed(badReminderSnap),
          _throwsValidationKind(BackupFailureKind.invalidPayload),
        );
        expect(
          (await db.select(db.reminders).get()).map((r) => r.id).toList(),
          <String>['rem-valid-custom'],
        );

        // 3. Omitted reminders on replace clears reminders and emits info
        final legacyNoReminders = _baseV7Snapshot(includeReminders: false);
        final legacyReport =
            await coordinator.importSnapshotDetailed(legacyNoReminders);
        expect(
          legacyReport.diagnostics
              .any((d) => d.code == 'LEGACY_REMINDERS_OMITTED'),
          isTrue,
        );
        expect(await db.select(db.reminders).get(), isEmpty);
      },
    );
  });

  group(
    'Stage 3.4.4 — 2. AppSettings Fidelity, Exclusions & Stale Cleanup',
    () {
      test(
        'User settings round-trip cleanly; internal sentinels and secret or '
        'device prefixes are excluded on export & skipped with warning on '
        'import',
        () async {
          final db = AppDatabase(NativeDatabase.memory());
          await db.ensureInitialized();
          addTearDown(db.close);

          final now = DateTime.utc(2026, 11, 10, 12, 0);
          await db.into(db.appSettings).insertOnConflictUpdate(
                AppSettingsCompanion.insert(
                  key: 'secret_local_key',
                  value: 'do-not-export',
                  updatedAt: now,
                ),
              );
          await db.into(db.appSettings).insertOnConflictUpdate(
                AppSettingsCompanion.insert(
                  key: 'calendar_display_mode',
                  value: 'ethiopian',
                  updatedAt: now,
                ),
              );

          final coordinator = DatabasePersistenceCoordinator(db);
          final exportedBefore = await coordinator.exportSnapshot();
          final exportedKeys = (exportedBefore['appSettings'] as List)
              .cast<Map<String, dynamic>>()
              .map((e) => e['key'] as String)
              .toList();
          expect(exportedKeys, contains('calendar_display_mode'));
          expect(exportedKeys, isNot(contains('secret_local_key')));
          expect(exportedKeys, isNot(contains(AppDatabase.seedSentinelKey)));
          expect(
            exportedKeys,
            isNot(contains(V6LedgerMigrator.v6MigratedSentinelKey)),
          );
          expect(exportedKeys, isNot(contains(AppDatabase.openingBalanceKey)));

          // Import snapshot attempting to inject protected/secret keys
          final injectedSnap = _baseV7Snapshot(
            appSettings: <Map<String, dynamic>>[
              <String, dynamic>{
                'key': 'default_currency',
                'value': 'ETB',
              },
              <String, dynamic>{
                'key': 'calendar_preference',
                'value': 'dual',
              },
              <String, dynamic>{
                'key': 'secret_injected',
                'value': 'hacked',
              },
              <String, dynamic>{
                'key': 'token_sync',
                'value': 'tok-bad',
              },
              <String, dynamic>{
                'key': 'push_token',
                'value': 'fcm-bad',
              },
              <String, dynamic>{
                'key': 'initial_seed_completed',
                'value': 'false',
              },
              <String, dynamic>{
                'key': 'opening_balance_cents',
                'value': '9999999',
              },
            ],
          );

          final report = await coordinator.importSnapshotDetailed(injectedSnap);
          expect(
            report.diagnostics
                .where((d) => d.code == 'EXCLUDED_APP_SETTING_SKIPPED')
                .length,
            5,
          );

          final rows = await db.select(db.appSettings).get();
          final map = {for (final r in rows) r.key: r.value};
          // Old exportable setting replaced; new user settings saved;
          // protected sentinel preserved
          expect(map.containsKey('calendar_display_mode'), isFalse);
          expect(map['default_currency'], 'ETB');
          expect(map['calendar_preference'], 'dual');
          // Local device secret not deleted or overwritten
          expect(map['secret_local_key'], 'do-not-export');
          expect(map.containsKey('secret_injected'), isFalse);
          expect(map.containsKey('token_sync'), isFalse);
          expect(map.containsKey('push_token'), isFalse);
          expect(map[AppDatabase.seedSentinelKey], 'true');
          expect(map[AppDatabase.openingBalanceKey], '100000');
          expect(
            AppSettingsBackupPolicy.isSecretOrDeviceKey('transient_x'),
            isTrue,
          );
        },
      );

      test(
        'Omitted appSettings preserves user settings, omitted '
        'ledgerMigrationReportV7 clears stale v7 report, and malformed '
        'settings fail closed',
        () async {
          final db = AppDatabase(NativeDatabase.memory());
          await db.ensureInitialized();
          addTearDown(db.close);

          final now = DateTime.utc(2026, 11, 10, 12, 0);
          await db.into(db.appSettings).insertOnConflictUpdate(
                AppSettingsCompanion.insert(
                  key: 'calendar_preference',
                  value: 'ethiopian_only',
                  updatedAt: now,
                ),
              );
          await db.into(db.appSettings).insertOnConflictUpdate(
                AppSettingsCompanion.insert(
                  key: V7LedgerHardener.v7ReportKey,
                  value: '{"stale":true}',
                  updatedAt: now,
                ),
              );

          final coordinator = DatabasePersistenceCoordinator(db);

          // Malformed setting rejects pre-transaction
          await expectLater(
            () => coordinator.importSnapshotDetailed(
              _baseV7Snapshot(
                appSettings: <Map<String, dynamic>>[
                  <String, dynamic>{'key': 'k1', 'value': 42},
                ],
              ),
            ),
            _throwsValidationKind(BackupFailureKind.invalidPayload),
          );
          await expectLater(
            () => coordinator.importSnapshotDetailed(
              _baseV7Snapshot(openingBalanceCents: '100000'),
            ),
            _throwsValidationKind(BackupFailureKind.invalidPayload),
          );
          await expectLater(
            () => coordinator.importSnapshotDetailed(
              _baseV7Snapshot(isFinanceSetupCompleted: 'yes'),
            ),
            _throwsValidationKind(BackupFailureKind.invalidPayload),
          );

          // Omitted appSettings & omitted ledgerMigrationReportV7
          final report = await coordinator.importSnapshotDetailed(
            _baseV7Snapshot(
              includeAppSettings: false,
              includeReport: false,
            ),
          );
          expect(
            report.diagnostics
                .any((d) => d.code == 'LEGACY_APP_SETTINGS_OMITTED'),
            isTrue,
          );
          final rows = await db.select(db.appSettings).get();
          final map = {for (final r in rows) r.key: r.value};
          expect(map['calendar_preference'], 'ethiopian_only');
          expect(map.containsKey(V7LedgerHardener.v7ReportKey), isFalse);
        },
      );
    },
  );

  group(
    'Stage 3.4.4 — 3. Per-Table Duplicate-ID & Unique Index Enforcement',
    () {
      test(
        'Same-table duplicate PK or duplicate key rejects fail closed; '
        'cross-table ID reuse succeeds',
        () {
          // Cross-table ID reuse ('shared-id-1' across accounts, goals,
          // commitments, reminders)
          final crossTableOk = _baseV7Snapshot(
            accounts: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'shared-id-1',
                'name': 'Main Cash',
                'type': 'asset',
                'subType': 'cash',
                'currencyCode': 'ETB',
                'openingBalanceCents': 50000,
              },
            ],
            goals: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'shared-id-1',
                'title': 'Emergency Goal',
                'status': 'active',
              },
            ],
            commitments: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'shared-id-1',
                'title': 'Internet Bill',
                'amountCents': 12000,
                'dueDate': '2026-11-30',
              },
            ],
            reminders: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'shared-id-1',
                'targetId': 'shared-id-1',
                'targetType': 'commitment',
                'triggerTimeUtc': '2026-11-29T09:00:00.000Z',
                'createdAt': '2026-11-01T09:00:00.000Z',
              },
            ],
            journalEntries: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'je-shared-open',
                'entryType': 'adjustment',
                'description': 'Opening',
                'occurrenceDate': '2026-11-01',
                'legacySourceTxId': 'open:shared-id-1',
              },
            ],
            postings: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'p-1',
                'entryId': 'je-shared-open',
                'accountId': 'shared-id-1',
                'amountCents': 50000,
                'direction': 'debit',
                'accountMovementDate': '2026-11-01',
              },
              <String, dynamic>{
                'id': 'p-2',
                'entryId': 'je-shared-open',
                'accountId': 'acc-sys-equity',
                'amountCents': 50000,
                'direction': 'credit',
                'accountMovementDate': '2026-11-01',
              },
            ],
          );
          final prepared =
              DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
            crossTableOk,
          );
          expect(prepared.restoredRecordCounts['reminders'], 1);

          // Duplicate PK in tasks
          expect(
            () => DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
              _baseV7Snapshot(
                tasks: <Map<String, dynamic>>[
                  <String, dynamic>{'id': 't-dup', 'title': 'One'},
                  <String, dynamic>{'id': 't-dup', 'title': 'Two'},
                ],
              ),
            ),
            _throwsValidationKind(BackupFailureKind.invalidPayload),
          );

          // Duplicate key in appSettings
          expect(
            () => DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
              _baseV7Snapshot(
                appSettings: <Map<String, dynamic>>[
                  <String, dynamic>{'key': 'dup_key', 'value': '1'},
                  <String, dynamic>{'key': 'dup_key', 'value': '2'},
                ],
              ),
            ),
            _throwsValidationKind(BackupFailureKind.invalidPayload),
          );

          // Duplicate (monthIso, categoryId) in budgets
          expect(
            () => DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
              _baseV7Snapshot(
                budgets: <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 'b-1',
                    'categoryId': 'cat-other-exp',
                    'monthIso': '2026-11',
                    'limitCents': 50000,
                  },
                  <String, dynamic>{
                    'id': 'b-2',
                    'categoryId': 'cat-other-exp',
                    'monthIso': '2026-11',
                    'limitCents': 60000,
                  },
                ],
              ),
            ),
            _throwsValidationKind(BackupFailureKind.invalidPayload),
          );

          // Duplicate non-null legacySourceTxId in journalEntries
          expect(
            () => DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
              _baseV7Snapshot(
                journalEntries: <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 'je-1',
                    'entryType': 'standard',
                    'occurrenceDate': '2026-11-01',
                    'legacySourceTxId': 'tx-same',
                  },
                  <String, dynamic>{
                    'id': 'je-2',
                    'entryType': 'standard',
                    'occurrenceDate': '2026-11-02',
                    'legacySourceTxId': 'tx-same',
                  },
                ],
                postings: const <Map<String, dynamic>>[],
              ),
            ),
            _throwsValidationKind(BackupFailureKind.invalidPayload),
          );
        },
      );
    },
  );

  group(
    'Stage 3.4.4 — 4. Tier 1 Required vs Tier 2/3 Optional FK & Type Safety',
    () {
      test(
        'Broken Tier 1 FKs fail closed with zero synthetic category creation; '
        'unsafe scalar types fail pre-transaction',
        () async {
          final db = AppDatabase(NativeDatabase.memory());
          await db.ensureInitialized();
          addTearDown(db.close);

          await DriftFinanceRepository(db).completeFinanceSetup([
            AccountModel(
              id: 'acc-keep',
              name: 'Original Account',
              type: AccountType.asset,
              subType: AccountSubType.cash,
              openingBalanceCents: 250000,
              openingBalanceDate: '2026-11-01',
            ),
          ]);

          final coordinator = DatabasePersistenceCoordinator(db);

          final tier1Failures = <Map<String, dynamic>>[
            // Missing explicit transaction categoryId -> must NOT synthesize
            // category!
            _baseV7Snapshot(
              transactions: <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'tx-bad-cat',
                  'categoryId': 'cat-does-not-exist',
                  'amountCents': 1000,
                  'type': 'expense',
                  'transactionDate': '2026-11-10',
                },
              ],
            ),
            // Missing milestone projectId
            _baseV7Snapshot(
              milestones: <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'ms-bad',
                  'projectId': 'missing-proj',
                  'title': 'Orphan Milestone',
                },
              ],
            ),
            // Missing posting accountId
            _baseV7Snapshot(
              postings: <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'p-bad-acc',
                  'entryId': 'je-open-cash',
                  'accountId': 'missing-account',
                  'amountCents': 100000,
                  'direction': 'debit',
                  'accountMovementDate': '2026-11-01',
                },
              ],
            ),
            // Missing debt partyId
            _baseV7Snapshot(
              debts: <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'debt-bad',
                  'originEntryId': 'je-open-cash',
                  'partyId': 'missing-party',
                  'debtType': 'payable',
                  'principalCents': 1000,
                },
              ],
            ),
            // Missing settlementAllocation debtId
            _baseV7Snapshot(
              settlementAllocations: <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'sa-bad',
                  'settlementEntryId': 'je-open-cash',
                  'debtId': 'missing-debt',
                  'allocatedCents': 500,
                  'settlementDate': '2026-11-02',
                },
              ],
            ),
            // Missing budget categoryId
            _baseV7Snapshot(
              budgets: <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'b-bad',
                  'categoryId': 'missing-cat',
                  'monthIso': '2026-11',
                  'limitCents': 10000,
                },
              ],
            ),
            // Missing commitmentSettlement commitmentId
            _baseV7Snapshot(
              commitmentSettlements: <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'cs-bad',
                  'commitmentId': 'missing-commitment',
                  'entryId': 'je-open-cash',
                  'amountCents': 500,
                  'settledDate': '2026-11-02',
                },
              ],
            ),
            // Unsafe type mismatches rejected cleanly as invalidPayload
            _baseV7Snapshot(
              tasks: <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 't-bad-type',
                  'title': 'Bad duration',
                  'estimatedDurationMinutes': '30',
                },
              ],
            ),
            _baseV7Snapshot(
              notes: <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'n-bad-bool',
                  'title': 'Bad pin',
                  'isPinned': 'true',
                },
              ],
            ),
          ];

          for (final badSnap in tier1Failures) {
            await expectLater(
              () => coordinator.importSnapshotDetailed(badSnap),
              _throwsValidationKind(BackupFailureKind.invalidPayload),
            );
          }

          // Live DB preserved completely intact without any synthetic category
          final cats = await db.select(db.financialCategories).get();
          expect(cats.any((c) => c.id == 'cat-does-not-exist'), isFalse);
          final accs = await db.select(db.accountsTable).get();
          expect(accs.any((a) => a.id == 'acc-keep'), isTrue);
        },
      );

      test(
        'Broken Tier 2 nullable FKs, cycles, and Tier 3 soft links warn-clear '
        'to null cleanly and pass PRAGMA foreign_key_check',
        () async {
          final db = AppDatabase(NativeDatabase.memory());
          await db.ensureInitialized();
          addTearDown(db.close);

          final snap = _baseV7Snapshot(
            categories: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'cat-other-exp',
                'name': 'Other Expense',
                'type': 'expense',
                'colorHex': '#64748B',
                'isDefault': true,
              },
              <String, dynamic>{
                'id': 'cat-cyc-a',
                'name': 'Cycle A',
                'type': 'expense',
                'parentId': 'cat-cyc-b',
              },
              <String, dynamic>{
                'id': 'cat-cyc-b',
                'name': 'Cycle B',
                'type': 'expense',
                'parentId': 'cat-cyc-a',
              },
            ],
            projects: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'proj-1',
                'title': 'Project',
                'goalId': 'missing-goal',
              },
            ],
            tasks: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'task-1',
                'title': 'Task',
                'projectId': 'missing-project',
                'milestoneId': 'missing-milestone',
              },
            ],
            notes: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'note-1',
                'title': 'Note',
                'projectId': 'missing-project',
                'goalId': 'missing-goal',
              },
            ],
            transactions: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'tx-soft',
                'categoryId': 'cat-other-exp',
                'amountCents': 5000,
                'type': 'expense',
                'transactionDate': '2026-11-10',
                'accountId': 'missing-acc',
                'destinationAccountId': 'missing-dest',
                'correctedFromId': 'tx-soft',
              },
            ],
            commitments: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'com-soft',
                'title': 'Utility',
                'amountCents': 2000,
                'dueDate': '2026-11-28',
                'linkedAccountId': 'missing-acc',
                'categoryId': 'missing-cat',
                'linkedDebtId': 'missing-debt',
                'settlementEntryId': 'missing-entry',
                'recurringRuleId': 'missing-rule',
              },
            ],
          );

          final coordinator = DatabasePersistenceCoordinator(db);
          final report = await coordinator.importSnapshotDetailed(snap);
          final codes = report.diagnostics.map((d) => d.code).toSet();
          expect(
            codes,
            containsAll(<String>{
              'ORPHANED_CATEGORY_PARENT_CLEARED',
              'ORPHANED_PROJECT_GOAL_CLEARED',
              'ORPHANED_TASK_PROJECT_CLEARED',
              'ORPHANED_TASK_MILESTONE_CLEARED',
              'ORPHANED_NOTE_PROJECT_CLEARED',
              'ORPHANED_NOTE_GOAL_CLEARED',
              'ORPHANED_TRANSACTION_ACCOUNT_CLEARED',
              'ORPHANED_TRANSACTION_DESTINATION_CLEARED',
              'ORPHANED_TRANSACTION_CORRECTION_CLEARED',
              'ORPHANED_COMMITMENT_ACCOUNT_CLEARED',
              'ORPHANED_COMMITMENT_CATEGORY_CLEARED',
              'ORPHANED_COMMITMENT_DEBT_CLEARED',
              'ORPHANED_COMMITMENT_ENTRY_CLEARED',
              'ORPHANED_RECURRING_RULE_LINK_CLEARED',
            }),
          );
          expect(report.warnings, isNotEmpty);

          await DatabasePersistenceCoordinator.verifyRestoredDatabaseInvariants(
            db,
          );
          final t = (await db.select(db.tasks).get()).single;
          expect(t.projectId, isNull);
          expect(t.milestoneId, isNull);
        },
      );
    },
  );

  group(
    'Stage 3.4.4 — 5. Unified 4-Entrypoint Validation, Quarantine Rollback & '
    'Best-Effort Boundary',
    () {
      test(
        'All 4 entrypoints reject broken Tier 1 FK snapshots pre-quarantine '
        'and pre-clear, and propagate diagnostics on warn-clear',
        () async {
          final tempDir = Directory.systemTemp.createTempSync('dw_e4_');
          addTearDown(() {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          });
          final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
          final supportDir = Directory(p.join(tempDir.path, 'support'))
            ..createSync();
          final dbPath = p.join(docsDir.path, 'personal_management.sqlite');
          final dbFile = File(dbPath);
          final quarantineDir =
              Directory(p.join(docsDir.path, 'recovery_quarantine'));

          final manager = AppStateManager(
            databaseBuilder: () => AppDatabase(NativeDatabase(dbFile)),
            recoveryExporter: RawDatabaseRecoveryExporter(
              documentsDirProvider: () async => docsDir,
              supportDirProvider: () async => supportDir,
            ),
            notificationService: _NoOpNotificationService(),
          );
          await manager.initialize();
          await manager.financeController.addAccount(
            name: 'Pre-Restore Cash',
            type: AccountType.asset,
            subType: AccountSubType.cash,
            openingBalanceCents: 440000,
          );

          final brokenFkSnap = _baseV7Snapshot(
            postings: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'p-broken',
                'entryId': 'je-open-cash',
                'accountId': 'acc-missing',
                'amountCents': 100000,
                'direction': 'debit',
                'accountMovementDate': '2026-11-01',
              },
            ],
          );
          final backupService = EncryptionBackupService();
          final brokenEnvelope = await backupService.encryptDatabasePayload(
            rawDatabaseJson: jsonEncode(brokenFkSnap),
            passphrase: 'Pass#344',
            schemaVersion: 7,
          );

          // 1 & 2. Encrypted restore & recovery reject before quarantine
          final r1 = await manager.restoreEncryptedBackupInRecoveryDetailed(
            encryptedEnvelopeJson: brokenEnvelope,
            passphrase: 'Pass#344',
          );
          expect(r1.success, isFalse);
          expect(r1.failureKind, BackupFailureKind.invalidPayload);
          expect(quarantineDir.existsSync(), isFalse);
          expect(manager.liquidCashCents, 440000);

          final r2 = await manager.restoreFromEncryptedBackupDetailed(
            brokenEnvelope,
            'Pass#344',
          );
          expect(r2.success, isFalse);
          expect(r2.failureKind, BackupFailureKind.invalidPayload);
          expect(quarantineDir.existsSync(), isFalse);

          // 3. Canonical importDetailed rejects
          final r3 = await manager.importCanonicalSnapshotDetailed(
            brokenFkSnap,
          );
          expect(r3.success, isFalse);
          expect(r3.failureKind, BackupFailureKind.invalidPayload);
          expect(manager.liquidCashCents, 440000);

          // 4. Direct coordinator importSnapshotDetailed rejects
          await expectLater(
            () => DatabasePersistenceCoordinator(
              AppDatabase(NativeDatabase.memory()),
            ).importSnapshotDetailed(brokenFkSnap),
            _throwsValidationKind(BackupFailureKind.invalidPayload),
          );

          // Verify warn-clear diagnostics propagate through restore result
          final warnSnap = _baseV7Snapshot(
            tasks: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 't-warn',
                'title': 'Warn Task',
                'projectId': 'missing-proj',
              },
            ],
          );
          final warnEnvelope = await backupService.encryptDatabasePayload(
            rawDatabaseJson: jsonEncode(warnSnap),
            passphrase: 'Pass#344',
            schemaVersion: 7,
          );
          final okWarn = await manager.restoreFromEncryptedBackupDetailed(
            warnEnvelope,
            'Pass#344',
          );
          expect(okWarn.success, isTrue);
          expect(okWarn.warnings, isNotEmpty);
          expect(
            okWarn.diagnostics
                .any((d) => d.code == 'ORPHANED_TASK_PROJECT_CLEARED'),
            isTrue,
          );
          expect(quarantineDir.existsSync(), isFalse);

          await manager.disposeAsync();
        },
      );

      test(
        '8-Step Rollback on healthy session failure: preserves quarantine, '
        'restores .sqlite+-wal+-shm copy-back, and rehydrates original healthy '
        'DB',
        () async {
          final tempDir = Directory.systemTemp.createTempSync('dw_rb1_');
          addTearDown(() {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          });
          final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
          final supportDir = Directory(p.join(tempDir.path, 'support'))
            ..createSync();
          final dbPath = p.join(docsDir.path, 'personal_management.sqlite');
          final dbFile = File(dbPath);
          final quarantineDir =
              Directory(p.join(docsDir.path, 'recovery_quarantine'));

          final manager = AppStateManager(
            databaseBuilder: () => AppDatabase(NativeDatabase(dbFile)),
            recoveryExporter: RawDatabaseRecoveryExporter(
              documentsDirProvider: () async => docsDir,
              supportDirProvider: () async => supportDir,
            ),
            notificationService: _NoOpNotificationService(),
          );
          await manager.initialize();
          await manager.financeController.addAccount(
            name: 'Healthy Original Cash',
            type: AccountType.asset,
            subType: AccountSubType.cash,
            openingBalanceCents: 750000,
          );
          expect(manager.liquidCashCents, 750000);

          final targetSnap = _baseV7Snapshot(openingBalanceCents: 12000);
          final backupService = EncryptionBackupService();
          final validEnvelope = await backupService.encryptDatabasePayload(
            rawDatabaseJson: jsonEncode(targetSnap),
            passphrase: 'Pass#344',
            schemaVersion: 7,
          );

          // Inject post-import, post-reopen fault right before deleteQuarantine
          manager.preQuarantineDeleteHookForTesting = () async {
            throw const BackupValidationException(
              BackupFailureKind.databaseImportFailure,
              'Simulated post-reopen verification failure.',
            );
          };

          final res = await manager.restoreEncryptedBackupInRecoveryDetailed(
            encryptedEnvelopeJson: validEnvelope,
            passphrase: 'Pass#344',
          );
          expect(res.success, isFalse);
          expect(res.failureKind, BackupFailureKind.databaseImportFailure);
          expect(
            res.message,
            contains('Original database was restored from quarantine'),
          );
          expect(manager.isInitialized, isTrue);
          expect(manager.liquidCashCents, 750000);
          // Quarantine copy stays intact on disk after rollback
          expect(quarantineDir.existsSync(), isTrue);
          expect(
            quarantineDir
                .listSync(recursive: true)
                .whereType<File>()
                .any((f) => p.basename(f.path) == 'personal_management.sqlite'),
            isTrue,
          );

          await manager.disposeAsync();
        },
      );

      test(
        '8-Step Rollback on corrupt startup recovery failure: preserves '
        'corrupt-startup recovery state, diagnostics, and quarantined '
        '.sqlite/-wal/-shm',
        () async {
          final tempDir = Directory.systemTemp.createTempSync('dw_rb2_');
          addTearDown(() {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          });
          final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
          final supportDir = Directory(p.join(tempDir.path, 'support'))
            ..createSync();
          final dbPath = p.join(docsDir.path, 'personal_management.sqlite');
          final dbFile = File(dbPath);
          final walFile = File('${dbFile.path}-wal');
          final shmFile = File('${dbFile.path}-shm');

          final corruptBytes = List<int>.filled(64, 0xAB);
          final walBytes = List<int>.filled(32, 0xCD);
          final shmBytes = List<int>.filled(16, 0xEF);
          dbFile.writeAsBytesSync(corruptBytes, flush: true);
          walFile.writeAsBytesSync(walBytes, flush: true);
          shmFile.writeAsBytesSync(shmBytes, flush: true);

          final exporter = RawDatabaseRecoveryExporter(
            documentsDirProvider: () async => docsDir,
            supportDirProvider: () async => supportDir,
          );
          final manager = AppStateManager(
            databaseBuilder: () => AppDatabase(NativeDatabase(dbFile)),
            recoveryExporter: exporter,
            notificationService: _NoOpNotificationService(),
          );
          await manager.initialize();
          expect(manager.isInitialized, isFalse);
          expect(manager.startupFailure?.isCorruption, isTrue);

          final backupService = EncryptionBackupService();
          final validEnvelope = await backupService.encryptDatabasePayload(
            rawDatabaseJson: jsonEncode(_baseV7Snapshot()),
            passphrase: 'Pass#344',
            schemaVersion: 7,
          );
          manager.preQuarantineDeleteHookForTesting = () async {
            throw const BackupValidationException(
              BackupFailureKind.databaseImportFailure,
              'Simulated post-reopen recovery abort.',
            );
          };

          final res = await manager.restoreEncryptedBackupInRecoveryDetailed(
            encryptedEnvelopeJson: validEnvelope,
            passphrase: 'Pass#344',
          );
          expect(res.success, isFalse);
          expect(manager.isInitialized, isFalse);
          expect(manager.startupFailure?.isCorruption, isTrue);
          expect(await exporter.readFailureDiagnostic(), isNotNull);
          // Corrupt original DB + sidecar files copied back faithfully
          expect(dbFile.readAsBytesSync(), corruptBytes);
          expect(walFile.readAsBytesSync(), walBytes);
          expect(shmFile.readAsBytesSync(), shmBytes);

          await manager.disposeAsync();
        },
      );

      test(
        'Best-effort post-commit notification failure does not roll back '
        'verified restore',
        () async {
          final tempDir = Directory.systemTemp.createTempSync('dw_nf_');
          addTearDown(() {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          });
          final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
          final supportDir = Directory(p.join(tempDir.path, 'support'))
            ..createSync();
          final dbPath = p.join(docsDir.path, 'personal_management.sqlite');
          final dbFile = File(dbPath);
          final quarantineDir =
              Directory(p.join(docsDir.path, 'recovery_quarantine'));

          final manager = AppStateManager(
            databaseBuilder: () => AppDatabase(NativeDatabase(dbFile)),
            recoveryExporter: RawDatabaseRecoveryExporter(
              documentsDirProvider: () async => docsDir,
              supportDirProvider: () async => supportDir,
            ),
            notificationService: _ThrowingNotificationService(),
          );
          await manager.initialize();

          final dueCommitmentSnap = _baseV7Snapshot(
            commitments: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'com-due',
                'title': 'Due Rent',
                'amountCents': 50000,
                'dueDate': '2026-11-01',
                'isPaid': false,
              },
            ],
          );
          final backupService = EncryptionBackupService();
          final envelope = await backupService.encryptDatabasePayload(
            rawDatabaseJson: jsonEncode(dueCommitmentSnap),
            passphrase: 'Pass#344',
            schemaVersion: 7,
          );

          final res = await manager.restoreEncryptedBackupInRecoveryDetailed(
            encryptedEnvelopeJson: envelope,
            passphrase: 'Pass#344',
          );
          expect(res.success, isTrue);
          expect(manager.isInitialized, isTrue);
          expect(manager.liquidCashCents, 100000);
          expect(quarantineDir.existsSync(), isFalse);

          await manager.disposeAsync();
        },
      );
    },
  );

  group(
    'Stage 3.4.4.1 — Recovery Cleanup Warnings, Concurrency Lock, '
    'Settings Normalization & Phase A Bounds',
    () {
      test(
        'Post-commit deleteQuarantine() and clearFailureDiagnostic() failures '
        'never reverse a committed restore and emit warning diagnostics',
        () async {
          final tempDir = Directory.systemTemp.createTempSync('dw_cw_');
          addTearDown(() {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          });
          final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
          final supportDir = Directory(p.join(tempDir.path, 'support'))
            ..createSync();
          final dbFile =
              File(p.join(docsDir.path, 'personal_management.sqlite'));

          // Simulate corrupt DB startup recovery with diagnostic on disk
          dbFile.writeAsBytesSync(List<int>.filled(64, 0xAB), flush: true);

          final exporter = _ThrowingCleanupRecoveryExporter(
            documentsDirProvider: () async => docsDir,
            supportDirProvider: () async => supportDir,
          );
          final manager = AppStateManager(
            databaseBuilder: () => AppDatabase(NativeDatabase(dbFile)),
            recoveryExporter: exporter,
            notificationService: _NoOpNotificationService(),
          );
          await manager.initialize();
          expect(manager.isInitialized, isFalse);

          final snap = _baseV7Snapshot(
            schemaVersion: 8,
            reminders: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'rem-cw',
                'targetId': 'rem-cw',
                'targetType': 'custom',
                'title': 'Check balance',
                'channelId': 'general_alerts',
                'triggerTimeUtc': '2026-11-28T08:00:00.000Z',
                'createdAt': '2026-11-16T08:00:00.000Z',
              },
            ],
          );
          final envelope =
              await EncryptionBackupService().encryptDatabasePayload(
            rawDatabaseJson: jsonEncode(snap),
            passphrase: 'Pass#3441',
            schemaVersion: 8,
          );

          final res = await manager.restoreEncryptedBackupInRecoveryDetailed(
            encryptedEnvelopeJson: envelope,
            passphrase: 'Pass#3441',
          );
          expect(res.success, isTrue);
          expect(manager.isInitialized, isTrue);
          expect(manager.startupFailure, isNull);
          expect(manager.liquidCashCents, 100000);
          final codes = res.diagnostics.map((d) => d.code).toSet();
          expect(
            codes,
            containsAll(<String>{
              'QUARANTINE_CLEANUP_WARNING',
              'FAILURE_DIAGNOSTIC_CLEANUP_WARNING',
            }),
          );
          expect(
            res.warnings.any((w) => w.contains('QUARANTINE_CLEANUP_WARNING')),
            isTrue,
          );
          expect(
            res.warnings
                .any((w) => w.contains('FAILURE_DIAGNOSTIC_CLEANUP_WARNING')),
            isTrue,
          );

          await manager.disposeAsync();
        },
      );

      test(
        'Concurrent recovery/import calls fail fast without state corruption '
        'and release lock cleanly in finally on success or error',
        () async {
          final tempDir = Directory.systemTemp.createTempSync('dw_lock_');
          addTearDown(() {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          });
          final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
          final supportDir = Directory(p.join(tempDir.path, 'support'))
            ..createSync();
          final dbFile =
              File(p.join(docsDir.path, 'personal_management.sqlite'));

          final manager = AppStateManager(
            databaseBuilder: () => AppDatabase(NativeDatabase(dbFile)),
            recoveryExporter: RawDatabaseRecoveryExporter(
              documentsDirProvider: () async => docsDir,
              supportDirProvider: () async => supportDir,
            ),
            notificationService: _NoOpNotificationService(),
          );
          await manager.initialize();

          final gate = Completer<void>();
          manager.preQuarantineDeleteHookForTesting = () => gate.future;

          final snap = _baseV7Snapshot(schemaVersion: 8);
          final envelope =
              await EncryptionBackupService().encryptDatabasePayload(
            rawDatabaseJson: jsonEncode(snap),
            passphrase: 'Pass#3441',
            schemaVersion: 8,
          );

          final firstRestoreFuture =
              manager.restoreEncryptedBackupInRecoveryDetailed(
            encryptedEnvelopeJson: envelope,
            passphrase: 'Pass#3441',
          );

          // Wait until first restore enters in-flight state
          while (!manager.isRestoreInProgress) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }

          final concurrentRecovery =
              await manager.restoreEncryptedBackupInRecoveryDetailed(
            encryptedEnvelopeJson: envelope,
            passphrase: 'Pass#3441',
          );
          expect(concurrentRecovery.success, isFalse);
          expect(
            concurrentRecovery.failureKind,
            BackupFailureKind.databaseImportFailure,
          );
          expect(concurrentRecovery.message, contains('already in progress'));

          final concurrentCanonical =
              await manager.importCanonicalSnapshotDetailed(snap);
          expect(concurrentCanonical.success, isFalse);
          expect(concurrentCanonical.message, contains('already in progress'));

          final concurrentBackup =
              await manager.restoreFromEncryptedBackupDetailed(
            envelope,
            'Pass#3441',
          );
          expect(concurrentBackup.success, isFalse);
          expect(concurrentBackup.message, contains('already in progress'));

          gate.complete();
          final firstResult = await firstRestoreFuture;
          expect(firstResult.success, isTrue);
          expect(manager.isRestoreInProgress, isFalse);

          // Subsequent sequential call succeeds (lock released cleanly)
          final afterSuccess =
              await manager.importCanonicalSnapshotDetailed(snap);
          expect(afterSuccess.success, isTrue);
          expect(manager.isRestoreInProgress, isFalse);

          await manager.disposeAsync();
        },
      );

      test(
        'Case/whitespace normalized appSettings policy, clearExisting: false '
        'merge cleanup, and merge reminders targeting live DB entities',
        () async {
          expect(
            AppSettingsBackupPolicy.isSecretOrDeviceKey('  SECRET_API  '),
            isTrue,
          );
          expect(
            AppSettingsBackupPolicy.isSecretOrDeviceKey(' Push_Token '),
            isTrue,
          );
          expect(
            AppSettingsBackupPolicy.isTopLevelManagedKey(
              'Opening_Balance_Cents',
            ),
            isTrue,
          );
          expect(
            AppSettingsBackupPolicy.isInternalSentinelKey(
              'INITIAL_SEED_COMPLETED',
            ),
            isTrue,
          );

          final db = AppDatabase(NativeDatabase.memory());
          await db.ensureInitialized();
          addTearDown(db.close);

          final now = DateTime.utc(2026, 11, 16, 12, 0);
          await db.into(db.tasks).insert(
                TasksCompanion.insert(
                  id: 'task-live-merge',
                  title: 'Live Target Task',
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          await db.into(db.appSettings).insertOnConflictUpdate(
                AppSettingsCompanion.insert(
                  key: 'Calendar_Display_Mode',
                  value: 'gregorian',
                  updatedAt: now,
                ),
              );
          await db.into(db.appSettings).insertOnConflictUpdate(
                AppSettingsCompanion.insert(
                  key: 'custom_theme_note',
                  value: 'keep_me',
                  updatedAt: now,
                ),
              );

          final mergeSnap = <String, dynamic>{
            'schemaVersion': 8,
            'accounts': const <Map<String, dynamic>>[],
            'categories': const <Map<String, dynamic>>[],
            'parties': const <Map<String, dynamic>>[],
            'goals': const <Map<String, dynamic>>[],
            'projects': const <Map<String, dynamic>>[],
            'milestones': const <Map<String, dynamic>>[],
            'tasks': const <Map<String, dynamic>>[],
            'notes': const <Map<String, dynamic>>[],
            'inboxItems': const <Map<String, dynamic>>[],
            'calendarEvents': const <Map<String, dynamic>>[],
            'commitments': const <Map<String, dynamic>>[],
            'transactions': const <Map<String, dynamic>>[],
            'journalEntries': const <Map<String, dynamic>>[],
            'postings': const <Map<String, dynamic>>[],
            'debts': const <Map<String, dynamic>>[],
            'settlementAllocations': const <Map<String, dynamic>>[],
            'commitmentSettlements': const <Map<String, dynamic>>[],
            'savingsGoals': const <Map<String, dynamic>>[],
            'budgets': const <Map<String, dynamic>>[],
            'recurringRules': const <Map<String, dynamic>>[],
            'reminders': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'rem-merge-live',
                'targetId': 'task-live-merge',
                'targetType': 'task',
                'title': 'Live Task Reminder',
                'channelId': 'task_channel',
                'triggerTimeUtc': '2026-11-20T09:00:00.000Z',
                'createdAt': '2026-11-16T09:00:00.000Z',
              },
            ],
            'appSettings': <Map<String, dynamic>>[
              <String, dynamic>{
                'key': '  calendar_display_mode  ',
                'value': 'ethiopian',
              },
              <String, dynamic>{
                'key': 'PUSH_TOKEN',
                'value': 'should-skip',
              },
            ],
          };

          final report =
              await DatabasePersistenceCoordinator(db).importSnapshotDetailed(
            mergeSnap,
            clearExisting: false,
          );
          expect(
            report.diagnostics
                .any((d) => d.code == 'ORPHANED_REMINDER_SKIPPED'),
            isFalse,
          );
          expect(
            report.diagnostics
                .where((d) => d.code == 'EXCLUDED_APP_SETTING_SKIPPED')
                .length,
            1,
          );

          final reminders = await db.select(db.reminders).get();
          expect(reminders.single.id, 'rem-merge-live');
          expect(reminders.single.title, 'Live Task Reminder');
          expect(reminders.single.channelId, 'task_channel');

          final settingsRows = await db.select(db.appSettings).get();
          final settingsMap = {for (final r in settingsRows) r.key: r.value};
          expect(settingsMap.containsKey('Calendar_Display_Mode'), isFalse);
          expect(settingsMap['calendar_display_mode'], 'ethiopian');
          expect(settingsMap['custom_theme_note'], 'keep_me');
          expect(settingsMap.containsKey('PUSH_TOKEN'), isFalse);
        },
      );

      test(
        'Phase A enforces all 12 Drift withLength bounds, allocatedCents >= 1, '
        'and v7+ fail-closed vs pre-v7 fallback for transfer categoryId',
        () {
          // 1. All 12 Drift withLength bounds: max succeeds, max+1 fails closed
          final boundCases = <({
            String label,
            int maxLen,
            Map<String, dynamic> Function(String value) build,
          })>[
            (
              label: 'categories.name',
              maxLen: 100,
              build: (v) => _baseV7Snapshot(
                    schemaVersion: 8,
                    categories: <Map<String, dynamic>>[
                      <String, dynamic>{
                        'id': 'cat-other-exp',
                        'name': v,
                        'type': 'expense',
                      },
                    ],
                  ),
            ),
            (
              label: 'accounts.name',
              maxLen: 150,
              build: (v) => _baseV7Snapshot(
                    schemaVersion: 8,
                    accounts: <Map<String, dynamic>>[
                      <String, dynamic>{
                        'id': 'acc-cash',
                        'name': v,
                        'type': 'asset',
                        'subType': 'cash',
                        'currencyCode': 'ETB',
                        'openingBalanceCents': 100000,
                      },
                    ],
                  ),
            ),
            (
              label: 'parties.name',
              maxLen: 150,
              build: (v) => _baseV7Snapshot(
                    schemaVersion: 8,
                    parties: <Map<String, dynamic>>[
                      <String, dynamic>{'id': 'pty-1', 'name': v},
                    ],
                  ),
            ),
            (
              label: 'goals.title',
              maxLen: 200,
              build: (v) => _baseV7Snapshot(
                    schemaVersion: 8,
                    goals: <Map<String, dynamic>>[
                      <String, dynamic>{
                        'id': 'goal-1',
                        'title': v,
                        'status': 'active',
                      },
                    ],
                  ),
            ),
            (
              label: 'projects.title',
              maxLen: 200,
              build: (v) => _baseV7Snapshot(
                    schemaVersion: 8,
                    projects: <Map<String, dynamic>>[
                      <String, dynamic>{'id': 'proj-1', 'title': v},
                    ],
                  ),
            ),
            (
              label: 'milestones.title',
              maxLen: 200,
              build: (v) => _baseV7Snapshot(
                    schemaVersion: 8,
                    projects: <Map<String, dynamic>>[
                      <String, dynamic>{'id': 'proj-1', 'title': 'Proj'},
                    ],
                    milestones: <Map<String, dynamic>>[
                      <String, dynamic>{
                        'id': 'ms-1',
                        'projectId': 'proj-1',
                        'title': v,
                      },
                    ],
                  ),
            ),
            (
              label: 'tasks.title',
              maxLen: 300,
              build: (v) => _baseV7Snapshot(
                    schemaVersion: 8,
                    tasks: <Map<String, dynamic>>[
                      <String, dynamic>{'id': 't-1', 'title': v},
                    ],
                  ),
            ),
            (
              label: 'notes.title',
              maxLen: 250,
              build: (v) => _baseV7Snapshot(
                    schemaVersion: 8,
                    notes: <Map<String, dynamic>>[
                      <String, dynamic>{'id': 'n-1', 'title': v},
                    ],
                  ),
            ),
            (
              label: 'calendarEvents.title',
              maxLen: 250,
              build: (v) => _baseV7Snapshot(
                    schemaVersion: 8,
                    calendarEvents: <Map<String, dynamic>>[
                      <String, dynamic>{
                        'id': 'e-1',
                        'title': v,
                        'dateIso': '2026-11-16',
                      },
                    ],
                  ),
            ),
            (
              label: 'savingsGoals.title',
              maxLen: 200,
              build: (v) => _baseV7Snapshot(
                    schemaVersion: 8,
                    savingsGoals: <Map<String, dynamic>>[
                      <String, dynamic>{
                        'id': 'sg-1',
                        'title': v,
                        'targetCents': 1000,
                      },
                    ],
                  ),
            ),
            (
              label: 'recurringRules.title',
              maxLen: 200,
              build: (v) => _baseV7Snapshot(
                    schemaVersion: 8,
                    recurringRules: <Map<String, dynamic>>[
                      <String, dynamic>{
                        'id': 'rr-1',
                        'title': v,
                        'amountCents': 1000,
                        'startDate': '2026-11-01',
                        'nextOccurrenceDate': '2026-12-01',
                      },
                    ],
                  ),
            ),
            (
              label: 'commitments.title',
              maxLen: 200,
              build: (v) => _baseV7Snapshot(
                    schemaVersion: 8,
                    commitments: <Map<String, dynamic>>[
                      <String, dynamic>{
                        'id': 'c-1',
                        'title': v,
                        'amountCents': 1000,
                        'dueDate': '2026-11-30',
                      },
                    ],
                  ),
            ),
          ];

          for (final tc in boundCases) {
            final exact =
                DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
              tc.build('a' * tc.maxLen),
            );
            expect(exact.snapshotVersion, 8, reason: tc.label);
            expect(
              () => DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
                tc.build('a' * (tc.maxLen + 1)),
              ),
              _throwsValidationKind(BackupFailureKind.invalidPayload),
              reason: '${tc.label} overflow must reject',
            );
          }

          // 2. settlementAllocations.allocatedCents must be >= 1
          for (final badAlloc in const <int>[0, -100]) {
            expect(
              () => DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
                _baseV7Snapshot(
                  schemaVersion: 8,
                  parties: <Map<String, dynamic>>[
                    <String, dynamic>{'id': 'pty-1', 'name': 'Alex'},
                  ],
                  debts: <Map<String, dynamic>>[
                    <String, dynamic>{
                      'id': 'd-1',
                      'originEntryId': 'je-open-cash',
                      'partyId': 'pty-1',
                      'debtType': 'payable',
                      'principalCents': 5000,
                    },
                  ],
                  settlementAllocations: <Map<String, dynamic>>[
                    <String, dynamic>{
                      'id': 'sa-bad',
                      'settlementEntryId': 'je-open-cash',
                      'debtId': 'd-1',
                      'allocatedCents': badAlloc,
                      'settlementDate': '2026-11-16',
                    },
                  ],
                ),
              ),
              _throwsValidationKind(BackupFailureKind.invalidPayload),
            );
          }

          // 3. v7/v8 transfer missing categoryId fails closed; pre-v7 falls back
          final missingCatTransferTx = <String, dynamic>{
            'id': 'tx-xfer',
            'amountCents': 5000,
            'type': 'transfer',
            'transactionDate': '2026-11-16',
          };
          for (final v in const <int>[7, 8]) {
            expect(
              () => DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
                _baseV7Snapshot(
                  schemaVersion: v,
                  transactions: <Map<String, dynamic>>[missingCatTransferTx],
                ),
              ),
              _throwsValidationKind(BackupFailureKind.invalidPayload),
            );
          }

          final legacyPrepared =
              DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
            _baseV7Snapshot(
              schemaVersion: 6,
              transactions: <Map<String, dynamic>>[missingCatTransferTx],
            ),
          );
          expect(
            legacyPrepared.transactions.single.categoryId.value,
            'cat-other-exp',
          );
          expect(
            legacyPrepared.preImportDiagnostics.any(
              (d) => d.code == 'LEGACY_TRANSACTION_DEFAULT_CATEGORY_APPLIED',
            ),
            isTrue,
          );

          // 4. Stage 2.2 strict ETB-only snapshot currency enforcement:
          // Rejects explicit non-ETB, unrecognized, blank, and v7/v8 omitted currencyCode;
          // preserves pre-v7 omitted currencyCode as '' + CURRENCY_UNVERIFIED_ON_LEGACY_IMPORT.
          for (final badAccount in const <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'acc-usd',
              'name': 'USD Cash',
              'type': 'asset',
              'currencyCode': 'USD',
            },
            <String, dynamic>{
              'id': 'acc-xyz',
              'name': 'Bad ISO',
              'type': 'asset',
              'currencyCode': 'XYZ',
            },
            <String, dynamic>{
              'id': 'acc-empty',
              'name': 'Empty Code',
              'type': 'asset',
              'currencyCode': '  ',
            },
          ]) {
            expect(
              () => DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
                _baseV7Snapshot(
                  schemaVersion: 8,
                  accounts: <Map<String, dynamic>>[badAccount],
                ),
              ),
              _throwsValidationKind(BackupFailureKind.invalidPayload),
            );
          }

          for (final v in const <int>[7, 8]) {
            expect(
              () => DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
                _baseV7Snapshot(
                  schemaVersion: v,
                  accounts: const <Map<String, dynamic>>[
                    <String, dynamic>{
                      'id': 'acc-missing-cur',
                      'name': 'Cash',
                      'type': 'asset',
                    },
                  ],
                ),
              ),
              _throwsValidationKind(BackupFailureKind.invalidPayload),
            );
          }

          final legacyUnverifiedCurrencyPrepared =
              DatabasePersistenceCoordinator.validateAndPrepareSnapshot(
            _baseV7Snapshot(
              schemaVersion: 6,
              accounts: const <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'acc-legacy-unv',
                  'name': 'Legacy Wallet',
                  'type': 'asset',
                },
              ],
              journalEntries: const <Map<String, dynamic>>[],
              postings: const <Map<String, dynamic>>[],
            ),
          );
          expect(
            legacyUnverifiedCurrencyPrepared.accounts.single.currencyCode.value,
            '',
          );
          expect(
            legacyUnverifiedCurrencyPrepared.preImportDiagnostics.any(
              (d) => d.code == 'CURRENCY_UNVERIFIED_ON_LEGACY_IMPORT',
            ),
            isTrue,
          );

          // AppStateManager quick capture currency parity check
          expect(
            AppStateManager.detectQuickCaptureUnsupportedCurrency(
              r'Coffee $15',
            ),
            r'USD ($)',
          );
          expect(
            AppStateManager.detectQuickCaptureUnsupportedCurrency(
              '100 USD lunch',
            ),
            'USD',
          );
          expect(
            AppStateManager.parseQuickCaptureExpense(r'Coffee $15'),
            isNull,
          );
          expect(
            AppStateManager.parseQuickCaptureExpense('200 pen notebook')
                ?.amountCents,
            20000,
          );
        },
      );
    },
  );
}
