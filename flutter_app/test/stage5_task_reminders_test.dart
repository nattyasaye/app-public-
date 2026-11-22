import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/tasks/tasks_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/interfaces/platform_service_interfaces.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/tasks_repository.dart';
import 'package:personal_management_app/domain/tasks/task_models.dart';
import 'package:personal_management_app/domain/tasks/task_reminder_engine.dart';
import 'package:personal_management_app/services/notifications/local_notification_service.dart';

import 'support/sqlite_test_helper.dart';

class _FakeNotificationService implements INotificationService {
  int initializeCalls = 0;
  int permissionRequests = 0;
  int cancelAllCalls = 0;
  bool permissionResult = true;

  final List<
      ({
        String id,
        String title,
        String body,
        DateTime scheduledDateUtc,
        String? payload,
      })> scheduledCalls = [];
  final List<String> cancelledIds = [];

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<bool> requestPermissions() async {
    permissionRequests += 1;
    return permissionResult;
  }

  @override
  Future<void> scheduleReminder({
    required String id,
    required String title,
    required String body,
    required DateTime scheduledDateUtc,
    String? payload,
  }) async {
    scheduledCalls.add((
      id: id,
      title: title,
      body: body,
      scheduledDateUtc: scheduledDateUtc.toUtc(),
      payload: payload,
    ));
  }

  @override
  Future<void> cancelReminder(String id) async {
    cancelledIds.add(id);
  }

  @override
  Future<void> cancelAllReminders() async {
    cancelAllCalls += 1;
  }
}

