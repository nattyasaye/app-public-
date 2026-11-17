import 'package:flutter/material.dart';
import '../shared_foundation.dart';
import 'daywell_theme_extensions.dart';
import 'daywell_typography.dart';

/// Centralized Material 3 component themes derived from [ColorScheme],
/// [DaywellSemanticColors], [TextTheme], and [SharedDesignTokens].
/// Targets Flutter 3.24.5 API compatibility.
class DaywellComponentThemes {
  const DaywellComponentThemes._();

  static AppBarTheme appBarTheme({
    required DaywellSemanticColors semantic,
  }) {
    return AppBarTheme(
      backgroundColor: semantic.canvas,
      foregroundColor: semantic.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: SharedDesignTokens.elevationNone,
      scrolledUnderElevation: SharedDesignTokens.elevationLow,
      centerTitle: false,
      titleTextStyle: DaywellTypography.fromToken(
        SharedDesignTokens.typeTitle,
        color: semantic.textPrimary,
      ),
    );
  }

  static CardTheme cardTheme({
    required DaywellSemanticColors semantic,
  }) {
    return CardTheme(
      color: semantic.card,
      surfaceTintColor: Colors.transparent,
      elevation: SharedDesignTokens.elevationNone,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SharedDesignTokens.radiusLg),
        side: BorderSide(color: semantic.border, width: 1.0),
      ),
    );
  }

  static ElevatedButtonThemeData elevatedButtonTheme({
    required ColorScheme colorScheme,
    required DaywellSemanticColors semantic,
    required TextTheme textTheme,
  }) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        disabledBackgroundColor: colorScheme.onSurface.withOpacity(0.12),
        disabledForegroundColor: semantic.textDisabled,
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
        padding: const EdgeInsets.symmetric(
          horizontal: SharedDesignTokens.spacingMd,
          vertical: SharedDesignTokens.spacingCompact,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
        ),
        elevation: SharedDesignTokens.elevationLow,
        textStyle: textTheme.labelLarge,
      ),
    );
  }

  static FilledButtonThemeData filledButtonTheme({
    required ColorScheme colorScheme,
    required DaywellSemanticColors semantic,
    required TextTheme textTheme,
  }) {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        disabledBackgroundColor: colorScheme.onSurface.withOpacity(0.12),
        disabledForegroundColor: semantic.textDisabled,
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
        padding: const EdgeInsets.symmetric(
          horizontal: SharedDesignTokens.spacingMd,
          vertical: SharedDesignTokens.spacingCompact,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
        ),
        textStyle: textTheme.labelLarge,
      ),
    );
  }

  static OutlinedButtonThemeData outlinedButtonTheme({
    required ColorScheme colorScheme,
    required DaywellSemanticColors semantic,
    required TextTheme textTheme,
  }) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.primary,
        disabledForegroundColor: semantic.textDisabled,
        side: BorderSide(color: colorScheme.outline, width: 1.0),
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
        padding: const EdgeInsets.symmetric(
          horizontal: SharedDesignTokens.spacingMd,
          vertical: SharedDesignTokens.spacingCompact,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
        ),
        textStyle: textTheme.labelLarge,
      ),
    );
  }

  static TextButtonThemeData textButtonTheme({
    required ColorScheme colorScheme,
    required DaywellSemanticColors semantic,
    required TextTheme textTheme,
  }) {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        disabledForegroundColor: semantic.textDisabled,
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
        padding: const EdgeInsets.symmetric(
          horizontal: SharedDesignTokens.spacingCompact,
          vertical: SharedDesignTokens.spacingSm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
        ),
        textStyle: textTheme.labelLarge,
      ),
    );
  }

  static InputDecorationTheme inputDecorationTheme({
    required ColorScheme colorScheme,
    required DaywellSemanticColors semantic,
    required TextTheme textTheme,
  }) {
    OutlineInputBorder buildBorder(Color color, {double width = 1.0}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecorationTheme(
      filled: true,
      fillColor: semantic.card,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: SharedDesignTokens.spacingMd,
        vertical: SharedDesignTokens.spacingCompact,
      ),
      labelStyle: textTheme.bodyMedium?.copyWith(color: semantic.textSecondary),
      floatingLabelStyle: textTheme.labelMedium?.copyWith(
        color: colorScheme.primary,
      ),
      hintStyle: textTheme.bodyMedium?.copyWith(color: semantic.textMuted),
      helperStyle: textTheme.bodySmall?.copyWith(color: semantic.textMuted),
      errorStyle: textTheme.bodySmall?.copyWith(color: colorScheme.error),
      border: buildBorder(colorScheme.outline),
      enabledBorder: buildBorder(colorScheme.outline),
      focusedBorder: buildBorder(colorScheme.primary, width: 2.0),
      errorBorder: buildBorder(colorScheme.error),
      focusedErrorBorder: buildBorder(colorScheme.error, width: 2.0),
      disabledBorder: buildBorder(semantic.border),
    );
  }

  static DialogTheme dialogTheme({
    required DaywellSemanticColors semantic,
    required TextTheme textTheme,
  }) {
    return DialogTheme(
      backgroundColor: semantic.elevated,
      surfaceTintColor: Colors.transparent,
      elevation: SharedDesignTokens.elevationHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SharedDesignTokens.radiusXl),
      ),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    );
  }

  static BottomSheetThemeData bottomSheetTheme({
    required DaywellSemanticColors semantic,
  }) {
    return BottomSheetThemeData(
      backgroundColor: semantic.elevated,
      modalBackgroundColor: semantic.elevated,
      surfaceTintColor: Colors.transparent,
      elevation: SharedDesignTokens.elevationHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SharedDesignTokens.radiusSheet),
        ),
      ),
    );
  }

  static NavigationBarThemeData navigationBarTheme({
    required ColorScheme colorScheme,
    required DaywellSemanticColors semantic,
    required TextTheme textTheme,
  }) {
    return NavigationBarThemeData(
      backgroundColor: semantic.card,
      surfaceTintColor: Colors.transparent,
      elevation: SharedDesignTokens.elevationMedium,
      indicatorColor: colorScheme.primaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 20,
          color: selected ? colorScheme.primary : semantic.textSecondary,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        final base = textTheme.labelSmall ??
            DaywellTypography.caption(color: semantic.textSecondary);
        return base.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? colorScheme.primary : semantic.textSecondary,
        );
      }),
    );
  }

  static ChipThemeData chipTheme({
    required ColorScheme colorScheme,
    required DaywellSemanticColors semantic,
    required TextTheme textTheme,
  }) {
    final baseLabel = textTheme.labelMedium ??
        DaywellTypography.label(color: semantic.textPrimary);
    return ChipThemeData(
      backgroundColor: semantic.surfaceSubtle,
      selectedColor: colorScheme.primaryContainer,
      disabledColor: colorScheme.onSurface.withOpacity(0.08),
      checkmarkColor: colorScheme.onPrimaryContainer,
      deleteIconColor: semantic.textSecondary,
      side: BorderSide(color: semantic.border, width: 1.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: SharedDesignTokens.spacingSm,
        vertical: SharedDesignTokens.spacingXs,
      ),
      labelStyle: baseLabel.copyWith(color: semantic.textPrimary),
      secondaryLabelStyle:
          baseLabel.copyWith(color: colorScheme.onPrimaryContainer),
    );
  }

  static DividerThemeData dividerTheme({
    required DaywellSemanticColors semantic,
  }) {
    return DividerThemeData(
      color: semantic.divider,
      thickness: 1.0,
      space: 1.0,
    );
  }

  static PopupMenuThemeData popupMenuTheme({
    required DaywellSemanticColors semantic,
    required TextTheme textTheme,
  }) {
    return PopupMenuThemeData(
      color: semantic.elevated,
      surfaceTintColor: Colors.transparent,
      elevation: SharedDesignTokens.elevationMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
        side: BorderSide(color: semantic.border, width: 1.0),
      ),
      textStyle: textTheme.bodyMedium,
    );
  }

  static SnackBarThemeData snackBarTheme({
    required Brightness brightness,
    required TextTheme textTheme,
  }) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark
        ? SharedDesignTokens.elevatedDark
        : SharedDesignTokens.textPrimaryLight;

    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: bg,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: SharedDesignTokens.textPrimaryDark,
      ),
      actionTextColor: SharedDesignTokens.primaryDarkMode,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
      ),
    );
  }
}
