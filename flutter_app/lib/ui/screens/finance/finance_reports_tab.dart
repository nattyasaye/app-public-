import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../application/finance/finance_controller.dart';
import '../../../application/finance/finance_state.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/finance/double_entry_engine.dart';
import '../../../domain/finance/finance_models.dart';
import '../../../services/export/finance_export_service.dart';
import '../../widgets/shared_ui_widgets.dart';
import 'finance_formatters.dart';

/// Stage F4 Reports & Export Hub Tab:
/// Dual-calendar period comparison (with Ethiopian Pagume 5/6 leap support),
/// Occurrence P&L & Liquid Cash Flow deltas, Aligned Balance Sheet,
/// Verified-ETB Account Balances, Savings Vaults & Goals,
/// Monthly Budget Progress, Canonical Hierarchical Category Spend,
/// Ledger Integrity & v7 Audit, all 13 UTF-8 BOM CSV exports,
/// 13-table SQLite analytical export, and Finance-only JSON portability.
class FinanceReportsTab extends StatefulWidget {
  final FinanceController controller;

  const FinanceReportsTab({
    super.key,
    required this.controller,
  });

  @override
  State<FinanceReportsTab> createState() => _FinanceReportsTabState();
}

class _FinanceReportsTabState extends State<FinanceReportsTab> {
  ReportPeriodMode _periodMode = ReportPeriodMode.thisMonth;
  late int _ethYear;
  late int _ethMonth;
  CalendarDate? _customStart;
  CalendarDate? _customEnd;
  String? _portabilityStatusMessage;
  bool _portabilityStatusIsError = false;

  @override
  void initState() {
    super.initState();
    final ethToday = EthiopianDate.today();
    _ethYear = ethToday.year;
    _ethMonth = ethToday.month;
  }

  void _shiftEthMonth(int delta) {
    setState(() {
      var m = _ethMonth + delta;
      var y = _ethYear;
      while (m > 13) {
        m -= 13;
        y += 1;
      }
      while (m < 1) {
        m += 13;
        y -= 1;
      }
      _ethYear = y;
      _ethMonth = m;
    });
  }

