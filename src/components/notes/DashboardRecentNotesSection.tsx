import React from 'react';
import { ArrowUpRight, NotebookPen, Pin } from 'lucide-react';
import {
  buildDashboardRecentNotesSummary,
  DEFAULT_DASHBOARD_RECENT_NOTES_LIMIT,
  formatReadableNoteDate,
  getNoteContentPreview,
  normalizeWebNoteNotebook,
} from '../../domain/noteHelpers';
import { TaskNoteRecord } from '../../domain/taskNotes';
import { getDisplayNoteTitle } from '../../domain/webNotesLifecycle';
import {
  DaywellButton,
  DaywellCard,
  DaywellEmptyState,
  DaywellSectionHeader,
  DaywellStatusBadge,
} from '../ui';

export interface DashboardRecentNotesSectionProps {
  notes: readonly TaskNoteRecord[];
  onOpenNote: (noteId: string) => void;
  onOpenAllNotes: () => void;
  limit?: number;
}

export function DashboardRecentNotesSection({
  notes,
  onOpenNote,
  onOpenAllNotes,
  limit = DEFAULT_DASHBOARD_RECENT_NOTES_LIMIT,
}: DashboardRecentNotesSectionProps) {
  const { recentNotes, totalActiveCount, archivedCount } =
    buildDashboardRecentNotesSummary(notes, {
      limit,
      includeArchived: false,
    });
  const remainingCount = Math.max(0, totalActiveCount - recentNotes.length);

  return (
    <div className="space-y-2 pt-1">
      <DaywellSectionHeader
        title="Recent Notes"
        count={totalActiveCount > 0 ? totalActiveCount : undefined}
        actionLabel="All Notes"
        onActionPressed={onOpenAllNotes}
      />

      {recentNotes.length === 0 ? (
        <DaywellCard padding="md" radius="lg">
          <DaywellEmptyState
            icon={<NotebookPen className="w-7 h-7" />}
            message="No active notes yet"
            subtitle={
              archivedCount > 0
                ? 'All recorded notes are archived. Open Notes to view your Archive.'
                : 'Capture ideas, references, and reflections in Notes.'
            }
            actionLabel="Open Notes"
            onActionPressed={onOpenAllNotes}
            className="py-4"
          />
        </DaywellCard>
      ) : (
        <DaywellCard padding="compact" radius="lg" className="space-y-2">
          <div className="space-y-1.5">
            {recentNotes.map((note) => {
              const displayTitle = getDisplayNoteTitle(note.title);
              const preview = getNoteContentPreview(note.content, 120);
              const updatedLabel = formatReadableNoteDate(note.updatedAt);
              const folderLabel = normalizeWebNoteNotebook(note.notebook);

              return (
                <button
                  key={note.id}
                  type="button"
                  onClick={() => onOpenNote(note.id)}
                  className="w-full text-left flex items-start justify-between gap-2.5 p-2.5 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] hover:border-[var(--dw-primary)]/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--dw-primary)] transition-colors cursor-pointer group"
                >
                  <div className="min-w-0 flex-1 space-y-1">
                    <div className="flex flex-wrap items-center gap-1.5">
                      {note.isPinned && (
                        <Pin
                          className="w-3.5 h-3.5 text-[var(--dw-warning)] shrink-0"
                          aria-label="Pinned note"
                        />
                      )}
                      <span className="text-xs font-bold text-[var(--dw-text-primary)] truncate max-w-full">
                        {displayTitle}
                      </span>
                      <DaywellStatusBadge
                        label={folderLabel}
                        tone="info"
                        showIcon={false}
                      />
                    </div>
                    {preview.length > 0 && (
                      <p className="text-[11px] leading-relaxed text-[var(--dw-text-secondary)] line-clamp-2">
                        {preview}
                      </p>
                    )}
                    <p className="text-[11px] text-[var(--dw-text-muted)]">
                      Updated {updatedLabel}
                    </p>
                  </div>
                  <ArrowUpRight
                    className="w-4 h-4 text-[var(--dw-text-muted)] group-hover:text-[var(--dw-primary)] shrink-0 mt-0.5 transition-colors"
                    aria-hidden="true"
                  />
                </button>
              );
            })}
          </div>

          {remainingCount > 0 && (
            <DaywellButton
              label={`+ ${remainingCount} more ${remainingCount === 1 ? 'note' : 'notes'}`}
              variant="text"
              size="compact"
              onClick={onOpenAllNotes}
            />
          )}
        </DaywellCard>
      )}
    </div>
  );
}
