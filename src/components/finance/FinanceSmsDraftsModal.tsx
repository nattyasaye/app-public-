import React, { useEffect, useMemo, useState } from 'react';
import {
  AlertTriangle,
  Check,
  ChevronDown,
  ChevronRight,
  MessageSquareText,
  Upload,
  X,
} from 'lucide-react';
import { Account, formatCurrencyCents, getAccountSubType, isActiveVerifiedEtbAccount, TransactionCategory } from '../../domain/financeV7Engine';
import { DEFAULT_EXPENSE_CATEGORIES } from '../../domain/doubleEntryFinance';
import {
  buildDefaultDraftDescription,
  FinanceSmsDraft,
  resolveDefaultDraftOccurrenceDate,
  SMS_FEE_DEFAULT_CATEGORY_ID,
  SMS_PROVIDER_LABELS,
  SmsDraftStatus,
  SmsImportBatchSummary,
  SmsProvider,
  suggestTransferDestinationAccount,
  totalDraftFeesCents,
} from '../../domain/financeSms';
import { SHARED_DESIGN_TOKENS } from '../../domain/sharedFoundation';
import { splitSmsBatchInput } from '../../services/financeSmsService';
import {
  DaywellButton,
  DaywellCard,
  DaywellEmptyState,
  DaywellIconButton,
  DaywellStatusBadge,
  DaywellStatusBanner,
  DaywellStatusTone,
} from '../ui';

type DraftFilterTab = SmsDraftStatus | 'all';

interface DraftEditState {
  finalType: 'expense' | 'income' | 'transfer' | '';
  accountId: string;
  destinationAccountId: string;
  categoryId: string;
  feeCategoryId: string;
  occurrenceDate: string;
  description: string;
  payee: string;
}

export interface FinanceSmsDraftsModalProps {
  isOpen: boolean;
  drafts: FinanceSmsDraft[];
  accounts: Account[];
  categories: TransactionCategory[];
  onClose: () => void;
  onImportMessages: (payload: {
    rawMessages: string[];
    providerHint?: SmsProvider;
  }) => SmsImportBatchSummary;
  onUpdateDraftReview: (payload: {
    draftId: string;
    suggestedType?: 'expense' | 'income' | 'transfer' | 'unknown';
    suggestedAccountId?: string;
    suggestedCategoryId?: string;
  }) => { ok: boolean; error?: string };
  onDismissDraft: (draftId: string) => { ok: boolean; error?: string };
  onApproveDraft: (payload: {
    draftId: string;
    finalType: 'expense' | 'income' | 'transfer';
    accountId: string;
    destinationAccountId?: string;
    categoryId?: string;
    feeCategoryId?: string;
    occurrenceDate: string;
    description: string;
    payee?: string;
  }) => { ok: boolean; error?: string };
}

function statusBadgeMeta(status: SmsDraftStatus): { label: string; tone: DaywellStatusTone } {
  switch (status) {
    case 'needs_review':
      return { label: 'Needs Review', tone: 'warning' };
    case 'approved':
      return { label: 'Approved', tone: 'success' };
    case 'dismissed':
      return { label: 'Dismissed', tone: 'neutral' };
    case 'unrecognized':
    default:
      return { label: 'Unrecognized / Notice', tone: 'info' };
  }
}

function directionBadgeMeta(draft: FinanceSmsDraft): { label: string; tone: DaywellStatusTone } {
  if (draft.direction === 'incoming') return { label: 'Incoming', tone: 'income' };
  if (draft.direction === 'outgoing') return { label: 'Outgoing', tone: 'expense' };
  return { label: 'Uncertain', tone: 'neutral' };
}

