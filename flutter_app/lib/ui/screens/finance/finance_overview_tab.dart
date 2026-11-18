import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../application/finance/finance_controller.dart';
import '../../../application/finance/finance_state.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/finance/double_entry_engine.dart';
import '../../../domain/finance/finance_models.dart';
import '../../widgets/shared_ui_widgets.dart';
import 'finance_composer_sheet.dart';
import 'finance_formatters.dart';

/// Stage 4.8 Overview Tab: Safe Harbor liquidity breakdown, Net Financial Position,
/// Account Management (Liquid, Vaults, Credit Cards), and Hierarchical Categories Manager.
class FinanceOverviewTab extends StatefulWidget {
  final FinanceController controller;
  final VoidCallback? onOpenTransactions;
  final VoidCallback? onOpenPlan;
  final VoidCallback? onOpenReports;

  const FinanceOverviewTab({
    super.key,
    required this.controller,
    this.onOpenTransactions,
    this.onOpenPlan,
    this.onOpenReports,
  });

  @override
  State<FinanceOverviewTab> createState() => _FinanceOverviewTabState();
}

class _FinanceOverviewTabState extends State<FinanceOverviewTab> {
  static const Uuid _uuid = Uuid();
  bool _showArchivedAccounts = false;
  String _categoryTabType = 'expense';

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final breakdown = state.availableToSpendBreakdown;
    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final activeUserAccounts = state.activeUserAccounts;
    final archivedAccounts = state.archivedAccounts;

