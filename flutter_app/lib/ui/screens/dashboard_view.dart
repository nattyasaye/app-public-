import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/finance/finance_state.dart';
import '../../core/date/shared_date.dart';
import '../../core/shared_foundation.dart';
import '../../core/theme/daywell_theme.dart';
import '../../domain/calendar/calendar_models.dart';
import '../../domain/finance/double_entry_engine.dart';
import '../../domain/finance/financial_engine.dart';
import '../../domain/inbox/inbox_models.dart';
import '../../domain/notes/note_models.dart';
import '../../domain/tasks/task_models.dart';
import '../../domain/tasks/task_recurrence_engine.dart';
import '../app_state.dart';
import '../shell/daywell_shell_routes.dart';
import '../widgets/shared_ui_widgets.dart';
import 'finance/finance_formatters.dart';

/// Primary Dashboard / Today screen coordinating per-module controller
/// subscriptions, deduplicated pull-to-refresh, and adaptive responsive layout.
class DashboardView extends StatefulWidget {
  final AppStateManager state;
  final VoidCallback onOpenQuickCapture;
  final void Function(int)? onNavigateTab;
  final void Function(DaywellTabId tab)? onSelectTab;
  final VoidCallback? onOpenBackup;

  const DashboardView({
    super.key,
    required this.state,
    required this.onOpenQuickCapture,
    this.onNavigateTab,
    this.onSelectTab,
    this.onOpenBackup,
  });

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  Future<void>? _activeRefreshFuture;

  void _goToTab(DaywellTabId tab) {
    if (widget.onSelectTab != null) {
      widget.onSelectTab!(tab);
      return;
    }
    final fallbackIndex = kDaywellPrimaryDestinations.indexWhere(
      (DaywellDestinationSpec d) => d.id == tab,
    );
    if (fallbackIndex >= 0) {
      widget.onNavigateTab?.call(fallbackIndex);
    }
  }

  void _goToBackup() {
    widget.onOpenBackup?.call();
  }

  Future<void> _handleRefresh() {
    final existing = _activeRefreshFuture;
    if (existing != null) return existing;

    final future = _runRefresh();
    _activeRefreshFuture = future;
    return future;
  }

  Future<void> _runRefresh() async {
    try {
      await Future.wait<void>(<Future<void>>[
        widget.state.financeController.loadAll(),
        widget.state.tasksController.loadAll(),
        widget.state.calendarController.loadAll(),
        widget.state.notesController.loadNotes(),
        widget.state.inboxController.loadItems(includeProcessed: true),
      ]);
    } finally {
      _activeRefreshFuture = null;
    }
  }

  DaywellDestinationSpec _destinationFor(DaywellTabId tab) {
    return kDaywellPrimaryDestinations.firstWhere(
      (DaywellDestinationSpec d) => d.id == tab,
      orElse: () => kDaywellPrimaryDestinations.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final dualDate = SharedDateFormatter.formatDual(
      CalendarDate.today(),
      useAmharic: false,
    );
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final double? adaptiveToolbarHeight = textScale > 1.3
        ? (kToolbarHeight * textScale.clamp(1.0, 2.1)).ceilToDouble()
        : null;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: adaptiveToolbarHeight,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dashboard',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              dualDate,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          DaywellIconButton(
            icon: Icons.flash_on_rounded,
            tooltip: '1-Tap Quick Capture',
            semanticLabel: 'Open 1-Tap Quick Capture',
            foregroundColor: colorScheme.primary,
            onPressed: widget.onOpenQuickCapture,
          ),
          DaywellIconButton(
            icon: Icons.shield_outlined,
            tooltip: 'Encrypted Backup',
            semanticLabel: 'Open Encrypted Backup',
            onPressed: widget.onOpenBackup != null ? _goToBackup : null,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool isWide = constraints.maxWidth >=
                SharedDesignTokens.breakpointMaxContentWidth;

            return ListView(
              key: const PageStorageKey<String>('daywell_dashboard_scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
              children: [
                _DashboardMetricsGrid(
                  state: widget.state,
                  onSelectTab: _goToTab,
                ),
                const SizedBox(height: SharedDesignTokens.spacingMd),
                _DashboardQuickNavigationStrip(
                  tasksSpec: _destinationFor(DaywellTabId.tasks),
                  calendarSpec: _destinationFor(DaywellTabId.calendar),
                  notesSpec: _destinationFor(DaywellTabId.notes),
                  financeSpec: _destinationFor(DaywellTabId.finance),
                  onSelectTab: _goToTab,
                  onOpenQuickCapture: widget.onOpenQuickCapture,
                ),
                const SizedBox(height: SharedDesignTokens.spacingLg),
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DashboardFinanceSection(
                              state: widget.state,
                              onOpenFinance: () =>
                                  _goToTab(DaywellTabId.finance),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: SharedDesignTokens.spacingMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DashboardTasksSection(
                              state: widget.state,
                              onOpenTasks: () => _goToTab(DaywellTabId.tasks),
                            ),
                            const SizedBox(
                                height: SharedDesignTokens.spacingLg),
                            DashboardCalendarSection(
                              state: widget.state,
                              onOpenCalendar: () =>
                                  _goToTab(DaywellTabId.calendar),
                            ),
                            const SizedBox(
                                height: SharedDesignTokens.spacingLg),
                            DashboardNotesSection(
                              state: widget.state,
                              onOpenNotes: () => _goToTab(DaywellTabId.notes),
                            ),
                            const SizedBox(
                                height: SharedDesignTokens.spacingLg),
                            DashboardInboxSection(
                              state: widget.state,
                              onOpenTasks: () {
                                widget.state.tasksController
                                    .setViewFilter('inbox');
                                _goToTab(DaywellTabId.tasks);
                              },
                              onOpenQuickCapture: widget.onOpenQuickCapture,
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else ...[
                  DashboardFinanceSection(
                    state: widget.state,
                    onOpenFinance: () => _goToTab(DaywellTabId.finance),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingLg),
                  DashboardTasksSection(
                    state: widget.state,
                    onOpenTasks: () => _goToTab(DaywellTabId.tasks),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingLg),
                  DashboardCalendarSection(
                    state: widget.state,
                    onOpenCalendar: () => _goToTab(DaywellTabId.calendar),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingLg),
                  DashboardNotesSection(
                    state: widget.state,
                    onOpenNotes: () => _goToTab(DaywellTabId.notes),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingLg),
                  DashboardInboxSection(
                    state: widget.state,
                    onOpenTasks: () {
                      widget.state.tasksController.setViewFilter('inbox');
                      _goToTab(DaywellTabId.tasks);
                    },
                    onOpenQuickCapture: widget.onOpenQuickCapture,
                  ),
                ],
                const SizedBox(height: SharedDesignTokens.spacingXl),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AdaptiveItemRow extends StatelessWidget {
  final Widget? leading;
  final Widget content;
  final Widget trailing;

  const _AdaptiveItemRow({
    this.leading,
    required this.content,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool stackTrailing =
            constraints.maxWidth < 250 || textScale >= 1.5;
        if (stackTrailing) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: SharedDesignTokens.spacingXs),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    content,
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                      ),
                      child: trailing,
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: SharedDesignTokens.spacingXs),
            ],
            Expanded(child: content),
            const SizedBox(width: SharedDesignTokens.spacingSm),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * 0.45,
              ),
              child: trailing,
            ),
          ],
        );
      },
    );
  }
}

