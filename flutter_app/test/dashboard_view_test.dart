import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/calendar/calendar_controller.dart';
import 'package:personal_management_app/application/finance/finance_controller.dart';
import 'package:personal_management_app/application/inbox/inbox_controller.dart';
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/application/projects/projects_controller.dart';
import 'package:personal_management_app/application/tasks/tasks_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/domain/calendar/calendar_contracts.dart';
import 'package:personal_management_app/domain/calendar/calendar_models.dart';
import 'package:personal_management_app/domain/finance/finance_contracts.dart';
import 'package:personal_management_app/domain/inbox/inbox_contracts.dart';
import 'package:personal_management_app/domain/inbox/inbox_models.dart';
import 'package:personal_management_app/domain/notes/note_contracts.dart';
import 'package:personal_management_app/domain/notes/note_models.dart';
import 'package:personal_management_app/domain/projects/project_contracts.dart';
import 'package:personal_management_app/domain/projects/project_models.dart';
import 'package:personal_management_app/domain/projects/project_package_codec.dart';
import 'package:personal_management_app/domain/tasks/task_contracts.dart';
import 'package:personal_management_app/domain/tasks/task_models.dart';
import 'package:personal_management_app/main.dart';
import 'package:personal_management_app/ui/app_state.dart';
import 'package:personal_management_app/ui/screens/backup_view.dart';
import 'package:personal_management_app/ui/screens/dashboard_view.dart';
import 'package:personal_management_app/ui/shell/daywell_shell_routes.dart';
import 'package:personal_management_app/ui/widgets/quick_capture_dialog.dart';
import 'package:personal_management_app/ui/widgets/shared_ui_widgets.dart';

import 'support/sqlite_test_helper.dart';

class _FakeFinanceRepository implements IFinanceRepository {
  int loadCalls = 0;
  bool shouldThrow = false;
  Completer<void>? loadGate;
  bool isSetupCompleted = true;
  int openingBalanceCents = 0;

  List<AccountModel> accounts = <AccountModel>[];
  List<TransactionCategoryModel> categories = <TransactionCategoryModel>[];
  List<PartyModel> parties = <PartyModel>[];
  List<JournalEntryModel> journalEntries = <JournalEntryModel>[];
  List<PostingModel> postings = <PostingModel>[];
  List<DebtModel> debts = <DebtModel>[];
  List<SettlementAllocationModel> settlementAllocations =
      <SettlementAllocationModel>[];
  List<TransactionModel> transactions = <TransactionModel>[];
  List<CommitmentModel> commitments = <CommitmentModel>[];
  List<CommitmentSettlementModel> commitmentSettlements =
      <CommitmentSettlementModel>[];
  List<SavingsGoalModel> savingsGoals = <SavingsGoalModel>[];
  List<BudgetModel> budgets = <BudgetModel>[];
  List<RecurringRuleModel> recurringRules = <RecurringRuleModel>[];

  Future<void> _guardLoad() async {
    loadCalls++;
    if (loadGate != null && !loadGate!.isCompleted) {
      await loadGate!.future;
    }
    if (shouldThrow) {
      throw StateError('Simulated finance load failure');
    }
  }

  @override
  Future<({bool isSetupCompleted, int openingBalanceCents})>
      getFinanceSettings() async {
    await _guardLoad();
    return (
      isSetupCompleted: isSetupCompleted,
      openingBalanceCents: openingBalanceCents,
    );
  }

  @override
  Future<List<AccountModel>> getAccounts({
    bool includeArchived = false,
    bool includeSystem = false,
  }) async =>
      accounts;

  @override
  Future<List<TransactionCategoryModel>> getCategories({
    bool includeArchived = false,
  }) async =>
      categories;

  @override
  Future<List<PartyModel>> getParties({bool includeArchived = false}) async =>
      parties;

  @override
  Future<List<JournalEntryModel>> getJournalEntries({
    String? startDate,
    String? endDate,
    bool includeVoided = true,
  }) async =>
      journalEntries;

  @override
  Future<List<PostingModel>> getPostings({
    String? accountId,
    String? entryId,
    String? startDate,
    String? endDate,
  }) async =>
      postings;

  @override
  Future<List<DebtModel>> getDebts({
    DebtType? type,
    DebtStatus? status,
  }) async =>
      debts;

  @override
  Future<List<SettlementAllocationModel>> getSettlementAllocations() async =>
      settlementAllocations;

  @override
  Future<List<TransactionModel>> getTransactions({
    CalendarDate? startDate,
    CalendarDate? endDate,
  }) async =>
      transactions;

  @override
  Future<List<CommitmentModel>> getCommitments({bool? isPaid}) async =>
      commitments;

  @override
  Future<List<CommitmentSettlementModel>> getCommitmentSettlements({
    String? commitmentId,
  }) async =>
      commitmentId == null
          ? commitmentSettlements
          : commitmentSettlements
              .where((s) => s.commitmentId == commitmentId)
              .toList(growable: false);

  @override
  Future<CommitmentSettlementModel> recordCommitmentSettlement({
    required String commitmentId,
    required String accountId,
    required int amountCents,
    String? categoryId,
    CalendarDate? settledDate,
    String? note,
  }) async {
    final saved = CommitmentSettlementModel(
      id: 'cs-${commitmentSettlements.length + 1}',
      commitmentId: commitmentId,
      entryId: 'entry-cs-${commitmentSettlements.length + 1}',
      amountCents: amountCents,
      settledDate: settledDate ?? CalendarDate.today(),
    );
    commitmentSettlements = <CommitmentSettlementModel>[
      ...commitmentSettlements,
      saved,
    ];
    return saved;
  }

  @override
  Future<void> voidCommitmentSettlement({
    required String settlementId,
    required String reason,
  }) async {}

  @override
  Future<CommitmentModel> markLegacyCommitmentUnpaid(
    String commitmentId,
  ) async =>
      commitments.firstWhere((c) => c.id == commitmentId);

  @override
  Future<List<SavingsGoalModel>> getSavingsGoals({
    bool includeArchived = false,
  }) async =>
      includeArchived
          ? savingsGoals
          : savingsGoals.where((g) => !g.isArchived).toList(growable: false);

  @override
  Future<List<BudgetModel>> getBudgets({String? monthIso}) async => budgets;

  @override
  Future<BudgetModel> upsertBudget(BudgetModel budget) async => budget;

  @override
  Future<void> deleteBudget(String budgetId) async {}

  @override
  Future<List<RecurringRuleModel>> getRecurringRules({
    bool activeOnly = false,
  }) async =>
      recurringRules;

  @override
  Future<RecurringRuleModel> upsertRecurringRule(
    RecurringRuleModel rule,
  ) async =>
      rule;

  @override
  Future<RecurringRuleModel> pauseRecurringRule(String ruleId) async =>
      recurringRules.firstWhere((r) => r.id == ruleId).copyWith(
            isActive: false,
          );

  @override
  Future<RecurringRuleModel> resumeRecurringRule(
    String ruleId, {
    CalendarDate? today,
  }) async =>
      recurringRules.firstWhere((r) => r.id == ruleId).copyWith(
            isActive: true,
          );

  @override
  Future<RecurringRuleModel> skipNextOccurrence(String ruleId) async =>
      recurringRules.firstWhere((r) => r.id == ruleId);

  @override
  Future<void> deleteRecurringRule(String ruleId) async {}

  @override
  Future<int> processDueRecurringRules(
          {required CalendarDate asOfDate}) async =>
      0;

  @override
  Future<TransactionModel> recordTransaction(TransactionModel tx) async {
    transactions = <TransactionModel>[tx, ...transactions];
    return tx;
  }

  @override
  Future<void> archiveAccount(String id) async {}

  @override
  Future<void> archiveCategory(String id) async {}

  @override
  Future<void> archiveParty(String id) async {}

  @override
  Future<void> completeFinanceSetup(List<AccountModel> setupAccounts) async {
    isSetupCompleted = true;
  }

  @override
  Future<CommitmentModel> addCommitment(CommitmentModel commitment) async =>
      commitment;

