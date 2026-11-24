import React from 'react';
import {
  AlertTriangle,
  CheckSquare,
  FileText,
  Link2Off,
  Square,
} from 'lucide-react';
import {
  inlinesToPlainText,
  NoteMarkdownBlock,
  NoteMarkdownInline,
  parseNoteMarkdown,
} from '../../domain/noteMarkdown';
import {
  NoteLinkCandidateShape,
  resolveNoteInternalLink,
} from '../../domain/noteLinks';

interface NoteMarkdownPreviewProps {
  content: string;
  emptyMessage?: string;
  className?: string;
  onToggleChecklistItem?: (lineIndex: number) => void;
  notes?: readonly NoteLinkCandidateShape[];
  onOpenInternalNote?: (noteId: string) => void;
  onOpenAmbiguousInternalLink?: (
    targetTitle: string,
    matches: readonly NoteLinkCandidateShape[]
  ) => void;
}

interface InlineRenderContext {
  notes: readonly NoteLinkCandidateShape[];
  onOpenInternalNote?: (noteId: string) => void;
  onOpenAmbiguousInternalLink?: (
    targetTitle: string,
    matches: readonly NoteLinkCandidateShape[]
  ) => void;
}

function renderInternalLinkNode(
  targetTitle: string,
  key: string,
  ctx: InlineRenderContext
): React.ReactNode {
  const resolution = resolveNoteInternalLink(targetTitle, ctx.notes);

  if (resolution.status === 'resolved') {
    const displayLabel = resolution.note.title.trim() || targetTitle;
    if (ctx.onOpenInternalNote) {
      return (
        <button
          key={key}
          type="button"
          data-testid="internal-note-link-resolved"
          data-internal-link-status="resolved"
          aria-label={`Open note: ${displayLabel}`}
          title={`Open note: ${displayLabel}`}
          onClick={() => ctx.onOpenInternalNote?.(resolution.note.id)}
          className="inline-flex items-center gap-1 px-1.5 py-0.5 mx-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)]/30 font-medium underline underline-offset-2 hover:opacity-85 cursor-pointer align-baseline max-w-full text-left break-words"
        >
          <FileText className="w-3 h-3 shrink-0" aria-hidden="true" />
          <span className="break-words">{targetTitle}</span>
        </button>
      );
    }
    return (
      <span
        key={key}
        data-testid="internal-note-link-resolved"
        data-internal-link-status="resolved"
        className="inline-flex items-center gap-1 px-1.5 py-0.5 mx-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)]/30 font-medium underline underline-offset-2 align-baseline max-w-full break-words"
      >
        <FileText className="w-3 h-3 shrink-0" aria-hidden="true" />
        <span className="break-words">{targetTitle}</span>
      </span>
    );
  }

  if (resolution.status === 'ambiguous') {
    const countLabel = `${resolution.matches.length}`;
    if (ctx.onOpenAmbiguousInternalLink) {
      return (
        <button
          key={key}
          type="button"
          data-testid="internal-note-link-ambiguous"
          data-internal-link-status="ambiguous"
          aria-label={`Multiple notes match "${targetTitle}" (${countLabel} matches). Choose a note.`}
          title={`Multiple active notes match "${targetTitle}". Click to choose.`}
          onClick={() =>
            ctx.onOpenAmbiguousInternalLink?.(targetTitle, resolution.matches)
          }
          className="inline-flex items-center gap-1 px-1.5 py-0.5 mx-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-warning-container)] text-[var(--dw-on-warning-container)] border border-[var(--dw-warning)]/40 font-medium underline decoration-dotted underline-offset-2 hover:opacity-90 cursor-pointer align-baseline max-w-full text-left break-words"
        >
          <AlertTriangle className="w-3 h-3 shrink-0" aria-hidden="true" />
          <span className="break-words">{targetTitle}</span>
          <span className="text-[10px] font-bold opacity-80 shrink-0">
            ({countLabel})
          </span>
        </button>
      );
    }
    return (
      <span
        key={key}
        data-testid="internal-note-link-ambiguous"
        data-internal-link-status="ambiguous"
        className="inline-flex items-center gap-1 px-1.5 py-0.5 mx-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-warning-container)] text-[var(--dw-on-warning-container)] border border-[var(--dw-warning)]/40 font-medium align-baseline max-w-full break-words"
      >
        <AlertTriangle className="w-3 h-3 shrink-0" aria-hidden="true" />
        <span className="break-words">{targetTitle}</span>
        <span className="text-[10px] font-bold opacity-80 shrink-0">
          ({countLabel})
        </span>
      </span>
    );
  }

  return (
    <span
      key={key}
      data-testid="internal-note-link-missing"
      data-internal-link-status="missing"
      title={`Unresolved note link: "${targetTitle}"`}
      className="inline-flex items-center gap-1 px-1.5 py-0.5 mx-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] text-[var(--dw-text-muted)] border border-dashed border-[var(--dw-border)] underline decoration-dashed underline-offset-2 align-baseline max-w-full break-words"
    >
      <Link2Off className="w-3 h-3 shrink-0" aria-hidden="true" />
      <span className="break-words">{targetTitle}</span>
    </span>
  );
}

