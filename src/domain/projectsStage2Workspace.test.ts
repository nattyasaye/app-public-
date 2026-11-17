import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { ProjectValidationError } from './projectsEngine';
import { projectsService } from '../services/projectsService';
import { SharedStateBridge } from '../services/sharedStateBridge';

function withMockBrowserStorage(
  fn: (store: Map<string, string>, dispatchedEvents: string[]) => void
): void {
  const store = new Map<string, string>();
  const dispatchedEvents: string[] = [];
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
    dispatchEvent: (ev: { type?: string }) => {
      if (ev?.type) dispatchedEvents.push(ev.type);
      return true;
    },
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
    fn(store, dispatchedEvents);
  } finally {
    (globalThis as any).window = prevWindow;
    (globalThis as any).localStorage = prevLocalStorage;
  }
}

describe('Daywell Projects Stage 2 — Workspace UI & Service Flows', () => {
  it('1. Creates a project with inline non-rollup + rollup blocks and resolves primaryDraftTempId cleanly', () => {
    withMockBrowserStorage((_store, events) => {
      const created = projectsService.createProjectWithBlocks({
        title: 'Stage 2 Thesis Draft',
        description: 'Multi-block research tracking',
        status: 'active',
        startDate: '2026-11-01',
        targetDate: '2026-12-01',
        primaryDraftTempId: 'draft-rollup',
        blocks: [
          {
            tempId: 'draft-rollup',
            blockType: 'counter',
            title: 'Total Chapters Read (Rollup)',
            unitLabel: 'pages',
            targetValue: 100,
            config: {
              rollupSourceBlockId: 'draft-sections',
              allowDirectLogging: false,
            },
          },
          {
            tempId: 'draft-sections',
            blockType: 'grouped_list',
            title: 'Sections',
            unitLabel: 'pages',
            config: {
              showGroupTotals: true,
              showDailyTotals: true,
            },
          },
        ],
      });

      const snapshot = projectsService.getProjectDetailSnapshot(created.id);
      assert.ok(snapshot, 'Detail snapshot should exist');
      assert.strictEqual(snapshot.blocks.length, 2);

      const sections = snapshot.blocks.find((b) => b.blockType === 'grouped_list');
      const rollup = snapshot.blocks.find((b) => b.blockType === 'counter');
      assert.ok(sections && rollup);
      assert.strictEqual(rollup.config?.rollupSourceBlockId, sections.id);
      assert.strictEqual(rollup.config?.allowDirectLogging, false);
      assert.strictEqual(created.customFields?.primaryBlockId, rollup.id);
      assert.strictEqual(snapshot.summary.primaryBlockId, rollup.id);
      assert.strictEqual(snapshot.summary.hasInvalidPrimaryBlockReference, false);
      assert.ok(events.includes(SharedStateBridge.SYNC_EVENT_NAME));
    });
  });

  it('2. Supports grouped_list, checklist, schedule rule auto-completion, and compensating adjustments', () => {
    withMockBrowserStorage(() => {
      const proj = projectsService.createProjectWithBlocks({
        title: 'Course Study Plan',
        status: 'active',
        primaryDraftTempId: 'chk-1',
        blocks: [
          {
            tempId: 'grp-1',
            blockType: 'grouped_list',
            title: 'Modules',
            unitLabel: 'exercises',
            targetValue: 10,
          },
          {
            tempId: 'chk-1',
            blockType: 'checklist',
            title: 'Milestones',
          },
          {
            tempId: 'sch-auto',
            blockType: 'schedule',
            title: 'Threshold Study Sessions',
            config: {
              completionRule: 'threshold_percent',
              autoCompleteThresholdRatio: 0.8,
              trackActualDuration: true,
            },
          },
          {
            tempId: 'sch-manual',
            blockType: 'schedule',
            title: 'Manual Review Sessions',
            config: {
              completionRule: 'manual',
              autoCompleteThresholdRatio: 1.0,
              trackActualDuration: true,
            },
          },
        ],
      });

      const detail0 = projectsService.getProjectDetailSnapshot(proj.id)!;
      const grpBlk = detail0.blocks.find((b) => b.blockType === 'grouped_list')!;
      const chkBlk = detail0.blocks.find((b) => b.blockType === 'checklist')!;
      const schAutoBlk = detail0.blocks.find((b) => b.title === 'Threshold Study Sessions')!;
      const schManualBlk = detail0.blocks.find((b) => b.title === 'Manual Review Sessions')!;

      // Grouped list item + log
      const group = projectsService.createGroup({
        projectId: proj.id,
        blockId: grpBlk.id,
        title: 'Week 1',
      });
      const item = projectsService.createGroupedItem({
        projectId: proj.id,
        blockId: grpBlk.id,
        groupId: group.id,
        title: 'Algebra drills',
        targetValue: 5,
      });
      const firstLog = projectsService.logProgress({
        projectId: proj.id,
        blockId: grpBlk.id,
        parentRecordId: item.id,
        deltaValue: 8,
        recordedDate: '2026-11-17',
        title: 'Completed exercises',
      });

      // Compensating adjustment requires non-empty reason
      assert.throws(() => {
        projectsService.appendProgressCorrection({
          targetLogId: firstLog.id,
          correctionDelta: -3,
          recordedDate: '2026-11-17',
          reason: '   ',
        });
      });

      projectsService.appendProgressCorrection({
        targetLogId: firstLog.id,
        correctionDelta: -3,
        recordedDate: '2026-11-17',
        reason: 'Miscounted solved items',
      });

      // Checklist toggle
      const chkItem = projectsService.createChecklistItem({
        projectId: proj.id,
        blockId: chkBlk.id,
        title: 'Submit outline',
      });
      projectsService.toggleRecordCompleted(chkItem);

      // Schedule auto-complete at 80% threshold vs manual staying incomplete
      const autoSession = projectsService.createScheduleItem({
        projectId: proj.id,
        blockId: schAutoBlk.id,
        title: 'Lecture 1',
        scheduledDate: '2026-11-17',
        durationMinutes: 100,
      });
      projectsService.logProgress({
        projectId: proj.id,
        blockId: schAutoBlk.id,
        parentRecordId: autoSession.id,
        deltaValue: 80,
        recordedDate: '2026-11-17',
      });

      const manualSession = projectsService.createScheduleItem({
        projectId: proj.id,
        blockId: schManualBlk.id,
        title: 'Workshop 1',
        scheduledDate: '2026-11-17',
        durationMinutes: 60,
      });
      projectsService.logProgress({
        projectId: proj.id,
        blockId: schManualBlk.id,
        parentRecordId: manualSession.id,
        deltaValue: 60,
        recordedDate: '2026-11-17',
      });

      const detail1 = projectsService.getProjectDetailSnapshot(proj.id)!;
      const grpMetric = detail1.summary.blockMetrics.find((m) => m.blockId === grpBlk.id)!;
      assert.strictEqual(grpMetric.loggedTotal, 5); // 8 - 3 = 5

      assert.strictEqual(detail1.summary.overallPercentage, 100); // checklist 1/1 = 100%

      const updatedAuto = detail1.records.find((r) => r.id === autoSession.id)!;
      const updatedManual = detail1.records.find((r) => r.id === manualSession.id)!;
      assert.strictEqual(updatedAuto.isCompleted, true);
      assert.strictEqual(updatedManual.isCompleted, false);

      const history = projectsService.getChronologicalProgressHistory(proj.id);
      assert.strictEqual(history.length, 4);
      assert.ok(history.some((h) => h.isCorrection && h.correctionReason === 'Miscounted solved items'));
    });
  });

  it('3. Enforces archive-first lifecycle rule before permanent deletion and detaches linked tasks', () => {
    withMockBrowserStorage((store) => {
      const proj = projectsService.createProjectWithBlocks({
        title: 'Archivable Project',
        status: 'active',
        blocks: [
          {
            tempId: 'cnt-1',
            blockType: 'counter',
            title: 'Steps',
            targetValue: 10,
          },
        ],
      });

      store.set(
        'daywell_tasks',
        JSON.stringify([
          {
            id: 'task-linked-1',
            title: 'Linked Task',
            status: 'not_started',
            priority: 'medium',
            projectId: proj.id,
            subtasks: [],
            labels: [],
            isPinned: false,
            isMyDay: false,
            createdAt: '2026-11-17T08:00:00.000Z',
            updatedAt: '2026-11-17T08:00:00.000Z',
          },
        ])
      );

      assert.throws(
        () => projectsService.deleteArchivedProject(proj.id),
        ProjectValidationError
      );

      const archived = projectsService.setProjectArchived(proj.id, true);
      assert.strictEqual(archived.isArchived, true);

      projectsService.deleteArchivedProject(proj.id);
      assert.strictEqual(projectsService.getProject(proj.id), undefined);

      const remainingTasks = JSON.parse(store.get('daywell_tasks') || '[]');
      assert.strictEqual(remainingTasks.length, 1);
      assert.strictEqual(remainingTasks[0].projectId, undefined);
    });
  });

  it('4. Routes Web prototype project entries into live Tasks > Projects and keeps Flutter Stage 2 token-clean', () => {
    const repoRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..', '..');
    const appSource = fs.readFileSync(path.join(repoRoot, 'src', 'App.tsx'), 'utf8');
    const tasksModuleSource = fs.readFileSync(
      path.join(repoRoot, 'src', 'components', 'DaywellTasksModule.tsx'),
      'utf8'
    );

    assert.strictEqual(
      appSource.includes("target === 'projects' || target === 'project_detail'"),
      true
    );
    assert.strictEqual(appSource.includes("activeScreen === 'projects'"), false);
    assert.strictEqual(appSource.includes("activeScreen === 'project_detail'"), false);
    assert.ok(tasksModuleSource.includes('ProjectsWorkspaceView'));

    const flutterProjectsDir = path.join(
      repoRoot,
      'flutter_app',
      'lib',
      'ui',
      'screens',
      'projects'
    );
    const dartFiles = fs
      .readdirSync(flutterProjectsDir)
      .filter((f) => f.endsWith('.dart'));
    assert.ok(dartFiles.length >= 5);

    for (const file of dartFiles) {
      const src = fs.readFileSync(path.join(flutterProjectsDir, file), 'utf8');
      assert.strictEqual(
        /Color\(\s*0x/i.test(src),
        false,
        `${file} must contain 0 Color(0x...) literals`
      );
      assert.strictEqual(
        /\bColors\.[a-zA-Z0-9_]+/.test(src),
        false,
        `${file} must contain 0 Material Colors.* literals`
      );
    }
  });
});
