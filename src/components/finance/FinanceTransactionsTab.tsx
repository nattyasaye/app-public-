import React, { useMemo, useState } from 'react';
import { Plus, X, RotateCcw, Edit3, Ban, ReceiptText, CornerDownLeft } from 'lucide-react';
import {
  Account,
  canCorrectJournalEntryV7,
  classifyAllJournalEntries,
  Debt,
  findCategoryByIdOrAlias,
  formatCurrencyCents,
  getAccountSubType,
  getExpenseRefundSummaryV7,
  isActiveVerifiedEtbAccount,
  isRefundEntry,
  JournalEntry,
  Posting,
  resolveCategoryDisplayName,
  SettlementAllocation,
  SharedCommitmentSettlement,
  SimpleTransaction,
  TransactionCategory,
} from '../../domain/financeV7Engine';
import { CalendarDate } from '../../domain/date';
import { SYSTEM_CONTROL_ACCOUNT_IDS } from '../../domain/sharedFoundation';
import {
  centsToInputText,
  ComposerKind,
  FinanceComposerPrefill,
  formatDualDateLabel,
  tryParseStrictDecimalToCents,
} from './financeV7Types';
import {
  DaywellButton,
  DaywellCard,
  DaywellEmptyState,
  DaywellIconButton,
  DaywellSearchField,
  DaywellStatusBadge,
  DaywellStatusBanner,
} from '../ui';

interface FinanceTransactionsTabProps {
  entries: JournalEntry[];
  postings: Posting[];
  accounts: Account[];
  categories: TransactionCategory[];
  debts?: Debt[];
  allocations?: SettlementAllocation[];
  commitmentSettlements?: SharedCommitmentSettlement[];
  simpleTransactions?: SimpleTransaction[];
  onOpenComposer: (
    kind: ComposerKind,
    correctedFromEntryId?: string,
    prefill?: Omit<FinanceComposerPrefill, 'nonce' | 'kind' | 'correctedFromEntryId'>
  ) => void;
  onVoidEntry: (entryId: string, reason: string) => { ok: boolean; error?: string } | void;
  onRestoreEntry: (entryId: string) => { ok: boolean; error?: string } | void;
  onRefundExpense?: (payload: {
    originalEntryId: string;
    refundAccountId: string;
    refundCents: number;
    refundDateIso: string;
    note?: string;
  }) => { ok: boolean; error?: string };
  onRequestConfirm: (
    title: string,
    message: string,
    confirmLabel: string,
    tone: 'danger' | 'primary',
    onConfirm: () => void
  ) => void;
}

