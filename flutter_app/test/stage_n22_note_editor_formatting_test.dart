import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/domain/notes/note_editor_formatting.dart';
import 'package:personal_management_app/domain/notes/note_models.dart';
import 'package:personal_management_app/ui/screens/notes_view.dart';
import 'package:personal_management_app/ui/widgets/notes/note_markdown_preview.dart';

Map<String, dynamic> _loadFormattingVectors() {
  final candidates = <File>[
    File('../shared_foundation/fixtures/note_editor_formatting_vectors.json'),
    File('shared_foundation/fixtures/note_editor_formatting_vectors.json'),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
  }
  throw StateError(
    'Unable to locate shared_foundation/fixtures/note_editor_formatting_vectors.json from ${Directory.current.path}',
  );
}

NoteToolbarFormatAction _parseAction(String raw) {
  switch (raw) {
    case 'heading2':
      return NoteToolbarFormatAction.heading2;
    case 'bold':
      return NoteToolbarFormatAction.bold;
    case 'italic':
      return NoteToolbarFormatAction.italic;
    case 'strikethrough':
      return NoteToolbarFormatAction.strikethrough;
    case 'bulletList':
      return NoteToolbarFormatAction.bulletList;
    case 'numberedList':
      return NoteToolbarFormatAction.numberedList;
    case 'checklist':
      return NoteToolbarFormatAction.checklist;
    case 'blockquote':
      return NoteToolbarFormatAction.blockquote;
    case 'inlineCode':
      return NoteToolbarFormatAction.inlineCode;
    case 'codeBlock':
      return NoteToolbarFormatAction.codeBlock;
    default:
      throw ArgumentError('Unknown action: $raw');
  }
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
  Future<int> clearLinksForTarget({
    required String linkedModule,
    required String linkedId,
  }) async {
    return 0;
  }

  @override
  Future<List<NoteEntity>> searchNotes(String query) async {
    return store.values
        .where((n) => !n.isTrashed && n.matchesQuery(query))
        .toList();
  }
}

