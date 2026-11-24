import React from 'react';
import {
  BookOpen,
  CheckCircle2,
  Circle,
  Lock,
  ShieldAlert,
  Snowflake,
  XCircle,
} from 'lucide-react';
import { DailyRhythmCalendarDayInspection } from '../../domain/dailyRhythmWorkflows';
import { LocalDateTime } from '../../domain/date';
import {
  DaywellCard,
  DaywellStatusBadge,
  DaywellStatusBanner,
  DaywellStatusTone,
} from '../ui';

export interface DailyRhythmCalendarDetailCardProps {
  inspection: DailyRhythmCalendarDayInspection;
}

function formatCompletedTime(iso?: string): string | null {
  if (!iso) return null;
  const parsed = LocalDateTime.tryParse(iso);
  return parsed ? parsed.timeOfDay.toDisplay12Hour() : null;
}

function badgeToneForInspection(
  inspection: DailyRhythmCalendarDayInspection
): DaywellStatusTone {
  switch (inspection.calendarStatus) {
    case 'complete':
      return 'success';
    case 'freeze_protected':
      return inspection.isProvisionalFreeze ? 'warning' : 'info';
    case 'partial':
      return 'warning';
    case 'missed':
      return 'error';
    case 'untouched':
    case 'unrecorded':
    default:
      return 'neutral';
  }
}

export function DailyRhythmCalendarDetailCard({
  inspection,
}: DailyRhythmCalendarDetailCardProps) {
  const bibleTime = formatCompletedTime(inspection.bibleStudyCompletedAt);
  const prayerTime = formatCompletedTime(inspection.prayerCompletedAt);
  const taskTime = formatCompletedTime(inspection.taskReviewedAt);
  const financeTime = formatCompletedTime(inspection.financeClosedAt);
  const ev = inspection.taskReviewEvidence;

  return (
    <DaywellCard padding="md" radius="lg" className="space-y-3">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0 space-y-0.5">
          <div className="flex flex-wrap items-center gap-2">
            <span className="dw-type-caption uppercase tracking-wider font-bold text-[var(--dw-primary)]">
              Daily Rhythm History
            </span>
            <DaywellStatusBadge
              tone={badgeToneForInspection(inspection)}
              label={inspection.statusLabel}
            />
          </div>
          <p className="text-xs text-[var(--dw-text-muted)]">
            {inspection.detailSummary}
          </p>
        </div>

        {inspection.hasRecordedHistory && (
          <span className="text-xs font-bold text-[var(--dw-text-primary)] dw-type-numeric-body shrink-0">
            {inspection.completedResponsibilities}/3
          </span>
        )}
      </div>

      {inspection.freezeExplanation && (
        <DaywellStatusBanner
          tone={inspection.isProvisionalFreeze ? 'warning' : 'info'}
          icon={<Snowflake className="w-4 h-4" />}
          title={
            inspection.isProvisionalFreeze
              ? 'Provisional freeze protection'
              : 'Finalized spent freeze'
          }
          message={inspection.freezeExplanation}
        />
      )}

      {!inspection.hasRecordedHistory ? (
        <div className="rounded-[var(--dw-radius-md)] border border-dashed border-[var(--dw-border)] bg-[var(--dw-surface-subtle)] p-3 text-xs text-[var(--dw-text-muted)]">
          {inspection.lockNotice ?? 'No Daily Rhythm history recorded for this date.'}
        </div>
      ) : (
        <div className="space-y-2 text-xs">
          {/* Faith */}
          <div className="rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] px-3 py-2 flex flex-wrap items-center justify-between gap-2">
            <div className="flex items-center gap-2 min-w-0">
              <BookOpen className="w-4 h-4 text-[var(--dw-primary)] shrink-0" />
              <div className="min-w-0">
                <p className="font-semibold text-[var(--dw-text-primary)]">
                  Faith · {inspection.faithComplete ? 'Complete (2/2)' : 'Incomplete'}
                </p>
                <p className="text-[11px] text-[var(--dw-text-muted)]">
                  Bible study:{' '}
                  {inspection.bibleStudyDone
                    ? bibleTime
                      ? `Done (${bibleTime})`
                      : 'Done'
                    : 'Not done'}{' '}
                  · Prayer:{' '}
                  {inspection.prayerDone
                    ? prayerTime
                      ? `Done (${prayerTime})`
                      : 'Done'
                    : 'Not done'}
                </p>
              </div>
            </div>
            {inspection.faithComplete ? (
              <CheckCircle2 className="w-4 h-4 text-[var(--dw-success)] shrink-0" />
            ) : (
              <Circle className="w-4 h-4 text-[var(--dw-text-disabled)] shrink-0" />
            )}
          </div>

          {/* Tasks */}
          <div className="rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] px-3 py-2 flex flex-wrap items-center justify-between gap-2">
            <div className="min-w-0">
              <p className="font-semibold text-[var(--dw-text-primary)]">
                Tasks · {inspection.taskReviewConfirmed ? 'Reviewed' : 'Not confirmed'}
              </p>
              <p className="text-[11px] text-[var(--dw-text-muted)]">
                {inspection.taskReviewConfirmed
                  ? taskTime
                    ? `Confirmed at ${taskTime}`
                    : 'Confirmed'
                  : 'No task review confirmation'}
                {ev
                  ? ` · Snapshot: ${ev.overdueCount} overdue, ${ev.todayCount} today, ${ev.plannedCount} My Day`
                  : ''}
              </p>
            </div>
            {inspection.tasksComplete ? (
              <CheckCircle2 className="w-4 h-4 text-[var(--dw-success)] shrink-0" />
            ) : (
              <Circle className="w-4 h-4 text-[var(--dw-text-disabled)] shrink-0" />
            )}
          </div>

          {/* Finance */}
          <div className="rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] px-3 py-2 flex flex-wrap items-center justify-between gap-2">
            <div className="min-w-0">
              <p className="font-semibold text-[var(--dw-text-primary)]">
                Finance · {inspection.financeStatusLabel}
              </p>
              <p className="text-[11px] text-[var(--dw-text-muted)]">
                {inspection.financeComplete
                  ? financeTime
                    ? `Closed at ${financeTime}`
                    : 'Closed'
                  : inspection.financeCloseStatus === 'needs_reconfirmation'
                  ? 'Ledger changed after closing'
                  : 'Not closed'}
              </p>
            </div>
            {inspection.financeComplete ? (
              <CheckCircle2 className="w-4 h-4 text-[var(--dw-success)] shrink-0" />
            ) : inspection.financeCloseStatus === 'needs_reconfirmation' ? (
              <ShieldAlert className="w-4 h-4 text-[var(--dw-warning)] shrink-0" />
            ) : (
              <XCircle className="w-4 h-4 text-[var(--dw-text-disabled)] shrink-0" />
            )}
          </div>

          {inspection.lockNotice && (
            <div className="flex items-center gap-1.5 text-[11px] text-[var(--dw-text-muted)] pt-0.5">
              <Lock className="w-3.5 h-3.5 shrink-0" />
              <span>{inspection.lockNotice}</span>
            </div>
          )}
        </div>
      )}
    </DaywellCard>
  );
}
