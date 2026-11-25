import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/domain/notes/note_helpers.dart';
import 'package:personal_management_app/domain/notes/note_models.dart';
import 'package:personal_management_app/main.dart';
import 'package:personal_management_app/ui/app_state.dart';
import 'package:personal_management_app/ui/screens/dashboard_view.dart';
import 'package:personal_management_app/ui/shell/daywell_shell_routes.dart';

import 'support/sqlite_test_helper.dart';

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
        addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

        final db = AppDatabase(NativeDatabase.memory());
        final appState = AppStateManager(db: db);
        await tester.runAsync(() => appState.initialize());
        addTearDown(() => appState.dispose());

        final t1 = DateTime.utc(2026, 3, 10, 9);
        final t2 = DateTime.utc(2026, 3, 15, 9);
        final t3 = DateTime.utc(2026, 3, 20, 9);
        final t4 = DateTime.utc(2026, 3, 22, 9);

        await tester.runAsync(() async {
          await appState.notesRepository.saveNote(
            NoteEntity(
              id: 'n-old-pin',
              title: 'Older Pinned Reference',
              content: 'Should sit after newer notes',
              category: 'work',
              isPinned: true,
              createdAt: t1,
              updatedAt: t1,
            ),
          );
          await appState.notesRepository.saveNote(
            NoteEntity(
              id: 'n-fresh',
              title: 'Fresh Strategy Note',
              content: '## Summary\nAlign **Milestones** for release.',
              category: 'study',
              createdAt: t2,
              updatedAt: t3,
            ),
          );
          await appState.notesRepository.saveNote(
            NoteEntity(
              id: 'n-arch',
              title: 'Archived Quarterly Note',
              content: 'Archived body',
              isArchived: true,
              createdAt: t1,
              updatedAt: t4,
            ),
          );
          await appState.notesRepository.saveNote(
            NoteEntity(
              id: 'n-trash',
              title: 'Trashed Scratch Note',
              content: 'Deleted body',
              isTrashed: true,
              createdAt: t1,
              updatedAt: t4,
            ),
          );
          await appState.notesController.loadNotes();
        });

        final openedNoteIds = <String>[];
        var openedAllNotesCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light(),
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
        await tester.pumpAndSettle();

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
        await tester.pumpAndSettle();
        expect(openedNoteIds, <String>['n-fresh']);

        // Updating Older Pinned Reference content/title updates Dashboard live.
        await tester.runAsync(() async {
          await appState.notesController.updateNote(
            NoteEntity(
              id: 'n-old-pin',
              title: 'Updated Pinned Reference',
              content: 'Now freshly revised',
              category: 'work',
              isPinned: true,
              createdAt: t1,
              updatedAt: DateTime.utc(2026, 3, 25, 9),
            ),
          );
        });
        await tester.pumpAndSettle();
        expect(find.text('Updated Pinned Reference'), findsOneWidget);
        expect(find.text('Now freshly revised'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Updated Pinned Reference')).dy,
          lessThan(tester.getTopLeft(find.text('Fresh Strategy Note')).dy),
        );

        // Trashing both active notes leaves only Archive-aware empty state.
        await tester.runAsync(() async {
          await appState.notesController.trashNote('n-old-pin');
          await appState.notesController.trashNote('n-fresh');
        });
        await tester.pumpAndSettle();

        expect(find.text('No active notes yet'), findsOneWidget);
        expect(
          find.text(
            'All recorded notes are archived. Open Notes to view your Archive.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Open Notes'));
        await tester.pumpAndSettle();
        expect(openedAllNotesCount, 1);
      },
    );

    testWidgets(
      '3. Selecting a Recent Note from Dashboard opens that exact note directly inside NotesView on narrow (<840dp) and wide (>=840dp) screens without overflow',
      (WidgetTester tester) async {
        // Part A: Narrow mobile layout (<840dp) pushes dedicated note editor route
        await tester.binding.setSurfaceSize(const Size(412, 892));
        addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

        final dbNarrow = AppDatabase(NativeDatabase.memory());
        final narrowState = AppStateManager(db: dbNarrow);
        await tester.runAsync(() async {
          await narrowState.initialize();
          await narrowState.notesRepository.saveNote(
            NoteEntity(
              id: 'n-target',
              title: 'Mobile Focus Note',
              content: 'Opened directly from Dashboard on phone width.',
              createdAt: DateTime.utc(2026, 3, 18, 9),
              updatedAt: DateTime.utc(2026, 3, 19, 9),
            ),
          );
          await narrowState.notesController.loadNotes();
        });
        addTearDown(() => narrowState.dispose());

        await tester.pumpWidget(DaywellApp(stateManager: narrowState));
        await tester.pumpAndSettle();

        final noteCard = find.text('Mobile Focus Note');
        await tester.ensureVisible(noteCard);
        await tester.pumpAndSettle();
        await tester.tap(noteCard);
        await tester.pumpAndSettle();

        // Now inside Notes tab with the narrow editor pushed for 'Mobile Focus Note'.
        expect(
          find.text('Opened directly from Dashboard on phone width.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        // Part B: Wide master-detail layout (>=840dp) opens target note in right detail pane
        await tester.binding.setSurfaceSize(const Size(1024, 800));
        final dbWide = AppDatabase(NativeDatabase.memory());
        final wideState = AppStateManager(db: dbWide);
        await tester.runAsync(() async {
          await wideState.initialize();
          await wideState.notesRepository.saveNote(
            NoteEntity(
              id: 'n-wide',
              title: 'Master Detail Note',
              content: 'Detail pane body loaded from Dashboard.',
              createdAt: DateTime.utc(2026, 3, 18, 9),
              updatedAt: DateTime.utc(2026, 3, 20, 9),
            ),
          );
          await wideState.notesController.loadNotes();
        });
        addTearDown(() => wideState.dispose());

        await tester.pumpWidget(DaywellApp(stateManager: wideState));
        await tester.pumpAndSettle();

        final wideNoteCard = find.text('Master Detail Note');
        await tester.ensureVisible(wideNoteCard);
        await tester.pumpAndSettle();
        await tester.tap(wideNoteCard);
        await tester.pumpAndSettle();

        expect(
          find.text('Detail pane body loaded from Dashboard.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '4. DashboardNotesSection handles tight 320dp viewport at 2.0x text scale without layout overflow',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 720));
        addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

        final db = AppDatabase(NativeDatabase.memory());
        final appState = AppStateManager(db: db);
        await tester.runAsync(() async {
          await appState.initialize();
          for (var i = 1; i <= 5; i++) {
            await appState.notesRepository.saveNote(
              NoteEntity(
                id: 'n-$i',
                title: 'Very Long Strategy And Operations Note Title #$i',
                content:
                    'Multi-word Markdown preview that truncates cleanly under 2.0x accessibility scale.',
                category: 'work_projects',
                isPinned: i == 1,
                createdAt: DateTime.utc(2026, 3, i, 9),
                updatedAt: DateTime.utc(2026, 3, i, 9),
              ),
            );
          }
          await appState.notesController.loadNotes();
        });
        addTearDown(() => appState.dispose());

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 720),
                textScaler: TextScaler.linear(2.0),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: DashboardView(
                    state: appState,
                    onOpenQuickCapture: () {},
                    onSelectTab: (DaywellTabId _) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('+ 1 more note'), findsOneWidget);
      },
    );
  });
}
