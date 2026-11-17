import React from 'react';
import { Search, X } from 'lucide-react';
import { DaywellIconButton } from './DaywellButton';

export interface DaywellTextFieldProps
  extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  helperText?: string;
  errorText?: string;
  leadingIcon?: React.ReactNode;
}

export function DaywellTextField({
  label,
  helperText,
  errorText,
  leadingIcon,
  id,
  className = '',
  ...rest
}: DaywellTextFieldProps) {
  const inputId = id ?? React.useId();
  const hasError = Boolean(errorText);
  return (
    <div className="space-y-1.5">
      {label ? (
        <label
          htmlFor={inputId}
          className="block dw-type-label text-[var(--dw-text-secondary)]"
        >
          {label}
        </label>
      ) : null}
      <div className="relative flex items-center">
        {leadingIcon ? (
          <span
            aria-hidden="true"
            className="absolute left-3 text-[var(--dw-text-muted)] pointer-events-none inline-flex items-center"
          >
            {leadingIcon}
          </span>
        ) : null}
        <input
          id={inputId}
          aria-invalid={hasError || undefined}
          className={`w-full min-h-[44px] rounded-[var(--dw-radius-md)] bg-[var(--dw-card)] text-[var(--dw-text-primary)] placeholder:text-[var(--dw-text-muted)] border px-3 py-2 text-sm transition-colors focus:outline-none focus:ring-2 ${
            leadingIcon ? 'pl-10' : ''
          } ${
            hasError
              ? 'border-[var(--dw-error)] focus:ring-[var(--dw-error)]/30'
              : 'border-[var(--dw-border)] focus:border-[var(--dw-primary)] focus:ring-[var(--dw-primary)]/25'
          } ${className}`}
          {...rest}
        />
      </div>
      {errorText ? (
        <p className="text-xs text-[var(--dw-error)] font-medium">{errorText}</p>
      ) : helperText ? (
        <p className="text-xs text-[var(--dw-text-muted)]">{helperText}</p>
      ) : null}
    </div>
  );
}

export interface DaywellSearchFieldProps {
  value: string;
  onChange: (next: string) => void;
  placeholder?: string;
  ariaLabel?: string;
  className?: string;
}

export function DaywellSearchField({
  value,
  onChange,
  placeholder = 'Search...',
  ariaLabel = 'Search',
  className = '',
}: DaywellSearchFieldProps) {
  return (
    <div className={`relative flex items-center ${className}`}>
      <Search
        className="w-4 h-4 text-[var(--dw-text-muted)] absolute left-3 pointer-events-none"
        aria-hidden="true"
      />
      <input
        type="search"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        aria-label={ariaLabel}
        className="w-full min-h-[42px] pl-9 pr-9 py-2 rounded-[var(--dw-radius-md)] bg-[var(--dw-card)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] placeholder:text-[var(--dw-text-muted)] focus:outline-none focus:border-[var(--dw-primary)] focus:ring-2 focus:ring-[var(--dw-primary)]/20"
      />
      {value ? (
        <div className="absolute right-1">
          <DaywellIconButton
            label="Clear search"
            size="compact"
            tone="muted"
            onClick={() => onChange('')}
            icon={<X className="w-3.5 h-3.5" />}
          />
        </div>
      ) : null}
    </div>
  );
}

export interface DaywellSelectOption {
  value: string;
  label: string;
}

export interface DaywellSelectFieldProps
  extends React.SelectHTMLAttributes<HTMLSelectElement> {
  label?: string;
  options: DaywellSelectOption[];
  errorText?: string;
}

export function DaywellSelectField({
  label,
  options,
  errorText,
  id,
  className = '',
  ...rest
}: DaywellSelectFieldProps) {
  const selectId = id ?? React.useId();
  return (
    <div className="space-y-1.5">
      {label ? (
        <label
          htmlFor={selectId}
          className="block dw-type-label text-[var(--dw-text-secondary)]"
        >
          {label}
        </label>
      ) : null}
      <select
        id={selectId}
        className={`w-full min-h-[44px] rounded-[var(--dw-radius-md)] bg-[var(--dw-card)] text-[var(--dw-text-primary)] border border-[var(--dw-border)] px-3 py-2 text-xs font-medium focus:outline-none focus:border-[var(--dw-primary)] focus:ring-2 focus:ring-[var(--dw-primary)]/25 ${className}`}
        {...rest}
      >
        {options.map((opt) => (
          <option key={opt.value} value={opt.value}>
            {opt.label}
          </option>
        ))}
      </select>
      {errorText ? (
        <p className="text-xs text-[var(--dw-error)] font-medium">{errorText}</p>
      ) : null}
    </div>
  );
}
