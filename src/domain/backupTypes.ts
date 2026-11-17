/**
 * Pure domain contract types for offline encrypted backup payloads.
 * Decoupled from browser-specific storage implementations in src/data/.
 */

export interface LocalInboxItem {
  id: string;
  rawText: string;
  category: 'task' | 'idea' | 'expense' | 'note' | 'problem' | 'decision' | 'general';
  isProcessed: boolean;
  createdAtUtc: string; // ISO 8601 UTC
}

export interface LocalGoal {
  id: string;
  title: string;
  description?: string;
  targetDateUtc?: string;
  status: 'active' | 'achieved' | 'archived';
  createdAtUtc: string;
}

export interface LocalProject {
  id: string;
  goalId?: string;
  title: string;
  description?: string;
  status: 'active' | 'completed' | 'on_hold';
  targetDateUtc?: string;
  createdAtUtc: string;
}

export interface LocalMilestone {
  id: string;
  projectId: string;
  title: string;
  dueDateUtc?: string;
  isCompleted: boolean;
  createdAtUtc: string;
}

export interface LocalTask {
  id: string;
  title: string;
  description?: string;
  status: 'inbox' | 'not_started' | 'in_progress' | 'completed' | 'cancelled';
  priority: 'low' | 'medium' | 'high' | 'urgent';
  dueDateUtc?: string;
  scheduledDateUtc?: string;
  estimatedDurationMinutes?: number;
  projectId?: string;
  milestoneId?: string;
  projectName?: string;
  createdAtUtc: string;
  updatedAtUtc: string;
}

export interface LocalFinancialCategory {
  id: string;
  name: string;
  type: 'income' | 'expense';
  colorHex: string;
  isDefault: boolean;
}

export interface LocalFinancialTransaction {
  id: string;
  categoryId: string;
  amountCents: number; // Integer minor units (1 ETB = 100 cents)
  type: 'income' | 'expense';
  transactionDateUtc: string;
  note?: string;
  payee?: string;
  createdAtUtc: string;
  correctedFromId?: string;
  correctionReason?: string;
  isSuperseded?: boolean;
}

export interface LocalCommitment {
  id: string;
  title: string;
  amountCents: number;
  dueDateUtc: string;
  isPaid: boolean;
  recurringRule?: string;
  category?: string;
}

export type LocalFinancialCommitment = LocalCommitment;

export interface LocalSavingsGoal {
  id: string;
  title: string;
  targetCents: number;
  currentAllocatedCents: number;
  targetDateUtc?: string;
  createdAtUtc: string;
}

export interface LocalNote {
  id: string;
  title: string;
  content: string;
  category: string;
  projectId?: string;
  goalId?: string;
  createdAtUtc: string;
}

export interface LocalReminder {
  id: string;
  targetId?: string;
  targetType: 'task' | 'commitment' | 'custom' | 'note';
  title: string;
  triggerTimeUtc: string;
  isActive: boolean;
  channelId?: string;
  createdAtUtc: string;
}

export interface LocalBackupLog {
  id: string;
  timestampUtc: string;
  filename: string;
  sizeBytes: number;
  checksumSha256: string;
  isEncrypted: boolean;
  type: 'export' | 'restore';
  status: 'verified' | 'restored' | 'failed';
  summary: string;
}

export interface LocalDatabaseState {
  version: number;
  inbox: LocalInboxItem[];
  goals: LocalGoal[];
  projects: LocalProject[];
  milestones: LocalMilestone[];
  tasks: LocalTask[];
  categories: LocalFinancialCategory[];
  transactions: LocalFinancialTransaction[];
  commitments: LocalCommitment[];
  savingsGoals: LocalSavingsGoal[];
  notes: LocalNote[];
  reminders: LocalReminder[];
  backupLogs: LocalBackupLog[];
  openingBalanceCents: number;
  incomesCents: number[];
  expensesCents: number[];
  savingsAllocationsCents: number[];
  budgetPeriod: 'current_month' | 'next_30_days' | 'all_time';
  lastSavedUtc: string;
}

export type BackupFailureKind =
  | 'authentication_failure'
  | 'invalid_backup_header'
  | 'unsupported_format_version'
  | 'unsupported_kdf'
  | 'unsupported_future_schema'
  | 'invalid_snapshot_version'
  | 'invalid_payload'
  | 'integrity_failure'
  | 'database_import_failure';

export interface BackupErrorInfo {
  kind: BackupFailureKind;
  message: string;
}

export class BackupValidationError extends Error {
  public readonly kind: BackupFailureKind;

  constructor(kind: BackupFailureKind, message: string) {
    super(message);
    this.name = 'BackupValidationError';
    this.kind = kind;
  }
}
