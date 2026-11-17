import {
  SHARED_BUSINESS_RULES,
  SharedProject,
  SharedProjectBlockType,
  SharedProjectCustomFieldType,
  SharedProjectCustomFieldsPayload,
  SharedProjectRecordType,
  SharedProjectTrackingBlock,
  SharedProjectTrackingRecord,
  SharedTask,
} from './sharedFoundation';
import { CalendarDate } from './date';

export class ProjectValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ProjectValidationError';
  }
}

export type ScheduleItemCompletionRule =
  | 'manual'
  | 'threshold_percent'
  | 'exact_duration';

export interface CounterBlockConfig {
  rollupSourceBlockId?: string;
  allowDirectLogging: boolean;
}

export interface GroupedListBlockConfig {
  showGroupTotals: boolean;
  showDailyTotals: boolean;
  groupLabel?: string;
  itemLabel?: string;
}

export interface ChecklistBlockConfig {
  allowReorder: boolean;
}

export interface ScheduleBlockConfig {
  completionRule: ScheduleItemCompletionRule;
  autoCompleteThresholdRatio: number;
  trackActualDuration: boolean;
}

export interface ProjectMilestoneInput {
  id: string;
  projectId: string;
  title: string;
  dueDate?: string;
  isCompleted: boolean;
  createdAt: string;
}

export interface ProjectGroupMetric {
  groupId: string;
  title: string;
  targetValue?: number;
  loggedTotal: number;
  itemCount: number;
  completedItemCount: number;
  progressPercent?: number;
}

export interface ProjectBlockProgressMetric {
  blockId: string;
  blockType: SharedProjectBlockType;
  title: string;
  unitLabel?: string;
  isArchived: boolean;
  loggedTotal: number;
  targetValue?: number;
  progressPercent?: number;
  dailyTargetValue?: number;
  todayTotal: number;
  dailyTotalsByDate: Record<string, number>;
  completedCount: number;
  totalCount: number;
  plannedDurationMinutes: number;
  actualLoggedDurationMinutes: number;
  itemTotals: Record<string, number>;
  groupMetrics: ProjectGroupMetric[];
  rollupSourceBlockId?: string;
  paceNeededPerDay?: number;
  daysRemaining?: number;
}

export interface ProjectProgressSummary {
  projectId: string;
  blockMetrics: ProjectBlockProgressMetric[];
  primaryBlockId?: string;
  primaryMetric?: ProjectBlockProgressMetric;
  overallPercentage?: number;
  hasInvalidPrimaryBlockReference: boolean;
  linkedTasksCompleted: number;
  linkedTasksTotal: number;
  milestonesCompleted: number;
  milestonesTotal: number;
}

const VALID_PROJECT_STATUSES = new Set<string>(SHARED_BUSINESS_RULES.projects.statuses);
const VALID_CUSTOM_FIELD_TYPES = new Set<string>(
  SHARED_BUSINESS_RULES.projects.customFieldTypes
);
const ALLOWED_CUSTOM_FIELD_TOP_KEYS = new Set<string>([
  'definitions',
  'values',
  'primaryBlockId',
]);
const ALLOWED_DEFINITION_KEYS = new Set<string>([
  'id',
  'label',
  'type',
  'required',
  'options',
]);
const VALID_SCHEDULE_RULES = new Set<string>([
  'manual',
  'threshold_percent',
  'exact_duration',
]);
const FIELD_ID_PATTERN = /^[a-zA-Z0-9_-]{1,64}$/;

export function parseCounterBlockConfig(
  raw?: Record<string, unknown>
): CounterBlockConfig {
  const source =
    typeof raw?.rollupSourceBlockId === 'string' && raw.rollupSourceBlockId.trim()
      ? raw.rollupSourceBlockId.trim()
      : undefined;
  const allowDirect =
    typeof raw?.allowDirectLogging === 'boolean'
      ? raw.allowDirectLogging
      : source === undefined;
  return {
    ...(source !== undefined ? { rollupSourceBlockId: source } : {}),
    allowDirectLogging: allowDirect,
  };
}

export function parseGroupedListBlockConfig(
  raw?: Record<string, unknown>
): GroupedListBlockConfig {
  return {
    showGroupTotals:
      typeof raw?.showGroupTotals === 'boolean' ? raw.showGroupTotals : true,
    showDailyTotals:
      typeof raw?.showDailyTotals === 'boolean' ? raw.showDailyTotals : true,
    ...(typeof raw?.groupLabel === 'string' ? { groupLabel: raw.groupLabel } : {}),
    ...(typeof raw?.itemLabel === 'string' ? { itemLabel: raw.itemLabel } : {}),
  };
}

export function parseChecklistBlockConfig(
  raw?: Record<string, unknown>
): ChecklistBlockConfig {
  return {
    allowReorder:
      typeof raw?.allowReorder === 'boolean' ? raw.allowReorder : true,
  };
}

export function parseScheduleBlockConfig(
  raw?: Record<string, unknown>
): ScheduleBlockConfig {
  const rule =
    typeof raw?.completionRule === 'string' &&
    VALID_SCHEDULE_RULES.has(raw.completionRule)
      ? (raw.completionRule as ScheduleItemCompletionRule)
      : 'manual';
  const ratio =
    typeof raw?.autoCompleteThresholdRatio === 'number' &&
    Number.isFinite(raw.autoCompleteThresholdRatio)
      ? raw.autoCompleteThresholdRatio
      : 1.0;
  return {
    completionRule: rule,
    autoCompleteThresholdRatio: ratio,
    trackActualDuration:
      typeof raw?.trackActualDuration === 'boolean' ? raw.trackActualDuration : true,
  };
}

