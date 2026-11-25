import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/notes/note_markdown_export.dart';
import '../../domain/notes/note_models.dart';

class NoteMarkdownShareOutcome {
  final bool ok;
  final String filename;
  final String markdownContent;
  final bool usedTextFallback;
  final String? filePath;
  final String? error;

  const NoteMarkdownShareOutcome({
    required this.ok,
    required this.filename,
    required this.markdownContent,
    required this.usedTextFallback,
    this.filePath,
    this.error,
  });
}

/// Platform `.md` file writer and OS share-sheet bridge for individual Daywell
/// Notes. Writes UTF-8 `.md` files into temporary storage and hands them off to
/// `Share.shareXFiles`, falling back cleanly to `Share.share` if file-sharing
/// plugins are unavailable.
class NoteMarkdownIoService {
  @visibleForTesting
  static Future<NoteMarkdownShareOutcome> Function(NoteEntity note)?
      debugExportOverride;

  static Future<void> _defaultShareFile(XFile file, String subject) {
    return Share.shareXFiles(
      <XFile>[file],
      subject: subject,
    );
  }

  static Future<void> _defaultShareText(String text, String subject) {
    return Share.share(text, subject: subject);
  }

  static Future<NoteMarkdownShareOutcome> exportAndShareNote(
    NoteEntity note, {
    Future<Directory> Function()? tempDirProvider,
    Future<void> Function(XFile file, String subject)? shareFileOverride,
    Future<void> Function(String text, String subject)? shareTextOverride,
  }) async {
    final override = debugExportOverride;
    if (override != null) {
      return override(note);
    }

    final prepared = NoteMarkdownExportHelper.buildExport(note);
    if (!prepared.ok) {
      return NoteMarkdownShareOutcome(
        ok: false,
        filename: prepared.filename,
        markdownContent: '',
        usedTextFallback: false,
        error: prepared.error ?? 'Unable to export note as Markdown.',
      );
    }

    String? writtenPath;
    try {
      final dir = await (tempDirProvider ?? getTemporaryDirectory)();
      final file = File(p.join(dir.path, prepared.filename));
      await file.writeAsString(
        prepared.markdownContent,
        encoding: utf8,
        flush: true,
      );
      writtenPath = file.path;

      await (shareFileOverride ?? _defaultShareFile)(
        XFile(
          file.path,
          mimeType: 'text/markdown',
          name: prepared.filename,
        ),
        prepared.resolvedTitle,
      );

      return NoteMarkdownShareOutcome(
        ok: true,
        filename: prepared.filename,
        markdownContent: prepared.markdownContent,
        usedTextFallback: false,
        filePath: writtenPath,
      );
    } on MissingPluginException {
      return _shareWithTextFallback(
        prepared: prepared,
        writtenPath: writtenPath,
        shareTextOverride: shareTextOverride,
      );
    } on PlatformException {
      return _shareWithTextFallback(
        prepared: prepared,
        writtenPath: writtenPath,
        shareTextOverride: shareTextOverride,
      );
    } catch (error) {
      return NoteMarkdownShareOutcome(
        ok: false,
        filename: prepared.filename,
        markdownContent: prepared.markdownContent,
        usedTextFallback: false,
        filePath: writtenPath,
        error: 'Unable to export "${prepared.filename}": $error',
      );
    }
  }

  static Future<NoteMarkdownShareOutcome> _shareWithTextFallback({
    required NoteMarkdownExportResult prepared,
    required String? writtenPath,
    Future<void> Function(String text, String subject)? shareTextOverride,
  }) async {
    try {
      await (shareTextOverride ?? _defaultShareText)(
        prepared.markdownContent,
        prepared.resolvedTitle,
      );
      return NoteMarkdownShareOutcome(
        ok: true,
        filename: prepared.filename,
        markdownContent: prepared.markdownContent,
        usedTextFallback: true,
        filePath: writtenPath,
      );
    } catch (error) {
      return NoteMarkdownShareOutcome(
        ok: false,
        filename: prepared.filename,
        markdownContent: prepared.markdownContent,
        usedTextFallback: false,
        filePath: writtenPath,
        error: 'Unable to share "${prepared.filename}": $error',
      );
    }
  }
}
