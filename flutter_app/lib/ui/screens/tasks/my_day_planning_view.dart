import 'package:flutter/material.dart';
import '../../../application/tasks/tasks_state.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/tasks/daily_planning_engine.dart';
import '../../../domain/tasks/task_models.dart';
import '../../../domain/tasks/task_recurrence_engine.dart';
import '../../widgets/shared_ui_widgets.dart';

/// Stage 2 My Day & Daily Planning workspace for Flutter.
///
/// Mirrors Web `MyDayPlanningView.tsx` while consuming canonical Flutter
/// `DaywellTheme` semantic tokens and shared UI primitives.
class MyDayPlanningView extends StatefulWidget {
  final TasksModuleState moduleState;
  final DailyPlanSnapshot snapshot;
  final ValueChanged<CalendarDate> onSelectDate;
  final ValueChanged<int> onStepDate;
  final VoidCallback onPickDate;
  final VoidCallback onJumpToToday;
  final ValueChanged<TaskEntity> onToggleTask;
  final ValueChanged<TaskEntity> onOpenTaskDetails;
  final void Function(String taskId, int delta) onMoveTaskOrder;
  final ValueChanged<TaskEntity> onRemoveFromDay;
  final void Function(String taskId, String action) onAddToDay;
  final VoidCallback onCarryForwardAll;
  final VoidCallback onCarryPastRemainingToToday;
  final VoidCallback onCreateTaskForDay;

  const MyDayPlanningView({
    super.key,
    required this.moduleState,
    required this.snapshot,
    required this.onSelectDate,
    required this.onStepDate,
    required this.onPickDate,
    required this.onJumpToToday,
    required this.onToggleTask,
    required this.onOpenTaskDetails,
    required this.onMoveTaskOrder,
    required this.onRemoveFromDay,
    required this.onAddToDay,
    required this.onCarryForwardAll,
    required this.onCarryPastRemainingToToday,
    required this.onCreateTaskForDay,
  });

  @override
  State<MyDayPlanningView> createState() => _MyDayPlanningViewState();
}

class _MyDayPlanningViewState extends State<MyDayPlanningView> {
  bool _showOtherActive = false;

  bool _matchesSearch(
    TaskEntity task,
    String query,
    Map<String, String> projectTitlesById,
  ) {
    if (query.isEmpty) return true;
    final projectTitle =
        task.projectId != null ? (projectTitlesById[task.projectId!] ?? '') : '';
    final hay = [
      task.title,
      task.description ?? '',
      projectTitle,
      ...task.labels,
    ].join(' ').toLowerCase();
    return hay.contains(query);
  }

  DaywellStatusTone _priorityTone(String priority) {
    switch (priority) {
      case 'urgent':
        return DaywellStatusTone.error;
      case 'high':
        return DaywellStatusTone.warning;
      default:
        return DaywellStatusTone.neutral;
    }
  }

