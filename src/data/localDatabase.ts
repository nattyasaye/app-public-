/**
 * Offline Local Database and Repository implementation using localStorage.
 * Simulates SQLite/Room/Drift local persistence with UUIDs, UTC timestamps, and ACID-like state updates.
 */

import type {
  LocalInboxItem,
  LocalGoal,
  LocalProject,
  LocalMilestone,
  LocalTask,
  LocalFinancialCategory,
  LocalFinancialTransaction,
  LocalCommitment,
  LocalFinancialCommitment,
  LocalSavingsGoal,
  LocalNote,
  LocalReminder,
  LocalBackupLog,
  LocalDatabaseState,
} from '../domain/backupTypes';

export type {
  LocalInboxItem,
  LocalGoal,
  LocalProject,
  LocalMilestone,
  LocalTask,
  LocalFinancialCategory,
  LocalFinancialTransaction,
  LocalCommitment,
  LocalFinancialCommitment,
  LocalSavingsGoal,
  LocalNote,
  LocalReminder,
  LocalBackupLog,
  LocalDatabaseState,
};

const STORAGE_KEY = 'personal_management_offline_db_v1';

export const DEFAULT_CATEGORIES: LocalFinancialCategory[] = [
  { id: 'cat-sal', name: 'ደመወዝ (Salary)', type: 'income', colorHex: '#2E7D32', isDefault: true },
  { id: 'cat-bus', name: 'ንግድ/ትርፍ (Business Income)', type: 'income', colorHex: '#388E3C', isDefault: true },
  { id: 'cat-groc', name: 'ምግብና ሸቀጣ ሸቀጥ (Groceries)', type: 'expense', colorHex: '#E53935', isDefault: true },
  { id: 'cat-rent', name: 'ቤት ኪራይ (Rent)', type: 'expense', colorHex: '#D81B60', isDefault: true },
  { id: 'cat-trans', name: 'ትራንስፖርት (Transport)', type: 'expense', colorHex: '#FB8C00', isDefault: true },
  { id: 'cat-util', name: 'መብራትና ውኃ (Utilities)', type: 'expense', colorHex: '#039BE5', isDefault: true },
  { id: 'cat-health', name: 'ጤና (Healthcare)', type: 'expense', colorHex: '#8E24AA', isDefault: true },
  { id: 'cat-sav', name: 'ቁጠባ (Savings Allocation)', type: 'expense', colorHex: '#00897B', isDefault: true },
];

