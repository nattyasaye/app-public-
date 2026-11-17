import React from 'react';

export interface DaywellCardProps extends React.HTMLAttributes<HTMLDivElement> {
  children: React.ReactNode;
  variant?: 'default' | 'subtle' | 'elevated' | 'primaryContainer';
  padding?: 'none' | 'sm' | 'compact' | 'md' | 'lg';
  radius?: 'md' | 'lg' | 'xl';
  interactive?: boolean;
}

const CARD_VARIANT_CLASSES: Record<NonNullable<DaywellCardProps['variant']>, string> = {
  default: 'bg-[var(--dw-card)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]',
  subtle:
    'bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]',
  elevated:
    'bg-[var(--dw-elevated)] border border-[var(--dw-border)] text-[var(--dw-text-primary)] shadow-sm',
  primaryContainer:
    'bg-[var(--dw-primary-container)] border border-[var(--dw-border)] text-[var(--dw-on-primary-container)]',
};

const CARD_PADDING_CLASSES: Record<NonNullable<DaywellCardProps['padding']>, string> = {
  none: '',
  sm: 'p-2.5',
  compact: 'p-3',
  md: 'p-4',
  lg: 'p-5',
};

const CARD_RADIUS_CLASSES: Record<NonNullable<DaywellCardProps['radius']>, string> = {
  md: 'rounded-[var(--dw-radius-md)]',
  lg: 'rounded-[var(--dw-radius-lg)]',
  xl: 'rounded-[var(--dw-radius-xl)]',
};

export function DaywellCard({
  children,
  variant = 'default',
  padding = 'md',
  radius = 'lg',
  interactive = false,
  className = '',
  onClick,
  ...rest
}: DaywellCardProps) {
  const isClickable = Boolean(interactive || onClick);
  return (
    <div
      onClick={onClick}
      role={onClick ? rest.role ?? 'button' : rest.role}
      tabIndex={onClick ? rest.tabIndex ?? 0 : rest.tabIndex}
      onKeyDown={
        onClick
          ? (e) => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                onClick(e as unknown as React.MouseEvent<HTMLDivElement>);
              }
              rest.onKeyDown?.(e);
            }
          : rest.onKeyDown
      }
      className={`${CARD_VARIANT_CLASSES[variant]} ${CARD_PADDING_CLASSES[padding]} ${CARD_RADIUS_CLASSES[radius]} ${
        isClickable
          ? 'cursor-pointer hover:border-[var(--dw-primary)] transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--dw-primary)]'
          : ''
      } ${className}`}
      {...rest}
    >
      {children}
    </div>
  );
}
