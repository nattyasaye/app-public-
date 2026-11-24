import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/date/shared_date.dart';
import '../../core/shared_foundation.dart';
import '../../core/theme/daywell_theme.dart';
import '../../domain/notes/note_helpers.dart';
import '../../domain/notes/note_models.dart';
import '../../domain/notes/task_notes_helpers.dart';
import '../../domain/tasks/task_models.dart';
import '../../application/notes/notes_controller.dart';
import '../../application/tasks/tasks_controller.dart';
import '../app_state.dart';
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
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Permanently?'),
          content: Text(
            'Delete "${note.displayTitle}" permanently? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                unawaited(
                  widget.effectiveController.permanentlyDeleteNote(note.id),
                );
                Navigator.pop(ctx);
              },
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmEmptyTrash(NotesController controller, int count) {
    final errorColor = Theme.of(context).colorScheme.error;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Empty Trash?'),
          content: Text(
            'Permanently delete $count trashed ${count == 1 ? 'note' : 'notes'}? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: errorColor),
              onPressed: () {
                unawaited(controller.emptyTrash());
                Navigator.pop(ctx);
              },
              child: const Text('Empty Trash'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.effectiveController;
    final tasksController = widget.effectiveTasksController;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark
        ? SharedDesignTokens.primaryDarkMode
        : SharedDesignTokens.primaryEmerald;
    final colorScheme = Theme.of(context).colorScheme;

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

        return Scaffold(
          appBar: AppBar(
            title: const Text('Notes & Knowledge',
                style: TextStyle(fontWeight: FontWeight.bold)),
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
                  ),
                  child: const Text('Empty Trash'),
                ),
              IconButton(
                icon: Icon(moduleState.isGridView
                    ? Icons.view_list_rounded
                    : Icons.grid_view_rounded),
                tooltip: moduleState.isGridView ? 'List View' : 'Grid View',
                onPressed: controller.toggleGridView,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.sort_rounded),
                onSelected: controller.setSortBy,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'recent', child: Text('Recently Modified')),
                  PopupMenuItem(
                      value: 'alpha', child: Text('Alphabetical (A–Z)')),
                  PopupMenuItem(value: 'oldest', child: Text('Oldest First')),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openNoteEditor(),
            backgroundColor: primary,
            foregroundColor: isDark ? Colors.black : Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('New Note'),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search notes, tags, or folders...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: moduleState.searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              controller.setSearchQuery('');
                            },
                          )
                        : null,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: controller.setSearchQuery,
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final sec in [
                      ('active', 'All Notes'),
                      ('pinned', 'Pinned'),
                      ('favorites', 'Favorites'),
                      ('archive', 'Archive'),
                      ('trash', 'Trash'),
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(sec.$2,
                              style: const TextStyle(fontSize: 12)),
                          selected: moduleState.sectionFilter == sec.$1,
                          onSelected: (_) =>
                              controller.setSectionFilter(sec.$1),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final cat in categoryChips)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilterChip(
                          label: Text(_formatFolderLabel(cat),
                              style: const TextStyle(fontSize: 11)),
                          selected: moduleState.categoryFilter == cat,
                          onSelected: (_) => controller.setCategoryFilter(cat),
                        ),
                      ),
                  ],
                ),
              ),
              if (hasError)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: DaywellStatusBanner(
                    tone: DaywellStatusTone.error,
                    title: 'Notes persistence error',
                    message: moduleState.errorMessage!,
                    actionLabel: 'Retry',
                    onActionPressed: () => unawaited(controller.loadNotes()),
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: notes.isEmpty
                    ? DaywellEmptyState(
                        icon: moduleState.sectionFilter == 'trash'
                            ? Icons.delete_outline
                            : Icons.note_alt_outlined,
                        message: moduleState.searchQuery.isNotEmpty
                            ? 'No notes match "${moduleState.searchQuery}"'
                            : moduleState.sectionFilter == 'trash'
                                ? 'Trash is empty'
                                : moduleState.sectionFilter == 'archive'
                                    ? 'No archived notes yet'
                                    : 'No notes in this view yet',
                        actionLabel: moduleState.searchQuery.isEmpty &&
                                moduleState.sectionFilter != 'trash' &&
                                moduleState.sectionFilter != 'archive'
                            ? 'Create First Note'
                            : null,
                        onActionPressed: moduleState.searchQuery.isEmpty &&
                                moduleState.sectionFilter != 'trash' &&
                                moduleState.sectionFilter != 'archive'
                            ? () => _openNoteEditor()
                            : null,
                      )
                    : moduleState.isGridView
                        ? GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 0.9,
                            ),
                            itemCount: notes.length,
                            itemBuilder: (_, i) => _buildNoteCard(
                                notes[i], moduleState.isGridView),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: notes.length,
                            itemBuilder: (_, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _buildNoteCard(
                                  notes[i], moduleState.isGridView),
                            ),
                          ),
              ),
            ],
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
    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;
    final ethDate =
        CalendarDate.fromUtcInstantInEthiopia(note.createdAt).toEthiopian();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withOpacity(0.2)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: note.isTrashed
            ? () => _promptRestoreTrashedNote(note)
            : () => _openNoteEditor(note),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  if (note.isPinned && !note.isTrashed && !note.isArchived)
                    const Icon(Icons.push_pin_rounded,
                        size: 16, color: SharedDesignTokens.primaryEmerald),
                  if (note.isFavorite && !note.isTrashed && !note.isArchived)
                    const Icon(Icons.star_rounded,
                        size: 16, color: Colors.amber),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
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
                            child: Text(note.isPinned ? 'Unpin' : 'Pin')),
                        PopupMenuItem(
                            value: 'fav',
                            child: Text(note.isFavorite
                                ? 'Remove Favorite'
                                : 'Favorite')),
                      ],
                      if (!note.isTrashed) ...[
                        const PopupMenuItem(
                            value: 'duplicate', child: Text('Duplicate')),
                      ],
                      const PopupMenuItem(
                          value: 'copy', child: Text('Copy Content')),
                      if (!note.isTrashed)
                        PopupMenuItem(
                            value: 'archive',
                            child:
                                Text(note.isArchived ? 'Unarchive' : 'Archive')),
                      PopupMenuItem(
                          value: 'trash',
                          child: Text(note.isTrashed
                              ? 'Restore from Trash'
                              : 'Move to Trash')),
                      if (note.isTrashed)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete Permanently',
                              style: TextStyle(color: Colors.red)),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                note.content,
                maxLines: isGridView ? 4 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: SharedDesignTokens.secondaryMint,
                      borderRadius:
                          BorderRadius.circular(SharedDesignTokens.radiusSm),
                    ),
                    child: Text(
                      note.category,
                      style: const TextStyle(
                        fontSize: 11,
                        color: SharedDesignTokens.primaryEmerald,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final t in note.tags.take(2))
                    Text('#$t',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.teal)),
                  Text(
                    SharedDateFormatter.formatEthiopian(
                      ethDate,
                      useAmharic: false,
                      includeEra: false,
                    ),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
              if (note.isLinkedToTask) ...[
                const SizedBox(height: 6),
                InkWell(
                  borderRadius:
                      BorderRadius.circular(SharedDesignTokens.radiusSm),
                  onTap: linkedTask != null && widget.onOpenTask != null
                      ? () => widget.onOpenTask!(linkedTask.id)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius:
                          BorderRadius.circular(SharedDesignTokens.radiusSm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 12,
                          color: linkedTask != null
                              ? colorScheme.primary
                              : semantic.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            linkedTask != null
                                ? 'Task: ${linkedTask.title}'
                                : 'Linked task unavailable',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: linkedTask != null
                                  ? colorScheme.onPrimaryContainer
                                  : semantic.textMuted,
                            ),
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
      ),
    );
  }
}

