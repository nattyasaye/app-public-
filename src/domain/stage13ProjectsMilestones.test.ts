import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  calculateDerivedTaskMilestoneProgress,
  calculateProjectProgressSummary,
  ProjectValidationError,
  validateMilestone,
} from './projectsEngine';
import {
  createTaskRecord,
  updateTaskRecord,
} from './taskOperations';
import { projectsService } from '../services/projectsService';
import { WebProjectsRepository } from '../data/projectsRepository';
import { SharedStateBridge } from '../services/sharedStateBridge';

function withMockBrowserStorage(fn: (store: Map<string, string>) => void): void {
  const store = new Map<string, string>();
  const prevWindow = (globalThis as any).window;
  const prevLocalStorage = (globalThis as any).localStorage;
  const mockStorage = {
    getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
    setItem: (k: string, v: string) => void store.set(k, String(v)),
    removeItem: (k: string) => void store.delete(k),
    clear: () => void store.clear(),
  };

  (globalThis as any).localStorage = mockStorage;
  (globalThis as any).window = {
    dispatchEvent: () => true,
    CustomEvent: class CustomEvent {
      type: string;
      detail: unknown;
      constructor(type: string, init?: { detail?: unknown }) {
        this.type = type;
        this.detail = init?.detail;
      }
    },
  };

  try {
    fn(store);
  } finally {
    (globalThis as any).window = prevWindow;
    (globalThis as any).localStorage = prevLocalStorage;
  }
}

