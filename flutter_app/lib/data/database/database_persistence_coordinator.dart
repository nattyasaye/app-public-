import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/date/shared_date.dart';
import '../../core/interfaces/platform_service_interfaces.dart';
import '../../core/shared_foundation_core.dart';
import '../../domain/finance/double_entry_engine.dart';
import 'app_database.dart';
import 'app_settings_policy.dart';
import 'v6_ledger_migrator.dart';
import 'v7_ledger_hardener.dart';

/// Validated, normalized snapshot ready for atomic Phase B SQLite persistence.
class PreparedSnapshotImport {
  final int snapshotVersion;
  final List<SnapshotImportDiagnostic> preImportDiagnostics;
  final Map<String, int> restoredRecordCounts;

  final List<FinancialCategoriesCompanion> categories;
  final List<AccountsTableCompanion> accounts;
  final List<PartiesTableCompanion> parties;
  final List<GoalsCompanion> goals;
  final List<ProjectsCompanion> projects;
  final List<MilestonesCompanion> milestones;
  final List<TasksCompanion> tasks;
  final List<NotesCompanion> notes;
  final List<InboxItemsCompanion> inboxItems;
  final List<CalendarEventsCompanion> calendarEvents;
  final List<FinancialTransactionsCompanion> transactions;
  final List<JournalEntriesTableCompanion> journalEntries;
  final List<PostingsTableCompanion> postings;
  final List<DebtsTableCompanion> debts;
  final List<SettlementAllocationsTableCompanion> settlementAllocations;
  final List<SavingsGoalsCompanion> savingsGoals;
  final List<BudgetsTableCompanion> budgets;
  final List<RecurringRulesTableCompanion> recurringRules;
  final List<FinancialCommitmentsCompanion> commitments;
  final List<CommitmentSettlementsTableCompanion> commitmentSettlements;
  final List<RemindersCompanion> reminders;
  final List<AppSettingsCompanion> appSettings;
  final List<String> replacedAppSettingKeys;

  final bool hasExplicitReminders;
  final bool hasExplicitAppSettings;
  final bool hasExplicitOpeningBalanceCents;
  final int openingBalanceCents;
  final bool? explicitIsFinanceSetupCompleted;
  final bool hasUserAccountsInSnapshot;
  final String? ledgerMigrationReportV7;

  const PreparedSnapshotImport({
    required this.snapshotVersion,
    required this.preImportDiagnostics,
    required this.restoredRecordCounts,
    required this.categories,
    required this.accounts,
    required this.parties,
    required this.goals,
    required this.projects,
    required this.milestones,
    required this.tasks,
    required this.notes,
    required this.inboxItems,
    required this.calendarEvents,
    required this.transactions,
    required this.journalEntries,
    required this.postings,
    required this.debts,
    required this.settlementAllocations,
    required this.savingsGoals,
    required this.budgets,
    required this.recurringRules,
    required this.commitments,
    required this.commitmentSettlements,
    required this.reminders,
    required this.appSettings,
    this.replacedAppSettingKeys = const <String>[],
    required this.hasExplicitReminders,
    required this.hasExplicitAppSettings,
    required this.hasExplicitOpeningBalanceCents,
    required this.openingBalanceCents,
    required this.explicitIsFinanceSetupCompleted,
    required this.hasUserAccountsInSnapshot,
    required this.ledgerMigrationReportV7,
  });
}

/// Coordinates atomic multi-table SQLite snapshots, backup restore,
/// canonical shared-foundation import, and safe demonstration-seed purges.
///
/// Keeps all Drift/SQLite multi-table transaction mechanics inside the Data layer
/// so Application controllers and Presentation remain decoupled from SQLite.
class DatabasePersistenceCoordinator {
  final AppDatabase _db;

  DatabasePersistenceCoordinator(this._db);

