import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/application/notes/notes_state.dart';
import 'package:personal_management_app/application/tasks/tasks_controller.dart';
import 'package:personal_management_app/application/tasks/tasks_state.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/domain/notes/note_models.dart';
import 'package:personal_management_app/domain/tasks/task_models.dart';
import 'package:personal_management_app/ui/screens/notes_view.dart';
import 'package:personal_management_app/ui/widgets/notes/note_markdown_preview.dart';
import 'package:personal_management_app/ui/widgets/shared_ui_widgets.dart';

class _InMemoryNotesRepository implements INotesRepository {
  final Map<String, NoteEntity> store = <String, NoteEntity>{};

  void seed(NoteEntity note) {
    store[note.id] = note;
  }

  @override
  Future<NoteEntity> createNote(NoteEntity note) async {
    store[note.id] = note;
    return note;
  }

  @override
  Future<void> deleteNote(String id, {DateTime? now}) async {
    final existing = store[id];
    if (existing != null) {
      store[id] = existing.copyWith(
        isTrashed: true,
        isPinned: false,
        updatedAt: now ?? DateTime.utc(2026, 2, 1),
      );
    }
  }

  @override
  Future<NoteEntity?> getNoteById(String id) async => store[id];

  @override
  Future<List<NoteEntity>> getNotes({
    bool includeArchived = false,
    bool includeTrashed = false,
  }) async {
    return store.values.where((n) {
      if (!includeTrashed && n.isTrashed) return false;
      if (!includeArchived && n.isArchived) return false;
      return true;
    }).toList();
  }

  @override
  Future<void> permanentlyDeleteNote(String id) async {
    store.remove(id);
  }

  @override
  Future<void> restoreNote(String id, {DateTime? now}) async {
    final existing = store[id];
    if (existing != null) {
      store[id] = existing.copyWith(
        isTrashed: false,
        updatedAt: now ?? DateTime.utc(2026, 2, 1),
      );
    }
  }

  @override
  Future<List<NoteEntity>> searchNotes(String query) async {
    return store.values.where((n) => n.matchesQuery(query)).toList();
  }

  @override
  Future<NoteEntity> updateNote(NoteEntity note) async {
    store[note.id] = note;
    return note;
  }
}

class _InMemoryTasksRepository implements ITasksRepository {
  final List<TaskEntity> store = <TaskEntity>[];

  @override
  Future<TaskEntity> createTask(TaskEntity task) async {
    store.add(task);
    return task;
  }

  @override
  Future<void> deleteTask(String id) async {
    store.removeWhere((t) => t.id == id);
  }

  @override
  Future<List<MilestoneEntity>> getMilestones({String? projectId}) async =>
      const <MilestoneEntity>[];

  @override
  Future<List<TaskEntity>> getTasks({bool includeArchived = false}) async {
    return includeArchived
        ? List<TaskEntity>.from(store)
        : store.where((t) => !t.isArchived).toList();
  }

