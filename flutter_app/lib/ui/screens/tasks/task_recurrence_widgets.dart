import 'package:flutter/material.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/tasks/task_models.dart';
import '../../../domain/tasks/task_recurrence_engine.dart';
import '../../widgets/shared_ui_widgets.dart';

class TaskRecurrenceEditorSection extends StatelessWidget {
  final bool isRecurring;
  final ValueChanged<bool> onToggleRecurring;
  final String frequency;
  final ValueChanged<String> onFrequencyChanged;
  final int interval;
  final ValueChanged<int> onIntervalChanged;
  final List<int> weekdays;
  final ValueChanged<List<int>> onWeekdaysChanged;
  final CalendarDate? startDate;
  final ValueChanged<CalendarDate?> onStartDateChanged;
  final CalendarDate? endDate;
  final ValueChanged<CalendarDate?> onEndDateChanged;
  final String repeatFrom;
  final ValueChanged<String> onRepeatFromChanged;
  final Future<CalendarDate?> Function(CalendarDate? current) onPickDate;
  final CalendarDate? dueDate;
  final CalendarDate? scheduledDate;
  final String? errorText;

  const TaskRecurrenceEditorSection({
    super.key,
    required this.isRecurring,
    required this.onToggleRecurring,
    required this.frequency,
    required this.onFrequencyChanged,
    required this.interval,
    required this.onIntervalChanged,
    required this.weekdays,
    required this.onWeekdaysChanged,
    required this.startDate,
    required this.onStartDateChanged,
    required this.endDate,
    required this.onEndDateChanged,
    required this.repeatFrom,
    required this.onRepeatFromChanged,
    required this.onPickDate,
    this.dueDate,
    this.scheduledDate,
    this.errorText,
  });

  static const List<(String, String, String, String)> _frequencyOptions = [
    ('daily', 'Daily', 'day', 'days'),
    ('weekly', 'Weekly', 'week', 'weeks'),
    ('monthly', 'Monthly', 'month', 'months'),
    ('yearly', 'Yearly', 'year', 'years'),
  ];

  static const List<(int, String)> _weekdayOptions = [
    (1, 'Mon'),
    (2, 'Tue'),
    (3, 'Wed'),
    (4, 'Thu'),
    (5, 'Fri'),
    (6, 'Sat'),
    (7, 'Sun'),
  ];

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;
    final safeInterval = interval >= 1 ? interval : 1;
    final freqMeta = _frequencyOptions.firstWhere(
      (opt) => opt.$1 == frequency,
      orElse: () => _frequencyOptions[1],
    );
    final unitLabel = safeInterval == 1 ? freqMeta.$3 : freqMeta.$4;

