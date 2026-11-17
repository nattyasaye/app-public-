import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/date/shared_date.dart';
import '../../core/shared_foundation.dart';
import '../../domain/notes/note_models.dart';
import '../../application/notes/notes_controller.dart';
import '../app_state.dart';
import '../widgets/shared_ui_widgets.dart';

class NotesView extends StatefulWidget {
  final AppStateManager? state;
  final NotesController? controller;

  const NotesView({
    super.key,
    this.state,
    this.controller,
  }) : assert(state != null || controller != null,
            'Either state or controller must be provided to NotesView');

  NotesController get effectiveController =>
      controller ?? state!.notesController;

  @override
  State<NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<NotesView> {
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.effectiveController.state.searchQuery,
    );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark
        ? SharedDesignTokens.primaryDarkMode
        : SharedDesignTokens.primaryEmerald;

    return AnimatedBuilder(
      animation: controller,
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
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteEditorScreen extends StatefulWidget {
  final NotesController controller;
  final NoteEntity? existingNote;

  const _NoteEditorScreen({
    required this.controller,
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
        );
        _noteId = created.id;
      } else {
        await widget.controller.updateNote(
          id: _noteId!,
          title: title.isEmpty ? 'Untitled Note' : title,
          content: content,
          category: _category,
          tags: _tags,
        );
      }
      if (!fromDispose && mounted) {
        setState(() => _saveStatus = 'Saved');
      }
    } finally {
      _isSaving = false;
    }
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
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final currentNote =
            _noteId != null ? widget.controller.state.findById(_noteId!) : null;
        final isPinned = currentNote?.isPinned ?? false;
        final isFavorite = currentNote?.isFavorite ?? false;

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
                child: Row(
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
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: const Icon(Icons.tag, size: 14),
                      label:
                          const Text('Add Tag', style: TextStyle(fontSize: 12)),
                      onPressed: _addTagDialog,
                    ),
                  ],
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
