import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/notes/notes_controller.dart';
import '../../../application/tasks/tasks_controller.dart';
import '../../../core/date/shared_date.dart';
import '../../../domain/projects/project_models.dart';
import '../../../domain/tasks/task_models.dart';
import '../../widgets/shared_ui_widgets.dart';

String formatProjectNumber(double value) {
  if ((value - value.roundToDouble()).abs() < 0.0001) {
    return value.round().toString();
  }
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String projectStatusLabel(ProjectEntity project) {
  if (project.isArchived) return 'Archived';
  switch (project.status) {
    case 'completed':
      return 'Completed';
    case 'on_hold':
      return 'On Hold';
    default:
      return 'Active';
  }
}

DaywellStatusTone projectStatusTone(ProjectEntity project) {
  if (project.isArchived) return DaywellStatusTone.info;
  switch (project.status) {
    case 'completed':
      return DaywellStatusTone.success;
    case 'on_hold':
      return DaywellStatusTone.warning;
    default:
      return DaywellStatusTone.info;
  }
}

String blockTypeLabel(ProjectBlockType type) {
  switch (type) {
    case ProjectBlockType.counter:
      return 'Counter';
    case ProjectBlockType.groupedList:
      return 'Grouped List';
    case ProjectBlockType.checklist:
      return 'Checklist';
    case ProjectBlockType.schedule:
      return 'Schedule';
  }
}

IconData blockTypeIcon(ProjectBlockType type) {
  switch (type) {
    case ProjectBlockType.counter:
      return Icons.exposure_plus_1_outlined;
    case ProjectBlockType.groupedList:
      return Icons.view_list_outlined;
    case ProjectBlockType.checklist:
      return Icons.checklist_outlined;
    case ProjectBlockType.schedule:
      return Icons.schedule_outlined;
  }
}

String scheduleRuleLabel(ScheduleItemCompletionRule rule) {
  switch (rule) {
    case ScheduleItemCompletionRule.manual:
      return 'Manual completion';
    case ScheduleItemCompletionRule.thresholdPercent:
      return 'Threshold % auto-complete';
    case ScheduleItemCompletionRule.exactDuration:
      return 'Exact duration auto-complete';
  }
}

Future<CalendarDate?> pickProjectCalendarDate(
  BuildContext context, {
  CalendarDate? initialDate,
  String? helpText,
}) async {
  final seed = initialDate ?? CalendarDate.today();
  final picked = await showDatePicker(
    context: context,
    initialDate: DateTime(seed.year, seed.month, seed.day),
    firstDate: DateTime(1970, 1, 1),
    lastDate: DateTime(2100, 12, 31),
    helpText: helpText,
  );
  if (picked == null) return null;
  return CalendarDate.fromDateComponents(picked);
}

void syncTasksControllerProjects(TasksController? tasksController) {
  if (tasksController != null) {
    unawaited(tasksController.loadAll());
  }
}

void syncNotesControllerProjects(NotesController? notesController) {
  if (notesController != null) {
    unawaited(notesController.loadNotes());
  }
}
