import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/inbox/inbox_controller.dart';
import 'package:personal_management_app/application/projects/projects_controller.dart';
import 'package:personal_management_app/application/tasks/tasks_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/interfaces/platform_service_interfaces.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/inbox_repository.dart';
import 'package:personal_management_app/data/repositories/projects_repository.dart';
import 'package:personal_management_app/data/repositories/tasks_repository.dart';
import 'package:personal_management_app/ui/app_state.dart';
import 'package:personal_management_app/ui/screens/tasks_view.dart';
import 'package:personal_management_app/ui/widgets/quick_capture_dialog.dart';

import 'support/sqlite_test_helper.dart';

class _NoopNotificationService implements INotificationService {
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

void main() {
  configureSqliteForHostTests();

  group('Stage 1.5 — Shared Inbox & Quick Capture Integration (Flutter)', () {
    test(
      '1. InboxItemEntity.toTaskDraft() converts single-line, multi-line, >120-char, and idea captures losslessly',
      () {
        final single = InboxItemEntity(
          id: 'inb-1',
          rawText: '  Submit quarterly report  ',
          category: 'task',
        ).toTaskDraft();
        expect(single.sourceInboxId, 'inb-1');
        expect(single.title, 'Submit quarterly report');
        expect(single.description, '');
        expect(single.initialLabels, isEmpty);

        final multiIdea = InboxItemEntity(
          id: 'inb-2',
          rawText: '  Build offline sync\nAdd Inbox badge\nAdd undo snackbar  ',
          category: 'idea',
        ).toTaskDraft();
        expect(multiIdea.title, 'Build offline sync');
        expect(multiIdea.description, 'Add Inbox badge\nAdd undo snackbar');
        expect(multiIdea.initialLabels, ['idea']);

        const longRaw =
            'Audit all monthly recurring utility subscriptions across electricity, mobile internet, cloud storage, and office lease renewals before Friday';
        final longDraft = InboxItemEntity(
          id: 'inb-3',
          rawText: longRaw,
          category: 'task',
        ).toTaskDraft();
        expect(longDraft.title.endsWith('...'), isTrue);
        expect(longDraft.title.length, lessThanOrEqualTo(120));
        expect(longDraft.description, longRaw);
      },
    );

    test(
      '2. AppStateManager quick capture keeps task & idea captures in shared InboxItems without premature Task auto-creation',
      () async {
        final state = AppStateManager(
          databaseBuilder: () => AppDatabase(NativeDatabase.memory()),
          notificationService: _NoopNotificationService(),
        );
        await state.initialize();
        addTearDown(() => state.disposeAsync());

        final capturedTask = await state.inboxController.captureQuickThought(
          'Prepare project milestone review\nConfirm dates with team',
          category: 'task',
        );
        final capturedIdea = await state.inboxController.captureQuickThought(
          'Try Sunday evening weekly planning',
          category: 'idea',
        );

        expect(capturedTask, isNotNull);
        expect(capturedIdea, isNotNull);

        // Give async triage microtasks a chance to settle.
        await Future<void>.delayed(Duration.zero);

        // Tasks table must remain clean until the user organizes/converts the capture.
        expect(state.tasksController.state.tasks, isEmpty);
        expect(state.inboxController.unprocessedCount, 2);

        // Capturing a note saves to Notes AND marks the Inbox item processed (no duplicate active Inbox entry).
        await state.inboxController.captureQuickThought(
          'Remember key safe code',
          category: 'note',
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(state.notesController.state.notes.length, 1);
        expect(state.inboxController.unprocessedCount, 2);

        // Editing captured text/category and converting into Task preserves content and clears active Inbox queue.
        await state.inboxController.updateItemText(
          capturedIdea!.id,
          'Schedule Sunday evening weekly planning',
          category: 'task',
        );
        final edited = state.inboxController.unprocessedItems
            .firstWhere((i) => i.id == capturedIdea.id);
        expect(edited.rawText, 'Schedule Sunday evening weekly planning');
        expect(edited.category, 'task');

        final draft = edited.toTaskDraft();
        final created = await state.tasksController.createTask(
          title: draft.title,
          description: draft.description.isEmpty ? null : draft.description,
          priority: 'high',
          dueDate: CalendarDate.today().addDays(2),
        );
        expect(created, isNotNull);
        await state.inboxController.markProcessed(edited.id);

        expect(state.tasksController.state.tasks.length, 1);
        expect(state.inboxController.unprocessedCount, 1);
        expect(
          state.inboxController.unprocessedItems.map((i) => i.id).toList(),
          [capturedTask!.id],
        );
      },
    );

    testWidgets(
      '3. QuickCaptureDialog & TasksView Inbox triage: edit capture, mark processed, and convert capture to Task without duplicate active Inbox entry',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 1400));

        final fixture = await tester.runAsync(() async {
          final db = AppDatabase(NativeDatabase.memory());
          await db.ensureInitialized();
          final tasksCtrl =
              TasksController(repository: DriftTasksRepository(db));
          final projectsCtrl =
              ProjectsController(repository: DriftProjectsRepository(db));
          final inboxCtrl =
              InboxController(repository: DriftInboxRepository(db));

          await tasksCtrl.loadAll();
          await projectsCtrl.loadAll();
          await inboxCtrl.loadItems();

          // Seed two unprocessed captures (via controller, zero premature Tasks)
          await inboxCtrl.captureQuickThought(
            'Draft client proposal\nAttach Q4 timeline',
            category: 'task',
            autoTriage: false,
          );
          await inboxCtrl.captureQuickThought(
            'Old temporary thought',
            category: 'idea',
            autoTriage: false,
          );
          return (
            db: db,
            tasksCtrl: tasksCtrl,
            projectsCtrl: projectsCtrl,
            inboxCtrl: inboxCtrl,
          );
        });

        final db = fixture!.db;
        final tasksCtrl = fixture.tasksCtrl;
        final projectsCtrl = fixture.projectsCtrl;
        final inboxCtrl = fixture.inboxCtrl;

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 20));
          tasksCtrl.dispose();
          projectsCtrl.dispose();
          await tester.runAsync(() => inboxCtrl.disposeAsync());
          var closed = false;
          final closeFuture = db.close().whenComplete(() {
            closed = true;
          });
          final closeWatch = Stopwatch()..start();
          while (!closed && closeWatch.elapsed < const Duration(seconds: 10)) {
            await tester.pump(const Duration(milliseconds: 20));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
          }
          if (closed) {
            await closeFuture;
          } else {
            await tester.runAsync(
              () => closeFuture.timeout(const Duration(seconds: 5)),
            );
          }
          await tester.binding.setSurfaceSize(null);
        });

        Future<void> pumpUntil(
          bool Function() condition, {
          required String reason,
        }) async {
          final watch = Stopwatch()..start();
          while (!condition()) {
            if (watch.elapsed > const Duration(seconds: 10)) {
              fail(reason);
            }
            await tester.pump(const Duration(milliseconds: 20));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
          }
          await tester.pumpAndSettle();
        }

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: TasksView(
              controller: tasksCtrl,
              projectsController: projectsCtrl,
              inboxController: inboxCtrl,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Pending Quick Capture banner shows outside Inbox view
        expect(
          find.text('2 Quick Capture item(s) waiting in Inbox'),
          findsOneWidget,
        );
        expect(find.text('Inbox (2)'), findsOneWidget);

        // Tap Review action on banner to switch straight to Inbox view
        await tester.tap(find.text('Review'));
        await tester.pumpAndSettle();

        expect(find.text('Captured Inbox Items (2)'), findsOneWidget);
        expect(
          find.text('Draft client proposal\nAttach Q4 timeline'),
          findsOneWidget,
        );

        // Mark second capture processed -> leaves active queue cleanly
        final markButtons = find.text('Mark Processed');
        expect(markButtons, findsNWidgets(2));
        await tester.tap(markButtons.first);
        await pumpUntil(
          () => inboxCtrl.unprocessedCount == 1,
          reason: 'Mark Processed did not update inboxCtrl.',
        );
        expect(inboxCtrl.unprocessedCount, 1);

        // Convert remaining capture -> opens prefilled Task form & marks source Inbox item processed on save
        final openConvertButton = find.text('Convert to Task');
        await tester.ensureVisible(openConvertButton);
        await tester.tap(openConvertButton);
        await tester.pumpAndSettle();

        expect(find.text('Convert Inbox Item to Task'), findsOneWidget);
        final submitConvertButton = find.text('Convert to Task').last;
        await tester.ensureVisible(submitConvertButton);
        await tester.tap(submitConvertButton);
        await pumpUntil(
          () =>
              tasksCtrl.state.tasks.length == 1 &&
              inboxCtrl.unprocessedCount == 0,
          reason: 'Convert to Task did not persist new task and clear inbox.',
        );

        expect(tasksCtrl.state.tasks.length, 1);
        expect(tasksCtrl.state.tasks.first.title, 'Draft client proposal');
        expect(tasksCtrl.state.tasks.first.description, 'Attach Q4 timeline');
        expect(inboxCtrl.unprocessedCount, 0);
        expect(find.text('Captured Inbox Items (0)'), findsOneWidget);
        expect(
          find.text('No unprocessed Quick Capture items right now.'),
          findsOneWidget,
        );
        expect(find.text('Unassigned Tasks (1)'), findsOneWidget);
        expect(find.text('Draft client proposal'), findsOneWidget);

        // Verify QuickCaptureDialog still captures directly into shared InboxController
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: ctx,
                    builder: (_) => QuickCaptureDialog(controller: inboxCtrl),
                  ),
                  child: const Text('Open Capture'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open Capture'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField),
          'Captured via modal offline',
        );
        await tester.tap(find.text('Capture'));
        await pumpUntil(
          () => inboxCtrl.unprocessedCount == 1,
          reason: 'QuickCaptureDialog capture did not persist.',
        );

        expect(inboxCtrl.unprocessedCount, 1);
        expect(
          inboxCtrl.unprocessedItems.first.rawText,
          'Captured via modal offline',
        );
      },
    );

    test(
      '4. Architecture & UI guardrails: pure domain Inbox models and zero raw Color(0x...) in modified Flutter UI files',
      () {
        final inboxModelsFile = File('lib/domain/inbox/inbox_models.dart');
        final modelsSrc = inboxModelsFile.existsSync()
            ? inboxModelsFile.readAsStringSync()
            : File('flutter_app/lib/domain/inbox/inbox_models.dart')
                .readAsStringSync();
        expect(modelsSrc.contains('package:flutter/'), isFalse);
        expect(modelsSrc.contains('package:drift/'), isFalse);

        for (final rel in [
          'lib/ui/screens/tasks_view.dart',
          'lib/ui/screens/dashboard_view.dart',
          'lib/ui/widgets/quick_capture_dialog.dart',
        ]) {
          final f =
              File(rel).existsSync() ? File(rel) : File('flutter_app/$rel');
          final src = f.readAsStringSync();
          expect(
            RegExp(r'Color\(0x').hasMatch(src),
            isFalse,
            reason: '$rel must not contain raw Color(0x...) literals',
          );
        }
      },
    );
  });
}
