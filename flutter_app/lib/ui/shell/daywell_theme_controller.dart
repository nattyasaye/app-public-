import 'package:flutter/material.dart';

/// Runtime theme mode controller for the Daywell application shell.
///
/// Holds the active [ThemeMode] in memory without modifying Drift database
/// schemas, while providing an explicit extension point for future persistence.
class DaywellThemeController extends ChangeNotifier {
  ThemeMode _themeMode;

  DaywellThemeController({
    ThemeMode initialMode = ThemeMode.system,
  }) : _themeMode = initialMode;

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }

  String get displayLabel => labelForMode(_themeMode);

  static String labelForMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System default';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }
}
