import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/domain/notes/note_markdown.dart';
import 'package:personal_management_app/domain/notes/note_models.dart';
import 'package:personal_management_app/ui/screens/notes_view.dart';
import 'package:personal_management_app/ui/widgets/notes/note_markdown_preview.dart';

Map<String, dynamic> _loadChecklistVectors() {
  final candidates = <File>[
    File('../shared_foundation/fixtures/note_checklist_vectors.json'),
    File('shared_foundation/fixtures/note_checklist_vectors.json'),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
  }
  throw StateError(
    'Unable to locate shared_foundation/fixtures/note_checklist_vectors.json from ${Directory.current.path}',
  );
}

class _InMemoryNotesRepository implements INotesRepository {
  final Map<String, NoteEntity> store = <String, NoteEntity>{};

  void seed(NoteEntity note) {
    store[note.id] = note;
  }

  @override
  Future<NoteEntity> createNote(NoteEntity note) async {
    store[note.id] = note;
    return note;
  }

  @override
  Future<NoteEntity> updateNote(NoteEntity note) async {
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
}

void main() {
  final vectors = _loadChecklistVectors();

  group('Stage N2.3 — Shared Vectors & Pure Dart Checklist Toggling', () {
    test('matches all shared toggleCases identically', () {
      final cases = (vectors['toggleCases'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final testCase in cases) {
        final name = testCase['name'] as String;
        final toggled = testCase['toggled'] as bool;
        final result = NoteMarkdownParser.toggleChecklistAtLine(
          testCase['source'] as String,
          testCase['lineIndex'] as int,
        );
        if (!toggled) {
          expect(result, isNull, reason: name);
        } else {
          expect(result, isNotNull, reason: name);
          expect(result!.text, testCase['expectedText'], reason: name);
          expect(result.checked, testCase['expectedChecked'], reason: name);
          expect(result.lineIndex, testCase['lineIndex'], reason: name);
        }
      }
    });

    test('matches all shared selectionCases identically', () {
      final cases = (vectors['selectionCases'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final testCase in cases) {
        final name = testCase['name'] as String;
        final found = testCase['found'] as bool;
        final result = NoteMarkdownParser.getChecklistAtSelection(
          testCase['source'] as String,
          testCase['selectionStart'] as int,
          testCase['selectionEnd'] as int,
        );
        if (!found) {
          expect(result, isNull, reason: name);
        } else {
          expect(result, isNotNull, reason: name);
          expect(result!.lineIndex, testCase['lineIndex'], reason: name);
          expect(result.checked, testCase['checked'], reason: name);
        }
      }
    });

    test('handles rapid sequential toggles and leaves bullets, fenced blocks, and malformed syntax untouched', () {
      const source = [
        '# Plan',
        '',
        '- [ ] One',
        '- [x] Two',
        '- Ordinary bullet',
        '- [] Malformed',
        '```dart',
        '- [ ] In fence',
        '```',
      ].join('\n');

      var current = source;
      current = NoteMarkdownParser.toggleChecklistAtLine(current, 2)!.text;
      current = NoteMarkdownParser.toggleChecklistAtLine(current, 2)!.text;
      current = NoteMarkdownParser.toggleChecklistAtLine(current, 2)!.text;
      current = NoteMarkdownParser.toggleChecklistAtLine(current, 3)!.text;

      expect(
        current,
        [
          '# Plan',
          '',
          '- [x] One',
          '- [ ] Two',
          '- Ordinary bullet',
          '- [] Malformed',
          '```dart',
          '- [ ] In fence',
          '```',
        ].join('\n'),
      );

      expect(NoteMarkdownParser.toggleChecklistAtLine(current, 4), isNull);
      expect(NoteMarkdownParser.toggleChecklistAtLine(current, 5), isNull);
      expect(NoteMarkdownParser.toggleChecklistAtLine(current, 7), isNull);
    });
  });

  group('Stage N2.3 — NotesView Interactive Preview & Write Checklist Widgets', () {
    testWidgets(
      'Preview checkboxes toggle items independently, handle rapid taps, preserve surrounding Markdown, and autosave',
      (WidgetTester tester) async {
        const initialMarkdown = [
          '# Daily Checklist',
          '',
          '- [ ] First open',
          '- [x] Already done',
          '- Ordinary bullet',
          '- [] Broken item',
        ].join('\n');

        final repo = _InMemoryNotesRepository();
        repo.seed(
          NoteEntity(
            id: 'note-n23-1',
            title: 'Checklist Note',
            content: initialMarkdown,
            category: 'general',
          ),
        );
        final controller = NotesController(repository: repo);
        addTearDown(controller.dispose);
        await controller.loadNotes();

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: NotesView(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Checklist Note'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Preview'));
        await tester.pumpAndSettle();

        expect(find.byType(NoteMarkdownPreview), findsOneWidget);
        expect(find.byTooltip('Mark item complete'), findsOneWidget);
        expect(find.byTooltip('Mark item incomplete'), findsOneWidget);

        // Rapidly tap first item complete -> incomplete -> complete
        await tester.tap(find.byTooltip('Mark item complete'));
        await tester.pump();
        expect(find.byTooltip('Mark item incomplete'), findsNWidgets(2));
        await tester.tap(find.byTooltip('Mark item incomplete').first);
        await tester.pump();
        expect(find.byTooltip('Mark item complete'), findsOneWidget);
        await tester.tap(find.byTooltip('Mark item complete'));
        await tester.pump();
        expect(find.byTooltip('Mark item incomplete'), findsNWidgets(2));

        // Uncheck the second item independently
        await tester.tap(find.byTooltip('Mark item incomplete').last);
        await tester.pump();
        expect(find.byTooltip('Mark item complete'), findsOneWidget);
        expect(find.byTooltip('Mark item incomplete'), findsOneWidget);

        // Wait past 600ms debounce and verify exact Markdown persisted
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();

        const expectedAfterPreview = [
          '# Daily Checklist',
          '',
          '- [x] First open',
          '- [ ] Already done',
          '- Ordinary bullet',
          '- [] Broken item',
        ].join('\n');
        expect(repo.store['note-n23-1']?.content, expectedAfterPreview);

        // Switch back to Write — exact source intact
        await tester.tap(find.text('Write'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField).last).controller?.text,
          expectedAfterPreview,
        );
      },
    );

    testWidgets(
      'Write-mode contextual checklist button toggles active checklist line and preserves unsaved edits across Write/Preview switches',
      (WidgetTester tester) async {
        final repo = _InMemoryNotesRepository();
        repo.seed(
          NoteEntity(
            id: 'note-n23-2',
            title: 'Write Toggle Note',
            content: 'Intro\n- [ ] Draft item',
            category: 'general',
          ),
        );
        final controller = NotesController(repository: repo);
        addTearDown(controller.dispose);
        await controller.loadNotes();

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: NotesView(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Write Toggle Note'));
        await tester.pumpAndSettle();

        final bodyFieldFinder = find.byType(TextField).last;
        final bodyController =
            tester.widget<TextField>(bodyFieldFinder).controller!;

        // On Intro line -> contextual button absent
        bodyController.selection = const TextSelection.collapsed(offset: 2);
        await tester.pump();
        expect(find.text('Check item'), findsNothing);
        expect(find.text('Checked'), findsNothing);

        // Edit unsaved text on checklist line and place cursor there
        bodyController.value = const TextEditingValue(
          text: 'Intro edited\n- [ ] Draft item',
          selection: TextSelection.collapsed(offset: 22),
        );
        await tester.pump();
        expect(find.text('Check item'), findsOneWidget);

        // Toggle via contextual Write toolbar button
        await tester.tap(find.text('Check item'));
        await tester.pump();
        expect(bodyController.text, 'Intro edited\n- [x] Draft item');
        expect(bodyController.selection, const TextSelection.collapsed(offset: 22));
        expect(find.text('Checked'), findsOneWidget);

        // Immediately switch to Preview before debounce completes — unsaved edit & checked state preserved
        await tester.tap(find.text('Preview'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Intro edited'), findsOneWidget);
        expect(find.byTooltip('Mark item incomplete'), findsOneWidget);

        // Toggle back in Preview and navigate back to flush
        await tester.tap(find.byTooltip('Mark item incomplete'));
        await tester.pump();
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(repo.store['note-n23-2']?.content, 'Intro edited\n- [ ] Draft item');
      },
    );
  });
}
