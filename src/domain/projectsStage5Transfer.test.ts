import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  BIM_OUTREACH_CAMPAIGN_TITLE,
  serializeBimOutreachTemplateJson,
} from './bimOutreachTemplate';
import {
  parseAndValidateProjectPackage,
  prepareProjectPackageForImport,
} from './projectPackage';
import { SharedProjectTrackingRecord } from './sharedFoundation';
import { WebProjectsRepository } from '../data/projectsRepository';
import { projectsService } from '../services/projectsService';

function withPersistentMockBrowserStorage(
  fn: (
    store: Map<string, string>,
    simulateBrowserRestart: () => void
  ) => void
): void {
  const store = new Map<string, string>();
  const dispatchedEvents: string[] = [];
  const prevWindow = (globalThis as any).window;
  const prevLocalStorage = (globalThis as any).localStorage;

  const bindGlobals = () => {
    (globalThis as any).localStorage = {
      getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
      setItem: (k: string, v: string) => void store.set(k, String(v)),
      removeItem: (k: string) => void store.delete(k),
      clear: () => void store.clear(),
    };
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
  };

  bindGlobals();
  try {
    fn(store, bindGlobals);
  } finally {
    (globalThis as any).window = prevWindow;
    (globalThis as any).localStorage = prevLocalStorage;
  }
}

