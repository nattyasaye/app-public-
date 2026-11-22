import 'package:flutter/material.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/tasks/task_models.dart';
import '../../../domain/tasks/task_reminder_engine.dart';
import '../../widgets/shared_ui_widgets.dart';

String _presetChipLabel(TaskReminderPreset preset) {
  switch (preset) {
    case TaskReminderPreset.atTime:
      return 'At time';
    case TaskReminderPreset.fifteenMinutesBefore:
      return '15m before';
    case TaskReminderPreset.oneHourBefore:
      return '1h before';
    case TaskReminderPreset.oneDayBefore:
      return '1d before';
    case TaskReminderPreset.custom:
      return 'Custom';
  }
}

String _describeAnchor({
  CalendarDate? dueDate,
  CalendarDate? scheduledDate,
  String? scheduledTime,
}) {
  final probe = TaskEntity(
    id: 'anchor-probe',
    title: 'Probe',
    dueDate: dueDate,
    scheduledDate: scheduledDate,
    scheduledTime: scheduledTime,
  );
  final anchor = TaskReminderEngine.resolveAnchor(probe);
  if (anchor == null) {
    return 'No scheduled or due date set — defaults to next 09:00 EAT';
  }
  if (anchor.source == 'scheduled') {
    return anchor.hasExplicitTime
        ? 'Anchored to scheduled time (${anchor.time.toIsoString()} EAT)'
        : 'Anchored to scheduled date · ${anchor.time.toIsoString()} EAT default';
  }
  return anchor.hasExplicitTime
      ? 'Anchored to due date · ${anchor.time.toIsoString()} EAT'
      : 'Anchored to due date · 09:00 EAT default';
}

class TaskReminderEditorSection extends StatelessWidget {
  final bool isEnabled;
  final ValueChanged<bool> onToggleReminder;
  final TaskReminderPreset preset;
  final ValueChanged<TaskReminderPreset> onPresetChanged;
  final CalendarDate? customDate;
  final ValueChanged<CalendarDate?> onCustomDateChanged;
  final DayTimeOfDay? customTime;
  final ValueChanged<DayTimeOfDay?> onCustomTimeChanged;
  final Future<CalendarDate?> Function(CalendarDate? current) onPickDate;
  final Future<DayTimeOfDay?> Function(DayTimeOfDay? current) onPickTime;
  final CalendarDate? dueDate;
  final CalendarDate? scheduledDate;
  final String? scheduledTime;
  final VoidCallback? onRequestPermission;
  final bool? notificationPermissionGranted;

