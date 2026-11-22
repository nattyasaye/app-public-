import { CalendarDate, EthiopiaClock } from '../domain/date';
import {
  CounterBlockConfig,
  GroupedListBlockConfig,
  ChecklistBlockConfig,
  ScheduleBlockConfig,
  DerivedTaskMilestoneProgress,
  ProjectBlockProgressMetric,
  ProjectProgressSummary,
  ProjectScheduleSpan,
  ProjectValidationError,
  calculateDerivedTaskMilestoneProgress,
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
  SharedDailyPlanningEntry,
  SharedGoal,
  SharedMilestone,
  SharedProject,
  SharedProjectBlockType,
  SharedProjectTrackingBlock,
  SharedProjectTrackingRecord,
  SharedReminder,
  SharedTask,
  SharedTaskRecurrenceConfig,
} from '../domain/sharedFoundation';
import {
  DaywellTaskRecord,
  TaskPriority,
  TaskStatus,
  createTaskRecord,
  deleteTaskFromList,
  isTaskCompleted,
  updateTaskRecord,
} from '../domain/taskOperations';
import {
  removeTaskFromPlannedDay,
  syncTaskCompletionWithDailyPlanning,
} from '../domain/dailyPlanningOperations';
import {
  completeTaskWithRecurrence,
  rescheduleRecurrenceOccurrence,
  resolveEffectiveRecurrenceConfig,
  skipRecurrenceOccurrence,
  stopTaskRecurrence,
} from '../domain/taskRecurrence';
import { WebProjectsRepository } from '../data/projectsRepository';
import {
  buildProjectPackageFilename,
  PreparedProjectPackageImport,
  ProjectPackageError,
} from '../domain/projectPackage';
import { dailyPlanningService } from './dailyPlanningService';
import { SharedStateBridge } from './sharedStateBridge';
import { taskRemindersService } from './taskRemindersService';

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

export interface ProjectSectionGroup {
  record: SharedProjectTrackingRecord;
  tasks: DaywellTaskRecord[];
}

export interface ProjectSectionsViewModel {
  sectionBlockId?: string;
  sections: ProjectSectionGroup[];
  unsectionedTasks: DaywellTaskRecord[];
}

