import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/domain/notes/note_contracts.dart';
import 'package:personal_management_app/domain/notes/note_markdown.dart';
import 'package:personal_management_app/domain/notes/note_models.dart';
import 'package:personal_management_app/ui/screens/notes_view.dart';
import 'package:personal_management_app/ui/widgets/notes/note_markdown_preview.dart';

Map<String, dynamic> _loadMarkdownVectors() {
  final candidates = <File>[
    File('../shared_foundation/fixtures/note_markdown_vectors.json'),
    File('shared_foundation/fixtures/note_markdown_vectors.json'),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
  }
  throw StateError(
    'Unable to locate shared_foundation/fixtures/note_markdown_vectors.json from ${Directory.current.path}',
  );
}

String _serializeBlockType(NoteMarkdownBlock block) {
  switch (block.type) {
    case NoteMarkdownBlockType.heading:
      return 'heading:${block.level}';
    case NoteMarkdownBlockType.paragraph:
      return 'paragraph';
    case NoteMarkdownBlockType.bulletList:
      return 'bulletList:${block.listItems.length}';
    case NoteMarkdownBlockType.orderedList:
      return 'orderedList:${block.start}:${block.orderedItems.length}';
    case NoteMarkdownBlockType.checklist:
      return 'checklist:${block.checklistItems.map((e) => e.checked).join(',')}';
    case NoteMarkdownBlockType.blockquote:
      return 'blockquote:${block.quoteLines.length}';
    case NoteMarkdownBlockType.codeBlock:
      return 'codeBlock:${block.language}';
    case NoteMarkdownBlockType.horizontalRule:
      return 'horizontalRule';
  }
}