  const TaskReminderEditorSection({
    super.key,
    required this.isEnabled,
    required this.onToggleReminder,
    required this.preset,
    required this.onPresetChanged,
    required this.customDate,
    required this.onCustomDateChanged,
    required this.customTime,
    required this.onCustomTimeChanged,
    required this.onPickDate,
    required this.onPickTime,
    this.dueDate,
    this.scheduledDate,
    this.scheduledTime,
    this.onRequestPermission,
    this.notificationPermissionGranted,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;
    final probe = TaskEntity(
      id: 'preview',
      title: 'Preview',
      dueDate: dueDate,
      scheduledDate: scheduledDate,
      scheduledTime: scheduledTime,
    );
    final previewTrigger = isEnabled
        ? TaskReminderEngine.computeTriggerFromPreset(
            task: probe,
            preset: preset,
            customDate: customDate,
            customTime: customTime,
          )
        : null;
    final summary = previewTrigger != null
        ? TaskReminderEngine.formatReminderSummary(previewTrigger)
        : null;

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            secondary: Icon(
              isEnabled
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_none_outlined,
              color: colorScheme.primary,
            ),
            title: Text(
              'Task Reminder',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: semantic.textPrimary,
                  ),
            ),
            subtitle: Text(
              isEnabled && summary != null
                  ? summary
                  : 'Notify before or at task time',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isEnabled && summary != null
                        ? colorScheme.primary
                        : semantic.textMuted,
                    fontWeight: isEnabled && summary != null
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
            ),
            value: isEnabled,
            onChanged: onToggleReminder,
          ),
          if (isEnabled) ...[
            const Divider(),
            const SizedBox(height: SharedDesignTokens.spacingXs),
            Text(
              'Reminder Timing',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: semantic.textSecondary,
                  ),
            ),
            const SizedBox(height: SharedDesignTokens.spacingXs),
            Wrap(
              spacing: SharedDesignTokens.spacingXs,
              runSpacing: SharedDesignTokens.spacingXs,
              children: [
                for (final option in TaskReminderPreset.values)
                  ChoiceChip(
                    label: Text(_presetChipLabel(option)),
                    selected: preset == option,
                    onSelected: (_) {
                      if (option == TaskReminderPreset.custom &&
                          (customDate == null || customTime == null)) {
                        final anchor = TaskReminderEngine.resolveAnchor(probe);
                        final fallback = TaskReminderEngine
                            .defaultFallbackEthiopiaDateTime();
                        if (customDate == null) {
                          onCustomDateChanged(anchor?.date ?? fallback.date);
                        }
                        if (customTime == null) {
                          onCustomTimeChanged(
                            anchor?.time ?? fallback.timeOfDay,
                          );
                        }
                      }
                      onPresetChanged(option);
                    },
                  ),
              ],
            ),
            if (preset == TaskReminderPreset.custom) ...[
              const SizedBox(height: SharedDesignTokens.spacingSm),
              Wrap(
                spacing: SharedDesignTokens.spacingSm,
                runSpacing: SharedDesignTokens.spacingXs,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.event, size: 16),
                    label: Text(
                      customDate != null
                          ? customDate!.toIsoString()
                          : 'Pick Date',
                    ),
                    onPressed: () async {
                      final picked = await onPickDate(customDate);
                      if (picked != null) {
                        onCustomDateChanged(picked);
                      }
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.schedule, size: 16),
                    label: Text(
                      customTime != null
                          ? '${customTime!.toIsoString()} EAT'
                          : 'Pick Time',
                    ),
                    onPressed: () async {
                      final picked = await onPickTime(customTime);
                      if (picked != null) {
                        onCustomTimeChanged(picked);
                      }
                    },
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: SharedDesignTokens.spacingXs),
              Text(
                _describeAnchor(
                  dueDate: dueDate,
                  scheduledDate: scheduledDate,
                  scheduledTime: scheduledTime,
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: semantic.textSecondary,
                    ),
              ),
            ],
            if (summary != null) ...[
              const SizedBox(height: SharedDesignTokens.spacingSm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(SharedDesignTokens.spacingSm),
                decoration: BoxDecoration(
                  color: semantic.surfaceSubtle,
                  borderRadius: BorderRadius.circular(
                    SharedDesignTokens.radiusSm,
                  ),
                  border: Border.all(color: semantic.border),
                ),
                child: Text(
                  'Fires at: $summary',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: semantic.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
            if (onRequestPermission != null &&
                notificationPermissionGranted == false) ...[
              const SizedBox(height: SharedDesignTokens.spacingSm),
              DaywellButton(
                label: 'Allow Notifications',
                variant: DaywellButtonVariant.outlined,
                size: DaywellButtonSize.compact,
                leadingIcon: Icons.notifications_active_outlined,
                onPressed: onRequestPermission,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class TaskReminderDetailsSection extends StatefulWidget {
  final TaskEntity task;
  final TaskReminderEntity? reminder;
  final ValueChanged<DateTime> onSaveReminder;
  final VoidCallback onRemoveReminder;
  final VoidCallback? onRequestPermission;
  final bool? notificationPermissionGranted;

  const TaskReminderDetailsSection({
    super.key,
    required this.task,
    required this.reminder,
    required this.onSaveReminder,
    required this.onRemoveReminder,
    this.onRequestPermission,
    this.notificationPermissionGranted,
  });

  @override
  State<TaskReminderDetailsSection> createState() =>
      _TaskReminderDetailsSectionState();
}

class _TaskReminderDetailsSectionState
    extends State<TaskReminderDetailsSection> {
  bool _isEditing = false;
  late TaskReminderPreset _preset;
  CalendarDate? _customDate;
  DayTimeOfDay? _customTime;

  @override
  void initState() {
    super.initState();
    _syncFromProps();
  }

  @override
  void didUpdateWidget(covariant TaskReminderDetailsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id ||
        oldWidget.reminder?.triggerTimeUtc != widget.reminder?.triggerTimeUtc ||
        oldWidget.reminder?.isActive != widget.reminder?.isActive) {
      _syncFromProps();
    }
  }

  void _syncFromProps() {
    _isEditing = false;
    final rem = widget.reminder;
    if (rem != null) {
      _preset = TaskReminderEngine.inferPreset(widget.task, rem.triggerTimeUtc);
      final wall = LocalDateTime.fromUtcInstant(rem.triggerTimeUtc);
      _customDate = wall.date;
      _customTime = wall.timeOfDay;
    } else {
      final anchor = TaskReminderEngine.resolveAnchor(widget.task);
      final fallback = TaskReminderEngine.defaultFallbackEthiopiaDateTime();
      _preset = TaskReminderPreset.atTime;
      _customDate = anchor?.date ?? fallback.date;
      _customTime = anchor?.time ?? fallback.timeOfDay;
    }
  }

  Future<CalendarDate?> _pickDate(CalendarDate? current) async {
    final seed = current ?? CalendarDate.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(seed.year, seed.month, seed.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return null;
    return CalendarDate(
      year: picked.year,
      month: picked.month,
      day: picked.day,
    );
  }

  Future<DayTimeOfDay?> _pickTime(DayTimeOfDay? current) async {
    final seed = current ??
        DayTimeOfDay(
          hour: TaskReminderEngine.defaultHour,
          minute: TaskReminderEngine.defaultMinute,
        );
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: seed.hour, minute: seed.minute),
    );
    if (picked == null) return null;
    return DayTimeOfDay(hour: picked.hour, minute: picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;
    final rem = widget.reminder;

    final String pausedLabel = widget.task.isArchived
        ? 'Paused (Archived)'
        : widget.task.isCompleted
            ? 'Paused (Completed)'
            : widget.task.status == 'cancelled'
                ? 'Paused (Cancelled)'
                : 'Paused';

    final String? summary = rem != null
        ? TaskReminderEngine.formatReminderSummary(rem.triggerTimeUtc)
        : null;
    final LocalDateTime? triggerWall =
        rem != null ? LocalDateTime.fromUtcInstant(rem.triggerTimeUtc) : null;
    final TaskReminderPreset? inferred = rem != null
        ? TaskReminderEngine.inferPreset(widget.task, rem.triggerTimeUtc)
        : null;

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                rem != null && rem.isActive
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_none_outlined,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: SharedDesignTokens.spacingXs),
              Expanded(
                child: Text(
                  'Reminder',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: semantic.textPrimary,
                      ),
                ),
              ),
              if (rem != null)
                DaywellStatusBadge(
                  label: rem.isActive ? 'Active' : pausedLabel,
                  tone: rem.isActive
                      ? DaywellStatusTone.success
                      : DaywellStatusTone.info,
                  showIcon: false,
                )
              else
                Text(
                  'Not set',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: semantic.textMuted,
                      ),
                ),
            ],
          ),
          if (rem != null && summary != null) ...[
            const SizedBox(height: SharedDesignTokens.spacingXs),
            Text(
              'Scheduled alert: $summary',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: semantic.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (triggerWall != null)
              Text(
                'Calendar date: ${SharedDateFormatter.formatDual(triggerWall.date, useAmharic: false)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: semantic.textSecondary,
                    ),
              ),
            if (inferred != null)
              Text(
                'Timing rule: ${TaskReminderEngine.presetLabel(inferred)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: semantic.textSecondary,
                    ),
              ),
          ],
          if (!_isEditing) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            Wrap(
              spacing: SharedDesignTokens.spacingSm,
              runSpacing: SharedDesignTokens.spacingXs,
              children: [
                DaywellButton(
                  label: rem != null ? 'Edit Reminder' : 'Set Reminder',
                  variant: DaywellButtonVariant.outlined,
                  size: DaywellButtonSize.compact,
                  leadingIcon: rem != null
                      ? Icons.edit_outlined
                      : Icons.notifications_active_outlined,
                  onPressed: () {
                    setState(() {
                      _syncFromProps();
                      _isEditing = true;
                    });
                  },
                ),
                if (rem != null)
                  DaywellButton(
                    label: 'Remove Reminder',
                    variant: DaywellButtonVariant.destructive,
                    size: DaywellButtonSize.compact,
                    leadingIcon: Icons.notifications_off_outlined,
                    onPressed: widget.onRemoveReminder,
                  ),
              ],
            ),
          ] else ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            TaskReminderEditorSection(
              isEnabled: true,
              onToggleReminder: (next) {
                if (!next) {
                  setState(() => _isEditing = false);
                  if (rem != null) {
                    widget.onRemoveReminder();
                  }
                }
              },
              preset: _preset,
              onPresetChanged: (p) => setState(() => _preset = p),
              customDate: _customDate,
              onCustomDateChanged: (d) => setState(() => _customDate = d),
              customTime: _customTime,
              onCustomTimeChanged: (t) => setState(() => _customTime = t),
              onPickDate: _pickDate,
              onPickTime: _pickTime,
              dueDate: widget.task.dueDate,
              scheduledDate: widget.task.scheduledDate,
              scheduledTime: widget.task.scheduledTime,
              onRequestPermission: widget.onRequestPermission,
              notificationPermissionGranted:
                  widget.notificationPermissionGranted,
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                DaywellButton(
                  label: 'Cancel',
                  variant: DaywellButtonVariant.text,
                  size: DaywellButtonSize.compact,
                  onPressed: () => setState(() => _isEditing = false),
                ),
                const SizedBox(width: SharedDesignTokens.spacingSm),
                DaywellButton(
                  label: 'Save Reminder',
                  variant: DaywellButtonVariant.primary,
                  size: DaywellButtonSize.compact,
                  onPressed: () {
                    final triggerUtc =
                        TaskReminderEngine.computeTriggerFromPreset(
                      task: widget.task,
                      preset: _preset,
                      customDate: _customDate,
                      customTime: _customTime,
                    );
                    setState(() => _isEditing = false);
                    widget.onSaveReminder(triggerUtc);
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
