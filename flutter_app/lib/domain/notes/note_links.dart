import 'note_helpers.dart';
import 'note_markdown.dart';
import 'note_models.dart';

/// Pure domain internal note link (`[[Note Title]]`) resolution and backlink
/// discovery helpers for Daywell Notes.
///
/// Zero dependencies on Flutter widgets or Drift SQLite.
/// Keeps normalized matching, active-only visibility, ambiguity handling, and
/// backlink snippet extraction strictly equivalent to `src/domain/noteLinks.ts`.
class ParsedNoteInternalLink {
  final String targetTitle;
  final String rawText;
  final String normalizedKey;

  const ParsedNoteInternalLink({
    required this.targetTitle,
    required this.rawText,
    required this.normalizedKey,
  });
}

enum NoteInternalLinkResolutionStatus {
  resolved,
  ambiguous,
  missing,
}

class NoteInternalLinkResolution {
  final NoteInternalLinkResolutionStatus status;
  final String targetTitle;
  final String normalizedKey;
  final NoteEntity? note;
  final List<NoteEntity> matches;

  NoteInternalLinkResolution({
    required this.status,
    required this.targetTitle,
    required this.normalizedKey,
    this.note,
    List<NoteEntity> matches = const <NoteEntity>[],
  }) : matches = List<NoteEntity>.unmodifiable(matches);
}

class NoteBacklinkEntry {
  final NoteEntity note;
  final String snippet;
  final int linkCount;

  const NoteBacklinkEntry({
    required this.note,
    required this.snippet,
    required this.linkCount,
  });
}

class NoteLinksDomain {
  const NoteLinksDomain._();

  static const int _maxBacklinkSnippetLength = 110;
  static final RegExp _multiWhitespaceRe = RegExp(r'\s+');

  /// Normalizes a note title or `[[Note Title]]` target for exact deterministic
  /// matching without fuzzy or substring matching.
  static String normalizeTitleKey(String? rawTitle) {
    if (rawTitle == null) return '';
    final trimmed = rawTitle.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceAll(_multiWhitespaceRe, ' ').toLowerCase();
  }

  static void _collectInternalLinksFromInlines(
    List<NoteMarkdownInline> inlines,
    List<ParsedNoteInternalLink> out,
  ) {
    for (final node in inlines) {
      switch (node.type) {
        case NoteMarkdownInlineType.internalLink:
          final key = normalizeTitleKey(node.text);
          if (key.isNotEmpty) {
            out.add(
              ParsedNoteInternalLink(
                targetTitle: node.text,
                rawText: node.rawText,
                normalizedKey: key,
              ),
            );
          }
          break;
        case NoteMarkdownInlineType.bold:
        case NoteMarkdownInlineType.italic:
        case NoteMarkdownInlineType.strikethrough:
          _collectInternalLinksFromInlines(node.children, out);
          break;
        case NoteMarkdownInlineType.text:
        case NoteMarkdownInlineType.code:
        case NoteMarkdownInlineType.link:
          break;
      }
    }
  }

  static bool _inlineListContainsTargetKey(
    List<NoteMarkdownInline> inlines,
    String targetKey,
  ) {
    final found = <ParsedNoteInternalLink>[];
    _collectInternalLinksFromInlines(inlines, found);
    return found.any((link) => link.normalizedKey == targetKey);
  }

  static void _collectFromDocument(
    NoteMarkdownDocument doc,
    List<ParsedNoteInternalLink> links,
  ) {
    for (final block in doc.blocks) {
      switch (block.type) {
        case NoteMarkdownBlockType.heading:
        case NoteMarkdownBlockType.paragraph:
          _collectInternalLinksFromInlines(block.inlines, links);
          break;
        case NoteMarkdownBlockType.bulletList:
          for (final item in block.listItems) {
            _collectInternalLinksFromInlines(item, links);
          }
          break;
        case NoteMarkdownBlockType.orderedList:
          for (final item in block.orderedItems) {
            _collectInternalLinksFromInlines(item.inlines, links);
          }
          break;
        case NoteMarkdownBlockType.checklist:
          for (final item in block.checklistItems) {
            _collectInternalLinksFromInlines(item.inlines, links);
          }
          break;
        case NoteMarkdownBlockType.blockquote:
          for (final line in block.quoteLines) {
            _collectInternalLinksFromInlines(line, links);
          }
          break;
        case NoteMarkdownBlockType.codeBlock:
        case NoteMarkdownBlockType.horizontalRule:
          break;
      }
    }
  }

  /// Extracts all valid `[[Note Title]]` internal links from parsed Markdown
  /// outside inline code and fenced code blocks.
  static List<ParsedNoteInternalLink> extractInternalLinks(String? source) {
    final doc = NoteMarkdownParser.parse(source);
    final links = <ParsedNoteInternalLink>[];
    _collectFromDocument(doc, links);
    return List<ParsedNoteInternalLink>.unmodifiable(links);
  }

