import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/shared_foundation.dart';
import '../../core/theme/daywell_theme.dart';
import 'shared_ui_widgets.dart';

/// Development and automated widget-testing showcase for the Stage 3.3 theme
/// foundation, Stage 3.4 primitive components, and Stage 3.5 composed patterns.
/// Not registered as a production route.
class DaywellThemeShowcase extends StatefulWidget {
  const DaywellThemeShowcase({super.key});

  @override
  State<DaywellThemeShowcase> createState() => _DaywellThemeShowcaseState();
}

class _DaywellThemeShowcaseState extends State<DaywellThemeShowcase> {
  final TextEditingController _sampleController = TextEditingController();
  final TextEditingController _primitiveSearchController =
      TextEditingController();
  final TextEditingController _primitiveTextController =
      TextEditingController();
  final TextEditingController _patternSearchController =
      TextEditingController();
  int _navIndex = 0;
  String _selectedMenuAction = 'Default';
  String _searchQuery = '';
  String? _selectedFrequency = 'daily';
  bool _notificationsEnabled = true;
  bool _includeArchived = false;
  String _calendarMode = 'ethiopian';
  bool _showDismissibleBanner = true;
  String _patternFilter = 'all';
  String _patternQuery = '';
  DaywellContentStatus _contentStatus = DaywellContentStatus.content;
  String _lastConfirmationOutcome = 'None yet';

  @override
  void dispose() {
    _sampleController.dispose();
    _primitiveSearchController.dispose();
    _primitiveTextController.dispose();
    _patternSearchController.dispose();
    super.dispose();
  }

  void _openSampleDialog() {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Theme Dialog Preview'),
          content: const Text(
            'Centralized DialogTheme styling for Latin and Ethiopic copy: '
            'መረጃው በትክክል ተቀምጧል።',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSampleSnackBar() {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Theme SnackBar preview — ተግባሩ ተጠናቋል።'),
      ),
    );
  }

