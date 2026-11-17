import React from 'react';
import {
  AlertCircle,
  AlertTriangle,
  ArrowLeftRight,
  CheckCircle2,
  Info,
  Loader2,
  TrendingDown,
  TrendingUp,
  X,
} from 'lucide-react';
import { DaywellButton, DaywellIconButton } from './DaywellButton';

export type DaywellStatusTone =
  | 'info'
  | 'success'
  | 'warning'
  | 'error'
  | 'income'
  | 'expense'
  | 'transfer'
  | 'neutral';

interface ToneStyle {
  container: string;
  icon: React.ReactNode;
  prefix: string;
}

const TONE_MAP: Record<DaywellStatusTone, ToneStyle> = {
  info: {
    container:
      'bg-[var(--dw-info-container)] text-[var(--dw-on-info-container)] border-[var(--dw-info)]/25',
    icon: <Info className="w-3.5 h-3.5 shrink-0" />,
    prefix: 'Info',
  },
  success: {
    container:
      'bg-[var(--dw-success-container)] text-[var(--dw-on-success-container)] border-[var(--dw-success)]/25',
    icon: <CheckCircle2 className="w-3.5 h-3.5 shrink-0" />,
    prefix: 'Success',
  },
  warning: {
    container:
      'bg-[var(--dw-warning-container)] text-[var(--dw-on-warning-container)] border-[var(--dw-warning)]/30',
    icon: <AlertTriangle className="w-3.5 h-3.5 shrink-0" />,
    prefix: 'Warning',
  },
  error: {
    container:
      'bg-[var(--dw-error-container)] text-[var(--dw-on-error-container)] border-[var(--dw-error)]/30',
    icon: <AlertCircle className="w-3.5 h-3.5 shrink-0" />,
    prefix: 'Error',
  },
  income: {
    container:
      'bg-[var(--dw-income-container)] text-[var(--dw-on-income-container)] border-[var(--dw-income)]/25',
    icon: <TrendingUp className="w-3.5 h-3.5 shrink-0" />,
    prefix: 'Income',
  },
  expense: {
    container:
      'bg-[var(--dw-expense-container)] text-[var(--dw-on-expense-container)] border-[var(--dw-expense)]/25',
    icon: <TrendingDown className="w-3.5 h-3.5 shrink-0" />,
    prefix: 'Expense',
  },
  transfer: {
    container:
      'bg-[var(--dw-transfer-container)] text-[var(--dw-on-transfer-container)] border-[var(--dw-transfer)]/25',
    icon: <ArrowLeftRight className="w-3.5 h-3.5 shrink-0" />,
    prefix: 'Transfer',
  },
  neutral: {
    container:
      'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-secondary)] border-[var(--dw-border)]',
    icon: <Info className="w-3.5 h-3.5 shrink-0" />,
    prefix: 'Status',
  },
};

export interface DaywellStatusBadgeProps {
  label: string;
  tone?: DaywellStatusTone;
  icon?: React.ReactNode;
  showIcon?: boolean;
  className?: string;
}

export function DaywellStatusBadge({
  label,
  tone = 'info',
  icon,
  showIcon = true,
  className = '',
}: DaywellStatusBadgeProps) {
  const spec = TONE_MAP[tone];
  return (
    <span
      className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-[var(--dw-radius-sm)] border text-[11px] font-semibold leading-4 ${spec.container} ${className}`}
    >
      {showIcon ? (
        <span aria-hidden="true" className="inline-flex items-center">
          {icon ?? spec.icon}
        </span>
      ) : null}
      <span className="truncate">{label}</span>
    </span>
  );
}

export interface DaywellStatusBannerProps {
  message: string;
  title?: string;
  tone?: DaywellStatusTone;
  icon?: React.ReactNode;
  actionLabel?: string;
  onActionPressed?: () => void;
  onDismiss?: () => void;
  liveRegion?: boolean;
  className?: string;
}

export function DaywellStatusBanner({
  message,
  title,
  tone = 'info',
  icon,
  actionLabel,
  onActionPressed,
  onDismiss,
  liveRegion = false,
  className = '',
}: DaywellStatusBannerProps) {
  const spec = TONE_MAP[tone];
  return (
    <div
      role={tone === 'error' || tone === 'warning' ? 'alert' : liveRegion ? 'status' : undefined}
      aria-live={liveRegion ? 'polite' : undefined}
      className={`flex items-start gap-3 p-3 rounded-[var(--dw-radius-md)] border ${spec.container} ${className}`}
    >
      <span className="mt-0.5 shrink-0" aria-hidden="true">
        {icon ?? spec.icon}
      </span>
      <div className="flex-1 min-w-0 space-y-1">
        {title ? <p className="text-xs font-bold leading-snug">{title}</p> : null}
        <p className="text-xs leading-relaxed">{message}</p>
        {actionLabel && onActionPressed ? (
          <div className="pt-1">
            <DaywellButton
              label={actionLabel}
              variant="text"
              size="compact"
              onClick={onActionPressed}
              className="!px-1 !text-current underline"
            />
          </div>
        ) : null}
      </div>
      {onDismiss ? (
        <DaywellIconButton
          label="Dismiss notice"
          size="compact"
          onClick={onDismiss}
          icon={<X className="w-4 h-4" />}
          className="!text-current"
        />
      ) : null}
    </div>
  );
}

export interface DaywellLoadingIndicatorProps {
  label?: string;
  className?: string;
}

export function DaywellLoadingIndicator({
  label = 'Loading...',
  className = '',
}: DaywellLoadingIndicatorProps) {
  return (
    <div
      role="status"
      aria-live="polite"
      className={`flex flex-col items-center justify-center gap-2 py-8 text-[var(--dw-text-muted)] ${className}`}
    >
      <Loader2 className="w-5 h-5 animate-spin text-[var(--dw-primary)]" aria-hidden="true" />
      <span className="dw-type-body-compact">{label}</span>
    </div>
  );
}

export interface DaywellProgressBarProps {
  value: number; // 0 to 100
  tone?: 'primary' | 'income' | 'warning' | 'error';
  label?: string;
  className?: string;
}

const PROGRESS_TONE: Record<NonNullable<DaywellProgressBarProps['tone']>, string> = {
  primary: 'bg-[var(--dw-primary)]',
  income: 'bg-[var(--dw-income)]',
  warning: 'bg-[var(--dw-warning)]',
  error: 'bg-[var(--dw-error)]',
};

export function DaywellProgressBar({
  value,
  tone = 'primary',
  label,
  className = '',
}: DaywellProgressBarProps) {
  const clamped = Math.max(0, Math.min(100, Number.isFinite(value) ? value : 0));
  return (
    <div
      role="progressbar"
      aria-valuenow={Math.round(clamped)}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-label={label}
      className={`w-full h-2 rounded-[var(--dw-radius-full)] bg-[var(--dw-surface-subtle)] overflow-hidden ${className}`}
    >
      <div
        className={`h-full rounded-[var(--dw-radius-full)] transition-all ${PROGRESS_TONE[tone]}`}
        style={{ width: `${clamped}%` }}
      />
    </div>
  );
}
