import '../../core/date/shared_date.dart';

/// Progress calculation engine for Projects and Goals.
///
/// Principles:
/// - A project can exist with or without a goal.
/// - Milestones are optional intermediate pacing markers.
/// - Progress is calculated deterministically from underlying completed tasks and milestones:
///   Progress % = (Completed Tasks + Completed Milestones) / (Total Tasks + Total Milestones) * 100
/// - Zero tasks/milestones returns 0% (or 100% if manually marked completed).
class ProgressEngine {
  /// Computes the integer percentage (0 to 100) of project completion.
  static int calculateProgressPercentage({
    required int totalTasks,
    required int completedTasks,
    required int totalMilestones,
    required int completedMilestones,
    bool isProjectManuallyCompleted = false,
  }) {
    if (isProjectManuallyCompleted) return 100;

    final totalItems = totalTasks + totalMilestones;
    if (totalItems == 0) return 0;

    final completedItems = completedTasks + completedMilestones;
    final percentage = (completedItems * 100) ~/ totalItems;
    return percentage.clamp(0, 100);
  }

  /// Evaluates health / status of a project.
  static String evaluateStatus({
    required int progressPercentage,
    required bool hasOverdueTasks,
    required CalendarDate? targetDate,
  }) {
    if (progressPercentage >= 100) return 'completed';
    if (hasOverdueTasks) return 'attention_needed';
    if (targetDate != null && targetDate.isBefore(CalendarDate.today())) {
      return 'past_target_date';
    }
    return 'on_track';
  }
}
