import React from 'react';
import { ArrowUpRight, NotebookPen, Pin, Plus } from 'lucide-react';
import { SharedProject } from '../../domain/sharedFoundation';
import { TaskNoteRecord } from '../../domain/taskNotes';
import {
  getNoteContentPreview,
  getNotesForProject,
} from '../../domain/projectNotes';
import {
  CalendarDate,
  EthiopiaClock,
  SharedDateFormatter,
} from '../../domain/date';
import { getDisplayNoteTitle } from '../../domain/webNotesLifecycle';
import {
  DaywellButton,
  DaywellCard,
  DaywellEmptyState,
  DaywellIconButton,
  DaywellStatusBadge,
  DaywellStatusBanner,
} from '../ui';

function formatReadableNoteDate(isoDate: string): string {
  const parsed = SharedDateFormatter.tryParseFlexibleToCalendarDate(isoDate);
  if (!parsed) return isoDate.slice(0, 10);
  const todayEthYear = CalendarDate.fromUtcInstantInEthiopia(
    EthiopiaClock.nowUtc()
  ).year;
  return parsed.year === todayEthYear
    ? `${parsed.gregorianShortMonthName} ${parsed.day}`
    : `${parsed.gregorianShortMonthName} ${parsed.day}, ${parsed.year}`;
}

export interface ProjectNotesSectionProps {
  project: SharedProject;
  notes: readonly TaskNoteRecord[];
  onOpenNote?: (noteId: string) => void;
  onCreateNote: () => void;
  errorMessage?: string | null;
}

export function ProjectNotesSection({
  project,
  notes,
  onOpenNote,
  onCreateNote,
  errorMessage,
}: ProjectNotesSectionProps) {
  const projectNotes = getNotesForProject(notes, project.id, {
    includeArchived: true,
    includeTrashed: false,
  });

  return (
    <DaywellCard radius="xl" padding="md" className="space-y-3">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div className="flex items-center gap-2">
          <NotebookPen className="w-4 h-4 text-[var(--dw-primary)] shrink-0" />
          <div className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
            NOTES ({projectNotes.length})
          </div>
        </div>
        <DaywellButton
          label="New Note"
          variant="tonal"
          size="compact"
          leadingIcon={<Plus className="w-3.5 h-3.5" />}
          onClick={onCreateNote}
        />
      </div>

      {errorMessage && (
        <DaywellStatusBanner tone="error" message={errorMessage} />
      )}

      {projectNotes.length === 0 ? (
        <DaywellEmptyState
          icon={<NotebookPen className="w-7 h-7" />}
          message="No notes for this project yet"
          subtitle="Capture project outlines, meeting notes, or reference checklists linked directly to this project."
          actionLabel="New Note"
          onActionPressed={onCreateNote}
        />
      ) : (
        <div className="space-y-2">
          {projectNotes.map((note) => {
            const displayTitle = getDisplayNoteTitle(note.title);
            const preview = getNoteContentPreview(note.content);
            const dateLabel = formatReadableNoteDate(note.updatedAt);
            const isArchived = Boolean(note.isArchived);
            const isPinned = Boolean(note.isPinned) && !isArchived;

            return (
              <div
                key={note.id}
                onClick={onOpenNote ? () => onOpenNote(note.id) : undefined}
                className={`flex items-start justify-between gap-3 p-3 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] ${
                  onOpenNote
                    ? 'hover:border-[var(--dw-primary)]/40 cursor-pointer transition-colors group'
                    : ''
                }`}
              >
                <div className="min-w-0 flex-1 space-y-1">
                  <div className="flex items-center gap-1.5 flex-wrap">
                    {isPinned && (
                      <Pin className="w-3 h-3 text-[var(--dw-warning)] fill-current shrink-0" />
                    )}
                    {onOpenNote ? (
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          onOpenNote(note.id);
                        }}
                        className="text-xs font-bold text-[var(--dw-text-primary)] group-hover:text-[var(--dw-primary)] text-left truncate max-w-full cursor-pointer"
                      >
                        {displayTitle}
                      </button>
                    ) : (
                      <span className="text-xs font-bold text-[var(--dw-text-primary)] truncate">
                        {displayTitle}
                      </span>
                    )}
                    <DaywellStatusBadge
                      label={note.notebook}
                      tone="neutral"
                      showIcon={false}
                    />
                    {isArchived && (
                      <DaywellStatusBadge
                        label="Archived"
                        tone="warning"
                        showIcon={false}
                      />
                    )}
                  </div>

                  {preview && (
                    <p className="dw-type-body-compact text-[var(--dw-text-secondary)] line-clamp-2">
                      {preview}
                    </p>
                  )}

                  <div className="flex items-center gap-1.5 flex-wrap text-[11px] text-[var(--dw-text-muted)]">
                    <span>Updated {dateLabel}</span>
                    {note.tags.slice(0, 2).map((tag) => (
                      <span
                        key={tag}
                        className="inline-flex items-center px-1.5 py-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] text-[10px] font-semibold"
                      >
                        #{tag}
                      </span>
                    ))}
                    {note.tags.length > 2 && (
                      <span className="text-[10px] font-semibold text-[var(--dw-text-secondary)]">
                        +{note.tags.length - 2}
                      </span>
                    )}
                  </div>
                </div>

                {onOpenNote && (
                  <DaywellIconButton
                    label={`Open note ${displayTitle}`}
                    size="compact"
                    tone="primary"
                    onClick={(e) => {
                      e.stopPropagation();
                      onOpenNote(note.id);
                    }}
                    icon={<ArrowUpRight className="w-3.5 h-3.5" />}
                  />
                )}
              </div>
            );
          })}
        </div>
      )}
    </DaywellCard>
  );
}
