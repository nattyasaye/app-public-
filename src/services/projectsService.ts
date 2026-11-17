import { CalendarDate, EthiopiaClock } from '../domain/date';
import {
  CounterBlockConfig,
  GroupedListBlockConfig,
  ChecklistBlockConfig,
  ScheduleBlockConfig,
  ProjectBlockProgressMetric,
  ProjectProgressSummary,
  ProjectScheduleSpan,
  ProjectValidationError,
  getProjectScheduleSpan,
  meetsScheduleDurationRule,
  parseCounterBlockConfig,
  parseScheduleBlockConfig,
  validateBlock,
  validateProject,
} from '../domain/projectsEngine';
import {
  BIM_OUTREACH_CAMPAIGN_TITLE,
  serializeBimOutreachTemplateJson,
} from '../domain/bimOutreachTemplate';
import {
  SharedGoal,
  SharedProject,
  SharedProjectBlockType,
  SharedProjectTrackingBlock,
  SharedProjectTrackingRecord,
  SharedTask,
} from '../domain/sharedFoundation';
import { WebProjectsRepository } from '../data/projectsRepository';
import {
  buildProjectPackageFilename,
  PreparedProjectPackageImport,
  ProjectPackageError,
} from '../domain/projectPackage';
import { SharedStateBridge } from './sharedStateBridge';

export interface InlineBlockDraft {
  tempId: string;
  blockType: SharedProjectBlockType;
  title: string;
  unitLabel?: string;
  targetValue?: number;
  dailyTargetValue?: number;
  config?: Record<string, unknown>;
}

export interface CreateProjectWithBlocksInput {
  title: string;
  description?: string;
  status: SharedProject['status'];
  startDate?: string;
  targetDate?: string;
  goalId?: string;
  primaryDraftTempId?: string;
  blocks: InlineBlockDraft[];
}

export interface UpdateProjectDetailsInput {
  projectId: string;
  title: string;
  description?: string;
  status: SharedProject['status'];
  startDate?: string;
  targetDate?: string;
  goalId?: string;
  primaryBlockId?: string;
  newBlocks?: InlineBlockDraft[];
  primaryDraftTempId?: string;
}

export interface ProjectDetailSnapshot {
  project: SharedProject;
  blocks: SharedProjectTrackingBlock[];
  records: SharedProjectTrackingRecord[];
  summary: ProjectProgressSummary;
  linkedTasks: SharedTask[];
}

export interface EnrichedProgressLogEntry {
  record: SharedProjectTrackingRecord;
  blockTitle: string;
  blockType: SharedProjectBlockType;
  unitLabel?: string;
  parentItemTitle?: string;
  groupTitle?: string;
  isCorrection: boolean;
  compensatesRecordId?: string;
  correctionReason?: string;
}

const GOALS_KEY = 'daywell_goals';
const TASKS_KEY = 'daywell_tasks';

function makeId(prefix: string): string {
  const now = EthiopiaClock.nowUtc().getTime();
  const rand = Math.floor(Math.random() * 100000);
  return `${prefix}-${now}-${rand}`;
}

function broadcastSync(): void {
  if (typeof window !== 'undefined' && typeof window.dispatchEvent === 'function') {
    window.dispatchEvent(new CustomEvent(SharedStateBridge.SYNC_EVENT_NAME));
  }
}

function readLocalArray<T>(key: string): T[] {
  if (typeof localStorage === 'undefined') return [];
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? (parsed as T[]) : [];
  } catch {
    return [];
  }
}

class ProjectsService {
  private readonly repo = new WebProjectsRepository();

  public listProjects(
    options: { status?: SharedProject['status']; includeArchived?: boolean } = {}
  ): SharedProject[] {
    return this.repo.getProjects(options);
  }

  public getProject(projectId: string): SharedProject | undefined {
    return this.repo.getProjectById(projectId);
  }

  public getGoals(): SharedGoal[] {
    return readLocalArray<SharedGoal>(GOALS_KEY);
  }

