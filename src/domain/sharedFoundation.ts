/**
 * SHARED FOUNDATION CORE (Single Source of Truth)
 * Generated automatically from /shared_foundation/*.json
 * DO NOT EDIT DIRECTLY. Run "npm run sync-foundation" to regenerate.
 */

export const SHARED_DESIGN_TOKENS = {
  "$schema": "http://json-schema.org/draft-07/schema#",
  "version": "1.1.0",
  "name": "Daywell Design Tokens",
  "colors": {
    "primary": {
      "emerald": "#1B4D3E",
      "emeraldDark": "#153E32",
      "emeraldLight": "#245E4D",
      "darkMode": "#81C784",
      "onLight": "#FFFFFF",
      "onDark": "#0E241C"
    },
    "secondary": {
      "mint": "#E0EFE8",
      "mintDark": "#1D382E",
      "mintLight": "#F0F7F4",
      "onLight": "#1B4D3E",
      "onDark": "#81C784"
    },
    "surface": {
      "canvasLight": "#FAF9F5",
      "canvasDark": "#121816",
      "subtleLight": "#F2F0E8",
      "subtleDark": "#161E1B",
      "cardLight": "#FFFFFF",
      "cardDark": "#1A2320",
      "elevatedLight": "#FFFFFF",
      "elevatedDark": "#212C28",
      "borderLight": "#E5E7EB",
      "borderDark": "#2B3A34",
      "dividerLight": "#ECEAE3",
      "dividerDark": "#222E29"
    },
    "text": {
      "primaryLight": "#111827",
      "primaryDark": "#F9FAFB",
      "secondaryLight": "#4B5563",
      "secondaryDark": "#CBD5E1",
      "mutedLight": "#6B7280",
      "mutedDark": "#9CA3AF",
      "disabledLight": "#9CA3AF",
      "disabledDark": "#5C6B64"
    },
    "semantic": {
      "income": "#10B981",
      "onIncome": "#052E16",
      "incomeContainerLight": "#ECFDF5",
      "onIncomeContainerLight": "#065F46",
      "incomeContainerDark": "#0D3326",
      "onIncomeContainerDark": "#6EE7B7",
      "expense": "#EF4444",
      "onExpense": "#090D16",
      "expenseContainerLight": "#FEF2F2",
      "onExpenseContainerLight": "#991B1B",
      "expenseContainerDark": "#3B1517",
      "onExpenseContainerDark": "#FCA5A5",
      "transfer": "#0D9488",
      "onTransfer": "#021615",
      "transferContainerLight": "#F0FDFA",
      "onTransferContainerLight": "#115E59",
      "transferContainerDark": "#0E3330",
      "onTransferContainerDark": "#5EEAD4",
      "success": "#15803D",
      "onSuccess": "#FFFFFF",
      "successContainerLight": "#F0FDF4",
      "onSuccessContainerLight": "#166534",
      "successContainerDark": "#11331F",
      "onSuccessContainerDark": "#86EFAC",
      "error": "#DC2626",
      "onError": "#FFFFFF",
      "errorContainerLight": "#FEE2E2",
      "onErrorContainerLight": "#7F1D1D",
      "errorContainerDark": "#451215",
      "onErrorContainerDark": "#FECACA",
      "warning": "#F59E0B",
      "onWarning": "#111827",
      "warningContainerLight": "#FFFBEB",
      "onWarningContainerLight": "#92400E",
      "warningContainerDark": "#36250B",
      "onWarningContainerDark": "#FCD34D",
      "info": "#3B82F6",
      "onInfo": "#0B1120",
      "infoContainerLight": "#EFF6FF",
      "onInfoContainerLight": "#1E40AF",
      "infoContainerDark": "#132645",
      "onInfoContainerDark": "#93C5FD"
    }
  },
  "typography": {
    "fontFamilySerif": "Newsreader, Georgia, serif",
    "fontFamilySans": "Inter, -apple-system, BlinkMacSystemFont, sans-serif",
    "fontFamilyMono": "JetBrains Mono, monospace",
    "scale": {
      "display": {
        "fontSize": 28,
        "lineHeight": 36,
        "fontWeight": 700,
        "letterSpacing": -0.5,
        "fontFamily": "serif",
        "tabularFigures": false
      },
      "heading": {
        "fontSize": 22,
        "lineHeight": 28,
        "fontWeight": 700,
        "letterSpacing": -0.3,
        "fontFamily": "serif",
        "tabularFigures": false
      },
      "title": {
        "fontSize": 17,
        "lineHeight": 24,
        "fontWeight": 600,
        "letterSpacing": -0.1,
        "fontFamily": "sans",
        "tabularFigures": false
      },
      "body": {
        "fontSize": 14,
        "lineHeight": 20,
        "fontWeight": 400,
        "letterSpacing": 0,
        "fontFamily": "sans",
        "tabularFigures": false
      },
      "bodyCompact": {
        "fontSize": 13,
        "lineHeight": 18,
        "fontWeight": 400,
        "letterSpacing": 0,
        "fontFamily": "sans",
        "tabularFigures": false
      },
      "label": {
        "fontSize": 12,
        "lineHeight": 16,
        "fontWeight": 600,
        "letterSpacing": 0.2,
        "fontFamily": "sans",
        "tabularFigures": false
      },
      "caption": {
        "fontSize": 11,
        "lineHeight": 14,
        "fontWeight": 500,
        "letterSpacing": 0.2,
        "fontFamily": "sans",
        "tabularFigures": false
      },
      "numericHero": {
        "fontSize": 32,
        "lineHeight": 38,
        "fontWeight": 700,
        "letterSpacing": -0.5,
        "fontFamily": "sans",
        "tabularFigures": true
      },
      "numericBody": {
        "fontSize": 15,
        "lineHeight": 20,
        "fontWeight": 600,
        "letterSpacing": 0,
        "fontFamily": "sans",
        "tabularFigures": true
      },
      "mono": {
        "fontSize": 12,
        "lineHeight": 16,
        "fontWeight": 500,
        "letterSpacing": 0,
        "fontFamily": "mono",
        "tabularFigures": true
      }
    }
  },
  "spacing": {
    "xs": 4,
    "sm": 8,
    "compact": 12,
    "md": 16,
    "lg": 24,
    "xl": 32
  },
  "radii": {
    "sm": 8,
    "md": 12,
    "lg": 16,
    "xl": 20,
    "sheet": 24,
    "full": 9999
  },
  "elevation": {
    "none": 0,
    "low": 1,
    "medium": 3,
    "high": 6
  },
  "breakpoints": {
    "medium": 600,
    "expanded": 840,
    "maxContentWidth": 720,
    "maxWideWidth": 1120
  }
} as const;