export interface ProjectDetailSnapshot {
  project: SharedProject;
  blocks: SharedProjectTrackingBlock[];
  records: SharedProjectTrackingRecord[];
  summary: ProjectProgressSummary;
  linkedTasks: DaywellTaskRecord[];
  milestones: SharedMilestone[];
  sectionsView: ProjectSectionsViewModel;
  derivedProgress: DerivedTaskMilestoneProgress;
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

function writeLocalArray<T>(key: string, items: T[]): void {
  if (typeof localStorage === 'undefined') return;
  localStorage.setItem(key, JSON.stringify(items));
}

function isTaskRecordDone(
  task: Partial<Pick<SharedTask, 'status'>> & { completed?: boolean }
): boolean {
  return task.completed === true || task.status === 'completed';
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

  public getLinkedTasks(projectId: string): DaywellTaskRecord[] {
    return readLocalArray<DaywellTaskRecord>(TASKS_KEY).filter(
      (t) => t.projectId === projectId
    );
  }

  public listAllMilestones(): SharedMilestone[] {
    return this.repo.getAllMilestones();
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
        includeArchivedTasks: Boolean(proj.isArchived),
      });
    }
    return out;
  }

  public getDerivedTaskMilestoneProgress(
    project: SharedProject,
    summary?: ProjectProgressSummary,
    options: { includeArchivedTasks?: boolean } = {}
  ): DerivedTaskMilestoneProgress {
    const includeArchivedTasks = options.includeArchivedTasks === true;
    const activeLinkedTasks = this.getLinkedTasks(project.id).filter(
      (t) => (includeArchivedTasks || !t.isArchived) && t.status !== 'cancelled'
    );
    const completedTasks = activeLinkedTasks.filter((t) =>
      isTaskRecordDone(t)
    ).length;
    const milestones = this.repo.getMilestonesForProject(project.id);
    const completedMilestones = milestones.filter((m) => m.isCompleted).length;

    return calculateDerivedTaskMilestoneProgress({
      totalTasks: activeLinkedTasks.length,
      completedTasks,
      totalMilestones: milestones.length,
      completedMilestones,
      isProjectManuallyCompleted:
        project.status === 'completed' &&
        (summary?.milestonesTotal ?? milestones.length) === 0 &&
        activeLinkedTasks.length === 0,
    });
  }

  public getProjectDetailSnapshot(
    projectId: string,
    options: { asOfDate?: CalendarDate } = {}
  ): ProjectDetailSnapshot | undefined {
    const project = this.repo.getProjectById(projectId);
    if (!project) return undefined;
    const includeArchivedTasks = Boolean(project.isArchived);
    const blocks = this.repo.getBlocksForProject(projectId, {
      includeArchived: true,
    });
    const records = this.repo.getRecordsForProject(projectId);
    const summary = this.repo.getProjectProgressSummary(projectId, {
      asOfDate: options.asOfDate,
      includeArchivedTasks,
    });
    const linkedTasks = this.getLinkedTasks(projectId);
    const milestones = this.repo.getMilestonesForProject(projectId);
    const sectionsView = this.getProjectSectionsViewModel(projectId, {
      includeArchivedTasks,
    });
    const derivedProgress = this.getDerivedTaskMilestoneProgress(
      project,
      summary,
      { includeArchivedTasks }
    );
    return {
      project,
      blocks,
      records,
      summary,
      linkedTasks,
      milestones,
      sectionsView,
      derivedProgress,
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
  // --- Stage 1.3 Milestones Workflow ---

  public listMilestones(projectId?: string): SharedMilestone[] {
    return projectId
      ? this.repo.getMilestonesForProject(projectId)
      : this.repo.getAllMilestones();
  }

  public createMilestone(input: {
    id?: string;
    projectId: string;
    title: string;
    dueDate?: string;
    isCompleted?: boolean;
  }): SharedMilestone {
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const created = this.repo.createMilestone({
      id: input.id?.trim() || makeId('ms'),
      projectId: input.projectId,
      title: input.title.trim(),
      ...(input.dueDate?.trim() ? { dueDate: input.dueDate.trim() } : {}),
      isCompleted: input.isCompleted === true,
      createdAt: nowIso,
    });
    broadcastSync();
    return created;
  }

  public updateMilestone(input: {
    milestoneId: string;
    title: string;
    dueDate?: string;
    isCompleted?: boolean;
  }): SharedMilestone {
    const existing = this.repo
      .getAllMilestones()
      .find((m) => m.id === input.milestoneId);
    if (!existing) {
      throw new ProjectValidationError(
        `Cannot update missing milestone "${input.milestoneId}".`
      );
    }
    const updated = this.repo.updateMilestone({
      ...existing,
      title: input.title.trim(),
      dueDate: input.dueDate?.trim() || undefined,
      isCompleted:
        input.isCompleted !== undefined
          ? input.isCompleted
          : existing.isCompleted,
    });
    broadcastSync();
    return updated;
  }

  public toggleMilestone(
    milestoneId: string,
    isCompleted?: boolean
  ): SharedMilestone {
    const existing = this.repo
      .getAllMilestones()
      .find((m) => m.id === milestoneId);
    if (!existing) {
      throw new ProjectValidationError(
        `Cannot toggle missing milestone "${milestoneId}".`
      );
    }
    const target =
      isCompleted !== undefined ? isCompleted : !existing.isCompleted;
    const updated = this.repo.toggleMilestone(milestoneId, target);
    broadcastSync();
    return updated;
  }

  public deleteMilestone(milestoneId: string): {
    deleted?: SharedMilestone;
    detachedTaskIds: string[];
  } {
    const result = this.repo.deleteMilestone(milestoneId);
    if (result.deleted) {
      broadcastSync();
    }
    return result;
  }

  public restoreMilestoneSnapshot(
    snapshot: SharedMilestone,
    restoreTaskIds: string[] = []
  ): SharedMilestone {
    const existing = this.repo
      .getAllMilestones()
      .find((m) => m.id === snapshot.id);
    const restored = existing
      ? existing
      : this.repo.createMilestone(snapshot);

    if (restoreTaskIds.length > 0) {
      const idSet = new Set(restoreTaskIds);
      const tasks = readLocalArray<DaywellTaskRecord>(TASKS_KEY);
      let changed = false;
      const nextTasks = tasks.map((t) => {
        if (!idSet.has(t.id) || t.projectId !== snapshot.projectId) return t;
        changed = true;
        return { ...t, milestoneId: restored.id };
      });
      if (changed) {
        writeLocalArray(TASKS_KEY, nextTasks);
      }
    }
    broadcastSync();
    return restored;
  }

  // --- Stage 1.3 Project Sections & Linked Task Organization ---

  public getProjectSectionsViewModel(
    projectId: string,
    options: { includeArchivedTasks?: boolean } = {}
  ): ProjectSectionsViewModel {
    const includeArchivedTasks = options.includeArchivedTasks === true;
    const blocks = this.repo
      .getBlocksForProject(projectId, { includeArchived: false })
      .filter((b) => b.blockType === 'grouped_list');
    const records = this.repo.getRecordsForProject(projectId);
    const activeTasks = this.getLinkedTasks(projectId).filter(
      (t) => (includeArchivedTasks || !t.isArchived) && t.status !== 'cancelled'
    );

    const preferredBlock =
      blocks.find((b) => b.config?.kind === 'task_sections') ??
      blocks.find((b) => b.title.toLowerCase() === 'task sections') ??
      blocks[0];

    const activeGroupedBlockIds = new Set(blocks.map((b) => b.id));
    const groupRecords = records.filter(
      (r) =>
        r.recordType === 'group' && activeGroupedBlockIds.has(r.blockId)
    );
    const groupIdSet = new Set(groupRecords.map((g) => g.id));

    const tasksById = new Map(activeTasks.map((t) => [t.id, t]));
    const taskToGroup = new Map<string, { groupId: string; sortOrder: number }>();

    for (const rec of records) {
      if (
        rec.recordType === 'grouped_item' &&
        activeGroupedBlockIds.has(rec.blockId) &&
        rec.linkedTaskId &&
        rec.parentRecordId &&
        groupIdSet.has(rec.parentRecordId) &&
        tasksById.has(rec.linkedTaskId)
      ) {
        if (!taskToGroup.has(rec.linkedTaskId)) {
          taskToGroup.set(rec.linkedTaskId, {
            groupId: rec.parentRecordId,
            sortOrder: rec.sortOrder,
          });
        }
      }
    }

    const groupedTasksMap = new Map<
      string,
      Array<{ task: DaywellTaskRecord; order: number }>
    >();
    for (const g of groupRecords) {
      groupedTasksMap.set(g.id, []);
    }

    const unsectionedTasks: DaywellTaskRecord[] = [];
    for (const task of activeTasks) {
      const mapping = taskToGroup.get(task.id);
      if (mapping && groupedTasksMap.has(mapping.groupId)) {
        groupedTasksMap.get(mapping.groupId)!.push({
          task,
          order: mapping.sortOrder,
        });
      } else {
        unsectionedTasks.push(task);
      }
    }

    const sections: ProjectSectionGroup[] = groupRecords.map((group) => {
      const entries = (groupedTasksMap.get(group.id) ?? []).slice();
      entries.sort((a, b) => a.order - b.order);
      return {
        record: group,
        tasks: entries.map((e) => e.task),
      };
    });

    return {
      sectionBlockId: preferredBlock?.id,
      sections,
      unsectionedTasks,
    };
  }

  public getProjectSectionTaskIds(
    projectId: string,
    sectionIdOrUnsectioned: string
  ): Set<string> {
    const blocks = this.repo
      .getBlocksForProject(projectId, { includeArchived: false })
      .filter((b) => b.blockType === 'grouped_list');
    const activeBlockIds = new Set(blocks.map((b) => b.id));
    const records = this.repo.getRecordsForProject(projectId);

    if (sectionIdOrUnsectioned === '__unsectioned__') {
      const validGroupIds = new Set(
        records
          .filter(
            (r) => r.recordType === 'group' && activeBlockIds.has(r.blockId)
          )
          .map((g) => g.id)
      );
      const sectionedTaskIds = new Set<string>();
      for (const rec of records) {
        if (
          rec.recordType === 'grouped_item' &&
          activeBlockIds.has(rec.blockId) &&
          rec.linkedTaskId &&
          rec.parentRecordId &&
          validGroupIds.has(rec.parentRecordId)
        ) {
          sectionedTaskIds.add(rec.linkedTaskId);
        }
      }
      const linkedTasks = this.getLinkedTasks(projectId);
      const unsectionedIds = new Set<string>();
      for (const t of linkedTasks) {
        if (!sectionedTaskIds.has(t.id)) {
          unsectionedIds.add(t.id);
        }
      }
      return unsectionedIds;
    }

    const ids = new Set<string>();
    for (const rec of records) {
      if (
        rec.recordType === 'grouped_item' &&
        activeBlockIds.has(rec.blockId) &&
        rec.parentRecordId === sectionIdOrUnsectioned &&
        rec.linkedTaskId
      ) {
        ids.add(rec.linkedTaskId);
      }
    }
    return ids;
  }

  public ensureProjectSectionsBlock(
    projectId: string
  ): SharedProjectTrackingBlock {
    const blocks = this.repo
      .getBlocksForProject(projectId, { includeArchived: false })
      .filter((b) => b.blockType === 'grouped_list');
    const existing =
      blocks.find((b) => b.config?.kind === 'task_sections') ??
      blocks.find((b) => b.title.toLowerCase() === 'task sections') ??
      blocks[0];
    if (existing) return existing;

    return this.createBlock({
      projectId,
      blockType: 'grouped_list',
      title: 'Task Sections',
      config: {
        kind: 'task_sections',
        groupLabel: 'Section',
        itemLabel: 'Task',
        showGroupTotals: false,
        showDailyTotals: false,
      },
    });
  }

  public createProjectSection(
    projectId: string,
    title: string
  ): SharedProjectTrackingRecord {
    const trimmed = title.trim();
    if (!trimmed) {
      throw new ProjectValidationError('Section title is required.');
    }
    const block = this.ensureProjectSectionsBlock(projectId);
    return this.createGroup({
      projectId,
      blockId: block.id,
      title: trimmed,
    });
  }

  public renameProjectSection(
    sectionRecordId: string,
    title: string
  ): SharedProjectTrackingRecord {
    const trimmed = title.trim();
    if (!trimmed) {
      throw new ProjectValidationError('Section title is required.');
    }
    const allRecords = readLocalArray<SharedProjectTrackingRecord>(
      WebProjectsRepository.RECORDS_KEY
    );
    const existing = allRecords.find(
      (r) => r.id === sectionRecordId && r.recordType === 'group'
    );
    if (!existing) {
      throw new ProjectValidationError(
        `Cannot rename missing section "${sectionRecordId}".`
      );
    }
    const updated = this.repo.updateRecord({
      ...existing,
      title: trimmed,
    });
    broadcastSync();
    return updated;
  }

  public deleteProjectSection(
    projectId: string,
    sectionRecordId: string
  ): {
    deletedGroup?: SharedProjectTrackingRecord;
    detachedTaskIds: string[];
  } {
    const records = this.repo.getRecordsForProject(projectId);
    const targetGroup = records.find(
      (r) => r.id === sectionRecordId && r.recordType === 'group'
    );
    if (!targetGroup) {
      return { detachedTaskIds: [] };
    }

    const children = records.filter((r) => r.parentRecordId === sectionRecordId);
    const detachedTaskIds: string[] = [];

    for (const child of children) {
      if (child.linkedTaskId) {
        detachedTaskIds.push(child.linkedTaskId);
      }
      const hasProgressLogs = records.some(
        (r) => r.parentRecordId === child.id && r.recordType === 'progress_log'
      );
      if (hasProgressLogs) {
        const nextChild: SharedProjectTrackingRecord = { ...child };
        delete nextChild.parentRecordId;
        delete nextChild.linkedTaskId;
        this.repo.updateRecord(nextChild);
      } else {
        this.repo.deleteRecord(child.id);
      }
    }

    this.repo.deleteRecord(sectionRecordId);
    broadcastSync();
    return { deletedGroup: targetGroup, detachedTaskIds };
  }

  public restoreProjectSection(
    projectId: string,
    deletedGroup: SharedProjectTrackingRecord,
    detachedTaskIds: string[] = []
  ): SharedProjectTrackingRecord {
    const existingBlock = this.repo
      .getBlocksForProject(projectId, { includeArchived: true })
      .find((b) => b.id === deletedGroup.blockId);
    const block = existingBlock ?? this.ensureProjectSectionsBlock(projectId);
    const records = this.repo.getRecordsForProject(projectId, { blockId: block.id });
    const existingGroup = records.find((r) => r.id === deletedGroup.id);
    const restoredGroup =
      existingGroup ??
      this.repo.createRecord({
        ...deletedGroup,
        blockId: block.id,
        projectId,
      });

    for (const taskId of detachedTaskIds) {
      this.assignTaskToProjectSection(projectId, taskId, restoredGroup.id);
    }
    broadcastSync();
    return restoredGroup;
  }

  private detachTaskSectionLinks(
    projectId: string,
    taskId: string
  ): string | undefined {
    const records = this.repo.getRecordsForProject(projectId);
    let previousSectionId: string | undefined;
    for (const rec of records) {
      if (rec.linkedTaskId !== taskId) continue;
      if (rec.parentRecordId && !previousSectionId) {
        previousSectionId = rec.parentRecordId;
      }
      const hasProgressLogs = records.some(
        (r) => r.parentRecordId === rec.id && r.recordType === 'progress_log'
      );
      if (hasProgressLogs || rec.recordType !== 'grouped_item') {
        const updated = { ...rec };
        delete updated.linkedTaskId;
        this.repo.updateRecord(updated);
      } else {
        this.repo.deleteRecord(rec.id);
      }
    }
    return previousSectionId;
  }

  public cleanupSectionLinksForTask(taskId: string): void {
    const allRecords = readLocalArray<SharedProjectTrackingRecord>(
      WebProjectsRepository.RECORDS_KEY
    );
    const affectedProjects = new Set<string>();
    for (const rec of allRecords) {
      if (rec.linkedTaskId === taskId) {
        affectedProjects.add(rec.projectId);
      }
    }
    for (const projectId of affectedProjects) {
      this.detachTaskSectionLinks(projectId, taskId);
    }
    if (affectedProjects.size > 0) {
      broadcastSync();
    }
  }

  public assignTaskToProjectSection(
    projectId: string,
    taskId: string,
    sectionRecordId?: string | null
  ): void {
    this.detachTaskSectionLinks(projectId, taskId);

    const trimmedSectionId = sectionRecordId?.trim() || undefined;
    if (!trimmedSectionId) {
      broadcastSync();
      return;
    }

    const records = this.repo.getRecordsForProject(projectId);
    const section = records.find(
      (r) => r.id === trimmedSectionId && r.recordType === 'group'
    );
    if (!section) {
      throw new ProjectValidationError(
        `Cannot assign task to missing section "${trimmedSectionId}".`
      );
    }
    const task = readLocalArray<DaywellTaskRecord>(TASKS_KEY).find(
      (t) => t.id === taskId && t.projectId === projectId
    );
    if (!task) {
      throw new ProjectValidationError(
        `Cannot assign missing task "${taskId}" to section.`
      );
    }

    const maxSort = records
      .filter(
        (r) =>
          r.blockId === section.blockId &&
          r.recordType === 'grouped_item' &&
          r.parentRecordId === section.id
      )
      .reduce((max, r) => Math.max(max, r.sortOrder), -1);

    const nowIso = EthiopiaClock.nowUtc().toISOString();
    this.repo.createRecord({
      id: makeId('seclink'),
      projectId,
      blockId: section.blockId,
      parentRecordId: section.id,
      recordType: 'grouped_item',
      title: task.title,
      sortOrder: maxSort + 1,
      isCompleted: isTaskRecordDone(task),
      linkedTaskId: task.id,
      metadata: { kind: 'task_section_link' },
      createdAt: nowIso,
      updatedAt: nowIso,
    });
    broadcastSync();
  }

  private syncLinkedSectionRecordForTask(task: DaywellTaskRecord): void {
    if (!task.projectId) return;
    const records = this.repo.getRecordsForProject(task.projectId);
    for (const rec of records) {
      if (rec.linkedTaskId !== task.id) continue;
      if (
        rec.title !== task.title ||
        rec.isCompleted !== isTaskRecordDone(task)
      ) {
        this.repo.updateRecord({
          ...rec,
          title: task.title,
          isCompleted: isTaskRecordDone(task),
          completedAt: isTaskRecordDone(task)
            ? rec.completedAt ?? EthiopiaClock.nowUtc().toISOString()
            : undefined,
        });
      }
    }
  }

  public copyTaskSectionLink(
    projectId: string,
    fromTaskId: string,
    nextTask: DaywellTaskRecord
  ): void {
    const cleanProjectId = projectId.trim();
    if (!cleanProjectId || nextTask.projectId !== cleanProjectId) return;
    const records = this.repo.getRecordsForProject(cleanProjectId);
    const existingLink = records.find(
      (r) =>
        r.linkedTaskId === fromTaskId &&
        r.recordType === 'grouped_item' &&
        Boolean(r.parentRecordId)
    );
    if (!existingLink?.parentRecordId) return;
    const alreadyLinked = records.some(
      (r) => r.linkedTaskId === nextTask.id && r.recordType === 'grouped_item'
    );
    if (alreadyLinked) return;
    this.assignTaskToProjectSection(
      cleanProjectId,
      nextTask.id,
      existingLink.parentRecordId
    );
  }

  public createTaskInProject(input: {
    projectId: string;
    title: string;
    description?: string;
    priority?: TaskPriority;
    status?: TaskStatus;
    dueDate?: string;
    scheduledDate?: string;
    scheduledTime?: string;
    milestoneId?: string;
    sectionId?: string;
    recurrenceConfig?: SharedTaskRecurrenceConfig;
    reminderTriggerUtc?: string;
  }): DaywellTaskRecord {
    const project = this.repo.getProjectById(input.projectId);
    if (!project) {
      throw new ProjectValidationError(
        `Cannot create task in missing project "${input.projectId}".`
      );
    }
    const result = createTaskRecord({
      title: input.title,
      description: input.description,
      priority: input.priority,
      status: input.status,
      dueDate: input.dueDate,
      scheduledDate: input.scheduledDate,
      scheduledTime: input.scheduledTime,
      hasReminder: Boolean(input.reminderTriggerUtc),
      projectId: project.id,
      milestoneId: input.milestoneId,
      projectName: project.title,
      category: project.title,
      recurrenceConfig: input.recurrenceConfig,
    });
    if (!result.ok) {
      const firstErr = Object.values(result.errors)[0] ?? 'Invalid task fields.';
      throw new ProjectValidationError(firstErr);
    }
    const existingTasks = readLocalArray<DaywellTaskRecord>(TASKS_KEY);
    writeLocalArray(TASKS_KEY, [result.task, ...existingTasks]);

    if (input.reminderTriggerUtc) {
      taskRemindersService.setTaskReminder(result.task, input.reminderTriggerUtc, {
        emitSync: false,
        syncTaskHasReminder: true,
      });
    }

    if (input.sectionId?.trim()) {
      this.assignTaskToProjectSection(
        project.id,
        result.task.id,
        input.sectionId.trim()
      );
    } else {
      broadcastSync();
    }
    return result.task;
  }

  public updateTaskInProject(
    taskId: string,
    patch: {
      title?: string;
      description?: string;
      priority?: TaskPriority;
      status?: TaskStatus;
      dueDate?: string;
      scheduledDate?: string;
      scheduledTime?: string;
      projectId?: string;
      milestoneId?: string;
      sectionId?: string | null;
      recurrenceConfig?: SharedTaskRecurrenceConfig;
      clearRecurrenceConfig?: boolean;
      reminderTriggerUtc?: string;
      clearReminder?: boolean;
    }
  ): DaywellTaskRecord | undefined {
    return this.updateTaskInProjectWithRecurrence(taskId, patch).updated;
  }

  public updateTaskInProjectWithRecurrence(
    taskId: string,
    patch: {
      title?: string;
      description?: string;
      priority?: TaskPriority;
      status?: TaskStatus;
      dueDate?: string;
      scheduledDate?: string;
      scheduledTime?: string;
      projectId?: string;
      milestoneId?: string;
      sectionId?: string | null;
      recurrenceConfig?: SharedTaskRecurrenceConfig;
      clearRecurrenceConfig?: boolean;
      reminderTriggerUtc?: string;
      clearReminder?: boolean;
    }
  ): {
    previousTasks: DaywellTaskRecord[];
    previousEntries: SharedDailyPlanningEntry[];
    previousReminders: SharedReminder[];
    updated?: DaywellTaskRecord;
    generatedNextTask?: DaywellTaskRecord;
    seriesEnded: boolean;
    duplicatePrevented: boolean;
  } {
    const previousTasks = readLocalArray<DaywellTaskRecord>(TASKS_KEY);
    const previousEntries = dailyPlanningService.loadDailyPlanningEntries();
    const previousReminders = taskRemindersService.loadAllReminders();
    const existing = previousTasks.find((t) => t.id === taskId);
    if (!existing) {
      return {
        previousTasks,
        previousEntries,
        previousReminders,
        seriesEnded: false,
        duplicatePrevented: false,
      };
    }

    const targetProjectId =
      patch.projectId !== undefined ? patch.projectId : existing.projectId;
    const targetProject = targetProjectId
      ? this.repo.getProjectById(targetProjectId)
      : undefined;

    const res = updateTaskRecord(existing, {
      ...(patch.title !== undefined ? { title: patch.title } : {}),
      ...(patch.description !== undefined
        ? { description: patch.description }
        : {}),
      ...(patch.priority !== undefined ? { priority: patch.priority } : {}),
      ...(patch.status !== undefined ? { status: patch.status } : {}),
      ...(patch.dueDate !== undefined ? { dueDate: patch.dueDate } : {}),
      ...(patch.scheduledDate !== undefined
        ? { scheduledDate: patch.scheduledDate }
        : {}),
      ...(patch.scheduledTime !== undefined
        ? { scheduledTime: patch.scheduledTime }
        : {}),
      ...(patch.projectId !== undefined
        ? {
            projectId: patch.projectId || undefined,
            projectName: targetProject?.title ?? 'Personal',
            category: targetProject?.title ?? 'Personal',
          }
        : {}),
      ...(patch.milestoneId !== undefined
        ? { milestoneId: patch.milestoneId || undefined }
        : {}),
      ...(patch.recurrenceConfig !== undefined
        ? { recurrenceConfig: patch.recurrenceConfig }
        : {}),
      ...(patch.clearRecurrenceConfig === true
        ? { isRecurring: false, clearRecurrenceConfig: true }
        : {}),
      ...(patch.clearReminder === true
        ? { hasReminder: false }
        : patch.reminderTriggerUtc !== undefined
        ? { hasReminder: true }
        : {}),
    });

    if (!res.ok) {
      const firstErr = Object.values(res.errors)[0] ?? 'Invalid task fields.';
      throw new ProjectValidationError(firstErr);
    }

    let finalTasks = previousTasks.map((t) =>
      t.id === taskId ? res.task : t
    );
    let finalUpdated = res.task;
    let generatedNextTask: DaywellTaskRecord | undefined;
    let seriesEnded = false;
    let duplicatePrevented = false;

    const wasCompleted = isTaskCompleted(existing);
    const isNowCompleted = isTaskCompleted(res.task);
    const transitionedToCompleted = !wasCompleted && isNowCompleted;

    if (
      transitionedToCompleted &&
      resolveEffectiveRecurrenceConfig(res.task)
    ) {
      const tempOpen: DaywellTaskRecord = {
        ...res.task,
        status: 'not_started',
        completed: false,
        completedAt: undefined,
      };
      const recRes = completeTaskWithRecurrence(
        previousTasks.map((t) => (t.id === taskId ? tempOpen : t)),
        taskId
      );
      if (recRes.updatedTask) {
        finalTasks = recRes.tasks;
        finalUpdated = recRes.updatedTask;
        generatedNextTask = recRes.generatedNextTask;
        seriesEnded = recRes.seriesEnded;
        duplicatePrevented = recRes.duplicatePrevented;
      }
    }

    writeLocalArray(TASKS_KEY, finalTasks);

    if (patch.clearReminder === true) {
      taskRemindersService.removeTaskReminder(taskId, {
        emitSync: false,
        syncTaskHasReminder: true,
      });
    } else if (patch.reminderTriggerUtc) {
      taskRemindersService.setTaskReminder(
        finalUpdated,
        patch.reminderTriggerUtc,
        { emitSync: false, syncTaskHasReminder: true }
      );
    }

    const reconciled = taskRemindersService.reconcileAndPersistForTasks({
      tasks: readLocalArray<DaywellTaskRecord>(TASKS_KEY),
      previousTasks,
      generatedFromTaskId: generatedNextTask ? taskId : undefined,
      generatedNextTask,
      persistTasks: true,
      emitSync: false,
    });
    finalTasks = reconciled.tasks;
    finalUpdated = finalTasks.find((t) => t.id === taskId) ?? finalUpdated;
    if (generatedNextTask) {
      generatedNextTask =
        finalTasks.find((t) => t.id === generatedNextTask!.id) ??
        generatedNextTask;
    }

    if (wasCompleted !== isNowCompleted) {
      const nextEntries = syncTaskCompletionWithDailyPlanning(
        finalTasks,
        previousEntries,
        taskId,
        isNowCompleted
      );
      dailyPlanningService.saveDailyPlanningEntries(nextEntries);
    }

    if (
      existing.projectId &&
      existing.projectId !== finalUpdated.projectId
    ) {
      this.detachTaskSectionLinks(existing.projectId, taskId);
    }

    if (finalUpdated.projectId && patch.sectionId !== undefined) {
      this.assignTaskToProjectSection(
        finalUpdated.projectId,
        finalUpdated.id,
        patch.sectionId
      );
    } else {
      this.syncLinkedSectionRecordForTask(finalUpdated);
    }

    if (generatedNextTask?.projectId) {
      this.copyTaskSectionLink(
        generatedNextTask.projectId,
        taskId,
        generatedNextTask
      );
    }

    broadcastSync();

    return {
      previousTasks,
      previousEntries,
      previousReminders,
      updated: finalUpdated,
      generatedNextTask,
      seriesEnded,
      duplicatePrevented,
    };
  }

  public skipTaskRecurrenceInProject(taskId: string): {
    ok: boolean;
    error?: string;
    previousTasks: DaywellTaskRecord[];
    previousEntries: SharedDailyPlanningEntry[];
    previousReminders: SharedReminder[];
    updated?: DaywellTaskRecord;
  } {
    const previousTasks = readLocalArray<DaywellTaskRecord>(TASKS_KEY);
    const previousEntries = dailyPlanningService.loadDailyPlanningEntries();
    const previousReminders = taskRemindersService.loadAllReminders();
    const existing = previousTasks.find((t) => t.id === taskId);
    const res = skipRecurrenceOccurrence(previousTasks, taskId);
    if (!res.ok || !res.updatedTask) {
      return {
        ok: false,
        error: res.error ?? 'Unable to skip occurrence.',
        previousTasks,
        previousEntries,
        previousReminders,
      };
    }

    const reconciled = taskRemindersService.reconcileAndPersistForTasks({
      tasks: res.tasks,
      previousTasks,
      shiftCustomOnDateShift: true,
      persistTasks: true,
      emitSync: false,
    });
    const finalUpdated =
      reconciled.tasks.find((t) => t.id === taskId) ?? res.updatedTask;
    if (
      finalUpdated.isMyDay === false &&
      previousEntries.some((e) => e.taskId === taskId)
    ) {
      const targetPlanDate =
        existing?.myDayDate ?? CalendarDate.today().toIsoString();
      const nextEntries = removeTaskFromPlannedDay(
        reconciled.tasks,
        previousEntries,
        taskId,
        targetPlanDate
      ).entries;
      dailyPlanningService.saveDailyPlanningEntries(nextEntries);
    }
    this.syncLinkedSectionRecordForTask(finalUpdated);
    broadcastSync();
    return {
      ok: true,
      previousTasks,
      previousEntries,
      previousReminders,
      updated: finalUpdated,
    };
  }

  public rescheduleTaskOccurrenceInProject(
    taskId: string,
    newDateIso: string
  ): {
    ok: boolean;
    error?: string;
    previousTasks: DaywellTaskRecord[];
    previousEntries: SharedDailyPlanningEntry[];
    previousReminders: SharedReminder[];
    updated?: DaywellTaskRecord;
  } {
    const previousTasks = readLocalArray<DaywellTaskRecord>(TASKS_KEY);
    const previousEntries = dailyPlanningService.loadDailyPlanningEntries();
    const previousReminders = taskRemindersService.loadAllReminders();
    const res = rescheduleRecurrenceOccurrence(
      previousTasks,
      taskId,
      newDateIso
    );
    if (!res.ok || !res.updatedTask) {
      return {
        ok: false,
        error: res.error ?? 'Unable to reschedule occurrence.',
        previousTasks,
        previousEntries,
        previousReminders,
      };
    }

    const reconciled = taskRemindersService.reconcileAndPersistForTasks({
      tasks: res.tasks,
      previousTasks,
      shiftCustomOnDateShift: true,
      persistTasks: true,
      emitSync: false,
    });
    const finalUpdated =
      reconciled.tasks.find((t) => t.id === taskId) ?? res.updatedTask;
    this.syncLinkedSectionRecordForTask(finalUpdated);
    broadcastSync();
    return {
      ok: true,
      previousTasks,
      previousEntries,
      previousReminders,
      updated: finalUpdated,
    };
  }

  public stopTaskRecurrenceInProject(taskId: string): {
    ok: boolean;
    error?: string;
    previousTasks: DaywellTaskRecord[];
    previousEntries: SharedDailyPlanningEntry[];
    previousReminders: SharedReminder[];
    updated?: DaywellTaskRecord;
  } {
    const previousTasks = readLocalArray<DaywellTaskRecord>(TASKS_KEY);
    const previousEntries = dailyPlanningService.loadDailyPlanningEntries();
    const previousReminders = taskRemindersService.loadAllReminders();
    const res = stopTaskRecurrence(previousTasks, taskId);
    if (!res.ok || !res.updatedTask) {
      return {
        ok: false,
        error: res.error ?? 'Unable to stop recurrence.',
        previousTasks,
        previousEntries,
        previousReminders,
      };
    }

    const reconciled = taskRemindersService.reconcileAndPersistForTasks({
      tasks: res.tasks,
      previousTasks,
      persistTasks: true,
      emitSync: false,
    });
    const finalUpdated =
      reconciled.tasks.find((t) => t.id === taskId) ?? res.updatedTask;
    this.syncLinkedSectionRecordForTask(finalUpdated);
    broadcastSync();
    return {
      ok: true,
      previousTasks,
      previousEntries,
      previousReminders,
      updated: finalUpdated,
    };
  }

  public toggleTaskCompletionInProject(taskId: string): {
    previousTasks: DaywellTaskRecord[];
    previousReminders: SharedReminder[];
    updated?: DaywellTaskRecord;
    generatedNextTask?: DaywellTaskRecord;
    seriesEnded: boolean;
    duplicatePrevented: boolean;
  } {
    const previousTasks = readLocalArray<DaywellTaskRecord>(TASKS_KEY);
    const previousReminders = taskRemindersService.loadAllReminders();
    const result = completeTaskWithRecurrence(previousTasks, taskId);
    if (!result.updatedTask) {
      return {
        previousTasks,
        previousReminders,
        seriesEnded: false,
        duplicatePrevented: false,
      };
    }

    const reconciled = taskRemindersService.reconcileAndPersistForTasks({
      tasks: result.tasks,
      previousTasks,
      generatedFromTaskId: result.generatedNextTask ? taskId : undefined,
      generatedNextTask: result.generatedNextTask,
      persistTasks: true,
      emitSync: false,
    });

    const finalUpdated =
      reconciled.tasks.find((t) => t.id === taskId) ?? result.updatedTask;
    const finalGeneratedNextTask = result.generatedNextTask
      ? reconciled.tasks.find((t) => t.id === result.generatedNextTask!.id) ??
        result.generatedNextTask
      : undefined;

    const currentEntries = dailyPlanningService.loadDailyPlanningEntries();
    const nextEntries = syncTaskCompletionWithDailyPlanning(
      reconciled.tasks,
      currentEntries,
      taskId,
      isTaskCompleted(finalUpdated)
    );
    dailyPlanningService.saveDailyPlanningEntries(nextEntries);
    this.syncLinkedSectionRecordForTask(finalUpdated);
    if (finalGeneratedNextTask?.projectId) {
      this.copyTaskSectionLink(
        finalGeneratedNextTask.projectId,
        taskId,
        finalGeneratedNextTask
      );
    }
    broadcastSync();
    return {
      previousTasks,
      previousReminders,
      updated: finalUpdated,
      generatedNextTask: finalGeneratedNextTask,
      seriesEnded: result.seriesEnded,
      duplicatePrevented: result.duplicatePrevented,
    };
  }

  public deleteTaskInProject(taskId: string): {
    previousTasks: DaywellTaskRecord[];
    previousReminders: SharedReminder[];
    deleted?: DaywellTaskRecord;
    previousSection?: { projectId: string; sectionId: string };
  } {
    const previousTasks = readLocalArray<DaywellTaskRecord>(TASKS_KEY);
    const previousReminders = taskRemindersService.loadAllReminders();
    const { remaining, deleted } = deleteTaskFromList(previousTasks, taskId);
    let previousSection: { projectId: string; sectionId: string } | undefined;

    if (deleted?.projectId) {
      const sectionId = this.detachTaskSectionLinks(deleted.projectId, taskId);
      if (sectionId) {
        previousSection = { projectId: deleted.projectId, sectionId };
      }
    } else {
      this.cleanupSectionLinksForTask(taskId);
    }

    writeLocalArray(TASKS_KEY, remaining);
    taskRemindersService.removeTaskReminder(taskId, {
      emitSync: false,
      syncTaskHasReminder: false,
    });
    SharedStateBridge.removeDailyPlanningForTask(taskId);
    broadcastSync();
    return { previousTasks, previousReminders, deleted, previousSection };
  }

  public restoreTasksSnapshot(
    tasksSnapshot: DaywellTaskRecord[],
    sectionRestore?: { projectId: string; taskId: string; sectionId: string },
    removeLinksForTaskId?: string,
    dailyPlanningSnapshot?: SharedDailyPlanningEntry[],
    remindersSnapshot?: SharedReminder[]
  ): void {
    if (removeLinksForTaskId) {
      this.cleanupSectionLinksForTask(removeLinksForTaskId);
    }
    writeLocalArray(TASKS_KEY, tasksSnapshot);
    if (remindersSnapshot !== undefined) {
      taskRemindersService.restoreRemindersSnapshot(remindersSnapshot, {
        tasks: tasksSnapshot,
        emitSync: false,
      });
    }
    if (dailyPlanningSnapshot) {
      dailyPlanningService.saveDailyPlanningEntries(dailyPlanningSnapshot);
    }
    if (sectionRestore) {
      const records = this.repo.getRecordsForProject(sectionRestore.projectId);
      const sectionExists = records.some(
        (r) => r.id === sectionRestore.sectionId && r.recordType === 'group'
      );
      if (sectionExists) {
        this.assignTaskToProjectSection(
          sectionRestore.projectId,
          sectionRestore.taskId,
          sectionRestore.sectionId
        );
        return;
      }
    }
    for (const t of tasksSnapshot) {
      this.syncLinkedSectionRecordForTask(t);
    }
    broadcastSync();
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
  DerivedTaskMilestoneProgress,
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
