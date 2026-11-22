import '../../core/date/shared_date.dart';
import '../tasks/task_models.dart';
import 'project_models.dart';

/// Progress calculation engine for Projects and Goals.
///
/// Principles:
/// - A project can exist with or without a goal.
/// - Milestones are optional intermediate pacing markers.
/// - Progress is calculated deterministically from underlying completed tasks and milestones:
///   Progress % = (Completed Tasks + Completed Milestones) / (Total Tasks + Total Milestones) * 100
/// - Zero tasks/milestones returns 0% (or 100% if manually marked completed).
/// - Stage 1 structured tracking blocks compute independent per-block metrics
///   and never implicitly average unrelated metrics.
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

  /// Evaluates whether a schedule item meets an explicit duration completion rule.
  /// Returns `false` for `ScheduleItemCompletionRule.manual` so duration logs
  /// never silently override manual completion state.
  static bool meetsScheduleDurationRule({
    required int? plannedDurationMinutes,
    required double actualLoggedMinutes,
    required ScheduleBlockConfig config,
  }) {
    if (config.completionRule == ScheduleItemCompletionRule.manual) {
      return false;
    }
    if (plannedDurationMinutes == null || plannedDurationMinutes <= 0) {
      return false;
    }
    final requiredRatio =
        config.completionRule == ScheduleItemCompletionRule.exactDuration
            ? 1.0
            : config.autoCompleteThresholdRatio.clamp(0.01, 1.0);
    return actualLoggedMinutes >= (plannedDurationMinutes * requiredRatio);
  }

  /// Computes deterministic independent metrics for all tracking blocks of [project].
  ///
  /// - Never implicitly averages metrics across blocks, tasks, or milestones.
  /// - Only populates `overallPercentage` when `customFields['primaryBlockId']`
  ///   references an existing, non-archived block belonging to [project].
  static ProjectProgressSummary calculateProjectProgressSummary({
    required ProjectEntity project,
    required List<ProjectTrackingBlockEntity> blocks,
    required List<ProjectTrackingRecordEntity> records,
    List<TaskEntity> linkedTasks = const [],
    List<MilestoneEntity> milestones = const [],
    CalendarDate? asOfDate,
    bool includeArchivedTasks = false,
  }) {
    final referenceDate = asOfDate ?? CalendarDate.today();
    final todayIso = referenceDate.toIsoString();

    final projectTasks = linkedTasks
        .where(
          (t) =>
              t.projectId == project.id &&
              (includeArchivedTasks || !t.isArchived) &&
              t.status != 'cancelled',
        )
        .toList();
    final linkedTasksTotal = projectTasks.length;
    final linkedTasksCompleted = projectTasks
        .where((t) => t.isCompleted || t.status == 'completed')
        .length;

    final projectMilestones =
        milestones.where((m) => m.projectId == project.id).toList();
    final milestonesTotal = projectMilestones.length;
    final milestonesCompleted =
        projectMilestones.where((m) => m.isCompleted).length;

    final projectBlocks =
        blocks.where((b) => b.projectId == project.id).toList()
          ..sort((a, b) {
            final orderCmp = a.sortOrder.compareTo(b.sortOrder);
            if (orderCmp != 0) return orderCmp;
            return a.createdAt.compareTo(b.createdAt);
          });

    final recordsByBlock = <String, List<ProjectTrackingRecordEntity>>{};
    for (final rec in records) {
      if (rec.projectId != project.id) continue;
      recordsByBlock.putIfAbsent(rec.blockId, () => []).add(rec);
    }

    int? daysRemaining;
    if (project.targetDate != null) {
      final diff = project.targetDate!.differenceInDays(referenceDate);
      daysRemaining = diff >= 0 ? diff + 1 : 0;
    }

    final rawMetricsById = <String, ProjectBlockProgressMetric>{};

    // First pass: compute non-rollup blocks (grouped_list, checklist, schedule, direct counters)
    for (final block in projectBlocks) {
      if (block.blockType == ProjectBlockType.counter &&
          CounterBlockConfig.fromMap(block.config).rollupSourceBlockId !=
              null) {
        continue;
      }
      final blockRecords =
          List<ProjectTrackingRecordEntity>.from(recordsByBlock[block.id] ?? [])
            ..sort((a, b) {
              final orderCmp = a.sortOrder.compareTo(b.sortOrder);
              if (orderCmp != 0) return orderCmp;
              return a.createdAt.compareTo(b.createdAt);
            });

      rawMetricsById[block.id] = _computeSingleBlockMetric(
        block: block,
        records: blockRecords,
        todayIso: todayIso,
        daysRemaining: daysRemaining,
      );
    }

    // Second pass: compute rollup counters from their single source of truth
    for (final block in projectBlocks) {
      if (rawMetricsById.containsKey(block.id)) continue;
      final cfg = CounterBlockConfig.fromMap(block.config);
      final sourceMetric = cfg.rollupSourceBlockId != null
          ? rawMetricsById[cfg.rollupSourceBlockId!]
          : null;
      final logged = sourceMetric?.loggedTotal ?? 0.0;
      final effectiveCompleted = sourceMetric?.targetCompletedTotal ?? logged;
      final effectiveTarget = block.targetValue ?? sourceMetric?.targetValue;
      final percent = (effectiveTarget != null && effectiveTarget > 0)
          ? (effectiveCompleted / effectiveTarget * 100.0).clamp(0.0, 100.0)
          : null;
      final pace = (effectiveTarget != null &&
              effectiveTarget > 0 &&
              daysRemaining != null)
          ? ((effectiveTarget - effectiveCompleted)
                  .clamp(0.0, double.infinity)) /
              (daysRemaining > 0 ? daysRemaining : 1)
          : null;

      rawMetricsById[block.id] = ProjectBlockProgressMetric(
        blockId: block.id,
        blockType: block.blockType,
        title: block.title,
        unitLabel: block.unitLabel ?? sourceMetric?.unitLabel,
        isArchived: block.isArchived,
        loggedTotal: logged,
        targetCompletedTotal: sourceMetric?.targetCompletedTotal,
        overTargetAmount: sourceMetric?.overTargetAmount,
        overTargetItemCount: sourceMetric?.overTargetItemCount,
        targetValue: effectiveTarget,
        progressPercent: percent,
        dailyTargetValue:
            block.dailyTargetValue ?? sourceMetric?.dailyTargetValue,
        todayTotal: sourceMetric?.todayTotal ?? 0.0,
        dailyTotalsByDate: sourceMetric?.dailyTotalsByDate,
        completedCount: sourceMetric?.completedCount ?? 0,
        totalCount: sourceMetric?.totalCount ?? 0,
        plannedDurationMinutes: sourceMetric?.plannedDurationMinutes ?? 0,
        actualLoggedDurationMinutes:
            sourceMetric?.actualLoggedDurationMinutes ?? 0,
        itemTotals: sourceMetric?.itemTotals,
        groupMetrics: sourceMetric?.groupMetrics,
        rollupSourceBlockId: cfg.rollupSourceBlockId,
        paceNeededPerDay: pace,
        daysRemaining: daysRemaining,
      );
    }

    final orderedMetrics = <ProjectBlockProgressMetric>[
      for (final block in projectBlocks)
        if (rawMetricsById.containsKey(block.id)) rawMetricsById[block.id]!,
    ];

    final rawPrimary =
        ProjectCustomFieldsPayload.fromMap(project.customFields).primaryBlockId;
    ProjectBlockProgressMetric? primaryMetric;
    var hasInvalidPrimary = false;
    String? resolvedPrimaryId;

    if (rawPrimary != null && rawPrimary.isNotEmpty) {
      final candidate = rawMetricsById[rawPrimary];
      if (candidate == null || candidate.isArchived) {
        hasInvalidPrimary = true;
      } else {
        resolvedPrimaryId = rawPrimary;
        primaryMetric = candidate;
      }
    }

    return ProjectProgressSummary(
      projectId: project.id,
      blockMetrics: orderedMetrics,
      primaryBlockId: resolvedPrimaryId,
      primaryMetric: primaryMetric,
      overallPercentage: primaryMetric?.progressPercent,
      hasInvalidPrimaryBlockReference: hasInvalidPrimary,
      linkedTasksCompleted: linkedTasksCompleted,
      linkedTasksTotal: linkedTasksTotal,
      milestonesCompleted: milestonesCompleted,
      milestonesTotal: milestonesTotal,
    );
  }

  static ProjectBlockProgressMetric _computeSingleBlockMetric({
    required ProjectTrackingBlockEntity block,
    required List<ProjectTrackingRecordEntity> records,
    required String todayIso,
    required int? daysRemaining,
  }) {
    final dailyTotals = <String, double>{};
    final itemTotals = <String, double>{};
    var loggedTotal = 0.0;

    void addLog(ProjectTrackingRecordEntity log) {
      final delta = log.deltaValue ?? 0.0;
      loggedTotal += delta;
      final dateIso = log.recordedDate?.toIsoString();
      if (dateIso != null) {
        dailyTotals[dateIso] = (dailyTotals[dateIso] ?? 0.0) + delta;
      }
      if (log.parentRecordId != null) {
        itemTotals[log.parentRecordId!] =
            (itemTotals[log.parentRecordId!] ?? 0.0) + delta;
      }
    }

    for (final rec in records) {
      if (rec.recordType == ProjectRecordType.progressLog) {
        addLog(rec);
      }
    }

    final todayTotal = dailyTotals[todayIso] ?? 0.0;

    switch (block.blockType) {
      case ProjectBlockType.counter:
        final percent = (block.targetValue != null && block.targetValue! > 0)
            ? (loggedTotal / block.targetValue! * 100.0).clamp(0.0, 100.0)
            : null;
        final pace = (block.targetValue != null &&
                block.targetValue! > 0 &&
                daysRemaining != null)
            ? ((block.targetValue! - loggedTotal).clamp(0.0, double.infinity)) /
                (daysRemaining > 0 ? daysRemaining : 1)
            : null;
        return ProjectBlockProgressMetric(
          blockId: block.id,
          blockType: block.blockType,
          title: block.title,
          unitLabel: block.unitLabel,
          isArchived: block.isArchived,
          loggedTotal: loggedTotal,
          targetValue: block.targetValue,
          progressPercent: percent,
          dailyTargetValue: block.dailyTargetValue,
          todayTotal: todayTotal,
          dailyTotalsByDate: dailyTotals,
          paceNeededPerDay: pace,
          daysRemaining: daysRemaining,
        );

      case ProjectBlockType.groupedList:
        final groups = records
            .where((r) => r.recordType == ProjectRecordType.group)
            .toList();
        final items = records
            .where((r) => r.recordType == ProjectRecordType.groupedItem)
            .toList();

        final itemsByGroup = <String, List<ProjectTrackingRecordEntity>>{};
        var summedItemTargets = 0.0;
        var hasAnyItemTarget = false;
        var completedItems = 0;
        var blockTargetCompletedTotal = 0.0;
        var blockOverTargetAmount = 0.0;
        var blockOverTargetItemCount = 0;
        final itemIds = <String>{};

        for (final item in items) {
          itemIds.add(item.id);
          if (item.parentRecordId != null) {
            itemsByGroup.putIfAbsent(item.parentRecordId!, () => []).add(item);
          }
          final itemTotal = itemTotals[item.id] ?? 0.0;
          final itemTarget = item.targetValue;
          if (itemTarget != null && itemTarget > 0) {
            hasAnyItemTarget = true;
            summedItemTargets += itemTarget;
            final capped = itemTotal < itemTarget ? itemTotal : itemTarget;
            final over = itemTotal > itemTarget ? itemTotal - itemTarget : 0.0;
            blockTargetCompletedTotal += capped;
            blockOverTargetAmount += over;
            if (over > 0) {
              blockOverTargetItemCount += 1;
            }
          } else {
            blockTargetCompletedTotal += itemTotal;
          }
          if (item.isCompleted ||
              (itemTarget != null &&
                  itemTarget > 0 &&
                  itemTotal >= itemTarget)) {
            completedItems += 1;
          }
        }

        for (final entry in itemTotals.entries) {
          if (!itemIds.contains(entry.key)) {
            blockTargetCompletedTotal += entry.value;
          }
        }

        final groupMetrics = <ProjectGroupMetric>[];
        for (final group in groups) {
          final children = itemsByGroup[group.id] ?? const [];
          var groupTotal = 0.0;
          var groupCappedTotal = 0.0;
          var groupOverTargetAmount = 0.0;
          var groupOverTargetItemCount = 0;
          var childTargetsSum = 0.0;
          var childCompleted = 0;
          for (final child in children) {
            final childTotal = itemTotals[child.id] ?? 0.0;
            groupTotal += childTotal;
            final childTarget = child.targetValue;
            if (childTarget != null && childTarget > 0) {
              childTargetsSum += childTarget;
              final capped =
                  childTotal < childTarget ? childTotal : childTarget;
              final over =
                  childTotal > childTarget ? childTotal - childTarget : 0.0;
              groupCappedTotal += capped;
              groupOverTargetAmount += over;
              if (over > 0) {
                groupOverTargetItemCount += 1;
              }
            } else {
              groupCappedTotal += childTotal;
            }
            if (child.isCompleted ||
                (childTarget != null &&
                    childTarget > 0 &&
                    childTotal >= childTarget)) {
              childCompleted += 1;
            }
          }
          final groupTarget = group.targetValue ??
              (childTargetsSum > 0 ? childTargetsSum : null);
          final groupPercent = (groupTarget != null && groupTarget > 0)
              ? (groupCappedTotal / groupTarget * 100.0).clamp(0.0, 100.0)
              : null;
          groupMetrics.add(
            ProjectGroupMetric(
              groupId: group.id,
              title: group.title ?? '',
              targetValue: groupTarget,
              loggedTotal: groupTotal,
              targetCompletedTotal: groupCappedTotal,
              overTargetAmount: groupOverTargetAmount,
              overTargetItemCount: groupOverTargetItemCount,
              itemCount: children.length,
              completedItemCount: childCompleted,
              progressPercent: groupPercent,
            ),
          );
        }

        final effectiveTarget =
            block.targetValue ?? (hasAnyItemTarget ? summedItemTargets : null);
        final effectiveCompleted =
            hasAnyItemTarget ? blockTargetCompletedTotal : loggedTotal;
        final effectiveOverTarget = hasAnyItemTarget
            ? blockOverTargetAmount
            : (effectiveTarget != null &&
                    effectiveTarget > 0 &&
                    loggedTotal > effectiveTarget
                ? loggedTotal - effectiveTarget
                : 0.0);
        final percent = (effectiveTarget != null && effectiveTarget > 0)
            ? (effectiveCompleted / effectiveTarget * 100.0).clamp(0.0, 100.0)
            : null;
        final pace = (effectiveTarget != null &&
                effectiveTarget > 0 &&
                daysRemaining != null)
            ? ((effectiveTarget - effectiveCompleted)
                    .clamp(0.0, double.infinity)) /
                (daysRemaining > 0 ? daysRemaining : 1)
            : null;

        return ProjectBlockProgressMetric(
          blockId: block.id,
          blockType: block.blockType,
          title: block.title,
          unitLabel: block.unitLabel,
          isArchived: block.isArchived,
          loggedTotal: loggedTotal,
          targetCompletedTotal: effectiveCompleted,
          overTargetAmount: effectiveOverTarget,
          overTargetItemCount: blockOverTargetItemCount,
          targetValue: effectiveTarget,
          progressPercent: percent,
          dailyTargetValue: block.dailyTargetValue,
          todayTotal: todayTotal,
          dailyTotalsByDate: dailyTotals,
          completedCount: completedItems,
          totalCount: items.length,
          itemTotals: itemTotals,
          groupMetrics: groupMetrics,
          paceNeededPerDay: pace,
          daysRemaining: daysRemaining,
        );

      case ProjectBlockType.checklist:
        final items = records
            .where((r) => r.recordType == ProjectRecordType.checklistItem)
            .toList();
        final completed = items.where((i) => i.isCompleted).length;
        final total = items.length;
        final percent =
            total > 0 ? (completed / total * 100.0).clamp(0.0, 100.0) : 0.0;
        return ProjectBlockProgressMetric(
          blockId: block.id,
          blockType: block.blockType,
          title: block.title,
          unitLabel: block.unitLabel,
          isArchived: block.isArchived,
          targetValue: block.targetValue ?? total.toDouble(),
          loggedTotal: completed.toDouble(),
          progressPercent: percent,
          dailyTargetValue: block.dailyTargetValue,
          completedCount: completed,
          totalCount: total,
        );

      case ProjectBlockType.schedule:
        final items = records
            .where((r) => r.recordType == ProjectRecordType.scheduleItem)
            .toList();
        final cfg = ScheduleBlockConfig.fromMap(block.config);
        final completed = items.where((i) => i.isCompleted).length;
        final total = items.length;
        var plannedMinutes = 0;
        for (final item in items) {
          plannedMinutes += item.durationMinutes ?? 0;
        }
        final actualMinutes = loggedTotal.round();
        double? percent;
        if (block.targetValue != null && block.targetValue! > 0) {
          percent =
              (loggedTotal / block.targetValue! * 100.0).clamp(0.0, 100.0);
        } else if (cfg.completionRule != ScheduleItemCompletionRule.manual &&
            plannedMinutes > 0) {
          percent = (loggedTotal / plannedMinutes * 100.0).clamp(0.0, 100.0);
        } else if (total > 0) {
          percent = (completed / total * 100.0).clamp(0.0, 100.0);
        } else {
          percent = 0.0;
        }

        return ProjectBlockProgressMetric(
          blockId: block.id,
          blockType: block.blockType,
          title: block.title,
          unitLabel: block.unitLabel,
          isArchived: block.isArchived,
          loggedTotal: loggedTotal,
          targetValue: block.targetValue ??
              (plannedMinutes > 0 ? plannedMinutes.toDouble() : null),
          progressPercent: percent,
          dailyTargetValue: block.dailyTargetValue,
          todayTotal: todayTotal,
          dailyTotalsByDate: dailyTotals,
          completedCount: completed,
          totalCount: total,
          plannedDurationMinutes: plannedMinutes,
          actualLoggedDurationMinutes: actualMinutes,
          itemTotals: itemTotals,
          daysRemaining: daysRemaining,
        );
    }
  }

  static ({int? totalDays, int? remainingDays, int? elapsedDays})
      computeScheduleSpan({
    required CalendarDate? startDate,
    required CalendarDate? targetDate,
    CalendarDate? asOfDate,
  }) {
    final reference = asOfDate ?? CalendarDate.today();
    int? totalDays;
    if (startDate != null &&
        targetDate != null &&
        !targetDate.isBefore(startDate)) {
      totalDays = targetDate.differenceInDays(startDate) + 1;
    }

    int? remainingDays;
    if (targetDate != null) {
      final diff = targetDate.differenceInDays(reference);
      remainingDays = diff >= 0 ? diff + 1 : 0;
    }

    int? elapsedDays;
    if (startDate != null) {
      final diff = reference.differenceInDays(startDate);
      elapsedDays = diff >= 0 ? diff + 1 : 0;
    }

    return (
      totalDays: totalDays,
      remainingDays: remainingDays,
      elapsedDays: elapsedDays,
    );
  }
}
