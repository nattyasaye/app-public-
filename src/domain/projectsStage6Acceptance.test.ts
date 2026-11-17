import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { CalendarDate } from './date';
import {
  BIM_OUTREACH_CAMPAIGN_DAILY_TARGET,
  BIM_OUTREACH_CAMPAIGN_TARGET_TOTAL,
  BIM_OUTREACH_CAMPAIGN_TITLE,
  BIM_OUTREACH_CITIES,
  US_CENSUS_REGION_ORDER,
  serializeBimOutreachTemplateJson,
} from './bimOutreachTemplate';
import {
  DaywellProjectPackageV1,
  ProjectPackageError,
  buildProjectPackageFilename,
  parseAndValidateProjectPackage,
  prepareProjectPackageForImport,
  serializeProjectPackage,
} from './projectPackage';
import {
  ProjectValidationError,
  getProjectScheduleSpan,
} from './projectsEngine';
import { SharedGoal, SharedProjectTrackingRecord } from './sharedFoundation';
import { WebProjectsRepository } from '../data/projectsRepository';
import { projectsService } from '../services/projectsService';

const REPO_ROOT = path.resolve(
  path.dirname(new URL(import.meta.url).pathname),
  '..',
  '..'
);

function withMockBrowserSession(
  fn: (
    store: Map<string, string>,
    simulateBrowserRefresh: () => void
  ) => void
): void {
  const store = new Map<string, string>();
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
  };

  bindGlobals();
  try {
    fn(store, bindGlobals);
  } finally {
    (globalThis as any).window = prevWindow;
    (globalThis as any).localStorage = prevLocalStorage;
  }
}

function assertPackageInvariantParity(pkg: DaywellProjectPackageV1): void {
  assert.strictEqual(pkg.formatId, 'daywell_project_package');
  assert.strictEqual(pkg.formatVersion, 1);
  assert.strictEqual(
    (pkg.project as unknown as Record<string, unknown>).goalId,
    undefined
  );

  // Topological order of tracking blocks: non-rollup blocks must precede rollup counters
  const seenBlockIds = new Set<string>();
  for (const blk of pkg.trackingBlocks) {
    assert.strictEqual(blk.projectId, pkg.project.id);
    const rollupSource = blk.config?.rollupSourceBlockId;
    if (blk.blockType === 'counter' && typeof rollupSource === 'string') {
      assert.ok(
        seenBlockIds.has(rollupSource),
        `Rollup block ${blk.id} references unseen source ${rollupSource}`
      );
    }
    seenBlockIds.add(blk.id);
  }

  // Topological order of records: parents precede children; normal logs precede corrections
  const seenRecordIds = new Set<string>();
  let seenCorrection = false;
  for (const rec of pkg.trackingRecords) {
    assert.strictEqual(rec.projectId, pkg.project.id);
    assert.ok(seenBlockIds.has(rec.blockId));
    assert.strictEqual(
      (rec as unknown as Record<string, unknown>).linkedTaskId,
      undefined
    );
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
        `Compensated record ${compId} must precede correction ${rec.id}`
      );
    } else if (rec.recordType === 'progress_log') {
      assert.strictEqual(
        seenCorrection,
        false,
        'Non-correction progress_log must precede corrections'
      );
    }
    seenRecordIds.add(rec.id);
  }
}

