export type NoteToolbarFormatAction =
  | 'heading2'
  | 'bold'
  | 'italic'
  | 'strikethrough'
  | 'bulletList'
  | 'numberedList'
  | 'checklist'
  | 'blockquote'
  | 'inlineCode'
  | 'codeBlock'
  | 'internalLink';

export interface NoteEditorTextEdit {
  text: string;
  selectionStart: number;
  selectionEnd: number;
}

type InlineMarker = '**' | '*' | '~~' | '`';

type LinePrefixKind =
  | 'none'
  | 'heading2'
  | 'headingOther'
  | 'bulletList'
  | 'numberedList'
  | 'checklist'
  | 'blockquote';

interface ParsedLinePrefix {
  indent: string;
  prefixKind: LinePrefixKind;
  prefixLen: number;
  body: string;
}

const FENCE_OPEN_RE = /^ {0,3}```[^`]*$/;
const FENCE_CLOSE_RE = /^ {0,3}```+\s*$/;

const CHECKLIST_LINE_RE = /^([ \t]*)([-*][ \t]+\[[ xX]\](?:[ \t]+|$))(.*)$/;
const HEADING_LINE_RE = /^([ \t]*)(#{1,3}(?:[ \t]+|$))(.*)$/;
const BULLET_LINE_RE = /^([ \t]*)([-*](?:[ \t]+|$))(.*)$/;
const ORDERED_LINE_RE = /^([ \t]*)(\d+\.(?:[ \t]+|$))(.*)$/;
const BLOCKQUOTE_LINE_RE = /^([ \t]*)(>(?:[ \t]?|$))(.*)$/;
const LEADING_WS_RE = /^([ \t]*)(.*)$/;

const SMART_CHECKLIST_RE = /^([ \t]*)([-*])[ \t]+\[([ xX])\](?:[ \t](.*))?$/;
const SMART_BULLET_RE = /^([ \t]*)([-*])[ \t](.*)$/;
const SMART_ORDERED_RE = /^([ \t]*)(\d+)\.[ \t](.*)$/;
const SMART_BLOCKQUOTE_RE = /^([ \t]*)>[ \t]?(.*)$/;

function clampSelection(
  textLength: number,
  rawStart: number,
  rawEnd: number
): { start: number; end: number } {
  const a = Math.max(0, Math.min(textLength, Math.trunc(rawStart)));
  const b = Math.max(0, Math.min(textLength, Math.trunc(rawEnd)));
  return a <= b ? { start: a, end: b } : { start: b, end: a };
}

function getLineBounds(
  text: string,
  offset: number
): { lineStart: number; lineEnd: number } {
  const clamped = Math.max(0, Math.min(text.length, offset));
  let lineStart = 0;
  if (clamped > 0) {
    const prevNl = text.lastIndexOf('\n', clamped - 1);
    lineStart = prevNl === -1 ? 0 : prevNl + 1;
  }
  const nextNl = text.indexOf('\n', clamped);
  const lineEnd = nextNl === -1 ? text.length : nextNl;
  return { lineStart, lineEnd };
}

/**
 * Returns true if the line containing `offset` lies inside an open fenced code
 * block (preceded by an unclosed triple-backtick opening line).
 */
export function isOffsetInsideFencedCodeBlock(
  text: string,
  offset: number
): boolean {
  const { lineStart } = getLineBounds(text, offset);
  const prefixText = lineStart > 0 ? text.slice(0, lineStart - 1) : '';
  if (!prefixText && lineStart === 0) return false;
  const precedingLines = lineStart === 0 ? [] : prefixText.split('\n');
  let inFence = false;
  for (const line of precedingLines) {
    if (!inFence) {
      if (FENCE_OPEN_RE.test(line)) {
        inFence = true;
      }
    } else if (FENCE_CLOSE_RE.test(line)) {
      inFence = false;
    }
  }
  if (!inFence) return false;
  const { lineEnd } = getLineBounds(text, offset);
  const currentLine = text.slice(lineStart, lineEnd);
  return !FENCE_CLOSE_RE.test(currentLine);
}

function hasSelfInlineWrapper(value: string, marker: InlineMarker): boolean {
  if (value.length < marker.length * 2) return false;
  if (!value.startsWith(marker) || !value.endsWith(marker)) return false;

  if (marker === '`') {
    return !value.startsWith('```') && !value.endsWith('```');
  }
  if (marker === '*') {
    const isSingle = !value.startsWith('**') && !value.endsWith('**');
    const isTriple =
      value.length >= 6 && value.startsWith('***') && value.endsWith('***');
    return isSingle || isTriple;
  }
  return true;
}

