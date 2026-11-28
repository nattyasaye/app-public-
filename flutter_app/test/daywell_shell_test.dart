import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_management_app/application/calendar/calendar_controller.dart';
import 'package:personal_management_app/core/interfaces/platform_service_interfaces.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/raw_database_recovery_exporter.dart';
import 'package:personal_management_app/domain/calendar/calendar_contracts.dart';
import 'package:personal_management_app/domain/calendar/calendar_models.dart';
import 'package:personal_management_app/main.dart';
import 'package:personal_management_app/ui/app_state.dart';
import 'package:personal_management_app/ui/screens/backup_view.dart';
import 'package:personal_management_app/ui/screens/calendar_view.dart';
import 'package:personal_management_app/ui/screens/dashboard_view.dart';
import 'package:personal_management_app/ui/screens/finance_view.dart';
import 'package:personal_management_app/ui/screens/more_view.dart';
import 'package:personal_management_app/ui/screens/notes_view.dart';
import 'package:personal_management_app/ui/screens/tasks_view.dart';
import 'package:personal_management_app/ui/shell/calendar_placeholder_view.dart';
import 'package:personal_management_app/ui/shell/daywell_app_shell.dart';
import 'package:personal_management_app/ui/shell/daywell_shell_routes.dart';
import 'package:personal_management_app/ui/shell/daywell_shell_status_view.dart';
import 'package:personal_management_app/ui/shell/daywell_theme_controller.dart';
import 'package:personal_management_app/ui/widgets/quick_capture_dialog.dart';
import 'package:personal_management_app/ui/widgets/shared_ui_widgets.dart';

import 'support/sqlite_test_helper.dart';

const MethodChannel _kQuickCaptureChannel =
    MethodChannel('com.example.personalmanagement/quick_capture');

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

class _ToggleableFailDatabase extends AppDatabase {
  bool shouldFail;
  Completer<void>? gate;

  _ToggleableFailDatabase({
    this.shouldFail = false,
    this.gate,
  }) : super(NativeDatabase.memory());

  @override
  Future<void> ensureInitialized() async {
    if (gate != null && !gate!.isCompleted) {
      await gate!.future;
    }
    if (shouldFail) {
      throw StateError('Simulated local database failure');
    }
    await super.ensureInitialized();
  }
}

class _FakeCalendarRepository implements ICalendarRepository {
  Completer<List<CalendarEventEntity>>? pendingLoad;
  bool shouldThrow = false;
  List<CalendarEventEntity> eventsToReturn = const <CalendarEventEntity>[];
  int loadCalls = 0;

  _FakeCalendarRepository({this.pendingLoad});

  @override
  Future<List<CalendarEventEntity>> getEvents({
    String? dateIso,
    String? category,
  }) async {
    loadCalls++;
    if (pendingLoad != null) {
      return pendingLoad!.future;
    }
    if (shouldThrow) {
      throw StateError('Simulated calendar read failure');
    }
    return eventsToReturn;
  }

  @override
  Future<CalendarEventEntity?> getEventById(String id) async => null;

  @override
  Future<CalendarEventEntity> createEvent(CalendarEventEntity event) async =>
      event;

  @override
  Future<CalendarEventEntity> updateEvent(CalendarEventEntity event) async =>
      event;

  @override
  Future<void> deleteEvent(String id) async {}
}

