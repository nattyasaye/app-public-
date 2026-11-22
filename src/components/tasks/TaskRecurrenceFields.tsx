import React, { useEffect, useState } from 'react';
import { Calendar, FastForward, Pencil, Repeat2, XCircle } from 'lucide-react';
import { CalendarDate, SharedDateFormatter } from '../../domain/date';
import {
  SharedTaskRecurrenceConfig,
  SharedTaskRecurrenceFrequency,
  SharedTaskRecurrenceRepeatFrom,
} from '../../domain/sharedFoundation';
import { DaywellTaskRecord, isTaskCompleted } from '../../domain/taskOperations';
import {
  formatRecurrenceSummary,
  previewNextOccurrenceDate,
  resolveEffectiveRecurrenceConfig,
} from '../../domain/taskRecurrence';
import { DaywellButton } from '../ui';

const FREQUENCY_OPTIONS: readonly {
  value: SharedTaskRecurrenceFrequency;
  label: string;
  unitSingular: string;
  unitPlural: string;
}[] = [
  { value: 'daily', label: 'Daily', unitSingular: 'day', unitPlural: 'days' },
  { value: 'weekly', label: 'Weekly', unitSingular: 'week', unitPlural: 'weeks' },
  { value: 'monthly', label: 'Monthly', unitSingular: 'month', unitPlural: 'months' },
  { value: 'yearly', label: 'Yearly', unitSingular: 'year', unitPlural: 'years' },
];

const WEEKDAY_CHIPS: readonly { isoDay: number; label: string; full: string }[] = [
  { isoDay: 1, label: 'Mon', full: 'Monday' },
  { isoDay: 2, label: 'Tue', full: 'Tuesday' },
  { isoDay: 3, label: 'Wed', full: 'Wednesday' },
  { isoDay: 4, label: 'Thu', full: 'Thursday' },
  { isoDay: 5, label: 'Fri', full: 'Friday' },
  { isoDay: 6, label: 'Sat', full: 'Saturday' },
  { isoDay: 7, label: 'Sun', full: 'Sunday' },
];

export interface TaskRecurrenceEditorSectionProps {
  isRecurring: boolean;
  onToggleRecurring: (next: boolean) => void;
  frequency: SharedTaskRecurrenceFrequency;
  onChangeFrequency: (next: SharedTaskRecurrenceFrequency) => void;
  interval: number;
  onChangeInterval: (next: number) => void;
  weekdays: number[];
  onChangeWeekdays: (next: number[]) => void;
  startDate: string;
  onChangeStartDate: (next: string) => void;
  endDate: string;
  onChangeEndDate: (next: string) => void;
  repeatFrom: SharedTaskRecurrenceRepeatFrom;
  onChangeRepeatFrom: (next: SharedTaskRecurrenceRepeatFrom) => void;
  dueDate?: string;
  scheduledDate?: string;
  errors?: Record<string, string>;
  compact?: boolean;
}

