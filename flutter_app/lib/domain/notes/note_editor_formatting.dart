import 'dart:math' as math;

/// Pure domain formatting toolbar and smart list/blockquote keyboard behavior
/// for Daywell Notes.
///
/// Zero dependencies on Flutter widgets or Drift SQLite.
/// Keeps toolbar transforms, smart Enter continuation, and smart Backspace exit
/// strictly aligned with `src/domain/noteEditorFormatting.ts`.
enum NoteToolbarFormatAction {
  heading2,
  bold,
  italic,
  strikethrough,
  bulletList,
  numberedList,
  checklist,
  blockquote,
  inlineCode,
  codeBlock,
  internalLink,
}

class NoteEditorTextEdit {
  final String text;
  final int selectionStart;
  final int selectionEnd;

  const NoteEditorTextEdit({
    required this.text,
    required this.selectionStart,
    required this.selectionEnd,
  });
}

enum _LinePrefixKind {
  none,
  heading2,
  headingOther,
  bulletList,
  numberedList,
  checklist,
  blockquote,
}

class _ParsedLinePrefix {
  final String indent;
  final _LinePrefixKind prefixKind;
  final int prefixLen;
  final String body;

  const _ParsedLinePrefix({
    required this.indent,
    required this.prefixKind,
    required this.prefixLen,
    required this.body,
  });
}

class _SmartPrefixInfo {
  final String indent;
  final int prefixLen;
  final String body;
  final String nextPrefix;

  const _SmartPrefixInfo({
    required this.indent,
    required this.prefixLen,
    required this.body,
    required this.nextPrefix,
  });
}

class NoteEditorFormatting {
  const NoteEditorFormatting._();

  static final RegExp _fenceOpenRe = RegExp(r'^ {0,3}```[^`]*$');
  static final RegExp _fenceCloseRe = RegExp(r'^ {0,3}```+\s*$');

  static final RegExp _checklistLineRe =
      RegExp(r'^([ \t]*)([-*][ \t]+\[[ xX]\](?:[ \t]+|$))(.*)$');
  static final RegExp _headingLineRe =
      RegExp(r'^([ \t]*)(#{1,3}(?:[ \t]+|$))(.*)$');
  static final RegExp _bulletLineRe =
      RegExp(r'^([ \t]*)([-*](?:[ \t]+|$))(.*)$');
  static final RegExp _orderedLineRe =
      RegExp(r'^([ \t]*)(\d+\.(?:[ \t]+|$))(.*)$');
  static final RegExp _blockquoteLineRe =
      RegExp(r'^([ \t]*)(>(?:[ \t]?|$))(.*)$');
  static final RegExp _leadingWsRe = RegExp(r'^([ \t]*)(.*)$');

  static final RegExp _leadSelectionWsRe = RegExp(r'^([ \t\r\n]*)');
  static final RegExp _trailSelectionWsRe = RegExp(r'([ \t\r\n]*)$');
  static final RegExp _selfFenceRe =
      RegExp(r'^ {0,3}```[^\n]*\n([\s\S]*?)\n {0,3}```\s*$');

  static final RegExp _smartChecklistRe =
      RegExp(r'^([ \t]*)([-*])[ \t]+\[([ xX])\](?:[ \t](.*))?$');
  static final RegExp _smartBulletRe = RegExp(r'^([ \t]*)([-*])[ \t](.*)$');
  static final RegExp _smartOrderedRe = RegExp(r'^([ \t]*)(\d+)\.[ \t](.*)$');
  static final RegExp _smartBlockquoteRe = RegExp(r'^([ \t]*)>[ \t]?(.*)$');

  static ({int start, int end}) _clampSelection(
    int textLength,
    int rawStart,
    int rawEnd,
  ) {
    final a = math.max(0, math.min(textLength, rawStart));
    final b = math.max(0, math.min(textLength, rawEnd));
    return a <= b ? (start: a, end: b) : (start: b, end: a);
  }

  static ({int lineStart, int lineEnd}) _getLineBounds(
    String text,
    int offset,
  ) {
    final clamped = math.max(0, math.min(text.length, offset));
    var lineStart = 0;
    if (clamped > 0) {
      final prevNl = text.lastIndexOf('\n', clamped - 1);
      lineStart = prevNl == -1 ? 0 : prevNl + 1;
    }
    final nextNl = text.indexOf('\n', clamped);
    final lineEnd = nextNl == -1 ? text.length : nextNl;
    return (lineStart: lineStart, lineEnd: lineEnd);
  }

