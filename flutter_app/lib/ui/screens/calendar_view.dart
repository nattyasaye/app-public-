import 'dart:async';
import 'package:flutter/material.dart';
import '../../application/calendar/calendar_controller.dart';
import '../../application/projects/projects_controller.dart';
import '../../application/tasks/tasks_controller.dart';
import '../../core/date/shared_date.dart';
import '../../core/shared_foundation.dart';
import '../../core/theme/daywell_theme.dart';
import '../../domain/calendar/calendar_models.dart';
import '../../domain/tasks/task_calendar_engine.dart';
import '../../domain/tasks/task_models.dart';
import '../widgets/shared_ui_widgets.dart';

/// Interactive Dual Ethiopian-Gregorian Calendar workspace integrating
/// [CalendarController] events with [TasksController] deadlines, scheduled
/// tasks, and projected recurring task occurrences without duplicating records.
class CalendarView extends StatefulWidget {
  final CalendarController calendarController;
  final TasksController? tasksController;
  final ProjectsController? projectsController;
  final void Function(String taskId)? onOpenTask;
  final VoidCallback? onOpenTasks;

  const CalendarView({
    super.key,
    required this.calendarController,
    this.tasksController,
    this.projectsController,
    this.onOpenTask,
    this.onOpenTasks,
  });

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  static const List<(String, String)> _categoryOptions = <(String, String)>[
    ('work', 'Work'),
    ('personal', 'Personal'),
    ('finance', 'Finance'),
    ('health', 'Health'),
    ('family', 'Family'),
  ];

