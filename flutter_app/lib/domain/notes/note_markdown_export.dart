import 'note_helpers.dart';
import 'note_models.dart';

/// Pure domain helpers for exporting an individual Daywell Note to Markdown.
///
/// Zero dependencies on Flutter widgets, `dart:io`, or Drift SQLite.
/// Keeps filename sanitization, trash exclusion, and verbatim Markdown body
/// preservation equivalent to `src/domain/noteMarkdownExport.ts`.
class NoteMarkdownExportResult {
  final bool ok;
  final String resolvedTitle;
  final String filename;
  final String markdownContent;
  final String? error;

  const NoteMarkdownExportResult({
    required this.ok,
    required this.resolvedTitle,
    required this.filename,
    required this.markdownContent,
    this.error,
  });
}

class NoteMarkdownExportHelper {
  const NoteMarkdownExportHelper._();

  static const String fileExtension = '.md';
  static const int maxFilenameStemLength = 80;

  static final RegExp _illegalFilenameCharsRegex = RegExp(
    r'[\\/:*?"<>|\u0000-\u001F\u007F]',
  );
  static final RegExp _windowsReservedStemRegex = RegExp(
    r'^(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$',
    caseSensitive: false,
  );
  static final RegExp _trimEdgesRegex = RegExp(r'^[\s.\-]+|[\s.\-]+$');
  static final RegExp _trimEndRegex = RegExp(r'[\s.\-]+$');

  static String _truncateUtf16Safely(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    if (maxLength <= 0) return '';
    var end = maxLength;
    final lastCode = value.codeUnitAt(end - 1);
    if (lastCode >= 0xD800 && lastCode <= 0xDBFF && end > 1) {
      end -= 1;
    }
    return value.substring(0, end);
  }

  static String _stripTrailingMarkdownExtension(String stem) {
    var current = stem.replaceAll(RegExp(r'[\s\-]+$'), '');
    while (current.toLowerCase().endsWith(fileExtension)) {
      current = current
          .substring(0, current.length - fileExtension.length)
          .replaceAll(_trimEndRegex, '');
    }
    return current.replaceAll(_trimEdgesRegex, '');
  }

  static String resolveExportTitle(String? rawTitle) {
    return NoteDomainHelpers.normalizeTitle(rawTitle);
  }

  static String buildFilename(String? rawTitle) {
    final baseTitle = resolveExportTitle(rawTitle);
    var stem = baseTitle
        .replaceAll(_illegalFilenameCharsRegex, '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'-{2,}'), '-');

    stem = _stripTrailingMarkdownExtension(stem);
    if (stem.isEmpty) {
      stem = NoteDomainHelpers.defaultTitle;
    }

    if (_windowsReservedStemRegex.hasMatch(stem)) {
      stem = '$stem-note';
    }

    stem = _truncateUtf16Safely(stem, maxFilenameStemLength)
        .replaceAll(_trimEndRegex, '');
    if (stem.isEmpty) {
      stem = NoteDomainHelpers.defaultTitle;
    }

    return '$stem$fileExtension';
  }

  static NoteMarkdownExportResult buildExport(NoteEntity? note) {
    if (note == null) {
      return const NoteMarkdownExportResult(
        ok: false,
        resolvedTitle: NoteDomainHelpers.defaultTitle,
        filename: '${NoteDomainHelpers.defaultTitle}$fileExtension',
        markdownContent: '',
        error: 'Note is unavailable for export.',
      );
    }

    final resolvedTitle = resolveExportTitle(note.title);
    final filename = buildFilename(resolvedTitle);

    if (NoteDomainHelpers.isTrashed(note)) {
      return NoteMarkdownExportResult(
        ok: false,
        resolvedTitle: resolvedTitle,
        filename: filename,
        markdownContent: '',
        error: 'Cannot export a note in Trash. Restore it from Trash first.',
      );
    }

    final rawContent = note.content;
    final markdownContent = rawContent.isEmpty
        ? '# $resolvedTitle\n'
        : '# $resolvedTitle\n\n$rawContent';

    return NoteMarkdownExportResult(
      ok: true,
      resolvedTitle: resolvedTitle,
      filename: filename,
      markdownContent: markdownContent,
    );
  }
}
