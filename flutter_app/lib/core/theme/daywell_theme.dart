import 'package:flutter/material.dart';
import '../shared_foundation.dart';
import 'daywell_component_themes.dart';
import 'daywell_theme_extensions.dart';
import 'daywell_typography.dart';

export 'daywell_theme_extensions.dart';
export 'daywell_typography.dart';

/// Centralized Daywell Material 3 theme entry point driven by [SharedDesignTokens].
class DaywellTheme {
  const DaywellTheme._();

  static const ColorScheme lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: SharedDesignTokens.primaryEmerald,
    onPrimary: SharedDesignTokens.onPrimaryLight,
    primaryContainer: SharedDesignTokens.secondaryMint,
    onPrimaryContainer: SharedDesignTokens.onSecondaryLight,
    secondary: SharedDesignTokens.primaryEmeraldLight,
    onSecondary: SharedDesignTokens.onPrimaryLight,
    secondaryContainer: SharedDesignTokens.secondaryMintLight,
    onSecondaryContainer: SharedDesignTokens.onSecondaryLight,
    tertiary: SharedDesignTokens.semanticTransfer,
    onTertiary: SharedDesignTokens.onSemanticTransfer,
    tertiaryContainer: SharedDesignTokens.semanticTransferContainerLight,
    onTertiaryContainer: SharedDesignTokens.onSemanticTransferContainerLight,
    error: SharedDesignTokens.semanticError,
    onError: SharedDesignTokens.onSemanticError,
    errorContainer: SharedDesignTokens.semanticErrorContainerLight,
    onErrorContainer: SharedDesignTokens.onSemanticErrorContainerLight,
    surface: SharedDesignTokens.canvasLight,
    onSurface: SharedDesignTokens.textPrimaryLight,
    surfaceContainerLowest: SharedDesignTokens.cardLight,
    surfaceContainerLow: SharedDesignTokens.canvasLight,
    surfaceContainer: SharedDesignTokens.surfaceSubtleLight,
    surfaceContainerHigh: SharedDesignTokens.surfaceSubtleLight,
    surfaceContainerHighest: SharedDesignTokens.dividerLight,
    onSurfaceVariant: SharedDesignTokens.textSecondaryLight,
    outline: SharedDesignTokens.textMutedLight,
    outlineVariant: SharedDesignTokens.borderLight,
    shadow: SharedDesignTokens.textPrimaryLight,
    scrim: SharedDesignTokens.textPrimaryLight,
    inverseSurface: SharedDesignTokens.cardDark,
    onInverseSurface: SharedDesignTokens.textPrimaryDark,
    inversePrimary: SharedDesignTokens.primaryDarkMode,
  );

  static const ColorScheme darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: SharedDesignTokens.primaryDarkMode,
    onPrimary: SharedDesignTokens.onPrimaryDark,
    primaryContainer: SharedDesignTokens.secondaryMintDark,
    onPrimaryContainer: SharedDesignTokens.onSecondaryDark,
    secondary: SharedDesignTokens.primaryDarkMode,
    onSecondary: SharedDesignTokens.onPrimaryDark,
    secondaryContainer: SharedDesignTokens.secondaryMintDark,
    onSecondaryContainer: SharedDesignTokens.onSecondaryDark,
    tertiary: SharedDesignTokens.onSemanticTransferContainerDark,
    onTertiary: SharedDesignTokens.onSemanticTransfer,
    tertiaryContainer: SharedDesignTokens.semanticTransferContainerDark,
    onTertiaryContainer: SharedDesignTokens.onSemanticTransferContainerDark,
    error: SharedDesignTokens.onSemanticErrorContainerDark,
    onError: SharedDesignTokens.semanticErrorContainerDark,
    errorContainer: SharedDesignTokens.semanticErrorContainerDark,
    onErrorContainer: SharedDesignTokens.onSemanticErrorContainerDark,
    surface: SharedDesignTokens.canvasDark,
    onSurface: SharedDesignTokens.textPrimaryDark,
    surfaceContainerLowest: SharedDesignTokens.canvasDark,
    surfaceContainerLow: SharedDesignTokens.surfaceSubtleDark,
    surfaceContainer: SharedDesignTokens.cardDark,
    surfaceContainerHigh: SharedDesignTokens.elevatedDark,
    surfaceContainerHighest: SharedDesignTokens.elevatedDark,
    onSurfaceVariant: SharedDesignTokens.textSecondaryDark,
    outline: SharedDesignTokens.textMutedDark,
    outlineVariant: SharedDesignTokens.borderDark,
    shadow: SharedDesignTokens.onSemanticExpense,
    scrim: SharedDesignTokens.onSemanticExpense,
    inverseSurface: SharedDesignTokens.cardLight,
    onInverseSurface: SharedDesignTokens.textPrimaryLight,
    inversePrimary: SharedDesignTokens.primaryEmerald,
  );

  static final ThemeData light = _buildTheme(Brightness.light);
  static final ThemeData dark = _buildTheme(Brightness.dark);

  static ThemeData forBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? dark : light;
  }

  static ThemeData resolve(
    ThemeMode mode, {
    required Brightness platformBrightness,
  }) {
    switch (mode) {
      case ThemeMode.light:
        return light;
      case ThemeMode.dark:
        return dark;
      case ThemeMode.system:
        return forBrightness(platformBrightness);
    }
  }

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = isDark ? darkColorScheme : lightColorScheme;
    final semantic = isDark
        ? const DaywellSemanticColors.dark()
        : const DaywellSemanticColors.light();
    final textTheme = DaywellTypography.buildTextTheme(brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: semantic.canvas,
      canvasColor: semantic.canvas,
      cardColor: semantic.card,
      dividerColor: semantic.divider,
      disabledColor: semantic.textDisabled,
      textTheme: textTheme,
      appBarTheme: DaywellComponentThemes.appBarTheme(semantic: semantic),
      cardTheme: DaywellComponentThemes.cardTheme(semantic: semantic),
      elevatedButtonTheme: DaywellComponentThemes.elevatedButtonTheme(
        colorScheme: colorScheme,
        semantic: semantic,
        textTheme: textTheme,
      ),
      filledButtonTheme: DaywellComponentThemes.filledButtonTheme(
        colorScheme: colorScheme,
        semantic: semantic,
        textTheme: textTheme,
      ),
      outlinedButtonTheme: DaywellComponentThemes.outlinedButtonTheme(
        colorScheme: colorScheme,
        semantic: semantic,
        textTheme: textTheme,
      ),
      textButtonTheme: DaywellComponentThemes.textButtonTheme(
        colorScheme: colorScheme,
        semantic: semantic,
        textTheme: textTheme,
      ),
      inputDecorationTheme: DaywellComponentThemes.inputDecorationTheme(
        colorScheme: colorScheme,
        semantic: semantic,
        textTheme: textTheme,
      ),
      dialogTheme: DaywellComponentThemes.dialogTheme(
        semantic: semantic,
        textTheme: textTheme,
      ),
      bottomSheetTheme:
          DaywellComponentThemes.bottomSheetTheme(semantic: semantic),
      navigationBarTheme: DaywellComponentThemes.navigationBarTheme(
        colorScheme: colorScheme,
        semantic: semantic,
        textTheme: textTheme,
      ),
      chipTheme: DaywellComponentThemes.chipTheme(
        colorScheme: colorScheme,
        semantic: semantic,
        textTheme: textTheme,
      ),
      dividerTheme: DaywellComponentThemes.dividerTheme(semantic: semantic),
      popupMenuTheme: DaywellComponentThemes.popupMenuTheme(
        semantic: semantic,
        textTheme: textTheme,
      ),
      snackBarTheme: DaywellComponentThemes.snackBarTheme(
        brightness: brightness,
        textTheme: textTheme,
      ),
      extensions: <ThemeExtension<dynamic>>[
        semantic,
      ],
    );
  }
}
