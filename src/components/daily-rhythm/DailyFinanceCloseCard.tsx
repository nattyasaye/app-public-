import React from 'react';
import { CalendarCheck2, CheckCircle2, Filter } from 'lucide-react';
import {
  DailyRhythmDayRecord,
  isDailyRhythmFinanceComplete,
} from '../../domain/dailyRhythm';
import { DailyRhythmFinanceDaySummary } from '../../domain/dailyRhythmWorkflows';
import { LocalDateTime } from '../../domain/date';
import {
  DaywellButton,
  DaywellCard,
  DaywellStatusBadge,
  DaywellStatusBanner,
} from '../ui';

export interface DailyFinanceCloseCardProps {
  summary: DailyRhythmFinanceDaySummary;
  record: DailyRhythmDayRecord;
  isShowingTodayFilter?: boolean;
  onConfirmClose: () => void;
  onFilterToday?: () => void;
}

function formatTimeLabel(iso?: string): string | null {
  if (!iso) return null;
  const parsed = LocalDateTime.tryParse(iso);
  return parsed ? parsed.timeOfDay.toDisplay12Hour() : null;
}

export function DailyFinanceCloseCard({
  summary,
  record,
  isShowingTodayFilter = false,
  onConfirmClose,
  onFilterToday,
}: DailyFinanceCloseCardProps) {
  const isClosed = isDailyRhythmFinanceComplete(record);
  const needsReconfirmation =
    record.financeCloseStatus === 'needs_reconfirmation';
  const closedTime = formatTimeLabel(record.financeClosedAt);

  const badgeLabel = needsReconfirmation
    ? 'Needs reconfirmation'
    : record.financeCloseStatus === 'closed_with_transactions'
    ? 'Closed · Reviewed'
    : record.financeCloseStatus === 'closed_no_transactions'
    ? 'Closed · No transactions'
    : 'Unreviewed today';

  const confirmLabel = needsReconfirmation
    ? summary.hasTransactions
      ? "Reconfirm today's transactions"
      : 'Confirm no transactions today'
    : summary.confirmActionLabel;

  return (
    <DaywellCard padding="md" radius="lg" className="space-y-3">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="flex items-start gap-2.5 min-w-0">
          <div className="w-8 h-8 rounded-[var(--dw-radius-md)] bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] flex items-center justify-center shrink-0">
            <CalendarCheck2 className="w-4 h-4" />
          </div>
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <h3 className="text-xs font-bold text-[var(--dw-text-primary)]">
                Daily Finance review
              </h3>
              <DaywellStatusBadge
                tone={
                  isClosed
                    ? 'success'
                    : needsReconfirmation
                    ? 'warning'
                    : 'neutral'
                }
                label={badgeLabel}
              />
            </div>
            <p className="text-[11px] text-[var(--dw-text-muted)] mt-0.5">
              {summary.hasTransactions
                ? `${summary.transactionCount} active entry(s) recorded today (${summary.targetDateIso}).`
                : `No active transactions recorded today (${summary.targetDateIso}).`}
              {isClosed && closedTime ? ` Confirmed at ${closedTime}.` : ''}
            </p>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          {onFilterToday && !isShowingTodayFilter && (
            <DaywellButton
              label="View Today"
              variant="outlined"
              size="compact"
              leadingIcon={<Filter className="w-3.5 h-3.5" />}
              onClick={onFilterToday}
            />
          )}
          <DaywellButton
            label={isClosed ? 'Reconfirm review' : confirmLabel}
            variant={isClosed ? 'outlined' : 'primary'}
            size="compact"
            leadingIcon={<CheckCircle2 className="w-3.5 h-3.5" />}
            onClick={onConfirmClose}
          />
        </div>
      </div>

      {needsReconfirmation && (
        <DaywellStatusBanner
          tone="warning"
          title="Today's ledger changed after closing"
          message="A same-day entry was added, replaced, voided, or restored. Review today's transactions and reconfirm to close Finance for today."
        />
      )}

      {!isClosed && !needsReconfirmation && (
        <p className="text-[11px] text-[var(--dw-text-muted)]">
          Explicit confirmation is required every day, even when there are no transactions today.
        </p>
      )}
    </DaywellCard>
  );
}