  @override
  Future<CommitmentModel> updateCommitment(CommitmentModel commitment) async =>
      commitment;

  @override
  Future<CommitmentModel> linkCommitmentToEtbAccount({
    required String commitmentId,
    required String accountId,
  }) async {
    final idx = commitments.indexWhere((c) => c.id == commitmentId);
    if (idx == -1) {
      throw StateError('Commitment not found: $commitmentId');
    }
    final updated = commitments[idx].copyWith(linkedAccountId: accountId);
    commitments = List<CommitmentModel>.from(commitments)..[idx] = updated;
    return updated;
  }

  @override
  Future<void> deleteCommitment(String commitmentId) async {}

  @override
  Future<CommitmentModel> markCommitmentPaidWithPosting({
    required String commitmentId,
    required String accountId,
    String? categoryId,
    CalendarDate? paidDate,
    String? note,
  }) async =>
      CommitmentModel(
        id: commitmentId,
        title: 'Paid',
        amountCents: 0,
        dueDate: paidDate ?? CalendarDate.today(),
        isPaid: true,
      );

  @override
  Future<TransactionModel> correctTransaction({
    required String originalId,
    required int newAmountCents,
    required String newCategoryId,
    required String newCategoryName,
    required String correctionReason,
    String? newNote,
    String? newPayee,
  }) async =>
      transactions.first;

  @override
  Future<AccountModel> createAccount(AccountModel account) async => account;

  @override
  Future<TransactionCategoryModel> createCategory({
    String? id,
    required String name,
    required String type,
    String colorHex = '#1B4D3E',
    String? parentId,
    int sortOrder = 0,
    bool isDefault = false,
  }) async =>
      TransactionCategoryModel(
        id: id ?? 'cat-1',
        name: name,
        type: type,
        colorHex: colorHex,
        parentId: parentId,
        sortOrder: sortOrder,
        isDefault: isDefault,
      );

  @override
  Future<PartyModel> createParty(PartyModel party) async => party;

  @override
  Future<PartyModel> updateParty(PartyModel party) async => party;

  @override
  Future<SavingsGoalModel> createSavingsGoal(SavingsGoalModel goal) async =>
      goal;

  @override
  Future<SavingsGoalModel> updateSavingsGoal(SavingsGoalModel goal) async =>
      goal;

  @override
  Future<void> deleteSavingsGoal(String goalId) async {}

  @override
  Future<SavingsGoalModel> releaseAndArchiveSavingsGoal(String goalId) async =>
      savingsGoals.firstWhere((g) => g.id == goalId).copyWith(
            currentAllocatedCents: 0,
            status: SavingsGoalStatus.archived,
          );

  @override
  Future<SavingsGoalModel> fundSavingsGoal({
    required String goalId,
    required int deltaCents,
    String? sourceAccountId,
    CalendarDate? date,
    String? note,
  }) async =>
      SavingsGoalModel(id: goalId, title: 'Goal', targetCents: 1000);

  @override
  Future<bool> deleteAccount(String id) async => true;

  @override
  Future<bool> deleteCategory(String id) async => true;

  @override
  Future<void> deleteTransaction(String id) async {}

  @override
  Future<AccountModel?> getAccountById(String id) async => null;

  @override
  Future<FinancialSnapshot> getFinancialSnapshot({
    required int openingBalanceCents,
    required CalendarDate periodStart,
    required CalendarDate periodEnd,
    required List<int> expectedFutureIncomeCents,
  }) async =>
      FinancialSnapshot(
        openingBalanceCents: openingBalanceCents,
        totalIncomeCents: 0,
        totalExpensesCents: 0,
        recordedBalanceCents: openingBalanceCents,
        unpaidCommitmentsCents: 0,
        savingsReservedCents: 0,
        expectedFutureIncomeCents: 0,
        availableToSpendCents: openingBalanceCents,
      );

  @override
  Future<void> markCommitmentPaid(
    String commitmentId, {
    bool createExpenseTransaction = false,
  }) async {}

  @override
  Future<DebtModel> recordDebt(DebtModel debt) async => debt;

  @override
  Future<DebtModel> recordDebtWithEntry({
    required JournalEntryModel entry,
    required List<PostingModel> postings,
    required DebtModel debt,
  }) async =>
      debt;

  @override
  Future<DebtModel> writeOffDebt({
    required String debtId,
    required String reason,
    required CalendarDate date,
  }) async =>
      debts.first;

  @override
  Future<JournalEntryModel> recordJournalEntry({
    required JournalEntryModel entry,
    required List<PostingModel> postings,
  }) async =>
      entry;

  @override
  Future<JournalEntryModel> recordDirectExpense({
    required String accountId,
    required String categoryId,
    required int amountCents,
    required CalendarDate date,
    CalendarDate? movementDate,
    required String description,
    String? payee,
    String? note,
  }) async =>
      JournalEntryModel(
        id: 'entry-exp',
        entryType: EntryType.standard,
        description: description,
        occurrenceDate: date.toIsoString(),
      );

  @override
  Future<JournalEntryModel> recordDirectIncome({
    required String accountId,
    required String categoryId,
    required int amountCents,
    required CalendarDate date,
    CalendarDate? movementDate,
    required String description,
    String? payee,
    String? note,
  }) async =>
      JournalEntryModel(
        id: 'entry-inc',
        entryType: EntryType.standard,
        description: description,
        occurrenceDate: date.toIsoString(),
      );

  @override
  Future<JournalEntryModel> recordAccountTransfer({
    required String fromAccountId,
    required String toAccountId,
    required int amountCents,
    int transferFeeCents = 0,
    String? feeCategoryId,
    required CalendarDate date,
    CalendarDate? movementDate,
    required String description,
    String? note,
  }) async =>
      JournalEntryModel(
        id: 'entry-xfer',
        entryType: EntryType.transfer,
        description: description,
        occurrenceDate: date.toIsoString(),
      );

  @override
  Future<JournalEntryModel> recordSplitExpense({
    required String paidAccountId,
    required String myCategoryId,
    required int myShareCents,
    required int theirShareCents,
    required String partyId,
    required CalendarDate date,
    CalendarDate? movementDate,
    CalendarDate? dueDate,
    required String description,
    String? note,
  }) async =>
      JournalEntryModel(
        id: 'entry-split',
        entryType: EntryType.splitExpense,
        description: description,
        occurrenceDate: date.toIsoString(),
      );

  @override
  Future<JournalEntryModel> recordExpenseRefund({
    required String originalEntryId,
    required String refundAccountId,
    required int refundCents,
    required CalendarDate date,
    String? note,
  }) async =>
      JournalEntryModel(
        id: 'entry-refund',
        entryType: EntryType.standard,
        description: 'Refund',
        occurrenceDate: date.toIsoString(),
        legacySourceTxId: 'refund:$originalEntryId:entry-refund',
      );

  @override
  Future<JournalEntryModel> correctJournalEntry({
    required String originalEntryId,
    required JournalEntryModel replacementEntry,
    required List<PostingModel> replacementPostings,
    required String correctionReason,
  }) async =>
      replacementEntry;

  @override
  Future<SettlementAllocationModel> recordSettlement({
    required SettlementAllocationModel allocation,
    required JournalEntryModel settlementEntry,
    required List<PostingModel> settlementPostings,
    required DebtModel updatedDebt,
  }) async =>
      allocation;

  @override
  Future<void> restoreTransaction(TransactionModel tx) async {}

  @override
  Future<void> setFinanceSetupCompleted(bool completed) async {
    isSetupCompleted = completed;
  }

  @override
  Future<void> toggleArchiveCategory(String id) async {}

  @override
  Future<void> unarchiveAccount(String id) async {}

  @override
  Future<void> unvoidJournalEntry(String entryId) async {}

  @override
  Future<AccountModel> updateAccount(AccountModel account) async => account;

  @override
  Future<void> updateCategory(
    String id, {
    String? name,
    String? colorHex,
    String? parentId,
    bool clearParentId = false,
    int? sortOrder,
  }) async {}

  @override
  Future<void> updateSavingsAllocation(
    String goalId,
    int newAllocatedCents,
  ) async {}