  String _priorityLabel(String priority) {
    switch (priority) {
      case 'urgent':
        return 'Urgent';
      case 'high':
        return 'High';
      case 'low':
        return 'Low';
      default:
        return 'Medium';
    }
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final snapshot = widget.snapshot;
    final query = widget.moduleState.searchQuery.trim().toLowerCase();

    final projectTitlesById = <String, String>{
      for (final p in widget.moduleState.projects) p.id: p.title,
    };

    final remainingItems = query.isEmpty
        ? snapshot.remainingItems
        : snapshot.remainingItems
            .where((item) => _matchesSearch(item.task, query, projectTitlesById))
            .toList(growable: false);

    final completedItems = query.isEmpty
        ? snapshot.completedItems
        : snapshot.completedItems
            .where((item) => _matchesSearch(item.task, query, projectTitlesById))
            .toList(growable: false);

    final carryForwardIds = {
      for (final s in snapshot.carryForwardSuggestions) s.task.id,
    };
    final overdueIds = {
      for (final s in snapshot.overdueSuggestions) s.task.id,
    };

    final carryForwardSuggestions = snapshot.carryForwardSuggestions
        .where((s) => _matchesSearch(s.task, query, projectTitlesById))
        .toList(growable: false);

    final overdueSuggestions = snapshot.overdueSuggestions
        .where(
          (s) =>
              !carryForwardIds.contains(s.task.id) &&
              _matchesSearch(s.task, query, projectTitlesById),
        )
        .toList(growable: false);

    final scheduledSuggestions = snapshot.scheduledSuggestions
        .where(
          (s) =>
              !carryForwardIds.contains(s.task.id) &&
              !overdueIds.contains(s.task.id) &&
              _matchesSearch(s.task, query, projectTitlesById),
        )
        .toList(growable: false);

    final otherActiveTasks = query.isEmpty
        ? snapshot.otherActiveTasks
        : snapshot.otherActiveTasks
            .where((t) => _matchesSearch(t, query, projectTitlesById))
            .toList(growable: false);

    final historyDatesSet = <CalendarDate>{
      snapshot.todayDate,
      snapshot.selectedDate,
      ...snapshot.historyDates,
    };
    final historyDates = historyDatesSet.toList(growable: false)
      ..sort((a, b) => b.compareTo(a));
    final visibleHistoryDates =
        historyDates.length > 12 ? historyDates.sublist(0, 12) : historyDates;

    final carryablePastCount = snapshot.isPastDay
        ? snapshot.remainingItems
            .where(
              (item) => !DailyPlanningEngine.isTaskPlannedForDate(
                item.task,
                widget.moduleState.dailyPlanningEntries,
                snapshot.todayDate,
                today: snapshot.todayDate,
              ),
            )
            .length
        : 0;

    final totalSuggestionsCount = carryForwardSuggestions.length +
        overdueSuggestions.length +
        scheduledSuggestions.length;

    final double progressRatio = snapshot.totalPlannedCount == 0
        ? 0.0
        : snapshot.completedCount / snapshot.totalPlannedCount;

    return ListView(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
      children: [
        // Selected Day Header, Date Navigation & History Strip
        DaywellCard(
          padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
          borderRadius: SharedDesignTokens.radiusLg,
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
                      Icons.wb_sunny_outlined,
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
                              'My Day',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: semantic.textPrimary,
                              ),
                            ),
                            DaywellStatusBadge(
                              label: snapshot.isToday
                                  ? 'Today'
                                  : snapshot.isPastDay
                                      ? 'Past Day Review'
                                      : 'Planned Ahead',
                              tone: snapshot.isToday
                                  ? DaywellStatusTone.success
                                  : snapshot.isPastDay
                                      ? DaywellStatusTone.warning
                                      : DaywellStatusTone.info,
                              showIcon: false,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          SharedDateFormatter.formatDual(
                            snapshot.selectedDate,
                            useAmharic: false,
                          ),
                          style: textTheme.bodySmall?.copyWith(
                            color: semantic.textSecondary,
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
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DaywellIconButton(
                    icon: Icons.chevron_left,
                    tooltip: 'Previous day',
                    onPressed: () => widget.onStepDate(-1),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.onPickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(snapshot.selectedDate.toIsoString()),
                  ),
                  DaywellIconButton(
                    icon: Icons.chevron_right,
                    tooltip: 'Next day',
                    onPressed: () => widget.onStepDate(1),
                  ),
                  if (!snapshot.isToday)
                    DaywellButton(
                      label: 'Today',
                      variant: DaywellButtonVariant.secondary,
                      size: DaywellButtonSize.compact,
                      onPressed: widget.onJumpToToday,
                    ),
                ],
              ),
              const Divider(height: SharedDesignTokens.spacingMd),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history,
                        size: 14,
                        color: semantic.textMuted,
                      ),
                      const SizedBox(width: SharedDesignTokens.spacingXs),
                      Text(
                        'DAILY PLANNING HISTORY',
                        style: DaywellTypography.caption(
                          color: semantic.textMuted,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  Text(
                    '${snapshot.historyDates.length} recorded day(s)',
                    style: DaywellTypography.caption(
                      color: semantic.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final date in visibleHistoryDates)
                      Padding(
                        padding: const EdgeInsets.only(
                          right: SharedDesignTokens.spacingXs,
                        ),
                        child: ChoiceChip(
                          selected: date == snapshot.selectedDate,
                          label: Text(
                            date == snapshot.todayDate
                                ? 'Today · ${date.toIsoString()}'
                                : '${SharedDateFormatter.formatEthiopian(date.toEthiopian(), useAmharic: false, includeEra: false)} (${date.toIsoString()})',
                            style: const TextStyle(fontSize: 11),
                          ),
                          onSelected: (_) => widget.onSelectDate(date),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: SharedDesignTokens.spacingMd),
              DaywellProgressBar(
                value: progressRatio,
                label:
                    '${snapshot.completedCount} of ${snapshot.totalPlannedCount} completed',
                valueText:
                    '${snapshot.remainingCount} remaining · ${snapshot.progressPercentage}%',
                tone: snapshot.progressPercentage == 100 &&
                        snapshot.totalPlannedCount > 0
                    ? DaywellStatusTone.success
                    : null,
                semanticLabel: 'My Day completion progress',
              ),
              if (snapshot.dismissedCount > 0) ...[
                const SizedBox(height: SharedDesignTokens.spacingXs),
                Text(
                  "${snapshot.dismissedCount} task(s) removed from this day's plan (tasks remain active in Tasks).",
                  style: DaywellTypography.caption(color: semantic.textMuted),
                ),
              ],
            ],
          ),
        ),

        if (snapshot.isPastDay && snapshot.remainingCount > 0) ...[
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          DaywellStatusBanner(
            tone: DaywellStatusTone.warning,
            title: 'Unfinished tasks from this day',
            message: carryablePastCount > 0
                ? "$carryablePastCount unfinished task(s) from ${snapshot.selectedDate.toIsoString()} are not yet in Today's plan."
                : 'All remaining unfinished tasks from ${snapshot.selectedDate.toIsoString()} are already planned for Today.',
            actionLabel: carryablePastCount > 0
                ? 'Carry $carryablePastCount to Today'
                : null,
            onActionPressed: carryablePastCount > 0
                ? widget.onCarryPastRemainingToToday
                : null,
          ),
        ],

        if (!snapshot.isPastDay &&
            snapshot.carryForwardSuggestions.isNotEmpty) ...[
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          DaywellStatusBanner(
            tone: DaywellStatusTone.info,
            title: 'Unfinished tasks from previous days',
            message:
                '${snapshot.carryForwardSuggestions.length} unfinished task(s) from earlier planned days can be carried forward without duplicates.',
            actionLabel:
                'Carry forward all (${snapshot.carryForwardSuggestions.length})',
            onActionPressed: widget.onCarryForwardAll,
          ),
        ],

        const SizedBox(height: SharedDesignTokens.spacingCompact),

        // Remaining for This Day
        DaywellCard(
          padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
          borderRadius: SharedDesignTokens.radiusLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DaywellSectionHeader(
                title: 'Remaining for This Day',
                count: remainingItems.length,
                actionLabel: 'Add Task',
                onActionPressed: widget.onCreateTaskForDay,
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
              if (remainingItems.isEmpty)
                snapshot.totalPlannedCount == 0
                    ? DaywellEmptyState(
                        icon: Icons.wb_sunny_outlined,
                        message: 'Nothing planned for this day yet',
                        subtitle:
                            'Add overdue, scheduled, carried-forward, or active tasks below without duplicating tasks.',
                        actionLabel: 'Create Task for Day',
                        onActionPressed: widget.onCreateTaskForDay,
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: SharedDesignTokens.spacingSm,
                        ),
                        child: Text(
                          'All planned tasks for this day are completed!',
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
              else
                for (var i = 0; i < remainingItems.length; i++)
                  _buildPlannedItemRow(
                    context,
                    item: remainingItems[i],
                    index: i,
                    totalRemaining: remainingItems.length,
                    isRemaining: true,
                    projectTitlesById: projectTitlesById,
                    todayDate: snapshot.todayDate,
                  ),
            ],
          ),
        ),

        if (completedItems.isNotEmpty) ...[
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          DaywellCard(
            padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
            borderRadius: SharedDesignTokens.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DaywellSectionHeader(
                  title: 'Completed for This Day',
                  count: completedItems.length,
                ),
                const SizedBox(height: SharedDesignTokens.spacingSm),
                for (var i = 0; i < completedItems.length; i++)
                  _buildPlannedItemRow(
                    context,
                    item: completedItems[i],
                    index: i,
                    totalRemaining: completedItems.length,
                    isRemaining: false,
                    projectTitlesById: projectTitlesById,
                    todayDate: snapshot.todayDate,
                  ),
              ],
            ),
          ),
        ],

