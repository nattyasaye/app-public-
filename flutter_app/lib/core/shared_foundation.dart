// SHARED FOUNDATION DESIGN TOKENS (Single Source of Truth)
// Generated automatically from /shared_foundation/*.json
// DO NOT EDIT DIRECTLY. Run "npm run sync-foundation" to regenerate.
// Re-exports pure-Dart CanonicalSeedDatabase, SharedBusinessRules (ETB),
// and KnownSeedIds.

import 'package:flutter/material.dart';

export 'shared_foundation_core.dart';

class SharedTextStyleToken {
  final double fontSize;
  final double lineHeight;
  final FontWeight fontWeight;
  final double letterSpacing;
  final String fontFamilyRole;
  final bool tabularFigures;

  const SharedTextStyleToken({
    required this.fontSize,
    required this.lineHeight,
    required this.fontWeight,
    required this.letterSpacing,
    required this.fontFamilyRole,
    this.tabularFigures = false,
  });

  double get height => lineHeight / fontSize;

  TextStyle toTextStyle({Color? color, String? fontFamily}) {
    return TextStyle(
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: color,
      fontFamily: fontFamily,
      fontFeatures:
          tabularFigures ? const [FontFeature.tabularFigures()] : null,
    );
  }
}

class SharedDesignTokens {
  static const String tokenVersion = '1.1.0';

  // Brand Primary
  static const Color primaryEmerald = Color(0xFF1B4D3E);
  static const Color primaryEmeraldDark = Color(0xFF153E32);
  static const Color primaryEmeraldLight = Color(0xFF245E4D);
  static const Color primaryDarkMode = Color(0xFF81C784);
  static const Color onPrimaryLight = Color(0xFFFFFFFF);
  static const Color onPrimaryDark = Color(0xFF0E241C);

  // Brand Secondary
  static const Color secondaryMint = Color(0xFFE0EFE8);
  static const Color secondaryMintDark = Color(0xFF1D382E);
  static const Color secondaryMintLight = Color(0xFFF0F7F4);
  static const Color onSecondaryLight = Color(0xFF1B4D3E);
  static const Color onSecondaryDark = Color(0xFF81C784);