  @override
  Future<AccountModel> reviseOpeningBalance({
    required String accountId,
    required int newOpeningBalanceCents,
    required String reason,
    CalendarDate? effectiveDate,
  }) async {
    final acc = accounts.firstWhere((a) => a.id == accountId);
    return acc.copyWith(openingBalanceCents: newOpeningBalanceCents);
  }

  @override
  Future<List<JournalEntryModel>> getOpeningBalanceHistory(
    String accountId,
  ) async =>
      const [];

  @override
  Future<DebtModel> voidDebtOrigin({
    required String debtId,
    required String reason,
  }) async =>
      debts.firstWhere((d) => d.id == debtId).copyWith(
            outstandingCents: 0,
            status: DebtStatus.voided,
          );

  @override
  Future<MigrationDiagnosticReport?> getLatestMigrationReport() async => null;

  @override
  Future<DebtControlAuditReport> auditDebtControlBalances() async =>
      const DebtControlAuditReport(
        receivableControlBalanceCents: 0,
        activeReceivableSumCents: 0,
        payableControlBalanceCents: 0,
        activePayableSumCents: 0,
      );

  @override
  Future<JournalEntryModel> voidJournalEntry({
    required String entryId,
    required String voidReason,
  }) async =>
      throw UnimplementedError();

  @override
  Future<String> exportFinanceOnlyJson() async =>
      '{"financeOnly":true,"exportScope":"finance_only","accounts":[],"transactions":[]}';

  @override
  Future<void> importFinanceOnlyJson(String rawJson) async {}
}

class _FakeTasksRepository implements ITasksRepository {
  int loadCalls = 0;
  bool shouldThrow = false;
  Completer<void>? loadGate;
  List<TaskEntity> tasks = <TaskEntity>[];
  List<ProjectEntity> projects = <ProjectEntity>[];
  List<MilestoneEntity> milestones = <MilestoneEntity>[];

  @override
  Future<List<TaskEntity>> getTasks({
    String? status,
    String? priority,
    String? projectId,
    bool? isOverdue,
  }) async {
    loadCalls++;
    if (loadGate != null && !loadGate!.isCompleted) {
      await loadGate!.future;
    }
    if (shouldThrow) {
      throw StateError('Simulated tasks load failure');
    }
    return List<TaskEntity>.from(tasks);
  }

  @override
  Future<void> updateTaskStatus(String id, String newStatus) async {
    tasks = tasks
        .map((TaskEntity t) => t.id == id ? t.copyWith(status: newStatus) : t)
        .toList();
  }

  @override
  Future<TaskEntity> createTask(TaskEntity task) async {
    tasks = <TaskEntity>[task, ...tasks];
    return task;
  }

  @override
  Future<ProjectEntity> createProject(ProjectEntity project) async => project;

  @override
  Future<MilestoneEntity> createMilestone(MilestoneEntity milestone) async =>
      milestone;

  @override
  Future<void> deleteMilestone(String milestoneId) async {}

  @override
  Future<void> deleteProject(String id) async {}

  @override
  Future<void> deleteTask(String id) async {}

  @override
  Future<List<MilestoneEntity>> getAllMilestones() async => milestones;

  @override
  Future<List<MilestoneEntity>> getMilestonesForProject(
    String projectId,
  ) async =>
      milestones;

  @override
  Future<ProjectEntity?> getProjectById(String id) async => null;

  @override
  Future<
      ({
        ProjectEntity project,
        List<TaskEntity> tasks,
        List<MilestoneEntity> milestones,
        int progressPercentage,
      })?> getProjectWithProgress(String projectId) async => null;

  @override
  Future<List<ProjectEntity>> getProjects({String? status}) async => projects;

  @override
  Future<TaskEntity?> getTaskById(String id) async => null;

  @override
  Future<List<TaskEntity>> getTasksForProject(String projectId) async =>
      const <TaskEntity>[];

  @override
  Future<List<DailyPlanningEntryEntity>> getDailyPlanningEntries({
    CalendarDate? planDate,
    String? taskId,
  }) async =>
      const <DailyPlanningEntryEntity>[];

  @override
  Future<DailyPlanningEntryEntity> upsertDailyPlanningEntry(
    DailyPlanningEntryEntity entry,
  ) async =>
      entry;

  @override
  Future<void> deleteDailyPlanningEntry(String id) async {}

  @override
  Future<void> deleteDailyPlanningEntriesForTask(String taskId) async {}

  @override
  Future<List<TaskReminderEntity>> getTaskReminders() async =>
      const <TaskReminderEntity>[];

  @override
  Future<TaskReminderEntity?> getTaskReminderForTask(String taskId) async =>
      null;

  @override
  Future<TaskReminderEntity> upsertTaskReminder(
    TaskReminderEntity reminder,
  ) async =>
      reminder;

  @override
  Future<void> deleteTaskReminderForTask(String taskId) async {}

  @override
  Future<void> postponeTaskDays(String id, int days) async {}

  @override
  Future<void> rescheduleTask(String id, CalendarDate? newDueDate) async {}

  @override
  Future<MilestoneEntity> updateMilestone(MilestoneEntity milestone) async =>
      milestone;

  @override
  Future<void> toggleMilestone(String milestoneId, bool isCompleted) async {}

  @override
  Future<ProjectEntity> updateProject(ProjectEntity project) async => project;

  @override
  Future<TaskEntity> updateTask(TaskEntity task) async => task;
}

class _FakeCalendarRepository implements ICalendarRepository {
  int loadCalls = 0;
  bool shouldThrow = false;
  Completer<void>? loadGate;
  List<CalendarEventEntity> events = <CalendarEventEntity>[];

  @override
  Future<List<CalendarEventEntity>> getEvents({
    String? dateIso,
    String? category,
  }) async {
    loadCalls++;
    if (loadGate != null && !loadGate!.isCompleted) {
      await loadGate!.future;
    }
    if (shouldThrow) {
      throw StateError('Simulated calendar load failure');
    }
    return List<CalendarEventEntity>.from(events);
  }

  @override
  Future<CalendarEventEntity> createEvent(CalendarEventEntity event) async {
    events = <CalendarEventEntity>[event, ...events];
    return event;
  }

  @override
  Future<void> deleteEvent(String id) async {}

  @override
  Future<CalendarEventEntity?> getEventById(String id) async => null;

  @override
  Future<CalendarEventEntity> updateEvent(CalendarEventEntity event) async =>
      event;
}

class _FakeNotesRepository implements INotesRepository {
  int loadCalls = 0;
  bool shouldThrow = false;
  Completer<void>? loadGate;
  List<NoteEntity> notes = <NoteEntity>[];

  @override
  Future<List<NoteEntity>> getNotes({
    String? category,
    String? projectId,
    String? goalId,
    bool includeArchived = false,
    bool includeTrashed = false,
  }) async {
    loadCalls++;
    if (loadGate != null && !loadGate!.isCompleted) {
      await loadGate!.future;
    }
    if (shouldThrow) {
      throw StateError('Simulated notes load failure');
    }
    return List<NoteEntity>.from(notes);
  }

  @override
  Future<NoteEntity> createNote(NoteEntity note) async {
    notes = <NoteEntity>[note, ...notes];
    return note;
  }

  @override
  Future<void> deleteNote(String id) async {}

  @override
  Future<NoteEntity?> getNoteById(String id) async => null;

  @override
  Future<List<NoteEntity>> searchNotes(String query) async => notes;

  @override
  Future<NoteEntity> updateNote(NoteEntity note) async => note;
}

class _FakeInboxRepository implements IInboxRepository {
  int loadCalls = 0;
  bool? lastIncludeProcessed;
  bool shouldThrow = false;
  Completer<void>? loadGate;
  List<InboxItemEntity> items = <InboxItemEntity>[];
  final StreamController<List<InboxItemEntity>> _stream =
      StreamController<List<InboxItemEntity>>.broadcast();
  int _seq = 0;

