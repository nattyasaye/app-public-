import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/core/shared_foundation.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/main.dart';
import 'package:personal_management_app/ui/widgets/daywell_theme_showcase.dart';

double _relativeLuminance(Color color) {
  double linearize(int channel) {
    final c = channel / 255.0;
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linearize(color.red) +
      0.7152 * linearize(color.green) +
      0.0722 * linearize(color.blue);
}

double _contrastRatio(Color fg, Color bg) {
  final l1 = _relativeLuminance(fg);
  final l2 = _relativeLuminance(bg);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  group('DaywellTheme & ThemeMode Construction', () {
    test('Light and Dark ThemeData use Material 3 and canonical design tokens',
        () {
      final light = DaywellTheme.light;
      final dark = DaywellTheme.dark;

      expect(light.useMaterial3, isTrue);
      expect(dark.useMaterial3, isTrue);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);

      expect(light.colorScheme.primary, SharedDesignTokens.primaryEmerald);
      expect(light.colorScheme.onPrimary, SharedDesignTokens.onPrimaryLight);
      expect(
        light.colorScheme.primaryContainer,
        SharedDesignTokens.secondaryMint,
      );
      expect(light.scaffoldBackgroundColor, SharedDesignTokens.canvasLight);
      expect(light.cardColor, SharedDesignTokens.cardLight);

      expect(dark.colorScheme.primary, SharedDesignTokens.primaryDarkMode);
      expect(dark.colorScheme.onPrimary, SharedDesignTokens.onPrimaryDark);
      expect(
        dark.colorScheme.primaryContainer,
        SharedDesignTokens.secondaryMintDark,
      );
      expect(dark.scaffoldBackgroundColor, SharedDesignTokens.canvasDark);
      expect(dark.cardColor, SharedDesignTokens.cardDark);

      expect(DaywellTheme.forBrightness(Brightness.light), same(light));
      expect(DaywellTheme.forBrightness(Brightness.dark), same(dark));

      expect(
        DaywellTheme.resolve(
          ThemeMode.system,
          platformBrightness: Brightness.dark,
        ),
        same(dark),
      );
      expect(
        DaywellTheme.resolve(
          ThemeMode.light,
          platformBrightness: Brightness.dark,
        ),
        same(light),
      );
      expect(
        DaywellTheme.resolve(
          ThemeMode.dark,
          platformBrightness: Brightness.light,
        ),
        same(dark),
      );
    });

    test('DaywellApp defaults to ThemeMode.system and accepts custom ThemeMode',
        () {
      const defaultApp = DaywellApp();
      const darkApp = DaywellApp(themeMode: ThemeMode.dark);
      const lightApp = DaywellApp(themeMode: ThemeMode.light);

      expect(defaultApp.themeMode, ThemeMode.system);
      expect(darkApp.themeMode, ThemeMode.dark);
      expect(lightApp.themeMode, ThemeMode.light);
    });
  });

  group('DaywellSemanticColors ThemeExtension', () {
    test('Both themes register DaywellSemanticColors with canonical values',
        () {
      final lightExt = DaywellTheme.light.extension<DaywellSemanticColors>();
      final darkExt = DaywellTheme.dark.extension<DaywellSemanticColors>();

      expect(lightExt, isNotNull);
      expect(darkExt, isNotNull);

      expect(lightExt!.income, SharedDesignTokens.semanticIncome);
      expect(
        lightExt.incomeContainer,
        SharedDesignTokens.semanticIncomeContainerLight,
      );
      expect(
        lightExt.onIncomeContainer,
        SharedDesignTokens.onSemanticIncomeContainerLight,
      );
      expect(lightExt.expense, SharedDesignTokens.semanticExpense);
      expect(lightExt.transfer, SharedDesignTokens.semanticTransfer);
      expect(lightExt.success, SharedDesignTokens.semanticSuccess);
      expect(lightExt.error, SharedDesignTokens.semanticError);
      expect(lightExt.warning, SharedDesignTokens.semanticWarning);
      expect(lightExt.info, SharedDesignTokens.semanticInfo);
      expect(lightExt.canvas, SharedDesignTokens.canvasLight);

      expect(
        darkExt!.incomeContainer,
        SharedDesignTokens.semanticIncomeContainerDark,
      );
      expect(
        darkExt.onIncomeContainer,
        SharedDesignTokens.onSemanticIncomeContainerDark,
      );
      expect(
        darkExt.expenseContainer,
        SharedDesignTokens.semanticExpenseContainerDark,
      );
      expect(
        darkExt.onExpenseContainer,
        SharedDesignTokens.onSemanticExpenseContainerDark,
      );
      expect(darkExt.canvas, SharedDesignTokens.canvasDark);
    });

    test('copyWith and lerp behave accurately', () {
      const light = DaywellSemanticColors.light();
      const dark = DaywellSemanticColors.dark();

      final copied = light.copyWith(
        income: SharedDesignTokens.primaryEmerald,
        canvas: SharedDesignTokens.cardLight,
      );
      expect(copied.income, SharedDesignTokens.primaryEmerald);
      expect(copied.canvas, SharedDesignTokens.cardLight);
      expect(copied.expense, light.expense);

      final lerpedStart = light.lerp(dark, 0.0);
      final lerpedMid = light.lerp(dark, 0.5);
      final lerpedEnd = light.lerp(dark, 1.0);

      expect(lerpedStart.canvas, light.canvas);
      expect(lerpedEnd.canvas, dark.canvas);
      expect(
        lerpedMid.canvas,
        Color.lerp(light.canvas, dark.canvas, 0.5),
      );
      expect(
        lerpedMid.incomeContainer,
        Color.lerp(light.incomeContainer, dark.incomeContainer, 0.5),
      );
      expect(light.lerp(null, 0.5), same(light));
    });

    testWidgets('BuildContext.daywellColors resolves registered extension',
        (tester) async {
      late DaywellSemanticColors captured;

      await tester.pumpWidget(
        MaterialApp(
          theme: DaywellTheme.light,
          darkTheme: DaywellTheme.dark,
          themeMode: ThemeMode.dark,
          home: Builder(
            builder: (context) {
              captured = context.daywellColors;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(captured.canvas, SharedDesignTokens.canvasDark);
      expect(
        captured.errorContainer,
        SharedDesignTokens.semanticErrorContainerDark,
      );
    });
  });

  group('DaywellTypography & Ethiopic Font Fallback', () {
    test('Maps canonical typography tokens and Ethiopic fallbacks cleanly', () {
      final lightText = DaywellTheme.light.textTheme;
      final darkText = DaywellTheme.dark.textTheme;

      expect(
        lightText.displaySmall!.fontSize,
        SharedDesignTokens.typeDisplay.fontSize,
      );
      expect(
        lightText.headlineMedium!.fontSize,
        SharedDesignTokens.typeHeading.fontSize,
      );
      expect(
        lightText.titleMedium!.fontSize,
        SharedDesignTokens.typeTitle.fontSize,
      );
      expect(
        lightText.bodyMedium!.fontSize,
        SharedDesignTokens.typeBody.fontSize,
      );
      expect(
        lightText.bodySmall!.fontSize,
        SharedDesignTokens.typeBodyCompact.fontSize,
      );
      expect(
        lightText.labelMedium!.fontSize,
        SharedDesignTokens.typeLabel.fontSize,
      );
      expect(
        lightText.labelSmall!.fontSize,
        SharedDesignTokens.typeCaption.fontSize,
      );

      expect(lightText.bodyMedium!.color, SharedDesignTokens.textPrimaryLight);
      expect(darkText.bodyMedium!.color, SharedDesignTokens.textPrimaryDark);
      expect(lightText.bodySmall!.color, SharedDesignTokens.textSecondaryLight);
      expect(darkText.bodySmall!.color, SharedDesignTokens.textSecondaryDark);

      // Ethiopic fallback present without forcing Ethiopic-only primary font
      final rawTextTheme = DaywellTypography.buildTextTheme(Brightness.light);
      expect(rawTextTheme.bodyMedium!.fontFamily, isNull);
      expect(
        lightText.bodyMedium!.fontFamily,
        anyOf(isNull, equals('Roboto')),
      );
      expect(
        lightText.bodyMedium!.fontFamilyFallback,
        contains('Noto Sans Ethiopic'),
      );
      expect(
        lightText.displaySmall!.fontFamilyFallback,
        contains('Noto Serif Ethiopic'),
      );

      final hero = DaywellTypography.numericHero();
      expect(hero.fontSize, SharedDesignTokens.typeNumericHero.fontSize);
      expect(hero.fontFeatures, const [FontFeature.tabularFigures()]);

      final bodyNum = DaywellTypography.numericBody();
      expect(bodyNum.fontSize, SharedDesignTokens.typeNumericBody.fontSize);
      expect(bodyNum.fontFeatures, const [FontFeature.tabularFigures()]);

      final mono = DaywellTypography.mono();
      expect(mono.fontSize, SharedDesignTokens.typeMono.fontSize);
      expect(mono.fontFamilyFallback, contains('Noto Sans Ethiopic'));
    });
  });

  group('Material Component Themes & Accessibility Contrast', () {
    test('Registers all centralized Material component themes', () {
      for (final theme in [DaywellTheme.light, DaywellTheme.dark]) {
        expect(theme.appBarTheme.elevation, SharedDesignTokens.elevationNone);
        expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
        expect(theme.elevatedButtonTheme.style, isNotNull);
        expect(theme.filledButtonTheme.style, isNotNull);
        expect(theme.outlinedButtonTheme.style, isNotNull);
        expect(theme.textButtonTheme.style, isNotNull);
        expect(theme.inputDecorationTheme.filled, isTrue);
        expect(theme.dialogTheme.shape, isA<RoundedRectangleBorder>());
        expect(theme.bottomSheetTheme.shape, isA<RoundedRectangleBorder>());
        expect(theme.navigationBarTheme.height, isNull);
        expect(theme.chipTheme.backgroundColor, isNotNull);
        expect(
          theme.chipTheme.selectedColor,
          theme.colorScheme.primaryContainer,
        );
        expect(theme.dividerTheme.thickness, 1.0);
        expect(theme.popupMenuTheme.shape, isA<RoundedRectangleBorder>());
        expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      }
    });

    test('Foreground/background contrast meets WCAG AA requirements', () {
      for (final theme in [DaywellTheme.light, DaywellTheme.dark]) {
        final cs = theme.colorScheme;
        final ext = theme.extension<DaywellSemanticColors>()!;

        final textPairs = <(String, Color, Color)>[
          ('onSurface / canvas', cs.onSurface, ext.canvas),
          ('onSurface / card', cs.onSurface, ext.card),
          ('onSurfaceVariant / canvas', cs.onSurfaceVariant, ext.canvas),
          ('onSurfaceVariant / card', cs.onSurfaceVariant, ext.card),
          ('textSecondary / canvas', ext.textSecondary, ext.canvas),
          ('onPrimary / primary', cs.onPrimary, cs.primary),
          (
            'onPrimaryContainer / primaryContainer',
            cs.onPrimaryContainer,
            cs.primaryContainer,
          ),
          ('onError / error', cs.onError, cs.error),
          ('error / card', cs.error, ext.card),
          (
            'onErrorContainer / errorContainer',
            cs.onErrorContainer,
            cs.errorContainer
          ),
          ('onIncome / income', ext.onIncome, ext.income),
          ('onExpense / expense', ext.onExpense, ext.expense),
          ('onTransfer / transfer', ext.onTransfer, ext.transfer),
          ('onSuccess / success', ext.onSuccess, ext.success),
          ('onWarning / warning', ext.onWarning, ext.warning),
          ('onInfo / info', ext.onInfo, ext.info),
          (
            'onIncomeContainer / incomeContainer',
            ext.onIncomeContainer,
            ext.incomeContainer,
          ),
          (
            'onExpenseContainer / expenseContainer',
            ext.onExpenseContainer,
            ext.expenseContainer,
          ),
          (
            'onTransferContainer / transferContainer',
            ext.onTransferContainer,
            ext.transferContainer,
          ),
          (
            'onSuccessContainer / successContainer',
            ext.onSuccessContainer,
            ext.successContainer,
          ),
          (
            'onErrorContainer / errorContainer (ext)',
            ext.onErrorContainer,
            ext.errorContainer,
          ),
          (
            'onWarningContainer / warningContainer',
            ext.onWarningContainer,
            ext.warningContainer,
          ),
          (
            'onInfoContainer / infoContainer',
            ext.onInfoContainer,
            ext.infoContainer,
          ),
          (
            'chip label / chip background',
            theme.chipTheme.labelStyle!.color!,
            theme.chipTheme.backgroundColor!,
          ),
          (
            'chip selected label / chip selected background',
            theme.chipTheme.secondaryLabelStyle!.color!,
            theme.chipTheme.selectedColor!,
          ),
        ];

        for (final (label, fg, bg) in textPairs) {
          final ratio = _contrastRatio(fg, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                '${theme.brightness.name} $label contrast ${ratio.toStringAsFixed(2)}:1 < 4.5:1',
          );
        }

        // Non-text interactive outline contrast >= 3.0:1
        final outlineOnCard = _contrastRatio(cs.outline, ext.card);
        expect(
          outlineOnCard,
          greaterThanOrEqualTo(3.0),
          reason:
              '${theme.brightness.name} outline on card ${outlineOnCard.toStringAsFixed(2)}:1 < 3.0:1',
        );
      }
    });
  });

  group('DaywellThemeShowcase Widget & Text Scale Verification', () {
    Future<void> pumpShowcase(
      WidgetTester tester, {
      required ThemeMode themeMode,
      double textScale = 1.0,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: DaywellTheme.light,
          darkTheme: DaywellTheme.dark,
          themeMode: themeMode,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            );
          },
          home: const DaywellThemeShowcase(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Renders cleanly in light theme at 1.0x text scale',
        (tester) async {
      await pumpShowcase(tester, themeMode: ThemeMode.light, textScale: 1.0);

      expect(tester.takeException(), isNull);
      expect(find.text('Daywell Theme Showcase'), findsOneWidget);
      expect(find.textContaining('Brightness: light'), findsOneWidget);
      expect(find.textContaining('ቀንዎን በአግባቡ ያደራጁ'), findsOneWidget);
      expect(find.text('1,250.00 ETB'), findsOneWidget);
    });

    testWidgets('Renders cleanly in dark theme at 1.0x text scale',
        (tester) async {
      await pumpShowcase(tester, themeMode: ThemeMode.dark, textScale: 1.0);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Brightness: dark'), findsOneWidget);
      expect(find.text('Primary'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
      expect(find.text('Expense'), findsOneWidget);
      expect(find.text('Transfer'), findsOneWidget);
    });

    testWidgets(
        'Handles enlarged 2.0x text scaling without layout overflow in light and dark themes',
        (tester) async {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await pumpShowcase(tester, themeMode: mode, textScale: 2.0);
        expect(tester.takeException(), isNull);

        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('Interactive controls, dialog, snackbar, and input work',
        (tester) async {
      await pumpShowcase(tester, themeMode: ThemeMode.light, textScale: 1.0);

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Open Dialog'),
        200.0,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Theme Dialog Preview'), findsOneWidget);
      expect(find.textContaining('መረጃው በትክክል ተቀምጧል።'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Theme Dialog Preview'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Show SnackBar'),
        200.0,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Show SnackBar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Theme SnackBar preview — ተግባሩ ተጠናቋል።'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byType(TextField).first,
        200.0,
        scrollable: scrollable,
      );
      await tester.enterText(
        find.byType(TextField).first,
        'ሰላም Daywell',
      );
      expect(find.text('ሰላም Daywell'), findsOneWidget);
    });
  });
}
