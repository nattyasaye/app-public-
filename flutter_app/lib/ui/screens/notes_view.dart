import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/date/shared_date.dart';
import '../../core/shared_foundation.dart';
import '../../core/theme/daywell_theme.dart';
import '../../domain/notes/note_models.dart';
import '../../domain/notes/task_notes_helpers.dart';
import '../../domain/tasks/task_models.dart';
import '../../application/notes/notes_controller.dart';
import '../../application/tasks/tasks_controller.dart';
import '../app_state.dart';
import '../widgets/shared_ui_widgets.dart';

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

  @override
  Widget build(BuildContext context) {
    final controller = widget.effectiveController;
    final tasksController = widget.effectiveTasksController;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark
        ? SharedDesignTokens.primaryDarkMode
        : SharedDesignTokens.primaryEmerald;

    return AnimatedBuilder(
      animation: Listenable.merge([
        controller,
        if (tasksController != null) tasksController,
      ]),
      builder: (context, _) {
        final moduleState = controller.state;
        final notes = moduleState.filteredNotes;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Notes & Knowledge',
                style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
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
                    for (final cat in [
                      ('all', 'All Folders'),
                      ('reflection', 'Reflection'),
                      ('reference', 'Reference'),
                      ('learning', 'Learning'),
                      ('general', 'General'),
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilterChip(
                          label: Text(cat.$2,
                              style: const TextStyle(fontSize: 11)),
                          selected: moduleState.categoryFilter == cat.$1,
                          onSelected: (_) =>
                              controller.setCategoryFilter(cat.$1),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: notes.isEmpty
                    ? DaywellEmptyState(
                        icon: Icons.note_alt_outlined,
                        message: moduleState.searchQuery.isNotEmpty
                            ? 'No notes match "${moduleState.searchQuery}"'
                            : 'No notes in this view yet',
                        actionLabel: 'Create First Note',
                        onActionPressed: () => _openNoteEditor(),
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
        onTap: () => _openNoteEditor(note),
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
                  if (note.isPinned)
                    const Icon(Icons.push_pin_rounded,
                        size: 16, color: SharedDesignTokens.primaryEmerald),
                  if (note.isFavorite)
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
                      PopupMenuItem(
                          value: 'pin',
                          child: Text(note.isPinned ? 'Unpin' : 'Pin')),
                      PopupMenuItem(
                          value: 'fav',
                          child: Text(note.isFavorite
                              ? 'Remove Favorite'
                              : 'Favorite')),
                      const PopupMenuItem(
                          value: 'duplicate', child: Text('Duplicate')),
                      const PopupMenuItem(
                          value: 'copy', child: Text('Copy Content')),
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
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _noteId = widget.existingNote?.id;
    _titleController =
        TextEditingController(text: widget.existingNote?.title ?? '');
    _contentController =
        TextEditingController(text: widget.existingNote?.content ?? '');
    _category = widget.existingNote?.category ?? 'reflection';
    _tags = List<String>.from(widget.existingNote?.tags ?? const []);
    _linkedModule = widget.existingNote?.linkedModule;
    _linkedId = widget.existingNote?.linkedId;
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    unawaited(_saveNow(fromDispose: true));
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _scheduleAutosave() {
    setState(() => _saveStatus = 'Saving...');
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(_saveNow()),
    );
  }

  Future<void> _saveNow({bool fromDispose = false}) async {
    if (_isSaving) return;
    final title = _titleController.text.trim();
    final content = _contentController.text;
    if (title.isEmpty && content.trim().isEmpty) return;

    _isSaving = true;
    try {
      if (_noteId == null) {
        final created = await widget.controller.createNote(
          title: title.isEmpty ? 'Untitled Note' : title,
          content: content,
          category: _category,
          tags: _tags,
          linkedModule: _linkedModule,
          linkedId: _linkedId,
        );
        _noteId = created.id;
      } else {
        await widget.controller.updateNote(
          id: _noteId!,
          title: title.isEmpty ? 'Untitled Note' : title,
          content: content,
          category: _category,
          tags: _tags,
          linkedModule: _linkedModule,
          linkedId: _linkedId,
          clearLink: _linkedModule == null || _linkedId == null,
        );
      }
      if (!fromDispose && mounted) {
        setState(() => _saveStatus = 'Saved');
      }
    } finally {
      _isSaving = false;
    }
  }

  Future<void> _linkTask(TaskEntity task) async {
    setState(() {
      _linkedModule = NoteEntity.taskLinkModule;
      _linkedId = task.id;
    });
    if (_noteId != null) {
      await widget.controller.linkNoteToEntity(
        _noteId!,
        module: NoteEntity.taskLinkModule,
        entityId: task.id,
      );
    }
  }

  Future<void> _unlinkTask() async {
    final prevModule = _linkedModule;
    final prevId = _linkedId;
    setState(() {
      _linkedModule = null;
      _linkedId = null;
    });
    if (_noteId != null) {
      await widget.controller.unlinkNote(_noteId!);
    }
    if (!mounted || prevModule == null || prevId == null) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Unlinked task from note'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (mounted) {
              setState(() {
                _linkedModule = prevModule;
                _linkedId = prevId;
              });
            }
            if (_noteId != null) {
              unawaited(
                widget.controller.linkNoteToEntity(
                  _noteId!,
                  module: prevModule,
                  entityId: prevId,
                ),
              );
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
    _scheduleAutosave();
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
                final tag = ctrl.text.trim().replaceAll('#', '');
                if (tag.isNotEmpty && !_tags.contains(tag)) {
                  setState(() => _tags.add(tag));
                  if (_noteId != null) {
                    unawaited(widget.controller.updateTags(_noteId!, _tags));
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
        final linkedTask = isTaskLinked && tasksCtrl != null
            ? tasksCtrl.state.findTaskById(effectiveLinkedId!)
            : null;
        final semantic = context.daywellColors;
        final colorScheme = Theme.of(context).colorScheme;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              _saveStatus,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            actions: [
              if (_noteId != null) ...[
                IconButton(
                  icon: Icon(
                    isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  ),
                  onPressed: () =>
                      unawaited(widget.controller.togglePin(_noteId!)),
                ),
                IconButton(
                  icon: Icon(isFavorite ? Icons.star : Icons.star_border),
                  onPressed: () =>
                      unawaited(widget.controller.toggleFavorite(_noteId!)),
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
                  onChanged: (_) => _scheduleAutosave(),
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
                      items: const [
                        DropdownMenuItem(
                            value: 'reflection', child: Text('Reflection')),
                        DropdownMenuItem(
                            value: 'reference', child: Text('Reference')),
                        DropdownMenuItem(
                            value: 'learning', child: Text('Learning')),
                        DropdownMenuItem(
                            value: 'general', child: Text('General')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _category = val);
                          _scheduleAutosave();
                        }
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.tag, size: 14),
                      label:
                          const Text('Add Tag', style: TextStyle(fontSize: 12)),
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
                              await _saveNow();
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
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
                              if (_noteId != null) {
                                unawaited(
                                  widget.controller.updateTags(_noteId!, _tags),
                                );
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
                    onChanged: (_) => _scheduleAutosave(),
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
