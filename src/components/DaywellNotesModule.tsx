import React, { useState, useEffect, useLayoutEffect, useMemo, useRef } from 'react';
import {
  NotebookPen,
  Plus,
  Search,
  Pin,
  Star,
  Archive,
  Trash2,
  X,
  Folder,
  ArrowUpRight,
  Check,
  Bold,
  Italic,
  Strikethrough,
  List,
  ListOrdered,
  CheckSquare,
  Square,
  Code,
  SquareCode,
  Quote,
  RotateCcw,
  AlertCircle,
  Link2,
  Link2Off,
  FileText,
  Unlink,
  Eye,
  Pencil,
  FolderPlus,
  LayoutGrid,
  Layers,
  Tag,
  Calendar as CalendarIcon,
} from 'lucide-react';
import { CalendarDate, EthiopiaClock, SharedDateFormatter } from '../domain/date';
import {
  getNoteMarkdownChecklistAtSelection,
  markdownToPlainText,
  toggleNoteMarkdownChecklistAtLine,
} from '../domain/noteMarkdown';
import {
  applyNoteSmartBackspace,
  applyNoteSmartEnter,
  applyNoteToolbarFormat,
  NoteToolbarFormatAction,
} from '../domain/noteEditorFormatting';
import {
  collectUniqueNoteTags,
  isNoteActive,
  isNoteArchived,
  isNoteTrashed,
  matchesNoteSearchQuery,
  normalizeFolderComparisonKey,
  normalizeNoteTags,
  noteMatchesDateFilter,
  noteMatchesTagFilter,
  NoteDateFilterMode,
  NoteSortMode,
  parseNoteDateFilterMode,
  resolveReusableNoteTag,
} from '../domain/noteHelpers';
import {
  findNoteBacklinks,
  NoteLinkCandidateShape,
} from '../domain/noteLinks';
import { DaywellTaskRecord } from '../domain/taskOperations';
import {
  getLinkedTaskForNote,
  linkNoteToTask,
  MAX_NOTE_TITLE_LENGTH,
  unlinkNoteFromTask,
} from '../domain/taskNotes';
import {
  createWebCustomFolder,
  deleteWebNotebook,
  emptyWebNotesTrash,
  filterAndSortWebNotes,
  getAvailableWebNotebooks,
  getDisplayNoteTitle,
  getWebNoteCounts,
  isDefaultWebNotebook,
  isNoteDraftBlank,
  moveWebNoteToNotebook,
  moveWebNoteToTrash,
  permanentlyDeleteWebNote,
  renameWebNotebook,
  resolveDefaultNotebookForTab,
  restoreWebNoteFromTrash,
  saveWebNoteDraft,
  toggleWebNoteArchive,
  toggleWebNoteFavorite,
  toggleWebNotePin,
} from '../domain/webNotesLifecycle';
import {
  buildProjectTitlesById,
  clearNoteProject,
  getProjectForNote,
  normalizeNoteProjectId,
  setNoteProject,
} from '../domain/projectNotes';
import {
  buildCalendarEventTitlesById,
  CalendarEventNoteTarget,
  getLinkedCalendarEventForNote,
  linkNoteToCalendarEvent,
  unlinkNoteFromCalendarEvent,
} from '../domain/calendarNotes';
import { notesService } from '../services/notesService';
import { projectsService } from '../services/projectsService';
import { SHARED_DESIGN_TOKENS, SharedProject } from '../domain/sharedFoundation';
import { SharedStateBridge } from '../services/sharedStateBridge';
import {
  DaywellButton,
  DaywellCard,
  DaywellConfirmationDialog,
  DaywellEmptyState,
  DaywellIconButton,
  DaywellSearchField,
  DaywellStatusBadge,
  DaywellStatusBanner,
  DaywellTextField,
} from './ui';
import { NoteMarkdownPreview } from './notes/NoteMarkdownPreview';

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
  projects?: SharedProject[];
  calendarEvents?: CalendarEventNoteTarget[];
  requestedNoteFocus?: {
    noteId: string;
    nonce: number;
  } | null;
  layoutMode?: 'auto' | 'compact';
  isActive?: boolean;
  onNavigateToTask?: (taskId: string) => void;
  onNavigateToCalendarEvent?: (event: CalendarEventNoteTarget) => void;
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
  projects: controlledProjects,
  calendarEvents: controlledCalendarEvents,
  requestedNoteFocus,
  layoutMode = 'auto',
  isActive = true,
  onNavigateToTask,
  onNavigateToCalendarEvent,
}: DaywellNotesModuleProps) {
  const moduleContainerRef = useRef<HTMLDivElement | null>(null);
  const [containerWidth, setContainerWidth] = useState<number>(() =>
    typeof window !== 'undefined' ? window.innerWidth : 0
  );

  useEffect(() => {
    if (layoutMode === 'compact') {
      return;
    }
    const element = moduleContainerRef.current;
    const measure = () => {
      if (!element) {
        if (typeof window !== 'undefined') {
          setContainerWidth(window.innerWidth);
        }
        return;
      }
      const nextWidth = Math.round(
        element.getBoundingClientRect().width || element.clientWidth || 0
      );
      if (nextWidth > 0) {
        setContainerWidth((prev) => (prev === nextWidth ? prev : nextWidth));
      }
    };

    measure();

    let resizeObserver: ResizeObserver | null = null;
    if (element && typeof ResizeObserver !== 'undefined') {
      resizeObserver = new ResizeObserver(() => measure());
      resizeObserver.observe(element);
    }

    if (typeof window !== 'undefined') {
      window.addEventListener('resize', measure);
    }

    return () => {
      resizeObserver?.disconnect();
      if (typeof window !== 'undefined') {
        window.removeEventListener('resize', measure);
      }
    };
  }, [layoutMode]);

  const isWideMasterDetail =
    layoutMode !== 'compact' &&
    containerWidth >= SHARED_DESIGN_TOKENS.breakpoints.expanded;

  const [internalNotes, setInternalNotes] = useState<DaywellNote[]>(() =>
    notesService.loadNotes()
  );
  const [customFolders, setCustomFolders] = useState<string[]>(() =>
    notesService.loadCustomFolders()
  );

  useEffect(() => {
    if (typeof window === 'undefined' || controlledNotes !== undefined) return;
    const handleSync = () => {
      setInternalNotes(notesService.loadNotes());
      setCustomFolders(notesService.loadCustomFolders());
    };
    window.addEventListener(SharedStateBridge.SYNC_EVENT_NAME, handleSync);
    return () => window.removeEventListener(SharedStateBridge.SYNC_EVENT_NAME, handleSync);
  }, [controlledNotes]);

  const notes = controlledNotes ?? internalNotes;
  const notesRef = useRef<DaywellNote[]>(notes);
  notesRef.current = notes;

  const [internalProjects, setInternalProjects] = useState<SharedProject[]>(() =>
    projectsService.listProjects({ includeArchived: true })
  );

  useEffect(() => {
    if (typeof window === 'undefined' || controlledProjects !== undefined) return;
    const handleProjectSync = () => {
      setInternalProjects(projectsService.listProjects({ includeArchived: true }));
    };
    window.addEventListener(SharedStateBridge.SYNC_EVENT_NAME, handleProjectSync);
    return () =>
      window.removeEventListener(
        SharedStateBridge.SYNC_EVENT_NAME,
        handleProjectSync
      );
  }, [controlledProjects]);

  const effectiveTasks = controlledTasks ?? [];
  const selectableTasks = useMemo(
    () =>
      effectiveTasks.filter(
        (t) => !t.isArchived && t.status !== 'cancelled'
      ),
    [effectiveTasks]
  );

  const effectiveProjects = controlledProjects ?? internalProjects;
  const selectableProjects = useMemo(
    () => effectiveProjects.filter((p) => !p.isArchived),
    [effectiveProjects]
  );
  const projectTitlesById = useMemo(
    () => buildProjectTitlesById(effectiveProjects),
    [effectiveProjects]
  );

  const [internalCalendarEvents, setInternalCalendarEvents] = useState<
    CalendarEventNoteTarget[]
  >(() => {
    try {
      const saved = localStorage.getItem('daywell_calendar_events');
      if (saved) {
        const parsed = JSON.parse(saved);
        if (Array.isArray(parsed)) return parsed;
      }
    } catch {
      // ignore
    }
    return [];
  });

  useEffect(() => {
    if (
      typeof window === 'undefined' ||
      controlledCalendarEvents !== undefined
    ) {
      return;
    }
    const handleCalendarSync = () => {
      try {
        const saved = localStorage.getItem('daywell_calendar_events');
        if (saved) {
          const parsed = JSON.parse(saved);
          if (Array.isArray(parsed)) {
            setInternalCalendarEvents(parsed);
          }
        }
      } catch {
        // ignore
      }
    };
    window.addEventListener(SharedStateBridge.SYNC_EVENT_NAME, handleCalendarSync);
    return () =>
      window.removeEventListener(
        SharedStateBridge.SYNC_EVENT_NAME,
        handleCalendarSync
      );
  }, [controlledCalendarEvents]);

  const effectiveCalendarEvents =
    controlledCalendarEvents ?? internalCalendarEvents;
  const calendarEventTitlesById = useMemo(
    () => buildCalendarEventTitlesById(effectiveCalendarEvents),
    [effectiveCalendarEvents]
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

  const persistCustomFolders = (nextFolders: readonly string[]): string[] => {
    const saved = notesService.saveCustomFolders(nextFolders);
    setCustomFolders(saved);
    return saved;
  };

  const [activeTab, setActiveTab] = useState<'all' | 'pinned' | 'favorites' | 'archived' | 'trash'>('all');
  const [notebookFilter, setNotebookFilter] = useState<string>('all');
  const [tagFilter, setTagFilter] = useState<string>('all');
  const [dateFilter, setDateFilter] = useState<NoteDateFilterMode>('all');
  const [sortBy, setSortBy] = useState<NoteSortMode>('recent');
  const [viewMode, setViewMode] = useState<'list' | 'grid'>('list');
  const [searchQuery, setSearchQuery] = useState('');

  const [folderDialogState, setFolderDialogState] = useState<{
    mode: 'create' | 'rename';
    sourceName?: string;
    targetContext?: 'list' | 'editor';
  } | null>(null);
  const [folderNameDraft, setFolderNameDraft] = useState('');
  const [folderDialogError, setFolderDialogError] = useState<string | null>(null);
  const [confirmDeleteFolder, setConfirmDeleteFolder] = useState<string | null>(null);

  const [selectedNoteId, setSelectedNoteId] = useState<string | null>(null);
  const selectedNoteIdRef = useRef<string | null>(null);
  const [isEditorOpen, setIsEditorOpen] = useState(false);

  const [editTitle, setEditTitle] = useState('');
  const [editContent, setEditContent] = useState('');
  const [editNotebook, setEditNotebook] = useState('Personal');
  const [editTags, setEditTags] = useState<string[]>([]);
  const [editProjectId, setEditProjectId] = useState<string | undefined>(undefined);
  const [tagInput, setTagInput] = useState('');
  const [saveStatus, setSaveStatus] = useState<'saved' | 'saving'>('saved');
  const [editorMode, setEditorMode] = useState<'write' | 'preview'>('write');

  const contentTextareaRef = useRef<HTMLTextAreaElement | null>(null);
  const lastContentSelectionRef = useRef<{ start: number; end: number }>({
    start: 0,
    end: 0,
  });
  const [contentSelection, setContentSelection] = useState<{
    start: number;
    end: number;
  }>({ start: 0, end: 0 });
  const pendingContentSelectionRef = useRef<{
    start: number;
    end: number;
  } | null>(null);

  const updateTrackedSelection = (start: number, end: number) => {
    lastContentSelectionRef.current = { start, end };
    setContentSelection((prev) =>
      prev.start === start && prev.end === end ? prev : { start, end }
    );
  };

  const activeWriteChecklist = useMemo(
    () =>
      editorMode === 'write'
        ? getNoteMarkdownChecklistAtSelection(
            editContent,
            contentSelection.start,
            contentSelection.end
          )
        : null,
    [editorMode, editContent, contentSelection]
  );

  const draftFieldsRef = useRef<{
    title: string;
    content: string;
    notebook: string;
    tags: string[];
    projectId: string | undefined;
  }>({
    title: editTitle,
    content: editContent,
    notebook: editNotebook,
    tags: editTags,
    projectId: editProjectId,
  });
  draftFieldsRef.current = {
    title: editTitle,
    content: editContent,
    notebook: editNotebook,
    tags: editTags,
    projectId: editProjectId,
  };

  const [feedbackToast, setFeedbackToast] = useState<{
    message: string;
    undoAction?: () => void;
    isError?: boolean;
  } | null>(null);
  const feedbackTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const triggerFeedback = (
    message: string,
    undoAction?: () => void,
    isError?: boolean
  ) => {
    if (feedbackTimerRef.current) clearTimeout(feedbackTimerRef.current);
    setFeedbackToast({ message, undoAction, isError });
    feedbackTimerRef.current = setTimeout(() => {
      setFeedbackToast(null);
    }, 4500);
  };

  const [confirmPermanentDeleteNote, setConfirmPermanentDeleteNote] =
    useState<DaywellNote | null>(null);
  const [isConfirmEmptyTrashOpen, setIsConfirmEmptyTrashOpen] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [ambiguousLinkChoice, setAmbiguousLinkChoice] = useState<{
    targetTitle: string;
    matches: DaywellNote[];
  } | null>(null);

  const noteCounts = useMemo(() => getWebNoteCounts(notes), [notes]);

  const notebooks = useMemo(
    () => getAvailableWebNotebooks(notes, undefined, customFolders),
    [notes, customFolders]
  );

  const availableFilterTags = useMemo(() => {
    const collected = collectUniqueNoteTags(notes, {
      includeArchived: activeTab === 'archived' || activeTab === 'trash',
      includeTrashed: activeTab === 'trash',
    });
    if (
      tagFilter !== 'all' &&
      !collected.some((t) => t.toLowerCase() === tagFilter.toLowerCase())
    ) {
      return [...collected, tagFilter];
    }
    return collected;
  }, [notes, activeTab, tagFilter]);

  const allKnownTags = useMemo(
    () =>
      collectUniqueNoteTags(notes, {
        includeArchived: true,
        includeTrashed: false,
      }),
    [notes]
  );

  const editorNotebooks = useMemo(() => {
    if (
      !editNotebook ||
      notebooks.some(
        (nb) =>
          normalizeFolderComparisonKey(nb) ===
          normalizeFolderComparisonKey(editNotebook)
      )
    ) {
      return notebooks;
    }
    return [...notebooks, editNotebook];
  }, [notebooks, editNotebook]);

  const filteredNotes = useMemo(
    () =>
      filterAndSortWebNotes(notes, {
        activeTab,
        notebookFilter,
        tagFilter,
        dateFilter,
        searchQuery,
        sortBy,
        projectTitlesById,
        calendarEventTitlesById,
      }),
    [
      notes,
      activeTab,
      notebookFilter,
      tagFilter,
      dateFilter,
      searchQuery,
      sortBy,
      projectTitlesById,
      calendarEventTitlesById,
    ]
  );

  const hasActiveFilters =
    searchQuery.trim().length > 0 ||
    activeTab !== 'all' ||
    notebookFilter !== 'all' ||
    tagFilter !== 'all' ||
    dateFilter !== 'all' ||
    sortBy !== 'recent';

  const clearAllFilters = () => {
    setSearchQuery('');
    setActiveTab('all');
    setNotebookFilter('all');
    setTagFilter('all');
    setDateFilter('all');
    setSortBy('recent');
  };

  const currentEditorNote = useMemo(
    () =>
      selectedNoteId
        ? notes.find((n) => n.id === selectedNoteId) ?? null
        : null,
    [notes, selectedNoteId]
  );

  const liveNotesForInternalLinks = useMemo(() => {
    if (!isEditorOpen || !selectedNoteId) return notes;
    return notes.map((n) =>
      n.id === selectedNoteId
        ? {
            ...n,
            title: editTitle,
            content: editContent,
            notebook: editNotebook,
            tags: editTags,
          }
        : n
    );
  }, [notes, isEditorOpen, selectedNoteId, editTitle, editContent, editNotebook, editTags]);

  const currentNoteBacklinks = useMemo(() => {
    if (!isEditorOpen) return [];
    const targetForBacklinks = {
      id: selectedNoteId ?? '__new_draft__',
      title: editTitle,
      isArchived: currentEditorNote?.isArchived ?? false,
      isTrashed: currentEditorNote?.isTrashed ?? false,
    };
    return findNoteBacklinks(targetForBacklinks, liveNotesForInternalLinks);
  }, [
    isEditorOpen,
    selectedNoteId,
    editTitle,
    currentEditorNote?.isArchived,
    currentEditorNote?.isTrashed,
    liveNotesForInternalLinks,
  ]);

  const isCurrentNewDraftBlank =
    selectedNoteId === null &&
    isNoteDraftBlank({
      title: editTitle,
      content: editContent,
      tags: editTags,
    });

  const autosaveTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const clearAutosaveTimer = () => {
    if (autosaveTimeoutRef.current) {
      clearTimeout(autosaveTimeoutRef.current);
      autosaveTimeoutRef.current = null;
    }
  };

  useEffect(() => {
    return () => {
      clearAutosaveTimer();
      if (feedbackTimerRef.current) clearTimeout(feedbackTimerRef.current);
    };
  }, []);

  const openEditor = (
    note: DaywellNote,
    options?: { preserveMode?: boolean; skipFlush?: boolean }
  ) => {
    if (isNoteTrashed(note)) {
      setActiveTab('trash');
      triggerFeedback('Restore note from Trash before editing.');
      return;
    }
    if (isEditorOpen && selectedNoteIdRef.current === note.id) {
      return;
    }
    if (isEditorOpen && !options?.skipFlush) {
      commitEditorDraftToNote();
    }
    const freshNote = notesRef.current.find((n) => n.id === note.id) ?? note;
    if (isNoteTrashed(freshNote)) {
      setActiveTab('trash');
      triggerFeedback('Restore note from Trash before editing.');
      return;
    }
    clearAutosaveTimer();
    setAmbiguousLinkChoice(null);
    selectedNoteIdRef.current = freshNote.id;
    setSelectedNoteId(freshNote.id);
    setEditTitle(freshNote.title);
    setEditContent(freshNote.content);
    setEditNotebook(freshNote.notebook);
    setEditTags([...freshNote.tags]);
    setEditProjectId(normalizeNoteProjectId(freshNote.projectId));
    setTagInput('');
    setSaveStatus('saved');
    if (!options?.preserveMode) {
      setEditorMode('write');
    }
    updateTrackedSelection(freshNote.content.length, freshNote.content.length);
    pendingContentSelectionRef.current = null;
    setIsEditorOpen(true);
  };

  const handleNavigateToInternalNote = (targetNoteId: string) => {
    setAmbiguousLinkChoice(null);
    if (isEditorOpen && selectedNoteIdRef.current === targetNoteId) {
      return;
    }
    if (isEditorOpen) {
      commitEditorDraftToNote();
    }
    const freshTarget = notesRef.current.find((n) => n.id === targetNoteId);
    if (!freshTarget || !isNoteActive(freshTarget)) {
      triggerFeedback('Referenced note is unavailable.', undefined, true);
      return;
    }
    if (activeTab === 'archived' || activeTab === 'trash') {
      setActiveTab('all');
    }
    openEditor(freshTarget, {
      preserveMode: isEditorOpen,
      skipFlush: true,
    });
  };

  const handleOpenAmbiguousInternalLink = (
    targetTitle: string,
    matches: readonly NoteLinkCandidateShape[]
  ) => {
    const resolvedMatches = matches
      .map((m) => notesRef.current.find((n) => n.id === m.id) ?? (m as DaywellNote))
      .filter((n) => isNoteActive(n));
    if (resolvedMatches.length === 1) {
      handleNavigateToInternalNote(resolvedMatches[0].id);
      return;
    }
    if (resolvedMatches.length > 1) {
      setAmbiguousLinkChoice({
        targetTitle,
        matches: resolvedMatches,
      });
    }
  };

  const handleCreateNote = () => {
    if (
      isEditorOpen &&
      selectedNoteIdRef.current === null &&
      isCurrentNewDraftBlank
    ) {
      return;
    }
    if (isEditorOpen) {
      commitEditorDraftToNote();
    }
    clearAutosaveTimer();
    setAmbiguousLinkChoice(null);
    selectedNoteIdRef.current = null;
    setSelectedNoteId(null);
    setEditTitle('');
    setEditContent('');
    setEditNotebook(
      notebookFilter !== 'all'
        ? resolveDefaultNotebookForTab(notebookFilter)
        : resolveDefaultNotebookForTab(activeTab)
    );
    setEditTags([]);
    setEditProjectId(undefined);
    setTagInput('');
    setSaveStatus('saved');
    setEditorMode('write');
    updateTrackedSelection(0, 0);
    pendingContentSelectionRef.current = null;
    setIsEditorOpen(true);
  };

  const commitEditorDraftToNote = (
    overrideTags?: string[]
  ): { noteId: string | null; status: string } => {
    clearAutosaveTimer();
    const fields = draftFieldsRef.current;
    const effectiveTags = overrideTags ?? fields.tags;
    const startingNoteId = selectedNoteIdRef.current;

    const preview = saveWebNoteDraft({
      notes: notesRef.current,
      noteId: startingNoteId,
      title: fields.title,
      content: fields.content,
      notebook: fields.notebook,
      tags: effectiveTags,
      projectId: fields.projectId,
      clearProjectId: fields.projectId === undefined,
    });

    if (preview.status === 'discarded_empty') {
      setSaveStatus('saved');
      return { noteId: null, status: 'discarded_empty' };
    }

    if (preview.status === 'unchanged') {
      setSaveStatus('saved');
      return { noteId: startingNoteId, status: 'unchanged' };
    }

    const assignedId =
      startingNoteId ?? preview.note?.id ?? undefined;
    if (assignedId && startingNoteId === null) {
      selectedNoteIdRef.current = assignedId;
      setSelectedNoteId(assignedId);
    }

    applyNotesUpdate((prevNotes) => {
      const res = saveWebNoteDraft({
        notes: prevNotes,
        noteId: startingNoteId,
        newNoteId: assignedId,
        title: fields.title,
        content: fields.content,
        notebook: fields.notebook,
        tags: effectiveTags,
        projectId: fields.projectId,
        clearProjectId: fields.projectId === undefined,
      });
      return res.notes;
    });

    setSaveStatus('saved');
    return {
      noteId: assignedId ?? startingNoteId,
      status: preview.status,
    };
  };

  useEffect(() => {
    if (!isEditorOpen) return;
    const currentId = selectedNoteIdRef.current;
    if (currentId === null) {
      if (
        isNoteDraftBlank({
          title: editTitle,
          content: editContent,
          tags: editTags,
        })
      ) {
        setSaveStatus('saved');
        return;
      }
    } else {
      const target = notesRef.current.find((n) => n.id === currentId);
      if (!target || isNoteTrashed(target)) return;
      const preview = saveWebNoteDraft({
        notes: notesRef.current,
        noteId: currentId,
        title: editTitle,
        content: editContent,
        notebook: editNotebook,
        tags: editTags,
        projectId: editProjectId,
        clearProjectId: editProjectId === undefined,
      });
      if (preview.status === 'unchanged') {
        setSaveStatus('saved');
        return;
      }
    }

    setSaveStatus('saving');
    clearAutosaveTimer();

    autosaveTimeoutRef.current = setTimeout(() => {
      commitEditorDraftToNote();
    }, 600);

    return () => {
      clearAutosaveTimer();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [editTitle, editContent, editNotebook, editTags, editProjectId, selectedNoteId, isEditorOpen]);

  const flushAutosaveAndClose = () => {
    commitEditorDraftToNote();
    selectedNoteIdRef.current = null;
    setSelectedNoteId(null);
    setEditProjectId(undefined);
    setIsEditorOpen(false);
  };

  const prevIsActiveRef = useRef<boolean>(isActive);
  useEffect(() => {
    const wasActive = prevIsActiveRef.current;
    prevIsActiveRef.current = isActive;
    if (wasActive && !isActive && isEditorOpen) {
      commitEditorDraftToNote();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isActive]);

  useEffect(() => {
    if (!requestedNoteFocus?.noteId) return;
    const target = notesRef.current.find((n) => n.id === requestedNoteFocus.noteId);
    if (!target) {
      triggerFeedback('This note is no longer available.', undefined, true);
      return;
    }
    if (isEditorOpen && selectedNoteIdRef.current !== target.id) {
      commitEditorDraftToNote();
    }
    if (isNoteTrashed(target)) {
      clearAutosaveTimer();
      selectedNoteIdRef.current = null;
      setSelectedNoteId(null);
      setIsEditorOpen(false);
      setActiveTab('trash');
      triggerFeedback('This note is in Trash. Restore it to edit.');
      return;
    }
    const targetArchived = isNoteArchived(target);
    if (targetArchived) {
      setActiveTab('archived');
    } else if (
      activeTab === 'archived' ||
      activeTab === 'trash' ||
      (activeTab === 'pinned' && !target.isPinned) ||
      (activeTab === 'favorites' && !Boolean(target.isFavorite))
    ) {
      setActiveTab('all');
    }
    if (
      notebookFilter !== 'all' &&
      normalizeFolderComparisonKey(target.notebook) !==
        normalizeFolderComparisonKey(notebookFilter)
    ) {
      setNotebookFilter('all');
    }
    if (!noteMatchesTagFilter(target.tags, tagFilter)) {
      setTagFilter('all');
    }
    if (!noteMatchesDateFilter(target, parseNoteDateFilterMode(dateFilter))) {
      setDateFilter('all');
    }
    if (
      searchQuery.trim() &&
      !matchesNoteSearchQuery(target, searchQuery, {
        projectTitle: target.projectId
          ? projectTitlesById.get(target.projectId)
          : undefined,
        linkedEventTitle:
          target.linkedModule === 'calendar' && target.linkedId
            ? calendarEventTitlesById.get(target.linkedId)
            : undefined,
      })
    ) {
      setSearchQuery('');
    }
    openEditor(target, { skipFlush: true });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [requestedNoteFocus?.nonce]);

  const applyEditorAwareMutation = (
    noteId: string | null,
    mutator: (
      notesList: DaywellNote[],
      targetId: string
    ) => { ok: boolean; notes: DaywellNote[]; updatedNote?: DaywellNote; error?: string },
    onSuccess: (updatedNote?: DaywellNote) => void
  ) => {
    const isEditingTarget =
      isEditorOpen &&
      (noteId === null || selectedNoteIdRef.current === noteId);
    if (isEditingTarget) {
      clearAutosaveTimer();
    }

    const prevSnapshot = [...notesRef.current];
    const fields = draftFieldsRef.current;
    const startingEditorNoteId = selectedNoteIdRef.current;

    let previewNotes = prevSnapshot;
    let targetId = noteId ?? startingEditorNoteId;
    let assignedDraftId: string | undefined;

    if (isEditingTarget) {
      const draftPreview = saveWebNoteDraft({
        notes: prevSnapshot,
        noteId: startingEditorNoteId,
        title: fields.title,
        content: fields.content,
        notebook: fields.notebook,
        tags: fields.tags,
        projectId: fields.projectId,
        clearProjectId: fields.projectId === undefined,
      });
      if (draftPreview.status === 'discarded_empty') {
        return prevSnapshot;
      }
      previewNotes = draftPreview.notes;
      if (draftPreview.note) {
        targetId = draftPreview.note.id;
        if (startingEditorNoteId === null) {
          assignedDraftId = draftPreview.note.id;
        }
      }
    }

    if (!targetId) return prevSnapshot;
    const previewRes = mutator(previewNotes, targetId);
    if (!previewRes.ok) {
      triggerFeedback(previewRes.error || 'Could not update note.', undefined, true);
      return prevSnapshot;
    }

    if (assignedDraftId) {
      selectedNoteIdRef.current = assignedDraftId;
      setSelectedNoteId(assignedDraftId);
    }

    applyNotesUpdate((prevNotes) => {
      let workingNotes = prevNotes;
      let resolvedId = noteId ?? startingEditorNoteId;

      if (isEditingTarget) {
        const draftRes = saveWebNoteDraft({
          notes: prevNotes,
          noteId: startingEditorNoteId,
          newNoteId: assignedDraftId,
          title: fields.title,
          content: fields.content,
          notebook: fields.notebook,
          tags: fields.tags,
          projectId: fields.projectId,
          clearProjectId: fields.projectId === undefined,
        });
        if (draftRes.status === 'discarded_empty') {
          return prevNotes;
        }
        workingNotes = draftRes.notes;
        if (draftRes.note) {
          resolvedId = draftRes.note.id;
        }
      }

      if (!resolvedId) return prevNotes;
      const res = mutator(workingNotes, resolvedId);
      return res.ok ? res.notes : workingNotes;
    });

    setSaveStatus('saved');
    onSuccess(previewRes.updatedNote);
    return prevSnapshot;
  };

  const togglePin = (noteId: string | null, e?: React.MouseEvent) => {
    e?.stopPropagation();
    const prevSnapshot = [...notesRef.current];
    applyEditorAwareMutation(
      noteId,
      (list, id) => toggleWebNotePin(list, id),
      (updated) => {
        if (!updated) return;
        triggerFeedback(
          updated.isPinned ? 'Note pinned' : 'Note unpinned',
          () => applyNotesUpdate(prevSnapshot)
        );
      }
    );
  };

  const toggleFavorite = (noteId: string | null, e?: React.MouseEvent) => {
    e?.stopPropagation();
    const prevSnapshot = [...notesRef.current];
    applyEditorAwareMutation(
      noteId,
      (list, id) => toggleWebNoteFavorite(list, id),
      (updated) => {
        if (!updated) return;
        triggerFeedback(
          updated.isFavorite ? 'Added to favorites' : 'Removed from favorites',
          () => applyNotesUpdate(prevSnapshot)
        );
      }
    );
  };

  const toggleArchive = (noteId: string | null, e?: React.MouseEvent) => {
    e?.stopPropagation();
    const prevSnapshot = [...notesRef.current];
    const shouldCloseEditor =
      isEditorOpen && (noteId === null || selectedNoteIdRef.current === noteId);
    applyEditorAwareMutation(
      noteId,
      (list, id) => toggleWebNoteArchive(list, id),
      (updated) => {
        if (!updated) return;
        if (shouldCloseEditor) {
          selectedNoteIdRef.current = null;
          setSelectedNoteId(null);
          setIsEditorOpen(false);
        }
        triggerFeedback(
          updated.isArchived
            ? 'Note moved to archive'
            : 'Note restored from archive',
          () => applyNotesUpdate(prevSnapshot)
        );
      }
    );
  };

  const handleMoveToTrash = (noteId: string | null, e?: React.MouseEvent) => {
    e?.stopPropagation();
    const prevSnapshot = [...notesRef.current];
    const shouldCloseEditor =
      isEditorOpen && (noteId === null || selectedNoteIdRef.current === noteId);
    applyEditorAwareMutation(
      noteId,
      (list, id) => moveWebNoteToTrash(list, id),
      (updated) => {
        if (!updated) return;
        if (shouldCloseEditor) {
          selectedNoteIdRef.current = null;
          setSelectedNoteId(null);
          setIsEditorOpen(false);
        }
        triggerFeedback(
          `Moved "${getDisplayNoteTitle(updated.title)}" to Trash`,
          () => applyNotesUpdate(prevSnapshot)
        );
      }
    );
  };

  const handleRestoreFromTrash = (noteId: string, e?: React.MouseEvent) => {
    e?.stopPropagation();
    const prevSnapshot = [...notesRef.current];
    const target = notesRef.current.find((n) => n.id === noteId);
    if (!target || !isNoteTrashed(target)) return;
    applyNotesUpdate((prevNotes) => {
      const res = restoreWebNoteFromTrash(prevNotes, noteId);
      return res.ok ? res.notes : prevNotes;
    });
    triggerFeedback(
      `Restored "${getDisplayNoteTitle(target.title)}" to ${
        target.isArchived ? 'Archive' : 'Notes'
      }`,
      () => applyNotesUpdate(prevSnapshot)
    );
  };

  const handleRequestPermanentDelete = (
    noteId: string,
    e?: React.MouseEvent
  ) => {
    e?.stopPropagation();
    const target = notesRef.current.find((n) => n.id === noteId);
    if (target && isNoteTrashed(target)) {
      setConfirmPermanentDeleteNote(target);
    }
  };

  const handleConfirmPermanentDeleteNote = () => {
    if (!confirmPermanentDeleteNote || isDeleting) return;
    setIsDeleting(true);
    const target = confirmPermanentDeleteNote;
    if (selectedNoteIdRef.current === target.id) {
      clearAutosaveTimer();
      selectedNoteIdRef.current = null;
      setSelectedNoteId(null);
      setIsEditorOpen(false);
    }
    applyNotesUpdate((prevNotes) => {
      const res = permanentlyDeleteWebNote(prevNotes, target.id);
      return res.ok ? res.notes : prevNotes;
    });
    setConfirmPermanentDeleteNote(null);
    setIsDeleting(false);
    triggerFeedback(
      `Permanently deleted "${getDisplayNoteTitle(target.title)}"`
    );
  };

  const handleConfirmEmptyTrash = () => {
    if (isDeleting) return;
    setIsDeleting(true);
    const { deletedCount } = emptyWebNotesTrash(notesRef.current);
    if (selectedNoteIdRef.current) {
      const activeSelected = notesRef.current.find(
        (n) => n.id === selectedNoteIdRef.current
      );
      if (!activeSelected || isNoteTrashed(activeSelected)) {
        clearAutosaveTimer();
        selectedNoteIdRef.current = null;
        setSelectedNoteId(null);
        setIsEditorOpen(false);
      }
    }
    applyNotesUpdate((prevNotes) => emptyWebNotesTrash(prevNotes).notes);
    setIsConfirmEmptyTrashOpen(false);
    setIsDeleting(false);
    if (deletedCount > 0) {
      triggerFeedback(
        `Emptied ${deletedCount} ${deletedCount === 1 ? 'note' : 'notes'} from Trash`
      );
    }
  };

  const handleLinkTaskToNote = (noteId: string | null, taskId: string) => {
    const cleanTaskId = taskId.trim();
    if (!cleanTaskId) return;
    const prevSnapshot = [...notesRef.current];
    const targetTask = effectiveTasks.find((t) => t.id === cleanTaskId);
    applyEditorAwareMutation(
      noteId,
      (list, id) => linkNoteToTask(list, id, cleanTaskId),
      () => {
        triggerFeedback(
          targetTask
            ? `Linked note to "${targetTask.title}"`
            : 'Linked note to task',
          () => applyNotesUpdate(prevSnapshot)
        );
      }
    );
  };

  const handleUnlinkTaskFromNote = (noteId: string) => {
    const prevSnapshot = [...notesRef.current];
    applyEditorAwareMutation(
      noteId,
      (list, id) => unlinkNoteFromTask(list, id),
      () => {
        triggerFeedback('Unlinked task from note', () =>
          applyNotesUpdate(prevSnapshot)
        );
      }
    );
  };

  const handleLinkCalendarEventToNote = (
    noteId: string | null,
    eventId: string
  ) => {
    const cleanEventId = eventId.trim();
    if (!cleanEventId) return;
    const prevSnapshot = [...notesRef.current];
    const targetEvent = effectiveCalendarEvents.find(
      (ev) => ev.id === cleanEventId
    );
    applyEditorAwareMutation(
      noteId,
      (list, id) => linkNoteToCalendarEvent(list, id, cleanEventId),
      () => {
        triggerFeedback(
          targetEvent
            ? `Linked note to "${targetEvent.title}"`
            : 'Linked note to event',
          () => applyNotesUpdate(prevSnapshot)
        );
      }
    );
  };

  const handleUnlinkCalendarEventFromNote = (noteId: string) => {
    const prevSnapshot = [...notesRef.current];
    applyEditorAwareMutation(
      noteId,
      (list, id) => unlinkNoteFromCalendarEvent(list, id),
      () => {
        triggerFeedback('Unlinked event from note', () =>
          applyNotesUpdate(prevSnapshot)
        );
      }
    );
  };

  const handleChangeNoteProject = (
    noteId: string | null,
    rawProjectId: string
  ) => {
    const nextProjectId = normalizeNoteProjectId(rawProjectId);
    const prevProjectId = draftFieldsRef.current.projectId;
    if (nextProjectId === prevProjectId) return;

    setEditProjectId(nextProjectId);
    draftFieldsRef.current.projectId = nextProjectId;

    if (noteId === null && isCurrentNewDraftBlank) {
      return;
    }

    const prevSnapshot = [...notesRef.current];
    const targetProject = nextProjectId
      ? effectiveProjects.find((p) => p.id === nextProjectId) ?? null
      : null;

    applyEditorAwareMutation(
      noteId,
      (list, id) =>
        nextProjectId
          ? setNoteProject(list, id, nextProjectId)
          : clearNoteProject(list, id),
      () => {
        triggerFeedback(
          nextProjectId
            ? targetProject
              ? `Associated with "${targetProject.title}"`
              : 'Associated note with project'
            : 'Removed project from note',
          () => {
            applyNotesUpdate(prevSnapshot);
            if (selectedNoteIdRef.current === noteId) {
              setEditProjectId(prevProjectId);
              draftFieldsRef.current.projectId = prevProjectId;
            }
          }
        );
      }
    );
  };

  useLayoutEffect(() => {
    const pending = pendingContentSelectionRef.current;
    if (!pending || editorMode !== 'write') return;
    pendingContentSelectionRef.current = null;
    const textarea = contentTextareaRef.current;
    if (!textarea) return;
    const maxLen = textarea.value.length;
    const start = Math.max(0, Math.min(maxLen, pending.start));
    const end = Math.max(0, Math.min(maxLen, pending.end));
    textarea.setSelectionRange(start, end);
  }, [editContent, editorMode]);

  const syncTextareaSelection = (textarea: HTMLTextAreaElement) => {
    updateTrackedSelection(
      textarea.selectionStart ?? 0,
      textarea.selectionEnd ?? 0
    );
  };

  const handleToggleChecklistLine = (lineIndex: number) => {
    const currentText = draftFieldsRef.current.content;
    const toggled = toggleNoteMarkdownChecklistAtLine(currentText, lineIndex);
    if (!toggled) return;

    const textarea = contentTextareaRef.current;
    const hasTextareaSelection =
      editorMode === 'write' &&
      textarea !== null &&
      typeof document !== 'undefined' &&
      document.activeElement === textarea;

    const rawStart = hasTextareaSelection
      ? textarea.selectionStart ?? lastContentSelectionRef.current.start
      : lastContentSelectionRef.current.start;
    const rawEnd = hasTextareaSelection
      ? textarea.selectionEnd ?? rawStart
      : lastContentSelectionRef.current.end;

    const nextStart = Math.max(0, Math.min(toggled.text.length, rawStart));
    const nextEnd = Math.max(0, Math.min(toggled.text.length, rawEnd));

    draftFieldsRef.current.content = toggled.text;
    updateTrackedSelection(nextStart, nextEnd);
    if (editorMode === 'write') {
      pendingContentSelectionRef.current = { start: nextStart, end: nextEnd };
    }
    setEditContent(toggled.text);
  };

  const applyToolbarFormatting = (action: NoteToolbarFormatAction) => {
    const textarea = contentTextareaRef.current;
    const currentText = draftFieldsRef.current.content;
    const hasTextareaSelection =
      textarea !== null &&
      typeof document !== 'undefined' &&
      document.activeElement === textarea;

    const rawStart = hasTextareaSelection
      ? textarea.selectionStart ?? 0
      : lastContentSelectionRef.current.start;
    const rawEnd = hasTextareaSelection
      ? textarea.selectionEnd ?? rawStart
      : lastContentSelectionRef.current.end;

    const next = applyNoteToolbarFormat(currentText, rawStart, rawEnd, action);
    draftFieldsRef.current.content = next.text;
    updateTrackedSelection(next.selectionStart, next.selectionEnd);
    pendingContentSelectionRef.current = {
      start: next.selectionStart,
      end: next.selectionEnd,
    };
    setEditContent(next.text);
  };

  const handleEditorContentKeyDown = (
    e: React.KeyboardEvent<HTMLTextAreaElement>
  ) => {
    if (
      e.nativeEvent.isComposing ||
      e.shiftKey ||
      e.ctrlKey ||
      e.metaKey ||
      e.altKey
    ) {
      return;
    }

    const textarea = e.currentTarget;
    const start = textarea.selectionStart ?? 0;
    const end = textarea.selectionEnd ?? start;

    if (e.key === 'Enter') {
      const next = applyNoteSmartEnter(textarea.value, start, end);
      if (!next) return;
      e.preventDefault();
      draftFieldsRef.current.content = next.text;
      updateTrackedSelection(next.selectionStart, next.selectionEnd);
      pendingContentSelectionRef.current = {
        start: next.selectionStart,
        end: next.selectionEnd,
      };
      setEditContent(next.text);
      return;
    }

    if (e.key === 'Backspace') {
      const next = applyNoteSmartBackspace(textarea.value, start, end);
      if (!next) return;
      e.preventDefault();
      draftFieldsRef.current.content = next.text;
      updateTrackedSelection(next.selectionStart, next.selectionEnd);
      pendingContentSelectionRef.current = {
        start: next.selectionStart,
        end: next.selectionEnd,
      };
      setEditContent(next.text);
    }
  };

  const handleAddTag = (explicitTag?: string) => {
    const candidate = explicitTag ?? tagInput;
    const resolved = resolveReusableNoteTag(candidate, [
      ...editTags,
      ...allKnownTags,
    ]);
    if (!resolved) {
      if (explicitTag === undefined) setTagInput('');
      return;
    }
    const alreadyExists = editTags.some(
      (t) => t.toLowerCase() === resolved.toLowerCase()
    );
    if (alreadyExists) {
      if (explicitTag === undefined) setTagInput('');
      triggerFeedback(`Tag "#${resolved}" is already on this note.`);
      return;
    }
    const nextTags = normalizeNoteTags([...editTags, resolved]);
    setEditTags(nextTags);
    if (explicitTag === undefined) setTagInput('');
  };

  const handleRemoveTag = (tag: string) => {
    setEditTags(editTags.filter((t) => t !== tag));
  };

  const reusableTagSuggestions = useMemo(() => {
    const activeLower = new Set(editTags.map((t) => t.toLowerCase()));
    const needle = tagInput.trim().replace(/^#+/, '').toLowerCase();
    return allKnownTags.filter((tag) => {
      if (activeLower.has(tag.toLowerCase())) return false;
      if (!needle) return true;
      return tag.toLowerCase().includes(needle);
    });
  }, [allKnownTags, editTags, tagInput]);

  const openCreateFolderDialog = (targetContext: 'list' | 'editor' = 'list') => {
    setFolderNameDraft('');
    setFolderDialogError(null);
    setFolderDialogState({ mode: 'create', targetContext });
  };

  const openRenameFolderDialog = (folderName: string) => {
    if (isDefaultWebNotebook(folderName)) {
      triggerFeedback('Built-in folders cannot be renamed.', undefined, true);
      return;
    }
    setFolderNameDraft(folderName);
    setFolderDialogError(null);
    setFolderDialogState({ mode: 'rename', sourceName: folderName });
  };

  const handleSubmitFolderDialog = () => {
    if (!folderDialogState) return;
    if (folderDialogState.mode === 'create') {
      const res = createWebCustomFolder({
        existingFolders: customFolders,
        folderName: folderNameDraft,
        knownFolders: notebooks,
      });
      if (!res.ok || !res.folder) {
        setFolderDialogError(res.error ?? 'Could not create folder.');
        return;
      }
      persistCustomFolders(res.customFolders);
      if (folderDialogState.targetContext === 'editor') {
        setEditNotebook(res.folder);
      } else {
        setNotebookFilter(res.folder);
        if (activeTab === 'trash' || activeTab === 'archived') {
          setActiveTab('all');
        }
      }
      setFolderDialogState(null);
      setFolderNameDraft('');
      setFolderDialogError(null);
      triggerFeedback(`Created folder "${res.folder}"`);
      return;
    }

    const oldName = folderDialogState.sourceName ?? '';
    const res = renameWebNotebook({
      notes: notesRef.current,
      customFolders,
      oldName,
      newName: folderNameDraft,
    });
    if (!res.ok || !res.folder) {
      setFolderDialogError(res.error ?? 'Could not rename folder.');
      return;
    }
    if (res.affectedCount > 0) {
      applyNotesUpdate((prev) =>
        renameWebNotebook({
          notes: prev,
          customFolders,
          oldName,
          newName: folderNameDraft,
        }).notes
      );
    }
    persistCustomFolders(res.customFolders);
    if (
      normalizeFolderComparisonKey(notebookFilter) ===
      normalizeFolderComparisonKey(oldName)
    ) {
      setNotebookFilter(res.folder);
    }
    if (
      normalizeFolderComparisonKey(editNotebook) ===
      normalizeFolderComparisonKey(oldName)
    ) {
      setEditNotebook(res.folder);
    }
    setFolderDialogState(null);
    setFolderNameDraft('');
    setFolderDialogError(null);
    triggerFeedback(
      res.affectedCount > 0
        ? `Renamed "${oldName}" to "${res.folder}" (${res.affectedCount} ${
            res.affectedCount === 1 ? 'note' : 'notes'
          } updated)`
        : `Renamed folder "${oldName}" to "${res.folder}"`
    );
  };

  const handleConfirmDeleteFolder = () => {
    if (!confirmDeleteFolder) return;
    const targetName = confirmDeleteFolder;
    const prevNotesSnapshot = [...notesRef.current];
    const prevFoldersSnapshot = [...customFolders];
    const res = deleteWebNotebook({
      notes: prevNotesSnapshot,
      customFolders: prevFoldersSnapshot,
      folderName: targetName,
      destinationNotebook: 'Personal',
    });
    setConfirmDeleteFolder(null);
    if (!res.ok) {
      triggerFeedback(res.error ?? 'Could not delete folder.', undefined, true);
      return;
    }
    if (res.affectedCount > 0) {
      applyNotesUpdate((prev) =>
        deleteWebNotebook({
          notes: prev,
          customFolders: prevFoldersSnapshot,
          folderName: targetName,
          destinationNotebook: 'Personal',
        }).notes
      );
    }
    persistCustomFolders(res.customFolders);
    if (
      normalizeFolderComparisonKey(notebookFilter) ===
      normalizeFolderComparisonKey(targetName)
    ) {
      setNotebookFilter('all');
    }
    if (
      normalizeFolderComparisonKey(editNotebook) ===
      normalizeFolderComparisonKey(targetName)
    ) {
      setEditNotebook(res.destinationNotebook ?? 'Personal');
    }
    triggerFeedback(
      res.affectedCount > 0
        ? `Deleted folder "${targetName}" — moved ${res.affectedCount} ${
            res.affectedCount === 1 ? 'note' : 'notes'
          } to ${res.destinationNotebook ?? 'Personal'}`
        : `Deleted folder "${targetName}"`,
      () => {
        applyNotesUpdate(prevNotesSnapshot);
        persistCustomFolders(prevFoldersSnapshot);
      }
    );
  };

  const handleMoveCardNoteToFolder = (
    note: DaywellNote,
    targetNotebook: string
  ) => {
    if (isNoteTrashed(note)) {
      triggerFeedback('Restore note from Trash before moving folders.');
      return;
    }
    if (
      normalizeFolderComparisonKey(note.notebook) ===
      normalizeFolderComparisonKey(targetNotebook)
    ) {
      return;
    }
    if (isEditorOpen && selectedNoteIdRef.current === note.id) {
      clearAutosaveTimer();
      draftFieldsRef.current.notebook = targetNotebook;
      setEditNotebook(targetNotebook);
    }
    const prevSnapshot = [...notesRef.current];
    applyNotesUpdate((prev) => {
      const res = moveWebNoteToNotebook(prev, note.id, targetNotebook);
      return res.ok ? res.notes : prev;
    });
    triggerFeedback(
      `Moved "${getDisplayNoteTitle(note.title)}" to ${targetNotebook}`,
      () => applyNotesUpdate(prevSnapshot)
    );
  };

  const formatReadableNoteDate = (isoDate: string): string => {
    const parsed = SharedDateFormatter.tryParseFlexibleToCalendarDate(isoDate);
    if (!parsed) return isoDate.slice(0, 10);
    const todayEthYear = CalendarDate.fromUtcInstantInEthiopia(
      EthiopiaClock.nowUtc()
    ).year;
    return parsed.year === todayEthYear
      ? `${parsed.gregorianShortMonthName} ${parsed.day}`
      : `${parsed.gregorianShortMonthName} ${parsed.day}, ${parsed.year}`;
  };

  const formatDateFilterLabel = (mode: NoteDateFilterMode): string => {
    switch (mode) {
      case 'updated_7d':
        return 'Updated last 7d';
      case 'updated_30d':
        return 'Updated last 30d';
      case 'created_7d':
        return 'Created last 7d';
      case 'created_30d':
        return 'Created last 30d';
      default:
        return 'Any date';
    }
  };

  const formatSortLabel = (mode: NoteSortMode): string => {
    switch (mode) {
      case 'created':
        return 'Recently created';
      case 'alpha':
        return 'A–Z';
      case 'oldest':
        return 'Oldest first';
      default:
        return 'Recently updated';
    }
  };

  const formatActiveTabLabel = (tab: typeof activeTab): string => {
    switch (tab) {
      case 'pinned':
        return 'Pinned';
      case 'favorites':
        return 'Favorites';
      case 'archived':
        return 'Archived';
      case 'trash':
        return 'Trash';
      default:
        return 'All Notes';
    }
  };

  const deleteFolderNoteCount = confirmDeleteFolder
    ? notes.filter(
        (n) =>
          !isNoteTrashed(n) &&
          normalizeFolderComparisonKey(n.notebook) ===
            normalizeFolderComparisonKey(confirmDeleteFolder)
      ).length
    : 0;

  const masterListSection = (
        <div className="space-y-4 min-w-0">
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
            onChange={(val) => {
              if (
                isEditorOpen &&
                autosaveTimeoutRef.current !== null &&
                !isCurrentNewDraftBlank
              ) {
                commitEditorDraftToNote();
              }
              setSearchQuery(val);
            }}
            placeholder="Search notes, collections, or tags..."
            ariaLabel="Search notes, collections, or tags"
          />

          {/* Lifecycle Tabs */}
          <div className="flex items-center gap-1.5 overflow-x-auto pb-0.5" role="tablist" aria-label="Note lifecycle views">
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
              All Notes ({noteCounts.active})
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
              Pinned{noteCounts.pinned > 0 ? ` (${noteCounts.pinned})` : ''}
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={activeTab === 'favorites'}
              onClick={() => setActiveTab('favorites')}
              className={`min-h-[36px] text-xs px-3.5 py-1.5 rounded-[var(--dw-radius-full)] font-semibold transition-all shrink-0 flex items-center gap-1 cursor-pointer ${
                activeTab === 'favorites'
                  ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)] font-bold'
                  : 'bg-[var(--dw-card)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)]'
              }`}
            >
              <Star className="w-3 h-3" />
              Favorites{noteCounts.favorites > 0 ? ` (${noteCounts.favorites})` : ''}
            </button>
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
              Archived{noteCounts.archived > 0 ? ` (${noteCounts.archived})` : ''}
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={activeTab === 'trash'}
              onClick={() => setActiveTab('trash')}
              className={`min-h-[36px] text-xs px-3.5 py-1.5 rounded-[var(--dw-radius-full)] font-semibold transition-all shrink-0 flex items-center gap-1 cursor-pointer ${
                activeTab === 'trash'
                  ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)] font-bold'
                  : 'bg-[var(--dw-card)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)]'
              }`}
            >
              <Trash2 className="w-3 h-3" />
              Trash{noteCounts.trash > 0 ? ` (${noteCounts.trash})` : ''}
            </button>
          </div>

          {/* Folder Filter Strip + Management */}
          <div className="space-y-1.5">
            <div
              className="flex items-center gap-1.5 overflow-x-auto pb-0.5"
              role="group"
              aria-label="Note folders"
            >
              <button
                type="button"
                aria-pressed={notebookFilter === 'all'}
                onClick={() => setNotebookFilter('all')}
                className={`min-h-[34px] text-xs px-3 py-1 rounded-[var(--dw-radius-full)] font-semibold transition-all shrink-0 flex items-center gap-1 cursor-pointer ${
                  notebookFilter === 'all'
                    ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)] font-bold'
                    : 'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)]'
                }`}
              >
                <Folder className="w-3 h-3" />
                All Folders
              </button>
              {notebooks.map((nb) => {
                const isSelected =
                  normalizeFolderComparisonKey(notebookFilter) ===
                  normalizeFolderComparisonKey(nb);
                return (
                  <button
                    key={nb}
                    type="button"
                    aria-pressed={isSelected}
                    onClick={() => setNotebookFilter(isSelected ? 'all' : nb)}
                    className={`min-h-[34px] text-xs px-3 py-1 rounded-[var(--dw-radius-full)] font-semibold transition-all shrink-0 cursor-pointer ${
                      isSelected
                        ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)] font-bold'
                        : 'bg-[var(--dw-card)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)]'
                    }`}
                  >
                    {nb}
                  </button>
                );
              })}
              <button
                type="button"
                onClick={() => openCreateFolderDialog('list')}
                className="min-h-[34px] text-xs px-3 py-1 rounded-[var(--dw-radius-full)] font-semibold transition-all shrink-0 flex items-center gap-1 cursor-pointer bg-[var(--dw-surface-subtle)] text-[var(--dw-primary)] border border-dashed border-[var(--dw-border)] hover:border-[var(--dw-primary)]"
              >
                <FolderPlus className="w-3.5 h-3.5" />
                New Folder
              </button>
            </div>

            {notebookFilter !== 'all' && (
              <div className="flex items-center justify-between gap-2 flex-wrap px-2.5 py-1.5 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-xs">
                <div className="flex items-center gap-1.5 min-w-0">
                  <Folder className="w-3.5 h-3.5 text-[var(--dw-primary)] shrink-0" />
                  <span className="font-semibold text-[var(--dw-text-primary)] truncate">
                    Folder: {notebookFilter}
                  </span>
                </div>
                <div className="flex items-center gap-1.5 shrink-0">
                  {!isDefaultWebNotebook(notebookFilter) && (
                    <>
                      <DaywellButton
                        label="Rename"
                        variant="outlined"
                        size="compact"
                        leadingIcon={<Pencil className="w-3 h-3" />}
                        onClick={() => openRenameFolderDialog(notebookFilter)}
                      />
                      <DaywellButton
                        label="Delete"
                        variant="outlined"
                        size="compact"
                        leadingIcon={<Trash2 className="w-3 h-3" />}
                        onClick={() => setConfirmDeleteFolder(notebookFilter)}
                      />
                    </>
                  )}
                  <DaywellButton
                    label="Show All"
                    variant="text"
                    size="compact"
                    onClick={() => setNotebookFilter('all')}
                  />
                </div>
              </div>
            )}
          </div>

          {/* Tag Filter Strip */}
          {(availableFilterTags.length > 0 || tagFilter !== 'all') && (
            <div
              className="flex items-center gap-1.5 overflow-x-auto pb-0.5"
              role="group"
              aria-label="Filter by tag"
            >
              <button
                type="button"
                aria-pressed={tagFilter === 'all'}
                onClick={() => setTagFilter('all')}
                className={`min-h-[32px] text-[11px] px-2.5 py-1 rounded-[var(--dw-radius-full)] font-semibold transition-all shrink-0 flex items-center gap-1 cursor-pointer ${
                  tagFilter === 'all'
                    ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)] font-bold'
                    : 'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)]'
                }`}
              >
                <Tag className="w-3 h-3" />
                All Tags
              </button>
              {availableFilterTags.map((tag) => {
                const isSelected = tagFilter.toLowerCase() === tag.toLowerCase();
                return (
                  <button
                    key={tag}
                    type="button"
                    aria-pressed={isSelected}
                    onClick={() => setTagFilter(isSelected ? 'all' : tag)}
                    className={`min-h-[32px] text-[11px] px-2.5 py-1 rounded-[var(--dw-radius-full)] font-semibold transition-all shrink-0 cursor-pointer ${
                      isSelected
                        ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)] font-bold'
                        : 'bg-[var(--dw-card)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)]'
                    }`}
                  >
                    #{tag}
                  </button>
                );
              })}
            </div>
          )}

          {/* Date Filter, Sort & List/Grid View Controls */}
          <div className="flex items-center justify-between gap-2 flex-wrap">
            <div className="flex items-center gap-2 flex-wrap">
              <select
                aria-label="Filter by date"
                value={dateFilter}
                onChange={(e) => setDateFilter(e.target.value as NoteDateFilterMode)}
                className="min-h-[36px] rounded-[var(--dw-radius-md)] bg-[var(--dw-card)] text-[var(--dw-text-primary)] border border-[var(--dw-border)] px-2.5 py-1 text-xs font-medium outline-none focus:border-[var(--dw-primary)]"
              >
                <option value="all">Any date</option>
                <option value="updated_7d">Updated last 7 days</option>
                <option value="updated_30d">Updated last 30 days</option>
                <option value="created_7d">Created last 7 days</option>
                <option value="created_30d">Created last 30 days</option>
              </select>
              <select
                aria-label="Sort notes"
                value={sortBy}
                onChange={(e) => setSortBy(e.target.value as NoteSortMode)}
                className="min-h-[36px] rounded-[var(--dw-radius-md)] bg-[var(--dw-card)] text-[var(--dw-text-primary)] border border-[var(--dw-border)] px-2.5 py-1 text-xs font-medium outline-none focus:border-[var(--dw-primary)]"
              >
                <option value="recent">Sort: Recently updated</option>
                <option value="created">Sort: Recently created</option>
                <option value="alpha">Sort: Alphabetical (A–Z)</option>
                <option value="oldest">Sort: Oldest first</option>
              </select>
            </div>
            <DaywellIconButton
              label={viewMode === 'grid' ? 'Switch to List view' : 'Switch to Grid view'}
              size="compact"
              tone="muted"
              onClick={() => setViewMode((m) => (m === 'grid' ? 'list' : 'grid'))}
              icon={
                viewMode === 'grid' ? (
                  <List className="w-4 h-4" />
                ) : (
                  <LayoutGrid className="w-4 h-4" />
                )
              }
            />
          </div>

          {/* Active Filter Summary */}
          {hasActiveFilters && (
            <div className="flex items-center justify-between gap-2 flex-wrap px-2.5 py-1.5 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-xs">
              <span className="text-[var(--dw-text-secondary)] font-medium">
                {filteredNotes.length} {filteredNotes.length === 1 ? 'note' : 'notes'} ·{' '}
                {formatActiveTabLabel(activeTab)}
                {notebookFilter !== 'all' ? ` · ${notebookFilter}` : ''}
                {tagFilter !== 'all' ? ` · #${tagFilter}` : ''}
                {dateFilter !== 'all' ? ` · ${formatDateFilterLabel(dateFilter)}` : ''}
                {sortBy !== 'recent' ? ` · ${formatSortLabel(sortBy)}` : ''}
              </span>
              <DaywellButton
                label="Clear filters"
                variant="text"
                size="compact"
                onClick={clearAllFilters}
              />
            </div>
          )}

          {activeTab === 'trash' && noteCounts.trash > 0 && (
            <div className="flex items-center justify-between gap-2 flex-wrap">
              <DaywellStatusBanner
                tone="warning"
                message="Notes in Trash stay excluded from active notes, favorites, and search until restored or permanently deleted."
                className="flex-1 min-w-[220px]"
              />
              <DaywellButton
                label="Empty Trash"
                variant="outlined"
                size="compact"
                leadingIcon={<Trash2 className="w-3.5 h-3.5" />}
                onClick={() => setIsConfirmEmptyTrashOpen(true)}
              />
            </div>
          )}

          {/* Notes List / Grid */}
          <div
            className={
              filteredNotes.length === 0 || viewMode === 'list'
                ? 'space-y-3 pt-1'
                : isWideMasterDetail
                ? 'grid grid-cols-1 gap-3 pt-1'
                : 'grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 pt-1'
            }
          >
            {filteredNotes.length === 0 ? (
              searchQuery.trim() ||
              tagFilter !== 'all' ||
              dateFilter !== 'all' ||
              (notebookFilter !== 'all' && activeTab !== 'all') ? (
                <DaywellEmptyState
                  icon={<Search className="w-8 h-8" />}
                  message={
                    searchQuery.trim()
                      ? `No notes matching "${searchQuery}"`
                      : 'No notes match your active filters'
                  }
                  subtitle="Adjust or clear your active folder, tag, date, or search filters."
                  actionLabel="Clear filters"
                  onActionPressed={clearAllFilters}
                />
              ) : notebookFilter !== 'all' && activeTab === 'all' ? (
                <DaywellEmptyState
                  icon={<Folder className="w-8 h-8" />}
                  message={`No notes in "${notebookFilter}"`}
                  subtitle="Create a note in this folder or switch to another folder."
                  actionLabel="Create Note"
                  onActionPressed={handleCreateNote}
                />
              ) : activeTab === 'pinned' ? (
                <DaywellEmptyState
                  icon={<Pin className="w-8 h-8" />}
                  message="No pinned notes"
                  subtitle="Pin important notes to keep them anchored at the top of your workspace."
                  actionLabel="View All Notes"
                  onActionPressed={() => setActiveTab('all')}
                />
              ) : activeTab === 'favorites' ? (
                <DaywellEmptyState
                  icon={<Star className="w-8 h-8" />}
                  message="No favorite notes"
                  subtitle="Star notes you return to often to find them quickly here."
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
              ) : activeTab === 'trash' ? (
                <DaywellEmptyState
                  icon={<Trash2 className="w-8 h-8" />}
                  message="Trash is empty"
                  subtitle="Notes moved to Trash can be restored or permanently deleted here."
                  actionLabel="View All Notes"
                  onActionPressed={() => setActiveTab('all')}
                />
              ) : (
                <DaywellEmptyState
                  icon={<NotebookPen className="w-8 h-8" />}
                  message="No notes yet"
                  subtitle="Capture thoughts, meeting outlines, drafts, or reflections with offline autosave."
                  actionLabel="Create Note"
                  onActionPressed={handleCreateNote}
                />
              )
            ) : (
              filteredNotes.map((note) => {
                const trashed = isNoteTrashed(note);
                const isCardSelected =
                  isWideMasterDetail &&
                  isEditorOpen &&
                  selectedNoteId === note.id &&
                  !trashed;
                const displayTitle = getDisplayNoteTitle(note.title);
                const cardNotebooks = notebooks.some(
                  (nb) =>
                    normalizeFolderComparisonKey(nb) ===
                    normalizeFolderComparisonKey(note.notebook)
                )
                  ? notebooks
                  : [...notebooks, note.notebook];
                const extraTagCount = note.tags.length > 2 ? note.tags.length - 2 : 0;
                return (
                <DaywellCard
                  key={note.id}
                  radius="lg"
                  padding="md"
                  variant={isCardSelected ? 'primaryContainer' : 'default'}
                  aria-current={isCardSelected ? 'true' : undefined}
                  data-selected={isCardSelected ? 'true' : undefined}
                  onClick={trashed ? undefined : () => openEditor(note)}
                  className={
                    trashed
                      ? 'space-y-2'
                      : `${
                          isCardSelected
                            ? 'border-[var(--dw-primary)] ring-1 ring-[var(--dw-primary)]/30'
                            : 'hover:border-[var(--dw-primary)]/40'
                        } space-y-2 group ${
                          viewMode === 'grid' ? 'flex flex-col justify-between h-full' : ''
                        }`
                  }
                >
                  <div className="space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-center gap-2 min-w-0">
                      {note.isPinned && !trashed && (
                        <Pin className="w-3.5 h-3.5 text-[var(--dw-warning)] fill-current shrink-0" />
                      )}
                      {note.isFavorite && !trashed && (
                        <Star className="w-3.5 h-3.5 text-[var(--dw-warning)] fill-current shrink-0" />
                      )}
                      <h4 className="text-sm font-bold text-[var(--dw-text-primary)] group-hover:text-[var(--dw-primary)] transition-colors line-clamp-1">
                        {displayTitle}
                      </h4>
                    </div>
                    {trashed ? (
                      <div className="flex items-center gap-1.5 shrink-0">
                        <DaywellButton
                          label="Restore"
                          variant="tonal"
                          size="compact"
                          leadingIcon={<RotateCcw className="w-3.5 h-3.5" />}
                          onClick={(e) => handleRestoreFromTrash(note.id, e)}
                        />
                        <DaywellIconButton
                          label={`Delete ${displayTitle} permanently`}
                          size="compact"
                          tone="danger"
                          onClick={(e) => handleRequestPermanentDelete(note.id, e)}
                          icon={<Trash2 className="w-3.5 h-3.5" />}
                        />
                      </div>
                    ) : (
                      <div className="flex items-center gap-1 shrink-0">
                        <DaywellIconButton
                          label={note.isFavorite ? 'Remove favorite' : 'Favorite note'}
                          aria-pressed={Boolean(note.isFavorite)}
                          size="compact"
                          tone={note.isFavorite ? 'default' : 'muted'}
                          className={note.isFavorite ? 'text-[var(--dw-warning)]' : undefined}
                          onClick={(e) => toggleFavorite(note.id, e)}
                          icon={
                            <Star
                              className={`w-3.5 h-3.5 ${
                                note.isFavorite ? 'fill-current' : ''
                              }`}
                            />
                          }
                        />
                        <DaywellIconButton
                          label={note.isPinned ? 'Unpin note' : 'Pin note to top'}
                          aria-pressed={Boolean(note.isPinned)}
                          size="compact"
                          tone={note.isPinned ? 'primary' : 'muted'}
                          onClick={(e) => togglePin(note.id, e)}
                          icon={<Pin className="w-3.5 h-3.5" />}
                        />
                        <ArrowUpRight className="w-4 h-4 text-[var(--dw-text-muted)] group-hover:text-[var(--dw-primary)]" />
                      </div>
                    )}
                  </div>

                  {note.content && (
                    <p
                      className={`dw-type-body-compact text-[var(--dw-text-secondary)] ${
                        viewMode === 'grid' ? 'line-clamp-3' : 'line-clamp-2'
                      }`}
                    >
                      {markdownToPlainText(note.content) || note.content}
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

                  {note.linkedModule === 'calendar' && note.linkedId && (() => {
                    const linkedEvent = getLinkedCalendarEventForNote(
                      note,
                      effectiveCalendarEvents
                    );
                    if (linkedEvent) {
                      return (
                        <div className="flex items-center flex-wrap gap-1.5 pt-0.5">
                          {onNavigateToCalendarEvent ? (
                            <button
                              type="button"
                              onClick={(e) => {
                                e.stopPropagation();
                                onNavigateToCalendarEvent(linkedEvent);
                              }}
                              className="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-info-container)] text-[var(--dw-on-info-container)] hover:opacity-90 cursor-pointer max-w-full"
                              title={`Open linked event: ${linkedEvent.title}`}
                            >
                              <CalendarIcon className="w-3 h-3 shrink-0" />
                              <span className="truncate">
                                Event: {linkedEvent.title}
                              </span>
                              <ArrowUpRight className="w-3 h-3 shrink-0" />
                            </button>
                          ) : (
                            <span className="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-secondary)] max-w-full">
                              <CalendarIcon className="w-3 h-3 shrink-0 text-[var(--dw-primary)]" />
                              <span className="truncate">
                                Event: {linkedEvent.title}
                              </span>
                            </span>
                          )}
                          {linkedEvent.date && (
                            <DaywellStatusBadge
                              label={linkedEvent.date}
                              tone="neutral"
                              showIcon={false}
                            />
                          )}
                        </div>
                      );
                    }
                    return (
                      <div className="flex items-center gap-1.5 pt-0.5">
                        <span className="inline-flex items-center gap-1 text-[11px] font-medium px-2 py-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-muted)]">
                          <CalendarIcon className="w-3 h-3 shrink-0" />
                          <span>Linked event unavailable</span>
                        </span>
                      </div>
                    );
                  })()}

                  {note.projectId && (() => {
                    const linkedProject = getProjectForNote(
                      note,
                      effectiveProjects
                    );
                    if (linkedProject) {
                      return (
                        <div className="flex items-center flex-wrap gap-1.5 pt-0.5">
                          <span className="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-secondary)] max-w-full">
                            <Layers className="w-3 h-3 shrink-0 text-[var(--dw-primary)]" />
                            <span className="truncate">
                              Project: {linkedProject.title}
                            </span>
                          </span>
                          {linkedProject.isArchived && (
                            <DaywellStatusBadge
                              label="Archived"
                              tone="neutral"
                              showIcon={false}
                            />
                          )}
                        </div>
                      );
                    }
                    return (
                      <div className="flex items-center gap-1.5 pt-0.5">
                        <span className="inline-flex items-center gap-1 text-[11px] font-medium px-2 py-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-muted)]">
                          <Layers className="w-3 h-3 shrink-0" />
                          <span>Project unavailable</span>
                        </span>
                      </div>
                    );
                  })()}
                  </div>

                  <div className="flex items-center justify-between gap-2 text-[10px] text-[var(--dw-text-muted)] pt-1.5 border-t border-[var(--dw-divider)]">
                    <div className="flex items-center gap-1.5 flex-wrap min-w-0">
                      {trashed ? (
                        <DaywellStatusBadge label={note.notebook} tone="neutral" showIcon={false} />
                      ) : (
                        <div
                          className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)]"
                          onClick={(e) => e.stopPropagation()}
                        >
                          <Folder className="w-2.5 h-2.5 text-[var(--dw-primary)] shrink-0" />
                          <select
                            aria-label={`Move ${displayTitle} to folder`}
                            value={note.notebook}
                            onChange={(e) =>
                              handleMoveCardNoteToFolder(note, e.target.value)
                            }
                            className="bg-transparent text-[11px] font-semibold text-[var(--dw-text-primary)] outline-none cursor-pointer"
                          >
                            {cardNotebooks.map((nb) => (
                              <option key={nb} value={nb}>
                                {nb}
                              </option>
                            ))}
                          </select>
                        </div>
                      )}
                      {trashed && (
                        <DaywellStatusBadge label="In Trash" tone="warning" showIcon={false} />
                      )}
                      {note.isArchived && (
                        <DaywellStatusBadge label="Archived" tone="neutral" showIcon={false} />
                      )}
                      {note.tags.slice(0, 2).map((tag) => (
                        <span
                          key={tag}
                          className="inline-flex items-center px-1.5 py-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] text-[10px] font-semibold"
                        >
                          #{tag}
                        </span>
                      ))}
                      {extraTagCount > 0 && (
                        <span className="inline-flex items-center px-1.5 py-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-secondary)] text-[10px] font-semibold">
                          +{extraTagCount}
                        </span>
                      )}
                    </div>
                    <span className="shrink-0 font-medium">
                      {formatReadableNoteDate(note.updatedAt)}
                    </span>
                  </div>
                </DaywellCard>
                );
              })
            )}
          </div>
        </div>
  );

  const editorPanelSection = (
        /* SHARED LIVE EDITOR PANEL (FULL-SCREEN ON NARROW, DETAIL PANE ON WIDE) */
        <DaywellCard radius="xl" padding="lg" className="space-y-4 w-full max-w-[720px] mx-auto">
          {/* Editor Top Navigation */}
          <div className="flex items-center justify-between gap-2 flex-wrap border-b border-[var(--dw-divider)] pb-3">
            <div className="flex items-center gap-2">
              <DaywellButton
                label={isWideMasterDetail ? 'Close' : 'Done'}
                variant="tonal"
                size="compact"
                onClick={flushAutosaveAndClose}
                leadingIcon={
                  isWideMasterDetail ? (
                    <X className="w-3.5 h-3.5" />
                  ) : (
                    <Check className="w-3.5 h-3.5 stroke-[2.5]" />
                  )
                }
              />
              {currentEditorNote?.isArchived && (
                <DaywellStatusBadge label="Archived" tone="neutral" showIcon={false} />
              )}
              {selectedNoteId === null && (
                <DaywellStatusBadge label="Draft" tone="info" showIcon={false} />
              )}
            </div>

            <div className="flex items-center gap-1.5">
              <span className="dw-type-caption text-[var(--dw-text-muted)] flex items-center gap-1 font-medium mr-1">
                {saveStatus === 'saving' ? (
                  <>
                    <RotateCcw className="w-3 h-3 animate-spin text-[var(--dw-warning)]" />
                    <span>Autosaving...</span>
                  </>
                ) : selectedNoteId === null ? (
                  <span>New draft</span>
                ) : (
                  <>
                    <Check className="w-3 h-3 text-[var(--dw-success)]" />
                    <span>Saved offline</span>
                  </>
                )}
              </span>

              {!isCurrentNewDraftBlank && (
                <>
                  <DaywellIconButton
                    label={currentEditorNote?.isPinned ? 'Unpin Note' : 'Pin Note'}
                    aria-pressed={Boolean(currentEditorNote?.isPinned)}
                    size="compact"
                    tone={currentEditorNote?.isPinned ? 'primary' : 'muted'}
                    onClick={() => togglePin(selectedNoteId)}
                    icon={<Pin className="w-4 h-4" />}
                  />
                  <DaywellIconButton
                    label={
                      currentEditorNote?.isFavorite
                        ? 'Remove Favorite'
                        : 'Favorite Note'
                    }
                    aria-pressed={Boolean(currentEditorNote?.isFavorite)}
                    size="compact"
                    tone={currentEditorNote?.isFavorite ? 'default' : 'muted'}
                    className={
                      currentEditorNote?.isFavorite
                        ? 'text-[var(--dw-warning)]'
                        : undefined
                    }
                    onClick={() => toggleFavorite(selectedNoteId)}
                    icon={
                      <Star
                        className={`w-4 h-4 ${
                          currentEditorNote?.isFavorite ? 'fill-current' : ''
                        }`}
                      />
                    }
                  />
                  <DaywellIconButton
                    label={currentEditorNote?.isArchived ? 'Restore from Archive' : 'Archive Note'}
                    aria-pressed={Boolean(currentEditorNote?.isArchived)}
                    size="compact"
                    tone={currentEditorNote?.isArchived ? 'primary' : 'muted'}
                    onClick={() => toggleArchive(selectedNoteId)}
                    icon={<Archive className="w-4 h-4" />}
                  />
                  <DaywellIconButton
                    label="Move Note to Trash"
                    size="compact"
                    tone="danger"
                    onClick={() => handleMoveToTrash(selectedNoteId)}
                    icon={<Trash2 className="w-4 h-4" />}
                  />
                </>
              )}
            </div>
          </div>

          {/* Folder & Tags Bar */}
          <div className="space-y-2">
            <div className="flex items-center gap-2 flex-wrap text-xs">
              <div className="flex items-center gap-1.5 bg-[var(--dw-surface-subtle)] px-2.5 py-1.5 rounded-[var(--dw-radius-md)] border border-[var(--dw-border)]">
                <Folder className="w-3.5 h-3.5 text-[var(--dw-text-muted)]" />
                <select
                  aria-label="Note collection"
                  value={editNotebook}
                  onChange={(e) => setEditNotebook(e.target.value)}
                  className="bg-transparent text-xs font-semibold text-[var(--dw-text-primary)] outline-none cursor-pointer"
                >
                  {editorNotebooks.map((nb) => (
                    <option key={nb} value={nb}>
                      {nb}
                    </option>
                  ))}
                </select>
                <button
                  type="button"
                  aria-label="New folder"
                  title="New folder"
                  onClick={() => openCreateFolderDialog('editor')}
                  className="ml-1 p-0.5 rounded-[var(--dw-radius-sm)] text-[var(--dw-primary)] hover:bg-[var(--dw-card)] cursor-pointer"
                >
                  <FolderPlus className="w-3.5 h-3.5" />
                </button>
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

              <div className="inline-flex items-center gap-1">
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
                  className="w-24 px-2 py-1 text-[11px] bg-transparent border-b border-[var(--dw-border)] outline-none text-[var(--dw-text-secondary)] focus:border-[var(--dw-primary)]"
                />
                {tagInput.trim().length > 0 && (
                  <DaywellButton
                    label="Add"
                    variant="tonal"
                    size="compact"
                    onClick={() => handleAddTag()}
                  />
                )}
              </div>
            </div>

            {reusableTagSuggestions.length > 0 && (
              <div className="flex items-center gap-1.5 flex-wrap text-[11px]">
                <span className="text-[var(--dw-text-muted)] font-medium">
                  Reuse tag:
                </span>
                {reusableTagSuggestions.slice(0, 8).map((tag) => (
                  <button
                    key={tag}
                    type="button"
                    onClick={() => handleAddTag(tag)}
                    className="px-2 py-0.5 rounded-[var(--dw-radius-full)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-secondary)] hover:border-[var(--dw-primary)] hover:text-[var(--dw-primary)] font-medium cursor-pointer"
                  >
                    + #{tag}
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* Project Bar */}
          {(() => {
            const activeProject = editProjectId
              ? effectiveProjects.find((p) => p.id === editProjectId) ?? null
              : null;
            const isMissingProject = Boolean(editProjectId && !activeProject);
            const hasProjectChoices =
              selectableProjects.length > 0 || Boolean(editProjectId);
            if (!hasProjectChoices) return null;
            const selectOptions =
              activeProject && activeProject.isArchived
                ? [activeProject, ...selectableProjects]
                : selectableProjects;
            return (
              <div className="flex flex-wrap items-center justify-between gap-2 px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs">
                <div className="flex items-center gap-2 min-w-0">
                  <Layers
                    className={`w-3.5 h-3.5 shrink-0 ${
                      isMissingProject
                        ? 'text-[var(--dw-text-muted)]'
                        : 'text-[var(--dw-primary)]'
                    }`}
                  />
                  <div className="min-w-0">
                    <div className="text-[10px] font-bold uppercase tracking-wider text-[var(--dw-text-muted)]">
                      Project
                    </div>
                    <div className="flex items-center gap-1.5 flex-wrap">
                      <span
                        className={`text-xs font-semibold truncate ${
                          isMissingProject
                            ? 'text-[var(--dw-text-muted)]'
                            : 'text-[var(--dw-text-primary)]'
                        }`}
                      >
                        {editProjectId
                          ? activeProject
                            ? activeProject.title
                            : 'Project unavailable'
                          : 'None'}
                      </span>
                      {activeProject?.isArchived && (
                        <DaywellStatusBadge
                          label="Archived"
                          tone="neutral"
                          showIcon={false}
                        />
                      )}
                    </div>
                  </div>
                </div>
                <div className="flex items-center gap-1.5 shrink-0">
                  {selectOptions.length > 0 && (
                    <select
                      aria-label="Associate note with project"
                      value={activeProject ? activeProject.id : ''}
                      onChange={(e) =>
                        handleChangeNoteProject(selectedNoteId, e.target.value)
                      }
                      className="bg-transparent text-xs font-semibold text-[var(--dw-text-primary)] outline-none max-w-[200px] cursor-pointer"
                    >
                      <option value="">No project</option>
                      {selectOptions.map((proj) => (
                        <option key={proj.id} value={proj.id}>
                          {proj.isArchived
                            ? `${proj.title} (Archived)`
                            : proj.title}
                        </option>
                      ))}
                    </select>
                  )}
                  {editProjectId && (
                    <DaywellButton
                      label="Remove"
                      variant="outlined"
                      size="compact"
                      leadingIcon={<Unlink className="w-3 h-3" />}
                      onClick={() => handleChangeNoteProject(selectedNoteId, '')}
                    />
                  )}
                </div>
              </div>
            );
          })()}

          {/* Linked Task / Linked Calendar Event Bar */}
          {!isCurrentNewDraftBlank && (
            currentEditorNote?.linkedModule === 'tasks' && currentEditorNote.linkedId ? (() => {
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
                          commitEditorDraftToNote();
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
            })() : currentEditorNote?.linkedModule === 'calendar' && currentEditorNote.linkedId ? (() => {
              const linkedEvent = getLinkedCalendarEventForNote(
                currentEditorNote,
                effectiveCalendarEvents
              );
              return (
                <div className="flex flex-wrap items-center justify-between gap-2 px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)]">
                  <div className="flex items-center gap-2 min-w-0">
                    <CalendarIcon className="w-4 h-4 text-[var(--dw-primary)] shrink-0" />
                    <div className="min-w-0">
                      <div className="text-[10px] font-bold uppercase tracking-wider text-[var(--dw-text-muted)]">
                        Linked Event
                      </div>
                      <div className="flex items-center gap-1.5 flex-wrap">
                        <span className="text-xs font-semibold text-[var(--dw-text-primary)] truncate">
                          {linkedEvent
                            ? linkedEvent.title
                            : 'Linked event unavailable'}
                        </span>
                        {linkedEvent?.date && (
                          <DaywellStatusBadge
                            label={linkedEvent.date}
                            tone="neutral"
                            showIcon={false}
                          />
                        )}
                      </div>
                    </div>
                  </div>
                  <div className="flex items-center gap-1.5 shrink-0">
                    {linkedEvent && onNavigateToCalendarEvent && (
                      <DaywellButton
                        label="Open Event"
                        variant="tonal"
                        size="compact"
                        trailingIcon={<ArrowUpRight className="w-3.5 h-3.5" />}
                        onClick={() => {
                          commitEditorDraftToNote();
                          onNavigateToCalendarEvent(linkedEvent);
                        }}
                      />
                    )}
                    <DaywellButton
                      label="Unlink"
                      variant="outlined"
                      size="compact"
                      leadingIcon={<Unlink className="w-3 h-3" />}
                      onClick={() =>
                        handleUnlinkCalendarEventFromNote(currentEditorNote.id)
                      }
                    />
                  </div>
                </div>
              );
            })() : !currentEditorNote?.linkedModule && (selectableTasks.length > 0 || effectiveCalendarEvents.length > 0) ? (
              <div className="space-y-2">
                {selectableTasks.length > 0 && (
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
                          handleLinkTaskToNote(selectedNoteId, e.target.value);
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
                )}
                {effectiveCalendarEvents.length > 0 && (
                  <div className="flex items-center justify-between gap-2 px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs">
                    <div className="flex items-center gap-1.5 text-[var(--dw-text-secondary)] font-medium">
                      <CalendarIcon className="w-3.5 h-3.5 text-[var(--dw-text-muted)] shrink-0" />
                      <span>Event link</span>
                    </div>
                    <select
                      aria-label="Link note to calendar event"
                      value=""
                      onChange={(e) => {
                        if (e.target.value) {
                          handleLinkCalendarEventToNote(
                            selectedNoteId,
                            e.target.value
                          );
                        }
                      }}
                      className="bg-transparent text-xs font-semibold text-[var(--dw-text-primary)] outline-none max-w-[230px] cursor-pointer"
                    >
                      <option value="">Link to an event...</option>
                      {effectiveCalendarEvents.map((ev) => (
                        <option key={ev.id} value={ev.id}>
                          {ev.title} ({ev.date})
                        </option>
                      ))}
                    </select>
                  </div>
                )}
              </div>
            ) : null
          )}

          {/* Write / Preview Switcher */}
          <div className="flex items-center justify-between gap-2 flex-wrap">
            <div
              role="tablist"
              aria-label="Note editor mode"
              className="inline-flex items-center p-1 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] gap-1"
            >
              <button
                type="button"
                role="tab"
                aria-selected={editorMode === 'write'}
                onClick={() => setEditorMode('write')}
                className={`min-h-[36px] px-3 py-1.5 rounded-[var(--dw-radius-sm)] text-xs font-semibold inline-flex items-center gap-1.5 transition-all cursor-pointer ${
                  editorMode === 'write'
                    ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] font-bold'
                    : 'text-[var(--dw-text-secondary)] hover:text-[var(--dw-text-primary)]'
                }`}
              >
                <Pencil className="w-3.5 h-3.5" />
                <span>Write</span>
              </button>
              <button
                type="button"
                role="tab"
                aria-selected={editorMode === 'preview'}
                onClick={() => setEditorMode('preview')}
                className={`min-h-[36px] px-3 py-1.5 rounded-[var(--dw-radius-sm)] text-xs font-semibold inline-flex items-center gap-1.5 transition-all cursor-pointer ${
                  editorMode === 'preview'
                    ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] font-bold'
                    : 'text-[var(--dw-text-secondary)] hover:text-[var(--dw-text-primary)]'
                }`}
              >
                <Eye className="w-3.5 h-3.5" />
                <span>Preview</span>
              </button>
            </div>
          </div>

          {editorMode === 'write' ? (
            <>
              {/* Formatting Toolbar */}
              <div
                role="toolbar"
                aria-label="Markdown formatting"
                className="flex items-center gap-1 p-1 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] overflow-x-auto"
              >
                <button
                  type="button"
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => applyToolbarFormatting('heading2')}
                  aria-label="Heading 2"
                  title="Heading 2"
                  className="min-w-[36px] min-h-[36px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-xs font-bold text-[var(--dw-text-secondary)] cursor-pointer inline-flex items-center justify-center shrink-0"
                >
                  H2
                </button>
                <button
                  type="button"
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => applyToolbarFormatting('bold')}
                  aria-label="Bold"
                  title="Bold"
                  className="min-w-[36px] min-h-[36px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-[var(--dw-text-secondary)] cursor-pointer inline-flex items-center justify-center shrink-0"
                >
                  <Bold className="w-3.5 h-3.5" />
                </button>
                <button
                  type="button"
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => applyToolbarFormatting('italic')}
                  aria-label="Italic"
                  title="Italic"
                  className="min-w-[36px] min-h-[36px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-[var(--dw-text-secondary)] cursor-pointer inline-flex items-center justify-center shrink-0"
                >
                  <Italic className="w-3.5 h-3.5" />
                </button>
                <button
                  type="button"
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => applyToolbarFormatting('strikethrough')}
                  aria-label="Strikethrough"
                  title="Strikethrough"
                  className="min-w-[36px] min-h-[36px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-[var(--dw-text-secondary)] cursor-pointer inline-flex items-center justify-center shrink-0"
                >
                  <Strikethrough className="w-3.5 h-3.5" />
                </button>
                <span
                  aria-hidden="true"
                  className="w-px h-5 bg-[var(--dw-divider)] mx-0.5 shrink-0"
                />
                <button
                  type="button"
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => applyToolbarFormatting('bulletList')}
                  aria-label="Bulleted list"
                  title="Bulleted list"
                  className="min-w-[36px] min-h-[36px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-[var(--dw-text-secondary)] cursor-pointer inline-flex items-center justify-center shrink-0"
                >
                  <List className="w-3.5 h-3.5" />
                </button>
                <button
                  type="button"
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => applyToolbarFormatting('numberedList')}
                  aria-label="Numbered list"
                  title="Numbered list"
                  className="min-w-[36px] min-h-[36px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-[var(--dw-text-secondary)] cursor-pointer inline-flex items-center justify-center shrink-0"
                >
                  <ListOrdered className="w-3.5 h-3.5" />
                </button>
                <button
                  type="button"
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => applyToolbarFormatting('checklist')}
                  aria-label="Checklist"
                  title="Checklist"
                  className="min-w-[36px] min-h-[36px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-[var(--dw-text-secondary)] cursor-pointer inline-flex items-center justify-center shrink-0"
                >
                  <CheckSquare className="w-3.5 h-3.5" />
                </button>
                <button
                  type="button"
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => applyToolbarFormatting('blockquote')}
                  aria-label="Blockquote"
                  title="Blockquote"
                  className="min-w-[36px] min-h-[36px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-[var(--dw-text-secondary)] cursor-pointer inline-flex items-center justify-center shrink-0"
                >
                  <Quote className="w-3.5 h-3.5" />
                </button>
                <span
                  aria-hidden="true"
                  className="w-px h-5 bg-[var(--dw-divider)] mx-0.5 shrink-0"
                />
                <button
                  type="button"
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => applyToolbarFormatting('inlineCode')}
                  aria-label="Inline code"
                  title="Inline code"
                  className="min-w-[36px] min-h-[36px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-[var(--dw-text-secondary)] cursor-pointer inline-flex items-center justify-center shrink-0"
                >
                  <Code className="w-3.5 h-3.5" />
                </button>
                <button
                  type="button"
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => applyToolbarFormatting('codeBlock')}
                  aria-label="Code block"
                  title="Code block"
                  className="min-w-[36px] min-h-[36px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-[var(--dw-text-secondary)] cursor-pointer inline-flex items-center justify-center shrink-0"
                >
                  <SquareCode className="w-3.5 h-3.5" />
                </button>
                <button
                  type="button"
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => applyToolbarFormatting('internalLink')}
                  aria-label="Internal note link"
                  title="Internal note link ([[Note Title]])"
                  className="min-w-[36px] min-h-[36px] p-1.5 rounded-[var(--dw-radius-sm)] hover:bg-[var(--dw-card)] text-[var(--dw-text-secondary)] cursor-pointer inline-flex items-center justify-center shrink-0"
                >
                  <Link2 className="w-3.5 h-3.5" />
                </button>
                {activeWriteChecklist && (
                  <>
                    <span
                      aria-hidden="true"
                      className="w-px h-5 bg-[var(--dw-divider)] mx-0.5 shrink-0"
                    />
                    <button
                      type="button"
                      onMouseDown={(e) => e.preventDefault()}
                      onClick={() =>
                        handleToggleChecklistLine(activeWriteChecklist.lineIndex)
                      }
                      aria-label={
                        activeWriteChecklist.checked
                          ? 'Mark item incomplete'
                          : 'Mark item complete'
                      }
                      title={
                        activeWriteChecklist.checked
                          ? 'Mark item incomplete'
                          : 'Mark item complete'
                      }
                      className="min-h-[36px] px-2.5 py-1.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] text-[11px] font-semibold cursor-pointer inline-flex items-center gap-1.5 shrink-0"
                    >
                      {activeWriteChecklist.checked ? (
                        <CheckSquare className="w-3.5 h-3.5" />
                      ) : (
                        <Square className="w-3.5 h-3.5" />
                      )}
                      <span>
                        {activeWriteChecklist.checked ? 'Checked' : 'Check item'}
                      </span>
                    </button>
                  </>
                )}
              </div>

              {/* Title Input */}
              <input
                type="text"
                value={editTitle}
                maxLength={MAX_NOTE_TITLE_LENGTH}
                onChange={(e) => setEditTitle(e.target.value)}
                placeholder="Note Title"
                className="w-full dw-type-heading bg-transparent border-none outline-none text-[var(--dw-text-primary)] placeholder:text-[var(--dw-text-muted)]"
              />

              {/* Content Textarea */}
              <textarea
                id="note-content-editor"
                ref={contentTextareaRef}
                value={editContent}
                onChange={(e) => {
                  syncTextareaSelection(e.currentTarget);
                  draftFieldsRef.current.content = e.target.value;
                  setEditContent(e.target.value);
                }}
                onKeyDown={handleEditorContentKeyDown}
                onSelect={(e) => syncTextareaSelection(e.currentTarget)}
                onKeyUp={(e) => syncTextareaSelection(e.currentTarget)}
                onMouseUp={(e) => syncTextareaSelection(e.currentTarget)}
                placeholder="Type your notes here... (Supports Markdown syntax, checklists, and Ethiopian Ge'ez script)"
                rows={14}
                className="w-full bg-transparent border-none outline-none text-xs text-[var(--dw-text-primary)] placeholder:text-[var(--dw-text-muted)] font-sans leading-relaxed resize-none"
              />
            </>
          ) : (
            <div className="space-y-4 pt-1">
              <h2 className="dw-type-heading text-[var(--dw-text-primary)] break-words">
                {getDisplayNoteTitle(editTitle)}
              </h2>
              <div className="min-h-[260px] pt-1">
                <NoteMarkdownPreview
                  content={editContent}
                  notes={liveNotesForInternalLinks}
                  onToggleChecklistItem={handleToggleChecklistLine}
                  onOpenInternalNote={handleNavigateToInternalNote}
                  onOpenAmbiguousInternalLink={handleOpenAmbiguousInternalLink}
                />
              </div>
            </div>
          )}

          {/* Backlinks Section */}
          {!isCurrentNewDraftBlank && (
            <section
              data-testid="note-backlinks-section"
              aria-label="Backlinks"
              className="pt-3 border-t border-[var(--dw-divider)] space-y-2"
            >
              <div className="flex items-center justify-between gap-2">
                <span className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)] font-bold">
                  Backlinks ({currentNoteBacklinks.length})
                </span>
              </div>
              {currentNoteBacklinks.length === 0 ? (
                <p className="dw-type-body-compact text-[var(--dw-text-muted)]">
                  No active notes link to this note yet.
                </p>
              ) : (
                <div className="space-y-2">
                  {currentNoteBacklinks.map((entry) => {
                    const refTitle = getDisplayNoteTitle(entry.note.title);
                    return (
                      <button
                        key={entry.note.id}
                        type="button"
                        data-testid={`backlink-item-${entry.note.id}`}
                        onClick={() => handleNavigateToInternalNote(entry.note.id)}
                        className="w-full text-left p-2.5 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] hover:border-[var(--dw-primary)]/40 transition-colors flex items-start justify-between gap-2 cursor-pointer"
                      >
                        <div className="min-w-0 space-y-0.5">
                          <div className="flex items-center gap-1.5 min-w-0">
                            <FileText
                              className="w-3.5 h-3.5 text-[var(--dw-primary)] shrink-0"
                              aria-hidden="true"
                            />
                            <span className="text-xs font-semibold text-[var(--dw-text-primary)] truncate">
                              {refTitle}
                            </span>
                            {entry.linkCount > 1 && (
                              <span className="text-[10px] font-semibold text-[var(--dw-text-muted)] shrink-0">
                                ({entry.linkCount})
                              </span>
                            )}
                          </div>
                          {entry.snippet && (
                            <p className="dw-type-body-compact text-[var(--dw-text-secondary)] line-clamp-2 break-words">
                              {entry.snippet}
                            </p>
                          )}
                        </div>
                        <ArrowUpRight
                          className="w-4 h-4 text-[var(--dw-text-muted)] shrink-0 mt-0.5"
                          aria-hidden="true"
                        />
                      </button>
                    );
                  })}
                </div>
              )}
            </section>
          )}
        </DaywellCard>
  );

  return (
    <div ref={moduleContainerRef} className="space-y-4">
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

      {isWideMasterDetail ? (
        <div
          data-testid="notes-master-detail-layout"
          className="grid grid-cols-[minmax(320px,370px)_minmax(0,1fr)] gap-5 items-start"
        >
          {masterListSection}
          <div className="min-w-0 sticky top-3">
            {isEditorOpen ? (
              editorPanelSection
            ) : (
              <DaywellCard
                radius="xl"
                padding="lg"
                data-testid="notes-detail-empty-state"
                className="w-full max-w-[720px] mx-auto"
              >
                <DaywellEmptyState
                  icon={<NotebookPen className="w-8 h-8" />}
                  message="Select a note to read or edit"
                  subtitle={
                    filteredNotes.length === 0
                      ? 'Create a new note or adjust filters on the left.'
                      : 'Choose a note from the list on the left, or start a new note.'
                  }
                  actionLabel="Create Note"
                  onActionPressed={handleCreateNote}
                />
              </DaywellCard>
            )}
          </div>
        </div>
      ) : !isEditorOpen ? (
        masterListSection
      ) : (
        editorPanelSection
      )}

      {/* Ambiguous Internal Link Disambiguation Modal */}
      {ambiguousLinkChoice && (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="ambiguous-note-link-title"
          data-testid="ambiguous-note-link-dialog"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/45"
          onClick={() => setAmbiguousLinkChoice(null)}
        >
          <div
            className="w-full max-w-md rounded-[var(--dw-radius-xl)] bg-[var(--dw-elevated)] border border-[var(--dw-border)] shadow-2xl p-4 space-y-3"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-start justify-between gap-2">
              <div className="space-y-0.5 min-w-0">
                <h3
                  id="ambiguous-note-link-title"
                  className="dw-type-title text-[var(--dw-text-primary)] break-words"
                >
                  Choose note for &ldquo;{ambiguousLinkChoice.targetTitle}&rdquo;
                </h3>
                <p className="dw-type-body-compact text-[var(--dw-text-secondary)]">
                  Multiple active notes share this title. Select the note you want to open.
                </p>
              </div>
              <DaywellIconButton
                label="Close chooser"
                size="compact"
                tone="muted"
                onClick={() => setAmbiguousLinkChoice(null)}
                icon={<X className="w-4 h-4" />}
              />
            </div>

            <div className="max-h-64 overflow-y-auto space-y-2">
              {ambiguousLinkChoice.matches.map((match) => {
                const snippet = (markdownToPlainText(match.content) || match.content).trim();
                const dateObj = SharedDateFormatter.tryParseFlexibleToCalendarDate(
                  match.updatedAt
                );
                const dateLabel = dateObj
                  ? `${dateObj.gregorianShortMonthName} ${dateObj.day}`
                  : match.updatedAt.slice(0, 10);
                return (
                  <button
                    key={match.id}
                    type="button"
                    data-testid={`ambiguous-choice-${match.id}`}
                    onClick={() => handleNavigateToInternalNote(match.id)}
                    className="w-full text-left p-2.5 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] hover:border-[var(--dw-primary)] transition-colors space-y-1 cursor-pointer"
                  >
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-xs font-bold text-[var(--dw-text-primary)] truncate">
                        {getDisplayNoteTitle(match.title)}
                      </span>
                      <span className="text-[10px] font-medium text-[var(--dw-text-muted)] shrink-0">
                        {match.notebook} · {dateLabel}
                      </span>
                    </div>
                    {snippet && (
                      <p className="dw-type-body-compact text-[var(--dw-text-secondary)] line-clamp-2 break-words">
                        {snippet}
                      </p>
                    )}
                  </button>
                );
              })}
            </div>

            <div className="flex justify-end pt-1">
              <DaywellButton
                label="Cancel"
                variant="outlined"
                size="compact"
                onClick={() => setAmbiguousLinkChoice(null)}
              />
            </div>
          </div>
        </div>
      )}

      {/* Permanent Delete Confirmation Modal (Trash Only) */}
      <DaywellConfirmationDialog
        isOpen={Boolean(confirmPermanentDeleteNote)}
        title="Delete Note Permanently?"
        description={
          confirmPermanentDeleteNote
            ? `Permanently delete "${getDisplayNoteTitle(confirmPermanentDeleteNote.title)}"? This cannot be undone.`
            : ''
        }
        cancelLabel="Cancel"
        confirmLabel={isDeleting ? 'Deleting...' : 'Delete Forever'}
        destructive
        onCancel={() => setConfirmPermanentDeleteNote(null)}
        onConfirm={handleConfirmPermanentDeleteNote}
      />

      {/* Empty Trash Confirmation Modal */}
      <DaywellConfirmationDialog
        isOpen={isConfirmEmptyTrashOpen}
        title="Empty Trash?"
        description={`Permanently delete all ${noteCounts.trash} ${
          noteCounts.trash === 1 ? 'note' : 'notes'
        } in Trash? This cannot be undone.`}
        cancelLabel="Cancel"
        confirmLabel={isDeleting ? 'Emptying...' : 'Empty Trash'}
        destructive
        onCancel={() => setIsConfirmEmptyTrashOpen(false)}
        onConfirm={handleConfirmEmptyTrash}
      />

      {/* Create / Rename Folder Modal */}
      {folderDialogState && (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="note-folder-dialog-title"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/45"
          onClick={() => setFolderDialogState(null)}
        >
          <div
            className="w-full max-w-sm rounded-[var(--dw-radius-xl)] bg-[var(--dw-elevated)] border border-[var(--dw-border)] shadow-2xl p-5 space-y-4"
            onClick={(e) => e.stopPropagation()}
          >
            <h3
              id="note-folder-dialog-title"
              className="dw-type-title text-[var(--dw-text-primary)]"
            >
              {folderDialogState.mode === 'create' ? 'New Folder' : 'Rename Folder'}
            </h3>
            <DaywellTextField
              label="Folder name"
              placeholder="e.g. Research"
              value={folderNameDraft}
              errorText={folderDialogError ?? undefined}
              onChange={(e) => {
                setFolderNameDraft(e.target.value);
                if (folderDialogError) setFolderDialogError(null);
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault();
                  handleSubmitFolderDialog();
                }
              }}
              autoFocus
            />
            <div className="flex items-center justify-end gap-2">
              <DaywellButton
                label="Cancel"
                variant="outlined"
                size="compact"
                onClick={() => setFolderDialogState(null)}
              />
              <DaywellButton
                label={folderDialogState.mode === 'create' ? 'Create' : 'Rename'}
                variant="primary"
                size="compact"
                onClick={handleSubmitFolderDialog}
              />
            </div>
          </div>
        </div>
      )}

      {/* Delete Folder Confirmation Modal (Safe Note Reassignment) */}
      <DaywellConfirmationDialog
        isOpen={Boolean(confirmDeleteFolder)}
        title="Delete Folder?"
        description={
          confirmDeleteFolder
            ? deleteFolderNoteCount > 0
              ? `Delete "${confirmDeleteFolder}"? No notes will be deleted — ${deleteFolderNoteCount} ${
                  deleteFolderNoteCount === 1 ? 'note' : 'notes'
                } will move safely to "Personal".`
              : `Delete empty folder "${confirmDeleteFolder}"?`
            : ''
        }
        cancelLabel="Cancel"
        confirmLabel="Delete Folder"
        destructive
        onCancel={() => setConfirmDeleteFolder(null)}
        onConfirm={handleConfirmDeleteFolder}
      />
    </div>
  );
}
