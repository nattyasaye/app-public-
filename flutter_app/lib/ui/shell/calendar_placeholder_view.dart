import 'dart:async';
import 'package:flutter/material.dart';
import '../../application/calendar/calendar_controller.dart';
import '../../core/date/shared_date.dart';
import '../../core/shared_foundation.dart';
import '../../core/theme/daywell_theme.dart';
import '../widgets/shared_ui_widgets.dart';

/// Explicit placeholder host for the Calendar destination until the dedicated
/// Calendar module UI is introduced. Replaces the prior silent TasksView alias
/// while reading hydrated [CalendarController] state directly.
class CalendarPlaceholderView extends StatelessWidget {
  final CalendarController controller;
  final VoidCallback? onOpenTasks;

  const CalendarPlaceholderView({
    super.key,
    required this.controller,
    this.onOpenTasks,
  });

  @override
  Widget build(BuildContext context) {
    final dualToday = SharedDateFormatter.formatDual(
      CalendarDate.today(),
      useAmharic: false,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, Widget? _) {
          final calendarState = controller.state;
          final semantic = context.daywellColors;
          final textTheme = Theme.of(context).textTheme;
          final hasError = calendarState.errorMessage != null &&
              calendarState.errorMessage!.trim().isNotEmpty;

          if (calendarState.isLoading) {
            return const DaywellContentState(
              status: DaywellContentStatus.loading,
              loadingLabel: 'Loading calendar events...',
              statePadding: EdgeInsets.all(SharedDesignTokens.spacingLg),
            );
          }

          if (hasError) {
            return Center(
              child: DaywellContentState(
                status: DaywellContentStatus.error,
                errorTitle: 'Unable to load calendar events',
                errorMessage: calendarState.errorMessage!,
                retryLabel: 'Retry',
                onRetry: () => unawaited(controller.loadAll()),
                statePadding:
                    const EdgeInsets.all(SharedDesignTokens.spacingLg),
              ),
            );
          }

          final hasEvents = calendarState.events.isNotEmpty;

          return ListView(
            padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
            children: [
              DaywellSectionContainer(
                title: 'Schedule Overview',
                useCard: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dualToday,
                      style: textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    Text(
                      hasEvents
                          ? '${calendarState.events.length} synced calendar events ready offline.'
                          : '0 synced calendar events stored offline.',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SharedDesignTokens.spacingLg),
              if (!hasEvents)
                DaywellContentState(
                  status: DaywellContentStatus.empty,
                  emptyIcon: Icons.calendar_month_outlined,
                  emptyMessage: 'Calendar workspace coming soon',
                  emptySubtitle:
                      'Your local schedule store is active. While the dedicated Calendar module is built, you can manage scheduled items from Tasks.',
                  emptyActionLabel: onOpenTasks != null ? 'Open Tasks' : null,
                  onEmptyAction: onOpenTasks,
                )
              else
                DaywellSectionContainer(
                  title: 'Synced Events Preview',
                  count: calendarState.events.length,
                  subtitle:
                      'Full Calendar views will arrive in an upcoming stage.',
                  useCard: true,
                  actionLabel: onOpenTasks != null ? 'Open Tasks' : null,
                  onActionPressed: onOpenTasks,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: calendarState.events
                        .take(3)
                        .map(
                          (event) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: SharedDesignTokens.spacingSm,
                            ),
                            child: Text(
                              '${event.title} · ${event.dateIso}',
                              style: textTheme.bodyMedium?.copyWith(
                                color: semantic.textPrimary,
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
