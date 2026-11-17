/**
 * Financial Calculation Engine using Integer Minor Units (Cents).
 * 1 ETB = 100 cents (ሳንቲም).
 */

export interface FinancialSnapshotState {
  openingBalanceCents: number;
  totalIncomeCents: number;
  totalExpensesCents: number;
  recordedBalanceCents: number;
  unpaidCommitmentsCents: number;
  savingsReservedCents: number;
  expectedFutureIncomeCents: number;
  availableToSpendCents: number;
}

export type CurrencyValidationTier = 'verified_etb' | 'verified_non_etb' | 'unverified';

const ISO_4217_RECOGNIZED_CODES = new Set<string>([
  'AED', 'AFN', 'ALL', 'AMD', 'ANG', 'AOA', 'ARS', 'AUD', 'AWG', 'AZN',
  'BAM', 'BBD', 'BDT', 'BGN', 'BHD', 'BIF', 'BMD', 'BND', 'BOB', 'BRL',
  'BSD', 'BTN', 'BWP', 'BYN', 'BZD', 'CAD', 'CDF', 'CHF', 'CLP', 'CNY',
  'COP', 'CRC', 'CUP', 'CVE', 'CZK', 'DJF', 'DKK', 'DOP', 'DZD', 'EGP',
  'ERN', 'ETB', 'EUR', 'FJD', 'FKP', 'GBP', 'GEL', 'GHS', 'GIP', 'GMD',
  'GNF', 'GTQ', 'GYD', 'HKD', 'HNL', 'HTG', 'HUF', 'IDR', 'ILS', 'INR',
  'IQD', 'IRR', 'ISK', 'JMD', 'JOD', 'JPY', 'KES', 'KGS', 'KHR', 'KMF',
  'KPW', 'KRW', 'KWD', 'KYD', 'KZT', 'LAK', 'LBP', 'LKR', 'LRD', 'LSL',
  'LYD', 'MAD', 'MDL', 'MGA', 'MKD', 'MMK', 'MNT', 'MOP', 'MRU', 'MUR',
  'MVR', 'MWK', 'MXN', 'MYR', 'MZN', 'NAD', 'NGN', 'NIO', 'NOK', 'NPR',
  'NZD', 'OMR', 'PAB', 'PEN', 'PGK', 'PHP', 'PKR', 'PLN', 'PYG', 'QAR',
  'RON', 'RSD', 'RUB', 'RWF', 'SAR', 'SBD', 'SCR', 'SDG', 'SEK', 'SGD',
  'SHP', 'SLE', 'SLL', 'SOS', 'SRD', 'SSP', 'STN', 'SYP', 'SZL', 'THB',
  'TJS', 'TMT', 'TND', 'TOP', 'TRY', 'TTD', 'TWD', 'TZS', 'UAH', 'UGX',
  'USD', 'UYU', 'UZS', 'VES', 'VND', 'VUV', 'WST', 'XAF', 'XCD', 'XOF',
  'XPF', 'YER', 'ZAR', 'ZMW', 'ZWL',
]);

export function normalizeCurrencyCode(currencyCode?: string | null): string {
  return (currencyCode ?? '').trim().toUpperCase();
}

export function classifyCurrencyCode(currencyCode?: string | null): CurrencyValidationTier {
  const norm = normalizeCurrencyCode(currencyCode);
  if (norm === 'ETB') return 'verified_etb';
  if (norm.length === 3 && ISO_4217_RECOGNIZED_CODES.has(norm)) {
    return 'verified_non_etb';
  }
  return 'unverified';
}

export function isValidCurrencyCode(currencyCode?: string | null): boolean {
  return classifyCurrencyCode(currencyCode) !== 'unverified';
}

export function isEtbCurrency(currencyCode?: string | null): boolean {
  return classifyCurrencyCode(currencyCode) === 'verified_etb';
}

export function formatCurrencyCents(
  amountCents: number,
  currencyCode: string | null | undefined = 'ETB'
): string {
  const isNegative = amountCents < 0;
  const absCents = Math.abs(amountCents);
  const whole = Math.floor(absCents / 100);
  const cents = String(absCents % 100).padStart(2, '0');
  const sign = isNegative ? '-' : '';
  const tier = classifyCurrencyCode(currencyCode);
  if (tier === 'unverified') {
    return `${sign}${whole.toLocaleString()}.${cents} (Unverified)`;
  }
  const code = normalizeCurrencyCode(currencyCode);
  return `${sign}${whole.toLocaleString()}.${cents} ${code}`;
}

export function formatBirr(amountCents: number): string {
  return formatCurrencyCents(amountCents, 'ETB');
}

