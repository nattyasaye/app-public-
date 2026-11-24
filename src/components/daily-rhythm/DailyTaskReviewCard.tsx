import React from 'react';
import { CheckCircle2, ClipboardCheck, Lock } from 'lucide-react';
import { DailyRhythmDayRecord } from '../../domain/dailyRhythm';
import { DailyRhythmTaskReviewSnapshot } from '../../domain/dailyRhythmWorkflows';
import { LocalDateTime } from '../../domain/date';
import {
  DaywellButton,
  DaywellCard,
  DaywellStatusBadge,
  DaywellStatusBanner,
} from '../ui';

export interface DailyTaskReviewCardProps {
  snapshot: DailyRhythmTaskReviewSnapshot;
  record: DailyRhythmDayRecord;
  isToday?: boolean;
  onConfirmReview: () => void;
  onOpenTask?: (taskId: string) => void;
}

function formatTimeLabel(iso?: string): string | null {
  if (!iso) return null;
  const parsed = LocalDateTime.tryParse(iso);
  return parsed ? parsed.timeOfDay.toDisplay12Hour() : null;
}

export function DailyTaskReviewCard({
  snapshot,
  record,
  isToday = true,
  onConfirmReview,
  onOpenTask,
}: DailyTaskReviewCardProps) {
  const confirmed = record.taskReviewConfirmed;
  const reviewedTime = formatTimeLabel(record.taskReviewedAt);
  const { evidence } = snapshot;

  return (
    <DaywellCard padding="md" radius="lg" className="space-y-3">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="flex items-start gap-2.5 min-w-0">
          <div className="w-8 h-8 rounded-[var(--dw-radius-md)] bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] flex items-center justify-center shrink-0">
            <ClipboardCheck className="w-4 h-4" />
          </div>
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <h3 className="text-xs font-bold text-[var(--dw-text-primary)]">
                Daily task review
              </h3>
              <DaywellStatusBadge
                tone={confirmed ? 'success' : 'neutral'}
                label={
                  confirmed
                    ? reviewedTime
                      ? `Confirmed · ${reviewedTime}`
                      : 'Confirmed'
                    : 'Needs review'
                }
              />
            </div>
            <p className="text-[11px] text-[var(--dw-text-muted)] mt-0.5">
              {snapshot.hasRelevantTasks
                ? 'Review what matters today. Completing every task is not required.'
                : 'No overdue, due today, scheduled, or My Day tasks need attention today.'}
            </p>
          </div>
        </div>

        {isToday && (
          <DaywellButton
            label={confirmed ? 'Reconfirm review' : snapshot.confirmActionLabel}
            variant={confirmed ? 'outlined' : 'primary'}
            size="compact"
            leadingIcon={<CheckCircle2 className="w-3.5 h-3.5" />}
            onClick={onConfirmReview}
          />
        )}
      </div>

      <div className="flex flex-wrap items-center gap-1.5">
        <DaywellStatusBadge
          tone={evidence.overdueCount > 0 ? 'error' : 'neutral'}
          showIcon={false}
          label={`Overdue: ${evidence.overdueCount}`}
        />
        <DaywellStatusBadge
          tone={evidence.todayCount > 0 ? 'info' : 'neutral'}
          showIcon={false}
          label={`Due / Today: ${evidence.todayCount}`}
        />
        <DaywellStatusBadge
          tone={evidence.plannedCount > 0 ? 'info' : 'neutral'}
          showIcon={false}
          label={`My Day: ${evidence.plannedCount}`}
        />
        <DaywellStatusBadge
          tone={evidence.completedTodayCount > 0 ? 'success' : 'neutral'}
          showIcon={false}
          label={`Done today: ${evidence.completedTodayCount}`}
        />
      </div>

      {!isToday && (
        <DaywellStatusBanner
          tone="warning"
          icon={<Lock className="w-4 h-4" />}
          message="Past and future daily task reviews are locked. Switch back to Today to confirm today's review."
        />
      )}

      {isToday && snapshot.attentionTasks.length > 0 && (
        <div className="space-y-1 pt-1 border-t border-[var(--dw-divider)]">
          <p className="text-[10px] font-bold uppercase tracking-wider text-[var(--dw-text-muted)]">
            Tasks in today&apos;s review ({snapshot.attentionTasks.length})
          </p>
          <div className="flex flex-wrap gap-1.5">
            {snapshot.attentionTasks.slice(0, 6).map((task) => (
              <button
                key={task.id}
                type="button"
                onClick={onOpenTask ? () => onOpenTask(task.id) : undefined}
                disabled={!onOpenTask}
                className="px-2 py-1 rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[11px] font-medium text-[var(--dw-text-primary)] hover:border-[var(--dw-primary)] transition-colors truncate max-w-[220px] cursor-pointer disabled:cursor-default"
              >
                {task.title}
              </button>
            ))}
            {snapshot.attentionTasks.length > 6 && (
              <span className="px-2 py-1 text-[11px] text-[var(--dw-text-muted)]">
                +{snapshot.attentionTasks.length - 6} more
              </span>
            )}
          </div>
        </div>
      )}
    </DaywellCard>
  );
}
