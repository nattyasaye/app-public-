import React, { useMemo, useState } from 'react';
import {
  Plus,
  X,
  RotateCcw,
  Edit3,
  Ban,
  ReceiptText,
  CornerDownLeft,
  ChevronDown,
  ChevronRight,
} from 'lucide-react';
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
  normalizeCurrencyCode,
  Posting,
  resolveCategoryDisplayName,
  resolveTransferDisplayEndpoints,
  SettlementAllocation,
  SharedCommitmentSettlement,
  SimpleTransaction,
  summarizeDirectExpense,
  TransactionCategory,
} from '../../domain/financeV7Engine';
import {
  collectUnambiguousHistoricalPostingNote,
  resolveDescriptionWithHistoricalNote,
} from '../../domain/doubleEntryFinance';
import { CalendarDate } from '../../domain/date';
import {
  createEmptyDailyRhythmDay,
  DailyRhythmDayRecord,
} from '../../domain/dailyRhythm';
import { inspectDailyRhythmFinanceDay } from '../../domain/dailyRhythmWorkflows';
import { SYSTEM_CONTROL_ACCOUNT_IDS } from '../../domain/sharedFoundation';
import {
  centsToInputText,
  ComposerKind,
  FinanceComposerPrefill,
  formatDualDateLabel,
  tryParseStrictDecimalToCents,
} from './financeV7Types';
import { DailyFinanceCloseCard } from '../daily-rhythm';
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
  }) => { ok: boolean; error?: string };
  onRequestConfirm: (
    title: string,
    message: string,
    confirmLabel: string,
    tone: 'danger' | 'primary',
    onConfirm: () => void
  ) => void;
  dailyRhythmRecord?: DailyRhythmDayRecord;
  onConfirmFinanceClose?: () => void;
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
  dailyRhythmRecord,
  onConfirmFinanceClose,
}: FinanceTransactionsTabProps) {
  const [query, setQuery] = useState('');
  const [typeFilter, setTypeFilter] = useState<string>('all');
  const [accountFilter, setAccountFilter] = useState<string>('all');
  const [datePreset, setDatePreset] = useState<'all' | 'today' | 'week' | 'month' | 'custom'>('all');
  const [customStart, setCustomStart] = useState('');
  const [customEnd, setCustomEnd] = useState('');
  const [showVoided, setShowVoided] = useState(false);
  const [showLegacyEntries, setShowLegacyEntries] = useState(false);
  const [inspectEntry, setInspectEntry] = useState<JournalEntry | null>(null);
  const [inspectError, setInspectError] = useState<string | null>(null);

  // Refund Expense modal state
  const [refundTargetEntry, setRefundTargetEntry] = useState<JournalEntry | null>(null);
  const [refundAccId, setRefundAccId] = useState('');
  const [refundAmtStr, setRefundAmtStr] = useState('');
  const [refundDate, setRefundDate] = useState(CalendarDate.today().toIsoString());
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

  const financeDaySummary = useMemo(
    () => inspectDailyRhythmFinanceDay({ entries }),
    [entries]
  );

  const accountById = useMemo(() => new Map(accounts.map((a) => [a.id, a])), [accounts]);
  const userEtbAccounts = useMemo(
    () => accounts.filter((a) => !a.isSystem && normalizeCurrencyCode(a.currencyCode) === 'ETB'),
    [accounts]
  );

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
          const resolvedDesc = resolveDescriptionWithHistoricalNote({
            description: entry.description,
            legacyNote: collectUnambiguousHistoricalPostingNote(entryPostings),
          });
          const matchDesc = resolvedDesc.toLowerCase().includes(q);
          const matchAcc = entryPostings.some((p) => {
            const acc = accountById.get(p.accountId);
            return acc && !acc.isSystem && acc.name.toLowerCase().includes(q);
          });
          const matchTransferLabel =
            entry.entryType === 'transfer' &&
            resolveTransferDisplayEndpoints(entryPostings, accountById)
              .displayLabel.toLowerCase()
              .includes(q);
          const matchCat = entryPostings.some((p) =>
            (p.categoryId ? resolveCategoryDisplayName(categories, p.categoryId) : '').toLowerCase().includes(q)
          );
          if (!matchDesc && !matchAcc && !matchTransferLabel && !matchCat) return false;
        }
        return true;
      });
  }, [
    entries,
    showVoided,
    typeFilter,
    datePreset,
    customStart,
    customEnd,
    accountFilter,
    query,
    postingsByEntry,
    accountById,
    categories,
  ]);

  const etbFilteredEntries = useMemo(
    () =>
      filteredEntries.filter(
        (entry) => classificationsByEntryId.get(entry.id)?.status === 'eligible_etb'
      ),
    [filteredEntries, classificationsByEntryId]
  );

  const legacyFilteredEntries = useMemo(
    () =>
      filteredEntries.filter(
        (entry) => classificationsByEntryId.get(entry.id)?.status !== 'eligible_etb'
      ),
    [filteredEntries, classificationsByEntryId]
  );

  const summarizeEntry = (entry: JournalEntry) => {
    const list = postingsByEntry.get(entry.id) || [];
    const transferEndpoints =
      entry.entryType === 'transfer'
        ? resolveTransferDisplayEndpoints(list, accountById)
        : undefined;
    const expenseSummary = summarizeDirectExpense({
      entry,
      postings: list,
      accountById,
    });
    const destTransferPosting =
      entry.entryType === 'transfer'
        ? list.find((p) => p.direction === 'debit' && !accountById.get(p.accountId)?.isSystem)
        : undefined;
    const maxAmount = expenseSummary.isDirectExpense
      ? expenseSummary.totalOutflowCents
      : destTransferPosting
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
    const primaryCatId = expenseSummary.isDirectExpense
      ? expenseSummary.primaryCategoryId
      : catPosting?.categoryId;
    const catName = primaryCatId
      ? resolveCategoryDisplayName(categories, primaryCatId)
      : undefined;
    const primaryUserPosting = list.find((p) => {
      const a = accountById.get(p.accountId);
      return a && !a.isSystem;
    });
    const accName =
      entry.entryType === 'transfer'
        ? transferEndpoints?.displayLabel || undefined
        : expenseSummary.isDirectExpense && expenseSummary.paidAccountId
        ? accountById.get(expenseSummary.paidAccountId)?.name
        : primaryUserPosting
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
    const singleNonEtbTouched =
      classification?.touchedCurrencies.length === 1 &&
      classification.touchedCurrencies[0] !== 'ETB' &&
      classification.touchedCurrencies[0] !== 'UNVERIFIED'
        ? classification.touchedCurrencies[0]
        : undefined;
    const displayCurrency =
      classification?.status === 'eligible_etb'
        ? 'ETB'
        : classification?.nativeCurrencyCode
        ? classification.nativeCurrencyCode
        : singleNonEtbTouched
        ? singleNonEtbTouched
        : !classification || classification.touchedCurrencies.length <= 1
        ? ''
        : 'MIXED';
    const nonSystemPostings = list.filter((p) => !accountById.get(p.accountId)?.isSystem);
    const isMixed = displayCurrency === 'MIXED';
    const effectiveCurrency =
      displayCurrency === 'UNVERIFIED'
        ? ''
        : displayCurrency ||
          (classification?.status === 'mixed_or_ambiguous' ||
          classification?.status === 'inactive_or_voided'
            ? ''
            : primaryUserPosting
            ? accountById.get(primaryUserPosting.accountId)?.currencyCode
            : '');
    const formattedAmount = isMixed
      ? nonSystemPostings.length > 0
        ? nonSystemPostings
            .map((p) =>
              formatCurrencyCents(p.amountCents, accountById.get(p.accountId)?.currencyCode || '')
            )
            .join(' / ')
        : `${centsToInputText(maxAmount)} (${classification!.touchedCurrencies.join('/')})`
      : formatCurrencyCents(maxAmount, effectiveCurrency);
    const feeCents = expenseSummary.isDirectExpense ? expenseSummary.feeCents : 0;
    const principalCents = expenseSummary.isDirectExpense
      ? expenseSummary.principalCents
      : maxAmount;
    const formattedFee =
      feeCents > 0 && !isMixed ? formatCurrencyCents(feeCents, effectiveCurrency) : undefined;
    const formattedPrincipal =
      feeCents > 0 && !isMixed ? formatCurrencyCents(principalCents, effectiveCurrency) : undefined;
    return {
      amountCents: maxAmount,
      principalCents,
      feeCents,
      formattedAmount,
      formattedFee,
      formattedPrincipal,
      expenseSummary,
      transferEndpoints,
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
      const baseDesc = resolveDescriptionWithHistoricalNote({
        description: entry.description,
        legacyNote:
          collectUnambiguousHistoricalPostingNote(info.postings) ??
          (matchedTx as { note?: string } | undefined)?.note,
      });
      const cleanedDescription = baseDesc.replace(/\s*\(Fee:\s*[^)]*\)\s*$/, '').trim();
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
    let prefillDesc = resolveDescriptionWithHistoricalNote({
      description: entry.description,
      legacyNote:
        collectUnambiguousHistoricalPostingNote(info.postings) ??
        (matchedTx as { note?: string } | undefined)?.note,
    });
    if (prefillPayee && prefillDesc.startsWith(`${prefillPayee}${payeeSep}`)) {
      prefillDesc = prefillDesc.slice(prefillPayee.length + payeeSep.length).trim();
    } else if (!prefillPayee && prefillDesc.includes(payeeSep)) {
      const sepIdx = prefillDesc.indexOf(payeeSep);
      if (sepIdx > 0) {
        prefillPayee = prefillDesc.slice(0, sepIdx).trim();
        prefillDesc = prefillDesc.slice(sepIdx + payeeSep.length).trim();
      }
    }

    const rawCatId =
      info.expenseSummary.isDirectExpense
        ? info.expenseSummary.primaryCategoryId
        : nominalPosting?.categoryId || catPosting?.categoryId;
    const matchedCatId = rawCatId
      ? findCategoryByIdOrAlias(categories, rawCatId)?.id || rawCatId
      : undefined;

    const matchedFeeCatId =
      kind === 'expense' && info.expenseSummary.isDirectExpense && info.expenseSummary.feeCategoryId
        ? findCategoryByIdOrAlias(categories, info.expenseSummary.feeCategoryId)?.id ||
          info.expenseSummary.feeCategoryId
        : undefined;

    onOpenComposer(kind, entry.id, {
      amountText: centsToInputText(
        kind === 'expense' && info.expenseSummary.isDirectExpense
          ? info.expenseSummary.principalCents
          : info.amountCents
      ),
      description: prefillDesc,
      accountId:
        (kind === 'expense' && info.expenseSummary.isDirectExpense
          ? info.expenseSummary.paidAccountId
          : undefined) || primaryUserPosting?.accountId,
      categoryId: matchedCatId,
      feeText:
        kind === 'expense' && info.expenseSummary.isDirectExpense
          ? info.expenseSummary.feeCents > 0
            ? centsToInputText(info.expenseSummary.feeCents)
            : '0'
          : undefined,
      feeCategoryId: matchedFeeCatId,
      occurrenceDate: entry.occurrenceDate,
      movementDate: primaryUserPosting?.accountMovementDate || entry.occurrenceDate,
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
      setRefundError('Select a valid active ETB refund account.');
      return;
    }
    const res = onRefundExpense({
      originalEntryId: refundTargetEntry.id,
      refundAccountId: refundAccId,
      refundCents: cents,
      refundDateIso: refundDate,
    });
    if (!res.ok) {
      setRefundError(res.error || 'Could not record expense refund.');
      return;
    }
    setRefundTargetEntry(null);
  };

  return (
    <div className="space-y-4">
      {onConfirmFinanceClose && (
        <DailyFinanceCloseCard
          summary={financeDaySummary}
          record={
            dailyRhythmRecord ??
            createEmptyDailyRhythmDay(financeDaySummary.targetDateIso)
          }
          isShowingTodayFilter={datePreset === 'today'}
          onConfirmClose={onConfirmFinanceClose}
          onFilterToday={() => setDatePreset('today')}
        />
      )}

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
            value={accountFilter}
            onChange={(e) => setAccountFilter(e.target.value)}
            className="px-2.5 py-1.5 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
          >
            <option value="all">All Accounts</option>
            {userEtbAccounts.map((a) => (
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

      {/* Entries List (ETB) */}
      <DaywellCard padding="none" radius="lg" className="divide-y divide-[var(--dw-divider)] overflow-hidden">
        {etbFilteredEntries.length === 0 ? (
          <DaywellEmptyState
            icon={<ReceiptText className="w-8 h-8" />}
            message="No matching journal entries"
            subtitle="Record an expense, income, transfer, or split to see balanced ledger entries here."
          />
        ) : (
          etbFilteredEntries.map((entry) => {
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
                    {resolveDescriptionWithHistoricalNote({
                      description: entry.description,
                      legacyNote: collectUnambiguousHistoricalPostingNote(info.postings),
                    })}
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
                    {info.formattedFee && info.formattedPrincipal && (
                      <>
                        <span aria-hidden="true">·</span>
                        <span>
                          Includes {info.formattedFee} fee (Principal {info.formattedPrincipal})
                        </span>
                      </>
                    )}
                    {info.isRefund && (
                      <DaywellStatusBadge tone="income" showIcon={false} label="Refund" />
                    )}
                    {entry.isVoided && (
                      <DaywellStatusBadge tone="error" showIcon={false} label="Voided" />
                    )}
                    {entry.correctedFromEntryId && (
                      <>
                        <span aria-hidden="true">·</span>
                        <span>Replacement</span>
                      </>
                    )}
                  </div>
                </div>
                <div className="shrink-0 text-right">
                  <div
                    className={`text-sm font-bold font-mono tabular-nums ${
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
                  {info.formattedFee && (
                    <div className="text-[11px] text-[var(--dw-text-muted)] font-mono tabular-nums">
                      Includes {info.formattedFee} fee
                    </div>
                  )}
                </div>
              </div>
            );
          })
        )}
      </DaywellCard>

      {legacyFilteredEntries.length > 0 && (
        <DaywellCard padding="lg" radius="lg" className="space-y-3">
          <button
            type="button"
            onClick={() => setShowLegacyEntries((v) => !v)}
            aria-expanded={showLegacyEntries}
            className="w-full flex items-center justify-between gap-2 text-left cursor-pointer"
          >
            <div>
              <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
                Legacy Non-ETB Entries ({legacyFilteredEntries.length}) · Read-Only
              </h3>
              <p className="text-xs text-[var(--dw-text-muted)]">
                Historical non-ETB or unclassified entries preserved separately and excluded from ETB totals
              </p>
            </div>
            <div className="flex items-center gap-2 shrink-0 text-[var(--dw-text-muted)]">
              {showLegacyEntries ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
            </div>
          </button>

          {showLegacyEntries && (
            <div className="divide-y divide-[var(--dw-divider)] border-t border-[var(--dw-divider)]">
              {legacyFilteredEntries.map((entry) => {
                const info = summarizeEntry(entry);
                const legacyCode =
                  info.classification?.nativeCurrencyCode &&
                  info.classification.nativeCurrencyCode !== 'ETB'
                    ? info.classification.nativeCurrencyCode
                    : info.classification?.touchedCurrencies.find(
                        (c) => c !== 'UNVERIFIED' && c !== 'ETB'
                      ) ?? '';
                const hideLegacyBadgeOnVoidedEtb =
                  entry.isVoided && info.classification?.nativeCurrencyCode === 'ETB';
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
                    className={`py-3 flex items-center justify-between gap-3 cursor-pointer hover:bg-[var(--dw-surface-subtle)] px-2 rounded-[var(--dw-radius-sm)] transition-colors ${
                      entry.isVoided ? 'opacity-55' : ''
                    }`}
                  >
                    <div className="min-w-0">
                      <div className={`text-sm font-semibold text-[var(--dw-text-primary)] truncate ${entry.isVoided ? 'line-through' : ''}`}>
                        {resolveDescriptionWithHistoricalNote({
                          description: entry.description,
                          legacyNote: collectUnambiguousHistoricalPostingNote(info.postings),
                        })}
                      </div>
                      <div className="text-xs text-[var(--dw-text-muted)] flex flex-wrap items-center gap-1.5 mt-0.5">
                        <span>{formatDualDateLabel(entry.occurrenceDate)}</span>
                        {info.accName && (
                          <>
                            <span aria-hidden="true">·</span>
                            <span>{info.accName}</span>
                          </>
                        )}
                        {!hideLegacyBadgeOnVoidedEtb && (
                          <DaywellStatusBadge
                            tone="warning"
                            showIcon={false}
                            label={legacyCode ? `Legacy (${legacyCode})` : 'Unclassified'}
                          />
                        )}
                        {entry.isVoided && (
                          <DaywellStatusBadge tone="error" showIcon={false} label="Voided" />
                        )}
                      </div>
                    </div>
                    <div className="shrink-0 text-right font-mono tabular-nums text-sm font-semibold text-[var(--dw-text-secondary)]">
                      {info.formattedAmount}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </DaywellCard>
      )}

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
                  {resolveDescriptionWithHistoricalNote({
                    description: inspectEntry.description,
                    legacyNote: collectUnambiguousHistoricalPostingNote(
                      postingsByEntry.get(inspectEntry.id) || []
                    ),
                  })}
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
                      ? inspectCls?.status === 'eligible_etb'
                        ? 'ETB'
                        : inspectCls?.nativeCurrencyCode && inspectCls.nativeCurrencyCode !== 'ETB'
                        ? inspectCls.nativeCurrencyCode
                        : inspectCls &&
                          inspectCls.touchedCurrencies.length === 1 &&
                          inspectCls.touchedCurrencies[0] !== 'UNVERIFIED' &&
                          inspectCls.touchedCurrencies[0] !== 'ETB'
                        ? inspectCls.touchedCurrencies[0]
                        : inspectEntry.isVoided && inspectCls?.nativeCurrencyCode === 'ETB'
                        ? 'ETB'
                        : ''
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
                    message="Legacy non-ETB record preserved read-only with original amounts and excluded from ETB totals. Editing is disabled."
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
              const inspectExpenseSummary = summarizeDirectExpense({
                entry: inspectEntry,
                postings: postingsByEntry.get(inspectEntry.id) || [],
                accountById,
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
                  {inspectExpenseSummary.isDirectExpense && inspectExpenseSummary.feeCents > 0 && (
                    <DaywellStatusBanner
                      tone="info"
                      message={`Principal ${formatCurrencyCents(inspectExpenseSummary.principalCents, 'ETB')} + Fee ${formatCurrencyCents(inspectExpenseSummary.feeCents, 'ETB')} = Total deduction ${formatCurrencyCents(inspectExpenseSummary.totalOutflowCents, 'ETB')}.`}
                    />
                  )}
                  {refundSum.eligible && refundSum.refundedCents > 0 && (
                    <DaywellStatusBanner
                      tone="info"
                      message={`Refunded so far: ${formatCurrencyCents(refundSum.refundedCents, 'ETB')} of ${formatCurrencyCents(refundSum.originalAmountCents, 'ETB')} principal (${formatCurrencyCents(refundSum.remainingRefundableCents, 'ETB')} remaining refundable${(refundSum.originalFeeCents || 0) > 0 ? `; excludes ${formatCurrencyCents(refundSum.originalFeeCents || 0, 'ETB')} fee` : ''}).`}
                    />
                  )}
                </>
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
                const isEligibleEtb =
                  classificationsByEntryId.get(inspectEntry.id)?.status === 'eligible_etb';
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
                    {isEligibleEtb && (
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
                    )}
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
                  Legacy non-ETB entries cannot be restored.
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

            {(() => {
              const modalRefundSum = getExpenseRefundSummaryV7({
                originalEntryId: refundTargetEntry.id,
                entries,
                postings,
                accounts,
                debts,
                allocations,
              });
              if (!modalRefundSum.eligible) return null;
              return (
                <DaywellStatusBanner
                  tone="info"
                  message={
                    (modalRefundSum.originalFeeCents || 0) > 0
                      ? `Maximum normal refund is principal only: ${formatCurrencyCents(modalRefundSum.remainingRefundableCents, 'ETB')} remaining (original principal ${formatCurrencyCents(modalRefundSum.originalAmountCents, 'ETB')}; ${formatCurrencyCents(modalRefundSum.originalFeeCents || 0, 'ETB')} bank fee excluded).`
                      : `Remaining refundable principal: ${formatCurrencyCents(modalRefundSum.remainingRefundableCents, 'ETB')} of ${formatCurrencyCents(modalRefundSum.originalAmountCents, 'ETB')}.`
                  }
                />
              );
            })()}

            {refundError && <DaywellStatusBanner tone="error" message={refundError} />}

            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                Refund To Account
              </label>
              <select
                value={refundAccId}
                onChange={(e) => setRefundAccId(e.target.value)}
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
              >
                {refundableEtbAccounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
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
