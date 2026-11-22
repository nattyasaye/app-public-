import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_management_app/application/calendar/calendar_controller.dart';
import 'package:personal_management_app/application/tasks/tasks_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/shared_foundation_bridge.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/domain/calendar/calendar_contracts.dart';
import 'package:personal_management_app/domain/calendar/calendar_models.dart';
import 'package:personal_management_app/domain/finance/double_entry_engine.dart';
import 'package:personal_management_app/domain/tasks/task_contracts.dart';
import 'package:personal_management_app/domain/tasks/task_models.dart';
import 'package:personal_management_app/ui/app_state.dart';

import 'support/sqlite_test_helper.dart';

class _InMemoryCalendarRepository implements ICalendarRepository {
  final Map<String, CalendarEventEntity> _store = {};

  @override
  Future<CalendarEventEntity> createEvent(CalendarEventEntity event) async {
    _store[event.id] = event;
    return event;
  }

  @override
  Future<void> deleteEvent(String id) async {
    _store.remove(id);
  }

  @override
  Future<CalendarEventEntity?> getEventById(String id) async => _store[id];

  @override
  Future<List<CalendarEventEntity>> getEvents({
    String? dateIso,
    String? category,
  }) async {
    return _store.values.where((e) {
      if (dateIso != null && e.dateIso != dateIso) return false;
      if (category != null && e.category != category) return false;
      return true;
    }).toList();
  }

  @override
  Future<CalendarEventEntity> updateEvent(CalendarEventEntity event) async {
    _store[event.id] = event;
    return event;
  }
}

class _InMemoryTasksRepository implements ITasksRepository {
  final Map<String, TaskEntity> _tasks = {};
  final Map<String, DailyPlanningEntryEntity> _dailyPlanningEntries = {};
  final Map<String, ProjectEntity> _projects = {};
  final Map<String, MilestoneEntity> _milestones = {};

  @override
  Future<TaskEntity> createTask(TaskEntity task) async {
    _tasks[task.id] = task;
    return task;
  }

  @override
  Future<void> deleteTask(String id) async => _tasks.remove(id);

  @override
  Future<TaskEntity?> getTaskById(String id) async => _tasks[id];

  @override
  Future<List<TaskEntity>> getTasks({
    String? status,
    String? priority,
    String? projectId,
    bool? isOverdue,
  }) async {
    return _tasks.values.toList();
  }

  @override
  Future<void> postponeTaskDays(String id, int days) async {
    final existing = _tasks[id];
    if (existing == null) return;
    final base = existing.dueDate ?? CalendarDate.today();
    _tasks[id] = existing.copyWith(dueDate: base.addDays(days));
  }

  @override
  Future<void> rescheduleTask(String id, CalendarDate? newDueDate) async {
    final existing = _tasks[id];
    if (existing == null) return;
    _tasks[id] = existing.copyWith(
      dueDate: newDueDate,
      clearDueDate: newDueDate == null,
    );
  }

  @override
  Future<TaskEntity> updateTask(TaskEntity task) async {
    _tasks[task.id] = task;
    return task;
  }

  @override
  Future<void> updateTaskStatus(String id, String newStatus) async {
    final existing = _tasks[id];
    if (existing == null) return;
    _tasks[id] = existing.copyWith(status: newStatus);
  }

  @override
  Future<ProjectEntity> createProject(ProjectEntity project) async {
    _projects[project.id] = project;
    return project;
  }

  @override
  Future<void> deleteProject(String id) async {
    _projects.remove(id);
    for (final entry in _tasks.entries.toList()) {
      if (entry.value.projectId == id) {
        _tasks[entry.key] = entry.value.copyWith(clearProject: true);
      }
    }
    _milestones.removeWhere((_, m) => m.projectId == id);
  }

  @override
  Future<ProjectEntity?> getProjectById(String id) async => _projects[id];

  @override
  Future<List<ProjectEntity>> getProjects({String? status}) async =>
      _projects.values.toList();

  @override
  Future<ProjectEntity> updateProject(ProjectEntity project) async {
    _projects[project.id] = project;
    return project;
  }

  @override
  Future<MilestoneEntity> createMilestone(MilestoneEntity milestone) async {
    _milestones[milestone.id] = milestone;
    return milestone;
  }

  @override
  Future<List<MilestoneEntity>> getAllMilestones() async =>
      _milestones.values.toList();

  @override
  Future<List<MilestoneEntity>> getMilestonesForProject(
    String projectId,
  ) async =>
      _milestones.values.where((m) => m.projectId == projectId).toList();