  @override
  Future<List<InboxItemEntity>> getAllInboxItems({
    bool includeProcessed = false,
  }) async {
    loadCalls++;
    lastIncludeProcessed = includeProcessed;
    if (loadGate != null && !loadGate!.isCompleted) {
      await loadGate!.future;
    }
    if (shouldThrow) {
      throw StateError('Simulated inbox load failure');
    }
    if (includeProcessed) return List<InboxItemEntity>.from(items);
    return items.where((InboxItemEntity i) => !i.isProcessed).toList();
  }

  @override
  Future<InboxItemEntity> captureQuickThought(
    String rawText, {
    String category = 'general',
  }) async {
    _seq++;
    final created = InboxItemEntity(
      id: 'cap-$_seq',
      rawText: rawText,
      category: category,
    );
    items = <InboxItemEntity>[created, ...items];
    return created;
  }

  @override
  Future<void> deleteItem(String id) async {}

  @override
  Future<void> markProcessed(String id) async {}

  @override
  Future<void> updateItemText(
    String id,
    String newText, {
    String? category,
  }) async {}

  @override
  Stream<List<InboxItemEntity>> watchUnprocessedItems() => _stream.stream;

  Future<void> close() => _stream.close();
}

class _FakeProjectsRepository implements IProjectsRepository {
  int loadCalls = 0;
  bool shouldThrow = false;
  Completer<void>? loadGate;
  List<ProjectEntity> projects = <ProjectEntity>[];
  List<ProjectTrackingBlockEntity> blocks = <ProjectTrackingBlockEntity>[];
  List<ProjectTrackingRecordEntity> records = <ProjectTrackingRecordEntity>[];

  @override
  Future<List<ProjectEntity>> getProjects({
    String? status,
    bool includeArchived = true,
  }) async {
    loadCalls++;
    if (loadGate != null && !loadGate!.isCompleted) {
      await loadGate!.future;
    }
    if (shouldThrow) {
      throw StateError('Simulated projects load failure');
    }
    return projects.where((ProjectEntity p) {
      if (!includeArchived && p.isArchived) return false;
      if (status != null && p.status != status) return false;
      return true;
    }).toList(growable: false);
  }