  /// Returns true if the line containing [offset] lies inside an open fenced
  /// code block.
  static bool isOffsetInsideFencedCodeBlock(String text, int offset) {
    final bounds = _getLineBounds(text, offset);
    final lineStart = bounds.lineStart;
    if (lineStart == 0) return false;
    final prefixText = text.substring(0, lineStart - 1);
    final precedingLines = prefixText.split('\n');
    var inFence = false;
    for (final line in precedingLines) {
      if (!inFence) {
        if (_fenceOpenRe.hasMatch(line)) {
          inFence = true;
        }
      } else if (_fenceCloseRe.hasMatch(line)) {
        inFence = false;
      }
    }
    if (!inFence) return false;
    final currentLine = text.substring(lineStart, bounds.lineEnd);
    return !_fenceCloseRe.hasMatch(currentLine);
  }

  static bool _hasSelfInlineWrapper(String value, String marker) {
    if (value.length < marker.length * 2) return false;
    if (!value.startsWith(marker) || !value.endsWith(marker)) return false;

    if (marker == '`') {
      return !value.startsWith('```') && !value.endsWith('```');
    }
    if (marker == '*') {
      final isSingle = !value.startsWith('**') && !value.endsWith('**');
      final isTriple =
          value.length >= 6 && value.startsWith('***') && value.endsWith('***');
      return isSingle || isTriple;
    }
    return true;
  }

  static bool _hasSurroundingInlineWrapper(
    String before,
    String after,
    String marker,
  ) {
    if (!before.endsWith(marker) || !after.startsWith(marker)) return false;

    if (marker == '`') {
      return !before.endsWith('```') && !after.startsWith('```');
    }
    if (marker == '*') {
      final isTriple = before.endsWith('***') && after.startsWith('***');
      final isSingle = !before.endsWith('**') && !after.startsWith('**');
      return isTriple || isSingle;
    }
    return true;
  }

  static NoteEditorTextEdit _applyInlineFormatting(
    String text,
    int start,
    int end,
    String marker,
  ) {
    final before = text.substring(0, start);
    final selected = text.substring(start, end);
    final after = text.substring(end);

    if (selected.isNotEmpty && _hasSelfInlineWrapper(selected, marker)) {
      final inner = selected.substring(
        marker.length,
        selected.length - marker.length,
      );
      return NoteEditorTextEdit(
        text: '$before$inner$after',
        selectionStart: start,
        selectionEnd: start + inner.length,
      );
    }

    if (_hasSurroundingInlineWrapper(before, after, marker)) {
      final trimmedBefore = before.substring(0, before.length - marker.length);
      final trimmedAfter = after.substring(marker.length);
      return NoteEditorTextEdit(
        text: '$trimmedBefore$selected$trimmedAfter',
        selectionStart: start - marker.length,
        selectionEnd: end - marker.length,
      );
    }

    if (start == end) {
      return NoteEditorTextEdit(
        text: '$before$marker$marker$after',
        selectionStart: start + marker.length,
        selectionEnd: start + marker.length,
      );
    }

    final leadMatch = _leadSelectionWsRe.firstMatch(selected);
    final trailMatch = _trailSelectionWsRe.firstMatch(selected);
    final leadWs = leadMatch?.group(1) ?? '';
    final trailWs = trailMatch?.group(1) ?? '';

    if (leadWs.length + trailWs.length >= selected.length) {
      return NoteEditorTextEdit(
        text: '$before$marker$marker$selected$after',
        selectionStart: start + marker.length,
        selectionEnd: start + marker.length,
      );
    }

    final core = selected.substring(
      leadWs.length,
      selected.length - trailWs.length,
    );
    if (_hasSelfInlineWrapper(core, marker)) {
      final inner = core.substring(marker.length, core.length - marker.length);
      final innerStart = start + leadWs.length;
      return NoteEditorTextEdit(
        text: '$before$leadWs$inner$trailWs$after',
        selectionStart: innerStart,
        selectionEnd: innerStart + inner.length,
      );
    }

    final wrappedStart = start + leadWs.length + marker.length;
    return NoteEditorTextEdit(
      text: '$before$leadWs$marker$core$marker$trailWs$after',
      selectionStart: wrappedStart,
      selectionEnd: wrappedStart + core.length,
    );
  }

