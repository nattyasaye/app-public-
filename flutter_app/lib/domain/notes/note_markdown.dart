/// Pure domain lightweight Markdown parser and URL safety validator for Daywell Notes.
///
/// Zero dependencies on Flutter widgets or Drift SQLite.
/// Keeps parsing, inline formatting, malformed-input safety, HTML/script inertness,
/// and URL validation strictly equivalent to `src/domain/noteMarkdown.ts`.
enum NoteMarkdownInlineType {
  text,
  bold,
  italic,
  strikethrough,
  code,
  link,
  internalLink,
}

class NoteMarkdownInline {
  final NoteMarkdownInlineType type;
  final String text;
  final String url;
  final String rawText;
  final List<NoteMarkdownInline> children;

  const NoteMarkdownInline.text(this.text)
      : type = NoteMarkdownInlineType.text,
        url = '',
        rawText = '',
        children = const <NoteMarkdownInline>[];

  NoteMarkdownInline.bold(List<NoteMarkdownInline> children)
      : type = NoteMarkdownInlineType.bold,
        text = '',
        url = '',
        rawText = '',
        children = List<NoteMarkdownInline>.unmodifiable(children);

  NoteMarkdownInline.italic(List<NoteMarkdownInline> children)
      : type = NoteMarkdownInlineType.italic,
        text = '',
        url = '',
        rawText = '',
        children = List<NoteMarkdownInline>.unmodifiable(children);

  NoteMarkdownInline.strikethrough(List<NoteMarkdownInline> children)
      : type = NoteMarkdownInlineType.strikethrough,
        text = '',
        url = '',
        rawText = '',
        children = List<NoteMarkdownInline>.unmodifiable(children);

  const NoteMarkdownInline.code(this.text)
      : type = NoteMarkdownInlineType.code,
        url = '',
        rawText = '',
        children = const <NoteMarkdownInline>[];

  const NoteMarkdownInline.link({
    required String label,
    required this.url,
  })  : type = NoteMarkdownInlineType.link,
        text = label,
        rawText = '',
        children = const <NoteMarkdownInline>[];

  const NoteMarkdownInline.internalLink({
    required String targetTitle,
    this.rawText = '',
  })  : type = NoteMarkdownInlineType.internalLink,
        text = targetTitle,
        url = '',
        children = const <NoteMarkdownInline>[];
}

class NoteMarkdownOrderedItem {
  final int number;
  final List<NoteMarkdownInline> inlines;

  NoteMarkdownOrderedItem({
    required this.number,
    required List<NoteMarkdownInline> inlines,
  }) : inlines = List<NoteMarkdownInline>.unmodifiable(inlines);
}

class NoteMarkdownChecklistItem {
  final bool checked;
  final List<NoteMarkdownInline> inlines;
  final int lineIndex;

  NoteMarkdownChecklistItem({
    required this.checked,
    required List<NoteMarkdownInline> inlines,
    this.lineIndex = -1,
  }) : inlines = List<NoteMarkdownInline>.unmodifiable(inlines);
}

class NoteChecklistToggleResult {
  final String text;
  final bool checked;
  final int lineIndex;

  const NoteChecklistToggleResult({
    required this.text,
    required this.checked,
    required this.lineIndex,
  });
}

class NoteChecklistLineStatus {
  final int lineIndex;
  final bool checked;

  const NoteChecklistLineStatus({
    required this.lineIndex,
    required this.checked,
  });
}

class _SourceLineSpan {
  final int start;
  final int end;

  const _SourceLineSpan(this.start, this.end);
}

enum NoteMarkdownBlockType {
  heading,
  paragraph,
  bulletList,
  orderedList,
  checklist,
  blockquote,
  codeBlock,
  horizontalRule,
}

class NoteMarkdownBlock {
  final NoteMarkdownBlockType type;
  final int level;
  final int start;
  final String language;
  final String code;
  final List<NoteMarkdownInline> inlines;
  final List<List<NoteMarkdownInline>> listItems;
  final List<NoteMarkdownOrderedItem> orderedItems;
  final List<NoteMarkdownChecklistItem> checklistItems;
  final List<List<NoteMarkdownInline>> quoteLines;

