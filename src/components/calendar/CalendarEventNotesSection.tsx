import React, { useMemo, useState } from 'react';
import {
  AlertTriangle,
  ArrowUpRight,
  Link2,
  NotebookPen,
  Pin,
  Plus,
  Unlink,
  X,
} from 'lucide-react';
import {
  CalendarDate,
  EthiopiaClock,
  SharedDateFormatter,
} from '../../domain/date';
import {
  CalendarEventNoteTarget,
  getAvailableNotesToLinkToCalendarEvent,
  getCalendarEventNotePreview,
  getNotesLinkedToCalendarEvent,
} from '../../domain/calendarNotes';
import { TaskNoteRecord } from '../../domain/taskNotes';
import { getDisplayNoteTitle } from '../../domain/webNotesLifecycle';
import {
  DaywellButton,
  DaywellCard,
  DaywellEmptyState,
  DaywellIconButton,
  DaywellSearchField,
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

export interface CalendarEventNotesSectionProps {
  event: CalendarEventNoteTarget;
  notes: readonly TaskNoteRecord[];
  tasks?: readonly { id: string; title: string }[];
  allEvents?: readonly CalendarEventNoteTarget[];
  onOpenNote?: (noteId: string) => void;
  onCreateNote: () => void;
  onLinkExistingNote: (
    noteId: string,
    options?: { allowReassign?: boolean }
  ) => { ok: boolean; error?: string };
  onUnlinkNote: (noteId: string) => void;
  errorMessage?: string | null;
}

export function CalendarEventNotesSection({
  event,
  notes,
  tasks = [],
  allEvents = [],
  onOpenNote,
  onCreateNote,
  onLinkExistingNote,
  onUnlinkNote,
  errorMessage,
}: CalendarEventNotesSectionProps) {
  const [isPickerOpen, setIsPickerOpen] = useState(false);
  const [pickerSearch, setPickerSearch] = useState('');
  const [confirmReassignNoteId, setConfirmReassignNoteId] = useState<string | null>(
    null
  );
  const [localError, setLocalError] = useState<string | null>(null);

  const linkedNotes = useMemo(
    () =>
      getNotesLinkedToCalendarEvent(notes, event.id, {
        includeArchived: true,
        includeTrashed: false,
      }),
    [notes, event.id]
  );

  const availableNotes = useMemo(
    () => getAvailableNotesToLinkToCalendarEvent(notes, event.id, pickerSearch),
    [notes, event.id, pickerSearch]
  );

  const taskTitleById = useMemo(() => {
    const map = new Map<string, string>();
    for (const t of tasks) {
      map.set(t.id, t.title);
    }
    return map;
  }, [tasks]);

  const eventTitleById = useMemo(() => {
    const map = new Map<string, string>();
    for (const ev of allEvents) {
      map.set(ev.id, ev.title);
    }
    return map;
  }, [allEvents]);

  const handleRequestLink = (
    noteId: string,
    hasExistingPrimaryLink: boolean
  ) => {
    setLocalError(null);
    if (hasExistingPrimaryLink) {
      setConfirmReassignNoteId(noteId);
      return;
    }
    const res = onLinkExistingNote(noteId);
    if (!res.ok) {
      setLocalError(res.error || 'Could not link note to event.');
      return;
    }
    setConfirmReassignNoteId(null);
    setPickerSearch('');
    setIsPickerOpen(false);
  };

  const handleConfirmReassign = (noteId: string) => {
    setLocalError(null);
    const res = onLinkExistingNote(noteId, { allowReassign: true });
    if (!res.ok) {
      setLocalError(res.error || 'Could not replace existing note link.');
      return;
    }
    setConfirmReassignNoteId(null);
    setPickerSearch('');
    setIsPickerOpen(false);
  };

  const activeError = errorMessage || localError;

  return (
    <DaywellCard radius="xl" padding="md" className="space-y-3">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div className="flex items-center gap-2">
          <NotebookPen className="w-4 h-4 text-[var(--dw-primary)] shrink-0" />
          <div className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
            LINKED NOTES ({linkedNotes.length})
          </div>
        </div>
        <div className="flex items-center gap-1.5 flex-wrap">
          <DaywellButton
            label={isPickerOpen ? 'Close Picker' : 'Link Existing'}
            variant="outlined"
            size="compact"
            leadingIcon={
              isPickerOpen ? (
                <X className="w-3.5 h-3.5" />
              ) : (
                <Link2 className="w-3.5 h-3.5" />
              )
            }
            onClick={() => {
              setLocalError(null);
              setConfirmReassignNoteId(null);
              setIsPickerOpen((prev) => !prev);
            }}
          />
          <DaywellButton
            label="New Note"
            variant="tonal"
            size="compact"
            leadingIcon={<Plus className="w-3.5 h-3.5" />}
            onClick={onCreateNote}
          />
        </div>
      </div>

      {activeError && <DaywellStatusBanner tone="error" message={activeError} />}

      {isPickerOpen && (
        <div className="p-3 rounded-[var(--dw-radius-lg)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] space-y-2.5">
          <DaywellSearchField
            value={pickerSearch}
            onChange={(val) => {
              setPickerSearch(val);
              setConfirmReassignNoteId(null);
            }}
            placeholder="Search existing notes to link..."
            ariaLabel="Search existing notes to link to event"
          />

          {availableNotes.length === 0 ? (
            <p className="text-xs text-[var(--dw-text-muted)] py-2 text-center">
              {pickerSearch.trim()
                ? 'No matching notes available to link.'
                : 'No other notes available to link.'}
            </p>
          ) : (
            <div className="max-h-48 overflow-y-auto space-y-1.5 pr-0.5">
              {availableNotes.slice(0, 20).map((option) => {
                const { note, hasExistingPrimaryLink } = option;
                const displayTitle = getDisplayNoteTitle(note.title);
                const preview = getCalendarEventNotePreview(note.content, 80);
                const isConfirming = confirmReassignNoteId === note.id;

                const linkedTaskTitle = option.linkedTaskId
                  ? taskTitleById.get(option.linkedTaskId)
                  : undefined;
                const linkedEventTitle = option.linkedEventId
                  ? eventTitleById.get(option.linkedEventId)
                  : undefined;
                const existingLinkSummary = option.linkedTaskId
                  ? linkedTaskTitle
                    ? `Linked to task: ${linkedTaskTitle}`
                    : 'Linked task unavailable'
                  : option.linkedEventId
                    ? linkedEventTitle
                      ? `Linked to event: ${linkedEventTitle}`
                      : 'Linked event unavailable'
                    : option.isLinkedToOtherModule
                      ? `Linked to ${note.linkedModule}`
                      : null;

                return (
                  <div
                    key={note.id}
                    className="p-2.5 rounded-[var(--dw-radius-md)] bg-[var(--dw-card)] border border-[var(--dw-border)] space-y-2"
                  >
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0 flex-1 space-y-0.5">
                        <div className="flex items-center gap-1.5 flex-wrap">
                          <span className="text-xs font-semibold text-[var(--dw-text-primary)] truncate">
                            {displayTitle}
                          </span>
                          <DaywellStatusBadge
                            label={note.notebook}
                            tone="neutral"
                            showIcon={false}
                          />
                          {note.isArchived && (
                            <DaywellStatusBadge
                              label="Archived"
                              tone="warning"
                              showIcon={false}
                            />
                          )}
                        </div>
                        {preview && (
                          <p className="text-[11px] text-[var(--dw-text-secondary)] truncate">
                            {preview}
                          </p>
                        )}
                        {existingLinkSummary && (
                          <p className="text-[11px] font-medium text-[var(--dw-warning)] flex items-center gap-1">
                            <AlertTriangle className="w-3 h-3 shrink-0" />
                            <span className="truncate">{existingLinkSummary}</span>
                          </p>
                        )}
                      </div>

                      {!isConfirming && (
                        <DaywellButton
                          label="Link"
                          variant={hasExistingPrimaryLink ? 'outlined' : 'tonal'}
                          size="compact"
                          onClick={() =>
                            handleRequestLink(note.id, hasExistingPrimaryLink)
                          }
                        />
                      )}
                    </div>

                    {isConfirming && (
                      <div className="flex items-center justify-between gap-2 pt-1.5 border-t border-[var(--dw-divider)]">
                        <span className="text-[11px] text-[var(--dw-text-secondary)]">
                          Replace current link with this event?
                        </span>
                        <div className="flex items-center gap-1.5 shrink-0">
                          <DaywellButton
                            label="Cancel"
                            variant="text"
                            size="compact"
                            onClick={() => setConfirmReassignNoteId(null)}
                          />
                          <DaywellButton
                            label="Replace link"
                            variant="primary"
                            size="compact"
                            onClick={() => handleConfirmReassign(note.id)}
                          />
                        </div>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}

      {linkedNotes.length === 0 ? (
        <DaywellEmptyState
          icon={<NotebookPen className="w-7 h-7" />}
          message="No notes linked to this event yet"
          subtitle="Create meeting prep, agendas, or follow-up notes linked directly to this Calendar event."
          actionLabel="New Note"
          onActionPressed={onCreateNote}
        />
      ) : (
        <div className="space-y-2">
          {linkedNotes.map((note) => {
            const displayTitle = getDisplayNoteTitle(note.title);
            const preview = getCalendarEventNotePreview(note.content);
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

                <div className="flex items-center gap-1 shrink-0">
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
                  <DaywellIconButton
                    label={`Unlink note ${displayTitle}`}
                    size="compact"
                    tone="muted"
                    onClick={(e) => {
                      e.stopPropagation();
                      onUnlinkNote(note.id);
                    }}
                    icon={<Unlink className="w-3.5 h-3.5" />}
                  />
                </div>
              </div>
            );
          })}
        </div>
      )}
    </DaywellCard>
  );
}
