import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/date/shared_date.dart';
import '../../core/shared_foundation.dart';
import '../../core/theme/daywell_theme.dart';
import '../../domain/notes/note_editor_formatting.dart';
import '../../domain/notes/note_helpers.dart';
import '../../domain/notes/note_links.dart';
import '../../domain/notes/note_markdown.dart';
import '../../domain/notes/note_models.dart';
import '../../domain/notes/task_notes_helpers.dart';
import '../../domain/tasks/task_models.dart';
import '../../application/notes/notes_controller.dart';
import '../../application/tasks/tasks_controller.dart';
import '../app_state.dart';
import '../widgets/notes/note_markdown_preview.dart';
import '../widgets/shared_ui_widgets.dart';

typedef _NoteDraftSnapshot = ({
  int revision,
  String title,
  String content,
  String category,
  List<String> tags,
  String? linkedModule,
  String? linkedId,
});

String _formatFolderLabel(String category) {
  if (category == 'all') return 'All Folders';
  final parts = category
      .trim()
      .split(RegExp(r'[\s_-]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'General';
  return parts
      .map((p) => '${p[0].toUpperCase()}${p.length > 1 ? p.substring(1) : ''}')
      .join(' ');
}

class NotesView extends StatefulWidget {
  final AppStateManager? state;
  final NotesController? controller;
  final TasksController? tasksController;
  final ({String noteId, int nonce})? requestedNoteFocus;
  final void Function(String taskId)? onOpenTask;

  const NotesView({
    super.key,
    this.state,
    this.controller,
    this.tasksController,
    this.requestedNoteFocus,
    this.onOpenTask,
  }) : assert(state != null || controller != null,
            'Either state or controller must be provided to NotesView');

  NotesController get effectiveController =>
      controller ?? state!.notesController;

  TasksController? get effectiveTasksController =>
      tasksController ?? state?.tasksController;

  @override
  State<NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<NotesView> {
  late TextEditingController _searchController;
  int? _lastHandledNoteFocusNonce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.effectiveController.state.searchQuery,
    );
    _scheduleNoteFocusIfNeeded();
  }

  @override
  void didUpdateWidget(covariant NotesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleNoteFocusIfNeeded();
  }

  void _scheduleNoteFocusIfNeeded() {
    final focus = widget.requestedNoteFocus;
    if (focus == null || focus.nonce == _lastHandledNoteFocusNonce) return;
    _lastHandledNoteFocusNonce = focus.nonce;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final note = widget.effectiveController.state.findById(focus.noteId);
      if (note == null || note.isTrashed) return;
      _openNoteEditor(note);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openNoteEditor([NoteEntity? existingNote]) {
    if (existingNote != null && existingNote.isTrashed) {
      return;
    }
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _NoteEditorScreen(
            controller: widget.effectiveController,
            tasksController: widget.effectiveTasksController,
            onOpenTask: widget.onOpenTask,
            existingNote: existingNote,
          ),
        ),
      ),
    );
  }

  void _promptRestoreTrashedNote(NoteEntity note) {
    final controller = widget.effectiveController;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Restore note from Trash before editing'),
        action: SnackBarAction(
          label: 'Restore',
          onPressed: () => unawaited(controller.restoreFromTrash(note.id)),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _confirmPermanentDelete(NoteEntity note) {
    unawaited(
      DaywellConfirmationDialog.show(
        context,
        title: 'Delete Permanently?',
        message:
            'Delete "${note.displayTitle}" permanently? This cannot be undone.',
        cancelLabel: 'Cancel',
        confirmLabel: 'Delete',
        isDestructive: true,
        icon: Icons.delete_forever_outlined,
      ).then((confirmed) {
        if (!confirmed || !mounted) return;
        unawaited(widget.effectiveController.permanentlyDeleteNote(note.id));
      }),
    );
  }

  void _confirmEmptyTrash(NotesController controller, int count) {
    unawaited(
      DaywellConfirmationDialog.show(
        context,
        title: 'Empty Trash?',
        message:
            'Permanently delete $count trashed ${count == 1 ? 'note' : 'notes'}? This cannot be undone.',
        cancelLabel: 'Cancel',
        confirmLabel: 'Empty Trash',
        isDestructive: true,
        icon: Icons.delete_sweep_outlined,
      ).then((confirmed) {
        if (!confirmed || !mounted) return;
        unawaited(controller.emptyTrash());
      }),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    NotesController controller,
    dynamic moduleState,
  ) {
    final String query = moduleState.searchQuery as String;
    final String section = moduleState.sectionFilter as String;
    final String category = moduleState.categoryFilter as String;

    if (query.isNotEmpty) {
      return DaywellEmptyState(
        icon: Icons.search_off_rounded,
        message: 'No notes match "$query"',
        subtitle: 'Try another keyword or clear your active filters.',
        actionLabel: 'Clear filters',
        onActionPressed: () {
          _searchController.clear();
          controller.clearFilters();
        },
      );
    }

    if (section == 'trash') {
      return const DaywellEmptyState(
        icon: Icons.delete_outline,
        message: 'Trash is empty',
        subtitle: 'Deleted notes appear here until permanently removed.',
      );
    }

    if (section == 'archive') {
      return const DaywellEmptyState(
        icon: Icons.archive_outlined,
        message: 'No archived notes yet',
        subtitle:
            'Archive notes you want to keep for reference without cluttering your active list.',
      );
    }

    if (section == 'pinned') {
      return DaywellEmptyState(
        icon: Icons.push_pin_outlined,
        message: 'No pinned notes yet',
        subtitle: 'Pin important notes to keep them at the top of your list.',
        actionLabel: 'Create First Note',
        onActionPressed: () => _openNoteEditor(),
      );
    }

    if (section == 'favorites') {
      return DaywellEmptyState(
        icon: Icons.star_outline_rounded,
        message: 'No favorite notes yet',
        subtitle: 'Star notes you revisit often for quick access.',
        actionLabel: 'Create First Note',
        onActionPressed: () => _openNoteEditor(),
      );
    }

    if (category != 'all') {
      return DaywellEmptyState(
        icon: Icons.folder_open_outlined,
        message: 'No notes in ${_formatFolderLabel(category)}',
        subtitle: 'Create a note in this folder or switch folders above.',
        actionLabel: 'Create First Note',
        onActionPressed: () => _openNoteEditor(),
      );
    }

    return DaywellEmptyState(
      icon: Icons.note_alt_outlined,
      message: 'No notes in this view yet',
      subtitle: 'Capture reflections, checklists, and linked references.',
      actionLabel: 'Create First Note',
      onActionPressed: () => _openNoteEditor(),
    );
  }

  String _sectionDisplayLabel(String section) {
    switch (section) {
      case 'pinned':
        return 'Pinned';
      case 'favorites':
        return 'Favorites';
      case 'archive':
        return 'Archive';
      case 'trash':
        return 'Trash';
      case 'active':
      default:
        return 'All Notes';
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.effectiveController;
    final tasksController = widget.effectiveTasksController;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final semantic = context.daywellColors;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final double? adaptiveToolbarHeight = textScale > 1.3
        ? (kToolbarHeight * textScale.clamp(1.0, 2.1)).ceilToDouble()
        : null;

    return AnimatedBuilder(
      animation: Listenable.merge([
        controller,
        if (tasksController != null) tasksController,
      ]),
      builder: (context, _) {
        final moduleState = controller.state;
        final notes = moduleState.filteredNotes;
        const defaultOrder = ['reflection', 'reference', 'learning', 'general'];
        final knownCategories = moduleState.sectionFilter == 'trash'
            ? moduleState.availableAllCategories
            : moduleState.availableCategories;
        final extraCategories = knownCategories
            .where((c) => !defaultOrder.contains(c))
            .toList()
          ..sort();
        if (moduleState.categoryFilter != 'all' &&
            !defaultOrder.contains(moduleState.categoryFilter) &&
            !extraCategories.contains(moduleState.categoryFilter)) {
          extraCategories.add(moduleState.categoryFilter);
          extraCategories.sort();
        }
        final categoryChips = <String>[
          'all',
          ...defaultOrder,
          ...extraCategories,
        ];
        final hasError = moduleState.errorMessage != null &&
            moduleState.errorMessage!.trim().isNotEmpty;
        final hasActiveFilters = moduleState.searchQuery.isNotEmpty ||
            moduleState.categoryFilter != 'all' ||
            moduleState.sectionFilter != 'active';
        final String? activeSummary = hasActiveFilters
            ? '${notes.length} ${notes.length == 1 ? 'note' : 'notes'} · ${_sectionDisplayLabel(moduleState.sectionFilter)}${moduleState.categoryFilter != 'all' ? ' · ${_formatFolderLabel(moduleState.categoryFilter)}' : ''}'
            : null;

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: adaptiveToolbarHeight,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DAYWELL / NOTES',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DaywellTypography.caption(
                    color: semantic.textMuted,
                  ).copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.2),
                ),
                Text(
                  'Notes & Knowledge',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            actions: [
              if (moduleState.sectionFilter == 'trash' &&
                  moduleState.trashedNotesCount > 0)
                TextButton(
                  onPressed: () => _confirmEmptyTrash(
                    controller,
                    moduleState.trashedNotesCount,
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Text('Empty Trash'),
                ),
              DaywellIconButton(
                icon: moduleState.isGridView
                    ? Icons.view_list_rounded
                    : Icons.grid_view_rounded,
                tooltip: moduleState.isGridView ? 'List View' : 'Grid View',
                onPressed: controller.toggleGridView,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.sort_rounded),
                tooltip: 'Sort notes',
                onSelected: controller.setSortBy,
                itemBuilder: (_) => [
                  for (final option in const [
                    ('recent', 'Recently Modified'),
                    ('alpha', 'Alphabetical (A–Z)'),
                    ('oldest', 'Oldest First'),
                  ])
                    PopupMenuItem<String>(
                      value: option.$1,
                      child: Row(
                        children: [
                          Icon(
                            moduleState.sortBy == option.$1
                                ? Icons.check_rounded
                                : Icons.sort_rounded,
                            size: DaywellIconSize.sm,
                            color: moduleState.sortBy == option.$1
                                ? colorScheme.primary
                                : semantic.textMuted,
                          ),
                          const SizedBox(width: SharedDesignTokens.spacingSm),
                          Text(
                            option.$2,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: moduleState.sortBy == option.$1
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: moduleState.sortBy == option.$1
                                  ? colorScheme.primary
                                  : semantic.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openNoteEditor(),
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            icon: const Icon(Icons.add),
            label: const Text('New Note'),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: SharedDesignTokens.breakpointMaxWideWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DaywellSearchFilterBar(
                    searchController: _searchController,
                    searchHintText: 'Search notes, tags, or folders...',
                    searchSemanticLabel: 'Search notes, tags, or folders',
                    onSearchChanged: controller.setSearchQuery,
                    onSearchCleared: () {
                      _searchController.clear();
                      controller.setSearchQuery('');
                    },
                    hasActiveFilters: hasActiveFilters,
                    activeSummary: activeSummary,
                    onClearFilters: () {
                      _searchController.clear();
                      controller.clearFilters();
                    },
                    showBottomDivider: false,
                    padding: const EdgeInsets.fromLTRB(
                      SharedDesignTokens.spacingMd,
                      SharedDesignTokens.spacingSm,
                      SharedDesignTokens.spacingMd,
                      SharedDesignTokens.spacingXs,
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: SharedDesignTokens.spacingMd,
                      vertical: SharedDesignTokens.spacingXs,
                    ),
                    child: Row(
                      children: [
                        for (final sec in const [
                          ('active', 'All Notes'),
                          ('pinned', 'Pinned'),
                          ('favorites', 'Favorites'),
                          ('archive', 'Archive'),
                          ('trash', 'Trash'),
                        ]) ...[
                          ChoiceChip(
                            label: Text(
                              sec.$2,
                              style: DaywellTypography.label(
                                color: moduleState.sectionFilter == sec.$1
                                    ? colorScheme.onPrimaryContainer
                                    : semantic.textSecondary,
                              ),
                            ),
                            selected: moduleState.sectionFilter == sec.$1,
                            onSelected: (_) =>
                                controller.setSectionFilter(sec.$1),
                          ),
                          const SizedBox(width: SharedDesignTokens.spacingSm),
                        ],
                      ],
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(
                      SharedDesignTokens.spacingMd,
                      0,
                      SharedDesignTokens.spacingMd,
                      SharedDesignTokens.spacingSm,
                    ),
                    child: Row(
                      children: [
                        for (final cat in categoryChips) ...[
                          FilterChip(
                            label: Text(
                              _formatFolderLabel(cat),
                              style: DaywellTypography.caption(
                                color: moduleState.categoryFilter == cat
                                    ? colorScheme.onPrimaryContainer
                                    : semantic.textSecondary,
                              ),
                            ),
                            selected: moduleState.categoryFilter == cat,
                            onSelected: (_) => controller.setCategoryFilter(cat),
                          ),
                          const SizedBox(width: SharedDesignTokens.spacingSm),
                        ],
                      ],
                    ),
                  ),
                  if (hasError)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        SharedDesignTokens.spacingMd,
                        SharedDesignTokens.spacingXs,
                        SharedDesignTokens.spacingMd,
                        SharedDesignTokens.spacingSm,
                      ),
                      child: DaywellStatusBanner(
                        tone: DaywellStatusTone.error,
                        title: 'Notes persistence error',
                        message: moduleState.errorMessage!,
                        actionLabel: 'Retry',
                        onActionPressed: () =>
                            unawaited(controller.loadNotes()),
                      ),
                    ),
                  if (moduleState.sectionFilter == 'trash' && notes.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(
                        SharedDesignTokens.spacingMd,
                        0,
                        SharedDesignTokens.spacingMd,
                        SharedDesignTokens.spacingSm,
                      ),
                      child: DaywellStatusBanner(
                        tone: DaywellStatusTone.warning,
                        title: 'Trash',
                        message:
                            'Tap a trashed note to restore it before editing, or use the menu to delete permanently.',
                      ),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: moduleState.isLoading && notes.isEmpty
                        ? const DaywellLoadingIndicator(label: 'Loading notes...')
                        : notes.isEmpty
                            ? _buildEmptyState(context, controller, moduleState)
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  if (moduleState.isGridView) {
                                    final int crossAxisCount =
                                        constraints.maxWidth >=
                                                SharedDesignTokens
                                                    .breakpointExpanded
                                            ? 3
                                            : constraints.maxWidth < 340
                                                ? 1
                                                : 2;
                                    final double cardExtent = (244.0 *
                                            textScale.clamp(1.0, 2.0))
                                        .ceilToDouble();
                                    return GridView.builder(
                                      padding: const EdgeInsets.fromLTRB(
                                        SharedDesignTokens.spacingMd,
                                        SharedDesignTokens.spacingCompact,
                                        SharedDesignTokens.spacingMd,
                                        88.0,
                                      ),
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: crossAxisCount,
                                        crossAxisSpacing:
                                            SharedDesignTokens.spacingCompact,
                                        mainAxisSpacing:
                                            SharedDesignTokens.spacingCompact,
                                        mainAxisExtent: cardExtent,
                                      ),
                                      itemCount: notes.length,
                                      itemBuilder: (_, i) => _buildNoteCard(
                                        notes[i],
                                        true,
                                      ),
                                    );
                                  }

                                  return ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                      SharedDesignTokens.spacingMd,
                                      SharedDesignTokens.spacingCompact,
                                      SharedDesignTokens.spacingMd,
                                      88.0,
                                    ),
                                    itemCount: notes.length,
                                    itemBuilder: (_, i) => Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: SharedDesignTokens
                                              .breakpointMaxContentWidth,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            bottom:
                                                SharedDesignTokens.spacingSm,
                                          ),
                                          child: _buildNoteCard(
                                            notes[i],
                                            false,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoteCard(NoteEntity note, bool isGridView) {
    final controller = widget.effectiveController;
    final tasksCtrl = widget.effectiveTasksController;
    final linkedTask = tasksCtrl != null
        ? TaskNotesHelper.findLinkedTask(note, tasksCtrl.state.tasks)
        : null;
    final theme = Theme.of(context);
    final semantic = context.daywellColors;
    final colorScheme = theme.colorScheme;
    final ethDate =
        CalendarDate.fromUtcInstantInEthiopia(note.updatedAt).toEthiopian();
    final isPinnedActive = note.isPinned && !note.isTrashed && !note.isArchived;

    final snippetRaw = NoteMarkdownParser.toPlainText(note.content);
    final snippetText = snippetRaw.isNotEmpty ? snippetRaw : note.content;
    final Widget snippetWidget = Text(
      snippetText,
      maxLines: isGridView ? 4 : 2,
      overflow: TextOverflow.ellipsis,
      style: DaywellTypography.fromToken(
        SharedDesignTokens.typeBodyCompact,
        color: semantic.textSecondary,
      ),
    );

    return DaywellCard(
      padding: EdgeInsets.zero,
      borderRadius: SharedDesignTokens.radiusLg,
      borderColor: isPinnedActive
          ? colorScheme.primary.withOpacity(0.45)
          : semantic.border,
      onTap: note.isTrashed
          ? () => _promptRestoreTrashedNote(note)
          : () => _openNoteEditor(note),
      child: Padding(
        padding: EdgeInsets.all(
          isGridView
              ? SharedDesignTokens.spacingCompact
              : SharedDesignTokens.spacingMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: semantic.textPrimary,
                    ),
                  ),
                ),
                if (isPinnedActive) ...[
                  const SizedBox(width: SharedDesignTokens.spacingXs),
                  Icon(
                    Icons.push_pin_rounded,
                    size: DaywellIconSize.sm,
                    color: colorScheme.primary,
                    semanticLabel: 'Pinned',
                  ),
                ],
                if (note.isFavorite && !note.isTrashed && !note.isArchived) ...[
                  const SizedBox(width: SharedDesignTokens.spacingXs),
                  Icon(
                    Icons.star_rounded,
                    size: DaywellIconSize.sm,
                    color: semantic.warning,
                    semanticLabel: 'Favorite',
                  ),
                ],
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  iconSize: DaywellIconSize.md,
                  iconColor: semantic.textSecondary,
                  tooltip: 'Note actions',
                  onSelected: (action) {
                    if (action == 'pin') {
                      unawaited(controller.togglePin(note.id));
                    } else if (action == 'fav') {
                      unawaited(controller.toggleFavorite(note.id));
                    } else if (action == 'duplicate') {
                      unawaited(controller.duplicateNote(note.id));
                    } else if (action == 'copy') {
                      unawaited(
                        Clipboard.setData(
                          ClipboardData(
                            text: '${note.title}\n\n${note.content}',
                          ),
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Note copied to clipboard'),
                        ),
                      );
                    } else if (action == 'archive') {
                      unawaited(controller.toggleArchive(note.id));
                    } else if (action == 'trash') {
                      if (note.isTrashed) {
                        unawaited(controller.restoreFromTrash(note.id));
                      } else {
                        unawaited(controller.deleteNote(note.id));
                      }
                    } else if (action == 'delete') {
                      _confirmPermanentDelete(note);
                    }
                  },
                  itemBuilder: (_) => [
                    if (!note.isTrashed && !note.isArchived) ...[
                      PopupMenuItem(
                        value: 'pin',
                        child: Text(note.isPinned ? 'Unpin' : 'Pin'),
                      ),
                      PopupMenuItem(
                        value: 'fav',
                        child: Text(
                          note.isFavorite ? 'Remove Favorite' : 'Favorite',
                        ),
                      ),
                    ],
                    if (!note.isTrashed)
                      const PopupMenuItem(
                        value: 'duplicate',
                        child: Text('Duplicate'),
                      ),
                    const PopupMenuItem(
                      value: 'copy',
                      child: Text('Copy Content'),
                    ),
                    if (!note.isTrashed)
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(note.isArchived ? 'Unarchive' : 'Archive'),
                      ),
                    PopupMenuItem(
                      value: 'trash',
                      child: Text(
                        note.isTrashed ? 'Restore from Trash' : 'Move to Trash',
                      ),
                    ),
                    if (note.isTrashed)
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete Permanently',
                          style: TextStyle(
                            color: colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: SharedDesignTokens.spacingXs),
            if (isGridView)
              Expanded(child: snippetWidget)
            else
              snippetWidget,
            const SizedBox(height: SharedDesignTokens.spacingCompact),
            Wrap(
              spacing: SharedDesignTokens.spacingSm,
              runSpacing: SharedDesignTokens.spacingXs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SharedDesignTokens.spacingSm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius:
                        BorderRadius.circular(SharedDesignTokens.radiusSm),
                  ),
                  child: Text(
                    _formatFolderLabel(note.category),
                    style: DaywellTypography.caption(
                      color: colorScheme.onPrimaryContainer,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (note.isTrashed)
                  const DaywellStatusBadge(
                    label: 'Trash',
                    tone: DaywellStatusTone.error,
                    showIcon: false,
                  )
                else if (note.isArchived)
                  const DaywellStatusBadge(
                    label: 'Archived',
                    tone: DaywellStatusTone.warning,
                    showIcon: false,
                  ),
                for (final t in note.tags.take(2))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SharedDesignTokens.spacingSm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: semantic.transferContainer,
                      borderRadius:
                          BorderRadius.circular(SharedDesignTokens.radiusSm),
                    ),
                    child: Text(
                      '#$t',
                      style: DaywellTypography.caption(
                        color: semantic.onTransferContainer,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                Text(
                  SharedDateFormatter.formatEthiopian(
                    ethDate,
                    useAmharic: false,
                    includeEra: false,
                  ),
                  style: DaywellTypography.caption(color: semantic.textMuted),
                ),
              ],
            ),
            if (note.isLinkedToTask) ...[
              const SizedBox(height: SharedDesignTokens.spacingSm),
              InkWell(
                borderRadius:
                    BorderRadius.circular(SharedDesignTokens.radiusSm),
                onTap: linkedTask != null && widget.onOpenTask != null
                    ? () => widget.onOpenTask!(linkedTask.id)
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SharedDesignTokens.spacingSm,
                    vertical: SharedDesignTokens.spacingXs,
                  ),
                  decoration: BoxDecoration(
                    color: linkedTask != null
                        ? colorScheme.primaryContainer
                        : semantic.surfaceSubtle,
                    borderRadius:
                        BorderRadius.circular(SharedDesignTokens.radiusSm),
                    border: linkedTask == null
                        ? Border.all(color: semantic.border)
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: DaywellIconSize.xs,
                        color: linkedTask != null
                            ? colorScheme.primary
                            : semantic.textMuted,
                      ),
                      const SizedBox(width: SharedDesignTokens.spacingXs),
                      Flexible(
                        child: Text(
                          linkedTask != null
                              ? 'Task: ${linkedTask.title}'
                              : 'Linked task unavailable',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DaywellTypography.caption(
                            color: linkedTask != null
                                ? colorScheme.onPrimaryContainer
                                : semantic.textMuted,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoteEditorScreen extends StatefulWidget {
  final NotesController controller;
  final TasksController? tasksController;
  final void Function(String taskId)? onOpenTask;
  final NoteEntity? existingNote;
  final bool initialPreviewMode;

  const _NoteEditorScreen({
    required this.controller,
    this.tasksController,
    this.onOpenTask,
    required this.existingNote,
    this.initialPreviewMode = false,
  });

  @override
  State<_NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<_NoteEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingValue _previousContentValue;
  bool _isApplyingProgrammaticContentEdit = false;
  late String _category;
  late List<String> _tags;
  String? _noteId;
  String? _linkedModule;
  String? _linkedId;
  Timer? _autosaveTimer;
  String _saveStatus = 'Saved';
  String? _saveErrorMessage;
  int _editRevision = 0;
  int _savedRevision = 0;
  Future<void> _savePipeline = Future<void>.value();
  bool _isDisposed = false;
  bool _allowDiscardOnNextPop = false;
  bool _isHandlingPop = false;
  bool _hasPopped = false;
  bool _isPreviewMode = false;
  bool _isWriteBacklinksExpanded = false;
  NoteChecklistLineStatus? _activeWriteChecklist;

  bool get _hasPendingChanges =>
      _editRevision > _savedRevision || _saveErrorMessage != null;

  NoteChecklistLineStatus? _resolveActiveWriteChecklist(
    TextEditingValue value,
  ) {
    final sel = value.selection;
    final start = sel.isValid && sel.start >= 0 ? sel.start : value.text.length;
    final end = sel.isValid && sel.end >= 0 ? sel.end : start;
    return NoteMarkdownParser.getChecklistAtSelection(value.text, start, end);
  }

  @override
  void initState() {
    super.initState();
    _isPreviewMode = widget.initialPreviewMode;
    _noteId = widget.existingNote?.id;
    _titleController =
        TextEditingController(text: widget.existingNote?.title ?? '');
    _contentController =
        TextEditingController(text: widget.existingNote?.content ?? '');
    _previousContentValue = _contentController.value;
    _activeWriteChecklist =
        _resolveActiveWriteChecklist(_contentController.value);
    _contentController.addListener(_handleContentControllerSelectionTrack);
    _category = widget.existingNote != null
        ? NoteDomainHelpers.normalizeFlutterCategory(
            widget.existingNote!.category,
          )
        : 'reflection';
    _tags = NoteDomainHelpers.normalizeTags(widget.existingNote?.tags ?? const [])
        .toList();
    _linkedModule = widget.existingNote?.linkedModule;
    _linkedId = widget.existingNote?.linkedId;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _autosaveTimer?.cancel();
    _contentController.removeListener(_handleContentControllerSelectionTrack);
    if (_hasPendingChanges && !_allowDiscardOnNextPop) {
      final finalSnapshot = _captureSnapshot();
      unawaited(_enqueueSaveSnapshot(finalSnapshot, fromDispose: true));
    }
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  _NoteDraftSnapshot _captureSnapshot() {
    return (
      revision: _editRevision,
      title: _titleController.text,
      content: _contentController.text,
      category: _category,
      tags: List<String>.unmodifiable(_tags),
      linkedModule: _linkedModule,
      linkedId: _linkedId,
    );
  }

  void _markDirty({bool scheduleTimer = true}) {
    _editRevision++;
    _allowDiscardOnNextPop = false;
    _saveErrorMessage = null;
    setState(() => _saveStatus = 'Saving...');
    _autosaveTimer?.cancel();
    if (scheduleTimer) {
      _autosaveTimer = Timer(
        const Duration(milliseconds: 600),
        () => unawaited(_flushPendingSaves()),
      );
    }
  }

  Future<bool> _flushPendingSaves({bool fromDispose = false}) {
    _autosaveTimer?.cancel();
    if (!_hasPendingChanges && !fromDispose) {
      return Future<bool>.value(true);
    }
    final snapshot = _captureSnapshot();
    return _enqueueSaveSnapshot(snapshot, fromDispose: fromDispose);
  }

  Future<bool> _enqueueSaveSnapshot(
    _NoteDraftSnapshot snapshot, {
    required bool fromDispose,
  }) {
    final completer = Completer<bool>();
    _savePipeline = _savePipeline.catchError((Object _) {}).then((_) async {
      final ok = await _persistSnapshot(snapshot, fromDispose: fromDispose);
      completer.complete(ok);
    });
    return completer.future;
  }

  Future<bool> _persistSnapshot(
    _NoteDraftSnapshot snapshot, {
    required bool fromDispose,
  }) async {
    if (!fromDispose && !_isDisposed && snapshot.revision < _editRevision) {
      return true;
    }

    final isNewBlankDraft = _noteId == null &&
        snapshot.title.trim().isEmpty &&
        snapshot.content.trim().isEmpty;
    if (isNewBlankDraft) {
      if (snapshot.revision > _savedRevision) {
        _savedRevision = snapshot.revision;
      }
      if (!fromDispose && mounted && _editRevision == _savedRevision) {
        setState(() {
          _saveErrorMessage = null;
          _saveStatus = 'Saved';
        });
      }
      return true;
    }

    final persistTitle = NoteDomainHelpers.normalizeTitle(snapshot.title);

    if (_noteId == null) {
      final created = await widget.controller.createNote(
        title: persistTitle,
        content: snapshot.content,
        category: snapshot.category,
        tags: snapshot.tags,
        linkedModule: snapshot.linkedModule,
        linkedId: snapshot.linkedId,
      );
      final persisted = widget.controller.state.findById(created.id);
      if (persisted == null) {
        final err = widget.controller.state.errorMessage;
        if (!fromDispose && mounted) {
          setState(() {
            _saveStatus = 'Save failed';
            _saveErrorMessage = err ?? 'Unable to save note.';
          });
        }
        return false;
      }
      _noteId = persisted.id;
      _savedRevision = snapshot.revision;
    } else {
      final result = await widget.controller.updateNote(
        id: _noteId!,
        title: persistTitle,
        content: snapshot.content,
        category: snapshot.category,
        tags: snapshot.tags,
        linkedModule: snapshot.linkedModule,
        linkedId: snapshot.linkedId,
        clearLink: snapshot.linkedModule == null || snapshot.linkedId == null,
      );
      if (!result.saved) {
        if (!fromDispose && mounted) {
          setState(() {
            _saveStatus = 'Save failed';
            _saveErrorMessage = result.errorMessage ?? 'Unable to save note.';
          });
        }
        return false;
      }
      _savedRevision = snapshot.revision;
    }

    if (!fromDispose && mounted) {
      setState(() {
        _saveErrorMessage = null;
        _saveStatus =
            _editRevision == _savedRevision ? 'Saved' : 'Saving...';
      });
    }
    return true;
  }

  Future<void> _handleTogglePin() async {
    final ok = await _flushPendingSaves();
    if (!ok || _noteId == null) return;
    await widget.controller.togglePin(_noteId!);
  }

  Future<void> _handleToggleFavorite() async {
    final ok = await _flushPendingSaves();
    if (!ok || _noteId == null) return;
    await widget.controller.toggleFavorite(_noteId!);
  }

  Future<void> _linkTask(TaskEntity task) async {
    final prevModule = _linkedModule;
    final prevId = _linkedId;
    setState(() {
      _linkedModule = NoteEntity.taskLinkModule;
      _linkedId = task.id;
    });
    _markDirty(scheduleTimer: false);
    if (_noteId != null) {
      final ok = await _flushPendingSaves();
      if (!ok && mounted) {
        setState(() {
          if (_linkedModule == NoteEntity.taskLinkModule &&
              _linkedId == task.id) {
            _linkedModule = prevModule;
            _linkedId = prevId;
          }
        });
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not link task. Kept previous link state.'),
          ),
        );
      }
    }
  }

  Future<void> _unlinkTask() async {
    final prevModule = _linkedModule;
    final prevId = _linkedId;
    setState(() {
      _linkedModule = null;
      _linkedId = null;
    });
    _markDirty(scheduleTimer: false);
    if (_noteId != null) {
      final ok = await _flushPendingSaves();
      if (!ok) {
        if (mounted) {
          setState(() {
            if (_linkedModule == null && _linkedId == null) {
              _linkedModule = prevModule;
              _linkedId = prevId;
            }
          });
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not unlink task. Kept existing link.'),
            ),
          );
        }
        return;
      }
    }
    if (!mounted || prevModule == null || prevId == null) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Unlinked task from note'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted) return;
            setState(() {
              _linkedModule = prevModule;
              _linkedId = prevId;
            });
            _markDirty(scheduleTimer: false);
            if (_noteId != null) {
              unawaited(() async {
                final restored = await _flushPendingSaves();
                if (!restored && mounted) {
                  setState(() {
                    if (_linkedModule == prevModule && _linkedId == prevId) {
                      _linkedModule = null;
                      _linkedId = null;
                    }
                  });
                }
              }());
            }
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _openTaskPicker() {
    final tasksCtrl = widget.tasksController;
    if (tasksCtrl == null) return;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SharedDesignTokens.radiusSheet),
          ),
        ),
        builder: (_) => _NoteTaskPickerSheet(
          tasksController: tasksCtrl,
          currentTaskId:
              _linkedModule == NoteEntity.taskLinkModule ? _linkedId : null,
          onSelectTask: (task) => unawaited(_linkTask(task)),
        ),
      ),
    );
  }

  void _handleContentControllerSelectionTrack() {
    if (_isApplyingProgrammaticContentEdit) return;
    final curr = _contentController.value;
    // Track cursor/selection moves before the next text edit without touching
    // _previousContentValue while onChanged inspects a just-committed edit.
    if (curr.text == _previousContentValue.text) {
      _previousContentValue = curr;
      final nextChecklist = _resolveActiveWriteChecklist(curr);
      if (nextChecklist?.lineIndex != _activeWriteChecklist?.lineIndex ||
          nextChecklist?.checked != _activeWriteChecklist?.checked) {
        setState(() => _activeWriteChecklist = nextChecklist);
      }
    }
  }

  void _applyProgrammaticContentEdit(
    String nextText,
    int selectionStart,
    int selectionEnd,
  ) {
    _isApplyingProgrammaticContentEdit = true;
    final nextValue = TextEditingValue(
      text: nextText,
      selection: TextSelection(
        baseOffset: selectionStart,
        extentOffset: selectionEnd,
      ),
    );
    _contentController.value = nextValue;
    _previousContentValue = nextValue;
    _activeWriteChecklist = _resolveActiveWriteChecklist(nextValue);
    _isApplyingProgrammaticContentEdit = false;
  }

  void _handleToggleChecklistLine(int lineIndex) {
    final toggled = NoteMarkdownParser.toggleChecklistAtLine(
      _contentController.text,
      lineIndex,
    );
    if (toggled == null) return;
    final sel = _contentController.selection;
    final rawStart =
        sel.isValid && sel.start >= 0 ? sel.start : toggled.text.length;
    final rawEnd = sel.isValid && sel.end >= 0 ? sel.end : rawStart;
    final nextStart = rawStart.clamp(0, toggled.text.length);
    final nextEnd = rawEnd.clamp(0, toggled.text.length);
    _applyProgrammaticContentEdit(toggled.text, nextStart, nextEnd);
    _markDirty();
  }

  void _handleBodyTextChanged(String _) {
    if (_isApplyingProgrammaticContentEdit) return;
    final prev = _previousContentValue;
    final curr = _contentController.value;
    final isComposing =
        curr.composing.isValid && !curr.composing.isCollapsed;

    if (!isComposing && prev.selection.isValid && curr.selection.isCollapsed) {
      final prevStart = prev.selection.start <= prev.selection.end
          ? prev.selection.start
          : prev.selection.end;
      final prevEnd = prev.selection.start <= prev.selection.end
          ? prev.selection.end
          : prev.selection.start;
      final expectedEnterLen = prev.text.length - (prevEnd - prevStart) + 1;

      final insertedNewline = !HardwareKeyboard.instance.isShiftPressed &&
          curr.text.length == expectedEnterLen &&
          curr.selection.baseOffset == prevStart + 1 &&
          prevStart < curr.text.length &&
          curr.text[prevStart] == '\n' &&
          curr.text.substring(0, prevStart) == prev.text.substring(0, prevStart) &&
          curr.text.substring(prevStart + 1) == prev.text.substring(prevEnd);

      if (insertedNewline) {
        final smartEnter = NoteEditorFormatting.applySmartEnter(
          prev.text,
          prevStart,
          prevEnd,
        );
        if (smartEnter != null) {
          _applyProgrammaticContentEdit(
            smartEnter.text,
            smartEnter.selectionStart,
            smartEnter.selectionEnd,
          );
          _markDirty();
          return;
        }
      }

      final deletedSingleBeforeCursor = prev.selection.isCollapsed &&
          prevStart > 0 &&
          curr.text.length == prev.text.length - 1 &&
          curr.selection.baseOffset == prevStart - 1 &&
          curr.text ==
              '${prev.text.substring(0, prevStart - 1)}${prev.text.substring(prevStart)}';

      if (deletedSingleBeforeCursor) {
        final smartBackspace = NoteEditorFormatting.applySmartBackspace(
          prev.text,
          prevStart,
          prevStart,
        );
        if (smartBackspace != null) {
          _applyProgrammaticContentEdit(
            smartBackspace.text,
            smartBackspace.selectionStart,
            smartBackspace.selectionEnd,
          );
          _markDirty();
          return;
        }
      }
    }

    _previousContentValue = curr;
    _activeWriteChecklist = _resolveActiveWriteChecklist(curr);
    _markDirty();
  }

  void _applyToolbarFormat(NoteToolbarFormatAction action) {
    final text = _contentController.text;
    final sel = _contentController.selection;
    final start = sel.isValid && sel.start >= 0 ? sel.start : text.length;
    final end = sel.isValid && sel.end >= 0 ? sel.end : start;
    final next = NoteEditorFormatting.applyToolbarAction(
      text,
      start,
      end,
      action,
    );
    _applyProgrammaticContentEdit(
      next.text,
      next.selectionStart,
      next.selectionEnd,
    );
    _markDirty();
  }

  void _addTagDialog() {
    final ctrl = TextEditingController();
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Add Tag'),
          content: DaywellTextField(
            controller: ctrl,
            label: 'Tag name',
            hintText: 'e.g. architecture',
            autofocus: true,
          ),
          actions: [
            DaywellButton(
              label: 'Cancel',
              variant: DaywellButtonVariant.text,
              size: DaywellButtonSize.compact,
              onPressed: () => Navigator.pop(ctx),
            ),
            DaywellButton(
              label: 'Add',
              variant: DaywellButtonVariant.primary,
              size: DaywellButtonSize.compact,
              onPressed: () {
                final candidate = ctrl.text.trim().replaceAll('#', '').trim();
                if (candidate.isNotEmpty) {
                  final nextTags =
                      NoteDomainHelpers.normalizeTags([..._tags, candidate]);
                  if (nextTags.length != _tags.length) {
                    setState(() => _tags = nextTags.toList());
                    _markDirty(scheduleTimer: false);
                    if (_noteId != null) {
                      unawaited(_flushPendingSaves());
                    }
                  }
                }
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ).whenComplete(ctrl.dispose),
    );
  }

  Future<void> _handlePopAttempt() async {
    if (_isHandlingPop || _hasPopped) return;
    _isHandlingPop = true;
    try {
      var ok = true;
      while (mounted && !_isDisposed && _hasPendingChanges) {
        ok = await _flushPendingSaves();
        if (!ok) {
          break;
        }
      }
      if (!mounted || _isDisposed || _hasPopped) return;
      if (ok && !_hasPendingChanges) {
        final route = ModalRoute.of(context);
        if (route == null || route.isCurrent) {
          _hasPopped = true;
          Navigator.of(context).pop();
        }
        return;
      }
      setState(() => _allowDiscardOnNextPop = true);
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save changes. Tap Back again to discard unsaved edits.',
          ),
        ),
      );
    } finally {
      _isHandlingPop = false;
    }
  }

  Future<void> _openInternalNote(NoteEntity targetNote) async {
    if (targetNote.id == _noteId) return;
    final ok = await _flushPendingSaves();
    if (!ok || !mounted || _isDisposed) return;

    final freshTarget = widget.controller.state.findById(targetNote.id);
    if (freshTarget == null || !NoteDomainHelpers.isActive(freshTarget)) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Referenced note is unavailable.'),
        ),
      );
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _NoteEditorScreen(
          controller: widget.controller,
          tasksController: widget.tasksController,
          onOpenTask: widget.onOpenTask,
          existingNote: freshTarget,
          initialPreviewMode: _isPreviewMode,
        ),
      ),
    );
  }

  void _openAmbiguousInternalLinkChooser(
    String targetTitle,
    List<NoteEntity> matches,
  ) {
    final activeMatches = matches
        .map((m) => widget.controller.state.findById(m.id) ?? m)
        .where(NoteDomainHelpers.isActive)
        .toList();
    if (activeMatches.isEmpty) return;
    if (activeMatches.length == 1) {
      unawaited(_openInternalNote(activeMatches.first));
      return;
    }

    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) {
          final semantic = ctx.daywellColors;
          final colorScheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: Text('Choose note for "$targetTitle"'),
            content: SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: activeMatches.length,
                  separatorBuilder: (_, __) => const SizedBox(
                    height: SharedDesignTokens.spacingXs,
                  ),
                  itemBuilder: (_, index) {
                    final match = activeMatches[index];
                    final snippet = NoteMarkdownParser.toPlainText(match.content)
                        .replaceAll(RegExp(r'\s+'), ' ')
                        .trim();
                    final ethDate =
                        EthiopiaClock.toEthiopianDate(match.updatedAt);
                    final dateLabel = SharedDateFormatter.formatEthiopian(
                      ethDate,
                      useAmharic: false,
                      includeEra: false,
                    );
                    return DaywellCard(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        leading: Icon(
                          Icons.description_outlined,
                          color: colorScheme.primary,
                        ),
                        title: Text(
                          match.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DaywellTypography.fromToken(
                            SharedDesignTokens.typeBodyCompact,
                            color: semantic.textPrimary,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          snippet.isNotEmpty
                              ? '${_formatFolderLabel(match.category)} · $dateLabel · $snippet'
                              : '${_formatFolderLabel(match.category)} · $dateLabel',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: DaywellTypography.caption(
                            color: semantic.textSecondary,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          unawaited(_openInternalNote(match));
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
            actions: [
              DaywellButton(
                label: 'Cancel',
                variant: DaywellButtonVariant.text,
                size: DaywellButtonSize.compact,
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasksCtrl = widget.tasksController;
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        if (tasksCtrl != null) tasksCtrl,
      ]),
      builder: (context, _) {
        final currentNote =
            _noteId != null ? widget.controller.state.findById(_noteId!) : null;
        final isPinned = currentNote?.isPinned ?? false;
        final isFavorite = currentNote?.isFavorite ?? false;
        final effectiveLinkedModule =
            currentNote != null ? currentNote.linkedModule : _linkedModule;
        final effectiveLinkedId =
            currentNote != null ? currentNote.linkedId : _linkedId;
        final isTaskLinked =
            effectiveLinkedModule == NoteEntity.taskLinkModule &&
                effectiveLinkedId != null;
        final linkedTask = effectiveLinkedModule == NoteEntity.taskLinkModule &&
                effectiveLinkedId != null &&
                tasksCtrl != null
            ? tasksCtrl.state.findTaskById(effectiveLinkedId)
            : null;
        final semantic = context.daywellColors;
        final colorScheme = Theme.of(context).colorScheme;
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final double? adaptiveToolbarHeight = textScale > 1.3
            ? (kToolbarHeight * textScale.clamp(1.0, 2.1)).ceilToDouble()
            : null;
        final isNewBlankDraft = _noteId == null &&
            _titleController.text.trim().isEmpty &&
            _contentController.text.trim().isEmpty;
        final liveNotesForInternalLinks = _noteId == null
            ? widget.controller.state.notes
            : widget.controller.state.notes
                .map(
                  (n) => n.id == _noteId
                      ? n.copyWith(
                          title: _titleController.text,
                          content: _contentController.text,
                          category: _category,
                          tags: _tags,
                          updatedAt: n.updatedAt,
                        )
                      : n,
                )
                .toList();
        final backlinks = isNewBlankDraft
            ? const <NoteBacklinkEntry>[]
            : NoteLinksDomain.findBacklinks(
                NoteEntity(
                  id: _noteId ?? '__new_draft__',
                  title: _titleController.text,
                  content: _contentController.text,
                  category: _category,
                  isArchived: currentNote?.isArchived ?? false,
                  isTrashed: currentNote?.isTrashed ?? false,
                ),
                liveNotesForInternalLinks,
              );
        const baseDropdownOrder = [
          'reflection',
          'reference',
          'learning',
          'general',
        ];
        final extraDropdownCategories = widget
            .controller.state.availableCategories
            .where((c) => !baseDropdownOrder.contains(c))
            .toList()
          ..sort();
        final dropdownCategories = <String>[
          ...baseDropdownOrder,
          ...extraDropdownCategories,
          if (!baseDropdownOrder.contains(_category) &&
              !extraDropdownCategories.contains(_category))
            _category,
        ];

        return PopScope<Object?>(
          canPop: !_hasPendingChanges || _allowDiscardOnNextPop,
          onPopInvokedWithResult: (bool didPop, Object? _) {
            if (!didPop) {
              unawaited(_handlePopAttempt());
            }
          },
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: adaptiveToolbarHeight,
              title: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: SharedDesignTokens.spacingSm,
                  vertical: SharedDesignTokens.spacingXs,
                ),
                decoration: BoxDecoration(
                  color: _saveStatus == 'Save failed'
                      ? semantic.errorContainer
                      : semantic.surfaceSubtle,
                  borderRadius:
                      BorderRadius.circular(SharedDesignTokens.radiusSm),
                  border: Border.all(
                    color: _saveStatus == 'Save failed'
                        ? colorScheme.error.withOpacity(0.4)
                        : semantic.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _saveStatus == 'Save failed'
                          ? Icons.error_outline
                          : _saveStatus == 'Saving...'
                              ? Icons.sync_rounded
                              : Icons.cloud_done_outlined,
                      size: DaywellIconSize.xs,
                      color: _saveStatus == 'Save failed'
                          ? colorScheme.error
                          : _saveStatus == 'Saving...'
                              ? colorScheme.primary
                              : semantic.textMuted,
                    ),
                    const SizedBox(width: SharedDesignTokens.spacingXs),
                    Flexible(
                      child: Text(
                        _saveStatus,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DaywellTypography.label(
                          color: _saveStatus == 'Save failed'
                              ? colorScheme.error
                              : _saveStatus == 'Saving...'
                                  ? colorScheme.primary
                                  : semantic.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (_noteId != null) ...[
                  DaywellIconButton(
                    icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    isSelected: isPinned,
                    tooltip: isPinned ? 'Unpin note' : 'Pin note',
                    onPressed: () => unawaited(_handleTogglePin()),
                  ),
                  DaywellIconButton(
                    icon: isFavorite ? Icons.star : Icons.star_border,
                    isSelected: isFavorite,
                    foregroundColor:
                        isFavorite ? semantic.warning : semantic.textSecondary,
                    tooltip: isFavorite ? 'Remove favorite' : 'Favorite note',
                    onPressed: () => unawaited(_handleToggleFavorite()),
                  ),
                ],
                DaywellIconButton(
                  icon: Icons.copy_rounded,
                  tooltip: 'Copy note',
                  onPressed: () {
                    unawaited(
                      Clipboard.setData(
                        ClipboardData(
                          text:
                              '${_titleController.text}\n\n${_contentController.text}',
                        ),
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Note copied to clipboard')),
                    );
                  },
                ),
              ],
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: SharedDesignTokens.breakpointMaxContentWidth,
                ),
                child: Column(
                  children: [
                    if (_saveErrorMessage != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SharedDesignTokens.spacingMd,
                          SharedDesignTokens.spacingXs,
                          SharedDesignTokens.spacingMd,
                          SharedDesignTokens.spacingXs,
                        ),
                        child: DaywellStatusBanner(
                          tone: DaywellStatusTone.error,
                          title: 'Unable to save note',
                          message: _saveErrorMessage!,
                          actionLabel: 'Retry',
                          onActionPressed: () =>
                              unawaited(_flushPendingSaves()),
                        ),
                      ),
                    if (!_isPreviewMode)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SharedDesignTokens.spacingMd,
                          SharedDesignTokens.spacingSm,
                          SharedDesignTokens.spacingMd,
                          0,
                        ),
                        child: TextField(
                          controller: _titleController,
                          style: DaywellTypography.fromToken(
                            SharedDesignTokens.typeHeading,
                            color: semantic.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Note title...',
                            hintStyle: DaywellTypography.fromToken(
                              SharedDesignTokens.typeHeading,
                              color: semantic.textMuted,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: SharedDesignTokens.spacingSm,
                            ),
                          ),
                          onChanged: (_) => _markDirty(),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SharedDesignTokens.spacingMd,
                          SharedDesignTokens.spacingCompact,
                          SharedDesignTokens.spacingMd,
                          SharedDesignTokens.spacingSm,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(
                            NoteDomainHelpers.normalizeTitle(
                              _titleController.text,
                            ),
                            style: DaywellTypography.fromToken(
                              SharedDesignTokens.typeHeading,
                              color: semantic.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SharedDesignTokens.spacingMd,
                        vertical: SharedDesignTokens.spacingXs,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: SharedDesignTokens.spacingSm,
                          runSpacing: SharedDesignTokens.spacingXs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: SharedDesignTokens.spacingSm,
                              ),
                              decoration: BoxDecoration(
                                color: semantic.surfaceSubtle,
                                borderRadius: BorderRadius.circular(
                                  SharedDesignTokens.radiusSm,
                                ),
                                border: Border.all(color: semantic.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.folder_outlined,
                                    size: DaywellIconSize.xs,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(
                                    width: SharedDesignTokens.spacingXs,
                                  ),
                                  DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _category,
                                      isDense: true,
                                      style: DaywellTypography.label(
                                        color: semantic.textPrimary,
                                      ),
                                      items: [
                                        for (final cat in dropdownCategories)
                                          DropdownMenuItem(
                                            value: cat,
                                            child: Text(_formatFolderLabel(cat)),
                                          ),
                                      ],
                                      onChanged: (val) {
                                        if (val != null && val != _category) {
                                          setState(() => _category = val);
                                          _markDirty();
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ActionChip(
                              avatar: Icon(
                                Icons.tag,
                                size: DaywellIconSize.xs,
                                color: semantic.textSecondary,
                              ),
                              label: Text(
                                'Add Tag',
                                style: DaywellTypography.label(
                                  color: semantic.textPrimary,
                                ),
                              ),
                              onPressed: _addTagDialog,
                            ),
                            if (tasksCtrl != null && !isTaskLinked)
                              ActionChip(
                                avatar: Icon(
                                  Icons.add_link,
                                  size: DaywellIconSize.xs,
                                  color: colorScheme.primary,
                                ),
                                label: Text(
                                  'Link Task',
                                  style: DaywellTypography.label(
                                    color: semantic.textPrimary,
                                  ),
                                ),
                                onPressed: _openTaskPicker,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (isTaskLinked)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SharedDesignTokens.spacingMd,
                          SharedDesignTokens.spacingXs,
                          SharedDesignTokens.spacingMd,
                          SharedDesignTokens.spacingXs,
                        ),
                        child: DaywellCard(
                          color: linkedTask != null
                              ? colorScheme.primaryContainer
                              : semantic.surfaceSubtle,
                          borderColor: semantic.border,
                          borderRadius: SharedDesignTokens.radiusMd,
                          padding: const EdgeInsets.symmetric(
                            horizontal: SharedDesignTokens.spacingCompact,
                            vertical: SharedDesignTokens.spacingXs,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: DaywellIconSize.sm,
                                color: linkedTask != null
                                    ? colorScheme.primary
                                    : semantic.textMuted,
                              ),
                              const SizedBox(
                                width: SharedDesignTokens.spacingSm,
                              ),
                              Expanded(
                                child: Text(
                                  linkedTask != null
                                      ? 'Linked Task: ${linkedTask.title}'
                                      : 'Linked task unavailable',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DaywellTypography.fromToken(
                                    SharedDesignTokens.typeBodyCompact,
                                    color: linkedTask != null
                                        ? colorScheme.onPrimaryContainer
                                        : semantic.textMuted,
                                  ).copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (linkedTask != null &&
                                  widget.onOpenTask != null)
                                DaywellButton(
                                  label: 'Open',
                                  variant: DaywellButtonVariant.text,
                                  size: DaywellButtonSize.compact,
                                  onPressed: () async {
                                    final ok = await _flushPendingSaves();
                                    if (!ok || !context.mounted) return;
                                    Navigator.pop(context);
                                    widget.onOpenTask!(linkedTask.id);
                                  },
                                ),
                              if (tasksCtrl != null)
                                DaywellIconButton(
                                  icon: Icons.swap_horiz,
                                  iconSize: DaywellIconSize.md,
                                  tooltip: 'Change Linked Task',
                                  onPressed: _openTaskPicker,
                                ),
                              DaywellIconButton(
                                icon: Icons.link_off_outlined,
                                iconSize: DaywellIconSize.md,
                                tooltip: 'Unlink Task',
                                onPressed: () => unawaited(_unlinkTask()),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SharedDesignTokens.spacingMd,
                          vertical: SharedDesignTokens.spacingXs,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: SharedDesignTokens.spacingSm,
                            runSpacing: SharedDesignTokens.spacingXs,
                            children: _tags
                                .map(
                                  (t) => Chip(
                                    backgroundColor: semantic.transferContainer,
                                    side: BorderSide(
                                      color: semantic.transfer.withOpacity(0.25),
                                    ),
                                    deleteIconColor:
                                        semantic.onTransferContainer,
                                    label: Text(
                                      '#$t',
                                      style: DaywellTypography.caption(
                                        color: semantic.onTransferContainer,
                                      ).copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    onDeleted: () {
                                      setState(() => _tags.remove(t));
                                      _markDirty(scheduleTimer: false);
                                      if (_noteId != null) {
                                        unawaited(_flushPendingSaves());
                                      }
                                    },
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        SharedDesignTokens.spacingMd,
                        SharedDesignTokens.spacingSm,
                        SharedDesignTokens.spacingMd,
                        SharedDesignTokens.spacingSm,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            color: semantic.surfaceSubtle,
                            borderRadius: BorderRadius.circular(
                              SharedDesignTokens.radiusMd,
                            ),
                            border: Border.all(color: semantic.border),
                          ),
                          padding: const EdgeInsets.all(
                            SharedDesignTokens.spacingXs,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildModeSegment(
                                label: 'Write',
                                icon: Icons.edit_outlined,
                                selected: !_isPreviewMode,
                                onTap: () {
                                  if (_isPreviewMode) {
                                    setState(() => _isPreviewMode = false);
                                  }
                                },
                                semantic: semantic,
                                colorScheme: colorScheme,
                              ),
                              const SizedBox(width: SharedDesignTokens.spacingXs),
                              _buildModeSegment(
                                label: 'Preview',
                                icon: Icons.visibility_outlined,
                                selected: _isPreviewMode,
                                onTap: () {
                                  if (!_isPreviewMode) {
                                    FocusScope.of(context).unfocus();
                                    setState(() => _isPreviewMode = true);
                                  }
                                },
                                semantic: semantic,
                                colorScheme: colorScheme,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    if (!_isPreviewMode) ...[
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SharedDesignTokens.spacingMd,
                          ),
                          child: TextField(
                            controller: _contentController,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            style: DaywellTypography.fromToken(
                              SharedDesignTokens.typeBody,
                              color: semantic.textPrimary,
                            ).copyWith(height: 1.55),
                            decoration: InputDecoration(
                              hintText:
                                  'Start writing (English & Amharic / ፊደል)...',
                              hintStyle: DaywellTypography.fromToken(
                                SharedDesignTokens.typeBody,
                                color: semantic.textMuted,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: SharedDesignTokens.spacingCompact,
                              ),
                            ),
                            onChanged: _handleBodyTextChanged,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: semantic.surfaceSubtle,
                          border: Border(
                            top: BorderSide(color: semantic.border),
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          bottom: isNewBlankDraft,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: SharedDesignTokens.spacingSm,
                              vertical: SharedDesignTokens.spacingXs,
                            ),
                            child: Row(
                              children: [
                                _buildToolbarActionButton(
                                  icon: Icons.title,
                                  tooltip: 'Heading 2',
                                  semantic: semantic,
                                  onPressed: () => _applyToolbarFormat(
                                    NoteToolbarFormatAction.heading2,
                                  ),
                                ),
                                _buildToolbarActionButton(
                                  icon: Icons.format_bold,
                                  tooltip: 'Bold',
                                  semantic: semantic,
                                  onPressed: () => _applyToolbarFormat(
                                    NoteToolbarFormatAction.bold,
                                  ),
                                ),
                                _buildToolbarActionButton(
                                  icon: Icons.format_italic,
                                  tooltip: 'Italic',
                                  semantic: semantic,
                                  onPressed: () => _applyToolbarFormat(
                                    NoteToolbarFormatAction.italic,
                                  ),
                                ),
                                _buildToolbarActionButton(
                                  icon: Icons.strikethrough_s,
                                  tooltip: 'Strikethrough',
                                  semantic: semantic,
                                  onPressed: () => _applyToolbarFormat(
                                    NoteToolbarFormatAction.strikethrough,
                                  ),
                                ),
                                _buildToolbarDivider(semantic),
                                _buildToolbarActionButton(
                                  icon: Icons.format_list_bulleted,
                                  tooltip: 'Bulleted list',
                                  semantic: semantic,
                                  onPressed: () => _applyToolbarFormat(
                                    NoteToolbarFormatAction.bulletList,
                                  ),
                                ),
                                _buildToolbarActionButton(
                                  icon: Icons.format_list_numbered,
                                  tooltip: 'Numbered list',
                                  semantic: semantic,
                                  onPressed: () => _applyToolbarFormat(
                                    NoteToolbarFormatAction.numberedList,
                                  ),
                                ),
                                _buildToolbarActionButton(
                                  icon: Icons.check_box_outlined,
                                  tooltip: 'Checklist',
                                  semantic: semantic,
                                  onPressed: () => _applyToolbarFormat(
                                    NoteToolbarFormatAction.checklist,
                                  ),
                                ),
                                _buildToolbarActionButton(
                                  icon: Icons.format_quote,
                                  tooltip: 'Blockquote',
                                  semantic: semantic,
                                  onPressed: () => _applyToolbarFormat(
                                    NoteToolbarFormatAction.blockquote,
                                  ),
                                ),
                                _buildToolbarDivider(semantic),
                                _buildToolbarActionButton(
                                  icon: Icons.code,
                                  tooltip: 'Inline code',
                                  semantic: semantic,
                                  onPressed: () => _applyToolbarFormat(
                                    NoteToolbarFormatAction.inlineCode,
                                  ),
                                ),
                                _buildToolbarActionButton(
                                  icon: Icons.data_object,
                                  tooltip: 'Code block',
                                  semantic: semantic,
                                  onPressed: () => _applyToolbarFormat(
                                    NoteToolbarFormatAction.codeBlock,
                                  ),
                                ),
                                _buildToolbarActionButton(
                                  icon: Icons.link,
                                  tooltip: 'Internal note link',
                                  semantic: semantic,
                                  onPressed: () => _applyToolbarFormat(
                                    NoteToolbarFormatAction.internalLink,
                                  ),
                                ),
                                if (_activeWriteChecklist != null) ...[
                                  _buildToolbarDivider(semantic),
                                  Tooltip(
                                    message: _activeWriteChecklist!.checked
                                        ? 'Mark item incomplete'
                                        : 'Mark item complete',
                                    child: Semantics(
                                      button: true,
                                      checked: _activeWriteChecklist!.checked,
                                      label: _activeWriteChecklist!.checked
                                          ? 'Mark item incomplete'
                                          : 'Mark item complete',
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(
                                          SharedDesignTokens.radiusSm,
                                        ),
                                        onTap: () => _handleToggleChecklistLine(
                                          _activeWriteChecklist!.lineIndex,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal:
                                                SharedDesignTokens.spacingCompact,
                                            vertical:
                                                SharedDesignTokens.spacingXs,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colorScheme.primaryContainer,
                                            borderRadius: BorderRadius.circular(
                                              SharedDesignTokens.radiusSm,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                _activeWriteChecklist!.checked
                                                    ? Icons.check_box_rounded
                                                    : Icons
                                                        .check_box_outline_blank_rounded,
                                                size: DaywellIconSize.sm,
                                                color: colorScheme
                                                    .onPrimaryContainer,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                _activeWriteChecklist!.checked
                                                    ? 'Checked'
                                                    : 'Check item',
                                                style: DaywellTypography.label(
                                                  color: colorScheme
                                                      .onPrimaryContainer,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (!isNewBlankDraft)
                        _buildWriteModeBacklinksBar(
                          backlinks: backlinks,
                          semantic: semantic,
                          colorScheme: colorScheme,
                        ),
                    ] else
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SharedDesignTokens.spacingMd,
                            vertical: SharedDesignTokens.spacingCompact,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              NoteMarkdownPreview(
                                content: _contentController.text,
                                notes: liveNotesForInternalLinks,
                                onToggleChecklistItem:
                                    _handleToggleChecklistLine,
                                onOpenInternalNote: (note) =>
                                    unawaited(_openInternalNote(note)),
                                onOpenAmbiguousInternalLink:
                                    _openAmbiguousInternalLinkChooser,
                              ),
                              if (!isNewBlankDraft) ...[
                                const SizedBox(
                                  height: SharedDesignTokens.spacingLg,
                                ),
                                _buildBacklinksSection(
                                  backlinks: backlinks,
                                  semantic: semantic,
                                  colorScheme: colorScheme,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolbarDivider(DaywellSemanticColors semantic) {
    return SizedBox(
      height: 20,
      child: VerticalDivider(
        width: SharedDesignTokens.spacingCompact,
        thickness: 1,
        color: semantic.divider,
      ),
    );
  }

  Widget _buildToolbarActionButton({
    required IconData icon,
    required String tooltip,
    required DaywellSemanticColors semantic,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: DaywellIconSize.md),
      color: semantic.textSecondary,
      tooltip: tooltip,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
        ),
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildWriteModeBacklinksBar({
    required List<NoteBacklinkEntry> backlinks,
    required DaywellSemanticColors semantic,
    required ColorScheme colorScheme,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: semantic.card,
        border: Border(top: BorderSide(color: semantic.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(
              () => _isWriteBacklinksExpanded = !_isWriteBacklinksExpanded,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SharedDesignTokens.spacingMd,
                vertical: SharedDesignTokens.spacingXs,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.call_received_rounded,
                    size: 14,
                    color: backlinks.isNotEmpty
                        ? colorScheme.primary
                        : semantic.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Backlinks (${backlinks.length})',
                      style: DaywellTypography.label(
                        color: semantic.textSecondary,
                      ),
                    ),
                  ),
                  Icon(
                    _isWriteBacklinksExpanded
                        ? Icons.expand_more
                        : Icons.expand_less,
                    size: 18,
                    color: semantic.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_isWriteBacklinksExpanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  SharedDesignTokens.spacingMd,
                  0,
                  SharedDesignTokens.spacingMd,
                  SharedDesignTokens.spacingSm,
                ),
                child: _buildBacklinksListBody(
                  backlinks: backlinks,
                  semantic: semantic,
                  colorScheme: colorScheme,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBacklinksSection({
    required List<NoteBacklinkEntry> backlinks,
    required DaywellSemanticColors semantic,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.only(top: SharedDesignTokens.spacingCompact),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: semantic.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.call_received_rounded,
                size: 14,
                color: backlinks.isNotEmpty
                    ? colorScheme.primary
                    : semantic.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                'BACKLINKS (${backlinks.length})',
                style: DaywellTypography.caption(
                  color: semantic.textMuted,
                ).copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.6),
              ),
            ],
          ),
          const SizedBox(height: SharedDesignTokens.spacingSm),
          _buildBacklinksListBody(
            backlinks: backlinks,
            semantic: semantic,
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  Widget _buildBacklinksListBody({
    required List<NoteBacklinkEntry> backlinks,
    required DaywellSemanticColors semantic,
    required ColorScheme colorScheme,
  }) {
    if (backlinks.isEmpty) {
      return Text(
        'No active notes link to this note yet.',
        style: DaywellTypography.fromToken(
          SharedDesignTokens.typeBodyCompact,
          color: semantic.textMuted,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < backlinks.length; i++) ...[
          if (i > 0) const SizedBox(height: SharedDesignTokens.spacingXs),
          Builder(
            builder: (_) {
              final entry = backlinks[i];
              return DaywellCard(
                padding: EdgeInsets.zero,
                child: InkWell(
                  borderRadius:
                      BorderRadius.circular(SharedDesignTokens.radiusMd),
                  onTap: () => unawaited(_openInternalNote(entry.note)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SharedDesignTokens.spacingCompact,
                      vertical: SharedDesignTokens.spacingSm,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.linkCount > 1
                                    ? '${entry.note.displayTitle} (${entry.linkCount})'
                                    : entry.note.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DaywellTypography.fromToken(
                                  SharedDesignTokens.typeBodyCompact,
                                  color: semantic.textPrimary,
                                ).copyWith(fontWeight: FontWeight.w600),
                              ),
                              if (entry.snippet.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  entry.snippet,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: DaywellTypography.caption(
                                    color: semantic.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_outward_rounded,
                          size: 15,
                          color: semantic.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildModeSegment({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    required DaywellSemanticColors semantic,
    required ColorScheme colorScheme,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(
            horizontal: SharedDesignTokens.spacingCompact,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: selected ? colorScheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: DaywellIconSize.sm,
                color: selected
                    ? colorScheme.onPrimaryContainer
                    : semantic.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: DaywellTypography.fromToken(
                  SharedDesignTokens.typeLabel,
                  color: selected
                      ? colorScheme.onPrimaryContainer
                      : semantic.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteTaskPickerSheet extends StatefulWidget {
  final TasksController tasksController;
  final String? currentTaskId;
  final void Function(TaskEntity task) onSelectTask;

  const _NoteTaskPickerSheet({
    required this.tasksController,
    required this.currentTaskId,
    required this.onSelectTask,
  });

  @override
  State<_NoteTaskPickerSheet> createState() => _NoteTaskPickerSheetState();
}

class _NoteTaskPickerSheetState extends State<_NoteTaskPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final tasks = widget.tasksController.state.tasks.where((t) {
      if (t.id == widget.currentTaskId) return false;
      if (q.isEmpty) return true;
      return t.title.toLowerCase().contains(q) ||
          (t.description?.toLowerCase().contains(q) ?? false);
    }).toList();
    tasks.sort((a, b) {
      if (a.isArchived != b.isArchived) {
        return a.isArchived ? 1 : -1;
      }
      if (a.isCompleted != b.isCompleted) {
        return a.isCompleted ? 1 : -1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          top: SharedDesignTokens.spacingMd,
          left: SharedDesignTokens.spacingMd,
          right: SharedDesignTokens.spacingMd,
          bottom: MediaQuery.of(context).viewInsets.bottom +
              SharedDesignTokens.spacingMd,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Link Note to Task',
                      style: DaywellTypography.fromToken(
                        SharedDesignTokens.typeTitle,
                        color: semantic.textPrimary,
                      ),
                    ),
                  ),
                  DaywellIconButton(
                    icon: Icons.close,
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
              DaywellSearchField(
                controller: _searchCtrl,
                hintText: 'Search tasks...',
                onChanged: (val) => setState(() => _query = val),
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
              Expanded(
                child: tasks.isEmpty
                    ? DaywellEmptyState(
                        icon: Icons.check_circle_outline,
                        message: q.isNotEmpty
                            ? 'No tasks match "$q"'
                            : 'No tasks available to link.',
                      )
                    : ListView.separated(
                        itemCount: tasks.length,
                        separatorBuilder: (_, __) => const SizedBox(
                          height: SharedDesignTokens.spacingXs,
                        ),
                        itemBuilder: (_, index) {
                          final task = tasks[index];
                          return DaywellCard(
                            padding: EdgeInsets.zero,
                            child: ListTile(
                              onTap: () {
                                widget.onSelectTask(task);
                                Navigator.pop(context);
                              },
                              leading: Icon(
                                task.isCompleted
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: colorScheme.primary,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      task.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (task.isArchived) ...[
                                    const SizedBox(
                                      width: SharedDesignTokens.spacingXs,
                                    ),
                                    const DaywellStatusBadge(
                                      label: 'Archived',
                                      tone: DaywellStatusTone.warning,
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                task.description?.trim().isNotEmpty == true
                                    ? task.description!.trim()
                                    : task.status.replaceAll('_', ' '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: semantic.textSecondary),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
