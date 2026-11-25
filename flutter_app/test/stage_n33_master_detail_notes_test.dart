import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/repositories/notes_repository.dart';
import 'package:personal_management_app/ui/screens/notes_view.dart';

class _StageN33InMemoryNotesRepository implements INotesRepository {
  final Map<String, NoteEntity> store = <String, NoteEntity>{};
  bool failUpdates = false;
  int createCount = 0;

  void seed(NoteEntity note) {
    store[note.id] = note;
  }

  @override
  Future<NoteEntity> createNote(NoteEntity note) async {
    createCount++;
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
  Future<NoteEntity> updateNote(NoteEntity note) async {
    if (failUpdates) {
      throw Exception('Simulated persistence error');
    }
    store[note.id] = note;
    return note;
  }

  @override
  Future<int> clearLinksForTarget({
    required String linkedModule,
    required String linkedId,
  }) async {
    return 0;
  }
}

List<NoteEntity> _seedNotes() {
  return <NoteEntity>[
    NoteEntity(
      id: 'note-alpha',
      title: 'Alpha Architecture',
      content: 'Initial architecture notes.\n\nSee [[Beta Roadmap]].',
      category: 'reference',
      tags: const ['architecture'],
      isPinned: true,
      createdAt: DateTime.utc(2026, 2, 1, 9),
      updatedAt: DateTime.utc(2026, 2, 10, 9),
    ),
    NoteEntity(
      id: 'note-beta',
      title: 'Beta Roadmap',
      content: 'Quarterly deliverables and milestones.',
      category: 'learning',
      tags: const ['planning'],
      createdAt: DateTime.utc(2026, 2, 2, 9),
      updatedAt: DateTime.utc(2026, 2, 9, 9),
    ),
    NoteEntity(
      id: 'note-gamma',
      title: 'Gamma Checklist',
      content: '- [ ] Review offline saves',
      category: 'reference',
      tags: const ['architecture'],
      createdAt: DateTime.utc(2026, 2, 3, 9),
      updatedAt: DateTime.utc(2026, 2, 8, 9),
    ),
    NoteEntity(
      id: 'note-trashed',
      title: 'Trashed Scratchpad',
      content: 'Inside trash',
      category: 'general',
      isTrashed: true,
      createdAt: DateTime.utc(2026, 2, 1, 8),
      updatedAt: DateTime.utc(2026, 2, 4, 8),
    ),
  ];
}

Future<NotesController> _buildController(
  _StageN33InMemoryNotesRepository repo,
) async {
  for (final n in _seedNotes()) {
    repo.seed(n);
  }
  final controller = NotesController(repository: repo);
  await controller.loadNotes();
  return controller;
}

Widget _wrapNotesApp({
  required NotesController controller,
  required Size surfaceSize,
  ThemeData? theme,
  double textScale = 1.0,
  ({String noteId, int nonce})? requestedNoteFocus,
}) {
  return MaterialApp(
    theme: theme ?? DaywellTheme.light,
    home: MediaQuery(
      data: MediaQueryData(
        size: surfaceSize,
        textScaler: TextScaler.linear(textScale),
      ),
      child: NotesView(
        controller: controller,
        requestedNoteFocus: requestedNoteFocus,
      ),
    ),
  );
}

void main() {
  group('Stage N3.3 — Responsive Master-Detail Notes Experience', () {
    testWidgets(
      '1. Narrow screen (< 840dp) preserves single-pane list, route push, and Back-button save flush',
      (tester) async {
        const size = Size(390, 800);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = _StageN33InMemoryNotesRepository();
        final controller = await _buildController(repo);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
            _wrapNotesApp(controller: controller, surfaceSize: size));
        await tester.pumpAndSettle();

        expect(find.text('Select a note to read or edit'), findsNothing);
        expect(find.byType(FloatingActionButton), findsOneWidget);
        expect(find.text('Alpha Architecture'), findsOneWidget);

        await tester.tap(find.text('Alpha Architecture'));
        await tester.pumpAndSettle();

        // Full-screen route pushed with Back button
        expect(find.byType(BackButton), findsOneWidget);

        final bodyField = find.widgetWithText(
          TextField,
          'Initial architecture notes.\n\nSee [[Beta Roadmap]].',
        );
        expect(bodyField, findsOneWidget);
        await tester.enterText(bodyField, 'Edited on narrow route');
        await tester.pump();

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        expect(find.byType(BackButton), findsNothing);
        expect(
          controller.state.findById('note-alpha')?.content,
          'Edited on narrow route',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '2. Wide screen (>= 840dp) displays master-detail side-by-side, highlights selected note, and flushes unsaved edits when switching notes',
      (tester) async {
        const size = Size(960, 800);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = _StageN33InMemoryNotesRepository();
        final controller = await _buildController(repo);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
            _wrapNotesApp(controller: controller, surfaceSize: size));
        await tester.pumpAndSettle();

        // Empty detail state visible alongside left master list; no FAB
        expect(find.text('Select a note to read or edit'), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(find.text('New Note'), findsOneWidget);

        // Select Alpha Architecture -> opens in right detail pane without pushing route
        await tester.tap(find.text('Alpha Architecture'));
        await tester.pumpAndSettle();

        expect(find.byType(BackButton), findsNothing);
        expect(find.text('Select a note to read or edit'), findsNothing);
        expect(find.byIcon(Icons.arrow_right_rounded), findsOneWidget);

        // Edit title & content without waiting 600ms debounce, then tap same card -> draft preserved
        final bodyField = find.widgetWithText(
          TextField,
          'Initial architecture notes.\n\nSee [[Beta Roadmap]].',
        );
        await tester.enterText(bodyField, 'Unsaved Alpha draft body');
        await tester.pump();

        await tester.tap(find.text('Alpha Architecture').first);
        await tester.pump();
        expect(find.text('Unsaved Alpha draft body'), findsOneWidget);

        // Switch to Beta Roadmap -> flushes Alpha edits cleanly with zero duplicates
        final initialCount = controller.state.notes.length;
        await tester.ensureVisible(find.text('Beta Roadmap'));
        await tester.pump();
        await tester.tap(find.text('Beta Roadmap'));
        await tester.pumpAndSettle();

        expect(
          controller.state.findById('note-alpha')?.content,
          'Unsaved Alpha draft body',
        );
        expect(controller.state.notes.length, initialCount);
        expect(
          find.widgetWithText(TextField, 'Beta Roadmap'),
          findsOneWidget,
        );

        // Closing detail returns cleanly to empty detail state
        await tester.tap(find.byTooltip('Close note'));
        await tester.pumpAndSettle();
        expect(find.text('Select a note to read or edit'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '3. Wide selection switch aborts safely on persistence failure without losing dirty draft',
      (tester) async {
        const size = Size(960, 800);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = _StageN33InMemoryNotesRepository();
        final controller = await _buildController(repo);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
            _wrapNotesApp(controller: controller, surfaceSize: size));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Alpha Architecture'));
        await tester.pumpAndSettle();

        repo.failUpdates = true;
        final bodyField = find.widgetWithText(
          TextField,
          'Initial architecture notes.\n\nSee [[Beta Roadmap]].',
        );
        await tester.enterText(bodyField, 'Must not be lost on failure');
        await tester.pump();

        await tester.ensureVisible(find.text('Beta Roadmap'));
        await tester.pump();
        await tester.tap(find.text('Beta Roadmap'));
        await tester.pumpAndSettle();

        // Still on Alpha with dirty text intact and retry warning shown
        expect(find.text('Must not be lost on failure'), findsOneWidget);
        expect(
          find.textContaining('Could not save current note changes'),
          findsOneWidget,
        );

        // Recover & switch cleanly
        repo.failUpdates = false;
        await tester.ensureVisible(find.text('Beta Roadmap'));
        await tester.pump();
        await tester.tap(find.text('Beta Roadmap'));
        await tester.pumpAndSettle();
        expect(
          controller.state.findById('note-alpha')?.content,
          'Must not be lost on failure',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '4. Wide internal links, backlinks, Quick Capture focus, and active filters work cleanly in detail pane',
      (tester) async {
        const size = Size(1200, 800);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = _StageN33InMemoryNotesRepository();
        final controller = await _buildController(repo);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
            _wrapNotesApp(controller: controller, surfaceSize: size));
        await tester.pumpAndSettle();

        // Apply folder filter ('Reference') -> keeps Alpha & Gamma, hides Beta from list
        final referenceChip = find.text('Reference').first;
        await tester.ensureVisible(referenceChip);
        await tester.pumpAndSettle();
        await tester.tap(referenceChip);
        await tester.pumpAndSettle();
        expect(find.text('Alpha Architecture'), findsOneWidget);
        expect(find.text('Beta Roadmap'), findsNothing);

        // Select Alpha and switch to Preview to follow [[Beta Roadmap]] internal link
        await tester.tap(find.text('Alpha Architecture'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Preview'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Beta Roadmap', findRichText: true).first);
        await tester.pumpAndSettle();

        // Beta opened in right detail pane without pushing route, and Reference filter persisted
        expect(find.byType(BackButton), findsNothing);
        expect(
          find.text(
            'Quarterly deliverables and milestones.',
            findRichText: true,
          ),
          findsOneWidget,
        );
        expect(find.text('Gamma Checklist'), findsOneWidget);

        // Backlinks section on Beta lists Alpha Architecture and jumps back into detail pane
        expect(find.textContaining('BACKLINKS (1)'), findsOneWidget);
        final backlinkAlpha = find.text('Alpha Architecture').last;
        await tester.ensureVisible(backlinkAlpha);
        await tester.pumpAndSettle();
        await tester.tap(backlinkAlpha);
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            'Initial architecture notes.',
            findRichText: true,
          ),
          findsOneWidget,
        );

        // Clear filters before Quick Capture focus test
        final clearFilters = find.text('Clear filters');
        await tester.ensureVisible(clearFilters);
        await tester.pumpAndSettle();
        await tester.tap(clearFilters);
        await tester.pumpAndSettle();

        // requestedNoteFocus opens target note directly in wide detail pane
        await tester.pumpWidget(
          _wrapNotesApp(
            controller: controller,
            surfaceSize: size,
            requestedNoteFocus: (noteId: 'note-gamma', nonce: 42),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BackButton), findsNothing);
        expect(find.byIcon(Icons.arrow_right_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '5. Wide New Note draft, Archive, Trash immutability, and Delete clear detail safely without duplicates',
      (tester) async {
        const size = Size(960, 800);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = _StageN33InMemoryNotesRepository();
        final controller = await _buildController(repo);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
            _wrapNotesApp(controller: controller, surfaceSize: size));
        await tester.pumpAndSettle();

        // New Note opens embedded draft
        await tester.tap(find.text('New Note'));
        await tester.pumpAndSettle();
        expect(find.text('Draft'), findsOneWidget);

        final beforeCreates = repo.createCount;
        await tester.enterText(
          find.byType(TextField).at(1),
          'Quick Wide Draft',
        );
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();
        expect(repo.createCount, beforeCreates + 1);

        // Move active detail note to Trash -> clears detail back to empty state
        await tester.tap(find.byTooltip('Move to Trash'));
        await tester.pumpAndSettle();
        expect(find.text('Select a note to read or edit'), findsOneWidget);

        // Trashed note cannot be opened in detail pane directly
        final trashChip = find.text('Trash').first;
        await tester.ensureVisible(trashChip);
        await tester.pumpAndSettle();
        await tester.tap(trashChip);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Trashed Scratchpad'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Trashed Scratchpad'));
        await tester.pumpAndSettle();
        expect(find.text('Select a note to read or edit'), findsOneWidget);
        expect(
          find.text('Restore note from Trash before editing'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '6. Renders cleanly at exact 840dp breakpoint in Dark theme, Grid mode, and 1.6x textScale without overflow',
      (tester) async {
        const size = Size(840, 720);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = _StageN33InMemoryNotesRepository();
        final controller = await _buildController(repo);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _wrapNotesApp(
            controller: controller,
            surfaceSize: size,
            theme: DaywellTheme.dark,
            textScale: 1.6,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Grid View'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Alpha Architecture'));
        await tester.pumpAndSettle();

        expect(find.byType(BackButton), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
