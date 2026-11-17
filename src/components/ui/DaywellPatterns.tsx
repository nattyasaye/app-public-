import React from 'react';
import { AlertCircle, AlertTriangle } from 'lucide-react';
import { DaywellButton } from './DaywellButton';
import { DaywellCard } from './DaywellCard';
import { DaywellEmptyState, DaywellSectionHeader } from './DaywellSectionHeader';
import { DaywellLoadingIndicator, DaywellStatusBanner } from './DaywellStatus';

export interface DaywellSectionContainerProps {
  title: string;
  eyebrow?: string;
  count?: number;
  actionLabel?: string;
  onActionPressed?: () => void;
  children: React.ReactNode;
  className?: string;
}

export function DaywellSectionContainer({
  title,
  eyebrow,
  count,
  actionLabel,
  onActionPressed,
  children,
  className = '',
}: DaywellSectionContainerProps) {
  return (
    <section className={`space-y-2.5 ${className}`}>
      <DaywellSectionHeader
        title={title}
        eyebrow={eyebrow}
        count={count}
        actionLabel={actionLabel}
        onActionPressed={onActionPressed}
      />
      <DaywellCard padding="md" radius="lg">
        {children}
      </DaywellCard>
    </section>
  );
}

export interface DaywellContentStateProps {
  isLoading?: boolean;
  error?: string | null;
  isEmpty?: boolean;
  emptyIcon?: React.ReactNode;
  emptyMessage?: string;
  emptySubtitle?: string;
  emptyActionLabel?: string;
  onEmptyAction?: () => void;
  onRetry?: () => void;
  children: React.ReactNode;
}

export function DaywellContentState({
  isLoading = false,
  error,
  isEmpty = false,
  emptyIcon,
  emptyMessage = 'Nothing here yet',
  emptySubtitle,
  emptyActionLabel,
  onEmptyAction,
  onRetry,
  children,
}: DaywellContentStateProps) {
  if (isLoading) {
    return <DaywellLoadingIndicator />;
  }
  if (error) {
    return (
      <DaywellStatusBanner
        tone="error"
        title="Something went wrong"
        message={error}
        actionLabel={onRetry ? 'Try again' : undefined}
        onActionPressed={onRetry}
      />
    );
  }
  if (isEmpty) {
    return (
      <DaywellEmptyState
        icon={emptyIcon ?? <AlertCircle className="w-8 h-8" />}
        message={emptyMessage}
        subtitle={emptySubtitle}
        actionLabel={emptyActionLabel}
        onActionPressed={onEmptyAction}
      />
    );
  }
  return <>{children}</>;
}

export interface DaywellConfirmationDialogProps {
  isOpen: boolean;
  title: string;
  description: string;
  confirmLabel?: string;
  cancelLabel?: string;
  destructive?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

export function DaywellConfirmationDialog({
  isOpen,
  title,
  description,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  destructive = false,
  onConfirm,
  onCancel,
}: DaywellConfirmationDialogProps) {
  const titleId = React.useId();
  if (!isOpen) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      className="fixed inset-0 z-60 bg-black/60 backdrop-blur-xs flex items-center justify-center p-4"
    >
      <div className="bg-[var(--dw-elevated)] border border-[var(--dw-border)] rounded-[var(--dw-radius-xl)] max-w-sm w-full p-6 space-y-4 shadow-2xl">
        <div
          className={`w-12 h-12 rounded-[var(--dw-radius-lg)] flex items-center justify-center mx-auto ${
            destructive
              ? 'bg-[var(--dw-error-container)] text-[var(--dw-on-error-container)]'
              : 'bg-[var(--dw-warning-container)] text-[var(--dw-on-warning-container)]'
          }`}
          aria-hidden="true"
        >
          <AlertCircle className="w-6 h-6" />
        </div>
        <div className="text-center space-y-1">
          <h3 id={titleId} className="dw-type-title text-[var(--dw-text-primary)]">
            {title}
          </h3>
          <p className="dw-type-body-compact text-[var(--dw-text-secondary)]">
            {description}
          </p>
        </div>
        <div className="flex items-center gap-2 pt-2">
          <DaywellButton
            label={cancelLabel}
            variant="outlined"
            fullWidth
            onClick={onCancel}
          />
          <DaywellButton
            label={confirmLabel}
            variant={destructive ? 'destructive' : 'primary'}
            fullWidth
            onClick={onConfirm}
          />
        </div>
      </div>
    </div>
  );
}

export interface DeprecatedPrototypeBannerProps {
  areaName: string;
  detail?: string;
  className?: string;
}

export function DeprecatedPrototypeBanner({
  areaName,
  detail = 'Static design prototype only — not backed by live canonical persistence. Use the core modules for real data.',
  className = '',
}: DeprecatedPrototypeBannerProps) {
  return (
    <DaywellStatusBanner
      tone="warning"
      icon={<AlertTriangle className="w-4 h-4 shrink-0" />}
      title={`Deprecated Design Prototype · ${areaName}`}
      message={detail}
      className={className}
    />
  );
}
