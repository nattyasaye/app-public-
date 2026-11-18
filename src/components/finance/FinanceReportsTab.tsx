import React, { useMemo, useState } from 'react';
import {
  ChevronLeft,
  ChevronRight,
  Download,
  ShieldCheck,
  AlertTriangle,
  Upload,
  CheckCircle2,
  FileSpreadsheet,
  Archive,
  Database,
} from 'lucide-react';
import {
  Account,
  AvailableToSpendBreakdownV7,
  buildAccountBalancesReportV7,
  buildAlignedBalanceSheetReportV7,
  buildMonthlyBudgetProgressReportV7,
  buildSavingsVaultsAndGoalsReportV7,
  calculateCanonicalCategorySpendV7,
  calculatePeriodComparisonReportV7,
  CategorySpendRowV7,
  Debt,
  FinanceV7IntegrityReport,
  formatCurrencyCents,
  JournalEntry,
  MetricDeltaV7,
  Party,
  Posting,
  ReportPeriodMode,
  resolveActiveReportMonthIsoV7,
  resolveReportPeriodWithComparisonV7,
  SettlementAllocation,
  SharedBudget,
  SharedCommitment,
  SharedCommitmentSettlement,
  SharedRecurringRule,
  SharedSavingsGoal,
  SimpleTransaction,
  TransactionCategory,
} from '../../domain/financeV7Engine';
import { CalendarDate, EthiopianDate } from '../../domain/date';
import { formatBirr } from '../../domain/financialEngine';
import { DataPortabilityService, ExportDataPayload } from '../../services/dataPortabilityService';
import { SharedStateBridge } from '../../services/sharedStateBridge';
import {
  DaywellButton,
  DaywellCard,
  DaywellIconButton,
  DaywellProgressBar,
  DaywellStatusBadge,
  DaywellStatusBanner,
} from '../ui';

interface FinanceReportsTabProps {
  accounts: Account[];
  categories: TransactionCategory[];
  parties?: Party[];
  entries: JournalEntry[];
  postings: Posting[];
  debts: Debt[];
  allocations?: SettlementAllocation[];
  commitments: SharedCommitment[];
  commitmentSettlements?: SharedCommitmentSettlement[];
  savingsGoals?: SharedSavingsGoal[];
  budgets?: SharedBudget[];
  recurringRules?: SharedRecurringRule[];
  simpleTransactions?: SimpleTransaction[];
  planningPeriodEndIso?: string;
  breakdown: AvailableToSpendBreakdownV7;
  integrityReport: FinanceV7IntegrityReport;
  onRefreshState: () => void;
}

function triggerDownload(filename: string, content: string, mimeType: string) {
  const blob = new Blob([content], { type: mimeType });
  DataPortabilityService.triggerDownload(blob, filename);
}

function formatDeltaBadgeText(delta: MetricDeltaV7): string {
  const sign = delta.deltaCents > 0 ? '+' : '';
  return `${sign}${formatBirr(delta.deltaCents)} (${delta.percentageDisplay})`;
}

function deltaToneClass(delta: MetricDeltaV7): string {
  if (delta.isPositiveOutcome === true) return 'text-[var(--dw-on-income-container)]';
  if (delta.isPositiveOutcome === false) return 'text-[var(--dw-on-expense-container)]';
  return 'text-[var(--dw-text-muted)]';
}

function CategoryHierarchyRow({
  row,
  depth = 0,
}: {
  row: CategorySpendRowV7;
  depth?: number;
}) {
  return (
    <div className={depth > 0 ? 'pl-4 border-l border-[var(--dw-border)] space-y-1.5' : 'space-y-1.5'}>
      <div className="space-y-1 text-xs">
        <div className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-1.5 min-w-0">
            <span
              className={`${
                depth === 0 ? 'font-semibold' : 'font-medium'
              } text-[var(--dw-text-primary)] truncate`}
            >
              {row.categoryName}
            </span>
            {row.isArchived && (
              <DaywellStatusBadge tone="neutral" showIcon={false} label="Archived" />
            )}
            {row.children.length > 0 && (
              <span className="text-[11px] text-[var(--dw-text-muted)] whitespace-nowrap">
                (incl. {row.children.length} sub)
              </span>
            )}
          </div>
          <span className="font-mono tabular-nums text-[var(--dw-text-secondary)] shrink-0">
            {formatBirr(row.rollupCents)} ({row.sharePercent}%)
          </span>
        </div>
        <DaywellProgressBar
          value={row.sharePercent}
          label={`${row.categoryName} spend share`}
        />
      </div>
      {row.children.length > 0 && (
        <div className="space-y-1.5 pt-0.5">
          {row.children.map((child) => (
            <CategoryHierarchyRow key={child.categoryId} row={child} depth={depth + 1} />
          ))}
        </div>
      )}
    </div>
  );
}