export function isRecordCorrection(record: SharedProjectTrackingRecord): boolean {
  return record.metadata?.isCorrection === true;
}

export function getCompensatesRecordId(
  record: SharedProjectTrackingRecord
): string | undefined {
  const raw = record.metadata?.compensatesRecordId;
  return typeof raw === 'string' && raw.trim() ? raw.trim() : undefined;
}

export function getCorrectionReason(
  record: SharedProjectTrackingRecord
): string | undefined {
  const raw = record.metadata?.correctionReason;
  return typeof raw === 'string' && raw.trim() ? raw.trim() : undefined;
}

export function validateProject(project: SharedProject): void {
  if (!project.id || !project.id.trim()) {
    throw new ProjectValidationError('Project id must not be empty.');
  }
  const title = (project.title ?? '').trim();
  if (!title || title.length > 200) {
    throw new ProjectValidationError(
      'Project title must be between 1 and 200 characters.'
    );
  }
  if (!VALID_PROJECT_STATUSES.has(project.status)) {
    throw new ProjectValidationError(
      `Invalid project status "${project.status}". Allowed: ${SHARED_BUSINESS_RULES.projects.statuses.join(', ')}.`
    );
  }
  if (project.startDate !== undefined && project.startDate !== null) {
    if (!CalendarDate.tryParse(project.startDate)) {
      throw new ProjectValidationError(
        `Project startDate "${project.startDate}" must be canonical YYYY-MM-DD.`
      );
    }
  }
  if (project.targetDate !== undefined && project.targetDate !== null) {
    if (!CalendarDate.tryParse(project.targetDate)) {
      throw new ProjectValidationError(
        `Project targetDate "${project.targetDate}" must be canonical YYYY-MM-DD.`
      );
    }
  }
  if (project.startDate && project.targetDate) {
    const start = CalendarDate.tryParse(project.startDate)!;
    const target = CalendarDate.tryParse(project.targetDate)!;
    if (target.isBefore(start)) {
      throw new ProjectValidationError(
        'Project targetDate cannot be earlier than startDate.'
      );
    }
  }
  if (project.customFields !== undefined && project.customFields !== null) {
    if (typeof project.customFields !== 'object' || Array.isArray(project.customFields)) {
      throw new ProjectValidationError('Project customFields must be an object.');
    }
    validateCustomFieldsMap(project.customFields as Record<string, unknown>);
  }
}

