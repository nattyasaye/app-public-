import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/date/shared_date.dart';
import '../../core/shared_foundation.dart';
import '../../core/theme/daywell_theme.dart';
import '../../domain/calendar/calendar_models.dart';
import '../../domain/notes/calendar_notes_helpers.dart';
import '../../domain/notes/note_editor_formatting.dart';
import '../../domain/notes/note_helpers.dart';
import '../../domain/notes/note_links.dart';
import '../../domain/notes/note_markdown.dart';
import '../../domain/notes/note_models.dart';
import '../../domain/notes/project_notes_helpers.dart';
import '../../domain/notes/task_notes_helpers.dart';
import '../../domain/projects/project_models.dart';
import '../../domain/tasks/task_models.dart';
import '../../application/calendar/calendar_controller.dart';
import '../../application/notes/notes_controller.dart';
import '../../application/projects/projects_controller.dart';
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
  String? projectId,
  String? linkedModule,
  String? linkedId,
});

String _formatFolderLabel(String category) {
  return NoteDomainHelpers.formatFolderLabel(category);
}

Future<String?> _showNotesFolderNameDialog(
  BuildContext context,
  NotesController controller, {
  String? oldName,
}) async {
  final isRename = oldName != null;
  final ctrl = TextEditingController(
    text: isRename ? _formatFolderLabel(oldName) : '',
  );
  String? errorText;
  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isRename ? 'Rename Folder' : 'New Folder'),
          content: SingleChildScrollView(
            child: DaywellTextField(
              controller: ctrl,
              label: 'Folder name',
              hintText: 'e.g. Research',
              errorText: errorText,
              autofocus: true,
              onChanged: (_) {
                if (errorText != null) {
                  setDialogState(() => errorText = null);
                }
              },
            ),
          ),
          actions: [
            DaywellButton(
              label: 'Cancel',
              variant: DaywellButtonVariant.text,
              size: DaywellButtonSize.compact,
              onPressed: () => Navigator.pop(ctx),
            ),
            DaywellButton(
              label: isRename ? 'Rename' : 'Create',
              variant: DaywellButtonVariant.primary,
              size: DaywellButtonSize.compact,
              onPressed: () async {
                if (isRename) {
                  final res = await controller.renameFolder(oldName, ctrl.text);
                  if (!ctx.mounted) return;
                  if (!res.ok || res.folder == null) {
                    setDialogState(
                      () => errorText =
                          res.errorMessage ?? 'Could not rename folder.',
                    );
                    return;
                  }
                  Navigator.pop(ctx, res.folder);
                } else {
                  final res = await controller.createFolder(ctrl.text);
                  if (!ctx.mounted) return;
                  if (!res.ok || res.folder == null) {
                    setDialogState(
                      () => errorText =
                          res.errorMessage ?? 'Could not create folder.',
                    );
                    return;
                  }
                  Navigator.pop(ctx, res.folder);
                }
              },
            ),
          ],
        ),
      ),
    );
  } finally {
    ctrl.dispose();
  }
}

class NotesView extends StatefulWidget {
  final AppStateManager? state;
  final NotesController? controller;
  final TasksController? tasksController;
  final ProjectsController? projectsController;
  final CalendarController? calendarController;
  final ({String noteId, int nonce})? requestedNoteFocus;
  final void Function(String taskId)? onOpenTask;
  final void Function(CalendarEventEntity event)? onOpenCalendarEvent;
  final void Function(Future<bool> Function()? flushHandler)?
      onRegisterPendingSaveFlush;

  const NotesView({
    super.key,
    this.state,
    this.controller,
    this.tasksController,
    this.projectsController,
    this.calendarController,
    this.requestedNoteFocus,
    this.onOpenTask,
    this.onOpenCalendarEvent,
    this.onRegisterPendingSaveFlush,
  }) : assert(state != null || controller != null,
            'Either state or controller must be provided to NotesView');

  NotesController get effectiveController =>
      controller ?? state!.notesController;

  TasksController? get effectiveTasksController =>
      tasksController ?? state?.tasksController;

  ProjectsController? get effectiveProjectsController =>
      projectsController ?? state?.projectsController;

  CalendarController? get effectiveCalendarController =>
      calendarController ?? state?.calendarController;