    final draftConfig = TaskRecurrenceConfig(
      frequency: frequency,
      interval: safeInterval,
      weekdays: frequency == 'weekly' && weekdays.isNotEmpty
          ? List<int>.unmodifiable(weekdays)
          : null,
      startDate: startDate,
      endDate: endDate,
      repeatFrom: repeatFrom,
    );
    final summary = TaskRecurrenceEngine.formatSummary(draftConfig);
    final previewDate = isRecurring
        ? TaskRecurrenceEngine.previewNextOccurrenceDate(
            TaskEntity(
              id: 'preview',
              title: 'Preview',
              dueDate: dueDate,
              scheduledDate: scheduledDate,
            ),
            draftConfig,
          )
        : null;

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            secondary: Icon(Icons.repeat, color: colorScheme.primary),
            title: Text(
              'Recurring Task',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: semantic.textPrimary,
                  ),
            ),
            subtitle: isRecurring && summary.isNotEmpty
                ? Text(
                    summary,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  )
                : Text(
                    'Repeat automatically on completion',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: semantic.textMuted,
                        ),
                  ),
            value: isRecurring,
            onChanged: onToggleRecurring,
          ),
          if (isRecurring) ...[
            const Divider(),
            const SizedBox(height: SharedDesignTokens.spacingXs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DaywellDropdownField<String>(
                    label: 'Frequency',
                    value: frequency,
                    items: [
                      for (final opt in _frequencyOptions)
                        DropdownMenuItem<String>(
                          value: opt.$1,
                          child: Text(opt.$2),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) onFrequencyChanged(v);
                    },
                  ),
                ),
                const SizedBox(width: SharedDesignTokens.spacingSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Every ($unitLabel)',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: semantic.textSecondary,
                                ),
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingXs),
                      Container(
                        decoration: BoxDecoration(
                          color: semantic.surfaceSubtle,
                          borderRadius: BorderRadius.circular(
                            SharedDesignTokens.radiusMd,
                          ),
                          border: Border.all(color: semantic.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove, size: 18),
                              tooltip: 'Decrease repeat interval',
                              onPressed: safeInterval > 1
                                  ? () => onIntervalChanged(safeInterval - 1)
                                  : null,
                            ),
                            Text(
                              '$safeInterval',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: semantic.textPrimary,
                                  ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, size: 18),
                              tooltip: 'Increase repeat interval',
                              onPressed: () =>
                                  onIntervalChanged(safeInterval + 1),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (frequency == 'weekly') ...[
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              Text(
                'Repeat On Days (optional)',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: semantic.textSecondary,
                    ),
              ),
              const SizedBox(height: SharedDesignTokens.spacingXs),
              Wrap(
                spacing: SharedDesignTokens.spacingXs,
                runSpacing: SharedDesignTokens.spacingXs,
                children: [
                  for (final wd in _weekdayOptions)
                    FilterChip(
                      label: Text(wd.$2),
                      selected: weekdays.contains(wd.$1),
                      onSelected: (selected) {
                        final next = Set<int>.from(weekdays);
                        if (selected) {
                          next.add(wd.$1);
                        } else {
                          next.remove(wd.$1);
                        }
                        final sorted = next.toList()..sort();
                        onWeekdaysChanged(sorted);
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: SharedDesignTokens.spacingCompact),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start Date',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: semantic.textSecondary,
                                ),
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingXs),
                      Wrap(
                        spacing: SharedDesignTokens.spacingXs,
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.event, size: 16),
                            label: Text(
                              startDate != null
                                  ? startDate!.toIsoString()
                                  : 'Set Start',
                            ),
                            onPressed: () async {
                              final picked = await onPickDate(startDate);
                              if (picked != null) {
                                onStartDateChanged(picked);
                              }
                            },
                          ),
                          if (startDate != null)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              tooltip: 'Clear start date',
                              onPressed: () => onStartDateChanged(null),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SharedDesignTokens.spacingSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'End Date (optional)',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: semantic.textSecondary,
                                ),
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingXs),
                      Wrap(
                        spacing: SharedDesignTokens.spacingXs,
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.event_available, size: 16),
                            label: Text(
                              endDate != null
                                  ? endDate!.toIsoString()
                                  : 'No End Date',
                            ),
                            onPressed: () async {
                              final picked = await onPickDate(endDate);
                              if (picked != null) {
                                onEndDateChanged(picked);
                              }
                            },
                          ),
                          if (endDate != null)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              tooltip: 'Clear end date',
                              onPressed: () => onEndDateChanged(null),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: SharedDesignTokens.spacingCompact),
            Text(
              'Repeat Based On',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: semantic.textSecondary,
                  ),
            ),
            const SizedBox(height: SharedDesignTokens.spacingXs),
            Wrap(
              spacing: SharedDesignTokens.spacingSm,
              children: [
                ChoiceChip(
                  label: const Text('Due Date'),
                  selected: repeatFrom != 'completion_date',
                  onSelected: (_) => onRepeatFromChanged('due_date'),
                ),
                ChoiceChip(
                  label: const Text('Completion Date'),
                  selected: repeatFrom == 'completion_date',
                  onSelected: (_) => onRepeatFromChanged('completion_date'),
                ),
              ],
            ),
            if (errorText != null && errorText!.trim().isNotEmpty) ...[
              const SizedBox(height: SharedDesignTokens.spacingSm),
              Text(
                errorText!,
                style: DaywellTypography.caption(color: semantic.error),
              ),
            ],
            const SizedBox(height: SharedDesignTokens.spacingSm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(SharedDesignTokens.spacingSm),
              decoration: BoxDecoration(
                color: semantic.surfaceSubtle,
                borderRadius:
                    BorderRadius.circular(SharedDesignTokens.radiusSm),
                border: Border.all(color: semantic.border),
              ),
              child: Text(
                previewDate != null
                    ? 'Next occurrence: ${SharedDateFormatter.formatDual(previewDate, useAmharic: false)}'
                    : 'Next occurrence: No further occurrence (past end date)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: semantic.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class TaskRecurrenceDetailsSection extends StatelessWidget {
  final TaskEntity task;
  final VoidCallback? onSkipOccurrence;
  final VoidCallback? onRescheduleOccurrence;
  final VoidCallback? onEditRecurrence;
  final VoidCallback? onStopRecurrence;

  const TaskRecurrenceDetailsSection({
    super.key,
    required this.task,
    this.onSkipOccurrence,
    this.onRescheduleOccurrence,
    this.onEditRecurrence,
    this.onStopRecurrence,
  });

  @override
  Widget build(BuildContext context) {
    final config = TaskRecurrenceEngine.resolveEffectiveConfig(task);
    if (config == null) return const SizedBox.shrink();

    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;
    final summary = TaskRecurrenceEngine.formatSummary(config);
    final nextPreview =
        TaskRecurrenceEngine.previewNextOccurrenceDate(task, config);

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.repeat, size: 18, color: colorScheme.primary),
              const SizedBox(width: SharedDesignTokens.spacingXs),
              Expanded(
                child: Text(
                  'Recurrence: $summary',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: semantic.textPrimary,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingXs),
          Text(
            'Repeat from: ${config.repeatFrom == 'completion_date' ? 'Completion date' : 'Due date'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: semantic.textSecondary,
                ),
          ),
          if (config.startDate != null)
            Text(
              'Starts: ${SharedDateFormatter.formatDual(config.startDate!, useAmharic: false)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: semantic.textSecondary,
                  ),
            ),
          if (config.endDate != null)
            Text(
              'Ends: ${SharedDateFormatter.formatDual(config.endDate!, useAmharic: false)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: semantic.textSecondary,
                  ),
            ),
          Text(
            nextPreview != null
                ? 'Next occurrence: ${SharedDateFormatter.formatDual(nextPreview, useAmharic: false)}'
                : 'Next occurrence: Ends after current occurrence',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (!task.isArchived) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            Wrap(
              spacing: SharedDesignTokens.spacingSm,
              runSpacing: SharedDesignTokens.spacingXs,
              children: [
                if (!task.isCompleted && onSkipOccurrence != null)
                  DaywellButton(
                    label: 'Skip Occurrence',
                    variant: DaywellButtonVariant.outlined,
                    size: DaywellButtonSize.compact,
                    leadingIcon: Icons.fast_forward,
                    onPressed: onSkipOccurrence,
                  ),
                if (!task.isCompleted && onRescheduleOccurrence != null)
                  DaywellButton(
                    label: 'Reschedule',
                    variant: DaywellButtonVariant.outlined,
                    size: DaywellButtonSize.compact,
                    leadingIcon: Icons.event,
                    onPressed: onRescheduleOccurrence,
                  ),
                if (onEditRecurrence != null)
                  DaywellButton(
                    label: 'Edit Schedule',
                    variant: DaywellButtonVariant.outlined,
                    size: DaywellButtonSize.compact,
                    leadingIcon: Icons.edit_outlined,
                    onPressed: onEditRecurrence,
                  ),
                if (onStopRecurrence != null)
                  DaywellButton(
                    label: 'Stop Recurrence',
                    variant: DaywellButtonVariant.destructive,
                    size: DaywellButtonSize.compact,
                    leadingIcon: Icons.cancel_outlined,
                    onPressed: onStopRecurrence,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
