import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'daywell_shell_routes.dart';

/// Adaptive shell navigation chrome and state-preserving route container.
///
/// Switches cleanly between bottom [NavigationBar] on compact widths (< 600dp)
/// and [NavigationRail] on medium/expanded widths (>= 600dp), keeps the
/// content subtree keyed at an identical depth across layouts so visited tab
/// states survive breakpoint resizing, disables [HeroMode] on inactive/covered
/// tabs to prevent duplicate FAB hero tag assertions, and unwinds secondary
/// routes cleanly via [PopScope].
class DaywellAdaptiveScaffold extends StatelessWidget {
  static const double wideBreakpoint = 600.0;
  static const double compactRailMinHeight = 440.0;
  static const ValueKey<String> _contentSlotKey =
      ValueKey<String>('daywell_shell_content_slot');

  final DaywellShellController shellController;
  final Widget Function(DaywellTabId tab) tabBuilder;
  final Widget Function(DaywellSecondaryRoute route) secondaryRouteBuilder;
  final List<DaywellDestinationSpec> destinations;

  const DaywellAdaptiveScaffold({
    super.key,
    required this.shellController,
    required this.tabBuilder,
    required this.secondaryRouteBuilder,
    this.destinations = kDaywellPrimaryDestinations,
  });

  Widget _buildNavigationRail(int selectedIndex) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints railConstraints) {
        final rail = NavigationRail(
          selectedIndex: selectedIndex,
          onDestinationSelected: (int index) =>
              shellController.selectDestinationAt(
            index,
            destinations: destinations,
          ),
          labelType: NavigationRailLabelType.all,
          destinations: destinations
              .map(
                (DaywellDestinationSpec dest) => NavigationRailDestination(
                  icon: Icon(dest.icon),
                  selectedIcon: Icon(dest.selectedIcon),
                  label: Text(dest.label),
                ),
              )
              .toList(growable: false),
        );

        if (railConstraints.maxHeight >= compactRailMinHeight) {
          return rail;
        }

        return SingleChildScrollView(
          child: SizedBox(
            height: math.max(railConstraints.maxHeight, compactRailMinHeight),
            child: rail,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: shellController,
      builder: (BuildContext context, Widget? _) {
        final secondaryRoute = shellController.activeSecondaryRoute;
        final hasSecondary = secondaryRoute != null;
        final selectedIndex = shellController.indexIn(destinations);

        final Widget tabStack = Visibility(
          visible: !hasSecondary,
          maintainState: true,
          child: IndexedStack(
            index: selectedIndex,
            children: List<Widget>.generate(
              destinations.length,
              (int index) {
                final tab = destinations[index].id;
                if (!shellController.hasVisited(tab)) {
                  return const SizedBox.shrink();
                }
                final isActiveTab =
                    !hasSecondary && shellController.currentTab == tab;
                return HeroMode(
                  enabled: isActiveTab,
                  child: tabBuilder(tab),
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
            if (hasSecondary) secondaryRouteBuilder(secondaryRoute),
          ],
        );

        return PopScope<Object?>(
          canPop: !hasSecondary,
          onPopInvokedWithResult: (bool didPop, Object? _) {
            if (!didPop) {
              shellController.handleBackNavigation();
            }
          },
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final isWide = constraints.maxWidth >= wideBreakpoint;

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
                        key: _contentSlotKey,
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
                            shellController.selectDestinationAt(
                          index,
                          destinations: destinations,
                        ),
                        destinations: destinations
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