  public getLinkedTasks(projectId: string): SharedTask[] {
    return readLocalArray<SharedTask>(TASKS_KEY).filter(
      (t) => t.projectId === projectId
    );
  }

  public getAllProjectSummaries(
    options: { asOfDate?: CalendarDate; includeArchived?: boolean } = {}
  ): Record<string, ProjectProgressSummary> {
    const projects = this.repo.getProjects({
      includeArchived: options.includeArchived ?? true,
    });
    const out: Record<string, ProjectProgressSummary> = {};
    for (const proj of projects) {
      out[proj.id] = this.repo.getProjectProgressSummary(proj.id, {
        asOfDate: options.asOfDate,
      });
    }
    return out;
  }

  public getProjectDetailSnapshot(
    projectId: string,
    options: { asOfDate?: CalendarDate } = {}
  ): ProjectDetailSnapshot | undefined {
    const project = this.repo.getProjectById(projectId);
    if (!project) return undefined;
    const blocks = this.repo.getBlocksForProject(projectId, {
      includeArchived: true,
    });
    const records = this.repo.getRecordsForProject(projectId);
    const summary = this.repo.getProjectProgressSummary(projectId, {
      asOfDate: options.asOfDate,
    });
    const linkedTasks = this.getLinkedTasks(projectId);
    return {
      project,
      blocks,
      records,
      summary,
      linkedTasks,
    };
  }

  public getChronologicalProgressHistory(
    projectId: string
  ): EnrichedProgressLogEntry[] {
    const blocks = this.repo.getBlocksForProject(projectId, {
      includeArchived: true,
    });
    const records = this.repo.getRecordsForProject(projectId);
    const blockById = new Map(blocks.map((b) => [b.id, b]));
    const recordById = new Map(records.map((r) => [r.id, r]));

    return records
      .filter((r) => r.recordType === 'progress_log')
      .sort((a, b) => {
        const dateCmp = (b.recordedDate ?? '').localeCompare(a.recordedDate ?? '');
        if (dateCmp !== 0) return dateCmp;
        return (b.createdAt ?? '').localeCompare(a.createdAt ?? '');
      })
      .map((rec) => {
        const block = blockById.get(rec.blockId);
        const parentItem = rec.parentRecordId
          ? recordById.get(rec.parentRecordId)
          : undefined;
        const parentGroup =
          parentItem?.parentRecordId !== undefined
            ? recordById.get(parentItem.parentRecordId)
            : undefined;
        const meta = rec.metadata ?? {};
        return {
          record: rec,
          blockTitle: block?.title ?? 'Tracking block',
          blockType: block?.blockType ?? 'counter',
          unitLabel: block?.unitLabel,
          parentItemTitle: parentItem?.title,
          groupTitle: parentGroup?.title,
          isCorrection: meta.isCorrection === true,
          compensatesRecordId:
            typeof meta.compensatesRecordId === 'string'
              ? meta.compensatesRecordId
              : undefined,
          correctionReason:
            typeof meta.correctionReason === 'string'
              ? meta.correctionReason
              : undefined,
        };
      });
  }

