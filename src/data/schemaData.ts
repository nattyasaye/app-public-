export interface TableSchema {
  name: string;
  category: 'core' | 'tasks_projects' | 'finance' | 'system';
  description: string;
  columns: {
    name: string;
    type: string;
    nullable?: boolean;
    primaryKey?: boolean;
    defaultValue?: string;
    foreignKey?: string;
    notes?: string;
  }[];
  indexes: string[];
  dartSnippet: string;
}

export const DRIFT_TABLES: TableSchema[] = [
  {
    name: 'inbox_items',
    category: 'core',
    description: 'Fast capture inbox holding raw thoughts, ideas, expenses, or notes before triage.',
    columns: [
      { name: 'id', type: 'TEXT', primaryKey: true, notes: 'UUID v4' },
      { name: 'raw_text', type: 'TEXT', notes: 'Unparsed captured text' },
      { name: 'category', type: 'TEXT', defaultValue: "'general'", notes: 'task | idea | expense | note | general' },
      { name: 'is_processed', type: 'INTEGER (BOOL)', defaultValue: '0' },
      { name: 'created_at', type: 'INTEGER (DATETIME)', notes: 'UTC Epoch timestamp' },
    ],
    indexes: ['idx_inbox_processed ON inbox_items(is_processed)'],
    dartSnippet: `class InboxItems extends Table {
  TextColumn get id => text()();
  TextColumn get rawText => text()();
  TextColumn get category => text().withDefault(const Constant('general'))();
  BoolColumn get isProcessed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}`,
  },
  {
    name: 'tasks',
    category: 'tasks_projects',
    description: 'User responsibilities and actionable items with priorities, status, and deadlines.',
    columns: [
      { name: 'id', type: 'TEXT', primaryKey: true, notes: 'UUID v4' },
      { name: 'title', type: 'TEXT', notes: 'Max 300 chars' },
      { name: 'description', type: 'TEXT', nullable: true },
      { name: 'status', type: 'TEXT', defaultValue: "'inbox'", notes: 'inbox | not_started | in_progress | completed | cancelled' },
      { name: 'priority', type: 'TEXT', defaultValue: "'medium'", notes: 'low | medium | high | urgent' },
      { name: 'due_date', type: 'INTEGER (DATETIME)', nullable: true, notes: 'Canonical UTC epoch' },
      { name: 'scheduled_date', type: 'INTEGER (DATETIME)', nullable: true },
      { name: 'estimated_duration_minutes', type: 'INTEGER', nullable: true },
      { name: 'project_id', type: 'TEXT', nullable: true, foreignKey: 'projects(id) ON DELETE SET NULL' },
      { name: 'milestone_id', type: 'TEXT', nullable: true, foreignKey: 'milestones(id) ON DELETE SET NULL' },
      { name: 'created_at', type: 'INTEGER (DATETIME)' },
      { name: 'updated_at', type: 'INTEGER (DATETIME)' },
    ],
    indexes: [
      'idx_tasks_due_date ON tasks(due_date)',
      'idx_tasks_status ON tasks(status)',
      'idx_tasks_project ON tasks(project_id)',
    ],
    dartSnippet: `class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 300)();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('inbox'))();
  TextColumn get priority => text().withDefault(const Constant('medium'))();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get scheduledDate => dateTime().nullable()();
  IntColumn get estimatedDurationMinutes => integer().nullable()();
  TextColumn get projectId => text().nullable().references(Projects, #id, onDelete: KeyAction.setNull)();
  TextColumn get milestoneId => text().nullable().references(Milestones, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}`,
  },
  {
    name: 'goals',
    category: 'tasks_projects',
    description: 'High-level desired outcomes and ambitions spanning months or years.',
    columns: [
      { name: 'id', type: 'TEXT', primaryKey: true, notes: 'UUID v4' },
      { name: 'title', type: 'TEXT' },
      { name: 'description', type: 'TEXT', nullable: true },
      { name: 'target_date', type: 'INTEGER (DATETIME)', nullable: true },
      { name: 'status', type: 'TEXT', defaultValue: "'active'", notes: 'active | achieved | archived' },
      { name: 'created_at', type: 'INTEGER (DATETIME)' },
    ],
    indexes: ['idx_goals_status ON goals(status)'],
    dartSnippet: `class Goals extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().nullable()();
  DateTimeColumn get targetDate => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}`,
  },
  {
    name: 'projects',
    category: 'tasks_projects',
    description: 'Organized work towards an outcome. Can belong to an optional Goal.',
    columns: [
      { name: 'id', type: 'TEXT', primaryKey: true, notes: 'UUID v4' },
      { name: 'goal_id', type: 'TEXT', nullable: true, foreignKey: 'goals(id) ON DELETE SET NULL' },
      { name: 'title', type: 'TEXT' },
      { name: 'description', type: 'TEXT', nullable: true },
      { name: 'status', type: 'TEXT', defaultValue: "'active'", notes: 'active | completed | on_hold' },
      { name: 'target_date', type: 'INTEGER (DATETIME)', nullable: true },
      { name: 'created_at', type: 'INTEGER (DATETIME)' },
    ],
    indexes: ['idx_projects_goal ON projects(goal_id)'],
    dartSnippet: `class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get goalId => text().nullable().references(Goals, #id, onDelete: KeyAction.setNull)();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get targetDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}`,
  },
  {
    name: 'milestones',
    category: 'tasks_projects',
    description: 'Optional intermediate project milestones to pace large initiatives.',
    columns: [
      { name: 'id', type: 'TEXT', primaryKey: true },
      { name: 'project_id', type: 'TEXT', foreignKey: 'projects(id) ON DELETE CASCADE' },
      { name: 'title', type: 'TEXT' },
      { name: 'due_date', type: 'INTEGER (DATETIME)', nullable: true },
      { name: 'is_completed', type: 'INTEGER (BOOL)', defaultValue: '0' },
      { name: 'created_at', type: 'INTEGER (DATETIME)' },
    ],
    indexes: ['idx_milestones_project ON milestones(project_id)'],
    dartSnippet: `class Milestones extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(Projects, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  DateTimeColumn get dueDate => dateTime().nullable()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}`,
  },
  {
    name: 'financial_transactions',
    category: 'finance',
    description: 'Recorded real-world cash inflows and outflows. Stored strictly in integer cents (ETB).',
    columns: [
      { name: 'id', type: 'TEXT', primaryKey: true },
      { name: 'category_id', type: 'TEXT', foreignKey: 'financial_categories(id)' },
      { name: 'amount_cents', type: 'INTEGER', notes: 'Integer minor units (1 ETB = 100 cents)' },
      { name: 'type', type: 'TEXT', notes: 'income | expense' },
      { name: 'transaction_date', type: 'INTEGER (DATETIME)', notes: 'Canonical UTC epoch' },
      { name: 'note', type: 'TEXT', nullable: true },
      { name: 'payee', type: 'TEXT', nullable: true },
      { name: 'created_at', type: 'INTEGER (DATETIME)' },
    ],
    indexes: [
      'idx_transactions_date ON financial_transactions(transaction_date)',
      'idx_transactions_category ON financial_transactions(category_id)',
    ],
    dartSnippet: `class FinancialTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text().references(FinancialCategories, #id)();
  IntColumn get amountCents => integer()();
  TextColumn get type => text()();
  DateTimeColumn get transactionDate => dateTime()();
  TextColumn get note => text().nullable()();
  TextColumn get payee => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}`,
  },
  {
    name: 'financial_commitments',
    category: 'finance',
    description: 'Upcoming obligations (Rent, School Fees, Internet). Deducted from Available-to-Spend.',
    columns: [
      { name: 'id', type: 'TEXT', primaryKey: true },
      { name: 'title', type: 'TEXT' },
      { name: 'amount_cents', type: 'INTEGER', notes: 'Integer minor units' },
      { name: 'due_date', type: 'INTEGER (DATETIME)' },
      { name: 'is_paid', type: 'INTEGER (BOOL)', defaultValue: '0' },
      { name: 'recurring_rule', type: 'TEXT', nullable: true },
      { name: 'created_at', type: 'INTEGER (DATETIME)' },
    ],
    indexes: ['idx_commitments_due ON financial_commitments(due_date)'],
    dartSnippet: `class FinancialCommitments extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  IntColumn get amountCents => integer()();
  DateTimeColumn get dueDate => dateTime()();
  BoolColumn get isPaid => boolean().withDefault(const Constant(false))();
  TextColumn get recurringRule => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}`,
  },
  {
    name: 'savings_goals',
    category: 'finance',
    description: 'Dedicated financial targets with reserved allocations withheld from spending balance.',
    columns: [
      { name: 'id', type: 'TEXT', primaryKey: true },
      { name: 'title', type: 'TEXT' },
      { name: 'target_cents', type: 'INTEGER' },
      { name: 'current_allocated_cents', type: 'INTEGER', defaultValue: '0' },
      { name: 'target_date', type: 'INTEGER (DATETIME)', nullable: true },
      { name: 'created_at', type: 'INTEGER (DATETIME)' },
    ],
    indexes: [],
    dartSnippet: `class SavingsGoals extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  IntColumn get targetCents => integer()();
  IntColumn get currentAllocatedCents => integer().withDefault(const Constant(0))();
  DateTimeColumn get targetDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}`,
  },
  {
    name: 'financial_categories',
    category: 'finance',
    description: 'Pre-seeded and custom budget categories with Amharic/English labels.',
    columns: [
      { name: 'id', type: 'TEXT', primaryKey: true },
      { name: 'name', type: 'TEXT', notes: 'e.g. ደመወዝ, ምግብና ሸቀጣ ሸቀጥ' },
      { name: 'type', type: 'TEXT', notes: 'income | expense' },
      { name: 'color_hex', type: 'TEXT', defaultValue: "'#4CAF50'" },
      { name: 'is_default', type: 'INTEGER (BOOL)', defaultValue: '0' },
    ],
    indexes: [],
    dartSnippet: `class FinancialCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get type => text()();
  TextColumn get colorHex => text().withDefault(const Constant('#4CAF50'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}`,
  },
  {
    name: 'notes',
    category: 'core',
    description: 'Personal reference, reflections, ideas, and documentation with Unicode/Amharic support.',
    columns: [
      { name: 'id', type: 'TEXT', primaryKey: true },
      { name: 'title', type: 'TEXT' },
      { name: 'content', type: 'TEXT', notes: 'Full Amharic & Ge`ez Unicode text' },
      { name: 'category', type: 'TEXT', defaultValue: "'general'" },
      { name: 'project_id', type: 'TEXT', nullable: true, foreignKey: 'projects(id) ON DELETE SET NULL' },
      { name: 'goal_id', type: 'TEXT', nullable: true, foreignKey: 'goals(id) ON DELETE SET NULL' },
      { name: 'created_at', type: 'INTEGER (DATETIME)' },
      { name: 'updated_at', type: 'INTEGER (DATETIME)' },
    ],
    indexes: ['idx_notes_category ON notes(category)'],
    dartSnippet: `class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 250)();
  TextColumn get content => text()();
  TextColumn get category => text().withDefault(const Constant('general'))();
  TextColumn get projectId => text().nullable().references(Projects, #id, onDelete: KeyAction.setNull)();
  TextColumn get goalId => text().nullable().references(Goals, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}`,
  },
  {
    name: 'reminders',
    category: 'system',
    description: 'Scheduled local offline alerts for tasks and financial commitments.',
    columns: [
      { name: 'id', type: 'TEXT', primaryKey: true },
      { name: 'target_id', type: 'TEXT' },
      { name: 'target_type', type: 'TEXT', notes: 'task | commitment | custom' },
      { name: 'trigger_time_utc', type: 'INTEGER (DATETIME)' },
      { name: 'is_active', type: 'INTEGER (BOOL)', defaultValue: '1' },
      { name: 'created_at', type: 'INTEGER (DATETIME)' },
    ],
    indexes: ['idx_reminders_trigger ON reminders(trigger_time_utc)'],
    dartSnippet: `class Reminders extends Table {
  TextColumn get id => text()();
  TextColumn get targetId => text()();
  TextColumn get targetType => text()();
  DateTimeColumn get triggerTimeUtc => dateTime()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}`,
  },
  {
    name: 'app_settings',
    category: 'system',
    description: 'Persistent preferences (calendar mode, currency, theme).',
    columns: [
      { name: 'key', type: 'TEXT', primaryKey: true },
      { name: 'value', type: 'TEXT' },
      { name: 'updated_at', type: 'INTEGER (DATETIME)' },
    ],
    indexes: [],
    dartSnippet: `class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}`,
  },
];
