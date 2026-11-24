import React from 'react';
import { BookOpen, CheckCircle2, HeartHandshake, Lock } from 'lucide-react';
import {
  DailyRhythmDayRecord,
  isDailyRhythmFaithComplete,
} from '../../domain/dailyRhythm';
import { LocalDateTime } from '../../domain/date';
import {
  DaywellCard,
  DaywellStatusBadge,
  DaywellStatusBanner,
} from '../ui';

export interface DailyFaithCheckInCardProps {
  dateIso: string;
  record: DailyRhythmDayRecord;
  isToday?: boolean;
  onToggleBibleStudy: (nextValue: boolean) => void;
  onTogglePrayer: (nextValue: boolean) => void;
}

function formatCompletedTime(iso?: string): string | null {
  if (!iso) return null;
  const parsed = LocalDateTime.tryParse(iso);
  return parsed ? parsed.timeOfDay.toDisplay12Hour() : null;
}

export function DailyFaithCheckInCard({
  dateIso,
  record,
  isToday = true,
  onToggleBibleStudy,
  onTogglePrayer,
}: DailyFaithCheckInCardProps) {
  const completedCount =
    (record.bibleStudyDone ? 1 : 0) + (record.prayerDone ? 1 : 0);
  const faithComplete = isDailyRhythmFaithComplete(record);
  const bibleTime = formatCompletedTime(record.bibleStudyCompletedAt);
  const prayerTime = formatCompletedTime(record.prayerCompletedAt);

  return (
    <DaywellCard padding="md" radius="lg" className="space-y-3">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="text-sm font-bold text-[var(--dw-text-primary)]">
              Daily Faith check-in
            </h3>
            <DaywellStatusBadge
              tone={
                faithComplete
                  ? 'success'
                  : completedCount === 1
                  ? 'warning'
                  : 'neutral'
              }
              label={
                faithComplete
                  ? '2/2 Complete'
                  : `${completedCount}/2 completed`
              }
            />
          </div>
          <p className="text-[11px] text-[var(--dw-text-muted)] mt-0.5">
            Both Bible study and prayer are required today ({dateIso}).
          </p>
        </div>
      </div>

      {!isToday && (
        <DaywellStatusBanner
          tone="warning"
          icon={<Lock className="w-4 h-4" />}
          message="Past and future Faith check-ins are locked. Only today can be updated."
        />
      )}

      <div className="space-y-2">
        <button
          type="button"
          role="checkbox"
          aria-checked={record.bibleStudyDone}
          disabled={!isToday}
          onClick={() => onToggleBibleStudy(!record.bibleStudyDone)}
          className={`w-full min-h-[52px] px-3 py-2.5 rounded-[var(--dw-radius-md)] border flex items-center justify-between gap-3 text-left transition-colors cursor-pointer disabled:opacity-60 disabled:cursor-not-allowed ${
            record.bibleStudyDone
              ? 'bg-[var(--dw-success-container)]/50 border-[var(--dw-success)]/40'
              : 'bg-[var(--dw-surface-subtle)] border-[var(--dw-border)] hover:border-[var(--dw-primary)]'
          }`}
        >
          <div className="flex items-center gap-3 min-w-0">
            <div
              className={`w-9 h-9 rounded-[var(--dw-radius-md)] flex items-center justify-center shrink-0 ${
                record.bibleStudyDone
                  ? 'bg-[var(--dw-success)] text-[var(--dw-on-success)]'
                  : 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)]'
              }`}
            >
              <BookOpen className="w-4 h-4" />
            </div>
            <div className="min-w-0">
              <div className="text-xs font-bold text-[var(--dw-text-primary)]">
                Bible study
              </div>
              <div className="text-[11px] text-[var(--dw-text-muted)] truncate">
                {record.bibleStudyDone
                  ? bibleTime
                    ? `Completed at ${bibleTime}`
                    : 'Completed today'
                  : 'Tap to mark Bible study complete'}
              </div>
            </div>
          </div>
          <CheckCircle2
            className={`w-5 h-5 shrink-0 ${
              record.bibleStudyDone
                ? 'text-[var(--dw-success)]'
                : 'text-[var(--dw-text-disabled)]'
            }`}
          />
        </button>

        <button
          type="button"
          role="checkbox"
          aria-checked={record.prayerDone}
          disabled={!isToday}
          onClick={() => onTogglePrayer(!record.prayerDone)}
          className={`w-full min-h-[52px] px-3 py-2.5 rounded-[var(--dw-radius-md)] border flex items-center justify-between gap-3 text-left transition-colors cursor-pointer disabled:opacity-60 disabled:cursor-not-allowed ${
            record.prayerDone
              ? 'bg-[var(--dw-success-container)]/50 border-[var(--dw-success)]/40'
              : 'bg-[var(--dw-surface-subtle)] border-[var(--dw-border)] hover:border-[var(--dw-primary)]'
          }`}
        >
          <div className="flex items-center gap-3 min-w-0">
            <div
              className={`w-9 h-9 rounded-[var(--dw-radius-md)] flex items-center justify-center shrink-0 ${
                record.prayerDone
                  ? 'bg-[var(--dw-success)] text-[var(--dw-on-success)]'
                  : 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)]'
              }`}
            >
              <HeartHandshake className="w-4 h-4" />
            </div>
            <div className="min-w-0">
              <div className="text-xs font-bold text-[var(--dw-text-primary)]">
                Prayer
              </div>
              <div className="text-[11px] text-[var(--dw-text-muted)] truncate">
                {record.prayerDone
                  ? prayerTime
                    ? `Completed at ${prayerTime}`
                    : 'Completed today'
                  : 'Tap to mark prayer complete'}
              </div>
            </div>
          </div>
          <CheckCircle2
            className={`w-5 h-5 shrink-0 ${
              record.prayerDone
                ? 'text-[var(--dw-success)]'
                : 'text-[var(--dw-text-disabled)]'
            }`}
          />
        </button>
      </div>

      {completedCount === 1 && (
        <p className="text-[11px] font-medium text-[var(--dw-warning)]">
          One step left: complete both Bible study and prayer to qualify Faith for today.
        </p>
      )}
    </DaywellCard>
  );
}
