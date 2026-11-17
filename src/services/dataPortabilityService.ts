import JSZip from 'jszip';
import * as XLSX from 'xlsx';
import {
  Account,
  Party,
  JournalEntry,
  Posting,
  Debt,
  SettlementAllocation,
  TransactionCategory,
  calculateAccountBalance,
  calculateNetPosition,
  calculateTotalPayables,
  classifyAllJournalEntries,
  classifyCurrencyCode,
  isDebtEligibleEtb,
  isEtbCurrency,
  normalizeCurrencyCode,
} from '../domain/doubleEntryFinance';
import {
  SharedCommitment,
  SharedCommitmentSettlement,
  SharedRecurringRule,
  SharedSavingsGoal,
  calculateAvailableToSpendBreakdownV7,
  getAccountSubType,
} from '../domain/financeV7Engine';
import { CalendarDate, EthiopiaClock } from '../domain/date';

export interface ExportDataPayload {
  accounts: Account[];
  parties: Party[];
  entries: JournalEntry[];
  postings: Posting[];
  debts: Debt[];
  settlementAllocations: SettlementAllocation[];
  categories: TransactionCategory[];
  reservedSavingsCents: number;
  commitments?: SharedCommitment[];
  commitmentSettlements?: SharedCommitmentSettlement[];
  recurringRules?: SharedRecurringRule[];
  savingsGoals?: SharedSavingsGoal[];
  planningPeriodEndIso?: string;
}

// Simple SHA-256 calculation in browser/Node
async function computeSha256(content: string): Promise<string> {
  if (typeof crypto !== 'undefined' && crypto.subtle) {
    const encoder = new TextEncoder();
    const data = encoder.encode(content);
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map((b) => b.toString(16).padStart(2, '0')).join('');
  }
  // Fallback hash simulation if crypto.subtle is not present
  let hash = 0;
  for (let i = 0; i < content.length; i++) {
    hash = (hash << 5) - hash + content.charCodeAt(i);
    hash |= 0;
  }
  return `fallback-${Math.abs(hash).toString(16).padStart(16, '0')}`;
}

export class DataPortabilityService {
  public static triggerDownload(blob: Blob, filename: string): void {
    if (typeof window === 'undefined') return;
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }

  public static async downloadFullPackage(payload: {
    accounts: Account[];
    parties: Party[];
    journalEntries?: JournalEntry[];
    entries?: JournalEntry[];
    postings: Posting[];
    debts: Debt[];
    settlementAllocations: SettlementAllocation[];
    categories: TransactionCategory[];
    reservedSavingsCents?: number;
    commitments?: SharedCommitment[];
    commitmentSettlements?: SharedCommitmentSettlement[];
    recurringRules?: SharedRecurringRule[];
    savingsGoals?: SharedSavingsGoal[];
    planningPeriodEndIso?: string;
  }): Promise<void> {
    const normPayload: ExportDataPayload = {
      accounts: payload.accounts,
      parties: payload.parties,
      entries: payload.entries || payload.journalEntries || [],
      postings: payload.postings,
      debts: payload.debts,
      settlementAllocations: payload.settlementAllocations,
      categories: payload.categories,
      reservedSavingsCents: payload.reservedSavingsCents || 0,
      commitments: payload.commitments,
      commitmentSettlements: payload.commitmentSettlements,
      recurringRules: payload.recurringRules,
      savingsGoals: payload.savingsGoals,
      planningPeriodEndIso: payload.planningPeriodEndIso,
    };
    const { blob, fileName } = await this.createExportZipBundle(normPayload);
    this.triggerDownload(blob, fileName);
  }

