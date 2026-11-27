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

/// Asynchronous back-navigation handler registered by a module or secondary
/// view. Returns `true` if the back action was consumed internally.
typedef DaywellBackNavigationHandler = Future<bool> Function();

/// Result of resolving a system back press inside [DaywellShellController].
enum DaywellShellBackOutcome {
  handledSecondaryRoute,
  handledByModule,
  handledTabHistory,
  promptExitApp,
  exitApp,
}

/// Typed navigation, tab history, module back-delegation, and lazy
/// tab-activation controller for [DaywellAdaptiveScaffold].
class DaywellShellController extends ChangeNotifier {
  static const Duration defaultExitConfirmWindow = Duration(seconds: 2);

  DaywellTabId _currentTab;
  DaywellSecondaryRoute? _activeSecondaryRoute;
  final Set<DaywellTabId> _visitedTabs = <DaywellTabId>{};
  final List<DaywellTabId> _tabHistory;
  final Map<DaywellTabId, DaywellBackNavigationHandler> _tabBackHandlers =
      <DaywellTabId, DaywellBackNavigationHandler>{};
  final Map<DaywellSecondaryRoute, DaywellBackNavigationHandler>
      _secondaryBackHandlers =
      <DaywellSecondaryRoute, DaywellBackNavigationHandler>{};
  final DateTime Function() _clock;
  final Duration exitConfirmWindow;
  DateTime? _lastRootBackAttemptAt;

  DaywellShellController({
    DaywellTabId initialTab = DaywellTabId.today,
    DateTime Function()? clock,
    this.exitConfirmWindow = defaultExitConfirmWindow,
  })  : _currentTab = initialTab,
        _clock = clock ?? DateTime.now,
        _tabHistory = initialTab == DaywellTabId.today
            ? <DaywellTabId>[DaywellTabId.today]
            : <DaywellTabId>[DaywellTabId.today, initialTab] {
    _visitedTabs.add(initialTab);
  }

  DaywellTabId get currentTab => _currentTab;
  int get currentTabIndex => indexIn();
  DaywellSecondaryRoute? get activeSecondaryRoute => _activeSecondaryRoute;
  bool get hasSecondaryRoute => _activeSecondaryRoute != null;
  List<DaywellTabId> get tabHistory =>
      List<DaywellTabId>.unmodifiable(_tabHistory);
  bool get isAtTodayRoot =>
      _activeSecondaryRoute == null &&
      _currentTab == DaywellTabId.today &&
      _tabHistory.length <= 1;

  bool hasVisited(DaywellTabId tab) => _visitedTabs.contains(tab);

  void registerTabBackHandler(
    DaywellTabId tab,
    DaywellBackNavigationHandler handler,
  ) {
    _tabBackHandlers[tab] = handler;
  }

  void unregisterTabBackHandler(
    DaywellTabId tab, [
    DaywellBackNavigationHandler? handler,
  ]) {
    if (handler == null || identical(_tabBackHandlers[tab], handler)) {
      _tabBackHandlers.remove(tab);
    }
  }

  void registerSecondaryBackHandler(
    DaywellSecondaryRoute route,
    DaywellBackNavigationHandler handler,
  ) {
    _secondaryBackHandlers[route] = handler;
  }

  void unregisterSecondaryBackHandler(
    DaywellSecondaryRoute route, [
    DaywellBackNavigationHandler? handler,
  ]) {
    if (handler == null ||
        identical(_secondaryBackHandlers[route], handler)) {
      _secondaryBackHandlers.remove(route);
    }
  }

  void resetExitBackPrompt() {
    _lastRootBackAttemptAt = null;
  }

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
    _lastRootBackAttemptAt = null;
    if (_currentTab == tab && _activeSecondaryRoute == null) return;
    _currentTab = tab;
    _visitedTabs.add(tab);
    _activeSecondaryRoute = null;
    if (tab == DaywellTabId.today) {
      _tabHistory
        ..clear()
        ..add(DaywellTabId.today);
    } else {
      _tabHistory.remove(tab);
      _tabHistory.add(tab);
    }
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
    _lastRootBackAttemptAt = null;
    if (_activeSecondaryRoute == route) return;
    _activeSecondaryRoute = route;
    notifyListeners();
  }

  /// Unwinds an active secondary route synchronously and returns true when
  /// handled. Used by secondary AppBar back buttons and unit tests.
  bool handleBackNavigation() {
    _lastRootBackAttemptAt = null;
    if (_activeSecondaryRoute == null) return false;
    _activeSecondaryRoute = null;
    notifyListeners();
    return true;
  }

  /// Pops one entry from main-tab navigation history back toward
  /// [DaywellTabId.today], returning `true` when the active tab changed.
  bool popTabHistory() {
    if (_activeSecondaryRoute != null) return false;
    if (_tabHistory.length > 1) {
      _tabHistory.removeLast();
      final previousTab = _tabHistory.last;
      if (_currentTab != previousTab) {
        _currentTab = previousTab;
        _visitedTabs.add(previousTab);
        _lastRootBackAttemptAt = null;
        notifyListeners();
        return true;
      }
    }
    if (_currentTab != DaywellTabId.today) {
      _tabHistory
        ..clear()
        ..add(DaywellTabId.today);
      _currentTab = DaywellTabId.today;
      _visitedTabs.add(DaywellTabId.today);
      _lastRootBackAttemptAt = null;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Resolves an Android system back press at the shell level in strict
  /// priority order:
  /// 1. Secondary shell routes (nested screens)
  /// 2. Active module internal back handler (split-view, subtabs, filters, etc.)
  /// 3. Main-tab navigation history back toward [DaywellTabId.today]
  /// 4. Double-back-to-exit within [exitConfirmWindow] at [DaywellTabId.today]
  Future<DaywellShellBackOutcome> handleSystemBack() async {
    final secondary = _activeSecondaryRoute;
    if (secondary != null) {
      _lastRootBackAttemptAt = null;
      final secondaryHandler = _secondaryBackHandlers[secondary];
      if (secondaryHandler != null) {
        final consumed = await secondaryHandler();
        if (consumed) {
          return DaywellShellBackOutcome.handledSecondaryRoute;
        }
      }
      _activeSecondaryRoute = null;
      notifyListeners();
      return DaywellShellBackOutcome.handledSecondaryRoute;
    }

    final moduleHandler = _tabBackHandlers[_currentTab];
    if (moduleHandler != null) {
      final consumed = await moduleHandler();
      if (consumed) {
        _lastRootBackAttemptAt = null;
        return DaywellShellBackOutcome.handledByModule;
      }
    }

    if (popTabHistory()) {
      return DaywellShellBackOutcome.handledTabHistory;
    }

    final now = _clock();
    final last = _lastRootBackAttemptAt;
    if (last != null &&
        !now.isBefore(last) &&
        now.difference(last) <= exitConfirmWindow) {
      _lastRootBackAttemptAt = null;
      return DaywellShellBackOutcome.exitApp;
    }

    _lastRootBackAttemptAt = now;
    return DaywellShellBackOutcome.promptExitApp;
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
