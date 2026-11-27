import 'dart:async';
import 'package:flutter/material.dart';

import '../../../application/daily_rhythm/daily_rhythm_controller.dart';
import '../../../application/finance/finance_controller.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/daily_rhythm/daily_rhythm_workflows.dart';
import '../../../domain/finance/double_entry_engine.dart';
import '../../../domain/finance/finance_models.dart';
import '../../widgets/daily_rhythm_workflow_widgets.dart';
import '../../widgets/shared_ui_widgets.dart';
import 'finance_composer_sheet.dart';
import 'finance_formatters.dart';

/// Stage 4.9 Transactions & Ledger Tab: powered directly by authoritative
/// [JournalEntryModel] and [PostingModel] records with search, filters,
/// audit detail inspection, correction/reversal, and void/unvoid.
class FinanceTransactionsTab extends StatefulWidget {
  final FinanceController controller;
  final DailyRhythmController? dailyRhythmController;

  const FinanceTransactionsTab({
    super.key,
    required this.controller,
    this.dailyRhythmController,
  });

  @override
  State<FinanceTransactionsTab> createState() => _FinanceTransactionsTabState();
}

class _FinanceTransactionsTabState extends State<FinanceTransactionsTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _showVoided = false;
  bool _showLegacyEntries = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.controller.state.searchQuery;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final categoryById = {for (final c in state.categories) c.id: c};
    final accountById = {for (final a in state.accounts) a.id: a};
    final postingsByEntry = <String, List<PostingModel>>{};
    for (final p in state.postings) {
      postingsByEntry.putIfAbsent(p.entryId, () => []).add(p);
    }

    final filtered = _filterEntries(
      entries: state.journalEntries,
      postingsByEntry: postingsByEntry,
      categoryById: categoryById,
      accountById: accountById,
    );
    final classifications = state.classificationsByEntryId;
    final etbFiltered = filtered
        .where((e) => (classifications[e.id] ?? state.classifyEntry(e)).isEligibleEtb)
        .toList(growable: false);
    final legacyFiltered = filtered
        .where((e) => !(classifications[e.id] ?? state.classifyEntry(e)).isEligibleEtb)
        .toList(growable: false);

    final visibleCount = state.txDisplayLimit < etbFiltered.length
        ? state.txDisplayLimit
        : etbFiltered.length;
    final visibleEntries = etbFiltered.take(visibleCount).toList(growable: false);

    return Column(
      children: [
        DaywellSearchFilterBar(
          searchController: _searchCtrl,
          searchHintText: 'Search ledger description, category, or account...',
          onSearchChanged: widget.controller.setSearchQuery,
          onSearchCleared: () {
            _searchCtrl.clear();
            widget.controller.setSearchQuery('');
          },
          trailingAction: DaywellButton(
            label: '+ Record',
            size: DaywellButtonSize.compact,
            onPressed: () => FinanceComposerSheet.show(
              context,
              controller: widget.controller,
            ),
          ),
          hasActiveFilters: state.isAnyFilterActive || _showVoided,
          activeSummary: '${etbFiltered.length} ETB entries',
          onClearFilters: () {
            _searchCtrl.clear();
            setState(() {
              _showVoided = false;
            });
            widget.controller.clearAllFilters();
          },
          filterControls: [
            _compactTypeChip('all', 'All'),
            _compactTypeChip('expense', 'Expense'),
            _compactTypeChip('income', 'Income'),
            _compactTypeChip('transfer', 'Transfer'),
            _compactTypeChip('split', 'Split'),
            _compactTypeChip('debt', 'Debt'),
            _compactTypeChip('settlement', 'Settlement'),
            FilterChip(
              label: const Text('Show Voided'),
              selected: _showVoided,
              onSelected: (val) => setState(() => _showVoided = val),
            ),
            _buildAccountFilterDropdown(context),
            _buildDateFilterDropdown(context),
          ],
        ),
        Expanded(
          child: _buildTransactionsBody(
            context,
            state: state,
            filtered: etbFiltered,
            legacyFiltered: legacyFiltered,
            visibleEntries: visibleEntries,
            visibleCount: visibleCount,
            postingsByEntry: postingsByEntry,
            categoryById: categoryById,
            accountById: accountById,
          ),
        ),
      ],
    );
  }

  Widget _buildFinanceCloseCard(BuildContext context) {
    final drCtrl = widget.dailyRhythmController!;
    final state = widget.controller.state;
    return ListenableBuilder(
      listenable: drCtrl,
      builder: (context, _) {
        final today = CalendarDate.today();
        final todayIso = today.toIsoString();
        final summary = DailyRhythmWorkflows.inspectFinanceDay(
          entries: state.journalEntries,
          targetDateIso: todayIso,
          today: today,
        );
        return DailyFinanceCloseCard(
          summary: summary,
          record: drCtrl.state.dayFor(todayIso),
          isShowingTodayFilter: state.datePresetFilter == 'today',
          isSaving: drCtrl.state.isSaving,
          errorMessage: drCtrl.state.errorMessage,
          onFilterToday: () => widget.controller.setDatePresetFilter('today'),
          onConfirmClose: () async {
            final res = await drCtrl.confirmFinanceClose(
              dateIso: todayIso,
              entries: state.journalEntries,
              today: today,
            );
            if (!context.mounted || !res.applied) return;
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  summary.hasTransactions
                      ? "Today's Finance transactions confirmed."
                      : 'Confirmed no transactions today.',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTransactionsBody(
    BuildContext context, {
    required dynamic state,
    required List<JournalEntryModel> filtered,
    required List<JournalEntryModel> legacyFiltered,
    required List<JournalEntryModel> visibleEntries,
    required int visibleCount,
    required Map<String, List<PostingModel>> postingsByEntry,
    required Map<String, TransactionCategoryModel> categoryById,
    required Map<String, AccountModel> accountById,
  }) {
    final hasCloseCard = widget.dailyRhythmController != null;
    final hasActiveFilters = state.isAnyFilterActive || _showVoided;
    final hasLegacySection = legacyFiltered.isNotEmpty;

    if (visibleEntries.isEmpty && !hasLegacySection) {
      final emptyState = DaywellEmptyState(
        icon: Icons.receipt_long_outlined,
        message: hasActiveFilters
            ? 'No ledger entries match these filters'
            : 'No ledger entries recorded yet',
        subtitle:
            'Record expenses, income, transfers, split expenses, or settlements.',
        actionLabel: hasActiveFilters ? 'Clear Filters' : 'Record Entry',
        onActionPressed: hasActiveFilters
            ? () {
                _searchCtrl.clear();
                setState(() {
                  _showVoided = false;
                });
                widget.controller.clearAllFilters();
              }
            : () => FinanceComposerSheet.show(
                  context,
                  controller: widget.controller,
                ),
      );
      if (!hasCloseCard) return emptyState;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFinanceCloseCard(context),
            const SizedBox(height: SharedDesignTokens.spacingMd),
            emptyState,
          ],
        ),
      );
    }

    final hasMoreButton = filtered.length > visibleCount;
    return ListView(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      children: [
        if (hasCloseCard) ...[
          _buildFinanceCloseCard(context),
          const SizedBox(height: SharedDesignTokens.spacingSm),
        ],
        if (visibleEntries.isEmpty)
          DaywellCard(
            padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
            child: Center(
              child: Text(
                hasActiveFilters
                    ? 'No matching ETB ledger entries.'
                    : 'No ETB ledger entries recorded yet.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.daywellColors.textSecondary,
                    ),
              ),
            ),
          )
        else ...[
          for (final entry in visibleEntries) ...[
            _buildEntryCard(
              context,
              entry: entry,
              postings: postingsByEntry[entry.id] ?? const <PostingModel>[],
              categoryById: categoryById,
              accountById: accountById,
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
          ],
          if (hasMoreButton)
            Center(
              child: DaywellButton(
                label: 'Load More (${filtered.length - visibleCount} remaining)',
                variant: DaywellButtonVariant.outlined,
                onPressed: () => widget.controller
                    .setTxDisplayLimit(state.txDisplayLimit + 25),
              ),
            ),
        ],
        if (hasLegacySection) ...[
          const SizedBox(height: SharedDesignTokens.spacingSm),
          _buildLegacyEntriesCard(
            context,
            legacyEntries: legacyFiltered,
            postingsByEntry: postingsByEntry,
            categoryById: categoryById,
            accountById: accountById,
          ),
        ],
      ],
    );
  }

  Widget _buildLegacyEntriesCard(
    BuildContext context, {
    required List<JournalEntryModel> legacyEntries,
    required Map<String, List<PostingModel>> postingsByEntry,
    required Map<String, TransactionCategoryModel> categoryById,
    required Map<String, AccountModel> accountById,
  }) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
            onTap: () =>
                setState(() => _showLegacyEntries = !_showLegacyEntries),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Legacy Non-ETB Entries (${legacyEntries.length}) · Read-Only',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Historical non-ETB or unclassified entries preserved separately and excluded from ETB totals',
                          style: textTheme.bodySmall?.copyWith(
                            color: semantic.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _showLegacyEntries ? Icons.expand_less : Icons.expand_more,
                    color: semantic.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_showLegacyEntries) ...[
            const Divider(),
            for (final entry in legacyEntries) ...[
              _buildEntryCard(
                context,
                entry: entry,
                postings: postingsByEntry[entry.id] ?? const <PostingModel>[],
                categoryById: categoryById,
                accountById: accountById,
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
            ],
          ],
        ],
      ),
    );
  }

  Widget _compactTypeChip(String value, String label) {
    final selected = widget.controller.state.typeFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => widget.controller.setTypeFilter(value),
    );
  }

  Widget _buildAccountFilterDropdown(BuildContext context) {
    final state = widget.controller.state;
    final accounts = state.etbUserAccounts;
    return DropdownButton<String>(
      value: state.accountFilter == 'all' ||
              accounts.any((a) => a.id == state.accountFilter)
          ? state.accountFilter
          : 'all',
      underline: const SizedBox.shrink(),
      items: [
        const DropdownMenuItem(value: 'all', child: Text('All Accounts')),
        for (final a in accounts)
          DropdownMenuItem(
            value: a.id,
            child: Text(a.name),
          ),
      ],
      onChanged: (val) {
        if (val != null) widget.controller.setAccountFilter(val);
      },
    );
  }

  Widget _buildDateFilterDropdown(BuildContext context) {
    final state = widget.controller.state;
    return DropdownButton<String>(
      value: state.datePresetFilter,
      underline: const SizedBox.shrink(),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('Any Date')),
        DropdownMenuItem(value: 'today', child: Text('Today')),
        DropdownMenuItem(value: 'yesterday', child: Text('Yesterday')),
        DropdownMenuItem(value: 'this_week', child: Text('Last 7 Days')),
        DropdownMenuItem(value: 'this_month', child: Text('This Month')),
        DropdownMenuItem(value: 'custom', child: Text('Custom Range...')),
      ],
      onChanged: (val) async {
        if (val == null) return;
        if (val == 'custom') {
          final today = CalendarDate.today();
          final start = await FinanceUiFormatters.pickCalendarDate(
            context,
            initialDate: state.customStartDate ?? today.addDays(-30),
          );
          if (start == null || !context.mounted) return;
          final end = await FinanceUiFormatters.pickCalendarDate(
            context,
            initialDate: state.customEndDate ?? today,
            firstDate: start,
          );
          if (end == null) return;
          widget.controller.setCustomDateRange(start, end);
        } else {
          widget.controller.setDatePresetFilter(val);
        }
      },
    );
  }

  List<JournalEntryModel> _filterEntries({
    required List<JournalEntryModel> entries,
    required Map<String, List<PostingModel>> postingsByEntry,
    required Map<String, TransactionCategoryModel> categoryById,
    required Map<String, AccountModel> accountById,
  }) {
    final state = widget.controller.state;
    final today = CalendarDate.today();
    final query = state.searchQuery.trim().toLowerCase();

    final list = entries.where((entry) {
      if (!_showVoided && entry.isVoided) return false;
      final ps = postingsByEntry[entry.id] ?? const <PostingModel>[];

      if (state.accountFilter != 'all' &&
          !ps.any((p) => p.accountId == state.accountFilter)) {
        return false;
      }

      if (!_matchesTypeFilter(entry, ps, state.typeFilter)) {
        return false;
      }

      final entryDate = SharedDateFormatter.tryParseFlexibleToCalendarDate(
        entry.occurrenceDate,
      );
      if (entryDate != null && !_matchesDateFilter(entryDate, today, state)) {
        return false;
      }

      if (query.isNotEmpty) {
        final catNames = ps
            .map((p) => FinanceUiFormatters.formatCategoryBreadcrumb(
                  p.categoryId,
                  categoryById,
                ))
            .join(' ')
            .toLowerCase();
        final accNames = ps
            .where((p) =>
                !SystemControlAccounts.isSystemControlId(p.accountId) &&
                !(accountById[p.accountId]?.isSystem ?? false))
            .map((p) => accountById[p.accountId]?.name ?? '')
            .join(' ')
            .toLowerCase();
        final transferLabel = entry.entryType == EntryType.transfer
            ? (() {
                final ep = DoubleEntryEngine.resolveTransferDisplayEndpoints(
                  postings: ps,
                  accounts: accountById.values,
                );
                return ep.isUnambiguous
                    ? '${ep.sourceName} → ${ep.destinationName}'
                    : ep.fallbackAccountNames.join(' · ');
              })().toLowerCase()
            : '';
        final resolvedDesc =
            DoubleEntryEngine.resolveDescriptionPreservingLegacyNote(
          description: entry.description,
          legacyNote: DoubleEntryEngine.resolveUnambiguousHistoricalPostingNote(
            ps,
          ),
        );
        final haystack =
            '${resolvedDesc.toLowerCase()} $catNames $accNames $transferLabel';
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      final dateCmp = b.occurrenceDate.compareTo(a.occurrenceDate);
      return dateCmp != 0 ? dateCmp : b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  bool _matchesTypeFilter(
    JournalEntryModel entry,
    List<PostingModel> postings,
    String filter,
  ) {
    if (filter == 'all') return true;
    if (filter == 'transfer') return entry.entryType == EntryType.transfer;
    if (filter == 'split') return entry.entryType == EntryType.splitExpense;
    if (filter == 'debt') return entry.entryType == EntryType.debtIssuance;
    if (filter == 'settlement') return entry.entryType == EntryType.settlement;
    if (filter == 'income') {
      return postings.any(
        (p) =>
            p.accountId == SystemControlAccounts.income &&
            p.direction == PostingDirection.credit,
      );
    }
    if (filter == 'expense') {
      return entry.entryType != EntryType.transfer &&
          postings.any(
            (p) =>
                p.accountId == SystemControlAccounts.expense &&
                p.direction == PostingDirection.debit,
          );
    }
    return true;
  }

  bool _matchesDateFilter(
    CalendarDate date,
    CalendarDate today,
    dynamic state,
  ) {
    switch (state.datePresetFilter as String) {
      case 'today':
        return date == today;
      case 'yesterday':
        return date == today.addDays(-1);
      case 'this_week':
        return date.jdn >= today.addDays(-6).jdn && date.jdn <= today.jdn;
      case 'this_month':
        return date.year == today.year && date.month == today.month;
      case 'custom':
        final start = state.customStartDate as CalendarDate?;
        final end = state.customEndDate as CalendarDate?;
        if (start != null && date.jdn < start.jdn) return false;
        if (end != null && date.jdn > end.jdn) return false;
        return true;
      default:
        return true;
    }
  }

  Widget _buildEntryCard(
    BuildContext context, {
    required JournalEntryModel entry,
    required List<PostingModel> postings,
    required Map<String, TransactionCategoryModel> categoryById,
    required Map<String, AccountModel> accountById,
  }) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final classification = widget.controller.state.classifyEntry(entry);

    final isIncome = postings.any(
      (p) =>
          p.accountId == SystemControlAccounts.income &&
          p.direction == PostingDirection.credit,
    );
    final isExpense = entry.entryType != EntryType.transfer &&
        postings.any(
          (p) =>
              p.accountId == SystemControlAccounts.expense &&
              p.direction == PostingDirection.debit,
        );

    final expenseSummary = DoubleEntryEngine.summarizeDirectExpense(
      entry: entry,
      postings: postings,
      accounts: accountById.values,
    );
    final transferEndpoints = entry.entryType == EntryType.transfer
        ? DoubleEntryEngine.resolveTransferDisplayEndpoints(
            postings: postings,
            accounts: accountById.values,
          )
        : null;

    final primaryPosting = postings.firstWhere(
      (p) =>
          p.categoryId != null &&
          (!expenseSummary.isDirectExpense ||
              !DoubleEntryEngine.isExpenseFeePosting(p)),
      orElse: () => postings.isNotEmpty
          ? postings.first
          : PostingModel(
              id: 'empty',
              entryId: entry.id,
              accountId: '',
              amountCents: 0,
              direction: PostingDirection.debit,
              accountMovementDate: entry.occurrenceDate,
            ),
    );
    final totalDebit = postings
        .where((p) => p.direction == PostingDirection.debit)
        .fold<int>(0, (s, p) => s + p.amountCents);

    final String userAccountsInvolved;
    if (transferEndpoints != null) {
      userAccountsInvolved = transferEndpoints.isUnambiguous
          ? '${transferEndpoints.sourceName} → ${transferEndpoints.destinationName}'
          : transferEndpoints.fallbackAccountNames.join(' · ');
    } else if (expenseSummary.isDirectExpense &&
        expenseSummary.paidAccountId != null) {
      userAccountsInvolved =
          accountById[expenseSummary.paidAccountId!]?.name ??
              expenseSummary.paidAccountId!;
    } else {
      userAccountsInvolved = postings
          .where((p) =>
              !SystemControlAccounts.isSystemControlId(p.accountId) &&
              !(accountById[p.accountId]?.isSystem ?? false))
          .map((p) => accountById[p.accountId]?.name ?? p.accountId)
          .toSet()
          .join(' · ');
    }

    final primaryCategoryId = expenseSummary.isDirectExpense
        ? expenseSummary.primaryCategoryId
        : primaryPosting.categoryId;
    final categoryBreadcrumb = primaryCategoryId != null
        ? FinanceUiFormatters.formatCategoryBreadcrumb(
            primaryCategoryId,
            categoryById,
          )
        : FinanceUiFormatters.formatEntryTypeLabel(entry.entryType);

    final Color amountColor = entry.isVoided
        ? semantic.textMuted
        : classification.needsCurrencyReview
            ? semantic.warning
            : isIncome
                ? semantic.income
                : (entry.entryType == EntryType.transfer
                    ? semantic.transfer
                    : (isExpense ? semantic.expense : semantic.textPrimary));

    final isMixedMultiCurrency = classification.touchedCurrencies.length > 1;
    final signPrefix = isIncome ? '+' : (isExpense ? '-' : '');
    final displayAmountCents = expenseSummary.isDirectExpense
        ? expenseSummary.totalOutflowCents
        : totalDebit;
    final displayCurrency = classification.nativeCurrencyCode ??
        (classification.touchedCurrencies.length == 1 &&
                classification.touchedCurrencies.first != 'UNVERIFIED'
            ? classification.touchedCurrencies.first
            : null);
    final String amountDisplay;
    if (isMixedMultiCurrency) {
      final legDisplays = postings
          .where((p) =>
              !SystemControlAccounts.isSystemControlId(p.accountId) &&
              !(accountById[p.accountId]?.isSystem ?? false))
          .map((p) => FinanceUiFormatters.formatCurrencyCents(
                p.amountCents,
                currencyCode: accountById[p.accountId]?.currencyCode,
              ))
          .toList(growable: false);
      amountDisplay = legDisplays.isNotEmpty
          ? legDisplays.join(' / ')
          : 'Mixed (${classification.touchedCurrencies.join(' / ')})';
    } else {
      final formatted = FinanceUiFormatters.formatCurrencyCents(
        displayAmountCents,
        currencyCode: displayCurrency,
      );
      amountDisplay = '$signPrefix$formatted';
    }
    final showExpenseFeeDetail = expenseSummary.isDirectExpense &&
        expenseSummary.feeCents > 0 &&
        !isMixedMultiCurrency;
    final formattedExpenseFee = showExpenseFeeDetail
        ? FinanceUiFormatters.formatCurrencyCents(
            expenseSummary.feeCents,
            currencyCode: displayCurrency,
          )
        : null;
    final formattedExpensePrincipal = showExpenseFeeDetail
        ? FinanceUiFormatters.formatCurrencyCents(
            expenseSummary.principalCents,
            currencyCode: displayCurrency,
          )
        : null;

    final dateObj = SharedDateFormatter.tryParseFlexibleToCalendarDate(
      entry.occurrenceDate,
    );
    final dateText = dateObj != null
        ? SharedDateFormatter.formatDual(dateObj, useAmharic: false)
        : entry.occurrenceDate;

    return DaywellCard(
      onTap: () => _openEntryAuditSheet(
        context,
        entry: entry,
        postings: postings,
        categoryById: categoryById,
        accountById: accountById,
      ),
      padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DoubleEntryEngine.resolveDescriptionPreservingLegacyNote(
                        description: entry.description,
                        legacyNote: DoubleEntryEngine
                            .resolveUnambiguousHistoricalPostingNote(
                          postings,
                        ),
                      ),
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: entry.isVoided ? semantic.textMuted : null,
                        decoration:
                            entry.isVoided ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      userAccountsInvolved.isEmpty
                          ? categoryBreadcrumb
                          : '$categoryBreadcrumb · $userAccountsInvolved',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                    if (formattedExpenseFee != null &&
                        formattedExpensePrincipal != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Principal $formattedExpensePrincipal · Includes $formattedExpenseFee fee',
                        style: textTheme.labelSmall?.copyWith(
                          color: semantic.textMuted,
                        ),
                      ),
                    ],
                    if (!entry.isVoided &&
                        classification.needsCurrencyReview &&
                        classification.reason != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        classification.reason!,
                        style: textTheme.labelSmall?.copyWith(
                          color: semantic.warning,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: SharedDesignTokens.spacingSm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amountDisplay,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: amountColor,
                    ),
                  ),
                  if (formattedExpenseFee != null)
                    Text(
                      'Includes $formattedExpenseFee fee',
                      style: textTheme.labelSmall?.copyWith(
                        color: semantic.textMuted,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingXs),
          Wrap(
            spacing: SharedDesignTokens.spacingSm,
            runSpacing: SharedDesignTokens.spacingXs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                dateText,
                style:
                    textTheme.labelSmall?.copyWith(color: semantic.textMuted),
              ),
              DaywellStatusBadge(
                label:
                    FinanceUiFormatters.formatEntryTypeLabel(entry.entryType),
                tone: entry.entryType == EntryType.writeOff
                    ? DaywellStatusTone.warning
                    : DaywellStatusTone.info,
                showIcon: false,
              ),
              if (classification.isInactiveOrVoided)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: semantic.textMuted.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(
                      SharedDesignTokens.radiusSm,
                    ),
                  ),
                  child: Text(
                    'Voided',
                    style: textTheme.labelSmall?.copyWith(
                      color: semantic.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else if (classification.isExcludedNonEtb)
                DaywellStatusBadge(
                  label:
                      'Legacy (${classification.nativeCurrencyCode ?? 'Non-ETB'})',
                  tone: DaywellStatusTone.warning,
                  showIcon: false,
                )
              else if (classification.needsCurrencyReview)
                const DaywellStatusBadge(
                  label: 'Legacy · Unclassified',
                  tone: DaywellStatusTone.warning,
                  showIcon: false,
                ),
              if (DoubleEntryEngine.isRefundEntry(entry))
                const DaywellStatusBadge(
                  label: 'Refund',
                  tone: DaywellStatusTone.success,
                  showIcon: false,
                ),
              if (entry.correctedFromEntryId != null)
                const DaywellStatusBadge(
                  label: 'CORRECTED',
                  tone: DaywellStatusTone.success,
                  showIcon: false,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openEntryAuditSheet(
    BuildContext context, {
    required JournalEntryModel entry,
    required List<PostingModel> postings,
    required Map<String, TransactionCategoryModel> categoryById,
    required Map<String, AccountModel> accountById,
  }) async {
    final state = widget.controller.state;
    final classification = state.classifyEntry(entry);
    final correctCheck = DoubleEntryEngine.canCorrectEntry(
      entry: entry,
      entries: state.journalEntries,
      postings: state.postings,
      accounts: state.accounts,
      debts: state.debts,
      allocations: state.settlementAllocations,
      commitmentSettlements: state.commitmentSettlements,
    );
    final refundSummary = DoubleEntryEngine.getExpenseRefundSummary(
      originalEntryId: entry.id,
      entries: state.journalEntries,
      postings: state.postings,
      accounts: state.accounts,
      debts: state.debts,
      allocations: state.settlementAllocations,
    );
    final canEdit = correctCheck.ok;
    final canRefund =
        refundSummary.eligible && refundSummary.remainingRefundableCents > 0;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) {
        final semantic = Theme.of(sheetCtx).brightness == Brightness.dark
            ? const DaywellSemanticColors.dark()
            : const DaywellSemanticColors.light();
        final textTheme = Theme.of(sheetCtx).textTheme;
        return Padding(
          padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        DoubleEntryEngine.resolveDescriptionPreservingLegacyNote(
                          description: entry.description,
                          legacyNote: DoubleEntryEngine
                              .resolveUnambiguousHistoricalPostingNote(
                            postings,
                          ),
                        ),
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DaywellIconButton(
                      icon: Icons.close,
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: SharedDesignTokens.spacingXs),
                Text(
                  'Date: ${entry.occurrenceDate} · Type: ${entry.entryType.name}',
                  style: textTheme.bodySmall?.copyWith(
                    color: semantic.textSecondary,
                  ),
                ),
                if (entry.voidReason != null && entry.voidReason!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: SharedDesignTokens.spacingSm,
                    ),
                    child: DaywellStatusBanner(
                      title: entry.isVoided ? 'Voided Entry' : 'Audit Note',
                      message: entry.voidReason!,
                      tone: DaywellStatusTone.warning,
                    ),
                  ),
                if (!entry.isVoided && !classification.isEligibleEtb)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: SharedDesignTokens.spacingSm,
                    ),
                    child: DaywellStatusBanner(
                      title: classification.isExcludedNonEtb
                          ? 'Legacy (${classification.nativeCurrencyCode ?? 'Non-ETB'}) · Read-Only'
                          : 'Legacy Record · Read-Only',
                      message:
                          'Preserved with original amounts and excluded from ETB totals. Editing is disabled.',
                      tone: DaywellStatusTone.warning,
                    ),
                  ),
                if (!entry.isVoided &&
                    classification.isEligibleEtb &&
                    !canEdit &&
                    correctCheck.error != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: SharedDesignTokens.spacingSm,
                    ),
                    child: DaywellStatusBanner(
                      title: 'Direct Correction Unavailable',
                      message: correctCheck.error!,
                      tone: DaywellStatusTone.info,
                    ),
                  ),
                Builder(
                  builder: (_) {
                    final auditExpenseSummary =
                        DoubleEntryEngine.summarizeDirectExpense(
                      entry: entry,
                      postings: postings,
                      accounts: accountById.values,
                    );
                    if (!auditExpenseSummary.isDirectExpense ||
                        auditExpenseSummary.feeCents <= 0) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(
                        top: SharedDesignTokens.spacingSm,
                      ),
                      child: DaywellStatusBanner(
                        title: 'Expense Fee Breakdown',
                        message:
                            'Principal ${FinanceUiFormatters.formatEtbCents(auditExpenseSummary.principalCents)} + '
                            'Fee ${FinanceUiFormatters.formatEtbCents(auditExpenseSummary.feeCents)} = '
                            'Total deduction ${FinanceUiFormatters.formatEtbCents(auditExpenseSummary.totalOutflowCents)}.',
                        tone: DaywellStatusTone.info,
                      ),
                    );
                  },
                ),
                const SizedBox(height: SharedDesignTokens.spacingMd),
                Text(
                  'Balanced Ledger Postings',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: SharedDesignTokens.spacingSm),
                for (final p in postings) ...[
                  Builder(
                    builder: (_) {
                      final acc = accountById[p.accountId];
                      final isSystemAcc =
                          SystemControlAccounts.isSystemControlId(
                                  p.accountId) ||
                              (acc?.isSystem ?? false);
                      final postingCurrency = isSystemAcc
                          ? (classification.nativeCurrencyCode ??
                              (classification.touchedCurrencies.length == 1 &&
                                      classification.touchedCurrencies.first !=
                                          'UNVERIFIED'
                                  ? classification.touchedCurrencies.first
                                  : null))
                          : acc?.currencyCode;

                      return DaywellCard(
                        padding: const EdgeInsets.all(
                          SharedDesignTokens.spacingCompact,
                        ),
                        child: Row(
                          children: [
                            DaywellStatusBadge(
                              label: p.direction == PostingDirection.debit
                                  ? 'DR'
                                  : 'CR',
                              tone: p.direction == PostingDirection.debit
                                  ? DaywellStatusTone.info
                                  : DaywellStatusTone.success,
                              showIcon: false,
                            ),
                            const SizedBox(width: SharedDesignTokens.spacingSm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    acc?.name ?? p.accountId,
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (p.categoryId != null)
                                    Text(
                                      FinanceUiFormatters
                                          .formatCategoryBreadcrumb(
                                        p.categoryId,
                                        categoryById,
                                      ),
                                      style: textTheme.bodySmall?.copyWith(
                                        color: semantic.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              FinanceUiFormatters.formatCurrencyCents(
                                p.amountCents,
                                currencyCode: postingCurrency,
                              ),
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                ],
                const SizedBox(height: SharedDesignTokens.spacingMd),
                Wrap(
                  spacing: SharedDesignTokens.spacingSm,
                  runSpacing: SharedDesignTokens.spacingSm,
                  children: [
                    if (canEdit)
                      DaywellButton(
                        label: 'Correct / Edit',
                        leadingIcon: Icons.edit_outlined,
                        variant: DaywellButtonVariant.secondary,
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          FinanceComposerSheet.show(
                            context,
                            controller: widget.controller,
                            editingEntry: entry,
                          );
                        },
                      ),
                    if (canRefund)
                      DaywellButton(
                        label: 'Refund Expense',
                        leadingIcon: Icons.undo_outlined,
                        variant: DaywellButtonVariant.outlined,
                        onPressed: () async {
                          Navigator.of(sheetCtx).pop();
                          await _openExpenseRefundSheet(
                            context,
                            entry: entry,
                            summary: refundSummary,
                          );
                        },
                      ),
                    if (!entry.isVoided && classification.isEligibleEtb)
                      DaywellButton(
                        label: 'Void Entry',
                        leadingIcon: Icons.block,
                        variant: DaywellButtonVariant.destructive,
                        onPressed: () async {
                          Navigator.of(sheetCtx).pop();
                          await _promptVoidReason(context, entry);
                        },
                      )
                    else if (entry.isVoided &&
                        classification.nativeCurrencyCode == 'ETB' &&
                        classification.touchedCurrencies.length == 1)
                      DaywellButton(
                        label: 'Restore Entry',
                        leadingIcon: Icons.restore,
                        variant: DaywellButtonVariant.primary,
                        onPressed: () async {
                          Navigator.of(sheetCtx).pop();
                          await widget.controller.unvoidJournalEntry(entry.id);
                          final err = widget.controller.state.errorMessage;
                          if (err != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(err)),
                            );
                          }
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _promptVoidReason(
    BuildContext context,
    JournalEntryModel entry,
  ) async {
    final reasonCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Void Ledger Entry'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Voiding "${entry.description}" reverses its balance effect without deleting audit history.',
            ),
            const SizedBox(height: SharedDesignTokens.spacingCompact),
            DaywellTextField(
              controller: reasonCtrl,
              label: 'Void Reason',
              hintText: 'e.g. Duplicate entry or cancelled payment',
            ),
          ],
        ),
        actions: [
          DaywellButton(
            label: 'Cancel',
            variant: DaywellButtonVariant.text,
            size: DaywellButtonSize.compact,
            onPressed: () => Navigator.of(dialogCtx).pop(),
          ),
          DaywellButton(
            label: 'Void',
            variant: DaywellButtonVariant.destructive,
            size: DaywellButtonSize.compact,
            onPressed: () async {
              final reason = reasonCtrl.text.trim().isEmpty
                  ? 'Voided by user'
                  : reasonCtrl.text.trim();
              Navigator.of(dialogCtx).pop();
              await widget.controller.voidJournalEntry(entry.id, reason);
              final err = widget.controller.state.errorMessage;
              if (err != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err)),
                );
              }
            },
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
  }

  Future<void> _openExpenseRefundSheet(
    BuildContext context, {
    required JournalEntryModel entry,
    required ExpenseRefundSummary summary,
  }) async {
    final state = widget.controller.state;
    final spendableAccounts = state.activeEtbSpendableAccounts;
    if (spendableAccounts.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No active ETB liquid or credit card account available to receive the refund.',
            ),
          ),
        );
      }
      return;
    }

    String selectedAccountId = spendableAccounts.any(
      (a) => a.id == summary.originalAccountId,
    )
        ? summary.originalAccountId!
        : spendableAccounts.first.id;
    final amountCtrl = TextEditingController(
      text: FinanceUiFormatters.formatCentsAsInput(
        summary.remainingRefundableCents,
      ),
    );
    final minDate = SharedDateFormatter.parseFlexibleToCalendarDate(
      summary.originalOccurrenceDate ?? entry.occurrenceDate,
    );
    var refundDate = CalendarDate.today();
    if (refundDate.jdn < minDate.jdn) {
      refundDate = minDate;
    }
    String? validationError;
    var isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final semantic = Theme.of(sheetCtx).brightness == Brightness.dark
                ? const DaywellSemanticColors.dark()
                : const DaywellSemanticColors.light();
            final textTheme = Theme.of(sheetCtx).textTheme;

            return Padding(
              padding: EdgeInsets.only(
                left: SharedDesignTokens.spacingMd,
                right: SharedDesignTokens.spacingMd,
                top: SharedDesignTokens.spacingMd,
                bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom +
                    SharedDesignTokens.spacingMd,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Refund Expense',
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        DaywellIconButton(
                          icon: Icons.close,
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(sheetCtx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    Text(
                      '${DoubleEntryEngine.resolveDescriptionPreservingLegacyNote(description: entry.description, legacyNote: DoubleEntryEngine.resolveUnambiguousHistoricalPostingNote(state.postings.where((p) => p.entryId == entry.id).toList()))} · Remaining refundable: ${FinanceUiFormatters.formatEtbCents(summary.remainingRefundableCents)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                    if (summary.originalFeeCents > 0) ...[
                      const SizedBox(height: SharedDesignTokens.spacingCompact),
                      DaywellStatusBanner(
                        tone: DaywellStatusTone.info,
                        message:
                            'Maximum normal refund is principal only (${FinanceUiFormatters.formatEtbCents(summary.originalAmountCents)}). Bank fee (${FinanceUiFormatters.formatEtbCents(summary.originalFeeCents)}) is excluded.',
                      ),
                    ],
                    if (validationError != null) ...[
                      const SizedBox(height: SharedDesignTokens.spacingCompact),
                      DaywellStatusBanner(
                        message: validationError!,
                        tone: DaywellStatusTone.error,
                        onDismiss: () =>
                            setSheetState(() => validationError = null),
                      ),
                    ],
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    DaywellDropdownField<String>(
                      label: 'Refund To Account',
                      value: selectedAccountId,
                      items: [
                        for (final acc in spendableAccounts)
                          DropdownMenuItem(
                            value: acc.id,
                            child: Text(
                              '${acc.name} (${FinanceUiFormatters.formatEtbCents(state.getAccountBalanceCents(acc))})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => selectedAccountId = val);
                        }
                      },
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    DaywellTextField(
                      controller: amountCtrl,
                      label: 'Refund Amount (ETB)',
                      hintText: '0.00',
                      isRequired: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    Wrap(
                      spacing: SharedDesignTokens.spacingSm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Refund Date: ${SharedDateFormatter.formatDual(refundDate, useAmharic: false)}',
                          style: textTheme.bodySmall?.copyWith(
                            color: semantic.textSecondary,
                          ),
                        ),
                        DaywellButton(
                          label: 'Pick Date',
                          variant: DaywellButtonVariant.text,
                          size: DaywellButtonSize.compact,
                          onPressed: () async {
                            final picked =
                                await FinanceUiFormatters.pickCalendarDate(
                              sheetCtx,
                              initialDate: refundDate,
                              firstDate: minDate,
                            );
                            if (picked != null && sheetCtx.mounted) {
                              setSheetState(() => refundDate = picked);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingMd),
                    DaywellButton(
                      label: 'Record Expense Refund',
                      leadingIcon: Icons.undo_outlined,
                      isLoading: isSaving,
                      fullWidth: true,
                      onPressed: isSaving
                          ? null
                          : () async {
                              final refundCents =
                                  FinanceUiFormatters.parseEtbToCents(
                                amountCtrl.text,
                              );
                              if (refundCents == null || refundCents <= 0) {
                                setSheetState(() {
                                  validationError =
                                      'Enter a refund amount greater than 0.';
                                });
                                return;
                              }
                              if (refundCents >
                                  summary.remainingRefundableCents) {
                                setSheetState(() {
                                  validationError =
                                      'Refund exceeds remaining refundable balance (${FinanceUiFormatters.formatEtbCents(summary.remainingRefundableCents)}).';
                                });
                                return;
                              }
                              setSheetState(() {
                                isSaving = true;
                                validationError = null;
                              });
                              final created =
                                  await widget.controller.recordExpenseRefund(
                                originalEntryId: entry.id,
                                refundAccountId: selectedAccountId,
                                refundCents: refundCents,
                                date: refundDate,
                              );
                              if (!sheetCtx.mounted) return;
                              if (created == null) {
                                setSheetState(() {
                                  isSaving = false;
                                  validationError =
                                      widget.controller.state.errorMessage ??
                                          'Could not record refund.';
                                });
                                return;
                              }
                              Navigator.of(sheetCtx).pop();
                            },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    amountCtrl.dispose();
  }
}