function hasSurroundingInlineWrapper(
  before: string,
  after: string,
  marker: InlineMarker
): boolean {
  if (!before.endsWith(marker) || !after.startsWith(marker)) return false;

  if (marker === '`') {
    return !before.endsWith('```') && !after.startsWith('```');
  }
  if (marker === '*') {
    const isTriple = before.endsWith('***') && after.startsWith('***');
    const isSingle =
      !before.endsWith('**') &&
      !after.startsWith('**');
    return isTriple || isSingle;
  }
  return true;
}

function applyInlineFormatting(
  text: string,
  start: number,
  end: number,
  marker: InlineMarker
): NoteEditorTextEdit {
  const before = text.slice(0, start);
  const selected = text.slice(start, end);
  const after = text.slice(end);

  if (selected.length > 0 && hasSelfInlineWrapper(selected, marker)) {
    const inner = selected.slice(marker.length, selected.length - marker.length);
    return {
      text: `${before}${inner}${after}`,
      selectionStart: start,
      selectionEnd: start + inner.length,
    };
  }

  if (hasSurroundingInlineWrapper(before, after, marker)) {
    const trimmedBefore = before.slice(0, before.length - marker.length);
    const trimmedAfter = after.slice(marker.length);
    return {
      text: `${trimmedBefore}${selected}${trimmedAfter}`,
      selectionStart: start - marker.length,
      selectionEnd: end - marker.length,
    };
  }

  if (start === end) {
    return {
      text: `${before}${marker}${marker}${after}`,
      selectionStart: start + marker.length,
      selectionEnd: start + marker.length,
    };
  }

  // Preserve leading/trailing whitespace on inline selection so Markdown renders cleanly
  const leadMatch = selected.match(/^([ \t\r\n]*)/);
  const trailMatch = selected.match(/([ \t\r\n]*)$/);
  const leadWs = leadMatch ? leadMatch[1] : '';
  const trailWs = trailMatch ? trailMatch[1] : '';

  if (leadWs.length + trailWs.length >= selected.length) {
    return {
      text: `${before}${marker}${marker}${selected}${after}`,
      selectionStart: start + marker.length,
      selectionEnd: start + marker.length,
    };
  }

  const core = selected.slice(leadWs.length, selected.length - trailWs.length);
  if (hasSelfInlineWrapper(core, marker)) {
    const inner = core.slice(marker.length, core.length - marker.length);
    const innerStart = start + leadWs.length;
    return {
      text: `${before}${leadWs}${inner}${trailWs}${after}`,
      selectionStart: innerStart,
      selectionEnd: innerStart + inner.length,
    };
  }

  const wrappedStart = start + leadWs.length + marker.length;
  return {
    text: `${before}${leadWs}${marker}${core}${marker}${trailWs}${after}`,
    selectionStart: wrappedStart,
    selectionEnd: wrappedStart + core.length,
  };
}

