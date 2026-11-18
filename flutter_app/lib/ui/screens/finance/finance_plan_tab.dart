import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../application/finance/finance_controller.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/finance/double_entry_engine.dart';
import '../../../domain/finance/finance_models.dart';
import '../../widgets/shared_ui_widgets.dart';
import 'finance_formatters.dart';

/// Stages 4.10 & 4.13 Plan Tab: Monthly Category Budgets, Commitments & Bills,
/// Recurring Rules, Savings Goals (Vault vs Virtual Reserve), and Debts & Parties.
class FinancePlanTab extends StatefulWidget {
  final FinanceController controller;

  const FinancePlanTab({
    super.key,
    required this.controller,
  });

  @override
  State<FinancePlanTab> createState() => _FinancePlanTabState();
}

class _FinancePlanTabState extends State<FinancePlanTab> {
  static const Uuid _uuid = Uuid();
  String _sectionFilter =
      'all'; // all, budgets, commitments, recurring, savings, debts
  late int _budgetYear;
  late int _budgetMonth;
  bool _showSettledDebts = false;

  @override
  void initState() {
    super.initState();
    final today = CalendarDate.today();
    _budgetYear = today.year;
    _budgetMonth = today.month;
  }

  String get _budgetMonthIso =>
      '${_budgetYear.toString().padLeft(4, '0')}-${_budgetMonth.toString().padLeft(2, '0')}';

