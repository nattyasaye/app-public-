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
  resolveCanonicalCategoryId,
  SimpleTransaction,
} from '../domain/doubleEntryFinance';
import {
  SharedBudget,
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
  budgets?: SharedBudget[];
  transactions?: SimpleTransaction[];
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
    budgets?: SharedBudget[];
    transactions?: SimpleTransaction[];
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
      budgets: payload.budgets,
      transactions: payload.transactions,
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
    budgets?: SharedBudget[];
    transactions?: SimpleTransaction[];
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
      budgets: payload.budgets,
      transactions: payload.transactions,
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
    const headers = columns.map((col) =>
      typeof col === 'object' ? `"${col.header.replace(/"/g, '""')}"` : `"${String(col)}"`
    );
    if (data.length === 0) {
      return BOM + headers.join(',');
    }

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

  public static exportAccountsCsv(accounts: Account[]): string {
    return this.toCsvWithBom(accounts, [
      'id',
      'name',
      'type',
      {
        key: 'subType',
        header: 'subType',
        transform: (_, row) => getAccountSubType(row),
      },
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
      {
        key: 'openingBalanceCents',
        header: 'openingBalanceCents',
        transform: (val) => String(val ?? 0),
      },
      'isArchived',
      'createdAt',
    ]);
  }

  public static exportCategoriesCsv(categories: TransactionCategory[]): string {
    return this.toCsvWithBom(categories, [
      'id',
      'name',
      'type',
      'colorHex',
      {
        key: 'parentId',
        header: 'parentId',
        transform: (val) => (val ? String(val) : ''),
      },
      {
        key: 'sortOrder',
        header: 'sortOrder',
        transform: (val) => String(val ?? 0),
      },
      {
        key: 'isDefault',
        header: 'isDefault',
        transform: (val) => String(Boolean(val)),
      },
      {
        key: 'isArchived',
        header: 'isArchived',
        transform: (val) => String(Boolean(val)),
      },
    ]);
  }

  public static exportPartiesCsv(parties: Party[]): string {
    return this.toCsvWithBom(parties, [
      'id',
      'name',
      'phone',
      'notes',
      'isArchived',
      'createdAt',
    ]);
  }

  public static exportJournalEntriesCsv(payload: {
    accounts: Account[];
    entries: JournalEntry[];
    postings: Posting[];
    debts: Debt[];
    allocations?: SettlementAllocation[];
  }): string {
    const classifications = classifyAllJournalEntries({
      accounts: payload.accounts,
      entries: payload.entries,
      postings: payload.postings,
      debts: payload.debts,
      allocations: payload.allocations,
    });
    return this.toCsvWithBom(payload.entries, [
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
          return (
            cls.nativeCurrencyCode ||
            (cls.touchedCurrencies.length > 0 ? cls.touchedCurrencies.join('/') : 'UNVERIFIED')
          );
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
      'correctedFromEntryId',
      'legacySourceTxId',
      'createdAt',
    ]);
  }

  public static exportPostingsCsv(postings: Posting[]): string {
    return this.toCsvWithBom(postings, [
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
      {
        key: 'categoryId',
        header: 'categoryId',
        transform: (val) => (val ? resolveCanonicalCategoryId(String(val)) : ''),
      },
      'note',
    ]);
  }

  public static exportDebtsCsv(payload: {
    accounts: Account[];
    entries: JournalEntry[];
    postings: Posting[];
    debts: Debt[];
    allocations?: SettlementAllocation[];
  }): string {
    const classifications = classifyAllJournalEntries({
      accounts: payload.accounts,
      entries: payload.entries,
      postings: payload.postings,
      debts: payload.debts,
      allocations: payload.allocations,
    });
    const entryMap = new Map(payload.entries.map((e) => [e.id, e]));
    return this.toCsvWithBom(payload.debts, [
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
      'writeOffEntryId',
      'createdAt',
    ]);
  }

  public static exportSettlementAllocationsCsv(allocations: SettlementAllocation[]): string {
    return this.toCsvWithBom(allocations, [
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
  }

  public static exportCommitmentsCsv(commitments: SharedCommitment[]): string {
    return this.toCsvWithBom(commitments, [
      'id',
      'title',
      {
        key: 'direction',
        header: 'direction',
        transform: (val) => val || 'outflow',
      },
      'amountCents',
      {
        key: 'amountCents',
        header: 'amount_decimal',
        transform: (val) => (Number(val || 0) / 100).toFixed(2),
      },
      'dueDate',
      'isPaid',
      'linkedAccountId',
      'categoryId',
      'linkedDebtId',
      'settlementEntryId',
      'recurringRuleId',
      {
        key: 'legacyPaidUnverified',
        header: 'legacyPaidUnverified',
        transform: (val) => String(Boolean(val)),
      },
    ]);
  }

  public static exportCommitmentSettlementsCsv(
    settlements: SharedCommitmentSettlement[]
  ): string {
    return this.toCsvWithBom(settlements, [
      'id',
      'commitmentId',
      'entryId',
      'amountCents',
      {
        key: 'amountCents',
        header: 'amount_decimal',
        transform: (val) => (Number(val || 0) / 100).toFixed(2),
      },
      'settledDate',
      'createdAt',
    ]);
  }

  public static exportSavingsGoalsCsv(goals: SharedSavingsGoal[]): string {
    return this.toCsvWithBom(goals, [
      'id',
      'title',
      'targetCents',
      {
        key: 'targetCents',
        header: 'target_decimal',
        transform: (val) => (Number(val || 0) / 100).toFixed(2),
      },
      'currentAllocatedCents',
      {
        key: 'currentAllocatedCents',
        header: 'allocated_decimal',
        transform: (val) => (Number(val || 0) / 100).toFixed(2),
      },
      'targetDate',
      'linkedAccountId',
      {
        key: 'status',
        header: 'status',
        transform: (val) => val || 'active',
      },
      {
        key: 'status',
        header: 'createdAt',
        transform: (_val, row) => String((row as unknown as Record<string, unknown>).createdAt || ''),
      },
    ]);
  }

  public static exportBudgetsCsv(budgets: SharedBudget[]): string {
    return this.toCsvWithBom(budgets, [
      'id',
      'monthIso',
      'categoryId',
      'limitCents',
      {
        key: 'limitCents',
        header: 'limit_decimal',
        transform: (val) => (Number(val || 0) / 100).toFixed(2),
      },
      {
        key: 'rolloverEnabled',
        header: 'rolloverEnabled',
        transform: (val) => String(Boolean(val)),
      },
      'createdAt',
      'updatedAt',
    ]);
  }

  public static exportRecurringRulesCsv(rules: SharedRecurringRule[]): string {
    return this.toCsvWithBom(rules, [
      'id',
      'title',
      'ruleType',
      'amountCents',
      {
        key: 'amountCents',
        header: 'amount_decimal',
        transform: (val) => (Number(val || 0) / 100).toFixed(2),
      },
      'frequency',
      'interval',
      'startDate',
      'nextOccurrenceDate',
      'endDate',
      'accountId',
      'destinationAccountId',
      'categoryId',
      'linkedDebtId',
      'isActive',
      'autoPost',
      'createdAt',
    ]);
  }

  public static exportTransactionsCsv(transactions: SimpleTransaction[]): string {
    return this.toCsvWithBom(transactions, [
      'id',
      'type',
      'amountCents',
      {
        key: 'amountCents',
        header: 'amount_decimal',
        transform: (val) => (Number(val || 0) / 100).toFixed(2),
      },
      'accountId',
      'destinationAccountId',
      'categoryId',
      'description',
      'transactionDate',
      'journalEntryId',
      {
        key: 'isSuperseded',
        header: 'isSuperseded',
        transform: (val) => String(Boolean(val)),
      },
      'createdAt',
    ]);
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

    // 6. Commitments and Savings Goals Sheet
    const goalsList = payload.savingsGoals || [];
    const commitmentsList = payload.commitments || [];
    const cmRows = [
      ['Record Kind', 'ID', 'Title', 'Direction / Status', 'Amount / Target (ETB)', 'Allocated (ETB)', 'Date', 'Linked Account', 'Paid / Legacy'],
      ...commitmentsList.map((c) => [
        'COMMITMENT',
        c.id,
        c.title,
        c.direction || 'outflow',
        (c.amountCents / 100).toFixed(2),
        '',
        c.dueDate,
        c.linkedAccountId || '',
        c.legacyPaidUnverified ? 'LEGACY_UNVERIFIED' : c.isPaid ? 'PAID' : 'OPEN',
      ]),
      ...goalsList.map((g) => [
        'SAVINGS_GOAL',
        g.id,
        g.title,
        (g.status || 'active').toUpperCase(),
        (g.targetCents / 100).toFixed(2),
        (g.currentAllocatedCents / 100).toFixed(2),
        g.targetDate || '',
        g.linkedAccountId || 'VIRTUAL',
        '',
      ]),
    ];
    const wsCommitmentsGoals = XLSX.utils.aoa_to_sheet(cmRows);
    XLSX.utils.book_append_sheet(wb, wsCommitmentsGoals, 'Commitments_and_Goals');

    // 7. Budgets and Recurring Rules Sheet
    const budgetsList = payload.budgets || [];
    const rulesList = payload.recurringRules || [];
    const budgetRulesRows = [
      ['Record Kind', 'ID', 'Month / Frequency', 'Category / Type', 'Title', 'Amount (ETB)', 'Next Date', 'Active / Rollover'],
      ...budgetsList.map((b) => [
        'BUDGET',
        b.id,
        b.monthIso,
        catMap.get(b.categoryId) || b.categoryId,
        catMap.get(b.categoryId) || b.categoryId,
        (b.limitCents / 100).toFixed(2),
        '',
        b.rolloverEnabled ? 'ROLLOVER_ON' : 'ROLLOVER_OFF',
      ]),
      ...rulesList.map((r) => [
        'RECURRING_RULE',
        r.id,
        `${r.frequency} (x${r.interval})`,
        r.ruleType,
        r.title,
        (r.amountCents / 100).toFixed(2),
        r.nextOccurrenceDate,
        `${r.isActive ? 'ACTIVE' : 'PAUSED'} / autoPost=${Boolean(r.autoPost)}`,
      ]),
    ];
    const wsBudgetsRecurring = XLSX.utils.aoa_to_sheet(budgetRulesRows);
    XLSX.utils.book_append_sheet(wb, wsBudgetsRecurring, 'Budgets_and_Recurring');

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
      '    color_hex TEXT NOT NULL,',
      '    parent_id TEXT REFERENCES categories(id),',
      '    sort_order INTEGER NOT NULL DEFAULT 0,',
      '    is_default INTEGER NOT NULL DEFAULT 0,',
      '    is_archived INTEGER NOT NULL DEFAULT 0',
      ');',
      '',
      'CREATE TABLE IF NOT EXISTS commitments (',
      '    id TEXT PRIMARY KEY,',
      '    title TEXT NOT NULL,',
      '    direction TEXT NOT NULL DEFAULT \'outflow\',',
      '    amount_cents INTEGER NOT NULL CHECK(amount_cents > 0),',
      '    due_date TEXT NOT NULL,',
      '    is_paid INTEGER NOT NULL DEFAULT 0,',
      '    linked_account_id TEXT REFERENCES accounts(id),',
      '    category_id TEXT REFERENCES categories(id),',
      '    linked_debt_id TEXT REFERENCES debts(id),',
      '    settlement_entry_id TEXT REFERENCES journal_entries(id),',
      '    recurring_rule_id TEXT,',
      '    legacy_paid_unverified INTEGER NOT NULL DEFAULT 0',
      ');',
      '',
      'CREATE TABLE IF NOT EXISTS commitment_settlements (',
      '    id TEXT PRIMARY KEY,',
      '    commitment_id TEXT NOT NULL REFERENCES commitments(id),',
      '    entry_id TEXT NOT NULL REFERENCES journal_entries(id),',
      '    amount_cents INTEGER NOT NULL CHECK(amount_cents > 0),',
      '    settled_date TEXT NOT NULL,',
      '    created_at TEXT NOT NULL',
      ');',
      '',
      'CREATE TABLE IF NOT EXISTS savings_goals (',
      '    id TEXT PRIMARY KEY,',
      '    title TEXT NOT NULL,',
      '    target_cents INTEGER NOT NULL CHECK(target_cents > 0),',
      '    current_allocated_cents INTEGER NOT NULL DEFAULT 0,',
      '    target_date TEXT,',
      '    linked_account_id TEXT REFERENCES accounts(id),',
      '    status TEXT NOT NULL DEFAULT \'active\',',
      '    created_at TEXT NOT NULL',
      ');',
      '',
      'CREATE TABLE IF NOT EXISTS budgets (',
      '    id TEXT PRIMARY KEY,',
      '    category_id TEXT NOT NULL REFERENCES categories(id),',
      '    month_iso TEXT NOT NULL,',
      '    limit_cents INTEGER NOT NULL CHECK(limit_cents > 0),',
      '    rollover_enabled INTEGER NOT NULL DEFAULT 0,',
      '    created_at TEXT NOT NULL,',
      '    updated_at TEXT NOT NULL',
      ');',
      '',
      'CREATE TABLE IF NOT EXISTS recurring_rules (',
      '    id TEXT PRIMARY KEY,',
      '    title TEXT NOT NULL,',
      '    rule_type TEXT NOT NULL,',
      '    amount_cents INTEGER NOT NULL CHECK(amount_cents > 0),',
      '    frequency TEXT NOT NULL,',
      '    interval INTEGER NOT NULL DEFAULT 1,',
      '    start_date TEXT NOT NULL,',
      '    next_occurrence_date TEXT NOT NULL,',
      '    end_date TEXT,',
      '    account_id TEXT REFERENCES accounts(id),',
      '    destination_account_id TEXT REFERENCES accounts(id),',
      '    category_id TEXT REFERENCES categories(id),',
      '    linked_debt_id TEXT REFERENCES debts(id),',
      '    is_active INTEGER NOT NULL DEFAULT 1,',
      '    auto_post INTEGER NOT NULL DEFAULT 0,',
      '    created_at TEXT NOT NULL',
      ');',
      '',
      'CREATE TABLE IF NOT EXISTS transactions (',
      '    id TEXT PRIMARY KEY,',
      '    type TEXT NOT NULL,',
      '    amount_cents INTEGER NOT NULL CHECK(amount_cents > 0),',
      '    account_id TEXT NOT NULL,',
      '    destination_account_id TEXT,',
      '    category_id TEXT,',
      '    description TEXT,',
      '    transaction_date TEXT NOT NULL,',
      '    journal_entry_id TEXT,',
      '    is_superseded INTEGER NOT NULL DEFAULT 0,',
      '    created_at TEXT NOT NULL',
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

    const sqlStr = (val?: string | null) =>
      val != null && val !== '' ? `'${String(val).replace(/'/g, "''")}'` : 'NULL';

    for (const a of payload.accounts) {
      const safeCurrency = normalizeCurrencyCode(a.currencyCode).replace(/'/g, "''");
      const safeSubType = getAccountSubType(a).replace(/'/g, "''");
      lines.push(
        `INSERT INTO accounts (id, name, type, sub_type, is_system, currency_code, is_archived, created_at) VALUES ('${a.id}', '${a.name.replace(/'/g, "''")}', '${a.type}', '${safeSubType}', ${a.isSystem ? 1 : 0}, '${safeCurrency}', ${a.isArchived ? 1 : 0}, '${a.createdAt}');`
      );
    }

    for (const p of payload.parties) {
      lines.push(
        `INSERT INTO parties (id, name, phone, notes, is_archived, created_at) VALUES ('${p.id}', '${p.name.replace(/'/g, "''")}', ${sqlStr(p.phone)}, ${sqlStr(p.notes)}, ${p.isArchived ? 1 : 0}, '${p.createdAt}');`
      );
    }

    // Topological sort categories (parents before children) for FK compliance
    const catById = new Map(payload.categories.map((c) => [c.id, c]));
    const visitedCats = new Set<string>();
    const orderedCats: TransactionCategory[] = [];
    const visitCat = (c: TransactionCategory) => {
      if (visitedCats.has(c.id)) return;
      visitedCats.add(c.id);
      if (c.parentId && catById.has(c.parentId)) {
        visitCat(catById.get(c.parentId)!);
      }
      orderedCats.push(c);
    };
    for (const c of payload.categories) visitCat(c);

    for (const c of orderedCats) {
      const safeParent = c.parentId && catById.has(c.parentId) ? sqlStr(c.parentId) : 'NULL';
      lines.push(
        `INSERT INTO categories (id, name, type, color_hex, parent_id, sort_order, is_default, is_archived) VALUES ('${c.id}', '${c.name.replace(/'/g, "''")}', '${c.type}', '${c.colorHex}', ${safeParent}, ${c.sortOrder ?? 0}, ${c.isDefault ? 1 : 0}, ${c.isArchived ? 1 : 0});`
      );
    }

    for (const j of payload.entries) {
      lines.push(
        `INSERT INTO journal_entries (id, entry_type, description, occurrence_date, is_voided, void_reason, created_at) VALUES ('${j.id}', '${j.entryType}', '${j.description.replace(/'/g, "''")}', '${j.occurrenceDate}', ${j.isVoided ? 1 : 0}, ${sqlStr(j.voidReason)}, '${j.createdAt}');`
      );
    }

    for (const p of payload.postings) {
      lines.push(
        `INSERT INTO postings (id, entry_id, account_id, amount_cents, direction, account_movement_date, category_id, note) VALUES ('${p.id}', '${p.entryId}', '${p.accountId}', ${p.amountCents}, '${p.direction}', '${p.accountMovementDate}', ${sqlStr(p.categoryId)}, ${sqlStr(p.note)});`
      );
    }

    for (const d of payload.debts) {
      lines.push(
        `INSERT INTO debts (id, origin_entry_id, party_id, debt_type, principal_cents, outstanding_cents, due_date, status, created_at) VALUES ('${d.id}', '${d.originEntryId}', '${d.partyId}', '${d.debtType}', ${d.principalCents}, ${d.outstandingCents}, ${sqlStr(d.dueDate)}, '${d.status}', '${d.createdAt}');`
      );
    }

    for (const s of payload.settlementAllocations) {
      lines.push(
        `INSERT INTO settlement_allocations (id, settlement_entry_id, debt_id, allocated_cents, settlement_date) VALUES ('${s.id}', '${s.settlementEntryId}', '${s.debtId}', ${s.allocatedCents}, '${s.settlementDate}');`
      );
    }

    for (const cm of payload.commitments || []) {
      lines.push(
        `INSERT INTO commitments (id, title, direction, amount_cents, due_date, is_paid, linked_account_id, category_id, linked_debt_id, settlement_entry_id, recurring_rule_id, legacy_paid_unverified) VALUES ('${cm.id}', '${cm.title.replace(/'/g, "''")}', '${cm.direction || 'outflow'}', ${cm.amountCents}, '${cm.dueDate}', ${cm.isPaid ? 1 : 0}, ${sqlStr(cm.linkedAccountId)}, ${sqlStr(cm.categoryId)}, ${sqlStr(cm.linkedDebtId)}, ${sqlStr(cm.settlementEntryId)}, ${sqlStr(cm.recurringRuleId)}, ${cm.legacyPaidUnverified ? 1 : 0});`
      );
    }

    for (const cs of payload.commitmentSettlements || []) {
      lines.push(
        `INSERT INTO commitment_settlements (id, commitment_id, entry_id, amount_cents, settled_date, created_at) VALUES ('${cs.id}', '${cs.commitmentId}', '${cs.entryId}', ${cs.amountCents}, '${cs.settledDate}', '${cs.createdAt || ''}');`
      );
    }

    for (const g of payload.savingsGoals || []) {
      const createdAt = String((g as unknown as Record<string, unknown>).createdAt || '');
      lines.push(
        `INSERT INTO savings_goals (id, title, target_cents, current_allocated_cents, target_date, linked_account_id, status, created_at) VALUES ('${g.id}', '${g.title.replace(/'/g, "''")}', ${g.targetCents}, ${g.currentAllocatedCents}, ${sqlStr(g.targetDate)}, ${sqlStr(g.linkedAccountId)}, '${g.status || 'active'}', '${createdAt}');`
      );
    }

    for (const b of payload.budgets || []) {
      lines.push(
        `INSERT INTO budgets (id, category_id, month_iso, limit_cents, rollover_enabled, created_at, updated_at) VALUES ('${b.id}', '${b.categoryId}', '${b.monthIso}', ${b.limitCents}, ${b.rolloverEnabled ? 1 : 0}, '${b.createdAt}', '${b.updatedAt}');`
      );
    }

    for (const r of payload.recurringRules || []) {
      lines.push(
        `INSERT INTO recurring_rules (id, title, rule_type, amount_cents, frequency, interval, start_date, next_occurrence_date, end_date, account_id, destination_account_id, category_id, linked_debt_id, is_active, auto_post, created_at) VALUES ('${r.id}', '${r.title.replace(/'/g, "''")}', '${r.ruleType}', ${r.amountCents}, '${r.frequency}', ${r.interval}, '${r.startDate}', '${r.nextOccurrenceDate}', ${sqlStr(r.endDate)}, ${sqlStr(r.accountId)}, ${sqlStr(r.destinationAccountId)}, ${sqlStr(r.categoryId)}, ${sqlStr(r.linkedDebtId)}, ${r.isActive ? 1 : 0}, ${r.autoPost ? 1 : 0}, '${r.createdAt}');`
      );
    }

    for (const t of payload.transactions || []) {
      lines.push(
        `INSERT INTO transactions (id, type, amount_cents, account_id, destination_account_id, category_id, description, transaction_date, journal_entry_id, is_superseded, created_at) VALUES ('${t.id}', '${t.type}', ${t.amountCents}, '${t.accountId}', ${sqlStr(t.destinationAccountId)}, ${sqlStr(t.categoryId)}, ${sqlStr(t.description)}, '${t.transactionDate}', ${sqlStr(t.journalEntryId)}, ${t.isSuperseded ? 1 : 0}, '${t.createdAt}');`
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

### \`categories\`
| Column | Type | Constraints | Description |
|---|---|---|---|
| \`id\` | TEXT | PRIMARY KEY | Category identifier |
| \`name\` | TEXT | NOT NULL | Display name |
| \`type\` | TEXT | NOT NULL | Enum: \`income\` or \`expense\` |
| \`color_hex\` | TEXT | NOT NULL | Hex token color |
| \`parent_id\` | TEXT | NULLABLE | Optional parent \`categories.id\` for hierarchy rollup |
| \`sort_order\` | INTEGER | DEFAULT 0 | Display ordering |
| \`is_default\` | INTEGER | DEFAULT 0 | 1 if canonical starter category |
| \`is_archived\` | INTEGER | DEFAULT 0 | 1 if archived |

### \`commitments\`
| Column | Type | Constraints | Description |
|---|---|---|---|
| \`id\` | TEXT | PRIMARY KEY | Commitment identifier |
| \`title\` | TEXT | NOT NULL | Bill or expected income label |
| \`direction\` | TEXT | NOT NULL | \`outflow\` (bill) or \`inflow\` (expected income) |
| \`amount_cents\` | INTEGER | NOT NULL (> 0) | Scheduled amount in minor units |
| \`due_date\` | TEXT | NOT NULL | Due date (\`YYYY-MM-DD\`) |
| \`is_paid\` | INTEGER | DEFAULT 0 | 1 if settled |
| \`linked_account_id\` | TEXT | NULLABLE | Optional FK to \`accounts.id\` |
| \`category_id\` | TEXT | NULLABLE | Optional FK to \`categories.id\` |
| \`linked_debt_id\` | TEXT | NULLABLE | Optional FK to \`debts.id\` |
| \`settlement_entry_id\` | TEXT | NULLABLE | Latest FK to \`journal_entries.id\` |
| \`recurring_rule_id\` | TEXT | NULLABLE | Optional recurring rule ID |
| \`legacy_paid_unverified\` | INTEGER | DEFAULT 0 | Legacy paid state without cash ledger entry |

### \`commitment_settlements\`
| Column | Type | Constraints | Description |
|---|---|---|---|
| \`id\` | TEXT | PRIMARY KEY | Installment settlement ID |
| \`commitment_id\` | TEXT | NOT NULL | Foreign key to \`commitments.id\` |
| \`entry_id\` | TEXT | NOT NULL | Foreign key to \`journal_entries.id\` |
| \`amount_cents\` | INTEGER | NOT NULL (> 0) | Settled installment amount in minor units |
| \`settled_date\` | TEXT | NOT NULL | Settlement date (\`YYYY-MM-DD\`) |
| \`created_at\` | TEXT | NOT NULL | ISO 8601 UTC timestamp |

### \`savings_goals\`
| Column | Type | Constraints | Description |
|---|---|---|---|
| \`id\` | TEXT | PRIMARY KEY | Savings goal ID |
| \`title\` | TEXT | NOT NULL | Goal title |
| \`target_cents\` | INTEGER | NOT NULL (> 0) | Target amount in minor units |
| \`current_allocated_cents\` | INTEGER | DEFAULT 0 | Allocated amount (synced to vault balance if linked) |
| \`target_date\` | TEXT | NULLABLE | Optional target date (\`YYYY-MM-DD\`) |
| \`linked_account_id\` | TEXT | NULLABLE | Optional vault \`accounts.id\` |
| \`status\` | TEXT | NOT NULL | \`active\`, \`completed\`, or \`archived\` |
| \`created_at\` | TEXT | NOT NULL | ISO 8601 UTC timestamp |

### \`budgets\`
| Column | Type | Constraints | Description |
|---|---|---|---|
| \`id\` | TEXT | PRIMARY KEY | Budget record ID |
| \`category_id\` | TEXT | NOT NULL | Foreign key to \`categories.id\` |
| \`month_iso\` | TEXT | NOT NULL | Month key (\`YYYY-MM\`) |
| \`limit_cents\` | INTEGER | NOT NULL (> 0) | Monthly spending limit in minor units |
| \`rollover_enabled\` | INTEGER | DEFAULT 0 | 1 if rollover enabled |
| \`created_at\` | TEXT | NOT NULL | ISO 8601 UTC timestamp |
| \`updated_at\` | TEXT | NOT NULL | ISO 8601 UTC timestamp |

### \`recurring_rules\`
| Column | Type | Constraints | Description |
|---|---|---|---|
| \`id\` | TEXT | PRIMARY KEY | Recurring schedule ID |
| \`title\` | TEXT | NOT NULL | Rule label |
| \`rule_type\` | TEXT | NOT NULL | \`expense\`, \`income\`, \`transfer\`, or \`commitment\` |
| \`amount_cents\` | INTEGER | NOT NULL (> 0) | Amount in minor units |
| \`frequency\` | TEXT | NOT NULL | \`weekly\`, \`biweekly\`, \`monthly\`, \`quarterly\`, \`yearly\` |
| \`interval\` | INTEGER | DEFAULT 1 | Interval multiplier |
| \`start_date\` | TEXT | NOT NULL | Start date (\`YYYY-MM-DD\`) |
| \`next_occurrence_date\` | TEXT | NOT NULL | Next due date (\`YYYY-MM-DD\`) |
| \`end_date\` | TEXT | NULLABLE | Optional end date (\`YYYY-MM-DD\`) |
| \`account_id\` | TEXT | NULLABLE | Source \`accounts.id\` |
| \`destination_account_id\` | TEXT | NULLABLE | Destination \`accounts.id\` for transfers |
| \`category_id\` | TEXT | NULLABLE | Category \`categories.id\` |
| \`linked_debt_id\` | TEXT | NULLABLE | Linked \`debts.id\` |
| \`is_active\` | INTEGER | DEFAULT 1 | 1 if active |
| \`auto_post\` | INTEGER | DEFAULT 0 | Opt-in auto-post flag |
| \`created_at\` | TEXT | NOT NULL | ISO 8601 UTC timestamp |

### \`transactions\`
| Column | Type | Constraints | Description |
|---|---|---|---|
| \`id\` | TEXT | PRIMARY KEY | Legacy/simplified transaction ID |
| \`type\` | TEXT | NOT NULL | \`income\`, \`expense\`, or \`transfer\` |
| \`amount_cents\` | INTEGER | NOT NULL (> 0) | Amount in minor units |
| \`account_id\` | TEXT | NOT NULL | Source account ID |
| \`destination_account_id\` | TEXT | NULLABLE | Destination account ID |
| \`category_id\` | TEXT | NULLABLE | Category ID |
| \`description\` | TEXT | NULLABLE | Memo |
| \`transaction_date\` | TEXT | NOT NULL | Date (\`YYYY-MM-DD\`) |
| \`journal_entry_id\` | TEXT | NULLABLE | Linked \`journal_entries.id\` |
| \`is_superseded\` | INTEGER | DEFAULT 0 | 1 if superseded |
| \`created_at\` | TEXT | NOT NULL | ISO 8601 UTC timestamp |
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

    const commitments = payload.commitments || [];
    const commitmentSettlements = payload.commitmentSettlements || [];
    const savingsGoals = payload.savingsGoals || [];
    const budgets = payload.budgets || [];
    const recurringRules = payload.recurringRules || [];
    const transactions = payload.transactions || [];

    // 1. All 13 Normalized CSVs (with UTF-8 BOM)
    const accountsCsv = this.exportAccountsCsv(payload.accounts);
    const categoriesCsv = this.exportCategoriesCsv(payload.categories);
    const partiesCsv = this.exportPartiesCsv(payload.parties);
    const entriesCsv = this.exportJournalEntriesCsv({
      accounts: payload.accounts,
      entries: payload.entries,
      postings: payload.postings,
      debts: payload.debts,
      allocations: payload.settlementAllocations,
    });
    const postingsCsv = this.exportPostingsCsv(payload.postings);
    const debtsCsv = this.exportDebtsCsv({
      accounts: payload.accounts,
      entries: payload.entries,
      postings: payload.postings,
      debts: payload.debts,
      allocations: payload.settlementAllocations,
    });
    const allocationsCsv = this.exportSettlementAllocationsCsv(payload.settlementAllocations);
    const commitmentsCsv = this.exportCommitmentsCsv(commitments);
    const commitmentSettlementsCsv = this.exportCommitmentSettlementsCsv(commitmentSettlements);
    const savingsGoalsCsv = this.exportSavingsGoalsCsv(savingsGoals);
    const budgetsCsv = this.exportBudgetsCsv(budgets);
    const recurringRulesCsv = this.exportRecurringRulesCsv(recurringRules);
    const transactionsCsv = this.exportTransactionsCsv(transactions);

    zip.file('csv/accounts.csv', accountsCsv);
    zip.file('csv/categories.csv', categoriesCsv);
    zip.file('csv/parties.csv', partiesCsv);
    zip.file('csv/journal_entries.csv', entriesCsv);
    zip.file('csv/postings.csv', postingsCsv);
    zip.file('csv/debts.csv', debtsCsv);
    zip.file('csv/settlement_allocations.csv', allocationsCsv);
    zip.file('csv/commitments.csv', commitmentsCsv);
    zip.file('csv/commitment_settlements.csv', commitmentSettlementsCsv);
    zip.file('csv/savings_goals.csv', savingsGoalsCsv);
    zip.file('csv/budgets.csv', budgetsCsv);
    zip.file('csv/recurring_rules.csv', recurringRulesCsv);
    zip.file('csv/transactions.csv', transactionsCsv);

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
      exportScope: 'finance_only',
      exportedAtUtc: nowIso,
      currency: 'ETB',
      accountingModel: 'Simplified Double-Entry Balanced Ledger',
      fileChecksums: {
        'csv/accounts.csv': { rows: payload.accounts.length, sha256: await computeSha256(accountsCsv) },
        'csv/categories.csv': { rows: payload.categories.length, sha256: await computeSha256(categoriesCsv) },
        'csv/parties.csv': { rows: payload.parties.length, sha256: await computeSha256(partiesCsv) },
        'csv/journal_entries.csv': { rows: payload.entries.length, sha256: await computeSha256(entriesCsv) },
        'csv/postings.csv': { rows: payload.postings.length, sha256: await computeSha256(postingsCsv) },
        'csv/debts.csv': { rows: payload.debts.length, sha256: await computeSha256(debtsCsv) },
        'csv/settlement_allocations.csv': { rows: payload.settlementAllocations.length, sha256: await computeSha256(allocationsCsv) },
        'csv/commitments.csv': { rows: commitments.length, sha256: await computeSha256(commitmentsCsv) },
        'csv/commitment_settlements.csv': { rows: commitmentSettlements.length, sha256: await computeSha256(commitmentSettlementsCsv) },
        'csv/savings_goals.csv': { rows: savingsGoals.length, sha256: await computeSha256(savingsGoalsCsv) },
        'csv/budgets.csv': { rows: budgets.length, sha256: await computeSha256(budgetsCsv) },
        'csv/recurring_rules.csv': { rows: recurringRules.length, sha256: await computeSha256(recurringRulesCsv) },
        'csv/transactions.csv': { rows: transactions.length, sha256: await computeSha256(transactionsCsv) },
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
