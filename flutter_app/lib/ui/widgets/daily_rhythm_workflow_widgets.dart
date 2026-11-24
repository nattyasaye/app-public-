import 'package:flutter/material.dart';

import '../../core/date/shared_date.dart';
import '../../core/shared_foundation.dart';
import '../../core/theme/daywell_theme.dart';
import '../../domain/daily_rhythm/daily_rhythm_models.dart';
import '../../domain/daily_rhythm/daily_rhythm_workflows.dart';
import 'shared_ui_widgets.dart';

String? _formatEthiopiaTime(String? iso) {
  if (iso == null || iso.trim().isEmpty) return null;
  final parsed = LocalDateTime.tryParse(iso);
  if (parsed == null) return null;
  return DayTimeOfDay(hour: parsed.hour, minute: parsed.minute)
      .toDisplay12Hour();
}

/// Built-in Daily Faith check-in card for Bible study and prayer inside More.
class DailyFaithCheckInCard extends StatelessWidget {
  final String dateIso;
  final DailyRhythmDayEntity record;
  final bool isToday;
  final ValueChanged<bool> onToggleBibleStudy;
  final ValueChanged<bool> onTogglePrayer;

  const DailyFaithCheckInCard({
    super.key,
    required this.dateIso,
    required this.record,
    this.isToday = true,
    required this.onToggleBibleStudy,
    required this.onTogglePrayer,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final completedCount =
        (record.bibleStudyDone ? 1 : 0) + (record.prayerDone ? 1 : 0);
    final faithComplete = record.isFaithComplete;
    final bibleTime = _formatEthiopiaTime(record.bibleStudyCompletedAt);
    final prayerTime = _formatEthiopiaTime(record.prayerCompletedAt);

    return DaywellCard(
      borderRadius: SharedDesignTokens.radiusLg,
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: SharedDesignTokens.spacingSm,
            runSpacing: SharedDesignTokens.spacingXs,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily Faith check-in',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: semantic.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Both Bible study and prayer are required today ($dateIso).',
                    style: textTheme.bodySmall?.copyWith(
                      color: semantic.textMuted,
                    ),
                  ),
                ],
              ),
              DaywellStatusBadge(
                label: faithComplete
                    ? '2/2 Complete'
                    : '$completedCount/2 completed',
                tone: faithComplete
                    ? DaywellStatusTone.success
                    : completedCount == 1
                        ? DaywellStatusTone.warning
                        : DaywellStatusTone.info,
              ),
            ],
          ),
          if (!isToday) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            const DaywellStatusBanner(
              tone: DaywellStatusTone.warning,
              icon: Icons.lock_outline,
              message:
                  'Past and future Faith check-ins are locked. Only today can be updated.',
            ),
          ],
          const SizedBox(height: SharedDesignTokens.spacingSm),
          DaywellCheckboxTile(
            title: 'Bible study',
            subtitle: record.bibleStudyDone
                ? (bibleTime != null
                    ? 'Completed at $bibleTime'
                    : 'Completed today')
                : 'Mark Bible study complete',
            value: record.bibleStudyDone,
            enabled: isToday,
            secondary: Icon(
              Icons.menu_book_outlined,
              size: DaywellIconSize.md,
              color: record.bibleStudyDone
                  ? semantic.success
                  : Theme.of(context).colorScheme.primary,
            ),
            onChanged: isToday
                ? (val) {
                    if (val != null) onToggleBibleStudy(val);
                  }
                : null,
          ),
          Divider(height: 1, color: semantic.divider),
          DaywellCheckboxTile(
            title: 'Prayer',
            subtitle: record.prayerDone
                ? (prayerTime != null
                    ? 'Completed at $prayerTime'
                    : 'Completed today')
                : 'Mark prayer complete',
            value: record.prayerDone,
            enabled: isToday,
            secondary: Icon(
              Icons.volunteer_activism_outlined,
              size: DaywellIconSize.md,
              color: record.prayerDone
                  ? semantic.success
                  : Theme.of(context).colorScheme.primary,
            ),
            onChanged: isToday
                ? (val) {
                    if (val != null) onTogglePrayer(val);
                  }
                : null,
          ),
          if (completedCount == 1) ...[
            const SizedBox(height: SharedDesignTokens.spacingXs),
            Text(
              'One step left: complete both Bible study and prayer to qualify Faith for today.',
              style: textTheme.bodySmall?.copyWith(
                color: semantic.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Daily Task Review card surfaced in Tasks Today and My Day views.
class DailyTaskReviewCard extends StatelessWidget {
  final DailyRhythmTaskReviewSnapshot snapshot;
  final DailyRhythmDayEntity record;
  final bool isToday;
  final VoidCallback onConfirmReview;

  const DailyTaskReviewCard({
    super.key,
    required this.snapshot,
    required this.record,
    this.isToday = true,
    required this.onConfirmReview,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final confirmed = record.taskReviewConfirmed;
    final reviewedTime = _formatEthiopiaTime(record.taskReviewedAt);
    final evidence = snapshot.evidence;

    return DaywellCard(
      borderRadius: SharedDesignTokens.radiusLg,
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius:
                      BorderRadius.circular(SharedDesignTokens.radiusMd),
                ),
                child: Icon(
                  Icons.fact_check_outlined,
                  size: DaywellIconSize.md,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: SharedDesignTokens.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: SharedDesignTokens.spacingSm,
                      runSpacing: SharedDesignTokens.spacingXs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Daily task review',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: semantic.textPrimary,
                          ),
                        ),
                        DaywellStatusBadge(
                          label: confirmed
                              ? (reviewedTime != null
                                  ? 'Confirmed · $reviewedTime'
                                  : 'Confirmed')
                              : 'Needs review',
                          tone: confirmed
                              ? DaywellStatusTone.success
                              : DaywellStatusTone.info,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      snapshot.hasRelevantTasks
                          ? 'Review what matters today. Completing every task is not required.'
                          : 'No overdue, due today, scheduled, or My Day tasks need attention today.',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Wrap(
            spacing: SharedDesignTokens.spacingXs,
            runSpacing: SharedDesignTokens.spacingXs,
            children: [
              DaywellStatusBadge(
                label: 'Overdue: ${evidence.overdueCount}',
                tone: evidence.overdueCount > 0
                    ? DaywellStatusTone.error
                    : DaywellStatusTone.info,
                showIcon: false,
              ),
              DaywellStatusBadge(
                label: 'Due / Today: ${evidence.todayCount}',
                tone: DaywellStatusTone.info,
                showIcon: false,
              ),
              DaywellStatusBadge(
                label: 'My Day: ${evidence.plannedCount}',
                tone: DaywellStatusTone.info,
                showIcon: false,
              ),
              DaywellStatusBadge(
                label: 'Done today: ${evidence.completedTodayCount}',
                tone: evidence.completedTodayCount > 0
                    ? DaywellStatusTone.success
                    : DaywellStatusTone.info,
                showIcon: false,
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          if (!isToday)
            const DaywellStatusBanner(
              tone: DaywellStatusTone.warning,
              icon: Icons.lock_outline,
              message:
                  'Past and future daily task reviews are locked. Switch back to Today to confirm today\'s review.',
            )
          else
            DaywellButton(
              label:
                  confirmed ? 'Reconfirm review' : snapshot.confirmActionLabel,
              variant: confirmed
                  ? DaywellButtonVariant.outlined
                  : DaywellButtonVariant.primary,
              size: DaywellButtonSize.compact,
              leadingIcon: Icons.check_circle_outline,
              fullWidth: true,
              onPressed: onConfirmReview,
            ),
        ],
      ),
    );
  }
}

/// Daily Finance Review & Close card surfaced in Finance Transactions tab.
class DailyFinanceCloseCard extends StatelessWidget {
  final DailyRhythmFinanceDaySummary summary;
  final DailyRhythmDayEntity record;
  final bool isShowingTodayFilter;
  final VoidCallback onConfirmClose;
  final VoidCallback? onFilterToday;

  const DailyFinanceCloseCard({
    super.key,
    required this.summary,
    required this.record,
    this.isShowingTodayFilter = false,
    required this.onConfirmClose,
    this.onFilterToday,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isClosed = record.isFinanceComplete;
    final needsReconfirmation = record.financeCloseStatus ==
        DailyRhythmFinanceCloseStatuses.needsReconfirmation;
    final closedTime = _formatEthiopiaTime(record.financeClosedAt);

    final String badgeLabel;
    if (needsReconfirmation) {
      badgeLabel = 'Needs reconfirmation';
    } else if (record.financeCloseStatus ==
        DailyRhythmFinanceCloseStatuses.closedWithTransactions) {
      badgeLabel = 'Closed · Reviewed';
    } else if (record.financeCloseStatus ==
        DailyRhythmFinanceCloseStatuses.closedNoTransactions) {
      badgeLabel = 'Closed · No transactions';
    } else {
      badgeLabel = 'Unreviewed today';
    }

    final String confirmLabel = needsReconfirmation
        ? (summary.hasTransactions
            ? "Reconfirm today's transactions"
            : 'Confirm no transactions today')
        : summary.confirmActionLabel;

    return DaywellCard(
      borderRadius: SharedDesignTokens.radiusLg,
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius:
                      BorderRadius.circular(SharedDesignTokens.radiusMd),
                ),
                child: Icon(
                  Icons.event_available_outlined,
                  size: DaywellIconSize.md,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: SharedDesignTokens.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: SharedDesignTokens.spacingSm,
                      runSpacing: SharedDesignTokens.spacingXs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Daily Finance review',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: semantic.textPrimary,
                          ),
                        ),
                        DaywellStatusBadge(
                          label: badgeLabel,
                          tone: isClosed
                              ? DaywellStatusTone.success
                              : needsReconfirmation
                                  ? DaywellStatusTone.warning
                                  : DaywellStatusTone.info,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary.hasTransactions
                          ? '${summary.transactionCount} active entry(s) recorded today (${summary.targetDateIso}).${isClosed && closedTime != null ? ' Confirmed at $closedTime.' : ''}'
                          : 'No active transactions recorded today (${summary.targetDateIso}).${isClosed && closedTime != null ? ' Confirmed at $closedTime.' : ''}',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (needsReconfirmation) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            const DaywellStatusBanner(
              tone: DaywellStatusTone.warning,
              title: "Today's ledger changed after closing",
              message:
                  'A same-day entry was added, replaced, voided, or restored. Review today\'s entries and reconfirm to close Finance for today.',
            ),
          ] else if (!isClosed) ...[
            const SizedBox(height: SharedDesignTokens.spacingXs),
            Text(
              'Explicit confirmation is required every day, even when there are no transactions today.',
              style: textTheme.bodySmall?.copyWith(
                color: semantic.textMuted,
              ),
            ),
          ],
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Wrap(
            spacing: SharedDesignTokens.spacingSm,
            runSpacing: SharedDesignTokens.spacingSm,
            children: [
              if (onFilterToday != null && !isShowingTodayFilter)
                DaywellButton(
                  label: 'View Today',
                  variant: DaywellButtonVariant.outlined,
                  size: DaywellButtonSize.compact,
                  leadingIcon: Icons.filter_list,
                  onPressed: onFilterToday,
                ),
              DaywellButton(
                label: isClosed ? 'Reconfirm review' : confirmLabel,
                variant: isClosed
                    ? DaywellButtonVariant.outlined
                    : DaywellButtonVariant.primary,
                size: DaywellButtonSize.compact,
                leadingIcon: Icons.check_circle_outline,
                onPressed: onConfirmClose,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