export function TaskRecurrenceEditorSection({
  isRecurring,
  onToggleRecurring,
  frequency,
  onChangeFrequency,
  interval,
  onChangeInterval,
  weekdays,
  onChangeWeekdays,
  startDate,
  onChangeStartDate,
  endDate,
  onChangeEndDate,
  repeatFrom,
  onChangeRepeatFrom,
  dueDate,
  scheduledDate,
  errors,
  compact = false,
}: TaskRecurrenceEditorSectionProps) {
  const safeInterval = Number.isInteger(interval) && interval >= 1 ? interval : 1;
  const freqMeta =
    FREQUENCY_OPTIONS.find((f) => f.value === frequency) ?? FREQUENCY_OPTIONS[0];
  const unitLabel = safeInterval === 1 ? freqMeta.unitSingular : freqMeta.unitPlural;

  const draftConfig: SharedTaskRecurrenceConfig = {
    frequency,
    interval: safeInterval,
    ...(frequency === 'weekly' && weekdays.length > 0 ? { weekdays } : {}),
    ...(startDate.trim() ? { startDate: startDate.trim() } : {}),
    ...(endDate.trim() ? { endDate: endDate.trim() } : {}),
    repeatFrom,
  };

  const summary = formatRecurrenceSummary(draftConfig);
  const nextPreviewIso = isRecurring
    ? previewNextOccurrenceDate(
        { dueDate: dueDate?.trim() || undefined, scheduledDate: scheduledDate?.trim() || undefined },
        draftConfig
      )
    : null;
  const parsedNextPreview = nextPreviewIso
    ? CalendarDate.tryParse(nextPreviewIso)
    : null;

  const toggleWeekday = (isoDay: number) => {
    const exists = weekdays.includes(isoDay);
    const updated = exists
      ? weekdays.filter((d) => d !== isoDay)
      : [...weekdays, isoDay].sort((a, b) => a - b);
    onChangeWeekdays(updated);
  };

  return (
    <div className="space-y-2.5 p-3 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)]">
      <div className="flex items-center justify-between gap-2">
        <label className="flex items-center gap-2 cursor-pointer">
          <input
            aria-label="Repeat task"
            type="checkbox"
            checked={isRecurring}
            onChange={(e) => onToggleRecurring(e.target.checked)}
            className="w-4 h-4 accent-[var(--dw-primary)]"
          />
          <Repeat2 className="w-3.5 h-3.5 text-[var(--dw-primary)]" />
          <span className="text-xs font-semibold text-[var(--dw-text-primary)]">
            Recurring Task
          </span>
        </label>
        {isRecurring && summary && (
          <span className="text-[11px] font-semibold text-[var(--dw-primary)]">
            {summary}
          </span>
        )}
      </div>

      {isRecurring && (
        <div className="space-y-2.5 pt-1 border-t border-[var(--dw-divider)]">
          {/* Frequency & Every N Interval */}
          <div className={compact ? 'grid grid-cols-1 gap-2' : 'grid grid-cols-2 gap-2'}>
            <div>
              <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                Frequency
              </label>
              <select
                aria-label="Recurrence frequency"
                value={frequency}
                onChange={(e) =>
                  onChangeFrequency(e.target.value as SharedTaskRecurrenceFrequency)
                }
                className="w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-card)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs font-medium text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
              >
                {FREQUENCY_OPTIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                Every ({unitLabel})
              </label>
              <input
                aria-label="Recurrence interval"
                type="number"
                min={1}
                step={1}
                value={safeInterval}
                onChange={(e) => {
                  const parsed = parseInt(e.target.value, 10);
                  onChangeInterval(
                    Number.isFinite(parsed) && parsed >= 1 ? parsed : 1
                  );
                }}
                className={`w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-card)] rounded-[var(--dw-radius-md)] border text-xs font-medium text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)] ${
                  errors?.recurrenceInterval
                    ? 'border-[var(--dw-error)]'
                    : 'border-[var(--dw-border)]'
                }`}
              />
              {errors?.recurrenceInterval && (
                <p className="text-[11px] text-[var(--dw-error)] mt-0.5">
                  {errors.recurrenceInterval}
                </p>
              )}
            </div>
          </div>

          {/* Weekly Weekday Selector */}
          {frequency === 'weekly' && (
            <div>
              <span className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                Repeat On Days (Optional)
              </span>
              <div className="flex flex-wrap gap-1.5">
                {WEEKDAY_CHIPS.map((day) => {
                  const active = weekdays.includes(day.isoDay);
                  return (
                    <button
                      key={day.isoDay}
                      type="button"
                      aria-label={`Repeat on ${day.full}`}
                      aria-pressed={active}
                      onClick={() => toggleWeekday(day.isoDay)}
                      className={`min-h-[32px] px-2.5 py-1 rounded-[var(--dw-radius-full)] border text-[11px] font-semibold transition-colors cursor-pointer ${
                        active
                          ? 'bg-[var(--dw-primary-container)] border-[var(--dw-primary)] text-[var(--dw-on-primary-container)]'
                          : 'bg-[var(--dw-card)] border-[var(--dw-border)] text-[var(--dw-text-secondary)] hover:border-[var(--dw-primary)]'
                      }`}
                    >
                      {day.label}
                    </button>
                  );
                })}
              </div>
              {errors?.recurrenceWeekdays && (
                <p className="text-[11px] text-[var(--dw-error)] mt-0.5">
                  {errors.recurrenceWeekdays}
                </p>
              )}
            </div>
          )}

          {/* Start & Optional End Date */}
          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                Start Date
              </label>
              <input
                aria-label="Recurrence start date"
                type="date"
                value={startDate}
                onChange={(e) => onChangeStartDate(e.target.value)}
                className={`w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-card)] rounded-[var(--dw-radius-md)] border text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)] ${
                  errors?.recurrenceStartDate
                    ? 'border-[var(--dw-error)]'
                    : 'border-[var(--dw-border)]'
                }`}
              />
              {errors?.recurrenceStartDate && (
                <p className="text-[11px] text-[var(--dw-error)] mt-0.5">
                  {errors.recurrenceStartDate}
                </p>
              )}
            </div>

            <div>
              <div className="flex items-center justify-between mb-1">
                <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)]">
                  End Date (Optional)
                </label>
                {endDate && (
                  <button
                    type="button"
                    onClick={() => onChangeEndDate('')}
                    className="text-[10px] font-semibold text-[var(--dw-primary)] hover:underline cursor-pointer"
                  >
                    Clear
                  </button>
                )}
              </div>
              <input
                aria-label="Recurrence end date"
                type="date"
                value={endDate}
                onChange={(e) => onChangeEndDate(e.target.value)}
                className={`w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-card)] rounded-[var(--dw-radius-md)] border text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)] ${
                  errors?.recurrenceEndDate
                    ? 'border-[var(--dw-error)]'
                    : 'border-[var(--dw-border)]'
                }`}
              />
              {errors?.recurrenceEndDate && (
                <p className="text-[11px] text-[var(--dw-error)] mt-0.5">
                  {errors.recurrenceEndDate}
                </p>
              )}
            </div>
          </div>

          {/* Repeat Based On */}
          <div>
            <span className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
              Repeat Based On
            </span>
            <div className="grid grid-cols-2 gap-1.5">
              {(
                [
                  { value: 'due_date', label: 'Due Date' },
                  { value: 'completion_date', label: 'Completion Date' },
                ] as const
              ).map((mode) => {
                const active = repeatFrom === mode.value;
                return (
                  <button
                    key={mode.value}
                    type="button"
                    aria-pressed={active}
                    onClick={() => onChangeRepeatFrom(mode.value)}
                    className={`min-h-[36px] px-2.5 py-1.5 rounded-[var(--dw-radius-md)] border text-[11px] font-semibold transition-colors cursor-pointer ${
                      active
                        ? 'bg-[var(--dw-primary-container)] border-[var(--dw-primary)] text-[var(--dw-on-primary-container)]'
                        : 'bg-[var(--dw-card)] border-[var(--dw-border)] text-[var(--dw-text-secondary)] hover:border-[var(--dw-primary)]'
                    }`}
                  >
                    {mode.label}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Live Next Occurrence Preview */}
          <div className="flex items-center justify-between gap-2 px-2.5 py-1.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-card)] border border-[var(--dw-border)] text-[11px]">
            <span className="text-[var(--dw-text-muted)]">Next occurrence</span>
            <span className="font-semibold text-[var(--dw-text-primary)] text-right">
              {parsedNextPreview
                ? SharedDateFormatter.formatDual(parsedNextPreview, false)
                : nextPreviewIso || 'No further occurrence (past end date)'}
            </span>
          </div>
        </div>
      )}
    </div>
  );
}

export interface TaskRecurrenceDetailsPanelProps {
  task: DaywellTaskRecord;
  onSkipOccurrence?: () => void;
  onRescheduleOccurrence?: (newDateIso: string) => void;
  onEditRecurrence?: () => void;
  onStopRecurrence?: () => void;
  actionError?: string;
}

export function TaskRecurrenceDetailsPanel({
  task,
  onSkipOccurrence,
  onRescheduleOccurrence,
  onEditRecurrence,
  onStopRecurrence,
  actionError,
}: TaskRecurrenceDetailsPanelProps) {
  const effectiveConfig = resolveEffectiveRecurrenceConfig(task);
  const completed = isTaskCompleted(task);
  const currentAnchor =
    task.dueDate || task.scheduledDate || CalendarDate.today().toIsoString();
  const [isRescheduling, setIsRescheduling] = useState(false);
  const [rescheduleDate, setRescheduleDate] = useState(currentAnchor);

  useEffect(() => {
    setRescheduleDate(
      task.dueDate || task.scheduledDate || CalendarDate.today().toIsoString()
    );
    setIsRescheduling(false);
  }, [task.id, task.dueDate, task.scheduledDate]);

  if (!effectiveConfig) return null;

  const summary = formatRecurrenceSummary(effectiveConfig);
  const nextIso = previewNextOccurrenceDate(task, effectiveConfig);
  const parsedNext = nextIso ? CalendarDate.tryParse(nextIso) : null;
  const parsedStart = effectiveConfig.startDate
    ? CalendarDate.tryParse(effectiveConfig.startDate)
    : null;
  const parsedEnd = effectiveConfig.endDate
    ? CalendarDate.tryParse(effectiveConfig.endDate)
    : null;

  return (
    <div className="space-y-2.5 p-3 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)]">
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-1.5">
          <Repeat2 className="w-3.5 h-3.5 text-[var(--dw-primary)]" />
          <span className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-secondary)]">
            Recurrence Series
          </span>
        </div>
        <span className="text-[11px] font-bold text-[var(--dw-primary)]">
          {summary}
        </span>
      </div>

      <div className="space-y-1.5 text-xs">
        <div className="flex items-center justify-between gap-2">
          <span className="text-[var(--dw-text-muted)]">Repeat From</span>
          <span className="font-semibold text-[var(--dw-text-primary)]">
            {effectiveConfig.repeatFrom === 'completion_date'
              ? 'Completion date'
              : 'Due date'}
          </span>
        </div>
        {effectiveConfig.startDate && (
          <div className="flex items-center justify-between gap-2">
            <span className="text-[var(--dw-text-muted)]">Starts</span>
            <span className="font-medium text-[var(--dw-text-secondary)]">
              {parsedStart
                ? SharedDateFormatter.formatDual(parsedStart, false)
                : effectiveConfig.startDate}
            </span>
          </div>
        )}
        {effectiveConfig.endDate && (
          <div className="flex items-center justify-between gap-2">
            <span className="text-[var(--dw-text-muted)]">Ends</span>
            <span className="font-medium text-[var(--dw-text-secondary)]">
              {parsedEnd
                ? SharedDateFormatter.formatDual(parsedEnd, false)
                : effectiveConfig.endDate}
            </span>
          </div>
        )}
        <div className="flex items-center justify-between gap-2">
          <span className="text-[var(--dw-text-muted)]">Next Occurrence</span>
          <span className="font-semibold text-[var(--dw-text-primary)] text-right">
            {parsedNext
              ? SharedDateFormatter.formatDual(parsedNext, false)
              : nextIso || 'Ends after current occurrence'}
          </span>
        </div>
      </div>

      {actionError && (
        <p className="text-[11px] text-[var(--dw-error)] font-medium">
          {actionError}
        </p>
      )}

      {!task.isArchived && (
        <div className="space-y-2 pt-1 border-t border-[var(--dw-divider)]">
          <div className="flex flex-wrap gap-1.5">
            {!completed && onSkipOccurrence && (
              <DaywellButton
                label="Skip Occurrence"
                variant="outlined"
                size="compact"
                leadingIcon={<FastForward className="w-3.5 h-3.5" />}
                onClick={onSkipOccurrence}
              />
            )}
            {!completed && onRescheduleOccurrence && (
              <DaywellButton
                label="Reschedule"
                variant="outlined"
                size="compact"
                leadingIcon={<Calendar className="w-3.5 h-3.5" />}
                onClick={() => setIsRescheduling((v) => !v)}
              />
            )}
            {onEditRecurrence && (
              <DaywellButton
                label="Edit Schedule"
                variant="outlined"
                size="compact"
                leadingIcon={<Pencil className="w-3.5 h-3.5" />}
                onClick={onEditRecurrence}
              />
            )}
            {onStopRecurrence && (
              <DaywellButton
                label="Stop Recurrence"
                variant="text"
                size="compact"
                leadingIcon={<XCircle className="w-3.5 h-3.5" />}
                onClick={onStopRecurrence}
                className="!text-[var(--dw-error)]"
              />
            )}
          </div>

          {!completed && isRescheduling && onRescheduleOccurrence && (
            <div className="flex items-center gap-2 pt-1">
              <input
                aria-label="Reschedule recurring occurrence date"
                type="date"
                value={rescheduleDate}
                onChange={(e) => setRescheduleDate(e.target.value)}
                className="flex-1 min-h-[36px] px-2.5 py-1 bg-[var(--dw-card)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
              />
              <DaywellButton
                label="Apply"
                variant="primary"
                size="compact"
                onClick={() => {
                  onRescheduleOccurrence(rescheduleDate);
                  setIsRescheduling(false);
                }}
              />
            </div>
          )}
        </div>
      )}
    </div>
  );
}
