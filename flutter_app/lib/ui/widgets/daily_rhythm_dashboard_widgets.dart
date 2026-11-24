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

/// Central Daily Rhythm Dashboard overview card built on Stage A/C domain
/// workflows and canonical Stage 3 theme tokens.
class DailyRhythmDashboardCard extends StatefulWidget {
  final DailyRhythmDashboardOverview? overview;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final ValueChanged<DailyRhythmFaithStep>? onCompleteFaithStep;
  final VoidCallback onOpenFaith;
  final VoidCallback onOpenTasksReview;
  final VoidCallback onOpenFinanceReview;
  final VoidCallback onOpenCalendarHistory;

  const DailyRhythmDashboardCard({
    super.key,
    required this.overview,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.onRetry,
    this.onCompleteFaithStep,
    required this.onOpenFaith,
    required this.onOpenTasksReview,
    required this.onOpenFinanceReview,
    required this.onOpenCalendarHistory,
  });

  @override
  State<DailyRhythmDashboardCard> createState() =>
      _DailyRhythmDashboardCardState();
}

class _DailyRhythmDashboardCardState extends State<DailyRhythmDashboardCard> {
  bool _showFreezeRules = false;

  void _handleNextAction(DailyRhythmDashboardOverview overview) {
    switch (overview.nextIncompleteResponsibility) {
      case DailyRhythmResponsibility.faith:
        final step = overview.nextFaithStep;
        if (step != null && widget.onCompleteFaithStep != null) {
          widget.onCompleteFaithStep!(step);
        } else {
          widget.onOpenFaith();
        }
        break;
      case DailyRhythmResponsibility.tasks:
        widget.onOpenTasksReview();
        break;
      case DailyRhythmResponsibility.finance:
        widget.onOpenFinanceReview();
        break;
      case null:
        widget.onOpenCalendarHistory();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final overview = widget.overview;

    if (widget.isLoading && overview == null) {
      return const DaywellCard(
        borderRadius: SharedDesignTokens.radiusXl,
        padding: EdgeInsets.all(SharedDesignTokens.spacingMd),
        child: DaywellLoadingIndicator(label: 'Loading Daily Rhythm...'),
      );
    }

    if (widget.errorMessage != null && overview == null) {
      return DaywellCard(
        borderRadius: SharedDesignTokens.radiusXl,
        padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
        child: DaywellStatusBanner(
          tone: DaywellStatusTone.error,
          title: 'Unable to load Daily Rhythm',
          message: widget.errorMessage!,
          actionLabel: widget.onRetry != null ? 'Retry' : null,
          onActionPressed: widget.onRetry,
        ),
      );
    }

    if (overview == null) return const SizedBox.shrink();

    final overallTone = overview.isDayQualified
        ? DaywellStatusTone.success
        : overview.financeNeedsReconfirmation
            ? DaywellStatusTone.warning
            : DaywellStatusTone.info;

    final IconData nextActionIcon;
    switch (overview.nextIncompleteResponsibility) {
      case DailyRhythmResponsibility.faith:
        nextActionIcon = Icons.menu_book_outlined;
        break;
      case DailyRhythmResponsibility.tasks:
        nextActionIcon = Icons.fact_check_outlined;
        break;
      case DailyRhythmResponsibility.finance:
        nextActionIcon = Icons.account_balance_wallet_outlined;
        break;
      case null:
        nextActionIcon = Icons.verified_outlined;
        break;
    }

    return DaywellCard(
      borderRadius: SharedDesignTokens.radiusXl,
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.start,
            spacing: SharedDesignTokens.spacingSm,
            runSpacing: SharedDesignTokens.spacingSm,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: SharedDesignTokens.spacingSm,
                    runSpacing: SharedDesignTokens.spacingXs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'DAILY RHYTHM',
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                        ),
                      ),
                      DaywellStatusBadge(
                        label: overview.overallStatusLabel,
                        tone: overallTone,
                      ),
                    ],
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                  Text(
                    '${overview.completedResponsibilities} of ${overview.totalResponsibilities} responsibilities complete',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: semantic.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    overview.overallStatusDescription,
                    style: textTheme.bodySmall?.copyWith(
                      color: semantic.textSecondary,
                    ),
                  ),
                ],
              ),
              DaywellButton(
                label: 'Calendar history',
                variant: DaywellButtonVariant.text,
                size: DaywellButtonSize.compact,
                leadingIcon: Icons.calendar_month_outlined,
                onPressed: widget.onOpenCalendarHistory,
              ),
            ],
          ),

          if (widget.errorMessage != null &&
              widget.errorMessage!.trim().isNotEmpty) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            DaywellStatusBanner(
              tone: DaywellStatusTone.error,
              message: widget.errorMessage!,
              actionLabel: widget.onRetry != null ? 'Retry' : null,
              onActionPressed: widget.onRetry,
            ),
          ],

          const SizedBox(height: SharedDesignTokens.spacingCompact),
          DaywellProgressBar(
            value: overview.progressFraction,
            label: "Today's Daily Rhythm progress",
            valueText:
                '${overview.completedResponsibilities}/${overview.totalResponsibilities}',
            tone: overallTone,
            semanticLabel:
                'Daily Rhythm progress ${overview.completedResponsibilities} of ${overview.totalResponsibilities}',
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),

          // Highlighted Next Step / Completed Calm Banner
          Container(
            padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
            decoration: BoxDecoration(
              color: overview.isDayQualified
                  ? semantic.successContainer
                  : overview.financeNeedsReconfirmation
                      ? semantic.warningContainer
                      : semantic.surfaceSubtle,
              borderRadius: BorderRadius.circular(SharedDesignTokens.radiusLg),
              border: Border.all(
                color: overview.isDayQualified
                    ? semantic.success.withOpacity(0.35)
                    : overview.financeNeedsReconfirmation
                        ? semantic.warning.withOpacity(0.45)
                        : semantic.border,
              ),
            ),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final stackButton = constraints.maxWidth < 400;
                final details = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          nextActionIcon,
                          size: DaywellIconSize.md,
                          color: overview.isDayQualified
                              ? semantic.onSuccessContainer
                              : overview.financeNeedsReconfirmation
                                  ? semantic.onWarningContainer
                                  : colorScheme.primary,
                        ),
                        const SizedBox(width: SharedDesignTokens.spacingSm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                overview.nextActionTitle,
                                style: textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: overview.isDayQualified
                                      ? semantic.onSuccessContainer
                                      : overview.financeNeedsReconfirmation
                                          ? semantic.onWarningContainer
                                          : semantic.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                overview.nextActionDescription,
                                style: textTheme.bodySmall?.copyWith(
                                  color: overview.isDayQualified
                                      ? semantic.onSuccessContainer
                                      : overview.financeNeedsReconfirmation
                                          ? semantic.onWarningContainer
                                          : semantic.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                );
                final actionBtn = DaywellButton(
                  label: widget.isSaving &&
                          overview.nextIncompleteResponsibility ==
                              DailyRhythmResponsibility.faith
                      ? 'Saving...'
                      : overview.nextActionButtonLabel,
                  variant: overview.isDayQualified
                      ? DaywellButtonVariant.outlined
                      : DaywellButtonVariant.primary,
                  size: DaywellButtonSize.compact,
                  trailingIcon: Icons.arrow_forward,
                  fullWidth: stackButton,
                  onPressed: widget.isSaving
                      ? null
                      : () => _handleNextAction(overview),
                );

                if (stackButton) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      details,
                      const SizedBox(height: SharedDesignTokens.spacingSm),
                      actionBtn,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: details),
                    const SizedBox(width: SharedDesignTokens.spacingMd),
                    actionBtn,
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: SharedDesignTokens.spacingCompact),

          // Three Daily Responsibilities
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final faithTile = _ResponsibilityTile(
                title: 'Faith',
                icon: Icons.menu_book_outlined,
                badgeLabel: overview.faithProgressLabel,
                badgeTone: overview.faithComplete
                    ? DaywellStatusTone.success
                    : overview.faithCompletedCount == 1
                        ? DaywellStatusTone.warning
                        : DaywellStatusTone.info,
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StepLine(
                      done: overview.bibleStudyDone,
                      label: 'Bible study',
                    ),
                    const SizedBox(height: 4),
                    _StepLine(
                      done: overview.prayerDone,
                      label: 'Prayer',
                    ),
                  ],
                ),
                primaryAction: DaywellButton(
                  label: overview.faithActionLabel,
                  variant: overview.faithComplete
                      ? DaywellButtonVariant.outlined
                      : DaywellButtonVariant.secondary,
                  size: DaywellButtonSize.compact,
                  fullWidth: true,
                  onPressed: widget.isSaving
                      ? null
                      : () {
                          final step = overview.nextFaithStep;
                          if (step != null &&
                              widget.onCompleteFaithStep != null) {
                            widget.onCompleteFaithStep!(step);
                          } else {
                            widget.onOpenFaith();
                          }
                        },
                ),
                secondaryAction: overview.nextFaithStep != null
                    ? DaywellButton(
                        label: 'Open in More',
                        variant: DaywellButtonVariant.text,
                        size: DaywellButtonSize.compact,
                        fullWidth: true,
                        onPressed: widget.onOpenFaith,
                      )
                    : null,
              );

              final tasksTile = _ResponsibilityTile(
                title: 'Tasks',
                icon: Icons.fact_check_outlined,
                badgeLabel: overview.tasksComplete ? 'Reviewed' : 'Review',
                badgeTone: overview.tasksComplete
                    ? DaywellStatusTone.success
                    : overview.tasksOverdueCount > 0
                        ? DaywellStatusTone.warning
                        : DaywellStatusTone.info,
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      overview.tasksStatusLabel,
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: semantic.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      overview.tasksContextLabel,
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                  ],
                ),
                primaryAction: DaywellButton(
                  label: overview.tasksActionLabel,
                  variant: overview.tasksComplete
                      ? DaywellButtonVariant.outlined
                      : DaywellButtonVariant.secondary,
                  size: DaywellButtonSize.compact,
                  fullWidth: true,
                  onPressed: widget.onOpenTasksReview,
                ),
              );

              final financeTile = _ResponsibilityTile(
                title: 'Finance',
                icon: Icons.account_balance_wallet_outlined,
                badgeLabel: overview.financeComplete
                    ? 'Closed'
                    : overview.financeNeedsReconfirmation
                        ? 'Reconfirm'
                        : 'Open',
                badgeTone: overview.financeComplete
                    ? DaywellStatusTone.success
                    : overview.financeNeedsReconfirmation
                        ? DaywellStatusTone.warning
                        : DaywellStatusTone.info,
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      overview.financeStatusLabel,
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: overview.financeNeedsReconfirmation
                            ? semantic.warning
                            : semantic.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      overview.financeContextLabel,
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                  ],
                ),
                primaryAction: DaywellButton(
                  label: overview.financeActionLabel,
                  variant: overview.financeComplete
                      ? DaywellButtonVariant.outlined
                      : DaywellButtonVariant.secondary,
                  size: DaywellButtonSize.compact,
                  fullWidth: true,
                  onPressed: widget.onOpenFinanceReview,
                ),
              );

              if (constraints.maxWidth >= 600) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: faithTile),
                    const SizedBox(width: SharedDesignTokens.spacingSm),
                    Expanded(child: tasksTile),
                    const SizedBox(width: SharedDesignTokens.spacingSm),
                    Expanded(child: financeTile),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  faithTile,
                  const SizedBox(height: SharedDesignTokens.spacingSm),
                  tasksTile,
                  const SizedBox(height: SharedDesignTokens.spacingSm),
                  financeTile,
                ],
              );
            },
          ),

          const SizedBox(height: SharedDesignTokens.spacingCompact),

          // Streak & Freeze Section
          Container(
            padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
            decoration: BoxDecoration(
              color: semantic.surfaceSubtle,
              borderRadius: BorderRadius.circular(SharedDesignTokens.radiusLg),
              border: Border.all(color: semantic.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: SharedDesignTokens.spacingSm,
                  runSpacing: SharedDesignTokens.spacingSm,
                  children: [
                    _StreakStatPill(
                      icon: Icons.local_fire_department_outlined,
                      iconColor: semantic.warning,
                      label: 'Current streak',
                      value: '${overview.currentStreak}d',
                    ),
                    _StreakStatPill(
                      icon: Icons.emoji_events_outlined,
                      iconColor: colorScheme.primary,
                      label: 'Best streak',
                      value: '${overview.bestStreak}d',
                    ),
                    _StreakStatPill(
                      icon: Icons.ac_unit,
                      iconColor: semantic.info,
                      label: 'Freezes',
                      value:
                          '${overview.availableFreezes} / ${overview.maxFreezes}',
                    ),
                  ],
                ),
                const SizedBox(height: SharedDesignTokens.spacingSm),
                DaywellProgressBar(
                  value: overview.nextFreezeProgressFraction,
                  label: 'Next freeze progress',
                  valueText:
                      '${overview.daysTowardNextFreeze} / ${overview.qualifyingDaysPerFreeze} qualifying days',
                  tone: DaywellStatusTone.info,
                  semanticLabel:
                      'Next freeze progress ${overview.daysTowardNextFreeze} of ${overview.qualifyingDaysPerFreeze} qualifying days',
                ),
                const SizedBox(height: SharedDesignTokens.spacingXs),
                if (overview.provisionalFreezeActive) ...[
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                  DaywellStatusBanner(
                    tone: DaywellStatusTone.warning,
                    icon: Icons.ac_unit,
                    title: 'Provisional freeze active',
                    message: overview.freezeStatusSummary,
                  ),
                ] else
                  Text(
                    overview.freezeStatusSummary,
                    style: textTheme.bodySmall?.copyWith(
                      color: semantic.textSecondary,
                    ),
                  ),
                const SizedBox(height: SharedDesignTokens.spacingXs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: DaywellButton(
                    label: _showFreezeRules
                        ? 'Hide freeze rules'
                        : 'How streak freezes work',
                    variant: DaywellButtonVariant.text,
                    size: DaywellButtonSize.compact,
                    leadingIcon: Icons.shield_outlined,
                    trailingIcon: _showFreezeRules
                        ? Icons.expand_less
                        : Icons.expand_more,
                    onPressed: () {
                      setState(() => _showFreezeRules = !_showFreezeRules);
                    },
                  ),
                ),
                if (_showFreezeRules) ...[
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                  for (final rule in overview.freezeRules)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '• ',
                            style: textTheme.bodySmall?.copyWith(
                              color: semantic.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              rule,
                              style: textTheme.bodySmall?.copyWith(
                                color: semantic.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponsibilityTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final String badgeLabel;
  final DaywellStatusTone badgeTone;
  final Widget body;
  final Widget primaryAction;
  final Widget? secondaryAction;

  const _ResponsibilityTile({
    required this.title,
    required this.icon,
    required this.badgeLabel,
    required this.badgeTone,
    required this.body,
    required this.primaryAction,
    this.secondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
      decoration: BoxDecoration(
        color: semantic.surfaceSubtle,
        borderRadius: BorderRadius.circular(SharedDesignTokens.radiusLg),
        border: Border.all(color: semantic.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: SharedDesignTokens.spacingXs,
            runSpacing: SharedDesignTokens.spacingXs,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: DaywellIconSize.sm,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: semantic.textPrimary,
                    ),
                  ),
                ],
              ),
              DaywellStatusBadge(
                label: badgeLabel,
                tone: badgeTone,
                showIcon: false,
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          body,
          const SizedBox(height: SharedDesignTokens.spacingSm),
          primaryAction,
          if (secondaryAction != null) ...[
            const SizedBox(height: 2),
            secondaryAction!,
          ],
        ],
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool done;
  final String label;

  const _StepLine({
    required this.done,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          size: DaywellIconSize.sm,
          color: done ? semantic.success : semantic.textMuted,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: done ? semantic.textPrimary : semantic.textSecondary,
              fontWeight: done ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _StreakStatPill extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _StreakStatPill({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 100),
      padding: const EdgeInsets.symmetric(
        horizontal: SharedDesignTokens.spacingCompact,
        vertical: SharedDesignTokens.spacingSm,
      ),
      decoration: BoxDecoration(
        color: semantic.card,
        borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
        border: Border.all(color: semantic.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: DaywellIconSize.xs, color: iconColor),
              const SizedBox(width: 4),
              Text(
                label.toUpperCase(),
                style: textTheme.labelSmall?.copyWith(
                  color: semantic.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(
              color: semantic.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Non-color-only Daily Rhythm marker placed inside Calendar month cells.
class DailyRhythmCalendarCellMarker extends StatelessWidget {
  final DailyRhythmCalendarDayInspection inspection;
  final bool isSelected;

  const DailyRhythmCalendarCellMarker({
    super.key,
    required this.inspection,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final textTheme = Theme.of(context).textTheme;

    if (inspection.shortMarkerGlyph.isEmpty ||
        (inspection.calendarStatus ==
                DailyRhythmCalendarDisplayStatus.untouched &&
            inspection.isToday)) {
      return const SizedBox.shrink();
    }

    final Color color = switch (inspection.calendarStatus) {
      DailyRhythmCalendarDisplayStatus.complete =>
        isSelected ? onPrimary : semantic.success,
      DailyRhythmCalendarDisplayStatus.partial =>
        isSelected ? onPrimary : semantic.warning,
      DailyRhythmCalendarDisplayStatus.freezeProtected =>
        isSelected ? onPrimary : semantic.info,
      DailyRhythmCalendarDisplayStatus.missed ||
      DailyRhythmCalendarDisplayStatus.untouched =>
        isSelected ? onPrimary : semantic.error,
      DailyRhythmCalendarDisplayStatus.unrecorded =>
        isSelected ? onPrimary : semantic.textMuted,
    };

    return Tooltip(
      message: inspection.accessibleLabel,
      child: Text(
        inspection.shortMarkerGlyph,
        style: textTheme.labelSmall?.copyWith(
          fontSize: 10,
          height: 1.0,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

/// Compact non-color-only Daily Rhythm legend displayed under the Calendar month grid.
class DailyRhythmCalendarLegend extends StatelessWidget {
  const DailyRhythmCalendarLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    Widget item(String glyph, Color color, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            glyph,
            style: textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: semantic.textMuted,
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: SharedDesignTokens.spacingCompact,
      runSpacing: SharedDesignTokens.spacingXs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Rhythm:',
          style: textTheme.labelSmall?.copyWith(
            color: semantic.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        item('✓', semantic.success, 'Complete'),
        item('◐', semantic.warning, 'In progress'),
        item('❄?', semantic.info, 'Provisional freeze'),
        item('❄', semantic.info, 'Freeze protected'),
        item('✕', semantic.error, 'Missed'),
      ],
    );
  }
}

/// Read-only Daily Rhythm history inspection card for the selected Calendar date.
class DailyRhythmCalendarDetailCard extends StatelessWidget {
  final DailyRhythmCalendarDayInspection inspection;

  const DailyRhythmCalendarDetailCard({
    super.key,
    required this.inspection,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final DaywellStatusTone badgeTone = switch (inspection.calendarStatus) {
      DailyRhythmCalendarDisplayStatus.complete => DaywellStatusTone.success,
      DailyRhythmCalendarDisplayStatus.partial => DaywellStatusTone.warning,
      DailyRhythmCalendarDisplayStatus.freezeProtected =>
        inspection.isProvisionalFreeze
            ? DaywellStatusTone.warning
            : DaywellStatusTone.info,
      DailyRhythmCalendarDisplayStatus.missed => DaywellStatusTone.error,
      DailyRhythmCalendarDisplayStatus.untouched ||
      DailyRhythmCalendarDisplayStatus.unrecorded =>
        DaywellStatusTone.info,
    };

    final bibleTime = _formatEthiopiaTime(inspection.bibleStudyCompletedAt);
    final prayerTime = _formatEthiopiaTime(inspection.prayerCompletedAt);
    final taskTime = _formatEthiopiaTime(inspection.taskReviewedAt);
    final financeTime = _formatEthiopiaTime(inspection.financeClosedAt);
    final ev = inspection.taskReviewEvidence;

    return DaywellCard(
      borderRadius: SharedDesignTokens.radiusLg,
      padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_outlined,
                        size: DaywellIconSize.sm,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Daily Rhythm history',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: semantic.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    inspection.ethiopianDateIso.isNotEmpty
                        ? '${inspection.dateIso} · Eth ${inspection.ethiopianDateIso}'
                        : inspection.dateIso,
                    style: textTheme.labelSmall?.copyWith(
                      color: semantic.textMuted,
                    ),
                  ),
                ],
              ),
              DaywellStatusBadge(
                label: inspection.shortMarkerGlyph.isNotEmpty
                    ? '${inspection.shortMarkerGlyph} ${inspection.statusLabel}'
                    : inspection.statusLabel,
                tone: badgeTone,
                showIcon: false,
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Text(
            inspection.detailSummary,
            style: textTheme.bodySmall?.copyWith(
              color: semantic.textSecondary,
            ),
          ),
          if (inspection.freezeExplanation != null) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            DaywellStatusBanner(
              tone: inspection.isProvisionalFreeze
                  ? DaywellStatusTone.warning
                  : DaywellStatusTone.info,
              icon: Icons.ac_unit,
              message: inspection.freezeExplanation!,
            ),
          ],
          if (inspection.hasRecordedHistory) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            _HistoryRow(
              icon: Icons.menu_book_outlined,
              label: 'Faith',
              status:
                  inspection.faithComplete ? 'Complete (2/2)' : 'Incomplete',
              tone: inspection.faithComplete
                  ? semantic.success
                  : semantic.textMuted,
              detail:
                  'Bible study: ${inspection.bibleStudyDone ? (bibleTime != null ? 'Done ($bibleTime)' : 'Done') : 'Not done'} · '
                  'Prayer: ${inspection.prayerDone ? (prayerTime != null ? 'Done ($prayerTime)' : 'Done') : 'Not done'}',
            ),
            const SizedBox(height: SharedDesignTokens.spacingXs),
            _HistoryRow(
              icon: Icons.fact_check_outlined,
              label: 'Tasks',
              status:
                  inspection.taskReviewConfirmed ? 'Reviewed' : 'Not confirmed',
              tone: inspection.taskReviewConfirmed
                  ? semantic.success
                  : semantic.textMuted,
              detail: [
                if (taskTime != null) 'Reviewed at $taskTime',
                if (ev != null)
                  'Overdue ${ev.overdueCount}, Today ${ev.todayCount}, My Day ${ev.plannedCount}',
                if (taskTime == null && ev == null)
                  'No daily task review recorded.',
              ].join(' · '),
            ),
            const SizedBox(height: SharedDesignTokens.spacingXs),
            _HistoryRow(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Finance',
              status: inspection.financeStatusLabel,
              tone: inspection.financeComplete
                  ? semantic.success
                  : inspection.financeCloseStatus ==
                          DailyRhythmFinanceCloseStatuses.needsReconfirmation
                      ? semantic.warning
                      : semantic.textMuted,
              detail: financeTime != null
                  ? 'Confirmed at $financeTime'
                  : 'No closing confirmation recorded.',
            ),
          ],
          if (inspection.lockNotice != null) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: DaywellIconSize.xs,
                  color: semantic.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    inspection.lockNotice!,
                    style: textTheme.labelSmall?.copyWith(
                      color: semantic.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String status;
  final Color tone;
  final String detail;

  const _HistoryRow({
    required this.icon,
    required this.label,
    required this.status,
    required this.tone,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingSm),
      decoration: BoxDecoration(
        color: semantic.surfaceSubtle,
        borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
        border: Border.all(color: semantic.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: DaywellIconSize.xs, color: tone),
              const SizedBox(width: 6),
              Text(
                label,
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: semantic.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                status,
                style: textTheme.labelSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            style: textTheme.bodySmall?.copyWith(
              color: semantic.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
