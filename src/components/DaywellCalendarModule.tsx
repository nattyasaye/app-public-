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
} from 'lucide-react';
import {
  CalendarDate,
  DateRange,
  SharedDateFormatter,
} from '../domain/date';
import { SHARED_DESIGN_TOKENS } from '../domain/sharedFoundation';
import { validateCalendarEventForm, isFormDirty } from '../domain/formValidationAndNavigation';
import { UnsavedChangesDialog } from './UnsavedChangesDialog';
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
  completed: boolean;
  priority?: 'urgent' | 'high' | 'medium' | 'low';
  recurrenceSummary?: string;
}

interface DaywellCalendarModuleProps {
  tasks?: CalendarTaskRef[];
  onToggleTask?: (taskId: string) => void;
  onNavigateToTask?: (taskId: string) => void;
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

export function DaywellCalendarModule({
  tasks = [],
  onToggleTask,
}: DaywellCalendarModuleProps) {
  const [viewMode, setViewMode] = useState<'month' | 'week' | 'day' | 'agenda'>('month');
  const [currentDate, setCurrentDate] = useState<CalendarDate>(() => CalendarDate.today());
  const [selectedDateStr, setSelectedDateStr] = useState<string>(() => CalendarDate.today().toIsoString());

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

  const monthDays = useMemo(() => {
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

    return gridDates.map(({ date, isCurrentMonth }) => {
      const dateStr = date.toIsoString();
      const eth = date.toEthiopian();
      const dayEvents = events.filter((e) => eventOccursOnDate(e, date));
      const dayTasks = tasks.filter((t) => t.dueDate === dateStr);
      return {
        dateStr,
        dayNumber: date.day,
        isCurrentMonth,
        ethiopian: eth,
        hasEvents: dayEvents.length > 0,
        hasTasks: dayTasks.length > 0,
        eventCount: dayEvents.length + dayTasks.length,
      };
    });
  }, [currentDate, events, tasks]);

  const selectedDayItems = useMemo(() => {
    let dayEvents = events.filter((e) => eventOccursOnDate(e, selectedCalendarDate));
    let dayTasks = tasks.filter((t) => t.dueDate === selectedDateStr);

    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      dayEvents = dayEvents.filter(
        (e) => e.title.toLowerCase().includes(q) || (e.description && e.description.toLowerCase().includes(q))
      );
      dayTasks = dayTasks.filter((t) => t.title.toLowerCase().includes(q));
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
  }, [events, tasks, selectedCalendarDate, selectedDateStr, searchQuery, categoryFilter]);

  const agendaList = useMemo(() => {
    let filtered = [...events];
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      filtered = filtered.filter(
        (e) => e.title.toLowerCase().includes(q) || (e.description && e.description.toLowerCase().includes(q))
      );
    }
    if (categoryFilter !== 'all') {
      filtered = filtered.filter((e) => e.category === categoryFilter);
    }
    filtered.sort((a, b) => a.date.localeCompare(b.date) || (a.startTime || '').localeCompare(b.startTime || ''));
    return filtered;
  }, [events, searchQuery, categoryFilter]);

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
      setEvents(updated);
      setIsSubmitting(false);
      setIsModalOpen(false);
      setFormErrors({});
      triggerUndo('Event updated', () => setEvents(previousEvents));
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
      setEvents([newEvent, ...events]);
      setSelectedDateStr(formDate);
      setIsSubmitting(false);
      setIsModalOpen(false);
      setFormErrors({});
      triggerUndo(`Added "${newEvent.title}"`, () => setEvents(previousEvents));
    }
  };

  const handleDeleteEvent = (id: string) => {
    const previous = [...events];
    const target = events.find((e) => e.id === id);
    setEvents(events.filter((e) => e.id !== id));
    setIsModalOpen(false);
    triggerUndo(`Deleted "${target?.title || 'event'}"`, () => setEvents(previous));
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

              return (
                <button
                  key={d.dateStr}
                  type="button"
                  onClick={() => setSelectedDateStr(d.dateStr)}
                  className={`min-h-[52px] p-1 rounded-[var(--dw-radius-md)] flex flex-col items-center justify-between transition-all relative cursor-pointer ${
                    currentSelected
                      ? 'bg-[var(--dw-primary)] text-[var(--dw-on-primary)] shadow-sm ring-2 ring-[var(--dw-primary)]/30'
                      : todayCell
                      ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] font-bold'
                      : d.isCurrentMonth
                      ? 'hover:bg-[var(--dw-surface-subtle)] text-[var(--dw-text-primary)]'
                      : 'text-[var(--dw-text-disabled)]'
                  }`}
                >
                  <span className="text-xs font-bold">
                    {d.dayNumber}
                  </span>

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
                    {d.hasTasks && (
                      <span
                        className={`w-1.5 h-1.5 rounded-full ${
                          currentSelected ? 'bg-current' : 'bg-[var(--dw-info)]'
                        }`}
                      />
                    )}
                  </div>
                </button>
              );
            })}
          </div>
        </DaywellCard>
      )}

      {/* DAY VIEW & SELECTED AGENDA DETAILS */}
      {(viewMode === 'month' || viewMode === 'day') && (
        <div className="space-y-3 pt-1">
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
                return (
                  <DaywellCard
                    key={ev.id}
                    radius="lg"
                    padding="sm"
                    onClick={() => handleOpenEdit(ev)}
                    className="hover:border-[var(--dw-primary)]/40 flex items-start justify-between gap-3 group"
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

              {selectedDayItems.tasks.map((task) => (
                <div
                  key={task.id}
                  onClick={() => onToggleTask && onToggleTask(task.id)}
                  className="p-2.5 bg-[var(--dw-info-container)] rounded-[var(--dw-radius-lg)] border border-[var(--dw-info)]/25 flex items-center justify-between gap-3 cursor-pointer transition-all"
                >
                  <div className="flex items-center gap-2.5">
                    <button
                      type="button"
                      aria-label={task.completed ? `Reopen ${task.title}` : `Complete ${task.title}`}
                      onClick={(e) => {
                        e.stopPropagation();
                        onToggleTask && onToggleTask(task.id);
                      }}
                      className="text-[var(--dw-info)] cursor-pointer"
                    >
                      {task.completed ? (
                        <CheckCircle2 className="w-4 h-4" />
                      ) : (
                        <Circle className="w-4 h-4" />
                      )}
                    </button>
                    <div className="min-w-0">
                      <span
                        className={`text-xs font-semibold block truncate ${
                          task.completed ? 'line-through text-[var(--dw-text-disabled)]' : 'text-[var(--dw-on-info-container)]'
                        }`}
                      >
                        {task.title}
                      </span>
                      {task.recurrenceSummary && (
                        <span className="inline-flex items-center gap-1 text-[10px] text-[var(--dw-text-secondary)]">
                          <Repeat className="w-2.5 h-2.5 text-[var(--dw-info)]" />
                          {task.recurrenceSummary}
                        </span>
                      )}
                    </div>
                  </div>
                  <DaywellStatusBadge tone="info" showIcon={false} label="Task Deadline" />
                </div>
              ))}
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
            placeholder="Search all upcoming events..."
            ariaLabel="Search all upcoming events"
          />

          <div className="space-y-2">
            {agendaList.map((ev) => {
              const color = CATEGORY_COLORS[ev.category];
              return (
                <DaywellCard
                  key={ev.id}
                  radius="lg"
                  padding="sm"
                  onClick={() => handleOpenEdit(ev)}
                  className="hover:border-[var(--dw-primary)]/40 flex items-center justify-between gap-3"
                >
                  <div className="flex items-center gap-3">
                    <div className="text-center w-12 py-1 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] shrink-0">
                      <span className="block text-[9px] font-bold text-[var(--dw-text-muted)] uppercase">
                        {(CalendarDate.tryParse(ev.date) ?? selectedCalendarDate).gregorianShortMonthName}
                      </span>
                      <span className="block text-sm font-extrabold text-[var(--dw-text-primary)]">
                        {(CalendarDate.tryParse(ev.date) ?? selectedCalendarDate).day}
                      </span>
                    </div>
                    <div>
                      <h4 className="text-xs font-bold text-[var(--dw-text-primary)]">{ev.title}</h4>
                      <p className="text-[11px] text-[var(--dw-text-muted)]">
                        {ev.isAllDay ? 'All Day' : `${ev.startTime} – ${ev.endTime || ''}`} {ev.location ? `· ${ev.location}` : ''}
                      </p>
                    </div>
                  </div>
                  <span className={`text-[10px] font-bold px-2 py-0.5 rounded-[var(--dw-radius-sm)] border ${color.badgeClass}`}>
                    {color.label}
                  </span>
                </DaywellCard>
              );
            })}
          </div>
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
