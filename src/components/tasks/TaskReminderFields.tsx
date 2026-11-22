import React, { useEffect, useState } from 'react';
import { Bell, BellOff, Clock, Pencil } from 'lucide-react';
import { CalendarDate, SharedDateFormatter } from '../../domain/date';
import { SharedReminder } from '../../domain/sharedFoundation';
import { DaywellTaskRecord, isTaskCompleted } from '../../domain/taskOperations';
import {
  TASK_REMINDER_PRESET_LABELS,
  TaskReminderPreset,
  computeTaskReminderTriggerFromPreset,
  defaultFallbackReminderDateTime,
  formatTaskReminderSummary,
  inferTaskReminderPreset,
  resolveTaskReminderAnchor,
  utcIsoToEthiopiaWallDateTime,
} from '../../domain/taskReminders';
import { taskRemindersService } from '../../services/taskRemindersService';
import { DaywellButton, DaywellStatusBadge } from '../ui';

const PRESET_OPTIONS: readonly {
  value: TaskReminderPreset;
  shortLabel: string;
}[] = [
  { value: 'at_time', shortLabel: 'At time' },
  { value: '15m_before', shortLabel: '15m before' },
  { value: '1h_before', shortLabel: '1h before' },
  { value: '1d_before', shortLabel: '1d before' },
  { value: 'custom', shortLabel: 'Custom' },
];

function describeAnchor(
  dueDate?: string,
  scheduledDate?: string,
  scheduledTime?: string
): string {
  const anchor = resolveTaskReminderAnchor({
    dueDate,
    scheduledDate,
    scheduledTime,
  });
  if (!anchor) {
    return 'No scheduled or due date set — defaults to next 09:00 EAT';
  }
  if (anchor.source === 'scheduled') {
    return anchor.hasExplicitTime
      ? `Anchored to scheduled time (${anchor.time} EAT)`
      : `Anchored to scheduled date · ${anchor.time} EAT default`;
  }
  return anchor.hasExplicitTime
    ? `Anchored to due date · ${anchor.time} EAT`
    : 'Anchored to due date · 09:00 EAT default';
}

export interface TaskReminderEditorSectionProps {
  enabled: boolean;
  onToggle: (next: boolean) => void;
  preset: TaskReminderPreset;
  onChangePreset: (next: TaskReminderPreset) => void;
  customDate: string;
  onChangeCustomDate: (next: string) => void;
  customTime: string;
  onChangeCustomTime: (next: string) => void;
  dueDate?: string;
  scheduledDate?: string;
  scheduledTime?: string;
  error?: string;
  compact?: boolean;
}