export function validateCustomFieldsMap(
  raw: Record<string, unknown> | SharedProjectCustomFieldsPayload
): void {
  const map = raw as Record<string, unknown>;
  const keys = Object.keys(map);
  if (keys.length === 0) return;

  for (const key of keys) {
    if (!ALLOWED_CUSTOM_FIELD_TOP_KEYS.has(key)) {
      throw new ProjectValidationError(
        `Unsupported customFields key "${key}". Allowed keys: definitions, values, primaryBlockId.`
      );
    }
  }

  if (
    Object.prototype.hasOwnProperty.call(map, 'primaryBlockId') &&
    map.primaryBlockId !== undefined &&
    map.primaryBlockId !== null
  ) {
    if (typeof map.primaryBlockId !== 'string' || !map.primaryBlockId.trim()) {
      throw new ProjectValidationError(
        'customFields.primaryBlockId must be a non-empty string.'
      );
    }
  }

  const defsById = new Map<string, Record<string, unknown>>();
  if (
    Object.prototype.hasOwnProperty.call(map, 'definitions') &&
    map.definitions !== undefined &&
    map.definitions !== null
  ) {
    if (!Array.isArray(map.definitions)) {
      throw new ProjectValidationError(
        'customFields.definitions must be an array.'
      );
    }
    if (
      map.definitions.length >
      SHARED_BUSINESS_RULES.projects.bounds.maxCustomFieldDefinitions
    ) {
      throw new ProjectValidationError(
        `customFields.definitions exceeds maximum allowed count (${SHARED_BUSINESS_RULES.projects.bounds.maxCustomFieldDefinitions}).`
      );
    }

    for (let i = 0; i < map.definitions.length; i++) {
      const item = map.definitions[i];
      if (!item || typeof item !== 'object' || Array.isArray(item)) {
        throw new ProjectValidationError(
          `customFields.definitions[${i}] must be an object.`
        );
      }
      const def = item as Record<string, unknown>;
      for (const k of Object.keys(def)) {
        if (!ALLOWED_DEFINITION_KEYS.has(k)) {
          throw new ProjectValidationError(
            `Unsupported custom field definition key "${k}" in definitions[${i}].`
          );
        }
      }
      const id = def.id;
      if (typeof id !== 'string' || !FIELD_ID_PATTERN.test(id)) {
        throw new ProjectValidationError(
          `Invalid custom field id "${String(id ?? '')}" at definitions[${i}].`
        );
      }
      if (defsById.has(id)) {
        throw new ProjectValidationError(
          `Duplicate custom field definition id "${id}".`
        );
      }
      const label = def.label;
      if (
        typeof label !== 'string' ||
        !label.trim() ||
        label.length > 120
      ) {
        throw new ProjectValidationError(
          `Invalid custom field label for "${id}".`
        );
      }
      const fieldType = def.type;
      if (
        typeof fieldType !== 'string' ||
        !VALID_CUSTOM_FIELD_TYPES.has(fieldType)
      ) {
        throw new ProjectValidationError(
          `Unsupported custom field type "${String(fieldType)}" for "${id}".`
        );
      }
      if (
        def.required !== undefined &&
        def.required !== null &&
        typeof def.required !== 'boolean'
      ) {
        throw new ProjectValidationError(
          `customFields.definitions[${i}].required must be a boolean.`
        );
      }

      const rawOptions = def.options;
      if ((fieldType as SharedProjectCustomFieldType) === 'select') {
        if (!Array.isArray(rawOptions) || rawOptions.length === 0) {
          throw new ProjectValidationError(
            `Select custom field "${id}" must define non-empty options.`
          );
        }
        if (
          rawOptions.length >
          SHARED_BUSINESS_RULES.projects.bounds.maxCustomFieldSelectOptions
        ) {
          throw new ProjectValidationError(
            `Select custom field "${id}" exceeds max options (${SHARED_BUSINESS_RULES.projects.bounds.maxCustomFieldSelectOptions}).`
          );
        }
        const seenOptions = new Set<string>();
        for (const opt of rawOptions) {
          if (typeof opt !== 'string' || !opt.trim()) {
            throw new ProjectValidationError(
              `Select custom field "${id}" contains invalid option "${String(opt)}".`
            );
          }
          if (seenOptions.has(opt)) {
            throw new ProjectValidationError(
              `Select custom field "${id}" contains duplicate option "${opt}".`
            );
          }
          seenOptions.add(opt);
        }
      } else if (
        rawOptions !== undefined &&
        rawOptions !== null &&
        (!Array.isArray(rawOptions) || rawOptions.length > 0)
      ) {
        throw new ProjectValidationError(
          `Non-select custom field "${id}" cannot define options.`
        );
      }
      defsById.set(id, def);
    }
  }

  let valuesMap: Record<string, unknown> = {};
  if (
    Object.prototype.hasOwnProperty.call(map, 'values') &&
    map.values !== undefined &&
    map.values !== null
  ) {
    if (typeof map.values !== 'object' || Array.isArray(map.values)) {
      throw new ProjectValidationError('customFields.values must be an object.');
    }
    valuesMap = map.values as Record<string, unknown>;
  }

  for (const [key, val] of Object.entries(valuesMap)) {
    const def = defsById.get(key);
    if (!def) {
      throw new ProjectValidationError(
        `Unknown custom field value key "${key}" without a matching definition.`
      );
    }
    if (val !== null && typeof val === 'object') {
      throw new ProjectValidationError(
        `Nested objects or arrays are not allowed in custom field value "${key}".`
      );
    }
    const isRequired = def.required === true;
    if (val === null || val === undefined) {
      if (isRequired) {
        throw new ProjectValidationError(
          `Required custom field "${key}" cannot be null.`
        );
      }
      continue;
    }

    const fieldType = def.type as SharedProjectCustomFieldType;
    switch (fieldType) {
      case 'text':
        if (typeof val !== 'string') {
          throw new ProjectValidationError(
            `Custom field "${key}" expects a text string.`
          );
        }
        if (
          val.length >
          SHARED_BUSINESS_RULES.projects.bounds.maxCustomFieldTextLength
        ) {
          throw new ProjectValidationError(
            `Custom field "${key}" exceeds max length (${SHARED_BUSINESS_RULES.projects.bounds.maxCustomFieldTextLength}).`
          );
        }
        if (isRequired && !val.trim()) {
          throw new ProjectValidationError(
            `Required custom field "${key}" cannot be blank.`
          );
        }
        break;
      case 'number':
        if (typeof val !== 'number' || !Number.isFinite(val)) {
          throw new ProjectValidationError(
            `Custom field "${key}" expects a finite number.`
          );
        }
        break;
      case 'date':
        if (typeof val !== 'string' || !CalendarDate.tryParse(val)) {
          throw new ProjectValidationError(
            `Custom field "${key}" expects canonical YYYY-MM-DD date.`
          );
        }
        break;
      case 'boolean':
        if (typeof val !== 'boolean') {
          throw new ProjectValidationError(
            `Custom field "${key}" expects a boolean.`
          );
        }
        break;
      case 'select': {
        const opts = (def.options as string[]) ?? [];
        if (typeof val !== 'string' || !opts.includes(val)) {
          throw new ProjectValidationError(
            `Custom field "${key}" value "${String(val)}" is not in allowed options.`
          );
        }
        break;
      }
    }
  }

  for (const [id, def] of defsById.entries()) {
    if (
      def.required === true &&
      !Object.prototype.hasOwnProperty.call(valuesMap, id)
    ) {
      throw new ProjectValidationError(
        `Missing value for required custom field "${id}".`
      );
    }
  }
}