function parseLinePrefix(line: string): ParsedLinePrefix {
  const checklist = line.match(CHECKLIST_LINE_RE);
  if (checklist) {
    return {
      indent: checklist[1],
      prefixKind: 'checklist',
      prefixLen: checklist[2].length,
      body: checklist[3],
    };
  }
  const heading = line.match(HEADING_LINE_RE);
  if (heading) {
    const hashes = heading[2].trim();
    return {
      indent: heading[1],
      prefixKind: hashes === '##' ? 'heading2' : 'headingOther',
      prefixLen: heading[2].length,
      body: heading[3],
    };
  }
  const bullet = line.match(BULLET_LINE_RE);
  if (bullet) {
    return {
      indent: bullet[1],
      prefixKind: 'bulletList',
      prefixLen: bullet[2].length,
      body: bullet[3],
    };
  }
  const ordered = line.match(ORDERED_LINE_RE);
  if (ordered) {
    return {
      indent: ordered[1],
      prefixKind: 'numberedList',
      prefixLen: ordered[2].length,
      body: ordered[3],
    };
  }
  const quote = line.match(BLOCKQUOTE_LINE_RE);
  if (quote) {
    return {
      indent: quote[1],
      prefixKind: 'blockquote',
      prefixLen: quote[2].length,
      body: quote[3],
    };
  }
  const ws = line.match(LEADING_WS_RE);
  return {
    indent: ws ? ws[1] : '',
    prefixKind: 'none',
    prefixLen: 0,
    body: ws ? ws[2] : line,
  };
}

type LineActionKind =
  | 'heading2'
  | 'bulletList'
  | 'numberedList'
  | 'checklist'
  | 'blockquote';

function buildBlockLinePrefix(kind: LineActionKind, indexNumber: number): string {
  switch (kind) {
    case 'heading2':
      return '## ';
    case 'bulletList':
      return '- ';
    case 'numberedList':
      return `${indexNumber}. `;
    case 'checklist':
      return '- [ ] ';
    case 'blockquote':
      return '> ';
  }
}

function mapOffsetInRewrittenLine(
  pos: number,
  oldLineStart: number,
  newLineStart: number,
  indentLen: number,
  oldPrefixLen: number,
  newPrefixLen: number
): number {
  const posInLine = pos - oldLineStart;
  const oldContentStart = indentLen + oldPrefixLen;
  const newContentStart = indentLen + newPrefixLen;
  if (posInLine >= oldContentStart) {
    return newLineStart + newContentStart + (posInLine - oldContentStart);
  }
  if (posInLine <= indentLen) {
    return newLineStart + posInLine;
  }
  return newLineStart + newContentStart;
}

