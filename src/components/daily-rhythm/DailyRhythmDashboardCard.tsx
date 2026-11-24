import React, { useState } from 'react';
import {
  ArrowRight,
  BookOpen,
  CalendarDays,
  CheckCircle2,
  ChevronDown,
  ChevronUp,
  Circle,
  Flame,
  ListChecks,
  ShieldCheck,
  Snowflake,
  Wallet,
} from 'lucide-react';
import {
  DailyRhythmDashboardOverview,
  DailyRhythmFaithStep,
} from '../../domain/dailyRhythmWorkflows';
import {
  DaywellButton,
  DaywellCard,
  DaywellLoadingIndicator,
  DaywellProgressBar,
  DaywellStatusBadge,
  DaywellStatusBanner,
} from '../ui';

export interface DailyRhythmDashboardCardProps {
  overview: DailyRhythmDashboardOverview | null;
  isLoading?: boolean;
  errorMessage?: string | null;
  onRetry?: () => void;
  onCompleteFaithStep?: (step: DailyRhythmFaithStep) => void;
  onOpenFaith: () => void;
  onOpenTasksReview: () => void;
  onOpenFinanceReview: () => void;
  onOpenCalendarHistory: () => void;
}

export function DailyRhythmDashboardCard({
  overview,
  isLoading = false,
  errorMessage = null,
  onRetry,
  onCompleteFaithStep,
  onOpenFaith,
  onOpenTasksReview,
  onOpenFinanceReview,
  onOpenCalendarHistory,
}: DailyRhythmDashboardCardProps) {
  const [showFreezeRules, setShowFreezeRules] = useState(false);

  if (isLoading && !overview) {
    return (
      <DaywellCard padding="md" radius="xl">
        <DaywellLoadingIndicator label="Loading Daily Rhythm..." />
      </DaywellCard>
    );
  }

  if (errorMessage && !overview) {
    return (
      <DaywellCard padding="md" radius="xl">
        <DaywellStatusBanner
          tone="error"
          title="Unable to load Daily Rhythm"
          message={errorMessage}
          actionLabel={onRetry ? 'Retry' : undefined}
          onActionPressed={onRetry}
        />
      </DaywellCard>
    );
  }

  if (!overview) return null;

  const overallBadgeTone = overview.isDayQualified
    ? 'success'
    : overview.financeNeedsReconfirmation
    ? 'warning'
    : overview.completedResponsibilities > 0 ||
      overview.bibleStudyDone ||
      overview.prayerDone
    ? 'info'
    : 'neutral';

  const handleNextAction = () => {
    switch (overview.nextIncompleteResponsibility) {
      case 'faith':
        if (overview.nextFaithStep && onCompleteFaithStep) {
          onCompleteFaithStep(overview.nextFaithStep);
        } else {
          onOpenFaith();
        }
        break;
      case 'tasks':
        onOpenTasksReview();
        break;
      case 'finance':
        onOpenFinanceReview();
        break;
      case null:
      default:
        onOpenCalendarHistory();
        break;
    }
  };

  return (
    <DaywellCard
      padding="md"
      radius="xl"
      className="space-y-4 border border-[var(--dw-border)]"
    >
      {/* Top Progress Header */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0 flex-1 space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="dw-type-caption uppercase tracking-wider text-[var(--dw-primary)] font-bold">
              Daily Rhythm
            </span>
            <DaywellStatusBadge
              tone={overallBadgeTone}
              label={overview.overallStatusLabel}
            />
          </div>
          <h3 className="dw-type-title text-[var(--dw-text-primary)]">
            {overview.isDayQualified
              ? 'Today is steady and qualified'
              : `${overview.completedResponsibilities} of ${overview.totalResponsibilities} responsibilities complete`}
          </h3>
          <p className="text-xs text-[var(--dw-text-muted)] leading-relaxed">
            {overview.overallStatusDescription}
          </p>
        </div>

        <DaywellButton
          label="History"
          variant="outlined"
          size="compact"
          leadingIcon={<CalendarDays className="w-3.5 h-3.5" />}
          onClick={onOpenCalendarHistory}
        />
      </div>

      {errorMessage && (
        <DaywellStatusBanner
          tone="error"
          title="Daily Rhythm sync notice"
          message={errorMessage}
          actionLabel={onRetry ? 'Retry' : undefined}
          onActionPressed={onRetry}
        />
      )}

      {/* Overall 0-3 Progress Bar */}
      <div className="space-y-1.5">
        <div className="flex items-center justify-between text-[11px] font-semibold text-[var(--dw-text-secondary)] dw-type-numeric-body">
          <span>Today&apos;s progress</span>
          <span>
            {overview.completedResponsibilities} / {overview.totalResponsibilities}
          </span>
        </div>
        <DaywellProgressBar
          value={overview.progressPercent}
          tone={overview.isDayQualified ? 'income' : 'primary'}
          label="Daily Rhythm responsibility completion"
        />
      </div>

      {/* Highlighted Next Incomplete Responsibility or Calm Completion Banner */}
      <div
        className={`rounded-[var(--dw-radius-lg)] border p-3 flex flex-wrap items-center justify-between gap-3 ${
          overview.isDayQualified
            ? 'bg-[var(--dw-success-container)]/55 border-[var(--dw-success)]/30'
            : overview.financeNeedsReconfirmation
            ? 'bg-[var(--dw-warning-container)]/60 border-[var(--dw-warning)]/35'
            : 'bg-[var(--dw-primary-container-subtle)] border-[var(--dw-primary)]/25'
        }`}
      >
        <div className="min-w-0 flex-1 space-y-0.5">
          <div className="flex items-center gap-1.5 text-xs font-bold text-[var(--dw-text-primary)]">
            {overview.isDayQualified ? (
              <ShieldCheck className="w-4 h-4 text-[var(--dw-success)] shrink-0" />
            ) : (
              <ArrowRight className="w-4 h-4 text-[var(--dw-primary)] shrink-0" />
            )}
            <span>{overview.nextActionTitle}</span>
          </div>
          <p className="text-[11px] text-[var(--dw-text-secondary)] leading-snug">
            {overview.nextActionDescription}
          </p>
        </div>
        <DaywellButton
          label={overview.nextActionButtonLabel}
          variant={overview.isDayQualified ? 'outlined' : 'primary'}
          size="compact"
          onClick={handleNextAction}
        />
      </div>

      {/* Three Responsibilities */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-2.5">
        {/* 1. Faith */}
        <div className="rounded-[var(--dw-radius-lg)] border border-[var(--dw-border)] bg-[var(--dw-surface-subtle)] p-3 flex flex-col justify-between gap-2.5">
          <div className="space-y-2">
            <div className="flex items-center justify-between gap-2">
              <div className="flex items-center gap-1.5 min-w-0">
                <BookOpen className="w-4 h-4 text-[var(--dw-primary)] shrink-0" />
                <span className="text-xs font-bold text-[var(--dw-text-primary)] truncate">
                  Faith
                </span>
              </div>
              <DaywellStatusBadge
                tone={
                  overview.faithComplete
                    ? 'success'
                    : overview.faithCompletedCount === 1
                    ? 'warning'
                    : 'neutral'
                }
                label={overview.faithProgressLabel}
              />
            </div>

            <div className="space-y-1 text-[11px]">
              <div className="flex items-center gap-1.5 text-[var(--dw-text-secondary)]">
                {overview.bibleStudyDone ? (
                  <CheckCircle2 className="w-3.5 h-3.5 text-[var(--dw-success)] shrink-0" />
                ) : (
                  <Circle className="w-3.5 h-3.5 text-[var(--dw-text-disabled)] shrink-0" />
                )}
                <span>
                  Bible study:{' '}
                  <strong className="text-[var(--dw-text-primary)]">
                    {overview.bibleStudyDone ? 'Done' : 'Pending'}
                  </strong>
                </span>
              </div>
              <div className="flex items-center gap-1.5 text-[var(--dw-text-secondary)]">
                {overview.prayerDone ? (
                  <CheckCircle2 className="w-3.5 h-3.5 text-[var(--dw-success)] shrink-0" />
                ) : (
                  <Circle className="w-3.5 h-3.5 text-[var(--dw-text-disabled)] shrink-0" />
                )}
                <span>
                  Prayer:{' '}
                  <strong className="text-[var(--dw-text-primary)]">
                    {overview.prayerDone ? 'Done' : 'Pending'}
                  </strong>
                </span>
              </div>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-1.5 pt-1">
            {overview.nextFaithStep && onCompleteFaithStep ? (
              <DaywellButton
                label={overview.faithActionLabel}
                variant="tonal"
                size="compact"
                onClick={() => onCompleteFaithStep(overview.nextFaithStep!)}
                className="flex-1"
              />
            ) : null}
            <DaywellButton
              label={overview.nextFaithStep && onCompleteFaithStep ? 'Edit' : overview.faithActionLabel}
              variant="text"
              size="compact"
              onClick={onOpenFaith}
            />
          </div>
        </div>

        {/* 2. Tasks */}
        <div className="rounded-[var(--dw-radius-lg)] border border-[var(--dw-border)] bg-[var(--dw-surface-subtle)] p-3 flex flex-col justify-between gap-2.5">
          <div className="space-y-2">
            <div className="flex items-center justify-between gap-2">
              <div className="flex items-center gap-1.5 min-w-0">
                <ListChecks className="w-4 h-4 text-[var(--dw-info)] shrink-0" />
                <span className="text-xs font-bold text-[var(--dw-text-primary)] truncate">
                  Tasks
                </span>
              </div>
              <DaywellStatusBadge
                tone={overview.tasksComplete ? 'success' : 'neutral'}
                label={overview.tasksComplete ? 'Reviewed' : 'Open'}
              />
            </div>

            <div className="space-y-1 text-[11px]">
              <p className="font-semibold text-[var(--dw-text-primary)]">
                {overview.tasksStatusLabel}
              </p>
              <p className="text-[var(--dw-text-muted)] leading-snug">
                {overview.tasksContextLabel}
              </p>
            </div>
          </div>

          <div className="pt-1">
            <DaywellButton
              label={overview.tasksActionLabel}
              variant={overview.tasksComplete ? 'text' : 'tonal'}
              size="compact"
              onClick={onOpenTasksReview}
              fullWidth={!overview.tasksComplete}
            />
          </div>
        </div>

        {/* 3. Finance */}
        <div
          className={`rounded-[var(--dw-radius-lg)] border p-3 flex flex-col justify-between gap-2.5 ${
            overview.financeNeedsReconfirmation
              ? 'border-[var(--dw-warning)]/40 bg-[var(--dw-warning-container)]/35'
              : 'border-[var(--dw-border)] bg-[var(--dw-surface-subtle)]'
          }`}
        >
          <div className="space-y-2">
            <div className="flex items-center justify-between gap-2">
              <div className="flex items-center gap-1.5 min-w-0">
                <Wallet className="w-4 h-4 text-[var(--dw-warning)] shrink-0" />
                <span className="text-xs font-bold text-[var(--dw-text-primary)] truncate">
                  Finance
                </span>
              </div>
              <DaywellStatusBadge
                tone={
                  overview.financeComplete
                    ? 'success'
                    : overview.financeNeedsReconfirmation
                    ? 'warning'
                    : 'neutral'
                }
                label={overview.financeStatusLabel}
              />
            </div>

            <div className="space-y-1 text-[11px]">
              <p className="text-[var(--dw-text-secondary)]">
                {overview.financeContextLabel}
              </p>
              {overview.financeNeedsReconfirmation && (
                <p className="font-medium text-[var(--dw-on-warning-container)] leading-snug">
                  Ledger changed after closing — reconfirm today&apos;s review.
                </p>
              )}
            </div>
          </div>

          <div className="pt-1">
            <DaywellButton
              label={overview.financeActionLabel}
              variant={
                overview.financeNeedsReconfirmation
                  ? 'primary'
                  : overview.financeComplete
                  ? 'text'
                  : 'tonal'
              }
              size="compact"
              onClick={onOpenFinanceReview}
              fullWidth={!overview.financeComplete}
            />
          </div>
        </div>
      </div>

      {/* Streak & Freeze Summary */}
      <div className="rounded-[var(--dw-radius-lg)] border border-[var(--dw-border)] bg-[var(--dw-surface-subtle)]/70 p-3 space-y-2.5">
        <div className="grid grid-cols-3 gap-2 text-center">
          <div className="rounded-[var(--dw-radius-md)] bg-[var(--dw-card)] border border-[var(--dw-border)] px-2 py-2">
            <div className="flex items-center justify-center gap-1 text-[10px] font-bold uppercase tracking-wider text-[var(--dw-text-muted)]">
              <Flame className="w-3.5 h-3.5 text-[var(--dw-warning)]" />
              <span>Streak</span>
            </div>
            <div className="text-base font-extrabold text-[var(--dw-text-primary)] dw-type-numeric-body mt-0.5">
              {overview.currentStreak}d
            </div>
          </div>

          <div className="rounded-[var(--dw-radius-md)] bg-[var(--dw-card)] border border-[var(--dw-border)] px-2 py-2">
            <div className="text-[10px] font-bold uppercase tracking-wider text-[var(--dw-text-muted)]">
              Best streak
            </div>
            <div className="text-base font-extrabold text-[var(--dw-text-primary)] dw-type-numeric-body mt-0.5">
              {overview.bestStreak}d
            </div>
          </div>

          <div className="rounded-[var(--dw-radius-md)] bg-[var(--dw-card)] border border-[var(--dw-border)] px-2 py-2">
            <div className="flex items-center justify-center gap-1 text-[10px] font-bold uppercase tracking-wider text-[var(--dw-text-muted)]">
              <Snowflake className="w-3.5 h-3.5 text-[var(--dw-info)]" />
              <span>Freezes</span>
            </div>
            <div className="text-base font-extrabold text-[var(--dw-text-primary)] dw-type-numeric-body mt-0.5">
              {overview.availableFreezes} / {overview.maxFreezes}
            </div>
          </div>
        </div>

        {/* Next Freeze Progress */}
        <div className="space-y-1">
          <div className="flex items-center justify-between gap-2 text-[11px] text-[var(--dw-text-secondary)] dw-type-numeric-body">
            <span>Next freeze progress</span>
            <span className="font-semibold text-[var(--dw-text-primary)]">
              {overview.daysTowardNextFreeze} / {overview.qualifyingDaysPerFreeze} qualifying days ({overview.daysUntilNextFreeze} to go)
            </span>
          </div>
          <DaywellProgressBar
            value={overview.nextFreezeProgressPercent}
            tone="primary"
            label="Progress toward next streak freeze"
          />
        </div>

        {overview.provisionalFreezeActive && (
          <DaywellStatusBanner
            tone="warning"
            icon={<Snowflake className="w-4 h-4" />}
            title={`Provisional freeze protecting ${overview.provisionalFreezeDateIso ?? 'yesterday'}`}
            message="Yesterday missed, so 1 freeze is provisionally holding your streak while today is in progress. Qualify all 3 responsibilities today to finalize that spent freeze, or yesterday becomes missed tomorrow."
          />
        )}

        <p className="text-[11px] text-[var(--dw-text-muted)] leading-relaxed">
          {overview.freezeStatusSummary}
        </p>

        <div>
          <button
            type="button"
            onClick={() => setShowFreezeRules((prev) => !prev)}
            className="inline-flex items-center gap-1 text-[11px] font-semibold text-[var(--dw-primary)] hover:underline cursor-pointer min-h-[32px]"
          >
            <span>How streak freezes work</span>
            {showFreezeRules ? (
              <ChevronUp className="w-3.5 h-3.5" />
            ) : (
              <ChevronDown className="w-3.5 h-3.5" />
            )}
          </button>

          {showFreezeRules && (
            <ul className="mt-1.5 space-y-1 pl-4 list-disc text-[11px] text-[var(--dw-text-secondary)] leading-snug">
              {overview.freezeRules.map((rule) => (
                <li key={rule}>{rule}</li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </DaywellCard>
  );
}
