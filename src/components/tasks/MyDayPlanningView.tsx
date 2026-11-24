import React, { useMemo, useState } from 'react';
import {
  ArrowDown,
  ArrowRight,
  ArrowUp,
  Calendar,
  Check,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Clock,
  Flag,
  History,
  Plus,
  Repeat2,
  Sun,
  X,
} from 'lucide-react';
import { CalendarDate, SharedDateFormatter } from '../../domain/date';
import {
  DailyPlanItem,
  DailyPlanSnapshot,
  isTaskPlannedForDate,
} from '../../domain/dailyPlanningOperations';
import { SharedDailyPlanningEntry } from '../../domain/sharedFoundation';
import {
  computeSubtaskProgress,
  DaywellTaskRecord,
  TASK_PRIORITY_LABELS,
} from '../../domain/taskOperations';
import {
  createEmptyDailyRhythmDay,
  DailyRhythmDayRecord,
} from '../../domain/dailyRhythm';
import { buildDailyRhythmTaskReviewSnapshot } from '../../domain/dailyRhythmWorkflows';
import {
  formatRecurrenceSummary,
  resolveEffectiveRecurrenceConfig,
} from '../../domain/taskRecurrence';
import { DailyTaskReviewCard } from '../daily-rhythm';
import {
  DaywellButton,
  DaywellCard,
  DaywellEmptyState,
  DaywellIconButton,
  DaywellProgressBar,
  DaywellSectionHeader,
  DaywellStatusBadge,
  DaywellStatusBanner,
  DaywellStatusTone,
} from '../ui';

interface MyDayPlanningViewProps {
  snapshot: DailyPlanSnapshot;
  tasks: readonly DaywellTaskRecord[];
  entries: readonly SharedDailyPlanningEntry[];
  selectedDate: string;
  todayDate: string;
  searchQuery?: string;
  onSelectDate: (isoDate: string) => void;
  onStepDate: (deltaDays: number) => void;
  onJumpToToday: () => void;
  onToggleTask: (taskId: string) => void;
  onOpenTaskDetails: (taskId: string) => void;
  onMoveTaskOrder: (taskId: string, direction: 'up' | 'down') => void;
  onRemoveFromDay: (taskId: string) => void;
  onAddToDay: (
    taskId: string,
    action?: 'planned' | 'carried_forward'
  ) => void;
  onCarryForwardAll: () => void;
  onCarryPastRemainingToToday: () => void;
  onCreateTaskForDay: () => void;
  dailyRhythmRecord?: DailyRhythmDayRecord;
  onConfirmDailyReview?: () => void;
}

function priorityTone(priority: DaywellTaskRecord['priority']): DaywellStatusTone {
  switch (priority) {
    case 'urgent':
      return 'error';
    case 'high':
      return 'warning';
    default:
      return 'neutral';
  }
}

function matchesSearch(task: DaywellTaskRecord, query: string): boolean {
  if (!query) return true;
  const hay = [
    task.title,
    task.description ?? '',
    task.projectName ?? '',
    ...(task.labels ?? []),
  ]
    .join(' ')
    .toLowerCase();
  return hay.includes(query);
}