String _serializeInline(NoteMarkdownInline node) {
  switch (node.type) {
    case NoteMarkdownInlineType.text:
      return 'text:${node.text}';
    case NoteMarkdownInlineType.code:
      return 'code:${node.text}';
    case NoteMarkdownInlineType.link:
      return 'link:${node.text}|${node.url}';
    case NoteMarkdownInlineType.internalLink:
      return 'internalLink:${node.text}|${node.rawText}';
    case NoteMarkdownInlineType.bold:
      return 'bold:[${node.children.map(_serializeInline).join(',')}]';
    case NoteMarkdownInlineType.italic:
      return 'italic:[${node.children.map(_serializeInline).join(',')}]';
    case NoteMarkdownInlineType.strikethrough:
      return 'strike:[${node.children.map(_serializeInline).join(',')}]';
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
  final vectors = _loadMarkdownVectors();

  group('Stage N2.1 — Shared Markdown Vectors & Pure Dart Parser', () {
    test('matches all shared blockCases identically', () {
      final blockCases =
          (vectors['blockCases'] as List<dynamic>).cast<Map<String, dynamic>>();
      for (final testCase in blockCases) {
        final name = testCase['name'] as String;
        final markdown = testCase['markdown'] as String;
        final expectedBlockTypes =
            (testCase['expectedBlockTypes'] as List<dynamic>).cast<String>();

        final doc = NoteMarkdownParser.parse(markdown);
        expect(
          doc.blocks.map(_serializeBlockType).toList(),
          expectedBlockTypes,
          reason: 'Block types mismatch for $name',
        );

        final expectedCodeBlocks =
            testCase['expectedCodeBlocks'] as List<dynamic>?;
        if (expectedCodeBlocks != null) {
          final actualCodeBlocks = doc.blocks
              .where((b) => b.type == NoteMarkdownBlockType.codeBlock)
              .map(
                (b) => <String, String>{
                  'language': b.language,
                  'code': b.code,
                },
              )
              .toList();
          expect(actualCodeBlocks, expectedCodeBlocks, reason: name);
        }

        final expectedPlainText = testCase['expectedPlainText'] as String?;
        if (expectedPlainText != null) {
          expect(
            NoteMarkdownParser.toPlainText(markdown),
            expectedPlainText,
            reason: 'Plain text mismatch for $name',
          );
        }
      }
    });

    test('matches all shared inlineCases identically', () {
      final inlineCases = (vectors['inlineCases'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final testCase in inlineCases) {
        final name = testCase['name'] as String;
        final input = testCase['input'] as String;
        final expectedTypes =
            (testCase['expectedTypes'] as List<dynamic>).cast<String>();

        final parsed = NoteMarkdownParser.parseInlines(input);
        expect(
          parsed.map(_serializeInline).toList(),
          expectedTypes,
          reason: 'Inline AST mismatch for $name',
        );
      }
    });

    test('matches all shared urlSafetyCases identically', () {
      final urlCases = (vectors['urlSafetyCases'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final testCase in urlCases) {
        final url = testCase['url'] as String;
        final expectedSafe = testCase['expectedSafe'] as String?;
        expect(
          NoteMarkdownParser.sanitizeUrl(url),
          expectedSafe,
          reason: 'URL sanitization mismatch for "$url"',
        );
      }
    });

    test('handles malformed, empty, and deeply nested markdown safely', () {
      expect(NoteMarkdownParser.parse(null).blocks, isEmpty);
      expect(NoteMarkdownParser.parse('').blocks, isEmpty);
      expect(NoteMarkdownParser.toPlainText('  \n\n\t '), '');

      const malformed =
          '***unclosed **bold *italic ~~strike `code\n```dart\nfinal x = 1;';
      final doc = NoteMarkdownParser.parse(malformed);
      expect(doc.blocks.length, 2);
      expect(doc.blocks.first.type, NoteMarkdownBlockType.paragraph);
      expect(doc.blocks.last.type, NoteMarkdownBlockType.codeBlock);

      final deep = '${'**' * 20}core${'**' * 20}';
      final parsedDeep = NoteMarkdownParser.parseInlines(deep);
      expect(
        NoteMarkdownParser.inlinesToPlainText(parsedDeep).contains('core'),
        isTrue,
      );
    });
  });

  group('Stage N2.1 — Flutter Preview Widget & Editor Write/Preview Toggle',
      () {
    testWidgets(
      'NoteMarkdownPreview renders all syntax safely, stays selectable, and avoids long-line overflow',
      (WidgetTester tester) async {
        final longCodeLine = 'final veryLongIdentifier = "${'x' * 240}";';
        final markdown = [
          '# Heading One',
          '## Heading Two',
          '### Heading Three',
          '',
          'Paragraph with **bold**, *italic*, ~~strike~~, `inlineCode`, and [Safe](https://daywell.example).',
          'Unsafe [Bad](javascript:alert(1)) and <script>alert(1)</script>',
          '',
          '- Bullet dash',
          '* Bullet star',
          '',
          '1. Number one',
          '2. Number two',
          '',
          '- [ ] Unchecked task',
          '- [x] Checked task',
          '',
          '> Blockquote line',
          '',
          '---',
          '',
          '```dart',
          longCodeLine,
          '```',
        ].join('\n');

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  child: NoteMarkdownPreview(content: markdown),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(SelectionArea), findsOneWidget);
        expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);
        expect(
          find.byIcon(Icons.check_box_outline_blank_rounded),
          findsOneWidget,
        );
        expect(find.byType(Divider), findsOneWidget);
        expect(find.text('DART'), findsOneWidget);
        expect(find.textContaining('javascript:'), findsNothing);
        expect(
            find.textContaining('<script>alert(1)</script>',
                findRichText: true),
            findsOneWidget);
      },
    );

    testWidgets(
      'NoteMarkdownPreview shows empty guidance for blank notes',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: const Scaffold(
              body: NoteMarkdownPreview(content: '  \n\n '),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Nothing to preview yet. Switch to Write to add note content.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'NotesView Write/Preview switch never mutates or trims original Markdown source',
      (WidgetTester tester) async {
        const rawMarkdown =
            '# Weekly Reflection\n\n  Indented line  \n- [x] Ship N2.1\n\n';
        final repo = _InMemoryNotesRepository();
        repo.seed(
          NoteEntity(
            id: 'note-md-1',
            title: 'Reflection',
            content: rawMarkdown,
            category: 'reflection',
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

        // List card snippet strips Markdown markers without modifying stored source
        expect(repo.store['note-md-1']?.content, rawMarkdown);

        // Open existing note in Write mode
        final noteCardTitle = find.descendant(
          of: find.byType(ListView),
          matching: find.text('Reflection'),
        );
        await tester.tap(noteCardTitle.first);
        await tester.pumpAndSettle();

        expect(find.text('Write'), findsOneWidget);
        expect(find.text('Preview'), findsOneWidget);
        expect(find.byType(TextField), findsNWidgets(2));
        expect(
          tester
              .widget<TextField>(find.byType(TextField).last)
              .controller
              ?.text,
          rawMarkdown,
        );

        // Switch to Preview mode
        await tester.tap(find.text('Preview'));
        await tester.pumpAndSettle();

        expect(find.byType(NoteMarkdownPreview), findsOneWidget);
        expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);
        expect(find.byType(TextField), findsNothing);

        // Switch back to Write mode — exact source and trailing newlines intact
        await tester.tap(find.text('Write'));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<TextField>(find.byType(TextField).last)
              .controller
              ?.text,
          rawMarkdown,
        );

        // Pop editor and verify persisted store never changed
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(repo.store['note-md-1']?.content, rawMarkdown);
      },
    );
  });
}
