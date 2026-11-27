import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/projects/projects_controller.dart';
import '../../../application/tasks/tasks_controller.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/projects/project_models.dart';
import '../../../domain/tasks/task_models.dart';
import '../../widgets/shared_ui_widgets.dart';
import 'project_ui_helpers.dart';

class ProjectFormSheet extends StatefulWidget {
  final ProjectsController projectsController;
  final TasksController? tasksController;
  final ProjectEntity? existingProject;

  const ProjectFormSheet({
    super.key,
    required this.projectsController,
    this.tasksController,
    this.existingProject,
  });

  static Future<ProjectEntity?> show(
    BuildContext context, {
    required ProjectsController projectsController,
    TasksController? tasksController,
    ProjectEntity? existingProject,
  }) {
    return showModalBottomSheet<ProjectEntity>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SharedDesignTokens.radiusSheet),
        ),
      ),
      builder: (_) => ProjectFormSheet(
        projectsController: projectsController,
        tasksController: tasksController,
        existingProject: existingProject,
      ),
    );
  }

  @override
  State<ProjectFormSheet> createState() => _ProjectFormSheetState();
}

class _InlineBlockDraft {
  final String tempId;
  final bool isExisting;
  final ProjectTrackingBlockEntity? originalBlock;
  ProjectBlockType blockType;
  String title;
  String unitLabel;
  double? targetValue;
  double? dailyTargetValue;
  bool isRollup;
  String? rollupSourceTempId;
  bool showGroupTotals;
  bool showDailyTotals;
  ScheduleItemCompletionRule completionRule;
  double thresholdPercent;
  bool trackActualDuration;

  _InlineBlockDraft({
    required this.tempId,
    required this.isExisting,
    this.originalBlock,
    required this.blockType,
    required this.title,
    this.unitLabel = '',
    this.targetValue,
    this.dailyTargetValue,
    this.isRollup = false,
    this.rollupSourceTempId,
    this.showGroupTotals = true,
    this.showDailyTotals = true,
    this.completionRule = ScheduleItemCompletionRule.manual,
    this.thresholdPercent = 80,
    this.trackActualDuration = true,
  });

  factory _InlineBlockDraft.fromExisting(ProjectTrackingBlockEntity block) {
    final counterCfg = CounterBlockConfig.fromMap(block.config);
    final groupedCfg = GroupedListBlockConfig.fromMap(block.config);
    final scheduleCfg = ScheduleBlockConfig.fromMap(block.config);
    return _InlineBlockDraft(
      tempId: block.id,
      isExisting: true,
      originalBlock: block,
      blockType: block.blockType,
      title: block.title,
      unitLabel: block.unitLabel ?? '',
      targetValue: block.targetValue,
      dailyTargetValue: block.dailyTargetValue,
      isRollup: block.blockType == ProjectBlockType.counter &&
          counterCfg.rollupSourceBlockId != null,
      rollupSourceTempId: counterCfg.rollupSourceBlockId,
      showGroupTotals: groupedCfg.showGroupTotals,
      showDailyTotals: groupedCfg.showDailyTotals,
      completionRule: scheduleCfg.completionRule,
      thresholdPercent:
          (scheduleCfg.autoCompleteThresholdRatio * 100).clamp(1, 100),
      trackActualDuration: scheduleCfg.trackActualDuration,
    );
  }

  Map<String, dynamic> buildConfig(Map<String, String> tempToRealId) {
    final base = Map<String, dynamic>.from(originalBlock?.config ?? const {});
    switch (blockType) {
      case ProjectBlockType.counter:
        if (isRollup && rollupSourceTempId != null) {
          final resolved =
              tempToRealId[rollupSourceTempId!] ?? rollupSourceTempId!;
          base['rollupSourceBlockId'] = resolved;
          base['allowDirectLogging'] = false;
        } else {
          base.remove('rollupSourceBlockId');
          base['allowDirectLogging'] = true;
        }
        return base;
      case ProjectBlockType.groupedList:
        base['showGroupTotals'] = showGroupTotals;
        base['showDailyTotals'] = showDailyTotals;
        return base;
      case ProjectBlockType.checklist:
        base['allowReorder'] = true;
        return base;
      case ProjectBlockType.schedule:
        base['completionRule'] = completionRule.wireValue;
        base['autoCompleteThresholdRatio'] =
            (thresholdPercent / 100.0).clamp(0.01, 1.0);
        base['trackActualDuration'] = trackActualDuration;
        return base;
    }
  }
}