export function MyDayPlanningView({
  snapshot,
  tasks,
  entries,
  selectedDate,
  todayDate,
  searchQuery = '',
  onSelectDate,
  onStepDate,
  onJumpToToday,
  onToggleTask,
  onOpenTaskDetails,
  onMoveTaskOrder,
  onRemoveFromDay,
  onAddToDay,
  onCarryForwardAll,
  onCarryPastRemainingToToday,
  onCreateTaskForDay,
  dailyRhythmRecord,
  onConfirmDailyReview,
}: MyDayPlanningViewProps) {
  const [showOtherActive, setShowOtherActive] = useState(false);

  const taskReviewSnapshot = useMemo(
    () =>
      buildDailyRhythmTaskReviewSnapshot({
        tasks,
        dailyPlanningEntries: entries,
        targetDateIso: selectedDate,
        todayIso: todayDate,
      }),
    [tasks, entries, selectedDate, todayDate]
  );

  const normalizedQuery = searchQuery.trim().toLowerCase();
  const parsedSelected =
    CalendarDate.tryParse(selectedDate) ?? CalendarDate.today();

  const remainingItems = useMemo(
    () =>
      normalizedQuery
        ? snapshot.remainingItems.filter((item) =>
            matchesSearch(item.task, normalizedQuery)
          )
        : snapshot.remainingItems,
    [snapshot.remainingItems, normalizedQuery]
  );

  const completedItems = useMemo(
    () =>
      normalizedQuery
        ? snapshot.completedItems.filter((item) =>
            matchesSearch(item.task, normalizedQuery)
          )
        : snapshot.completedItems,
    [snapshot.completedItems, normalizedQuery]
  );

  const carryForwardSuggestions = useMemo(
    () =>
      normalizedQuery
        ? snapshot.carryForwardSuggestions.filter((s) =>
            matchesSearch(s.task, normalizedQuery)
          )
        : snapshot.carryForwardSuggestions,
    [snapshot.carryForwardSuggestions, normalizedQuery]
  );

  const carryForwardIds = useMemo(
    () => new Set(snapshot.carryForwardSuggestions.map((s) => s.task.id)),
    [snapshot.carryForwardSuggestions]
  );

  const overdueSuggestions = useMemo(
    () =>
      snapshot.overdueSuggestions.filter(
        (s) =>
          !carryForwardIds.has(s.task.id) &&
          matchesSearch(s.task, normalizedQuery)
      ),
    [snapshot.overdueSuggestions, carryForwardIds, normalizedQuery]
  );

  const overdueIds = useMemo(
    () => new Set(snapshot.overdueSuggestions.map((s) => s.task.id)),
    [snapshot.overdueSuggestions]
  );

  const scheduledSuggestions = useMemo(
    () =>
      snapshot.scheduledSuggestions.filter(
        (s) =>
          !carryForwardIds.has(s.task.id) &&
          !overdueIds.has(s.task.id) &&
          matchesSearch(s.task, normalizedQuery)
      ),
    [snapshot.scheduledSuggestions, carryForwardIds, overdueIds, normalizedQuery]
  );

  const otherActiveTasks = useMemo(
    () =>
      normalizedQuery
        ? snapshot.otherActiveTasks.filter((t) =>
            matchesSearch(t, normalizedQuery)
          )
        : snapshot.otherActiveTasks,
    [snapshot.otherActiveTasks, normalizedQuery]
  );

  const historyChips = useMemo(() => {
    const dates = new Set<string>([todayDate, selectedDate, ...snapshot.historyDates]);
    return Array.from(dates).sort((a, b) => b.localeCompare(a)).slice(0, 12);
  }, [todayDate, selectedDate, snapshot.historyDates]);

  const carryablePastCount = useMemo(() => {
    if (!snapshot.isPastDay) return 0;
    return snapshot.remainingItems.filter(
      (item) =>
        !isTaskPlannedForDate(item.task, entries, todayDate, todayDate)
    ).length;
  }, [snapshot.isPastDay, snapshot.remainingItems, entries, todayDate]);

  const totalSuggestionsCount =
    carryForwardSuggestions.length +
    overdueSuggestions.length +
    scheduledSuggestions.length;

  const renderPlannedItemRow = (
    item: DailyPlanItem,
    index: number,
    totalRemaining: number,
    isRemaining: boolean
  ) => {
    const task = item.task;
    const subProgress = computeSubtaskProgress(task.subtasks);
    const hasSubtasks = subProgress.total > 0;
    const isOverdue = Boolean(task.dueDate && task.dueDate < todayDate);

    return (
      <div
        key={task.id}
        className="p-3 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] flex items-start gap-3"
      >
        <button
          type="button"
          aria-label={
            item.isCompletedForDay
              ? `Reopen ${task.title}`
              : `Complete ${task.title}`
          }
          onClick={() => onToggleTask(task.id)}
          className={`w-5 h-5 rounded-[var(--dw-radius-sm)] border mt-0.5 flex items-center justify-center transition-colors shrink-0 cursor-pointer ${
            item.isCompletedForDay
              ? 'bg-[var(--dw-primary)] border-[var(--dw-primary)] text-[var(--dw-on-primary)]'
              : 'bg-[var(--dw-card)] border-[var(--dw-border)] hover:border-[var(--dw-primary)]'
          }`}
        >
          {item.isCompletedForDay && <Check className="w-3.5 h-3.5 stroke-[3]" />}
        </button>

        <div
          onClick={() => onOpenTaskDetails(task.id)}
          className="flex-1 min-w-0 cursor-pointer space-y-1"
        >
          <p
            className={`text-xs font-semibold leading-snug ${
              item.isCompletedForDay
                ? 'line-through text-[var(--dw-text-disabled)]'
                : 'text-[var(--dw-text-primary)]'
            }`}
          >
            {task.title}
          </p>

          <div className="flex flex-wrap items-center gap-1.5 text-[10px]">
            <DaywellStatusBadge
              tone={priorityTone(task.priority)}
              showIcon={false}
              label={TASK_PRIORITY_LABELS[task.priority]}
            />
            {item.isCarriedForward && (
              <DaywellStatusBadge
                tone="info"
                showIcon={false}
                label="Carried forward"
              />
            )}
            {item.completedLater && (
              <DaywellStatusBadge
                tone="success"
                showIcon={false}
                label="Completed later"
              />
            )}
            {!item.isCompletedForDay && isOverdue && (
              <DaywellStatusBadge
                tone="error"
                showIcon={false}
                label={`Overdue · ${task.dueDate}`}
              />
            )}
            {task.projectName && (
              <span className="font-semibold text-[var(--dw-text-secondary)]">
                {task.projectName}
              </span>
            )}
            {task.scheduledTime && (
              <span className="inline-flex items-center gap-0.5 text-[var(--dw-text-muted)]">
                <Clock className="w-3 h-3" />
                {task.scheduledTime}
              </span>
            )}
            {task.dueDate && !isOverdue && (
              <span className="inline-flex items-center gap-0.5 text-[var(--dw-primary)] font-medium">
                <Calendar className="w-3 h-3" />
                Due {task.dueDate}
              </span>
            )}
            {(() => {
              const rec = resolveEffectiveRecurrenceConfig(task);
              if (!rec) return null;
              return (
                <span className="inline-flex items-center gap-0.5 text-[var(--dw-text-secondary)]">
                  <Repeat2 className="w-3 h-3 text-[var(--dw-primary)]" />
                  {formatRecurrenceSummary(rec)}
                </span>
              );
            })()}
            {hasSubtasks && (
              <span className="text-[var(--dw-text-muted)]">
                {subProgress.completed}/{subProgress.total} subtasks
              </span>
            )}
          </div>
        </div>

        <div className="flex items-center gap-0.5 shrink-0">
          {isRemaining && (
            <>
              <DaywellIconButton
                label={`Move ${task.title} up`}
                size="compact"
                tone="muted"
                disabled={index === 0}
                onClick={() => onMoveTaskOrder(task.id, 'up')}
                icon={<ArrowUp className="w-3.5 h-3.5" />}
              />
              <DaywellIconButton
                label={`Move ${task.title} down`}
                size="compact"
                tone="muted"
                disabled={index === totalRemaining - 1}
                onClick={() => onMoveTaskOrder(task.id, 'down')}
                icon={<ArrowDown className="w-3.5 h-3.5" />}
              />
            </>
          )}
          <DaywellIconButton
            label={`Remove ${task.title} from My Day`}
            size="compact"
            tone="muted"
            onClick={() => onRemoveFromDay(task.id)}
            icon={<X className="w-3.5 h-3.5" />}
          />
        </div>
      </div>
    );
  };

  return (
    <div className="space-y-4">
      {/* Selected Day Header & History Navigation */}
      <DaywellCard padding="sm" radius="lg" className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex items-center gap-2 min-w-0">
            <div className="w-8 h-8 rounded-[var(--dw-radius-md)] bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] flex items-center justify-center shrink-0">
              <Sun className="w-4 h-4" />
            </div>
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-1.5">
                <h2 className="dw-type-title text-[var(--dw-text-primary)]">
                  My Day
                </h2>
                <DaywellStatusBadge
                  tone={
                    snapshot.isToday
                      ? 'success'
                      : snapshot.isPastDay
                        ? 'warning'
                        : 'info'
                  }
                  showIcon={false}
                  label={
                    snapshot.isToday
                      ? 'Today'
                      : snapshot.isPastDay
                        ? 'Past Day Review'
                        : 'Planned Ahead'
                  }
                />
              </div>
              <p className="text-[11px] text-[var(--dw-text-secondary)] truncate">
                {SharedDateFormatter.formatDual(parsedSelected, false)}
              </p>
            </div>
          </div>

          <div className="flex items-center gap-1">
            <DaywellIconButton
              label="Previous day"
              size="compact"
              tone="muted"
              onClick={() => onStepDate(-1)}
              icon={<ChevronLeft className="w-4 h-4" />}
            />
            <input
              type="date"
              aria-label="Select My Day plan date"
              value={selectedDate}
              onChange={(e) => {
                if (e.target.value) onSelectDate(e.target.value);
              }}
              className="min-h-[34px] px-2 py-1 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
            />
            <DaywellIconButton
              label="Next day"
              size="compact"
              tone="muted"
              onClick={() => onStepDate(1)}
              icon={<ChevronRight className="w-4 h-4" />}
            />
            {!snapshot.isToday && (
              <DaywellButton
                label="Today"
                variant="tonal"
                size="compact"
                onClick={onJumpToToday}
              />
            )}
          </div>
        </div>

        {/* Planning History Strip */}
        <div className="space-y-1.5 pt-1 border-t border-[var(--dw-divider)]">
          <div className="flex items-center justify-between gap-2">
            <span className="inline-flex items-center gap-1 text-[10px] font-bold uppercase tracking-wider text-[var(--dw-text-muted)]">
              <History className="w-3 h-3" />
              Daily Planning History
            </span>
            <span className="text-[10px] text-[var(--dw-text-muted)]">
              {snapshot.historyDates.length} recorded day(s)
            </span>
          </div>
          <div className="flex items-center gap-1.5 overflow-x-auto pb-0.5">
            {historyChips.map((dateIso) => {
              const active = dateIso === selectedDate;
              const isTodayChip = dateIso === todayDate;
              const parsed = CalendarDate.tryParse(dateIso);
              const label = isTodayChip
                ? `Today · ${dateIso}`
                : parsed
                  ? SharedDateFormatter.formatEthiopian(
                      parsed.toEthiopian(),
                      { useAmharic: false, includeEra: false }
                    ) + ` (${dateIso})`
                  : dateIso;
              return (
                <button
                  key={dateIso}
                  type="button"
                  onClick={() => onSelectDate(dateIso)}
                  className={`min-h-[30px] px-2.5 py-1 rounded-[var(--dw-radius-full)] text-[11px] font-semibold shrink-0 transition-colors cursor-pointer ${
                    active
                      ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)]'
                      : 'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)] hover:border-[var(--dw-primary)]'
                  }`}
                >
                  {label}
                </button>
              );
            })}
          </div>
        </div>

        {/* Daily Progress Bar & Carry-Forward Banner */}
        <div className="space-y-2 pt-1 border-t border-[var(--dw-divider)]">
          <div className="flex items-center justify-between gap-2 text-xs">
            <span className="font-semibold text-[var(--dw-text-primary)] tabular-nums">
              {snapshot.completedCount} of {snapshot.totalPlannedCount} completed
            </span>
            <span className="text-[11px] text-[var(--dw-text-muted)] tabular-nums">
              {snapshot.remainingCount} remaining · {snapshot.progressPercentage}%
            </span>
          </div>
          <DaywellProgressBar
            value={snapshot.progressPercentage}
            tone={snapshot.progressPercentage === 100 && snapshot.totalPlannedCount > 0 ? 'income' : 'primary'}
            label="My Day completion progress"
          />
          {snapshot.dismissedCount > 0 && (
            <p className="text-[10px] text-[var(--dw-text-muted)]">
              {snapshot.dismissedCount} task(s) removed from this day&apos;s plan (tasks remain active in Tasks).
            </p>
          )}
        </div>
      </DaywellCard>

      {snapshot.isPastDay && snapshot.remainingCount > 0 && (
        <DaywellStatusBanner
          tone="warning"
          title="Unfinished tasks from this day"
          message={
            carryablePastCount > 0
              ? `${carryablePastCount} unfinished task(s) from ${selectedDate} are not yet in Today's plan.`
              : `All remaining unfinished tasks from ${selectedDate} are already planned for Today.`
          }
          actionLabel={
            carryablePastCount > 0
              ? `Carry ${carryablePastCount} to Today`
              : undefined
          }
          onActionPressed={
            carryablePastCount > 0 ? onCarryPastRemainingToToday : undefined
          }
        />
      )}

      {!snapshot.isPastDay && snapshot.carryForwardSuggestions.length > 0 && (
        <DaywellStatusBanner
          tone="info"
          title="Unfinished tasks from previous days"
          message={`${snapshot.carryForwardSuggestions.length} unfinished task(s) from earlier planned days can be carried forward without duplicates.`}
          actionLabel={`Carry forward all (${snapshot.carryForwardSuggestions.length})`}
          onActionPressed={onCarryForwardAll}
        />
      )}

      {onConfirmDailyReview && (
        <DailyTaskReviewCard
          snapshot={taskReviewSnapshot}
          record={dailyRhythmRecord ?? createEmptyDailyRhythmDay(selectedDate)}
          isToday={snapshot.isToday}
          onConfirmReview={onConfirmDailyReview}
          onOpenTask={onOpenTaskDetails}
        />
      )}

      {/* Remaining Planned Tasks */}
      <DaywellCard padding="sm" radius="lg" className="space-y-2.5">
        <DaywellSectionHeader
          title="Remaining for This Day"
          count={remainingItems.length}
          actionLabel="Add Task"
          onActionPressed={onCreateTaskForDay}
        />

        {remainingItems.length === 0 ? (
          snapshot.totalPlannedCount === 0 ? (
            <DaywellEmptyState
              icon={<Sun className="w-7 h-7" />}
              message="Nothing planned for this day yet"
              subtitle="Add overdue, scheduled, carried-forward, or active tasks below without duplicating tasks."
              actionLabel="Create Task for Day"
              onActionPressed={onCreateTaskForDay}
            />
          ) : (
            <p className="text-xs text-[var(--dw-primary)] font-semibold py-2 text-center">
              All planned tasks for this day are completed!
            </p>
          )
        ) : (
          <div className="space-y-2">
            {remainingItems.map((item, idx) =>
              renderPlannedItemRow(item, idx, remainingItems.length, true)
            )}
          </div>
        )}
      </DaywellCard>

      {/* Completed for This Day */}
      {completedItems.length > 0 && (
        <DaywellCard padding="sm" radius="lg" className="space-y-2.5">
          <DaywellSectionHeader
            title="Completed for This Day"
            count={completedItems.length}
          />
          <div className="space-y-2">
            {completedItems.map((item, idx) =>
              renderPlannedItemRow(item, idx, completedItems.length, false)
            )}
          </div>
        </DaywellCard>
      )}

      {/* Suggestions & Add Tasks to Day */}
      <DaywellCard padding="sm" radius="lg" className="space-y-3">
        <DaywellSectionHeader
          title="Plan & Add Tasks"
          count={totalSuggestionsCount > 0 ? totalSuggestionsCount : undefined}
        />

        {carryForwardSuggestions.length > 0 && (
          <div className="space-y-2">
            <div className="flex items-center justify-between gap-2">
              <span className="text-[11px] font-bold uppercase tracking-wider text-[var(--dw-text-secondary)]">
                Carry Forward from Previous Days ({carryForwardSuggestions.length})
              </span>
              {!snapshot.isPastDay && (
                <DaywellButton
                  label="Carry forward all"
                  variant="tonal"
                  size="compact"
                  leadingIcon={<ArrowRight className="w-3.5 h-3.5" />}
                  onClick={onCarryForwardAll}
                />
              )}
            </div>
            <div className="space-y-1.5">
              {carryForwardSuggestions.map((s) => {
                const isOverdue = Boolean(
                  s.task.dueDate && s.task.dueDate < todayDate
                );
                return (
                  <div
                    key={s.task.id}
                    className="p-2.5 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] flex items-center justify-between gap-2"
                  >
                    <div
                      onClick={() => onOpenTaskDetails(s.task.id)}
                      className="min-w-0 flex-1 cursor-pointer space-y-0.5"
                    >
                      <p className="text-xs font-semibold text-[var(--dw-text-primary)] truncate">
                        {s.task.title}
                      </p>
                      <div className="flex flex-wrap items-center gap-1.5 text-[10px]">
                        {s.sourcePlanDate && (
                          <DaywellStatusBadge
                            tone="info"
                            showIcon={false}
                            label={`From ${s.sourcePlanDate}`}
                          />
                        )}
                        {isOverdue && (
                          <DaywellStatusBadge
                            tone="error"
                            showIcon={false}
                            label="Overdue"
                          />
                        )}
                        {(() => {
                          const rec = resolveEffectiveRecurrenceConfig(s.task);
                          if (!rec) return null;
                          return (
                            <span className="inline-flex items-center gap-0.5 text-[var(--dw-text-secondary)]">
                              <Repeat2 className="w-3 h-3 text-[var(--dw-primary)]" />
                              {formatRecurrenceSummary(rec)}
                            </span>
                          );
                        })()}
                      </div>
                    </div>
                    <DaywellButton
                      label="Carry"
                      variant="outlined"
                      size="compact"
                      leadingIcon={<Plus className="w-3.5 h-3.5" />}
                      onClick={() => onAddToDay(s.task.id, 'carried_forward')}
                    />
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {overdueSuggestions.length > 0 && (
          <div className="space-y-2">
            <span className="block text-[11px] font-bold uppercase tracking-wider text-[var(--dw-error)]">
              Overdue Tasks ({overdueSuggestions.length})
            </span>
            <div className="space-y-1.5">
              {overdueSuggestions.map((s) => (
                <div
                  key={s.task.id}
                  className="p-2.5 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] flex items-center justify-between gap-2"
                >
                  <div
                    onClick={() => onOpenTaskDetails(s.task.id)}
                    className="min-w-0 flex-1 cursor-pointer space-y-0.5"
                  >
                    <p className="text-xs font-semibold text-[var(--dw-text-primary)] truncate">
                      {s.task.title}
                    </p>
                    <div className="flex flex-wrap items-center gap-1.5 text-[10px]">
                      <DaywellStatusBadge
                        tone="error"
                        showIcon={false}
                        label={`Overdue · ${s.task.dueDate}`}
                      />
                      <span className="inline-flex items-center gap-0.5 text-[var(--dw-text-muted)]">
                        <Flag className="w-3 h-3" />
                        {TASK_PRIORITY_LABELS[s.task.priority]}
                      </span>
                      {(() => {
                        const rec = resolveEffectiveRecurrenceConfig(s.task);
                        if (!rec) return null;
                        return (
                          <span className="inline-flex items-center gap-0.5 text-[var(--dw-text-secondary)]">
                            <Repeat2 className="w-3 h-3 text-[var(--dw-primary)]" />
                            {formatRecurrenceSummary(rec)}
                          </span>
                        );
                      })()}
                    </div>
                  </div>
                  <DaywellButton
                    label="Add"
                    variant="outlined"
                    size="compact"
                    leadingIcon={<Plus className="w-3.5 h-3.5" />}
                    onClick={() => onAddToDay(s.task.id, 'planned')}
                  />
                </div>
              ))}
            </div>
          </div>
        )}

        {scheduledSuggestions.length > 0 && (
          <div className="space-y-2">
            <span className="block text-[11px] font-bold uppercase tracking-wider text-[var(--dw-primary)]">
              Due or Scheduled for {selectedDate} ({scheduledSuggestions.length})
            </span>
            <div className="space-y-1.5">
              {scheduledSuggestions.map((s) => (
                <div
                  key={s.task.id}
                  className="p-2.5 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] flex items-center justify-between gap-2"
                >
                  <div
                    onClick={() => onOpenTaskDetails(s.task.id)}
                    className="min-w-0 flex-1 cursor-pointer space-y-0.5"
                  >
                    <p className="text-xs font-semibold text-[var(--dw-text-primary)] truncate">
                      {s.task.title}
                    </p>
                    <div className="flex flex-wrap items-center gap-1.5 text-[10px]">
                      <DaywellStatusBadge
                        tone="success"
                        showIcon={false}
                        label={
                          s.task.dueDate === selectedDate
                            ? 'Due this day'
                            : 'Scheduled this day'
                        }
                      />
                      {(() => {
                        const rec = resolveEffectiveRecurrenceConfig(s.task);
                        if (!rec) return null;
                        return (
                          <span className="inline-flex items-center gap-0.5 text-[var(--dw-text-secondary)]">
                            <Repeat2 className="w-3 h-3 text-[var(--dw-primary)]" />
                            {formatRecurrenceSummary(rec)}
                          </span>
                        );
                      })()}
                    </div>
                  </div>
                  <DaywellButton
                    label="Add"
                    variant="outlined"
                    size="compact"
                    leadingIcon={<Plus className="w-3.5 h-3.5" />}
                    onClick={() => onAddToDay(s.task.id, 'planned')}
                  />
                </div>
              ))}
            </div>
          </div>
        )}

        {otherActiveTasks.length > 0 && (
          <div className="space-y-2 pt-1 border-t border-[var(--dw-divider)]">
            <button
              type="button"
              onClick={() => setShowOtherActive((prev) => !prev)}
              className="w-full flex items-center justify-between text-xs font-semibold text-[var(--dw-text-secondary)] hover:text-[var(--dw-primary)] py-1 cursor-pointer"
            >
              <span>Other Active Tasks ({otherActiveTasks.length})</span>
              <ChevronDown
                className={`w-4 h-4 transition-transform ${
                  showOtherActive ? 'rotate-180' : ''
                }`}
              />
            </button>
            {showOtherActive && (
              <div className="space-y-1.5">
                {otherActiveTasks.map((task) => {
                  const rec = resolveEffectiveRecurrenceConfig(task);
                  return (
                  <div
                    key={task.id}
                    className="p-2.5 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] flex items-center justify-between gap-2"
                  >
                    <div
                      onClick={() => onOpenTaskDetails(task.id)}
                      className="min-w-0 flex-1 cursor-pointer"
                    >
                      <p className="text-xs font-semibold text-[var(--dw-text-primary)] truncate">
                        {task.title}
                      </p>
                      <p className="text-[10px] text-[var(--dw-text-muted)] flex flex-wrap items-center gap-1.5">
                        <span>
                          {TASK_PRIORITY_LABELS[task.priority]}
                          {task.dueDate ? ` · Due ${task.dueDate}` : ''}
                        </span>
                        {rec && (
                          <span className="inline-flex items-center gap-0.5 text-[var(--dw-text-secondary)]">
                            <Repeat2 className="w-3 h-3 text-[var(--dw-primary)]" />
                            {formatRecurrenceSummary(rec)}
                          </span>
                        )}
                      </p>
                    </div>
                    <DaywellButton
                      label="Add"
                      variant="outlined"
                      size="compact"
                      leadingIcon={<Plus className="w-3.5 h-3.5" />}
                      onClick={() => onAddToDay(task.id, 'planned')}
                    />
                  </div>
                  );
                })}
              </div>
            )}
          </div>
        )}

        {totalSuggestionsCount === 0 && otherActiveTasks.length === 0 && (
          <p className="text-[11px] text-[var(--dw-text-muted)]">
            No additional active tasks waiting to be planned for this day.
          </p>
        )}
      </DaywellCard>
    </div>
  );
}
