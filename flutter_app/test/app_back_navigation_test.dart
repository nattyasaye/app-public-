import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/interfaces/platform_service_interfaces.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/raw_database_recovery_exporter.dart';
import 'package:personal_management_app/data/repositories/notes_repository.dart';
import 'package:personal_management_app/domain/finance/double_entry_engine.dart';
import 'package:personal_management_app/main.dart';
import 'package:personal_management_app/ui/app_state.dart';
import 'package:personal_management_app/ui/screens/backup_view.dart';
import 'package:personal_management_app/ui/screens/calendar_view.dart';
import 'package:personal_management_app/ui/screens/finance/finance_composer_sheet.dart';
import 'package:personal_management_app/ui/screens/finance/finance_setup_wizard.dart';
import 'package:personal_management_app/ui/screens/finance_view.dart';
import 'package:personal_management_app/ui/screens/more_view.dart';
import 'package:personal_management_app/ui/screens/notes_view.dart';
import 'package:personal_management_app/ui/screens/projects/project_detail_screen.dart';
import 'package:personal_management_app/ui/screens/projects/project_form_sheet.dart';
import 'package:personal_management_app/ui/screens/tasks_view.dart';
import 'package:personal_management_app/ui/shell/daywell_shell_routes.dart';
import 'package:personal_management_app/ui/widgets/quick_capture_dialog.dart';
import 'package:personal_management_app/ui/widgets/shared_ui_widgets.dart';

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

class _ControllableNotesRepo implements INotesRepository {
  final Map<String, NoteEntity> store = <String, NoteEntity>{};
  bool failUpdates = false;

  void seed(NoteEntity note) => store[note.id] = note;

  @override
  Future<NoteEntity> createNote(NoteEntity note) async {
    store[note.id] = note;
    return note;
  }

  @override
  Future<NoteEntity> updateNote(NoteEntity note) async {
    if (failUpdates) {
      throw StateError('Simulated save failure');
    }
    store[note.id] = note;
    return note;
  }

  @override
  Future<void> deleteNote(String id) async {
    store.remove(id);
  }

  @override
  Future<NoteEntity?> getNoteById(String id) async => store[id];

  @override
  Future<List<NoteEntity>> getNotes({
    String? category,
    String? projectId,
    String? goalId,
    String? linkedModule,
    String? linkedId,
    bool includeArchived = false,
    bool includeTrashed = false,
  }) async {
    return store.values.where((n) {
      if (category != null &&
          category != 'all' &&
          n.category != NoteEntity.normalizeCategory(category)) {
        return false;
      }
      if (!includeArchived && n.isArchived) return false;
      if (!includeTrashed && n.isTrashed) return false;
      return true;
    }).toList();
  }

  @override
  Future<List<NoteEntity>> getNotesByLink({
    required String linkedModule,
    required String linkedId,
    bool includeArchived = true,
    bool includeTrashed = false,
  }) async {
    return store.values
        .where(
          (n) =>
              n.linkedModule == linkedModule &&
              n.linkedId == linkedId &&
              (includeArchived || !n.isArchived) &&
              (includeTrashed || !n.isTrashed),
        )
        .toList();
  }

  @override
  Future<List<NoteEntity>> searchNotes(String query) async {
    return store.values
        .where((n) => !n.isTrashed && n.matchesQuery(query))
        .toList();
  }

  @override
  Future<int> clearLinksForTarget({
    required String linkedModule,
    required String linkedId,
  }) async {
    return 0;
  }
}