export function validateBlock(
  block: SharedProjectTrackingBlock,
  options: {
    expectedProjectId: string;
    projectBlocks?: SharedProjectTrackingBlock[];
    isNew?: boolean;
  }
): void {
  const {
    expectedProjectId,
    projectBlocks = [],
    isNew = true,
  } = options;

  if (!block.id || !block.id.trim()) {
    throw new ProjectValidationError('Block id must not be empty.');
  }
  if (block.projectId !== expectedProjectId) {
    throw new ProjectValidationError(
      `Block "${block.id}" projectId "${block.projectId}" does not match project "${expectedProjectId}".`
    );
  }
  if (isNew && projectBlocks.some((b) => b.id === block.id)) {
    throw new ProjectValidationError(
      `Duplicate tracking block id "${block.id}".`
    );
  }
  if (
    isNew &&
    projectBlocks.length >=
      SHARED_BUSINESS_RULES.projects.bounds.maxBlocksPerProject
  ) {
    throw new ProjectValidationError(
      `Project exceeds maximum tracking blocks (${SHARED_BUSINESS_RULES.projects.bounds.maxBlocksPerProject}).`
    );
  }

  const title = (block.title ?? '').trim();
  if (!title || title.length > 200) {
    throw new ProjectValidationError(
      'Block title must be between 1 and 200 characters.'
    );
  }
  if (!Number.isInteger(block.sortOrder) || block.sortOrder < 0) {
    throw new ProjectValidationError('Block sortOrder must be non-negative.');
  }
  if (block.unitLabel !== undefined && block.unitLabel !== null) {
    if (block.unitLabel.trim().length > 64) {
      throw new ProjectValidationError(
        'Block unitLabel cannot exceed 64 characters.'
      );
    }
  }
  if (
    block.targetValue !== undefined &&
    block.targetValue !== null &&
    (!Number.isFinite(block.targetValue) || block.targetValue < 0)
  ) {
    throw new ProjectValidationError(
      'Block targetValue must be finite and non-negative.'
    );
  }
  if (
    block.dailyTargetValue !== undefined &&
    block.dailyTargetValue !== null &&
    (!Number.isFinite(block.dailyTargetValue) || block.dailyTargetValue < 0)
  ) {
    throw new ProjectValidationError(
      'Block dailyTargetValue must be finite and non-negative.'
    );
  }

  const config = block.config ?? {};
  switch (block.blockType) {
    case 'counter': {
      const cfg = parseCounterBlockConfig(config);
      if (cfg.rollupSourceBlockId !== undefined) {
        if (cfg.rollupSourceBlockId === block.id) {
          throw new ProjectValidationError(
            `Counter block "${block.id}" cannot roll up from itself.`
          );
        }
        if (cfg.allowDirectLogging) {
          throw new ProjectValidationError(
            `Rollup counter block "${block.id}" cannot allow direct logging alongside rollupSourceBlockId "${cfg.rollupSourceBlockId}".`
          );
        }
        const sourceBlock = projectBlocks.find(
          (b) => b.id === cfg.rollupSourceBlockId
        );
        if (!sourceBlock) {
          throw new ProjectValidationError(
            `Counter block "${block.id}" references missing rollupSourceBlockId "${cfg.rollupSourceBlockId}" in project "${expectedProjectId}".`
          );
        }
        if (sourceBlock.blockType === 'counter') {
          const nested = parseCounterBlockConfig(
            sourceBlock.config
          ).rollupSourceBlockId;
          if (nested !== undefined) {
            throw new ProjectValidationError(
              `Counter block "${block.id}" cannot chain rollups through another rollup counter "${cfg.rollupSourceBlockId}".`
            );
          }
        }
      }
      break;
    }
    case 'grouped_list':
      parseGroupedListBlockConfig(config);
      break;
    case 'checklist':
      parseChecklistBlockConfig(config);
      break;
    case 'schedule': {
      const rawRule = config.completionRule;
      if (
        rawRule !== undefined &&
        rawRule !== null &&
        (typeof rawRule !== 'string' || !VALID_SCHEDULE_RULES.has(rawRule))
      ) {
        throw new ProjectValidationError(
          `Unsupported schedule completionRule "${String(rawRule)}".`
        );
      }
      const cfg = parseScheduleBlockConfig(config);
      if (
        !Number.isFinite(cfg.autoCompleteThresholdRatio) ||
        cfg.autoCompleteThresholdRatio <= 0 ||
        cfg.autoCompleteThresholdRatio > 1.0
      ) {
        throw new ProjectValidationError(
          'Schedule autoCompleteThresholdRatio must be within (0.0, 1.0].'
        );
      }
      break;
    }
    default:
      throw new ProjectValidationError(
        `Unsupported project blockType "${String(block.blockType)}".`
      );
  }
}