  static const List<String> _weekdayHeaders = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  late CalendarDate _displayedMonth;
  late CalendarDate _lastSyncedSelectedDate;
  String _viewMode = 'month'; // 'month', 'day', 'agenda'
  String _categoryFilter = 'all';
  String _searchQuery = '';
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _lastSyncedSelectedDate =
        widget.calendarController.state.selectedCalendarDate;
    _displayedMonth = CalendarDate(
      year: _lastSyncedSelectedDate.year,
      month: _lastSyncedSelectedDate.month,
      day: 1,
    );
    widget.calendarController.addListener(_onCalendarStateChanged);
  }

  @override
  void didUpdateWidget(covariant CalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.calendarController != widget.calendarController) {
      oldWidget.calendarController.removeListener(_onCalendarStateChanged);
      widget.calendarController.addListener(_onCalendarStateChanged);
      _syncDisplayedMonthFromController();
    }
  }

  @override
  void dispose() {
    widget.calendarController.removeListener(_onCalendarStateChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onCalendarStateChanged() {
    _syncDisplayedMonthFromController();
  }

  void _syncDisplayedMonthFromController() {
    final selected = widget.calendarController.state.selectedCalendarDate;
    if (selected != _lastSyncedSelectedDate) {
      _lastSyncedSelectedDate = selected;
      if (selected.year != _displayedMonth.year ||
          selected.month != _displayedMonth.month) {
        if (mounted) {
          setState(() {
            _displayedMonth = CalendarDate(
              year: selected.year,
              month: selected.month,
              day: 1,
            );
          });
        }
      }
    }
  }

  void _navigateMonth(int delta) {
    setState(() {
      _displayedMonth = delta < 0
          ? _displayedMonth.previousGregorianMonth()
          : _displayedMonth.nextGregorianMonth();
    });
  }

  void _jumpToToday() {
    final today = CalendarDate.today();
    setState(() {
      _displayedMonth =
          CalendarDate(year: today.year, month: today.month, day: 1);
    });
    widget.calendarController.setSelectedCalendarDate(today);
  }

  List<({CalendarDate date, bool isCurrentMonth})> _buildMonthGridDates() {
    final startOfMonth = _displayedMonth.startOfGregorianMonth;
    final leadingDays = startOfMonth.weekday - 1;
    final cells = <({CalendarDate date, bool isCurrentMonth})>[];

    for (var i = leadingDays; i > 0; i--) {
      cells.add((date: startOfMonth.subtractDays(i), isCurrentMonth: false));
    }
    for (final day in _displayedMonth.gregorianMonthDays()) {
      cells.add((date: day, isCurrentMonth: true));
    }
    final endOfMonth = _displayedMonth.endOfGregorianMonth;
    final trailing = (7 - (cells.length % 7)) % 7;
    for (var i = 1; i <= trailing; i++) {
      cells.add((date: endOfMonth.addDays(i), isCurrentMonth: false));
    }
    return cells;
  }

  String _categoryLabel(String category) {
    for (final opt in _categoryOptions) {
      if (opt.$1 == category) return opt.$2;
    }
    return 'Personal';
  }

  DaywellStatusTone _categoryTone(String category) {
    switch (category) {
      case 'work':
        return DaywellStatusTone.success;
      case 'finance':
        return DaywellStatusTone.warning;
      case 'health':
        return DaywellStatusTone.error;
      default:
        return DaywellStatusTone.info;
    }
  }

  Color _categoryAccentColor(BuildContext context, String category) {
    final semantic = context.daywellColors;
    final primary = Theme.of(context).colorScheme.primary;
    switch (category) {
      case 'work':
        return primary;
      case 'finance':
        return semantic.warning;
      case 'health':
        return semantic.error;
      case 'family':
        return semantic.transfer;
      default:
        return semantic.info;
    }
  }

  Future<void> _toggleTaskWithUndo(TaskEntity task) async {
    final tasksCtrl = widget.tasksController;
    if (tasksCtrl == null) return;
    final projectsCtrl = widget.projectsController;
    final wasCompleted = task.isCompleted;
    final previousSnapshot = task;
    final res = await tasksCtrl.toggleTaskWithRecurrence(task.id);

    if (res.updatedTask != null &&
        projectsCtrl != null &&
        res.updatedTask!.projectId != null) {
      await projectsCtrl.syncTaskSectionLink(
        res.updatedTask!.projectId!,
        res.updatedTask!,
      );
    }
    if (res.generatedNextTask != null &&
        projectsCtrl != null &&
        res.generatedNextTask!.projectId != null) {
      await projectsCtrl.copyTaskSectionLink(
        res.generatedNextTask!.projectId!,
        task.id,
        res.generatedNextTask!,
      );
    }
    if (!mounted) return;
    final nextDate =
        res.generatedNextTask?.dueDate ?? res.generatedNextTask?.scheduledDate;
    final message = wasCompleted
        ? 'Reopened "${task.title}"'
        : res.generatedNextTask != null
            ? 'Completed "${task.title}" · Next: ${nextDate?.toIsoString() ?? 'scheduled'}'
            : res.seriesEnded
                ? 'Completed "${task.title}" · Series ended'
                : 'Completed "${task.title}"';

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(() async {
              if (res.generatedNextTask != null &&
                  projectsCtrl != null &&
                  res.generatedNextTask!.projectId != null) {
                await projectsCtrl.detachTaskFromProjectSections(
                  res.generatedNextTask!.projectId!,
                  res.generatedNextTask!.id,
                );
              }
              await tasksCtrl.undoGeneratedRecurrenceCompletion(
                previousTask: previousSnapshot,
                generatedNextTaskId: res.generatedNextTask?.id,
              );
              if (projectsCtrl != null && previousSnapshot.projectId != null) {
                await projectsCtrl.syncTaskSectionLink(
                  previousSnapshot.projectId!,
                  previousSnapshot,
                );
              }
            }());
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<CalendarDate?> _pickDate(CalendarDate initial) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.toGregorianUtcMidnight(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return null;
    return CalendarDate.fromDateComponents(picked);
  }

  Future<String?> _pickTime(String? initial) async {
    final parsed = initial != null ? DayTimeOfDay.tryParse(initial) : null;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: parsed?.hour ?? 10,
        minute: parsed?.minute ?? 0,
      ),
    );
    if (picked == null) return null;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> _showEventFormModal({CalendarEventEntity? existing}) async {
    final isEditing = existing != null;
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    var eventDate = existing?.startDate ??
        widget.calendarController.state.selectedCalendarDate;
    CalendarDate? endDate = existing?.endDate;
    var isAllDay = existing?.isAllDay ?? false;
    var startTime = existing?.startTime ?? '10:00';
    var endTime = existing?.endTime ?? '11:00';
    var category = _categoryOptions.any((c) => c.$1 == existing?.category)
        ? existing!.category
        : 'personal';
    var hasReminder = existing?.hasReminder ?? true;
    String? titleError;
    String? timeError;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SharedDesignTokens.radiusSheet),
        ),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalContext, setModalState) {
          final semantic = modalContext.daywellColors;
          return Padding(
            padding: EdgeInsets.only(
              top: SharedDesignTokens.spacingMd,
              left: SharedDesignTokens.spacingMd,
              right: SharedDesignTokens.spacingMd,
              bottom: MediaQuery.of(modalContext).viewInsets.bottom +
                  SharedDesignTokens.spacingMd,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEditing ? 'Edit Event' : 'Add Event',
                    style: Theme.of(modalContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellTextField(
                    controller: titleCtrl,
                    autofocus: !isEditing,
                    isRequired: true,
                    label: 'Event Title',
                    hintText: 'e.g. Clinic Appointment',
                    errorText: titleError,
                    onChanged: (_) {
                      if (titleError != null) {
                        setModalState(() => titleError = null);
                      }
                    },
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellTextField(
                    controller: notesCtrl,
                    label: 'Notes (optional)',
                    hintText: 'Location or details...',
                    maxLines: 2,
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  DaywellDropdownField<String>(
                    label: 'Category',
                    value: category,
                    items: [
                      for (final opt in _categoryOptions)
                        DropdownMenuItem(value: opt.$1, child: Text(opt.$2)),
                    ],
                    onChanged: (v) {
                      if (v != null) setModalState(() => category = v);
                    },
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingCompact),
                  Wrap(
                    spacing: SharedDesignTokens.spacingSm,
                    runSpacing: SharedDesignTokens.spacingSm,
                    children: [
                      DaywellButton(
                        label: 'Date: ${eventDate.toIsoString()}',
                        variant: DaywellButtonVariant.outlined,
                        size: DaywellButtonSize.compact,
                        leadingIcon: Icons.calendar_today_outlined,
                        onPressed: () async {
                          final picked = await _pickDate(eventDate);
                          if (picked != null) {
                            setModalState(() {
                              eventDate = picked;
                              if (endDate != null &&
                                  endDate!.isBefore(eventDate)) {
                                endDate = null;
                              }
                            });
                          }
                        },
                      ),
                      DaywellButton(
                        label: endDate != null
                            ? 'End: ${endDate!.toIsoString()}'
                            : 'Multi-day End',
                        variant: DaywellButtonVariant.outlined,
                        size: DaywellButtonSize.compact,
                        leadingIcon: Icons.event_outlined,
                        onPressed: () async {
                          final picked = await _pickDate(endDate ?? eventDate);
                          if (picked != null && !picked.isBefore(eventDate)) {
                            setModalState(() => endDate = picked);
                          }
                        },
                      ),
                      if (endDate != null)
                        DaywellIconButton(
                          icon: Icons.clear,
                          tooltip: 'Clear end date',
                          onPressed: () => setModalState(() => endDate = null),
                        ),
                    ],
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingSm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('All Day'),
                    value: isAllDay,
                    onChanged: (val) => setModalState(() {
                      isAllDay = val;
                      timeError = null;
                    }),
                  ),
                  if (!isAllDay) ...[
                    Row(
                      children: [
                        Expanded(
                          child: DaywellButton(
                            label: 'Start: $startTime',
                            variant: DaywellButtonVariant.outlined,
                            size: DaywellButtonSize.compact,
                            leadingIcon: Icons.schedule_outlined,
                            onPressed: () async {
                              final picked = await _pickTime(startTime);
                              if (picked != null) {
                                setModalState(() {
                                  startTime = picked;
                                  timeError = null;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: SharedDesignTokens.spacingSm),
                        Expanded(
                          child: DaywellButton(
                            label: 'End: $endTime',
                            variant: DaywellButtonVariant.outlined,
                            size: DaywellButtonSize.compact,
                            leadingIcon: Icons.schedule,
                            onPressed: () async {
                              final picked = await _pickTime(endTime);
                              if (picked != null) {
                                setModalState(() {
                                  endTime = picked;
                                  timeError = null;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    if (timeError != null) ...[
                      const SizedBox(height: SharedDesignTokens.spacingXs),
                      Text(
                        timeError!,
                        style: Theme.of(modalContext)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: semantic.error),
                      ),
                    ],
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Reminder'),
                    value: hasReminder,
                    onChanged: (val) => setModalState(() => hasReminder = val),
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingMd),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (isEditing)
                        DaywellButton(
                          label: 'Delete',
                          variant: DaywellButtonVariant.destructive,
                          size: DaywellButtonSize.compact,
                          leadingIcon: Icons.delete_outline,
                          onPressed: () async {
                            final confirmed =
                                await DaywellConfirmationDialog.show(
                              modalContext,
                              title: 'Delete event?',
                              message:
                                  'Delete "${existing.title}" from Calendar?',
                              confirmLabel: 'Delete',
                              isDestructive: true,
                              icon: Icons.delete_outline,
                            );
                            if (!confirmed) return;
                            await widget.calendarController
                                .deleteEvent(existing.id);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        )
                      else
                        const SizedBox.shrink(),
                      Row(
                        children: [
                          DaywellButton(
                            label: 'Cancel',
                            variant: DaywellButtonVariant.text,
                            size: DaywellButtonSize.compact,
                            onPressed: () => Navigator.pop(ctx),
                          ),
                          const SizedBox(width: SharedDesignTokens.spacingSm),
                          DaywellButton(
                            label: isEditing ? 'Save' : 'Add Event',
                            variant: DaywellButtonVariant.primary,
                            size: DaywellButtonSize.compact,
                            onPressed: () async {
                              final title = titleCtrl.text.trim();
                              if (title.isEmpty) {
                                setModalState(
                                  () => titleError = 'Event title is required',
                                );
                                return;
                              }
                              if (!isAllDay &&
                                  (endDate == null || endDate == eventDate)) {
                                final startTod = DayTimeOfDay.parse(startTime);
                                final endTod = DayTimeOfDay.parse(endTime);
                                if (endTod < startTod) {
                                  setModalState(
                                    () => timeError =
                                        'End time cannot precede start time',
                                  );
                                  return;
                                }
                              }
                              if (isEditing) {
                                final updated = existing.copyWith(
                                  title: title,
                                  dateIso: eventDate.toIsoString(),
                                  endDateIso: endDate?.toIsoString(),
                                  clearEndDate: endDate == null,
                                  startTime: isAllDay ? null : startTime,
                                  endTime: isAllDay ? null : endTime,
                                  isAllDay: isAllDay,
                                  category: category,
                                  hasReminder: hasReminder,
                                  notes: notesCtrl.text.trim().isEmpty
                                      ? null
                                      : notesCtrl.text.trim(),
                                );
                                await widget.calendarController
                                    .updateEvent(updated);
                              } else {
                                await widget.calendarController.createEvent(
                                  title: title,
                                  dateIso: eventDate.toIsoString(),
                                  endDateIso: endDate?.toIsoString(),
                                  startTime: isAllDay ? null : startTime,
                                  endTime: isAllDay ? null : endTime,
                                  isAllDay: isAllDay,
                                  category: category,
                                  hasReminder: hasReminder,
                                  notes: notesCtrl.text.trim().isEmpty
                                      ? null
                                      : notesCtrl.text.trim(),
                                );
                                widget.calendarController
                                    .setSelectedCalendarDate(eventDate);
                              }
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    titleCtrl.dispose();
    notesCtrl.dispose();
  }

  Widget _buildEventCard(
    BuildContext context,
    CalendarEventEntity ev, {
    bool showDateChip = false,
  }) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final accent = _categoryAccentColor(context, ev.category);
    final timeLabel = ev.isAllDay
        ? 'All Day'
        : '${ev.startTime ?? ''}${ev.endTime != null ? ' – ${ev.endTime}' : ''}'
            .trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: SharedDesignTokens.spacingSm),
      child: DaywellCard(
        onTap: () => unawaited(_showEventFormModal(existing: ev)),
        padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showDateChip) ...[
              Container(
                width: 44,
                padding: const EdgeInsets.symmetric(
                  vertical: SharedDesignTokens.spacingXs,
                ),
                decoration: BoxDecoration(
                  color: semantic.surfaceSubtle,
                  borderRadius:
                      BorderRadius.circular(SharedDesignTokens.radiusSm),
                ),
                child: Column(
                  children: [
                    Text(
                      ev.startDate.gregorianShortMonthName.toUpperCase(),
                      style: textTheme.labelSmall?.copyWith(
                        color: semantic.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${ev.startDate.day}',
                      style: textTheme.titleSmall?.copyWith(
                        color: semantic.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SharedDesignTokens.spacingCompact),
            ] else ...[
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: SharedDesignTokens.spacingCompact),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ev.title,
                          style: textTheme.titleSmall?.copyWith(
                            color: semantic.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: SharedDesignTokens.spacingSm),
                      DaywellStatusBadge(
                        label: _categoryLabel(ev.category),
                        tone: _categoryTone(ev.category),
                        showIcon: false,
                      ),
                    ],
                  ),
                  if (ev.notes != null && ev.notes!.trim().isNotEmpty) ...[
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    Text(
                      ev.notes!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                  ],
                  if (timeLabel.isNotEmpty) ...[
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_outlined,
                          size: DaywellIconSize.xs,
                          color: semantic.textMuted,
                        ),
                        const SizedBox(width: SharedDesignTokens.spacingXs),
                        Text(
                          timeLabel,
                          style: textTheme.labelSmall?.copyWith(
                            color: semantic.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskOccurrenceCard(
    BuildContext context,
    TaskCalendarOccurrence occ, {
    bool showDateChip = false,
  }) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final bool isPreview = occ.isProjectedOccurrence;

    final String badgeLabel;
    final DaywellStatusTone badgeTone;
    switch (occ.kind) {
      case TaskCalendarOccurrenceKind.dueAndScheduled:
        badgeLabel = 'Scheduled & Due';
        badgeTone = DaywellStatusTone.info;
      case TaskCalendarOccurrenceKind.scheduled:
        badgeLabel = 'Scheduled Task';
        badgeTone = DaywellStatusTone.info;
      case TaskCalendarOccurrenceKind.due:
        badgeLabel = 'Task Deadline';
        badgeTone = DaywellStatusTone.warning;
      case TaskCalendarOccurrenceKind.recurringPreview:
        badgeLabel = 'Upcoming Recurrence';
        badgeTone = DaywellStatusTone.info;
    }

    final metadataParts = <String>[];
    if (occ.scheduledTime != null && occ.scheduledTime!.isNotEmpty) {
      metadataParts.add(
        occ.estimatedDurationMinutes != null
            ? '${occ.scheduledTime} · ${occ.estimatedDurationMinutes}m'
            : occ.scheduledTime!,
      );
    }
    if (occ.companionDueDate != null) {
      metadataParts.add('Due ${occ.companionDueDate!.toIsoString()}');
    }
    if (occ.companionScheduledDate != null) {
      metadataParts
          .add('Scheduled ${occ.companionScheduledDate!.toIsoString()}');
    }
    if (occ.recurrenceSummary != null) {
      metadataParts.add(
        isPreview && occ.isCompletionBasedRecurrence
            ? '${occ.recurrenceSummary} (est.)'
            : occ.recurrenceSummary!,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: SharedDesignTokens.spacingSm),
      child: DaywellCard(
        color: isPreview ? semantic.surfaceSubtle : semantic.infoContainer,
        borderColor: isPreview ? semantic.border : semantic.info,
        onTap: widget.onOpenTask != null
            ? () => widget.onOpenTask!(occ.sourceTaskId)
            : (!isPreview && widget.tasksController != null)
                ? () => unawaited(_toggleTaskWithUndo(occ.task))
                : null,
        padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showDateChip) ...[
              Container(
                width: 44,
                padding: const EdgeInsets.symmetric(
                  vertical: SharedDesignTokens.spacingXs,
                ),
                decoration: BoxDecoration(
                  color: semantic.card,
                  borderRadius:
                      BorderRadius.circular(SharedDesignTokens.radiusSm),
                ),
                child: Column(
                  children: [
                    Text(
                      occ.occurrenceDate.gregorianShortMonthName.toUpperCase(),
                      style: textTheme.labelSmall?.copyWith(
                        color: semantic.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${occ.occurrenceDate.day}',
                      style: textTheme.titleSmall?.copyWith(
                        color: semantic.info,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SharedDesignTokens.spacingCompact),
            ] else if (isPreview) ...[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.repeat,
                  size: DaywellIconSize.md,
                  color: semantic.transfer,
                  semanticLabel: 'Projected recurring task occurrence',
                ),
              ),
              const SizedBox(width: SharedDesignTokens.spacingCompact),
            ] else ...[
              IconButton(
                icon: Icon(
                  occ.completed
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: semantic.info,
                ),
                tooltip: occ.completed
                    ? 'Reopen ${occ.task.title}'
                    : 'Complete ${occ.task.title}',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onPressed: widget.tasksController != null
                    ? () => unawaited(_toggleTaskWithUndo(occ.task))
                    : null,
              ),
              const SizedBox(width: SharedDesignTokens.spacingXs),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          occ.task.title,
                          style: textTheme.titleSmall?.copyWith(
                            color: occ.completed
                                ? semantic.textDisabled
                                : isPreview
                                    ? semantic.textPrimary
                                    : semantic.onInfoContainer,
                            decoration: occ.completed
                                ? TextDecoration.lineThrough
                                : null,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: SharedDesignTokens.spacingSm),
                      DaywellStatusBadge(
                        label: badgeLabel,
                        tone: badgeTone,
                        showIcon: false,
                      ),
                    ],
                  ),
                  if (metadataParts.isNotEmpty) ...[
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    Text(
                      metadataParts.join(' · '),
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mergeListenable = widget.tasksController != null
        ? Listenable.merge(
            <Listenable>[widget.calendarController, widget.tasksController!],
          )
        : widget.calendarController;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: SharedDesignTokens.spacingXs),
            child: DaywellButton(
              label: 'Today',
              variant: DaywellButtonVariant.text,
              size: DaywellButtonSize.compact,
              onPressed: _jumpToToday,
            ),
          ),
          DaywellIconButton(
            icon: Icons.add,
            tooltip: 'Add Event',
            semanticLabel: 'Add Calendar Event',
            onPressed: () => unawaited(_showEventFormModal()),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: mergeListenable,
        builder: (BuildContext context, Widget? _) {
          final calendarState = widget.calendarController.state;
          final semantic = context.daywellColors;
          final colorScheme = Theme.of(context).colorScheme;
          final textTheme = Theme.of(context).textTheme;

          if (calendarState.isLoading) {
            return const DaywellContentState(
              status: DaywellContentStatus.loading,
              loadingLabel: 'Loading calendar events...',
              statePadding: EdgeInsets.all(SharedDesignTokens.spacingLg),
            );
          }

          if (calendarState.errorMessage != null &&
              calendarState.errorMessage!.trim().isNotEmpty) {
            return Center(
              child: DaywellContentState(
                status: DaywellContentStatus.error,
                errorTitle: 'Unable to load calendar events',
                errorMessage: calendarState.errorMessage!,
                retryLabel: 'Retry',
                onRetry: () => unawaited(widget.calendarController.loadAll()),
                statePadding:
                    const EdgeInsets.all(SharedDesignTokens.spacingLg),
              ),
            );
          }

          final selectedDate = calendarState.selectedCalendarDate;
          final today = CalendarDate.today();
          final monthCells = _buildMonthGridDates();
          final firstCell = monthCells.first.date;
          final lastCell = monthCells.last.date;
          final minProj =
              selectedDate.isBefore(firstCell) ? selectedDate : firstCell;
          final maxProj =
              selectedDate.isAfter(lastCell) ? selectedDate : lastCell;

          final allTasks =
              widget.tasksController?.state.tasks ?? const <TaskEntity>[];
          final monthOccurrences = TaskCalendarEngine.projectTasksForDateRange(
            allTasks,
            DateRange(start: minProj, end: maxProj),
          );

          final displayEth = _displayedMonth.toEthiopian();
          final query = _searchQuery.trim().toLowerCase();

          var dayEvents = calendarState.eventsForCalendarDate(selectedDate);
          var dayTasks = TaskCalendarEngine.occurrencesOnDate(
              monthOccurrences, selectedDate);

          if (_categoryFilter != 'all') {
            dayEvents = dayEvents
                .where((e) => e.category == _categoryFilter)
                .toList(growable: false);
          }
          if (query.isNotEmpty) {
            dayEvents = dayEvents
                .where(
                  (e) =>
                      e.title.toLowerCase().contains(query) ||
                      (e.notes?.toLowerCase().contains(query) ?? false),
                )
                .toList(growable: false);
            dayTasks = dayTasks
                .where(
                  (t) =>
                      t.task.title.toLowerCase().contains(query) ||
                      (t.recurrenceSummary?.toLowerCase().contains(query) ??
                          false),
                )
                .toList(growable: false);
          }

          return ListView(
            padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
            children: [
              // Dual Month & Selected Date Header Card
              DaywellCard(
                color: semantic.surfaceSubtle,
                padding:
                    const EdgeInsets.all(SharedDesignTokens.spacingCompact),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: SharedDesignTokens.spacingSm,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '${_displayedMonth.gregorianFullMonthName} ${_displayedMonth.year}',
                                    style: textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: semantic.textPrimary,
                                    ),
                                  ),
                                  DaywellStatusBadge(
                                    label:
                                        '${displayEth.amharicMonthName} ${displayEth.year} ዓ.ም',
                                    tone: DaywellStatusTone.success,
                                    showIcon: false,
                                  ),
                                ],
                              ),
                              const SizedBox(
                                  height: SharedDesignTokens.spacingXs),
                              Text(
                                'Selected: ${SharedDateFormatter.formatDual(selectedDate)}',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        DaywellIconButton(
                          icon: Icons.chevron_left,
                          tooltip: 'Previous Month',
                          onPressed: () => _navigateMonth(-1),
                        ),
                        DaywellIconButton(
                          icon: Icons.chevron_right,
                          tooltip: 'Next Month',
                          onPressed: () => _navigateMonth(1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),

              // View Mode Switcher & Category Filter
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment<String>(
                            value: 'month', label: Text('Month')),
                        ButtonSegment<String>(value: 'day', label: Text('Day')),
                        ButtonSegment<String>(
                            value: 'agenda', label: Text('Agenda')),
                      ],
                      selected: <String>{_viewMode},
                      onSelectionChanged: (Set<String> next) {
                        if (next.isNotEmpty) {
                          setState(() => _viewMode = next.first);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
              DaywellDropdownField<String>(
                label: 'Category Filter',
                value: _categoryFilter,
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: 'all',
                    child: Text('All Categories'),
                  ),
                  for (final opt in _categoryOptions)
                    DropdownMenuItem<String>(
                      value: opt.$1,
                      child: Text(opt.$2),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _categoryFilter = v);
                },
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),

              if (_viewMode == 'month') ...[
                DaywellCard(
                  padding: const EdgeInsets.all(SharedDesignTokens.spacingSm),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          for (final header in _weekdayHeaders)
                            Expanded(
                              child: Center(
                                child: Text(
                                  header.toUpperCase(),
                                  style: textTheme.labelSmall?.copyWith(
                                    color: semantic.textMuted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: SharedDesignTokens.spacingSm),
                      for (var weekStart = 0;
                          weekStart < monthCells.length;
                          weekStart += 7)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              for (var col = 0; col < 7; col++)
                                Expanded(
                                  child: Builder(
                                    builder: (BuildContext context) {
                                      final cell = monthCells[weekStart + col];
                                      final cellDate = cell.date;
                                      final isSelected =
                                          cellDate == selectedDate;
                                      final isToday = cellDate == today;
                                      final ethDay = cellDate.toEthiopian().day;
                                      final hasEvents = calendarState
                                          .eventsForCalendarDate(cellDate)
                                          .isNotEmpty;
                                      final cellTasks =
                                          TaskCalendarEngine.occurrencesOnDate(
                                        monthOccurrences,
                                        cellDate,
                                      );
                                      final hasStoredTasks = cellTasks
                                          .any((t) => !t.isProjectedOccurrence);
                                      final hasProjectedTasks = cellTasks
                                          .any((t) => t.isProjectedOccurrence);

                                      final Color bgColor = isSelected
                                          ? colorScheme.primary
                                          : isToday
                                              ? colorScheme.primaryContainer
                                              : semantic.card;
                                      final Color fgColor = isSelected
                                          ? colorScheme.onPrimary
                                          : isToday
                                              ? colorScheme.onPrimaryContainer
                                              : cell.isCurrentMonth
                                                  ? semantic.textPrimary
                                                  : semantic.textDisabled;

                                      return InkWell(
                                        borderRadius: BorderRadius.circular(
                                          SharedDesignTokens.radiusSm,
                                        ),
                                        onTap: () => widget.calendarController
                                            .setSelectedCalendarDate(cellDate),
                                        child: Container(
                                          constraints: const BoxConstraints(
                                              minHeight: 48),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: bgColor,
                                            borderRadius: BorderRadius.circular(
                                              SharedDesignTokens.radiusSm,
                                            ),
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                '${cellDate.day}',
                                                style: textTheme.labelMedium
                                                    ?.copyWith(
                                                  color: fgColor,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              Text(
                                                '$ethDay',
                                                style: textTheme.labelSmall
                                                    ?.copyWith(
                                                  fontSize: 10,
                                                  color: isSelected
                                                      ? fgColor
                                                      : semantic.textMuted,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  if (hasEvents)
                                                    Container(
                                                      width: 5,
                                                      height: 5,
                                                      margin: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 1,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: isSelected
                                                            ? semantic.warning
                                                            : colorScheme
                                                                .primary,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                  if (hasStoredTasks)
                                                    Container(
                                                      width: 5,
                                                      height: 5,
                                                      margin: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 1,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: isSelected
                                                            ? fgColor
                                                            : semantic.info,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    )
                                                  else if (hasProjectedTasks)
                                                    Container(
                                                      width: 5,
                                                      height: 5,
                                                      margin: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 1,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: isSelected
                                                            ? fgColor
                                                            : semantic.transfer,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: SharedDesignTokens.spacingMd),
              ],

              if (_viewMode == 'month' || _viewMode == 'day') ...[
                DaywellSectionHeader(
                  title:
                      'Schedule for ${SharedDateFormatter.formatDual(selectedDate)}',
                  actionLabel: widget.onOpenTasks != null ? 'Open Tasks' : null,
                  onActionPressed: widget.onOpenTasks,
                ),
                Text(
                  '${dayEvents.length} events · ${dayTasks.length} tasks',
                  style: textTheme.bodySmall?.copyWith(
                    color: semantic.textMuted,
                  ),
                ),
                const SizedBox(height: SharedDesignTokens.spacingSm),
                if (dayEvents.isEmpty && dayTasks.isEmpty)
                  DaywellContentState(
                    status: DaywellContentStatus.empty,
                    emptyIcon: Icons.calendar_month_outlined,
                    emptyMessage: 'No events or tasks scheduled',
                    emptySubtitle:
                        'Add a calendar event or assign a due/scheduled date to a task.',
                    emptyActionLabel: 'Add Event',
                    onEmptyAction: () => unawaited(_showEventFormModal()),
                  )
                else ...[
                  for (final ev in dayEvents) _buildEventCard(context, ev),
                  for (final occ in dayTasks)
                    _buildTaskOccurrenceCard(context, occ),
                ],
              ] else ...[
                DaywellSearchField(
                  controller: _searchController,
                  hintText: 'Search upcoming events & tasks...',
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                Builder(
                  builder: (BuildContext context) {
                    var agendaEvents = calendarState.events
                        .where((e) =>
                            _categoryFilter == 'all' ||
                            e.category == _categoryFilter)
                        .toList();
                    var agendaTasks =
                        TaskCalendarEngine.projectTasksForDateRange(
                      allTasks,
                      DateRange(start: today, end: today.addDays(30)),
                    );

                    if (query.isNotEmpty) {
                      agendaEvents = agendaEvents
                          .where(
                            (e) =>
                                e.title.toLowerCase().contains(query) ||
                                (e.notes?.toLowerCase().contains(query) ??
                                    false),
                          )
                          .toList();
                      agendaTasks = agendaTasks
                          .where(
                            (t) =>
                                t.task.title.toLowerCase().contains(query) ||
                                (t.recurrenceSummary
                                        ?.toLowerCase()
                                        .contains(query) ??
                                    false),
                          )
                          .toList();
                    }

                    agendaEvents.sort((a, b) {
                      final cmp = a.dateIso.compareTo(b.dateIso);
                      if (cmp != 0) return cmp;
                      return (a.startTime ?? '').compareTo(b.startTime ?? '');
                    });

                    if (agendaEvents.isEmpty && agendaTasks.isEmpty) {
                      return DaywellContentState(
                        status: DaywellContentStatus.empty,
                        emptyIcon: Icons.calendar_month_outlined,
                        emptyMessage: 'No upcoming events or scheduled tasks',
                        emptySubtitle:
                            'Add an event or schedule tasks to populate your 30-day agenda.',
                        emptyActionLabel: 'Add Event',
                        onEmptyAction: () => unawaited(_showEventFormModal()),
                      );
                    }

                    final combined = <({
                      String sortDate,
                      int kindOrder,
                      String sortTime,
                      CalendarEventEntity? event,
                      TaskCalendarOccurrence? occ,
                    })>[
                      for (final ev in agendaEvents)
                        (
                          sortDate: ev.dateIso,
                          kindOrder: 0,
                          sortTime:
                              ev.isAllDay ? '00:00' : (ev.startTime ?? '00:00'),
                          event: ev,
                          occ: null,
                        ),
                      for (final occ in agendaTasks)
                        (
                          sortDate: occ.occurrenceDateIso,
                          kindOrder: 1,
                          sortTime: occ.scheduledTime ?? '23:59',
                          event: null,
                          occ: occ,
                        ),
                    ]..sort((a, b) {
                        final dc = a.sortDate.compareTo(b.sortDate);
                        if (dc != 0) return dc;
                        final kc = a.kindOrder.compareTo(b.kindOrder);
                        if (kc != 0) return kc;
                        return a.sortTime.compareTo(b.sortTime);
                      });

                    return Column(
                      children: [
                        for (final item in combined)
                          if (item.event != null)
                            _buildEventCard(
                              context,
                              item.event!,
                              showDateChip: true,
                            )
                          else if (item.occ != null)
                            _buildTaskOccurrenceCard(
                              context,
                              item.occ!,
                              showDateChip: true,
                            ),
                      ],
                    );
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