    return ListView(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      children: [
        // 1. Safe Harbor Hero Summary Card
        DaywellCard(
          color: colorScheme.primaryContainer.withOpacity(0.42),
          borderColor:
              (state.isShortfall ? semantic.error : colorScheme.primary)
                  .withOpacity(0.32),
          padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: SharedDesignTokens.spacingSm,
                runSpacing: SharedDesignTokens.spacingXs,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Safe Harbor Available to Spend',
                    style: textTheme.labelLarge?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Wrap(
                    spacing: SharedDesignTokens.spacingXs,
                    runSpacing: SharedDesignTokens.spacingXs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.event_outlined, size: 16),
                        label: Text(
                          'Through ${SharedDateFormatter.formatGregorianShort(state.effectivePlanningPeriodEnd)}',
                        ),
                        tooltip: 'Change planning horizon H',
                        onPressed: () => _pickHorizonDate(context, state),
                      ),
                      if (state.planningPeriodEnd != null)
                        DaywellButton(
                          label: 'Reset Month',
                          variant: DaywellButtonVariant.text,
                          size: DaywellButtonSize.compact,
                          onPressed: () =>
                              widget.controller.setPlanningPeriodEnd(null),
                        ),
                      DaywellButton(
                        label: 'Breakdown',
                        leadingIcon: Icons.analytics_outlined,
                        variant: DaywellButtonVariant.outlined,
                        size: DaywellButtonSize.compact,
                        onPressed: () => _showBreakdownSheet(context, state),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
              Text(
                FinanceUiFormatters.formatEtbCents(
                  breakdown.availableToSpendCents,
                ),
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: breakdown.availableToSpendCents < 0
                      ? semantic.error
                      : colorScheme.primary,
                ),
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              _metricRow(
                context,
                label: 'Liquid Cash (Bank, Cash, Mobile Money)',
                value: FinanceUiFormatters.formatEtbCents(
                  breakdown.liquidCashCents,
                ),
                valueColor: semantic.income,
              ),
              if (breakdown.prepaidCardCreditCents > 0)
                _metricRow(
                  context,
                  label: '+ Prepaid Card Credit (Included)',
                  value: FinanceUiFormatters.formatEtbCents(
                    breakdown.prepaidCardCreditCents,
                    includePlusSign: true,
                  ),
                  valueColor: semantic.income,
                ),
              if (breakdown.shortTermCreditOwedCents > 0)
                _metricRow(
                  context,
                  label: '− Short-Term Credit Card Owed',
                  value: FinanceUiFormatters.formatEtbCents(
                    -breakdown.shortTermCreditOwedCents,
                  ),
                  valueColor: semantic.expense,
                ),
              if (breakdown.duePayablesCents > 0)
                _metricRow(
                  context,
                  label: '− Due Payables in Horizon',
                  value: FinanceUiFormatters.formatEtbCents(
                    -breakdown.duePayablesCents,
                  ),
                  valueColor: semantic.expense,
                ),
              if (breakdown.dueNonDebtCommitmentsCents > 0)
                _metricRow(
                  context,
                  label: '− Due Bills & Commitments',
                  value: FinanceUiFormatters.formatEtbCents(
                    -breakdown.dueNonDebtCommitmentsCents,
                  ),
                  valueColor: semantic.warning,
                ),
              if (breakdown.virtualSavingsReservedCents > 0)
                _metricRow(
                  context,
                  label: '− Virtual Savings Reserve',
                  value: FinanceUiFormatters.formatEtbCents(
                    -breakdown.virtualSavingsReservedCents,
                  ),
                  valueColor: semantic.transfer,
                ),
              const Divider(height: SharedDesignTokens.spacingLg),
              Wrap(
                spacing: SharedDesignTokens.spacingMd,
                runSpacing: SharedDesignTokens.spacingSm,
                children: [
                  _miniStatChip(
                    context,
                    'Net Worth',
                    FinanceUiFormatters.formatEtbCents(
                      state.netFinancialPositionCents,
                    ),
                  ),
                  _miniStatChip(
                    context,
                    'Vault Savings',
                    FinanceUiFormatters.formatEtbCents(
                      breakdown.vaultSavingsCents,
                    ),
                  ),
                  _miniStatChip(
                    context,
                    'Receivables',
                    FinanceUiFormatters.formatEtbCents(
                      breakdown.receivablesCents,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (state.isShortfall) ...[
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          DaywellStatusBanner(
            tone: DaywellStatusTone.error,
            title: 'Safe Harbor Shortfall',
            message:
                'Obligations due through ${SharedDateFormatter.formatGregorianShort(state.effectivePlanningPeriodEnd)} exceed liquid cash by ${FinanceUiFormatters.formatEtbCents(-breakdown.availableToSpendCents)}.',
            actionLabel: widget.onOpenPlan != null ? 'Review Plan' : null,
            onActionPressed: widget.onOpenPlan,
          ),
        ],
        if (state.nonEtbAccountCount > 0) ...[
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          DaywellStatusBanner(
            tone: DaywellStatusTone.warning,
            title: 'Non-ETB Accounts Excluded',
            message: state.unverifiedAccountCount > 0
                ? '${state.nonEtbAccountCount} active non-ETB or unverified account(s) (${state.unverifiedAccountCount} unverified) are excluded from ETB Safe Harbor, P&L, and Net Worth totals.'
                : '${state.nonEtbAccountCount} active non-ETB account(s) are excluded from ETB Safe Harbor, P&L, and Net Worth totals.',
          ),
        ],
        if (state.currencyReviewEntryCount > 0 ||
            state.excludedNonEtbEntryCount > 0) ...[
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          DaywellStatusBanner(
            tone: state.currencyReviewEntryCount > 0
                ? DaywellStatusTone.warning
                : DaywellStatusTone.info,
            title: state.currencyReviewEntryCount > 0
                ? 'Ledger Entries Pending Currency Review'
                : 'Foreign-Currency Entries Isolated',
            message:
                '${state.excludedNonEtbEntryCount} foreign-currency entry(s) and ${state.currencyReviewEntryCount} unverified/mixed entry(s) are kept visible in ledger history but excluded from ETB reports.',
            actionLabel:
                widget.onOpenTransactions != null ? 'Review Ledger' : null,
            onActionPressed: widget.onOpenTransactions,
          ),
        ],
        if (state.unverifiedLegacyPaidCount > 0) ...[
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          DaywellStatusBanner(
            tone: DaywellStatusTone.warning,
            title: 'Legacy Paid Commitments Need Verification',
            message:
                '${state.unverifiedLegacyPaidCount} migrated commitment(s) were isolated with 0 cash impact until you record cash payment or mark unpaid.',
            actionLabel: widget.onOpenPlan != null ? 'Verify in Plan' : null,
            onActionPressed: widget.onOpenPlan,
          ),
        ],
        if (state.migrationReport != null &&
            (state.migrationReport!.hasErrors ||
                state.migrationReport!.hasWarnings)) ...[
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          DaywellStatusBanner(
            tone: state.migrationReport!.hasErrors
                ? DaywellStatusTone.error
                : DaywellStatusTone.warning,
            title: 'v7 Migration Audit Notices',
            message: state.migrationReport!.summary,
            actionLabel: widget.onOpenReports != null ? 'View Audit' : null,
            onActionPressed: widget.onOpenReports,
          ),
        ],
        const SizedBox(height: SharedDesignTokens.spacingMd),

        // 2. Quick Actions
        Wrap(
          spacing: SharedDesignTokens.spacingSm,
          runSpacing: SharedDesignTokens.spacingSm,
          children: [
            DaywellButton(
              label: 'Expense',
              leadingIcon: Icons.remove_circle_outline,
              variant: DaywellButtonVariant.primary,
              size: DaywellButtonSize.compact,
              onPressed: () => FinanceComposerSheet.show(
                context,
                controller: widget.controller,
                initialMode: FinanceComposerMode.expense,
              ),
            ),
            DaywellButton(
              label: 'Income',
              leadingIcon: Icons.add_circle_outline,
              variant: DaywellButtonVariant.secondary,
              size: DaywellButtonSize.compact,
              onPressed: () => FinanceComposerSheet.show(
                context,
                controller: widget.controller,
                initialMode: FinanceComposerMode.income,
              ),
            ),
            DaywellButton(
              label: 'Transfer',
              leadingIcon: Icons.swap_horiz,
              variant: DaywellButtonVariant.outlined,
              size: DaywellButtonSize.compact,
              onPressed: () => FinanceComposerSheet.show(
                context,
                controller: widget.controller,
                initialMode: FinanceComposerMode.transfer,
              ),
            ),
            DaywellButton(
              label: 'Split',
              leadingIcon: Icons.call_split,
              variant: DaywellButtonVariant.outlined,
              size: DaywellButtonSize.compact,
              onPressed: () => FinanceComposerSheet.show(
                context,
                controller: widget.controller,
                initialMode: FinanceComposerMode.split,
              ),
            ),
          ],
        ),
        const SizedBox(height: SharedDesignTokens.spacingLg),

        // 3. Accounts Section
        DaywellSectionHeader(
          title: 'Accounts',
          count: activeUserAccounts.length,
          actionLabel: '+ Add Account',
          onActionPressed: () => _openAccountEditorSheet(context),
        ),
        const SizedBox(height: SharedDesignTokens.spacingCompact),
        if (activeUserAccounts.isEmpty)
          DaywellEmptyState(
            icon: Icons.account_balance_wallet_outlined,
            message: 'No active accounts yet',
            subtitle:
                'Add a bank, cash wallet, mobile money, savings vault, or credit card.',
            actionLabel: 'Add Account',
            onActionPressed: () => _openAccountEditorSheet(context),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 680;
              final itemWidth = twoColumns
                  ? (constraints.maxWidth - SharedDesignTokens.spacingCompact) /
                      2
                  : constraints.maxWidth;
              return Wrap(
                spacing: SharedDesignTokens.spacingCompact,
                runSpacing: SharedDesignTokens.spacingCompact,
                children: [
                  for (final account in activeUserAccounts)
                    SizedBox(
                      width: itemWidth,
                      child: _buildAccountCard(context, account),
                    ),
                ],
              );
            },
          ),
        if (archivedAccounts.isNotEmpty) ...[
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DaywellButton(
              label: _showArchivedAccounts
                  ? 'Hide Archived (${archivedAccounts.length})'
                  : 'Show Archived (${archivedAccounts.length})',
              variant: DaywellButtonVariant.text,
              size: DaywellButtonSize.compact,
              onPressed: () => setState(
                () => _showArchivedAccounts = !_showArchivedAccounts,
              ),
            ),
          ),
          if (_showArchivedAccounts)
            for (final acc in archivedAccounts) ...[
              const SizedBox(height: SharedDesignTokens.spacingSm),
              _buildAccountCard(context, acc, isArchivedView: true),
            ],
        ],
        const SizedBox(height: SharedDesignTokens.spacingLg),

        // 4. Hierarchical Categories Manager
        DaywellSectionHeader(
          title: 'Categories',
          count: state.activeCategories.length,
          actionLabel: '+ Add Category',
          onActionPressed: () => _openCategoryEditorSheet(context),
        ),
        const SizedBox(height: SharedDesignTokens.spacingSm),
        Wrap(
          spacing: SharedDesignTokens.spacingSm,
          children: [
            ChoiceChip(
              label: const Text('Expense Categories'),
              selected: _categoryTabType == 'expense',
              onSelected: (_) => setState(() => _categoryTabType = 'expense'),
            ),
            ChoiceChip(
              label: const Text('Income Categories'),
              selected: _categoryTabType == 'income',
              onSelected: (_) => setState(() => _categoryTabType = 'income'),
            ),
          ],
        ),
        const SizedBox(height: SharedDesignTokens.spacingCompact),
        _buildCategoryHierarchyCard(context),
        const SizedBox(height: SharedDesignTokens.spacingLg),
      ],
    );
  }

  Widget _metricRow(
    BuildContext context, {
    required String label,
    required String value,
    Color? valueColor,
  }) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style:
                  textTheme.bodySmall?.copyWith(color: semantic.textSecondary),
            ),
          ),
          const SizedBox(width: SharedDesignTokens.spacingSm),
          Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor ?? semantic.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStatChip(BuildContext context, String label, String value) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(color: semantic.textSecondary),
        ),
        Text(
          value,
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildAccountCard(
    BuildContext context,
    AccountModel account, {
    bool isArchivedView = false,
  }) {
    final state = widget.controller.state;
    final balanceCents = state.getAccountBalanceCents(account);
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final isLiability = account.type == AccountType.liability;

    final currencyTier =
        DoubleEntryEngine.classifyCurrencyCode(account.currencyCode);
    final normalizedCode =
        DoubleEntryEngine.normalizeCurrencyCode(account.currencyCode);
    final formattedBal = FinanceUiFormatters.formatCurrencyCents(
      balanceCents,
      currencyCode: account.currencyCode,
    );

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FinanceUiFormatters.accountSubTypeIcon(account.subType),
                color: isLiability
                    ? semantic.error
                    : (account.subType.isSavingsVault
                        ? semantic.transfer
                        : Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: SharedDesignTokens.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      FinanceUiFormatters.accountSubTypeLabel(account.subType),
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Account actions',
                onSelected: (value) async {
                  if (value == 'edit') {
                    await _openAccountEditorSheet(context, existing: account);
                  } else if (value == 'archive') {
                    await widget.controller.archiveAccount(account.id);
                    final err = widget.controller.state.errorMessage;
                    if (err != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(err)),
                      );
                    }
                  } else if (value == 'unarchive') {
                    await widget.controller.unarchiveAccount(account.id);
                    final err = widget.controller.state.errorMessage;
                    if (err != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(err)),
                      );
                    }
                  } else if (value == 'delete') {
                    final confirmed = await DaywellConfirmationDialog.show(
                      context,
                      title: 'Delete Account?',
                      message:
                          'Delete "${account.name}" permanently? Accounts with ledger history cannot be deleted and should be archived instead.',
                      confirmLabel: 'Delete',
                      isDestructive: true,
                      icon: Icons.delete_outline,
                    );
                    if (confirmed) {
                      await widget.controller.deleteAccount(account.id);
                      final err = widget.controller.state.errorMessage;
                      if (err != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(err)),
                        );
                      }
                    }
                  }
                },
                itemBuilder: (_) => [
                  if (!isArchivedView)
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(
                        currencyTier == CurrencyValidationTier.verifiedEtb
                            ? 'Edit / Opening Balance'
                            : 'Rename Account',
                      ),
                    ),
                  PopupMenuItem(
                    value: isArchivedView ? 'unarchive' : 'archive',
                    child: Text(isArchivedView ? 'Restore' : 'Archive'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Wrap(
            spacing: SharedDesignTokens.spacingSm,
            runSpacing: SharedDesignTokens.spacingXs,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                isLiability ? 'Owed: $formattedBal' : formattedBal,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isLiability && balanceCents > 0
                      ? semantic.error
                      : semantic.textPrimary,
                ),
              ),
              if (currencyTier == CurrencyValidationTier.verifiedNonEtb)
                DaywellStatusBadge(
                  label: 'Excluded ($normalizedCode)',
                  tone: DaywellStatusTone.warning,
                  showIcon: false,
                )
              else if (currencyTier == CurrencyValidationTier.unverified)
                const DaywellStatusBadge(
                  label: 'Currency Review',
                  tone: DaywellStatusTone.warning,
                )
              else if (account.subType.isSavingsVault)
                const DaywellStatusBadge(
                  label: 'Protected Vault',
                  tone: DaywellStatusTone.info,
                  showIcon: false,
                )
              else if (account.subType.isCreditCard)
                DaywellStatusBadge(
                  label:
                      balanceCents < 0 ? 'Prepaid Credit' : 'Credit Liability',
                  tone: balanceCents < 0
                      ? DaywellStatusTone.success
                      : DaywellStatusTone.warning,
                  showIcon: false,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickHorizonDate(
    BuildContext context,
    FinanceModuleState state,
  ) async {
    final picked = await FinanceUiFormatters.pickCalendarDate(
      context,
      initialDate: state.effectivePlanningPeriodEnd,
    );
    if (picked != null) {
      widget.controller.setPlanningPeriodEnd(picked);
    }
  }

  Future<void> _showBreakdownSheet(
    BuildContext context,
    FinanceModuleState state,
  ) async {
    final b = state.availableToSpendBreakdown;
    final semantic = context.daywellColors;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Safe Harbor Breakdown',
                style: Theme.of(sheetCtx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Planning Horizon H: ${SharedDateFormatter.formatDual(state.effectivePlanningPeriodEnd, useAmharic: false)}',
                style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                      color: semantic.textSecondary,
                    ),
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              _metricRow(
                sheetCtx,
                label: 'Liquid Cash (Bank, Cash, Mobile Money)',
                value: FinanceUiFormatters.formatEtbCents(b.liquidCashCents),
                valueColor: semantic.income,
              ),
              _metricRow(
                sheetCtx,
                label: '+ Prepaid Card Credit (Option 1 Included)',
                value: FinanceUiFormatters.formatEtbCents(
                  b.prepaidCardCreditCents,
                  includePlusSign: true,
                ),
                valueColor: semantic.income,
              ),
              _metricRow(
                sheetCtx,
                label: '− Short-Term Credit Card Owed',
                value: FinanceUiFormatters.formatEtbCents(
                  -b.shortTermCreditOwedCents,
                ),
                valueColor: semantic.expense,
              ),
              _metricRow(
                sheetCtx,
                label: '− Due Payables (<= H)',
                value: FinanceUiFormatters.formatEtbCents(-b.duePayablesCents),
                valueColor: semantic.expense,
              ),
              _metricRow(
                sheetCtx,
                label: '− Due Outflow Commitments (<= H)',
                value: FinanceUiFormatters.formatEtbCents(
                  -b.dueNonDebtCommitmentsCents,
                ),
                valueColor: semantic.warning,
              ),
              _metricRow(
                sheetCtx,
                label: '− Virtual Savings Reserves',
                value: FinanceUiFormatters.formatEtbCents(
                  -b.virtualSavingsReservedCents,
                ),
                valueColor: semantic.transfer,
              ),
              const Divider(),
              _metricRow(
                sheetCtx,
                label: 'Available to Spend (H)',
                value: FinanceUiFormatters.formatEtbCents(
                  b.availableToSpendCents,
                ),
                valueColor: b.availableToSpendCents < 0
                    ? semantic.error
                    : Theme.of(sheetCtx).colorScheme.primary,
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
              Text(
                'Vault Savings (${FinanceUiFormatters.formatEtbCents(b.vaultSavingsCents)}), Active Receivables (${FinanceUiFormatters.formatEtbCents(b.receivablesCents)}), and pending Expected Income inflows do not inflate Safe Harbor until received.',
                style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                      color: semantic.textSecondary,
                    ),
              ),
              const SizedBox(height: SharedDesignTokens.spacingMd),
              DaywellButton(
                label: 'Close',
                fullWidth: true,
                variant: DaywellButtonVariant.outlined,
                onPressed: () => Navigator.of(sheetCtx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryHierarchyCard(BuildContext context) {
    final allCats = widget.controller.state.categories
        .where((c) => c.type == _categoryTabType)
        .toList()
      ..sort((a, b) {
        final cmp = a.sortOrder.compareTo(b.sortOrder);
        return cmp != 0 ? cmp : a.name.compareTo(b.name);
      });

    if (allCats.isEmpty) {
      return DaywellEmptyState(
        icon: Icons.category_outlined,
        message: 'No $_categoryTabType categories',
        actionLabel: 'Add Category',
        onActionPressed: () => _openCategoryEditorSheet(context),
      );
    }

    final parents = allCats
        .where(
          (c) => c.parentId == null || !allCats.any((p) => p.id == c.parentId),
        )
        .toList();

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
      child: Column(
        children: [
          for (final parent in parents) ...[
            _buildCategoryTile(context, parent, isChild: false),
            for (final child in allCats.where((c) => c.parentId == parent.id))
              _buildCategoryTile(context, child, isChild: true),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryTile(
    BuildContext context,
    TransactionCategoryModel category, {
    required bool isChild,
  }) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final dotColor = FinanceUiFormatters.parseColorHex(
      category.colorHex,
      Theme.of(context).colorScheme.primary,
    );

    return Padding(
      padding: EdgeInsets.only(
        left: isChild ? SharedDesignTokens.spacingLg : 0,
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SharedDesignTokens.spacingSm,
        ),
        leading: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        title: Text(
          category.name,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: isChild ? FontWeight.normal : FontWeight.w600,
            decoration: category.isArchived ? TextDecoration.lineThrough : null,
            color:
                category.isArchived ? semantic.textMuted : semantic.textPrimary,
          ),
        ),
        trailing: Wrap(
          spacing: 0,
          children: [
            DaywellIconButton(
              icon: Icons.edit_outlined,
              tooltip: 'Edit category',
              iconSize: DaywellIconSize.sm,
              onPressed: () =>
                  _openCategoryEditorSheet(context, existing: category),
            ),
            DaywellIconButton(
              icon: category.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
              tooltip: category.isArchived ? 'Restore' : 'Archive',
              iconSize: DaywellIconSize.sm,
              onPressed: () => widget.controller.archiveCategory(category.id),
            ),
            if (!category.isDefault)
              DaywellIconButton(
                icon: Icons.delete_outline,
                tooltip: 'Delete category',
                iconSize: DaywellIconSize.sm,
                isDestructive: true,
                onPressed: () async {
                  final confirmed = await DaywellConfirmationDialog.show(
                    context,
                    title: 'Delete Category?',
                    message:
                        'Delete "${category.name}"? Categories referenced by postings, commitments, budgets, or recurring rules cannot be deleted.',
                    confirmLabel: 'Delete',
                    isDestructive: true,
                    icon: Icons.delete_outline,
                  );
                  if (confirmed) {
                    await widget.controller.deleteCategory(category.id);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAccountEditorSheet(
    BuildContext context, {
    AccountModel? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final balCtrl = TextEditingController(
      text: existing != null
          ? FinanceUiFormatters.formatCentsAsInput(existing.openingBalanceCents)
          : '0.00',
    );
    var subType = existing?.subType ?? AccountSubType.bank;
    var openingDate = existing != null
        ? SharedDateFormatter.parseFlexibleToCalendarDate(
            existing.openingBalanceDate,
          )
        : CalendarDate.today();
    String? error;

    final isLegacyLockedCurrency =
        existing != null && !DoubleEntryEngine.isEtb(existing.currencyCode);
    final currencyBadgeLabel = existing == null
        ? 'ETB (Required in first release)'
        : FinanceUiFormatters.currencyDisplayLabel(existing.currencyCode);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: SharedDesignTokens.spacingMd,
            right: SharedDesignTokens.spacingMd,
            top: SharedDesignTokens.spacingMd,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom +
                SharedDesignTokens.spacingMd,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  existing == null ? 'New Account' : 'Edit Account',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (error != null) ...[
                  const SizedBox(height: SharedDesignTokens.spacingSm),
                  DaywellStatusBanner(
                    message: error!,
                    tone: DaywellStatusTone.error,
                  ),
                ],
                const SizedBox(height: SharedDesignTokens.spacingSm),
                DaywellStatusBanner(
                  tone: isLegacyLockedCurrency
                      ? DaywellStatusTone.warning
                      : DaywellStatusTone.info,
                  title: 'Currency: $currencyBadgeLabel',
                  message: isLegacyLockedCurrency
                      ? 'First-release reporting supports ETB writes only; historical foreign-currency balances are preserved read-only.'
                      : 'All new accounts and transactions operate in ETB.',
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellTextField(
                  controller: nameCtrl,
                  label: 'Account Name',
                  isRequired: true,
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellDropdownField<AccountSubType>(
                  label: 'Account Kind',
                  value: subType,
                  items: const [
                    DropdownMenuItem(
                      value: AccountSubType.bank,
                      child: Text('Bank Account (Liquid)'),
                    ),
                    DropdownMenuItem(
                      value: AccountSubType.cash,
                      child: Text('Cash Wallet (Liquid)'),
                    ),
                    DropdownMenuItem(
                      value: AccountSubType.mobileMoney,
                      child: Text('Mobile Money (Liquid)'),
                    ),
                    DropdownMenuItem(
                      value: AccountSubType.savingsVault,
                      child: Text('Savings Vault (Protected)'),
                    ),
                    DropdownMenuItem(
                      value: AccountSubType.creditCard,
                      child: Text('Credit Card (Short-Term Liability)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setModalState(() => subType = val);
                  },
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellTextField(
                  controller: balCtrl,
                  enabled: !isLegacyLockedCurrency,
                  readOnly: isLegacyLockedCurrency,
                  label: subType == AccountSubType.creditCard
                      ? 'Opening Amount Owed (${isLegacyLockedCurrency ? currencyBadgeLabel : 'ETB'})'
                      : 'Opening Balance (${isLegacyLockedCurrency ? currencyBadgeLabel : 'ETB'})',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: SharedDesignTokens.spacingSm),
                Wrap(
                  spacing: SharedDesignTokens.spacingSm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Opening Date: ${SharedDateFormatter.formatDual(openingDate, useAmharic: false)}',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    if (!isLegacyLockedCurrency)
                      DaywellButton(
                        label: 'Pick Date',
                        variant: DaywellButtonVariant.text,
                        size: DaywellButtonSize.compact,
                        onPressed: () async {
                          final picked =
                              await FinanceUiFormatters.pickCalendarDate(
                            ctx,
                            initialDate: openingDate,
                          );
                          if (picked != null) {
                            setModalState(() => openingDate = picked);
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: SharedDesignTokens.spacingMd),
                DaywellButton(
                  label: existing == null ? 'Create Account' : 'Save Account',
                  fullWidth: true,
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      setModalState(() => error = 'Enter an account name.');
                      return;
                    }
                    if (isLegacyLockedCurrency) {
                      await widget.controller.updateAccount(
                        existing.copyWith(
                          name: name,
                          subType: subType,
                        ),
                      );
                      final err = widget.controller.state.errorMessage;
                      if (err != null) {
                        setModalState(() => error = err);
                        return;
                      }
                      if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                      return;
                    }
                    final rawBal = balCtrl.text.trim();
                    final cents = rawBal.isEmpty
                        ? 0
                        : FinanceUiFormatters.parseEtbToCents(rawBal);
                    if (cents == null) {
                      setModalState(
                        () => error = 'Enter a valid decimal balance.',
                      );
                      return;
                    }
                    final type = subType == AccountSubType.creditCard
                        ? AccountType.liability
                        : AccountType.asset;
                    if (existing == null) {
                      await widget.controller.addAccount(
                        name: name,
                        type: type,
                        subType: subType,
                        currencyCode: 'ETB',
                        openingBalanceCents: cents,
                        openingBalanceDate: openingDate.toIsoString(),
                      );
                    } else {
                      await widget.controller.updateAccount(
                        existing.copyWith(
                          name: name,
                          type: type,
                          subType: subType,
                          openingBalanceCents: cents,
                          openingBalanceDate: openingDate.toIsoString(),
                        ),
                      );
                    }
                    final err = widget.controller.state.errorMessage;
                    if (err != null) {
                      setModalState(() => error = err);
                      return;
                    }
                    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    nameCtrl.dispose();
    balCtrl.dispose();
  }

  Future<void> _openCategoryEditorSheet(
    BuildContext context, {
    TransactionCategoryModel? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    var catType = existing?.type ?? _categoryTabType;
    var parentId = existing?.parentId;
    var colorHex = existing?.colorHex ?? '#1B4D3E';
    String? error;

    const palette = [
      '#1B4D3E',
      '#0D9488',
      '#10B981',
      '#3B82F6',
      '#F59E0B',
      '#EF4444',
      '#8B5CF6',
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final parentCandidates = widget.controller.state.categories
              .where(
                (c) =>
                    c.type == catType &&
                    c.parentId == null &&
                    c.id != existing?.id &&
                    !c.isArchived,
              )
              .toList();

          return Padding(
            padding: EdgeInsets.only(
              left: SharedDesignTokens.spacingMd,
              right: SharedDesignTokens.spacingMd,
              top: SharedDesignTokens.spacingMd,
              bottom: MediaQuery.viewInsetsOf(ctx).bottom +
                  SharedDesignTokens.spacingMd,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    existing == null ? 'New Category' : 'Edit Category',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: SharedDesignTokens.spacingSm),
                    DaywellStatusBanner(
                      message: error!,
                      tone: DaywellStatusTone.error,
                    ),
                  ],
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  if (existing == null) ...[
                    Wrap(
                      spacing: SharedDesignTokens.spacingSm,
                      children: [
                        ChoiceChip(
                          label: const Text('Expense'),
                          selected: catType == 'expense',
                          onSelected: (_) => setModalState(() {
                            catType = 'expense';
                            parentId = null;
                          }),
                        ),
                        ChoiceChip(
                          label: const Text('Income'),
                          selected: catType == 'income',
                          onSelected: (_) => setModalState(() {
                            catType = 'income';
                            parentId = null;
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                  ],
                  DaywellTextField(
                    controller: nameCtrl,
                    label: 'Category Name',
                    isRequired: true,
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellDropdownField<String?>(
                    label: 'Parent Group (Optional)',
                    value: parentCandidates.any((c) => c.id == parentId)
                        ? parentId
                        : null,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Top-Level Category'),
                      ),
                      for (final p in parentCandidates)
                        DropdownMenuItem<String?>(
                          value: p.id,
                          child: Text(p.name),
                        ),
                    ],
                    onChanged: (val) => setModalState(() => parentId = val),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  Wrap(
                    spacing: SharedDesignTokens.spacingSm,
                    runSpacing: SharedDesignTokens.spacingSm,
                    children: [
                      for (final hex in palette)
                        ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: FinanceUiFormatters.parseColorHex(
                                    hex,
                                    Colors.teal,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(hex),
                            ],
                          ),
                          selected: colorHex == hex,
                          onSelected: (_) =>
                              setModalState(() => colorHex = hex),
                        ),
                    ],
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingMd),
                  DaywellButton(
                    label:
                        existing == null ? 'Create Category' : 'Save Changes',
                    fullWidth: true,
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        setModalState(
                          () => error = 'Enter a category name.',
                        );
                        return;
                      }
                      if (existing == null) {
                        await widget.controller.addCategory(
                          TransactionCategoryModel(
                            id: 'cat-${_uuid.v4()}',
                            name: name,
                            type: catType,
                            colorHex: colorHex,
                            parentId: parentId,
                          ),
                        );
                      } else {
                        await widget.controller.updateCategoryDetails(
                          existing.id,
                          name: name,
                          colorHex: colorHex,
                          parentId: parentId,
                          clearParentId: parentId == null,
                        );
                      }
                      final err = widget.controller.state.errorMessage;
                      if (err != null) {
                        setModalState(() => error = err);
                        return;
                      }
                      if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    nameCtrl.dispose();
  }
}