  @override
  Future<void> toggleMilestone(String id, bool isCompleted) async {
    final existing = _milestones[id];
    if (existing != null) {
      _milestones[id] = existing.copyWith(isCompleted: isCompleted);
    }
  }

  @override
  Future<void> deleteMilestone(String id) async {
    _milestones.remove(id);
  }

  @override
  Future<List<TaskEntity>> getTasksForProject(String projectId) async =>
      _tasks.values.where((t) => t.projectId == projectId).toList();

  @override
  Future<List<DailyPlanningEntryEntity>> getDailyPlanningEntries({
    CalendarDate? planDate,
    String? taskId,
  }) async {
    return _dailyPlanningEntries.values.where((entry) {
      if (planDate != null &&
          entry.planDate.toIsoString() != planDate.toIsoString()) {
        return false;
      }
      if (taskId != null && entry.taskId != taskId) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<DailyPlanningEntryEntity> upsertDailyPlanningEntry(
    DailyPlanningEntryEntity entry,
  ) async {
    _dailyPlanningEntries[entry.id] = entry;
    return entry;
  }

  @override
  Future<void> deleteDailyPlanningEntry(String id) async {
    _dailyPlanningEntries.remove(id);
  }

  @override
  Future<void> deleteDailyPlanningEntriesForTask(String taskId) async {
    _dailyPlanningEntries.removeWhere((_, entry) => entry.taskId == taskId);
  }

  @override
  Future<
      ({
        ProjectEntity project,
        List<TaskEntity> tasks,
        List<MilestoneEntity> milestones,
        int progressPercentage,
      })?> getProjectWithProgress(String projectId) async {
    final project = _projects[projectId];
    if (project == null) return null;
    final tasks = await getTasksForProject(projectId);
    final milestones = await getMilestonesForProject(projectId);
    return (
      project: project,
      tasks: tasks,
      milestones: milestones,
      progressPercentage: 0,
    );
  }
}

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage 2 Unit Controller Hydration', () {
    test(
      'CalendarController persists events and rehydrates cleanly on '
      'fresh restart instance',
      () async {
        final repo = _InMemoryCalendarRepository();
        final controllerA = CalendarController(repository: repo);

        final created = await controllerA.createEvent(
          title: 'Meskel Square Run',
          dateIso: '2026-11-12',
          startTime: '06:30',
          category: 'health',
          hasReminder: true,
        );

        expect(created, isNotNull);
        expect(controllerA.state.events.length, 1);
        controllerA.dispose();

        final controllerB = CalendarController(repository: repo);
        await controllerB.loadAll();

        expect(controllerB.state.events.length, 1);
        expect(controllerB.state.events.first.title, 'Meskel Square Run');
        expect(controllerB.state.events.first.hasReminder, isTrue);
        controllerB.dispose();
      },
    );

    test(
      'TasksController persists Schema v4 task metadata across restart',
      () async {
        final repo = _InMemoryTasksRepository();
        final controllerA = TasksController(repository: repo);

        final task = await controllerA.createTask(
          id: 'task-v4-1',
          title: 'Finalize Stage 2 Audit',
          labels: ['architecture', 'daywell'],
          isMyDay: true,
          recurrenceRule: 'weekly',
        );
        expect(task, isNotNull);

        await controllerA.togglePin(task!.id);
        await controllerA.addSubtask(task.id, 'Verify SQLite schema v4');
        await controllerA.toggleSubtask(task.id, 0, true);
        controllerA.dispose();

        final controllerB = TasksController(repository: repo);
        await controllerB.loadAll();

        final hydrated = controllerB.state.findTaskById('task-v4-1');
        expect(hydrated, isNotNull);
        expect(hydrated!.isPinned, isTrue);
        expect(hydrated.isMyDay, isTrue);
        expect(hydrated.labels, ['architecture', 'daywell']);
        expect(hydrated.recurrenceRule, 'weekly');
        expect(hydrated.subtasks.length, 1);
        expect(hydrated.subtasks.first.done, isTrue);
        controllerB.dispose();
      },
    );
  });

