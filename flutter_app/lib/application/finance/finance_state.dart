import '../../core/date/shared_date.dart';
import '../../core/interfaces/platform_service_interfaces.dart';
import '../../domain/finance/double_entry_engine.dart';
import '../../domain/finance/finance_models.dart';
import '../../domain/finance/finance_sms_models.dart';
import '../../domain/finance/financial_engine.dart';

/// Immutable state container for the Daywell Finance module.
class FinanceModuleState {
  final List<AccountModel> accounts;
  final List<TransactionCategoryModel> categories;
  final List<PartyModel> parties;
  final List<JournalEntryModel> journalEntries;
  final List<PostingModel> postings;
  final List<DebtModel> debts;
  final List<SettlementAllocationModel> settlementAllocations;
  final List<TransactionModel> transactions;
  final List<CommitmentModel> commitments;
  final List<CommitmentSettlementModel> commitmentSettlements;
  final List<SavingsGoalModel> savingsGoals;
  final List<BudgetModel> budgets;
  final List<RecurringRuleModel> recurringRules;
  final List<FinanceSmsDraftModel> smsDrafts;
  final CalendarDate? planningPeriodEnd;
  final int openingBalanceCents;
  final MigrationDiagnosticReport? migrationReport;
  final DebtControlAuditReport? debtControlAudit;

  // Presentation / Filter State
  final String searchQuery;
  final String typeFilter; // 'all', 'expense', 'income', 'transfer'
  final String accountFilter; // 'all' or accountId
  // 'all', 'today', 'yesterday', 'this_week', 'this_month', 'custom'
  final String datePresetFilter;
  final CalendarDate? customStartDate;
  final CalendarDate? customEndDate;
  final int txDisplayLimit;
  final bool isLoading;
  final String? errorMessage;
  final bool isSetupCompleted;
  final bool legacyNonEtbNoticeDismissed;
  final DeviceSmsPermissionStatus smsPermissionStatus;
  final SmsScanCheckpointState smsScanCheckpoint;
  final bool isSmsScanning;
  final SmsInboxScanResult? lastSmsScanResult;

  const FinanceModuleState({
    this.accounts = const [],
    this.categories = const [],
    this.parties = const [],
    this.journalEntries = const [],
    this.postings = const [],
    this.debts = const [],
    this.settlementAllocations = const [],
    this.transactions = const [],
    this.commitments = const [],
    this.commitmentSettlements = const [],
    this.savingsGoals = const [],
    this.budgets = const [],
    this.recurringRules = const [],
    this.smsDrafts = const [],
    this.planningPeriodEnd,
    this.openingBalanceCents = 0,
    this.migrationReport,
    this.debtControlAudit,
    this.searchQuery = '',
    this.typeFilter = 'all',
    this.accountFilter = 'all',
    this.datePresetFilter = 'all',
    this.customStartDate,
    this.customEndDate,
    this.txDisplayLimit = 25,
    this.isLoading = false,
    this.errorMessage,
    this.isSetupCompleted = true,
    this.legacyNonEtbNoticeDismissed = false,
    this.smsPermissionStatus = DeviceSmsPermissionStatus.unavailable,
    this.smsScanCheckpoint = const SmsScanCheckpointState(),
    this.isSmsScanning = false,
    this.lastSmsScanResult,
  });