  // Surfaces & Borders
  static const Color canvasLight = Color(0xFFFAF9F5);
  static const Color canvasDark = Color(0xFF121816);
  static const Color surfaceSubtleLight = Color(0xFFF2F0E8);
  static const Color surfaceSubtleDark = Color(0xFF161E1B);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF1A2320);
  static const Color elevatedLight = Color(0xFFFFFFFF);
  static const Color elevatedDark = Color(0xFF212C28);
  static const Color borderLight = Color(0xFFE5E7EB);
  static const Color borderDark = Color(0xFF2B3A34);
  static const Color dividerLight = Color(0xFFECEAE3);
  static const Color dividerDark = Color(0xFF222E29);

  // Text Hierarchy
  static const Color textPrimaryLight = Color(0xFF111827);
  static const Color textPrimaryDark = Color(0xFFF9FAFB);
  static const Color textSecondaryLight = Color(0xFF4B5563);
  static const Color textSecondaryDark = Color(0xFFCBD5E1);
  static const Color textMutedLight = Color(0xFF6B7280);
  static const Color textMutedDark = Color(0xFF9CA3AF);
  static const Color textDisabledLight = Color(0xFF9CA3AF);
  static const Color textDisabledDark = Color(0xFF5C6B64);

  // Semantic Roles (Finance & System States)
  static const Color semanticIncome = Color(0xFF10B981);
  static const Color onSemanticIncome = Color(0xFF052E16);
  static const Color semanticIncomeContainerLight = Color(0xFFECFDF5);
  static const Color onSemanticIncomeContainerLight = Color(0xFF065F46);
  static const Color semanticIncomeContainerDark = Color(0xFF0D3326);
  static const Color onSemanticIncomeContainerDark = Color(0xFF6EE7B7);
  static const Color semanticExpense = Color(0xFFEF4444);
  static const Color onSemanticExpense = Color(0xFF090D16);
  static const Color semanticExpenseContainerLight = Color(0xFFFEF2F2);
  static const Color onSemanticExpenseContainerLight = Color(0xFF991B1B);
  static const Color semanticExpenseContainerDark = Color(0xFF3B1517);
  static const Color onSemanticExpenseContainerDark = Color(0xFFFCA5A5);
  static const Color semanticTransfer = Color(0xFF0D9488);
  static const Color onSemanticTransfer = Color(0xFF021615);
  static const Color semanticTransferContainerLight = Color(0xFFF0FDFA);
  static const Color onSemanticTransferContainerLight = Color(0xFF115E59);
  static const Color semanticTransferContainerDark = Color(0xFF0E3330);
  static const Color onSemanticTransferContainerDark = Color(0xFF5EEAD4);
  static const Color semanticSuccess = Color(0xFF15803D);
  static const Color onSemanticSuccess = Color(0xFFFFFFFF);
  static const Color semanticSuccessContainerLight = Color(0xFFF0FDF4);
  static const Color onSemanticSuccessContainerLight = Color(0xFF166534);
  static const Color semanticSuccessContainerDark = Color(0xFF11331F);
  static const Color onSemanticSuccessContainerDark = Color(0xFF86EFAC);
  static const Color semanticError = Color(0xFFDC2626);
  static const Color onSemanticError = Color(0xFFFFFFFF);
  static const Color semanticErrorContainerLight = Color(0xFFFEE2E2);
  static const Color onSemanticErrorContainerLight = Color(0xFF7F1D1D);
  static const Color semanticErrorContainerDark = Color(0xFF451215);
  static const Color onSemanticErrorContainerDark = Color(0xFFFECACA);
  static const Color semanticWarning = Color(0xFFF59E0B);
  static const Color onSemanticWarning = Color(0xFF111827);
  static const Color semanticWarningContainerLight = Color(0xFFFFFBEB);
  static const Color onSemanticWarningContainerLight = Color(0xFF92400E);
  static const Color semanticWarningContainerDark = Color(0xFF36250B);
  static const Color onSemanticWarningContainerDark = Color(0xFFFCD34D);
  static const Color semanticInfo = Color(0xFF3B82F6);
  static const Color onSemanticInfo = Color(0xFF0B1120);
  static const Color semanticInfoContainerLight = Color(0xFFEFF6FF);
  static const Color onSemanticInfoContainerLight = Color(0xFF1E40AF);
  static const Color semanticInfoContainerDark = Color(0xFF132645);
  static const Color onSemanticInfoContainerDark = Color(0xFF93C5FD);

  // Typography Families
  static const String fontFamilySerif = 'Newsreader, Georgia, serif';
  static const String fontFamilySans =
      'Inter, -apple-system, BlinkMacSystemFont, sans-serif';
  static const String fontFamilyMono = 'JetBrains Mono, monospace';

  // Typography Scale
  static const SharedTextStyleToken typeDisplay = SharedTextStyleToken(
    fontSize: 28.0,
    lineHeight: 36.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    fontFamilyRole: 'serif',
    tabularFigures: false,
  );

  static const SharedTextStyleToken typeHeading = SharedTextStyleToken(
    fontSize: 22.0,
    lineHeight: 28.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    fontFamilyRole: 'serif',
    tabularFigures: false,
  );

  static const SharedTextStyleToken typeTitle = SharedTextStyleToken(
    fontSize: 17.0,
    lineHeight: 24.0,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    fontFamilyRole: 'sans',
    tabularFigures: false,
  );

  static const SharedTextStyleToken typeBody = SharedTextStyleToken(
    fontSize: 14.0,
    lineHeight: 20.0,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.0,
    fontFamilyRole: 'sans',
    tabularFigures: false,
  );

  static const SharedTextStyleToken typeBodyCompact = SharedTextStyleToken(
    fontSize: 13.0,
    lineHeight: 18.0,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.0,
    fontFamilyRole: 'sans',
    tabularFigures: false,
  );

  static const SharedTextStyleToken typeLabel = SharedTextStyleToken(
    fontSize: 12.0,
    lineHeight: 16.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    fontFamilyRole: 'sans',
    tabularFigures: false,
  );

  static const SharedTextStyleToken typeCaption = SharedTextStyleToken(
    fontSize: 11.0,
    lineHeight: 14.0,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    fontFamilyRole: 'sans',
    tabularFigures: false,
  );

  static const SharedTextStyleToken typeNumericHero = SharedTextStyleToken(
    fontSize: 32.0,
    lineHeight: 38.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    fontFamilyRole: 'sans',
    tabularFigures: true,
  );

  static const SharedTextStyleToken typeNumericBody = SharedTextStyleToken(
    fontSize: 15.0,
    lineHeight: 20.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.0,
    fontFamilyRole: 'sans',
    tabularFigures: true,
  );

  static const SharedTextStyleToken typeMono = SharedTextStyleToken(
    fontSize: 12.0,
    lineHeight: 16.0,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.0,
    fontFamilyRole: 'mono',
    tabularFigures: true,
  );

  // Spacing Scale
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingCompact = 12.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;

  // Corner Radii
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radiusSheet = 24.0;
  static const double radiusFull = 9999.0;

  // Elevation Levels
  static const double elevationNone = 0.0;
  static const double elevationLow = 1.0;
  static const double elevationMedium = 3.0;
  static const double elevationHigh = 6.0;

  // Responsive Breakpoints & Content Caps
  static const double breakpointMedium = 600.0;
  static const double breakpointExpanded = 840.0;
  static const double breakpointMaxContentWidth = 720.0;
  static const double breakpointMaxWideWidth = 1120.0;
}