  group('Real File-Backed SQLite Restart Persistence (Part E)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('daywell_restart_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'Persists all 5 modules + Schema v5 metadata across full '
      'AppStateManager teardown & restart without duplicate seeding',
      () async {
        final dbFile = File(p.join(tempDir.path, 'daywell_restart.sqlite'));
        final now = EthiopiaClock.nowUtc();
        final txDate = CalendarDate(year: 2026, month: 11, day: 12);

        // --- SESSION 1 ---
        final db1 = AppDatabase(NativeDatabase(dbFile));
        final state1 = AppStateManager(db: db1);
        await state1.initialize();

        expect(state1.isInitialized, isTrue);
        expect(state1.initializationError, isNull);
        expect(state1.financeController.state.categories.length, 11);

        // Finance setup + accounts + category + tx + commitment + savings
        await state1.financeController.completeSetup([
          AccountModel(
            id: 'acc-cbe-user',
            name: 'CBE Checking',
            type: AccountType.asset,
            openingBalanceCents: 250000,
            openingBalanceDate: '2026-11-12',
            createdAt: now,
          ),
          AccountModel(
            id: 'acc-telebirr-user',
            name: 'Telebirr Wallet',
            type: AccountType.asset,
            openingBalanceCents: 45000,
            openingBalanceDate: '2026-11-12',
            createdAt: now,
          ),
        ]);
        await state1.financeController.addCategory(
          TransactionCategoryModel(
            id: 'cat-custom-solar',
            name: 'Solar Parts',
            type: 'expense',
            colorHex: '#047857',
          ),
        );
        // ignore: deprecated_member_use_from_same_package
        await state1.financeController.recordTransaction(
          TransactionModel(
            id: 'tx-restart-1',
            categoryId: 'cat-custom-solar',
            categoryName: 'Solar Parts',
            amountCents: 18500,
            type: 'expense',
            transactionDate: txDate,
            accountId: 'acc-cbe-user',
            payee: 'Addis Solar',
            note: 'Inverter fuse',
          ),
        );
        await state1.financeController.recordTransfer(
          fromAssetAccountId: 'acc-cbe-user',
          toAssetAccountId: 'acc-telebirr-user',
          amountCents: 10000,
          date: '2026-11-12',
          description: 'Top up wallet',
        );
        await state1.financeController.addCommitment(
          CommitmentModel(
            id: 'com-restart-1',
            title: 'Ethio Telecom Fiber',
            amountCents: 99000,
            dueDate: txDate.addDays(5),
          ),
        );
        await state1.financeController.addSavingsGoal(
          SavingsGoalModel(
            id: 'sav-restart-1',
            title: 'Backup Battery',
            targetCents: 500000,
            currentAllocatedCents: 120000,
          ),
        );

        // Tasks, Projects & Milestones + Schema v4 metadata
        final project = await state1.tasksController.createProject(
          title: 'Daywell Release Prep',
          description: 'Native SQLite validation',
        );
        expect(project, isNotNull);
        final milestone = await state1.tasksController.addMilestone(
          projectId: project!.id,
          title: 'Migration sign-off',
        );
        expect(milestone, isNotNull);
        await state1.tasksController.toggleMilestone(milestone!.id, true);

        final createdTask = await state1.tasksController.createTask(
          id: 'task-restart-1',
          title: 'Verify restart hydration',
          projectId: project.id,
          milestoneId: milestone.id,
          labels: ['stage2', 'sqlite'],
          isMyDay: true,
          recurrenceRule: 'weekly',
          subtasks: const [
            TaskSubtask(id: 'sub-1', title: 'Inspect tables', done: true),
          ],
        );
        expect(createdTask, isNotNull);
        await state1.tasksController.togglePin(createdTask!.id);

        // Notes + Schema v4 metadata + Amharic UTF-8
        final noteA = await state1.notesController.createNote(
          id: 'note-restart-1',
          title: 'የዕለት ማስታወሻ',
          content: 'ትኩረት ማድረግ ያለብኝ ዋና ዋና ጉዳዮች።',
          category: 'reflection',
          projectId: project.id,
          tags: ['journal', 'amharic'],
          isPinned: true,
          isFavorite: true,
        );
        expect(noteA.id, 'note-restart-1');

        final noteB = await state1.notesController.createNote(
          id: 'note-restart-2',
          title: 'Archived Note',
          content: 'Keep stored in archive',
        );
        await state1.notesController.toggleArchive(noteB.id);

        // Inbox capture (autoTriage: false keeps item queued cleanly)
        final inboxItem = await state1.inboxController.captureQuickThought(
          'Pick up coffee beans',
          category: 'idea',
          autoTriage: false,
        );
        expect(inboxItem, isNotNull);

        // Calendar event (with multi-day range via endDateIso)
        final event = await state1.calendarController.createEvent(
          title: 'Release Sync',
          dateIso: '2026-11-15',
          endDateIso: '2026-11-17',
          startTime: '10:00',
          endTime: '11:00',
          category: 'work',
          hasReminder: true,
          notes: 'Confirm CI passes',
        );
        expect(event, isNotNull);

        await state1.disposeAsync();
        expect(state1.isDisposed, isTrue);

        // --- SESSION 2 (COLD RESTART) ---
        final db2 = AppDatabase(NativeDatabase(dbFile));
        final state2 = AppStateManager(db: db2);
        await state2.initialize();

        expect(state2.isInitialized, isTrue);
        expect(state2.initializationError, isNull);

        // Verify zero duplicate starter categories on restart
        expect(state2.financeController.state.categories.length, 12);
        expect(state2.financeController.state.isSetupCompleted, isTrue);
        expect(state2.financeController.state.accounts.length, 2);
        expect(state2.financeController.state.transactions.length, 2);
        final expenseTx = state2.financeController.state.transactions
            .firstWhere((t) => t.id == 'tx-restart-1');
        expect(expenseTx.amountCents, 18500);
        expect(expenseTx.type, 'expense');
        final transferTx = state2.financeController.state.transactions
            .firstWhere((t) => t.type == 'transfer');
        expect(transferTx.amountCents, 10000);
        expect(transferTx.accountId, 'acc-cbe-user');
        expect(transferTx.destinationAccountId, 'acc-telebirr-user');
        // 2 opening balance entries + 1 recorded expense + 1 transfer = 4 entries, 8 postings
        expect(state2.financeController.state.journalEntries.length, 4);
        expect(state2.financeController.state.postings.length, 8);
        expect(state2.financeController.state.commitments.length, 1);
        expect(state2.financeController.state.savingsGoals.length, 1);
        final goal = state2.financeController.state.savingsGoals.single;
        expect(goal.currentAllocatedCents, 120000);

        // Verify Tasks, Projects, Milestones & v4 task metadata
        expect(state2.tasksController.state.projects.length, 1);
        expect(state2.tasksController.state.milestones.length, 1);
        expect(
          state2.tasksController.state.milestones.single.isCompleted,
          isTrue,
        );

        final restoredTask =
            state2.tasksController.state.findTaskById('task-restart-1');
        expect(restoredTask, isNotNull);
        expect(restoredTask!.isPinned, isTrue);
        expect(restoredTask.isMyDay, isTrue);
        expect(restoredTask.labels, ['stage2', 'sqlite']);
        expect(restoredTask.recurrenceRule, 'weekly');
        expect(restoredTask.subtasks.length, 1);
        expect(restoredTask.subtasks.first.title, 'Inspect tables');
        expect(restoredTask.subtasks.first.done, isTrue);

        // Verify Notes & v4 note metadata
        expect(state2.notesController.state.notes.length, 2);
        final restoredNoteA =
            state2.notesController.state.findById('note-restart-1');
        expect(restoredNoteA, isNotNull);
        expect(restoredNoteA!.title, 'የዕለት ማስታወሻ');
        expect(restoredNoteA.tags, ['journal', 'amharic']);
        expect(restoredNoteA.isPinned, isTrue);
        expect(restoredNoteA.isFavorite, isTrue);
        final restoredNoteB =
            state2.notesController.state.findById('note-restart-2');
        expect(restoredNoteB?.isArchived, isTrue);

        // Verify Inbox & Calendar
        expect(state2.inboxController.state.items.length, 1);
        expect(
          state2.inboxController.state.items.single.rawText,
          'Pick up coffee beans',
        );
        expect(state2.inboxController.state.items.single.isProcessed, isFalse);

        expect(state2.calendarController.state.events.length, 1);
        final restoredEvt = state2.calendarController.state.events.single;
        expect(restoredEvt.title, 'Release Sync');
        expect(restoredEvt.dateIso, '2026-11-15');
        expect(restoredEvt.endDateIso, '2026-11-17');
        expect(
          restoredEvt.occursOn(CalendarDate(year: 2026, month: 11, day: 16)),
          isTrue,
        );
        expect(restoredEvt.hasReminder, isTrue);

        await state2.disposeAsync();
      },
    );
  });

  group(
    'Application Lifecycle, Concurrency, Failure Recovery & Disposal (Part F)',
    () {
      test(
        '1. Concurrent initialize() calls share one startup run and stay '
        'idempotent',
        () async {
          final db = AppDatabase(NativeDatabase.memory());
          final state = AppStateManager(db: db);

          final f1 = state.initialize();
          final f2 = state.initialize();
          expect(identical(f1, f2), isTrue);

          await Future.wait([f1, f2]);
          expect(state.isInitialized, isTrue);
          expect(state.isInitializing, isFalse);
          expect(state.initializationError, isNull);

          await state.initialize();
          expect(state.financeController.state.categories.length, 11);

          await state.disposeAsync();
        },
      );

      test(
        '2. Startup failure sets initializationError cleanly and recovers on '
        'retry initialize()',
        () async {
          var shouldFailOpen = true;
          final db = AppDatabase(
            NativeDatabase.memory(
              setup: (_) {
                if (shouldFailOpen) {
                  throw StateError('Simulated SQLite open failure');
                }
              },
            ),
          );
          final state = AppStateManager(db: db);

          await state.initialize();
          expect(state.isInitialized, isFalse);
          expect(state.isInitializing, isFalse);
          expect(
            state.initializationError,
            contains('Simulated SQLite open failure'),
          );

          // Recover and retry cleanly
          shouldFailOpen = false;
          await state.initialize();
          expect(state.isInitialized, isTrue);
          expect(state.isInitializing, isFalse);
          expect(state.initializationError, isNull);
          expect(state.financeController.state.categories.length, 11);

          await state.disposeAsync();
        },
      );

      test(
        '3. Calling disposeAsync() mid-initialization waits cleanly before '
        'closing DB with zero post-dispose errors',
        () async {
          final gate = Completer<void>();
          final db = AppDatabase(
            LazyDatabase(() async {
              await gate.future;
              return NativeDatabase.memory();
            }),
          );
          final state = AppStateManager(db: db);

          final initFuture = state.initialize();
          final disposeFuture = state.disposeAsync();

          // Release database open while disposal is already requested
          gate.complete();

          await Future.wait([initFuture, disposeFuture]);

          expect(state.isDisposed, isTrue);
          expect(state.isInitialized, isFalse);
          // Repeated disposal remains idempotent and safe
          await state.disposeAsync();
        },
      );

      test(
        '4. Stream subscriptions cancel safely on disposeAsync() without late '
        'listener crashes',
        () async {
          final db = AppDatabase(NativeDatabase.memory());
          final state = AppStateManager(db: db);
          await state.initialize();

          await state.inboxController.captureQuickThought(
            'Active watcher check',
            category: 'idea',
            autoTriage: false,
          );
          expect(state.inboxController.unprocessedCount, 1);

          // Trigger async capture & disposeAsync immediately
          await state.disposeAsync();
          expect(state.isDisposed, isTrue);

          // No-op notifications after dispose must not throw
          state.notifyListeners();
          state.financeController.notifyListeners();
          state.tasksController.notifyListeners();
          state.notesController.notifyListeners();
          state.inboxController.notifyListeners();
          state.calendarController.notifyListeners();
        },
      );

      test(
        '5. SharedFoundationBridge.auditConsistency excludes non-ETB, '
        'unverified, and receivable asset accounts',
        () async {
          final db = AppDatabase(NativeDatabase.memory());
          final state = AppStateManager(db: db);
          await state.initialize();

          await state.financeController.addAccount(
            name: 'CBE Bank',
            type: AccountType.asset,
            subType: AccountSubType.bank,
            openingBalanceCents: 100000,
            openingBalanceDate: '2026-11-01',
          );
          await state.financeController.addAccount(
            name: 'Emergency Vault',
            type: AccountType.asset,
            subType: AccountSubType.savingsVault,
            openingBalanceCents: 50000,
            openingBalanceDate: '2026-11-01',
          );
          await db.into(db.accountsTable).insert(
                AccountsTableCompanion.insert(
                  id: 'acc-usd-audit',
                  name: 'USD Travel',
                  type: 'asset',
                  subType: const Value('bank'),
                  currencyCode: const Value('USD'),
                  openingBalanceCents: const Value(25000),
                  createdAt: DateTime.utc(2026, 11, 1),
                ),
              );
          await db.into(db.accountsTable).insert(
                AccountsTableCompanion.insert(
                  id: 'acc-unv-audit',
                  name: 'Legacy Unknown',
                  type: 'asset',
                  subType: const Value('cash'),
                  currencyCode: const Value(''),
                  openingBalanceCents: const Value(12000),
                  createdAt: DateTime.utc(2026, 11, 1),
                ),
              );
          await state.financeController.loadAll();

          final audit = SharedFoundationBridge.auditConsistency(state);
          expect(audit['isConsistent'], isTrue);
          expect(audit['activeAccountsCount'], 2);
          expect(audit['combinedBalanceCents'], 150000);
          expect(audit['computedCombinedCents'], 150000);
          expect(audit['currency'], 'ETB');

          await state.disposeAsync();
        },
      );
    },
  );
}