        const SizedBox(height: SharedDesignTokens.spacingCompact),

        // Plan & Add Tasks
        DaywellCard(
          padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
          borderRadius: SharedDesignTokens.radiusLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DaywellSectionHeader(
                title: 'Plan & Add Tasks',
                count:
                    totalSuggestionsCount > 0 ? totalSuggestionsCount : null,
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
              if (carryForwardSuggestions.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'CARRY FORWARD FROM PREVIOUS DAYS (${carryForwardSuggestions.length})',
                        style: DaywellTypography.caption(
                          color: semantic.textSecondary,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (!snapshot.isPastDay)
                      DaywellButton(
                        label: 'Carry forward all',
                        variant: DaywellButtonVariant.secondary,
                        size: DaywellButtonSize.compact,
                        leadingIcon: Icons.arrow_forward,
                        onPressed: widget.onCarryForwardAll,
                      ),
                  ],
                ),
                const SizedBox(height: SharedDesignTokens.spacingXs),
                for (final suggestion in carryForwardSuggestions)
                  _buildSuggestionRow(
                    context,
                    task: suggestion.task,
                    actionLabel: 'Carry',
                    onAdd: () => widget.onAddToDay(
                      suggestion.task.id,
                      DailyPlanningActions.carriedForward,
                    ),
                    badges: [
                      if (suggestion.sourcePlanDate != null)
                        DaywellStatusBadge(
                          label:
                              'From ${suggestion.sourcePlanDate!.toIsoString()}',
                          tone: DaywellStatusTone.info,
                          showIcon: false,
                        ),
                      if (suggestion.task.dueDate != null &&
                          suggestion.task.dueDate!.isBefore(snapshot.todayDate))
                        const DaywellStatusBadge(
                          label: 'Overdue',
                          tone: DaywellStatusTone.error,
                          showIcon: false,
                        ),
                    ],
                  ),
                const SizedBox(height: SharedDesignTokens.spacingSm),
              ],
              if (overdueSuggestions.isNotEmpty) ...[
                Text(
                  'OVERDUE TASKS (${overdueSuggestions.length})',
                  style: DaywellTypography.caption(
                    color: semantic.error,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: SharedDesignTokens.spacingXs),
                for (final suggestion in overdueSuggestions)
                  _buildSuggestionRow(
                    context,
                    task: suggestion.task,
                    actionLabel: 'Add',
                    onAdd: () => widget.onAddToDay(
                      suggestion.task.id,
                      DailyPlanningActions.planned,
                    ),
                    badges: [
                      if (suggestion.task.dueDate != null)
                        DaywellStatusBadge(
                          label:
                              'Overdue · ${suggestion.task.dueDate!.toIsoString()}',
                          tone: DaywellStatusTone.error,
                          showIcon: false,
                        ),
                      DaywellStatusBadge(
                        label: _priorityLabel(suggestion.task.priority),
                        tone: _priorityTone(suggestion.task.priority),
                        showIcon: false,
                      ),
                    ],
                  ),
                const SizedBox(height: SharedDesignTokens.spacingSm),
              ],
              if (scheduledSuggestions.isNotEmpty) ...[
                Text(
                  'DUE OR SCHEDULED FOR ${snapshot.selectedDate.toIsoString()} (${scheduledSuggestions.length})',
                  style: DaywellTypography.caption(
                    color: colorScheme.primary,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: SharedDesignTokens.spacingXs),
                for (final suggestion in scheduledSuggestions)
                  _buildSuggestionRow(
                    context,
                    task: suggestion.task,
                    actionLabel: 'Add',
                    onAdd: () => widget.onAddToDay(
                      suggestion.task.id,
                      DailyPlanningActions.planned,
                    ),
                    badges: [
                      DaywellStatusBadge(
                        label: suggestion.task.dueDate == snapshot.selectedDate
                            ? 'Due this day'
                            : 'Scheduled this day',
                        tone: DaywellStatusTone.success,
                        showIcon: false,
                      ),
                    ],
                  ),
                const SizedBox(height: SharedDesignTokens.spacingSm),
              ],
              if (otherActiveTasks.isNotEmpty) ...[
                const Divider(height: SharedDesignTokens.spacingCompact),
                InkWell(
                  borderRadius:
                      BorderRadius.circular(SharedDesignTokens.radiusSm),
                  onTap: () =>
                      setState(() => _showOtherActive = !_showOtherActive),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: SharedDesignTokens.spacingXs,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Other Active Tasks (${otherActiveTasks.length})',
                          style: textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: semantic.textSecondary,
                          ),
                        ),
                        Icon(
                          _showOtherActive
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: DaywellIconSize.md,
                          color: semantic.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showOtherActive) ...[
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                  for (final task in otherActiveTasks)
                    _buildSuggestionRow(
                      context,
                      task: task,
                      actionLabel: 'Add',
                      onAdd: () => widget.onAddToDay(
                        task.id,
                        DailyPlanningActions.planned,
                      ),
                      badges: [
                        DaywellStatusBadge(
                          label: _priorityLabel(task.priority),
                          tone: _priorityTone(task.priority),
                          showIcon: false,
                        ),
                        if (task.dueDate != null)
                          DaywellStatusBadge(
                            label: 'Due ${task.dueDate!.toIsoString()}',
                            tone: DaywellStatusTone.neutral,
                            showIcon: false,
                          ),
                      ],
                    ),
                ],
              ],
              if (totalSuggestionsCount == 0 && otherActiveTasks.isEmpty)
                Text(
                  'No additional active tasks waiting to be planned for this day.',
                  style: textTheme.bodySmall?.copyWith(
                    color: semantic.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlannedItemRow(
    BuildContext context, {
    required DailyPlanItem item,
    required int index,
    required int totalRemaining,
    required bool isRemaining,
    required Map<String, String> projectTitlesById,
    required CalendarDate todayDate,
  }) {
    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final task = item.task;
    final isOverdue =
        task.dueDate != null && task.dueDate!.isBefore(todayDate);
    final projectName =
        task.projectId != null ? projectTitlesById[task.projectId!] : null;

    return Container(
      margin: const EdgeInsets.only(bottom: SharedDesignTokens.spacingSm),
      padding: const EdgeInsets.all(SharedDesignTokens.spacingSm),
      decoration: BoxDecoration(
        color: semantic.surfaceSubtle,
        borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
        border: Border.all(color: semantic.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: item.isCompletedForDay,
            activeColor: colorScheme.primary,
            onChanged: (_) => widget.onToggleTask(task),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
              onTap: () => widget.onOpenTaskDetails(task),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: SharedDesignTokens.spacingXs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: item.isCompletedForDay
                            ? semantic.textDisabled
                            : semantic.textPrimary,
                        decoration: item.isCompletedForDay
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    Wrap(
                      spacing: SharedDesignTokens.spacingXs,
                      runSpacing: SharedDesignTokens.spacingXs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DaywellStatusBadge(
                          label: _priorityLabel(task.priority),
                          tone: _priorityTone(task.priority),
                          showIcon: false,
                        ),
                        if (item.isCarriedForward)
                          const DaywellStatusBadge(
                            label: 'Carried forward',
                            tone: DaywellStatusTone.info,
                            showIcon: false,
                          ),
                        if (item.completedLater)
                          const DaywellStatusBadge(
                            label: 'Completed later',
                            tone: DaywellStatusTone.success,
                            showIcon: false,
                          ),
                        if (!item.isCompletedForDay && isOverdue)
                          DaywellStatusBadge(
                            label: 'Overdue · ${task.dueDate!.toIsoString()}',
                            tone: DaywellStatusTone.error,
                            showIcon: false,
                          ),
                        if (projectName != null && projectName.isNotEmpty)
                          Text(
                            projectName,
                            style: DaywellTypography.caption(
                              color: semantic.textSecondary,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                        if (task.dueDate != null && !isOverdue)
                          Text(
                            'Due ${task.dueDate!.toIsoString()}',
                            style: DaywellTypography.caption(
                              color: colorScheme.primary,
                            ),
                          ),
                        if (TaskRecurrenceEngine.resolveEffectiveConfig(task) !=
                            null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.repeat,
                                size: 12,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                TaskRecurrenceEngine.formatSummary(
                                  TaskRecurrenceEngine.resolveEffectiveConfig(
                                    task,
                                  ),
                                ),
                                style: DaywellTypography.caption(
                                  color: semantic.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        if (task.subtasks.isNotEmpty)
                          Text(
                            '${task.completedSubtaskCount}/${task.subtasks.length} subtasks',
                            style: DaywellTypography.caption(
                              color: semantic.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRemaining) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  tooltip: 'Move ${task.title} up',
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: index == 0
                      ? null
                      : () => widget.onMoveTaskOrder(task.id, -1),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  tooltip: 'Move ${task.title} down',
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: index >= totalRemaining - 1
                      ? null
                      : () => widget.onMoveTaskOrder(task.id, 1),
                ),
              ],
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove ${task.title} from My Day',
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                padding: EdgeInsets.zero,
                onPressed: () => widget.onRemoveFromDay(task),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionRow(
    BuildContext context, {
    required TaskEntity task,
    required String actionLabel,
    required VoidCallback onAdd,
    required List<Widget> badges,
  }) {
    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final recConfig = TaskRecurrenceEngine.resolveEffectiveConfig(task);
    final allBadges = <Widget>[
      ...badges,
      if (recConfig != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.repeat,
              size: 12,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 2),
            Text(
              TaskRecurrenceEngine.formatSummary(recConfig),
              style: DaywellTypography.caption(
                color: semantic.textSecondary,
              ),
            ),
          ],
        ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: SharedDesignTokens.spacingXs),
      padding: const EdgeInsets.symmetric(
        horizontal: SharedDesignTokens.spacingSm,
        vertical: SharedDesignTokens.spacingSm,
      ),
      decoration: BoxDecoration(
        color: semantic.surfaceSubtle,
        borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
        border: Border.all(color: semantic.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
              onTap: () => widget.onOpenTaskDetails(task),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: semantic.textPrimary,
                    ),
                  ),
                  if (allBadges.isNotEmpty) ...[
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    Wrap(
                      spacing: SharedDesignTokens.spacingXs,
                      runSpacing: SharedDesignTokens.spacingXs,
                      children: allBadges,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: SharedDesignTokens.spacingSm),
          DaywellButton(
            label: actionLabel,
            variant: DaywellButtonVariant.outlined,
            size: DaywellButtonSize.compact,
            leadingIcon: Icons.add,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}