  NoteMarkdownBlock.heading({
    required this.level,
    required List<NoteMarkdownInline> inlines,
  })  : type = NoteMarkdownBlockType.heading,
        start = 1,
        language = '',
        code = '',
        inlines = List<NoteMarkdownInline>.unmodifiable(inlines),
        listItems = const <List<NoteMarkdownInline>>[],
        orderedItems = const <NoteMarkdownOrderedItem>[],
        checklistItems = const <NoteMarkdownChecklistItem>[],
        quoteLines = const <List<NoteMarkdownInline>>[];

  NoteMarkdownBlock.paragraph({
    required List<NoteMarkdownInline> inlines,
  })  : type = NoteMarkdownBlockType.paragraph,
        level = 0,
        start = 1,
        language = '',
        code = '',
        inlines = List<NoteMarkdownInline>.unmodifiable(inlines),
        listItems = const <List<NoteMarkdownInline>>[],
        orderedItems = const <NoteMarkdownOrderedItem>[],
        checklistItems = const <NoteMarkdownChecklistItem>[],
        quoteLines = const <List<NoteMarkdownInline>>[];

  NoteMarkdownBlock.bulletList({
    required List<List<NoteMarkdownInline>> items,
  })  : type = NoteMarkdownBlockType.bulletList,
        level = 0,
        start = 1,
        language = '',
        code = '',
        inlines = const <NoteMarkdownInline>[],
        listItems = List<List<NoteMarkdownInline>>.unmodifiable(
          items.map(List<NoteMarkdownInline>.unmodifiable),
        ),
        orderedItems = const <NoteMarkdownOrderedItem>[],
        checklistItems = const <NoteMarkdownChecklistItem>[],
        quoteLines = const <List<NoteMarkdownInline>>[];

  NoteMarkdownBlock.orderedList({
    required this.start,
    required List<NoteMarkdownOrderedItem> items,
  })  : type = NoteMarkdownBlockType.orderedList,
        level = 0,
        language = '',
        code = '',
        inlines = const <NoteMarkdownInline>[],
        listItems = const <List<NoteMarkdownInline>>[],
        orderedItems = List<NoteMarkdownOrderedItem>.unmodifiable(items),
        checklistItems = const <NoteMarkdownChecklistItem>[],
        quoteLines = const <List<NoteMarkdownInline>>[];

  NoteMarkdownBlock.checklist({
    required List<NoteMarkdownChecklistItem> items,
  })  : type = NoteMarkdownBlockType.checklist,
        level = 0,
        start = 1,
        language = '',
        code = '',
        inlines = const <NoteMarkdownInline>[],
        listItems = const <List<NoteMarkdownInline>>[],
        orderedItems = const <NoteMarkdownOrderedItem>[],
        checklistItems = List<NoteMarkdownChecklistItem>.unmodifiable(items),
        quoteLines = const <List<NoteMarkdownInline>>[];

  NoteMarkdownBlock.blockquote({
    required List<List<NoteMarkdownInline>> lines,
  })  : type = NoteMarkdownBlockType.blockquote,
        level = 0,
        start = 1,
        language = '',
        code = '',
        inlines = const <NoteMarkdownInline>[],
        listItems = const <List<NoteMarkdownInline>>[],
        orderedItems = const <NoteMarkdownOrderedItem>[],
        checklistItems = const <NoteMarkdownChecklistItem>[],
        quoteLines = List<List<NoteMarkdownInline>>.unmodifiable(
          lines.map(List<NoteMarkdownInline>.unmodifiable),
        );

  const NoteMarkdownBlock.codeBlock({
    required this.language,
    required this.code,
  })  : type = NoteMarkdownBlockType.codeBlock,
        level = 0,
        start = 1,
        inlines = const <NoteMarkdownInline>[],
        listItems = const <List<NoteMarkdownInline>>[],
        orderedItems = const <NoteMarkdownOrderedItem>[],
        checklistItems = const <NoteMarkdownChecklistItem>[],
        quoteLines = const <List<NoteMarkdownInline>>[];

