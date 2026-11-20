import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/ui/widgets/daywell_theme_showcase.dart';
import 'package:personal_management_app/ui/widgets/shared_ui_widgets.dart';

Widget _wrapWithTheme(
  Widget child, {
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1.0,
  Size? surfaceSize,
}) {
  Widget content = Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );

  if (surfaceSize != null) {
    content = Center(
      child: SizedBox(
        width: surfaceSize.width,
        height: surfaceSize.height,
        child: content,
      ),
    );
  }

  return MaterialApp(
    theme: DaywellTheme.light,
    darkTheme: DaywellTheme.dark,
    themeMode: themeMode,
    builder: (context, widget) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: widget!,
    ),
    home: content,
  );
}

void main() {
  group('DaywellSectionContainer', () {
    testWidgets(
      'Composes optional header, subtitle, surface card, and footer across themes',
      (tester) async {
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          var actionCount = 0;

          await tester.pumpWidget(
            _wrapWithTheme(
              themeMode: mode,
              Column(
                children: [
                  DaywellSectionContainer(
                    title: 'Upcoming Commitments',
                    count: 3,
                    actionLabel: 'See All',
                    onActionPressed: () => actionCount++,
                    subtitle: 'Scheduled for today and this week.',
                    useCard: true,
                    footer: const Text('+ 2 more items'),
                    child: const Text('Card body item'),
                  ),
                  const SizedBox(height: 16),
                  const DaywellSectionContainer(
                    useCard: false,
                    child: Text('Flat headerless section'),
                  ),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Upcoming Commitments'), findsOneWidget);
          expect(find.text('3'), findsOneWidget);
          expect(
              find.text('Scheduled for today and this week.'), findsOneWidget);
          expect(find.text('Card body item'), findsOneWidget);
          expect(find.text('+ 2 more items'), findsOneWidget);
          expect(find.text('Flat headerless section'), findsOneWidget);
          expect(find.byType(DaywellCard), findsOneWidget);

          await tester.tap(find.text('See All'));
          await tester.pump();
          expect(actionCount, 1);
        }
      },
    );

    testWidgets(
      'Renders without overflow at 2.0x text scale on 320px width and preserves header semantics',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _wrapWithTheme(
              textScale: 2.0,
              surfaceSize: const Size(320, 640),
              DaywellSectionContainer(
                title: 'Long Bilingual Section Header · የዕለት ተግባራት',
                count: 14,
                actionLabel: 'Manage All',
                onActionPressed: () {},
                subtitle:
                    'Supporting description that wraps cleanly on narrow widths.',
                useCard: true,
                child: const Text('Inside container'),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          final headerNode = tester.getSemantics(
            find.text('Long Bilingual Section Header · የዕለት ተግባራት'),
          );
          expect(headerNode.hasFlag(SemanticsFlag.isHeader), isTrue);
        } finally {
          handle.dispose();
        }
      },
    );
  });

  group('DaywellContentState', () {
    testWidgets(
      'Switches cleanly across loading, empty, error, and lazy content states',
      (tester) async {
        DaywellContentStatus status = DaywellContentStatus.loading;
        var emptyActionCalls = 0;
        var retryCalls = 0;
        var contentBuildCalls = 0;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return _wrapWithTheme(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final next in DaywellContentStatus.values)
                          ChoiceChip(
                            label: Text('state-${next.name}'),
                            selected: status == next,
                            onSelected: (_) => setState(() => status = next),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DaywellContentState(
                      status: status,
                      loadingLabel: 'Fetching records...',
                      emptyIcon: Icons.task_alt,
                      emptyMessage: 'No tasks match filter',
                      emptySubtitle: 'Create one to begin.',
                      emptyActionLabel: 'Add Task',
                      onEmptyAction: () => emptyActionCalls++,
                      errorTitle: 'Load Failed',
                      errorMessage: 'Local store could not be read.',
                      retryLabel: 'Try Again',
                      onRetry: () => retryCalls++,
                      contentBuilder: (_) {
                        contentBuildCalls++;
                        return const Text('Loaded Items Ready');
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        );

        expect(find.byType(DaywellLoadingIndicator), findsOneWidget);
        expect(find.text('Fetching records...'), findsOneWidget);
        expect(contentBuildCalls, 0);

        await tester.tap(find.text('state-empty'));
        await tester.pumpAndSettle();
        expect(find.byType(DaywellEmptyState), findsOneWidget);
        expect(find.text('No tasks match filter'), findsOneWidget);
        await tester.tap(find.text('Add Task'));
        await tester.pump();
        expect(emptyActionCalls, 1);

        await tester.tap(find.text('state-error'));
        await tester.pumpAndSettle();
        expect(find.byType(DaywellStatusBanner), findsOneWidget);
        expect(find.text('Local store could not be read.'), findsOneWidget);
        await tester.tap(find.text('Try Again'));
        await tester.pump();
        expect(retryCalls, 1);

        await tester.tap(find.text('state-content'));
        await tester.pumpAndSettle();
        expect(find.text('Loaded Items Ready'), findsOneWidget);
        expect(contentBuildCalls, 1);
      },
    );

    testWidgets(
      'Renders empty and error states in dark mode at 2.0x text scale on 320px width',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          for (final status in [
            DaywellContentStatus.loading,
            DaywellContentStatus.empty,
            DaywellContentStatus.error,
          ]) {
            await tester.pumpWidget(
              _wrapWithTheme(
                themeMode: ThemeMode.dark,
                textScale: 2.0,
                surfaceSize: const Size(320, 640),
                DaywellContentState(
                  status: status,
                  loadingLabel: 'Loading...',
                  emptyMessage: 'Empty list at large text scale',
                  emptyActionLabel: 'Create',
                  onEmptyAction: () {},
                  errorTitle: 'Error',
                  errorMessage: 'Failed to load entries on narrow screen.',
                  onRetry: () {},
                  child: const SizedBox.shrink(),
                ),
              ),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);

            if (status == DaywellContentStatus.loading) {
              final loadingData = tester
                  .getSemantics(find.byType(DaywellLoadingIndicator))
                  .getSemanticsData();
              expect(loadingData.hasFlag(SemanticsFlag.isLiveRegion), isFalse);
            } else if (status == DaywellContentStatus.error) {
              final errorData = tester
                  .getSemantics(find.byType(DaywellStatusBanner))
                  .getSemanticsData();
              expect(errorData.hasFlag(SemanticsFlag.isLiveRegion), isFalse);
            }
          }
        } finally {
          handle.dispose();
        }
      },
    );

    testWidgets(
      'Omits empty or whitespace-only action labels instead of rendering blank buttons',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithTheme(
            Column(
              children: [
                DaywellContentState(
                  status: DaywellContentStatus.empty,
                  emptyMessage: 'Empty state',
                  emptyActionLabel: '   ',
                  onEmptyAction: () {},
                ),
                DaywellContentState(
                  status: DaywellContentStatus.error,
                  errorMessage: 'Error state',
                  retryLabel: '  ',
                  onRetry: () {},
                ),
              ],
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(DaywellButton), findsNothing);
        expect(find.byType(TextButton), findsNothing);
      },
    );
  });

  group('DaywellSearchFilterBar', () {
    testWidgets(
      'Forwards search input, clear button, filter selection, and reset action',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        String query = '';
        String selectedFilter = 'all';
        var searchClearedCount = 0;
        var filtersClearedCount = 0;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return _wrapWithTheme(
                DaywellSearchFilterBar(
                  searchController: controller,
                  searchHintText: 'Search ledger...',
                  onSearchChanged: (value) => setState(() => query = value),
                  onSearchCleared: () {
                    searchClearedCount++;
                    setState(() => query = '');
                  },
                  trailingAction: DaywellIconButton(
                    icon: Icons.tune,
                    tooltip: 'Advanced filters',
                    onPressed: () {},
                  ),
                  filterControls: [
                    for (final option in ['all', 'income', 'expense'])
                      ChoiceChip(
                        label: Text(option),
                        selected: selectedFilter == option,
                        onSelected: (_) =>
                            setState(() => selectedFilter = option),
                      ),
                  ],
                  hasActiveFilters: query.isNotEmpty || selectedFilter != 'all',
                  activeSummary: 'Showing $selectedFilter results',
                  clearFiltersLabel: 'Clear filters',
                  onClearFilters: () {
                    filtersClearedCount++;
                    controller.clear();
                    setState(() {
                      query = '';
                      selectedFilter = 'all';
                    });
                  },
                ),
              );
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'coffee');
        await tester.pump();
        expect(query, 'coffee');
        expect(find.text('Clear filters'), findsOneWidget);

        await tester.tap(find.text('income'));
        await tester.pump();
        expect(selectedFilter, 'income');
        expect(find.text('Showing income results'), findsOneWidget);

        await tester.tap(find.byTooltip('Clear search'));
        await tester.pump();
        expect(searchClearedCount, 1);
        expect(query, '');

        await tester.enterText(find.byType(TextField), 'rent');
        await tester.pump();
        await tester.tap(find.text('Clear filters'));
        await tester.pump();
        expect(filtersClearedCount, 1);
        expect(controller.text, '');
        expect(selectedFilter, 'all');
        expect(find.text('Clear filters'), findsNothing);
      },
    );

    testWidgets(
      'Handles horizontal scroll layout, 320px width, 2.0x text scale, dark mode, and semantics',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          for (final layout in DaywellFilterLayout.values) {
            await tester.pumpWidget(
              _wrapWithTheme(
                themeMode: ThemeMode.dark,
                textScale: 2.0,
                surfaceSize: const Size(320, 640),
                DaywellSearchFilterBar(
                  searchHintText: 'Search notes or መዝገብ...',
                  filterLayout: layout,
                  trailingAction: DaywellIconButton(
                    icon: Icons.add,
                    tooltip: 'Add filter',
                    onPressed: () {},
                  ),
                  filterControls: const [
                    Chip(label: Text('Pinned')),
                    Chip(label: Text('Tasks')),
                    Chip(label: Text('Finance')),
                  ],
                  hasActiveFilters: true,
                  activeSummary: '3 matching items · Active category filter',
                  onClearFilters: () {},
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            final searchSemantics = tester.getSemantics(
              find.descendant(
                of: find.byType(DaywellSearchFilterBar),
                matching: find.byType(EditableText),
              ),
            );
            expect(searchSemantics.hasFlag(SemanticsFlag.isTextField), isTrue);
            final clearSemantics = tester.getSemantics(
              find.widgetWithText(DaywellButton, 'Clear filters'),
            );
            expect(clearSemantics.hasFlag(SemanticsFlag.isButton), isTrue);
          }
        } finally {
          handle.dispose();
        }
      },
    );
  });

  group('DaywellConfirmationDialog', () {
    testWidgets(
      'Resolves true on confirm, false on cancel, and false on barrier dismiss',
      (tester) async {
        bool? lastResult;

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            darkTheme: DaywellTheme.dark,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DaywellButton(
                        label: 'Open Destructive',
                        onPressed: () async {
                          lastResult = await DaywellConfirmationDialog.show(
                            context,
                            title: 'Delete Transaction?',
                            message: 'This action cannot be undone.',
                            icon: Icons.delete_outline,
                            confirmLabel: 'Confirm Delete',
                            isDestructive: true,
                          );
                        },
                      ),
                      DaywellButton(
                        label: 'Open Standard',
                        onPressed: () async {
                          lastResult = await DaywellConfirmationDialog.show(
                            context,
                            title: 'Archive Account?',
                            message: 'Account history will remain intact.',
                            icon: Icons.archive_outlined,
                            confirmLabel: 'Archive',
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Destructive'));
        await tester.pumpAndSettle();
        expect(find.text('Delete Transaction?'), findsOneWidget);
        await tester.tap(find.text('Confirm Delete'));
        await tester.pumpAndSettle();
        expect(lastResult, isTrue);

        await tester.tap(find.text('Open Standard'));
        await tester.pumpAndSettle();
        expect(find.text('Archive Account?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(lastResult, isFalse);

        lastResult = null;
        await tester.tap(find.text('Open Standard'));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(lastResult, isFalse);
      },
    );

    testWidgets(
      'Renders safely at 2.0x text scale on 320px width in dark mode with clean semantics',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: DaywellTheme.light,
              darkTheme: DaywellTheme.dark,
              themeMode: ThemeMode.dark,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2.0),
                ),
                child: child!,
              ),
              home: SizedBox(
                width: 320,
                height: 640,
                child: Scaffold(
                  body: Builder(
                    builder: (context) => Center(
                      child: DaywellButton(
                        label: 'Launch Dialog',
                        onPressed: () {
                          unawaited(
                            DaywellConfirmationDialog.show(
                              context,
                              title: 'Delete Very Long Account Name · ሂሳብ?',
                              message:
                                  'This verifies dialog text wrapping, scrollable body behavior, and button stacking without overflow on narrow displays.',
                              icon: Icons.warning_amber_rounded,
                              confirmLabel: 'Delete Permanently',
                              isDestructive: true,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.text('Launch Dialog'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          final titleSemantics = tester.getSemantics(
            find.text('Delete Very Long Account Name · ሂሳብ?'),
          );
          expect(titleSemantics.hasFlag(SemanticsFlag.isHeader), isTrue);

          final confirmSemantics = tester.getSemantics(
            find.widgetWithText(DaywellButton, 'Delete Permanently'),
          );
          expect(confirmSemantics.hasFlag(SemanticsFlag.isButton), isTrue);
        } finally {
          handle.dispose();
        }
      },
    );
  });

  group('DaywellThemeShowcase Stage 3.5 section', () {
    testWidgets(
      'Displays and interacts with composed patterns at 2.0x text scale in light and dark themes',
      (tester) async {
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey(mode),
              theme: DaywellTheme.light,
              darkTheme: DaywellTheme.dark,
              themeMode: mode,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2.0),
                ),
                child: child!,
              ),
              home: const DaywellThemeShowcase(),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));

          final scrollable = find.byType(Scrollable).first;
          final stage35Header =
              find.text('Stage 3.5 · Composed Shared UI Patterns');
          await tester.scrollUntilVisible(
            stage35Header,
            250,
            scrollable: scrollable,
            maxScrolls: 100,
          );
          await tester.pump(const Duration(milliseconds: 200));
          expect(stage35Header, findsOneWidget);

          final contentStateChip = find.widgetWithText(ChoiceChip, 'empty');
          await tester.scrollUntilVisible(
            contentStateChip,
            250,
            scrollable: scrollable,
            maxScrolls: 100,
          );
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tap(contentStateChip);
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text('No records match current filter'), findsOneWidget);

          final restoreButton =
              find.widgetWithText(DaywellButton, 'Restore Content');
          await tester.scrollUntilVisible(
            restoreButton,
            200,
            scrollable: scrollable,
            maxScrolls: 100,
          );
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tap(restoreButton);
          await tester.pump(const Duration(milliseconds: 200));
          expect(
              find.text('Loaded 3 verified sample entries.'), findsOneWidget);

          final destructiveBtn =
              find.widgetWithText(DaywellButton, 'Destructive Confirm');
          await tester.scrollUntilVisible(
            destructiveBtn,
            250,
            scrollable: scrollable,
            maxScrolls: 100,
          );
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tap(destructiveBtn);
          await tester.pump(const Duration(milliseconds: 300));

          await tester.tap(find.text('Confirm Delete'));
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            find.text('Last outcome: Destructive confirmed'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  });

  group('Stage 3.6 Adaptive Pattern Edge Cases', () {
    testWidgets(
      'DaywellConfirmationDialog scrolls cleanly on short landscape viewport at 2.0x text scale',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            darkTheme: DaywellTheme.dark,
            themeMode: ThemeMode.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2.0),
              ),
              child: child!,
            ),
            home: SizedBox(
              width: 568,
              height: 320,
              child: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: DaywellButton(
                      label: 'Open Landscape Dialog',
                      onPressed: () {
                        unawaited(
                          DaywellConfirmationDialog.show(
                            context,
                            title:
                                'Confirm Permanent Removal of Local Backup Vault',
                            message:
                                'This long confirmation message verifies that both title and body remain scrollable without vertical overflow on compact landscape screens.',
                            icon: Icons.warning_amber_rounded,
                            confirmLabel: 'Confirm Delete',
                            isDestructive: true,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Landscape Dialog'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Confirm Delete'), findsOneWidget);
      },
    );

    testWidgets(
      'DaywellSearchFilterBar renders safely with button/badge controls and unbounded horizontal parents',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    DaywellSearchFilterBar(
                      searchHintText: 'Filter entries...',
                      filterLayout: DaywellFilterLayout.horizontalScroll,
                      filterControls: [
                        const DaywellStatusBadge(
                          label: 'Synced',
                          tone: DaywellStatusTone.success,
                        ),
                        DaywellButton(
                          label: 'Reset View',
                          size: DaywellButtonSize.compact,
                          variant: DaywellButtonVariant.outlined,
                          onPressed: () {},
                        ),
                      ],
                      hasActiveFilters: true,
                      activeSummary: '2 filters active',
                      onClearFilters: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Synced'), findsOneWidget);
        expect(find.text('Reset View'), findsOneWidget);
      },
    );

    testWidgets(
      'DaywellSectionContainer wraps cleanly at tight 260px width and 2.0x text scale',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithTheme(
            textScale: 2.0,
            surfaceSize: const Size(260, 600),
            DaywellSectionContainer(
              title: 'Upcoming Commitments',
              count: 12,
              actionLabel: 'See All',
              onActionPressed: () {},
              subtitle: 'Wraps cleanly inside narrow card.',
              useCard: true,
              child: const Text('Card content'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Upcoming Commitments'), findsOneWidget);
        expect(find.text('See All'), findsOneWidget);
      },
    );
  });
}