function renderInlineNodes(
  nodes: readonly NoteMarkdownInline[],
  keyPrefix: string,
  ctx: InlineRenderContext
): React.ReactNode[] {
  return nodes.map((node, index) => {
    const key = `${keyPrefix}-${index}`;
    switch (node.type) {
      case 'text':
        return <React.Fragment key={key}>{node.text}</React.Fragment>;
      case 'bold':
        return (
          <strong
            key={key}
            className="font-semibold text-[var(--dw-text-primary)]"
          >
            {renderInlineNodes(node.children, `${key}-b`, ctx)}
          </strong>
        );
      case 'italic':
        return (
          <em key={key} className="italic">
            {renderInlineNodes(node.children, `${key}-i`, ctx)}
          </em>
        );
      case 'strikethrough':
        return (
          <del
            key={key}
            className="line-through text-[var(--dw-text-muted)]"
          >
            {renderInlineNodes(node.children, `${key}-s`, ctx)}
          </del>
        );
      case 'code':
        return (
          <code
            key={key}
            className="px-1.5 py-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] dw-type-mono text-[var(--dw-primary)] break-words"
          >
            {node.code}
          </code>
        );
      case 'link':
        return (
          <a
            key={key}
            href={node.url}
            target="_blank"
            rel="noopener noreferrer nofollow"
            className="text-[var(--dw-primary)] underline underline-offset-2 hover:opacity-80 break-words"
          >
            {node.label}
          </a>
        );
      case 'internalLink':
        return renderInternalLinkNode(node.targetTitle, key, ctx);
    }
  });
}

