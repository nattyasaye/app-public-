import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/projects/projects_controller.dart';
import 'package:personal_management_app/application/tasks/tasks_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/repositories/projects_repository.dart';
import 'package:personal_management_app/data/repositories/tasks_repository.dart';
import 'package:personal_management_app/domain/projects/project_models.dart';
import 'package:personal_management_app/ui/screens/projects/project_detail_screen.dart';
import 'package:personal_management_app/ui/screens/projects/projects_workspace_tab.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  configureSqliteForHostTests();

  group('Stage 1.3 — Projects and Milestones Workflow (Flutter)', () {
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
      addTearDown(tasksCtrl.dispose);
      addTearDown(projectsCtrl.dispose);
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
      '1. Milestones CRUD, deletion detaches Task.milestoneId, and restoreDeletedMilestone Undo relinks tasks',
      () async {
        final h = await createHarness();
        final project = await h.projectsCtrl.createProject(
          id: 'proj-f13-1',
          title: 'Portfolio Website',
          description: 'Ship dark and light modes',
          startDate: CalendarDate(year: 2026, month: 11, day: 1),
          targetDate: CalendarDate(year: 2026, month: 12, day: 15),
        );
        expect(project, isNotNull);

        await h.tasksCtrl.loadAll();
        final ms = await h.tasksCtrl.addMilestone(
          projectId: project!.id,
          title: 'Design System Ready',
          dueDate: CalendarDate(year: 2026, month: 11, day: 28),
        );
        expect(ms, isNotNull);

        final updatedMs = await h.tasksCtrl.updateMilestone(
          milestoneId: ms!.id,
          title: 'Design System Approved',
          dueDate: CalendarDate(year: 2026, month: 12, day: 2),
        );
        expect(updatedMs?.title, 'Design System Approved');

        final linkedTask = await h.tasksCtrl.createTask(
          id: 'task-f13-1',
          title: 'Export SVG icons',
          projectId: project.id,
          milestoneId: ms.id,
        );
        expect(linkedTask?.milestoneId, ms.id);

        final snapshotBeforeDelete = h.tasksCtrl.state.milestones.first;
        final detachedTaskIds = await h.tasksCtrl.deleteMilestone(ms.id);
        expect(detachedTaskIds, ['task-f13-1']);
        expect(h.tasksCtrl.state.milestones, isEmpty);
        expect(h.tasksCtrl.state.findTaskById('task-f13-1')?.projectId,
            project.id);
        expect(
            h.tasksCtrl.state.findTaskById('task-f13-1')?.milestoneId, isNull);

        await h.tasksCtrl.restoreDeletedMilestone(
          snapshotBeforeDelete,
          restoreTaskIds: detachedTaskIds,
        );
        expect(h.tasksCtrl.state.milestones.length, 1);
        expect(
          h.tasksCtrl.state.findTaskById('task-f13-1')?.milestoneId,
          snapshotBeforeDelete.id,
        );
      },
    );

    test(
      '2. Project Sections create/rename/assign/delete+Undo reuse grouped_list without touching tasks',
      () async {
        final h = await createHarness();
        final project = await h.projectsCtrl.createProject(
          id: 'proj-f13-sec',
          title: 'Home Office Upgrade',
        );
        expect(project, isNotNull);

        final sec1 = await h.projectsCtrl.createProjectSection(
          project!.id,
          'Wiring',
        );
        expect(sec1, isNotNull);
        expect(sec1!.recordType, ProjectRecordType.group);

        final renamed = await h.projectsCtrl.renameProjectSection(
          project.id,
          sec1.id,
          'Electrical & Wiring',
        );
        expect(renamed?.title, 'Electrical & Wiring');

        await h.tasksCtrl.loadAll();
        final task = await h.tasksCtrl.createTask(
          id: 'task-sec-1',
          title: 'Mount surge protector',
          projectId: project.id,
        );
        expect(task, isNotNull);

        await h.projectsCtrl.assignTaskToProjectSection(
          projectId: project.id,
          taskId: task!.id,
          taskTitle: task.title,
          sectionRecordId: sec1.id,
        );
        final linkedRecords = h.projectsCtrl.state
            .recordsForProject(project.id)
            .where((r) => r.linkedTaskId == task.id)
            .toList();
        expect(linkedRecords.length, 1);
        expect(linkedRecords.first.parentRecordId, sec1.id);

        final deleted = await h.projectsCtrl.deleteProjectSection(
          project.id,
          sec1.id,
        );
        expect(deleted.deletedGroup?.id, sec1.id);
        expect(deleted.detachedTaskIds, [task.id]);

        // Task itself stays safely inside Tasks table
        expect(h.tasksCtrl.state.findTaskById(task.id), isNotNull);

        // Undo restore re-links task into section
        await h.projectsCtrl.restoreProjectSection(
          project.id,
          deleted.deletedGroup!,
          deleted.detachedTaskIds,
          tasks: h.tasksCtrl.state.tasks,
        );
        final restoredLinks = h.projectsCtrl.state
            .recordsForProject(project.id)
            .where((r) => r.linkedTaskId == task.id)
            .toList();
        expect(restoredLinks.length, 1);
        expect(restoredLinks.first.parentRecordId, sec1.id);
      },
    );

    testWidgets(
      '3. ProjectsWorkspaceTab and ProjectDetailScreen render derived progress, milestones, and sections without raw color literals',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1400));
        addTearDown(() => unawaited(tester.binding.setSurfaceSize(null)));

        final h = await createHarness();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });
        final project = await h.projectsCtrl.createProject(
          id: 'proj-ui-13',
          title: 'Stage 1.3 UI Check',
          description: 'Verify derived progress and sections',
        );
        await h.tasksCtrl.loadAll();
        await h.tasksCtrl.createTask(
          id: 'task-ui-done',
          title: 'Complete milestone prep',
          status: 'completed',
          projectId: project!.id,
        );
        await h.tasksCtrl.createTask(
          id: 'task-ui-open',
          title: 'Write release summary',
          projectId: project.id,
        );
        await h.tasksCtrl.addMilestone(
          projectId: project.id,
          title: 'Beta Sign-off',
        );
        await h.projectsCtrl.createProjectSection(project.id, 'Delivery');

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: Scaffold(
              body: ProjectsWorkspaceTab(
                projectsController: h.projectsCtrl,
                tasksController: h.tasksCtrl,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1 completed of 3 (2 tasks + 1 milestone) -> 33%
        expect(find.text('Stage 1.3 UI Check'), findsOneWidget);
        expect(find.text('33%'), findsOneWidget);
        expect(
          find.textContaining('1/2 tasks · 1 remaining · 0/1 milestone'),
          findsOneWidget,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light,
            home: ProjectDetailScreen(
              projectId: project.id,
              projectsController: h.projectsCtrl,
              tasksController: h.tasksCtrl,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('PROJECT COMPLETION'), findsOneWidget);
        expect(find.text('Milestones'), findsOneWidget);
        expect(find.text('Beta Sign-off'), findsOneWidget);
        expect(find.text('Tasks & Sections'), findsOneWidget);
        expect(find.text('Delivery (0)'), findsOneWidget);
        expect(find.text('Write release summary'), findsOneWidget);
      },
    );

    test(
      '4. Static UI guard: projects screens use zero Color(0x...) or Colors.* literals',
      () {
        final dir = Directory('lib/ui/screens/projects');
        expect(dir.existsSync(), isTrue);
        for (final entity in dir.listSync().whereType<File>()) {
          if (!entity.path.endsWith('.dart')) continue;
          final source = entity.readAsStringSync();
          expect(
            RegExp(r'Color\(0x').hasMatch(source),
            isFalse,
            reason: '${entity.path} must not contain raw Color(0x...) literals',
          );
          expect(
            RegExp(r'\bColors\.').hasMatch(source),
            isFalse,
            reason: '${entity.path} must not contain Colors.* literals',
          );
        }
      },
    );
  });
}