  private buildCandidateBlocks(
    projectId: string,
    drafts: InlineBlockDraft[],
    startingSortOrder: number,
    existingSiblingBlocks: SharedProjectTrackingBlock[]
  ): {
    tempToRealId: Map<string, string>;
    prepared: SharedProjectTrackingBlock[];
  } {
    const tempToRealId = new Map<string, string>();
    const nowIso = EthiopiaClock.nowUtc().toISOString();

    for (const draft of drafts) {
      tempToRealId.set(draft.tempId, makeId('blk'));
    }

    const resolveBlockConfig = (draft: InlineBlockDraft): Record<string, unknown> => {
      if (draft.blockType === 'counter') {
        const rawSource =
          typeof draft.config?.rollupSourceBlockId === 'string'
            ? draft.config.rollupSourceBlockId.trim()
            : undefined;
        const resolvedSource = rawSource
          ? tempToRealId.get(rawSource) ?? rawSource
          : undefined;
        const cfg: CounterBlockConfig = resolvedSource
          ? { rollupSourceBlockId: resolvedSource, allowDirectLogging: false }
          : { allowDirectLogging: true };
        return cfg as unknown as Record<string, unknown>;
      }
      return { ...(draft.config ?? {}) };
    };

    const orderedDrafts = [...drafts].sort((a, b) => {
      const aRollup =
        a.blockType === 'counter' && Boolean(a.config?.rollupSourceBlockId);
      const bRollup =
        b.blockType === 'counter' && Boolean(b.config?.rollupSourceBlockId);
      if (aRollup === bRollup) return 0;
      return aRollup ? 1 : -1;
    });

    const prepared: SharedProjectTrackingBlock[] = [];
    const accumulatedSiblings = [...existingSiblingBlocks];

    drafts.forEach((draft, idx) => {
      const id = tempToRealId.get(draft.tempId)!;
      const block: SharedProjectTrackingBlock = {
        id,
        projectId,
        blockType: draft.blockType,
        title: draft.title.trim(),
        sortOrder: startingSortOrder + idx,
        ...(draft.unitLabel?.trim() ? { unitLabel: draft.unitLabel.trim() } : {}),
        ...(draft.targetValue !== undefined ? { targetValue: draft.targetValue } : {}),
        ...(draft.dailyTargetValue !== undefined
          ? { dailyTargetValue: draft.dailyTargetValue }
          : {}),
        config: resolveBlockConfig(draft),
        isArchived: false,
        createdAt: nowIso,
        updatedAt: nowIso,
      };
      // Store temporarily by index; validate in topological order below
      prepared.push(block);
    });

    const preparedById = new Map(prepared.map((b) => [b.id, b]));
    for (const draft of orderedDrafts) {
      const block = preparedById.get(tempToRealId.get(draft.tempId)!)!;
      validateBlock(block, {
        expectedProjectId: projectId,
        projectBlocks: accumulatedSiblings,
        isNew: true,
      });
      accumulatedSiblings.push(block);
    }

    const preparedInCreationOrder = orderedDrafts.map(
      (d) => preparedById.get(tempToRealId.get(d.tempId)!)!
    );

    return { tempToRealId, prepared: preparedInCreationOrder };
  }

  public createProjectWithBlocks(
    input: CreateProjectWithBlocksInput
  ): SharedProject {
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const projectId = makeId('proj');
    const baseProject: SharedProject = {
      id: projectId,
      title: input.title.trim(),
      ...(input.description?.trim()
        ? { description: input.description.trim() }
        : {}),
      status: input.status,
      ...(input.startDate ? { startDate: input.startDate } : {}),
      ...(input.targetDate ? { targetDate: input.targetDate } : {}),
      ...(input.goalId?.trim() ? { goalId: input.goalId.trim() } : {}),
      isArchived: false,
      customFields: {},
      createdAt: nowIso,
      updatedAt: nowIso,
    };

    // Pre-validate project and all inline block drafts before writing anything
    validateProject(baseProject);
    const { tempToRealId, prepared } = this.buildCandidateBlocks(
      projectId,
      input.blocks,
      0,
      []
    );

    const createdProject = this.repo.createProject(baseProject);
    try {
      for (const blk of prepared) {
        this.repo.createBlock(blk);
      }

      if (input.primaryDraftTempId) {
        const primaryId = tempToRealId.get(input.primaryDraftTempId);
        if (primaryId) {
          this.repo.updateProject({
            ...createdProject,
            customFields: {
              ...(createdProject.customFields ?? {}),
              primaryBlockId: primaryId,
            },
          });
        }
      }
    } catch (err) {
      this.repo.deleteProject(projectId);
      throw err;
    }

    broadcastSync();
    return this.repo.getProjectById(projectId) ?? createdProject;
  }