class _NoteEditorScreen extends StatefulWidget {
  final NotesController controller;
  final TasksController? tasksController;
  final void Function(String taskId)? onOpenTask;
  final NoteEntity? existingNote;

  const _NoteEditorScreen({
    required this.controller,
    this.tasksController,
    this.onOpenTask,
    required this.existingNote,
  });

  @override
  State<_NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<_NoteEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
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

  bool get _hasPendingChanges =>
      _editRevision > _savedRevision || _saveErrorMessage != null;

  @override
  void initState() {
    super.initState();
    _noteId = widget.existingNote?.id;
    _titleController =
        TextEditingController(text: widget.existingNote?.title ?? '');
    _contentController =
        TextEditingController(text: widget.existingNote?.content ?? '');
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

  void _insertFormat(String prefix, [String suffix = '']) {
    final text = _contentController.text;
    final sel = _contentController.selection;
    final start = sel.start >= 0 ? sel.start : text.length;
    final end = sel.end >= 0 ? sel.end : text.length;
    final selected = text.substring(start, end);
    final updated = text.replaceRange(start, end, '$prefix$selected$suffix');
    _contentController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(
        offset: start + prefix.length + selected.length + suffix.length,
      ),
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
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'e.g. architecture'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
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
              child: const Text('Add'),
            ),
          ],
        ),
      ),
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
              title: Text(
                _saveStatus,
                style: TextStyle(
                  fontSize: 13,
                  color: _saveStatus == 'Save failed'
                      ? colorScheme.error
                      : Colors.grey,
                ),
              ),
              actions: [
                if (_noteId != null) ...[
                  IconButton(
                    icon: Icon(
                      isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    ),
                    onPressed: () => unawaited(_handleTogglePin()),
                  ),
                  IconButton(
                    icon: Icon(isFavorite ? Icons.star : Icons.star_border),
                    onPressed: () => unawaited(_handleToggleFavorite()),
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.copy_rounded),
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
            body: Column(
              children: [
                if (_saveErrorMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: DaywellStatusBanner(
                      tone: DaywellStatusTone.error,
                      title: 'Unable to save note',
                      message: _saveErrorMessage!,
                      actionLabel: 'Retry',
                      onActionPressed: () => unawaited(_flushPendingSaves()),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _titleController,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      hintText: 'Note title...',
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => _markDirty(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DropdownButton<String>(
                        value: _category,
                        underline: const SizedBox.shrink(),
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
                      ActionChip(
                        avatar: const Icon(Icons.tag, size: 14),
                        label: const Text('Add Tag',
                            style: TextStyle(fontSize: 12)),
                        onPressed: _addTagDialog,
                      ),
                      if (tasksCtrl != null && !isTaskLinked)
                        ActionChip(
                          avatar: const Icon(Icons.add_link, size: 14),
                          label: const Text('Link Task',
                              style: TextStyle(fontSize: 12)),
                          onPressed: _openTaskPicker,
                        ),
                    ],
                  ),
                ),
                if (isTaskLinked)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius:
                            BorderRadius.circular(SharedDesignTokens.radiusSm),
                        border: Border.all(color: semantic.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 16,
                            color: linkedTask != null
                                ? colorScheme.primary
                                : semantic.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              linkedTask != null
                                  ? 'Linked Task: ${linkedTask.title}'
                                  : 'Linked task unavailable',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: linkedTask != null
                                        ? colorScheme.onPrimaryContainer
                                        : semantic.textMuted,
                                  ),
                            ),
                          ),
                          if (linkedTask != null && widget.onOpenTask != null)
                            TextButton(
                              onPressed: () async {
                                final ok = await _flushPendingSaves();
                                if (!ok || !context.mounted) return;
                                Navigator.pop(context);
                                widget.onOpenTask!(linkedTask.id);
                              },
                              child: const Text('Open'),
                            ),
                          if (tasksCtrl != null)
                            IconButton(
                              icon: const Icon(Icons.swap_horiz, size: 18),
                              tooltip: 'Change Linked Task',
                              onPressed: _openTaskPicker,
                            ),
                          IconButton(
                            icon: const Icon(Icons.link_off_outlined, size: 18),
                            tooltip: 'Unlink Task',
                            onPressed: () => unawaited(_unlinkTask()),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_tags.isNotEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Wrap(
                      spacing: 6,
                      children: _tags
                          .map(
                            (t) => Chip(
                              label: Text('#$t',
                                  style: const TextStyle(fontSize: 11)),
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
                const Divider(height: 1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _contentController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText: 'Start writing (English & Amharic / ፊደል)...',
                        border: InputBorder.none,
                      ),
                      onChanged: (_) => _markDirty(),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border(
                        top: BorderSide(color: Colors.grey.withOpacity(0.2))),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                            icon: const Icon(Icons.title),
                            tooltip: 'Heading',
                            onPressed: () => _insertFormat('# ')),
                        IconButton(
                            icon: const Icon(Icons.format_bold),
                            tooltip: 'Bold',
                            onPressed: () => _insertFormat('**', '**')),
                        IconButton(
                            icon: const Icon(Icons.format_italic),
                            tooltip: 'Italic',
                            onPressed: () => _insertFormat('*', '*')),
                        IconButton(
                            icon: const Icon(Icons.format_list_bulleted),
                            tooltip: 'Bullet',
                            onPressed: () => _insertFormat('- ')),
                        IconButton(
                            icon: const Icon(Icons.format_list_numbered),
                            tooltip: 'Numbered',
                            onPressed: () => _insertFormat('1. ')),
                        IconButton(
                            icon: const Icon(Icons.check_box_outlined),
                            tooltip: 'Checklist',
                            onPressed: () => _insertFormat('- [ ] ')),
                        IconButton(
                            icon: const Icon(Icons.format_quote),
                            tooltip: 'Quote',
                            onPressed: () => _insertFormat('> ')),
                        IconButton(
                            icon: const Icon(Icons.link),
                            tooltip: 'Link Note',
                            onPressed: () => _insertFormat('[[', ']]')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
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
