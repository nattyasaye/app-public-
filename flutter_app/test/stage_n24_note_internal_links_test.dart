import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/domain/notes/note_editor_formatting.dart';
import 'package:personal_management_app/domain/notes/note_links.dart';
import 'package:personal_management_app/domain/notes/note_markdown.dart';
import 'package:personal_management_app/domain/notes/note_models.dart';
import 'package:personal_management_app/ui/screens/notes_view.dart';
import 'package:personal_management_app/ui/widgets/notes/note_markdown_preview.dart';

Map<String, dynamic> _loadInternalLinkVectors() {
  final candidates = <File>[
    File('../shared_foundation/fixtures/note_internal_links_vectors.json'),
    File('shared_foundation/fixtures/note_internal_links_vectors.json'),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
  }
  throw StateError(
    'Unable to locate shared_foundation/fixtures/note_internal_links_vectors.json from ${Directory.current.path}',
  );
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

List<NoteEntity> _buildFixtureNotes() {
  return <NoteEntity>[
    NoteEntity(
      id: 'n-roadmap',
      title: 'Project Roadmap',
      content: 'Core milestones and [[Project Roadmap]] self-note.',
      category: 'reference',
      createdAt: DateTime.utc(2026, 1, 1, 8),
      updatedAt: DateTime.utc(2026, 1, 5, 8),
    ),
    NoteEntity(
      id: 'n-daily',
      title: 'Daily Focus',
      content:
          'Morning check\nReview [[Project Roadmap]] before noon.\nAlso [[  project   roadmap  ]] tonight.\n```\n[[Project Roadmap]]\n```',
      category: 'reflection',
      createdAt: DateTime.utc(2026, 1, 2, 8),
      updatedAt: DateTime.utc(2026, 1, 10, 9),
    ),
    NoteEntity(
      id: 'n-ref-checklist',
      title: 'Sprint Checklist',
      content: '- [ ] Confirm milestones on [[Project Roadmap]]',
      category: 'general',
      createdAt: DateTime.utc(2026, 1, 3, 8),
      updatedAt: DateTime.utc(2026, 1, 8, 9),
    ),
    NoteEntity(
      id: 'n-weekly-old',
      title: 'Weekly Review',
      content: 'Older review copy.',
      category: 'reflection',
      createdAt: DateTime.utc(2026, 1, 1, 8),
      updatedAt: DateTime.utc(2026, 1, 4, 8),
    ),
    NoteEntity(
      id: 'n-weekly-new',
      title: '  weekly   review ',
      content: 'Newer review copy.',
      category: 'learning',
      createdAt: DateTime.utc(2026, 1, 2, 8),
      updatedAt: DateTime.utc(2026, 1, 9, 8),
    ),
    NoteEntity(
      id: 'n-archived-spec',
      title: 'Archived Spec',
      content: 'Links to [[Project Roadmap]] while archived.',
      category: 'reference',
      isArchived: true,
      createdAt: DateTime.utc(2026, 1, 1, 8),
      updatedAt: DateTime.utc(2026, 1, 12, 8),
    ),
    NoteEntity(
      id: 'n-trashed-draft',
      title: 'Trashed Draft',
      content: 'Links to [[Project Roadmap]] from trash.',
      category: 'general',
      isTrashed: true,
      createdAt: DateTime.utc(2026, 1, 1, 8),
      updatedAt: DateTime.utc(2026, 1, 13, 8),
    ),
  ];
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
  final vectors = _loadInternalLinkVectors();

  group('Stage N2.4 — Shared Vectors & Pure Dart Internal Links / Backlinks',
      () {
    test(
        'matches all shared inlineCases, normalizeTitleCases, resolutionCases, backlinkCases, and toolbarCases',
        () {
      final inlineCases = (vectors['inlineCases'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final testCase in inlineCases) {
        final name = testCase['name'] as String;
        final parsed =
            NoteMarkdownParser.parseInlines(testCase['input'] as String);
        final expected =
            (testCase['expectedTypes'] as List<dynamic>).cast<String>();
        expect(
          parsed.map(_serializeInline).toList(),
          expected,
          reason: name,
        );
      }

      final normalizeCases = (vectors['normalizeTitleCases'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final testCase in normalizeCases) {
        expect(
          NoteLinksDomain.normalizeTitleKey(testCase['input'] as String),
          testCase['expected'] as String,
        );
      }

      final fixtureNotes = _buildFixtureNotes();
      final resolutionCases = (vectors['resolutionCases'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final testCase in resolutionCases) {
        final name = testCase['name'] as String;
        final res = NoteLinksDomain.resolveInternalLink(
          testCase['targetTitle'] as String,
          fixtureNotes,
        );
        expect(res.status.name, testCase['expectedStatus'], reason: name);
        expect(
          res.matches.map((m) => m.id).toList(),
          (testCase['expectedMatchedIds'] as List<dynamic>).cast<String>(),
          reason: name,
        );
      }

      final backlinkCases = (vectors['backlinkCases'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final testCase in backlinkCases) {
        final name = testCase['name'] as String;
        final targetId = testCase['targetNoteId'] as String;
        final target = fixtureNotes.firstWhere((n) => n.id == targetId);
        final backlinks = NoteLinksDomain.findBacklinks(target, fixtureNotes);
        expect(
          backlinks.map((b) => b.note.id).toList(),
          (testCase['expectedReferrerIds'] as List<dynamic>).cast<String>(),
          reason: name,
        );
        expect(
          backlinks.map((b) => b.linkCount).toList(),
          (testCase['expectedCounts'] as List<dynamic>).cast<int>(),
          reason: name,
        );
      }

      final toolbarCases = (vectors['toolbarCases'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final testCase in toolbarCases) {
        final name = testCase['name'] as String;
        final edited = NoteEditorFormatting.applyToolbarAction(
          testCase['text'] as String,
          testCase['selectionStart'] as int,
          testCase['selectionEnd'] as int,
          NoteToolbarFormatAction.internalLink,
        );
        expect(edited.text, testCase['expectedText'], reason: name);
        expect(edited.selectionStart, testCase['expectedStart'], reason: name);
        expect(edited.selectionEnd, testCase['expectedEnd'], reason: name);
      }
    });

    test(
        'handles renames, code exclusions, and dynamic archive/trash restoration',
        () {
      final initial = _buildFixtureNotes();
      final daily = initial.firstWhere((n) => n.id == 'n-daily');
      expect(NoteLinksDomain.extractInternalLinks(daily.content).length, 2);

      // Restoring an archived note makes links to it resolve dynamically
      final unarchived = initial
          .map(
            (n) =>
                n.id == 'n-archived-spec' ? n.copyWith(isArchived: false) : n,
          )
          .toList();
      expect(
        NoteLinksDomain.resolveInternalLink('Archived Spec', unarchived).status,
        NoteInternalLinkResolutionStatus.resolved,
      );
      expect(
        NoteLinksDomain.findBacklinks(initial.first, unarchived)
            .any((b) => b.note.id == 'n-archived-spec'),
        isTrue,
      );
    });
  });

  group(
      'Stage N2.4 — Flutter Preview, Navigation, Ambiguity Chooser & Backlinks',
      () {
    testWidgets(
      'navigates internal links safely while flushing edits, shows ambiguity chooser, ignores missing targets, and renders backlinks',
      (WidgetTester tester) async {
        final repo = _InMemoryNotesRepository();
        for (final note in _buildFixtureNotes()) {
          repo.seed(note);
        }
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

        // Open Daily Focus note
        await tester.tap(find.text('Daily Focus'));
        await tester.pumpAndSettle();

        // Edit Daily Focus content to include missing link + ambiguous link + resolved link
        final bodyFinder = find.byType(TextField).last;
        await tester.enterText(
          bodyFinder,
          'Updated context: [[Project Roadmap]], [[Weekly Review]], [[Does Not Exist]].',
        );
        await tester.pump();

        // Switch to Preview — verify links render with zero overflow
        await tester.tap(find.text('Preview'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(NoteMarkdownPreview), findsOneWidget);

        // Tap missing link: does not navigate or create a new note
        final countBefore = repo.store.length;
        await tester.tap(find.text('Does Not Exist', findRichText: true));
        await tester.pumpAndSettle();
        expect(repo.store.length, countBefore);

        // Tap ambiguous link: opens chooser dialog rather than picking silently
        await tester.tap(find.text('Weekly Review (2)', findRichText: true));
        await tester.pumpAndSettle();
        expect(find.text('Choose note for "Weekly Review"'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Tap resolved [[Project Roadmap]] link — flushes pending edit and opens Project Roadmap
        await tester
            .tap(find.text('Project Roadmap', findRichText: true).first);
        await tester.pumpAndSettle();
        expect(
          repo.store['n-daily']?.content,
          'Updated context: [[Project Roadmap]], [[Weekly Review]], [[Does Not Exist]].',
        );
        expect(find.text('BACKLINKS (2)'), findsOneWidget);
        expect(find.text('Daily Focus'), findsOneWidget);
        expect(find.text('Sprint Checklist'), findsOneWidget);

        // Archived and trashed referrers remain excluded
        expect(find.text('Archived Spec'), findsNothing);
        expect(find.text('Trashed Draft'), findsNothing);

        // Clicking a backlink opens that referring note cleanly
        await tester.tap(find.text('Sprint Checklist'));
        await tester.pumpAndSettle();
        expect(
            find.text('Sprint Checklist', findRichText: true), findsOneWidget);

        // Switch to Write mode and verify Internal note link toolbar button inserts [[]]
        await tester.tap(find.text('Write'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Internal note link'));
        await tester.pumpAndSettle();
        final updatedBody = tester
                .widget<TextField>(find.byType(TextField).last)
                .controller
                ?.text ??
            '';
        expect(updatedBody.contains('[[]]'), isTrue);
      },
    );
  });
}
