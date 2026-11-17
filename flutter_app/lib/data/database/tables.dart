import 'package:drift/drift.dart';

/// Quick Capture Inbox Entity
class InboxItems extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get rawText => text()();
  TextColumn get category => text().withDefault(
      const Constant('general'))(); // task, idea, expense, note, general
  BoolColumn get isProcessed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Goals Table (High-level ambition)
class Goals extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().nullable()();
  TextColumn get targetDate => text().nullable()(); // YYYY-MM-DD
  TextColumn get status => text()
      .withDefault(const Constant('active'))(); // active, achieved, archived
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Projects Table (Organized work towards an outcome)
class Projects extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get goalId =>
      text().nullable().references(Goals, #id, onDelete: KeyAction.setNull)();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().nullable()();
  TextColumn get status => text()
      .withDefault(const Constant('active'))(); // active, completed, on_hold
  TextColumn get targetDate => text().nullable()(); // YYYY-MM-DD
  // Schema v9 additions
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  TextColumn get startDate => text().nullable()(); // YYYY-MM-DD
  TextColumn get customFieldsJson => text().withDefault(const Constant('{}'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Tracking Blocks inside a Project (Schema v9)
class ProjectTrackingBlocks extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get projectId =>
      text().references(Projects, #id, onDelete: KeyAction.cascade)();
  TextColumn get blockType =>
      text()(); // counter, grouped_list, checklist, schedule
  TextColumn get title => text().withLength(min: 1, max: 200)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get unitLabel => text().nullable()();
  RealColumn get targetValue => real().nullable()();
  RealColumn get dailyTargetValue => real().nullable()();
  TextColumn get configJson => text().withDefault(const Constant('{}'))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Structured Tracking Records & Append-Only Progress Logs (Schema v9)
class ProjectTrackingRecords extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get projectId =>
      text().references(Projects, #id, onDelete: KeyAction.cascade)();
  TextColumn get blockId => text()
      .references(ProjectTrackingBlocks, #id, onDelete: KeyAction.cascade)();
  TextColumn get parentRecordId => text()
      .nullable()
      .references(ProjectTrackingRecords, #id, onDelete: KeyAction.restrict)();
  TextColumn get recordType => text()();
  TextColumn get title => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  RealColumn get targetValue => real().nullable()();
  RealColumn get deltaValue => real().nullable()();
  IntColumn get durationMinutes => integer().nullable()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get recordedDate => text().nullable()(); // YYYY-MM-DD
  TextColumn get scheduledDate => text().nullable()(); // YYYY-MM-DD
  TextColumn get linkedTaskId =>
      text().nullable().references(Tasks, #id, onDelete: KeyAction.setNull)();
  TextColumn get metadataJson => text().withDefault(const Constant('{}'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Optional intermediate project milestones
class Milestones extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get projectId =>
      text().references(Projects, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get dueDate => text().nullable()(); // YYYY-MM-DD
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Task items with priority, status, organization metadata, and project associations
class Tasks extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get title => text().withLength(min: 1, max: 300)();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant(
      'inbox'))(); // inbox, not_started, in_progress, completed, cancelled
  TextColumn get priority => text()
      .withDefault(const Constant('medium'))(); // low, medium, high, urgent
  TextColumn get dueDate => text().nullable()(); // YYYY-MM-DD
  TextColumn get scheduledDate => text().nullable()(); // YYYY-MM-DD
  IntColumn get estimatedDurationMinutes => integer().nullable()();
  TextColumn get projectId => text()
      .nullable()
      .references(Projects, #id, onDelete: KeyAction.setNull)();
  TextColumn get milestoneId => text()
      .nullable()
      .references(Milestones, #id, onDelete: KeyAction.setNull)();
  // Schema v4 additions
  TextColumn get subtasksJson => text().withDefault(const Constant('[]'))();
  TextColumn get labelsJson => text().withDefault(const Constant('[]'))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isMyDay => boolean().withDefault(const Constant(false))();
  TextColumn get recurrenceRule => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Notes and Personal Information
class Notes extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get title => text().withLength(min: 1, max: 250)();
  TextColumn get content =>
      text()(); // Full Unicode support for Amharic / Ge'ez
  TextColumn get category => text().withDefault(
      const Constant('general'))(); // general, reference, reflection, learning
  TextColumn get projectId => text()
      .nullable()
      .references(Projects, #id, onDelete: KeyAction.setNull)();
  TextColumn get goalId =>
      text().nullable().references(Goals, #id, onDelete: KeyAction.setNull)();
  // Schema v4 additions
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isTrashed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Calendar Events (Schema v4)
class CalendarEvents extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 250)();
  TextColumn get dateIso => text()(); // YYYY-MM-DD
  TextColumn get endDateIso => text().nullable()(); // YYYY-MM-DD (Schema v5)
  TextColumn get startTime => text().nullable()(); // HH:mm
  TextColumn get endTime => text().nullable()(); // HH:mm
  BoolColumn get isAllDay => boolean().withDefault(const Constant(false))();
  TextColumn get category => text().withDefault(const Constant('personal'))();
  TextColumn get colorHex => text().withDefault(const Constant('#1B4D3E'))();
  BoolColumn get hasReminder => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Financial Categories
class FinancialCategories extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get type => text()(); // income, expense
  TextColumn get colorHex => text().withDefault(const Constant('#4CAF50'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  // Schema v4 addition
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  // Schema v6 additions; v7 enforces ON DELETE RESTRICT
  TextColumn get parentId => text()
      .nullable()
      .references(FinancialCategories, #id, onDelete: KeyAction.restrict)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Recorded Financial Transactions (Integer minor units - cents)
class FinancialTransactions extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get categoryId => text()
      .references(FinancialCategories, #id, onDelete: KeyAction.restrict)();
  IntColumn get amountCents =>
      integer()(); // Minor units in cents (1 ETB = 100 cents)
  TextColumn get type => text()(); // income, expense, transfer
  TextColumn get transactionDate =>
      text()(); // Canonical YYYY-MM-DD (Schema v5)
  TextColumn get note => text().nullable()();
  TextColumn get payee => text().nullable()();
  // Schema v4 additions
  TextColumn get accountId => text().nullable()();
  TextColumn get destinationAccountId => text().nullable()();
  BoolColumn get isSuperseded => boolean().withDefault(const Constant(false))();
  TextColumn get correctedFromId => text().nullable()();
  TextColumn get correctionReason => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Upcoming Financial Commitments (Bills, Rent, Subscriptions, Expected Income)
class FinancialCommitments extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get title => text().withLength(min: 1, max: 200)();
  IntColumn get amountCents => integer()(); // Minor units
  TextColumn get dueDate => text()(); // Canonical YYYY-MM-DD (Schema v5)
  BoolColumn get isPaid => boolean().withDefault(const Constant(false))();
  // Schema v7 additions
  TextColumn get direction =>
      text().withDefault(const Constant('outflow'))(); // outflow | inflow
  BoolColumn get legacyPaidUnverified =>
      boolean().withDefault(const Constant(false))();
  TextColumn get recurringRule => text().nullable()(); // monthly, weekly, none
  // Schema v6 additions; v7 enforces ON DELETE RESTRICT
  TextColumn get linkedAccountId => text()
      .nullable()
      .references(AccountsTable, #id, onDelete: KeyAction.restrict)();
  TextColumn get categoryId => text()
      .nullable()
      .references(FinancialCategories, #id, onDelete: KeyAction.restrict)();
  TextColumn get linkedDebtId => text()
      .nullable()
      .references(DebtsTable, #id, onDelete: KeyAction.restrict)();
  TextColumn get settlementEntryId => text()
      .nullable()
      .references(JournalEntriesTable, #id, onDelete: KeyAction.restrict)();
  TextColumn get recurringRuleId => text()
      .nullable()
      .references(RecurringRulesTable, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Partial & Full Commitment Installment Settlements (Schema v7)
class CommitmentSettlementsTable extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get commitmentId => text()
      .references(FinancialCommitments, #id, onDelete: KeyAction.restrict)();
  TextColumn get entryId => text()
      .references(JournalEntriesTable, #id, onDelete: KeyAction.restrict)();
  IntColumn get amountCents => integer()(); // Minor units > 0
  TextColumn get settledDate => text()(); // Canonical YYYY-MM-DD
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Savings Goals & Allocations
class SavingsGoals extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get title => text().withLength(min: 1, max: 200)();
  IntColumn get targetCents => integer()();
  IntColumn get currentAllocatedCents =>
      integer().withDefault(const Constant(0))();
  TextColumn get targetDate =>
      text().nullable()(); // Canonical YYYY-MM-DD (Schema v5)
  // Schema v6 addition; v7 enforces ON DELETE RESTRICT
  TextColumn get linkedAccountId => text()
      .nullable()
      .references(AccountsTable, #id, onDelete: KeyAction.restrict)();
  // Schema v7 addition: active, completed, archived
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local Reminders for Tasks, Commitments, Calendar Events, Notes, and Custom Alerts
class Reminders extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get targetId => text()(); // Entity ID or custom reminder ID
  TextColumn get targetType =>
      text()(); // task, commitment, calendar_event, note, custom
  TextColumn get title => text().nullable()();
  TextColumn get channelId => text().nullable()();
  DateTimeColumn get triggerTimeUtc => dateTime()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Key-Value Application Settings
class AppSettings extends Table {
  TextColumn get key =>
      text()(); // e.g., 'calendar_preference', 'default_currency'
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

// ============================================================================
// REVISED DOUBLE-ENTRY ACCOUNTING TABLES (BALANCED LEDGER GUARANTEE)
// ============================================================================

/// Flexible Accounts (Strict single currency per account, ETB default)
class AccountsTable extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get name => text().withLength(min: 1, max: 150)();
  TextColumn get type => text()(); // asset, liability, equity, income, expense
  // Schema v6 additions
  TextColumn get subType => text().withDefault(const Constant('cash'))();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  TextColumn get currencyCode => text().withDefault(const Constant('ETB'))();
  IntColumn get openingBalanceCents =>
      integer().withDefault(const Constant(0))();
  TextColumn get openingBalanceDate => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Parties (Lenders, Borrowers, Colleagues, Creditors)
class PartiesTable extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get name => text().withLength(min: 1, max: 150)();
  TextColumn get phone => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Journal Entries (Atomic business transaction headers)
class JournalEntriesTable extends Table {
  TextColumn get id => text()(); // UUID v4
  // standard, transfer, debtIssuance, settlement, splitExpense,
  // adjustment, writeOff
  TextColumn get entryType => text()();
  TextColumn get description => text()();
  TextColumn get occurrenceDate =>
      text()(); // ISO Date YYYY-MM-DD (Economic date)
  BoolColumn get isVoided => boolean().withDefault(const Constant(false))();
  TextColumn get voidReason => text().nullable()();
  // Schema v6 additions; v7 enforces ON DELETE RESTRICT on correctedFromEntryId
  TextColumn get legacySourceTxId => text().nullable()();
  TextColumn get correctedFromEntryId => text()
      .nullable()
      .references(JournalEntriesTable, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Postings (Debits and credits belonging to a journal entry)
/// Invariant: Sum of Debits == Sum of Credits per entry
class PostingsTable extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get entryId => text()
      .references(JournalEntriesTable, #id, onDelete: KeyAction.restrict)();
  TextColumn get accountId =>
      text().references(AccountsTable, #id, onDelete: KeyAction.restrict)();
  IntColumn get amountCents => integer()(); // Minor units > 0
  TextColumn get direction => text()(); // 'debit' or 'credit'
  TextColumn get accountMovementDate =>
      text()(); // ISO Date YYYY-MM-DD (Cash movement date)
  TextColumn get categoryId => text()
      .nullable()
      .references(FinancialCategories, #id, onDelete: KeyAction.restrict)();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Debts (Receivables owed to me & Payables I owe to others)
class DebtsTable extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get originEntryId => text()
      .references(JournalEntriesTable, #id, onDelete: KeyAction.restrict)();
  TextColumn get partyId =>
      text().references(PartiesTable, #id, onDelete: KeyAction.restrict)();
  TextColumn get debtType => text()(); // 'receivable' | 'payable'
  IntColumn get principalCents => integer()(); // Minor units > 0
  IntColumn get outstandingCents => integer()(); // Remaining balance
  TextColumn get dueDate => text().nullable()(); // ISO Date YYYY-MM-DD
  // active, settled, written_off, voided
  TextColumn get status => text().withDefault(const Constant('active'))();
  // Schema v7 addition: explicit link to write-off journal entry
  TextColumn get writeOffEntryId => text()
      .nullable()
      .references(JournalEntriesTable, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Settlement Allocations (Links settlement journal entry to debt record)
class SettlementAllocationsTable extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get settlementEntryId => text()
      .references(JournalEntriesTable, #id, onDelete: KeyAction.restrict)();
  TextColumn get debtId =>
      text().references(DebtsTable, #id, onDelete: KeyAction.restrict)();
  IntColumn get allocatedCents =>
      integer()(); // Amount applied to reduce principal
  TextColumn get settlementDate => text()(); // ISO Date YYYY-MM-DD

  @override
  Set<Column> get primaryKey => {id};
}

/// Monthly Category Budgets (Schema v6; v7 enforces ON DELETE RESTRICT)
class BudgetsTable extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get categoryId => text()
      .references(FinancialCategories, #id, onDelete: KeyAction.restrict)();
  TextColumn get monthIso => text()(); // YYYY-MM
  IntColumn get limitCents => integer()(); // Minor units > 0
  BoolColumn get rolloverEnabled =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Recurring Rules & Scheduled Cashflows (Schema v6; v7 ON DELETE RESTRICT)
class RecurringRulesTable extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get ruleType => text()(); // expense, income, transfer, commitment
  IntColumn get amountCents => integer()(); // Minor units > 0
  TextColumn get frequency =>
      text()(); // weekly, biweekly, monthly, quarterly, yearly
  IntColumn get interval => integer().withDefault(const Constant(1))();
  TextColumn get startDate => text()(); // YYYY-MM-DD
  TextColumn get nextOccurrenceDate => text()(); // YYYY-MM-DD
  TextColumn get endDate => text().nullable()(); // YYYY-MM-DD
  TextColumn get accountId => text()
      .nullable()
      .references(AccountsTable, #id, onDelete: KeyAction.restrict)();
  TextColumn get destinationAccountId => text()
      .nullable()
      .references(AccountsTable, #id, onDelete: KeyAction.restrict)();
  TextColumn get categoryId => text()
      .nullable()
      .references(FinancialCategories, #id, onDelete: KeyAction.restrict)();
  TextColumn get linkedDebtId => text()
      .nullable()
      .references(DebtsTable, #id, onDelete: KeyAction.restrict)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get autoPost => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
