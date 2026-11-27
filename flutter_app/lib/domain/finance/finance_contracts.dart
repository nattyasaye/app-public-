import '../../core/date/shared_date.dart';
import 'double_entry_engine.dart';
import 'financial_engine.dart';
import 'finance_models.dart';
import 'finance_sms_inbox_scanner.dart';
import 'finance_sms_models.dart';
import 'finance_sms_parsers.dart';

export 'double_entry_engine.dart';
export 'financial_engine.dart';
export 'finance_models.dart';
export 'finance_sms_inbox_scanner.dart';
export 'finance_sms_models.dart';
export 'finance_sms_parsers.dart';

/// Domain contract for Account persistence and lifecycle management.
abstract class IAccountRepositoryContract {
  Future<List<AccountModel>> getAccounts({
    bool includeArchived = false,
    bool includeSystem = false,
  });
  Future<AccountModel?> getAccountById(String id);
  Future<AccountModel> createAccount(AccountModel account);
  Future<AccountModel> updateAccount(AccountModel account);
  Future<AccountModel> reviseOpeningBalance({
    required String accountId,
    required int newOpeningBalanceCents,
    required String reason,
    CalendarDate? effectiveDate,
  });
  Future<List<JournalEntryModel>> getOpeningBalanceHistory(String accountId);
  Future<void> archiveAccount(String id);
  Future<void> unarchiveAccount(String id);
  Future<bool> deleteAccount(String id);
}

/// Domain contract for Category persistence, hierarchy, and budgeting rules.
abstract class ICategoryRepositoryContract {
  Future<List<TransactionCategoryModel>> getCategories({
    bool includeArchived = false,
  });
  Future<TransactionCategoryModel> createCategory({
    String? id,
    required String name,
    required String type, // 'income' | 'expense'
    String colorHex = '#1B4D3E',
    String? parentId,
    int sortOrder = 0,
    bool isDefault = false,
  });
  Future<void> updateCategory(
    String id, {
    String? name,
    String? colorHex,
    String? parentId,
    bool clearParentId = false,
    int? sortOrder,
  });
  Future<void> toggleArchiveCategory(String id);
  Future<void> archiveCategory(String id);
  Future<bool> deleteCategory(String id);
}

/// Domain contract for Double-Entry Journal Entries, Ledger Postings,
/// and Cashflow Transactions.
abstract class ITransactionRepositoryContract {
  Future<List<JournalEntryModel>> getJournalEntries({
    String? startDate,
    String? endDate,
    bool includeVoided = true,
  });

  Future<List<PostingModel>> getPostings({
    String? accountId,
    String? entryId,
    String? startDate,
    String? endDate,
  });

  /// Atomically records a balanced journal entry and its postings.
  Future<JournalEntryModel> recordJournalEntry({
    required JournalEntryModel entry,
    required List<PostingModel> postings,
  });

  /// Atomically records a balanced direct expense on the ledger.
  Future<JournalEntryModel> recordDirectExpense({
    required String accountId,
    required String categoryId,
    required int amountCents,
    int feeCents = 0,
    String? feeCategoryId,
    required CalendarDate date,
    CalendarDate? movementDate,
    required String description,
    String? payee,
    String? note,
  });

  /// Atomically records a balanced direct income on the ledger.
  Future<JournalEntryModel> recordDirectIncome({
    required String accountId,
    required String categoryId,
    required int amountCents,
    required CalendarDate date,
    CalendarDate? movementDate,
    required String description,
    String? payee,
    String? note,
  });

  /// Atomically records a transfer (with optional fee) on the ledger.
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
  });

  /// Atomically records a split expense with optional counterparty receivable.
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
  });

  /// Atomically records a full or partial refund for an active direct ETB expense.
  Future<JournalEntryModel> recordExpenseRefund({
    required String originalEntryId,
    required String refundAccountId,
    required int refundCents,
    required CalendarDate date,
    String? note,
  });

  /// Atomically voids the original journal entry and records a replacement.
  Future<JournalEntryModel> correctJournalEntry({
    required String originalEntryId,
    required JournalEntryModel replacementEntry,
    required List<PostingModel> replacementPostings,
    required String correctionReason,
  });

  /// Voids a journal entry and recalculates affected debts and commitments atomically.
  Future<JournalEntryModel> voidJournalEntry({
    required String entryId,
    required String voidReason,
  });

  /// Reverses a void marker and recalculates affected debts and commitments atomically.
  Future<void> unvoidJournalEntry(String entryId);

  /// Read-only legacy archive accessor during migration stabilization.
  Future<List<TransactionModel>> getTransactions({
    CalendarDate? startDate,
    CalendarDate? endDate,
  });

  @Deprecated('Use double-entry ledger methods instead.')
  Future<TransactionModel> recordTransaction(TransactionModel tx);

  @Deprecated('Use correctJournalEntry instead.')
  Future<TransactionModel> correctTransaction({
    required String originalId,
    required int newAmountCents,
    required String newCategoryId,
    required String newCategoryName,
    required String correctionReason,
    String? newNote,
    String? newPayee,
  });

  @Deprecated('Use voidJournalEntry instead.')
  Future<void> deleteTransaction(String id);

  @Deprecated('Use unvoidJournalEntry instead.')
  Future<void> restoreTransaction(TransactionModel tx);
}