  public updateProjectDetails(input: UpdateProjectDetailsInput): SharedProject {
    const existing = this.repo.getProjectById(input.projectId);
    if (!existing) {
      throw new ProjectValidationError(
        `Cannot update missing project "${input.projectId}".`
      );
    }

    const existingBlocks = this.repo.getBlocksForProject(existing.id, {
      includeArchived: true,
    });
    const newDrafts = input.newBlocks ?? [];
    const maxSort = existingBlocks.reduce(
      (max, b) => Math.max(max, b.sortOrder),
      -1
    );

    const { tempToRealId, prepared } = this.buildCandidateBlocks(
      existing.id,
      newDrafts,
      maxSort + 1,
      existingBlocks
    );

    const resolvedPrimaryBlockId = input.primaryDraftTempId
      ? tempToRealId.get(input.primaryDraftTempId)
      : input.primaryBlockId?.trim() || undefined;

    const nextCustomFields: Record<string, unknown> = {
      ...(existing.customFields ?? {}),
    };
    if (resolvedPrimaryBlockId) {
      nextCustomFields.primaryBlockId = resolvedPrimaryBlockId;
    } else {
      delete nextCustomFields.primaryBlockId;
    }

    const candidateProject: SharedProject = {
      ...existing,
      title: input.title.trim(),
      description: input.description?.trim() || undefined,
      status: input.status,
      startDate: input.startDate || undefined,
      targetDate: input.targetDate || undefined,
      goalId: input.goalId?.trim() || undefined,
      customFields: nextCustomFields,
    };

    validateProject(candidateProject);

    for (const blk of prepared) {
      this.repo.createBlock(blk);
    }
    const updated = this.repo.updateProject(candidateProject);
    broadcastSync();
    return updated;
  }

  public setProjectArchived(
    projectId: string,
    isArchived: boolean
  ): SharedProject {
    const updated = this.repo.setProjectArchived(projectId, isArchived);
    broadcastSync();
    return updated;
  }

  public deleteArchivedProject(projectId: string): void {
    const existing = this.repo.getProjectById(projectId);
    if (!existing) return;
    if (!existing.isArchived) {
      throw new ProjectValidationError(
        'Active projects must be archived before permanent deletion.'
      );
    }
    this.repo.deleteProject(projectId);
    broadcastSync();
  }

  public createBlock(input: {
    projectId: string;
    blockType: SharedProjectBlockType;
    title: string;
    unitLabel?: string;
    targetValue?: number;
    dailyTargetValue?: number;
    config?: Record<string, unknown>;
    setAsPrimary?: boolean;
  }): SharedProjectTrackingBlock {
    const existingBlocks = this.repo.getBlocksForProject(input.projectId, {
      includeArchived: true,
    });
    const maxSort = existingBlocks.reduce(
      (max, b) => Math.max(max, b.sortOrder),
      -1
    );
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const block: SharedProjectTrackingBlock = {
      id: makeId('blk'),
      projectId: input.projectId,
      blockType: input.blockType,
      title: input.title.trim(),
      sortOrder: maxSort + 1,
      ...(input.unitLabel?.trim() ? { unitLabel: input.unitLabel.trim() } : {}),
      ...(input.targetValue !== undefined ? { targetValue: input.targetValue } : {}),
      ...(input.dailyTargetValue !== undefined
        ? { dailyTargetValue: input.dailyTargetValue }
        : {}),
      config: input.config ?? {},
      isArchived: false,
      createdAt: nowIso,
      updatedAt: nowIso,
    };
    const created = this.repo.createBlock(block);
    if (input.setAsPrimary) {
      const proj = this.repo.getProjectById(input.projectId);
      if (proj) {
        this.repo.updateProject({
          ...proj,
          customFields: {
            ...(proj.customFields ?? {}),
            primaryBlockId: created.id,
          },
        });
      }
    }
    broadcastSync();
    return created;
  }

  public updateBlock(
    block: SharedProjectTrackingBlock
  ): SharedProjectTrackingBlock {
    const updated = this.repo.updateBlock(block);
    broadcastSync();
    return updated;
  }