export function validateRecord(
  record: SharedProjectTrackingRecord,
  options: {
    block: SharedProjectTrackingBlock;
    existingBlockRecords?: SharedProjectTrackingRecord[];
    isNew?: boolean;
  }
): void {
  const { block, existingBlockRecords = [], isNew = true } = options;

  if (!record.id || !record.id.trim()) {
    throw new ProjectValidationError('Record id must not be empty.');
  }
  if (record.projectId !== block.projectId) {
    throw new ProjectValidationError(
      `Record "${record.id}" projectId "${record.projectId}" does not match block project "${block.projectId}".`
    );
  }
  if (record.blockId !== block.id) {
    throw new ProjectValidationError(
      `Record "${record.id}" blockId "${record.blockId}" does not match block "${block.id}".`
    );
  }
  if (isNew && existingBlockRecords.some((r) => r.id === record.id)) {
    throw new ProjectValidationError(
      `Duplicate tracking record id "${record.id}".`
    );
  }
  if (!Number.isInteger(record.sortOrder) || record.sortOrder < 0) {
    throw new ProjectValidationError('Record sortOrder must be non-negative.');
  }
  if (
    record.targetValue !== undefined &&
    record.targetValue !== null &&
    (!Number.isFinite(record.targetValue) || record.targetValue < 0)
  ) {
    throw new ProjectValidationError(
      'Record targetValue must be finite and non-negative.'
    );
  }
  if (
    record.durationMinutes !== undefined &&
    record.durationMinutes !== null &&
    (!Number.isInteger(record.durationMinutes) || record.durationMinutes < 0)
  ) {
    throw new ProjectValidationError(
      'Record durationMinutes must be non-negative.'
    );
  }
  if (
    record.recordedDate !== undefined &&
    record.recordedDate !== null &&
    !CalendarDate.tryParse(record.recordedDate)
  ) {
    throw new ProjectValidationError(
      `Record "${record.id}" recordedDate "${record.recordedDate}" must be canonical YYYY-MM-DD.`
    );
  }
  if (
    record.scheduledDate !== undefined &&
    record.scheduledDate !== null &&
    !CalendarDate.tryParse(record.scheduledDate)
  ) {
    throw new ProjectValidationError(
      `Record "${record.id}" scheduledDate "${record.scheduledDate}" must be canonical YYYY-MM-DD.`
    );
  }

  const byId = new Map<string, SharedProjectTrackingRecord>();
  for (const item of existingBlockRecords) {
    byId.set(item.id, item);
  }

  let parent: SharedProjectTrackingRecord | undefined;
  if (record.parentRecordId !== undefined && record.parentRecordId !== null) {
    if (record.parentRecordId === record.id) {
      throw new ProjectValidationError(
        `Record "${record.id}" cannot set itself as parentRecordId.`
      );
    }
    parent = byId.get(record.parentRecordId);
    if (!parent) {
      throw new ProjectValidationError(
        `Record "${record.id}" references missing or cross-block parentRecordId "${record.parentRecordId}".`
      );
    }
    const visited = new Set<string>([record.id]);
    let cursor: SharedProjectTrackingRecord | undefined = parent;
    let depth = 1;
    while (cursor) {
      if (visited.has(cursor.id)) {
        throw new ProjectValidationError(
          `Cycle detected in parentRecordId hierarchy involving "${record.id}".`
        );
      }
      visited.add(cursor.id);
      depth += 1;
      if (depth > SHARED_BUSINESS_RULES.projects.bounds.maxHierarchyDepth) {
        throw new ProjectValidationError(
          `Record hierarchy exceeds maximum depth (${SHARED_BUSINESS_RULES.projects.bounds.maxHierarchyDepth}).`
        );
      }
      cursor = cursor.parentRecordId ? byId.get(cursor.parentRecordId) : undefined;
    }
  }

  switch (record.recordType as SharedProjectRecordType) {
    case 'group':
      if (block.blockType !== 'grouped_list') {
        throw new ProjectValidationError(
          'Record type "group" is only valid in grouped_list blocks.'
        );
      }
      if (record.parentRecordId !== undefined && record.parentRecordId !== null) {
        throw new ProjectValidationError(
          'Group records must be top-level (parentRecordId must be null).'
        );
      }
      if (!(record.title ?? '').trim()) {
        throw new ProjectValidationError(
          'Group record must have a non-empty title.'
        );
      }
      break;

    case 'grouped_item':
      if (block.blockType !== 'grouped_list') {
        throw new ProjectValidationError(
          'Record type "grouped_item" is only valid in grouped_list blocks.'
        );
      }
      if (!(record.title ?? '').trim()) {
        throw new ProjectValidationError(
          'Grouped item record must have a non-empty title.'
        );
      }
      if (parent && parent.recordType !== 'group') {
        throw new ProjectValidationError(
          `Grouped item "${record.id}" parentRecordId must reference a "group" record.`
        );
      }
      break;

    case 'checklist_item':
      if (block.blockType !== 'checklist') {
        throw new ProjectValidationError(
          'Record type "checklist_item" is only valid in checklist blocks.'
        );
      }
      if (record.parentRecordId !== undefined && record.parentRecordId !== null) {
        throw new ProjectValidationError(
          'Checklist items cannot have a parentRecordId.'
        );
      }
      if (!(record.title ?? '').trim()) {
        throw new ProjectValidationError(
          'Checklist item record must have a non-empty title.'
        );
      }
      break;

    case 'schedule_item':
      if (block.blockType !== 'schedule') {
        throw new ProjectValidationError(
          'Record type "schedule_item" is only valid in schedule blocks.'
        );
      }
      if (record.parentRecordId !== undefined && record.parentRecordId !== null) {
        throw new ProjectValidationError(
          'Schedule items cannot have a parentRecordId.'
        );
      }
      if (!(record.title ?? '').trim()) {
        throw new ProjectValidationError(
          'Schedule item record must have a non-empty title.'
        );
      }
      break;

    case 'progress_log': {
      if (block.blockType === 'checklist') {
        throw new ProjectValidationError(
          'Progress logs cannot be attached to checklist blocks.'
        );
      }
      if (!record.recordedDate || !CalendarDate.tryParse(record.recordedDate)) {
        throw new ProjectValidationError(
          `Progress log "${record.id}" requires recordedDate (YYYY-MM-DD).`
        );
      }
      if (block.blockType === 'counter') {
        const cfg = parseCounterBlockConfig(block.config);
        if (cfg.rollupSourceBlockId !== undefined || !cfg.allowDirectLogging) {
          throw new ProjectValidationError(
            `Cannot log directly on rollup counter block "${block.id}" (source: "${cfg.rollupSourceBlockId}"). Log against the source block items instead.`
          );
        }
        if (record.parentRecordId !== undefined && record.parentRecordId !== null) {
          throw new ProjectValidationError(
            'Direct counter progress logs must have parentRecordId == null.'
          );
        }
      } else if (block.blockType === 'grouped_list') {
        if (!parent || parent.recordType !== 'grouped_item') {
          throw new ProjectValidationError(
            `Progress log "${record.id}" in a grouped_list block must reference a parent grouped_item record.`
          );
        }
      } else if (block.blockType === 'schedule') {
        if (!parent || parent.recordType !== 'schedule_item') {
          throw new ProjectValidationError(
            `Progress log "${record.id}" in a schedule block must reference a parent schedule_item record.`
          );
        }
      }

      const delta = record.deltaValue;
      if (typeof delta !== 'number' || !Number.isFinite(delta) || delta === 0) {
        throw new ProjectValidationError(
          `Progress log "${record.id}" must have a finite non-zero deltaValue.`
        );
      }
      if (isRecordCorrection(record)) {
        const targetId = getCompensatesRecordId(record) ?? '';
        const reason = getCorrectionReason(record) ?? '';
        if (!targetId) {
          throw new ProjectValidationError(
            'Compensating progress correction requires metadata.compensatesRecordId.'
          );
        }
        if (!reason) {
          throw new ProjectValidationError(
            'Compensating progress correction requires metadata.correctionReason.'
          );
        }
        if (targetId === record.id) {
          throw new ProjectValidationError(
            'Compensating progress correction cannot reference itself.'
          );
        }
        const target = byId.get(targetId);
        if (!target || target.recordType !== 'progress_log') {
          throw new ProjectValidationError(
            `Compensating correction "${record.id}" references missing or non-log record "${targetId}".`
          );
        }
        if ((target.parentRecordId ?? null) !== (record.parentRecordId ?? null)) {
          throw new ProjectValidationError(
            `Compensating correction "${record.id}" must match parentRecordId of target log "${targetId}".`
          );
        }
      } else if (delta <= 0) {
        throw new ProjectValidationError(
          `Progress log "${record.id}" deltaValue must be > 0 (use explicit compensating correction for negative adjustments).`
        );
      }
      break;
    }

    default:
      throw new ProjectValidationError(
        `Unsupported project recordType "${String(record.recordType)}".`
      );
  }
}

