import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { describe, it } from 'node:test';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { NoteMarkdownPreview } from '../components/notes/NoteMarkdownPreview';
import {
  inlinesToPlainText,
  markdownToPlainText,
  NoteMarkdownBlock,
  NoteMarkdownInline,
  parseNoteMarkdown,
  parseNoteMarkdownInlines,
  sanitizeMarkdownUrl,
} from './noteMarkdown';

interface SharedBlockCase {
  name: string;
  markdown: string;
  expectedBlockTypes: string[];
  expectedCodeBlocks?: Array<{ language: string; code: string }>;
  expectedPlainText?: string;
}

interface SharedInlineCase {
  name: string;
  input: string;
  expectedTypes: string[];
}

interface SharedUrlSafetyCase {
  url: string;
  expectedSafe: string | null;
}

interface SharedMarkdownVectors {
  blockCases: SharedBlockCase[];
  inlineCases: SharedInlineCase[];
  urlSafetyCases: SharedUrlSafetyCase[];
}

const repoRoot = path.resolve(process.cwd());
const vectorsPath = path.join(
  repoRoot,
  'shared_foundation',
  'fixtures',
  'note_markdown_vectors.json'
);
const vectors: SharedMarkdownVectors = JSON.parse(
  fs.readFileSync(vectorsPath, 'utf8')
);

function serializeBlockType(block: NoteMarkdownBlock): string {
  switch (block.type) {
    case 'heading':
      return `heading:${block.level}`;
    case 'paragraph':
      return 'paragraph';
    case 'bulletList':
      return `bulletList:${block.items.length}`;
    case 'orderedList':
      return `orderedList:${block.start}:${block.items.length}`;
    case 'checklist':
      return `checklist:${block.items.map((item) => item.checked).join(',')}`;
    case 'blockquote':
      return `blockquote:${block.lines.length}`;
    case 'codeBlock':
      return `codeBlock:${block.language}`;
    case 'horizontalRule':
      return 'horizontalRule';
  }
}

function serializeInline(node: NoteMarkdownInline): string {
  switch (node.type) {
    case 'text':
      return `text:${node.text}`;
    case 'code':
      return `code:${node.code}`;
    case 'link':
      return `link:${node.label}|${node.url}`;
    case 'internalLink':
      return `internalLink:${node.targetTitle}|${node.rawText}`;
    case 'bold':
      return `bold:[${node.children.map(serializeInline).join(',')}]`;
    case 'italic':
      return `italic:[${node.children.map(serializeInline).join(',')}]`;
    case 'strikethrough':
      return `strike:[${node.children.map(serializeInline).join(',')}]`;
  }
}

