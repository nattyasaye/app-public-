/**
 * Daywell Finance SMS Draft Foundation & Provider-Specific Parsers (Web Domain)
 *
 * Pure domain logic — zero DOM, React, localStorage, or network dependencies.
 * Core invariant: SMS messages NEVER create ledger postings automatically.
 * Workflow: SMS text -> parsed result -> reviewable draft -> explicit user approval -> ledger posting.
 */

import { CalendarDate, EthiopiaClock } from './date';
import {
  Account,
  assertEtbPostingAccounts,
  buildDirectExpense,
  buildDirectIncome,
  buildTransfer,
  DEFAULT_EXPENSE_CATEGORIES,
  DoubleEntryValidationError,
  JournalEntry,
  Posting,
  SimpleTransaction,
  TransactionCategory,
} from './doubleEntryFinance';
import { getAccountSubType, isActiveVerifiedEtbAccount } from './financeV7Engine';
import { SHARED_DESIGN_TOKENS, SYSTEM_CONTROL_ACCOUNT_IDS } from './sharedFoundation';

export type SmsProvider = 'cbe' | 'telebirr' | 'boa' | 'unknown';
export type SmsDirection = 'incoming' | 'outgoing' | 'uncertain';
export type SmsSuggestedTransactionType = 'expense' | 'income' | 'transfer' | 'unknown';
export type SmsDraftStatus = 'needs_review' | 'approved' | 'dismissed' | 'unrecognized';
export type SmsParseConfidence = 'high' | 'medium' | 'low' | 'unrecognized';

export interface FinanceSmsDraft {
  id: string;
  provider: SmsProvider;
  fingerprint: string;
  transactionReference?: string;
  receiptUrl?: string;
  suggestedType: SmsSuggestedTransactionType;
  direction: SmsDirection;
  principalCents: number;
  serviceFeeCents: number;
  vatCents: number;
  otherChargesCents: number;
  totalAmountCents?: number;
  hasAmountMismatch: boolean;
  currencyCode: string;
  accountHint?: string;
  counterpartyName?: string;
  counterpartyHint?: string;
  reportedBalanceCents?: number;
  transactionTimestampIso?: string;
  transactionDateIso?: string;
  receivedAtUtc: string;
  confidence: SmsParseConfidence;
  status: SmsDraftStatus;
  isNonLedgerNotice: boolean;
  parseNotes?: string;
  suggestedAccountId?: string;
  suggestedCategoryId?: string;
  approvedEntryId?: string;
  /** Local-only raw SMS text for review/troubleshooting; excluded from portable backups & exports. */
  rawSmsText: string;
  createdAt: string;
  updatedAt: string;
}

export interface SmsParseOutcome {
  kind: 'draft' | 'ignored_non_transactional';
  provider?: SmsProvider;
  reason?: string;
  draft?: FinanceSmsDraft;
}

export interface SmsDeduplicationResult {
  isDuplicate: boolean;
  existingDraft?: FinanceSmsDraft;
  matchedBy?: 'provider_reference' | 'fingerprint';
}

export interface SmsImportBatchSummary {
  importedCount: number;
  unrecognizedCount: number;
  duplicateCount: number;
  ignoredCount: number;
  importedDrafts: FinanceSmsDraft[];
  duplicateMatches: Array<{ reference?: string; existingStatus: SmsDraftStatus }>;
  ignoredReasons: string[];
}

export const SMS_PROVIDER_LABELS: Readonly<Record<SmsProvider, string>> = {
  cbe: 'CBE',
  telebirr: 'Telebirr',
  boa: 'Bank of Abyssinia (BOA)',
  unknown: 'Unknown',
};

// ============================================================================
// Pure RFC 6234 SHA-256 (synchronous, zero Node/WebCrypto dependency)
// ============================================================================

const SHA256_K = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]);

function rotr(value: number, bits: number): number {
  return (value >>> bits) | (value << (32 - bits));
}

function encodeUtf8Bytes(input: string): Uint8Array {
  if (typeof TextEncoder !== 'undefined') {
    return new TextEncoder().encode(input);
  }
  const bytes: number[] = [];
  for (let i = 0; i < input.length; i++) {
    let code = input.charCodeAt(i);
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    } else if (code >= 0xd800 && code <= 0xdbff && i + 1 < input.length) {
      const next = input.charCodeAt(++i);
      const cp = 0x10000 + (((code & 0x3ff) << 10) | (next & 0x3ff));
      bytes.push(
        0xf0 | (cp >> 18),
        0x80 | ((cp >> 12) & 0x3f),
        0x80 | ((cp >> 6) & 0x3f),
        0x80 | (cp & 0x3f)
      );
    } else {
      bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    }
  }
  return new Uint8Array(bytes);
}

export function sha256HexSync(input: string): string {
  const bytes = encodeUtf8Bytes(input);
  const bitLenHi = Math.floor((bytes.length * 8) / 0x100000000);
  const bitLenLo = (bytes.length * 8) >>> 0;

  const paddedLen = Math.ceil((bytes.length + 9) / 64) * 64;
  const padded = new Uint8Array(paddedLen);
  padded.set(bytes);
  padded[bytes.length] = 0x80;
  const view = new DataView(padded.buffer);
  view.setUint32(paddedLen - 8, bitLenHi, false);
  view.setUint32(paddedLen - 4, bitLenLo, false);

  const h = new Uint32Array([
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ]);
  const w = new Uint32Array(64);

  for (let offset = 0; offset < paddedLen; offset += 64) {
    for (let i = 0; i < 16; i++) {
      w[i] = view.getUint32(offset + i * 4, false);
    }
    for (let i = 16; i < 64; i++) {
      const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }

    let a = h[0];
    let b = h[1];
    let c = h[2];
    let d = h[3];
    let e = h[4];
    let f = h[5];
    let g = h[6];
    let hh = h[7];

    for (let i = 0; i < 64; i++) {
      const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch = (e & f) ^ (~e & g);
      const temp1 = (hh + S1 + ch + SHA256_K[i] + w[i]) >>> 0;
      const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const temp2 = (S0 + maj) >>> 0;

      hh = g;
      g = f;
      f = e;
      e = (d + temp1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) >>> 0;
    }

    h[0] = (h[0] + a) >>> 0;
    h[1] = (h[1] + b) >>> 0;
    h[2] = (h[2] + c) >>> 0;
    h[3] = (h[3] + d) >>> 0;
    h[4] = (h[4] + e) >>> 0;
    h[5] = (h[5] + f) >>> 0;
    h[6] = (h[6] + g) >>> 0;
    h[7] = (h[7] + hh) >>> 0;
  }

  return Array.from(h)
    .map((word) => word.toString(16).padStart(8, '0'))
    .join('');
}

// ============================================================================
// Normalization, Integer Cents, Masking & Date Helpers
// ============================================================================

export function normalizeSmsTextForFingerprint(rawSmsText: string): string {
  return rawSmsText.trim().replace(/\s+/g, ' ').toLowerCase();
}

export function computeSmsFingerprint(rawSmsText: string): string {
  return sha256HexSync(normalizeSmsTextForFingerprint(rawSmsText));
}

/**
 * Parses an SMS decimal currency value like "1,234.50" or "500" into integer cents
 * without ever using floating-point arithmetic.
 */
export function parseSmsAmountToCents(rawAmount: string): number | null {
  const cleaned = rawAmount.replace(/,/g, '').trim();
  const match = /^(\d+)(?:\.(\d{1,2}))?$/.exec(cleaned);
  if (!match) return null;
  const whole = Number.parseInt(match[1], 10);
  if (!Number.isSafeInteger(whole)) return null;
  const fracRaw = match[2] ?? '';
  const frac = Number.parseInt(fracRaw.padEnd(2, '0'), 10);
  const cents = whole * 100 + frac;
  return Number.isSafeInteger(cents) ? cents : null;
}

/**
 * Masks an account number or phone hint while retaining at most the final 4 digits.
 * Already-masked strings with '*' keep their suffix safely masked without leaking full digits.
 */
export function maskAccountOrPhoneHint(rawHint: string | null | undefined): string | undefined {
  if (!rawHint) return undefined;
  const trimmed = rawHint.trim().replace(/[.,;:]+$/, '');
  if (!trimmed) return undefined;
  const compact = trimmed.replace(/\s+/g, '');
  if (compact.includes('*')) {
    const trailingDigits = /\*+([0-9]+)$/.exec(compact)?.[1];
    if (trailingDigits && trailingDigits.length > 0) {
      const visible = trailingDigits.slice(-4);
      return `****${visible}`;
    }
    return compact;
  }
  const digitsOnly = compact.replace(/\D/g, '');
  if (digitsOnly.length >= 4) {
    return `****${digitsOnly.slice(-4)}`;
  }
  if (digitsOnly.length >= 2) {
    return `****${digitsOnly}`;
  }
  return trimmed;
}

