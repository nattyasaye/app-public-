import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/domain/notes/note_markdown_export.dart';
import 'package:personal_management_app/domain/notes/note_models.dart';
import 'package:personal_management_app/services/export/note_markdown_io_service.dart';
import 'package:personal_management_app/ui/app_state.dart';
import 'package:personal_management_app/ui/screens/notes_view.dart';
import 'package:share_plus/share_plus.dart';

import 'support/sqlite_test_helper.dart';

NoteEntity _makeNote({
  required String id,
  required String title,
  String content = '',
  String category = 'general',
  bool isArchived = false,
  bool isTrashed = false,
  String? projectId,
  String? linkedModule,
  String? linkedId,
}) {
  final now = DateTime.utc(2026, 3, 20, 9);
  return NoteEntity(
    id: id,
    title: title,
    content: content,
    category: category,
    isArchived: isArchived,
    isTrashed: isTrashed,
    projectId: projectId,
    linkedModule: linkedModule,
    linkedId: linkedId,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  setUpAll(configureSqliteForHostTests);

  tearDown(() {
    NoteMarkdownIoService.debugExportOverride = null;
  });

  group('Stage N5.4 — Notes Markdown Export & Sharing (Flutter)', () {
    test(
      '1. Preserves Markdown headings, lists, checklists, internal links, Unicode, and empty content verbatim without expanding linked records',
      () {
        const richBody = '''## Daily Plan
- [ ] Audit backup
- [x] Sync [[Ethiopia Calendar Rules]]

> Keep notes pure Markdown.

```dart
const cents = 4200;
```''';

        final richResult = NoteMarkdownExportHelper.buildExport(
          _makeNote(
            id: 'n-rich',
            title: 'Sprint Plan',
            content: richBody,
            projectId: 'proj-1',
            linkedModule: 'calendar',
            linkedId: 'evt-1',
          ),
        );
        expect(richResult.ok, isTrue);
        expect(richResult.filename, 'Sprint Plan.md');
        expect(richResult.markdownContent, '# Sprint Plan\n\n$richBody');
        expect(richResult.markdownContent.contains('proj-1'), isFalse);
        expect(richResult.markdownContent.contains('evt-1'), isFalse);

        const unicodeTitle = 'የዛሬ ዕቅድ — Café';
        const unicodeBody = 'ዛሬ:\n- [ ] የ[[ሳምንታዊ እቅድ]] ማስታወሻ';
        final unicodeResult = NoteMarkdownExportHelper.buildExport(
          _makeNote(id: 'n-eth', title: unicodeTitle, content: unicodeBody),
        );
        expect(unicodeResult.ok, isTrue);
        expect(unicodeResult.filename, '$unicodeTitle.md');
        expect(
          unicodeResult.markdownContent,
          '# $unicodeTitle\n\n$unicodeBody',
        );

        final emptyBodyResult = NoteMarkdownExportHelper.buildExport(
          _makeNote(id: 'n-empty', title: 'Empty Body Note', content: ''),
        );
        expect(emptyBodyResult.ok, isTrue);
        expect(emptyBodyResult.filename, 'Empty Body Note.md');
        expect(emptyBodyResult.markdownContent, '# Empty Body Note\n');
      },
    );

    test(
      '2. Sanitizes filenames for empty titles, OS-illegal chars, double .md, Windows reserved names, and surrogate boundaries',
      () {
        expect(NoteMarkdownExportHelper.buildFilename(''), 'Untitled Note.md');
        expect(
          NoteMarkdownExportHelper.buildFilename('   \n\t '),
          'Untitled Note.md',
        );
        expect(
          NoteMarkdownExportHelper.buildFilename('///\\\\***???'),
          'Untitled Note.md',
        );
        expect(NoteMarkdownExportHelper.buildFilename('.md'), 'Untitled Note.md');
        expect(
          NoteMarkdownExportHelper.buildFilename('Q1/Q2: Plan? <Final>|"*'),
          'Q1-Q2- Plan- -Final.md',
        );
        expect(NoteMarkdownExportHelper.buildFilename('Spec.MD.md'), 'Spec.md');
        expect(NoteMarkdownExportHelper.buildFilename('CON'), 'CON-note.md');
        expect(NoteMarkdownExportHelper.buildFilename('com3'), 'com3-note.md');

        final longFilename =
            NoteMarkdownExportHelper.buildFilename('A' * 160);
        expect(longFilename.endsWith('.md'), isTrue);
        expect(
          longFilename.length,
          NoteMarkdownExportHelper.maxFilenameStemLength + '.md'.length,
        );
      },
    );

    test(
      '3. Rejects trashed notes fail-closed and writes UTF-8 .md file to temporary storage for OS sharing with PlatformException text fallback',
      () async {
        final tempDir =
            await Directory.systemTemp.createTemp('daywell_n54_note_export_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        var shareAttempts = 0;
        final trashedOutcome = await NoteMarkdownIoService.exportAndShareNote(
          _makeNote(
            id: 'n-trash',
            title: 'Trashed Note',
            content: 'Should not write',
            isTrashed: true,
          ),
          tempDirProvider: () async => tempDir,
          shareFileOverride: (XFile _, String __) async {
            shareAttempts += 1;
          },
        );
        expect(trashedOutcome.ok, isFalse);
        expect(trashedOutcome.error, contains('Trash'));
        expect(shareAttempts, 0);
        expect(await tempDir.list().isEmpty, isTrue);

        XFile? sharedFile;
        String? sharedSubject;
        final okOutcome = await NoteMarkdownIoService.exportAndShareNote(
          _makeNote(
            id: 'n-amh',
            title: 'የዕለት ማስታወሻ',
            content: '- [ ] [[ግብ]] checklist item',
          ),
          tempDirProvider: () async => tempDir,
          shareFileOverride: (XFile file, String subject) async {
            sharedFile = file;
            sharedSubject = subject;
          },
        );
        expect(okOutcome.ok, isTrue);
        expect(okOutcome.usedTextFallback, isFalse);
        expect(okOutcome.filename, 'የዕለት ማስታወሻ.md');
        expect(sharedFile, isNotNull);
        expect(sharedFile!.mimeType, 'text/markdown');
        expect(sharedFile!.name, 'የዕለት ማስታወሻ.md');
        expect(sharedSubject, 'የዕለት ማስታወሻ');
        final bytesOnDisk =
            await File(sharedFile!.path).readAsString(encoding: utf8);
        expect(bytesOnDisk, '# የዕለት ማስታወሻ\n\n- [ ] [[ግብ]] checklist item');

        String? fallbackText;
        final fallbackOutcome = await NoteMarkdownIoService.exportAndShareNote(
          _makeNote(id: 'n-fb', title: 'Fallback Test', content: 'Body line'),
          tempDirProvider: () async => tempDir,
          shareFileOverride: (XFile _, String __) async {
            throw const MissingPluginException('No platform share plugin');
          },
          shareTextOverride: (String text, String subject) async {
            fallbackText = text;
          },
        );
        expect(fallbackOutcome.ok, isTrue);
        expect(fallbackOutcome.usedTextFallback, isTrue);
        expect(fallbackText, '# Fallback Test\n\nBody line');
      },
    );

    testWidgets(
      '4. Flushes pending editor changes before exporting/sharing in NotesView and hides export from trashed cards while surfacing feedback SnackBars',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1024, 800));
        addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

        final db = AppDatabase(NativeDatabase.memory());
        final appState = AppStateManager(db: db);
        await tester.runAsync(() async {
          await appState.initialize();
          await appState.notesRepository.saveNote(
            _makeNote(
              id: 'n-live',
              title: 'Initial Export Title',
              content: '- [ ] Initial task',
            ),
          );
          await appState.notesRepository.saveNote(
            _makeNote(
              id: 'n-trash',
              title: 'Trashed Hidden Note',
              content: 'Deleted note',
              isTrashed: true,
            ),
          );
          await appState.notesController.loadNotes();
        });
        addTearDown(() => appState.dispose());

        final exportedSnapshots = <NoteEntity>[];
        NoteMarkdownIoService.debugExportOverride = (NoteEntity note) async {
          exportedSnapshots.add(note);
          return NoteMarkdownShareOutcome(
            ok: true,
            filename: NoteMarkdownExportHelper.buildFilename(note.title),
            markdownContent:
                NoteMarkdownExportHelper.buildExport(note).markdownContent,
            usedTextFallback: false,
          );
        };

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light(),
            home: NotesView(state: appState),
          ),
        );
        await tester.pumpAndSettle();

        // Select the active note to open the wide master-detail editor pane.
        await tester.tap(find.text('Initial Export Title'));
        await tester.pumpAndSettle();

        // Enter unsaved content edits and export immediately before autosave timer fires.
        final contentField = find.byWidgetPredicate(
          (Widget w) =>
              w is TextField &&
              w.controller?.text == '- [ ] Initial task',
        );
        expect(contentField, findsOneWidget);
        await tester.enterText(
          contentField,
          '- [x] Unsaved edited item [[Next Note]]',
        );
        await tester.pump();

        await tester.tap(find.byTooltip('Export / Share Markdown (.md)'));
        await tester.pumpAndSettle();

        expect(exportedSnapshots.length, 1);
        expect(
          exportedSnapshots.single.content,
          '- [x] Unsaved edited item [[Next Note]]',
        );
        expect(
          find.text('Prepared "Initial Export Title.md" for export/share'),
          findsOneWidget,
        );

        // Switch to Trash section: Export / Share (.md) must NOT appear in trashed card menu.
        await tester.tap(find.textContaining('Trash'));
        await tester.pumpAndSettle();
        expect(find.text('Trashed Hidden Note'), findsOneWidget);

        await tester.tap(find.byTooltip('Note actions').first);
        await tester.pumpAndSettle();
        expect(find.text('Export / Share (.md)'), findsNothing);
        expect(find.text('Restore from Trash'), findsOneWidget);
      },
    );
  });
}