class _DashboardMetricsGrid extends StatelessWidget {
  final AppStateManager state;
  final void Function(DaywellTabId tab) onSelectTab;

  const _DashboardMetricsGrid({
    required this.state,
    required this.onSelectTab,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.maxWidth;
        final double textScale = MediaQuery.textScalerOf(context).scale(1.0);
        const double spacing = SharedDesignTokens.spacingCompact;

        final int columns;
        if (maxWidth >= 360 && textScale <= 1.35) {
          columns = 3;
        } else if (maxWidth >= 280 && textScale < 1.8) {
          columns = 2;
        } else {
          columns = 1;
        }

        final double tileWidth = columns == 1
            ? maxWidth
            : (maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: tileWidth,
              child: DashboardActiveTasksMetricTile(
                state: state,
                onTap: () => onSelectTab(DaywellTabId.tasks),
              ),
            ),
            SizedBox(
              width: tileWidth,
              child: DashboardCommitmentsMetricTile(
                state: state,
                onTap: () => onSelectTab(DaywellTabId.finance),
              ),
            ),
            SizedBox(
              width: tileWidth,
              child: DashboardNotesMetricTile(
                state: state,
                onTap: () => onSelectTab(DaywellTabId.notes),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DashboardQuickNavigationStrip extends StatelessWidget {
  final DaywellDestinationSpec tasksSpec;
  final DaywellDestinationSpec calendarSpec;
  final DaywellDestinationSpec notesSpec;
  final DaywellDestinationSpec financeSpec;
  final void Function(DaywellTabId tab) onSelectTab;
  final VoidCallback onOpenQuickCapture;

  const _DashboardQuickNavigationStrip({
    required this.tasksSpec,
    required this.calendarSpec,
    required this.notesSpec,
    required this.financeSpec,
    required this.onSelectTab,
    required this.onOpenQuickCapture,
  });

  @override
  Widget build(BuildContext context) {
    return DaywellSectionContainer(
      title: 'Quick Navigation',
      child: Wrap(
        spacing: SharedDesignTokens.spacingSm,
        runSpacing: SharedDesignTokens.spacingSm,
        children: [
          DaywellButton(
            label: 'Open ${tasksSpec.label}',
            leadingIcon: tasksSpec.icon,
            variant: DaywellButtonVariant.secondary,
            size: DaywellButtonSize.compact,
            onPressed: () => onSelectTab(DaywellTabId.tasks),
          ),
          DaywellButton(
            label: 'Open ${calendarSpec.label}',
            leadingIcon: calendarSpec.icon,
            variant: DaywellButtonVariant.secondary,
            size: DaywellButtonSize.compact,
            onPressed: () => onSelectTab(DaywellTabId.calendar),
          ),
          DaywellButton(
            label: 'Open ${notesSpec.label}',
            leadingIcon: notesSpec.icon,
            variant: DaywellButtonVariant.secondary,
            size: DaywellButtonSize.compact,
            onPressed: () => onSelectTab(DaywellTabId.notes),
          ),
          DaywellButton(
            label: 'Open ${financeSpec.label}',
            leadingIcon: financeSpec.icon,
            variant: DaywellButtonVariant.secondary,
            size: DaywellButtonSize.compact,
            onPressed: () => onSelectTab(DaywellTabId.finance),
          ),
          DaywellButton(
            label: 'Capture <3s',
            leadingIcon: Icons.flash_on_rounded,
            variant: DaywellButtonVariant.primary,
            size: DaywellButtonSize.compact,
            onPressed: onOpenQuickCapture,
          ),
        ],
      ),
    );
  }
}

/// Scoped metric tile listening strictly to [AppStateManager.tasksController].
class DashboardActiveTasksMetricTile extends StatelessWidget {
  final AppStateManager state;
  final VoidCallback onTap;

  const DashboardActiveTasksMetricTile({
    super.key,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state.tasksController,
      builder: (BuildContext context, Widget? _) {
        final tasksState = state.tasksController.state;
        final hasError = tasksState.errorMessage != null &&
            tasksState.errorMessage!.trim().isNotEmpty;
        final pendingCount = tasksState.pendingTasks.length;
        final urgentCount = tasksState.urgentTasks.length;
        final value = tasksState.isLoading && tasksState.tasks.isEmpty
            ? '--'
            : '$pendingCount';
        final subtitle = hasError && tasksState.tasks.isEmpty
            ? 'Tap to open'
            : urgentCount > 0
                ? '$urgentCount urgent'
                : '${tasksState.completedCount} done';

        return _MetricTileCard(
          icon: Icons.check_circle_outline_rounded,
          iconColor: Theme.of(context).colorScheme.primary,
          value: value,
          title: 'Active Tasks',
          subtitle: subtitle,
          onTap: onTap,
        );
      },
    );
  }
}

/// Scoped metric tile listening strictly to [AppStateManager.financeController].
class DashboardCommitmentsMetricTile extends StatelessWidget {
  final AppStateManager state;
  final VoidCallback onTap;

  const DashboardCommitmentsMetricTile({
    super.key,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state.financeController,
      builder: (BuildContext context, Widget? _) {
        final financeState = state.financeController.state;
        final hasData = _financeHasData(financeState);
        final hasError = financeState.errorMessage != null &&
            financeState.errorMessage!.trim().isNotEmpty;
        final count = financeState.pendingCommitments.length;
        final value = financeState.isLoading && !hasData ? '--' : '$count';
        final subtitle = hasError && !hasData
            ? 'Tap to open'
            : financeState.pendingCommitments.isNotEmpty
                ? 'Due soon'
                : 'Up to date';

        return _MetricTileCard(
          icon: Icons.receipt_long_outlined,
          iconColor: context.daywellColors.warning,
          value: value,
          title: 'Commitments',
          subtitle: subtitle,
          onTap: onTap,
        );
      },
    );
  }
}

/// Scoped metric tile listening strictly to [AppStateManager.notesController].
class DashboardNotesMetricTile extends StatelessWidget {
  final AppStateManager state;
  final VoidCallback onTap;

  const DashboardNotesMetricTile({
    super.key,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state.notesController,
      builder: (BuildContext context, Widget? _) {
        final notesState = state.notesController.state;
        final hasError = notesState.errorMessage != null &&
            notesState.errorMessage!.trim().isNotEmpty;
        final activeCount = notesState.activeNotesCount;
        final pinnedCount = notesState.pinnedNotesCount;
        final value = notesState.isLoading && notesState.notes.isEmpty
            ? '--'
            : '$activeCount';
        final subtitle = hasError && notesState.notes.isEmpty
            ? 'Tap to open'
            : pinnedCount > 0
                ? '$pinnedCount pinned'
                : 'Active';

        return _MetricTileCard(
          icon: Icons.menu_book_outlined,
          iconColor: context.daywellColors.transfer,
          value: value,
          title: 'Notes',
          subtitle: subtitle,
          onTap: onTap,
        );
      },
    );
  }
}

class _MetricTileCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MetricTileCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    return DaywellCard(
      onTap: onTap,
      padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: iconColor, size: DaywellIconSize.md),
                const SizedBox(width: SharedDesignTokens.spacingXs),
                Flexible(
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DaywellTypography.caption(
                      color: semantic.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DaywellTypography.numericBody(
                color: semantic.textPrimary,
              ).copyWith(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: SharedDesignTokens.spacingXs),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                color: semantic.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _financeHasData(FinanceModuleState financeState) {
  return financeState.accounts.isNotEmpty ||
      financeState.transactions.isNotEmpty ||
      financeState.commitments.isNotEmpty ||
      financeState.savingsGoals.isNotEmpty ||
      financeState.journalEntries.isNotEmpty ||
      financeState.openingBalanceCents != 0;
}

/// Scoped Finance overview section listening strictly to
/// [AppStateManager.financeController].
class DashboardFinanceSection extends StatelessWidget {
  final AppStateManager state;
  final VoidCallback onOpenFinance;

  const DashboardFinanceSection({
    super.key,
    required this.state,
    required this.onOpenFinance,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state.financeController,
      builder: (BuildContext context, Widget? _) {
        final financeState = state.financeController.state;
        final hasData = _financeHasData(financeState);
        final hasError = financeState.errorMessage != null &&
            financeState.errorMessage!.trim().isNotEmpty;

        final DaywellContentStatus status;
        if (financeState.isLoading && !hasData) {
          status = DaywellContentStatus.loading;
        } else if (hasError && !hasData) {
          status = DaywellContentStatus.error;
        } else {
          status = DaywellContentStatus.content;
        }

        final pendingCommitments = financeState.pendingCommitments;
        final recentActivity = _buildRecentFinanceActivity(financeState);

        return DaywellSectionContainer(
          title: 'Finance Overview',
          actionLabel: 'Manage',
          onActionPressed: onOpenFinance,
          child: DaywellContentState(
            status: status,
            loadingLabel: 'Loading finance overview...',
            errorTitle: 'Unable to load finance overview',
            errorMessage:
                financeState.errorMessage ?? 'Unable to load finance data.',
            onRetry: () => unawaited(state.financeController.loadAll()),
            contentBuilder: (BuildContext context) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasError) ...[
                  DaywellStatusBanner(
                    tone: DaywellStatusTone.error,
                    title: 'Unable to refresh finance overview',
                    message: financeState.errorMessage!,
                    actionLabel: 'Retry',
                    onActionPressed: () =>
                        unawaited(state.financeController.loadAll()),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                ],
                if (!financeState.isSetupCompleted) ...[
                  DaywellStatusBanner(
                    tone: DaywellStatusTone.warning,
                    title: 'Finance setup incomplete',
                    message:
                        'Finish account setup in Finance to track accurate liquid cash and Safe Harbor limits.',
                    actionLabel: 'Open Finance',
                    onActionPressed: onOpenFinance,
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                ],
                if (financeState.isShortfall) ...[
                  DaywellStatusBanner(
                    tone: DaywellStatusTone.error,
                    title: 'Safe Harbor Shortfall',
                    message:
                        'Obligations due through ${SharedDateFormatter.formatGregorianShort(financeState.effectivePlanningPeriodEnd)} exceed liquid cash by ${FinancialEngine.formatBirr(-financeState.availableToSpendCents)}.',
                    actionLabel: 'Open Finance',
                    onActionPressed: onOpenFinance,
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                ],
                if (financeState.nonEtbAccountCount > 0) ...[
                  DaywellStatusBanner(
                    tone: DaywellStatusTone.warning,
                    title: 'Non-ETB accounts excluded',
                    message: financeState.unverifiedAccountCount > 0
                        ? '${financeState.nonEtbAccountCount} non-ETB/unverified account(s) (${financeState.unverifiedAccountCount} unverified) are excluded from ETB Safe Harbor totals.'
                        : '${financeState.nonEtbAccountCount} active non-ETB account(s) are excluded from ETB Safe Harbor totals.',
                    actionLabel: 'Review',
                    onActionPressed: onOpenFinance,
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                ],
                if (financeState.currencyReviewEntryCount > 0 ||
                    financeState.excludedNonEtbEntryCount > 0) ...[
                  DaywellStatusBanner(
                    tone: financeState.currencyReviewEntryCount > 0
                        ? DaywellStatusTone.warning
                        : DaywellStatusTone.info,
                    title: financeState.currencyReviewEntryCount > 0
                        ? 'Ledger currency review needed'
                        : 'Foreign-currency entries isolated',
                    message:
                        '${financeState.excludedNonEtbEntryCount} foreign and ${financeState.currencyReviewEntryCount} unverified/mixed entry(s) remain visible in history but excluded from ETB totals.',
                    actionLabel: 'Open Finance',
                    onActionPressed: onOpenFinance,
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                ],
                if (financeState.unverifiedLegacyPaidCount > 0) ...[
                  DaywellStatusBanner(
                    tone: DaywellStatusTone.warning,
                    title: 'Legacy paid commitments pending check',
                    message:
                        '${financeState.unverifiedLegacyPaidCount} migrated commitment(s) need payment or unpaid verification.',
                    actionLabel: 'Verify',
                    onActionPressed: onOpenFinance,
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                ],
                _SafeHarborSummaryCard(
                  financeState: financeState,
                  onPickHorizon: () async {
                    final picked = await FinanceUiFormatters.pickCalendarDate(
                      context,
                      initialDate: financeState.effectivePlanningPeriodEnd,
                    );
                    if (picked != null) {
                      state.financeController.setPlanningPeriodEnd(picked);
                    }
                  },
                ),
                const SizedBox(height: SharedDesignTokens.spacingMd),
                if (pendingCommitments.isEmpty && recentActivity.isEmpty)
                  DaywellContentState(
                    status: DaywellContentStatus.empty,
                    emptyIcon: Icons.account_balance_wallet_outlined,
                    emptyMessage: 'No commitments or recent transactions',
                    emptySubtitle:
                        'Add accounts, upcoming commitments, or cashflow records in Finance.',
                    emptyActionLabel: 'Open Finance',
                    onEmptyAction: onOpenFinance,
                  )
                else ...[
                  _FinanceCommitmentsPreview(
                    commitments: pendingCommitments,
                    financeState: financeState,
                    onOpenFinance: onOpenFinance,
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingMd),
                  _FinanceTransactionsPreview(
                    items: recentActivity,
                    onOpenFinance: onOpenFinance,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SafeHarborSummaryCard extends StatelessWidget {
  final FinanceModuleState financeState;
  final VoidCallback? onPickHorizon;

  const _SafeHarborSummaryCard({
    required this.financeState,
    this.onPickHorizon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final semantic = context.daywellColors;
    final onContainer = colorScheme.onPrimaryContainer;
    final breakdown = financeState.availableToSpendBreakdown;
    final horizonLabel = SharedDateFormatter.formatGregorianShort(
      financeState.effectivePlanningPeriodEnd,
    );

    return DaywellCard(
      color: colorScheme.primaryContainer,
      borderColor:
          (financeState.isShortfall ? semantic.error : colorScheme.primary)
              .withOpacity(0.25),
      elevation: SharedDesignTokens.elevationLow,
      borderRadius: SharedDesignTokens.radiusLg,
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: SharedDesignTokens.spacingSm,
            runSpacing: SharedDesignTokens.spacingXs,
            children: [
              Text(
                'AVAILABLE TO SPEND',
                style: DaywellTypography.label(
                  color: onContainer.withOpacity(0.85),
                ).copyWith(letterSpacing: 1.0),
              ),
              Wrap(
                spacing: SharedDesignTokens.spacingXs,
                runSpacing: SharedDesignTokens.spacingXs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  InkWell(
                    onTap: onPickHorizon,
                    borderRadius:
                        BorderRadius.circular(SharedDesignTokens.radiusSm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SharedDesignTokens.spacingSm,
                        vertical: SharedDesignTokens.spacingXs,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surface.withOpacity(0.7),
                        borderRadius:
                            BorderRadius.circular(SharedDesignTokens.radiusSm),
                      ),
                      child: Text(
                        'Horizon: $horizonLabel',
                        style: DaywellTypography.caption(
                          color: colorScheme.onSurface,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SharedDesignTokens.spacingSm,
                      vertical: SharedDesignTokens.spacingXs,
                    ),
                    decoration: BoxDecoration(
                      color: financeState.isShortfall
                          ? semantic.error
                          : colorScheme.primary,
                      borderRadius:
                          BorderRadius.circular(SharedDesignTokens.radiusSm),
                    ),
                    child: Text(
                      financeState.isShortfall ? 'SHORTFALL' : 'SAFE HARBOR',
                      style: DaywellTypography.caption(
                        color: colorScheme.onPrimary,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          Text(
            FinancialEngine.formatBirr(breakdown.availableToSpendCents),
            style: DaywellTypography.numericHero(
              color: financeState.isShortfall ? semantic.error : onContainer,
            ),
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          Divider(color: onContainer.withOpacity(0.2)),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Wrap(
            spacing: SharedDesignTokens.spacingMd,
            runSpacing: SharedDesignTokens.spacingSm,
            children: [
              _SafeHarborBreakdownItem(
                label: 'Liquid Cash',
                value: FinancialEngine.formatBirr(breakdown.liquidCashCents),
                textColor: onContainer,
              ),
              if (breakdown.prepaidCardCreditCents > 0)
                _SafeHarborBreakdownItem(
                  label: 'Prepaid Credit',
                  value: FinancialEngine.formatBirr(
                    breakdown.prepaidCardCreditCents,
                  ),
                  textColor: onContainer,
                ),
              _SafeHarborBreakdownItem(
                label: 'Due Payables',
                value: FinancialEngine.formatBirr(breakdown.duePayablesCents),
                textColor: onContainer,
              ),
              if (breakdown.dueNonDebtCommitmentsCents > 0)
                _SafeHarborBreakdownItem(
                  label: 'Bills Due',
                  value: FinancialEngine.formatBirr(
                    breakdown.dueNonDebtCommitmentsCents,
                  ),
                  textColor: onContainer,
                ),
              if (breakdown.shortTermCreditOwedCents > 0)
                _SafeHarborBreakdownItem(
                  label: 'Card Owed',
                  value: FinancialEngine.formatBirr(
                    breakdown.shortTermCreditOwedCents,
                  ),
                  textColor: onContainer,
                ),
              if (breakdown.virtualSavingsReservedCents > 0)
                _SafeHarborBreakdownItem(
                  label: 'Reserved',
                  value: FinancialEngine.formatBirr(
                    breakdown.virtualSavingsReservedCents,
                  ),
                  textColor: onContainer,
                ),
              _SafeHarborBreakdownItem(
                label: 'Net Position',
                value: FinancialEngine.formatBirr(
                  financeState.netFinancialPositionCents,
                ),
                textColor: onContainer,
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingXs),
          Text(
            'Liquid cash plus prepaid card credit minus card debt, due obligations through $horizonLabel, and virtual savings reserves.',
            style: textTheme.bodySmall?.copyWith(
              color: onContainer.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _SafeHarborBreakdownItem extends StatelessWidget {
  final String label;
  final String value;
  final Color textColor;

  const _SafeHarborBreakdownItem({
    required this.label,
    required this.value,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: DaywellTypography.caption(color: textColor.withOpacity(0.8)),
        ),
        Text(
          value,
          style: DaywellTypography.numericBody(color: textColor),
        ),
      ],
    );
  }
}

class _FinanceCommitmentsPreview extends StatelessWidget {
  final List<CommitmentModel> commitments;
  final FinanceModuleState financeState;
  final VoidCallback onOpenFinance;

  const _FinanceCommitmentsPreview({
    required this.commitments,
    required this.financeState,
    required this.onOpenFinance,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    return DaywellSectionContainer(
      title: 'Upcoming Commitments',
      count: commitments.isNotEmpty ? commitments.length : null,
      useCard: true,
      child: commitments.isEmpty
          ? Text(
              'No pending commitments due.',
              style: textTheme.bodySmall?.copyWith(
                color: semantic.textSecondary,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...commitments.take(3).map(
                  (CommitmentModel commitment) {
                    final res =
                        financeState.resolveCommitmentCurrency(commitment);
                    final amountLabel = FinanceUiFormatters.formatCurrencyCents(
                      commitment.amountCents,
                      currencyCode:
                          res.isEligibleEtb ? 'ETB' : res.currencyCode,
                    );
                    final String? isolationLabel;
                    if (res.isExcludedNonEtb) {
                      isolationLabel =
                          'Excluded (${res.currencyCode ?? 'Foreign'})';
                    } else if (res.needsReview) {
                      isolationLabel = 'Currency Review';
                    } else if (commitment.direction ==
                        CommitmentDirection.inflow) {
                      isolationLabel = 'Expected Income';
                    } else {
                      isolationLabel = null;
                    }
                    return Padding(
                      padding: const EdgeInsets.only(
                        bottom: SharedDesignTokens.spacingSm,
                      ),
                      child: _AdaptiveItemRow(
                        content: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              commitment.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: semantic.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Due: ${SharedDateFormatter.formatDual(commitment.dueDate, useAmharic: false)}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: semantic.textSecondary,
                              ),
                            ),
                            if (isolationLabel != null) ...[
                              const SizedBox(height: 4),
                              DaywellStatusBadge(
                                label: isolationLabel,
                                tone: res.isExcludedNonEtb || res.needsReview
                                    ? DaywellStatusTone.warning
                                    : DaywellStatusTone.info,
                                showIcon: false,
                              ),
                            ],
                          ],
                        ),
                        trailing: Text(
                          amountLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DaywellTypography.numericBody(
                            color: res.needsReview
                                ? semantic.warning
                                : commitment.direction ==
                                        CommitmentDirection.inflow
                                    ? semantic.income
                                    : semantic.expense,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (commitments.length > 3)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: DaywellButton(
                      label: '+ ${commitments.length - 3} more commitments',
                      variant: DaywellButtonVariant.text,
                      size: DaywellButtonSize.compact,
                      onPressed: onOpenFinance,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _FinanceActivityPreviewItem {
  final String title;
  final String detail;
  final int amountCents;
  final String kind; // 'income' | 'expense' | 'transfer'
  final String amountText;
  final String? isolationBadgeLabel;
  final bool needsCurrencyReview;

  const _FinanceActivityPreviewItem({
    required this.title,
    required this.detail,
    required this.amountCents,
    required this.kind,
    required this.amountText,
    this.isolationBadgeLabel,
    this.needsCurrencyReview = false,
  });
}

List<_FinanceActivityPreviewItem> _buildRecentFinanceActivity(
  FinanceModuleState financeState,
) {
  final accountById = {for (final a in financeState.accounts) a.id: a};
  final classifications = financeState.classificationsByEntryId;
  final ledgerEntries = financeState.activeJournalEntries
      .where((e) => e.entryType != EntryType.adjustment)
      .toList();

  if (ledgerEntries.isNotEmpty) {
    ledgerEntries.sort(
      (a, b) => b.occurrenceDate.compareTo(a.occurrenceDate),
    );
    final categoryNames = {
      for (final c in financeState.categories) c.id: c.name,
    };
    final postingsByEntry = <String, List<PostingModel>>{};
    for (final p in financeState.postings) {
      postingsByEntry.putIfAbsent(p.entryId, () => []).add(p);
    }

    return ledgerEntries.map((entry) {
      final entryPostings = postingsByEntry[entry.id] ?? const <PostingModel>[];
      final cls =
          classifications[entry.id] ?? financeState.classifyEntry(entry);
      final hasIncome = entryPostings.any(
        (p) =>
            p.accountId == SystemControlAccounts.income &&
            p.direction == PostingDirection.credit,
      );
      final hasExpense = entryPostings.any(
        (p) =>
            p.accountId == SystemControlAccounts.expense &&
            p.direction == PostingDirection.debit,
      );

      final String kind;
      if (entry.entryType == EntryType.transfer) {
        kind = 'transfer';
      } else if (hasIncome && !hasExpense) {
        kind = 'income';
      } else {
        kind = 'expense';
      }

      String? categoryId;
      for (final p in entryPostings) {
        if (p.categoryId != null) {
          categoryId = p.categoryId;
          break;
        }
      }

      int amountCents = 0;
      if (kind == 'transfer') {
        amountCents = entryPostings
            .where((p) =>
                p.direction == PostingDirection.debit &&
                p.accountId != SystemControlAccounts.expense)
            .fold<int>(0, (sum, p) => sum + p.amountCents);
      } else {
        amountCents = entryPostings
            .where((p) => p.direction == PostingDirection.debit)
            .fold<int>(0, (sum, p) => sum + p.amountCents);
      }

      final sign = kind == 'income' ? '+' : (kind == 'transfer' ? '' : '-');
      final isMixed = cls.touchedCurrencies.length > 1;
      final String amountText;
      if (isMixed) {
        final legs = entryPostings
            .where((p) =>
                !SystemControlAccounts.isSystemControlId(p.accountId) &&
                !(accountById[p.accountId]?.isSystem ?? false))
            .map((p) => FinanceUiFormatters.formatCurrencyCents(
                  p.amountCents,
                  currencyCode: accountById[p.accountId]?.currencyCode,
                ))
            .toList(growable: false);
        amountText = legs.isNotEmpty
            ? legs.join(' / ')
            : 'Mixed (${cls.touchedCurrencies.join(' / ')})';
      } else {
        final displayCurrency = cls.nativeCurrencyCode ??
            (cls.touchedCurrencies.length == 1 &&
                    cls.touchedCurrencies.first != 'UNVERIFIED'
                ? cls.touchedCurrencies.first
                : null);
        amountText = '$sign${FinanceUiFormatters.formatCurrencyCents(
          amountCents,
          currencyCode: displayCurrency,
        )}';
      }

      final String? isolationBadgeLabel;
      if (cls.isExcludedNonEtb) {
        isolationBadgeLabel =
            'Excluded (${cls.nativeCurrencyCode ?? 'Non-ETB'})';
      } else if (cls.needsCurrencyReview) {
        isolationBadgeLabel = 'Currency Review';
      } else {
        isolationBadgeLabel = null;
      }

      final title = kind == 'transfer'
          ? 'Transfer'
          : (categoryId != null
              ? (categoryNames[categoryId] ?? entry.description)
              : entry.description);
      final parsedDate = SharedDateFormatter.tryParseFlexibleToCalendarDate(
        entry.occurrenceDate,
      );
      final detail = entry.description.trim().isNotEmpty &&
              entry.description.trim() != title
          ? entry.description.trim()
          : (parsedDate != null
              ? SharedDateFormatter.formatDual(parsedDate, useAmharic: false)
              : entry.occurrenceDate);

      return _FinanceActivityPreviewItem(
        title: title,
        detail: detail,
        amountCents: amountCents,
        kind: kind,
        amountText: amountText,
        isolationBadgeLabel: isolationBadgeLabel,
        needsCurrencyReview: cls.needsCurrencyReview,
      );
    }).toList(growable: false);
  }

  final recentTransactions = List<TransactionModel>.from(
    financeState.activeTransactions,
  )..sort(
      (TransactionModel a, TransactionModel b) =>
          b.transactionDate.compareTo(a.transactionDate),
    );
  return recentTransactions.map((tx) {
    final detail = (tx.payee != null && tx.payee!.trim().isNotEmpty)
        ? tx.payee!.trim()
        : (tx.note != null && tx.note!.trim().isNotEmpty)
            ? tx.note!.trim()
            : SharedDateFormatter.formatDual(
                tx.transactionDate,
                useAmharic: false,
              );
    final txAcc = tx.accountId != null ? accountById[tx.accountId] : null;
    final sign = tx.type == 'income' ? '+' : (tx.type == 'transfer' ? '' : '-');
    final currencyCode = txAcc != null ? txAcc.currencyCode : '';
    final tier = DoubleEntryEngine.classifyCurrencyCode(currencyCode);
    final String? badgeLabel;
    if (tier == CurrencyValidationTier.verifiedNonEtb) {
      badgeLabel =
          'Excluded (${DoubleEntryEngine.normalizeCurrencyCode(currencyCode)})';
    } else if (tier == CurrencyValidationTier.unverified) {
      badgeLabel = 'Currency Review';
    } else {
      badgeLabel = null;
    }
    return _FinanceActivityPreviewItem(
      title: tx.categoryName,
      detail: detail,
      amountCents: tx.amountCents,
      kind: tx.type,
      amountText: '$sign${FinanceUiFormatters.formatCurrencyCents(
        tx.amountCents,
        currencyCode: currencyCode,
      )}',
      isolationBadgeLabel: badgeLabel,
      needsCurrencyReview: tier == CurrencyValidationTier.unverified,
    );
  }).toList(growable: false);
}

class _FinanceTransactionsPreview extends StatelessWidget {
  final List<_FinanceActivityPreviewItem> items;
  final VoidCallback onOpenFinance;

  const _FinanceTransactionsPreview({
    required this.items,
    required this.onOpenFinance,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    return DaywellSectionContainer(
      title: 'Recent Transactions',
      count: items.isNotEmpty ? items.length : null,
      useCard: true,
      child: items.isEmpty
          ? Text(
              'No recent transactions recorded.',
              style: textTheme.bodySmall?.copyWith(
                color: semantic.textSecondary,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...items.take(3).map(
                  (_FinanceActivityPreviewItem item) {
                    final Color amountColor;
                    if (item.needsCurrencyReview) {
                      amountColor = semantic.warning;
                    } else {
                      switch (item.kind) {
                        case 'income':
                          amountColor = semantic.income;
                        case 'transfer':
                          amountColor = semantic.transfer;
                        default:
                          amountColor = semantic.expense;
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.only(
                        bottom: SharedDesignTokens.spacingSm,
                      ),
                      child: _AdaptiveItemRow(
                        content: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: semantic.textPrimary,
                              ),
                            ),
                            Text(
                              item.detail,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: semantic.textSecondary,
                              ),
                            ),
                            if (item.isolationBadgeLabel != null) ...[
                              const SizedBox(height: 4),
                              DaywellStatusBadge(
                                label: item.isolationBadgeLabel!,
                                tone: DaywellStatusTone.warning,
                                showIcon: false,
                              ),
                            ],
                          ],
                        ),
                        trailing: Text(
                          item.amountText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: DaywellTypography.numericBody(
                            color: amountColor,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (items.length > 3)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: DaywellButton(
                      label: '+ ${items.length - 3} more transactions',
                      variant: DaywellButtonVariant.text,
                      size: DaywellButtonSize.compact,
                      onPressed: onOpenFinance,
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Scoped Tasks overview section listening strictly to
/// [AppStateManager.tasksController].
class DashboardTasksSection extends StatelessWidget {
  final AppStateManager state;
  final VoidCallback onOpenTasks;

  const DashboardTasksSection({
    super.key,
    required this.state,
    required this.onOpenTasks,
  });

  List<TaskEntity> _prioritizedPendingTasks(List<TaskEntity> pending) {
    final today = CalendarDate.today();
    const priorityRank = <String, int>{
      'urgent': 0,
      'high': 1,
      'medium': 2,
      'low': 3,
    };

    final sorted = List<TaskEntity>.from(pending);
    sorted.sort((TaskEntity a, TaskEntity b) {
      final aUrgentOrDue =
          a.isOverdue || (a.dueDate != null && !a.dueDate!.isAfter(today));
      final bUrgentOrDue =
          b.isOverdue || (b.dueDate != null && !b.dueDate!.isAfter(today));
      if (aUrgentOrDue != bUrgentOrDue) {
        return aUrgentOrDue ? -1 : 1;
      }
      final rankA = priorityRank[a.priority] ?? 2;
      final rankB = priorityRank[b.priority] ?? 2;
      if (rankA != rankB) return rankA.compareTo(rankB);
      final dueA = a.dueDate ?? CalendarDate(year: 2099, month: 12, day: 31);
      final dueB = b.dueDate ?? CalendarDate(year: 2099, month: 12, day: 31);
      return dueA.compareTo(dueB);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state.tasksController,
      builder: (BuildContext context, Widget? _) {
        final tasksState = state.tasksController.state;
        final hasData = tasksState.tasks.isNotEmpty;
        final hasError = tasksState.errorMessage != null &&
            tasksState.errorMessage!.trim().isNotEmpty;

        final DaywellContentStatus status;
        if (tasksState.isLoading && !hasData) {
          status = DaywellContentStatus.loading;
        } else if (hasError && !hasData) {
          status = DaywellContentStatus.error;
        } else if (!hasData) {
          status = DaywellContentStatus.empty;
        } else {
          status = DaywellContentStatus.content;
        }

        final activeTotal = tasksState.tasks
            .where((TaskEntity t) => t.status != 'cancelled')
            .length;
        final completedCount = tasksState.completedCount;
        final pendingTasks = _prioritizedPendingTasks(tasksState.pendingTasks);
        final double progressValue =
            activeTotal > 0 ? completedCount / activeTotal : 0.0;

        return DaywellSectionContainer(
          title: 'Today & Urgent Tasks',
          count: tasksState.pendingTasks.isNotEmpty
              ? tasksState.pendingTasks.length
              : null,
          actionLabel: 'View All',
          onActionPressed: onOpenTasks,
          child: DaywellContentState(
            status: status,
            loadingLabel: 'Loading tasks...',
            errorTitle: 'Unable to load tasks',
            errorMessage: tasksState.errorMessage ?? 'Unable to load tasks.',
            onRetry: () => unawaited(state.tasksController.loadAll()),
            emptyIcon: Icons.task_alt_rounded,
            emptyMessage: 'No tasks recorded yet',
            emptySubtitle:
                'Add daily priorities or project milestones from the Tasks tab.',
            emptyActionLabel: 'Open Tasks',
            onEmptyAction: onOpenTasks,
            contentBuilder: (BuildContext context) {
              final semantic = context.daywellColors;
              final textTheme = Theme.of(context).textTheme;

              return DaywellCard(
                padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasError) ...[
                      DaywellStatusBanner(
                        tone: DaywellStatusTone.error,
                        title: 'Unable to refresh tasks',
                        message: tasksState.errorMessage!,
                        actionLabel: 'Retry',
                        onActionPressed: () =>
                            unawaited(state.tasksController.loadAll()),
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingCompact),
                    ],
                    DaywellProgressBar(
                      value: progressValue,
                      label: 'Task Completion',
                      valueText: '$completedCount / $activeTotal done',
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingSm),
                    Text(
                      '${tasksState.todayCount} due today or overdue · ${tasksState.pendingTasks.length} open',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    if (pendingTasks.isEmpty)
                      Text(
                        'All active tasks are completed.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: semantic.success,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      ...pendingTasks.take(4).map(
                        (TaskEntity task) {
                          final DaywellStatusTone badgeTone =
                              task.isOverdue || task.priority == 'urgent'
                                  ? DaywellStatusTone.error
                                  : (task.priority == 'high'
                                      ? DaywellStatusTone.warning
                                      : DaywellStatusTone.info);
                          final String badgeLabel = task.isOverdue
                              ? 'OVERDUE'
                              : task.priority.toUpperCase();

                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: SharedDesignTokens.spacingSm,
                            ),
                            child: _AdaptiveItemRow(
                              leading: Semantics(
                                label: 'Toggle ${task.title}',
                                child: Checkbox(
                                  value: task.isCompleted,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.padded,
                                  activeColor:
                                      Theme.of(context).colorScheme.primary,
                                  onChanged: (_) => unawaited(
                                    state.tasksController.toggleTaskStatus(
                                      task.id,
                                    ),
                                  ),
                                ),
                              ),
                              content: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    task.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: semantic.textPrimary,
                                      decoration: task.isCompleted
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  if (task.dueDate != null)
                                    Text(
                                      'Due: ${SharedDateFormatter.formatDual(task.dueDate!, useAmharic: false)}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.bodySmall?.copyWith(
                                        color: semantic.textSecondary,
                                      ),
                                    ),
                                  if (TaskRecurrenceEngine.resolveEffectiveConfig(
                                        task,
                                      ) !=
                                      null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.repeat,
                                          size: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            TaskRecurrenceEngine.formatSummary(
                                              TaskRecurrenceEngine
                                                  .resolveEffectiveConfig(task),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: textTheme.bodySmall?.copyWith(
                                              color: semantic.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              trailing: DaywellStatusBadge(
                                label: badgeLabel,
                                tone: badgeTone,
                              ),
                            ),
                          );
                        },
                      ),
                    if (pendingTasks.length > 4)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: DaywellButton(
                          label: '+ ${pendingTasks.length - 4} more tasks',
                          variant: DaywellButtonVariant.text,
                          size: DaywellButtonSize.compact,
                          onPressed: onOpenTasks,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Scoped Calendar overview section listening strictly to
/// [AppStateManager.calendarController].
class DashboardCalendarSection extends StatelessWidget {
  final AppStateManager state;
  final VoidCallback onOpenCalendar;

  const DashboardCalendarSection({
    super.key,
    required this.state,
    required this.onOpenCalendar,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state.calendarController,
      builder: (BuildContext context, Widget? _) {
        final calendarState = state.calendarController.state;
        final hasAnyEvents = calendarState.events.isNotEmpty;
        final hasError = calendarState.errorMessage != null &&
            calendarState.errorMessage!.trim().isNotEmpty;

        final DaywellContentStatus status;
        if (calendarState.isLoading && !hasAnyEvents) {
          status = DaywellContentStatus.loading;
        } else if (hasError && !hasAnyEvents) {
          status = DaywellContentStatus.error;
        } else if (!hasAnyEvents) {
          status = DaywellContentStatus.empty;
        } else {
          status = DaywellContentStatus.content;
        }

        final today = CalendarDate.today();
        final todayEvents = calendarState.eventsForCalendarDate(today);

        return DaywellSectionContainer(
          title: "Today's Schedule",
          count: todayEvents.isNotEmpty ? todayEvents.length : null,
          actionLabel: 'Calendar',
          onActionPressed: onOpenCalendar,
          child: DaywellContentState(
            status: status,
            loadingLabel: 'Loading today\'s schedule...',
            errorTitle: 'Unable to load schedule',
            errorMessage:
                calendarState.errorMessage ?? 'Unable to load calendar events.',
            onRetry: () => unawaited(state.calendarController.loadAll()),
            emptyIcon: Icons.event_available_outlined,
            emptyMessage: 'No calendar events stored',
            emptySubtitle:
                'Scheduled calendar events for today will appear here offline.',
            emptyActionLabel: 'Open Calendar',
            onEmptyAction: onOpenCalendar,
            contentBuilder: (BuildContext context) {
              final semantic = context.daywellColors;
              final textTheme = Theme.of(context).textTheme;

              return DaywellCard(
                padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasError) ...[
                      DaywellStatusBanner(
                        tone: DaywellStatusTone.error,
                        title: 'Unable to refresh schedule',
                        message: calendarState.errorMessage!,
                        actionLabel: 'Retry',
                        onActionPressed: () =>
                            unawaited(state.calendarController.loadAll()),
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingCompact),
                    ],
                    if (todayEvents.isEmpty) ...[
                      Text(
                        'No events scheduled for today.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: semantic.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingXs),
                      Text(
                        '${calendarState.events.length} synced calendar event(s) stored on other dates.',
                        style: textTheme.bodySmall?.copyWith(
                          color: semantic.textSecondary,
                        ),
                      ),
                    ] else ...[
                      ...todayEvents.take(3).map((CalendarEventEntity event) {
                        final parsedTime =
                            DayTimeOfDay.tryParse(event.startTime);
                        final timeLabel = event.isAllDay
                            ? 'All day'
                            : (parsedTime?.toDisplay12Hour() ?? 'Scheduled');
                        return Padding(
                          padding: const EdgeInsets.only(
                            bottom: SharedDesignTokens.spacingSm,
                          ),
                          child: _AdaptiveItemRow(
                            content: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: semantic.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  timeLabel,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: semantic.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            trailing: DaywellStatusBadge(
                              label: event.category.toUpperCase(),
                              tone: DaywellStatusTone.info,
                            ),
                          ),
                        );
                      }),
                      if (todayEvents.length > 3)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: DaywellButton(
                            label: '+ ${todayEvents.length - 3} more today',
                            variant: DaywellButtonVariant.text,
                            size: DaywellButtonSize.compact,
                            onPressed: onOpenCalendar,
                          ),
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Scoped Notes overview section listening strictly to
/// [AppStateManager.notesController].
class DashboardNotesSection extends StatelessWidget {
  final AppStateManager state;
  final VoidCallback onOpenNotes;

  const DashboardNotesSection({
    super.key,
    required this.state,
    required this.onOpenNotes,
  });

  List<NoteEntity> _recentActiveNotes(List<NoteEntity> notes) {
    final active =
        notes.where((NoteEntity n) => !n.isTrashed && !n.isArchived).toList();
    active.sort((NoteEntity a, NoteEntity b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return active;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state.notesController,
      builder: (BuildContext context, Widget? _) {
        final notesState = state.notesController.state;
        final activeNotes = _recentActiveNotes(notesState.notes);
        final hasData = activeNotes.isNotEmpty;
        final hasError = notesState.errorMessage != null &&
            notesState.errorMessage!.trim().isNotEmpty;

        final DaywellContentStatus status;
        if (notesState.isLoading && !hasData) {
          status = DaywellContentStatus.loading;
        } else if (hasError && !hasData) {
          status = DaywellContentStatus.error;
        } else if (!hasData) {
          status = DaywellContentStatus.empty;
        } else {
          status = DaywellContentStatus.content;
        }

        return DaywellSectionContainer(
          title: 'Recent Notes',
          count: activeNotes.isNotEmpty ? activeNotes.length : null,
          actionLabel: 'All Notes',
          onActionPressed: onOpenNotes,
          child: DaywellContentState(
            status: status,
            loadingLabel: 'Loading notes...',
            errorTitle: 'Unable to load notes',
            errorMessage: notesState.errorMessage ?? 'Unable to load notes.',
            onRetry: () => unawaited(state.notesController.loadNotes()),
            emptyIcon: Icons.menu_book_outlined,
            emptyMessage: 'No active notes yet',
            emptySubtitle:
                'Capture ideas, references, and reflections in Notes.',
            emptyActionLabel: 'Open Notes',
            onEmptyAction: onOpenNotes,
            contentBuilder: (BuildContext context) {
              final semantic = context.daywellColors;
              final textTheme = Theme.of(context).textTheme;

              return DaywellCard(
                padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasError) ...[
                      DaywellStatusBanner(
                        tone: DaywellStatusTone.error,
                        title: 'Unable to refresh notes',
                        message: notesState.errorMessage!,
                        actionLabel: 'Retry',
                        onActionPressed: () =>
                            unawaited(state.notesController.loadNotes()),
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingCompact),
                    ],
                    ...activeNotes.take(3).map((NoteEntity note) {
                      final snippet = note.content.trim();
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: SharedDesignTokens.spacingSm,
                        ),
                        child: _AdaptiveItemRow(
                          content: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                note.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: semantic.textPrimary,
                                ),
                              ),
                              if (snippet.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  snippet,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: semantic.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: DaywellStatusBadge(
                            label: note.isPinned
                                ? 'PINNED'
                                : note.category.toUpperCase(),
                            tone: note.isPinned
                                ? DaywellStatusTone.warning
                                : DaywellStatusTone.info,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Scoped Quick Capture Inbox section listening strictly to
/// [AppStateManager.inboxController].
class DashboardInboxSection extends StatelessWidget {
  final AppStateManager state;
  final VoidCallback onOpenTasks;
  final VoidCallback onOpenQuickCapture;

  const DashboardInboxSection({
    super.key,
    required this.state,
    required this.onOpenTasks,
    required this.onOpenQuickCapture,
  });

  List<InboxItemEntity> _newestUnprocessed(List<InboxItemEntity> unprocessed) {
    final sorted = List<InboxItemEntity>.from(unprocessed);
    sorted.sort(
      (InboxItemEntity a, InboxItemEntity b) =>
          b.createdAt.compareTo(a.createdAt),
    );
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state.inboxController,
      builder: (BuildContext context, Widget? _) {
        final inboxState = state.inboxController.state;
        final hasData = inboxState.items.isNotEmpty;
        final hasError = inboxState.errorMessage != null &&
            inboxState.errorMessage!.trim().isNotEmpty;

        final DaywellContentStatus status;
        if (inboxState.isLoading && !hasData) {
          status = DaywellContentStatus.loading;
        } else if (hasError && !hasData) {
          status = DaywellContentStatus.error;
        } else if (!hasData) {
          status = DaywellContentStatus.empty;
        } else {
          status = DaywellContentStatus.content;
        }

        final pendingItems = _newestUnprocessed(inboxState.unprocessedItems);

        return DaywellSectionContainer(
          title: 'Inbox Captures',
          count: pendingItems.isNotEmpty ? pendingItems.length : null,
          actionLabel: 'Review Tasks',
          onActionPressed: onOpenTasks,
          child: DaywellContentState(
            status: status,
            loadingLabel: 'Loading inbox captures...',
            errorTitle: 'Unable to load inbox captures',
            errorMessage:
                inboxState.errorMessage ?? 'Unable to load inbox captures.',
            onRetry: () => unawaited(
              state.inboxController.loadItems(includeProcessed: true),
            ),
            emptyIcon: Icons.flash_on_rounded,
            emptyMessage: 'Inbox is clear',
            emptySubtitle:
                'Use 1-Tap Quick Capture to save thoughts, expenses, or tasks fast.',
            emptyActionLabel: 'Quick Capture',
            onEmptyAction: onOpenQuickCapture,
            contentBuilder: (BuildContext context) {
              final semantic = context.daywellColors;
              final textTheme = Theme.of(context).textTheme;

              return DaywellCard(
                padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasError) ...[
                      DaywellStatusBanner(
                        tone: DaywellStatusTone.error,
                        title: 'Unable to refresh inbox',
                        message: inboxState.errorMessage!,
                        actionLabel: 'Retry',
                        onActionPressed: () => unawaited(
                          state.inboxController
                              .loadItems(includeProcessed: true),
                        ),
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingCompact),
                    ],
                    Text(
                      '${inboxState.unprocessedCount} unorganized · ${inboxState.processedCount} processed',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    if (pendingItems.isEmpty)
                      Text(
                        'All captured items have been processed.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: semantic.success,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      ...pendingItems.take(3).map(
                            (InboxItemEntity item) => Padding(
                              padding: const EdgeInsets.only(
                                bottom: SharedDesignTokens.spacingSm,
                              ),
                              child: _AdaptiveItemRow(
                                content: Text(
                                  item.rawText,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: semantic.textPrimary,
                                  ),
                                ),
                                trailing: DaywellStatusBadge(
                                  label: item.category.toUpperCase(),
                                  tone: DaywellStatusTone.info,
                                ),
                              ),
                            ),
                          ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
