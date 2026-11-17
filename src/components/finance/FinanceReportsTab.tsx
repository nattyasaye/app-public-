import React, { useMemo, useState } from 'react';
import {
  ChevronLeft,
  ChevronRight,
  Download,
  ShieldCheck,
  AlertTriangle,
  Upload,
  CheckCircle2,
} from 'lucide-react';
import {
  Account,
  AvailableToSpendBreakdownV7,
  classifyAllJournalEntries,
  Debt,
  FinanceV7IntegrityReport,
  generateCashFlowReport,
  generateOccurrenceReport,
  JournalEntry,
  Posting,
  resolveCommitmentCurrencyStatus,
  SettlementAllocation,
  SharedCommitment,
  TransactionCategory,
} from '../../domain/financeV7Engine';
import { CalendarDate, EthiopianDate } from '../../domain/date';
import { formatBirr } from '../../domain/financialEngine';
import { SharedStateBridge } from '../../services/sharedStateBridge';
import {
  DaywellButton,
  DaywellCard,
  DaywellIconButton,
  DaywellProgressBar,
  DaywellStatusBadge,
  DaywellStatusBanner,
} from '../ui';

type PeriodMode = 'thisMonth' | 'last30Days' | 'thisYear' | 'ethiopianMonth' | 'custom';

interface FinanceReportsTabProps {
  accounts: Account[];
  categories: TransactionCategory[];
  entries: JournalEntry[];
  postings: Posting[];
  debts: Debt[];
  allocations?: SettlementAllocation[];
  commitments: SharedCommitment[];
  breakdown: AvailableToSpendBreakdownV7;
  integrityReport: FinanceV7IntegrityReport;
  onRefreshState: () => void;
}