describe('Stage N2.1 — Lightweight Markdown Parser & Preview Renderer', () => {
  it('verifies all shared block test vectors identically against fixture contract', () => {
    for (const testCase of vectors.blockCases) {
      const originalSnapshot = `${testCase.markdown}`;
      const doc = parseNoteMarkdown(testCase.markdown);
      assert.deepEqual(
        doc.blocks.map(serializeBlockType),
        testCase.expectedBlockTypes,
        `Block types mismatch for case "${testCase.name}"`
      );
      if (testCase.expectedCodeBlocks) {
        const codeBlocks = doc.blocks
          .filter(
            (b): b is Extract<NoteMarkdownBlock, { type: 'codeBlock' }> =>
              b.type === 'codeBlock'
          )
          .map((b) => ({ language: b.language, code: b.code }));
        assert.deepEqual(
          codeBlocks,
          testCase.expectedCodeBlocks,
          `Code block content mismatch for case "${testCase.name}"`
        );
      }
      if (typeof testCase.expectedPlainText === 'string') {
        assert.equal(
          markdownToPlainText(testCase.markdown),
          testCase.expectedPlainText,
          `Plain text mismatch for case "${testCase.name}"`
        );
      }
      assert.equal(testCase.markdown, originalSnapshot);
    }
  });

  it('verifies all shared inline test vectors identically against fixture contract', () => {
    for (const testCase of vectors.inlineCases) {
      const parsed = parseNoteMarkdownInlines(testCase.input);
      assert.deepEqual(
        parsed.map(serializeInline),
        testCase.expectedTypes,
        `Inline AST mismatch for case "${testCase.name}"`
      );
    }
  });

  it('verifies all shared URL safety vectors fail closed on unsafe schemes', () => {
    for (const testCase of vectors.urlSafetyCases) {
      assert.equal(
        sanitizeMarkdownUrl(testCase.url),
        testCase.expectedSafe,
        `URL sanitization mismatch for "${testCase.url}"`
      );
    }
  });

  it('supports every required syntax category, multiline paragraphs, blank lines, and non-mutation', () => {
    const sampleSource = [
      '# Title One',
      '## Section Two',
      '### Subsection Three',
      '',
      'First paragraph line one',
      'line two with **bold**, *italic*, ~~strike~~, and `const x = 1`.',
      '',
      '- Bullet dash',
      '* Bullet star',
      '',
      '1. First ordered',
      '2. Second ordered',
      '',
      '- [ ] Pending box',
      '- [x] Checked box',
      '',
      '> Quoted thought',
      '> Second line',
      '',
      '---',
      '',
      '```ts',
      'function greet(name: string) {',
      '  return `Hello ${name}`;',
      '}',
      '```',
      '',
      'Tail   whitespace   preserved',
    ].join('\n');

    const snapshotCopy = String(sampleSource);
    const doc = parseNoteMarkdown(sampleSource);
    assert.equal(sampleSource, snapshotCopy);

    assert.deepEqual(
      doc.blocks.map((b) => b.type),
      [
        'heading',
        'heading',
        'heading',
        'paragraph',
        'bulletList',
        'orderedList',
        'checklist',
        'blockquote',
        'horizontalRule',
        'codeBlock',
        'paragraph',
      ]
    );

    const firstPara = doc.blocks[3];
    assert.equal(firstPara.type, 'paragraph');
    assert.equal(
      inlinesToPlainText(firstPara.inlines),
      'First paragraph line one\nline two with bold, italic, strike, and const x = 1.'
    );
    assert.equal(
      markdownToPlainText(sampleSource).includes('Tail   whitespace   preserved'),
      true
    );
  });

  it('handles empty, null/undefined, malformed, and deeply nested markers without throwing', () => {
    assert.deepEqual(parseNoteMarkdown('').blocks, []);
    assert.deepEqual(parseNoteMarkdown(null).blocks, []);
    assert.deepEqual(parseNoteMarkdown(undefined).blocks, []);
    assert.equal(markdownToPlainText('   \n\n  '), '');

    const malformed = [
      '***unclosed **bold *italic ~~strike `code',
      '1.NoSpaceAfterDot',
      '-NoSpaceDash',
      '>',
      '```',
      'unclosed code line',
    ].join('\n');
    const doc = parseNoteMarkdown(malformed);
    assert.equal(doc.blocks.length, 3);
    assert.equal(doc.blocks[0].type, 'paragraph');
    assert.equal(doc.blocks[1].type, 'blockquote');
    assert.equal(doc.blocks[2].type, 'codeBlock');

    // Deeply nested delimiters cap cleanly at MAX_INLINE_DEPTH without stack overflow
    const deep = `${'**'.repeat(20)}core${'**'.repeat(20)}`;
    const deepInlines = parseNoteMarkdownInlines(deep);
    assert.equal(inlinesToPlainText(deepInlines).includes('core'), true);
  });

  it('renders NoteMarkdownPreview safely via React without executing HTML, scripts, or unsafe links', () => {
    const hostileMarkdown = [
      '# Safe Heading',
      '',
      '<script>alert("xss")</script>',
      '<img src="x" onerror="alert(1)" />',
      '<iframe src="https://evil.example"></iframe>',
      '<svg onload="alert(1)"></svg>',
      '',
      'Bad links: [JS](javascript:alert(1)) [Data](data:text/html;base64,PHNjcmlwdD4=) [Mail](mailto:bad<x>@example.com)',
      'Good link: [Docs](https://daywell.example/notes?ref=1)',
      'Image syntax inert: ![Alt text](https://daywell.example/pic.png)',
      '',
      '- [ ] Open task',
      '- [x] Done task',
      '',
      '```html',
      '<script>console.log("inert")</script>',
      '```',
      '',
      '---',
    ].join('\n');

    const beforeRender = String(hostileMarkdown);
    const html = renderToStaticMarkup(
      React.createElement(NoteMarkdownPreview, { content: hostileMarkdown })
    );
    assert.equal(hostileMarkdown, beforeRender);

    // Zero raw injected elements
    assert.equal(html.includes('<script'), false);
    assert.equal(html.includes('<img'), false);
    assert.equal(html.includes('<iframe'), false);
    assert.equal(html.includes('<svg onload'), false);
    assert.equal(html.includes('javascript:'), false);
    assert.equal(html.includes('data:text/html'), false);

    // Escaped literal text present
    assert.equal(html.includes('&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;'), true);
    assert.equal(html.includes('&lt;img src=&quot;x&quot; onerror=&quot;alert(1)&quot; /&gt;'), true);
    assert.equal(html.includes('&lt;svg onload=&quot;alert(1)&quot;&gt;&lt;/svg&gt;'), true);
    assert.equal(html.includes('Alt text'), true);

    // Safe link rendered with strict rel attributes
    assert.equal(
      html.includes(
        '<a href="https://daywell.example/notes?ref=1" target="_blank" rel="noopener noreferrer nofollow"'
      ),
      true
    );

    // Required semantic elements rendered cleanly
    assert.equal(html.includes('<h1'), true);
    assert.equal(html.includes('<pre'), true);
    assert.equal(html.includes('<hr'), true);
    assert.equal(html.includes('Completed item: '), true);
    assert.equal(html.includes('Open item: '), true);

    // Empty preview renders friendly empty state
    const emptyHtml = renderToStaticMarkup(
      React.createElement(NoteMarkdownPreview, { content: '   \n\n  ' })
    );
    assert.equal(emptyHtml.includes('note-markdown-preview-empty'), true);
  });

  it('maintains Dart parser purity, token-only preview widget, and matching Flutter test coverage', () => {
    const dartParser = fs.readFileSync(
      path.join(repoRoot, 'flutter_app/lib/domain/notes/note_markdown.dart'),
      'utf8'
    );
    const dartPreview = fs.readFileSync(
      path.join(
        repoRoot,
        'flutter_app/lib/ui/widgets/notes/note_markdown_preview.dart'
      ),
      'utf8'
    );
    const dartTest = fs.readFileSync(
      path.join(repoRoot, 'flutter_app/test/stage_n21_note_markdown_test.dart'),
      'utf8'
    );
    const webPreview = fs.readFileSync(
      path.join(repoRoot, 'src/components/notes/NoteMarkdownPreview.tsx'),
      'utf8'
    );

    // Domain purity
    assert.equal(dartParser.includes('package:flutter/'), false);
    assert.equal(dartParser.includes('package:drift/'), false);

    // UI token compliance
    assert.equal(/Color\(0x[0-9A-Fa-f]+\)/.test(dartPreview), false);
    assert.equal(/Colors\.[a-zA-Z0-9_]+/.test(dartPreview), false);
    assert.equal(webPreview.includes('dangerouslySetInnerHTML'), false);
    assert.equal(/#[0-9A-Fa-f]{3,8}\b/.test(webPreview), false);

    // Flutter test reads the shared vectors and tests NoteMarkdownPreview & NotesView
    assert.equal(dartTest.includes('note_markdown_vectors.json'), true);
    assert.equal(dartTest.includes('NoteMarkdownPreview'), true);
    assert.equal(dartTest.includes('NotesView'), true);
  });
});
