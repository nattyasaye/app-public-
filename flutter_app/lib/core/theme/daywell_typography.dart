import 'package:flutter/material.dart';
import '../shared_foundation.dart';

/// Centralized typography mapping built from [SharedDesignTokens] with
/// system Latin + Ethiopic font fallback lists (zero bundled font assets).
class DaywellTypography {
  const DaywellTypography._();

  static const List<String> sansFallback = [
    'Roboto',
    'Noto Sans',
    'Noto Sans Ethiopic',
    'Abyssinica SIL',
    'sans-serif',
  ];

  static const List<String> serifFallback = [
    'Noto Serif',
    'Georgia',
    'Noto Serif Ethiopic',
    'Noto Sans Ethiopic',
    'serif',
  ];

  static const List<String> monoFallback = [
    'JetBrains Mono',
    'Roboto Mono',
    'Noto Sans Mono',
    'Noto Sans Ethiopic',
    'monospace',
  ];

  static String? fontFamilyForRole(String role) {
    switch (role) {
      case 'serif':
        return 'serif';
      case 'mono':
        return 'monospace';
      case 'sans':
      default:
        return null;
    }
  }

  static List<String> fontFallbackForRole(String role) {
    switch (role) {
      case 'serif':
        return serifFallback;
      case 'mono':
        return monoFallback;
      case 'sans':
      default:
        return sansFallback;
    }
  }

  static TextStyle fromToken(
    SharedTextStyleToken token, {
    Color? color,
  }) {
    return token
        .toTextStyle(
          color: color,
          fontFamily: fontFamilyForRole(token.fontFamilyRole),
        )
        .copyWith(
          fontFamilyFallback: fontFallbackForRole(token.fontFamilyRole),
        );
  }

  static TextStyle numericHero({Color? color}) {
    return fromToken(SharedDesignTokens.typeNumericHero, color: color);
  }

  static TextStyle numericBody({Color? color}) {
    return fromToken(SharedDesignTokens.typeNumericBody, color: color);
  }

  static TextStyle mono({Color? color}) {
    return fromToken(SharedDesignTokens.typeMono, color: color);
  }

  static TextStyle label({Color? color}) {
    return fromToken(SharedDesignTokens.typeLabel, color: color);
  }

  static TextStyle caption({Color? color}) {
    return fromToken(SharedDesignTokens.typeCaption, color: color);
  }

  static TextTheme buildTextTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final primary = isDark
        ? SharedDesignTokens.textPrimaryDark
        : SharedDesignTokens.textPrimaryLight;
    final secondary = isDark
        ? SharedDesignTokens.textSecondaryDark
        : SharedDesignTokens.textSecondaryLight;

    return TextTheme(
      displayLarge: fromToken(SharedDesignTokens.typeDisplay, color: primary),
      displayMedium: fromToken(SharedDesignTokens.typeDisplay, color: primary),
      displaySmall: fromToken(SharedDesignTokens.typeDisplay, color: primary),
      headlineLarge: fromToken(SharedDesignTokens.typeDisplay, color: primary),
      headlineMedium: fromToken(SharedDesignTokens.typeHeading, color: primary),
      headlineSmall: fromToken(SharedDesignTokens.typeHeading, color: primary),
      titleLarge: fromToken(SharedDesignTokens.typeHeading, color: primary),
      titleMedium: fromToken(SharedDesignTokens.typeTitle, color: primary),
      titleSmall: fromToken(SharedDesignTokens.typeBody, color: primary)
          .copyWith(fontWeight: FontWeight.w600),
      bodyLarge: fromToken(SharedDesignTokens.typeBody, color: primary),
      bodyMedium: fromToken(SharedDesignTokens.typeBody, color: primary),
      bodySmall:
          fromToken(SharedDesignTokens.typeBodyCompact, color: secondary),
      labelLarge: fromToken(SharedDesignTokens.typeBody, color: primary)
          .copyWith(fontWeight: FontWeight.w600),
      labelMedium: fromToken(SharedDesignTokens.typeLabel, color: secondary),
      labelSmall: fromToken(SharedDesignTokens.typeCaption, color: secondary),
    );
  }
}
