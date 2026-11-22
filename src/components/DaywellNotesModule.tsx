import React, { useState, useEffect, useMemo, useRef } from 'react';
import {
  NotebookPen,
  Plus,
  Search,
  Pin,
  Archive,
  Trash2,
  X,
  Folder,
  ArrowUpRight,
  Check,
  Bold,
  Italic,
  List,
  CheckSquare,
  Code,
  Quote,
  RotateCcw,
  AlertCircle,
  Link2,
  Unlink,
} from 'lucide-react';
import { EthiopiaClock, SharedDateFormatter } from '../domain/date';
import { DaywellTaskRecord } from '../domain/taskOperations';
import {
  getLinkedTaskForNote,
  linkNoteToTask,
  MAX_NOTE_TITLE_LENGTH,
  unlinkNoteFromTask,
} from '../domain/taskNotes';
import { notesService } from '../services/notesService';
import { SharedStateBridge } from '../services/sharedStateBridge';
import {
  DaywellButton,
  DaywellCard,
  DaywellConfirmationDialog,
  DaywellEmptyState,
  DaywellIconButton,
  DaywellSearchField,
  DaywellStatusBadge,
} from './ui';

export interface DaywellNote {
  id: string;
  title: string;
  content: string;
  notebook: string; // Folder/collection
  tags: string[];
  isPinned: boolean;
  isArchived: boolean;
  isFavorite?: boolean;
  isTrashed?: boolean;
  projectId?: string;
  goalId?: string;
  linkedModule?: 'tasks' | 'finance' | 'calendar';
  linkedId?: string;
  createdAt: string; // ISO 8601 UTC
  updatedAt: string;
}

interface DaywellNotesModuleProps {
  notes?: DaywellNote[];
  onUpdateNotes?: (
    updater: DaywellNote[] | ((prev: DaywellNote[]) => DaywellNote[])
  ) => void;
  tasks?: DaywellTaskRecord[];
  requestedNoteFocus?: {
    noteId: string;
    nonce: number;
  } | null;
  onNavigateToTask?: (taskId: string) => void;
  onRequestQuickCapture?: () => void;
  onNavigateToModule?: (module: string) => void;
}

export const DEFAULT_SAMPLE_NOTES: DaywellNote[] = [
  {
    id: 'note-1',
    title: 'Portfolio Case Study Story Arc & Trade-Offs',
    content: `## Portfolio Storytelling Arc\nLead with the problem, not the final polished screens. Detail the onboarding friction identified in user testing.\n\n### Key Trade-Offs:\n- **Simplicity vs Power**: Kept the 3-step setup minimal, hiding advanced ledger options in collapsible cards.\n- **Amharic Typography**: Tuned Noto Sans Ethiopic font metrics for mobile readability.\n\n> "Good design solves real friction without calling attention to itself."`,
    notebook: 'Work',
    tags: ['portfolio', 'design', 'ux'],
    isPinned: true,
    isArchived: false,
    createdAt: new Date(EthiopiaClock.nowUtc().getTime() - 86400000 * 2).toISOString(),
    updatedAt: EthiopiaClock.nowUtc().toISOString(),
  },
  {
    id: 'note-2',
    title: 'የዓመት ዕቅድና የሕይወት ግቦች (Life Vision 2017 ዓ.ም)',
    content: `## የ2017 ዓ.ም ዋና ዋና ግቦች\n\n1. **ጤና (Health First)**: በየቀኑ 20 ደቂቃ የእግር ጉዞ እና በቂ ውሃ መጠጣት\n2. **የፋይናንስ ነፃነት (Financial Peace)**:\n   - የብድር ክፍያዎችን በወቅቱ ማጠናቀቅ\n   - በየወሩ ከገቢ 20% የድንገተኛ አደጋ ቁጠባ (CBE Savings)\n3. **ሙያዊ ክህሎት**: የሞባይልና የዳታቤዝ አርክቴክቸር ማሳደግ`,
    notebook: 'Reflections',
    tags: ['vision', 'goals', 'ethiopian_calendar'],
    isPinned: true,
    isArchived: false,
    createdAt: new Date(EthiopiaClock.nowUtc().getTime() - 86400000 * 5).toISOString(),
    updatedAt: EthiopiaClock.nowUtc().toISOString(),
  },
  {
    id: 'note-3',
    title: 'Personal Finance Standard Operating Procedure',
    content: `### Double-Entry Accounting Invariant:\n- Debits always equal Credits.\n- Safe Harbor Available-to-Spend strictly locks out money lent to others until collected.\n- Review bank balances every Sunday evening.`,
    notebook: 'Finances',
    tags: ['finance', 'rules', 'etb'],
    isPinned: false,
    isArchived: false,
    createdAt: new Date(EthiopiaClock.nowUtc().getTime() - 86400000 * 7).toISOString(),
    updatedAt: EthiopiaClock.nowUtc().toISOString(),
  },
];