  public setBlockArchived(
    blockId: string,
    isArchived: boolean
  ): SharedProjectTrackingBlock {
    const updated = this.repo.setBlockArchived(blockId, isArchived);
    broadcastSync();
    return updated;
  }

  public setPrimaryBlock(
    projectId: string,
    blockId: string | undefined
  ): SharedProject {
    const project = this.repo.getProjectById(projectId);
    if (!project) {
      throw new ProjectValidationError(`Missing project "${projectId}".`);
    }
    const nextCustomFields: Record<string, unknown> = {
      ...(project.customFields ?? {}),
    };
    if (blockId) {
      nextCustomFields.primaryBlockId = blockId;
    } else {
      delete nextCustomFields.primaryBlockId;
    }
    const updated = this.repo.updateProject({
      ...project,
      customFields: nextCustomFields,
    });
    broadcastSync();
    return updated;
  }

  public deleteBlock(projectId: string, blockId: string): void {
    const project = this.repo.getProjectById(projectId);
    if (project && project.customFields?.primaryBlockId === blockId) {
      const nextCustomFields = { ...(project.customFields ?? {}) };
      delete nextCustomFields.primaryBlockId;
      this.repo.updateProject({
        ...project,
        customFields: nextCustomFields,
      });
    }
    this.repo.deleteBlock(blockId);
    broadcastSync();
  }

  public createGroup(input: {
    projectId: string;
    blockId: string;
    title: string;
    targetValue?: number;
  }): SharedProjectTrackingRecord {
    const existing = this.repo.getRecordsForProject(input.projectId, {
      blockId: input.blockId,
    });
    const maxSort = existing
      .filter((r) => r.recordType === 'group')
      .reduce((max, r) => Math.max(max, r.sortOrder), -1);
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const created = this.repo.createRecord({
      id: makeId('grp'),
      projectId: input.projectId,
      blockId: input.blockId,
      recordType: 'group',
      title: input.title.trim(),
      sortOrder: maxSort + 1,
      ...(input.targetValue !== undefined ? { targetValue: input.targetValue } : {}),
      isCompleted: false,
      metadata: {},
      createdAt: nowIso,
      updatedAt: nowIso,
    });
    broadcastSync();
    return created;
  }

  public createGroupedItem(input: {
    projectId: string;
    blockId: string;
    groupId?: string;
    title: string;
    targetValue?: number;
  }): SharedProjectTrackingRecord {
    const existing = this.repo.getRecordsForProject(input.projectId, {
      blockId: input.blockId,
    });
    const maxSort = existing
      .filter((r) => r.recordType === 'grouped_item')
      .reduce((max, r) => Math.max(max, r.sortOrder), -1);
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const created = this.repo.createRecord({
      id: makeId('item'),
      projectId: input.projectId,
      blockId: input.blockId,
      ...(input.groupId ? { parentRecordId: input.groupId } : {}),
      recordType: 'grouped_item',
      title: input.title.trim(),
      sortOrder: maxSort + 1,
      ...(input.targetValue !== undefined ? { targetValue: input.targetValue } : {}),
      isCompleted: false,
      metadata: {},
      createdAt: nowIso,
      updatedAt: nowIso,
    });
    broadcastSync();
    return created;
  }

  public createChecklistItem(input: {
    projectId: string;
    blockId: string;
    title: string;
  }): SharedProjectTrackingRecord {
    const existing = this.repo.getRecordsForProject(input.projectId, {
      blockId: input.blockId,
    });
    const maxSort = existing
      .filter((r) => r.recordType === 'checklist_item')
      .reduce((max, r) => Math.max(max, r.sortOrder), -1);
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const created = this.repo.createRecord({
      id: makeId('chk'),
      projectId: input.projectId,
      blockId: input.blockId,
      recordType: 'checklist_item',
      title: input.title.trim(),
      sortOrder: maxSort + 1,
      isCompleted: false,
      metadata: {},
      createdAt: nowIso,
      updatedAt: nowIso,
    });
    broadcastSync();
    return created;
  }