  FinanceModuleState copyWith({
    List<AccountModel>? accounts,
    List<TransactionCategoryModel>? categories,
    List<PartyModel>? parties,
    List<JournalEntryModel>? journalEntries,
    List<PostingModel>? postings,
    List<DebtModel>? debts,
    List<SettlementAllocationModel>? settlementAllocations,
    List<TransactionModel>? transactions,
    List<CommitmentModel>? commitments,
    List<CommitmentSettlementModel>? commitmentSettlements,
    List<SavingsGoalModel>? savingsGoals,
    List<BudgetModel>? budgets,
    List<RecurringRuleModel>? recurringRules,
    List<FinanceSmsDraftModel>? smsDrafts,
    CalendarDate? planningPeriodEnd,
    bool clearPlanningPeriodEnd = false,
    int? openingBalanceCents,
    MigrationDiagnosticReport? migrationReport,
    bool clearMigrationReport = false,
    DebtControlAuditReport? debtControlAudit,
    bool clearDebtControlAudit = false,
    String? searchQuery,
    String? typeFilter,
    String? accountFilter,
    String? datePresetFilter,
    CalendarDate? customStartDate,
    bool clearCustomStartDate = false,
    CalendarDate? customEndDate,
    bool clearCustomEndDate = false,
    int? txDisplayLimit,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    bool? isSetupCompleted,
    bool? legacyNonEtbNoticeDismissed,
    DeviceSmsPermissionStatus? smsPermissionStatus,
    SmsScanCheckpointState? smsScanCheckpoint,
    bool? isSmsScanning,
    SmsInboxScanResult? lastSmsScanResult,
    bool clearLastSmsScanResult = false,
  }) {
    return FinanceModuleState(
      accounts: accounts ?? this.accounts,
      categories: categories ?? this.categories,
      parties: parties ?? this.parties,
      journalEntries: journalEntries ?? this.journalEntries,
      postings: postings ?? this.postings,
      debts: debts ?? this.debts,
      settlementAllocations:
          settlementAllocations ?? this.settlementAllocations,
      transactions: transactions ?? this.transactions,
      commitments: commitments ?? this.commitments,
      commitmentSettlements:
          commitmentSettlements ?? this.commitmentSettlements,
      savingsGoals: savingsGoals ?? this.savingsGoals,
      budgets: budgets ?? this.budgets,
      recurringRules: recurringRules ?? this.recurringRules,
      smsDrafts: smsDrafts ?? this.smsDrafts,
      planningPeriodEnd: clearPlanningPeriodEnd
          ? null
          : (planningPeriodEnd ?? this.planningPeriodEnd),
      openingBalanceCents: openingBalanceCents ?? this.openingBalanceCents,
      migrationReport: clearMigrationReport
          ? null
          : (migrationReport ?? this.migrationReport),
      debtControlAudit: clearDebtControlAudit
          ? null
          : (debtControlAudit ?? this.debtControlAudit),
      searchQuery: searchQuery ?? this.searchQuery,
      typeFilter: typeFilter ?? this.typeFilter,
      accountFilter: accountFilter ?? this.accountFilter,
      datePresetFilter: datePresetFilter ?? this.datePresetFilter,
      customStartDate: clearCustomStartDate
          ? null
          : (customStartDate ?? this.customStartDate),
      customEndDate:
          clearCustomEndDate ? null : (customEndDate ?? this.customEndDate),
      txDisplayLimit: txDisplayLimit ?? this.txDisplayLimit,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isSetupCompleted: isSetupCompleted ?? this.isSetupCompleted,
      legacyNonEtbNoticeDismissed:
          legacyNonEtbNoticeDismissed ?? this.legacyNonEtbNoticeDismissed,
      smsPermissionStatus: smsPermissionStatus ?? this.smsPermissionStatus,
      smsScanCheckpoint: smsScanCheckpoint ?? this.smsScanCheckpoint,
      isSmsScanning: isSmsScanning ?? this.isSmsScanning,
      lastSmsScanResult: clearLastSmsScanResult
          ? null
          : (lastSmsScanResult ?? this.lastSmsScanResult),
    );
  }

  CalendarDate get effectivePlanningPeriodEnd {
    if (planningPeriodEnd != null) return planningPeriodEnd!;
    return CalendarDate.today().endOfGregorianMonth;
  }

  // --- Authoritative Ledger Calculation Getters (PostingsTable Authority) ---

  List<TransactionModel> get activeTransactions =>
      transactions.where((t) => !t.isSuperseded).toList(growable: false);

  List<CommitmentModel> get pendingCommitments => commitments
      .where((c) => !c.isPaid && !c.legacyPaidUnverified)
      .toList(growable: false);

  List<CommitmentModel> get pendingOutflowCommitments => pendingCommitments
      .where((c) => c.direction == CommitmentDirection.outflow)
      .toList(growable: false);

  List<CommitmentModel> get pendingInflowCommitments => pendingCommitments
      .where((c) => c.direction == CommitmentDirection.inflow)
      .toList(growable: false);

  List<CommitmentModel> get legacyUnverifiedPaidCommitments =>
      commitments.where((c) => c.legacyPaidUnverified).toList(growable: false);

  List<CommitmentSettlementModel> settlementsForCommitment(
    String commitmentId,
  ) {
    return commitmentSettlements
        .where((s) => s.commitmentId == commitmentId)
        .toList(growable: false);
  }