  Future<void> _openPatternConfirmation({required bool isDestructive}) async {
    final confirmed = await DaywellConfirmationDialog.show(
      context,
      title: isDestructive ? 'Delete Sample Entry?' : 'Archive Sample Entry?',
      message: isDestructive
          ? 'This permanently removes the preview item from local state.'
          : 'Archiving keeps history intact while hiding it from active lists.',
      icon: isDestructive ? Icons.delete_outline : Icons.archive_outlined,
      confirmLabel: isDestructive ? 'Confirm Delete' : 'Archive',
      isDestructive: isDestructive,
    );
    if (!mounted) return;
    setState(() {
      _lastConfirmationOutcome = confirmed
          ? (isDestructive ? 'Destructive confirmed' : 'Archive confirmed')
          : 'Cancelled';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = context.daywellColors;
    final textTheme = theme.textTheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daywell Theme Showcase'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Showcase menu',
            onSelected: (value) {
              setState(() => _selectedMenuAction = value);
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'Latin',
                child: Text('Latin sample'),
              ),
              PopupMenuItem<String>(
                value: 'Ethiopic',
                child: Text('አማርኛ ናሙና'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
        children: [
          Text(
            'Brightness: ${theme.brightness.name} · Scale: ${textScale.toStringAsFixed(1)}x · Menu: $_selectedMenuAction',
            style: textTheme.labelMedium,
          ),
          const SizedBox(height: SharedDesignTokens.spacingMd),
          _SectionTitle(
              label: 'Brand & Semantic Color Pairs',
              style: textTheme.titleMedium),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Wrap(
            spacing: SharedDesignTokens.spacingSm,
            runSpacing: SharedDesignTokens.spacingSm,
            children: [
              _ColorPairChip(
                label: 'Primary',
                background: colorScheme.primary,
                foreground: colorScheme.onPrimary,
              ),
              _ColorPairChip(
                label: 'Primary Container',
                background: colorScheme.primaryContainer,
                foreground: colorScheme.onPrimaryContainer,
              ),
              _ColorPairChip(
                label: 'Income',
                background: semantic.incomeContainer,
                foreground: semantic.onIncomeContainer,
              ),
              _ColorPairChip(
                label: 'Expense',
                background: semantic.expenseContainer,
                foreground: semantic.onExpenseContainer,
              ),
              _ColorPairChip(
                label: 'Transfer',
                background: semantic.transferContainer,
                foreground: semantic.onTransferContainer,
              ),
              _ColorPairChip(
                label: 'Success',
                background: semantic.successContainer,
                foreground: semantic.onSuccessContainer,
              ),
              _ColorPairChip(
                label: 'Error',
                background: semantic.errorContainer,
                foreground: semantic.onErrorContainer,
              ),
              _ColorPairChip(
                label: 'Warning',
                background: semantic.warningContainer,
                foreground: semantic.onWarningContainer,
              ),
              _ColorPairChip(
                label: 'Info',
                background: semantic.infoContainer,
                foreground: semantic.onInfoContainer,
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingLg),
          const Divider(),
          const SizedBox(height: SharedDesignTokens.spacingMd),
          _SectionTitle(
              label: 'Typography & Bilingual Script',
              style: textTheme.titleMedium),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Display · ዕለታዊ ዕቅድ', style: textTheme.displaySmall),
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                  Text('Heading · አጠቃላይ እይታ', style: textTheme.headlineMedium),
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                  Text('Title · ንዑስ ርዕስ', style: textTheme.titleMedium),
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                  Text(
                    'Body · Daywell Personal System — ቀንዎን በአግባቡ ያደራጁ።',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                  Text(
                    'Body Small · ጥቅምት 2019 ዓ.ም. (2026-11-14)',
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingSm),
                  Text(
                    '1,250.00 ETB',
                    style: DaywellTypography.numericHero(
                      color: semantic.textPrimary,
                    ),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                  Text(
                    '+450.00 ብር',
                    style: DaywellTypography.numericBody(
                      color: semantic.onIncomeContainer,
                    ),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                  Text(
                    'schemaVersion: 5 · UTF-8 / Ge\'ez',
                    style: DaywellTypography.mono(
                      color: semantic.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SharedDesignTokens.spacingLg),
          _SectionTitle(
              label: 'Material Buttons & Interactive Targets',
              style: textTheme.titleMedium),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Wrap(
            spacing: SharedDesignTokens.spacingSm,
            runSpacing: SharedDesignTokens.spacingSm,
            children: [
              ElevatedButton(
                onPressed: _openSampleDialog,
                child: const Text('Open Dialog'),
              ),
              FilledButton(
                onPressed: _showSampleSnackBar,
                child: const Text('Show SnackBar'),
              ),
              OutlinedButton(
                onPressed: () {},
                child: const Text('Outlined Action'),
              ),
              TextButton(
                onPressed: () {},
                child: const Text('Text Action'),
              ),
              const ElevatedButton(
                onPressed: null,
                child: Text('Disabled'),
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingLg),
          _SectionTitle(
              label: 'Material Input Themes', style: textTheme.titleMedium),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          TextField(
            controller: _sampleController,
            decoration: const InputDecoration(
              labelText: 'Task or Note Title',
              hintText: 'Enter Latin or አማርኛ text',
              helperText: 'Uses centralized InputDecorationTheme',
            ),
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          const TextField(
            enabled: true,
            decoration: InputDecoration(
              labelText: 'Amount (ETB)',
              errorText: 'Amount must be greater than zero',
            ),
          ),
          const SizedBox(height: SharedDesignTokens.spacingLg),
          const Divider(),
          const SizedBox(height: SharedDesignTokens.spacingMd),
          _SectionTitle(
            label: 'Stage 3.4 · Primitive Shared UI Components',
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: SharedDesignTokens.spacingMd),
          DaywellSectionHeader(
            title: 'Primitive Buttons & Actions',
            count: 5,
            actionLabel: 'Reset Demo',
            onActionPressed: () {
              setState(() {
                _showDismissibleBanner = true;
                _searchQuery = '';
                _primitiveSearchController.clear();
              });
            },
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Wrap(
            spacing: SharedDesignTokens.spacingSm,
            runSpacing: SharedDesignTokens.spacingSm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DaywellButton(
                label: 'Primary',
                leadingIcon: Icons.check,
                onPressed: _showSampleSnackBar,
              ),
              DaywellButton(
                label: 'Secondary',
                variant: DaywellButtonVariant.secondary,
                leadingIcon: Icons.bookmark_border,
                onPressed: () {},
              ),
              DaywellButton(
                label: 'Outlined',
                variant: DaywellButtonVariant.outlined,
                onPressed: () {},
              ),
              DaywellButton(
                label: 'Text',
                variant: DaywellButtonVariant.text,
                onPressed: () {},
              ),
              DaywellButton(
                label: 'Delete',
                variant: DaywellButtonVariant.destructive,
                leadingIcon: Icons.delete_outline,
                onPressed: () {},
              ),
              const DaywellButton(
                label: 'Saving',
                isLoading: true,
                onPressed: null,
              ),
              DaywellIconButton(
                icon: Icons.tune,
                tooltip: 'Filter options',
                onPressed: () {},
              ),
              DaywellIconButton(
                icon: Icons.delete_outline,
                tooltip: 'Delete item',
                isDestructive: true,
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingLg),
          const DaywellSectionHeader(title: 'Primitive Inputs'),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          DaywellSearchField(
            controller: _primitiveSearchController,
            hintText: 'Search tasks, notes, or መዝገብ...',
            onChanged: (value) => setState(() => _searchQuery = value),
            onCleared: () => setState(() => _searchQuery = ''),
          ),
          if (_searchQuery.isNotEmpty) ...[
            const SizedBox(height: SharedDesignTokens.spacingXs),
            Text(
              'Active search: $_searchQuery',
              style: textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          DaywellTextField(
            controller: _primitiveTextController,
            label: 'Category Name',
            hintText: 'e.g. Utilities · መብራት',
            helperText: 'Supports Latin and Ethiopic text',
            isRequired: true,
            prefixIcon: const Icon(Icons.label_outline),
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          DaywellDropdownField<String>(
            label: 'Recurrence',
            value: _selectedFrequency,
            items: const [
              DropdownMenuItem(value: 'daily', child: Text('Daily')),
              DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
              DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
            ],
            onChanged: (val) => setState(() => _selectedFrequency = val),
          ),
          const SizedBox(height: SharedDesignTokens.spacingLg),
          const DaywellSectionHeader(title: 'Selection Controls'),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          DaywellCard(
            padding: const EdgeInsets.symmetric(
              vertical: SharedDesignTokens.spacingXs,
            ),
            child: Column(
              children: [
                DaywellSwitchTile(
                  title: 'Daily reminder alerts',
                  subtitle: 'Local offline notifications only',
                  value: _notificationsEnabled,
                  onChanged: (val) =>
                      setState(() => _notificationsEnabled = val),
                ),
                const Divider(),
                DaywellCheckboxTile(
                  title: 'Include archived records',
                  subtitle: 'Show completed items in summaries',
                  value: _includeArchived,
                  onChanged: (val) =>
                      setState(() => _includeArchived = val ?? false),
                ),
                const Divider(),
                DaywellRadioTile<String>(
                  title: 'Ethiopian Calendar (ዓ.ም.)',
                  value: 'ethiopian',
                  groupValue: _calendarMode,
                  onChanged: (val) {
                    if (val != null) setState(() => _calendarMode = val);
                  },
                ),
                DaywellRadioTile<String>(
                  title: 'Gregorian Calendar',
                  value: 'gregorian',
                  groupValue: _calendarMode,
                  onChanged: (val) {
                    if (val != null) setState(() => _calendarMode = val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: SharedDesignTokens.spacingLg),
          const DaywellSectionHeader(title: 'Feedback & Status Indicators'),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          const Wrap(
            spacing: SharedDesignTokens.spacingSm,
            runSpacing: SharedDesignTokens.spacingSm,
            children: [
              DaywellStatusBadge(label: 'Synced', tone: DaywellStatusTone.info),
              DaywellStatusBadge(
                label: 'Balanced',
                tone: DaywellStatusTone.success,
              ),
              DaywellStatusBadge(
                label: 'Due Soon',
                tone: DaywellStatusTone.warning,
              ),
              DaywellStatusBadge(
                label: 'Overdue',
                tone: DaywellStatusTone.error,
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          if (_showDismissibleBanner) ...[
            DaywellStatusBanner(
              title: 'Offline Backup Ready',
              message:
                  'Your encrypted vault can be exported locally at any time.',
              tone: DaywellStatusTone.success,
              actionLabel: 'Inspect',
              onActionPressed: _openSampleDialog,
              onDismiss: () => setState(() => _showDismissibleBanner = false),
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
          ],
          const DaywellStatusBanner(
            title: 'Unreconciled Entry',
            message: 'Verify cash balance before closing the monthly period.',
            tone: DaywellStatusTone.warning,
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          const DaywellProgressBar(
            label: 'Monthly Budget Used',
            valueText: '68%',
            value: 0.68,
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          const DaywellLoadingIndicator(
            inline: true,
            label: 'Reconciling local ledger...',
          ),
          const SizedBox(height: SharedDesignTokens.spacingMd),
          DaywellCard(
            child: DaywellEmptyState(
              icon: Icons.inbox_outlined,
              message: 'No sample items queued',
              subtitle: 'Tap below to preview empty state CTA styling.',
              actionLabel: 'Add Sample',
              onActionPressed: () {},
            ),
          ),
          const SizedBox(height: SharedDesignTokens.spacingLg),
          const Divider(),
          const SizedBox(height: SharedDesignTokens.spacingMd),
          _SectionTitle(
            label: 'Stage 3.5 · Composed Shared UI Patterns',
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: SharedDesignTokens.spacingMd),
          DaywellSectionContainer(
            title: 'Search & Filter Pattern',
            subtitle:
                'Composes DaywellSearchField, chip filters, and summary reset.',
            useCard: true,
            contentPadding: EdgeInsets.zero,
            child: DaywellSearchFilterBar(
              searchController: _patternSearchController,
              searchHintText: 'Filter tasks, ledger, or መዝገብ...',
              onSearchChanged: (value) => setState(() => _patternQuery = value),
              onSearchCleared: () => setState(() => _patternQuery = ''),
              trailingAction: DaywellIconButton(
                icon: Icons.filter_list,
                tooltip: 'Toggle archived filter',
                isSelected: _patternFilter == 'active',
                onPressed: () {
                  setState(() {
                    _patternFilter = _patternFilter == 'all' ? 'active' : 'all';
                  });
                },
              ),
              filterControls: [
                for (final key in ['all', 'active', 'done'])
                  ChoiceChip(
                    label: Text(key.toUpperCase()),
                    selected: _patternFilter == key,
                    onSelected: (_) => setState(() => _patternFilter = key),
                  ),
              ],
              hasActiveFilters:
                  _patternQuery.isNotEmpty || _patternFilter != 'all',
              activeSummary:
                  'Filter: $_patternFilter${_patternQuery.isNotEmpty ? ' · "$_patternQuery"' : ''}',
              onClearFilters: () {
                _patternSearchController.clear();
                setState(() {
                  _patternQuery = '';
                  _patternFilter = 'all';
                });
              },
              showBottomDivider: false,
            ),
          ),
          const SizedBox(height: SharedDesignTokens.spacingMd),
          DaywellSectionContainer(
            title: 'Content State Pattern',
            count: DaywellContentStatus.values.length,
            actionLabel: 'Reset State',
            onActionPressed: () {
              setState(() => _contentStatus = DaywellContentStatus.content);
            },
            subtitle:
                'Switch between loading, empty, error, and content views.',
            useCard: true,
            footer: Text(
              'Active state: ${_contentStatus.name}',
              style: textTheme.bodySmall?.copyWith(color: semantic.textMuted),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: SharedDesignTokens.spacingSm,
                  runSpacing: SharedDesignTokens.spacingSm,
                  children: [
                    for (final status in DaywellContentStatus.values)
                      ChoiceChip(
                        label: Text(status.name),
                        selected: _contentStatus == status,
                        onSelected: (_) =>
                            setState(() => _contentStatus = status),
                      ),
                  ],
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellContentState(
                  status: _contentStatus,
                  loadingLabel: 'Loading sample module records...',
                  emptyIcon: Icons.note_alt_outlined,
                  emptyMessage: 'No records match current filter',
                  emptySubtitle: 'Try clearing filters or adding a new entry.',
                  emptyActionLabel: 'Restore Content',
                  onEmptyAction: () => setState(
                      () => _contentStatus = DaywellContentStatus.content),
                  errorTitle: 'Sync Check Failed',
                  errorMessage: 'Unable to verify sample ledger totals.',
                  onRetry: () => setState(
                      () => _contentStatus = DaywellContentStatus.content),
                  child: const DaywellStatusBanner(
                    title: 'Content Ready',
                    message: 'Loaded 3 verified sample entries.',
                    tone: DaywellStatusTone.info,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SharedDesignTokens.spacingMd),
          DaywellSectionContainer(
            title: 'Confirmation Dialog Pattern',
            subtitle: 'Last outcome: $_lastConfirmationOutcome',
            child: Wrap(
              spacing: SharedDesignTokens.spacingSm,
              runSpacing: SharedDesignTokens.spacingSm,
              children: [
                DaywellButton(
                  label: 'Confirm Archive',
                  variant: DaywellButtonVariant.secondary,
                  leadingIcon: Icons.archive_outlined,
                  onPressed: () =>
                      unawaited(_openPatternConfirmation(isDestructive: false)),
                ),
                DaywellButton(
                  label: 'Destructive Confirm',
                  variant: DaywellButtonVariant.destructive,
                  leadingIcon: Icons.delete_outline,
                  onPressed: () =>
                      unawaited(_openPatternConfirmation(isDestructive: true)),
                ),
              ],
            ),
          ),
          const SizedBox(height: SharedDesignTokens.spacingLg),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (idx) => setState(() => _navIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.palette_outlined),
            selectedIcon: Icon(Icons.palette_rounded),
            label: 'Tokens',
          ),
          NavigationDestination(
            icon: Icon(Icons.text_fields_outlined),
            selectedIcon: Icon(Icons.text_fields_rounded),
            label: 'Type',
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  final TextStyle? style;

  const _SectionTitle({
    required this.label,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(label, style: style),
    );
  }
}

class _ColorPairChip extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _ColorPairChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SharedDesignTokens.spacingCompact,
        vertical: SharedDesignTokens.spacingSm,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
      ),
      child: Text(
        label,
        style: DaywellTypography.label(color: foreground),
      ),
    );
  }
}
