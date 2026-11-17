import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/projects/projects_controller.dart';
import '../../../application/tasks/tasks_controller.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/projects/project_models.dart';
import '../../../domain/projects/project_package_codec.dart';
import '../../../domain/tasks/task_models.dart';
import '../../../services/export/project_package_io_service.dart';
import '../../widgets/shared_ui_widgets.dart';
import 'project_detail_screen.dart';
import 'project_form_sheet.dart';
import 'project_import_dialog.dart';
import 'project_ui_helpers.dart';

class ProjectsWorkspaceTab extends StatefulWidget {
  final ProjectsController? projectsController;
  final TasksController? tasksController;

  const ProjectsWorkspaceTab({
    super.key,
    required this.projectsController,
    this.tasksController,
  });

  @override
  State<ProjectsWorkspaceTab> createState() => _ProjectsWorkspaceTabState();
}

class _ProjectsWorkspaceTabState extends State<ProjectsWorkspaceTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = 'all';
  String _query = '';

  @override
  void initState() {
    super.initState();
    final ctrl = widget.projectsController;
    if (ctrl != null && !ctrl.state.isLoading && ctrl.state.projects.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.projectsController == ctrl) {
          unawaited(ctrl.loadAll());
        }
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ProjectEntity> _applyFilters(List<ProjectEntity> projects) {
    final normalizedQuery = _query.trim().toLowerCase();
    return projects.where((p) {
      switch (_filter) {
        case 'archived':
          if (!p.isArchived) return false;
        case 'active':
          if (p.isArchived || p.status != 'active') return false;
        case 'on_hold':
          if (p.isArchived || p.status != 'on_hold') return false;
        case 'completed':
          if (p.isArchived || p.status != 'completed') return false;
        case 'all':
        default:
          if (p.isArchived) return false;
      }

      if (normalizedQuery.isEmpty) return true;
      final inTitle = p.title.toLowerCase().contains(normalizedQuery);
      final inDesc =
          (p.description ?? '').toLowerCase().contains(normalizedQuery);
      return inTitle || inDesc;
    }).toList(growable: false);
  }

  Future<void> _archiveOrRestore(
    ProjectsController ctrl,
    ProjectEntity project,
  ) async {
    final nextArchived = !project.isArchived;
    if (nextArchived) {
      final confirmed = await DaywellConfirmationDialog.show(
        context,
        title: 'Archive Project?',
        message:
            'Archive "${project.title}"? Blocks and progress history stay preserved and can be restored anytime from Archived.',
        confirmLabel: 'Archive',
        icon: Icons.archive_outlined,
      );
      if (!confirmed || !mounted) return;
    }
    await ctrl.setProjectArchived(project.id, nextArchived);
    syncTasksControllerProjects(widget.tasksController);
  }

  Future<void> _deleteArchivedProject(
    ProjectsController ctrl,
    ProjectEntity project,
  ) async {
    if (!project.isArchived) return;
    final confirmed = await DaywellConfirmationDialog.show(
      context,
      title: 'Delete Archived Project?',
      message:
          'Permanently delete "${project.title}" and all of its tracking blocks and progress logs? Linked tasks will remain safely in Tasks.',
      confirmLabel: 'Delete Forever',
      isDestructive: true,
      icon: Icons.delete_forever_outlined,
    );
    if (!confirmed || !mounted) return;
    await ctrl.deleteProject(project.id);
    syncTasksControllerProjects(widget.tasksController);
  }

  void _openDetail(ProjectsController ctrl, ProjectEntity project) {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ProjectDetailScreen(
            projectId: project.id,
            projectsController: ctrl,
            tasksController: widget.tasksController,
          ),
        ),
      ),
    );
  }

  Future<void> _exportProject(
    ProjectsController ctrl,
    ProjectEntity project,
  ) async {
    final json = await ctrl.exportProjectPackageJson(project.id);
    if (!mounted) return;
    if (json == null) {
      final err = ctrl.state.errorMessage ?? 'Unable to export project.';
      ctrl.clearError();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $err')),
      );
      return;
    }
    final filename = ProjectPackageCodec.buildFilename(project.title);
    try {
      await ProjectPackageIoService.exportPackageFile(
        filename: filename,
        jsonContent: json,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Prepared "$filename" for export.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to share "$filename": $e')),
      );
    }
  }

  Future<void> _importProject(ProjectsController ctrl) async {
    final imported = await ProjectImportDialog.show(
      context,
      projectsController: ctrl,
    );
    if (imported == null || !mounted) return;
    setState(() {
      if (imported.project.isArchived) {
        _filter = 'archived';
      } else if (_filter != 'all' && _filter != imported.project.status) {
        _filter = imported.project.status;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Imported "${imported.project.title}" (${imported.trackingBlocks.length} blocks, ${imported.trackingRecords.length} records).',
        ),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () => _openDetail(ctrl, imported.project),
        ),
      ),
    );
  }

  String _compactMetricSummary(ProjectProgressSummary? summary) {
    if (summary == null || summary.blockMetrics.isEmpty) {
      return 'No tracking blocks configured';
    }
    final activeMetrics =
        summary.blockMetrics.where((m) => !m.isArchived).toList();
    if (activeMetrics.isEmpty) {
      return 'Only archived blocks';
    }
    final first = activeMetrics.first;
    final unit = first.unitLabel?.trim().isNotEmpty == true
        ? ' ${first.unitLabel!.trim()}'
        : '';
    final capped = first.targetCompletedTotal ?? first.loggedTotal;
    final over = first.overTargetAmount ?? 0.0;
    final String firstPart;
    if (first.blockType == ProjectBlockType.checklist ||
        first.blockType == ProjectBlockType.schedule) {
      firstPart = '${first.title}: ${first.completedCount}/${first.totalCount}';
    } else if (first.targetValue != null) {
      final overNote = over > 0
          ? ' (${formatProjectNumber(first.loggedTotal)} sent, +${formatProjectNumber(over)} over)'
          : '';
      firstPart =
          '${first.title}: ${formatProjectNumber(capped)}/${formatProjectNumber(first.targetValue!)}$unit$overNote';
    } else {
      firstPart =
          '${first.title}: ${formatProjectNumber(first.loggedTotal)}$unit';
    }
    if (activeMetrics.length == 1) return firstPart;
    return '$firstPart · +${activeMetrics.length - 1} more';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.projectsController;
    if (ctrl == null) {
      return const DaywellEmptyState(
        icon: Icons.folder_outlined,
        message: 'Projects workspace unavailable',
        subtitle: 'Attach a ProjectsController to manage projects here.',
      );
    }

    final listenable = widget.tasksController != null
        ? Listenable.merge([ctrl, widget.tasksController!])
        : ctrl;

    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final state = ctrl.state;
        final semantic = context.daywellColors;
        final textTheme = Theme.of(context).textTheme;
        final filtered = _applyFilters(state.projects);

        final DaywellContentStatus contentStatus;
        if (state.isLoading && state.projects.isEmpty) {
          contentStatus = DaywellContentStatus.loading;
        } else if (state.errorMessage != null && state.projects.isEmpty) {
          contentStatus = DaywellContentStatus.error;
        } else if (filtered.isEmpty) {
          contentStatus = DaywellContentStatus.empty;
        } else {
          contentStatus = DaywellContentStatus.content;
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SharedDesignTokens.spacingMd,
                SharedDesignTokens.spacingCompact,
                SharedDesignTokens.spacingMd,
                SharedDesignTokens.spacingSm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: DaywellSearchField(
                      controller: _searchCtrl,
                      hintText: 'Search projects...',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: SharedDesignTokens.spacingSm),
                  DaywellButton(
                    label: 'Import',
                    variant: DaywellButtonVariant.outlined,
                    size: DaywellButtonSize.compact,
                    leadingIcon: Icons.file_upload_outlined,
                    tooltip: 'Import .daywellproject file',
                    onPressed: () => _importProject(ctrl),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: SharedDesignTokens.spacingCompact,
                ),
                children: [
                  for (final f in const [
                    ('all', 'All'),
                    ('active', 'Active'),
                    ('on_hold', 'On Hold'),
                    ('completed', 'Completed'),
                    ('archived', 'Archived'),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SharedDesignTokens.spacingXs,
                      ),
                      child: ChoiceChip(
                        label: Text(f.$2),
                        selected: _filter == f.$1,
                        onSelected: (_) => setState(() => _filter = f.$1),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: DaywellContentState(
                status: contentStatus,
                loadingLabel: 'Loading projects...',
                errorTitle: 'Could not load projects',
                errorMessage: state.errorMessage ?? 'Something went wrong.',
                onRetry: () => unawaited(ctrl.loadAll()),
                emptyIcon: _filter == 'archived'
                    ? Icons.archive_outlined
                    : Icons.folder_outlined,
                emptyMessage: _query.trim().isNotEmpty
                    ? 'No projects match "${_query.trim()}"'
                    : _filter == 'archived'
                        ? 'No archived projects'
                        : 'No projects in this view yet',
                emptySubtitle: _filter == 'archived'
                    ? 'Archived projects can be restored or deleted permanently here.'
                    : 'Create a project to organize custom tracking blocks and progress.',
                emptyActionLabel: _filter == 'archived' ? null : 'New Project',
                onEmptyAction: _filter == 'archived'
                    ? null
                    : () => ProjectFormSheet.show(
                          context,
                          projectsController: ctrl,
                          tasksController: widget.tasksController,
                        ),
                contentBuilder: (ctx) => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    SharedDesignTokens.spacingMd,
                    SharedDesignTokens.spacingCompact,
                    SharedDesignTokens.spacingMd,
                    88,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(
                    height: SharedDesignTokens.spacingCompact,
                  ),
                  itemBuilder: (_, index) {
                    final project = filtered[index];
                    final summary = state.summaryForProject(project.id);
                    final blocks = state.blocksForProject(
                      project.id,
                      includeArchived: false,
                    );
                    final linkedActiveTasks =
                        (widget.tasksController?.state.tasks ??
                                const <TaskEntity>[])
                            .where(
                              (t) =>
                                  t.projectId == project.id &&
                                  !t.isCompleted &&
                                  t.status != 'cancelled',
                            )
                            .length;
                    final primaryPct = summary?.overallPercentage;

                    return DaywellCard(
                      padding: const EdgeInsets.all(
                        SharedDesignTokens.spacingMd,
                      ),
                      onTap: () => _openDetail(ctrl, project),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  project.title,
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(
                                width: SharedDesignTokens.spacingSm,
                              ),
                              DaywellStatusBadge(
                                label: projectStatusLabel(project),
                                tone: projectStatusTone(project),
                              ),
                            ],
                          ),
                          if (project.description != null &&
                              project.description!.trim().isNotEmpty) ...[
                            const SizedBox(
                                height: SharedDesignTokens.spacingXs),
                            Text(
                              project.description!.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: semantic.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(
                            height: SharedDesignTokens.spacingCompact,
                          ),
                          if (summary?.primaryMetric != null &&
                              primaryPct != null)
                            DaywellProgressBar(
                              value: primaryPct / 100.0,
                              label: summary!.primaryMetric!.title,
                              valueText: '${primaryPct.round()}%',
                            )
                          else
                            Text(
                              _compactMetricSummary(summary),
                              style: textTheme.bodySmall?.copyWith(
                                color: semantic.textSecondary,
                              ),
                            ),
                          const SizedBox(
                            height: SharedDesignTokens.spacingCompact,
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  [
                                    '${blocks.length} ${blocks.length == 1 ? "block" : "blocks"}',
                                    '$linkedActiveTasks active ${linkedActiveTasks == 1 ? "task" : "tasks"}',
                                    if (project.targetDate != null)
                                      'Due ${SharedDateFormatter.formatDual(project.targetDate!, useAmharic: false)}',
                                  ].join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: semantic.textMuted,
                                  ),
                                ),
                              ),
                              DaywellIconButton(
                                icon: Icons.file_download_outlined,
                                tooltip: 'Export .daywellproject',
                                onPressed: () => _exportProject(ctrl, project),
                              ),
                              DaywellButton(
                                label:
                                    project.isArchived ? 'Restore' : 'Archive',
                                variant: DaywellButtonVariant.text,
                                size: DaywellButtonSize.compact,
                                onPressed: () =>
                                    _archiveOrRestore(ctrl, project),
                              ),
                              if (project.isArchived)
                                DaywellIconButton(
                                  icon: Icons.delete_forever_outlined,
                                  tooltip: 'Delete permanently',
                                  isDestructive: true,
                                  onPressed: () =>
                                      _deleteArchivedProject(ctrl, project),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