  TextStyle? _tabularStyle(TextStyle? base) {
    return base?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  Color _deltaColor(BuildContext context, MetricComparisonDelta delta) {
    final semantic = context.daywellColors;
    if (delta.isPositiveOutcome == true) return semantic.income;
    if (delta.isPositiveOutcome == false) return semantic.expense;
    return semantic.textSecondary;
  }

  String _formatDeltaText(MetricComparisonDelta delta) {
    final formatted = FinanceUiFormatters.formatEtbCents(
      delta.deltaCents,
      includePlusSign: true,
    );
    return '$formatted (${delta.percentageDisplay})';
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final todayIso = CalendarDate.today().toIsoString();
    final period = DoubleEntryEngine.resolveReportPeriodWithComparison(
      mode: _periodMode,
      ethYear: _ethYear,
      ethMonth: _ethMonth,
      customStartIso: _customStart?.toIsoString(),
      customEndIso: _customEnd?.toIsoString(),
      todayIso: todayIso,
    );
    final comparison = DoubleEntryEngine.calculatePeriodComparisonReport(
      period: period,
      accounts: state.accounts,
      entries: state.journalEntries,
      postings: state.postings,
      debts: state.debts,
      allocations: state.settlementAllocations,
    );
    final categorySpendReport =
        DoubleEntryEngine.calculateCanonicalCategorySpend(
      entries: state.journalEntries,
      postings: state.postings,
      accounts: state.accounts,
      categories: state.categories,
      debts: state.debts,
      allocations: state.settlementAllocations,
      startDateIso: period.currentStart,
      endDateIso: period.currentEnd,
    );
    final accountBalancesReport = DoubleEntryEngine.buildAccountBalancesReport(
      accounts: state.accounts,
      entries: state.journalEntries,
      postings: state.postings,
    );
    final savingsVaultsReport =
        DoubleEntryEngine.buildSavingsVaultsAndGoalsReport(
      accounts: state.accounts,
      entries: state.journalEntries,
      postings: state.postings,
      savingsGoals: state.savingsGoals,
    );
    final activeBudgetMonthIso = DoubleEntryEngine.resolveActiveReportMonthIso(
      mode: _periodMode,
      startDateIso: period.currentStart,
      endDateIso: period.currentEnd,
      todayIso: todayIso,
    );
    final budgetProgressReport =
        DoubleEntryEngine.buildMonthlyBudgetProgressReport(
      budgets: state.budgets,
      categories: state.categories,
      entries: state.journalEntries,
      postings: state.postings,
      accounts: state.accounts,
      debts: state.debts,
      allocations: state.settlementAllocations,
      monthIso: activeBudgetMonthIso,
    );
    final alignedBalanceSheet =
        DoubleEntryEngine.buildAlignedBalanceSheetReport(
      accounts: state.accounts,
      entries: state.journalEntries,
      postings: state.postings,
      debts: state.debts,
      allocations: state.settlementAllocations,
      breakdown: state.availableToSpendBreakdown,
    );

    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      children: [
        // 1. Dual-Calendar Period Selector
        DaywellCard(
          padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Report Period',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${period.label} · vs. ${period.baselineLabel}',
                          style: textTheme.bodySmall?.copyWith(
                            color: semantic.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: SharedDesignTokens.spacingSm),
                  Text(
                    '${period.currentStart} – ${period.currentEnd}',
                    style: _tabularStyle(
                      textTheme.labelSmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
              Wrap(
                spacing: SharedDesignTokens.spacingSm,
                runSpacing: SharedDesignTokens.spacingSm,
                children: [
                  _periodChip(ReportPeriodMode.thisMonth, 'This Month'),
                  _periodChip(ReportPeriodMode.last30Days, 'Last 30 Days'),
                  _periodChip(ReportPeriodMode.thisYear, 'This Year'),
                  _periodChip(
                    ReportPeriodMode.ethiopianMonth,
                    'Ethiopian Month',
                  ),
                  _periodChip(ReportPeriodMode.custom, 'Custom'),
                ],
              ),
              if (_periodMode == ReportPeriodMode.ethiopianMonth) ...[
                const SizedBox(height: SharedDesignTokens.spacingSm),
                Wrap(
                  spacing: SharedDesignTokens.spacingSm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DaywellIconButton(
                      icon: Icons.chevron_left,
                      tooltip: 'Previous Ethiopian month',
                      onPressed: () => _shiftEthMonth(-1),
                    ),
                    Text(
                      period.label,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    DaywellIconButton(
                      icon: Icons.chevron_right,
                      tooltip: 'Next Ethiopian month',
                      onPressed: () => _shiftEthMonth(1),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: SharedDesignTokens.spacingMd),

        // 2. Liquid Cash Flow & Occurrence P&L with Preceding-Period Deltas
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 640;
            final cashCard = _buildCashFlowCard(context, period, comparison);
            final pnlCard =
                _buildOccurrencePnlCard(context, period, comparison);
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cashCard),
                  const SizedBox(width: SharedDesignTokens.spacingMd),
                  Expanded(child: pnlCard),
                ],
              );
            }
            return Column(
              children: [
                cashCard,
                const SizedBox(height: SharedDesignTokens.spacingMd),
                pnlCard,
              ],
            );
          },
        ),
        const SizedBox(height: SharedDesignTokens.spacingMd),

        // 3. Aligned Balance Sheet Snapshot
        _buildAlignedBalanceSheetCard(context, alignedBalanceSheet),
        const SizedBox(height: SharedDesignTokens.spacingMd),

        // 4. Account Balances (Verified ETB) & Savings Vaults / Goals
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 680;
            final balancesCard =
                _buildAccountBalancesCard(context, accountBalancesReport);
            final savingsCard =
                _buildSavingsVaultsCard(context, savingsVaultsReport);
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: balancesCard),
                  const SizedBox(width: SharedDesignTokens.spacingMd),
                  Expanded(child: savingsCard),
                ],
              );
            }
            return Column(
              children: [
                balancesCard,
                const SizedBox(height: SharedDesignTokens.spacingMd),
                savingsCard,
              ],
            );
          },
        ),
        const SizedBox(height: SharedDesignTokens.spacingMd),

        // 5. Monthly Budget Progress & Canonical Hierarchical Category Spend
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 680;
            final budgetCard =
                _buildMonthlyBudgetCard(context, budgetProgressReport);
            final catCard =
                _buildCategorySpendCard(context, categorySpendReport);
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: budgetCard),
                  const SizedBox(width: SharedDesignTokens.spacingMd),
                  Expanded(child: catCard),
                ],
              );
            }
            return Column(
              children: [
                budgetCard,
                const SizedBox(height: SharedDesignTokens.spacingMd),
                catCard,
              ],
            );
          },
        ),
        const SizedBox(height: SharedDesignTokens.spacingMd),

        // 6. Ledger Integrity & v7 Migration Diagnostic Audit
        _buildAuditCard(context, state),
        const SizedBox(height: SharedDesignTokens.spacingMd),

        // 7. Export Hub & Finance-Only Portability
        _buildExportAndPortabilityCard(context, state, todayIso),
        const SizedBox(height: SharedDesignTokens.spacingLg),
      ],
    );
  }

  Widget _buildCashFlowCard(
    BuildContext context,
    ResolvedReportPeriod period,
    PeriodComparisonReport comparison,
  ) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cash Flow (Liquid ETB Movement)',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            'vs. ${period.baselineLabel}',
            style: textTheme.bodySmall?.copyWith(color: semantic.textSecondary),
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          _reportMetricDeltaRow(
            context,
            label: 'Cash Inflow',
            value: FinanceUiFormatters.formatEtbCents(
              comparison.currentLiquidCash.inflowCents,
              includePlusSign: true,
            ),
            valueColor: semantic.income,
            delta: comparison.cashInflow,
          ),
          _reportMetricDeltaRow(
            context,
            label: 'Cash Outflow',
            value: FinanceUiFormatters.formatEtbCents(
              -comparison.currentLiquidCash.outflowCents,
            ),
            valueColor: semantic.expense,
            delta: comparison.cashOutflow,
          ),
          const Divider(),
          _reportMetricDeltaRow(
            context,
            label: 'Net Cash Flow',
            value: FinanceUiFormatters.formatEtbCents(
              comparison.currentLiquidCash.netCashflowCents,
              includePlusSign: true,
            ),
            valueColor: comparison.currentLiquidCash.netCashflowCents >= 0
                ? semantic.income
                : semantic.error,
            delta: comparison.cashNet,
          ),
        ],
      ),
    );
  }

  Widget _buildOccurrencePnlCard(
    BuildContext context,
    ResolvedReportPeriod period,
    PeriodComparisonReport comparison,
  ) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Occurrence P&L (Economic Date)',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            'vs. ${period.baselineLabel}',
            style: textTheme.bodySmall?.copyWith(color: semantic.textSecondary),
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          _reportMetricDeltaRow(
            context,
            label: 'Earned Income',
            value: FinanceUiFormatters.formatEtbCents(
              comparison.currentOccurrence.incomeCents,
              includePlusSign: true,
            ),
            valueColor: semantic.income,
            delta: comparison.occurrenceIncome,
          ),
          _reportMetricDeltaRow(
            context,
            label: 'Incurred Expense',
            value: FinanceUiFormatters.formatEtbCents(
              -comparison.currentOccurrence.expenseCents,
            ),
            valueColor: semantic.expense,
            delta: comparison.occurrenceExpense,
          ),
          const Divider(),
          _reportMetricDeltaRow(
            context,
            label: 'Net Savings (P&L)',
            value: FinanceUiFormatters.formatEtbCents(
              comparison.currentOccurrence.netCashflowCents,
              includePlusSign: true,
            ),
            valueColor: comparison.currentOccurrence.netCashflowCents >= 0
                ? semantic.income
                : semantic.error,
            delta: comparison.occurrenceNet,
          ),
        ],
      ),
    );
  }

  Widget _buildAlignedBalanceSheetCard(
    BuildContext context,
    AlignedBalanceSheetReport sheet,
  ) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Balance Sheet Snapshot (ETB)',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Horizon <= ${sheet.planningPeriodEndIso}',
                style: _tabularStyle(
                  textTheme.labelSmall?.copyWith(color: semantic.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          _reportRow(
            context,
            'Liquid Cash (Bank / Cash / Mobile Money)',
            FinanceUiFormatters.formatEtbCents(sheet.liquidCashCents),
          ),
          _reportRow(
            context,
            'Dedicated Savings Vaults',
            FinanceUiFormatters.formatEtbCents(sheet.vaultSavingsCents),
          ),
          if (sheet.prepaidCardCreditCents > 0)
            _reportRow(
              context,
              '+ Prepaid Card Credit (Included)',
              FinanceUiFormatters.formatEtbCents(sheet.prepaidCardCreditCents),
              valueColor: semantic.income,
            ),
          _reportRow(
            context,
            'Active Receivables',
            FinanceUiFormatters.formatEtbCents(sheet.receivablesCents),
          ),
          _reportRow(
            context,
            '- Short-Term Credit Card Owed',
            FinanceUiFormatters.formatEtbCents(-sheet.shortTermCreditOwedCents),
            valueColor: semantic.expense,
          ),
          _reportRow(
            context,
            '- Active Payables (Total Liabilities)',
            FinanceUiFormatters.formatEtbCents(-sheet.activePayablesCents),
            valueColor: semantic.expense,
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: SharedDesignTokens.spacingMd,
              top: 2,
              bottom: 4,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Due in Horizon (<= ${sheet.planningPeriodEndIso})',
                  style: textTheme.bodySmall?.copyWith(
                    color: semantic.textSecondary,
                  ),
                ),
                Text(
                  FinanceUiFormatters.formatEtbCents(sheet.duePayablesCents),
                  style: _tabularStyle(
                    textTheme.bodySmall?.copyWith(
                      color: semantic.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          _reportRow(
            context,
            'Net Financial Position',
            FinanceUiFormatters.formatEtbCents(
              sheet.netFinancialPositionCents,
              includePlusSign: sheet.netFinancialPositionCents > 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountBalancesCard(
    BuildContext context,
    AccountBalancesReport report,
  ) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final hasAnyActive = report.liquidAccounts.isNotEmpty ||
        report.vaultAccounts.isNotEmpty ||
        report.creditCardAccounts.isNotEmpty;

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: SharedDesignTokens.spacingSm,
            runSpacing: SharedDesignTokens.spacingXs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Account Balances (Verified ETB)',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (report.nonEtbReviewAccounts.isNotEmpty)
                DaywellStatusBadge(
                  label:
                      '${report.nonEtbReviewAccounts.length} Non-ETB / Review',
                  tone: DaywellStatusTone.warning,
                  showIcon: false,
                ),
              if (report.archivedCount > 0)
                DaywellStatusBadge(
                  label: '${report.archivedCount} Archived',
                  tone: DaywellStatusTone.info,
                  showIcon: false,
                ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          if (!hasAnyActive)
            Text(
              'No active Verified ETB accounts configured.',
              style: textTheme.bodySmall?.copyWith(
                color: semantic.textSecondary,
              ),
            )
          else ...[
            if (report.liquidAccounts.isNotEmpty) ...[
              _reportRow(
                context,
                'Liquid Accounts',
                FinanceUiFormatters.formatEtbCents(report.liquidTotalCents),
              ),
              for (final acc in report.liquidAccounts)
                _reportRow(
                  context,
                  '  ${acc.name} (${FinanceUiFormatters.accountSubTypeLabel(acc.subType)})',
                  FinanceUiFormatters.formatEtbCents(acc.balanceCents),
                ),
            ],
            if (report.vaultAccounts.isNotEmpty) ...[
              const Divider(),
              _reportRow(
                context,
                'Savings Vaults',
                FinanceUiFormatters.formatEtbCents(report.vaultTotalCents),
              ),
              for (final acc in report.vaultAccounts)
                _reportRow(
                  context,
                  '  ${acc.name}',
                  FinanceUiFormatters.formatEtbCents(acc.balanceCents),
                ),
            ],
            if (report.creditCardAccounts.isNotEmpty) ...[
              const Divider(),
              _reportRow(
                context,
                'Credit Cards',
                'Owed ${FinanceUiFormatters.formatEtbCents(report.creditCardOwedTotalCents)}',
              ),
              for (final acc in report.creditCardAccounts)
                _reportRow(
                  context,
                  '  ${acc.name}',
                  acc.prepaidCents > 0
                      ? 'Prepaid +${FinanceUiFormatters.formatEtbCents(acc.prepaidCents)}'
                      : 'Owed ${FinanceUiFormatters.formatEtbCents(acc.owedCents)}',
                  valueColor:
                      acc.owedCents > 0 ? semantic.expense : semantic.income,
                ),
            ],
          ],
          if (report.nonEtbReviewAccounts.isNotEmpty) ...[
            const Divider(),
            Text(
              'Read-Only Non-ETB / Currency Review Accounts (Excluded)',
              style: textTheme.labelMedium?.copyWith(
                color: semantic.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: SharedDesignTokens.spacingXs),
            for (final acc in report.nonEtbReviewAccounts)
              _reportRow(
                context,
                '${acc.name} (${acc.currencyCode})',
                FinanceUiFormatters.formatCurrencyCents(
                  acc.balanceCents,
                  currencyCode: acc.currencyCode,
                ),
                valueColor: semantic.textSecondary,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSavingsVaultsCard(
    BuildContext context,
    SavingsVaultsReport report,
  ) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Savings Vaults & Goals',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Live vault ledger totals and allocated goal targets',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Vaults: ${FinanceUiFormatters.formatEtbCents(report.totalVaultBalanceCents)}',
                style: _tabularStyle(
                  textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          if (report.goals.isEmpty)
            Text(
              'No savings goals configured yet.',
              style: textTheme.bodySmall?.copyWith(
                color: semantic.textSecondary,
              ),
            )
          else
            for (final goal in report.goals) ...[
              Padding(
                padding: const EdgeInsets.only(
                  bottom: SharedDesignTokens.spacingCompact,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: SharedDesignTokens.spacingXs,
                      runSpacing: SharedDesignTokens.spacingXs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          goal.title,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        DaywellStatusBadge(
                          label: goal.isExcludedNonEtbVault
                              ? 'Excluded'
                              : goal.status.name,
                          tone: goal.isExcludedNonEtbVault
                              ? DaywellStatusTone.warning
                              : (goal.status == SavingsGoalStatus.completed
                                  ? DaywellStatusTone.success
                                  : DaywellStatusTone.info),
                          showIcon: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    DaywellProgressBar(
                      value: (goal.percentComplete / 100.0).clamp(0.0, 1.0),
                      label: goal.isVaultLinked
                          ? 'Vault: ${goal.linkedAccountName ?? 'Unknown'}'
                          : 'Virtual Earmark',
                      valueText:
                          '${FinanceUiFormatters.formatEtbCents(goal.allocatedCents)} / ${FinanceUiFormatters.formatEtbCents(goal.targetCents)} (${goal.percentComplete}%)',
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildMonthlyBudgetCard(
    BuildContext context,
    MonthlyBudgetProgressReport report,
  ) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly Budget Progress (${report.monthIso})',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Subcategory expenses roll up into parent category budgets',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (report.items.isNotEmpty)
                Text(
                  '${FinanceUiFormatters.formatEtbCents(report.totalSpentCents)} / ${FinanceUiFormatters.formatEtbCents(report.totalLimitCents)}',
                  style: _tabularStyle(
                    textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          if (report.items.isEmpty)
            Text(
              'No monthly budgets set for ${report.monthIso}.',
              style: textTheme.bodySmall?.copyWith(
                color: semantic.textSecondary,
              ),
            )
          else
            for (final item in report.items)
              Padding(
                padding: const EdgeInsets.only(
                  bottom: SharedDesignTokens.spacingCompact,
                ),
                child: DaywellProgressBar(
                  value: item.limitCents > 0
                      ? (item.spentCents / item.limitCents).clamp(0.0, 1.0)
                      : 0.0,
                  tone: item.isOverBudget
                      ? DaywellStatusTone.error
                      : DaywellStatusTone.success,
                  label: item.categoryName,
                  valueText:
                      '${FinanceUiFormatters.formatEtbCents(item.spentCents)} / ${FinanceUiFormatters.formatEtbCents(item.limitCents)} (${item.percentUsed}%)',
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildCategorySpendCard(
    BuildContext context,
    CanonicalCategorySpendReport report,
  ) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Category Expense Breakdown',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Canonical aliases resolved · Subcategories roll up without double counting',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Total ${FinanceUiFormatters.formatEtbCents(report.totalExpenseCents)}',
                style: _tabularStyle(
                  textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          if (report.rows.isEmpty)
            Text(
              'No categorized expenses in this reporting window.',
              style: textTheme.bodySmall?.copyWith(
                color: semantic.textSecondary,
              ),
            )
          else
            for (final row in report.rows)
              _buildCategoryHierarchyRow(context, row, depth: 0),
        ],
      ),
    );
  }

  Widget _buildCategoryHierarchyRow(
    BuildContext context,
    CategorySpendRow row, {
    required int depth,
  }) {
    final semantic = context.daywellColors;
    final labelSuffix = row.children.isNotEmpty
        ? ' (incl. ${row.children.length} sub)'
        : (row.isArchived ? ' (Archived)' : '');
    return Padding(
      padding: EdgeInsets.only(
        left: depth * SharedDesignTokens.spacingMd,
        bottom: SharedDesignTokens.spacingCompact,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DaywellProgressBar(
            value: row.exactShareRatio.clamp(0.0, 1.0),
            label: '${row.categoryName}$labelSuffix',
            valueText:
                '${FinanceUiFormatters.formatEtbCents(row.rollupCents)} (${row.sharePercent}%)',
          ),
          if (row.children.isNotEmpty) ...[
            const SizedBox(height: SharedDesignTokens.spacingXs),
            Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: semantic.border, width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final child in row.children)
                    _buildCategoryHierarchyRow(
                      context,
                      child,
                      depth: depth + 1,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAuditCard(BuildContext context, FinanceModuleState state) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final audit = state.debtControlAudit;
    final report = state.migrationReport;

    return DaywellCard(
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
                'Ledger Integrity & v7 Audit',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              DaywellButton(
                label: 'Refresh Audit',
                leadingIcon: Icons.verified_outlined,
                variant: DaywellButtonVariant.text,
                size: DaywellButtonSize.compact,
                onPressed: widget.controller.refreshAuditDiagnostics,
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingXs),
          if (audit != null) ...[
            _reportRow(
              context,
              'Debt Control Reconciliation',
              audit.isTierABalanced ? 'Balanced' : 'Mismatch Detected',
              valueColor:
                  audit.isTierABalanced ? semantic.income : semantic.error,
            ),
            if (!audit.isTierABalanced)
              for (final detail in audit.mismatchDetails)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '• $detail',
                    style: textTheme.bodySmall?.copyWith(color: semantic.error),
                  ),
                ),
          ],
          if (report != null) ...[
            const Divider(),
            _reportRow(
              context,
              'Migration Baseline',
              'v${report.fromVersion} -> v${report.toVersion}',
            ),
            _reportRow(
              context,
              'Accounts Audited / Opening Entries',
              '${report.accountsAudited} / ${report.entriesCreated}',
            ),
            if (report.legacyPaidFlaggedCount > 0)
              _reportRow(
                context,
                'Legacy Unverified Paid Flagged',
                '${report.legacyPaidFlaggedCount}',
                valueColor: semantic.warning,
              ),
            Text(
              report.summary,
              style: textTheme.bodySmall?.copyWith(
                color: semantic.textSecondary,
              ),
            ),
            for (final err in report.errors)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Error: $err',
                  style: textTheme.bodySmall?.copyWith(color: semantic.error),
                ),
              ),
            for (final warn in report.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Notice: $warn',
                  style: textTheme.bodySmall?.copyWith(color: semantic.warning),
                ),
              ),
          ] else
            Text(
              'No v7 migration warnings recorded on this database.',
              style: textTheme.bodySmall?.copyWith(
                color: semantic.textSecondary,
              ),
            ),
          const Divider(),
          Text(
            'ETB Currency Isolation Summary',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: SharedDesignTokens.spacingXs),
          _reportRow(
            context,
            'Excluded Non-ETB Accounts',
            '${state.nonEtbAccountCount}',
            valueColor: state.nonEtbAccountCount > 0 ? semantic.warning : null,
          ),
          _reportRow(
            context,
            'Unverified Currency Accounts',
            '${state.unverifiedAccountCount}',
            valueColor:
                state.unverifiedAccountCount > 0 ? semantic.warning : null,
          ),
          _reportRow(
            context,
            'Excluded Foreign Entries',
            '${state.excludedNonEtbEntryCount}',
            valueColor:
                state.excludedNonEtbEntryCount > 0 ? semantic.warning : null,
          ),
          _reportRow(
            context,
            'Currency Review Entries',
            '${state.currencyReviewEntryCount}',
            valueColor:
                state.currencyReviewEntryCount > 0 ? semantic.warning : null,
          ),
          _reportRow(
            context,
            'Unverified Legacy Paid Commitments',
            '${state.unverifiedLegacyPaidCount}',
            valueColor:
                state.unverifiedLegacyPaidCount > 0 ? semantic.warning : null,
          ),
          if (state.currencyIsolationAudit.excludedVaultGoalCount > 0)
            _reportRow(
              context,
              'Excluded / Invalid Goal Vaults',
              '${state.currencyIsolationAudit.excludedVaultGoalCount}',
              valueColor: semantic.warning,
            ),
        ],
      ),
    );
  }

  Widget _buildExportAndPortabilityCard(
    BuildContext context,
    FinanceModuleState state,
    String todayIso,
  ) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reports Export & Finance-Only Portability Hub',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: SharedDesignTokens.spacingXs),
          Text(
            'Finance-only JSON export and restore operate strictly on Finance records and preserve Tasks, Notes, Projects, Calendar events, Reminders, and Inbox items untouched. Full cross-module device backups live in Settings.',
            style: textTheme.bodySmall?.copyWith(color: semantic.textSecondary),
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          Text(
            'Finance-Only Portability (JSON)',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Wrap(
            spacing: SharedDesignTokens.spacingSm,
            runSpacing: SharedDesignTokens.spacingSm,
            children: [
              DaywellButton(
                label: 'Export Finance-Only JSON',
                leadingIcon: Icons.download_outlined,
                variant: DaywellButtonVariant.primary,
                size: DaywellButtonSize.compact,
                onPressed: () async {
                  try {
                    final json =
                        await widget.controller.exportFinanceOnlyJson();
                    if (!context.mounted) return;
                    await _showExportPreviewDialog(
                      context,
                      filename: 'daywell_finance_only_$todayIso.json',
                      payload: json,
                    );
                  } catch (e) {
                    if (!mounted) return;
                    setState(() {
                      _portabilityStatusMessage = e.toString();
                      _portabilityStatusIsError = true;
                    });
                  }
                },
              ),
              DaywellButton(
                label: 'Restore Finance-Only JSON',
                leadingIcon: Icons.upload_outlined,
                variant: DaywellButtonVariant.outlined,
                size: DaywellButtonSize.compact,
                onPressed: () => _openFinanceOnlyImportDialog(context),
              ),
            ],
          ),
          if (_portabilityStatusMessage != null) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            DaywellStatusBanner(
              message: _portabilityStatusMessage!,
              tone: _portabilityStatusIsError
                  ? DaywellStatusTone.error
                  : DaywellStatusTone.success,
              onDismiss: () {
                setState(() => _portabilityStatusMessage = null);
              },
            ),
          ],
          const Divider(),
          Text(
            'Analytical SQLite Script (13 Tables)',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          _exportButton(
            context,
            label: 'Analytical SQLite (.sql)',
            filename: 'daywell_finance_export_$todayIso.sql',
            builder: () => FinanceExportService.exportSqliteAnalyticalScript(
              accounts: state.accounts,
              categories: state.categories,
              parties: state.parties,
              entries: state.journalEntries,
              postings: state.postings,
              debts: state.debts,
              allocations: state.settlementAllocations,
              budgets: state.budgets,
              recurringRules: state.recurringRules,
              commitments: state.commitments,
              commitmentSettlements: state.commitmentSettlements,
              savingsGoals: state.savingsGoals,
              transactions: state.transactions,
            ),
          ),
          const Divider(),
          Text(
            'Individual Finance CSV Tables (13 UTF-8 BOM)',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Wrap(
            spacing: SharedDesignTokens.spacingSm,
            runSpacing: SharedDesignTokens.spacingSm,
            children: [
              _exportButton(
                context,
                label: 'Accounts CSV',
                filename: 'daywell_accounts_$todayIso.csv',
                builder: () => FinanceExportService.exportAccountsCsv(
                  state.accounts,
                  state.postings,
                  entries: state.journalEntries,
                ),
              ),
              _exportButton(
                context,
                label: 'Categories CSV',
                filename: 'daywell_categories_$todayIso.csv',
                builder: () =>
                    FinanceExportService.exportCategoriesCsv(state.categories),
              ),
              _exportButton(
                context,
                label: 'Parties CSV',
                filename: 'daywell_parties_$todayIso.csv',
                builder: () =>
                    FinanceExportService.exportPartiesCsv(state.parties),
              ),
              _exportButton(
                context,
                label: 'Journal Entries CSV',
                filename: 'daywell_journal_entries_$todayIso.csv',
                builder: () => FinanceExportService.exportJournalEntriesCsv(
                  state.journalEntries,
                  postings: state.postings,
                  accounts: state.accounts,
                  debts: state.debts,
                  allocations: state.settlementAllocations,
                ),
              ),
              _exportButton(
                context,
                label: 'Postings CSV',
                filename: 'daywell_postings_$todayIso.csv',
                builder: () =>
                    FinanceExportService.exportPostingsCsv(state.postings),
              ),
              _exportButton(
                context,
                label: 'Debts CSV',
                filename: 'daywell_debts_$todayIso.csv',
                builder: () => FinanceExportService.exportDebtsCsv(
                  state.debts,
                  entries: state.journalEntries,
                  postings: state.postings,
                  accounts: state.accounts,
                  allocations: state.settlementAllocations,
                ),
              ),
              _exportButton(
                context,
                label: 'Settlement Allocations CSV',
                filename: 'daywell_settlement_allocations_$todayIso.csv',
                builder: () =>
                    FinanceExportService.exportSettlementAllocationsCsv(
                  state.settlementAllocations,
                ),
              ),
              _exportButton(
                context,
                label: 'Commitments CSV',
                filename: 'daywell_commitments_$todayIso.csv',
                builder: () => FinanceExportService.exportCommitmentsCsv(
                  state.commitments,
                  accounts: state.accounts,
                  debts: state.debts,
                  entries: state.journalEntries,
                  postings: state.postings,
                  allocations: state.settlementAllocations,
                  recurringRules: state.recurringRules,
                  settlements: state.commitmentSettlements,
                ),
              ),
              _exportButton(
                context,
                label: 'Commitment Settlements CSV',
                filename: 'daywell_commitment_settlements_$todayIso.csv',
                builder: () =>
                    FinanceExportService.exportCommitmentSettlementsCsv(
                  state.commitmentSettlements,
                ),
              ),
              _exportButton(
                context,
                label: 'Savings Goals CSV',
                filename: 'daywell_savings_goals_$todayIso.csv',
                builder: () => FinanceExportService.exportSavingsGoalsCsv(
                  state.savingsGoals,
                ),
              ),
              _exportButton(
                context,
                label: 'Budgets CSV',
                filename: 'daywell_budgets_$todayIso.csv',
                builder: () =>
                    FinanceExportService.exportBudgetsCsv(state.budgets),
              ),
              _exportButton(
                context,
                label: 'Recurring Rules CSV',
                filename: 'daywell_recurring_rules_$todayIso.csv',
                builder: () => FinanceExportService.exportRecurringRulesCsv(
                  state.recurringRules,
                ),
              ),
              _exportButton(
                context,
                label: 'Transactions CSV',
                filename: 'daywell_transactions_$todayIso.csv',
                builder: () => FinanceExportService.exportTransactionsCsv(
                  state.transactions,
                  entries: state.journalEntries,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openFinanceOnlyImportDialog(BuildContext context) async {
    final textCtrl = TextEditingController();
    final submitted = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Restore Finance-Only JSON'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paste a Finance-only JSON snapshot (financeOnly: true). Only Finance tables will be replaced; Tasks, Notes, Projects, Calendar, Reminders, and Inbox stay untouched. Full backups must be restored from Settings.',
                style: Theme.of(dialogCtx).textTheme.bodySmall,
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
              TextField(
                controller: textCtrl,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: '{"financeOnly": true, ...}',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: SharedDesignTokens.spacingXs),
              DaywellButton(
                label: 'Paste from Clipboard',
                leadingIcon: Icons.content_paste_outlined,
                variant: DaywellButtonVariant.text,
                size: DaywellButtonSize.compact,
                onPressed: () async {
                  final clip = await Clipboard.getData(Clipboard.kTextPlain);
                  if (clip?.text != null) {
                    textCtrl.text = clip!.text!;
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          DaywellButton(
            label: 'Cancel',
            variant: DaywellButtonVariant.text,
            size: DaywellButtonSize.compact,
            onPressed: () => Navigator.of(dialogCtx).pop(),
          ),
          DaywellButton(
            label: 'Restore Finance',
            variant: DaywellButtonVariant.primary,
            size: DaywellButtonSize.compact,
            onPressed: () => Navigator.of(dialogCtx).pop(textCtrl.text.trim()),
          ),
        ],
      ),
    );
    textCtrl.dispose();
    if (submitted == null || submitted.isEmpty || !mounted) return;

    final ok = await widget.controller.importFinanceOnlyJson(submitted);
    if (!mounted) return;
    setState(() {
      if (ok) {
        _portabilityStatusIsError = false;
        _portabilityStatusMessage =
            'Finance-only snapshot restored cleanly. Tasks, Notes, Projects, Calendar, Reminders, and Inbox were preserved untouched.';
      } else {
        _portabilityStatusIsError = true;
        _portabilityStatusMessage =
            'Finance restore rejected (existing data preserved): ${widget.controller.state.errorMessage ?? 'Invalid payload.'}';
      }
    });
  }

  Widget _periodChip(ReportPeriodMode mode, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _periodMode == mode,
      onSelected: (selected) async {
        if (!selected) return;
        if (mode == ReportPeriodMode.custom) {
          final today = CalendarDate.today();
          final start = await FinanceUiFormatters.pickCalendarDate(
            context,
            initialDate: _customStart ?? today.addDays(-30),
          );
          if (start == null || !mounted) return;
          final end = await FinanceUiFormatters.pickCalendarDate(
            context,
            initialDate: _customEnd ?? today,
            firstDate: start,
          );
          if (end == null || !mounted) return;
          setState(() {
            _customStart = start;
            _customEnd = end;
            _periodMode = ReportPeriodMode.custom;
          });
        } else {
          setState(() => _periodMode = mode);
        }
      },
    );
  }

  Widget _reportMetricDeltaRow(
    BuildContext context, {
    required String label,
    required String value,
    required Color valueColor,
    required MetricComparisonDelta delta,
  }) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: semantic.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: SharedDesignTokens.spacingSm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: _tabularStyle(
                  textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: valueColor,
                  ),
                ),
              ),
              Text(
                _formatDeltaText(delta),
                style: _tabularStyle(
                  textTheme.labelSmall?.copyWith(
                    color: _deltaColor(context, delta),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reportRow(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
  }) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: semantic.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: SharedDesignTokens.spacingSm),
          Text(
            value,
            style: _tabularStyle(
              textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: valueColor ?? semantic.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exportButton(
    BuildContext context, {
    required String label,
    required String filename,
    required String Function() builder,
  }) {
    return DaywellButton(
      label: label,
      leadingIcon: Icons.download_outlined,
      variant: DaywellButtonVariant.outlined,
      size: DaywellButtonSize.compact,
      onPressed: () {
        final payload = builder();
        _showExportPreviewDialog(context, filename: filename, payload: payload);
      },
    );
  }

  Future<void> _showExportPreviewDialog(
    BuildContext context, {
    required String filename,
    required String payload,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(filename),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: SelectableText(
              payload,
              style: _tabularStyle(Theme.of(dialogCtx).textTheme.bodySmall),
            ),
          ),
        ),
        actions: [
          DaywellButton(
            label: 'Copy',
            leadingIcon: Icons.copy,
            variant: DaywellButtonVariant.outlined,
            size: DaywellButtonSize.compact,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: payload));
              if (dialogCtx.mounted) {
                ScaffoldMessenger.of(dialogCtx).showSnackBar(
                  SnackBar(content: Text('Copied $filename to clipboard.')),
                );
              }
            },
          ),
          DaywellButton(
            label: 'Share',
            leadingIcon: Icons.share_outlined,
            variant: DaywellButtonVariant.primary,
            size: DaywellButtonSize.compact,
            onPressed: () async {
              try {
                await Share.share(payload, subject: filename);
              } catch (_) {
                await Clipboard.setData(ClipboardData(text: payload));
              }
            },
          ),
          DaywellButton(
            label: 'Close',
            variant: DaywellButtonVariant.text,
            size: DaywellButtonSize.compact,
            onPressed: () => Navigator.of(dialogCtx).pop(),
          ),
        ],
      ),
    );
  }
}
