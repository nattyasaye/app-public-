import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/shared_foundation.dart';
import '../../core/theme/daywell_theme.dart';
import '../app_state.dart';
import '../shell/daywell_shell_routes.dart';
import '../shell/daywell_theme_controller.dart';
import '../widgets/shared_ui_widgets.dart';

class MoreView extends StatelessWidget {
  final AppStateManager state;
  final Function(String route)? onNavigateSubScreen;
  final void Function(DaywellTabId tab)? onSelectTab;
  final VoidCallback? onOpenBackup;
  final DaywellThemeController? themeController;

  const MoreView({
    super.key,
    required this.state,
    this.onNavigateSubScreen,
    this.onSelectTab,
    this.onOpenBackup,
    this.themeController,
  });

  void _goToTab(DaywellTabId tab, String routeKey) {
    if (onSelectTab != null) {
      onSelectTab!(tab);
    } else {
      onNavigateSubScreen?.call(routeKey);
    }
  }

  void _openBackup() {
    if (onOpenBackup != null) {
      onOpenBackup!();
    } else {
      onNavigateSubScreen?.call('backup');
    }
  }

  void _openAppearancePicker(BuildContext context) {
    final controller = themeController;
    if (controller == null) return;

    unawaited(
      showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return ListenableBuilder(
            listenable: controller,
            builder: (BuildContext context, Widget? _) {
              final currentMode = controller.themeMode;
              return AlertDialog(
                title: const Text('Appearance'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DaywellRadioTile<ThemeMode>(
                        title: 'System default',
                        subtitle: 'Match device display setting',
                        value: ThemeMode.system,
                        groupValue: currentMode,
                        onChanged: (ThemeMode? mode) {
                          if (mode != null) controller.setThemeMode(mode);
                        },
                      ),
                      DaywellRadioTile<ThemeMode>(
                        title: 'Light',
                        subtitle: 'Always use light appearance',
                        value: ThemeMode.light,
                        groupValue: currentMode,
                        onChanged: (ThemeMode? mode) {
                          if (mode != null) controller.setThemeMode(mode);
                        },
                      ),
                      DaywellRadioTile<ThemeMode>(
                        title: 'Dark',
                        subtitle: 'Always use dark appearance',
                        value: ThemeMode.dark,
                        groupValue: currentMode,
                        onChanged: (ThemeMode? mode) {
                          if (mode != null) controller.setThemeMode(mode);
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  DaywellButton(
                    label: 'Done',
                    variant: DaywellButtonVariant.text,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _openNotificationsInfoDialog(BuildContext context) {
    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;
    final activeTaskReminders = state.tasksController.state.activeReminderCount;
    final totalTaskReminders = state.tasksController.state.reminders
        .where((r) => r.targetType == 'task')
        .length;

    unawaited(
      showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Notifications & Reminders'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DaywellStatusBanner(
                    tone: DaywellStatusTone.info,
                    title: '$activeTaskReminders active task reminder(s)',
                    message: totalTaskReminders > activeTaskReminders
                        ? '$totalTaskReminders total saved (completed or archived tasks stay paused).'
                        : 'Shared local notifications run 100% offline with zero external push servers.',
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  Text(
                    'Configured local channels:',
                    style: Theme.of(dialogContext)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                  Text(
                    '• Task Reminders (task_reminders_channel)\n'
                    '• Financial Commitment Alerts (commitment_reminders_channel)\n'
                    '• General Reminders (custom_reminders_channel)',
                    style: Theme.of(dialogContext)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: semantic.textSecondary),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingSm),
                  Text(
                    'Future reminders schedule in-session via LocalNotificationService when tasks are created, edited, completed, rescheduled, or restored.',
                    style:
                        Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                  ),
                ],
              ),
            ),
            actions: [
              DaywellButton(
                label: 'Allow Notifications',
                variant: DaywellButtonVariant.outlined,
                size: DaywellButtonSize.compact,
                leadingIcon: Icons.notifications_active_outlined,
                onPressed: () async {
                  final granted = await state.requestNotificationPermission();
                  if (!context.mounted) return;
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        granted
                            ? 'Local notifications permitted for Daywell reminders.'
                            : 'Notification permission was not granted. Check Android app settings if needed.',
                      ),
                    ),
                  );
                },
              ),
              DaywellButton(
                label: 'Done',
                variant: DaywellButtonVariant.text,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final semantic = context.daywellColors;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final double? adaptiveToolbarHeight = textScale > 1.3
        ? (kToolbarHeight * textScale.clamp(1.0, 2.1)).ceilToDouble()
        : null;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: adaptiveToolbarHeight,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DAYWELL / ALL AREAS',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DaywellTypography.caption(
                color: semantic.textMuted,
              ).copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.2),
            ),
            Text(
              'Your space',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: state,
        builder: (BuildContext context, Widget? _) {
          return ListView(
            padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
            children: [
              // Workspace Profile Card
              DaywellCard(
                borderRadius: SharedDesignTokens.radiusXl,
                padding:
                    const EdgeInsets.all(SharedDesignTokens.spacingCompact),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: colorScheme.primaryContainer,
                      child: Text(
                        'DW',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: SharedDesignTokens.spacingCompact),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daywell Workspace',
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'A little more intentional, every day.',
                            style: textTheme.bodySmall?.copyWith(
                              color: semantic.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: SharedDesignTokens.spacingLg),

              // All Areas 8-Grid Section
              const DaywellSectionHeader(title: 'All areas'),
              const SizedBox(height: SharedDesignTokens.spacingCompact),

              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: SharedDesignTokens.spacingCompact,
                mainAxisSpacing: SharedDesignTokens.spacingCompact,
                childAspectRatio: textScale > 1.2 ? 1.25 : 1.5,
                children: [
                  _AreaCard(
                    icon: Icons.track_changes_rounded,
                    title: 'Goals',
                    subtitle:
                        '${state.financeController.state.savingsGoals.length} in progress',
                    onTap: () => _goToTab(DaywellTabId.finance, 'finance'),
                  ),
                  _AreaCard(
                    icon: Icons.menu_book_rounded,
                    title: 'Notes & knowledge',
                    subtitle:
                        '${state.notesController.state.activeNotesCount} in notes',
                    onTap: () => _goToTab(DaywellTabId.notes, 'notes'),
                  ),
                  _AreaCard(
                    icon: Icons.account_balance_wallet_rounded,
                    title: 'Finance',
                    subtitle:
                        '${state.financeController.state.accounts.length} accounts',
                    onTap: () => _goToTab(DaywellTabId.finance, 'finance'),
                  ),
                  _AreaCard(
                    icon: Icons.calendar_month_rounded,
                    title: 'Calendar',
                    subtitle:
                        '${state.calendarController.state.events.length} events',
                    onTap: () => _goToTab(DaywellTabId.calendar, 'calendar'),
                  ),
                  _AreaCard(
                    icon: Icons.list_alt_rounded,
                    title: 'Priorities',
                    subtitle: 'Your top 3',
                    onTap: () => _goToTab(DaywellTabId.tasks, 'tasks'),
                  ),
                  _AreaCard(
                    icon: Icons.calculate_outlined,
                    title: 'Calculations & tools',
                    subtitle: 'Everyday utilities',
                    onTap: () => _goToTab(DaywellTabId.today, 'today'),
                  ),
                  _AreaCard(
                    icon: Icons.bar_chart_rounded,
                    title: 'History & progress',
                    subtitle: 'Weekly summary',
                    onTap: () => _goToTab(DaywellTabId.today, 'today'),
                  ),
                  _AreaCard(
                    icon: Icons.inbox_outlined,
                    title: 'Inbox',
                    subtitle:
                        '${state.inboxController.state.unprocessedCount} unorganized',
                    onTap: () => _goToTab(DaywellTabId.tasks, 'tasks'),
                  ),
                ],
              ),

              const SizedBox(height: SharedDesignTokens.spacingLg),

              // Make it yours Section
              const DaywellSectionHeader(title: 'Make it yours'),
              const SizedBox(height: SharedDesignTokens.spacingSm),

              DaywellCard(
                borderRadius: SharedDesignTokens.radiusLg,
                child: Column(
                  children: [
                    if (themeController != null)
                      ListenableBuilder(
                        listenable: themeController!,
                        builder: (BuildContext context, Widget? _) {
                          return ListTile(
                            leading: Icon(
                              Icons.brightness_medium_rounded,
                              size: DaywellIconSize.lg,
                              color: colorScheme.primary,
                            ),
                            title: Text(
                              'Appearance',
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              themeController!.displayLabel,
                              style: textTheme.bodySmall?.copyWith(
                                color: semantic.textSecondary,
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right,
                              size: DaywellIconSize.md,
                              color: semantic.textMuted,
                            ),
                            onTap: () => _openAppearancePicker(context),
                          );
                        },
                      )
                    else
                      ListTile(
                        leading: Icon(
                          Icons.brightness_medium_rounded,
                          size: DaywellIconSize.lg,
                          color: colorScheme.primary,
                        ),
                        title: Text(
                          'Appearance',
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          'System · Light / Dark',
                          style: textTheme.bodySmall?.copyWith(
                            color: semantic.textSecondary,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          size: DaywellIconSize.md,
                          color: semantic.textMuted,
                        ),
                        onTap: () {},
                      ),
                    Divider(height: 1, color: semantic.divider),
                    ListTile(
                      leading: Icon(
                        Icons.notifications_outlined,
                        size: DaywellIconSize.lg,
                        color: colorScheme.primary,
                      ),
                      title: Text(
                        'Notifications & reminders',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'Schedules, sound & Android permissions',
                        style: textTheme.bodySmall?.copyWith(
                          color: semantic.textSecondary,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        size: DaywellIconSize.md,
                        color: semantic.textMuted,
                      ),
                      onTap: () => _openNotificationsInfoDialog(context),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: SharedDesignTokens.spacingLg),

              // Your data Section
              const DaywellSectionHeader(title: 'Your data'),
              const SizedBox(height: SharedDesignTokens.spacingSm),

              DaywellCard(
                borderRadius: SharedDesignTokens.radiusLg,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.sync_rounded,
                        size: DaywellIconSize.lg,
                        color: colorScheme.primary,
                      ),
                      title: Text(
                        'Sync & backup',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'Local save, sync status & recovery',
                        style: textTheme.bodySmall?.copyWith(
                          color: semantic.textSecondary,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        size: DaywellIconSize.md,
                        color: semantic.textMuted,
                      ),
                      onTap: _openBackup,
                    ),
                    Divider(height: 1, color: semantic.divider),
                    ListTile(
                      leading: Icon(
                        Icons.send_rounded,
                        size: DaywellIconSize.lg,
                        color: colorScheme.primary,
                      ),
                      title: Text(
                        'Telegram backup',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'Configure external backup destination',
                        style: textTheme.bodySmall?.copyWith(
                          color: semantic.textSecondary,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        size: DaywellIconSize.md,
                        color: semantic.textMuted,
                      ),
                      onTap: _openBackup,
                    ),
                    Divider(height: 1, color: semantic.divider),
                    ListTile(
                      leading: Icon(
                        Icons.security_rounded,
                        size: DaywellIconSize.lg,
                        color: colorScheme.primary,
                      ),
                      title: Text(
                        'Data management',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'AES-GCM-256 export & restore',
                        style: textTheme.bodySmall?.copyWith(
                          color: semantic.textSecondary,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        size: DaywellIconSize.md,
                        color: semantic.textMuted,
                      ),
                      onTap: _openBackup,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: SharedDesignTokens.spacingXl),
              Text(
                'Daywell · A considered place for everyday life.',
                textAlign: TextAlign.center,
                style: DaywellTypography.caption(color: semantic.textMuted),
              ),
              const SizedBox(height: SharedDesignTokens.spacingXl),
            ],
          );
        },
      ),
    );
  }
}

class _AreaCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AreaCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final semantic = context.daywellColors;

    return DaywellCard(
      onTap: onTap,
      borderRadius: SharedDesignTokens.radiusLg,
      padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: DaywellIconSize.md,
            color: colorScheme.primary,
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Text(
            title,
            style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: DaywellTypography.caption(color: semantic.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
