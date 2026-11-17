import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/inbox/inbox_controller.dart';
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/domain/inbox/inbox_contracts.dart';
import 'package:personal_management_app/domain/inbox/inbox_models.dart';
import 'package:personal_management_app/domain/notes/note_contracts.dart';
import 'package:personal_management_app/domain/notes/note_models.dart';

class _InMemoryNotesRepository implements INotesRepository {
  final List<NoteEntity> _store = [];
  bool shouldThrowOnWrite = false;

  void seedPersisted(NoteEntity note) => _store.add(note);

  @override
  Future<NoteEntity> createNote(NoteEntity note) async {
    if (shouldThrowOnWrite) throw StateError('Simulated DB write failure');
    final persisted = note.copyWith();
    _store.insert(0, persisted);
    return persisted;
  }

  @override
  Future<void> deleteNote(String id) async {
    _store.removeWhere((n) => n.id == id);
  }

  @override
  Future<NoteEntity?> getNoteById(String id) async {
    for (final n in _store) {
      if (n.id == id) return n;
    }
    return null;
  }

  @override
  Future<List<NoteEntity>> getNotes({
    String? category,
    String? projectId,
    String? goalId,
    bool includeArchived = false,
    bool includeTrashed = false,
  }) async {
    // Simulates schema v4 SQLite returning full persisted note metadata columns.
    return _store.map((n) => n.copyWith()).toList();
  }

  @override
  Future<List<NoteEntity>> searchNotes(String query) async {
    return _store.where((n) => n.matchesQuery(query)).toList();
  }

  @override
  Future<NoteEntity> updateNote(NoteEntity note) async {
    if (shouldThrowOnWrite) throw StateError('Simulated DB write failure');
    final idx = _store.indexWhere((n) => n.id == note.id);
    if (idx != -1) {
      _store[idx] = note;
    }
    return note;
  }
}

class _InMemoryInboxRepository implements IInboxRepository {
  final List<InboxItemEntity> _store = [];
  final StreamController<List<InboxItemEntity>> _streamController =
      StreamController<List<InboxItemEntity>>.broadcast();
  int _seq = 0;

  @override
  Future<InboxItemEntity> captureQuickThought(String rawText,
      {String category = 'general'}) async {
    _seq++;
    final item = InboxItemEntity(
      id: 'inbox-$_seq',
      rawText: rawText.trim(),
      category: category,
      isProcessed: false,
    );
    _store.insert(0, item);
    _streamController.add(_store.where((i) => !i.isProcessed).toList());
    return item;
  }

  @override
  Future<void> deleteItem(String id) async {
    _store.removeWhere((i) => i.id == id);
    _streamController.add(_store.where((i) => !i.isProcessed).toList());
  }

  @override
  Future<List<InboxItemEntity>> getAllInboxItems(
      {bool includeProcessed = false}) async {
    if (includeProcessed) return List.of(_store);
    return _store.where((i) => !i.isProcessed).toList();
  }

  @override
  Future<void> markProcessed(String id) async {
    final idx = _store.indexWhere((i) => i.id == id);
    if (idx != -1) {
      _store[idx] = _store[idx].copyWith(isProcessed: true);
    }
    _streamController.add(_store.where((i) => !i.isProcessed).toList());
  }

  @override
  Future<void> updateItemText(String id, String newText,
      {String? category}) async {
    final idx = _store.indexWhere((i) => i.id == id);
    if (idx != -1) {
      _store[idx] = _store[idx].copyWith(rawText: newText, category: category);
    }
    _streamController.add(_store.where((i) => !i.isProcessed).toList());
  }

  @override
  Stream<List<InboxItemEntity>> watchUnprocessedItems() =>
      _streamController.stream;

  Future<void> close() => _streamController.close();
}

void main() {
  group('NotesController & NotesModuleState Architecture Tests', () {
    test(
        'Create, pin, tag, archive, trash, and reload persists metadata under schema v4',
        () async {
      final repo = _InMemoryNotesRepository();
      final controller = NotesController(repository: repo);

      final created = await controller.createNote(
        title: 'Ethiopian Calendar Spec',
        content: 'Pagume leap year every 4th year',
        category: 'reference',
        tags: ['calendar', 'ethiopia'],
      );

      expect(controller.state.activeNotesCount, 1);
      await controller.togglePin(created.id);
      await controller.toggleFavorite(created.id);

      // Simulate restart with fresh controller reading persisted schema v4 repository metadata
      final restartedController = NotesController(repository: repo);
      await restartedController.loadNotes();

      final reloaded = restartedController.state.findById(created.id)!;
      expect(reloaded.isPinned, isTrue);
      expect(reloaded.isFavorite, isTrue);
      expect(reloaded.tags, ['calendar', 'ethiopia']);

      await restartedController.deleteNote(created.id); // soft trash
      expect(restartedController.state.activeNotesCount, 0);
      expect(restartedController.state.trashedNotesCount, 1);

      await restartedController.restoreFromTrash(created.id);
      expect(restartedController.state.activeNotesCount, 1);
      expect(restartedController.state.trashedNotesCount, 0);

      restartedController.dispose();
      controller.dispose();
    });

    test(
        'Repository errors are captured cleanly in NotesModuleState.errorMessage',
        () async {
      final repo = _InMemoryNotesRepository()..shouldThrowOnWrite = true;
      final controller = NotesController(repository: repo);

      await controller.createNote(title: 'Test', content: 'Body');
      expect(controller.state.errorMessage, isNotNull);
      expect(controller.state.notes, isEmpty);

      controller.dispose();
    });
  });

  group('InboxController & InboxModuleState Architecture Tests', () {
    test(
        'Captures quick thoughts, triggers decoupled triage callback, and disposes stream cleanly',
        () async {
      final repo = _InMemoryInboxRepository();
      final triaged = <InboxItemEntity>[];
      final controller = InboxController(
        repository: repo,
        onTriageCapture: triaged.add,
      );

      controller.startWatchingUnprocessed();
      final item = await controller.captureQuickThought('Buy coffee beans',
          category: 'task');

      expect(item, isNotNull);
      expect(controller.unprocessedCount, 1);
      expect(triaged.length, 1);
      expect(triaged.first.category, 'task');

      await controller.markProcessed(item!.id);
      expect(controller.unprocessedCount, 0);
      expect(controller.state.processedCount, 1);

      controller.dispose();
      await repo.close();
    });
  });
}