  public createScheduleItem(input: {
    projectId: string;
    blockId: string;
    title: string;
    scheduledDate?: string;
    durationMinutes?: number;
  }): SharedProjectTrackingRecord {
    const existing = this.repo.getRecordsForProject(input.projectId, {
      blockId: input.blockId,
    });
    const maxSort = existing
      .filter((r) => r.recordType === 'schedule_item')
      .reduce((max, r) => Math.max(max, r.sortOrder), -1);
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const created = this.repo.createRecord({
      id: makeId('sch'),
      projectId: input.projectId,
      blockId: input.blockId,
      recordType: 'schedule_item',
      title: input.title.trim(),
      sortOrder: maxSort + 1,
      ...(input.scheduledDate ? { scheduledDate: input.scheduledDate } : {}),
      ...(input.durationMinutes !== undefined
        ? { durationMinutes: input.durationMinutes }
        : {}),
      isCompleted: false,
      metadata: {},
      createdAt: nowIso,
      updatedAt: nowIso,
    });
    broadcastSync();
    return created;
  }

  public updateRecord(
    record: SharedProjectTrackingRecord
  ): SharedProjectTrackingRecord {
    const updated = this.repo.updateRecord(record);
    broadcastSync();
    return updated;
  }

  public toggleRecordCompleted(
    record: SharedProjectTrackingRecord
  ): SharedProjectTrackingRecord {
    const nextCompleted = !record.isCompleted;
    const updated = this.repo.updateRecord({
      ...record,
      isCompleted: nextCompleted,
      completedAt: nextCompleted
        ? EthiopiaClock.nowUtc().toISOString()
        : undefined,
    });
    broadcastSync();
    return updated;
  }

  public deleteRecord(recordId: string): void {
    this.repo.deleteRecord(recordId);
    broadcastSync();
  }

  public logProgress(input: {
    projectId: string;
    blockId: string;
    parentRecordId?: string;
    deltaValue: number;
    recordedDate: string;
    title?: string;
  }): SharedProjectTrackingRecord {
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const created = this.repo.appendProgressLog({
      id: makeId('log'),
      projectId: input.projectId,
      blockId: input.blockId,
      ...(input.parentRecordId ? { parentRecordId: input.parentRecordId } : {}),
      recordType: 'progress_log',
      ...(input.title?.trim() ? { title: input.title.trim() } : {}),
      sortOrder: 0,
      deltaValue: input.deltaValue,
      isCompleted: false,
      recordedDate: input.recordedDate,
      metadata: {},
      createdAt: nowIso,
      updatedAt: nowIso,
    });

    // Apply explicit ScheduleBlockConfig auto-completion rule if applicable
    if (input.parentRecordId) {
      const blocks = this.repo.getBlocksForProject(input.projectId, {
        includeArchived: true,
      });
      const block = blocks.find((b) => b.id === input.blockId);
      if (block && block.blockType === 'schedule') {
        const cfg = parseScheduleBlockConfig(block.config);
        if (cfg.completionRule !== 'manual') {
          const blockRecords = this.repo.getRecordsForProject(input.projectId, {
            blockId: block.id,
          });
          const item = blockRecords.find(
            (r) => r.id === input.parentRecordId && r.recordType === 'schedule_item'
          );
          if (item && !item.isCompleted) {
            const totalForItem = blockRecords
              .filter(
                (r) =>
                  r.recordType === 'progress_log' &&
                  r.parentRecordId === item.id
              )
              .reduce((sum, r) => sum + (r.deltaValue ?? 0), 0);
            if (
              meetsScheduleDurationRule({
                plannedDurationMinutes: item.durationMinutes,
                actualLoggedMinutes: totalForItem,
                config: cfg,
              })
            ) {
              this.repo.updateRecord({
                ...item,
                isCompleted: true,
                completedAt: nowIso,
              });
            }
          }
        }
      }
    }

    broadcastSync();
    return created;
  }