  /// Exports the entire authoritative SQLite database state as a JSON-compatible map.
  Future<Map<String, dynamic>> exportSnapshot() async {
    final settings = await _db.select(_db.appSettings).get();
    final settingsMap = {for (final s in settings) s.key: s.value};
    final exportableSettings = settings
        .where((s) => AppSettingsBackupPolicy.isExportableUserSetting(s.key))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final accounts = await _db.select(_db.accountsTable).get();
    final categories = await _db.select(_db.financialCategories).get();
    final categoryNames = {for (final c in categories) c.id: c.name};
    final accountNames = {for (final a in accounts) a.id: a.name};

    final transactions = await _db.select(_db.financialTransactions).get();
    final commitments = await _db.select(_db.financialCommitments).get();
    final commitmentSettlements =
        await _db.select(_db.commitmentSettlementsTable).get();
    final savingsGoals = await _db.select(_db.savingsGoals).get();
    final parties = await _db.select(_db.partiesTable).get();
    final journalEntries = await _db.select(_db.journalEntriesTable).get();
    final postings = await _db.select(_db.postingsTable).get();
    final debts = await _db.select(_db.debtsTable).get();
    final allocations = await _db.select(_db.settlementAllocationsTable).get();
    final budgets = await _db.select(_db.budgetsTable).get();
    final recurringRules = await _db.select(_db.recurringRulesTable).get();

    final lifeGoals = await _db.select(_db.goals).get();
    final projects = await _db.select(_db.projects).get();
    final milestones = await _db.select(_db.milestones).get();
    final tasks = await _db.select(_db.tasks).get();
    final notes = await _db.select(_db.notes).get();
    final inboxItems = await _db.select(_db.inboxItems).get();
    final calendarEvents = await _db.select(_db.calendarEvents).get();
    final reminders = await _db.select(_db.reminders).get();

    final openingBalanceCents =
        int.tryParse(settingsMap[AppDatabase.openingBalanceKey] ?? '') ?? 0;
    final hasUserAccounts = accounts.any((a) => !a.isSystem);
    final isSetupCompleted =
        settingsMap[AppDatabase.financeSetupKey] == 'true' || hasUserAccounts;

    return {
      'schemaVersion': _db.schemaVersion,
      'appVersion': CanonicalSeedDatabase.appVersion,
      'exportedAt': LocalDateTime.now().toEthiopiaIsoString(),
      'isFinanceSetupCompleted': isSetupCompleted,
      'openingBalanceCents': openingBalanceCents,
      'accounts': accounts
          .map((a) => {
                'id': a.id,
                'name': a.name,
                'type': a.type,
                'subType': a.subType,
                'isSystem': a.isSystem,
                'currencyCode': a.currencyCode,
                'isArchived': a.isArchived,
                'openingBalanceCents': a.openingBalanceCents,
                'openingBalanceDate': a.openingBalanceDate,
                'createdAt': EthiopiaClock.toUtcIsoString(a.createdAt),
              })
          .toList(),
      'categories': categories
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'type': c.type,
                'colorHex': c.colorHex,
                'parentId': c.parentId,
                'sortOrder': c.sortOrder,
                'isDefault': c.isDefault,
                'isArchived': c.isArchived,
              })
          .toList(),
      'transactions': transactions
          .map((t) => {
                'id': t.id,
                'categoryId': t.categoryId,
                'categoryName': categoryNames[t.categoryId] ?? 'General',
                'amountCents': t.amountCents,
                'type': t.type,
                'transactionDate': t.transactionDate,
                'note': t.note,
                'payee': t.payee,
                'isSuperseded': t.isSuperseded,
                'correctedFromId': t.correctedFromId,
                'correctionReason': t.correctionReason,
                'accountId': t.accountId,
                'accountName':
                    t.accountId != null ? accountNames[t.accountId!] : null,
                'destinationAccountId': t.destinationAccountId,
                'destinationAccountName': t.destinationAccountId != null
                    ? accountNames[t.destinationAccountId!]
                    : null,
                'createdAt': EthiopiaClock.toUtcIsoString(t.createdAt),
              })
          .toList(),
      'commitments': commitments
          .map((c) => {
                'id': c.id,
                'title': c.title,
                'amountCents': c.amountCents,
                'dueDate': c.dueDate,
                'isPaid': c.isPaid,
                'direction': c.direction,
                'legacyPaidUnverified': c.legacyPaidUnverified,
                'recurringRule': c.recurringRule,
                'linkedAccountId': c.linkedAccountId,
                'categoryId': c.categoryId,
                'linkedDebtId': c.linkedDebtId,
                'settlementEntryId': c.settlementEntryId,
                'recurringRuleId': c.recurringRuleId,
                'createdAt': EthiopiaClock.toUtcIsoString(c.createdAt),
              })
          .toList(),
      'commitmentSettlements': commitmentSettlements
          .map((s) => {
                'id': s.id,
                'commitmentId': s.commitmentId,
                'entryId': s.entryId,
                'amountCents': s.amountCents,
                'settledDate': s.settledDate,
                'createdAt': EthiopiaClock.toUtcIsoString(s.createdAt),
              })
          .toList(),
      'savingsGoals': savingsGoals
          .map((s) => {
                'id': s.id,
                'title': s.title,
                'targetCents': s.targetCents,
                'currentAllocatedCents': s.currentAllocatedCents,
                'targetDate': s.targetDate,
                'linkedAccountId': s.linkedAccountId,
                'status': s.status,
                'createdAt': EthiopiaClock.toUtcIsoString(s.createdAt),
              })
          .toList(),
      'budgets': budgets
          .map((b) => {
                'id': b.id,
                'categoryId': b.categoryId,
                'monthIso': b.monthIso,
                'limitCents': b.limitCents,
                'rolloverEnabled': b.rolloverEnabled,
                'createdAt': EthiopiaClock.toUtcIsoString(b.createdAt),
                'updatedAt': EthiopiaClock.toUtcIsoString(b.updatedAt),
              })
          .toList(),
      'recurringRules': recurringRules
          .map((r) => {
                'id': r.id,
                'title': r.title,
                'ruleType': r.ruleType,
                'amountCents': r.amountCents,
                'frequency': r.frequency,
                'interval': r.interval,
                'startDate': r.startDate,
                'nextOccurrenceDate': r.nextOccurrenceDate,
                'endDate': r.endDate,
                'accountId': r.accountId,
                'destinationAccountId': r.destinationAccountId,
                'categoryId': r.categoryId,
                'linkedDebtId': r.linkedDebtId,
                'isActive': r.isActive,
                'autoPost': r.autoPost,
                'createdAt': EthiopiaClock.toUtcIsoString(r.createdAt),
              })
          .toList(),
      'goals': lifeGoals
          .map((g) => {
                'id': g.id,
                'title': g.title,
                'description': g.description,
                'targetDate': g.targetDate,
                'status': g.status,
                'createdAt': EthiopiaClock.toUtcIsoString(g.createdAt),
              })
          .toList(),
      'parties': parties
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'phone': p.phone,
                'notes': p.notes,
                'isArchived': p.isArchived,
                'createdAt': EthiopiaClock.toUtcIsoString(p.createdAt),
              })
          .toList(),
      'journalEntries': journalEntries
          .map((e) => {
                'id': e.id,
                'entryType': e.entryType,
                'description': e.description,
                'occurrenceDate': e.occurrenceDate,
                'isVoided': e.isVoided,
                'voidReason': e.voidReason,
                'legacySourceTxId': e.legacySourceTxId,
                'correctedFromEntryId': e.correctedFromEntryId,
                'createdAt': EthiopiaClock.toUtcIsoString(e.createdAt),
              })
          .toList(),
      'postings': postings
          .map((p) => {
                'id': p.id,
                'entryId': p.entryId,
                'accountId': p.accountId,
                'amountCents': p.amountCents,
                'direction': p.direction,
                'accountMovementDate': p.accountMovementDate,
                'categoryId': p.categoryId,
                'note': p.note,
              })
          .toList(),
      'debts': debts
          .map((d) => {
                'id': d.id,
                'originEntryId': d.originEntryId,
                'partyId': d.partyId,
                'debtType': d.debtType,
                'principalCents': d.principalCents,
                'outstandingCents': d.outstandingCents,
                'dueDate': d.dueDate,
                'status': d.status,
                'writeOffEntryId': d.writeOffEntryId,
                'createdAt': EthiopiaClock.toUtcIsoString(d.createdAt),
              })
          .toList(),
      'settlementAllocations': allocations
          .map((a) => {
                'id': a.id,
                'settlementEntryId': a.settlementEntryId,
                'debtId': a.debtId,
                'allocatedCents': a.allocatedCents,
                'settlementDate': a.settlementDate,
              })
          .toList(),
      'ledgerMigrationReportV7': settingsMap[V7LedgerHardener.v7ReportKey],
      'projects': projects
          .map((p) => {
                'id': p.id,
                'goalId': p.goalId,
                'title': p.title,
                'description': p.description,
                'status': p.status,
                'targetDate': p.targetDate,
                'createdAt': EthiopiaClock.toUtcIsoString(p.createdAt),
              })
          .toList(),
      'milestones': milestones
          .map((m) => {
                'id': m.id,
                'projectId': m.projectId,
                'title': m.title,
                'dueDate': m.dueDate,
                'isCompleted': m.isCompleted,
                'createdAt': EthiopiaClock.toUtcIsoString(m.createdAt),
              })
          .toList(),
      'tasks': tasks
          .map((t) => {
                'id': t.id,
                'title': t.title,
                'description': t.description,
                'status': t.status,
                'completed': t.status == 'completed',
                'priority': t.priority,
                'dueDate': t.dueDate,
                'scheduledDate': t.scheduledDate,
                'estimatedDurationMinutes': t.estimatedDurationMinutes,
                'projectId': t.projectId,
                'milestoneId': t.milestoneId,
                'subtasks': _decodeJsonList(t.subtasksJson),
                'labels': _decodeStringList(t.labelsJson),
                'isPinned': t.isPinned,
                'isMyDay': t.isMyDay,
                'recurrenceRule': t.recurrenceRule,
                'createdAt': EthiopiaClock.toUtcIsoString(t.createdAt),
                'updatedAt': EthiopiaClock.toUtcIsoString(t.updatedAt),
              })
          .toList(),
      'notes': notes
          .map((n) => {
                'id': n.id,
                'title': n.title,
                'content': n.content,
                'category': n.category,
                'projectId': n.projectId,
                'goalId': n.goalId,
                'tags': _decodeStringList(n.tagsJson),
                'isPinned': n.isPinned,
                'isFavorite': n.isFavorite,
                'isArchived': n.isArchived,
                'isTrashed': n.isTrashed,
                'createdAt': EthiopiaClock.toUtcIsoString(n.createdAt),
                'updatedAt': EthiopiaClock.toUtcIsoString(n.updatedAt),
              })
          .toList(),
      'inboxItems': inboxItems
          .map((i) => {
                'id': i.id,
                'rawText': i.rawText,
                'category': i.category,
                'isProcessed': i.isProcessed,
                'createdAt': EthiopiaClock.toUtcIsoString(i.createdAt),
              })
          .toList(),
      'calendarEvents': calendarEvents
          .map((e) => {
                'id': e.id,
                'title': e.title,
                'dateIso': e.dateIso,
                'date': e.dateIso,
                'endDateIso': e.endDateIso,
                'endDate': e.endDateIso,
                'startTime': e.startTime,
                'endTime': e.endTime,
                'isAllDay': e.isAllDay,
                'category': e.category,
                'colorHex': e.colorHex,
                'hasReminder': e.hasReminder,
                'notes': e.notes,
                'createdAt': EthiopiaClock.toUtcIsoString(e.createdAt),
                'updatedAt': EthiopiaClock.toUtcIsoString(e.updatedAt),
              })
          .toList(),
      'reminders': reminders
          .map((r) => {
                'id': r.id,
                'targetId': r.targetId,
                'targetType': r.targetType,
                'title': r.title,
                'channelId': r.channelId,
                'triggerTimeUtc':
                    EthiopiaClock.toUtcIsoString(r.triggerTimeUtc),
                'isActive': r.isActive,
                'createdAt': EthiopiaClock.toUtcIsoString(r.createdAt),
              })
          .toList(),
      'appSettings': exportableSettings
          .map((s) => {
                'key': s.key,
                'value': s.value,
                'updatedAt': EthiopiaClock.toUtcIsoString(s.updatedAt),
              })
          .toList(),
    };
  }

  static const int minSupportedCanonicalSnapshotVersion = 4;
  static const int maxSupportedCanonicalSnapshotVersion = 8;
  static const int legacyOmittedSnapshotVersion = 5;

  static const List<String> _snapshotListFields = <String>[
    'accounts',
    'categories',
    'transactions',
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
    'goals',
    'projects',
    'milestones',
    'tasks',
    'notes',
    'inboxItems',
    'calendarEvents',
    'reminders',
    'appSettings',
  ];

  static const Set<String> _accountTypes = <String>{
    'asset',
    'liability',
    'equity',
    'income',
    'expense',
    'revenue',
  };

  static const Set<String> _accountSubTypes = <String>{
    'cash',
    'bank',
    'mobile_money',
    'savings_vault',
    'credit_card',
    'receivable',
    'payable',
    'opening_equity',
    'nominal_income',
    'nominal_expense',
    'legacy_clearing',
  };

  static const Set<String> _categoryTypes = <String>{'income', 'expense'};
  static const Set<String> _txTypes = <String>{'income', 'expense', 'transfer'};
  static const Set<String> _goalStatuses = <String>{
    'active',
    'achieved',
    'archived',
  };
  static const Set<String> _projectStatuses = <String>{
    'active',
    'completed',
    'on_hold',
  };
  static const Set<String> _taskStatuses = <String>{
    'inbox',
    'not_started',
    'in_progress',
    'completed',
    'cancelled',
  };
  static const Set<String> _taskPriorities = <String>{
    'low',
    'medium',
    'high',
    'urgent',
  };
  static const Set<String> _inboxCategories = <String>{
    'task',
    'idea',
    'expense',
    'note',
    'problem',
    'decision',
    'general',
  };
  static const Set<String> _postingDirections = <String>{'debit', 'credit'};
  static const Set<String> _journalEntryTypes = <String>{
    'standard',
    'transfer',
    'debtIssuance',
    'settlement',
    'splitExpense',
    'adjustment',
    'writeOff',
  };
  static const Map<String, String> _journalEntryTypeAliases = <String, String>{
    'debt_issuance': 'debtIssuance',
    'split_expense': 'splitExpense',
    'write_off': 'writeOff',
  };
  static const Set<String> _debtTypes = <String>{'receivable', 'payable'};
  static const Set<String> _debtStatuses = <String>{
    'active',
    'settled',
    'written_off',
    'voided',
  };
  static const Set<String> _savingsStatuses = <String>{
    'active',
    'completed',
    'archived',
  };
  static const Set<String> _ruleTypes = <String>{
    'expense',
    'income',
    'transfer',
    'commitment',
  };
  static const Set<String> _ruleFrequencies = <String>{
    'weekly',
    'biweekly',
    'monthly',
    'quarterly',
    'yearly',
  };
  static const Set<String> _commitmentDirections = <String>{
    'outflow',
    'inflow',
  };
  static const Set<String> _reminderTargetTypes = <String>{
    'task',
    'commitment',
    'calendar_event',
    'note',
    'custom',
  };

  /// Validates canonical snapshot structure and version bounds before any
  /// destructive database operation occurs.
  ///
  /// Returns the resolved canonical integer version (`4..8`), preserving the
  /// documented omitted-version legacy default (`5`) only when neither
  /// `schemaVersion` nor `version` is present in [rawSnapshot].
  static int validateCanonicalSnapshot(
    dynamic rawSnapshot, {
    int? expectedHeaderVersion,
  }) {
    if (rawSnapshot is! Map<String, dynamic>) {
      throw const BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Snapshot payload must be a JSON object.',
      );
    }

    final hasSchemaVersion = rawSnapshot.containsKey('schemaVersion');
    final hasVersion = rawSnapshot.containsKey('version');

    int? parsedSchemaVersion;
    if (hasSchemaVersion) {
      final rawSv = rawSnapshot['schemaVersion'];
      if (rawSv is! int) {
        throw const BackupValidationException(
          BackupFailureKind.invalidSnapshotVersion,
          'Snapshot schemaVersion must be a valid integer.',
        );
      }
      parsedSchemaVersion = rawSv;
    }

    int? parsedVersion;
    if (hasVersion) {
      final rawV = rawSnapshot['version'];
      if (rawV is! int) {
        throw const BackupValidationException(
          BackupFailureKind.invalidSnapshotVersion,
          'Snapshot version must be a valid integer.',
        );
      }
      parsedVersion = rawV;
    }

    if (parsedSchemaVersion != null &&
        parsedVersion != null &&
        parsedSchemaVersion != parsedVersion) {
      throw BackupValidationException(
        BackupFailureKind.invalidSnapshotVersion,
        'Contradictory snapshot version metadata: '
        'schemaVersion=$parsedSchemaVersion does not match version=$parsedVersion.',
      );
    }

    final resolvedVersion =
        parsedSchemaVersion ?? parsedVersion ?? legacyOmittedSnapshotVersion;

    if (resolvedVersion < 0) {
      throw BackupValidationException(
        BackupFailureKind.invalidSnapshotVersion,
        'Invalid snapshot version $resolvedVersion: version cannot be negative.',
      );
    }

    if (resolvedVersion > maxSupportedCanonicalSnapshotVersion) {
      throw BackupValidationException(
        BackupFailureKind.unsupportedFutureSchema,
        'Unsupported future snapshot schemaVersion $resolvedVersion '
        '(maximum supported version is $maxSupportedCanonicalSnapshotVersion). '
        'Update Daywell before importing this snapshot.',
      );
    }

    if (resolvedVersion < minSupportedCanonicalSnapshotVersion) {
      throw BackupValidationException(
        BackupFailureKind.invalidSnapshotVersion,
        'Unsupported canonical snapshot version $resolvedVersion '
        '(supported versions are $minSupportedCanonicalSnapshotVersion..'
        '$maxSupportedCanonicalSnapshotVersion).',
      );
    }

    if (expectedHeaderVersion != null &&
        resolvedVersion != expectedHeaderVersion) {
      throw BackupValidationException(
        BackupFailureKind.invalidSnapshotVersion,
        'Backup header schema_version ($expectedHeaderVersion) does not match '
        'effective inner snapshot version ($resolvedVersion).',
      );
    }

    for (final field in _snapshotListFields) {
      if (!rawSnapshot.containsKey(field) || rawSnapshot[field] == null) {
        continue;
      }
      final val = rawSnapshot[field];
      if (val is! List) {
        throw BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Snapshot field "$field" must be a list.',
        );
      }
      for (var i = 0; i < val.length; i++) {
        if (val[i] is! Map<String, dynamic>) {
          throw BackupValidationException(
            BackupFailureKind.invalidPayload,
            'Snapshot item $field[$i] must be a JSON object.',
          );
        }
      }
    }

    return resolvedVersion;
  }

  /// Phase A DB-free unified validation, scalar/date/PK/FK checking, and
  /// normalization pipeline shared across all import and restore entry points.
  static PreparedSnapshotImport validateAndPrepareSnapshot(
    dynamic rawSnapshot, {
    int? expectedHeaderVersion,
    DateTime? fallbackTimestampUtc,
    bool clearExisting = true,
    Set<String> existingCategoryIds = const <String>{},
    Set<String> existingAccountIds = const <String>{},
    Set<String> existingPartyIds = const <String>{},
    Set<String> existingGoalIds = const <String>{},
    Set<String> existingProjectIds = const <String>{},
    Set<String> existingMilestoneIds = const <String>{},
    Set<String> existingTransactionIds = const <String>{},
    Set<String> existingEntryIds = const <String>{},
    Set<String> existingDebtIds = const <String>{},
    Set<String> existingCommitmentIds = const <String>{},
    Set<String> existingRuleIds = const <String>{},
    Set<String> existingTaskIds = const <String>{},
    Set<String> existingCalendarEventIds = const <String>{},
    Set<String> existingNoteIds = const <String>{},
    Map<String, String> existingBudgetIdsByMonthCategory =
        const <String, String>{},
    Map<String, String> existingEntryIdByLegacySourceTxId =
        const <String, String>{},
    Map<String, String> existingAppSettingKeysByLower =
        const <String, String>{},
  }) {
    final snapshotVersion = validateCanonicalSnapshot(
      rawSnapshot,
      expectedHeaderVersion: expectedHeaderVersion,
    );
    final stateMap = rawSnapshot as Map<String, dynamic>;
    final now = (fallbackTimestampUtc ?? EthiopiaClock.nowUtc()).toUtc();
    final diagnostics = <SnapshotImportDiagnostic>[];

    // Validate typed root fields strictly pre-transaction.
    final hasExplicitOpeningBalanceCents =
        stateMap.containsKey('openingBalanceCents') &&
            stateMap['openingBalanceCents'] != null;
    final openingBalanceCents = _optInt(
          stateMap,
          'openingBalanceCents',
          'snapshot',
        ) ??
        0;
    final explicitIsFinanceSetupCompleted = _optBool(
      stateMap,
      'isFinanceSetupCompleted',
      'snapshot',
    );
    String? ledgerMigrationReportV7;
    if (stateMap.containsKey('ledgerMigrationReportV7') &&
        stateMap['ledgerMigrationReportV7'] != null) {
      final rawReport = stateMap['ledgerMigrationReportV7'];
      if (rawReport is! String) {
        throw const BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Snapshot field "ledgerMigrationReportV7" must be a string.',
        );
      }
      ledgerMigrationReportV7 = rawReport;
    }

    List<Map<String, dynamic>> listOf(String key) {
      final raw = stateMap[key] as List<dynamic>?;
      if (raw == null) return const <Map<String, dynamic>>[];
      return raw.cast<Map<String, dynamic>>();
    }

    // 1. Categories (independent seenIds + cycle-safe topological sort)
    final rawCategories = listOf('categories');
    final catSeenIds = <String>{};
    final catStaging = <({
      String id,
      String name,
      String type,
      String colorHex,
      String? parentId,
      int sortOrder,
      bool isDefault,
      bool isArchived,
    })>[];
    for (var i = 0; i < rawCategories.length; i++) {
      final c = rawCategories[i];
      final ctx = 'categories[$i]';
      final id = _reqUniqueId(c, 'categories', i, catSeenIds);
      final name = _reqString(c, 'name', ctx, maxLength: 100).trim();
      final type = _reqEnum(c, 'type', _categoryTypes, ctx);
      final colorHex =
          _optString(c, 'colorHex', ctx, allowEmpty: false) ?? '#1B4D3E';
      final parentId = _optString(c, 'parentId', ctx, allowEmpty: false);
      final sortOrder = _optInt(c, 'sortOrder', ctx) ?? 0;
      final isDefault = _optBool(c, 'isDefault', ctx) ?? false;
      final isArchived = _optBool(c, 'isArchived', ctx) ?? false;
      catStaging.add((
        id: id,
        name: name,
        type: type,
        colorHex: colorHex,
        parentId: parentId,
        sortOrder: sortOrder,
        isDefault: isDefault,
        isArchived: isArchived,
      ));
    }

    // 2. Accounts
    final rawAccounts = listOf('accounts');
    final accountSeenIds = <String>{};
    final hasUserAccountsInSnapshot = <bool>[false];
    final accountCompanions = <AccountsTableCompanion>[];
    for (var i = 0; i < rawAccounts.length; i++) {
      final a = rawAccounts[i];
      final ctx = 'accounts[$i]';
      final id = _reqUniqueId(a, 'accounts', i, accountSeenIds);
      final name = _reqString(a, 'name', ctx, maxLength: 150).trim();
      final type = _optEnum(a, 'type', _accountTypes, ctx) ?? 'asset';
      final subTypeRaw = _optEnum(a, 'subType', _accountSubTypes, ctx);
      final isSystem = _optBool(a, 'isSystem', ctx) ?? false;
      final classified = V6LedgerMigrator.inferAccountClassification(
        id: id,
        name: name,
        type: type,
        currentSubType: subTypeRaw,
        currentIsSystem: isSystem,
      );

      final hasCurrencyKey =
          a.containsKey('currencyCode') && a['currencyCode'] != null;
      late final String currencyCode;
      if (hasCurrencyKey) {
        final rawCurrency = _reqString(a, 'currencyCode', ctx, allowEmpty: true);
        if (classified.isSystem) {
          if (rawCurrency.trim().isEmpty) {
            currencyCode = 'ETB';
          } else if (!DoubleEntryEngine.isEtb(rawCurrency)) {
            throw BackupValidationException(
              BackupFailureKind.invalidPayload,
              'Unsupported currencyCode "${DoubleEntryEngine.normalizeCurrencyCode(rawCurrency)}" on system account $ctx ("$name"): ETB only.',
            );
          } else {
            currencyCode = 'ETB';
          }
        } else {
          if (!DoubleEntryEngine.isEtb(rawCurrency)) {
            final label = rawCurrency.trim().isEmpty
                ? 'empty'
                : DoubleEntryEngine.normalizeCurrencyCode(rawCurrency);
            throw BackupValidationException(
              BackupFailureKind.invalidPayload,
              'Unsupported currencyCode "$label" on $ctx ("$name"): first-release Finance supports ETB only.',
            );
          }
          currencyCode = 'ETB';
        }
      } else if (classified.isSystem) {
        currencyCode = 'ETB';
      } else if (snapshotVersion >= 7) {
        throw BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Missing required field "$ctx.currencyCode" on v$snapshotVersion snapshot: first-release Finance requires explicit "ETB" currencyCode on all accounts.',
        );
      } else {
        currencyCode = '';
        diagnostics.add(
          SnapshotImportDiagnostic(
            code: 'CURRENCY_UNVERIFIED_ON_LEGACY_IMPORT',
            message:
                'Legacy snapshot omitted currencyCode on account "$name" ($id); preserved as Unverified for Currency Review instead of assuming ETB.',
            table: 'accounts',
            recordId: id,
            field: 'currencyCode',
            severity: SnapshotDiagnosticSeverity.warning,
          ),
        );
      }

      final isArchived = _optBool(a, 'isArchived', ctx) ?? false;
      final openingCents = _optInt(a, 'openingBalanceCents', ctx) ?? 0;
      final openingDate = _optCanonicalDate(a, 'openingBalanceDate', ctx);
      final createdAt = _optInstantUtc(a, 'createdAt', ctx) ?? now;
      if (!classified.isSystem) {
        hasUserAccountsInSnapshot[0] = true;
      }
      accountCompanions.add(
        AccountsTableCompanion.insert(
          id: id,
          name: name,
          type: type,
          subType: Value(classified.subType),
          isSystem: Value(classified.isSystem),
          currencyCode: Value(currencyCode),
          openingBalanceCents: Value(openingCents),
          openingBalanceDate: Value(openingDate),
          isArchived: Value(isArchived),
          createdAt: createdAt,
        ),
      );
    }

    // 3. Parties
    final rawParties = listOf('parties');
    final partySeenIds = <String>{};
    final partyCompanions = <PartiesTableCompanion>[];
    for (var i = 0; i < rawParties.length; i++) {
      final p = rawParties[i];
      final ctx = 'parties[$i]';
      final id = _reqUniqueId(p, 'parties', i, partySeenIds);
      final name = _reqString(p, 'name', ctx, maxLength: 150).trim();
      final phone = _optString(p, 'phone', ctx, allowEmpty: true);
      final notes = _optString(p, 'notes', ctx, allowEmpty: true);
      final isArchived = _optBool(p, 'isArchived', ctx) ?? false;
      final createdAt = _optInstantUtc(p, 'createdAt', ctx) ?? now;
      partyCompanions.add(
        PartiesTableCompanion.insert(
          id: id,
          name: name,
          phone: Value(phone),
          notes: Value(notes),
          isArchived: Value(isArchived),
          createdAt: createdAt,
        ),
      );
    }

    // 4. Goals (partition legacy v4 savings-shaped objects before seenIds)
    final rawGoalsAll = listOf('goals');
    final rawLifeGoals = <Map<String, dynamic>>[];
    final legacySavingsFromGoals = <Map<String, dynamic>>[];
    for (final g in rawGoalsAll) {
      if (g.containsKey('targetCents') && !g.containsKey('status')) {
        legacySavingsFromGoals.add(g);
      } else {
        rawLifeGoals.add(g);
      }
    }
    final goalSeenIds = <String>{};
    final goalCompanions = <GoalsCompanion>[];
    for (var i = 0; i < rawLifeGoals.length; i++) {
      final g = rawLifeGoals[i];
      final ctx = 'goals[$i]';
      final id = _reqUniqueId(g, 'goals', i, goalSeenIds);
      final title = _reqString(g, 'title', ctx, maxLength: 200).trim();
      final description = _optString(g, 'description', ctx, allowEmpty: true);
      final targetDate = _optCanonicalDate(g, 'targetDate', ctx);
      final status = _optEnum(g, 'status', _goalStatuses, ctx) ?? 'active';
      final createdAt = _optInstantUtc(g, 'createdAt', ctx) ?? now;
      goalCompanions.add(
        GoalsCompanion.insert(
          id: id,
          title: title,
          description: Value(description),
          targetDate: Value(targetDate),
          status: Value(status),
          createdAt: createdAt,
        ),
      );
    }
    final targetGoalIds = <String>{...existingGoalIds, ...goalSeenIds};

    // 5. Projects (Tier 2: goalId)
    final rawProjects = listOf('projects');
    final projectSeenIds = <String>{};
    final projectCompanions = <ProjectsCompanion>[];
    for (var i = 0; i < rawProjects.length; i++) {
      final p = rawProjects[i];
      final ctx = 'projects[$i]';
      final id = _reqUniqueId(p, 'projects', i, projectSeenIds);
      final title = _reqString(p, 'title', ctx, maxLength: 200).trim();
      final description = _optString(p, 'description', ctx, allowEmpty: true);
      final rawGoalId = _optString(p, 'goalId', ctx, allowEmpty: false);
      String? safeGoalId;
      if (rawGoalId != null) {
        if (targetGoalIds.contains(rawGoalId)) {
          safeGoalId = rawGoalId;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_PROJECT_GOAL_CLEARED',
              message: 'Cleared missing goalId "$rawGoalId" on project "$id".',
              table: 'projects',
              recordId: id,
              field: 'goalId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      final status = _optEnum(p, 'status', _projectStatuses, ctx) ?? 'active';
      final targetDate = _optCanonicalDate(p, 'targetDate', ctx);
      final createdAt = _optInstantUtc(p, 'createdAt', ctx) ?? now;
      projectCompanions.add(
        ProjectsCompanion.insert(
          id: id,
          goalId: Value(safeGoalId),
          title: title,
          description: Value(description),
          status: Value(status),
          targetDate: Value(targetDate),
          createdAt: createdAt,
        ),
      );
    }
    final targetProjectIds = <String>{...existingProjectIds, ...projectSeenIds};

    // 6. Milestones (Tier 1 required FK: projectId)
    final rawMilestones = listOf('milestones');
    final milestoneSeenIds = <String>{};
    final milestoneCompanions = <MilestonesCompanion>[];
    for (var i = 0; i < rawMilestones.length; i++) {
      final m = rawMilestones[i];
      final ctx = 'milestones[$i]';
      final id = _reqUniqueId(m, 'milestones', i, milestoneSeenIds);
      final projectId = _reqString(m, 'projectId', ctx).trim();
      if (!targetProjectIds.contains(projectId)) {
        throw BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Invalid foreign key "$ctx.projectId": project "$projectId" does not exist.',
        );
      }
      final title = _reqString(m, 'title', ctx, maxLength: 200).trim();
      final dueDate = _optCanonicalDate(m, 'dueDate', ctx);
      final isCompleted = _optBool(m, 'isCompleted', ctx) ?? false;
      final createdAt = _optInstantUtc(m, 'createdAt', ctx) ?? now;
      milestoneCompanions.add(
        MilestonesCompanion.insert(
          id: id,
          projectId: projectId,
          title: title,
          dueDate: Value(dueDate),
          isCompleted: Value(isCompleted),
          createdAt: createdAt,
        ),
      );
    }
    final targetMilestoneIds = <String>{
      ...existingMilestoneIds,
      ...milestoneSeenIds,
    };

    // 7. Tasks (Tier 2: projectId, milestoneId)
    final rawTasks = listOf('tasks');
    final taskSeenIds = <String>{};
    final taskCompanions = <TasksCompanion>[];
    for (var i = 0; i < rawTasks.length; i++) {
      final t = rawTasks[i];
      final ctx = 'tasks[$i]';
      final id = _reqUniqueId(t, 'tasks', i, taskSeenIds);
      final title = _reqString(t, 'title', ctx, maxLength: 300).trim();
      final description = _optString(t, 'description', ctx, allowEmpty: true);
      final completed = _optBool(t, 'completed', ctx);
      final status = _optEnum(t, 'status', _taskStatuses, ctx) ??
          (completed == true ? 'completed' : 'not_started');
      final priority =
          _optEnum(t, 'priority', _taskPriorities, ctx) ?? 'medium';
      final dueDate = _optCanonicalDate(t, 'dueDate', ctx);
      final scheduledDate = _optCanonicalDate(t, 'scheduledDate', ctx);
      final estimatedMinutes =
          _optInt(t, 'estimatedDurationMinutes', ctx, min: 0);
      final rawProjectId = _optString(t, 'projectId', ctx, allowEmpty: false);
      String? safeProjectId;
      if (rawProjectId != null) {
        if (targetProjectIds.contains(rawProjectId)) {
          safeProjectId = rawProjectId;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_TASK_PROJECT_CLEARED',
              message:
                  'Cleared missing projectId "$rawProjectId" on task "$id".',
              table: 'tasks',
              recordId: id,
              field: 'projectId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      final rawMilestoneId =
          _optString(t, 'milestoneId', ctx, allowEmpty: false);
      String? safeMilestoneId;
      if (rawMilestoneId != null) {
        if (targetMilestoneIds.contains(rawMilestoneId)) {
          safeMilestoneId = rawMilestoneId;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_TASK_MILESTONE_CLEARED',
              message:
                  'Cleared missing milestoneId "$rawMilestoneId" on task "$id".',
              table: 'tasks',
              recordId: id,
              field: 'milestoneId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      final subtasks = _optJsonList(t, 'subtasks', ctx);
      final labels = _optStringList(t, 'labels', ctx);
      final isPinned = _optBool(t, 'isPinned', ctx) ?? false;
      final isMyDay = _optBool(t, 'isMyDay', ctx) ?? false;
      final recurrenceRule =
          _optString(t, 'recurrenceRule', ctx, allowEmpty: true);
      final createdAt = _optInstantUtc(t, 'createdAt', ctx) ?? now;
      final updatedAt = _optInstantUtc(t, 'updatedAt', ctx) ?? createdAt;

      taskCompanions.add(
        TasksCompanion.insert(
          id: id,
          title: title,
          description: Value(description),
          status: Value(status),
          priority: Value(priority),
          dueDate: Value(dueDate),
          scheduledDate: Value(scheduledDate),
          estimatedDurationMinutes: Value(estimatedMinutes),
          projectId: Value(safeProjectId),
          milestoneId: Value(safeMilestoneId),
          subtasksJson: Value(jsonEncode(subtasks)),
          labelsJson: Value(jsonEncode(labels)),
          isPinned: Value(isPinned),
          isMyDay: Value(isMyDay),
          recurrenceRule: Value(recurrenceRule),
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
      );
    }

    // 8. Notes (Tier 2: projectId, goalId)
    final rawNotes = listOf('notes');
    final noteSeenIds = <String>{};
    final noteCompanions = <NotesCompanion>[];
    for (var i = 0; i < rawNotes.length; i++) {
      final n = rawNotes[i];
      final ctx = 'notes[$i]';
      final id = _reqUniqueId(n, 'notes', i, noteSeenIds);
      final title = _reqString(n, 'title', ctx, maxLength: 250).trim();
      final content = _optString(n, 'content', ctx, allowEmpty: true) ??
          _optString(n, 'body', ctx, allowEmpty: true) ??
          '';
      final category = _optString(n, 'category', ctx, allowEmpty: false) ??
          _optString(n, 'folder', ctx, allowEmpty: false) ??
          'general';
      final rawProjectId = _optString(n, 'projectId', ctx, allowEmpty: false);
      String? safeProjectId;
      if (rawProjectId != null) {
        if (targetProjectIds.contains(rawProjectId)) {
          safeProjectId = rawProjectId;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_NOTE_PROJECT_CLEARED',
              message:
                  'Cleared missing projectId "$rawProjectId" on note "$id".',
              table: 'notes',
              recordId: id,
              field: 'projectId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      final rawGoalId = _optString(n, 'goalId', ctx, allowEmpty: false);
      String? safeGoalId;
      if (rawGoalId != null) {
        if (targetGoalIds.contains(rawGoalId)) {
          safeGoalId = rawGoalId;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_NOTE_GOAL_CLEARED',
              message: 'Cleared missing goalId "$rawGoalId" on note "$id".',
              table: 'notes',
              recordId: id,
              field: 'goalId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      final tags = _optStringList(n, 'tags', ctx);
      final isPinned = _optBool(n, 'isPinned', ctx) ?? false;
      final isFavorite = _optBool(n, 'isFavorite', ctx) ?? false;
      final isArchived = _optBool(n, 'isArchived', ctx) ?? false;
      final isTrashed = _optBool(n, 'isTrashed', ctx) ?? false;
      final createdAt = _optInstantUtc(n, 'createdAt', ctx) ?? now;
      final updatedAt = _optInstantUtc(n, 'updatedAt', ctx) ?? createdAt;

      noteCompanions.add(
        NotesCompanion.insert(
          id: id,
          title: title,
          content: content,
          category: Value(category),
          projectId: Value(safeProjectId),
          goalId: Value(safeGoalId),
          tagsJson: Value(jsonEncode(tags)),
          isPinned: Value(isPinned),
          isFavorite: Value(isFavorite),
          isArchived: Value(isArchived),
          isTrashed: Value(isTrashed),
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
      );
    }

    // 9. InboxItems
    final rawInbox = listOf('inboxItems');
    final inboxSeenIds = <String>{};
    final inboxCompanions = <InboxItemsCompanion>[];
    for (var i = 0; i < rawInbox.length; i++) {
      final item = rawInbox[i];
      final ctx = 'inboxItems[$i]';
      final id = _reqUniqueId(item, 'inboxItems', i, inboxSeenIds);
      final rawText = _reqString(item, 'rawText', ctx).trim();
      final category =
          _optEnum(item, 'category', _inboxCategories, ctx) ?? 'general';
      final isProcessed = _optBool(item, 'isProcessed', ctx) ?? false;
      final createdAt = _optInstantUtc(item, 'createdAt', ctx) ?? now;
      inboxCompanions.add(
        InboxItemsCompanion.insert(
          id: id,
          rawText: rawText,
          category: Value(category),
          isProcessed: Value(isProcessed),
          createdAt: createdAt,
        ),
      );
    }

    // 10. CalendarEvents
    final rawEvents = listOf('calendarEvents');
    final eventSeenIds = <String>{};
    final eventCompanions = <CalendarEventsCompanion>[];
    for (var i = 0; i < rawEvents.length; i++) {
      final e = rawEvents[i];
      final ctx = 'calendarEvents[$i]';
      final id = _reqUniqueId(e, 'calendarEvents', i, eventSeenIds);
      final title = _reqString(e, 'title', ctx, maxLength: 250).trim();
      final dateIso = _reqCanonicalDateFromKeys(
        e,
        const <String>['dateIso', 'date'],
        ctx,
        'dateIso',
      );
      final endDateIso = _optCanonicalDateFromKeys(
        e,
        const <String>['endDateIso', 'endDate'],
        ctx,
        'endDateIso',
      );
      if (endDateIso != null && endDateIso.compareTo(dateIso) < 0) {
        throw BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Calendar event "$id" endDateIso ($endDateIso) cannot precede dateIso ($dateIso).',
        );
      }
      final startTime = _optString(e, 'startTime', ctx, allowEmpty: true);
      final endTime = _optString(e, 'endTime', ctx, allowEmpty: true);
      final isAllDay = _optBool(e, 'isAllDay', ctx) ?? false;
      final category =
          _optString(e, 'category', ctx, allowEmpty: false) ?? 'personal';
      final colorHex =
          _optString(e, 'colorHex', ctx, allowEmpty: false) ?? '#1B4D3E';
      final hasReminder = _optBool(e, 'hasReminder', ctx) ?? false;
      final notes = _optString(e, 'notes', ctx, allowEmpty: true);
      final createdAt = _optInstantUtc(e, 'createdAt', ctx) ?? now;
      final updatedAt = _optInstantUtc(e, 'updatedAt', ctx) ?? createdAt;

      eventCompanions.add(
        CalendarEventsCompanion.insert(
          id: id,
          title: title,
          dateIso: dateIso,
          endDateIso: Value(endDateIso),
          startTime: Value(startTime),
          endTime: Value(endTime),
          isAllDay: Value(isAllDay),
          category: Value(category),
          colorHex: Value(colorHex),
          hasReminder: Value(hasReminder),
          notes: Value(notes),
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
      );
    }

    // Finalize Categories (topological sort + cycle/orphan parentId clearing)
    final allInitialCatIds = <String>{...existingCategoryIds, ...catSeenIds};
    final orderedCats = _topologicalSortByParent(
      items: catStaging,
      getId: (c) => c.id,
      getParentId: (c) => c.parentId,
    );
    final placedCatIds = <String>{...existingCategoryIds};
    final categoryCompanions = <FinancialCategoriesCompanion>[];
    for (final c in orderedCats) {
      final rawParentId = c.parentId;
      String? safeParentId;
      if (rawParentId != null) {
        if (rawParentId != c.id &&
            allInitialCatIds.contains(rawParentId) &&
            placedCatIds.contains(rawParentId)) {
          safeParentId = rawParentId;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_CATEGORY_PARENT_CLEARED',
              message:
                  'Cleared orphaned or cyclic parentId "$rawParentId" on category "${c.id}".',
              table: 'categories',
              recordId: c.id,
              field: 'parentId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      placedCatIds.add(c.id);
      categoryCompanions.add(
        FinancialCategoriesCompanion.insert(
          id: c.id,
          name: c.name,
          type: c.type,
          colorHex: Value(c.colorHex),
          parentId: Value(safeParentId),
          sortOrder: Value(c.sortOrder),
          isDefault: Value(c.isDefault),
          isArchived: Value(c.isArchived),
        ),
      );
    }

    // Lookup canonical starter categories from CanonicalSeedDatabase strictly
    // for omitted transfer / legacy < v7 transaction fallbacks.
    final canonicalStarterCategoriesById = <String, Map<String, dynamic>>{};
    final seedCats =
        CanonicalSeedDatabase.state['categories'] as List<dynamic>? ??
            const <dynamic>[];
    for (final item in seedCats) {
      if (item is Map<String, dynamic> && item['id'] is String) {
        canonicalStarterCategoriesById[item['id'] as String] = item;
      }
    }

    // 11. Transactions (Pass 1: IDs/scalars/categoryId rule; Pass 2: soft FKs)
    final rawTxs = listOf('transactions');
    final txSeenIds = <String>{};
    final txStaging = <({
      String id,
      String categoryId,
      int amountCents,
      String type,
      String transactionDate,
      String? note,
      String? payee,
      String? accountId,
      String? destinationAccountId,
      bool isSuperseded,
      String? correctedFromId,
      String? correctionReason,
      DateTime createdAt,
    })>[];

    for (var i = 0; i < rawTxs.length; i++) {
      final t = rawTxs[i];
      final ctx = 'transactions[$i]';
      final id = _reqUniqueId(t, 'transactions', i, txSeenIds);
      final type = _reqEnum(t, 'type', _txTypes, ctx);
      final amountCents = _reqInt(t, 'amountCents', ctx, min: 1);
      final txDate = _reqCanonicalDate(t, 'transactionDate', ctx);
      final note = _optString(t, 'note', ctx, allowEmpty: true);
      final payee = _optString(t, 'payee', ctx, allowEmpty: true);
      final accountId = _optString(t, 'accountId', ctx, allowEmpty: false);
      final destAccountId =
          _optString(t, 'destinationAccountId', ctx, allowEmpty: false);
      final isSuperseded = _optBool(t, 'isSuperseded', ctx) ?? false;
      final correctedFromId =
          _optString(t, 'correctedFromId', ctx, allowEmpty: false);
      final correctionReason =
          _optString(t, 'correctionReason', ctx, allowEmpty: true);
      final createdAt = _optInstantUtc(t, 'createdAt', ctx) ?? now;

      // Explicit Contract Resolution for FinancialTransactions.categoryId
      if (t.containsKey('categoryId') && t['categoryId'] != null) {
        final rawCat = t['categoryId'];
        if (rawCat is! String || rawCat.trim().isEmpty) {
          throw BackupValidationException(
            BackupFailureKind.invalidPayload,
            'Invalid field "$ctx.categoryId": expected a non-empty string.',
          );
        }
        final explicitCatId = rawCat.trim();
        if (!placedCatIds.contains(explicitCatId)) {
          throw BackupValidationException(
            BackupFailureKind.invalidPayload,
            'Invalid foreign key "$ctx.categoryId": category "$explicitCatId" does not exist.',
          );
        }
        txStaging.add((
          id: id,
          categoryId: explicitCatId,
          amountCents: amountCents,
          type: type,
          transactionDate: txDate,
          note: note,
          payee: payee,
          accountId: accountId,
          destinationAccountId: destAccountId,
          isSuperseded: isSuperseded,
          correctedFromId: correctedFromId,
          correctionReason: correctionReason,
          createdAt: createdAt,
        ));
      } else {
        if (snapshotVersion >= 7) {
          throw BackupValidationException(
            BackupFailureKind.invalidPayload,
            'Missing required foreign key "$ctx.categoryId" on v$snapshotVersion $type transaction "$id".',
          );
        }
        final canonicalId =
            type == 'income' ? 'cat-other-inc' : 'cat-other-exp';
        if (!placedCatIds.contains(canonicalId)) {
          final seedCat = canonicalStarterCategoriesById[canonicalId];
          if (seedCat == null) {
            throw BackupValidationException(
              BackupFailureKind.invalidPayload,
              'Missing canonical fallback category "$canonicalId" for "$ctx.categoryId".',
            );
          }
          placedCatIds.add(canonicalId);
          categoryCompanions.add(
            FinancialCategoriesCompanion.insert(
              id: canonicalId,
              name: seedCat['name'] as String,
              type: seedCat['type'] as String,
              colorHex: Value((seedCat['colorHex'] as String?) ?? '#64748B'),
              isDefault: Value((seedCat['isDefault'] as bool?) ?? true),
              isArchived: Value((seedCat['isArchived'] as bool?) ?? false),
            ),
          );
        }
        diagnostics.add(
          SnapshotImportDiagnostic(
            code: 'LEGACY_TRANSACTION_DEFAULT_CATEGORY_APPLIED',
            message:
                'Resolved omitted categoryId on $type transaction "$id" to canonical starter category "$canonicalId".',
            table: 'transactions',
            recordId: id,
            field: 'categoryId',
            severity: SnapshotDiagnosticSeverity.warning,
          ),
        );
        txStaging.add((
          id: id,
          categoryId: canonicalId,
          amountCents: amountCents,
          type: type,
          transactionDate: txDate,
          note: note,
          payee: payee,
          accountId: accountId,
          destinationAccountId: destAccountId,
          isSuperseded: isSuperseded,
          correctedFromId: correctedFromId,
          correctionReason: correctionReason,
          createdAt: createdAt,
        ));
      }
    }

    final targetCategoryIds = Set<String>.unmodifiable(placedCatIds);
    final targetAccountIds = <String>{...existingAccountIds, ...accountSeenIds};
    final targetAccountIdsWithSystem = <String>{
      ...targetAccountIds,
      ...SystemControlAccounts.allIds,
    };
    final targetPartyIds = <String>{...existingPartyIds, ...partySeenIds};
    final targetTransactionIds = <String>{
      ...existingTransactionIds,
      ...txSeenIds,
    };

    final transactionCompanions = <FinancialTransactionsCompanion>[];
    for (final tx in txStaging) {
      String? safeAccountId;
      if (tx.accountId != null) {
        if (targetAccountIdsWithSystem.contains(tx.accountId)) {
          safeAccountId = tx.accountId;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_TRANSACTION_ACCOUNT_CLEARED',
              message:
                  'Cleared missing accountId "${tx.accountId}" on transaction "${tx.id}".',
              table: 'transactions',
              recordId: tx.id,
              field: 'accountId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      String? safeDestAccountId;
      if (tx.destinationAccountId != null) {
        if (targetAccountIdsWithSystem.contains(tx.destinationAccountId)) {
          safeDestAccountId = tx.destinationAccountId;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_TRANSACTION_DESTINATION_CLEARED',
              message:
                  'Cleared missing destinationAccountId "${tx.destinationAccountId}" on transaction "${tx.id}".',
              table: 'transactions',
              recordId: tx.id,
              field: 'destinationAccountId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      String? safeCorrectedFromId;
      if (tx.correctedFromId != null) {
        if (tx.correctedFromId != tx.id &&
            targetTransactionIds.contains(tx.correctedFromId)) {
          safeCorrectedFromId = tx.correctedFromId;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_TRANSACTION_CORRECTION_CLEARED',
              message:
                  'Cleared missing or self-referential correctedFromId "${tx.correctedFromId}" on transaction "${tx.id}".',
              table: 'transactions',
              recordId: tx.id,
              field: 'correctedFromId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      transactionCompanions.add(
        FinancialTransactionsCompanion.insert(
          id: tx.id,
          categoryId: tx.categoryId,
          amountCents: tx.amountCents,
          type: tx.type,
          transactionDate: tx.transactionDate,
          note: Value(tx.note),
          payee: Value(tx.payee),
          accountId: Value(safeAccountId),
          destinationAccountId: Value(safeDestAccountId),
          isSuperseded: Value(tx.isSuperseded),
          correctedFromId: Value(safeCorrectedFromId),
          correctionReason: Value(tx.correctionReason),
          createdAt: tx.createdAt,
        ),
      );
    }

    // 12. JournalEntries (topological by correctedFromEntryId + partial unique legacySourceTxId)
    final rawEntries = listOf('journalEntries');
    final entrySeenIds = <String>{};
    final legacySourceSeen = <String, String>{
      ...existingEntryIdByLegacySourceTxId,
    };
    final entryStaging = <({
      String id,
      String entryType,
      String description,
      String occurrenceDate,
      bool isVoided,
      String? voidReason,
      String? legacySourceTxId,
      String? correctedFromEntryId,
      DateTime createdAt,
    })>[];
    for (var i = 0; i < rawEntries.length; i++) {
      final e = rawEntries[i];
      final ctx = 'journalEntries[$i]';
      final id = _reqUniqueId(e, 'journalEntries', i, entrySeenIds);
      final rawEntryType = _optString(e, 'entryType', ctx, allowEmpty: false);
      final entryType = rawEntryType == null
          ? 'standard'
          : (_journalEntryTypeAliases[rawEntryType] ?? rawEntryType);
      if (!_journalEntryTypes.contains(entryType)) {
        throw BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Invalid field "$ctx.entryType": "$entryType" is not one of ${_journalEntryTypes.join(', ')}.',
        );
      }
      final description =
          _optString(e, 'description', ctx, allowEmpty: true) ?? '';
      final occurrenceDate = _reqCanonicalDate(e, 'occurrenceDate', ctx);
      final isVoided = _optBool(e, 'isVoided', ctx) ?? false;
      final voidReason = _optString(e, 'voidReason', ctx, allowEmpty: true);
      final legacySourceTxId =
          _optString(e, 'legacySourceTxId', ctx, allowEmpty: false);
      if (legacySourceTxId != null) {
        final existingOwnerId = legacySourceSeen[legacySourceTxId];
        if (existingOwnerId != null && existingOwnerId != id) {
          throw BackupValidationException(
            BackupFailureKind.invalidPayload,
            'Duplicate legacySourceTxId "$legacySourceTxId" in "$ctx".',
          );
        }
        legacySourceSeen[legacySourceTxId] = id;
      }
      final correctedFromEntryId =
          _optString(e, 'correctedFromEntryId', ctx, allowEmpty: false);
      final createdAt = _optInstantUtc(e, 'createdAt', ctx) ?? now;
      entryStaging.add((
        id: id,
        entryType: entryType,
        description: description,
        occurrenceDate: occurrenceDate,
        isVoided: isVoided,
        voidReason: voidReason,
        legacySourceTxId: legacySourceTxId,
        correctedFromEntryId: correctedFromEntryId,
        createdAt: createdAt,
      ));
    }

    final allInitialEntryIds = <String>{...existingEntryIds, ...entrySeenIds};
    final orderedEntries = _topologicalSortByParent(
      items: entryStaging,
      getId: (e) => e.id,
      getParentId: (e) => e.correctedFromEntryId,
    );
    final placedEntryIds = <String>{...existingEntryIds};
    final entryCompanions = <JournalEntriesTableCompanion>[];
    for (final e in orderedEntries) {
      final rawCorrected = e.correctedFromEntryId;
      String? safeCorrected;
      if (rawCorrected != null) {
        if (rawCorrected != e.id &&
            allInitialEntryIds.contains(rawCorrected) &&
            placedEntryIds.contains(rawCorrected)) {
          safeCorrected = rawCorrected;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_CORRECTED_ENTRY_CLEARED',
              message:
                  'Cleared orphaned or cyclic correctedFromEntryId "$rawCorrected" on journal entry "${e.id}".',
              table: 'journalEntries',
              recordId: e.id,
              field: 'correctedFromEntryId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      placedEntryIds.add(e.id);
      entryCompanions.add(
        JournalEntriesTableCompanion.insert(
          id: e.id,
          entryType: e.entryType,
          description: e.description,
          occurrenceDate: e.occurrenceDate,
          isVoided: Value(e.isVoided),
          voidReason: Value(e.voidReason),
          legacySourceTxId: Value(e.legacySourceTxId),
          correctedFromEntryId: Value(safeCorrected),
          createdAt: e.createdAt,
        ),
      );
    }
    final targetEntryIds = Set<String>.unmodifiable(placedEntryIds);

    // 13. Postings (Tier 1: entryId, accountId; Tier 2: categoryId)
    final rawPostings = listOf('postings');
    final postingSeenIds = <String>{};
    final postingCompanions = <PostingsTableCompanion>[];
    for (var i = 0; i < rawPostings.length; i++) {
      final p = rawPostings[i];
      final ctx = 'postings[$i]';
      final id = _reqUniqueId(p, 'postings', i, postingSeenIds);
      final entryId = _reqString(p, 'entryId', ctx).trim();
      if (!targetEntryIds.contains(entryId)) {
        throw BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Invalid foreign key "$ctx.entryId": journal entry "$entryId" does not exist.',
        );
      }
      final accountId = _reqString(p, 'accountId', ctx).trim();
      if (!targetAccountIdsWithSystem.contains(accountId)) {
        throw BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Invalid foreign key "$ctx.accountId": account "$accountId" does not exist.',
        );
      }
      final amountCents = _reqInt(p, 'amountCents', ctx, min: 1);
      final direction =
          _optEnum(p, 'direction', _postingDirections, ctx) ?? 'debit';
      final movementDate = _reqCanonicalDate(p, 'accountMovementDate', ctx);
      final rawCatId = _optString(p, 'categoryId', ctx, allowEmpty: false);
      String? safeCatId;
      if (rawCatId != null) {
        if (targetCategoryIds.contains(rawCatId)) {
          safeCatId = rawCatId;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_POSTING_CATEGORY_CLEARED',
              message:
                  'Cleared missing categoryId "$rawCatId" on posting "$id".',
              table: 'postings',
              recordId: id,
              field: 'categoryId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      final note = _optString(p, 'note', ctx, allowEmpty: true);
      postingCompanions.add(
        PostingsTableCompanion.insert(
          id: id,
          entryId: entryId,
          accountId: accountId,
          amountCents: amountCents,
          direction: direction,
          accountMovementDate: movementDate,
          categoryId: Value(safeCatId),
          note: Value(note),
        ),
      );
    }

    // 14. Debts (Tier 1: originEntryId, partyId; Tier 2: writeOffEntryId)
    final rawDebts = listOf('debts');
    final debtSeenIds = <String>{};
    final debtCompanions = <DebtsTableCompanion>[];
    for (var i = 0; i < rawDebts.length; i++) {
      final d = rawDebts[i];
      final ctx = 'debts[$i]';
      final id = _reqUniqueId(d, 'debts', i, debtSeenIds);
      final originEntryId = _reqString(d, 'originEntryId', ctx).trim();
      if (!targetEntryIds.contains(originEntryId)) {
        throw BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Invalid foreign key "$ctx.originEntryId": journal entry "$originEntryId" does not exist.',
        );
      }
      final partyId = _reqString(d, 'partyId', ctx).trim();
      if (!targetPartyIds.contains(partyId)) {
        throw BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Invalid foreign key "$ctx.partyId": party "$partyId" does not exist.',
        );
      }
      final debtType = _optEnum(d, 'debtType', _debtTypes, ctx) ?? 'payable';
      final principalCents = _reqInt(d, 'principalCents', ctx, min: 1);
      final outstandingCents = _optInt(d, 'outstandingCents', ctx, min: 0) ?? 0;
      final dueDate = _optCanonicalDate(d, 'dueDate', ctx);
      final rawStatus = _optString(d, 'status', ctx, allowEmpty: false);
      final normalizedStatus = rawStatus == null
          ? 'active'
          : (rawStatus == 'writtenOff' ? 'written_off' : rawStatus);
      if (!_debtStatuses.contains(normalizedStatus)) {
        throw BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Invalid field "$ctx.status": "$normalizedStatus" is not one of ${_debtStatuses.join(', ')}.',
        );
      }
      final rawWriteOffId =
          _optString(d, 'writeOffEntryId', ctx, allowEmpty: false);
      String? safeWriteOffId;
      if (rawWriteOffId != null) {
        if (targetEntryIds.contains(rawWriteOffId)) {
          safeWriteOffId = rawWriteOffId;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_DEBT_WRITEOFF_ENTRY_CLEARED',
              message:
                  'Cleared missing writeOffEntryId "$rawWriteOffId" on debt "$id".',
              table: 'debts',
              recordId: id,
              field: 'writeOffEntryId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      final createdAt = _optInstantUtc(d, 'createdAt', ctx) ?? now;
      debtCompanions.add(
        DebtsTableCompanion.insert(
          id: id,
          originEntryId: originEntryId,
          partyId: partyId,
          debtType: debtType,
          principalCents: principalCents,
          outstandingCents: outstandingCents,
          dueDate: Value(dueDate),
          status: Value(normalizedStatus),
          writeOffEntryId: Value(safeWriteOffId),
          createdAt: createdAt,
        ),
      );
    }
    final targetDebtIds = <String>{...existingDebtIds, ...debtSeenIds};

    // 15. SettlementAllocations (Tier 1: settlementEntryId, debtId)
    final rawAllocations = listOf('settlementAllocations');
    final allocationSeenIds = <String>{};
    final allocationCompanions = <SettlementAllocationsTableCompanion>[];
    for (var i = 0; i < rawAllocations.length; i++) {
      final a = rawAllocations[i];
      final ctx = 'settlementAllocations[$i]';
      final id = _reqUniqueId(a, 'settlementAllocations', i, allocationSeenIds);
      final entryId = _reqString(a, 'settlementEntryId', ctx).trim();
      if (!targetEntryIds.contains(entryId)) {
        throw BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Invalid foreign key "$ctx.settlementEntryId": journal entry "$entryId" does not exist.',
        );
      }
      final debtId = _reqString(a, 'debtId', ctx).trim();
      if (!targetDebtIds.contains(debtId)) {
        throw BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Invalid foreign key "$ctx.debtId": debt "$debtId" does not exist.',
        );
      }
      final allocatedCents = _reqInt(a, 'allocatedCents', ctx, min: 1);
      final settlementDate = _reqCanonicalDate(a, 'settlementDate', ctx);
      allocationCompanions.add(
        SettlementAllocationsTableCompanion.insert(
          id: id,
          settlementEntryId: entryId,
          debtId: debtId,
          allocatedCents: allocatedCents,
          settlementDate: settlementDate,
        ),
      );
    }

    // 16. SavingsGoals (Tier 2: linkedAccountId)
    final rawSavings = stateMap['savingsGoals'] != null
        ? listOf('savingsGoals')
        : legacySavingsFromGoals;
    final savingsSeenIds = <String>{};
    final savingsCompanions = <SavingsGoalsCompanion>[];
    for (var i = 0; i < rawSavings.length; i++) {
      final s = rawSavings[i];
      final ctx = 'savingsGoals[$i]';
      final id = _reqUniqueId(s, 'savingsGoals', i, savingsSeenIds);
      final title = _reqString(s, 'title', ctx, maxLength: 200).trim();
      final targetCents = _reqInt(s, 'targetCents', ctx, min: 1);
      final allocatedCents =
          _optInt(s, 'currentAllocatedCents', ctx, min: 0) ?? 0;
      final targetDate = _optCanonicalDate(s, 'targetDate', ctx);
      final rawLinkedAcc =
          _optString(s, 'linkedAccountId', ctx, allowEmpty: false);
      String? safeLinkedAcc;
      if (rawLinkedAcc != null) {
        if (targetAccountIdsWithSystem.contains(rawLinkedAcc)) {
          safeLinkedAcc = rawLinkedAcc;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_SAVINGS_ACCOUNT_CLEARED',
              message:
                  'Cleared missing linkedAccountId "$rawLinkedAcc" on savings goal "$id".',
              table: 'savingsGoals',
              recordId: id,
              field: 'linkedAccountId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      final status = _optEnum(s, 'status', _savingsStatuses, ctx) ?? 'active';
      final createdAt = _optInstantUtc(s, 'createdAt', ctx) ?? now;
      savingsCompanions.add(
        SavingsGoalsCompanion.insert(
          id: id,
          title: title,
          targetCents: targetCents,
          currentAllocatedCents: Value(allocatedCents),
          targetDate: Value(targetDate),
          linkedAccountId: Value(safeLinkedAcc),
          status: Value(status),
          createdAt: createdAt,
        ),
      );
    }

    // 17. Budgets (Tier 1: categoryId + composite unique (monthIso, categoryId))
    final rawBudgets = listOf('budgets');
    final budgetSeenIds = <String>{};
    final budgetCompositeSeen = <String, String>{
      ...existingBudgetIdsByMonthCategory,
    };
    final budgetCompanions = <BudgetsTableCompanion>[];
    for (var i = 0; i < rawBudgets.length; i++) {
      final b = rawBudgets[i];
      final ctx = 'budgets[$i]';
      final id = _reqUniqueId(b, 'budgets', i, budgetSeenIds);
      final categoryId = _reqString(b, 'categoryId', ctx).trim();
      if (!targetCategoryIds.contains(categoryId)) {
        throw BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Invalid foreign key "$ctx.categoryId": category "$categoryId" does not exist.',
        );
      }
      final monthIso = _reqMonthIso(b, 'monthIso', ctx);
      final compositeKey = '$monthIso\u0000$categoryId';
      final existingOwnerId = budgetCompositeSeen[compositeKey];
      if (existingOwnerId != null && existingOwnerId != id) {
        throw BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Duplicate budget for monthIso="$monthIso" and categoryId="$categoryId" at "$ctx".',
        );
      }
      budgetCompositeSeen[compositeKey] = id;
      final limitCents = _reqInt(b, 'limitCents', ctx, min: 1);
      final rolloverEnabled = _optBool(b, 'rolloverEnabled', ctx) ?? false;
      final createdAt = _optInstantUtc(b, 'createdAt', ctx) ?? now;
      final updatedAt = _optInstantUtc(b, 'updatedAt', ctx) ?? createdAt;
      budgetCompanions.add(
        BudgetsTableCompanion.insert(
          id: id,
          categoryId: categoryId,
          monthIso: monthIso,
          limitCents: limitCents,
          rolloverEnabled: Value(rolloverEnabled),
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
      );
    }

    // 18. RecurringRules (Tier 2: accountId, destinationAccountId, categoryId, linkedDebtId)
    final rawRules = listOf('recurringRules');
    final ruleSeenIds = <String>{};
    final ruleCompanions = <RecurringRulesTableCompanion>[];
    for (var i = 0; i < rawRules.length; i++) {
      final r = rawRules[i];
      final ctx = 'recurringRules[$i]';
      final id = _reqUniqueId(r, 'recurringRules', i, ruleSeenIds);
      final title = _reqString(r, 'title', ctx, maxLength: 200).trim();
      final ruleType = _optEnum(r, 'ruleType', _ruleTypes, ctx) ?? 'commitment';
      final amountCents = _reqInt(r, 'amountCents', ctx, min: 1);
      final frequency =
          _optEnum(r, 'frequency', _ruleFrequencies, ctx) ?? 'monthly';
      final interval = _optInt(r, 'interval', ctx, min: 1) ?? 1;
      final startDate = _reqCanonicalDate(r, 'startDate', ctx);
      final nextOccurrenceDate =
          _reqCanonicalDate(r, 'nextOccurrenceDate', ctx);
      final endDate = _optCanonicalDate(r, 'endDate', ctx);
      final rawAcc = _optString(r, 'accountId', ctx, allowEmpty: false);
      String? safeAcc;
      if (rawAcc != null) {
        if (targetAccountIdsWithSystem.contains(rawAcc)) {
          safeAcc = rawAcc;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_RULE_ACCOUNT_CLEARED',
              message:
                  'Cleared missing accountId "$rawAcc" on recurring rule "$id".',
              table: 'recurringRules',
              recordId: id,
              field: 'accountId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      final rawDestAcc =
          _optString(r, 'destinationAccountId', ctx, allowEmpty: false);
      String? safeDestAcc;
      if (rawDestAcc != null) {
        if (targetAccountIdsWithSystem.contains(rawDestAcc)) {
          safeDestAcc = rawDestAcc;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_RULE_DESTINATION_CLEARED',
              message:
                  'Cleared missing destinationAccountId "$rawDestAcc" on recurring rule "$id".',
              table: 'recurringRules',
              recordId: id,
              field: 'destinationAccountId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      final rawCat = _optString(r, 'categoryId', ctx, allowEmpty: false);
      String? safeCat;
      if (rawCat != null) {
        if (targetCategoryIds.contains(rawCat)) {
          safeCat = rawCat;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_RULE_CATEGORY_CLEARED',
              message:
                  'Cleared missing categoryId "$rawCat" on recurring rule "$id".',
              table: 'recurringRules',
              recordId: id,
              field: 'categoryId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      final rawDebt = _optString(r, 'linkedDebtId', ctx, allowEmpty: false);
      String? safeDebt;
      if (rawDebt != null) {
        if (targetDebtIds.contains(rawDebt)) {
          safeDebt = rawDebt;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_RULE_DEBT_CLEARED',
              message:
                  'Cleared missing linkedDebtId "$rawDebt" on recurring rule "$id".',
              table: 'recurringRules',
              recordId: id,
              field: 'linkedDebtId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      final isActive = _optBool(r, 'isActive', ctx) ?? true;
      final autoPost = _optBool(r, 'autoPost', ctx) ?? false;
      final createdAt = _optInstantUtc(r, 'createdAt', ctx) ?? now;
      ruleCompanions.add(
        RecurringRulesTableCompanion.insert(
          id: id,
          title: title,
          ruleType: ruleType,
          amountCents: amountCents,
          frequency: frequency,
          interval: Value(interval),
          startDate: startDate,
          nextOccurrenceDate: nextOccurrenceDate,
          endDate: Value(endDate),
          accountId: Value(safeAcc),
          destinationAccountId: Value(safeDestAcc),
          categoryId: Value(safeCat),
          linkedDebtId: Value(safeDebt),
          isActive: Value(isActive),
          autoPost: Value(autoPost),
          createdAt: createdAt,
        ),
      );
    }
    final targetRuleIds = <String>{...existingRuleIds, ...ruleSeenIds};

    // 19. FinancialCommitments (Tier 2: linkedAccountId, categoryId, linkedDebtId, settlementEntryId, recurringRuleId)
    final rawCommitments = listOf('commitments');
    final commitmentSeenIds = <String>{};
    final commitmentCompanions = <FinancialCommitmentsCompanion>[];
    for (var i = 0; i < rawCommitments.length; i++) {
      final c = rawCommitments[i];
      final ctx = 'commitments[$i]';
      final id = _reqUniqueId(c, 'commitments', i, commitmentSeenIds);
      final title = _reqString(c, 'title', ctx, maxLength: 200).trim();
      final amountCents = _reqInt(c, 'amountCents', ctx, min: 1);
      final dueDate = _reqCanonicalDate(c, 'dueDate', ctx);
      final isPaid = _optBool(c, 'isPaid', ctx) ?? false;
      final direction =
          _optEnum(c, 'direction', _commitmentDirections, ctx) ?? 'outflow';
      final legacyPaidUnverified =
          _optBool(c, 'legacyPaidUnverified', ctx) ?? false;
      final recurringRule =
          _optString(c, 'recurringRule', ctx, allowEmpty: true);

      final rawAcc = _optString(c, 'linkedAccountId', ctx, allowEmpty: false);
      String? safeAcc;
      if (rawAcc != null) {
        if (targetAccountIdsWithSystem.contains(rawAcc)) {
          safeAcc = rawAcc;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_COMMITMENT_ACCOUNT_CLEARED',
              message:
                  'Cleared missing linkedAccountId "$rawAcc" on commitment "$id".',
              table: 'commitments',
              recordId: id,
              field: 'linkedAccountId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      final rawCat = _optString(c, 'categoryId', ctx, allowEmpty: false);
      String? safeCat;
      if (rawCat != null) {
        if (targetCategoryIds.contains(rawCat)) {
          safeCat = rawCat;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_COMMITMENT_CATEGORY_CLEARED',
              message:
                  'Cleared missing categoryId "$rawCat" on commitment "$id".',
              table: 'commitments',
              recordId: id,
              field: 'categoryId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      final rawDebt = _optString(c, 'linkedDebtId', ctx, allowEmpty: false);
      String? safeDebt;
      if (rawDebt != null) {
        if (targetDebtIds.contains(rawDebt)) {
          safeDebt = rawDebt;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_COMMITMENT_DEBT_CLEARED',
              message:
                  'Cleared missing linkedDebtId "$rawDebt" on commitment "$id".',
              table: 'commitments',
              recordId: id,
              field: 'linkedDebtId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      final rawEntry =
          _optString(c, 'settlementEntryId', ctx, allowEmpty: false);
      String? safeEntry;
      if (rawEntry != null) {
        if (targetEntryIds.contains(rawEntry)) {
          safeEntry = rawEntry;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_COMMITMENT_ENTRY_CLEARED',
              message:
                  'Cleared missing settlementEntryId "$rawEntry" on commitment "$id".',
              table: 'commitments',
              recordId: id,
              field: 'settlementEntryId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      final rawRuleId =
          _optString(c, 'recurringRuleId', ctx, allowEmpty: false);
      String? safeRuleId;
      if (rawRuleId != null) {
        if (targetRuleIds.contains(rawRuleId)) {
          safeRuleId = rawRuleId;
        } else {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_RECURRING_RULE_LINK_CLEARED',
              message:
                  'Cleared missing recurringRuleId "$rawRuleId" on commitment "$id".',
              table: 'commitments',
              recordId: id,
              field: 'recurringRuleId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
        }
      }
      final createdAt = _optInstantUtc(c, 'createdAt', ctx) ?? now;
      commitmentCompanions.add(
        FinancialCommitmentsCompanion.insert(
          id: id,
          title: title,
          amountCents: amountCents,
          dueDate: dueDate,
          isPaid: Value(isPaid),
          direction: Value(direction),
          legacyPaidUnverified: Value(legacyPaidUnverified),
          recurringRule: Value(recurringRule),
          linkedAccountId: Value(safeAcc),
          categoryId: Value(safeCat),
          linkedDebtId: Value(safeDebt),
          settlementEntryId: Value(safeEntry),
          recurringRuleId: Value(safeRuleId),
          createdAt: createdAt,
        ),
      );
    }
    final targetCommitmentIds = <String>{
      ...existingCommitmentIds,
      ...commitmentSeenIds,
    };

    // 20. CommitmentSettlements (Tier 1: commitmentId, entryId)
    final rawSettlements = listOf('commitmentSettlements');
    final settlementSeenIds = <String>{};
    final settlementCompanions = <CommitmentSettlementsTableCompanion>[];
    for (var i = 0; i < rawSettlements.length; i++) {
      final s = rawSettlements[i];
      final ctx = 'commitmentSettlements[$i]';
      final id = _reqUniqueId(s, 'commitmentSettlements', i, settlementSeenIds);
      final commitmentId = _reqString(s, 'commitmentId', ctx).trim();
      if (!targetCommitmentIds.contains(commitmentId)) {
        throw BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Invalid foreign key "$ctx.commitmentId": commitment "$commitmentId" does not exist.',
        );
      }
      final entryId = _reqString(s, 'entryId', ctx).trim();
      if (!targetEntryIds.contains(entryId)) {
        throw BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Invalid foreign key "$ctx.entryId": journal entry "$entryId" does not exist.',
        );
      }
      final amountCents = _reqInt(s, 'amountCents', ctx, min: 1);
      final settledDate = _reqCanonicalDate(s, 'settledDate', ctx);
      final createdAt = _optInstantUtc(s, 'createdAt', ctx) ?? now;
      settlementCompanions.add(
        CommitmentSettlementsTableCompanion.insert(
          id: id,
          commitmentId: commitmentId,
          entryId: entryId,
          amountCents: amountCents,
          settledDate: settledDate,
          createdAt: createdAt,
        ),
      );
    }

    // 21. Reminders (Tier 3 polymorphic soft link + legacy omission handling)
    final hasExplicitReminders =
        stateMap.containsKey('reminders') && stateMap['reminders'] != null;
    final reminderSeenIds = <String>{};
    final reminderCompanions = <RemindersCompanion>[];
    if (!hasExplicitReminders) {
      diagnostics.add(
        SnapshotImportDiagnostic(
          code: 'LEGACY_REMINDERS_OMITTED',
          message: clearExisting
              ? 'Snapshot omitted reminders; existing reminders cleared on replace.'
              : 'Snapshot omitted reminders; existing reminders preserved on merge.',
          table: 'reminders',
          severity: SnapshotDiagnosticSeverity.info,
        ),
      );
    } else {
      final rawReminders = listOf('reminders');
      final targetTaskIds = <String>{...existingTaskIds, ...taskSeenIds};
      final targetEventIds = <String>{
        ...existingCalendarEventIds,
        ...eventSeenIds,
      };
      final targetNoteIds = <String>{...existingNoteIds, ...noteSeenIds};

      for (var i = 0; i < rawReminders.length; i++) {
        final r = rawReminders[i];
        final ctx = 'reminders[$i]';
        final id = _reqUniqueId(r, 'reminders', i, reminderSeenIds);
        final targetType = _reqEnum(r, 'targetType', _reminderTargetTypes, ctx);
        final String targetId;
        if (targetType == 'custom') {
          targetId = _optString(r, 'targetId', ctx, allowEmpty: false) ?? id;
        } else {
          targetId = _reqString(r, 'targetId', ctx).trim();
        }
        final rawTitle = _optString(r, 'title', ctx, allowEmpty: true)?.trim();
        final title =
            (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : null;
        final rawChannelId =
            _optString(r, 'channelId', ctx, allowEmpty: true)?.trim();
        final channelId = (rawChannelId != null && rawChannelId.isNotEmpty)
            ? rawChannelId
            : null;

        final triggerTimeUtc = _reqInstantUtc(r, 'triggerTimeUtc', ctx);
        final isActive = _optBool(r, 'isActive', ctx) ?? true;
        final createdAt = _reqInstantUtcFromKeys(
          r,
          const <String>['createdAt', 'createdAtUtc'],
          ctx,
          'createdAt',
        );

        var targetExists = true;
        switch (targetType) {
          case 'task':
            targetExists = targetTaskIds.contains(targetId);
            break;
          case 'commitment':
            targetExists = targetCommitmentIds.contains(targetId);
            break;
          case 'calendar_event':
            targetExists = targetEventIds.contains(targetId);
            break;
          case 'note':
            targetExists = targetNoteIds.contains(targetId);
            break;
          case 'custom':
            targetExists = true;
            break;
        }

        if (!targetExists) {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'ORPHANED_REMINDER_SKIPPED',
              message:
                  'Skipped dangling $targetType reminder "$id" targeting missing "$targetId".',
              table: 'reminders',
              recordId: id,
              field: 'targetId',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
          continue;
        }

        reminderCompanions.add(
          RemindersCompanion.insert(
            id: id,
            targetId: targetId,
            targetType: targetType,
            title: Value(title),
            channelId: Value(channelId),
            triggerTimeUtc: triggerTimeUtc,
            isActive: Value(isActive),
            createdAt: createdAt,
          ),
        );
      }
    }

    // 22. AppSettings (AppSettingsBackupPolicy classification + legacy omission)
    final hasExplicitAppSettings =
        stateMap.containsKey('appSettings') && stateMap['appSettings'] != null;
    final settingSeenKeys = <String>{};
    final appSettingCompanions = <AppSettingsCompanion>[];
    final replacedAppSettingKeys = <String>[];
    if (!hasExplicitAppSettings) {
      diagnostics.add(
        const SnapshotImportDiagnostic(
          code: 'LEGACY_APP_SETTINGS_OMITTED',
          message:
              'Snapshot omitted appSettings; existing user-owned application settings preserved.',
          table: 'appSettings',
          severity: SnapshotDiagnosticSeverity.info,
        ),
      );
    } else {
      final rawSettings = listOf('appSettings');
      for (var i = 0; i < rawSettings.length; i++) {
        final s = rawSettings[i];
        final ctx = 'appSettings[$i]';
        final key = _reqString(s, 'key', ctx).trim();
        final lowerKey = key.toLowerCase();
        if (!settingSeenKeys.add(lowerKey)) {
          throw BackupValidationException(
            BackupFailureKind.invalidPayload,
            'Duplicate setting key "$key" in "appSettings" at index $i.',
          );
        }
        final value = _reqString(s, 'value', ctx, allowEmpty: true);
        final updatedAt = _optInstantUtc(s, 'updatedAt', ctx) ?? now;
        final exclusionReason = AppSettingsBackupPolicy.exclusionReason(key);
        if (exclusionReason != null) {
          diagnostics.add(
            SnapshotImportDiagnostic(
              code: 'EXCLUDED_APP_SETTING_SKIPPED',
              message: exclusionReason,
              table: 'appSettings',
              recordId: key,
              field: 'key',
              severity: SnapshotDiagnosticSeverity.warning,
            ),
          );
          continue;
        }
        final existingCanonicalKey = existingAppSettingKeysByLower[lowerKey];
        if (!clearExisting &&
            existingCanonicalKey != null &&
            existingCanonicalKey != key &&
            AppSettingsBackupPolicy.isExportableUserSetting(
                existingCanonicalKey)) {
          replacedAppSettingKeys.add(existingCanonicalKey);
        }
        appSettingCompanions.add(
          AppSettingsCompanion.insert(
            key: key,
            value: value,
            updatedAt: updatedAt,
          ),
        );
      }
    }

    final restoredCounts = <String, int>{
      'categories': categoryCompanions.length,
      'accounts': accountCompanions.length,
      'parties': partyCompanions.length,
      'goals': goalCompanions.length,
      'projects': projectCompanions.length,
      'milestones': milestoneCompanions.length,
      'tasks': taskCompanions.length,
      'notes': noteCompanions.length,
      'inboxItems': inboxCompanions.length,
      'calendarEvents': eventCompanions.length,
      'transactions': transactionCompanions.length,
      'journalEntries': entryCompanions.length,
      'postings': postingCompanions.length,
      'debts': debtCompanions.length,
      'settlementAllocations': allocationCompanions.length,
      'savingsGoals': savingsCompanions.length,
      'budgets': budgetCompanions.length,
      'recurringRules': ruleCompanions.length,
      'commitments': commitmentCompanions.length,
      'commitmentSettlements': settlementCompanions.length,
      'reminders': reminderCompanions.length,
      'appSettings': appSettingCompanions.length,
    };

    return PreparedSnapshotImport(
      snapshotVersion: snapshotVersion,
      preImportDiagnostics:
          List<SnapshotImportDiagnostic>.unmodifiable(diagnostics),
      restoredRecordCounts: Map<String, int>.unmodifiable(restoredCounts),
      categories: categoryCompanions,
      accounts: accountCompanions,
      parties: partyCompanions,
      goals: goalCompanions,
      projects: projectCompanions,
      milestones: milestoneCompanions,
      tasks: taskCompanions,
      notes: noteCompanions,
      inboxItems: inboxCompanions,
      calendarEvents: eventCompanions,
      transactions: transactionCompanions,
      journalEntries: entryCompanions,
      postings: postingCompanions,
      debts: debtCompanions,
      settlementAllocations: allocationCompanions,
      savingsGoals: savingsCompanions,
      budgets: budgetCompanions,
      recurringRules: ruleCompanions,
      commitments: commitmentCompanions,
      commitmentSettlements: settlementCompanions,
      reminders: reminderCompanions,
      appSettings: appSettingCompanions,
      replacedAppSettingKeys: List<String>.unmodifiable(replacedAppSettingKeys),
      hasExplicitReminders: hasExplicitReminders,
      hasExplicitAppSettings: hasExplicitAppSettings,
      hasExplicitOpeningBalanceCents: hasExplicitOpeningBalanceCents,
      openingBalanceCents: openingBalanceCents,
      explicitIsFinanceSetupCompleted: explicitIsFinanceSetupCompleted,
      hasUserAccountsInSnapshot: hasUserAccountsInSnapshot[0],
      ledgerMigrationReportV7: ledgerMigrationReportV7,
    );
  }

  /// Verifies integrity of a reopened SQLite database handle outside the
  /// import transaction (`PRAGMA quick_check`, `PRAGMA foreign_key_check`, and
  /// `V7LedgerHardener.verifyInvariantsOnly`).
  static Future<void> verifyRestoredDatabaseInvariants(AppDatabase db) async {
    final qcRows = await db.customSelect('PRAGMA quick_check').get();
    final qcValue = qcRows.isNotEmpty && qcRows.first.data.values.isNotEmpty
        ? qcRows.first.data.values.first?.toString().trim().toLowerCase()
        : null;
    if (qcRows.length != 1 || qcValue != 'ok') {
      throw BackupValidationException(
        BackupFailureKind.databaseImportFailure,
        'Restored database failed PRAGMA quick_check ($qcValue).',
      );
    }

    final fkRows = await db.customSelect('PRAGMA foreign_key_check').get();
    if (fkRows.isNotEmpty) {
      throw BackupValidationException(
        BackupFailureKind.databaseImportFailure,
        'Restored database failed PRAGMA foreign_key_check '
        '(${fkRows.length} violation(s)).',
      );
    }

    await V7LedgerHardener.verifyInvariantsOnly(db);
  }

  /// Atomically restores or imports a snapshot inside a single Drift SQLite transaction
  /// and returns structured diagnostics & restored counts.
  Future<SnapshotImportReport> importSnapshotDetailed(
    Map<String, dynamic> stateMap, {
    bool clearExisting = true,
    PreparedSnapshotImport? prepared,
  }) async {
    final now = EthiopiaClock.nowUtc();
    final PreparedSnapshotImport plan;
    if (prepared != null) {
      plan = prepared;
    } else if (clearExisting) {
      plan = validateAndPrepareSnapshot(
        stateMap,
        fallbackTimestampUtc: now,
      );
    } else {
      // Phase A validation first (rejects malformed payloads/shapes/PKs early).
      validateCanonicalSnapshot(stateMap);
      final liveCategories = await _db.select(_db.financialCategories).get();
      final liveAccounts = await _db.select(_db.accountsTable).get();
      final liveParties = await _db.select(_db.partiesTable).get();
      final liveGoals = await _db.select(_db.goals).get();
      final liveProjects = await _db.select(_db.projects).get();
      final liveMilestones = await _db.select(_db.milestones).get();
      final liveTransactions =
          await _db.select(_db.financialTransactions).get();
      final liveEntries = await _db.select(_db.journalEntriesTable).get();
      final liveDebts = await _db.select(_db.debtsTable).get();
      final liveCommitments = await _db.select(_db.financialCommitments).get();
      final liveRules = await _db.select(_db.recurringRulesTable).get();
      final liveTasks = await _db.select(_db.tasks).get();
      final liveEvents = await _db.select(_db.calendarEvents).get();
      final liveNotes = await _db.select(_db.notes).get();
      final liveBudgets = await _db.select(_db.budgetsTable).get();
      final liveSettings = await _db.select(_db.appSettings).get();

      plan = validateAndPrepareSnapshot(
        stateMap,
        fallbackTimestampUtc: now,
        clearExisting: false,
        existingCategoryIds: {for (final c in liveCategories) c.id},
        existingAccountIds: {for (final a in liveAccounts) a.id},
        existingPartyIds: {for (final p in liveParties) p.id},
        existingGoalIds: {for (final g in liveGoals) g.id},
        existingProjectIds: {for (final p in liveProjects) p.id},
        existingMilestoneIds: {for (final m in liveMilestones) m.id},
        existingTransactionIds: {for (final t in liveTransactions) t.id},
        existingEntryIds: {for (final e in liveEntries) e.id},
        existingDebtIds: {for (final d in liveDebts) d.id},
        existingCommitmentIds: {for (final c in liveCommitments) c.id},
        existingRuleIds: {for (final r in liveRules) r.id},
        existingTaskIds: {for (final t in liveTasks) t.id},
        existingCalendarEventIds: {for (final e in liveEvents) e.id},
        existingNoteIds: {for (final n in liveNotes) n.id},
        existingBudgetIdsByMonthCategory: {
          for (final b in liveBudgets)
            '${b.monthIso}\u0000${b.categoryId}': b.id,
        },
        existingEntryIdByLegacySourceTxId: {
          for (final e in liveEntries)
            if (e.legacySourceTxId != null) e.legacySourceTxId!: e.id,
        },
        existingAppSettingKeysByLower: {
          for (final s in liveSettings)
            if (AppSettingsBackupPolicy.isExportableUserSetting(s.key))
              s.key.trim().toLowerCase(): s.key,
        },
      );
    }

    final diagnostics = List<SnapshotImportDiagnostic>.from(
      plan.preImportDiagnostics,
    );
    final warningStrings = diagnostics
        .where((d) => d.severity == SnapshotDiagnosticSeverity.warning)
        .map((d) => d.toWarningString())
        .toList();

    await _db.transaction(() async {
      if (clearExisting) {
        // Break self-referential & cross-cycle FKs before leaf-to-parent delete.
        await _db.customStatement(
          'UPDATE financial_categories SET parent_id = NULL;',
        );
        await _db.customStatement(
          'UPDATE journal_entries_table SET corrected_from_entry_id = NULL;',
        );
        await _db.customStatement(
          'UPDATE debts_table SET write_off_entry_id = NULL;',
        );

        await _db.delete(_db.commitmentSettlementsTable).go();
        await _db.delete(_db.recurringRulesTable).go();
        await _db.delete(_db.budgetsTable).go();
        await _db.delete(_db.financialCommitments).go();
        await _db.delete(_db.savingsGoals).go();
        await _db.delete(_db.settlementAllocationsTable).go();
        await _db.delete(_db.debtsTable).go();
        await _db.delete(_db.postingsTable).go();
        await _db.delete(_db.journalEntriesTable).go();
        await _db.delete(_db.financialTransactions).go();
        await _db.delete(_db.reminders).go();
        await _db.delete(_db.tasks).go();
        await _db.delete(_db.milestones).go();
        await _db.delete(_db.notes).go();
        await _db.delete(_db.projects).go();
        await _db.delete(_db.goals).go();
        await _db.delete(_db.inboxItems).go();
        await _db.delete(_db.calendarEvents).go();
        await _db.delete(_db.partiesTable).go();
        await _db.delete(_db.accountsTable).go();
        await _db.delete(_db.financialCategories).go();

        // Clear stale migration sentinel & report on clean replace.
        await (_db.delete(_db.appSettings)
              ..where((t) =>
                  t.key.equals(V6LedgerMigrator.v6MigratedSentinelKey) |
                  t.key.equals(V7LedgerHardener.v7ReportKey)))
            .go();

        // When explicit appSettings are supplied, replace user-owned settings
        // cleanly while never deleting local secret/device/sentinel keys.
        if (plan.hasExplicitAppSettings) {
          final existingSettings = await _db.select(_db.appSettings).get();
          for (final existing in existingSettings) {
            if (AppSettingsBackupPolicy.isExportableUserSetting(existing.key)) {
              await (_db.delete(_db.appSettings)
                    ..where((t) => t.key.equals(existing.key)))
                  .go();
            }
          }
        }
      }

      // 1..20. Insert normalized entities in FK dependency order.
      for (final row in plan.categories) {
        await _db.into(_db.financialCategories).insertOnConflictUpdate(row);
      }
      for (final row in plan.accounts) {
        await _db.into(_db.accountsTable).insertOnConflictUpdate(row);
      }
      // Provision system control accounts BEFORE postings/debts/rules so
      // references to acc-sys-* always satisfy SQLite foreign_keys = ON.
      await V6LedgerMigrator.ensureSystemControlAccounts(_db);

      for (final row in plan.parties) {
        await _db.into(_db.partiesTable).insertOnConflictUpdate(row);
      }
      for (final row in plan.goals) {
        await _db.into(_db.goals).insertOnConflictUpdate(row);
      }
      for (final row in plan.projects) {
        await _db.into(_db.projects).insertOnConflictUpdate(row);
      }
      for (final row in plan.milestones) {
        await _db.into(_db.milestones).insertOnConflictUpdate(row);
      }
      for (final row in plan.tasks) {
        await _db.into(_db.tasks).insertOnConflictUpdate(row);
      }
      for (final row in plan.notes) {
        await _db.into(_db.notes).insertOnConflictUpdate(row);
      }
      for (final row in plan.inboxItems) {
        await _db.into(_db.inboxItems).insertOnConflictUpdate(row);
      }
      for (final row in plan.calendarEvents) {
        await _db.into(_db.calendarEvents).insertOnConflictUpdate(row);
      }
      for (final row in plan.transactions) {
        await _db.into(_db.financialTransactions).insertOnConflictUpdate(row);
      }
      for (final row in plan.journalEntries) {
        await _db.into(_db.journalEntriesTable).insertOnConflictUpdate(row);
      }
      for (final row in plan.postings) {
        await _db.into(_db.postingsTable).insertOnConflictUpdate(row);
      }
      for (final row in plan.debts) {
        await _db.into(_db.debtsTable).insertOnConflictUpdate(row);
      }
      for (final row in plan.settlementAllocations) {
        await _db
            .into(_db.settlementAllocationsTable)
            .insertOnConflictUpdate(row);
      }
      for (final row in plan.savingsGoals) {
        await _db.into(_db.savingsGoals).insertOnConflictUpdate(row);
      }
      for (final row in plan.budgets) {
        await _db.into(_db.budgetsTable).insertOnConflictUpdate(row);
      }
      for (final row in plan.recurringRules) {
        await _db.into(_db.recurringRulesTable).insertOnConflictUpdate(row);
      }
      for (final row in plan.commitments) {
        await _db.into(_db.financialCommitments).insertOnConflictUpdate(row);
      }
      for (final row in plan.commitmentSettlements) {
        await _db
            .into(_db.commitmentSettlementsTable)
            .insertOnConflictUpdate(row);
      }
      for (final row in plan.reminders) {
        await _db.into(_db.reminders).insertOnConflictUpdate(row);
      }
      if (!clearExisting && plan.replacedAppSettingKeys.isNotEmpty) {
        await (_db.delete(_db.appSettings)
              ..where((t) => t.key.isIn(plan.replacedAppSettingKeys)))
            .go();
      }
      for (final row in plan.appSettings) {
        await _db.into(_db.appSettings).insertOnConflictUpdate(row);
      }

      // 21. Upgrade / normalize v4..v8 snapshots deterministically to v8.
      if (plan.snapshotVersion < 6) {
        await V6LedgerMigrator.migrateDataInTransaction(_db);
        final report = await V7LedgerHardener.hardenAndAuditInTransaction(
          _db,
          fromVersion: plan.snapshotVersion,
          preRebuildWarnings: warningStrings,
        );
        for (final w in report.warnings) {
          if (!warningStrings.contains(w)) {
            warningStrings.add(w);
          }
        }
      } else if (plan.snapshotVersion == 6) {
        final report = await V7LedgerHardener.hardenAndAuditInTransaction(
          _db,
          fromVersion: 6,
          preRebuildWarnings: warningStrings,
        );
        for (final w in report.warnings) {
          if (!warningStrings.contains(w)) {
            warningStrings.add(w);
          }
        }
      } else {
        await V6LedgerMigrator.ensureSystemControlAccounts(_db);
        await V7LedgerHardener.reconcileAllDebtsV7(_db);
        await V7LedgerHardener.verifyInvariantsOnly(_db);
        final savedReport = plan.ledgerMigrationReportV7;
        if (savedReport != null && savedReport.trim().isNotEmpty) {
          await _db.into(_db.appSettings).insertOnConflictUpdate(
                AppSettingsCompanion.insert(
                  key: V7LedgerHardener.v7ReportKey,
                  value: savedReport,
                  updatedAt: now,
                ),
              );
        }
      }

      // 22. Managed Finance & Sentinel Settings
      final isSetupDone = plan.explicitIsFinanceSetupCompleted ??
          plan.hasUserAccountsInSnapshot;

      await _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: AppDatabase.openingBalanceKey,
              value: '${plan.openingBalanceCents}',
              updatedAt: now,
            ),
          );
      await _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: AppDatabase.financeSetupKey,
              value: isSetupDone ? 'true' : 'false',
              updatedAt: now,
            ),
          );
      await _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: AppDatabase.seedSentinelKey,
              value: 'true',
              updatedAt: now,
            ),
          );

      // Explicit transaction-end SQLite foreign-key verification before commit.
      final fkViolations =
          await _db.customSelect('PRAGMA foreign_key_check').get();
      if (fkViolations.isNotEmpty) {
        throw BackupValidationException(
          BackupFailureKind.databaseImportFailure,
          'Foreign key constraint violation detected before commit '
          '(${fkViolations.length} row(s)).',
        );
      }
    });

    return SnapshotImportReport(
      warnings: List<String>.unmodifiable(warningStrings),
      diagnostics: List<SnapshotImportDiagnostic>.unmodifiable(diagnostics),
      restoredRecordCounts: plan.restoredRecordCounts,
    );
  }

  /// Atomically restores or imports a snapshot inside a single Drift SQLite transaction.
  Future<void> importSnapshot(Map<String, dynamic> stateMap,
      {bool clearExisting = true}) async {
    await importSnapshotDetailed(stateMap, clearExisting: clearExisting);
  }

  /// Safely purges demonstration records matching [KnownSeedIds] directly in SQLite
  /// while preserving any seed accounts still referenced by user transactions or postings.
  Future<int> purgeKnownSeedData() async {
    int purgedCount = 0;

    await _db.transaction(() async {
      purgedCount += await (_db.delete(_db.financialTransactions)
            ..where((tbl) => tbl.id.isIn(KnownSeedIds.transactions.toList())))
          .go();

      final remainingTxs = await _db.select(_db.financialTransactions).get();
      final remainingPostings = await _db.select(_db.postingsTable).get();
      final remainingCommitments =
          await _db.select(_db.financialCommitments).get();
      final remainingSettlements =
          await _db.select(_db.commitmentSettlementsTable).get();
      final remainingGoals = await _db.select(_db.savingsGoals).get();
      final remainingRules = await _db.select(_db.recurringRulesTable).get();

      for (final accId in KnownSeedIds.accounts) {
        if (SystemControlAccounts.isSystemControlId(accId)) continue;
        final usedInTx = remainingTxs.any(
          (t) => t.accountId == accId || t.destinationAccountId == accId,
        );
        final usedInPosting =
            remainingPostings.any((p) => p.accountId == accId);
        final usedInCommitment =
            remainingCommitments.any((c) => c.linkedAccountId == accId);
        final usedInGoal =
            remainingGoals.any((g) => g.linkedAccountId == accId);
        final usedInRule = remainingRules.any(
          (r) => r.accountId == accId || r.destinationAccountId == accId,
        );
        if (!usedInTx &&
            !usedInPosting &&
            !usedInCommitment &&
            !usedInGoal &&
            !usedInRule) {
          purgedCount += await (_db.delete(_db.accountsTable)
                ..where(
                  (tbl) => tbl.id.equals(accId) & tbl.isSystem.equals(false),
                ))
              .go();
        }
      }

      purgedCount += await (_db.delete(_db.tasks)
            ..where((tbl) => tbl.id.isIn(KnownSeedIds.tasks.toList())))
          .go();

      purgedCount += await (_db.delete(_db.notes)
            ..where((tbl) => tbl.id.isIn(KnownSeedIds.notes.toList())))
          .go();

      final settledCommitmentIds = {
        for (final s in remainingSettlements) s.commitmentId,
      };
      final deletableSeedCommitments = KnownSeedIds.commitments
          .where((id) => !settledCommitmentIds.contains(id))
          .toList();
      if (deletableSeedCommitments.isNotEmpty) {
        await (_db.delete(_db.reminders)
              ..where(
                (tbl) =>
                    tbl.targetType.equals('commitment') &
                    tbl.targetId.isIn(deletableSeedCommitments),
              ))
            .go();
        purgedCount += await (_db.delete(_db.financialCommitments)
              ..where((tbl) => tbl.id.isIn(deletableSeedCommitments)))
            .go();
      }

      purgedCount += await (_db.delete(_db.savingsGoals)
            ..where((tbl) => tbl.id.isIn(KnownSeedIds.savingsGoals.toList())))
          .go();

      purgedCount += await (_db.delete(_db.inboxItems)
            ..where((tbl) => tbl.id.isIn(KnownSeedIds.inboxItems.toList())))
          .go();

      purgedCount += await (_db.delete(_db.calendarEvents)
            ..where((tbl) => tbl.id.isIn(KnownSeedIds.events.toList())))
          .go();

      purgedCount += await (_db.delete(_db.projects)
            ..where((tbl) => tbl.id.isIn(KnownSeedIds.projects.toList())))
          .go();

      // Update setup state based on remaining non-system user accounts
      final accountsLeft = await (_db.select(_db.accountsTable)
            ..where((tbl) => tbl.isSystem.equals(false))
            ..limit(1))
          .get();
      await _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: AppDatabase.financeSetupKey,
              value: accountsLeft.isNotEmpty ? 'true' : 'false',
              updatedAt: EthiopiaClock.nowUtc(),
            ),
          );
    });

    return purgedCount;
  }

  static String _reqUniqueId(
    Map<String, dynamic> map,
    String table,
    int index,
    Set<String> seenIds,
  ) {
    final id = _reqString(map, 'id', '$table[$index]').trim();
    if (!seenIds.add(id)) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Duplicate primary key "$id" in "$table" at index $index.',
      );
    }
    return id;
  }

  static String _reqString(
    Map<String, dynamic> map,
    String field,
    String ctx, {
    bool allowEmpty = false,
    int? maxLength,
  }) {
    if (!map.containsKey(field) || map[field] == null) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Missing required field "$ctx.$field".',
      );
    }
    final val = map[field];
    if (val is! String) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid field "$ctx.$field": expected a string.',
      );
    }
    final trimmed = val.trim();
    if (!allowEmpty && trimmed.isEmpty) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid field "$ctx.$field": cannot be empty.',
      );
    }
    final lengthToCheck = allowEmpty ? val.length : trimmed.length;
    if (maxLength != null && lengthToCheck > maxLength) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid field "$ctx.$field": length $lengthToCheck exceeds maximum of $maxLength characters.',
      );
    }
    return val;
  }

  static String? _optString(
    Map<String, dynamic> map,
    String field,
    String ctx, {
    bool allowEmpty = false,
  }) {
    if (!map.containsKey(field) || map[field] == null) return null;
    final val = map[field];
    if (val is! String) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid field "$ctx.$field": expected a string or null.',
      );
    }
    if (!allowEmpty) {
      final trimmed = val.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return val;
  }

  static String _reqEnum(
    Map<String, dynamic> map,
    String field,
    Set<String> allowed,
    String ctx,
  ) {
    final val = _reqString(map, field, ctx).trim();
    if (!allowed.contains(val)) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid field "$ctx.$field": "$val" is not one of ${allowed.join(', ')}.',
      );
    }
    return val;
  }

  static String? _optEnum(
    Map<String, dynamic> map,
    String field,
    Set<String> allowed,
    String ctx,
  ) {
    final val = _optString(map, field, ctx, allowEmpty: false);
    if (val == null) return null;
    if (!allowed.contains(val)) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid field "$ctx.$field": "$val" is not one of ${allowed.join(', ')}.',
      );
    }
    return val;
  }

  static int _reqInt(
    Map<String, dynamic> map,
    String field,
    String ctx, {
    int? min,
  }) {
    if (!map.containsKey(field) || map[field] == null) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Missing required field "$ctx.$field".',
      );
    }
    final val = map[field];
    if (val is! int) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid field "$ctx.$field": expected an integer.',
      );
    }
    if (min != null && val < min) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid field "$ctx.$field": value $val must be >= $min.',
      );
    }
    return val;
  }

  static int? _optInt(
    Map<String, dynamic> map,
    String field,
    String ctx, {
    int? min,
  }) {
    if (!map.containsKey(field) || map[field] == null) return null;
    final val = map[field];
    if (val is! int) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid field "$ctx.$field": expected an integer or null.',
      );
    }
    if (min != null && val < min) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid field "$ctx.$field": value $val must be >= $min.',
      );
    }
    return val;
  }

  static bool? _optBool(
    Map<String, dynamic> map,
    String field,
    String ctx,
  ) {
    if (!map.containsKey(field) || map[field] == null) return null;
    final val = map[field];
    if (val is! bool) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid field "$ctx.$field": expected a boolean or null.',
      );
    }
    return val;
  }

  static DateTime _parseInstantStrict(dynamic val, String fieldPath) {
    if (val is DateTime) return val.toUtc();
    if (val is! String || val.trim().isEmpty) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid timestamp "$fieldPath": expected a non-empty ISO-8601 string.',
      );
    }
    final parsed = EthiopiaClock.tryParseInstantUtc(val);
    if (parsed == null) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid ISO-8601 timestamp "$val" for "$fieldPath".',
      );
    }
    return parsed;
  }

  static DateTime _reqInstantUtc(
    Map<String, dynamic> map,
    String field,
    String ctx,
  ) {
    if (!map.containsKey(field) || map[field] == null) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Missing required timestamp "$ctx.$field".',
      );
    }
    return _parseInstantStrict(map[field], '$ctx.$field');
  }

  static DateTime _reqInstantUtcFromKeys(
    Map<String, dynamic> map,
    List<String> keys,
    String ctx,
    String canonicalFieldName,
  ) {
    for (final key in keys) {
      if (map.containsKey(key) && map[key] != null) {
        return _parseInstantStrict(map[key], '$ctx.$key');
      }
    }
    throw BackupValidationException(
      BackupFailureKind.invalidPayload,
      'Missing required timestamp "$ctx.$canonicalFieldName".',
    );
  }

  static DateTime? _optInstantUtc(
    Map<String, dynamic> map,
    String field,
    String ctx,
  ) {
    if (!map.containsKey(field) || map[field] == null) return null;
    final raw = map[field];
    if (raw is String && raw.trim().isEmpty) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid timestamp "$ctx.$field": cannot be an empty string.',
      );
    }
    return _parseInstantStrict(raw, '$ctx.$field');
  }

  static String? _parseOptionalCanonicalDateString(
    dynamic value, {
    required String fieldName,
  }) {
    if (value == null) return null;
    if (value is CalendarDate) return value.toIsoString();
    if (value is DateTime) {
      return (value.isUtc
              ? CalendarDate.fromUtcInstantInEthiopia(value)
              : CalendarDate.fromDateComponents(value))
          .toIsoString();
    }
    if (value is! String) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid date value for "$fieldName": expected an ISO-8601 date string.',
      );
    }
    final raw = value.trim();
    if (raw.isEmpty) return null;
    try {
      return SharedDateFormatter.parseFlexibleToCalendarDate(raw).toIsoString();
    } on FormatException catch (e) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid date value "$raw" for $fieldName: ${e.message}',
      );
    } on ArgumentError catch (e) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid date value "$raw" for $fieldName: ${e.message ?? e.toString()}',
      );
    }
  }

  static String? _optCanonicalDate(
    Map<String, dynamic> map,
    String field,
    String ctx,
  ) {
    if (!map.containsKey(field) || map[field] == null) return null;
    return _parseOptionalCanonicalDateString(
      map[field],
      fieldName: '$ctx.$field',
    );
  }

  static String _reqCanonicalDate(
    Map<String, dynamic> map,
    String field,
    String ctx,
  ) {
    final parsed = _optCanonicalDate(map, field, ctx);
    if (parsed == null) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Missing required date value for "$ctx.$field".',
      );
    }
    return parsed;
  }

  static String? _optCanonicalDateFromKeys(
    Map<String, dynamic> map,
    List<String> keys,
    String ctx,
    String canonicalFieldName,
  ) {
    for (final key in keys) {
      if (map.containsKey(key) && map[key] != null) {
        return _parseOptionalCanonicalDateString(
          map[key],
          fieldName: '$ctx.$key',
        );
      }
    }
    return null;
  }

  static String _reqCanonicalDateFromKeys(
    Map<String, dynamic> map,
    List<String> keys,
    String ctx,
    String canonicalFieldName,
  ) {
    final parsed = _optCanonicalDateFromKeys(
      map,
      keys,
      ctx,
      canonicalFieldName,
    );
    if (parsed == null) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Missing required date value for "$ctx.$canonicalFieldName".',
      );
    }
    return parsed;
  }

  static String _reqMonthIso(
    Map<String, dynamic> map,
    String field,
    String ctx,
  ) {
    final val = _reqString(map, field, ctx).trim();
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(val)) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid field "$ctx.$field": expected YYYY-MM month format, got "$val".',
      );
    }
    return val;
  }

  static List<dynamic> _optJsonList(
    Map<String, dynamic> map,
    String field,
    String ctx,
  ) {
    if (!map.containsKey(field) || map[field] == null) {
      return const <dynamic>[];
    }
    final val = map[field];
    if (val is! List) {
      throw BackupValidationException(
        BackupFailureKind.invalidPayload,
        'Invalid field "$ctx.$field": expected a list.',
      );
    }
    return val;
  }

  static List<String> _optStringList(
    Map<String, dynamic> map,
    String field,
    String ctx,
  ) {
    final list = _optJsonList(map, field, ctx);
    final result = <String>[];
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is! String) {
        throw BackupValidationException(
          BackupFailureKind.invalidPayload,
          'Invalid field "$ctx.$field[$i]": expected a string.',
        );
      }
      result.add(item);
    }
    return result;
  }

  static List<T> _topologicalSortByParent<T extends Object>({
    required List<T> items,
    required String Function(T) getId,
    required String? Function(T) getParentId,
  }) {
    final byId = <String, T>{
      for (final item in items) getId(item): item,
    };
    final result = <T>[];
    final visited = <String>{};
    final visiting = <String>{};

    void visit(T item) {
      final id = getId(item);
      if (visited.contains(id) || visiting.contains(id)) return;
      visiting.add(id);
      final parentId = getParentId(item);
      if (parentId != null && parentId != id && byId.containsKey(parentId)) {
        visit(byId[parentId]!);
      }
      visiting.remove(id);
      visited.add(id);
      result.add(item);
    }

    for (final item in items) {
      visit(item);
    }
    return result;
  }

  static List<dynamic> _decodeJsonList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  static List<String> _decodeStringList(String raw) {
    return _decodeJsonList(raw).map((e) => e.toString()).toList();
  }
}