  @override
  Future<TaskEntity?> getTaskById(String id) async {
    for (final t in store) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Future<void> saveMilestone(MilestoneEntity milestone) async {}

  @override
  Future<TaskEntity> updateTask(TaskEntity task) async {
    final idx = store.indexWhere((t) => t.id == task.id);
    if (idx >= 0) store[idx] = task;
    return task;
  }
}

List<NoteEntity> _sampleNotes() {
  return <NoteEntity>[
    NoteEntity(
      id: 'n-alpha',
      title: 'Architecture Review & Quarterly Focus Checklist',
      content:
          '# Overview\n\n- [ ] Confirm offline sync invariants\n- [x] Verify **Ethiopian** dates\n\nSee [[Project Roadmap]] for timeline.',
      category: 'work_projects',
      tags: const ['architecture', 'q2', 'extra'],
      isPinned: true,
      isFavorite: true,
      linkedModule: NoteEntity.taskLinkModule,
      linkedId: 'task-1',
      createdAt: DateTime.utc(2026, 1, 5, 8),
      updatedAt: DateTime.utc(2026, 1, 14, 9),
    ),
    NoteEntity(
      id: 'n-roadmap',
      title: 'Project Roadmap',
      content: '1. Milestone one\n2. Milestone two\n\nReference [[Architecture Review & Quarterly Focus Checklist]].',
      category: 'reference',
      tags: const ['planning'],
      createdAt: DateTime.utc(2026, 1, 2, 8),
      updatedAt: DateTime.utc(2026, 1, 12, 9),
    ),
    NoteEntity(
      id: 'n-archived',
      title: 'Archived Brief',
      content: 'Kept for historical reference.',
      category: 'learning',
      isArchived: true,
      createdAt: DateTime.utc(2026, 1, 1, 8),
      updatedAt: DateTime.utc(2026, 1, 3, 8),
    ),
    NoteEntity(
      id: 'n-trashed',
      title: 'Old Draft in Trash',
      content: 'Temporary scratch note.',
      category: 'general',
      isTrashed: true,
      createdAt: DateTime.utc(2026, 1, 1, 8),
      updatedAt: DateTime.utc(2026, 1, 4, 8),
    ),
  ];
}

void main() {
  group('Stage N3.1 — Flutter Notes UI Design-System Compliance', () {
    testWidgets(
      'NotesView renders Daywell primitives cleanly across Light/Dark themes, narrow/wide viewports, Grid/List modes, and 1.6x text scale',
      (WidgetTester tester) async {
        final notesRepo = _InMemoryNotesRepository();
        for (final n in _sampleNotes()) {
          notesRepo.seed(n);
        }
        final controller = NotesController(repository: notesRepo);
        await controller.loadNotes();

        final tasksRepo = _InMemoryTasksRepository();
        tasksRepo.store.add(
          TaskEntity(
            id: 'task-1',
            title: 'Finalize Q2 Milestone Review',
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 10),
          ),
        );
        final tasksController = TasksController(repository: tasksRepo);
        await tasksController.loadAll();

        // 1. Narrow mobile (320px) + Light theme + 1.6x accessibility text scale in List & Grid modes
        await tester.binding.setSurfaceSize(const Size(320, 720));
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 720),
                textScaler: TextScaler.linear(1.6),
              ),
              child: NotesView(
                controller: controller,
                tasksController: tasksController,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DaywellSearchFilterBar), findsOneWidget);
        expect(find.byType(DaywellCard), findsWidgets);
        expect(find.text('DAYWELL / NOTES'), findsOneWidget);
        expect(find.text('Notes & Knowledge'), findsOneWidget);
        expect(find.text('Work Projects'), findsWidgets);
        expect(find.text('Task: Finalize Q2 Milestone Review'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Toggle to Grid View at narrow 320px + 1.6x text scale -> zero overflow
        await tester.tap(find.byTooltip('Grid View'));
        await tester.pumpAndSettle();
        expect(find.byType(GridView), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 2. Wide tablet/desktop (960px) + Dark theme in Grid mode (3 columns)
        await tester.binding.setSurfaceSize(const Size(960, 800));
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.dark(),
            home: NotesView(
              controller: controller,
              tasksController: tasksController,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(GridView), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Toggle back to List mode on wide screen
        await tester.tap(find.byTooltip('List View'));
        await tester.pumpAndSettle();
        expect(find.byType(ListView), findsWidgets);
        expect(tester.takeException(), isNull);

        await tester.binding.setSurfaceSize(null);
      },
    );

    testWidgets(
      'NotesView displays loading indicator, contextual empty states, Trash banner, and DaywellConfirmationDialog',
      (WidgetTester tester) async {
        final notesRepo = _InMemoryNotesRepository();
        notesRepo.seed(
          NoteEntity(
            id: 'n-trash-1',
            title: 'Discarded Note',
            content: 'Trash body',
            isTrashed: true,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 2),
          ),
        );
        final controller = NotesController(
          repository: notesRepo,
          initialState: const NotesModuleState(isLoading: true),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light(),
            home: NotesView(controller: controller),
          ),
        );
        await tester.pump();
        expect(find.byType(DaywellLoadingIndicator), findsOneWidget);

        await controller.loadNotes();
        await tester.pumpAndSettle();

        // Active list empty state
        expect(find.byType(DaywellEmptyState), findsOneWidget);
        expect(find.text('Create First Note'), findsOneWidget);

        // Search active empty state offers Clear filters
        controller.setSearchQuery('missing-term');
        await tester.pumpAndSettle();
        expect(find.text('No notes match "missing-term"'), findsOneWidget);
        expect(find.text('Clear filters'), findsWidgets);

        await tester.tap(find.text('Clear filters').last);
        await tester.pumpAndSettle();
        expect(controller.state.searchQuery, '');

        // Switch to Trash -> shows warning banner + confirmation dialog on Empty Trash
        await tester.tap(find.text('Trash'));
        await tester.pumpAndSettle();
        expect(find.byType(DaywellStatusBanner), findsOneWidget);
        expect(find.text('Empty Trash'), findsOneWidget);

        await tester.tap(find.text('Empty Trash'));
        await tester.pumpAndSettle();
        expect(find.byType(DaywellConfirmationDialog), findsOneWidget);
        expect(find.text('Empty Trash?'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(notesRepo.store.length, 1);
      },
    );

    testWidgets(
      'Note editor complies with Daywell typography, grouped formatting toolbar, DaywellTextField tag dialog, Preview & Backlinks',
      (WidgetTester tester) async {
        final notesRepo = _InMemoryNotesRepository();
        for (final n in _sampleNotes()) {
          notesRepo.seed(n);
        }
        final controller = NotesController(repository: notesRepo);
        await controller.loadNotes();

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.dark(),
            home: NotesView(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Project Roadmap'));
        await tester.pumpAndSettle();

        // Write mode checks: save status pill, tooltips, 2 TextFields, VerticalDividers in grouped toolbar
        expect(find.text('Saved'), findsOneWidget);
        expect(find.byType(TextField), findsNWidgets(2));
        expect(find.byTooltip('Pin note'), findsOneWidget);
        expect(find.byTooltip('Favorite note'), findsOneWidget);
        expect(find.byTooltip('Copy note'), findsOneWidget);
        expect(find.byType(VerticalDivider), findsNWidgets(2));

        // Add Tag dialog uses DaywellTextField and DaywellButton
        await tester.tap(find.text('Add Tag'));
        await tester.pumpAndSettle();
        expect(find.byType(DaywellTextField), findsOneWidget);
        await tester.enterText(find.byType(DaywellTextField), 'flutter_ui');
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();
        expect(find.text('#flutter_ui'), findsOneWidget);

        // Switch to Preview: 0 TextFields, NoteMarkdownPreview, BACKLINKS (1)
        await tester.tap(find.text('Preview'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(NoteMarkdownPreview), findsOneWidget);
        expect(find.text('BACKLINKS (1)'), findsOneWidget);
        expect(
          find.text('Architecture Review & Quarterly Focus Checklist'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