/// Domain contract for Debt (Receivables & Payables), Settlement Allocations,
/// Financial Commitments & Installment Settlements, and Savings Goals.
abstract class IDebtRepositoryContract {
  Future<List<DebtModel>> getDebts({DebtType? type, DebtStatus? status});
  Future<List<PartyModel>> getParties({bool includeArchived = false});
  Future<PartyModel> createParty(PartyModel party);
  Future<PartyModel> updateParty(PartyModel party);
  Future<void> archiveParty(String id);
  Future<List<SettlementAllocationModel>> getSettlementAllocations();

  /// Records a new debt issuance linked to a journal entry.
  Future<DebtModel> recordDebt(DebtModel debt);

  /// Atomically issues a debt alongside its origin balanced journal entry.
  Future<DebtModel> recordDebtWithEntry({
    required JournalEntryModel entry,
    required List<PostingModel> postings,
    required DebtModel debt,
  });

  /// Atomically records a debt settlement allocation and updates outstanding balance.
  Future<SettlementAllocationModel> recordSettlement({
    required SettlementAllocationModel allocation,
    required JournalEntryModel settlementEntry,
    required List<PostingModel> settlementPostings,
    required DebtModel updatedDebt,
  });

  /// Writes off remaining active debt principal with a balanced write-off entry.
  Future<DebtModel> writeOffDebt({
    required String debtId,
    required String reason,
    required CalendarDate date,
  });

  /// Voids a debt's origin entry when no active/partial settlements or write-offs block it.
  Future<DebtModel> voidDebtOrigin({
    required String debtId,
    required String reason,
  });

  /// Commitments & Partial Settlements
  Future<List<CommitmentModel>> getCommitments({bool? isPaid});
  Future<List<CommitmentSettlementModel>> getCommitmentSettlements({
    String? commitmentId,
  });
  Future<CommitmentModel> addCommitment(CommitmentModel commitment);
  Future<CommitmentModel> updateCommitment(CommitmentModel commitment);
  Future<CommitmentModel> linkCommitmentToEtbAccount({
    required String commitmentId,
    required String accountId,
  });
  Future<void> deleteCommitment(String commitmentId);

  /// Records a partial or full commitment payment/receipt atomically via a ledger entry.
  Future<CommitmentSettlementModel> recordCommitmentSettlement({
    required String commitmentId,
    required String accountId,
    required int amountCents,
    String? categoryId,
    CalendarDate? settledDate,
    String? note,
  });

  /// Voids a commitment settlement entry and restores commitment status/remaining balance.
  Future<void> voidCommitmentSettlement({
    required String settlementId,
    required String reason,
  });

  /// Converts a pre-v7 `legacyPaidUnverified` commitment back to unpaid.
  Future<CommitmentModel> markLegacyCommitmentUnpaid(String commitmentId);

  /// Pays remaining amount of a commitment atomically by posting a balanced journal entry.
  Future<CommitmentModel> markCommitmentPaidWithPosting({
    required String commitmentId,
    required String accountId,
    String? categoryId,
    CalendarDate? paidDate,
    String? note,
  });

  @Deprecated('Use markCommitmentPaidWithPosting with an explicit accountId.')
  Future<void> markCommitmentPaid(
    String commitmentId, {
    bool createExpenseTransaction = false,
  });

  /// Savings Goals
  Future<List<SavingsGoalModel>> getSavingsGoals(
      {bool includeArchived = false});
  Future<SavingsGoalModel> createSavingsGoal(SavingsGoalModel goal);
  Future<SavingsGoalModel> updateSavingsGoal(SavingsGoalModel goal);
  Future<void> deleteSavingsGoal(String goalId);
  Future<SavingsGoalModel> releaseAndArchiveSavingsGoal(String goalId);
  Future<void> updateSavingsAllocation(String goalId, int newAllocatedCents);

  /// Transfers money into/out of a vault-linked goal or updates virtual earmark.
  Future<SavingsGoalModel> fundSavingsGoal({
    required String goalId,
    required int deltaCents,
    String? sourceAccountId,
    CalendarDate? date,
    String? note,
  });
}

/// Domain contract for Monthly Category Budgets.
abstract class IBudgetRepositoryContract {
  Future<List<BudgetModel>> getBudgets({String? monthIso});
  Future<BudgetModel> upsertBudget(BudgetModel budget);
  Future<void> deleteBudget(String budgetId);
}

