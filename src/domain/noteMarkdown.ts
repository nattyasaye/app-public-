export type NoteMarkdownInline =
  | { type: 'text'; text: string }
  | { type: 'bold'; children: NoteMarkdownInline[] }
  | { type: 'italic'; children: NoteMarkdownInline[] }
  | { type: 'strikethrough'; children: NoteMarkdownInline[] }
  | { type: 'code'; code: string }
  | { type: 'link'; label: string; url: string }
  | { type: 'internalLink'; targetTitle: string; rawText: string };

export interface NoteMarkdownOrderedItem {
  number: number;
  inlines: NoteMarkdownInline[];
}

export interface NoteMarkdownChecklistItem {
  checked: boolean;
  inlines: NoteMarkdownInline[];
  lineIndex: number;
}

export type NoteMarkdownBlock =
  | { type: 'heading'; level: 1 | 2 | 3; inlines: NoteMarkdownInline[] }
  | { type: 'paragraph'; inlines: NoteMarkdownInline[] }
  | { type: 'bulletList'; items: NoteMarkdownInline[][] }
  | { type: 'orderedList'; start: number; items: NoteMarkdownOrderedItem[] }
  | { type: 'checklist'; items: NoteMarkdownChecklistItem[] }
  | { type: 'blockquote'; lines: NoteMarkdownInline[][] }
  | { type: 'codeBlock'; language: string; code: string }
  | { type: 'horizontalRule' };

export interface NoteMarkdownDocument {
  blocks: NoteMarkdownBlock[];
}

const ALLOWED_URL_SCHEMES: ReadonlySet<string> = new Set([
  'http',
  'https',
  'mailto',
]);

const MAX_INLINE_DEPTH = 8;

function isWhitespaceChar(ch: string | undefined): boolean {
  if (!ch) return false;
  return ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r';
}

function hasControlChars(value: string): boolean {
  for (let i = 0; i < value.length; i += 1) {
    const code = value.charCodeAt(i);
    if (code <= 0x1f || code === 0x7f) {
      return true;
    }
  }
  return false;
}

/**
 * Validates a Markdown link URL using a strict fail-closed scheme allowlist.
 * Permits only explicit `http:`, `https:`, and `mailto:` URLs with no control
 * characters or whitespace. Returns null for unsafe or malformed URLs.
 */
