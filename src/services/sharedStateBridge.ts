import {
  SharedDatabaseState,
  SharedAccount,
  SharedCategory,
  SharedTransaction,
  SharedTask,
  SharedTaskRecurrenceConfig,
  SharedTaskRecurrenceFrequency,
  SharedTaskRecurrenceRepeatFrom,
  SharedDailyPlanningEntry,
  SharedDailyPlanningAction,
  SharedDailyRhythmDay,
  SharedDailyRhythmFinanceCloseStatus,
  SharedDailyRhythmTaskReviewEvidence,
  CANONICAL_DAILY_RHYTHM_FINANCE_CLOSE_STATUSES,
  SharedNote,
  SharedCalendarEvent,
  SharedProject,
  SharedProjectBlockType,
  SharedProjectRecordType,
  SharedProjectTrackingBlock,
  SharedProjectTrackingRecord,
  SharedGoal,
  SharedInboxItem,
  SharedCommitment,
  SharedCommitmentSettlement,
  SharedSavingsGoal,
  SharedBudget,
  SharedRecurringRule,
  SharedReminder,
  SharedAppSetting,
  SHARED_BUSINESS_RULES,
  CANONICAL_SEED_DATABASE,
  KNOWN_SEED_IDS,
  SYSTEM_CONTROL_ACCOUNT_IDS,
} from '../domain/sharedFoundation';
import {
  ProjectValidationError,
  validateBlock,
  validateCustomFieldsMap,
  validateRecord,
} from '../domain/projectsEngine';
import {
  Account,
  CANONICAL_DEBT_STATUSES,
  CANONICAL_ENTRY_TYPES,
  DEBT_STATUS_LEGACY_ALIASES,
  Debt,
  DebtStatus,
  ENTRY_TYPE_LEGACY_ALIASES,
  EntryType,
  isEtbCurrency,
  isValidCurrencyCode,
  JournalEntry,
  normalizeCurrencyCode,
  normalizeDebtStatus,
  normalizeEntryType,
  Party,
  Posting,
  SettlementAllocation,
  tryNormalizeDebtStatus,
  tryNormalizeEntryType,
} from '../domain/doubleEntryFinance';
import {
  reconcileDebtsV7,
  syncVaultSavingsGoalsV7,
} from '../domain/financeV7Engine';
import { EthiopiaClock, LocalDateTime, SharedDateFormatter } from '../domain/date';
import { BackupFailureKind, BackupValidationError } from '../domain/backupTypes';
import { normalizeDailyRhythmTimeline } from '../domain/dailyRhythm';
import { interpretSnapshotVersions } from '../domain/snapshotVersionPolicy';

export interface SharedMilestone {
  id: string;
  projectId: string;
  title: string;
  dueDate?: string;
  isCompleted: boolean;
  createdAt: string;
}

export interface SharedBridgeNote extends SharedNote {
  projectId?: string;
  goalId?: string;
  linkedModule?: 'tasks' | 'finance' | 'calendar';
  linkedId?: string;
}

export interface SharedBridgeCalendarEvent extends SharedCalendarEvent {
  description?: string;
  location?: string;
  recurrence?: 'none' | 'daily' | 'weekly' | 'monthly' | 'yearly';
  linkedTaskId?: string;
}

export interface SharedDatabaseStateV7 extends SharedDatabaseState {
  financeSchemaVersion?: number;
  parties?: Party[];
  journalEntries?: JournalEntry[];
  postings?: Posting[];
  debts?: Debt[];
  settlementAllocations?: SettlementAllocation[];
  milestones?: SharedMilestone[];
  notes: SharedBridgeNote[];
  calendarEvents?: SharedBridgeCalendarEvent[];
  ledgerMigrationReportV7?: string | null;
}

export interface FinanceOnlySnapshotV7 {
  financeOnly: true;
  exportScope: 'finance_only';
  schemaVersion: number;
  snapshotFormatVersion: number;
  databaseSchemaVersion?: number;
  financeSchemaVersion: number;
  appVersion: string;
  exportedAt: string;
  isFinanceSetupCompleted: boolean;
  openingBalanceCents: number;
  ledgerMigrationReportV7?: string | null;
  accounts: SharedAccount[];
  categories: SharedCategory[];
  parties: Party[];
  transactions: SharedTransaction[];
  journalEntries: JournalEntry[];
  postings: Posting[];
  debts: Debt[];
  settlementAllocations: SettlementAllocation[];
  commitments: SharedCommitment[];
  commitmentSettlements: SharedCommitmentSettlement[];
  savingsGoals: SharedSavingsGoal[];
  budgets: SharedBudget[];
  recurringRules: SharedRecurringRule[];
}

export class SharedStateBridge {
  public static readonly STORAGE_KEY = 'daywell_canonical_database_v3';
  public static readonly SYNC_EVENT_NAME = 'daywell:canonical-synced';
  public static readonly DAILY_PLANNING_STORAGE_KEY =
    'daywell_daily_planning_entries';
  public static readonly DAILY_RHYTHM_STORAGE_KEY =
    'daywell_daily_rhythm_days';
  public static readonly PROJECTS_STORAGE_KEY = 'daywell_projects';
  public static readonly PROJECT_TRACKING_BLOCKS_STORAGE_KEY =
    'daywell_project_tracking_blocks';
  public static readonly PROJECT_TRACKING_RECORDS_STORAGE_KEY =
    'daywell_project_tracking_records';
  public static readonly GOALS_STORAGE_KEY = 'daywell_goals';
  public static readonly MILESTONES_STORAGE_KEY = 'daywell_milestones';
  public static readonly INBOX_STORAGE_KEY = 'daywell_inbox_items';
  public static readonly LEGACY_INBOX_STORAGE_KEY = 'daywell_inbox';
  public static readonly REMINDERS_STORAGE_KEY = 'daywell_reminders';
  public static readonly APP_SETTINGS_STORAGE_KEY = 'daywell_app_settings';

  private static readonly VALID_PROJECT_BLOCK_TYPES =
    new Set<SharedProjectBlockType>([
      'counter',
      'grouped_list',
      'checklist',
      'schedule',
    ]);

  private static readonly VALID_PROJECT_RECORD_TYPES =
    new Set<SharedProjectRecordType>([
      'group',
      'grouped_item',
      'checklist_item',
      'schedule_item',
      'progress_log',
    ]);

  private static readonly VALID_REMINDER_TARGET_TYPES = new Set<
    SharedReminder['targetType']
  >(['task', 'commitment', 'calendar_event', 'note', 'custom']);

  private static readonly VALID_TASK_STATUSES = new Set<SharedTask['status']>([
    'not_started',
    'in_progress',
    'completed',
    'cancelled',
    'inbox',
  ]);

  private static readonly VALID_TASK_PRIORITIES = new Set<SharedTask['priority']>([
    'low',
    'medium',
    'high',
    'urgent',
  ]);

  private static readonly VALID_TASK_RECURRENCE_FREQUENCIES =
    new Set<SharedTaskRecurrenceFrequency>([
      'daily',
      'weekly',
      'monthly',
      'yearly',
    ]);

  private static readonly VALID_TASK_RECURRENCE_REPEAT_FROM =
    new Set<SharedTaskRecurrenceRepeatFrom>([
      'due_date',
      'completion_date',
    ]);

  private static readonly VALID_DAILY_PLANNING_ACTIONS =
    new Set<SharedDailyPlanningAction>([
      'planned',
      'carried_forward',
      'completed',
      'dismissed',
    ]);

  private static readonly VALID_DAILY_RHYTHM_FINANCE_CLOSE_STATUSES =
    new Set<SharedDailyRhythmFinanceCloseStatus>(
      CANONICAL_DAILY_RHYTHM_FINANCE_CLOSE_STATUSES
    );

  private static readonly SCHEDULED_TIME_HHMM_REGEX =
    /^(?:[01]\d|2[0-3]):[0-5]\d$/;

  private static readonly VALID_ACCOUNT_TYPES = new Set<SharedAccount['type']>([
    'asset',
    'liability',
    'equity',
    'revenue',
    'income',
    'expense',
  ]);

  private static readonly VALID_CATEGORY_TYPES = new Set<SharedCategory['type']>([
    'income',
    'expense',
  ]);

  private static readonly VALID_TRANSACTION_TYPES = new Set<SharedTransaction['type']>([
    'income',
    'expense',
    'transfer',
  ]);

  private static readonly VALID_INBOX_CATEGORIES = new Set<SharedInboxItem['category']>([
    'task',
    'idea',
    'expense',
    'note',
    'problem',
    'decision',
    'general',
  ]);

  private static readonly VALID_PROJECT_STATUSES = new Set<SharedProject['status']>([
    'active',
    'completed',
    'on_hold',
  ]);

  private static readonly VALID_GOAL_STATUSES = new Set<SharedGoal['status']>([
    'active',
    'achieved',
    'archived',
  ]);

  private static readonly VALID_RULE_TYPES = new Set<SharedRecurringRule['ruleType']>([
    'expense',
    'income',
    'transfer',
    'commitment',
  ]);

  private static readonly VALID_RULE_FREQUENCIES = new Set<
    SharedRecurringRule['frequency']
  >(['weekly', 'biweekly', 'monthly', 'quarterly', 'yearly']);

  private static readonly VALID_COMMITMENT_DIRECTIONS = new Set<
    NonNullable<SharedCommitment['direction']>
  >(['outflow', 'inflow']);

  private static readonly VALID_SAVINGS_STATUSES = new Set<
    NonNullable<SharedSavingsGoal['status']>
  >(['active', 'completed', 'archived']);

  private static readonly VALID_POSTING_DIRECTIONS = new Set<string>([
    'debit',
    'credit',
  ]);

  private static readonly VALID_DEBT_TYPES = new Set<string>([
    'payable',
    'receivable',
  ]);

  private static readonly SYSTEM_CONTROL_ACCOUNT_ID_SET = new Set<string>(
    Object.values(SYSTEM_CONTROL_ACCOUNT_IDS)
  );

  private static readonly CANONICAL_STARTER_CATEGORY_ID_SET = new Set<string>(
    CANONICAL_SEED_DATABASE.categories.map((c) => c.id)
  );

  private static readonly TOP_LEVEL_MANAGED_SETTING_KEYS = new Set<string>([
    'opening_balance_cents',
    'is_finance_setup_completed',
    'ledger_migration_report_v7',
  ]);

  private static readonly INTERNAL_SENTINEL_SETTING_KEYS = new Set<string>([
    'initial_seed_completed',
    'ledger_v6_migrated_at',
  ]);

  private static readonly EXACT_EXCLUDED_SECRET_OR_DEVICE_KEYS = new Set<string>([
    'push_token',
  ]);

  private static readonly EXCLUDED_SETTING_PREFIXES = [
    'secret_',
    'token_',
    'auth_',
    'passphrase_',
    'device_',
    'local_cache_',
    'transient_',
  ] as const;

  private static isExcludedAppSettingKey(key: string): boolean {
    const normalized = key.trim().toLowerCase();
    if (!normalized) return true;
    if (this.TOP_LEVEL_MANAGED_SETTING_KEYS.has(normalized)) return true;
    if (this.INTERNAL_SENTINEL_SETTING_KEYS.has(normalized)) return true;
    if (this.EXACT_EXCLUDED_SECRET_OR_DEVICE_KEYS.has(normalized)) return true;
    return this.EXCLUDED_SETTING_PREFIXES.some((prefix) =>
      normalized.startsWith(prefix)
    );
  }

  private static normalizeAssembledReminders(raw: unknown[]): SharedReminder[] {
    const mapped: SharedReminder[] = [];
    for (const entry of raw) {
      if (!entry || typeof entry !== 'object' || Array.isArray(entry)) continue;
      const r = entry as Record<string, any>;
      const id = typeof r.id === 'string' ? r.id.trim() : '';
      if (!id) continue;
      const targetTypeRaw = typeof r.targetType === 'string' ? r.targetType.trim() : '';
      if (!this.VALID_REMINDER_TARGET_TYPES.has(targetTypeRaw as SharedReminder['targetType'])) {
        continue;
      }
      const targetType = targetTypeRaw as SharedReminder['targetType'];
      const rawTargetId = typeof r.targetId === 'string' ? r.targetId.trim() : '';
      const targetId = rawTargetId || (targetType === 'custom' ? id : '');
      if (!targetId) continue;

      const rawTrigger = typeof r.triggerTimeUtc === 'string' ? r.triggerTimeUtc.trim() : '';
      const triggerParsed = rawTrigger ? Date.parse(rawTrigger) : NaN;
      if (!rawTrigger || Number.isNaN(triggerParsed)) continue;

      const rawCreated =
        typeof r.createdAt === 'string' && r.createdAt.trim()
          ? r.createdAt.trim()
          : typeof r.createdAtUtc === 'string' && r.createdAtUtc.trim()
            ? r.createdAtUtc.trim()
            : '';
      const createdParsed = rawCreated ? Date.parse(rawCreated) : NaN;
      const createdAt =
        rawCreated && !Number.isNaN(createdParsed)
          ? new Date(createdParsed).toISOString()
          : EthiopiaClock.nowUtc().toISOString();

      const cleanTitle = typeof r.title === 'string' ? r.title.trim() : '';
      const cleanChannelId = typeof r.channelId === 'string' ? r.channelId.trim() : '';

      mapped.push({
        id,
        targetId,
        targetType,
        triggerTimeUtc: new Date(triggerParsed).toISOString(),
        isActive: r.isActive !== undefined ? Boolean(r.isActive) : true,
        createdAt,
        ...(cleanTitle.length > 0 ? { title: cleanTitle } : {}),
        ...(cleanChannelId.length > 0 ? { channelId: cleanChannelId } : {}),
      });
    }
    return this.dedupeById(mapped);
  }

  private static normalizeAssembledAppSettings(raw: unknown[]): SharedAppSetting[] {
    const seenKeys = new Set<string>();
    const result: SharedAppSetting[] = [];
    for (const entry of raw) {
      if (!entry || typeof entry !== 'object' || Array.isArray(entry)) continue;
      const s = entry as Record<string, any>;
      const key = typeof s.key === 'string' ? s.key.trim() : '';
      const normalizedKey = key.toLowerCase();
      if (!key || this.isExcludedAppSettingKey(key) || seenKeys.has(normalizedKey)) continue;
      if (typeof s.value !== 'string') continue;
      seenKeys.add(normalizedKey);

      let updatedAt: string | undefined;
      if (typeof s.updatedAt === 'string' && s.updatedAt.trim()) {
        const parsedMs = Date.parse(s.updatedAt.trim());
        if (!Number.isNaN(parsedMs)) {
          updatedAt = new Date(parsedMs).toISOString();
        }
      }
      result.push({
        key,
        value: s.value,
        ...(updatedAt !== undefined ? { updatedAt } : {}),
      });
    }
    result.sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
    return result;
  }

  private static normalizeAccountRecord(raw: unknown): SharedAccount | null {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
    const acc = raw as Record<string, any>;
    const id = typeof acc.id === 'string' ? acc.id.trim() : '';
    if (!id) return null;
    const { isActive: legacyIsActive, ...rest } = acc;
    const isArchived = Boolean(acc.isArchived) || legacyIsActive === false;
    const isSystemAccount = Boolean(acc.isSystem) || this.SYSTEM_CONTROL_ACCOUNT_ID_SET.has(id);
    const normalizedCurrency =
      typeof acc.currencyCode === 'string' ? normalizeCurrencyCode(acc.currencyCode) : '';
    return {
      ...(rest as SharedAccount),
      id,
      currencyCode: normalizedCurrency || (isSystemAccount ? 'ETB' : ''),
      openingBalanceCents:
        typeof acc.openingBalanceCents === 'number' && Number.isFinite(acc.openingBalanceCents)
          ? Math.trunc(acc.openingBalanceCents)
          : 0,
      isArchived,
    };
  }

  private static normalizeAccounts(raw: unknown[]): SharedAccount[] {
    const mapped: SharedAccount[] = [];
    for (const entry of raw) {
      const normalized = this.normalizeAccountRecord(entry);
      if (normalized) mapped.push(normalized);
    }
    return this.dedupeById(mapped);
  }

  private static normalizeCategories(raw: unknown[]): SharedCategory[] {
    const mapped: SharedCategory[] = [];
    for (const entry of raw) {
      if (!entry || typeof entry !== 'object' || Array.isArray(entry)) continue;
      const c = entry as Record<string, any>;
      const id = typeof c.id === 'string' ? c.id.trim() : '';
      if (!id) continue;
      const type: SharedCategory['type'] = c.type === 'income' ? 'income' : 'expense';
      const parentId =
        typeof c.parentId === 'string' && c.parentId.trim() ? c.parentId.trim() : undefined;
      mapped.push({
        id,
        name: typeof c.name === 'string' ? c.name.trim() : String(c.name ?? ''),
        type,
        colorHex:
          typeof c.colorHex === 'string' && c.colorHex.trim()
            ? c.colorHex.trim()
            : '#1B4D3E',
        ...(parentId !== undefined ? { parentId } : {}),
        ...(typeof c.sortOrder === 'number' && Number.isInteger(c.sortOrder)
          ? { sortOrder: c.sortOrder }
          : {}),
        isDefault: Boolean(c.isDefault),
        isArchived: Boolean(c.isArchived),
      });
    }
    return this.dedupeById(mapped);
  }

  private static normalizeOptionalTaskRecurrenceConfig(
    raw: unknown
  ): SharedTaskRecurrenceConfig | undefined {
    const obj = this.tryParseOptionalJsonObject(raw);
    if (!obj) return undefined;
    const freqRaw = typeof obj.frequency === 'string' ? obj.frequency.trim() : '';
    if (
      !this.VALID_TASK_RECURRENCE_FREQUENCIES.has(
        freqRaw as SharedTaskRecurrenceFrequency
      )
    ) {
      return undefined;
    }
    const frequency = freqRaw as SharedTaskRecurrenceFrequency;
    const interval =
      typeof obj.interval === 'number' &&
      Number.isInteger(obj.interval) &&
      obj.interval >= 1
        ? obj.interval
        : undefined;
    const weekdays = Array.isArray(obj.weekdays)
      ? Array.from(
          new Set(
            obj.weekdays.filter(
              (d): d is number =>
                typeof d === 'number' && Number.isInteger(d) && d >= 1 && d <= 7
            )
          )
        )
      : undefined;
    const parsedStart =
      typeof obj.startDate === 'string' && obj.startDate.trim()
        ? SharedDateFormatter.tryParseFlexibleToCalendarDate(obj.startDate.trim())
        : null;
    const parsedEnd =
      typeof obj.endDate === 'string' && obj.endDate.trim()
        ? SharedDateFormatter.tryParseFlexibleToCalendarDate(obj.endDate.trim())
        : null;
    const startDate = parsedStart ? parsedStart.toIsoString() : undefined;
    const endDate =
      parsedEnd && (!startDate || parsedEnd.toIsoString() >= startDate)
        ? parsedEnd.toIsoString()
        : undefined;
    const repeatFromRaw =
      typeof obj.repeatFrom === 'string' ? obj.repeatFrom.trim() : '';
    const repeatFrom = this.VALID_TASK_RECURRENCE_REPEAT_FROM.has(
      repeatFromRaw as SharedTaskRecurrenceRepeatFrom
    )
      ? (repeatFromRaw as SharedTaskRecurrenceRepeatFrom)
      : undefined;

    return {
      frequency,
      ...(interval !== undefined ? { interval } : {}),
      ...(weekdays !== undefined && weekdays.length > 0 ? { weekdays } : {}),
      ...(startDate !== undefined ? { startDate } : {}),
      ...(endDate !== undefined ? { endDate } : {}),
      ...(repeatFrom !== undefined ? { repeatFrom } : {}),
    };
  }

  private static normalizeOptionalIsoInstantString(raw: unknown): string | undefined {
    if (typeof raw !== 'string') return undefined;
    const trimmed = raw.trim();
    if (!trimmed || !/^\d{4}-\d{2}-\d{2}/.test(trimmed)) return undefined;
    const ms = Date.parse(trimmed);
    if (Number.isNaN(ms)) return undefined;
    return new Date(ms).toISOString();
  }

  private static normalizeTaskRecord(raw: unknown): SharedTask | null {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
    const t = raw as Record<string, any>;
    const id = typeof t.id === 'string' ? t.id.trim() : '';
    if (!id) return null;

    const statusRaw = typeof t.status === 'string' ? t.status.trim() : '';
    const status: SharedTask['status'] = this.VALID_TASK_STATUSES.has(
      statusRaw as SharedTask['status']
    )
      ? (statusRaw as SharedTask['status'])
      : t.completed
        ? 'completed'
        : 'not_started';

    const priorityRaw = typeof t.priority === 'string' ? t.priority.trim() : '';
    const priority: SharedTask['priority'] = this.VALID_TASK_PRIORITIES.has(
      priorityRaw as SharedTask['priority']
    )
      ? (priorityRaw as SharedTask['priority'])
      : 'medium';

    const description =
      typeof t.description === 'string' && t.description.length > 0
        ? t.description
        : undefined;
    const completedAt = this.normalizeOptionalIsoInstantString(t.completedAt);
    const dueDateRaw =
      typeof t.dueDate === 'string' && t.dueDate.trim() ? t.dueDate.trim() : undefined;
    const dueDateParsed = dueDateRaw
      ? SharedDateFormatter.tryParseFlexibleToCalendarDate(dueDateRaw)
      : null;
    const dueDate = dueDateParsed ? dueDateParsed.toIsoString() : dueDateRaw;
    const scheduledDateRaw =
      typeof t.scheduledDate === 'string' && t.scheduledDate.trim()
        ? t.scheduledDate.trim()
        : undefined;
    const scheduledDateParsed = scheduledDateRaw
      ? SharedDateFormatter.tryParseFlexibleToCalendarDate(scheduledDateRaw)
      : null;
    const scheduledDate = scheduledDateParsed
      ? scheduledDateParsed.toIsoString()
      : scheduledDateRaw;
    const scheduledTimeRaw =
      typeof t.scheduledTime === 'string' ? t.scheduledTime.trim() : '';
    const scheduledTime = this.SCHEDULED_TIME_HHMM_REGEX.test(scheduledTimeRaw)
      ? scheduledTimeRaw
      : undefined;
    const projectId =
      typeof t.projectId === 'string' && t.projectId.trim()
        ? t.projectId.trim()
        : undefined;
    const milestoneId =
      typeof t.milestoneId === 'string' && t.milestoneId.trim()
        ? t.milestoneId.trim()
        : undefined;
    const estimatedDurationMinutes =
      typeof t.estimatedDurationMinutes === 'number' &&
      Number.isInteger(t.estimatedDurationMinutes) &&
      t.estimatedDurationMinutes >= 0
        ? t.estimatedDurationMinutes
        : undefined;

    const subtasks: SharedTask['subtasks'] = Array.isArray(t.subtasks)
      ? t.subtasks
          .filter((st: unknown): st is Record<string, any> => Boolean(st && typeof st === 'object' && !Array.isArray(st)))
          .map((st: Record<string, any>, idx: number) => {
            const subTitle = typeof st.title === 'string' ? st.title.trim() : '';
            const subId =
              typeof st.id === 'string' && st.id.trim()
                ? st.id.trim()
                : `${id}-sub-${idx + 1}`;
            if (!subTitle) return null;
            return {
              id: subId,
              title: subTitle,
              done: Boolean(st.done ?? st.completed),
            };
          })
          .filter((st): st is NonNullable<typeof st> => st !== null)
      : [];

    const labels: string[] = Array.isArray(t.labels)
      ? t.labels
          .filter((l: unknown): l is string => typeof l === 'string' && l.trim().length > 0)
          .map((l) => l.trim())
      : [];

    const myDayDateRaw =
      typeof t.myDayDate === 'string' && t.myDayDate.trim()
        ? t.myDayDate.trim()
        : undefined;
    const myDayDateParsed = myDayDateRaw
      ? SharedDateFormatter.tryParseFlexibleToCalendarDate(myDayDateRaw)
      : null;
    const myDayDate = myDayDateParsed ? myDayDateParsed.toIsoString() : undefined;

    const recurrenceRaw =
      typeof t.recurrenceRule === 'string' && t.recurrenceRule.trim()
        ? t.recurrenceRule.trim()
        : typeof t.recurringRule === 'string' && t.recurringRule.trim()
          ? t.recurringRule.trim()
          : undefined;
    const recurrenceConfig = this.normalizeOptionalTaskRecurrenceConfig(
      t.recurrenceConfig ?? t.recurrenceConfigJson
    );
    const isArchived = Boolean(t.isArchived);
    const sortOrder =
      typeof t.sortOrder === 'number' &&
      Number.isInteger(t.sortOrder) &&
      t.sortOrder >= 0
        ? t.sortOrder
        : 0;

    const createdAt =
      this.normalizeOptionalIsoInstantString(t.createdAt) ??
      (typeof t.createdAt === 'string' && t.createdAt.trim()
        ? t.createdAt.trim()
        : EthiopiaClock.nowUtc().toISOString());
    const updatedAt =
      this.normalizeOptionalIsoInstantString(t.updatedAt) ??
      (typeof t.updatedAt === 'string' && t.updatedAt.trim()
        ? t.updatedAt.trim()
        : undefined);

    return {
      id,
      title: typeof t.title === 'string' ? t.title.trim() : String(t.title ?? ''),
      ...(description !== undefined ? { description } : {}),
      status,
      priority,
      ...(completedAt !== undefined ? { completedAt } : {}),
      ...(dueDate !== undefined ? { dueDate } : {}),
      ...(scheduledDate !== undefined ? { scheduledDate } : {}),
      ...(scheduledTime !== undefined ? { scheduledTime } : {}),
      ...(projectId !== undefined ? { projectId } : {}),
      ...(milestoneId !== undefined ? { milestoneId } : {}),
      ...(estimatedDurationMinutes !== undefined ? { estimatedDurationMinutes } : {}),
      subtasks,
      labels,
      isPinned: Boolean(t.isPinned),
      isMyDay: Boolean(t.isMyDay),
      ...(myDayDate !== undefined ? { myDayDate } : {}),
      ...(recurrenceRaw !== undefined ? { recurrenceRule: recurrenceRaw } : {}),
      ...(recurrenceConfig !== undefined ? { recurrenceConfig } : {}),
      isArchived,
      sortOrder,
      createdAt,
      ...(updatedAt !== undefined ? { updatedAt } : {}),
    };
  }

  private static normalizeTasks(raw: unknown[]): SharedTask[] {
    const mapped: SharedTask[] = [];
    for (const entry of raw) {
      const normalized = this.normalizeTaskRecord(entry);
      if (normalized) mapped.push(normalized);
    }
    return this.dedupeById(mapped);
  }

  private static normalizeDailyPlanningEntryRecord(
    raw: unknown
  ): SharedDailyPlanningEntry | null {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
    const e = raw as Record<string, any>;
    const id = typeof e.id === 'string' ? e.id.trim() : '';
    const taskId = typeof e.taskId === 'string' ? e.taskId.trim() : '';
    const rawPlanDate =
      typeof e.planDate === 'string' ? e.planDate.trim() : '';
    const parsedPlanDate = rawPlanDate
      ? SharedDateFormatter.tryParseFlexibleToCalendarDate(rawPlanDate)
      : null;
    if (!id || !taskId || !parsedPlanDate) return null;
    const actionRaw = typeof e.action === 'string' ? e.action.trim() : '';
    const action: SharedDailyPlanningAction = this.VALID_DAILY_PLANNING_ACTIONS.has(
      actionRaw as SharedDailyPlanningAction
    )
      ? (actionRaw as SharedDailyPlanningAction)
      : 'planned';
    const createdAt =
      this.normalizeOptionalIsoInstantString(e.createdAt) ??
      EthiopiaClock.nowUtc().toISOString();
    const updatedAt = this.normalizeOptionalIsoInstantString(e.updatedAt);

    return {
      id,
      planDate: parsedPlanDate.toIsoString(),
      taskId,
      action,
      createdAt,
      ...(updatedAt !== undefined ? { updatedAt } : {}),
    };
  }

