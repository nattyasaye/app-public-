import React, { useState, useEffect, useMemo, useRef } from 'react';
import {
  Calendar as CalendarIcon,
  ChevronLeft,
  ChevronRight,
  Plus,
  Clock,
  MapPin,
  CheckCircle2,
  Circle,
  Search,
  X,
  Trash2,
  Repeat,
  CalendarDays,
  Sun,
  Loader2,
  AlertTriangle,
  NotebookPen,
} from 'lucide-react';
import {
  CalendarDate,
  DateRange,
  SharedDateFormatter,
} from '../domain/date';
import {
  SHARED_DESIGN_TOKENS,
  SharedTaskRecurrenceConfig,
} from '../domain/sharedFoundation';
import {
  projectTasksForDateRange,
  TaskCalendarOccurrence,
} from '../domain/taskCalendar';
import { TaskStatus } from '../domain/taskOperations';
import { validateCalendarEventForm, isFormDirty } from '../domain/formValidationAndNavigation';
import {
  DailyRhythmDayRecord,
  evaluateDailyRhythmTimeline,
} from '../domain/dailyRhythm';
import {
  DailyRhythmCalendarDayInspection,
  describeDailyRhythmCalendarDay,
} from '../domain/dailyRhythmWorkflows';
import { DailyRhythmCalendarDetailCard } from './daily-rhythm';
import { UnsavedChangesDialog } from './UnsavedChangesDialog';
import { CalendarEventNotesSection } from './calendar/CalendarEventNotesSection';
import type { DaywellNote } from './DaywellNotesModule';
import {
  countNotesLinkedToCalendarEvent,
  createNoteForCalendarEvent,
  linkNoteToCalendarEvent,
  undoCalendarEventNoteLink,
  unlinkNoteFromCalendarEvent,
  unlinkNotesForDeletedCalendarEvent,
} from '../domain/calendarNotes';
import { notesService } from '../services/notesService';
import { SharedStateBridge } from '../services/sharedStateBridge';
import {
  DaywellButton,
  DaywellCard,
  DaywellEmptyState,
  DaywellIconButton,
  DaywellSearchField,
  DaywellStatusBadge,
} from './ui';

export interface CalendarEvent {
  id: string;
  title: string;
  description?: string;
  date: string; // YYYY-MM-DD
  endDate?: string; // YYYY-MM-DD
  startTime?: string; // HH:MM
  endTime?: string; // HH:MM
  isAllDay: boolean;
  category: 'work' | 'personal' | 'finance' | 'health' | 'family';
  colorHex: string;
  location?: string;
  recurrence?: 'none' | 'daily' | 'weekly' | 'monthly' | 'yearly';
  hasReminder: boolean;
  linkedTaskId?: string;
}

export interface CalendarTaskRef {
  id: string;
  title: string;
  dueDate?: string;
  scheduledDate?: string;
  scheduledTime?: string;
  estimatedDurationMinutes?: number;
  status?: TaskStatus;
  isArchived?: boolean;
  completed: boolean;
  priority?: 'urgent' | 'high' | 'medium' | 'low';
  isRecurring?: boolean;
  recurringRule?: 'daily' | 'weekly' | 'monthly';
  recurrenceRule?: string;
  recurrenceConfig?: SharedTaskRecurrenceConfig;
  recurrenceSummary?: string;
  projectId?: string;
  projectName?: string;
}

interface DaywellCalendarModuleProps {
  tasks?: CalendarTaskRef[];
  notes?: DaywellNote[];
  onUpdateNotes?: (
    updater: DaywellNote[] | ((prev: DaywellNote[]) => DaywellNote[])
  ) => void;
  onToggleTask?: (taskId: string) => void;
  onNavigateToTask?: (taskId: string) => void;
  onNavigateToNote?: (noteId: string) => void;
  onEventsChange?: (events: CalendarEvent[]) => void;
  requestedFocusDate?: { dateStr: string; eventId?: string; nonce: number } | null;
  dailyRhythmDays?: DailyRhythmDayRecord[];
  onRequestQuickCapture?: () => void;
}

const CATEGORY_COLORS: Record<CalendarEvent['category'], { label: string; badgeClass: string }> = {
  work: {
    label: 'Work',
    badgeClass: 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border-[var(--dw-primary)]/20',
  },
  personal: {
    label: 'Personal',
    badgeClass: 'bg-[var(--dw-info-container)] text-[var(--dw-on-info-container)] border-[var(--dw-info)]/25',
  },
  finance: {
    label: 'Finance',
    badgeClass: 'bg-[var(--dw-warning-container)] text-[var(--dw-on-warning-container)] border-[var(--dw-warning)]/25',
  },
  health: {
    label: 'Health',
    badgeClass: 'bg-[var(--dw-expense-container)] text-[var(--dw-on-expense-container)] border-[var(--dw-expense)]/25',
  },
  family: {
    label: 'Family',
    badgeClass: 'bg-[var(--dw-transfer-container)] text-[var(--dw-on-transfer-container)] border-[var(--dw-transfer)]/25',
  },
};

function getRhythmCellIndicator(
  inspection: DailyRhythmCalendarDayInspection,
  isSelected: boolean
): { glyph: string; className: string; label: string } | null {
  switch (inspection.calendarStatus) {
    case 'complete':
      return {
        glyph: '✓',
        className: isSelected
          ? 'text-[var(--dw-on-primary)]'
          : 'text-[var(--dw-income)]',
        label: 'Complete',
      };
    case 'partial':
      return {
        glyph: '◐',
        className: isSelected
          ? 'text-[var(--dw-on-primary)]'
          : 'text-[var(--dw-warning)]',
        label: 'In progress',
      };
    case 'freeze_protected':
      return {
        glyph: inspection.isProvisionalFreeze ? '❄?' : '❄',
        className: isSelected
          ? 'text-[var(--dw-on-primary)]'
          : 'text-[var(--dw-info)]',
        label: inspection.isProvisionalFreeze
          ? 'Freeze provisional'
          : 'Freeze protected',
      };
    case 'missed':
      return {
        glyph: '✕',
        className: isSelected
          ? 'text-[var(--dw-on-primary)]'
          : 'text-[var(--dw-expense)]',
        label: 'Missed',
      };
    case 'untouched':
      if (inspection.isToday) return null;
      return {
        glyph: '✕',
        className: isSelected
          ? 'text-[var(--dw-on-primary)]'
          : 'text-[var(--dw-expense)]',
        label: 'Untouched',
      };
    case 'unrecorded':
    default:
      return null;
  }
}