export function assertAppendOnlyLogProtection(
  existing: SharedProjectTrackingRecord,
  isDelete = false
): void {
  if (existing.recordType === 'progress_log') {
    if (isDelete) {
      throw new ProjectValidationError(
        `Progress log "${existing.id}" is append-only and cannot be silently deleted; append a compensating correction instead.`
      );
    }
    throw new ProjectValidationError(
      `Progress log "${existing.id}" is append-only and cannot be mutated; append a compensating correction instead.`
    );
  }
}

export function calculateProgressPercentage(params: {
  totalTasks: number;
  completedTasks: number;
  totalMilestones: number;
  completedMilestones: number;
  isProjectManuallyCompleted?: boolean;
}): number {
  if (params.isProjectManuallyCompleted) return 100;
  const totalItems = params.totalTasks + params.totalMilestones;
  if (totalItems === 0) return 0;
  const completedItems = params.completedTasks + params.completedMilestones;
  const pct = Math.trunc((completedItems * 100) / totalItems);
  return Math.max(0, Math.min(100, pct));
}

export function meetsScheduleDurationRule(params: {
  plannedDurationMinutes?: number;
  actualLoggedMinutes: number;
  config: ScheduleBlockConfig;
}): boolean {
  const { plannedDurationMinutes, actualLoggedMinutes, config } = params;
  if (config.completionRule === 'manual') return false;
  if (plannedDurationMinutes === undefined || plannedDurationMinutes <= 0) {
    return false;
  }
  const requiredRatio =
    config.completionRule === 'exact_duration'
      ? 1.0
      : Math.max(0.01, Math.min(1.0, config.autoCompleteThresholdRatio));
  return actualLoggedMinutes >= plannedDurationMinutes * requiredRatio;
}

function clampPercent(value: number): number {
  return Math.max(0, Math.min(100, value));
}