function renderBlock(
  block: NoteMarkdownBlock,
  index: number,
  inlineCtx: InlineRenderContext,
  onToggleChecklistItem?: (lineIndex: number) => void
): React.ReactNode {
  const key = `md-block-${index}`;
  switch (block.type) {
    case 'heading': {
      if (block.level === 1) {
        return (
          <h1
            key={key}
            className="dw-type-display text-[var(--dw-text-primary)] pt-1 break-words"
          >
            {renderInlineNodes(block.inlines, `${key}-h1`, inlineCtx)}
          </h1>
        );
      }
      if (block.level === 2) {
        return (
          <h2
            key={key}
            className="dw-type-heading text-[var(--dw-text-primary)] pt-1 break-words"
          >
            {renderInlineNodes(block.inlines, `${key}-h2`, inlineCtx)}
          </h2>
        );
      }
      return (
        <h3
          key={key}
          className="dw-type-title text-[var(--dw-text-primary)] pt-0.5 break-words"
        >
          {renderInlineNodes(block.inlines, `${key}-h3`, inlineCtx)}
        </h3>
      );
    }

    case 'paragraph':
      return (
        <p
          key={key}
          className="dw-type-body text-[var(--dw-text-primary)] whitespace-pre-wrap break-words leading-relaxed"
        >
          {renderInlineNodes(block.inlines, `${key}-p`, inlineCtx)}
        </p>
      );

    case 'bulletList':
      return (
        <ul
          key={key}
          className="list-disc pl-5 space-y-1.5 dw-type-body text-[var(--dw-text-primary)]"
        >
          {block.items.map((item, itemIdx) => (
            <li key={`${key}-li-${itemIdx}`} className="break-words leading-relaxed">
              {renderInlineNodes(item, `${key}-li-${itemIdx}`, inlineCtx)}
            </li>
          ))}
        </ul>
      );

    case 'orderedList':
      return (
        <ol
          key={key}
          start={block.start}
          className="list-decimal pl-5 space-y-1.5 dw-type-body text-[var(--dw-text-primary)]"
        >
          {block.items.map((item, itemIdx) => (
            <li
              key={`${key}-oli-${itemIdx}`}
              value={item.number}
              className="break-words leading-relaxed"
            >
              {renderInlineNodes(item.inlines, `${key}-oli-${itemIdx}`, inlineCtx)}
            </li>
          ))}
        </ol>
      );

    case 'checklist':
      return (
        <ul key={key} className="space-y-1.5 list-none pl-0">
          {block.items.map((item, itemIdx) => {
            const plainItem = inlinesToPlainText(item.inlines).trim();
            const actionLabel = item.checked
              ? plainItem
                ? `Mark item incomplete: ${plainItem}`
                : 'Mark item incomplete'
              : plainItem
                ? `Mark item complete: ${plainItem}`
                : 'Mark item complete';
            const canToggle =
              typeof onToggleChecklistItem === 'function' && item.lineIndex >= 0;

            return (
              <li
                key={`${key}-chk-${itemIdx}`}
                className="flex items-start gap-2 dw-type-body leading-relaxed"
              >
                {canToggle ? (
                  <label className="relative inline-flex items-center justify-center w-6 h-6 -m-1 mt-[-2px] rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-surface-subtle)] cursor-pointer shrink-0 focus-within:ring-2 focus-within:ring-[var(--dw-primary)]">
                    <input
                      type="checkbox"
                      checked={item.checked}
                      aria-label={actionLabel}
                      onChange={() => onToggleChecklistItem(item.lineIndex)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') {
                          e.preventDefault();
                          onToggleChecklistItem(item.lineIndex);
                        }
                      }}
                      className="sr-only"
                    />
                    <span
                      aria-hidden="true"
                      className={
                        item.checked
                          ? 'text-[var(--dw-primary)]'
                          : 'text-[var(--dw-text-muted)]'
                      }
                    >
                      {item.checked ? (
                        <CheckSquare className="w-4 h-4" />
                      ) : (
                        <Square className="w-4 h-4" />
                      )}
                    </span>
                  </label>
                ) : (
                  <>
                    <span
                      aria-hidden="true"
                      className={`mt-0.5 shrink-0 ${
                        item.checked
                          ? 'text-[var(--dw-primary)]'
                          : 'text-[var(--dw-text-muted)]'
                      }`}
                    >
                      {item.checked ? (
                        <CheckSquare className="w-4 h-4" />
                      ) : (
                        <Square className="w-4 h-4" />
                      )}
                    </span>
                    <span className="sr-only">
                      {item.checked ? 'Completed item: ' : 'Open item: '}
                    </span>
                  </>
                )}
                <span
                  className={`min-w-0 break-words ${
                    item.checked
                      ? 'line-through text-[var(--dw-text-muted)]'
                      : 'text-[var(--dw-text-primary)]'
                  }`}
                >
                  {renderInlineNodes(
                    item.inlines,
                    `${key}-chk-${itemIdx}`,
                    inlineCtx
                  )}
                </span>
              </li>
            );
          })}
        </ul>
      );

    case 'blockquote':
      return (
        <blockquote
          key={key}
          className="border-l-[3px] border-[var(--dw-primary)] bg-[var(--dw-surface-subtle)] px-3 py-2 rounded-r-[var(--dw-radius-sm)] space-y-1"
        >
          {block.lines.map((line, lineIdx) => (
            <p
              key={`${key}-q-${lineIdx}`}
              className="dw-type-body text-[var(--dw-text-secondary)] italic break-words leading-relaxed min-h-[1em]"
            >
              {renderInlineNodes(line, `${key}-q-${lineIdx}`, inlineCtx)}
            </p>
          ))}
        </blockquote>
      );

    case 'codeBlock':
      return (
        <div
          key={key}
          className="rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] bg-[var(--dw-surface-subtle)] overflow-hidden"
        >
          {block.language && (
            <div className="px-3 py-1 border-b border-[var(--dw-divider)] dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
              {block.language}
            </div>
          )}
          <div className="overflow-x-auto">
            <pre className="p-3 m-0 dw-type-mono text-[var(--dw-text-primary)] whitespace-pre leading-relaxed">
              <code>{block.code}</code>
            </pre>
          </div>
        </div>
      );

    case 'horizontalRule':
      return (
        <hr
          key={key}
          className="border-0 border-t border-[var(--dw-divider)] my-2"
        />
      );
  }
}

export function NoteMarkdownPreview({
  content,
  emptyMessage = 'Nothing to preview yet. Switch to Write to add note content.',
  className = '',
  onToggleChecklistItem,
  notes = [],
  onOpenInternalNote,
  onOpenAmbiguousInternalLink,
}: NoteMarkdownPreviewProps) {
  const doc = React.useMemo(() => parseNoteMarkdown(content), [content]);
  const inlineCtx = React.useMemo<InlineRenderContext>(
    () => ({
      notes,
      onOpenInternalNote,
      onOpenAmbiguousInternalLink,
    }),
    [notes, onOpenInternalNote, onOpenAmbiguousInternalLink]
  );

  if (doc.blocks.length === 0) {
    return (
      <div
        data-testid="note-markdown-preview-empty"
        className={`py-8 px-4 text-center rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] ${className}`}
      >
        <p className="dw-type-body-compact text-[var(--dw-text-muted)]">
          {emptyMessage}
        </p>
      </div>
    );
  }

  return (
    <div
      data-testid="note-markdown-preview"
      className={`space-y-3 min-w-0 select-text ${className}`}
    >
      {doc.blocks.map((block, index) =>
        renderBlock(block, index, inlineCtx, onToggleChecklistItem)
      )}
    </div>
  );
}
