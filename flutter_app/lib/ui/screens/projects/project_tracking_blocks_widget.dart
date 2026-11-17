import 'package:flutter/material.dart';

import '../../../application/projects/projects_controller.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/projects/progress_engine.dart';
import '../../../domain/projects/project_models.dart';
import '../../../domain/tasks/task_models.dart';
import '../../widgets/shared_ui_widgets.dart';
import 'project_ui_helpers.dart';

class ProjectTrackingBlocksWidget extends StatefulWidget {
  final ProjectEntity project;
  final List<ProjectTrackingBlockEntity> blocks;
  final List<ProjectTrackingRecordEntity> records;
  final ProjectProgressSummary? summary;
  final ProjectsController projectsController;

  const ProjectTrackingBlocksWidget({
    super.key,
    required this.project,
    required this.blocks,
    required this.records,
    required this.summary,
    required this.projectsController,
  });

  @override
  State<ProjectTrackingBlocksWidget> createState() =>
      _ProjectTrackingBlocksWidgetState();
}

class _ProjectTrackingBlocksWidgetState
    extends State<ProjectTrackingBlocksWidget> {
  final Map<String, TextEditingController> _checklistAddCtrls = {};
  final Map<String, TextEditingController> _groupedSearchCtrls = {};
  final Map<String, String> _groupedQueries = {};
  final Map<String, String> _groupedFilters = {};
  final Map<String, Set<String>> _collapsedGroupsByBlock = {};
  bool _showArchivedBlocks = false;

  @override
  void dispose() {
    for (final ctrl in _checklistAddCtrls.values) {
      ctrl.dispose();
    }
    for (final ctrl in _groupedSearchCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  TextEditingController _checklistControllerFor(String blockId) {
    return _checklistAddCtrls.putIfAbsent(
      blockId,
      () => TextEditingController(),
    );
  }

  TextEditingController _groupedSearchControllerFor(String blockId) {
    return _groupedSearchCtrls.putIfAbsent(
      blockId,
      () => TextEditingController(),
    );
  }

  ProjectBlockProgressMetric? _metricFor(String blockId) {
    final metrics = widget.summary?.blockMetrics ?? const [];
    for (final m in metrics) {
      if (m.blockId == blockId) return m;
    }
    return null;
  }

  Future<void> _togglePrimaryBlock(ProjectTrackingBlockEntity block) async {
    final currentPrimary = widget.summary?.primaryBlockId;
    final nextFields = Map<String, dynamic>.from(widget.project.customFields);
    if (currentPrimary == block.id) {
      nextFields.remove('primaryBlockId');
    } else {
      nextFields['primaryBlockId'] = block.id;
    }
    await widget.projectsController.updateProject(
      widget.project.copyWith(
        customFields: nextFields,
        updatedAt: EthiopiaClock.nowUtc(),
      ),
    );
  }

  Future<void> _archiveBlock(ProjectTrackingBlockEntity block) async {
    await widget.projectsController.setBlockArchived(block.id, true);
    if (widget.project.customFields['primaryBlockId'] == block.id) {
      final nextFields =
          Map<String, dynamic>.from(widget.project.customFields)
            ..remove('primaryBlockId');
      await widget.projectsController.updateProject(
        widget.project.copyWith(
          customFields: nextFields,
          updatedAt: EthiopiaClock.nowUtc(),
        ),
      );
    }
  }

  Future<void> _deleteArchivedBlock(ProjectTrackingBlockEntity block) async {
    final confirmed = await DaywellConfirmationDialog.show(
      context,
      title: 'Delete Archived Block?',
      message:
          'Permanently delete "${block.title}" and all of its items and progress logs?',
      confirmLabel: 'Delete Forever',
      isDestructive: true,
      icon: Icons.delete_forever_outlined,
    );
    if (!confirmed || !mounted) return;
    await widget.projectsController.deleteBlock(widget.project.id, block.id);
  }

  Future<void> _openBlockDialog({ProjectTrackingBlockEntity? existing}) async {
    final activeSiblings = widget.blocks
        .where((b) => !b.isArchived && b.id != existing?.id)
        .toList();
    await showDialog<void>(
      context: context,
      builder: (_) => _StandaloneBlockDialog(
        projectId: widget.project.id,
        existingBlock: existing,
        siblingBlocks: activeSiblings,
        nextSortOrder: widget.blocks.length,
        projectsController: widget.projectsController,
      ),
    );
  }

  Future<void> _openLogAmountDialog({
    required ProjectTrackingBlockEntity block,
    ProjectTrackingRecordEntity? targetItem,
    bool isScheduleDuration = false,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _LogAmountDialog(
        projectId: widget.project.id,
        block: block,
        targetItem: targetItem,
        isScheduleDuration: isScheduleDuration,
        allBlockRecords: widget.records
            .where((r) => r.blockId == block.id)
            .toList(growable: false),
        projectsController: widget.projectsController,
      ),
    );
  }

  Future<void> _openAddGroupOrItemDialog({
    required ProjectTrackingBlockEntity block,
    ProjectTrackingRecordEntity? parentGroup,
  }) async {
    final titleCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text(
            parentGroup == null
                ? 'Add Group to ${block.title}'
                : 'Add Item to ${parentGroup.title ?? "Group"}',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null) ...[
                DaywellStatusBanner(
                  message: error!,
                  tone: DaywellStatusTone.error,
                ),
                const SizedBox(height: SharedDesignTokens.spacingSm),
              ],
              DaywellTextField(
                controller: titleCtrl,
                label: parentGroup == null ? 'Group Title' : 'Item Title',
                hintText: parentGroup == null
                    ? 'e.g. Level 1 / Phase A'
                    : 'e.g. Doors & Windows',
                isRequired: true,
                autofocus: true,
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              DaywellTextField(
                controller: targetCtrl,
                label: 'Target Value (Optional)',
                hintText: 'e.g. 20',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
          actions: [
            DaywellButton(
              label: 'Cancel',
              variant: DaywellButtonVariant.text,
              size: DaywellButtonSize.compact,
              onPressed: () => Navigator.of(dialogCtx).pop(),
            ),
            DaywellButton(
              label: 'Add',
              variant: DaywellButtonVariant.primary,
              size: DaywellButtonSize.compact,
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) {
                  setDialogState(() => error = 'Title is required.');
                  return;
                }
                final rawTarget = targetCtrl.text.trim();
                final parsedTarget =
                    rawTarget.isEmpty ? null : double.tryParse(rawTarget);
                if (rawTarget.isNotEmpty &&
                    (parsedTarget == null || parsedTarget <= 0)) {
                  setDialogState(
                    () => error = 'Target must be a positive number.',
                  );
                  return;
                }
                await widget.projectsController.createRecord(
                  projectId: widget.project.id,
                  blockId: block.id,
                  parentRecordId: parentGroup?.id,
                  recordType: parentGroup == null
                      ? ProjectRecordType.group
                      : ProjectRecordType.groupedItem,
                  title: title,
                  targetValue: parsedTarget,
                );
                if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddScheduleItemDialog(
    ProjectTrackingBlockEntity block,
  ) async {
    final titleCtrl = TextEditingController();
    final durationCtrl = TextEditingController(text: '30');
    CalendarDate? scheduledDate = CalendarDate.today();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final semantic = ctx.daywellColors;
          final textTheme = Theme.of(ctx).textTheme;
          return AlertDialog(
            scrollable: true,
            title: Text('Add Session to ${block.title}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (error != null) ...[
                  DaywellStatusBanner(
                    message: error!,
                    tone: DaywellStatusTone.error,
                  ),
                  const SizedBox(height: SharedDesignTokens.spacingSm),
                ],
                DaywellTextField(
                  controller: titleCtrl,
                  label: 'Session Title',
                  hintText: 'e.g. Lesson 1 / Review',
                  isRequired: true,
                  autofocus: true,
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellTextField(
                  controller: durationCtrl,
                  label: 'Planned Duration (minutes)',
                  hintText: 'e.g. 45',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellCard(
                  onTap: () async {
                    final picked = await pickProjectCalendarDate(
                      ctx,
                      initialDate: scheduledDate,
                      helpText: 'Scheduled Date',
                    );
                    if (picked != null) {
                      setDialogState(() => scheduledDate = picked);
                    }
                  },
                  padding: const EdgeInsets.symmetric(
                    horizontal: SharedDesignTokens.spacingCompact,
                    vertical: SharedDesignTokens.spacingSm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: DaywellIconSize.sm,
                        color: semantic.textSecondary,
                      ),
                      const SizedBox(width: SharedDesignTokens.spacingSm),
                      Expanded(
                        child: Text(
                          scheduledDate == null
                              ? 'Unscheduled'
                              : SharedDateFormatter.formatDual(
                                  scheduledDate!,
                                  useAmharic: false,
                                ),
                          style: textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              DaywellButton(
                label: 'Cancel',
                variant: DaywellButtonVariant.text,
                size: DaywellButtonSize.compact,
                onPressed: () => Navigator.of(dialogCtx).pop(),
              ),
              DaywellButton(
                label: 'Add Session',
                variant: DaywellButtonVariant.primary,
                size: DaywellButtonSize.compact,
                onPressed: () async {
                  final title = titleCtrl.text.trim();
                  if (title.isEmpty) {
                    setDialogState(() => error = 'Session title is required.');
                    return;
                  }
                  final durRaw = durationCtrl.text.trim();
                  final parsedDur = durRaw.isEmpty ? null : int.tryParse(durRaw);
                  if (durRaw.isNotEmpty &&
                      (parsedDur == null || parsedDur <= 0)) {
                    setDialogState(
                      () => error = 'Duration must be a positive integer.',
                    );
                    return;
                  }
                  await widget.projectsController.createRecord(
                    projectId: widget.project.id,
                    blockId: block.id,
                    recordType: ProjectRecordType.scheduleItem,
                    title: title,
                    durationMinutes: parsedDur,
                    scheduledDate: scheduledDate,
                  );
                  if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final activeBlocks = widget.blocks.where((b) => !b.isArchived).toList();
    final archivedBlocks = widget.blocks.where((b) => b.isArchived).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DaywellSectionHeader(
          title: 'Tracking Blocks',
          count: activeBlocks.length,
          actionLabel: 'Add Block',
          onActionPressed: () => _openBlockDialog(),
        ),
        const SizedBox(height: SharedDesignTokens.spacingSm),
        if (activeBlocks.isEmpty)
          DaywellCard(
            padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No active tracking blocks yet.',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: SharedDesignTokens.spacingXs),
                Text(
                  'Add a counter, grouped list, checklist, or schedule block to track progress cleanly.',
                  style: textTheme.bodySmall?.copyWith(
                    color: semantic.textSecondary,
                  ),
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
                DaywellButton(
                  label: 'Add Tracking Block',
                  leadingIcon: Icons.add,
                  size: DaywellButtonSize.compact,
                  onPressed: () => _openBlockDialog(),
                ),
              ],
            ),
          )
        else
          for (final block in activeBlocks)
            Padding(
              padding: const EdgeInsets.only(
                bottom: SharedDesignTokens.spacingCompact,
              ),
              child: _buildActiveBlockCard(context, block),
            ),
        if (archivedBlocks.isNotEmpty) ...[
          const SizedBox(height: SharedDesignTokens.spacingSm),
          DaywellSectionHeader(
            title: 'Archived Blocks',
            count: archivedBlocks.length,
            actionLabel: _showArchivedBlocks ? 'Hide' : 'Show',
            onActionPressed: () => setState(
              () => _showArchivedBlocks = !_showArchivedBlocks,
            ),
          ),
          if (_showArchivedBlocks) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            for (final block in archivedBlocks)
              Padding(
                padding: const EdgeInsets.only(
                  bottom: SharedDesignTokens.spacingSm,
                ),
                child: DaywellCard(
                  padding: const EdgeInsets.all(
                    SharedDesignTokens.spacingCompact,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        blockTypeIcon(block.blockType),
                        size: DaywellIconSize.md,
                        color: semantic.textMuted,
                      ),
                      const SizedBox(width: SharedDesignTokens.spacingSm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              block.title,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              blockTypeLabel(block.blockType),
                              style: textTheme.bodySmall?.copyWith(
                                color: semantic.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DaywellButton(
                        label: 'Restore',
                        variant: DaywellButtonVariant.text,
                        size: DaywellButtonSize.compact,
                        onPressed: () => widget.projectsController
                            .setBlockArchived(block.id, false),
                      ),
                      DaywellIconButton(
                        icon: Icons.delete_forever_outlined,
                        tooltip: 'Delete block permanently',
                        isDestructive: true,
                        onPressed: () => _deleteArchivedBlock(block),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ],
    );
  }

  Widget _buildActiveBlockCard(
    BuildContext context,
    ProjectTrackingBlockEntity block,
  ) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final metric = _metricFor(block.id);
    final isPrimary = widget.summary?.primaryBlockId == block.id;
    final counterCfg = block.blockType == ProjectBlockType.counter
        ? CounterBlockConfig.fromMap(block.config)
        : null;
    final isRollup = counterCfg?.rollupSourceBlockId != null;

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  blockTypeIcon(block.blockType),
                  size: DaywellIconSize.md,
                  color: colorScheme.primary,
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
                          block.title,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (isPrimary)
                          const DaywellStatusBadge(
                            label: 'Primary',
                            tone: DaywellStatusTone.success,
                          ),
                        if (isRollup)
                          const DaywellStatusBadge(
                            label: 'Rollup',
                            tone: DaywellStatusTone.info,
                          ),
                      ],
                    ),
                    Text(
                      blockTypeLabel(block.blockType),
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              DaywellIconButton(
                icon: isPrimary ? Icons.star : Icons.star_outline,
                tooltip:
                    isPrimary ? 'Unset primary block' : 'Set as primary block',
                isSelected: isPrimary,
                onPressed: () => _togglePrimaryBlock(block),
              ),
              DaywellIconButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit block',
                onPressed: () => _openBlockDialog(existing: block),
              ),
              DaywellIconButton(
                icon: Icons.archive_outlined,
                tooltip: 'Archive block',
                onPressed: () => _archiveBlock(block),
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          switch (block.blockType) {
            ProjectBlockType.counter =>
              _buildCounterBody(context, block, metric, counterCfg!),
            ProjectBlockType.groupedList =>
              _buildGroupedListBody(context, block, metric),
            ProjectBlockType.checklist =>
              _buildChecklistBody(context, block, metric),
            ProjectBlockType.schedule =>
              _buildScheduleBody(context, block, metric),
          },
        ],
      ),
    );
  }

  Widget _buildCounterBody(
    BuildContext context,
    ProjectTrackingBlockEntity block,
    ProjectBlockProgressMetric? metric,
    CounterBlockConfig cfg,
  ) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final logged = metric?.loggedTotal ?? 0.0;
    final target = metric?.targetValue ?? block.targetValue;
    final pct = metric?.progressPercent;
    final unit = block.unitLabel?.trim().isNotEmpty == true
        ? ' ${block.unitLabel!.trim()}'
        : '';

    ProjectTrackingBlockEntity? sourceBlock;
    if (cfg.rollupSourceBlockId != null) {
      for (final b in widget.blocks) {
        if (b.id == cfg.rollupSourceBlockId) {
          sourceBlock = b;
          break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                target != null
                    ? '${formatProjectNumber(logged)} / ${formatProjectNumber(target)}$unit'
                    : '${formatProjectNumber(logged)}$unit logged',
                style: DaywellTypography.numericBody(
                  color: semantic.textPrimary,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (pct != null)
              Text(
                '${pct.round()}%',
                style: DaywellTypography.numericBody(
                  color: semantic.textSecondary,
                ),
              ),
          ],
        ),
        if (pct != null) ...[
          const SizedBox(height: SharedDesignTokens.spacingSm),
          DaywellProgressBar(
            value: pct / 100.0,
            semanticLabel: '${block.title} progress',
          ),
        ],
        if ((metric?.todayTotal ?? 0) > 0 ||
            block.dailyTargetValue != null ||
            metric?.paceNeededPerDay != null) ...[
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Text(
            [
              if ((metric?.todayTotal ?? 0) > 0)
                'Today: ${formatProjectNumber(metric!.todayTotal)}$unit',
              if (block.dailyTargetValue != null)
                'Daily goal: ${formatProjectNumber(block.dailyTargetValue!)}$unit',
              if (metric?.paceNeededPerDay != null &&
                  metric!.paceNeededPerDay! > 0)
                'Pace needed: ${formatProjectNumber(metric.paceNeededPerDay!)}$unit/day',
            ].join(' · '),
            style: textTheme.bodySmall?.copyWith(color: semantic.textMuted),
          ),
        ],
        const SizedBox(height: SharedDesignTokens.spacingCompact),
        if (cfg.rollupSourceBlockId != null || !cfg.allowDirectLogging)
          Text(
            'Rollup synced automatically from ${sourceBlock?.title ?? "source block"} (read-only).',
            style: textTheme.bodySmall?.copyWith(color: semantic.textMuted),
          )
        else
          Wrap(
            spacing: SharedDesignTokens.spacingSm,
            runSpacing: SharedDesignTokens.spacingXs,
            children: [
              DaywellButton(
                label: '+1',
                variant: DaywellButtonVariant.secondary,
                size: DaywellButtonSize.compact,
                onPressed: () => widget.projectsController.appendProgressLog(
                  projectId: widget.project.id,
                  blockId: block.id,
                  deltaValue: 1,
                  recordedDate: CalendarDate.today(),
                ),
              ),
              DaywellButton(
                label: 'Log Amount',
                leadingIcon: Icons.add,
                variant: DaywellButtonVariant.outlined,
                size: DaywellButtonSize.compact,
                onPressed: () => _openLogAmountDialog(block: block),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildGroupedListBody(
    BuildContext context,
    ProjectTrackingBlockEntity block,
    ProjectBlockProgressMetric? metric,
  ) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final cfg = GroupedListBlockConfig.fromMap(block.config);
    final groupNoun = (cfg.groupLabel?.trim().isNotEmpty == true)
        ? cfg.groupLabel!.trim()
        : 'Group';
    final itemNoun = (cfg.itemLabel?.trim().isNotEmpty == true)
        ? cfg.itemLabel!.trim()
        : 'Item';
    final blockRecords = widget.records
        .where((r) => r.blockId == block.id)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final groups =
        blockRecords.where((r) => r.recordType == ProjectRecordType.group).toList();
    final items = blockRecords
        .where((r) => r.recordType == ProjectRecordType.groupedItem)
        .toList();

    final pct = metric?.progressPercent;
    final unit = block.unitLabel?.trim().isNotEmpty == true
        ? ' ${block.unitLabel!.trim()}'
        : '';
    final cappedCompleted =
        metric?.targetCompletedTotal ?? metric?.loggedTotal ?? 0.0;
    final blockOver = metric?.overTargetAmount ?? 0.0;
    final blockOverItems = metric?.overTargetItemCount ?? 0;
    final remainingTotal = (metric?.targetValue != null &&
            metric!.targetValue! > 0)
        ? (metric.targetValue! - cappedCompleted).clamp(0.0, double.infinity)
        : null;

    final showToolbar = items.length > 6 || groups.length > 2;
    final searchCtrl = _groupedSearchControllerFor(block.id);
    final query = (_groupedQueries[block.id] ?? '').trim().toLowerCase();
    final statusFilter = _groupedFilters[block.id] ?? 'all';
    final collapsedSet = _collapsedGroupsByBlock.putIfAbsent(
      block.id,
      () => <String>{},
    );
    final allCollapsed =
        groups.isNotEmpty && groups.every((g) => collapsedSet.contains(g.id));

    bool matchesFilter(ProjectTrackingRecordEntity item) {
      final logged = metric?.itemTotals[item.id] ?? 0.0;
      final target = item.targetValue;
      final isOver = target != null && target > 0 && logged > target;
      final isDone =
          item.isCompleted || (target != null && target > 0 && logged >= target);
      switch (statusFilter) {
        case 'remaining':
          return !isDone;
        case 'done':
          return isDone;
        case 'over':
          return isOver;
        case 'all':
        default:
          return true;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pct != null) ...[
          DaywellProgressBar(
            value: pct / 100.0,
            label:
                '${formatProjectNumber(cappedCompleted)} / ${formatProjectNumber(metric?.targetValue ?? 0)}$unit',
            valueText: '${pct.round()}%',
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
        ],
        if ((cfg.showDailyTotals &&
                ((metric?.todayTotal ?? 0) > 0 ||
                    block.dailyTargetValue != null ||
                    metric?.paceNeededPerDay != null)) ||
            remainingTotal != null ||
            blockOver > 0) ...[
          Text(
            [
              if (cfg.showDailyTotals &&
                  (block.dailyTargetValue != null ||
                      (metric?.todayTotal ?? 0) > 0))
                'Today: ${formatProjectNumber(metric?.todayTotal ?? 0)}${block.dailyTargetValue != null ? ' / ${formatProjectNumber(block.dailyTargetValue!)}$unit' : unit}',
              if (remainingTotal != null)
                'Remaining: ${formatProjectNumber(remainingTotal)}$unit',
              if (cfg.showDailyTotals &&
                  metric?.paceNeededPerDay != null &&
                  metric!.paceNeededPerDay! > 0)
                'Pace needed: ${formatProjectNumber(metric.paceNeededPerDay!)}/day',
            ].join(' · '),
            style: DaywellTypography.numericBody(color: semantic.textSecondary),
          ),
          if (blockOver > 0) ...[
            const SizedBox(height: SharedDesignTokens.spacingXs),
            Text(
              'Actual sent: ${formatProjectNumber(metric?.loggedTotal ?? 0)}$unit (+${formatProjectNumber(blockOver)} over target)',
              style: DaywellTypography.numericBody(color: semantic.warning),
            ),
          ],
          const SizedBox(height: SharedDesignTokens.spacingCompact),
        ],
        if (showToolbar) ...[
          Row(
            children: [
              Expanded(
                child: DaywellSearchField(
                  controller: searchCtrl,
                  hintText:
                      'Search ${itemNoun.toLowerCase()}s or ${groupNoun.toLowerCase()}s...',
                  onChanged: (v) =>
                      setState(() => _groupedQueries[block.id] = v),
                  onCleared: () =>
                      setState(() => _groupedQueries[block.id] = ''),
                ),
              ),
              if (groups.isNotEmpty && query.isEmpty) ...[
                const SizedBox(width: SharedDesignTokens.spacingSm),
                DaywellButton(
                  label: allCollapsed ? 'Expand all' : 'Collapse all',
                  variant: DaywellButtonVariant.outlined,
                  size: DaywellButtonSize.compact,
                  onPressed: () {
                    setState(() {
                      if (allCollapsed) {
                        collapsedSet.clear();
                      } else {
                        collapsedSet.addAll(groups.map((g) => g.id));
                      }
                    });
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Wrap(
            spacing: SharedDesignTokens.spacingXs,
            runSpacing: SharedDesignTokens.spacingXs,
            children: [
              for (final f in <(String, String)>[
                ('all', 'All (${items.length})'),
                ('remaining', 'Remaining'),
                ('done', 'Done'),
                if (blockOverItems > 0) ('over', 'Over target ($blockOverItems)'),
              ])
                ChoiceChip(
                  label: Text(f.$2),
                  selected: statusFilter == f.$1,
                  onSelected: (_) =>
                      setState(() => _groupedFilters[block.id] = f.$1),
                ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DaywellButton(
            label: 'Add $groupNoun',
            leadingIcon: Icons.create_new_folder_outlined,
            variant: DaywellButtonVariant.outlined,
            size: DaywellButtonSize.compact,
            onPressed: () => _openAddGroupOrItemDialog(block: block),
          ),
        ),
        if (groups.isEmpty) ...[
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Text(
            'No groups yet. Create a group to organize trackable items.',
            style: textTheme.bodySmall?.copyWith(color: semantic.textMuted),
          ),
        ] else ...[
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          for (final group in groups) ...[
            Builder(
              builder: (context) {
                final rawChildren = items
                    .where((it) => it.parentRecordId == group.id)
                    .toList();
                final groupMatchesQuery = query.isNotEmpty &&
                    (group.title ?? '').toLowerCase().contains(query);
                final childItems = rawChildren.where((it) {
                  if (!matchesFilter(it)) return false;
                  if (query.isEmpty || groupMatchesQuery) return true;
                  return (it.title ?? '').toLowerCase().contains(query);
                }).toList();

                if ((query.isNotEmpty || statusFilter != 'all') &&
                    childItems.isEmpty &&
                    !(groupMatchesQuery && statusFilter == 'all')) {
                  return const SizedBox.shrink();
                }

                ProjectGroupMetric? groupMetric;
                for (final gm in metric?.groupMetrics ?? const []) {
                  if (gm.groupId == group.id) {
                    groupMetric = gm;
                    break;
                  }
                }
                final groupCompleted = groupMetric?.targetCompletedTotal ??
                    groupMetric?.loggedTotal ??
                    0.0;
                final groupOver = groupMetric?.overTargetAmount ?? 0.0;
                final groupTarget = groupMetric?.targetValue ?? group.targetValue;
                final isCollapsed = query.isEmpty &&
                    statusFilter == 'all' &&
                    collapsedSet.contains(group.id);

                return Container(
                  margin: const EdgeInsets.only(
                    bottom: SharedDesignTokens.spacingSm,
                  ),
                  padding: const EdgeInsets.all(
                    SharedDesignTokens.spacingCompact,
                  ),
                  decoration: BoxDecoration(
                    color: semantic.surfaceSubtle,
                    borderRadius: BorderRadius.circular(
                      SharedDesignTokens.radiusSm,
                    ),
                    border: Border.all(color: semantic.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          DaywellIconButton(
                            icon: isCollapsed
                                ? Icons.chevron_right
                                : Icons.expand_more,
                            tooltip: isCollapsed
                                ? 'Expand ${group.title ?? groupNoun}'
                                : 'Collapse ${group.title ?? groupNoun}',
                            onPressed: () {
                              setState(() {
                                if (collapsedSet.contains(group.id)) {
                                  collapsedSet.remove(group.id);
                                } else {
                                  collapsedSet.add(group.id);
                                }
                              });
                            },
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  if (collapsedSet.contains(group.id)) {
                                    collapsedSet.remove(group.id);
                                  } else {
                                    collapsedSet.add(group.id);
                                  }
                                });
                              },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: SharedDesignTokens.spacingXs,
                                    runSpacing: SharedDesignTokens.spacingXs,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        group.title ?? groupNoun,
                                        style: textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (groupOver > 0 && groupMetric != null)
                                        DaywellStatusBadge(
                                          label:
                                              '${formatProjectNumber(groupMetric.loggedTotal)} sent (+${formatProjectNumber(groupOver)})',
                                          tone: DaywellStatusTone.warning,
                                        ),
                                    ],
                                  ),
                                  if (cfg.showGroupTotals)
                                    Text(
                                      groupTarget != null
                                          ? '${formatProjectNumber(groupCompleted)} / ${formatProjectNumber(groupTarget)}$unit · ${groupMetric?.completedItemCount ?? 0}/${groupMetric?.itemCount ?? rawChildren.length} ${itemNoun.toLowerCase()}s'
                                          : '${formatProjectNumber(groupMetric?.loggedTotal ?? 0)}$unit logged',
                                      style: DaywellTypography.numericBody(
                                        color: semantic.textSecondary,
                                      ).copyWith(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          DaywellButton(
                            label: '+ $itemNoun',
                            variant: DaywellButtonVariant.text,
                            size: DaywellButtonSize.compact,
                            onPressed: () => _openAddGroupOrItemDialog(
                              block: block,
                              parentGroup: group,
                            ),
                          ),
                          DaywellIconButton(
                            icon: Icons.delete_outline,
                            tooltip: 'Delete group',
                            isDestructive: true,
                            onPressed: () async {
                              final confirmed =
                                  await DaywellConfirmationDialog.show(
                                context,
                                title: 'Delete $groupNoun?',
                                message:
                                    'Delete "${group.title ?? groupNoun}" and its items?',
                                confirmLabel: 'Delete',
                                isDestructive: true,
                              );
                              if (!confirmed) return;
                              await widget.projectsController.deleteRecord(
                                widget.project.id,
                                group.id,
                              );
                            },
                          ),
                        ],
                      ),
                      if (cfg.showGroupTotals &&
                          groupMetric?.progressPercent != null) ...[
                        const SizedBox(height: SharedDesignTokens.spacingXs),
                        DaywellProgressBar(
                          value: groupMetric!.progressPercent! / 100.0,
                          minHeight: 6,
                        ),
                      ],
                      if (!isCollapsed && childItems.isNotEmpty) ...[
                        const SizedBox(height: SharedDesignTokens.spacingSm),
                        for (final item in childItems)
                          Builder(
                            builder: (context) {
                              final itemLogged =
                                  metric?.itemTotals[item.id] ?? 0.0;
                              final itemTarget = item.targetValue;
                              final itemOver = (itemTarget != null &&
                                      itemTarget > 0 &&
                                      itemLogged > itemTarget)
                                  ? itemLogged - itemTarget
                                  : 0.0;
                              return Padding(
                                padding: const EdgeInsets.only(
                                  top: SharedDesignTokens.spacingXs,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Wrap(
                                            spacing:
                                                SharedDesignTokens.spacingXs,
                                            runSpacing:
                                                SharedDesignTokens.spacingXs,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                item.title ?? itemNoun,
                                                style: textTheme.bodyMedium,
                                              ),
                                              if (itemOver > 0)
                                                DaywellStatusBadge(
                                                  label:
                                                      'Over +${formatProjectNumber(itemOver)}',
                                                  tone:
                                                      DaywellStatusTone.warning,
                                                ),
                                            ],
                                          ),
                                          Text(
                                            itemTarget != null
                                                ? '${formatProjectNumber(itemLogged)} / ${formatProjectNumber(itemTarget)}$unit'
                                                : '${formatProjectNumber(itemLogged)}$unit',
                                            style:
                                                DaywellTypography.numericBody(
                                              color: semantic.textMuted,
                                            ).copyWith(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    DaywellButton(
                                      label: '+1',
                                      variant: DaywellButtonVariant.secondary,
                                      size: DaywellButtonSize.compact,
                                      onPressed: () => widget.projectsController
                                          .appendProgressLog(
                                        projectId: widget.project.id,
                                        blockId: block.id,
                                        parentRecordId: item.id,
                                        deltaValue: 1,
                                        recordedDate: CalendarDate.today(),
                                      ),
                                    ),
                                    const SizedBox(
                                      width: SharedDesignTokens.spacingXs,
                                    ),
                                    DaywellIconButton(
                                      icon: Icons.edit_note_outlined,
                                      tooltip: 'Log amount for item',
                                      onPressed: () => _openLogAmountDialog(
                                        block: block,
                                        targetItem: item,
                                      ),
                                    ),
                                    DaywellIconButton(
                                      icon: Icons.delete_outline,
                                      tooltip: 'Delete item',
                                      isDestructive: true,
                                      onPressed: () => widget
                                          .projectsController
                                          .deleteRecord(
                                        widget.project.id,
                                        item.id,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildChecklistBody(
    BuildContext context,
    ProjectTrackingBlockEntity block,
    ProjectBlockProgressMetric? metric,
  ) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final items = widget.records
        .where(
          (r) =>
              r.blockId == block.id &&
              r.recordType == ProjectRecordType.checklistItem,
        )
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final addCtrl = _checklistControllerFor(block.id);
    final completed = metric?.completedCount ??
        items.where((i) => i.isCompleted).length;
    final total = metric?.totalCount ?? items.length;
    final pct = total > 0 ? (completed / total) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DaywellProgressBar(
          value: pct,
          label: '$completed of $total complete',
          valueText: total > 0 ? '${(pct * 100).round()}%' : '0%',
        ),
        const SizedBox(height: SharedDesignTokens.spacingCompact),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: DaywellTextField(
                controller: addCtrl,
                hintText: 'Add checklist item...',
                onFieldSubmitted: (_) => _submitChecklistItem(block, addCtrl),
              ),
            ),
            const SizedBox(width: SharedDesignTokens.spacingSm),
            DaywellButton(
              label: 'Add',
              variant: DaywellButtonVariant.secondary,
              size: DaywellButtonSize.compact,
              onPressed: () => _submitChecklistItem(block, addCtrl),
            ),
          ],
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: SharedDesignTokens.spacingSm),
          for (final item in items)
            DaywellCheckboxTile(
              title: item.title ?? '',
              value: item.isCompleted,
              contentPadding: EdgeInsets.zero,
              secondary: DaywellIconButton(
                icon: Icons.delete_outline,
                tooltip: 'Delete checklist item',
                isDestructive: true,
                onPressed: () => widget.projectsController.deleteRecord(
                  widget.project.id,
                  item.id,
                ),
              ),
              onChanged: (checked) {
                final nextDone = checked ?? false;
                widget.projectsController.updateRecord(
                  ProjectTrackingRecordEntity(
                    id: item.id,
                    projectId: item.projectId,
                    blockId: item.blockId,
                    parentRecordId: item.parentRecordId,
                    recordType: item.recordType,
                    title: item.title,
                    sortOrder: item.sortOrder,
                    targetValue: item.targetValue,
                    deltaValue: item.deltaValue,
                    durationMinutes: item.durationMinutes,
                    isCompleted: nextDone,
                    completedAt: nextDone ? EthiopiaClock.nowUtc() : null,
                    recordedDate: item.recordedDate,
                    scheduledDate: item.scheduledDate,
                    linkedTaskId: item.linkedTaskId,
                    metadata: item.metadata,
                    createdAt: item.createdAt,
                    updatedAt: EthiopiaClock.nowUtc(),
                  ),
                );
              },
            ),
        ] else ...[
          const SizedBox(height: SharedDesignTokens.spacingSm),
          Text(
            'No checklist items yet.',
            style: textTheme.bodySmall?.copyWith(color: semantic.textMuted),
          ),
        ],
      ],
    );
  }

  Future<void> _submitChecklistItem(
    ProjectTrackingBlockEntity block,
    TextEditingController ctrl,
  ) async {
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    ctrl.clear();
    await widget.projectsController.createRecord(
      projectId: widget.project.id,
      blockId: block.id,
      recordType: ProjectRecordType.checklistItem,
      title: text,
    );
  }

  Widget _buildScheduleBody(
    BuildContext context,
    ProjectTrackingBlockEntity block,
    ProjectBlockProgressMetric? metric,
  ) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final cfg = ScheduleBlockConfig.fromMap(block.config);
    final items = widget.records
        .where(
          (r) =>
              r.blockId == block.id &&
              r.recordType == ProjectRecordType.scheduleItem,
        )
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final planned = metric?.plannedDurationMinutes ?? 0;
    final actual = metric?.actualLoggedDurationMinutes ?? 0;
    final pct = (metric?.progressPercent ?? 0) / 100.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DaywellProgressBar(
          value: pct,
          label: planned > 0
              ? '$actual / $planned min · ${metric?.completedCount ?? 0}/${metric?.totalCount ?? items.length} sessions'
              : '${metric?.completedCount ?? 0}/${metric?.totalCount ?? items.length} sessions',
          valueText: '${(metric?.progressPercent ?? 0).round()}%',
        ),
        const SizedBox(height: SharedDesignTokens.spacingXs),
        Text(
          'Rule: ${scheduleRuleLabel(cfg.completionRule)}${cfg.completionRule == ScheduleItemCompletionRule.thresholdPercent ? ' (${(cfg.autoCompleteThresholdRatio * 100).round()}%)' : ''}',
          style: textTheme.bodySmall?.copyWith(color: semantic.textMuted),
        ),
        const SizedBox(height: SharedDesignTokens.spacingCompact),
        DaywellButton(
          label: 'Add Session',
          leadingIcon: Icons.event_available_outlined,
          variant: DaywellButtonVariant.outlined,
          size: DaywellButtonSize.compact,
          onPressed: () => _openAddScheduleItemDialog(block),
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: SharedDesignTokens.spacingSm),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: SharedDesignTokens.spacingXs),
              child: Row(
                children: [
                  Checkbox(
                    value: item.isCompleted,
                    onChanged: (checked) {
                      final nextDone = checked ?? false;
                      widget.projectsController.updateRecord(
                        ProjectTrackingRecordEntity(
                          id: item.id,
                          projectId: item.projectId,
                          blockId: item.blockId,
                          parentRecordId: item.parentRecordId,
                          recordType: item.recordType,
                          title: item.title,
                          sortOrder: item.sortOrder,
                          targetValue: item.targetValue,
                          deltaValue: item.deltaValue,
                          durationMinutes: item.durationMinutes,
                          isCompleted: nextDone,
                          completedAt:
                              nextDone ? EthiopiaClock.nowUtc() : null,
                          recordedDate: item.recordedDate,
                          scheduledDate: item.scheduledDate,
                          linkedTaskId: item.linkedTaskId,
                          metadata: item.metadata,
                          createdAt: item.createdAt,
                          updatedAt: EthiopiaClock.nowUtc(),
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title ?? 'Session',
                          style: textTheme.bodyMedium?.copyWith(
                            decoration: item.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        Text(
                          [
                            if (item.scheduledDate != null)
                              SharedDateFormatter.formatDual(
                                item.scheduledDate!,
                                useAmharic: false,
                              ),
                            if (item.durationMinutes != null)
                              '${formatProjectNumber(metric?.itemTotals[item.id] ?? 0)} / ${item.durationMinutes} min'
                            else if ((metric?.itemTotals[item.id] ?? 0) > 0)
                              '${formatProjectNumber(metric!.itemTotals[item.id]!)} min logged',
                          ].join(' · '),
                          style: textTheme.bodySmall?.copyWith(
                            color: semantic.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (cfg.trackActualDuration)
                    DaywellButton(
                      label: 'Log',
                      variant: DaywellButtonVariant.text,
                      size: DaywellButtonSize.compact,
                      onPressed: () => _openLogAmountDialog(
                        block: block,
                        targetItem: item,
                        isScheduleDuration: true,
                      ),
                    ),
                  DaywellIconButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete session',
                    isDestructive: true,
                    onPressed: () => widget.projectsController.deleteRecord(
                      widget.project.id,
                      item.id,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _LogAmountDialog extends StatefulWidget {
  final String projectId;
  final ProjectTrackingBlockEntity block;
  final ProjectTrackingRecordEntity? targetItem;
  final bool isScheduleDuration;
  final List<ProjectTrackingRecordEntity> allBlockRecords;
  final ProjectsController projectsController;

  const _LogAmountDialog({
    required this.projectId,
    required this.block,
    this.targetItem,
    this.isScheduleDuration = false,
    required this.allBlockRecords,
    required this.projectsController,
  });

  @override
  State<_LogAmountDialog> createState() => _LogAmountDialogState();
}

class _LogAmountDialogState extends State<_LogAmountDialog> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  late CalendarDate _date;
  String? _error;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
      text: widget.isScheduleDuration &&
              widget.targetItem?.durationMinutes != null
          ? '${widget.targetItem!.durationMinutes}'
          : '1',
    );
    _noteCtrl = TextEditingController();
    _date = CalendarDate.today();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final parsed = double.tryParse(_amountCtrl.text.trim());
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      setState(() => _error = 'Enter a positive numeric amount.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final created = await widget.projectsController.appendProgressLog(
      projectId: widget.projectId,
      blockId: widget.block.id,
      parentRecordId: widget.targetItem?.id,
      deltaValue: parsed,
      recordedDate: _date,
      title: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );

    if (created == null) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = widget.projectsController.state.errorMessage ??
            'Failed to log progress.';
      });
      return;
    }

    // Apply explicit schedule duration completion rule if configured
    if (widget.isScheduleDuration && widget.targetItem != null) {
      final item = widget.targetItem!;
      if (!item.isCompleted) {
        final cfg = ScheduleBlockConfig.fromMap(widget.block.config);
        final priorLogged = widget.allBlockRecords
            .where(
              (r) =>
                  r.recordType == ProjectRecordType.progressLog &&
                  r.parentRecordId == item.id,
            )
            .fold<double>(0.0, (sum, r) => sum + (r.deltaValue ?? 0.0));
        final totalLogged = priorLogged + parsed;
        if (ProgressEngine.meetsScheduleDurationRule(
          plannedDurationMinutes: item.durationMinutes,
          actualLoggedMinutes: totalLogged,
          config: cfg,
        )) {
          await widget.projectsController.updateRecord(
            item.copyWith(
              isCompleted: true,
              completedAt: EthiopiaClock.nowUtc(),
              updatedAt: EthiopiaClock.nowUtc(),
            ),
          );
        }
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final unitSuffix = widget.isScheduleDuration
        ? 'minutes'
        : (widget.block.unitLabel?.trim().isNotEmpty == true
            ? widget.block.unitLabel!.trim()
            : 'units');

    final alreadyLogged = widget.targetItem != null
        ? widget.allBlockRecords
            .where(
              (r) =>
                  r.recordType == ProjectRecordType.progressLog &&
                  r.parentRecordId == widget.targetItem!.id,
            )
            .fold<double>(0.0, (sum, r) => sum + (r.deltaValue ?? 0.0))
        : null;
    final itemTarget = widget.targetItem?.targetValue;
    final remaining = (alreadyLogged != null &&
            itemTarget != null &&
            itemTarget > 0)
        ? (itemTarget - alreadyLogged).clamp(0.0, double.infinity)
        : null;
    final enteredAmount = double.tryParse(_amountCtrl.text.trim());
    final willExceedTarget = !widget.isScheduleDuration &&
        alreadyLogged != null &&
        itemTarget != null &&
        itemTarget > 0 &&
        enteredAmount != null &&
        enteredAmount > 0 &&
        alreadyLogged + enteredAmount > itemTarget;

    return AlertDialog(
      scrollable: true,
      title: Text(
        widget.targetItem != null
            ? 'Log for ${widget.targetItem!.title ?? widget.block.title}'
            : 'Log ${widget.block.title}',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            DaywellStatusBanner(
              message: _error!,
              tone: DaywellStatusTone.error,
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
          ],
          if (!widget.isScheduleDuration &&
              alreadyLogged != null &&
              itemTarget != null &&
              itemTarget > 0) ...[
            Text(
              'Logged: ${formatProjectNumber(alreadyLogged)} / ${formatProjectNumber(itemTarget)} $unitSuffix · Remaining: ${formatProjectNumber(remaining ?? 0)}',
              style: DaywellTypography.numericBody(
                color: semantic.textSecondary,
              ),
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
          ],
          DaywellTextField(
            controller: _amountCtrl,
            label: widget.isScheduleDuration
                ? 'Duration (minutes)'
                : 'Amount ($unitSuffix)',
            isRequired: true,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          if (!widget.isScheduleDuration) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            Wrap(
              spacing: SharedDesignTokens.spacingXs,
              runSpacing: SharedDesignTokens.spacingXs,
              children: [
                DaywellButton(
                  label: '+5',
                  variant: DaywellButtonVariant.outlined,
                  size: DaywellButtonSize.compact,
                  onPressed: () => setState(() => _amountCtrl.text = '5'),
                ),
                DaywellButton(
                  label: '+10',
                  variant: DaywellButtonVariant.outlined,
                  size: DaywellButtonSize.compact,
                  onPressed: () => setState(() => _amountCtrl.text = '10'),
                ),
                if (remaining != null && remaining > 0)
                  DaywellButton(
                    label: 'Left (${formatProjectNumber(remaining)})',
                    variant: DaywellButtonVariant.secondary,
                    size: DaywellButtonSize.compact,
                    onPressed: () => setState(
                      () => _amountCtrl.text = formatProjectNumber(remaining),
                    ),
                  ),
              ],
            ),
          ],
          if (willExceedTarget) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            DaywellStatusBanner(
              tone: DaywellStatusTone.warning,
              message:
                  'Exceeds target by +${formatProjectNumber(alreadyLogged + enteredAmount - itemTarget)}: actual sent count is saved, while excess does not inflate campaign completion.',
            ),
          ],
          if (widget.block.blockType != ProjectBlockType.groupedList) ...[
            const SizedBox(height: SharedDesignTokens.spacingCompact),
            DaywellTextField(
              controller: _noteCtrl,
              label: 'Note (Optional)',
              hintText: 'What did you finish?',
            ),
          ],
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          DaywellCard(
            onTap: () async {
              final picked = await pickProjectCalendarDate(
                context,
                initialDate: _date,
                helpText: 'Log Date',
              );
              if (picked != null && mounted) {
                setState(() => _date = picked);
              }
            },
            padding: const EdgeInsets.symmetric(
              horizontal: SharedDesignTokens.spacingCompact,
              vertical: SharedDesignTokens.spacingSm,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: DaywellIconSize.sm,
                  color: semantic.textSecondary,
                ),
                const SizedBox(width: SharedDesignTokens.spacingSm),
                Expanded(
                  child: Text(
                    SharedDateFormatter.formatDual(_date, useAmharic: false),
                    style: textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        DaywellButton(
          label: 'Cancel',
          variant: DaywellButtonVariant.text,
          size: DaywellButtonSize.compact,
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        ),
        DaywellButton(
          label: 'Log Progress',
          variant: DaywellButtonVariant.primary,
          size: DaywellButtonSize.compact,
          isLoading: _isSaving,
          onPressed: _isSaving ? null : _submit,
        ),
      ],
    );
  }
}

class _StandaloneBlockDialog extends StatefulWidget {
  final String projectId;
  final ProjectTrackingBlockEntity? existingBlock;
  final List<ProjectTrackingBlockEntity> siblingBlocks;
  final int nextSortOrder;
  final ProjectsController projectsController;

  const _StandaloneBlockDialog({
    required this.projectId,
    this.existingBlock,
    required this.siblingBlocks,
    required this.nextSortOrder,
    required this.projectsController,
  });

  @override
  State<_StandaloneBlockDialog> createState() => _StandaloneBlockDialogState();
}

class _StandaloneBlockDialogState extends State<_StandaloneBlockDialog> {
  late ProjectBlockType _blockType;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _targetCtrl;
  late final TextEditingController _dailyTargetCtrl;
  late final TextEditingController _thresholdCtrl;
  bool _isRollup = false;
  String? _rollupSourceId;
  bool _showGroupTotals = true;
  bool _showDailyTotals = true;
  ScheduleItemCompletionRule _completionRule = ScheduleItemCompletionRule.manual;
  bool _trackActualDuration = true;
  String? _error;
  bool _isSaving = false;

  bool get _isEditing => widget.existingBlock != null;

  @override
  void initState() {
    super.initState();
    final b = widget.existingBlock;
    _blockType = b?.blockType ?? ProjectBlockType.counter;
    _titleCtrl = TextEditingController(text: b?.title ?? '');
    _unitCtrl = TextEditingController(text: b?.unitLabel ?? '');
    _targetCtrl = TextEditingController(
      text: b?.targetValue != null ? formatProjectNumber(b!.targetValue!) : '',
    );
    _dailyTargetCtrl = TextEditingController(
      text: b?.dailyTargetValue != null
          ? formatProjectNumber(b!.dailyTargetValue!)
          : '',
    );

    if (b != null) {
      final counterCfg = CounterBlockConfig.fromMap(b.config);
      final groupedCfg = GroupedListBlockConfig.fromMap(b.config);
      final scheduleCfg = ScheduleBlockConfig.fromMap(b.config);
      _isRollup = b.blockType == ProjectBlockType.counter &&
          counterCfg.rollupSourceBlockId != null;
      _rollupSourceId = counterCfg.rollupSourceBlockId;
      _showGroupTotals = groupedCfg.showGroupTotals;
      _showDailyTotals = groupedCfg.showDailyTotals;
      _completionRule = scheduleCfg.completionRule;
      _thresholdCtrl = TextEditingController(
        text: formatProjectNumber(
          (scheduleCfg.autoCompleteThresholdRatio * 100).clamp(1, 100),
        ),
      );
      _trackActualDuration = scheduleCfg.trackActualDuration;
    } else {
      _thresholdCtrl = TextEditingController(text: '80');
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _unitCtrl.dispose();
    _targetCtrl.dispose();
    _dailyTargetCtrl.dispose();
    _thresholdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Block title is required.');
      return;
    }

    final targetRaw = _targetCtrl.text.trim();
    final targetValue = targetRaw.isEmpty ? null : double.tryParse(targetRaw);
    if (targetRaw.isNotEmpty && (targetValue == null || targetValue <= 0)) {
      setState(() => _error = 'Target value must be a positive number.');
      return;
    }

    final dailyRaw = _dailyTargetCtrl.text.trim();
    final dailyTargetValue =
        dailyRaw.isEmpty ? null : double.tryParse(dailyRaw);
    if (dailyRaw.isNotEmpty &&
        (dailyTargetValue == null || dailyTargetValue <= 0)) {
      setState(() => _error = 'Daily target must be a positive number.');
      return;
    }

    final eligibleSources = widget.siblingBlocks
        .where(
          (s) =>
              !(s.blockType == ProjectBlockType.counter &&
                  CounterBlockConfig.fromMap(s.config).rollupSourceBlockId !=
                      null),
        )
        .toList();

    if (_blockType == ProjectBlockType.counter &&
        _isRollup &&
        (_rollupSourceId == null ||
            !eligibleSources.any((s) => s.id == _rollupSourceId))) {
      setState(() => _error = 'Select a source tracking block for this rollup.');
      return;
    }

    double thresholdRatio = 0.8;
    if (_blockType == ProjectBlockType.schedule &&
        _completionRule == ScheduleItemCompletionRule.thresholdPercent) {
      final parsed = double.tryParse(_thresholdCtrl.text.trim());
      if (parsed == null || parsed <= 0 || parsed > 100) {
        setState(() => _error = 'Threshold % must be between 1 and 100.');
        return;
      }
      thresholdRatio = parsed / 100.0;
    }

    final cfg = Map<String, dynamic>.from(
      widget.existingBlock?.config ?? const <String, dynamic>{},
    );
    switch (_blockType) {
      case ProjectBlockType.counter:
        if (_isRollup && _rollupSourceId != null) {
          cfg['rollupSourceBlockId'] = _rollupSourceId;
          cfg['allowDirectLogging'] = false;
        } else {
          cfg.remove('rollupSourceBlockId');
          cfg['allowDirectLogging'] = true;
        }
      case ProjectBlockType.groupedList:
        cfg['showGroupTotals'] = _showGroupTotals;
        cfg['showDailyTotals'] = _showDailyTotals;
      case ProjectBlockType.checklist:
        cfg['allowReorder'] = true;
      case ProjectBlockType.schedule:
        cfg['completionRule'] = _completionRule.wireValue;
        cfg['autoCompleteThresholdRatio'] = thresholdRatio.clamp(0.01, 1.0);
        cfg['trackActualDuration'] = _trackActualDuration;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final unitLabel =
        _unitCtrl.text.trim().isEmpty ? null : _unitCtrl.text.trim();

    ProjectTrackingBlockEntity? saved;
    if (_isEditing) {
      final orig = widget.existingBlock!;
      saved = await widget.projectsController.updateBlock(
        ProjectTrackingBlockEntity(
          id: orig.id,
          projectId: orig.projectId,
          blockType: orig.blockType,
          title: title,
          sortOrder: orig.sortOrder,
          unitLabel: unitLabel,
          targetValue: targetValue,
          dailyTargetValue: dailyTargetValue,
          config: cfg,
          isArchived: orig.isArchived,
          createdAt: orig.createdAt,
          updatedAt: EthiopiaClock.nowUtc(),
        ),
      );
    } else {
      saved = await widget.projectsController.createBlock(
        projectId: widget.projectId,
        blockType: _blockType,
        title: title,
        sortOrder: widget.nextSortOrder,
        unitLabel: unitLabel,
        targetValue: targetValue,
        dailyTargetValue: dailyTargetValue,
        config: cfg,
      );
    }

    if (!mounted) return;
    if (saved == null) {
      setState(() {
        _isSaving = false;
        _error = widget.projectsController.state.errorMessage ??
            'Could not save tracking block.';
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final eligibleSources = widget.siblingBlocks
        .where(
          (s) =>
              !(s.blockType == ProjectBlockType.counter &&
                  CounterBlockConfig.fromMap(s.config).rollupSourceBlockId !=
                      null),
        )
        .toList();

    return AlertDialog(
      scrollable: true,
      title: Text(_isEditing ? 'Edit Tracking Block' : 'Add Tracking Block'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            DaywellStatusBanner(
              message: _error!,
              tone: DaywellStatusTone.error,
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
          ],
          DaywellDropdownField<ProjectBlockType>(
            value: _blockType,
            label: 'Block Type',
            enabled: !_isEditing,
            helperText:
                _isEditing ? 'Block type cannot be changed after creation.' : null,
            items: ProjectBlockType.values
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(blockTypeLabel(t)),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _blockType = v);
            },
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          DaywellTextField(
            controller: _titleCtrl,
            label: 'Block Title',
            isRequired: true,
            autofocus: true,
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          Row(
            children: [
              Expanded(
                child: DaywellTextField(
                  controller: _unitCtrl,
                  label: 'Unit (Optional)',
                ),
              ),
              const SizedBox(width: SharedDesignTokens.spacingSm),
              Expanded(
                child: DaywellTextField(
                  controller: _targetCtrl,
                  label: 'Target (Optional)',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ],
          ),
          if (_blockType == ProjectBlockType.counter ||
              _blockType == ProjectBlockType.groupedList) ...[
            const SizedBox(height: SharedDesignTokens.spacingCompact),
            DaywellTextField(
              controller: _dailyTargetCtrl,
              label: 'Daily Target (Optional)',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
          if (_blockType == ProjectBlockType.counter) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            DaywellSwitchTile(
              title: 'Rollup from another block',
              value: _isRollup,
              enabled: eligibleSources.isNotEmpty || _isRollup,
              onChanged: (val) {
                setState(() {
                  _isRollup = val;
                  if (val &&
                      _rollupSourceId == null &&
                      eligibleSources.isNotEmpty) {
                    _rollupSourceId = eligibleSources.first.id;
                  }
                });
              },
            ),
            if (_isRollup) ...[
              const SizedBox(height: SharedDesignTokens.spacingSm),
              DaywellDropdownField<String?>(
                value: eligibleSources.any((s) => s.id == _rollupSourceId)
                    ? _rollupSourceId
                    : null,
                label: 'Source Block',
                items: eligibleSources
                    .map(
                      (s) => DropdownMenuItem<String?>(
                        value: s.id,
                        child: Text(s.title),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _rollupSourceId = v),
              ),
            ],
          ],
          if (_blockType == ProjectBlockType.groupedList) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            DaywellSwitchTile(
              title: 'Show group totals',
              value: _showGroupTotals,
              onChanged: (v) => setState(() => _showGroupTotals = v),
            ),
            DaywellSwitchTile(
              title: 'Show daily totals',
              value: _showDailyTotals,
              onChanged: (v) => setState(() => _showDailyTotals = v),
            ),
          ],
          if (_blockType == ProjectBlockType.schedule) ...[
            const SizedBox(height: SharedDesignTokens.spacingCompact),
            DaywellDropdownField<ScheduleItemCompletionRule>(
              value: _completionRule,
              label: 'Session Completion Rule',
              items: ScheduleItemCompletionRule.values
                  .map(
                    (r) => DropdownMenuItem(
                      value: r,
                      child: Text(scheduleRuleLabel(r)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _completionRule = v);
              },
            ),
            if (_completionRule ==
                ScheduleItemCompletionRule.thresholdPercent) ...[
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              DaywellTextField(
                controller: _thresholdCtrl,
                label: 'Auto-Complete Threshold (%)',
                keyboardType: TextInputType.number,
              ),
            ],
            const SizedBox(height: SharedDesignTokens.spacingSm),
            DaywellSwitchTile(
              title: 'Track actual duration (minutes)',
              value: _trackActualDuration,
              onChanged: (v) => setState(() => _trackActualDuration = v),
            ),
          ],
        ],
      ),
      actions: [
        DaywellButton(
          label: 'Cancel',
          variant: DaywellButtonVariant.text,
          size: DaywellButtonSize.compact,
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        ),
        DaywellButton(
          label: _isEditing ? 'Save Block' : 'Add Block',
          variant: DaywellButtonVariant.primary,
          size: DaywellButtonSize.compact,
          isLoading: _isSaving,
          onPressed: _isSaving ? null : _submit,
        ),
      ],
    );
  }
}
