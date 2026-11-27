import React, { useState } from 'react';
import {
  ArrowLeftRight,
  ArrowDownLeft,
  ArrowUpRight,
  Users,
  Calendar,
  Plus,
  Edit3,
  History,
  Archive,
  RotateCcw,
  Trash2,
  X,
  AlertTriangle,
  Info,
  ChevronDown,
  ChevronRight,
} from 'lucide-react';
import {
  Account,
  AccountSubType,
  AvailableToSpendBreakdownV7,
  calculateV7AccountBalance,
  classifyCurrencyCode,
  formatCurrencyCents,
  getAccountSubType,
  getOpeningBalanceRevisionHistory,
  isEtbCurrency,
  JournalEntry,
  normalizeCurrencyCode,
  OpeningBalanceRevisionItem,
  Posting,
  TransactionCategory,
} from '../../domain/financeV7Engine';
import { formatBirr } from '../../domain/financialEngine';
import {
  canDeleteSimpleAccount,
  canDeleteSimpleCategory,
  classifyAllJournalEntries,
  SimpleTransaction,
} from '../../domain/doubleEntryFinance';
import { SHARED_DESIGN_TOKENS } from '../../domain/sharedFoundation';
import { centsToInputText, ComposerKind, formatDualDateLabel, tryParseStrictDecimalToCents } from './financeV7Types';
import {
  DaywellButton,
  DaywellCard,
  DaywellIconButton,
  DaywellStatusBadge,
  DaywellStatusBanner,
} from '../ui';

interface FinanceOverviewTabProps {
  accounts: Account[];
  categories: TransactionCategory[];
  entries: JournalEntry[];
  postings: Posting[];
  simpleTransactions: SimpleTransaction[];
  breakdown: AvailableToSpendBreakdownV7;
  planningPeriodEnd: string | null;
  onChangePlanningPeriodEnd: (iso: string | null) => void;
  onOpenComposer: (kind: ComposerKind) => void;
  onSaveAccount: (payload: {
    editingAccount?: Account;
    name: string;
    subType: AccountSubType;
    currencyCode: string;
    openingBalanceCents: number;
    openingBalanceDate: string;
  }) => { ok: boolean; error?: string };
  onToggleArchiveAccount: (accountId: string) => { ok: boolean; error?: string } | void;
  onDeleteAccount: (accountId: string) => { ok: boolean; error?: string };
  onSaveCategory: (payload: {
    editingCategory?: TransactionCategory & { parentId?: string };
    name: string;
    type: 'income' | 'expense';
    colorHex: string;
    parentId?: string;
  }) => { ok: boolean; error?: string };
  onToggleArchiveCategory: (categoryId: string) => void;
  onDeleteCategory: (categoryId: string) => { ok: boolean; error?: string };
  onNavigateTab: (tab: 'plan' | 'reports' | 'transactions') => void;
  onRequestConfirm: (
    title: string,
    message: string,
    confirmLabel: string,
    tone: 'danger' | 'primary',
    onConfirm: () => void
  ) => void;
  hasIntegrityNotices: boolean;
  legacyNoticeDismissed?: boolean;
  onDismissLegacyNotice?: () => void;
}

const SUBTYPE_LABELS: Record<string, string> = {
  cash: 'Cash',
  bank: 'Bank',
  mobile_money: 'Mobile Money',
  savings_vault: 'Savings Vault',
  credit_card: 'Credit Card',
};