function triggerDownload(filename: string, content: string, mimeType: string) {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

function escapeCsv(val: unknown): string {
  const s = val == null ? '' : String(val);
  if (s.includes(',') || s.includes('"') || s.includes('\n')) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

export function FinanceReportsTab({
  accounts,
  categories,
  entries,
  postings,
  debts,
  allocations = [],
  commitments,
  breakdown,
  integrityReport,
  onRefreshState,
}: FinanceReportsTabProps) {
  const ethNow = useMemo(() => EthiopianDate.today(), []);
  const [mode, setMode] = useState<PeriodMode>('thisMonth');
  const [ethYear, setEthYear] = useState(ethNow.year);
  const [ethMonth, setEthMonth] = useState(ethNow.month);
  const [customStart, setCustomStart] = useState(CalendarDate.today().addDays(-30).toIsoString());
  const [customEnd, setCustomEnd] = useState(CalendarDate.today().toIsoString());
  const [importStatus, setImportStatus] = useState<{ ok: boolean; text: string } | null>(null);

  const range = useMemo(() => {
    const today = CalendarDate.today();
    if (mode === 'thisMonth') {
      return {
        start: today.startOfGregorianMonth.toIsoString(),
        end: today.endOfGregorianMonth.toIsoString(),
        label: `${today.gregorianFullMonthName} ${today.year}`,
      };
    }
    if (mode === 'last30Days') {
      const start = today.subtractDays(29);
      return {
        start: start.toIsoString(),
        end: today.toIsoString(),
        label: `Last 30 Days (${start.toIsoString()} - ${today.toIsoString()})`,
      };
    }
    if (mode === 'thisYear') {
      return {
        start: `${today.year}-01-01`,
        end: `${today.year}-12-31`,
        label: `Gregorian Year ${today.year}`,
      };
    }
    if (mode === 'ethiopianMonth') {
      const ethStart = new EthiopianDate(ethYear, ethMonth, 1);
      const ethEnd = ethStart.endOfMonth;
      return {
        start: ethStart.toCalendarDate().toIsoString(),
        end: ethEnd.toCalendarDate().toIsoString(),
        label: `${ethStart.englishMonthName} (${ethStart.amharicMonthName}) ${ethYear} E.C.`,
      };
    }
    return {
      start: customStart,
      end: customEnd,
      label: `${customStart} to ${customEnd}`,
    };
  }, [mode, ethYear, ethMonth, customStart, customEnd]);

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

  const cashFlowReport = useMemo(
    () =>
      generateCashFlowReport({
        entries,
        postings,
        accounts,
        debts,
        allocations,
        startDate: range.start,
        endDate: range.end,
      }),
    [entries, postings, accounts, debts, allocations, range]
  );

  const occurrenceReport = useMemo(
    () =>
      generateOccurrenceReport({
        entries,
        postings,
        accounts,
        categories,
        debts,
        allocations,
        startDate: range.start,
        endDate: range.end,
      }),
    [entries, postings, accounts, categories, debts, allocations, range]
  );

  const categorySpendRows = useMemo(() => {
    const expCatNames = new Set(
      categories.filter((c) => c.type === 'expense').map((c) => c.name)
    );
    const list = Object.entries(occurrenceReport.categoryBreakdown)
      .filter(([name, amt]) => amt > 0 && (expCatNames.has(name) || name === 'Expense Control'))
      .sort((a, b) => b[1] - a[1]);
    const total = list.reduce((s, [, v]) => s + v, 0);
    return { list, total };
  }, [occurrenceReport, categories]);

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

  const handleExportCommitmentsCsv = () => {
    const accountById = new Map(accounts.map((a) => [a.id, a]));
    const entryById = new Map(entries.map((e) => [e.id, e]));
    const debtById = new Map(debts.map((d) => [d.id, d]));
    const header = [
      'id',
      'title',
      'direction',
      'currency',
      'reportingStatus',
      'amountCents',
      'dueDate',
      'isPaid',
      'linkedAccountId',
      'categoryId',
      'legacyPaidUnverified',
    ].join(',');
    const rows = commitments.map((c) => {
      const res = resolveCommitmentCurrencyStatus({
        commitment: c,
        accountById,
        debtById,
        entryById,
        classificationsByEntryId,
      });
      return [
        c.id,
        c.title,
        c.direction || 'outflow',
        res.currencyCode || 'UNVERIFIED',
        res.status.toUpperCase(),
        c.amountCents,
        c.dueDate,
        c.isPaid,
        c.linkedAccountId || '',
        c.categoryId || '',
        Boolean(c.legacyPaidUnverified),
      ]
        .map(escapeCsv)
        .join(',');
    });
    triggerDownload(
      `daywell_commitments_${CalendarDate.today().toIsoString()}.csv`,
      '\uFEFF' + [header, ...rows].join('\n'),
      'text/csv;charset=utf-8'
    );
  };

  const handleExportEntriesCsv = () => {
    const header = [
      'id',
      'entryType',
      'description',
      'occurrenceDate',
      'currency',
      'reportingStatus',
      'isVoided',
    ].join(',');
    const rows = entries.map((e) => {
      const cls = classificationsByEntryId.get(e.id);
      const curLabel =
        cls?.nativeCurrencyCode ||
        (cls && cls.touchedCurrencies.length > 0 ? cls.touchedCurrencies.join('/') : 'UNVERIFIED');
      return [
        e.id,
        e.entryType,
        e.description,
        e.occurrenceDate,
        curLabel,
        (cls?.status || 'mixed_or_ambiguous').toUpperCase(),
        e.isVoided,
      ]
        .map(escapeCsv)
        .join(',');
    });
    triggerDownload(
      `daywell_journal_entries_${CalendarDate.today().toIsoString()}.csv`,
      '\uFEFF' + [header, ...rows].join('\n'),
      'text/csv;charset=utf-8'
    );
  };

  const handleExportCanonicalJson = () => {
    const json = SharedStateBridge.exportToAndroidJson();
    triggerDownload(
      `daywell_canonical_v7_${CalendarDate.today().toIsoString()}.json`,
      json,
      'application/json'
    );
  };

  const handleImportJsonFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      const text = await file.text();
      const res = SharedStateBridge.importFromAndroidJson(text);
      if (res.success) {
        setImportStatus({ ok: true, text: 'Canonical database restored cleanly.' });
        onRefreshState();
      } else {
        setImportStatus({
          ok: false,
          text: `Import rejected (existing data preserved): ${res.error || 'Import failed.'}`,
        });
      }
    } catch (err: any) {
      setImportStatus({ ok: false, text: err?.message || 'Could not read backup file.' });
    }
    e.target.value = '';
  };

  return (
    <div className="space-y-6">
      {/* 1. Period Picker (including Ethiopian 13-month + Pagume) */}
      <DaywellCard padding="md" radius="lg" className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">Report Period</h3>
          <span className="text-xs text-[var(--dw-text-muted)]">{range.label}</span>
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
            <span className="font-semibold text-[var(--dw-text-primary)]">{range.label}</span>
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

      {/* 2. Dual Cashflow & Occurrence P&L */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <DaywellCard padding="lg" radius="lg" className="space-y-2.5">
          <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
            Cash Flow (Physical Cash Movement)
          </h3>
          <div className="flex justify-between text-xs">
            <span className="text-[var(--dw-text-secondary)]">Cash Inflow</span>
            <span className="font-mono tabular-nums font-semibold text-[var(--dw-on-income-container)]">
              +{formatBirr(cashFlowReport.totalCashInflowCents)}
            </span>
          </div>
          <div className="flex justify-between text-xs">
            <span className="text-[var(--dw-text-secondary)]">Cash Outflow</span>
            <span className="font-mono tabular-nums font-semibold text-[var(--dw-on-expense-container)]">
              -{formatBirr(cashFlowReport.totalCashOutflowCents)}
            </span>
          </div>
          <div className="pt-2 border-t border-[var(--dw-divider)] flex justify-between text-sm font-bold text-[var(--dw-text-primary)]">
            <span>Net Cash Flow</span>
            <span className="font-mono tabular-nums">
              {formatBirr(cashFlowReport.netCashFlowCents)}
            </span>
          </div>
        </DaywellCard>

        <DaywellCard padding="lg" radius="lg" className="space-y-2.5">
          <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
            Occurrence P&amp;L (Economic Date)
          </h3>
          <div className="flex justify-between text-xs">
            <span className="text-[var(--dw-text-secondary)]">Earned Income</span>
            <span className="font-mono tabular-nums font-semibold text-[var(--dw-on-income-container)]">
              +{formatBirr(occurrenceReport.totalIncomeCents)}
            </span>
          </div>
          <div className="flex justify-between text-xs">
            <span className="text-[var(--dw-text-secondary)]">Incurred Expense</span>
            <span className="font-mono tabular-nums font-semibold text-[var(--dw-on-expense-container)]">
              -{formatBirr(occurrenceReport.totalExpenseCents)}
            </span>
          </div>
          <div className="pt-2 border-t border-[var(--dw-divider)] flex justify-between text-sm font-bold text-[var(--dw-text-primary)]">
            <span>Net Savings</span>
            <span className="font-mono tabular-nums">
              {formatBirr(occurrenceReport.netSavingsCents)}
            </span>
          </div>
        </DaywellCard>
      </div>

      {/* 3. Balance Sheet w/ Prepaid Card Credit */}
      <DaywellCard padding="lg" radius="lg" className="space-y-2.5 text-xs">
        <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
          Balance Sheet Snapshot (ETB)
        </h3>
        <div className="flex justify-between">
          <span className="text-[var(--dw-text-secondary)]">Liquid Cash (Bank / Cash / Mobile Money)</span>
          <span className="font-mono tabular-nums font-semibold">{formatBirr(breakdown.liquidCashCents)}</span>
        </div>
        <div className="flex justify-between">
          <span className="text-[var(--dw-text-secondary)]">Dedicated Savings Vaults</span>
          <span className="font-mono tabular-nums font-semibold">{formatBirr(breakdown.vaultSavingsCents)}</span>
        </div>
        {breakdown.prepaidCardCreditCents > 0 && (
          <div className="flex justify-between text-[var(--dw-on-income-container)]">
            <span>+ Prepaid Card Credit (Included)</span>
            <span className="font-mono tabular-nums font-semibold">
              {formatBirr(breakdown.prepaidCardCreditCents)}
            </span>
          </div>
        )}
        <div className="flex justify-between">
          <span className="text-[var(--dw-text-secondary)]">Receivables</span>
          <span className="font-mono tabular-nums font-semibold">{formatBirr(breakdown.receivablesCents)}</span>
        </div>
        <div className="flex justify-between text-[var(--dw-on-expense-container)]">
          <span>- Short-Term Credit Card Owed</span>
          <span className="font-mono tabular-nums font-semibold">
            {formatBirr(-breakdown.shortTermCreditOwedCents)}
          </span>
        </div>
        <div className="flex justify-between text-[var(--dw-on-expense-container)]">
          <span>- Active Payables Due (≤ H)</span>
          <span className="font-mono tabular-nums font-semibold">
            {formatBirr(-breakdown.duePayablesCents)}
          </span>
        </div>
        <div className="pt-2 border-t border-[var(--dw-divider)] flex justify-between text-sm font-bold text-[var(--dw-text-primary)]">
          <span>Net Financial Position</span>
          <span className="font-mono tabular-nums">{formatBirr(breakdown.netFinancialPositionCents)}</span>
        </div>
      </DaywellCard>

      {/* 4. Category Spend Breakdown */}
      <DaywellCard padding="lg" radius="lg" className="space-y-3">
        <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
          Category Spend Breakdown
        </h3>
        {categorySpendRows.list.length === 0 ? (
          <p className="text-xs text-[var(--dw-text-muted)]">
            No categorized expenses recorded in this period.
          </p>
        ) : (
          <div className="space-y-2.5">
            {categorySpendRows.list.map(([name, cents]) => {
              const pct =
                categorySpendRows.total > 0
                  ? Math.round((cents / categorySpendRows.total) * 100)
                  : 0;
              return (
                <div key={name} className="space-y-1 text-xs">
                  <div className="flex justify-between">
                    <span className="font-medium text-[var(--dw-text-primary)]">{name}</span>
                    <span className="font-mono tabular-nums text-[var(--dw-text-secondary)]">
                      {formatBirr(cents)} ({pct}%)
                    </span>
                  </div>
                  <DaywellProgressBar value={pct} label={`${name} spend share`} />
                </div>
              );
            })}
          </div>
        )}
      </DaywellCard>

      {/* 5. Ledger Integrity & v7 Audit */}
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
            label={integrityReport.isHealthy ? 'Healthy · Tier A Reconciled' : 'Discrepancy Detected'}
          />
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-1">
          <div className="p-3 rounded-[var(--dw-radius-md)] bg-[var(--dw-canvas)] border border-[var(--dw-border)]">
            <div className="text-[var(--dw-text-muted)]">Receivable Control vs Active Debts</div>
            <div className="font-mono tabular-nums font-semibold mt-0.5 text-[var(--dw-text-primary)]">
              {formatBirr(integrityReport.debtControlAudit.receivableControlBalanceCents)} vs{' '}
              {formatBirr(integrityReport.debtControlAudit.activeReceivableSumCents)}
            </div>
          </div>
          <div className="p-3 rounded-[var(--dw-radius-md)] bg-[var(--dw-canvas)] border border-[var(--dw-border)]">
            <div className="text-[var(--dw-text-muted)]">Payable Control vs Active Debts</div>
            <div className="font-mono tabular-nums font-semibold mt-0.5 text-[var(--dw-text-primary)]">
              {formatBirr(integrityReport.debtControlAudit.payableControlBalanceCents)} vs{' '}
              {formatBirr(integrityReport.debtControlAudit.activePayableSumCents)}
            </div>
          </div>
        </div>

        <div className="text-[var(--dw-text-secondary)]">
          Journal Entries Audited: <span className="font-mono tabular-nums">{integrityReport.totalEntriesCount}</span> · Unbalanced: <span className="font-mono tabular-nums">{integrityReport.unbalancedEntriesCount}</span>
        </div>

        <div className="p-3 rounded-[var(--dw-radius-md)] bg-[var(--dw-canvas)] border border-[var(--dw-border)] space-y-1">
          <div className="font-semibold text-[var(--dw-text-primary)]">
            ETB Currency Isolation Summary
          </div>
          <div className="text-[var(--dw-text-secondary)]">
            Non-ETB accounts excluded: <span className="font-mono tabular-nums font-semibold">{breakdown.nonEtbAccountCount}</span> · Unverified accounts: <span className="font-mono tabular-nums font-semibold">{breakdown.unverifiedAccountCount || 0}</span> · Foreign entries excluded: <span className="font-mono tabular-nums font-semibold">{breakdown.excludedNonEtbEntryCount}</span> · Currency Review entries: <span className="font-mono tabular-nums font-semibold">{breakdown.currencyReviewEntryCount}</span> · Legacy paid unverified: <span className="font-mono tabular-nums font-semibold">{breakdown.unverifiedLegacyPaidCount}</span>
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

      {/* 6. Export & Canonical Restore Hub */}
      <DaywellCard padding="lg" radius="lg" className="space-y-3">
        <h3 className="text-sm font-semibold text-[var(--dw-text-primary)]">
          Export &amp; Canonical Restore Hub
        </h3>
        <div className="flex flex-wrap gap-2">
          <DaywellButton
            label="Journal Entries CSV"
            variant="outlined"
            size="compact"
            leadingIcon={<Download className="w-3.5 h-3.5" />}
            onClick={handleExportEntriesCsv}
          />
          <DaywellButton
            label="Commitments CSV"
            variant="outlined"
            size="compact"
            leadingIcon={<Download className="w-3.5 h-3.5" />}
            onClick={handleExportCommitmentsCsv}
          />
          <DaywellButton
            label="Export Canonical JSON (v7)"
            variant="primary"
            size="compact"
            leadingIcon={<Download className="w-3.5 h-3.5" />}
            onClick={handleExportCanonicalJson}
          />
          <label className="inline-flex items-center justify-center gap-2 min-h-[36px] px-3 py-1.5 text-xs font-semibold rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] text-[var(--dw-primary)] hover:bg-[var(--dw-surface-subtle)] cursor-pointer transition-colors">
            <Upload className="w-3.5 h-3.5" />
            Restore Canonical JSON
            <input
              type="file"
              accept=".json,application/json"
              onChange={handleImportJsonFile}
              className="hidden"
            />
          </label>
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