function computeSingleBlockMetric(params: {
  block: SharedProjectTrackingBlock;
  records: SharedProjectTrackingRecord[];
  todayIso: string;
  daysRemaining?: number;
}): ProjectBlockProgressMetric {
  const { block, records, todayIso, daysRemaining } = params;
  const dailyTotalsByDate: Record<string, number> = {};
  const itemTotals: Record<string, number> = {};
  let loggedTotal = 0;

  for (const rec of records) {
    if (rec.recordType !== 'progress_log') continue;
    const delta = rec.deltaValue ?? 0;
    loggedTotal += delta;
    if (rec.recordedDate) {
      dailyTotalsByDate[rec.recordedDate] =
        (dailyTotalsByDate[rec.recordedDate] ?? 0) + delta;
    }
    if (rec.parentRecordId) {
      itemTotals[rec.parentRecordId] =
        (itemTotals[rec.parentRecordId] ?? 0) + delta;
    }
  }

  const todayTotal = dailyTotalsByDate[todayIso] ?? 0;

  switch (block.blockType) {
    case 'counter': {
      const progressPercent =
        block.targetValue !== undefined && block.targetValue > 0
          ? clampPercent((loggedTotal / block.targetValue) * 100)
          : undefined;
      const paceNeededPerDay =
        block.targetValue !== undefined &&
        block.targetValue > 0 &&
        daysRemaining !== undefined
          ? Math.max(0, block.targetValue - loggedTotal) /
            (daysRemaining > 0 ? daysRemaining : 1)
          : undefined;
      return {
        blockId: block.id,
        blockType: block.blockType,
        title: block.title,
        unitLabel: block.unitLabel,
        isArchived: block.isArchived,
        loggedTotal,
        targetValue: block.targetValue,
        progressPercent,
        dailyTargetValue: block.dailyTargetValue,
        todayTotal,
        dailyTotalsByDate,
        completedCount: 0,
        totalCount: 0,
        plannedDurationMinutes: 0,
        actualLoggedDurationMinutes: 0,
        itemTotals,
        groupMetrics: [],
        paceNeededPerDay,
        daysRemaining,
      };
    }

    case 'grouped_list': {
      const groups = records.filter((r) => r.recordType === 'group');
      const items = records.filter((r) => r.recordType === 'grouped_item');
      const itemsByGroup = new Map<string, SharedProjectTrackingRecord[]>();
      let summedItemTargets = 0;
      let hasAnyItemTarget = false;
      let completedItems = 0;

      for (const item of items) {
        if (item.parentRecordId) {
          const arr = itemsByGroup.get(item.parentRecordId) ?? [];
          arr.push(item);
          itemsByGroup.set(item.parentRecordId, arr);
        }
        const itemTotal = itemTotals[item.id] ?? 0;
        const itemTarget = item.targetValue;
        if (itemTarget !== undefined && itemTarget > 0) {
          hasAnyItemTarget = true;
          summedItemTargets += itemTarget;
        }
        if (
          item.isCompleted ||
          (itemTarget !== undefined && itemTarget > 0 && itemTotal >= itemTarget)
        ) {
          completedItems += 1;
        }
      }

      const groupMetrics: ProjectGroupMetric[] = groups.map((group) => {
        const children = itemsByGroup.get(group.id) ?? [];
        let groupTotal = 0;
        let childTargetsSum = 0;
        let childCompleted = 0;
        for (const child of children) {
          const childTotal = itemTotals[child.id] ?? 0;
          groupTotal += childTotal;
          if (child.targetValue !== undefined && child.targetValue > 0) {
            childTargetsSum += child.targetValue;
          }
          if (
            child.isCompleted ||
            (child.targetValue !== undefined &&
              child.targetValue > 0 &&
              childTotal >= child.targetValue)
          ) {
            childCompleted += 1;
          }
        }
        const groupTarget =
          group.targetValue ?? (childTargetsSum > 0 ? childTargetsSum : undefined);
        const groupPercent =
          groupTarget !== undefined && groupTarget > 0
            ? clampPercent((groupTotal / groupTarget) * 100)
            : undefined;
        return {
          groupId: group.id,
          title: group.title ?? '',
          targetValue: groupTarget,
          loggedTotal: groupTotal,
          itemCount: children.length,
          completedItemCount: childCompleted,
          progressPercent: groupPercent,
        };
      });

      const effectiveTarget =
        block.targetValue ?? (hasAnyItemTarget ? summedItemTargets : undefined);
      const progressPercent =
        effectiveTarget !== undefined && effectiveTarget > 0
          ? clampPercent((loggedTotal / effectiveTarget) * 100)
          : undefined;
      const paceNeededPerDay =
        effectiveTarget !== undefined &&
        effectiveTarget > 0 &&
        daysRemaining !== undefined
          ? Math.max(0, effectiveTarget - loggedTotal) /
            (daysRemaining > 0 ? daysRemaining : 1)
          : undefined;

      return {
        blockId: block.id,
        blockType: block.blockType,
        title: block.title,
        unitLabel: block.unitLabel,
        isArchived: block.isArchived,
        loggedTotal,
        targetValue: effectiveTarget,
        progressPercent,
        dailyTargetValue: block.dailyTargetValue,
        todayTotal,
        dailyTotalsByDate,
        completedCount: completedItems,
        totalCount: items.length,
        plannedDurationMinutes: 0,
        actualLoggedDurationMinutes: 0,
        itemTotals,
        groupMetrics,
        paceNeededPerDay,
        daysRemaining,
      };
    }

    case 'checklist': {
      const items = records.filter((r) => r.recordType === 'checklist_item');
      const completed = items.filter((i) => i.isCompleted).length;
      const total = items.length;
      const progressPercent =
        total > 0 ? clampPercent((completed / total) * 100) : 0;
      return {
        blockId: block.id,
        blockType: block.blockType,
        title: block.title,
        unitLabel: block.unitLabel,
        isArchived: block.isArchived,
        loggedTotal: completed,
        targetValue: block.targetValue ?? total,
        progressPercent,
        dailyTargetValue: block.dailyTargetValue,
        todayTotal: 0,
        dailyTotalsByDate: {},
        completedCount: completed,
        totalCount: total,
        plannedDurationMinutes: 0,
        actualLoggedDurationMinutes: 0,
        itemTotals: {},
        groupMetrics: [],
      };
    }

    case 'schedule': {
      const items = records.filter((r) => r.recordType === 'schedule_item');
      const cfg = parseScheduleBlockConfig(block.config);
      const completed = items.filter((i) => i.isCompleted).length;
      const total = items.length;
      let plannedDurationMinutes = 0;
      for (const item of items) {
        plannedDurationMinutes += item.durationMinutes ?? 0;
      }
      const actualLoggedDurationMinutes = Math.round(loggedTotal);
      let progressPercent: number;
      if (block.targetValue !== undefined && block.targetValue > 0) {
        progressPercent = clampPercent((loggedTotal / block.targetValue) * 100);
      } else if (cfg.completionRule !== 'manual' && plannedDurationMinutes > 0) {
        progressPercent = clampPercent((loggedTotal / plannedDurationMinutes) * 100);
      } else if (total > 0) {
        progressPercent = clampPercent((completed / total) * 100);
      } else {
        progressPercent = 0;
      }

      return {
        blockId: block.id,
        blockType: block.blockType,
        title: block.title,
        unitLabel: block.unitLabel,
        isArchived: block.isArchived,
        loggedTotal,
        targetValue:
          block.targetValue ??
          (plannedDurationMinutes > 0 ? plannedDurationMinutes : undefined),
        progressPercent,
        dailyTargetValue: block.dailyTargetValue,
        todayTotal,
        dailyTotalsByDate,
        completedCount: completed,
        totalCount: total,
        plannedDurationMinutes,
        actualLoggedDurationMinutes,
        itemTotals,
        groupMetrics: [],
        daysRemaining,
      };
    }
  }
}

