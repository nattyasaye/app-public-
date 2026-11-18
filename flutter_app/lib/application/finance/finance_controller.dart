import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/date/shared_date.dart';
import '../../domain/finance/finance_contracts.dart';
import 'finance_state.dart';

/// Module-scoped application controller for Daywell Finance.
///
/// Sole owner of Finance runtime state, hydrated directly from and persisted to
/// [IFinanceRepository] (authoritative Drift SQLite double-entry ledger).
class FinanceController extends ChangeNotifier {
  final IFinanceRepository _repository;
  final Uuid _uuid = const Uuid();
  FinanceModuleState _state;
  bool _isDisposed = false;

  FinanceController({
    required IFinanceRepository repository,
    FinanceModuleState? initialState,
  })  : _repository = repository,
        _state = initialState ?? const FinanceModuleState();

  FinanceModuleState get state => _state;

  // --- Hydration ---

  Future<void> loadAll() async {
    _state = _state.copyWith(isLoading: true, clearError: true);
    notifyListeners();
    try {
      await _hydrateState();
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
    notifyListeners();
  }

  Future<void> _hydrateState() async {
    final settings = await _repository.getFinanceSettings();
    final accounts = await _repository.getAccounts(includeArchived: true);
    final categories = await _repository.getCategories(includeArchived: true);
    final parties = await _repository.getParties(includeArchived: true);
    final entries = await _repository.getJournalEntries(includeVoided: true);
    final postings = await _repository.getPostings();
    final debts = await _repository.getDebts();
    final allocations = await _repository.getSettlementAllocations();
    final transactions = await _repository.getTransactions();
    final commitments = await _repository.getCommitments();
    final commitmentSettlements = await _repository.getCommitmentSettlements();
    final savingsGoals =
        await _repository.getSavingsGoals(includeArchived: true);
    final budgets = await _repository.getBudgets();
    final recurringRules = await _repository.getRecurringRules();
    final migrationReport = await _repository.getLatestMigrationReport();
    final debtControlAudit = await _repository.auditDebtControlBalances();

    _state = _state.copyWith(
      accounts: List<AccountModel>.unmodifiable(accounts),
      categories: List<TransactionCategoryModel>.unmodifiable(categories),
      parties: List<PartyModel>.unmodifiable(parties),
      journalEntries: List<JournalEntryModel>.unmodifiable(entries),
      postings: List<PostingModel>.unmodifiable(postings),
      debts: List<DebtModel>.unmodifiable(debts),
      settlementAllocations:
          List<SettlementAllocationModel>.unmodifiable(allocations),
      transactions: List<TransactionModel>.unmodifiable(transactions),
      commitments: List<CommitmentModel>.unmodifiable(commitments),
      commitmentSettlements:
          List<CommitmentSettlementModel>.unmodifiable(commitmentSettlements),
      savingsGoals: List<SavingsGoalModel>.unmodifiable(savingsGoals),
      budgets: List<BudgetModel>.unmodifiable(budgets),
      recurringRules: List<RecurringRuleModel>.unmodifiable(recurringRules),
      openingBalanceCents: settings.openingBalanceCents,
      isSetupCompleted: settings.isSetupCompleted,
      migrationReport: migrationReport,
      clearMigrationReport: migrationReport == null,
      debtControlAudit: debtControlAudit,
      isLoading: false,
      clearError: true,
    );
  }

  Future<void> refreshAuditDiagnostics() async {
    try {
      final migrationReport = await _repository.getLatestMigrationReport();
      final debtControlAudit = await _repository.auditDebtControlBalances();
      _state = _state.copyWith(
        migrationReport: migrationReport,
        clearMigrationReport: migrationReport == null,
        debtControlAudit: debtControlAudit,
        clearError: true,
      );
      notifyListeners();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> _refreshAccountsAndLedger() async {
    await _hydrateState();
    notifyListeners();
  }

  // --- Presentation Filter Controls ---

  void setSearchQuery(String query) {
    _state = _state.copyWith(searchQuery: query);
    notifyListeners();
  }

  void setTypeFilter(String filter) {
    _state = _state.copyWith(typeFilter: filter);
    notifyListeners();
  }

  void setAccountFilter(String accountId) {
    _state = _state.copyWith(accountFilter: accountId);
    notifyListeners();
  }

  void setDatePresetFilter(String preset) {
    _state = _state.copyWith(datePresetFilter: preset);
    notifyListeners();
  }

  void setCustomDateRange(CalendarDate? start, CalendarDate? end) {
    _state = _state.copyWith(
      datePresetFilter: 'custom',
      customStartDate: start,
      customEndDate: end,
    );
    notifyListeners();
  }

  void setTxDisplayLimit(int limit) {
    _state = _state.copyWith(txDisplayLimit: limit);
    notifyListeners();
  }

  void setPlanningPeriodEnd(CalendarDate? date) {
    _state = date == null
        ? _state.copyWith(clearPlanningPeriodEnd: true)
        : _state.copyWith(planningPeriodEnd: date);
    notifyListeners();
  }

  void clearAllFilters() {
    _state = _state.copyWith(
      typeFilter: 'all',
      accountFilter: 'all',
      datePresetFilter: 'all',
      clearCustomStartDate: true,
      clearCustomEndDate: true,
      searchQuery: '',
      txDisplayLimit: 25,
    );
    notifyListeners();
  }

  // --- Account Lifecycle Workflows ---

  void _preflightAssertEtbAccountIfLoaded(
    String accountId, {
    String roleLabel = 'Account',
  }) {
    if (SystemControlAccounts.isSystemControlId(accountId)) return;
    if (_state.accounts.isEmpty) return;
    final match = _state.accounts.where((a) => a.id == accountId);
    if (match.isNotEmpty) {
      DoubleEntryEngine.assertVerifiedEtbAccount(
        match.first,
        roleLabel: roleLabel,
      );
    }
  }

  void _preflightAssertSpendableEtbAccountIfLoaded(
    String accountId, {
    String roleLabel = 'Account',
  }) {
    _preflightAssertEtbAccountIfLoaded(accountId, roleLabel: roleLabel);
    if (SystemControlAccounts.isSystemControlId(accountId)) return;
    if (_state.accounts.isEmpty) return;
    final match = _state.accounts.where((a) => a.id == accountId);
    if (match.isEmpty) return;
    final acc = match.first;
    if (acc.isArchived) {
      throw DoubleEntryValidationError(
        '$roleLabel "${acc.name}" is archived and cannot receive new postings.',
      );
    }
    final isSpendable = !acc.subType.isSavingsVault &&
        acc.subType != AccountSubType.receivable &&
        acc.subType != AccountSubType.payable &&
        (acc.type == AccountType.asset ||
            (acc.type == AccountType.liability &&
                acc.subType == AccountSubType.creditCard));
    if (!isSpendable) {
      throw DoubleEntryValidationError(
        '$roleLabel "${acc.name}" cannot be used here; select an active Verified ETB liquid asset or credit card account (Savings Vaults are allowed in Transfers only).',
      );
    }
  }

  void _preflightAssertTransferEtbAccountIfLoaded(
    String accountId, {
    String roleLabel = 'Account',
  }) {
    _preflightAssertEtbAccountIfLoaded(accountId, roleLabel: roleLabel);
    if (SystemControlAccounts.isSystemControlId(accountId)) return;
    if (_state.accounts.isEmpty) return;
    final match = _state.accounts.where((a) => a.id == accountId);
    if (match.isEmpty) return;
    final acc = match.first;
    if (acc.isArchived) {
      throw DoubleEntryValidationError(
        '$roleLabel "${acc.name}" is archived and cannot participate in transfers.',
      );
    }
    final isTransferable = acc.subType != AccountSubType.receivable &&
        acc.subType != AccountSubType.payable &&
        (acc.type == AccountType.asset ||
            (acc.type == AccountType.liability &&
                acc.subType == AccountSubType.creditCard));
    if (!isTransferable) {
      throw DoubleEntryValidationError(
        '$roleLabel "${acc.name}" cannot participate in an ETB transfer.',
      );
    }
  }

  Future<void> addAccount({
    required String name,
    required AccountType type,
    AccountSubType? subType,
    String currencyCode = 'ETB',
    int openingBalanceCents = 0,
    String? openingBalanceDate,
  }) async {
    _state = _state.copyWith(clearError: true);
    if (!DoubleEntryEngine.isEtb(currencyCode)) {
      _state = _state.copyWith(
        errorMessage: DoubleEntryValidationError(
          'First-release reporting supports ETB accounts only; currency '
          '"${currencyCode.trim().isEmpty ? 'Unverified' : currencyCode.trim()}" '
          'cannot be created.',
        ).toString(),
      );
      notifyListeners();
      return;
    }

    final now = EthiopiaClock.nowUtc();
    final accId = 'acc-${_uuid.v4()}';
    final dateStr = openingBalanceDate ??
        CalendarDate.fromUtcInstantInEthiopia(now).toIsoString();

    final newAccount = AccountModel(
      id: accId,
      name: name.trim(),
      type: type,
      subType: subType ?? AccountSubType.defaultForType(type),
      currencyCode: 'ETB',
      openingBalanceCents: openingBalanceCents,
      openingBalanceDate: dateStr,
      createdAt: now,
    );

    try {
      await _repository.createAccount(newAccount);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> updateAccount(AccountModel account) async {
    _state = _state.copyWith(clearError: true);
    try {
      await _repository.updateAccount(account);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> renameAccount(String accountId, String newName) async {
    try {
      final account = await _repository.getAccountById(accountId);
      if (account == null) return;
      await _repository.updateAccount(account.copyWith(name: newName.trim()));
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> archiveAccount(String accountId) async {
    try {
      await _repository.archiveAccount(accountId);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> unarchiveAccount(String accountId) async {
    try {
      await _repository.unarchiveAccount(accountId);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<bool> deleteAccount(String accountId) async {
    try {
      final deleted = await _repository.deleteAccount(accountId);
      if (deleted) {
        await _refreshAccountsAndLedger();
      }
      return deleted;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return false;
    }
  }

  Future<AccountModel?> reviseOpeningBalance({
    required String accountId,
    required int newOpeningBalanceCents,
    String reason = 'Updated opening balance',
    CalendarDate? effectiveDate,
  }) async {
    try {
      _preflightAssertEtbAccountIfLoaded(accountId, roleLabel: 'Account');
      final updated = await _repository.reviseOpeningBalance(
        accountId: accountId,
        newOpeningBalanceCents: newOpeningBalanceCents,
        reason: reason,
        effectiveDate: effectiveDate,
      );
      await _refreshAccountsAndLedger();
      return updated;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<List<JournalEntryModel>> getOpeningBalanceHistory(String accountId) {
    return _repository.getOpeningBalanceHistory(accountId);
  }

  Future<void> updateAccountOpeningBalance({
    required String accountId,
    required int newOpeningBalanceCents,
    required String openingDate,
    String reason = 'Updated opening balance',
  }) async {
    final canonicalDate =
        SharedDateFormatter.parseFlexibleToCalendarDate(openingDate);
    await reviseOpeningBalance(
      accountId: accountId,
      newOpeningBalanceCents: newOpeningBalanceCents,
      reason: reason,
      effectiveDate: canonicalDate,
    );
  }

  // --- Category Workflows ---

  Future<TransactionCategoryModel?> addCategory(
    TransactionCategoryModel category,
  ) async {
    _state = _state.copyWith(clearError: true);
    try {
      final created = await _repository.createCategory(
        id: category.id,
        name: category.name,
        type: category.type,
        colorHex: category.colorHex,
        parentId: category.parentId,
        sortOrder: category.sortOrder,
        isDefault: category.isDefault,
      );
      final updated = await _repository.getCategories(includeArchived: true);
      _state = _state.copyWith(
        categories: List<TransactionCategoryModel>.unmodifiable(updated),
        clearError: true,
      );
      notifyListeners();
      return created;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<void> updateCategoryDetails(
    String id, {
    String? name,
    String? colorHex,
    String? parentId,
    bool clearParentId = false,
    int? sortOrder,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      await _repository.updateCategory(
        id,
        name: name,
        colorHex: colorHex,
        parentId: parentId,
        clearParentId: clearParentId,
        sortOrder: sortOrder,
      );
      final updated = await _repository.getCategories(includeArchived: true);
      _state = _state.copyWith(
        categories: List<TransactionCategoryModel>.unmodifiable(updated),
        clearError: true,
      );
      notifyListeners();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> renameCategory(String id, String newName) async {
    await updateCategoryDetails(id, name: newName.trim());
  }

  Future<void> archiveCategory(String id) async {
    try {
      await _repository.toggleArchiveCategory(id);
      final updated = await _repository.getCategories(includeArchived: true);
      _state = _state.copyWith(
        categories: List<TransactionCategoryModel>.unmodifiable(updated),
        clearError: true,
      );
      notifyListeners();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<bool> deleteCategory(String id) async {
    try {
      final deleted = await _repository.deleteCategory(id);
      if (deleted) {
        final updated = await _repository.getCategories(includeArchived: true);
        _state = _state.copyWith(
          categories: List<TransactionCategoryModel>.unmodifiable(updated),
          clearError: true,
        );
        notifyListeners();
      }
      return deleted;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return false;
    }
  }

  // --- Double-Entry Ledger Transaction Workflows ---

  Future<JournalEntryModel?> recordDirectExpense({
    required String accountId,
    required String categoryId,
    required int amountCents,
    required CalendarDate date,
    CalendarDate? movementDate,
    required String description,
    String? payee,
    String? note,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      _preflightAssertSpendableEtbAccountIfLoaded(
        accountId,
        roleLabel: 'Paid account',
      );
      final entry = await _repository.recordDirectExpense(
        accountId: accountId,
        categoryId: categoryId,
        amountCents: amountCents,
        date: date,
        movementDate: movementDate,
        description: description,
        payee: payee,
        note: note,
      );
      await _refreshAccountsAndLedger();
      return entry;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<JournalEntryModel?> recordDirectIncome({
    required String accountId,
    required String categoryId,
    required int amountCents,
    required CalendarDate date,
    CalendarDate? movementDate,
    required String description,
    String? payee,
    String? note,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      _preflightAssertSpendableEtbAccountIfLoaded(
        accountId,
        roleLabel: 'Deposit account',
      );
      final entry = await _repository.recordDirectIncome(
        accountId: accountId,
        categoryId: categoryId,
        amountCents: amountCents,
        date: date,
        movementDate: movementDate,
        description: description,
        payee: payee,
        note: note,
      );
      await _refreshAccountsAndLedger();
      return entry;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<JournalEntryModel?> recordSplitExpense({
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
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      _preflightAssertSpendableEtbAccountIfLoaded(
        paidAccountId,
        roleLabel: 'Paid account',
      );
      final entry = await _repository.recordSplitExpense(
        paidAccountId: paidAccountId,
        myCategoryId: myCategoryId,
        myShareCents: myShareCents,
        theirShareCents: theirShareCents,
        partyId: partyId,
        date: date,
        movementDate: movementDate,
        dueDate: dueDate,
        description: description,
        note: note,
      );
      await _refreshAccountsAndLedger();
      return entry;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<JournalEntryModel?> correctJournalEntry({
    required String originalEntryId,
    required JournalEntryModel replacementEntry,
    required List<PostingModel> replacementPostings,
    required String correctionReason,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      if (!DoubleEntryEngine.isCorrectableEntryType(
            replacementEntry.entryType,
          ) ||
          DoubleEntryEngine.isRefundEntry(replacementEntry)) {
        throw DoubleEntryValidationError(
          'Replacement entry type "${replacementEntry.entryType.dbValue}" is '
          'not supported during correction.',
        );
      }
      final origMatches =
          _state.journalEntries.where((e) => e.id == originalEntryId);
      if (origMatches.isNotEmpty) {
        final orig = origMatches.first;
        final origCls = _state.classifyEntry(orig);
        if (!origCls.isEligibleEtb) {
          throw DoubleEntryValidationError(
            'Only active ETB journal entries can be corrected or replaced '
            'in first-release ETB mode.',
          );
        }
        final check = DoubleEntryEngine.canCorrectEntry(
          entry: orig,
          entries: _state.journalEntries,
          postings: _state.postings,
          accounts: _state.accounts,
          debts: _state.debts,
          allocations: _state.settlementAllocations,
          commitmentSettlements: _state.commitmentSettlements,
        );
        if (!check.ok) {
          throw DoubleEntryValidationError(
            check.error ?? 'Entry cannot be replaced.',
          );
        }
      }
      for (final p in replacementPostings) {
        if (replacementEntry.entryType == EntryType.transfer) {
          _preflightAssertTransferEtbAccountIfLoaded(p.accountId);
        } else {
          _preflightAssertSpendableEtbAccountIfLoaded(p.accountId);
        }
      }
      final entry = await _repository.correctJournalEntry(
        originalEntryId: originalEntryId,
        replacementEntry: replacementEntry,
        replacementPostings: replacementPostings,
        correctionReason: correctionReason,
      );
      await _refreshAccountsAndLedger();
      return entry;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<JournalEntryModel?> recordExpenseRefund({
    required String originalEntryId,
    required String refundAccountId,
    required int refundCents,
    CalendarDate? date,
    String? note,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      _preflightAssertSpendableEtbAccountIfLoaded(
        refundAccountId,
        roleLabel: 'Refund destination account',
      );
      final entry = await _repository.recordExpenseRefund(
        originalEntryId: originalEntryId,
        refundAccountId: refundAccountId,
        refundCents: refundCents,
        date: date ?? CalendarDate.today(),
        note: note,
      );
      await _refreshAccountsAndLedger();
      return entry;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<void> recordTransfer({
    required String fromAssetAccountId,
    required String toAssetAccountId,
    required int amountCents,
    required String date,
    String? movementDate,
    required String description,
    int transferFeeCents = 0,
    String? feeCategoryId,
    String? note,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      _preflightAssertTransferEtbAccountIfLoaded(
        fromAssetAccountId,
        roleLabel: 'Source account',
      );
      _preflightAssertTransferEtbAccountIfLoaded(
        toAssetAccountId,
        roleLabel: 'Destination account',
      );
      await _repository.recordAccountTransfer(
        fromAccountId: fromAssetAccountId,
        toAccountId: toAssetAccountId,
        amountCents: amountCents,
        transferFeeCents: transferFeeCents,
        feeCategoryId: feeCategoryId,
        date: SharedDateFormatter.parseFlexibleToCalendarDate(date),
        movementDate: movementDate != null
            ? SharedDateFormatter.parseFlexibleToCalendarDate(movementDate)
            : null,
        description: description,
        note: note,
      );
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      rethrow;
    }
  }

  Future<void> addDoubleEntryTransfer({
    required String sourceAssetAccountId,
    required String destAssetAccountId,
    required int principalCents,
    int bankFeeCents = 0,
    required String date,
    required String description,
  }) async {
    await recordTransfer(
      fromAssetAccountId: sourceAssetAccountId,
      toAssetAccountId: destAssetAccountId,
      amountCents: principalCents,
      date: date,
      description: description,
      transferFeeCents: bankFeeCents,
    );
  }

  Future<void> voidJournalEntry(String entryId, String reason) async {
    _state = _state.copyWith(clearError: true);
    try {
      await _repository.voidJournalEntry(
        entryId: entryId,
        voidReason: reason,
      );
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> unvoidJournalEntry(String entryId) async {
    _state = _state.copyWith(clearError: true);
    try {
      await _repository.unvoidJournalEntry(entryId);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> addDoubleEntryDirectExpense({
    required String assetAccountId,
    required String expenseAccountId,
    required int amountCents,
    required String description,
    required String occurrenceDate,
    String? categoryId,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      _preflightAssertEtbAccountIfLoaded(
        assetAccountId,
        roleLabel: 'Asset account',
      );
      final entryId = 'entry-${_uuid.v4()}';
      final entry = JournalEntryModel(
        id: entryId,
        entryType: EntryType.standard,
        description: description,
        occurrenceDate: occurrenceDate,
      );
      final pDr = PostingModel(
        id: '$entryId-dr',
        entryId: entryId,
        accountId: expenseAccountId,
        amountCents: amountCents,
        direction: PostingDirection.debit,
        accountMovementDate: occurrenceDate,
        categoryId: categoryId,
      );
      final pCr = PostingModel(
        id: '$entryId-cr',
        entryId: entryId,
        accountId: assetAccountId,
        amountCents: amountCents,
        direction: PostingDirection.credit,
        accountMovementDate: occurrenceDate,
      );
      await _repository.recordJournalEntry(entry: entry, postings: [pDr, pCr]);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  // --- Legacy Cashflow Bridge Methods (Maintained for Test & Caller Compatibility) ---

  @Deprecated('Use recordDirectExpense, recordDirectIncome, or recordTransfer.')
  Future<void> recordTransaction(TransactionModel tx) async {
    try {
      // ignore: deprecated_member_use_from_same_package
      await _repository.recordTransaction(tx);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  @Deprecated('Use correctJournalEntry.')
  Future<void> correctTransaction({
    required String originalId,
    required int newAmountCents,
    required String newCategoryId,
    required String newCategoryName,
    required String reason,
    String? newNote,
    String? newPayee,
  }) async {
    try {
      // ignore: deprecated_member_use_from_same_package
      await _repository.correctTransaction(
        originalId: originalId,
        newAmountCents: newAmountCents,
        newCategoryId: newCategoryId,
        newCategoryName: newCategoryName,
        correctionReason: reason,
        newNote: newNote,
        newPayee: newPayee,
      );
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  @Deprecated('Use voidJournalEntry.')
  Future<void> deleteTransaction(String id) async {
    try {
      // ignore: deprecated_member_use_from_same_package
      await _repository.deleteTransaction(id);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  @Deprecated('Use unvoidJournalEntry.')
  Future<void> restoreTransaction(TransactionModel tx) async {
    try {
      // ignore: deprecated_member_use_from_same_package
      await _repository.restoreTransaction(tx);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  // --- Commitments & Savings Goals Workflows ---

  Future<void> addCommitment(CommitmentModel commitment) async {
    _state = _state.copyWith(clearError: true);
    try {
      final linkedAccId = commitment.linkedAccountId?.trim();
      final linkedDebtId = commitment.linkedDebtId?.trim();
      if (linkedAccId != null && linkedAccId.isNotEmpty) {
        _preflightAssertEtbAccountIfLoaded(
          linkedAccId,
          roleLabel: 'Linked account',
        );
      }
      if (linkedDebtId != null &&
          linkedDebtId.isNotEmpty &&
          _state.journalEntries.isNotEmpty) {
        final match = _state.debts.where((d) => d.id == linkedDebtId);
        if (match.isNotEmpty) {
          DoubleEntryEngine.assertEtbDebtEligible(
            debt: match.first,
            accounts: _state.accounts,
            entries: _state.journalEntries,
            postings: _state.postings,
            allocations: _state.settlementAllocations,
          );
        }
      }
      await _repository.addCommitment(commitment);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> updateCommitment(CommitmentModel commitment) async {
    _state = _state.copyWith(clearError: true);
    try {
      final linkedAccId = commitment.linkedAccountId?.trim();
      final linkedDebtId = commitment.linkedDebtId?.trim();
      if (linkedAccId != null && linkedAccId.isNotEmpty) {
        _preflightAssertEtbAccountIfLoaded(
          linkedAccId,
          roleLabel: 'Linked account',
        );
      }
      if (linkedDebtId != null &&
          linkedDebtId.isNotEmpty &&
          _state.journalEntries.isNotEmpty) {
        final match = _state.debts.where((d) => d.id == linkedDebtId);
        if (match.isNotEmpty) {
          DoubleEntryEngine.assertEtbDebtEligible(
            debt: match.first,
            accounts: _state.accounts,
            entries: _state.journalEntries,
            postings: _state.postings,
            allocations: _state.settlementAllocations,
          );
        }
      }
      await _repository.updateCommitment(commitment);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<bool> linkCommitmentToAccount({
    required String commitmentId,
    required String accountId,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      _preflightAssertEtbAccountIfLoaded(
        accountId,
        roleLabel: 'Linked account',
      );
      await _repository.linkCommitmentToEtbAccount(
        commitmentId: commitmentId,
        accountId: accountId,
      );
      await _refreshAccountsAndLedger();
      return true;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return false;
    }
  }

  Future<void> deleteCommitment(String commitmentId) async {
    _state = _state.copyWith(clearError: true);
    try {
      await _repository.deleteCommitment(commitmentId);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<CommitmentSettlementModel?> recordCommitmentSettlement({
    required String commitmentId,
    required String accountId,
    required int amountCents,
    String? categoryId,
    CalendarDate? settledDate,
    String? note,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      _preflightAssertEtbAccountIfLoaded(
        accountId,
        roleLabel: 'Settlement account',
      );
      final saved = await _repository.recordCommitmentSettlement(
        commitmentId: commitmentId,
        accountId: accountId,
        amountCents: amountCents,
        categoryId: categoryId,
        settledDate: settledDate,
        note: note,
      );
      await _refreshAccountsAndLedger();
      return saved;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<void> voidCommitmentSettlement({
    required String settlementId,
    required String reason,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      await _repository.voidCommitmentSettlement(
        settlementId: settlementId,
        reason: reason,
      );
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> markLegacyCommitmentUnpaid(String commitmentId) async {
    _state = _state.copyWith(clearError: true);
    try {
      await _repository.markLegacyCommitmentUnpaid(commitmentId);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> markCommitmentPaidWithPosting({
    required String commitmentId,
    required String accountId,
    String? categoryId,
    CalendarDate? paidDate,
    String? note,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      _preflightAssertSpendableEtbAccountIfLoaded(
        accountId,
        roleLabel: 'Payment account',
      );
      await _repository.markCommitmentPaidWithPosting(
        commitmentId: commitmentId,
        accountId: accountId,
        categoryId: categoryId,
        paidDate: paidDate,
        note: note,
      );
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  @Deprecated('Use markCommitmentPaidWithPosting.')
  Future<void> markCommitmentPaid(String id, {bool logExpense = true}) async {
    try {
      // ignore: deprecated_member_use_from_same_package
      await _repository.markCommitmentPaid(
        id,
        createExpenseTransaction: logExpense,
      );
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> addSavingsGoal(SavingsGoalModel goal) async {
    _state = _state.copyWith(clearError: true);
    try {
      final vaultId = goal.linkedAccountId?.trim();
      if (vaultId != null && vaultId.isNotEmpty) {
        _preflightAssertEtbAccountIfLoaded(
          vaultId,
          roleLabel: 'Vault account',
        );
      }
      await _repository.createSavingsGoal(goal);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> updateSavingsGoal(SavingsGoalModel goal) async {
    _state = _state.copyWith(clearError: true);
    try {
      final vaultId = goal.linkedAccountId?.trim();
      if (vaultId != null && vaultId.isNotEmpty) {
        _preflightAssertEtbAccountIfLoaded(
          vaultId,
          roleLabel: 'Vault account',
        );
      }
      await _repository.updateSavingsGoal(goal);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> deleteSavingsGoal(String goalId) async {
    _state = _state.copyWith(clearError: true);
    try {
      await _repository.deleteSavingsGoal(goalId);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<SavingsGoalModel?> releaseAndArchiveSavingsGoal(String goalId) async {
    _state = _state.copyWith(clearError: true);
    try {
      final archived = await _repository.releaseAndArchiveSavingsGoal(goalId);
      await _refreshAccountsAndLedger();
      return archived;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<void> fundSavingsGoal({
    required String goalId,
    required int deltaCents,
    String? sourceAccountId,
    CalendarDate? date,
    String? note,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      if (sourceAccountId != null && sourceAccountId.trim().isNotEmpty) {
        _preflightAssertEtbAccountIfLoaded(
          sourceAccountId.trim(),
          roleLabel: 'Source account',
        );
      }
      await _repository.fundSavingsGoal(
        goalId: goalId,
        deltaCents: deltaCents,
        sourceAccountId: sourceAccountId,
        date: date,
        note: note,
      );
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> adjustSavingsAllocation(
    String id,
    int deltaCents, {
    String? sourceAccountId,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      await _repository.fundSavingsGoal(
        goalId: id,
        deltaCents: deltaCents,
        sourceAccountId: sourceAccountId,
      );
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  // --- Party & Debt Workflows ---

  Future<String> ensurePartyId(String name, {String? phone}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Party name cannot be empty.');
    }
    final match = _state.parties
        .where((p) => p.name.toLowerCase() == trimmed.toLowerCase());
    if (match.isNotEmpty) return match.first.id;

    final now = EthiopiaClock.nowUtc();
    final newParty = PartyModel(
      id: 'party-${_uuid.v4()}',
      name: trimmed,
      phone: phone?.trim(),
      createdAt: now,
    );
    await _repository.createParty(newParty);
    await _refreshAccountsAndLedger();
    return newParty.id;
  }

  Future<PartyModel?> createParty({
    required String name,
    String? phone,
    String? notes,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      final party = PartyModel(
        id: 'party-${_uuid.v4()}',
        name: name.trim(),
        phone: phone?.trim(),
        notes: notes?.trim(),
      );
      final saved = await _repository.createParty(party);
      await _refreshAccountsAndLedger();
      return saved;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<void> updateParty(PartyModel party) async {
    _state = _state.copyWith(clearError: true);
    try {
      await _repository.updateParty(party);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> archiveParty(String id) async {
    _state = _state.copyWith(clearError: true);
    try {
      await _repository.archiveParty(id);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<DebtModel?> lendMoney({
    required String partyId,
    required String sourceAccountId,
    required int amountCents,
    required CalendarDate date,
    CalendarDate? movementDate,
    CalendarDate? dueDate,
    required String description,
    String? note,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      if (amountCents <= 0) {
        throw ArgumentError('Loan amount must be strictly greater than 0.');
      }
      _preflightAssertSpendableEtbAccountIfLoaded(
        sourceAccountId,
        roleLabel: 'Source account',
      );
      final entryId = 'entry-lend-${_uuid.v4()}';
      final debtId = 'debt-${_uuid.v4()}';
      final payload = DoubleEntryEngine.buildLendMoney(
        entryId: entryId,
        debtId: debtId,
        partyId: partyId,
        receivableAccountId: SystemControlAccounts.receivable,
        sourceAssetAccountId: sourceAccountId,
        amountCents: amountCents,
        date: date.toIsoString(),
        movementDate: movementDate?.toIsoString(),
        dueDate: dueDate?.toIsoString(),
        description: description.trim(),
        note: note,
      );
      final saved = await _repository.recordDebtWithEntry(
        entry: payload['entry'] as JournalEntryModel,
        postings: payload['postings'] as List<PostingModel>,
        debt: payload['debt'] as DebtModel,
      );
      await _refreshAccountsAndLedger();
      return saved;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<DebtModel?> borrowMoney({
    required String partyId,
    required String destinationAccountId,
    required int amountCents,
    required CalendarDate date,
    CalendarDate? movementDate,
    CalendarDate? dueDate,
    required String description,
    String? note,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      if (amountCents <= 0) {
        throw ArgumentError('Loan amount must be strictly greater than 0.');
      }
      _preflightAssertSpendableEtbAccountIfLoaded(
        destinationAccountId,
        roleLabel: 'Destination account',
      );
      final entryId = 'entry-borrow-${_uuid.v4()}';
      final debtId = 'debt-${_uuid.v4()}';
      final payload = DoubleEntryEngine.buildBorrowMoney(
        entryId: entryId,
        debtId: debtId,
        partyId: partyId,
        destAssetAccountId: destinationAccountId,
        payableAccountId: SystemControlAccounts.payable,
        amountCents: amountCents,
        date: date.toIsoString(),
        movementDate: movementDate?.toIsoString(),
        dueDate: dueDate?.toIsoString(),
        description: description.trim(),
        note: note,
      );
      final saved = await _repository.recordDebtWithEntry(
        entry: payload['entry'] as JournalEntryModel,
        postings: payload['postings'] as List<PostingModel>,
        debt: payload['debt'] as DebtModel,
      );
      await _refreshAccountsAndLedger();
      return saved;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<void> recordDoubleEntrySettlement({
    required DebtModel debt,
    required String settlementAssetAccountId,
    required int allocatedCents,
    int interestCents = 0,
    int feeCents = 0,
    required String settlementDate,
    required String description,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      _preflightAssertSpendableEtbAccountIfLoaded(
        settlementAssetAccountId,
        roleLabel: 'Settlement account',
      );
      if (_state.journalEntries.isNotEmpty) {
        DoubleEntryEngine.assertEtbDebtEligible(
          debt: debt,
          accounts: _state.accounts,
          entries: _state.journalEntries,
          postings: _state.postings,
          allocations: _state.settlementAllocations,
        );
      }
      final settlementEntryId = 'entry-settle-${_uuid.v4()}';
      final debtAccountId = debt.debtType == DebtType.payable
          ? SystemControlAccounts.payable
          : SystemControlAccounts.receivable;
      final res = DoubleEntryEngine.buildDebtSettlement(
        settlementEntryId: settlementEntryId,
        debt: debt,
        settlementAssetAccountId: settlementAssetAccountId,
        debtAccountId: debtAccountId,
        allocatedPrincipalCents: allocatedCents,
        interestCents: interestCents,
        interestAccountId: interestCents > 0
            ? (debt.debtType == DebtType.payable
                ? SystemControlAccounts.expense
                : SystemControlAccounts.income)
            : null,
        feeCents: feeCents,
        feeAccountId: feeCents > 0 ? SystemControlAccounts.expense : null,
        settlementDate: settlementDate,
        description: description,
      );
      await _repository.recordSettlement(
        allocation: res['allocation'] as SettlementAllocationModel,
        settlementEntry: res['entry'] as JournalEntryModel,
        settlementPostings: res['postings'] as List<PostingModel>,
        updatedDebt: res['updatedDebt'] as DebtModel,
      );
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> writeOffDebt({
    required String debtId,
    required String reason,
    CalendarDate? date,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      final debtMatches = _state.debts.where((d) => d.id == debtId);
      if (debtMatches.isNotEmpty && _state.journalEntries.isNotEmpty) {
        DoubleEntryEngine.assertEtbDebtEligible(
          debt: debtMatches.first,
          accounts: _state.accounts,
          entries: _state.journalEntries,
          postings: _state.postings,
          allocations: _state.settlementAllocations,
        );
      }
      await _repository.writeOffDebt(
        debtId: debtId,
        reason: reason,
        date: date ?? CalendarDate.today(),
      );
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<DebtModel?> voidDebtOrigin({
    required String debtId,
    required String reason,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      final updated = await _repository.voidDebtOrigin(
        debtId: debtId,
        reason: reason,
      );
      await _refreshAccountsAndLedger();
      return updated;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  // --- Budgets & Recurring Rules Workflows ---

  Future<void> upsertBudget(BudgetModel budget) async {
    _state = _state.copyWith(clearError: true);
    try {
      await _repository.upsertBudget(budget);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> deleteBudget(String budgetId) async {
    _state = _state.copyWith(clearError: true);
    try {
      await _repository.deleteBudget(budgetId);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> upsertRecurringRule(RecurringRuleModel rule) async {
    _state = _state.copyWith(clearError: true);
    try {
      final accId = rule.accountId?.trim();
      final destId = rule.destinationAccountId?.trim();
      final debtId = rule.linkedDebtId?.trim();
      if (accId != null && accId.isNotEmpty) {
        _preflightAssertEtbAccountIfLoaded(accId, roleLabel: 'Rule account');
      }
      if (destId != null && destId.isNotEmpty) {
        _preflightAssertEtbAccountIfLoaded(
          destId,
          roleLabel: 'Destination account',
        );
      }
      if (debtId != null &&
          debtId.isNotEmpty &&
          _state.journalEntries.isNotEmpty) {
        final match = _state.debts.where((d) => d.id == debtId);
        if (match.isNotEmpty) {
          DoubleEntryEngine.assertEtbDebtEligible(
            debt: match.first,
            accounts: _state.accounts,
            entries: _state.journalEntries,
            postings: _state.postings,
            allocations: _state.settlementAllocations,
          );
        }
      }
      await _repository.upsertRecurringRule(rule);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<RecurringRuleModel?> pauseRecurringRule(String ruleId) async {
    _state = _state.copyWith(clearError: true);
    try {
      final updated = await _repository.pauseRecurringRule(ruleId);
      await _refreshAccountsAndLedger();
      return updated;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<RecurringRuleModel?> resumeRecurringRule(
    String ruleId, {
    CalendarDate? today,
  }) async {
    _state = _state.copyWith(clearError: true);
    try {
      final updated =
          await _repository.resumeRecurringRule(ruleId, today: today);
      await _refreshAccountsAndLedger();
      return updated;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<RecurringRuleModel?> skipNextOccurrence(String ruleId) async {
    _state = _state.copyWith(clearError: true);
    try {
      final updated = await _repository.skipNextOccurrence(ruleId);
      await _refreshAccountsAndLedger();
      return updated;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<void> deleteRecurringRule(String ruleId) async {
    _state = _state.copyWith(clearError: true);
    try {
      await _repository.deleteRecurringRule(ruleId);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<int> processDueRecurringRules({CalendarDate? asOfDate}) async {
    try {
      final count = await _repository.processDueRecurringRules(
        asOfDate: asOfDate ?? CalendarDate.today(),
      );
      if (count > 0) {
        await _refreshAccountsAndLedger();
      }
      return count;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return 0;
    }
  }

  // --- Setup Workflows ---

  Future<void> completeSetup(List<AccountModel> setupAccounts) async {
    try {
      for (final acc in setupAccounts) {
        if (!acc.isSystem && !DoubleEntryEngine.isEtb(acc.currencyCode)) {
          throw DoubleEntryValidationError(
            'First-release reporting supports ETB accounts only; account '
            '"${acc.name}" (${acc.currencyCode}) cannot be created.',
          );
        }
      }
      await _repository.completeFinanceSetup(setupAccounts);
      await _refreshAccountsAndLedger();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> dismissSetupWizard() async {
    try {
      await _repository.setFinanceSetupCompleted(true);
      _state = _state.copyWith(isSetupCompleted: true, clearError: true);
      notifyListeners();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  Future<void> resetSetup() async {
    try {
      await _repository.setFinanceSetupCompleted(false);
      _state = _state.copyWith(isSetupCompleted: false, clearError: true);
      notifyListeners();
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
    }
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    super.dispose();
  }
}