void main() {
  configureSqliteForHostTests();

  Future<void> dispatchQuickCapturePlatformCall(
    WidgetTester tester,
    String method, [
    dynamic arguments,
  ]) async {
    final ByteData encoded = const StandardMethodCodec()
        .encodeMethodCall(MethodCall(method, arguments));
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      _kQuickCaptureChannel.name,
      encoded,
      (ByteData? _) {},
    );
  }

  Future<void> waitForCondition(
    WidgetTester tester,
    bool Function() predicate, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final stopwatch = Stopwatch()..start();
    while (!predicate()) {
      if (stopwatch.elapsed > timeout) {
        throw TimeoutException(
          'Timed out after ${timeout.inMilliseconds}ms waiting for condition',
        );
      }
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
  }

  Future<void> settleShell(WidgetTester tester) {
    return tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }

  Future<void> disposeTestState(
    WidgetTester tester,
    AppStateManager state, {
    Directory? tempDir,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    try {
      if (!state.isDisposed) {
        await tester.runAsync(
          () => state.disposeAsync().timeout(const Duration(seconds: 10)),
        );
      }
    } finally {
      if (tempDir != null && tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  }

  Future<({AppStateManager state, Directory tempDir})> createIsolatedState(
    WidgetTester tester, {
    AppDatabase? db,
    bool initialize = true,
  }) async {
    final result = await tester.runAsync(() async {
      final tempDir = Directory.systemTemp.createTempSync('daywell_shell_');
      final docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
      final supportDir = Directory(p.join(tempDir.path, 'support'))
        ..createSync();
      final targetDb = db ?? AppDatabase(NativeDatabase.memory());
      final state = AppStateManager(
        db: targetDb,
        recoveryExporter: RawDatabaseRecoveryExporter(
          documentsDirProvider: () async => docsDir,
          supportDirProvider: () async => supportDir,
        ),
        notificationService: _NoOpNotificationService(),
      );
      if (!initialize) {
        return (state: state, tempDir: tempDir);
      }
      try {
        final ensureFuture = targetDb.ensureInitialized();
        await ensureFuture.timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException(
            'db.ensureInitialized() timed out after 20s',
          ),
        );
        final initFuture = state.initialize();
        await initFuture.timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException(
            'state.initialize() timed out after 20s',
          ),
        );
        return (state: state, tempDir: tempDir);
      } catch (_) {
        try {
          if (!state.isDisposed) {
            await state.disposeAsync().timeout(const Duration(seconds: 5));
          }
        } catch (_) {}
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
        rethrow;
      }
    });
    final created = result!;
    addTearDown(() async {
      await disposeTestState(
        tester,
        created.state,
        tempDir: created.tempDir,
      );
    });
    return created;
  }

  group('DaywellThemeController & DaywellApp Contract Unit Tests', () {
    test('Defaults to ThemeMode.system and notifies only on changes', () {
      final controller = DaywellThemeController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(controller.themeMode, ThemeMode.system);
      expect(controller.displayLabel, 'System default');

      controller.setThemeMode(ThemeMode.system);
      expect(notifications, 0);

      controller.setThemeMode(ThemeMode.dark);
      expect(controller.themeMode, ThemeMode.dark);
      expect(controller.displayLabel, 'Dark');
      expect(notifications, 1);

      controller.setThemeMode(ThemeMode.light);
      expect(controller.themeMode, ThemeMode.light);
      expect(controller.displayLabel, 'Light');
      expect(notifications, 2);

      controller.dispose();
    });

    test(
        'Asserts when non-system themeMode and themeController are both passed',
        () {
      final controller = DaywellThemeController();
      addTearDown(controller.dispose);

      expect(
        () => DaywellApp(
          themeMode: ThemeMode.dark,
          themeController: controller,
        ),
        throwsAssertionError,
      );
    });
  });

  group('DaywellShellController & Destination Registry Unit Tests', () {
    test('Manages typed tabs, lazy visited set, and secondary route unwind',
        () {
      final shell = DaywellShellController();
      addTearDown(shell.dispose);

      expect(shell.currentTab, DaywellTabId.today);
      expect(shell.hasVisited(DaywellTabId.today), isTrue);
      expect(shell.hasVisited(DaywellTabId.calendar), isFalse);
      expect(shell.hasSecondaryRoute, isFalse);
      expect(shell.handleBackNavigation(), isFalse);

      shell.navigateByKey('calendar');
      expect(shell.currentTab, DaywellTabId.calendar);
      expect(shell.hasVisited(DaywellTabId.calendar), isTrue);

      shell.navigateByKey('backup');
      expect(shell.activeSecondaryRoute, DaywellSecondaryRoute.backup);
      expect(shell.hasSecondaryRoute, isTrue);

      expect(shell.handleBackNavigation(), isTrue);
      expect(shell.activeSecondaryRoute, isNull);
      expect(shell.currentTab, DaywellTabId.calendar);
    });

    test(
        'Resolves indexes via destination registry independently of enum order and guards out-of-range indexes',
        () {
      final reversedDestinations =
          kDaywellPrimaryDestinations.reversed.toList(growable: false);
      final shell = DaywellShellController(initialTab: DaywellTabId.notes);
      addTearDown(shell.dispose);

      // DaywellTabId.notes.index is 3, but in reversedDestinations its index is 2.
      expect(DaywellTabId.notes.index, 3);
      expect(shell.indexIn(reversedDestinations), 2);

      // Out-of-range indexes are safely ignored.
      shell.selectDestinationAt(-1, destinations: reversedDestinations);
      expect(shell.currentTab, DaywellTabId.notes);
      shell.selectDestinationAt(99, destinations: reversedDestinations);
      expect(shell.currentTab, DaywellTabId.notes);

      // Selecting index 4 in reversedDestinations selects DaywellTabId.tasks.
      shell.selectDestinationAt(4, destinations: reversedDestinations);
      expect(shell.currentTab, DaywellTabId.tasks);
    });

    testWidgets(
        'DaywellAdaptiveScaffold renders and navigates custom destination order via registry',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 840));
      addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

      final reversedDestinations =
          kDaywellPrimaryDestinations.reversed.toList(growable: false);
      final shell = DaywellShellController(initialTab: DaywellTabId.more);
      addTearDown(shell.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: DaywellAdaptiveScaffold(
            shellController: shell,
            destinations: reversedDestinations,
            tabBuilder: (DaywellTabId tab) => Scaffold(
              body: Center(child: Text('Tab:${tab.name}')),
            ),
            secondaryRouteBuilder: (DaywellSecondaryRoute route) => Scaffold(
              body: Center(child: Text('Secondary:${route.name}')),
            ),
          ),
        ),
      );
      await settleShell(tester);

      expect(find.text('Tab:more'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Tasks'),
        ),
      );
      await settleShell(tester);

      expect(shell.currentTab, DaywellTabId.tasks);
      expect(find.text('Tab:tasks'), findsOneWidget);
    });
  });

  group('DaywellAppShell Startup, Navigation, Hero & Adaptive Widget Tests',
      () {
    Future<AppStateManager> pumpInitializedShell(
      WidgetTester tester, {
      required Size viewportSize,
      DaywellThemeController? themeController,
      DaywellShellController? shellController,
    }) async {
      await tester.binding.setSurfaceSize(viewportSize);
      addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

      final created = await createIsolatedState(tester);
      final state = created.state;

      await tester.pumpWidget(
        DaywellApp(
          stateManager: state,
          themeController: themeController,
          shellController: shellController,
        ),
      );
      await settleShell(tester);
      return state;
    }

    testWidgets(
        'Displays DaywellShellStatusView error banner on failure and recovers on Retry',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 840));
      addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

      final db = _ToggleableFailDatabase(shouldFail: true);
      final created = await createIsolatedState(
        tester,
        db: db,
        initialize: false,
      );
      final state = created.state;

      await tester.pumpWidget(DaywellApp(stateManager: state));
      await waitForCondition(tester, () => state.initializationError != null);
      await settleShell(tester);

      expect(find.byType(DaywellShellStatusView), findsOneWidget);
      expect(find.byType(DaywellStatusBanner), findsOneWidget);
      expect(find.text('Unable to initialize local database'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      db.shouldFail = false;
      await tester.tap(find.text('Retry'));
      await waitForCondition(tester, () => state.isInitialized);
      await settleShell(tester);

      expect(find.byType(DaywellShellStatusView), findsNothing);
      expect(find.byType(DaywellAdaptiveScaffold), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets(
        'Prevents FAB Hero collision across visited Tasks and Notes tabs and pushes Note editor cleanly',
        (WidgetTester tester) async {
      final shellController = DaywellShellController();
      addTearDown(shellController.dispose);

      await pumpInitializedShell(
        tester,
        viewportSize: const Size(412, 840),
        shellController: shellController,
      );

      // Visit Tasks (mounts FAB with default Hero tag)
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Tasks'),
        ),
      );
      await settleShell(tester);
      expect(find.byType(TasksView), findsOneWidget);

      // Visit Notes (also mounts FAB with default Hero tag inside IndexedStack)
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Notes'),
        ),
      );
      await settleShell(tester);
      expect(find.byType(NotesView), findsOneWidget);

      // Push NoteEditor route from NotesView's FloatingActionButton.extended
      await tester.tap(find.text('New Note'));
      await settleShell(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Note title...'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await settleShell(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(NotesView), findsOneWidget);

      // Opening Backup secondary route disables HeroMode for underlying tabs
      shellController.openSecondaryRoute(DaywellSecondaryRoute.backup);
      await settleShell(tester);
      expect(find.byType(BackupView), findsOneWidget);

      final heroModes = tester
          .widgetList<HeroMode>(
            find.descendant(
              of: find.byType(DaywellAdaptiveScaffold),
              matching: find.byType(HeroMode, skipOffstage: false),
              skipOffstage: false,
            ),
          )
          .toList();
      expect(heroModes, isNotEmpty);
      expect(heroModes.every((HeroMode mode) => !mode.enabled), isTrue);
    });

    testWidgets(
        'Preserves visited tab State and user input live across 600dp breakpoint resize and back',
        (WidgetTester tester) async {
      final shellController = DaywellShellController();
      addTearDown(shellController.dispose);

      await pumpInitializedShell(
        tester,
        viewportSize: const Size(412, 840),
        shellController: shellController,
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);

      // Visit Tasks and enter a filter query so a background tab holds input state
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Tasks'),
        ),
      );
      await settleShell(tester);
      await tester.enterText(
        find
            .descendant(
              of: find.byType(TasksView),
              matching: find.byType(TextField),
            )
            .first,
        'focus task',
      );
      await settleShell(tester);

      // Switch to Notes and enter search text
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Notes'),
        ),
      );
      await settleShell(tester);
      await tester.enterText(
        find
            .descendant(
              of: find.byType(NotesView),
              matching: find.byType(TextField),
            )
            .first,
        'persistent search',
      );
      await settleShell(tester);

      final State tasksStateBefore =
          tester.state(find.byType(TasksView, skipOffstage: false));
      final State notesStateBefore = tester.state(find.byType(NotesView));

      // Resize same running widget surface above 600dp breakpoint
      await tester.binding.setSurfaceSize(const Size(900, 700));
      await settleShell(tester);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
      expect(shellController.currentTab, DaywellTabId.notes);
      expect(find.text('persistent search'), findsOneWidget);
      expect(
        identical(tester.state(find.byType(NotesView)), notesStateBefore),
        isTrue,
      );
      expect(
        identical(
          tester.state(find.byType(TasksView, skipOffstage: false)),
          tasksStateBefore,
        ),
        isTrue,
      );

      // Switch to Tasks in NavigationRail and verify its background state survived
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Tasks'),
        ),
      );
      await settleShell(tester);
      expect(find.text('focus task'), findsOneWidget);

      // Resize back below 600dp breakpoint and verify state still survives
      await tester.binding.setSurfaceSize(const Size(412, 840));
      await settleShell(tester);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.takeException(), isNull);
      expect(shellController.currentTab, DaywellTabId.tasks);
      expect(find.text('focus task'), findsOneWidget);
      expect(
        identical(tester.state(find.byType(TasksView)), tasksStateBefore),
        isTrue,
      );
    });

    testWidgets(
        'Routes real Dashboard and More callbacks and unwinds Backup via system PopScope back',
        (WidgetTester tester) async {
      final shellController = DaywellShellController();
      addTearDown(shellController.dispose);

      await pumpInitializedShell(
        tester,
        viewportSize: const Size(412, 840),
        shellController: shellController,
      );

      // Dashboard metric card: Active Tasks -> TasksView
      await tester.tap(
        find.descendant(
          of: find.byType(DashboardView),
          matching: find.text('Active Tasks'),
        ),
      );
      await settleShell(tester);
      expect(shellController.currentTab, DaywellTabId.tasks);
      expect(find.byType(TasksView), findsOneWidget);

      // Return to Today, tap Commitments -> FinanceView
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Today'),
        ),
      );
      await settleShell(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(DashboardView),
          matching: find.text('Commitments'),
        ),
      );
      await settleShell(tester);
      expect(shellController.currentTab, DaywellTabId.finance);
      expect(find.byType(FinanceView), findsOneWidget);

      // Return to Today, tap Notes metric card -> NotesView
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Today'),
        ),
      );
      await settleShell(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(DashboardView),
          matching: find.text('Notes'),
        ),
      );
      await settleShell(tester);
      expect(shellController.currentTab, DaywellTabId.notes);
      expect(find.byType(NotesView), findsOneWidget);

      // Return to Today, scroll and tap View All -> TasksView, then Manage -> FinanceView
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Today'),
        ),
      );
      await settleShell(tester);
      final Finder dashboardScrollable = find
          .descendant(
            of: find.byType(DashboardView),
            matching: find.byType(Scrollable),
          )
          .first;
      final Finder viewAllFinder = find.descendant(
        of: find.byType(DashboardView),
        matching: find.text('View All'),
      );
      await tester.scrollUntilVisible(
        viewAllFinder,
        200.0,
        scrollable: dashboardScrollable,
      );
      await settleShell(tester);
      await tester.tap(viewAllFinder);
      await settleShell(tester);
      expect(shellController.currentTab, DaywellTabId.tasks);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Today'),
        ),
      );
      await settleShell(tester);
      final Finder manageFinder = find.descendant(
        of: find.byType(DashboardView),
        matching: find.text('Manage'),
      );
      if (manageFinder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          manageFinder,
          -200.0,
          scrollable: dashboardScrollable,
        );
        await settleShell(tester);
      }
      await tester.ensureVisible(manageFinder);
      await settleShell(tester);
      await tester.tap(manageFinder);
      await settleShell(tester);
      expect(shellController.currentTab, DaywellTabId.finance);

      // Return to Today, tap Encrypted Backup AppBar icon -> BackupView, unwind via system back
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Today'),
        ),
      );
      await settleShell(tester);
      await tester.tap(find.byTooltip('Encrypted Backup'));
      await settleShell(tester);
      expect(find.byType(BackupView), findsOneWidget);
      expect(shellController.hasSecondaryRoute, isTrue);

      await tester.binding.handlePopRoute();
      await settleShell(tester);
      expect(find.byType(BackupView), findsNothing);
      expect(shellController.hasSecondaryRoute, isFalse);
      expect(shellController.currentTab, DaywellTabId.today);

      // Navigate via More All-areas cards -> CalendarView, Sync & backup
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('More'),
        ),
      );
      await settleShell(tester);
      final Finder moreCalendarCard = find.descendant(
        of: find.byType(MoreView),
        matching: find.text('Calendar'),
      );
      await tester.scrollUntilVisible(
        moreCalendarCard,
        200.0,
        scrollable: find
            .descendant(
              of: find.byType(MoreView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(moreCalendarCard);
      await settleShell(tester);
      expect(shellController.currentTab, DaywellTabId.calendar);
      expect(find.byType(CalendarView), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('More'),
        ),
      );
      await settleShell(tester);
      final Finder moreSyncBackupTile = find.descendant(
        of: find.byType(MoreView),
        matching: find.text('Sync & backup'),
      );
      await tester.scrollUntilVisible(
        moreSyncBackupTile,
        200.0,
        scrollable: find
            .descendant(
              of: find.byType(MoreView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(moreSyncBackupTile);
      await settleShell(tester);
      expect(find.byType(BackupView), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await settleShell(tester);
      expect(find.byType(BackupView), findsNothing);
      expect(shellController.currentTab, DaywellTabId.more);
    });

    testWidgets(
        'Supports live ThemeMode switching via More Appearance dialog and renders on short wide landscape',
        (WidgetTester tester) async {
      final themeController = DaywellThemeController();
      addTearDown(themeController.dispose);

      await pumpInitializedShell(
        tester,
        viewportSize: const Size(700, 380),
        themeController: themeController,
      );
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('More'),
        ),
      );
      await settleShell(tester);
      expect(
        find.descendant(
          of: find.byType(MoreView),
          matching: find.byType(DaywellCard),
        ),
        findsWidgets,
      );
      final Finder moreScrollable = find
          .descendant(
            of: find.byType(MoreView),
            matching: find.byType(Scrollable),
          )
          .first;
      final Finder moreSectionHeader = find.descendant(
        of: find.byType(MoreView),
        matching: find.byType(DaywellSectionHeader),
      );
      await tester.scrollUntilVisible(
        moreSectionHeader,
        200.0,
        scrollable: moreScrollable,
      );
      expect(moreSectionHeader, findsWidgets);

      await tester.scrollUntilVisible(
        find.text('Appearance'),
        200.0,
        scrollable: moreScrollable,
      );
      await tester.tap(find.text('Appearance'));
      await settleShell(tester);

      expect(find.byType(DaywellRadioTile<ThemeMode>), findsNWidgets(3));
      await tester.ensureVisible(find.text('Dark'));
      await settleShell(tester);
      await tester.tap(find.text('Dark'));
      await settleShell(tester);
      await tester.tap(find.text('Done'));
      await settleShell(tester);

      expect(themeController.themeMode, ThemeMode.dark);
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.dark);
      expect(tester.takeException(), isNull);
    });
  });

  group('Quick Capture & Shared Text MethodChannel Regression Tests', () {
    testWidgets(
        'Buffers cold-start trigger and shared text while DB initializes and deduplicates repeat signals',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 840));
      addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

      final initGate = Completer<void>();
      final db = _ToggleableFailDatabase(gate: initGate);
      final created = await createIsolatedState(
        tester,
        db: db,
        initialize: false,
      );
      final state = created.state;

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _kQuickCaptureChannel,
        (MethodCall call) async {
          if (call.method == 'checkQuickCaptureTrigger') return true;
          if (call.method == 'getSharedText') return 'Shared note';
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(_kQuickCaptureChannel, null);
      });

      await tester.pumpWidget(DaywellApp(stateManager: state));
      await tester.pump();

      // Still loading: QuickCaptureDialog must NOT attempt to open prematurely.
      expect(find.byType(DaywellLoadingIndicator), findsOneWidget);
      expect(find.byType(QuickCaptureDialog), findsNothing);

      // Push duplicate Android signals before initialization finishes.
      await dispatchQuickCapturePlatformCall(
        tester,
        'onQuickCaptureTriggered',
      );
      await dispatchQuickCapturePlatformCall(
        tester,
        'onTextShared',
        'Shared note',
      );
      await tester.pump();
      expect(find.byType(QuickCaptureDialog), findsNothing);

      // Finish initialization cleanly across FakeAsync and real async loops.
      initGate.complete();
      await waitForCondition(tester, () => state.isInitialized);
      await settleShell(tester);

      // Exactly 1 QuickCaptureDialog opens and shared text wins over empty trigger.
      expect(find.byType(QuickCaptureDialog), findsOneWidget);
      expect(find.text('Shared note'), findsOneWidget);

      // Canceling does not spawn a second redundant blank dialog.
      await tester.tap(find.text('Cancel'));
      await settleShell(tester);
      expect(find.byType(QuickCaptureDialog), findsNothing);
    });

    testWidgets(
        'Preserves buffered shared text across startup failure and Retry recovery',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 840));
      addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

      final db = _ToggleableFailDatabase(shouldFail: true);
      final created = await createIsolatedState(
        tester,
        db: db,
        initialize: false,
      );
      final state = created.state;

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _kQuickCaptureChannel,
        (MethodCall call) async {
          if (call.method == 'checkQuickCaptureTrigger') return false;
          if (call.method == 'getSharedText') return 'Survives retry';
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(_kQuickCaptureChannel, null);
      });

      await tester.pumpWidget(DaywellApp(stateManager: state));
      await waitForCondition(tester, () => state.initializationError != null);
      await settleShell(tester);

      expect(find.byType(DaywellShellStatusView), findsOneWidget);
      expect(find.byType(QuickCaptureDialog), findsNothing);

      db.shouldFail = false;
      await tester.tap(find.text('Retry'));
      await waitForCondition(tester, () => state.isInitialized);
      await tester.pump();
      await settleShell(tester);

      expect(find.byType(QuickCaptureDialog), findsOneWidget);
      expect(find.text('Survives retry'), findsOneWidget);
    });

    testWidgets(
        'Warm-start rapid duplicate triggers show 1 dialog at a time and flush distinct queued text on barrier dismiss',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 840));
      addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

      final created = await createIsolatedState(tester);
      final state = created.state;

      await tester.pumpWidget(DaywellApp(stateManager: state));
      await settleShell(tester);

      // Send rapid warm-start calls: duplicate trigger, duplicate shared text, distinct shared text.
      await dispatchQuickCapturePlatformCall(
        tester,
        'onTextShared',
        'First item',
      );
      await dispatchQuickCapturePlatformCall(
        tester,
        'onQuickCaptureTriggered',
      );
      await dispatchQuickCapturePlatformCall(
        tester,
        'onTextShared',
        'First item',
      );
      await dispatchQuickCapturePlatformCall(
        tester,
        'onTextShared',
        'Second item',
      );
      await settleShell(tester);

      expect(find.byType(QuickCaptureDialog), findsOneWidget);
      expect(find.text('First item'), findsOneWidget);

      // Dismiss first dialog via modal barrier tap; queued 'Second item' opens next.
      await tester.tapAt(const Offset(10, 10));
      await settleShell(tester);

      expect(find.byType(QuickCaptureDialog), findsOneWidget);
      expect(find.text('Second item'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await settleShell(tester);
      expect(find.byType(QuickCaptureDialog), findsNothing);
    });
  });

  group('CalendarPlaceholderView States Tests', () {
    testWidgets(
        'Renders loading, error + Retry, populated preview, and empty states accurately',
        (WidgetTester tester) async {
      final completer = Completer<List<CalendarEventEntity>>();
      final repo = _FakeCalendarRepository(pendingLoad: completer);
      final controller = CalendarController(repository: repo);
      addTearDown(controller.dispose);
      var openTasksTapped = 0;

      unawaited(controller.loadAll());

      await tester.pumpWidget(
        MaterialApp(
          home: CalendarPlaceholderView(
            controller: controller,
            onOpenTasks: () => openTasksTapped++,
          ),
        ),
      );
      await tester.pump();

      // 1. Loading state
      expect(find.byType(DaywellLoadingIndicator), findsOneWidget);
      expect(find.text('Loading calendar events...'), findsOneWidget);

      // 2. Error state + Retry CTA
      repo.pendingLoad = null;
      repo.shouldThrow = true;
      completer.completeError(StateError('Calendar IO failure'));
      await settleShell(tester);

      expect(find.text('Unable to load calendar events'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Tap Retry -> transitions to Populated state
      final callsBeforeRetry = repo.loadCalls;
      repo.shouldThrow = false;
      repo.eventsToReturn = <CalendarEventEntity>[
        CalendarEventEntity(
          id: 'evt-1',
          title: 'Team Sync',
          dateIso: '2026-04-02',
        ),
      ];
      await tester.tap(find.text('Retry'));
      await settleShell(tester);

      expect(repo.loadCalls, callsBeforeRetry + 1);
      expect(
        find.text('1 synced calendar events ready offline.'),
        findsOneWidget,
      );
      expect(find.text('Synced Events Preview'), findsOneWidget);
      expect(find.text('Team Sync · 2026-04-02'), findsOneWidget);

      // 3. Empty state + Open Tasks CTA
      repo.eventsToReturn = const <CalendarEventEntity>[];
      await controller.loadAll();
      await settleShell(tester);

      expect(find.text('Calendar workspace coming soon'), findsOneWidget);
      expect(find.text('Open Tasks'), findsOneWidget);

      await tester.tap(find.text('Open Tasks'));
      await settleShell(tester);
      expect(openTasksTapped, 1);
    });
  });

  group('Stage 4 Shell Back Navigation & Double-Back-to-Exit Tests', () {
    test(
        'Deduplicates main-tab history, avoids loops, resets on Today, and enforces priority order',
        () async {
      var now = DateTime.utc(2026, 4, 10, 12, 0, 0);
      final shell = DaywellShellController(clock: () => now);
      addTearDown(shell.dispose);

      expect(shell.tabHistory, [DaywellTabId.today]);
      expect(shell.isAtTodayRoot, isTrue);

      // Selecting already-active tab is a no-op
      shell.selectTab(DaywellTabId.today);
      expect(shell.tabHistory, [DaywellTabId.today]);

      // Visit Tasks -> Finance -> Tasks (loop-free deduplication)
      shell.selectTab(DaywellTabId.tasks);
      shell.selectTab(DaywellTabId.tasks); // duplicate tap ignored
      shell.selectTab(DaywellTabId.finance);
      shell.selectTab(DaywellTabId.tasks);
      expect(
        shell.tabHistory,
        [DaywellTabId.today, DaywellTabId.finance, DaywellTabId.tasks],
      );

      // Priority 2: Secondary route before module handler & tab history
      var tasksHandlerCalls = 0;
      var tasksConsumes = true;
      shell.registerTabBackHandler(DaywellTabId.tasks, () async {
        tasksHandlerCalls++;
        return tasksConsumes;
      });
      shell.openSecondaryRoute(DaywellSecondaryRoute.backup);
      expect(
        await shell.handleSystemBack(),
        DaywellShellBackOutcome.handledSecondaryRoute,
      );
      expect(shell.hasSecondaryRoute, isFalse);
      expect(tasksHandlerCalls, 0);
      expect(shell.currentTab, DaywellTabId.tasks);

      // Priority 3: Active module handler consumes internal state first
      expect(
        await shell.handleSystemBack(),
        DaywellShellBackOutcome.handledByModule,
      );
      expect(tasksHandlerCalls, 1);
      expect(shell.currentTab, DaywellTabId.tasks);

      // Priority 4: When module handler returns false, pop tab history (Tasks -> Finance -> Today)
      tasksConsumes = false;
      expect(
        await shell.handleSystemBack(),
        DaywellShellBackOutcome.handledTabHistory,
      );
      expect(shell.currentTab, DaywellTabId.finance);

      expect(
        await shell.handleSystemBack(),
        DaywellShellBackOutcome.handledTabHistory,
      );
      expect(shell.currentTab, DaywellTabId.today);
      expect(shell.isAtTodayRoot, isTrue);

      // Navigating directly to Today clears prior non-Today tab history
      shell.selectTab(DaywellTabId.notes);
      shell.selectTab(DaywellTabId.calendar);
      shell.selectTab(DaywellTabId.today);
      expect(shell.tabHistory, [DaywellTabId.today]);
      expect(shell.isAtTodayRoot, isTrue);

      // Priority 5: Double-back-to-exit at Today root with 2s timeout reset
      expect(
        await shell.handleSystemBack(),
        DaywellShellBackOutcome.promptExitApp,
      );

      now = now.add(const Duration(seconds: 3));
      expect(
        await shell.handleSystemBack(),
        DaywellShellBackOutcome.promptExitApp,
      );

      now = now.add(const Duration(seconds: 1));
      expect(
        await shell.handleSystemBack(),
        DaywellShellBackOutcome.exitApp,
      );
    });

    testWidgets(
        'Shows Press back again to exit at Today root, exits on second press within 2s, and never exits from other modules',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 840));
      addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

      var now = DateTime.utc(2026, 4, 10, 12, 0, 0);
      var exitCalls = 0;
      final shell = DaywellShellController(clock: () => now);
      addTearDown(shell.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: DaywellAdaptiveScaffold(
            shellController: shell,
            onExitApp: () async => exitCalls++,
            tabBuilder: (DaywellTabId tab) => Scaffold(
              body: Center(child: Text('Tab:${tab.name}')),
            ),
            secondaryRouteBuilder: (DaywellSecondaryRoute route) => Scaffold(
              body: Center(child: Text('Secondary:${route.name}')),
            ),
          ),
        ),
      );
      await settleShell(tester);

      // On Tasks tab, back returns to Today instead of prompting exit or exiting
      shell.selectTab(DaywellTabId.tasks);
      await settleShell(tester);
      expect(shell.currentTab, DaywellTabId.tasks);

      await tester.binding.handlePopRoute();
      await settleShell(tester);
      expect(shell.currentTab, DaywellTabId.today);
      expect(exitCalls, 0);
      expect(find.text('Press back again to exit'), findsNothing);

      // First back at Today root shows unobtrusive prompt without exiting
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Press back again to exit'), findsOneWidget);
      expect(exitCalls, 0);

      // After > 2 seconds, resets instead of exiting
      now = now.add(const Duration(milliseconds: 2500));
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(exitCalls, 0);
      expect(find.text('Press back again to exit'), findsOneWidget);

      // Second press within 2 seconds exits
      now = now.add(const Duration(milliseconds: 900));
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(exitCalls, 1);
    });
  });
}