export function calculateProjectProgressSummary(params: {
  project: SharedProject;
  blocks: SharedProjectTrackingBlock[];
  records: SharedProjectTrackingRecord[];
  linkedTasks?: SharedTask[];
  milestones?: ProjectMilestoneInput[];
  asOfDate?: CalendarDate;
}): ProjectProgressSummary {
  const {
    project,
    blocks,
    records,
    linkedTasks = [],
    milestones = [],
    asOfDate,
  } = params;

  const referenceDate = asOfDate ?? CalendarDate.today();
  const todayIso = referenceDate.toIsoString();

  const projectTasks = linkedTasks.filter(
    (t) => t.projectId === project.id && t.status !== 'cancelled'
  );
  const linkedTasksTotal = projectTasks.length;
  const linkedTasksCompleted = projectTasks.filter(
    (t) => t.status === 'completed'
  ).length;

  const projectMilestones = milestones.filter((m) => m.projectId === project.id);
  const milestonesTotal = projectMilestones.length;
  const milestonesCompleted = projectMilestones.filter((m) => m.isCompleted).length;

  const projectBlocks = blocks
    .filter((b) => b.projectId === project.id)
    .sort((a, b) => {
      if (a.sortOrder !== b.sortOrder) return a.sortOrder - b.sortOrder;
      return a.createdAt.localeCompare(b.createdAt);
    });

  const recordsByBlock = new Map<string, SharedProjectTrackingRecord[]>();
  for (const rec of records) {
    if (rec.projectId !== project.id) continue;
    const list = recordsByBlock.get(rec.blockId) ?? [];
    list.push(rec);
    recordsByBlock.set(rec.blockId, list);
  }

  let daysRemaining: number | undefined;
  if (project.targetDate) {
    const parsedTarget = CalendarDate.tryParse(project.targetDate);
    if (parsedTarget) {
      const diff = parsedTarget.differenceInDays(referenceDate);
      daysRemaining = diff >= 0 ? diff + 1 : 0;
    }
  }

  const rawMetricsById = new Map<string, ProjectBlockProgressMetric>();

  // Pass 1: non-rollup blocks (grouped_list, checklist, schedule, direct counters)
  for (const block of projectBlocks) {
    if (
      block.blockType === 'counter' &&
      parseCounterBlockConfig(block.config).rollupSourceBlockId !== undefined
    ) {
      continue;
    }
    const blockRecords = [...(recordsByBlock.get(block.id) ?? [])].sort((a, b) => {
      if (a.sortOrder !== b.sortOrder) return a.sortOrder - b.sortOrder;
      return a.createdAt.localeCompare(b.createdAt);
    });
    rawMetricsById.set(
      block.id,
      computeSingleBlockMetric({
        block,
        records: blockRecords,
        todayIso,
        daysRemaining,
      })
    );
  }

  // Pass 2: rollup counters from single source block
  for (const block of projectBlocks) {
    if (rawMetricsById.has(block.id)) continue;
    const cfg = parseCounterBlockConfig(block.config);
    const sourceMetric = cfg.rollupSourceBlockId
      ? rawMetricsById.get(cfg.rollupSourceBlockId)
      : undefined;
    const logged = sourceMetric?.loggedTotal ?? 0;
    const effectiveTarget = block.targetValue ?? sourceMetric?.targetValue;
    const progressPercent =
      effectiveTarget !== undefined && effectiveTarget > 0
        ? clampPercent((logged / effectiveTarget) * 100)
        : undefined;
    const paceNeededPerDay =
      effectiveTarget !== undefined &&
      effectiveTarget > 0 &&
      daysRemaining !== undefined
        ? Math.max(0, effectiveTarget - logged) /
          (daysRemaining > 0 ? daysRemaining : 1)
        : undefined;

    rawMetricsById.set(block.id, {
      blockId: block.id,
      blockType: block.blockType,
      title: block.title,
      unitLabel: block.unitLabel ?? sourceMetric?.unitLabel,
      isArchived: block.isArchived,
      loggedTotal: logged,
      targetValue: effectiveTarget,
      progressPercent,
      dailyTargetValue: block.dailyTargetValue ?? sourceMetric?.dailyTargetValue,
      todayTotal: sourceMetric?.todayTotal ?? 0,
      dailyTotalsByDate: { ...(sourceMetric?.dailyTotalsByDate ?? {}) },
      completedCount: sourceMetric?.completedCount ?? 0,
      totalCount: sourceMetric?.totalCount ?? 0,
      plannedDurationMinutes: sourceMetric?.plannedDurationMinutes ?? 0,
      actualLoggedDurationMinutes: sourceMetric?.actualLoggedDurationMinutes ?? 0,
      itemTotals: { ...(sourceMetric?.itemTotals ?? {}) },
      groupMetrics: [...(sourceMetric?.groupMetrics ?? [])],
      rollupSourceBlockId: cfg.rollupSourceBlockId,
      paceNeededPerDay,
      daysRemaining,
    });
  }

  const orderedMetrics: ProjectBlockProgressMetric[] = [];
  for (const block of projectBlocks) {
    const metric = rawMetricsById.get(block.id);
    if (metric) orderedMetrics.push(metric);
  }

  const rawPrimary =
    typeof project.customFields?.primaryBlockId === 'string'
      ? project.customFields.primaryBlockId.trim()
      : '';
  let primaryBlockId: string | undefined;
  let primaryMetric: ProjectBlockProgressMetric | undefined;
  let hasInvalidPrimaryBlockReference = false;

  if (rawPrimary) {
    const candidate = rawMetricsById.get(rawPrimary);
    if (!candidate || candidate.isArchived) {
      hasInvalidPrimaryBlockReference = true;
    } else {
      primaryBlockId = rawPrimary;
      primaryMetric = candidate;
    }
  }

  return {
    projectId: project.id,
    blockMetrics: orderedMetrics,
    primaryBlockId,
    primaryMetric,
    overallPercentage: primaryMetric?.progressPercent,
    hasInvalidPrimaryBlockReference,
    linkedTasksCompleted,
    linkedTasksTotal,
    milestonesCompleted,
    milestonesTotal,
  };
}