  const NoteMarkdownBlock.horizontalRule()
      : type = NoteMarkdownBlockType.horizontalRule,
        level = 0,
        start = 1,
        language = '',
        code = '',
        inlines = const <NoteMarkdownInline>[],
        listItems = const <List<NoteMarkdownInline>>[],
        orderedItems = const <NoteMarkdownOrderedItem>[],
        checklistItems = const <NoteMarkdownChecklistItem>[],
        quoteLines = const <List<NoteMarkdownInline>>[];
}

class NoteMarkdownDocument {
  final List<NoteMarkdownBlock> blocks;

  NoteMarkdownDocument({required List<NoteMarkdownBlock> blocks})
      : blocks = List<NoteMarkdownBlock>.unmodifiable(blocks);
}

class _ParsedBracketLink {
  final String label;
  final String rawUrl;
  final int endIndex;

  const _ParsedBracketLink({
    required this.label,
    required this.rawUrl,
    required this.endIndex,
  });
}

class _ParsedInternalLink {
  final String targetTitle;
  final String rawText;
  final int endIndex;

  const _ParsedInternalLink({
    required this.targetTitle,
    required this.rawText,
    required this.endIndex,
  });
}

class NoteMarkdownParser {
  const NoteMarkdownParser._();

  static const Set<String> _allowedUrlSchemes = <String>{
    'http',
    'https',
    'mailto',
  };

  static const int _maxInlineDepth = 8;

  static final RegExp _whitespaceRe = RegExp(r'\s');
  static final RegExp _schemeRe = RegExp(r'^[a-z][a-z0-9+.-]*$');
  static final RegExp _authorityDelimRe = RegExp(r'[/?#]');
  static final RegExp _mailtoForbiddenRe = RegExp(r'''[<>"']''');

  static final RegExp _fenceOpenRe = RegExp(r'^ {0,3}```(.*)$');
  static final RegExp _fenceCloseRe = RegExp(r'^ {0,3}```+\s*$');
  static final RegExp _hrRe = RegExp(r'^ {0,3}-{3,}\s*$');
  static final RegExp _headingRe = RegExp(r'^ {0,3}(#{1,3})[ \t]+(.*)$');
  static final RegExp _blockquoteRe = RegExp(r'^ {0,3}> ?(.*)$');
  static final RegExp _checklistRe =
      RegExp(r'^\s*[-*][ \t]+\[([ xX])\](?:[ \t]+(.*))?$');
  static final RegExp _checklistToggleRe =
      RegExp(r'^(\s*[-*][ \t]+\[)([ xX])(\](?:[ \t].*)?)$');
  static final RegExp _bulletRe = RegExp(r'^\s*[-*][ \t]+(.*)$');
  static final RegExp _orderedRe = RegExp(r'^\s*(\d+)\.[ \t]+(.*)$');

  static bool _isWhitespaceChar(String? ch) {
    if (ch == null || ch.isEmpty) return false;
    return ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
  }

