import 'package:flutter/material.dart';

import '../../application/finance/finance_controller.dart';
import '../../core/shared_foundation.dart';
import '../app_state.dart';
import '../widgets/shared_ui_widgets.dart';
import 'finance/finance_composer_sheet.dart';
import 'finance/finance_overview_tab.dart';
import 'finance/finance_plan_tab.dart';
import 'finance/finance_reports_tab.dart';
import 'finance/finance_setup_wizard.dart';
import 'finance/finance_transactions_tab.dart';

/// Stage 4 modular Finance shell built exclusively on Stage 3 design tokens,
/// shared primitives, and the authoritative double-entry ledger controller.
class FinanceView extends StatefulWidget {
  final AppStateManager? state;
  final FinanceController? controller;
  final VoidCallback? onOpenQuickCapture;

  const FinanceView({
    super.key,
    this.state,
    this.controller,
    this.onOpenQuickCapture,
  }) : assert(
          state != null || controller != null,
          'Either state or controller must be provided to FinanceView',
        );

  FinanceController get effectiveController =>
      controller ?? state!.financeController;

  @override
  State<FinanceView> createState() => _FinanceViewState();
}

class _FinanceViewState extends State<FinanceView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    widget.effectiveController.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant FinanceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effectiveController != widget.effectiveController) {
      oldWidget.effectiveController.removeListener(_onControllerChanged);
      widget.effectiveController.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.effectiveController.removeListener(_onControllerChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.effectiveController;
    final financeState = ctrl.state;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final double? adaptiveToolbarHeight = textScale > 1.3
        ? (kToolbarHeight * textScale.clamp(1.0, 1.85)).ceilToDouble()
        : null;

    final status = financeState.isLoading
        ? DaywellContentStatus.loading
        : DaywellContentStatus.content;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: adaptiveToolbarHeight,
        title: Text(
          'Finance',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        actions: [
          if (financeState.isSetupCompleted)
            Padding(
              padding: const EdgeInsets.only(
                right: SharedDesignTokens.spacingSm,
              ),
              child: DaywellButton(
                label: '+ Record',
                size: DaywellButtonSize.compact,
                onPressed: () => FinanceComposerSheet.show(
                  context,
                  controller: ctrl,
                ),
              ),
            ),
        ],
        bottom: financeState.isSetupCompleted
            ? TabBar(
                controller: _tabController,
                isScrollable:
                    MediaQuery.sizeOf(context).width < 420 || textScale > 1.25,
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'Transactions'),
                  Tab(text: 'Plan'),
                  Tab(text: 'Reports'),
                ],
              )
            : null,
      ),
      body: DaywellContentState(
        status: status,
        loadingLabel: 'Loading double-entry ledger...',
        contentBuilder: (ctx) {
          if (!financeState.isSetupCompleted) {
            return FinanceSetupWizard(controller: ctrl);
          }

          return Column(
            children: [
              if (financeState.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SharedDesignTokens.spacingMd,
                    SharedDesignTokens.spacingSm,
                    SharedDesignTokens.spacingMd,
                    0,
                  ),
                  child: DaywellStatusBanner(
                    title: 'Finance Action Error',
                    message: financeState.errorMessage!,
                    tone: DaywellStatusTone.error,
                    actionLabel: 'Reload',
                    onActionPressed: ctrl.loadAll,
                  ),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    FinanceOverviewTab(
                      controller: ctrl,
                      onOpenTransactions: () => _tabController.animateTo(1),
                      onOpenPlan: () => _tabController.animateTo(2),
                      onOpenReports: () => _tabController.animateTo(3),
                    ),
                    FinanceTransactionsTab(controller: ctrl),
                    FinancePlanTab(controller: ctrl),
                    FinanceReportsTab(controller: ctrl),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
