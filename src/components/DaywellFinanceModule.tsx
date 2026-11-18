import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Wallet,
  Building2,
  Calendar,
  CheckCircle2,
  ChevronRight,
  Plus,
  RotateCcw,
  AlertTriangle,
} from 'lucide-react';
import {
  Account,
  AccountSubType,
  assertCanArchiveAccountV7,
  assertEtbDebtEligible,
  assertEtbPostingAccounts,
  buildBorrowMoney,
  buildDebtSettlement,
  buildDebtWriteOff,
  buildDirectExpense,
  buildDirectIncome,
  buildLendMoney,
  buildSplitExpense,
  buildThirdPartyPaidExpense,
  buildTransfer,
  calculateAvailableToSpendBreakdownV7,
  canCorrectJournalEntryV7,
  correctJournalEntryV7,
  Debt,
  ensureSystemControlAccounts,
  fundSavingsGoalV7,
  hydrateLedgerFromSimpleTransactions,
  isActiveVerifiedEtbAccount,
  isEtbCurrency,
  JournalEntry,
  normalizeCurrencyCode,
  Party,
  Posting,
  processDueRecurringRulesV7,
  recordCommitmentSettlementV7,
  recordExpenseRefundV7,
  reviseAccountOpeningBalanceV7,
  SettlementAllocation,
  SharedBudget,
  SharedCommitment,
  SharedCommitmentSettlement,
  SharedRecurringRule,
  SharedSavingsGoal,
  SimpleTransaction,
  skipNextRecurringOccurrenceV7,
  syncVaultSavingsGoalsV7,
  TransactionCategory,
  unvoidJournalEntryGuardedV7,
  verifyFinanceV7Integrity,
  voidCommitmentSettlementV7,
  voidDebtOriginV7,
  voidDebtWriteOffV7,
  voidJournalEntryGuardedV7,
} from '../domain/financeV7Engine';
import {
  DoubleEntryValidationError,
  FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
  FOUNDATION_DEFAULT_INCOME_CATEGORIES,
  isDuplicateCategoryName,
} from '../domain/doubleEntryFinance';
import { SYSTEM_CONTROL_ACCOUNT_IDS } from '../domain/sharedFoundation';
import { CalendarDate, EthiopiaClock } from '../domain/date';
import { formatBirr, parseDecimalToCentsStrict } from '../domain/financialEngine';
import { SharedStateBridge } from '../services/sharedStateBridge';
import { FinanceOverviewTab } from './finance/FinanceOverviewTab';
import { FinanceTransactionsTab } from './finance/FinanceTransactionsTab';
import { FinancePlanTab } from './finance/FinancePlanTab';
import { FinanceReportsTab } from './finance/FinanceReportsTab';
import { FinanceComposerModal } from './finance/FinanceComposerModal';
import {
  ComposerKind,
  ConfirmActionState,
  FinanceComposerPrefill,
  FinanceV7Tab,
} from './finance/financeV7Types';
import {
  DaywellButton,
  DaywellCard,
  DaywellConfirmationDialog,
  DaywellStatusBanner,
} from './ui';

export type FinanceTab = FinanceV7Tab;

interface DaywellFinanceModuleProps {
  effectiveDark: boolean;
  onOpenQuickCapture?: () => void;
  composerPrefill?: FinanceComposerPrefill | null;
  onClearComposerPrefill?: () => void;
}

function readStoredArray<T>(key: string, fallback: T[] = []): T[] {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return fallback;
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : fallback;
  } catch {
    return fallback;
  }
}

