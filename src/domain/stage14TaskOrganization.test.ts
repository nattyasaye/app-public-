import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { CalendarDate } from './date';
import {
  assignLabelToTask,
  computeTaskTabCounts,
  createTaskRecord,
  DaywellTaskRecord,
  extractAvailableTaskLabels,
  filterTasksForView,
  hasActiveTaskOrganizationFilters,
  isTaskOverdueRecord,
  normalizeTaskLabel,
  normalizeTaskLabels,
  removeLabelFromAllTasks,
  removeLabelFromTask,
  renameLabelAcrossTasks,
  taskHasAllLabels,
  updateTaskRecord,
} from './taskOperations';
import { projectsService } from '../services/projectsService';
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

describe('Stage 1.4 — Task Organization (Web Domain, Sections & UI Guardrails)', () => {
  const today = CalendarDate.today();
  const todayIso = today.toIsoString();
  const yesterdayIso = today.addDays(-1).toIsoString();
  const tomorrowIso = today.addDays(1).toIsoString();
  const nextWeekIso = today.addDays(7).toIsoString();

  it('1. Tags / Labels: normalizes prefixes/whitespace, deduplicates case-insensitively, supports multi-tag create/update/assign/remove', () => {
    assert.strictEqual(normalizeTaskLabel('  @Deep   Work  '), 'Deep Work');
    assert.strictEqual(normalizeTaskLabel('##finance'), 'finance');
    assert.strictEqual(normalizeTaskLabel('  @#   '), '');

    assert.deepStrictEqual(
      normalizeTaskLabels(['@Work', 'work', '  #Finance ', '', 'Urgent', 'WORK']),
      ['Work', 'Finance', 'Urgent']
    );

    const created = createTaskRecord(
      {
        id: 't-tag-1',
        title: 'Prepare board briefing',
        labels: ['@Executive', 'Finance', 'executive', ' Q4 '],
      },
      new Date('2026-11-21T08:00:00.000Z')
    );
    assert.strictEqual(created.ok, true);
    if (!created.ok) return;
    assert.deepStrictEqual(created.task.labels, ['Executive', 'Finance', 'Q4']);

    // Multi-tag matching is case-insensitive AND requires all selected tags
    assert.strictEqual(taskHasAllLabels(created.task, ['executive', 'q4']), true);
    assert.strictEqual(taskHasAllLabels(created.task, ['executive', 'ops']), false);

    // Assign & reject blank tag
    const blankAssign = assignLabelToTask(created.task, '   @# ');
    assert.strictEqual(blankAssign.ok, false);

    const assigned = assignLabelToTask(created.task, '#Legal');
    assert.strictEqual(assigned.ok, true);
    if (!assigned.ok) return;
    assert.deepStrictEqual(assigned.task.labels, [
      'Executive',
      'Finance',
      'Q4',
      'Legal',
    ]);

    // Case-insensitive duplicate assignment is a safe no-op
    const dupAssign = assignLabelToTask(assigned.task, '@legal');
    assert.strictEqual(dupAssign.ok, true);
    if (dupAssign.ok) {
      assert.deepStrictEqual(dupAssign.task.labels, assigned.task.labels);
    }

    // Remove single tag
    const removed = removeLabelFromTask(assigned.task, 'FINANCE');
    assert.deepStrictEqual(removed.labels, ['Executive', 'Q4', 'Legal']);

    // UpdateTaskRecord clears labels when explicit empty array passed, preserves when omitted
    const cleared = updateTaskRecord(removed, { labels: [] });
    assert.strictEqual(cleared.ok, true);
    if (cleared.ok) {
      assert.deepStrictEqual(cleared.task.labels, []);
    }
  });

  it('2. Global Tag Rename, Delete, and Extraction deduplicate cleanly and preserve other task metadata', () => {
    const t1: DaywellTaskRecord = {
      id: 't-1',
      title: 'Audit ledger',
      priority: 'high',
      status: 'in_progress',
      completed: false,
      hasReminder: false,
      subtasks: [],
      labels: ['Fin', 'Taxes'],
      createdAt: '2026-11-18T10:00:00.000Z',
    };
    const t2: DaywellTaskRecord = {
      id: 't-2',
      title: 'Pay rent',
      priority: 'urgent',
      status: 'not_started',
      completed: false,
      hasReminder: true,
      subtasks: [],
      labels: ['fin', 'Finance'],
      createdAt: '2026-11-19T10:00:00.000Z',
    };
    const t3: DaywellTaskRecord = {
      id: 't-3',
      title: 'Clean desk',
      priority: 'low',
      status: 'not_started',
      completed: false,
      hasReminder: false,
      subtasks: [],
      labels: ['Home'],
      createdAt: '2026-11-20T10:00:00.000Z',
    };

    assert.deepStrictEqual(
      extractAvailableTaskLabels([t1, t2, t3], ['@Alpha']),
      ['Alpha', 'Fin', 'Finance', 'Home', 'Taxes']
    );

    const badRename = renameLabelAcrossTasks([t1, t2, t3], 'Fin', '   ');
    assert.strictEqual(badRename.ok, false);

    // Renaming "fin" -> "Finance" merges duplicate on t2 instead of duplicating
    const renamed = renameLabelAcrossTasks([t1, t2, t3], '@fin', 'Finance');
    assert.strictEqual(renamed.ok, true);
    if (!renamed.ok) return;
    assert.strictEqual(renamed.changedCount, 2);
    assert.deepStrictEqual(renamed.tasks[0].labels, ['Finance', 'Taxes']);
    assert.deepStrictEqual(renamed.tasks[1].labels, ['Finance']);
    assert.deepStrictEqual(renamed.tasks[2].labels, ['Home']);

    const deleted = removeLabelFromAllTasks(renamed.tasks, 'Finance');
    assert.strictEqual(deleted.changedCount, 2);
    assert.deepStrictEqual(deleted.tasks[0].labels, ['Taxes']);
    assert.deepStrictEqual(deleted.tasks[1].labels, []);
    assert.deepStrictEqual(deleted.tasks[2].labels, ['Home']);
  });

  it('3. Task Views (Active, Overdue, All, Completed, Archived) & Tab Counts work consistently', () => {
    const sampleTasks: DaywellTaskRecord[] = [
      {
        id: 'overdue-1',
        title: 'Submit tax form',
        priority: 'urgent',
        status: 'not_started',
        completed: false,
        dueDate: yesterdayIso,
        hasReminder: false,
        subtasks: [],
        createdAt: '2026-11-01T08:00:00.000Z',
      },
      {
        id: 'active-today',
        title: 'Call contractor',
        priority: 'high',
        status: 'in_progress',
        completed: false,
        dueDate: todayIso,
        hasReminder: false,
        subtasks: [],
        createdAt: '2026-11-02T08:00:00.000Z',
      },
      {
        id: 'active-nodate',
        title: 'Read engineering RFC',
        priority: 'medium',
        status: 'inbox',
        completed: false,
        hasReminder: false,
        subtasks: [],
        createdAt: '2026-11-03T08:00:00.000Z',
      },
      {
        id: 'completed-past',
        title: 'Renew domain',
        priority: 'low',
        status: 'completed',
        completed: true,
        dueDate: yesterdayIso,
        hasReminder: false,
        subtasks: [],
        createdAt: '2026-11-04T08:00:00.000Z',
      },
      {
        id: 'cancelled-past',
        title: 'Cancelled errand',
        priority: 'low',
        status: 'cancelled',
        completed: false,
        dueDate: yesterdayIso,
        hasReminder: false,
        subtasks: [],
        createdAt: '2026-11-05T08:00:00.000Z',
      },
      {
        id: 'archived-overdue',
        title: 'Archived old task',
        priority: 'urgent',
        status: 'not_started',
        completed: false,
        isArchived: true,
        dueDate: yesterdayIso,
        hasReminder: false,
        subtasks: [],
        createdAt: '2026-11-06T08:00:00.000Z',
      },
    ];

    assert.strictEqual(isTaskOverdueRecord(sampleTasks[0], todayIso), true);
    assert.strictEqual(isTaskOverdueRecord(sampleTasks[1], todayIso), false);
    assert.strictEqual(isTaskOverdueRecord(sampleTasks[3], todayIso), false);
    assert.strictEqual(isTaskOverdueRecord(sampleTasks[4], todayIso), false);
    assert.strictEqual(isTaskOverdueRecord(sampleTasks[5], todayIso), false);

    const counts = computeTaskTabCounts(sampleTasks, todayIso);
    assert.strictEqual(counts.activePendingCount, 3);
    assert.strictEqual(counts.overdueCount, 1);
    assert.strictEqual(counts.allCount, 5);
    assert.strictEqual(counts.completedCount, 1);
    assert.strictEqual(counts.archivedCount, 1);

    assert.deepStrictEqual(
      filterTasksForView(sampleTasks, { viewFilter: 'active', todayIso }).map((t) => t.id),
      ['overdue-1', 'active-today', 'active-nodate']
    );
    assert.deepStrictEqual(
      filterTasksForView(sampleTasks, { viewFilter: 'overdue', todayIso }).map((t) => t.id),
      ['overdue-1']
    );
    assert.deepStrictEqual(
      filterTasksForView(sampleTasks, { viewFilter: 'completed', todayIso }).map((t) => t.id),
      ['completed-past']
    );
    assert.deepStrictEqual(
      filterTasksForView(sampleTasks, { viewFilter: 'archived', todayIso }).map((t) => t.id),
      ['archived-overdue']
    );
  });

  it('4. Sorting (due, priority, created, title, time) & Multi-Criteria Filtering (status, priority, dueDate, project, section, tags, search) compose together and clear cleanly', () => {
    withMockBrowserStorage(() => {
      const projA = projectsService.createProjectWithBlocks({
        title: 'Q4 Launch',
        status: 'active',
        blocks: [{ tempId: 'b1', blockType: 'grouped_list', title: 'Sections' }],
      });
      const projB = projectsService.createProjectWithBlocks({
        title: 'Personal Ops',
        status: 'active',
        blocks: [],
      });
      const secBackend = projectsService.createProjectSection(projA.project.id, 'Backend');
      const secDesign = projectsService.createProjectSection(projA.project.id, 'Design');

      const tasks: DaywellTaskRecord[] = [
        {
          id: 't-a',
          title: 'Zebra migration',
          description: 'Migrate schema cleanly',
          priority: 'low',
          status: 'in_progress',
          completed: false,
          dueDate: tomorrowIso,
          scheduledTime: '15:00',
          projectId: projA.project.id,
          projectName: projA.project.title,
          labels: ['Backend', 'Launch'],
          hasReminder: false,
          subtasks: [],
          createdAt: '2026-11-10T09:00:00.000Z',
        },
        {
          id: 't-b',
          title: 'Alpha endpoint',
          description: 'Verify schema indexes and cache',
          priority: 'urgent',
          status: 'in_progress',
          completed: false,
          dueDate: nextWeekIso,
          scheduledTime: '08:30',
          projectId: projA.project.id,
          projectName: projA.project.title,
          labels: ['Backend', 'Launch'],
          hasReminder: false,
          subtasks: [],
          createdAt: '2026-11-15T09:00:00.000Z',
        },
        {
          id: 't-c',
          title: 'Banner artwork',
          description: 'Hero illustration',
          priority: 'high',
          status: 'not_started',
          completed: false,
          dueDate: todayIso,
          scheduledTime: '11:00',
          projectId: projA.project.id,
          projectName: projA.project.title,
          labels: ['Design'],
          hasReminder: false,
          subtasks: [],
          createdAt: '2026-11-20T09:00:00.000Z',
        },
        {
          id: 't-d',
          title: 'Unsectioned checklist',
          description: 'Verify release schema notes',
          priority: 'medium',
          status: 'in_progress',
          completed: false,
          projectId: projA.project.id,
          projectName: projA.project.title,
          labels: ['Launch'],
          hasReminder: false,
          subtasks: [],
          createdAt: '2026-11-21T09:00:00.000Z',
        },
        {
          id: 't-e',
          title: 'Gym membership',
          priority: 'high',
          status: 'not_started',
          completed: false,
          dueDate: yesterdayIso,
          projectId: projB.project.id,
          projectName: projB.project.title,
          labels: ['Health'],
          hasReminder: false,
          subtasks: [],
          createdAt: '2026-11-18T09:00:00.000Z',
        },
      ];

      localStorage.setItem(SharedStateBridge.TASKS_STORAGE_KEY, JSON.stringify(tasks));
      projectsService.assignTaskToProjectSection({
        projectId: projA.project.id,
        taskId: 't-a',
        taskTitle: 'Zebra migration',
        taskCompleted: false,
        sectionRecordId: secBackend.id,
      });
      projectsService.assignTaskToProjectSection({
        projectId: projA.project.id,
        taskId: 't-b',
        taskTitle: 'Alpha endpoint',
        taskCompleted: false,
        sectionRecordId: secBackend.id,
      });
      projectsService.assignTaskToProjectSection({
        projectId: projA.project.id,
        taskId: 't-c',
        taskTitle: 'Banner artwork',
        taskCompleted: false,
        sectionRecordId: secDesign.id,
      });

      // Verify sorting options independently on Active view
      assert.deepStrictEqual(
        filterTasksForView(tasks, { viewFilter: 'active', sortBy: 'due', todayIso }).map((t) => t.id),
        ['t-e', 't-c', 't-a', 't-b', 't-d']
      );
      assert.deepStrictEqual(
        filterTasksForView(tasks, { viewFilter: 'active', sortBy: 'created', todayIso }).map((t) => t.id),
        ['t-d', 't-c', 't-e', 't-b', 't-a']
      );
      assert.deepStrictEqual(
        filterTasksForView(tasks, { viewFilter: 'active', sortBy: 'title', todayIso }).map((t) => t.id),
        ['t-b', 't-c', 't-e', 't-d', 't-a']
      );
      assert.deepStrictEqual(
        filterTasksForView(tasks, { viewFilter: 'active', sortBy: 'priority', todayIso }).map((t) => t.id),
        ['t-b', 't-c', 't-e', 't-d', 't-a']
      );

      // Section task lookup + Unsectioned lookup
      const backendSectionIds = projectsService.getProjectSectionTaskIds(
        projA.project.id,
        secBackend.id
      );
      assert.deepStrictEqual([...backendSectionIds].sort(), ['t-a', 't-b']);

      const unsectionedIds = projectsService.getProjectSectionTaskIds(
        projA.project.id,
        '__unsectioned__'
      );
      assert.deepStrictEqual([...unsectionedIds], ['t-d']);

      // Composed filters: View(active) + Status(in_progress) + DueDate(upcoming) + Project(projA) + Section(Backend) + Tags([Backend, Launch]) + Search(description:"schema") + Sort(created)
      const composed = filterTasksForView(tasks, {
        viewFilter: 'active',
        statusFilter: 'in_progress',
        dueDateFilter: 'upcoming',
        projectIdFilter: projA.project.id,
        sectionTaskIds: backendSectionIds,
        tagFilters: ['backend', 'launch'],
        searchQuery: 'schema',
        sortBy: 'created',
        todayIso,
      });
      assert.deepStrictEqual(composed.map((t) => t.id), ['t-b', 't-a']);

      // Adding priorityFilter narrows further
      const narrowed = filterTasksForView(tasks, {
        viewFilter: 'active',
        statusFilter: 'in_progress',
        priorityFilter: 'urgent',
        dueDateFilter: 'upcoming',
        projectIdFilter: projA.project.id,
        sectionTaskIds: backendSectionIds,
        tagFilters: ['backend', 'launch'],
        searchQuery: 'schema',
        sortBy: 'created',
        todayIso,
      });
      assert.deepStrictEqual(narrowed.map((t) => t.id), ['t-b']);

      // Active filter detection + Clear filters check
      assert.strictEqual(
        hasActiveTaskOrganizationFilters({
          statusFilter: 'in_progress',
          tagFilters: ['launch'],
        }),
        true
      );
      assert.strictEqual(
        hasActiveTaskOrganizationFilters({
          searchQuery: '   ',
          tagFilters: [],
        }),
        false
      );

      const cleared = filterTasksForView(tasks, {
        viewFilter: 'active',
        sortBy: 'priority',
        todayIso,
      });
      assert.strictEqual(cleared.length, 5);
    });
  });

  it('5. Layering & UI Consistency: taskOperations remains pure and DaywellTasksModule wires Stage 1.4 organization controls with zero hex literals', () => {
    const domainSource = fs.readFileSync(
      path.join(process.cwd(), 'src/domain/taskOperations.ts'),
      'utf8'
    );
    assert.ok(!domainSource.includes("from 'react'"));
    assert.ok(!domainSource.includes('document.'));
    assert.ok(!domainSource.includes('projectsService'));

    const uiSource = fs.readFileSync(
      path.join(process.cwd(), 'src/components/DaywellTasksModule.tsx'),
      'utf8'
    );
    assert.ok(uiSource.includes('DaywellSearchField'));
    assert.ok(uiSource.includes('Active ('));
    assert.ok(uiSource.includes('Overdue ('));
    assert.ok(uiSource.includes('Manage Tags'));
    assert.ok(uiSource.includes('Clear filters'));
    assert.ok(uiSource.includes('aria-label="Filter by status"'));
    assert.ok(uiSource.includes('aria-label="Filter by section"'));
    assert.ok(uiSource.includes('aria-label="Sort tasks by"'));
    assert.strictEqual(/#[0-9a-fA-F]{3,8}\b/.test(uiSource), false);
  });
});
