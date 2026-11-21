import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import {
  SHARED_BUSINESS_RULES,
  CANONICAL_TASK_STATUSES,
  CANONICAL_TASK_PRIORITIES,
  CANONICAL_TASK_RECURRENCE_FREQUENCIES,
  CANONICAL_DAILY_PLANNING_ACTIONS,
  SharedTask,
  SharedMilestone,
  SharedDailyPlanningEntry,
  SharedDatabaseState,
} from './sharedFoundation';
// @ts-ignore - ESM governance script validated dynamically by Node test runner
import { validateBusinessRules, validateSchemaContracts } from '../../scripts/sync_foundation.mjs';

const REPO_ROOT = process.cwd();

describe('STAGE 0.2A — CANONICAL TASK DATA CONTRACT ALIGNMENT', () => {
  it('1. schema_contracts.json retains schemaVersion 9, version 2.0.0, and complete Task/Milestone/DailyPlanningEntry contracts', () => {
    const contracts = JSON.parse(
      fs.readFileSync(path.join(REPO_ROOT, 'shared_foundation', 'schema_contracts.json'), 'utf8')
    );

    assert.strictEqual(contracts.version, '2.0.0');
    assert.strictEqual(contracts.schemaVersion, 9);
    assert.strictEqual(contracts.timeConvention.id, 'Africa/Addis_Ababa');
    assert.strictEqual(contracts.timeConvention.fixedUtcOffsetMinutes, 180);

    const taskFields = contracts.entities.Task.fields;
    assert.ok(taskFields, 'Task entity fields must exist');

    // Existing retained baseline fields
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
    }

    // Newly aligned additive Task fields
    assert.deepStrictEqual(taskFields.completedAt, {
      type: 'string',
      format: 'date-time',
      required: false,
    });
    assert.deepStrictEqual(taskFields.scheduledTime, {
      type: 'string',
      format: 'time',
      required: false,
    });
    assert.deepStrictEqual(taskFields.myDayDate, {
      type: 'string',
      format: 'date',
      required: false,
    });
    assert.deepStrictEqual(taskFields.recurrenceConfig, {
      type: 'object',
      required: false,
    });
    assert.deepStrictEqual(taskFields.isArchived, {
      type: 'boolean',
      default: false,
    });
    assert.deepStrictEqual(taskFields.sortOrder, {
      type: 'integer',
      minimum: 0,
      default: 0,
      required: false,
    });

    // Deliberate exclusions (single source of truth & no dangling FK bloat)
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

    // Coupled Milestone & DailyPlanningEntry contracts
    const milestoneFields = contracts.entities.Milestone.fields;
    assert.deepStrictEqual(Object.keys(milestoneFields), [
      'id',
      'projectId',
      'title',
      'dueDate',
      'isCompleted',
      'createdAt',
    ]);
    assert.strictEqual(milestoneFields.dueDate.format, 'date');
    assert.strictEqual(milestoneFields.createdAt.format, 'date-time');

    const planningFields = contracts.entities.DailyPlanningEntry.fields;
    assert.deepStrictEqual(Object.keys(planningFields), [
      'id',
      'planDate',
      'taskId',
      'action',
      'createdAt',
      'updatedAt',
    ]);
    assert.strictEqual(planningFields.planDate.format, 'date');
    assert.deepStrictEqual(planningFields.action.enum, [
      'planned',
      'carried_forward',
      'completed',
      'dismissed',
    ]);
    assert.strictEqual(planningFields.action.default, 'planned');
  });

  it('2. business_rules.json defines canonical Task enums, weights, and Stage 0.2A domain rule flags', () => {
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
    assert.strictEqual(rules.tasks.defaultStatus, 'not_started');
    assert.strictEqual(rules.tasks.defaultPriority, 'medium');
    assert.deepStrictEqual(rules.tasks.rules, {
      deriveReminderStateFromReminders: true,
      singleCompletionSourceInStatus: true,
      utcIsoCompletedAt: true,
      preserveMyDayPlanningHistory: true,
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

    // TS generated enum constants
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
    for (const action of CANONICAL_DAILY_PLANNING_ACTIONS) {
      assert.ok(body.includes(`'${action}'`), `Missing Dart planning action "${action}"`);
    }

    assert.ok(body.includes("static const String defaultStatus = 'not_started';"));
    assert.ok(body.includes("static const String defaultPriority = 'medium';"));
    assert.ok(body.includes('static const bool deriveReminderStateFromReminders = true;'));
    assert.ok(body.includes('static const bool singleCompletionSourceInStatus = true;'));
    assert.ok(body.includes('static const bool utcIsoCompletedAt = true;'));
    assert.ok(body.includes('static const bool preserveMyDayPlanningHistory = true;'));

    // Compile-time structural verification of generated SharedTask / SharedMilestone / SharedDailyPlanningEntry
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
      subtasks: [{ id: 'st-1', title: 'Check ledger', done: true }],
      labels: ['work'],
      isPinned: false,
      isMyDay: true,
      myDayDate: '2026-11-21',
      recurrenceRule: 'monthly',
      recurrenceConfig: {
        frequency: 'monthly',
        interval: 1,
        startDate: '2026-11-01',
        repeatFrom: 'due_date',
      },
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

    assert.strictEqual(snapshotSlice.tasks[0].completedAt, '2026-11-21T08:30:00.000Z');
    assert.strictEqual(snapshotSlice.milestones?.[0].id, 'ms-1');
    assert.strictEqual(snapshotSlice.dailyPlanningEntries?.[0].action, 'carried_forward');
  });

  it('4. Generator validators reject invalid task rules or mismatched defaults fail-closed', () => {
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
  });
});