void main() {
  configureSqliteForHostTests();

  Future<void> settle(WidgetTester tester) {
    return tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }

  Future<({AppStateManager state, Directory tempDir})> createState(
    WidgetTester tester,
  ) async {
    final result = await tester.runAsync(() async {
      final tempDir = Directory.systemTemp.createTempSync('daywell_back_');
      final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
      final supportDir = Directory(p.join(tempDir.path, 'support'))
        ..createSync();
      final db = AppDatabase(NativeDatabase.memory());
      final state = AppStateManager(
        db: db,
        recoveryExporter: RawDatabaseRecoveryExporter(
          documentsDirProvider: () async => docsDir,
          supportDirProvider: () async => supportDir,
        ),
        notificationService: _NoOpNotificationService(),
      );
      await db.ensureInitialized().timeout(const Duration(seconds: 20));
      await state.initialize().timeout(const Duration(seconds: 20));
      return (state: state, tempDir: tempDir);
    });
    final created = result!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      if (!created.state.isDisposed) {
        final state = created.state;
        await tester.runAsync(
          () => state.disposeAsync().timeout(const Duration(seconds: 10)),
        );
      }
      if (created.tempDir.existsSync()) {
        created.tempDir.deleteSync(recursive: true);
      }
    });
    return created;
  }

  group('Stage 4 — App-Wide Android Back Navigation Tests', () {
    testWidgets(
        'Enforces priority order across overlays, nested screens, internal tabs/filters, main-tab history, and Today exit',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 840));
      addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

      final created = await createState(tester);
      final state = created.state;
      await tester.runAsync(() async {
        await state.projectsController
            .createProject(title: 'Back Test Project');
        await state.tasksController.loadAll();
        await state.notesController.createNote(
          title: 'Archived Sample Note',
          content: 'Archived body',
        );
      });
      final createdProject = state.projectsController.state.projects.first;
      final archivedCandidate = state.notesController.state.notes.first;
      await tester.runAsync(() async {
        await state.notesController.toggleArchive(archivedCandidate.id);
      });

      var now = DateTime.utc(2026, 4, 15, 9, 0, 0);
      var exitCalls = 0;
      final shell = DaywellShellController(clock: () => now);
      addTearDown(shell.dispose);

      await tester.pumpWidget(
        DaywellApp(
          stateManager: state,
          shellController: shell,
          onExitApp: () async => exitCalls++,
        ),
      );
      await settle(tester);

      // 1. Move Today -> Tasks -> subtab Projects -> ProjectDetailScreen -> ProjectFormSheet
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Tasks'),
        ),
      );
      await settle(tester);
      expect(shell.currentTab, DaywellTabId.tasks);

      await tester.tap(
        find.descendant(
          of: find.byType(TabBar),
          matching: find.text('Projects'),
        ),
      );
      await settle(tester);

      await tester.tap(find.text('Back Test Project'));
      await settle(tester);
      expect(find.byType(ProjectDetailScreen), findsOneWidget);

      // Open Edit Project sheet (clean) -> system back dismisses overlay first (Priority 1)
      await tester.tap(find.byTooltip('Edit project'));
      await settle(tester);
      expect(find.byType(ProjectFormSheet), findsOneWidget);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(ProjectFormSheet), findsNothing);
      expect(find.byType(ProjectDetailScreen), findsOneWidget);

      // System back pops ProjectDetailScreen to Tasks > Projects (Priority 2)
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(ProjectDetailScreen), findsNothing);
      expect(find.byType(TasksView), findsOneWidget);
      expect(exitCalls, 0);

      // System back returns from Projects subtab -> Tasks subtab (Priority 3)
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(shell.currentTab, DaywellTabId.tasks);
      expect(
        find.descendant(
          of: find.byType(FloatingActionButton),
          matching: find.text('Add Task'),
        ),
        findsOneWidget,
      );

      // Open filter panel -> system back collapses filter panel before leaving Tasks
      await tester.tap(find.byTooltip('Toggle Filters'));
      await settle(tester);
      expect(find.text('Status'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Status'), findsNothing);
      expect(shell.currentTab, DaywellTabId.tasks);

      // Switch view filter Today -> Upcoming -> system back restores Today view filter
      await tester.tap(find.text('Upcoming'));
      await settle(tester);
      expect(state.tasksController.state.viewFilter, 'upcoming');

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(state.tasksController.state.viewFilter, 'today');
      expect(shell.currentTab, DaywellTabId.tasks);

      // 2. Visit Calendar -> change viewMode Month -> Day -> Agenda and back unwinds step-by-step
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Calendar'),
        ),
      );
      await settle(tester);
      expect(find.byType(CalendarView), findsOneWidget);

      await tester.tap(find.text('Day'));
      await settle(tester);
      await tester.tap(find.text('Agenda'));
      await settle(tester);
      expect(find.text('Search upcoming events & tasks...'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Search upcoming events & tasks...'), findsNothing);
      expect(shell.currentTab, DaywellTabId.calendar);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('MON'), findsOneWidget);
      expect(shell.currentTab, DaywellTabId.calendar);

      // 3. Visit More -> Settings Appearance dialog -> Back dismisses dialog -> BackupView -> Back unwinds
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('More'),
        ),
      );
      await settle(tester);

      final moreScrollable = find
          .descendant(
            of: find.byType(MoreView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Appearance'),
        200.0,
        scrollable: moreScrollable,
      );
      await tester.drag(moreScrollable, const Offset(0, -160));
      await settle(tester);
      await tester.tap(find.text('Appearance'));
      await settle(tester);
      expect(find.byType(DaywellRadioTile<ThemeMode>), findsNWidgets(3));

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(DaywellRadioTile<ThemeMode>), findsNothing);
      expect(shell.currentTab, DaywellTabId.more);

      await tester.scrollUntilVisible(
        find.text('Sync & backup'),
        200.0,
        scrollable: moreScrollable,
      );
      await tester.drag(moreScrollable, const Offset(0, -160));
      await settle(tester);
      await tester.tap(find.text('Sync & backup'));
      await settle(tester);
      expect(find.byType(BackupView), findsOneWidget);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(BackupView), findsNothing);
      expect(shell.currentTab, DaywellTabId.more);

      // 4. Unwind main-tab history: More -> Calendar -> Tasks -> Today (never exiting early)
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(shell.currentTab, DaywellTabId.calendar);
      expect(exitCalls, 0);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(shell.currentTab, DaywellTabId.tasks);
      expect(exitCalls, 0);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(shell.currentTab, DaywellTabId.today);
      expect(exitCalls, 0);

      // 5. At Today root: 1st back prompts, >2s resets, 2nd back within 2s exits
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Press back again to exit'), findsOneWidget);
      expect(exitCalls, 0);

      now = now.add(const Duration(seconds: 3));
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(exitCalls, 0);

      now = now.add(const Duration(seconds: 1));
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(exitCalls, 1);

      expect(createdProject.id, isNotEmpty);
    });

    testWidgets(
        'Finance handles setup wizard step-back and internal tabs before returning to Today',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 840));
      addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

      final created = await createState(tester);
      final state = created.state;
      var exitCalls = 0;
      final shell = DaywellShellController();
      addTearDown(shell.dispose);

      await tester.pumpWidget(
        DaywellApp(
          stateManager: state,
          shellController: shell,
          onExitApp: () async => exitCalls++,
        ),
      );
      await settle(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Finance'),
        ),
      );
      await settle(tester);
      expect(find.byType(FinanceView), findsOneWidget);
      expect(find.byType(FinanceSetupWizard), findsOneWidget);
      expect(find.text('Step 1 of 3'), findsOneWidget);

      // Advance wizard Step 1 -> Step 2, then press system back -> returns to Step 1
      await tester.ensureVisible(find.text('Continue'));
      await settle(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(find.text('Step 2 of 3'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(shell.currentTab, DaywellTabId.finance);

      // Complete wizard to unlock internal tabs Overview / Transactions / Plan / Reports
      await tester.ensureVisible(find.text('Skip Setup'));
      await settle(tester);
      await tester.tap(find.text('Skip Setup'));
      final setupWatch = Stopwatch()..start();
      while (!state.financeController.state.isSetupCompleted &&
          setupWatch.elapsed < const Duration(seconds: 10)) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      await settle(tester);
      final transactionsTab = find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Transactions'),
      );
      expect(transactionsTab, findsOneWidget);

      await tester.ensureVisible(transactionsTab);
      await settle(tester);
      await tester.tap(transactionsTab);
      await settle(tester);
      final reportsTab = find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Reports'),
      );
      await tester.ensureVisible(reportsTab);
      await settle(tester);
      await tester.tap(reportsTab);
      await settle(tester);

      // Back steps Reports -> Transactions -> Overview -> Today
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(shell.currentTab, DaywellTabId.finance);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(shell.currentTab, DaywellTabId.finance);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(shell.currentTab, DaywellTabId.today);
      expect(exitCalls, 0);
    });

    testWidgets(
        'Protects unsaved edits with Save/Discard/Cancel across QuickCaptureDialog, Task modal, Calendar modal, and FinanceComposerSheet without prompting when clean',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 840));
      addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

      final created = await createState(tester);
      final state = created.state;
      final shell = DaywellShellController();
      addTearDown(shell.dispose);

      // Complete Finance setup so FinanceComposerSheet can open cleanly
      await tester.runAsync(() async {
        await state.financeController.completeSetup(<AccountModel>[
          AccountModel(
            id: 'acc-cash-back-test',
            name: 'Cash Wallet',
            type: AccountType.asset,
            subType: AccountSubType.cash,
            openingBalanceCents: 100000,
            openingBalanceDate: CalendarDate.today().toIsoString(),
          ),
        ]);
      });

      await tester.pumpWidget(
        DaywellApp(
          stateManager: state,
          shellController: shell,
        ),
      );
      await settle(tester);

      // A. QuickCaptureDialog: clean closes immediately; dirty prompts Cancel -> stay, Save -> persists
      await tester.tap(find.byTooltip('1-Tap Quick Capture'));
      await settle(tester);
      expect(find.byType(QuickCaptureDialog), findsOneWidget);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(QuickCaptureDialog), findsNothing);
      expect(find.byType(DaywellUnsavedChangesDialog), findsNothing);

      await tester.tap(find.byTooltip('1-Tap Quick Capture'));
      await settle(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(QuickCaptureDialog),
          matching: find.byType(TextField),
        ),
        'Unsaved thought',
      );
      await settle(tester);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(DaywellUnsavedChangesDialog), findsOneWidget);

      // Cancel stays on dialog
      await tester.tap(
        find.descendant(
          of: find.byType(DaywellUnsavedChangesDialog),
          matching: find.text('Cancel'),
        ),
      );
      await settle(tester);
      expect(find.byType(QuickCaptureDialog), findsOneWidget);

      // Second back -> Capture saves to Inbox
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(DaywellUnsavedChangesDialog),
          matching: find.text('Capture'),
        ),
      );
      final saveWatch = Stopwatch()..start();
      while (find.byType(QuickCaptureDialog).evaluate().isNotEmpty &&
          saveWatch.elapsed < const Duration(seconds: 10)) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      await settle(tester);
      expect(find.byType(QuickCaptureDialog), findsNothing);
      expect(
        state.inboxController.state.items.any(
          (i) => i.rawText == 'Unsaved thought',
        ),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);

      // B. Task Form Modal: clean dismisses; dirty prompts Discard
      shell.selectTab(DaywellTabId.tasks);
      await settle(tester);
      final addTaskFab = find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.text('Add Task'),
      );
      await tester.tap(addTaskFab);
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(DaywellUnsavedChangesDialog), findsNothing);

      await tester.tap(addTaskFab);
      await settle(tester);
      await tester.enterText(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(TextField),
            )
            .first,
        'Draft Task Name',
      );
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(DaywellUnsavedChangesDialog), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(DaywellUnsavedChangesDialog),
          matching: find.text('Discard'),
        ),
      );
      await settle(tester);
      expect(
        state.tasksController.state.tasks.any(
          (t) => t.title == 'Draft Task Name',
        ),
        isFalse,
      );

      // C. Calendar Event Modal: dirty prompts Discard
      shell.selectTab(DaywellTabId.calendar);
      await settle(tester);
      await tester.tap(find.byTooltip('Add Event'));
      await settle(tester);
      await tester.enterText(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(TextField),
            )
            .first,
        'Doctor Visit',
      );
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(DaywellUnsavedChangesDialog), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(DaywellUnsavedChangesDialog),
          matching: find.text('Discard'),
        ),
      );
      await settle(tester);
      expect(
        state.calendarController.state.events.any(
          (e) => e.title == 'Doctor Visit',
        ),
        isFalse,
      );

      // D. FinanceComposerSheet: clean closes immediately; dirty prompts Discard
      shell.selectTab(DaywellTabId.finance);
      await settle(tester);
      await tester.tap(find.text('+ Record'));
      await settle(tester);
      expect(find.byType(FinanceComposerSheet), findsOneWidget);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(FinanceComposerSheet), findsNothing);

      await tester.tap(find.text('+ Record'));
      await settle(tester);
      await tester.enterText(
        find
            .descendant(
              of: find.byType(FinanceComposerSheet),
              matching: find.byType(TextField),
            )
            .first,
        '250',
      );
      await settle(tester);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(DaywellUnsavedChangesDialog), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(DaywellUnsavedChangesDialog),
          matching: find.text('Discard'),
        ),
      );
      await settle(tester);
      expect(find.byType(FinanceComposerSheet), findsNothing);
    });

    testWidgets(
        'Notes split-view clears detail pane cleanly on back, unwinds section filters, and offers Retry Save / Discard / Cancel when autosave fails',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 760));
      addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

      final notesRepo = _ControllableNotesRepo();
      notesRepo.seed(
        NoteEntity(
          id: 'note-split-1',
          title: 'Split View Architecture',
          content: 'Original note content',
          category: 'reference',
        ),
      );
      final notesController = NotesController(repository: notesRepo);
      addTearDown(notesController.dispose);
      await notesController.loadNotes();

      final shell = DaywellShellController(initialTab: DaywellTabId.notes);
      addTearDown(shell.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: DaywellTheme.light,
          home: PopScope<Object?>(
            canPop: false,
            onPopInvokedWithResult: (bool didPop, Object? _) {
              if (!didPop) {
                unawaited(shell.handleSystemBack());
              }
            },
            child: NotesView(
              controller: notesController,
              shellController: shell,
            ),
          ),
        ),
      );
      await settle(tester);

      // Select a note in wide split-view
      await tester.tap(find.text('Split View Architecture'));
      await settle(tester);
      expect(find.text('Select a note to read or edit'), findsNothing);

      // Clean back clears split-view selection before changing section or tab
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Select a note to read or edit'), findsOneWidget);
      expect(shell.currentTab, DaywellTabId.notes);

      // Switch section filter to Archive, back restores All Notes before leaving tab
      await tester.ensureVisible(find.text('Archive'));
      await settle(tester);
      await tester.tap(find.text('Archive'));
      await settle(tester);
      expect(notesController.state.sectionFilter, 'archive');

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(notesController.state.sectionFilter, 'active');
      expect(shell.currentTab, DaywellTabId.notes);

      // Open note, make pending edit while update fails -> shows Retry Save / Discard / Cancel
      await tester.tap(find.text('Split View Architecture'));
      await settle(tester);

      notesRepo.failUpdates = true;
      await tester.enterText(
        find.byType(TextField).last,
        'Unsaved split-view edit',
      );
      await tester.pump();

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(DaywellUnsavedChangesDialog), findsOneWidget);
      expect(find.text('Retry Save'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Cancel stays inside note detail pane
      await tester.tap(
        find.descendant(
          of: find.byType(DaywellUnsavedChangesDialog),
          matching: find.text('Cancel'),
        ),
      );
      await settle(tester);
      expect(find.text('Unsaved split-view edit'), findsOneWidget);

      // Back -> Discard closes split-view cleanly without saving failed edit
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(DaywellUnsavedChangesDialog),
          matching: find.text('Discard'),
        ),
      );
      await settle(tester);
      expect(find.text('Select a note to read or edit'), findsOneWidget);
      expect(
        notesRepo.store['note-split-1']?.content,
        'Original note content',
      );

      // Next back unwinds Notes -> Today root
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(shell.currentTab, DaywellTabId.today);
    });
  });
}
