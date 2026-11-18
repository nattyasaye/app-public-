import { CalendarDate } from '../../domain/date';

export type FinanceV7Tab = 'overview' | 'transactions' | 'plan' | 'reports';

export type ComposerKind = 'expense' | 'income' | 'transfer' | 'split' | 'lend' | 'borrow' | 'third_party';

export interface FinanceComposerPrefill {
  nonce: number;
  kind: ComposerKind;
  amountText?: string;
  description?: string;
  accountId?: string;
  destinationAccountId?: string;
  categoryId?: string;
  occurrenceDate?: string;
  movementDate?: string;
  feeText?: string;
  feeCategoryId?: string;
  note?: string;
  payee?: string;
  correctedFromEntryId?: string;
}

export interface ConfirmActionState {
  title: string;
  message: string;
  confirmLabel: string;
  tone: 'danger' | 'primary';
  onConfirm: () => void;
}

export function formatDualDateLabel(isoDate: string): string {
  const cal = CalendarDate.tryParse(isoDate);
  if (!cal) return isoDate;
  const eth = cal.toEthiopian();
  return `${cal.gregorianShortMonthName} ${cal.day}, ${cal.year} · ${eth.englishMonthName} ${eth.day}, ${eth.year}`;
}

import {
  formatCentsAsInput,
  parseDecimalToCentsStrict,
} from '../../domain/financialEngine';

export function centsToInputText(cents: number): string {
  return formatCentsAsInput(cents);
}

export function tryParseStrictDecimalToCents(
  input: string,
  options?: { allowNegative?: boolean }
): number | null {
  const res = parseDecimalToCentsStrict(input, options);
  return res.valid ? res.cents : null;
}