export function FinanceOverviewTab({
  accounts,
  categories,
  entries,
  postings,
  simpleTransactions,
  breakdown,
  planningPeriodEnd,
  onChangePlanningPeriodEnd,
  onOpenComposer,
  onSaveAccount,
  onToggleArchiveAccount,
  onDeleteAccount,
  onSaveCategory,
  onToggleArchiveCategory,
  onDeleteCategory,
  onNavigateTab,
  onRequestConfirm,
  hasIntegrityNotices,
  legacyNoticeDismissed,
  onDismissLegacyNotice,
}: FinanceOverviewTabProps) {
  const [showArchivedAccounts, setShowArchivedAccounts] = useState(false);
  const [showLegacyArchive, setShowLegacyArchive] = useState(false);
  const [localLegacyNoticeDismissed, setLocalLegacyNoticeDismissed] = useState<boolean>(() => {
    try {
      return localStorage.getItem('daywell_finance_legacy_non_etb_notice_dismissed_v1') === 'true';
    } catch {
      return false;
    }
  });
  const [showBreakdownModal, setShowBreakdownModal] = useState(false);
  const [categoryTabType, setCategoryTabType] = useState<'expense' | 'income'>('expense');
  const [showArchivedCategories, setShowArchivedCategories] = useState(false);
  const [noticeBanner, setNoticeBanner] = useState<string | null>(null);

  // Account Modal
  const [accountModalOpen, setAccountModalOpen] = useState(false);
  const [editingAccount, setEditingAccount] = useState<Account | undefined>(undefined);
  const [accName, setAccName] = useState('');
  const [accSubType, setAccSubType] = useState<AccountSubType>('bank');
  const [accCurrency, setAccCurrency] = useState('ETB');
  const [accOpeningStr, setAccOpeningStr] = useState('0');
  const [accOpeningDate, setAccOpeningDate] = useState(breakdown.planningPeriodEndIso.slice(0, 10));
  const [accError, setAccError] = useState<string | null>(null);

  // Revision History Modal
  const [historyAccount, setHistoryAccount] = useState<Account | null>(null);
  const [historyItems, setHistoryItems] = useState<OpeningBalanceRevisionItem[]>([]);

  // Category Modal
  const [catModalOpen, setCatModalOpen] = useState(false);
  const [editingCategory, setEditingCategory] = useState<(TransactionCategory & { parentId?: string }) | undefined>(undefined);
  const [catName, setCatName] = useState('');
  const [catType, setCatType] = useState<'expense' | 'income'>('expense');
  const [catColor, setCatColor] = useState<string>(SHARED_DESIGN_TOKENS.colors.primary.emerald);
  const [catParentId, setCatParentId] = useState('');
  const [catError, setCatError] = useState<string | null>(null);

  const userAccounts = accounts.filter((a) => !a.isSystem);
  const etbUserAccounts = userAccounts.filter((a) => isEtbCurrency(a.currencyCode));
  const legacyNonEtbAccounts = userAccounts.filter((a) => !isEtbCurrency(a.currencyCode));
  const activeAccounts = etbUserAccounts.filter((a) => !a.isArchived);
  const archivedAccounts = etbUserAccounts.filter((a) => a.isArchived);

  const entryClassifications = React.useMemo(
    () =>
      classifyAllJournalEntries({
        accounts,
        entries,
        postings,
      }),
    [accounts, entries, postings]
  );
  const legacyNonEtbEntriesCount = React.useMemo(
    () =>
      entries.filter((e) => {
        const cls = entryClassifications.get(e.id);
        return cls && (cls.status === 'excluded_non_etb' || cls.status === 'mixed_or_ambiguous');
      }).length,
    [entries, entryClassifications]
  );
  const hasLegacyNonEtbRecords =
    legacyNonEtbAccounts.length > 0 ||
    legacyNonEtbEntriesCount > 0 ||
    breakdown.nonEtbAccountCount > 0 ||
    (breakdown.unverifiedAccountCount || 0) > 0 ||
    breakdown.excludedNonEtbEntryCount > 0 ||
    breakdown.currencyReviewEntryCount > 0;
  const isLegacyNoticeDismissed = legacyNoticeDismissed ?? localLegacyNoticeDismissed;
  const handleDismissLegacyNotice = () => {
    setLocalLegacyNoticeDismissed(true);
    try {
      localStorage.setItem('daywell_finance_legacy_non_etb_notice_dismissed_v1', 'true');
    } catch {
      // ignore storage failure
    }
    onDismissLegacyNotice?.();
  };

  const visibleCategories = categories.filter(
    (c) => c.type === categoryTabType && (showArchivedCategories || !c.isArchived)
  );
  const parentCandidates = categories.filter(
    (c) =>
      c.type === catType &&
      !c.isArchived &&
      c.id !== editingCategory?.id &&
      !(c as TransactionCategory & { parentId?: string }).parentId
  );

  const openCreateAccount = () => {
    setEditingAccount(undefined);
    setAccName('');
    setAccSubType('bank');
    setAccCurrency('ETB');
    setAccOpeningStr('0');
    setAccOpeningDate(new Date().toISOString().slice(0, 10));
    setAccError(null);
    setAccountModalOpen(true);
  };

  const openEditAccount = (acc: Account) => {
    setEditingAccount(acc);
    setAccName(acc.name);
    setAccSubType(getAccountSubType(acc));
    setAccCurrency(acc.currencyCode ?? '');
    setAccOpeningStr(centsToInputText(acc.openingBalanceCents || 0));
    setAccOpeningDate(acc.openingBalanceDate || new Date().toISOString().slice(0, 10));
    setAccError(null);
    setAccountModalOpen(true);
  };

  const submitAccount = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = accName.trim();
    if (!trimmed) {
      setAccError('Account name is required.');
      return;
    }
    const isNonEtbEdit = Boolean(editingAccount && !isEtbCurrency(editingAccount.currencyCode));
    let openingBalanceCents = editingAccount?.openingBalanceCents || 0;
    if (!isNonEtbEdit) {
      const parsedCents = accOpeningStr.trim()
        ? tryParseStrictDecimalToCents(accOpeningStr, { allowNegative: true })
        : 0;
      if (parsedCents === null) {
        setAccError('Enter a valid starting balance (up to 2 decimal places).');
        return;
      }
      openingBalanceCents = parsedCents;
    }
    const res = onSaveAccount({
      editingAccount,
      name: trimmed,
      subType: accSubType,
      currencyCode: editingAccount ? editingAccount.currencyCode ?? '' : 'ETB',
      openingBalanceCents,
      openingBalanceDate: isNonEtbEdit
        ? editingAccount?.openingBalanceDate || new Date().toISOString().slice(0, 10)
        : accOpeningDate || new Date().toISOString().slice(0, 10),
    });
    if (!res.ok) {
      setAccError(res.error || 'Could not save account.');
      return;
    }
    setAccountModalOpen(false);
  };

  const openRevisionHistory = (acc: Account) => {
    setHistoryAccount(acc);
    setHistoryItems(getOpeningBalanceRevisionHistory(acc.id, entries, postings));
  };

  const openCreateCategory = () => {
    setEditingCategory(undefined);
    setCatName('');
    setCatType(categoryTabType);
    setCatColor(
      categoryTabType === 'expense'
        ? SHARED_DESIGN_TOKENS.colors.semantic.expense
        : SHARED_DESIGN_TOKENS.colors.semantic.income
    );
    setCatParentId('');
    setCatError(null);
    setCatModalOpen(true);
  };

  const openEditCategory = (cat: TransactionCategory & { parentId?: string }) => {
    setEditingCategory(cat);
    setCatName(cat.name);
    setCatType(cat.type);
    setCatColor(cat.colorHex || SHARED_DESIGN_TOKENS.colors.primary.emerald);
    setCatParentId(cat.parentId || '');
    setCatError(null);
    setCatModalOpen(true);
  };

  const submitCategory = (e: React.FormEvent) => {
    e.preventDefault();
    const res = onSaveCategory({
      editingCategory,
      name: catName.trim(),
      type: catType,
      colorHex: catColor,
      parentId: catParentId || undefined,
    });
    if (!res.ok) {
      setCatError(res.error || 'Could not save category.');
      return;
    }
    setCatModalOpen(false);
  };

  return (
    <div className="space-y-6">
      {noticeBanner && (
        <DaywellStatusBanner
          tone="warning"
          message={noticeBanner}
          onDismiss={() => setNoticeBanner(null)}
        />
      )}

      {/* 1. Safe Harbor Hero */}
      <DaywellCard padding="lg" radius="lg" className="space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="text-sm font-semibold text-[var(--dw-text-primary)]">
              Safe Harbor Available to Spend
            </h2>
            <p className="text-xs text-[var(--dw-text-muted)]">
              Through {formatDualDateLabel(breakdown.planningPeriodEndIso)}
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <label className="flex items-center gap-1.5 text-xs text-[var(--dw-text-secondary)] border border-[var(--dw-border)] rounded-[var(--dw-radius-sm)] px-2.5 py-1.5 bg-[var(--dw-canvas)]">
              <Calendar className="w-3.5 h-3.5 text-[var(--dw-primary)] shrink-0" />
              <span className="whitespace-nowrap">Horizon H:</span>
              <input
                type="date"
                value={breakdown.planningPeriodEndIso}
                onChange={(e) => onChangePlanningPeriodEnd(e.target.value || null)}
                className="bg-transparent text-xs font-mono tabular-nums text-[var(--dw-text-primary)] outline-none"
                aria-label="Planning horizon end date"
              />
            </label>
            {planningPeriodEnd && (
              <DaywellButton
                label="Reset Month"
                variant="text"
                size="compact"
                onClick={() => onChangePlanningPeriodEnd(null)}
              />
            )}
            <DaywellButton
              label="Breakdown"
              variant="outlined"
              size="compact"
              onClick={() => setShowBreakdownModal(true)}
            />
          </div>
        </div>

        <div
          className={`dw-type-numeric-hero font-mono ${
            breakdown.isShortfall ? 'text-[var(--dw-on-expense-container)]' : 'text-[var(--dw-primary)]'
          }`}
        >
          {formatBirr(breakdown.availableToSpendCents)}
        </div>

        {/* Formula Rows */}
        <div className="space-y-1.5 text-xs pt-1">
          <div className="flex items-center justify-between gap-2">
            <span className="text-[var(--dw-text-secondary)]">
              Liquid Cash (Bank, Cash, Mobile Money)
            </span>
            <span className="font-mono tabular-nums font-semibold text-[var(--dw-on-income-container)]">
              {formatBirr(breakdown.liquidCashCents)}
            </span>
          </div>
          {breakdown.prepaidCardCreditCents > 0 && (
            <div className="flex items-center justify-between gap-2">
              <span className="text-[var(--dw-text-secondary)]">
                + Prepaid Card Credit (Included)
              </span>
              <span className="font-mono tabular-nums font-semibold text-[var(--dw-on-income-container)]">
                +{formatBirr(breakdown.prepaidCardCreditCents)}
              </span>
            </div>
          )}
          {breakdown.shortTermCreditOwedCents > 0 && (
            <div className="flex items-center justify-between gap-2">
              <span className="text-[var(--dw-text-secondary)]">
                - Short-Term Credit Card Owed
              </span>
              <span className="font-mono tabular-nums font-semibold text-[var(--dw-on-expense-container)]">
                {formatBirr(-breakdown.shortTermCreditOwedCents)}
              </span>
            </div>
          )}
          {breakdown.duePayablesCents > 0 && (
            <div className="flex items-center justify-between gap-2">
              <span className="text-[var(--dw-text-secondary)]">
                - Due Payables in Horizon
              </span>
              <span className="font-mono tabular-nums font-semibold text-[var(--dw-on-expense-container)]">
                {formatBirr(-breakdown.duePayablesCents)}
              </span>
            </div>
          )}
          {breakdown.dueNonDebtCommitmentsCents > 0 && (
            <div className="flex items-center justify-between gap-2">
              <span className="text-[var(--dw-text-secondary)]">
                - Due Bills & Commitments
              </span>
              <span className="font-mono tabular-nums font-semibold text-[var(--dw-on-warning-container)]">
                {formatBirr(-breakdown.dueNonDebtCommitmentsCents)}
              </span>
            </div>
          )}
          {breakdown.virtualSavingsReservedCents > 0 && (
            <div className="flex items-center justify-between gap-2">
              <span className="text-[var(--dw-text-secondary)]">
                - Virtual Savings Reserve
              </span>
              <span className="font-mono tabular-nums font-semibold text-[var(--dw-on-transfer-container)]">
                {formatBirr(-breakdown.virtualSavingsReservedCents)}
              </span>
            </div>
          )}
        </div>

        <div className="pt-3 border-t border-[var(--dw-divider)] grid grid-cols-1 sm:grid-cols-3 gap-3 text-xs">
          <div>
            <div className="text-[var(--dw-text-muted)]">Net Position (ETB)</div>
            <div className="font-mono tabular-nums font-semibold text-[var(--dw-text-primary)] mt-0.5">
              {formatBirr(breakdown.netFinancialPositionCents)}
            </div>
          </div>
          <div>
            <div className="text-[var(--dw-text-muted)]">Vault Savings</div>
            <div className="font-mono tabular-nums font-semibold text-[var(--dw-text-primary)] mt-0.5">
              {formatBirr(breakdown.vaultSavingsCents)}
            </div>
          </div>
          <div>
            <div className="text-[var(--dw-text-muted)]">Receivables (Excluded)</div>
            <div className="font-mono tabular-nums font-semibold text-[var(--dw-text-primary)] mt-0.5">
              {formatBirr(breakdown.receivablesCents)}
            </div>
          </div>
        </div>
      </DaywellCard>

      {/* Alert Banners */}
      {breakdown.isShortfall && (
        <DaywellStatusBanner
          tone="error"
          icon={<AlertTriangle className="w-4 h-4 shrink-0" />}
          title="Safe Harbor Shortfall"
          message={`Obligations due through ${breakdown.planningPeriodEndIso} exceed liquid cash by ${formatBirr(-breakdown.availableToSpendCents)}.`}
          actionLabel="Review Plan"
          onActionPressed={() => onNavigateTab('plan')}
        />
      )}

      {hasLegacyNonEtbRecords && !isLegacyNoticeDismissed && (
        <DaywellStatusBanner
          tone="info"
          icon={<Info className="w-4 h-4 shrink-0" />}
          title="Historical Non-ETB Records Preserved"
          message="Legacy foreign-currency or unclassified records remain safely preserved with their original amounts in the read-only Legacy Archive below and are excluded from ETB balances, budgets, and reports."
          onDismiss={handleDismissLegacyNotice}
        />
      )}

      {breakdown.unverifiedLegacyPaidCount > 0 && (
        <DaywellStatusBanner
          tone="warning"
          icon={<AlertTriangle className="w-4 h-4 shrink-0" />}
          title="Legacy Paid Commitments Need Verification"
          message={`${breakdown.unverifiedLegacyPaidCount} commitment(s) were isolated with 0 cash impact until you record cash payment or mark unpaid.`}
          actionLabel="Verify in Plan"
          onActionPressed={() => onNavigateTab('plan')}
        />
      )}

      {hasIntegrityNotices && (
        <DaywellStatusBanner
          tone="info"
          icon={<Info className="w-4 h-4 shrink-0" />}
          title="Ledger Audit Notices"
          message="Inspect v7 debt control reconciliation & audit checks in Reports."
          actionLabel="View Audit"
          onActionPressed={() => onNavigateTab('reports')}
        />
      )}

      {/* 2. Quick Actions */}
      <section className="flex flex-wrap items-center gap-2">
        <DaywellButton
          label="Expense"
          variant="primary"
          size="compact"
          leadingIcon={<ArrowUpRight className="w-3.5 h-3.5" />}
          onClick={() => onOpenComposer('expense')}
        />
        <button
          type="button"
          onClick={() => onOpenComposer('income')}
          className="min-h-[36px] px-3 py-1.5 rounded-[var(--dw-radius-sm)] bg-[var(--dw-income)] text-[var(--dw-on-income)] text-xs font-semibold inline-flex items-center gap-1.5 hover:opacity-90 whitespace-nowrap shrink-0 cursor-pointer"
        >
          <ArrowDownLeft className="w-3.5 h-3.5" />
          Income
        </button>
        <DaywellButton
          label="Transfer"
          variant="outlined"
          size="compact"
          leadingIcon={<ArrowLeftRight className="w-3.5 h-3.5" />}
          onClick={() => onOpenComposer('transfer')}
        />
        <DaywellButton
          label="Split Expense"
          variant="outlined"
          size="compact"
          leadingIcon={<Users className="w-3.5 h-3.5" />}
          onClick={() => onOpenComposer('split')}
        />
      </section>

      {/* 3. Accounts Section */}
      <DaywellCard padding="lg" radius="lg" className="space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
              Accounts ({activeAccounts.length})
            </h3>
            <p className="text-xs text-[var(--dw-text-muted)]">
              Liquid wallets, savings vaults, credit cards &amp; opening balance provenance
            </p>
          </div>
          <div className="flex items-center gap-2">
            {archivedAccounts.length > 0 && (
              <DaywellButton
                label={showArchivedAccounts ? 'Hide Archived' : `Archived (${archivedAccounts.length})`}
                variant="outlined"
                size="compact"
                onClick={() => setShowArchivedAccounts((v) => !v)}
              />
            )}
            <DaywellButton
              label="Add Account"
              variant="secondary"
              size="compact"
              leadingIcon={<Plus className="w-3.5 h-3.5" />}
              onClick={openCreateAccount}
            />
          </div>
        </div>

        <div className="divide-y divide-[var(--dw-divider)]">
          {(showArchivedAccounts ? etbUserAccounts : activeAccounts).map((acc) => {
            const sub = getAccountSubType(acc);
            const bal = calculateV7AccountBalance(acc, postings, entries);
            const isPrepaidCard = sub === 'credit_card' && bal < 0;
            const deleteGuard = canDeleteSimpleAccount(acc.id, simpleTransactions);
            const hasPostings = postings.some((p) => p.accountId === acc.id);
            const canDelete = deleteGuard.canDelete && !hasPostings;

            return (
              <div key={acc.id} className="py-3 flex flex-wrap items-center justify-between gap-3">
                <div className="min-w-0">
                  <div className="text-sm font-semibold text-[var(--dw-text-primary)] truncate">
                    {acc.name}
                  </div>
                  <div className="text-xs text-[var(--dw-text-muted)] flex flex-wrap items-center gap-1.5">
                    <span>{SUBTYPE_LABELS[sub] || sub}</span>
                    {isPrepaidCard && (
                      <span className="text-[var(--dw-on-income-container)] font-medium">
                        · Prepaid Credit ({formatBirr(-bal)})
                      </span>
                    )}
                    {acc.isArchived && (
                      <span className="text-[var(--dw-text-disabled)]">· Archived</span>
                    )}
                  </div>
                </div>

                <div className="flex items-center gap-3 shrink-0">
                  <div className="text-right">
                    <div className="text-sm font-bold font-mono tabular-nums text-[var(--dw-text-primary)]">
                      {formatBirr(bal)}
                    </div>
                    <div className="text-[11px] font-mono tabular-nums text-[var(--dw-text-muted)]">
                      Open: {formatBirr(acc.openingBalanceCents || 0)}
                    </div>
                  </div>
                  <div className="flex items-center gap-1">
                    <DaywellIconButton
                      label="Edit account & opening balance"
                      size="compact"
                      tone="muted"
                      onClick={() => openEditAccount(acc)}
                      icon={<Edit3 className="w-3.5 h-3.5" />}
                    />
                    <DaywellIconButton
                      label="Opening balance revision history"
                      size="compact"
                      tone="muted"
                      onClick={() => openRevisionHistory(acc)}
                      icon={<History className="w-3.5 h-3.5" />}
                    />
                    <DaywellIconButton
                      label={acc.isArchived ? 'Restore account' : 'Archive account'}
                      size="compact"
                      tone="muted"
                      onClick={() => {
                        const res = onToggleArchiveAccount(acc.id);
                        if (res && !res.ok && res.error) {
                          setNoticeBanner(res.error);
                        }
                      }}
                      icon={acc.isArchived ? <RotateCcw className="w-3.5 h-3.5" /> : <Archive className="w-3.5 h-3.5" />}
                    />
                    <DaywellIconButton
                      label="Delete unused account"
                      size="compact"
                      tone={canDelete ? 'danger' : 'muted'}
                      onClick={() => {
                        if (!canDelete) {
                          setNoticeBanner(
                            `Cannot delete "${acc.name}" because ledger postings exist. Archive it instead.`
                          );
                          return;
                        }
                        onRequestConfirm(
                          'Delete Account?',
                          `Delete unused account "${acc.name}" permanently?`,
                          'Delete',
                          'danger',
                          () => {
                            const res = onDeleteAccount(acc.id);
                            if (!res.ok && res.error) setNoticeBanner(res.error);
                          }
                        );
                      }}
                      icon={<Trash2 className="w-3.5 h-3.5" />}
                    />
                  </div>
                </div>
              </div>
            );
          })}
          {activeAccounts.length === 0 && (
            <div className="py-6 text-center text-xs text-[var(--dw-text-muted)]">
              No active ETB accounts yet. Add an account to begin tracking Safe Harbor.
            </div>
          )}
        </div>
      </DaywellCard>

      {(legacyNonEtbAccounts.length > 0 || legacyNonEtbEntriesCount > 0) && (
        <DaywellCard padding="lg" radius="lg" className="space-y-3">
          <button
            type="button"
            onClick={() => setShowLegacyArchive((v) => !v)}
            aria-expanded={showLegacyArchive}
            className="w-full flex items-center justify-between gap-2 text-left cursor-pointer"
          >
            <div>
              <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
                Legacy Non-ETB Archive (Read-Only)
              </h3>
              <p className="text-xs text-[var(--dw-text-muted)]">
                {legacyNonEtbAccounts.length} account(s) · {legacyNonEtbEntriesCount} ledger entry(ies) preserved separately from ETB totals
              </p>
            </div>
            <div className="flex items-center gap-2 shrink-0 text-[var(--dw-text-muted)]">
              <DaywellStatusBadge tone="neutral" showIcon={false} label="Excluded from ETB" />
              {showLegacyArchive ? (
                <ChevronDown className="w-4 h-4" />
              ) : (
                <ChevronRight className="w-4 h-4" />
              )}
            </div>
          </button>

          {showLegacyArchive && (
            <div className="pt-2 border-t border-[var(--dw-divider)] space-y-3">
              {legacyNonEtbAccounts.length > 0 && (
                <div className="divide-y divide-[var(--dw-divider)]">
                  {legacyNonEtbAccounts.map((acc) => {
                    const sub = getAccountSubType(acc);
                    const bal = calculateV7AccountBalance(acc, postings, entries);
                    const curTier = classifyCurrencyCode(acc.currencyCode);
                    const normCode = normalizeCurrencyCode(acc.currencyCode);
                    const deleteGuard = canDeleteSimpleAccount(acc.id, simpleTransactions);
                    const hasPostings = postings.some((p) => p.accountId === acc.id);
                    const canDelete = deleteGuard.canDelete && !hasPostings;

                    return (
                      <div key={acc.id} className="py-2.5 flex flex-wrap items-center justify-between gap-3">
                        <div className="min-w-0">
                          <div className="text-sm font-semibold text-[var(--dw-text-primary)] truncate">
                            {acc.name}
                          </div>
                          <div className="text-xs text-[var(--dw-text-muted)] flex flex-wrap items-center gap-1.5">
                            <span>{SUBTYPE_LABELS[sub] || sub}</span>
                            <DaywellStatusBadge
                              tone="warning"
                              showIcon={false}
                              label={
                                curTier === 'verified_non_etb'
                                  ? `Legacy (${normCode})`
                                  : 'Unclassified'
                              }
                            />
                            {acc.isArchived && (
                              <span className="text-[var(--dw-text-disabled)]">· Archived</span>
                            )}
                          </div>
                        </div>

                        <div className="flex items-center gap-3 shrink-0">
                          <div className="text-right">
                            <div className="text-sm font-bold font-mono tabular-nums text-[var(--dw-text-secondary)]">
                              {formatCurrencyCents(bal, acc.currencyCode)}
                            </div>
                            <div className="text-[11px] font-mono tabular-nums text-[var(--dw-text-muted)]">
                              Open: {formatCurrencyCents(acc.openingBalanceCents || 0, acc.currencyCode)}
                            </div>
                          </div>
                          <div className="flex items-center gap-1">
                            <DaywellIconButton
                              label={acc.isArchived ? 'Restore legacy account' : 'Archive legacy account'}
                              size="compact"
                              tone="muted"
                              onClick={() => {
                                const res = onToggleArchiveAccount(acc.id);
                                if (res && !res.ok && res.error) {
                                  setNoticeBanner(res.error);
                                }
                              }}
                              icon={acc.isArchived ? <RotateCcw className="w-3.5 h-3.5" /> : <Archive className="w-3.5 h-3.5" />}
                            />
                            <DaywellIconButton
                              label="Delete unused legacy account"
                              size="compact"
                              tone={canDelete ? 'danger' : 'muted'}
                              onClick={() => {
                                if (!canDelete) {
                                  setNoticeBanner(
                                    `Cannot delete "${acc.name}" because ledger postings exist. Archive it instead.`
                                  );
                                  return;
                                }
                                onRequestConfirm(
                                  'Delete Legacy Account?',
                                  `Delete unused legacy account "${acc.name}" permanently?`,
                                  'Delete',
                                  'danger',
                                  () => {
                                    const res = onDeleteAccount(acc.id);
                                    if (!res.ok && res.error) setNoticeBanner(res.error);
                                  }
                                );
                              }}
                              icon={<Trash2 className="w-3.5 h-3.5" />}
                            />
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}

              {legacyNonEtbEntriesCount > 0 && (
                <div className="flex flex-wrap items-center justify-between gap-2 pt-1 text-xs text-[var(--dw-text-muted)]">
                  <span>
                    {legacyNonEtbEntriesCount} historical non-ETB or unclassified journal entry(ies) preserved separately.
                  </span>
                  <DaywellButton
                    label="Inspect in Transactions"
                    variant="text"
                    size="compact"
                    onClick={() => onNavigateTab('transactions')}
                  />
                </div>
              )}
            </div>
          )}
        </DaywellCard>
      )}

      {/* 4. Hierarchical Categories Manager */}
      <DaywellCard padding="lg" radius="lg" className="space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">Categories</h3>
            <div className="flex items-center gap-1 p-1 rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)]">
              {(['expense', 'income'] as const).map((t) => (
                <button
                  key={t}
                  type="button"
                  onClick={() => setCategoryTabType(t)}
                  className={`px-3 py-1 text-xs font-medium rounded-[var(--dw-radius-sm)] capitalize whitespace-nowrap shrink-0 cursor-pointer ${
                    categoryTabType === t
                      ? 'bg-[var(--dw-elevated)] text-[var(--dw-text-primary)] shadow-xs'
                      : 'text-[var(--dw-text-muted)]'
                  }`}
                >
                  {t}
                </button>
              ))}
            </div>
          </div>
          <div className="flex items-center gap-2">
            <DaywellButton
              label={showArchivedCategories ? 'Hide Archived' : 'Show Archived'}
              variant="outlined"
              size="compact"
              onClick={() => setShowArchivedCategories((v) => !v)}
            />
            <DaywellButton
              label="Add Category"
              variant="secondary"
              size="compact"
              leadingIcon={<Plus className="w-3.5 h-3.5" />}
              onClick={openCreateCategory}
            />
          </div>
        </div>

        <div className="divide-y divide-[var(--dw-divider)]">
          {visibleCategories.map((cat) => {
            const catWithParent = cat as TransactionCategory & { parentId?: string };
            const parentName = catWithParent.parentId
              ? categories.find((p) => p.id === catWithParent.parentId)?.name
              : undefined;
            const guard = canDeleteSimpleCategory(cat.id, simpleTransactions);
            const hasPostingRef = postings.some((p) => p.categoryId === cat.id);
            const canDel = guard.canDelete && !hasPostingRef && !cat.isDefault;

            return (
              <div key={cat.id} className="py-2.5 flex items-center justify-between gap-3">
                <div className="flex items-center gap-2.5 min-w-0">
                  <span
                    className="w-3 h-3 rounded-sm shrink-0"
                    style={{ backgroundColor: cat.colorHex || SHARED_DESIGN_TOKENS.colors.primary.emerald }}
                  />
                  <div className="min-w-0">
                    <span className="text-sm font-medium text-[var(--dw-text-primary)] truncate">
                      {cat.name}
                    </span>
                    <div className="text-xs text-[var(--dw-text-muted)]">
                      {parentName ? `Subcategory of ${parentName}` : 'Top-level category'}
                      {cat.isArchived ? ' · Archived' : ''}
                    </div>
                  </div>
                </div>
                <div className="flex items-center gap-1 shrink-0">
                  <DaywellIconButton
                    label="Edit category"
                    size="compact"
                    tone="muted"
                    onClick={() => openEditCategory(catWithParent)}
                    icon={<Edit3 className="w-3.5 h-3.5" />}
                  />
                  <DaywellIconButton
                    label={cat.isArchived ? 'Restore category' : 'Archive category'}
                    size="compact"
                    tone="muted"
                    onClick={() => onToggleArchiveCategory(cat.id)}
                    icon={cat.isArchived ? <RotateCcw className="w-3.5 h-3.5" /> : <Archive className="w-3.5 h-3.5" />}
                  />
                  <DaywellIconButton
                    label="Delete unused category"
                    size="compact"
                    tone={canDel ? 'danger' : 'muted'}
                    onClick={() => {
                      if (!canDel) {
                        setNoticeBanner(
                          `Category "${cat.name}" is in use or default. Archive it instead.`
                        );
                        return;
                      }
                      onRequestConfirm(
                        'Delete Category?',
                        `Delete unused category "${cat.name}"?`,
                        'Delete',
                        'danger',
                        () => {
                          const res = onDeleteCategory(cat.id);
                          if (!res.ok && res.error) setNoticeBanner(res.error);
                        }
                      );
                    }}
                    icon={<Trash2 className="w-3.5 h-3.5" />}
                  />
                </div>
              </div>
            );
          })}
        </div>
      </DaywellCard>

      {/* Safe Harbor Breakdown Modal */}
      {showBreakdownModal && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Safe Harbor Formula Breakdown"
          className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4"
        >
          <div className="w-full max-w-md rounded-[var(--dw-radius-lg)] bg-[var(--dw-card)] border border-[var(--dw-border)] p-5 space-y-4 shadow-xl">
            <div className="flex items-center justify-between">
              <h3 className="dw-type-title text-[var(--dw-text-primary)]">
                Safe Harbor Formula Breakdown
              </h3>
              <DaywellIconButton
                label="Close breakdown"
                size="compact"
                tone="muted"
                onClick={() => setShowBreakdownModal(false)}
                icon={<X className="w-4 h-4" />}
              />
            </div>
            <div className="space-y-2 text-xs text-[var(--dw-text-primary)]">
              <div className="flex justify-between">
                <span className="text-[var(--dw-text-secondary)]">Horizon End (H)</span>
                <span className="font-mono tabular-nums font-semibold">
                  {breakdown.planningPeriodEndIso}
                </span>
              </div>
              <div className="flex justify-between">
                <span>Liquid Cash</span>
                <span className="font-mono tabular-nums">{formatBirr(breakdown.liquidCashCents)}</span>
              </div>
              <div className="flex justify-between text-[var(--dw-on-income-container)]">
                <span>+ Prepaid Card Credit (Included)</span>
                <span className="font-mono tabular-nums">
                  {formatBirr(breakdown.prepaidCardCreditCents)}
                </span>
              </div>
              <div className="flex justify-between text-[var(--dw-on-expense-container)]">
                <span>- Short-Term Credit Card Owed</span>
                <span className="font-mono tabular-nums">
                  {formatBirr(-breakdown.shortTermCreditOwedCents)}
                </span>
              </div>
              <div className="flex justify-between text-[var(--dw-on-expense-container)]">
                <span>- Due Payables (≤ H)</span>
                <span className="font-mono tabular-nums">
                  {formatBirr(-breakdown.duePayablesCents)}
                </span>
              </div>
              <div className="flex justify-between text-[var(--dw-on-warning-container)]">
                <span>- Due Outflow Commitments (≤ H)</span>
                <span className="font-mono tabular-nums">
                  {formatBirr(-breakdown.dueNonDebtCommitmentsCents)}
                </span>
              </div>
              <div className="flex justify-between text-[var(--dw-on-transfer-container)]">
                <span>- Virtual Savings Reserve</span>
                <span className="font-mono tabular-nums">
                  {formatBirr(-breakdown.virtualSavingsReservedCents)}
                </span>
              </div>
              <div className="pt-2 border-t border-[var(--dw-border)] flex justify-between font-bold text-sm">
                <span>Available to Spend</span>
                <span className="font-mono tabular-nums">
                  {formatBirr(breakdown.availableToSpendCents)}
                </span>
              </div>
              <div className="pt-2 text-[11px] text-[var(--dw-text-muted)]">
                Pending Inflow Commitments, Receivables ({formatBirr(breakdown.receivablesCents)}), and isolated legacyPaidUnverified commitments contribute 0.
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Account Add/Edit Modal */}
      {accountModalOpen && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={editingAccount ? 'Edit Account & Opening Revision' : 'Add Account'}
          className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4"
        >
          <form
            onSubmit={submitAccount}
            className="w-full max-w-md rounded-[var(--dw-radius-lg)] bg-[var(--dw-card)] border border-[var(--dw-border)] p-5 space-y-4 shadow-xl"
          >
            <div className="flex items-center justify-between">
              <h3 className="dw-type-title text-[var(--dw-text-primary)]">
                {editingAccount ? 'Edit Account & Opening Revision' : 'Add Account'}
              </h3>
              <DaywellIconButton
                label="Close account modal"
                size="compact"
                tone="muted"
                onClick={() => setAccountModalOpen(false)}
                icon={<X className="w-4 h-4" />}
              />
            </div>
            {accError && <DaywellStatusBanner tone="error" message={accError} />}
            <div className="space-y-3 text-xs">
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                  Account Name
                </label>
                <input
                  type="text"
                  value={accName}
                  onChange={(e) => setAccName(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
                  placeholder="e.g. CBE Savings"
                />
              </div>
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                  Account Type
                </label>
                <select
                  value={accSubType}
                  onChange={(e) => setAccSubType(e.target.value as AccountSubType)}
                  disabled={Boolean(editingAccount)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
                >
                  <option value="bank">Bank</option>
                  <option value="cash">Cash</option>
                  <option value="mobile_money">Mobile Money</option>
                  <option value="savings_vault">Savings Vault</option>
                  <option value="credit_card">Credit Card</option>
                </select>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                    Opening Balance (ETB)
                  </label>
                  <input
                    type="number"
                    step="0.01"
                    value={accOpeningStr}
                    onChange={(e) => setAccOpeningStr(e.target.value)}
                    disabled={Boolean(editingAccount && !isEtbCurrency(editingAccount.currencyCode))}
                    className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono tabular-nums disabled:opacity-60"
                  />
                </div>
                <div>
                  <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                    Opening Date
                  </label>
                  <input
                    type="date"
                    value={accOpeningDate}
                    onChange={(e) => setAccOpeningDate(e.target.value)}
                    disabled={Boolean(editingAccount && !isEtbCurrency(editingAccount.currencyCode))}
                    className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono tabular-nums disabled:opacity-60"
                  />
                </div>
              </div>
              <p className="text-[11px] text-[var(--dw-text-muted)]">
                {editingAccount && !isEtbCurrency(editingAccount.currencyCode)
                  ? 'Legacy non-ETB and unverified accounts are read-only for balances and currency; you can safely rename or archive this account.'
                  : 'Editing opening balance records a balanced :rev:{n} equity adjustment entry and voids the previous opening entry without altering income or expense history.'}
              </p>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <DaywellButton
                label="Cancel"
                variant="text"
                size="compact"
                onClick={() => setAccountModalOpen(false)}
              />
              <DaywellButton type="submit" label="Save Account" variant="primary" size="compact" />
            </div>
          </form>
        </div>
      )}

      {/* Opening Balance Revision History Modal */}
      {historyAccount && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={`Opening Balance History ${historyAccount.name}`}
          className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4"
        >
          <div className="w-full max-w-md rounded-[var(--dw-radius-lg)] bg-[var(--dw-card)] border border-[var(--dw-border)] p-5 space-y-4 shadow-xl">
            <div className="flex items-center justify-between">
              <h3 className="dw-type-title text-[var(--dw-text-primary)]">
                Opening Balance History · {historyAccount.name}
              </h3>
              <DaywellIconButton
                label="Close history"
                size="compact"
                tone="muted"
                onClick={() => setHistoryAccount(null)}
                icon={<X className="w-4 h-4" />}
              />
            </div>
            <div className="space-y-2 max-h-72 overflow-y-auto text-xs">
              {historyItems.length === 0 ? (
                <p className="text-[var(--dw-text-muted)] py-4 text-center">
                  No ledger opening revisions recorded yet.
                </p>
              ) : (
                historyItems.map((item) => (
                  <div
                    key={item.entryId}
                    className={`p-3 rounded-[var(--dw-radius-md)] border ${
                      item.isVoided
                        ? 'border-[var(--dw-border)] opacity-60'
                        : 'border-[var(--dw-primary)]/40 bg-[var(--dw-primary-container-subtle)]'
                    }`}
                  >
                    <div className="flex items-center justify-between font-semibold text-[var(--dw-text-primary)]">
                      <span>{item.description}</span>
                      <span className="font-mono tabular-nums">
                        {formatCurrencyCents(item.amountCents, historyAccount.currencyCode)}
                      </span>
                    </div>
                    <div className="text-[11px] text-[var(--dw-text-muted)] mt-1 font-mono">
                      {item.dateIso} · {item.provenanceKey} · {item.isVoided ? 'Voided' : 'Active'}
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>
      )}

      {/* Category Add/Edit Modal */}
      {catModalOpen && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={editingCategory ? 'Edit Category' : 'Add Category'}
          className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4"
        >
          <form
            onSubmit={submitCategory}
            className="w-full max-w-md rounded-[var(--dw-radius-lg)] bg-[var(--dw-card)] border border-[var(--dw-border)] p-5 space-y-4 shadow-xl"
          >
            <div className="flex items-center justify-between">
              <h3 className="dw-type-title text-[var(--dw-text-primary)]">
                {editingCategory ? 'Edit Category' : 'Add Category'}
              </h3>
              <DaywellIconButton
                label="Close category modal"
                size="compact"
                tone="muted"
                onClick={() => setCatModalOpen(false)}
                icon={<X className="w-4 h-4" />}
              />
            </div>
            {catError && <DaywellStatusBanner tone="error" message={catError} />}
            <div className="space-y-3 text-xs">
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                  Category Name
                </label>
                <input
                  type="text"
                  value={catName}
                  onChange={(e) => setCatName(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
                  placeholder="e.g. Dining Out"
                />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Type</label>
                  <select
                    value={catType}
                    onChange={(e) => setCatType(e.target.value as 'expense' | 'income')}
                    disabled={Boolean(editingCategory)}
                    className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
                  >
                    <option value="expense">Expense</option>
                    <option value="income">Income</option>
                  </select>
                </div>
                <div>
                  <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Color</label>
                  <input
                    type="color"
                    value={catColor}
                    onChange={(e) => setCatColor(e.target.value)}
                    className="w-full h-9 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-transparent cursor-pointer"
                  />
                </div>
              </div>
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                  Parent Category (Optional)
                </label>
                <select
                  value={catParentId}
                  onChange={(e) => setCatParentId(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
                >
                  <option value="">None (Top-level)</option>
                  {parentCandidates.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name}
                    </option>
                  ))}
                </select>
              </div>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <DaywellButton
                label="Cancel"
                variant="text"
                size="compact"
                onClick={() => setCatModalOpen(false)}
              />
              <DaywellButton type="submit" label="Save Category" variant="primary" size="compact" />
            </div>
          </form>
        </div>
      )}
    </div>
  );
}
