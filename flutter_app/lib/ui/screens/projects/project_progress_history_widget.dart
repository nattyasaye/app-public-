import 'package:flutter/material.dart';

import '../../../application/projects/projects_controller.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/projects/project_models.dart';
import '../../widgets/shared_ui_widgets.dart';
import 'project_ui_helpers.dart';

class ProjectProgressHistoryWidget extends StatelessWidget {
  final String projectId;
  final List<ProjectTrackingBlockEntity> blocks;
  final List<ProjectTrackingRecordEntity> records;
  final ProjectsController projectsController;

  const ProjectProgressHistoryWidget({
    super.key,
    required this.projectId,
    required this.blocks,
    required this.records,
    required this.projectsController,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;

    final blockById = <String, ProjectTrackingBlockEntity>{
      for (final b in blocks) b.id: b,
    };
    final recordById = <String, ProjectTrackingRecordEntity>{
      for (final r in records) r.id: r,
    };

    final logs = records
        .where((r) => r.recordType == ProjectRecordType.progressLog)
        .toList()
      ..sort((a, b) {
        final dateA = a.recordedDate?.toIsoString() ?? '';
        final dateB = b.recordedDate?.toIsoString() ?? '';
        final dateCmp = dateB.compareTo(dateA);
        if (dateCmp != 0) return dateCmp;
        return b.createdAt.compareTo(a.createdAt);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DaywellSectionHeader(
          title: 'Progress History',
          count: logs.length,
        ),
        const SizedBox(height: SharedDesignTokens.spacingSm),
        if (logs.isEmpty)
          DaywellCard(
            padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
            child: Row(
              children: [
                Icon(
                  Icons.history_outlined,
                  size: DaywellIconSize.md,
                  color: semantic.textMuted,
                ),
                const SizedBox(width: SharedDesignTokens.spacingSm),
                Expanded(
                  child: Text(
                    'No progress logs yet. Logged updates are append-only and can be corrected via compensating adjustments.',
                    style: textTheme.bodySmall?.copyWith(
                      color: semantic.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children: [
              for (final log in logs.take(25))
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: SharedDesignTokens.spacingSm,
                  ),
                  child: _buildLogCard(
                    context,
                    log: log,
                    block: blockById[log.blockId],
                    parentRecord: log.parentRecordId != null
                        ? recordById[log.parentRecordId!]
                        : null,
                  ),
                ),
              if (logs.length > 25)
                Padding(
                  padding: const EdgeInsets.only(
                    top: SharedDesignTokens.spacingXs,
                  ),
                  child: Text(
                    'Showing most recent 25 of ${logs.length} logs.',
                    style: textTheme.bodySmall?.copyWith(
                      color: semantic.textMuted,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildLogCard(
    BuildContext context, {
    required ProjectTrackingRecordEntity log,
    required ProjectTrackingBlockEntity? block,
    required ProjectTrackingRecordEntity? parentRecord,
  }) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final delta = log.deltaValue ?? 0.0;
    final deltaPrefix = delta >= 0 ? '+' : '';
    final unit = block?.unitLabel?.trim().isNotEmpty == true
        ? ' ${block!.unitLabel!.trim()}'
        : '';
    final formattedDelta = '$deltaPrefix${formatProjectNumber(delta)}$unit';

    return DaywellCard(
      padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: SharedDesignTokens.spacingSm,
              vertical: SharedDesignTokens.spacingXs,
            ),
            decoration: BoxDecoration(
              color: delta < 0
                  ? semantic.warningContainer
                  : colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
            ),
            child: Text(
              formattedDelta,
              style: DaywellTypography.numericBody(
                color: delta < 0
                    ? semantic.onWarningContainer
                    : colorScheme.onPrimaryContainer,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: SharedDesignTokens.spacingCompact),
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
                      block?.title ?? 'Deleted block',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (parentRecord?.title != null &&
                        parentRecord!.title!.isNotEmpty)
                      Text(
                        '· ${parentRecord.title!}',
                        style: textTheme.bodySmall?.copyWith(
                          color: semantic.textSecondary,
                        ),
                      ),
                    if (log.isCorrection)
                      const DaywellStatusBadge(
                        label: 'Adjustment',
                        tone: DaywellStatusTone.warning,
                      ),
                  ],
                ),
                const SizedBox(height: SharedDesignTokens.spacingXs),
                if (log.recordedDate != null)
                  Text(
                    SharedDateFormatter.formatDual(
                      log.recordedDate!,
                      useAmharic: false,
                    ),
                    style: textTheme.bodySmall?.copyWith(
                      color: semantic.textMuted,
                    ),
                  ),
                if (log.correctionReason != null &&
                    log.correctionReason!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: SharedDesignTokens.spacingXs,
                    ),
                    child: Text(
                      'Reason: ${log.correctionReason!}',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                  )
                else if (log.title != null && log.title!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: SharedDesignTokens.spacingXs,
                    ),
                    child: Text(
                      log.title!.trim(),
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!log.isCorrection)
            DaywellButton(
              label: 'Adjust',
              variant: DaywellButtonVariant.text,
              size: DaywellButtonSize.compact,
              onPressed: () => _showAdjustmentDialog(context, log),
            ),
        ],
      ),
    );
  }

  Future<void> _showAdjustmentDialog(
    BuildContext context,
    ProjectTrackingRecordEntity targetLog,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CompensatingAdjustmentDialog(
        targetLog: targetLog,
        projectsController: projectsController,
      ),
    );
  }
}

class _CompensatingAdjustmentDialog extends StatefulWidget {
  final ProjectTrackingRecordEntity targetLog;
  final ProjectsController projectsController;

  const _CompensatingAdjustmentDialog({
    required this.targetLog,
    required this.projectsController,
  });

  @override
  State<_CompensatingAdjustmentDialog> createState() =>
      _CompensatingAdjustmentDialogState();
}

class _CompensatingAdjustmentDialogState
    extends State<_CompensatingAdjustmentDialog> {
  late final TextEditingController _deltaCtrl;
  late final TextEditingController _reasonCtrl;
  late CalendarDate _recordedDate;
  String? _error;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final original = widget.targetLog.deltaValue ?? 0.0;
    _deltaCtrl = TextEditingController(
      text: original != 0 ? formatProjectNumber(-original) : '',
    );
    _reasonCtrl = TextEditingController();
    _recordedDate = widget.targetLog.recordedDate ?? CalendarDate.today();
  }

  @override
  void dispose() {
    _deltaCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final parsedDelta = double.tryParse(_deltaCtrl.text.trim());
    if (parsedDelta == null || !parsedDelta.isFinite || parsedDelta == 0) {
      setState(() => _error = 'Enter a non-zero numeric adjustment delta.');
      return;
    }
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Please provide a reason for this adjustment.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final created = await widget.projectsController.appendProgressCorrection(
      targetLogId: widget.targetLog.id,
      correctionDelta: parsedDelta,
      recordedDate: _recordedDate,
      reason: reason,
    );

    if (!mounted) return;
    if (created == null) {
      setState(() {
        _isSaving = false;
        _error = widget.projectsController.state.errorMessage ??
            'Could not save adjustment.';
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final origDelta = widget.targetLog.deltaValue ?? 0.0;

    return AlertDialog(
      scrollable: true,
      title: const Text('Compensating Adjustment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Progress logs are append-only. Record a signed adjustment against original delta ${origDelta >= 0 ? '+' : ''}${formatProjectNumber(origDelta)}.',
            style: textTheme.bodySmall?.copyWith(color: semantic.textSecondary),
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          if (_error != null) ...[
            DaywellStatusBanner(
              message: _error!,
              tone: DaywellStatusTone.error,
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
          ],
          DaywellTextField(
            controller: _deltaCtrl,
            label: 'Adjustment Delta (e.g. -5 or +2)',
            isRequired: true,
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          DaywellTextField(
            controller: _reasonCtrl,
            label: 'Reason',
            hintText: 'e.g. Corrected typo in logged total',
            isRequired: true,
            maxLines: 2,
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          DaywellCard(
            onTap: () async {
              final picked = await pickProjectCalendarDate(
                context,
                initialDate: _recordedDate,
                helpText: 'Adjustment Date',
              );
              if (picked != null && mounted) {
                setState(() => _recordedDate = picked);
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
                    SharedDateFormatter.formatDual(
                      _recordedDate,
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
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        ),
        DaywellButton(
          label: 'Record Adjustment',
          variant: DaywellButtonVariant.primary,
          size: DaywellButtonSize.compact,
          isLoading: _isSaving,
          onPressed: _isSaving ? null : _submit,
        ),
      ],
    );
  }
}