  static _ParsedLinePrefix _parseLinePrefix(String line) {
    final checklist = _checklistLineRe.firstMatch(line);
    if (checklist != null) {
      return _ParsedLinePrefix(
        indent: checklist.group(1)!,
        prefixKind: _LinePrefixKind.checklist,
        prefixLen: checklist.group(2)!.length,
        body: checklist.group(3)!,
      );
    }
    final heading = _headingLineRe.firstMatch(line);
    if (heading != null) {
      final hashes = heading.group(2)!.trim();
      return _ParsedLinePrefix(
        indent: heading.group(1)!,
        prefixKind: hashes == '##'
            ? _LinePrefixKind.heading2
            : _LinePrefixKind.headingOther,
        prefixLen: heading.group(2)!.length,
        body: heading.group(3)!,
      );
    }
    final bullet = _bulletLineRe.firstMatch(line);
    if (bullet != null) {
      return _ParsedLinePrefix(
        indent: bullet.group(1)!,
        prefixKind: _LinePrefixKind.bulletList,
        prefixLen: bullet.group(2)!.length,
        body: bullet.group(3)!,
      );
    }
    final ordered = _orderedLineRe.firstMatch(line);
    if (ordered != null) {
      return _ParsedLinePrefix(
        indent: ordered.group(1)!,
        prefixKind: _LinePrefixKind.numberedList,
        prefixLen: ordered.group(2)!.length,
        body: ordered.group(3)!,
      );
    }
    final quote = _blockquoteLineRe.firstMatch(line);
    if (quote != null) {
      return _ParsedLinePrefix(
        indent: quote.group(1)!,
        prefixKind: _LinePrefixKind.blockquote,
        prefixLen: quote.group(2)!.length,
        body: quote.group(3)!,
      );
    }
    final ws = _leadingWsRe.firstMatch(line);
    return _ParsedLinePrefix(
      indent: ws?.group(1) ?? '',
      prefixKind: _LinePrefixKind.none,
      prefixLen: 0,
      body: ws?.group(2) ?? line,
    );
  }

  static _LinePrefixKind _targetKindForAction(NoteToolbarFormatAction action) {
    switch (action) {
      case NoteToolbarFormatAction.heading2:
        return _LinePrefixKind.heading2;
      case NoteToolbarFormatAction.bulletList:
        return _LinePrefixKind.bulletList;
      case NoteToolbarFormatAction.numberedList:
        return _LinePrefixKind.numberedList;
      case NoteToolbarFormatAction.checklist:
        return _LinePrefixKind.checklist;
      case NoteToolbarFormatAction.blockquote:
        return _LinePrefixKind.blockquote;
      default:
        return _LinePrefixKind.none;
    }
  }

  static String _buildBlockLinePrefix(
    NoteToolbarFormatAction action,
    int indexNumber,
  ) {
    switch (action) {
      case NoteToolbarFormatAction.heading2:
        return '## ';
      case NoteToolbarFormatAction.bulletList:
        return '- ';
      case NoteToolbarFormatAction.numberedList:
        return '$indexNumber. ';
      case NoteToolbarFormatAction.checklist:
        return '- [ ] ';
      case NoteToolbarFormatAction.blockquote:
        return '> ';
      default:
        return '';
    }
  }

  static int _mapOffsetInRewrittenLine(
    int pos,
    int oldLineStart,
    int newLineStart,
    int indentLen,
    int oldPrefixLen,
    int newPrefixLen,
  ) {
    final posInLine = pos - oldLineStart;
    final oldContentStart = indentLen + oldPrefixLen;
    final newContentStart = indentLen + newPrefixLen;
    if (posInLine >= oldContentStart) {
      return newLineStart + newContentStart + (posInLine - oldContentStart);
    }
    if (posInLine <= indentLen) {
      return newLineStart + posInLine;
    }
    return newLineStart + newContentStart;
  }