describe('Daywell Projects Stage 5 — PC Workflow, Persistence & Bidirectional Transfer', () => {
  it('1. Supports full PC BIM workflow: load template, edit details/region/city/schedule, log batches, persist across reload, and export Android-compatible .daywellproject', () => {
    withPersistentMockBrowserStorage((store, simulateBrowserRestart) => {
      // 1. Load BIM template in Web Preview
      const templateJson = serializeBimOutreachTemplateJson();
      const imported = projectsService.importProjectPackage(templateJson);
      const projectId = imported.project.id;
      assert.strictEqual(imported.project.title, BIM_OUTREACH_CAMPAIGN_TITLE);

      let snapshot = projectsService.getProjectDetailSnapshot(projectId)!;
      assert.ok(snapshot);
      const groupedBlock = snapshot.blocks.find(
        (b) => b.blockType === 'grouped_list'
      )!;
      assert.ok(groupedBlock);

      const groups = snapshot.records.filter((r) => r.recordType === 'group');
      const cities = snapshot.records.filter(
        (r) => r.recordType === 'grouped_item'
      );
      assert.strictEqual(groups.length, 4);
      assert.strictEqual(cities.length, 100);

      // 2. Edit project details + create/edit a schedule session + edit a region & city entry
      const updatedProject = projectsService.updateProjectDetails({
        projectId,
        title: 'BIM Outreach Campaign — US Q4',
        description: 'Prepared on PC workspace for Android field tracking.',
        status: 'active',
        startDate: snapshot.project.startDate,
        targetDate: snapshot.project.targetDate,
        primaryBlockId: snapshot.summary.primaryBlockId,
      });
      assert.strictEqual(updatedProject.title, 'BIM Outreach Campaign — US Q4');

      const westRegion = groups.find((g) => (g.title ?? '').includes('West'))!;
      assert.ok(westRegion);
      projectsService.updateRecord({
        ...westRegion,
        title: 'West Coast Focus',
      });

      const seattle = cities.find((c) => (c.title ?? '').startsWith('Seattle,'))!;
      const portlandOr = cities.find(
        (c) => (c.title ?? '') === 'Portland, OR'
      )!;
      assert.ok(seattle);
      assert.ok(portlandOr);

      const originalSeattleTarget = seattle.targetValue ?? 10;
      projectsService.updateRecord({
        ...seattle,
        title: 'Seattle, WA (Priority)',
        targetValue: originalSeattleTarget + 5,
      });

      const scheduleBlock = projectsService.createBlock({
        projectId,
        blockType: 'schedule',
        title: 'Outreach Review Calls',
        config: {
          completionRule: 'manual',
          autoCompleteThresholdRatio: 1,
          trackActualDuration: true,
        },
      });
      const session = projectsService.createScheduleItem({
        projectId,
        blockId: scheduleBlock.id,
        title: 'Initial Sync',
        scheduledDate: '2026-11-20',
        durationMinutes: 30,
      });
      projectsService.updateRecord({
        ...session,
        title: 'Mid-Campaign Review Call',
        scheduledDate: '2026-11-25',
        durationMinutes: 45,
      });

      // 3. Record batch entries for cities (including an over-target batch + correction)
      const log1 = projectsService.logProgress({
        projectId,
        blockId: groupedBlock.id,
        parentRecordId: seattle.id,
        deltaValue: 10,
        recordedDate: '2026-11-18',
      });
      const portlandTarget = portlandOr.targetValue ?? 10;
      projectsService.logProgress({
        projectId,
        blockId: groupedBlock.id,
        parentRecordId: portlandOr.id,
        deltaValue: portlandTarget + 4,
        recordedDate: '2026-11-19',
      });
      projectsService.appendProgressCorrection({
        targetLogId: log1.id,
        correctionDelta: -2,
        recordedDate: '2026-11-18',
        reason: 'Bounced 2 test addresses',
      });

      // 4. Simulate browser refresh / close & reopen (localStorage preserved, fresh repo instance)
      assert.ok(store.has(WebProjectsRepository.PROJECTS_KEY));
      assert.ok(store.has(WebProjectsRepository.BLOCKS_KEY));
      assert.ok(store.has(WebProjectsRepository.RECORDS_KEY));
      simulateBrowserRestart();

      const freshRepo = new WebProjectsRepository();
      const persistedProject = freshRepo.getProjectById(projectId)!;
      assert.strictEqual(persistedProject.title, 'BIM Outreach Campaign — US Q4');

      const persistedRecords = freshRepo.getRecordsForProject(projectId);
      const persistedRegion = persistedRecords.find((r) => r.id === westRegion.id)!;
      const persistedSeattle = persistedRecords.find((r) => r.id === seattle.id)!;
      const persistedSession = persistedRecords.find((r) => r.id === session.id)!;
      assert.strictEqual(persistedRegion.title, 'West Coast Focus');
      assert.strictEqual(persistedSeattle.title, 'Seattle, WA (Priority)');
      assert.strictEqual(persistedSeattle.targetValue, originalSeattleTarget + 5);
      assert.strictEqual(persistedSession.title, 'Mid-Campaign Review Call');
      assert.strictEqual(persistedSession.scheduledDate, '2026-11-25');
      assert.strictEqual(persistedSession.durationMinutes, 45);

      const persistedSummary = freshRepo.getProjectProgressSummary(projectId);
      const persistedGroupMetric = persistedSummary.blockMetrics.find(
        (m) => m.blockId === groupedBlock.id
      )!;
      assert.strictEqual(persistedGroupMetric.itemTotals[seattle.id], 8);
      assert.strictEqual(
        persistedGroupMetric.itemTotals[portlandOr.id],
        portlandTarget + 4
      );
      assert.strictEqual(persistedGroupMetric.overTargetAmount, 4);
      assert.strictEqual(persistedGroupMetric.loggedTotal, 8 + portlandTarget + 4);
      assert.strictEqual(persistedGroupMetric.targetCompletedTotal, 8 + portlandTarget);

      // 5. Export from Web Preview and validate against Android ProjectPackageCodec contract
      const exported = projectsService.exportProjectPackage(projectId);
      assert.ok(exported.filename.endsWith('.daywellproject'));

      const validatedPkg = parseAndValidateProjectPackage(exported.json);
      assert.strictEqual(validatedPkg.formatId, 'daywell_project_package');
      assert.strictEqual(validatedPkg.formatVersion, 1);
      assert.strictEqual(validatedPkg.sourcePlatform, 'web');
      assert.strictEqual(validatedPkg.project.title, 'BIM Outreach Campaign — US Q4');
      assert.strictEqual(
        validatedPkg.project.customFields.primaryBlockId,
        persistedSummary.primaryBlockId
      );

      // Verify Android codec structural requirements:
      // - Cross-module links stripped
      assert.strictEqual(
        (validatedPkg.project as unknown as Record<string, unknown>).goalId,
        undefined
      );
      for (const rec of validatedPkg.trackingRecords) {
        assert.strictEqual(
          (rec as unknown as Record<string, unknown>).linkedTaskId,
          undefined
        );
      }
      // - Topological ordering (base blocks before rollups, groups before items, normal logs before corrections)
      let seenCorrection = false;
      const seenRecordIds = new Set<string>();
      for (const rec of validatedPkg.trackingRecords) {
        if (rec.parentRecordId) {
          assert.ok(
            seenRecordIds.has(rec.parentRecordId),
            `Parent record ${rec.parentRecordId} must precede child ${rec.id}`
          );
        }
        if (rec.recordType === 'progress_log' && rec.metadata?.isCorrection === true) {
          seenCorrection = true;
          const compId = String(rec.metadata.compensatesRecordId ?? '');
          assert.ok(
            seenRecordIds.has(compId),
            `Compensated log ${compId} must precede correction ${rec.id}`
          );
        } else if (rec.recordType === 'progress_log') {
          assert.strictEqual(seenCorrection, false);
        }
        seenRecordIds.add(rec.id);
      }

      // - Simulate Android import preparing collision-free remapped entities
      const androidPrepared = prepareProjectPackageForImport(exported.json, {
        existingProjectIds: [validatedPkg.project.id],
        existingBlockIds: validatedPkg.trackingBlocks.map((b) => b.id),
        existingRecordIds: validatedPkg.trackingRecords.map((r) => r.id),
      });
      assert.notStrictEqual(androidPrepared.project.id, validatedPkg.project.id);
      assert.strictEqual(androidPrepared.trackingBlocks.length, 2);
      assert.strictEqual(
        androidPrepared.trackingRecords.length,
        persistedRecords.length
      );
    });
  });

  it('2. Supports reverse transfer (Android Export -> Web Preview Import) creating a new ID-remapped project without overwriting existing projects', () => {
    withPersistentMockBrowserStorage((_store, simulateBrowserRestart) => {
      // Existing local Web project that shares exact raw IDs with the incoming Android package
      const existingWebProject = projectsService.createProjectWithBlocks({
        title: 'Existing Local Web Project',
        status: 'active',
        blocks: [
          {
            tempId: 'tmp-blk',
            blockType: 'counter',
            title: 'Local Pages',
            targetValue: 100,
          },
        ],
      });

      const androidPackagePayload = {
        formatId: 'daywell_project_package',
        formatVersion: 1,
        exportedAt: '2026-11-22T14:30:00.000Z',
        sourcePlatform: 'android',
        project: {
          id: existingWebProject.id,
          title: 'Android Field Survey',
          description: 'Exported from Android APK for PC review.',
          status: 'on_hold',
          startDate: '2026-11-18',
          targetDate: '2026-12-10',
          isArchived: false,
          customFields: {
            primaryBlockId: 'android-blk-list',
          },
          createdAt: '2026-11-18T08:00:00.000Z',
          updatedAt: '2026-11-22T14:25:00.000Z',
        },
        trackingBlocks: [
          {
            id: 'android-blk-list',
            projectId: existingWebProject.id,
            blockType: 'grouped_list',
            title: 'Cities Visited',
            sortOrder: 0,
            unitLabel: 'visits',
            targetValue: 20,
            dailyTargetValue: 2,
            config: {
              showGroupTotals: true,
              showDailyTotals: true,
              groupLabel: 'Region',
              itemLabel: 'City',
            },
            isArchived: false,
            createdAt: '2026-11-18T08:00:00.000Z',
            updatedAt: '2026-11-22T14:20:00.000Z',
          },
          {
            id: 'android-blk-rollup',
            projectId: existingWebProject.id,
            blockType: 'counter',
            title: 'Total Visits Mirror',
            sortOrder: 1,
            unitLabel: 'visits',
            targetValue: 20,
            config: {
              rollupSourceBlockId: 'android-blk-list',
              allowDirectLogging: false,
            },
            isArchived: false,
            createdAt: '2026-11-18T08:00:00.000Z',
            updatedAt: '2026-11-22T14:20:00.000Z',
          },
          {
            id: 'android-blk-sched',
            projectId: existingWebProject.id,
            blockType: 'schedule',
            title: 'Field Interviews',
            sortOrder: 2,
            config: {
              completionRule: 'exact_duration',
              autoCompleteThresholdRatio: 1,
              trackActualDuration: true,
            },
            isArchived: false,
            createdAt: '2026-11-18T08:00:00.000Z',
            updatedAt: '2026-11-22T14:20:00.000Z',
          },
          {
            id: 'android-blk-check',
            projectId: existingWebProject.id,
            blockType: 'checklist',
            title: 'Equipment Prep',
            sortOrder: 3,
            config: { allowReorder: true },
            isArchived: true,
            createdAt: '2026-11-18T08:00:00.000Z',
            updatedAt: '2026-11-22T14:20:00.000Z',
          },
        ],
        trackingRecords: [
          {
            id: 'android-grp-1',
            projectId: existingWebProject.id,
            blockId: 'android-blk-list',
            recordType: 'group',
            title: 'Northwest',
            sortOrder: 0,
            targetValue: 20,
            isCompleted: false,
            metadata: {},
            createdAt: '2026-11-18T08:01:00.000Z',
            updatedAt: '2026-11-18T08:01:00.000Z',
          },
          {
            id: 'android-item-1',
            projectId: existingWebProject.id,
            blockId: 'android-blk-list',
            parentRecordId: 'android-grp-1',
            recordType: 'grouped_item',
            title: 'Portland, OR',
            sortOrder: 0,
            targetValue: 20,
            isCompleted: false,
            metadata: {},
            createdAt: '2026-11-18T08:02:00.000Z',
            updatedAt: '2026-11-18T08:02:00.000Z',
          },
          {
            id: 'android-log-1',
            projectId: existingWebProject.id,
            blockId: 'android-blk-list',
            parentRecordId: 'android-item-1',
            recordType: 'progress_log',
            sortOrder: 0,
            deltaValue: 12,
            isCompleted: false,
            recordedDate: '2026-11-19',
            metadata: {},
            createdAt: '2026-11-19T10:00:00.000Z',
            updatedAt: '2026-11-19T10:00:00.000Z',
          },
          {
            id: 'android-corr-1',
            projectId: existingWebProject.id,
            blockId: 'android-blk-list',
            parentRecordId: 'android-item-1',
            recordType: 'progress_log',
            sortOrder: 1,
            deltaValue: -2,
            isCompleted: false,
            recordedDate: '2026-11-20',
            metadata: {
              isCorrection: true,
              compensatesRecordId: 'android-log-1',
              correctionReason: 'Duplicate field entry',
            },
            createdAt: '2026-11-20T11:00:00.000Z',
            updatedAt: '2026-11-20T11:00:00.000Z',
          },
          {
            id: 'android-sched-1',
            projectId: existingWebProject.id,
            blockId: 'android-blk-sched',
            recordType: 'schedule_item',
            title: 'Site Walkthrough',
            sortOrder: 0,
            scheduledDate: '2026-11-21',
            durationMinutes: 60,
            isCompleted: true,
            completedAt: '2026-11-21T16:00:00.000Z',
            metadata: {},
            createdAt: '2026-11-18T08:05:00.000Z',
            updatedAt: '2026-11-21T16:00:00.000Z',
          },
          {
            id: 'android-sched-log-1',
            projectId: existingWebProject.id,
            blockId: 'android-blk-sched',
            parentRecordId: 'android-sched-1',
            recordType: 'progress_log',
            sortOrder: 0,
            deltaValue: 60,
            isCompleted: false,
            recordedDate: '2026-11-21',
            metadata: {},
            createdAt: '2026-11-21T16:00:00.000Z',
            updatedAt: '2026-11-21T16:00:00.000Z',
          },
          {
            id: 'android-chk-1',
            projectId: existingWebProject.id,
            blockId: 'android-blk-check',
            recordType: 'checklist_item',
            title: 'Charge tablet',
            sortOrder: 0,
            isCompleted: true,
            completedAt: '2026-11-18T09:00:00.000Z',
            metadata: {},
            createdAt: '2026-11-18T08:06:00.000Z',
            updatedAt: '2026-11-18T09:00:00.000Z',
          },
        ],
      };

      const imported = projectsService.importProjectPackage(
        JSON.stringify(androidPackagePayload)
      );
      assert.strictEqual(imported.sourcePlatform, 'android');
      assert.notStrictEqual(imported.project.id, existingWebProject.id);
      assert.strictEqual(imported.project.title, 'Android Field Survey');
      assert.strictEqual(imported.project.status, 'on_hold');
      assert.strictEqual(imported.project.startDate, '2026-11-18');
      assert.strictEqual(imported.project.targetDate, '2026-12-10');

      // Existing Web project remains intact and unmodified
      const existingAfter = projectsService.getProject(existingWebProject.id)!;
      assert.strictEqual(existingAfter.title, 'Existing Local Web Project');

      // Simulate browser reload & re-inspect imported snapshot
      simulateBrowserRestart();
      const snapshot = projectsService.getProjectDetailSnapshot(
        imported.project.id
      )!;
      assert.ok(snapshot);
      assert.strictEqual(snapshot.blocks.length, 4);
      const listBlock = snapshot.blocks.find((b) => b.blockType === 'grouped_list')!;
      const rollupBlock = snapshot.blocks.find((b) => b.blockType === 'counter')!;
      const archivedCheck = snapshot.blocks.find(
        (b) => b.blockType === 'checklist'
      )!;
      assert.strictEqual(snapshot.summary.primaryBlockId, listBlock.id);
      assert.strictEqual(
        rollupBlock.config?.rollupSourceBlockId,
        listBlock.id
      );
      assert.strictEqual(archivedCheck.isArchived, true);

      const listMetric = snapshot.summary.blockMetrics.find(
        (m) => m.blockId === listBlock.id
      )!;
      const rollupMetric = snapshot.summary.blockMetrics.find(
        (m) => m.blockId === rollupBlock.id
      )!;
      assert.strictEqual(listMetric.loggedTotal, 10);
      assert.strictEqual(listMetric.progressPercent, 50);
      assert.strictEqual(rollupMetric.loggedTotal, 10);
      assert.strictEqual(Math.round(snapshot.summary.overallPercentage ?? 0), 50);

      // Verify chronological history preserves original log + correction chain
      const history = projectsService.getChronologicalProgressHistory(
        imported.project.id
      );
      const correction = history.find((h) => h.isCorrection)!;
      const origLog = history.find(
        (h) => !h.isCorrection && h.blockType === 'grouped_list'
      )!;
      assert.ok(correction);
      assert.ok(origLog);
      assert.strictEqual(correction.compensatesRecordId, origLog.record.id);
      assert.strictEqual(correction.correctionReason, 'Duplicate field entry');

      // Verify continuing work on Web (e.g. editing imported session & logging batch)
      const importedItem = snapshot.records.find(
        (r: SharedProjectTrackingRecord) => r.recordType === 'grouped_item'
      )!;
      projectsService.logProgress({
        projectId: imported.project.id,
        blockId: listBlock.id,
        parentRecordId: importedItem.id,
        deltaValue: 10,
        recordedDate: '2026-11-23',
      });
      const afterMoreProgress = projectsService.getProjectDetailSnapshot(
        imported.project.id
      )!;
      assert.strictEqual(
        Math.round(afterMoreProgress.summary.overallPercentage ?? 0),
        100
      );
    });
  });
});