function applyBlockLineFormatting(
  text: string,
  start: number,
  end: number,
  action: LineActionKind
): NoteEditorTextEdit {
  const { lineStart: blockStart } = getLineBounds(text, start);
  const effectiveEnd =
    end > start && text[end - 1] === '\n' ? end - 1 : end;
  const { lineEnd: blockEnd } = getLineBounds(text, effectiveEnd);

  const sliceText = text.slice(blockStart, blockEnd);
  const rawLines = sliceText.split('\n');
  const parsedLines = rawLines.map(parseLinePrefix);

  const relevantIndexes: number[] = [];
  if (rawLines.length === 1) {
    relevantIndexes.push(0);
  } else {
    for (let idx = 0; idx < rawLines.length; idx += 1) {
      if (rawLines[idx].trim().length > 0) {
        relevantIndexes.push(idx);
      }
    }
  }

  const shouldToggleOff =
    relevantIndexes.length > 0 &&
    relevantIndexes.every((idx) => parsedLines[idx].prefixKind === action);

  let orderedCounter = 1;
  let oldOffset = blockStart;
  let newOffset = blockStart;
  const rewrittenLines: string[] = [];

  let mappedStart = start;
  let mappedEnd = end;

  for (let idx = 0; idx < rawLines.length; idx += 1) {
    const rawLine = rawLines[idx];
    const parsed = parsedLines[idx];
    const oldLineStart = oldOffset;
    const oldLineEnd = oldOffset + rawLine.length;

    let newPrefix = '';
    let newLine = rawLine;
    let effectiveIndentLen = parsed.indent.length;
    let effectiveOldPrefixLen = parsed.prefixLen;

    if (rawLines.length > 1 && rawLine.trim().length === 0) {
      // Preserve blank lines untouched in multiline selections
      effectiveIndentLen = 0;
      effectiveOldPrefixLen = 0;
    } else if (shouldToggleOff) {
      newPrefix = '';
      newLine = `${parsed.indent}${parsed.body}`;
    } else {
      newPrefix = buildBlockLinePrefix(action, orderedCounter);
      if (action === 'numberedList') {
        orderedCounter += 1;
      }
      newLine = `${parsed.indent}${newPrefix}${parsed.body}`;
    }

    const newLineStart = newOffset;

    if (start >= oldLineStart && start <= oldLineEnd) {
      mappedStart =
        rawLines.length > 1 && rawLine.trim().length === 0
          ? newLineStart + (start - oldLineStart)
          : mapOffsetInRewrittenLine(
              start,
              oldLineStart,
              newLineStart,
              effectiveIndentLen,
              effectiveOldPrefixLen,
              newPrefix.length
            );
    }
    if (end >= oldLineStart && end <= oldLineEnd) {
      mappedEnd =
        rawLines.length > 1 && rawLine.trim().length === 0
          ? newLineStart + (end - oldLineStart)
          : mapOffsetInRewrittenLine(
              end,
              oldLineStart,
              newLineStart,
              effectiveIndentLen,
              effectiveOldPrefixLen,
              newPrefix.length
            );
    }

    rewrittenLines.push(newLine);
    oldOffset = oldLineEnd + 1;
    newOffset = newLineStart + newLine.length + 1;
  }

  const nextText = `${text.slice(0, blockStart)}${rewrittenLines.join('\n')}${text.slice(blockEnd)}`;
  const clamped = clampSelection(nextText.length, mappedStart, mappedEnd);
  return {
    text: nextText,
    selectionStart: clamped.start,
    selectionEnd: clamped.end,
  };
}

function applyFencedCodeBlockFormatting(
  text: string,
  start: number,
  end: number
): NoteEditorTextEdit {
  const before = text.slice(0, start);
  const selected = text.slice(start, end);
  const after = text.slice(end);

  const selfFenceMatch = selected.match(
    /^ {0,3}```[^\n]*\n([\s\S]*?)\n {0,3}```\s*$/
  );
  if (selfFenceMatch) {
    const inner = selfFenceMatch[1];
    return {
      text: `${before}${inner}${after}`,
      selectionStart: start,
      selectionEnd: start + inner.length,
    };
  }

  const leadingNl = before.length === 0 || before.endsWith('\n') ? '' : '\n';

  if (start === end) {
    const trailingNl = after.length === 0 || after.startsWith('\n') ? '' : '\n';
    const inserted = `${leadingNl}\`\`\`\n\n\`\`\`${trailingNl}`;
    const cursorPos = before.length + leadingNl.length + 4;
    return {
      text: `${before}${inserted}${after}`,
      selectionStart: cursorPos,
      selectionEnd: cursorPos,
    };
  }

  const hasTrailingNl = selected.endsWith('\n');
  const body = hasTrailingNl ? selected.slice(0, -1) : selected;
  const trailingNl =
    hasTrailingNl || (after.length > 0 && !after.startsWith('\n')) ? '\n' : '';
  const inserted = `${leadingNl}\`\`\`\n${body}\n\`\`\`${trailingNl}`;
  const innerStart = before.length + leadingNl.length + 4;
  return {
    text: `${before}${inserted}${after}`,
    selectionStart: innerStart,
    selectionEnd: innerStart + body.length,
  };
}

