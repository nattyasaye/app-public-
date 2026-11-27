import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'daywell_shell_routes.dart';

/// Adaptive shell navigation chrome and state-preserving route container.
///
/// Switches cleanly between bottom [NavigationBar] on compact widths (< 600dp)
/// and [NavigationRail] on medium/expanded widths (>= 600dp), keeps the
/// content subtree keyed at an identical depth across layouts so visited tab
/// states survive breakpoint resizing, disables [HeroMode] on inactive/covered
/// tabs to prevent duplicate FAB hero tag assertions, and coordinates Android
/// system-back navigation across secondary routes, active modules, main-tab
/// history, and Today root double-back-to-exit via [PopScope].
class DaywellAdaptiveScaffold extends StatefulWidget {
  static const double wideBreakpoint = 600.0;
  static const double compactRailMinHeight = 440.0;
  static const ValueKey<String> _contentSlotKey =
      ValueKey<String>('daywell_shell_content_slot');

  final DaywellShellController shellController;
  final Widget Function(DaywellTabId tab) tabBuilder;
  final Widget Function(DaywellSecondaryRoute route) secondaryRouteBuilder;
  final List<DaywellDestinationSpec> destinations;
  final Future<void> Function()? onExitApp;

  const DaywellAdaptiveScaffold({
    super.key,
    required this.shellController,
    required this.tabBuilder,
    required this.secondaryRouteBuilder,
    this.destinations = kDaywellPrimaryDestinations,
    this.onExitApp,
  });

  @override
  State<DaywellAdaptiveScaffold> createState() =>
      _DaywellAdaptiveScaffoldState();
}

class _DaywellAdaptiveScaffoldState extends State<DaywellAdaptiveScaffold> {
  bool _isHandlingSystemBack = false;

  Future<void> _handleSystemBack() async {
    if (_isHandlingSystemBack) return;
    _isHandlingSystemBack = true;
    try {
      final outcome = await widget.shellController.handleSystemBack();
      if (!mounted) return;
      switch (outcome) {
        case DaywellShellBackOutcome.handledSecondaryRoute:
        case DaywellShellBackOutcome.handledByModule:
        case DaywellShellBackOutcome.handledTabHistory:
          return;
        case DaywellShellBackOutcome.promptExitApp:
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.hideCurrentSnackBar();
          messenger?.showSnackBar(
            SnackBar(
              content: const Text('Press back again to exit'),
              duration: widget.shellController.exitConfirmWindow,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        case DaywellShellBackOutcome.exitApp:
          ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
          final exitFn = widget.onExitApp ?? () => SystemNavigator.pop();
          await exitFn();
          return;
      }
    } finally {
      _isHandlingSystemBack = false;
    }
  }

  Widget _buildNavigationRail(int selectedIndex) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints railConstraints) {
        final rail = NavigationRail(
          selectedIndex: selectedIndex,
          onDestinationSelected: (int index) =>
              widget.shellController.selectDestinationAt(
            index,
            destinations: widget.destinations,
          ),
          labelType: NavigationRailLabelType.all,
          destinations: widget.destinations
              .map(
                (DaywellDestinationSpec dest) => NavigationRailDestination(
                  icon: Icon(dest.icon),
                  selectedIcon: Icon(dest.selectedIcon),
                  label: Text(dest.label),
                ),
              )
              .toList(growable: false),
        );

        if (railConstraints.maxHeight >=
            DaywellAdaptiveScaffold.compactRailMinHeight) {
          return rail;
        }

        return SingleChildScrollView(
          child: SizedBox(
            height: math.max(
              railConstraints.maxHeight,
              DaywellAdaptiveScaffold.compactRailMinHeight,
            ),
            child: rail,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.shellController,
      builder: (BuildContext context, Widget? _) {
        final secondaryRoute = widget.shellController.activeSecondaryRoute;
        final hasSecondary = secondaryRoute != null;
        final selectedIndex =
            widget.shellController.indexIn(widget.destinations);

        final Widget tabStack = Visibility(
          visible: !hasSecondary,
          maintainState: true,
          child: IndexedStack(
            index: selectedIndex,
            children: List<Widget>.generate(
              widget.destinations.length,
              (int index) {
                final tab = widget.destinations[index].id;
                if (!widget.shellController.hasVisited(tab)) {
                  return const SizedBox.shrink();
                }
                final isActiveTab =
                    !hasSecondary && widget.shellController.currentTab == tab;
                return HeroMode(
                  enabled: isActiveTab,
                  child: widget.tabBuilder(tab),
                );
              },
              growable: false,
            ),
          ),
        );

        final Widget contentHost = Stack(
          fit: StackFit.expand,
          children: [
            tabStack,
            if (hasSecondary) widget.secondaryRouteBuilder(secondaryRoute),
          ],
        );

        return PopScope<Object?>(
          canPop: false,
          onPopInvokedWithResult: (bool didPop, Object? _) {
            if (!didPop) {
              unawaited(_handleSystemBack());
            }
          },
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final isWide = constraints.maxWidth >=
                  DaywellAdaptiveScaffold.wideBreakpoint;

              return Scaffold(
                body: SafeArea(
                  bottom: isWide,
                  child: Row(
                    children: [
                      if (isWide) ...[
                        _buildNavigationRail(selectedIndex),
                        const VerticalDivider(width: 1),
                      ],
                      Expanded(
                        key: DaywellAdaptiveScaffold._contentSlotKey,
                        child: contentHost,
                      ),
                    ],
                  ),
                ),
                bottomNavigationBar: isWide
                    ? null
                    : NavigationBar(
                        selectedIndex: selectedIndex,
                        onDestinationSelected: (int index) =>
                            widget.shellController.selectDestinationAt(
                          index,
                          destinations: widget.destinations,
                        ),
                        destinations: widget.destinations
                            .map(
                              (DaywellDestinationSpec dest) =>
                                  NavigationDestination(
                                icon: Icon(dest.icon),
                                selectedIcon: Icon(dest.selectedIcon),
                                label: dest.label,
                              ),
                            )
                            .toList(growable: false),
                      ),
              );
            },
          ),
        );
      },
    );
  }
}