export function DaywellFinanceModule({
  composerPrefill,
  onClearComposerPrefill,
}: DaywellFinanceModuleProps) {
  const todayStr = useMemo(() => CalendarDate.today().toIsoString(), []);
  const [activeTab, setActiveTab] = useState<FinanceV7Tab>('overview');
  const isApplyingExternalSyncRef = useRef(false);

  // 1. Setup State
  const [isSetupCompleted, setIsSetupCompleted] = useState<boolean>(() => {
    try {
      if (localStorage.getItem('daywell_finance_setup_completed') === 'true') return true;
      const savedAccounts = localStorage.getItem('daywell_accounts');
      if (savedAccounts) {
        const parsed = JSON.parse(savedAccounts);
        if (Array.isArray(parsed) && parsed.some((a: Account) => !a.isSystem)) return true;
      }
    } catch {
      // ignore
    }
    return false;
  });

  const [setupStep, setSetupStep] = useState<1 | 2>(1);
  const [setupAccountsList, setSetupAccountsList] = useState<
    Array<{
      id: string;
      name: string;
      subType: AccountSubType;
      balanceText: string;
      openingDate: string;
      isActive: boolean;
    }>
  >([
    { id: 'acc-cbe', name: 'CBE', subType: 'bank', balanceText: '', openingDate: todayStr, isActive: true },
    { id: 'acc-boa', name: 'BOA', subType: 'bank', balanceText: '', openingDate: todayStr, isActive: true },
    { id: 'acc-dashen', name: 'Dashen Bank', subType: 'bank', balanceText: '', openingDate: todayStr, isActive: true },
    { id: 'acc-telebirr', name: 'Telebirr', subType: 'mobile_money', balanceText: '', openingDate: todayStr, isActive: true },
    { id: 'acc-cash', name: 'Cash', subType: 'cash', balanceText: '', openingDate: todayStr, isActive: true },
  ]);
  const [setupCustomName, setSetupCustomName] = useState('');
  const [setupCustomBalance, setSetupCustomBalance] = useState('');
  const [setupError, setSetupError] = useState<string | null>(null);

  // 2. Canonical v7 Stores
  const [accounts, setAccounts] = useState<Account[]>(() =>
    ensureSystemControlAccounts(readStoredArray<Account>('daywell_accounts'))
  );
  const [categories, setCategories] = useState<TransactionCategory[]>(() => {
    const saved = readStoredArray<TransactionCategory>('daywell_categories');
    return saved.length > 0
      ? saved
      : [...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES, ...FOUNDATION_DEFAULT_INCOME_CATEGORIES];
  });
  const [simpleTransactions, setSimpleTransactions] = useState<SimpleTransaction[]>(() => {
    const rawPrimary = localStorage.getItem('daywell_finance_transactions');
    if (rawPrimary) {
      try {
        const parsed = JSON.parse(rawPrimary);
        if (Array.isArray(parsed)) return parsed;
      } catch {
        // ignore
      }
    }
    return readStoredArray<SimpleTransaction>('daywell_transactions');
  });
  const [parties, setParties] = useState<Party[]>(() => readStoredArray<Party>('daywell_parties'));
  const [entries, setEntries] = useState<JournalEntry[]>(() =>
    readStoredArray<JournalEntry>('daywell_journal_entries')
  );
  const [postings, setPostings] = useState<Posting[]>(() =>
    readStoredArray<Posting>('daywell_postings')
  );
  const [debts, setDebts] = useState<Debt[]>(() => readStoredArray<Debt>('daywell_debts'));
  const [allocations, setAllocations] = useState<SettlementAllocation[]>(() =>
    readStoredArray<SettlementAllocation>('daywell_settlement_allocations')
  );
  const [commitments, setCommitments] = useState<SharedCommitment[]>(() =>
    readStoredArray<SharedCommitment>('daywell_commitments')
  );
  const [commitmentSettlements, setCommitmentSettlements] = useState<SharedCommitmentSettlement[]>(
    () => readStoredArray<SharedCommitmentSettlement>('daywell_commitment_settlements')
  );
  const [savingsGoals, setSavingsGoals] = useState<SharedSavingsGoal[]>(() =>
    readStoredArray<SharedSavingsGoal>('daywell_savings_goals')
  );
  const [budgets, setBudgets] = useState<SharedBudget[]>(() =>
    readStoredArray<SharedBudget>('daywell_budgets')
  );
  const [recurringRules, setRecurringRules] = useState<SharedRecurringRule[]>(() =>
    readStoredArray<SharedRecurringRule>('daywell_recurring_rules')
  );
  const [planningPeriodEnd, setPlanningPeriodEnd] = useState<string | null>(() => {
    try {
      return localStorage.getItem('daywell_finance_planning_horizon') || null;
    } catch {
      return null;
    }
  });

  // UI Overlays: Composer, Confirm Modal, Status Toast
  const [composerOpen, setComposerOpen] = useState(false);
  const [activePrefill, setActivePrefill] = useState<FinanceComposerPrefill | null>(null);
  const [confirmState, setConfirmState] = useState<ConfirmActionState | null>(null);
  const [toastMsg, setToastMsg] = useState<string | null>(null);
  const toastTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const showToast = useCallback((msg: string) => {
    if (toastTimerRef.current) clearTimeout(toastTimerRef.current);
    setToastMsg(msg);
    toastTimerRef.current = setTimeout(() => setToastMsg(null), 4000);
  }, []);

  const notifyCanonicalSynced = useCallback(() => {
    if (isApplyingExternalSyncRef.current) return;
    window.dispatchEvent(new CustomEvent(SharedStateBridge.SYNC_EVENT_NAME));
  }, []);

  // Hydrate ledger whenever SimpleTransaction[] or Accounts gain unindexed items (e.g. Quick Capture or legacy seed)
  useEffect(() => {
    if (!isSetupCompleted) return;
    const res = hydrateLedgerFromSimpleTransactions({
      accounts,
      transactions: simpleTransactions,
      entries,
      postings,
    });
    const addedControls = res.accounts.length !== accounts.length;
    const addedLedger = res.entries.length !== entries.length || res.postings.length !== postings.length;
    if (addedControls) setAccounts(res.accounts);
    if (addedLedger) {
      setEntries(res.entries);
      setPostings(res.postings);
    }
  }, [isSetupCompleted, accounts, simpleTransactions, entries, postings]);

  // Persist v7 state to localStorage
  useEffect(() => {
    try {
      localStorage.setItem('daywell_accounts', JSON.stringify(accounts));
      localStorage.setItem('daywell_categories', JSON.stringify(categories));
      localStorage.setItem('daywell_finance_transactions', JSON.stringify(simpleTransactions));
      localStorage.setItem('daywell_transactions', JSON.stringify(simpleTransactions));
      localStorage.setItem('daywell_parties', JSON.stringify(parties));
      localStorage.setItem('daywell_journal_entries', JSON.stringify(entries));
      localStorage.setItem('daywell_postings', JSON.stringify(postings));
      localStorage.setItem('daywell_debts', JSON.stringify(debts));
      localStorage.setItem('daywell_settlement_allocations', JSON.stringify(allocations));
      localStorage.setItem('daywell_commitments', JSON.stringify(commitments));
      localStorage.setItem(
        'daywell_commitment_settlements',
        JSON.stringify(commitmentSettlements)
      );
      localStorage.setItem('daywell_savings_goals', JSON.stringify(savingsGoals));
      localStorage.setItem('daywell_budgets', JSON.stringify(budgets));
      localStorage.setItem('daywell_recurring_rules', JSON.stringify(recurringRules));
      if (planningPeriodEnd) {
        localStorage.setItem('daywell_finance_planning_horizon', planningPeriodEnd);
      } else {
        localStorage.removeItem('daywell_finance_planning_horizon');
      }
    } catch (e) {
      console.error('Failed to persist finance state:', e);
    }
  }, [
    accounts,
    categories,
    simpleTransactions,
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
    planningPeriodEnd,
  ]);

  const reloadFromStorage = useCallback(() => {
    isApplyingExternalSyncRef.current = true;
    try {
      const nextAcc = ensureSystemControlAccounts(readStoredArray<Account>('daywell_accounts'));
      const nextCat = readStoredArray<TransactionCategory>('daywell_categories');
      const nextTx = readStoredArray<SimpleTransaction>('daywell_finance_transactions');
      const nextEntries = readStoredArray<JournalEntry>('daywell_journal_entries');
      const nextPostings = readStoredArray<Posting>('daywell_postings');
      const hydrated = hydrateLedgerFromSimpleTransactions({
        accounts: nextAcc,
        transactions: nextTx,
        entries: nextEntries,
        postings: nextPostings,
      });

      setAccounts(hydrated.accounts);
      if (nextCat.length > 0) setCategories(nextCat);
      setSimpleTransactions(nextTx);
      setParties(readStoredArray<Party>('daywell_parties'));
      setEntries(hydrated.entries);
      setPostings(hydrated.postings);
      setDebts(readStoredArray<Debt>('daywell_debts'));
      setAllocations(readStoredArray<SettlementAllocation>('daywell_settlement_allocations'));
      setCommitments(readStoredArray<SharedCommitment>('daywell_commitments'));
      setCommitmentSettlements(
        readStoredArray<SharedCommitmentSettlement>('daywell_commitment_settlements')
      );
      setSavingsGoals(readStoredArray<SharedSavingsGoal>('daywell_savings_goals'));
      setBudgets(readStoredArray<SharedBudget>('daywell_budgets'));
      setRecurringRules(readStoredArray<SharedRecurringRule>('daywell_recurring_rules'));
      setPlanningPeriodEnd(localStorage.getItem('daywell_finance_planning_horizon') || null);
      setIsSetupCompleted(
        localStorage.getItem('daywell_finance_setup_completed') === 'true' ||
          hydrated.accounts.some((a) => !a.isSystem)
      );
    } finally {
      setTimeout(() => {
        isApplyingExternalSyncRef.current = false;
      }, 0);
    }
  }, []);

  // Listen for canonical sync from Backup/Restore or Quick Capture
  useEffect(() => {
    window.addEventListener(SharedStateBridge.SYNC_EVENT_NAME, reloadFromStorage);
    return () => window.removeEventListener(SharedStateBridge.SYNC_EVENT_NAME, reloadFromStorage);
  }, [reloadFromStorage]);

  // Accept Quick Capture -> Finance Composer handoff
  useEffect(() => {
    if (!composerPrefill) return;
    if (!isSetupCompleted) return;
    setActivePrefill(composerPrefill);
    setComposerOpen(true);
    onClearComposerPrefill?.();
  }, [composerPrefill, isSetupCompleted, onClearComposerPrefill]);

  // Computed Safe Harbor Breakdown & Integrity Audit
  const breakdown = useMemo(
    () =>
      calculateAvailableToSpendBreakdownV7({
        accounts,
        postings,
        entries,
        debts,
        allocations,
        commitments,
        commitmentSettlements,
        recurringRules,
        savingsGoals,
        planningPeriodEndIso: planningPeriodEnd || undefined,
      }),
    [
      accounts,
      postings,
      entries,
      debts,
      allocations,
      commitments,
      commitmentSettlements,
      recurringRules,
      savingsGoals,
      planningPeriodEnd,
    ]
  );

  const integrityReport = useMemo(
    () =>
      verifyFinanceV7Integrity({
        accounts,
        entries,
        postings,
        debts,
        commitments,
        allocations,
        recurringRules,
        commitmentSettlements,
        savingsGoals,
      }),
    [accounts, entries, postings, debts, commitments, allocations, recurringRules, commitmentSettlements, savingsGoals]
  );

  const requestConfirm = (
    title: string,
    message: string,
    confirmLabel: string,
    tone: 'danger' | 'primary',
    onConfirm: () => void
  ) => {
    setConfirmState({ title, message, confirmLabel, tone, onConfirm });
  };

  const openComposer = (
    kind: ComposerKind,
    correctedFromEntryId?: string,
    prefill?: Omit<FinanceComposerPrefill, 'nonce' | 'kind' | 'correctedFromEntryId'>
  ) => {
    setActivePrefill({
      nonce: Date.now(),
      kind,
      correctedFromEntryId,
      amountText: prefill?.amountText,
      description: prefill?.description,
      accountId: prefill?.accountId,
      destinationAccountId: prefill?.destinationAccountId,
      categoryId: prefill?.categoryId,
      occurrenceDate: prefill?.occurrenceDate,
      movementDate: prefill?.movementDate,
      feeText: prefill?.feeText,
      feeCategoryId: prefill?.feeCategoryId,
      note: prefill?.note,
    });
    setComposerOpen(true);
  };

  // -------------------------------------------------------------
  // Setup Wizard Handlers
  // -------------------------------------------------------------
  const handleToggleSetupAccount = (id: string) => {
    setSetupAccountsList((prev) =>
      prev.map((acc) => (acc.id === id ? { ...acc, isActive: !acc.isActive } : acc))
    );
  };

  const handleUpdateSetupBalance = (id: string, text: string) => {
    setSetupAccountsList((prev) =>
      prev.map((acc) => (acc.id === id ? { ...acc, balanceText: text } : acc))
    );
  };

  const handleUpdateSetupDate = (id: string, date: string) => {
    setSetupAccountsList((prev) =>
      prev.map((acc) => (acc.id === id ? { ...acc, openingDate: date } : acc))
    );
  };

  const handleAddSetupCustomAccount = () => {
    const trimmed = setupCustomName.trim();
    if (!trimmed) {
      setSetupError('Please enter an account name.');
      return;
    }
    if (setupAccountsList.some((a) => a.name.toLowerCase() === trimmed.toLowerCase())) {
      setSetupError('An account with this name already exists.');
      return;
    }
    setSetupError(null);
    setSetupAccountsList((prev) => [
      ...prev,
      {
        id: `acc-custom-${Date.now()}`,
        name: trimmed,
        subType: 'bank',
        balanceText: setupCustomBalance.trim() || '0',
        openingDate: todayStr,
        isActive: true,
      },
    ]);
    setSetupCustomName('');
    setSetupCustomBalance('');
  };

  const handleProceedSetupToReview = () => {
    const active = setupAccountsList.filter((a) => a.isActive);
    if (active.length === 0) {
      setSetupError('Please select at least one account to proceed.');
      return;
    }
    for (const acc of active) {
      if (acc.balanceText.trim() !== '') {
        const parsed = parseDecimalToCentsStrict(acc.balanceText);
        if (!parsed.valid || parsed.cents < 0) {
          setSetupError(`Invalid balance for ${acc.name}. Enter 0 or a positive ETB amount (up to 2 decimal places).`);
          return;
        }
      }
    }
    setSetupError(null);
    setSetupStep(2);
  };

  const handleCompleteSetup = () => {
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const userAccounts: Account[] = setupAccountsList
      .filter((a) => a.isActive)
      .map((a) => {
        const parsed = a.balanceText.trim() ? parseDecimalToCentsStrict(a.balanceText) : null;
        const cents = parsed && parsed.valid && parsed.cents > 0 ? parsed.cents : 0;
        return {
          id: a.id,
          name: a.name.trim(),
          type: 'asset',
          subType: a.subType,
          currencyCode: 'ETB',
          openingBalanceCents: cents,
          openingBalanceDate: a.openingDate || todayStr,
          isArchived: false,
          createdAt: nowIso,
        };
      });

    let nextAccounts = ensureSystemControlAccounts(userAccounts);
    let nextEntries = [...entries];
    let nextPostings = [...postings];

    for (let i = 0; i < nextAccounts.length; i += 1) {
      const acc = nextAccounts[i];
      if (acc.isSystem || (acc.openingBalanceCents || 0) === 0) continue;
      const rev = reviseAccountOpeningBalanceV7({
        account: acc,
        newOpeningBalanceCents: acc.openingBalanceCents || 0,
        newOpeningDateIso: acc.openingBalanceDate,
        entries: nextEntries,
        postings: nextPostings,
      });
      nextAccounts[i] = rev.updatedAccount;
      nextEntries = rev.updatedEntries;
      nextPostings = rev.updatedPostings;
    }

    setAccounts(nextAccounts);
    setEntries(nextEntries);
    setPostings(nextPostings);
    setIsSetupCompleted(true);
    try {
      localStorage.setItem('daywell_accounts', JSON.stringify(nextAccounts));
      localStorage.setItem('daywell_journal_entries', JSON.stringify(nextEntries));
      localStorage.setItem('daywell_postings', JSON.stringify(nextPostings));
      localStorage.setItem('daywell_finance_setup_completed', 'true');
    } catch {
      // ignore
    }
    setTimeout(notifyCanonicalSynced, 0);
  };

  // -------------------------------------------------------------
  // Account & Category Handlers (with :rev:{n} & ON DELETE RESTRICT)
  // -------------------------------------------------------------
  const handleSaveAccount = (payload: {
    editingAccount?: Account;
    name: string;
    subType: AccountSubType;
    currencyCode: string;
    openingBalanceCents: number;
    openingBalanceDate: string;
  }): { ok: boolean; error?: string } => {
    const accountType: Account['type'] =
      payload.subType === 'credit_card' || payload.subType === 'payable' ? 'liability' : 'asset';
    const nowIso = EthiopiaClock.nowUtc().toISOString();

    if (payload.editingAccount) {
      const target = payload.editingAccount;
      const targetNormCur = normalizeCurrencyCode(target.currencyCode);
      const requestedNormCur = normalizeCurrencyCode(payload.currencyCode);
      if (requestedNormCur !== targetNormCur) {
        return {
          ok: false,
          error: 'Account currency cannot be changed after creation in first-release ETB mode.',
        };
      }

      const updatedMeta: Account = {
        ...target,
        name: payload.name,
        type: accountType,
        subType: payload.subType,
        currencyCode: target.currencyCode,
        updatedAt: nowIso,
      };
      const openingChanged =
        (target.openingBalanceCents || 0) !== payload.openingBalanceCents ||
        (target.openingBalanceDate || '') !== payload.openingBalanceDate;

      if (openingChanged) {
        if (!isEtbCurrency(target.currencyCode)) {
          return {
            ok: false,
            error: `Opening balance revisions are blocked on non-ETB or unverified account "${target.name}".`,
          };
        }
        try {
          const rev = reviseAccountOpeningBalanceV7({
            account: updatedMeta,
            newOpeningBalanceCents: payload.openingBalanceCents,
            newOpeningDateIso: payload.openingBalanceDate,
            entries,
            postings,
          });
          const nextAccounts = accounts.map((a) =>
            a.id === target.id ? rev.updatedAccount : a
          );
          setAccounts(nextAccounts);
          setEntries(rev.updatedEntries);
          setPostings(rev.updatedPostings);
          setSavingsGoals((prev) =>
            syncVaultSavingsGoalsV7({
              accounts: nextAccounts,
              entries: rev.updatedEntries,
              postings: rev.updatedPostings,
              savingsGoals: prev,
            })
          );
          showToast(`Revised opening balance for ${payload.name} (:rev provenance updated).`);
        } catch (err: unknown) {
          return {
            ok: false,
            error: err instanceof Error ? err.message : 'Opening balance revision failed.',
          };
        }
      } else {
        setAccounts((prev) => prev.map((a) => (a.id === target.id ? updatedMeta : a)));
        showToast(`Updated account ${payload.name}.`);
      }
    } else {
      const normalized = normalizeCurrencyCode(payload.currencyCode || 'ETB');
      if (normalized !== 'ETB') {
        return {
          ok: false,
          error: 'Only Verified ETB accounts can be created in first-release ETB mode.',
        };
      }
      const newAcc: Account = {
        id: `acc-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
        name: payload.name,
        type: accountType,
        subType: payload.subType,
        currencyCode: 'ETB',
        openingBalanceCents: 0,
        openingBalanceDate: payload.openingBalanceDate,
        isArchived: false,
        createdAt: nowIso,
      };
      let nextEntries = entries;
      let nextPostings = postings;
      let finalAcc = newAcc;
      if (payload.openingBalanceCents !== 0) {
        try {
          const rev = reviseAccountOpeningBalanceV7({
            account: newAcc,
            newOpeningBalanceCents: payload.openingBalanceCents,
            newOpeningDateIso: payload.openingBalanceDate,
            entries,
            postings,
          });
          finalAcc = rev.updatedAccount;
          nextEntries = rev.updatedEntries;
          nextPostings = rev.updatedPostings;
        } catch (err: unknown) {
          return {
            ok: false,
            error: err instanceof Error ? err.message : 'Could not set opening balance.',
          };
        }
      }
      setAccounts((prev) => ensureSystemControlAccounts([...prev, finalAcc]));
      setEntries(nextEntries);
      setPostings(nextPostings);
      showToast(`Created account ${payload.name}.`);
    }
    setTimeout(notifyCanonicalSynced, 0);
    return { ok: true };
  };

  const handleToggleArchiveAccount = (
    accountId: string
  ): { ok: boolean; error?: string } => {
    const target = accounts.find((a) => a.id === accountId);
    if (!target) {
      return { ok: false, error: 'Account not found.' };
    }
    if (!target.isArchived) {
      try {
        assertCanArchiveAccountV7({
          account: target,
          entries,
          postings,
        });
      } catch (err: unknown) {
        const msg =
          err instanceof Error ? err.message : 'Cannot archive account with nonzero balance.';
        showToast(msg);
        return { ok: false, error: msg };
      }
    }
    setAccounts((prev) =>
      prev.map((a) => (a.id === accountId ? { ...a, isArchived: !a.isArchived } : a))
    );
    showToast(target.isArchived ? `Restored account ${target.name}.` : `Archived account ${target.name}.`);
    setTimeout(notifyCanonicalSynced, 0);
    return { ok: true };
  };

  const handleDeleteAccount = (accountId: string): { ok: boolean; error?: string } => {
    const usedInPostings = postings.some((p) => p.accountId === accountId);
    const usedInTx = simpleTransactions.some(
      (t) => t.accountId === accountId || t.destinationAccountId === accountId
    );
    const usedInPlan =
      commitments.some((c) => c.linkedAccountId === accountId) ||
      savingsGoals.some((g) => g.linkedAccountId === accountId) ||
      recurringRules.some(
        (r) => r.accountId === accountId || r.destinationAccountId === accountId
      );

    if (usedInPostings || usedInTx || usedInPlan) {
      return {
        ok: false,
        error:
          'ON DELETE RESTRICT: This account is referenced by ledger postings or plans. Archive it instead to preserve ledger integrity.',
      };
    }

    setAccounts((prev) => prev.filter((a) => a.id !== accountId));
    setTimeout(notifyCanonicalSynced, 0);
    return { ok: true };
  };

  const handleSaveCategory = (payload: {
    editingCategory?: TransactionCategory & { parentId?: string };
    name: string;
    type: 'income' | 'expense';
    colorHex: string;
    parentId?: string;
  }): { ok: boolean; error?: string } => {
    if (
      isDuplicateCategoryName(
        payload.name,
        payload.type,
        categories,
        payload.editingCategory?.id
      )
    ) {
      return { ok: false, error: `A ${payload.type} category named "${payload.name}" already exists.` };
    }

    if (payload.editingCategory) {
      setCategories((prev) =>
        prev.map((c) =>
          c.id === payload.editingCategory!.id
            ? ({
                ...c,
                name: payload.name,
                type: payload.type,
                colorHex: payload.colorHex,
                parentId: payload.parentId,
              } as TransactionCategory)
            : c
        )
      );
    } else {
      const newCat: TransactionCategory & { parentId?: string } = {
        id: `cat-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
        name: payload.name,
        type: payload.type,
        colorHex: payload.colorHex,
        isArchived: false,
        parentId: payload.parentId,
      };
      setCategories((prev) => [...prev, newCat]);
    }
    setTimeout(notifyCanonicalSynced, 0);
    return { ok: true };
  };

  const handleToggleArchiveCategory = (categoryId: string) => {
    setCategories((prev) =>
      prev.map((c) => (c.id === categoryId ? { ...c, isArchived: !c.isArchived } : c))
    );
    setTimeout(notifyCanonicalSynced, 0);
  };

  const handleDeleteCategory = (categoryId: string): { ok: boolean; error?: string } => {
    const used =
      postings.some((p) => p.categoryId === categoryId) ||
      simpleTransactions.some((t) => t.categoryId === categoryId) ||
      budgets.some((b) => b.categoryId === categoryId) ||
      commitments.some((c) => c.categoryId === categoryId) ||
      recurringRules.some((r) => r.categoryId === categoryId) ||
      categories.some((c) => (c as TransactionCategory & { parentId?: string }).parentId === categoryId);

    if (used) {
      return {
        ok: false,
        error:
          'ON DELETE RESTRICT: This category is referenced by entries, budgets, rules, or subcategories. Archive it instead.',
      };
    }

    setCategories((prev) => prev.filter((c) => c.id !== categoryId));
    setTimeout(notifyCanonicalSynced, 0);
    return { ok: true };
  };

  // -------------------------------------------------------------
  // Composer Submission (7 Double-Entry Modes + Correction Replacement)
  // -------------------------------------------------------------
  const handleCreateParty = (name: string): Party => {
    const existing = parties.find((p) => p.name.toLowerCase() === name.trim().toLowerCase());
    if (existing) return existing;
    const p: Party = {
      id: `party-${Date.now()}-${Math.random().toString(36).slice(2, 5)}`,
      name: name.trim(),
      isArchived: false,
      createdAt: EthiopiaClock.nowUtc().toISOString(),
    };
    setParties((prev) => [...prev, p]);
    return p;
  };

  const handleComposerSubmit = (payload: {
    kind: ComposerKind;
    amountCents: number;
    theirShareCents?: number;
    feeCents?: number;
    feeCategoryId?: string;
    accountId: string;
    destinationAccountId?: string;
    categoryId?: string;
    partyId?: string;
    occurrenceDate: string;
    movementDate: string;
    dueDate?: string;
    description: string;
    note?: string;
    correctedFromEntryId?: string;
  }): { ok: boolean; error?: string } => {
    try {
      if (payload.correctedFromEntryId) {
        const orig = entries.find((e) => e.id === payload.correctedFromEntryId);
        if (!orig) {
          return { ok: false, error: 'Original entry to replace was not found.' };
        }
        const check = canCorrectJournalEntryV7({
          entry: orig,
          entries,
          postings,
          accounts,
          debts,
          allocations,
        });
        if (!check.ok) {
          return { ok: false, error: check.error || 'This entry cannot be replaced directly.' };
        }
        if (payload.kind !== 'expense' && payload.kind !== 'income' && payload.kind !== 'transfer') {
          return {
            ok: false,
            error:
              'Replacing an entry into a debt or split transaction is disabled. Void the entry and record a new transaction instead.',
          };
        }
      }

      if (payload.kind === 'third_party') {
        return {
          ok: false,
          error:
            'Unbacked third-party entries without an active Verified ETB account leg are disabled in ETB first-release mode. Use Split Expense or Borrow from an ETB account.',
        };
      }

      assertEtbPostingAccounts({
        accounts,
        accountIds:
          payload.kind === 'transfer'
            ? [payload.accountId, payload.destinationAccountId || '']
            : [payload.accountId],
        roleLabels:
          payload.kind === 'transfer'
            ? ['From account', 'Destination account']
            : ['Posting account'],
      });

      const entryId = `entry-${payload.kind}-${Date.now()}`;
      const nowIso = EthiopiaClock.nowUtc().toISOString();
      let newEntry: JournalEntry;
      let newPostings: Posting[];
      let newDebt: Debt | undefined;
      let newSimpleTx: SimpleTransaction | undefined;

      if (payload.kind === 'expense') {
        const res = buildDirectExpense({
          id: entryId,
          assetAccountId: payload.accountId,
          expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
          categoryId: payload.categoryId || 'cat-other-exp',
          amountCents: payload.amountCents,
          occurrenceDate: payload.occurrenceDate,
          movementDate: payload.movementDate,
          description: payload.description,
          note: payload.note,
        });
        newEntry = res.entry;
        newPostings = res.postings;
        newSimpleTx = {
          id: `tx-${entryId}`,
          type: 'expense',
          amountCents: payload.amountCents,
          accountId: payload.accountId,
          categoryId: payload.categoryId || 'cat-other-exp',
          description: payload.description,
          transactionDate: payload.occurrenceDate,
          createdAt: nowIso,
          updatedAt: nowIso,
          journalEntryId: entryId,
        };
      } else if (payload.kind === 'income') {
        const res = buildDirectIncome({
          id: entryId,
          assetAccountId: payload.accountId,
          incomeAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.income,
          categoryId: payload.categoryId || 'cat-other-inc',
          amountCents: payload.amountCents,
          occurrenceDate: payload.occurrenceDate,
          movementDate: payload.movementDate,
          description: payload.description,
          note: payload.note,
        });
        newEntry = res.entry;
        newPostings = res.postings;
        newSimpleTx = {
          id: `tx-${entryId}`,
          type: 'income',
          amountCents: payload.amountCents,
          accountId: payload.accountId,
          categoryId: payload.categoryId || 'cat-other-inc',
          description: payload.description,
          transactionDate: payload.occurrenceDate,
          createdAt: nowIso,
          updatedAt: nowIso,
          journalEntryId: entryId,
        };
      } else if (payload.kind === 'transfer') {
        if (!payload.destinationAccountId) {
          return { ok: false, error: 'Destination account is required.' };
        }
        const res = buildTransfer({
          id: entryId,
          fromAssetAccountId: payload.accountId,
          toAssetAccountId: payload.destinationAccountId,
          amountCents: payload.amountCents,
          transferFeeCents: payload.feeCents || 0,
          feeExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
          feeCategoryId: payload.feeCategoryId,
          date: payload.occurrenceDate,
          movementDate: payload.movementDate,
          description: payload.description,
          note: payload.note,
        });
        newEntry = res.entry;
        newPostings = res.postings;
        newSimpleTx = {
          id: `tx-${entryId}`,
          type: 'transfer',
          amountCents: payload.amountCents,
          accountId: payload.accountId,
          destinationAccountId: payload.destinationAccountId,
          description: payload.description,
          transactionDate: payload.occurrenceDate,
          createdAt: nowIso,
          updatedAt: nowIso,
          journalEntryId: entryId,
        };
      } else if (payload.kind === 'split') {
        if (!payload.partyId) return { ok: false, error: 'Select a counterparty for Split Expense.' };
        const theirShareCents = payload.theirShareCents || 0;
        const myShareCents = payload.amountCents - theirShareCents;
        if (theirShareCents <= 0 || myShareCents <= 0) {
          return {
            ok: false,
            error: 'Split requires both your share and their share to be greater than zero.',
          };
        }
        const res = buildSplitExpense({
          entryId,
          debtId: `debt-${entryId}`,
          paidAssetAccountId: payload.accountId,
          myExpenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
          receivableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
          categoryId: payload.categoryId || 'cat-other-exp',
          partyId: payload.partyId,
          myShareCents,
          theirShareCents,
          occurrenceDate: payload.occurrenceDate,
          description: payload.description,
          dueDate: payload.dueDate,
        });
        newEntry = res.entry;
        newPostings = res.postings;
        newDebt = res.debt;
      } else if (payload.kind === 'lend') {
        if (!payload.partyId) return { ok: false, error: 'Select a counterparty to lend to.' };
        const res = buildLendMoney({
          entryId,
          debtId: `debt-${entryId}`,
          sourceAssetAccountId: payload.accountId,
          receivableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
          partyId: payload.partyId,
          amountCents: payload.amountCents,
          date: payload.occurrenceDate,
          dueDate: payload.dueDate,
          description: payload.description,
        });
        newEntry = res.entry;
        newPostings = res.postings;
        newDebt = res.debt;
      } else if (payload.kind === 'borrow') {
        if (!payload.partyId) return { ok: false, error: 'Select a counterparty you borrowed from.' };
        const res = buildBorrowMoney({
          entryId,
          debtId: `debt-${entryId}`,
          destAssetAccountId: payload.accountId,
          payableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.payable,
          partyId: payload.partyId,
          amountCents: payload.amountCents,
          date: payload.occurrenceDate,
          dueDate: payload.dueDate,
          description: payload.description,
        });
        newEntry = res.entry;
        newPostings = res.postings;
        newDebt = res.debt;
      } else {
        if (!payload.partyId) return { ok: false, error: 'Select a counterparty who paid for you.' };
        const res = buildThirdPartyPaidExpense({
          entryId,
          debtId: `debt-${entryId}`,
          expenseAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
          payableAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.payable,
          categoryId: payload.categoryId || 'cat-other-exp',
          partyId: payload.partyId,
          amountCents: payload.amountCents,
          occurrenceDate: payload.occurrenceDate,
          dueDate: payload.dueDate,
          description: payload.description,
        });
        newEntry = res.entry;
        newPostings = res.postings;
        newDebt = res.debt;
      }

      if (payload.correctedFromEntryId) {
        const res = correctJournalEntryV7({
          originalEntryId: payload.correctedFromEntryId,
          replacementEntry: newEntry,
          replacementPostings: newPostings,
          correctionReason: `Replaced by ${entryId}`,
          accounts,
          entries,
          postings,
          debts,
          allocations,
          commitments,
          savingsGoals,
          simpleTransactions,
          replacementSimpleTx: newSimpleTx,
        });
        setEntries(res.updatedEntries);
        setPostings(res.updatedPostings);
        setDebts(res.updatedDebts);
        setCommitments(res.updatedCommitments);
        setSavingsGoals(res.updatedSavingsGoals);
        setSimpleTransactions(res.updatedSimpleTransactions);
      } else {
        const nextEntries = [newEntry, ...entries];
        const nextPostings = [...newPostings, ...postings];
        setEntries(nextEntries);
        setPostings(nextPostings);
        if (newDebt) {
          setDebts((prev) => [newDebt!, ...prev]);
        }
        if (newSimpleTx) {
          setSimpleTransactions((prev) => [newSimpleTx!, ...prev]);
        }
        setSavingsGoals((prev) =>
          syncVaultSavingsGoalsV7({
            accounts,
            entries: nextEntries,
            postings: nextPostings,
            savingsGoals: prev,
          })
        );
      }

      showToast(
        payload.correctedFromEntryId ? 'Entry replaced with audit trail.' : `Saved: ${payload.description}`
      );
      setTimeout(notifyCanonicalSynced, 0);
      return { ok: true };
    } catch (err: unknown) {
      if (err instanceof DoubleEntryValidationError || err instanceof Error) {
        return { ok: false, error: err.message };
      }
      return { ok: false, error: 'Failed to save transaction.' };
    }
  };

  // -------------------------------------------------------------
  // Void / Restore / Refund Entry
  // -------------------------------------------------------------
  const handleVoidEntry = (entryId: string, reason: string): { ok: boolean; error?: string } => {
    try {
      const res = voidJournalEntryGuardedV7({
        entryId,
        reason,
        accounts,
        entries,
        postings,
        debts,
        allocations,
        commitments,
        commitmentSettlements,
        savingsGoals,
        simpleTransactions,
      });
      setEntries(res.updatedEntries);
      setDebts(res.updatedDebts);
      setCommitments(res.updatedCommitments);
      setSavingsGoals(res.updatedSavingsGoals);
      setSimpleTransactions(res.updatedSimpleTransactions);
      showToast('Journal entry voided.');
      setTimeout(notifyCanonicalSynced, 0);
      return { ok: true };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Cannot void journal entry.';
      showToast(msg);
      return { ok: false, error: msg };
    }
  };

  const handleRestoreEntry = (entryId: string): { ok: boolean; error?: string } => {
    try {
      const res = unvoidJournalEntryGuardedV7({
        entryId,
        accounts,
        entries,
        postings,
        debts,
        allocations,
        commitments,
        commitmentSettlements,
        savingsGoals,
        simpleTransactions,
      });
      setEntries(res.updatedEntries);
      setDebts(res.updatedDebts);
      setCommitments(res.updatedCommitments);
      setSavingsGoals(res.updatedSavingsGoals);
      setSimpleTransactions(res.updatedSimpleTransactions);
      showToast('Journal entry restored.');
      setTimeout(notifyCanonicalSynced, 0);
      return { ok: true };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Only Verified ETB entries can be restored.';
      showToast(msg);
      return { ok: false, error: msg };
    }
  };

  const handleExpenseRefund = (payload: {
    originalEntryId: string;
    refundAccountId: string;
    refundCents: number;
    refundDateIso: string;
    note?: string;
  }): { ok: boolean; error?: string } => {
    try {
      const res = recordExpenseRefundV7({
        originalEntryId: payload.originalEntryId,
        refundAccountId: payload.refundAccountId,
        refundCents: payload.refundCents,
        refundDateIso: payload.refundDateIso,
        note: payload.note,
        entries,
        postings,
        accounts,
        debts,
        allocations,
      });
      const nextEntries = [res.entry, ...entries];
      const nextPostings = [...res.postings, ...postings];
      setEntries(nextEntries);
      setPostings(nextPostings);
      showToast(`Recorded refund: ${res.entry.description}`);
      setTimeout(notifyCanonicalSynced, 0);
      return { ok: true };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Failed to record expense refund.';
      return { ok: false, error: msg };
    }
  };

  // -------------------------------------------------------------
  // Plan Tab Handlers (Commitments, Debts, Goals, Budgets, Rules)
  // -------------------------------------------------------------
  const handleAddCommitment = (
    c: Omit<SharedCommitment, 'id' | 'isPaid'>
  ): { ok: boolean; error?: string } => {
    try {
      const linkedAccId = c.linkedAccountId?.trim();
      const linkedDebtId = c.linkedDebtId?.trim();
      if (linkedAccId) {
        assertEtbPostingAccounts({
          accounts,
          accountIds: [linkedAccId],
          roleLabels: ['Linked account'],
        });
      }
      if (linkedDebtId) {
        const targetDebt = debts.find((d) => d.id === linkedDebtId);
        if (!targetDebt) {
          return { ok: false, error: 'Referenced debt not found.' };
        }
        assertEtbDebtEligible({
          debt: targetDebt,
          entries,
          postings,
          accounts,
          allocations,
        });
      }
      const newItem: SharedCommitment = {
        ...c,
        linkedAccountId: linkedAccId || undefined,
        linkedDebtId: linkedDebtId || undefined,
        id: `com-${Date.now()}-${Math.random().toString(36).slice(2, 5)}`,
        isPaid: false,
        legacyPaidUnverified: false,
      };
      setCommitments((prev) => [newItem, ...prev]);
      showToast(`Added ${c.direction === 'inflow' ? 'expected inflow' : 'outflow'} commitment.`);
      setTimeout(notifyCanonicalSynced, 0);
      return { ok: true };
    } catch (err: unknown) {
      return {
        ok: false,
        error: err instanceof Error ? err.message : 'Commitment must link to active Verified ETB accounts.',
      };
    }
  };

  const handleLinkCommitmentAccount = (
    commitmentId: string,
    accountId: string
  ): { ok: boolean; error?: string } => {
    const trimmedAccId = accountId.trim();
    if (!trimmedAccId) {
      return { ok: false, error: 'Select an active Verified ETB account to link.' };
    }
    try {
      assertEtbPostingAccounts({
        accounts,
        accountIds: [trimmedAccId],
        roleLabels: ['Linked account'],
      });
      setCommitments((prev) =>
        prev.map((c) => (c.id === commitmentId ? { ...c, linkedAccountId: trimmedAccId } : c))
      );
      showToast('Linked commitment to Verified ETB account.');
      setTimeout(notifyCanonicalSynced, 0);
      return { ok: true };
    } catch (err: unknown) {
      return {
        ok: false,
        error: err instanceof Error ? err.message : 'Failed to link ETB account.',
      };
    }
  };

  const handleRecordCommitmentSettlement = (payload: {
    commitmentId: string;
    accountId: string;
    amountCents: number;
    settledDateIso: string;
  }): { ok: boolean; error?: string } => {
    const target = commitments.find((c) => c.id === payload.commitmentId);
    if (!target) return { ok: false, error: 'Commitment not found.' };
    try {
      const res = recordCommitmentSettlementV7({
        commitment: target,
        accountId: payload.accountId,
        amountCents: payload.amountCents,
        settledDateIso: payload.settledDateIso,
        existingSettlements: commitmentSettlements,
        entries,
        accounts,
        postings,
        debts,
        allocations,
        recurringRules,
      });
      setCommitments((prev) => prev.map((c) => (c.id === target.id ? res.updatedCommitment : c)));
      setCommitmentSettlements((prev) => [res.settlement, ...prev]);
      setEntries((prev) => [res.entry, ...prev]);
      setPostings((prev) => [...res.postings, ...prev]);
      setSimpleTransactions((prev) => [res.simpleTransaction, ...prev]);
      showToast(`Recorded settlement for "${target.title}".`);
      setTimeout(notifyCanonicalSynced, 0);
      return { ok: true };
    } catch (err: unknown) {
      return { ok: false, error: err instanceof Error ? err.message : 'Settlement failed.' };
    }
  };

  const handleVoidCommitmentSettlement = (settlementId: string, commitmentId: string) => {
    const target = commitments.find((c) => c.id === commitmentId);
    if (!target) return;
    try {
      const res = voidCommitmentSettlementV7({
        settlementId,
        reason: 'Voided commitment installment',
        commitment: target,
        settlements: commitmentSettlements,
        entries,
      });
      const voidedSet = commitmentSettlements.find((s) => s.id === settlementId);
      setCommitments((prev) => prev.map((c) => (c.id === commitmentId ? res.updatedCommitment : c)));
      setEntries(res.updatedEntries);
      if (voidedSet) {
        setSimpleTransactions((prev) =>
          prev.map((t) => (t.journalEntryId === voidedSet.entryId ? { ...t, isSuperseded: true } : t))
        );
      }
      showToast(`Voided installment for "${target.title}".`);
      setTimeout(notifyCanonicalSynced, 0);
    } catch (err) {
      console.error(err);
    }
  };

  const handleMarkLegacyUnpaid = (commitmentId: string) => {
    setCommitments((prev) =>
      prev.map((c) =>
        c.id === commitmentId ? { ...c, isPaid: false, legacyPaidUnverified: false } : c
      )
    );
    showToast('Marked commitment unpaid and restored remaining due balance.');
    setTimeout(notifyCanonicalSynced, 0);
  };

  const handleSettleDebt = (payload: {
    debtId: string;
    accountId: string;
    principalCents: number;
    interestCents: number;
    feeCents: number;
    dateIso: string;
  }): { ok: boolean; error?: string } => {
    const target = debts.find((d) => d.id === payload.debtId);
    if (!target) return { ok: false, error: 'Debt not found.' };
    try {
      assertEtbPostingAccounts({
        accounts,
        accountIds: [payload.accountId],
        roleLabels: ['Settlement account'],
      });
      assertEtbDebtEligible({
        debt: target,
        entries,
        postings,
        accounts,
        allocations,
      });
      const entryId = `entry-dset-${Date.now()}`;
      const res = buildDebtSettlement({
        settlementEntryId: entryId,
        debt: target,
        settlementAccountId: payload.accountId,
        debtAccountId:
          target.debtType === 'payable'
            ? SYSTEM_CONTROL_ACCOUNT_IDS.payable
            : SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
        interestAccountId:
          target.debtType === 'payable'
            ? SYSTEM_CONTROL_ACCOUNT_IDS.expense
            : SYSTEM_CONTROL_ACCOUNT_IDS.income,
        feeAccountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
        allocatedPrincipalCents: payload.principalCents,
        interestCents: payload.interestCents,
        feeCents: payload.feeCents,
        settlementDate: payload.dateIso,
        description: `Debt Settlement: ${
          parties.find((p) => p.id === target.partyId)?.name || target.debtType
        }`,
      });

      const nextOutstanding = Math.max(0, target.outstandingCents - payload.principalCents);
      setDebts((prev) =>
        prev.map((d) =>
          d.id === target.id
            ? {
                ...d,
                outstandingCents: nextOutstanding,
                status: nextOutstanding === 0 ? 'settled' : 'active',
              }
            : d
        )
      );
      setAllocations((prev) => [res.allocation, ...prev]);
      setEntries((prev) => [res.entry, ...prev]);
      setPostings((prev) => [...res.postings, ...prev]);
      showToast('Debt settlement posted to ledger.');
      setTimeout(notifyCanonicalSynced, 0);
      return { ok: true };
    } catch (err: unknown) {
      return { ok: false, error: err instanceof Error ? err.message : 'Debt settlement failed.' };
    }
  };

  const handleWriteOffDebt = (debtId: string, reason: string) => {
    const target = debts.find((d) => d.id === debtId);
    if (!target || target.outstandingCents <= 0) return;
    try {
      assertEtbDebtEligible({
        debt: target,
        entries,
        postings,
        accounts,
        allocations,
      });
      const entryId = `entry-wo-${Date.now()}`;
      const res = buildDebtWriteOff({
        writeOffEntryId: entryId,
        debt: target,
        debtAccountId:
          target.debtType === 'payable'
            ? SYSTEM_CONTROL_ACCOUNT_IDS.payable
            : SYSTEM_CONTROL_ACCOUNT_IDS.receivable,
        writeOffAccountId:
          target.debtType === 'payable'
            ? SYSTEM_CONTROL_ACCOUNT_IDS.income
            : SYSTEM_CONTROL_ACCOUNT_IDS.expense,
        writeOffCents: target.outstandingCents,
        date: todayStr,
        reason,
      });
      setDebts((prev) =>
        prev.map((d) =>
          d.id === debtId
            ? {
                ...d,
                status: 'written_off',
                outstandingCents: 0,
                writeOffEntryId: entryId,
              }
            : d
        )
      );
      setEntries((prev) => [res.entry, ...prev]);
      setPostings((prev) => [...res.postings, ...prev]);
      showToast('Debt written off with balanced adjustment entry.');
      setTimeout(notifyCanonicalSynced, 0);
    } catch (err) {
      showToast(err instanceof Error ? err.message : 'Cannot write off non-ETB or unverified debt.');
    }
  };

  const handleVoidDebtWriteOff = (debtId: string) => {
    const target = debts.find((d) => d.id === debtId);
    if (!target) return;
    try {
      const res = voidDebtWriteOffV7({
        debt: target,
        reason: 'Write-off voided by user',
        allocations,
        entries,
      });
      setDebts((prev) => prev.map((d) => (d.id === debtId ? res.updatedDebt : d)));
      setEntries(res.updatedEntries);
      showToast('Write-off voided and outstanding balance restored.');
      setTimeout(notifyCanonicalSynced, 0);
    } catch (err) {
      console.error(err);
    }
  };

  const handleVoidDebtOrigin = (debtId: string): { ok: boolean; error?: string } => {
    const target = debts.find((d) => d.id === debtId);
    if (!target) return { ok: false, error: 'Debt not found.' };
    try {
      const res = voidDebtOriginV7({
        debt: target,
        reason: 'Debt origin voided for re-issue',
        allocations,
        entries,
      });
      setDebts((prev) => prev.map((d) => (d.id === debtId ? res.updatedDebt : d)));
      setEntries(res.updatedEntries);
      showToast('Debt voided cleanly. You can re-issue via Composer.');
      setTimeout(notifyCanonicalSynced, 0);
      return { ok: true };
    } catch (err: unknown) {
      return { ok: false, error: err instanceof Error ? err.message : 'Cannot void debt.' };
    }
  };

  const handleAddSavingsGoal = (
    g: Omit<SharedSavingsGoal, 'id' | 'currentAllocatedCents' | 'status'>
  ): { ok: boolean; error?: string } => {
    try {
      const vaultId = g.linkedAccountId?.trim();
      if (vaultId) {
        assertEtbPostingAccounts({
          accounts,
          accountIds: [vaultId],
          roleLabels: ['Vault account'],
        });
        const vaultAcc = accounts.find((a) => a.id === vaultId);
        if (!vaultAcc || vaultAcc.subType !== 'savings_vault') {
          return {
            ok: false,
            error: 'Vault-linked savings goals must link to an active Verified ETB Savings Vault account.',
          };
        }
      }
      const rawGoal: SharedSavingsGoal = {
        ...g,
        linkedAccountId: vaultId || undefined,
        id: `sav-${Date.now()}-${Math.random().toString(36).slice(2, 5)}`,
        currentAllocatedCents: 0,
        status: 'active',
      };
      const [syncedGoal] = syncVaultSavingsGoalsV7({
        accounts,
        entries,
        postings,
        savingsGoals: [rawGoal],
      });
      setSavingsGoals((prev) => [syncedGoal, ...prev]);
      showToast(`Created savings goal "${g.title}".`);
      setTimeout(notifyCanonicalSynced, 0);
      return { ok: true };
    } catch (err: unknown) {
      return {
        ok: false,
        error: err instanceof Error ? err.message : 'Savings goal validation failed.',
      };
    }
  };

  const handleFundSavingsGoal = (payload: {
    goalId: string;
    amountCents: number;
    direction: 'deposit' | 'withdraw';
    sourceAccountId?: string;
    dateIso: string;
  }): { ok: boolean; error?: string } => {
    const target = savingsGoals.find((g) => g.id === payload.goalId);
    if (!target) return { ok: false, error: 'Savings goal not found.' };
    try {
      const res = fundSavingsGoalV7({
        goal: target,
        amountCents: payload.amountCents,
        direction: payload.direction,
        sourceAccountId: payload.sourceAccountId,
        dateIso: payload.dateIso,
        accounts,
        entries,
        postings,
      });
      const nextEntries = res.entry ? [res.entry, ...entries] : entries;
      const nextPostings = res.postings ? [...res.postings, ...postings] : postings;
      const nextGoals = syncVaultSavingsGoalsV7({
        accounts,
        entries: nextEntries,
        postings: nextPostings,
        savingsGoals: savingsGoals.map((g) => (g.id === target.id ? res.updatedGoal : g)),
      });
      setSavingsGoals(nextGoals);
      if (res.entry && res.postings) {
        setEntries(nextEntries);
        setPostings(nextPostings);
      }
      if (res.simpleTransaction) {
        setSimpleTransactions((prev) => [res.simpleTransaction!, ...prev]);
      }
      showToast(
        payload.direction === 'withdraw'
          ? `Withdrew from "${target.title}".`
          : `Funded "${target.title}".`
      );
      setTimeout(notifyCanonicalSynced, 0);
      return { ok: true };
    } catch (err: unknown) {
      return { ok: false, error: err instanceof Error ? err.message : 'Savings goal update failed.' };
    }
  };

  const handleReleaseAndArchiveGoal = (goalId: string) => {
    const target = savingsGoals.find((g) => g.id === goalId);
    setSavingsGoals((prev) =>
      prev.map((g) =>
        g.id === goalId
          ? {
              ...g,
              status: 'archived',
              currentAllocatedCents: g.linkedAccountId ? g.currentAllocatedCents : 0,
            }
          : g
      )
    );
    showToast(
      target?.linkedAccountId
        ? `Archived goal "${target.title}". Funds remain in the linked vault.`
        : 'Released virtual reserve back to Available to Spend and archived goal.'
    );
    setTimeout(notifyCanonicalSynced, 0);
  };

  const handleUpsertBudget = (payload: {
    categoryId: string;
    limitCents: number;
    rolloverEnabled: boolean;
  }) => {
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const monthIso = todayStr.slice(0, 7);
    setBudgets((prev) => {
      const existing = prev.find((b) => b.categoryId === payload.categoryId);
      if (existing) {
        return prev.map((b) =>
          b.categoryId === payload.categoryId
            ? {
                ...b,
                limitCents: payload.limitCents,
                rolloverEnabled: payload.rolloverEnabled,
                updatedAt: nowIso,
              }
            : b
        );
      }
      return [
        {
          id: `bud-${Date.now()}`,
          categoryId: payload.categoryId,
          monthIso,
          limitCents: payload.limitCents,
          rolloverEnabled: payload.rolloverEnabled,
          createdAt: nowIso,
          updatedAt: nowIso,
        },
        ...prev,
      ];
    });
    showToast('Saved monthly budget.');
    setTimeout(notifyCanonicalSynced, 0);
  };

  const handleAddRecurringRule = (
    r: Omit<SharedRecurringRule, 'id' | 'createdAt' | 'isActive'>
  ): { ok: boolean; error?: string } => {
    try {
      const accId = r.accountId?.trim();
      const destId = r.destinationAccountId?.trim();
      const linkedDebtId = r.linkedDebtId?.trim();

      if (r.ruleType !== 'commitment' && !accId) {
        return {
          ok: false,
          error: `Recurring ${r.ruleType} rule must specify an active Verified ETB account.`,
        };
      }
      if (r.ruleType === 'transfer') {
        if (!destId) {
          return {
            ok: false,
            error: 'Recurring transfer rule must specify a destination ETB account.',
          };
        }
        if (accId === destId) {
          return {
            ok: false,
            error: 'Recurring transfer source and destination accounts must be distinct.',
          };
        }
      }

      const idsToCheck = [accId, destId].filter((id): id is string => Boolean(id));
      if (idsToCheck.length > 0) {
        assertEtbPostingAccounts({
          accounts,
          accountIds: idsToCheck,
          roleLabels: idsToCheck.map((_, i) => (i === 0 ? 'Rule account' : 'Destination account')),
        });
      }
      if (linkedDebtId) {
        const targetDebt = debts.find((d) => d.id === linkedDebtId);
        if (!targetDebt) {
          return { ok: false, error: 'Referenced debt not found.' };
        }
        assertEtbDebtEligible({
          debt: targetDebt,
          entries,
          postings,
          accounts,
          allocations,
        });
      }

      const newRule: SharedRecurringRule = {
        ...r,
        accountId: accId || undefined,
        destinationAccountId: destId || undefined,
        linkedDebtId: linkedDebtId || undefined,
        id: `rec-${Date.now()}-${Math.random().toString(36).slice(2, 5)}`,
        isActive: true,
        autoPost: Boolean(r.autoPost),
        createdAt: EthiopiaClock.nowUtc().toISOString(),
      };
      setRecurringRules((prev) => [newRule, ...prev]);
      showToast(`Created recurring rule "${r.title}".`);
      setTimeout(notifyCanonicalSynced, 0);
      return { ok: true };
    } catch (err: unknown) {
      return {
        ok: false,
        error: err instanceof Error ? err.message : 'Recurring rule must target active Verified ETB accounts.',
      };
    }
  };

  const handleToggleRecurringActive = (ruleId: string) => {
    setRecurringRules((prev) =>
      prev.map((r) => (r.id === ruleId ? { ...r, isActive: !r.isActive } : r))
    );
    setTimeout(notifyCanonicalSynced, 0);
  };

  const handleToggleRecurringAutoPost = (ruleId: string) => {
    const rule = recurringRules.find((r) => r.id === ruleId);
    if (rule && !rule.autoPost) {
      const accountById = new Map(accounts.map((a) => [a.id, a]));
      const src = rule.accountId ? accountById.get(rule.accountId) : undefined;
      const dst = rule.destinationAccountId ? accountById.get(rule.destinationAccountId) : undefined;
      if (
        (rule.ruleType !== 'commitment' && (!src || !isActiveVerifiedEtbAccount(src))) ||
        (rule.ruleType === 'transfer' && (!dst || !isActiveVerifiedEtbAccount(dst))) ||
        (rule.accountId && (!src || !isActiveVerifiedEtbAccount(src)))
      ) {
        showToast('Cannot enable auto-post for non-ETB, unverified, or archived accounts.');
        return;
      }
    }
    setRecurringRules((prev) =>
      prev.map((r) => (r.id === ruleId ? { ...r, autoPost: !r.autoPost } : r))
    );
    setTimeout(notifyCanonicalSynced, 0);
  };

  const handleSkipNextRecurring = (ruleId: string) => {
    setRecurringRules((prev) =>
      prev.map((r) => (r.id === ruleId ? skipNextRecurringOccurrenceV7(r) : r))
    );
    showToast('Skipped next recurring occurrence.');
    setTimeout(notifyCanonicalSynced, 0);
  };

  const handleProcessDueRules = (): number => {
    const res = processDueRecurringRulesV7({
      rules: recurringRules,
      todayIso: todayStr,
      accounts,
      debts,
      entries,
      postings,
      allocations,
    });
    const count = res.createdEntries.length + res.createdCommitments.length;
    setRecurringRules(res.updatedRules);
    if (res.createdEntries.length > 0) {
      const nextEntries = [...res.createdEntries, ...entries];
      const nextPostings = [...res.createdPostings, ...postings];
      setEntries(nextEntries);
      setPostings(nextPostings);
      setSavingsGoals((prev) =>
        syncVaultSavingsGoalsV7({
          accounts,
          entries: nextEntries,
          postings: nextPostings,
          savingsGoals: prev,
        })
      );
    }
    if (res.createdCommitments.length > 0) {
      setCommitments((prev) => [...res.createdCommitments, ...prev]);
    }
    if (res.createdSimpleTransactions.length > 0) {
      setSimpleTransactions((prev) => [...res.createdSimpleTransactions, ...prev]);
    }
    if (res.warnings.length > 0) {
      showToast(res.warnings[0]);
      setTimeout(notifyCanonicalSynced, 0);
    } else if (count > 0) {
      showToast(`Posted ${count} due recurring item(s).`);
      setTimeout(notifyCanonicalSynced, 0);
    } else {
      showToast('No auto-post rules due today.');
    }
    return count;
  };

  // -------------------------------------------------------------
  // RENDER: First-Time Finance Setup Wizard
  // -------------------------------------------------------------
  if (!isSetupCompleted) {
    return (
      <div className="space-y-4">
        <div className="bg-[var(--dw-primary-brand)] text-white p-6 rounded-[var(--dw-radius-lg)] shadow-xs">
          <div className="flex items-center gap-2 text-xs uppercase tracking-wider font-semibold text-white/90 mb-2">
            <Building2 className="w-4 h-4 text-white/90" />
            <span>Finance v7 Setup</span>
          </div>
          <h1 className="dw-type-heading text-white">Set Up Your Starting Balances</h1>
          <p className="text-xs text-white/85 mt-1 leading-relaxed">
            Configure the accounts you actually use and their opening balances. Opening balances are posted against Opening Equity (never counted as income).
          </p>
        </div>

        {setupError && <DaywellStatusBanner tone="error" message={setupError} />}

        {setupStep === 1 ? (
          <DaywellCard padding="lg" radius="lg" className="space-y-4 shadow-xs">
            <div className="flex items-center justify-between pb-2 border-b border-[var(--dw-divider)]">
              <span className="dw-type-label uppercase tracking-wider text-[var(--dw-text-muted)]">
                Select Active Accounts & Balances
              </span>
              <span className="text-xs text-[var(--dw-text-muted)]">Step 1 of 2</span>
            </div>

            <div className="space-y-3">
              {setupAccountsList.map((acc) => (
                <div
                  key={acc.id}
                  className={`p-3.5 rounded-[var(--dw-radius-md)] border transition-all ${
                    acc.isActive
                      ? 'border-[var(--dw-primary)]/40 bg-[var(--dw-canvas)]'
                      : 'border-[var(--dw-border)] opacity-60 bg-[var(--dw-surface-subtle)]'
                  }`}
                >
                  <div className="flex items-center justify-between mb-2">
                    <label className="flex items-center gap-2.5 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={acc.isActive}
                        onChange={() => handleToggleSetupAccount(acc.id)}
                        className="w-4 h-4 accent-[var(--dw-primary)] rounded border-[var(--dw-border)]"
                      />
                      <Building2 className="w-4 h-4 text-[var(--dw-primary)]" />
                      <span className="text-sm font-semibold text-[var(--dw-text-primary)]">
                        {acc.name}
                      </span>
                    </label>
                  </div>

                  {acc.isActive && (
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5 pt-1">
                      <div>
                        <label className="block text-[11px] font-medium text-[var(--dw-text-muted)] mb-1">
                          Starting Balance (ETB)
                        </label>
                        <input
                          type="text"
                          inputMode="decimal"
                          value={acc.balanceText}
                          onChange={(e) => handleUpdateSetupBalance(acc.id, e.target.value)}
                          placeholder="0.00"
                          className="w-full px-3 py-1.5 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-sm text-[var(--dw-text-primary)] tabular-nums"
                        />
                      </div>
                      <div>
                        <label className="block text-[11px] font-medium text-[var(--dw-text-muted)] mb-1">
                          Opening Balance Date
                        </label>
                        <div className="relative">
                          <input
                            type="date"
                            value={acc.openingDate}
                            onChange={(e) => handleUpdateSetupDate(acc.id, e.target.value)}
                            className="w-full px-3 py-1.5 pl-8 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-xs text-[var(--dw-text-primary)]"
                          />
                          <Calendar className="w-3.5 h-3.5 text-[var(--dw-text-muted)] absolute left-2.5 top-2" />
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              ))}
            </div>

            <div className="p-3 border border-dashed border-[var(--dw-border)] rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)]">
              <span className="block text-xs font-semibold text-[var(--dw-text-secondary)] mb-2">
                Add Another Account
              </span>
              <div className="flex flex-col sm:flex-row gap-2">
                <input
                  type="text"
                  value={setupCustomName}
                  onChange={(e) => setSetupCustomName(e.target.value)}
                  placeholder="Account Name"
                  className="flex-1 px-3 py-1.5 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] text-xs bg-[var(--dw-card)] text-[var(--dw-text-primary)]"
                />
                <input
                  type="text"
                  inputMode="decimal"
                  value={setupCustomBalance}
                  onChange={(e) => setSetupCustomBalance(e.target.value)}
                  placeholder="Initial Balance"
                  className="w-full sm:w-32 px-3 py-1.5 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] text-xs bg-[var(--dw-card)] text-[var(--dw-text-primary)] tabular-nums"
                />
                <DaywellButton
                  label="Add"
                  variant="secondary"
                  size="compact"
                  leadingIcon={<Plus className="w-3.5 h-3.5" />}
                  disabled={!setupCustomName.trim()}
                  onClick={handleAddSetupCustomAccount}
                />
              </div>
            </div>

            <DaywellButton
              label="Review Starting Balances"
              variant="primary"
              fullWidth
              trailingIcon={<ChevronRight className="w-4 h-4" />}
              disabled={!setupAccountsList.some((a) => a.isActive)}
              onClick={handleProceedSetupToReview}
            />
          </DaywellCard>
        ) : (
          <DaywellCard padding="lg" radius="lg" className="space-y-4 shadow-xs">
            <div className="flex items-center justify-between pb-2 border-b border-[var(--dw-divider)]">
              <span className="dw-type-label uppercase tracking-wider text-[var(--dw-text-muted)]">
                Review & Confirm Starting Position
              </span>
              <span className="text-xs text-[var(--dw-text-muted)]">Step 2 of 2</span>
            </div>

            <div className="p-4 bg-[var(--dw-primary-brand)] text-white rounded-[var(--dw-radius-md)] flex items-center justify-between">
              <div>
                <span className="text-[11px] uppercase tracking-wider text-white/85 block font-semibold">
                  Total Starting Capital
                </span>
                <span className="dw-type-heading text-white tabular-nums">
                  {formatBirr(
                    setupAccountsList
                      .filter((a) => a.isActive)
                      .reduce((sum, a) => {
                        const parsed = a.balanceText.trim()
                          ? parseDecimalToCentsStrict(a.balanceText)
                          : null;
                        return sum + (parsed && parsed.valid && parsed.cents > 0 ? parsed.cents : 0);
                      }, 0)
                  )}
                </span>
              </div>
              <Wallet className="w-8 h-8 text-white/40" />
            </div>

            <div className="divide-y divide-[var(--dw-divider)] border border-[var(--dw-border)] rounded-[var(--dw-radius-md)] overflow-hidden">
              {setupAccountsList
                .filter((a) => a.isActive)
                .map((acc) => {
                  const parsed = acc.balanceText.trim()
                    ? parseDecimalToCentsStrict(acc.balanceText)
                    : null;
                  const balCents = parsed && parsed.valid && parsed.cents > 0 ? parsed.cents : 0;
                  return (
                    <div key={acc.id} className="p-3 flex items-center justify-between text-sm">
                      <div>
                        <span className="font-semibold text-[var(--dw-text-primary)] block">
                          {acc.name}
                        </span>
                        <span className="text-xs text-[var(--dw-text-muted)]">
                          Opening Date: {acc.openingDate}
                        </span>
                      </div>
                      <span className="font-mono font-medium text-[var(--dw-text-primary)] tabular-nums">
                        {formatBirr(balCents)}
                      </span>
                    </div>
                  );
                })}
            </div>

            <div className="flex items-center gap-3 pt-2">
              <DaywellButton
                label="Back to Edit"
                variant="outlined"
                size="compact"
                onClick={() => setSetupStep(1)}
              />
              <DaywellButton
                label="Confirm & Launch Finance v7"
                variant="primary"
                size="compact"
                fullWidth
                leadingIcon={<CheckCircle2 className="w-4 h-4" />}
                onClick={handleCompleteSetup}
                className="flex-1"
              />
            </div>
          </DaywellCard>
        )}
      </div>
    );
  }

  // -------------------------------------------------------------
  // RENDER: Stage 4 v7 Finance Dashboard
  // -------------------------------------------------------------
  const tabDefs: Array<{ id: FinanceV7Tab; label: string }> = [
    { id: 'overview', label: 'Overview' },
    { id: 'transactions', label: 'Transactions' },
    { id: 'plan', label: 'Plan' },
    { id: 'reports', label: 'Reports' },
  ];

  return (
    <div className="space-y-4">
      {toastMsg && (
        <div
          role="status"
          aria-live="polite"
          className="fixed bottom-20 left-1/2 -translate-x-1/2 z-50 max-w-md w-[92%] bg-[var(--dw-elevated)] text-[var(--dw-text-primary)] px-4 py-2.5 rounded-[var(--dw-radius-lg)] shadow-xl flex items-center gap-2 border border-[var(--dw-primary)]/40 text-xs font-medium"
        >
          <RotateCcw className="w-3.5 h-3.5 text-[var(--dw-primary)] shrink-0" />
          <span>{toastMsg}</span>
        </div>
      )}

      {/* 4-Tab Bar */}
      <div
        role="tablist"
        aria-label="Finance sections"
        className="grid grid-cols-4 gap-1 p-1 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-lg)] border border-[var(--dw-border)]"
      >
        {tabDefs.map((tab) => {
          const active = activeTab === tab.id;
          return (
            <button
              key={tab.id}
              type="button"
              role="tab"
              aria-selected={active}
              onClick={() => setActiveTab(tab.id)}
              className={`py-2 px-2 rounded-[var(--dw-radius-md)] text-xs font-bold transition-all cursor-pointer ${
                active
                  ? 'bg-[var(--dw-primary-brand)] text-white shadow-xs'
                  : 'text-[var(--dw-text-secondary)] hover:bg-[var(--dw-card)]/60'
              }`}
            >
              {tab.label}
            </button>
          );
        })}
      </div>

      {activeTab === 'overview' && (
        <FinanceOverviewTab
          accounts={accounts}
          categories={categories}
          entries={entries}
          postings={postings}
          simpleTransactions={simpleTransactions}
          breakdown={breakdown}
          planningPeriodEnd={planningPeriodEnd}
          onChangePlanningPeriodEnd={(iso) => {
            setPlanningPeriodEnd(iso);
            setTimeout(notifyCanonicalSynced, 0);
          }}
          onOpenComposer={(kind) => openComposer(kind)}
          onSaveAccount={handleSaveAccount}
          onToggleArchiveAccount={handleToggleArchiveAccount}
          onDeleteAccount={handleDeleteAccount}
          onSaveCategory={handleSaveCategory}
          onToggleArchiveCategory={handleToggleArchiveCategory}
          onDeleteCategory={handleDeleteCategory}
          onNavigateTab={(tab) => setActiveTab(tab)}
          onRequestConfirm={requestConfirm}
          hasIntegrityNotices={!integrityReport.isHealthy}
        />
      )}

      {activeTab === 'transactions' && (
        <FinanceTransactionsTab
          entries={entries}
          postings={postings}
          accounts={accounts}
          categories={categories}
          debts={debts}
          allocations={allocations}
          onOpenComposer={openComposer}
          onVoidEntry={handleVoidEntry}
          onRestoreEntry={handleRestoreEntry}
          onRefundExpense={handleExpenseRefund}
          onRequestConfirm={requestConfirm}
        />
      )}

      {activeTab === 'plan' && (
        <FinancePlanTab
          accounts={accounts}
          categories={categories}
          parties={parties}
          entries={entries}
          postings={postings}
          debts={debts}
          allocations={allocations}
          commitments={commitments}
          commitmentSettlements={commitmentSettlements}
          savingsGoals={savingsGoals}
          budgets={budgets}
          recurringRules={recurringRules}
          availableLiquidCashCents={breakdown.liquidCashCents}
          onAddCommitment={handleAddCommitment}
          onLinkCommitmentAccount={handleLinkCommitmentAccount}
          onRecordCommitmentSettlement={handleRecordCommitmentSettlement}
          onVoidCommitmentSettlement={handleVoidCommitmentSettlement}
          onMarkLegacyUnpaid={handleMarkLegacyUnpaid}
          onOpenComposer={(kind) => openComposer(kind)}
          onSettleDebt={handleSettleDebt}
          onWriteOffDebt={handleWriteOffDebt}
          onVoidDebtWriteOff={handleVoidDebtWriteOff}
          onVoidDebtOrigin={handleVoidDebtOrigin}
          onAddSavingsGoal={handleAddSavingsGoal}
          onFundSavingsGoal={handleFundSavingsGoal}
          onReleaseAndArchiveGoal={handleReleaseAndArchiveGoal}
          onUpsertBudget={handleUpsertBudget}
          onAddRecurringRule={handleAddRecurringRule}
          onToggleRecurringActive={handleToggleRecurringActive}
          onToggleRecurringAutoPost={handleToggleRecurringAutoPost}
          onSkipNextRecurring={handleSkipNextRecurring}
          onProcessDueRules={handleProcessDueRules}
          onRequestConfirm={requestConfirm}
        />
      )}

      {activeTab === 'reports' && (
        <FinanceReportsTab
          accounts={accounts}
          categories={categories}
          entries={entries}
          postings={postings}
          debts={debts}
          allocations={allocations}
          commitments={commitments}
          breakdown={breakdown}
          integrityReport={integrityReport}
          onRefreshState={() => {
            reloadFromStorage();
            setTimeout(notifyCanonicalSynced, 0);
          }}
        />
      )}

      {/* Unified Double-Entry Composer Modal */}
      <FinanceComposerModal
        isOpen={composerOpen}
        prefill={activePrefill}
        accounts={accounts}
        categories={categories}
        parties={parties}
        onClose={() => {
          setComposerOpen(false);
          setActivePrefill(null);
        }}
        onCreateParty={handleCreateParty}
        onSubmit={handleComposerSubmit}
      />

      {/* Custom Confirm Dialog (Zero window.confirm) */}
      <DaywellConfirmationDialog
        isOpen={Boolean(confirmState)}
        title={confirmState?.title || ''}
        description={confirmState?.message || ''}
        confirmLabel={confirmState?.confirmLabel || 'Confirm'}
        destructive={confirmState?.tone === 'danger'}
        onCancel={() => setConfirmState(null)}
        onConfirm={() => {
          const fn = confirmState?.onConfirm;
          setConfirmState(null);
          fn?.();
        }}
      />
    </div>
  );
}
