import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
  group('DaywellButton & DaywellIconButton', () {
    testWidgets(
      'Renders all variants, invokes callbacks, and enforces >=48x48 touch targets',
      (tester) async {
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          final tapped = <DaywellButtonVariant>[];

          await tester.pumpWidget(
            _wrapWithTheme(
              themeMode: mode,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final variant in DaywellButtonVariant.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DaywellButton(
                        label: variant.name,
                        variant: variant,
                        leadingIcon: Icons.check,
                        trailingIcon: Icons.arrow_forward,
                        onPressed: () => tapped.add(variant),
                      ),
                    ),
                  const DaywellButton(
                    label: 'Compact',
                    size: DaywellButtonSize.compact,
                    onPressed: null,
                  ),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();

          for (final variant in DaywellButtonVariant.values) {
            final finder = find.text(variant.name);
            expect(finder, findsOneWidget);
            final size = tester.getSize(
              find.ancestor(
                of: finder,
                matching: find.byType(DaywellButton),
              ),
            );
            expect(size.width, greaterThanOrEqualTo(48.0));
            expect(size.height, greaterThanOrEqualTo(48.0));

            await tester.tap(finder);
            await tester.pump();
          }

          expect(tapped, DaywellButtonVariant.values);

          final compactSize = tester.getSize(
            find.ancestor(
              of: find.text('Compact'),
              matching: find.byType(DaywellButton),
            ),
          );
          expect(compactSize.height, greaterThanOrEqualTo(48.0));
        }
      },
    );

    testWidgets(
      'Disabled and loading states prevent interaction and expose loading indicator',
      (tester) async {
        var disabledTapped = 0;
        var loadingTapped = 0;

        await tester.pumpWidget(
          _wrapWithTheme(
            Column(
              children: [
                const DaywellButton(
                  label: 'Disabled Action',
                  onPressed: null,
                ),
                DaywellButton(
                  label: 'Saving Item',
                  isLoading: true,
                  onPressed: () => loadingTapped++,
                ),
                DaywellButton(
                  label: 'Full Width',
                  fullWidth: true,
                  onPressed: () => disabledTapped++,
                ),
              ],
            ),
          ),
        );

        await tester.tap(find.text('Disabled Action'));
        await tester.tap(find.text('Saving Item'));
        await tester.pump();

        expect(loadingTapped, 0);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await tester.tap(find.text('Full Width'));
        await tester.pump();
        expect(disabledTapped, 1);
      },
    );

    testWidgets(
      'DaywellIconButton supports tooltips, selection, destructive tint, and 48x48 hit target',
      (tester) async {
        var pressed = 0;

        await tester.pumpWidget(
          _wrapWithTheme(
            Row(
              children: [
                DaywellIconButton(
                  icon: Icons.star_border,
                  selectedIcon: Icons.star,
                  isSelected: true,
                  tooltip: 'Favorite item',
                  onPressed: () => pressed++,
                ),
                const DaywellIconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Disabled delete',
                  isDestructive: true,
                  onPressed: null,
                ),
              ],
            ),
          ),
        );

        expect(find.byIcon(Icons.star), findsOneWidget);
        expect(find.byTooltip('Favorite item'), findsOneWidget);
        expect(find.byTooltip('Disabled delete'), findsOneWidget);

        final iconButtonFinder = find.byType(DaywellIconButton).first;
        final size = tester.getSize(iconButtonFinder);
        expect(size.width, greaterThanOrEqualTo(48.0));
        expect(size.height, greaterThanOrEqualTo(48.0));

        await tester.tap(iconButtonFinder);
        await tester.tap(find.byType(DaywellIconButton).last);
        await tester.pump();

        expect(pressed, 1);
      },
    );
  });

  group('Cards, SectionHeader & EmptyState', () {
    testWidgets(
      'Preserves existing constructors, supports light/dark themes, and handles taps',
      (tester) async {
        var cardTapped = 0;
        var headerTapped = 0;
        var emptyActionTapped = 0;

        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          await tester.pumpWidget(
            _wrapWithTheme(
              themeMode: mode,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DaywellSectionHeader(
                    title: 'Recent Activity',
                    count: 12,
                    actionLabel: 'See All',
                    onActionPressed: () => headerTapped++,
                  ),
                  DaywellCard(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 12),
                    onTap: () => cardTapped++,
                    child: const Text('Tap Card Content'),
                  ),
                  DaywellEmptyState(
                    icon: Icons.inbox_outlined,
                    message: 'Nothing queued',
                    subtitle: 'Add a task to get started',
                    actionLabel: 'Create Task',
                    onActionPressed: () => emptyActionTapped++,
                  ),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Recent Activity'), findsOneWidget);
          expect(find.text('12'), findsOneWidget);
          expect(find.text('Tap Card Content'), findsOneWidget);
          expect(find.text('Nothing queued'), findsOneWidget);
          expect(find.text('Add a task to get started'), findsOneWidget);
        }

        await tester.tap(find.text('See All'));
        await tester.tap(find.text('Tap Card Content'));
        await tester.tap(find.text('Create Task'));
        await tester.pump();

        expect(headerTapped, 1);
        expect(cardTapped, 1);
        expect(emptyActionTapped, 1);
      },
    );

    testWidgets(
      'DaywellSectionHeader handles narrow width and 2.0x text scale without overflow',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithTheme(
            textScale: 2.0,
            surfaceSize: const Size(320, 480),
            DaywellSectionHeader(
              title: 'Long Section Header Title With Count',
              count: 42,
              actionLabel: 'Reset Demo Action',
              onActionPressed: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('42'), findsOneWidget);
      },
    );
  });

  group('Input Primitives & Search Controller Lifecycle', () {
    testWidgets(
      'DaywellTextField handles labels, required indicator, errors, callbacks, and disabled state',
      (tester) async {
        var changedValue = '';

        await tester.pumpWidget(
          _wrapWithTheme(
            Column(
              children: [
                DaywellTextField(
                  label: 'Task Title',
                  isRequired: true,
                  hintText: 'Enter title',
                  helperText: 'Visible helper',
                  errorText: 'Title required',
                  onChanged: (v) => changedValue = v,
                ),
                const SizedBox(height: 12),
                const DaywellTextField(
                  label: 'Locked Field',
                  initialValue: 'Immutable',
                  enabled: false,
                ),
              ],
            ),
          ),
        );

        expect(find.text('Task Title *'), findsOneWidget);
        expect(find.text('Title required'), findsOneWidget);

        await tester.enterText(find.byType(TextFormField).first, 'Pay rent');
        expect(changedValue, 'Pay rent');

        final disabledFormField = tester.widget<TextFormField>(
          find.byType(TextFormField).last,
        );
        expect(disabledFormField.enabled, isFalse);

        final disabledEditable = tester.widget<EditableText>(
          find.descendant(
            of: find.byType(TextFormField).last,
            matching: find.byType(EditableText),
          ),
        );
        expect(disabledEditable.readOnly, isTrue);

        await tester.tap(find.byType(TextFormField).last);
        await tester.pump();
        expect(disabledEditable.focusNode.hasFocus, isFalse);
        expect(find.text('Immutable'), findsOneWidget);
      },
    );

    testWidgets(
      'DaywellSearchField clear action fires onChanged("") and onCleared once without duplicates',
      (tester) async {
        final changes = <String>[];
        var clearedCount = 0;

        await tester.pumpWidget(
          _wrapWithTheme(
            DaywellSearchField(
              hintText: 'Search items',
              onChanged: changes.add,
              onCleared: () => clearedCount++,
            ),
          ),
        );

        expect(find.byIcon(Icons.clear), findsNothing);

        await tester.enterText(find.byType(TextField), 'coffee');
        await tester.pump();

        expect(changes, ['coffee']);
        expect(find.byIcon(Icons.clear), findsOneWidget);

        await tester.tap(find.byIcon(Icons.clear));
        await tester.pump();

        expect(changes, ['coffee', '']);
        expect(clearedCount, 1);
        expect(find.byIcon(Icons.clear), findsNothing);
      },
    );

    testWidgets(
      'DaywellSearchField safely replaces controllers and does not dispose external controllers',
      (tester) async {
        final controllerA = TextEditingController(text: 'alpha');
        final controllerB = TextEditingController(text: '');
        final changes = <String>[];

        await tester.pumpWidget(
          _wrapWithTheme(
            DaywellSearchField(
              controller: controllerA,
              onChanged: changes.add,
            ),
          ),
        );

        expect(find.byIcon(Icons.clear), findsOneWidget);
        expect(changes, isEmpty);

        // Replace with controllerB
        await tester.pumpWidget(
          _wrapWithTheme(
            DaywellSearchField(
              controller: controllerB,
              onChanged: changes.add,
            ),
          ),
        );

        expect(find.byIcon(Icons.clear), findsNothing);
        controllerB.text = 'beta';
        await tester.pump();
        expect(find.byIcon(Icons.clear), findsOneWidget);
        // Programmatic controller mutation must not trigger onChanged
        expect(changes, isEmpty);

        // Switch from external controllerB to internal controller
        await tester.pumpWidget(
          _wrapWithTheme(
            DaywellSearchField(
              onChanged: changes.add,
            ),
          ),
        );

        // Unmount completely and confirm external controllers were not disposed
        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        controllerA.text = 'still_alive_a';
        controllerB.text = 'still_alive_b';
        expect(controllerA.text, 'still_alive_a');
        expect(controllerB.text, 'still_alive_b');

        controllerA.dispose();
        controllerB.dispose();
      },
    );

    testWidgets(
      'DaywellDropdownField selects values and respects disabled state',
      (tester) async {
        String? selected = 'low';

        await tester.pumpWidget(
          _wrapWithTheme(
            StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    DaywellDropdownField<String>(
                      label: 'Priority',
                      isRequired: true,
                      value: selected,
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Low')),
                        DropdownMenuItem(value: 'high', child: Text('High')),
                      ],
                      onChanged: (v) => setState(() => selected = v),
                    ),
                    const SizedBox(height: 12),
                    DaywellDropdownField<String>(
                      label: 'Disabled Priority',
                      value: 'low',
                      enabled: false,
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Low')),
                      ],
                      onChanged: (_) {},
                    ),
                  ],
                );
              },
            ),
          ),
        );

        expect(find.text('Priority *'), findsOneWidget);
        await tester.tap(find.byType(DropdownButtonFormField<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('High').last);
        await tester.pumpAndSettle();

        expect(selected, 'high');
      },
    );
  });

  group('Selection Controls', () {
    testWidgets(
      'Switch, Checkbox, and Radio tiles toggle via row tap and respect disabled state',
      (tester) async {
        var switchVal = false;
        var checkboxVal = false;
        var radioVal = 'a';
        var disabledSwitchTapped = 0;

        await tester.pumpWidget(
          _wrapWithTheme(
            StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    DaywellSwitchTile(
                      title: 'Sync reminders',
                      subtitle: 'Local schedule',
                      value: switchVal,
                      onChanged: (v) => setState(() => switchVal = v),
                    ),
                    DaywellSwitchTile(
                      title: 'Disabled switch',
                      value: false,
                      enabled: false,
                      onChanged: (_) => disabledSwitchTapped++,
                    ),
                    DaywellCheckboxTile(
                      title: 'Include notes',
                      value: checkboxVal,
                      onChanged: (v) =>
                          setState(() => checkboxVal = v ?? false),
                    ),
                    DaywellRadioTile<String>(
                      title: 'Option A',
                      value: 'a',
                      groupValue: radioVal,
                      onChanged: (v) {
                        if (v != null) setState(() => radioVal = v);
                      },
                    ),
                    DaywellRadioTile<String>(
                      title: 'Option B',
                      value: 'b',
                      groupValue: radioVal,
                      onChanged: (v) {
                        if (v != null) setState(() => radioVal = v);
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('Sync reminders'));
        await tester.tap(find.text('Disabled switch'));
        await tester.tap(find.text('Include notes'));
        await tester.tap(find.text('Option B'));
        await tester.pump();

        expect(switchVal, isTrue);
        expect(disabledSwitchTapped, 0);
        expect(checkboxVal, isTrue);
        expect(radioVal, 'b');
      },
    );
  });

  group('Feedback & Status Indicators', () {
    testWidgets(
      'DaywellStatusBadge and DaywellStatusBanner render all tones with icons, actions, and dismiss',
      (tester) async {
        var actionCount = 0;
        var dismissCount = 0;

        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          await tester.pumpWidget(
            _wrapWithTheme(
              themeMode: mode,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Wrap(
                    spacing: 8,
                    children: [
                      DaywellStatusBadge(
                        label: 'Info',
                        tone: DaywellStatusTone.info,
                      ),
                      DaywellStatusBadge(
                        label: 'Success',
                        tone: DaywellStatusTone.success,
                      ),
                      DaywellStatusBadge(
                        label: 'Warning',
                        tone: DaywellStatusTone.warning,
                      ),
                      DaywellStatusBadge(
                        label: 'Error',
                        tone: DaywellStatusTone.error,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final tone in DaywellStatusTone.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DaywellStatusBanner(
                        title: '${tone.name} title',
                        message: '${tone.name} banner message',
                        tone: tone,
                        actionLabel:
                            tone == DaywellStatusTone.error ? 'Retry' : null,
                        onActionPressed: tone == DaywellStatusTone.error
                            ? () => actionCount++
                            : null,
                        onDismiss: tone == DaywellStatusTone.info
                            ? () => dismissCount++
                            : null,
                      ),
                    ),
                  const DaywellProgressBar(
                    label: 'Savings Goal',
                    valueText: '75%',
                    value: 0.75,
                    tone: DaywellStatusTone.success,
                  ),
                  const SizedBox(height: 8),
                  const DaywellLoadingIndicator(
                    inline: true,
                    label: 'Syncing vault...',
                  ),
                ],
              ),
            ),
          );
          await tester.pump();

          expect(find.byIcon(Icons.info_outline), findsNWidgets(2));
          expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(2));
          expect(find.byIcon(Icons.warning_amber_rounded), findsNWidgets(2));
          expect(find.byIcon(Icons.error_outline), findsNWidgets(2));
          expect(find.text('Savings Goal'), findsOneWidget);
          expect(find.text('75%'), findsOneWidget);
          expect(find.text('Syncing vault...'), findsOneWidget);
        }

        await tester.tap(find.text('Retry'));
        await tester.tap(find.byTooltip('Dismiss'));
        await tester.pump();

        expect(actionCount, 1);
        expect(dismissCount, 1);
      },
    );
  });

  group('Responsive Narrow Screen, 2.0x Text Scale & Expanded Showcase', () {
    testWidgets(
      'Expanded DaywellThemeShowcase renders without overflow at 2.0x text scale and narrow width',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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
          expect(tester.takeException(), isNull);

          final scrollable = find.byType(Scrollable).first;
          await tester.scrollUntilVisible(
            find.text('Stage 3.4 · Primitive Shared UI Components'),
            250,
            scrollable: scrollable,
          );
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.takeException(), isNull);

          await tester.scrollUntilVisible(
            find.text('Add Sample'),
            250,
            scrollable: scrollable,
          );
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.takeException(), isNull);
        }
      },
    );
  });

  group('Stage 3.4.1 Semantics & Edge-Case Regressions', () {
    testWidgets(
      'DaywellButton and DaywellIconButton expose single button SemanticsNodes without duplicate labels',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _wrapWithTheme(
              Column(
                children: [
                  DaywellButton(
                    label: 'Save',
                    onPressed: () {},
                  ),
                  DaywellButton(
                    label: 'Save',
                    semanticLabel: 'Save entry',
                    isLoading: true,
                    onPressed: () {},
                  ),
                  DaywellIconButton(
                    icon: Icons.star_border,
                    selectedIcon: Icons.star,
                    isSelected: true,
                    tooltip: 'Favorite',
                    semanticLabel: 'Favorite item',
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          );

          final regularNode =
              tester.getSemantics(find.byType(DaywellButton).first);
          final regularData = regularNode.getSemanticsData();
          expect(regularData.hasFlag(SemanticsFlag.isButton), isTrue);
          expect(regularData.hasAction(SemanticsAction.tap), isTrue);
          expect(regularData.label, 'Save');
          expect(regularNode.childrenCount, 0);

          final loadingNode =
              tester.getSemantics(find.byType(DaywellButton).last);
          final loadingData = loadingNode.getSemanticsData();
          expect(loadingData.hasFlag(SemanticsFlag.isButton), isTrue);
          expect(loadingData.hasFlag(SemanticsFlag.isEnabled), isFalse);
          expect(loadingData.label, 'Save entry');
          expect(loadingNode.childrenCount, 0);

          final iconNode = tester.getSemantics(find.byType(DaywellIconButton));
          final iconData = iconNode.getSemanticsData();
          expect(iconData.hasFlag(SemanticsFlag.isButton), isTrue);
          expect(iconData.hasFlag(SemanticsFlag.isSelected), isTrue);
          expect(iconData.hasAction(SemanticsAction.tap), isTrue);
          expect(iconData.label, 'Favorite item');
          expect(iconData.tooltip, 'Favorite');
          expect(iconNode.childrenCount, 0);
        } finally {
          handle.dispose();
        }
      },
    );

    testWidgets(
      'Input and selection primitives preserve native Material semantics without wrapper duplication',
      (tester) async {
        final handle = tester.ensureSemantics();
        final searchController = TextEditingController(text: 'notes');
        try {
          await tester.pumpWidget(
            _wrapWithTheme(
              Column(
                children: [
                  DaywellSearchField(
                    controller: searchController,
                    hintText: 'Search...',
                  ),
                  const DaywellTextField(
                    label: 'Title',
                    isRequired: true,
                    hintText: 'Enter title',
                  ),
                  DaywellDropdownField<String>(
                    label: 'Frequency',
                    isRequired: true,
                    value: 'daily',
                    items: const [
                      DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    ],
                    onChanged: (_) {},
                  ),
                  DaywellSwitchTile(
                    title: 'Alerts',
                    subtitle: 'Local only',
                    value: true,
                    onChanged: (_) {},
                  ),
                  DaywellCheckboxTile(
                    title: 'Archived',
                    value: null,
                    tristate: true,
                    onChanged: (_) {},
                  ),
                  DaywellRadioTile<String>(
                    title: 'Option A',
                    value: 'a',
                    groupValue: 'a',
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          );

          final searchNode = tester.getSemantics(
            find.descendant(
              of: find.byType(DaywellSearchField),
              matching: find.byType(EditableText),
            ),
          );
          final searchData = searchNode.getSemanticsData();
          expect(searchData.hasFlag(SemanticsFlag.isTextField), isTrue);
          expect(searchData.value, 'notes');
          // Single child is the Clear search DaywellIconButton (no duplicate wrappers).
          expect(searchNode.childrenCount, 1);

          final clearButtonNode =
              tester.getSemantics(find.byType(DaywellIconButton));
          final clearButtonData = clearButtonNode.getSemanticsData();
          expect(clearButtonData.hasFlag(SemanticsFlag.isButton), isTrue);
          expect(clearButtonData.tooltip, 'Clear search');
          expect(clearButtonNode.childrenCount, 0);

          final textFieldNode = tester.getSemantics(
            find.descendant(
              of: find.byType(DaywellTextField),
              matching: find.byType(EditableText),
            ),
          );
          expect(
            textFieldNode.getSemanticsData().hasFlag(SemanticsFlag.isTextField),
            isTrue,
          );
          expect(textFieldNode.childrenCount, 0);
          final titleLabelData =
              tester.getSemantics(find.text('Title *')).getSemanticsData();
          expect(titleLabelData.label, 'Title *');

          final dropdownNode =
              tester.getSemantics(find.byType(DropdownButtonFormField<String>));
          expect(
            dropdownNode.getSemanticsData().hasFlag(SemanticsFlag.isButton),
            isTrue,
          );
          expect(dropdownNode.getSemanticsData().label, 'Daily');

          final switchNode =
              tester.getSemantics(find.byType(DaywellSwitchTile));
          final switchData = switchNode.getSemanticsData();
          expect(switchData.hasFlag(SemanticsFlag.hasToggledState), isTrue);
          expect(switchData.hasFlag(SemanticsFlag.isToggled), isTrue);
          expect(switchData.hasAction(SemanticsAction.tap), isTrue);
          expect(switchData.label, 'Alerts\nLocal only');

          final checkboxNode =
              tester.getSemantics(find.byType(DaywellCheckboxTile));
          final checkboxData = checkboxNode.getSemanticsData();
          expect(checkboxData.hasFlag(SemanticsFlag.hasCheckedState), isTrue);
          expect(checkboxData.hasFlag(SemanticsFlag.isCheckStateMixed), isTrue);
          expect(checkboxData.hasAction(SemanticsAction.tap), isTrue);
          expect(checkboxData.label, 'Archived');

          final radioNode =
              tester.getSemantics(find.byType(DaywellRadioTile<String>));
          final radioData = radioNode.getSemanticsData();
          expect(
            radioData.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup),
            isTrue,
          );
          expect(radioData.hasFlag(SemanticsFlag.isChecked), isTrue);
          expect(radioData.hasAction(SemanticsAction.tap), isTrue);
          expect(radioData.label, 'Option A');
        } finally {
          searchController.dispose();
          handle.dispose();
        }
      },
    );

    testWidgets(
      'Feedback & indicator semantics avoid duplication, liveRegion spam, and NaN crashes',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _wrapWithTheme(
              Column(
                children: [
                  const DaywellStatusBadge(
                    label: 'Synced',
                    tone: DaywellStatusTone.info,
                  ),
                  DaywellStatusBanner(
                    title: 'Alert',
                    message: 'Check cash',
                    tone: DaywellStatusTone.warning,
                    actionLabel: 'Fix',
                    onActionPressed: () {},
                    onDismiss: () {},
                  ),
                  const DaywellLoadingIndicator(
                    inline: true,
                    label: 'Syncing...',
                  ),
                  const DaywellProgressBar(
                    label: 'Budget',
                    valueText: '68%',
                    value: 0.68,
                  ),
                  const DaywellProgressBar(
                    label: 'Clamped',
                    value: 1.8,
                  ),
                  const DaywellProgressBar(
                    label: 'NaN Guard',
                    value: double.nan,
                  ),
                ],
              ),
            ),
          );

          final badgeData = tester
              .getSemantics(find.byType(DaywellStatusBadge))
              .getSemanticsData();
          expect(badgeData.label, 'Info: Synced');

          final bannerNode =
              tester.getSemantics(find.byType(DaywellStatusBanner));
          final bannerData = bannerNode.getSemanticsData();
          expect(bannerData.hasFlag(SemanticsFlag.isButton), isFalse);
          expect(bannerData.hasFlag(SemanticsFlag.isLiveRegion), isFalse);
          expect(bannerNode.childrenCount, 3);

          final loadingData = tester
              .getSemantics(find.byType(DaywellLoadingIndicator))
              .getSemanticsData();
          expect(loadingData.label, 'Syncing...');
          expect(loadingData.hasFlag(SemanticsFlag.isLiveRegion), isFalse);

          final progressBars = find.byType(DaywellProgressBar);
          final budgetData =
              tester.getSemantics(progressBars.at(0)).getSemanticsData();
          expect(budgetData.label, 'Budget');
          expect(budgetData.value, '68%');

          final clampedData =
              tester.getSemantics(progressBars.at(1)).getSemanticsData();
          expect(clampedData.label, 'Clamped');
          expect(clampedData.value, '100%');

          final nanData =
              tester.getSemantics(progressBars.at(2)).getSemanticsData();
          expect(nanData.label, 'NaN Guard');
          expect(nanData.value, '');
        } finally {
          handle.dispose();
        }
      },
    );

    testWidgets(
      'DaywellSearchField updates clear button visibility across disabled-to-enabled controller swaps',
      (tester) async {
        final emptyController = TextEditingController();
        final populatedController = TextEditingController(text: 'ledger');
        addTearDown(emptyController.dispose);
        addTearDown(populatedController.dispose);

        await tester.pumpWidget(
          _wrapWithTheme(
            DaywellSearchField(
              controller: emptyController,
              enabled: false,
            ),
          ),
        );
        expect(find.byIcon(Icons.clear), findsNothing);

        // Swap to populated controller while disabled: clear icon remains hidden.
        await tester.pumpWidget(
          _wrapWithTheme(
            DaywellSearchField(
              controller: populatedController,
              enabled: false,
            ),
          ),
        );
        expect(find.byIcon(Icons.clear), findsNothing);

        // Re-enable without changing controller: clear icon immediately appears.
        await tester.pumpWidget(
          _wrapWithTheme(
            DaywellSearchField(
              controller: populatedController,
              enabled: true,
            ),
          ),
        );
        expect(find.byIcon(Icons.clear), findsOneWidget);

        // Mutating old detached emptyController must not hide populatedController's clear icon.
        emptyController.text = 'old';
        emptyController.clear();
        await tester.pump();
        expect(find.byIcon(Icons.clear), findsOneWidget);
      },
    );
  });

  group('Stage 3.6 Adaptive Layout & Accessibility', () {
    testWidgets(
      'Shared primitives survive unbounded horizontal constraints without Flex errors',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    DaywellButton(
                      label: 'Horizontal Action',
                      leadingIcon: Icons.add,
                      onPressed: () {},
                    ),
                    const SizedBox(width: 8),
                    const DaywellStatusBadge(
                      label: 'Horizontal Badge',
                      tone: DaywellStatusTone.info,
                    ),
                    const SizedBox(width: 8),
                    const DaywellLoadingIndicator(
                      inline: true,
                      label: 'Syncing...',
                    ),
                    const SizedBox(width: 8),
                    const DaywellProgressBar(
                      label: 'Budget',
                      valueText: '68%',
                      value: 0.68,
                    ),
                    const SizedBox(width: 8),
                    DaywellStatusBanner(
                      title: 'Alert',
                      message: 'Check ledger balance',
                      actionLabel: 'Fix',
                      onActionPressed: () {},
                      onDismiss: () {},
                    ),
                    const SizedBox(width: 8),
                    DaywellSectionHeader(
                      title: 'Section',
                      count: 4,
                      actionLabel: 'View',
                      onActionPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Horizontal Action'), findsOneWidget);
        expect(find.text('Horizontal Badge'), findsOneWidget);
      },
    );

    testWidgets(
      'Handles 320px width and 2.0x text scale across stacked headers, progress headers, badges, buttons, and banners',
      (tester) async {
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          await tester.pumpWidget(
            _wrapWithTheme(
              themeMode: mode,
              textScale: 2.0,
              surfaceSize: const Size(320, 640),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DaywellSectionHeader(
                    title: 'Monthly Reconciliation Summary',
                    count: 18,
                    actionLabel: 'Manage All',
                    onActionPressed: () {},
                  ),
                  const SizedBox(height: 12),
                  const DaywellProgressBar(
                    label: 'Monthly Savings Goal',
                    valueText: '12,500 / 20,000 ETB',
                    value: 0.625,
                  ),
                  const SizedBox(height: 12),
                  const DaywellStatusBadge(
                    label: 'Pending Verification',
                    tone: DaywellStatusTone.warning,
                  ),
                  const SizedBox(height: 12),
                  DaywellButton(
                    label: 'Confirm Monthly Statement',
                    leadingIcon: Icons.check_circle_outline,
                    onPressed: () {},
                  ),
                  const SizedBox(height: 12),
                  DaywellStatusBanner(
                    title: 'Period Unbalanced',
                    message: 'Review cash balance before closing month.',
                    tone: DaywellStatusTone.error,
                    actionLabel: 'Retry',
                    onActionPressed: () {},
                    onDismiss: () {},
                  ),
                ],
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);

          final bannerActionSize = tester.getSize(
            find.widgetWithText(TextButton, 'Retry'),
          );
          expect(bannerActionSize.height, greaterThanOrEqualTo(48.0));
        }
      },
    );

    testWidgets(
      'Custom semanticLabel binds cleanly to interactive inputs without double-reading static labels',
      (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _wrapWithTheme(
              Column(
                children: [
                  const DaywellTextField(
                    label: 'Amount',
                    isRequired: true,
                    semanticLabel: 'Amount in ETB, required',
                  ),
                  const SizedBox(height: 12),
                  DaywellDropdownField<String>(
                    label: 'Frequency',
                    semanticLabel: 'Recurrence frequency',
                    value: 'daily',
                    items: const [
                      DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    ],
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          );

          expect(find.text('Amount *'), findsOneWidget);
          expect(
            find.bySemanticsLabel(RegExp('Amount in ETB, required')),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(RegExp('Recurrence frequency')),
            findsOneWidget,
          );
        } finally {
          handle.dispose();
        }
      },
    );

    testWidgets(
      'Keyboard Tab focus moves across DaywellButton and interactive DaywellCard',
      (tester) async {
        var buttonActivated = false;
        var cardTapped = false;

        await tester.pumpWidget(
          _wrapWithTheme(
            Column(
              children: [
                DaywellButton(
                  label: 'Primary Action',
                  onPressed: () => buttonActivated = true,
                ),
                const SizedBox(height: 12),
                DaywellCard(
                  padding: const EdgeInsets.all(16),
                  onTap: () => cardTapped = true,
                  child: const Text('Interactive Card'),
                ),
              ],
            ),
          ),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(buttonActivated, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(cardTapped, isTrue);
      },
    );
  });
}