  List<JournalEntryModel> get activeJournalEntries =>
      journalEntries.where((e) => !e.isVoided).toList(growable: false);

  AvailableToSpendBreakdown get availableToSpendBreakdown =>
      DoubleEntryEngine.calculateAvailableToSpendBreakdown(
        accounts: accounts,
        postings: postings,
        entries: journalEntries,
        debts: debts,
        commitments: commitments,
        savingsGoals: savingsGoals,
        periodEndIso: effectivePlanningPeriodEnd.toIsoString(),
        allocations: settlementAllocations,
        recurringRules: recurringRules,
        commitmentSettlements: commitmentSettlements,
      );

  int get liquidCashCents => availableToSpendBreakdown.liquidCashCents;

  int get prepaidCardCreditCents =>
      availableToSpendBreakdown.prepaidCardCreditCents;

  int get vaultSavingsCents => availableToSpendBreakdown.vaultSavingsCents;

  int get shortTermCreditOwedCents =>
      availableToSpendBreakdown.shortTermCreditOwedCents;

  int get duePayablesCents => availableToSpendBreakdown.duePayablesCents;

  int get dueNonDebtCommitmentsCents =>
      availableToSpendBreakdown.dueNonDebtCommitmentsCents;

  int get virtualSavingsReservedCents =>
      availableToSpendBreakdown.virtualSavingsReservedCents;

  int get availableToSpendCents =>
      availableToSpendBreakdown.availableToSpendCents;

  bool get isShortfall => availableToSpendCents < 0;

  int get nonEtbAccountCount => availableToSpendBreakdown.nonEtbAccountCount;

  int get unverifiedAccountCount =>
      availableToSpendBreakdown.unverifiedAccountCount;

  int get excludedNonEtbEntryCount =>
      availableToSpendBreakdown.excludedNonEtbEntryCount;

  int get currencyReviewEntryCount =>
      availableToSpendBreakdown.currencyReviewEntryCount;

  int get unverifiedLegacyPaidCount =>
      availableToSpendBreakdown.unverifiedLegacyPaidCount;

  CurrencyIsolationAudit get currencyIsolationAudit =>
      DoubleEntryEngine.auditCurrencyIsolation(
        accounts: accounts,
        entries: journalEntries,
        postings: postings,
        debts: debts,
        allocations: settlementAllocations,
        commitments: commitments,
        recurringRules: recurringRules,
        commitmentSettlements: commitmentSettlements,
        savingsGoals: savingsGoals,
      );

  Map<String, EntryCurrencyClassification> get classificationsByEntryId =>
      currencyIsolationAudit.classificationsByEntryId;

  EntryCurrencyClassification classifyEntry(JournalEntryModel entry) {
    final accountById = {for (final a in accounts) a.id: a};
    final entryPostings =
        postings.where((p) => p.entryId == entry.id).toList(growable: false);
    return DoubleEntryEngine.classifyEntryCurrency(
      entry: entry,
      entryPostings: entryPostings,
      accountById: accountById,
      debts: debts,
      allocations: settlementAllocations,
      allEntries: journalEntries,
      allPostings: postings,
    );
  }

  CommitmentCurrencyResolution classifyCommitment(CommitmentModel commitment) {
    final accountById = {for (final a in accounts) a.id: a};
    final debtById = {for (final d in debts) d.id: d};
    final entryById = {for (final e in journalEntries) e.id: e};
    final ruleById = {for (final r in recurringRules) r.id: r};
    final settlementsByCommitment = <String, List<CommitmentSettlementModel>>{};
    for (final s in commitmentSettlements) {
      settlementsByCommitment.putIfAbsent(s.commitmentId, () => []).add(s);
    }
    return DoubleEntryEngine.resolveCommitmentCurrencyStatus(
      commitment: commitment,
      accountById: accountById,
      debtById: debtById,
      entryById: entryById,
      classificationsByEntryId: classificationsByEntryId,
      ruleById: ruleById,
      settlementsByCommitmentId: settlementsByCommitment,
    );
  }

  CommitmentCurrencyResolution resolveCommitmentCurrency(
    CommitmentModel commitment,
  ) =>
      classifyCommitment(commitment);