export function formatCentsAsInput(amountCents: number): string {
  const safe = Number.isFinite(amountCents) ? Math.trunc(amountCents) : 0;
  const sign = safe < 0 ? '-' : '';
  const abs = Math.abs(safe);
  const whole = Math.trunc(abs / 100);
  const cents = String(abs % 100).padStart(2, '0');
  return `${sign}${whole}.${cents}`;
}

/**
 * Pure integer decimal parser (zero floating-point arithmetic).
 * Accepts optional commas, sign (when allowNegative is true), and up to 2 decimal places.
 */
export function parseDecimalToCentsStrict(
  input: string,
  options?: { allowNegative?: boolean }
): { valid: boolean; cents: number; error?: string } {
  if (typeof input !== 'string') {
    return { valid: false, cents: 0, error: 'Amount must be a text value' };
  }
  const allowNegative = options?.allowNegative ?? false;
  const cleaned = input.trim().replace(/,/g, '');
  if (!cleaned) {
    return { valid: false, cents: 0, error: 'Amount is required' };
  }

  const sign = cleaned.startsWith('-') ? -1 : cleaned.startsWith('+') ? 1 : 0;
  if (sign === -1 && !allowNegative) {
    return { valid: false, cents: 0, error: 'Amount cannot be negative' };
  }
  const unsigned = sign !== 0 ? cleaned.slice(1) : cleaned;
  if (!unsigned || unsigned === '.') {
    return { valid: false, cents: 0, error: 'Enter a valid amount (e.g. 150.00)' };
  }

  const decimalRegex = /^(\d+)?(?:\.(\d{1,2}))?$/;
  const match = decimalRegex.exec(unsigned);
  if (!match) {
    return {
      valid: false,
      cents: 0,
      error: 'Enter a valid amount (maximum 2 decimal places, e.g. 150.00)',
    };
  }

  const wholeDigits = match[1] ?? '0';
  const fracDigits = (match[2] ?? '').padEnd(2, '0');
  const whole = Number.parseInt(wholeDigits, 10);
  const frac = Number.parseInt(fracDigits, 10);
  if (!Number.isSafeInteger(whole) || !Number.isSafeInteger(frac)) {
    return { valid: false, cents: 0, error: 'Amount is out of range' };
  }

  const total = whole * 100 + frac;
  if (!Number.isSafeInteger(total)) {
    return { valid: false, cents: 0, error: 'Amount is out of range' };
  }

  const signed = sign === -1 ? -total : total;
  return { valid: true, cents: signed === 0 ? 0 : signed };
}

export function parseBirrToCents(input: string): number {
  const cleaned = input.trim().replace(/,/g, '');
  if (!cleaned) return 0;

  const negative = cleaned.startsWith('-');
  const unsigned = negative || cleaned.startsWith('+') ? cleaned.slice(1) : cleaned;
  const dotIdx = unsigned.indexOf('.');
  const rawWhole = (dotIdx >= 0 ? unsigned.slice(0, dotIdx) : unsigned).replace(/\D/g, '');
  const rawFrac = dotIdx >= 0 ? unsigned.slice(dotIdx + 1).replace(/\D/g, '') : '';

  const whole = rawWhole ? Number.parseInt(rawWhole, 10) : 0;
  const frac = rawFrac ? Number.parseInt(rawFrac.padEnd(2, '0').slice(0, 2), 10) : 0;
  if (!Number.isFinite(whole) || !Number.isFinite(frac)) return 0;

  const total = whole * 100 + frac;
  if (total === 0) return 0;
  return negative ? -total : total;
}

export function computeFinancialSnapshot(params: {
  openingBalanceCents: number;
  incomesCents: number[];
  expensesCents: number[];
  unpaidCommitmentsCents: number[];
  savingsAllocationsCents: number[];
  expectedFutureIncomeCents: number[];
}): FinancialSnapshotState {
  const totalIncome = params.incomesCents.reduce((a, b) => a + b, 0);
  const totalExpenses = params.expensesCents.reduce((a, b) => a + b, 0);
  const recordedBalance = params.openingBalanceCents + totalIncome - totalExpenses;

  const totalCommitments = params.unpaidCommitmentsCents.reduce((a, b) => a + b, 0);
  const totalSavings = params.savingsAllocationsCents.reduce((a, b) => a + b, 0);
  const totalExpected = params.expectedFutureIncomeCents.reduce((a, b) => a + b, 0);

  const availableToSpend = recordedBalance - totalCommitments - totalSavings;

  return {
    openingBalanceCents: params.openingBalanceCents,
    totalIncomeCents: totalIncome,
    totalExpensesCents: totalExpenses,
    recordedBalanceCents: recordedBalance,
    unpaidCommitmentsCents: totalCommitments,
    savingsReservedCents: totalSavings,
    expectedFutureIncomeCents: totalExpected,
    availableToSpendCents: availableToSpend,
  };
}
