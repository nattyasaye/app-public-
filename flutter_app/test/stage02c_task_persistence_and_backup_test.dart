import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/tasks/tasks_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/interfaces/platform_service_interfaces.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/database_persistence_coordinator.dart';
import 'package:personal_management_app/data/repositories/tasks_repository.dart';
import 'package:personal_management_app/services/backup/encryption_backup_service.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  configureSqliteForHostTests();

  group(
      'Stage 0.2C — Flutter Task Persistence, DailyPlanning & Backup Compatibility',
      () {
    test(
      '1 & 2. DriftTasksRepository + TasksController persist all 6 v10 Task fields, normalized subtask IDs, and DailyPlanningEntries with cascade delete',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final repo = DriftTasksRepository(db);
        final controller = TasksController(repository: repo);
        final recurrence = TaskRecurrenceConfig(
          frequency: 'weekly',
          interval: 2,
          weekdays: const [1, 4],
          startDate: CalendarDate(year: 2026, month: 11, day: 1),
          endDate: CalendarDate(year: 2027, month: 1, day: 31),
          repeatFrom: 'completion_date',
        );

        await controller.createTask(
          id: 'task-ctrl-1',
          title: 'Design Audit',
          description: 'Review color contrast and tokens',
          priority: 'high',
          dueDate: CalendarDate(year: 2026, month: 11, day: 25),
          scheduledDate: CalendarDate(year: 2026, month: 11, day: 21),
          scheduledTime: '09:45',
          isMyDay: true,
          myDayDate: CalendarDate(year: 2026, month: 11, day: 21),
          recurrenceRule: 'weekly',
          recurrenceConfig: recurrence,
          isArchived: true,
          sortOrder: 5,
        );
        await controller.addSubtask('task-ctrl-1', 'Check light theme');
        await controller.toggleTaskStatus('task-ctrl-1');

        final loadedTasks = await repo.getTasks();
        expect(loadedTasks.length, 1);
        final task = loadedTasks.single;
        expect(task.status, 'completed');
        expect(task.completedAt, isNotNull);
        expect(task.scheduledTime, '09:45');
        expect(task.myDayDate, CalendarDate(year: 2026, month: 11, day: 21));
        expect(task.recurrenceConfig, recurrence);
        expect(task.isArchived, isTrue);
        expect(task.sortOrder, 5);
        expect(task.subtasks.single.id, 'task-ctrl-1-sub-1');
        expect(task.subtasks.single.title, 'Check light theme');

        // Verify controller completion synced the 2026-11-21 DailyPlanningEntry,
        // then upsert an explicit entry on 2026-11-22 and verify query + cascade.
        final syncedEntries = await repo.getDailyPlanningEntries(
          planDate: CalendarDate(year: 2026, month: 11, day: 21),
        );
        expect(syncedEntries.length, 1);
        expect(syncedEntries.single.id, 'dpe-2026-11-21-task-ctrl-1');
        expect(syncedEntries.single.action, 'completed');

        final entry = DailyPlanningEntryEntity(
          id: 'dpe-1',
          planDate: CalendarDate(year: 2026, month: 11, day: 22),
          taskId: 'task-ctrl-1',
          action: 'completed',
          createdAt: DateTime.utc(2026, 11, 22, 6, 0),
          updatedAt: DateTime.utc(2026, 11, 22, 10, 0),
        );
        await repo.upsertDailyPlanningEntry(entry);
        final entries = await repo.getDailyPlanningEntries(
          planDate: CalendarDate(year: 2026, month: 11, day: 22),
        );
        expect(entries.length, 1);
        expect(entries.single.id, 'dpe-1');
        expect(entries.single.action, 'completed');

        // Deleting task cascades DailyPlanningEntries cleanly
        await repo.deleteTask('task-ctrl-1');
        expect(await repo.getTasks(), isEmpty);
        expect(await repo.getDailyPlanningEntries(), isEmpty);
      },
    );

    test(
      '3. Full v11 snapshot + .daywell encrypted backup export declares databaseSchemaVersion 11 and restores all v10 Task fields & DailyPlanningEntries losslessly',
      () async {
        final sourceDb = AppDatabase(NativeDatabase.memory());
        await sourceDb.ensureInitialized();
        addTearDown(sourceDb.close);

        final repo = DriftTasksRepository(sourceDb);
        final project = ProjectEntity(
          id: 'proj-v10',
          title: 'Daywell Core',
        );
        await repo.createProject(project);
        await repo.createTask(
          TaskEntity(
            id: 'task-v10',
            title: 'Ship v10 Backup',
            status: 'completed',
            priority: 'urgent',
            completedAt: DateTime.utc(2026, 11, 21, 12, 30),
            dueDate: CalendarDate(year: 2026, month: 11, day: 21),
            scheduledDate: CalendarDate(year: 2026, month: 11, day: 21),
            scheduledTime: '15:20',
            projectId: 'proj-v10',
            subtasks: const [
              TaskSubtask(id: 'sub-custom-1', title: 'Export', done: true),
              TaskSubtask(id: 'sub-custom-2', title: 'Restore', done: false),
            ],
            isMyDay: true,
            myDayDate: CalendarDate(year: 2026, month: 11, day: 21),
            recurrenceRule: 'daily',
            recurrenceConfig: TaskRecurrenceConfig(
              frequency: 'daily',
              interval: 1,
              startDate: CalendarDate(year: 2026, month: 11, day: 1),
              endDate: CalendarDate(year: 2026, month: 12, day: 31),
              repeatFrom: 'due_date',
            ),
            isArchived: true,
            sortOrder: 9,
          ),
        );
        await repo.upsertDailyPlanningEntry(
          DailyPlanningEntryEntity(
            id: 'dpe-v10-1',
            planDate: CalendarDate(year: 2026, month: 11, day: 21),
            taskId: 'task-v10',
            action: 'carried_forward',
            createdAt: DateTime.utc(2026, 11, 21, 5, 0),
            updatedAt: DateTime.utc(2026, 11, 21, 12, 30),
          ),
        );

        final coordinator = DatabasePersistenceCoordinator(sourceDb);
        final exported = await coordinator.exportSnapshot();
        expect(exported['schemaVersion'], 5);
        expect(exported['snapshotFormatVersion'], 2);
        expect(exported['databaseSchemaVersion'], 11);

        // Encrypt & decrypt through EncryptionBackupService (.daywell)
        final backupService = EncryptionBackupService();
        final envelope = await backupService.encryptDatabasePayload(
          rawDatabaseJson: jsonEncode(exported),
          passphrase: 'StrongPass#Stage02C',
          schemaVersion: exported['schemaVersion'] as int,
        );
        final decryptedJson = await backupService.decryptDatabasePayload(
          encryptedEnvelopeJson: envelope,
          passphrase: 'StrongPass#Stage02C',
        );
        final decryptedMap = jsonDecode(decryptedJson) as Map<String, dynamic>;

        final targetDb = AppDatabase(NativeDatabase.memory());
        await targetDb.ensureInitialized();
        addTearDown(targetDb.close);

        final report = await DatabasePersistenceCoordinator(targetDb)
            .importSnapshotDetailed(decryptedMap);
        expect(report.diagnostics, isEmpty);
        expect(report.restoredRecordCounts['tasks'], 1);
        expect(report.restoredRecordCounts['dailyPlanningEntries'], 1);
        await DatabasePersistenceCoordinator.verifyRestoredDatabaseInvariants(
          targetDb,
        );

        final restoredTasks = await DriftTasksRepository(targetDb).getTasks();
        expect(restoredTasks.single.completedAt,
            DateTime.utc(2026, 11, 21, 12, 30));
        expect(restoredTasks.single.scheduledTime, '15:20');
        expect(
          restoredTasks.single.myDayDate,
          CalendarDate(year: 2026, month: 11, day: 21),
        );
        expect(restoredTasks.single.recurrenceConfig?.frequency, 'daily');
        expect(restoredTasks.single.isArchived, isTrue);
        expect(restoredTasks.single.sortOrder, 9);
        expect(restoredTasks.single.subtasks.map((s) => s.id).toList(), [
          'sub-custom-1',
          'sub-custom-2',
        ]);

        final restoredEntries =
            await DriftTasksRepository(targetDb).getDailyPlanningEntries();
        expect(restoredEntries.single.id, 'dpe-v10-1');
        expect(restoredEntries.single.action, 'carried_forward');
        expect(
          restoredEntries.single.planDate,
          CalendarDate(year: 2026, month: 11, day: 21),
        );
      },
    );

    test(
      '4 & 5. Older v4-v9 snapshots (format-1 & format-2 v9) import safely with v10 defaults and normalized subtask IDs',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final legacyPayloads = <Map<String, dynamic>>[
          {
            'schemaVersion': 4,
            'accounts': const [],
            'transactions': const [],
            'tasks': [
              {
                'id': 'task-v4',
                'title': 'Legacy v4',
                'status': 'not_started',
                'priority': 'medium',
                'subtasks': [
                  {'title': 'Old subtask', 'completed': true},
                ],
                'createdAt': '2025-11-01T08:00:00.000Z',
                'updatedAt': '2025-11-01T08:00:00.000Z',
              },
            ],
          },
          {
            'schemaVersion': 5,
            'snapshotFormatVersion': 2,
            'databaseSchemaVersion': 9,
            'accounts': const [],
            'transactions': const [],
            'tasks': [
              {
                'id': 'task-v9',
                'title': 'Legacy format-2 v9',
                'status': 'completed',
                'priority': 'high',
                'subtasks': [
                  {'id': 'sub-9', 'title': 'Existing id', 'done': false},
                ],
                'createdAt': '2026-11-01T08:00:00.000Z',
                'updatedAt': '2026-11-01T08:00:00.000Z',
              },
            ],
          },
        ];

        final coordinator = DatabasePersistenceCoordinator(db);
        for (final snap in legacyPayloads) {
          final report = await coordinator.importSnapshotDetailed(snap);
          expect(report.restoredRecordCounts['dailyPlanningEntries'], 0);
          final task = (await DriftTasksRepository(db).getTasks()).single;
          expect(task.isArchived, isFalse);
          expect(task.sortOrder, 0);
          expect(task.completedAt, isNull);
          expect(task.scheduledTime, isNull);
          expect(task.myDayDate, isNull);
          expect(task.recurrenceConfig, isNull);
          expect(task.subtasks.single.id, isNotEmpty);
        }
      },
    );

    test(
      '6. Finance-only export/import excludes DailyPlanningEntries and preserves SQLite Task & DailyPlanning state untouched',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        await db.into(db.accountsTable).insert(
              AccountsTableCompanion.insert(
                id: 'acc-etb',
                name: 'Cash',
                type: 'asset',
                subType: const Value('cash'),
                currencyCode: const Value('ETB'),
                openingBalanceCents: const Value(50000),
                createdAt: DateTime.utc(2026, 11, 20),
              ),
            );
        await DriftTasksRepository(db).createTask(
          TaskEntity(
            id: 'task-keep-fin',
            title: 'Keep across Finance-only restore',
            scheduledTime: '08:00',
          ),
        );
        await DriftTasksRepository(db).upsertDailyPlanningEntry(
          DailyPlanningEntryEntity(
            id: 'dpe-keep-fin',
            planDate: CalendarDate(year: 2026, month: 11, day: 21),
            taskId: 'task-keep-fin',
            action: 'planned',
          ),
        );

        final coordinator = DatabasePersistenceCoordinator(db);
        final finExport = await coordinator.exportFinanceOnlySnapshot();
        expect(finExport['financeOnly'], isTrue);
        expect(finExport['databaseSchemaVersion'], 11);
        expect(finExport.containsKey('tasks'), isFalse);
        expect(finExport.containsKey('dailyPlanningEntries'), isFalse);

        // Finance-only import rejects snapshots carrying dailyPlanningEntries
        final contaminated = Map<String, dynamic>.from(finExport)
          ..['dailyPlanningEntries'] = const [];
        expect(
          () => coordinator.importFinanceOnlySnapshot(contaminated),
          throwsA(
            isA<BackupValidationException>().having(
              (e) => e.kind,
              'kind',
              BackupFailureKind.invalidPayload,
            ),
          ),
        );

        // Clean Finance-only import keeps Tasks & DailyPlanningEntries intact
        await coordinator.importFinanceOnlySnapshot(finExport);
        expect((await DriftTasksRepository(db).getTasks()).single.scheduledTime,
            '08:00');
        expect(
          (await DriftTasksRepository(db).getDailyPlanningEntries()).single.id,
          'dpe-keep-fin',
        );
      },
    );

    test(
      '7 & 8. Future versions and invalid DailyPlanningEntries/merge conflicts fail closed without losing existing records',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        await DriftTasksRepository(db).createTask(
          TaskEntity(
            id: 'task-existing',
            title: 'Existing Task',
            scheduledTime: '10:00',
          ),
        );
        await DriftTasksRepository(db).upsertDailyPlanningEntry(
          DailyPlanningEntryEntity(
            id: 'dpe-existing',
            planDate: CalendarDate(year: 2026, month: 11, day: 21),
            taskId: 'task-existing',
            action: 'planned',
          ),
        );

        final coordinator = DatabasePersistenceCoordinator(db);

        // Future databaseSchemaVersion 12 fails closed
        expect(
          () => DatabasePersistenceCoordinator.validateAndPrepareSnapshot({
            'schemaVersion': 5,
            'snapshotFormatVersion': 2,
            'databaseSchemaVersion': 12,
            'accounts': const [],
            'transactions': const [],
          }),
          throwsA(
            isA<BackupValidationException>().having(
              (e) => e.kind,
              'kind',
              BackupFailureKind.unsupportedFutureSchema,
            ),
          ),
        );

        // Merge-mode duplicate (taskId, planDate) under different id fails closed
        await expectLater(
          coordinator.importSnapshotDetailed(
            {
              'schemaVersion': 5,
              'snapshotFormatVersion': 2,
              'databaseSchemaVersion': 10,
              'accounts': const [],
              'transactions': const [],
              'tasks': const [],
              'dailyPlanningEntries': [
                {
                  'id': 'dpe-conflict',
                  'planDate': '2026-11-21',
                  'taskId': 'task-existing',
                  'action': 'completed',
                  'createdAt': '2026-11-21T09:00:00.000Z',
                },
              ],
            },
            clearExisting: false,
          ),
          throwsA(
            isA<BackupValidationException>().having(
              (e) => e.kind,
              'kind',
              BackupFailureKind.invalidPayload,
            ),
          ),
        );

        // Existing Task & DailyPlanningEntry remain intact
        expect((await DriftTasksRepository(db).getTasks()).single.id,
            'task-existing');
        expect(
          (await DriftTasksRepository(db).getDailyPlanningEntries()).single.id,
          'dpe-existing',
        );
      },
    );
  });
}