export type DaywellDesignTokens = typeof SHARED_DESIGN_TOKENS;

export const SHARED_BUSINESS_RULES = {
  "version": "1.0.0",
  "finance": {
    "currencyCode": "ETB",
    "minorUnitsPerMajor": 100,
    "rules": {
      "integerCentsOnly": true,
      "rejectZeroOrNegativeAmount": true,
      "rejectIdenticalTransferAccounts": true,
      "transferPreservesCombinedBalance": true,
      "guardAccountDeletionIfTransactionsExist": true,
      "guardCategoryDeletionIfTransactionsExist": true
    },
    "formulas": {
      "accountBalance": "openingBalanceCents + totalIncomeCents - totalExpenseCents + incomingTransfersCents - outgoingTransfersCents",
      "combinedBalance": "sumOfAllActiveAssetAccountBalances"
    }
  },
  "tasks": {
    "priorityWeights": {
      "urgent": 4,
      "high": 3,
      "medium": 2,
      "low": 1
    },
    "defaultPriority": "medium",
    "defaultStatus": "not_started"
  },
  "calendar": {
    "system": "ethiopian_dual",
    "monthsCount": 13,
    "standardMonthDays": 30,
    "pagumeStandardDays": 5,
    "pagumeLeapDays": 6,
    "pagumeLeapRule": "year % 4 == 3",
    "canonicalDateFormat": "YYYY-MM-DD",
    "timeConvention": "UTC+3",
    "fixedUtcOffsetMinutes": 180
  }
} as const;