  static NoteEditorTextEdit _applyBlockLineFormatting(
    String text,
    int start,
    int end,
    NoteToolbarFormatAction action,
  ) {
    final blockStart = _getLineBounds(text, start).lineStart;
    final effectiveEnd = end > start && text[end - 1] == '\n' ? end - 1 : end;
    final blockEnd = _getLineBounds(text, effectiveEnd).lineEnd;

    final sliceText = text.substring(blockStart, blockEnd);
    final rawLines = sliceText.split('\n');
    final parsedLines = rawLines.map(_parseLinePrefix).toList();
    final targetKind = _targetKindForAction(action);

    final relevantIndexes = <int>[];
    if (rawLines.length == 1) {
      relevantIndexes.add(0);
    } else {
      for (var idx = 0; idx < rawLines.length; idx++) {
        if (rawLines[idx].trim().isNotEmpty) {
          relevantIndexes.add(idx);
        }
      }
    }

    final shouldToggleOff = relevantIndexes.isNotEmpty &&
        relevantIndexes
            .every((idx) => parsedLines[idx].prefixKind == targetKind);

    var orderedCounter = 1;
    var oldOffset = blockStart;
    var newOffset = blockStart;
    final rewrittenLines = <String>[];

    var mappedStart = start;
    var mappedEnd = end;

    for (var idx = 0; idx < rawLines.length; idx++) {
      final rawLine = rawLines[idx];
      final parsed = parsedLines[idx];
      final oldLineStart = oldOffset;
      final oldLineEnd = oldOffset + rawLine.length;

      var newPrefix = '';
      var newLine = rawLine;
      var effectiveIndentLen = parsed.indent.length;
      var effectiveOldPrefixLen = parsed.prefixLen;

      if (rawLines.length > 1 && rawLine.trim().isEmpty) {
        effectiveIndentLen = 0;
        effectiveOldPrefixLen = 0;
      } else if (shouldToggleOff) {
        newPrefix = '';
        newLine = '${parsed.indent}${parsed.body}';
      } else {
        newPrefix = _buildBlockLinePrefix(action, orderedCounter);
        if (action == NoteToolbarFormatAction.numberedList) {
          orderedCounter += 1;
        }
        newLine = '${parsed.indent}$newPrefix${parsed.body}';
      }

      final newLineStart = newOffset;

      if (start >= oldLineStart && start <= oldLineEnd) {
        mappedStart = rawLines.length > 1 && rawLine.trim().isEmpty
            ? newLineStart + (start - oldLineStart)
            : _mapOffsetInRewrittenLine(
                start,
                oldLineStart,
                newLineStart,
                effectiveIndentLen,
                effectiveOldPrefixLen,
                newPrefix.length,
              );
      }
      if (end >= oldLineStart && end <= oldLineEnd) {
        mappedEnd = rawLines.length > 1 && rawLine.trim().isEmpty
            ? newLineStart + (end - oldLineStart)
            : _mapOffsetInRewrittenLine(
                end,
                oldLineStart,
                newLineStart,
                effectiveIndentLen,
                effectiveOldPrefixLen,
                newPrefix.length,
              );
      }

      rewrittenLines.add(newLine);
      oldOffset = oldLineEnd + 1;
      newOffset = newLineStart + newLine.length + 1;
    }

    final nextText =
        '${text.substring(0, blockStart)}${rewrittenLines.join('\n')}${text.substring(blockEnd)}';
    final clamped = _clampSelection(nextText.length, mappedStart, mappedEnd);
    return NoteEditorTextEdit(
      text: nextText,
      selectionStart: clamped.start,
      selectionEnd: clamped.end,
    );
  }

  static NoteEditorTextEdit _applyFencedCodeBlockFormatting(
    String text,
    int start,
    int end,
  ) {
    final before = text.substring(0, start);
    final selected = text.substring(start, end);
    final after = text.substring(end);

    final selfFenceMatch = _selfFenceRe.firstMatch(selected);
    if (selfFenceMatch != null) {
      final inner = selfFenceMatch.group(1)!;
      return NoteEditorTextEdit(
        text: '$before$inner$after',
        selectionStart: start,
        selectionEnd: start + inner.length,
      );
    }

    final leadingNl = before.isEmpty || before.endsWith('\n') ? '' : '\n';

    if (start == end) {
      final trailingNl = after.isEmpty || after.startsWith('\n') ? '' : '\n';
      final inserted = '$leadingNl```\n\n```$trailingNl';
      final cursorPos = before.length + leadingNl.length + 4;
      return NoteEditorTextEdit(
        text: '$before$inserted$after',
        selectionStart: cursorPos,
        selectionEnd: cursorPos,
      );
    }

    final hasTrailingNl = selected.endsWith('\n');
    final body =
        hasTrailingNl ? selected.substring(0, selected.length - 1) : selected;
    final trailingNl =
        hasTrailingNl || (after.isNotEmpty && !after.startsWith('\n'))
            ? '\n'
            : '';
    final inserted = '$leadingNl```\n$body\n```$trailingNl';
    final innerStart = before.length + leadingNl.length + 4;
    return NoteEditorTextEdit(
      text: '$before$inserted$after',
      selectionStart: innerStart,
      selectionEnd: innerStart + body.length,
    );
  }