  public appendProgressCorrection(input: {
    targetLogId: string;
    correctionDelta: number;
    recordedDate: string;
    reason: string;
  }): SharedProjectTrackingRecord {
    const created = this.repo.appendProgressCorrection(input);
    broadcastSync();
    return created;
  }

  public exportProjectPackage(projectId: string): {
    filename: string;
    json: string;
    project: SharedProject;
  } {
    const project = this.repo.getProjectById(projectId);
    if (!project) {
      throw new ProjectPackageError(
        'validation_failed',
        `Cannot export missing project "${projectId}".`
      );
    }
    const json = this.repo.exportProjectPackage(projectId, {
      sourcePlatform: 'web',
    });
    return {
      filename: buildProjectPackageFilename(project.title),
      json,
      project,
    };
  }

  public downloadProjectPackage(projectId: string): {
    filename: string;
    json: string;
    project: SharedProject;
  } {
    const bundle = this.exportProjectPackage(projectId);
    if (typeof window !== 'undefined' && typeof document !== 'undefined') {
      const blob = new Blob([bundle.json], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = bundle.filename;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    }
    return bundle;
  }

  public importProjectPackage(rawJson: string): PreparedProjectPackageImport {
    const imported = this.repo.importProjectPackage(rawJson);
    broadcastSync();
    return imported;
  }

  public formatBlockMetricSummary(metric: ProjectBlockProgressMetric): string {
    const unit = metric.unitLabel ? ` ${metric.unitLabel}` : '';
    const completedTowardTarget =
      metric.targetCompletedTotal ?? metric.loggedTotal;
    const overAmount = metric.overTargetAmount ?? 0;

    switch (metric.blockType) {
      case 'counter': {
        if (metric.targetValue !== undefined && metric.targetValue > 0) {
          const pct = Math.round(metric.progressPercent ?? 0);
          const overNote =
            overAmount > 0
              ? ` (${formatNumber(metric.loggedTotal)} sent, +${formatNumber(
                  overAmount
                )} over)`
              : '';
          return `${formatNumber(completedTowardTarget)} / ${formatNumber(
            metric.targetValue
          )}${unit} (${pct}%)${overNote}`;
        }
        return `${formatNumber(metric.loggedTotal)}${unit} logged`;
      }
      case 'grouped_list': {
        if (metric.targetValue !== undefined && metric.targetValue > 0) {
          const overNote =
            overAmount > 0
              ? ` (${formatNumber(metric.loggedTotal)} sent, +${formatNumber(
                  overAmount
                )} over)`
              : '';
          return `${formatNumber(completedTowardTarget)} / ${formatNumber(
            metric.targetValue
          )}${unit}${overNote} · ${metric.completedCount}/${metric.totalCount} items`;
        }
        return `${metric.completedCount}/${metric.totalCount} items complete`;
      }
      case 'checklist':
        return `${metric.completedCount}/${metric.totalCount} checked`;
      case 'schedule': {
        if (metric.plannedDurationMinutes > 0) {
          return `${metric.actualLoggedDurationMinutes} / ${metric.plannedDurationMinutes} min · ${metric.completedCount}/${metric.totalCount} sessions`;
        }
        return `${metric.completedCount}/${metric.totalCount} sessions`;
      }
    }
  }
}

export function formatNumber(n: number): string {
  if (!Number.isFinite(n)) return '0';
  return Number.isInteger(n) ? String(n) : n.toFixed(1).replace(/\.0$/, '');
}

export const projectsService = new ProjectsService();

export type {
  CounterBlockConfig,
  GroupedListBlockConfig,
  ChecklistBlockConfig,
  ScheduleBlockConfig,
  PreparedProjectPackageImport,
  ProjectScheduleSpan,
};
export {
  BIM_OUTREACH_CAMPAIGN_TITLE,
  buildProjectPackageFilename,
  getProjectScheduleSpan,
  parseCounterBlockConfig,
  parseScheduleBlockConfig,
  ProjectPackageError,
  ProjectValidationError,
  serializeBimOutreachTemplateJson,
};