export const CANONICAL_SEED_DATABASE = {
  "schemaVersion": 5,
  "appVersion": "1.0.2+3",
  "exportedAt": "2026-11-11T00:00:00.000Z",
  "isFinanceSetupCompleted": false,
  "openingBalanceCents": 0,
  "accounts": [],
  "categories": [
    {
      "id": "cat-food",
      "name": "Food",
      "type": "expense",
      "colorHex": "#EF4444",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-transport",
      "name": "Transport",
      "type": "expense",
      "colorHex": "#F97316",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-housing",
      "name": "Housing",
      "type": "expense",
      "colorHex": "#F59E0B",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-utilities",
      "name": "Utilities",
      "type": "expense",
      "colorHex": "#EAB308",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-comm",
      "name": "Communication",
      "type": "expense",
      "colorHex": "#84CC16",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-other-exp",
      "name": "Other",
      "type": "expense",
      "colorHex": "#94A3B8",
      "isDefault": true,
      "isArchived": false
    },
    {
      "id": "cat-salary",
      "name": "Salary",
      "type": "income",
      "colorHex": "#10B981",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-freelance",
      "name": "Freelance & Business",
      "type": "income",
      "colorHex": "#06B6D4",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-asaye",
      "name": "From Asaye",
      "type": "income",
      "colorHex": "#3B82F6",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-invest",
      "name": "Investments & Returns",
      "type": "income",
      "colorHex": "#8B5CF6",
      "isDefault": false,
      "isArchived": false
    },
    {
      "id": "cat-other-inc",
      "name": "Other Income",
      "type": "income",
      "colorHex": "#64748B",
      "isDefault": true,
      "isArchived": false
    }
  ],
  "transactions": [],
  "tasks": [],
  "notes": [],
  "projects": [],
  "goals": [],
  "inboxItems": [],
  "calendarEvents": []
} as const;

export interface SharedTask {
  id: string;
  title: string;
  description?: string;
  status: 'not_started' | 'in_progress' | 'completed' | 'cancelled' | 'inbox';
  priority: 'low' | 'medium' | 'high' | 'urgent';
  dueDate?: string;
  scheduledDate?: string;
  projectId?: string;
  milestoneId?: string;
  estimatedDurationMinutes?: number;
  subtasks?: Array<{ title: string; done: boolean }>;
  labels?: string[];
  isPinned?: boolean;
  isMyDay?: boolean;
  recurrenceRule?: string;
  createdAt: string;
  updatedAt?: string;
}

