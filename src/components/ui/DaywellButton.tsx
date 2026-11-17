import React from 'react';
import { Loader2 } from 'lucide-react';

export type DaywellButtonVariant =
  | 'primary'
  | 'secondary'
  | 'tonal'
  | 'outlined'
  | 'text'
  | 'destructive';

export type DaywellButtonSize = 'regular' | 'compact';

export interface DaywellButtonProps
  extends Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, 'children'> {
  label: string;
  variant?: DaywellButtonVariant;
  size?: DaywellButtonSize;
  leadingIcon?: React.ReactNode;
  trailingIcon?: React.ReactNode;
  isLoading?: boolean;
  fullWidth?: boolean;
}

const VARIANT_CLASSES: Record<DaywellButtonVariant, string> = {
  primary:
    'bg-[var(--dw-primary)] text-[var(--dw-on-primary)] hover:opacity-90 border border-transparent shadow-xs',
  secondary:
    'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] hover:opacity-90 border border-transparent',
  tonal:
    'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] hover:opacity-90 border border-transparent',
  outlined:
    'bg-transparent text-[var(--dw-primary)] border border-[var(--dw-border)] hover:bg-[var(--dw-surface-subtle)]',
  text:
    'bg-transparent text-[var(--dw-primary)] border border-transparent hover:bg-[var(--dw-surface-subtle)]',
  destructive:
    'bg-[var(--dw-error)] text-[var(--dw-on-error)] hover:opacity-90 border border-transparent shadow-xs',
};

const SIZE_CLASSES: Record<DaywellButtonSize, string> = {
  regular: 'min-h-[44px] px-4 py-2.5 text-xs font-bold rounded-[var(--dw-radius-md)]',
  compact: 'min-h-[36px] px-3 py-1.5 text-xs font-semibold rounded-[var(--dw-radius-sm)]',
};

export function DaywellButton({
  label,
  variant = 'primary',
  size = 'regular',
  leadingIcon,
  trailingIcon,
  isLoading = false,
  fullWidth = false,
  disabled,
  type = 'button',
  className = '',
  ...rest
}: DaywellButtonProps) {
  const isDisabled = Boolean(disabled || isLoading);
  return (
    <button
      type={type}
      disabled={isDisabled}
      aria-busy={isLoading || undefined}
      className={`inline-flex items-center justify-center gap-2 whitespace-nowrap shrink-0 transition-all cursor-pointer focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--dw-primary)] disabled:opacity-50 disabled:cursor-not-allowed active:scale-[0.99] ${VARIANT_CLASSES[variant]} ${SIZE_CLASSES[size]} ${fullWidth ? 'w-full' : ''} ${className}`}
      {...rest}
    >
      {isLoading ? (
        <Loader2 className="w-4 h-4 animate-spin shrink-0" aria-hidden="true" />
      ) : leadingIcon ? (
        <span className="shrink-0 inline-flex items-center" aria-hidden="true">
          {leadingIcon}
        </span>
      ) : null}
      <span className="truncate">{label}</span>
      {!isLoading && trailingIcon ? (
        <span className="shrink-0 inline-flex items-center" aria-hidden="true">
          {trailingIcon}
        </span>
      ) : null}
    </button>
  );
}

export interface DaywellIconButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  label: string;
  icon: React.ReactNode;
  tone?: 'default' | 'primary' | 'muted' | 'danger';
  size?: 'regular' | 'compact';
}

const ICON_TONE_CLASSES: Record<NonNullable<DaywellIconButtonProps['tone']>, string> = {
  default: 'text-[var(--dw-text-primary)] hover:bg-[var(--dw-surface-subtle)]',
  primary:
    'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] hover:opacity-90',
  muted: 'text-[var(--dw-text-muted)] hover:bg-[var(--dw-surface-subtle)] hover:text-[var(--dw-text-primary)]',
  danger: 'text-[var(--dw-error)] hover:bg-[var(--dw-error-container)]',
};

export function DaywellIconButton({
  label,
  icon,
  tone = 'default',
  size = 'regular',
  type = 'button',
  className = '',
  ...rest
}: DaywellIconButtonProps) {
  const dim = size === 'compact' ? 'min-h-[36px] min-w-[36px]' : 'min-h-[44px] min-w-[44px]';
  return (
    <button
      type={type}
      aria-label={label}
      title={rest.title ?? label}
      className={`inline-flex items-center justify-center rounded-[var(--dw-radius-md)] transition-all cursor-pointer focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--dw-primary)] disabled:opacity-50 disabled:cursor-not-allowed ${dim} ${ICON_TONE_CLASSES[tone]} ${className}`}
      {...rest}
    >
      <span aria-hidden="true" className="inline-flex items-center justify-center">
        {icon}
      </span>
    </button>
  );
}