export function sanitizeMarkdownUrl(rawUrl: string | null | undefined): string | null {
  if (typeof rawUrl !== 'string') return null;
  const trimmed = rawUrl.trim();
  if (!trimmed || hasControlChars(trimmed) || /\s/.test(trimmed)) {
    return null;
  }
  if (trimmed.startsWith('//')) {
    return null;
  }
  const colonIdx = trimmed.indexOf(':');
  if (colonIdx <= 0) {
    return null;
  }
  const scheme = trimmed.slice(0, colonIdx).toLowerCase();
  if (!/^[a-z][a-z0-9+.-]*$/.test(scheme) || !ALLOWED_URL_SCHEMES.has(scheme)) {
    return null;
  }

  if (scheme === 'http' || scheme === 'https') {
    const prefix = `${scheme}://`;
    if (!trimmed.toLowerCase().startsWith(prefix)) {
      return null;
    }
    const rest = trimmed.slice(prefix.length);
    const authorityEnd = rest.search(/[/?#]/);
    const authority = authorityEnd === -1 ? rest : rest.slice(0, authorityEnd);
    if (!authority || authority.startsWith('@')) {
      return null;
    }
    return trimmed;
  }

  // mailto:
  const target = trimmed.slice('mailto:'.length);
  if (!target || /[<>"']/.test(target)) {
    return null;
  }
  return trimmed;
}

function pushTextNode(nodes: NoteMarkdownInline[], text: string): void {
  if (!text) return;
  const last = nodes[nodes.length - 1];
  if (last && last.type === 'text') {
    last.text += text;
  } else {
    nodes.push({ type: 'text', text });
  }
}

function findInlineCodeClose(text: string, openIdx: number): number {
  for (let idx = openIdx + 1; idx < text.length; idx += 1) {
    const ch = text[idx];
    if (ch === '\n') return -1;
    if (ch === '`') return idx;
  }
  return -1;
}

function findClosingMarker(text: string, startIdx: number, marker: '**' | '~~'): number {
  let idx = startIdx;
  while (idx <= text.length - marker.length) {
    if (text[idx] === '`') {
      const codeClose = findInlineCodeClose(text, idx);
      if (codeClose !== -1) {
        idx = codeClose + 1;
        continue;
      }
    }
    if (text.startsWith(marker, idx)) {
      if (
        marker === '**' &&
        text.startsWith('***', idx) &&
        idx + 1 <= text.length - 2 &&
        !isWhitespaceChar(text[idx])
      ) {
        // Prefer matching the trailing `**` of `***` when inner italic also needs `*`
        if (idx > startIdx && !isWhitespaceChar(text[idx - 1])) {
          return idx + 1;
        }
      }
      if (idx > startIdx && !isWhitespaceChar(text[idx - 1])) {
        return idx;
      }
    }
    idx += 1;
  }
  return -1;
}

function findClosingSingleAsterisk(text: string, startIdx: number): number {
  let idx = startIdx;
  while (idx < text.length) {
    if (text[idx] === '`') {
      const codeClose = findInlineCodeClose(text, idx);
      if (codeClose !== -1) {
        idx = codeClose + 1;
        continue;
      }
    }
    if (text[idx] === '*') {
      if (text.startsWith('**', idx) && !text.startsWith('***', idx)) {
        idx += 2;
        continue;
      }
      if (idx > startIdx && !isWhitespaceChar(text[idx - 1])) {
        return idx;
      }
    }
    idx += 1;
  }
  return -1;
}

interface ParsedBracketLink {
  label: string;
  rawUrl: string;
  endIndex: number;
}

interface ParsedInternalLink {
  targetTitle: string;
  rawText: string;
  endIndex: number;
}

function tryParseInternalLink(
  text: string,
  bracketStart: number
): ParsedInternalLink | null {
  if (text[bracketStart] !== '[' || text[bracketStart + 1] !== '[') {
    return null;
  }
  for (let j = bracketStart + 2; j < text.length - 1; j += 1) {
    const ch = text[j];
    if (ch === '\n' || ch === '\r') return null;
    if (ch === '[' && text[j + 1] === '[') return null;
    if (ch === ']' && text[j + 1] === ']') {
      const inner = text.slice(bracketStart + 2, j);
      const targetTitle = inner.trim();
      if (!targetTitle) return null;
      return {
        targetTitle,
        rawText: text.slice(bracketStart, j + 2),
        endIndex: j + 2,
      };
    }
  }
  return null;
}

function tryParseBracketLink(text: string, bracketStart: number): ParsedBracketLink | null {
  if (text[bracketStart] !== '[') return null;
  let closeBracket = -1;
  for (let j = bracketStart + 1; j < text.length; j += 1) {
    const ch = text[j];
    if (ch === '\n' || ch === '[') return null;
    if (ch === ']') {
      closeBracket = j;
      break;
    }
  }
  if (closeBracket === -1 || text[closeBracket + 1] !== '(') {
    return null;
  }

  let depth = 1;
  let closeParen = -1;
  for (let k = closeBracket + 2; k < text.length; k += 1) {
    const ch = text[k];
    if (ch === '\n') return null;
    if (ch === '(') {
      depth += 1;
    } else if (ch === ')') {
      depth -= 1;
      if (depth === 0) {
        closeParen = k;
        break;
      }
    }
  }
  if (closeParen === -1) return null;

  return {
    label: text.slice(bracketStart + 1, closeBracket),
    rawUrl: text.slice(closeBracket + 2, closeParen),
    endIndex: closeParen + 1,
  };
}

function parseInlineRange(text: string, depth: number): NoteMarkdownInline[] {
  if (!text) return [];
  if (depth >= MAX_INLINE_DEPTH) {
    return [{ type: 'text', text }];
  }

  const nodes: NoteMarkdownInline[] = [];
  let i = 0;

  while (i < text.length) {
    const ch = text[i];

    // Image syntax `![alt](url)` is intentionally inert plain text (no <img> loading)
    if (ch === '!' && text[i + 1] === '[') {
      const parsedImg = tryParseBracketLink(text, i + 1);
      if (parsedImg && parsedImg.label.trim().length > 0) {
        pushTextNode(nodes, parsedImg.label);
        i = parsedImg.endIndex;
        continue;
      }
    }

    // Internal note link `[[Note Title]]` (checked before single-bracket external links)
    if (ch === '[' && text[i + 1] === '[') {
      const parsedInternal = tryParseInternalLink(text, i);
      if (parsedInternal) {
        nodes.push({
          type: 'internalLink',
          targetTitle: parsedInternal.targetTitle,
          rawText: parsedInternal.rawText,
        });
        i = parsedInternal.endIndex;
        continue;
      }
    }

    // Link `[label](url)` with strict safe-URL validation
    if (ch === '[') {
      const parsedLink = tryParseBracketLink(text, i);
      if (parsedLink && parsedLink.label.trim().length > 0) {
        const safeUrl = sanitizeMarkdownUrl(parsedLink.rawUrl);
        if (safeUrl !== null) {
          nodes.push({
            type: 'link',
            label: parsedLink.label,
            url: safeUrl,
          });
        } else {
          // Unsafe link renders strictly as inert plain text
          pushTextNode(nodes, parsedLink.label);
        }
        i = parsedLink.endIndex;
        continue;
      }
    }

    // Inline code `` `code` ``
    if (ch === '`') {
      const closeIdx = findInlineCodeClose(text, i);
      if (closeIdx === i + 1) {
        pushTextNode(nodes, '``');
        i += 2;
        continue;
      }
      if (closeIdx > i + 1) {
        nodes.push({
          type: 'code',
          code: text.slice(i + 1, closeIdx),
        });
        i = closeIdx + 1;
        continue;
      }
    }

    // Bold `**text**`
    if (
      ch === '*' &&
      text.startsWith('**', i) &&
      i + 2 < text.length &&
      !isWhitespaceChar(text[i + 2])
    ) {
      const closeIdx = findClosingMarker(text, i + 2, '**');
      if (closeIdx !== -1) {
        nodes.push({
          type: 'bold',
          children: parseInlineRange(text.slice(i + 2, closeIdx), depth + 1),
        });
        i = closeIdx + 2;
        continue;
      }
    }

    // Strikethrough `~~text~~`
    if (
      ch === '~' &&
      text.startsWith('~~', i) &&
      i + 2 < text.length &&
      !isWhitespaceChar(text[i + 2])
    ) {
      const closeIdx = findClosingMarker(text, i + 2, '~~');
      if (closeIdx !== -1) {
        nodes.push({
          type: 'strikethrough',
          children: parseInlineRange(text.slice(i + 2, closeIdx), depth + 1),
        });
        i = closeIdx + 2;
        continue;
      }
    }

    // Italic `*text*`
    if (
      ch === '*' &&
      !text.startsWith('**', i) &&
      i + 1 < text.length &&
      !isWhitespaceChar(text[i + 1])
    ) {
      const closeIdx = findClosingSingleAsterisk(text, i + 1);
      if (closeIdx !== -1) {
        nodes.push({
          type: 'italic',
          children: parseInlineRange(text.slice(i + 1, closeIdx), depth + 1),
        });
        i = closeIdx + 1;
        continue;
      }
    }

    pushTextNode(nodes, ch);
    i += 1;
  }

  return nodes;
}

export function parseNoteMarkdownInlines(text: string): NoteMarkdownInline[] {
  if (!text) return [];
  return parseInlineRange(text, 0);
}

const FENCE_OPEN_RE = /^ {0,3}```(.*)$/;
const FENCE_CLOSE_RE = /^ {0,3}```+\s*$/;
const HR_RE = /^ {0,3}-{3,}\s*$/;
const HEADING_RE = /^ {0,3}(#{1,3})[ \t]+(.*)$/;
const BLOCKQUOTE_RE = /^ {0,3}> ?(.*)$/;
const CHECKLIST_RE = /^\s*[-*][ \t]+\[([ xX])\](?:[ \t]+(.*))?$/;
const BULLET_RE = /^\s*[-*][ \t]+(.*)$/;
const ORDERED_RE = /^\s*(\d+)\.[ \t]+(.*)$/;

function matchFenceOpen(line: string): string | null {
  const m = line.match(FENCE_OPEN_RE);
  if (!m) return null;
  const info = m[1];
  if (info.includes('`')) return null;
  return info.trim();
}

function isBlockBoundaryLine(line: string): boolean {
  if (line.trim().length === 0) return true;
  if (matchFenceOpen(line) !== null) return true;
  if (HR_RE.test(line)) return true;
  if (HEADING_RE.test(line)) return true;
  if (BLOCKQUOTE_RE.test(line)) return true;
  if (CHECKLIST_RE.test(line)) return true;
  if (BULLET_RE.test(line)) return true;
  if (ORDERED_RE.test(line)) return true;
  return false;
}

/**
 * Parses lightweight Markdown source into an immutable block/inline AST.
 * Never mutates the input string and never executes or trusts embedded HTML.
 */
export function parseNoteMarkdown(source: string | null | undefined): NoteMarkdownDocument {
  if (typeof source !== 'string' || source.length === 0) {
    return { blocks: [] };
  }

  const normalized = source.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  const lines = normalized.split('\n');
  const blocks: NoteMarkdownBlock[] = [];

  let i = 0;
  while (i < lines.length) {
    const line = lines[i];

    // 1. Blank line separator
    if (line.trim().length === 0) {
      i += 1;
      continue;
    }

    // 2. Fenced code block
    const fenceLang = matchFenceOpen(line);
    if (fenceLang !== null) {
      const codeLines: string[] = [];
      i += 1;
      while (i < lines.length) {
        if (FENCE_CLOSE_RE.test(lines[i])) {
          i += 1;
          break;
        }
        codeLines.push(lines[i]);
        i += 1;
      }
      blocks.push({
        type: 'codeBlock',
        language: fenceLang,
        code: codeLines.join('\n'),
      });
      continue;
    }

    // 3. Horizontal rule
    if (HR_RE.test(line)) {
      blocks.push({ type: 'horizontalRule' });
      i += 1;
      continue;
    }

    // 4. Headings (#, ##, ###)
    const headingMatch = line.match(HEADING_RE);
    if (headingMatch) {
      const level = headingMatch[1].length as 1 | 2 | 3;
      const text = headingMatch[2].trimEnd();
      blocks.push({
        type: 'heading',
        level,
        inlines: parseNoteMarkdownInlines(text),
      });
      i += 1;
      continue;
    }

    // 5. Blockquote
    if (BLOCKQUOTE_RE.test(line)) {
      const quoteLines: NoteMarkdownInline[][] = [];
      while (i < lines.length) {
        const qMatch = lines[i].match(BLOCKQUOTE_RE);
        if (!qMatch) break;
        quoteLines.push(parseNoteMarkdownInlines(qMatch[1]));
        i += 1;
      }
      blocks.push({
        type: 'blockquote',
        lines: quoteLines,
      });
      continue;
    }

    // 6. Checklist (- [ ] / - [x])
    if (CHECKLIST_RE.test(line)) {
      const items: NoteMarkdownChecklistItem[] = [];
      while (i < lines.length) {
        const cMatch = lines[i].match(CHECKLIST_RE);
        if (!cMatch) break;
        items.push({
          checked: cMatch[1].toLowerCase() === 'x',
          inlines: parseNoteMarkdownInlines(cMatch[2] ?? ''),
          lineIndex: i,
        });
        i += 1;
      }
      blocks.push({
        type: 'checklist',
        items,
      });
      continue;
    }

    // 7. Bulleted list (- / *)
    if (BULLET_RE.test(line)) {
      const items: NoteMarkdownInline[][] = [];
      while (i < lines.length) {
        if (CHECKLIST_RE.test(lines[i])) break;
        const bMatch = lines[i].match(BULLET_RE);
        if (!bMatch) break;
        items.push(parseNoteMarkdownInlines(bMatch[1]));
        i += 1;
      }
      blocks.push({
        type: 'bulletList',
        items,
      });
      continue;
    }

    // 8. Numbered list (1. item)
    if (ORDERED_RE.test(line)) {
      const items: NoteMarkdownOrderedItem[] = [];
      let start = 1;
      while (i < lines.length) {
        const oMatch = lines[i].match(ORDERED_RE);
        if (!oMatch) break;
        const num = Number.parseInt(oMatch[1], 10);
        if (items.length === 0) {
          start = Number.isFinite(num) ? num : 1;
        }
        items.push({
          number: Number.isFinite(num) ? num : items.length + 1,
          inlines: parseNoteMarkdownInlines(oMatch[2]),
        });
        i += 1;
      }
      blocks.push({
        type: 'orderedList',
        start,
        items,
      });
      continue;
    }

    // 9. Ordinary paragraph
    const paraLines: string[] = [];
    while (i < lines.length && !isBlockBoundaryLine(lines[i])) {
      paraLines.push(lines[i]);
      i += 1;
    }
    if (paraLines.length > 0) {
      blocks.push({
        type: 'paragraph',
        inlines: parseNoteMarkdownInlines(paraLines.join('\n')),
      });
    } else {
      i += 1;
    }
  }

  return { blocks };
}

export function inlinesToPlainText(inlines: readonly NoteMarkdownInline[]): string {
  return inlines
    .map((node) => {
      switch (node.type) {
        case 'text':
          return node.text;
        case 'code':
          return node.code;
        case 'link':
          return node.label;
        case 'internalLink':
          return node.targetTitle;
        case 'bold':
        case 'italic':
        case 'strikethrough':
          return inlinesToPlainText(node.children);
      }
    })
    .join('');
}

/**
 * Produces a readable plain-text preview string from Markdown source for list
 * card snippets without mutating the underlying Markdown content.
 */
export function markdownToPlainText(source: string | null | undefined): string {
  const doc = parseNoteMarkdown(source);
  const parts: string[] = [];
  for (const block of doc.blocks) {
    switch (block.type) {
      case 'heading':
      case 'paragraph': {
        const text = inlinesToPlainText(block.inlines).trim();
        if (text) parts.push(text);
        break;
      }
      case 'bulletList': {
        for (const item of block.items) {
          const text = inlinesToPlainText(item).trim();
          if (text) parts.push(text);
        }
        break;
      }
      case 'orderedList': {
        for (const item of block.items) {
          const text = inlinesToPlainText(item.inlines).trim();
          if (text) parts.push(text);
        }
        break;
      }
      case 'checklist': {
        for (const item of block.items) {
          const text = inlinesToPlainText(item.inlines).trim();
          if (text) parts.push(text);
        }
        break;
      }
      case 'blockquote': {
        for (const line of block.lines) {
          const text = inlinesToPlainText(line).trim();
          if (text) parts.push(text);
        }
        break;
      }
      case 'codeBlock': {
        if (block.code.trim()) parts.push(block.code);
        break;
      }
      case 'horizontalRule':
        break;
    }
  }
  return parts.join('\n');
}

export interface NoteChecklistToggleResult {
  text: string;
  checked: boolean;
  lineIndex: number;
}

export interface NoteChecklistLineStatus {
  lineIndex: number;
  checked: boolean;
}

interface SourceLineSpan {
  start: number;
  end: number;
}

const CHECKLIST_TOGGLE_RE = /^(\s*[-*][ \t]+\[)([ xX])(\](?:[ \t].*)?)$/;

function splitSourceLineSpans(source: string): SourceLineSpan[] {
  const spans: SourceLineSpan[] = [];
  let lineStart = 0;
  let i = 0;
  while (i < source.length) {
    const ch = source[i];
    if (ch === '\r') {
      spans.push({ start: lineStart, end: i });
      if (source[i + 1] === '\n') {
        i += 2;
      } else {
        i += 1;
      }
      lineStart = i;
      continue;
    }
    if (ch === '\n') {
      spans.push({ start: lineStart, end: i });
      i += 1;
      lineStart = i;
      continue;
    }
    i += 1;
  }
  spans.push({ start: lineStart, end: source.length });
  return spans;
}

function isLineIndexInsideFence(
  source: string,
  spans: readonly SourceLineSpan[],
  targetLineIndex: number
): boolean {
  let inFence = false;
  for (let idx = 0; idx < targetLineIndex && idx < spans.length; idx += 1) {
    const line = source.slice(spans[idx].start, spans[idx].end);
    if (!inFence) {
      if (matchFenceOpen(line) !== null) {
        inFence = true;
      }
    } else if (FENCE_CLOSE_RE.test(line)) {
      inFence = false;
    }
  }
  return inFence;
}

function findLineIndexForOffset(
  spans: readonly SourceLineSpan[],
  offset: number
): number {
  for (let idx = 0; idx < spans.length; idx += 1) {
    if (offset <= spans[idx].end) {
      return idx;
    }
  }
  return Math.max(0, spans.length - 1);
}

/**
 * Toggles a single Markdown checklist item (`- [ ]` <-> `- [x]`) at `lineIndex`
 * while preserving all other lines, formatting, whitespace, and line endings.
 * Returns `null` if `lineIndex` is out of range, inside a fenced code block,
 * an ordinary bullet, or malformed checklist syntax.
 */
export function toggleNoteMarkdownChecklistAtLine(
  source: string | null | undefined,
  lineIndex: number
): NoteChecklistToggleResult | null {
  if (typeof source !== 'string' || source.length === 0) return null;
  if (!Number.isInteger(lineIndex) || lineIndex < 0) return null;

  const spans = splitSourceLineSpans(source);
  if (lineIndex >= spans.length) return null;
  if (isLineIndexInsideFence(source, spans, lineIndex)) return null;

  const span = spans[lineIndex];
  const rawLine = source.slice(span.start, span.end);
  const match = rawLine.match(CHECKLIST_TOGGLE_RE);
  if (!match) return null;

  const nextChecked = match[2].toLowerCase() !== 'x';
  const nextLine = `${match[1]}${nextChecked ? 'x' : ' '}${match[3]}`;
  return {
    text: `${source.slice(0, span.start)}${nextLine}${source.slice(span.end)}`,
    checked: nextChecked,
    lineIndex,
  };
}

/**
 * Inspects whether a single-line cursor/selection sits on a valid Markdown
 * checklist line outside fenced code blocks (used for Write-mode toggling).
 */
export function getNoteMarkdownChecklistAtSelection(
  source: string | null | undefined,
  selectionStart: number,
  selectionEnd: number
): NoteChecklistLineStatus | null {
  if (typeof source !== 'string' || source.length === 0) return null;
  const a = Math.max(0, Math.min(source.length, Math.trunc(selectionStart)));
  const b = Math.max(0, Math.min(source.length, Math.trunc(selectionEnd)));
  const start = Math.min(a, b);
  const end = Math.max(a, b);

  const spans = splitSourceLineSpans(source);
  const startLine = findLineIndexForOffset(spans, start);
  const endLine = findLineIndexForOffset(spans, end);
  if (startLine !== endLine) return null;
  if (isLineIndexInsideFence(source, spans, startLine)) return null;

  const span = spans[startLine];
  const rawLine = source.slice(span.start, span.end);
  const match = rawLine.match(CHECKLIST_TOGGLE_RE);
  if (!match) return null;

  return {
    lineIndex: startLine,
    checked: match[2].toLowerCase() === 'x',
  };
}