export function FinanceReportsTab({
  accounts,
  categories,
  parties = [],
  entries,
  postings,
  debts,
  allocations = [],
  commitments,
  commitmentSettlements = [],
  savingsGoals = [],
  budgets = [],
  recurringRules = [],
  simpleTransactions = [],
  planningPeriodEndIso,
  breakdown,
  integrityReport,
  onRefreshState,
}: FinanceReportsTabProps) {
  const todayIso = useMemo(() => CalendarDate.today().toIsoString(), []);
  const ethNow = useMemo(() => EthiopianDate.today(), []);
  const [mode, setMode] = useState<ReportPeriodMode>('thisMonth');
  const [ethYear, setEthYear] = useState(ethNow.year);
  const [ethMonth, setEthMonth] = useState(ethNow.month);
  const [customStart, setCustomStart] = useState(
    CalendarDate.today().subtractDays(29).toIsoString()
  );
  const [customEnd, setCustomEnd] = useState(CalendarDate.today().toIsoString());
  const [importStatus, setImportStatus] = useState<{ ok: boolean; text: string } | null>(
    null
  );
  const [exportBusy, setExportBusy] = useState(false);

  const period = useMemo(
    () =>
      resolveReportPeriodWithComparisonV7({
        mode,
        todayIso,
        ethYear,
        ethMonth,
        customStartIso: customStart,
        customEndIso: customEnd,
      }),
    [mode, todayIso, ethYear, ethMonth, customStart, customEnd]
  );

  const shiftEthMonth = (delta: number) => {
    let m = ethMonth + delta;
    let y = ethYear;
    while (m > 13) {
      m -= 13;
      y += 1;
    }
    while (m < 1) {
      m += 13;
      y -= 1;
    }
    setEthYear(y);
    setEthMonth(m);
  };

  const comparisonReport = useMemo(
    () =>
      calculatePeriodComparisonReportV7({
        period,
        accounts,
        categories,
        entries,
        postings,
        debts,
        allocations,
      }),
    [period, accounts, categories, entries, postings, debts, allocations]
  );

  const canonicalCategorySpend = useMemo(
    () =>
      calculateCanonicalCategorySpendV7({
        entries,
        postings,
        accounts,
        categories,
        debts,
        allocations,
        startDate: period.currentStart,
        endDate: period.currentEnd,
      }),
    [entries, postings, accounts, categories, debts, allocations, period]
  );

  const accountBalancesReport = useMemo(
    () =>
      buildAccountBalancesReportV7({
        accounts,
        entries,
        postings,
      }),
    [accounts, entries, postings]
  );

  const savingsVaultsReport = useMemo(
    () =>
      buildSavingsVaultsAndGoalsReportV7({
        accounts,
        entries,
        postings,
        savingsGoals,
      }),
    [accounts, entries, postings, savingsGoals]
  );

  const activeBudgetMonthIso = useMemo(
    () =>
      resolveActiveReportMonthIsoV7({
        mode,
        startDateIso: period.currentStart,
        endDateIso: period.currentEnd,
        todayIso,
      }),
    [mode, period, todayIso]
  );

  const monthlyBudgetProgress = useMemo(
    () =>
      buildMonthlyBudgetProgressReportV7({
        budgets,
        categories,
        entries,
        postings,
        accounts,
        debts,
        allocations,
        monthIso: activeBudgetMonthIso,
      }),
    [budgets, categories, entries, postings, accounts, debts, allocations, activeBudgetMonthIso]
  );

  const alignedBalanceSheet = useMemo(
    () =>
      buildAlignedBalanceSheetReportV7({
        accounts,
        entries,
        postings,
        debts,
        allocations,
        breakdown,
      }),
    [accounts, entries, postings, debts, allocations, breakdown]
  );

  const exportPayload: ExportDataPayload = useMemo(
    () => ({
      accounts,
      parties,
      entries,
      postings,
      debts,
      settlementAllocations: allocations,
      categories,
      reservedSavingsCents: breakdown.virtualSavingsReservedCents,
      commitments,
      commitmentSettlements,
      recurringRules,
      savingsGoals,
      budgets,
      transactions: simpleTransactions,
      planningPeriodEndIso: planningPeriodEndIso || alignedBalanceSheet.planningPeriodEndIso,
    }),
    [
      accounts,
      parties,
      entries,
      postings,
      debts,
      allocations,
      categories,
      breakdown.virtualSavingsReservedCents,
      commitments,
      commitmentSettlements,
      recurringRules,
      savingsGoals,
      budgets,
      simpleTransactions,
      planningPeriodEndIso,
      alignedBalanceSheet.planningPeriodEndIso,
    ]
  );

  const dateStamp = todayIso;

  const handleDownloadCsv = (filename: string, csvContent: string) => {
    triggerDownload(filename, csvContent, 'text/csv;charset=utf-8');
  };

  const handleExportSqliteSql = () => {
    const sql = DataPortabilityService.generateSqliteAnalyticalScript(exportPayload);
    triggerDownload(
      `daywell_finance_export_${dateStamp}.sql`,
      sql,
      'application/sql;charset=utf-8'
    );
  };

  const handleExportExcel = () => {
    DataPortabilityService.downloadSingleExcelFile({
      ...exportPayload,
      journalEntries: entries,
    });
  };

  const handleExportZip = async () => {
    setExportBusy(true);
    try {
      await DataPortabilityService.downloadFullPackage({
        ...exportPayload,
        journalEntries: entries,
      });
    } finally {
      setExportBusy(false);
    }
  };

  const handleExportFinanceOnlyJson = () => {
    const json = SharedStateBridge.exportFinanceOnlyJson();
    triggerDownload(
      `daywell_finance_only_${dateStamp}.json`,
      json,
      'application/json'
    );
  };

  const handleImportFinanceOnlyFile = async (
    e: React.ChangeEvent<HTMLInputElement>
  ) => {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      const text = await file.text();
      const res = SharedStateBridge.importFinanceOnlyJson(text);
      if (res.success) {
        setImportStatus({
          ok: true,
          text: 'Finance-only snapshot restored cleanly. Tasks, Notes, Projects, Calendar, Reminders, and Inbox were preserved untouched.',
        });
        onRefreshState();
      } else {
        setImportStatus({
          ok: false,
          text: `Finance restore rejected (existing data preserved): ${res.error || 'Import failed.'}`,
        });
      }
    } catch (err: any) {
      setImportStatus({
        ok: false,
        text: err?.message || 'Could not read Finance JSON file.',
      });
    }
    e.target.value = '';
  };

  const csvExports = [
    {
      label: 'Accounts CSV',
      filename: `daywell_accounts_${dateStamp}.csv`,
      build: () => DataPortabilityService.exportAccountsCsv(accounts),
    },
    {
      label: 'Categories CSV',
      filename: `daywell_categories_${dateStamp}.csv`,
      build: () => DataPortabilityService.exportCategoriesCsv(categories),
    },
    {
      label: 'Parties CSV',
      filename: `daywell_parties_${dateStamp}.csv`,
      build: () => DataPortabilityService.exportPartiesCsv(parties),
    },
    {
      label: 'Journal Entries CSV',
      filename: `daywell_journal_entries_${dateStamp}.csv`,
      build: () =>
        DataPortabilityService.exportJournalEntriesCsv({
          accounts,
          entries,
          postings,
          debts,
          allocations,
        }),
    },
    {
      label: 'Postings CSV',
      filename: `daywell_postings_${dateStamp}.csv`,
      build: () => DataPortabilityService.exportPostingsCsv(postings),
    },
    {
      label: 'Debts CSV',
      filename: `daywell_debts_${dateStamp}.csv`,
      build: () =>
        DataPortabilityService.exportDebtsCsv({
          accounts,
          entries,
          postings,
          debts,
          allocations,
        }),
    },
    {
      label: 'Settlement Allocations CSV',
      filename: `daywell_settlement_allocations_${dateStamp}.csv`,
      build: () => DataPortabilityService.exportSettlementAllocationsCsv(allocations),
    },
    {
      label: 'Commitments CSV',
      filename: `daywell_commitments_${dateStamp}.csv`,
      build: () => DataPortabilityService.exportCommitmentsCsv(commitments),
    },
    {
      label: 'Commitment Settlements CSV',
      filename: `daywell_commitment_settlements_${dateStamp}.csv`,
      build: () =>
        DataPortabilityService.exportCommitmentSettlementsCsv(commitmentSettlements),
    },
    {
      label: 'Savings Goals CSV',
      filename: `daywell_savings_goals_${dateStamp}.csv`,
      build: () => DataPortabilityService.exportSavingsGoalsCsv(savingsGoals),
    },
    {
      label: 'Budgets CSV',
      filename: `daywell_budgets_${dateStamp}.csv`,
      build: () => DataPortabilityService.exportBudgetsCsv(budgets),
    },
    {
      label: 'Recurring Rules CSV',
      filename: `daywell_recurring_rules_${dateStamp}.csv`,
      build: () => DataPortabilityService.exportRecurringRulesCsv(recurringRules),
    },
    {
      label: 'Transactions CSV',
      filename: `daywell_transactions_${dateStamp}.csv`,
      build: () => DataPortabilityService.exportTransactionsCsv(simpleTransactions),
    },
  ];

  const {
    currentCashFlow: cashFlowReport,
    currentOccurrence: occurrenceReport,
  } = comparisonReport;

  return (
    <div className="space-y-6">
      {/* 1. Dual-Calendar Report Period Selector */}
      <DaywellCard padding="md" radius="lg" className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div>
            <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
              Report Period
            </h3>
            <p className="text-xs text-[var(--dw-text-muted)]">
              {period.label} · vs. {period.baselineLabel}
            </p>
          </div>
          <span className="text-xs font-mono tabular-nums text-[var(--dw-text-muted)]">
            {period.currentStart} – {period.currentEnd}
          </span>
        </div>
        <div className="flex flex-wrap gap-1.5">
          {(
            [
              ['thisMonth', 'This Month'],
              ['last30Days', 'Last 30 Days'],
              ['thisYear', 'This Year'],
              ['ethiopianMonth', 'Ethiopian Month'],
              ['custom', 'Custom'],
            ] as const
          ).map(([id, label]) => (
            <button
              key={id}
              type="button"
              onClick={() => setMode(id)}
              className={`px-3 py-1.5 text-xs font-semibold rounded-[var(--dw-radius-sm)] whitespace-nowrap shrink-0 cursor-pointer transition-colors ${
                mode === id
                  ? 'bg-[var(--dw-primary)] text-[var(--dw-on-primary)]'
                  : 'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-secondary)] hover:text-[var(--dw-text-primary)]'
              }`}
            >
              {label}
            </button>
          ))}
        </div>

        {mode === 'ethiopianMonth' && (
          <div className="flex items-center gap-2 pt-1 text-xs">
            <DaywellIconButton
              label="Previous Ethiopian month"
              size="compact"
              onClick={() => shiftEthMonth(-1)}
              icon={<ChevronLeft className="w-4 h-4" />}
            />
            <span className="font-semibold text-[var(--dw-text-primary)]">
              {period.label}
            </span>
            <DaywellIconButton
              label="Next Ethiopian month"
              size="compact"
              onClick={() => shiftEthMonth(1)}
              icon={<ChevronRight className="w-4 h-4" />}
            />
          </div>
        )}

        {mode === 'custom' && (
          <div className="flex flex-wrap items-center gap-2 text-xs pt-1">
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

      {/* 2. Cash Flow & Occurrence P&L with Preceding-Period Deltas */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <DaywellCard padding="lg" radius="lg" className="space-y-3">
          <div>
            <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
              Cash Flow (Liquid ETB Movement)
            </h3>
            <p className="text-[11px] text-[var(--dw-text-muted)]">
              vs. {period.baselineLabel}
            </p>
          </div>
          <div className="flex items-start justify-between gap-2 text-xs">
            <span className="text-[var(--dw-text-secondary)]">Cash Inflow</span>
            <div className="text-right">
              <div className="font-mono tabular-nums font-semibold text-[var(--dw-on-income-container)]">
                +{formatBirr(cashFlowReport.totalCashInflowCents)}
              </div>
              <div
                className={`text-[11px] font-mono tabular-nums ${deltaToneClass(
                  comparisonReport.cashInflow
                )}`}
              >
                {formatDeltaBadgeText(comparisonReport.cashInflow)}
              </div>
            </div>
          </div>
          <div className="flex items-start justify-between gap-2 text-xs">
            <span className="text-[var(--dw-text-secondary)]">Cash Outflow</span>
            <div className="text-right">
              <div className="font-mono tabular-nums font-semibold text-[var(--dw-on-expense-container)]">
                -{formatBirr(cashFlowReport.totalCashOutflowCents)}
              </div>
              <div
                className={`text-[11px] font-mono tabular-nums ${deltaToneClass(
                  comparisonReport.cashOutflow
                )}`}
              >
                {formatDeltaBadgeText(comparisonReport.cashOutflow)}
              </div>
            </div>
          </div>
          <div className="pt-2 border-t border-[var(--dw-divider)] flex items-start justify-between gap-2 text-sm font-bold text-[var(--dw-text-primary)]">
            <span>Net Cash Flow</span>
            <div className="text-right">
              <div className="font-mono tabular-nums">
                {formatBirr(cashFlowReport.netCashFlowCents)}
              </div>
              <div
                className={`text-[11px] font-normal font-mono tabular-nums ${deltaToneClass(
                  comparisonReport.cashNet
                )}`}
              >
                {formatDeltaBadgeText(comparisonReport.cashNet)}
              </div>
            </div>
          </div>
        </DaywellCard>

        <DaywellCard padding="lg" radius="lg" className="space-y-3">
          <div>
            <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
              Occurrence P&amp;L (Economic Date)
            </h3>
            <p className="text-[11px] text-[var(--dw-text-muted)]">
              vs. {period.baselineLabel}
            </p>
          </div>
          <div className="flex items-start justify-between gap-2 text-xs">
            <span className="text-[var(--dw-text-secondary)]">Earned Income</span>
            <div className="text-right">
              <div className="font-mono tabular-nums font-semibold text-[var(--dw-on-income-container)]">
                +{formatBirr(occurrenceReport.totalIncomeCents)}
              </div>
              <div
                className={`text-[11px] font-mono tabular-nums ${deltaToneClass(
                  comparisonReport.occurrenceIncome
                )}`}
              >
                {formatDeltaBadgeText(comparisonReport.occurrenceIncome)}
              </div>
            </div>
          </div>
          <div className="flex items-start justify-between gap-2 text-xs">
            <span className="text-[var(--dw-text-secondary)]">Incurred Expense</span>
            <div className="text-right">
              <div className="font-mono tabular-nums font-semibold text-[var(--dw-on-expense-container)]">
                -{formatBirr(occurrenceReport.totalExpenseCents)}
              </div>
              <div
                className={`text-[11px] font-mono tabular-nums ${deltaToneClass(
                  comparisonReport.occurrenceExpense
                )}`}
              >
                {formatDeltaBadgeText(comparisonReport.occurrenceExpense)}
              </div>
            </div>
          </div>
          <div className="pt-2 border-t border-[var(--dw-divider)] flex items-start justify-between gap-2 text-sm font-bold text-[var(--dw-text-primary)]">
            <span>Net Savings</span>
            <div className="text-right">
              <div className="font-mono tabular-nums">
                {formatBirr(occurrenceReport.netSavingsCents)}
              </div>
              <div
                className={`text-[11px] font-normal font-mono tabular-nums ${deltaToneClass(
                  comparisonReport.occurrenceNet
                )}`}
              >
                {formatDeltaBadgeText(comparisonReport.occurrenceNet)}
              </div>
            </div>
          </div>
        </DaywellCard>
      </div>

      {/* 3. Aligned Balance Sheet Snapshot */}
      <DaywellCard padding="lg" radius="lg" className="space-y-2.5 text-xs">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
            Balance Sheet Snapshot (ETB)
          </h3>
          <span className="text-[11px] font-mono tabular-nums text-[var(--dw-text-muted)]">
            Horizon ≤ {alignedBalanceSheet.planningPeriodEndIso}
          </span>
        </div>
        <div className="flex justify-between">
          <span className="text-[var(--dw-text-secondary)]">
            Liquid Cash (Bank / Cash / Mobile Money)
          </span>
          <span className="font-mono tabular-nums font-semibold">
            {formatBirr(alignedBalanceSheet.liquidCashCents)}
          </span>
        </div>
        <div className="flex justify-between">
          <span className="text-[var(--dw-text-secondary)]">
            Dedicated Savings Vaults
          </span>
          <span className="font-mono tabular-nums font-semibold">
            {formatBirr(alignedBalanceSheet.vaultSavingsCents)}
          </span>
        </div>
        {alignedBalanceSheet.prepaidCardCreditCents > 0 && (
          <div className="flex justify-between text-[var(--dw-on-income-container)]">
            <span>+ Prepaid Card Credit (Included)</span>
            <span className="font-mono tabular-nums font-semibold">
              {formatBirr(alignedBalanceSheet.prepaidCardCreditCents)}
            </span>
          </div>
        )}
        <div className="flex justify-between">
          <span className="text-[var(--dw-text-secondary)]">Active Receivables</span>
          <span className="font-mono tabular-nums font-semibold">
            {formatBirr(alignedBalanceSheet.receivablesCents)}
          </span>
        </div>
        <div className="flex justify-between text-[var(--dw-on-expense-container)]">
          <span>- Short-Term Credit Card Owed</span>
          <span className="font-mono tabular-nums font-semibold">
            {formatBirr(-alignedBalanceSheet.shortTermCreditOwedCents)}
          </span>
        </div>
        <div className="flex justify-between text-[var(--dw-on-expense-container)]">
          <span>- Active Payables (Total Liabilities)</span>
          <span className="font-mono tabular-nums font-semibold">
            {formatBirr(-alignedBalanceSheet.activePayablesCents)}
          </span>
        </div>
        <div className="flex justify-between text-[11px] text-[var(--dw-text-muted)] pl-3">
          <span>Due in Horizon (≤ {alignedBalanceSheet.planningPeriodEndIso})</span>
          <span className="font-mono tabular-nums">
            {formatBirr(alignedBalanceSheet.duePayablesCents)}
          </span>
        </div>
        <div className="pt-2 border-t border-[var(--dw-divider)] flex justify-between text-sm font-bold text-[var(--dw-text-primary)]">
          <span>Net Financial Position</span>
          <span className="font-mono tabular-nums">
            {formatBirr(alignedBalanceSheet.netFinancialPositionCents)}
          </span>
        </div>
      </DaywellCard>

      {/* 4. Account Balances & Savings Vaults/Goals */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <DaywellCard padding="lg" radius="lg" className="space-y-3 text-xs">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
              Account Balances (Verified ETB)
            </h3>
            <div className="flex flex-wrap items-center gap-1.5">
              {accountBalancesReport.nonEtbReviewAccounts.length > 0 && (
                <DaywellStatusBadge
                  tone="warning"
                  showIcon={false}
                  label={`${accountBalancesReport.nonEtbReviewAccounts.length} Non-ETB / Review`}
                />
              )}
              {accountBalancesReport.archivedCount > 0 && (
                <DaywellStatusBadge
                  tone="neutral"
                  showIcon={false}
                  label={`${accountBalancesReport.archivedCount} Archived`}
                />
              )}
            </div>
          </div>

          {accountBalancesReport.liquidAccounts.length === 0 &&
          accountBalancesReport.vaultAccounts.length === 0 &&
          accountBalancesReport.creditCardAccounts.length === 0 ? (
            <p className="text-[var(--dw-text-muted)]">
              No active Verified ETB accounts configured.
            </p>
          ) : (
            <div className="space-y-3">
              {accountBalancesReport.liquidAccounts.length > 0 && (
                <div className="space-y-1.5">
                  <div className="flex justify-between text-[11px] font-semibold text-[var(--dw-text-muted)]">
                    <span>Liquid Accounts</span>
                    <span className="font-mono tabular-nums">
                      {formatBirr(accountBalancesReport.liquidTotalCents)}
                    </span>
                  </div>
                  {accountBalancesReport.liquidAccounts.map((acc) => (
                    <div key={acc.accountId} className="flex justify-between">
                      <span className="text-[var(--dw-text-secondary)]">
                        {acc.name} ({acc.subType.replace(/_/g, ' ')})
                      </span>
                      <span className="font-mono tabular-nums font-semibold text-[var(--dw-text-primary)]">
                        {formatBirr(acc.balanceCents)}
                      </span>
                    </div>
                  ))}
                </div>
              )}

              {accountBalancesReport.vaultAccounts.length > 0 && (
                <div className="space-y-1.5 pt-2 border-t border-[var(--dw-divider)]">
                  <div className="flex justify-between text-[11px] font-semibold text-[var(--dw-text-muted)]">
                    <span>Savings Vaults</span>
                    <span className="font-mono tabular-nums">
                      {formatBirr(accountBalancesReport.vaultTotalCents)}
                    </span>
                  </div>
                  {accountBalancesReport.vaultAccounts.map((acc) => (
                    <div key={acc.accountId} className="flex justify-between">
                      <span className="text-[var(--dw-text-secondary)]">{acc.name}</span>
                      <span className="font-mono tabular-nums font-semibold text-[var(--dw-text-primary)]">
                        {formatBirr(acc.balanceCents)}
                      </span>
                    </div>
                  ))}
                </div>
              )}

              {accountBalancesReport.creditCardAccounts.length > 0 && (
                <div className="space-y-1.5 pt-2 border-t border-[var(--dw-divider)]">
                  <div className="flex justify-between text-[11px] font-semibold text-[var(--dw-text-muted)]">
                    <span>Credit Cards</span>
                    <span className="font-mono tabular-nums">
                      Owed {formatBirr(accountBalancesReport.creditCardOwedTotalCents)}
                    </span>
                  </div>
                  {accountBalancesReport.creditCardAccounts.map((acc) => (
                    <div key={acc.accountId} className="flex justify-between">
                      <span className="text-[var(--dw-text-secondary)]">{acc.name}</span>
                      <span
                        className={`font-mono tabular-nums font-semibold ${
                          acc.owedCents > 0
                            ? 'text-[var(--dw-on-expense-container)]'
                            : 'text-[var(--dw-on-income-container)]'
                        }`}
                      >
                        {acc.prepaidCents > 0
                          ? `Prepaid +${formatBirr(acc.prepaidCents)}`
                          : `Owed ${formatBirr(acc.owedCents)}`}
                      </span>
                    </div>
                  ))}
                </div>
              )}

              {accountBalancesReport.nonEtbReviewAccounts.length > 0 && (
                <div className="pt-2 border-t border-[var(--dw-divider)] space-y-1">
                  <div className="text-[11px] font-semibold text-[var(--dw-on-warning-container)]">
                    Read-Only Non-ETB / Currency Review Accounts (Excluded)
                  </div>
                  {accountBalancesReport.nonEtbReviewAccounts.map((acc) => (
                    <div
                      key={acc.accountId}
                      className="flex justify-between text-[var(--dw-text-muted)]"
                    >
                      <span>
                        {acc.name} ({acc.currencyCode})
                      </span>
                      <span className="font-mono tabular-nums">
                        {formatCurrencyCents(acc.balanceCents, acc.currencyCode)}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </DaywellCard>

        <DaywellCard padding="lg" radius="lg" className="space-y-3 text-xs">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div>
              <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
                Savings Vaults &amp; Goals
              </h3>
              <p className="text-[11px] text-[var(--dw-text-muted)]">
                Live vault ledger totals and allocated goal targets
              </p>
            </div>
            <span className="font-mono tabular-nums font-semibold text-[var(--dw-text-primary)]">
              Vaults: {formatBirr(savingsVaultsReport.totalVaultBalanceCents)}
            </span>
          </div>

          {savingsVaultsReport.goals.length === 0 ? (
            <p className="text-[var(--dw-text-muted)]">
              No savings goals configured yet.
            </p>
          ) : (
            <div className="space-y-2.5">
              {savingsVaultsReport.goals.map((goal) => (
                <div key={goal.goalId} className="space-y-1">
                  <div className="flex flex-wrap items-center justify-between gap-1.5">
                    <div className="flex flex-wrap items-center gap-1.5">
                      <span className="font-semibold text-[var(--dw-text-primary)]">
                        {goal.title}
                      </span>
                      <DaywellStatusBadge
                        tone={
                          goal.isExcludedNonEtbVault
                            ? 'warning'
                            : goal.status === 'completed'
                              ? 'success'
                              : 'neutral'
                        }
                        showIcon={false}
                        label={
                          goal.isExcludedNonEtbVault
                            ? 'Excluded'
                            : goal.status
                        }
                      />
                    </div>
                    <span className="font-mono tabular-nums text-[var(--dw-text-secondary)]">
                      {formatBirr(goal.allocatedCents)} / {formatBirr(goal.targetCents)} (
                      {goal.percentComplete}%)
                    </span>
                  </div>
                  <DaywellProgressBar
                    value={goal.percentComplete}
                    label={`${goal.title} savings progress`}
                  />
                  <div className="flex justify-between text-[11px] text-[var(--dw-text-muted)]">
                    <span>
                      {goal.isVaultLinked
                        ? `Vault: ${goal.linkedAccountName || 'Unknown'}`
                        : 'Virtual Earmark'}
                    </span>
                    <span className="font-mono tabular-nums">
                      Remaining {formatBirr(goal.remainingCents)}
                    </span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </DaywellCard>
      </div>

      {/* 5. Monthly Budget Progress & Canonical Category Spend Hierarchy */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <DaywellCard padding="lg" radius="lg" className="space-y-3 text-xs">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div>
              <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
                Monthly Budget Progress ({monthlyBudgetProgress.monthIso})
              </h3>
              <p className="text-[11px] text-[var(--dw-text-muted)]">
                Subcategory expenses roll up into parent category budgets
              </p>
            </div>
            {monthlyBudgetProgress.items.length > 0 && (
              <span className="font-mono tabular-nums font-semibold text-[var(--dw-text-secondary)]">
                {formatBirr(monthlyBudgetProgress.totalSpentCents)} /{' '}
                {formatBirr(monthlyBudgetProgress.totalLimitCents)}
              </span>
            )}
          </div>

          {monthlyBudgetProgress.items.length === 0 ? (
            <p className="text-[var(--dw-text-muted)]">
              No monthly budgets set for {monthlyBudgetProgress.monthIso}.
            </p>
          ) : (
            <div className="space-y-2.5">
              {monthlyBudgetProgress.items.map((b) => (
                <div key={b.budgetId} className="space-y-1">
                  <div className="flex justify-between gap-2">
                    <span className="font-semibold text-[var(--dw-text-primary)]">
                      {b.categoryName}
                    </span>
                    <span
                      className={`font-mono tabular-nums ${
                        b.isOverBudget
                          ? 'text-[var(--dw-on-expense-container)] font-semibold'
                          : 'text-[var(--dw-text-secondary)]'
                      }`}
                    >
                      {formatBirr(b.spentCents)} / {formatBirr(b.limitCents)} ({b.percentUsed}%)
                    </span>
                  </div>
                  <DaywellProgressBar
                    value={b.percentUsed}
                    tone={b.isOverBudget ? 'error' : 'primary'}
                    label={`${b.categoryName} monthly budget usage`}
                  />
                </div>
              ))}
            </div>
          )}
        </DaywellCard>

        <DaywellCard padding="lg" radius="lg" className="space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div>
              <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
                Category Spend Breakdown
              </h3>
              <p className="text-[11px] text-[var(--dw-text-muted)]">
                Canonical aliases resolved · Subcategories roll up without double counting
              </p>
            </div>
            <span className="text-xs font-mono tabular-nums font-semibold text-[var(--dw-text-primary)]">
              Total {formatBirr(canonicalCategorySpend.totalExpenseCents)}
            </span>
          </div>
          {canonicalCategorySpend.rows.length === 0 ? (
            <p className="text-xs text-[var(--dw-text-muted)]">
              No categorized expenses recorded in this period.
            </p>
          ) : (
            <div className="space-y-3">
              {canonicalCategorySpend.rows.map((row) => (
                <CategoryHierarchyRow key={row.categoryId} row={row} />
              ))}
            </div>
          )}
        </DaywellCard>
      </div>

      {/* 6. Ledger Integrity & v7 Audit */}
      <DaywellCard padding="lg" radius="lg" className="space-y-3 text-xs">
        <div className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            {integrityReport.isHealthy ? (
              <ShieldCheck className="w-4 h-4 text-[var(--dw-on-success-container)]" />
            ) : (
              <AlertTriangle className="w-4 h-4 text-[var(--dw-error)]" />
            )}
            <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
              Ledger Integrity &amp; v7 Audit
            </h3>
          </div>
          <DaywellStatusBadge
            tone={integrityReport.isHealthy ? 'success' : 'error'}
            showIcon={false}
            label={
              integrityReport.isHealthy
                ? 'Healthy · Tier A Reconciled'
                : 'Discrepancy Detected'
            }
          />
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-1">
          <div className="p-3 rounded-[var(--dw-radius-md)] bg-[var(--dw-canvas)] border border-[var(--dw-border)]">
            <div className="text-[var(--dw-text-muted)]">
              Receivable Control vs Active Debts
            </div>
            <div className="font-mono tabular-nums font-semibold mt-0.5 text-[var(--dw-text-primary)]">
              {formatBirr(integrityReport.debtControlAudit.receivableControlBalanceCents)} vs{' '}
              {formatBirr(integrityReport.debtControlAudit.activeReceivableSumCents)}
            </div>
          </div>
          <div className="p-3 rounded-[var(--dw-radius-md)] bg-[var(--dw-canvas)] border border-[var(--dw-border)]">
            <div className="text-[var(--dw-text-muted)]">
              Payable Control vs Active Debts
            </div>
            <div className="font-mono tabular-nums font-semibold mt-0.5 text-[var(--dw-text-primary)]">
              {formatBirr(integrityReport.debtControlAudit.payableControlBalanceCents)} vs{' '}
              {formatBirr(integrityReport.debtControlAudit.activePayableSumCents)}
            </div>
          </div>
        </div>

        <div className="text-[var(--dw-text-secondary)]">
          Journal Entries Audited:{' '}
          <span className="font-mono tabular-nums">
            {integrityReport.totalEntriesCount}
          </span>{' '}
          · Unbalanced:{' '}
          <span className="font-mono tabular-nums">
            {integrityReport.unbalancedEntriesCount}
          </span>
        </div>

        <div className="p-3 rounded-[var(--dw-radius-md)] bg-[var(--dw-canvas)] border border-[var(--dw-border)] space-y-1">
          <div className="font-semibold text-[var(--dw-text-primary)]">
            ETB Currency Isolation Summary
          </div>
          <div className="text-[var(--dw-text-secondary)]">
            Non-ETB accounts excluded:{' '}
            <span className="font-mono tabular-nums font-semibold">
              {breakdown.nonEtbAccountCount}
            </span>{' '}
            · Unverified accounts:{' '}
            <span className="font-mono tabular-nums font-semibold">
              {breakdown.unverifiedAccountCount || 0}
            </span>{' '}
            · Foreign entries excluded:{' '}
            <span className="font-mono tabular-nums font-semibold">
              {breakdown.excludedNonEtbEntryCount}
            </span>{' '}
            · Currency Review entries:{' '}
            <span className="font-mono tabular-nums font-semibold">
              {breakdown.currencyReviewEntryCount}
            </span>{' '}
            · Legacy paid unverified:{' '}
            <span className="font-mono tabular-nums font-semibold">
              {breakdown.unverifiedLegacyPaidCount}
            </span>
          </div>
        </div>

        {integrityReport.warnings.map((w, i) => (
          <div key={i} className="text-[var(--dw-on-warning-container)]">
            · {w}
          </div>
        ))}
        {integrityReport.errors.map((err, i) => (
          <div key={i} className="text-[var(--dw-on-error-container)]">
            · {err}
          </div>
        ))}
      </DaywellCard>

      {/* 7. Organized Reports Export & Finance-Only Restore Hub */}
      <DaywellCard padding="lg" radius="lg" className="space-y-4">
        <div className="space-y-1">
          <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
            Reports Export &amp; Finance-Only Portability Hub
          </h3>
          <p className="text-xs text-[var(--dw-text-muted)]">
            Finance-only JSON export and restore operate strictly on Finance records and preserve Tasks, Notes, Projects, Calendar events, Reminders, and Inbox items untouched. Full cross-module device backups live in Settings.
          </p>
        </div>

        {/* Finance-Only JSON Portability */}
        <div className="p-3 rounded-[var(--dw-radius-md)] bg-[var(--dw-canvas)] border border-[var(--dw-border)] space-y-2.5">
          <div className="text-xs font-semibold text-[var(--dw-text-primary)]">
            Finance-Only Portability (JSON)
          </div>
          <div className="flex flex-wrap gap-2">
            <DaywellButton
              label="Export Finance-Only JSON"
              variant="primary"
              size="compact"
              leadingIcon={<Download className="w-3.5 h-3.5" />}
              onClick={handleExportFinanceOnlyJson}
            />
            <label className="inline-flex items-center justify-center gap-2 min-h-[36px] px-3 py-1.5 text-xs font-semibold rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] text-[var(--dw-primary)] hover:bg-[var(--dw-surface-subtle)] cursor-pointer transition-colors">
              <Upload className="w-3.5 h-3.5" />
              Restore Finance-Only JSON
              <input
                type="file"
                accept=".json,application/json"
                onChange={handleImportFinanceOnlyFile}
                className="hidden"
              />
            </label>
          </div>
        </div>

        {/* Packaged Analytical Exports */}
        <div className="space-y-2">
          <div className="text-xs font-semibold text-[var(--dw-text-primary)]">
            Spreadsheet &amp; Analytical Bundles
          </div>
          <div className="flex flex-wrap gap-2">
            <DaywellButton
              label={exportBusy ? 'Building ZIP Bundle...' : 'Complete ZIP Bundle (SHA-256)'}
              variant="secondary"
              size="compact"
              disabled={exportBusy}
              leadingIcon={<Archive className="w-3.5 h-3.5" />}
              onClick={handleExportZip}
            />
            <DaywellButton
              label="Excel Workbook (.xlsx)"
              variant="outlined"
              size="compact"
              leadingIcon={<FileSpreadsheet className="w-3.5 h-3.5" />}
              onClick={handleExportExcel}
            />
            <DaywellButton
              label="Analytical SQLite (.sql)"
              variant="outlined"
              size="compact"
              leadingIcon={<Database className="w-3.5 h-3.5" />}
              onClick={handleExportSqliteSql}
            />
          </div>
        </div>

        {/* Complete 13-Table UTF-8 BOM CSV Suite */}
        <div className="space-y-2">
          <div className="text-xs font-semibold text-[var(--dw-text-primary)]">
            Individual Finance CSV Tables (UTF-8 BOM)
          </div>
          <div className="flex flex-wrap gap-1.5">
            {csvExports.map((item) => (
              <DaywellButton
                key={item.label}
                label={item.label}
                variant="outlined"
                size="compact"
                leadingIcon={<Download className="w-3 h-3" />}
                onClick={() => handleDownloadCsv(item.filename, item.build())}
              />
            ))}
          </div>
        </div>

        {importStatus && (
          <DaywellStatusBanner
            tone={importStatus.ok ? 'success' : 'error'}
            icon={importStatus.ok ? <CheckCircle2 className="w-4 h-4 shrink-0" /> : undefined}
            message={importStatus.text}
          />
        )}
      </DaywellCard>
    </div>
  );
}
