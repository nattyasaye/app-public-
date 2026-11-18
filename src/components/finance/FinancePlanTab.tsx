import React, { useMemo, useState } from 'react';
import {
  Plus,
  CheckCircle2,
  Pause,
  Play,
  SkipForward,
  Archive,
  X,
  AlertTriangle,
  Ban,
  RotateCcw,
} from 'lucide-react';
import {
  Account,
  calculateCommitmentSettledCents,
  classifyAllJournalEntries,
  classifyCurrencyCode,
  Debt,
  formatCurrencyCents,
  generateOccurrenceReport,
  getCommitmentRemainingCents,
  isActiveVerifiedEtbAccount,
  isDebtEligibleEtb,
  isEtbCurrency,
  JournalEntry,
  normalizeCurrencyCode,
  Party,
  Posting,
  resolveCommitmentCurrencyStatus,
  SettlementAllocation,
  SharedBudget,
  SharedCommitment,
  SharedCommitmentSettlement,
  SharedRecurringRule,
  SharedSavingsGoal,
  TransactionCategory,
} from '../../domain/financeV7Engine';
import { formatBirr } from '../../domain/financialEngine';
import { CalendarDate } from '../../domain/date';
import { centsToInputText, ComposerKind, tryParseStrictDecimalToCents } from './financeV7Types';
import {
  DaywellButton,
  DaywellCard,
  DaywellIconButton,
  DaywellProgressBar,
  DaywellStatusBadge,
  DaywellStatusBanner,
} from '../ui';

interface FinancePlanTabProps {
  accounts: Account[];
  categories: TransactionCategory[];
  parties: Party[];
  entries: JournalEntry[];
  postings: Posting[];
  debts: Debt[];
  allocations: SettlementAllocation[];
  commitments: SharedCommitment[];
  commitmentSettlements: SharedCommitmentSettlement[];
  savingsGoals: SharedSavingsGoal[];
  budgets: SharedBudget[];
  recurringRules: SharedRecurringRule[];
  availableLiquidCashCents: number;
  onAddCommitment: (
    c: Omit<SharedCommitment, 'id' | 'isPaid'>
  ) => { ok: boolean; error?: string } | void;
  onLinkCommitmentAccount?: (
    commitmentId: string,
    accountId: string
  ) => { ok: boolean; error?: string };
  onRecordCommitmentSettlement: (payload: {
    commitmentId: string;
    accountId: string;
    amountCents: number;
    settledDateIso: string;
  }) => { ok: boolean; error?: string };
  onVoidCommitmentSettlement: (settlementId: string, commitmentId: string) => void;
  onMarkLegacyUnpaid: (commitmentId: string) => void;
  onOpenComposer: (kind: ComposerKind) => void;
  onSettleDebt: (payload: {
    debtId: string;
    accountId: string;
    principalCents: number;
    interestCents: number;
    feeCents: number;
    dateIso: string;
  }) => { ok: boolean; error?: string };
  onWriteOffDebt: (debtId: string, reason: string) => void;
  onVoidDebtWriteOff: (debtId: string) => void;
  onVoidDebtOrigin: (debtId: string) => { ok: boolean; error?: string };
  onAddSavingsGoal: (
    g: Omit<SharedSavingsGoal, 'id' | 'currentAllocatedCents' | 'status'>
  ) => { ok: boolean; error?: string } | void;
  onFundSavingsGoal: (payload: {
    goalId: string;
    amountCents: number;
    direction: 'deposit' | 'withdraw';
    sourceAccountId?: string;
    dateIso: string;
  }) => { ok: boolean; error?: string };
  onReleaseAndArchiveGoal: (goalId: string) => { ok: boolean; error?: string } | void;
  onUpsertBudget: (payload: { categoryId: string; limitCents: number; rolloverEnabled: boolean }) => void;
  onAddRecurringRule: (
    r: Omit<SharedRecurringRule, 'id' | 'createdAt' | 'isActive'>
  ) => { ok: boolean; error?: string } | void;
  onToggleRecurringActive: (ruleId: string) => void;
  onToggleRecurringAutoPost: (ruleId: string) => void;
  onSkipNextRecurring: (ruleId: string) => void;
  onProcessDueRules: () => number;
  onRequestConfirm: (
    title: string,
    message: string,
    confirmLabel: string,
    tone: 'danger' | 'primary',
    onConfirm: () => void
  ) => void;
}