/// Domain contract for Recurring Financial Rules & Schedules.
abstract class IRecurringRuleRepositoryContract {
  Future<List<RecurringRuleModel>> getRecurringRules({bool activeOnly = false});
  Future<RecurringRuleModel> upsertRecurringRule(RecurringRuleModel rule);
  Future<RecurringRuleModel> pauseRecurringRule(String ruleId);
  Future<RecurringRuleModel> resumeRecurringRule(
    String ruleId, {
    CalendarDate? today,
  });
  Future<RecurringRuleModel> skipNextOccurrence(String ruleId);
  Future<void> deleteRecurringRule(String ruleId);
  Future<int> processDueRecurringRules({required CalendarDate asOfDate});
}

/// Domain contract for Stage 5 local-only Financial SMS Draft review lifecycle.
///
/// Invariant: SMS imports NEVER create ledger postings automatically. Only
/// explicit user approval through [approveSmsDraft] converts a reviewable draft
/// into balanced journal postings.
abstract class ISmsDraftRepositoryContract {
  Future<List<FinanceSmsDraftModel>> getSmsDrafts({SmsDraftStatus? status});

  Future<SmsImportBatchResult> importSmsDrafts({
    required List<String> rawMessages,
    SmsProvider? providerHint,
    DateTime? receivedAtUtc,
  });

  Future<FinanceSmsDraftModel> updateSmsDraftReview({
    required String draftId,
    SmsSuggestedTransactionType? suggestedType,
    String? suggestedAccountId,
    bool clearSuggestedAccountId = false,
    String? suggestedCategoryId,
    bool clearSuggestedCategoryId = false,
    String? parseNotes,
  });

  Future<FinanceSmsDraftModel> dismissSmsDraft(String draftId);

  Future<({FinanceSmsDraftModel draft, JournalEntryModel entry})>
      approveSmsDraft({
    required String draftId,
    required SmsSuggestedTransactionType finalType,
    required String accountId,
    String? destinationAccountId,
    String? categoryId,
    String? feeCategoryId,
    required CalendarDate occurrenceDate,
    CalendarDate? movementDate,
    required String description,
    String? payee,
  });

  // --- Stage 6: Device-Local Inbox Checkpoint & Reliable Batch Import ---

  Future<SmsScanCheckpointState> getSmsScanCheckpointState();

  Future<void> setSmsPermissionAsked(bool asked);

  Future<void> setSmsDailyScanEnabled(bool enabled);

  Future<void> saveSmsSenderAliases(Map<String, SmsProvider> aliases);

  Future<void> recordSmsScanAttempt(DateTime attemptUtc);

  Future<({
    SmsImportBatchResult batch,
    DateTime? updatedCheckpointUtc,
    DateTime completedAtUtc,
  })> importInboxSmsBatchWithCheckpoint({
    required List<SmsInboxMessage> messages,
    DateTime? completedAtUtc,
    bool advanceCheckpoint = true,
    bool recordCompletionSuccess = true,
  });
}

/// Cohesive Finance Repository unifying all domain sub-contracts.
///
/// Ensures single-unit atomic database transaction boundaries while maintaining
/// highly-cohesive, domain-focused sub-interfaces.
abstract class IFinanceRepository
    implements
        IAccountRepositoryContract,
        ICategoryRepositoryContract,
        ITransactionRepositoryContract,
        IDebtRepositoryContract,
        IBudgetRepositoryContract,
        IRecurringRuleRepositoryContract,
        ISmsDraftRepositoryContract {
  /// Reads persisted finance setup status and opening balance from SQLite settings.
  Future<({bool isSetupCompleted, int openingBalanceCents})>
      getFinanceSettings();

  /// Atomically persists setup accounts (and opening equity postings) and marks setup completed.
  Future<void> completeFinanceSetup(List<AccountModel> setupAccounts);

  /// Updates setup-completed status flag in SQLite settings.
  Future<void> setFinanceSetupCompleted(bool completed);

  /// Reads whether the one-time notice about preserved historical non-ETB records was dismissed.
  Future<bool> getLegacyNonEtbNoticeDismissed();

  /// Persists dismissal of the historical non-ETB preservation notice.
  Future<void> dismissLegacyNonEtbNotice();

  /// Reads the latest v7 ledger migration diagnostic report, if any.
  Future<MigrationDiagnosticReport?> getLatestMigrationReport();

  /// Runs a Tier A/B debt control-account reconciliation check against active debts.
  Future<DebtControlAuditReport> auditDebtControlBalances();

  /// Reconstructs real-time financial snapshot across accounts and periods.
  Future<FinancialSnapshot> getFinancialSnapshot({
    required int openingBalanceCents,
    required CalendarDate periodStart,
    required CalendarDate periodEnd,
    required List<int> expectedFutureIncomeCents,
  });

  /// Exports strictly Finance-module records as a Finance-only JSON string (`financeOnly: true`).
  Future<String> exportFinanceOnlyJson();

  /// Validates and atomically restores strictly Finance-module records from a Finance-only JSON string.
  Future<void> importFinanceOnlyJson(String rawJson);
}