export function TaskReminderEditorSection({
  enabled,
  onToggle,
  preset,
  onChangePreset,
  customDate,
  onChangeCustomDate,
  customTime,
  onChangeCustomTime,
  dueDate,
  scheduledDate,
  scheduledTime,
  error,
  compact = false,
}: TaskReminderEditorSectionProps) {
  const [supportStatus, setSupportStatus] = useState(() =>
    taskRemindersService.getWebNotificationSupportStatus()
  );

  const taskProbe = {
    dueDate: dueDate?.trim() || undefined,
    scheduledDate: scheduledDate?.trim() || undefined,
    scheduledTime: scheduledTime?.trim() || undefined,
  };

  const previewResult = enabled
    ? computeTaskReminderTriggerFromPreset({
        task: taskProbe,
        preset,
        customDateIso: customDate,
        customTime,
      })
    : null;

  const summary =
    previewResult?.ok && previewResult.triggerTimeUtc
      ? formatTaskReminderSummary(previewResult.triggerTimeUtc)
      : undefined;

  const anchorDescription = describeAnchor(dueDate, scheduledDate, scheduledTime);
  const validationMessage =
    error || (enabled && previewResult && !previewResult.ok ? previewResult.error : undefined);

  const handleSelectPreset = (nextPreset: TaskReminderPreset) => {
    if (nextPreset === 'custom' && (!customDate.trim() || !customTime.trim())) {
      const anchor = resolveTaskReminderAnchor(taskProbe);
      const fallback = defaultFallbackReminderDateTime();
      if (!customDate.trim()) {
        onChangeCustomDate(anchor?.dateIso ?? fallback.dateIso);
      }
      if (!customTime.trim()) {
        onChangeCustomTime(anchor?.time ?? fallback.time);
      }
    }
    onChangePreset(nextPreset);
  };

  const handleRequestBrowserPermission = async () => {
    await taskRemindersService.requestWebNotificationPermission();
    setSupportStatus(taskRemindersService.getWebNotificationSupportStatus());
  };

  return (
    <div className="space-y-2.5 p-3 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)]">
      <div className="flex items-center justify-between gap-2">
        <label className="flex items-center gap-2 cursor-pointer">
          <input
            aria-label="Set task reminder"
            type="checkbox"
            checked={enabled}
            onChange={(e) => onToggle(e.target.checked)}
            className="w-4 h-4 accent-[var(--dw-primary)]"
          />
          <Bell className="w-3.5 h-3.5 text-[var(--dw-primary)]" />
          <span className="text-xs font-semibold text-[var(--dw-text-primary)]">
            Task Reminder
          </span>
        </label>
        {enabled && summary && (
          <span className="text-[11px] font-semibold text-[var(--dw-primary)] text-right">
            {summary}
          </span>
        )}
      </div>

      {enabled && (
        <div className="space-y-2.5 pt-1 border-t border-[var(--dw-divider)]">
          <div>
            <span className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
              Reminder Timing
            </span>
            <div className="flex flex-wrap gap-1.5">
              {PRESET_OPTIONS.map((opt) => {
                const active = preset === opt.value;
                return (
                  <button
                    key={opt.value}
                    type="button"
                    aria-pressed={active}
                    onClick={() => handleSelectPreset(opt.value)}
                    className={`min-h-[32px] px-2.5 py-1 rounded-[var(--dw-radius-full)] border text-[11px] font-semibold transition-colors cursor-pointer ${
                      active
                        ? 'bg-[var(--dw-primary-container)] border-[var(--dw-primary)] text-[var(--dw-on-primary-container)]'
                        : 'bg-[var(--dw-card)] border-[var(--dw-border)] text-[var(--dw-text-secondary)] hover:border-[var(--dw-primary)]'
                    }`}
                  >
                    {opt.shortLabel}
                  </button>
                );
              })}
            </div>
          </div>

          {preset === 'custom' ? (
            <div className={compact ? 'grid grid-cols-1 gap-2' : 'grid grid-cols-2 gap-2'}>
              <div>
                <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                  Reminder Date
                </label>
                <input
                  aria-label="Custom reminder date"
                  type="date"
                  value={customDate}
                  onChange={(e) => onChangeCustomDate(e.target.value)}
                  className="w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-card)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                />
              </div>
              <div>
                <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                  Reminder Time (EAT)
                </label>
                <input
                  aria-label="Custom reminder time"
                  type="time"
                  value={customTime}
                  onChange={(e) => onChangeCustomTime(e.target.value)}
                  className="w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-card)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                />
              </div>
            </div>
          ) : (
            <p className="text-[11px] text-[var(--dw-text-secondary)]">
              {anchorDescription}
            </p>
          )}

          {validationMessage && (
            <p className="text-[11px] text-[var(--dw-error)] font-medium">
              {validationMessage}
            </p>
          )}

          <div className="flex items-center justify-between gap-2 px-2.5 py-1.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-card)] border border-[var(--dw-border)] text-[11px]">
            <span className="text-[var(--dw-text-muted)] inline-flex items-center gap-1">
              <Clock className="w-3 h-3" />
              Fires at
            </span>
            <span className="font-semibold text-[var(--dw-text-primary)] text-right">
              {summary ?? 'Select valid date and time'}
            </span>
          </div>

          <div className="flex flex-wrap items-center justify-between gap-2 text-[10px] text-[var(--dw-text-muted)]">
            <span className="flex-1 min-w-[180px] leading-relaxed">
              {supportStatus.capabilityNote}
            </span>
            {supportStatus.supported && supportStatus.permission === 'default' && (
              <DaywellButton
                label="Enable Browser Alerts"
                variant="outlined"
                size="compact"
                onClick={() => void handleRequestBrowserPermission()}
              />
            )}
          </div>
        </div>
      )}
    </div>
  );
}

export interface TaskReminderDetailsPanelProps {
  task: DaywellTaskRecord;
  reminder?: SharedReminder;
  onSaveReminder: (triggerTimeUtc: string) => void;
  onRemoveReminder: () => void;
  compact?: boolean;
}

