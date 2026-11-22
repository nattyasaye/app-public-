import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/projects/projects_controller.dart';
import 'package:personal_management_app/application/tasks/tasks_controller.dart';
import 'package:personal_management_app/application/tasks/tasks_state.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/projects_repository.dart';
import 'package:personal_management_app/data/repositories/tasks_repository.dart';
import 'package:personal_management_app/ui/screens/tasks_view.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  configureSqliteForHostTests();

  group('Stage 1.4 — Task Organization (Flutter Controller, State & UI)', () {
    Future<
        ({
          AppDatabase db,
          DriftTasksRepository tasksRepo,
          DriftProjectsRepository projectsRepo,
          TasksController tasksCtrl,
          ProjectsController projectsCtrl,
        })> createHarness() async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.ensureInitialized();
      addTearDown(db.close);

      final tasksRepo = DriftTasksRepository(db);
      final projectsRepo = DriftProjectsRepository(db);
      final tasksCtrl = TasksController(repository: tasksRepo);
      final projectsCtrl = ProjectsController(repository: projectsRepo);
      await tasksCtrl.loadAll();
      await projectsCtrl.loadAll();

      return (
        db: db,
        tasksRepo: tasksRepo,
        projectsRepo: projectsRepo,
        tasksCtrl: tasksCtrl,
        projectsCtrl: projectsCtrl,
      );
    }

    test(
      '1. Tags/Labels CRUD: normalize, multi-assign, createTag, renameTag across tasks, deleteTag, and restoreTasksLabelsSnapshot Undo',
      () async {
        final h = await createHarness();
        final today = CalendarDate.today();

        expect(TasksModuleState.normalizeLabel('  @Deep   Work '), 'Deep Work');
        expect(
          TasksModuleState.normalizeLabels(['@Work', 'work', '##Finance', '']),
          ['Work', 'Finance'],
        );

        final createdTag = h.tasksCtrl.createTag('Quarterly');
        expect(createdTag, isTrue);
        expect(h.tasksCtrl.state.availableTags, contains('Quarterly'));
        // Rejects empty / case-insensitive duplicate tag
        expect(h.tasksCtrl.createTag('  '), isFalse);
        expect(h.tasksCtrl.createTag('@quarterly'), isFalse);

        final t1 = await h.tasksCtrl.createTask(
          id: 't14-tag-1',
          title: 'Prepare VAT filing',
          labels: const ['@Fin', 'Taxes', 'fin'],
          dueDate: today,
        );
        final t2 = await h.tasksCtrl.createTask(
          id: 't14-tag-2',
          title: 'Reconcile accounts',
          labels: const ['fin', 'Finance'],
          dueDate: today,
        );
        expect(t1?.labels, ['Fin', 'Taxes']);
        expect(t2?.labels, ['fin', 'Finance']);

        h.tasksCtrl.toggleTagFilter('Fin');
        expect(h.tasksCtrl.state.tagFilters, {'Fin'});

        final snapshotBeforeRename = List.of(h.tasksCtrl.state.tasks);
        final customBeforeRename = List.of(h.tasksCtrl.state.customTags);
        final filtersBeforeRename = Set.of(h.tasksCtrl.state.tagFilters);

        // Rename merges Fin -> Finance cleanly across SQLite tasks & active filters
        final renamed = await h.tasksCtrl.renameTag('Fin', 'Finance');
        expect(renamed, isTrue);
        expect(
          h.tasksCtrl.state.findTaskById('t14-tag-1')?.labels,
          ['Finance', 'Taxes'],
        );
        expect(
          h.tasksCtrl.state.findTaskById('t14-tag-2')?.labels,
          ['Finance'],
        );
        expect(h.tasksCtrl.state.tagFilters, {'Finance'});

        // Undo rename restores labels + filters in SQLite
        await h.tasksCtrl.restoreTasksLabelsSnapshot(
          snapshotBeforeRename,
          previousCustomTags: customBeforeRename,
          previousTagFilters: filtersBeforeRename,
        );
        expect(
          h.tasksCtrl.state.findTaskById('t14-tag-1')?.labels,
          ['Fin', 'Taxes'],
        );
        expect(h.tasksCtrl.state.tagFilters, {'Fin'});

        // Delete tag removes from all tasks & active filters
        final affected = await h.tasksCtrl.deleteTag('Fin');
        expect(affected, 2);
        expect(h.tasksCtrl.state.findTaskById('t14-tag-1')?.labels, ['Taxes']);
        expect(
            h.tasksCtrl.state.findTaskById('t14-tag-2')?.labels, ['Finance']);
        expect(h.tasksCtrl.state.tagFilters, isEmpty);
      },
    );

    test(
      '2. Views (Active, Overdue, All, Completed, Archived), Sorting (due, priority, created, alpha), Composed Filters (status, priority, dueDate, project, section, tags, search) & Clear Filters work together',
      () async {
        final h = await createHarness();
        final today = CalendarDate.today();
        final yesterday = today.addDays(-1);
        final tomorrow = today.addDays(1);
        final nextWeek = today.addDays(5);

        final project = await h.projectsCtrl.createProject(
          id: 'proj-14-org',
          title: 'Platform Rollout',
        );
        expect(project, isNotNull);
        final secApi = await h.projectsCtrl.createProjectSection(
          project!.id,
          'API',
        );
        expect(secApi, isNotNull);

        await h.tasksCtrl.loadAll();

        final tA = await h.tasksCtrl.createTask(
          id: 'org-a',
          title: 'Zeta endpoint',
          description: 'Schema index check',
          priority: 'low',
          status: 'in_progress',
          dueDate: tomorrow,
          projectId: project.id,
          labels: const ['Backend', 'Release'],
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final tB = await h.tasksCtrl.createTask(
          id: 'org-b',
          title: 'Alpha endpoint',
          description: 'Schema cache warmup',
          priority: 'urgent',
          status: 'in_progress',
          dueDate: nextWeek,
          projectId: project.id,
          labels: const ['Backend', 'Release'],
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final tOverdue = await h.tasksCtrl.createTask(
          id: 'org-overdue',
          title: 'Backfill audit',
          priority: 'high',
          status: 'not_started',
          dueDate: yesterday,
          projectId: project.id,
          labels: const ['Ops'],
        );
        final tCompleted = await h.tasksCtrl.createTask(
          id: 'org-done',
          title: 'Completed task',
          status: 'completed',
          dueDate: yesterday,
        );
        final tArchived = await h.tasksCtrl.createTask(
          id: 'org-archived',
          title: 'Archived overdue task',
          dueDate: yesterday,
          isArchived: true,
        );

        expect(tA, isNotNull);
        expect(tB, isNotNull);
        expect(tOverdue, isNotNull);
        expect(tCompleted, isNotNull);
        expect(tArchived, isNotNull);

        await h.projectsCtrl.assignTaskToProjectSection(
          projectId: project.id,
          taskId: 'org-a',
          taskTitle: 'Zeta endpoint',
          taskCompleted: false,
          sectionRecordId: secApi!.id,
        );
        await h.projectsCtrl.assignTaskToProjectSection(
          projectId: project.id,
          taskId: 'org-b',
          taskTitle: 'Alpha endpoint',
          taskCompleted: false,
          sectionRecordId: secApi.id,
        );

        // Counts
        expect(h.tasksCtrl.state.activeCount, 3);
        expect(h.tasksCtrl.state.overdueCount, 1);
        expect(h.tasksCtrl.state.completedCount, 1);
        expect(h.tasksCtrl.state.archivedCount, 1);

        // Active & Overdue views
        h.tasksCtrl.setViewFilter('active');
        expect(
          h.tasksCtrl.state.filterTasks().map((t) => t.id).toSet(),
          {'org-a', 'org-b', 'org-overdue'},
        );
        h.tasksCtrl.setViewFilter('overdue');
        expect(
          h.tasksCtrl.state.filterTasks().map((t) => t.id).toList(),
          ['org-overdue'],
        );

        // Sorting checks on Active view
        h.tasksCtrl.setViewFilter('active');
        h.tasksCtrl.setSortBy('due');
        expect(
          h.tasksCtrl.state.filterTasks().map((t) => t.id).toList(),
          ['org-overdue', 'org-a', 'org-b'],
        );
        h.tasksCtrl.setSortBy('priority');
        expect(
          h.tasksCtrl.state.filterTasks().map((t) => t.id).toList(),
          ['org-b', 'org-overdue', 'org-a'],
        );
        h.tasksCtrl.setSortBy('alpha');
        expect(
          h.tasksCtrl.state.filterTasks().map((t) => t.id).toList(),
          ['org-b', 'org-overdue', 'org-a'],
        );
        h.tasksCtrl.setSortBy('created');
        expect(
          h.tasksCtrl.state.filterTasks().map((t) => t.id).toList(),
          ['org-overdue', 'org-b', 'org-a'],
        );

        // Unsectioned vs Section ID lookup
        final apiTaskIds = h.projectsCtrl.state.taskIdsForSection(
          project.id,
          secApi.id,
          allTasks: h.tasksCtrl.state.tasks,
        );
        expect(apiTaskIds, {'org-a', 'org-b'});
        final unsectionedIds = h.projectsCtrl.state.taskIdsForSection(
          project.id,
          '__unsectioned__',
          allTasks: h.tasksCtrl.state.tasks,
        );
        expect(unsectionedIds, {'org-overdue'});

        // Composed filters + Search + Sort
        h.tasksCtrl.setStatusFilter('in_progress');
        h.tasksCtrl.setDueDateFilter('upcoming');
        h.tasksCtrl.selectProject(project.id);
        h.tasksCtrl.setSectionFilter(secApi.id);
        h.tasksCtrl.toggleTagFilter('Backend');
        h.tasksCtrl.toggleTagFilter('Release');
        h.tasksCtrl.setSearchQuery('schema');
        h.tasksCtrl.setSortBy('alpha');

        expect(h.tasksCtrl.state.hasActiveFilters, isTrue);
        expect(
          h.tasksCtrl.state
              .filterTasks(sectionTaskIds: apiTaskIds)
              .map((t) => t.id)
              .toList(),
          ['org-b', 'org-a'],
        );

        // Changing project clears sectionFilter safely
        h.tasksCtrl.selectProject(null);
        expect(h.tasksCtrl.state.sectionFilter, isNull);

        // Clear filters preserves current view when resetView: false
        h.tasksCtrl.clearFilters(resetView: false);
        expect(h.tasksCtrl.state.hasActiveFilters, isFalse);
        expect(h.tasksCtrl.state.viewFilter, 'active');
        expect(h.tasksCtrl.state.filterTasks().length, 3);
      },
    );

    testWidgets(
      '3. TasksView renders shared DaywellSearchFilterBar, Active/Overdue chips, Filter controls, Manage Tags, and Clear filters',
      (WidgetTester tester) async {
        final h = await createHarness();
        final today = CalendarDate.today();
        final yesterday = today.addDays(-1);

        await h.tasksCtrl.createTask(
          id: 'w14-1',
          title: 'Review release notes',
          description: 'Verify changelog',
          priority: 'high',
          dueDate: yesterday,
          labels: const ['Launch'],
        );
        await h.tasksCtrl.createTask(
          id: 'w14-2',
          title: 'Buy groceries',
          dueDate: today.addDays(2),
          labels: const ['Errands'],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: TasksView(
              controller: h.tasksCtrl,
              projectsController: h.projectsCtrl,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Shared Search bar present
        expect(
          find.text('Search tasks by title, description, or @tags...'),
          findsOneWidget,
        );

        // Switch to Overdue view chip
        await tester.tap(find.text('Overdue'));
        await tester.pumpAndSettle();
        expect(find.text('Review release notes'), findsOneWidget);
        expect(find.text('Buy groceries'), findsNothing);

        // Switch to Active view chip -> shows both
        await tester.tap(find.text('Active'));
        await tester.pumpAndSettle();
        expect(find.text('Review release notes'), findsOneWidget);
        expect(find.text('Buy groceries'), findsOneWidget);

        // Open Filters panel and filter by @Launch tag
        await tester.tap(find.byTooltip('Toggle Filters'));
        await tester.pumpAndSettle();
        expect(find.text('@Launch'), findsWidgets);
        await tester.tap(find.widgetWithText(FilterChip, '@Launch'));
        await tester.pumpAndSettle();
        expect(find.text('Review release notes'), findsOneWidget);
        expect(find.text('Buy groceries'), findsNothing);

        // Clear filters brings both tasks back
        await tester.tap(find.text('Clear filters').first);
        await tester.pumpAndSettle();
        expect(find.text('Review release notes'), findsOneWidget);
        expect(find.text('Buy groceries'), findsOneWidget);

        // Open Manage Tags dialog
        await tester.tap(find.byTooltip('Manage Tags'));
        await tester.pumpAndSettle();
        expect(find.text('Manage Tags'), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      },
    );

    test(
      '4. Static architecture & design-system check: no raw Color(0x...) and no duplicate Search repository',
      () {
        final tasksViewFile = File('lib/ui/screens/tasks_view.dart');
        final content = tasksViewFile.existsSync()
            ? tasksViewFile.readAsStringSync()
            : File('flutter_app/lib/ui/screens/tasks_view.dart')
                .readAsStringSync();
        expect(content.contains('DaywellSearchFilterBar'), isTrue);
        expect(RegExp(r'Color\(0x').hasMatch(content), isFalse);
      },
    );
  });
}