export const INITIAL_DEFAULT_STATE: LocalDatabaseState = {
  version: 3,
  inbox: [
    {
      id: 'inbox-1',
      rawText: 'Pay monthly house rent (ቤት ኪራይ) to landlord before 30th',
      category: 'expense',
      isProcessed: false,
      createdAtUtc: new Date(Date.now() - 3600000 * 2).toISOString(),
    },
    {
      id: 'inbox-2',
      rawText: 'Reflect on Amharic proverb: ቀስ በቀስ ዕንቁላል በእግሩ ይሄዳል',
      category: 'note',
      isProcessed: false,
      createdAtUtc: new Date(Date.now() - 3600000 * 5).toISOString(),
    },
    {
      id: 'inbox-3',
      rawText: 'Check solar battery voltage and inverter cables',
      category: 'task',
      isProcessed: false,
      createdAtUtc: new Date(Date.now() - 3600000 * 12).toISOString(),
    },
  ],
  goals: [
    {
      id: 'goal-1',
      title: 'Financial Independence & Safety Reserve',
      description: 'Build a 6-month buffer in ETB and eliminate unnecessary recurring expenses.',
      targetDateUtc: new Date(Date.now() + 86400000 * 180).toISOString(),
      status: 'active',
      createdAtUtc: new Date().toISOString(),
    },
    {
      id: 'goal-2',
      title: 'Long-term Knowledge & Personal Mastery',
      description: 'Master systems programming, Amharic language preservation, and health habits.',
      targetDateUtc: new Date(Date.now() + 86400000 * 365).toISOString(),
      status: 'active',
      createdAtUtc: new Date().toISOString(),
    },
  ],
  projects: [
    {
      id: 'proj-1',
      goalId: 'goal-1',
      title: 'Monthly Cashflow Audit & Savings Allocation',
      description: 'Reconcile all recorded income and expenses; ensure savings allocation is funded.',
      status: 'active',
      targetDateUtc: new Date(Date.now() + 86400000 * 30).toISOString(),
      createdAtUtc: new Date().toISOString(),
    },
    {
      id: 'proj-2',
      goalId: 'goal-2',
      title: 'Home Solar & Hardware Maintenance',
      description: 'Inspect electrical grounding, clean panels, and maintain offline workstations.',
      status: 'active',
      targetDateUtc: new Date(Date.now() + 86400000 * 14).toISOString(),
      createdAtUtc: new Date().toISOString(),
    },
    {
      id: 'proj-3',
      title: 'Stand-alone Personal Archive System',
      description: 'Project without a goal: organize offline PDFs, tax receipts, and certificates.',
      status: 'active',
      createdAtUtc: new Date().toISOString(),
    },
  ],
  milestones: [
    {
      id: 'ms-1',
      projectId: 'proj-1',
      title: 'Complete Week 1 receipt reconciliation',
      dueDateUtc: new Date(Date.now() + 86400000 * 7).toISOString(),
      isCompleted: true,
      createdAtUtc: new Date().toISOString(),
    },
    {
      id: 'ms-2',
      projectId: 'proj-1',
      title: 'Transfer 5,000 ETB to Emergency Reserve',
      dueDateUtc: new Date(Date.now() + 86400000 * 20).toISOString(),
      isCompleted: false,
      createdAtUtc: new Date().toISOString(),
    },
    {
      id: 'ms-3',
      projectId: 'proj-2',
      title: 'Test battery capacity under full load',
      dueDateUtc: new Date(Date.now() + 86400000 * 5).toISOString(),
      isCompleted: false,
      createdAtUtc: new Date().toISOString(),
    },
  ],
  tasks: [
    {
      id: 'task-1',
      title: 'Audit monthly living expenses and ETB budget',
      description: 'Reconcile actual receipts with recorded transactions',
      status: 'in_progress',
      priority: 'urgent',
      dueDateUtc: new Date().toISOString(),
      projectId: 'proj-1',
      projectName: 'Monthly Cashflow Audit & Savings Allocation',
      milestoneId: 'ms-1',
      estimatedDurationMinutes: 45,
      createdAtUtc: new Date().toISOString(),
      updatedAtUtc: new Date().toISOString(),
    },
    {
      id: 'task-2',
      title: 'Check solar battery voltage and inverter cables',
      description: 'Measure multimeter readings on cells 1 through 4',
      status: 'not_started',
      priority: 'high',
      dueDateUtc: new Date(Date.now() + 86400000 * 2).toISOString(),
      projectId: 'proj-2',
      projectName: 'Home Solar & Hardware Maintenance',
      estimatedDurationMinutes: 60,
      createdAtUtc: new Date().toISOString(),
      updatedAtUtc: new Date().toISOString(),
    },
    {
      id: 'task-3',
      title: 'Clean workspace desk and backup offline files',
      status: 'completed',
      priority: 'low',
      projectId: 'proj-3',
      projectName: 'Stand-alone Personal Archive System',
      createdAtUtc: new Date(Date.now() - 86400000 * 2).toISOString(),
      updatedAtUtc: new Date().toISOString(),
    },
  ],
  categories: DEFAULT_CATEGORIES,
  transactions: [
    {
      id: 'tx-1',
      categoryId: 'cat-sal',
      amountCents: 3500000, // 35,000.00 ETB
      type: 'income',
      transactionDateUtc: new Date(Date.now() - 86400000 * 5).toISOString(),
      payee: 'Direct Deposit / Employer',
      note: 'Monthly base salary payment received',
      createdAtUtc: new Date(Date.now() - 86400000 * 5).toISOString(),
    },
    {
      id: 'tx-2',
      categoryId: 'cat-groc',
      amountCents: 480000, // 4,800.00 ETB
      type: 'expense',
      transactionDateUtc: new Date(Date.now() - 86400000 * 3).toISOString(),
      payee: 'Mercato Market',
      note: 'Teff, spices, oil, and monthly pantry staples',
      createdAtUtc: new Date(Date.now() - 86400000 * 3).toISOString(),
    },
    {
      id: 'tx-3',
      categoryId: 'cat-trans',
      amountCents: 150000, // 1,500.00 ETB
      type: 'expense',
      transactionDateUtc: new Date(Date.now() - 86400000 * 1).toISOString(),
      payee: 'Fuel Station / Ride',
      note: 'Monthly commute transport refill',
      createdAtUtc: new Date(Date.now() - 86400000 * 1).toISOString(),
    },
  ],
  commitments: [
    {
      id: 'commit-1',
      title: 'Apartment Rent (ቤት ኪራይ)',
      amountCents: 800000, // 8,000 ETB
      dueDateUtc: new Date(Date.now() + 86400000 * 5).toISOString(),
      isPaid: false,
      recurringRule: 'monthly',
      category: 'Rent',
    },
    {
      id: 'commit-2',
      title: 'Ethio Telecom Broadband Internet',
      amountCents: 120000, // 1,200 ETB
      dueDateUtc: new Date(Date.now() + 86400000 * 3).toISOString(),
      isPaid: false,
      recurringRule: 'monthly',
      category: 'Utilities',
    },
  ],
  savingsGoals: [
    {
      id: 'sav-1',
      title: 'Emergency Safety Reserve (የአደጋ ጊዜ ቁጠባ)',
      targetCents: 5000000, // 50,000 ETB
      currentAllocatedCents: 500000, // 5,000 ETB
      targetDateUtc: new Date(Date.now() + 86400000 * 120).toISOString(),
      createdAtUtc: new Date().toISOString(),
    },
    {
      id: 'sav-2',
      title: 'Backup Solar Inverter Replacement',
      targetCents: 3000000, // 30,000 ETB
      currentAllocatedCents: 1000000, // 10,000 ETB
      targetDateUtc: new Date(Date.now() + 86400000 * 90).toISOString(),
      createdAtUtc: new Date().toISOString(),
    },
  ],
  notes: [
    {
      id: 'note-1',
      title: 'የዕለት ማስታወሻ (Daily Reflection)',
      content: 'ትኩረት ማድረግ ያለብኝ ዋና ዋና ጉዳዮች፡ የአካል ብቃት እንቅስቃሴ፣ የቤተሰብ ጊዜ እና የሥራ ግቦች።',
      category: 'reflection',
      createdAtUtc: new Date().toISOString(),
    },
    {
      id: 'note-2',
      title: 'Emergency Medical Numbers & Blood Type',
      content: 'Blood Type: O+; Family Physician: 0911-XXXXXX; Red Cross Ambulance: 907',
      category: 'reference',
      createdAtUtc: new Date().toISOString(),
    },
  ],
  reminders: [
    {
      id: 'rem-1',
      targetId: 'task-1',
      targetType: 'task',
      title: 'Audit monthly living expenses and ETB budget',
      triggerTimeUtc: new Date(Date.now() + 3600000 * 2).toISOString(),
      isActive: true,
      channelId: 'task_reminders_channel',
      createdAtUtc: new Date().toISOString(),
    },
    {
      id: 'rem-2',
      targetId: 'commit-1',
      targetType: 'commitment',
      title: 'Apartment Rent (ቤት ኪራይ) Payment Due in 5 Days',
      triggerTimeUtc: new Date(Date.now() + 86400000 * 4).toISOString(),
      isActive: true,
      channelId: 'commitment_reminders_channel',
      createdAtUtc: new Date().toISOString(),
    },
    {
      id: 'rem-3',
      targetType: 'custom',
      title: 'Daily Evening Review & Quick Capture Check (የማታ ግምገማ)',
      triggerTimeUtc: new Date(Date.now() + 3600000 * 6).toISOString(),
      isActive: true,
      channelId: 'custom_reminders_channel',
      createdAtUtc: new Date().toISOString(),
    },
  ],
  backupLogs: [
    {
      id: 'log-1',
      timestampUtc: new Date(Date.now() - 86400000).toISOString(),
      filename: 'personal_management_backup_20261106.pmbackup',
      sizeBytes: 4128,
      checksumSha256: 'a3f890b4e28cd82304918e9c20a17f654b9d031e87854cfd3178045e2a9b2449',
      isEncrypted: true,
      type: 'export',
      status: 'verified',
      summary: '3 tasks, 3 transactions, 2 notes, 2 savings targets',
    },
  ],
  openingBalanceCents: 1500000, // 15,000.00 ETB
  incomesCents: [3500000],
  expensesCents: [480000, 150000],
  savingsAllocationsCents: [500000, 1000000], // 15,000 ETB
  budgetPeriod: 'current_month',
  lastSavedUtc: new Date().toISOString(),
};