describe('Daywell Projects Stage 6 — Final End-to-End Integration & Acceptance', () => {
  it('A & B: Web Preview BIM campaign workflow, over-target preservation, correction coherence, reload persistence, and Android package parity', () => {
    withMockBrowserSession((store, simulateBrowserRefresh) => {
      // 1. Load canonical BIM fixture & confirm byte parity with Web template builder
      const fixturePath = path.join(
        REPO_ROOT,
        'shared_foundation',
        'fixtures',
        'bim_outreach_campaign_v1.daywellproject'
      );
      const fixtureJson = fs.readFileSync(fixturePath, 'utf8');
      assert.strictEqual(fixtureJson, serializeBimOutreachTemplateJson());

      const imported = projectsService.importProjectPackage(fixtureJson);
      const projectId = imported.project.id;
      assert.strictEqual(imported.project.title, BIM_OUTREACH_CAMPAIGN_TITLE);
      assert.strictEqual(imported.project.startDate, '2026-11-18');
      assert.strictEqual(imported.project.targetDate, '2026-12-09');

      // 2. Confirm all 100 cities and their exact assigned targets
      const initialSnap = projectsService.getProjectDetailSnapshot(projectId, {
        asOfDate: CalendarDate.parse('2026-11-18'),
      })!;
      const block = initialSnap.blocks[0];
      assert.strictEqual(block.blockType, 'grouped_list');
      assert.strictEqual(block.targetValue, BIM_OUTREACH_CAMPAIGN_TARGET_TOTAL);
      assert.strictEqual(block.dailyTargetValue, BIM_OUTREACH_CAMPAIGN_DAILY_TARGET);

      const cityRecords = initialSnap.records.filter(
        (r) => r.recordType === 'grouped_item'
      );
      const regionRecords = initialSnap.records.filter(
        (r) => r.recordType === 'group'
      );
      assert.strictEqual(cityRecords.length, 100);
      assert.strictEqual(regionRecords.length, 4);

      const expectedCityTargetByTitle = new Map(
        BIM_OUTREACH_CITIES.map((c) => [`${c.city}, ${c.state}`, c.target])
      );
      for (const cityRec of cityRecords) {
        const expectedTarget = expectedCityTargetByTitle.get(cityRec.title ?? '');
        assert.ok(expectedTarget !== undefined, `Unexpected city ${cityRec.title}`);
        assert.strictEqual(cityRec.targetValue, expectedTarget);
      }

      // Verify Ethiopian dates and schedule span match Hidar 9–30, 2019 E.C.
      const span = getProjectScheduleSpan(
        initialSnap.project,
        CalendarDate.parse('2026-11-18')
      );
      assert.strictEqual(span.totalDays, 22);
      assert.strictEqual(span.remainingDays, 22);

      // 3. Record multiple batches for different cities across multiple regions & days
      const findCity = (title: string) =>
        cityRecords.find((c) => c.title === title)!;
      const nyc = findCity('New York, NY'); // target 30 (Northeast)
      const chicago = findCity('Chicago, IL'); // target 24 (Midwest)
      const houston = findCity('Houston, TX'); // target 22 (South)
      const losAngeles = findCity('Los Angeles, CA'); // target 28 (West)

      const nycBatch1 = projectsService.logProgress({
        projectId,
        blockId: block.id,
        parentRecordId: nyc.id,
        deltaValue: 20,
        recordedDate: '2026-11-18',
        title: 'NYC wave 1',
      });
      const nycBatch2 = projectsService.logProgress({
        projectId,
        blockId: block.id,
        parentRecordId: nyc.id,
        deltaValue: 18, // total NYC = 38 (+8 over 30 target)
        recordedDate: '2026-11-19',
        title: 'NYC wave 2 (over-target)',
      });
      projectsService.logProgress({
        projectId,
        blockId: block.id,
        parentRecordId: chicago.id,
        deltaValue: 12,
        recordedDate: '2026-11-19',
      });
      projectsService.logProgress({
        projectId,
        blockId: block.id,
        parentRecordId: houston.id,
        deltaValue: 11,
        recordedDate: '2026-11-19',
      });
      projectsService.logProgress({
        projectId,
        blockId: block.id,
        parentRecordId: losAngeles.id,
        deltaValue: 14,
        recordedDate: '2026-11-20',
      });

      // 4 & 5. Confirm city progress, region progress, over-target preservation, and overall campaign progress
      const preCorrectionSnap = projectsService.getProjectDetailSnapshot(projectId, {
        asOfDate: CalendarDate.parse('2026-11-20'),
      })!;
      const pmPre = preCorrectionSnap.summary.primaryMetric!;
      // Actual sent = 38 + 12 + 11 + 14 = 75
      assert.strictEqual(pmPre.loggedTotal, 75);
      // Capped target contribution = min(38, 30) + 12 + 11 + 14 = 67
      assert.strictEqual(pmPre.targetCompletedTotal, 67);
      assert.strictEqual(pmPre.overTargetAmount, 8);
      assert.strictEqual(pmPre.overTargetItemCount, 1);
      assert.strictEqual(pmPre.itemTotals[nyc.id], 38);
      assert.strictEqual(pmPre.itemTotals[chicago.id], 12);
      assert.strictEqual(pmPre.itemTotals[houston.id], 11);
      assert.strictEqual(pmPre.itemTotals[losAngeles.id], 14);
      assert.strictEqual(pmPre.dailyTotalsByDate['2026-11-18'], 20);
      assert.strictEqual(pmPre.dailyTotalsByDate['2026-11-19'], 41);
      assert.strictEqual(pmPre.dailyTotalsByDate['2026-11-20'], 14);
      assert.strictEqual(pmPre.todayTotal, 14);
      assert.ok(Math.abs((preCorrectionSnap.summary.overallPercentage ?? 0) - 6.7) < 1e-6);

      // All 4 US regions reflect their respective contributions
      const expectedRegionTargets: Record<string, number> = {
        Northeast: 152,
        Midwest: 179,
        South: 411,
        West: 258,
      };
      for (const region of US_CENSUS_REGION_ORDER) {
        const gm = pmPre.groupMetrics.find((g) => g.title === region)!;
        assert.strictEqual(gm.targetValue, expectedRegionTargets[region]);
      }
      const northeastGm = pmPre.groupMetrics.find((g) => g.title === 'Northeast')!;
      assert.strictEqual(northeastGm.loggedTotal, 38);
      assert.strictEqual(northeastGm.targetCompletedTotal, 30);
      assert.strictEqual(northeastGm.overTargetAmount, 8);

      // 6. Add compensating correction on NYC batch 2 and verify append-only immutability + coherent history
      assert.throws(
        () =>
          projectsService.updateRecord({
            ...nycBatch1,
            deltaValue: 99,
          }),
        ProjectValidationError
      );
      assert.throws(
        () => projectsService.deleteRecord(nycBatch1.id),
        ProjectValidationError
      );

      const correction = projectsService.appendProgressCorrection({
        targetLogId: nycBatch2.id,
        correctionDelta: -5, // NYC becomes 33 (+3 over 30 target -> actual 70, capped 67)
        recordedDate: '2026-11-20',
        reason: '5 bounced architectural firms',
      });

      const history = projectsService.getChronologicalProgressHistory(projectId);
      assert.strictEqual(history.length, 6);
      const correctionEntry = history.find((h) => h.isCorrection)!;
      assert.strictEqual(correctionEntry.record.id, correction.id);
      assert.strictEqual(correctionEntry.compensatesRecordId, nycBatch2.id);
      assert.strictEqual(
        correctionEntry.correctionReason,
        '5 bounced architectural firms'
      );
      assert.strictEqual(correctionEntry.parentItemTitle, 'New York, NY');
      assert.strictEqual(correctionEntry.groupTitle, 'Northeast');
      assert.strictEqual(correctionEntry.record.deltaValue, -5);

      // 7. Simulate browser refresh & confirm persistence in localStorage
      assert.ok(store.has(WebProjectsRepository.PROJECTS_KEY));
      simulateBrowserRefresh();
      const freshRepo = new WebProjectsRepository();
      const persistedSnap = freshRepo.getProjectProgressSummary(projectId, {
        asOfDate: CalendarDate.parse('2026-11-20'),
      });
      assert.strictEqual(persistedSnap.primaryMetric?.loggedTotal, 70);
      assert.strictEqual(persistedSnap.primaryMetric?.targetCompletedTotal, 67);
      assert.strictEqual(persistedSnap.primaryMetric?.overTargetAmount, 3);
      assert.strictEqual(persistedSnap.primaryMetric?.itemTotals[nyc.id], 33);

      // 8. Export from Web Preview & confirm Android codec parity + collision-free remapping + editability
      const exported = projectsService.exportProjectPackage(projectId);
      assert.strictEqual(
        exported.filename,
        buildProjectPackageFilename(BIM_OUTREACH_CAMPAIGN_TITLE)
      );
      assert.strictEqual(
        exported.filename,
        'bim-company-outreach-1-000-companies.daywellproject'
      );

      const parsedForAndroid = parseAndValidateProjectPackage(exported.json);
      assert.strictEqual(parsedForAndroid.sourcePlatform, 'web');
      assertPackageInvariantParity(parsedForAndroid);
      assert.strictEqual(parsedForAndroid.trackingBlocks.length, 1);
      assert.strictEqual(parsedForAndroid.trackingRecords.length, 110); // 4 groups + 100 cities + 5 logs + 1 correction

      // Simulate Android database that already contains colliding IDs
      const androidPrepared = prepareProjectPackageForImport(exported.json, {
        existingProjectIds: [parsedForAndroid.project.id],
        existingBlockIds: parsedForAndroid.trackingBlocks.map((b) => b.id),
        existingRecordIds: parsedForAndroid.trackingRecords.map((r) => r.id),
      });
      assert.notStrictEqual(androidPrepared.project.id, parsedForAndroid.project.id);
      assert.strictEqual(
        androidPrepared.project.customFields?.primaryBlockId,
        androidPrepared.trackingBlocks[0].id
      );

      const androidOldIds = new Set<string>([
        parsedForAndroid.project.id,
        ...parsedForAndroid.trackingBlocks.map((b) => b.id),
        ...parsedForAndroid.trackingRecords.map((r) => r.id),
      ]);
      for (const blk of androidPrepared.trackingBlocks) {
        assert.strictEqual(androidOldIds.has(blk.id), false);
        assert.strictEqual(blk.projectId, androidPrepared.project.id);
      }
      for (const rec of androidPrepared.trackingRecords) {
        assert.strictEqual(androidOldIds.has(rec.id), false);
        assert.strictEqual(rec.projectId, androidPrepared.project.id);
        assert.strictEqual(rec.blockId, androidPrepared.trackingBlocks[0].id);
      }

      // Verify Android-imported package can be mutated & re-exported cleanly
      const reExportedFromImported = serializeProjectPackage({
        project: androidPrepared.project,
        blocks: androidPrepared.trackingBlocks,
        records: androidPrepared.trackingRecords,
        sourcePlatform: 'android',
      });
      const reValidated = parseAndValidateProjectPackage(reExportedFromImported);
      assert.strictEqual(reValidated.sourcePlatform, 'android');
      assertPackageInvariantParity(reValidated);

      // Invalid/future packages fail closed without modifying local Web storage
      const projectCountBefore = projectsService.listProjects({ includeArchived: true }).length;
      assert.throws(
        () =>
          projectsService.importProjectPackage(
            JSON.stringify({ ...parsedForAndroid, formatVersion: 99 })
          ),
        (err: unknown) =>
          err instanceof ProjectPackageError && err.kind === 'unsupported_version'
      );
      assert.strictEqual(
        projectsService.listProjects({ includeArchived: true }).length,
        projectCountBefore
      );
    });
  });

  it('C: Reverse transfer (Android -> Web Preview) creates an isolated copy preserving shared fixture structure & history', () => {
    withMockBrowserSession((_store, simulateBrowserRefresh) => {
      const sampleFixturePath = path.join(
        REPO_ROOT,
        'shared_foundation',
        'fixtures',
        'sample_project_package_v1.json'
      );
      const androidFixtureJson = fs.readFileSync(sampleFixturePath, 'utf8');

      // Seed local Web project first, then import the Android fixture twice
      const localWeb = projectsService.createProjectWithBlocks({
        title: 'Local Desktop Workspace Project',
        status: 'active',
        blocks: [
          {
            tempId: 'b1',
            blockType: 'counter',
            title: 'Local Counter',
            targetValue: 50,
          },
        ],
      });

      const import1 = projectsService.importProjectPackage(androidFixtureJson);
      const import2 = projectsService.importProjectPackage(androidFixtureJson);

      assert.notStrictEqual(import1.project.id, import2.project.id);
      assert.notStrictEqual(import1.project.id, localWeb.id);
      assert.strictEqual(import1.project.goalId, undefined);
      assert.strictEqual(import1.project.title, 'Home Studio Build & Curriculum');
      assert.strictEqual(projectsService.getProject(localWeb.id)?.title, 'Local Desktop Workspace Project');

      // Simulate browser refresh and confirm imported structure, archived blocks, rollups & corrections survive
      simulateBrowserRefresh();
      const snap = projectsService.getProjectDetailSnapshot(import1.project.id, {
        asOfDate: CalendarDate.parse('2026-11-12'),
      })!;
      assert.strictEqual(snap.blocks.length, 6);
      assert.strictEqual(snap.summary.primaryMetric?.loggedTotal, 10);
      assert.strictEqual(Math.round(snap.summary.overallPercentage ?? 0), 33);

      const history = projectsService.getChronologicalProgressHistory(import1.project.id);
      const correction = history.find((h) => h.isCorrection)!;
      assert.ok(correction);
      assert.strictEqual(
        correction.correctionReason,
        'Logged 2 extra hours by mistake'
      );
      assert.ok(
        history.some((h) => h.record.id === correction.compensatesRecordId)
      );

      // Continuing work on imported copy updates only that copy
      const groupedBlock = snap.blocks.find((b) => b.blockType === 'grouped_list')!;
      const groupedItem = snap.records.find(
        (r: SharedProjectTrackingRecord) =>
          r.blockId === groupedBlock.id && r.recordType === 'grouped_item'
      )!;
      projectsService.logProgress({
        projectId: import1.project.id,
        blockId: groupedBlock.id,
        parentRecordId: groupedItem.id,
        deltaValue: 5,
        recordedDate: '2026-11-13',
      });

      const snap1After = projectsService.getProjectDetailSnapshot(import1.project.id, {
        asOfDate: CalendarDate.parse('2026-11-13'),
      })!;
      const snap2Unchanged = projectsService.getProjectDetailSnapshot(import2.project.id, {
        asOfDate: CalendarDate.parse('2026-11-13'),
      })!;
      assert.strictEqual(snap1After.summary.primaryMetric?.loggedTotal, 15);
      assert.strictEqual(snap2Unchanged.summary.primaryMetric?.loggedTotal, 10);
    });
  });

  it('D: General project compatibility preserves counter (direct + rollup), grouped_list, checklist, and all schedule completion rules across bidirectional transfer', () => {
    withMockBrowserSession((store, simulateBrowserRefresh) => {
      // Seed an existing local goal so we verify export strips cross-module goalId cleanly
      const localGoal: SharedGoal = {
        id: 'goal-local-1',
        title: 'General Mastery Goal',
        status: 'active',
      };
      store.set('daywell_goals', JSON.stringify([localGoal]));

      const proj = projectsService.createProjectWithBlocks({
        title: 'General Multi-Block Project',
        description: 'Covers all 4 tracking block types & rules.',
        status: 'active',
        startDate: '2026-11-01',
        targetDate: '2026-11-30',
        goalId: localGoal.id,
        primaryDraftTempId: 'draft-rollup',
        blocks: [
          {
            tempId: 'draft-direct',
            blockType: 'counter',
            title: 'Direct Practice Units',
            unitLabel: 'units',
            targetValue: 10,
            dailyTargetValue: 2,
          },
          {
            tempId: 'draft-grouped',
            blockType: 'grouped_list',
            title: 'Modules List',
            unitLabel: 'lessons',
            targetValue: 10,
          },
          {
            tempId: 'draft-rollup',
            blockType: 'counter',
            title: 'Rollup From Modules',
            unitLabel: 'lessons',
            targetValue: 10,
            config: {
              rollupSourceBlockId: 'draft-grouped',
              allowDirectLogging: false,
            },
          },
          {
            tempId: 'draft-check',
            blockType: 'checklist',
            title: 'Milestone Checklist',
          },
          {
            tempId: 'draft-sched-manual',
            blockType: 'schedule',
            title: 'Manual Sessions',
            config: {
              completionRule: 'manual',
              autoCompleteThresholdRatio: 1,
              trackActualDuration: true,
            },
          },
          {
            tempId: 'draft-sched-thresh',
            blockType: 'schedule',
            title: 'Threshold Sessions (75%)',
            config: {
              completionRule: 'threshold_percent',
              autoCompleteThresholdRatio: 0.75,
              trackActualDuration: true,
            },
          },
          {
            tempId: 'draft-sched-exact',
            blockType: 'schedule',
            title: 'Exact Duration Sessions',
            config: {
              completionRule: 'exact_duration',
              autoCompleteThresholdRatio: 1,
              trackActualDuration: true,
            },
          },
        ],
      });

      const snap = projectsService.getProjectDetailSnapshot(proj.id)!;
      const directBlock = snap.blocks.find((b) => b.title === 'Direct Practice Units')!;
      const groupedBlock = snap.blocks.find((b) => b.title === 'Modules List')!;
      const rollupBlock = snap.blocks.find((b) => b.title === 'Rollup From Modules')!;
      const checkBlock = snap.blocks.find((b) => b.title === 'Milestone Checklist')!;
      const schedManualBlock = snap.blocks.find((b) => b.title === 'Manual Sessions')!;
      const schedThreshBlock = snap.blocks.find((b) => b.title === 'Threshold Sessions (75%)')!;
      const schedExactBlock = snap.blocks.find((b) => b.title === 'Exact Duration Sessions')!;

      // 1. Direct counter logging works; rollup counter blocks direct logging
      projectsService.logProgress({
        projectId: proj.id,
        blockId: directBlock.id,
        deltaValue: 4,
        recordedDate: '2026-11-05',
      });
      assert.throws(
        () =>
          projectsService.logProgress({
            projectId: proj.id,
            blockId: rollupBlock.id,
            deltaValue: 1,
            recordedDate: '2026-11-05',
          }),
        ProjectValidationError
      );

      // 2. Grouped list populates rollup counter
      const grp = projectsService.createGroup({
        projectId: proj.id,
        blockId: groupedBlock.id,
        title: 'Core Section',
        targetValue: 10,
      });
      const grpItem = projectsService.createGroupedItem({
        projectId: proj.id,
        blockId: groupedBlock.id,
        groupId: grp.id,
        title: 'Module A',
        targetValue: 10,
      });
      projectsService.logProgress({
        projectId: proj.id,
        blockId: groupedBlock.id,
        parentRecordId: grpItem.id,
        deltaValue: 5,
        recordedDate: '2026-11-05',
      });

      // 3. Checklist allows item toggle & blocks progress_log
      const chk1 = projectsService.createChecklistItem({
        projectId: proj.id,
        blockId: checkBlock.id,
        title: 'Setup env',
      });
      projectsService.toggleRecordCompleted(chk1);
      assert.throws(
        () =>
          projectsService.logProgress({
            projectId: proj.id,
            blockId: checkBlock.id,
            parentRecordId: chk1.id,
            deltaValue: 1,
            recordedDate: '2026-11-05',
          }),
        ProjectValidationError
      );

      // 4. Schedule completion rules: manual, threshold_percent (75%), exact_duration
      const manualItem = projectsService.createScheduleItem({
        projectId: proj.id,
        blockId: schedManualBlock.id,
        title: 'Manual workshop',
        scheduledDate: '2026-11-06',
        durationMinutes: 60,
      });
      projectsService.logProgress({
        projectId: proj.id,
        blockId: schedManualBlock.id,
        parentRecordId: manualItem.id,
        deltaValue: 60,
        recordedDate: '2026-11-06',
      });

      const threshItem = projectsService.createScheduleItem({
        projectId: proj.id,
        blockId: schedThreshBlock.id,
        title: 'Threshold lab',
        scheduledDate: '2026-11-06',
        durationMinutes: 60,
      });
      projectsService.logProgress({
        projectId: proj.id,
        blockId: schedThreshBlock.id,
        parentRecordId: threshItem.id,
        deltaValue: 45, // exactly 75%
        recordedDate: '2026-11-06',
      });

      const exactItem = projectsService.createScheduleItem({
        projectId: proj.id,
        blockId: schedExactBlock.id,
        title: 'Exact sprint',
        scheduledDate: '2026-11-06',
        durationMinutes: 60,
      });
      projectsService.logProgress({
        projectId: proj.id,
        blockId: schedExactBlock.id,
        parentRecordId: exactItem.id,
        deltaValue: 50,
        recordedDate: '2026-11-06',
      });

      const midSnap = projectsService.getProjectDetailSnapshot(proj.id)!;
      assert.strictEqual(
        midSnap.records.find((r) => r.id === manualItem.id)?.isCompleted,
        false
      );
      assert.strictEqual(
        midSnap.records.find((r) => r.id === threshItem.id)?.isCompleted,
        true
      );
      assert.strictEqual(
        midSnap.records.find((r) => r.id === exactItem.id)?.isCompleted,
        false
      );
      // Complete exactItem by logging remaining 10 minutes
      projectsService.logProgress({
        projectId: proj.id,
        blockId: schedExactBlock.id,
        parentRecordId: exactItem.id,
        deltaValue: 10,
        recordedDate: '2026-11-06',
      });

      // Export package & verify topological ordering + stripped goalId + round-trip import
      const exported = projectsService.exportProjectPackage(proj.id);
      const parsed = parseAndValidateProjectPackage(exported.json);
      assertPackageInvariantParity(parsed);
      assert.strictEqual(
        buildProjectPackageFilename(proj.title),
        'general-multi-block-project.daywellproject'
      );

      simulateBrowserRefresh();
      const roundTripped = projectsService.importProjectPackage(exported.json);
      assert.notStrictEqual(roundTripped.project.id, proj.id);
      assert.strictEqual(roundTripped.project.goalId, undefined);

      const roundTrippedSnap = projectsService.getProjectDetailSnapshot(
        roundTripped.project.id,
        { asOfDate: CalendarDate.parse('2026-11-06') }
      )!;
      assert.strictEqual(roundTrippedSnap.blocks.length, 7);

      const rtGrouped = roundTrippedSnap.blocks.find(
        (b) => b.title === 'Modules List'
      )!;
      const rtRollup = roundTrippedSnap.blocks.find(
        (b) => b.title === 'Rollup From Modules'
      )!;
      const rtDirect = roundTrippedSnap.blocks.find(
        (b) => b.title === 'Direct Practice Units'
      )!;
      const rtCheck = roundTrippedSnap.blocks.find(
        (b) => b.title === 'Milestone Checklist'
      )!;
      const rtSchedManual = roundTrippedSnap.blocks.find(
        (b) => b.title === 'Manual Sessions'
      )!;
      const rtSchedThresh = roundTrippedSnap.blocks.find(
        (b) => b.title === 'Threshold Sessions (75%)'
      )!;
      const rtSchedExact = roundTrippedSnap.blocks.find(
        (b) => b.title === 'Exact Duration Sessions'
      )!;

      assert.strictEqual(rtRollup.config?.rollupSourceBlockId, rtGrouped.id);
      assert.strictEqual(roundTrippedSnap.summary.primaryBlockId, rtRollup.id);

      const metricByBlockId = new Map(
        roundTrippedSnap.summary.blockMetrics.map((m) => [m.blockId, m])
      );
      assert.strictEqual(metricByBlockId.get(rtDirect.id)?.loggedTotal, 4);
      assert.strictEqual(metricByBlockId.get(rtGrouped.id)?.loggedTotal, 5);
      assert.strictEqual(metricByBlockId.get(rtRollup.id)?.loggedTotal, 5);
      assert.strictEqual(metricByBlockId.get(rtCheck.id)?.completedCount, 1);
      assert.strictEqual(metricByBlockId.get(rtSchedManual.id)?.completedCount, 0);
      assert.strictEqual(metricByBlockId.get(rtSchedThresh.id)?.completedCount, 1);
      assert.strictEqual(metricByBlockId.get(rtSchedExact.id)?.completedCount, 1);
      assert.strictEqual(
        metricByBlockId.get(rtSchedExact.id)?.actualLoggedDurationMinutes,
        60
      );
      assert.strictEqual(Math.round(roundTrippedSnap.summary.overallPercentage ?? 0), 50);

      // Verify imported project remains editable & trackable across blocks
      const rtGroupedItem = roundTrippedSnap.records.find(
        (r) => r.blockId === rtGrouped.id && r.recordType === 'grouped_item'
      )!;
      projectsService.logProgress({
        projectId: roundTripped.project.id,
        blockId: rtGrouped.id,
        parentRecordId: rtGroupedItem.id,
        deltaValue: 5,
        recordedDate: '2026-11-07',
      });
      const finalSnap = projectsService.getProjectDetailSnapshot(
        roundTripped.project.id,
        { asOfDate: CalendarDate.parse('2026-11-07') }
      )!;
      assert.strictEqual(finalSnap.summary.primaryMetric?.loggedTotal, 10);
      assert.strictEqual(Math.round(finalSnap.summary.overallPercentage ?? 0), 100);
    });
  });
});