  static NoteEditorTextEdit _applyInternalLinkFormatting(
    String text,
    int start,
    int end,
  ) {
    final before = text.substring(0, start);
    final selected = text.substring(start, end);
    final after = text.substring(end);

    if (selected.length >= 4 &&
        selected.startsWith('[[') &&
        selected.endsWith(']]')) {
      final inner = selected.substring(2, selected.length - 2);
      if (!inner.contains('[[') && !inner.contains(']]')) {
        return NoteEditorTextEdit(
          text: '$before$inner$after',
          selectionStart: start,
          selectionEnd: start + inner.length,
        );
      }
    }

    if (before.endsWith('[[') &&
        after.startsWith(']]') &&
        !selected.contains('[[') &&
        !selected.contains(']]')) {
      final trimmedBefore = before.substring(0, before.length - 2);
      final trimmedAfter = after.substring(2);
      return NoteEditorTextEdit(
        text: '$trimmedBefore$selected$trimmedAfter',
        selectionStart: start - 2,
        selectionEnd: end - 2,
      );
    }

    if (start == end) {
      return NoteEditorTextEdit(
        text: '$before[[]]$after',
        selectionStart: start + 2,
        selectionEnd: start + 2,
      );
    }

    final leadMatch = _leadSelectionWsRe.firstMatch(selected);
    final trailMatch = _trailSelectionWsRe.firstMatch(selected);
    final leadWs = leadMatch?.group(1) ?? '';
    final trailWs = trailMatch?.group(1) ?? '';

    if (leadWs.length + trailWs.length >= selected.length) {
      return NoteEditorTextEdit(
        text: '$before[[]]$selected$after',
        selectionStart: start + 2,
        selectionEnd: start + 2,
      );
    }

    final core = selected.substring(
      leadWs.length,
      selected.length - trailWs.length,
    );
    if (core.length >= 4 && core.startsWith('[[') && core.endsWith(']]')) {
      final inner = core.substring(2, core.length - 2);
      if (!inner.contains('[[') && !inner.contains(']]')) {
        final innerStart = start + leadWs.length;
        return NoteEditorTextEdit(
          text: '$before$leadWs$inner$trailWs$after',
          selectionStart: innerStart,
          selectionEnd: innerStart + inner.length,
        );
      }
    }

    final wrappedStart = start + leadWs.length + 2;
    return NoteEditorTextEdit(
      text: '$before$leadWs[[$core]]$trailWs$after',
      selectionStart: wrappedStart,
      selectionEnd: wrappedStart + core.length,
    );
  }

  /// Pure deterministic toolbar formatting shared across platforms.
  static NoteEditorTextEdit applyToolbarAction(
    String text,
    int selectionStart,
    int selectionEnd,
    NoteToolbarFormatAction action,
  ) {
    final clamped = _clampSelection(text.length, selectionStart, selectionEnd);
    final start = clamped.start;
    final end = clamped.end;

    switch (action) {
      case NoteToolbarFormatAction.bold:
        return _applyInlineFormatting(text, start, end, '**');
      case NoteToolbarFormatAction.italic:
        return _applyInlineFormatting(text, start, end, '*');
      case NoteToolbarFormatAction.strikethrough:
        return _applyInlineFormatting(text, start, end, '~~');
      case NoteToolbarFormatAction.inlineCode:
        return _applyInlineFormatting(text, start, end, '`');
      case NoteToolbarFormatAction.heading2:
      case NoteToolbarFormatAction.bulletList:
      case NoteToolbarFormatAction.numberedList:
      case NoteToolbarFormatAction.checklist:
      case NoteToolbarFormatAction.blockquote:
        return _applyBlockLineFormatting(text, start, end, action);
      case NoteToolbarFormatAction.codeBlock:
        return _applyFencedCodeBlockFormatting(text, start, end);
      case NoteToolbarFormatAction.internalLink:
        return _applyInternalLinkFormatting(text, start, end);
    }
  }