describe('Stage 1.3 — Projects and Milestones Workflow (Web & Shared Engine)', () => {
  it('1. Project CRUD, status, dates validation, archive/restore, and archived-only safe delete', () => {
    withMockBrowserStorage(() => {
      assert.throws(
        () =>
          projectsService.createProjectWithBlocks({
            title: 'Invalid dates',
            status: 'active',
            startDate: '2026-12-10',
            targetDate: '2026-12-01',
            blocks: [],
          }),
        ProjectValidationError
      );

      const created = projectsService.createProjectWithBlocks({
        title: '  House Renovation  ',
        description: '  Phase 1 interior work  ',
        startDate: '2026-11-01',
        targetDate: '2026-12-30',
        status: 'on_hold',
        blocks: [],
      });
      assert.strictEqual(created.title, 'House Renovation');
      assert.strictEqual(created.description, 'Phase 1 interior work');
      assert.strictEqual(created.status, 'on_hold');
      assert.strictEqual(created.isArchived, false);

      // Cannot permanently delete unarchived project
      assert.throws(
        () => projectsService.deleteArchivedProject(created.id),
        ProjectValidationError
      );

      // Edit details & status, archive, restore, then archive + permanently delete
      const edited = projectsService.updateProjectDetails({
        projectId: created.id,
        title: 'House Renovation 2026',
        description: created.description,
        status: 'active',
        startDate: created.startDate,
        targetDate: created.targetDate,
      });
      assert.strictEqual(edited.title, 'House Renovation 2026');
      assert.strictEqual(edited.status, 'active');

      const archived = projectsService.setProjectArchived(edited.id, true);
      assert.strictEqual(archived.isArchived, true);
      assert.strictEqual(
        projectsService.listProjects({ includeArchived: false }).length,
        0
      );

      const restored = projectsService.setProjectArchived(edited.id, false);
      assert.strictEqual(restored.isArchived, false);
      assert.strictEqual(
        projectsService.listProjects({ includeArchived: false }).length,
        1
      );

      projectsService.setProjectArchived(edited.id, true);
      projectsService.deleteArchivedProject(edited.id);
      assert.strictEqual(projectsService.getProject(edited.id), undefined);
    });
  });

  it('2. Milestones CRUD, validation, deletion safely detaches Task.milestoneId, and Undo restore relinks tasks', () => {
    withMockBrowserStorage((store) => {
      const project = projectsService.createProjectWithBlocks({
        title: 'Research Thesis',
        status: 'active',
        blocks: [],
      });

      assert.throws(
        () =>
          validateMilestone({
            id: 'ms-bad',
            projectId: project.id,
            title: '   ',
            isCompleted: false,
            createdAt: '2026-11-22T08:00:00.000Z',
          }),
        ProjectValidationError
      );

      const ms = projectsService.createMilestone({
        id: 'ms-s13-1',
        projectId: project.id,
        title: '  Literature Review  ',
        dueDate: '2026-12-05',
      });
      assert.strictEqual(ms.title, 'Literature Review');
      assert.strictEqual(ms.dueDate, '2026-12-05');
      assert.strictEqual(ms.isCompleted, false);

      const updatedMs = projectsService.updateMilestone({
        milestoneId: ms.id,
        title: 'Literature Review v2',
        dueDate: '2026-12-10',
      });
      assert.strictEqual(updatedMs.title, 'Literature Review v2');
      assert.strictEqual(updatedMs.dueDate, '2026-12-10');

      const toggled = projectsService.toggleMilestone(ms.id, true);
      assert.strictEqual(toggled.isCompleted, true);

      const task = projectsService.createTaskInProject({
        projectId: project.id,
        title: 'Summarize 5 papers',
        milestoneId: ms.id,
      });
      assert.strictEqual(task.milestoneId, ms.id);

      // Deleting milestone keeps the task intact inside the project but clears milestoneId
      const delResult = projectsService.deleteMilestone(ms.id);
      assert.ok(delResult.deleted);
      assert.deepStrictEqual(delResult.detachedTaskIds, [task.id]);
      assert.strictEqual(projectsService.listMilestones(project.id).length, 0);

      const tasksAfterDelete = JSON.parse(
        store.get('daywell_tasks') || '[]'
      );
      assert.strictEqual(tasksAfterDelete.length, 1);
      assert.strictEqual(tasksAfterDelete[0].projectId, project.id);
      assert.strictEqual(tasksAfterDelete[0].milestoneId, undefined);

      // Undo restore brings back milestone and restores task link
      projectsService.restoreMilestoneSnapshot(
        delResult.deleted!,
        delResult.detachedTaskIds
      );
      assert.strictEqual(projectsService.listMilestones(project.id).length, 1);
      const tasksAfterUndo = JSON.parse(
        store.get('daywell_tasks') || '[]'
      );
      assert.strictEqual(tasksAfterUndo[0].milestoneId, ms.id);
    });
  });

  it('3. Sections reuse grouped_list/group/grouped_item without forbidden Task.sectionId or ProjectSection, preserve tasks on delete+Undo, and roundtrip in SharedStateBridge', () => {
    // Contract guardrails remain intact
    const contracts = JSON.parse(
      fs.readFileSync(
        path.join(process.cwd(), 'shared_foundation', 'schema_contracts.json'),
        'utf8'
      )
    );
    assert.strictEqual('ProjectSection' in contracts.entities, false);
    assert.strictEqual('sectionId' in contracts.entities.Task.fields, false);

    withMockBrowserStorage((store) => {
      const project = projectsService.createProjectWithBlocks({
        title: 'Product Launch',
        status: 'active',
        blocks: [],
      });

      const secPlanning = projectsService.createProjectSection(
        project.id,
        'Planning'
      );
      const secBuild = projectsService.createProjectSection(
        project.id,
        'Execution'
      );
      projectsService.renameProjectSection(secBuild.id, 'Build');

      const t1 = projectsService.createTaskInProject({
        projectId: project.id,
        title: 'Write launch brief',
        sectionId: secPlanning.id,
      });
      const t2 = projectsService.createTaskInProject({
        projectId: project.id,
        title: 'Ship landing page',
        sectionId: secBuild.id,
      });
      const t3 = projectsService.createTaskInProject({
        projectId: project.id,
        title: 'General QA',
      });

      let vm = projectsService.getProjectSectionsViewModel(project.id);
      assert.strictEqual(vm.sections.length, 2);
      assert.deepStrictEqual(
        vm.sections[0].tasks.map((t) => t.id),
        [t1.id]
      );
      assert.deepStrictEqual(
        vm.sections[1].tasks.map((t) => t.id),
        [t2.id]
      );
      assert.deepStrictEqual(
        vm.unsectionedTasks.map((t) => t.id),
        [t3.id]
      );

      // Reassign t3 to Planning
      projectsService.assignTaskToProjectSection(
        project.id,
        t3.id,
        secPlanning.id
      );
      vm = projectsService.getProjectSectionsViewModel(project.id);
      assert.deepStrictEqual(
        vm.sections[0].tasks.map((t) => t.id),
        [t1.id, t3.id]
      );
      assert.strictEqual(vm.unsectionedTasks.length, 0);

      // Delete Planning section: tasks remain safely in project as unsectioned
      const deletedSec = projectsService.deleteProjectSection(
        project.id,
        secPlanning.id
      );
      assert.ok(deletedSec.deletedGroup);
      assert.deepStrictEqual(deletedSec.detachedTaskIds, [t1.id, t3.id]);
      vm = projectsService.getProjectSectionsViewModel(project.id);
      assert.strictEqual(vm.sections.length, 1);
      assert.deepStrictEqual(
        vm.unsectionedTasks.map((t) => t.id).sort(),
        [t1.id, t3.id].sort()
      );

      // Undo section restore re-attaches t1 and t3
      projectsService.restoreProjectSection(
        project.id,
        deletedSec.deletedGroup!,
        deletedSec.detachedTaskIds
      );
      vm = projectsService.getProjectSectionsViewModel(project.id);
      assert.strictEqual(vm.sections.length, 2);
      const restoredPlanning = vm.sections.find(
        (s) => s.record.id === secPlanning.id
      );
      assert.ok(restoredPlanning);
      assert.strictEqual(restoredPlanning.tasks.length, 2);

      // SharedStateBridge roundtrip preserves milestones, section blocks, records, and task links
      const exportedJson = SharedStateBridge.exportToAndroidJson();
      const exported = JSON.parse(exportedJson) as {
        projects: Array<{ id: string }>;
        projectTrackingBlocks: Array<{ projectId: string }>;
        projectTrackingRecords: Array<{ recordType: string; linkedTaskId?: string }>;
      };
      assert.ok(exported.projects.some((p) => p.id === project.id));
      assert.ok(exported.projectTrackingBlocks.some((b) => b.projectId === project.id));
      assert.ok(
        exported.projectTrackingRecords.some(
          (r) => r.recordType === 'grouped_item' && r.linkedTaskId === t2.id
        )
      );

      store.clear();
      const imported = SharedStateBridge.importFromAndroidJson(exportedJson);
      assert.strictEqual(imported.success, true, imported.error);
      const restoredVm = projectsService.getProjectSectionsViewModel(project.id);
      assert.strictEqual(restoredVm.sections.length, 2);
      assert.strictEqual(
        WebProjectsRepository.PROJECTS_KEY.length > 0,
        true
      );
    });
  });

  it('4. Derived Task+Milestone progress & clearing Task.milestoneId when projectId is cleared/changed', () => {
    const empty = calculateDerivedTaskMilestoneProgress({
      totalTasks: 0,
      completedTasks: 0,
      totalMilestones: 0,
      completedMilestones: 0,
    });
    assert.strictEqual(empty.percentage, 0);

    const mixed = calculateDerivedTaskMilestoneProgress({
      totalTasks: 3,
      completedTasks: 2,
      totalMilestones: 1,
      completedMilestones: 1,
    });
    assert.strictEqual(mixed.completedItems, 3);
    assert.strictEqual(mixed.totalItems, 4);
    assert.strictEqual(mixed.percentage, 75);

    const manualDone = calculateDerivedTaskMilestoneProgress({
      totalTasks: 2,
      completedTasks: 0,
      totalMilestones: 1,
      completedMilestones: 0,
      isProjectManuallyCompleted: true,
    });
    assert.strictEqual(manualDone.percentage, 100);

    // Must not interfere with tracking block primaryBlockId behavior
    const summary = calculateProjectProgressSummary({
      project: {
        id: 'p1',
        title: 'P1',
        status: 'active',
        isArchived: false,
        createdAt: '2026-11-22T08:00:00.000Z',
        updatedAt: '2026-11-22T08:00:00.000Z',
      },
      blocks: [],
      records: [],
    });
    assert.strictEqual(summary.overallPercentage, undefined);

    // Changing projectId without specifying a new milestoneId clears stale milestoneId
    const createdTask = createTaskRecord({
      title: 'Subgoal task',
      projectId: 'proj-a',
      milestoneId: 'ms-a',
    });
    assert.ok(createdTask.ok);
    const movedProject = updateTaskRecord(createdTask.task, {
      projectId: 'proj-b',
    });
    assert.ok(movedProject.ok);
    assert.strictEqual(movedProject.task.projectId, 'proj-b');
    assert.strictEqual(movedProject.task.milestoneId, undefined);
  });

  it('5. Stage 1.3 Web UI components contain zero hardcoded hex literals', () => {
    const filesToCheck = [
      path.join(process.cwd(), 'src/components/projects/ProjectMilestonesSection.tsx'),
      path.join(process.cwd(), 'src/components/projects/ProjectTasksSectionsCard.tsx'),
      path.join(process.cwd(), 'src/components/projects/ProjectDetailView.tsx'),
      path.join(process.cwd(), 'src/components/projects/ProjectsWorkspaceView.tsx'),
      path.join(process.cwd(), 'src/components/DaywellTasksModule.tsx'),
    ];
    for (const filePath of filesToCheck) {
      const content = fs.readFileSync(filePath, 'utf8');
      assert.strictEqual(
        /#[0-9a-fA-F]{3,8}\b/.test(content),
        false,
        `Unexpected hardcoded hex color literal in ${path.basename(filePath)}`
      );
    }
  });
});