/**
 * Parses `DD/MM/YYYY HH:MM:SS` explicitly in Africa/Addis_Ababa (UTC+3, no DST)
 * and converts to canonical `YYYY-MM-DD` and UTC ISO-8601 instant.
 */
export function parseAddisAbabaDateTime(
  rawDateTime: string
): { dateIso: string; timestampUtcIso: string } | null {
  const match = /^(\d{2})\/(\d{2})\/(\d{4})\s+(\d{2}):(\d{2}):(\d{2})$/.exec(rawDateTime.trim());
  if (!match) return null;
  const day = Number.parseInt(match[1], 10);
  const month = Number.parseInt(match[2], 10);
  const year = Number.parseInt(match[3], 10);
  const hour = Number.parseInt(match[4], 10);
  const minute = Number.parseInt(match[5], 10);
  const second = Number.parseInt(match[6], 10);

  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59) return null;

  // Validate calendar rollover
  const checkUtc = new Date(Date.UTC(year, month - 1, day, 0, 0, 0));
  if (
    checkUtc.getUTCFullYear() !== year ||
    checkUtc.getUTCMonth() !== month - 1 ||
    checkUtc.getUTCDate() !== day
  ) {
    return null;
  }

  // Convert Africa/Addis_Ababa (UTC+3) local instant to UTC epoch milliseconds
  const utcMs = Date.UTC(year, month - 1, day, hour - 3, minute, second);
  const dateIso = `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  return {
    dateIso,
    timestampUtcIso: new Date(utcMs).toISOString(),
  };
}

/**
 * Extracts receipt URL and query/path transaction reference offline via string parsing only.
 * Never performs any network request.
 */
export function extractReceiptUrlAndRef(rawSmsText: string): {
  receiptUrl?: string;
  queryRef?: string;
} {
  const urlMatch = /(https?:\/\/[^\s"'<>]+)/i.exec(rawSmsText);
  if (!urlMatch) return {};
  const receiptUrl = urlMatch[1].replace(/[.,;)\]]+$/, '');
  const trxMatch = /[?&](?:trx|id|ref)=([A-Za-z0-9._-]+)/i.exec(receiptUrl);
  if (trxMatch?.[1]) {
    return { receiptUrl, queryRef: trxMatch[1] };
  }
  const pathReceiptMatch = /\/receipt\/([A-Za-z0-9._-]+)/i.exec(receiptUrl);
  return {
    receiptUrl,
    ...(pathReceiptMatch?.[1] ? { queryRef: pathReceiptMatch[1] } : {}),
  };
}

function buildDeterministicDraftId(provider: SmsProvider, fingerprint: string, ref?: string): string {
  const suffix = (ref ? sha256HexSync(`${provider}:${ref}:${fingerprint}`) : fingerprint).slice(0, 16);
  return `sms-draft-${provider}-${suffix}`;
}

function cleanCounterpartyName(raw: string | undefined): string | undefined {
  if (!raw) return undefined;
  const cleaned = raw.replace(/\s+/g, ' ').replace(/[.,;]+$/, '').trim();
  return cleaned.length > 0 ? cleaned : undefined;
}

// ============================================================================
// Account & Category Auto-Suggestion Helpers
// ============================================================================

function extractTrailingDigitsHint(rawHint: string | undefined): string | undefined {
  if (!rawHint) return undefined;
  const digits = rawHint.replace(/\D/g, '');
  if (digits.length >= 4) return digits.slice(-4);
  if (digits.length >= 2) return digits;
  return undefined;
}

export function suggestEtbAccountForProvider(
  provider: SmsProvider,
  accounts: Account[],
  accountHint?: string
): string | undefined {
  const spendable = accounts.filter((a) => {
    if (!isActiveVerifiedEtbAccount(a)) return false;
    const sub = getAccountSubType(a);
    return (
      (a.type === 'asset' && sub !== 'savings_vault' && sub !== 'receivable') ||
      (a.type === 'liability' && sub === 'credit_card')
    );
  });
  if (spendable.length === 0) return undefined;

  const keywords: Record<SmsProvider, string[]> = {
    cbe: ['cbe', 'commercial bank'],
    boa: ['boa', 'abyssinia'],
    telebirr: ['telebirr'],
    unknown: [],
  };

  const matches = spendable.filter((acc) => {
    const lower = acc.name.toLowerCase();
    return keywords[provider].some((kw) => lower.includes(kw));
  });
  if (matches.length === 1) return matches[0].id;

  const trailingDigits = extractTrailingDigitsHint(accountHint);
  if (trailingDigits) {
    const pool = matches.length > 0 ? matches : spendable;
    const digitMatches = pool.filter((acc) => acc.name.includes(trailingDigits));
    if (digitMatches.length === 1) return digitMatches[0].id;
  }

  if (provider === 'telebirr') {
    const mobileMoneyAccounts = spendable.filter(
      (a) => getAccountSubType(a) === 'mobile_money'
    );
    if (mobileMoneyAccounts.length === 1) return mobileMoneyAccounts[0].id;
  }

  return undefined;
}

export function suggestTransferDestinationAccount(
  draft: FinanceSmsDraft,
  accounts: Account[]
): string | undefined {
  const transferable = accounts.filter((a) => {
    if (!isActiveVerifiedEtbAccount(a)) return false;
    if (draft.suggestedAccountId && a.id === draft.suggestedAccountId) return false;
    const sub = getAccountSubType(a);
    return (
      (a.type === 'asset' && sub !== 'receivable') ||
      (a.type === 'liability' && sub === 'credit_card')
    );
  });
  if (transferable.length === 0) return undefined;

  const trailingDigits = extractTrailingDigitsHint(draft.counterpartyHint);
  if (trailingDigits) {
    const digitMatches = transferable.filter((acc) => acc.name.includes(trailingDigits));
    if (digitMatches.length === 1) return digitMatches[0].id;
  }

  const cpLower = draft.counterpartyName?.trim().toLowerCase();
  if (cpLower) {
    const nameMatches = transferable.filter((acc) => {
      const accLower = acc.name.trim().toLowerCase();
      return accLower === cpLower || cpLower.includes(accLower) || accLower.includes(cpLower);
    });
    if (nameMatches.length === 1) return nameMatches[0].id;
  }

  return undefined;
}

export function suggestCategoryForDraft(
  suggestedType: SmsSuggestedTransactionType,
  categories: TransactionCategory[]
): string | undefined {
  const active = categories.filter((c) => !c.isArchived);
  if (suggestedType === 'expense') {
    return (
      active.find((c) => c.id === 'cat-other-exp')?.id ??
      active.find((c) => c.type === 'expense')?.id ??
      'cat-other-exp'
    );
  }
  if (suggestedType === 'income') {
    return (
      active.find((c) => c.id === 'cat-other-inc')?.id ??
      active.find((c) => c.type === 'income')?.id ??
      'cat-other-inc'
    );
  }
  return undefined;
}

// ============================================================================
// Provider Detection & Dedicated Per-Provider Parsers
// ============================================================================

export function detectSmsProvider(
  rawSmsText: string,
  providerHint?: SmsProvider
): SmsProvider | null {
  const lower = rawSmsText.toLowerCase();
  if (
    lower.includes('telebirr') ||
    lower.includes('e-money account') ||
    lower.includes('transactioninfo.ethiotelecom.et') ||
    lower.includes('your transaction number is')
  ) {
    return 'telebirr';
  }
  if (
    lower.includes('bank of abyssinia') ||
    lower.includes('cs.bankofabyssinia.com') ||
    lower.includes('was debited with etb') ||
    lower.includes('was credited with etb') ||
    (lower.includes('is locked from your account') && lower.includes('pos transaction'))
  ) {
    return 'boa';
  }
  if (
    lower.includes('commercial bank of ethiopia') ||
    lower.includes('apps.cbe.com.et') ||
    lower.includes('disaster recovery') ||
    /you have successfully transferred etb\s+[0-9,.]+\s+from account/i.test(rawSmsText) ||
    /you have received etb\s+[0-9,.]+\s+from account\s+[0-9*xX]+/i.test(rawSmsText)
  ) {
    return 'cbe';
  }
  return providerHint ?? null;
}

const NON_TRANSACTIONAL_NOISE_MARKERS: readonly string[] = [
  'pin or password is incorrect',
  'pin is incorrect',
  'invalid pin',
  'incorrect pin',
  'wrong pin',
  'wrong password',
  'pin locked',
  'pin blocked',
  'failed login',
  'password will expire',
  'never share your pin',
  'never share your password',
  'do not share your otp',
  'verification code',
  'one time password',
  'otp is',
  'security alert',
  'security tip',
  'download our',
  'special offer',
  'win a',
  'happy holiday',
  'promotion',
];

function hasCompletedTransactionMarker(rawSmsText: string): boolean {
  return (
    /was (?:debited|credited) with etb/i.test(rawSmsText) ||
    /you have successfully transferred etb/i.test(rawSmsText) ||
    /you have (?:transferred|paid|received) etb/i.test(rawSmsText) ||
    (/is locked from your account/i.test(rawSmsText) && /pos transaction/i.test(rawSmsText))
  );
}

function hasNonTransactionalNoiseMarker(rawSmsText: string): boolean {
  if (hasCompletedTransactionMarker(rawSmsText)) return false;
  const lower = rawSmsText.toLowerCase();
  return NON_TRANSACTIONAL_NOISE_MARKERS.some((marker) => lower.includes(marker));
}

function isNonTransactionalNoise(provider: SmsProvider, rawSmsText: string): string | null {
  if (hasNonTransactionalNoiseMarker(rawSmsText)) {
    return `Ignored non-transactional ${SMS_PROVIDER_LABELS[provider]} security/promotional notice.`;
  }
  return null;
}

// ----------------------------------------------------------------------------
// 1. Bank of Abyssinia (BOA) Parser
// ----------------------------------------------------------------------------

export function parseBoaSms(
  rawSmsText: string,
  options: {
    receivedAtUtc: string;
    accounts?: Account[];
    categories?: TransactionCategory[];
  }
): SmsParseOutcome {
  const trimmed = rawSmsText.trim();
  const ignoreReason = isNonTransactionalNoise('boa', trimmed);
  if (ignoreReason) {
    return { kind: 'ignored_non_transactional', provider: 'boa', reason: ignoreReason };
  }

  const fingerprint = computeSmsFingerprint(trimmed);
  const { receiptUrl, queryRef } = extractReceiptUrlAndRef(trimmed);
  const nowIso = options.receivedAtUtc;
  const fallbackAccountId = options.accounts
    ? suggestEtbAccountForProvider('boa', options.accounts)
    : undefined;

  // 1a. BOA POS Locked / Authorization hold — MUST NOT create a normal expense draft!
  if (/is\s+locked\s+from\s+your\s+account/i.test(trimmed) || /pos\s+transaction/i.test(trimmed)) {
    const posMatch =
      /ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)\s+is\s+locked\s+from\s+your\s+account\s+([0-9*xX]+).*?due\s+to\s+pos\s+transaction(?:\s+at\s+([^.\n]+))?(?:\.\s*your\s+available\s+balance\s+is\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?))?/is.exec(
        trimmed
      );
    const lockedAmount = posMatch?.[1] ? (parseSmsAmountToCents(posMatch[1]) ?? 0) : 0;
    const availMatch =
      posMatch?.[4] ??
      (/available\s+balance(?:\s+is|:)\s*ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)/i.exec(trimmed)?.[1] ??
        undefined);
    const reportedBalanceCents = availMatch
      ? (parseSmsAmountToCents(availMatch) ?? undefined)
      : undefined;
    const merchant = cleanCounterpartyName(posMatch?.[3]);
    const accountHint = maskAccountOrPhoneHint(posMatch?.[2]);
    const matchedAccountId = options.accounts
      ? suggestEtbAccountForProvider('boa', options.accounts, accountHint)
      : fallbackAccountId;

    return {
      kind: 'draft',
      provider: 'boa',
      draft: {
        id: buildDeterministicDraftId('boa', fingerprint, queryRef),
        provider: 'boa',
        fingerprint,
        ...(queryRef ? { transactionReference: queryRef } : {}),
        ...(receiptUrl ? { receiptUrl } : {}),
        suggestedType: 'unknown',
        direction: 'uncertain',
        principalCents: lockedAmount,
        serviceFeeCents: 0,
        vatCents: 0,
        otherChargesCents: 0,
        hasAmountMismatch: false,
        currencyCode: 'ETB',
        ...(accountHint ? { accountHint } : {}),
        ...(merchant ? { counterpartyName: merchant } : {}),
        ...(reportedBalanceCents !== undefined ? { reportedBalanceCents } : {}),
        receivedAtUtc: nowIso,
        confidence: 'unrecognized',
        status: 'unrecognized',
        isNonLedgerNotice: true,
        parseNotes:
          'POS authorization lock notice — informational only; not a completed debit and cannot be posted as an expense.',
        ...(matchedAccountId ? { suggestedAccountId: matchedAccountId } : {}),
        rawSmsText: trimmed,
        createdAt: nowIso,
        updatedAt: nowIso,
      },
    };
  }

  // 1b. BOA Debit
  const debitMatch =
    /your\s+account\s+([0-9*xX]+)\s+was\s+debited\s+with\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)(?:\s+(?:for|to|at|by)\s+([^.\n]+?))?(?=\.(?:\s|$)|,\s|https?:|$)/is.exec(
      trimmed
    );
  if (debitMatch) {
    const accountHint = maskAccountOrPhoneHint(debitMatch[1]);
    const matchedAccountId = options.accounts
      ? suggestEtbAccountForProvider('boa', options.accounts, accountHint)
      : fallbackAccountId;
    const principalCents = parseSmsAmountToCents(debitMatch[2]);
    const counterpartyName = cleanCounterpartyName(debitMatch[3]);
    const balanceMatch = /available\s+balance(?:\s+is|:)\s*ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)/i.exec(
      trimmed
    );
    const reportedBalanceCents = balanceMatch?.[1]
      ? (parseSmsAmountToCents(balanceMatch[1]) ?? undefined)
      : undefined;

    if (!principalCents || principalCents <= 0) {
      return {
        kind: 'draft',
        provider: 'boa',
        draft: {
          id: buildDeterministicDraftId('boa', fingerprint, queryRef),
          provider: 'boa',
          fingerprint,
          ...(queryRef ? { transactionReference: queryRef } : {}),
          ...(receiptUrl ? { receiptUrl } : {}),
          suggestedType: 'unknown',
          direction: 'outgoing',
          principalCents: 0,
          serviceFeeCents: 0,
          vatCents: 0,
          otherChargesCents: 0,
          hasAmountMismatch: false,
          currencyCode: 'ETB',
          ...(accountHint ? { accountHint } : {}),
          receivedAtUtc: nowIso,
          confidence: 'unrecognized',
          status: 'unrecognized',
          isNonLedgerNotice: true,
          parseNotes: 'BOA debit message could not parse a positive ETB amount.',
          rawSmsText: trimmed,
          createdAt: nowIso,
          updatedAt: nowIso,
        },
      };
    }

    const suggestedCategoryId = options.categories
      ? suggestCategoryForDraft('expense', options.categories)
      : 'cat-other-exp';

    return {
      kind: 'draft',
      provider: 'boa',
      draft: {
        id: buildDeterministicDraftId('boa', fingerprint, queryRef),
        provider: 'boa',
        fingerprint,
        ...(queryRef ? { transactionReference: queryRef } : {}),
        ...(receiptUrl ? { receiptUrl } : {}),
        suggestedType: 'expense',
        direction: 'outgoing',
        principalCents,
        serviceFeeCents: 0,
        vatCents: 0,
        otherChargesCents: 0,
        totalAmountCents: principalCents,
        hasAmountMismatch: false,
        currencyCode: 'ETB',
        ...(accountHint ? { accountHint } : {}),
        ...(counterpartyName ? { counterpartyName } : {}),
        ...(reportedBalanceCents !== undefined ? { reportedBalanceCents } : {}),
        receivedAtUtc: nowIso,
        confidence: queryRef || reportedBalanceCents !== undefined ? 'high' : 'medium',
        status: 'needs_review',
        isNonLedgerNotice: false,
        ...(matchedAccountId ? { suggestedAccountId: matchedAccountId } : {}),
        ...(suggestedCategoryId ? { suggestedCategoryId } : {}),
        rawSmsText: trimmed,
        createdAt: nowIso,
        updatedAt: nowIso,
      },
    };
  }

  // 1c. BOA Credit
  const creditMatch =
    /your\s+account\s+([0-9*xX]+)\s+was\s+credited\s+with\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)(?:\s+by\s+([^.\n]+?))?(?=\.(?:\s|$)|,\s|https?:|$)/is.exec(
      trimmed
    );
  if (creditMatch) {
    const accountHint = maskAccountOrPhoneHint(creditMatch[1]);
    const matchedAccountId = options.accounts
      ? suggestEtbAccountForProvider('boa', options.accounts, accountHint)
      : fallbackAccountId;
    const principalCents = parseSmsAmountToCents(creditMatch[2]);
    const counterpartyName = cleanCounterpartyName(creditMatch[3]);
    const balanceMatch = /available\s+balance(?:\s+is|:)\s*ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)/i.exec(
      trimmed
    );
    const reportedBalanceCents = balanceMatch?.[1]
      ? (parseSmsAmountToCents(balanceMatch[1]) ?? undefined)
      : undefined;

    if (!principalCents || principalCents <= 0) {
      return {
        kind: 'draft',
        provider: 'boa',
        draft: {
          id: buildDeterministicDraftId('boa', fingerprint, queryRef),
          provider: 'boa',
          fingerprint,
          ...(queryRef ? { transactionReference: queryRef } : {}),
          ...(receiptUrl ? { receiptUrl } : {}),
          suggestedType: 'unknown',
          direction: 'incoming',
          principalCents: 0,
          serviceFeeCents: 0,
          vatCents: 0,
          otherChargesCents: 0,
          hasAmountMismatch: false,
          currencyCode: 'ETB',
          ...(accountHint ? { accountHint } : {}),
          receivedAtUtc: nowIso,
          confidence: 'unrecognized',
          status: 'unrecognized',
          isNonLedgerNotice: true,
          parseNotes: 'BOA credit message could not parse a positive ETB amount.',
          rawSmsText: trimmed,
          createdAt: nowIso,
          updatedAt: nowIso,
        },
      };
    }

    const suggestedCategoryId = options.categories
      ? suggestCategoryForDraft('income', options.categories)
      : 'cat-other-inc';

    return {
      kind: 'draft',
      provider: 'boa',
      draft: {
        id: buildDeterministicDraftId('boa', fingerprint, queryRef),
        provider: 'boa',
        fingerprint,
        ...(queryRef ? { transactionReference: queryRef } : {}),
        ...(receiptUrl ? { receiptUrl } : {}),
        suggestedType: 'income',
        direction: 'incoming',
        principalCents,
        serviceFeeCents: 0,
        vatCents: 0,
        otherChargesCents: 0,
        totalAmountCents: principalCents,
        hasAmountMismatch: false,
        currencyCode: 'ETB',
        ...(accountHint ? { accountHint } : {}),
        ...(counterpartyName ? { counterpartyName } : {}),
        ...(reportedBalanceCents !== undefined ? { reportedBalanceCents } : {}),
        receivedAtUtc: nowIso,
        confidence: queryRef || reportedBalanceCents !== undefined ? 'high' : 'medium',
        status: 'needs_review',
        isNonLedgerNotice: false,
        ...(matchedAccountId ? { suggestedAccountId: matchedAccountId } : {}),
        ...(suggestedCategoryId ? { suggestedCategoryId } : {}),
        rawSmsText: trimmed,
        createdAt: nowIso,
        updatedAt: nowIso,
      },
    };
  }

  return {
    kind: 'draft',
    provider: 'boa',
    draft: {
      id: buildDeterministicDraftId('boa', fingerprint, queryRef),
      provider: 'boa',
      fingerprint,
      ...(queryRef ? { transactionReference: queryRef } : {}),
      ...(receiptUrl ? { receiptUrl } : {}),
      suggestedType: 'unknown',
      direction: 'uncertain',
      principalCents: 0,
      serviceFeeCents: 0,
      vatCents: 0,
      otherChargesCents: 0,
      hasAmountMismatch: false,
      currencyCode: 'ETB',
      receivedAtUtc: nowIso,
      confidence: 'unrecognized',
      status: 'unrecognized',
      isNonLedgerNotice: true,
      parseNotes: 'Unrecognized Bank of Abyssinia message format; saved for review without posting.',
      rawSmsText: trimmed,
      createdAt: nowIso,
      updatedAt: nowIso,
    },
  };
}

// ----------------------------------------------------------------------------
// 2. Commercial Bank of Ethiopia (CBE) Parser
// ----------------------------------------------------------------------------

export function parseCbeSms(
  rawSmsText: string,
  options: {
    receivedAtUtc: string;
    accounts?: Account[];
    categories?: TransactionCategory[];
  }
): SmsParseOutcome {
  const trimmed = rawSmsText.trim();
  const ignoreReason = isNonTransactionalNoise('cbe', trimmed);
  if (ignoreReason) {
    return { kind: 'ignored_non_transactional', provider: 'cbe', reason: ignoreReason };
  }

  const fingerprint = computeSmsFingerprint(trimmed);
  const { receiptUrl, queryRef } = extractReceiptUrlAndRef(trimmed);
  const refTokenMatch = /(?:ref(?:erence)?(?:\s*no\.?)?|trx)\s*[:#]?\s*([A-Za-z0-9_-]{6,})/i.exec(
    trimmed
  );
  const transactionReference = queryRef ?? refTokenMatch?.[1];
  const nowIso = options.receivedAtUtc;
  const fallbackAccountId = options.accounts
    ? suggestEtbAccountForProvider('cbe', options.accounts)
    : undefined;

  // 2a. CBE Outgoing transfer
  const outgoingMatch =
    /you\s+have\s+successfully\s+transferred\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)\s+from\s+account\s+([0-9*xX]+)\s+to\s+(?:account\s+)?([0-9*xX]+)(?:\s*\(([^)]+)\))?/is.exec(
      trimmed
    );
  if (outgoingMatch) {
    const principalCents = parseSmsAmountToCents(outgoingMatch[1]);
    const accountHint = maskAccountOrPhoneHint(outgoingMatch[2]);
    const matchedAccountId = options.accounts
      ? suggestEtbAccountForProvider('cbe', options.accounts, accountHint)
      : fallbackAccountId;
    const counterpartyHint = maskAccountOrPhoneHint(outgoingMatch[3]);
    const counterpartyName = cleanCounterpartyName(outgoingMatch[4]);

    const serviceChargeMatch = /service\s+charge\s+of\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)/i.exec(
      trimmed
    );
    const vatMatch = /VAT(?:\s*\(\s*\d+(?:\.\d+)?%\s*\))?\s+of\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)/i.exec(
      trimmed
    );
    const disasterMatch =
      /Disaster\s+Recovery(?:\s+Fund)?(?:\s*\(\s*\d+(?:\.\d+)?%\s*\))?\s+of\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)/i.exec(
        trimmed
      );
    const totalMatch = /with\s+total\s+of\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)/i.exec(trimmed);
    const balanceMatch = /your\s+current\s+balance\s+is\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)/i.exec(
      trimmed
    );

    if (!principalCents || principalCents <= 0) {
      return {
        kind: 'draft',
        provider: 'cbe',
        draft: {
          id: buildDeterministicDraftId('cbe', fingerprint, transactionReference),
          provider: 'cbe',
          fingerprint,
          ...(transactionReference ? { transactionReference } : {}),
          ...(receiptUrl ? { receiptUrl } : {}),
          suggestedType: 'unknown',
          direction: 'outgoing',
          principalCents: 0,
          serviceFeeCents: 0,
          vatCents: 0,
          otherChargesCents: 0,
          hasAmountMismatch: false,
          currencyCode: 'ETB',
          ...(accountHint ? { accountHint } : {}),
          receivedAtUtc: nowIso,
          confidence: 'unrecognized',
          status: 'unrecognized',
          isNonLedgerNotice: true,
          parseNotes: 'CBE outgoing message could not parse a positive principal ETB amount.',
          rawSmsText: trimmed,
          createdAt: nowIso,
          updatedAt: nowIso,
        },
      };
    }

    const serviceFeeCents = serviceChargeMatch?.[1]
      ? (parseSmsAmountToCents(serviceChargeMatch[1]) ?? 0)
      : 0;
    const vatCents = vatMatch?.[1] ? (parseSmsAmountToCents(vatMatch[1]) ?? 0) : 0;
    const otherChargesCents = disasterMatch?.[1]
      ? (parseSmsAmountToCents(disasterMatch[1]) ?? 0)
      : 0;
    const computedTotalCents = principalCents + serviceFeeCents + vatCents + otherChargesCents;
    const reportedTotalCents = totalMatch?.[1]
      ? (parseSmsAmountToCents(totalMatch[1]) ?? undefined)
      : undefined;
    const hasAmountMismatch =
      reportedTotalCents !== undefined && reportedTotalCents !== computedTotalCents;
    const totalAmountCents = reportedTotalCents ?? computedTotalCents;
    const reportedBalanceCents = balanceMatch?.[1]
      ? (parseSmsAmountToCents(balanceMatch[1]) ?? undefined)
      : undefined;

    const notes: string[] = [];
    if (hasAmountMismatch) {
      notes.push(
        `Amount mismatch: principal + fees (${(computedTotalCents / 100).toFixed(2)} ETB) differs from reported total (${(reportedTotalCents! / 100).toFixed(2)} ETB). Verify before approving.`
      );
    }
    notes.push('Outgoing CBE transfer can be approved as an Expense or an Internal Transfer.');

    const suggestedCategoryId = options.categories
      ? suggestCategoryForDraft('expense', options.categories)
      : 'cat-other-exp';

    return {
      kind: 'draft',
      provider: 'cbe',
      draft: {
        id: buildDeterministicDraftId('cbe', fingerprint, transactionReference),
        provider: 'cbe',
        fingerprint,
        ...(transactionReference ? { transactionReference } : {}),
        ...(receiptUrl ? { receiptUrl } : {}),
        suggestedType: 'expense',
        direction: 'outgoing',
        principalCents,
        serviceFeeCents,
        vatCents,
        otherChargesCents,
        totalAmountCents,
        hasAmountMismatch,
        currencyCode: 'ETB',
        ...(accountHint ? { accountHint } : {}),
        ...(counterpartyName ? { counterpartyName } : {}),
        ...(counterpartyHint ? { counterpartyHint } : {}),
        ...(reportedBalanceCents !== undefined ? { reportedBalanceCents } : {}),
        receivedAtUtc: nowIso,
        confidence: hasAmountMismatch ? 'medium' : 'high',
        status: 'needs_review',
        isNonLedgerNotice: false,
        parseNotes: notes.join(' '),
        ...(matchedAccountId ? { suggestedAccountId: matchedAccountId } : {}),
        ...(suggestedCategoryId ? { suggestedCategoryId } : {}),
        rawSmsText: trimmed,
        createdAt: nowIso,
        updatedAt: nowIso,
      },
    };
  }

  // 2b. CBE Incoming transfer
  const incomingMatch =
    /you\s+have\s+received\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)\s+from\s+account\s+([0-9*xX]+)(?:\s*\(([^)]+)\))?\s+to\s+your\s+account\s+([0-9*xX]+)/is.exec(
      trimmed
    );
  if (incomingMatch) {
    const principalCents = parseSmsAmountToCents(incomingMatch[1]);
    const counterpartyHint = maskAccountOrPhoneHint(incomingMatch[2]);
    const counterpartyName = cleanCounterpartyName(incomingMatch[3]);
    const accountHint = maskAccountOrPhoneHint(incomingMatch[4]);
    const matchedAccountId = options.accounts
      ? suggestEtbAccountForProvider('cbe', options.accounts, accountHint)
      : fallbackAccountId;
    const balanceMatch = /your\s+current\s+balance\s+is\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)/i.exec(
      trimmed
    );
    const reportedBalanceCents = balanceMatch?.[1]
      ? (parseSmsAmountToCents(balanceMatch[1]) ?? undefined)
      : undefined;

    if (!principalCents || principalCents <= 0) {
      return {
        kind: 'draft',
        provider: 'cbe',
        draft: {
          id: buildDeterministicDraftId('cbe', fingerprint, transactionReference),
          provider: 'cbe',
          fingerprint,
          ...(transactionReference ? { transactionReference } : {}),
          ...(receiptUrl ? { receiptUrl } : {}),
          suggestedType: 'unknown',
          direction: 'incoming',
          principalCents: 0,
          serviceFeeCents: 0,
          vatCents: 0,
          otherChargesCents: 0,
          hasAmountMismatch: false,
          currencyCode: 'ETB',
          ...(accountHint ? { accountHint } : {}),
          receivedAtUtc: nowIso,
          confidence: 'unrecognized',
          status: 'unrecognized',
          isNonLedgerNotice: true,
          parseNotes: 'CBE incoming message could not parse a positive ETB amount.',
          rawSmsText: trimmed,
          createdAt: nowIso,
          updatedAt: nowIso,
        },
      };
    }

    const suggestedCategoryId = options.categories
      ? suggestCategoryForDraft('income', options.categories)
      : 'cat-other-inc';

    return {
      kind: 'draft',
      provider: 'cbe',
      draft: {
        id: buildDeterministicDraftId('cbe', fingerprint, transactionReference),
        provider: 'cbe',
        fingerprint,
        ...(transactionReference ? { transactionReference } : {}),
        ...(receiptUrl ? { receiptUrl } : {}),
        suggestedType: 'income',
        direction: 'incoming',
        principalCents,
        serviceFeeCents: 0,
        vatCents: 0,
        otherChargesCents: 0,
        totalAmountCents: principalCents,
        hasAmountMismatch: false,
        currencyCode: 'ETB',
        ...(accountHint ? { accountHint } : {}),
        ...(counterpartyName ? { counterpartyName } : {}),
        ...(counterpartyHint ? { counterpartyHint } : {}),
        ...(reportedBalanceCents !== undefined ? { reportedBalanceCents } : {}),
        receivedAtUtc: nowIso,
        confidence: 'high',
        status: 'needs_review',
        isNonLedgerNotice: false,
        ...(matchedAccountId ? { suggestedAccountId: matchedAccountId } : {}),
        ...(suggestedCategoryId ? { suggestedCategoryId } : {}),
        rawSmsText: trimmed,
        createdAt: nowIso,
        updatedAt: nowIso,
      },
    };
  }

  return {
    kind: 'draft',
    provider: 'cbe',
    draft: {
      id: buildDeterministicDraftId('cbe', fingerprint, transactionReference),
      provider: 'cbe',
      fingerprint,
      ...(transactionReference ? { transactionReference } : {}),
      ...(receiptUrl ? { receiptUrl } : {}),
      suggestedType: 'unknown',
      direction: 'uncertain',
      principalCents: 0,
      serviceFeeCents: 0,
      vatCents: 0,
      otherChargesCents: 0,
      hasAmountMismatch: false,
      currencyCode: 'ETB',
      receivedAtUtc: nowIso,
      confidence: 'unrecognized',
      status: 'unrecognized',
      isNonLedgerNotice: true,
      parseNotes: 'Unrecognized CBE message format; saved for review without posting.',
      rawSmsText: trimmed,
      createdAt: nowIso,
      updatedAt: nowIso,
    },
  };
}

// ----------------------------------------------------------------------------
// 3. Telebirr Parser
// ----------------------------------------------------------------------------

export function parseTelebirrSms(
  rawSmsText: string,
  options: {
    receivedAtUtc: string;
    accounts?: Account[];
    categories?: TransactionCategory[];
  }
): SmsParseOutcome {
  const trimmed = rawSmsText.trim();
  const ignoreReason = isNonTransactionalNoise('telebirr', trimmed);
  if (ignoreReason) {
    return { kind: 'ignored_non_transactional', provider: 'telebirr', reason: ignoreReason };
  }

  const fingerprint = computeSmsFingerprint(trimmed);
  const { receiptUrl, queryRef } = extractReceiptUrlAndRef(trimmed);
  const txNoMatch = /your\s+transaction\s+number\s+is\s+([A-Za-z0-9_-]+)/i.exec(trimmed);
  const transactionReference = txNoMatch?.[1] ?? queryRef;
  const nowIso = options.receivedAtUtc;
  const matchedAccountId = options.accounts
    ? suggestEtbAccountForProvider('telebirr', options.accounts)
    : undefined;

  // 3a. Telebirr Outgoing (transferred / paid)
  const outgoingMatch =
    /you\s+have\s+(?:transferred|paid)\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)\s+to\s+(?:(.+?)\s*\(([^)]+)\)|(.+?))\s+on\s+(\d{2}\/\d{2}\/\d{4}\s+\d{2}:\d{2}:\d{2})/is.exec(
      trimmed
    );
  if (outgoingMatch) {
    const principalCents = parseSmsAmountToCents(outgoingMatch[1]);
    const counterpartyName = cleanCounterpartyName(outgoingMatch[2] ?? outgoingMatch[4]);
    const counterpartyHint = maskAccountOrPhoneHint(outgoingMatch[3]);
    const parsedDt = parseAddisAbabaDateTime(outgoingMatch[5]);

    const serviceFeeMatch =
      /(?:the\s+)?service\s+fee\s+(?:is|of)\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)/i.exec(trimmed);
    const vatMatch =
      /(?:\d+(?:\.\d+)?%\s+)?VAT(?:\s+on\s+(?:the\s+)?service\s+fee)?\s+(?:is|of)\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)/i.exec(
        trimmed
      );
    const totalPaidMatch =
      /(?:with\s+)?(?:the\s+)?total(?:\s+(?:paid|deducted|amount))?(?:\s+is|\s+of)\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)/i.exec(
        trimmed
      );
    const balanceMatch =
      /your\s+current\s+(?:E-Money\s+Account\s+)?balance\s+is\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)/i.exec(
        trimmed
      );

    if (!principalCents || principalCents <= 0) {
      return {
        kind: 'draft',
        provider: 'telebirr',
        draft: {
          id: buildDeterministicDraftId('telebirr', fingerprint, transactionReference),
          provider: 'telebirr',
          fingerprint,
          ...(transactionReference ? { transactionReference } : {}),
          ...(receiptUrl ? { receiptUrl } : {}),
          suggestedType: 'unknown',
          direction: 'outgoing',
          principalCents: 0,
          serviceFeeCents: 0,
          vatCents: 0,
          otherChargesCents: 0,
          hasAmountMismatch: false,
          currencyCode: 'ETB',
          accountHint: 'Telebirr',
          receivedAtUtc: nowIso,
          confidence: 'unrecognized',
          status: 'unrecognized',
          isNonLedgerNotice: true,
          parseNotes: 'Telebirr outgoing message could not parse a positive principal ETB amount.',
          rawSmsText: trimmed,
          createdAt: nowIso,
          updatedAt: nowIso,
        },
      };
    }

    const serviceFeeCents = serviceFeeMatch?.[1]
      ? (parseSmsAmountToCents(serviceFeeMatch[1]) ?? 0)
      : 0;
    const vatCents = vatMatch?.[1] ? (parseSmsAmountToCents(vatMatch[1]) ?? 0) : 0;
    const computedTotalCents = principalCents + serviceFeeCents + vatCents;
    const reportedTotalCents = totalPaidMatch?.[1]
      ? (parseSmsAmountToCents(totalPaidMatch[1]) ?? undefined)
      : undefined;
    const hasAmountMismatch =
      reportedTotalCents !== undefined && reportedTotalCents !== computedTotalCents;
    const totalAmountCents = reportedTotalCents ?? computedTotalCents;
    const reportedBalanceCents = balanceMatch?.[1]
      ? (parseSmsAmountToCents(balanceMatch[1]) ?? undefined)
      : undefined;

    const suggestedCategoryId = options.categories
      ? suggestCategoryForDraft('expense', options.categories)
      : 'cat-other-exp';

    return {
      kind: 'draft',
      provider: 'telebirr',
      draft: {
        id: buildDeterministicDraftId('telebirr', fingerprint, transactionReference),
        provider: 'telebirr',
        fingerprint,
        ...(transactionReference ? { transactionReference } : {}),
        ...(receiptUrl ? { receiptUrl } : {}),
        suggestedType: 'expense',
        direction: 'outgoing',
        principalCents,
        serviceFeeCents,
        vatCents,
        otherChargesCents: 0,
        totalAmountCents,
        hasAmountMismatch,
        currencyCode: 'ETB',
        accountHint: 'Telebirr',
        ...(counterpartyName ? { counterpartyName } : {}),
        ...(counterpartyHint ? { counterpartyHint } : {}),
        ...(reportedBalanceCents !== undefined ? { reportedBalanceCents } : {}),
        ...(parsedDt ? { transactionTimestampIso: parsedDt.timestampUtcIso } : {}),
        ...(parsedDt ? { transactionDateIso: parsedDt.dateIso } : {}),
        receivedAtUtc: nowIso,
        confidence: hasAmountMismatch
          ? 'medium'
          : transactionReference && parsedDt
            ? 'high'
            : 'medium',
        status: 'needs_review',
        isNonLedgerNotice: false,
        ...(hasAmountMismatch
          ? {
              parseNotes: `Amount mismatch: principal + fees (${(computedTotalCents / 100).toFixed(2)} ETB) differs from reported total (${(reportedTotalCents! / 100).toFixed(2)} ETB). Verify before approving.`,
            }
          : {}),
        ...(matchedAccountId ? { suggestedAccountId: matchedAccountId } : {}),
        ...(suggestedCategoryId ? { suggestedCategoryId } : {}),
        rawSmsText: trimmed,
        createdAt: nowIso,
        updatedAt: nowIso,
      },
    };
  }

  // 3b. Telebirr Incoming
  const incomingMatch =
    /you\s+have\s+received\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)\s+from\s+(?:(.+?)\s*\(([^)]+)\)|(.+?))\s+on\s+(\d{2}\/\d{2}\/\d{4}\s+\d{2}:\d{2}:\d{2})/is.exec(
      trimmed
    );
  if (incomingMatch) {
    const principalCents = parseSmsAmountToCents(incomingMatch[1]);
    const counterpartyName = cleanCounterpartyName(incomingMatch[2] ?? incomingMatch[4]);
    const counterpartyHint = maskAccountOrPhoneHint(incomingMatch[3]);
    const parsedDt = parseAddisAbabaDateTime(incomingMatch[5]);
    const balanceMatch =
      /your\s+current\s+(?:E-Money\s+Account\s+)?balance\s+is\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)/i.exec(
        trimmed
      );
    const reportedBalanceCents = balanceMatch?.[1]
      ? (parseSmsAmountToCents(balanceMatch[1]) ?? undefined)
      : undefined;

    if (!principalCents || principalCents <= 0) {
      return {
        kind: 'draft',
        provider: 'telebirr',
        draft: {
          id: buildDeterministicDraftId('telebirr', fingerprint, transactionReference),
          provider: 'telebirr',
          fingerprint,
          ...(transactionReference ? { transactionReference } : {}),
          ...(receiptUrl ? { receiptUrl } : {}),
          suggestedType: 'unknown',
          direction: 'incoming',
          principalCents: 0,
          serviceFeeCents: 0,
          vatCents: 0,
          otherChargesCents: 0,
          hasAmountMismatch: false,
          currencyCode: 'ETB',
          accountHint: 'Telebirr',
          receivedAtUtc: nowIso,
          confidence: 'unrecognized',
          status: 'unrecognized',
          isNonLedgerNotice: true,
          parseNotes: 'Telebirr incoming message could not parse a positive ETB amount.',
          rawSmsText: trimmed,
          createdAt: nowIso,
          updatedAt: nowIso,
        },
      };
    }

    const suggestedCategoryId = options.categories
      ? suggestCategoryForDraft('income', options.categories)
      : 'cat-other-inc';

    return {
      kind: 'draft',
      provider: 'telebirr',
      draft: {
        id: buildDeterministicDraftId('telebirr', fingerprint, transactionReference),
        provider: 'telebirr',
        fingerprint,
        ...(transactionReference ? { transactionReference } : {}),
        ...(receiptUrl ? { receiptUrl } : {}),
        suggestedType: 'income',
        direction: 'incoming',
        principalCents,
        serviceFeeCents: 0,
        vatCents: 0,
        otherChargesCents: 0,
        totalAmountCents: principalCents,
        hasAmountMismatch: false,
        currencyCode: 'ETB',
        accountHint: 'Telebirr',
        ...(counterpartyName ? { counterpartyName } : {}),
        ...(counterpartyHint ? { counterpartyHint } : {}),
        ...(reportedBalanceCents !== undefined ? { reportedBalanceCents } : {}),
        ...(parsedDt ? { transactionTimestampIso: parsedDt.timestampUtcIso } : {}),
        ...(parsedDt ? { transactionDateIso: parsedDt.dateIso } : {}),
        receivedAtUtc: nowIso,
        confidence: transactionReference && parsedDt ? 'high' : 'medium',
        status: 'needs_review',
        isNonLedgerNotice: false,
        ...(matchedAccountId ? { suggestedAccountId: matchedAccountId } : {}),
        ...(suggestedCategoryId ? { suggestedCategoryId } : {}),
        rawSmsText: trimmed,
        createdAt: nowIso,
        updatedAt: nowIso,
      },
    };
  }

  return {
    kind: 'draft',
    provider: 'telebirr',
    draft: {
      id: buildDeterministicDraftId('telebirr', fingerprint, transactionReference),
      provider: 'telebirr',
      fingerprint,
      ...(transactionReference ? { transactionReference } : {}),
      ...(receiptUrl ? { receiptUrl } : {}),
      suggestedType: 'unknown',
      direction: 'uncertain',
      principalCents: 0,
      serviceFeeCents: 0,
      vatCents: 0,
      otherChargesCents: 0,
      hasAmountMismatch: false,
      currencyCode: 'ETB',
      accountHint: 'Telebirr',
      receivedAtUtc: nowIso,
      confidence: 'unrecognized',
      status: 'unrecognized',
      isNonLedgerNotice: true,
      parseNotes: 'Unrecognized Telebirr message format; saved for review without posting.',
      rawSmsText: trimmed,
      createdAt: nowIso,
      updatedAt: nowIso,
    },
  };
}

// ----------------------------------------------------------------------------
// Orchestrator & Deduplication Foundation
// ----------------------------------------------------------------------------

export function parseFinancialSmsMessage(
  rawSmsText: string,
  options: {
    providerHint?: SmsProvider;
    receivedAtUtc: string;
    accounts?: Account[];
    categories?: TransactionCategory[];
  }
): SmsParseOutcome {
  const trimmed = rawSmsText.trim();
  if (!trimmed) {
    return {
      kind: 'ignored_non_transactional',
      reason: 'Empty SMS message.',
    };
  }

  const detected = detectSmsProvider(trimmed, options.providerHint);
  if (!detected) {
    const fingerprint = computeSmsFingerprint(trimmed);
    const { receiptUrl, queryRef } = extractReceiptUrlAndRef(trimmed);
    // Still check generic security/PIN/OTP/promo noise
    if (hasNonTransactionalNoiseMarker(trimmed)) {
      return {
        kind: 'ignored_non_transactional',
        reason: 'Ignored non-transactional security/PIN/OTP message.',
      };
    }
    return {
      kind: 'draft',
      draft: {
        id: buildDeterministicDraftId('unknown', fingerprint, queryRef),
        provider: 'unknown',
        fingerprint,
        ...(queryRef ? { transactionReference: queryRef } : {}),
        ...(receiptUrl ? { receiptUrl } : {}),
        suggestedType: 'unknown',
        direction: 'uncertain',
        principalCents: 0,
        serviceFeeCents: 0,
        vatCents: 0,
        otherChargesCents: 0,
        hasAmountMismatch: false,
        currencyCode: 'ETB',
        receivedAtUtc: options.receivedAtUtc,
        confidence: 'unrecognized',
        status: 'unrecognized',
        isNonLedgerNotice: true,
        parseNotes:
          'Unable to identify provider (CBE, Telebirr, or BOA). Select a provider or verify message text.',
        rawSmsText: trimmed,
        createdAt: options.receivedAtUtc,
        updatedAt: options.receivedAtUtc,
      },
    };
  }

  switch (detected) {
    case 'boa':
      return parseBoaSms(trimmed, options);
    case 'cbe':
      return parseCbeSms(trimmed, options);
    case 'telebirr':
      return parseTelebirrSms(trimmed, options);
    case 'unknown':
      return {
        kind: 'draft',
        provider: 'unknown',
        draft: {
          id: buildDeterministicDraftId(
            'unknown',
            computeSmsFingerprint(trimmed),
            extractReceiptUrlAndRef(trimmed).queryRef
          ),
          provider: 'unknown',
          fingerprint: computeSmsFingerprint(trimmed),
          suggestedType: 'unknown',
          direction: 'uncertain',
          principalCents: 0,
          serviceFeeCents: 0,
          vatCents: 0,
          otherChargesCents: 0,
          hasAmountMismatch: false,
          currencyCode: 'ETB',
          receivedAtUtc: options.receivedAtUtc,
          confidence: 'unrecognized',
          status: 'unrecognized',
          isNonLedgerNotice: true,
          parseNotes:
            'Unable to identify provider (CBE, Telebirr, or BOA). Select a provider or verify message text.',
          rawSmsText: trimmed,
          createdAt: options.receivedAtUtc,
          updatedAt: options.receivedAtUtc,
        },
      };
  }
}

export function findDuplicateSmsDraft(
  candidate: FinanceSmsDraft,
  existingDrafts: FinanceSmsDraft[]
): SmsDeduplicationResult {
  const candidateRef = candidate.transactionReference?.trim().toLowerCase();
  if (candidateRef) {
    const refMatch = existingDrafts.find(
      (d) =>
        d.provider === candidate.provider &&
        d.transactionReference?.trim().toLowerCase() === candidateRef
    );
    if (refMatch) {
      return {
        isDuplicate: true,
        existingDraft: refMatch,
        matchedBy: 'provider_reference',
      };
    }
  }

  const fpMatch = existingDrafts.find((d) => d.fingerprint === candidate.fingerprint);
  if (fpMatch) {
    return {
      isDuplicate: true,
      existingDraft: fpMatch,
      matchedBy: 'fingerprint',
    };
  }

  return { isDuplicate: false };
}

export function totalDraftFeesCents(draft: FinanceSmsDraft): number {
  return draft.serviceFeeCents + draft.vatCents + draft.otherChargesCents;
}

function formatCentsFixed(cents: number): string {
  const whole = Math.floor(cents / 100);
  const frac = String(cents % 100).padStart(2, '0');
  return `${whole}.${frac}`;
}

export function formatSmsFeeBreakdownNote(
  draft: FinanceSmsDraft,
  defaultLabel: string
): string {
  const parts: string[] = [];
  if (draft.serviceFeeCents > 0) {
    parts.push(`Service fee: ETB ${formatCentsFixed(draft.serviceFeeCents)}`);
  }
  if (draft.vatCents > 0) {
    parts.push(`VAT: ETB ${formatCentsFixed(draft.vatCents)}`);
  }
  if (draft.otherChargesCents > 0) {
    parts.push(`Disaster Recovery / Other: ETB ${formatCentsFixed(draft.otherChargesCents)}`);
  }
  if (parts.length === 0) return defaultLabel;
  return `${defaultLabel} (${parts.join(', ')})`;
}

export function canApproveSmsDraft(draft: FinanceSmsDraft): { ok: boolean; error?: string } {
  if (draft.status === 'approved') {
    return { ok: false, error: 'This SMS draft has already been approved and posted to the ledger.' };
  }
  if (draft.status === 'dismissed') {
    return { ok: false, error: 'Dismissed SMS drafts cannot be approved directly.' };
  }
  if (draft.status === 'unrecognized' || draft.isNonLedgerNotice || draft.suggestedType === 'unknown') {
    return {
      ok: false,
      error:
        draft.parseNotes ||
        'Informational or unrecognized SMS notices cannot be posted automatically.',
    };
  }
  if (draft.principalCents <= 0) {
    return { ok: false, error: 'Draft principal amount must be greater than zero ETB.' };
  }
  return { ok: true };
}

export function buildDefaultDraftDescription(draft: FinanceSmsDraft): string {
  const providerLabel = SMS_PROVIDER_LABELS[draft.provider];
  const refPart = draft.transactionReference ? ` (${draft.transactionReference})` : '';
  if (draft.counterpartyName) {
    if (draft.direction === 'incoming') {
      return `${providerLabel} from ${draft.counterpartyName}${refPart}`;
    }
    return `${providerLabel} to ${draft.counterpartyName}${refPart}`;
  }
  if (draft.direction === 'incoming') {
    return `${providerLabel} credit${refPart}`;
  }
  if (draft.direction === 'outgoing') {
    return `${providerLabel} debit${refPart}`;
  }
  return `${providerLabel} SMS${refPart}`;
}

export const SMS_FEE_DEFAULT_CATEGORY_ID = 'cat-fees';

export function resolveDefaultDraftOccurrenceDate(draft: FinanceSmsDraft): string {
  const explicit = draft.transactionDateIso ? CalendarDate.tryParse(draft.transactionDateIso) : null;
  if (explicit) return explicit.toIsoString();

  const receivedMs = Date.parse(draft.receivedAtUtc);
  if (Number.isFinite(receivedMs)) {
    const addis = new Date(receivedMs + 3 * 60 * 60 * 1000);
    const y = String(addis.getUTCFullYear()).padStart(4, '0');
    const m = String(addis.getUTCMonth() + 1).padStart(2, '0');
    const d = String(addis.getUTCDate()).padStart(2, '0');
    const parsed = CalendarDate.tryParse(`${y}-${m}-${d}`);
    if (parsed) return parsed.toIsoString();
  }
  return CalendarDate.today().toIsoString();
}

export interface SmsDraftApprovalInput {
  draft: FinanceSmsDraft;
  finalType: 'expense' | 'income' | 'transfer';
  accountId: string;
  destinationAccountId?: string;
  categoryId?: string;
  feeCategoryId?: string;
  occurrenceDate: string;
  movementDate?: string;
  description: string;
  payee?: string;
  entryId: string;
  accounts: Account[];
  categories: TransactionCategory[];
  nowIso?: string;
}

export interface SmsDraftApprovalBuildResult {
  updatedDraft: FinanceSmsDraft;
  entry: JournalEntry;
  postings: Posting[];
  simpleTx: SimpleTransaction;
  feeCategoryToAdd?: TransactionCategory;
}

function assertSpendableEtbAccount(account: Account | undefined, roleLabel: string): void {
  if (!account || !isActiveVerifiedEtbAccount(account)) {
    throw new DoubleEntryValidationError(
      `${roleLabel} must be an active, verified ETB account.`
    );
  }
  const sub = getAccountSubType(account);
  const isSpendable =
    (account.type === 'asset' && sub !== 'savings_vault' && sub !== 'receivable') ||
    (account.type === 'liability' && sub === 'credit_card');
  if (!isSpendable) {
    throw new DoubleEntryValidationError(
      `${roleLabel} "${account.name}" cannot be used for direct income/expense; select an active ETB liquid asset or credit card account (Savings Vaults are allowed in Transfers only).`
    );
  }
}

function assertTransferableEtbAccount(account: Account | undefined, roleLabel: string): void {
  if (!account || !isActiveVerifiedEtbAccount(account)) {
    throw new DoubleEntryValidationError(
      `${roleLabel} must be an active, verified ETB account.`
    );
  }
  const sub = getAccountSubType(account);
  const isTransferable =
    (account.type === 'asset' && sub !== 'receivable') ||
    (account.type === 'liability' && sub === 'credit_card');
  if (!isTransferable) {
    throw new DoubleEntryValidationError(
      `${roleLabel} "${account.name}" cannot participate in an ETB transfer.`
    );
  }
}

/**
 * Pure atomic builder converting an explicitly approved SMS draft into a balanced
 * double-entry ledger transaction. NEVER copies rawSmsText into ledger entries/notes.
 */
export function buildApprovedSmsLedgerEntry(
  input: SmsDraftApprovalInput
): SmsDraftApprovalBuildResult {
  const { draft } = input;
  const check = canApproveSmsDraft({
    ...draft,
    suggestedType: input.finalType,
  });
  if (!check.ok) {
    throw new DoubleEntryValidationError(check.error || 'SMS draft cannot be approved.');
  }
  if (draft.status !== 'needs_review' || draft.isNonLedgerNotice) {
    throw new DoubleEntryValidationError(
      'Only pending financial drafts can be approved and posted.'
    );
  }
  const occCal = CalendarDate.tryParse(input.occurrenceDate);
  if (!occCal) {
    throw new DoubleEntryValidationError('Occurrence date must be a valid YYYY-MM-DD date.');
  }
  const movCal = input.movementDate ? CalendarDate.tryParse(input.movementDate) : occCal;
  if (!movCal) {
    throw new DoubleEntryValidationError('Movement date must be a valid YYYY-MM-DD date.');
  }
  const occurrenceIso = occCal.toIsoString();
  const movementIso = movCal.toIsoString();
  const nowIso = input.nowIso ?? EthiopiaClock.nowUtc().toISOString();
  const feesCents = totalDraftFeesCents(draft);

  const accountById = new Map(input.accounts.map((a) => [a.id, a]));
  const primaryAcc = accountById.get(input.accountId);
  const cleanDesc = input.description.trim() || buildDefaultDraftDescription(draft);
  const cleanPayee =
    input.payee?.trim() ||
    (input.finalType !== 'transfer' ? draft.counterpartyName?.trim() : undefined) ||
    undefined;
  const formattedDesc =
    cleanPayee && cleanDesc !== cleanPayee && !cleanDesc.startsWith(`${cleanPayee} — `)
      ? `${cleanPayee} — ${cleanDesc}`
      : cleanDesc;

  let feeCategoryToAdd: TransactionCategory | undefined;
  const effectiveFeeCategoryId =
    feesCents > 0
      ? (input.feeCategoryId?.trim() || SMS_FEE_DEFAULT_CATEGORY_ID)
      : undefined;

  if (
    effectiveFeeCategoryId === SMS_FEE_DEFAULT_CATEGORY_ID &&
    !input.categories.some((c) => c.id === SMS_FEE_DEFAULT_CATEGORY_ID)
  ) {
    feeCategoryToAdd = {
      id: SMS_FEE_DEFAULT_CATEGORY_ID,
      name: 'Financial Fees',
      type: 'expense',
      colorHex:
        DEFAULT_EXPENSE_CATEGORIES.find((c) => c.id === SMS_FEE_DEFAULT_CATEGORY_ID)?.colorHex ??
        SHARED_DESIGN_TOKENS.colors.text.mutedLight,
      isArchived: false,
    };
  }

  let entry: JournalEntry;
  let postings: Posting[];
  let simpleTx: SimpleTransaction;
  let updatedCategoryId: string | undefined = input.categoryId;

  if (input.finalType === 'transfer') {
    if (!input.destinationAccountId) {
      throw new DoubleEntryValidationError('Destination account is required for a transfer.');
    }
    if (input.accountId === input.destinationAccountId) {
      throw new DoubleEntryValidationError(
        'Source and destination accounts must be distinct.'
      );
    }
    assertEtbPostingAccounts({
      accounts: input.accounts,
      accountIds: [input.accountId, input.destinationAccountId],
      roleLabels: ['Source account', 'Destination account'],
    });
    assertTransferableEtbAccount(primaryAcc, 'Source account');
    assertTransferableEtbAccount(
      accountById.get(input.destinationAccountId),
      'Destination account'
    );

    const built = buildTransfer({
      id: input.entryId,
      fromAssetAccountId: input.accountId,
      toAssetAccountId: input.destinationAccountId,
      amountCents: draft.principalCents,
      date: occurrenceIso,
      movementDate: movementIso,
      description: cleanDesc,
      transferFeeCents: feesCents,
      feeExpenseAccountId: feesCents > 0 ? SYSTEM_CONTROL_ACCOUNT_IDS.expense : undefined,
      feeCategoryId: effectiveFeeCategoryId,
    });
    entry = {
      ...built.entry,
      legacySourceTxId: `tx-${input.entryId}`,
    };
    postings =
      feesCents > 0
        ? built.postings.map((p) =>
            p.id.endsWith('-dr-fee') || p.id.endsWith('-post-dr-fee')
              ? { ...p, note: formatSmsFeeBreakdownNote(draft, p.note || 'Transfer service fee') }
              : p
          )
        : built.postings;
    simpleTx = {
      id: `tx-${input.entryId}`,
      type: 'transfer',
      amountCents: draft.principalCents,
      accountId: input.accountId,
      destinationAccountId: input.destinationAccountId,
      categoryId: effectiveFeeCategoryId,
      description: cleanDesc,
      transactionDate: occurrenceIso,
      createdAt: nowIso,
      updatedAt: nowIso,
      journalEntryId: input.entryId,
    };
    updatedCategoryId = undefined;
  } else if (input.finalType === 'income') {
    assertEtbPostingAccounts({
      accounts: input.accounts,
      accountIds: [input.accountId],
      roleLabels: ['Deposit account'],
    });
    assertSpendableEtbAccount(primaryAcc, 'Deposit account');
    const resolvedCatId = input.categoryId?.trim() || 'cat-other-inc';
    updatedCategoryId = resolvedCatId;

    const built = buildDirectIncome({
      id: input.entryId,
      assetAccountId: input.accountId,
      incomeAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.income,
      categoryId: resolvedCatId,
      amountCents: draft.principalCents,
      occurrenceDate: occurrenceIso,
      movementDate: movementIso,
      description: formattedDesc,
    });
    entry = {
      ...built.entry,
      legacySourceTxId: `tx-${input.entryId}`,
    };
    postings = built.postings;
    simpleTx = {
      id: `tx-${input.entryId}`,
      type: 'income',
      amountCents: draft.principalCents,
      accountId: input.accountId,
      categoryId: resolvedCatId,
      description: formattedDesc,
      payee: cleanPayee,
      transactionDate: occurrenceIso,
      createdAt: nowIso,
      updatedAt: nowIso,
      journalEntryId: input.entryId,
    };
  } else {
    assertEtbPostingAccounts({
      accounts: input.accounts,
      accountIds: [input.accountId],
      roleLabels: ['Paid account'],
    });
    assertSpendableEtbAccount(primaryAcc, 'Paid account');
    const resolvedCatId = input.categoryId?.trim() || 'cat-other-exp';
    updatedCategoryId = resolvedCatId;

    const built = buildDirectExpense({
      id: input.entryId,
      assetAccountId: input.accountId,
      expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
      categoryId: resolvedCatId,
      amountCents: draft.principalCents,
      feeCents: feesCents,
      feeExpenseAccountId: feesCents > 0 ? SYSTEM_CONTROL_ACCOUNT_IDS.expense : undefined,
      feeCategoryId: effectiveFeeCategoryId,
      occurrenceDate: occurrenceIso,
      movementDate: movementIso,
      description: formattedDesc,
    });
    entry = {
      ...built.entry,
      legacySourceTxId: `tx-${input.entryId}`,
    };
    postings =
      feesCents > 0
        ? built.postings.map((p) =>
            p.id.endsWith('-dr-fee') || p.id.endsWith('-post-dr-fee')
              ? { ...p, note: formatSmsFeeBreakdownNote(draft, p.note || 'Bank / transaction fee') }
              : p
          )
        : built.postings;
    simpleTx = {
      id: `tx-${input.entryId}`,
      type: 'expense',
      amountCents: draft.principalCents,
      accountId: input.accountId,
      categoryId: resolvedCatId,
      description: formattedDesc,
      payee: cleanPayee,
      transactionDate: occurrenceIso,
      createdAt: nowIso,
      updatedAt: nowIso,
      journalEntryId: input.entryId,
    };
  }

  const updatedDraft: FinanceSmsDraft = {
    ...draft,
    suggestedType: input.finalType,
    suggestedAccountId: input.accountId,
    ...(updatedCategoryId ? { suggestedCategoryId: updatedCategoryId } : {}),
    status: 'approved',
    approvedEntryId: entry.id,
    updatedAt: nowIso,
  };

  return {
    updatedDraft,
    entry,
    postings,
    simpleTx,
    ...(feeCategoryToAdd ? { feeCategoryToAdd } : {}),
  };
}