export class LocalOfflineDatabase {
  static loadState(): LocalDatabaseState {
    try {
      const data = localStorage.getItem(STORAGE_KEY);
      if (data) {
        const parsed = JSON.parse(data);
        return {
          ...INITIAL_DEFAULT_STATE,
          ...parsed,
          inbox: parsed.inbox || INITIAL_DEFAULT_STATE.inbox,
          goals: parsed.goals && parsed.goals.length > 0 ? parsed.goals : INITIAL_DEFAULT_STATE.goals,
          projects: parsed.projects && parsed.projects.length > 0 ? parsed.projects : INITIAL_DEFAULT_STATE.projects,
          milestones: parsed.milestones && parsed.milestones.length > 0 ? parsed.milestones : INITIAL_DEFAULT_STATE.milestones,
          tasks: parsed.tasks && parsed.tasks.length > 0 ? parsed.tasks : INITIAL_DEFAULT_STATE.tasks,
          categories: parsed.categories && parsed.categories.length > 0 ? parsed.categories : INITIAL_DEFAULT_STATE.categories,
          transactions: parsed.transactions && parsed.transactions.length > 0 ? parsed.transactions : INITIAL_DEFAULT_STATE.transactions,
          commitments: parsed.commitments || INITIAL_DEFAULT_STATE.commitments,
          savingsGoals: parsed.savingsGoals && parsed.savingsGoals.length > 0 ? parsed.savingsGoals : INITIAL_DEFAULT_STATE.savingsGoals,
          notes: parsed.notes || INITIAL_DEFAULT_STATE.notes,
          reminders: parsed.reminders || INITIAL_DEFAULT_STATE.reminders,
          backupLogs: parsed.backupLogs || INITIAL_DEFAULT_STATE.backupLogs,
        };
      }
    } catch (e) {
      console.warn('Could not read from localStorage, using initial defaults', e);
    }
    return INITIAL_DEFAULT_STATE;
  }

  static saveState(state: LocalDatabaseState): void {
    try {
      const updated = { ...state, lastSavedUtc: new Date().toISOString() };
      localStorage.setItem(STORAGE_KEY, JSON.stringify(updated));
    } catch (e) {
      console.error('Failed to write to localStorage', e);
    }
  }

  static clearState(): void {
    try {
      localStorage.removeItem(STORAGE_KEY);
    } catch (e) {
      console.error('Failed to clear localStorage', e);
    }
  }
}