export function FinancePlanTab({
  accounts,
  categories,
  parties,
  entries,
  postings,
  debts,
  allocations,
  commitments,
  commitmentSettlements,
  savingsGoals,
  budgets,
  recurringRules,
  availableLiquidCashCents,
  onAddCommitment,
  onLinkCommitmentAccount,
  onRecordCommitmentSettlement,
  onVoidCommitmentSettlement,
  onMarkLegacyUnpaid,
  onOpenComposer,
  onSettleDebt,
  onWriteOffDebt,
  onVoidDebtWriteOff,
  onVoidDebtOrigin,
  onAddSavingsGoal,
  onFundSavingsGoal,
  onReleaseAndArchiveGoal,
  onUpsertBudget,
  onAddRecurringRule,
  onToggleRecurringActive,
  onToggleRecurringAutoPost,
  onSkipNextRecurring,
  onProcessDueRules,
  onRequestConfirm,
}: FinancePlanTabProps) {
  const todayIso = useMemo(() => CalendarDate.today().toIsoString(), []);
  const monthIso = todayIso.slice(0, 7);
  const [banner, setBanner] = useState<string | null>(null);

  const liquidEtbAccounts = useMemo(
    () =>
      accounts.filter(
        (a) =>
          isActiveVerifiedEtbAccount(a) &&
          a.type === 'asset' &&
          a.subType !== 'savings_vault' &&
          a.subType !== 'receivable'
      ),
    [accounts]
  );
  const allSpendableAccounts = useMemo(
    () => accounts.filter((a) => isActiveVerifiedEtbAccount(a)),
    [accounts]
  );
  const vaultAccounts = useMemo(
    () =>
      accounts.filter(
        (a) => isActiveVerifiedEtbAccount(a) && a.subType === 'savings_vault'
      ),
    [accounts]
  );
  const hasNonEtbAccounts = useMemo(
    () => accounts.some((a) => !a.isSystem && !isEtbCurrency(a.currencyCode)),
    [accounts]
  );
  const accountById = useMemo(() => new Map(accounts.map((a) => [a.id, a])), [accounts]);
  const entryById = useMemo(() => new Map(entries.map((e) => [e.id, e])), [entries]);
  const debtById = useMemo(() => new Map(debts.map((d) => [d.id, d])), [debts]);
  const ruleById = useMemo(() => new Map(recurringRules.map((r) => [r.id, r])), [recurringRules]);
  const settlementsByCommitmentId = useMemo(() => {
    const map = new Map<string, SharedCommitmentSettlement[]>();
    for (const s of commitmentSettlements) {
      const list = map.get(s.commitmentId) || [];
      list.push(s);
      map.set(s.commitmentId, list);
    }
    return map;
  }, [commitmentSettlements]);
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
  const partyById = useMemo(() => new Map(parties.map((p) => [p.id, p.name])), [parties]);
  const voidedEntryIds = useMemo(
    () => new Set(entries.filter((e) => e.isVoided).map((e) => e.id)),
    [entries]
  );

  // Month occurrence spend for budgets
  const currentMonthOccurrence = useMemo(() => {
    const today = CalendarDate.today();
    return generateOccurrenceReport({
      entries,
      postings,
      accounts,
      categories,
      debts,
      allocations,
      startDate: today.startOfGregorianMonth.toIsoString(),
      endDate: today.endOfGregorianMonth.toIsoString(),
    });
  }, [entries, postings, accounts, categories, debts, allocations]);

  // Add Commitment modal state
  const [comModalOpen, setComModalOpen] = useState(false);
  const [comTitle, setComTitle] = useState('');
  const [comDirection, setComDirection] = useState<'outflow' | 'inflow'>('outflow');
  const [comAmountStr, setComAmountStr] = useState('');
  const [comDueDate, setComDueDate] = useState(todayIso);
  const [comCategoryId, setComCategoryId] = useState('');
  const [comLinkedAccountId, setComLinkedAccountId] = useState('');

  // Settle Commitment modal state
  const [settleComTarget, setSettleComTarget] = useState<SharedCommitment | null>(null);
  const [settleComAccId, setSettleComAccId] = useState('');
  const [settleComAmtStr, setSettleComAmtStr] = useState('');
  const [settleComDate, setSettleComDate] = useState(todayIso);

  // Settle Debt modal state
  const [settleDebtTarget, setSettleDebtTarget] = useState<Debt | null>(null);
  const [settleDebtAccId, setSettleDebtAccId] = useState('');
  const [settleDebtPrincipalStr, setSettleDebtPrincipalStr] = useState('');
  const [settleDebtInterestStr, setSettleDebtInterestStr] = useState('0');
  const [settleDebtFeeStr, setSettleDebtFeeStr] = useState('0');
  const [settleDebtDate, setSettleDebtDate] = useState(todayIso);

  // Add Savings Goal modal state
  const [goalModalOpen, setGoalModalOpen] = useState(false);
  const [goalTitle, setGoalTitle] = useState('');
  const [goalTargetStr, setGoalTargetStr] = useState('');
  const [goalDate, setGoalDate] = useState('');
  const [goalVaultId, setGoalVaultId] = useState('');

  // Fund / Withdraw Goal modal state
  const [fundGoalTarget, setFundGoalTarget] = useState<SharedSavingsGoal | null>(null);
  const [fundGoalDirection, setFundGoalDirection] = useState<'deposit' | 'withdraw'>('deposit');
  const [fundGoalAmtStr, setFundGoalAmtStr] = useState('');
  const [fundGoalSourceId, setFundGoalSourceId] = useState('');

  // Add Budget modal
  const [budgetModalOpen, setBudgetModalOpen] = useState(false);
  const [budgetCatId, setBudgetCatId] = useState('');
  const [budgetLimitStr, setBudgetLimitStr] = useState('');
  const [budgetRollover, setBudgetRollover] = useState(false);

  // Add Recurring modal
  const [recModalOpen, setRecModalOpen] = useState(false);
  const [recTitle, setRecTitle] = useState('');
  const [recType, setRecType] = useState<'expense' | 'income' | 'transfer' | 'commitment'>('commitment');
  const [recAmountStr, setRecAmountStr] = useState('');
  const [recFreq, setRecFreq] = useState<'weekly' | 'biweekly' | 'monthly' | 'quarterly' | 'yearly'>('monthly');
  const [recStartDate, setRecStartDate] = useState(todayIso);
  const [recEndDate, setRecEndDate] = useState('');
  const [recAccountId, setRecAccountId] = useState('');
  const [recDestinationAccountId, setRecDestinationAccountId] = useState('');
  const [recAutoPost, setRecAutoPost] = useState(false);
  const [linkComAccSelection, setLinkComAccSelection] = useState<Record<string, string>>({});

  const openSettleCommitment = (c: SharedCommitment) => {
    const remaining = c.legacyPaidUnverified
      ? c.amountCents
      : getCommitmentRemainingCents(c, commitmentSettlements, entries);
    setSettleComTarget(c);
    setSettleComAccId(c.linkedAccountId || liquidEtbAccounts[0]?.id || allSpendableAccounts[0]?.id || '');
    setSettleComAmtStr(centsToInputText(remaining));
    setSettleComDate(todayIso);
  };

  const openSettleDebt = (d: Debt) => {
    setSettleDebtTarget(d);
    setSettleDebtAccId(liquidEtbAccounts[0]?.id || '');
    setSettleDebtPrincipalStr(centsToInputText(d.outstandingCents));
    setSettleDebtInterestStr('0');
    setSettleDebtFeeStr('0');
    setSettleDebtDate(todayIso);
  };

  const openFundGoal = (g: SharedSavingsGoal, direction: 'deposit' | 'withdraw' = 'deposit') => {
    setFundGoalTarget(g);
    setFundGoalDirection(direction);
    setFundGoalAmtStr('');
    setFundGoalSourceId(liquidEtbAccounts[0]?.id || '');
  };

  const handleSubmitCommitment = (e: React.FormEvent) => {
    e.preventDefault();
    const cents = tryParseStrictDecimalToCents(comAmountStr);
    if (!comTitle.trim() || cents === null || cents <= 0) {
      setBanner('Commitment title and a valid positive ETB amount are required.');
      return;
    }
    const res = onAddCommitment({
      title: comTitle.trim(),
      amountCents: cents,
      dueDate: comDueDate || todayIso,
      direction: comDirection,
      categoryId: comCategoryId || undefined,
      linkedAccountId: comLinkedAccountId || undefined,
      legacyPaidUnverified: false,
    });
    if (res && !res.ok) {
      setBanner(res.error || 'Could not save commitment.');
      return;
    }
    setComModalOpen(false);
    setComTitle('');
    setComAmountStr('');
    setComLinkedAccountId('');
  };

  const handleSubmitSettleCommitment = (e: React.FormEvent) => {
    e.preventDefault();
    if (!settleComTarget) return;
    const cents = tryParseStrictDecimalToCents(settleComAmtStr);
    if (cents === null || cents <= 0) {
      setBanner('Enter a valid positive ETB settlement amount.');
      return;
    }
    const res = onRecordCommitmentSettlement({
      commitmentId: settleComTarget.id,
      accountId: settleComAccId,
      amountCents: cents,
      settledDateIso: settleComDate,
    });
    if (!res.ok) {
      setBanner(res.error || 'Could not settle commitment.');
      return;
    }
    setSettleComTarget(null);
  };

  const handleSubmitSettleDebt = (e: React.FormEvent) => {
    e.preventDefault();
    if (!settleDebtTarget) return;
    const principalCents = tryParseStrictDecimalToCents(settleDebtPrincipalStr);
    const interestCents = settleDebtInterestStr.trim()
      ? tryParseStrictDecimalToCents(settleDebtInterestStr)
      : 0;
    const feeCents = settleDebtFeeStr.trim()
      ? tryParseStrictDecimalToCents(settleDebtFeeStr)
      : 0;
    if (
      principalCents === null ||
      principalCents <= 0 ||
      interestCents === null ||
      interestCents < 0 ||
      feeCents === null ||
      feeCents < 0
    ) {
      setBanner('Enter valid ETB principal, interest, and fee amounts (up to 2 decimal places).');
      return;
    }
    const res = onSettleDebt({
      debtId: settleDebtTarget.id,
      accountId: settleDebtAccId,
      principalCents,
      interestCents,
      feeCents,
      dateIso: settleDebtDate,
    });
    if (!res.ok) {
      setBanner(res.error || 'Could not settle debt.');
      return;
    }
    setSettleDebtTarget(null);
  };

  const handleSubmitGoal = (e: React.FormEvent) => {
    e.preventDefault();
    const targetCents = tryParseStrictDecimalToCents(goalTargetStr);
    if (!goalTitle.trim() || targetCents === null || targetCents <= 0) {
      setBanner('Goal title and a valid positive ETB target are required.');
      return;
    }
    const res = onAddSavingsGoal({
      title: goalTitle.trim(),
      targetCents,
      targetDate: goalDate || undefined,
      linkedAccountId: goalVaultId || undefined,
    });
    if (res && !res.ok) {
      setBanner(res.error || 'Could not create savings goal.');
      return;
    }
    setGoalModalOpen(false);
    setGoalTitle('');
    setGoalTargetStr('');
    setGoalVaultId('');
  };

  const handleSubmitFundGoal = (e: React.FormEvent) => {
    e.preventDefault();
    if (!fundGoalTarget) return;
    const amountCents = tryParseStrictDecimalToCents(fundGoalAmtStr);
    if (amountCents === null || amountCents <= 0) {
      setBanner('Enter a valid positive ETB amount.');
      return;
    }
    if (fundGoalDirection === 'withdraw' && amountCents > fundGoalTarget.currentAllocatedCents) {
      setBanner(
        `Withdrawal exceeds goal balance (${formatBirr(fundGoalTarget.currentAllocatedCents)}).`
      );
      return;
    }
    const res = onFundSavingsGoal({
      goalId: fundGoalTarget.id,
      amountCents,
      direction: fundGoalDirection,
      sourceAccountId: fundGoalTarget.linkedAccountId ? fundGoalSourceId : undefined,
      dateIso: todayIso,
    });
    if (!res.ok) {
      setBanner(res.error || 'Could not update savings goal.');
      return;
    }
    setFundGoalTarget(null);
  };

  const handleSubmitBudget = (e: React.FormEvent) => {
    e.preventDefault();
    const limitCents = tryParseStrictDecimalToCents(budgetLimitStr);
    if (!budgetCatId || limitCents === null || limitCents <= 0) {
      setBanner('Select a category and enter a valid positive monthly ETB limit.');
      return;
    }
    onUpsertBudget({
      categoryId: budgetCatId,
      limitCents,
      rolloverEnabled: budgetRollover,
    });
    setBudgetModalOpen(false);
    setBudgetLimitStr('');
  };

  const handleSubmitRecurring = (e: React.FormEvent) => {
    e.preventDefault();
    const amountCents = tryParseStrictDecimalToCents(recAmountStr);
    if (!recTitle.trim() || amountCents === null || amountCents <= 0) {
      setBanner('Rule title and a valid positive ETB amount are required.');
      return;
    }
    const defaultSrcId = liquidEtbAccounts[0]?.id || allSpendableAccounts[0]?.id || '';
    const resolvedAccId = recType === 'commitment'
      ? (recAccountId || undefined)
      : (recAccountId || defaultSrcId);
    const defaultDestId = allSpendableAccounts.find((a) => a.id !== resolvedAccId)?.id || '';
    const resolvedDestId = recType === 'transfer'
      ? (recDestinationAccountId || defaultDestId)
      : undefined;

    if (recType !== 'commitment' && !resolvedAccId) {
      setBanner('Select an active Verified ETB account first.');
      return;
    }
    if (recType === 'transfer' && (!resolvedDestId || resolvedDestId === resolvedAccId)) {
      setBanner('Select distinct source and destination Verified ETB accounts for a recurring transfer.');
      return;
    }

    const res = onAddRecurringRule({
      title: recTitle.trim(),
      ruleType: recType,
      amountCents,
      frequency: recFreq,
      interval: 1,
      startDate: recStartDate,
      nextOccurrenceDate: recStartDate,
      endDate: recEndDate || undefined,
      accountId: resolvedAccId,
      destinationAccountId: resolvedDestId,
      autoPost: recType === 'commitment' ? false : recAutoPost,
    });
    if (res && !res.ok) {
      setBanner(res.error || 'Could not create recurring rule.');
      return;
    }
    setRecModalOpen(false);
    setRecTitle('');
    setRecAmountStr('');
    setRecDestinationAccountId('');
  };

  return (
    <div className="space-y-6">
      {banner && (
        <DaywellStatusBanner
          tone="warning"
          message={banner}
          onDismiss={() => setBanner(null)}
        />
      )}

      {/* 1. Commitments (Bills & Expected Income) */}
      <DaywellCard padding="lg" radius="lg" className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div>
            <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
              Commitments (Bills &amp; Expected Income)
            </h3>
            <p className="text-xs text-[var(--dw-text-muted)]">
              Partial installment settlements · Expected inflows have 0 Safe Harbor boost until received
            </p>
          </div>
          <DaywellButton
            label="Add Commitment"
            variant="secondary"
            size="compact"
            leadingIcon={<Plus className="w-3.5 h-3.5" />}
            onClick={() => {
              setComDirection('outflow');
              setComDueDate(todayIso);
              setComLinkedAccountId(liquidEtbAccounts[0]?.id || allSpendableAccounts[0]?.id || '');
              setComModalOpen(true);
            }}
          />
        </div>

        <div className="divide-y divide-[var(--dw-divider)]">
          {commitments.length === 0 ? (
            <p className="py-5 text-center text-xs text-[var(--dw-text-muted)]">
              No commitments scheduled yet.
            </p>
          ) : (
            commitments.map((c) => {
              const settledCents = calculateCommitmentSettledCents(
                c.id,
                commitmentSettlements,
                entries
              );
              const remainingCents = getCommitmentRemainingCents(
                c,
                commitmentSettlements,
                entries
              );
              const cSettlements = commitmentSettlements.filter(
                (s) => s.commitmentId === c.id && !voidedEntryIds.has(s.entryId)
              );
              const isInflow = c.direction === 'inflow';
              const cmRes = resolveCommitmentCurrencyStatus({
                commitment: c,
                accountById,
                debtById,
                entryById,
                classificationsByEntryId,
                ruleById,
                settlementsByCommitmentId,
              });
              const cmCurrency = cmRes.currencyCode || '';
              const isEtbCommitment = cmRes.status === 'eligible_etb';
              const settledPct =
                c.amountCents > 0 ? Math.min(100, Math.round((settledCents / c.amountCents) * 100)) : 0;

              return (
                <div key={c.id} className="py-3 space-y-2 text-xs">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <div className="text-sm font-semibold text-[var(--dw-text-primary)] flex flex-wrap items-center gap-1.5">
                        <span>{c.title}</span>
                        {cmRes.status === 'excluded_non_etb' && (
                          <DaywellStatusBadge
                            tone="warning"
                            showIcon={false}
                            label={`Excluded (${cmCurrency})`}
                          />
                        )}
                        {cmRes.status === 'needs_review' && (
                          <DaywellStatusBadge tone="error" showIcon={false} label="Currency Review" />
                        )}
                      </div>
                      <div className="text-[var(--dw-text-muted)]">
                        {isInflow ? 'Expected Income' : 'Outflow Bill'} · Due {c.dueDate} ·{' '}
                        {c.legacyPaidUnverified
                          ? 'Needs Verification (0 Cash Impact)'
                          : c.isPaid
                          ? 'Paid'
                          : `Remaining ${formatCurrencyCents(remainingCents, isEtbCommitment ? 'ETB' : cmCurrency)}`}
                      </div>
                    </div>
                    <div className="flex flex-wrap items-center gap-2 shrink-0">
                      <span className="font-mono tabular-nums font-bold text-sm">
                        {formatCurrencyCents(c.amountCents, isEtbCommitment ? 'ETB' : cmCurrency)}
                      </span>
                      {!isEtbCommitment ? (
                        <div className="flex flex-wrap items-center gap-1.5">
                          {cmRes.status === 'needs_review' &&
                            !c.isPaid &&
                            !c.legacyPaidUnverified &&
                            onLinkCommitmentAccount &&
                            allSpendableAccounts.length > 0 && (
                              <>
                                <select
                                  value={linkComAccSelection[c.id] || allSpendableAccounts[0]?.id || ''}
                                  onChange={(e) =>
                                    setLinkComAccSelection((prev) => ({
                                      ...prev,
                                      [c.id]: e.target.value,
                                    }))
                                  }
                                  className="px-2 py-1 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] text-[11px]"
                                  aria-label={`Select ETB account for ${c.title}`}
                                >
                                  {allSpendableAccounts.map((a) => (
                                    <option key={a.id} value={a.id}>
                                      {a.name}
                                    </option>
                                  ))}
                                </select>
                                <DaywellButton
                                  label="Link ETB Account"
                                  variant="secondary"
                                  size="compact"
                                  onClick={() => {
                                    const targetAccId =
                                      linkComAccSelection[c.id] || allSpendableAccounts[0]?.id || '';
                                    const res = onLinkCommitmentAccount(c.id, targetAccId);
                                    if (!res.ok) {
                                      setBanner(res.error || 'Could not link ETB account.');
                                    }
                                  }}
                                />
                              </>
                            )}
                          <span className="text-[11px] text-[var(--dw-on-warning-container)] font-medium">
                            Read-only
                          </span>
                        </div>
                      ) : c.legacyPaidUnverified ? (
                        <>
                          <DaywellButton
                            label="Record Cash Payment"
                            variant="primary"
                            size="compact"
                            onClick={() => openSettleCommitment(c)}
                          />
                          <DaywellButton
                            label="Mark Unpaid"
                            variant="outlined"
                            size="compact"
                            onClick={() => onMarkLegacyUnpaid(c.id)}
                          />
                        </>
                      ) : !c.isPaid ? (
                        <DaywellButton
                          label={isInflow ? 'Record Receipt' : 'Pay Installment'}
                          variant="primary"
                          size="compact"
                          onClick={() => openSettleCommitment(c)}
                        />
                      ) : (
                        <span className="text-[var(--dw-on-income-container)] font-semibold flex items-center gap-1">
                          <CheckCircle2 className="w-3.5 h-3.5" />
                          Settled
                        </span>
                      )}
                    </div>
                  </div>

                  {settledCents > 0 && (
                    <DaywellProgressBar value={settledPct} label={`${c.title} settlement progress`} />
                  )}

                  {cSettlements.length > 0 && (
                    <div className="pl-3 border-l border-[var(--dw-border)] space-y-1">
                      {cSettlements.map((s) => (
                        <div key={s.id} className="flex items-center justify-between text-[11px] text-[var(--dw-text-muted)]">
                          <span>
                            Installment · {s.settledDate} ·{' '}
                            <span className="font-mono tabular-nums">
                              {formatCurrencyCents(s.amountCents, isEtbCommitment ? 'ETB' : cmCurrency)}
                            </span>
                          </span>
                          <button
                            type="button"
                            onClick={() =>
                              onRequestConfirm(
                                'Void Installment?',
                                `Void this settlement of ${formatCurrencyCents(s.amountCents, isEtbCommitment ? 'ETB' : cmCurrency)}?`,
                                'Void',
                                'danger',
                                () => onVoidCommitmentSettlement(s.id, c.id)
                              )
                            }
                            className="text-[var(--dw-error)] hover:underline cursor-pointer"
                          >
                            Void Settlement
                          </button>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              );
            })
          )}
        </div>
      </DaywellCard>

      {/* 2. Debts (Receivables & Payables) */}
      <DaywellCard padding="lg" radius="lg" className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div>
            <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
              Debts (Receivables &amp; Payables)
            </h3>
            <p className="text-xs text-[var(--dw-text-muted)]">
              Principal stays immutable (use Void &amp; Re-issue to adjust) · Interest &amp; fees separated on settlement
            </p>
          </div>
          <div className="flex items-center gap-2">
            <DaywellButton
              label="+ Lend Money"
              variant="secondary"
              size="compact"
              onClick={() => onOpenComposer('lend')}
            />
            <DaywellButton
              label="+ Borrow Money"
              variant="outlined"
              size="compact"
              onClick={() => onOpenComposer('borrow')}
            />
          </div>
        </div>

        <div className="divide-y divide-[var(--dw-divider)]">
          {debts.length === 0 ? (
            <p className="py-5 text-center text-xs text-[var(--dw-text-muted)]">
              No receivables or payables recorded yet.
            </p>
          ) : (
            debts.map((d) => {
              const partyName = partyById.get(d.partyId) || d.partyId;
              const entryById = new Map(entries.map((e) => [e.id, e]));
              const eligible = isDebtEligibleEtb(d, entryById, classificationsByEntryId);
              const originCls = classificationsByEntryId.get(d.originEntryId);
              const debtCurrency =
                originCls?.nativeCurrencyCode ||
                (originCls && originCls.touchedCurrencies.length === 1 && originCls.touchedCurrencies[0] !== 'UNVERIFIED'
                  ? originCls.touchedCurrencies[0]
                  : eligible
                  ? 'ETB'
                  : '');
              const isForeign = originCls?.status === 'excluded_non_etb';

              return (
                <div key={d.id} className="py-3 flex flex-wrap items-center justify-between gap-3 text-xs">
                  <div>
                    <div className="text-sm font-semibold text-[var(--dw-text-primary)] flex flex-wrap items-center gap-1.5">
                      <span>
                        {partyName} · {d.debtType === 'receivable' ? 'Owes Me' : 'I Owe'}
                      </span>
                      {isForeign && (
                        <DaywellStatusBadge
                          tone="warning"
                          showIcon={false}
                          label={`Excluded (${debtCurrency || 'Non-ETB'})`}
                        />
                      )}
                      {!eligible && !isForeign && (
                        <DaywellStatusBadge tone="error" showIcon={false} label="Currency Review" />
                      )}
                    </div>
                    <div className="text-[var(--dw-text-muted)]">
                      Principal{' '}
                      <span className="font-mono tabular-nums">
                        {formatCurrencyCents(d.principalCents, debtCurrency)}
                      </span>{' '}
                      · Outstanding{' '}
                      <span className="font-mono tabular-nums">
                        {formatCurrencyCents(d.outstandingCents, debtCurrency)}
                      </span>{' '}
                      · Status: {d.status}
                      {d.dueDate ? ` · Due ${d.dueDate}` : ''}
                    </div>
                  </div>
                  <div className="flex flex-wrap items-center gap-1.5 shrink-0">
                    {!eligible ? (
                      <span className="text-[11px] text-[var(--dw-on-warning-container)] font-medium">
                        Read-only
                      </span>
                    ) : (
                      <>
                        {d.status === 'active' && (
                          <>
                            <DaywellButton
                              label="Settle"
                              variant="primary"
                              size="compact"
                              onClick={() => openSettleDebt(d)}
                            />
                            <DaywellButton
                              label="Write Off"
                              variant="outlined"
                              size="compact"
                              onClick={() =>
                                onRequestConfirm(
                                  'Write Off Debt?',
                                  `Write off remaining ${formatBirr(d.outstandingCents)} for ${partyName}?`,
                                  'Write Off',
                                  'danger',
                                  () => onWriteOffDebt(d.id, 'Forgiven / written off')
                                )
                              }
                            />
                            <DaywellButton
                              label="Void & Re-issue"
                              variant="outlined"
                              size="compact"
                              leadingIcon={<Ban className="w-3 h-3" />}
                              onClick={() => {
                                const res = onVoidDebtOrigin(d.id);
                                if (!res.ok) setBanner(res.error || 'Cannot void debt.');
                              }}
                              className="!text-[var(--dw-error)] !border-[var(--dw-error)]/30"
                            />
                          </>
                        )}
                        {d.status === 'written_off' && d.writeOffEntryId && (
                          <DaywellButton
                            label="Void Write-Off"
                            variant="outlined"
                            size="compact"
                            leadingIcon={<RotateCcw className="w-3 h-3" />}
                            onClick={() => onVoidDebtWriteOff(d.id)}
                          />
                        )}
                      </>
                    )}
                  </div>
                </div>
              );
            })
          )}
        </div>
      </DaywellCard>

      {/* 3. Savings Goals */}
      <DaywellCard padding="lg" radius="lg" className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div>
            <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">Savings Goals</h3>
            <p className="text-xs text-[var(--dw-text-muted)]">
              Virtual earmarks (deducted from Safe Harbor) or vault-linked transfers
            </p>
          </div>
          <DaywellButton
            label="Add Goal"
            variant="secondary"
            size="compact"
            leadingIcon={<Plus className="w-3.5 h-3.5" />}
            onClick={() => setGoalModalOpen(true)}
          />
        </div>

        <div className="divide-y divide-[var(--dw-divider)]">
          {savingsGoals.length === 0 ? (
            <p className="py-5 text-center text-xs text-[var(--dw-text-muted)]">
              No savings goals created yet.
            </p>
          ) : (
            savingsGoals.map((g) => {
              const linkedVault = g.linkedAccountId ? accountById.get(g.linkedAccountId) : undefined;
              const vaultMissing = Boolean(g.linkedAccountId && !linkedVault);
              const vaultTier = linkedVault ? classifyCurrencyCode(linkedVault.currencyCode) : 'verified_etb';
              const vaultInvalidType = Boolean(
                linkedVault && (!isActiveVerifiedEtbAccount(linkedVault) || linkedVault.subType !== 'savings_vault')
              );
              const goalCurrency = vaultMissing
                ? ''
                : linkedVault
                ? linkedVault.currencyCode
                : 'ETB';
              const canFundGoal =
                !vaultMissing &&
                (!linkedVault ||
                  (isActiveVerifiedEtbAccount(linkedVault) && linkedVault.subType === 'savings_vault'));
              const isOverfundedVirtual =
                !g.linkedAccountId &&
                g.status !== 'archived' &&
                g.currentAllocatedCents > availableLiquidCashCents;
              const pct =
                g.targetCents > 0
                  ? Math.min(100, Math.round((g.currentAllocatedCents / g.targetCents) * 100))
                  : 0;
              return (
                <div key={g.id} className="py-3 space-y-2 text-xs">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <div className="text-sm font-semibold text-[var(--dw-text-primary)] flex flex-wrap items-center gap-1.5">
                        <span>{g.title}</span>
                        {!vaultMissing && vaultTier === 'verified_non_etb' && linkedVault && (
                          <DaywellStatusBadge
                            tone="warning"
                            showIcon={false}
                            label={`Excluded (${normalizeCurrencyCode(linkedVault.currencyCode)})`}
                          />
                        )}
                        {(vaultMissing || vaultTier === 'unverified' || (vaultTier === 'verified_etb' && vaultInvalidType)) && (
                          <DaywellStatusBadge tone="error" showIcon={false} label="Currency Review" />
                        )}
                      </div>
                      <div className="text-[var(--dw-text-muted)]">
                        {g.linkedAccountId
                          ? `Vault-linked (${linkedVault?.name || 'Missing Vault'})`
                          : 'Virtual Earmark'}{' '}
                        · Status: {g.status || 'active'}
                        {g.targetDate ? ` · Target ${g.targetDate}` : ''}
                      </div>
                    </div>
                    <div className="flex items-center gap-2 shrink-0">
                      <span className="font-mono tabular-nums font-bold">
                        {formatCurrencyCents(g.currentAllocatedCents, goalCurrency)} /{' '}
                        {formatCurrencyCents(g.targetCents, goalCurrency)}
                      </span>
                      {g.status !== 'archived' && (
                        <>
                          {canFundGoal ? (
                            <>
                              <DaywellButton
                                label="Fund"
                                variant="primary"
                                size="compact"
                                onClick={() => openFundGoal(g, 'deposit')}
                              />
                              {g.currentAllocatedCents > 0 && (
                                <DaywellButton
                                  label="Withdraw"
                                  variant="outlined"
                                  size="compact"
                                  onClick={() => openFundGoal(g, 'withdraw')}
                                />
                              )}
                            </>
                          ) : (
                            <span className="text-[11px] text-[var(--dw-on-warning-container)] font-medium">
                              Read-only
                            </span>
                          )}
                          <DaywellButton
                            label={g.linkedAccountId ? 'Archive Goal' : 'Release & Archive'}
                            variant="outlined"
                            size="compact"
                            leadingIcon={<Archive className="w-3 h-3" />}
                            onClick={() =>
                              onRequestConfirm(
                                g.linkedAccountId ? 'Archive Vault Goal?' : 'Release & Archive Goal?',
                                g.linkedAccountId
                                  ? `Archive goal "${g.title}"? Cash stays safely in the linked Savings Vault account until withdrawn.`
                                  : `Release ${formatCurrencyCents(g.currentAllocatedCents, goalCurrency)} reserved for "${g.title}" and archive it?`,
                                g.linkedAccountId ? 'Archive Goal' : 'Release & Archive',
                                'primary',
                                () => {
                                  const res = onReleaseAndArchiveGoal(g.id);
                                  if (res && !res.ok && res.error) {
                                    setBanner(res.error);
                                  }
                                }
                              )
                            }
                          />
                        </>
                      )}
                    </div>
                  </div>
                  <DaywellProgressBar value={pct} label={`${g.title} funding progress`} />
                  {isOverfundedVirtual && (
                    <div className="flex items-center gap-1.5 text-[var(--dw-on-warning-container)]">
                      <AlertTriangle className="w-3.5 h-3.5 shrink-0" />
                      <span>
                        Virtual reserve exceeds current liquid cash ({formatBirr(availableLiquidCashCents)}). Retained until withdrawn or released to archive.
                      </span>
                    </div>
                  )}
                </div>
              );
            })
          )}
        </div>
      </DaywellCard>

      {/* 4. Monthly Budgets & Recurring Rules */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {/* Budgets */}
        <DaywellCard padding="lg" radius="lg" className="space-y-3">
          <div className="flex items-center justify-between gap-2">
            <div>
              <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
                Monthly Budgets ({monthIso})
              </h3>
            </div>
            <DaywellButton
              label="+ Set Budget"
              variant="secondary"
              size="compact"
              onClick={() => {
                setBudgetCatId(categories.find((c) => c.type === 'expense')?.id || '');
                setBudgetModalOpen(true);
              }}
            />
          </div>
          <div className="space-y-2.5 text-xs">
            {budgets.length === 0 ? (
              <p className="py-4 text-center text-[var(--dw-text-muted)]">No monthly category budgets set.</p>
            ) : (
              budgets.map((b) => {
                const catName = categories.find((c) => c.id === b.categoryId)?.name || b.categoryId;
                const spent = currentMonthOccurrence.categoryBreakdown[catName] || 0;
                const pct = b.limitCents > 0 ? Math.min(100, Math.round((spent / b.limitCents) * 100)) : 0;
                const over = spent > b.limitCents;
                return (
                  <div key={b.id} className="space-y-1">
                    <div className="flex justify-between">
                      <span className="font-semibold text-[var(--dw-text-primary)]">{catName}</span>
                      <span className={`font-mono tabular-nums ${over ? 'text-[var(--dw-on-expense-container)]' : ''}`}>
                        {formatBirr(spent)} / {formatBirr(b.limitCents)}
                      </span>
                    </div>
                    <DaywellProgressBar
                      value={pct}
                      tone={over ? 'error' : 'primary'}
                      label={`${catName} budget usage`}
                    />
                  </div>
                );
              })
            )}
          </div>
        </DaywellCard>

        {/* Recurring Rules */}
        <DaywellCard padding="lg" radius="lg" className="space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div>
              <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">Recurring Rules</h3>
              <p className="text-[11px] text-[var(--dw-text-muted)]">Auto-post defaults off (opt-in)</p>
            </div>
            <div className="flex items-center gap-2">
              <DaywellButton
                label="Run Due Rules"
                variant="outlined"
                size="compact"
                onClick={() => {
                  const count = onProcessDueRules();
                  setBanner(
                    count > 0
                      ? `Processed ${count} due auto-post rule occurrence(s).`
                      : 'No active auto-post rules due today.'
                  );
                }}
              />
              <DaywellButton
                label="+ Add Rule"
                variant="secondary"
                size="compact"
                onClick={() => {
                  const defaultSrc = liquidEtbAccounts[0]?.id || allSpendableAccounts[0]?.id || '';
                  const defaultDst = allSpendableAccounts.find((a) => a.id !== defaultSrc)?.id || '';
                  setRecAccountId(defaultSrc);
                  setRecDestinationAccountId(defaultDst);
                  setRecModalOpen(true);
                }}
              />
            </div>
          </div>
          <div className="divide-y divide-[var(--dw-divider)] text-xs">
            {recurringRules.length === 0 ? (
              <p className="py-4 text-center text-[var(--dw-text-muted)]">No recurring schedules yet.</p>
            ) : (
              recurringRules.map((r) => {
                const srcAcc = r.accountId ? accountById.get(r.accountId) : undefined;
                const dstAcc = r.destinationAccountId
                  ? accountById.get(r.destinationAccountId)
                  : undefined;
                const srcTier = srcAcc ? classifyCurrencyCode(srcAcc.currencyCode) : 'verified_etb';
                const dstTier = dstAcc ? classifyCurrencyCode(dstAcc.currencyCode) : 'verified_etb';
                const missingAcc =
                  (r.ruleType !== 'commitment' && (!r.accountId || !srcAcc)) ||
                  (r.ruleType === 'transfer' && (!r.destinationAccountId || !dstAcc)) ||
                  Boolean(r.accountId && !srcAcc) ||
                  Boolean(r.destinationAccountId && !dstAcc);
                const nonEtbBlocked =
                  missingAcc ||
                  (srcAcc != null && !isActiveVerifiedEtbAccount(srcAcc)) ||
                  (dstAcc != null && !isActiveVerifiedEtbAccount(dstAcc));
                const ruleCurrency = srcAcc ? srcAcc.currencyCode : 'ETB';

                return (
                  <div key={r.id} className="py-2.5 flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <div className="font-semibold text-[var(--dw-text-primary)] flex flex-wrap items-center gap-1.5">
                        <span>{r.title}</span>
                        {srcTier === 'verified_non_etb' && srcAcc && (
                          <DaywellStatusBadge
                            tone="warning"
                            showIcon={false}
                            label={`Excluded (${normalizeCurrencyCode(srcAcc.currencyCode)})`}
                          />
                        )}
                        {(missingAcc || srcTier === 'unverified' || dstTier === 'unverified' || (!nonEtbBlocked ? false : dstTier === 'verified_non_etb')) && (
                          <DaywellStatusBadge tone="error" showIcon={false} label="Currency Review" />
                        )}
                      </div>
                      <div className="text-[var(--dw-text-muted)]">
                        {r.ruleType} · {r.frequency} · Next: {r.nextOccurrenceDate} ·{' '}
                        <span className="font-mono tabular-nums">
                          {formatCurrencyCents(r.amountCents, ruleCurrency)}
                        </span>
                      </div>
                    </div>
                    <div className="flex items-center gap-1.5 shrink-0">
                      <label className={`flex items-center gap-1 text-[11px] ${nonEtbBlocked ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}`}>
                        <input
                          type="checkbox"
                          checked={r.autoPost}
                          disabled={nonEtbBlocked && !r.autoPost}
                          onChange={() => onToggleRecurringAutoPost(r.id)}
                          className="accent-[var(--dw-primary)]"
                        />
                        Auto
                      </label>
                      <DaywellIconButton
                        label={r.isActive ? 'Pause rule' : 'Resume rule'}
                        size="compact"
                        tone="muted"
                        onClick={() => onToggleRecurringActive(r.id)}
                        icon={r.isActive ? <Pause className="w-3.5 h-3.5" /> : <Play className="w-3.5 h-3.5" />}
                      />
                      <DaywellIconButton
                        label="Skip next occurrence"
                        size="compact"
                        tone="muted"
                        onClick={() => onSkipNextRecurring(r.id)}
                        icon={<SkipForward className="w-3.5 h-3.5" />}
                      />
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </DaywellCard>
      </div>

      {/* Add Commitment Modal */}
      {comModalOpen && (
        <div role="dialog" aria-modal="true" aria-label="Add Commitment" className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4">
          <form
            onSubmit={handleSubmitCommitment}
            className="w-full max-w-md rounded-[var(--dw-radius-lg)] bg-[var(--dw-card)] border border-[var(--dw-border)] p-5 space-y-3 text-xs shadow-xl"
          >
            <div className="flex items-center justify-between">
              <h3 className="dw-type-title text-[var(--dw-text-primary)]">Add Commitment</h3>
              <DaywellIconButton
                label="Close"
                size="compact"
                tone="muted"
                onClick={() => setComModalOpen(false)}
                icon={<X className="w-4 h-4" />}
              />
            </div>
            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Title</label>
              <input
                type="text"
                value={comTitle}
                onChange={(e) => setComTitle(e.target.value)}
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
                placeholder="e.g. Monthly Rent or Retainer Invoice"
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Direction</label>
                <select
                  value={comDirection}
                  onChange={(e) => setComDirection(e.target.value as 'outflow' | 'inflow')}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
                >
                  <option value="outflow">Outflow (Bill)</option>
                  <option value="inflow">Inflow (Expected Income)</option>
                </select>
              </div>
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Amount (ETB)</label>
                <input
                  type="number"
                  step="0.01"
                  value={comAmountStr}
                  onChange={(e) => setComAmountStr(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
                />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Due Date</label>
                <input
                  type="date"
                  value={comDueDate}
                  onChange={(e) => setComDueDate(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
                />
              </div>
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Category</label>
                <select
                  value={comCategoryId}
                  onChange={(e) => setComCategoryId(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
                >
                  <option value="">Default</option>
                  {categories
                    .filter((c) => c.type === (comDirection === 'inflow' ? 'income' : 'expense'))
                    .map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.name}
                      </option>
                    ))}
                </select>
              </div>
            </div>
            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Default Account (Optional)</label>
              <select
                value={comLinkedAccountId}
                onChange={(e) => setComLinkedAccountId(e.target.value)}
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
              >
                <option value="">Select at payment</option>
                {allSpendableAccounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
              </select>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <DaywellButton label="Cancel" variant="text" size="compact" onClick={() => setComModalOpen(false)} />
              <DaywellButton type="submit" label="Save Commitment" variant="primary" size="compact" />
            </div>
          </form>
        </div>
      )}

      {/* Settle Commitment Modal */}
      {settleComTarget && (
        <div role="dialog" aria-modal="true" aria-label="Settle Commitment" className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4">
          <form
            onSubmit={handleSubmitSettleCommitment}
            className="w-full max-w-md rounded-[var(--dw-radius-lg)] bg-[var(--dw-card)] border border-[var(--dw-border)] p-5 space-y-3 text-xs shadow-xl"
          >
            <div className="flex items-center justify-between">
              <h3 className="dw-type-title text-[var(--dw-text-primary)]">
                {settleComTarget.direction === 'inflow' ? 'Record Receipt' : 'Pay Installment'} ·{' '}
                {settleComTarget.title}
              </h3>
              <DaywellIconButton
                label="Close"
                size="compact"
                tone="muted"
                onClick={() => setSettleComTarget(null)}
                icon={<X className="w-4 h-4" />}
              />
            </div>
            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Account</label>
              <select
                value={settleComAccId}
                onChange={(e) => setSettleComAccId(e.target.value)}
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
              >
                {allSpendableAccounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
              </select>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Amount (ETB)</label>
                <input
                  type="number"
                  step="0.01"
                  value={settleComAmtStr}
                  onChange={(e) => setSettleComAmtStr(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
                />
              </div>
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Date</label>
                <input
                  type="date"
                  value={settleComDate}
                  onChange={(e) => setSettleComDate(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
                />
              </div>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <DaywellButton label="Cancel" variant="text" size="compact" onClick={() => setSettleComTarget(null)} />
              <DaywellButton type="submit" label="Post Settlement" variant="primary" size="compact" />
            </div>
          </form>
        </div>
      )}

      {/* Settle Debt Modal */}
      {settleDebtTarget && (
        <div role="dialog" aria-modal="true" aria-label="Settle Debt" className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4">
          <form
            onSubmit={handleSubmitSettleDebt}
            className="w-full max-w-md rounded-[var(--dw-radius-lg)] bg-[var(--dw-card)] border border-[var(--dw-border)] p-5 space-y-3 text-xs shadow-xl"
          >
            <div className="flex items-center justify-between">
              <h3 className="dw-type-title text-[var(--dw-text-primary)]">
                Settle {settleDebtTarget.debtType === 'receivable' ? 'Receivable' : 'Payable'}
              </h3>
              <DaywellIconButton
                label="Close"
                size="compact"
                tone="muted"
                onClick={() => setSettleDebtTarget(null)}
                icon={<X className="w-4 h-4" />}
              />
            </div>
            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Cash / Bank Account</label>
              <select
                value={settleDebtAccId}
                onChange={(e) => setSettleDebtAccId(e.target.value)}
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
              >
                {liquidEtbAccounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
              </select>
            </div>
            <div className="grid grid-cols-3 gap-2">
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Principal</label>
                <input
                  type="number"
                  step="0.01"
                  value={settleDebtPrincipalStr}
                  onChange={(e) => setSettleDebtPrincipalStr(e.target.value)}
                  className="w-full px-2.5 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
                />
              </div>
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Interest</label>
                <input
                  type="number"
                  step="0.01"
                  value={settleDebtInterestStr}
                  onChange={(e) => setSettleDebtInterestStr(e.target.value)}
                  className="w-full px-2.5 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
                />
              </div>
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Fee</label>
                <input
                  type="number"
                  step="0.01"
                  value={settleDebtFeeStr}
                  onChange={(e) => setSettleDebtFeeStr(e.target.value)}
                  className="w-full px-2.5 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
                />
              </div>
            </div>
            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Settlement Date</label>
              <input
                type="date"
                value={settleDebtDate}
                onChange={(e) => setSettleDebtDate(e.target.value)}
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
              />
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <DaywellButton label="Cancel" variant="text" size="compact" onClick={() => setSettleDebtTarget(null)} />
              <DaywellButton type="submit" label="Post Settlement" variant="primary" size="compact" />
            </div>
          </form>
        </div>
      )}

      {/* Add Goal Modal */}
      {goalModalOpen && (
        <div role="dialog" aria-modal="true" aria-label="Add Savings Goal" className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4">
          <form
            onSubmit={handleSubmitGoal}
            className="w-full max-w-md rounded-[var(--dw-radius-lg)] bg-[var(--dw-card)] border border-[var(--dw-border)] p-5 space-y-3 text-xs shadow-xl"
          >
            <div className="flex items-center justify-between">
              <h3 className="dw-type-title text-[var(--dw-text-primary)]">Add Savings Goal</h3>
              <DaywellIconButton
                label="Close"
                size="compact"
                tone="muted"
                onClick={() => setGoalModalOpen(false)}
                icon={<X className="w-4 h-4" />}
              />
            </div>
            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Title</label>
              <input
                type="text"
                value={goalTitle}
                onChange={(e) => setGoalTitle(e.target.value)}
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Target (ETB)</label>
                <input
                  type="number"
                  step="0.01"
                  value={goalTargetStr}
                  onChange={(e) => setGoalTargetStr(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
                />
              </div>
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Target Date</label>
                <input
                  type="date"
                  value={goalDate}
                  onChange={(e) => setGoalDate(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
                />
              </div>
            </div>
            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Funding Mode</label>
              <select
                value={goalVaultId}
                onChange={(e) => setGoalVaultId(e.target.value)}
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
              >
                <option value="">Virtual Earmark (Reserves from Liquid Cash)</option>
                {vaultAccounts.map((v) => (
                  <option key={v.id} value={v.id}>
                    Linked Vault: {v.name}
                  </option>
                ))}
              </select>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <DaywellButton label="Cancel" variant="text" size="compact" onClick={() => setGoalModalOpen(false)} />
              <DaywellButton type="submit" label="Create Goal" variant="primary" size="compact" />
            </div>
          </form>
        </div>
      )}

      {/* Fund / Withdraw Goal Modal */}
      {fundGoalTarget && (
        <div role="dialog" aria-modal="true" aria-label="Savings Goal Transfer" className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4">
          <form
            onSubmit={handleSubmitFundGoal}
            className="w-full max-w-md rounded-[var(--dw-radius-lg)] bg-[var(--dw-card)] border border-[var(--dw-border)] p-5 space-y-3 text-xs shadow-xl"
          >
            <div className="flex items-center justify-between">
              <h3 className="dw-type-title text-[var(--dw-text-primary)]">
                {fundGoalDirection === 'withdraw' ? 'Withdraw from Goal' : 'Fund Goal'} · {fundGoalTarget.title}
              </h3>
              <DaywellIconButton
                label="Close"
                size="compact"
                tone="muted"
                onClick={() => setFundGoalTarget(null)}
                icon={<X className="w-4 h-4" />}
              />
            </div>

            <div className="flex gap-1.5">
              <button
                type="button"
                onClick={() => setFundGoalDirection('deposit')}
                className={`flex-1 py-1.5 px-2.5 rounded-[var(--dw-radius-sm)] font-semibold cursor-pointer ${
                  fundGoalDirection === 'deposit'
                    ? 'bg-[var(--dw-primary)] text-[var(--dw-on-primary)]'
                    : 'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-secondary)]'
                }`}
              >
                Deposit / Allocate
              </button>
              <button
                type="button"
                disabled={fundGoalTarget.currentAllocatedCents <= 0}
                onClick={() => setFundGoalDirection('withdraw')}
                className={`flex-1 py-1.5 px-2.5 rounded-[var(--dw-radius-sm)] font-semibold ${
                  fundGoalDirection === 'withdraw'
                    ? 'bg-[var(--dw-primary)] text-[var(--dw-on-primary)] cursor-pointer'
                    : fundGoalTarget.currentAllocatedCents <= 0
                    ? 'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-disabled)] opacity-50 cursor-not-allowed'
                    : 'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-secondary)] cursor-pointer'
                }`}
              >
                Withdraw
              </button>
            </div>

            <div className="text-[11px] text-[var(--dw-text-muted)]">
              Current balance: <span className="font-mono font-semibold text-[var(--dw-text-primary)]">{formatBirr(fundGoalTarget.currentAllocatedCents)}</span>
            </div>

            {fundGoalTarget.linkedAccountId && (
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                  {fundGoalDirection === 'withdraw'
                    ? 'Return Funds To Liquid Account'
                    : 'Transfer From Liquid Account'}
                </label>
                <select
                  value={fundGoalSourceId}
                  onChange={(e) => setFundGoalSourceId(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
                >
                  {liquidEtbAccounts.map((a) => (
                    <option key={a.id} value={a.id}>
                      {a.name}
                    </option>
                  ))}
                </select>
              </div>
            )}
            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Amount (ETB)</label>
              <input
                type="number"
                step="0.01"
                value={fundGoalAmtStr}
                onChange={(e) => setFundGoalAmtStr(e.target.value)}
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
              />
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <DaywellButton label="Cancel" variant="text" size="compact" onClick={() => setFundGoalTarget(null)} />
              <DaywellButton
                type="submit"
                label={fundGoalDirection === 'withdraw' ? 'Withdraw' : 'Allocate'}
                variant="primary"
                size="compact"
              />
            </div>
          </form>
        </div>
      )}

      {/* Set Budget Modal */}
      {budgetModalOpen && (
        <div role="dialog" aria-modal="true" aria-label="Set Category Budget" className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4">
          <form
            onSubmit={handleSubmitBudget}
            className="w-full max-w-md rounded-[var(--dw-radius-lg)] bg-[var(--dw-card)] border border-[var(--dw-border)] p-5 space-y-3 text-xs shadow-xl"
          >
            <div className="flex items-center justify-between">
              <h3 className="dw-type-title text-[var(--dw-text-primary)]">Set Category Budget ({monthIso})</h3>
              <DaywellIconButton
                label="Close"
                size="compact"
                tone="muted"
                onClick={() => setBudgetModalOpen(false)}
                icon={<X className="w-4 h-4" />}
              />
            </div>
            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Expense Category</label>
              <select
                value={budgetCatId}
                onChange={(e) => setBudgetCatId(e.target.value)}
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
              >
                {categories
                  .filter((c) => c.type === 'expense' && !c.isArchived)
                  .map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name}
                    </option>
                  ))}
              </select>
            </div>
            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Monthly Limit (ETB)</label>
              <input
                type="number"
                step="0.01"
                value={budgetLimitStr}
                onChange={(e) => setBudgetLimitStr(e.target.value)}
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
              />
            </div>
            <label className="flex items-center gap-2 cursor-pointer text-[var(--dw-text-secondary)]">
              <input
                type="checkbox"
                checked={budgetRollover}
                onChange={(e) => setBudgetRollover(e.target.checked)}
                className="accent-[var(--dw-primary)]"
              />
              Rollover unused budget
            </label>
            <div className="flex justify-end gap-2 pt-2">
              <DaywellButton label="Cancel" variant="text" size="compact" onClick={() => setBudgetModalOpen(false)} />
              <DaywellButton type="submit" label="Save Budget" variant="primary" size="compact" />
            </div>
          </form>
        </div>
      )}

      {/* Add Recurring Rule Modal */}
      {recModalOpen && (
        <div role="dialog" aria-modal="true" aria-label="Add Recurring Rule" className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4">
          <form
            onSubmit={handleSubmitRecurring}
            className="w-full max-w-md rounded-[var(--dw-radius-lg)] bg-[var(--dw-card)] border border-[var(--dw-border)] p-5 space-y-3 text-xs shadow-xl"
          >
            <div className="flex items-center justify-between">
              <h3 className="dw-type-title text-[var(--dw-text-primary)]">Add Recurring Rule</h3>
              <DaywellIconButton
                label="Close"
                size="compact"
                tone="muted"
                onClick={() => setRecModalOpen(false)}
                icon={<X className="w-4 h-4" />}
              />
            </div>
            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Title</label>
              <input
                type="text"
                value={recTitle}
                onChange={(e) => setRecTitle(e.target.value)}
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Type</label>
                <select
                  value={recType}
                  onChange={(e) => setRecType(e.target.value as any)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
                >
                  <option value="commitment">Commitment</option>
                  <option value="expense">Expense</option>
                  <option value="income">Income</option>
                  <option value="transfer">Transfer</option>
                </select>
              </div>
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Frequency</label>
                <select
                  value={recFreq}
                  onChange={(e) => setRecFreq(e.target.value as any)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
                >
                  <option value="weekly">Weekly</option>
                  <option value="biweekly">Biweekly</option>
                  <option value="monthly">Monthly</option>
                  <option value="quarterly">Quarterly</option>
                  <option value="yearly">Yearly</option>
                </select>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Amount (ETB)</label>
                <input
                  type="number"
                  step="0.01"
                  value={recAmountStr}
                  onChange={(e) => setRecAmountStr(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
                />
              </div>
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                  {recType === 'transfer' ? 'From ETB Account' : 'ETB Account'}
                </label>
                <select
                  value={recAccountId}
                  onChange={(e) => setRecAccountId(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
                >
                  {recType === 'commitment' && <option value="">None (Unlinked)</option>}
                  {allSpendableAccounts.map((a) => (
                    <option key={a.id} value={a.id}>
                      {a.name}
                    </option>
                  ))}
                </select>
              </div>
            </div>
            {recType === 'transfer' && (
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">To ETB Account</label>
                <select
                  value={recDestinationAccountId}
                  onChange={(e) => setRecDestinationAccountId(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
                >
                  {allSpendableAccounts
                    .filter((a) => a.id !== recAccountId)
                    .map((a) => (
                      <option key={a.id} value={a.id}>
                        {a.name}
                      </option>
                    ))}
                </select>
              </div>
            )}
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Start / Next Date</label>
                <input
                  type="date"
                  value={recStartDate}
                  onChange={(e) => setRecStartDate(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
                />
              </div>
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">End Date (Optional)</label>
                <input
                  type="date"
                  value={recEndDate}
                  onChange={(e) => setRecEndDate(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
                />
              </div>
            </div>
            <label className="flex items-center gap-2 cursor-pointer text-[var(--dw-text-secondary)]">
              <input
                type="checkbox"
                checked={recAutoPost}
                onChange={(e) => setRecAutoPost(e.target.checked)}
                className="accent-[var(--dw-primary)]"
              />
              Auto-post automatically when due (default off)
            </label>
            <div className="flex justify-end gap-2 pt-2">
              <DaywellButton label="Cancel" variant="text" size="compact" onClick={() => setRecModalOpen(false)} />
              <DaywellButton type="submit" label="Create Rule" variant="primary" size="compact" />
            </div>
          </form>
        </div>
      )}
    </div>
  );
}