  static _SmartPrefixInfo? _matchSmartPrefix(String line) {
    final checklist = _smartChecklistRe.firstMatch(line);
    if (checklist != null) {
      final indent = checklist.group(1)!;
      final bulletChar = checklist.group(2)!;
      final body = checklist.group(4) ?? '';
      final prefixEnd = line.length - body.length;
      return _SmartPrefixInfo(
        indent: indent,
        prefixLen: prefixEnd,
        body: body,
        nextPrefix: '$indent$bulletChar [ ] ',
      );
    }

    final bullet = _smartBulletRe.firstMatch(line);
    if (bullet != null) {
      final indent = bullet.group(1)!;
      final bulletChar = bullet.group(2)!;
      final body = bullet.group(3)!;
      final prefixEnd = indent.length + 2;
      return _SmartPrefixInfo(
        indent: indent,
        prefixLen: prefixEnd,
        body: body,
        nextPrefix: '$indent$bulletChar ',
      );
    }

    final ordered = _smartOrderedRe.firstMatch(line);
    if (ordered != null) {
      final indent = ordered.group(1)!;
      final numStr = ordered.group(2)!;
      final body = ordered.group(3)!;
      final num = int.tryParse(numStr);
      final nextNum = num != null ? num + 1 : 2;
      final prefixEnd = indent.length + numStr.length + 2;
      return _SmartPrefixInfo(
        indent: indent,
        prefixLen: prefixEnd,
        body: body,
        nextPrefix: '$indent$nextNum. ',
      );
    }

    final quote = _smartBlockquoteRe.firstMatch(line);
    if (quote != null) {
      final indent = quote.group(1)!;
      final body = quote.group(2)!;
      final prefixEnd = line.length - body.length;
      return _SmartPrefixInfo(
        indent: indent,
        prefixLen: prefixEnd,
        body: body,
        nextPrefix: '$indent> ',
      );
    }

    return null;
  }

  /// Computes smart Enter continuation or exit on bullets, numbered lists,
  /// checklists, and blockquotes.
  /// Returns `null` when normal Enter newline behavior should run instead.
  static NoteEditorTextEdit? applySmartEnter(
    String text,
    int selectionStart,
    int selectionEnd,
  ) {
    final clamped = _clampSelection(text.length, selectionStart, selectionEnd);
    final start = clamped.start;
    final end = clamped.end;
    if (start != end && text.substring(start, end).contains('\n')) {
      return null;
    }

    final workingText = start == end
        ? text
        : '${text.substring(0, start)}${text.substring(end)}';
    final cursor = start;

    if (isOffsetInsideFencedCodeBlock(workingText, cursor)) {
      return null;
    }

    final bounds = _getLineBounds(workingText, cursor);
    final lineStart = bounds.lineStart;
    final lineEnd = bounds.lineEnd;
    final currentLine = workingText.substring(lineStart, lineEnd);
    final matched = _matchSmartPrefix(currentLine);
    if (matched == null) {
      return null;
    }

    final cursorInLine = cursor - lineStart;
    if (cursorInLine < matched.prefixLen) {
      return null;
    }

    if (matched.body.trim().isEmpty) {
      final nextText =
          '${workingText.substring(0, lineStart)}${workingText.substring(lineEnd)}';
      return NoteEditorTextEdit(
        text: nextText,
        selectionStart: lineStart,
        selectionEnd: lineStart,
      );
    }

    final inserted = '\n${matched.nextPrefix}';
    final nextText =
        '${workingText.substring(0, cursor)}$inserted${workingText.substring(cursor)}';
    final nextCursor = cursor + inserted.length;
    return NoteEditorTextEdit(
      text: nextText,
      selectionStart: nextCursor,
      selectionEnd: nextCursor,
    );
  }

  /// Computes smart Backspace exit when the cursor sits inside/after the prefix
  /// of an otherwise empty list item or blockquote without deleting preceding
  /// lines.
  static NoteEditorTextEdit? applySmartBackspace(
    String text,
    int selectionStart,
    int selectionEnd,
  ) {
    final clamped = _clampSelection(text.length, selectionStart, selectionEnd);
    final start = clamped.start;
    final end = clamped.end;
    if (start != end) {
      return null;
    }

    if (isOffsetInsideFencedCodeBlock(text, start)) {
      return null;
    }

    final bounds = _getLineBounds(text, start);
    final lineStart = bounds.lineStart;
    final lineEnd = bounds.lineEnd;
    if (start <= lineStart) {
      return null;
    }

    final currentLine = text.substring(lineStart, lineEnd);
    final matched = _matchSmartPrefix(currentLine);
    if (matched == null || matched.body.trim().isNotEmpty) {
      return null;
    }

    final targetOffset = lineStart + matched.indent.length;
    if (start <= targetOffset) {
      return null;
    }

    final nextText =
        '${text.substring(0, lineStart)}${matched.indent}${text.substring(lineEnd)}';
    return NoteEditorTextEdit(
      text: nextText,
      selectionStart: targetOffset,
      selectionEnd: targetOffset,
    );
  }
}