export interface SharedNote {
  id: string;
  title: string;
  body: string;
  folder?: string;
  tags: string[];
  isPinned: boolean;
  isFavorite?: boolean;
  isArchived: boolean;
  isTrashed?: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface SharedCalendarEvent {
  id: string;
  title: string;
  date: string;
  endDate?: string;
  startTime?: string;
  endTime?: string;
  isAllDay: boolean;
  category: string;
  colorHex: string;
  hasReminder: boolean;
  notes?: string;
  createdAt: string;
  updatedAt: string;
}

export type SharedAccountSubType =
  | 'cash'
  | 'bank'
  | 'mobile_money'
  | 'savings_vault'
  | 'credit_card'
  | 'receivable'
  | 'payable'
  | 'opening_equity'
  | 'nominal_income'
  | 'nominal_expense'
  | 'legacy_clearing';

export const SYSTEM_CONTROL_ACCOUNT_IDS = {
  equity: 'acc-sys-equity',
  income: 'acc-sys-income',
  expense: 'acc-sys-expense',
  receivable: 'acc-sys-receivable',
  payable: 'acc-sys-payable',
  legacyOffset: 'acc-sys-legacy-offset',
} as const;

export interface SharedAccount {
  id: string;
  name: string;
  type: 'asset' | 'liability' | 'equity' | 'revenue' | 'income' | 'expense';
  subType?: SharedAccountSubType;
  isSystem?: boolean;
  currencyCode: string;
  openingBalanceCents: number;
  openingBalanceDate?: string;
  isArchived: boolean;
}

export interface SharedCategory {
  id: string;
  name: string;
  type: 'income' | 'expense';
  colorHex: string;
  parentId?: string;
  sortOrder?: number;
  isDefault: boolean;
  isArchived: boolean;
}

export interface SharedTransaction {
  id: string;
  amountCents: number;
  type: 'income' | 'expense' | 'transfer';
  categoryId?: string;
  categoryName?: string;
  accountId: string;
  accountName?: string;
  destinationAccountId?: string;
  destinationAccountName?: string;
  transactionDate: string;
  note?: string;
  payee?: string;
  isSuperseded?: boolean;
}

export interface SharedCommitment {
  id: string;
  title: string;
  amountCents: number;
  dueDate: string;
  isPaid: boolean;
  recurringRule?: string;
  linkedAccountId?: string;
  categoryId?: string;
  linkedDebtId?: string;
  settlementEntryId?: string;
  recurringRuleId?: string;
  direction?: 'outflow' | 'inflow';
  legacyPaidUnverified?: boolean;
}

export interface SharedCommitmentSettlement {
  id: string;
  commitmentId: string;
  entryId: string;
  amountCents: number;
  settledDate: string;
  createdAt: string;
}

export interface SharedSavingsGoal {
  id: string;
  title: string;
  targetCents: number;
  currentAllocatedCents: number;
  targetDate?: string;
  linkedAccountId?: string;
  status?: 'active' | 'completed' | 'archived';
}

export interface SharedBudget {
  id: string;
  categoryId: string;
  monthIso: string;
  limitCents: number;
  rolloverEnabled: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface SharedRecurringRule {
  id: string;
  title: string;
  ruleType: 'expense' | 'income' | 'transfer' | 'commitment';
  amountCents: number;
  frequency: 'weekly' | 'biweekly' | 'monthly' | 'quarterly' | 'yearly';
  interval: number;
  startDate: string;
  nextOccurrenceDate: string;
  endDate?: string;
  accountId?: string;
  destinationAccountId?: string;
  categoryId?: string;
  linkedDebtId?: string;
  isActive: boolean;
  autoPost: boolean;
  createdAt: string;
}

export interface SharedProject {
  id: string;
  title: string;
  description?: string;
  status: 'active' | 'completed' | 'on_hold';
  targetDate?: string;
  goalId?: string;
}

export interface SharedGoal {
  id: string;
  title: string;
  description?: string;
  status: 'active' | 'achieved' | 'archived';
  targetDate?: string;
}

export interface SharedInboxItem {
  id: string;
  rawText: string;
  category: 'task' | 'idea' | 'expense' | 'note' | 'problem' | 'decision' | 'general';
  isProcessed: boolean;
  createdAt: string;
}

export interface SharedReminder {
  id: string;
  targetId: string;
  targetType: 'task' | 'commitment' | 'calendar_event' | 'note' | 'custom';
  triggerTimeUtc: string;
  isActive: boolean;
  createdAt: string;
  title?: string;
  channelId?: string;
}

export interface SharedAppSetting {
  key: string;
  value: string;
  updatedAt?: string;
}

export interface SharedDatabaseState {
  schemaVersion: number;
  appVersion: string;
  exportedAt: string;
  isFinanceSetupCompleted: boolean;
  openingBalanceCents: number;
  accounts: SharedAccount[];
  categories: SharedCategory[];
  transactions: SharedTransaction[];
  commitments?: SharedCommitment[];
  commitmentSettlements?: SharedCommitmentSettlement[];
  savingsGoals?: SharedSavingsGoal[];
  budgets?: SharedBudget[];
  recurringRules?: SharedRecurringRule[];
  tasks: SharedTask[];
  notes: SharedNote[];
  projects: SharedProject[];
  goals: SharedGoal[];
  inboxItems: SharedInboxItem[];
  calendarEvents?: SharedCalendarEvent[];
  reminders?: SharedReminder[];
  appSettings?: SharedAppSetting[];
}

/**
 * Shared Business Rule: Account Balance Calculation
 * Balance = Opening Balance + Income - Expenses + Incoming Transfers - Outgoing Transfers
 */
export function calculateSharedAccountBalance(
  account: SharedAccount,
  transactions: SharedTransaction[]
): number {
  let balance = account.openingBalanceCents || 0;
  for (const tx of transactions) {
    if (tx.isSuperseded) continue;
    if (tx.type === 'income' && tx.accountId === account.id) {
      balance += tx.amountCents;
    } else if (tx.type === 'expense' && tx.accountId === account.id) {
      balance -= tx.amountCents;
    } else if (tx.type === 'transfer') {
      if (tx.accountId === account.id) {
        balance -= tx.amountCents;
      }
      if (tx.destinationAccountId === account.id) {
        balance += tx.amountCents;
      }
    }
  }
  return balance;
}

/**
 * Shared Business Rule: Combined Active Asset Balance
 */
export function calculateSharedCombinedBalance(
  accounts: SharedAccount[],
  transactions: SharedTransaction[]
): number {
  return accounts
    .filter(
      (a) =>
        !a.isArchived &&
        !((a as unknown as { isSystem?: boolean }).isSystem === true) &&
        a.type === 'asset' &&
        (a.currencyCode ?? '').trim().toUpperCase() === 'ETB'
    )
    .reduce((sum, a) => sum + calculateSharedAccountBalance(a, transactions), 0);
}

/**
 * Shared Business Rule: Safe Account Deletion Guard
 */
export function canDeleteSharedAccount(
  accountId: string,
  transactions: SharedTransaction[]
): boolean {
  return !transactions.some(
    (t) => !t.isSuperseded && (t.accountId === accountId || t.destinationAccountId === accountId)
  );
}

/**
 * Shared Business Rule: Safe Category Deletion Guard
 */
export function canDeleteSharedCategory(
  categoryId: string,
  categoryName: string,
  transactions: SharedTransaction[]
): boolean {
  return !transactions.some(
    (t) =>
      !t.isSuperseded && (t.categoryId === categoryId || t.categoryName === categoryName)
  );
}

/**
 * Shared Business Rule: Validate Transfer
 */
export function validateSharedTransfer(
  fromAccountId: string,
  toAccountId: string,
  amountCents: number
): { valid: boolean; error?: string } {
  if (!fromAccountId || !toAccountId) {
    return { valid: false, error: 'Source and destination accounts are required.' };
  }
  if (fromAccountId === toAccountId) {
    return { valid: false, error: 'Source and destination accounts cannot be identical.' };
  }
  if (!Number.isInteger(amountCents) || amountCents <= 0) {
    return { valid: false, error: 'Transfer amount must be a positive integer in cents.' };
  }
  return { valid: true };
}
/**
 * Shared Business Rule: Total Income Calculation
 */
export function calculateSharedTotalIncome(
  transactions: SharedTransaction[],
  accountId?: string
): number {
  return transactions
    .filter((t) => !t.isSuperseded && t.type === 'income' && (!accountId || t.accountId === accountId))
    .reduce((sum, t) => sum + t.amountCents, 0);
}

/**
 * Shared Business Rule: Total Expense Calculation
 */
export function calculateSharedTotalExpense(
  transactions: SharedTransaction[],
  accountId?: string
): number {
  return transactions
    .filter((t) => !t.isSuperseded && t.type === 'expense' && (!accountId || t.accountId === accountId))
    .reduce((sum, t) => sum + t.amountCents, 0);
}

/**
 * Known demonstration seed record identifiers to safely purge from legacy storage
 */
export const KNOWN_SEED_IDS = {
  accounts: ['acc-cbe', 'acc-boa', 'acc-dashen', 'acc-telebirr', 'acc-cash'],
  transactions: ['tx-seed-1', 'tx-seed-2', 'tx-seed-3'],
  tasks: ['task-seed-1', 'task-seed-2', 't-1', 't-2', 't-3', 't-4', 't-5', 't-6', 't-7'],
  notes: ['note-seed-1', 'note-1', 'note-2', 'note-3'],
  projects: ['proj-seed-1', 'proj-1', 'proj-2', 'proj-3'],
  goals: ['goal-seed-1', 'goal-1', 'goal-2'],
  events: ['evt-1', 'evt-2', 'evt-3', 'evt-4'],
  commitments: ['com-1', 'com-2'],
  savingsGoals: ['sav-1', 'sav-2'],
  inboxItems: ['inbox-1'],
  parties: ['party-abebe', 'party-landlord', 'party-boss'],
} as const;

export function isKnownSeedId(id: string): boolean {
  return Object.values(KNOWN_SEED_IDS).some((ids) => (ids as readonly string[]).includes(id));
}