class _ProjectFormSheetState extends State<ProjectFormSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late String _status;
  CalendarDate? _startDate;
  CalendarDate? _targetDate;
  String? _primaryDraftId;
  final List<_InlineBlockDraft> _blocks = [];
  int _draftCounter = 0;

  String? _titleError;
  String? _formError;
  bool _isSaving = false;
  bool _didSave = false;
  bool _isPromptingDiscard = false;
  bool _lastHasUnsavedChanges = false;

  late String _initialTitle;
  late String _initialDesc;
  late String _initialStatus;
  CalendarDate? _initialStartDate;
  CalendarDate? _initialTargetDate;
  String? _initialPrimaryDraftId;
  late String _initialBlocksSignature;

  bool get _isEditing => widget.existingProject != null;

  String _computeBlocksSignature() {
    return _blocks
        .map(
          (b) =>
              '${b.tempId}|${b.blockType.name}|${b.title.trim()}|${b.unitLabel.trim()}|${b.targetValue}|${b.dailyTargetValue}|${b.isRollup}|${b.rollupSourceTempId}|${b.showGroupTotals}|${b.showDailyTotals}|${b.completionRule.name}|${b.thresholdPercent}|${b.trackActualDuration}',
        )
        .join(';;');
  }

  bool get _hasUnsavedChanges {
    if (_didSave) return false;
    return _titleCtrl.text.trim() != _initialTitle ||
        _descCtrl.text.trim() != _initialDesc ||
        _status != _initialStatus ||
        _startDate != _initialStartDate ||
        _targetDate != _initialTargetDate ||
        _primaryDraftId != _initialPrimaryDraftId ||
        _computeBlocksSignature() != _initialBlocksSignature;
  }

  void _onTextDirtyChanged() {
    if (!mounted) return;
    final next = _hasUnsavedChanges;
    if (next != _lastHasUnsavedChanges) {
      _lastHasUnsavedChanges = next;
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existingProject;
    _titleCtrl = TextEditingController(text: existing?.title ?? '');
    _descCtrl = TextEditingController(text: existing?.description ?? '');
    _status = existing?.status ?? 'active';
    _startDate = existing?.startDate;
    _targetDate = existing?.targetDate;

    if (existing != null) {
      final existingBlocks = widget.projectsController.state
          .blocksForProject(existing.id, includeArchived: false);
      for (final block in existingBlocks) {
        _blocks.add(_InlineBlockDraft.fromExisting(block));
      }
      final existingPrimary = ProjectCustomFieldsPayload.fromMap(
        existing.customFields,
      ).primaryBlockId;
      if (existingPrimary != null &&
          _blocks.any((b) => b.tempId == existingPrimary)) {
        _primaryDraftId = existingPrimary;
      }
    }

    _initialTitle = _titleCtrl.text.trim();
    _initialDesc = _descCtrl.text.trim();
    _initialStatus = _status;
    _initialStartDate = _startDate;
    _initialTargetDate = _targetDate;
    _initialPrimaryDraftId = _primaryDraftId;
    _initialBlocksSignature = _computeBlocksSignature();

    _titleCtrl.addListener(_onTextDirtyChanged);
    _descCtrl.addListener(_onTextDirtyChanged);
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_onTextDirtyChanged);
    _descCtrl.removeListener(_onTextDirtyChanged);
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _handlePopBlocked() async {
    if (_isSaving || _isPromptingDiscard || !mounted) return;
    _isPromptingDiscard = true;
    try {
      final action = await DaywellUnsavedChangesDialog.show(
        context,
        title: _isEditing ? 'Discard Project Changes?' : 'Discard Project?',
        message: _isEditing
            ? 'Save your project changes or discard them?'
            : 'Create this project or discard your edits?',
        saveLabel: _isEditing ? 'Save Changes' : 'Create Project',
        discardLabel: 'Discard',
      );
      if (!mounted) return;
      if (action == DaywellUnsavedChangesAction.save) {
        await _handleSave();
      } else if (action == DaywellUnsavedChangesAction.discard) {
        setState(() => _didSave = true);
        Navigator.of(context).pop();
      }
    } finally {
      _isPromptingDiscard = false;
    }
  }

  Future<void> _openInlineBlockEditor({_InlineBlockDraft? editingDraft}) async {
    final result = await _InlineBlockEditorDialog.show(
      context,
      existingDraft: editingDraft,
      siblingDrafts: _blocks
          .where((b) => editingDraft == null || b.tempId != editingDraft.tempId)
          .toList(growable: false),
      nextTempId: 'draft-${++_draftCounter}',
    );
    if (result == null || !mounted) return;
    setState(() {
      if (editingDraft != null) {
        final idx = _blocks.indexWhere((b) => b.tempId == editingDraft.tempId);
        if (idx >= 0) {
          _blocks[idx] = result;
        }
      } else {
        _blocks.add(result);
      }
      _formError = null;
    });
  }

  Future<void> _handleSave() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() {
        _titleError = 'Project title is required.';
        _formError = null;
      });
      return;
    }

    if (_startDate != null &&
        _targetDate != null &&
        _targetDate!.isBefore(_startDate!)) {
      setState(() {
        _titleError = null;
        _formError = 'Target date cannot be earlier than start date.';
      });
      return;
    }

    for (final block in _blocks) {
      if (block.title.trim().isEmpty) {
        setState(() => _formError = 'Every tracking block must have a title.');
        return;
      }
      if (block.blockType == ProjectBlockType.counter && block.isRollup) {
        final hasValidSource = block.rollupSourceTempId != null &&
            _blocks.any(
              (other) =>
                  other.tempId == block.rollupSourceTempId &&
                  !(other.blockType == ProjectBlockType.counter &&
                      other.isRollup),
            );
        if (!hasValidSource) {
          setState(() {
            _formError =
                'Rollup counter "${block.title}" needs a non-rollup source block.';
          });
          return;
        }
      }
    }

    setState(() {
      _isSaving = true;
      _titleError = null;
      _formError = null;
    });

    try {
      final controller = widget.projectsController;
      final existing = widget.existingProject;
      final descText = _descCtrl.text.trim();
      final String? normalizedDesc = descText.isEmpty ? null : descText;

      final Map<String, dynamic> customFields = Map<String, dynamic>.from(
        existing?.customFields ?? const <String, dynamic>{},
      );
      if (_primaryDraftId == null) {
        customFields.remove('primaryBlockId');
      } else {
        customFields['primaryBlockId'] = _primaryDraftId;
      }

      ProjectEntity? savedProject;
      if (existing == null) {
        savedProject = await controller.createProject(
          title: title,
          description: normalizedDesc,
          status: _status,
          startDate: _startDate,
          targetDate: _targetDate,
          customFields: customFields,
        );
      } else {
        final updatedEntity = ProjectEntity(
          id: existing.id,
          title: title,
          description: normalizedDesc,
          status: _status,
          startDate: _startDate,
          targetDate: _targetDate,
          goalId: existing.goalId,
          isArchived: existing.isArchived,
          customFields: customFields,
          createdAt: existing.createdAt,
          updatedAt: EthiopiaClock.nowUtc(),
        );
        savedProject = await controller.updateProject(updatedEntity);
      }

      if (savedProject == null) {
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _formError =
              controller.state.errorMessage ?? 'Could not save project.';
        });
        return;
      }

      final projectId = savedProject.id;
      final tempToRealId = <String, String>{};
      for (final block in _blocks) {
        if (block.isExisting) {
          tempToRealId[block.tempId] = block.tempId;
        }
      }

      // First pass: update existing blocks & create non-rollup new blocks
      for (var i = 0; i < _blocks.length; i++) {
        final draft = _blocks[i];
        final isRollup =
            draft.blockType == ProjectBlockType.counter && draft.isRollup;
        if (isRollup && !draft.isExisting) continue;

        final unitLabel =
            draft.unitLabel.trim().isEmpty ? null : draft.unitLabel.trim();
        final cfg = draft.buildConfig(tempToRealId);

        if (draft.isExisting && draft.originalBlock != null) {
          final updatedBlock = ProjectTrackingBlockEntity(
            id: draft.originalBlock!.id,
            projectId: projectId,
            blockType: draft.originalBlock!.blockType,
            title: draft.title.trim(),
            sortOrder: i,
            unitLabel: unitLabel,
            targetValue: draft.targetValue,
            dailyTargetValue: draft.dailyTargetValue,
            config: cfg,
            isArchived: draft.originalBlock!.isArchived,
            createdAt: draft.originalBlock!.createdAt,
            updatedAt: EthiopiaClock.nowUtc(),
          );
          await controller.updateBlock(updatedBlock);
        } else {
          final createdBlock = await controller.createBlock(
            projectId: projectId,
            blockType: draft.blockType,
            title: draft.title.trim(),
            sortOrder: i,
            unitLabel: unitLabel,
            targetValue: draft.targetValue,
            dailyTargetValue: draft.dailyTargetValue,
            config: cfg,
          );
          if (createdBlock != null) {
            tempToRealId[draft.tempId] = createdBlock.id;
          }
        }
      }

      // Second pass: create newly added rollup counters with resolved source IDs
      for (var i = 0; i < _blocks.length; i++) {
        final draft = _blocks[i];
        final isRollup =
            draft.blockType == ProjectBlockType.counter && draft.isRollup;
        if (!isRollup || draft.isExisting) continue;

        final unitLabel =
            draft.unitLabel.trim().isEmpty ? null : draft.unitLabel.trim();
        final cfg = draft.buildConfig(tempToRealId);
        final createdBlock = await controller.createBlock(
          projectId: projectId,
          blockType: draft.blockType,
          title: draft.title.trim(),
          sortOrder: i,
          unitLabel: unitLabel,
          targetValue: draft.targetValue,
          dailyTargetValue: draft.dailyTargetValue,
          config: cfg,
        );
        if (createdBlock != null) {
          tempToRealId[draft.tempId] = createdBlock.id;
        }
      }

      // Resolve primary block ID if a newly created block was selected
      if (_primaryDraftId != null) {
        final resolvedPrimary =
            tempToRealId[_primaryDraftId!] ?? _primaryDraftId!;
        if (resolvedPrimary != savedProject.customFields['primaryBlockId']) {
          final resolvedFields = Map<String, dynamic>.from(
            savedProject.customFields,
          )..['primaryBlockId'] = resolvedPrimary;
          savedProject = await controller.updateProject(
            savedProject.copyWith(
              customFields: resolvedFields,
              updatedAt: EthiopiaClock.nowUtc(),
            ),
          );
        }
      }

      syncTasksControllerProjects(widget.tasksController);

      if (!mounted) return;
      _didSave = true;
      Navigator.of(context).pop(savedProject);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _formError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final validPrimaryValue = (_primaryDraftId != null &&
            _blocks.any((b) => b.tempId == _primaryDraftId))
        ? _primaryDraftId
        : null;

    return PopScope<Object?>(
      canPop: !_hasUnsavedChanges && !_isSaving,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) {
          unawaited(_handlePopBlocked());
        }
      },
      child: Padding(
        padding: EdgeInsets.only(
          left: SharedDesignTokens.spacingMd,
          right: SharedDesignTokens.spacingMd,
          top: SharedDesignTokens.spacingMd,
          bottom: MediaQuery.of(context).viewInsets.bottom +
              SharedDesignTokens.spacingMd,
        ),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isEditing ? 'Edit Project' : 'New Project',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                DaywellIconButton(
                  icon: Icons.close,
                  tooltip: 'Close',
                  onPressed:
                      _isSaving ? null : () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
            if (_formError != null) ...[
              DaywellStatusBanner(
                message: _formError!,
                tone: DaywellStatusTone.error,
                onDismiss: () => setState(() => _formError = null),
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),
            ],
            DaywellTextField(
              controller: _titleCtrl,
              label: 'Project Title',
              hintText: 'e.g. Portfolio Refresh or Thesis Chapter 3',
              isRequired: true,
              errorText: _titleError,
              autofocus: !_isEditing,
              onChanged: (_) {
                if (_titleError != null) {
                  setState(() => _titleError = null);
                }
              },
            ),
            const SizedBox(height: SharedDesignTokens.spacingCompact),
            DaywellTextField(
              controller: _descCtrl,
              label: 'Description',
              hintText: 'Optional goal summary or scope notes',
              maxLines: 3,
            ),
            const SizedBox(height: SharedDesignTokens.spacingCompact),
            DaywellDropdownField<String>(
              value: _status,
              label: 'Status',
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'on_hold', child: Text('On Hold')),
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _status = v);
              },
            ),
            const SizedBox(height: SharedDesignTokens.spacingCompact),
            Row(
              children: [
                Expanded(
                  child: _DatePickerTile(
                    label: 'Start Date',
                    date: _startDate,
                    onPick: () async {
                      final picked = await pickProjectCalendarDate(
                        context,
                        initialDate: _startDate,
                        helpText: 'Select start date',
                      );
                      if (picked != null && mounted) {
                        setState(() => _startDate = picked);
                      }
                    },
                    onClear: _startDate != null
                        ? () => setState(() => _startDate = null)
                        : null,
                  ),
                ),
                const SizedBox(width: SharedDesignTokens.spacingSm),
                Expanded(
                  child: _DatePickerTile(
                    label: 'Target Date',
                    date: _targetDate,
                    onPick: () async {
                      final picked = await pickProjectCalendarDate(
                        context,
                        initialDate: _targetDate ?? _startDate,
                        helpText: 'Select target date',
                      );
                      if (picked != null && mounted) {
                        setState(() => _targetDate = picked);
                      }
                    },
                    onClear: _targetDate != null
                        ? () => setState(() => _targetDate = null)
                        : null,
                  ),
                ),
              ],
            ),
            if (widget.existingProject?.goalId != null &&
                widget.existingProject!.goalId!.isNotEmpty) ...[
              const SizedBox(height: SharedDesignTokens.spacingSm),
              Text(
                'Linked Goal ID: ${widget.existingProject!.goalId}',
                style: textTheme.bodySmall?.copyWith(color: semantic.textMuted),
              ),
            ],
            const SizedBox(height: SharedDesignTokens.spacingMd),
            DaywellSectionHeader(
              title: 'Tracking Blocks',
              count: _blocks.length,
              actionLabel: 'Add Block',
              onActionPressed: () => _openInlineBlockEditor(),
            ),
            const SizedBox(height: SharedDesignTokens.spacingSm),
            if (_blocks.isEmpty)
              DaywellCard(
                padding:
                    const EdgeInsets.all(SharedDesignTokens.spacingCompact),
                child: Row(
                  children: [
                    Icon(
                      Icons.widgets_outlined,
                      color: semantic.textMuted,
                      size: DaywellIconSize.md,
                    ),
                    const SizedBox(width: SharedDesignTokens.spacingSm),
                    Expanded(
                      child: Text(
                        'Optional: add counters, grouped lists, checklists, or schedules now or later inside Project Details.',
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
                  for (var i = 0; i < _blocks.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: SharedDesignTokens.spacingSm,
                      ),
                      child: DaywellCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SharedDesignTokens.spacingCompact,
                          vertical: SharedDesignTokens.spacingSm,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              blockTypeIcon(_blocks[i].blockType),
                              size: DaywellIconSize.md,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: SharedDesignTokens.spacingSm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _blocks[i].title,
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    [
                                      blockTypeLabel(_blocks[i].blockType),
                                      if (_blocks[i].isRollup) 'Rollup',
                                      if (_blocks[i].targetValue != null)
                                        'Target ${formatProjectNumber(_blocks[i].targetValue!)}',
                                      if (_blocks[i]
                                          .unitLabel
                                          .trim()
                                          .isNotEmpty)
                                        _blocks[i].unitLabel.trim(),
                                    ].join(' · '),
                                    style: textTheme.bodySmall?.copyWith(
                                      color: semantic.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DaywellIconButton(
                              icon: Icons.edit_outlined,
                              tooltip: 'Edit block',
                              onPressed: () => _openInlineBlockEditor(
                                editingDraft: _blocks[i],
                              ),
                            ),
                            if (!_blocks[i].isExisting)
                              DaywellIconButton(
                                icon: Icons.delete_outline,
                                tooltip: 'Remove staged block',
                                isDestructive: true,
                                onPressed: () {
                                  setState(() {
                                    final removedId = _blocks[i].tempId;
                                    _blocks.removeAt(i);
                                    if (_primaryDraftId == removedId) {
                                      _primaryDraftId = null;
                                    }
                                    for (final b in _blocks) {
                                      if (b.rollupSourceTempId == removedId) {
                                        b.rollupSourceTempId = null;
                                      }
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: SharedDesignTokens.spacingSm),
                  DaywellDropdownField<String?>(
                    value: validPrimaryValue,
                    label: 'Primary Progress Block (Optional)',
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None (track each block independently)'),
                      ),
                      for (final b in _blocks)
                        DropdownMenuItem<String?>(
                          value: b.tempId,
                          child: Text(
                              '${b.title} (${blockTypeLabel(b.blockType)})'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _primaryDraftId = v),
                  ),
                ],
              ),
            const SizedBox(height: SharedDesignTokens.spacingMd),
            Row(
              children: [
                Expanded(
                  child: DaywellButton(
                    label: 'Cancel',
                    variant: DaywellButtonVariant.outlined,
                    fullWidth: true,
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).maybePop(),
                  ),
                ),
                const SizedBox(width: SharedDesignTokens.spacingSm),
                Expanded(
                  child: DaywellButton(
                    label: _isEditing ? 'Save Changes' : 'Create Project',
                    variant: DaywellButtonVariant.primary,
                    isLoading: _isSaving,
                    fullWidth: true,
                    onPressed: _isSaving ? null : _handleSave,
                  ),
                ),
              ],
            ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  final String label;
  final CalendarDate? date;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const _DatePickerTile({
    required this.label,
    required this.date,
    required this.onPick,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(color: semantic.textSecondary),
        ),
        const SizedBox(height: SharedDesignTokens.spacingXs),
        DaywellCard(
          onTap: onPick,
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
                  date == null
                      ? 'Not set'
                      : SharedDateFormatter.formatDual(date!,
                          useAmharic: false),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: date == null
                        ? semantic.textMuted
                        : semantic.textPrimary,
                  ),
                ),
              ),
              if (onClear != null)
                InkWell(
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.clear,
                      size: DaywellIconSize.sm,
                      color: semantic.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InlineBlockEditorDialog extends StatefulWidget {
  final _InlineBlockDraft? existingDraft;
  final List<_InlineBlockDraft> siblingDrafts;
  final String nextTempId;

  const _InlineBlockEditorDialog({
    required this.existingDraft,
    required this.siblingDrafts,
    required this.nextTempId,
  });

  static Future<_InlineBlockDraft?> show(
    BuildContext context, {
    _InlineBlockDraft? existingDraft,
    required List<_InlineBlockDraft> siblingDrafts,
    required String nextTempId,
  }) {
    return showDialog<_InlineBlockDraft>(
      context: context,
      builder: (_) => _InlineBlockEditorDialog(
        existingDraft: existingDraft,
        siblingDrafts: siblingDrafts,
        nextTempId: nextTempId,
      ),
    );
  }

  @override
  State<_InlineBlockEditorDialog> createState() =>
      _InlineBlockEditorDialogState();
}

class _InlineBlockEditorDialogState extends State<_InlineBlockEditorDialog> {
  late ProjectBlockType _blockType;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _targetCtrl;
  late final TextEditingController _dailyTargetCtrl;
  late final TextEditingController _thresholdCtrl;
  bool _isRollup = false;
  String? _rollupSourceTempId;
  bool _showGroupTotals = true;
  bool _showDailyTotals = true;
  ScheduleItemCompletionRule _completionRule =
      ScheduleItemCompletionRule.manual;
  bool _trackActualDuration = true;
  String? _error;

  bool get _isLockedExistingType => widget.existingDraft?.isExisting == true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingDraft;
    _blockType = existing?.blockType ?? ProjectBlockType.counter;
    _titleCtrl = TextEditingController(text: existing?.title ?? '');
    _unitCtrl = TextEditingController(text: existing?.unitLabel ?? '');
    _targetCtrl = TextEditingController(
      text: existing?.targetValue != null
          ? formatProjectNumber(existing!.targetValue!)
          : '',
    );
    _dailyTargetCtrl = TextEditingController(
      text: existing?.dailyTargetValue != null
          ? formatProjectNumber(existing!.dailyTargetValue!)
          : '',
    );
    _thresholdCtrl = TextEditingController(
      text: existing != null
          ? formatProjectNumber(existing.thresholdPercent)
          : '80',
    );
    _isRollup = existing?.isRollup ?? false;
    _rollupSourceTempId = existing?.rollupSourceTempId;
    _showGroupTotals = existing?.showGroupTotals ?? true;
    _showDailyTotals = existing?.showDailyTotals ?? true;
    _completionRule =
        existing?.completionRule ?? ScheduleItemCompletionRule.manual;
    _trackActualDuration = existing?.trackActualDuration ?? true;
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

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Block title is required.');
      return;
    }

    final targetRaw = _targetCtrl.text.trim();
    final double? targetValue =
        targetRaw.isEmpty ? null : double.tryParse(targetRaw);
    if (targetRaw.isNotEmpty && (targetValue == null || targetValue <= 0)) {
      setState(() => _error = 'Target value must be a positive number.');
      return;
    }

    final dailyRaw = _dailyTargetCtrl.text.trim();
    final double? dailyTargetValue =
        dailyRaw.isEmpty ? null : double.tryParse(dailyRaw);
    if (dailyRaw.isNotEmpty &&
        (dailyTargetValue == null || dailyTargetValue <= 0)) {
      setState(() => _error = 'Daily target must be a positive number.');
      return;
    }

    final eligibleSources = widget.siblingDrafts
        .where(
          (s) => !(s.blockType == ProjectBlockType.counter && s.isRollup),
        )
        .toList();

    if (_blockType == ProjectBlockType.counter &&
        _isRollup &&
        (_rollupSourceTempId == null ||
            !eligibleSources.any((s) => s.tempId == _rollupSourceTempId))) {
      setState(
          () => _error = 'Select a source tracking block for this rollup.');
      return;
    }

    double thresholdPercent = 80;
    if (_blockType == ProjectBlockType.schedule &&
        _completionRule == ScheduleItemCompletionRule.thresholdPercent) {
      final parsed = double.tryParse(_thresholdCtrl.text.trim());
      if (parsed == null || parsed <= 0 || parsed > 100) {
        setState(() => _error = 'Threshold % must be between 1 and 100.');
        return;
      }
      thresholdPercent = parsed;
    }

    Navigator.of(context).pop(
      _InlineBlockDraft(
        tempId: widget.existingDraft?.tempId ?? widget.nextTempId,
        isExisting: widget.existingDraft?.isExisting ?? false,
        originalBlock: widget.existingDraft?.originalBlock,
        blockType: _blockType,
        title: title,
        unitLabel: _unitCtrl.text.trim(),
        targetValue: targetValue,
        dailyTargetValue: dailyTargetValue,
        isRollup: _blockType == ProjectBlockType.counter && _isRollup,
        rollupSourceTempId: _blockType == ProjectBlockType.counter && _isRollup
            ? _rollupSourceTempId
            : null,
        showGroupTotals: _showGroupTotals,
        showDailyTotals: _showDailyTotals,
        completionRule: _completionRule,
        thresholdPercent: thresholdPercent,
        trackActualDuration: _trackActualDuration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eligibleSources = widget.siblingDrafts
        .where(
          (s) => !(s.blockType == ProjectBlockType.counter && s.isRollup),
        )
        .toList();

    return AlertDialog(
      scrollable: true,
      title: Text(
        widget.existingDraft == null
            ? 'Add Tracking Block'
            : 'Edit Tracking Block',
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
          DaywellDropdownField<ProjectBlockType>(
            value: _blockType,
            label: 'Block Type',
            enabled: !_isLockedExistingType,
            helperText: _isLockedExistingType
                ? 'Block type cannot be changed after creation.'
                : null,
            items: ProjectBlockType.values
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(blockTypeLabel(t)),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  _blockType = v;
                  _error = null;
                });
              }
            },
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          DaywellTextField(
            controller: _titleCtrl,
            label: 'Block Title',
            hintText: 'e.g. Pages Written, Chapters, Study Hours',
            isRequired: true,
          ),
          const SizedBox(height: SharedDesignTokens.spacingCompact),
          Row(
            children: [
              Expanded(
                child: DaywellTextField(
                  controller: _unitCtrl,
                  label: 'Unit (Optional)',
                  hintText: 'e.g. pages, min, items',
                ),
              ),
              const SizedBox(width: SharedDesignTokens.spacingSm),
              Expanded(
                child: DaywellTextField(
                  controller: _targetCtrl,
                  label: 'Target (Optional)',
                  hintText: 'e.g. 100',
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
              hintText: 'e.g. 5',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
          if (_blockType == ProjectBlockType.counter) ...[
            const SizedBox(height: SharedDesignTokens.spacingSm),
            DaywellSwitchTile(
              title: 'Rollup from another block',
              subtitle: 'Derive totals automatically from a sibling block',
              value: _isRollup,
              enabled: eligibleSources.isNotEmpty || _isRollup,
              onChanged: (val) {
                setState(() {
                  _isRollup = val;
                  if (val &&
                      _rollupSourceTempId == null &&
                      eligibleSources.isNotEmpty) {
                    _rollupSourceTempId = eligibleSources.first.tempId;
                  }
                });
              },
            ),
            if (_isRollup) ...[
              const SizedBox(height: SharedDesignTokens.spacingSm),
              DaywellDropdownField<String?>(
                value: eligibleSources.any(
                  (s) => s.tempId == _rollupSourceTempId,
                )
                    ? _rollupSourceTempId
                    : null,
                label: 'Source Block',
                items: eligibleSources
                    .map(
                      (s) => DropdownMenuItem<String?>(
                        value: s.tempId,
                        child: Text(s.title),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _rollupSourceTempId = v),
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
                hintText: '80',
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
          onPressed: () => Navigator.of(context).pop(),
        ),
        DaywellButton(
          label: widget.existingDraft == null ? 'Add Block' : 'Save Block',
          variant: DaywellButtonVariant.primary,
          size: DaywellButtonSize.compact,
          onPressed: _submit,
        ),
      ],
    );
  }
}