  private static normalizeDailyPlanningEntries(
    raw: unknown[]
  ): SharedDailyPlanningEntry[] {
    const dedupedById: SharedDailyPlanningEntry[] = [];
    const seenIds = new Set<string>();
    const seenTaskDates = new Set<string>();
    for (const entry of raw) {
      const normalized = this.normalizeDailyPlanningEntryRecord(entry);
      if (!normalized) continue;
      if (seenIds.has(normalized.id)) continue;
      const compositeKey = `${normalized.taskId}::${normalized.planDate}`;
      if (seenTaskDates.has(compositeKey)) continue;
      seenIds.add(normalized.id);
      seenTaskDates.add(compositeKey);
      dedupedById.push(normalized);
    }
    return dedupedById;
  }

  public static removeDailyPlanningForTask(taskId: string): void {
    if (typeof window === 'undefined' || !taskId.trim()) return;
    try {
      const rawList = localStorage.getItem(this.DAILY_PLANNING_STORAGE_KEY);
      if (rawList !== null) {
        try {
          const parsed = JSON.parse(rawList);
          if (Array.isArray(parsed)) {
            const filtered = parsed.filter((e: any) => e?.taskId !== taskId);
            localStorage.setItem(
              this.DAILY_PLANNING_STORAGE_KEY,
              JSON.stringify(filtered)
            );
          }
        } catch {}
      }
      const rawCanonical = localStorage.getItem(this.STORAGE_KEY);
      if (rawCanonical !== null) {
        try {
          const canonical = JSON.parse(rawCanonical);
          if (
            canonical &&
            typeof canonical === 'object' &&
            Array.isArray(canonical.dailyPlanningEntries)
          ) {
            canonical.dailyPlanningEntries =
              canonical.dailyPlanningEntries.filter(
                (e: any) => e?.taskId !== taskId
              );
            localStorage.setItem(this.STORAGE_KEY, JSON.stringify(canonical));
          }
        } catch {}
      }
    } catch {}
  }

  private static normalizeNoteRecord(raw: unknown): SharedBridgeNote | null {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
    const n = raw as Record<string, any>;
    const id = typeof n.id === 'string' ? n.id.trim() : '';
    if (!id) return null;

    const body =
      typeof n.body === 'string'
        ? n.body
        : typeof n.content === 'string'
          ? n.content
          : '';
    const folder =
      typeof n.folder === 'string' && n.folder.trim()
        ? n.folder.trim()
        : typeof n.category === 'string' && n.category.trim()
          ? n.category.trim()
          : typeof n.notebook === 'string' && n.notebook.trim()
            ? n.notebook.trim()
            : 'General';
    const tags: string[] = Array.isArray(n.tags)
      ? n.tags
          .filter((tag: unknown): tag is string => typeof tag === 'string' && tag.trim().length > 0)
          .map((tag) => tag.trim())
      : [];
    const createdAt =
      typeof n.createdAt === 'string' && n.createdAt.trim()
        ? n.createdAt.trim()
        : EthiopiaClock.nowUtc().toISOString();
    const updatedAt =
      typeof n.updatedAt === 'string' && n.updatedAt.trim()
        ? n.updatedAt.trim()
        : createdAt;
    const projectId =
      typeof n.projectId === 'string' && n.projectId.trim() ? n.projectId.trim() : undefined;
    const goalId =
      typeof n.goalId === 'string' && n.goalId.trim() ? n.goalId.trim() : undefined;
    const linkedModule =
      n.linkedModule === 'tasks' || n.linkedModule === 'finance' || n.linkedModule === 'calendar'
        ? n.linkedModule
        : undefined;
    const linkedId =
      typeof n.linkedId === 'string' && n.linkedId.trim() ? n.linkedId.trim() : undefined;

    return {
      id,
      title: typeof n.title === 'string' ? n.title.trim() : String(n.title ?? ''),
      body,
      folder,
      tags,
      isPinned: Boolean(n.isPinned),
      isFavorite: Boolean(n.isFavorite),
      isArchived: Boolean(n.isArchived),
      isTrashed: Boolean(n.isTrashed),
      ...(projectId !== undefined ? { projectId } : {}),
      ...(goalId !== undefined ? { goalId } : {}),
      ...(linkedModule !== undefined ? { linkedModule } : {}),
      ...(linkedId !== undefined ? { linkedId } : {}),
      createdAt,
      updatedAt,
    };
  }

  private static normalizeNotes(raw: unknown[]): SharedBridgeNote[] {
    const mapped: SharedBridgeNote[] = [];
    for (const entry of raw) {
      const normalized = this.normalizeNoteRecord(entry);
      if (normalized) mapped.push(normalized);
    }
    return this.dedupeById(mapped);
  }

  private static normalizeMilestones(raw: unknown[]): SharedMilestone[] {
    const mapped: SharedMilestone[] = [];
    for (const entry of raw) {
      if (!entry || typeof entry !== 'object' || Array.isArray(entry)) continue;
      const m = entry as Record<string, any>;
      const id = typeof m.id === 'string' ? m.id.trim() : '';
      const projectId = typeof m.projectId === 'string' ? m.projectId.trim() : '';
      if (!id || !projectId) continue;
      const dueDate =
        typeof m.dueDate === 'string' && m.dueDate.trim() ? m.dueDate.trim() : undefined;
      const createdAt =
        typeof m.createdAt === 'string' && m.createdAt.trim()
          ? m.createdAt.trim()
          : EthiopiaClock.nowUtc().toISOString();
      mapped.push({
        id,
        projectId,
        title: typeof m.title === 'string' ? m.title.trim() : String(m.title ?? ''),
        ...(dueDate !== undefined ? { dueDate } : {}),
        isCompleted: Boolean(m.isCompleted),
        createdAt,
      });
    }
    return this.dedupeById(mapped);
  }

  private static normalizeCalendarEvents(raw: unknown[]): SharedBridgeCalendarEvent[] {
    const mapped: SharedBridgeCalendarEvent[] = [];
    for (const entry of raw) {
      if (!entry || typeof entry !== 'object' || Array.isArray(entry)) continue;
      const e = entry as Record<string, any>;
      const id = typeof e.id === 'string' ? e.id.trim() : '';
      if (!id) continue;
      const dateRaw =
        typeof e.date === 'string' && e.date.trim()
          ? e.date.trim()
          : typeof e.dateIso === 'string' && e.dateIso.trim()
            ? e.dateIso.trim()
            : '';
      if (!dateRaw) continue;
      const endDateRaw =
        typeof e.endDate === 'string' && e.endDate.trim()
          ? e.endDate.trim()
          : typeof e.endDateIso === 'string' && e.endDateIso.trim()
            ? e.endDateIso.trim()
            : undefined;
      const createdAt =
        typeof e.createdAt === 'string' && e.createdAt.trim()
          ? e.createdAt.trim()
          : EthiopiaClock.nowUtc().toISOString();
      const updatedAt =
        typeof e.updatedAt === 'string' && e.updatedAt.trim()
          ? e.updatedAt.trim()
          : createdAt;
      mapped.push({
        id,
        title: typeof e.title === 'string' ? e.title.trim() : String(e.title ?? ''),
        date: dateRaw,
        ...(endDateRaw !== undefined ? { endDate: endDateRaw } : {}),
        ...(typeof e.startTime === 'string' && e.startTime.trim()
          ? { startTime: e.startTime.trim() }
          : {}),
        ...(typeof e.endTime === 'string' && e.endTime.trim()
          ? { endTime: e.endTime.trim() }
          : {}),
        isAllDay: Boolean(e.isAllDay),
        category:
          typeof e.category === 'string' && e.category.trim()
            ? e.category.trim()
            : 'personal',
        colorHex:
          typeof e.colorHex === 'string' && e.colorHex.trim()
            ? e.colorHex.trim()
            : '#1B4D3E',
        hasReminder: Boolean(e.hasReminder),
        ...(typeof e.notes === 'string' ? { notes: e.notes } : {}),
        ...(typeof e.description === 'string' ? { description: e.description } : {}),
        ...(typeof e.location === 'string' && e.location.trim()
          ? { location: e.location.trim() }
          : {}),
        ...(typeof e.recurrence === 'string' && e.recurrence.trim()
          ? { recurrence: e.recurrence.trim() as SharedBridgeCalendarEvent['recurrence'] }
          : {}),
        ...(typeof e.linkedTaskId === 'string' && e.linkedTaskId.trim()
          ? { linkedTaskId: e.linkedTaskId.trim() }
          : {}),
        createdAt,
        updatedAt,
      });
    }
    return this.dedupeById(mapped);
  }

  private static dedupeById<T extends { id?: unknown }>(items: T[]): T[] {
    const seen = new Set<string>();
    const result: T[] = [];
    for (const item of items) {
      if (!item || typeof item !== 'object') continue;
      const id = typeof item.id === 'string' ? item.id.trim() : '';
      if (!id || seen.has(id)) continue;
      seen.add(id);
      result.push(item);
    }
    return result;
  }

