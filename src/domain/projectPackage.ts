import { CalendarDate, EthiopiaClock } from './date';
import {
  ProjectValidationError,
  isRecordCorrection,
  getCompensatesRecordId,
  parseCounterBlockConfig,
  validateBlock,
  validateProject,
  validateRecord,
} from './projectsEngine';
import {
  SHARED_BUSINESS_RULES,
  SHARED_PROJECT_PACKAGE_SPEC,
  SharedProject,
  SharedProjectBlockType,
  SharedProjectCustomFieldsPayload,
  SharedProjectRecordType,
  SharedProjectTrackingBlock,
  SharedProjectTrackingRecord,
} from './sharedFoundation';

export type ProjectPackageErrorKind =
  | 'malformed_json'
  | 'invalid_format'
  | 'unsupported_version'
  | 'validation_failed';

export class ProjectPackageError extends Error {
  public readonly kind: ProjectPackageErrorKind;

  constructor(kind: ProjectPackageErrorKind, message: string) {
    super(message);
    this.name = 'ProjectPackageError';
    this.kind = kind;
  }
}

export interface DaywellProjectPackageProject {
  id: string;
  title: string;
  description?: string;
  status: SharedProject['status'];
  targetDate?: string;
  startDate?: string;
  isArchived: boolean;
  customFields: SharedProjectCustomFieldsPayload | Record<string, unknown>;
  createdAt: string;
  updatedAt: string;
}

export interface DaywellProjectPackageV1 {
  formatId: typeof SHARED_PROJECT_PACKAGE_SPEC.formatId;
  formatVersion: number;
  exportedAt: string;
  sourcePlatform: string;
  project: DaywellProjectPackageProject;
  trackingBlocks: SharedProjectTrackingBlock[];
  trackingRecords: SharedProjectTrackingRecord[];
}

export interface PreparedProjectPackageImport {
  sourceFormatVersion: number;
  sourcePlatform: string;
  exportedAt: string;
  project: SharedProject;
  trackingBlocks: SharedProjectTrackingBlock[];
  trackingRecords: SharedProjectTrackingRecord[];
}

export interface PrepareProjectPackageImportOptions {
  existingProjectIds?: Iterable<string>;
  existingBlockIds?: Iterable<string>;
  existingRecordIds?: Iterable<string>;
  generateId?: (prefix: 'proj' | 'blk' | 'rec') => string;
}

const VALID_PROJECT_STATUSES = new Set<string>(SHARED_BUSINESS_RULES.projects.statuses);
const VALID_BLOCK_TYPES = new Set<string>(SHARED_BUSINESS_RULES.projects.blockTypes);
const VALID_RECORD_TYPES = new Set<string>(SHARED_BUSINESS_RULES.projects.recordTypes);

let localIdSeq = 0;