  void _shiftBudgetMonth(int delta) {
    setState(() {
      var m = _budgetMonth + delta;
      var y = _budgetYear;
      while (m > 12) {
        m -= 12;
        y += 1;
      }
      while (m < 1) {
        m += 12;
        y -= 1;
      }
      _budgetYear = y;
      _budgetMonth = m;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      children: [
        // Planning Horizon Control
        DaywellCard(
          padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
          child: Wrap(
            spacing: SharedDesignTokens.spacingSm,
            runSpacing: SharedDesignTokens.spacingXs,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Safe Harbor Planning Horizon',
                    style: textTheme.labelMedium?.copyWith(
                      color: semantic.textSecondary,
                    ),
                  ),
                  Text(
                    SharedDateFormatter.formatDual(
                      state.effectivePlanningPeriodEnd,
                      useAmharic: false,
                    ),
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: SharedDesignTokens.spacingXs,
                children: [
                  DaywellButton(
                    label: 'Set Date',
                    variant: DaywellButtonVariant.outlined,
                    size: DaywellButtonSize.compact,
                    onPressed: () async {
                      final picked = await FinanceUiFormatters.pickCalendarDate(
                        context,
                        initialDate: state.effectivePlanningPeriodEnd,
                      );
                      if (picked != null) {
                        widget.controller.setPlanningPeriodEnd(picked);
                      }
                    },
                  ),
                  if (state.planningPeriodEnd != null)
                    DaywellButton(
                      label: 'Reset',
                      variant: DaywellButtonVariant.text,
                      size: DaywellButtonSize.compact,
                      onPressed: () =>
                          widget.controller.setPlanningPeriodEnd(null),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: SharedDesignTokens.spacingCompact),

        // Sub-section filter chips
        Wrap(
          spacing: SharedDesignTokens.spacingSm,
          runSpacing: SharedDesignTokens.spacingSm,
          children: [
            _filterChip('all', 'All'),
            _filterChip('budgets', 'Budgets'),
            _filterChip('commitments', 'Bills'),
            _filterChip('recurring', 'Recurring'),
            _filterChip('savings', 'Savings'),
            _filterChip('debts', 'Debts & Parties'),
          ],
        ),
        const SizedBox(height: SharedDesignTokens.spacingMd),

        if (_sectionFilter == 'all' || _sectionFilter == 'budgets') ...[
          _buildBudgetsSection(context),
          const SizedBox(height: SharedDesignTokens.spacingLg),
        ],
        if (_sectionFilter == 'all' || _sectionFilter == 'commitments') ...[
          _buildCommitmentsSection(context),
          const SizedBox(height: SharedDesignTokens.spacingLg),
        ],
        if (_sectionFilter == 'all' || _sectionFilter == 'recurring') ...[
          _buildRecurringSection(context),
          const SizedBox(height: SharedDesignTokens.spacingLg),
        ],
        if (_sectionFilter == 'all' || _sectionFilter == 'savings') ...[
          _buildSavingsSection(context),
          const SizedBox(height: SharedDesignTokens.spacingLg),
        ],
        if (_sectionFilter == 'all' || _sectionFilter == 'debts') ...[
          _buildDebtsAndPartiesSection(context),
          const SizedBox(height: SharedDesignTokens.spacingLg),
        ],
      ],
    );
  }

  Widget _filterChip(String id, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _sectionFilter == id,
      onSelected: (_) => setState(() => _sectionFilter = id),
    );
  }

  // ==================== 1. BUDGETS SECTION ====================

  Widget _buildBudgetsSection(BuildContext context) {
    final state = widget.controller.state;
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final monthIso = _budgetMonthIso;
    final monthBudgets =
        state.budgets.where((b) => b.monthIso == monthIso).toList();
    final monthParts = monthIso.split('-');
    final todayCal = CalendarDate.today();
    final budgetYear = monthParts.length == 2
        ? (int.tryParse(monthParts[0]) ?? todayCal.year)
        : todayCal.year;
    final budgetMonth = monthParts.length == 2
        ? (int.tryParse(monthParts[1]) ?? todayCal.month).clamp(1, 12)
        : todayCal.month;
    final monthBounds = CalendarDate.monthBounds(
      CalendarSystem.gregorian,
      budgetYear,
      budgetMonth,
    );
    final spendReport = DoubleEntryEngine.calculateCanonicalCategorySpend(
      entries: state.journalEntries,
      postings: state.postings,
      accounts: state.accounts,
      categories: state.categories,
      debts: state.debts,
      allocations: state.settlementAllocations,
      startDateIso: monthBounds.start.toIsoString(),
      endDateIso: monthBounds.end.toIsoString(),
    );
    final categoryById = {for (final c in state.categories) c.id: c};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DaywellSectionHeader(
          title: 'Monthly Category Budgets',
          count: monthBudgets.length,
          actionLabel: '+ Add Budget',
          onActionPressed: () => _openBudgetEditorSheet(context),
        ),
        const SizedBox(height: SharedDesignTokens.spacingSm),
        Wrap(
          spacing: SharedDesignTokens.spacingSm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DaywellIconButton(
              icon: Icons.chevron_left,
              tooltip: 'Previous month',
              onPressed: () => _shiftBudgetMonth(-1),
            ),
            Text(
              monthIso,
              style:
                  textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            DaywellIconButton(
              icon: Icons.chevron_right,
              tooltip: 'Next month',
              onPressed: () => _shiftBudgetMonth(1),
            ),
          ],
        ),
        const SizedBox(height: SharedDesignTokens.spacingSm),
        if (monthBudgets.isEmpty)
          DaywellEmptyState(
            icon: Icons.pie_chart_outline,
            message: 'No budgets set for $monthIso',
            subtitle:
                'Set monthly spending caps by category to monitor burn rate.',
            actionLabel: 'Set Category Budget',
            onActionPressed: () => _openBudgetEditorSheet(context),
          )
        else
          for (final budget in monthBudgets) ...[
            Builder(
              builder: (ctx) {
                final spent = DoubleEntryEngine.getCanonicalBudgetSpentCents(
                  spendReport,
                  budget.categoryId,
                  state.categories,
                );
                final limit = budget.limitCents <= 0 ? 1 : budget.limitCents;
                final ratio = spent / limit;
                final tone = ratio > 1.0
                    ? DaywellStatusTone.error
                    : (ratio >= 0.8
                        ? DaywellStatusTone.warning
                        : DaywellStatusTone.success);
                final catLabel = FinanceUiFormatters.formatCategoryBreadcrumb(
                  budget.categoryId,
                  categoryById,
                );
                return DaywellCard(
                  padding:
                      const EdgeInsets.all(SharedDesignTokens.spacingCompact),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              catLabel,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (budget.rolloverEnabled)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: DaywellStatusBadge(
                                label: 'Rollover',
                                tone: DaywellStatusTone.info,
                                showIcon: false,
                              ),
                            ),
                          DaywellIconButton(
                            icon: Icons.edit_outlined,
                            tooltip: 'Edit budget',
                            iconSize: DaywellIconSize.sm,
                            onPressed: () => _openBudgetEditorSheet(
                              context,
                              existing: budget,
                            ),
                          ),
                          DaywellIconButton(
                            icon: Icons.delete_outline,
                            tooltip: 'Delete budget',
                            iconSize: DaywellIconSize.sm,
                            isDestructive: true,
                            onPressed: () async {
                              final ok = await DaywellConfirmationDialog.show(
                                context,
                                title: 'Delete Budget?',
                                message:
                                    'Remove budget for "$catLabel" ($monthIso)?',
                                confirmLabel: 'Delete',
                                isDestructive: true,
                              );
                              if (ok) {
                                await widget.controller.deleteBudget(budget.id);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingSm),
                      DaywellProgressBar(
                        value: ratio.clamp(0.0, 1.0),
                        tone: tone,
                        label: '${(ratio * 100).round()}% used',
                        valueText:
                            '${FinanceUiFormatters.formatEtbCents(spent)} / ${FinanceUiFormatters.formatEtbCents(budget.limitCents)}',
                      ),
                      if (spent > budget.limitCents)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Over budget by ${FinanceUiFormatters.formatEtbCents(spent - budget.limitCents)}',
                            style: textTheme.labelSmall?.copyWith(
                              color: semantic.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
          ],
      ],
    );
  }

  // ==================== 2. COMMITMENTS & BILLS ====================

  Widget _buildCommitmentsSection(BuildContext context) {
    final state = widget.controller.state;
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final today = CalendarDate.today();
    final sorted = List<CommitmentModel>.from(state.commitments)
      ..sort((a, b) {
        if (a.isPaid != b.isPaid) return a.isPaid ? 1 : -1;
        return a.dueDate.jdn.compareTo(b.dueDate.jdn);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DaywellSectionHeader(
          title: 'Commitments & Upcoming Bills',
          count: state.pendingCommitments.length,
          actionLabel: '+ Add Bill',
          onActionPressed: () => _openCommitmentEditorSheet(context),
        ),
        const SizedBox(height: SharedDesignTokens.spacingCompact),
        if (sorted.isEmpty)
          DaywellEmptyState(
            icon: Icons.event_note_outlined,
            message: 'No financial commitments',
            subtitle:
                'Track upcoming rent, utilities, and scheduled debt installments.',
            actionLabel: 'Add Commitment',
            onActionPressed: () => _openCommitmentEditorSheet(context),
          )
        else
          for (final item in sorted) ...[
            Builder(
              builder: (ctx) {
                final cmRes = state.resolveCommitmentCurrency(item);
                final etbAccounts = state.activeEtbUserAccounts;
                final isOverdue = !item.isPaid && item.dueDate.jdn < today.jdn;
                final tone = item.isPaid
                    ? DaywellStatusTone.success
                    : (isOverdue
                        ? DaywellStatusTone.error
                        : DaywellStatusTone.warning);
                final amountLabel = FinanceUiFormatters.formatCurrencyCents(
                  item.amountCents,
                  currencyCode:
                      cmRes.isEligibleEtb ? 'ETB' : cmRes.currencyCode,
                );
                return DaywellCard(
                  padding:
                      const EdgeInsets.all(SharedDesignTokens.spacingCompact),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                decoration: item.isPaid
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                          Text(
                            amountLabel,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: item.isPaid
                                  ? semantic.textMuted
                                  : (cmRes.needsReview
                                      ? semantic.warning
                                      : semantic.textPrimary),
                            ),
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
                            'Due: ${SharedDateFormatter.formatDual(item.dueDate, useAmharic: false)}',
                            style: textTheme.bodySmall?.copyWith(
                              color: semantic.textSecondary,
                            ),
                          ),
                          DaywellStatusBadge(
                            label: item.isPaid
                                ? 'Paid'
                                : (isOverdue ? 'Overdue' : 'Due'),
                            tone: tone,
                          ),
                          if (item.linkedDebtId != null)
                            const DaywellStatusBadge(
                              label: 'Debt Linked',
                              tone: DaywellStatusTone.info,
                              showIcon: false,
                            ),
                          if (cmRes.isExpectedIncome)
                            const DaywellStatusBadge(
                              label: 'Expected Income',
                              tone: DaywellStatusTone.info,
                              showIcon: false,
                            ),
                          if (cmRes.isExcludedNonEtb)
                            DaywellStatusBadge(
                              label:
                                  'Excluded (${cmRes.currencyCode ?? 'Non-ETB'})',
                              tone: DaywellStatusTone.warning,
                              showIcon: false,
                            )
                          else if (cmRes.needsReview)
                            const DaywellStatusBadge(
                              label: 'Currency Review',
                              tone: DaywellStatusTone.warning,
                            ),
                        ],
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingSm),
                      Wrap(
                        spacing: SharedDesignTokens.spacingSm,
                        runSpacing: SharedDesignTokens.spacingXs,
                        children: [
                          if (!item.isPaid && cmRes.isEligibleEtb)
                            DaywellButton(
                              label:
                                  item.direction == CommitmentDirection.inflow
                                      ? 'Record Receipt'
                                      : 'Mark Paid',
                              leadingIcon: Icons.check_circle_outline,
                              variant: DaywellButtonVariant.secondary,
                              size: DaywellButtonSize.compact,
                              onPressed: () =>
                                  _openMarkCommitmentPaidSheet(context, item),
                            ),
                          if (!item.isPaid &&
                              cmRes.needsReview &&
                              item.linkedDebtId == null &&
                              etbAccounts.isNotEmpty)
                            DaywellButton(
                              label: 'Link ETB Account',
                              leadingIcon: Icons.link,
                              variant: DaywellButtonVariant.secondary,
                              size: DaywellButtonSize.compact,
                              onPressed: () => _promptLinkCommitmentAccount(
                                context,
                                item,
                                etbAccounts,
                              ),
                            ),
                          if (!item.isPaid)
                            DaywellButton(
                              label: 'Edit',
                              variant: DaywellButtonVariant.outlined,
                              size: DaywellButtonSize.compact,
                              onPressed: () => _openCommitmentEditorSheet(
                                context,
                                existing: item,
                              ),
                            ),
                          DaywellButton(
                            label: 'Delete',
                            variant: DaywellButtonVariant.text,
                            size: DaywellButtonSize.compact,
                            onPressed: () async {
                              final ok = await DaywellConfirmationDialog.show(
                                context,
                                title: 'Delete Commitment?',
                                message: 'Remove "${item.title}"?',
                                confirmLabel: 'Delete',
                                isDestructive: true,
                              );
                              if (ok) {
                                await widget.controller
                                    .deleteCommitment(item.id);
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
          ],
      ],
    );
  }

  // ==================== 3. RECURRING RULES ====================

  Widget _buildRecurringSection(BuildContext context) {
    final state = widget.controller.state;
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final accountById = {for (final a in state.accounts) a.id: a};
    final debtById = {for (final d in state.debts) d.id: d};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DaywellSectionHeader(
          title: 'Recurring Rules & Schedules',
          count: state.activeRecurringRules.length,
          actionLabel: '+ Add Rule',
          onActionPressed: () => _openRecurringRuleSheet(context),
        ),
        const SizedBox(height: SharedDesignTokens.spacingSm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DaywellButton(
            label: 'Process Due Schedules',
            leadingIcon: Icons.play_arrow_outlined,
            variant: DaywellButtonVariant.outlined,
            size: DaywellButtonSize.compact,
            onPressed: () async {
              final count = await widget.controller.processDueRecurringRules();
              if (!context.mounted) return;
              final err = widget.controller.state.errorMessage;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    err ??
                        (count > 0
                            ? 'Processed $count recurring schedule(s).'
                            : 'No recurring schedules are currently due.'),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: SharedDesignTokens.spacingCompact),
        if (state.recurringRules.isEmpty)
          DaywellEmptyState(
            icon: Icons.repeat_outlined,
            message: 'No recurring schedules yet',
            subtitle:
                'Automate monthly salary, rent commitments, or recurring transfers.',
            actionLabel: 'Create Recurring Rule',
            onActionPressed: () => _openRecurringRuleSheet(context),
          )
        else
          for (final rule in state.recurringRules) ...[
            Builder(
              builder: (ctx) {
                final srcAcc =
                    rule.accountId != null ? accountById[rule.accountId] : null;
                final dstAcc = rule.destinationAccountId != null
                    ? accountById[rule.destinationAccountId]
                    : null;
                final linkedDebt = rule.linkedDebtId != null
                    ? debtById[rule.linkedDebtId]
                    : null;
                final bool ruleEligibleEtb;
                String? displayCurrency;
                bool isExcludedForeign = false;

                if (rule.linkedDebtId != null &&
                    rule.linkedDebtId!.isNotEmpty) {
                  ruleEligibleEtb =
                      linkedDebt != null && state.isDebtEligibleEtb(linkedDebt);
                  final dCls = linkedDebt != null
                      ? state.classifyDebt(linkedDebt)
                      : null;
                  if (ruleEligibleEtb) {
                    displayCurrency = 'ETB';
                  } else if (dCls != null && dCls.isExcludedNonEtb) {
                    displayCurrency = dCls.nativeCurrencyCode;
                    isExcludedForeign = true;
                  }
                } else if (rule.ruleType == RecurringRuleType.transfer) {
                  ruleEligibleEtb = srcAcc != null &&
                      dstAcc != null &&
                      DoubleEntryEngine.isActiveVerifiedEtbAccount(srcAcc) &&
                      DoubleEntryEngine.isActiveVerifiedEtbAccount(dstAcc) &&
                      srcAcc.id != dstAcc.id;
                  if (ruleEligibleEtb) {
                    displayCurrency = 'ETB';
                  } else if (srcAcc != null &&
                      dstAcc != null &&
                      DoubleEntryEngine.classifyCurrencyCode(
                              srcAcc.currencyCode) ==
                          CurrencyValidationTier.verifiedNonEtb &&
                      DoubleEntryEngine.normalizeCurrencyCode(
                              srcAcc.currencyCode) ==
                          DoubleEntryEngine.normalizeCurrencyCode(
                              dstAcc.currencyCode)) {
                    displayCurrency = DoubleEntryEngine.normalizeCurrencyCode(
                        srcAcc.currencyCode);
                    isExcludedForeign = true;
                  }
                } else {
                  ruleEligibleEtb = srcAcc != null &&
                      DoubleEntryEngine.isActiveVerifiedEtbAccount(srcAcc);
                  if (ruleEligibleEtb) {
                    displayCurrency = 'ETB';
                  } else if (srcAcc != null &&
                      DoubleEntryEngine.classifyCurrencyCode(
                              srcAcc.currencyCode) ==
                          CurrencyValidationTier.verifiedNonEtb) {
                    displayCurrency = DoubleEntryEngine.normalizeCurrencyCode(
                        srcAcc.currencyCode);
                    isExcludedForeign = true;
                  }
                }

                return DaywellCard(
                  padding:
                      const EdgeInsets.all(SharedDesignTokens.spacingCompact),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              rule.title,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            FinanceUiFormatters.formatCurrencyCents(
                              rule.amountCents,
                              currencyCode: displayCurrency,
                            ),
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: !ruleEligibleEtb && !isExcludedForeign
                                  ? semantic.warning
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingXs),
                      Wrap(
                        spacing: SharedDesignTokens.spacingSm,
                        runSpacing: SharedDesignTokens.spacingXs,
                        children: [
                          DaywellStatusBadge(
                            label:
                                '${rule.ruleType.name} · ${rule.frequency.name}',
                            tone: rule.isActive
                                ? DaywellStatusTone.info
                                : DaywellStatusTone.warning,
                            showIcon: false,
                          ),
                          DaywellStatusBadge(
                            label:
                                rule.autoPost ? 'Auto-Post' : 'Generates Bill',
                            tone: DaywellStatusTone.success,
                            showIcon: false,
                          ),
                          if (!ruleEligibleEtb)
                            DaywellStatusBadge(
                              label: isExcludedForeign
                                  ? 'Excluded ($displayCurrency)'
                                  : 'Currency Review',
                              tone: DaywellStatusTone.warning,
                              showIcon: !isExcludedForeign,
                            ),
                          Text(
                            'Next: ${rule.nextOccurrenceDate.toIsoString()}',
                            style: textTheme.bodySmall?.copyWith(
                              color: semantic.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingSm),
                      Wrap(
                        spacing: SharedDesignTokens.spacingSm,
                        children: [
                          DaywellButton(
                            label: rule.isActive ? 'Pause' : 'Resume',
                            variant: DaywellButtonVariant.outlined,
                            size: DaywellButtonSize.compact,
                            onPressed: (!rule.isActive && !ruleEligibleEtb)
                                ? null
                                : () async {
                                    await widget.controller.upsertRecurringRule(
                                      rule.copyWith(isActive: !rule.isActive),
                                    );
                                    final err =
                                        widget.controller.state.errorMessage;
                                    if (err != null && context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(content: Text(err)),
                                      );
                                    }
                                  },
                          ),
                          DaywellButton(
                            label: 'Edit',
                            variant: DaywellButtonVariant.text,
                            size: DaywellButtonSize.compact,
                            onPressed: () => _openRecurringRuleSheet(
                              context,
                              existing: rule,
                            ),
                          ),
                          DaywellButton(
                            label: 'Delete',
                            variant: DaywellButtonVariant.text,
                            size: DaywellButtonSize.compact,
                            onPressed: () async {
                              final ok = await DaywellConfirmationDialog.show(
                                context,
                                title: 'Delete Recurring Rule?',
                                message: 'Remove schedule "${rule.title}"?',
                                confirmLabel: 'Delete',
                                isDestructive: true,
                              );
                              if (ok) {
                                await widget.controller
                                    .deleteRecurringRule(rule.id);
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
          ],
      ],
    );
  }

  // ==================== 4. SAVINGS GOALS ====================

  Widget _buildSavingsSection(BuildContext context) {
    final state = widget.controller.state;
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final accountById = {for (final a in state.accounts) a.id: a};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DaywellSectionHeader(
          title: 'Savings Goals & Vaults',
          count: state.savingsGoals.length,
          actionLabel: '+ Add Goal',
          onActionPressed: () => _openSavingsGoalEditorSheet(context),
        ),
        const SizedBox(height: SharedDesignTokens.spacingCompact),
        if (state.savingsGoals.isEmpty)
          DaywellEmptyState(
            icon: Icons.savings_outlined,
            message: 'No savings goals yet',
            subtitle:
                'Link a goal to a Savings Vault account or reserve virtual cash from liquid accounts.',
            actionLabel: 'Create Savings Goal',
            onActionPressed: () => _openSavingsGoalEditorSheet(context),
          )
        else
          for (final goal in state.savingsGoals) ...[
            Builder(
              builder: (ctx) {
                final target = goal.targetCents <= 0 ? 1 : goal.targetCents;
                final linkedAcc = goal.linkedAccountId != null
                    ? accountById[goal.linkedAccountId]
                    : null;
                final isVaultGoal = goal.isVaultLinked;
                final isVaultEligibleEtb = !isVaultGoal ||
                    (linkedAcc != null &&
                        DoubleEntryEngine.isActiveVerifiedEtbAccount(
                            linkedAcc) &&
                        linkedAcc.subType.isSavingsVault);
                final vaultTier = linkedAcc != null
                    ? DoubleEntryEngine.classifyCurrencyCode(
                        linkedAcc.currencyCode,
                      )
                    : CurrencyValidationTier.unverified;
                final goalCurrency = !isVaultGoal
                    ? 'ETB'
                    : (isVaultEligibleEtb
                        ? 'ETB'
                        : (vaultTier == CurrencyValidationTier.verifiedNonEtb
                            ? DoubleEntryEngine.normalizeCurrencyCode(
                                linkedAcc!.currencyCode,
                              )
                            : null));
                final allocatedDisplay = linkedAcc != null
                    ? state.getAccountBalanceCents(linkedAcc)
                    : goal.currentAllocatedCents;
                final ratio = (allocatedDisplay / target).clamp(0.0, 1.0);

                return DaywellCard(
                  padding:
                      const EdgeInsets.all(SharedDesignTokens.spacingCompact),
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
                            goal.title,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          DaywellStatusBadge(
                            label: isVaultGoal
                                ? (linkedAcc != null
                                    ? 'Vault: ${linkedAcc.name}'
                                    : 'Missing Vault')
                                : 'Virtual Reserve',
                            tone: isVaultGoal
                                ? (isVaultEligibleEtb
                                    ? DaywellStatusTone.info
                                    : DaywellStatusTone.warning)
                                : DaywellStatusTone.success,
                            showIcon: false,
                          ),
                          if (isVaultGoal && !isVaultEligibleEtb)
                            DaywellStatusBadge(
                              label: vaultTier ==
                                      CurrencyValidationTier.verifiedNonEtb
                                  ? 'Excluded ($goalCurrency)'
                                  : 'Currency Review',
                              tone: DaywellStatusTone.warning,
                              showIcon: vaultTier !=
                                  CurrencyValidationTier.verifiedNonEtb,
                            ),
                        ],
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingSm),
                      DaywellProgressBar(
                        value: ratio,
                        label: '${(ratio * 100).round()}% saved',
                        valueText:
                            '${FinanceUiFormatters.formatCurrencyCents(allocatedDisplay, currencyCode: goalCurrency)} / ${FinanceUiFormatters.formatCurrencyCents(goal.targetCents, currencyCode: goalCurrency)}',
                      ),
                      if (goal.targetDate != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Target: ${SharedDateFormatter.formatDual(goal.targetDate!, useAmharic: false)}',
                            style: textTheme.labelSmall?.copyWith(
                              color: semantic.textSecondary,
                            ),
                          ),
                        ),
                      const SizedBox(height: SharedDesignTokens.spacingSm),
                      Wrap(
                        spacing: SharedDesignTokens.spacingSm,
                        children: [
                          DaywellButton(
                            label: 'Fund / Withdraw',
                            leadingIcon: Icons.swap_vert,
                            variant: DaywellButtonVariant.secondary,
                            size: DaywellButtonSize.compact,
                            onPressed: isVaultEligibleEtb
                                ? () => _openFundSavingsGoalSheet(context, goal)
                                : null,
                          ),
                          DaywellButton(
                            label: 'Edit',
                            variant: DaywellButtonVariant.outlined,
                            size: DaywellButtonSize.compact,
                            onPressed: () => _openSavingsGoalEditorSheet(
                              context,
                              existing: goal,
                            ),
                          ),
                          DaywellButton(
                            label: 'Delete',
                            variant: DaywellButtonVariant.text,
                            size: DaywellButtonSize.compact,
                            onPressed: () async {
                              final ok = await DaywellConfirmationDialog.show(
                                context,
                                title: 'Delete Savings Goal?',
                                message: 'Delete "${goal.title}"?',
                                confirmLabel: 'Delete',
                                isDestructive: true,
                              );
                              if (ok) {
                                await widget.controller
                                    .deleteSavingsGoal(goal.id);
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
          ],
      ],
    );
  }

  // ==================== 5. DEBTS & PARTIES ====================

  Widget _buildDebtsAndPartiesSection(BuildContext context) {
    final state = widget.controller.state;
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final partyById = {for (final p in state.parties) p.id: p};
    final visibleDebts = state.debts
        .where((d) => _showSettledDebts || d.status == DebtStatus.active)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DaywellSectionHeader(
          title: 'Debts, Loans & Parties',
          count: state.debts.where((d) => d.status == DebtStatus.active).length,
          actionLabel: '+ Add Party',
          onActionPressed: () => _openPartyEditorSheet(context),
        ),
        const SizedBox(height: SharedDesignTokens.spacingSm),
        Wrap(
          spacing: SharedDesignTokens.spacingSm,
          runSpacing: SharedDesignTokens.spacingSm,
          children: [
            DaywellButton(
              label: 'Lend Money',
              leadingIcon: Icons.call_made,
              variant: DaywellButtonVariant.primary,
              size: DaywellButtonSize.compact,
              onPressed: () => _openLendOrBorrowSheet(
                context,
                isReceivable: true,
              ),
            ),
            DaywellButton(
              label: 'Borrow Money',
              leadingIcon: Icons.call_received,
              variant: DaywellButtonVariant.secondary,
              size: DaywellButtonSize.compact,
              onPressed: () => _openLendOrBorrowSheet(
                context,
                isReceivable: false,
              ),
            ),
            FilterChip(
              label: const Text('Show Settled/Written-Off'),
              selected: _showSettledDebts,
              onSelected: (v) => setState(() => _showSettledDebts = v),
            ),
          ],
        ),
        const SizedBox(height: SharedDesignTokens.spacingCompact),
        if (visibleDebts.isEmpty)
          const DaywellEmptyState(
            icon: Icons.handshake_outlined,
            message: 'No active receivables or payables',
            subtitle: 'Use Lend Money or Borrow Money above to track IOUs.',
          )
        else
          for (final debt in visibleDebts) ...[
            Builder(
              builder: (ctx) {
                final partyName =
                    partyById[debt.partyId]?.name ?? 'Unknown Party';
                final isReceivable = debt.debtType == DebtType.receivable;
                final debtCls = state.classifyDebt(debt);
                final debtEligible = state.isDebtEligibleEtb(debt);
                final nativeCurrency = debtEligible
                    ? 'ETB'
                    : (debtCls != null && debtCls.isExcludedNonEtb
                        ? debtCls.nativeCurrencyCode
                        : null);
                return DaywellCard(
                  padding:
                      const EdgeInsets.all(SharedDesignTokens.spacingCompact),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              partyName,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            FinanceUiFormatters.formatCurrencyCents(
                              debt.outstandingCents,
                              currencyCode: nativeCurrency,
                            ),
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: !debtEligible
                                  ? semantic.warning
                                  : (isReceivable
                                      ? semantic.income
                                      : semantic.expense),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingXs),
                      Wrap(
                        spacing: SharedDesignTokens.spacingSm,
                        runSpacing: SharedDesignTokens.spacingXs,
                        children: [
                          DaywellStatusBadge(
                            label: isReceivable ? 'Owed to Me' : 'I Owe',
                            tone: isReceivable
                                ? DaywellStatusTone.info
                                : DaywellStatusTone.warning,
                            showIcon: false,
                          ),
                          DaywellStatusBadge(
                            label: debt.status.name.toUpperCase(),
                            tone: debt.status == DebtStatus.settled
                                ? DaywellStatusTone.success
                                : (debt.status == DebtStatus.writtenOff
                                    ? DaywellStatusTone.error
                                    : DaywellStatusTone.info),
                            showIcon: false,
                          ),
                          if (!debtEligible)
                            DaywellStatusBadge(
                              label: debtCls != null && debtCls.isExcludedNonEtb
                                  ? 'Excluded (${nativeCurrency ?? 'Foreign'})'
                                  : 'Currency Review',
                              tone: DaywellStatusTone.warning,
                              showIcon: !(debtCls?.isExcludedNonEtb ?? false),
                            ),
                          Text(
                            'Principal: ${FinanceUiFormatters.formatCurrencyCents(debt.principalCents, currencyCode: nativeCurrency)}',
                            style: textTheme.bodySmall?.copyWith(
                              color: semantic.textSecondary,
                            ),
                          ),
                          if (debt.dueDate != null)
                            Text(
                              'Due: ${debt.dueDate}',
                              style: textTheme.bodySmall?.copyWith(
                                color: semantic.textSecondary,
                              ),
                            ),
                        ],
                      ),
                      if (debt.status == DebtStatus.active && debtEligible) ...[
                        const SizedBox(height: SharedDesignTokens.spacingSm),
                        Wrap(
                          spacing: SharedDesignTokens.spacingSm,
                          children: [
                            DaywellButton(
                              label: 'Settle',
                              leadingIcon: Icons.payments_outlined,
                              variant: DaywellButtonVariant.secondary,
                              size: DaywellButtonSize.compact,
                              onPressed: () => _openSettleDebtSheet(
                                  context, debt, partyName),
                            ),
                            DaywellButton(
                              label: 'Write Off',
                              variant: DaywellButtonVariant.destructive,
                              size: DaywellButtonSize.compact,
                              onPressed: () =>
                                  _promptWriteOffDebt(context, debt, partyName),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
          ],
        const SizedBox(height: SharedDesignTokens.spacingSm),
        if (state.parties.isNotEmpty)
          DaywellCard(
            padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Parties Directory (${state.parties.length})',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: SharedDesignTokens.spacingXs),
                for (final party in state.parties)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      party.name,
                      style: textTheme.bodyMedium?.copyWith(
                        decoration: party.isArchived
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    subtitle: party.phone != null && party.phone!.isNotEmpty
                        ? Text(party.phone!)
                        : null,
                    trailing: Wrap(
                      children: [
                        DaywellIconButton(
                          icon: Icons.edit_outlined,
                          tooltip: 'Edit party',
                          iconSize: DaywellIconSize.sm,
                          onPressed: () => _openPartyEditorSheet(
                            context,
                            existing: party,
                          ),
                        ),
                        if (!party.isArchived)
                          DaywellIconButton(
                            icon: Icons.archive_outlined,
                            tooltip: 'Archive party',
                            iconSize: DaywellIconSize.sm,
                            onPressed: () =>
                                widget.controller.archiveParty(party.id),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // ==================== MODAL SHEETS ====================

  Future<void> _openBudgetEditorSheet(
    BuildContext context, {
    BudgetModel? existing,
  }) async {
    final state = widget.controller.state;
    final categoryItems = FinanceUiFormatters.buildCategoryDropdownItems(
      state.activeCategories,
      type: 'expense',
    );
    String? catId = existing?.categoryId ??
        (categoryItems.isNotEmpty ? categoryItems.first.value : null);
    final limitCtrl = TextEditingController(
      text: existing != null
          ? FinanceUiFormatters.formatCentsAsInput(existing.limitCents)
          : '',
    );
    var rollover = existing?.rolloverEnabled ?? false;
    String? error;

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
                  existing == null
                      ? 'Set Budget ($_budgetMonthIso)'
                      : 'Edit Budget (${existing.monthIso})',
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
                DaywellDropdownField<String>(
                  label: 'Expense Category',
                  value: categoryItems.any((i) => i.value == catId)
                      ? catId
                      : (categoryItems.isNotEmpty
                          ? categoryItems.first.value
                          : null),
                  items: categoryItems,
                  onChanged: (v) => setModalState(() => catId = v),
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellTextField(
                  controller: limitCtrl,
                  label: 'Monthly Limit (ETB)',
                  hintText: '5000.00',
                  isRequired: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                DaywellSwitchTile(
                  title: 'Enable Rollover',
                  subtitle: 'Carry unused budget guidance forward',
                  value: rollover,
                  onChanged: (v) => setModalState(() => rollover = v),
                ),
                const SizedBox(height: SharedDesignTokens.spacingMd),
                DaywellButton(
                  label: 'Save Budget',
                  fullWidth: true,
                  onPressed: () async {
                    if (catId == null) {
                      setModalState(
                          () => error = 'Select an expense category.');
                      return;
                    }
                    final cents = FinanceUiFormatters.parseEtbToCents(
                      limitCtrl.text,
                    );
                    if (cents == null || cents <= 0) {
                      setModalState(
                        () => error = 'Enter a valid limit greater than 0.',
                      );
                      return;
                    }
                    await widget.controller.upsertBudget(
                      BudgetModel(
                        id: existing?.id ?? 'budget-${_uuid.v4()}',
                        categoryId: catId!,
                        monthIso: existing?.monthIso ?? _budgetMonthIso,
                        limitCents: cents,
                        rolloverEnabled: rollover,
                      ),
                    );
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
    limitCtrl.dispose();
  }

  Future<void> _openCommitmentEditorSheet(
    BuildContext context, {
    CommitmentModel? existing,
  }) async {
    final state = widget.controller.state;
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final amountCtrl = TextEditingController(
      text: existing != null
          ? FinanceUiFormatters.formatCentsAsInput(existing.amountCents)
          : '',
    );
    var dueDate = existing?.dueDate ?? CalendarDate.today();
    final catItems = FinanceUiFormatters.buildCategoryDropdownItemsWithPreserved(
      state.categories,
      type: 'expense',
      preserveCategoryId: existing?.categoryId,
    );
    String? catId = FinanceUiFormatters.resolveCategorySelectionValue(
          existing?.categoryId,
          state.categories,
          type: 'expense',
          preserveUnmatchedHistorical: existing != null,
        ) ??
        (catItems.isNotEmpty ? catItems.first.value : null);
    String? linkedDebtId = existing?.linkedDebtId;
    final etbAccounts = state.activeEtbSpendableAccounts;
    String? linkedAccountId = existing?.linkedAccountId ??
        (linkedDebtId == null && etbAccounts.isNotEmpty
            ? etbAccounts.first.id
            : null);
    final activePayables = state.debts
        .where(
          (d) =>
              d.debtType == DebtType.payable &&
              d.status == DebtStatus.active &&
              state.isDebtEligibleEtb(d),
        )
        .toList();
    String? error;

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
                  existing == null
                      ? 'New Commitment / Bill'
                      : 'Edit Commitment',
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
                DaywellTextField(
                  controller: titleCtrl,
                  label: 'Title',
                  hintText: 'e.g. Apartment Rent',
                  isRequired: true,
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellTextField(
                  controller: amountCtrl,
                  label: 'Amount (ETB)',
                  isRequired: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellDropdownField<String>(
                  label: 'Category',
                  value: catItems.any((i) => i.value == catId)
                      ? catId
                      : (catItems.isNotEmpty ? catItems.first.value : null),
                  items: catItems,
                  onChanged: (v) => setModalState(() => catId = v),
                ),
                if (etbAccounts.isNotEmpty) ...[
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellDropdownField<String?>(
                    label: 'Linked ETB Account',
                    value: etbAccounts.any((a) => a.id == linkedAccountId)
                        ? linkedAccountId
                        : null,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None (Requires Debt or Account Link)'),
                      ),
                      for (final a in etbAccounts)
                        DropdownMenuItem<String?>(
                          value: a.id,
                          child: Text(a.name),
                        ),
                    ],
                    onChanged: (v) => setModalState(() => linkedAccountId = v),
                  ),
                ],
                if (activePayables.isNotEmpty) ...[
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellDropdownField<String?>(
                    label: 'Linked Payable Debt (Optional)',
                    value: activePayables.any((d) => d.id == linkedDebtId)
                        ? linkedDebtId
                        : null,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None (Standard Bill)'),
                      ),
                      for (final d in activePayables)
                        DropdownMenuItem<String?>(
                          value: d.id,
                          child: Text(
                            'Payable ${FinanceUiFormatters.formatEtbCents(d.outstandingCents)}',
                          ),
                        ),
                    ],
                    onChanged: (v) => setModalState(() => linkedDebtId = v),
                  ),
                ],
                const SizedBox(height: SharedDesignTokens.spacingSm),
                Wrap(
                  spacing: SharedDesignTokens.spacingSm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Due Date: ${SharedDateFormatter.formatDual(dueDate, useAmharic: false)}',
                    ),
                    DaywellButton(
                      label: 'Change',
                      variant: DaywellButtonVariant.text,
                      size: DaywellButtonSize.compact,
                      onPressed: () async {
                        final picked =
                            await FinanceUiFormatters.pickCalendarDate(
                          ctx,
                          initialDate: dueDate,
                        );
                        if (picked != null) {
                          setModalState(() => dueDate = picked);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: SharedDesignTokens.spacingMd),
                DaywellButton(
                  label: existing == null ? 'Add Commitment' : 'Save Changes',
                  fullWidth: true,
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    final cents = FinanceUiFormatters.parseEtbToCents(
                      amountCtrl.text,
                    );
                    if (title.isEmpty) {
                      setModalState(() => error = 'Enter a commitment title.');
                      return;
                    }
                    if (cents == null || cents <= 0) {
                      setModalState(() => error = 'Enter a valid amount > 0.');
                      return;
                    }
                    if (linkedAccountId == null && linkedDebtId == null) {
                      setModalState(
                        () => error =
                            'Link an active ETB account or ETB payable debt.',
                      );
                      return;
                    }
                    final model = CommitmentModel(
                      id: existing?.id ?? 'com-${_uuid.v4()}',
                      title: title,
                      amountCents: cents,
                      dueDate: dueDate,
                      isPaid: existing?.isPaid ?? false,
                      direction:
                          existing?.direction ?? CommitmentDirection.outflow,
                      verifiedSettledCents: existing?.verifiedSettledCents ?? 0,
                      legacyPaidUnverified:
                          existing?.legacyPaidUnverified ?? false,
                      categoryId: catId,
                      linkedAccountId: linkedAccountId,
                      linkedDebtId: linkedDebtId,
                      settlementEntryId: existing?.settlementEntryId,
                      recurringRuleId: existing?.recurringRuleId,
                    );
                    if (existing == null) {
                      await widget.controller.addCommitment(model);
                    } else {
                      await widget.controller.updateCommitment(model);
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
    titleCtrl.dispose();
    amountCtrl.dispose();
  }

  Future<void> _promptLinkCommitmentAccount(
    BuildContext context,
    CommitmentModel item,
    List<AccountModel> etbAccounts,
  ) async {
    String? selectedAccountId =
        etbAccounts.isNotEmpty ? etbAccounts.first.id : null;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Link ETB Account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Assign an active ETB account to "${item.title}" to clear Currency Review.',
              ),
              if (error != null) ...[
                const SizedBox(height: SharedDesignTokens.spacingSm),
                DaywellStatusBanner(
                  message: error!,
                  tone: DaywellStatusTone.error,
                ),
              ],
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              DaywellDropdownField<String>(
                label: 'ETB Account',
                value: selectedAccountId,
                items: [
                  for (final a in etbAccounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setDialogState(() => selectedAccountId = v),
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
              label: 'Link Account',
              size: DaywellButtonSize.compact,
              onPressed: () async {
                if (selectedAccountId == null) {
                  setDialogState(() => error = 'Select an active ETB account.');
                  return;
                }
                final ok = await widget.controller.linkCommitmentToAccount(
                  commitmentId: item.id,
                  accountId: selectedAccountId!,
                );
                if (!ok) {
                  setDialogState(
                    () => error = widget.controller.state.errorMessage ??
                        'Unable to link account.',
                  );
                  return;
                }
                if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMarkCommitmentPaidSheet(
    BuildContext context,
    CommitmentModel item,
  ) async {
    final state = widget.controller.state;
    final accounts = state.activeEtbSpendableAccounts;
    String? accountId = item.linkedAccountId != null &&
            accounts.any((a) => a.id == item.linkedAccountId)
        ? item.linkedAccountId
        : (accounts.isNotEmpty ? accounts.first.id : null);
    final catType =
        item.direction == CommitmentDirection.inflow ? 'income' : 'expense';
    final catItems =
        FinanceUiFormatters.buildCategoryDropdownItemsWithPreserved(
      state.categories,
      type: catType,
      preserveCategoryId: item.categoryId,
    );
    String? catId = FinanceUiFormatters.resolveCategorySelectionValue(
          item.categoryId,
          state.categories,
          type: catType,
          preserveUnmatchedHistorical: true,
        ) ??
        (catItems.isNotEmpty ? catItems.first.value : null);
    var paidDate = CalendarDate.today();
    final noteCtrl = TextEditingController();
    var isSaving = false;
    String? error;

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
                  'Pay "${item.title}"',
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
                const SizedBox(height: SharedDesignTokens.spacingXs),
                Text(
                  'Amount: ${FinanceUiFormatters.formatEtbCents(item.amountCents)}',
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                if (accounts.isEmpty)
                  const DaywellStatusBanner(
                    message:
                        'Add an active ETB account before paying a commitment.',
                    tone: DaywellStatusTone.warning,
                  )
                else ...[
                  DaywellDropdownField<String>(
                    label: item.direction == CommitmentDirection.inflow
                        ? 'Receive Into ETB Account'
                        : 'Pay From ETB Account',
                    value: accountId ?? accounts.first.id,
                    items: [
                      for (final a in accounts)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ],
                    onChanged: (v) => setModalState(() => accountId = v),
                  ),
                  if (item.linkedDebtId == null && catItems.isNotEmpty) ...[
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    DaywellDropdownField<String>(
                      label: item.direction == CommitmentDirection.inflow
                          ? 'Income Category'
                          : 'Expense Category',
                      value: catItems.any((i) => i.value == catId)
                          ? catId
                          : catItems.first.value,
                      items: catItems,
                      onChanged: (v) => setModalState(() => catId = v),
                    ),
                  ],
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellTextField(
                    controller: noteCtrl,
                    label: 'Payment Note (optional)',
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingSm),
                  Wrap(
                    spacing: SharedDesignTokens.spacingSm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Paid Date: ${paidDate.toIsoString()}'),
                      DaywellButton(
                        label: 'Pick Date',
                        variant: DaywellButtonVariant.text,
                        size: DaywellButtonSize.compact,
                        onPressed: () async {
                          final picked =
                              await FinanceUiFormatters.pickCalendarDate(
                            ctx,
                            initialDate: paidDate,
                          );
                          if (picked != null) {
                            setModalState(() => paidDate = picked);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingMd),
                  DaywellButton(
                    label: item.direction == CommitmentDirection.inflow
                        ? 'Record Receipt & Settle'
                        : 'Post Payment & Mark Paid',
                    fullWidth: true,
                    isLoading: isSaving,
                    onPressed: isSaving
                        ? null
                        : () async {
                            setModalState(() {
                              isSaving = true;
                              error = null;
                            });
                            final settled = await widget.controller
                                .recordCommitmentSettlement(
                              commitmentId: item.id,
                              accountId: accountId ?? accounts.first.id,
                              amountCents: item.remainingCents > 0
                                  ? item.remainingCents
                                  : item.amountCents,
                              categoryId: catId,
                              settledDate: paidDate,
                              note: noteCtrl.text.trim().isEmpty
                                  ? null
                                  : noteCtrl.text.trim(),
                            );
                            final err = widget.controller.state.errorMessage;
                            if (settled == null || err != null) {
                              if (ctx.mounted) {
                                setModalState(() {
                                  isSaving = false;
                                  error = err ?? 'Unable to record settlement.';
                                });
                              }
                              return;
                            }
                            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                          },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    noteCtrl.dispose();
  }

  Future<void> _openRecurringRuleSheet(
    BuildContext context, {
    RecurringRuleModel? existing,
  }) async {
    final state = widget.controller.state;
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final amountCtrl = TextEditingController(
      text: existing != null
          ? FinanceUiFormatters.formatCentsAsInput(existing.amountCents)
          : '',
    );
    final intervalCtrl = TextEditingController(
      text: (existing?.interval ?? 1).toString(),
    );
    var ruleType = existing?.ruleType ?? RecurringRuleType.expense;
    var frequency = existing?.frequency ?? RecurrenceFrequency.monthly;
    var startDate = existing?.startDate ?? CalendarDate.today();
    var autoPost = existing?.autoPost ?? false;

    List<AccountModel> eligibleFor(RecurringRuleType type) =>
        type == RecurringRuleType.transfer
            ? [
                ...state.activeEtbSpendableAccounts,
                ...state.activeEtbVaultAccounts,
              ]
            : state.activeEtbSpendableAccounts;

    final initialAccounts = eligibleFor(ruleType);
    String? accountId = existing?.accountId != null &&
            initialAccounts.any((a) => a.id == existing!.accountId)
        ? existing!.accountId
        : (initialAccounts.isNotEmpty ? initialAccounts.first.id : null);
    String? destAccountId = existing?.destinationAccountId != null &&
            initialAccounts.any((a) => a.id == existing!.destinationAccountId)
        ? existing!.destinationAccountId
        : (initialAccounts.length > 1 ? initialAccounts[1].id : null);
    String? categoryId = existing?.categoryId;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final accounts = eligibleFor(ruleType);
          if (accountId == null || !accounts.any((a) => a.id == accountId)) {
            accountId = accounts.isNotEmpty ? accounts.first.id : null;
          }
          if (ruleType == RecurringRuleType.transfer &&
              (destAccountId == null ||
                  destAccountId == accountId ||
                  !accounts.any((a) => a.id == destAccountId))) {
            destAccountId = accounts.length > 1
                ? accounts
                    .firstWhere(
                      (a) => a.id != accountId,
                      orElse: () => accounts.first,
                    )
                    .id
                : null;
          }
          final catType =
              ruleType == RecurringRuleType.income ? 'income' : 'expense';
          final catItems =
              FinanceUiFormatters.buildCategoryDropdownItemsWithPreserved(
            state.categories,
            type: catType,
            preserveCategoryId: existing?.categoryId,
          );
          categoryId = FinanceUiFormatters.resolveCategorySelectionValue(
                categoryId,
                state.categories,
                type: catType,
                preserveUnmatchedHistorical: existing != null,
              ) ??
              (catItems.isNotEmpty ? catItems.first.value : null);

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
                    existing == null ? 'New Recurring Rule' : 'Edit Rule',
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
                  DaywellTextField(
                    controller: titleCtrl,
                    label: 'Rule Title',
                    hintText: 'e.g. Monthly Rent or Salary',
                    isRequired: true,
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellDropdownField<RecurringRuleType>(
                    label: 'Rule Type',
                    value: ruleType,
                    items: const [
                      DropdownMenuItem(
                        value: RecurringRuleType.expense,
                        child: Text('Expense'),
                      ),
                      DropdownMenuItem(
                        value: RecurringRuleType.income,
                        child: Text('Income'),
                      ),
                      DropdownMenuItem(
                        value: RecurringRuleType.transfer,
                        child: Text('Transfer'),
                      ),
                      DropdownMenuItem(
                        value: RecurringRuleType.commitment,
                        child: Text('Upcoming Bill / Commitment'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setModalState(() => ruleType = v);
                    },
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellTextField(
                    controller: amountCtrl,
                    label: 'Amount (ETB)',
                    isRequired: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellDropdownField<RecurrenceFrequency>(
                    label: 'Frequency',
                    value: frequency,
                    items: const [
                      DropdownMenuItem(
                        value: RecurrenceFrequency.weekly,
                        child: Text('Weekly'),
                      ),
                      DropdownMenuItem(
                        value: RecurrenceFrequency.biweekly,
                        child: Text('Every 2 Weeks'),
                      ),
                      DropdownMenuItem(
                        value: RecurrenceFrequency.monthly,
                        child: Text('Monthly'),
                      ),
                      DropdownMenuItem(
                        value: RecurrenceFrequency.quarterly,
                        child: Text('Quarterly'),
                      ),
                      DropdownMenuItem(
                        value: RecurrenceFrequency.yearly,
                        child: Text('Yearly'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setModalState(() => frequency = v);
                    },
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellTextField(
                    controller: intervalCtrl,
                    label: 'Repeat Every N Cycles',
                    keyboardType: TextInputType.number,
                  ),
                  if (accounts.isNotEmpty) ...[
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    DaywellDropdownField<String>(
                      label: ruleType == RecurringRuleType.income
                          ? 'Deposit Account'
                          : 'Account',
                      value: accounts.any((a) => a.id == accountId)
                          ? accountId
                          : accounts.first.id,
                      items: [
                        for (final a in accounts)
                          DropdownMenuItem(value: a.id, child: Text(a.name)),
                      ],
                      onChanged: (v) => setModalState(() => accountId = v),
                    ),
                  ],
                  if (ruleType == RecurringRuleType.transfer &&
                      accounts.length > 1) ...[
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    DaywellDropdownField<String>(
                      label: 'Destination Account',
                      value: accounts.any((a) => a.id == destAccountId)
                          ? destAccountId
                          : accounts.last.id,
                      items: [
                        for (final a in accounts)
                          DropdownMenuItem(value: a.id, child: Text(a.name)),
                      ],
                      onChanged: (v) => setModalState(() => destAccountId = v),
                    ),
                  ],
                  if (ruleType != RecurringRuleType.transfer &&
                      catItems.isNotEmpty) ...[
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    DaywellDropdownField<String>(
                      label: 'Category',
                      value: categoryId,
                      items: catItems,
                      onChanged: (v) => setModalState(() => categoryId = v),
                    ),
                  ],
                  DaywellSwitchTile(
                    title: 'Auto-Post Directly to Ledger',
                    subtitle:
                        'When off, generates an unpaid Commitment bill instead',
                    value: autoPost,
                    onChanged: (v) => setModalState(() => autoPost = v),
                  ),
                  Wrap(
                    spacing: SharedDesignTokens.spacingSm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Start Date: ${startDate.toIsoString()}'),
                      DaywellButton(
                        label: 'Change',
                        variant: DaywellButtonVariant.text,
                        size: DaywellButtonSize.compact,
                        onPressed: () async {
                          final picked =
                              await FinanceUiFormatters.pickCalendarDate(
                            ctx,
                            initialDate: startDate,
                          );
                          if (picked != null) {
                            setModalState(() => startDate = picked);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingMd),
                  DaywellButton(
                    label: 'Save Recurring Rule',
                    fullWidth: true,
                    onPressed: () async {
                      final title = titleCtrl.text.trim();
                      final cents = FinanceUiFormatters.parseEtbToCents(
                        amountCtrl.text,
                      );
                      final interval =
                          int.tryParse(intervalCtrl.text.trim()) ?? 1;
                      if (title.isEmpty) {
                        setModalState(() => error = 'Enter a title.');
                        return;
                      }
                      if (cents == null || cents <= 0) {
                        setModalState(() => error = 'Enter amount > 0.');
                        return;
                      }
                      if (accountId == null) {
                        setModalState(
                          () => error = 'Select an active ETB account.',
                        );
                        return;
                      }
                      if (ruleType == RecurringRuleType.transfer &&
                          (destAccountId == null ||
                              destAccountId == accountId)) {
                        setModalState(
                          () => error =
                              'Select two distinct active ETB accounts for transfer.',
                        );
                        return;
                      }
                      await widget.controller.upsertRecurringRule(
                        RecurringRuleModel(
                          id: existing?.id ?? 'rec-${_uuid.v4()}',
                          title: title,
                          ruleType: ruleType,
                          amountCents: cents,
                          frequency: frequency,
                          interval: interval < 1 ? 1 : interval,
                          startDate: startDate,
                          nextOccurrenceDate:
                              existing?.nextOccurrenceDate ?? startDate,
                          accountId: accountId,
                          destinationAccountId:
                              ruleType == RecurringRuleType.transfer
                                  ? destAccountId
                                  : null,
                          categoryId: categoryId,
                          isActive: existing?.isActive ?? true,
                          autoPost: ruleType == RecurringRuleType.commitment
                              ? false
                              : autoPost,
                        ),
                      );
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
    titleCtrl.dispose();
    amountCtrl.dispose();
    intervalCtrl.dispose();
  }

  Future<void> _openSavingsGoalEditorSheet(
    BuildContext context, {
    SavingsGoalModel? existing,
  }) async {
    final state = widget.controller.state;
    final vaults = state.vaultAssetAccounts;
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final targetCtrl = TextEditingController(
      text: existing != null
          ? FinanceUiFormatters.formatCentsAsInput(existing.targetCents)
          : '',
    );
    String? linkedAccountId = existing?.linkedAccountId;
    var targetDate = existing?.targetDate;
    String? error;

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
                  existing == null ? 'New Savings Goal' : 'Edit Savings Goal',
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
                DaywellTextField(
                  controller: titleCtrl,
                  label: 'Goal Name',
                  hintText: 'e.g. Emergency Fund',
                  isRequired: true,
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellTextField(
                  controller: targetCtrl,
                  label: 'Target Amount (ETB)',
                  isRequired: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellDropdownField<String?>(
                  label: 'Backing Mode',
                  value: vaults.any((v) => v.id == linkedAccountId)
                      ? linkedAccountId
                      : null,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child:
                          Text('Virtual Reserve (Earmarked from Liquid Cash)'),
                    ),
                    for (final v in vaults)
                      DropdownMenuItem<String?>(
                        value: v.id,
                        child: Text('Vault Account: ${v.name}'),
                      ),
                  ],
                  onChanged: (v) => setModalState(() => linkedAccountId = v),
                ),
                const SizedBox(height: SharedDesignTokens.spacingSm),
                Wrap(
                  spacing: SharedDesignTokens.spacingSm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      targetDate == null
                          ? 'Target Date: Optional'
                          : 'Target: ${targetDate!.toIsoString()}',
                    ),
                    DaywellButton(
                      label: targetDate == null ? 'Set Date' : 'Change',
                      variant: DaywellButtonVariant.text,
                      size: DaywellButtonSize.compact,
                      onPressed: () async {
                        final picked =
                            await FinanceUiFormatters.pickCalendarDate(
                          ctx,
                          initialDate:
                              targetDate ?? CalendarDate.today().addDays(90),
                        );
                        if (picked != null) {
                          setModalState(() => targetDate = picked);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: SharedDesignTokens.spacingMd),
                DaywellButton(
                  label: 'Save Goal',
                  fullWidth: true,
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    final target = FinanceUiFormatters.parseEtbToCents(
                      targetCtrl.text,
                    );
                    if (title.isEmpty) {
                      setModalState(() => error = 'Enter a goal title.');
                      return;
                    }
                    if (target == null || target <= 0) {
                      setModalState(() => error = 'Enter target > 0.');
                      return;
                    }
                    final model = SavingsGoalModel(
                      id: existing?.id ?? 'sav-${_uuid.v4()}',
                      title: title,
                      targetCents: target,
                      currentAllocatedCents:
                          existing?.currentAllocatedCents ?? 0,
                      targetDate: targetDate,
                      linkedAccountId: linkedAccountId,
                    );
                    if (existing == null) {
                      await widget.controller.addSavingsGoal(model);
                    } else {
                      await widget.controller.updateSavingsGoal(model);
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
    titleCtrl.dispose();
    targetCtrl.dispose();
  }

  Future<void> _openFundSavingsGoalSheet(
    BuildContext context,
    SavingsGoalModel goal,
  ) async {
    final state = widget.controller.state;
    final liquid = state.liquidAssetAccounts;
    final amountCtrl = TextEditingController();
    var isWithdraw = false;
    String? sourceAccountId = liquid.isNotEmpty ? liquid.first.id : null;
    String? error;

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
                  '${goal.isVaultLinked ? 'Transfer Vault' : 'Adjust Reserve'}: ${goal.title}',
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
                Wrap(
                  spacing: SharedDesignTokens.spacingSm,
                  children: [
                    ChoiceChip(
                      label: const Text('Fund / Deposit'),
                      selected: !isWithdraw,
                      onSelected: (_) =>
                          setModalState(() => isWithdraw = false),
                    ),
                    ChoiceChip(
                      label: const Text('Withdraw / Release'),
                      selected: isWithdraw,
                      onSelected: (_) => setModalState(() => isWithdraw = true),
                    ),
                  ],
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                if (goal.isVaultLinked) ...[
                  if (liquid.isEmpty)
                    const DaywellStatusBanner(
                      message:
                          'No liquid account available for vault transfer.',
                      tone: DaywellStatusTone.warning,
                    )
                  else
                    DaywellDropdownField<String>(
                      label: isWithdraw
                          ? 'Destination Liquid Account'
                          : 'Source Liquid Account',
                      value: sourceAccountId ?? liquid.first.id,
                      items: [
                        for (final a in liquid)
                          DropdownMenuItem(value: a.id, child: Text(a.name)),
                      ],
                      onChanged: (v) =>
                          setModalState(() => sourceAccountId = v),
                    ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                ],
                DaywellTextField(
                  controller: amountCtrl,
                  label: 'Amount (ETB)',
                  isRequired: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: SharedDesignTokens.spacingMd),
                DaywellButton(
                  label: isWithdraw ? 'Withdraw' : 'Fund Goal',
                  fullWidth: true,
                  onPressed: () async {
                    final cents = FinanceUiFormatters.parseEtbToCents(
                      amountCtrl.text,
                    );
                    if (cents == null || cents <= 0) {
                      setModalState(() => error = 'Enter amount > 0.');
                      return;
                    }
                    if (goal.isVaultLinked && sourceAccountId == null) {
                      setModalState(() => error = 'Select a liquid account.');
                      return;
                    }
                    await widget.controller.fundSavingsGoal(
                      goalId: goal.id,
                      deltaCents: isWithdraw ? -cents : cents,
                      sourceAccountId: sourceAccountId,
                    );
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
    amountCtrl.dispose();
  }

  Future<void> _openPartyEditorSheet(
    BuildContext context, {
    PartyModel? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    String? error;

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
                  existing == null ? 'Add Party / Person' : 'Edit Party',
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
                DaywellTextField(
                  controller: nameCtrl,
                  label: 'Name',
                  isRequired: true,
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellTextField(
                  controller: phoneCtrl,
                  label: 'Phone (optional)',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellTextField(
                  controller: notesCtrl,
                  label: 'Notes (optional)',
                  maxLines: 2,
                ),
                const SizedBox(height: SharedDesignTokens.spacingMd),
                DaywellButton(
                  label: 'Save Party',
                  fullWidth: true,
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      setModalState(() => error = 'Enter a party name.');
                      return;
                    }
                    if (existing == null) {
                      await widget.controller.createParty(
                        name: name,
                        phone: phoneCtrl.text.trim().isEmpty
                            ? null
                            : phoneCtrl.text.trim(),
                        notes: notesCtrl.text.trim().isEmpty
                            ? null
                            : notesCtrl.text.trim(),
                      );
                    } else {
                      await widget.controller.updateParty(
                        existing.copyWith(
                          name: name,
                          phone: phoneCtrl.text.trim().isEmpty
                              ? null
                              : phoneCtrl.text.trim(),
                          notes: notesCtrl.text.trim().isEmpty
                              ? null
                              : notesCtrl.text.trim(),
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
    phoneCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _openLendOrBorrowSheet(
    BuildContext context, {
    required bool isReceivable,
  }) async {
    final state = widget.controller.state;
    final accounts = state.activeEtbSpendableAccounts;
    final activeParties = state.parties.where((p) => !p.isArchived).toList();
    String? accountId = accounts.isNotEmpty ? accounts.first.id : null;
    String? partyId = activeParties.isNotEmpty ? activeParties.first.id : null;
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final newPartyCtrl = TextEditingController();
    var showNewParty = activeParties.isEmpty;
    var date = CalendarDate.today();
    CalendarDate? dueDate;
    var isSaving = false;
    String? error;

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
                  isReceivable
                      ? 'Lend Money (Receivable)'
                      : 'Borrow Money (Payable)',
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
                if (accounts.isEmpty)
                  const DaywellStatusBanner(
                    message: 'Add an active spendable ETB account first.',
                    tone: DaywellStatusTone.warning,
                  )
                else ...[
                  DaywellDropdownField<String>(
                    label:
                        isReceivable ? 'Source Account' : 'Destination Account',
                    value: accountId ?? accounts.first.id,
                    items: [
                      for (final a in accounts)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ],
                    onChanged: (v) => setModalState(() => accountId = v),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  if (!showNewParty && activeParties.isNotEmpty) ...[
                    DaywellDropdownField<String>(
                      label: 'Person / Party',
                      value: partyId ?? activeParties.first.id,
                      items: [
                        for (final p in activeParties)
                          DropdownMenuItem(value: p.id, child: Text(p.name)),
                      ],
                      onChanged: (v) => setModalState(() => partyId = v),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: DaywellButton(
                        label: '+ New Person',
                        variant: DaywellButtonVariant.text,
                        size: DaywellButtonSize.compact,
                        onPressed: () =>
                            setModalState(() => showNewParty = true),
                      ),
                    ),
                  ] else ...[
                    DaywellTextField(
                      controller: newPartyCtrl,
                      label: 'New Party Name',
                      isRequired: true,
                    ),
                    if (activeParties.isNotEmpty)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: DaywellButton(
                          label: 'Choose Existing Party',
                          variant: DaywellButtonVariant.text,
                          size: DaywellButtonSize.compact,
                          onPressed: () =>
                              setModalState(() => showNewParty = false),
                        ),
                      ),
                  ],
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellTextField(
                    controller: amountCtrl,
                    label: 'Amount (ETB)',
                    isRequired: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellTextField(
                    controller: descCtrl,
                    label: 'Description',
                    hintText:
                        isReceivable ? 'Loan to friend' : 'Short-term loan',
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingSm),
                  Wrap(
                    spacing: SharedDesignTokens.spacingSm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Date: ${date.toIsoString()}'),
                      DaywellButton(
                        label: 'Change',
                        variant: DaywellButtonVariant.text,
                        size: DaywellButtonSize.compact,
                        onPressed: () async {
                          final picked =
                              await FinanceUiFormatters.pickCalendarDate(
                            ctx,
                            initialDate: date,
                          );
                          if (picked != null) {
                            setModalState(() => date = picked);
                          }
                        },
                      ),
                      Text(
                        dueDate == null
                            ? 'Due: Optional'
                            : 'Due: ${dueDate!.toIsoString()}',
                      ),
                      DaywellButton(
                        label: dueDate == null ? 'Set Due' : 'Edit Due',
                        variant: DaywellButtonVariant.text,
                        size: DaywellButtonSize.compact,
                        onPressed: () async {
                          final picked =
                              await FinanceUiFormatters.pickCalendarDate(
                            ctx,
                            initialDate: dueDate ?? date.addDays(14),
                          );
                          if (picked != null) {
                            setModalState(() => dueDate = picked);
                          }
                        },
                      ),
                      if (dueDate != null)
                        DaywellButton(
                          label: 'Clear',
                          variant: DaywellButtonVariant.text,
                          size: DaywellButtonSize.compact,
                          onPressed: () => setModalState(() => dueDate = null),
                        ),
                    ],
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingMd),
                  DaywellButton(
                    label: isReceivable ? 'Post Loan Out' : 'Post Loan In',
                    fullWidth: true,
                    isLoading: isSaving,
                    onPressed: isSaving
                        ? null
                        : () async {
                            final cents = FinanceUiFormatters.parseEtbToCents(
                              amountCtrl.text,
                            );
                            if (cents == null || cents <= 0) {
                              setModalState(() => error = 'Enter amount > 0.');
                              return;
                            }
                            String? resolvedPartyId = partyId;
                            if (showNewParty || resolvedPartyId == null) {
                              final pName = newPartyCtrl.text.trim();
                              if (pName.isEmpty) {
                                setModalState(
                                    () => error = 'Enter party name.');
                                return;
                              }
                              resolvedPartyId =
                                  await widget.controller.ensurePartyId(pName);
                            }
                            setModalState(() {
                              isSaving = true;
                              error = null;
                            });
                            final desc = descCtrl.text.trim().isEmpty
                                ? (isReceivable
                                    ? 'Money Lent'
                                    : 'Money Borrowed')
                                : descCtrl.text.trim();
                            final DebtModel? saved;
                            if (isReceivable) {
                              saved = await widget.controller.lendMoney(
                                partyId: resolvedPartyId,
                                sourceAccountId: accountId!,
                                amountCents: cents,
                                date: date,
                                dueDate: dueDate,
                                description: desc,
                              );
                            } else {
                              saved = await widget.controller.borrowMoney(
                                partyId: resolvedPartyId,
                                destinationAccountId: accountId!,
                                amountCents: cents,
                                date: date,
                                dueDate: dueDate,
                                description: desc,
                              );
                            }
                            final err = widget.controller.state.errorMessage;
                            if (saved == null || err != null) {
                              if (ctx.mounted) {
                                setModalState(() {
                                  isSaving = false;
                                  error = err ?? 'Unable to record debt entry.';
                                });
                              }
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
      ),
    );
    amountCtrl.dispose();
    descCtrl.dispose();
    newPartyCtrl.dispose();
  }

  Future<void> _openSettleDebtSheet(
    BuildContext context,
    DebtModel debt,
    String partyName,
  ) async {
    final accounts = widget.controller.state.activeEtbSpendableAccounts;
    String? accountId = accounts.isNotEmpty ? accounts.first.id : null;
    final principalCtrl = TextEditingController(
      text: FinanceUiFormatters.formatCentsAsInput(debt.outstandingCents),
    );
    final interestCtrl = TextEditingController();
    var date = CalendarDate.today();
    var isSaving = false;
    String? error;

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
                  'Settle Debt: $partyName',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  'Outstanding: ${FinanceUiFormatters.formatEtbCents(debt.outstandingCents)}',
                ),
                if (error != null) ...[
                  const SizedBox(height: SharedDesignTokens.spacingSm),
                  DaywellStatusBanner(
                    message: error!,
                    tone: DaywellStatusTone.error,
                  ),
                ],
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                if (accounts.isEmpty)
                  const DaywellStatusBanner(
                    message: 'Add an active spendable ETB account to settle debt.',
                    tone: DaywellStatusTone.warning,
                  )
                else ...[
                  DaywellDropdownField<String>(
                    label: debt.debtType == DebtType.payable
                        ? 'Pay From Account'
                        : 'Receive Into Account',
                    value: accountId ?? accounts.first.id,
                    items: [
                      for (final a in accounts)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ],
                    onChanged: (v) => setModalState(() => accountId = v),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellTextField(
                    controller: principalCtrl,
                    label: 'Principal Payment (ETB)',
                    isRequired: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellTextField(
                    controller: interestCtrl,
                    label: 'Optional Interest (ETB)',
                    hintText: '0.00',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingSm),
                  Wrap(
                    spacing: SharedDesignTokens.spacingSm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Settlement Date: ${date.toIsoString()}'),
                      DaywellButton(
                        label: 'Pick Date',
                        variant: DaywellButtonVariant.text,
                        size: DaywellButtonSize.compact,
                        onPressed: () async {
                          final picked =
                              await FinanceUiFormatters.pickCalendarDate(
                            ctx,
                            initialDate: date,
                          );
                          if (picked != null) {
                            setModalState(() => date = picked);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingMd),
                  DaywellButton(
                    label: 'Post Settlement',
                    fullWidth: true,
                    isLoading: isSaving,
                    onPressed: isSaving
                        ? null
                        : () async {
                            final principal =
                                FinanceUiFormatters.parseEtbToCents(
                              principalCtrl.text,
                            );
                            final interestRaw = interestCtrl.text.trim();
                            final interest = interestRaw.isEmpty
                                ? 0
                                : FinanceUiFormatters.parseEtbToCents(
                                    interestRaw,
                                  );
                            if (principal == null ||
                                principal <= 0 ||
                                principal > debt.outstandingCents) {
                              setModalState(
                                () => error =
                                    'Enter principal between 0.01 and outstanding balance.',
                              );
                              return;
                            }
                            if (interest == null || interest < 0) {
                              setModalState(
                                () => error =
                                    'Enter valid non-negative interest.',
                              );
                              return;
                            }
                            setModalState(() {
                              isSaving = true;
                              error = null;
                            });
                            await widget.controller.recordDoubleEntrySettlement(
                              debt: debt,
                              settlementAssetAccountId: accountId!,
                              allocatedCents: principal,
                              interestCents: interest,
                              settlementDate: date.toIsoString(),
                              description: 'Settlement: $partyName',
                            );
                            final err = widget.controller.state.errorMessage;
                            if (err != null) {
                              if (ctx.mounted) {
                                setModalState(() {
                                  isSaving = false;
                                  error = err;
                                });
                              }
                              return;
                            }
                            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                          },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    principalCtrl.dispose();
    interestCtrl.dispose();
  }

  Future<void> _promptWriteOffDebt(
    BuildContext context,
    DebtModel debt,
    String partyName,
  ) async {
    final reasonCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Write Off Debt ($partyName)?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Remaining ${FinanceUiFormatters.formatEtbCents(debt.outstandingCents)} will be written off cleanly via balanced ledger entry.',
            ),
            const SizedBox(height: SharedDesignTokens.spacingCompact),
            DaywellTextField(
              controller: reasonCtrl,
              label: 'Write-Off Reason',
              hintText: 'e.g. Forgiven or uncollectible',
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
            label: 'Write Off',
            variant: DaywellButtonVariant.destructive,
            size: DaywellButtonSize.compact,
            onPressed: () async {
              final reason = reasonCtrl.text.trim().isEmpty
                  ? 'Written off'
                  : reasonCtrl.text.trim();
              Navigator.of(dialogCtx).pop();
              await widget.controller.writeOffDebt(
                debtId: debt.id,
                reason: reason,
              );
            },
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
  }
}