  EntryCurrencyClassification? classifyDebt(DebtModel debt) =>
      classificationsByEntryId[debt.originEntryId];

  bool isDebtEligibleEtb(DebtModel debt) {
    final entryById = {for (final e in journalEntries) e.id: e};
    return DoubleEntryEngine.isDebtEligibleEtb(
      debt,
      entryById: entryById,
      classifications: classificationsByEntryId,
    );
  }

  int get netFinancialPositionCents => DoubleEntryEngine.calculateNetPosition(
        accounts: accounts,
        postings: postings,
        entries: journalEntries,
        debts: debts,
        allocations: settlementAllocations,
      );

  int get totalReceivablesCents => DoubleEntryEngine.calculateTotalReceivables(
        debts,
        accounts: accounts,
        entries: journalEntries,
        postings: postings,
        allocations: settlementAllocations,
      );

  int get totalPayablesCents => DoubleEntryEngine.calculateTotalPayables(
        debts,
        accounts: accounts,
        entries: journalEntries,
        postings: postings,
        allocations: settlementAllocations,
      );

  int getAccountBalanceCents(AccountModel account) {
    return DoubleEntryEngine.calculateAccountBalance(
      account: account,
      postings: postings,
      entries: journalEntries,
    );
  }

  int get combinedBalanceCents => liquidCashCents + vaultSavingsCents;

  ({int incomeCents, int expenseCents, int netCashflowCents})
      occurrencePnlForRange(CalendarDate startDate, CalendarDate endDate) {
    return DoubleEntryEngine.calculateOccurrencePnlTotals(
      accounts: accounts,
      postings: postings,
      entries: journalEntries,
      startDateIso: startDate.toIsoString(),
      endDateIso: endDate.toIsoString(),
      debts: debts,
      allocations: settlementAllocations,
    );
  }

  ({int inflowCents, int outflowCents, int netCashflowCents})
      liquidCashflowForRange(CalendarDate startDate, CalendarDate endDate) {
    return DoubleEntryEngine.calculateLiquidCashflowTotals(
      accounts: accounts,
      postings: postings,
      entries: journalEntries,
      startDateIso: startDate.toIsoString(),
      endDateIso: endDate.toIsoString(),
      debts: debts,
      allocations: settlementAllocations,
    );
  }

  ({int incomeCents, int expenseCents, int netCashflowCents})
      netCashflowForRange(CalendarDate startDate, CalendarDate endDate) {
    return occurrencePnlForRange(startDate, endDate);
  }

  int get totalIncomeCents {
    return DoubleEntryEngine.calculatePeriodCashflowTotals(
      accounts: accounts,
      postings: postings,
      entries: journalEntries,
      startDateIso: '0001-01-01',
      endDateIso: '9999-12-31',
      debts: debts,
      allocations: settlementAllocations,
    ).incomeCents;
  }

  int get totalExpenseCents {
    return DoubleEntryEngine.calculatePeriodCashflowTotals(
      accounts: accounts,
      postings: postings,
      entries: journalEntries,
      startDateIso: '0001-01-01',
      endDateIso: '9999-12-31',
      debts: debts,
      allocations: settlementAllocations,
    ).expenseCents;
  }

  Map<String, int> categorySpendForMonth(
    String monthIso, {
    bool rollupToParents = true,
  }) {
    return DoubleEntryEngine.calculateCategorySpendForPeriod(
      postings: postings,
      entries: journalEntries,
      startDateIso: '$monthIso-01',
      endDateIso: '$monthIso-31',
      categories: categories,
      accounts: accounts,
      debts: debts,
      allocations: settlementAllocations,
      rollupToParents: rollupToParents,
    );
  }

  FinancialSnapshot get financialSnapshot {
    final breakdown = availableToSpendBreakdown;
    return FinancialSnapshot(
      openingBalanceCents: openingBalanceCents,
      totalIncomeCents: totalIncomeCents,
      totalExpensesCents: totalExpenseCents,
      recordedBalanceCents: combinedBalanceCents,
      unpaidCommitmentsCents: breakdown.totalDueObligationsCents,
      savingsReservedCents: breakdown.virtualSavingsReservedCents,
      expectedFutureIncomeCents: 0,
      availableToSpendCents: breakdown.availableToSpendCents,
    );
  }