  @override
  Future<ProjectEntity?> getProjectById(String id) async {
    for (final p in projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<ProjectEntity> createProject(ProjectEntity project) async {
    projects = <ProjectEntity>[...projects, project];
    return project;
  }

  @override
  Future<ProjectEntity> updateProject(ProjectEntity project) async => project;

  @override
  Future<ProjectEntity> setProjectArchived(
    String projectId,
    bool isArchived,
  ) async =>
      projects.firstWhere((p) => p.id == projectId).copyWith(
            isArchived: isArchived,
          );

  @override
  Future<void> deleteProject(String projectId) async {}

  @override
  Future<List<ProjectTrackingBlockEntity>> getBlocksForProject(
    String projectId, {
    bool includeArchived = true,
  }) async =>
      blocks.where((b) => b.projectId == projectId).toList(growable: false);

  @override
  Future<ProjectTrackingBlockEntity> createBlock(
    ProjectTrackingBlockEntity block,
  ) async =>
      block;

  @override
  Future<ProjectTrackingBlockEntity> updateBlock(
    ProjectTrackingBlockEntity block,
  ) async =>
      block;

  @override
  Future<ProjectTrackingBlockEntity> setBlockArchived(
    String blockId,
    bool isArchived,
  ) async =>
      blocks.firstWhere((b) => b.id == blockId);

  @override
  Future<void> deleteBlock(String blockId) async {}

  @override
  Future<List<ProjectTrackingRecordEntity>> getRecordsForProject(
    String projectId, {
    String? blockId,
  }) async =>
      records.where((r) => r.projectId == projectId).toList(growable: false);

  @override
  Future<ProjectTrackingRecordEntity> createRecord(
    ProjectTrackingRecordEntity record,
  ) async =>
      record;

  @override
  Future<ProjectTrackingRecordEntity> updateRecord(
    ProjectTrackingRecordEntity record,
  ) async =>
      record;

  @override
  Future<ProjectTrackingRecordEntity> appendProgressLog(
    ProjectTrackingRecordEntity logRecord,
  ) async =>
      logRecord;

  @override
  Future<ProjectTrackingRecordEntity> appendProgressCorrection({
    required String targetLogId,
    required double correctionDelta,
    required CalendarDate recordedDate,
    required String reason,
    String? correctionId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteRecord(String recordId) async {}

  @override
  Future<ProjectProgressSummary> getProjectProgressSummary(
    String projectId, {
    CalendarDate? asOfDate,
  }) async =>
      ProjectProgressSummary(
        projectId: projectId,
        blockMetrics: const <ProjectBlockProgressMetric>[],
      );

  @override
  Future<String> exportProjectPackageJson(String projectId) async => '{}';

  @override
  Future<PreparedProjectPackageImport> importProjectPackageJson(
    String rawJson,
  ) async =>
      throw UnimplementedError();
}

class _HarnessAppStateManager extends ChangeNotifier
    implements AppStateManager {
  @override
  final FinanceController financeController;
  @override
  final TasksController tasksController;
  @override
  final ProjectsController projectsController;
  @override
  final CalendarController calendarController;
  @override
  final NotesController notesController;
  @override
  final InboxController inboxController;

  _HarnessAppStateManager({
    required _FakeFinanceRepository financeRepo,
    required _FakeTasksRepository tasksRepo,
    _FakeProjectsRepository? projectsRepo,
    required _FakeCalendarRepository calendarRepo,
    required _FakeNotesRepository notesRepo,
    required _FakeInboxRepository inboxRepo,
  })  : financeController = FinanceController(repository: financeRepo),
        tasksController = TasksController(repository: tasksRepo),
        projectsController = ProjectsController(
          repository: projectsRepo ?? _FakeProjectsRepository(),
        ),
        calendarController = CalendarController(repository: calendarRepo),
        notesController = NotesController(repository: notesRepo),
        inboxController = InboxController(repository: inboxRepo);

  void emitRootNotification() => notifyListeners();

  Future<void> loadAllControllers() async {
    await Future.wait<void>(<Future<void>>[
      financeController.loadAll(),
      tasksController.loadAll(),
      projectsController.loadAll(),
      calendarController.loadAll(),
      notesController.loadNotes(),
      inboxController.loadItems(includeProcessed: true),
    ]);
  }

  @override
  void dispose() {
    financeController.dispose();
    tasksController.dispose();
    projectsController.dispose();
    calendarController.dispose();
    notesController.dispose();
    inboxController.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrapDashboard({
  required AppStateManager state,
  ThemeData? theme,
  VoidCallback? onOpenQuickCapture,
  void Function(DaywellTabId tab)? onSelectTab,
  void Function(int index)? onNavigateTab,
  VoidCallback? onOpenBackup,
  double textScaleFactor = 1.0,
}) {
  return MaterialApp(
    theme: theme ?? DaywellTheme.light,
    home: Builder(
      builder: (BuildContext context) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScaleFactor),
          ),
          child: DashboardView(
            state: state,
            onOpenQuickCapture: onOpenQuickCapture ?? () {},
            onSelectTab: onSelectTab,
            onNavigateTab: onNavigateTab,
            onOpenBackup: onOpenBackup,
          ),
        );
      },
    ),
  );
}

DaywellSectionContainer _outerSectionContainer(
  WidgetTester tester,
  Type sectionType,
) {
  return tester.widget<DaywellSectionContainer>(
    find
        .descendant(
          of: find.byType(sectionType),
          matching: find.byType(DaywellSectionContainer),
        )
        .first,
  );
}

DaywellCard _metricTileCard(WidgetTester tester, Type tileType) {
  return tester.widget<DaywellCard>(
    find.descendant(
      of: find.byType(tileType),
      matching: find.byType(DaywellCard),
    ),
  );
}

void main() {
  configureSqliteForHostTests();

  Future<void> waitForCondition(
    WidgetTester tester,
    bool Function() predicate, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final stopwatch = Stopwatch()..start();
    while (!predicate()) {
      if (stopwatch.elapsed > timeout) {
        throw TimeoutException(
          'Timed out after ${timeout.inMilliseconds}ms waiting for condition',
        );
      }
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
  }

  Future<void> disposeTestState(
    WidgetTester tester,
    AppStateManager state,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
    var disposed = false;
    final disposeFuture = state.disposeAsync().whenComplete(() {
      disposed = true;
    });
    final stopwatch = Stopwatch()..start();
    while (!disposed && stopwatch.elapsed < const Duration(seconds: 10)) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    if (disposed) {
      await disposeFuture;
    } else {
      await tester.runAsync(
        () => disposeFuture.timeout(const Duration(seconds: 5)),
      );
    }
  }

  group('DashboardView Stage 3.8 Integration & SQLite Tests', () {
    testWidgets(
      'Renders live hydrated values across all 5 modules from SQLite and persists inline task toggle',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

        final db = AppDatabase(NativeDatabase.memory());
        final state = AppStateManager(db: db);
        await tester.runAsync(() => state.initialize());

        addTearDown(() => disposeTestState(tester, state));

        final today = CalendarDate.today();

        await tester.runAsync(() async {
          await state.financeController.completeSetup(<AccountModel>[
            AccountModel(
              id: 'acc-cash',
              name: 'Wallet Cash',
              type: AccountType.asset,
              openingBalanceCents: 150000, // 1,500.00 ETB
            ),
          ]);
          await state.financeController.addCommitment(
            CommitmentModel(
              id: 'com-rent',
              title: 'Internet Bill',
              amountCents: 45000,
              dueDate: today.addDays(2),
            ),
          );
          // ignore: deprecated_member_use_from_same_package
          await state.financeController.recordTransaction(
            TransactionModel(
              id: 'tx-coffee',
              categoryId: 'cat-groceries',
              categoryName: 'Groceries',
              amountCents: 12050,
              type: 'expense',
              transactionDate: today,
              payee: 'Merkato Market',
            ),
          );
          await state.tasksController.createTask(
            id: 'task-urgent',
            title: 'Submit tax filing',
            priority: 'urgent',
            dueDate: today,
          );
          await state.tasksController.createTask(
            id: 'task-done',
            title: 'Clean inbox',
            priority: 'low',
            dueDate: today,
          );
          await state.tasksController.toggleTaskStatus('task-done');
          await state.calendarController.createEvent(
            title: 'Clinic Checkup',
            dateIso: today.toIsoString(),
            startTime: '14:30',
            category: 'health',
          );
          await state.notesController.createNote(
            title: 'Budget Plan Note',
            content: 'Keep groceries below weekly target.',
            category: 'reference',
            isPinned: true,
          );
          await state.inboxController.captureQuickThought(
            'Buy printer paper',
            category: 'idea',
            autoTriage: false,
          );
        });

        // Apply narrow search filters in module controllers to verify Dashboard
        // does not leak module-internal filter state onto overview cards.
        state.notesController.setSearchQuery('non-matching-filter');
        state.tasksController.setSearchQuery('non-matching-filter');
        state.inboxController.setCategoryFilter('problem');

        await tester.pumpWidget(_wrapDashboard(state: state));
        await tester.pumpAndSettle();

        expect(find.text('Dashboard'), findsOneWidget);
        expect(find.text('AVAILABLE TO SPEND'), findsOneWidget);
        expect(
          find.text(
            FinancialEngine.formatBirr(
              state.financeController.state.availableToSpendCents,
            ),
          ),
          findsWidgets,
        );
        expect(find.text('Internet Bill'), findsOneWidget);
        expect(find.text('Groceries'), findsOneWidget);
        expect(find.text('Submit tax filing'), findsOneWidget);
        expect(find.text('1 / 2 done'), findsOneWidget);
        expect(find.text('Clinic Checkup'), findsOneWidget);
        expect(find.text('02:30 PM'), findsOneWidget);
        expect(find.text('Budget Plan Note'), findsOneWidget);
        expect(find.text('Buy printer paper'), findsOneWidget);

        // Toggle urgent task inline from Dashboard checkbox & verify persistence.
        final Finder checkbox = find.byType(Checkbox).first;
        await tester.ensureVisible(checkbox);
        await tester.pumpAndSettle();
        await tester.tap(checkbox);
        await waitForCondition(
          tester,
          () => state.tasksController.state.completedCount >= 2,
        );
        await tester.pumpAndSettle();

        expect(find.text('2 / 2 done'), findsOneWidget);
        expect(find.text('All active tasks are completed.'), findsOneWidget);
      },
    );
  });

  group('DashboardView Loading, Error, Preserved Data & Refresh Tests', () {
    testWidgets(
      'Displays initial loading per module, preserves populated data during reload, and isolates module failures',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

        final financeGate = Completer<void>();
        final financeRepo = _FakeFinanceRepository()..loadGate = financeGate;
        final tasksRepo = _FakeTasksRepository()
          ..tasks = <TaskEntity>[
            TaskEntity(
              id: 't-1',
              title: 'Healthy task item',
              priority: 'urgent',
              dueDate: CalendarDate.today(),
            ),
          ];
        final calendarRepo = _FakeCalendarRepository()..shouldThrow = true;
        final notesRepo = _FakeNotesRepository()
          ..notes = <NoteEntity>[
            NoteEntity(
              id: 'n-1',
              title: 'Healthy note preview',
              content: 'Visible even if another module fails',
            ),
          ];
        final inboxRepo = _FakeInboxRepository()
          ..items = <InboxItemEntity>[
            InboxItemEntity(id: 'i-1', rawText: 'Captured errand'),
          ];

        final harness = _HarnessAppStateManager(
          financeRepo: financeRepo,
          tasksRepo: tasksRepo,
          calendarRepo: calendarRepo,
          notesRepo: notesRepo,
          inboxRepo: inboxRepo,
        );
        addTearDown(harness.dispose);
        addTearDown(inboxRepo.close);

        unawaited(harness.loadAllControllers());

        await tester.pumpWidget(_wrapDashboard(state: harness));
        await tester.pump();

        // Finance is initially loading; Tasks & Notes render healthy content;
        // Calendar shows its independent section error banner with Retry.
        expect(find.text('Loading finance overview...'), findsOneWidget);
        expect(find.text('Healthy task item'), findsOneWidget);
        expect(find.text('Healthy note preview'), findsOneWidget);
        expect(find.text('Captured errand'), findsOneWidget);
        expect(find.text('Unable to load schedule'), findsOneWidget);

        // Finish Finance initial load cleanly -> Finance content renders.
        financeRepo.accounts = <AccountModel>[
          AccountModel(
            id: 'a-1',
            name: 'Bank Account',
            type: AccountType.asset,
            openingBalanceCents: 200000,
          ),
        ];
        financeRepo.commitments = <CommitmentModel>[
          CommitmentModel(
            id: 'c-1',
            title: 'Monthly Rent',
            amountCents: 50000,
            dueDate: CalendarDate.today(),
          ),
        ];
        financeGate.complete();
        await tester.pumpAndSettle();

        expect(find.text('Loading finance overview...'), findsNothing);
        expect(find.text('Monthly Rent'), findsOneWidget);

        // Trigger populated Finance refresh -> existing data stays mounted!
        final financeReloadGate = Completer<void>();
        financeRepo.loadGate = financeReloadGate;
        unawaited(harness.financeController.loadAll());
        await tester.pump();

        expect(find.text('Monthly Rent'), findsOneWidget);
        expect(find.text('Loading finance overview...'), findsNothing);

        // Refresh fails after data was already loaded -> shows inline error banner
        // + Retry ABOVE preserved data instead of replacing it!
        financeRepo.shouldThrow = true;
        financeReloadGate.complete();
        await tester.pumpAndSettle();

        expect(find.text('Unable to refresh finance overview'), findsOneWidget);
        expect(find.text('Monthly Rent'), findsOneWidget);

        // Retry Finance error and Calendar error independently -> both recover.
        financeRepo.shouldThrow = false;
        financeRepo.loadGate = null;
        calendarRepo.shouldThrow = false;
        calendarRepo.events = <CalendarEventEntity>[
          CalendarEventEntity(
            id: 'ev-1',
            title: 'Recovered Event',
            dateIso: CalendarDate.today().toIsoString(),
          ),
        ];

        final Finder retries = find.text('Retry');
        expect(retries, findsNWidgets(2));
        await tester.tap(retries.first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Retry').first);
        await tester.pumpAndSettle();

        expect(find.text('Unable to refresh finance overview'), findsNothing);
        expect(find.text('Unable to load schedule'), findsNothing);
        expect(find.text('Monthly Rent'), findsOneWidget);
        expect(find.text('Recovered Event'), findsOneWidget);
      },
    );

    testWidgets(
      'Deduplicates concurrent RefreshIndicator reloads and preserves Inbox includeProcessed=true',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(500, 800));
        addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

        final gate = Completer<void>();
        final financeRepo = _FakeFinanceRepository()..loadGate = gate;
        final tasksRepo = _FakeTasksRepository();
        final calendarRepo = _FakeCalendarRepository();
        final notesRepo = _FakeNotesRepository();
        final inboxRepo = _FakeInboxRepository();

        final harness = _HarnessAppStateManager(
          financeRepo: financeRepo,
          tasksRepo: tasksRepo,
          calendarRepo: calendarRepo,
          notesRepo: notesRepo,
          inboxRepo: inboxRepo,
        );
        addTearDown(harness.dispose);
        addTearDown(inboxRepo.close);

        await tester.pumpWidget(_wrapDashboard(state: harness));
        await tester.pump();

        final RefreshIndicator indicator =
            tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));

        // Launch two concurrent refreshes while reload is in flight.
        final Future<void> firstRefresh = indicator.onRefresh();
        final Future<void> secondRefresh = indicator.onRefresh();
        await tester.pump();

        expect(financeRepo.loadCalls, 1);
        expect(tasksRepo.loadCalls, 1);
        expect(calendarRepo.loadCalls, 1);
        expect(notesRepo.loadCalls, 1);
        expect(inboxRepo.loadCalls, 1);
        expect(inboxRepo.lastIncludeProcessed, isTrue);

        gate.complete();
        await Future.wait<void>(<Future<void>>[firstRefresh, secondRefresh]);
        await tester.pumpAndSettle();

        // Subsequent refresh after completion starts a fresh cycle.
        financeRepo.loadGate = null;
        await indicator.onRefresh();
        expect(financeRepo.loadCalls, 2);
        expect(inboxRepo.loadCalls, 2);
        expect(inboxRepo.lastIncludeProcessed, isTrue);
      },
    );

