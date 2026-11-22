import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import {
  SHARED_BUSINESS_RULES,
  CANONICAL_TASK_STATUSES,
  CANONICAL_TASK_PRIORITIES,
  CANONICAL_TASK_RECURRENCE_FREQUENCIES,
  CANONICAL_TASK_RECURRENCE_REPEAT_FROM,
  CANONICAL_DAILY_PLANNING_ACTIONS,
  PLANNED_TASK_V10_FIELDS,
  SharedTask,
  SharedCanonicalTaskSubtask,
  SharedTaskSubtask,
  SharedLegacyTaskSubtask,
  SharedTaskRecurrenceConfig,
  SharedMilestone,
  SharedDailyPlanningEntry,
  SharedDatabaseState,
} from './sharedFoundation';
// @ts-ignore - ESM governance script validated dynamically by Node test runner
import { validateBusinessRules, validateSchemaContracts } from '../../scripts/sync_foundation.mjs';

const REPO_ROOT = process.cwd();

describe('STAGE 0.2A — CANONICAL TASK DATA CONTRACT ALIGNMENT', () => {
  it('1. schema_contracts.json declares schemaVersion 11 and keeps separated v9 baseline vs v10 Task/DailyPlanningEntry contracts', () => {
    const contracts = JSON.parse(
      fs.readFileSync(path.join(REPO_ROOT, 'shared_foundation', 'schema_contracts.json'), 'utf8')
    );

    assert.strictEqual(contracts.version, '2.0.0');
    assert.strictEqual(contracts.schemaVersion, 11);
    assert.strictEqual(contracts.timeConvention.id, 'Africa/Addis_Ababa');
    assert.strictEqual(contracts.timeConvention.fixedUtcOffsetMinutes, 180);

    const taskFields = contracts.entities.Task.fields;
    assert.ok(taskFields, 'Task entity fields must exist');

    // Existing retained v9 baseline fields (must not declare plannedDatabaseSchemaVersion: 10)
    for (const expectedField of [
      'id',
      'title',
      'description',
      'status',
      'priority',
      'dueDate',
      'scheduledDate',
      'projectId',
      'milestoneId',
      'estimatedDurationMinutes',
      'subtasks',
      'labels',
      'isPinned',
      'isMyDay',
      'recurrenceRule',
      'createdAt',
      'updatedAt',
    ]) {
      assert.ok(expectedField in taskFields, `Task must retain canonical field "${expectedField}"`);
      assert.strictEqual(
        taskFields[expectedField].plannedDatabaseSchemaVersion,
        undefined,
        `Existing v9 Task field "${expectedField}" must remain in v9 baseline`
      );
    }

    // Canonical subtask schema & legacy alias metadata
    assert.deepStrictEqual(taskFields.subtasks, {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string', required: false },
          title: { type: 'string', required: true },
          done: { type: 'boolean', required: true, default: false },
        },
        legacyAliases: {
          doneFrom: 'completed',
          optionalIdOnLegacyRead: true,
        },
      },
      default: [],
    });

    // Newly aligned additive Task fields explicitly tagged as planned for DB v10
    assert.deepStrictEqual(taskFields.completedAt, {
      type: 'string',
      format: 'date-time',
      required: false,
      plannedDatabaseSchemaVersion: 10,
    });
    assert.deepStrictEqual(taskFields.scheduledTime, {
      type: 'string',
      format: 'time',
      required: false,
      plannedDatabaseSchemaVersion: 10,
    });
    assert.deepStrictEqual(taskFields.myDayDate, {
      type: 'string',
      format: 'date',
      required: false,
      plannedDatabaseSchemaVersion: 10,
    });
    assert.deepStrictEqual(taskFields.recurrenceConfig, {
      type: 'object',
      required: false,
      plannedDatabaseSchemaVersion: 10,
      properties: {
        frequency: {
          type: 'string',
          enum: ['daily', 'weekly', 'monthly', 'yearly'],
          required: true,
        },
        interval: {
          type: 'integer',
          minimum: 1,
          default: 1,
          required: false,
        },
        weekdays: {
          type: 'array',
          items: { type: 'integer', minimum: 1, maximum: 7 },
          required: false,
        },
        startDate: { type: 'string', format: 'date', required: false },
        endDate: { type: 'string', format: 'date', required: false },
        repeatFrom: {
          type: 'string',
          enum: ['due_date', 'completion_date'],
          default: 'due_date',
          required: false,
        },
      },
    });
    assert.deepStrictEqual(taskFields.isArchived, {
      type: 'boolean',
      default: false,
      plannedDatabaseSchemaVersion: 10,
    });
    assert.deepStrictEqual(taskFields.sortOrder, {
      type: 'integer',
      minimum: 0,
      default: 0,
      required: false,
      plannedDatabaseSchemaVersion: 10,
    });

    assert.deepStrictEqual(Array.from(PLANNED_TASK_V10_FIELDS), [
      'completedAt',
      'scheduledTime',
      'myDayDate',
      'recurrenceConfig',
      'isArchived',
      'sortOrder',
    ]);

    // Deliberate exclusions (single source of truth & no dangling FK/entity bloat)
    assert.strictEqual(
      'hasReminder' in taskFields,
      false,
      'Task must not store dual-truth hasReminder; reminder state derives from Reminder records'
    );
    assert.strictEqual(
      'completed' in taskFields,
      false,
      'Task must not duplicate completion in a boolean field; status === "completed" is canonical'
    );
    assert.strictEqual(
      'sectionId' in taskFields,
      false,
      'Task must not declare sectionId without an agreed ProjectSection entity/table'
    );
    assert.strictEqual(
      'ProjectSection' in contracts.entities,
      false,
      'schema_contracts.json must not declare unapproved ProjectSection entity'
    );

    // Coupled Milestone contract stays untouched at its 6 existing persisted fields
    const milestoneFields = contracts.entities.Milestone.fields;
    assert.deepStrictEqual(Object.keys(milestoneFields), [
      'id',
      'projectId',
      'title',
      'dueDate',
      'isCompleted',
      'createdAt',
    ]);
    assert.strictEqual(contracts.entities.Milestone.plannedDatabaseSchemaVersion, undefined);
    assert.strictEqual(milestoneFields.dueDate.format, 'date');
    assert.strictEqual(milestoneFields.createdAt.format, 'date-time');

    // DailyPlanningEntry planned for DB v10 with unique (taskId, planDate) and cascade delete
    const planningEntity = contracts.entities.DailyPlanningEntry;
    assert.strictEqual(planningEntity.plannedDatabaseSchemaVersion, 10);
    assert.deepStrictEqual(planningEntity.uniqueKey, ['taskId', 'planDate']);
    assert.strictEqual(planningEntity.onTaskDelete, 'cascade');
    assert.deepStrictEqual(Object.keys(planningEntity.fields), [
      'id',
      'planDate',
      'taskId',
      'action',
      'createdAt',
      'updatedAt',
    ]);
    assert.strictEqual(planningEntity.fields.planDate.format, 'date');
    assert.deepStrictEqual(planningEntity.fields.action.enum, [
      'planned',
      'carried_forward',
      'completed',
      'dismissed',
    ]);
    assert.strictEqual(planningEntity.fields.action.default, 'planned');
  });

  it('2. business_rules.json defines canonical Task rules, recurrence basis, subtask compatibility, and Inbox separation', () => {
    const rules = JSON.parse(
      fs.readFileSync(path.join(REPO_ROOT, 'shared_foundation', 'business_rules.json'), 'utf8')
    );

    assert.deepStrictEqual(rules.tasks.statuses, [
      'not_started',
      'in_progress',
      'completed',
      'cancelled',
      'inbox',
    ]);
    assert.deepStrictEqual(rules.tasks.priorities, ['low', 'medium', 'high', 'urgent']);
    assert.deepStrictEqual(rules.tasks.recurrenceFrequencies, [
      'daily',
      'weekly',
      'monthly',
      'yearly',
    ]);
    assert.deepStrictEqual(rules.tasks.recurrenceRepeatFromModes, [
      'due_date',
      'completion_date',
    ]);
    assert.strictEqual(rules.tasks.defaultRecurrenceRepeatFrom, 'due_date');
    assert.strictEqual(rules.tasks.recurrenceCalendarBasis, 'gregorian');
    assert.strictEqual(rules.tasks.weekdayConvention, 'iso_1_to_7');
    assert.strictEqual(rules.tasks.minWeekday, 1);
    assert.strictEqual(rules.tasks.maxWeekday, 7);
    assert.strictEqual(rules.tasks.minRecurrenceInterval, 1);
    assert.deepStrictEqual(rules.tasks.dailyPlanningUniqueKey, ['taskId', 'planDate']);
    assert.strictEqual(rules.tasks.dailyPlanningOnTaskDelete, 'cascade');
    assert.deepStrictEqual(rules.tasks.subtaskCanonicalFields, ['id', 'title', 'done']);
    assert.strictEqual(rules.tasks.subtaskLegacyDoneAlias, 'completed');
    assert.strictEqual(rules.tasks.subtaskLegacyIdOptional, true);
    assert.strictEqual(rules.tasks.defaultStatus, 'not_started');
    assert.strictEqual(rules.tasks.defaultPriority, 'medium');
    assert.deepStrictEqual(rules.tasks.rules, {
      deriveReminderStateFromReminders: true,
      singleCompletionSourceInStatus: true,
      utcIsoCompletedAt: true,
      preserveMyDayPlanningHistory: true,
      separateInboxFromUnassignedTasks: true,
      uniqueDailyPlanningEntryPerTaskDate: true,
      cascadeDeleteDailyPlanningOnTaskDelete: true,
    });

    assert.deepStrictEqual(SHARED_BUSINESS_RULES.tasks, rules.tasks);
  });

  it('3. Generated TypeScript and pure-Dart SharedTaskContracts stay synchronized and pure-Dart isolated', () => {
    const contracts = JSON.parse(
      fs.readFileSync(path.join(REPO_ROOT, 'shared_foundation', 'schema_contracts.json'), 'utf8')
    );
    const rules = JSON.parse(
      fs.readFileSync(path.join(REPO_ROOT, 'shared_foundation', 'business_rules.json'), 'utf8')
    );
    const dartCoreSource = fs.readFileSync(
      path.join(REPO_ROOT, 'flutter_app', 'lib', 'core', 'shared_foundation_core.dart'),
      'utf8'
    );

    // TS generated enum & metadata constants
    assert.deepStrictEqual(
      Array.from(CANONICAL_TASK_STATUSES),
      contracts.entities.Task.fields.status.enum
    );
    assert.deepStrictEqual(
      Array.from(CANONICAL_TASK_PRIORITIES),
      contracts.entities.Task.fields.priority.enum
    );
    assert.deepStrictEqual(
      Array.from(CANONICAL_TASK_RECURRENCE_FREQUENCIES),
      rules.tasks.recurrenceFrequencies
    );
    assert.deepStrictEqual(
      Array.from(CANONICAL_TASK_RECURRENCE_REPEAT_FROM),
      contracts.entities.Task.fields.recurrenceConfig.properties.repeatFrom.enum
    );
    assert.deepStrictEqual(
      Array.from(CANONICAL_DAILY_PLANNING_ACTIONS),
      contracts.entities.DailyPlanningEntry.fields.action.enum
    );

    // Pure-Dart isolation & SharedTaskContracts parity
    assert.strictEqual(dartCoreSource.includes('package:flutter/'), false);
    assert.strictEqual(dartCoreSource.includes('dart:ui'), false);

    const taskContractsMatch = dartCoreSource.match(
      /class SharedTaskContracts \{([\s\S]*?)\n\}/
    );
    assert.ok(taskContractsMatch, 'SharedTaskContracts class must be generated in Dart core');
    const body = taskContractsMatch[1].replace(/\s+/g, ' ');

    for (const status of CANONICAL_TASK_STATUSES) {
      assert.ok(body.includes(`'${status}'`), `Missing Dart task status "${status}"`);
    }
    for (const priority of CANONICAL_TASK_PRIORITIES) {
      assert.ok(body.includes(`'${priority}'`), `Missing Dart task priority "${priority}"`);
    }
    for (const freq of CANONICAL_TASK_RECURRENCE_FREQUENCIES) {
      assert.ok(body.includes(`'${freq}'`), `Missing Dart recurrence frequency "${freq}"`);
    }
    for (const mode of CANONICAL_TASK_RECURRENCE_REPEAT_FROM) {
      assert.ok(body.includes(`'${mode}'`), `Missing Dart repeatFrom mode "${mode}"`);
    }
    for (const action of CANONICAL_DAILY_PLANNING_ACTIONS) {
      assert.ok(body.includes(`'${action}'`), `Missing Dart planning action "${action}"`);
    }
    for (const plannedField of PLANNED_TASK_V10_FIELDS) {
      assert.ok(body.includes(`'${plannedField}'`), `Missing Dart planned v10 field "${plannedField}"`);
    }

    assert.ok(body.includes("static const String defaultStatus = 'not_started';"));
    assert.ok(body.includes("static const String defaultPriority = 'medium';"));
    assert.ok(body.includes("static const String defaultRecurrenceRepeatFrom = 'due_date';"));
    assert.ok(body.includes("static const String recurrenceCalendarBasis = 'gregorian';"));
    assert.ok(body.includes("static const String weekdayConvention = 'iso_1_to_7';"));
    assert.ok(body.includes('static const int minWeekday = 1;'));
    assert.ok(body.includes('static const int maxWeekday = 7;'));
    assert.ok(body.includes('static const int minRecurrenceInterval = 1;'));
    assert.ok(body.includes("static const String subtaskLegacyDoneAlias = 'completed';"));
    assert.ok(body.includes('static const bool subtaskLegacyIdOptional = true;'));
    assert.ok(body.includes("static const String dailyPlanningOnTaskDelete = 'cascade';"));
    assert.ok(body.includes('static const bool deriveReminderStateFromReminders = true;'));
    assert.ok(body.includes('static const bool singleCompletionSourceInStatus = true;'));
    assert.ok(body.includes('static const bool utcIsoCompletedAt = true;'));
    assert.ok(body.includes('static const bool preserveMyDayPlanningHistory = true;'));
    assert.ok(body.includes('static const bool separateInboxFromUnassignedTasks = true;'));
    assert.ok(body.includes('static const bool uniqueDailyPlanningEntryPerTaskDate = true;'));
    assert.ok(body.includes('static const bool cascadeDeleteDailyPlanningOnTaskDelete = true;'));

    // Compile-time structural verification of generated canonical & legacy subtask and Task contracts
    const canonicalSubtask: SharedCanonicalTaskSubtask = {
      id: 'st-1',
      title: 'Check ledger',
      done: true,
    };
    const normalizedSubtask: SharedTaskSubtask = canonicalSubtask;
    const legacyWebSubtask: SharedLegacyTaskSubtask = {
      id: 'st-legacy-1',
      title: 'Legacy Web subtask',
      completed: false,
    };
    const recurrenceConfig: SharedTaskRecurrenceConfig = {
      frequency: 'weekly',
      interval: 2,
      weekdays: [1, 3, 5],
      startDate: '2026-11-01',
      endDate: '2027-01-31',
      repeatFrom: 'due_date',
    };
    const sampleTask: SharedTask = {
      id: 'task-contract-1',
      title: 'Prepare monthly close',
      status: 'completed',
      priority: 'high',
      completedAt: '2026-11-21T08:30:00.000Z',
      dueDate: '2026-11-21',
      scheduledDate: '2026-11-21',
      scheduledTime: '09:00',
      projectId: 'proj-1',
      milestoneId: 'ms-1',
      estimatedDurationMinutes: 45,
      subtasks: [normalizedSubtask],
      labels: ['work'],
      isPinned: false,
      isMyDay: true,
      myDayDate: '2026-11-21',
      recurrenceRule: 'weekly',
      recurrenceConfig,
      isArchived: false,
      sortOrder: 0,
      createdAt: '2026-11-20T06:00:00.000Z',
      updatedAt: '2026-11-21T08:30:00.000Z',
    };
    const sampleMilestone: SharedMilestone = {
      id: 'ms-1',
      projectId: 'proj-1',
      title: 'Q4 Reconciliation',
      dueDate: '2026-11-30',
      isCompleted: false,
      createdAt: '2026-11-01T06:00:00.000Z',
    };
    const samplePlanningEntry: SharedDailyPlanningEntry = {
      id: 'plan-1',
      planDate: '2026-11-21',
      taskId: sampleTask.id,
      action: 'carried_forward',
      createdAt: '2026-11-21T05:00:00.000Z',
    };
    const snapshotSlice: Pick<
      SharedDatabaseState,
      'tasks' | 'milestones' | 'dailyPlanningEntries'
    > = {
      tasks: [sampleTask],
      milestones: [sampleMilestone],
      dailyPlanningEntries: [samplePlanningEntry],
    };

    assert.strictEqual(legacyWebSubtask.completed, false);
    assert.strictEqual(snapshotSlice.tasks[0].completedAt, '2026-11-21T08:30:00.000Z');
    assert.strictEqual(snapshotSlice.milestones?.[0].id, 'ms-1');
    assert.strictEqual(snapshotSlice.dailyPlanningEntries?.[0].action, 'carried_forward');
  });

  it('4. Generator validators reject invalid task rules, recurrence schemas, or daily planning constraints fail-closed', () => {
    const contracts = JSON.parse(
      fs.readFileSync(path.join(REPO_ROOT, 'shared_foundation', 'schema_contracts.json'), 'utf8')
    );
    const rules = JSON.parse(
      fs.readFileSync(path.join(REPO_ROOT, 'shared_foundation', 'business_rules.json'), 'utf8')
    );

    assert.doesNotThrow(() => validateSchemaContracts(contracts));
    assert.doesNotThrow(() => validateBusinessRules(rules));

    const badStatusRules = structuredClone(rules);
    badStatusRules.tasks.defaultStatus = 'nonexistent';
    assert.throws(
      () => validateBusinessRules(badStatusRules),
      /tasks\.defaultStatus.*is not in tasks\.statuses/
    );

    const badFlagRules = structuredClone(rules);
    badFlagRules.tasks.rules.preserveMyDayPlanningHistory = 'yes';
    assert.throws(
      () => validateBusinessRules(badFlagRules),
      /tasks\.rules\.preserveMyDayPlanningHistory/
    );

    const badCalendarBasisRules = structuredClone(rules);
    badCalendarBasisRules.tasks.recurrenceCalendarBasis = 'lunar';
    assert.throws(
      () => validateBusinessRules(badCalendarBasisRules),
      /tasks\.recurrenceCalendarBasis/
    );

    const badPlannedVersionSchema = structuredClone(contracts);
    badPlannedVersionSchema.entities.Task.fields.completedAt.plannedDatabaseSchemaVersion = 8;
    assert.throws(
      () => validateSchemaContracts(badPlannedVersionSchema),
      /plannedDatabaseSchemaVersion/
    );

    const badRepeatFromSchema = structuredClone(contracts);
    badRepeatFromSchema.entities.Task.fields.recurrenceConfig.properties.repeatFrom.default = 'invalid_mode';
    assert.throws(
      () => validateSchemaContracts(badRepeatFromSchema),
      /repeatFrom\.default/
    );

    const badUniqueKeySchema = structuredClone(contracts);
    badUniqueKeySchema.entities.DailyPlanningEntry.uniqueKey = ['taskId', 'missingField'];
    assert.throws(
      () => validateSchemaContracts(badUniqueKeySchema),
      /DailyPlanningEntry\.uniqueKey/
    );
  });
});
