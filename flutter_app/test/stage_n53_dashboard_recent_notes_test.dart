import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/interfaces/platform_service_interfaces.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/raw_database_recovery_exporter.dart';
import 'package:personal_management_app/domain/notes/note_helpers.dart';
import 'package:personal_management_app/domain/notes/note_models.dart';
import 'package:personal_management_app/main.dart';
import 'package:personal_management_app/ui/app_state.dart';
import 'package:personal_management_app/ui/screens/dashboard_view.dart';
import 'package:personal_management_app/ui/shell/daywell_shell_routes.dart';

import 'support/sqlite_test_helper.dart';

typedef _N53Fixture = ({
  AppDatabase db,
  AppStateManager appState,
  Directory tempDir,
});

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

Future<void> _settle(WidgetTester tester) {
  return tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
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
  await _settle(tester);
}

Future<void> _disposeTestState(
  WidgetTester tester,
  AppStateManager state, {
  Directory? tempDir,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
  try {
    if (!state.isDisposed) {
      var disposed = false;
      final disposeFuture = state.disposeAsync().whenComplete(() {
        disposed = true;
      });
      final stopwatch = Stopwatch()..start();
      while (!disposed && stopwatch.elapsed < const Duration(seconds: 10)) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      if (disposed) {
        await disposeFuture;
      } else {
        await tester.runAsync(
          () => disposeFuture.timeout(const Duration(seconds: 5)),
        );
      }
    }
  } finally {
    if (tempDir != null && tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}

Future<_N53Fixture> _createIsolatedAppState(
  WidgetTester tester, {
  Future<void> Function(AppDatabase db, AppStateManager appState)? seed,
}) async {
  final result = await tester.runAsync(() async {
    final tempDir = Directory.systemTemp.createTempSync('daywell_n53_');
    final docsDir = Directory(p.join(tempDir.path, 'docs'));
    docsDir.createSync();
    final supportDir = Directory(p.join(tempDir.path, 'support'));
    supportDir.createSync();
    final db = AppDatabase(NativeDatabase.memory());
    final appState = AppStateManager(
      db: db,
      recoveryExporter: RawDatabaseRecoveryExporter(
        documentsDirProvider: () async => docsDir,
        supportDirProvider: () async => supportDir,
      ),
      notificationService: _NoOpNotificationService(),
    );
    try {
      final ensureFuture = db.ensureInitialized();
      await ensureFuture.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'db.ensureInitialized() timed out after 15s',
        ),
      );
      final initFuture = appState.initialize();
      await initFuture.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'appState.initialize() timed out after 15s',
        ),
      );
      if (seed != null) {
        final seedFuture = seed(db, appState);
        await seedFuture.timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException(
            'Stage N5.3 test seed timed out after 15s',
          ),
        );
      }
      return (db: db, appState: appState, tempDir: tempDir);
    } catch (_) {
      try {
        if (!appState.isDisposed) {
          await appState.disposeAsync().timeout(const Duration(seconds: 5));
        }
      } catch (_) {}
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      rethrow;
    }
  });
  return result!;
}

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage N5.3 — Dashboard Recent Notes Integration', () {
    test(
      '1. NoteDomainHelpers.buildDashboardRecentNotesSummary sorts strictly by updatedAt desc, deduplicates IDs, excludes trash & archive, and strips Markdown previews',
      () {
        final t1 = DateTime.utc(2026, 3, 10, 9);
        final t2 = DateTime.utc(2026, 3, 12, 9);
        final t3 = DateTime.utc(2026, 3, 14, 9);
        final t4 = DateTime.utc(2026, 3, 16, 9);
        final t5 = DateTime.utc(2026, 3, 18, 9);
        final t6 = DateTime.utc(2026, 3, 20, 9);

        final notes = <NoteEntity>[
          NoteEntity(
            id: 'n-old-pinned',
            title: 'Older Pinned Note',
            content: 'Pinned much earlier',
            isPinned: true,
            createdAt: t1,
            updatedAt: t1,
          ),
          NoteEntity(
            id: 'n-dup',
            title: 'Stale Copy',
            content: 'Old draft',
            createdAt: t1,
            updatedAt: t1,
          ),
          NoteEntity(
            id: 'n-dup',
            title: 'Fresh Copy',
            content: 'Latest **Markdown** body',
            createdAt: t1,
            updatedAt: t5,
          ),
          NoteEntity(
            id: 'n-2',
            title: 'Second Note',
            content: 'Second body',
            createdAt: t2,
            updatedAt: t4,
          ),
          NoteEntity(
            id: 'n-3',
            title: 'Third Note',
            content: 'Third body',
            createdAt: t2,
            updatedAt: t3,
          ),
          NoteEntity(
            id: 'n-4',
            title: 'Fourth Note',
            content: 'Fourth body',
            createdAt: t1,
            updatedAt: t2,
          ),
          NoteEntity(
            id: 'n-arch',
            title: 'Archived Note',
            content: 'Should not appear on active Dashboard',
            isArchived: true,
            createdAt: t1,
            updatedAt: t6,
          ),
          NoteEntity(
            id: 'n-trash',
            title: 'Trashed Note',
            content: 'Deleted item',
            isTrashed: true,
            createdAt: t1,
            updatedAt: t6,
          ),
        ];

        final summary =
            NoteDomainHelpers.buildDashboardRecentNotesSummary(notes);
        expect(summary.totalActiveCount, 5);
        expect(summary.archivedCount, 1);
        expect(summary.recentNotes.length, 4);
        expect(
          summary.recentNotes.map((NoteEntity n) => n.id).toList(),
          <String>['n-dup', 'n-2', 'n-3', 'n-4'],
        );
        expect(summary.recentNotes.first.title, 'Fresh Copy');

        final preview = NoteDomainHelpers.buildContentPreview(
          '# Heading\n- [x] Ship **N5.3** preview\n- Follow [[Roadmap]]',
          maxLength: 80,
        );
        expect(preview.contains('# '), isFalse);
        expect(preview.contains('**'), isFalse);
        expect(preview, contains('Heading'));
        expect(preview, contains('Ship N5.3 preview'));
      },
    );

    testWidgets(
      '2. DashboardNotesSection displays updated notes by recency, formats dates & plain previews, excludes Trash/Archive, and reflects live NotesController changes',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(960, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final t1 = DateTime.utc(2026, 3, 10, 9);
        final t2 = DateTime.utc(2026, 3, 15, 9);
        final t3 = DateTime.utc(2026, 3, 20, 9);
        final t4 = DateTime.utc(2026, 3, 22, 9);

        final fixture = await _createIsolatedAppState(
          tester,
          seed: (AppDatabase db, AppStateManager appState) async {
            await db.into(db.notes).insert(
                  NotesCompanion.insert(
                    id: 'n-old-pin',
                    title: 'Older Pinned Reference',
                    content: 'Should sit after newer notes',
                    category: const Value('work'),
                    isPinned: const Value(true),
                    createdAt: t1,
                    updatedAt: t1,
                  ),
                );
            await db.into(db.notes).insert(
                  NotesCompanion.insert(
                    id: 'n-fresh',
                    title: 'Fresh Strategy Note',
                    content: '## Summary\nAlign **Milestones** for release.',
                    category: const Value('study'),
                    createdAt: t2,
                    updatedAt: t3,
                  ),
                );
            await db.into(db.notes).insert(
                  NotesCompanion.insert(
                    id: 'n-arch',
                    title: 'Archived Quarterly Note',
                    content: 'Archived body',
                    isArchived: const Value(true),
                    createdAt: t1,
                    updatedAt: t4,
                  ),
                );
            await db.into(db.notes).insert(
                  NotesCompanion.insert(
                    id: 'n-trash',
                    title: 'Trashed Scratch Note',
                    content: 'Deleted body',
                    isTrashed: const Value(true),
                    createdAt: t1,
                    updatedAt: t4,
                  ),
                );
            await appState.notesController.loadNotes();
          },
        );
        final appState = fixture.appState;
        addTearDown(
          () => _disposeTestState(
            tester,
            appState,
            tempDir: fixture.tempDir,
          ),
        );

        final openedNoteIds = <String>[];
        var openedAllNotesCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: DashboardNotesSection(
                  state: appState,
                  onOpenNotes: () => openedAllNotesCount++,
                  onOpenNote: openedNoteIds.add,
                ),
              ),
            ),
          ),
        );
        await _settle(tester);

        expect(find.text('Recent Notes'), findsOneWidget);
        expect(find.text('All Notes'), findsOneWidget);
        expect(find.text('Fresh Strategy Note'), findsOneWidget);
        expect(
          find.text('Summary Align Milestones for release.'),
          findsOneWidget,
        );
        final freshDate = SharedDateFormatter.formatEthiopian(
          CalendarDate.fromUtcInstantInEthiopia(t3).toEthiopian(),
          useAmharic: false,
          includeEra: false,
        );
        expect(find.text('Updated $freshDate'), findsOneWidget);
        expect(find.text('Older Pinned Reference'), findsOneWidget);
        expect(find.text('Archived Quarterly Note'), findsNothing);
        expect(find.text('Trashed Scratch Note'), findsNothing);

        // Fresh Strategy Note renders strictly above Older Pinned Reference.
        final freshY = tester.getTopLeft(find.text('Fresh Strategy Note')).dy;
        final oldPinY =
            tester.getTopLeft(find.text('Older Pinned Reference')).dy;
        expect(freshY, lessThan(oldPinY));

        // Tapping a note card triggers direct onOpenNote with that exact ID.
        await tester.tap(find.text('Fresh Strategy Note'));
        await _settle(tester);
        expect(openedNoteIds, <String>['n-fresh']);

        // Updating Older Pinned Reference content/title updates Dashboard live.
        await tester.runAsync(() async {
          final updateFuture = appState.notesController.updateNote(
            id: 'n-old-pin',
            title: 'Updated Pinned Reference',
            content: 'Now freshly revised',
          );
          await updateFuture.timeout(const Duration(seconds: 10));
        });
        await _pumpUntil(
          tester,
          () => find.text('Updated Pinned Reference').evaluate().isNotEmpty,
          reason: 'DashboardNotesSection did not reflect updated note.',
        );
        expect(find.text('Updated Pinned Reference'), findsOneWidget);
        expect(find.text('Now freshly revised'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Updated Pinned Reference')).dy,
          lessThan(tester.getTopLeft(find.text('Fresh Strategy Note')).dy),
        );

        // Trashing both active notes leaves only Archive-aware empty state.
        await tester.runAsync(() async {
          final deleteOld = appState.notesController.deleteNote('n-old-pin');
          await deleteOld.timeout(const Duration(seconds: 10));
          final deleteFresh = appState.notesController.deleteNote('n-fresh');
          await deleteFresh.timeout(const Duration(seconds: 10));
        });
        await _pumpUntil(
          tester,
          () => find.text('No active notes yet').evaluate().isNotEmpty,
          reason:
              'DashboardNotesSection did not show archive-aware empty state.',
        );

        expect(find.text('No active notes yet'), findsOneWidget);
        expect(
          find.text(
            'All recorded notes are archived. Open Notes to view your Archive.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Open Notes'));
        await _settle(tester);
        expect(openedAllNotesCount, 1);
      },
    );

    testWidgets(
      '3. Selecting a Recent Note from Dashboard opens that exact note directly inside NotesView on narrow (<840dp) and wide (>=840dp) screens without overflow',
      (WidgetTester tester) async {
        // Part A: Narrow mobile layout (<840dp) pushes dedicated note editor route
        await tester.binding.setSurfaceSize(const Size(412, 892));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final narrowFixture = await _createIsolatedAppState(
          tester,
          seed: (AppDatabase db, AppStateManager appState) async {
            await db.into(db.notes).insert(
                  NotesCompanion.insert(
                    id: 'n-target',
                    title: 'Mobile Focus Note',
                    content: 'Opened directly from Dashboard on phone width.',
                    createdAt: DateTime.utc(2026, 3, 18, 9),
                    updatedAt: DateTime.utc(2026, 3, 19, 9),
                  ),
                );
            await appState.notesController.loadNotes();
          },
        );
        addTearDown(
          () => _disposeTestState(
            tester,
            narrowFixture.appState,
            tempDir: narrowFixture.tempDir,
          ),
        );

        await tester.pumpWidget(
          DaywellApp(stateManager: narrowFixture.appState),
        );
        await _settle(tester);

        final noteCard = find.text('Mobile Focus Note');
        await tester.scrollUntilVisible(
          noteCard,
          240.0,
          scrollable: find.byType(Scrollable).first,
        );
        await _settle(tester);
        await tester.tap(noteCard);
        await _pumpUntil(
          tester,
          () => find
              .widgetWithText(
                TextField,
                'Opened directly from Dashboard on phone width.',
              )
              .evaluate()
              .isNotEmpty,
          reason: 'Mobile note editor did not open from Dashboard.',
        );

        // Now inside Notes tab with the narrow editor pushed for 'Mobile Focus Note'.
        expect(find.byType(BackButton), findsOneWidget);
        expect(
          find.widgetWithText(TextField, 'Mobile Focus Note'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(
            TextField,
            'Opened directly from Dashboard on phone width.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await _disposeTestState(
          tester,
          narrowFixture.appState,
          tempDir: narrowFixture.tempDir,
        );

        // Part B: Wide master-detail layout (>=840dp) opens target note in right detail pane
        await tester.binding.setSurfaceSize(const Size(1024, 800));
        final wideFixture = await _createIsolatedAppState(
          tester,
          seed: (AppDatabase db, AppStateManager appState) async {
            await db.into(db.notes).insert(
                  NotesCompanion.insert(
                    id: 'n-wide',
                    title: 'Master Detail Note',
                    content: 'Detail pane body loaded from Dashboard.',
                    createdAt: DateTime.utc(2026, 3, 18, 9),
                    updatedAt: DateTime.utc(2026, 3, 20, 9),
                  ),
                );
            await appState.notesController.loadNotes();
          },
        );
        addTearDown(
          () => _disposeTestState(
            tester,
            wideFixture.appState,
            tempDir: wideFixture.tempDir,
          ),
        );

        await tester.pumpWidget(DaywellApp(stateManager: wideFixture.appState));
        await _settle(tester);

        final wideNoteCard = find.text('Master Detail Note');
        await tester.scrollUntilVisible(
          wideNoteCard,
          240.0,
          scrollable: find.byType(Scrollable).first,
        );
        await _settle(tester);
        await tester.tap(wideNoteCard);
        await _pumpUntil(
          tester,
          () => find
              .widgetWithText(
                TextField,
                'Detail pane body loaded from Dashboard.',
              )
              .evaluate()
              .isNotEmpty,
          reason: 'Wide master-detail note pane did not open from Dashboard.',
        );

        expect(find.byType(BackButton), findsNothing);
        expect(find.text('Select a note to read or edit'), findsNothing);
        expect(find.byIcon(Icons.arrow_right_rounded), findsOneWidget);
        expect(
          find.widgetWithText(TextField, 'Master Detail Note'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(
            TextField,
            'Detail pane body loaded from Dashboard.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '4. DashboardNotesSection handles tight 320dp viewport at 2.0x text scale without layout overflow',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final fixture = await _createIsolatedAppState(
          tester,
          seed: (AppDatabase db, AppStateManager appState) async {
            for (var i = 1; i <= 5; i++) {
              await db.into(db.notes).insert(
                    NotesCompanion.insert(
                      id: 'n-$i',
                      title: 'Very Long Strategy And Operations Note Title #$i',
                      content:
                          'Multi-word Markdown preview that truncates cleanly under 2.0x accessibility scale.',
                      category: const Value('work_projects'),
                      isPinned: Value(i == 1),
                      createdAt: DateTime.utc(2026, 3, i, 9),
                      updatedAt: DateTime.utc(2026, 3, i, 9),
                    ),
                  );
            }
            await appState.notesController.loadNotes();
          },
        );
        addTearDown(
          () => _disposeTestState(
            tester,
            fixture.appState,
            tempDir: fixture.tempDir,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Builder(
              builder: (BuildContext context) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(2.0),
                  ),
                  child: DashboardView(
                    state: fixture.appState,
                    onOpenQuickCapture: () {},
                    onSelectTab: (DaywellTabId _) {},
                  ),
                );
              },
            ),
          ),
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);

        await tester.scrollUntilVisible(
          find.byType(DashboardNotesSection),
          240.0,
          scrollable: find.byType(Scrollable).first,
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);

        await tester.scrollUntilVisible(
          find.text('+ 1 more note'),
          120.0,
          scrollable: find.byType(Scrollable).first,
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(DashboardNotesSection), findsOneWidget);
        expect(find.text('+ 1 more note'), findsOneWidget);
      },
    );
  });
}