    testWidgets(
      'Renders empty states for all modules and Finance incomplete-setup notice banner',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

        final financeRepo = _FakeFinanceRepository()..isSetupCompleted = false;
        final tasksRepo = _FakeTasksRepository();
        final calendarRepo = _FakeCalendarRepository();
        final notesRepo = _FakeNotesRepository();
        final inboxRepo = _FakeInboxRepository();

        final harness = _HarnessAppStateManager(
          financeRepo: financeRepo,
          tasksRepo: tasksRepo,
          calendarRepo: calendarRepo,
          notesRepo: notesRepo,
          inboxRepo: inboxRepo,
        );
        addTearDown(harness.dispose);
        addTearDown(inboxRepo.close);

        await harness.loadAllControllers();
        await tester.pumpWidget(_wrapDashboard(state: harness));
        await tester.pumpAndSettle();

        expect(find.text('Finance setup incomplete'), findsOneWidget);
        expect(
            find.text('No commitments or recent transactions'), findsOneWidget);
        expect(find.text('No tasks recorded yet'), findsOneWidget);
        expect(find.text('No calendar events stored'), findsOneWidget);
        expect(find.text('No active notes yet'), findsOneWidget);
        expect(find.text('Inbox is clear'), findsOneWidget);
      },
    );
  });

  group('DashboardView Rebuild Isolation Tests', () {
    testWidgets(
      'Rebuilds only the affected section and metric tile when an individual controller notifies',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

        final financeRepo = _FakeFinanceRepository()
          ..accounts = <AccountModel>[
            AccountModel(
              id: 'acc-1',
              name: 'Cash',
              type: AccountType.asset,
              openingBalanceCents: 100000,
            ),
          ];
        final tasksRepo = _FakeTasksRepository()
          ..tasks = <TaskEntity>[
            TaskEntity(id: 't-1', title: 'Task A', priority: 'urgent'),
          ];
        final calendarRepo = _FakeCalendarRepository()
          ..events = <CalendarEventEntity>[
            CalendarEventEntity(
              id: 'e-1',
              title: 'Event A',
              dateIso: CalendarDate.today().toIsoString(),
            ),
          ];
        final notesRepo = _FakeNotesRepository()
          ..notes = <NoteEntity>[
            NoteEntity(id: 'n-1', title: 'Note A', content: 'Body A'),
          ];
        final inboxRepo = _FakeInboxRepository()
          ..items = <InboxItemEntity>[
            InboxItemEntity(id: 'i-1', rawText: 'Capture A'),
          ];

        final harness = _HarnessAppStateManager(
          financeRepo: financeRepo,
          tasksRepo: tasksRepo,
          calendarRepo: calendarRepo,
          notesRepo: notesRepo,
          inboxRepo: inboxRepo,
        );
        addTearDown(harness.dispose);
        addTearDown(inboxRepo.close);

        await harness.loadAllControllers();
        await tester.pumpWidget(_wrapDashboard(state: harness));
        await tester.pumpAndSettle();

        // Snapshot exact Widget instances inside every ListenableBuilder.
        var financeBefore =
            _outerSectionContainer(tester, DashboardFinanceSection);
        var tasksBefore = _outerSectionContainer(tester, DashboardTasksSection);
        var calendarBefore =
            _outerSectionContainer(tester, DashboardCalendarSection);
        var notesBefore = _outerSectionContainer(tester, DashboardNotesSection);
        var inboxBefore = _outerSectionContainer(tester, DashboardInboxSection);

        var tasksTileBefore =
            _metricTileCard(tester, DashboardActiveTasksMetricTile);
        var financeTileBefore =
            _metricTileCard(tester, DashboardCommitmentsMetricTile);
        var notesTileBefore = _metricTileCard(tester, DashboardNotesMetricTile);

        // 0. Root AppStateManager notification rebuilds ZERO Dashboard sections.
        harness.emitRootNotification();
        await tester.pump();
        expect(
          identical(
            financeBefore,
            _outerSectionContainer(tester, DashboardFinanceSection),
          ),
          isTrue,
        );
        expect(
          identical(
            tasksBefore,
            _outerSectionContainer(tester, DashboardTasksSection),
          ),
          isTrue,
        );
        expect(
          identical(
            calendarBefore,
            _outerSectionContainer(tester, DashboardCalendarSection),
          ),
          isTrue,
        );
        expect(
          identical(
            notesBefore,
            _outerSectionContainer(tester, DashboardNotesSection),
          ),
          isTrue,
        );
        expect(
          identical(
            inboxBefore,
            _outerSectionContainer(tester, DashboardInboxSection),
          ),
          isTrue,
        );

        // 1. Mutate ONLY TasksController -> only Tasks section & Active Tasks tile rebuild.
        await harness.tasksController.toggleTaskStatus('t-1');
        await tester.pump();

        expect(
          identical(
            tasksBefore,
            _outerSectionContainer(tester, DashboardTasksSection),
          ),
          isFalse,
        );
        expect(
          identical(
            tasksTileBefore,
            _metricTileCard(tester, DashboardActiveTasksMetricTile),
          ),
          isFalse,
        );
        expect(
          identical(
            financeBefore,
            _outerSectionContainer(tester, DashboardFinanceSection),
          ),
          isTrue,
        );
        expect(
          identical(
            financeTileBefore,
            _metricTileCard(tester, DashboardCommitmentsMetricTile),
          ),
          isTrue,
        );
        expect(
          identical(
            calendarBefore,
            _outerSectionContainer(tester, DashboardCalendarSection),
          ),
          isTrue,
        );
        expect(
          identical(
            notesBefore,
            _outerSectionContainer(tester, DashboardNotesSection),
          ),
          isTrue,
        );
        expect(
          identical(
            notesTileBefore,
            _metricTileCard(tester, DashboardNotesMetricTile),
          ),
          isTrue,
        );
        expect(
          identical(
            inboxBefore,
            _outerSectionContainer(tester, DashboardInboxSection),
          ),
          isTrue,
        );

        tasksBefore = _outerSectionContainer(tester, DashboardTasksSection);
        tasksTileBefore =
            _metricTileCard(tester, DashboardActiveTasksMetricTile);

        // 2. Mutate ONLY FinanceController -> only Finance section & Commitments tile rebuild.
        // ignore: deprecated_member_use_from_same_package
        await harness.financeController.recordTransaction(
          TransactionModel(
            id: 'tx-new',
            categoryId: 'cat-1',
            categoryName: 'Transport',
            amountCents: 2500,
            type: 'expense',
            transactionDate: CalendarDate.today(),
          ),
        );
        await tester.pump();

        expect(
          identical(
            financeBefore,
            _outerSectionContainer(tester, DashboardFinanceSection),
          ),
          isFalse,
        );
        expect(
          identical(
            financeTileBefore,
            _metricTileCard(tester, DashboardCommitmentsMetricTile),
          ),
          isFalse,
        );
        expect(
          identical(
            tasksBefore,
            _outerSectionContainer(tester, DashboardTasksSection),
          ),
          isTrue,
        );
        expect(
          identical(
            calendarBefore,
            _outerSectionContainer(tester, DashboardCalendarSection),
          ),
          isTrue,
        );
        expect(
          identical(
            notesBefore,
            _outerSectionContainer(tester, DashboardNotesSection),
          ),
          isTrue,
        );
        expect(
          identical(
            inboxBefore,
            _outerSectionContainer(tester, DashboardInboxSection),
          ),
          isTrue,
        );

        financeBefore = _outerSectionContainer(tester, DashboardFinanceSection);
        financeTileBefore =
            _metricTileCard(tester, DashboardCommitmentsMetricTile);

        // 3. Mutate ONLY NotesController -> only Notes section & Notes tile rebuild.
        await harness.notesController.createNote(
          title: 'New Note',
          content: 'Isolation check',
        );
        await tester.pump();

        expect(
          identical(
            notesBefore,
            _outerSectionContainer(tester, DashboardNotesSection),
          ),
          isFalse,
        );
        expect(
          identical(
            notesTileBefore,
            _metricTileCard(tester, DashboardNotesMetricTile),
          ),
          isFalse,
        );
        expect(
          identical(
            financeBefore,
            _outerSectionContainer(tester, DashboardFinanceSection),
          ),
          isTrue,
        );
        expect(
          identical(
            tasksBefore,
            _outerSectionContainer(tester, DashboardTasksSection),
          ),
          isTrue,
        );
        expect(
          identical(
            calendarBefore,
            _outerSectionContainer(tester, DashboardCalendarSection),
          ),
          isTrue,
        );
        expect(
          identical(
            inboxBefore,
            _outerSectionContainer(tester, DashboardInboxSection),
          ),
          isTrue,
        );

        notesBefore = _outerSectionContainer(tester, DashboardNotesSection);
        notesTileBefore = _metricTileCard(tester, DashboardNotesMetricTile);

        // 4. Mutate ONLY CalendarController -> only Calendar section rebuilds.
        await harness.calendarController.createEvent(
          title: 'Added Meeting',
          dateIso: CalendarDate.today().toIsoString(),
        );
        await tester.pump();

        expect(
          identical(
            calendarBefore,
            _outerSectionContainer(tester, DashboardCalendarSection),
          ),
          isFalse,
        );
        expect(
          identical(
            financeBefore,
            _outerSectionContainer(tester, DashboardFinanceSection),
          ),
          isTrue,
        );
        expect(
          identical(
            tasksBefore,
            _outerSectionContainer(tester, DashboardTasksSection),
          ),
          isTrue,
        );
        expect(
          identical(
            notesBefore,
            _outerSectionContainer(tester, DashboardNotesSection),
          ),
          isTrue,
        );
        expect(
          identical(
            inboxBefore,
            _outerSectionContainer(tester, DashboardInboxSection),
          ),
          isTrue,
        );

        calendarBefore =
            _outerSectionContainer(tester, DashboardCalendarSection);

        // 5. Mutate ONLY InboxController (autoTriage: false) -> only Inbox section rebuilds.
        await harness.inboxController.captureQuickThought(
          'Isolated thought',
          autoTriage: false,
        );
        await tester.pump();

        expect(
          identical(
            inboxBefore,
            _outerSectionContainer(tester, DashboardInboxSection),
          ),
          isFalse,
        );
        expect(
          identical(
            financeBefore,
            _outerSectionContainer(tester, DashboardFinanceSection),
          ),
          isTrue,
        );
        expect(
          identical(
            tasksBefore,
            _outerSectionContainer(tester, DashboardTasksSection),
          ),
          isTrue,
        );
        expect(
          identical(
            calendarBefore,
            _outerSectionContainer(tester, DashboardCalendarSection),
          ),
          isTrue,
        );
        expect(
          identical(
            notesBefore,
            _outerSectionContainer(tester, DashboardNotesSection),
          ),
          isTrue,
        );
      },
    );
  });

  group('DashboardView Navigation, Themes & Responsive Layout Stress Tests',
      () {
    testWidgets(
      'Routes all Dashboard navigation, Quick Capture, Backup callbacks and shell flows',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

        final inboxRepo = _FakeInboxRepository();
        final harness = _HarnessAppStateManager(
          financeRepo: _FakeFinanceRepository(),
          tasksRepo: _FakeTasksRepository(),
          calendarRepo: _FakeCalendarRepository(),
          notesRepo: _FakeNotesRepository(),
          inboxRepo: inboxRepo,
        );
        addTearDown(harness.dispose);
        addTearDown(inboxRepo.close);
        await harness.loadAllControllers();

        final selectedTabs = <DaywellTabId>[];
        var quickCaptureCount = 0;
        var backupCount = 0;

        await tester.pumpWidget(
          _wrapDashboard(
            state: harness,
            onSelectTab: selectedTabs.add,
            onOpenQuickCapture: () => quickCaptureCount++,
            onOpenBackup: () => backupCount++,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('1-Tap Quick Capture'));
        await tester.tap(find.byTooltip('Encrypted Backup'));
        await tester.tap(find.text('Active Tasks'));
        await tester.tap(find.text('Commitments'));
        await tester.tap(find.text('Notes'));
        await tester.tap(find.text('Open Tasks').first);
        await tester.tap(find.text('Open Calendar').first);
        await tester.tap(find.text('Open Notes').first);
        await tester.tap(find.text('Open Finance').first);
        await tester.tap(find.text('Capture <3s'));

        for (final String sectionAction in const <String>[
          'Manage',
          'View All',
          'Calendar',
          'All Notes',
          'Review Tasks',
        ]) {
          final Finder finder = find.text(sectionAction);
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
        }

        expect(quickCaptureCount, 2);
        expect(backupCount, 1);
        expect(selectedTabs, <DaywellTabId>[
          DaywellTabId.tasks,
          DaywellTabId.finance,
          DaywellTabId.notes,
          DaywellTabId.tasks,
          DaywellTabId.calendar,
          DaywellTabId.notes,
          DaywellTabId.finance,
          DaywellTabId.finance,
          DaywellTabId.tasks,
          DaywellTabId.calendar,
          DaywellTabId.notes,
          DaywellTabId.tasks,
        ]);

        // Full DaywellApp shell integration smoke check for Quick Capture + Backup.
        final db = AppDatabase(NativeDatabase.memory());
        final appState = AppStateManager(db: db);
        await tester.runAsync(() => appState.initialize());
        addTearDown(() => disposeTestState(tester, appState));

        await tester.pumpWidget(DaywellApp(stateManager: appState));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('1-Tap Quick Capture'));
        await tester.pumpAndSettle();
        expect(find.byType(QuickCaptureDialog), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Encrypted Backup'));
        await tester.pumpAndSettle();
        expect(find.byType(BackupView), findsOneWidget);
      },
    );

    testWidgets(
      'Renders under Light and Dark themes without exceptions',
      (WidgetTester tester) async {
        final harness = _HarnessAppStateManager(
          financeRepo: _FakeFinanceRepository()
            ..accounts = <AccountModel>[
              AccountModel(
                id: 'a-1',
                name: 'Cash',
                type: AccountType.asset,
                openingBalanceCents: 75000,
              ),
            ],
          tasksRepo: _FakeTasksRepository()
            ..tasks = <TaskEntity>[
              TaskEntity(id: 't-1', title: 'Review budget', priority: 'high'),
            ],
          calendarRepo: _FakeCalendarRepository(),
          notesRepo: _FakeNotesRepository(),
          inboxRepo: _FakeInboxRepository(),
        );
        addTearDown(harness.dispose);
        await harness.loadAllControllers();

        for (final ThemeData theme in <ThemeData>[
          DaywellTheme.light,
          DaywellTheme.dark,
        ]) {
          await tester.pumpWidget(_wrapDashboard(state: harness, theme: theme));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('AVAILABLE TO SPEND'), findsOneWidget);
          expect(find.text('Review budget'), findsOneWidget);
        }
      },
    );

    testWidgets(
      'Switches single-column (<720dp) vs two-column (>=720dp) cleanly and avoids overflow at 320dp + 2.0x textScale',
      (WidgetTester tester) async {
        addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

        final today = CalendarDate.today();
        final financeRepo = _FakeFinanceRepository()
          ..accounts = <AccountModel>[
            AccountModel(
              id: 'a-1',
              name: 'Primary Commercial Bank Account Ethiopia',
              type: AccountType.asset,
              openingBalanceCents: 9500000,
            ),
          ]
          ..commitments = <CommitmentModel>[
            CommitmentModel(
              id: 'c-1',
              title:
                  'Very long monthly housing lease commitment payment reminder title',
              amountCents: 1200000,
              dueDate: today.addDays(3),
            ),
          ]
          ..transactions = <TransactionModel>[
            TransactionModel(
              id: 'tx-1',
              categoryId: 'cat-food',
              categoryName: 'Household Supplies & Groceries',
              amountCents: 48550,
              type: 'expense',
              transactionDate: today,
              payee: 'Addis Ababa Central Market Cooperative',
            ),
          ];
        final tasksRepo = _FakeTasksRepository()
          ..tasks = <TaskEntity>[
            TaskEntity(
              id: 't-1',
              title:
                  'Complete quarterly financial audit reconciliation and archive receipts',
              priority: 'urgent',
              dueDate: today.addDays(-1),
            ),
          ];
        final calendarRepo = _FakeCalendarRepository()
          ..events = <CalendarEventEntity>[
            CalendarEventEntity(
              id: 'e-1',
              title: 'Quarterly Planning & Architecture Review Meeting',
              dateIso: today.toIsoString(),
              startTime: '09:30',
              category: 'work',
            ),
          ];
        final notesRepo = _FakeNotesRepository()
          ..notes = <NoteEntity>[
            NoteEntity(
              id: 'n-1',
              title: 'Bilingual Note / ማስታወሻ ረጅም ርዕስ ለሙከራ',
              content: 'Long offline note body snippet for layout wrapping.',
              category: 'reflection',
              isPinned: true,
            ),
          ];
        final inboxRepo = _FakeInboxRepository()
          ..items = <InboxItemEntity>[
            InboxItemEntity(
              id: 'i-1',
              rawText:
                  'Captured long voice transcript or shared link text to verify multi-line wrapping',
              category: 'decision',
            ),
          ];

        final harness = _HarnessAppStateManager(
          financeRepo: financeRepo,
          tasksRepo: tasksRepo,
          calendarRepo: calendarRepo,
          notesRepo: notesRepo,
          inboxRepo: inboxRepo,
        );
        addTearDown(harness.dispose);
        addTearDown(inboxRepo.close);
        await harness.loadAllControllers();

        Future<void> scrollToFinanceTasksSeam() async {
          final Finder scrollableFinder = find.byType(Scrollable).first;
          final ScrollPosition position =
              tester.state<ScrollableState>(scrollableFinder).position;
          for (int i = 0; i < 100; i++) {
            final bool hasFinance =
                find.byType(DashboardFinanceSection).evaluate().isNotEmpty;
            final bool hasTasks =
                find.byType(DashboardTasksSection).evaluate().isNotEmpty;
            if (hasFinance && hasTasks) {
              final double tasksTop =
                  tester.getTopLeft(find.byType(DashboardTasksSection)).dy;
              final double financeBottom =
                  tester.getBottomLeft(find.byType(DashboardFinanceSection)).dy;
              if (tasksTop <= 540.0 && financeBottom >= 80.0) {
                break;
              }
              if (tasksTop > 540.0 &&
                  position.pixels < position.maxScrollExtent) {
                await tester.drag(scrollableFinder, const Offset(0, -100.0));
                await tester.pump();
                continue;
              }
              if (financeBottom < 80.0 &&
                  position.pixels > position.minScrollExtent) {
                await tester.drag(scrollableFinder, const Offset(0, 100.0));
                await tester.pump();
                continue;
              }
              break;
            }
            if (!hasTasks && position.pixels < position.maxScrollExtent) {
              await tester.drag(scrollableFinder, const Offset(0, -100.0));
            } else if (!hasFinance &&
                position.pixels > position.minScrollExtent) {
              await tester.drag(scrollableFinder, const Offset(0, 100.0));
            } else {
              break;
            }
            await tester.pump();
          }
          await tester.pumpAndSettle();
        }

        // 1. Narrow phone (320dp) + 2.0x text scaling -> single column, zero overflow
        await tester.binding.setSurfaceSize(const Size(320, 640));
        await tester.pumpWidget(
          _wrapDashboard(state: harness, textScaleFactor: 2.0),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await scrollToFinanceTasksSeam();
        expect(tester.takeException(), isNull);
        expect(find.byType(DashboardFinanceSection), findsOneWidget);
        expect(find.byType(DashboardTasksSection), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(DashboardTasksSection)).dy,
          greaterThan(
            tester.getBottomLeft(find.byType(DashboardFinanceSection)).dy - 1.0,
          ),
        );

        for (final Type sectionType in const <Type>[
          DashboardCalendarSection,
          DashboardNotesSection,
          DashboardInboxSection,
        ]) {
          await tester.scrollUntilVisible(
            find.byType(sectionType),
            240.0,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        // 2. Just below breakpoint (719dp) -> single column stacked vertically
        await tester.binding.setSurfaceSize(const Size(719, 900));
        await tester.pumpWidget(_wrapDashboard(state: harness));
        await tester.pumpAndSettle();
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0.0);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await scrollToFinanceTasksSeam();
        expect(tester.takeException(), isNull);
        expect(find.byType(DashboardFinanceSection), findsOneWidget);
        expect(find.byType(DashboardTasksSection), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(DashboardTasksSection)).dy,
          greaterThan(
            tester.getBottomLeft(find.byType(DashboardFinanceSection)).dy - 1.0,
          ),
        );

        // 3. At breakpoint (720dp) -> two-column Row side-by-side
        await tester.binding.setSurfaceSize(const Size(720, 900));
        await tester.pumpWidget(_wrapDashboard(state: harness));
        await tester.pumpAndSettle();
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0.0);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(DashboardFinanceSection), findsOneWidget);
        expect(find.byType(DashboardTasksSection), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(DashboardTasksSection)).dx,
          greaterThan(
            tester.getTopRight(find.byType(DashboardFinanceSection)).dx - 1.0,
          ),
        );

        // 4. Wide desktop/tablet (1024dp) + 1.6x text scale -> zero overflow
        await tester.binding.setSurfaceSize(const Size(1024, 900));
        await tester.pumpWidget(
          _wrapDashboard(state: harness, textScaleFactor: 1.6),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