export function TaskReminderDetailsPanel({
  task,
  reminder,
  onSaveReminder,
  onRemoveReminder,
  compact = false,
}: TaskReminderDetailsPanelProps) {
  const [isEditing, setIsEditing] = useState(false);
  const [preset, setPreset] = useState<TaskReminderPreset>('at_time');
  const [customDate, setCustomDate] = useState('');
  const [customTime, setCustomTime] = useState('');
  const [formError, setFormError] = useState<string | undefined>();

  useEffect(() => {
    setIsEditing(false);
    setFormError(undefined);
    if (reminder) {
      setPreset(inferTaskReminderPreset(task, reminder.triggerTimeUtc));
      const wall = utcIsoToEthiopiaWallDateTime(reminder.triggerTimeUtc);
      if (wall) {
        setCustomDate(wall.dateIso);
        setCustomTime(wall.time);
      }
    } else {
      const anchor = resolveTaskReminderAnchor(task);
      const fallback = defaultFallbackReminderDateTime();
      setPreset('at_time');
      setCustomDate(anchor?.dateIso ?? fallback.dateIso);
      setCustomTime(anchor?.time ?? fallback.time);
    }
  }, [
    task.id,
    task.dueDate,
    task.scheduledDate,
    task.scheduledTime,
    reminder?.triggerTimeUtc,
    reminder?.isActive,
  ]);

  const completed = isTaskCompleted(task);
  const inactiveReason = task.isArchived
    ? 'Paused (Archived)'
    : completed
    ? 'Paused (Completed)'
    : task.status === 'cancelled'
    ? 'Paused (Cancelled)'
    : 'Paused';

  const triggerWall = reminder
    ? utcIsoToEthiopiaWallDateTime(reminder.triggerTimeUtc)
    : null;
  const dualDateLabel = triggerWall
    ? SharedDateFormatter.formatDual(triggerWall.date, false)
    : undefined;
  const inferredPreset = reminder
    ? inferTaskReminderPreset(task, reminder.triggerTimeUtc)
    : 'at_time';

  const handleOpenEditor = () => {
    if (reminder) {
      setPreset(inferTaskReminderPreset(task, reminder.triggerTimeUtc));
      const wall = utcIsoToEthiopiaWallDateTime(reminder.triggerTimeUtc);
      if (wall) {
        setCustomDate(wall.dateIso);
        setCustomTime(wall.time);
      }
    } else {
      const anchor = resolveTaskReminderAnchor(task);
      const fallback = defaultFallbackReminderDateTime();
      setPreset('at_time');
      setCustomDate(anchor?.dateIso ?? fallback.dateIso);
      setCustomTime(anchor?.time ?? fallback.time);
    }
    setFormError(undefined);
    setIsEditing(true);
  };

  const handleApply = () => {
    const res = computeTaskReminderTriggerFromPreset({
      task,
      preset,
      customDateIso: customDate,
      customTime,
    });
    if (!res.ok || !res.triggerTimeUtc) {
      setFormError(res.error ?? 'Choose a valid reminder time.');
      return;
    }
    setFormError(undefined);
    setIsEditing(false);
    onSaveReminder(res.triggerTimeUtc);
  };

  return (
    <div className="space-y-2.5 p-3 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)]">
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-1.5">
          <Bell className="w-3.5 h-3.5 text-[var(--dw-primary)]" />
          <span className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-secondary)]">
            Reminder
          </span>
        </div>
        {reminder ? (
          <DaywellStatusBadge
            label={reminder.isActive ? 'Active' : inactiveReason}
            tone={reminder.isActive ? 'success' : 'neutral'}
            showIcon={false}
          />
        ) : (
          <span className="text-[11px] font-medium text-[var(--dw-text-muted)]">
            Not set
          </span>
        )}
      </div>

      {reminder && (
        <div className="space-y-1 text-xs">
          <div className="flex items-center justify-between gap-2">
            <span className="text-[var(--dw-text-muted)]">Scheduled Alert</span>
            <span className="font-semibold text-[var(--dw-text-primary)] text-right">
              {formatTaskReminderSummary(reminder.triggerTimeUtc)}
            </span>
          </div>
          {dualDateLabel && (
            <div className="flex items-center justify-between gap-2">
              <span className="text-[var(--dw-text-muted)]">Calendar Date</span>
              <span className="font-medium text-[var(--dw-text-secondary)] text-right">
                {dualDateLabel}
              </span>
            </div>
          )}
          <div className="flex items-center justify-between gap-2">
            <span className="text-[var(--dw-text-muted)]">Timing Rule</span>
            <span className="font-medium text-[var(--dw-text-secondary)] text-right">
              {TASK_REMINDER_PRESET_LABELS[inferredPreset]}
            </span>
          </div>
        </div>
      )}

      {!isEditing ? (
        <div className="flex flex-wrap gap-1.5 pt-1 border-t border-[var(--dw-divider)]">
          <DaywellButton
            label={reminder ? 'Edit Reminder' : 'Set Reminder'}
            variant="outlined"
            size="compact"
            leadingIcon={reminder ? <Pencil className="w-3.5 h-3.5" /> : <Bell className="w-3.5 h-3.5" />}
            onClick={handleOpenEditor}
          />
          {reminder && (
            <DaywellButton
              label="Remove Reminder"
              variant="text"
              size="compact"
              leadingIcon={<BellOff className="w-3.5 h-3.5" />}
              onClick={onRemoveReminder}
              className="!text-[var(--dw-error)]"
            />
          )}
        </div>
      ) : (
        <div className="space-y-2 pt-2 border-t border-[var(--dw-divider)]">
          <TaskReminderEditorSection
            enabled
            onToggle={(next) => {
              if (!next) {
                setIsEditing(false);
                if (reminder) onRemoveReminder();
              }
            }}
            preset={preset}
            onChangePreset={setPreset}
            customDate={customDate}
            onChangeCustomDate={(v) => {
              setCustomDate(v);
              setFormError(undefined);
            }}
            customTime={customTime}
            onChangeCustomTime={(v) => {
              setCustomTime(v);
              setFormError(undefined);
            }}
            dueDate={task.dueDate}
            scheduledDate={task.scheduledDate}
            scheduledTime={task.scheduledTime}
            error={formError}
            compact={compact}
          />
          <div className="flex items-center justify-end gap-2">
            <DaywellButton
              label="Cancel"
              variant="text"
              size="compact"
              onClick={() => {
                setIsEditing(false);
                setFormError(undefined);
              }}
            />
            <DaywellButton
              label="Save Reminder"
              variant="primary"
              size="compact"
              onClick={handleApply}
            />
          </div>
        </div>
      )}
    </div>
  );
}
