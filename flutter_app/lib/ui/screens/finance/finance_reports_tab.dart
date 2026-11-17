import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../application/finance/finance_controller.dart';
import '../../../application/finance/finance_state.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/finance/double_entry_engine.dart';
import '../../../services/export/finance_export_service.dart';
import '../../widgets/shared_ui_widgets.dart';
import 'finance_formatters.dart';

enum _ReportPeriodMode {
  thisMonth,
  last30Days,
  thisYear,
  ethiopianMonth,
  custom,
}

/// Stage 4.15 Reports & Export Hub Tab: Cashflow P&L, Category Spend Breakdown
/// (with Gregorian & Ethiopian Calendar Pagume period support), Account Balance Sheet
/// (with Option 1 Prepaid Card Credit), Ledger Integrity & v7 Migration Audit,
/// and Export Hub powered by reconciled v7 CSV / SQLite exporters.
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
  _ReportPeriodMode _periodMode = _ReportPeriodMode.thisMonth;
  late int _ethYear;
  late int _ethMonth;
  CalendarDate? _customStart;
  CalendarDate? _customEnd;

  @override
  void initState() {
    super.initState();
    final ethToday = EthiopianDate.today();
    _ethYear = ethToday.year;
    _ethMonth = ethToday.month;
  }

  ({CalendarDate start, CalendarDate end, String label}) _resolveRange() {
    final today = CalendarDate.today();
    switch (_periodMode) {
      case _ReportPeriodMode.thisMonth:
        final bounds = CalendarDate.monthBounds(
          CalendarSystem.gregorian,
          today.year,
          today.month,
        );
        return (
          start: bounds.start,
          end: bounds.end,
          label: '${today.gregorianFullMonthName} ${today.year}',
        );
      case _ReportPeriodMode.last30Days:
        final start = today.addDays(-29);
        return (
          start: start,
          end: today,
          label:
              'Last 30 Days (${start.toIsoString()} - ${today.toIsoString()})',
        );
      case _ReportPeriodMode.thisYear:
        final bounds = CalendarDate.yearBounds(
          CalendarSystem.gregorian,
          today.year,
        );
        return (
          start: bounds.start,
          end: bounds.end,
          label: 'Gregorian Year ${today.year}',
        );
      case _ReportPeriodMode.ethiopianMonth:
        final bounds = CalendarDate.monthBounds(
          CalendarSystem.ethiopian,
          _ethYear,
          _ethMonth,
        );
        final ethStart =
            EthiopianDate(year: _ethYear, month: _ethMonth, day: 1);
        return (
          start: bounds.start,
          end: bounds.end,
          label:
              '${ethStart.englishMonthName} (${ethStart.amharicMonthName}) $_ethYear E.C.',
        );
      case _ReportPeriodMode.custom:
        final start = _customStart ?? today.addDays(-30);
        final end = _customEnd ?? today;
        return (
          start: start,
          end: end,
          label: '${start.toIsoString()} to ${end.toIsoString()}',
        );
    }
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

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final range = _resolveRange();
    final pnl = state.occurrencePnlForRange(range.start, range.end);
    final cashflow = state.liquidCashflowForRange(range.start, range.end);
    final categorySpend = DoubleEntryEngine.calculateCategorySpendForPeriod(
      postings: state.postings,
      entries: state.journalEntries,
      startDateIso: range.start.toIsoString(),
      endDateIso: range.end.toIsoString(),
      categories: state.categories,
      accounts: state.accounts,
      debts: state.debts,
      allocations: state.settlementAllocations,
      rollupToParents: true,
    );
    final sortedCategories = categorySpend.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalCatExpense =
        sortedCategories.fold<int>(0, (s, e) => s + e.value);
    final categoryById = {for (final c in state.categories) c.id: c};

    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      children: [
        // 1. Period Picker
        DaywellCard(
          padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report Period',
                style:
                    textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
              Wrap(
                spacing: SharedDesignTokens.spacingSm,
                runSpacing: SharedDesignTokens.spacingSm,
                children: [
                  _periodChip(_ReportPeriodMode.thisMonth, 'This Month'),
                  _periodChip(_ReportPeriodMode.last30Days, '30 Days'),
                  _periodChip(_ReportPeriodMode.thisYear, 'Year'),
                  _periodChip(
                    _ReportPeriodMode.ethiopianMonth,
                    'Ethiopian Month',
                  ),
                  _periodChip(_ReportPeriodMode.custom, 'Custom'),
                ],
              ),
              if (_periodMode == _ReportPeriodMode.ethiopianMonth) ...[
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
                      range.label,
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
              const SizedBox(height: SharedDesignTokens.spacingXs),
              Text(
                'Active Window: ${range.label}',
                style: textTheme.bodySmall?.copyWith(
                  color: semantic.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: SharedDesignTokens.spacingMd),

        // 2. Occurrence P&L Card (Economic Date)
        DaywellCard(
          padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Occurrence P&L (Economic Date)',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              _reportRow(
                context,
                'Total Income',
                FinanceUiFormatters.formatEtbCents(
                  pnl.incomeCents,
                  includePlusSign: true,
                ),
                valueColor: semantic.income,
              ),
              _reportRow(
                context,
                'Total Expense',
                FinanceUiFormatters.formatEtbCents(-pnl.expenseCents),
                valueColor: semantic.expense,
              ),
              const Divider(),
              _reportRow(
                context,
                'Net Income (P&L)',
                FinanceUiFormatters.formatEtbCents(
                  pnl.netCashflowCents,
                  includePlusSign: true,
                ),
                valueColor: pnl.netCashflowCents >= 0
                    ? semantic.income
                    : semantic.error,
              ),
            ],
          ),
        ),
        const SizedBox(height: SharedDesignTokens.spacingMd),

        // 2b. Liquid Cash Flow Card (Account Movement Date)
        DaywellCard(
          padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Liquid Cash Flow (Movement Date)',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              _reportRow(
                context,
                'Liquid Inflow',
                FinanceUiFormatters.formatEtbCents(
                  cashflow.inflowCents,
                  includePlusSign: true,
                ),
                valueColor: semantic.income,
              ),
              _reportRow(
                context,
                'Liquid Outflow',
                FinanceUiFormatters.formatEtbCents(-cashflow.outflowCents),
                valueColor: semantic.expense,
              ),
              const Divider(),
              _reportRow(
                context,
                'Net Liquid Cash Flow',
                FinanceUiFormatters.formatEtbCents(
                  cashflow.netCashflowCents,
                  includePlusSign: true,
                ),
                valueColor: cashflow.netCashflowCents >= 0
                    ? semantic.income
                    : semantic.error,
              ),
            ],
          ),
        ),
        const SizedBox(height: SharedDesignTokens.spacingMd),

        // 3. Category Breakdown
        DaywellCard(
          padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Category Expense Breakdown',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              if (sortedCategories.isEmpty)
                Text(
                  'No categorized expenses in this reporting window.',
                  style: textTheme.bodySmall?.copyWith(
                    color: semantic.textSecondary,
                  ),
                )
              else
                for (final entry in sortedCategories) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: SharedDesignTokens.spacingCompact,
                    ),
                    child: DaywellProgressBar(
                      value: totalCatExpense > 0
                          ? (entry.value / totalCatExpense).clamp(0.0, 1.0)
                          : 0.0,
                      label: categoryById[entry.key]?.name ?? entry.key,
                      valueText:
                          FinanceUiFormatters.formatEtbCents(entry.value),
                    ),
                  ),
                ],
            ],
          ),
        ),
        const SizedBox(height: SharedDesignTokens.spacingMd),

        // 4. Balance Sheet Snapshot
        DaywellCard(
          padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Account Balance Sheet',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              _reportRow(
                context,
                'Liquid Assets',
                FinanceUiFormatters.formatEtbCents(state.liquidCashCents),
              ),
              _reportRow(
                context,
                'Savings Vaults',
                FinanceUiFormatters.formatEtbCents(state.vaultSavingsCents),
              ),
              _reportRow(
                context,
                'Active Receivables',
                FinanceUiFormatters.formatEtbCents(state.totalReceivablesCents),
              ),
              if (state.prepaidCardCreditCents > 0)
                _reportRow(
                  context,
                  'Prepaid Card Credit (Included)',
                  FinanceUiFormatters.formatEtbCents(
                    state.prepaidCardCreditCents,
                  ),
                  valueColor: semantic.income,
                ),
              _reportRow(
                context,
                'Credit Card Liabilities',
                FinanceUiFormatters.formatEtbCents(
                  -state.shortTermCreditOwedCents,
                ),
                valueColor: semantic.expense,
              ),
              _reportRow(
                context,
                'Active Payables',
                FinanceUiFormatters.formatEtbCents(-state.totalPayablesCents),
                valueColor: semantic.expense,
              ),
              const Divider(),
              _reportRow(
                context,
                'Net Financial Position (Assets - Liabilities)',
                FinanceUiFormatters.formatEtbCents(
                  state.netFinancialPositionCents,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: SharedDesignTokens.spacingMd),

        // 5. v7 Ledger Integrity & Migration Diagnostic Audit
        _buildAuditCard(context, state),
        const SizedBox(height: SharedDesignTokens.spacingMd),

        // 6. Export Hub
        DaywellCard(
          padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Export Hub',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: SharedDesignTokens.spacingXs),
              Text(
                'Export reconciled v7 CSV tables or a standalone SQLite database script.',
                style: textTheme.bodySmall?.copyWith(
                  color: semantic.textSecondary,
                ),
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              Wrap(
                spacing: SharedDesignTokens.spacingSm,
                runSpacing: SharedDesignTokens.spacingSm,
                children: [
                  _exportButton(
                    context,
                    label: 'Accounts CSV',
                    filename: 'daywell_accounts.csv',
                    builder: () => FinanceExportService.exportAccountsCsv(
                      state.accounts,
                      state.postings,
                      entries: state.journalEntries,
                    ),
                  ),
                  _exportButton(
                    context,
                    label: 'Journal Entries CSV',
                    filename: 'daywell_journal_entries.csv',
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
                    filename: 'daywell_postings.csv',
                    builder: () => FinanceExportService.exportPostingsCsv(
                      state.postings,
                    ),
                  ),
                  _exportButton(
                    context,
                    label: 'Debts CSV',
                    filename: 'daywell_debts.csv',
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
                    label: 'Commitments CSV',
                    filename: 'daywell_commitments.csv',
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
                    label: 'Budgets CSV',
                    filename: 'daywell_budgets.csv',
                    builder: () => FinanceExportService.exportBudgetsCsv(
                      state.budgets,
                    ),
                  ),
                  _exportButton(
                    context,
                    label: 'Recurring CSV',
                    filename: 'daywell_recurring_rules.csv',
                    builder: () => FinanceExportService.exportRecurringRulesCsv(
                      state.recurringRules,
                    ),
                  ),
                  _exportButton(
                    context,
                    label: 'SQLite SQL Script',
                    filename: 'daywell_finance_v7.sql',
                    builder: () =>
                        FinanceExportService.exportSqliteAnalyticalScript(
                      accounts: state.accounts,
                      categories: state.categories,
                      parties: state.parties,
                      entries: state.journalEntries,
                      postings: state.postings,
                      debts: state.debts,
                      allocations: state.settlementAllocations,
                      budgets: state.budgets,
                      recurringRules: state.recurringRules,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: SharedDesignTokens.spacingLg),
      ],
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

  Widget _periodChip(_ReportPeriodMode mode, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _periodMode == mode,
      onSelected: (selected) async {
        if (!selected) return;
        if (mode == _ReportPeriodMode.custom) {
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
            _periodMode = _ReportPeriodMode.custom;
          });
        } else {
          setState(() => _periodMode = mode);
        }
      },
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
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: valueColor ?? semantic.textPrimary,
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
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
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
