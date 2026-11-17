import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { CalendarDate } from './date';
import {
  buildProjectPackageFilename,
  parseAndValidateProjectPackage,
  prepareProjectPackageForImport,
  ProjectPackageError,
  serializeProjectPackage,
} from './projectPackage';
import { SHARED_PROJECT_PACKAGE_SPEC } from './sharedFoundation';
import { projectsService } from '../services/projectsService';
import { WebProjectsRepository } from '../data/projectsRepository';

const REPO_ROOT = path.resolve(
  path.dirname(new URL(import.meta.url).pathname),
  '..',
  '..'
);

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

describe('Daywell Projects Stage 3 — Portable .daywellproject Package Format, Import & Export', () => {
  it('1. Parses canonical shared fixture v1, imports into Web storage, preserves all 4 block types, archived blocks, rollups, corrections & metrics', () => {
    withMockBrowserStorage((_store, events) => {
      const fixturePath = path.join(
        REPO_ROOT,
        'shared_foundation',
        'fixtures',
        'sample_project_package_v1.json'
      );
      const fixtureJson = fs.readFileSync(fixturePath, 'utf8');
      const parsed = parseAndValidateProjectPackage(fixtureJson);

      assert.strictEqual(parsed.formatId, SHARED_PROJECT_PACKAGE_SPEC.formatId);
      assert.strictEqual(
        parsed.formatVersion,
        SHARED_PROJECT_PACKAGE_SPEC.currentFormatVersion
      );
      assert.strictEqual(parsed.trackingBlocks.length, 6);
      assert.strictEqual(parsed.trackingRecords.length, 11);

      const imported = projectsService.importProjectPackage(fixtureJson);
      assert.strictEqual(imported.project.title, 'Home Studio Build & Curriculum');
      assert.notStrictEqual(imported.project.id, parsed.project.id);
      assert.strictEqual(imported.project.goalId, undefined);
      assert.ok(events.length >= 1);

      const detail = projectsService.getProjectDetailSnapshot(imported.project.id, {
        asOfDate: CalendarDate.parse('2026-11-12'),
      });
      assert.ok(detail);
      assert.strictEqual(detail.blocks.length, 6);
      assert.strictEqual(detail.records.length, 11);

      const archivedBlock = detail.blocks.find((b) => b.isArchived);
      assert.ok(archivedBlock, 'Archived block should be preserved on import');
      assert.strictEqual(archivedBlock.title, 'Legacy Draft Notes');

      const rollupBlock = detail.blocks.find(
        (b) => b.blockType === 'counter' && b.config?.rollupSourceBlockId
      )!;
      const groupedBlock = detail.blocks.find((b) => b.blockType === 'grouped_list')!;
      const scheduleBlock = detail.blocks.find((b) => b.blockType === 'schedule')!;
      const checklistBlock = detail.blocks.find((b) => b.blockType === 'checklist')!;

      assert.strictEqual(rollupBlock.config?.rollupSourceBlockId, groupedBlock.id);
      assert.strictEqual(detail.project.customFields?.primaryBlockId, rollupBlock.id);

      const rollupMetric = detail.summary.blockMetrics.find(
        (m) => m.blockId === rollupBlock.id
      )!;
      const groupedMetric = detail.summary.blockMetrics.find(
        (m) => m.blockId === groupedBlock.id
      )!;
      const scheduleMetric = detail.summary.blockMetrics.find(
        (m) => m.blockId === scheduleBlock.id
      )!;
      const checklistMetric = detail.summary.blockMetrics.find(
        (m) => m.blockId === checklistBlock.id
      )!;
      const archivedMetric = detail.summary.blockMetrics.find(
        (m) => m.blockId === archivedBlock.id
      )!;

      // 12 - 2 compensating correction = 10 hours
      assert.strictEqual(groupedMetric.loggedTotal, 10);
      assert.strictEqual(rollupMetric.loggedTotal, 10);
      assert.strictEqual(Math.round(detail.summary.overallPercentage ?? 0), 33);
      assert.strictEqual(checklistMetric.completedCount, 1);
      assert.strictEqual(checklistMetric.totalCount, 2);
      assert.strictEqual(scheduleMetric.plannedDurationMinutes, 60);
      assert.strictEqual(scheduleMetric.actualLoggedDurationMinutes, 50);
      assert.strictEqual(archivedMetric.loggedTotal, 3);

      const history = projectsService.getChronologicalProgressHistory(
        imported.project.id
      );
      assert.strictEqual(history.length, 5);
      const correctionEntry = history.find((h) => h.isCorrection);
      assert.ok(correctionEntry);
      assert.strictEqual(
        correctionEntry.correctionReason,
        'Logged 2 extra hours by mistake'
      );
      assert.notStrictEqual(correctionEntry.compensatesRecordId, 'fx-rec-log-grp1');
      assert.ok(
        detail.records.some((r) => r.id === correctionEntry.compensatesRecordId)
      );
    });
  });

  it('2. Round-trips Web-created projects through export & double-import, keeping original titles and stripping goalId/linkedTaskId', () => {
    withMockBrowserStorage((store) => {
      // Seed unrelated Goal and Tasks to verify scope isolation + linkedTaskId stripping
      store.set(
        'daywell_goals',
        JSON.stringify([
          {
            id: 'goal-secret',
            title: 'Private Goal',
            createdAt: '2026-11-01T00:00:00.000Z',
          },
        ])
      );
      store.set(
        'daywell_tasks',
        JSON.stringify([
          {
            id: 'task-ref-1',
            title: 'Unrelated or Linked Task',
            status: 'not_started',
            priority: 'medium',
            subtasks: [],
            labels: [],
            isPinned: false,
            isMyDay: false,
            createdAt: '2026-11-01T00:00:00.000Z',
            updatedAt: '2026-11-01T00:00:00.000Z',
          },
        ])
      );

      const created = projectsService.createProjectWithBlocks({
        title: 'Construction Tracker',
        description: 'Site inspection & pours',
        status: 'active',
        startDate: '2026-11-01',
        targetDate: '2026-12-20',
        goalId: 'goal-secret',
        primaryDraftTempId: 'cnt-main',
        blocks: [
          {
            tempId: 'cnt-main',
            blockType: 'counter',
            title: 'Concrete Batches',
            unitLabel: 'batches',
            targetValue: 20,
          },
          {
            tempId: 'sch-main',
            blockType: 'schedule',
            title: 'Safety Walkthroughs',
            unitLabel: 'minutes',
            config: {
              completionRule: 'threshold_percent',
              autoCompleteThresholdRatio: 0.8,
              trackActualDuration: true,
            },
          },
        ],
      });

      const detail0 = projectsService.getProjectDetailSnapshot(created.id)!;
      const cntBlk = detail0.blocks.find((b) => b.blockType === 'counter')!;
      const schBlk = detail0.blocks.find((b) => b.blockType === 'schedule')!;

      const log1 = projectsService.logProgress({
        projectId: created.id,
        blockId: cntBlk.id,
        deltaValue: 8,
        recordedDate: '2026-11-15',
        title: 'Foundation pour',
      });
      projectsService.appendProgressCorrection({
        targetLogId: log1.id,
        correctionDelta: -1,
        recordedDate: '2026-11-15',
        reason: 'Adjusted batch ticket count',
      });

      const schItem = projectsService.createScheduleItem({
        projectId: created.id,
        blockId: schBlk.id,
        title: 'Rebar check',
        scheduledDate: '2026-11-16',
        durationMinutes: 50,
      });
      // Inject linkedTaskId onto schedule item in repository storage
      const repo = new WebProjectsRepository();
      repo.updateRecord({ ...schItem, linkedTaskId: 'task-ref-1' });
      projectsService.setBlockArchived(schBlk.id, true);

      const exported = projectsService.exportProjectPackage(created.id);
      assert.strictEqual(
        exported.filename,
        'construction-tracker.daywellproject'
      );

      const exportedObj = JSON.parse(exported.json);
      assert.strictEqual(exportedObj.formatId, 'daywell_project_package');
      assert.strictEqual(exportedObj.formatVersion, 1);
      assert.strictEqual('goalId' in exportedObj.project, false);
      for (const rec of exportedObj.trackingRecords) {
        assert.strictEqual('linkedTaskId' in rec, false);
      }
      // Verify unrelated/finance data is NOT in package
      assert.strictEqual('accounts' in exportedObj, false);
      assert.strictEqual('tasks' in exportedObj, false);

      // Even if a crafted package injects goalId / linkedTaskId, import strips them
      exportedObj.project.goalId = 'goal-secret';
      exportedObj.trackingRecords[0].linkedTaskId = 'task-ref-1';
      const craftedJson = JSON.stringify(exportedObj);

      // Import twice -> 2 new projects keeping exact original title, zero collisions
      const importA = projectsService.importProjectPackage(craftedJson);
      const importB = projectsService.importProjectPackage(craftedJson);

      const allProjects = projectsService.listProjects({ includeArchived: true });
      assert.strictEqual(allProjects.length, 3);
      assert.strictEqual(
        allProjects.filter((p) => p.title === 'Construction Tracker').length,
        3
      );

      assert.notStrictEqual(importA.project.id, created.id);
      assert.notStrictEqual(importB.project.id, created.id);
      assert.notStrictEqual(importA.project.id, importB.project.id);
      assert.strictEqual(importA.project.goalId, undefined);
      assert.strictEqual(importB.project.goalId, undefined);
      for (const rec of [...importA.trackingRecords, ...importB.trackingRecords]) {
        assert.strictEqual(rec.linkedTaskId, undefined);
      }

      const snapOrig = projectsService.getProjectDetailSnapshot(created.id, {
        asOfDate: CalendarDate.parse('2026-11-16'),
      })!;
      const snapA = projectsService.getProjectDetailSnapshot(importA.project.id, {
        asOfDate: CalendarDate.parse('2026-11-16'),
      })!;
      assert.strictEqual(
        snapA.summary.overallPercentage,
        snapOrig.summary.overallPercentage
      );
      assert.strictEqual(snapA.blocks.filter((b) => b.isArchived).length, 1);
    });
  });

  it('3. Rejects malformed JSON, wrong formatId, future/zero formatVersion, dangling references, and preserves existing projects atomically on failure', () => {
    withMockBrowserStorage((store) => {
      const existing = projectsService.createProjectWithBlocks({
        title: 'Existing Untouched Project',
        status: 'active',
        blocks: [
          {
            tempId: 'cnt-existing',
            blockType: 'counter',
            title: 'Calls',
            targetValue: 10,
          },
        ],
      });
      const beforeProjectsJson = store.get('daywell_projects');
      const beforeBlocksJson = store.get('daywell_project_tracking_blocks');
      const beforeRecordsJson = store.get('daywell_project_tracking_records');

      const fixtureJson = fs.readFileSync(
        path.join(
          REPO_ROOT,
          'shared_foundation',
          'fixtures',
          'sample_project_package_v1.json'
        ),
        'utf8'
      );
      const validPkg = JSON.parse(fixtureJson);

      const expectImportFailsUntouched = (
        input: string,
        expectedKind: ProjectPackageError['kind']
      ) => {
        assert.throws(
          () => projectsService.importProjectPackage(input),
          (err: unknown) =>
            err instanceof ProjectPackageError && err.kind === expectedKind
        );
        assert.strictEqual(store.get('daywell_projects'), beforeProjectsJson);
        assert.strictEqual(
          store.get('daywell_project_tracking_blocks'),
          beforeBlocksJson
        );
        assert.strictEqual(
          store.get('daywell_project_tracking_records'),
          beforeRecordsJson
        );
        assert.ok(projectsService.getProject(existing.id));
      };

      // Malformed / empty JSON
      expectImportFailsUntouched('', 'malformed_json');
      expectImportFailsUntouched('{bad json', 'malformed_json');

      // Wrong formatId
      const badFormat = structuredClone(validPkg);
      badFormat.formatId = 'wrong_format';
      expectImportFailsUntouched(JSON.stringify(badFormat), 'invalid_format');

      // Future formatVersion 2 & zero version 0
      const futureVer = structuredClone(validPkg);
      futureVer.formatVersion = 2;
      expectImportFailsUntouched(
        JSON.stringify(futureVer),
        'unsupported_version'
      );

      const zeroVer = structuredClone(validPkg);
      zeroVer.formatVersion = 0;
      expectImportFailsUntouched(
        JSON.stringify(zeroVer),
        'unsupported_version'
      );

      // Missing project title
      const missingTitle = structuredClone(validPkg);
      missingTitle.project.title = '   ';
      expectImportFailsUntouched(
        JSON.stringify(missingTitle),
        'validation_failed'
      );

      // Dangling primaryBlockId
      const badPrimary = structuredClone(validPkg);
      badPrimary.project.customFields.primaryBlockId = 'blk-does-not-exist';
      expectImportFailsUntouched(
        JSON.stringify(badPrimary),
        'validation_failed'
      );

      // Dangling rollupSourceBlockId
      const badRollup = structuredClone(validPkg);
      badRollup.trackingBlocks.find(
        (b: any) => b.id === 'fx-blk-rollup'
      ).config.rollupSourceBlockId = 'blk-missing';
      expectImportFailsUntouched(
        JSON.stringify(badRollup),
        'validation_failed'
      );

      // Dangling record blockId
      const badRecordBlock = structuredClone(validPkg);
      badRecordBlock.trackingRecords[0].blockId = 'blk-missing';
      expectImportFailsUntouched(
        JSON.stringify(badRecordBlock),
        'validation_failed'
      );

      // Dangling parentRecordId
      const badParent = structuredClone(validPkg);
      badParent.trackingRecords.find(
        (r: any) => r.id === 'fx-rec-item-1'
      ).parentRecordId = 'rec-missing';
      expectImportFailsUntouched(
        JSON.stringify(badParent),
        'validation_failed'
      );

      // Dangling compensatesRecordId
      const badCompensates = structuredClone(validPkg);
      badCompensates.trackingRecords.find(
        (r: any) => r.id === 'fx-rec-corr-grp1'
      ).metadata.compensatesRecordId = 'log-missing';
      expectImportFailsUntouched(
        JSON.stringify(badCompensates),
        'validation_failed'
      );

      // Invalid canonical date
      const badDate = structuredClone(validPkg);
      badDate.project.startDate = '2026-02-30';
      expectImportFailsUntouched(JSON.stringify(badDate), 'validation_failed');
    });
  });

  it('4. Filename helper sanitizes titles and prepareProjectPackageForImport handles out-of-order blocks/records cleanly', () => {
    assert.strictEqual(
      buildProjectPackageFilename('BIM Outreach (2026)!'),
      'bim-outreach-2026.daywellproject'
    );
    assert.strictEqual(
      buildProjectPackageFilename('   '),
      'daywell-project.daywellproject'
    );

    const fixtureJson = fs.readFileSync(
      path.join(
        REPO_ROOT,
        'shared_foundation',
        'fixtures',
        'sample_project_package_v1.json'
      ),
      'utf8'
    );
    const reversed = JSON.parse(fixtureJson);
    reversed.trackingBlocks.reverse();
    reversed.trackingRecords.reverse();

    const prepared = prepareProjectPackageForImport(JSON.stringify(reversed));
    assert.strictEqual(prepared.trackingBlocks.length, 6);
    assert.strictEqual(prepared.trackingRecords.length, 11);

    // Re-serializing prepared bundle produces valid v1 JSON
    const reserialized = serializeProjectPackage({
      project: prepared.project,
      blocks: prepared.trackingBlocks,
      records: prepared.trackingRecords,
    });
    const reparsed = parseAndValidateProjectPackage(reserialized);
    assert.strictEqual(reparsed.project.title, prepared.project.title);
  });
});