  private static readExplicitJsonArray(key: string): { exists: boolean; items: unknown[] } {
    try {
      const raw = localStorage.getItem(key);
      if (raw === null) return { exists: false, items: [] };
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) return { exists: false, items: [] };
      return { exists: true, items: parsed };
    } catch {
      return { exists: false, items: [] };
    }
  }

  private static readCanonicalStoredState(): Partial<SharedDatabaseStateV7> | null {
    try {
      const raw = localStorage.getItem(this.STORAGE_KEY);
      if (!raw) return null;
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === 'object' ? (parsed as Partial<SharedDatabaseStateV7>) : null;
    } catch {
      return null;
    }
  }

  private static tryParseOptionalJsonObject(
    raw: unknown
  ): Record<string, unknown> | undefined {
    if (raw === undefined || raw === null) return undefined;
    if (typeof raw === 'string') {
      const trimmed = raw.trim();
      if (!trimmed) return undefined;
      try {
        const parsed = JSON.parse(trimmed);
        return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
          ? (parsed as Record<string, unknown>)
          : undefined;
      } catch {
        return undefined;
      }
    }
    if (typeof raw === 'object' && !Array.isArray(raw)) {
      return raw as Record<string, unknown>;
    }
    return undefined;
  }

  private static parseStrictJsonObject(
    record: Record<string, any>,
    keys: string[],
    ctx: string
  ): Record<string, unknown> | undefined {
    for (const key of keys) {
      if (!Object.prototype.hasOwnProperty.call(record, key)) continue;
      const val = record[key];
      if (val === undefined || val === null) continue;
      if (typeof val === 'string') {
        const trimmed = val.trim();
        if (!trimmed) return {};
        let parsed: unknown;
        try {
          parsed = JSON.parse(trimmed);
        } catch {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid JSON in "${ctx}.${key}": expected a JSON object.`
          );
        }
        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid field "${ctx}.${key}": expected a JSON object.`
          );
        }
        return parsed as Record<string, unknown>;
      }
      if (typeof val !== 'object' || Array.isArray(val)) {
        throw new BackupValidationError(
          'invalid_payload',
          `Invalid field "${ctx}.${key}": expected an object.`
        );
      }
      return val as Record<string, unknown>;
    }
    return undefined;
  }

  private static normalizeProjects(raw: unknown[]): SharedProject[] {
    const mapped: SharedProject[] = [];
    for (const entry of raw) {
      if (!entry || typeof entry !== 'object') continue;
      const p = entry as Record<string, any>;
      const id = typeof p.id === 'string' ? p.id.trim() : '';
      if (!id) continue;
      const description =
        p.description !== undefined
          ? p.description
          : p.narrative ?? p.subtitle ?? undefined;
      const status: SharedProject['status'] =
        p.status === 'completed' || p.status === 'on_hold' || p.status === 'active'
          ? p.status
          : 'active';
      const customFields = this.tryParseOptionalJsonObject(
        p.customFields ?? p.customFieldsJson
      );
      const { customFieldsJson: _droppedCfJson, ...rest } = p;
      mapped.push({
        ...(rest as SharedProject),
        id,
        title: typeof p.title === 'string' ? p.title : String(p.title ?? ''),
        ...(description !== undefined ? { description } : {}),
        status,
        ...(p.targetDate ? { targetDate: p.targetDate } : {}),
        ...(p.goalId ? { goalId: p.goalId } : {}),
        ...(typeof p.isArchived === 'boolean' ? { isArchived: p.isArchived } : {}),
        ...(typeof p.startDate === 'string' && p.startDate.trim()
          ? { startDate: p.startDate.trim() }
          : {}),
        ...(customFields !== undefined ? { customFields } : {}),
        ...(typeof p.createdAt === 'string' && p.createdAt.trim()
          ? { createdAt: p.createdAt.trim() }
          : {}),
        ...(typeof p.updatedAt === 'string' && p.updatedAt.trim()
          ? { updatedAt: p.updatedAt.trim() }
          : {}),
      });
    }
    return this.dedupeById(mapped);
  }

  private static normalizeProjectTrackingBlocks(
    raw: unknown[]
  ): SharedProjectTrackingBlock[] {
    const mapped: SharedProjectTrackingBlock[] = [];
    for (const entry of raw) {
      if (!entry || typeof entry !== 'object' || Array.isArray(entry)) continue;
      const b = entry as Record<string, any>;
      const id = typeof b.id === 'string' ? b.id.trim() : '';
      const projectId =
        typeof b.projectId === 'string' ? b.projectId.trim() : '';
      const blockTypeRaw =
        typeof b.blockType === 'string' ? b.blockType.trim() : '';
      if (
        !id ||
        !projectId ||
        !this.VALID_PROJECT_BLOCK_TYPES.has(
          blockTypeRaw as SharedProjectBlockType
        )
      ) {
        continue;
      }
      const createdAt =
        typeof b.createdAt === 'string' && b.createdAt.trim()
          ? b.createdAt.trim()
          : EthiopiaClock.nowUtc().toISOString();
      const updatedAt =
        typeof b.updatedAt === 'string' && b.updatedAt.trim()
          ? b.updatedAt.trim()
          : createdAt;
      const config = this.tryParseOptionalJsonObject(b.config ?? b.configJson);
      mapped.push({
        id,
        projectId,
        blockType: blockTypeRaw as SharedProjectBlockType,
        title: typeof b.title === 'string' ? b.title.trim() : String(b.title ?? ''),
        sortOrder:
          typeof b.sortOrder === 'number' && Number.isInteger(b.sortOrder)
            ? b.sortOrder
            : 0,
        ...(typeof b.unitLabel === 'string' && b.unitLabel.trim()
          ? { unitLabel: b.unitLabel.trim() }
          : {}),
        ...(typeof b.targetValue === 'number' && Number.isFinite(b.targetValue)
          ? { targetValue: b.targetValue }
          : {}),
        ...(typeof b.dailyTargetValue === 'number' &&
        Number.isFinite(b.dailyTargetValue)
          ? { dailyTargetValue: b.dailyTargetValue }
          : {}),
        ...(config !== undefined ? { config } : {}),
        isArchived: Boolean(b.isArchived),
        createdAt,
        updatedAt,
      });
    }
    return this.dedupeById(mapped);
  }

  private static normalizeProjectTrackingRecords(
    raw: unknown[]
  ): SharedProjectTrackingRecord[] {
    const mapped: SharedProjectTrackingRecord[] = [];
    for (const entry of raw) {
      if (!entry || typeof entry !== 'object' || Array.isArray(entry)) continue;
      const r = entry as Record<string, any>;
      const id = typeof r.id === 'string' ? r.id.trim() : '';
      const projectId =
        typeof r.projectId === 'string' ? r.projectId.trim() : '';
      const blockId = typeof r.blockId === 'string' ? r.blockId.trim() : '';
      const recordTypeRaw =
        typeof r.recordType === 'string' ? r.recordType.trim() : '';
      if (
        !id ||
        !projectId ||
        !blockId ||
        !this.VALID_PROJECT_RECORD_TYPES.has(
          recordTypeRaw as SharedProjectRecordType
        )
      ) {
        continue;
      }
      const createdAt =
        typeof r.createdAt === 'string' && r.createdAt.trim()
          ? r.createdAt.trim()
          : EthiopiaClock.nowUtc().toISOString();
      const updatedAt =
        typeof r.updatedAt === 'string' && r.updatedAt.trim()
          ? r.updatedAt.trim()
          : createdAt;
      const metadata = this.tryParseOptionalJsonObject(
        r.metadata ?? r.metadataJson
      );
      mapped.push({
        id,
        projectId,
        blockId,
        ...(typeof r.parentRecordId === 'string' && r.parentRecordId.trim()
          ? { parentRecordId: r.parentRecordId.trim() }
          : {}),
        recordType: recordTypeRaw as SharedProjectRecordType,
        ...(typeof r.title === 'string' && r.title.trim()
          ? { title: r.title.trim() }
          : {}),
        sortOrder:
          typeof r.sortOrder === 'number' && Number.isInteger(r.sortOrder)
            ? r.sortOrder
            : 0,
        ...(typeof r.targetValue === 'number' && Number.isFinite(r.targetValue)
          ? { targetValue: r.targetValue }
          : {}),
        ...(typeof r.deltaValue === 'number' && Number.isFinite(r.deltaValue)
          ? { deltaValue: r.deltaValue }
          : {}),
        ...(typeof r.durationMinutes === 'number' &&
        Number.isInteger(r.durationMinutes)
          ? { durationMinutes: r.durationMinutes }
          : {}),
        isCompleted: Boolean(r.isCompleted),
        ...(typeof r.completedAt === 'string' && r.completedAt.trim()
          ? { completedAt: r.completedAt.trim() }
          : {}),
        ...(typeof r.recordedDate === 'string' && r.recordedDate.trim()
          ? { recordedDate: r.recordedDate.trim() }
          : {}),
        ...(typeof r.scheduledDate === 'string' && r.scheduledDate.trim()
          ? { scheduledDate: r.scheduledDate.trim() }
          : {}),
        ...(typeof r.linkedTaskId === 'string' && r.linkedTaskId.trim()
          ? { linkedTaskId: r.linkedTaskId.trim() }
          : {}),
        ...(metadata !== undefined ? { metadata } : {}),
        createdAt,
        updatedAt,
      });
    }
    return this.dedupeById(mapped);
  }

  private static normalizeGoals(raw: unknown[]): SharedGoal[] {
    const mapped: SharedGoal[] = [];
    for (const entry of raw) {
      if (!entry || typeof entry !== 'object') continue;
      const g = entry as Record<string, any>;
      const id = typeof g.id === 'string' ? g.id.trim() : '';
      if (!id) continue;
      const status: SharedGoal['status'] =
        g.status === 'achieved' || g.status === 'archived' || g.status === 'active'
          ? g.status
          : 'active';
      mapped.push({
        ...(g as SharedGoal),
        id,
        title: typeof g.title === 'string' ? g.title : String(g.title ?? ''),
        ...(g.description !== undefined ? { description: g.description } : {}),
        status,
        ...(g.targetDate ? { targetDate: g.targetDate } : {}),
      });
    }
    return this.dedupeById(mapped);
  }

  private static normalizeInboxItems(raw: unknown[]): SharedInboxItem[] {
    const mapped: SharedInboxItem[] = [];
    for (const entry of raw) {
      if (!entry || typeof entry !== 'object') continue;
      const item = entry as Record<string, any>;
      const id = typeof item.id === 'string' ? item.id.trim() : '';
      if (!id) continue;
      const rawText =
        item.rawText !== undefined
          ? String(item.rawText)
          : item.text !== undefined
            ? String(item.text)
            : '';
      const category: SharedInboxItem['category'] = this.VALID_INBOX_CATEGORIES.has(item.category)
        ? item.category
        : 'general';
      const createdAt =
        typeof item.createdAt === 'string' && item.createdAt
          ? item.createdAt
          : typeof item.createdAtUtc === 'string' && item.createdAtUtc
            ? item.createdAtUtc
            : EthiopiaClock.nowUtc().toISOString();
      mapped.push({
        ...(item as SharedInboxItem),
        id,
        rawText,
        category,
        isProcessed: Boolean(item.isProcessed),
        createdAt,
      });
    }
    return this.dedupeById(mapped);
  }

  /**
   * Reads all live individual module stores from localStorage and assembles
   * the complete canonical database state. Falls back to canonical seed ONLY when keys are absent.
   */
  public static assembleLiveDatabaseState(): SharedDatabaseStateV7 {
    if (typeof window === 'undefined') {
      return {
        ...(JSON.parse(JSON.stringify(CANONICAL_SEED_DATABASE)) as SharedDatabaseStateV7),
        snapshotFormatVersion: this.SUPPORTED_SNAPSHOT_FORMAT_VERSION,
        financeSchemaVersion: this.SUPPORTED_FINANCE_SCHEMA_VERSION,
        milestones: [],
        dailyRhythmDays: [],
        projectTrackingBlocks: [],
        projectTrackingRecords: [],
      };
    }

    try {
      const canonicalStored = this.readCanonicalStoredState();

      // 1. Accounts (explicit [] stays [])
      const explicitAccounts = this.readExplicitJsonArray('daywell_accounts');
      const accounts: SharedAccount[] = explicitAccounts.exists
        ? this.normalizeAccounts(explicitAccounts.items)
        : Array.isArray(canonicalStored?.accounts)
          ? this.normalizeAccounts(canonicalStored.accounts)
          : this.normalizeAccounts(
              JSON.parse(JSON.stringify(CANONICAL_SEED_DATABASE.accounts)) as unknown[]
            );

      // 2. Categories (explicit [] stays []; seed ONLY when both live & canonical keys are missing)
      const explicitCategories = this.readExplicitJsonArray('daywell_categories');
      const categories: SharedCategory[] = explicitCategories.exists
        ? this.normalizeCategories(explicitCategories.items)
        : Array.isArray(canonicalStored?.categories)
          ? this.normalizeCategories(canonicalStored.categories)
          : this.normalizeCategories(
              JSON.parse(JSON.stringify(CANONICAL_SEED_DATABASE.categories)) as unknown[]
            );

      // 3. Transactions (check daywell_finance_transactions then daywell_transactions then canonical)
      const explicitFinanceTxs = this.readExplicitJsonArray('daywell_finance_transactions');
      const explicitLegacyTxs = this.readExplicitJsonArray('daywell_transactions');
      const transactions: SharedTransaction[] = explicitFinanceTxs.exists
        ? (explicitFinanceTxs.items as SharedTransaction[])
        : explicitLegacyTxs.exists
          ? (explicitLegacyTxs.items as SharedTransaction[])
          : Array.isArray(canonicalStored?.transactions)
            ? (canonicalStored.transactions as SharedTransaction[])
            : (JSON.parse(JSON.stringify(CANONICAL_SEED_DATABASE.transactions)) as SharedTransaction[]);

      // 4. Tasks (preserve full canonical metadata; explicit [] stays [])
      const explicitTasks = this.readExplicitJsonArray('daywell_tasks');
      const tasks: SharedTask[] = explicitTasks.exists
        ? this.normalizeTasks(explicitTasks.items)
        : Array.isArray(canonicalStored?.tasks)
          ? this.normalizeTasks(canonicalStored.tasks)
          : this.normalizeTasks(
              JSON.parse(JSON.stringify(CANONICAL_SEED_DATABASE.tasks)) as unknown[]
            );

      // 5. Notes (preserve full canonical + Web/Flutter metadata; explicit [] stays [])
      const explicitNotes = this.readExplicitJsonArray('daywell_notes');
      const notes: SharedBridgeNote[] = explicitNotes.exists
        ? this.normalizeNotes(explicitNotes.items)
        : Array.isArray(canonicalStored?.notes)
          ? this.normalizeNotes(canonicalStored.notes)
          : this.normalizeNotes(
              JSON.parse(JSON.stringify(CANONICAL_SEED_DATABASE.notes)) as unknown[]
            );

      // 6. Calendar Events (explicit [] stays [])
      const explicitCalendarEvents = this.readExplicitJsonArray('daywell_calendar_events');
      const calendarEvents: SharedBridgeCalendarEvent[] = explicitCalendarEvents.exists
        ? this.normalizeCalendarEvents(explicitCalendarEvents.items)
        : Array.isArray(canonicalStored?.calendarEvents)
          ? this.normalizeCalendarEvents(canonicalStored.calendarEvents)
          : [];

      // 7. Milestones (explicit [] stays [])
      const explicitMilestones = this.readExplicitJsonArray(this.MILESTONES_STORAGE_KEY);
      const milestones: SharedMilestone[] = explicitMilestones.exists
        ? this.normalizeMilestones(explicitMilestones.items)
        : Array.isArray(canonicalStored?.milestones)
          ? this.normalizeMilestones(canonicalStored.milestones)
          : [];

      // 7b. Daily Planning Entries (explicit [] stays [])
      const explicitDailyPlanning = this.readExplicitJsonArray(
        this.DAILY_PLANNING_STORAGE_KEY
      );
      const dailyPlanningEntries: SharedDailyPlanningEntry[] =
        explicitDailyPlanning.exists
          ? this.normalizeDailyPlanningEntries(explicitDailyPlanning.items)
          : Array.isArray(canonicalStored?.dailyPlanningEntries)
            ? this.normalizeDailyPlanningEntries(
                canonicalStored.dailyPlanningEntries
              )
            : [];

      // 7c. Daily Rhythm Days (explicit [] stays [])
      const explicitDailyRhythm = this.readExplicitJsonArray(
        this.DAILY_RHYTHM_STORAGE_KEY
      );
      const dailyRhythmDays: SharedDailyRhythmDay[] = explicitDailyRhythm.exists
        ? normalizeDailyRhythmTimeline(explicitDailyRhythm.items)
        : Array.isArray(canonicalStored?.dailyRhythmDays)
          ? normalizeDailyRhythmTimeline(canonicalStored.dailyRhythmDays)
          : [];

      // 8. v7 Finance collections (live store overrides canonical if present)
      const readCollectionWithCanonicalFallback = <T>(
        key: string,
        canonicalArr: unknown
      ): T[] => {
        const explicit = this.readExplicitJsonArray(key);
        if (explicit.exists) return explicit.items as T[];
        if (Array.isArray(canonicalArr)) return canonicalArr as T[];
        return [];
      };

      const commitments = readCollectionWithCanonicalFallback<SharedCommitment>(
        'daywell_commitments',
        canonicalStored?.commitments
      );
      const commitmentSettlements = readCollectionWithCanonicalFallback<SharedCommitmentSettlement>(
        'daywell_commitment_settlements',
        canonicalStored?.commitmentSettlements
      );
      const savingsGoals = readCollectionWithCanonicalFallback<SharedSavingsGoal>(
        'daywell_savings_goals',
        canonicalStored?.savingsGoals
      );
      const budgets = readCollectionWithCanonicalFallback<SharedBudget>(
        'daywell_budgets',
        canonicalStored?.budgets
      );
      const recurringRules = readCollectionWithCanonicalFallback<SharedRecurringRule>(
        'daywell_recurring_rules',
        canonicalStored?.recurringRules
      );
      const parties = readCollectionWithCanonicalFallback<Party>(
        'daywell_parties',
        canonicalStored?.parties
      );
      const rawJournalEntries = readCollectionWithCanonicalFallback<JournalEntry>(
        'daywell_journal_entries',
        canonicalStored?.journalEntries
      );
      const journalEntries = rawJournalEntries.map((entry) => {
        if (!entry || typeof entry !== 'object') return entry;
        const normalized = tryNormalizeEntryType(
          typeof entry.entryType === 'string' ? entry.entryType : undefined
        );
        return normalized ? { ...entry, entryType: normalized } : entry;
      });
      const postings = readCollectionWithCanonicalFallback<Posting>(
        'daywell_postings',
        canonicalStored?.postings
      );
      const rawDebts = readCollectionWithCanonicalFallback<Debt>(
        'daywell_debts',
        canonicalStored?.debts
      );
      const debts = rawDebts.map((debt) => {
        if (!debt || typeof debt !== 'object') return debt;
        const normalized = tryNormalizeDebtStatus(
          typeof debt.status === 'string' ? debt.status : undefined
        );
        return normalized ? { ...debt, status: normalized } : debt;
      });
      const settlementAllocations = readCollectionWithCanonicalFallback<SettlementAllocation>(
        'daywell_settlement_allocations',
        canonicalStored?.settlementAllocations
      );

      // 9. Projects, Goals & Inbox Items (authoritative live stores with canonical fallback; never seed-override live/deleted state)
      const explicitProjects = this.readExplicitJsonArray(this.PROJECTS_STORAGE_KEY);
      const projects: SharedProject[] = explicitProjects.exists
        ? this.normalizeProjects(explicitProjects.items)
        : Array.isArray(canonicalStored?.projects)
          ? this.normalizeProjects(canonicalStored.projects)
          : JSON.parse(JSON.stringify(CANONICAL_SEED_DATABASE.projects));

      const explicitProjectBlocks = this.readExplicitJsonArray(
        this.PROJECT_TRACKING_BLOCKS_STORAGE_KEY
      );
      const projectTrackingBlocks: SharedProjectTrackingBlock[] =
        explicitProjectBlocks.exists
          ? this.normalizeProjectTrackingBlocks(explicitProjectBlocks.items)
          : Array.isArray(canonicalStored?.projectTrackingBlocks)
            ? this.normalizeProjectTrackingBlocks(
                canonicalStored.projectTrackingBlocks
              )
            : [];

      const explicitProjectRecords = this.readExplicitJsonArray(
        this.PROJECT_TRACKING_RECORDS_STORAGE_KEY
      );
      const projectTrackingRecords: SharedProjectTrackingRecord[] =
        explicitProjectRecords.exists
          ? this.normalizeProjectTrackingRecords(explicitProjectRecords.items)
          : Array.isArray(canonicalStored?.projectTrackingRecords)
            ? this.normalizeProjectTrackingRecords(
                canonicalStored.projectTrackingRecords
              )
            : [];

      const explicitGoals = this.readExplicitJsonArray(this.GOALS_STORAGE_KEY);
      const goals: SharedGoal[] = explicitGoals.exists
        ? this.normalizeGoals(explicitGoals.items)
        : Array.isArray(canonicalStored?.goals)
          ? this.normalizeGoals(canonicalStored.goals)
          : JSON.parse(JSON.stringify(CANONICAL_SEED_DATABASE.goals));

      const primaryInbox = this.readExplicitJsonArray(this.INBOX_STORAGE_KEY);
      const explicitInbox = primaryInbox.exists
        ? primaryInbox
        : this.readExplicitJsonArray(this.LEGACY_INBOX_STORAGE_KEY);
      const inboxItems: SharedInboxItem[] = explicitInbox.exists
        ? this.normalizeInboxItems(explicitInbox.items)
        : Array.isArray(canonicalStored?.inboxItems)
          ? this.normalizeInboxItems(canonicalStored.inboxItems)
          : JSON.parse(JSON.stringify(CANONICAL_SEED_DATABASE.inboxItems));

      // 10. Optional Reminders & AppSettings (present when stored or canonical)
      const explicitReminders = this.readExplicitJsonArray(this.REMINDERS_STORAGE_KEY);
      const hasReminders =
        explicitReminders.exists || Array.isArray(canonicalStored?.reminders);
      const reminders = hasReminders
        ? this.normalizeAssembledReminders(
            explicitReminders.exists
              ? explicitReminders.items
              : (canonicalStored?.reminders as unknown[])
          )
        : undefined;

      const explicitAppSettings = this.readExplicitJsonArray(
        this.APP_SETTINGS_STORAGE_KEY
      );
      const hasAppSettings =
        explicitAppSettings.exists || Array.isArray(canonicalStored?.appSettings);
      const appSettings = hasAppSettings
        ? this.normalizeAssembledAppSettings(
            explicitAppSettings.exists
              ? explicitAppSettings.items
              : (canonicalStored?.appSettings as unknown[])
          )
        : undefined;

      // 11. Setup flag & opening balance (ETB-isolated)
      const rawSetupFlag = localStorage.getItem('daywell_finance_setup_completed');
      const isSetupCompleted =
        rawSetupFlag !== null
          ? rawSetupFlag === 'true'
          : Boolean(canonicalStored?.isFinanceSetupCompleted);
      const openingBalanceCents = accounts
        .filter((a) => !a.isSystem && !a.isArchived && isEtbCurrency(a.currencyCode))
        .reduce((sum, a) => sum + (a.openingBalanceCents || 0), 0);
      const ledgerMigrationReportV7 =
        typeof canonicalStored?.ledgerMigrationReportV7 === 'string'
          ? canonicalStored.ledgerMigrationReportV7
          : undefined;

      return {
        schemaVersion: this.SUPPORTED_EXCHANGE_SCHEMA_VERSION,
        snapshotFormatVersion: this.SUPPORTED_SNAPSHOT_FORMAT_VERSION,
        databaseSchemaVersion: this.SUPPORTED_DATABASE_SCHEMA_VERSION,
        financeSchemaVersion: this.SUPPORTED_FINANCE_SCHEMA_VERSION,
        appVersion:
          typeof canonicalStored?.appVersion === 'string' && canonicalStored.appVersion.trim()
            ? canonicalStored.appVersion.trim()
            : '1.0.2+3',
        exportedAt: LocalDateTime.now().toEthiopiaIsoString(),
        isFinanceSetupCompleted: isSetupCompleted,
        openingBalanceCents,
        ...(ledgerMigrationReportV7 !== undefined ? { ledgerMigrationReportV7 } : {}),
        accounts,
        categories,
        transactions,
        commitments,
        commitmentSettlements,
        savingsGoals,
        budgets,
        recurringRules,
        parties,
        journalEntries,
        postings,
        debts,
        settlementAllocations,
        milestones,
        tasks,
        dailyPlanningEntries,
        dailyRhythmDays,
        notes,
        projects,
        projectTrackingBlocks,
        projectTrackingRecords,
        goals,
        inboxItems,
        calendarEvents,
        ...(reminders !== undefined ? { reminders } : {}),
        ...(appSettings !== undefined ? { appSettings } : {}),
      };
    } catch (e) {
      console.warn('[SharedStateBridge] Error assembling live database, falling back to seed:', e);
      return {
        ...(JSON.parse(JSON.stringify(CANONICAL_SEED_DATABASE)) as SharedDatabaseStateV7),
        snapshotFormatVersion: this.SUPPORTED_SNAPSHOT_FORMAT_VERSION,
        databaseSchemaVersion: this.SUPPORTED_DATABASE_SCHEMA_VERSION,
        financeSchemaVersion: this.SUPPORTED_FINANCE_SCHEMA_VERSION,
        milestones: [],
        dailyPlanningEntries: [],
        dailyRhythmDays: [],
        projectTrackingBlocks: [],
        projectTrackingRecords: [],
      };
    }
  }

  /**
   * Loads the current canonical database state.
   */
  public static loadCanonicalState(): SharedDatabaseStateV7 {
    return this.assembleLiveDatabaseState();
  }

  /**
   * Persists canonical database state across the unified canonical key
   * AND synchronizes all individual module stores so UI components update without dropping metadata.
   */
  public static saveCanonicalState(state: SharedDatabaseStateV7): void {
    if (typeof window === 'undefined') return;
    try {
      const accounts = Array.isArray(state.accounts)
        ? this.normalizeAccounts(state.accounts)
        : [];
      const categories = Array.isArray(state.categories)
        ? this.normalizeCategories(state.categories)
        : [];
      const transactions = Array.isArray(state.transactions) ? state.transactions : [];
      const tasks = Array.isArray(state.tasks) ? this.normalizeTasks(state.tasks) : [];
      const notes = Array.isArray(state.notes) ? this.normalizeNotes(state.notes) : [];
      const projects = this.normalizeProjects(Array.isArray(state.projects) ? state.projects : []);
      const projectTrackingBlocks = this.normalizeProjectTrackingBlocks(
        Array.isArray(state.projectTrackingBlocks)
          ? state.projectTrackingBlocks
          : []
      );
      const projectTrackingRecords = this.normalizeProjectTrackingRecords(
        Array.isArray(state.projectTrackingRecords)
          ? state.projectTrackingRecords
          : []
      );
      const goals = this.normalizeGoals(Array.isArray(state.goals) ? state.goals : []);
      const milestones = this.normalizeMilestones(
        Array.isArray(state.milestones) ? state.milestones : []
      );
      const dailyPlanningEntries = this.normalizeDailyPlanningEntries(
        Array.isArray(state.dailyPlanningEntries) ? state.dailyPlanningEntries : []
      );
      const dailyRhythmDays = normalizeDailyRhythmTimeline(
        Array.isArray(state.dailyRhythmDays) ? state.dailyRhythmDays : []
      );
      const inboxItems = this.normalizeInboxItems(
        Array.isArray(state.inboxItems) ? state.inboxItems : []
      );
      const calendarEvents = this.normalizeCalendarEvents(
        Array.isArray(state.calendarEvents) ? state.calendarEvents : []
      );
      const reminders = Array.isArray(state.reminders)
        ? this.normalizeAssembledReminders(state.reminders)
        : undefined;
      const appSettings = Array.isArray(state.appSettings)
        ? this.normalizeAssembledAppSettings(state.appSettings)
        : undefined;

      const {
        reminders: _omittedReminders,
        appSettings: _omittedSettings,
        ...restState
      } = state;

      const normalizedState: SharedDatabaseStateV7 = {
        ...restState,
        accounts,
        categories,
        transactions,
        tasks,
        dailyPlanningEntries,
        dailyRhythmDays,
        notes,
        projects,
        projectTrackingBlocks,
        projectTrackingRecords,
        goals,
        milestones,
        inboxItems,
        calendarEvents,
        ...(reminders !== undefined ? { reminders } : {}),
        ...(appSettings !== undefined ? { appSettings } : {}),
      };

      localStorage.setItem(this.STORAGE_KEY, JSON.stringify(normalizedState));

      // Synchronize all individual module stores
      localStorage.setItem('daywell_accounts', JSON.stringify(normalizedState.accounts));
      localStorage.setItem('daywell_categories', JSON.stringify(normalizedState.categories));
      // Save to BOTH transaction keys for complete backward and forward compatibility
      localStorage.setItem(
        'daywell_finance_transactions',
        JSON.stringify(normalizedState.transactions)
      );
      localStorage.setItem('daywell_transactions', JSON.stringify(normalizedState.transactions));

      // Synchronize v7 finance stores
      localStorage.setItem('daywell_commitments', JSON.stringify(normalizedState.commitments || []));
      localStorage.setItem(
        'daywell_commitment_settlements',
        JSON.stringify(normalizedState.commitmentSettlements || [])
      );
      localStorage.setItem(
        'daywell_savings_goals',
        JSON.stringify(normalizedState.savingsGoals || [])
      );
      localStorage.setItem('daywell_budgets', JSON.stringify(normalizedState.budgets || []));
      localStorage.setItem(
        'daywell_recurring_rules',
        JSON.stringify(normalizedState.recurringRules || [])
      );
      localStorage.setItem('daywell_parties', JSON.stringify(normalizedState.parties || []));
      localStorage.setItem(
        'daywell_journal_entries',
        JSON.stringify(normalizedState.journalEntries || [])
      );
      localStorage.setItem('daywell_postings', JSON.stringify(normalizedState.postings || []));
      localStorage.setItem('daywell_debts', JSON.stringify(normalizedState.debts || []));
      localStorage.setItem(
        'daywell_settlement_allocations',
        JSON.stringify(normalizedState.settlementAllocations || [])
      );

      // Synchronize tasks with BOTH UI (DaywellTask) and canonical metadata preserved
      const daywellTasks = normalizedState.tasks.map((t) => ({
        id: t.id,
        title: t.title,
        ...(t.description !== undefined ? { description: t.description } : {}),
        status: t.status,
        priority: t.priority,
        completed: t.status === 'completed',
        ...(t.completedAt !== undefined ? { completedAt: t.completedAt } : {}),
        ...(t.dueDate !== undefined ? { dueDate: t.dueDate } : {}),
        ...(t.scheduledDate !== undefined ? { scheduledDate: t.scheduledDate } : {}),
        ...(t.scheduledTime !== undefined ? { scheduledTime: t.scheduledTime } : {}),
        ...(t.projectId !== undefined ? { projectId: t.projectId } : {}),
        ...(t.milestoneId !== undefined ? { milestoneId: t.milestoneId } : {}),
        ...(t.estimatedDurationMinutes !== undefined
          ? { estimatedDurationMinutes: t.estimatedDurationMinutes }
          : {}),
        subtasks: (t.subtasks || []).map((st: any, idx: number) => ({
          id:
            typeof st.id === 'string' && st.id.trim()
              ? st.id.trim()
              : `${t.id}-sub-${idx + 1}`,
          title: st.title,
          completed: Boolean(st.done ?? st.completed),
        })),
        labels: t.labels || [],
        isPinned: Boolean(t.isPinned),
        isMyDay: Boolean(t.isMyDay),
        ...(t.myDayDate !== undefined ? { myDayDate: t.myDayDate } : {}),
        ...(t.recurrenceRule !== undefined ? { recurrenceRule: t.recurrenceRule } : {}),
        ...(t.recurrenceConfig !== undefined
          ? { recurrenceConfig: t.recurrenceConfig }
          : {}),
        ...(t.recurrenceRule === 'daily' ||
        t.recurrenceRule === 'weekly' ||
        t.recurrenceRule === 'monthly'
          ? { isRecurring: true, recurringRule: t.recurrenceRule }
          : {}),
        isArchived: Boolean(t.isArchived),
        sortOrder:
          typeof t.sortOrder === 'number' &&
          Number.isInteger(t.sortOrder) &&
          t.sortOrder >= 0
            ? t.sortOrder
            : 0,
        hasReminder: false,
        createdAt: t.createdAt,
        ...(t.updatedAt !== undefined ? { updatedAt: t.updatedAt } : {}),
      }));
      localStorage.setItem('daywell_tasks', JSON.stringify(daywellTasks));
      localStorage.setItem(
        this.DAILY_PLANNING_STORAGE_KEY,
        JSON.stringify(dailyPlanningEntries)
      );
      localStorage.setItem(
        this.DAILY_RHYTHM_STORAGE_KEY,
        JSON.stringify(dailyRhythmDays)
      );

      // Synchronize notes with BOTH UI (DaywellNote) and canonical/Flutter metadata preserved
      const daywellNotes = normalizedState.notes.map((n) => ({
        id: n.id,
        title: n.title,
        content: n.body,
        notebook: n.folder || 'General',
        tags: n.tags || [],
        isPinned: Boolean(n.isPinned),
        isFavorite: Boolean(n.isFavorite),
        isArchived: Boolean(n.isArchived),
        isTrashed: Boolean(n.isTrashed),
        ...(n.projectId !== undefined ? { projectId: n.projectId } : {}),
        ...(n.goalId !== undefined ? { goalId: n.goalId } : {}),
        ...(n.linkedModule !== undefined ? { linkedModule: n.linkedModule } : {}),
        ...(n.linkedId !== undefined ? { linkedId: n.linkedId } : {}),
        createdAt: n.createdAt,
        updatedAt: n.updatedAt,
      }));
      localStorage.setItem('daywell_notes', JSON.stringify(daywellNotes));
      localStorage.setItem(this.PROJECTS_STORAGE_KEY, JSON.stringify(projects));
      localStorage.setItem(
        this.PROJECT_TRACKING_BLOCKS_STORAGE_KEY,
        JSON.stringify(projectTrackingBlocks)
      );
      localStorage.setItem(
        this.PROJECT_TRACKING_RECORDS_STORAGE_KEY,
        JSON.stringify(projectTrackingRecords)
      );
      localStorage.setItem(this.GOALS_STORAGE_KEY, JSON.stringify(goals));
      localStorage.setItem(this.MILESTONES_STORAGE_KEY, JSON.stringify(milestones));
      localStorage.setItem(this.INBOX_STORAGE_KEY, JSON.stringify(inboxItems));
      localStorage.setItem(
        'daywell_calendar_events',
        JSON.stringify(normalizedState.calendarEvents || [])
      );
      if (reminders !== undefined) {
        localStorage.setItem(this.REMINDERS_STORAGE_KEY, JSON.stringify(reminders));
      } else {
        localStorage.removeItem(this.REMINDERS_STORAGE_KEY);
      }
      if (appSettings !== undefined) {
        localStorage.setItem(this.APP_SETTINGS_STORAGE_KEY, JSON.stringify(appSettings));
      } else {
        localStorage.removeItem(this.APP_SETTINGS_STORAGE_KEY);
      }

      localStorage.setItem(
        'daywell_finance_setup_completed',
        normalizedState.isFinanceSetupCompleted ? 'true' : 'false'
      );

      // Dispatch event to inform any live React components of the update
      window.dispatchEvent(new CustomEvent(this.SYNC_EVENT_NAME, { detail: normalizedState }));
    } catch (e) {
      console.error('[SharedStateBridge] Failed to persist canonical state:', e);
    }
  }

  private static saveFinanceOnlyToStorage(params: {
    schemaVersion: number;
    snapshotFormatVersion: number;
    databaseSchemaVersion?: number;
    financeSchemaVersion: number;
    appVersion: string;
    isFinanceSetupCompleted: boolean;
    openingBalanceCents: number;
    ledgerMigrationReportV7?: string | null;
    accounts: SharedAccount[];
    categories: SharedCategory[];
    transactions: SharedTransaction[];
    commitments: SharedCommitment[];
    commitmentSettlements: SharedCommitmentSettlement[];
    savingsGoals: SharedSavingsGoal[];
    budgets: SharedBudget[];
    recurringRules: SharedRecurringRule[];
    parties: Party[];
    journalEntries: JournalEntry[];
    postings: Posting[];
    debts: Debt[];
    settlementAllocations: SettlementAllocation[];
  }): SharedDatabaseStateV7 {
    const existing = this.assembleLiveDatabaseState();
    const updatedState: SharedDatabaseStateV7 = {
      ...existing,
      schemaVersion: params.schemaVersion,
      snapshotFormatVersion: params.snapshotFormatVersion,
      ...(params.databaseSchemaVersion !== undefined
        ? { databaseSchemaVersion: params.databaseSchemaVersion }
        : {}),
      financeSchemaVersion: params.financeSchemaVersion,
      appVersion: params.appVersion,
      exportedAt: LocalDateTime.now().toEthiopiaIsoString(),
      isFinanceSetupCompleted: params.isFinanceSetupCompleted,
      openingBalanceCents: params.openingBalanceCents,
      ...(params.ledgerMigrationReportV7 !== undefined
        ? { ledgerMigrationReportV7: params.ledgerMigrationReportV7 }
        : {}),
      accounts: params.accounts,
      categories: params.categories,
      transactions: params.transactions,
      commitments: params.commitments,
      commitmentSettlements: params.commitmentSettlements,
      savingsGoals: params.savingsGoals,
      budgets: params.budgets,
      recurringRules: params.recurringRules,
      parties: params.parties,
      journalEntries: params.journalEntries,
      postings: params.postings,
      debts: params.debts,
      settlementAllocations: params.settlementAllocations,
    };

    try {
      localStorage.setItem(this.STORAGE_KEY, JSON.stringify(updatedState));
      localStorage.setItem('daywell_accounts', JSON.stringify(updatedState.accounts));
      localStorage.setItem('daywell_categories', JSON.stringify(updatedState.categories));
      localStorage.setItem(
        'daywell_finance_transactions',
        JSON.stringify(updatedState.transactions)
      );
      localStorage.setItem('daywell_transactions', JSON.stringify(updatedState.transactions));
      localStorage.setItem(
        'daywell_commitments',
        JSON.stringify(updatedState.commitments || [])
      );
      localStorage.setItem(
        'daywell_commitment_settlements',
        JSON.stringify(updatedState.commitmentSettlements || [])
      );
      localStorage.setItem(
        'daywell_savings_goals',
        JSON.stringify(updatedState.savingsGoals || [])
      );
      localStorage.setItem('daywell_budgets', JSON.stringify(updatedState.budgets || []));
      localStorage.setItem(
        'daywell_recurring_rules',
        JSON.stringify(updatedState.recurringRules || [])
      );
      localStorage.setItem('daywell_parties', JSON.stringify(updatedState.parties || []));
      localStorage.setItem(
        'daywell_journal_entries',
        JSON.stringify(updatedState.journalEntries || [])
      );
      localStorage.setItem('daywell_postings', JSON.stringify(updatedState.postings || []));
      localStorage.setItem('daywell_debts', JSON.stringify(updatedState.debts || []));
      localStorage.setItem(
        'daywell_settlement_allocations',
        JSON.stringify(updatedState.settlementAllocations || [])
      );
      localStorage.setItem(
        'daywell_finance_setup_completed',
        updatedState.isFinanceSetupCompleted ? 'true' : 'false'
      );

      window.dispatchEvent(new CustomEvent(this.SYNC_EVENT_NAME, { detail: updatedState }));
    } catch (e) {
      console.error('[SharedStateBridge] Failed to persist finance-only state:', e);
    }

    return updatedState;
  }

  /**
   * Exports canonical state formatted for direct import into Android application.
   */
  public static exportToAndroidJson(state?: SharedDatabaseStateV7): string {
    const active = state || this.assembleLiveDatabaseState();
    return JSON.stringify(active, null, 2);
  }

  /**
   * Exports a strict Finance-only JSON snapshot excluding Tasks, Notes, Projects,
   * Goals, Calendar Events, Reminders, Inbox Items, and non-Finance settings.
   */
  public static exportFinanceOnlyJson(state?: SharedDatabaseStateV7): string {
    const active = state || this.assembleLiveDatabaseState();
    const payload: FinanceOnlySnapshotV7 = {
      financeOnly: true,
      exportScope: 'finance_only',
      schemaVersion: this.SUPPORTED_EXCHANGE_SCHEMA_VERSION,
      snapshotFormatVersion: this.SUPPORTED_SNAPSHOT_FORMAT_VERSION,
      databaseSchemaVersion: this.SUPPORTED_DATABASE_SCHEMA_VERSION,
      financeSchemaVersion: this.SUPPORTED_FINANCE_SCHEMA_VERSION,
      appVersion: active.appVersion || '1.0.2+3',
      exportedAt: LocalDateTime.now().toEthiopiaIsoString(),
      isFinanceSetupCompleted: Boolean(active.isFinanceSetupCompleted),
      openingBalanceCents: active.openingBalanceCents ?? 0,
      ...(active.ledgerMigrationReportV7 !== undefined
        ? { ledgerMigrationReportV7: active.ledgerMigrationReportV7 }
        : {}),
      accounts: active.accounts || [],
      categories: active.categories || [],
      parties: active.parties || [],
      transactions: active.transactions || [],
      journalEntries: active.journalEntries || [],
      postings: active.postings || [],
      debts: active.debts || [],
      settlementAllocations: active.settlementAllocations || [],
      commitments: active.commitments || [],
      commitmentSettlements: active.commitmentSettlements || [],
      savingsGoals: active.savingsGoals || [],
      budgets: active.budgets || [],
      recurringRules: active.recurringRules || [],
    };
    return JSON.stringify(payload, null, 2);
  }

  private static requireUniqueId(
    record: Record<string, any>,
    tableName: string,
    index: number,
    seenIds: Set<string>
  ): string {
    const raw = record.id;
    if (typeof raw !== 'string' || !raw.trim()) {
      throw new BackupValidationError(
        'invalid_payload',
        `Missing required non-empty string "${tableName}[${index}].id".`
      );
    }
    const id = raw.trim();
    if (seenIds.has(id)) {
      throw new BackupValidationError(
        'invalid_payload',
        `Duplicate primary key "${id}" in "${tableName}" at index ${index}.`
      );
    }
    seenIds.add(id);
    return id;
  }

  private static requireStringId(
    record: Record<string, any>,
    tableName: string,
    index: number
  ): string {
    const raw = record.id;
    if (typeof raw !== 'string' || !raw.trim()) {
      throw new BackupValidationError(
        'invalid_payload',
        `Missing required non-empty string "${tableName}[${index}].id".`
      );
    }
    return raw.trim();
  }

  private static optionalBool(
    record: Record<string, any>,
    field: string,
    ctx: string
  ): boolean | undefined {
    if (
      !Object.prototype.hasOwnProperty.call(record, field) ||
      record[field] === undefined ||
      record[field] === null
    ) {
      return undefined;
    }
    if (typeof record[field] !== 'boolean') {
      throw new BackupValidationError(
        'invalid_payload',
        `Invalid field "${ctx}.${field}": expected a boolean.`
      );
    }
    return record[field];
  }

  private static optionalString(
    record: Record<string, any>,
    field: string,
    ctx: string,
    options: { allowEmpty?: boolean } = {}
  ): string | undefined {
    if (
      !Object.prototype.hasOwnProperty.call(record, field) ||
      record[field] === undefined ||
      record[field] === null
    ) {
      return undefined;
    }
    if (typeof record[field] !== 'string') {
      throw new BackupValidationError(
        'invalid_payload',
        `Invalid field "${ctx}.${field}": expected a string.`
      );
    }
    const trimmed = record[field].trim();
    if (!options.allowEmpty && trimmed.length === 0) {
      return undefined;
    }
    return options.allowEmpty ? record[field] : trimmed;
  }

  private static optionalEnum<T extends string>(
    record: Record<string, any>,
    field: string,
    allowed: Set<T>,
    ctx: string
  ): T | undefined {
    if (
      !Object.prototype.hasOwnProperty.call(record, field) ||
      record[field] === undefined ||
      record[field] === null
    ) {
      return undefined;
    }
    if (typeof record[field] !== 'string' || !record[field].trim()) {
      throw new BackupValidationError(
        'invalid_payload',
        `Invalid field "${ctx}.${field}": expected a non-empty string.`
      );
    }
    const val = record[field].trim() as T;
    if (!allowed.has(val)) {
      throw new BackupValidationError(
        'invalid_payload',
        `Invalid field "${ctx}.${field}": "${val}" is not one of ${Array.from(allowed).join(', ')}.`
      );
    }
    return val;
  }

  private static optionalStringArray(
    record: Record<string, any>,
    field: string,
    ctx: string
  ): string[] | undefined {
    if (
      !Object.prototype.hasOwnProperty.call(record, field) ||
      record[field] === undefined ||
      record[field] === null
    ) {
      return undefined;
    }
    if (!Array.isArray(record[field])) {
      throw new BackupValidationError(
        'invalid_payload',
        `Invalid field "${ctx}.${field}": expected an array of strings.`
      );
    }
    const out: string[] = [];
    for (let i = 0; i < record[field].length; i++) {
      const item = record[field][i];
      if (typeof item !== 'string') {
        throw new BackupValidationError(
          'invalid_payload',
          `Invalid element "${ctx}.${field}[${i}]": expected a string.`
        );
      }
      const trimmed = item.trim();
      if (trimmed) out.push(trimmed);
    }
    return out;
  }

  private static requireMonthIso(
    record: Record<string, any>,
    field: string,
    ctx: string
  ): string {
    const raw = record[field];
    if (typeof raw !== 'string' || !/^\d{4}-(0[1-9]|1[0-2])$/.test(raw.trim())) {
      throw new BackupValidationError(
        'invalid_payload',
        `Invalid or missing field "${ctx}.${field}": expected YYYY-MM.`
      );
    }
    return raw.trim();
  }

  private static breakChainCycles<T extends Record<string, any>>(
    items: T[],
    refField: string
  ): T[] {
    const validIds = new Set(items.map((item) => item.id as string));
    const byId = new Map<string, T>();
    const brokenIds = new Set<string>();

    const sanitized = items.map((item) => {
      const ref = item[refField];
      if (typeof ref === 'string' && (ref === item.id || !validIds.has(ref))) {
        const copy = { ...item };
        delete copy[refField];
        return copy as T;
      }
      return { ...item } as T;
    });

    for (const item of sanitized) {
      byId.set(item.id, item);
    }

    const cleared = new Set<string>();
    for (const item of sanitized) {
      if (cleared.has(item.id)) continue;
      const visiting = new Set<string>();
      let curr: T | undefined = item;
      while (curr) {
        if (cleared.has(curr.id) || brokenIds.has(curr.id)) break;
        visiting.add(curr.id);
        const nextId = curr[refField];
        if (typeof nextId !== 'string' || !nextId) break;
        if (visiting.has(nextId)) {
          delete (curr as Record<string, any>)[refField];
          brokenIds.add(curr.id);
          break;
        }
        curr = byId.get(nextId);
      }
      for (const id of visiting) cleared.add(id);
    }

    return sanitized;
  }

  public static readonly SUPPORTED_EXCHANGE_SCHEMA_VERSION = 5;
  public static readonly SUPPORTED_SNAPSHOT_FORMAT_VERSION = 2;
  public static readonly LEGACY_OMITTED_SNAPSHOT_FORMAT_VERSION = 1;
  public static readonly MIN_SUPPORTED_SNAPSHOT_FORMAT_VERSION = 1;
  public static readonly MAX_SUPPORTED_SNAPSHOT_FORMAT_VERSION = 2;
  public static readonly SUPPORTED_DATABASE_SCHEMA_VERSION = 12;
  public static readonly MAX_SUPPORTED_DATABASE_SCHEMA_VERSION = 12;
  public static readonly MIN_SUPPORTED_CANONICAL_SCHEMA_VERSION = 4;
  public static readonly MAX_SUPPORTED_CANONICAL_SCHEMA_VERSION = 9;
  public static readonly SUPPORTED_FINANCE_SCHEMA_VERSION = 7;

  private static readonly OPTIONAL_ARRAY_COLLECTIONS = [
    'categories',
    'milestones',
    'commitments',
    'commitmentSettlements',
    'savingsGoals',
    'budgets',
    'recurringRules',
    'parties',
    'journalEntries',
    'postings',
    'debts',
    'settlementAllocations',
    'tasks',
    'dailyPlanningEntries',
    'dailyRhythmDays',
    'notes',
    'projects',
    'projectTrackingBlocks',
    'projectTrackingRecords',
    'goals',
    'inboxItems',
    'calendarEvents',
    'reminders',
    'appSettings',
  ] as const;

  private static readonly FINANCE_OPTIONAL_ARRAY_COLLECTIONS = [
    'categories',
    'parties',
    'journalEntries',
    'postings',
    'debts',
    'settlementAllocations',
    'commitments',
    'commitmentSettlements',
    'savingsGoals',
    'budgets',
    'recurringRules',
  ] as const;

  private static readonly NON_FINANCE_MODULE_KEYS = [
    'tasks',
    'dailyPlanningEntries',
    'dailyRhythmDays',
    'notes',
    'projects',
    'projectTrackingBlocks',
    'projectTrackingRecords',
    'milestones',
    'goals',
    'inboxItems',
    'calendarEvents',
    'reminders',
    'appSettings',
  ] as const;

  private static requireBoundedString(
    record: Record<string, any>,
    field: string,
    ctx: string,
    maxLength: number
  ): string {
    const val = record[field];
    if (typeof val !== 'string') {
      throw new BackupValidationError(
        'invalid_payload',
        `Invalid or missing field "${ctx}.${field}": expected a non-empty string.`
      );
    }
    const trimmed = val.trim();
    if (!trimmed) {
      throw new BackupValidationError(
        'invalid_payload',
        `Invalid field "${ctx}.${field}": cannot be empty.`
      );
    }
    if (trimmed.length > maxLength) {
      throw new BackupValidationError(
        'invalid_payload',
        `Invalid field "${ctx}.${field}": length ${trimmed.length} exceeds maximum of ${maxLength} characters.`
      );
    }
    return trimmed;
  }

  private static requireIntMin(
    record: Record<string, any>,
    field: string,
    ctx: string,
    min: number
  ): number {
    const val = record[field];
    if (typeof val !== 'number' || !Number.isInteger(val)) {
      throw new BackupValidationError(
        'invalid_payload',
        `Invalid or missing field "${ctx}.${field}": expected an integer.`
      );
    }
    if (val < min) {
      throw new BackupValidationError(
        'invalid_payload',
        `Invalid field "${ctx}.${field}": value ${val} must be >= ${min}.`
      );
    }
    return val;
  }

  private static optionalIntMin(
    record: Record<string, any>,
    field: string,
    ctx: string,
    min: number
  ): number | undefined {
    if (
      !Object.prototype.hasOwnProperty.call(record, field) ||
      record[field] === undefined ||
      record[field] === null
    ) {
      return undefined;
    }
    return this.requireIntMin(record, field, ctx, min);
  }

  private static validateIncomingSnapshot(raw: unknown): {
    record: Record<string, any>;
    schemaVersion: number;
    snapshotFormatVersion: number;
    databaseSchemaVersion?: number;
    financeSchemaVersion: number;
    usesModernFinanceV7Rules: boolean;
  } {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
      throw new BackupValidationError(
        'invalid_payload',
        'Snapshot payload must be a JSON object.'
      );
    }

    const record = raw as Record<string, any>;
    const versionInfo = interpretSnapshotVersions(record);

    if (!Array.isArray(record.accounts) || !Array.isArray(record.transactions)) {
      throw new BackupValidationError(
        'invalid_payload',
        'Database payload is missing required accounts or transactions array.'
      );
    }

    for (const key of this.OPTIONAL_ARRAY_COLLECTIONS) {
      if (
        Object.prototype.hasOwnProperty.call(record, key) &&
        record[key] !== undefined &&
        !Array.isArray(record[key])
      ) {
        throw new BackupValidationError(
          'invalid_payload',
          `Invalid snapshot field "${key}": expected an array.`
        );
      }
    }

    const arrayFieldsToCheck: readonly string[] = [
      'accounts',
      'transactions',
      ...this.OPTIONAL_ARRAY_COLLECTIONS,
    ];
    for (const key of arrayFieldsToCheck) {
      const value = record[key];
      if (!Array.isArray(value)) continue;
      for (let i = 0; i < value.length; i++) {
        const entry = value[i];
        if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid record in "${key}" at index ${i}: expected a JSON object.`
          );
        }
      }
    }

    return {
      record,
      schemaVersion: versionInfo.schemaVersion,
      snapshotFormatVersion: versionInfo.snapshotFormatVersion,
      ...(versionInfo.databaseSchemaVersion !== undefined
        ? { databaseSchemaVersion: versionInfo.databaseSchemaVersion }
        : {}),
      financeSchemaVersion:
        versionInfo.financeSchemaVersion ?? this.SUPPORTED_FINANCE_SCHEMA_VERSION,
      usesModernFinanceV7Rules: versionInfo.usesModernFinanceV7Rules,
    };
  }

  /**
   * Validates and imports a JSON database exported from either Web or Android.
   * Performs strict fail-closed validation before any localStorage mutation.
   */
  public static importFromAndroidJson(
    jsonString: string
  ): {
    success: boolean;
    state?: SharedDatabaseStateV7;
    error?: string;
    errorKind?: BackupFailureKind;
  } {
    try {
      let rawParsed: unknown;
      try {
        rawParsed = JSON.parse(jsonString);
      } catch {
        return {
          success: false,
          error: 'Invalid JSON payload.',
          errorKind: 'invalid_payload',
        };
      }

      const {
        record: parsed,
        schemaVersion,
        snapshotFormatVersion,
        databaseSchemaVersion,
        financeSchemaVersion,
        usesModernFinanceV7Rules,
      } = this.validateIncomingSnapshot(rawParsed);

      const nowIso = EthiopiaClock.nowUtc().toISOString();

      const normalizeOptionalDate = (
        val: unknown,
        fieldName: string
      ): string | undefined => {
        if (val == null) return undefined;
        if (typeof val !== 'string') {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid date value "${val}" for ${fieldName}.`
          );
        }
        if (val.trim() === '') return undefined;
        const parsedDate = SharedDateFormatter.tryParseFlexibleToCalendarDate(val);
        if (!parsedDate) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid date value "${val}" for ${fieldName}.`
          );
        }
        return parsedDate.toIsoString();
      };

      const normalizeRequiredDate = (
        val: unknown,
        fieldName: string
      ): string => {
        const parsedDate = normalizeOptionalDate(val, fieldName);
        if (!parsedDate) {
          throw new BackupValidationError(
            'invalid_payload',
            `Missing required date value for ${fieldName}.`
          );
        }
        return parsedDate;
      };

      const normalizeRequiredInstant = (val: unknown, fieldName: string): string => {
        if (typeof val !== 'string' || !val.trim()) {
          throw new BackupValidationError(
            'invalid_payload',
            `Missing or invalid ISO timestamp for ${fieldName}.`
          );
        }
        const trimmed = val.trim();
        const ms = Date.parse(trimmed);
        if (Number.isNaN(ms)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid ISO timestamp "${val}" for ${fieldName}.`
          );
        }
        return new Date(ms).toISOString();
      };

      const normalizeOptionalInstant = (
        val: unknown,
        fieldName: string
      ): string | undefined => {
        if (val === undefined || val === null) return undefined;
        return normalizeRequiredInstant(val, fieldName);
      };

      // 1. Categories
      const categorySeenIds = new Set<string>();
      const rawCategories = (parsed.categories || []) as Record<string, any>[];
      const stagedCategories = rawCategories.map((c, idx) => {
        const ctx = `categories[${idx}]`;
        const id = this.requireUniqueId(c, 'categories', idx, categorySeenIds);
        const name = this.requireBoundedString(c, 'name', ctx, 100);
        const type = this.optionalEnum(c, 'type', this.VALID_CATEGORY_TYPES, ctx);
        if (!type) {
          throw new BackupValidationError(
            'invalid_payload',
            `Missing required field "${ctx}.type" (expected income or expense).`
          );
        }
        const colorHex =
          this.optionalString(c, 'colorHex', ctx) ?? '#1B4D3E';
        const parentId = this.optionalString(c, 'parentId', ctx);
        const sortOrder = this.optionalIntMin(c, 'sortOrder', ctx, -1000000) ?? 0;
        const isDefault = this.optionalBool(c, 'isDefault', ctx) ?? false;
        const isArchived = this.optionalBool(c, 'isArchived', ctx) ?? false;
        return {
          ...c,
          id,
          name,
          type,
          colorHex,
          ...(parentId !== undefined ? { parentId } : {}),
          sortOrder,
          isDefault,
          isArchived,
        } as SharedCategory;
      });

      const validatedCategories = this.breakChainCycles(
        stagedCategories,
        'parentId'
      ) as SharedCategory[];
      const validCategoryIds = new Set<string>([
        ...categorySeenIds,
        ...this.CANONICAL_STARTER_CATEGORY_ID_SET,
      ]);

      // 2. Accounts
      const accountSeenIds = new Set<string>();
      const validatedAccounts = (parsed.accounts as Record<string, any>[]).map((a, idx) => {
        const ctx = `accounts[${idx}]`;
        const id = this.requireUniqueId(a, 'accounts', idx, accountSeenIds);
        const name = this.requireBoundedString(a, 'name', ctx, 150);
        const type =
          this.optionalEnum(a, 'type', this.VALID_ACCOUNT_TYPES, ctx) ?? 'asset';
        const subType = this.optionalString(a, 'subType', ctx);
        const isSystem = this.optionalBool(a, 'isSystem', ctx);
        const isSystemAccount = Boolean(isSystem) || this.SYSTEM_CONTROL_ACCOUNT_ID_SET.has(id);
        const hasCurrencyField =
          Object.prototype.hasOwnProperty.call(a, 'currencyCode') &&
          a.currencyCode !== undefined &&
          a.currencyCode !== null;
        const rawCurrency = this.optionalString(a, 'currencyCode', ctx, { allowEmpty: true });

        let currencyCode: string;
        if (isSystemAccount) {
          if (hasCurrencyField) {
            const trimmedSys = (rawCurrency ?? '').trim();
            if (trimmedSys !== '' && !isEtbCurrency(trimmedSys)) {
              throw new BackupValidationError(
                'invalid_payload',
                `Invalid ${ctx}.currencyCode: system control account "${name}" must use ETB.`
              );
            }
          }
          currencyCode = 'ETB';
        } else if (hasCurrencyField) {
          const trimmed = (rawCurrency ?? '').trim();
          if (trimmed === '') {
            currencyCode = '';
          } else if (isEtbCurrency(trimmed)) {
            currencyCode = 'ETB';
          } else if (isValidCurrencyCode(trimmed)) {
            currencyCode = normalizeCurrencyCode(trimmed);
          } else {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid ${ctx}.currencyCode on snapshot ${ctx} ("${name}"): unrecognized currency code "${normalizeCurrencyCode(trimmed)}".`
            );
          }
        } else {
          // Omitted currencyCode on user account across snapshots: preserve empty (unverified) without converting to ETB.
          currencyCode = '';
        }

        const openingBalanceCents =
          a.openingBalanceCents !== undefined && a.openingBalanceCents !== null
            ? this.requireIntMin(a, 'openingBalanceCents', ctx, Number.MIN_SAFE_INTEGER)
            : 0;
        const openingBalanceDate = normalizeOptionalDate(
          a.openingBalanceDate,
          `${ctx}.openingBalanceDate`
        );
        const isArchivedFlag = this.optionalBool(a, 'isArchived', ctx) ?? false;
        const legacyIsActiveFlag = this.optionalBool(a, 'isActive', ctx);
        const createdAt = normalizeOptionalInstant(a.createdAt, `${ctx}.createdAt`);
        const { isActive: _retiredIsActive, ...rest } = a;
        return {
          ...rest,
          id,
          name,
          type,
          ...(subType !== undefined ? { subType } : {}),
          ...(isSystem !== undefined ? { isSystem } : {}),
          currencyCode,
          openingBalanceCents,
          isArchived: isArchivedFlag || legacyIsActiveFlag === false,
          ...(openingBalanceDate !== undefined ? { openingBalanceDate } : {}),
          ...(createdAt !== undefined ? { createdAt } : {}),
        } as SharedAccount;
      });
      const targetAccountIdsWithSystem = new Set<string>([
        ...accountSeenIds,
        ...this.SYSTEM_CONTROL_ACCOUNT_ID_SET,
      ]);

      // 3. Parties
      const partySeenIds = new Set<string>();
      const validatedParties = ((parsed.parties || []) as Record<string, any>[]).map((p, idx) => {
        const ctx = `parties[${idx}]`;
        const id = this.requireUniqueId(p, 'parties', idx, partySeenIds);
        const name = this.requireBoundedString(p, 'name', ctx, 150);
        const phone = this.optionalString(p, 'phone', ctx, { allowEmpty: true });
        const notes = this.optionalString(p, 'notes', ctx, { allowEmpty: true });
        const isArchived = this.optionalBool(p, 'isArchived', ctx) ?? false;
        const createdAt = normalizeOptionalInstant(p.createdAt, `${ctx}.createdAt`) ?? nowIso;
        return {
          ...p,
          id,
          name,
          ...(phone !== undefined ? { phone } : {}),
          ...(notes !== undefined ? { notes } : {}),
          isArchived,
          createdAt,
        } as Party;
      });

      // 4. Goals (with legacy v4 savings-shaped goal partitioning)
      const rawGoalsAll = (parsed.goals || []) as Record<string, any>[];
      const rawLifeGoals: Record<string, any>[] = [];
      const legacySavingsFromGoals: Record<string, any>[] = [];
      for (const g of rawGoalsAll) {
        const isLegacySavings =
          Object.prototype.hasOwnProperty.call(g, 'targetCents') &&
          !Object.prototype.hasOwnProperty.call(g, 'status');
        if (isLegacySavings) {
          legacySavingsFromGoals.push(g);
        } else {
          rawLifeGoals.push(g);
        }
      }

      const validatedGoals = this.normalizeGoals(
        rawLifeGoals.map((g, idx) => {
          const ctx = `goals[${idx}]`;
          const id = this.requireStringId(g, 'goals', idx);
          const title = this.requireBoundedString(g, 'title', ctx, 200);
          const description = this.optionalString(g, 'description', ctx, { allowEmpty: true });
          const status =
            this.optionalEnum(g, 'status', this.VALID_GOAL_STATUSES, ctx) ?? 'active';
          const targetDate = normalizeOptionalDate(g.targetDate, `${ctx}.targetDate`);
          const createdAt = normalizeOptionalInstant(g.createdAt, `${ctx}.createdAt`);
          return {
            ...g,
            id,
            title,
            ...(description !== undefined ? { description } : {}),
            status,
            ...(targetDate !== undefined ? { targetDate } : {}),
            ...(createdAt !== undefined ? { createdAt } : {}),
          };
        })
      );
      const targetGoalIds = new Set<string>(validatedGoals.map((g) => g.id));

      // 5. Projects (preserve Test #8 dedupe; clear dangling Tier-2 goalId; validate Stage 1 fields)
      const validatedProjects = this.normalizeProjects(
        ((parsed.projects || []) as Record<string, any>[]).map((p, idx) => {
          const ctx = `projects[${idx}]`;
          const id = this.requireStringId(p, 'projects', idx);
          const title = this.requireBoundedString(p, 'title', ctx, 200);
          const description =
            this.optionalString(p, 'description', ctx, { allowEmpty: true }) ??
            this.optionalString(p, 'narrative', ctx, { allowEmpty: true }) ??
            this.optionalString(p, 'subtitle', ctx, { allowEmpty: true });
          const status =
            this.optionalEnum(p, 'status', this.VALID_PROJECT_STATUSES, ctx) ?? 'active';
          const isArchived = this.optionalBool(p, 'isArchived', ctx);
          const startDate = normalizeOptionalDate(p.startDate, `${ctx}.startDate`);
          const targetDate = normalizeOptionalDate(p.targetDate, `${ctx}.targetDate`);
          if (startDate && targetDate && targetDate < startDate) {
            throw new BackupValidationError(
              'invalid_payload',
              `Project "${id}" targetDate (${targetDate}) cannot precede startDate (${startDate}).`
            );
          }
          const customFields = this.parseStrictJsonObject(
            p,
            ['customFields', 'customFieldsJson'],
            ctx
          );
          if (customFields !== undefined) {
            try {
              validateCustomFieldsMap(customFields);
            } catch (err) {
              throw new BackupValidationError(
                'invalid_payload',
                err instanceof ProjectValidationError
                  ? err.message
                  : `Invalid customFields on ${ctx}.`
              );
            }
          }
          const rawGoalId = this.optionalString(p, 'goalId', ctx);
          const safeGoalId =
            rawGoalId && targetGoalIds.has(rawGoalId) ? rawGoalId : undefined;
          const createdAt = normalizeOptionalInstant(p.createdAt, `${ctx}.createdAt`);
          const updatedAt = normalizeOptionalInstant(p.updatedAt, `${ctx}.updatedAt`);
          const {
            goalId: _droppedGoal,
            customFieldsJson: _droppedCfJson,
            ...rest
          } = p;
          return {
            ...rest,
            id,
            title,
            ...(description !== undefined ? { description } : {}),
            status,
            ...(isArchived !== undefined ? { isArchived } : {}),
            ...(startDate !== undefined ? { startDate } : {}),
            ...(targetDate !== undefined ? { targetDate } : {}),
            ...(customFields !== undefined ? { customFields } : {}),
            ...(safeGoalId !== undefined ? { goalId: safeGoalId } : {}),
            ...(createdAt !== undefined ? { createdAt } : {}),
            ...(updatedAt !== undefined ? { updatedAt } : {}),
          };
        })
      );
      const targetProjectIds = new Set<string>(validatedProjects.map((p) => p.id));

      // 6. Milestones (Tier-1 required FK projectId -> projects)
      const milestoneSeenIds = new Set<string>();
      const validatedMilestones: SharedMilestone[] = (
        (parsed.milestones || []) as Record<string, any>[]
      ).map((m, idx) => {
        const ctx = `milestones[${idx}]`;
        const id = this.requireUniqueId(m, 'milestones', idx, milestoneSeenIds);
        const title = this.requireBoundedString(m, 'title', ctx, 200);
        const projectId = this.requireBoundedString(m, 'projectId', ctx, 200);
        if (!targetProjectIds.has(projectId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.projectId": project "${projectId}" does not exist.`
          );
        }
        const dueDate = normalizeOptionalDate(m.dueDate, `${ctx}.dueDate`);
        const isCompleted = this.optionalBool(m, 'isCompleted', ctx) ?? false;
        const createdAt = normalizeOptionalInstant(m.createdAt, `${ctx}.createdAt`) ?? nowIso;
        return {
          id,
          projectId,
          title,
          ...(dueDate !== undefined ? { dueDate } : {}),
          isCompleted,
          createdAt,
        };
      });

      // 7. Tasks (preserve full canonical metadata + v10 fields; clear dangling Tier-2 projectId/milestoneId)
      const taskSeenIds = new Set<string>();
      const validatedTasks: SharedTask[] = ((parsed.tasks || []) as Record<string, any>[]).map(
        (t, idx) => {
          const ctx = `tasks[${idx}]`;
          const id = this.requireUniqueId(t, 'tasks', idx, taskSeenIds);
          const title = this.requireBoundedString(t, 'title', ctx, 300);
          const description = this.optionalString(t, 'description', ctx, { allowEmpty: true });
          const completedBool = this.optionalBool(t, 'completed', ctx);
          const status =
            this.optionalEnum(t, 'status', this.VALID_TASK_STATUSES, ctx) ??
            (completedBool === true ? 'completed' : 'not_started');
          const priority =
            this.optionalEnum(t, 'priority', this.VALID_TASK_PRIORITIES, ctx) ?? 'medium';
          const completedAt = normalizeOptionalInstant(t.completedAt, `${ctx}.completedAt`);
          const dueDate = normalizeOptionalDate(t.dueDate, `${ctx}.dueDate`);
          const scheduledDate = normalizeOptionalDate(t.scheduledDate, `${ctx}.scheduledDate`);
          let scheduledTime: string | undefined;
          if (
            Object.prototype.hasOwnProperty.call(t, 'scheduledTime') &&
            t.scheduledTime !== undefined &&
            t.scheduledTime !== null
          ) {
            if (typeof t.scheduledTime !== 'string') {
              throw new BackupValidationError(
                'invalid_payload',
                `Invalid field "${ctx}.scheduledTime": expected a string.`
              );
            }
            const trimmedTime = t.scheduledTime.trim();
            if (!this.SCHEDULED_TIME_HHMM_REGEX.test(trimmedTime)) {
              throw new BackupValidationError(
                'invalid_payload',
                `Invalid field "${ctx}.scheduledTime": expected 24h HH:MM format.`
              );
            }
            scheduledTime = trimmedTime;
          }
          const rawProjectId = this.optionalString(t, 'projectId', ctx);
          const safeProjectId =
            rawProjectId && targetProjectIds.has(rawProjectId) ? rawProjectId : undefined;
          const rawMilestoneId = this.optionalString(t, 'milestoneId', ctx);
          const safeMilestoneId =
            rawMilestoneId && milestoneSeenIds.has(rawMilestoneId)
              ? rawMilestoneId
              : undefined;
          const estimatedDurationMinutes = this.optionalIntMin(
            t,
            'estimatedDurationMinutes',
            ctx,
            0
          );

          let subtasks: SharedTask['subtasks'] = [];
          if (t.subtasks !== undefined && t.subtasks !== null) {
            if (!Array.isArray(t.subtasks)) {
              throw new BackupValidationError(
                'invalid_payload',
                `Invalid field "${ctx}.subtasks": expected an array.`
              );
            }
            subtasks = t.subtasks.map((st: unknown, sIdx: number) => {
              if (!st || typeof st !== 'object' || Array.isArray(st)) {
                throw new BackupValidationError(
                  'invalid_payload',
                  `Invalid element "${ctx}.subtasks[${sIdx}]": expected an object.`
                );
              }
              const subObj = st as Record<string, any>;
              const subTitle = this.requireBoundedString(
                subObj,
                'title',
                `${ctx}.subtasks[${sIdx}]`,
                300
              );
              const subId =
                this.optionalString(subObj, 'id', `${ctx}.subtasks[${sIdx}]`) ??
                `${id}-sub-${sIdx + 1}`;
              const doneBool =
                subObj.done !== undefined
                  ? this.optionalBool(subObj, 'done', `${ctx}.subtasks[${sIdx}]`)
                  : this.optionalBool(subObj, 'completed', `${ctx}.subtasks[${sIdx}]`);
              return {
                id: subId,
                title: subTitle,
                done: Boolean(doneBool),
              };
            });
          }

          const labels = this.optionalStringArray(t, 'labels', ctx) ?? [];
          const isPinned = this.optionalBool(t, 'isPinned', ctx) ?? false;
          const isMyDay = this.optionalBool(t, 'isMyDay', ctx) ?? false;
          const myDayDate = normalizeOptionalDate(t.myDayDate, `${ctx}.myDayDate`);
          const recurrenceRule =
            this.optionalString(t, 'recurrenceRule', ctx) ??
            this.optionalString(t, 'recurringRule', ctx);

          let recurrenceConfig: SharedTaskRecurrenceConfig | undefined;
          const hasNonEmptyRecurrenceJson =
            typeof t.recurrenceConfigJson === 'string' &&
            t.recurrenceConfigJson.trim().length > 0;
          const hasRecurrenceObj =
            t.recurrenceConfig !== undefined && t.recurrenceConfig !== null;
          if (hasRecurrenceObj || hasNonEmptyRecurrenceJson) {
            const rawRc = this.parseStrictJsonObject(
              t,
              ['recurrenceConfig', 'recurrenceConfigJson'],
              ctx
            );
            if (rawRc !== undefined) {
              const rcCtx = `${ctx}.recurrenceConfig`;
              const freq = this.optionalEnum(
                rawRc,
                'frequency',
                this.VALID_TASK_RECURRENCE_FREQUENCIES,
                rcCtx
              );
              if (!freq) {
                throw new BackupValidationError(
                  'invalid_payload',
                  `Missing or invalid field "${rcCtx}.frequency".`
                );
              }
              const interval = this.optionalIntMin(rawRc, 'interval', rcCtx, 1);
              let weekdays: number[] | undefined;
              if (rawRc.weekdays !== undefined && rawRc.weekdays !== null) {
                if (!Array.isArray(rawRc.weekdays)) {
                  throw new BackupValidationError(
                    'invalid_payload',
                    `Invalid field "${rcCtx}.weekdays": expected an array.`
                  );
                }
                weekdays = rawRc.weekdays.map((wd: unknown, wIdx: number) => {
                  if (
                    typeof wd !== 'number' ||
                    !Number.isInteger(wd) ||
                    wd < 1 ||
                    wd > 7
                  ) {
                    throw new BackupValidationError(
                      'invalid_payload',
                      `Invalid weekday "${rcCtx}.weekdays[${wIdx}]": expected integer 1..7.`
                    );
                  }
                  return wd;
                });
              }
              const startDate = normalizeOptionalDate(
                rawRc.startDate,
                `${rcCtx}.startDate`
              );
              const endDate = normalizeOptionalDate(
                rawRc.endDate,
                `${rcCtx}.endDate`
              );
              if (startDate !== undefined && endDate !== undefined && endDate < startDate) {
                throw new BackupValidationError(
                  'invalid_payload',
                  `Invalid recurrence range on "${rcCtx}": endDate "${endDate}" precedes startDate "${startDate}".`
                );
              }
              const repeatFrom = this.optionalEnum(
                rawRc,
                'repeatFrom',
                this.VALID_TASK_RECURRENCE_REPEAT_FROM,
                rcCtx
              );
              recurrenceConfig = {
                frequency: freq,
                ...(interval !== undefined ? { interval } : {}),
                ...(weekdays !== undefined ? { weekdays } : {}),
                ...(startDate !== undefined ? { startDate } : {}),
                ...(endDate !== undefined ? { endDate } : {}),
                ...(repeatFrom !== undefined ? { repeatFrom } : {}),
              };
            }
          } else if (
            t.recurrenceConfigJson !== undefined &&
            t.recurrenceConfigJson !== null &&
            typeof t.recurrenceConfigJson !== 'string'
          ) {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid field "${ctx}.recurrenceConfigJson": expected a JSON string.`
            );
          }

          const isArchived = this.optionalBool(t, 'isArchived', ctx) ?? false;
          const sortOrder = this.optionalIntMin(t, 'sortOrder', ctx, 0) ?? 0;
          const createdAt =
            normalizeOptionalInstant(t.createdAt, `${ctx}.createdAt`) ?? nowIso;
          const updatedAt = normalizeOptionalInstant(t.updatedAt, `${ctx}.updatedAt`);

          return {
            id,
            title,
            ...(description !== undefined ? { description } : {}),
            status,
            priority,
            ...(completedAt !== undefined ? { completedAt } : {}),
            ...(dueDate !== undefined ? { dueDate } : {}),
            ...(scheduledDate !== undefined ? { scheduledDate } : {}),
            ...(scheduledTime !== undefined ? { scheduledTime } : {}),
            ...(safeProjectId !== undefined ? { projectId: safeProjectId } : {}),
            ...(safeMilestoneId !== undefined ? { milestoneId: safeMilestoneId } : {}),
            ...(estimatedDurationMinutes !== undefined ? { estimatedDurationMinutes } : {}),
            subtasks,
            labels,
            isPinned,
            isMyDay,
            ...(myDayDate !== undefined ? { myDayDate } : {}),
            ...(recurrenceRule !== undefined ? { recurrenceRule } : {}),
            ...(recurrenceConfig !== undefined ? { recurrenceConfig } : {}),
            isArchived,
            sortOrder,
            createdAt,
            ...(updatedAt !== undefined ? { updatedAt } : {}),
          };
        }
      );

      // 7a. DailyPlanningEntries (Tier-1 required FK taskId -> tasks + unique (taskId, planDate))
      const dailyPlanningSeenIds = new Set<string>();
      const dailyPlanningSeenTaskDates = new Set<string>();
      const validatedDailyPlanningEntries: SharedDailyPlanningEntry[] = (
        (parsed.dailyPlanningEntries || []) as Record<string, any>[]
      ).map((entry, idx) => {
        const ctx = `dailyPlanningEntries[${idx}]`;
        const id = this.requireUniqueId(
          entry,
          'dailyPlanningEntries',
          idx,
          dailyPlanningSeenIds
        );
        const planDate = normalizeRequiredDate(entry.planDate, `${ctx}.planDate`);
        const taskId = this.requireBoundedString(entry, 'taskId', ctx, 200);
        if (!taskSeenIds.has(taskId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.taskId": task "${taskId}" does not exist.`
          );
        }
        const compositeKey = `${taskId}::${planDate}`;
        if (dailyPlanningSeenTaskDates.has(compositeKey)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Duplicate dailyPlanningEntries key (${taskId}, ${planDate}) at ${ctx}.`
          );
        }
        dailyPlanningSeenTaskDates.add(compositeKey);
        const action =
          this.optionalEnum(
            entry,
            'action',
            this.VALID_DAILY_PLANNING_ACTIONS,
            ctx
          ) ?? 'planned';
        const createdAt =
          normalizeOptionalInstant(entry.createdAt, `${ctx}.createdAt`) ?? nowIso;
        const updatedAt = normalizeOptionalInstant(
          entry.updatedAt,
          `${ctx}.updatedAt`
        );
        return {
          id,
          planDate,
          taskId,
          action,
          createdAt,
          ...(updatedAt !== undefined ? { updatedAt } : {}),
        };
      });

      // 7a-2. DailyRhythmDays (unique canonical dateIso)
      const dailyRhythmSeenDates = new Set<string>();
      const validatedDailyRhythmDays: SharedDailyRhythmDay[] = (
        (parsed.dailyRhythmDays || []) as Record<string, any>[]
      )
        .map((entry, idx) => {
          const ctx = `dailyRhythmDays[${idx}]`;
          const dateIso = normalizeRequiredDate(entry.dateIso, `${ctx}.dateIso`);
          if (dailyRhythmSeenDates.has(dateIso)) {
            throw new BackupValidationError(
              'invalid_payload',
              `Duplicate dailyRhythmDays dateIso "${dateIso}" at ${ctx}.`
            );
          }
          dailyRhythmSeenDates.add(dateIso);

          const bibleStudyDone = this.optionalBool(entry, 'bibleStudyDone', ctx) ?? false;
          const bibleStudyCompletedAt = normalizeOptionalInstant(
            entry.bibleStudyCompletedAt,
            `${ctx}.bibleStudyCompletedAt`
          );
          const prayerDone = this.optionalBool(entry, 'prayerDone', ctx) ?? false;
          const prayerCompletedAt = normalizeOptionalInstant(
            entry.prayerCompletedAt,
            `${ctx}.prayerCompletedAt`
          );
          const taskReviewConfirmed =
            this.optionalBool(entry, 'taskReviewConfirmed', ctx) ?? false;
          const taskReviewedAt = normalizeOptionalInstant(
            entry.taskReviewedAt,
            `${ctx}.taskReviewedAt`
          );

          let taskReviewEvidence: SharedDailyRhythmTaskReviewEvidence | undefined;
          const hasEvidenceObj =
            Object.prototype.hasOwnProperty.call(entry, 'taskReviewEvidence') &&
            entry.taskReviewEvidence !== undefined &&
            entry.taskReviewEvidence !== null;
          const hasEvidenceJson =
            Object.prototype.hasOwnProperty.call(entry, 'taskReviewEvidenceJson') &&
            entry.taskReviewEvidenceJson !== undefined &&
            entry.taskReviewEvidenceJson !== null;
          if (hasEvidenceObj || hasEvidenceJson) {
            if (hasEvidenceJson && !hasEvidenceObj) {
              if (typeof entry.taskReviewEvidenceJson !== 'string') {
                throw new BackupValidationError(
                  'invalid_payload',
                  `Invalid field "${ctx}.taskReviewEvidenceJson": expected a JSON string.`
                );
              }
            }
            const rawEvidence = this.parseStrictJsonObject(
              entry,
              ['taskReviewEvidence', 'taskReviewEvidenceJson'],
              ctx
            );
            if (rawEvidence !== undefined && taskReviewConfirmed) {
              const evCtx = `${ctx}.taskReviewEvidence`;
              taskReviewEvidence = {
                overdueCount:
                  this.optionalIntMin(rawEvidence, 'overdueCount', evCtx, 0) ?? 0,
                todayCount:
                  this.optionalIntMin(rawEvidence, 'todayCount', evCtx, 0) ?? 0,
                plannedCount:
                  this.optionalIntMin(rawEvidence, 'plannedCount', evCtx, 0) ?? 0,
                completedTodayCount:
                  this.optionalIntMin(rawEvidence, 'completedTodayCount', evCtx, 0) ?? 0,
              };
            }
          }

          const financeCloseStatus =
            this.optionalEnum<SharedDailyRhythmFinanceCloseStatus>(
              entry,
              'financeCloseStatus',
              this.VALID_DAILY_RHYTHM_FINANCE_CLOSE_STATUSES,
              ctx
            ) ?? 'open';
          const financeClosedAt = normalizeOptionalInstant(
            entry.financeClosedAt,
            `${ctx}.financeClosedAt`
          );
          const updatedAt =
            normalizeOptionalInstant(entry.updatedAt, `${ctx}.updatedAt`) ?? nowIso;

          const isFinanceClosed =
            financeCloseStatus === 'closed_with_transactions' ||
            financeCloseStatus === 'closed_no_transactions';

          return {
            dateIso,
            bibleStudyDone,
            ...(bibleStudyDone && bibleStudyCompletedAt !== undefined
              ? { bibleStudyCompletedAt }
              : {}),
            prayerDone,
            ...(prayerDone && prayerCompletedAt !== undefined
              ? { prayerCompletedAt }
              : {}),
            taskReviewConfirmed,
            ...(taskReviewConfirmed && taskReviewedAt !== undefined
              ? { taskReviewedAt }
              : {}),
            ...(taskReviewConfirmed && taskReviewEvidence !== undefined
              ? { taskReviewEvidence }
              : {}),
            financeCloseStatus,
            ...(isFinanceClosed && financeClosedAt !== undefined
              ? { financeClosedAt }
              : {}),
            updatedAt,
          };
        })
        .sort((a, b) => (a.dateIso < b.dateIso ? -1 : a.dateIso > b.dateIso ? 1 : 0));

      // 7b. Project Tracking Blocks (two-pass validation: non-rollup first, then rollup counters)
      const optionalNumberMin = (
        record: Record<string, any>,
        field: string,
        ctx: string,
        min: number
      ): number | undefined => {
        if (
          !Object.prototype.hasOwnProperty.call(record, field) ||
          record[field] === undefined ||
          record[field] === null
        ) {
          return undefined;
        }
        const val = record[field];
        if (typeof val !== 'number' || !Number.isFinite(val)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid field "${ctx}.${field}": expected a finite number.`
          );
        }
        if (val < min) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid field "${ctx}.${field}": value ${val} must be >= ${min}.`
          );
        }
        return val;
      };

      const blockSeenIds = new Set<string>();
      const stagedBlocks: SharedProjectTrackingBlock[] = (
        (parsed.projectTrackingBlocks || []) as Record<string, any>[]
      ).map((b, idx) => {
        const ctx = `projectTrackingBlocks[${idx}]`;
        const id = this.requireUniqueId(
          b,
          'projectTrackingBlocks',
          idx,
          blockSeenIds
        );
        const projectId = this.requireBoundedString(b, 'projectId', ctx, 200);
        if (!targetProjectIds.has(projectId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.projectId": project "${projectId}" does not exist.`
          );
        }
        const blockType = this.optionalEnum(
          b,
          'blockType',
          this.VALID_PROJECT_BLOCK_TYPES,
          ctx
        );
        if (!blockType) {
          throw new BackupValidationError(
            'invalid_payload',
            `Missing or invalid field "${ctx}.blockType".`
          );
        }
        const title = this.requireBoundedString(b, 'title', ctx, 200);
        const sortOrder = this.optionalIntMin(b, 'sortOrder', ctx, 0) ?? 0;
        const unitLabel = this.optionalString(b, 'unitLabel', ctx);
        if (unitLabel !== undefined && unitLabel.length > 64) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid field "${ctx}.unitLabel": exceeds 64 characters.`
          );
        }
        const targetValue = optionalNumberMin(b, 'targetValue', ctx, 0);
        const dailyTargetValue = optionalNumberMin(
          b,
          'dailyTargetValue',
          ctx,
          0
        );
        const config =
          this.parseStrictJsonObject(b, ['config', 'configJson'], ctx) ?? {};
        const isArchived = this.optionalBool(b, 'isArchived', ctx) ?? false;
        const createdAt =
          normalizeOptionalInstant(b.createdAt, `${ctx}.createdAt`) ?? nowIso;
        const updatedAt =
          normalizeOptionalInstant(b.updatedAt, `${ctx}.updatedAt`) ?? createdAt;
        return {
          id,
          projectId,
          blockType,
          title,
          sortOrder,
          ...(unitLabel !== undefined ? { unitLabel } : {}),
          ...(targetValue !== undefined ? { targetValue } : {}),
          ...(dailyTargetValue !== undefined ? { dailyTargetValue } : {}),
          config,
          isArchived,
          createdAt,
          updatedAt,
        };
      });

      const stagedBlocksById = new Map<string, SharedProjectTrackingBlock>(
        stagedBlocks.map((b) => [b.id, b])
      );
      const acceptedBlocksByProject = new Map<
        string,
        SharedProjectTrackingBlock[]
      >();
      const nonRollupBlocks: SharedProjectTrackingBlock[] = [];
      const rollupBlocks: SharedProjectTrackingBlock[] = [];
      for (const blk of stagedBlocks) {
        const hasRollupSource =
          blk.blockType === 'counter' &&
          typeof blk.config?.rollupSourceBlockId === 'string' &&
          blk.config.rollupSourceBlockId.trim().length > 0;
        if (hasRollupSource) {
          rollupBlocks.push(blk);
        } else {
          nonRollupBlocks.push(blk);
        }
      }
      for (const passBlocks of [nonRollupBlocks, rollupBlocks]) {
        for (const blk of passBlocks) {
          const siblingBlocks =
            acceptedBlocksByProject.get(blk.projectId) ?? [];
          try {
            validateBlock(blk, {
              expectedProjectId: blk.projectId,
              projectBlocks: siblingBlocks,
              isNew: true,
            });
          } catch (err) {
            throw new BackupValidationError(
              'invalid_payload',
              err instanceof ProjectValidationError
                ? err.message
                : `Invalid tracking block "${blk.id}".`
            );
          }
          siblingBlocks.push(blk);
          acceptedBlocksByProject.set(blk.projectId, siblingBlocks);
        }
      }
      const validatedProjectTrackingBlocks = stagedBlocks;

      // 7c. Project Tracking Records (hierarchical parent-before-child + non-correction-before-correction validation)
      const recordSeenIds = new Set<string>();
      const stagedRecords: SharedProjectTrackingRecord[] = (
        (parsed.projectTrackingRecords || []) as Record<string, any>[]
      ).map((r, idx) => {
        const ctx = `projectTrackingRecords[${idx}]`;
        const id = this.requireUniqueId(
          r,
          'projectTrackingRecords',
          idx,
          recordSeenIds
        );
        const projectId = this.requireBoundedString(r, 'projectId', ctx, 200);
        if (!targetProjectIds.has(projectId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.projectId": project "${projectId}" does not exist.`
          );
        }
        const blockId = this.requireBoundedString(r, 'blockId', ctx, 200);
        const targetBlock = stagedBlocksById.get(blockId);
        if (!targetBlock) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.blockId": block "${blockId}" does not exist.`
          );
        }
        if (targetBlock.projectId !== projectId) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}": block "${blockId}" belongs to project "${targetBlock.projectId}", not "${projectId}".`
          );
        }
        const recordType = this.optionalEnum(
          r,
          'recordType',
          this.VALID_PROJECT_RECORD_TYPES,
          ctx
        );
        if (!recordType) {
          throw new BackupValidationError(
            'invalid_payload',
            `Missing or invalid field "${ctx}.recordType".`
          );
        }
        const parentRecordId = this.optionalString(r, 'parentRecordId', ctx);
        const title = this.optionalString(r, 'title', ctx, { allowEmpty: true });
        const maxRecordTitleLength =
          SHARED_BUSINESS_RULES.projects.bounds.maxTrackingRecordTitleLength;
        if (title !== undefined && title.trim().length > maxRecordTitleLength) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid field "${ctx}.title": exceeds ${maxRecordTitleLength} characters.`
          );
        }
        const sortOrder = this.optionalIntMin(r, 'sortOrder', ctx, 0) ?? 0;
        const targetValue = optionalNumberMin(r, 'targetValue', ctx, 0);
        let deltaValue: number | undefined;
        if (
          Object.prototype.hasOwnProperty.call(r, 'deltaValue') &&
          r.deltaValue !== undefined &&
          r.deltaValue !== null
        ) {
          if (typeof r.deltaValue !== 'number' || !Number.isFinite(r.deltaValue)) {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid field "${ctx}.deltaValue": expected a finite number.`
            );
          }
          deltaValue = r.deltaValue;
        }
        const durationMinutes = this.optionalIntMin(
          r,
          'durationMinutes',
          ctx,
          0
        );
        const isCompleted = this.optionalBool(r, 'isCompleted', ctx) ?? false;
        const completedAt = normalizeOptionalInstant(
          r.completedAt,
          `${ctx}.completedAt`
        );
        const recordedDate = normalizeOptionalDate(
          r.recordedDate,
          `${ctx}.recordedDate`
        );
        const scheduledDate = normalizeOptionalDate(
          r.scheduledDate,
          `${ctx}.scheduledDate`
        );
        const rawLinkedTaskId = this.optionalString(r, 'linkedTaskId', ctx);
        const safeLinkedTaskId =
          rawLinkedTaskId && taskSeenIds.has(rawLinkedTaskId)
            ? rawLinkedTaskId
            : undefined;
        const metadata =
          this.parseStrictJsonObject(r, ['metadata', 'metadataJson'], ctx) ?? {};
        const createdAt =
          normalizeOptionalInstant(r.createdAt, `${ctx}.createdAt`) ?? nowIso;
        const updatedAt =
          normalizeOptionalInstant(r.updatedAt, `${ctx}.updatedAt`) ?? createdAt;

        return {
          id,
          projectId,
          blockId,
          ...(parentRecordId !== undefined ? { parentRecordId } : {}),
          recordType,
          ...(title !== undefined && title.trim() ? { title: title.trim() } : {}),
          sortOrder,
          ...(targetValue !== undefined ? { targetValue } : {}),
          ...(deltaValue !== undefined ? { deltaValue } : {}),
          ...(durationMinutes !== undefined ? { durationMinutes } : {}),
          isCompleted,
          ...(completedAt !== undefined ? { completedAt } : {}),
          ...(recordedDate !== undefined ? { recordedDate } : {}),
          ...(scheduledDate !== undefined ? { scheduledDate } : {}),
          ...(safeLinkedTaskId !== undefined
            ? { linkedTaskId: safeLinkedTaskId }
            : {}),
          metadata,
          createdAt,
          updatedAt,
        };
      });

      const stagedRecordsById = new Map<string, SharedProjectTrackingRecord>(
        stagedRecords.map((r) => [r.id, r])
      );
      for (const rec of stagedRecords) {
        if (rec.parentRecordId !== undefined) {
          if (rec.parentRecordId === rec.id) {
            throw new BackupValidationError(
              'invalid_payload',
              `Project tracking record "${rec.id}" cannot set itself as parentRecordId.`
            );
          }
          const parent = stagedRecordsById.get(rec.parentRecordId);
          if (!parent) {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid foreign key "projectTrackingRecords[${rec.id}].parentRecordId": parent "${rec.parentRecordId}" does not exist.`
            );
          }
          if (
            parent.projectId !== rec.projectId ||
            parent.blockId !== rec.blockId
          ) {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid hierarchy "projectTrackingRecords[${rec.id}]": parentRecordId "${parent.id}" belongs to a different block or project.`
            );
          }
        }
        if (rec.metadata?.isCorrection === true) {
          const targetLogId =
            typeof rec.metadata.compensatesRecordId === 'string'
              ? rec.metadata.compensatesRecordId.trim()
              : '';
          if (targetLogId && targetLogId === rec.id) {
            throw new BackupValidationError(
              'invalid_payload',
              `Compensating correction "${rec.id}" cannot reference itself.`
            );
          }
          if (targetLogId) {
            const targetLog = stagedRecordsById.get(targetLogId);
            if (
              !targetLog ||
              targetLog.projectId !== rec.projectId ||
              targetLog.blockId !== rec.blockId
            ) {
              throw new BackupValidationError(
                'invalid_payload',
                `Compensating correction "${rec.id}" references missing or cross-block log "${targetLogId}".`
              );
            }
          }
        }
      }

      // Cycle detection & topological ordering (parents before children, target logs before corrections)
      const visitState = new Map<string, 'visiting' | 'visited'>();
      const orderedRecords: SharedProjectTrackingRecord[] = [];
      const visitRecord = (rec: SharedProjectTrackingRecord): void => {
        const state = visitState.get(rec.id);
        if (state === 'visited') return;
        if (state === 'visiting') {
          throw new BackupValidationError(
            'invalid_payload',
            `Cycle detected in projectTrackingRecords hierarchy involving "${rec.id}".`
          );
        }
        visitState.set(rec.id, 'visiting');
        if (rec.parentRecordId !== undefined) {
          const parent = stagedRecordsById.get(rec.parentRecordId);
          if (parent) visitRecord(parent);
        }
        if (rec.metadata?.isCorrection === true) {
          const targetId =
            typeof rec.metadata.compensatesRecordId === 'string'
              ? rec.metadata.compensatesRecordId.trim()
              : '';
          if (targetId) {
            const targetLog = stagedRecordsById.get(targetId);
            if (targetLog) visitRecord(targetLog);
          }
        }
        visitState.set(rec.id, 'visited');
        orderedRecords.push(rec);
      };
      for (const rec of stagedRecords) {
        visitRecord(rec);
      }

      const acceptedRecordsByBlock = new Map<
        string,
        SharedProjectTrackingRecord[]
      >();
      for (const rec of orderedRecords) {
        const blk = stagedBlocksById.get(rec.blockId)!;
        const existingBlockRecords =
          acceptedRecordsByBlock.get(rec.blockId) ?? [];
        try {
          validateRecord(rec, {
            block: blk,
            existingBlockRecords,
            isNew: true,
          });
        } catch (err) {
          throw new BackupValidationError(
            'invalid_payload',
            err instanceof ProjectValidationError
              ? err.message
              : `Invalid project tracking record "${rec.id}".`
          );
        }
        existingBlockRecords.push(rec);
        acceptedRecordsByBlock.set(rec.blockId, existingBlockRecords);
      }
      const validatedProjectTrackingRecords = stagedRecords;

      // 8. Notes (preserve full canonical + Web/Flutter metadata; clear dangling Tier-2 projectId/goalId)
      const noteSeenIds = new Set<string>();
      const validatedNotes: SharedBridgeNote[] = (
        (parsed.notes || []) as Record<string, any>[]
      ).map((n, idx) => {
        const ctx = `notes[${idx}]`;
        const id = this.requireUniqueId(n, 'notes', idx, noteSeenIds);
        const title = this.requireBoundedString(n, 'title', ctx, 250);
        const body =
          this.optionalString(n, 'body', ctx, { allowEmpty: true }) ??
          this.optionalString(n, 'content', ctx, { allowEmpty: true }) ??
          '';
        const folder =
          this.optionalString(n, 'folder', ctx) ??
          this.optionalString(n, 'category', ctx) ??
          this.optionalString(n, 'notebook', ctx) ??
          'General';
        const tags = this.optionalStringArray(n, 'tags', ctx) ?? [];
        const isPinned = this.optionalBool(n, 'isPinned', ctx) ?? false;
        const isFavorite = this.optionalBool(n, 'isFavorite', ctx) ?? false;
        const isArchived = this.optionalBool(n, 'isArchived', ctx) ?? false;
        const isTrashed = this.optionalBool(n, 'isTrashed', ctx) ?? false;
        const rawProjectId = this.optionalString(n, 'projectId', ctx);
        const safeProjectId =
          rawProjectId && targetProjectIds.has(rawProjectId) ? rawProjectId : undefined;
        const rawGoalId = this.optionalString(n, 'goalId', ctx);
        const safeGoalId =
          rawGoalId && targetGoalIds.has(rawGoalId) ? rawGoalId : undefined;
        const linkedModule = this.optionalEnum(
          n,
          'linkedModule',
          new Set(['tasks', 'finance', 'calendar'] as const),
          ctx
        );
        const linkedId = this.optionalString(n, 'linkedId', ctx);
        const createdAt =
          normalizeOptionalInstant(n.createdAt, `${ctx}.createdAt`) ?? nowIso;
        const updatedAt =
          normalizeOptionalInstant(n.updatedAt, `${ctx}.updatedAt`) ?? createdAt;

        return {
          id,
          title,
          body,
          folder,
          tags,
          isPinned,
          isFavorite,
          isArchived,
          isTrashed,
          ...(safeProjectId !== undefined ? { projectId: safeProjectId } : {}),
          ...(safeGoalId !== undefined ? { goalId: safeGoalId } : {}),
          ...(linkedModule !== undefined ? { linkedModule } : {}),
          ...(linkedId !== undefined ? { linkedId } : {}),
          createdAt,
          updatedAt,
        };
      });

      // 9. Inbox Items (preserve Test #8 dedupe)
      const validatedInboxItems = this.normalizeInboxItems(
        ((parsed.inboxItems || []) as Record<string, any>[]).map((item, idx) => {
          const ctx = `inboxItems[${idx}]`;
          const id = this.requireStringId(item, 'inboxItems', idx);
          const rawText =
            this.optionalString(item, 'rawText', ctx) ??
            this.optionalString(item, 'text', ctx);
          if (!rawText) {
            throw new BackupValidationError(
              'invalid_payload',
              `Missing required non-empty string "${ctx}.rawText".`
            );
          }
          const category =
            this.optionalEnum(item, 'category', this.VALID_INBOX_CATEGORIES, ctx) ??
            'general';
          const isProcessed = this.optionalBool(item, 'isProcessed', ctx) ?? false;
          const createdAt =
            normalizeOptionalInstant(
              item.createdAt ?? item.createdAtUtc,
              `${ctx}.createdAt`
            ) ?? nowIso;
          return {
            ...item,
            id,
            rawText,
            category,
            isProcessed,
            createdAt,
          };
        })
      );

      // 10. Calendar Events
      const eventSeenIds = new Set<string>();
      const validatedCalendarEvents: SharedBridgeCalendarEvent[] = (
        (parsed.calendarEvents || []) as Record<string, any>[]
      ).map((e, idx) => {
        const ctx = `calendarEvents[${idx}]`;
        const id = this.requireUniqueId(e, 'calendarEvents', idx, eventSeenIds);
        const title = this.requireBoundedString(e, 'title', ctx, 250);
        const date = normalizeRequiredDate(e.dateIso ?? e.date, `${ctx}.date`);
        const endDate = normalizeOptionalDate(
          e.endDateIso ?? e.endDate,
          `${ctx}.endDate`
        );
        if (endDate && endDate < date) {
          throw new BackupValidationError(
            'invalid_payload',
            `Calendar event "${id}" endDate (${endDate}) cannot precede date (${date}).`
          );
        }
        const startTime = this.optionalString(e, 'startTime', ctx, { allowEmpty: true });
        const endTime = this.optionalString(e, 'endTime', ctx, { allowEmpty: true });
        const isAllDay = this.optionalBool(e, 'isAllDay', ctx) ?? false;
        const category = this.optionalString(e, 'category', ctx) ?? 'personal';
        const colorHex = this.optionalString(e, 'colorHex', ctx) ?? '#1B4D3E';
        const hasReminder = this.optionalBool(e, 'hasReminder', ctx) ?? false;
        const notes = this.optionalString(e, 'notes', ctx, { allowEmpty: true });
        const description = this.optionalString(e, 'description', ctx, { allowEmpty: true });
        const location = this.optionalString(e, 'location', ctx);
        const recurrence = this.optionalEnum(
          e,
          'recurrence',
          new Set(['none', 'daily', 'weekly', 'monthly', 'yearly'] as const),
          ctx
        );
        const linkedTaskId = this.optionalString(e, 'linkedTaskId', ctx);
        const createdAt =
          normalizeOptionalInstant(e.createdAt, `${ctx}.createdAt`) ?? nowIso;
        const updatedAt =
          normalizeOptionalInstant(e.updatedAt, `${ctx}.updatedAt`) ?? createdAt;

        return {
          id,
          title,
          date,
          ...(endDate !== undefined ? { endDate } : {}),
          ...(startTime !== undefined ? { startTime } : {}),
          ...(endTime !== undefined ? { endTime } : {}),
          isAllDay,
          category,
          colorHex,
          hasReminder,
          ...(notes !== undefined ? { notes } : {}),
          ...(description !== undefined ? { description } : {}),
          ...(location !== undefined ? { location } : {}),
          ...(recurrence !== undefined ? { recurrence } : {}),
          ...(linkedTaskId !== undefined ? { linkedTaskId } : {}),
          createdAt,
          updatedAt,
        };
      });

      // 11. Transactions
      const txSeenIds = new Set<string>();
      const stagedTransactions = (parsed.transactions as Record<string, any>[]).map((tx, idx) => {
        const ctx = `transactions[${idx}]`;
        const id = this.requireUniqueId(tx, 'transactions', idx, txSeenIds);
        const type = this.optionalEnum(tx, 'type', this.VALID_TRANSACTION_TYPES, ctx);
        if (!type) {
          throw new BackupValidationError(
            'invalid_payload',
            `Missing or invalid field "${ctx}.type".`
          );
        }
        const amountCents = this.requireIntMin(tx, 'amountCents', ctx, 1);
        const transactionDate = normalizeRequiredDate(
          tx.transactionDate,
          `${ctx}.transactionDate`
        );

        let categoryId: string;
        if (tx.categoryId !== undefined && tx.categoryId !== null) {
          if (typeof tx.categoryId !== 'string' || !tx.categoryId.trim()) {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid field "${ctx}.categoryId": expected a non-empty string.`
            );
          }
          categoryId = tx.categoryId.trim();
          if (!validCategoryIds.has(categoryId)) {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid foreign key "${ctx}.categoryId": category "${categoryId}" does not exist.`
            );
          }
        } else {
          if (usesModernFinanceV7Rules) {
            const formatLabel =
              snapshotFormatVersion >= this.SUPPORTED_SNAPSHOT_FORMAT_VERSION
                ? 'format-2'
                : `v${schemaVersion}`;
            throw new BackupValidationError(
              'invalid_payload',
              `Missing required foreign key "${ctx}.categoryId" on ${formatLabel} ${type} transaction "${id}".`
            );
          }
          categoryId = type === 'income' ? 'cat-other-inc' : 'cat-other-exp';
        }

        const isSuperseded = this.optionalBool(tx, 'isSuperseded', ctx);
        const correctedFromId = this.optionalString(tx, 'correctedFromId', ctx);
        const createdAt = normalizeOptionalInstant(tx.createdAt, `${ctx}.createdAt`);

        return {
          ...tx,
          id,
          type,
          categoryId,
          amountCents,
          transactionDate,
          ...(isSuperseded !== undefined ? { isSuperseded } : {}),
          ...(correctedFromId !== undefined ? { correctedFromId } : {}),
          ...(createdAt !== undefined ? { createdAt } : {}),
        };
      });
      const validatedTransactions = this.breakChainCycles(
        stagedTransactions,
        'correctedFromId'
      ) as SharedTransaction[];

      // 12. Journal Entries
      const entrySeenIds = new Set<string>();
      const legacySourceSeen = new Map<string, string>();
      const stagedEntries = ((parsed.journalEntries || []) as Record<string, any>[]).map(
        (e, idx) => {
          const ctx = `journalEntries[${idx}]`;
          const id = this.requireUniqueId(e, 'journalEntries', idx, entrySeenIds);
          const rawEntryType = this.optionalString(e, 'entryType', ctx, {
            allowEmpty: true,
          });
          let entryType: EntryType;
          try {
            entryType = normalizeEntryType(rawEntryType, {
              defaultIfOmitted: 'standard',
            });
          } catch (err) {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid field "${ctx}.entryType": ${err instanceof Error ? err.message : String(rawEntryType)}`
            );
          }
          const occurrenceDate = normalizeRequiredDate(
            e.occurrenceDate,
            `${ctx}.occurrenceDate`
          );
          const legacySourceTxId = this.optionalString(e, 'legacySourceTxId', ctx);
          if (legacySourceTxId !== undefined) {
            const owner = legacySourceSeen.get(legacySourceTxId);
            if (owner && owner !== id) {
              throw new BackupValidationError(
                'invalid_payload',
                `Duplicate legacySourceTxId "${legacySourceTxId}" in "${ctx}".`
              );
            }
            legacySourceSeen.set(legacySourceTxId, id);
          }
          const isVoided = this.optionalBool(e, 'isVoided', ctx) ?? false;
          const correctedFromEntryId = this.optionalString(
            e,
            'correctedFromEntryId',
            ctx
          );
          const createdAt =
            normalizeOptionalInstant(e.createdAt, `${ctx}.createdAt`) ?? nowIso;
          return {
            ...e,
            id,
            entryType,
            description:
              this.optionalString(e, 'description', ctx, { allowEmpty: true }) ?? '',
            occurrenceDate,
            isVoided,
            ...(legacySourceTxId !== undefined ? { legacySourceTxId } : {}),
            ...(correctedFromEntryId !== undefined ? { correctedFromEntryId } : {}),
            createdAt,
          };
        }
      );
      const validatedJournalEntries = this.breakChainCycles(
        stagedEntries,
        'correctedFromEntryId'
      ) as JournalEntry[];

      // 13. Postings (Tier-1 FKs: entryId, accountId; plus balanced double-entry invariant per entry)
      const postingSeenIds = new Set<string>();
      const entryLedgerTotals = new Map<string, { debits: number; credits: number }>();
      const validatedPostings = ((parsed.postings || []) as Record<string, any>[]).map(
        (p, idx) => {
          const ctx = `postings[${idx}]`;
          const id = this.requireUniqueId(p, 'postings', idx, postingSeenIds);
          const amountCents = this.requireIntMin(p, 'amountCents', ctx, 1);
          const accountMovementDate = normalizeRequiredDate(
            p.accountMovementDate,
            `${ctx}.accountMovementDate`
          );
          const entryId = this.requireBoundedString(p, 'entryId', ctx, 200);
          if (!entrySeenIds.has(entryId)) {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid foreign key "${ctx}.entryId": journal entry "${entryId}" does not exist.`
            );
          }
          const accountId = this.requireBoundedString(p, 'accountId', ctx, 200);
          if (!targetAccountIdsWithSystem.has(accountId)) {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid foreign key "${ctx}.accountId": account "${accountId}" does not exist.`
            );
          }
          const direction =
            this.optionalEnum(p, 'direction', this.VALID_POSTING_DIRECTIONS, ctx) ??
            'debit';
          const rawCategoryId = this.optionalString(p, 'categoryId', ctx);
          const safeCategoryId =
            rawCategoryId && validCategoryIds.has(rawCategoryId)
              ? rawCategoryId
              : undefined;

          const running = entryLedgerTotals.get(entryId) ?? { debits: 0, credits: 0 };
          if (direction === 'debit') running.debits += amountCents;
          else running.credits += amountCents;
          entryLedgerTotals.set(entryId, running);

          const { categoryId: _droppedCat, ...rest } = p;
          return {
            ...rest,
            id,
            entryId,
            accountId,
            amountCents,
            direction,
            accountMovementDate,
            ...(safeCategoryId !== undefined ? { categoryId: safeCategoryId } : {}),
          } as Posting;
        }
      );

      for (const [entryId, totals] of entryLedgerTotals.entries()) {
        if (totals.debits !== totals.credits) {
          throw new BackupValidationError(
            'invalid_payload',
            `Unbalanced double-entry postings for journal entry "${entryId}": debits=${totals.debits}, credits=${totals.credits}.`
          );
        }
      }

      // 14. Debts (Tier-1 FKs: originEntryId, partyId)
      const debtSeenIds = new Set<string>();
      const validatedDebts = ((parsed.debts || []) as Record<string, any>[]).map((d, idx) => {
        const ctx = `debts[${idx}]`;
        const id = this.requireUniqueId(d, 'debts', idx, debtSeenIds);
        const principalCents = this.requireIntMin(d, 'principalCents', ctx, 1);
        const outstandingCents = this.optionalIntMin(d, 'outstandingCents', ctx, 0);
        const originEntryId = this.requireBoundedString(d, 'originEntryId', ctx, 200);
        if (!entrySeenIds.has(originEntryId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.originEntryId": journal entry "${originEntryId}" does not exist.`
          );
        }
        const partyId = this.requireBoundedString(d, 'partyId', ctx, 200);
        if (!partySeenIds.has(partyId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.partyId": party "${partyId}" does not exist.`
          );
        }
        const debtType =
          this.optionalEnum(d, 'debtType', this.VALID_DEBT_TYPES, ctx) ?? 'payable';
        const rawStatus = this.optionalString(d, 'status', ctx, {
          allowEmpty: true,
        });
        let normalizedStatus: DebtStatus;
        try {
          normalizedStatus = normalizeDebtStatus(rawStatus, {
            defaultIfOmitted: 'active',
          });
        } catch (err) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid field "${ctx}.status": ${err instanceof Error ? err.message : String(rawStatus)}`
          );
        }
        const rawWriteOff = this.optionalString(d, 'writeOffEntryId', ctx);
        const safeWriteOff =
          rawWriteOff && entrySeenIds.has(rawWriteOff) ? rawWriteOff : undefined;
        const dueDate = normalizeOptionalDate(d.dueDate, `${ctx}.dueDate`);
        const createdAt =
          normalizeOptionalInstant(d.createdAt, `${ctx}.createdAt`) ?? nowIso;
        const { writeOffEntryId: _droppedWo, ...rest } = d;
        return {
          ...rest,
          id,
          originEntryId,
          partyId,
          debtType,
          principalCents,
          ...(outstandingCents !== undefined ? { outstandingCents } : {}),
          ...(dueDate !== undefined ? { dueDate } : {}),
          status: normalizedStatus,
          ...(safeWriteOff !== undefined ? { writeOffEntryId: safeWriteOff } : {}),
          createdAt,
        } as Debt;
      });

      // 15. SettlementAllocations (Tier-1 FKs: settlementEntryId, debtId)
      const allocationSeenIds = new Set<string>();
      const validatedSettlementAllocations = (
        (parsed.settlementAllocations || []) as Record<string, any>[]
      ).map((a, idx) => {
        const ctx = `settlementAllocations[${idx}]`;
        const id = this.requireUniqueId(a, 'settlementAllocations', idx, allocationSeenIds);
        const allocatedCents = this.requireIntMin(a, 'allocatedCents', ctx, 1);
        const settlementDate = normalizeRequiredDate(
          a.settlementDate,
          `${ctx}.settlementDate`
        );
        const settlementEntryId = this.requireBoundedString(
          a,
          'settlementEntryId',
          ctx,
          200
        );
        if (!entrySeenIds.has(settlementEntryId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.settlementEntryId": journal entry "${settlementEntryId}" does not exist.`
          );
        }
        const debtId = this.requireBoundedString(a, 'debtId', ctx, 200);
        if (!debtSeenIds.has(debtId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.debtId": debt "${debtId}" does not exist.`
          );
        }
        return {
          ...a,
          id,
          settlementEntryId,
          debtId,
          allocatedCents,
          settlementDate,
        } as SettlementAllocation;
      });

      // 16. SavingsGoals (including legacy v4 fallback from goals when savingsGoals omitted)
      const rawSavings =
        parsed.savingsGoals !== undefined
          ? (parsed.savingsGoals as Record<string, any>[])
          : legacySavingsFromGoals;
      const savingsSeenIds = new Set<string>();
      const validatedSavingsGoals: SharedSavingsGoal[] = rawSavings.map((g, idx) => {
        const ctx = `savingsGoals[${idx}]`;
        const id = this.requireUniqueId(g, 'savingsGoals', idx, savingsSeenIds);
        const title = this.requireBoundedString(g, 'title', ctx, 200);
        const targetCents = this.requireIntMin(g, 'targetCents', ctx, 1);
        const currentAllocatedCents =
          this.optionalIntMin(g, 'currentAllocatedCents', ctx, 0) ?? 0;
        const targetDate = normalizeOptionalDate(g.targetDate, `${ctx}.targetDate`);
        const rawLinkedAcc = this.optionalString(g, 'linkedAccountId', ctx);
        const safeLinkedAcc =
          rawLinkedAcc && targetAccountIdsWithSystem.has(rawLinkedAcc)
            ? rawLinkedAcc
            : undefined;
        const status =
          this.optionalEnum(g, 'status', this.VALID_SAVINGS_STATUSES, ctx) ?? 'active';
        const createdAt = normalizeOptionalInstant(g.createdAt, `${ctx}.createdAt`);
        const { linkedAccountId: _droppedAcc, ...rest } = g;
        return {
          ...rest,
          id,
          title,
          targetCents,
          currentAllocatedCents,
          ...(targetDate !== undefined ? { targetDate } : {}),
          ...(safeLinkedAcc !== undefined ? { linkedAccountId: safeLinkedAcc } : {}),
          status,
          ...(createdAt !== undefined ? { createdAt } : {}),
        };
      });

      // 17. Budgets (Tier-1 FK: categoryId; composite unique monthIso + categoryId)
      const budgetSeenIds = new Set<string>();
      const budgetCompositeSeen = new Map<string, string>();
      const validatedBudgets: SharedBudget[] = ((parsed.budgets || []) as Record<string, any>[]).map(
        (b, idx) => {
          const ctx = `budgets[${idx}]`;
          const id = this.requireUniqueId(b, 'budgets', idx, budgetSeenIds);
          const limitCents = this.requireIntMin(b, 'limitCents', ctx, 1);
          const categoryId = this.requireBoundedString(b, 'categoryId', ctx, 200);
          if (!validCategoryIds.has(categoryId)) {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid foreign key "${ctx}.categoryId": category "${categoryId}" does not exist.`
            );
          }
          const monthIso = this.requireMonthIso(b, 'monthIso', ctx);
          const compositeKey = `${monthIso}\u0000${categoryId}`;
          const existingOwner = budgetCompositeSeen.get(compositeKey);
          if (existingOwner && existingOwner !== id) {
            throw new BackupValidationError(
              'invalid_payload',
              `Duplicate budget for monthIso="${monthIso}" and categoryId="${categoryId}" at "${ctx}".`
            );
          }
          budgetCompositeSeen.set(compositeKey, id);
          const rolloverEnabled = this.optionalBool(b, 'rolloverEnabled', ctx) ?? false;
          const createdAt =
            normalizeOptionalInstant(b.createdAt, `${ctx}.createdAt`) ?? nowIso;
          const updatedAt =
            normalizeOptionalInstant(b.updatedAt, `${ctx}.updatedAt`) ?? createdAt;
          return {
            id,
            categoryId,
            monthIso,
            limitCents,
            rolloverEnabled,
            createdAt,
            updatedAt,
          };
        }
      );

      // 18. Recurring Rules
      const ruleSeenIds = new Set<string>();
      const validatedRecurringRules: SharedRecurringRule[] = (
        (parsed.recurringRules || []) as Record<string, any>[]
      ).map((r, idx) => {
        const ctx = `recurringRules[${idx}]`;
        const id = this.requireUniqueId(r, 'recurringRules', idx, ruleSeenIds);
        const title = this.requireBoundedString(r, 'title', ctx, 200);
        const amountCents = this.requireIntMin(r, 'amountCents', ctx, 1);
        const startDate = normalizeRequiredDate(r.startDate, `${ctx}.startDate`);
        const nextOccurrenceDate = normalizeRequiredDate(
          r.nextOccurrenceDate,
          `${ctx}.nextOccurrenceDate`
        );
        const endDate = normalizeOptionalDate(r.endDate, `${ctx}.endDate`);
        const ruleType =
          this.optionalEnum(r, 'ruleType', this.VALID_RULE_TYPES, ctx) ?? 'commitment';
        const frequency =
          this.optionalEnum(r, 'frequency', this.VALID_RULE_FREQUENCIES, ctx) ?? 'monthly';
        const interval = this.optionalIntMin(r, 'interval', ctx, 1) ?? 1;
        const rawAcc = this.optionalString(r, 'accountId', ctx);
        const safeAcc =
          rawAcc && targetAccountIdsWithSystem.has(rawAcc) ? rawAcc : undefined;
        const rawDestAcc = this.optionalString(r, 'destinationAccountId', ctx);
        const safeDestAcc =
          rawDestAcc && targetAccountIdsWithSystem.has(rawDestAcc)
            ? rawDestAcc
            : undefined;
        const rawCat = this.optionalString(r, 'categoryId', ctx);
        const safeCat = rawCat && validCategoryIds.has(rawCat) ? rawCat : undefined;
        const rawDebt = this.optionalString(r, 'linkedDebtId', ctx);
        const safeDebt = rawDebt && debtSeenIds.has(rawDebt) ? rawDebt : undefined;
        const isActive = this.optionalBool(r, 'isActive', ctx) ?? true;
        const autoPost = this.optionalBool(r, 'autoPost', ctx) ?? false;
        const createdAt =
          normalizeOptionalInstant(r.createdAt, `${ctx}.createdAt`) ?? nowIso;
        return {
          id,
          title,
          ruleType,
          amountCents,
          frequency,
          interval,
          startDate,
          nextOccurrenceDate,
          ...(endDate !== undefined ? { endDate } : {}),
          ...(safeAcc !== undefined ? { accountId: safeAcc } : {}),
          ...(safeDestAcc !== undefined ? { destinationAccountId: safeDestAcc } : {}),
          ...(safeCat !== undefined ? { categoryId: safeCat } : {}),
          ...(safeDebt !== undefined ? { linkedDebtId: safeDebt } : {}),
          isActive,
          autoPost,
          createdAt,
        };
      });

      // 19. Commitments
      const commitmentSeenIds = new Set<string>();
      const validatedCommitments: SharedCommitment[] = (
        (parsed.commitments || []) as Record<string, any>[]
      ).map((c, idx) => {
        const ctx = `commitments[${idx}]`;
        const id = this.requireUniqueId(c, 'commitments', idx, commitmentSeenIds);
        const title = this.requireBoundedString(c, 'title', ctx, 200);
        const amountCents = this.requireIntMin(c, 'amountCents', ctx, 1);
        const dueDate = normalizeRequiredDate(c.dueDate, `${ctx}.dueDate`);
        const isPaid = this.optionalBool(c, 'isPaid', ctx) ?? false;
        const direction =
          this.optionalEnum(c, 'direction', this.VALID_COMMITMENT_DIRECTIONS, ctx) ??
          'outflow';
        const legacyPaidUnverified =
          this.optionalBool(c, 'legacyPaidUnverified', ctx) ?? false;
        const recurringRule = this.optionalString(c, 'recurringRule', ctx);
        const rawAcc = this.optionalString(c, 'linkedAccountId', ctx);
        const safeAcc =
          rawAcc && targetAccountIdsWithSystem.has(rawAcc) ? rawAcc : undefined;
        const rawCat = this.optionalString(c, 'categoryId', ctx);
        const safeCat = rawCat && validCategoryIds.has(rawCat) ? rawCat : undefined;
        const rawDebt = this.optionalString(c, 'linkedDebtId', ctx);
        const safeDebt = rawDebt && debtSeenIds.has(rawDebt) ? rawDebt : undefined;
        const rawEntry = this.optionalString(c, 'settlementEntryId', ctx);
        const safeEntry = rawEntry && entrySeenIds.has(rawEntry) ? rawEntry : undefined;
        const rawRule = this.optionalString(c, 'recurringRuleId', ctx);
        const safeRule = rawRule && ruleSeenIds.has(rawRule) ? rawRule : undefined;
        const createdAt = normalizeOptionalInstant(c.createdAt, `${ctx}.createdAt`);
        const {
          linkedAccountId: _droppedAcc,
          categoryId: _droppedCat,
          linkedDebtId: _droppedDebt,
          settlementEntryId: _droppedEntry,
          recurringRuleId: _droppedRule,
          ...rest
        } = c;
        return {
          ...rest,
          id,
          title,
          amountCents,
          dueDate,
          isPaid,
          direction,
          legacyPaidUnverified,
          ...(recurringRule !== undefined ? { recurringRule } : {}),
          ...(safeAcc !== undefined ? { linkedAccountId: safeAcc } : {}),
          ...(safeCat !== undefined ? { categoryId: safeCat } : {}),
          ...(safeDebt !== undefined ? { linkedDebtId: safeDebt } : {}),
          ...(safeEntry !== undefined ? { settlementEntryId: safeEntry } : {}),
          ...(safeRule !== undefined ? { recurringRuleId: safeRule } : {}),
          ...(createdAt !== undefined ? { createdAt } : {}),
        };
      });

      // 20. Commitment Settlements (Tier-1 FKs: commitmentId, entryId)
      const settlementSeenIds = new Set<string>();
      const validatedCommitmentSettlements: SharedCommitmentSettlement[] = (
        (parsed.commitmentSettlements || []) as Record<string, any>[]
      ).map((s, idx) => {
        const ctx = `commitmentSettlements[${idx}]`;
        const id = this.requireUniqueId(s, 'commitmentSettlements', idx, settlementSeenIds);
        const amountCents = this.requireIntMin(s, 'amountCents', ctx, 1);
        const settledDate = normalizeRequiredDate(
          s.settledDate,
          `${ctx}.settledDate`
        );
        const commitmentId = this.requireBoundedString(s, 'commitmentId', ctx, 200);
        if (!commitmentSeenIds.has(commitmentId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.commitmentId": commitment "${commitmentId}" does not exist.`
          );
        }
        const entryId = this.requireBoundedString(s, 'entryId', ctx, 200);
        if (!entrySeenIds.has(entryId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.entryId": journal entry "${entryId}" does not exist.`
          );
        }
        const createdAt =
          normalizeOptionalInstant(s.createdAt, `${ctx}.createdAt`) ?? nowIso;
        return {
          id,
          commitmentId,
          entryId,
          amountCents,
          settledDate,
          createdAt,
        };
      });

      // 21. Reminders (optional; legacy omission semantics preserved)
      let importedReminders: SharedReminder[] | undefined;
      if (
        Object.prototype.hasOwnProperty.call(parsed, 'reminders') &&
        parsed.reminders !== undefined
      ) {
        const seenReminderIds = new Set<string>();
        importedReminders = (parsed.reminders as any[]).map((r: any, idx: number) => {
          const ctx = `reminders[${idx}]`;
          const id = this.requireUniqueId(r, 'reminders', idx, seenReminderIds);

          if (
            typeof r.targetType !== 'string' ||
            !this.VALID_REMINDER_TARGET_TYPES.has(
              r.targetType.trim() as SharedReminder['targetType']
            )
          ) {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid reminder targetType "${r.targetType}" at "${ctx}.targetType".`
            );
          }
          const targetType = r.targetType.trim() as SharedReminder['targetType'];

          let targetId: string;
          if (targetType === 'custom') {
            if (
              r.targetId !== undefined &&
              r.targetId !== null &&
              typeof r.targetId !== 'string'
            ) {
              throw new BackupValidationError(
                'invalid_payload',
                `Invalid field "${ctx}.targetId": expected a string.`
              );
            }
            const rawTarget = typeof r.targetId === 'string' ? r.targetId.trim() : '';
            targetId = rawTarget || id;
          } else {
            if (typeof r.targetId !== 'string' || !r.targetId.trim()) {
              throw new BackupValidationError(
                'invalid_payload',
                `Missing required field "${ctx}.targetId" for ${targetType} reminder "${id}".`
              );
            }
            targetId = r.targetId.trim();
          }

          const isActive = this.optionalBool(r, 'isActive', ctx) ?? true;
          const cleanTitle = this.optionalString(r, 'title', ctx) ?? '';
          const cleanChannelId = this.optionalString(r, 'channelId', ctx) ?? '';

          const triggerTimeUtc = normalizeRequiredInstant(
            r.triggerTimeUtc,
            `${ctx}.triggerTimeUtc`
          );
          const createdAt = normalizeRequiredInstant(
            r.createdAt ?? r.createdAtUtc,
            `${ctx}.createdAt`
          );

          return {
            id,
            targetId,
            targetType,
            triggerTimeUtc,
            isActive,
            createdAt,
            ...(cleanTitle.length > 0 ? { title: cleanTitle } : {}),
            ...(cleanChannelId.length > 0 ? { channelId: cleanChannelId } : {}),
          };
        });
      }

      // 22. AppSettings (optional; case-insensitive uniqueness + secret/sentinel exclusion)
      let importedAppSettings: SharedAppSetting[] | undefined;
      if (
        Object.prototype.hasOwnProperty.call(parsed, 'appSettings') &&
        parsed.appSettings !== undefined
      ) {
        const seenKeys = new Set<string>();
        const acceptedSettings: SharedAppSetting[] = [];
        for (let idx = 0; idx < (parsed.appSettings as any[]).length; idx++) {
          const s = (parsed.appSettings as any[])[idx];
          const ctx = `appSettings[${idx}]`;
          if (typeof s.key !== 'string' || !s.key.trim()) {
            throw new BackupValidationError(
              'invalid_payload',
              `Missing required non-empty string "${ctx}.key".`
            );
          }
          const key = s.key.trim();
          const normalizedKey = key.toLowerCase();
          if (seenKeys.has(normalizedKey)) {
            throw new BackupValidationError(
              'invalid_payload',
              `Duplicate setting key "${key}" in "appSettings" at index ${idx}.`
            );
          }
          seenKeys.add(normalizedKey);

          if (typeof s.value !== 'string') {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid field "${ctx}.value": expected a string.`
            );
          }

          let updatedAt: string | undefined;
          if (s.updatedAt !== undefined && s.updatedAt !== null) {
            updatedAt = normalizeRequiredInstant(s.updatedAt, `${ctx}.updatedAt`);
          }

          if (this.isExcludedAppSettingKey(key)) {
            continue;
          }

          acceptedSettings.push({
            key,
            value: s.value,
            ...(updatedAt !== undefined ? { updatedAt } : {}),
          });
        }
        acceptedSettings.sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
        importedAppSettings = acceptedSettings;
      }

      const appVersion = this.optionalString(parsed, 'appVersion', 'snapshot') ?? '1.0.2+3';
      const isFinanceSetupCompleted =
        this.optionalBool(parsed, 'isFinanceSetupCompleted', 'snapshot') ?? true;
      const openingBalanceCents =
        this.optionalIntMin(parsed, 'openingBalanceCents', 'snapshot', Number.MIN_SAFE_INTEGER) ??
        0;
      const ledgerMigrationReportV7 =
        parsed.ledgerMigrationReportV7 === undefined
          ? undefined
          : parsed.ledgerMigrationReportV7 === null
            ? null
            : this.optionalString(parsed, 'ledgerMigrationReportV7', 'snapshot', {
                allowEmpty: true,
              });

      const accountsForSync = validatedAccounts as unknown as Account[];
      const entryById = new Map(validatedJournalEntries.map((e) => [e.id, e]));
      const reconciledDebts = validatedDebts.map((debt) => {
        const originEntry = entryById.get(debt.originEntryId);
        const writeOffEntry = debt.writeOffEntryId
          ? entryById.get(debt.writeOffEntryId)
          : undefined;
        const hasLedgerAllocs = validatedSettlementAllocations.some(
          (a) => a.debtId === debt.id
        );
        const hasWriteOffLedgerLink = writeOffEntry?.entryType === 'write_off';
        if (originEntry?.isVoided || hasWriteOffLedgerLink || hasLedgerAllocs) {
          return reconcileDebtsV7({
            debts: [debt],
            entries: validatedJournalEntries,
            allocations: validatedSettlementAllocations,
          })[0];
        }
        return debt;
      });
      const syncedSavingsGoals = syncVaultSavingsGoalsV7({
        accounts: accountsForSync,
        entries: validatedJournalEntries,
        postings: validatedPostings,
        savingsGoals: validatedSavingsGoals,
      });

      const importedState: SharedDatabaseStateV7 = {
        schemaVersion,
        snapshotFormatVersion,
        ...(databaseSchemaVersion !== undefined ? { databaseSchemaVersion } : {}),
        financeSchemaVersion,
        appVersion,
        exportedAt: LocalDateTime.now().toEthiopiaIsoString(),
        isFinanceSetupCompleted,
        openingBalanceCents,
        ...(ledgerMigrationReportV7 !== undefined ? { ledgerMigrationReportV7 } : {}),
        accounts: validatedAccounts,
        categories: validatedCategories,
        transactions: validatedTransactions,
        commitments: validatedCommitments,
        commitmentSettlements: validatedCommitmentSettlements,
        savingsGoals: syncedSavingsGoals,
        budgets: validatedBudgets,
        recurringRules: validatedRecurringRules,
        parties: validatedParties,
        journalEntries: validatedJournalEntries,
        postings: validatedPostings,
        debts: reconciledDebts,
        settlementAllocations: validatedSettlementAllocations,
        milestones: validatedMilestones,
        tasks: validatedTasks,
        dailyPlanningEntries: validatedDailyPlanningEntries,
        dailyRhythmDays: validatedDailyRhythmDays,
        notes: validatedNotes,
        projects: validatedProjects,
        projectTrackingBlocks: validatedProjectTrackingBlocks,
        projectTrackingRecords: validatedProjectTrackingRecords,
        goals: validatedGoals,
        inboxItems: validatedInboxItems,
        calendarEvents: validatedCalendarEvents,
        ...(importedReminders !== undefined ? { reminders: importedReminders } : {}),
        ...(importedAppSettings !== undefined ? { appSettings: importedAppSettings } : {}),
      };

      this.saveCanonicalState(importedState);
      return { success: true, state: importedState };
    } catch (e: any) {
      if (e instanceof BackupValidationError) {
        return { success: false, error: e.message, errorKind: e.kind };
      }
      return {
        success: false,
        error: e?.message || 'Failed to import payload.',
        errorKind: 'invalid_payload',
      };
    }
  }

  /**
   * Validates and atomically imports a Finance-only JSON export, strictly rejecting
   * full cross-module backups or payloads containing non-Finance module keys.
   * Existing Tasks, Notes, Projects, Goals, Calendar events, Reminders, Inbox items,
   * and non-Finance settings are completely preserved.
   */
  public static importFinanceOnlyJson(
    jsonString: string
  ): {
    success: boolean;
    state?: SharedDatabaseStateV7;
    error?: string;
    errorKind?: BackupFailureKind;
  } {
    try {
      let rawParsed: unknown;
      try {
        rawParsed = JSON.parse(jsonString);
      } catch {
        return {
          success: false,
          error: 'Invalid JSON payload.',
          errorKind: 'invalid_payload',
        };
      }

      if (!rawParsed || typeof rawParsed !== 'object' || Array.isArray(rawParsed)) {
        throw new BackupValidationError(
          'invalid_payload',
          'Finance-only snapshot payload must be a JSON object.'
        );
      }

      const record = rawParsed as Record<string, any>;
      if (record.financeOnly !== true) {
        throw new BackupValidationError(
          'invalid_payload',
          'Full cross-module backups cannot be restored here. Select a Finance-only JSON export (financeOnly: true), or use Settings > Backup & Restore for full device backups.'
        );
      }
      if (
        record.exportScope !== undefined &&
        record.exportScope !== 'finance_only'
      ) {
        throw new BackupValidationError(
          'invalid_payload',
          `Invalid exportScope "${String(record.exportScope)}": expected "finance_only".`
        );
      }

      for (const forbiddenKey of this.NON_FINANCE_MODULE_KEYS) {
        if (
          Object.prototype.hasOwnProperty.call(record, forbiddenKey) &&
          record[forbiddenKey] !== undefined
        ) {
          throw new BackupValidationError(
            'invalid_payload',
            `Finance-only restore rejected: payload contains non-Finance collection "${forbiddenKey}". Use Settings > Backup & Restore for full backups.`
          );
        }
      }

      const versionInfo = interpretSnapshotVersions(record);
      if (!Array.isArray(record.accounts) || !Array.isArray(record.transactions)) {
        throw new BackupValidationError(
          'invalid_payload',
          'Finance-only payload is missing required accounts or transactions array.'
        );
      }

      for (const key of this.FINANCE_OPTIONAL_ARRAY_COLLECTIONS) {
        if (
          Object.prototype.hasOwnProperty.call(record, key) &&
          record[key] !== undefined &&
          !Array.isArray(record[key])
        ) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid Finance snapshot field "${key}": expected an array.`
          );
        }
      }

      for (const key of ['accounts', 'transactions', ...this.FINANCE_OPTIONAL_ARRAY_COLLECTIONS]) {
        const value = record[key];
        if (!Array.isArray(value)) continue;
        for (let i = 0; i < value.length; i++) {
          const entry = value[i];
          if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid record in "${key}" at index ${i}: expected a JSON object.`
            );
          }
        }
      }

      const nowIso = EthiopiaClock.nowUtc().toISOString();
      const normalizeOptionalDate = (val: unknown, fieldName: string): string | undefined => {
        if (val == null) return undefined;
        if (typeof val !== 'string') {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid date value "${val}" for ${fieldName}.`
          );
        }
        if (val.trim() === '') return undefined;
        const parsedDate = SharedDateFormatter.tryParseFlexibleToCalendarDate(val);
        if (!parsedDate) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid date value "${val}" for ${fieldName}.`
          );
        }
        return parsedDate.toIsoString();
      };
      const normalizeRequiredDate = (val: unknown, fieldName: string): string => {
        const parsedDate = normalizeOptionalDate(val, fieldName);
        if (!parsedDate) {
          throw new BackupValidationError(
            'invalid_payload',
            `Missing required date value for ${fieldName}.`
          );
        }
        return parsedDate;
      };
      const normalizeRequiredInstant = (val: unknown, fieldName: string): string => {
        if (typeof val !== 'string' || !val.trim()) {
          throw new BackupValidationError(
            'invalid_payload',
            `Missing or invalid ISO timestamp for ${fieldName}.`
          );
        }
        const ms = Date.parse(val.trim());
        if (Number.isNaN(ms)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid ISO timestamp "${val}" for ${fieldName}.`
          );
        }
        return new Date(ms).toISOString();
      };
      const normalizeOptionalInstant = (val: unknown, fieldName: string): string | undefined => {
        if (val === undefined || val === null) return undefined;
        return normalizeRequiredInstant(val, fieldName);
      };

      // 1. Categories
      const categorySeenIds = new Set<string>();
      const stagedCategories = ((record.categories || []) as Record<string, any>[]).map((c, idx) => {
        const ctx = `categories[${idx}]`;
        const id = this.requireUniqueId(c, 'categories', idx, categorySeenIds);
        const name = this.requireBoundedString(c, 'name', ctx, 100);
        const type = this.optionalEnum(c, 'type', this.VALID_CATEGORY_TYPES, ctx);
        if (!type) {
          throw new BackupValidationError(
            'invalid_payload',
            `Missing required field "${ctx}.type" (expected income or expense).`
          );
        }
        const colorHex = this.optionalString(c, 'colorHex', ctx) ?? '#1B4D3E';
        const parentId = this.optionalString(c, 'parentId', ctx);
        const sortOrder = this.optionalIntMin(c, 'sortOrder', ctx, -1000000) ?? 0;
        const isDefault = this.optionalBool(c, 'isDefault', ctx) ?? false;
        const isArchived = this.optionalBool(c, 'isArchived', ctx) ?? false;
        return {
          ...c,
          id,
          name,
          type,
          colorHex,
          ...(parentId !== undefined ? { parentId } : {}),
          sortOrder,
          isDefault,
          isArchived,
        } as SharedCategory;
      });
      const validatedCategories = this.breakChainCycles(stagedCategories, 'parentId') as SharedCategory[];
      const validCategoryIds = new Set<string>([
        ...categorySeenIds,
        ...this.CANONICAL_STARTER_CATEGORY_ID_SET,
      ]);

      // 2. Accounts
      const accountSeenIds = new Set<string>();
      const validatedAccounts = (record.accounts as Record<string, any>[]).map((a, idx) => {
        const ctx = `accounts[${idx}]`;
        const id = this.requireUniqueId(a, 'accounts', idx, accountSeenIds);
        const name = this.requireBoundedString(a, 'name', ctx, 150);
        const type = this.optionalEnum(a, 'type', this.VALID_ACCOUNT_TYPES, ctx) ?? 'asset';
        const subType = this.optionalString(a, 'subType', ctx);
        const isSystem = this.optionalBool(a, 'isSystem', ctx);
        const isSystemAccount = Boolean(isSystem) || this.SYSTEM_CONTROL_ACCOUNT_ID_SET.has(id);
        const hasCurrencyField =
          Object.prototype.hasOwnProperty.call(a, 'currencyCode') &&
          a.currencyCode !== undefined &&
          a.currencyCode !== null;
        const rawCurrency = this.optionalString(a, 'currencyCode', ctx, { allowEmpty: true });

        let currencyCode: string;
        if (isSystemAccount) {
          if (hasCurrencyField) {
            const trimmedSys = (rawCurrency ?? '').trim();
            if (trimmedSys !== '' && !isEtbCurrency(trimmedSys)) {
              throw new BackupValidationError(
                'invalid_payload',
                `Invalid ${ctx}.currencyCode: system control account "${name}" must use ETB.`
              );
            }
          }
          currencyCode = 'ETB';
        } else if (hasCurrencyField) {
          const trimmed = (rawCurrency ?? '').trim();
          if (trimmed === '') currencyCode = '';
          else if (isEtbCurrency(trimmed)) currencyCode = 'ETB';
          else if (isValidCurrencyCode(trimmed)) currencyCode = normalizeCurrencyCode(trimmed);
          else {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid ${ctx}.currencyCode on snapshot ${ctx} ("${name}"): unrecognized currency code "${normalizeCurrencyCode(trimmed)}".`
            );
          }
        } else {
          currencyCode = '';
        }

        const openingBalanceCents =
          a.openingBalanceCents !== undefined && a.openingBalanceCents !== null
            ? this.requireIntMin(a, 'openingBalanceCents', ctx, Number.MIN_SAFE_INTEGER)
            : 0;
        const openingBalanceDate = normalizeOptionalDate(
          a.openingBalanceDate,
          `${ctx}.openingBalanceDate`
        );
        const isArchivedFlag = this.optionalBool(a, 'isArchived', ctx) ?? false;
        const legacyIsActiveFlag = this.optionalBool(a, 'isActive', ctx);
        const createdAt = normalizeOptionalInstant(a.createdAt, `${ctx}.createdAt`);
        const { isActive: _retiredIsActive, ...rest } = a;
        return {
          ...rest,
          id,
          name,
          type,
          ...(subType !== undefined ? { subType } : {}),
          ...(isSystem !== undefined ? { isSystem } : {}),
          currencyCode,
          openingBalanceCents,
          isArchived: isArchivedFlag || legacyIsActiveFlag === false,
          ...(openingBalanceDate !== undefined ? { openingBalanceDate } : {}),
          ...(createdAt !== undefined ? { createdAt } : {}),
        } as SharedAccount;
      });
      const targetAccountIdsWithSystem = new Set<string>([
        ...accountSeenIds,
        ...this.SYSTEM_CONTROL_ACCOUNT_ID_SET,
      ]);

      // 3. Parties
      const partySeenIds = new Set<string>();
      const validatedParties = ((record.parties || []) as Record<string, any>[]).map((p, idx) => {
        const ctx = `parties[${idx}]`;
        const id = this.requireUniqueId(p, 'parties', idx, partySeenIds);
        const name = this.requireBoundedString(p, 'name', ctx, 150);
        const phone = this.optionalString(p, 'phone', ctx, { allowEmpty: true });
        const notes = this.optionalString(p, 'notes', ctx, { allowEmpty: true });
        const isArchived = this.optionalBool(p, 'isArchived', ctx) ?? false;
        const createdAt = normalizeOptionalInstant(p.createdAt, `${ctx}.createdAt`) ?? nowIso;
        return {
          ...p,
          id,
          name,
          ...(phone !== undefined ? { phone } : {}),
          ...(notes !== undefined ? { notes } : {}),
          isArchived,
          createdAt,
        } as Party;
      });

      // 4. Transactions
      const txSeenIds = new Set<string>();
      const stagedTransactions = (record.transactions as Record<string, any>[]).map((tx, idx) => {
        const ctx = `transactions[${idx}]`;
        const id = this.requireUniqueId(tx, 'transactions', idx, txSeenIds);
        const type = this.optionalEnum(tx, 'type', this.VALID_TRANSACTION_TYPES, ctx);
        if (!type) {
          throw new BackupValidationError(
            'invalid_payload',
            `Missing or invalid field "${ctx}.type".`
          );
        }
        const amountCents = this.requireIntMin(tx, 'amountCents', ctx, 1);
        const transactionDate = normalizeRequiredDate(
          tx.transactionDate,
          `${ctx}.transactionDate`
        );
        let categoryId: string;
        if (tx.categoryId !== undefined && tx.categoryId !== null) {
          if (typeof tx.categoryId !== 'string' || !tx.categoryId.trim()) {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid field "${ctx}.categoryId": expected a non-empty string.`
            );
          }
          categoryId = tx.categoryId.trim();
          if (!validCategoryIds.has(categoryId)) {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid foreign key "${ctx}.categoryId": category "${categoryId}" does not exist.`
            );
          }
        } else {
          if (versionInfo.usesModernFinanceV7Rules) {
            throw new BackupValidationError(
              'invalid_payload',
              `Missing required foreign key "${ctx}.categoryId" on ${type} transaction "${id}".`
            );
          }
          categoryId = type === 'income' ? 'cat-other-inc' : 'cat-other-exp';
        }
        const isSuperseded = this.optionalBool(tx, 'isSuperseded', ctx);
        const correctedFromId = this.optionalString(tx, 'correctedFromId', ctx);
        const createdAt = normalizeOptionalInstant(tx.createdAt, `${ctx}.createdAt`);
        return {
          ...tx,
          id,
          type,
          categoryId,
          amountCents,
          transactionDate,
          ...(isSuperseded !== undefined ? { isSuperseded } : {}),
          ...(correctedFromId !== undefined ? { correctedFromId } : {}),
          ...(createdAt !== undefined ? { createdAt } : {}),
        };
      });
      const validatedTransactions = this.breakChainCycles(
        stagedTransactions,
        'correctedFromId'
      ) as SharedTransaction[];

      // 5. Journal Entries
      const entrySeenIds = new Set<string>();
      const legacySourceSeen = new Map<string, string>();
      const stagedEntries = ((record.journalEntries || []) as Record<string, any>[]).map(
        (e, idx) => {
          const ctx = `journalEntries[${idx}]`;
          const id = this.requireUniqueId(e, 'journalEntries', idx, entrySeenIds);
          const rawEntryType = this.optionalString(e, 'entryType', ctx, { allowEmpty: true });
          let entryType: EntryType;
          try {
            entryType = normalizeEntryType(rawEntryType, { defaultIfOmitted: 'standard' });
          } catch (err) {
            throw new BackupValidationError(
              'invalid_payload',
              `Invalid field "${ctx}.entryType": ${err instanceof Error ? err.message : String(rawEntryType)}`
            );
          }
          const occurrenceDate = normalizeRequiredDate(
            e.occurrenceDate,
            `${ctx}.occurrenceDate`
          );
          const legacySourceTxId = this.optionalString(e, 'legacySourceTxId', ctx);
          if (legacySourceTxId !== undefined) {
            const owner = legacySourceSeen.get(legacySourceTxId);
            if (owner && owner !== id) {
              throw new BackupValidationError(
                'invalid_payload',
                `Duplicate legacySourceTxId "${legacySourceTxId}" in "${ctx}".`
              );
            }
            legacySourceSeen.set(legacySourceTxId, id);
          }
          const isVoided = this.optionalBool(e, 'isVoided', ctx) ?? false;
          const correctedFromEntryId = this.optionalString(e, 'correctedFromEntryId', ctx);
          const createdAt = normalizeOptionalInstant(e.createdAt, `${ctx}.createdAt`) ?? nowIso;
          return {
            ...e,
            id,
            entryType,
            description: this.optionalString(e, 'description', ctx, { allowEmpty: true }) ?? '',
            occurrenceDate,
            isVoided,
            ...(legacySourceTxId !== undefined ? { legacySourceTxId } : {}),
            ...(correctedFromEntryId !== undefined ? { correctedFromEntryId } : {}),
            createdAt,
          };
        }
      );
      const validatedJournalEntries = this.breakChainCycles(
        stagedEntries,
        'correctedFromEntryId'
      ) as JournalEntry[];

      // 6. Postings (balanced double-entry + FKs)
      const postingSeenIds = new Set<string>();
      const entryLedgerTotals = new Map<string, { debits: number; credits: number }>();
      const validatedPostings = ((record.postings || []) as Record<string, any>[]).map((p, idx) => {
        const ctx = `postings[${idx}]`;
        const id = this.requireUniqueId(p, 'postings', idx, postingSeenIds);
        const amountCents = this.requireIntMin(p, 'amountCents', ctx, 1);
        const accountMovementDate = normalizeRequiredDate(
          p.accountMovementDate,
          `${ctx}.accountMovementDate`
        );
        const entryId = this.requireBoundedString(p, 'entryId', ctx, 200);
        if (!entrySeenIds.has(entryId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.entryId": journal entry "${entryId}" does not exist.`
          );
        }
        const accountId = this.requireBoundedString(p, 'accountId', ctx, 200);
        if (!targetAccountIdsWithSystem.has(accountId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.accountId": account "${accountId}" does not exist.`
          );
        }
        const direction =
          this.optionalEnum(p, 'direction', this.VALID_POSTING_DIRECTIONS, ctx) ?? 'debit';
        const rawCategoryId = this.optionalString(p, 'categoryId', ctx);
        const safeCategoryId =
          rawCategoryId && validCategoryIds.has(rawCategoryId) ? rawCategoryId : undefined;

        const running = entryLedgerTotals.get(entryId) ?? { debits: 0, credits: 0 };
        if (direction === 'debit') running.debits += amountCents;
        else running.credits += amountCents;
        entryLedgerTotals.set(entryId, running);

        const { categoryId: _droppedCat, ...rest } = p;
        return {
          ...rest,
          id,
          entryId,
          accountId,
          amountCents,
          direction,
          accountMovementDate,
          ...(safeCategoryId !== undefined ? { categoryId: safeCategoryId } : {}),
        } as Posting;
      });

      for (const [entryId, totals] of entryLedgerTotals.entries()) {
        if (totals.debits !== totals.credits) {
          throw new BackupValidationError(
            'invalid_payload',
            `Unbalanced double-entry postings for journal entry "${entryId}": debits=${totals.debits}, credits=${totals.credits}.`
          );
        }
      }

      // 7. Debts
      const debtSeenIds = new Set<string>();
      const validatedDebts = ((record.debts || []) as Record<string, any>[]).map((d, idx) => {
        const ctx = `debts[${idx}]`;
        const id = this.requireUniqueId(d, 'debts', idx, debtSeenIds);
        const principalCents = this.requireIntMin(d, 'principalCents', ctx, 1);
        const outstandingCents = this.optionalIntMin(d, 'outstandingCents', ctx, 0);
        const originEntryId = this.requireBoundedString(d, 'originEntryId', ctx, 200);
        if (!entrySeenIds.has(originEntryId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.originEntryId": journal entry "${originEntryId}" does not exist.`
          );
        }
        const partyId = this.requireBoundedString(d, 'partyId', ctx, 200);
        if (!partySeenIds.has(partyId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.partyId": party "${partyId}" does not exist.`
          );
        }
        const debtType =
          this.optionalEnum(d, 'debtType', this.VALID_DEBT_TYPES, ctx) ?? 'payable';
        const rawStatus = this.optionalString(d, 'status', ctx, { allowEmpty: true });
        let normalizedStatus: DebtStatus;
        try {
          normalizedStatus = normalizeDebtStatus(rawStatus, { defaultIfOmitted: 'active' });
        } catch (err) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid field "${ctx}.status": ${err instanceof Error ? err.message : String(rawStatus)}`
          );
        }
        const rawWriteOff = this.optionalString(d, 'writeOffEntryId', ctx);
        const safeWriteOff =
          rawWriteOff && entrySeenIds.has(rawWriteOff) ? rawWriteOff : undefined;
        const dueDate = normalizeOptionalDate(d.dueDate, `${ctx}.dueDate`);
        const createdAt = normalizeOptionalInstant(d.createdAt, `${ctx}.createdAt`) ?? nowIso;
        const { writeOffEntryId: _droppedWo, ...rest } = d;
        return {
          ...rest,
          id,
          originEntryId,
          partyId,
          debtType,
          principalCents,
          ...(outstandingCents !== undefined ? { outstandingCents } : {}),
          ...(dueDate !== undefined ? { dueDate } : {}),
          status: normalizedStatus,
          ...(safeWriteOff !== undefined ? { writeOffEntryId: safeWriteOff } : {}),
          createdAt,
        } as Debt;
      });

      // 8. SettlementAllocations
      const allocationSeenIds = new Set<string>();
      const validatedSettlementAllocations = (
        (record.settlementAllocations || []) as Record<string, any>[]
      ).map((a, idx) => {
        const ctx = `settlementAllocations[${idx}]`;
        const id = this.requireUniqueId(a, 'settlementAllocations', idx, allocationSeenIds);
        const allocatedCents = this.requireIntMin(a, 'allocatedCents', ctx, 1);
        const settlementDate = normalizeRequiredDate(
          a.settlementDate,
          `${ctx}.settlementDate`
        );
        const settlementEntryId = this.requireBoundedString(a, 'settlementEntryId', ctx, 200);
        if (!entrySeenIds.has(settlementEntryId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.settlementEntryId": journal entry "${settlementEntryId}" does not exist.`
          );
        }
        const debtId = this.requireBoundedString(a, 'debtId', ctx, 200);
        if (!debtSeenIds.has(debtId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.debtId": debt "${debtId}" does not exist.`
          );
        }
        return {
          ...a,
          id,
          settlementEntryId,
          debtId,
          allocatedCents,
          settlementDate,
        } as SettlementAllocation;
      });

      // 9. SavingsGoals
      const savingsSeenIds = new Set<string>();
      const validatedSavingsGoals: SharedSavingsGoal[] = (
        (record.savingsGoals || []) as Record<string, any>[]
      ).map((g, idx) => {
        const ctx = `savingsGoals[${idx}]`;
        const id = this.requireUniqueId(g, 'savingsGoals', idx, savingsSeenIds);
        const title = this.requireBoundedString(g, 'title', ctx, 200);
        const targetCents = this.requireIntMin(g, 'targetCents', ctx, 1);
        const currentAllocatedCents =
          this.optionalIntMin(g, 'currentAllocatedCents', ctx, 0) ?? 0;
        const targetDate = normalizeOptionalDate(g.targetDate, `${ctx}.targetDate`);
        const rawLinkedAcc = this.optionalString(g, 'linkedAccountId', ctx);
        const safeLinkedAcc =
          rawLinkedAcc && targetAccountIdsWithSystem.has(rawLinkedAcc)
            ? rawLinkedAcc
            : undefined;
        const status =
          this.optionalEnum(g, 'status', this.VALID_SAVINGS_STATUSES, ctx) ?? 'active';
        const createdAt = normalizeOptionalInstant(g.createdAt, `${ctx}.createdAt`);
        const { linkedAccountId: _droppedAcc, ...rest } = g;
        return {
          ...rest,
          id,
          title,
          targetCents,
          currentAllocatedCents,
          ...(targetDate !== undefined ? { targetDate } : {}),
          ...(safeLinkedAcc !== undefined ? { linkedAccountId: safeLinkedAcc } : {}),
          status,
          ...(createdAt !== undefined ? { createdAt } : {}),
        };
      });

      // 10. Budgets
      const budgetSeenIds = new Set<string>();
      const budgetCompositeSeen = new Map<string, string>();
      const validatedBudgets: SharedBudget[] = (
        (record.budgets || []) as Record<string, any>[]
      ).map((b, idx) => {
        const ctx = `budgets[${idx}]`;
        const id = this.requireUniqueId(b, 'budgets', idx, budgetSeenIds);
        const limitCents = this.requireIntMin(b, 'limitCents', ctx, 1);
        const categoryId = this.requireBoundedString(b, 'categoryId', ctx, 200);
        if (!validCategoryIds.has(categoryId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.categoryId": category "${categoryId}" does not exist.`
          );
        }
        const monthIso = this.requireMonthIso(b, 'monthIso', ctx);
        const compositeKey = `${monthIso}\u0000${categoryId}`;
        const existingOwner = budgetCompositeSeen.get(compositeKey);
        if (existingOwner && existingOwner !== id) {
          throw new BackupValidationError(
            'invalid_payload',
            `Duplicate budget for monthIso="${monthIso}" and categoryId="${categoryId}" at "${ctx}".`
          );
        }
        budgetCompositeSeen.set(compositeKey, id);
        const rolloverEnabled = this.optionalBool(b, 'rolloverEnabled', ctx) ?? false;
        const createdAt = normalizeOptionalInstant(b.createdAt, `${ctx}.createdAt`) ?? nowIso;
        const updatedAt = normalizeOptionalInstant(b.updatedAt, `${ctx}.updatedAt`) ?? createdAt;
        return {
          id,
          categoryId,
          monthIso,
          limitCents,
          rolloverEnabled,
          createdAt,
          updatedAt,
        };
      });

      // 11. Recurring Rules
      const ruleSeenIds = new Set<string>();
      const validatedRecurringRules: SharedRecurringRule[] = (
        (record.recurringRules || []) as Record<string, any>[]
      ).map((r, idx) => {
        const ctx = `recurringRules[${idx}]`;
        const id = this.requireUniqueId(r, 'recurringRules', idx, ruleSeenIds);
        const title = this.requireBoundedString(r, 'title', ctx, 200);
        const amountCents = this.requireIntMin(r, 'amountCents', ctx, 1);
        const startDate = normalizeRequiredDate(r.startDate, `${ctx}.startDate`);
        const nextOccurrenceDate = normalizeRequiredDate(
          r.nextOccurrenceDate,
          `${ctx}.nextOccurrenceDate`
        );
        const endDate = normalizeOptionalDate(r.endDate, `${ctx}.endDate`);
        const ruleType =
          this.optionalEnum(r, 'ruleType', this.VALID_RULE_TYPES, ctx) ?? 'commitment';
        const frequency =
          this.optionalEnum(r, 'frequency', this.VALID_RULE_FREQUENCIES, ctx) ?? 'monthly';
        const interval = this.optionalIntMin(r, 'interval', ctx, 1) ?? 1;
        const rawAcc = this.optionalString(r, 'accountId', ctx);
        const safeAcc =
          rawAcc && targetAccountIdsWithSystem.has(rawAcc) ? rawAcc : undefined;
        const rawDestAcc = this.optionalString(r, 'destinationAccountId', ctx);
        const safeDestAcc =
          rawDestAcc && targetAccountIdsWithSystem.has(rawDestAcc) ? rawDestAcc : undefined;
        const rawCat = this.optionalString(r, 'categoryId', ctx);
        const safeCat = rawCat && validCategoryIds.has(rawCat) ? rawCat : undefined;
        const rawDebt = this.optionalString(r, 'linkedDebtId', ctx);
        const safeDebt = rawDebt && debtSeenIds.has(rawDebt) ? rawDebt : undefined;
        const isActive = this.optionalBool(r, 'isActive', ctx) ?? true;
        const autoPost = this.optionalBool(r, 'autoPost', ctx) ?? false;
        const createdAt = normalizeOptionalInstant(r.createdAt, `${ctx}.createdAt`) ?? nowIso;
        return {
          id,
          title,
          ruleType,
          amountCents,
          frequency,
          interval,
          startDate,
          nextOccurrenceDate,
          ...(endDate !== undefined ? { endDate } : {}),
          ...(safeAcc !== undefined ? { accountId: safeAcc } : {}),
          ...(safeDestAcc !== undefined ? { destinationAccountId: safeDestAcc } : {}),
          ...(safeCat !== undefined ? { categoryId: safeCat } : {}),
          ...(safeDebt !== undefined ? { linkedDebtId: safeDebt } : {}),
          isActive,
          autoPost,
          createdAt,
        };
      });

      // 12. Commitments
      const commitmentSeenIds = new Set<string>();
      const validatedCommitments: SharedCommitment[] = (
        (record.commitments || []) as Record<string, any>[]
      ).map((c, idx) => {
        const ctx = `commitments[${idx}]`;
        const id = this.requireUniqueId(c, 'commitments', idx, commitmentSeenIds);
        const title = this.requireBoundedString(c, 'title', ctx, 200);
        const amountCents = this.requireIntMin(c, 'amountCents', ctx, 1);
        const dueDate = normalizeRequiredDate(c.dueDate, `${ctx}.dueDate`);
        const isPaid = this.optionalBool(c, 'isPaid', ctx) ?? false;
        const direction =
          this.optionalEnum(c, 'direction', this.VALID_COMMITMENT_DIRECTIONS, ctx) ?? 'outflow';
        const legacyPaidUnverified =
          this.optionalBool(c, 'legacyPaidUnverified', ctx) ?? false;
        const recurringRule = this.optionalString(c, 'recurringRule', ctx);
        const rawAcc = this.optionalString(c, 'linkedAccountId', ctx);
        const safeAcc =
          rawAcc && targetAccountIdsWithSystem.has(rawAcc) ? rawAcc : undefined;
        const rawCat = this.optionalString(c, 'categoryId', ctx);
        const safeCat = rawCat && validCategoryIds.has(rawCat) ? rawCat : undefined;
        const rawDebt = this.optionalString(c, 'linkedDebtId', ctx);
        const safeDebt = rawDebt && debtSeenIds.has(rawDebt) ? rawDebt : undefined;
        const rawEntry = this.optionalString(c, 'settlementEntryId', ctx);
        const safeEntry = rawEntry && entrySeenIds.has(rawEntry) ? rawEntry : undefined;
        const rawRule = this.optionalString(c, 'recurringRuleId', ctx);
        const safeRule = rawRule && ruleSeenIds.has(rawRule) ? rawRule : undefined;
        const createdAt = normalizeOptionalInstant(c.createdAt, `${ctx}.createdAt`);
        const {
          linkedAccountId: _droppedAcc,
          categoryId: _droppedCat,
          linkedDebtId: _droppedDebt,
          settlementEntryId: _droppedEntry,
          recurringRuleId: _droppedRule,
          ...rest
        } = c;
        return {
          ...rest,
          id,
          title,
          amountCents,
          dueDate,
          isPaid,
          direction,
          legacyPaidUnverified,
          ...(recurringRule !== undefined ? { recurringRule } : {}),
          ...(safeAcc !== undefined ? { linkedAccountId: safeAcc } : {}),
          ...(safeCat !== undefined ? { categoryId: safeCat } : {}),
          ...(safeDebt !== undefined ? { linkedDebtId: safeDebt } : {}),
          ...(safeEntry !== undefined ? { settlementEntryId: safeEntry } : {}),
          ...(safeRule !== undefined ? { recurringRuleId: safeRule } : {}),
          ...(createdAt !== undefined ? { createdAt } : {}),
        };
      });

      // 13. Commitment Settlements
      const settlementSeenIds = new Set<string>();
      const validatedCommitmentSettlements: SharedCommitmentSettlement[] = (
        (record.commitmentSettlements || []) as Record<string, any>[]
      ).map((s, idx) => {
        const ctx = `commitmentSettlements[${idx}]`;
        const id = this.requireUniqueId(s, 'commitmentSettlements', idx, settlementSeenIds);
        const amountCents = this.requireIntMin(s, 'amountCents', ctx, 1);
        const settledDate = normalizeRequiredDate(s.settledDate, `${ctx}.settledDate`);
        const commitmentId = this.requireBoundedString(s, 'commitmentId', ctx, 200);
        if (!commitmentSeenIds.has(commitmentId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.commitmentId": commitment "${commitmentId}" does not exist.`
          );
        }
        const entryId = this.requireBoundedString(s, 'entryId', ctx, 200);
        if (!entrySeenIds.has(entryId)) {
          throw new BackupValidationError(
            'invalid_payload',
            `Invalid foreign key "${ctx}.entryId": journal entry "${entryId}" does not exist.`
          );
        }
        const createdAt = normalizeOptionalInstant(s.createdAt, `${ctx}.createdAt`) ?? nowIso;
        return {
          id,
          commitmentId,
          entryId,
          amountCents,
          settledDate,
          createdAt,
        };
      });

      const appVersion = this.optionalString(record, 'appVersion', 'snapshot') ?? '1.0.2+3';
      const isFinanceSetupCompleted =
        this.optionalBool(record, 'isFinanceSetupCompleted', 'snapshot') ?? true;
      const openingBalanceCents =
        this.optionalIntMin(record, 'openingBalanceCents', 'snapshot', Number.MIN_SAFE_INTEGER) ??
        0;
      const ledgerMigrationReportV7 =
        record.ledgerMigrationReportV7 === undefined
          ? undefined
          : record.ledgerMigrationReportV7 === null
            ? null
            : this.optionalString(record, 'ledgerMigrationReportV7', 'snapshot', {
                allowEmpty: true,
              });

      const accountsForSync = validatedAccounts as unknown as Account[];
      const entryById = new Map(validatedJournalEntries.map((e) => [e.id, e]));
      const reconciledDebts = validatedDebts.map((debt) => {
        const originEntry = entryById.get(debt.originEntryId);
        const writeOffEntry = debt.writeOffEntryId
          ? entryById.get(debt.writeOffEntryId)
          : undefined;
        const hasLedgerAllocs = validatedSettlementAllocations.some(
          (a) => a.debtId === debt.id
        );
        const hasWriteOffLedgerLink = writeOffEntry?.entryType === 'write_off';
        if (originEntry?.isVoided || hasWriteOffLedgerLink || hasLedgerAllocs) {
          return reconcileDebtsV7({
            debts: [debt],
            entries: validatedJournalEntries,
            allocations: validatedSettlementAllocations,
          })[0];
        }
        return debt;
      });
      const syncedSavingsGoals = syncVaultSavingsGoalsV7({
        accounts: accountsForSync,
        entries: validatedJournalEntries,
        postings: validatedPostings,
        savingsGoals: validatedSavingsGoals,
      });

      const updatedState = this.saveFinanceOnlyToStorage({
        schemaVersion: versionInfo.schemaVersion,
        snapshotFormatVersion: versionInfo.snapshotFormatVersion,
        ...(versionInfo.databaseSchemaVersion !== undefined
          ? { databaseSchemaVersion: versionInfo.databaseSchemaVersion }
          : {}),
        financeSchemaVersion:
          versionInfo.financeSchemaVersion ?? this.SUPPORTED_FINANCE_SCHEMA_VERSION,
        appVersion,
        isFinanceSetupCompleted,
        openingBalanceCents,
        ...(ledgerMigrationReportV7 !== undefined ? { ledgerMigrationReportV7 } : {}),
        accounts: validatedAccounts,
        categories: validatedCategories,
        transactions: validatedTransactions,
        commitments: validatedCommitments,
        commitmentSettlements: validatedCommitmentSettlements,
        savingsGoals: syncedSavingsGoals,
        budgets: validatedBudgets,
        recurringRules: validatedRecurringRules,
        parties: validatedParties,
        journalEntries: validatedJournalEntries,
        postings: validatedPostings,
        debts: reconciledDebts,
        settlementAllocations: validatedSettlementAllocations,
      });

      return { success: true, state: updatedState };
    } catch (e: any) {
      if (e instanceof BackupValidationError) {
        return { success: false, error: e.message, errorKind: e.kind };
      }
      return {
        success: false,
        error: e?.message || 'Failed to import Finance-only payload.',
        errorKind: 'invalid_payload',
      };
    }
  }

  /**
   * Synchronizes an in-memory modification into the canonical database.
   */
  public static recordTransaction(tx: SharedTransaction): SharedDatabaseState {
    const state = this.assembleLiveDatabaseState();
    const existingIdx = state.transactions.findIndex((t) => t.id === tx.id);
    if (existingIdx !== -1) {
      state.transactions[existingIdx] = tx;
    } else {
      state.transactions.unshift(tx);
    }
    this.saveCanonicalState(state);
    return state;
  }

  /**
   * Deletes a transaction and updates the canonical state.
   */
  public static deleteTransaction(txId: string): SharedDatabaseState {
    const state = this.assembleLiveDatabaseState();
    state.transactions = state.transactions.filter((t) => t.id !== txId);
    this.saveCanonicalState(state);
    return state;
  }

  /**
   * Safely purges legacy demonstration records matching known seed IDs from localStorage,
   * strictly safeguarding all genuine user-created records and accounts with user transactions.
   */
  public static purgeKnownSeedData(): { purgedCount: number; remainingCount: number } {
    if (typeof window === 'undefined') return { purgedCount: 0, remainingCount: 0 };
    let purgedCount = 0;
    try {
      const filterSeedArray = <T extends Record<string, any>>(
        rawJson: string | null,
        seedIds: readonly string[],
        onParsed?: (items: T[], removedCount: number) => T[]
      ): { exists: boolean; cleaned: T[]; removed: number } => {
        if (rawJson === null) return { exists: false, cleaned: [], removed: 0 };
        try {
          const parsed = JSON.parse(rawJson);
          if (!Array.isArray(parsed)) return { exists: false, cleaned: [], removed: 0 };
          const cleaned = onParsed
            ? onParsed(parsed, 0)
            : parsed.filter((item) => !seedIds.includes(item?.id));
          return {
            exists: true,
            cleaned,
            removed: parsed.length - cleaned.length,
          };
        } catch {
          return { exists: false, cleaned: [], removed: 0 };
        }
      };

      // 1. Transactions
      const savedFinanceTxs = localStorage.getItem('daywell_finance_transactions');
      const savedLegacyTxs = localStorage.getItem('daywell_transactions');
      const activeTxRaw = savedFinanceTxs ?? savedLegacyTxs;
      const txRes = filterSeedArray<SharedTransaction>(
        activeTxRaw,
        KNOWN_SEED_IDS.transactions
      );
      let transactions = txRes.cleaned;
      purgedCount += txRes.removed;

      // 2. Accounts: Only remove known seed accounts IF they have zero user transactions!
      const savedAccounts = localStorage.getItem('daywell_accounts');
      const accRes = filterSeedArray<SharedAccount>(
        savedAccounts,
        KNOWN_SEED_IDS.accounts,
        (parsed) =>
          parsed.filter((a) => {
            if ((KNOWN_SEED_IDS.accounts as readonly string[]).includes(a?.id)) {
              const hasUserTx = transactions.some(
                (t) =>
                  (t.accountId === a.id || t.destinationAccountId === a.id) &&
                  !(KNOWN_SEED_IDS.transactions as readonly string[]).includes(t.id)
              );
              return hasUserTx;
            }
            return true;
          })
      );
      let accounts = accRes.cleaned;
      purgedCount += accRes.removed;

      // 3. Tasks & DailyPlanningEntries
      const savedTasks = localStorage.getItem('daywell_tasks');
      const taskRes = filterSeedArray<any>(savedTasks, KNOWN_SEED_IDS.tasks);
      let tasks = taskRes.cleaned;
      purgedCount += taskRes.removed;

      const seedTaskIds = KNOWN_SEED_IDS.tasks as readonly string[];
      const savedDailyPlanning = localStorage.getItem(this.DAILY_PLANNING_STORAGE_KEY);
      let dailyPlanningExists = false;
      let cleanedDailyPlanning: any[] = [];
      if (savedDailyPlanning !== null) {
        try {
          const parsedDaily = JSON.parse(savedDailyPlanning);
          if (Array.isArray(parsedDaily)) {
            dailyPlanningExists = true;
            cleanedDailyPlanning = parsedDaily.filter(
              (d: any) => !seedTaskIds.includes(d?.taskId)
            );
            purgedCount += parsedDaily.length - cleanedDailyPlanning.length;
            localStorage.setItem(
              this.DAILY_PLANNING_STORAGE_KEY,
              JSON.stringify(cleanedDailyPlanning)
            );
          }
        } catch {}
      }

      // 4. Notes
      const savedNotes = localStorage.getItem('daywell_notes');
      const noteRes = filterSeedArray<any>(savedNotes, KNOWN_SEED_IDS.notes);
      let notes = noteRes.cleaned;
      purgedCount += noteRes.removed;

      // 5. Calendar events
      const savedEvents = localStorage.getItem('daywell_calendar_events');
      const eventRes = filterSeedArray<any>(savedEvents, KNOWN_SEED_IDS.events);
      purgedCount += eventRes.removed;
      if (eventRes.exists) {
        localStorage.setItem('daywell_calendar_events', JSON.stringify(eventRes.cleaned));
      }

      // 6. Commitments, SavingsGoals & Parties
      const savedCommitments = localStorage.getItem('daywell_commitments');
      const commitmentRes = filterSeedArray<any>(
        savedCommitments,
        KNOWN_SEED_IDS.commitments
      );
      purgedCount += commitmentRes.removed;
      if (commitmentRes.exists) {
        localStorage.setItem('daywell_commitments', JSON.stringify(commitmentRes.cleaned));
      }

      const savedSavingsGoals = localStorage.getItem('daywell_savings_goals');
      const savingsRes = filterSeedArray<any>(
        savedSavingsGoals,
        KNOWN_SEED_IDS.savingsGoals
      );
      purgedCount += savingsRes.removed;
      if (savingsRes.exists) {
        localStorage.setItem('daywell_savings_goals', JSON.stringify(savingsRes.cleaned));
      }

      const savedParties = localStorage.getItem('daywell_parties');
      const partyRes = filterSeedArray<any>(savedParties, KNOWN_SEED_IDS.parties);
      purgedCount += partyRes.removed;
      if (partyRes.exists) {
        localStorage.setItem('daywell_parties', JSON.stringify(partyRes.cleaned));
      }

      // 7. Projects, ProjectTrackingBlocks, ProjectTrackingRecords, Goals & Inbox Items
      let projectsCount = 0;
      const savedProjects = localStorage.getItem(this.PROJECTS_STORAGE_KEY);
      const projectRes = filterSeedArray<any>(savedProjects, KNOWN_SEED_IDS.projects);
      if (projectRes.exists) {
        purgedCount += projectRes.removed;
        projectsCount = projectRes.cleaned.length;
        localStorage.setItem(this.PROJECTS_STORAGE_KEY, JSON.stringify(projectRes.cleaned));
      }

      const seedProjectIds = KNOWN_SEED_IDS.projects as readonly string[];
      const savedProjectRecords = localStorage.getItem(
        this.PROJECT_TRACKING_RECORDS_STORAGE_KEY
      );
      let projectRecordsExist = false;
      let cleanedProjectRecords: any[] = [];
      if (savedProjectRecords !== null) {
        try {
          const parsedRecs = JSON.parse(savedProjectRecords);
          if (Array.isArray(parsedRecs)) {
            projectRecordsExist = true;
            cleanedProjectRecords = parsedRecs.filter(
              (r: any) => !seedProjectIds.includes(r?.projectId)
            );
            purgedCount += parsedRecs.length - cleanedProjectRecords.length;
            localStorage.setItem(
              this.PROJECT_TRACKING_RECORDS_STORAGE_KEY,
              JSON.stringify(cleanedProjectRecords)
            );
          }
        } catch {}
      }

      const savedProjectBlocks = localStorage.getItem(
        this.PROJECT_TRACKING_BLOCKS_STORAGE_KEY
      );
      let projectBlocksExist = false;
      let cleanedProjectBlocks: any[] = [];
      if (savedProjectBlocks !== null) {
        try {
          const parsedBlocks = JSON.parse(savedProjectBlocks);
          if (Array.isArray(parsedBlocks)) {
            projectBlocksExist = true;
            cleanedProjectBlocks = parsedBlocks.filter(
              (b: any) => !seedProjectIds.includes(b?.projectId)
            );
            purgedCount += parsedBlocks.length - cleanedProjectBlocks.length;
            localStorage.setItem(
              this.PROJECT_TRACKING_BLOCKS_STORAGE_KEY,
              JSON.stringify(cleanedProjectBlocks)
            );
          }
        } catch {}
      }

      let goalsCount = 0;
      const savedGoals = localStorage.getItem(this.GOALS_STORAGE_KEY);
      const goalRes = filterSeedArray<any>(savedGoals, KNOWN_SEED_IDS.goals);
      if (goalRes.exists) {
        purgedCount += goalRes.removed;
        goalsCount = goalRes.cleaned.length;
        localStorage.setItem(this.GOALS_STORAGE_KEY, JSON.stringify(goalRes.cleaned));
      }

      let inboxCount = 0;
      const savedInbox = localStorage.getItem(this.INBOX_STORAGE_KEY);
      const inboxRes = filterSeedArray<any>(savedInbox, KNOWN_SEED_IDS.inboxItems);
      if (inboxRes.exists) {
        purgedCount += inboxRes.removed;
        inboxCount = inboxRes.cleaned.length;
        localStorage.setItem(this.INBOX_STORAGE_KEY, JSON.stringify(inboxRes.cleaned));
      }

      const savedLegacyInbox = localStorage.getItem(this.LEGACY_INBOX_STORAGE_KEY);
      const legacyInboxRes = filterSeedArray<any>(
        savedLegacyInbox,
        KNOWN_SEED_IDS.inboxItems
      );
      if (legacyInboxRes.exists) {
        purgedCount += legacyInboxRes.removed;
        if (!inboxRes.exists) inboxCount = legacyInboxRes.cleaned.length;
        localStorage.setItem(
          this.LEGACY_INBOX_STORAGE_KEY,
          JSON.stringify(legacyInboxRes.cleaned)
        );
      }

      // Write back only stores that existed so missing keys are never materialized as []
      if (accRes.exists) {
        localStorage.setItem('daywell_accounts', JSON.stringify(accounts));
        if (accounts.length === 0) {
          localStorage.setItem('daywell_finance_setup_completed', 'false');
        }
      }
      if (savedFinanceTxs !== null && txRes.exists) {
        localStorage.setItem('daywell_finance_transactions', JSON.stringify(transactions));
      }
      if (savedLegacyTxs !== null && txRes.exists) {
        localStorage.setItem('daywell_transactions', JSON.stringify(transactions));
      }
      if (taskRes.exists) {
        localStorage.setItem('daywell_tasks', JSON.stringify(tasks));
      }
      if (noteRes.exists) {
        localStorage.setItem('daywell_notes', JSON.stringify(notes));
      }

      // 8. Also clean canonical database key if present, preserving non-seed user records
      const savedCanonical = localStorage.getItem(this.STORAGE_KEY);
      let commitmentsCount = commitmentRes.cleaned.length;
      let savingsCount = savingsRes.cleaned.length;
      let partiesCount = partyRes.cleaned.length;
      let eventsCount = eventRes.cleaned.length;

      if (savedCanonical) {
        try {
          const parsed = JSON.parse(savedCanonical);
          if (parsed && typeof parsed === 'object') {
            if (Array.isArray(parsed.transactions)) {
              const cTx = parsed.transactions.filter(
                (t: any) => !(KNOWN_SEED_IDS.transactions as readonly string[]).includes(t?.id)
              );
              if (!txRes.exists) {
                purgedCount += parsed.transactions.length - cTx.length;
                transactions = cTx;
              }
              parsed.transactions = txRes.exists ? transactions : cTx;
            }
            if (Array.isArray(parsed.accounts)) {
              const cAcc = parsed.accounts.filter((a: any) => {
                if ((KNOWN_SEED_IDS.accounts as readonly string[]).includes(a?.id)) {
                  return transactions.some(
                    (t) =>
                      (t.accountId === a.id || t.destinationAccountId === a.id) &&
                      !(KNOWN_SEED_IDS.transactions as readonly string[]).includes(t.id)
                  );
                }
                return true;
              });
              if (!accRes.exists) {
                purgedCount += parsed.accounts.length - cAcc.length;
                accounts = cAcc;
              }
              parsed.accounts = accRes.exists ? accounts : cAcc;
            }
            if (Array.isArray(parsed.tasks)) {
              const cTasks = parsed.tasks.filter(
                (t: any) => !(KNOWN_SEED_IDS.tasks as readonly string[]).includes(t?.id)
              );
              if (!taskRes.exists) {
                purgedCount += parsed.tasks.length - cTasks.length;
                tasks = cTasks;
              }
              parsed.tasks = taskRes.exists ? tasks : cTasks;
            }
            if (Array.isArray(parsed.dailyPlanningEntries)) {
              const cDaily = parsed.dailyPlanningEntries.filter(
                (d: any) => !seedTaskIds.includes(d?.taskId)
              );
              if (!dailyPlanningExists) {
                purgedCount += parsed.dailyPlanningEntries.length - cDaily.length;
              }
              parsed.dailyPlanningEntries = dailyPlanningExists
                ? cleanedDailyPlanning
                : cDaily;
            }
            if (Array.isArray(parsed.notes)) {
              const cNotes = parsed.notes.filter(
                (n: any) => !(KNOWN_SEED_IDS.notes as readonly string[]).includes(n?.id)
              );
              if (!noteRes.exists) {
                purgedCount += parsed.notes.length - cNotes.length;
                notes = cNotes;
              }
              parsed.notes = noteRes.exists ? notes : cNotes;
            }
            if (Array.isArray(parsed.calendarEvents)) {
              const cEvents = parsed.calendarEvents.filter(
                (e: any) => !(KNOWN_SEED_IDS.events as readonly string[]).includes(e?.id)
              );
              if (!eventRes.exists) {
                purgedCount += parsed.calendarEvents.length - cEvents.length;
                eventsCount = cEvents.length;
              }
              parsed.calendarEvents = eventRes.exists ? eventRes.cleaned : cEvents;
            }
            if (Array.isArray(parsed.commitments)) {
              const cCommitments = parsed.commitments.filter(
                (c: any) => !(KNOWN_SEED_IDS.commitments as readonly string[]).includes(c?.id)
              );
              if (!commitmentRes.exists) {
                purgedCount += parsed.commitments.length - cCommitments.length;
                commitmentsCount = cCommitments.length;
              }
              parsed.commitments = commitmentRes.exists ? commitmentRes.cleaned : cCommitments;
            }
            if (Array.isArray(parsed.savingsGoals)) {
              const cSavings = parsed.savingsGoals.filter(
                (s: any) => !(KNOWN_SEED_IDS.savingsGoals as readonly string[]).includes(s?.id)
              );
              if (!savingsRes.exists) {
                purgedCount += parsed.savingsGoals.length - cSavings.length;
                savingsCount = cSavings.length;
              }
              parsed.savingsGoals = savingsRes.exists ? savingsRes.cleaned : cSavings;
            }
            if (Array.isArray(parsed.parties)) {
              const cParties = parsed.parties.filter(
                (p: any) => !(KNOWN_SEED_IDS.parties as readonly string[]).includes(p?.id)
              );
              if (!partyRes.exists) {
                purgedCount += parsed.parties.length - cParties.length;
                partiesCount = cParties.length;
              }
              parsed.parties = partyRes.exists ? partyRes.cleaned : cParties;
            }
            if (Array.isArray(parsed.projects)) {
              const cleanedProjects = parsed.projects.filter(
                (p: any) => !(KNOWN_SEED_IDS.projects as readonly string[]).includes(p?.id)
              );
              if (!projectRes.exists) {
                purgedCount += parsed.projects.length - cleanedProjects.length;
                projectsCount = cleanedProjects.length;
              }
              parsed.projects = projectRes.exists ? projectRes.cleaned : cleanedProjects;
            }
            if (Array.isArray(parsed.projectTrackingRecords)) {
              const cRecs = parsed.projectTrackingRecords.filter(
                (r: any) => !seedProjectIds.includes(r?.projectId)
              );
              if (!projectRecordsExist) {
                purgedCount += parsed.projectTrackingRecords.length - cRecs.length;
              }
              parsed.projectTrackingRecords = projectRecordsExist
                ? cleanedProjectRecords
                : cRecs;
            }
            if (Array.isArray(parsed.projectTrackingBlocks)) {
              const cBlocks = parsed.projectTrackingBlocks.filter(
                (b: any) => !seedProjectIds.includes(b?.projectId)
              );
              if (!projectBlocksExist) {
                purgedCount += parsed.projectTrackingBlocks.length - cBlocks.length;
              }
              parsed.projectTrackingBlocks = projectBlocksExist
                ? cleanedProjectBlocks
                : cBlocks;
            }
            if (Array.isArray(parsed.goals)) {
              const cleanedGoals = parsed.goals.filter(
                (g: any) => !(KNOWN_SEED_IDS.goals as readonly string[]).includes(g?.id)
              );
              if (!goalRes.exists) {
                purgedCount += parsed.goals.length - cleanedGoals.length;
                goalsCount = cleanedGoals.length;
              }
              parsed.goals = goalRes.exists ? goalRes.cleaned : cleanedGoals;
            }
            if (Array.isArray(parsed.inboxItems)) {
              const cleanedInbox = parsed.inboxItems.filter(
                (i: any) => !(KNOWN_SEED_IDS.inboxItems as readonly string[]).includes(i?.id)
              );
              if (!inboxRes.exists && !legacyInboxRes.exists) {
                purgedCount += parsed.inboxItems.length - cleanedInbox.length;
                inboxCount = cleanedInbox.length;
              }
              parsed.inboxItems = cleanedInbox;
            }
            parsed.isFinanceSetupCompleted = accounts.length > 0;
            localStorage.setItem(this.STORAGE_KEY, JSON.stringify(parsed));
          }
        } catch (e) {}
      }

      const remainingCount =
        accounts.length +
        transactions.length +
        tasks.length +
        notes.length +
        projectsCount +
        goalsCount +
        inboxCount +
        eventsCount +
        commitmentsCount +
        savingsCount +
        partiesCount;
      return { purgedCount, remainingCount };
    } catch (e) {
      console.warn('[SharedStateBridge] Error purging seed data:', e);
      return { purgedCount: 0, remainingCount: 0 };
    }
  }
}