function defaultGenerateId(prefix: 'proj' | 'blk' | 'rec'): string {
  localIdSeq = (localIdSeq + 1) % 1000000;
  const now = EthiopiaClock.nowUtc().getTime();
  const rand = Math.floor(Math.random() * 100000);
  return `${prefix}-${now}-${localIdSeq}-${rand}`;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function cloneJsonObject(value: unknown): Record<string, unknown> {
  if (!isPlainObject(value)) return {};
  return JSON.parse(JSON.stringify(value)) as Record<string, unknown>;
}

function assertValidIsoTimestamp(raw: unknown, fieldLabel: string): string {
  if (typeof raw !== 'string' || !raw.trim()) {
    throw new ProjectPackageError(
      'validation_failed',
      `Package field "${fieldLabel}" must be a valid ISO-8601 timestamp string.`
    );
  }
  const trimmed = raw.trim();
  const ms = Date.parse(trimmed);
  if (!Number.isFinite(ms)) {
    throw new ProjectPackageError(
      'validation_failed',
      `Package field "${fieldLabel}" is not a valid ISO-8601 timestamp ("${trimmed}").`
    );
  }
  return new Date(ms).toISOString();
}

function parseOptionalIsoTimestamp(
  raw: unknown,
  fieldLabel: string
): string | undefined {
  if (raw === undefined || raw === null) return undefined;
  return assertValidIsoTimestamp(raw, fieldLabel);
}

function parseOptionalString(raw: unknown, fieldLabel: string): string | undefined {
  if (raw === undefined || raw === null) return undefined;
  if (typeof raw !== 'string') {
    throw new ProjectPackageError(
      'validation_failed',
      `Package field "${fieldLabel}" must be a string when present.`
    );
  }
  const trimmed = raw.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function parseOptionalCanonicalDate(
  raw: unknown,
  fieldLabel: string
): string | undefined {
  if (raw === undefined || raw === null) return undefined;
  if (typeof raw !== 'string') {
    throw new ProjectPackageError(
      'validation_failed',
      `Package field "${fieldLabel}" must be a YYYY-MM-DD string.`
    );
  }
  const trimmed = raw.trim();
  if (!trimmed) return undefined;
  const parsed = CalendarDate.tryParse(trimmed);
  if (!parsed) {
    throw new ProjectPackageError(
      'validation_failed',
      `Package field "${fieldLabel}" ("${trimmed}") must be canonical YYYY-MM-DD.`
    );
  }
  return parsed.toIsoString();
}

function parseNonNegativeInt(
  raw: unknown,
  fieldLabel: string,
  defaultValue: number
): number {
  if (raw === undefined || raw === null) return defaultValue;
  if (typeof raw !== 'number' || !Number.isInteger(raw) || raw < 0) {
    throw new ProjectPackageError(
      'validation_failed',
      `Package field "${fieldLabel}" must be a non-negative integer.`
    );
  }
  return raw;
}

function parseOptionalNonNegativeInt(
  raw: unknown,
  fieldLabel: string
): number | undefined {
  if (raw === undefined || raw === null) return undefined;
  if (typeof raw !== 'number' || !Number.isInteger(raw) || raw < 0) {
    throw new ProjectPackageError(
      'validation_failed',
      `Package field "${fieldLabel}" must be a non-negative integer.`
    );
  }
  return raw;
}

function parseOptionalFiniteNumber(
  raw: unknown,
  fieldLabel: string
): number | undefined {
  if (raw === undefined || raw === null) return undefined;
  if (typeof raw !== 'number' || !Number.isFinite(raw)) {
    throw new ProjectPackageError(
      'validation_failed',
      `Package field "${fieldLabel}" must be a finite number.`
    );
  }
  return raw;
}

function parseBooleanWithDefault(
  raw: unknown,
  fieldLabel: string,
  defaultValue: boolean
): boolean {
  if (raw === undefined || raw === null) return defaultValue;
  if (typeof raw !== 'boolean') {
    throw new ProjectPackageError(
      'validation_failed',
      `Package field "${fieldLabel}" must be a boolean.`
    );
  }
  return raw;
}

/**
 * Builds a clean `.daywellproject` filename from a project title.
 */
export function buildProjectPackageFilename(projectTitle: string): string {
  const slug = projectTitle
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 48);
  const base = slug || 'daywell-project';
  return `${base}${SHARED_PROJECT_PACKAGE_SPEC.fileExtension}`;
}

/**
 * Orders blocks so non-rollup base blocks always precede rollup counters.
 */
export function sortBlocksTopologically(
  blocks: SharedProjectTrackingBlock[]
): SharedProjectTrackingBlock[] {
  const base: SharedProjectTrackingBlock[] = [];
  const rollups: SharedProjectTrackingBlock[] = [];
  for (const blk of blocks) {
    if (
      blk.blockType === 'counter' &&
      parseCounterBlockConfig(blk.config).rollupSourceBlockId !== undefined
    ) {
      rollups.push(blk);
    } else {
      base.push(blk);
    }
  }
  const cmp = (a: SharedProjectTrackingBlock, b: SharedProjectTrackingBlock) => {
    if (a.sortOrder !== b.sortOrder) return a.sortOrder - b.sortOrder;
    const createdCmp = a.createdAt.localeCompare(b.createdAt);
    if (createdCmp !== 0) return createdCmp;
    return a.id.localeCompare(b.id);
  };
  base.sort(cmp);
  rollups.sort(cmp);
  return [...base, ...rollups];
}

function recordPhaseRank(rec: SharedProjectTrackingRecord): number {
  switch (rec.recordType) {
    case 'group':
      return 0;
    case 'grouped_item':
    case 'checklist_item':
    case 'schedule_item':
      return 1;
    case 'progress_log':
      return isRecordCorrection(rec) ? 3 : 2;
  }
}

/**
 * Orders tracking records topologically so parents precede children and
 * target progress logs precede compensating corrections.
 */
export function sortRecordsTopologically(
  records: SharedProjectTrackingRecord[]
): SharedProjectTrackingRecord[] {
  const baseCmp = (
    a: SharedProjectTrackingRecord,
    b: SharedProjectTrackingRecord
  ): number => {
    const rankCmp = recordPhaseRank(a) - recordPhaseRank(b);
    if (rankCmp !== 0) return rankCmp;
    if (a.sortOrder !== b.sortOrder) return a.sortOrder - b.sortOrder;
    const createdCmp = a.createdAt.localeCompare(b.createdAt);
    if (createdCmp !== 0) return createdCmp;
    return a.id.localeCompare(b.id);
  };

  const nonCorrections = records
    .filter((r) => !(r.recordType === 'progress_log' && isRecordCorrection(r)))
    .sort(baseCmp);
  const corrections = records
    .filter((r) => r.recordType === 'progress_log' && isRecordCorrection(r))
    .sort(baseCmp);

  const byId = new Map(records.map((r) => [r.id, r]));
  const depthCache = new Map<string, number>();

  const computeCorrectionDepth = (
    rec: SharedProjectTrackingRecord,
    visiting: Set<string>
  ): number => {
    const cached = depthCache.get(rec.id);
    if (cached !== undefined) return cached;
    if (visiting.has(rec.id)) {
      throw new ProjectPackageError(
        'validation_failed',
        `Cycle detected in compensating progress correction chain involving "${rec.id}".`
      );
    }
    const targetId = getCompensatesRecordId(rec);
    if (!targetId) return 0;
    const target = byId.get(targetId);
    if (!target) return 0;
    visiting.add(rec.id);
    const d =
      target.recordType === 'progress_log' && isRecordCorrection(target)
        ? 1 + computeCorrectionDepth(target, visiting)
        : 1;
    visiting.delete(rec.id);
    depthCache.set(rec.id, d);
    return d;
  };

  corrections.sort((a, b) => {
    const depthA = computeCorrectionDepth(a, new Set());
    const depthB = computeCorrectionDepth(b, new Set());
    if (depthA !== depthB) return depthA - depthB;
    return baseCmp(a, b);
  });

  return [...nonCorrections, ...corrections];
}

/**
 * Serializes a single Daywell project, all its tracking blocks (active & archived),
 * and all its tracking records into a portable `.daywellproject` v1 JSON package.
 * Cross-module `goalId` and `linkedTaskId` references are stripped so packages are self-contained.
 */
export function buildProjectPackageObject(params: {
  project: SharedProject;
  blocks: SharedProjectTrackingBlock[];
  records: SharedProjectTrackingRecord[];
  exportedAt?: string;
  sourcePlatform?: 'web' | 'android';
}): DaywellProjectPackageV1 {
  const {
    project,
    blocks,
    records,
    exportedAt = EthiopiaClock.nowUtc().toISOString(),
    sourcePlatform = 'web',
  } = params;

  try {
    validateProject(project);
  } catch (err) {
    throw new ProjectPackageError(
      'validation_failed',
      err instanceof Error ? err.message : 'Invalid project for export.'
    );
  }

  for (const blk of blocks) {
    if (blk.projectId !== project.id) {
      throw new ProjectPackageError(
        'validation_failed',
        `Cannot export block "${blk.id}": projectId "${blk.projectId}" does not match "${project.id}".`
      );
    }
  }
  for (const rec of records) {
    if (rec.projectId !== project.id) {
      throw new ProjectPackageError(
        'validation_failed',
        `Cannot export record "${rec.id}": projectId "${rec.projectId}" does not match "${project.id}".`
      );
    }
  }

  const orderedBlocks = sortBlocksTopologically(blocks).map((b) => ({
    id: b.id,
    projectId: b.projectId,
    blockType: b.blockType,
    title: b.title.trim(),
    sortOrder: b.sortOrder,
    ...(b.unitLabel?.trim() ? { unitLabel: b.unitLabel.trim() } : {}),
    ...(b.targetValue !== undefined ? { targetValue: b.targetValue } : {}),
    ...(b.dailyTargetValue !== undefined
      ? { dailyTargetValue: b.dailyTargetValue }
      : {}),
    config: cloneJsonObject(b.config),
    isArchived: b.isArchived === true,
    createdAt: b.createdAt,
    updatedAt: b.updatedAt,
  }));

  const orderedRecords = sortRecordsTopologically(records).map((r) => ({
    id: r.id,
    projectId: r.projectId,
    blockId: r.blockId,
    ...(r.parentRecordId ? { parentRecordId: r.parentRecordId } : {}),
    recordType: r.recordType,
    ...(r.title !== undefined && r.title !== null && r.title.trim()
      ? { title: r.title.trim() }
      : {}),
    sortOrder: r.sortOrder,
    ...(r.targetValue !== undefined ? { targetValue: r.targetValue } : {}),
    ...(r.deltaValue !== undefined ? { deltaValue: r.deltaValue } : {}),
    ...(r.durationMinutes !== undefined
      ? { durationMinutes: r.durationMinutes }
      : {}),
    isCompleted: r.isCompleted === true,
    ...(r.completedAt ? { completedAt: r.completedAt } : {}),
    ...(r.recordedDate ? { recordedDate: r.recordedDate } : {}),
    ...(r.scheduledDate ? { scheduledDate: r.scheduledDate } : {}),
    // linkedTaskId intentionally omitted for self-contained portability
    metadata: cloneJsonObject(r.metadata),
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  }));

  const nowIso = EthiopiaClock.nowUtc().toISOString();
  const cleanProject: DaywellProjectPackageProject = {
    id: project.id,
    title: project.title.trim(),
    ...(project.description?.trim()
      ? { description: project.description.trim() }
      : {}),
    status: project.status,
    ...(project.targetDate ? { targetDate: project.targetDate } : {}),
    ...(project.startDate ? { startDate: project.startDate } : {}),
    // goalId intentionally omitted for self-contained portability
    isArchived: project.isArchived === true,
    customFields: cloneJsonObject(project.customFields),
    createdAt: project.createdAt ?? nowIso,
    updatedAt: project.updatedAt ?? project.createdAt ?? nowIso,
  };

  return {
    formatId: SHARED_PROJECT_PACKAGE_SPEC.formatId,
    formatVersion: SHARED_PROJECT_PACKAGE_SPEC.currentFormatVersion,
    exportedAt: assertValidIsoTimestamp(exportedAt, 'exportedAt'),
    sourcePlatform,
    project: cleanProject,
    trackingBlocks: orderedBlocks,
    trackingRecords: orderedRecords,
  };
}

export function serializeProjectPackage(params: {
  project: SharedProject;
  blocks: SharedProjectTrackingBlock[];
  records: SharedProjectTrackingRecord[];
  exportedAt?: string;
  sourcePlatform?: 'web' | 'android';
}): string {
  return JSON.stringify(buildProjectPackageObject(params), null, 2);
}

/**
 * Parses and validates a `.daywellproject` JSON payload fail-closed without mutating storage.
 */
export function parseAndValidateProjectPackage(
  rawJson: string
): DaywellProjectPackageV1 {
  if (typeof rawJson !== 'string' || !rawJson.trim()) {
    throw new ProjectPackageError(
      'malformed_json',
      'Project package input is empty. Choose a .daywellproject file or paste valid JSON.'
    );
  }

  let decoded: unknown;
  try {
    decoded = JSON.parse(rawJson);
  } catch (err) {
    throw new ProjectPackageError(
      'malformed_json',
      `Malformed JSON in project package: ${
        err instanceof Error ? err.message : 'parse error'
      }.`
    );
  }

  if (!isPlainObject(decoded)) {
    throw new ProjectPackageError(
      'invalid_format',
      'Project package root must be a JSON object.'
    );
  }

  if (decoded.formatId !== SHARED_PROJECT_PACKAGE_SPEC.formatId) {
    throw new ProjectPackageError(
      'invalid_format',
      `Invalid project package formatId "${String(
        decoded.formatId ?? ''
      )}". Expected "${SHARED_PROJECT_PACKAGE_SPEC.formatId}".`
    );
  }

  const rawVersion = decoded.formatVersion;
  if (typeof rawVersion !== 'number' || !Number.isInteger(rawVersion)) {
    throw new ProjectPackageError(
      'invalid_format',
      'Project package formatVersion must be an integer.'
    );
  }
  if (
    rawVersion < SHARED_PROJECT_PACKAGE_SPEC.minSupportedFormatVersion ||
    rawVersion > SHARED_PROJECT_PACKAGE_SPEC.currentFormatVersion
  ) {
    throw new ProjectPackageError(
      'unsupported_version',
      `Unsupported .daywellproject formatVersion ${rawVersion}. This version of Daywell supports version ${SHARED_PROJECT_PACKAGE_SPEC.currentFormatVersion}.`
    );
  }

  const exportedAt = assertValidIsoTimestamp(decoded.exportedAt, 'exportedAt');
  const sourcePlatform =
    parseOptionalString(decoded.sourcePlatform, 'sourcePlatform') ?? 'unknown';

  if (!isPlainObject(decoded.project)) {
    throw new ProjectPackageError(
      'validation_failed',
      'Project package must contain a "project" object.'
    );
  }

  const nowIso = EthiopiaClock.nowUtc().toISOString();
  const rawProj = decoded.project;
  const projId = parseOptionalString(rawProj.id, 'project.id');
  if (!projId) {
    throw new ProjectPackageError(
      'validation_failed',
      'Package field "project.id" is required and must be a non-empty string.'
    );
  }
  const projTitle = parseOptionalString(rawProj.title, 'project.title');
  if (!projTitle) {
    throw new ProjectPackageError(
      'validation_failed',
      'Package field "project.title" is required and must be a non-empty string.'
    );
  }
  if (
    typeof rawProj.status !== 'string' ||
    !VALID_PROJECT_STATUSES.has(rawProj.status)
  ) {
    throw new ProjectPackageError(
      'validation_failed',
      `Package field "project.status" must be one of: ${SHARED_BUSINESS_RULES.projects.statuses.join(
        ', '
      )}.`
    );
  }

  if (
    rawProj.customFields !== undefined &&
    rawProj.customFields !== null &&
    !isPlainObject(rawProj.customFields)
  ) {
    throw new ProjectPackageError(
      'validation_failed',
      'Package field "project.customFields" must be a JSON object.'
    );
  }

  const projectCreatedAt =
    parseOptionalIsoTimestamp(rawProj.createdAt, 'project.createdAt') ?? nowIso;
  const projectUpdatedAt =
    parseOptionalIsoTimestamp(rawProj.updatedAt, 'project.updatedAt') ??
    projectCreatedAt;

  const project: DaywellProjectPackageProject = {
    id: projId,
    title: projTitle,
    ...(parseOptionalString(rawProj.description, 'project.description') !== undefined
      ? {
          description: parseOptionalString(
            rawProj.description,
            'project.description'
          ),
        }
      : {}),
    status: rawProj.status as SharedProject['status'],
    ...(parseOptionalCanonicalDate(rawProj.startDate, 'project.startDate') !==
    undefined
      ? {
          startDate: parseOptionalCanonicalDate(
            rawProj.startDate,
            'project.startDate'
          ),
        }
      : {}),
    ...(parseOptionalCanonicalDate(rawProj.targetDate, 'project.targetDate') !==
    undefined
      ? {
          targetDate: parseOptionalCanonicalDate(
            rawProj.targetDate,
            'project.targetDate'
          ),
        }
      : {}),
    isArchived: parseBooleanWithDefault(
      rawProj.isArchived,
      'project.isArchived',
      false
    ),
    customFields: cloneJsonObject(rawProj.customFields),
    createdAt: projectCreatedAt,
    updatedAt: projectUpdatedAt,
  };

  try {
    validateProject(project);
  } catch (err) {
    throw new ProjectPackageError(
      'validation_failed',
      err instanceof ProjectValidationError || err instanceof Error
        ? err.message
        : 'Invalid project payload.'
    );
  }

  if (!Array.isArray(decoded.trackingBlocks)) {
    throw new ProjectPackageError(
      'validation_failed',
      'Project package must contain a "trackingBlocks" array.'
    );
  }
  if (
    decoded.trackingBlocks.length >
    SHARED_BUSINESS_RULES.projects.bounds.maxBlocksPerProject
  ) {
    throw new ProjectPackageError(
      'validation_failed',
      `Project package exceeds maximum tracking blocks (${SHARED_BUSINESS_RULES.projects.bounds.maxBlocksPerProject}).`
    );
  }

  const parsedBlocks: SharedProjectTrackingBlock[] = [];
  const blockIdsSeen = new Set<string>();

  for (let i = 0; i < decoded.trackingBlocks.length; i += 1) {
    const rawBlk = decoded.trackingBlocks[i];
    const prefix = `trackingBlocks[${i}]`;
    if (!isPlainObject(rawBlk)) {
      throw new ProjectPackageError(
        'validation_failed',
        `Package entry "${prefix}" must be a JSON object.`
      );
    }
    const blkId = parseOptionalString(rawBlk.id, `${prefix}.id`);
    if (!blkId) {
      throw new ProjectPackageError(
        'validation_failed',
        `Package field "${prefix}.id" is required.`
      );
    }
    if (blockIdsSeen.has(blkId)) {
      throw new ProjectPackageError(
        'validation_failed',
        `Duplicate tracking block id "${blkId}" in package.`
      );
    }
    blockIdsSeen.add(blkId);

    const blkProjId = parseOptionalString(
      rawBlk.projectId,
      `${prefix}.projectId`
    );
    if (blkProjId !== project.id) {
      throw new ProjectPackageError(
        'validation_failed',
        `Block "${blkId}" projectId "${String(
          rawBlk.projectId ?? ''
        )}" does not match package project "${project.id}".`
      );
    }
    if (
      typeof rawBlk.blockType !== 'string' ||
      !VALID_BLOCK_TYPES.has(rawBlk.blockType)
    ) {
      throw new ProjectPackageError(
        'validation_failed',
        `Block "${blkId}" has unsupported blockType "${String(
          rawBlk.blockType ?? ''
        )}".`
      );
    }
    const blkTitle = parseOptionalString(rawBlk.title, `${prefix}.title`);
    if (!blkTitle) {
      throw new ProjectPackageError(
        'validation_failed',
        `Block "${blkId}" title is required.`
      );
    }
    if (
      rawBlk.config !== undefined &&
      rawBlk.config !== null &&
      !isPlainObject(rawBlk.config)
    ) {
      throw new ProjectPackageError(
        'validation_failed',
        `Block "${blkId}" config must be an object.`
      );
    }

    const blkCreatedAt =
      parseOptionalIsoTimestamp(rawBlk.createdAt, `${prefix}.createdAt`) ??
      projectCreatedAt;
    const blkUpdatedAt =
      parseOptionalIsoTimestamp(rawBlk.updatedAt, `${prefix}.updatedAt`) ??
      blkCreatedAt;

    const unitLabel = parseOptionalString(
      rawBlk.unitLabel,
      `${prefix}.unitLabel`
    );
    const targetValue = parseOptionalFiniteNumber(
      rawBlk.targetValue,
      `${prefix}.targetValue`
    );
    const dailyTargetValue = parseOptionalFiniteNumber(
      rawBlk.dailyTargetValue,
      `${prefix}.dailyTargetValue`
    );

    parsedBlocks.push({
      id: blkId,
      projectId: project.id,
      blockType: rawBlk.blockType as SharedProjectBlockType,
      title: blkTitle,
      sortOrder: parseNonNegativeInt(
        rawBlk.sortOrder,
        `${prefix}.sortOrder`,
        i
      ),
      ...(unitLabel !== undefined ? { unitLabel } : {}),
      ...(targetValue !== undefined ? { targetValue } : {}),
      ...(dailyTargetValue !== undefined ? { dailyTargetValue } : {}),
      config: cloneJsonObject(rawBlk.config),
      isArchived: parseBooleanWithDefault(
        rawBlk.isArchived,
        `${prefix}.isArchived`,
        false
      ),
      createdAt: blkCreatedAt,
      updatedAt: blkUpdatedAt,
    });
  }

  // Verify primaryBlockId if configured
  const rawPrimaryBlockId =
    typeof project.customFields.primaryBlockId === 'string'
      ? project.customFields.primaryBlockId.trim()
      : '';
  if (rawPrimaryBlockId && !blockIdsSeen.has(rawPrimaryBlockId)) {
    throw new ProjectPackageError(
      'validation_failed',
      `Project customFields.primaryBlockId "${rawPrimaryBlockId}" references a missing tracking block.`
    );
  }

  // Validate blocks topologically so rollupSourceBlockId resolves cleanly
  const orderedBlocks = sortBlocksTopologically(parsedBlocks);
  const validatedBlocks: SharedProjectTrackingBlock[] = [];
  for (const blk of orderedBlocks) {
    try {
      validateBlock(blk, {
        expectedProjectId: project.id,
        projectBlocks: validatedBlocks,
        isNew: true,
      });
    } catch (err) {
      throw new ProjectPackageError(
        'validation_failed',
        err instanceof Error ? err.message : `Invalid block "${blk.id}".`
      );
    }
    validatedBlocks.push(blk);
  }
  const blockById = new Map(validatedBlocks.map((b) => [b.id, b]));

  if (!Array.isArray(decoded.trackingRecords)) {
    throw new ProjectPackageError(
      'validation_failed',
      'Project package must contain a "trackingRecords" array.'
    );
  }

  const parsedRecords: SharedProjectTrackingRecord[] = [];
  const recordIdsSeen = new Set<string>();

  for (let i = 0; i < decoded.trackingRecords.length; i += 1) {
    const rawRec = decoded.trackingRecords[i];
    const prefix = `trackingRecords[${i}]`;
    if (!isPlainObject(rawRec)) {
      throw new ProjectPackageError(
        'validation_failed',
        `Package entry "${prefix}" must be a JSON object.`
      );
    }
    const recId = parseOptionalString(rawRec.id, `${prefix}.id`);
    if (!recId) {
      throw new ProjectPackageError(
        'validation_failed',
        `Package field "${prefix}.id" is required.`
      );
    }
    if (recordIdsSeen.has(recId)) {
      throw new ProjectPackageError(
        'validation_failed',
        `Duplicate tracking record id "${recId}" in package.`
      );
    }
    recordIdsSeen.add(recId);

    const recProjId = parseOptionalString(
      rawRec.projectId,
      `${prefix}.projectId`
    );
    if (recProjId !== project.id) {
      throw new ProjectPackageError(
        'validation_failed',
        `Record "${recId}" projectId "${String(
          rawRec.projectId ?? ''
        )}" does not match package project "${project.id}".`
      );
    }
    const recBlockId = parseOptionalString(
      rawRec.blockId,
      `${prefix}.blockId`
    );
    if (!recBlockId || !blockById.has(recBlockId)) {
      throw new ProjectPackageError(
        'validation_failed',
        `Record "${recId}" references missing blockId "${String(
          rawRec.blockId ?? ''
        )}".`
      );
    }
    if (
      typeof rawRec.recordType !== 'string' ||
      !VALID_RECORD_TYPES.has(rawRec.recordType)
    ) {
      throw new ProjectPackageError(
        'validation_failed',
        `Record "${recId}" has unsupported recordType "${String(
          rawRec.recordType ?? ''
        )}".`
      );
    }
    if (
      rawRec.metadata !== undefined &&
      rawRec.metadata !== null &&
      !isPlainObject(rawRec.metadata)
    ) {
      throw new ProjectPackageError(
        'validation_failed',
        `Record "${recId}" metadata must be an object.`
      );
    }

    const recCreatedAt =
      parseOptionalIsoTimestamp(rawRec.createdAt, `${prefix}.createdAt`) ??
      projectCreatedAt;
    const recUpdatedAt =
      parseOptionalIsoTimestamp(rawRec.updatedAt, `${prefix}.updatedAt`) ??
      recCreatedAt;

    const parentRecordId = parseOptionalString(
      rawRec.parentRecordId,
      `${prefix}.parentRecordId`
    );
    const title = parseOptionalString(rawRec.title, `${prefix}.title`);
    const targetValue = parseOptionalFiniteNumber(
      rawRec.targetValue,
      `${prefix}.targetValue`
    );
    const deltaValue = parseOptionalFiniteNumber(
      rawRec.deltaValue,
      `${prefix}.deltaValue`
    );
    const durationMinutes = parseOptionalNonNegativeInt(
      rawRec.durationMinutes,
      `${prefix}.durationMinutes`
    );
    const completedAt = parseOptionalIsoTimestamp(
      rawRec.completedAt,
      `${prefix}.completedAt`
    );
    const recordedDate = parseOptionalCanonicalDate(
      rawRec.recordedDate,
      `${prefix}.recordedDate`
    );
    const scheduledDate = parseOptionalCanonicalDate(
      rawRec.scheduledDate,
      `${prefix}.scheduledDate`
    );

    parsedRecords.push({
      id: recId,
      projectId: project.id,
      blockId: recBlockId,
      ...(parentRecordId !== undefined ? { parentRecordId } : {}),
      recordType: rawRec.recordType as SharedProjectRecordType,
      ...(title !== undefined ? { title } : {}),
      sortOrder: parseNonNegativeInt(
        rawRec.sortOrder,
        `${prefix}.sortOrder`,
        i
      ),
      ...(targetValue !== undefined ? { targetValue } : {}),
      ...(deltaValue !== undefined ? { deltaValue } : {}),
      ...(durationMinutes !== undefined ? { durationMinutes } : {}),
      isCompleted: parseBooleanWithDefault(
        rawRec.isCompleted,
        `${prefix}.isCompleted`,
        false
      ),
      ...(completedAt !== undefined ? { completedAt } : {}),
      ...(recordedDate !== undefined ? { recordedDate } : {}),
      ...(scheduledDate !== undefined ? { scheduledDate } : {}),
      // linkedTaskId intentionally cleared on import
      metadata: cloneJsonObject(rawRec.metadata),
      createdAt: recCreatedAt,
      updatedAt: recUpdatedAt,
    });
  }

  const orderedRecords = sortRecordsTopologically(parsedRecords);
  const validatedByBlock = new Map<string, SharedProjectTrackingRecord[]>();

  for (const rec of orderedRecords) {
    const blk = blockById.get(rec.blockId)!;
    const blockRecords = validatedByBlock.get(blk.id) ?? [];
    try {
      validateRecord(rec, {
        block: blk,
        existingBlockRecords: blockRecords,
        isNew: true,
      });
    } catch (err) {
      throw new ProjectPackageError(
        'validation_failed',
        err instanceof Error ? err.message : `Invalid record "${rec.id}".`
      );
    }
    blockRecords.push(rec);
    validatedByBlock.set(blk.id, blockRecords);
  }

  return {
    formatId: SHARED_PROJECT_PACKAGE_SPEC.formatId,
    formatVersion: rawVersion,
    exportedAt,
    sourcePlatform,
    project,
    trackingBlocks: validatedBlocks,
    trackingRecords: orderedRecords,
  };
}

function allocateUniqueId(
  prefix: 'proj' | 'blk' | 'rec',
  existingIds: Set<string>,
  allocatedIds: Set<string>,
  generator: (prefix: 'proj' | 'blk' | 'rec') => string
): string {
  for (let attempt = 0; attempt < 32; attempt += 1) {
    const candidate = generator(prefix);
    if (!existingIds.has(candidate) && !allocatedIds.has(candidate)) {
      allocatedIds.add(candidate);
      return candidate;
    }
  }
  // Guaranteed unique deterministic suffix fallback
  let suffix = allocatedIds.size + existingIds.size + 1;
  while (true) {
    const candidate = `${prefix}-${EthiopiaClock.nowUtc().getTime()}-${suffix}`;
    if (!existingIds.has(candidate) && !allocatedIds.has(candidate)) {
      allocatedIds.add(candidate);
      return candidate;
    }
    suffix += 1;
  }
}

/**
 * Validates a `.daywellproject` JSON payload and prepares a collision-free
 * local import bundle with all IDs remapped and cross-module `goalId` /
 * `linkedTaskId` references cleared.
 */
export function prepareProjectPackageForImport(
  rawJson: string,
  options: PrepareProjectPackageImportOptions = {}
): PreparedProjectPackageImport {
  const pkg = parseAndValidateProjectPackage(rawJson);
  const generator = options.generateId ?? defaultGenerateId;
  const existingProjects = new Set(options.existingProjectIds ?? []);
  const existingBlocks = new Set(options.existingBlockIds ?? []);
  const existingRecords = new Set(options.existingRecordIds ?? []);

  const allocatedProjects = new Set<string>();
  const allocatedBlocks = new Set<string>();
  const allocatedRecords = new Set<string>();

  const newProjectId = allocateUniqueId(
    'proj',
    existingProjects,
    allocatedProjects,
    generator
  );

  const blockIdMap = new Map<string, string>();
  for (const blk of pkg.trackingBlocks) {
    blockIdMap.set(
      blk.id,
      allocateUniqueId('blk', existingBlocks, allocatedBlocks, generator)
    );
  }

  const recordIdMap = new Map<string, string>();
  for (const rec of pkg.trackingRecords) {
    recordIdMap.set(
      rec.id,
      allocateUniqueId('rec', existingRecords, allocatedRecords, generator)
    );
  }

  const nextCustomFields = cloneJsonObject(pkg.project.customFields);
  if (
    typeof nextCustomFields.primaryBlockId === 'string' &&
    nextCustomFields.primaryBlockId.trim()
  ) {
    const remappedPrimary = blockIdMap.get(
      nextCustomFields.primaryBlockId.trim()
    );
    if (!remappedPrimary) {
      throw new ProjectPackageError(
        'validation_failed',
        `Project primaryBlockId "${nextCustomFields.primaryBlockId}" could not be remapped.`
      );
    }
    nextCustomFields.primaryBlockId = remappedPrimary;
  }

  const importedProject: SharedProject = {
    id: newProjectId,
    title: pkg.project.title,
    ...(pkg.project.description !== undefined
      ? { description: pkg.project.description }
      : {}),
    status: pkg.project.status,
    ...(pkg.project.targetDate !== undefined
      ? { targetDate: pkg.project.targetDate }
      : {}),
    ...(pkg.project.startDate !== undefined
      ? { startDate: pkg.project.startDate }
      : {}),
    // goalId explicitly omitted/cleared on import
    isArchived: pkg.project.isArchived,
    customFields: nextCustomFields,
    createdAt: pkg.project.createdAt,
    updatedAt: pkg.project.updatedAt,
  };

  const importedBlocks: SharedProjectTrackingBlock[] = pkg.trackingBlocks.map(
    (blk) => {
      const nextConfig = cloneJsonObject(blk.config);
      if (
        blk.blockType === 'counter' &&
        typeof nextConfig.rollupSourceBlockId === 'string' &&
        nextConfig.rollupSourceBlockId.trim()
      ) {
        const remappedSource = blockIdMap.get(
          nextConfig.rollupSourceBlockId.trim()
        );
        if (!remappedSource) {
          throw new ProjectPackageError(
            'validation_failed',
            `Block "${blk.id}" rollupSourceBlockId "${nextConfig.rollupSourceBlockId}" could not be remapped.`
          );
        }
        nextConfig.rollupSourceBlockId = remappedSource;
      }

      return {
        id: blockIdMap.get(blk.id)!,
        projectId: newProjectId,
        blockType: blk.blockType,
        title: blk.title,
        sortOrder: blk.sortOrder,
        ...(blk.unitLabel !== undefined ? { unitLabel: blk.unitLabel } : {}),
        ...(blk.targetValue !== undefined
          ? { targetValue: blk.targetValue }
          : {}),
        ...(blk.dailyTargetValue !== undefined
          ? { dailyTargetValue: blk.dailyTargetValue }
          : {}),
        config: nextConfig,
        isArchived: blk.isArchived,
        createdAt: blk.createdAt,
        updatedAt: blk.updatedAt,
      };
    }
  );

  const importedRecords: SharedProjectTrackingRecord[] =
    pkg.trackingRecords.map((rec) => {
      const nextMeta = cloneJsonObject(rec.metadata);
      if (
        typeof nextMeta.compensatesRecordId === 'string' &&
        nextMeta.compensatesRecordId.trim()
      ) {
        const remappedTarget = recordIdMap.get(
          nextMeta.compensatesRecordId.trim()
        );
        if (!remappedTarget) {
          throw new ProjectPackageError(
            'validation_failed',
            `Correction "${rec.id}" compensatesRecordId "${nextMeta.compensatesRecordId}" could not be remapped.`
          );
        }
        nextMeta.compensatesRecordId = remappedTarget;
      }

      return {
        id: recordIdMap.get(rec.id)!,
        projectId: newProjectId,
        blockId: blockIdMap.get(rec.blockId)!,
        ...(rec.parentRecordId !== undefined
          ? { parentRecordId: recordIdMap.get(rec.parentRecordId)! }
          : {}),
        recordType: rec.recordType,
        ...(rec.title !== undefined ? { title: rec.title } : {}),
        sortOrder: rec.sortOrder,
        ...(rec.targetValue !== undefined
          ? { targetValue: rec.targetValue }
          : {}),
        ...(rec.deltaValue !== undefined ? { deltaValue: rec.deltaValue } : {}),
        ...(rec.durationMinutes !== undefined
          ? { durationMinutes: rec.durationMinutes }
          : {}),
        isCompleted: rec.isCompleted,
        ...(rec.completedAt !== undefined
          ? { completedAt: rec.completedAt }
          : {}),
        ...(rec.recordedDate !== undefined
          ? { recordedDate: rec.recordedDate }
          : {}),
        ...(rec.scheduledDate !== undefined
          ? { scheduledDate: rec.scheduledDate }
          : {}),
        // linkedTaskId explicitly omitted/cleared on import
        metadata: nextMeta,
        createdAt: rec.createdAt,
        updatedAt: rec.updatedAt,
      };
    });

  // Final post-remap invariant pass
  validateProject(importedProject);
  const validatedBlocks: SharedProjectTrackingBlock[] = [];
  for (const blk of importedBlocks) {
    validateBlock(blk, {
      expectedProjectId: newProjectId,
      projectBlocks: validatedBlocks,
      isNew: true,
    });
    validatedBlocks.push(blk);
  }
  const blockById = new Map(validatedBlocks.map((b) => [b.id, b]));
  const recordsByBlock = new Map<string, SharedProjectTrackingRecord[]>();
  for (const rec of importedRecords) {
    const blk = blockById.get(rec.blockId)!;
    const existing = recordsByBlock.get(blk.id) ?? [];
    validateRecord(rec, {
      block: blk,
      existingBlockRecords: existing,
      isNew: true,
    });
    existing.push(rec);
    recordsByBlock.set(blk.id, existing);
  }

  return {
    sourceFormatVersion: pkg.formatVersion,
    sourcePlatform: pkg.sourcePlatform,
    exportedAt: pkg.exportedAt,
    project: importedProject,
    trackingBlocks: validatedBlocks,
    trackingRecords: importedRecords,
  };
}