void main() {
  configureSqliteForHostTests();

  group(
      'Stage 5 — Task Reminders and Notifications (Flutter Domain, Controller & Service)',
      () {
    Future<
        ({
          AppDatabase db,
          DriftTasksRepository repo,
          TasksController controller,
          _FakeNotificationService notifications,
        })> createHarness() async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.ensureInitialized();
      addTearDown(db.close);

      final repo = DriftTasksRepository(db);
      final notifications = _FakeNotificationService();
      final controller = TasksController(
        repository: repo,
        notificationService: notifications,
      );
      addTearDown(controller.dispose);
      await controller.loadAll();

      return (
        db: db,
        repo: repo,
        controller: controller,
        notifications: notifications,
      );
    }

    test(
      '1. TaskReminderEngine resolves scheduled/due anchors, presets, Ethiopia UTC+3 offsets, and lifecycle reconciliation cleanly',
      () {
        final task = TaskEntity(
          id: 'eng-1',
          title: 'Submit audit packet',
          scheduledDate: const CalendarDate(year: 2026, month: 12, day: 10),
          scheduledTime: '14:00',
          dueDate: const CalendarDate(year: 2026, month: 12, day: 12),
        );

        final anchor = TaskReminderEngine.resolveAnchor(task);
        expect(anchor, isNotNull);
        expect(anchor!.source, 'scheduled');
        expect(anchor.hasExplicitTime, isTrue);
        // 14:00 EAT == 11:00 UTC
        expect(anchor.utcInstant, DateTime.utc(2026, 12, 10, 11, 0));

        final dueOnly = TaskEntity(
          id: 'eng-due',
          title: 'Pay utility bill',
          dueDate: const CalendarDate(year: 2026, month: 12, day: 15),
        );
        final dueAnchor = TaskReminderEngine.resolveAnchor(dueOnly);
        expect(dueAnchor, isNotNull);
        expect(dueAnchor!.source, 'due');
        expect(dueAnchor.hasExplicitTime, isFalse);
        // Default 09:00 EAT == 06:00 UTC
        expect(dueAnchor.utcInstant, DateTime.utc(2026, 12, 15, 6, 0));

        final oneHourBefore = TaskReminderEngine.computeTriggerFromPreset(
          task: task,
          preset: TaskReminderPreset.oneHourBefore,
        );
        expect(oneHourBefore, DateTime.utc(2026, 12, 10, 10, 0));
        expect(
          TaskReminderEngine.inferPreset(task, oneHourBefore),
          TaskReminderPreset.oneHourBefore,
        );

        final reminder = TaskReminderEngine.buildReminder(
          task: task,
          triggerTimeUtc: oneHourBefore,
          nowUtc: DateTime.utc(2026, 12, 1, 6, 0),
        );
        expect(reminder.id, 'rem-task-eng-1');
        expect(reminder.channelId, TaskReminderEngine.taskReminderChannelId);
        expect(reminder.isActive, isTrue);

        // Date/time shift updates relative trigger automatically
        final shiftedTask = task.copyWith(
          scheduledDate: const CalendarDate(year: 2026, month: 12, day: 11),
          scheduledTime: '16:00',
        );
        final shiftedReminder = TaskReminderEngine.reconcileForUpdatedTask(
          previousTask: task,
          nextTask: shiftedTask,
          existingReminder: reminder,
          nowUtc: DateTime.utc(2026, 12, 1, 6, 0),
        );
        expect(shiftedReminder, isNotNull);
        expect(
          shiftedReminder!.triggerTimeUtc,
          DateTime.utc(2026, 12, 11, 12, 0), // 15:00 EAT == 12:00 UTC
        );

        // Completing pauses active reminder; reopening before trigger re-arms
        final completed = shiftedTask.copyWith(status: 'completed');
        final paused = TaskReminderEngine.reconcileForUpdatedTask(
          previousTask: shiftedTask,
          nextTask: completed,
          existingReminder: shiftedReminder,
          nowUtc: DateTime.utc(2026, 12, 1, 6, 0),
        );
        expect(paused!.isActive, isFalse);

        final reopened = completed.copyWith(status: 'not_started');
        final rearmed = TaskReminderEngine.reconcileForUpdatedTask(
          previousTask: completed,
          nextTask: reopened,
          existingReminder: paused,
          nowUtc: DateTime.utc(2026, 12, 1, 6, 0),
        );
        expect(rearmed!.isActive, isTrue);
      },
    );

    test(
      '2. TasksController schedules on shared INotificationService, carries over recurring reminders cleanly, and restores on Undo without duplicates',
      () async {
        final h = await createHarness();
        final futureBase =
            EthiopiaClock.nowUtc().toUtc().add(const Duration(days: 5));
        final schedDate = CalendarDate.fromUtcInstantInEthiopia(futureBase);
        final triggerUtc = LocalDateTime(
          date: schedDate,
          hour: 10,
          minute: 0,
        ).toUtcInstant();

        final created = await h.controller.createTask(
          id: 'task-rem-1',
          title: 'Prepare monthly close',
          scheduledDate: schedDate,
          scheduledTime: '10:30',
          dueDate: schedDate,
          recurrenceRule: 'weekly',
          recurrenceConfig: const TaskRecurrenceConfig(
            frequency: 'weekly',
            interval: 1,
            repeatFrom: 'due_date',
          ),
          reminderTriggerUtc: triggerUtc,
          requestReminderPermission: true,
        );

        expect(created, isNotNull);
        expect(h.notifications.permissionRequests, 1);
        expect(h.controller.state.activeReminderCount, 1);
        expect(
          h.notifications.scheduledCalls.any(
            (c) =>
                c.id == 'rem-task-task-rem-1' &&
                c.scheduledDateUtc == triggerUtc,
          ),
          isTrue,
        );

        final parentReminderBeforeComplete =
            h.controller.state.findReminderForTask(created!.id);
        expect(parentReminderBeforeComplete, isNotNull);

        // Complete recurring task -> parent reminder cancelled & paused, next occurrence gets carried-over active reminder
        final recResult =
            await h.controller.toggleTaskWithRecurrence(created.id);
        expect(recResult.generatedNextTask, isNotNull);
        final nextTask = recResult.generatedNextTask!;

        expect(
          h.notifications.cancelledIds.contains('rem-task-task-rem-1'),
          isTrue,
        );
        final completedParentRem =
            h.controller.state.findReminderForTask(created.id);
        expect(completedParentRem?.isActive, isFalse);

        final nextTaskRem = h.controller.state.findReminderForTask(nextTask.id);
        expect(nextTaskRem, isNotNull);
        expect(nextTaskRem!.isActive, isTrue);
        expect(
          h.notifications.scheduledCalls.any((c) => c.id == nextTaskRem.id),
          isTrue,
        );

        // Undo completion restores parent active reminder and removes+cancels spawned occurrence reminder
        await h.controller.undoGeneratedRecurrenceCompletion(
          previousTask: created,
          generatedNextTaskId: nextTask.id,
          previousReminder: parentReminderBeforeComplete,
        );
        expect(h.controller.state.findTaskById(nextTask.id), isNull);
        expect(
          h.notifications.cancelledIds.contains(nextTaskRem.id),
          isTrue,
        );
        expect(
          h.controller.state.findReminderForTask(created.id)?.isActive,
          isTrue,
        );

        // Archive cancels notification; delete removes & restore recovers reminder
        await h.controller.archiveTask(created.id);
        expect(
          h.controller.state.findReminderForTask(created.id)?.isActive,
          isFalse,
        );
        await h.controller.restoreTask(created.id);
        expect(
          h.controller.state.findReminderForTask(created.id)?.isActive,
          isTrue,
        );

        final snapRem = h.controller.state.findReminderForTask(created.id);
        await h.controller.deleteTask(created.id);
        expect(h.controller.state.findReminderForTask(created.id), isNull);

        await h.controller.restoreDeletedTask(
          created,
          restoreReminder: snapRem,
        );
        expect(
          h.controller.state.findReminderForTask(created.id)?.isActive,
          isTrue,
        );
      },
    );

    test(
      '3. Finance commitment reminders in Reminders table remain isolated and deterministic notification IDs stay stable',
      () async {
        final h = await createHarness();
        await h.db.into(h.db.reminders).insert(
              RemindersCompanion.insert(
                id: 'fin-commit-1',
                targetId: 'commit-1',
                targetType: 'commitment',
                title: const Value('Rent payment'),
                channelId: const Value('commitment_reminders_channel'),
                triggerTimeUtc: DateTime.utc(2026, 12, 20, 6, 0),
                createdAt: DateTime.utc(2026, 11, 20, 6, 0),
              ),
            );

        final t = await h.controller.createTask(
          id: 'task-iso-1',
          title: 'Send invoice',
          reminderTriggerUtc:
              EthiopiaClock.nowUtc().toUtc().add(const Duration(days: 2)),
        );
        expect(t, isNotNull);
        await h.controller.removeTaskReminder(t!.id);

        final allRows = await h.db.select(h.db.reminders).get();
        expect(allRows.any((r) => r.id == 'fin-commit-1'), isTrue);
        expect(allRows.any((r) => r.targetId == 'task-iso-1'), isFalse);

        final idA = LocalNotificationService.deterministicNotificationId(
          'rem-task-abc',
        );
        final idB = LocalNotificationService.deterministicNotificationId(
          'rem-task-abc',
        );
        final idOther = LocalNotificationService.deterministicNotificationId(
          'rem-task-xyz',
        );
        expect(idA, idB);
        expect(idA, greaterThan(0));
        expect(idA, isNot(idOther));
      },
    );
  });
}
