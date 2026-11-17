import { describe, it } from 'node:test';
import assert from 'node:assert';
import { CalendarDate } from './date';
import {
  SHARED_BUSINESS_RULES,
  SharedGoal,
  SharedProject,
  SharedProjectTrackingBlock,
  SharedProjectTrackingRecord,
  SharedTask,
} from './sharedFoundation';
import {
  assertAppendOnlyLogProtection,
  calculateProjectProgressSummary,
  meetsScheduleDurationRule,
  parseScheduleBlockConfig,
  ProjectMilestoneInput,
  ProjectValidationError,
  validateBlock,
  validateCustomFieldsMap,
  validateProject,
  validateRecord,
} from './projectsEngine';
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

const NOW_ISO = '2026-11-17T08:00:00.000Z';

describe('PROJECTS STAGE 1: DOMAIN VALIDATION, PROGRESS ENGINE, REPOSITORY & BRIDGE PARITY', () => {
  it('1. Project & customFields schema validation enforces types, required fields, date order, bounds, and rejects nested objects', () => {
    const validCustomFields = {
      primaryBlockId: 'blk-counter',
      definitions: [
        { id: 'channel', label: 'Outreach Channel', type: 'select', required: true, options: ['Email', 'LinkedIn'] },
        { id: 'hours_goal', label: 'Weekly Hours', type: 'number', required: false },
        { id: 'kickoff', label: 'Kickoff', type: 'date', required: false },
        { id: 'active_flag', label: 'Client Facing', type: 'boolean', required: true },
        { id: 'owner', label: 'Lead', type: 'text', required: false },
      ],
      values: {
        channel: 'Email',
        hours_goal: 12.5,
        kickoff: '2026-11-10',
        active_flag: true,
        owner: 'Dawit',
      },
    };

    validateCustomFieldsMap(validCustomFields);

    const validProject: SharedProject = {
      id: 'proj-valid',
      title: 'Outreach Q4',
      status: 'active',
      isArchived: false,
      startDate: '2026-11-01',
      targetDate: '2026-12-01',
      customFields: validCustomFields,
      createdAt: NOW_ISO,
      updatedAt: NOW_ISO,
    };
    validateProject(validProject);

    // Date ordering failure
    assert.throws(
      () =>
        validateProject({
          ...validProject,
          startDate: '2026-12-10',
          targetDate: '2026-11-15',
        }),
      ProjectValidationError
    );

    // Missing required custom field
    assert.throws(
      () =>
        validateCustomFieldsMap({
          definitions: [{ id: 'channel', label: 'Channel', type: 'text', required: true }],
          values: {},
        }),
      ProjectValidationError
    );

    // Nested object/array rejected
    assert.throws(
      () =>
        validateCustomFieldsMap({
          definitions: [{ id: 'meta', label: 'Meta', type: 'text', required: false }],
          values: { meta: { nested: true } },
        }),
      ProjectValidationError
    );

    // Unknown value key rejected
    assert.throws(
      () =>
        validateCustomFieldsMap({
          definitions: [{ id: 'a', label: 'A', type: 'text', required: false }],
          values: { unknown_key: 'x' },
        }),
      ProjectValidationError
    );

    // Unsupported top-level customFields key rejected
    assert.throws(
      () => validateCustomFieldsMap({ arbitraryKey: 123 } as any),
      ProjectValidationError
    );

    // Invalid select value rejected
    assert.throws(
      () =>
        validateCustomFieldsMap({
          definitions: [{ id: 'tier', label: 'Tier', type: 'select', required: true, options: ['A', 'B'] }],
          values: { tier: 'C' },
        }),
      ProjectValidationError
    );

    // Exceeds maxCustomFieldDefinitions (24)
    const tooManyDefs = Array.from(
      { length: SHARED_BUSINESS_RULES.projects.bounds.maxCustomFieldDefinitions + 1 },
      (_, idx) => ({ id: `f_${idx}`, label: `Field ${idx}`, type: 'text', required: false })
    );
    assert.throws(
      () => validateCustomFieldsMap({ definitions: tooManyDefs, values: {} }),
      ProjectValidationError
    );
  });

  it('2. Tracking block validation enforces 32-block limit, schedule bounds, and rollup counter guards', () => {
    const baseBlock: SharedProjectTrackingBlock = {
      id: 'blk-source',
      projectId: 'proj-1',
      blockType: 'grouped_list',
      title: 'Regions',
      sortOrder: 0,
      isArchived: false,
      config: { showGroupTotals: true, showDailyTotals: true },
      createdAt: NOW_ISO,
      updatedAt: NOW_ISO,
    };

    // Up to 32 existing blocks rejected on 33rd
    const fullBlocks: SharedProjectTrackingBlock[] = Array.from(
      { length: SHARED_BUSINESS_RULES.projects.bounds.maxBlocksPerProject },
      (_, i) => ({ ...baseBlock, id: `blk-${i}`, sortOrder: i })
    );
    assert.throws(
      () =>
        validateBlock(
          { ...baseBlock, id: 'blk-33', sortOrder: 32 },
          { expectedProjectId: 'proj-1', projectBlocks: fullBlocks, isNew: true }
        ),
      ProjectValidationError
    );

    // Valid rollup counter referencing existing grouped_list
    const validRollup: SharedProjectTrackingBlock = {
      id: 'blk-rollup',
      projectId: 'proj-1',
      blockType: 'counter',
      title: 'Total Sent',
      sortOrder: 1,
      targetValue: 100,
      isArchived: false,
      config: { rollupSourceBlockId: 'blk-source', allowDirectLogging: false },
      createdAt: NOW_ISO,
      updatedAt: NOW_ISO,
    };
    validateBlock(validRollup, {
      expectedProjectId: 'proj-1',
      projectBlocks: [baseBlock],
      isNew: true,
    });

    // Self-rollup rejected
    assert.throws(
      () =>
        validateBlock(
          {
            ...validRollup,
            id: 'blk-self',
            config: { rollupSourceBlockId: 'blk-self', allowDirectLogging: false },
          },
          { expectedProjectId: 'proj-1', projectBlocks: [baseBlock], isNew: true }
        ),
      ProjectValidationError
    );

    // Rollup with allowDirectLogging: true rejected
    assert.throws(
      () =>
        validateBlock(
          {
            ...validRollup,
            config: { rollupSourceBlockId: 'blk-source', allowDirectLogging: true },
          },
          { expectedProjectId: 'proj-1', projectBlocks: [baseBlock], isNew: true }
        ),
      ProjectValidationError
    );

    // Missing source block rejected
    assert.throws(
      () =>
        validateBlock(
          {
            ...validRollup,
            config: { rollupSourceBlockId: 'blk-missing', allowDirectLogging: false },
          },
          { expectedProjectId: 'proj-1', projectBlocks: [baseBlock], isNew: true }
        ),
      ProjectValidationError
    );

    // Chained rollup through another rollup counter rejected
    assert.throws(
      () =>
        validateBlock(
          {
            ...validRollup,
            id: 'blk-chain',
            config: { rollupSourceBlockId: 'blk-rollup', allowDirectLogging: false },
          },
          { expectedProjectId: 'proj-1', projectBlocks: [baseBlock, validRollup], isNew: true }
        ),
      ProjectValidationError
    );

    // Schedule autoCompleteThresholdRatio out of bounds rejected
    assert.throws(
      () =>
        validateBlock(
          {
            id: 'blk-sched-bad',
            projectId: 'proj-1',
            blockType: 'schedule',
            title: 'Schedule',
            sortOrder: 2,
            isArchived: false,
            config: { completionRule: 'threshold_percent', autoCompleteThresholdRatio: 1.5 },
            createdAt: NOW_ISO,
            updatedAt: NOW_ISO,
          },
          { expectedProjectId: 'proj-1', projectBlocks: [baseBlock], isNew: true }
        ),
      ProjectValidationError
    );
  });

  it('3. Tracking record invariants & append-only progress_log protection enforce compensating corrections and reject mutations/cycles', () => {
    const groupedBlock: SharedProjectTrackingBlock = {
      id: 'blk-gl',
      projectId: 'proj-1',
      blockType: 'grouped_list',
      title: 'Regions',
      sortOrder: 0,
      isArchived: false,
      config: {},
      createdAt: NOW_ISO,
      updatedAt: NOW_ISO,
    };
    const checklistBlock: SharedProjectTrackingBlock = {
      id: 'blk-chk',
      projectId: 'proj-1',
      blockType: 'checklist',
      title: 'Checklist',
      sortOrder: 1,
      isArchived: false,
      config: {},
      createdAt: NOW_ISO,
      updatedAt: NOW_ISO,
    };
    const rollupCounterBlock: SharedProjectTrackingBlock = {
      id: 'blk-rollup',
      projectId: 'proj-1',
      blockType: 'counter',
      title: 'Rollup Total',
      sortOrder: 2,
      isArchived: false,
      config: { rollupSourceBlockId: 'blk-gl', allowDirectLogging: false },
      createdAt: NOW_ISO,
      updatedAt: NOW_ISO,
    };

    const grp: SharedProjectTrackingRecord = {
      id: 'rec-grp',
      projectId: 'proj-1',
      blockId: 'blk-gl',
      recordType: 'group',
      title: 'East Africa',
      sortOrder: 0,
      isCompleted: false,
      metadata: {},
      createdAt: NOW_ISO,
      updatedAt: NOW_ISO,
    };
    const city: SharedProjectTrackingRecord = {
      id: 'rec-city',
      projectId: 'proj-1',
      blockId: 'blk-gl',
      parentRecordId: 'rec-grp',
      recordType: 'grouped_item',
      title: 'Addis Ababa',
      sortOrder: 1,
      targetValue: 25,
      isCompleted: false,
      metadata: {},
      createdAt: NOW_ISO,
      updatedAt: NOW_ISO,
    };
    const log1: SharedProjectTrackingRecord = {
      id: 'log-1',
      projectId: 'proj-1',
      blockId: 'blk-gl',
      parentRecordId: 'rec-city',
      recordType: 'progress_log',
      sortOrder: 2,
      deltaValue: 10,
      isCompleted: false,
      recordedDate: '2026-11-17',
      metadata: {},
      createdAt: NOW_ISO,
      updatedAt: NOW_ISO,
    };

    validateRecord(grp, { block: groupedBlock, existingBlockRecords: [], isNew: true });
    validateRecord(city, { block: groupedBlock, existingBlockRecords: [grp], isNew: true });
    validateRecord(log1, { block: groupedBlock, existingBlockRecords: [grp, city], isNew: true });

    // Append-only log protection blocks update and delete
    assert.throws(() => assertAppendOnlyLogProtection(log1, false), ProjectValidationError);
    assert.throws(() => assertAppendOnlyLogProtection(log1, true), ProjectValidationError);

    // Negative delta without correction metadata rejected
    assert.throws(
      () =>
        validateRecord(
          { ...log1, id: 'log-neg-bad', deltaValue: -3 },
          { block: groupedBlock, existingBlockRecords: [grp, city, log1], isNew: true }
        ),
      ProjectValidationError
    );

    // Valid compensating correction succeeds
    validateRecord(
      {
        id: 'corr-1',
        projectId: 'proj-1',
        blockId: 'blk-gl',
        parentRecordId: 'rec-city',
        recordType: 'progress_log',
        sortOrder: 3,
        deltaValue: -3,
        isCompleted: false,
        recordedDate: '2026-11-17',
        metadata: {
          isCorrection: true,
          compensatesRecordId: 'log-1',
          correctionReason: 'Duplicate count removed',
        },
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      },
      { block: groupedBlock, existingBlockRecords: [grp, city, log1], isNew: true }
    );

    // Progress log on checklist block rejected
    assert.throws(
      () =>
        validateRecord(
          { ...log1, id: 'log-chk-bad', blockId: 'blk-chk', parentRecordId: undefined },
          { block: checklistBlock, existingBlockRecords: [], isNew: true }
        ),
      ProjectValidationError
    );

    // Direct log on rollup counter rejected
    assert.throws(
      () =>
        validateRecord(
          { ...log1, id: 'log-rollup-bad', blockId: 'blk-rollup', parentRecordId: undefined },
          { block: rollupCounterBlock, existingBlockRecords: [], isNew: true }
        ),
      ProjectValidationError
    );

    // Self-referential parent and cycle rejected
    assert.throws(
      () =>
        validateRecord(
          { ...grp, parentRecordId: 'rec-grp' },
          { block: groupedBlock, existingBlockRecords: [grp], isNew: false }
        ),
      ProjectValidationError
    );
    const childA: SharedProjectTrackingRecord = {
      ...city,
      id: 'rec-a',
      parentRecordId: 'rec-b',
    };
    const childB: SharedProjectTrackingRecord = {
      ...city,
      id: 'rec-b',
      parentRecordId: 'rec-a',
    };
    assert.throws(
      () =>
        validateRecord(childA, {
          block: groupedBlock,
          existingBlockRecords: [grp, childA, childB],
          isNew: false,
        }),
      ProjectValidationError
    );

    // Canonical 300-character record title limit (SHARED_BUSINESS_RULES)
    const maxTitleLen = SHARED_BUSINESS_RULES.projects.bounds.maxTrackingRecordTitleLength;
    assert.strictEqual(maxTitleLen, 300);
    validateRecord(
      { ...city, id: 'rec-title-300', title: 'A'.repeat(maxTitleLen) },
      { block: groupedBlock, existingBlockRecords: [grp], isNew: true }
    );
    assert.throws(
      () =>
        validateRecord(
          { ...city, id: 'rec-title-301', title: 'A'.repeat(maxTitleLen + 1) },
          { block: groupedBlock, existingBlockRecords: [grp], isNew: true }
        ),
      ProjectValidationError
    );
  });

  it('4. ProgressEngine preserves multi-block independence, computes schedule duration rules, and tracks tasks/milestones separately', () => {
    const asOfDate = CalendarDate.tryParse('2026-11-17')!;
    const projectWithoutPrimary: SharedProject = {
      id: 'proj-multi',
      title: 'Multi-block Study',
      status: 'active',
      isArchived: false,
      targetDate: '2026-11-26', // 10 days inclusive from 2026-11-17
      customFields: {},
      createdAt: NOW_ISO,
      updatedAt: NOW_ISO,
    };

    const blocks: SharedProjectTrackingBlock[] = [
      {
        id: 'blk-counter',
        projectId: 'proj-multi',
        blockType: 'counter',
        title: 'Practice Exercises',
        sortOrder: 0,
        unitLabel: 'exercises',
        targetValue: 100,
        dailyTargetValue: 10,
        isArchived: false,
        config: {},
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      },
      {
        id: 'blk-checklist',
        projectId: 'proj-multi',
        blockType: 'checklist',
        title: 'Setup Checklist',
        sortOrder: 1,
        isArchived: false,
        config: {},
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      },
    ];

    const records: SharedProjectTrackingRecord[] = [
      {
        id: 'log-c1',
        projectId: 'proj-multi',
        blockId: 'blk-counter',
        recordType: 'progress_log',
        sortOrder: 0,
        deltaValue: 40,
        isCompleted: false,
        recordedDate: '2026-11-17',
        metadata: {},
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      },
      {
        id: 'chk-1',
        projectId: 'proj-multi',
        blockId: 'blk-checklist',
        recordType: 'checklist_item',
        title: 'Install tools',
        sortOrder: 0,
        isCompleted: true,
        metadata: {},
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      },
      {
        id: 'chk-2',
        projectId: 'proj-multi',
        blockId: 'blk-checklist',
        recordType: 'checklist_item',
        title: 'Download assets',
        sortOrder: 1,
        isCompleted: false,
        metadata: {},
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      },
    ];

    const linkedTasks: SharedTask[] = [
      {
        id: 't-done',
        title: 'Done Task',
        status: 'completed',
        priority: 'medium',
        projectId: 'proj-multi',
        subtasks: [],
        labels: [],
        isPinned: false,
        isMyDay: false,
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      },
      {
        id: 't-open',
        title: 'Open Task',
        status: 'in_progress',
        priority: 'high',
        projectId: 'proj-multi',
        subtasks: [],
        labels: [],
        isPinned: false,
        isMyDay: false,
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      },
      {
        id: 't-cancelled',
        title: 'Cancelled Task',
        status: 'cancelled',
        priority: 'low',
        projectId: 'proj-multi',
        subtasks: [],
        labels: [],
        isPinned: false,
        isMyDay: false,
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      },
    ];

    const milestones: ProjectMilestoneInput[] = [
      { id: 'ms-1', projectId: 'proj-multi', title: 'M1', isCompleted: true, createdAt: NOW_ISO },
      { id: 'ms-2', projectId: 'proj-multi', title: 'M2', isCompleted: false, createdAt: NOW_ISO },
    ];

    // No primaryBlockId -> never averages 40% + 50%
    const summaryNoPrimary = calculateProjectProgressSummary({
      project: projectWithoutPrimary,
      blocks,
      records,
      linkedTasks,
      milestones,
      asOfDate,
    });
    assert.strictEqual(summaryNoPrimary.overallPercentage, undefined);
    assert.strictEqual(summaryNoPrimary.hasInvalidPrimaryBlockReference, false);
    assert.strictEqual(summaryNoPrimary.linkedTasksCompleted, 1);
    assert.strictEqual(summaryNoPrimary.linkedTasksTotal, 2); // cancelled excluded
    assert.strictEqual(summaryNoPrimary.milestonesCompleted, 1);
    assert.strictEqual(summaryNoPrimary.milestonesTotal, 2);
    assert.strictEqual(summaryNoPrimary.blockMetrics[0].progressPercent, 40);
    assert.strictEqual(summaryNoPrimary.blockMetrics[0].daysRemaining, 10);
    assert.strictEqual(summaryNoPrimary.blockMetrics[0].paceNeededPerDay, 6); // (100 - 40) / 10
    assert.strictEqual(summaryNoPrimary.blockMetrics[1].progressPercent, 50);

    // Explicit valid primaryBlockId
    const summaryWithPrimary = calculateProjectProgressSummary({
      project: { ...projectWithoutPrimary, customFields: { primaryBlockId: 'blk-counter' } },
      blocks,
      records,
      linkedTasks,
      milestones,
      asOfDate,
    });
    assert.strictEqual(summaryWithPrimary.primaryBlockId, 'blk-counter');
    assert.strictEqual(summaryWithPrimary.overallPercentage, 40);
    assert.strictEqual(summaryWithPrimary.hasInvalidPrimaryBlockReference, false);

    // Archived primaryBlockId flagged as invalid without falling back
    const summaryArchivedPrimary = calculateProjectProgressSummary({
      project: { ...projectWithoutPrimary, customFields: { primaryBlockId: 'blk-counter' } },
      blocks: blocks.map((b) => (b.id === 'blk-counter' ? { ...b, isArchived: true } : b)),
      records,
      asOfDate,
    });
    assert.strictEqual(summaryArchivedPrimary.hasInvalidPrimaryBlockReference, true);
    assert.strictEqual(summaryArchivedPrimary.overallPercentage, undefined);

    // Schedule duration rules
    assert.strictEqual(
      meetsScheduleDurationRule({
        plannedDurationMinutes: 60,
        actualLoggedMinutes: 60,
        config: parseScheduleBlockConfig({ completionRule: 'manual' }),
      }),
      false
    );
    assert.strictEqual(
      meetsScheduleDurationRule({
        plannedDurationMinutes: 60,
        actualLoggedMinutes: 48,
        config: parseScheduleBlockConfig({
          completionRule: 'threshold_percent',
          autoCompleteThresholdRatio: 0.8,
        }),
      }),
      true
    );
    assert.strictEqual(
      meetsScheduleDurationRule({
        plannedDurationMinutes: 60,
        actualLoggedMinutes: 59,
        config: parseScheduleBlockConfig({ completionRule: 'exact_duration' }),
      }),
      false
    );
  });

  it('5. WebProjectsRepository persists Projects/Blocks/Records, separates isArchived from status, validates FKs, and detaches tasks on deleteProject', () => {
    withMockBrowserStorage((store) => {
      const goals: SharedGoal[] = [
        { id: 'goal-1', title: 'Career Growth', status: 'active' },
      ];
      const tasks: SharedTask[] = [
        {
          id: 'task-1',
          title: 'Linked Task',
          status: 'completed',
          priority: 'medium',
          projectId: 'proj-bim',
          milestoneId: 'ms-1',
          subtasks: [],
          labels: [],
          isPinned: false,
          isMyDay: false,
          createdAt: NOW_ISO,
          updatedAt: NOW_ISO,
        },
      ];
      const milestones: ProjectMilestoneInput[] = [
        { id: 'ms-1', projectId: 'proj-bim', title: 'Phase 1', isCompleted: true, createdAt: NOW_ISO },
      ];
      store.set('daywell_goals', JSON.stringify(goals));
      store.set('daywell_tasks', JSON.stringify(tasks));
      store.set('daywell_milestones', JSON.stringify(milestones));

      const repo = new WebProjectsRepository();

      // Missing goalId rejected fail-closed
      assert.throws(
        () =>
          repo.createProject({
            id: 'proj-bad-goal',
            title: 'Orphan',
            status: 'active',
            goalId: 'goal-missing',
            isArchived: false,
            customFields: {},
            createdAt: NOW_ISO,
            updatedAt: NOW_ISO,
          }),
        ProjectValidationError
      );

      // Representative BIM Outreach fixture (4 regions + cities + rollup counter, NO 100-city seed)
      const bimProject = repo.createProject({
        id: 'proj-bim',
        title: 'BIM Outreach Initiative',
        status: 'on_hold',
        goalId: 'goal-1',
        isArchived: false,
        startDate: '2026-11-01',
        targetDate: '2026-12-31',
        customFields: {
          primaryBlockId: 'blk-bim-total',
          definitions: [
            { id: 'campaign_tier', label: 'Tier', type: 'select', required: true, options: ['Global', 'Regional'] },
          ],
          values: { campaign_tier: 'Global' },
        },
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      });
      assert.strictEqual(bimProject.status, 'on_hold');
      assert.strictEqual(bimProject.isArchived, false);

      // Archive preserves status separately
      const archivedBim = repo.setProjectArchived('proj-bim', true);
      assert.strictEqual(archivedBim.isArchived, true);
      assert.strictEqual(archivedBim.status, 'on_hold');
      assert.strictEqual(repo.getProjects({ includeArchived: false }).length, 0);
      assert.strictEqual(repo.getProjects({ includeArchived: true }).length, 1);
      repo.setProjectArchived('proj-bim', false);

      const glBlock = repo.createBlock({
        id: 'blk-bim-cities',
        projectId: 'proj-bim',
        blockType: 'grouped_list',
        title: 'Regional Cities',
        sortOrder: 0,
        unitLabel: 'outreaches',
        dailyTargetValue: 15,
        isArchived: false,
        config: { showGroupTotals: true, showDailyTotals: true, groupLabel: 'Region', itemLabel: 'City' },
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      });
      const rollupBlock = repo.createBlock({
        id: 'blk-bim-total',
        projectId: 'proj-bim',
        blockType: 'counter',
        title: 'Total Outreach Counter',
        sortOrder: 1,
        unitLabel: 'outreaches',
        targetValue: 100,
        isArchived: false,
        config: { rollupSourceBlockId: glBlock.id, allowDirectLogging: false },
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      });
      assert.strictEqual(rollupBlock.blockType, 'counter');

      for (const [idx, regionTitle] of ['North America', 'Europe', 'Asia-Pacific', 'Africa'].entries()) {
        repo.createRecord({
          id: `grp-${idx + 1}`,
          projectId: 'proj-bim',
          blockId: glBlock.id,
          recordType: 'group',
          title: regionTitle,
          sortOrder: idx,
          isCompleted: false,
          metadata: {},
          createdAt: NOW_ISO,
          updatedAt: NOW_ISO,
        });
      }
      repo.createRecord({
        id: 'city-addis',
        projectId: 'proj-bim',
        blockId: glBlock.id,
        parentRecordId: 'grp-4',
        recordType: 'grouped_item',
        title: 'Addis Ababa',
        sortOrder: 10,
        targetValue: 30,
        isCompleted: false,
        linkedTaskId: 'task-1',
        metadata: {},
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      });

      // 300-char title accepted; 301-char title rejected in WebProjectsRepository
      const maxRecTitle = SHARED_BUSINESS_RULES.projects.bounds.maxTrackingRecordTitleLength;
      repo.createRecord({
        id: 'city-max-300',
        projectId: 'proj-bim',
        blockId: glBlock.id,
        parentRecordId: 'grp-4',
        recordType: 'grouped_item',
        title: 'C'.repeat(maxRecTitle),
        sortOrder: 11,
        isCompleted: false,
        metadata: {},
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      });
      assert.throws(
        () =>
          repo.createRecord({
            id: 'city-over-301',
            projectId: 'proj-bim',
            blockId: glBlock.id,
            parentRecordId: 'grp-4',
            recordType: 'grouped_item',
            title: 'C'.repeat(maxRecTitle + 1),
            sortOrder: 12,
            isCompleted: false,
            metadata: {},
            createdAt: NOW_ISO,
            updatedAt: NOW_ISO,
          }),
        ProjectValidationError
      );

      // Missing linkedTaskId rejected
      assert.throws(
        () =>
          repo.createRecord({
            id: 'city-bad-task',
            projectId: 'proj-bim',
            blockId: glBlock.id,
            parentRecordId: 'grp-1',
            recordType: 'grouped_item',
            title: 'London',
            sortOrder: 11,
            isCompleted: false,
            linkedTaskId: 'task-nonexistent',
            metadata: {},
            createdAt: NOW_ISO,
            updatedAt: NOW_ISO,
          }),
        ProjectValidationError
      );

      const log1 = repo.appendProgressLog({
        id: 'log-bim-1',
        projectId: 'proj-bim',
        blockId: glBlock.id,
        parentRecordId: 'city-addis',
        recordType: 'progress_log',
        sortOrder: 20,
        deltaValue: 18,
        isCompleted: false,
        recordedDate: '2026-11-17',
        metadata: {},
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      });

      // Append-only log mutation / deletion rejected by repository
      assert.throws(() => repo.updateRecord({ ...log1, deltaValue: 99 }), ProjectValidationError);
      assert.throws(() => repo.deleteRecord(log1.id), ProjectValidationError);

      // Compensating correction updates totals cleanly
      repo.appendProgressCorrection({
        targetLogId: log1.id,
        correctionDelta: -3,
        recordedDate: '2026-11-17',
        reason: 'Bounced addresses',
        correctionId: 'corr-bim-1',
      });

      // Re-instantiate repository to verify real persistence round-trip
      const reloadedRepo = new WebProjectsRepository();
      const summary = reloadedRepo.getProjectProgressSummary('proj-bim', {
        asOfDate: CalendarDate.tryParse('2026-11-17')!,
      });
      assert.strictEqual(summary.overallPercentage, 15);
      assert.strictEqual(summary.blockMetrics[1].loggedTotal, 15);
      assert.strictEqual(summary.linkedTasksCompleted, 1);
      assert.strictEqual(summary.linkedTasksTotal, 1);
      assert.strictEqual(summary.milestonesCompleted, 1);
      assert.strictEqual(summary.milestonesTotal, 1);

      // deleteProject detaches linked tasks & removes blocks/records/milestones
      reloadedRepo.deleteProject('proj-bim');
      assert.strictEqual(reloadedRepo.getProjectById('proj-bim'), undefined);
      assert.strictEqual(reloadedRepo.getBlocksForProject('proj-bim').length, 0);
      assert.strictEqual(reloadedRepo.getRecordsForProject('proj-bim').length, 0);
      const tasksAfter = JSON.parse(store.get('daywell_tasks')!);
      assert.strictEqual(tasksAfter[0].projectId, undefined);
      assert.strictEqual(tasksAfter[0].milestoneId, undefined);
      assert.deepStrictEqual(JSON.parse(store.get('daywell_milestones')!), []);
    });
  });

  it('6. SharedStateBridge supports v9 export/import round-trip (Video Learning fixture), unordered parent/correction topological import, v4..v8 compat, purgeKnownSeedData, and fail-closed rejection', () => {
    withMockBrowserStorage((store) => {
      const repo = new WebProjectsRepository();
      store.set(
        'daywell_tasks',
        JSON.stringify([
          {
            id: 'task-video-edit',
            title: 'Practice Module 1',
            status: 'in_progress',
            priority: 'medium',
            projectId: 'proj-video',
            subtasks: [],
            labels: [],
            isPinned: false,
            isMyDay: false,
            createdAt: NOW_ISO,
            updatedAt: NOW_ISO,
          },
        ])
      );

      // Representative Video Learning Plan fixture
      repo.createProject({
        id: 'proj-video',
        title: 'Blender 3D Learning Plan',
        status: 'active',
        isArchived: false,
        startDate: '2026-11-15',
        targetDate: '2026-12-15',
        customFields: {
          primaryBlockId: 'blk-sched',
          definitions: [{ id: 'instructor', label: 'Course Instructor', type: 'text', required: false }],
          values: { instructor: 'Grant Abbitt' },
        },
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      });
      repo.createBlock({
        id: 'blk-sched',
        projectId: 'proj-video',
        blockType: 'schedule',
        title: 'Lesson Schedule',
        sortOrder: 0,
        unitLabel: 'minutes',
        isArchived: false,
        config: { completionRule: 'threshold_percent', autoCompleteThresholdRatio: 0.8, trackActualDuration: true },
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      });
      repo.createBlock({
        id: 'blk-chk',
        projectId: 'proj-video',
        blockType: 'checklist',
        title: 'Software Setup',
        sortOrder: 1,
        isArchived: false,
        config: { allowReorder: true },
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      });
      repo.createRecord({
        id: 'sched-1',
        projectId: 'proj-video',
        blockId: 'blk-sched',
        recordType: 'schedule_item',
        title: 'Day 1: Mesh Basics',
        sortOrder: 0,
        durationMinutes: 60,
        scheduledDate: '2026-11-17',
        linkedTaskId: 'task-video-edit',
        isCompleted: false,
        metadata: {},
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      });
      repo.appendProgressLog({
        id: 'log-sched-1',
        projectId: 'proj-video',
        blockId: 'blk-sched',
        parentRecordId: 'sched-1',
        recordType: 'progress_log',
        sortOrder: 1,
        deltaValue: 50,
        isCompleted: false,
        recordedDate: '2026-11-17',
        metadata: {},
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      });
      repo.createRecord({
        id: 'chk-item-1',
        projectId: 'proj-video',
        blockId: 'blk-chk',
        recordType: 'checklist_item',
        title: 'Install Blender 4.2',
        sortOrder: 0,
        isCompleted: true,
        metadata: {},
        createdAt: NOW_ISO,
        updatedAt: NOW_ISO,
      });

      const exported = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(exported.schemaVersion, 5);
      assert.strictEqual(exported.snapshotFormatVersion, 2);
      assert.strictEqual(exported.financeSchemaVersion, 7);
      assert.strictEqual(exported.projectTrackingBlocks?.length, 2);
      assert.strictEqual(exported.projectTrackingRecords?.length, 3);

      // Re-import exported v5/snapshotFormatVersion=2 AND unordered legacy v9 payload + orphan linkedTaskId
      const directReimport = SharedStateBridge.importFromAndroidJson(JSON.stringify(exported));
      assert.strictEqual(directReimport.success, true, directReimport.error);
      assert.strictEqual(directReimport.state?.snapshotFormatVersion, 2);

      const reorderedPayload = {
        ...exported,
        schemaVersion: 9,
        projectTrackingRecords: [
          {
            id: 'corr-sched-1',
            projectId: 'proj-video',
            blockId: 'blk-sched',
            parentRecordId: 'sched-1',
            recordType: 'progress_log',
            sortOrder: 2,
            deltaValue: -5,
            isCompleted: false,
            recordedDate: '2026-11-17',
            metadata: {
              isCorrection: true,
              compensatesRecordId: 'log-sched-1',
              correctionReason: 'Break adjustment',
            },
            createdAt: NOW_ISO,
            updatedAt: NOW_ISO,
          },
          exported.projectTrackingRecords![1], // log-sched-1
          { ...exported.projectTrackingRecords![0], linkedTaskId: 'missing-task-id' }, // sched-1 before parent? topologically sorted
          exported.projectTrackingRecords![2], // chk-item-1
        ],
      };

      const importRes = SharedStateBridge.importFromAndroidJson(JSON.stringify(reorderedPayload));
      assert.strictEqual(importRes.success, true, importRes.error);

      const afterReimport = SharedStateBridge.assembleLiveDatabaseState();
      assert.strictEqual(afterReimport.projectTrackingRecords?.length, 4);
      const schedAfter = afterReimport.projectTrackingRecords!.find((r) => r.id === 'sched-1')!;
      assert.strictEqual(schedAfter.linkedTaskId, undefined);

      // 301-char record title rejected fail-closed in SharedStateBridge BEFORE mutating localStorage
      const recordsBeforeTooLong = store.get(SharedStateBridge.PROJECT_TRACKING_RECORDS_STORAGE_KEY);
      const tooLongRecordRes = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          ...exported,
          projectTrackingRecords: [
            ...exported.projectTrackingRecords!,
            {
              id: 'chk-item-301',
              projectId: 'proj-video',
              blockId: 'blk-chk',
              recordType: 'checklist_item',
              title: 'R'.repeat(SHARED_BUSINESS_RULES.projects.bounds.maxTrackingRecordTitleLength + 1),
              sortOrder: 9,
              isCompleted: false,
              metadata: {},
              createdAt: NOW_ISO,
              updatedAt: NOW_ISO,
            },
          ],
        })
      );
      assert.strictEqual(tooLongRecordRes.success, false);
      assert.strictEqual(tooLongRecordRes.errorKind, 'invalid_payload');
      assert.strictEqual(
        store.get(SharedStateBridge.PROJECT_TRACKING_RECORDS_STORAGE_KEY),
        recordsBeforeTooLong
      );

      // Invalid cyclic snapshot rejects fail-closed BEFORE mutating localStorage
      const snapshotBeforeReject = store.get(SharedStateBridge.PROJECT_TRACKING_RECORDS_STORAGE_KEY);
      const cyclicReject = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          schemaVersion: 9,
          accounts: [],
          transactions: [],
          projects: [
            {
              id: 'proj-bad',
              title: 'Bad',
              status: 'active',
              isArchived: false,
              createdAt: NOW_ISO,
              updatedAt: NOW_ISO,
            },
          ],
          projectTrackingBlocks: [
            {
              id: 'blk-bad',
              projectId: 'proj-bad',
              blockType: 'grouped_list',
              title: 'GL',
              sortOrder: 0,
              isArchived: false,
              config: {},
              createdAt: NOW_ISO,
              updatedAt: NOW_ISO,
            },
          ],
          projectTrackingRecords: [
            {
              id: 'r-a',
              projectId: 'proj-bad',
              blockId: 'blk-bad',
              parentRecordId: 'r-b',
              recordType: 'grouped_item',
              title: 'A',
              sortOrder: 0,
              isCompleted: false,
              metadata: {},
              createdAt: NOW_ISO,
              updatedAt: NOW_ISO,
            },
            {
              id: 'r-b',
              projectId: 'proj-bad',
              blockId: 'blk-bad',
              parentRecordId: 'r-a',
              recordType: 'grouped_item',
              title: 'B',
              sortOrder: 1,
              isCompleted: false,
              metadata: {},
              createdAt: NOW_ISO,
              updatedAt: NOW_ISO,
            },
          ],
        })
      );
      assert.strictEqual(cyclicReject.success, false);
      assert.strictEqual(
        store.get(SharedStateBridge.PROJECT_TRACKING_RECORDS_STORAGE_KEY),
        snapshotBeforeReject
      );

      // Backward compatibility: v8 snapshot without Stage 1 arrays imports cleanly
      const v8Compat = SharedStateBridge.importFromAndroidJson(
        JSON.stringify({
          schemaVersion: 8,
          financeSchemaVersion: 7,
          accounts: [],
          transactions: [],
          projects: [
            {
              id: 'proj-v8',
              title: 'Legacy v8 Project',
              status: 'active',
              createdAt: NOW_ISO,
            },
          ],
        })
      );
      assert.strictEqual(v8Compat.success, true, v8Compat.error);
      assert.strictEqual(v8Compat.state?.projects.length, 1);
      assert.deepStrictEqual(v8Compat.state?.projectTrackingBlocks, []);
      assert.deepStrictEqual(v8Compat.state?.projectTrackingRecords, []);

      // purgeKnownSeedData clears seed projects & tracking entities while keeping user projects
      store.set(
        SharedStateBridge.PROJECTS_STORAGE_KEY,
        JSON.stringify([
          { id: 'proj-1', title: 'Seed Project', status: 'active', createdAt: NOW_ISO },
          { id: 'proj-user-keep', title: 'User Project', status: 'active', createdAt: NOW_ISO },
        ])
      );
      store.set(
        SharedStateBridge.PROJECT_TRACKING_BLOCKS_STORAGE_KEY,
        JSON.stringify([
          { id: 'blk-seed', projectId: 'proj-1', blockType: 'counter', title: 'Seed', sortOrder: 0, isArchived: false, config: {}, createdAt: NOW_ISO, updatedAt: NOW_ISO },
          { id: 'blk-user', projectId: 'proj-user-keep', blockType: 'counter', title: 'User', sortOrder: 0, isArchived: false, config: {}, createdAt: NOW_ISO, updatedAt: NOW_ISO },
        ])
      );
      store.set(
        SharedStateBridge.PROJECT_TRACKING_RECORDS_STORAGE_KEY,
        JSON.stringify([
          { id: 'rec-seed', projectId: 'proj-1', blockId: 'blk-seed', recordType: 'progress_log', sortOrder: 0, deltaValue: 1, isCompleted: false, recordedDate: '2026-11-17', metadata: {}, createdAt: NOW_ISO, updatedAt: NOW_ISO },
          { id: 'rec-user', projectId: 'proj-user-keep', blockId: 'blk-user', recordType: 'progress_log', sortOrder: 0, deltaValue: 2, isCompleted: false, recordedDate: '2026-11-17', metadata: {}, createdAt: NOW_ISO, updatedAt: NOW_ISO },
        ])
      );
      const purged = SharedStateBridge.purgeKnownSeedData();
      assert.ok(purged.purgedCount >= 3);
      assert.deepStrictEqual(
        JSON.parse(store.get(SharedStateBridge.PROJECTS_STORAGE_KEY)!).map((p: SharedProject) => p.id),
        ['proj-user-keep']
      );
      assert.deepStrictEqual(
        JSON.parse(store.get(SharedStateBridge.PROJECT_TRACKING_BLOCKS_STORAGE_KEY)!).map((b: SharedProjectTrackingBlock) => b.id),
        ['blk-user']
      );
      assert.deepStrictEqual(
        JSON.parse(store.get(SharedStateBridge.PROJECT_TRACKING_RECORDS_STORAGE_KEY)!).map((r: SharedProjectTrackingRecord) => r.id),
        ['rec-user']
      );
    });
  });
});