  static bool _hasControlChars(String value) {
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      if (code <= 0x1f || code == 0x7f) {
        return true;
      }
    }
    return false;
  }

  /// Validates a Markdown link URL using a strict fail-closed scheme allowlist.
  /// Permits only explicit `http:`, `https:`, and `mailto:` URLs with no control
  /// characters or whitespace. Returns null for unsafe or malformed URLs.
  static String? sanitizeUrl(String? rawUrl) {
    if (rawUrl == null) return null;
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty ||
        _hasControlChars(trimmed) ||
        _whitespaceRe.hasMatch(trimmed)) {
      return null;
    }
    if (trimmed.startsWith('//')) {
      return null;
    }
    final colonIdx = trimmed.indexOf(':');
    if (colonIdx <= 0) {
      return null;
    }
    final scheme = trimmed.substring(0, colonIdx).toLowerCase();
    if (!_schemeRe.hasMatch(scheme) || !_allowedUrlSchemes.contains(scheme)) {
      return null;
    }

    if (scheme == 'http' || scheme == 'https') {
      final prefix = '$scheme://';
      if (!trimmed.toLowerCase().startsWith(prefix)) {
        return null;
      }
      final rest = trimmed.substring(prefix.length);
      final authorityEnd = rest.indexOf(_authorityDelimRe);
      final authority =
          authorityEnd == -1 ? rest : rest.substring(0, authorityEnd);
      if (authority.isEmpty || authority.startsWith('@')) {
        return null;
      }
      return trimmed;
    }

    final target = trimmed.substring('mailto:'.length);
    if (target.isEmpty || _mailtoForbiddenRe.hasMatch(target)) {
      return null;
    }
    return trimmed;
  }

  static void _pushTextNode(List<NoteMarkdownInline> nodes, String text) {
    if (text.isEmpty) return;
    if (nodes.isNotEmpty && nodes.last.type == NoteMarkdownInlineType.text) {
      final merged = '${nodes.last.text}$text';
      nodes[nodes.length - 1] = NoteMarkdownInline.text(merged);
    } else {
      nodes.add(NoteMarkdownInline.text(text));
    }
  }

  static int _findInlineCodeClose(String text, int openIdx) {
    for (var idx = openIdx + 1; idx < text.length; idx++) {
      final ch = text[idx];
      if (ch == '\n') return -1;
      if (ch == '`') return idx;
    }
    return -1;
  }

  static int _findClosingMarker(String text, int startIdx, String marker) {
    var idx = startIdx;
    while (idx <= text.length - marker.length) {
      if (text[idx] == '`') {
        final codeClose = _findInlineCodeClose(text, idx);
        if (codeClose != -1) {
          idx = codeClose + 1;
          continue;
        }
      }
      if (text.startsWith(marker, idx)) {
        if (marker == '**' &&
            text.startsWith('***', idx) &&
            idx + 1 <= text.length - 2 &&
            !_isWhitespaceChar(text[idx])) {
          if (idx > startIdx && !_isWhitespaceChar(text[idx - 1])) {
            return idx + 1;
          }
        }
        if (idx > startIdx && !_isWhitespaceChar(text[idx - 1])) {
          return idx;
        }
      }
      idx++;
    }
    return -1;
  }

  static int _findClosingSingleAsterisk(String text, int startIdx) {
    var idx = startIdx;
    while (idx < text.length) {
      if (text[idx] == '`') {
        final codeClose = _findInlineCodeClose(text, idx);
        if (codeClose != -1) {
          idx = codeClose + 1;
          continue;
        }
      }
      if (text[idx] == '*') {
        if (text.startsWith('**', idx) && !text.startsWith('***', idx)) {
          idx += 2;
          continue;
        }
        if (idx > startIdx && !_isWhitespaceChar(text[idx - 1])) {
          return idx;
        }
      }
      idx++;
    }
    return -1;
  }

  static _ParsedInternalLink? _tryParseInternalLink(
    String text,
    int bracketStart,
  ) {
    if (bracketStart + 1 >= text.length ||
        text[bracketStart] != '[' ||
        text[bracketStart + 1] != '[') {
      return null;
    }
    for (var j = bracketStart + 2; j < text.length - 1; j++) {
      final ch = text[j];
      if (ch == '\n' || ch == '\r') return null;
      if (ch == '[' && text[j + 1] == '[') return null;
      if (ch == ']' && text[j + 1] == ']') {
        final inner = text.substring(bracketStart + 2, j);
        final trimmed = inner.trim();
        if (trimmed.isEmpty) return null;
        return _ParsedInternalLink(
          targetTitle: trimmed,
          rawText: text.substring(bracketStart, j + 2),
          endIndex: j + 2,
        );
      }
    }
    return null;
  }

  static _ParsedBracketLink? _tryParseBracketLink(
    String text,
    int bracketStart,
  ) {
    if (text[bracketStart] != '[') return null;
    var closeBracket = -1;
    for (var j = bracketStart + 1; j < text.length; j++) {
      final ch = text[j];
      if (ch == '\n' || ch == '[') return null;
      if (ch == ']') {
        closeBracket = j;
        break;
      }
    }
    if (closeBracket == -1 ||
        closeBracket + 1 >= text.length ||
        text[closeBracket + 1] != '(') {
      return null;
    }

    var depth = 1;
    var closeParen = -1;
    for (var k = closeBracket + 2; k < text.length; k++) {
      final ch = text[k];
      if (ch == '\n') return null;
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
        if (depth == 0) {
          closeParen = k;
          break;
        }
      }
    }
    if (closeParen == -1) return null;

    return _ParsedBracketLink(
      label: text.substring(bracketStart + 1, closeBracket),
      rawUrl: text.substring(closeBracket + 2, closeParen),
      endIndex: closeParen + 1,
    );
  }

  static List<NoteMarkdownInline> _parseInlineRange(String text, int depth) {
    if (text.isEmpty) return const <NoteMarkdownInline>[];
    if (depth >= _maxInlineDepth) {
      return <NoteMarkdownInline>[NoteMarkdownInline.text(text)];
    }

    final nodes = <NoteMarkdownInline>[];
    var i = 0;

    while (i < text.length) {
      final ch = text[i];

      if (ch == '!' && i + 1 < text.length && text[i + 1] == '[') {
        final parsedImg = _tryParseBracketLink(text, i + 1);
        if (parsedImg != null && parsedImg.label.trim().isNotEmpty) {
          _pushTextNode(nodes, parsedImg.label);
          i = parsedImg.endIndex;
          continue;
        }
      }

      if (ch == '[' && i + 1 < text.length && text[i + 1] == '[') {
        final parsedInternal = _tryParseInternalLink(text, i);
        if (parsedInternal != null) {
          nodes.add(
            NoteMarkdownInline.internalLink(
              targetTitle: parsedInternal.targetTitle,
              rawText: parsedInternal.rawText,
            ),
          );
          i = parsedInternal.endIndex;
          continue;
        }
      }

      if (ch == '[') {
        final parsedLink = _tryParseBracketLink(text, i);
        if (parsedLink != null && parsedLink.label.trim().isNotEmpty) {
          final safeUrl = sanitizeUrl(parsedLink.rawUrl);
          if (safeUrl != null) {
            nodes.add(
              NoteMarkdownInline.link(
                label: parsedLink.label,
                url: safeUrl,
              ),
            );
          } else {
            _pushTextNode(nodes, parsedLink.label);
          }
          i = parsedLink.endIndex;
          continue;
        }
      }

      if (ch == '`') {
        final closeIdx = _findInlineCodeClose(text, i);
        if (closeIdx == i + 1) {
          _pushTextNode(nodes, '``');
          i += 2;
          continue;
        }
        if (closeIdx > i + 1) {
          nodes.add(
            NoteMarkdownInline.code(text.substring(i + 1, closeIdx)),
          );
          i = closeIdx + 1;
          continue;
        }
      }

      if (ch == '*' &&
          text.startsWith('**', i) &&
          i + 2 < text.length &&
          !_isWhitespaceChar(text[i + 2])) {
        final closeIdx = _findClosingMarker(text, i + 2, '**');
        if (closeIdx != -1) {
          nodes.add(
            NoteMarkdownInline.bold(
              _parseInlineRange(text.substring(i + 2, closeIdx), depth + 1),
            ),
          );
          i = closeIdx + 2;
          continue;
        }
      }

      if (ch == '~' &&
          text.startsWith('~~', i) &&
          i + 2 < text.length &&
          !_isWhitespaceChar(text[i + 2])) {
        final closeIdx = _findClosingMarker(text, i + 2, '~~');
        if (closeIdx != -1) {
          nodes.add(
            NoteMarkdownInline.strikethrough(
              _parseInlineRange(text.substring(i + 2, closeIdx), depth + 1),
            ),
          );
          i = closeIdx + 2;
          continue;
        }
      }

      if (ch == '*' &&
          !text.startsWith('**', i) &&
          i + 1 < text.length &&
          !_isWhitespaceChar(text[i + 1])) {
        final closeIdx = _findClosingSingleAsterisk(text, i + 1);
        if (closeIdx != -1) {
          nodes.add(
            NoteMarkdownInline.italic(
              _parseInlineRange(text.substring(i + 1, closeIdx), depth + 1),
            ),
          );
          i = closeIdx + 1;
          continue;
        }
      }

      _pushTextNode(nodes, ch);
      i++;
    }

    return List<NoteMarkdownInline>.unmodifiable(nodes);
  }

  static List<NoteMarkdownInline> parseInlines(String text) {
    if (text.isEmpty) return const <NoteMarkdownInline>[];
    return _parseInlineRange(text, 0);
  }

  static String? _matchFenceOpen(String line) {
    final m = _fenceOpenRe.firstMatch(line);
    if (m == null) return null;
    final info = m.group(1) ?? '';
    if (info.contains('`')) return null;
    return info.trim();
  }

  static bool _isBlockBoundaryLine(String line) {
    if (line.trim().isEmpty) return true;
    if (_matchFenceOpen(line) != null) return true;
    if (_hrRe.hasMatch(line)) return true;
    if (_headingRe.hasMatch(line)) return true;
    if (_blockquoteRe.hasMatch(line)) return true;
    if (_checklistRe.hasMatch(line)) return true;
    if (_bulletRe.hasMatch(line)) return true;
    if (_orderedRe.hasMatch(line)) return true;
    return false;
  }

  /// Parses lightweight Markdown source into an immutable block/inline AST.
  /// Never mutates the input string and never executes or trusts embedded HTML.
  static NoteMarkdownDocument parse(String? source) {
    if (source == null || source.isEmpty) {
      return NoteMarkdownDocument(blocks: const <NoteMarkdownBlock>[]);
    }

    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final blocks = <NoteMarkdownBlock>[];

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];

      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      final fenceLang = _matchFenceOpen(line);
      if (fenceLang != null) {
        final codeLines = <String>[];
        i++;
        while (i < lines.length) {
          if (_fenceCloseRe.hasMatch(lines[i])) {
            i++;
            break;
          }
          codeLines.add(lines[i]);
          i++;
        }
        blocks.add(
          NoteMarkdownBlock.codeBlock(
            language: fenceLang,
            code: codeLines.join('\n'),
          ),
        );
        continue;
      }

      if (_hrRe.hasMatch(line)) {
        blocks.add(const NoteMarkdownBlock.horizontalRule());
        i++;
        continue;
      }

      final headingMatch = _headingRe.firstMatch(line);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        final text = headingMatch.group(2)!.trimRight();
        blocks.add(
          NoteMarkdownBlock.heading(
            level: level,
            inlines: parseInlines(text),
          ),
        );
        i++;
        continue;
      }

      if (_blockquoteRe.hasMatch(line)) {
        final quoteLines = <List<NoteMarkdownInline>>[];
        while (i < lines.length) {
          final qMatch = _blockquoteRe.firstMatch(lines[i]);
          if (qMatch == null) break;
          quoteLines.add(parseInlines(qMatch.group(1) ?? ''));
          i++;
        }
        blocks.add(NoteMarkdownBlock.blockquote(lines: quoteLines));
        continue;
      }

      if (_checklistRe.hasMatch(line)) {
        final items = <NoteMarkdownChecklistItem>[];
        while (i < lines.length) {
          final cMatch = _checklistRe.firstMatch(lines[i]);
          if (cMatch == null) break;
          final marker = (cMatch.group(1) ?? ' ').toLowerCase();
          items.add(
            NoteMarkdownChecklistItem(
              checked: marker == 'x',
              inlines: parseInlines(cMatch.group(2) ?? ''),
              lineIndex: i,
            ),
          );
          i++;
        }
        blocks.add(NoteMarkdownBlock.checklist(items: items));
        continue;
      }

      if (_bulletRe.hasMatch(line)) {
        final items = <List<NoteMarkdownInline>>[];
        while (i < lines.length) {
          if (_checklistRe.hasMatch(lines[i])) break;
          final bMatch = _bulletRe.firstMatch(lines[i]);
          if (bMatch == null) break;
          items.add(parseInlines(bMatch.group(1) ?? ''));
          i++;
        }
        blocks.add(NoteMarkdownBlock.bulletList(items: items));
        continue;
      }

      if (_orderedRe.hasMatch(line)) {
        final items = <NoteMarkdownOrderedItem>[];
        var start = 1;
        while (i < lines.length) {
          final oMatch = _orderedRe.firstMatch(lines[i]);
          if (oMatch == null) break;
          final num = int.tryParse(oMatch.group(1) ?? '') ?? (items.length + 1);
          if (items.isEmpty) {
            start = num;
          }
          items.add(
            NoteMarkdownOrderedItem(
              number: num,
              inlines: parseInlines(oMatch.group(2) ?? ''),
            ),
          );
          i++;
        }
        blocks.add(NoteMarkdownBlock.orderedList(start: start, items: items));
        continue;
      }

      final paraLines = <String>[];
      while (i < lines.length && !_isBlockBoundaryLine(lines[i])) {
        paraLines.add(lines[i]);
        i++;
      }
      if (paraLines.isNotEmpty) {
        blocks.add(
          NoteMarkdownBlock.paragraph(
            inlines: parseInlines(paraLines.join('\n')),
          ),
        );
      } else {
        i++;
      }
    }

    return NoteMarkdownDocument(blocks: blocks);
  }

  static String inlinesToPlainText(List<NoteMarkdownInline> inlines) {
    final buffer = StringBuffer();
    for (final node in inlines) {
      switch (node.type) {
        case NoteMarkdownInlineType.text:
        case NoteMarkdownInlineType.code:
        case NoteMarkdownInlineType.link:
        case NoteMarkdownInlineType.internalLink:
          buffer.write(node.text);
          break;
        case NoteMarkdownInlineType.bold:
        case NoteMarkdownInlineType.italic:
        case NoteMarkdownInlineType.strikethrough:
          buffer.write(inlinesToPlainText(node.children));
          break;
      }
    }
    return buffer.toString();
  }

  /// Produces a readable plain-text preview string from Markdown source for list
  /// card snippets without mutating the underlying Markdown content.
  static String toPlainText(String? source) {
    final doc = parse(source);
    final parts = <String>[];
    for (final block in doc.blocks) {
      switch (block.type) {
        case NoteMarkdownBlockType.heading:
        case NoteMarkdownBlockType.paragraph:
          final text = inlinesToPlainText(block.inlines).trim();
          if (text.isNotEmpty) parts.add(text);
          break;
        case NoteMarkdownBlockType.bulletList:
          for (final item in block.listItems) {
            final text = inlinesToPlainText(item).trim();
            if (text.isNotEmpty) parts.add(text);
          }
          break;
        case NoteMarkdownBlockType.orderedList:
          for (final item in block.orderedItems) {
            final text = inlinesToPlainText(item.inlines).trim();
            if (text.isNotEmpty) parts.add(text);
          }
          break;
        case NoteMarkdownBlockType.checklist:
          for (final item in block.checklistItems) {
            final text = inlinesToPlainText(item.inlines).trim();
            if (text.isNotEmpty) parts.add(text);
          }
          break;
        case NoteMarkdownBlockType.blockquote:
          for (final line in block.quoteLines) {
            final text = inlinesToPlainText(line).trim();
            if (text.isNotEmpty) parts.add(text);
          }
          break;
        case NoteMarkdownBlockType.codeBlock:
          if (block.code.trim().isNotEmpty) parts.add(block.code);
          break;
        case NoteMarkdownBlockType.horizontalRule:
          break;
      }
    }
    return parts.join('\n');
  }

  static List<_SourceLineSpan> _splitSourceLineSpans(String source) {
    final spans = <_SourceLineSpan>[];
    var lineStart = 0;
    var i = 0;
    while (i < source.length) {
      final ch = source[i];
      if (ch == '\r') {
        spans.add(_SourceLineSpan(lineStart, i));
        if (i + 1 < source.length && source[i + 1] == '\n') {
          i += 2;
        } else {
          i += 1;
        }
        lineStart = i;
        continue;
      }
      if (ch == '\n') {
        spans.add(_SourceLineSpan(lineStart, i));
        i += 1;
        lineStart = i;
        continue;
      }
      i += 1;
    }
    spans.add(_SourceLineSpan(lineStart, source.length));
    return spans;
  }

  static bool _isLineIndexInsideFence(
    String source,
    List<_SourceLineSpan> spans,
    int targetLineIndex,
  ) {
    var inFence = false;
    for (var idx = 0; idx < targetLineIndex && idx < spans.length; idx++) {
      final line = source.substring(spans[idx].start, spans[idx].end);
      if (!inFence) {
        if (_matchFenceOpen(line) != null) {
          inFence = true;
        }
      } else if (_fenceCloseRe.hasMatch(line)) {
        inFence = false;
      }
    }
    return inFence;
  }

  static int _findLineIndexForOffset(List<_SourceLineSpan> spans, int offset) {
    for (var idx = 0; idx < spans.length; idx++) {
      if (offset <= spans[idx].end) {
        return idx;
      }
    }
    return spans.isEmpty ? 0 : spans.length - 1;
  }

  /// Toggles a single Markdown checklist item (`- [ ]` <-> `- [x]`) at [lineIndex]
  /// while preserving all other lines, formatting, whitespace, and line endings.
  static NoteChecklistToggleResult? toggleChecklistAtLine(
    String? source,
    int lineIndex,
  ) {
    if (source == null || source.isEmpty || lineIndex < 0) return null;
    final spans = _splitSourceLineSpans(source);
    if (lineIndex >= spans.length) return null;
    if (_isLineIndexInsideFence(source, spans, lineIndex)) return null;

    final span = spans[lineIndex];
    final rawLine = source.substring(span.start, span.end);
    final match = _checklistToggleRe.firstMatch(rawLine);
    if (match == null) return null;

    final nextChecked = match.group(2)!.toLowerCase() != 'x';
    final nextLine = '${match.group(1)}${nextChecked ? 'x' : ' '}${match.group(3)}';
    return NoteChecklistToggleResult(
      text:
          '${source.substring(0, span.start)}$nextLine${source.substring(span.end)}',
      checked: nextChecked,
      lineIndex: lineIndex,
    );
  }

  /// Inspects whether a single-line cursor/selection sits on a valid Markdown
  /// checklist line outside fenced code blocks (used for Write-mode toggling).
  static NoteChecklistLineStatus? getChecklistAtSelection(
    String? source,
    int selectionStart,
    int selectionEnd,
  ) {
    if (source == null || source.isEmpty) return null;
    final a = selectionStart.clamp(0, source.length);
    final b = selectionEnd.clamp(0, source.length);
    final start = a <= b ? a : b;
    final end = a <= b ? b : a;

    final spans = _splitSourceLineSpans(source);
    final startLine = _findLineIndexForOffset(spans, start);
    final endLine = _findLineIndexForOffset(spans, end);
    if (startLine != endLine) return null;
    if (_isLineIndexInsideFence(source, spans, startLine)) return null;

    final span = spans[startLine];
    final rawLine = source.substring(span.start, span.end);
    final match = _checklistToggleRe.firstMatch(rawLine);
    if (match == null) return null;

    return NoteChecklistLineStatus(
      lineIndex: startLine,
      checked: match.group(2)!.toLowerCase() == 'x',
    );
  }
}