function applyInternalLinkFormatting(
  text: string,
  start: number,
  end: number
): NoteEditorTextEdit {
  const before = text.slice(0, start);
  const selected = text.slice(start, end);
  const after = text.slice(end);

  if (
    selected.length >= 4 &&
    selected.startsWith('[[') &&
    selected.endsWith(']]')
  ) {
    const inner = selected.slice(2, selected.length - 2);
    if (!inner.includes('[[') && !inner.includes(']]')) {
      return {
        text: `${before}${inner}${after}`,
        selectionStart: start,
        selectionEnd: start + inner.length,
      };
    }
  }

  if (
    before.endsWith('[[') &&
    after.startsWith(']]') &&
    !selected.includes('[[') &&
    !selected.includes(']]')
  ) {
    const trimmedBefore = before.slice(0, before.length - 2);
    const trimmedAfter = after.slice(2);
    return {
      text: `${trimmedBefore}${selected}${trimmedAfter}`,
      selectionStart: start - 2,
      selectionEnd: end - 2,
    };
  }

  if (start === end) {
    return {
      text: `${before}[[]]${after}`,
      selectionStart: start + 2,
      selectionEnd: start + 2,
    };
  }

  const leadMatch = selected.match(/^([ \t\r\n]*)/);
  const trailMatch = selected.match(/([ \t\r\n]*)$/);
  const leadWs = leadMatch ? leadMatch[1] : '';
  const trailWs = trailMatch ? trailMatch[1] : '';

  if (leadWs.length + trailWs.length >= selected.length) {
    return {
      text: `${before}[[]]${selected}${after}`,
      selectionStart: start + 2,
      selectionEnd: start + 2,
    };
  }

  const core = selected.slice(leadWs.length, selected.length - trailWs.length);
  if (core.length >= 4 && core.startsWith('[[') && core.endsWith(']]')) {
    const inner = core.slice(2, core.length - 2);
    if (!inner.includes('[[') && !inner.includes(']]')) {
      const innerStart = start + leadWs.length;
      return {
        text: `${before}${leadWs}${inner}${trailWs}${after}`,
        selectionStart: innerStart,
        selectionEnd: innerStart + inner.length,
      };
    }
  }

  const wrappedStart = start + leadWs.length + 2;
  return {
    text: `${before}${leadWs}[[${core}]]${trailWs}${after}`,
    selectionStart: wrappedStart,
    selectionEnd: wrappedStart + core.length,
  };
}

/**
 * Pure deterministic formatting handler shared by Web and Flutter toolbars.
 * Never trims unrelated whitespace or mutates the caller's input string.
 */
export function applyNoteToolbarFormat(
  text: string,
  selectionStart: number,
  selectionEnd: number,
  action: NoteToolbarFormatAction
): NoteEditorTextEdit {
  const { start, end } = clampSelection(text.length, selectionStart, selectionEnd);

  switch (action) {
    case 'bold':
      return applyInlineFormatting(text, start, end, '**');
    case 'italic':
      return applyInlineFormatting(text, start, end, '*');
    case 'strikethrough':
      return applyInlineFormatting(text, start, end, '~~');
    case 'inlineCode':
      return applyInlineFormatting(text, start, end, '`');
    case 'heading2':
    case 'bulletList':
    case 'numberedList':
    case 'checklist':
    case 'blockquote':
      return applyBlockLineFormatting(text, start, end, action);
    case 'codeBlock':
      return applyFencedCodeBlockFormatting(text, start, end);
    case 'internalLink':
      return applyInternalLinkFormatting(text, start, end);
  }
}

interface SmartPrefixInfo {
  prefixLen: number;
  body: string;
  nextPrefix: string;
  indent: string;
}