  @override
  State<NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<NotesView> {
  late TextEditingController _searchController;
  int? _lastHandledNoteFocusNonce;
  String? _selectedNoteId;
  bool _isNewDraftSelected = false;
  String _newDraftInitialCategory = 'reflection';
  bool _detailPreviewMode = false;
  int _editorSessionToken = 0;
  int _selectionSwitchSeq = 0;
  Future<void> _selectionOperationQueue = Future<void>.value();
  bool _isWideLayout = false;
  final GlobalKey<_NoteEditorSurfaceState> _editorSurfaceKey =
      GlobalKey<_NoteEditorSurfaceState>();
  GlobalKey<_NoteEditorSurfaceState>? _activeNarrowEditorKey;
  ModalRoute<void>? _activeNarrowRoute;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.effectiveController.state.searchQuery,
    );
    widget.onRegisterPendingSaveFlush?.call(_flushActiveEditorEdits);
    _scheduleNoteFocusIfNeeded();
  }

  @override
  void didUpdateWidget(covariant NotesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onRegisterPendingSaveFlush !=
        oldWidget.onRegisterPendingSaveFlush) {
      oldWidget.onRegisterPendingSaveFlush?.call(null);
      widget.onRegisterPendingSaveFlush?.call(_flushActiveEditorEdits);
    }
    _scheduleNoteFocusIfNeeded();
  }

  Future<bool> _flushActiveEditorEdits() async {
    var wideOk = true;
    final wideSurface = _editorSurfaceKey.currentState;
    if (wideSurface != null) {
      wideOk = await wideSurface.flushPendingSaves();
    }
    var narrowOk = true;
    final narrowSurface = _activeNarrowEditorKey?.currentState;
    if (narrowSurface != null && !identical(narrowSurface, wideSurface)) {
      narrowOk = await narrowSurface.flushPendingSaves();
    }
    return wideOk && narrowOk;
  }

  void _alignFiltersForNote(NoteEntity note) {
    final controller = widget.effectiveController;
    final state = controller.state;
    if (note.isArchived) {
      if (state.sectionFilter != 'archive') {
        controller.setSectionFilter('archive');
      }
    } else {
      final excludedBySection = state.sectionFilter == 'archive' ||
          state.sectionFilter == 'trash' ||
          (state.sectionFilter == 'pinned' && !note.isPinned) ||
          (state.sectionFilter == 'favorites' && !note.isFavorite);
      if (excludedBySection) {
        controller.setSectionFilter('active');
      }
    }

    if (state.categoryFilter != 'all' &&
        note.category !=
            NoteDomainHelpers.normalizeFlutterCategory(state.categoryFilter)) {
      controller.setCategoryFilter('all');
    }

    if (!NoteDomainHelpers.matchesTagFilter(note.tags, state.tagFilter)) {
      controller.setTagFilter('all');
    }

    if (!NoteDomainHelpers.matchesDateFilter(
      note,
      NoteDomainHelpers.parseDateFilterMode(state.dateFilter),
    )) {
      controller.setDateFilter('all');
    }

    final projectTitle = note.projectId != null
        ? ProjectNotesHelper.findLinkedProject(
            note,
            widget.effectiveProjectsController?.state.projects ??
                const <ProjectEntity>[],
          )?.title
        : null;
    final linkedEventTitle = note.isLinkedToCalendarEvent
        ? CalendarNotesHelper.findLinkedEvent(
            note,
            widget.effectiveCalendarController?.state.events ??
                const <CalendarEventEntity>[],
          )?.title
        : null;
    if (state.searchQuery.trim().isNotEmpty &&
        !NoteDomainHelpers.matchesNoteSearchQuery(
          title: note.title,
          content: note.content,
          category: note.category,
          tags: note.tags,
          rawQuery: state.searchQuery,
          projectTitle: projectTitle,
          linkedEventTitle: linkedEventTitle,
        )) {
      _searchController.clear();
      controller.setSearchQuery('');
    }
  }

  Future<void> _handleRequestedNoteFocus(String noteId) async {
    if (!mounted) return;
    final note = widget.effectiveController.state.findById(noteId);
    if (note == null) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This note is no longer available.'),
        ),
      );
      return;
    }
    if (note.isTrashed) {
      _promptRestoreTrashedNote(note);
      return;
    }

    if (_isWideLayout) {
      if (!_isNewDraftSelected && _selectedNoteId == note.id) {
        _alignFiltersForNote(note);
        return;
      }
      final wideSurface = _editorSurfaceKey.currentState;
      if (wideSurface != null) {
        final flushed = await wideSurface.flushPendingSaves();
        if (!mounted) return;
        if (!flushed) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not save current note changes. Retry before switching notes.',
              ),
            ),
          );
          return;
        }
      }
      final latest = widget.effectiveController.state.findById(note.id);
      if (latest == null) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This note is no longer available.'),
          ),
        );
        return;
      }
      if (latest.isTrashed) {
        _promptRestoreTrashedNote(latest);
        return;
      }
      _alignFiltersForNote(latest);
      await _selectWideDetailTarget(existingNote: latest);
      return;
    }

    final narrowRoute = _activeNarrowRoute;
    final narrowSurface = _activeNarrowEditorKey?.currentState;
    if (narrowRoute != null &&
        narrowRoute.isActive &&
        narrowSurface != null) {
      if (narrowSurface.noteId == note.id) {
        _alignFiltersForNote(note);
        return;
      }
      final flushed = await narrowSurface.flushPendingSaves();
      if (!mounted) return;
      if (!flushed) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save current note changes. Retry before switching notes.',
            ),
          ),
        );
        return;
      }
    }

    final latest = widget.effectiveController.state.findById(note.id);
    if (latest == null) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This note is no longer available.'),
        ),
      );
      return;
    }
    if (latest.isTrashed) {
      _promptRestoreTrashedNote(latest);
      return;
    }
    _alignFiltersForNote(latest);
    _openNarrowNoteEditor(latest, replaceActiveRoute: true);
  }

  void _scheduleNoteFocusIfNeeded() {
    final focus = widget.requestedNoteFocus;
    if (focus == null || focus.nonce == _lastHandledNoteFocusNonce) return;
    _lastHandledNoteFocusNonce = focus.nonce;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_handleRequestedNoteFocus(focus.noteId));
    });
  }

  @override
  void dispose() {
    widget.onRegisterPendingSaveFlush?.call(null);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _selectWideDetailTarget({
    NoteEntity? existingNote,
    bool createNew = false,
    bool preservePreviewMode = false,
    bool clearSelection = false,
  }) {
    final seq = ++_selectionSwitchSeq;
    final completer = Completer<void>();
    final previousOp = _selectionOperationQueue;
    _selectionOperationQueue = completer.future;

    () async {
      try {
        await previousOp.catchError((Object _) {});
        if (!mounted || seq != _selectionSwitchSeq) return;

        if (existingNote != null && existingNote.isTrashed) {
          _promptRestoreTrashedNote(existingNote);
          return;
        }

        if (!clearSelection &&
            !createNew &&
            existingNote != null &&
            !_isNewDraftSelected &&
            _selectedNoteId == existingNote.id) {
          return;
        }

        final currentSurface = _editorSurfaceKey.currentState;
        if (currentSurface != null) {
          if (createNew &&
              _isNewDraftSelected &&
              currentSurface.noteId == null &&
              currentSurface.isNewBlankDraft) {
            return;
          }

          final flushed = await currentSurface.flushPendingSaves();
          if (!mounted || seq != _selectionSwitchSeq) return;
          if (!flushed) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Could not save current note changes. Retry before switching notes.',
                ),
              ),
            );
            return;
          }
        }

        if (!mounted || seq != _selectionSwitchSeq) return;

        if (clearSelection) {
          setState(() {
            _selectedNoteId = null;
            _isNewDraftSelected = false;
            _detailPreviewMode = false;
            _editorSessionToken++;
          });
          return;
        }

        if (createNew) {
          final activeCategoryFilter =
              widget.effectiveController.state.categoryFilter;
          final defaultNewCategory =
              activeCategoryFilter != 'all' ? activeCategoryFilter : 'reflection';
          setState(() {
            _selectedNoteId = null;
            _isNewDraftSelected = true;
            _newDraftInitialCategory = defaultNewCategory;
            _detailPreviewMode = false;
            _editorSessionToken++;
          });
          return;
        }

        if (existingNote == null) {
          setState(() {
            _selectedNoteId = null;
            _isNewDraftSelected = false;
            _detailPreviewMode = false;
            _editorSessionToken++;
          });
          return;
        }

        final fresh =
            widget.effectiveController.state.findById(existingNote.id) ??
                existingNote;
        if (fresh.isTrashed) {
          _promptRestoreTrashedNote(fresh);
          return;
        }

        setState(() {
          _selectedNoteId = fresh.id;
          _isNewDraftSelected = false;
          _detailPreviewMode = preservePreviewMode
              ? (currentSurface?.isPreviewMode ?? false)
              : false;
          _editorSessionToken++;
        });
      } finally {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }();

    return completer.future;
  }

  void _openNarrowNoteEditor(
    NoteEntity? existingNote, {
    bool replaceActiveRoute = false,
  }) {
    final activeCategoryFilter = widget.effectiveController.state.categoryFilter;
    final defaultNewCategory =
        activeCategoryFilter != 'all' ? activeCategoryFilter : 'reflection';
    final surfaceKey = GlobalKey<_NoteEditorSurfaceState>();
    final route = MaterialPageRoute<void>(
      builder: (_) => _NoteEditorScreen(
        controller: widget.effectiveController,
        tasksController: widget.effectiveTasksController,
        projectsController: widget.effectiveProjectsController,
        calendarController: widget.effectiveCalendarController,
        onOpenTask: widget.onOpenTask,
        onOpenCalendarEvent: widget.onOpenCalendarEvent,
        existingNote: existingNote,
        initialCategory: defaultNewCategory,
        editorSurfaceKey: surfaceKey,
      ),
    );
    final previousRoute = _activeNarrowRoute;
    _activeNarrowEditorKey = surfaceKey;
    _activeNarrowRoute = route;

    final navigator = Navigator.of(context);
    final Future<void> routeFuture = (replaceActiveRoute &&
            previousRoute != null &&
            previousRoute.isCurrent)
        ? navigator.pushReplacement<void, void>(route)
        : navigator.push<void>(route);

    unawaited(
      routeFuture.whenComplete(() {
        if (identical(_activeNarrowRoute, route)) {
          _activeNarrowRoute = null;
          _activeNarrowEditorKey = null;
        }
      }),
    );
  }

  void _openNoteEditor([NoteEntity? existingNote]) {
    if (existingNote != null && existingNote.isTrashed) {
      return;
    }
    if (_isWideLayout) {
      unawaited(
        _selectWideDetailTarget(
          existingNote: existingNote,
          createNew: existingNote == null,
        ),
      );
      return;
    }
    _openNarrowNoteEditor(existingNote);
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
        if (_selectedNoteId == note.id) {
          setState(() {
            _selectedNoteId = null;
            _isNewDraftSelected = false;
            _editorSessionToken++;
          });
        }
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
        if (_selectedNoteId != null) {
          final current = controller.state.findById(_selectedNoteId!);
          if (current == null || current.isTrashed) {
            setState(() {
              _selectedNoteId = null;
              _isNewDraftSelected = false;
              _editorSessionToken++;
            });
          }
        }
        unawaited(controller.emptyTrash());
      }),
    );
  }

  Future<String?> _showFolderNameDialog(
    NotesController controller, {
    String? oldName,
  }) =>
      _showNotesFolderNameDialog(context, controller, oldName: oldName);

  void _handleCreateFolderFromList(NotesController controller) {
    unawaited(() async {
      final created = await _showFolderNameDialog(controller);
      if (created == null || !mounted) return;
      controller.setCategoryFilter(created);
      if (controller.state.sectionFilter == 'trash' ||
          controller.state.sectionFilter == 'archive') {
        controller.setSectionFilter('active');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Created folder "${_formatFolderLabel(created)}"'),
        ),
      );
    }());
  }

  void _handleRenameFolderFromList(
    NotesController controller,
    String folderName,
  ) {
    unawaited(() async {
      final renamed = await _showFolderNameDialog(
        controller,
        oldName: folderName,
      );
      if (renamed == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Renamed folder to "${_formatFolderLabel(renamed)}"'),
        ),
      );
    }());
  }

  void _confirmDeleteFolder(
    NotesController controller,
    String folderName,
    NotesModuleState moduleState,
  ) {
    final normalized = NoteDomainHelpers.normalizeFlutterCategory(folderName);
    final affectedCount = moduleState.notes
        .where((n) => !n.isTrashed && n.category == normalized)
        .length;
    final label = _formatFolderLabel(normalized);
    unawaited(
      DaywellConfirmationDialog.show(
        context,
        title: 'Delete Folder?',
        message: affectedCount > 0
            ? 'Delete "$label"? No notes will be deleted — $affectedCount ${affectedCount == 1 ? 'note' : 'notes'} will move safely to "General".'
            : 'Delete empty folder "$label"?',
        cancelLabel: 'Cancel',
        confirmLabel: 'Delete Folder',
        isDestructive: true,
        icon: Icons.folder_delete_outlined,
      ).then((confirmed) async {
        if (!confirmed || !mounted) return;
        final res = await controller.deleteFolder(
          normalized,
          destinationFolder: 'general',
        );
        if (!mounted) return;
        if (!res.ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.errorMessage ?? 'Could not delete folder.'),
            ),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.movedCount > 0
                  ? 'Deleted "$label" — moved ${res.movedCount} ${res.movedCount == 1 ? 'note' : 'notes'} to General'
                  : 'Deleted folder "$label"',
            ),
          ),
        );
      }),
    );
  }

  void _showMoveNoteFolderDialog(NotesController controller, NoteEntity note) {
    const defaultOrder = ['reflection', 'reference', 'learning', 'general'];
    final extra = controller.state.availableCategories
        .where((c) => !defaultOrder.contains(c))
        .toList()
      ..sort();
    final folders = <String>[
      ...defaultOrder,
      ...extra,
      if (!defaultOrder.contains(note.category) && !extra.contains(note.category))
        note.category,
    ];

    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) {
          final semantic = ctx.daywellColors;
          final colorScheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: const Text('Move to Folder'),
            content: SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final folder in folders)
                      ListTile(
                        leading: Icon(
                          folder == note.category
                              ? Icons.folder_rounded
                              : Icons.folder_outlined,
                          color: folder == note.category
                              ? colorScheme.primary
                              : semantic.textSecondary,
                        ),
                        title: Text(
                          _formatFolderLabel(folder),
                          style: DaywellTypography.body(
                            color: semantic.textPrimary,
                          ).copyWith(
                            fontWeight: folder == note.category
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                        trailing: folder == note.category
                            ? Icon(
                                Icons.check_rounded,
                                color: colorScheme.primary,
                              )
                            : null,
                        onTap: () {
                          Navigator.pop(ctx);
                          unawaited(() async {
                            if (_isWideLayout && _selectedNoteId == note.id) {
                              final ok = await _editorSurfaceKey.currentState
                                      ?.flushPendingSaves() ??
                                  true;
                              if (!ok || !mounted) return;
                            }
                            final res = await controller.moveNoteToFolder(
                              note.id,
                              folder,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  res.saved
                                      ? 'Moved to "${_formatFolderLabel(folder)}"'
                                      : (res.errorMessage ?? 'Could not move note.'),
                                ),
                              ),
                            );
                          }());
                        },
                      ),
                    const Divider(),
                    ListTile(
                      leading: Icon(
                        Icons.create_new_folder_outlined,
                        color: colorScheme.primary,
                      ),
                      title: Text(
                        'New Folder...',
                        style: DaywellTypography.body(
                          color: colorScheme.primary,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        unawaited(() async {
                          final created = await _showFolderNameDialog(controller);
                          if (created == null || !mounted) return;
                          final res = await controller.moveNoteToFolder(
                            note.id,
                            created,
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                res.saved
                                    ? 'Moved to "${_formatFolderLabel(created)}"'
                                    : (res.errorMessage ?? 'Could not move note.'),
                              ),
                            ),
                          );
                        }());
                      },
                    ),
                  ],
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

  Widget _buildEmptyState(
    BuildContext context,
    NotesController controller,
    NotesModuleState moduleState,
  ) {
    final String query = moduleState.searchQuery;
    final String section = moduleState.sectionFilter;
    final String category = moduleState.categoryFilter;
    final String tagFilter = moduleState.tagFilter;
    final String dateFilter = moduleState.dateFilter;

    if (query.isNotEmpty ||
        tagFilter != 'all' ||
        dateFilter != 'all' ||
        (category != 'all' && section != 'active')) {
      return DaywellEmptyState(
        icon: Icons.search_off_rounded,
        message: query.isNotEmpty
            ? 'No notes match "$query"'
            : 'No notes match your active filters',
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

  String _dateFilterDisplayLabel(String dateFilter) {
    switch (dateFilter) {
      case 'updated_7d':
        return 'Updated 7d';
      case 'updated_30d':
        return 'Updated 30d';
      case 'created_7d':
        return 'Created 7d';
      case 'created_30d':
        return 'Created 30d';
      default:
        return 'Any Date';
    }
  }

  String _sortDisplayLabel(String sortBy) {
    switch (sortBy) {
      case 'created':
        return 'Recently Created';
      case 'alpha':
        return 'A–Z';
      case 'oldest':
        return 'Oldest First';
      default:
        return 'Recently Modified';
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.effectiveController;
    final tasksController = widget.effectiveTasksController;
    final projectsController = widget.effectiveProjectsController;
    final calendarController = widget.effectiveCalendarController;
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
        if (projectsController != null) projectsController,
        if (calendarController != null) calendarController,
      ]),
      builder: (context, _) {
        final moduleState = controller.state;
        final projectTitlesById = projectsController != null
            ? ProjectNotesHelper.buildProjectTitlesById(
                projectsController.state.projects,
              )
            : const <String, String>{};
        final eventTitlesById = calendarController != null
            ? CalendarNotesHelper.buildEventTitlesById(
                calendarController.state.events,
              )
            : const <String, String>{};
        final notes = moduleState.filterNotes(
          projectTitlesById: projectTitlesById,
          eventTitlesById: eventTitlesById,
        );
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
        final availableTags = <String>[...moduleState.availableTags];
        if (moduleState.tagFilter != 'all' &&
            !availableTags.any(
              (t) => t.toLowerCase() == moduleState.tagFilter.toLowerCase(),
            )) {
          availableTags.add(moduleState.tagFilter);
        }
        final hasError = moduleState.errorMessage != null &&
            moduleState.errorMessage!.trim().isNotEmpty;
        final hasActiveFilters = moduleState.searchQuery.isNotEmpty ||
            moduleState.categoryFilter != 'all' ||
            moduleState.tagFilter != 'all' ||
            moduleState.dateFilter != 'all' ||
            moduleState.sectionFilter != 'active' ||
            moduleState.sortBy != 'recent';
        final String? activeSummary = hasActiveFilters
            ? '${notes.length} ${notes.length == 1 ? 'note' : 'notes'} · ${_sectionDisplayLabel(moduleState.sectionFilter)}'
                '${moduleState.categoryFilter != 'all' ? ' · ${_formatFolderLabel(moduleState.categoryFilter)}' : ''}'
                '${moduleState.tagFilter != 'all' ? ' · #${moduleState.tagFilter}' : ''}'
                '${moduleState.dateFilter != 'all' ? ' · ${_dateFilterDisplayLabel(moduleState.dateFilter)}' : ''}'
                '${moduleState.sortBy != 'recent' ? ' · ${_sortDisplayLabel(moduleState.sortBy)}' : ''}'
            : null;
        final bool canManageSelectedFolder =
            moduleState.categoryFilter != 'all' &&
            !NoteEntity.defaultCategories.contains(moduleState.categoryFilter);
        final NoteEntity? selectedWideNote = _selectedNoteId != null
            ? moduleState.findById(_selectedNoteId!)
            : null;
        if (_selectedNoteId != null &&
            (selectedWideNote == null || selectedWideNote.isTrashed)) {
          final hasPendingInSurface =
              _editorSurfaceKey.currentState?.hasPendingChanges ?? false;
          if (!hasPendingInSurface) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _selectedNoteId == null) return;
              final latest = controller.state.findById(_selectedNoteId!);
              if (latest == null || latest.isTrashed) {
                setState(() {
                  _selectedNoteId = null;
                  _isNewDraftSelected = false;
                });
              }
            });
          }
        }

        Widget buildMasterColumn({required bool isWide}) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isWide)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SharedDesignTokens.spacingMd,
                    SharedDesignTokens.spacingCompact,
                    SharedDesignTokens.spacingMd,
                    0,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${notes.length} ${notes.length == 1 ? 'note' : 'notes'} · ${_sectionDisplayLabel(moduleState.sectionFilter)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DaywellTypography.label(
                            color: semantic.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: SharedDesignTokens.spacingSm),
                      DaywellButton(
                        label: 'New Note',
                        leadingIcon: Icons.add,
                        variant: DaywellButtonVariant.primary,
                        size: DaywellButtonSize.compact,
                        onPressed: () => _openNoteEditor(),
                      ),
                    ],
                  ),
                ),
              DaywellSearchFilterBar(
                searchController: _searchController,
                searchHintText: 'Search notes, tags, or folders...',
                searchSemanticLabel: 'Search notes, tags, or folders',
                onSearchChanged: (value) {
                  final wideSurface = _editorSurfaceKey.currentState;
                  if (_isWideLayout &&
                      wideSurface != null &&
                      wideSurface.hasPendingChanges &&
                      !wideSurface.isNewBlankDraft) {
                    unawaited(wideSurface.flushPendingSaves());
                  }
                  controller.setSearchQuery(value);
                },
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
                        onSelected: (_) {
                          final wideSurface = _editorSurfaceKey.currentState;
                          if (_isWideLayout &&
                              wideSurface != null &&
                              wideSurface.hasPendingChanges &&
                              !wideSurface.isNewBlankDraft) {
                            unawaited(wideSurface.flushPendingSaves());
                          }
                          controller.setSectionFilter(sec.$1);
                        },
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
                  SharedDesignTokens.spacingXs,
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
                        onSelected: (_) => controller.setCategoryFilter(
                          moduleState.categoryFilter == cat && cat != 'all'
                              ? 'all'
                              : cat,
                        ),
                      ),
                      const SizedBox(width: SharedDesignTokens.spacingSm),
                    ],
                    ActionChip(
                      avatar: Icon(
                        Icons.create_new_folder_outlined,
                        size: DaywellIconSize.xs,
                        color: colorScheme.primary,
                      ),
                      label: Text(
                        'New Folder',
                        style: DaywellTypography.caption(
                          color: colorScheme.primary,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                      onPressed: () =>
                          _handleCreateFolderFromList(controller),
                    ),
                  ],
                ),
              ),
              if (canManageSelectedFolder)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SharedDesignTokens.spacingMd,
                    0,
                    SharedDesignTokens.spacingMd,
                    SharedDesignTokens.spacingXs,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SharedDesignTokens.spacingCompact,
                      vertical: SharedDesignTokens.spacingXs,
                    ),
                    decoration: BoxDecoration(
                      color: semantic.surfaceSubtle,
                      borderRadius: BorderRadius.circular(
                        SharedDesignTokens.radiusMd,
                      ),
                      border: Border.all(color: semantic.border),
                    ),
                    child: Wrap(
                      spacing: SharedDesignTokens.spacingSm,
                      runSpacing: SharedDesignTokens.spacingXs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
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
                            Text(
                              'Folder: ${_formatFolderLabel(moduleState.categoryFilter)}',
                              style: DaywellTypography.label(
                                color: semantic.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        DaywellButton(
                          label: 'Rename',
                          variant: DaywellButtonVariant.outlined,
                          size: DaywellButtonSize.compact,
                          onPressed: () => _handleRenameFolderFromList(
                            controller,
                            moduleState.categoryFilter,
                          ),
                        ),
                        DaywellButton(
                          label: 'Delete Folder',
                          variant: DaywellButtonVariant.text,
                          size: DaywellButtonSize.compact,
                          onPressed: () => _confirmDeleteFolder(
                            controller,
                            moduleState.categoryFilter,
                            moduleState,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (availableTags.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(
                    SharedDesignTokens.spacingMd,
                    0,
                    SharedDesignTokens.spacingMd,
                    SharedDesignTokens.spacingXs,
                  ),
                  child: Row(
                    children: [
                      FilterChip(
                        label: Text(
                          'All Tags',
                          style: DaywellTypography.caption(
                            color: moduleState.tagFilter == 'all'
                                ? colorScheme.onPrimaryContainer
                                : semantic.textSecondary,
                          ),
                        ),
                        selected: moduleState.tagFilter == 'all',
                        onSelected: (_) => controller.setTagFilter('all'),
                      ),
                      const SizedBox(width: SharedDesignTokens.spacingSm),
                      for (final tag in availableTags) ...[
                        FilterChip(
                          label: Text(
                            '#$tag',
                            style: DaywellTypography.caption(
                              color: moduleState.tagFilter.toLowerCase() ==
                                      tag.toLowerCase()
                                  ? colorScheme.onPrimaryContainer
                                  : semantic.textSecondary,
                            ),
                          ),
                          selected: moduleState.tagFilter.toLowerCase() ==
                              tag.toLowerCase(),
                          onSelected: (_) => controller.setTagFilter(
                            moduleState.tagFilter.toLowerCase() ==
                                    tag.toLowerCase()
                                ? 'all'
                                : tag,
                          ),
                        ),
                        const SizedBox(
                          width: SharedDesignTokens.spacingSm,
                        ),
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
                    for (final opt in const [
                      ('all', 'Any Date'),
                      ('updated_7d', 'Updated 7d'),
                      ('updated_30d', 'Updated 30d'),
                      ('created_7d', 'Created 7d'),
                      ('created_30d', 'Created 30d'),
                    ]) ...[
                      ChoiceChip(
                        label: Text(
                          opt.$2,
                          style: DaywellTypography.caption(
                            color: moduleState.dateFilter == opt.$1
                                ? colorScheme.onPrimaryContainer
                                : semantic.textSecondary,
                          ),
                        ),
                        selected: moduleState.dateFilter == opt.$1,
                        onSelected: (_) =>
                            controller.setDateFilter(opt.$1),
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
                            builder: (context, listConstraints) {
                              final bottomPad = isWide
                                  ? SharedDesignTokens.spacingMd
                                  : 88.0;
                              if (moduleState.isGridView) {
                                final int crossAxisCount =
                                    listConstraints.maxWidth >=
                                            SharedDesignTokens
                                                .breakpointExpanded
                                        ? 3
                                        : listConstraints.maxWidth < 400
                                            ? 1
                                            : 2;
                                final double cardExtent = (256.0 *
                                        textScale.clamp(1.0, 2.0))
                                    .ceilToDouble();
                                return GridView.builder(
                                  padding: EdgeInsets.fromLTRB(
                                    SharedDesignTokens.spacingMd,
                                    SharedDesignTokens.spacingCompact,
                                    SharedDesignTokens.spacingMd,
                                    bottomPad,
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
                                    isSelected: isWide &&
                                        !_isNewDraftSelected &&
                                        _selectedNoteId == notes[i].id,
                                  ),
                                );
                              }

                              return ListView.builder(
                                padding: EdgeInsets.fromLTRB(
                                  SharedDesignTokens.spacingMd,
                                  SharedDesignTokens.spacingCompact,
                                  SharedDesignTokens.spacingMd,
                                  bottomPad,
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
                                        isSelected: isWide &&
                                            !_isNewDraftSelected &&
                                            _selectedNoteId == notes[i].id,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          );
        }

        return LayoutBuilder(
          builder: (context, viewportConstraints) {
            final bool isWide = viewportConstraints.maxWidth >=
                SharedDesignTokens.breakpointExpanded;
            _isWideLayout = isWide;

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
                        ('created', 'Recently Created'),
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
              floatingActionButton: isWide
                  ? null
                  : FloatingActionButton.extended(
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
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: (viewportConstraints.maxWidth * 0.36)
                                  .clamp(320.0, 380.0)
                                  .toDouble(),
                              child: buildMasterColumn(isWide: true),
                            ),
                            VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: semantic.divider,
                            ),
                            Expanded(
                              child: _buildWideDetailPane(
                                context,
                                controller,
                                tasksController,
                                selectedWideNote,
                                notes.isEmpty,
                              ),
                            ),
                          ],
                        )
                      : buildMasterColumn(isWide: false),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWideDetailPane(
    BuildContext context,
    NotesController controller,
    TasksController? tasksController,
    NoteEntity? selectedNote,
    bool isFilteredListEmpty,
  ) {
    final activeSelected =
        selectedNote != null && !selectedNote.isTrashed ? selectedNote : null;
    if (activeSelected == null && !_isNewDraftSelected) {
      return DaywellEmptyState(
        icon: Icons.note_alt_outlined,
        message: 'Select a note to read or edit',
        subtitle: isFilteredListEmpty
            ? 'Create a new note or adjust filters on the left.'
            : 'Choose a note from the list on the left, or start a new note.',
        actionLabel: 'Create Note',
        onActionPressed: () => _openNoteEditor(),
      );
    }

    return _NoteEditorSurface(
      key: _editorSurfaceKey,
      controller: controller,
      tasksController: tasksController,
      projectsController: widget.effectiveProjectsController,
      calendarController: widget.effectiveCalendarController,
      onOpenTask: widget.onOpenTask,
      onOpenCalendarEvent: widget.onOpenCalendarEvent,
      existingNote: activeSelected,
      initialPreviewMode: _detailPreviewMode,
      initialCategory: _newDraftInitialCategory,
      isEmbedded: true,
      editorSessionToken: _editorSessionToken,
      onNoteCreated: (NoteEntity created) {
        if (!mounted) return;
        setState(() {
          _selectedNoteId = created.id;
          _isNewDraftSelected = false;
        });
      },
      onSelectInternalNote: (NoteEntity targetNote) => _selectWideDetailTarget(
        existingNote: targetNote,
        preservePreviewMode: true,
      ),
      onCloseEmbedded: () {
        unawaited(_selectWideDetailTarget(clearSelection: true));
      },
      onNoteArchivedToggled: (String noteId) {
        if (!mounted) return;
        final updated = controller.state.findById(noteId);
        final section = controller.state.sectionFilter;
        final leftSection = updated == null ||
            (section == 'archive' ? !updated.isArchived : updated.isArchived);
        if (leftSection && _selectedNoteId == noteId) {
          setState(() {
            _selectedNoteId = null;
            _isNewDraftSelected = false;
            _editorSessionToken++;
          });
        }
        if (updated != null) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                updated.isArchived
                    ? 'Note moved to archive'
                    : 'Note restored from archive',
              ),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => unawaited(controller.toggleArchive(noteId)),
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      },
      onNoteMovedToTrash: (String noteId) {
        if (!mounted) return;
        if (_selectedNoteId == noteId || _isNewDraftSelected) {
          setState(() {
            _selectedNoteId = null;
            _isNewDraftSelected = false;
            _editorSessionToken++;
          });
        }
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Moved note to Trash'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => unawaited(controller.restoreFromTrash(noteId)),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      },
    );
  }

  Future<void> _handleCardMenuAction(
    NotesController controller,
    NoteEntity note,
    String action,
  ) async {
    if (_isWideLayout && _selectedNoteId == note.id) {
      if (action == 'pin' ||
          action == 'fav' ||
          action == 'duplicate' ||
          action == 'archive' ||
          action == 'trash') {
        final flushed =
            await _editorSurfaceKey.currentState?.flushPendingSaves() ?? true;
        if (!flushed || !mounted) return;
      }
    }

    if (action == 'pin') {
      await controller.togglePin(note.id);
    } else if (action == 'fav') {
      await controller.toggleFavorite(note.id);
    } else if (action == 'move_folder') {
      _showMoveNoteFolderDialog(controller, note);
    } else if (action == 'duplicate') {
      await controller.duplicateNote(note.id);
    } else if (action == 'copy') {
      await Clipboard.setData(
        ClipboardData(
          text: '${note.title}\n\n${note.content}',
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Note copied to clipboard'),
        ),
      );
    } else if (action == 'archive') {
      await controller.toggleArchive(note.id);
      if (!mounted) return;
      if (_selectedNoteId == note.id) {
        final updated = controller.state.findById(note.id);
        final section = controller.state.sectionFilter;
        final leftSection = updated == null ||
            (section == 'archive' ? !updated.isArchived : updated.isArchived);
        if (leftSection) {
          setState(() {
            _selectedNoteId = null;
            _isNewDraftSelected = false;
            _editorSessionToken++;
          });
        }
      }
    } else if (action == 'trash') {
      if (note.isTrashed) {
        await controller.restoreFromTrash(note.id);
      } else {
        if (_selectedNoteId == note.id) {
          setState(() {
            _selectedNoteId = null;
            _isNewDraftSelected = false;
            _editorSessionToken++;
          });
        }
        await controller.deleteNote(note.id);
      }
    } else if (action == 'delete') {
      _confirmPermanentDelete(note);
    }
  }

  Widget _buildNoteCard(
    NoteEntity note,
    bool isGridView, {
    bool isSelected = false,
  }) {
    final controller = widget.effectiveController;
    final tasksCtrl = widget.effectiveTasksController;
    final projectsCtrl = widget.effectiveProjectsController;
    final calendarCtrl = widget.effectiveCalendarController;
    final linkedTask = tasksCtrl != null
        ? TaskNotesHelper.findLinkedTask(note, tasksCtrl.state.tasks)
        : null;
    final linkedEvent = calendarCtrl != null
        ? CalendarNotesHelper.findLinkedEvent(note, calendarCtrl.state.events)
        : null;
    final hasProjectRef =
        ProjectNotesHelper.normalizeProjectId(note.projectId) != null;
    final linkedProject = hasProjectRef && projectsCtrl != null
        ? ProjectNotesHelper.findLinkedProject(note, projectsCtrl.state.projects)
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
      color: isSelected
          ? colorScheme.primaryContainer.withOpacity(0.45)
          : null,
      borderColor: isSelected
          ? colorScheme.primary
          : isPinnedActive
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
                if (isSelected) ...[
                  Icon(
                    Icons.arrow_right_rounded,
                    size: DaywellIconSize.sm,
                    color: colorScheme.primary,
                    semanticLabel: 'Selected note',
                  ),
                  const SizedBox(width: 2),
                ],
                Expanded(
                  child: Text(
                    note.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? colorScheme.primary
                          : semantic.textPrimary,
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
                  onSelected: (action) =>
                      unawaited(_handleCardMenuAction(controller, note, action)),
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
                        value: 'move_folder',
                        child: Text('Move to Folder'),
                      ),
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
                if (note.tags.length > 2)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SharedDesignTokens.spacingXs,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: semantic.surfaceSubtle,
                      borderRadius:
                          BorderRadius.circular(SharedDesignTokens.radiusSm),
                      border: Border.all(color: semantic.border),
                    ),
                    child: Text(
                      '+${note.tags.length - 2}',
                      style: DaywellTypography.caption(
                        color: semantic.textSecondary,
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
            if (note.isLinkedToCalendarEvent) ...[
              const SizedBox(height: SharedDesignTokens.spacingSm),
              InkWell(
                borderRadius:
                    BorderRadius.circular(SharedDesignTokens.radiusSm),
                onTap: linkedEvent != null && widget.onOpenCalendarEvent != null
                    ? () => widget.onOpenCalendarEvent!(linkedEvent)
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SharedDesignTokens.spacingSm,
                    vertical: SharedDesignTokens.spacingXs,
                  ),
                  decoration: BoxDecoration(
                    color: linkedEvent != null
                        ? semantic.transferContainer
                        : semantic.surfaceSubtle,
                    borderRadius:
                        BorderRadius.circular(SharedDesignTokens.radiusSm),
                    border: linkedEvent == null
                        ? Border.all(color: semantic.border)
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.event_note_outlined,
                        size: DaywellIconSize.xs,
                        color: linkedEvent != null
                            ? semantic.transfer
                            : semantic.textMuted,
                      ),
                      const SizedBox(width: SharedDesignTokens.spacingXs),
                      Flexible(
                        child: Text(
                          linkedEvent != null
                              ? 'Event: ${linkedEvent.title}'
                              : 'Linked event unavailable',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DaywellTypography.caption(
                            color: linkedEvent != null
                                ? semantic.onTransferContainer
                                : semantic.textMuted,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (hasProjectRef) ...[
              const SizedBox(height: SharedDesignTokens.spacingSm),
              Wrap(
                spacing: SharedDesignTokens.spacingXs,
                runSpacing: SharedDesignTokens.spacingXs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SharedDesignTokens.spacingSm,
                      vertical: SharedDesignTokens.spacingXs,
                    ),
                    decoration: BoxDecoration(
                      color: semantic.surfaceSubtle,
                      borderRadius:
                          BorderRadius.circular(SharedDesignTokens.radiusSm),
                      border: Border.all(color: semantic.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.layers_outlined,
                          size: DaywellIconSize.xs,
                          color: linkedProject != null
                              ? colorScheme.primary
                              : semantic.textMuted,
                        ),
                        const SizedBox(width: SharedDesignTokens.spacingXs),
                        Flexible(
                          child: Text(
                            linkedProject != null
                                ? 'Project: ${linkedProject.title}'
                                : 'Project unavailable',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DaywellTypography.caption(
                              color: linkedProject != null
                                  ? semantic.textSecondary
                                  : semantic.textMuted,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (linkedProject?.isArchived == true)
                    const DaywellStatusBadge(
                      label: 'Archived',
                      tone: DaywellStatusTone.warning,
                      showIcon: false,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoteEditorScreen extends StatelessWidget {
  final NotesController controller;
  final TasksController? tasksController;
  final ProjectsController? projectsController;
  final CalendarController? calendarController;
  final void Function(String taskId)? onOpenTask;
  final void Function(CalendarEventEntity event)? onOpenCalendarEvent;
  final NoteEntity? existingNote;
  final bool initialPreviewMode;
  final String initialCategory;
  final Key? editorSurfaceKey;

  const _NoteEditorScreen({
    required this.controller,
    this.tasksController,
    this.projectsController,
    this.calendarController,
    this.onOpenTask,
    this.onOpenCalendarEvent,
    required this.existingNote,
    this.initialPreviewMode = false,
    this.initialCategory = 'reflection',
    this.editorSurfaceKey,
  });

  @override
  Widget build(BuildContext context) {
    return _NoteEditorSurface(
      key: editorSurfaceKey,
      controller: controller,
      tasksController: tasksController,
      projectsController: projectsController,
      calendarController: calendarController,
      onOpenTask: onOpenTask,
      onOpenCalendarEvent: onOpenCalendarEvent,
      existingNote: existingNote,
      initialPreviewMode: initialPreviewMode,
      initialCategory: initialCategory,
      isEmbedded: false,
    );
  }
}

class _NoteEditorSurface extends StatefulWidget {
  final NotesController controller;
  final TasksController? tasksController;
  final ProjectsController? projectsController;
  final CalendarController? calendarController;
  final void Function(String taskId)? onOpenTask;
  final void Function(CalendarEventEntity event)? onOpenCalendarEvent;
  final NoteEntity? existingNote;
  final bool initialPreviewMode;
  final String initialCategory;
  final bool isEmbedded;
  final int editorSessionToken;
  final void Function(NoteEntity createdNote)? onNoteCreated;
  final Future<void> Function(NoteEntity targetNote)? onSelectInternalNote;
  final VoidCallback? onCloseEmbedded;
  final void Function(String noteId)? onNoteArchivedToggled;
  final void Function(String noteId)? onNoteMovedToTrash;

  const _NoteEditorSurface({
    super.key,
    required this.controller,
    this.tasksController,
    this.projectsController,
    this.calendarController,
    this.onOpenTask,
    this.onOpenCalendarEvent,
    required this.existingNote,
    this.initialPreviewMode = false,
    this.initialCategory = 'reflection',
    this.isEmbedded = false,
    this.editorSessionToken = 0,
    this.onNoteCreated,
    this.onSelectInternalNote,
    this.onCloseEmbedded,
    this.onNoteArchivedToggled,
    this.onNoteMovedToTrash,
  });

  @override
  State<_NoteEditorSurface> createState() => _NoteEditorSurfaceState();
}

class _NoteEditorSurfaceState extends State<_NoteEditorSurface> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingValue _previousContentValue;
  bool _isApplyingProgrammaticContentEdit = false;
  late String _category;
  late List<String> _tags;
  String? _noteId;
  String? _projectId;
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

  String? get noteId => _noteId;

  bool get isPreviewMode => _isPreviewMode;

  bool get isNewBlankDraft =>
      _noteId == null &&
      _titleController.text.trim().isEmpty &&
      _contentController.text.trim().isEmpty &&
      _tags.isEmpty;

  bool get hasPendingChanges => _hasPendingChanges;

  bool get _hasPendingChanges =>
      _editRevision > _savedRevision || _saveErrorMessage != null;

  Future<bool> flushPendingSaves() => _flushPendingSaves();

  NoteChecklistLineStatus? _resolveActiveWriteChecklist(
    TextEditingValue value,
  ) {
    final sel = value.selection;
    final start = sel.isValid && sel.start >= 0 ? sel.start : value.text.length;
    final end = sel.isValid && sel.end >= 0 ? sel.end : start;
    return NoteMarkdownParser.getChecklistAtSelection(value.text, start, end);
  }

  void _loadFromWidget() {
    _autosaveTimer?.cancel();
    _isPreviewMode = widget.initialPreviewMode;
    _noteId = widget.existingNote?.id;
    final nextTitle = widget.existingNote?.title ?? '';
    final nextContent = widget.existingNote?.content ?? '';
    _isApplyingProgrammaticContentEdit = true;
    _titleController.value = TextEditingValue(
      text: nextTitle,
      selection: TextSelection.collapsed(offset: nextTitle.length),
    );
    _contentController.value = TextEditingValue(
      text: nextContent,
      selection: TextSelection.collapsed(offset: nextContent.length),
    );
    _previousContentValue = _contentController.value;
    _activeWriteChecklist =
        _resolveActiveWriteChecklist(_contentController.value);
    _isApplyingProgrammaticContentEdit = false;

    _category = widget.existingNote != null
        ? NoteDomainHelpers.normalizeFlutterCategory(
            widget.existingNote!.category,
          )
        : NoteDomainHelpers.normalizeFlutterCategory(widget.initialCategory);
    _tags = NoteDomainHelpers.normalizeTags(widget.existingNote?.tags ?? const [])
        .toList();
    _projectId = ProjectNotesHelper.normalizeProjectId(
      widget.existingNote?.projectId,
    );
    _linkedModule = widget.existingNote?.linkedModule;
    _linkedId = widget.existingNote?.linkedId;
    _saveStatus = 'Saved';
    _saveErrorMessage = null;
    _editRevision = 0;
    _savedRevision = 0;
    _allowDiscardOnNextPop = false;
    _isWriteBacklinksExpanded = false;
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
        : NoteDomainHelpers.normalizeFlutterCategory(widget.initialCategory);
    _tags = NoteDomainHelpers.normalizeTags(widget.existingNote?.tags ?? const [])
        .toList();
    _projectId = ProjectNotesHelper.normalizeProjectId(
      widget.existingNote?.projectId,
    );
    _linkedModule = widget.existingNote?.linkedModule;
    _linkedId = widget.existingNote?.linkedId;
  }

  @override
  void didUpdateWidget(covariant _NoteEditorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editorSessionToken != oldWidget.editorSessionToken ||
        (widget.isEmbedded &&
            widget.existingNote?.id != oldWidget.existingNote?.id &&
            widget.existingNote?.id != _noteId)) {
      _loadFromWidget();
      return;
    }

    if (widget.existingNote != null &&
        oldWidget.existingNote != null &&
        widget.existingNote!.id == _noteId &&
        !_hasPendingChanges) {
      if (widget.existingNote!.category != oldWidget.existingNote!.category) {
        _category = NoteDomainHelpers.normalizeFlutterCategory(
          widget.existingNote!.category,
        );
      }
      if (widget.existingNote!.projectId != oldWidget.existingNote!.projectId) {
        _projectId = ProjectNotesHelper.normalizeProjectId(
          widget.existingNote!.projectId,
        );
      }
      if (widget.existingNote!.linkedModule !=
              oldWidget.existingNote!.linkedModule ||
          widget.existingNote!.linkedId != oldWidget.existingNote!.linkedId) {
        _linkedModule = widget.existingNote!.linkedModule;
        _linkedId = widget.existingNote!.linkedId;
      }
    }
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
      projectId: _projectId,
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
        projectId: snapshot.projectId,
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
      if (!fromDispose) {
        widget.onNoteCreated?.call(persisted);
      }
    } else {
      final result = await widget.controller.updateNote(
        id: _noteId!,
        title: persistTitle,
        content: snapshot.content,
        category: snapshot.category,
        tags: snapshot.tags,
        projectId: snapshot.projectId,
        clearProjectId: snapshot.projectId == null,
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

  Future<void> _handleEmbeddedToggleArchive() async {
    final ok = await _flushPendingSaves();
    if (!ok || _noteId == null || !mounted || _isDisposed) return;
    final id = _noteId!;
    await widget.controller.toggleArchive(id);
    if (!mounted || _isDisposed) return;
    widget.onNoteArchivedToggled?.call(id);
  }

  Future<void> _handleEmbeddedMoveToTrash() async {
    final ok = await _flushPendingSaves();
    if (!ok || _noteId == null || !mounted || _isDisposed) return;
    final id = _noteId!;
    await widget.controller.deleteNote(id);
    if (!mounted || _isDisposed) return;
    widget.onNoteMovedToTrash?.call(id);
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

  Future<void> _linkCalendarEvent(CalendarEventEntity event) async {
    final prevModule = _linkedModule;
    final prevId = _linkedId;
    setState(() {
      _linkedModule = NoteEntity.calendarLinkModule;
      _linkedId = event.id;
    });
    _markDirty(scheduleTimer: false);
    if (_noteId != null) {
      final ok = await _flushPendingSaves();
      if (!ok && mounted) {
        setState(() {
          if (_linkedModule == NoteEntity.calendarLinkModule &&
              _linkedId == event.id) {
            _linkedModule = prevModule;
            _linkedId = prevId;
          }
        });
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not link event. Kept previous link state.'),
          ),
        );
      }
    }
  }

  Future<void> _unlinkCalendarEvent() async {
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
              content: Text('Could not unlink event. Kept existing link.'),
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
        content: const Text('Unlinked event from note'),
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

  void _openCalendarEventPicker() {
    final calendarCtrl = widget.calendarController;
    if (calendarCtrl == null) return;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SharedDesignTokens.radiusSheet),
          ),
        ),
        builder: (_) => _NoteCalendarEventPickerSheet(
          calendarController: calendarCtrl,
          currentEventId:
              _linkedModule == NoteEntity.calendarLinkModule ? _linkedId : null,
          onSelectEvent: (event) => unawaited(_linkCalendarEvent(event)),
        ),
      ),
    );
  }

  Future<void> _setProject(ProjectEntity project) async {
    final prevProjectId = _projectId;
    setState(() {
      _projectId = project.id;
    });
    _markDirty(scheduleTimer: false);
    if (_noteId != null) {
      final ok = await _flushPendingSaves();
      if (!ok && mounted) {
        setState(() {
          if (_projectId == project.id) {
            _projectId = prevProjectId;
          }
        });
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not associate project. Kept previous state.'),
          ),
        );
      }
    }
  }

  Future<void> _clearProject() async {
    final prevProjectId = _projectId;
    setState(() {
      _projectId = null;
    });
    _markDirty(scheduleTimer: false);
    if (_noteId != null) {
      final ok = await _flushPendingSaves();
      if (!ok) {
        if (mounted) {
          setState(() {
            if (_projectId == null) {
              _projectId = prevProjectId;
            }
          });
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Could not remove project. Kept existing association.'),
            ),
          );
        }
        return;
      }
    }
    if (!mounted || prevProjectId == null) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Removed project from note'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted) return;
            setState(() {
              _projectId = prevProjectId;
            });
            _markDirty(scheduleTimer: false);
            if (_noteId != null) {
              unawaited(_flushPendingSaves());
            }
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _openProjectPicker() {
    final projectsCtrl = widget.projectsController;
    if (projectsCtrl == null) return;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SharedDesignTokens.radiusSheet),
          ),
        ),
        builder: (_) => _NoteProjectPickerSheet(
          projectsController: projectsCtrl,
          currentProjectId: _projectId,
          onSelectProject: (project) => unawaited(_setProject(project)),
          onClearProject: _projectId != null ? () => unawaited(_clearProject()) : null,
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

  Future<void> _handleCreateFolderFromEditor() async {
    final created = await _showNotesFolderNameDialog(
      context,
      widget.controller,
    );
    if (created == null || !mounted || _isDisposed) return;
    setState(() => _category = created);
    _markDirty();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Moved to new folder "${_formatFolderLabel(created)}"'),
      ),
    );
  }

  void _applyTagCandidate(String rawCandidate) {
    final resolved = NoteDomainHelpers.resolveTagForReuse(
      rawCandidate,
      [..._tags, ...widget.controller.state.availableTags],
    );
    if (resolved == null) return;
    final alreadyOnNote = _tags.any(
      (existing) => existing.toLowerCase() == resolved.toLowerCase(),
    );
    if (alreadyOnNote) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tag "#$resolved" is already on this note'),
        ),
      );
      return;
    }
    final nextTags = NoteDomainHelpers.normalizeTags([..._tags, resolved]);
    if (nextTags.length != _tags.length) {
      setState(() => _tags = nextTags.toList());
      _markDirty(scheduleTimer: false);
      if (_noteId != null) {
        unawaited(_flushPendingSaves());
      }
    }
  }

  void _addTagDialog() {
    final ctrl = TextEditingController();
    final existingSuggestions = widget.controller.state.availableTags
        .where(
          (tag) => !_tags.any(
            (existing) => existing.toLowerCase() == tag.toLowerCase(),
          ),
        )
        .toList();
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) {
          final semantic = ctx.daywellColors;
          return AlertDialog(
            title: const Text('Add Tag'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DaywellTextField(
                    controller: ctrl,
                    label: 'Tag name',
                    hintText: 'e.g. architecture',
                    autofocus: true,
                  ),
                  if (existingSuggestions.isNotEmpty) ...[
                    const SizedBox(height: SharedDesignTokens.spacingCompact),
                    Text(
                      'Existing tags',
                      style: DaywellTypography.caption(
                        color: semantic.textMuted,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    Wrap(
                      spacing: SharedDesignTokens.spacingXs,
                      runSpacing: SharedDesignTokens.spacingXs,
                      children: [
                        for (final suggestion in existingSuggestions)
                          ActionChip(
                            label: Text(
                              '#$suggestion',
                              style: DaywellTypography.caption(
                                color: semantic.onTransferContainer,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                            backgroundColor: semantic.transferContainer,
                            onPressed: () {
                              Navigator.pop(ctx);
                              _applyTagCandidate(suggestion);
                            },
                          ),
                      ],
                    ),
                  ],
                ],
              ),
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
                  final candidate = ctrl.text;
                  Navigator.pop(ctx);
                  _applyTagCandidate(candidate);
                },
              ),
            ],
          );
        },
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

    if (widget.onSelectInternalNote != null) {
      await widget.onSelectInternalNote!(freshTarget);
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _NoteEditorScreen(
          controller: widget.controller,
          tasksController: widget.tasksController,
          projectsController: widget.projectsController,
          calendarController: widget.calendarController,
          onOpenTask: widget.onOpenTask,
          onOpenCalendarEvent: widget.onOpenCalendarEvent,
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
    final projectsCtrl = widget.projectsController;
    final calendarCtrl = widget.calendarController;
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        if (tasksCtrl != null) tasksCtrl,
        if (projectsCtrl != null) projectsCtrl,
        if (calendarCtrl != null) calendarCtrl,
      ]),
      builder: (context, _) {
        final currentNote =
            _noteId != null ? widget.controller.state.findById(_noteId!) : null;
        final isPinned = currentNote?.isPinned ?? false;
        final isFavorite = currentNote?.isFavorite ?? false;
        final effectiveLinkedModule =
            (_hasPendingChanges || _noteId == null)
                ? _linkedModule
                : (currentNote != null ? currentNote.linkedModule : _linkedModule);
        final effectiveLinkedId =
            (_hasPendingChanges || _noteId == null)
                ? _linkedId
                : (currentNote != null ? currentNote.linkedId : _linkedId);
        final isTaskLinked =
            effectiveLinkedModule == NoteEntity.taskLinkModule &&
                effectiveLinkedId != null;
        final linkedTask = effectiveLinkedModule == NoteEntity.taskLinkModule &&
                effectiveLinkedId != null &&
                tasksCtrl != null
            ? tasksCtrl.state.findTaskById(effectiveLinkedId)
            : null;
        final isEventLinked =
            effectiveLinkedModule == NoteEntity.calendarLinkModule &&
                effectiveLinkedId != null;
        final linkedEvent = isEventLinked && calendarCtrl != null
            ? calendarCtrl.state.events.cast<CalendarEventEntity?>().firstWhere(
                  (e) => e?.id == effectiveLinkedId,
                  orElse: () => null,
                )
            : null;
        final effectiveProjectId = ProjectNotesHelper.normalizeProjectId(
          (_hasPendingChanges || _noteId == null)
              ? _projectId
              : (currentNote != null ? currentNote.projectId : _projectId),
        );
        final hasProject = effectiveProjectId != null;
        final linkedProject = hasProject && projectsCtrl != null
            ? projectsCtrl.state.findProjectById(effectiveProjectId)
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

        final Widget saveStatusBadge = Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SharedDesignTokens.spacingSm,
            vertical: SharedDesignTokens.spacingXs,
          ),
          decoration: BoxDecoration(
            color: _saveStatus == 'Save failed'
                ? semantic.errorContainer
                : semantic.surfaceSubtle,
            borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
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
        );

        final bool isArchivedNote = currentNote?.isArchived ?? false;
        final List<Widget> editorActionButtons = [
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
            if (widget.isEmbedded) ...[
              DaywellIconButton(
                icon: isArchivedNote
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
                isSelected: isArchivedNote,
                tooltip: isArchivedNote ? 'Unarchive note' : 'Archive note',
                onPressed: () => unawaited(_handleEmbeddedToggleArchive()),
              ),
              DaywellIconButton(
                icon: Icons.delete_outline_rounded,
                foregroundColor: colorScheme.error,
                tooltip: 'Move to Trash',
                onPressed: () => unawaited(_handleEmbeddedMoveToTrash()),
              ),
            ],
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
          if (widget.isEmbedded && widget.onCloseEmbedded != null)
            DaywellIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Close note',
              onPressed: widget.onCloseEmbedded,
            ),
        ];

        final Widget editorBody = Center(
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
                            DaywellIconButton(
                              icon: Icons.create_new_folder_outlined,
                              iconSize: DaywellIconSize.sm,
                              tooltip: 'New folder',
                              onPressed: () =>
                                  unawaited(_handleCreateFolderFromEditor()),
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
                            if (tasksCtrl != null &&
                                !isTaskLinked &&
                                !isEventLinked &&
                                effectiveLinkedModule == null)
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
                            if (calendarCtrl != null &&
                                !isTaskLinked &&
                                !isEventLinked &&
                                effectiveLinkedModule == null)
                              ActionChip(
                                avatar: Icon(
                                  Icons.event_note_outlined,
                                  size: DaywellIconSize.xs,
                                  color: semantic.transfer,
                                ),
                                label: Text(
                                  'Link Event',
                                  style: DaywellTypography.label(
                                    color: semantic.textPrimary,
                                  ),
                                ),
                                onPressed: _openCalendarEventPicker,
                              ),
                            if (projectsCtrl != null && !hasProject)
                              ActionChip(
                                avatar: Icon(
                                  Icons.layers_outlined,
                                  size: DaywellIconSize.xs,
                                  color: colorScheme.primary,
                                ),
                                label: Text(
                                  'Add Project',
                                  style: DaywellTypography.label(
                                    color: semantic.textPrimary,
                                  ),
                                ),
                                onPressed: _openProjectPicker,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (hasProject)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SharedDesignTokens.spacingMd,
                          SharedDesignTokens.spacingXs,
                          SharedDesignTokens.spacingMd,
                          SharedDesignTokens.spacingXs,
                        ),
                        child: DaywellCard(
                          color: semantic.surfaceSubtle,
                          borderColor: semantic.border,
                          borderRadius: SharedDesignTokens.radiusMd,
                          padding: const EdgeInsets.symmetric(
                            horizontal: SharedDesignTokens.spacingCompact,
                            vertical: SharedDesignTokens.spacingXs,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.layers_outlined,
                                size: DaywellIconSize.sm,
                                color: linkedProject != null
                                    ? colorScheme.primary
                                    : semantic.textMuted,
                              ),
                              const SizedBox(
                                width: SharedDesignTokens.spacingSm,
                              ),
                              Expanded(
                                child: Wrap(
                                  spacing: SharedDesignTokens.spacingXs,
                                  runSpacing: SharedDesignTokens.spacingXs,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      linkedProject != null
                                          ? 'Project: ${linkedProject.title}'
                                          : 'Project unavailable',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: DaywellTypography.fromToken(
                                        SharedDesignTokens.typeBodyCompact,
                                        color: linkedProject != null
                                            ? semantic.textPrimary
                                            : semantic.textMuted,
                                      ).copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    if (linkedProject?.isArchived == true)
                                      const DaywellStatusBadge(
                                        label: 'Archived',
                                        tone: DaywellStatusTone.warning,
                                        showIcon: false,
                                      ),
                                  ],
                                ),
                              ),
                              if (projectsCtrl != null)
                                DaywellIconButton(
                                  icon: Icons.swap_horiz,
                                  iconSize: DaywellIconSize.md,
                                  tooltip: 'Change Project',
                                  onPressed: _openProjectPicker,
                                ),
                              DaywellIconButton(
                                icon: Icons.link_off_outlined,
                                iconSize: DaywellIconSize.md,
                                tooltip: 'Remove Project',
                                onPressed: () => unawaited(_clearProject()),
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
                                    if (!widget.isEmbedded) {
                                      Navigator.pop(context);
                                    }
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
                    if (isEventLinked)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SharedDesignTokens.spacingMd,
                          SharedDesignTokens.spacingXs,
                          SharedDesignTokens.spacingMd,
                          SharedDesignTokens.spacingXs,
                        ),
                        child: DaywellCard(
                          color: linkedEvent != null
                              ? semantic.transferContainer
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
                                Icons.event_note_outlined,
                                size: DaywellIconSize.sm,
                                color: linkedEvent != null
                                    ? semantic.transfer
                                    : semantic.textMuted,
                              ),
                              const SizedBox(
                                width: SharedDesignTokens.spacingSm,
                              ),
                              Expanded(
                                child: Text(
                                  linkedEvent != null
                                      ? 'Linked Event: ${linkedEvent.title}'
                                      : 'Linked event unavailable',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DaywellTypography.fromToken(
                                    SharedDesignTokens.typeBodyCompact,
                                    color: linkedEvent != null
                                        ? semantic.onTransferContainer
                                        : semantic.textMuted,
                                  ).copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (linkedEvent != null &&
                                  widget.onOpenCalendarEvent != null)
                                DaywellButton(
                                  label: 'Open',
                                  variant: DaywellButtonVariant.text,
                                  size: DaywellButtonSize.compact,
                                  onPressed: () async {
                                    final ok = await _flushPendingSaves();
                                    if (!ok || !context.mounted) return;
                                    if (!widget.isEmbedded) {
                                      Navigator.pop(context);
                                    }
                                    widget.onOpenCalendarEvent!(linkedEvent);
                                  },
                                ),
                              if (calendarCtrl != null)
                                DaywellIconButton(
                                  icon: Icons.swap_horiz,
                                  iconSize: DaywellIconSize.md,
                                  tooltip: 'Change Linked Event',
                                  onPressed: _openCalendarEventPicker,
                                ),
                              DaywellIconButton(
                                icon: Icons.link_off_outlined,
                                iconSize: DaywellIconSize.md,
                                tooltip: 'Unlink Event',
                                onPressed: () =>
                                    unawaited(_unlinkCalendarEvent()),
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
            );

        if (widget.isEmbedded) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: SharedDesignTokens.spacingMd,
                  vertical: SharedDesignTokens.spacingSm,
                ),
                decoration: BoxDecoration(
                  color: semantic.card,
                  border: Border(
                    bottom: BorderSide(color: semantic.divider),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: SharedDesignTokens.spacingSm,
                    runSpacing: SharedDesignTokens.spacingXs,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          saveStatusBadge,
                          if (isArchivedNote) ...[
                            const SizedBox(width: SharedDesignTokens.spacingSm),
                            const DaywellStatusBadge(
                              label: 'Archived',
                              tone: DaywellStatusTone.warning,
                              showIcon: false,
                            ),
                          ] else if (_noteId == null) ...[
                            const SizedBox(width: SharedDesignTokens.spacingSm),
                            const DaywellStatusBadge(
                              label: 'Draft',
                              tone: DaywellStatusTone.info,
                              showIcon: false,
                            ),
                          ],
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: editorActionButtons,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: editorBody),
            ],
          );
        }

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
              title: saveStatusBadge,
              actions: editorActionButtons,
            ),
            body: editorBody,
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

class _NoteProjectPickerSheet extends StatefulWidget {
  final ProjectsController projectsController;
  final String? currentProjectId;
  final void Function(ProjectEntity project) onSelectProject;
  final VoidCallback? onClearProject;

  const _NoteProjectPickerSheet({
    required this.projectsController,
    required this.currentProjectId,
    required this.onSelectProject,
    this.onClearProject,
  });

  @override
  State<_NoteProjectPickerSheet> createState() =>
      _NoteProjectPickerSheetState();
}

class _NoteProjectPickerSheetState extends State<_NoteProjectPickerSheet> {
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
    final projects = widget.projectsController.state.projects.where((p) {
      if (p.id == widget.currentProjectId) return false;
      if (q.isEmpty) return true;
      return p.title.toLowerCase().contains(q) ||
          (p.description?.toLowerCase().contains(q) ?? false);
    }).toList();
    projects.sort((a, b) {
      if (a.isArchived != b.isArchived) {
        return a.isArchived ? 1 : -1;
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
                      'Associate Note with Project',
                      style: DaywellTypography.fromToken(
                        SharedDesignTokens.typeTitle,
                        color: semantic.textPrimary,
                      ),
                    ),
                  ),
                  if (widget.onClearProject != null)
                    DaywellButton(
                      label: 'Remove',
                      variant: DaywellButtonVariant.text,
                      size: DaywellButtonSize.compact,
                      onPressed: () {
                        widget.onClearProject!();
                        Navigator.pop(context);
                      },
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
                hintText: 'Search projects...',
                onChanged: (val) => setState(() => _query = val),
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
              Expanded(
                child: projects.isEmpty
                    ? DaywellEmptyState(
                        icon: Icons.layers_outlined,
                        message: q.isNotEmpty
                            ? 'No projects match "$q"'
                            : 'No other projects available.',
                      )
                    : ListView.separated(
                        itemCount: projects.length,
                        separatorBuilder: (_, __) => const SizedBox(
                          height: SharedDesignTokens.spacingXs,
                        ),
                        itemBuilder: (_, index) {
                          final project = projects[index];
                          return DaywellCard(
                            padding: EdgeInsets.zero,
                            child: ListTile(
                              onTap: () {
                                widget.onSelectProject(project);
                                Navigator.pop(context);
                              },
                              leading: Icon(
                                Icons.layers_outlined,
                                color: colorScheme.primary,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      project.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (project.isArchived) ...[
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
                                project.description?.trim().isNotEmpty == true
                                    ? project.description!.trim()
                                    : project.status.replaceAll('_', ' '),
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

class _NoteCalendarEventPickerSheet extends StatefulWidget {
  final CalendarController calendarController;
  final String? currentEventId;
  final void Function(CalendarEventEntity event) onSelectEvent;

  const _NoteCalendarEventPickerSheet({
    required this.calendarController,
    required this.currentEventId,
    required this.onSelectEvent,
  });

  @override
  State<_NoteCalendarEventPickerSheet> createState() =>
      _NoteCalendarEventPickerSheetState();
}

class _NoteCalendarEventPickerSheetState
    extends State<_NoteCalendarEventPickerSheet> {
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
    final q = _query.trim().toLowerCase();
    final events = widget.calendarController.state.events.where((ev) {
      if (ev.id == widget.currentEventId) return false;
      if (q.isEmpty) return true;
      return ev.title.toLowerCase().contains(q) ||
          ev.dateIso.toLowerCase().contains(q) ||
          ev.category.toLowerCase().contains(q) ||
          (ev.notes?.toLowerCase().contains(q) ?? false);
    }).toList();
    events.sort((a, b) {
      final byDate = b.dateIso.compareTo(a.dateIso);
      if (byDate != 0) return byDate;
      return (b.startTime ?? '').compareTo(a.startTime ?? '');
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
                      'Link Note to Calendar Event',
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
                hintText: 'Search calendar events...',
                onChanged: (val) => setState(() => _query = val),
              ),
              const SizedBox(height: SharedDesignTokens.spacingSm),
              Expanded(
                child: events.isEmpty
                    ? DaywellEmptyState(
                        icon: Icons.event_note_outlined,
                        message: q.isNotEmpty
                            ? 'No calendar events match "$q"'
                            : 'No calendar events available to link.',
                      )
                    : ListView.separated(
                        itemCount: events.length,
                        separatorBuilder: (_, __) => const SizedBox(
                          height: SharedDesignTokens.spacingXs,
                        ),
                        itemBuilder: (_, index) {
                          final ev = events[index];
                          final ethDate = ev.ethiopianStartDate;
                          final ethLabel = SharedDateFormatter.formatEthiopian(
                            ethDate,
                            useAmharic: false,
                            includeEra: false,
                          );
                          final timeLabel = ev.isAllDay
                              ? 'All Day'
                              : (ev.startTime ?? '');
                          final subtitleParts = <String>[
                            '${ev.dateIso} ($ethLabel)',
                            if (timeLabel.isNotEmpty) timeLabel,
                            ev.category,
                          ];
                          return DaywellCard(
                            padding: EdgeInsets.zero,
                            child: ListTile(
                              onTap: () {
                                widget.onSelectEvent(ev);
                                Navigator.pop(context);
                              },
                              leading: Icon(
                                Icons.event_note_outlined,
                                color: semantic.transfer,
                              ),
                              title: Text(
                                ev.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                subtitleParts.join(' · '),
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