export function FinanceSmsDraftsModal({
  isOpen,
  drafts,
  accounts,
  categories,
  onClose,
  onImportMessages,
  onUpdateDraftReview,
  onDismissDraft,
  onApproveDraft,
}: FinanceSmsDraftsModalProps) {
  const [filterTab, setFilterTab] = useState<DraftFilterTab>('needs_review');
  const [pasteInput, setPasteInput] = useState('');
  const [providerHint, setProviderHint] = useState<'auto' | SmsProvider>('auto');
  const [importSummary, setImportSummary] = useState<SmsImportBatchSummary | null>(null);
  const [errorByDraftId, setErrorByDraftId] = useState<Record<string, string>>({});
  const [globalError, setGlobalError] = useState<string | null>(null);
  const [expandedRawIds, setExpandedRawIds] = useState<Record<string, boolean>>({});
  const [editMap, setEditMap] = useState<Record<string, DraftEditState>>({});

  const activeEtbAccounts = useMemo(
    () => accounts.filter((a) => isActiveVerifiedEtbAccount(a)),
    [accounts]
  );

  const spendableAccounts = useMemo(
    () =>
      activeEtbAccounts.filter((a) => {
        const sub = getAccountSubType(a);
        return (
          (a.type === 'asset' && sub !== 'savings_vault' && sub !== 'receivable') ||
          (a.type === 'liability' && sub === 'credit_card')
        );
      }),
    [activeEtbAccounts]
  );

  const transferableAccounts = useMemo(
    () =>
      activeEtbAccounts.filter((a) => {
        const sub = getAccountSubType(a);
        return (
          (a.type === 'asset' && sub !== 'receivable') ||
          (a.type === 'liability' && sub === 'credit_card')
        );
      }),
    [activeEtbAccounts]
  );

  const expenseCategories = useMemo(
    () => categories.filter((c) => c.type === 'expense' && !c.isArchived),
    [categories]
  );
  const incomeCategories = useMemo(
    () => categories.filter((c) => c.type === 'income' && !c.isArchived),
    [categories]
  );
  const feeCategoryOptions = useMemo(() => {
    if (expenseCategories.some((c) => c.id === SMS_FEE_DEFAULT_CATEGORY_ID)) {
      return expenseCategories;
    }
    return [
      {
        id: SMS_FEE_DEFAULT_CATEGORY_ID,
        name: 'Financial Fees',
        type: 'expense' as const,
        colorHex:
          DEFAULT_EXPENSE_CATEGORIES.find((c) => c.id === SMS_FEE_DEFAULT_CATEGORY_ID)?.colorHex ??
          SHARED_DESIGN_TOKENS.colors.text.mutedLight,
        isArchived: false,
      },
      ...expenseCategories,
    ];
  }, [expenseCategories]);

  useEffect(() => {
    if (!isOpen) return;
    setGlobalError(null);
    setErrorByDraftId({});
  }, [isOpen]);

  const buildInitialEditState = (draft: FinanceSmsDraft): DraftEditState => {
    const finalType: DraftEditState['finalType'] =
      draft.suggestedType === 'expense' ||
      draft.suggestedType === 'income' ||
      draft.suggestedType === 'transfer'
        ? draft.suggestedType
        : '';
    const accountPool = finalType === 'transfer' ? transferableAccounts : spendableAccounts;
    const validSuggestedAcc =
      draft.suggestedAccountId && accountPool.some((a) => a.id === draft.suggestedAccountId)
        ? draft.suggestedAccountId
        : accountPool[0]?.id || '';
    const suggestedDest =
      suggestTransferDestinationAccount(
        { ...draft, suggestedAccountId: validSuggestedAcc },
        accounts
      ) ||
      transferableAccounts.find((a) => a.id !== validSuggestedAcc)?.id ||
      '';
    const catPool = finalType === 'income' ? incomeCategories : expenseCategories;
    const validCat =
      draft.suggestedCategoryId && catPool.some((c) => c.id === draft.suggestedCategoryId)
        ? draft.suggestedCategoryId
        : catPool[0]?.id ||
          (finalType === 'income' ? 'cat-other-inc' : 'cat-other-exp');

    return {
      finalType,
      accountId: validSuggestedAcc,
      destinationAccountId: suggestedDest,
      categoryId: validCat,
      feeCategoryId: SMS_FEE_DEFAULT_CATEGORY_ID,
      occurrenceDate: resolveDefaultDraftOccurrenceDate(draft),
      description: buildDefaultDraftDescription(draft),
      payee: draft.counterpartyName || '',
    };
  };

  const getDraftEdit = (draft: FinanceSmsDraft): DraftEditState => {
    return editMap[draft.id] ?? buildInitialEditState(draft);
  };

  const updateDraftEdit = (
    draft: FinanceSmsDraft,
    updater: (prev: DraftEditState) => DraftEditState
  ) => {
    setEditMap((prev) => {
      const current = prev[draft.id] ?? buildInitialEditState(draft);
      return { ...prev, [draft.id]: updater(current) };
    });
  };

  const counts = useMemo(() => {
    let needsReview = 0;
    let unrecognized = 0;
    let approved = 0;
    let dismissed = 0;
    for (const d of drafts) {
      if (d.status === 'needs_review') needsReview += 1;
      else if (d.status === 'unrecognized') unrecognized += 1;
      else if (d.status === 'approved') approved += 1;
      else if (d.status === 'dismissed') dismissed += 1;
    }
    return {
      needsReview,
      unrecognized,
      approved,
      dismissed,
      all: drafts.length,
    };
  }, [drafts]);

  const filteredDrafts = useMemo(() => {
    if (filterTab === 'all') return drafts;
    return drafts.filter((d) => d.status === filterTab);
  }, [drafts, filterTab]);

  if (!isOpen) return null;

  const handleImportSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const messages = splitSmsBatchInput(pasteInput);
    if (messages.length === 0) {
      setGlobalError('Paste one or more CBE, Telebirr, or BOA SMS messages first.');
      return;
    }
    setGlobalError(null);
    const summary = onImportMessages({
      rawMessages: messages,
      providerHint: providerHint === 'auto' ? undefined : providerHint,
    });
    setImportSummary(summary);
    setPasteInput('');
    if (summary.importedCount > 0) {
      setFilterTab('needs_review');
    } else if (summary.unrecognizedCount > 0) {
      setFilterTab('unrecognized');
    }
  };

  const filterDefs: Array<{ id: DraftFilterTab; label: string; count: number }> = [
    { id: 'needs_review', label: 'Needs Review', count: counts.needsReview },
    { id: 'unrecognized', label: 'Unrecognized', count: counts.unrecognized },
    { id: 'approved', label: 'Approved', count: counts.approved },
    { id: 'dismissed', label: 'Dismissed', count: counts.dismissed },
    { id: 'all', label: 'All', count: counts.all },
  ];

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="sms-drafts-modal-title"
      className="fixed inset-0 z-50 bg-black/60 backdrop-blur-xs flex items-center justify-center p-3 sm:p-4"
    >
      <div className="bg-[var(--dw-elevated)] border border-[var(--dw-border)] rounded-[var(--dw-radius-xl)] max-w-2xl w-full max-h-[90vh] flex flex-col shadow-2xl overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between gap-3 px-4 py-3.5 border-b border-[var(--dw-divider)] bg-[var(--dw-card)]">
          <div className="flex items-center gap-2.5 min-w-0">
            <span
              className="w-9 h-9 rounded-[var(--dw-radius-md)] bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] inline-flex items-center justify-center shrink-0"
              aria-hidden="true"
            >
              <MessageSquareText className="w-4 h-4" />
            </span>
            <div className="min-w-0">
              <h2
                id="sms-drafts-modal-title"
                className="dw-type-title text-[var(--dw-text-primary)] truncate"
              >
                Financial SMS Drafts
              </h2>
              <p className="text-[11px] text-[var(--dw-text-muted)] truncate">
                CBE · Telebirr · Bank of Abyssinia (BOA)
              </p>
            </div>
          </div>
          <DaywellIconButton
            label="Close SMS drafts"
            icon={<X className="w-4 h-4" />}
            onClick={onClose}
          />
        </div>

        {/* Scrollable Content */}
        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          <DaywellStatusBanner
            tone="info"
            title="Review Required Before Ledger Posting"
            message="Imported SMS messages stay in local review drafts only. Nothing affects account balances, budgets, or reports until you explicitly click Approve & Post."
          />

          {globalError && (
            <DaywellStatusBanner
              tone="error"
              message={globalError}
              onDismiss={() => setGlobalError(null)}
            />
          )}

          {/* Paste / Import SMS Section */}
          <DaywellCard variant="subtle" padding="md" radius="lg" className="space-y-3">
            <form onSubmit={handleImportSubmit} className="space-y-3">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <span className="text-xs font-bold text-[var(--dw-text-primary)]">
                  Import SMS Message(s)
                </span>
                <div className="flex items-center gap-2">
                  <label
                    htmlFor="sms-provider-hint"
                    className="text-[11px] text-[var(--dw-text-muted)] font-medium"
                  >
                    Provider hint:
                  </label>
                  <select
                    id="sms-provider-hint"
                    value={providerHint}
                    onChange={(e) => setProviderHint(e.target.value as 'auto' | SmsProvider)}
                    className="px-2.5 py-1.5 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-xs text-[var(--dw-text-primary)]"
                  >
                    <option value="auto">Auto-detect</option>
                    <option value="cbe">CBE</option>
                    <option value="telebirr">Telebirr</option>
                    <option value="boa">BOA</option>
                  </select>
                </div>
              </div>

              <textarea
                value={pasteInput}
                onChange={(e) => setPasteInput(e.target.value)}
                rows={4}
                aria-label="Paste CBE, Telebirr, or BOA SMS text"
                placeholder="Paste one or more CBE, Telebirr, or BOA SMS messages here. Separate multiple messages with a blank line or ---"
                className="w-full rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-[var(--dw-text-primary)] placeholder:text-[var(--dw-text-muted)] p-3 text-xs leading-relaxed focus:outline-none focus:border-[var(--dw-primary)] focus:ring-2 focus:ring-[var(--dw-primary)]/20"
              />

              <div className="flex flex-wrap items-center justify-between gap-2">
                <span className="text-[11px] text-[var(--dw-text-muted)]">
                  Parsed 100% offline. Receipt URLs are never fetched.
                </span>
                <DaywellButton
                  type="submit"
                  label="Import as Drafts"
                  variant="primary"
                  size="compact"
                  leadingIcon={<Upload className="w-3.5 h-3.5" />}
                />
              </div>
            </form>

            {importSummary && (
              <DaywellStatusBanner
                tone={importSummary.importedCount > 0 ? 'success' : 'info'}
                message={`${importSummary.importedCount} ready for review · ${importSummary.unrecognizedCount} unrecognized/notices · ${importSummary.duplicateCount} duplicates skipped · ${importSummary.ignoredCount} non-transactional ignored.`}
                onDismiss={() => setImportSummary(null)}
              />
            )}
          </DaywellCard>

          {/* Status Filter Tabs */}
          <div
            role="tablist"
            aria-label="SMS draft status filter"
            className="flex flex-wrap gap-1.5"
          >
            {filterDefs.map((tab) => {
              const active = filterTab === tab.id;
              return (
                <button
                  key={tab.id}
                  type="button"
                  role="tab"
                  aria-selected={active}
                  onClick={() => setFilterTab(tab.id)}
                  className={`px-3 py-1.5 rounded-[var(--dw-radius-sm)] text-xs font-semibold border transition-colors cursor-pointer ${
                    active
                      ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border-[var(--dw-primary)]/40'
                      : 'bg-[var(--dw-card)] text-[var(--dw-text-secondary)] border-[var(--dw-border)] hover:bg-[var(--dw-surface-subtle)]'
                  }`}
                >
                  {tab.label} ({tab.count})
                </button>
              );
            })}
          </div>

          {/* Draft List */}
          {filteredDrafts.length === 0 ? (
            <DaywellEmptyState
              icon={<MessageSquareText className="w-8 h-8" />}
              message="No SMS drafts in this view"
              subtitle="Paste a CBE, Telebirr, or BOA SMS above to parse and review it safely before posting."
            />
          ) : (
            <div className="space-y-3">
              {filteredDrafts.map((draft) => {
                const statusMeta = statusBadgeMeta(draft.status);
                const dirMeta = directionBadgeMeta(draft);
                const feesCents = totalDraftFeesCents(draft);
                const isRawExpanded = Boolean(expandedRawIds[draft.id]);
                const edit = getDraftEdit(draft);
                const accountPool =
                  edit.finalType === 'transfer' ? transferableAccounts : spendableAccounts;
                const catPool =
                  edit.finalType === 'income' ? incomeCategories : expenseCategories;
                const draftErr = errorByDraftId[draft.id];

                return (
                  <DaywellCard key={draft.id} padding="md" radius="lg" className="space-y-3">
                    {/* Top badges */}
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <div className="flex flex-wrap items-center gap-1.5">
                        <DaywellStatusBadge
                          label={SMS_PROVIDER_LABELS[draft.provider]}
                          tone="info"
                          showIcon={false}
                        />
                        <DaywellStatusBadge
                          label={dirMeta.label}
                          tone={dirMeta.tone}
                        />
                        <DaywellStatusBadge
                          label={statusMeta.label}
                          tone={statusMeta.tone}
                        />
                        {draft.confidence !== 'high' && (
                          <DaywellStatusBadge
                            label={`Confidence: ${draft.confidence}`}
                            tone={draft.confidence === 'unrecognized' ? 'neutral' : 'warning'}
                            showIcon={false}
                          />
                        )}
                      </div>
                      <span className="text-[11px] text-[var(--dw-text-muted)] tabular-nums">
                        {draft.transactionDateIso || resolveDefaultDraftOccurrenceDate(draft)}
                      </span>
                    </div>

                    {/* Amount breakdown */}
                    <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 p-2.5 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-xs">
                      <div>
                        <span className="block text-[10px] uppercase tracking-wider text-[var(--dw-text-muted)] font-semibold">
                          Principal
                        </span>
                        <span className="font-mono font-bold text-[var(--dw-text-primary)] tabular-nums">
                          {formatCurrencyCents(draft.principalCents, draft.currencyCode)}
                        </span>
                      </div>
                      <div>
                        <span className="block text-[10px] uppercase tracking-wider text-[var(--dw-text-muted)] font-semibold">
                          Fees & Charges
                        </span>
                        <span className="font-mono font-semibold text-[var(--dw-text-secondary)] tabular-nums">
                          {formatCurrencyCents(feesCents, draft.currencyCode)}
                        </span>
                      </div>
                      <div>
                        <span className="block text-[10px] uppercase tracking-wider text-[var(--dw-text-muted)] font-semibold">
                          Total Reported
                        </span>
                        <span className="font-mono font-semibold text-[var(--dw-text-primary)] tabular-nums">
                          {draft.totalAmountCents !== undefined
                            ? formatCurrencyCents(draft.totalAmountCents, draft.currencyCode)
                            : '—'}
                        </span>
                      </div>
                      <div>
                        <span className="block text-[10px] uppercase tracking-wider text-[var(--dw-text-muted)] font-semibold">
                          Reported Balance
                        </span>
                        <span className="font-mono text-[var(--dw-text-secondary)] tabular-nums">
                          {draft.reportedBalanceCents !== undefined
                            ? formatCurrencyCents(draft.reportedBalanceCents, draft.currencyCode)
                            : '—'}
                        </span>
                      </div>
                    </div>

                    {/* Fee breakdown detail if present */}
                    {feesCents > 0 && (
                      <div className="flex flex-wrap gap-3 text-[11px] text-[var(--dw-text-muted)] tabular-nums">
                        {draft.serviceFeeCents > 0 && (
                          <span>
                            Service Fee: {formatCurrencyCents(draft.serviceFeeCents, draft.currencyCode)}
                          </span>
                        )}
                        {draft.vatCents > 0 && (
                          <span>
                            VAT: {formatCurrencyCents(draft.vatCents, draft.currencyCode)}
                          </span>
                        )}
                        {draft.otherChargesCents > 0 && (
                          <span>
                            Disaster Recovery / Other:{' '}
                            {formatCurrencyCents(draft.otherChargesCents, draft.currencyCode)}
                          </span>
                        )}
                      </div>
                    )}

                    {/* Metadata */}
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-1.5 text-xs text-[var(--dw-text-secondary)]">
                      {draft.counterpartyName && (
                        <div>
                          <span className="text-[var(--dw-text-muted)]">Counterparty: </span>
                          <span className="font-medium text-[var(--dw-text-primary)]">
                            {draft.counterpartyName}
                          </span>
                          {draft.counterpartyHint ? ` (${draft.counterpartyHint})` : ''}
                        </div>
                      )}
                      {draft.accountHint && (
                        <div>
                          <span className="text-[var(--dw-text-muted)]">Account Hint: </span>
                          <span className="font-mono">{draft.accountHint}</span>
                        </div>
                      )}
                      {draft.transactionReference && (
                        <div>
                          <span className="text-[var(--dw-text-muted)]">Reference: </span>
                          <span className="font-mono">{draft.transactionReference}</span>
                        </div>
                      )}
                      {draft.receiptUrl && (
                        <div className="sm:col-span-2 truncate">
                          <span className="text-[var(--dw-text-muted)]">Receipt URL (offline ref): </span>
                          <span className="font-mono text-[11px] text-[var(--dw-text-secondary)]">
                            {draft.receiptUrl}
                          </span>
                        </div>
                      )}
                    </div>

                    {/* Warnings */}
                    {draft.hasAmountMismatch && (
                      <DaywellStatusBanner
                        tone="warning"
                        title="Total Mismatch Detected"
                        message={
                          draft.parseNotes ||
                          'Principal plus extracted fees does not match the total reported in the SMS. Verify amounts before approving.'
                        }
                      />
                    )}
                    {!draft.hasAmountMismatch &&
                      (draft.isNonLedgerNotice ||
                        draft.status === 'unrecognized' ||
                        draft.confidence === 'low' ||
                        draft.direction === 'uncertain') &&
                      draft.parseNotes && (
                        <DaywellStatusBanner
                          tone={draft.isNonLedgerNotice ? 'info' : 'warning'}
                          icon={<AlertTriangle className="w-4 h-4 shrink-0" />}
                          message={draft.parseNotes}
                        />
                      )}

                    {/* Collapsible raw local SMS text */}
                    <div>
                      <button
                        type="button"
                        onClick={() =>
                          setExpandedRawIds((prev) => ({
                            ...prev,
                            [draft.id]: !prev[draft.id],
                          }))
                        }
                        className="inline-flex items-center gap-1 text-[11px] font-semibold text-[var(--dw-primary)] hover:underline cursor-pointer"
                      >
                        {isRawExpanded ? (
                          <ChevronDown className="w-3.5 h-3.5" />
                        ) : (
                          <ChevronRight className="w-3.5 h-3.5" />
                        )}
                        {isRawExpanded ? 'Hide local raw SMS text' : 'View local raw SMS text'}
                      </button>
                      {isRawExpanded && (
                        <pre className="mt-1.5 p-2.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[11px] whitespace-pre-wrap break-words text-[var(--dw-text-secondary)] font-mono">
                          {draft.rawSmsText}
                        </pre>
                      )}
                    </div>

                    {/* Review & Approval Form for Needs Review */}
                    {draft.status === 'needs_review' && !draft.isNonLedgerNotice && (
                      <div className="pt-2 border-t border-[var(--dw-divider)] space-y-2.5">
                        {draftErr && (
                          <DaywellStatusBanner
                            tone="error"
                            message={draftErr}
                            onDismiss={() =>
                              setErrorByDraftId((prev) => {
                                const next = { ...prev };
                                delete next[draft.id];
                                return next;
                              })
                            }
                          />
                        )}

                        <div className="grid grid-cols-1 sm:grid-cols-3 gap-2 text-xs">
                          <div>
                            <label className="block text-[11px] font-medium text-[var(--dw-text-muted)] mb-1">
                              Post As
                            </label>
                            <select
                              value={edit.finalType}
                              onChange={(e) => {
                                const rawVal = e.target.value;
                                if (!rawVal) {
                                  updateDraftEdit(draft, (prev) => ({
                                    ...prev,
                                    finalType: '',
                                  }));
                                  return;
                                }
                                const nextType = rawVal as
                                  | 'expense'
                                  | 'income'
                                  | 'transfer';
                                const nextPool =
                                  nextType === 'transfer'
                                    ? transferableAccounts
                                    : spendableAccounts;
                                const nextAccountId = nextPool.some(
                                  (a) => a.id === edit.accountId
                                )
                                  ? edit.accountId
                                  : nextPool[0]?.id || '';
                                const nextCats =
                                  nextType === 'income'
                                    ? incomeCategories
                                    : expenseCategories;
                                const nextCatId =
                                  nextCats[0]?.id ||
                                  (nextType === 'income'
                                    ? 'cat-other-inc'
                                    : 'cat-other-exp');
                                const nextDest =
                                  nextType === 'transfer'
                                    ? suggestTransferDestinationAccount(
                                        { ...draft, suggestedAccountId: nextAccountId },
                                        accounts
                                      ) ||
                                      transferableAccounts.find(
                                        (a) => a.id !== nextAccountId
                                      )?.id ||
                                      ''
                                    : '';
                                updateDraftEdit(draft, (prev) => ({
                                  ...prev,
                                  finalType: nextType,
                                  accountId: nextAccountId,
                                  destinationAccountId: nextDest,
                                  categoryId: nextCatId,
                                }));
                                onUpdateDraftReview({
                                  draftId: draft.id,
                                  suggestedType: nextType,
                                  suggestedAccountId: nextAccountId || undefined,
                                  suggestedCategoryId:
                                    nextType === 'transfer' ? undefined : nextCatId,
                                });
                              }}
                              className="w-full px-2.5 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-[var(--dw-text-primary)]"
                            >
                              {edit.finalType === '' && (
                                <option value="">Select type (required)...</option>
                              )}
                              <option value="expense">Expense</option>
                              <option value="income">Income</option>
                              <option value="transfer">Transfer</option>
                            </select>
                          </div>

                          <div>
                            <label className="block text-[11px] font-medium text-[var(--dw-text-muted)] mb-1">
                              {edit.finalType === 'transfer'
                                ? 'From ETB Account'
                                : edit.finalType === 'income'
                                  ? 'Deposit ETB Account'
                                  : 'Paid ETB Account'}
                            </label>
                            <select
                              value={edit.accountId}
                              onChange={(e) => {
                                const accId = e.target.value;
                                updateDraftEdit(draft, (prev) => ({
                                  ...prev,
                                  accountId: accId,
                                }));
                                onUpdateDraftReview({
                                  draftId: draft.id,
                                  suggestedAccountId: accId || undefined,
                                });
                              }}
                              className="w-full px-2.5 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-[var(--dw-text-primary)]"
                            >
                              {accountPool.length === 0 ? (
                                <option value="">No active ETB account</option>
                              ) : (
                                accountPool.map((acc) => (
                                  <option key={acc.id} value={acc.id}>
                                    {acc.name}
                                  </option>
                                ))
                              )}
                            </select>
                          </div>

                          {edit.finalType === 'transfer' ? (
                            <div>
                              <label className="block text-[11px] font-medium text-[var(--dw-text-muted)] mb-1">
                                To ETB Account
                              </label>
                              <select
                                value={edit.destinationAccountId}
                                onChange={(e) =>
                                  updateDraftEdit(draft, (prev) => ({
                                    ...prev,
                                    destinationAccountId: e.target.value,
                                  }))
                                }
                                className="w-full px-2.5 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-[var(--dw-text-primary)]"
                              >
                                <option value="">Select destination...</option>
                                {transferableAccounts
                                  .filter((a) => a.id !== edit.accountId)
                                  .map((acc) => (
                                    <option key={acc.id} value={acc.id}>
                                      {acc.name}
                                    </option>
                                  ))}
                              </select>
                            </div>
                          ) : (
                            <div>
                              <label className="block text-[11px] font-medium text-[var(--dw-text-muted)] mb-1">
                                Category
                              </label>
                              <select
                                value={edit.categoryId}
                                onChange={(e) => {
                                  const catId = e.target.value;
                                  updateDraftEdit(draft, (prev) => ({
                                    ...prev,
                                    categoryId: catId,
                                  }));
                                  onUpdateDraftReview({
                                    draftId: draft.id,
                                    suggestedCategoryId: catId || undefined,
                                  });
                                }}
                                className="w-full px-2.5 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-[var(--dw-text-primary)]"
                              >
                                {catPool.map((cat) => (
                                  <option key={cat.id} value={cat.id}>
                                    {cat.name}
                                  </option>
                                ))}
                              </select>
                            </div>
                          )}
                        </div>

                        <div className="grid grid-cols-1 sm:grid-cols-3 gap-2 text-xs">
                          <div>
                            <label className="block text-[11px] font-medium text-[var(--dw-text-muted)] mb-1">
                              Occurrence Date
                            </label>
                            <input
                              type="date"
                              value={edit.occurrenceDate}
                              onChange={(e) =>
                                updateDraftEdit(draft, (prev) => ({
                                  ...prev,
                                  occurrenceDate: e.target.value,
                                }))
                              }
                              className="w-full px-2.5 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-[var(--dw-text-primary)]"
                            />
                          </div>

                          <div className={feesCents > 0 ? '' : 'sm:col-span-2'}>
                            <label className="block text-[11px] font-medium text-[var(--dw-text-muted)] mb-1">
                              Description
                            </label>
                            <input
                              type="text"
                              value={edit.description}
                              onChange={(e) =>
                                updateDraftEdit(draft, (prev) => ({
                                  ...prev,
                                  description: e.target.value,
                                }))
                              }
                              className="w-full px-2.5 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-[var(--dw-text-primary)]"
                            />
                          </div>

                          {feesCents > 0 && (
                            <div>
                              <label className="block text-[11px] font-medium text-[var(--dw-text-muted)] mb-1">
                                Fee Category
                              </label>
                              <select
                                value={edit.feeCategoryId}
                                onChange={(e) =>
                                  updateDraftEdit(draft, (prev) => ({
                                    ...prev,
                                    feeCategoryId: e.target.value,
                                  }))
                                }
                                className="w-full px-2.5 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-[var(--dw-text-primary)]"
                              >
                                {feeCategoryOptions.map((cat) => (
                                  <option key={cat.id} value={cat.id}>
                                    {cat.name}
                                  </option>
                                ))}
                              </select>
                            </div>
                          )}
                        </div>

                        {edit.finalType !== 'transfer' && (
                          <div className="text-xs">
                            <label className="block text-[11px] font-medium text-[var(--dw-text-muted)] mb-1">
                              Payee / Counterparty (optional)
                            </label>
                            <input
                              type="text"
                              value={edit.payee}
                              placeholder="Counterparty or merchant name"
                              onChange={(e) =>
                                updateDraftEdit(draft, (prev) => ({
                                  ...prev,
                                  payee: e.target.value,
                                }))
                              }
                              className="w-full px-2.5 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-[var(--dw-text-primary)]"
                            />
                          </div>
                        )}

                        <div className="flex flex-wrap items-center justify-end gap-2 pt-1">
                          <DaywellButton
                            label="Dismiss"
                            variant="outlined"
                            size="compact"
                            onClick={() => {
                              const res = onDismissDraft(draft.id);
                              if (!res.ok && res.error) {
                                setErrorByDraftId((prev) => ({
                                  ...prev,
                                  [draft.id]: res.error!,
                                }));
                              }
                            }}
                          />
                          <DaywellButton
                            label="Approve & Post"
                            variant="primary"
                            size="compact"
                            disabled={!edit.finalType}
                            leadingIcon={<Check className="w-3.5 h-3.5" />}
                            onClick={() => {
                              if (!edit.finalType) {
                                setErrorByDraftId((prev) => ({
                                  ...prev,
                                  [draft.id]:
                                    'Select Expense, Income, or Transfer after reviewing before approving.',
                                }));
                                return;
                              }
                              const res = onApproveDraft({
                                draftId: draft.id,
                                finalType: edit.finalType,
                                accountId: edit.accountId,
                                destinationAccountId:
                                  edit.finalType === 'transfer'
                                    ? edit.destinationAccountId
                                    : undefined,
                                categoryId:
                                  edit.finalType === 'transfer'
                                    ? undefined
                                    : edit.categoryId,
                                feeCategoryId:
                                  feesCents > 0 ? edit.feeCategoryId : undefined,
                                occurrenceDate: edit.occurrenceDate,
                                description: edit.description,
                                payee:
                                  edit.finalType !== 'transfer'
                                    ? edit.payee || undefined
                                    : undefined,
                              });
                              if (!res.ok && res.error) {
                                setErrorByDraftId((prev) => ({
                                  ...prev,
                                  [draft.id]: res.error!,
                                }));
                              }
                            }}
                          />
                        </div>
                      </div>
                    )}

                    {/* Actions for Unrecognized / Approved */}
                    {draft.status === 'unrecognized' && (
                      <div className="flex justify-end pt-1 border-t border-[var(--dw-divider)]">
                        <DaywellButton
                          label="Dismiss Notice"
                          variant="outlined"
                          size="compact"
                          onClick={() => onDismissDraft(draft.id)}
                        />
                      </div>
                    )}

                    {draft.status === 'approved' && draft.approvedEntryId && (
                      <div className="text-[11px] text-[var(--dw-text-muted)] pt-1 border-t border-[var(--dw-divider)]">
                        Posted Ledger Entry:{' '}
                        <span className="font-mono text-[var(--dw-text-primary)]">
                          {draft.approvedEntryId}
                        </span>
                      </div>
                    )}
                  </DaywellCard>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