export function DaywellCalendarModule({
  tasks = [],
  notes: controlledNotes,
  onUpdateNotes,
  onToggleTask,
  onNavigateToTask,
  onNavigateToNote,
  onEventsChange,
  requestedFocusDate,
  dailyRhythmDays = [],
}: DaywellCalendarModuleProps) {
  const [viewMode, setViewMode] = useState<'month' | 'week' | 'day' | 'agenda'>('month');
  const [currentDate, setCurrentDate] = useState<CalendarDate>(() => CalendarDate.today());
  const [selectedDateStr, setSelectedDateStr] = useState<string>(() => CalendarDate.today().toIsoString());
  const [highlightedEventId, setHighlightedEventId] = useState<string | null>(null);

  useEffect(() => {
    if (!requestedFocusDate?.dateStr) return;
    const parsed = CalendarDate.tryParse(requestedFocusDate.dateStr);
    if (!parsed) return;
    setCurrentDate(parsed);
    setSelectedDateStr(parsed.toIsoString());
    setHighlightedEventId(requestedFocusDate.eventId ?? null);
    setViewMode((prev) => (prev === 'agenda' ? 'month' : prev));
  }, [requestedFocusDate?.nonce, requestedFocusDate?.dateStr, requestedFocusDate?.eventId]);

  const [internalNotes, setInternalNotes] = useState<DaywellNote[]>(() =>
    notesService.loadNotes()
  );

  useEffect(() => {
    if (typeof window === 'undefined' || controlledNotes !== undefined) return;
    const handleNotesSync = () => {
      setInternalNotes(notesService.loadNotes());
    };
    window.addEventListener(SharedStateBridge.SYNC_EVENT_NAME, handleNotesSync);
    return () =>
      window.removeEventListener(
        SharedStateBridge.SYNC_EVENT_NAME,
        handleNotesSync
      );
  }, [controlledNotes]);

  const effectiveNotes = controlledNotes ?? internalNotes;
  const notesRef = useRef<DaywellNote[]>(effectiveNotes);
  notesRef.current = effectiveNotes;

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

  const [events, setEvents] = useState<CalendarEvent[]>(() => {
    try {
      const saved = localStorage.getItem('daywell_calendar_events');
      if (saved) {
        const parsed = JSON.parse(saved);
        if (Array.isArray(parsed) && parsed.length > 0) return parsed;
      }
    } catch {
      // ignore
    }
    return [];
  });
  const eventsRef = useRef<CalendarEvent[]>(events);
  eventsRef.current = events;
  const tasksRef = useRef(tasks);
  tasksRef.current = tasks;

  useEffect(() => {
    if (typeof window === 'undefined') return;
    const handleCalendarSync = (event: Event) => {
      const detail =
        event instanceof CustomEvent &&
        event.detail &&
        typeof event.detail === 'object'
          ? (event.detail as Record<string, unknown>)
          : null;
      if (detail?.source === 'calendar_module') return;
      try {
        const saved = localStorage.getItem('daywell_calendar_events');
        if (saved) {
          const parsed = JSON.parse(saved);
          if (Array.isArray(parsed)) {
            setEvents(parsed);
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
  }, []);

  const commitEvents = (nextEvents: CalendarEvent[]) => {
    setEvents(nextEvents);
    try {
      localStorage.setItem('daywell_calendar_events', JSON.stringify(nextEvents));
    } catch (e) {
      console.error(e);
    }
    onEventsChange?.(nextEvents);
    if (typeof window !== 'undefined') {
      window.dispatchEvent(
        new CustomEvent(SharedStateBridge.SYNC_EVENT_NAME, {
          detail: { calendarEvents: nextEvents, source: 'calendar_module' },
        })
      );
    }
  };

  useEffect(() => {
    try {
      localStorage.setItem('daywell_calendar_events', JSON.stringify(events));
    } catch (e) {
      console.error(e);
    }
  }, [events]);

  const [searchQuery, setSearchQuery] = useState('');
  const [categoryFilter, setCategoryFilter] = useState<string>('all');

  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingEventId, setEditingEventId] = useState<string | null>(null);
  const [formTitle, setFormTitle] = useState('');
  const [formDescription, setFormDescription] = useState('');
  const [formDate, setFormDate] = useState(selectedDateStr);
  const [formEndDate, setFormEndDate] = useState('');
  const [formStartTime, setFormStartTime] = useState('10:00');
  const [formEndTime, setFormEndTime] = useState('11:00');
  const [formIsAllDay, setFormIsAllDay] = useState(false);
  const [formCategory, setFormCategory] = useState<CalendarEvent['category']>('personal');
  const [formLocation, setFormLocation] = useState('');
  const [formRecurrence, setFormRecurrence] = useState<CalendarEvent['recurrence']>('none');
  const [formHasReminder, setFormHasReminder] = useState(true);

  const [formErrors, setFormErrors] = useState<Record<string, string>>({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [showUnsavedPrompt, setShowUnsavedPrompt] = useState(false);
  const [initialEventValues, setInitialEventValues] = useState<Record<string, unknown> | null>(null);
  const titleInputRef = useRef<HTMLInputElement>(null);

  const [undoToast, setUndoToast] = useState<{ message: string; undoAction: () => void } | null>(null);

  const triggerUndo = (message: string, undoAction: () => void) => {
    setUndoToast({ message, undoAction });
    setTimeout(() => {
      setUndoToast((cur) => (cur?.message === message ? null : cur));
    }, 5000);
  };

  const currentEthiopian = useMemo(() => currentDate.toEthiopian(), [currentDate]);
  const selectedCalendarDate = useMemo(
    () => CalendarDate.tryParse(selectedDateStr) ?? CalendarDate.today(),
    [selectedDateStr]
  );

  const dailyRhythmSummary = useMemo(
    () => evaluateDailyRhythmTimeline(dailyRhythmDays),
    [dailyRhythmDays]
  );
  const selectedDailyRhythm = useMemo(
    () =>
      describeDailyRhythmCalendarDay({
        dateIso: selectedCalendarDate.toIsoString(),
        timelineSummary: dailyRhythmSummary,
      }),
    [selectedCalendarDate, dailyRhythmSummary]
  );

  const navigateMonth = (direction: number) => {
    setCurrentDate((prev) =>
      direction < 0 ? prev.previousGregorianMonth() : prev.nextGregorianMonth()
    );
  };

  const jumpToToday = () => {
    const today = CalendarDate.today();
    setCurrentDate(today);
    setSelectedDateStr(today.toIsoString());
  };

  const eventOccursOnDate = (ev: CalendarEvent, day: CalendarDate): boolean => {
    const start = CalendarDate.tryParse(ev.date);
    if (!start) return ev.date === day.toIsoString();
    const end = ev.endDate ? CalendarDate.tryParse(ev.endDate) : null;
    if (end && !end.isBefore(start)) {
      return new DateRange(start, end).contains(day);
    }
    return start.isSameDay(day);
  };

  const monthGridDates = useMemo(() => {
    const startOfMonth = currentDate.startOfGregorianMonth;
    const startDayOfWeek = startOfMonth.weekday - 1;

    const gridDates: Array<{ date: CalendarDate; isCurrentMonth: boolean }> = [];

    for (let i = startDayOfWeek; i > 0; i--) {
      gridDates.push({ date: startOfMonth.subtractDays(i), isCurrentMonth: false });
    }
    for (const day of currentDate.gregorianMonthDays()) {
      gridDates.push({ date: day, isCurrentMonth: true });
    }
    const endOfMonth = currentDate.endOfGregorianMonth;
    const trailing = (7 - (gridDates.length % 7)) % 7;
    for (let i = 1; i <= trailing; i++) {
      gridDates.push({ date: endOfMonth.addDays(i), isCurrentMonth: false });
    }
    return gridDates;
  }, [currentDate]);

  const monthTaskOccurrences = useMemo(() => {
    if (monthGridDates.length === 0) return [];
    const first = monthGridDates[0].date;
    const last = monthGridDates[monthGridDates.length - 1].date;
    const minDate = selectedCalendarDate.isBefore(first) ? selectedCalendarDate : first;
    const maxDate = selectedCalendarDate.isAfter(last) ? selectedCalendarDate : last;
    return projectTasksForDateRange(tasks, minDate.toIsoString(), maxDate.toIsoString());
  }, [tasks, monthGridDates, selectedCalendarDate]);

  const monthDays = useMemo(() => {
    return monthGridDates.map(({ date, isCurrentMonth }) => {
      const dateStr = date.toIsoString();
      const eth = date.toEthiopian();
      const dayEvents = events.filter((e) => eventOccursOnDate(e, date));
      const dayTasks = monthTaskOccurrences.filter((t) => t.occurrenceDate === dateStr);
      const hasStoredTasks = dayTasks.some((t) => !t.isProjectedOccurrence);
      const hasProjectedTasks = dayTasks.some((t) => t.isProjectedOccurrence);
      const rhythm = describeDailyRhythmCalendarDay({
        dateIso: dateStr,
        timelineSummary: dailyRhythmSummary,
      });
      return {
        dateStr,
        dayNumber: date.day,
        isCurrentMonth,
        ethiopian: eth,
        hasEvents: dayEvents.length > 0,
        hasTasks: dayTasks.length > 0,
        hasStoredTasks,
        hasProjectedTasks,
        eventCount: dayEvents.length + dayTasks.length,
        rhythm,
      };
    });
  }, [monthGridDates, events, monthTaskOccurrences, dailyRhythmSummary]);

  const selectedDayItems = useMemo(() => {
    let dayEvents = events.filter((e) => eventOccursOnDate(e, selectedCalendarDate));
    let dayTasks = monthTaskOccurrences.filter(
      (t) => t.occurrenceDate === selectedDateStr
    );

    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      dayEvents = dayEvents.filter(
        (e) =>
          e.title.toLowerCase().includes(q) ||
          (e.description && e.description.toLowerCase().includes(q))
      );
      dayTasks = dayTasks.filter(
        (t) =>
          t.task.title.toLowerCase().includes(q) ||
          (t.task.projectName && t.task.projectName.toLowerCase().includes(q)) ||
          (t.recurrenceSummary && t.recurrenceSummary.toLowerCase().includes(q))
      );
    }

    if (categoryFilter !== 'all') {
      dayEvents = dayEvents.filter((e) => e.category === categoryFilter);
    }

    dayEvents.sort((a, b) => {
      if (a.isAllDay && !b.isAllDay) return -1;
      if (!a.isAllDay && b.isAllDay) return 1;
      return (a.startTime || '00:00').localeCompare(b.startTime || '00:00');
    });

    return { events: dayEvents, tasks: dayTasks };
  }, [events, monthTaskOccurrences, selectedCalendarDate, selectedDateStr, searchQuery, categoryFilter]);

  const agendaTimeline = useMemo(() => {
    const today = CalendarDate.today();
    const horizonEnd = today.addDays(30);
    const q = searchQuery.trim().toLowerCase();

    let filteredEvents = [...events];
    if (q) {
      filteredEvents = filteredEvents.filter(
        (e) =>
          e.title.toLowerCase().includes(q) ||
          (e.description && e.description.toLowerCase().includes(q))
      );
    }
    if (categoryFilter !== 'all') {
      filteredEvents = filteredEvents.filter((e) => e.category === categoryFilter);
    }
    filteredEvents.sort(
      (a, b) =>
        a.date.localeCompare(b.date) || (a.startTime || '').localeCompare(b.startTime || '')
    );

    let agendaTasks = projectTasksForDateRange(
      tasks,
      today.toIsoString(),
      horizonEnd.toIsoString()
    );
    if (q) {
      agendaTasks = agendaTasks.filter(
        (t) =>
          t.task.title.toLowerCase().includes(q) ||
          (t.task.projectName && t.task.projectName.toLowerCase().includes(q)) ||
          (t.recurrenceSummary && t.recurrenceSummary.toLowerCase().includes(q))
      );
    }

    type AgendaEntry =
      | { kind: 'event'; sortDate: string; sortTime: string; event: CalendarEvent }
      | { kind: 'task'; sortDate: string; sortTime: string; occurrence: TaskCalendarOccurrence<CalendarTaskRef> };

    const combined: AgendaEntry[] = [
      ...filteredEvents.map((ev) => ({
        kind: 'event' as const,
        sortDate: ev.date,
        sortTime: ev.isAllDay ? '00:00' : ev.startTime || '00:00',
        event: ev,
      })),
      ...agendaTasks.map((occ) => ({
        kind: 'task' as const,
        sortDate: occ.occurrenceDate,
        sortTime: occ.scheduledTime || '23:59',
        occurrence: occ,
      })),
    ];

    combined.sort((a, b) => {
      const dateCmp = a.sortDate.localeCompare(b.sortDate);
      if (dateCmp !== 0) return dateCmp;
      if (a.kind !== b.kind) return a.kind === 'event' ? -1 : 1;
      return a.sortTime.localeCompare(b.sortTime);
    });

    return combined;
  }, [events, tasks, searchQuery, categoryFilter]);

  const getCurrentEventValues = () => ({
    title: formTitle,
    description: formDescription,
    date: formDate,
    endDate: formEndDate,
    startTime: formStartTime,
    endTime: formEndTime,
    isAllDay: formIsAllDay,
    category: formCategory,
    location: formLocation,
    recurrence: formRecurrence,
    hasReminder: formHasReminder,
  });

  const handleAttemptClose = () => {
    if (initialEventValues && isFormDirty(initialEventValues, getCurrentEventValues())) {
      setShowUnsavedPrompt(true);
    } else {
      setIsModalOpen(false);
      setFormErrors({});
    }
  };

  const handleOpenCreate = () => {
    setEditingEventId(null);
    setFormTitle('');
    setFormDescription('');
    setFormDate(selectedDateStr);
    setFormEndDate('');
    setFormStartTime('10:00');
    setFormEndTime('11:00');
    setFormIsAllDay(false);
    setFormCategory('personal');
    setFormLocation('');
    setFormRecurrence('none');
    setFormHasReminder(true);
    setFormErrors({});
    setIsSubmitting(false);

    setInitialEventValues({
      title: '',
      description: '',
      date: selectedDateStr,
      endDate: '',
      startTime: '10:00',
      endTime: '11:00',
      isAllDay: false,
      category: 'personal',
      location: '',
      recurrence: 'none',
      hasReminder: true,
    });

    setIsModalOpen(true);
    setTimeout(() => {
      titleInputRef.current?.focus();
    }, 60);
  };

  const handleOpenEdit = (event: CalendarEvent) => {
    setEditingEventId(event.id);
    setFormTitle(event.title);
    setFormDescription(event.description || '');
    setFormDate(event.date);
    setFormEndDate(event.endDate || '');
    setFormStartTime(event.startTime || '10:00');
    setFormEndTime(event.endTime || '11:00');
    setFormIsAllDay(event.isAllDay);
    setFormCategory(event.category);
    setFormLocation(event.location || '');
    setFormRecurrence(event.recurrence || 'none');
    setFormHasReminder(event.hasReminder);
    setFormErrors({});
    setIsSubmitting(false);

    setInitialEventValues({
      title: event.title,
      description: event.description || '',
      date: event.date,
      endDate: event.endDate || '',
      startTime: event.startTime || '10:00',
      endTime: event.endTime || '11:00',
      isAllDay: event.isAllDay,
      category: event.category,
      location: event.location || '',
      recurrence: event.recurrence || 'none',
      hasReminder: event.hasReminder,
    });

    setIsModalOpen(true);
    setTimeout(() => {
      titleInputRef.current?.focus();
    }, 60);
  };

  const handleSaveEvent = (e: React.FormEvent) => {
    e.preventDefault();

    const normalizedEndDate = formEndDate.trim() && formEndDate.trim() !== formDate ? formEndDate.trim() : undefined;
    const validation = validateCalendarEventForm({
      title: formTitle,
      date: formDate,
      endDate: normalizedEndDate,
      isAllDay: formIsAllDay,
      startTime: formStartTime,
      endTime: formEndTime,
      location: formLocation,
    });

    if (!validation.isValid) {
      setFormErrors(validation.errors);
      if (validation.errors.title) {
        titleInputRef.current?.focus();
      }
      return;
    }

    if (isSubmitting) return;
    setIsSubmitting(true);

    const previousEvents = [...events];

    if (editingEventId) {
      const updated = events.map((ev) =>
        ev.id === editingEventId
          ? {
              ...ev,
              title: formTitle.trim(),
              description: formDescription.trim() || undefined,
              date: formDate,
              endDate: normalizedEndDate,
              startTime: formIsAllDay ? undefined : formStartTime,
              endTime: formIsAllDay ? undefined : formEndTime,
              isAllDay: formIsAllDay,
              category: formCategory,
              location: formLocation.trim() || undefined,
              recurrence: formRecurrence,
              hasReminder: formHasReminder,
            }
          : ev
      );
      commitEvents(updated);
      setIsSubmitting(false);
      setIsModalOpen(false);
      setFormErrors({});
      triggerUndo('Event updated', () => commitEvents(previousEvents));
    } else {
      const newEvent: CalendarEvent = {
        id: `evt-${Date.now()}`,
        title: formTitle.trim(),
        description: formDescription.trim() || undefined,
        date: formDate,
        endDate: normalizedEndDate,
        startTime: formIsAllDay ? undefined : formStartTime,
        endTime: formIsAllDay ? undefined : formEndTime,
        isAllDay: formIsAllDay,
        category: formCategory,
        colorHex:
          formCategory === 'work'
            ? SHARED_DESIGN_TOKENS.colors.primary.emerald
            : formCategory === 'finance'
            ? SHARED_DESIGN_TOKENS.colors.semantic.warning
            : SHARED_DESIGN_TOKENS.colors.semantic.info,
        location: formLocation.trim() || undefined,
        recurrence: formRecurrence,
        hasReminder: formHasReminder,
      };
      commitEvents([newEvent, ...events]);
      setSelectedDateStr(formDate);
      setIsSubmitting(false);
      setIsModalOpen(false);
      setFormErrors({});
      triggerUndo(`Added "${newEvent.title}"`, () => commitEvents(previousEvents));
    }
  };

  const handleDeleteEvent = (id: string) => {
    const previous = [...events];
    const previousNotes = [...notesRef.current];
    const target = events.find((e) => e.id === id);
    const unlinkRes = unlinkNotesForDeletedCalendarEvent(previousNotes, id);
    if (unlinkRes.unlinkedCount > 0) {
      applyNotesUpdate(unlinkRes.notes);
    }
    commitEvents(events.filter((e) => e.id !== id));
    if (highlightedEventId === id) {
      setHighlightedEventId(null);
    }
    setIsModalOpen(false);
    triggerUndo(`Deleted "${target?.title || 'event'}"`, () => {
      commitEvents(previous);
      if (unlinkRes.unlinkedCount > 0) {
        applyNotesUpdate((cur) => {
          let next = cur;
          for (const nid of unlinkRes.unlinkedNoteIds) {
            const relinked = linkNoteToCalendarEvent(
              next,
              nid,
              id,
              undefined,
              { allowReassign: false }
            );
            if (relinked.ok) {
              next = relinked.notes;
            }
          }
          return next;
        });
      }
    });
  };

  const todayIsoStr = CalendarDate.today().toIsoString();
  const isToday = (dateStr: string) => dateStr === todayIsoStr;
  const isSelected = (dateStr: string) => dateStr === selectedDateStr;

  return (
    <div className="space-y-4">
      {/* Undo Toast */}
      {undoToast && (
        <div
          role="status"
          aria-live="polite"
          className="fixed bottom-20 left-1/2 -translate-x-1/2 z-50 flex items-center gap-3 px-4 py-2.5 bg-[var(--dw-elevated)] text-[var(--dw-text-primary)] border border-[var(--dw-border)] text-xs rounded-[var(--dw-radius-lg)] shadow-xl"
        >
          <span>{undoToast.message}</span>
          <DaywellButton
            label="Undo"
            variant="text"
            size="compact"
            onClick={() => {
              undoToast.undoAction();
              setUndoToast(null);
            }}
            className="uppercase tracking-wider"
          />
        </div>
      )}

      {/* Header & View Switcher */}
      <div className="flex items-start justify-between pt-1">
        <div>
          <div className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)] flex items-center gap-1.5">
            <Sun className="w-3 h-3 text-[var(--dw-warning)]" />
            <span>Dual Ethiopian-Gregorian Calendar</span>
          </div>
          <h1 className="dw-type-display text-[var(--dw-text-primary)] flex items-center flex-wrap gap-2">
            <span>{currentDate.gregorianFullMonthName} {currentDate.year}</span>
            <DaywellStatusBadge
              tone="info"
              showIcon={false}
              label={`${currentEthiopian.amharicMonthName} ${currentEthiopian.year} ዓ.ም`}
              className="!bg-[var(--dw-primary-container)] !text-[var(--dw-on-primary-container)] !border-[var(--dw-primary)]/20"
            />
          </h1>
        </div>
        <div className="flex items-center gap-1.5">
          <DaywellButton
            label="Today"
            variant="tonal"
            size="compact"
            onClick={jumpToToday}
          />
          <DaywellIconButton
            label="Create Event"
            tone="primary"
            onClick={handleOpenCreate}
            icon={<Plus className="w-5 h-5 stroke-[2.5]" />}
            className="bg-[var(--dw-primary)] text-[var(--dw-on-primary)] hover:opacity-90"
          />
        </div>
      </div>

      {/* Dual Banner Info Pill */}
      <DaywellCard
        radius="lg"
        padding="sm"
        className="!bg-[var(--dw-primary-container-subtle)] !border-[var(--dw-primary)]/25 flex items-center justify-between"
      >
        <div className="flex items-center gap-2 min-w-0">
          <CalendarIcon className="w-4 h-4 text-[var(--dw-primary)] shrink-0" />
          <div className="text-xs truncate">
            <span className="font-bold text-[var(--dw-text-primary)]">Selected: </span>
            <span className="text-[var(--dw-primary)] font-semibold">
              {SharedDateFormatter.formatDual(selectedCalendarDate)}
            </span>
          </div>
        </div>
        <div className="flex items-center gap-1 shrink-0">
          <DaywellIconButton
            label="Previous Month"
            size="compact"
            tone="muted"
            onClick={() => navigateMonth(-1)}
            icon={<ChevronLeft className="w-4 h-4" />}
          />
          <DaywellIconButton
            label="Next Month"
            size="compact"
            tone="muted"
            onClick={() => navigateMonth(1)}
            icon={<ChevronRight className="w-4 h-4" />}
          />
        </div>
      </DaywellCard>

      {/* View Switcher & Filter */}
      <div className="flex items-center justify-between gap-2">
        <div
          className="flex items-center gap-1 bg-[var(--dw-surface-subtle)] p-1 rounded-[var(--dw-radius-lg)] border border-[var(--dw-border)]"
          role="tablist"
          aria-label="Calendar view mode"
        >
          {(['month', 'day', 'agenda'] as const).map((mode) => (
            <button
              key={mode}
              type="button"
              role="tab"
              aria-selected={viewMode === mode}
              onClick={() => setViewMode(mode)}
              className={`min-h-[34px] px-3 py-1 text-xs font-bold rounded-[var(--dw-radius-md)] transition-all capitalize cursor-pointer ${
                viewMode === mode
                  ? 'bg-[var(--dw-card)] text-[var(--dw-text-primary)] shadow-xs'
                  : 'text-[var(--dw-text-muted)] hover:text-[var(--dw-text-primary)]'
              }`}
            >
              {mode}
            </button>
          ))}
        </div>

        <select
          aria-label="Filter calendar by category"
          value={categoryFilter}
          onChange={(e) => setCategoryFilter(e.target.value)}
          className="min-h-[38px] text-xs bg-[var(--dw-card)] border border-[var(--dw-border)] rounded-[var(--dw-radius-md)] px-2.5 py-1.5 text-[var(--dw-text-secondary)] outline-none focus:border-[var(--dw-primary)]"
        >
          <option value="all">All Categories</option>
          <option value="work">Work</option>
          <option value="personal">Personal</option>
          <option value="finance">Finance</option>
          <option value="health">Health</option>
          <option value="family">Family</option>
        </select>
      </div>

      {/* MONTH VIEW */}
      {viewMode === 'month' && (
        <DaywellCard radius="xl" padding="sm" className="space-y-2">
          <div className="grid grid-cols-7 text-center dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)] pb-1.5 border-b border-[var(--dw-divider)]">
            <span>Mon</span>
            <span>Tue</span>
            <span>Wed</span>
            <span>Thu</span>
            <span>Fri</span>
            <span>Sat</span>
            <span>Sun</span>
          </div>

          <div className="grid grid-cols-7 gap-1">
            {monthDays.map((d) => {
              const currentSelected = isSelected(d.dateStr);
              const todayCell = isToday(d.dateStr);
              const rhythmMarker = getRhythmCellIndicator(
                d.rhythm,
                currentSelected
              );

              return (
                <button
                  key={d.dateStr}
                  type="button"
                  aria-label={`${d.dateStr}, Daily Rhythm: ${d.rhythm.statusLabel}`}
                  onClick={() => setSelectedDateStr(d.dateStr)}
                  className={`min-h-[54px] p-1 rounded-[var(--dw-radius-md)] flex flex-col items-center justify-between transition-all relative cursor-pointer ${
                    currentSelected
                      ? 'bg-[var(--dw-primary)] text-[var(--dw-on-primary)] shadow-sm ring-2 ring-[var(--dw-primary)]/30'
                      : todayCell
                      ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] font-bold'
                      : d.isCurrentMonth
                      ? 'hover:bg-[var(--dw-surface-subtle)] text-[var(--dw-text-primary)]'
                      : 'text-[var(--dw-text-disabled)]'
                  }`}
                >
                  <div className="w-full flex items-center justify-between px-0.5">
                    <span className="text-xs font-bold leading-none">
                      {d.dayNumber}
                    </span>
                    {rhythmMarker && (
                      <span
                        title={`Daily Rhythm: ${rhythmMarker.label}`}
                        className={`text-[9px] font-extrabold leading-none ${rhythmMarker.className}`}
                      >
                        {rhythmMarker.glyph}
                      </span>
                    )}
                  </div>

                  <span
                    className={`text-[9px] font-medium leading-none ${
                      currentSelected ? 'opacity-90' : 'text-[var(--dw-text-muted)]'
                    }`}
                  >
                    {d.ethiopian.day}
                  </span>

                  <div className="flex items-center gap-0.5 mt-0.5">
                    {d.hasEvents && (
                      <span
                        className={`w-1.5 h-1.5 rounded-full ${
                          currentSelected ? 'bg-[var(--dw-warning)]' : 'bg-[var(--dw-primary)]'
                        }`}
                      />
                    )}
                    {d.hasStoredTasks && (
                      <span
                        className={`w-1.5 h-1.5 rounded-full ${
                          currentSelected ? 'bg-current' : 'bg-[var(--dw-info)]'
                        }`}
                      />
                    )}
                    {!d.hasStoredTasks && d.hasProjectedTasks && (
                      <span
                        className={`w-1.5 h-1.5 rounded-full opacity-75 ${
                          currentSelected ? 'bg-current' : 'bg-[var(--dw-transfer)]'
                        }`}
                      />
                    )}
                  </div>
                </button>
              );
            })}
          </div>

          <div
            aria-label="Daily Rhythm calendar legend"
            className="pt-2 border-t border-[var(--dw-divider)] flex flex-wrap items-center gap-x-3 gap-y-1 text-[10px] text-[var(--dw-text-muted)]"
          >
            <span className="font-semibold text-[var(--dw-text-secondary)]">
              Rhythm:
            </span>
            <span className="inline-flex items-center gap-1">
              <strong className="text-[var(--dw-income)]">✓</strong> Complete
            </span>
            <span className="inline-flex items-center gap-1">
              <strong className="text-[var(--dw-warning)]">◐</strong> In progress
            </span>
            <span className="inline-flex items-center gap-1">
              <strong className="text-[var(--dw-info)]">❄?</strong> Provisional freeze
            </span>
            <span className="inline-flex items-center gap-1">
              <strong className="text-[var(--dw-info)]">❄</strong> Freeze protected
            </span>
            <span className="inline-flex items-center gap-1">
              <strong className="text-[var(--dw-expense)]">✕</strong> Missed
            </span>
          </div>
        </DaywellCard>
      )}

      {/* DAY VIEW & SELECTED AGENDA DETAILS */}
      {(viewMode === 'month' || viewMode === 'day') && (
        <div className="space-y-3 pt-1">
          <DailyRhythmCalendarDetailCard inspection={selectedDailyRhythm} />

          <div className="flex items-center justify-between gap-2">
            <h3 className="dw-type-label text-[var(--dw-text-primary)] uppercase tracking-wider flex items-center gap-1.5">
              <CalendarDays className="w-3.5 h-3.5 text-[var(--dw-primary)]" />
              <span>Schedule for {SharedDateFormatter.formatDual(selectedCalendarDate)}</span>
            </h3>
            <span className="dw-type-caption text-[var(--dw-text-muted)] shrink-0">
              {selectedDayItems.events.length} events · {selectedDayItems.tasks.length} tasks
            </span>
          </div>

          {selectedDayItems.events.length === 0 && selectedDayItems.tasks.length === 0 ? (
            <DaywellEmptyState
              icon={<CalendarIcon className="w-8 h-8" />}
              message="No events or tasks scheduled"
              subtitle="Enjoy your free time, or add a meeting, reminder, or personal commitment."
              actionLabel="Add Event"
              onActionPressed={handleOpenCreate}
            />
          ) : (
            <div className="space-y-2">
              {selectedDayItems.events.map((ev) => {
                const color = CATEGORY_COLORS[ev.category];
                const linkedNotesCount = countNotesLinkedToCalendarEvent(
                  effectiveNotes,
                  ev.id
                );
                const isHighlighted = highlightedEventId === ev.id;
                return (
                  <DaywellCard
                    key={ev.id}
                    radius="lg"
                    padding="sm"
                    onClick={() => handleOpenEdit(ev)}
                    className={`hover:border-[var(--dw-primary)]/40 flex items-start justify-between gap-3 group ${
                      isHighlighted
                        ? 'border-[var(--dw-primary)] ring-2 ring-[var(--dw-primary)]/20'
                        : ''
                    }`}
                  >
                    <div className="flex items-start gap-3">
                      <div className="w-2.5 h-2.5 rounded-full mt-1.5 shrink-0" style={{ backgroundColor: ev.colorHex }} />
                      <div className="space-y-1">
                        <div className="flex items-center flex-wrap gap-2">
                          <h4 className="text-xs font-bold text-[var(--dw-text-primary)] group-hover:text-[var(--dw-primary)] transition-colors">
                            {ev.title}
                          </h4>
                          <span className={`text-[10px] font-bold px-2 py-0.5 rounded-[var(--dw-radius-sm)] border ${color.badgeClass}`}>
                            {color.label}
                          </span>
                        </div>
                        {ev.description && (
                          <p className="text-[11px] text-[var(--dw-text-secondary)] leading-snug">
                            {ev.description}
                          </p>
                        )}
                        <div className="flex items-center flex-wrap gap-3 text-[10px] text-[var(--dw-text-muted)] pt-0.5">
                          <span className="flex items-center gap-1 font-semibold text-[var(--dw-text-secondary)]">
                            <Clock className="w-3 h-3 text-[var(--dw-text-muted)]" />
                            {ev.isAllDay ? 'All Day' : `${ev.startTime} – ${ev.endTime || ''}`}
                          </span>
                          {ev.location && (
                            <span className="flex items-center gap-1">
                              <MapPin className="w-3 h-3" />
                              {ev.location}
                            </span>
                          )}
                          {ev.recurrence && ev.recurrence !== 'none' && (
                            <span className="flex items-center gap-1 text-[var(--dw-success)]">
                              <Repeat className="w-3 h-3" />
                              {ev.recurrence}
                            </span>
                          )}
                          {linkedNotesCount > 0 && (
                            <span className="inline-flex items-center gap-1 font-medium text-[var(--dw-primary)]">
                              <NotebookPen className="w-3 h-3" />
                              {linkedNotesCount}{' '}
                              {linkedNotesCount === 1 ? 'note' : 'notes'}
                            </span>
                          )}
                        </div>
                      </div>
                    </div>
                    <DaywellIconButton
                      label={`Delete ${ev.title}`}
                      size="compact"
                      tone="danger"
                      onClick={(e) => {
                        e.stopPropagation();
                        handleDeleteEvent(ev.id);
                      }}
                      icon={<Trash2 className="w-3.5 h-3.5" />}
                    />
                  </DaywellCard>
                );
              })}

              {selectedDayItems.tasks.map((occ) => {
                const badgeLabel =
                  occ.kind === 'due_and_scheduled'
                    ? 'Scheduled & Due'
                    : occ.kind === 'scheduled'
                    ? 'Scheduled Task'
                    : occ.kind === 'recurring_preview'
                    ? 'Upcoming Recurrence'
                    : 'Task Deadline';
                const badgeTone =
                  occ.kind === 'scheduled'
                    ? 'transfer'
                    : occ.kind === 'due'
                    ? 'warning'
                    : occ.kind === 'recurring_preview'
                    ? 'neutral'
                    : 'info';

                return (
                  <div
                    key={occ.id}
                    onClick={() => {
                      if (onNavigateToTask) {
                        onNavigateToTask(occ.sourceTaskId);
                      } else if (!occ.isProjectedOccurrence && onToggleTask) {
                        onToggleTask(occ.sourceTaskId);
                      }
                    }}
                    className={`p-2.5 rounded-[var(--dw-radius-lg)] flex items-center justify-between gap-3 cursor-pointer transition-all border ${
                      occ.isProjectedOccurrence
                        ? 'bg-[var(--dw-surface-subtle)] border-dashed border-[var(--dw-border)] hover:border-[var(--dw-primary)]/40'
                        : 'bg-[var(--dw-info-container)] border-[var(--dw-info)]/25 hover:border-[var(--dw-primary)]/45'
                    }`}
                  >
                    <div className="flex items-start gap-2.5 min-w-0 flex-1">
                      {occ.isProjectedOccurrence ? (
                        <span
                          aria-label={`Projected recurring occurrence for ${occ.task.title}`}
                          className="mt-0.5 text-[var(--dw-transfer)] shrink-0"
                        >
                          <Repeat className="w-4 h-4" />
                        </span>
                      ) : (
                        <button
                          type="button"
                          aria-label={
                            occ.completed
                              ? `Reopen ${occ.task.title}`
                              : `Complete ${occ.task.title}`
                          }
                          onClick={(e) => {
                            e.stopPropagation();
                            onToggleTask && onToggleTask(occ.sourceTaskId);
                          }}
                          className="mt-0.5 text-[var(--dw-info)] cursor-pointer shrink-0"
                        >
                          {occ.completed ? (
                            <CheckCircle2 className="w-4 h-4" />
                          ) : (
                            <Circle className="w-4 h-4" />
                          )}
                        </button>
                      )}
                      <div className="min-w-0 space-y-0.5">
                        <span
                          className={`text-xs font-semibold block truncate ${
                            occ.completed
                              ? 'line-through text-[var(--dw-text-disabled)]'
                              : occ.isProjectedOccurrence
                              ? 'text-[var(--dw-text-primary)]'
                              : 'text-[var(--dw-on-info-container)]'
                          }`}
                        >
                          {occ.task.title}
                        </span>
                        <div className="flex items-center flex-wrap gap-2 text-[10px] text-[var(--dw-text-secondary)]">
                          {occ.scheduledTime && (
                            <span className="inline-flex items-center gap-1 font-semibold">
                              <Clock className="w-2.5 h-2.5" />
                              {occ.scheduledTime}
                              {occ.estimatedDurationMinutes
                                ? ` · ${occ.estimatedDurationMinutes}m`
                                : ''}
                            </span>
                          )}
                          {occ.companionDueDate && (
                            <span>Due {occ.companionDueDate}</span>
                          )}
                          {occ.companionScheduledDate && (
                            <span>Scheduled {occ.companionScheduledDate}</span>
                          )}
                          {occ.task.projectName && (
                            <span className="text-[var(--dw-text-muted)]">
                              {occ.task.projectName}
                            </span>
                          )}
                          {occ.recurrenceSummary && (
                            <span className="inline-flex items-center gap-1">
                              <Repeat className="w-2.5 h-2.5 text-[var(--dw-info)]" />
                              {occ.recurrenceSummary}
                              {occ.isProjectedOccurrence &&
                              occ.isCompletionBasedRecurrence
                                ? ' (est.)'
                                : ''}
                            </span>
                          )}
                        </div>
                      </div>
                    </div>
                    <DaywellStatusBadge
                      tone={badgeTone}
                      showIcon={false}
                      label={badgeLabel}
                    />
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}

      {/* AGENDA VIEW */}
      {viewMode === 'agenda' && (
        <div className="space-y-3">
          <DaywellSearchField
            value={searchQuery}
            onChange={setSearchQuery}
            placeholder="Search upcoming events & tasks..."
            ariaLabel="Search upcoming events and tasks"
          />

          {agendaTimeline.length === 0 ? (
            <DaywellEmptyState
              icon={<CalendarIcon className="w-8 h-8" />}
              message="No upcoming events or scheduled tasks"
              subtitle="Create an event or assign due/scheduled dates to tasks to populate your 30-day agenda."
              actionLabel="Add Event"
              onActionPressed={handleOpenCreate}
            />
          ) : (
            <div className="space-y-2">
              {agendaTimeline.map((entry) => {
                if (entry.kind === 'event') {
                  const ev = entry.event;
                  const color = CATEGORY_COLORS[ev.category];
                  const parsedEvDate =
                    CalendarDate.tryParse(ev.date) ?? selectedCalendarDate;
                  const linkedNotesCount = countNotesLinkedToCalendarEvent(
                    effectiveNotes,
                    ev.id
                  );
                  return (
                    <DaywellCard
                      key={ev.id}
                      radius="lg"
                      padding="sm"
                      onClick={() => handleOpenEdit(ev)}
                      className="hover:border-[var(--dw-primary)]/40 flex items-center justify-between gap-3"
                    >
                      <div className="flex items-center gap-3 min-w-0">
                        <div className="text-center w-12 py-1 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] shrink-0">
                          <span className="block text-[9px] font-bold text-[var(--dw-text-muted)] uppercase">
                            {parsedEvDate.gregorianShortMonthName}
                          </span>
                          <span className="block text-sm font-extrabold text-[var(--dw-text-primary)]">
                            {parsedEvDate.day}
                          </span>
                        </div>
                        <div className="min-w-0">
                          <h4 className="text-xs font-bold text-[var(--dw-text-primary)] truncate">
                            {ev.title}
                          </h4>
                          <p className="text-[11px] text-[var(--dw-text-muted)] truncate flex items-center gap-2">
                            <span>
                              {ev.isAllDay
                                ? 'All Day'
                                : `${ev.startTime} – ${ev.endTime || ''}`}{' '}
                              {ev.location ? `· ${ev.location}` : ''}
                            </span>
                            {linkedNotesCount > 0 && (
                              <span className="inline-flex items-center gap-1 font-medium text-[var(--dw-primary)] shrink-0">
                                <NotebookPen className="w-3 h-3" />
                                {linkedNotesCount}{' '}
                                {linkedNotesCount === 1 ? 'note' : 'notes'}
                              </span>
                            )}
                          </p>
                        </div>
                      </div>
                      <span
                        className={`text-[10px] font-bold px-2 py-0.5 rounded-[var(--dw-radius-sm)] border shrink-0 ${color.badgeClass}`}
                      >
                        {color.label}
                      </span>
                    </DaywellCard>
                  );
                }

                const occ = entry.occurrence;
                const parsedTaskDate =
                  CalendarDate.tryParse(occ.occurrenceDate) ??
                  selectedCalendarDate;
                const agendaTaskBadge =
                  occ.kind === 'scheduled'
                    ? 'Scheduled Task'
                    : occ.kind === 'due_and_scheduled'
                    ? 'Scheduled & Due'
                    : occ.kind === 'recurring_preview'
                    ? 'Upcoming Recurrence'
                    : 'Task Deadline';

                return (
                  <DaywellCard
                    key={occ.id}
                    radius="lg"
                    padding="sm"
                    onClick={() => {
                      if (onNavigateToTask) {
                        onNavigateToTask(occ.sourceTaskId);
                      } else if (!occ.isProjectedOccurrence && onToggleTask) {
                        onToggleTask(occ.sourceTaskId);
                      }
                    }}
                    className={`flex items-center justify-between gap-3 ${
                      occ.isProjectedOccurrence
                        ? '!bg-[var(--dw-surface-subtle)] border-dashed'
                        : '!bg-[var(--dw-info-container)]/50'
                    }`}
                  >
                    <div className="flex items-center gap-3 min-w-0">
                      <div className="text-center w-12 py-1 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] shrink-0">
                        <span className="block text-[9px] font-bold text-[var(--dw-text-muted)] uppercase">
                          {parsedTaskDate.gregorianShortMonthName}
                        </span>
                        <span className="block text-sm font-extrabold text-[var(--dw-info)]">
                          {parsedTaskDate.day}
                        </span>
                      </div>
                      <div className="min-w-0">
                        <h4
                          className={`text-xs font-bold truncate ${
                            occ.completed
                              ? 'line-through text-[var(--dw-text-disabled)]'
                              : 'text-[var(--dw-text-primary)]'
                          }`}
                        >
                          {occ.task.title}
                        </h4>
                        <p className="text-[11px] text-[var(--dw-text-muted)] truncate">
                          {occ.scheduledTime ? `${occ.scheduledTime} · ` : ''}
                          {occ.recurrenceSummary
                            ? `${occ.recurrenceSummary} · `
                            : ''}
                          {occ.task.projectName || 'Task'}
                        </p>
                      </div>
                    </div>
                    <DaywellStatusBadge
                      tone={
                        occ.kind === 'recurring_preview'
                          ? 'neutral'
                          : occ.kind === 'scheduled'
                          ? 'transfer'
                          : 'info'
                      }
                      showIcon={false}
                      label={agendaTaskBadge}
                    />
                  </DaywellCard>
                );
              })}
            </div>
          )}
        </div>
      )}

      {/* CREATE / EDIT EVENT MODAL */}
      {isModalOpen && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={editingEventId ? 'Edit Event' : 'Add New Event'}
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs"
          onClick={(e) => {
            if (e.target === e.currentTarget) handleAttemptClose();
          }}
        >
          <div className="w-full max-w-md bg-[var(--dw-elevated)] rounded-[var(--dw-radius-xl)] p-5 shadow-2xl border border-[var(--dw-border)] space-y-4 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <h2 className="dw-type-title text-[var(--dw-text-primary)]">
                {editingEventId ? 'Edit Event' : 'Add New Event'}
              </h2>
              <DaywellIconButton
                label="Close event dialog"
                size="compact"
                tone="muted"
                onClick={handleAttemptClose}
                icon={<X className="w-4 h-4" />}
              />
            </div>

            <form onSubmit={handleSaveEvent} className="space-y-3.5">
              <div>
                <label className="block dw-type-caption uppercase tracking-wider text-[var(--dw-text-secondary)] mb-1">
                  Title <span className="text-[var(--dw-error)]">*</span>
                </label>
                <input
                  ref={titleInputRef}
                  type="text"
                  placeholder="e.g. CBE Loan Repayment Review"
                  value={formTitle}
                  onChange={(e) => {
                    setFormTitle(e.target.value);
                    if (formErrors.title) {
                      setFormErrors((prev) => ({ ...prev, title: '' }));
                    }
                  }}
                  className={`w-full min-h-[42px] px-3.5 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)] transition-colors ${
                    formErrors.title ? 'border-[var(--dw-error)]' : 'border-[var(--dw-border)]'
                  }`}
                />
                {formErrors.title && (
                  <p className="text-[11px] text-[var(--dw-error)] font-medium mt-1 flex items-center gap-1">
                    <AlertTriangle className="w-3 h-3 shrink-0" />
                    <span>{formErrors.title}</span>
                  </p>
                )}
              </div>

              <div>
                <label className="block dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)] mb-1">
                  Description / Agenda (Optional)
                </label>
                <textarea
                  rows={2}
                  placeholder="Notes, link, or meeting details..."
                  value={formDescription}
                  onChange={(e) => setFormDescription(e.target.value)}
                  className="w-full px-3.5 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                />
              </div>

              <div className="grid grid-cols-2 gap-2.5">
                <div>
                  <label className="block dw-type-caption uppercase tracking-wider text-[var(--dw-text-secondary)] mb-1">
                    Start Date <span className="text-[var(--dw-error)]">*</span>
                  </label>
                  <input
                    type="date"
                    value={formDate}
                    onChange={(e) => {
                      setFormDate(e.target.value);
                      if (formErrors.date) {
                        setFormErrors((prev) => ({ ...prev, date: '' }));
                      }
                    }}
                    className={`w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border text-xs text-[var(--dw-text-primary)] outline-none ${
                      formErrors.date ? 'border-[var(--dw-error)]' : 'border-[var(--dw-border)]'
                    }`}
                  />
                  {formErrors.date && (
                    <p className="text-[11px] text-[var(--dw-error)] font-medium mt-1">{formErrors.date}</p>
                  )}
                </div>

                <div>
                  <label className="block dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)] mb-1">
                    End Date (Optional)
                  </label>
                  <input
                    type="date"
                    value={formEndDate}
                    onChange={(e) => {
                      setFormEndDate(e.target.value);
                      if (formErrors.endDate) {
                        setFormErrors((prev) => ({ ...prev, endDate: '' }));
                      }
                    }}
                    className={`w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border text-xs text-[var(--dw-text-primary)] outline-none ${
                      formErrors.endDate ? 'border-[var(--dw-error)]' : 'border-[var(--dw-border)]'
                    }`}
                  />
                  {formErrors.endDate && (
                    <p className="text-[11px] text-[var(--dw-error)] font-medium mt-1">{formErrors.endDate}</p>
                  )}
                </div>
              </div>

              <div>
                <label className="block dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)] mb-1">
                  Category
                </label>
                <select
                  value={formCategory}
                  onChange={(e) => setFormCategory(e.target.value as CalendarEvent['category'])}
                  className="w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                >
                  <option value="personal">Personal</option>
                  <option value="work">Work</option>
                  <option value="finance">Finance</option>
                  <option value="health">Health</option>
                  <option value="family">Family</option>
                </select>
              </div>

              {/* All-Day Switch */}
              <label className="flex items-center justify-between p-2.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] cursor-pointer">
                <span className="text-xs font-semibold text-[var(--dw-text-secondary)]">All-Day Event</span>
                <input
                  type="checkbox"
                  checked={formIsAllDay}
                  onChange={(e) => {
                    setFormIsAllDay(e.target.checked);
                    if (formErrors.endTime || formErrors.startTime) {
                      setFormErrors((prev) => {
                        const copy = { ...prev };
                        delete copy.startTime;
                        delete copy.endTime;
                        return copy;
                      });
                    }
                  }}
                  className="w-4 h-4 accent-[var(--dw-primary)]"
                />
              </label>

              {!formIsAllDay && (
                <div className="grid grid-cols-2 gap-2.5">
                  <div>
                    <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                      Start Time
                    </label>
                    <input
                      type="time"
                      value={formStartTime}
                      onChange={(e) => {
                        setFormStartTime(e.target.value);
                        if (formErrors.startTime) {
                          setFormErrors((prev) => ({ ...prev, startTime: '' }));
                        }
                      }}
                      className="w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none"
                    />
                    {formErrors.startTime && (
                      <p className="text-[10px] text-[var(--dw-error)] mt-0.5">{formErrors.startTime}</p>
                    )}
                  </div>
                  <div>
                    <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                      End Time
                    </label>
                    <input
                      type="time"
                      value={formEndTime}
                      onChange={(e) => {
                        setFormEndTime(e.target.value);
                        if (formErrors.endTime) {
                          setFormErrors((prev) => ({ ...prev, endTime: '' }));
                        }
                      }}
                      className={`w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border text-xs text-[var(--dw-text-primary)] outline-none ${
                        formErrors.endTime ? 'border-[var(--dw-error)]' : 'border-[var(--dw-border)]'
                      }`}
                    />
                    {formErrors.endTime && (
                      <p className="text-[10px] text-[var(--dw-error)] mt-0.5">{formErrors.endTime}</p>
                    )}
                  </div>
                </div>
              )}

              <div className="grid grid-cols-2 gap-2.5">
                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Location / Link (Optional)
                  </label>
                  <input
                    type="text"
                    placeholder="e.g. Bole Medhanialem / Zoom"
                    value={formLocation}
                    onChange={(e) => setFormLocation(e.target.value)}
                    className="w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none"
                  />
                </div>
                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Repeat
                  </label>
                  <select
                    value={formRecurrence}
                    onChange={(e) => setFormRecurrence(e.target.value as CalendarEvent['recurrence'])}
                    className="w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none"
                  >
                    <option value="none">Does not repeat</option>
                    <option value="daily">Daily</option>
                    <option value="weekly">Weekly</option>
                    <option value="monthly">Monthly</option>
                    <option value="yearly">Yearly</option>
                  </select>
                </div>
              </div>

              {/* Actions */}
              <div className="flex items-center justify-between pt-2">
                {editingEventId ? (
                  <DaywellButton
                    label="Delete Event"
                    variant="text"
                    size="compact"
                    onClick={() => handleDeleteEvent(editingEventId)}
                    className="!text-[var(--dw-error)]"
                  />
                ) : (
                  <div />
                )}
                <div className="flex items-center gap-2">
                  <DaywellButton
                    label="Cancel"
                    variant="outlined"
                    size="compact"
                    onClick={handleAttemptClose}
                  />
                  <DaywellButton
                    type="submit"
                    variant="primary"
                    size="compact"
                    disabled={isSubmitting || !formTitle.trim()}
                    leadingIcon={isSubmitting ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : undefined}
                    label={editingEventId ? 'Save Changes' : 'Create Event'}
                  />
                </div>
              </div>
            </form>

            {editingEventId && (() => {
              const editingEvent =
                events.find((ev) => ev.id === editingEventId) ?? null;
              if (!editingEvent) return null;
              return (
                <div className="pt-2 border-t border-[var(--dw-divider)]">
                  <CalendarEventNotesSection
                    event={editingEvent}
                    notes={effectiveNotes}
                    tasks={tasks}
                    allEvents={events}
                    onOpenNote={
                      onNavigateToNote
                        ? (noteId) => {
                            setIsModalOpen(false);
                            setFormErrors({});
                            onNavigateToNote(noteId);
                          }
                        : undefined
                    }
                    onCreateNote={() => {
                      const res = createNoteForCalendarEvent<DaywellNote>({
                        notes: notesRef.current,
                        event: editingEvent,
                      });
                      if (!res.ok || !res.note) return;
                      applyNotesUpdate(res.notes);
                      if (onNavigateToNote) {
                        setIsModalOpen(false);
                        setFormErrors({});
                        onNavigateToNote(res.note.id);
                      } else {
                        triggerUndo(
                          `Created note "${res.note.title}"`,
                          () =>
                            applyNotesUpdate((prev) =>
                              prev.filter((n) => n.id !== res.note?.id)
                            )
                        );
                      }
                    }}
                    onLinkExistingNote={(noteId, options) => {
                      const eventId = editingEvent.id;
                      const res = linkNoteToCalendarEvent(
                        notesRef.current,
                        noteId,
                        eventId,
                        undefined,
                        options
                      );
                      if (!res.ok) {
                        return { ok: false, error: res.error };
                      }
                      const prevMod = res.previousLinkedModule;
                      const prevId = res.previousLinkedId;
                      applyNotesUpdate((cur) => {
                        const next = linkNoteToCalendarEvent(
                          cur,
                          noteId,
                          eventId,
                          undefined,
                          options
                        );
                        return next.ok ? next.notes : cur;
                      });
                      triggerUndo('Linked note to event', () => {
                        applyNotesUpdate((cur) => {
                          const previousTargetExists =
                            prevMod === 'tasks' && prevId
                              ? tasksRef.current.some((t) => t.id === prevId)
                              : prevMod === 'calendar' && prevId
                                ? eventsRef.current.some(
                                    (ev) => ev.id === prevId
                                  )
                                : undefined;
                          const undoRes = undoCalendarEventNoteLink({
                            notes: cur,
                            noteId,
                            appliedEventId: eventId,
                            previousLinkedModule: prevMod,
                            previousLinkedId: prevId,
                            previousTargetExists,
                          });
                          return undoRes.ok ? undoRes.notes : cur;
                        });
                      });
                      return { ok: true };
                    }}
                    onUnlinkNote={(noteId) => {
                      const eventId = editingEvent.id;
                      const res = unlinkNoteFromCalendarEvent(
                        notesRef.current,
                        noteId,
                        eventId
                      );
                      if (!res.ok) return;
                      applyNotesUpdate((cur) => {
                        const next = unlinkNoteFromCalendarEvent(
                          cur,
                          noteId,
                          eventId
                        );
                        return next.ok ? next.notes : cur;
                      });
                      triggerUndo('Unlinked note from event', () => {
                        applyNotesUpdate((cur) => {
                          if (!eventsRef.current.some((ev) => ev.id === eventId)) {
                            return cur;
                          }
                          const restored = linkNoteToCalendarEvent(
                            cur,
                            noteId,
                            eventId,
                            undefined,
                            { allowReassign: false }
                          );
                          return restored.ok ? restored.notes : cur;
                        });
                      });
                    }}
                  />
                </div>
              );
            })()}
          </div>
        </div>
      )}

      {/* Unsaved Changes Dialog */}
      <UnsavedChangesDialog
        isOpen={showUnsavedPrompt}
        onContinueEditing={() => setShowUnsavedPrompt(false)}
        onDiscardChanges={() => {
          setShowUnsavedPrompt(false);
          setIsModalOpen(false);
          setFormErrors({});
        }}
      />
    </div>
  );
}