  /// Resolves an internal link target dynamically against active notes only.
  /// Archived and trashed notes are excluded, and multiple active matches report
  /// [NoteInternalLinkResolutionStatus.ambiguous].
  static NoteInternalLinkResolution resolveInternalLink(
    String? targetTitle,
    Iterable<NoteEntity> notes,
  ) {
    final cleanTitle = targetTitle?.trim() ?? '';
    final normalizedKey = normalizeTitleKey(cleanTitle);
    if (normalizedKey.isEmpty) {
      return NoteInternalLinkResolution(
        status: NoteInternalLinkResolutionStatus.missing,
        targetTitle: cleanTitle,
        normalizedKey: '',
      );
    }

    final matched = notes
        .where(
          (note) =>
              NoteDomainHelpers.isActive(note) &&
              normalizeTitleKey(note.title) == normalizedKey,
        )
        .toList();

    if (matched.isEmpty) {
      return NoteInternalLinkResolution(
        status: NoteInternalLinkResolutionStatus.missing,
        targetTitle: cleanTitle,
        normalizedKey: normalizedKey,
      );
    }

    final sorted = NoteDomainHelpers.sortNotes(
      matched,
      sortBy: NoteSortMode.recent,
      pinFirst: false,
    );

    if (sorted.length == 1) {
      return NoteInternalLinkResolution(
        status: NoteInternalLinkResolutionStatus.resolved,
        targetTitle: cleanTitle,
        normalizedKey: normalizedKey,
        note: sorted.first,
        matches: sorted,
      );
    }

    return NoteInternalLinkResolution(
      status: NoteInternalLinkResolutionStatus.ambiguous,
      targetTitle: cleanTitle,
      normalizedKey: normalizedKey,
      matches: sorted,
    );
  }

  static String _truncateSnippet(String raw) {
    final collapsed = raw.replaceAll(_multiWhitespaceRe, ' ').trim();
    if (collapsed.isEmpty) return '';
    if (collapsed.length <= _maxBacklinkSnippetLength) {
      return collapsed;
    }
    return '${collapsed.substring(0, _maxBacklinkSnippetLength - 3).trimRight()}...';
  }

  static String _extractMatchingLineSnippet(
    NoteMarkdownDocument doc,
    String targetKey,
    String fallbackContent,
  ) {
    final candidateInlineLists = <List<NoteMarkdownInline>>[];
    for (final block in doc.blocks) {
      switch (block.type) {
        case NoteMarkdownBlockType.heading:
        case NoteMarkdownBlockType.paragraph:
          candidateInlineLists.add(block.inlines);
          break;
        case NoteMarkdownBlockType.bulletList:
          candidateInlineLists.addAll(block.listItems);
          break;
        case NoteMarkdownBlockType.orderedList:
          for (final item in block.orderedItems) {
            candidateInlineLists.add(item.inlines);
          }
          break;
        case NoteMarkdownBlockType.checklist:
          for (final item in block.checklistItems) {
            candidateInlineLists.add(item.inlines);
          }
          break;
        case NoteMarkdownBlockType.blockquote:
          candidateInlineLists.addAll(block.quoteLines);
          break;
        case NoteMarkdownBlockType.codeBlock:
        case NoteMarkdownBlockType.horizontalRule:
          break;
      }
    }

    for (final inlineList in candidateInlineLists) {
      if (!_inlineListContainsTargetKey(inlineList, targetKey)) continue;
      final plain = NoteMarkdownParser.inlinesToPlainText(inlineList);
      final subLines = plain
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty);
      for (final subLine in subLines) {
        if (subLine
            .replaceAll(_multiWhitespaceRe, ' ')
            .toLowerCase()
            .contains(targetKey)) {
          return _truncateSnippet(subLine);
        }
      }
      final truncated = _truncateSnippet(plain);
      if (truncated.isNotEmpty) return truncated;
    }

    return _truncateSnippet(NoteMarkdownParser.toPlainText(fallbackContent));
  }

  /// Finds active notes containing at least one valid `[[Note Title]]` link
  /// referencing [targetNote]. Excludes self, archived, and trashed notes.
  static List<NoteBacklinkEntry> findBacklinks(
    NoteEntity? targetNote,
    Iterable<NoteEntity> notes,
  ) {
    if (targetNote == null || !NoteDomainHelpers.isActive(targetNote)) {
      return const <NoteBacklinkEntry>[];
    }
    final targetKey = normalizeTitleKey(targetNote.title);
    if (targetKey.isEmpty) {
      return const <NoteBacklinkEntry>[];
    }

    final backlinks = <NoteBacklinkEntry>[];
    final seenIds = <String>{};

    for (final candidate in notes) {
      if (candidate.id == targetNote.id) continue;
      if (seenIds.contains(candidate.id)) continue;
      if (!NoteDomainHelpers.isActive(candidate)) continue;

      final doc = NoteMarkdownParser.parse(candidate.content);
      final links = <ParsedNoteInternalLink>[];
      _collectFromDocument(doc, links);
      final matchingCount =
          links.where((link) => link.normalizedKey == targetKey).length;
      if (matchingCount == 0) continue;

      seenIds.add(candidate.id);
      backlinks.add(
        NoteBacklinkEntry(
          note: candidate,
          snippet: _extractMatchingLineSnippet(
            doc,
            targetKey,
            candidate.content,
          ),
          linkCount: matchingCount,
        ),
      );
    }

    backlinks.sort(
      (a, b) => NoteDomainHelpers.compareNotes(
        a.note,
        b.note,
        sortBy: NoteSortMode.recent,
        pinFirst: false,
      ),
    );
    return List<NoteBacklinkEntry>.unmodifiable(backlinks);
  }
}
