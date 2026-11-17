import 'package:flutter/material.dart';

/// Primary top-level destinations hosted by the Daywell application shell.
enum DaywellTabId {
  today,
  tasks,
  calendar,
  notes,
  finance,
  more,
}

/// Secondary utility destinations unwound via back navigation.
enum DaywellSecondaryRoute {
  backup,
}

/// Declarative metadata describing a primary module destination in the shell.
class DaywellDestinationSpec {
  final DaywellTabId id;
  final String routeKey;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const DaywellDestinationSpec({
    required this.id,
    required this.routeKey,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

/// Ordered registry of primary destinations shared by mobile [NavigationBar]
/// and tablet [NavigationRail].
const List<DaywellDestinationSpec> kDaywellPrimaryDestinations =
    <DaywellDestinationSpec>[
  DaywellDestinationSpec(
    id: DaywellTabId.today,
    routeKey: 'today',
    label: 'Today',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
  ),
  DaywellDestinationSpec(
    id: DaywellTabId.tasks,
    routeKey: 'tasks',
    label: 'Tasks',
    icon: Icons.check_circle_outline_rounded,
    selectedIcon: Icons.check_circle_rounded,
  ),
  DaywellDestinationSpec(
    id: DaywellTabId.calendar,
    routeKey: 'calendar',
    label: 'Calendar',
    icon: Icons.calendar_today_outlined,
    selectedIcon: Icons.calendar_today_rounded,
  ),
  DaywellDestinationSpec(
    id: DaywellTabId.notes,
    routeKey: 'notes',
    label: 'Notes',
    icon: Icons.menu_book_outlined,
    selectedIcon: Icons.menu_book_rounded,
  ),
  DaywellDestinationSpec(
    id: DaywellTabId.finance,
    routeKey: 'finance',
    label: 'Finance',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet_rounded,
  ),
  DaywellDestinationSpec(
    id: DaywellTabId.more,
    routeKey: 'more',
    label: 'More',
    icon: Icons.grid_view_outlined,
    selectedIcon: Icons.grid_view_rounded,
  ),
];

/// Typed navigation and lazy tab-activation controller for [DaywellAdaptiveScaffold].
class DaywellShellController extends ChangeNotifier {
  DaywellTabId _currentTab;
  DaywellSecondaryRoute? _activeSecondaryRoute;
  final Set<DaywellTabId> _visitedTabs = <DaywellTabId>{};

  DaywellShellController({
    DaywellTabId initialTab = DaywellTabId.today,
  }) : _currentTab = initialTab {
    _visitedTabs.add(initialTab);
  }

  DaywellTabId get currentTab => _currentTab;
  int get currentTabIndex => indexIn();
  DaywellSecondaryRoute? get activeSecondaryRoute => _activeSecondaryRoute;
  bool get hasSecondaryRoute => _activeSecondaryRoute != null;

  bool hasVisited(DaywellTabId tab) => _visitedTabs.contains(tab);

  /// Resolves the active destination index within [destinations] without
  /// assuming [DaywellTabId.values] order matches UI destination ordering.
  int indexIn([
    List<DaywellDestinationSpec> destinations = kDaywellPrimaryDestinations,
  ]) {
    final idx = destinations.indexWhere(
      (DaywellDestinationSpec d) => d.id == _currentTab,
    );
    return idx >= 0 ? idx : 0;
  }

  void selectTab(DaywellTabId tab) {
    if (_currentTab == tab && _activeSecondaryRoute == null) return;
    _currentTab = tab;
    _visitedTabs.add(tab);
    _activeSecondaryRoute = null;
    notifyListeners();
  }

  /// Selects the destination at [index] inside [destinations], safely ignoring
  /// out-of-range indexes.
  void selectDestinationAt(
    int index, {
    List<DaywellDestinationSpec> destinations = kDaywellPrimaryDestinations,
  }) {
    if (index < 0 || index >= destinations.length) return;
    selectTab(destinations[index].id);
  }

  void selectTabIndex(int index) {
    selectDestinationAt(index);
  }

  void openSecondaryRoute(DaywellSecondaryRoute route) {
    if (_activeSecondaryRoute == route) return;
    _activeSecondaryRoute = route;
    notifyListeners();
  }

  /// Unwinds an active secondary route and returns true when handled.
  bool handleBackNavigation() {
    if (_activeSecondaryRoute == null) return false;
    _activeSecondaryRoute = null;
    notifyListeners();
    return true;
  }

  /// Resolves string route identifiers from secondary entry points into typed
  /// shell routes via [kDaywellPrimaryDestinations] or secondary routes.
  void navigateByKey(String routeKey) {
    for (final dest in kDaywellPrimaryDestinations) {
      if (dest.routeKey == routeKey) {
        selectTab(dest.id);
        return;
      }
    }
    if (routeKey == 'backup') {
      openSecondaryRoute(DaywellSecondaryRoute.backup);
    }
  }
}