  public static async downloadSingleExcelFile(payload: {
    accounts: Account[];
    parties: Party[];
    journalEntries?: JournalEntry[];
    entries?: JournalEntry[];
    postings: Posting[];
    debts: Debt[];
    settlementAllocations: SettlementAllocation[];
    categories: TransactionCategory[];
    reservedSavingsCents?: number;
    commitments?: SharedCommitment[];
    commitmentSettlements?: SharedCommitmentSettlement[];
    recurringRules?: SharedRecurringRule[];
    savingsGoals?: SharedSavingsGoal[];
    planningPeriodEndIso?: string;
  }): Promise<void> {
    const normPayload: ExportDataPayload = {
      accounts: payload.accounts,
      parties: payload.parties,
      entries: payload.entries || payload.journalEntries || [],
      postings: payload.postings,
      debts: payload.debts,
      settlementAllocations: payload.settlementAllocations,
      categories: payload.categories,
      reservedSavingsCents: payload.reservedSavingsCents || 0,
      commitments: payload.commitments,
      commitmentSettlements: payload.commitmentSettlements,
      recurringRules: payload.recurringRules,
      savingsGoals: payload.savingsGoals,
      planningPeriodEndIso: payload.planningPeriodEndIso,
    };
    const excelBytes = this.generateExcelWorkbook(normPayload);
    const blob = new Blob([excelBytes.buffer as ArrayBuffer], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
    const dateStamp = CalendarDate.today().toIsoString();
    this.triggerDownload(blob, `daywell_finance_${dateStamp}.xlsx`);
  }

  /**
   * Generates CSV string with UTF-8 BOM (\uFEFF) to guarantee Amharic Ge'ez script renders in Excel.
   */
  public static toCsvWithBom<T extends Record<string, any>>(
    data: T[],
    columns: (keyof T | { key: keyof T; header: string; transform?: (val: any, row: T) => string })[]
  ): string {
    const BOM = '\uFEFF';
    if (data.length === 0) return BOM;

    const headers = columns.map((col) =>
      typeof col === 'object' ? `"${col.header.replace(/"/g, '""')}"` : `"${String(col)}"`
    );

    const rows = data.map((row) =>
      columns
        .map((col) => {
          let val = typeof col === 'object' ? (col.transform ? col.transform(row[col.key], row) : row[col.key]) : row[col];
          if (val === null || val === undefined) val = '';
          const str = String(val).replace(/"/g, '""');
          return `"${str}"`;
        })
        .join(',')
    );

    return BOM + [headers.join(','), ...rows].join('\r\n');
  }

  /**
   * Generates the multi-sheet Excel Workbook (.xlsx)
   */
  public static generateExcelWorkbook(payload: ExportDataPayload): Uint8Array {
    const wb = XLSX.utils.book_new();

    // 1. Executive Summary Sheet (Verified ETB Only)
    const classifications = classifyAllJournalEntries({
      accounts: payload.accounts,
      entries: payload.entries,
      postings: payload.postings,
      debts: payload.debts,
      allocations: payload.settlementAllocations,
    });
    const effectiveHorizon =
      payload.planningPeriodEndIso ||
      CalendarDate.today().endOfGregorianMonth.toIsoString();
    const effectiveGoals: SharedSavingsGoal[] =
      payload.savingsGoals && payload.savingsGoals.length > 0
        ? payload.savingsGoals
        : payload.reservedSavingsCents > 0
        ? [
            {
              id: 'export-virtual-reserve',
              title: 'Reserved Savings',
              targetCents: payload.reservedSavingsCents,
              currentAllocatedCents: payload.reservedSavingsCents,
              status: 'active',
            },
          ]
        : [];
    const breakdown = calculateAvailableToSpendBreakdownV7({
      accounts: payload.accounts,
      postings: payload.postings,
      entries: payload.entries,
      debts: payload.debts,
      commitments: payload.commitments || [],
      savingsGoals: effectiveGoals,
      planningPeriodEndIso: effectiveHorizon,
      allocations: payload.settlementAllocations,
      recurringRules: payload.recurringRules || [],
      commitmentSettlements: payload.commitmentSettlements || [],
    });
    const liquidCash = breakdown.liquidCashCents;
    const netPosition = calculateNetPosition(
      payload.accounts,
      payload.postings,
      payload.debts,
      payload.entries,
      payload.settlementAllocations
    );
    const unpaidPayables = calculateTotalPayables(payload.debts, {
      accounts: payload.accounts,
      entries: payload.entries,
      postings: payload.postings,
      allocations: payload.settlementAllocations,
    });
    const availableToSpend = breakdown.availableToSpendCents;

    const summaryData = [
      ['DAYWELL PERSONAL FINANCE - EXECUTIVE SUMMARY'],
      ['Export Generated (UTC)', EthiopiaClock.nowUtc().toISOString()],
      ['Currency Standard', 'ETB (Ethiopian Birr) - Non-ETB & Unverified Records Excluded'],
      ['Accounting Model', 'Simplified Double-Entry Balanced Ledger (Sum Debits = Sum Credits)'],
      ['Safe Harbor Horizon (H)', effectiveHorizon],
      [''],
      ['Metric', 'Amount (ETB Cents)', 'Amount (Decimal ETB)', 'Basis / Formula'],
      ['Total Liquid Cash', liquidCash, (liquidCash / 100).toFixed(2), 'Sum of Verified ETB Liquid Asset Accounts'],
      ['+ Prepaid Card Credit (Option 1 Included)', breakdown.prepaidCardCreditCents, (breakdown.prepaidCardCreditCents / 100).toFixed(2), 'Verified ETB Credit Card Overpayments (Included in AvailableToSpend)'],
      ['- Short-Term Credit Card Owed', breakdown.shortTermCreditOwedCents, (breakdown.shortTermCreditOwedCents / 100).toFixed(2), 'Verified ETB Credit Card Liabilities Owed'],
      ['- Due ETB Payables (<= H)', breakdown.duePayablesCents, (breakdown.duePayablesCents / 100).toFixed(2), 'Verified ETB Debt Payables Due Within Horizon'],
      ['- Due ETB Outflow Commitments (<= H)', breakdown.dueNonDebtCommitmentsCents, (breakdown.dueNonDebtCommitmentsCents / 100).toFixed(2), 'Verified ETB Non-Debt Outflow Commitments Due Within Horizon'],
      ['- Virtual Savings Reserve', breakdown.virtualSavingsReservedCents, (breakdown.virtualSavingsReservedCents / 100).toFixed(2), 'Ring-fenced Virtual Savings Reserves'],
      ['Available-to-Spend (ETB Option 1)', availableToSpend, (availableToSpend / 100).toFixed(2), 'Liquid Cash + Prepaid Credit - Card Debt - Due Payables - Due Commitments - Virtual Reserves'],
      ['Dedicated Savings Vaults', breakdown.vaultSavingsCents, (breakdown.vaultSavingsCents / 100).toFixed(2), 'Protected Verified ETB Savings Vault Balances'],
      ['Active Receivables', breakdown.receivablesCents, (breakdown.receivablesCents / 100).toFixed(2), 'Verified ETB Receivables Owed to User'],
      ['Unpaid ETB Payables (Total)', unpaidPayables, (unpaidPayables / 100).toFixed(2), 'All Active Verified ETB Payables Owed'],
      ['Net Financial Position', netPosition, (netPosition / 100).toFixed(2), 'Verified ETB Assets - Verified ETB Liabilities'],
      ['Excluded Non-ETB / Unverified Accounts', breakdown.nonEtbAccountCount, '', `${breakdown.unverifiedAccountCount} unverified currency code(s)`],
      ['Excluded Foreign / Review Entries', breakdown.excludedNonEtbEntryCount + breakdown.currencyReviewEntryCount, '', `${breakdown.excludedNonEtbEntryCount} excluded foreign, ${breakdown.currencyReviewEntryCount} currency review`],
    ];
    const wsSummary = XLSX.utils.aoa_to_sheet(summaryData);
    XLSX.utils.book_append_sheet(wb, wsSummary, 'Executive_Summary');

    // 2. Accounts and Balances Sheet (Preserving Native Currencies & Reporting Status)
    const accountsData = [
      ['Account ID', 'Account Name', 'Type', 'Currency', 'Reporting Status', 'Archived', 'Balance (Cents)', 'Balance (Decimal Native)'],
      ...payload.accounts.map((a) => {
        const bal = calculateAccountBalance(a, payload.postings, undefined, payload.entries);
        const tier = classifyCurrencyCode(a.currencyCode);
        const statusLabel = a.isSystem
          ? 'SYSTEM'
          : tier === 'verified_etb'
          ? 'ELIGIBLE_ETB'
          : tier === 'verified_non_etb'
          ? `EXCLUDED_${normalizeCurrencyCode(a.currencyCode)}`
          : 'CURRENCY_REVIEW';
        return [
          a.id,
          a.name,
          a.type,
          normalizeCurrencyCode(a.currencyCode) || 'UNVERIFIED',
          statusLabel,
          a.isArchived ? 'TRUE' : 'FALSE',
          bal,
          (bal / 100).toFixed(2),
        ];
      }),
    ];
    const wsAccounts = XLSX.utils.aoa_to_sheet(accountsData);
    XLSX.utils.book_append_sheet(wb, wsAccounts, 'Accounts_and_Balances');

    // 3. Cash Flow Ledger (Verified ETB Liquid Asset Accounts Only)
    const accMap = new Map(payload.accounts.map((a) => [a.id, a]));
    const entryMap = new Map(payload.entries.map((e) => [e.id, e]));

    const cashFlowRows = [
      ['Movement Date', 'Account Name', 'Direction', 'Cash Inflow (ETB)', 'Cash Outflow (ETB)', 'Description', 'Entry ID', 'Posting ID'],
      ...payload.postings
        .filter((p) => {
          const entry = entryMap.get(p.entryId);
          if (!entry || entry.isVoided) return false;
          if (!(classifications.get(entry.id)?.isEligibleEtb ?? false)) return false;
          const acc = accMap.get(p.accountId);
          if (!acc) return false;
          const subType = getAccountSubType(acc);
          return (
            !acc.isSystem &&
            acc.type === 'asset' &&
            isEtbCurrency(acc.currencyCode) &&
            subType !== 'savings_vault' &&
            subType !== 'receivable' &&
            !acc.name.toLowerCase().includes('receivable')
          );
        })
        .map((p) => {
          const acc = accMap.get(p.accountId)!;
          const entry = entryMap.get(p.entryId);
          const inflow = p.direction === 'debit' ? (p.amountCents / 100).toFixed(2) : '0.00';
          const outflow = p.direction === 'credit' ? (p.amountCents / 100).toFixed(2) : '0.00';
          return [
            p.accountMovementDate,
            acc.name,
            p.direction.toUpperCase(),
            inflow,
            outflow,
            entry?.description || '',
            p.entryId,
            p.id,
          ];
        }),
    ];
    const wsCashFlow = XLSX.utils.aoa_to_sheet(cashFlowRows);
    XLSX.utils.book_append_sheet(wb, wsCashFlow, 'Cash_Flow_Ledger');

    // 4. Occurrence P&L Sheet (ETB Eligible Entries Only)
    const catMap = new Map(payload.categories.map((c) => [c.id, c.name]));
    const pnlRows = [
      ['Occurrence Date', 'Type', 'Category / Account', 'Income (ETB)', 'Expense (ETB)', 'Description', 'Entry ID'],
      ...payload.postings
        .filter((p) => {
          const entry = entryMap.get(p.entryId);
          if (!entry || entry.isVoided) return false;
          if (!(classifications.get(entry.id)?.isEligibleEtb ?? false)) return false;
          const acc = accMap.get(p.accountId);
          return acc && (acc.type === 'income' || acc.type === 'expense');
        })
        .map((p) => {
          const acc = accMap.get(p.accountId)!;
          const entry = entryMap.get(p.entryId);
          const categoryName = (p.categoryId && catMap.get(p.categoryId)) || acc.name;
          const isIncome = acc.type === 'income';
          return [
            entry?.occurrenceDate || p.accountMovementDate,
            acc.type.toUpperCase(),
            categoryName,
            isIncome ? (p.amountCents / 100).toFixed(2) : '0.00',
            !isIncome ? (p.amountCents / 100).toFixed(2) : '0.00',
            entry?.description || '',
            p.entryId,
          ];
        }),
    ];
    const wsPnl = XLSX.utils.aoa_to_sheet(pnlRows);
    XLSX.utils.book_append_sheet(wb, wsPnl, 'Occurrence_PnL');

    // 5. Debts and Receivables Sheet (Native Currency & Isolation Status)
    const partyMap = new Map(payload.parties.map((p) => [p.id, p]));
    const debtsRows = [
      ['Debt ID', 'Party Name', 'Debt Type', 'Currency', 'Reporting Status', 'Principal (Native)', 'Outstanding (Native)', 'Due Date', 'Status', 'Created At'],
      ...payload.debts.map((d) => {
        const party = partyMap.get(d.partyId);
        const originCls = classifications.get(d.originEntryId);
        const eligible = isDebtEligibleEtb(d, entryMap, classifications);
        const curLabel =
          originCls?.nativeCurrencyCode ||
          (originCls && originCls.touchedCurrencies.length === 1 && originCls.touchedCurrencies[0] !== 'UNVERIFIED'
            ? originCls.touchedCurrencies[0]
            : eligible
            ? 'ETB'
            : 'UNVERIFIED');
        const statusLabel = eligible
          ? 'ELIGIBLE_ETB'
          : originCls?.status === 'excluded_non_etb'
          ? `EXCLUDED_${curLabel}`
          : 'CURRENCY_REVIEW';
        return [
          d.id,
          party?.name || 'Unknown Party',
          d.debtType === 'receivable' ? 'RECEIVABLE (Owed to Me)' : 'PAYABLE (I Owe)',
          curLabel,
          statusLabel,
          (d.principalCents / 100).toFixed(2),
          (d.outstandingCents / 100).toFixed(2),
          d.dueDate || 'None',
          d.status.toUpperCase(),
          d.createdAt,
        ];
      }),
    ];
    const wsDebts = XLSX.utils.aoa_to_sheet(debtsRows);
    XLSX.utils.book_append_sheet(wb, wsDebts, 'Debts_and_Receivables');

    return XLSX.write(wb, { bookType: 'xlsx', type: 'array' });
  }

  /**
   * Generates analytical SQLite SQL script that reconstructs the database,
   * creates all foreign keys, populates records, and creates analytical views.
   */
  public static generateSqliteAnalyticalScript(payload: ExportDataPayload): string {
    const lines: string[] = [
      '--',
      '-- Daywell Personal Finance - Standalone SQLite Analytical Schema & Export',
      `-- Generated UTC: ${EthiopiaClock.nowUtc().toISOString()}`,
      '--',
      'PRAGMA foreign_keys = ON;',
      '',
      'CREATE TABLE IF NOT EXISTS accounts (',
      '    id TEXT PRIMARY KEY,',
      '    name TEXT NOT NULL,',
      '    type TEXT NOT NULL CHECK(type IN (\'asset\', \'liability\', \'equity\', \'income\', \'expense\')),',
      '    sub_type TEXT NOT NULL DEFAULT \'bank\',',
      '    is_system INTEGER NOT NULL DEFAULT 0,',
      '    currency_code TEXT NOT NULL DEFAULT \'\',',
      '    is_archived INTEGER NOT NULL DEFAULT 0,',
      '    created_at TEXT NOT NULL',
      ');',
      '',
      'CREATE TABLE IF NOT EXISTS parties (',
      '    id TEXT PRIMARY KEY,',
      '    name TEXT NOT NULL,',
      '    phone TEXT,',
      '    notes TEXT,',
      '    is_archived INTEGER NOT NULL DEFAULT 0,',
      '    created_at TEXT NOT NULL',
      ');',
      '',
      'CREATE TABLE IF NOT EXISTS journal_entries (',
      '    id TEXT PRIMARY KEY,',
      '    entry_type TEXT NOT NULL,',
      '    description TEXT NOT NULL,',
      '    occurrence_date TEXT NOT NULL,',
      '    is_voided INTEGER NOT NULL DEFAULT 0,',
      '    void_reason TEXT,',
      '    created_at TEXT NOT NULL',
      ');',
      '',
      'CREATE TABLE IF NOT EXISTS postings (',
      '    id TEXT PRIMARY KEY,',
      '    entry_id TEXT NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,',
      '    account_id TEXT NOT NULL REFERENCES accounts(id),',
      '    amount_cents INTEGER NOT NULL CHECK(amount_cents > 0),',
      '    direction TEXT NOT NULL CHECK(direction IN (\'debit\', \'credit\')),',
      '    account_movement_date TEXT NOT NULL,',
      '    category_id TEXT,',
      '    note TEXT',
      ');',
      '',
      'CREATE TABLE IF NOT EXISTS debts (',
      '    id TEXT PRIMARY KEY,',
      '    origin_entry_id TEXT NOT NULL REFERENCES journal_entries(id),',
      '    party_id TEXT NOT NULL REFERENCES parties(id),',
      '    debt_type TEXT NOT NULL CHECK(debt_type IN (\'receivable\', \'payable\')),',
      '    principal_cents INTEGER NOT NULL CHECK(principal_cents > 0),',
      '    outstanding_cents INTEGER NOT NULL,',
      '    due_date TEXT,',
      '    status TEXT NOT NULL,',
      '    created_at TEXT NOT NULL',
      ');',
      '',
      'CREATE TABLE IF NOT EXISTS settlement_allocations (',
      '    id TEXT PRIMARY KEY,',
      '    settlement_entry_id TEXT NOT NULL REFERENCES journal_entries(id),',
      '    debt_id TEXT NOT NULL REFERENCES debts(id),',
      '    allocated_cents INTEGER NOT NULL CHECK(allocated_cents > 0),',
      '    settlement_date TEXT NOT NULL',
      ');',
      '',
      'CREATE TABLE IF NOT EXISTS categories (',
      '    id TEXT PRIMARY KEY,',
      '    name TEXT NOT NULL,',
      '    type TEXT NOT NULL,',
      '    color_hex TEXT NOT NULL',
      ');',
      '',
      '-- Analytical Views --',
      'CREATE VIEW IF NOT EXISTS view_account_balances AS',
      'SELECT a.id, a.name, a.type, a.currency_code,',
      '  SUM(CASE WHEN a.type IN (\'asset\', \'expense\') THEN',
      '    CASE WHEN p.direction = \'debit\' THEN p.amount_cents ELSE -p.amount_cents END',
      '  ELSE',
      '    CASE WHEN p.direction = \'credit\' THEN p.amount_cents ELSE -p.amount_cents END',
      '  END) AS balance_cents,',
      '  ROUND(SUM(CASE WHEN a.type IN (\'asset\', \'expense\') THEN',
      '    CASE WHEN p.direction = \'debit\' THEN p.amount_cents ELSE -p.amount_cents END',
      '  ELSE',
      '    CASE WHEN p.direction = \'credit\' THEN p.amount_cents ELSE -p.amount_cents END',
      '  END) / 100.0, 2) AS balance_decimal',
      'FROM accounts a',
      'LEFT JOIN postings p ON a.id = p.account_id',
      'LEFT JOIN journal_entries j ON p.entry_id = j.id',
      'WHERE j.is_voided = 0 OR j.id IS NULL',
      'GROUP BY a.id;',
      '',
      'CREATE VIEW IF NOT EXISTS view_occurrence_pnl AS',
      'SELECT j.occurrence_date,',
      '  c.name AS category_name,',
      '  a.type AS account_type,',
      '  j.description,',
      '  p.amount_cents,',
      '  ROUND(p.amount_cents / 100.0, 2) AS amount_decimal',
      'FROM postings p',
      'JOIN accounts a ON p.account_id = a.id',
      'JOIN journal_entries j ON p.entry_id = j.id',
      'LEFT JOIN categories c ON p.category_id = c.id',
      'WHERE a.type IN (\'income\', \'expense\') AND j.is_voided = 0',
      '  AND (SELECT COUNT(*) FROM postings pc WHERE pc.entry_id = j.id) >= 2',
      '  AND NOT EXISTS (',
      '    SELECT 1 FROM postings px LEFT JOIN accounts ax ON px.account_id = ax.id',
      '    WHERE px.entry_id = j.id AND (',
      '      px.account_id = \'acc-sys-legacy-offset\'',
      '      OR ax.id IS NULL',
      '      OR (ax.type IN (\'asset\', \'liability\') AND LOWER(COALESCE(ax.name, \'\')) NOT LIKE \'%receivable%\' AND LOWER(COALESCE(ax.name, \'\')) NOT LIKE \'%payable%\' AND UPPER(TRIM(COALESCE(ax.currency_code, \'\'))) != \'ETB\')',
      '    )',
      '  )',
      '  AND (',
      '    EXISTS (',
      '      SELECT 1 FROM postings pr JOIN accounts ar ON pr.account_id = ar.id',
      '      WHERE pr.entry_id = j.id',
      '        AND ar.type IN (\'asset\', \'liability\')',
      '        AND LOWER(COALESCE(ar.name, \'\')) NOT LIKE \'%receivable%\'',
      '        AND LOWER(COALESCE(ar.name, \'\')) NOT LIKE \'%payable%\'',
      '        AND UPPER(TRIM(COALESCE(ar.currency_code, \'\'))) = \'ETB\'',
      '    )',
      '    OR EXISTS (',
      '      SELECT 1 FROM debts d JOIN settlement_allocations sa ON sa.debt_id = d.id',
      '      JOIN journal_entries sj ON sa.settlement_entry_id = sj.id',
      '      JOIN postings sp ON sp.entry_id = sj.id',
      '      JOIN accounts sax ON sp.account_id = sax.id',
      '      WHERE d.origin_entry_id = j.id AND sj.is_voided = 0',
      '        AND sax.type IN (\'asset\', \'liability\')',
      '        AND LOWER(COALESCE(sax.name, \'\')) NOT LIKE \'%receivable%\'',
      '        AND LOWER(COALESCE(sax.name, \'\')) NOT LIKE \'%payable%\'',
      '        AND UPPER(TRIM(COALESCE(sax.currency_code, \'\'))) = \'ETB\'',
      '    )',
      '  )',
      '  AND NOT EXISTS (',
      '    SELECT 1 FROM debts d JOIN settlement_allocations sa ON sa.debt_id = d.id',
      '    JOIN journal_entries sj ON sa.settlement_entry_id = sj.id',
      '    JOIN postings sp ON sp.entry_id = sj.id',
      '    JOIN accounts sax ON sp.account_id = sax.id',
      '    WHERE d.origin_entry_id = j.id AND sj.is_voided = 0',
      '      AND sax.type IN (\'asset\', \'liability\')',
      '      AND LOWER(COALESCE(sax.name, \'\')) NOT LIKE \'%receivable%\'',
      '      AND LOWER(COALESCE(sax.name, \'\')) NOT LIKE \'%payable%\'',
      '      AND UPPER(TRIM(COALESCE(sax.currency_code, \'\'))) != \'ETB\'',
      '  );',
      '',
      'CREATE VIEW IF NOT EXISTS view_cash_flow AS',
      'SELECT p.account_movement_date,',
      '  a.name AS account_name,',
      '  p.direction,',
      '  CASE WHEN p.direction = \'debit\' THEN p.amount_cents ELSE 0 END AS inflow_cents,',
      '  CASE WHEN p.direction = \'credit\' THEN p.amount_cents ELSE 0 END AS outflow_cents,',
      '  ROUND(CASE WHEN p.direction = \'debit\' THEN p.amount_cents ELSE 0 END / 100.0, 2) AS inflow_decimal,',
      '  ROUND(CASE WHEN p.direction = \'credit\' THEN p.amount_cents ELSE 0 END / 100.0, 2) AS outflow_decimal,',
      '  j.description',
      'FROM postings p',
      'JOIN accounts a ON p.account_id = a.id',
      'JOIN journal_entries j ON p.entry_id = j.id',
      'WHERE a.type = \'asset\' AND a.is_system = 0 AND LOWER(COALESCE(a.sub_type, \'bank\')) NOT IN (\'receivable\', \'savings_vault\') AND LOWER(a.name) NOT LIKE \'%receivable%\' AND j.is_voided = 0',
      '  AND UPPER(TRIM(COALESCE(a.currency_code, \'\'))) = \'ETB\'',
      '  AND (SELECT COUNT(*) FROM postings pc WHERE pc.entry_id = j.id) >= 2',
      '  AND NOT EXISTS (',
      '    SELECT 1 FROM postings px LEFT JOIN accounts ax ON px.account_id = ax.id',
      '    WHERE px.entry_id = j.id AND (',
      '      px.account_id = \'acc-sys-legacy-offset\'',
      '      OR ax.id IS NULL',
      '      OR (ax.type IN (\'asset\', \'liability\') AND LOWER(COALESCE(ax.name, \'\')) NOT LIKE \'%receivable%\' AND LOWER(COALESCE(ax.name, \'\')) NOT LIKE \'%payable%\' AND UPPER(TRIM(COALESCE(ax.currency_code, \'\'))) != \'ETB\')',
      '    )',
      '  );',
      '',
      '-- Seed Data Insertion --',
      'BEGIN TRANSACTION;',
    ];

    for (const a of payload.accounts) {
      const safeCurrency = normalizeCurrencyCode(a.currencyCode).replace(/'/g, "''");
      const safeSubType = getAccountSubType(a).replace(/'/g, "''");
      lines.push(
        `INSERT INTO accounts (id, name, type, sub_type, is_system, currency_code, is_archived, created_at) VALUES ('${a.id}', '${a.name.replace(/'/g, "''")}', '${a.type}', '${safeSubType}', ${a.isSystem ? 1 : 0}, '${safeCurrency}', ${a.isArchived ? 1 : 0}, '${a.createdAt}');`
      );
    }

    for (const p of payload.parties) {
      lines.push(
        `INSERT INTO parties (id, name, phone, notes, is_archived, created_at) VALUES ('${p.id}', '${p.name.replace(/'/g, "''")}', ${p.phone ? `'${p.phone}'` : 'NULL'}, ${p.notes ? `'${p.notes.replace(/'/g, "''")}'` : 'NULL'}, ${p.isArchived ? 1 : 0}, '${p.createdAt}');`
      );
    }

    for (const c of payload.categories) {
      lines.push(
        `INSERT INTO categories (id, name, type, color_hex) VALUES ('${c.id}', '${c.name.replace(/'/g, "''")}', '${c.type}', '${c.colorHex}');`
      );
    }

    for (const j of payload.entries) {
      lines.push(
        `INSERT INTO journal_entries (id, entry_type, description, occurrence_date, is_voided, void_reason, created_at) VALUES ('${j.id}', '${j.entryType}', '${j.description.replace(/'/g, "''")}', '${j.occurrenceDate}', ${j.isVoided ? 1 : 0}, ${j.voidReason ? `'${j.voidReason.replace(/'/g, "''")}'` : 'NULL'}, '${j.createdAt}');`
      );
    }

    for (const p of payload.postings) {
      lines.push(
        `INSERT INTO postings (id, entry_id, account_id, amount_cents, direction, account_movement_date, category_id, note) VALUES ('${p.id}', '${p.entryId}', '${p.accountId}', ${p.amountCents}, '${p.direction}', '${p.accountMovementDate}', ${p.categoryId ? `'${p.categoryId}'` : 'NULL'}, ${p.note ? `'${p.note.replace(/'/g, "''")}'` : 'NULL'});`
      );
    }

    for (const d of payload.debts) {
      lines.push(
        `INSERT INTO debts (id, origin_entry_id, party_id, debt_type, principal_cents, outstanding_cents, due_date, status, created_at) VALUES ('${d.id}', '${d.originEntryId}', '${d.partyId}', '${d.debtType}', ${d.principalCents}, ${d.outstandingCents}, ${d.dueDate ? `'${d.dueDate}'` : 'NULL'}, '${d.status}', '${d.createdAt}');`
      );
    }

    for (const s of payload.settlementAllocations) {
      lines.push(
        `INSERT INTO settlement_allocations (id, settlement_entry_id, debt_id, allocated_cents, settlement_date) VALUES ('${s.id}', '${s.settlementEntryId}', '${s.debtId}', ${s.allocatedCents}, '${s.settlementDate}');`
      );
    }

    lines.push('COMMIT;');
    return lines.join('\n');
  }

  /**
   * Generates comprehensive markdown Data Dictionary.
   */
  public static generateDataDictionary(): string {
    return `# Daywell Personal Finance - Data Dictionary & Accounting Standard (v2.0.0)

## Overview
This document defines the schema, units of measure, double-entry invariants, and date models for the Daywell Personal Finance Engine. All calculations and exports follow the rules defined herein.

---

## 1. Unit Convention: Integer Minor Units (Cents / ሳንቲም)
- All currency balances, transaction amounts, and allocations are stored as **64-bit integers in minor currency units**.
- **1 Ethiopian Birr (ETB) = 100 cents (ሳንቲም)**.
- Decimal values in exports (e.g. \`amount_decimal\`) are computed views for human analysis (\`amount_cents / 100.0\`).
- Floating-point arithmetic is strictly prohibited in the storage and calculation engine to prevent compounding rounding drift.

---

## 2. Double-Entry Invariant & Balancing Guarantee
Every transaction is represented by one \`journal_entries\` record and two or more \`postings\` records.
- **Rule**: For every journal entry:
  $$\\sum \\text{Debits} - \\sum \\text{Credits} = 0$$
- Normal balance rules:
  - **Asset** accounts: Balance = $\\sum \\text{Debits} - \\sum \\text{Credits}$
  - **Expense** accounts: Balance = $\\sum \\text{Debits} - \\sum \\text{Credits}$
  - **Liability** accounts: Balance = $\\sum \\text{Credits} - \\sum \\text{Debits}$
  - **Equity** accounts: Balance = $\\sum \\text{Credits} - \\sum \\text{Debits}$
  - **Income** accounts: Balance = $\\sum \\text{Credits} - \\sum \\text{Debits}$

---

## 3. Date Architecture
Three distinct, non-conflated dates are tracked:
1. **\`occurrence_date\`**: The economic date of the transaction (when the expense/income was consumed or earned). Used in Occurrence-based P&L reporting.
2. **\`account_movement_date\`**: The date funds entered or left a physical account (bank, cash, wallet). Used in Cash-Flow reporting.
3. **\`settlement_date\`**: The date a specific debt allocation was recorded.

### Dual-Reporting Boundary Rule:
An expense incurred on **January 30** and paid/repaid on **February 2**:
- **January Occurrence Report**: Shows the expense.
- **January Cash-Flow Report**: Shows 0 outflow.
- **February Occurrence Report**: Shows 0 expense.
- **February Cash-Flow Report**: Shows the cash outflow.

---

## 4. Tables and Entities

### \`accounts\`
| Column | Type | Constraints | Description |
|---|---|---|---|
| \`id\` | TEXT | PRIMARY KEY | UUID v4 identifier |
| \`name\` | TEXT | NOT NULL | Human-readable name (e.g. "CBE Account", "Cash Wallet") |
| \`type\` | TEXT | NOT NULL | Enum: \`asset\`, \`liability\`, \`equity\`, \`income\`, \`expense\` |
| \`sub_type\` | TEXT | NOT NULL | Account sub-type (\`bank\`, \`cash\`, \`mobile_wallet\`, \`savings_vault\`, etc.) |
| \`is_system\` | INTEGER | NOT NULL | Boolean (0/1) identifying internal double-entry control accounts |
| \`currency_code\` | TEXT | NOT NULL | Verified ISO-4217 code (\`ETB\` active; foreign or blank isolated) |
| \`is_archived\` | INTEGER | DEFAULT 0 | 1 if archived, 0 if active |
| \`created_at\` | TEXT | NOT NULL | ISO 8601 UTC timestamp |

### \`parties\`
| Column | Type | Constraints | Description |
|---|---|---|---|
| \`id\` | TEXT | PRIMARY KEY | UUID v4 identifier |
| \`name\` | TEXT | NOT NULL | Contact name (borrower, lender, employer, colleague) |
| \`phone\` | TEXT | NULLABLE | Phone number |
| \`notes\` | TEXT | NULLABLE | Additional context |
| \`is_archived\` | INTEGER | DEFAULT 0 | 1 if archived (blocked if outstanding balance > 0) |
| \`created_at\` | TEXT | NOT NULL | ISO 8601 UTC timestamp |

### \`journal_entries\`
| Column | Type | Constraints | Description |
|---|---|---|---|
| \`id\` | TEXT | PRIMARY KEY | UUID v4 identifier |
| \`entry_type\` | TEXT | NOT NULL | \`standard\`, \`transfer\`, \`debt_issuance\`, \`settlement\`, \`split_expense\`, \`adjustment\`, \`write_off\` |
| \`description\` | TEXT | NOT NULL | User description or automated memo |
| \`occurrence_date\` | TEXT | NOT NULL | ISO 8601 Date (\`YYYY-MM-DD\`) |
| \`is_voided\` | INTEGER | DEFAULT 0 | 1 if entry has been voided by correction |
| \`void_reason\` | TEXT | NULLABLE | Reason for voiding / reversal |
| \`created_at\` | TEXT | NOT NULL | ISO 8601 UTC timestamp |

### \`postings\`
| Column | Type | Constraints | Description |
|---|---|---|---|
| \`id\` | TEXT | PRIMARY KEY | UUID v4 identifier |
| \`entry_id\` | TEXT | NOT NULL | Foreign key to \`journal_entries.id\` |
| \`account_id\` | TEXT | NOT NULL | Foreign key to \`accounts.id\` |
| \`amount_cents\` | INTEGER | NOT NULL (> 0) | Amount in minor units |
| \`direction\` | TEXT | NOT NULL | Enum: \`debit\` or \`credit\` |
| \`account_movement_date\` | TEXT | NOT NULL | ISO 8601 Date (\`YYYY-MM-DD\`) |
| \`category_id\` | TEXT | NULLABLE | Foreign key to \`categories.id\` |
| \`note\` | TEXT | NULLABLE | Line-item note |

### \`debts\`
| Column | Type | Constraints | Description |
|---|---|---|---|
| \`id\` | TEXT | PRIMARY KEY | UUID v4 identifier |
| \`origin_entry_id\` | TEXT | NOT NULL | Foreign key to originating \`journal_entries.id\` |
| \`party_id\` | TEXT | NOT NULL | Foreign key to \`parties.id\` |
| \`debt_type\` | TEXT | NOT NULL | \`receivable\` (they owe me) or \`payable\` (I owe them) |
| \`principal_cents\` | INTEGER | NOT NULL (> 0) | Original principal in minor units |
| \`outstanding_cents\`| INTEGER | NOT NULL (>= 0)| Remaining unpaid balance |
| \`due_date\` | TEXT | NULLABLE | Expected due date (\`YYYY-MM-DD\`) |
| \`status\` | TEXT | NOT NULL | \`active\`, \`settled\`, \`written_off\` |
| \`created_at\` | TEXT | NOT NULL | ISO 8601 UTC timestamp |

### \`settlement_allocations\`
| Column | Type | Constraints | Description |
|---|---|---|---|
| \`id\` | TEXT | PRIMARY KEY | UUID v4 identifier |
| \`settlement_entry_id\`| TEXT | NOT NULL | Foreign key to \`journal_entries.id\` |
| \`debt_id\` | TEXT | NOT NULL | Foreign key to \`debts.id\` |
| \`allocated_cents\` | INTEGER | NOT NULL (> 0) | Amount allocated to reduce principal |
| \`settlement_date\` | TEXT | NOT NULL | ISO 8601 Date (\`YYYY-MM-DD\`) |
`;
  }

  /**
   * Builds the complete export bundle as a JSZip archive.
   */
  public static async createExportZipBundle(payload: ExportDataPayload): Promise<{ blob: Blob; fileName: string }> {
    const zip = new JSZip();
    const nowUtc = EthiopiaClock.nowUtc();
    const nowIso = nowUtc.toISOString();
    const dateStamp = CalendarDate.fromUtcInstantInEthiopia(nowUtc).toIsoString();

    const classifications = classifyAllJournalEntries({
      accounts: payload.accounts,
      entries: payload.entries,
      postings: payload.postings,
      debts: payload.debts,
      allocations: payload.settlementAllocations,
    });
    const entryMap = new Map(payload.entries.map((e) => [e.id, e]));

    // 1. Normalized CSVs (with UTF-8 BOM)
    const accountsCsv = this.toCsvWithBom(payload.accounts, [
      'id',
      'name',
      'type',
      {
        key: 'currencyCode',
        header: 'currencyCode',
        transform: (val) => normalizeCurrencyCode(val) || 'UNVERIFIED',
      },
      {
        key: 'id',
        header: 'reportingStatus',
        transform: (_, row) => {
          if (row.isSystem) return 'SYSTEM';
          const tier = classifyCurrencyCode(row.currencyCode);
          if (tier === 'verified_etb') return 'ELIGIBLE_ETB';
          if (tier === 'verified_non_etb') {
            return `EXCLUDED_${normalizeCurrencyCode(row.currencyCode)}`;
          }
          return 'CURRENCY_REVIEW';
        },
      },
      'isArchived',
      'createdAt',
    ]);
    zip.file('csv/accounts.csv', accountsCsv);

    const partiesCsv = this.toCsvWithBom(payload.parties, [
      'id',
      'name',
      'phone',
      'notes',
      'isArchived',
      'createdAt',
    ]);
    zip.file('csv/parties.csv', partiesCsv);

    const categoriesCsv = this.toCsvWithBom(payload.categories, [
      'id',
      'name',
      'type',
      'colorHex',
      'isDefault',
    ]);
    zip.file('csv/categories.csv', categoriesCsv);

    const entriesCsv = this.toCsvWithBom(payload.entries, [
      'id',
      'entryType',
      'description',
      'occurrenceDate',
      {
        key: 'id',
        header: 'currency',
        transform: (_, row) => {
          const cls = classifications.get(row.id);
          if (!cls) return 'UNVERIFIED';
          return cls.nativeCurrencyCode || (cls.touchedCurrencies.length > 0 ? cls.touchedCurrencies.join('/') : 'UNVERIFIED');
        },
      },
      {
        key: 'id',
        header: 'reportingStatus',
        transform: (_, row) => {
          const cls = classifications.get(row.id);
          if (!cls) return 'CURRENCY_REVIEW';
          if (cls.status === 'eligible_etb') return 'ELIGIBLE_ETB';
          if (cls.status === 'excluded_non_etb') {
            return `EXCLUDED_${cls.nativeCurrencyCode || 'FOREIGN'}`;
          }
          if (cls.status === 'inactive_or_voided') return 'INACTIVE_OR_VOIDED';
          return 'CURRENCY_REVIEW';
        },
      },
      'isVoided',
      'voidReason',
      'createdAt',
    ]);
    zip.file('csv/journal_entries.csv', entriesCsv);

    const postingsCsv = this.toCsvWithBom(payload.postings, [
      'id',
      'entryId',
      'accountId',
      'amountCents',
      {
        key: 'amountCents',
        header: 'amount_decimal',
        transform: (val) => (val / 100).toFixed(2),
      },
      'direction',
      'accountMovementDate',
      'categoryId',
      'note',
    ]);
    zip.file('csv/postings.csv', postingsCsv);

    const debtsCsv = this.toCsvWithBom(payload.debts, [
      'id',
      'originEntryId',
      'partyId',
      'debtType',
      {
        key: 'id',
        header: 'currency',
        transform: (_, row) => {
          const originCls = classifications.get(row.originEntryId);
          if (originCls?.nativeCurrencyCode) return originCls.nativeCurrencyCode;
          if (
            originCls &&
            originCls.touchedCurrencies.length === 1 &&
            originCls.touchedCurrencies[0] !== 'UNVERIFIED'
          ) {
            return originCls.touchedCurrencies[0];
          }
          return isDebtEligibleEtb(row, entryMap, classifications) ? 'ETB' : 'UNVERIFIED';
        },
      },
      {
        key: 'id',
        header: 'reportingStatus',
        transform: (_, row) => {
          const eligible = isDebtEligibleEtb(row, entryMap, classifications);
          if (eligible) return 'ELIGIBLE_ETB';
          const originCls = classifications.get(row.originEntryId);
          if (originCls?.status === 'excluded_non_etb') {
            return `EXCLUDED_${originCls.nativeCurrencyCode || 'FOREIGN'}`;
          }
          return 'CURRENCY_REVIEW';
        },
      },
      'principalCents',
      {
        key: 'principalCents',
        header: 'principal_decimal',
        transform: (val) => (val / 100).toFixed(2),
      },
      'outstandingCents',
      {
        key: 'outstandingCents',
        header: 'outstanding_decimal',
        transform: (val) => (val / 100).toFixed(2),
      },
      'dueDate',
      'status',
      'createdAt',
    ]);
    zip.file('csv/debts.csv', debtsCsv);

    const allocationsCsv = this.toCsvWithBom(payload.settlementAllocations, [
      'id',
      'settlementEntryId',
      'debtId',
      'allocatedCents',
      {
        key: 'allocatedCents',
        header: 'allocated_decimal',
        transform: (val) => (val / 100).toFixed(2),
      },
      'settlementDate',
    ]);
    zip.file('csv/settlement_allocations.csv', allocationsCsv);

    // 2. Multi-Sheet Excel Workbook
    const excelBytes = this.generateExcelWorkbook(payload);
    zip.file('excel/finance_workbook.xlsx', excelBytes);

    // 3. Standalone SQLite Analytical SQL
    const sqliteSql = this.generateSqliteAnalyticalScript(payload);
    zip.file('sqlite/finance_export.sql', sqliteSql);

    // 4. Data Dictionary
    const dataDict = this.generateDataDictionary();
    zip.file('data_dictionary.md', dataDict);

    // 5. Manifest with Checksums
    const manifest = {
      schemaVersion: '2.0.0',
      exportedAtUtc: nowIso,
      currency: 'ETB',
      accountingModel: 'Simplified Double-Entry Balanced Ledger',
      fileChecksums: {
        'csv/accounts.csv': { rows: payload.accounts.length, sha256: await computeSha256(accountsCsv) },
        'csv/parties.csv': { rows: payload.parties.length, sha256: await computeSha256(partiesCsv) },
        'csv/journal_entries.csv': { rows: payload.entries.length, sha256: await computeSha256(entriesCsv) },
        'csv/postings.csv': { rows: payload.postings.length, sha256: await computeSha256(postingsCsv) },
        'csv/debts.csv': { rows: payload.debts.length, sha256: await computeSha256(debtsCsv) },
        'csv/settlement_allocations.csv': { rows: payload.settlementAllocations.length, sha256: await computeSha256(allocationsCsv) },
        'csv/categories.csv': { rows: payload.categories.length, sha256: await computeSha256(categoriesCsv) },
        'sqlite/finance_export.sql': { sha256: await computeSha256(sqliteSql) },
        'data_dictionary.md': { sha256: await computeSha256(dataDict) },
      },
    };
    zip.file('manifest.json', JSON.stringify(manifest, null, 2));

    const blob = await zip.generateAsync({ type: 'blob' });
    const fileName = `daywell_finance_export_${dateStamp}.zip`;
    return { blob, fileName };
  }
}