void main() {
  final vectors = _loadFormattingVectors();

  group('Stage N2.2 — Shared Vectors & Pure Dart Editor Formatting', () {
    test('matches all shared toolbarCases identically', () {
      final cases = (vectors['toolbarCases'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final testCase in cases) {
        final name = testCase['name'] as String;
        final result = NoteEditorFormatting.applyToolbarAction(
          testCase['text'] as String,
          testCase['selectionStart'] as int,
          testCase['selectionEnd'] as int,
          _parseAction(testCase['action'] as String),
        );
        expect(result.text, testCase['expectedText'], reason: name);
        expect(result.selectionStart, testCase['expectedStart'], reason: name);
        expect(result.selectionEnd, testCase['expectedEnd'], reason: name);
      }
    });

    test('matches all shared enterCases identically', () {
      final cases =
          (vectors['enterCases'] as List<dynamic>).cast<Map<String, dynamic>>();
      for (final testCase in cases) {
        final name = testCase['name'] as String;
        final handled = testCase['handled'] as bool;
        final result = NoteEditorFormatting.applySmartEnter(
          testCase['text'] as String,
          testCase['selectionStart'] as int,
          testCase['selectionEnd'] as int,
        );
        if (!handled) {
          expect(result, isNull, reason: name);
        } else {
          expect(result, isNotNull, reason: name);
          expect(result!.text, testCase['expectedText'], reason: name);
          expect(result.selectionStart, testCase['expectedStart'],
              reason: name);
          expect(result.selectionEnd, testCase['expectedEnd'], reason: name);
        }
      }
    });

    test('matches all shared backspaceCases identically', () {
      final cases = (vectors['backspaceCases'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final testCase in cases) {
        final name = testCase['name'] as String;
        final handled = testCase['handled'] as bool;
        final result = NoteEditorFormatting.applySmartBackspace(
          testCase['text'] as String,
          testCase['selectionStart'] as int,
          testCase['selectionEnd'] as int,
        );
        if (!handled) {
          expect(result, isNull, reason: name);
        } else {
          expect(result, isNotNull, reason: name);
          expect(result!.text, testCase['expectedText'], reason: name);
          expect(result.selectionStart, testCase['expectedStart'],
              reason: name);
          expect(result.selectionEnd, testCase['expectedEnd'], reason: name);
        }
      }
    });

    test('handles multiline prefixes, prefix replacement, and fenced isolation',
        () {
      final stepped = NoteEditorFormatting.applyToolbarAction(
        '  - One\n\n  - Two',
        0,
        16,
        NoteToolbarFormatAction.numberedList,
      );
      expect(stepped.text, '  1. One\n\n  2. Two');

      final toggledOff = NoteEditorFormatting.applyToolbarAction(
        stepped.text,
        stepped.selectionStart,
        stepped.selectionEnd,
        NoteToolbarFormatAction.numberedList,
      );
      expect(toggledOff.text, '  One\n\n  Two');

      final nineToTen = NoteEditorFormatting.applySmartEnter(
        '  9. Ninth',
        10,
        10,
      );
      expect(nineToTen, isNotNull);
      expect(nineToTen!.text, '  9. Ninth\n  10. ');
      expect(nineToTen.selectionStart, 17);

      expect(
        NoteEditorFormatting.applySmartEnter('```\n- inside', 12, 12),
        isNull,
      );
      expect(
        NoteEditorFormatting.applySmartBackspace('```\n- ', 6, 6),
        isNull,
      );
    });
  });

  group('Stage N2.2 — NotesView Toolbar & Smart List Continuation Widgets', () {
    testWidgets(
      'Toolbar exposes all 10 controls, formats selections & cursors without stealing focus, and autosaves cleanly',
      (WidgetTester tester) async {
        final repo = _InMemoryNotesRepository();
        repo.seed(
          NoteEntity(
            id: 'note-n22-1',
            title: 'Formatting Check',
            content: 'Hello world\nFirst item',
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

        await tester.tap(find.text('Formatting Check'));
        await tester.pumpAndSettle();

        const expectedTooltips = <String>[
          'Heading 2',
          'Bold',
          'Italic',
          'Strikethrough',
          'Bulleted list',
          'Numbered list',
          'Checklist',
          'Blockquote',
          'Inline code',
          'Code block',
        ];
        for (final tooltip in expectedTooltips) {
          expect(find.byTooltip(tooltip), findsOneWidget);
        }

        final bodyFieldFinder = find.byType(TextField).last;
        final bodyController =
            tester.widget<TextField>(bodyFieldFinder).controller!;

        // 1. Select "world" and tap Bold
        bodyController.selection =
            const TextSelection(baseOffset: 6, extentOffset: 11);
        await tester.pump();
        await tester.tap(find.byTooltip('Bold'));
        await tester.pump();
        expect(bodyController.text, 'Hello **world**\nFirst item');
        expect(
          bodyController.selection,
          const TextSelection(baseOffset: 8, extentOffset: 13),
        );

        // 2. Tap Bold again — toggles off cleanly without duplicating markers
        await tester.tap(find.byTooltip('Bold'));
        await tester.pump();
        expect(bodyController.text, 'Hello world\nFirst item');

        // 3. Collapsed cursor on second line + Checklist + Numbered list replacement
        bodyController.selection = const TextSelection.collapsed(offset: 17);
        await tester.pump();
        await tester.tap(find.byTooltip('Checklist'));
        await tester.pump();
        expect(bodyController.text, 'Hello world\n- [ ] First item');

        await tester.tap(find.byTooltip('Numbered list'));
        await tester.pump();
        expect(bodyController.text, 'Hello world\n1. First item');

        // 4. Wait past 650ms debounce and confirm raw Markdown persisted
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();
        expect(repo.store['note-n22-1']?.content, 'Hello world\n1. First item');

        // 5. Switch to Preview and back to Write without modifying raw Markdown
        await tester.tap(find.text('Preview'));
        await tester.pumpAndSettle();
        expect(find.byType(NoteMarkdownPreview), findsOneWidget);
        await tester.tap(find.text('Write'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byType(TextField).last)
              .controller
              ?.text,
          'Hello world\n1. First item',
        );
      },
    );

    testWidgets(
      'Smart Enter continues & exits lists/blockquotes and Smart Backspace exits empty items via IME edits',
      (WidgetTester tester) async {
        final repo = _InMemoryNotesRepository();
        repo.seed(
          NoteEntity(
            id: 'note-n22-2',
            title: 'Smart List Check',
            content: '- First',
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

        await tester.tap(find.text('Smart List Check'));
        await tester.pumpAndSettle();

        final bodyFieldFinder = find.byType(TextField).last;
        await tester.showKeyboard(bodyFieldFinder);
        await tester.pump();

        final bodyController =
            tester.widget<TextField>(bodyFieldFinder).controller!;
        bodyController.selection = const TextSelection.collapsed(offset: 7);
        await tester.pump();

        // Simulate Enter after "- First" -> "- First\n- "
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '- First\n',
            selection: TextSelection.collapsed(offset: 8),
          ),
        );
        await tester.pump();
        expect(bodyController.text, '- First\n- ');
        expect(bodyController.selection,
            const TextSelection.collapsed(offset: 10));

        // Simulate Enter on empty "- " -> exits list to "- First\n"
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '- First\n- \n',
            selection: TextSelection.collapsed(offset: 11),
          ),
        );
        await tester.pump();
        expect(bodyController.text, '- First\n');
        expect(
            bodyController.selection, const TextSelection.collapsed(offset: 8));

        // Simulate Backspace on empty checklist line below text
        bodyController.value = const TextEditingValue(
          text: 'Keep line\n- [ ] ',
          selection: TextSelection.collapsed(offset: 16),
        );
        await tester.pump();
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'Keep line\n- [ ]',
            selection: TextSelection.collapsed(offset: 15),
          ),
        );
        await tester.pump();
        expect(bodyController.text, 'Keep line\n');
        expect(bodyController.selection,
            const TextSelection.collapsed(offset: 10));

        // Inside fenced code block, Enter does not insert list prefix
        bodyController.value = const TextEditingValue(
          text: '```md\n- literal',
          selection: TextSelection.collapsed(offset: 15),
        );
        await tester.pump();
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '```md\n- literal\n',
            selection: TextSelection.collapsed(offset: 16),
          ),
        );
        await tester.pump();
        expect(bodyController.text, '```md\n- literal\n');

        // Back button flushes dirty state cleanly
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(repo.store['note-n22-2']?.content, '```md\n- literal\n');
      },
    );
  });
}
