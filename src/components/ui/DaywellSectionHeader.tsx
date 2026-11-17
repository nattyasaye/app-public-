import React from 'react';
import { DaywellButton } from './DaywellButton';

export interface DaywellSectionHeaderProps {
  title: string;
  eyebrow?: string;
  count?: number;
  actionLabel?: string;
  onActionPressed?: () => void;
  className?: string;
}

export function DaywellSectionHeader({
  title,
  eyebrow,
  count,
  actionLabel,
  onActionPressed,
  className = '',
}: DaywellSectionHeaderProps) {
  return (
    <div className={`flex items-center justify-between gap-3 ${className}`}>
      <div className="min-w-0">
        {eyebrow ? (
          <p className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
            {eyebrow}
          </p>
        ) : null}
        <div className="flex items-center gap-2 min-w-0">
          <h3 className="dw-type-title text-[var(--dw-text-primary)] truncate">
            {title}
          </h3>
          {typeof count === 'number' ? (
            <span className="inline-flex items-center px-2 py-0.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] text-[11px] font-bold tabular-nums shrink-0">
              {count}
            </span>
          ) : null}
        </div>
      </div>
      {actionLabel && onActionPressed ? (
        <DaywellButton
          label={actionLabel}
          variant="text"
          size="compact"
          onClick={onActionPressed}
        />
      ) : null}
    </div>
  );
}

export interface DaywellEmptyStateProps {
  icon: React.ReactNode;
  message: string;
  subtitle?: string;
  actionLabel?: string;
  onActionPressed?: () => void;
  className?: string;
}

export function DaywellEmptyState({
  icon,
  message,
  subtitle,
  actionLabel,
  onActionPressed,
  className = '',
}: DaywellEmptyStateProps) {
  return (
    <div
      className={`flex flex-col items-center justify-center text-center px-6 py-8 space-y-3 ${className}`}
    >
      <div className="text-[var(--dw-text-muted)] inline-flex items-center justify-center" aria-hidden="true">
        {icon}
      </div>
      <div className="space-y-1 max-w-sm">
        <p className="dw-type-body font-medium text-[var(--dw-text-secondary)]">
          {message}
        </p>
        {subtitle ? (
          <p className="dw-type-body-compact text-[var(--dw-text-muted)]">
            {subtitle}
          </p>
        ) : null}
      </div>
      {actionLabel && onActionPressed ? (
        <DaywellButton
          label={actionLabel}
          variant="primary"
          size="compact"
          onClick={onActionPressed}
        />
      ) : null}
    </div>
  );
}
