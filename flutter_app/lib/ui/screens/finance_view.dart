import 'package:flutter/material.dart';

import '../../application/daily_rhythm/daily_rhythm_controller.dart';
import '../../application/finance/finance_controller.dart';
import '../../core/shared_foundation.dart';
import '../app_state.dart';
import '../shell/daywell_shell_routes.dart';
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
  final DailyRhythmController? dailyRhythmController;
  final DaywellShellController? shellController;
  final VoidCallback? onOpenQuickCapture;
  final ({int tabIndex, int nonce})? requestedTab;

  const FinanceView({
    super.key,
    this.state,
    this.controller,
    this.dailyRhythmController,
    this.shellController,
    this.onOpenQuickCapture,
    this.requestedTab,
  }) : assert(
          state != null || controller != null,
          'Either state or controller must be provided to FinanceView',
        );

  FinanceController get effectiveController =>
      controller ?? state!.financeController;

  DailyRhythmController? get effectiveDailyRhythmController =>
      dailyRhythmController ?? state?.dailyRhythmController;

  @override
  State<FinanceView> createState() => _FinanceViewState();
}

class _FinanceViewState extends State<FinanceView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final GlobalKey<FinanceSetupWizardState> _setupWizardKey =
      GlobalKey<FinanceSetupWizardState>();
  late final List<int> _tabHistory;
  late int _lastRecordedTabIndex;
  bool _isPoppingTab = false;

  @override
  void initState() {
    super.initState();
    final initialIndex = (widget.requestedTab?.tabIndex ?? 0).clamp(0, 3);
    _tabController = TabController(
      length: 4,
      initialIndex: initialIndex,
      vsync: this,
    );
    _tabHistory = <int>[initialIndex];
    _lastRecordedTabIndex = initialIndex;
    _tabController.addListener(_onTabChanged);
    widget.effectiveController.addListener(_onControllerChanged);
    widget.shellController
        ?.registerTabBackHandler(DaywellTabId.finance, _handleModuleBack);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onTabChanged() {
    final next = _tabController.index;
    if (next == _lastRecordedTabIndex) return;
    _lastRecordedTabIndex = next;
    if (_isPoppingTab) return;
    if (next == 0) {
      _tabHistory
        ..clear()
        ..add(0);
    } else {
      _tabHistory.remove(next);
      _tabHistory.add(next);
    }
  }

  Future<bool> _handleModuleBack() async {
    if (!widget.effectiveController.state.isSetupCompleted) {
      return _setupWizardKey.currentState?.handleBackStep() ?? false;
    }
    if (_tabHistory.length > 1) {
      _tabHistory.removeLast();
      final previousIndex = _tabHistory.last;
      _isPoppingTab = true;
      _lastRecordedTabIndex = previousIndex;
      _tabController.animateTo(previousIndex);
      _isPoppingTab = false;
      return true;
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant FinanceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effectiveController != widget.effectiveController) {
      oldWidget.effectiveController.removeListener(_onControllerChanged);
      widget.effectiveController.addListener(_onControllerChanged);
    }
    if (oldWidget.shellController != widget.shellController) {
      oldWidget.shellController
          ?.unregisterTabBackHandler(DaywellTabId.finance, _handleModuleBack);
      widget.shellController
          ?.registerTabBackHandler(DaywellTabId.finance, _handleModuleBack);
    }
    if (widget.requestedTab != null &&
        widget.requestedTab != oldWidget.requestedTab) {
      final targetIndex = widget.requestedTab!.tabIndex.clamp(0, 3);
      if (_tabController.index != targetIndex) {
        _tabController.animateTo(targetIndex);
      }
    }
  }

  @override
  void dispose() {
    widget.shellController
        ?.unregisterTabBackHandler(DaywellTabId.finance, _handleModuleBack);
    widget.effectiveController.removeListener(_onControllerChanged);
    _tabController.removeListener(_onTabChanged);
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
            return FinanceSetupWizard(
              key: _setupWizardKey,
              controller: ctrl,
            );
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
                    FinanceTransactionsTab(
                      controller: ctrl,
                      dailyRhythmController:
                          widget.effectiveDailyRhythmController,
                    ),
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
