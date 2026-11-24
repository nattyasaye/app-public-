import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/notes/notes_controller.dart';
import '../../../core/date/shared_date.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/notes/note_helpers.dart';
import '../../../domain/notes/note_models.dart';
import '../../../domain/notes/project_notes_helpers.dart';
import '../../../domain/projects/project_models.dart';
import '../../widgets/shared_ui_widgets.dart';

class ProjectNotesWidget extends StatelessWidget {
  final ProjectEntity project;
  final NotesController? notesController;
  final void Function(String noteId)? onOpenNote;

  const ProjectNotesWidget({
    super.key,
    required this.project,
    this.notesController,
    this.onOpenNote,
  });

  Future<void> _createProjectNote(BuildContext context) async {
    final ctrl = notesController;
    if (ctrl == null) return;
    final created = await ctrl.createNote(
      title: ProjectNotesHelper.buildDefaultProjectNoteTitle(project),
      content: '',
      projectId: project.id,
    );
    if (!context.mounted) return;
    final err = ctrl.state.errorMessage;
    if (ctrl.state.findById(created.id) == null && err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
      return;
    }
    if (onOpenNote != null) {
      onOpenNote!(created.id);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Created note "${created.displayTitle}"'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = notesController;
    if (ctrl == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final semantic = context.daywellColors;
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final projectNotes = ProjectNotesHelper.getNotesForProject(
          ctrl.state.notes,
          project.id,
          includeArchived: true,
          includeTrashed: false,
        );

        return DaywellCard(
          borderRadius: SharedDesignTokens.radiusXl,
          padding: const EdgeInsets.all(SharedDesignTokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.note_alt_outlined,
                    size: DaywellIconSize.sm,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: SharedDesignTokens.spacingSm),
                  Expanded(
                    child: Text(
                      'NOTES (${projectNotes.length})',
                      style: DaywellTypography.caption(
                        color: semantic.textMuted,
                      ).copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  DaywellButton(
                    label: 'New Note',
                    variant: DaywellButtonVariant.tonal,
                    size: DaywellButtonSize.compact,
                    leadingIcon: Icons.add,
                    onPressed: () => unawaited(_createProjectNote(context)),
                  ),
                ],
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              if (projectNotes.isEmpty)
                DaywellEmptyState(
                  icon: Icons.note_alt_outlined,
                  message: 'No notes for this project yet',
                  subtitle:
                      'Create a note directly for this project to capture specs, meeting outlines, or ideas.',
                  actionLabel: 'New Note',
                  onActionPressed: () => unawaited(_createProjectNote(context)),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < projectNotes.length; i++) ...[
                      if (i > 0)
                        const SizedBox(height: SharedDesignTokens.spacingSm),
                      _ProjectNoteRow(
                        note: projectNotes[i],
                        onTap: onOpenNote != null
                            ? () => onOpenNote!(projectNotes[i].id)
                            : null,
                        semantic: semantic,
                        colorScheme: colorScheme,
                        textTheme: textTheme,
                      ),
                    ],
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ProjectNoteRow extends StatelessWidget {
  final NoteEntity note;
  final VoidCallback? onTap;
  final DaywellSemanticColors semantic;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const _ProjectNoteRow({
    required this.note,
    required this.onTap,
    required this.semantic,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final preview = ProjectNotesHelper.buildContentPreview(note.content);
    final ethDate =
        CalendarDate.fromUtcInstantInEthiopia(note.updatedAt).toEthiopian();
    final updatedLabel = SharedDateFormatter.formatEthiopian(
      ethDate,
      useAmharic: false,
      includeEra: false,
    );
    final isPinnedActive = note.isPinned && !note.isArchived && !note.isTrashed;
    final folderLabel = NoteDomainHelpers.formatFolderLabel(note.category);

    return DaywellCard(
      color: semantic.surfaceSubtle,
      borderColor: semantic.border,
      borderRadius: SharedDesignTokens.radiusMd,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: SharedDesignTokens.spacingXs,
                    runSpacing: SharedDesignTokens.spacingXs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (isPinnedActive)
                        Icon(
                          Icons.push_pin_rounded,
                          size: DaywellIconSize.xs,
                          color: semantic.warning,
                        ),
                      Text(
                        note.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: semantic.textPrimary,
                        ),
                      ),
                      DaywellStatusBadge(
                        label: folderLabel,
                        tone: DaywellStatusTone.info,
                        showIcon: false,
                      ),
                      if (note.isArchived)
                        const DaywellStatusBadge(
                          label: 'Archived',
                          tone: DaywellStatusTone.warning,
                          showIcon: false,
                        ),
                    ],
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DaywellTypography.fromToken(
                        SharedDesignTokens.typeBodyCompact,
                        color: semantic.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                  Text(
                    'Updated $updatedLabel',
                    style: DaywellTypography.caption(color: semantic.textMuted),
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: SharedDesignTokens.spacingXs),
              Icon(
                Icons.arrow_outward_rounded,
                size: DaywellIconSize.sm,
                color: colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