function matchSmartPrefix(line: string): SmartPrefixInfo | null {
  const checklist = line.match(SMART_CHECKLIST_RE);
  if (checklist) {
    const indent = checklist[1];
    const bulletChar = checklist[2];
    const body = checklist[4] ?? '';
    const prefixEnd = line.length - body.length;
    return {
      indent,
      prefixLen: prefixEnd,
      body,
      nextPrefix: `${indent}${bulletChar} [ ] `,
    };
  }

  const bullet = line.match(SMART_BULLET_RE);
  if (bullet) {
    const indent = bullet[1];
    const bulletChar = bullet[2];
    const body = bullet[3];
    const prefixEnd = indent.length + 2;
    return {
      indent,
      prefixLen: prefixEnd,
      body,
      nextPrefix: `${indent}${bulletChar} `,
    };
  }

  const ordered = line.match(SMART_ORDERED_RE);
  if (ordered) {
    const indent = ordered[1];
    const numStr = ordered[2];
    const body = ordered[3];
    const num = Number.parseInt(numStr, 10);
    const nextNum = Number.isFinite(num) ? num + 1 : 2;
    const prefixEnd = indent.length + numStr.length + 2;
    return {
      indent,
      prefixLen: prefixEnd,
      body,
      nextPrefix: `${indent}${nextNum}. `,
    };
  }

  const quote = line.match(SMART_BLOCKQUOTE_RE);
  if (quote) {
    const indent = quote[1];
    const body = quote[2];
    const prefixEnd = line.length - body.length;
    return {
      indent,
      prefixLen: prefixEnd,
      body,
      nextPrefix: `${indent}> `,
    };
  }

  return null;
}

/**
 * Computes smart Enter continuation or exit on bullets, numbered lists,
 * checklists, and blockquotes.
 * Returns `null` when normal Enter newline behavior should run instead
 * (ordinary paragraphs, inside fenced code blocks, or multiline selections).
 */
export function applyNoteSmartEnter(
  text: string,
  selectionStart: number,
  selectionEnd: number
): NoteEditorTextEdit | null {
  const { start, end } = clampSelection(text.length, selectionStart, selectionEnd);
  if (start !== end && text.slice(start, end).includes('\n')) {
    return null;
  }

  const workingText =
    start === end ? text : `${text.slice(0, start)}${text.slice(end)}`;
  const cursor = start;

  if (isOffsetInsideFencedCodeBlock(workingText, cursor)) {
    return null;
  }

  const { lineStart, lineEnd } = getLineBounds(workingText, cursor);
  const currentLine = workingText.slice(lineStart, lineEnd);
  const matched = matchSmartPrefix(currentLine);
  if (!matched) {
    return null;
  }

  const cursorInLine = cursor - lineStart;
  if (cursorInLine < matched.prefixLen) {
    return null;
  }

  // Exit empty list item or empty blockquote cleanly to a plain paragraph line
  if (matched.body.trim().length === 0) {
    const nextText = `${workingText.slice(0, lineStart)}${workingText.slice(lineEnd)}`;
    return {
      text: nextText,
      selectionStart: lineStart,
      selectionEnd: lineStart,
    };
  }

  // Continue non-empty item on the next line, splitting cleanly at cursor
  const inserted = `\n${matched.nextPrefix}`;
  const nextText = `${workingText.slice(0, cursor)}${inserted}${workingText.slice(cursor)}`;
  const nextCursor = cursor + inserted.length;
  return {
    text: nextText,
    selectionStart: nextCursor,
    selectionEnd: nextCursor,
  };
}

/**
 * Computes smart Backspace exit when the cursor sits inside/after the prefix of
 * an otherwise empty list item or blockquote without deleting preceding lines.
 * Returns `null` when normal Backspace behavior should run.
 */
export function applyNoteSmartBackspace(
  text: string,
  selectionStart: number,
  selectionEnd: number
): NoteEditorTextEdit | null {
  const { start, end } = clampSelection(text.length, selectionStart, selectionEnd);
  if (start !== end) {
    return null;
  }

  if (isOffsetInsideFencedCodeBlock(text, start)) {
    return null;
  }

  const { lineStart, lineEnd } = getLineBounds(text, start);
  if (start <= lineStart) {
    return null;
  }

  const currentLine = text.slice(lineStart, lineEnd);
  const matched = matchSmartPrefix(currentLine);
  if (!matched || matched.body.trim().length > 0) {
    return null;
  }

  const targetOffset = lineStart + matched.indent.length;
  if (start <= targetOffset) {
    return null;
  }

  const nextText = `${text.slice(0, lineStart)}${matched.indent}${text.slice(lineEnd)}`;
  return {
    text: nextText,
    selectionStart: targetOffset,
    selectionEnd: targetOffset,
  };
}