export function FinanceTransactionsTab({
  entries,
  postings,
  accounts,
  categories,
  debts = [],
  allocations = [],
  commitmentSettlements = [],
  simpleTransactions = [],
  onOpenComposer,
  onVoidEntry,
  onRestoreEntry,
  onRefundExpense,
  onRequestConfirm,
}: FinanceTransactionsTabProps) {
  const [query, setQuery] = useState('');
  const [typeFilter, setTypeFilter] = useState<string>('all');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [accountFilter, setAccountFilter] = useState<string>('all');
  const [datePreset, setDatePreset] = useState<'all' | 'today' | 'week' | 'month' | 'custom'>('all');
  const [customStart, setCustomStart] = useState('');
  const [customEnd, setCustomEnd] = useState('');
  const [showVoided, setShowVoided] = useState(false);
  const [inspectEntry, setInspectEntry] = useState<JournalEntry | null>(null);
  const [inspectError, setInspectError] = useState<string | null>(null);

  // Refund Expense modal state
  const [refundTargetEntry, setRefundTargetEntry] = useState<JournalEntry | null>(null);
  const [refundAccId, setRefundAccId] = useState('');
  const [refundAmtStr, setRefundAmtStr] = useState('');
  const [refundDate, setRefundDate] = useState(CalendarDate.today().toIsoString());
  const [refundNote, setRefundNote] = useState('');
  const [refundError, setRefundError] = useState<string | null>(null);

  const refundableEtbAccounts = useMemo(
    () =>
      accounts.filter((a) => {
        if (!isActiveVerifiedEtbAccount(a)) return false;
        const sub = getAccountSubType(a);
        return (
          (a.type === 'asset' && sub !== 'savings_vault' && sub !== 'receivable') ||
          (a.type === 'liability' && sub === 'credit_card')
        );
      }),
    [accounts]
  );

  const accountById = useMemo(() => new Map(accounts.map((a) => [a.id, a])), [accounts]);
  const userAccounts = useMemo(() => accounts.filter((a) => !a.isSystem), [accounts]);

  const postingsByEntry = useMemo(() => {
    const map = new Map<string, Posting[]>();
    for (const p of postings) {
      const list = map.get(p.entryId) || [];
      list.push(p);
      map.set(p.entryId, list);
    }
    return map;
  }, [postings]);

  const classificationsByEntryId = useMemo(
    () =>
      classifyAllJournalEntries({
        accounts,
        entries,
        postings,
        debts,
        allocations,
      }),
    [accounts, entries, postings, debts, allocations]
  );

  const filteredEntries = useMemo(() => {
    const today = CalendarDate.today();
    const todayIso = today.toIsoString();
    const weekStartIso = today.subtractDays(today.weekday - 1).toIsoString();
    const weekEndIso = today.addDays(7 - today.weekday).toIsoString();
    const monthStartIso = today.startOfGregorianMonth.toIsoString();
    const monthEndIso = today.endOfGregorianMonth.toIsoString();
    const q = query.trim().toLowerCase();

    return [...entries]
      .sort((a, b) => {
        if (a.occurrenceDate !== b.occurrenceDate) {
          return b.occurrenceDate.localeCompare(a.occurrenceDate);
        }
        return (b.createdAt || '').localeCompare(a.createdAt || '');
      })
      .filter((entry) => {
        if (!showVoided && entry.isVoided) return false;
        if (typeFilter !== 'all' && entry.entryType !== typeFilter) return false;
        if (statusFilter !== 'all') {
          const clsStatus = classificationsByEntryId.get(entry.id)?.status;
          if (clsStatus !== statusFilter) return false;
        }

        if (datePreset === 'today' && entry.occurrenceDate !== todayIso) return false;
        if (
          datePreset === 'week' &&
          (entry.occurrenceDate < weekStartIso || entry.occurrenceDate > weekEndIso)
        ) {
          return false;
        }
        if (
          datePreset === 'month' &&
          (entry.occurrenceDate < monthStartIso || entry.occurrenceDate > monthEndIso)
        ) {
          return false;
        }
        if (datePreset === 'custom') {
          if (customStart && entry.occurrenceDate < customStart) return false;
          if (customEnd && entry.occurrenceDate > customEnd) return false;
        }

        const entryPostings = postingsByEntry.get(entry.id) || [];
        if (accountFilter !== 'all' && !entryPostings.some((p) => p.accountId === accountFilter)) {
          return false;
        }

        if (q) {
          const matchDesc = entry.description.toLowerCase().includes(q);
          const matchAcc = entryPostings.some((p) =>
            (accountById.get(p.accountId)?.name || '').toLowerCase().includes(q)
          );
          const matchCat = entryPostings.some((p) =>
            (p.categoryId ? resolveCategoryDisplayName(categories, p.categoryId) : '').toLowerCase().includes(q)
          );
          if (!matchDesc && !matchAcc && !matchCat) return false;
        }
        return true;
      });
  }, [
    entries,
    showVoided,
    typeFilter,
    statusFilter,
    classificationsByEntryId,
    datePreset,
    customStart,
    customEnd,
    accountFilter,
    query,
    postingsByEntry,
    accountById,
    categories,
  ]);

  const summarizeEntry = (entry: JournalEntry) => {
    const list = postingsByEntry.get(entry.id) || [];
    const destTransferPosting =
      entry.entryType === 'transfer'
        ? list.find((p) => p.direction === 'debit' && !accountById.get(p.accountId)?.isSystem)
        : undefined;
    const maxAmount = destTransferPosting
      ? destTransferPosting.amountCents
      : list.reduce((m, p) => Math.max(m, p.amountCents), 0);
    const hasExpenseDebit = list.some(
      (p) =>
        p.direction === 'debit' &&
        (p.accountId === SYSTEM_CONTROL_ACCOUNT_IDS.expense ||
          accountById.get(p.accountId)?.type === 'expense')
    );
    const hasExpenseCredit = list.some(
      (p) =>
        p.direction === 'credit' &&
        (p.accountId === SYSTEM_CONTROL_ACCOUNT_IDS.expense ||
          accountById.get(p.accountId)?.type === 'expense')
    );
    const hasIncome = list.some(
      (p) =>
        p.accountId === SYSTEM_CONTROL_ACCOUNT_IDS.income ||
        accountById.get(p.accountId)?.type === 'income'
    );
    const isRefund = isRefundEntry(entry);
    const catPosting = list.find((p) => p.categoryId);
    const catName = catPosting?.categoryId
      ? resolveCategoryDisplayName(categories, catPosting.categoryId)
      : undefined;
    const primaryUserPosting = list.find((p) => {
      const a = accountById.get(p.accountId);
      return a && !a.isSystem;
    });
    const accName = primaryUserPosting
      ? accountById.get(primaryUserPosting.accountId)?.name
      : undefined;

    let polarity: 'expense' | 'income' | 'neutral' = 'neutral';
    if (isRefund) {
      polarity = 'income';
    } else if (entry.entryType === 'standard' || entry.entryType === 'split_expense') {
      if (hasExpenseDebit && !hasIncome) polarity = 'expense';
      else if ((hasIncome || hasExpenseCredit) && !hasExpenseDebit) polarity = 'income';
    }
    const classification = classificationsByEntryId.get(entry.id);
    const displayCurrency =
      classification?.nativeCurrencyCode
        ? classification.nativeCurrencyCode
        : classification?.touchedCurrencies.length === 1
        ? classification.touchedCurrencies[0]
        : !classification || classification.touchedCurrencies.length === 0
        ? ''
        : 'MIXED';
    const nonSystemPostings = list.filter((p) => !accountById.get(p.accountId)?.isSystem);
    const isMixed = displayCurrency === 'MIXED';
    const formattedAmount = isMixed
      ? nonSystemPostings.length > 0
        ? nonSystemPostings
            .map((p) =>
              formatCurrencyCents(p.amountCents, accountById.get(p.accountId)?.currencyCode || '')
            )
            .join(' / ')
        : `${centsToInputText(maxAmount)} (${classification!.touchedCurrencies.join('/')})`
      : formatCurrencyCents(
          maxAmount,
          displayCurrency === 'UNVERIFIED'
            ? ''
            : displayCurrency ||
                (primaryUserPosting
                  ? accountById.get(primaryUserPosting.accountId)?.currencyCode
                  : classification?.status === 'eligible_etb'
                  ? 'ETB'
                  : '')
        );
    return {
      amountCents: maxAmount,
      formattedAmount,
      isMixed,
      isRefund,
      classification,
      catName,
      accName,
      polarity,
      postings: list,
    };
  };

  const handleCorrectAndReplace = (entry: JournalEntry) => {
    const check = canCorrectJournalEntryV7({
      entry,
      entries,
      postings,
      accounts,
      debts,
      allocations,
      commitmentSettlements,
    });
    if (!check.ok) {
      setInspectError(check.error || 'This entry cannot be replaced.');
      return;
    }

    const matchedTx = simpleTransactions.find(
      (t) =>
        t.journalEntryId === entry.id ||
        (entry.legacySourceTxId && t.id === entry.legacySourceTxId)
    );
    const info = summarizeEntry(entry);
    if (entry.entryType === 'transfer') {
      const sourceCr = info.postings.find(
        (p) => p.direction === 'credit' && !accountById.get(p.accountId)?.isSystem
      );
      const destDr = info.postings.find(
        (p) => p.direction === 'debit' && !accountById.get(p.accountId)?.isSystem
      );
      const feeDr = info.postings.find(
        (p) =>
          p.direction === 'debit' &&
          (p.accountId === SYSTEM_CONTROL_ACCOUNT_IDS.expense ||
            accountById.get(p.accountId)?.type === 'expense')
      );
      const cleanedDescription = entry.description.replace(/\s*\(Fee:\s*[^)]*\)\s*$/, '').trim();
      onOpenComposer('transfer', entry.id, {
        amountText: centsToInputText(destDr?.amountCents ?? info.amountCents),
        description: cleanedDescription,
        accountId: sourceCr?.accountId,
        destinationAccountId: destDr?.accountId,
        occurrenceDate: entry.occurrenceDate,
        movementDate:
          destDr?.accountMovementDate || sourceCr?.accountMovementDate || entry.occurrenceDate,
        feeText: feeDr ? centsToInputText(feeDr.amountCents) : '0',
        feeCategoryId: feeDr?.categoryId,
        note: destDr?.note || sourceCr?.note,
      });
      setInspectEntry(null);
      return;
    }

    const primaryUserPosting = info.postings.find((p) => !accountById.get(p.accountId)?.isSystem);
    const nominalPosting = info.postings.find((p) => accountById.get(p.accountId)?.isSystem);
    const catPosting = info.postings.find((p) => p.categoryId);
    const kind: ComposerKind = info.polarity === 'income' ? 'income' : 'expense';
    const payeeSep = ' — ';
    let prefillPayee = matchedTx?.payee?.trim() || undefined;
    let prefillDesc = entry.description;
    if (prefillPayee && prefillDesc.startsWith(`${prefillPayee}${payeeSep}`)) {
      prefillDesc = prefillDesc.slice(prefillPayee.length + payeeSep.length).trim();
    } else if (!prefillPayee && prefillDesc.includes(payeeSep)) {
      const sepIdx = prefillDesc.indexOf(payeeSep);
      if (sepIdx > 0) {
        prefillPayee = prefillDesc.slice(0, sepIdx).trim();
        prefillDesc = prefillDesc.slice(sepIdx + payeeSep.length).trim();
      }
    }

    const rawCatId = nominalPosting?.categoryId || catPosting?.categoryId;
    const matchedCatId = rawCatId
      ? findCategoryByIdOrAlias(categories, rawCatId)?.id || rawCatId
      : undefined;

    onOpenComposer(kind, entry.id, {
      amountText: centsToInputText(info.amountCents),
      description: prefillDesc,
      accountId: primaryUserPosting?.accountId,
      categoryId: matchedCatId,
      occurrenceDate: entry.occurrenceDate,
      movementDate: primaryUserPosting?.accountMovementDate || entry.occurrenceDate,
      note: primaryUserPosting?.note || nominalPosting?.note,
      payee: prefillPayee,
    });
    setInspectEntry(null);
  };

  const openRefundModal = (entry: JournalEntry) => {
    const summary = getExpenseRefundSummaryV7({
      originalEntryId: entry.id,
      entries,
      postings,
      accounts,
      debts,
      allocations,
    });
    if (!summary.eligible || summary.remainingRefundableCents <= 0) {
      setInspectError(summary.reason || 'This expense has no remaining refundable balance.');
      return;
    }
    const todayIso = CalendarDate.today().toIsoString();
    const defaultDate =
      entry.occurrenceDate > todayIso ? entry.occurrenceDate : todayIso;
    const defaultAccId =
      summary.originalAccountId &&
      refundableEtbAccounts.some((a) => a.id === summary.originalAccountId)
        ? summary.originalAccountId
        : refundableEtbAccounts[0]?.id || '';
    setRefundTargetEntry(entry);
    setRefundAccId(defaultAccId);
    setRefundAmtStr(centsToInputText(summary.remainingRefundableCents));
    setRefundDate(defaultDate);
    setRefundNote('');
    setRefundError(null);
    setInspectEntry(null);
  };

  const handleSubmitRefund = (e: React.FormEvent) => {
    e.preventDefault();
    if (!refundTargetEntry || !onRefundExpense) return;
    const cents = tryParseStrictDecimalToCents(refundAmtStr);
    if (cents === null || cents <= 0) {
      setRefundError('Enter a valid positive ETB refund amount.');
      return;
    }
    if (!refundAccId) {
      setRefundError('Select a valid active Verified ETB refund account.');
      return;
    }
    const res = onRefundExpense({
      originalEntryId: refundTargetEntry.id,
      refundAccountId: refundAccId,
      refundCents: cents,
      refundDateIso: refundDate,
      note: refundNote.trim() || undefined,
    });
    if (!res.ok) {
      setRefundError(res.error || 'Could not record expense refund.');
      return;
    }
    setRefundTargetEntry(null);
  };

  return (
    <div className="space-y-4">
      {/* Search & Filter Toolbar */}
      <DaywellCard padding="md" radius="lg" className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <DaywellSearchField
            value={query}
            onChange={setQuery}
            placeholder="Search description, account, category..."
            ariaLabel="Search ledger entries"
            className="flex-1 min-w-[200px]"
          />
          <DaywellButton
            label="Log Entry"
            variant="primary"
            size="compact"
            leadingIcon={<Plus className="w-3.5 h-3.5" />}
            onClick={() => onOpenComposer('expense')}
          />
        </div>

        <div className="flex flex-wrap items-center gap-2 text-xs">
          <select
            value={typeFilter}
            onChange={(e) => setTypeFilter(e.target.value)}
            className="px-2.5 py-1.5 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
          >
            <option value="all">All Types</option>
            <option value="standard">Standard</option>
            <option value="transfer">Transfer</option>
            <option value="split_expense">Split Expense</option>
            <option value="debt_issuance">Debt Issuance</option>
            <option value="settlement">Settlement</option>
            <option value="write_off">Write-Off</option>
            <option value="adjustment">Adjustment</option>
          </select>

          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="px-2.5 py-1.5 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
            aria-label="Filter by currency status"
          >
            <option value="all">All Currency Statuses</option>
            <option value="eligible_etb">ETB Eligible</option>
            <option value="excluded_non_etb">Excluded (Foreign)</option>
            <option value="mixed_or_ambiguous">Currency Review</option>
          </select>

          <select
            value={accountFilter}
            onChange={(e) => setAccountFilter(e.target.value)}
            className="px-2.5 py-1.5 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
          >
            <option value="all">All Accounts</option>
            {userAccounts.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name}
              </option>
            ))}
          </select>

          <select
            value={datePreset}
            onChange={(e) => setDatePreset(e.target.value as any)}
            className="px-2.5 py-1.5 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
          >
            <option value="all">All Dates</option>
            <option value="today">Today</option>
            <option value="week">This Week</option>
            <option value="month">This Month</option>
            <option value="custom">Custom Range</option>
          </select>

          <label className="flex items-center gap-1.5 text-[var(--dw-text-secondary)] cursor-pointer ml-auto">
            <input
              type="checkbox"
              checked={showVoided}
              onChange={(e) => setShowVoided(e.target.checked)}
              className="rounded accent-[var(--dw-primary)]"
            />
            <span>Show Voided</span>
          </label>
        </div>

        {datePreset === 'custom' && (
          <div className="flex flex-wrap items-center gap-2 text-xs">
            <input
              type="date"
              value={customStart}
              onChange={(e) => setCustomStart(e.target.value)}
              className="px-2.5 py-1.5 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
            />
            <span className="text-[var(--dw-text-muted)]">to</span>
            <input
              type="date"
              value={customEnd}
              onChange={(e) => setCustomEnd(e.target.value)}
              className="px-2.5 py-1.5 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
            />
          </div>
        )}
      </DaywellCard>

      {/* Entries List */}
      <DaywellCard padding="none" radius="lg" className="divide-y divide-[var(--dw-divider)] overflow-hidden">
        {filteredEntries.length === 0 ? (
          <DaywellEmptyState
            icon={<ReceiptText className="w-8 h-8" />}
            message="No matching journal entries"
            subtitle="Record an expense, income, transfer, or split to see balanced ledger entries here."
          />
        ) : (
          filteredEntries.map((entry) => {
            const info = summarizeEntry(entry);
            return (
              <div
                key={entry.id}
                onClick={() => {
                  setInspectError(null);
                  setInspectEntry(entry);
                }}
                role="button"
                tabIndex={0}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    setInspectError(null);
                    setInspectEntry(entry);
                  }
                }}
                className={`p-3.5 flex items-center justify-between gap-3 cursor-pointer hover:bg-[var(--dw-surface-subtle)] transition-colors ${
                  entry.isVoided ? 'opacity-55' : ''
                }`}
              >
                <div className="min-w-0">
                  <div className={`text-sm font-semibold text-[var(--dw-text-primary)] truncate ${entry.isVoided ? 'line-through' : ''}`}>
                    {entry.description}
                  </div>
                  <div className="text-xs text-[var(--dw-text-muted)] flex flex-wrap items-center gap-1.5 mt-0.5">
                    <span>{formatDualDateLabel(entry.occurrenceDate)}</span>
                    {info.accName && (
                      <>
                        <span aria-hidden="true">·</span>
                        <span>{info.accName}</span>
                      </>
                    )}
                    {info.catName && (
                      <>
                        <span aria-hidden="true">·</span>
                        <span>{info.catName}</span>
                      </>
                    )}
                    {info.isRefund && (
                      <DaywellStatusBadge tone="income" showIcon={false} label="Refund" />
                    )}
                    {entry.isVoided && (
                      <DaywellStatusBadge tone="error" showIcon={false} label="Voided" />
                    )}
                    {!entry.isVoided && info.classification?.status === 'excluded_non_etb' && (
                      <DaywellStatusBadge
                        tone="warning"
                        showIcon={false}
                        label={`Excluded (${info.classification.nativeCurrencyCode || info.classification.touchedCurrencies[0] || 'Non-ETB'})`}
                      />
                    )}
                    {!entry.isVoided && info.classification?.status === 'mixed_or_ambiguous' && (
                      <DaywellStatusBadge tone="error" showIcon={false} label="Currency Review" />
                    )}
                    {entry.correctedFromEntryId && (
                      <>
                        <span aria-hidden="true">·</span>
                        <span>Replacement</span>
                      </>
                    )}
                  </div>
                </div>
                <div
                  className={`text-sm font-bold font-mono tabular-nums shrink-0 ${
                    entry.isVoided
                      ? 'text-[var(--dw-text-disabled)] line-through'
                      : info.polarity === 'income'
                      ? 'text-[var(--dw-on-income-container)]'
                      : info.polarity === 'expense'
                      ? 'text-[var(--dw-on-expense-container)]'
                      : 'text-[var(--dw-on-transfer-container)]'
                  }`}
                >
                  {info.isMixed
                    ? info.formattedAmount
                    : info.polarity === 'income'
                    ? `+${info.formattedAmount}`
                    : info.polarity === 'expense'
                    ? `-${info.formattedAmount}`
                    : info.formattedAmount}
                </div>
              </div>
            );
          })
        )}
      </DaywellCard>

      {/* Inspect Postings Drawer / Modal */}
      {inspectEntry && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={inspectEntry.description}
          className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4"
        >
          <div className="w-full max-w-lg rounded-[var(--dw-radius-lg)] bg-[var(--dw-card)] border border-[var(--dw-border)] p-5 space-y-4 shadow-xl">
            <div className="flex items-start justify-between gap-3">
              <div>
                <h3 className="dw-type-title text-[var(--dw-text-primary)]">
                  {inspectEntry.description}
                </h3>
                <p className="text-xs text-[var(--dw-text-muted)] mt-0.5">
                  {formatDualDateLabel(inspectEntry.occurrenceDate)} · Type: {inspectEntry.entryType}
                </p>
              </div>
              <DaywellIconButton
                label="Close entry details"
                size="compact"
                tone="muted"
                onClick={() => setInspectEntry(null)}
                icon={<X className="w-4 h-4" />}
              />
            </div>

            {inspectEntry.isVoided && (
              <DaywellStatusBanner
                tone="error"
                message={`Voided: ${inspectEntry.voidReason || 'Marked void'}`}
              />
            )}

            <div className="space-y-1.5">
              <div className="text-xs font-semibold text-[var(--dw-text-secondary)]">
                Balanced Double-Entry Postings
              </div>
              <div className="rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] divide-y divide-[var(--dw-divider)] text-xs">
                {(postingsByEntry.get(inspectEntry.id) || []).map((p) => {
                  const pAcc = accountById.get(p.accountId);
                  const inspectCls = classificationsByEntryId.get(inspectEntry.id);
                  const postingCur =
                    !pAcc || pAcc.isSystem
                      ? inspectCls?.nativeCurrencyCode
                        ? inspectCls.nativeCurrencyCode
                        : inspectCls && inspectCls.touchedCurrencies.length === 1 && inspectCls.touchedCurrencies[0] !== 'UNVERIFIED'
                        ? inspectCls.touchedCurrencies[0]
                        : inspectCls?.status === 'eligible_etb'
                        ? 'ETB'
                        : pAcc?.currencyCode || ''
                      : pAcc.currencyCode;
                  return (
                    <div key={p.id} className="p-2.5 flex items-center justify-between gap-2">
                      <div className="min-w-0">
                        <div className="font-medium text-[var(--dw-text-primary)] truncate">
                          {pAcc?.name || p.accountId}
                        </div>
                        <div className="text-[11px] text-[var(--dw-text-muted)]">
                          {p.direction.toUpperCase()} · Movement: {p.accountMovementDate}
                          {p.categoryId
                            ? ` · ${resolveCategoryDisplayName(categories, p.categoryId)}`
                            : ''}
                        </div>
                      </div>
                      <span className="font-mono tabular-nums font-semibold text-[var(--dw-text-primary)]">
                        {formatCurrencyCents(p.amountCents, postingCur)}
                      </span>
                    </div>
                  );
                })}
              </div>
            </div>

            {inspectError && <DaywellStatusBanner tone="error" message={inspectError} />}

            {!inspectEntry.isVoided && (() => {
              const cls = classificationsByEntryId.get(inspectEntry.id);
              if (cls?.status !== 'eligible_etb') {
                return (
                  <DaywellStatusBanner
                    tone="warning"
                    message={`This entry is excluded from ETB totals (${cls?.reason || 'Non-ETB / Currency Review'}). Correct & Replace is disabled; you may inspect or void it.`}
                  />
                );
              }
              const correctCheck = canCorrectJournalEntryV7({
                entry: inspectEntry,
                entries,
                postings,
                accounts,
                debts,
                allocations,
                commitmentSettlements,
              });
              if (!correctCheck.ok && correctCheck.error) {
                return <DaywellStatusBanner tone="info" message={correctCheck.error} />;
              }
              return null;
            })()}

            {(() => {
              const refundSum = getExpenseRefundSummaryV7({
                originalEntryId: inspectEntry.id,
                entries,
                postings,
                accounts,
                debts,
                allocations,
              });
              if (!refundSum.eligible || refundSum.refundedCents <= 0) return null;
              return (
                <DaywellStatusBanner
                  tone="info"
                  message={`Refunded so far: ${formatCurrencyCents(refundSum.refundedCents, 'ETB')} of ${formatCurrencyCents(refundSum.originalAmountCents, 'ETB')} (${formatCurrencyCents(refundSum.remainingRefundableCents, 'ETB')} remaining refundable).`}
                />
              );
            })()}

            <div className="flex flex-wrap items-center justify-end gap-2 pt-3 border-t border-[var(--dw-divider)]">
              {!inspectEntry.isVoided ? (() => {
                const correctCheck = canCorrectJournalEntryV7({
                  entry: inspectEntry,
                  entries,
                  postings,
                  accounts,
                  debts,
                  allocations,
                  commitmentSettlements,
                });
                const refundSum = getExpenseRefundSummaryV7({
                  originalEntryId: inspectEntry.id,
                  entries,
                  postings,
                  accounts,
                  debts,
                  allocations,
                });
                return (
                  <>
                    {refundSum.eligible && refundSum.remainingRefundableCents > 0 && onRefundExpense && (
                      <DaywellButton
                        label="Refund Expense"
                        variant="secondary"
                        size="compact"
                        leadingIcon={<CornerDownLeft className="w-3.5 h-3.5" />}
                        onClick={() => openRefundModal(inspectEntry)}
                      />
                    )}
                    {correctCheck.ok && (
                      <DaywellButton
                        label="Correct / Replace"
                        variant="outlined"
                        size="compact"
                        leadingIcon={<Edit3 className="w-3.5 h-3.5" />}
                        onClick={() => handleCorrectAndReplace(inspectEntry)}
                      />
                    )}
                    <DaywellButton
                      label="Void Entry"
                      variant="destructive"
                      size="compact"
                      leadingIcon={<Ban className="w-3.5 h-3.5" />}
                      onClick={() =>
                        onRequestConfirm(
                          'Void Journal Entry?',
                          `Void "${inspectEntry.description}"? This reverses its cash and report impact without deleting audit history.`,
                          'Void Entry',
                          'danger',
                          () => {
                            const res = onVoidEntry(inspectEntry.id, 'Voided by user');
                            if (res && !res.ok) {
                              setInspectError(res.error || 'Could not void journal entry.');
                            } else {
                              setInspectEntry(null);
                            }
                          }
                        )
                      }
                    />
                  </>
                );
              })() : classificationsByEntryId.get(inspectEntry.id)?.status === 'eligible_etb' ? (
                <DaywellButton
                  label="Restore Entry"
                  variant="primary"
                  size="compact"
                  leadingIcon={<RotateCcw className="w-3.5 h-3.5" />}
                  onClick={() => {
                    const res = onRestoreEntry(inspectEntry.id);
                    if (res && !res.ok) {
                      setInspectError(res.error || 'Could not restore journal entry.');
                    } else {
                      setInspectEntry(null);
                    }
                  }}
                />
              ) : (
                <span className="text-xs text-[var(--dw-text-muted)]">
                  Non-ETB / unverified entries cannot be restored in ETB mode.
                </span>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Expense Refund Modal */}
      {refundTargetEntry && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Record Expense Refund"
          className="fixed inset-0 z-50 bg-black/55 flex items-center justify-center p-4"
        >
          <form
            onSubmit={handleSubmitRefund}
            className="w-full max-w-md rounded-[var(--dw-radius-lg)] bg-[var(--dw-card)] border border-[var(--dw-border)] p-5 space-y-3 text-xs shadow-xl"
          >
            <div className="flex items-start justify-between gap-3">
              <div>
                <h3 className="dw-type-title text-[var(--dw-text-primary)]">Record Expense Refund</h3>
                <p className="text-[11px] text-[var(--dw-text-muted)] mt-0.5">
                  {refundTargetEntry.description} · Original date {refundTargetEntry.occurrenceDate}
                </p>
              </div>
              <DaywellIconButton
                label="Close refund dialog"
                size="compact"
                tone="muted"
                onClick={() => setRefundTargetEntry(null)}
                icon={<X className="w-4 h-4" />}
              />
            </div>

            {refundError && <DaywellStatusBanner tone="error" message={refundError} />}

            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                Refund To Account (Verified ETB)
              </label>
              <select
                value={refundAccId}
                onChange={(e) => setRefundAccId(e.target.value)}
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
              >
                {refundableEtbAccounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name} ({a.currencyCode})
                  </option>
                ))}
              </select>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                  Refund Amount (ETB)
                </label>
                <input
                  type="number"
                  step="0.01"
                  value={refundAmtStr}
                  onChange={(e) => setRefundAmtStr(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono tabular-nums"
                />
              </div>
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                  Refund Date
                </label>
                <input
                  type="date"
                  value={refundDate}
                  min={refundTargetEntry.occurrenceDate}
                  onChange={(e) => setRefundDate(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
                />
              </div>
            </div>

            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                Note (Optional)
              </label>
              <input
                type="text"
                value={refundNote}
                onChange={(e) => setRefundNote(e.target.value)}
                placeholder="Merchant credit or returned item"
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
              />
            </div>

            <div className="flex justify-end gap-2 pt-2 border-t border-[var(--dw-divider)]">
              <DaywellButton label="Cancel" variant="text" size="compact" onClick={() => setRefundTargetEntry(null)} />
              <DaywellButton type="submit" label="Record Refund" variant="primary" size="compact" />
            </div>
          </form>
        </div>
      )}
    </div>
  );
}
