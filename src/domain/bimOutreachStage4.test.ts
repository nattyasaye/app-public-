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
  buildBimOutreachPackage,
  getBimOutreachCampaignDates,
  serializeBimOutreachTemplateJson,
} from './bimOutreachTemplate';
import { getProjectScheduleSpan } from './projectsEngine';
import { parseAndValidateProjectPackage } from './projectPackage';
import { projectsService } from '../services/projectsService';

const REPO_ROOT = path.resolve(
  path.dirname(new URL(import.meta.url).pathname),
  '..',
  '..'
);

function withMockBrowserStorage(fn: () => void): void {
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
    fn();
  } finally {
    (globalThis as any).window = prevWindow;
    (globalThis as any).localStorage = prevLocalStorage;
  }
}

describe('Daywell Projects Stage 4 — BIM Company Outreach Campaign Template', () => {
  it('1. Defines exactly 100 unique US cities summing to 1,000 across 4 US Census regions with exact Hidar 9–30, 2019 E.C. dates', () => {
    assert.strictEqual(BIM_OUTREACH_CITIES.length, 100);

    const uniqueDisplayNames = new Set(
      BIM_OUTREACH_CITIES.map((c) => `${c.city}, ${c.state}`)
    );
    assert.strictEqual(uniqueDisplayNames.size, 100);
    assert.ok(uniqueDisplayNames.has('Portland, OR'));
    assert.ok(uniqueDisplayNames.has('Portland, ME'));

    const sumTotal = BIM_OUTREACH_CITIES.reduce((s, c) => s + c.target, 0);
    assert.strictEqual(sumTotal, BIM_OUTREACH_CAMPAIGN_TARGET_TOTAL);
    assert.strictEqual(sumTotal, 1000);

    const regionExpected: Record<string, { count: number; target: number }> = {
      Northeast: { count: 16, target: 152 },
      Midwest: { count: 19, target: 179 },
      South: { count: 42, target: 411 },
      West: { count: 23, target: 258 },
    };
    for (const region of US_CENSUS_REGION_ORDER) {
      const citiesInRegion = BIM_OUTREACH_CITIES.filter(
        (c) => c.region === region
      );
      const regionSum = citiesInRegion.reduce((s, c) => s + c.target, 0);
      assert.strictEqual(citiesInRegion.length, regionExpected[region].count);
      assert.strictEqual(regionSum, regionExpected[region].target);
    }

    const dates = getBimOutreachCampaignDates();
    assert.strictEqual(dates.startIso, '2026-11-18');
    assert.strictEqual(dates.targetIso, '2026-12-09');
    assert.strictEqual(dates.durationDays, 22);
    const ethStart = dates.startDate.toEthiopian();
    const ethEnd = dates.targetDate.toEthiopian();
    assert.strictEqual(ethStart.year, 2019);
    assert.strictEqual(ethStart.month, 3);
    assert.strictEqual(ethStart.day, 9);
    assert.strictEqual(ethEnd.year, 2019);
    assert.strictEqual(ethEnd.month, 3);
    assert.strictEqual(ethEnd.day, 30);
    assert.strictEqual(BIM_OUTREACH_CAMPAIGN_DAILY_TARGET, 46);
  });

  it('2. Fixture bim_outreach_campaign_v1.daywellproject matches template builder and imports cleanly via standard Stage 3 package pipeline', () => {
    const fixturePath = path.join(
      REPO_ROOT,
      'shared_foundation',
      'fixtures',
      'bim_outreach_campaign_v1.daywellproject'
    );
    const fixtureJson = fs.readFileSync(fixturePath, 'utf8');
    assert.strictEqual(fixtureJson, serializeBimOutreachTemplateJson());

    const pkg = parseAndValidateProjectPackage(fixtureJson);
    assert.strictEqual(pkg.project.title, BIM_OUTREACH_CAMPAIGN_TITLE);
    assert.strictEqual(pkg.trackingBlocks.length, 1);
    assert.strictEqual(pkg.trackingRecords.length, 104); // 4 groups + 100 cities

    const built = buildBimOutreachPackage();
    assert.deepStrictEqual(pkg, built);

    withMockBrowserStorage(() => {
      const imported = projectsService.importProjectPackage(fixtureJson);
      assert.strictEqual(imported.project.title, BIM_OUTREACH_CAMPAIGN_TITLE);
      assert.strictEqual(imported.project.startDate, '2026-11-18');
      assert.strictEqual(imported.project.targetDate, '2026-12-09');
      assert.strictEqual(imported.trackingBlocks.length, 1);
      assert.strictEqual(imported.trackingRecords.length, 104);

      const span = getProjectScheduleSpan(
        imported.project,
        CalendarDate.parse('2026-11-18')
      );
      assert.strictEqual(span.totalDays, 22);
      assert.strictEqual(span.remainingDays, 22);
      assert.strictEqual(span.elapsedDays, 1);

      const snap = projectsService.getProjectDetailSnapshot(
        imported.project.id,
        { asOfDate: CalendarDate.parse('2026-11-18') }
      )!;
      assert.strictEqual(snap.summary.primaryMetric?.targetValue, 1000);
      assert.strictEqual(snap.summary.primaryMetric?.dailyTargetValue, 46);
      assert.strictEqual(snap.summary.primaryMetric?.totalCount, 100);
      assert.strictEqual(snap.summary.primaryMetric?.completedCount, 0);
      assert.strictEqual(snap.summary.primaryMetric?.groupMetrics.length, 4);
      assert.strictEqual(snap.summary.overallPercentage, 0);
      assert.ok(
        Math.abs((snap.summary.primaryMetric?.paceNeededPerDay ?? 0) - 1000 / 22) <
          1e-6
      );
    });
  });

  it('3. Preserves actual sent counts while capping city contribution to 1,000-email target completion and supporting corrections + re-export', () => {
    withMockBrowserStorage(() => {
      const imported = projectsService.importProjectPackage(
        serializeBimOutreachTemplateJson()
      );
      const block = imported.trackingBlocks[0];
      const nyc = imported.trackingRecords.find(
        (r) => r.title === 'New York, NY'
      )!;
      const boston = imported.trackingRecords.find(
        (r) => r.title === 'Boston, MA'
      )!;

      // Batch 1 & 2 for New York (target 30): 20 + 15 = 35 actual sent (+5 over)
      const batch1 = projectsService.logProgress({
        projectId: imported.project.id,
        blockId: block.id,
        parentRecordId: nyc.id,
        deltaValue: 20,
        recordedDate: '2026-11-18',
      });
      projectsService.logProgress({
        projectId: imported.project.id,
        blockId: block.id,
        parentRecordId: nyc.id,
        deltaValue: 15,
        recordedDate: '2026-11-18',
      });
      // Batch for Boston (target 20): 12 emails on next day
      projectsService.logProgress({
        projectId: imported.project.id,
        blockId: block.id,
        parentRecordId: boston.id,
        deltaValue: 12,
        recordedDate: '2026-11-19',
      });

      const snapDay2 = projectsService.getProjectDetailSnapshot(
        imported.project.id,
        { asOfDate: CalendarDate.parse('2026-11-19') }
      )!;
      const metric = snapDay2.summary.primaryMetric!;
      assert.strictEqual(metric.loggedTotal, 47); // 35 + 12 actual sent
      assert.strictEqual(metric.targetCompletedTotal, 42); // min(35,30) + 12
      assert.strictEqual(metric.overTargetAmount, 5);
      assert.strictEqual(metric.overTargetItemCount, 1);
      assert.strictEqual(metric.todayTotal, 12);
      assert.strictEqual(metric.dailyTotalsByDate['2026-11-18'], 35);
      assert.strictEqual(metric.dailyTotalsByDate['2026-11-19'], 12);
      assert.strictEqual(metric.completedCount, 1); // NYC done
      assert.ok(
        Math.abs((snapDay2.summary.overallPercentage ?? 0) - 4.2) < 1e-6
      );

      const northeast = metric.groupMetrics.find(
        (g) => g.title === 'Northeast'
      )!;
      assert.strictEqual(northeast.loggedTotal, 47);
      assert.strictEqual(northeast.targetCompletedTotal, 42);
      assert.strictEqual(northeast.overTargetAmount, 5);
      assert.strictEqual(northeast.overTargetItemCount, 1);

      const formatted = projectsService.formatBlockMetricSummary(metric);
      assert.ok(formatted.includes('42 / 1000 emails'));
      assert.ok(formatted.includes('47 sent'));
      assert.ok(formatted.includes('+5 over'));

      // Compensating correction brings NYC from 35 down to 27 (within 30 target)
      projectsService.appendProgressCorrection({
        targetLogId: batch1.id,
        correctionDelta: -8,
        recordedDate: '2026-11-19',
        reason: 'Bounced test batch adjustment',
      });

      const snapCorrected = projectsService.getProjectDetailSnapshot(
        imported.project.id,
        { asOfDate: CalendarDate.parse('2026-11-19') }
      )!;
      const correctedMetric = snapCorrected.summary.primaryMetric!;
      assert.strictEqual(correctedMetric.loggedTotal, 39); // 27 + 12
      assert.strictEqual(correctedMetric.targetCompletedTotal, 39);
      assert.strictEqual(correctedMetric.overTargetAmount, 0);
      assert.strictEqual(correctedMetric.overTargetItemCount, 0);
      assert.strictEqual(correctedMetric.completedCount, 0);
      assert.ok(
        Math.abs((snapCorrected.summary.overallPercentage ?? 0) - 3.9) < 1e-6
      );

      // Re-export and re-import into a second local project preserves full campaign & history
      const exported = projectsService.exportProjectPackage(imported.project.id);
      const reimported = projectsService.importProjectPackage(exported.json);
      assert.notStrictEqual(reimported.project.id, imported.project.id);
      assert.strictEqual(
        reimported.trackingRecords.length,
        snapCorrected.records.length
      );
      const reimportedSnap = projectsService.getProjectDetailSnapshot(
        reimported.project.id,
        { asOfDate: CalendarDate.parse('2026-11-19') }
      )!;
      assert.strictEqual(reimportedSnap.summary.primaryMetric?.loggedTotal, 39);
      assert.strictEqual(
        reimportedSnap.summary.primaryMetric?.targetCompletedTotal,
        39
      );
    });
  });
});