export function DaywellNotesModule({
  notes: controlledNotes,
  onUpdateNotes,
  tasks: controlledTasks,
  requestedNoteFocus,
  onNavigateToTask,
}: DaywellNotesModuleProps) {
  const [internalNotes, setInternalNotes] = useState<DaywellNote[]>(() =>
    notesService.loadNotes()
  );

  useEffect(() => {
    if (typeof window === 'undefined' || controlledNotes !== undefined) return;
    const handleSync = () => {
      setInternalNotes(notesService.loadNotes());
    };
    window.addEventListener(SharedStateBridge.SYNC_EVENT_NAME, handleSync);
    return () => window.removeEventListener(SharedStateBridge.SYNC_EVENT_NAME, handleSync);
  }, [controlledNotes]);

  const notes = controlledNotes ?? internalNotes;
  const notesRef = useRef<DaywellNote[]>(notes);
  notesRef.current = notes;

  const effectiveTasks = controlledTasks ?? [];
  const selectableTasks = useMemo(
    () =>
      effectiveTasks.filter(
        (t) => !t.isArchived && t.status !== 'cancelled'
      ),
    [effectiveTasks]
  );

  const applyNotesUpdate = (
    updater: DaywellNote[] | ((prev: DaywellNote[]) => DaywellNote[])
  ) => {
    if (onUpdateNotes) {
      onUpdateNotes(updater);
    } else {
      setInternalNotes((prev) => {
        const nextRaw = typeof updater === 'function' ? updater(prev) : updater;
        return notesService.saveNotes(nextRaw, { emitSync: true });
      });
    }
  };

  const [activeTab, setActiveTab] = useState<string>('all');
  const [searchQuery, setSearchQuery] = useState('');

  const [selectedNoteId, setSelectedNoteId] = useState<string | null>(null);
  const [isEditorOpen, setIsEditorOpen] = useState(false);

  const [editTitle, setEditTitle] = useState('');
  const [editContent, setEditContent] = useState('');
  const [editNotebook, setEditNotebook] = useState('Personal');
  const [editTags, setEditTags] = useState<string[]>([]);
  const [tagInput, setTagInput] = useState('');
  const [saveStatus, setSaveStatus] = useState<'saved' | 'saving'>('saved');

  const [feedbackToast, setFeedbackToast] = useState<{ message: string; undoAction?: () => void; isError?: boolean } | null>(null);
  const feedbackTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const triggerFeedback = (message: string, undoAction?: () => void, isError?: boolean) => {
    if (feedbackTimerRef.current) clearTimeout(feedbackTimerRef.current);
    setFeedbackToast({ message, undoAction, isError });
    feedbackTimerRef.current = setTimeout(() => {
      setFeedbackToast(null);
    }, 4500);
  };

  const [confirmDeleteNote, setConfirmDeleteNote] = useState<DaywellNote | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);

  const notebooks = useMemo(() => {
    const set = new Set<string>(['Personal', 'Work', 'Reflections', 'Finances']);
    notes.forEach((n) => set.add(n.notebook));
    return Array.from(set);
  }, [notes]);

  const filteredNotes = useMemo(() => {
    let list = [...notes];

    if (activeTab === 'pinned') {
      list = list.filter((n) => n.isPinned && !n.isArchived);
    } else if (activeTab === 'archived') {
      list = list.filter((n) => n.isArchived);
    } else if (activeTab === 'all') {
      list = list.filter((n) => !n.isArchived);
    } else {
      list = list.filter((n) => n.notebook === activeTab && !n.isArchived);
    }

    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      list = list.filter(
        (n) =>
          n.title.toLowerCase().includes(q) ||
          n.content.toLowerCase().includes(q) ||
          n.tags.some((t) => t.toLowerCase().includes(q))
      );
    }

    list.sort((a, b) => {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.updatedAt.localeCompare(a.updatedAt);
    });

    return list;
  }, [notes, activeTab, searchQuery]);

  const currentEditorNote = useMemo(
    () =>
      selectedNoteId
        ? notes.find((n) => n.id === selectedNoteId) ?? null
        : null,
    [notes, selectedNoteId]
  );

  const openEditor = (note: DaywellNote) => {
    setSelectedNoteId(note.id);
    setEditTitle(note.title);
    setEditContent(note.content);
    setEditNotebook(note.notebook);
    setEditTags([...note.tags]);
    setSaveStatus('saved');
    setIsEditorOpen(true);
  };

  const handleCreateNote = () => {
    const existingIds = new Set(notesRef.current.map((n) => n.id));
    let nextId = `note-${Date.now()}`;
    while (existingIds.has(nextId)) {
      nextId = `${nextId}-2`;
    }
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const newNote: DaywellNote = {
      id: nextId,
      title: 'Untitled Note',
      content: '',
      notebook: activeTab !== 'all' && activeTab !== 'pinned' && activeTab !== 'archived' ? activeTab : 'Personal',
      tags: [],
      isPinned: false,
      isArchived: false,
      createdAt: nowIso,
      updatedAt: nowIso,
    };

    const prev = [...notesRef.current];
    applyNotesUpdate([newNote, ...notesRef.current]);
    openEditor(newNote);
    triggerFeedback('Note created', () => {
      applyNotesUpdate(prev);
      setIsEditorOpen(false);
    });
  };

  const autosaveTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const commitEditorDraftToNote = (noteId: string) => {
    const target = notesRef.current.find((n) => n.id === noteId);
    if (!target) return;
    const nextTitle = (editTitle.trim() || 'Untitled Note').slice(
      0,
      MAX_NOTE_TITLE_LENGTH
    );
    const hasFieldChanges =
      nextTitle !== target.title ||
      editContent !== target.content ||
      editNotebook !== target.notebook ||
      JSON.stringify(editTags) !== JSON.stringify(target.tags);
    if (!hasFieldChanges) {
      setSaveStatus('saved');
      return;
    }
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    applyNotesUpdate((prevNotes) =>
      prevNotes.map((n) =>
        n.id === noteId
          ? {
              ...n,
              title: nextTitle,
              content: editContent,
              notebook: editNotebook,
              tags: editTags,
              updatedAt: nowIso,
            }
          : n
      )
    );
    setSaveStatus('saved');
  };

  useEffect(() => {
    if (!selectedNoteId || !isEditorOpen) return;
    const target = notesRef.current.find((n) => n.id === selectedNoteId);
    if (!target) return;
    const nextTitle = (editTitle.trim() || 'Untitled Note').slice(
      0,
      MAX_NOTE_TITLE_LENGTH
    );
    const hasFieldChanges =
      nextTitle !== target.title ||
      editContent !== target.content ||
      editNotebook !== target.notebook ||
      JSON.stringify(editTags) !== JSON.stringify(target.tags);
    if (!hasFieldChanges) {
      setSaveStatus('saved');
      return;
    }

    setSaveStatus('saving');
    if (autosaveTimeoutRef.current) clearTimeout(autosaveTimeoutRef.current);

    autosaveTimeoutRef.current = setTimeout(() => {
      commitEditorDraftToNote(selectedNoteId);
    }, 600);

    return () => {
      if (autosaveTimeoutRef.current) clearTimeout(autosaveTimeoutRef.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [editTitle, editContent, editNotebook, editTags, selectedNoteId, isEditorOpen]);

  const flushAutosaveAndClose = () => {
    if (selectedNoteId) {
      if (autosaveTimeoutRef.current) clearTimeout(autosaveTimeoutRef.current);
      commitEditorDraftToNote(selectedNoteId);
    }
    setIsEditorOpen(false);
  };

  useEffect(() => {
    if (!requestedNoteFocus?.noteId) return;
    const target = notesRef.current.find((n) => n.id === requestedNoteFocus.noteId);
    if (!target) return;
    if (isEditorOpen && selectedNoteId && selectedNoteId !== target.id) {
      if (autosaveTimeoutRef.current) clearTimeout(autosaveTimeoutRef.current);
      commitEditorDraftToNote(selectedNoteId);
    }
    setSearchQuery('');
    setActiveTab(target.isArchived ? 'archived' : 'all');
    openEditor(target);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [requestedNoteFocus?.nonce]);

  const togglePin = (noteId: string, e?: React.MouseEvent) => {
    e?.stopPropagation();
    const target = notesRef.current.find((n) => n.id === noteId);
    if (!target) return;
    const nextPinned = !target.isPinned;
    const prev = [...notesRef.current];
    applyNotesUpdate((prevNotes) =>
      prevNotes.map((n) => (n.id === noteId ? { ...n, isPinned: nextPinned, updatedAt: EthiopiaClock.nowUtc().toISOString() } : n))
    );
    triggerFeedback(nextPinned ? 'Note pinned' : 'Note unpinned', () => applyNotesUpdate(prev));
  };

  const toggleArchive = (noteId: string, e?: React.MouseEvent) => {
    e?.stopPropagation();
    const target = notesRef.current.find((n) => n.id === noteId);
    if (!target) return;
    const nextArchived = !target.isArchived;
    const prev = [...notesRef.current];

    applyNotesUpdate((prevNotes) =>
      prevNotes.map((n) => (n.id === noteId ? { ...n, isArchived: nextArchived, updatedAt: EthiopiaClock.nowUtc().toISOString() } : n))
    );

    triggerFeedback(nextArchived ? 'Note moved to archive' : 'Note restored from archive', () => {
      applyNotesUpdate(prev);
    });

    if (isEditorOpen && selectedNoteId === noteId) {
      setIsEditorOpen(false);
    }
  };

  const handleLinkTaskToNote = (noteId: string, taskId: string) => {
    const cleanTaskId = taskId.trim();
    if (!cleanTaskId) return;
    if (isEditorOpen && selectedNoteId === noteId) {
      if (autosaveTimeoutRef.current) clearTimeout(autosaveTimeoutRef.current);
      commitEditorDraftToNote(noteId);
    }
    const prev = [...notesRef.current];
    const targetTask = effectiveTasks.find((t) => t.id === cleanTaskId);
    applyNotesUpdate((prevNotes) => {
      const res = linkNoteToTask(prevNotes, noteId, cleanTaskId);
      return res.ok ? res.notes : prevNotes;
    });
    triggerFeedback(
      targetTask ? `Linked note to "${targetTask.title}"` : 'Linked note to task',
      () => applyNotesUpdate(prev)
    );
  };

  const handleUnlinkTaskFromNote = (noteId: string) => {
    if (isEditorOpen && selectedNoteId === noteId) {
      if (autosaveTimeoutRef.current) clearTimeout(autosaveTimeoutRef.current);
      commitEditorDraftToNote(noteId);
    }
    const prev = [...notesRef.current];
    applyNotesUpdate((prevNotes) => {
      const res = unlinkNoteFromTask(prevNotes, noteId);
      return res.ok ? res.notes : prevNotes;
    });
    triggerFeedback('Unlinked task from note', () => applyNotesUpdate(prev));
  };

  const handleRequestDeleteNote = (noteId: string, e?: React.MouseEvent) => {
    e?.stopPropagation();
    const target = notesRef.current.find((n) => n.id === noteId);
    if (target) {
      setConfirmDeleteNote(target);
    }
  };

  const handleConfirmDeleteNote = () => {
    if (!confirmDeleteNote || isDeleting) return;
    setIsDeleting(true);
    const target = confirmDeleteNote;
    const prev = [...notesRef.current];
    applyNotesUpdate((prevNotes) => prevNotes.filter((n) => n.id !== target.id));
    if (isEditorOpen && selectedNoteId === target.id) {
      setIsEditorOpen(false);
    }
    setConfirmDeleteNote(null);
    setIsDeleting(false);
    triggerFeedback(`Deleted "${target.title || 'note'}"`, () => applyNotesUpdate(prev));
  };

  const insertFormatting = (prefix: string, suffix: string = '') => {
    const textarea = document.getElementById('note-content-editor') as HTMLTextAreaElement | null;
    if (!textarea) return;

    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const selected = textarea.value.substring(start, end) || 'text';
    const replacement = `${prefix}${selected}${suffix}`;

    const newContent = textarea.value.substring(0, start) + replacement + textarea.value.substring(end);
    setEditContent(newContent);

    setTimeout(() => {
      textarea.focus();
      textarea.setSelectionRange(start + prefix.length, start + prefix.length + selected.length);
    }, 50);
  };

  const handleAddTag = () => {
    if (!tagInput.trim()) return;
    const clean = tagInput.trim().replace(/^#/, '');
    if (!editTags.includes(clean)) {
      setEditTags([...editTags, clean]);
    }
    setTagInput('');
  };

  const handleRemoveTag = (tag: string) => {
    setEditTags(editTags.filter((t) => t !== tag));
  };

  return (
    <div className="space-y-4">
      {/* Action Feedback & Undo Toast */}
      {feedbackToast && (
        <div
          role="status"
          aria-live="polite"
          className="fixed bottom-20 left-4 right-4 max-w-sm mx-auto z-50 flex items-center justify-between gap-3 p-3 bg-[var(--dw-elevated)] text-[var(--dw-text-primary)] rounded-[var(--dw-radius-lg)] shadow-xl text-xs font-semibold border border-[var(--dw-border)]"
        >
          <div className="flex items-center gap-2 min-w-0">
            {feedbackToast.isError ? (
              <AlertCircle className="w-4 h-4 text-[var(--dw-error)] shrink-0" />
            ) : (
              <Check className="w-4 h-4 text-[var(--dw-success)] shrink-0" />
            )}
            <span className="truncate">{feedbackToast.message}</span>
          </div>
          <div className="flex items-center gap-1.5 shrink-0">
            {feedbackToast.undoAction && (
              <DaywellButton
                label="Undo"
                variant="tonal"
                size="compact"
                onClick={() => {
                  feedbackToast.undoAction?.();
                  setFeedbackToast(null);
                }}
              />
            )}
            <DaywellIconButton
              label="Dismiss notice"
              size="compact"
              tone="muted"
              onClick={() => setFeedbackToast(null)}
              icon={<X className="w-3.5 h-3.5" />}
            />
          </div>
        </div>
      )}

      {/* Main List View (when editor not full screen) */}
      {!isEditorOpen ? (
        <div className="space-y-4">
          {/* Header */}
          <div className="flex items-start justify-between pt-1">
            <div>
              <div className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
                A HOME FOR YOUR THINKING
              </div>
              <h1 className="dw-type-display text-[var(--dw-text-primary)]">
                Notes & knowledge
              </h1>
            </div>
            <DaywellIconButton
              label="New Note"
              tone="primary"
              onClick={handleCreateNote}
              icon={<Plus className="w-5 h-5 stroke-[2.5]" />}
              className="bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] hover:opacity-90"
            />
          </div>

          {/* Search */}
          <DaywellSearchField
            value={searchQuery}
            onChange={setSearchQuery}
            placeholder="Search notes, collections, or tags..."
            ariaLabel="Search notes, collections, or tags"
          />

          {/* Notebook Filter Pills */}
          <div className="flex items-center gap-1.5 overflow-x-auto pb-0.5" role="tablist" aria-label="Note collections">
            <button
              type="button"
              role="tab"
              aria-selected={activeTab === 'all'}
              onClick={() => setActiveTab('all')}
              className={`min-h-[36px] text-xs px-3.5 py-1.5 rounded-[var(--dw-radius-full)] font-semibold transition-all shrink-0 cursor-pointer ${
                activeTab === 'all'
                  ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)] font-bold'
                  : 'bg-[var(--dw-card)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)]'
              }`}
            >
              All Notes ({notes.filter((n) => !n.isArchived).length})
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={activeTab === 'pinned'}
              onClick={() => setActiveTab('pinned')}
              className={`min-h-[36px] text-xs px-3.5 py-1.5 rounded-[var(--dw-radius-full)] font-semibold transition-all shrink-0 flex items-center gap-1 cursor-pointer ${
                activeTab === 'pinned'
                  ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)] font-bold'
                  : 'bg-[var(--dw-card)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)]'
              }`}
            >
              <Pin className="w-3 h-3" />
              Pinned
            </button>
            {notebooks.map((nb) => (
              <button
                key={nb}
                type="button"
                role="tab"
                aria-selected={activeTab === nb}
                onClick={() => setActiveTab(nb)}
                className={`min-h-[36px] text-xs px-3.5 py-1.5 rounded-[var(--dw-radius-full)] font-semibold transition-all shrink-0 cursor-pointer ${
                  activeTab === nb
                    ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)] font-bold'
                    : 'bg-[var(--dw-card)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)]'
                }`}
              >
                {nb}
              </button>
            ))}
            <button
              type="button"
              role="tab"
              aria-selected={activeTab === 'archived'}
              onClick={() => setActiveTab('archived')}
              className={`min-h-[36px] text-xs px-3.5 py-1.5 rounded-[var(--dw-radius-full)] font-semibold transition-all shrink-0 flex items-center gap-1 cursor-pointer ${
                activeTab === 'archived'
                  ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)] font-bold'
                  : 'bg-[var(--dw-card)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)]'
              }`}
            >
              <Archive className="w-3 h-3" />
              Archived
            </button>
          </div>

          {/* Notes List */}
          <div className="space-y-3 pt-1">
            {filteredNotes.length === 0 ? (
              searchQuery ? (
                <DaywellEmptyState
                  icon={<Search className="w-8 h-8" />}
                  message={`No notes matching "${searchQuery}"`}
                  subtitle="Check your search term or search within a specific notebook."
                  actionLabel="Clear Search"
                  onActionPressed={() => setSearchQuery('')}
                />
              ) : activeTab === 'pinned' ? (
                <DaywellEmptyState
                  icon={<Pin className="w-8 h-8" />}
                  message="No pinned notes"
                  subtitle="Pin important notes to keep them anchored at the top of your workspace."
                  actionLabel="View All Notes"
                  onActionPressed={() => setActiveTab('all')}
                />
              ) : activeTab === 'archived' ? (
                <DaywellEmptyState
                  icon={<Archive className="w-8 h-8" />}
                  message="Archive is empty"
                  subtitle="Archived notes are stored here safely when you no longer need them on your main board."
                  actionLabel="View All Notes"
                  onActionPressed={() => setActiveTab('all')}
                />
              ) : (
                <DaywellEmptyState
                  icon={<NotebookPen className="w-8 h-8" />}
                  message={activeTab === 'all' ? 'No notes yet' : `No notes in "${activeTab}"`}
                  subtitle="Capture thoughts, meeting outlines, drafts, or reflections with offline autosave."
                  actionLabel="Create Note"
                  onActionPressed={handleCreateNote}
                />
              )
            ) : (
              filteredNotes.map((note) => (
                <DaywellCard
                  key={note.id}
                  radius="lg"
                  padding="md"
                  onClick={() => openEditor(note)}
                  className="hover:border-[var(--dw-primary)]/40 space-y-2 group"
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-center gap-2 min-w-0">
                      {note.isPinned && (
                        <Pin className="w-3.5 h-3.5 text-[var(--dw-warning)] fill-current shrink-0" />
                      )}
                      <h4 className="text-sm font-bold text-[var(--dw-text-primary)] group-hover:text-[var(--dw-primary)] transition-colors line-clamp-1">
                        {note.title}
                      </h4>
                    </div>
                    <div className="flex items-center gap-1 shrink-0">
                      <DaywellIconButton
                        label={note.isPinned ? 'Unpin note' : 'Pin note to top'}
                        size="compact"
                        tone={note.isPinned ? 'primary' : 'muted'}
                        onClick={(e) => togglePin(note.id, e)}
                        icon={<Pin className="w-3.5 h-3.5" />}
                      />
                      <ArrowUpRight className="w-4 h-4 text-[var(--dw-text-muted)] group-hover:text-[var(--dw-primary)]" />
                    </div>
                  </div>

                  {note.content && (
                    <p className="dw-type-body-compact text-[var(--dw-text-secondary)] line-clamp-2">
                      {note.content.replace(/[#*`>]/g, '')}
                    </p>
                  )}

                  {note.linkedModule === 'tasks' && note.linkedId && (() => {
                    const linkedTask = getLinkedTaskForNote(note, effectiveTasks);
                    if (linkedTask) {
                      return (
                        <div className="flex items-center flex-wrap gap-1.5 pt-0.5">
                          {onNavigateToTask ? (
                            <button
                              type="button"
                              onClick={(e) => {
                                e.stopPropagation();
                                onNavigateToTask(linkedTask.id);
                              }}
                              className="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] hover:opacity-90 cursor-pointer max-w-full"
                              title={`Open linked task: ${linkedTask.title}`}
                            >
                              <CheckSquare className="w-3 h-3 shrink-0" />
                              <span className="truncate">Task: {linkedTask.title}</span>
                              <ArrowUpRight className="w-3 h-3 shrink-0" />
                            </button>
                          ) : (
                            <span className="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-secondary)] max-w-full">
                              <CheckSquare className="w-3 h-3 shrink-0 text-[var(--dw-primary)]" />
                              <span className="truncate">Task: {linkedTask.title}</span>
                            </span>
                          )}
                          {linkedTask.isArchived && (
                            <DaywellStatusBadge label="Archived" tone="neutral" showIcon={false} />
                          )}
                        </div>
                      );
                    }
                    return (
                      <div className="flex items-center gap-1.5 pt-0.5">
                        <span className="inline-flex items-center gap-1 text-[11px] font-medium px-2 py-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-muted)]">
                          <Link2 className="w-3 h-3 shrink-0" />
                          <span>Linked task unavailable</span>
                        </span>
                      </div>
                    );
                  })()}

                  <div className="flex items-center justify-between text-[10px] text-[var(--dw-text-muted)] pt-1.5 border-t border-[var(--dw-divider)]">
                    <div className="flex items-center gap-2">
                      <DaywellStatusBadge label={note.notebook} tone="neutral" showIcon={false} />
                      {note.tags.length > 0 && (
                        <span>
                          #{note.tags.slice(0, 2).join(' #')}
                        </span>
                      )}
                    </div>
                    <span>
                      {(() => {
                        const d = SharedDateFormatter.tryParseFlexibleToCalendarDate(note.updatedAt);
                        return d ? `${d.gregorianShortMonthName} ${d.day}` : note.updatedAt.slice(0, 10);
                      })()}
                    </span>
                  </div>
                </DaywellCard>
              ))
            )}
          </div>
        </div>
      ) : (
        /* FULL-SCREEN LIVE EDITOR */
        <DaywellCard radius="xl" padding="lg" className="space-y-4">
          {/* Editor Top Navigation */}
          <div className="flex items-center justify-between border-b border-[var(--dw-divider)] pb-3">
            <div className="flex items-center gap-2">
              <DaywellButton
                label="Done"
                variant="tonal"
                size="compact"
                onClick={flushAutosaveAndClose}
                leadingIcon={<Check className="w-3.5 h-3.5 stroke-[2.5]" />}
              />
              {currentEditorNote?.isArchived && (
                <DaywellStatusBadge label="Archived" tone="neutral" showIcon={false} />
              )}
            </div>

            <div className="flex items-center gap-1.5">
              <span className="dw-type-caption text-[var(--dw-text-muted)] flex items-center gap-1 font-medium mr-1">
                {saveStatus === 'saving' ? (
                  <>
                    <RotateCcw className="w-3 h-3 animate-spin text-[var(--dw-warning)]" />
                    <span>Autosaving...</span>
                  </>
                ) : (
                  <>
                    <Check className="w-3 h-3 text-[var(--dw-success)]" />
                    <span>Saved offline</span>
                  </>
                )}
              </span>

              {selectedNoteId && (
                <>
                  <DaywellIconButton
                    label="Toggle Pin"
                    size="compact"
                    tone="muted"
                    onClick={() => togglePin(selectedNoteId)}
                    icon={<Pin className="w-4 h-4" />}
                  />
                  <DaywellIconButton
                    label={currentEditorNote?.isArchived ? 'Restore Note' : 'Archive Note'}
                    size="compact"
                    tone="muted"
                    onClick={() => toggleArchive(selectedNoteId)}
                    icon={<Archive className="w-4 h-4" />}
                  />
                  <DaywellIconButton
                    label="Delete Note"
                    size="compact"
                    tone="danger"
                    onClick={() => handleRequestDeleteNote(selectedNoteId)}
                    icon={<Trash2 className="w-4 h-4" />}
                  />
                </>
              )}
            </div>
          </div>

          {/* Folder & Tags Bar */}
          <div className="flex items-center gap-2 flex-wrap text-xs">
            <div className="flex items-center gap-1.5 bg-[var(--dw-surface-subtle)] px-2.5 py-1.5 rounded-[var(--dw-radius-md)] border border-[var(--dw-border)]">
              <Folder className="w-3.5 h-3.5 text-[var(--dw-text-muted)]" />
              <select
                aria-label="Note collection"
                value={editNotebook}
                onChange={(e) => setEditNotebook(e.target.value)}
                className="bg-transparent text-xs font-semibold text-[var(--dw-text-primary)] outline-none"
              >
                {notebooks.map((nb) => (
                  <option key={nb} value={nb}>
                    {nb}
                  </option>
                ))}
              </select>
            </div>

            {editTags.map((t) => (
              <span
                key={t}
                className="inline-flex items-center gap-1 bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] px-2 py-0.5 rounded-[var(--dw-radius-sm)] text-[11px] font-semibold"
              >
                #{t}
                <button
                  type="button"
                  aria-label={`Remove tag ${t}`}
                  onClick={() => handleRemoveTag(t)}
                  className="hover:text-[var(--dw-error)] cursor-pointer"
                >
                  <X className="w-3 h-3" />
                </button>
              </span>
            ))}

            <input
              type="text"
              placeholder="+ tag"
              aria-label="Add tag"
              value={tagInput}
              onChange={(e) => setTagInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault();
                  handleAddTag();
                }
              }}
              className="w-20 px-2 py-1 text-[11px] bg-transparent border-b border-[var(--dw-border)] outline-none text-[var(--dw-text-secondary)] focus:border-[var(--dw-primary)]"
            />
          </div>

          {/* Linked Task Bar */}
          {currentEditorNote && (
            currentEditorNote.linkedModule === 'tasks' && currentEditorNote.linkedId ? (() => {
              const linkedTask = getLinkedTaskForNote(currentEditorNote, effectiveTasks);
              return (
                <div className="flex flex-wrap items-center justify-between gap-2 px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)]">
                  <div className="flex items-center gap-2 min-w-0">
                    <CheckSquare className="w-4 h-4 text-[var(--dw-primary)] shrink-0" />
                    <div className="min-w-0">
                      <div className="text-[10px] font-bold uppercase tracking-wider text-[var(--dw-text-muted)]">
                        Linked Task
                      </div>
                      <div className="flex items-center gap-1.5 flex-wrap">
                        <span className="text-xs font-semibold text-[var(--dw-text-primary)] truncate">
                          {linkedTask ? linkedTask.title : 'Linked task unavailable'}
                        </span>
                        {linkedTask?.isArchived && (
                          <DaywellStatusBadge label="Archived" tone="neutral" showIcon={false} />
                        )}
                        {linkedTask && (linkedTask.completed || linkedTask.status === 'completed') && (
                          <DaywellStatusBadge label="Done" tone="success" showIcon={false} />
                        )}
                      </div>
                    </div>
                  </div>
                  <div className="flex items-center gap-1.5 shrink-0">
                    {linkedTask && onNavigateToTask && (
                      <DaywellButton
                        label="Open Task"
                        variant="tonal"
                        size="compact"
                        trailingIcon={<ArrowUpRight className="w-3.5 h-3.5" />}
                        onClick={() => {
                          if (selectedNoteId) {
                            if (autosaveTimeoutRef.current) clearTimeout(autosaveTimeoutRef.current);
                            commitEditorDraftToNote(selectedNoteId);
                          }
                          onNavigateToTask(linkedTask.id);
                        }}
                      />
                    )}
                    <DaywellButton
                      label="Unlink"
                      variant="outlined"
                      size="compact"
                      leadingIcon={<Unlink className="w-3 h-3" />}
                      onClick={() => handleUnlinkTaskFromNote(currentEditorNote.id)}
                    />
                  </div>
                </div>
              );
            })() : selectableTasks.length > 0 ? (
              <div className="flex items-center justify-between gap-2 px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs">
                <div className="flex items-center gap-1.5 text-[var(--dw-text-secondary)] font-medium">
                  <Link2 className="w-3.5 h-3.5 text-[var(--dw-text-muted)] shrink-0" />
                  <span>Task link</span>
                </div>
                <select
                  aria-label="Link note to task"
                  value=""
                  onChange={(e) => {
                    if (e.target.value) {
                      handleLinkTaskToNote(currentEditorNote.id, e.target.value);
                    }
                  }}
                  className="bg-transparent text-xs font-semibold text-[var(--dw-text-primary)] outline-none max-w-[230px] cursor-pointer"
                >
                  <option value="">Link to a task...</option>
                  {selectableTasks.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.title}
                    </option>
                  ))}
                </select>
              </div>
            ) : null
          )}

          {/* Formatting Toolbar */}
          <div className="flex items-center gap-1 p-1 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] overflow-x-auto">
            <button
              type="button"
              onClick={() => insertFormatting('## ', '')}
              className="min-w-[34px] min-h-[34px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-xs font-bold text-[var(--dw-text-secondary)] cursor-pointer"
              title="Heading"
            >
              H2
            </button>
            <button
              type="button"
              onClick={() => insertFormatting('**', '**')}
              className="min-w-[34px] min-h-[34px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-[var(--dw-text-secondary)] cursor-pointer inline-flex items-center justify-center"
              title="Bold"
            >
              <Bold className="w-3.5 h-3.5" />
            </button>
            <button
              type="button"
              onClick={() => insertFormatting('*', '*')}
              className="min-w-[34px] min-h-[34px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-[var(--dw-text-secondary)] cursor-pointer inline-flex items-center justify-center"
              title="Italic"
            >
              <Italic className="w-3.5 h-3.5" />
            </button>
            <button
              type="button"
              onClick={() => insertFormatting('- ', '')}
              className="min-w-[34px] min-h-[34px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-[var(--dw-text-secondary)] cursor-pointer inline-flex items-center justify-center"
              title="Bullet List"
            >
              <List className="w-3.5 h-3.5" />
            </button>
            <button
              type="button"
              onClick={() => insertFormatting('- [ ] ', '')}
              className="min-w-[34px] min-h-[34px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-[var(--dw-text-secondary)] cursor-pointer inline-flex items-center justify-center"
              title="Checklist"
            >
              <CheckSquare className="w-3.5 h-3.5" />
            </button>
            <button
              type="button"
              onClick={() => insertFormatting('> ', '')}
              className="min-w-[34px] min-h-[34px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-[var(--dw-text-secondary)] cursor-pointer inline-flex items-center justify-center"
              title="Quote"
            >
              <Quote className="w-3.5 h-3.5" />
            </button>
            <button
              type="button"
              onClick={() => insertFormatting('`', '`')}
              className="min-w-[34px] min-h-[34px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-[var(--dw-text-secondary)] cursor-pointer inline-flex items-center justify-center"
              title="Inline Code"
            >
              <Code className="w-3.5 h-3.5" />
            </button>
          </div>

          {/* Title Input */}
          <input
            type="text"
            value={editTitle}
            onChange={(e) => setEditTitle(e.target.value)}
            placeholder="Note Title"
            className="w-full dw-type-heading bg-transparent border-none outline-none text-[var(--dw-text-primary)] placeholder:text-[var(--dw-text-muted)]"
          />

          {/* Content Textarea */}
          <textarea
            id="note-content-editor"
            value={editContent}
            onChange={(e) => setEditContent(e.target.value)}
            placeholder="Type your notes here... (Supports Markdown syntax, checklists, and Ethiopian Ge'ez script)"
            rows={14}
            className="w-full bg-transparent border-none outline-none text-xs text-[var(--dw-text-primary)] placeholder:text-[var(--dw-text-muted)] font-sans leading-relaxed resize-none"
          />
        </DaywellCard>
      )}

      {/* Destructive Action Confirmation Modal */}
      <DaywellConfirmationDialog
        isOpen={Boolean(confirmDeleteNote)}
        title="Delete Note?"
        description={
          confirmDeleteNote
            ? `Are you sure you want to delete "${confirmDeleteNote.title}"? You can also undo this action right after.`
            : ''
        }
        cancelLabel="Cancel"
        confirmLabel={isDeleting ? 'Deleting...' : 'Delete Note'}
        destructive
        onCancel={() => setConfirmDeleteNote(null)}
        onConfirm={handleConfirmDeleteNote}
      />
    </div>
  );
}