  List<AccountModel> get activeAccounts => accounts
      .where((a) =>
          !a.isArchived &&
          !a.isSystem &&
          DoubleEntryEngine.isEtb(a.currencyCode) &&
          a.type == AccountType.asset)
      .toList(growable: false);

  List<AccountModel> get activeUserAccounts => accounts
      .where((a) => !a.isArchived && !a.isSystem)
      .toList(growable: false);

  List<AccountModel> get activeEtbUserAccounts => accounts
      .where(DoubleEntryEngine.isActiveVerifiedEtbAccount)
      .toList(growable: false);

  List<AccountModel> get activeEtbAccounts => activeEtbUserAccounts;

  List<AccountModel> get activeEtbSpendableAccounts => accounts
      .where((a) =>
          DoubleEntryEngine.isActiveVerifiedEtbAccount(a) &&
          ((a.type == AccountType.asset &&
                  !a.subType.isSavingsVault &&
                  a.subType != AccountSubType.receivable) ||
              (a.type == AccountType.liability &&
                  a.subType == AccountSubType.creditCard)))
      .toList(growable: false);

  List<AccountModel> get activeEtbVaultAccounts => accounts
      .where((a) =>
          DoubleEntryEngine.isActiveVerifiedEtbAccount(a) &&
          a.type == AccountType.asset &&
          a.subType.isSavingsVault)
      .toList(growable: false);

  List<AccountModel> get etbUserAccounts => accounts
      .where((a) => !a.isSystem && DoubleEntryEngine.isEtb(a.currencyCode))
      .toList(growable: false);

  List<AccountModel> get archivedEtbAccounts => accounts
      .where(
        (a) =>
            a.isArchived &&
            !a.isSystem &&
            DoubleEntryEngine.isEtb(a.currencyCode),
      )
      .toList(growable: false);

  List<AccountModel> get nonEtbAccounts => accounts
      .where((a) =>
          !a.isArchived &&
          !a.isSystem &&
          !DoubleEntryEngine.isEtb(a.currencyCode))
      .toList(growable: false);

  List<AccountModel> get legacyNonEtbAccounts => accounts
      .where((a) => !a.isSystem && !DoubleEntryEngine.isEtb(a.currencyCode))
      .toList(growable: false);

  int get legacyNonEtbEntryCount {
    final map = classificationsByEntryId;
    return journalEntries
        .where((e) => map[e.id]?.isEligibleEtb != true)
        .length;
  }

  bool get hasLegacyNonEtbRecords =>
      legacyNonEtbAccounts.isNotEmpty ||
      legacyNonEtbEntryCount > 0 ||
      nonEtbAccountCount > 0 ||
      unverifiedAccountCount > 0 ||
      excludedNonEtbEntryCount > 0 ||
      currencyReviewEntryCount > 0;

  List<AccountModel> get liquidAssetAccounts => accounts
      .where((a) =>
          DoubleEntryEngine.isActiveVerifiedEtbAccount(a) &&
          a.type == AccountType.asset &&
          a.subType.isLiquid)
      .toList(growable: false);

  List<AccountModel> get vaultAssetAccounts => activeEtbVaultAccounts;

  List<AccountModel> get archivedAccounts => accounts
      .where((a) => a.isArchived && !a.isSystem)
      .toList(growable: false);

  List<SavingsGoalModel> get activeSavingsGoals =>
      savingsGoals.where((g) => !g.isArchived).toList(growable: false);

  List<SavingsGoalModel> get archivedSavingsGoals =>
      savingsGoals.where((g) => g.isArchived).toList(growable: false);

  List<TransactionCategoryModel> get activeCategories =>
      categories.where((c) => !c.isArchived).toList(growable: false);

  List<RecurringRuleModel> get activeRecurringRules =>
      recurringRules.where((r) => r.isActive).toList(growable: false);

  List<FinanceSmsDraftModel> get pendingSmsDrafts => smsDrafts
      .where((d) => d.status == SmsDraftStatus.needsReview)
      .toList(growable: false);

  int get pendingSmsDraftCount =>
      smsDrafts.where((d) => d.status == SmsDraftStatus.needsReview).length;

  bool get isAnyFilterActive =>
      typeFilter != 'all' ||
      accountFilter != 'all' ||
      datePresetFilter != 'all' ||
      searchQuery.trim().isNotEmpty;
}
