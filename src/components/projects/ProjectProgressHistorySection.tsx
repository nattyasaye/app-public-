import React, { useMemo, useState } from 'react';
import { CalendarDate } from '../../domain/date';
import {
  EnrichedProgressLogEntry,
  formatNumber,
  projectsService,
} from '../../services/projectsService';
import { History, RotateCcw } from 'lucide-react';
import {
  DaywellButton,
  DaywellCard,
  DaywellEmptyState,
  DaywellSectionHeader,
  DaywellStatusBadge,
  DaywellStatusBanner,
  DaywellTextField,
} from '../ui';

export interface ProjectProgressHistorySectionProps {
  projectId: string;
  history: EnrichedProgressLogEntry[];
  onRefresh: () => void;
}

export function ProjectProgressHistorySection({
  history,
  onRefresh,
}: ProjectProgressHistorySectionProps) {
  const [selectedTarget, setSelectedTarget] =
    useState<EnrichedProgressLogEntry | null>(null);
  const [correctionDelta, setCorrectionDelta] = useState('');
  const [correctionDate, setCorrectionDate] = useState(() =>
    CalendarDate.today().toIsoString()
  );
  const [correctionReason, setCorrectionReason] = useState('');
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [showAll, setShowAll] = useState(false);

  const visibleHistory = useMemo(
    () => (showAll ? history : history.slice(0, 12)),
    [history, showAll]
  );

  const openAdjust = (entry: EnrichedProgressLogEntry) => {
    setSelectedTarget(entry);
    const origDelta = entry.record.deltaValue ?? 0;
    // Suggest negating the original positive delta by default to reverse a mistake cleanly
    setCorrectionDelta(origDelta > 0 ? String(-origDelta) : '');
    setCorrectionDate(CalendarDate.today().toIsoString());
    setCorrectionReason('');
    setErrorMsg(null);
  };

  const handleSubmitAdjustment = (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedTarget) return;
    setErrorMsg(null);

    const delta = Number(correctionDelta);
    if (!Number.isFinite(delta) || delta === 0) {
      setErrorMsg('Adjustment amount must be a non-zero number (use negative to subtract).');
      return;
    }
    const reason = correctionReason.trim();
    if (!reason) {
      setErrorMsg('A reason is required for compensating progress adjustments.');
      return;
    }

    try {
      projectsService.appendProgressCorrection({
        targetLogId: selectedTarget.record.id,
        correctionDelta: delta,
        recordedDate: correctionDate || CalendarDate.today().toIsoString(),
        reason,
      });
      setSelectedTarget(null);
      onRefresh();
    } catch (err) {
      setErrorMsg(
        err instanceof Error
          ? err.message
          : 'Unable to record compensating adjustment.'
      );
    }
  };

  return (
    <section className="space-y-3">
      <DaywellSectionHeader
        title="Progress Activity"
        count={history.length}
      />

      {history.length === 0 ? (
        <DaywellCard padding="md" radius="lg">
          <DaywellEmptyState
            icon={<History className="w-7 h-7" />}
            message="No progress logged yet"
            subtitle="Logged counter totals, grouped item updates, and timed sessions appear here chronologically."
          />
        </DaywellCard>
      ) : (
        <DaywellCard padding="compact" radius="lg" className="divide-y divide-[var(--dw-divider)]">
          {visibleHistory.map((entry) => {
            const delta = entry.record.deltaValue ?? 0;
            const unit = entry.unitLabel ? ` ${entry.unitLabel}` : '';
            const deltaText = `${delta > 0 ? '+' : ''}${formatNumber(delta)}${unit}`;

            return (
              <div
                key={entry.record.id}
                className="py-2.5 first:pt-1 last:pb-1 flex items-start justify-between gap-2"
              >
                <div className="min-w-0 space-y-0.5">
                  <div className="flex items-center flex-wrap gap-1.5">
                    <span className="text-xs font-bold text-[var(--dw-text-primary)] dw-type-numeric-body">
                      {deltaText}
                    </span>
                    <span className="text-xs text-[var(--dw-text-secondary)] truncate">
                      · {entry.blockTitle}
                      {entry.parentItemTitle ? ` / ${entry.parentItemTitle}` : ''}
                    </span>
                    {entry.isCorrection && (
                      <DaywellStatusBadge
                        tone="warning"
                        showIcon={false}
                        label="Adjustment"
                      />
                    )}
                  </div>
                  <p className="text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
                    {entry.record.recordedDate ?? ''}
                    {entry.correctionReason ? ` · Reason: ${entry.correctionReason}` : ''}
                  </p>
                </div>

                {!entry.isCorrection && (
                  <DaywellButton
                    label="Adjust"
                    variant="text"
                    size="compact"
                    leadingIcon={<RotateCcw className="w-3 h-3" />}
                    onClick={() => openAdjust(entry)}
                  />
                )}
              </div>
            );
          })}

          {history.length > 12 && (
            <div className="pt-2 flex justify-center">
              <DaywellButton
                label={
                  showAll
                    ? 'Show recent activity'
                    : `Show all ${history.length} logs`
                }
                variant="text"
                size="compact"
                onClick={() => setShowAll((v) => !v)}
              />
            </div>
          )}
        </DaywellCard>
      )}

      {/* Compensating Adjustment Modal */}
      {selectedTarget && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Adjust Logged Progress"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs"
          onClick={(e) => {
            if (e.target === e.currentTarget) setSelectedTarget(null);
          }}
        >
          <div className="w-full max-w-md bg-[var(--dw-elevated)] rounded-[var(--dw-radius-xl)] p-5 shadow-2xl border border-[var(--dw-border)] space-y-4">
            <div className="space-y-1">
              <h3 className="dw-type-title text-[var(--dw-text-primary)]">
                Log Compensating Adjustment
              </h3>
              <p className="text-xs text-[var(--dw-text-secondary)]">
                Progress logs are append-only to keep your activity history accurate. Record an explicit adjustment for{' '}
                <strong>
                  +{formatNumber(selectedTarget.record.deltaValue ?? 0)}
                  {selectedTarget.unitLabel ? ` ${selectedTarget.unitLabel}` : ''}
                </strong>{' '}
                in {selectedTarget.blockTitle}.
              </p>
            </div>

            {errorMsg ? <DaywellStatusBanner tone="error" message={errorMsg} /> : null}

            <form onSubmit={handleSubmitAdjustment} className="space-y-3">
              <div className="grid grid-cols-2 gap-2.5">
                <DaywellTextField
                  label="Adjustment Delta *"
                  type="number"
                  step="any"
                  placeholder="-1"
                  value={correctionDelta}
                  onChange={(e) => setCorrectionDelta(e.target.value)}
                />
                <DaywellTextField
                  label="Date"
                  type="date"
                  value={correctionDate}
                  onChange={(e) => setCorrectionDate(e.target.value)}
                />
              </div>

              <DaywellTextField
                label="Reason *"
                placeholder="e.g. Logged twice by mistake"
                value={correctionReason}
                onChange={(e) => setCorrectionReason(e.target.value)}
              />

              <div className="flex items-center justify-end gap-2 pt-2">
                <DaywellButton
                  label="Cancel"
                  variant="outlined"
                  size="compact"
                  onClick={() => setSelectedTarget(null)}
                />
                <DaywellButton
                  type="submit"
                  label="Record Adjustment"
                  variant="primary"
                  size="compact"
                />
              </div>
            </form>
          </div>
        </div>
      )}
    </section>
  );
}
