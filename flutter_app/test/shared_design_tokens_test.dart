import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/core/shared_foundation.dart';
import 'package:personal_management_app/core/shared_foundation_core.dart'
    as core;

void main() {
  group('SharedDesignTokens & SharedFoundation Native Verification', () {
    test('Token version and color tokens compile with expected ARGB values',
        () {
      expect(SharedDesignTokens.tokenVersion, '1.1.0');
      expect(SharedDesignTokens.primaryEmerald, const Color(0xFF1B4D3E));
      expect(SharedDesignTokens.primaryDarkMode, const Color(0xFF81C784));
      expect(SharedDesignTokens.secondaryMint, const Color(0xFFE0EFE8));
      expect(SharedDesignTokens.canvasLight, const Color(0xFFFAF9F5));
      expect(SharedDesignTokens.canvasDark, const Color(0xFF121816));
      expect(SharedDesignTokens.semanticIncome, const Color(0xFF10B981));
      expect(SharedDesignTokens.semanticExpense, const Color(0xFFEF4444));
      expect(SharedDesignTokens.semanticTransfer, const Color(0xFF0D9488));
    });

    test(
        'Typography tokens resolve TextStyle and tabularFigures FontFeature accurately',
        () {
      expect(SharedDesignTokens.typeDisplay.fontSize, 28.0);
      expect(SharedDesignTokens.typeDisplay.lineHeight, 36.0);
      expect(
        SharedDesignTokens.typeDisplay.height,
        closeTo(36.0 / 28.0, 1e-9),
      );
      expect(SharedDesignTokens.typeDisplay.fontWeight, FontWeight.w700);
      expect(SharedDesignTokens.typeDisplay.tabularFigures, isFalse);

      final displayStyle = SharedDesignTokens.typeDisplay.toTextStyle(
        color: SharedDesignTokens.textPrimaryLight,
      );
      expect(displayStyle.fontFeatures, isNull);
      expect(displayStyle.color, SharedDesignTokens.textPrimaryLight);

      final heroNumericStyle = SharedDesignTokens.typeNumericHero.toTextStyle();
      expect(SharedDesignTokens.typeNumericHero.tabularFigures, isTrue);
      expect(
        heroNumericStyle.fontFeatures,
        const [FontFeature.tabularFigures()],
      );

      final bodyNumericStyle = SharedDesignTokens.typeNumericBody.toTextStyle();
      expect(
        bodyNumericStyle.fontFeatures,
        const [FontFeature.tabularFigures()],
      );

      final monoStyle = SharedDesignTokens.typeMono.toTextStyle();
      expect(
        monoStyle.fontFeatures,
        const [FontFeature.tabularFigures()],
      );
    });

    test('Spacing, radii, elevation, and breakpoints are monotonic doubles',
        () {
      expect(SharedDesignTokens.spacingXs, 4.0);
      expect(SharedDesignTokens.spacingSm, 8.0);
      expect(SharedDesignTokens.spacingCompact, 12.0);
      expect(SharedDesignTokens.spacingMd, 16.0);
      expect(SharedDesignTokens.spacingLg, 24.0);
      expect(SharedDesignTokens.spacingXl, 32.0);

      expect(SharedDesignTokens.radiusSm, 8.0);
      expect(SharedDesignTokens.radiusSheet, 24.0);
      expect(SharedDesignTokens.radiusFull, 9999.0);

      expect(SharedDesignTokens.elevationNone, 0.0);
      expect(SharedDesignTokens.elevationHigh, 6.0);

      expect(SharedDesignTokens.breakpointMedium, 600.0);
      expect(SharedDesignTokens.breakpointExpanded, 840.0);
      expect(SharedDesignTokens.breakpointMaxContentWidth, 720.0);
      expect(SharedDesignTokens.breakpointMaxWideWidth, 1120.0);
    });

    test('Pure-Dart core foundation exports rules and clean seed state', () {
      expect(core.SharedBusinessRules.currencyCode, 'ETB');
      expect(core.CanonicalSeedDatabase.schemaVersion, 5);
      final seedState = core.CanonicalSeedDatabase.state;
      expect(seedState['accounts'], isEmpty);
      expect((seedState['categories'] as List).length, 11);
      expect(core.KnownSeedIds.isKnownSeedId('acc-cbe'), isTrue);
      expect(core.KnownSeedIds.isKnownSeedId('user-real-acc'), isFalse);

      // Re-exported through shared_foundation.dart for UI compatibility
      expect(SharedBusinessRules.currencyCode, 'ETB');
      expect(CanonicalSeedDatabase.schemaVersion, 5);
    });
  });
}
