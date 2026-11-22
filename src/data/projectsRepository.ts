import {
  SharedGoal,
  SharedMilestone,
  SharedProject,
  SharedProjectTrackingBlock,
  SharedProjectTrackingRecord,
  SharedTask,
} from '../domain/sharedFoundation';
import { CalendarDate, EthiopiaClock } from '../domain/date';
import {
  assertAppendOnlyLogProtection,
  calculateProjectProgressSummary,
  ProjectMilestoneInput,
  ProjectProgressSummary,
  ProjectValidationError,
  validateBlock,
  validateMilestone,
  validateProject,
  validateRecord,
} from '../domain/projectsEngine';
import {
  PreparedProjectPackageImport,
  prepareProjectPackageForImport,
  ProjectPackageError,
  serializeProjectPackage,
} from '../domain/projectPackage';

export interface IWebProjectsRepository {
  getProjects(options?: {
    status?: SharedProject['status'];
    includeArchived?: boolean;
  }): SharedProject[];
  getProjectById(id: string): SharedProject | undefined;
  createProject(project: SharedProject): SharedProject;
  updateProject(project: SharedProject): SharedProject;
  setProjectArchived(projectId: string, isArchived: boolean): SharedProject;
  deleteProject(projectId: string): void;

  getBlocksForProject(
    projectId: string,
    options?: { includeArchived?: boolean }
  ): SharedProjectTrackingBlock[];
  createBlock(block: SharedProjectTrackingBlock): SharedProjectTrackingBlock;
  updateBlock(block: SharedProjectTrackingBlock): SharedProjectTrackingBlock;
  setBlockArchived(blockId: string, isArchived: boolean): SharedProjectTrackingBlock;
  deleteBlock(blockId: string): void;

  getRecordsForProject(
    projectId: string,
    options?: { blockId?: string }
  ): SharedProjectTrackingRecord[];
  createRecord(record: SharedProjectTrackingRecord): SharedProjectTrackingRecord;
  updateRecord(record: SharedProjectTrackingRecord): SharedProjectTrackingRecord;
  appendProgressLog(
    logRecord: SharedProjectTrackingRecord
  ): SharedProjectTrackingRecord;
  appendProgressCorrection(params: {
    targetLogId: string;
    correctionDelta: number;
    recordedDate: string;
    reason: string;
    correctionId?: string;
  }): SharedProjectTrackingRecord;
  deleteRecord(recordId: string): void;

  getProjectProgressSummary(
    projectId: string,
    options?: { asOfDate?: CalendarDate }
  ): ProjectProgressSummary;

  exportProjectPackage(
    projectId: string,
    options?: { exportedAt?: string; sourcePlatform?: 'web' | 'android' }
  ): string;

  importProjectPackage(rawJson: string): PreparedProjectPackageImport;

  getAllMilestones(): SharedMilestone[];
  getMilestonesForProject(projectId: string): SharedMilestone[];
  createMilestone(milestone: SharedMilestone): SharedMilestone;
  updateMilestone(milestone: SharedMilestone): SharedMilestone;
  toggleMilestone(milestoneId: string, isCompleted: boolean): SharedMilestone;
  deleteMilestone(milestoneId: string): {
    deleted?: SharedMilestone;
    detachedTaskIds: string[];
  };
}

/**
 * Offline-first Web Preview repository for Stage 1 Projects, tracking blocks,
 * and append-only progress records backed by browser localStorage.
 */
export class WebProjectsRepository implements IWebProjectsRepository {
  public static readonly PROJECTS_KEY = 'daywell_projects';
  public static readonly BLOCKS_KEY = 'daywell_project_tracking_blocks';
  public static readonly RECORDS_KEY = 'daywell_project_tracking_records';
  public static readonly MILESTONES_KEY = 'daywell_milestones';
  private static readonly GOALS_KEY = 'daywell_goals';
  private static readonly TASKS_KEY = 'daywell_tasks';

  private readArray<T>(key: string): T[] {
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

  private writeArray<T>(key: string, items: T[]): void {
    if (typeof localStorage === 'undefined') return;
    localStorage.setItem(key, JSON.stringify(items));
  }

  private ensureGoalExists(goalId?: string): void {
    const trimmed = goalId?.trim();
    if (!trimmed) return;
    const goals = this.readArray<SharedGoal>(WebProjectsRepository.GOALS_KEY);
    if (!goals.some((g) => g.id === trimmed)) {
      throw new ProjectValidationError(
        `Cannot link project to missing goal "${trimmed}".`
      );
    }
  }

  private ensureTaskExists(linkedTaskId?: string): void {
    const trimmed = linkedTaskId?.trim();
    if (!trimmed) return;
    const tasks = this.readArray<SharedTask>(WebProjectsRepository.TASKS_KEY);
    if (!tasks.some((t) => t.id === trimmed)) {
      throw new ProjectValidationError(
        `Cannot link tracking record to missing task "${trimmed}".`
      );
    }
  }

  public getProjects(
    options: { status?: SharedProject['status']; includeArchived?: boolean } = {}
  ): SharedProject[] {
    const { status, includeArchived = true } = options;
    return this.readArray<SharedProject>(WebProjectsRepository.PROJECTS_KEY)
      .filter((p) => {
        if (status && p.status !== status) return false;
        if (!includeArchived && p.isArchived === true) return false;
        return true;
      })
      .sort((a, b) => (b.createdAt ?? '').localeCompare(a.createdAt ?? ''));
  }

  public getProjectById(id: string): SharedProject | undefined {
    return this.readArray<SharedProject>(WebProjectsRepository.PROJECTS_KEY).find(
      (p) => p.id === id
    );
  }

  public createProject(project: SharedProject): SharedProject {
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const cleanGoalId = project.goalId?.trim() || undefined;
    const normalized: SharedProject = {
      ...project,
      title: (project.title ?? '').trim(),
      ...(project.description !== undefined
        ? { description: project.description.trim() }
        : {}),
      status: project.status ?? 'active',
      ...(cleanGoalId !== undefined ? { goalId: cleanGoalId } : {}),
      isArchived: project.isArchived === true,
      customFields: project.customFields ?? {},
      createdAt: project.createdAt ?? nowIso,
      updatedAt: project.updatedAt ?? project.createdAt ?? nowIso,
    };
    if (cleanGoalId === undefined) delete normalized.goalId;

    validateProject(normalized);
    const all = this.readArray<SharedProject>(WebProjectsRepository.PROJECTS_KEY);
    if (all.some((p) => p.id === normalized.id)) {
      throw new ProjectValidationError(
        `Duplicate project id "${normalized.id}".`
      );
    }
    this.ensureGoalExists(normalized.goalId);
    all.unshift(normalized);
    this.writeArray(WebProjectsRepository.PROJECTS_KEY, all);
    return normalized;
  }

  public updateProject(project: SharedProject): SharedProject {
    const cleanGoalId = project.goalId?.trim() || undefined;
    const updated: SharedProject = {
      ...project,
      title: (project.title ?? '').trim(),
      ...(project.description !== undefined
        ? { description: project.description.trim() }
        : {}),
      ...(cleanGoalId !== undefined ? { goalId: cleanGoalId } : {}),
      isArchived: project.isArchived === true,
      customFields: project.customFields ?? {},
      updatedAt: EthiopiaClock.nowUtc().toISOString(),
    };
    if (cleanGoalId === undefined) delete updated.goalId;

    validateProject(updated);
    const all = this.readArray<SharedProject>(WebProjectsRepository.PROJECTS_KEY);
    const idx = all.findIndex((p) => p.id === updated.id);
    if (idx === -1) {
      throw new ProjectValidationError(
        `Cannot update missing project "${updated.id}".`
      );
    }
    this.ensureGoalExists(updated.goalId);
    all[idx] = {
      ...updated,
      createdAt: all[idx].createdAt ?? updated.createdAt,
    };
    this.writeArray(WebProjectsRepository.PROJECTS_KEY, all);
    return all[idx];
  }

  public setProjectArchived(projectId: string, isArchived: boolean): SharedProject {
    const all = this.readArray<SharedProject>(WebProjectsRepository.PROJECTS_KEY);
    const idx = all.findIndex((p) => p.id === projectId);
    if (idx === -1) {
      throw new ProjectValidationError(
        `Cannot archive missing project "${projectId}".`
      );
    }
    all[idx] = {
      ...all[idx],
      isArchived,
      updatedAt: EthiopiaClock.nowUtc().toISOString(),
    };
    this.writeArray(WebProjectsRepository.PROJECTS_KEY, all);
    return all[idx];
  }

  public deleteProject(projectId: string): void {
    // 1. Detach tasks safely (SET NULL parity with SQLite Tasks.projectId FK)
    if (typeof localStorage !== 'undefined' && localStorage.getItem(WebProjectsRepository.TASKS_KEY) !== null) {
      const tasks = this.readArray<SharedTask>(WebProjectsRepository.TASKS_KEY);
      const nextTasks = tasks.map((t) => {
        if (t.projectId !== projectId) return t;
        const copy = { ...t };
        delete copy.projectId;
        delete copy.milestoneId;
        return copy;
      });
      this.writeArray(WebProjectsRepository.TASKS_KEY, nextTasks);
    }

    // 2. Delete project tracking records, blocks, milestones, and project
    const records = this.readArray<SharedProjectTrackingRecord>(
      WebProjectsRepository.RECORDS_KEY
    ).filter((r) => r.projectId !== projectId);
    this.writeArray(WebProjectsRepository.RECORDS_KEY, records);

    const blocks = this.readArray<SharedProjectTrackingBlock>(
      WebProjectsRepository.BLOCKS_KEY
    ).filter((b) => b.projectId !== projectId);
    this.writeArray(WebProjectsRepository.BLOCKS_KEY, blocks);

    if (
      typeof localStorage !== 'undefined' &&
      localStorage.getItem(WebProjectsRepository.MILESTONES_KEY) !== null
    ) {
      const milestones = this.readArray<ProjectMilestoneInput>(
        WebProjectsRepository.MILESTONES_KEY
      ).filter((m) => m.projectId !== projectId);
      this.writeArray(WebProjectsRepository.MILESTONES_KEY, milestones);
    }

    const projects = this.readArray<SharedProject>(
      WebProjectsRepository.PROJECTS_KEY
    ).filter((p) => p.id !== projectId);
    this.writeArray(WebProjectsRepository.PROJECTS_KEY, projects);
  }

  public getBlocksForProject(
    projectId: string,
    options: { includeArchived?: boolean } = {}
  ): SharedProjectTrackingBlock[] {
    const { includeArchived = true } = options;
    return this.readArray<SharedProjectTrackingBlock>(WebProjectsRepository.BLOCKS_KEY)
      .filter((b) => {
        if (b.projectId !== projectId) return false;
        if (!includeArchived && b.isArchived) return false;
        return true;
      })
      .sort((a, b) => {
        if (a.sortOrder !== b.sortOrder) return a.sortOrder - b.sortOrder;
        return a.createdAt.localeCompare(b.createdAt);
      });
  }

  public createBlock(block: SharedProjectTrackingBlock): SharedProjectTrackingBlock {
    const project = this.getProjectById(block.projectId);
    if (!project) {
      throw new ProjectValidationError(
        `Cannot create block "${block.id}": missing project "${block.projectId}".`
      );
    }
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const normalized: SharedProjectTrackingBlock = {
      ...block,
      title: (block.title ?? '').trim(),
      sortOrder: block.sortOrder ?? 0,
      ...(block.unitLabel !== undefined && block.unitLabel !== null
        ? { unitLabel: block.unitLabel.trim() }
        : {}),
      config: block.config ?? {},
      isArchived: block.isArchived === true,
      createdAt: block.createdAt ?? nowIso,
      updatedAt: block.updatedAt ?? block.createdAt ?? nowIso,
    };

    const allBlocks = this.readArray<SharedProjectTrackingBlock>(
      WebProjectsRepository.BLOCKS_KEY
    );
    const siblingBlocks = allBlocks.filter((b) => b.projectId === project.id);
    validateBlock(normalized, {
      expectedProjectId: project.id,
      projectBlocks: siblingBlocks,
      isNew: true,
    });

    allBlocks.push(normalized);
    this.writeArray(WebProjectsRepository.BLOCKS_KEY, allBlocks);
    return normalized;
  }

  public updateBlock(block: SharedProjectTrackingBlock): SharedProjectTrackingBlock {
    const allBlocks = this.readArray<SharedProjectTrackingBlock>(
      WebProjectsRepository.BLOCKS_KEY
    );
    const idx = allBlocks.findIndex((b) => b.id === block.id);
    if (idx === -1) {
      throw new ProjectValidationError(
        `Cannot update missing tracking block "${block.id}".`
      );
    }
    const existing = allBlocks[idx];
    if (
      existing.projectId !== block.projectId ||
      existing.blockType !== block.blockType
    ) {
      throw new ProjectValidationError(
        `Cannot change projectId or blockType on existing block "${block.id}".`
      );
    }
    const updated: SharedProjectTrackingBlock = {
      ...block,
      title: (block.title ?? '').trim(),
      config: block.config ?? {},
      isArchived: block.isArchived === true,
      createdAt: existing.createdAt,
      updatedAt: EthiopiaClock.nowUtc().toISOString(),
    };
    const siblingBlocks = allBlocks.filter(
      (b) => b.projectId === existing.projectId
    );
    validateBlock(updated, {
      expectedProjectId: existing.projectId,
      projectBlocks: siblingBlocks,
      isNew: false,
    });
    allBlocks[idx] = updated;
    this.writeArray(WebProjectsRepository.BLOCKS_KEY, allBlocks);
    return updated;
  }

  public setBlockArchived(
    blockId: string,
    isArchived: boolean
  ): SharedProjectTrackingBlock {
    const allBlocks = this.readArray<SharedProjectTrackingBlock>(
      WebProjectsRepository.BLOCKS_KEY
    );
    const idx = allBlocks.findIndex((b) => b.id === blockId);
    if (idx === -1) {
      throw new ProjectValidationError(
        `Cannot archive missing block "${blockId}".`
      );
    }
    allBlocks[idx] = {
      ...allBlocks[idx],
      isArchived,
      updatedAt: EthiopiaClock.nowUtc().toISOString(),
    };
    this.writeArray(WebProjectsRepository.BLOCKS_KEY, allBlocks);
    return allBlocks[idx];
  }

  public deleteBlock(blockId: string): void {
    const records = this.readArray<SharedProjectTrackingRecord>(
      WebProjectsRepository.RECORDS_KEY
    ).filter((r) => r.blockId !== blockId);
    this.writeArray(WebProjectsRepository.RECORDS_KEY, records);

    const blocks = this.readArray<SharedProjectTrackingBlock>(
      WebProjectsRepository.BLOCKS_KEY
    ).filter((b) => b.id !== blockId);
    this.writeArray(WebProjectsRepository.BLOCKS_KEY, blocks);
  }

  public getRecordsForProject(
    projectId: string,
    options: { blockId?: string } = {}
  ): SharedProjectTrackingRecord[] {
    const { blockId } = options;
    return this.readArray<SharedProjectTrackingRecord>(WebProjectsRepository.RECORDS_KEY)
      .filter((r) => {
        if (r.projectId !== projectId) return false;
        if (blockId && r.blockId !== blockId) return false;
        return true;
      })
      .sort((a, b) => {
        if (a.sortOrder !== b.sortOrder) return a.sortOrder - b.sortOrder;
        return a.createdAt.localeCompare(b.createdAt);
      });
  }

  public createRecord(
    record: SharedProjectTrackingRecord
  ): SharedProjectTrackingRecord {
    const blocks = this.readArray<SharedProjectTrackingBlock>(
      WebProjectsRepository.BLOCKS_KEY
    );
    const block = blocks.find((b) => b.id === record.blockId);
    if (!block) {
      throw new ProjectValidationError(
        `Cannot create record "${record.id}": missing block "${record.blockId}".`
      );
    }

    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const cleanTaskId = record.linkedTaskId?.trim() || undefined;
    const normalized: SharedProjectTrackingRecord = {
      ...record,
      ...(record.title !== undefined && record.title !== null
        ? { title: record.title.trim() }
        : {}),
      sortOrder: record.sortOrder ?? 0,
      isCompleted: record.isCompleted === true,
      ...(cleanTaskId !== undefined ? { linkedTaskId: cleanTaskId } : {}),
      metadata: record.metadata ?? {},
      createdAt: record.createdAt ?? nowIso,
      updatedAt: record.updatedAt ?? record.createdAt ?? nowIso,
    };
    if (cleanTaskId === undefined) delete normalized.linkedTaskId;

    const allRecords = this.readArray<SharedProjectTrackingRecord>(
      WebProjectsRepository.RECORDS_KEY
    );
    const existingBlockRecords = allRecords.filter((r) => r.blockId === block.id);
    validateRecord(normalized, {
      block,
      existingBlockRecords,
      isNew: true,
    });
    this.ensureTaskExists(normalized.linkedTaskId);

    allRecords.push(normalized);
    this.writeArray(WebProjectsRepository.RECORDS_KEY, allRecords);
    return normalized;
  }

  public updateRecord(
    record: SharedProjectTrackingRecord
  ): SharedProjectTrackingRecord {
    const allRecords = this.readArray<SharedProjectTrackingRecord>(
      WebProjectsRepository.RECORDS_KEY
    );
    const idx = allRecords.findIndex((r) => r.id === record.id);
    if (idx === -1) {
      throw new ProjectValidationError(
        `Cannot update missing tracking record "${record.id}".`
      );
    }
    const existing = allRecords[idx];
    assertAppendOnlyLogProtection(existing, false);

    if (
      existing.projectId !== record.projectId ||
      existing.blockId !== record.blockId ||
      existing.recordType !== record.recordType
    ) {
      throw new ProjectValidationError(
        `Cannot change projectId, blockId, or recordType on tracking record "${record.id}".`
      );
    }

    const block = this.readArray<SharedProjectTrackingBlock>(
      WebProjectsRepository.BLOCKS_KEY
    ).find((b) => b.id === record.blockId);
    if (!block) {
      throw new ProjectValidationError(
        `Missing parent block "${record.blockId}" for record "${record.id}".`
      );
    }

    const cleanTaskId = record.linkedTaskId?.trim() || undefined;
    const updated: SharedProjectTrackingRecord = {
      ...record,
      ...(record.title !== undefined && record.title !== null
        ? { title: record.title.trim() }
        : {}),
      ...(cleanTaskId !== undefined ? { linkedTaskId: cleanTaskId } : {}),
      metadata: record.metadata ?? {},
      createdAt: existing.createdAt,
      updatedAt: EthiopiaClock.nowUtc().toISOString(),
    };
    if (cleanTaskId === undefined) delete updated.linkedTaskId;

    const existingBlockRecords = allRecords.filter((r) => r.blockId === block.id);
    validateRecord(updated, {
      block,
      existingBlockRecords,
      isNew: false,
    });
    this.ensureTaskExists(updated.linkedTaskId);

    allRecords[idx] = updated;
    this.writeArray(WebProjectsRepository.RECORDS_KEY, allRecords);
    return updated;
  }

  public appendProgressLog(
    logRecord: SharedProjectTrackingRecord
  ): SharedProjectTrackingRecord {
    if (logRecord.recordType !== 'progress_log') {
      throw new ProjectValidationError(
        'appendProgressLog requires recordType === progress_log.'
      );
    }
    return this.createRecord(logRecord);
  }

  public appendProgressCorrection(params: {
    targetLogId: string;
    correctionDelta: number;
    recordedDate: string;
    reason: string;
    correctionId?: string;
  }): SharedProjectTrackingRecord {
    const trimmedReason = params.reason.trim();
    if (!trimmedReason) {
      throw new ProjectValidationError(
        'Compensating progress correction requires a non-empty reason.'
      );
    }
    const allRecords = this.readArray<SharedProjectTrackingRecord>(
      WebProjectsRepository.RECORDS_KEY
    );
    const target = allRecords.find((r) => r.id === params.targetLogId);
    if (!target) {
      throw new ProjectValidationError(
        `Cannot compensate missing progress log "${params.targetLogId}".`
      );
    }
    if (target.recordType !== 'progress_log') {
      throw new ProjectValidationError(
        `Record "${params.targetLogId}" is not a progress_log and cannot be compensated.`
      );
    }
    const now = EthiopiaClock.nowUtc();
    const id =
      params.correctionId && params.correctionId.trim()
        ? params.correctionId.trim()
        : `corr-${now.getTime()}-${Math.floor(Math.random() * 10000)}`;
    const nowIso = now.toISOString();
    return this.createRecord({
      id,
      projectId: target.projectId,
      blockId: target.blockId,
      ...(target.parentRecordId ? { parentRecordId: target.parentRecordId } : {}),
      recordType: 'progress_log',
      sortOrder: 0,
      deltaValue: params.correctionDelta,
      isCompleted: false,
      recordedDate: params.recordedDate,
      metadata: {
        isCorrection: true,
        compensatesRecordId: params.targetLogId,
        correctionReason: trimmedReason,
      },
      createdAt: nowIso,
      updatedAt: nowIso,
    });
  }

  public deleteRecord(recordId: string): void {
    const allRecords = this.readArray<SharedProjectTrackingRecord>(
      WebProjectsRepository.RECORDS_KEY
    );
    const existing = allRecords.find((r) => r.id === recordId);
    if (!existing) return;
    assertAppendOnlyLogProtection(existing, true);

    const children = allRecords.filter((r) => r.parentRecordId === recordId);
    if (children.length > 0) {
      throw new ProjectValidationError(
        `Cannot delete tracking record "${recordId}" while ${children.length} child record(s) reference it.`
      );
    }
    this.writeArray(
      WebProjectsRepository.RECORDS_KEY,
      allRecords.filter((r) => r.id !== recordId)
    );
  }

  public getProjectProgressSummary(
    projectId: string,
    options: { asOfDate?: CalendarDate } = {}
  ): ProjectProgressSummary {
    const project = this.getProjectById(projectId);
    if (!project) {
      throw new ProjectValidationError(
        `Cannot compute summary for missing project "${projectId}".`
      );
    }
    const blocks = this.getBlocksForProject(projectId, { includeArchived: true });
    const records = this.getRecordsForProject(projectId);
    const linkedTasks = this.readArray<SharedTask>(WebProjectsRepository.TASKS_KEY);
    const milestones = this.readArray<ProjectMilestoneInput>(
      WebProjectsRepository.MILESTONES_KEY
    );
    return calculateProjectProgressSummary({
      project,
      blocks,
      records,
      linkedTasks,
      milestones,
      asOfDate: options.asOfDate,
    });
  }

  public exportProjectPackage(
    projectId: string,
    options: { exportedAt?: string; sourcePlatform?: 'web' | 'android' } = {}
  ): string {
    const project = this.getProjectById(projectId);
    if (!project) {
      throw new ProjectPackageError(
        'validation_failed',
        `Cannot export missing project "${projectId}".`
      );
    }
    const blocks = this.getBlocksForProject(projectId, { includeArchived: true });
    const records = this.getRecordsForProject(projectId);
    return serializeProjectPackage({
      project,
      blocks,
      records,
      exportedAt: options.exportedAt,
      sourcePlatform: options.sourcePlatform ?? 'web',
    });
  }

  public importProjectPackage(rawJson: string): PreparedProjectPackageImport {
    const existingProjects = this.readArray<SharedProject>(
      WebProjectsRepository.PROJECTS_KEY
    );
    const existingBlocks = this.readArray<SharedProjectTrackingBlock>(
      WebProjectsRepository.BLOCKS_KEY
    );
    const existingRecords = this.readArray<SharedProjectTrackingRecord>(
      WebProjectsRepository.RECORDS_KEY
    );

    // Validates fail-closed before mutating any persisted data.
    const prepared = prepareProjectPackageForImport(rawJson, {
      existingProjectIds: existingProjects.map((p) => p.id),
      existingBlockIds: existingBlocks.map((b) => b.id),
      existingRecordIds: existingRecords.map((r) => r.id),
    });

    const hasStorage = typeof localStorage !== 'undefined';
    const prevProjectsRaw = hasStorage
      ? localStorage.getItem(WebProjectsRepository.PROJECTS_KEY)
      : null;
    const prevBlocksRaw = hasStorage
      ? localStorage.getItem(WebProjectsRepository.BLOCKS_KEY)
      : null;
    const prevRecordsRaw = hasStorage
      ? localStorage.getItem(WebProjectsRepository.RECORDS_KEY)
      : null;

    try {
      this.writeArray(WebProjectsRepository.PROJECTS_KEY, [
        prepared.project,
        ...existingProjects,
      ]);
      this.writeArray(WebProjectsRepository.BLOCKS_KEY, [
        ...existingBlocks,
        ...prepared.trackingBlocks,
      ]);
      this.writeArray(WebProjectsRepository.RECORDS_KEY, [
        ...existingRecords,
        ...prepared.trackingRecords,
      ]);
    } catch (err) {
      if (hasStorage) {
        const restoreKey = (key: string, prev: string | null) => {
          if (prev === null) {
            localStorage.removeItem(key);
          } else {
            localStorage.setItem(key, prev);
          }
        };
        restoreKey(WebProjectsRepository.PROJECTS_KEY, prevProjectsRaw);
        restoreKey(WebProjectsRepository.BLOCKS_KEY, prevBlocksRaw);
        restoreKey(WebProjectsRepository.RECORDS_KEY, prevRecordsRaw);
      }
      throw err;
    }

    return prepared;
  }

  public getAllMilestones(): SharedMilestone[] {
    return this.readArray<SharedMilestone>(WebProjectsRepository.MILESTONES_KEY)
      .slice()
      .sort((a, b) => {
        if (a.dueDate && b.dueDate) {
          const cmp = a.dueDate.localeCompare(b.dueDate);
          if (cmp !== 0) return cmp;
        } else if (a.dueDate && !b.dueDate) {
          return -1;
        } else if (!a.dueDate && b.dueDate) {
          return 1;
        }
        return (a.createdAt ?? '').localeCompare(b.createdAt ?? '');
      });
  }

  public getMilestonesForProject(projectId: string): SharedMilestone[] {
    return this.getAllMilestones().filter((m) => m.projectId === projectId);
  }

  public createMilestone(milestone: SharedMilestone): SharedMilestone {
    const project = this.getProjectById(milestone.projectId);
    if (!project) {
      throw new ProjectValidationError(
        `Cannot create milestone "${milestone.id}": missing project "${milestone.projectId}".`
      );
    }
    const cleanDue = milestone.dueDate?.trim() || undefined;
    const nowIso = EthiopiaClock.nowUtc().toISOString();
    const normalized: SharedMilestone = {
      id: milestone.id,
      projectId: milestone.projectId,
      title: (milestone.title ?? '').trim(),
      ...(cleanDue !== undefined ? { dueDate: cleanDue } : {}),
      isCompleted: milestone.isCompleted === true,
      createdAt: milestone.createdAt ?? nowIso,
    };
    validateMilestone(normalized);

    const all = this.readArray<SharedMilestone>(WebProjectsRepository.MILESTONES_KEY);
    if (all.some((m) => m.id === normalized.id)) {
      throw new ProjectValidationError(
        `Duplicate milestone id "${normalized.id}".`
      );
    }
    all.push(normalized);
    this.writeArray(WebProjectsRepository.MILESTONES_KEY, all);
    return normalized;
  }

  public updateMilestone(milestone: SharedMilestone): SharedMilestone {
    const project = this.getProjectById(milestone.projectId);
    if (!project) {
      throw new ProjectValidationError(
        `Cannot update milestone "${milestone.id}": missing project "${milestone.projectId}".`
      );
    }
    const all = this.readArray<SharedMilestone>(WebProjectsRepository.MILESTONES_KEY);
    const idx = all.findIndex((m) => m.id === milestone.id);
    if (idx === -1) {
      throw new ProjectValidationError(
        `Cannot update missing milestone "${milestone.id}".`
      );
    }
    const existing = all[idx];
    const cleanDue = milestone.dueDate?.trim() || undefined;
    const updated: SharedMilestone = {
      id: existing.id,
      projectId: milestone.projectId,
      title: (milestone.title ?? '').trim(),
      ...(cleanDue !== undefined ? { dueDate: cleanDue } : {}),
      isCompleted: milestone.isCompleted === true,
      createdAt: existing.createdAt,
    };
    validateMilestone(updated);
    all[idx] = updated;
    this.writeArray(WebProjectsRepository.MILESTONES_KEY, all);
    return updated;
  }

  public toggleMilestone(
    milestoneId: string,
    isCompleted: boolean
  ): SharedMilestone {
    const all = this.readArray<SharedMilestone>(WebProjectsRepository.MILESTONES_KEY);
    const idx = all.findIndex((m) => m.id === milestoneId);
    if (idx === -1) {
      throw new ProjectValidationError(
        `Cannot toggle missing milestone "${milestoneId}".`
      );
    }
    const updated: SharedMilestone = {
      ...all[idx],
      isCompleted,
    };
    all[idx] = updated;
    this.writeArray(WebProjectsRepository.MILESTONES_KEY, all);
    return updated;
  }

  public deleteMilestone(milestoneId: string): {
    deleted?: SharedMilestone;
    detachedTaskIds: string[];
  } {
    const all = this.readArray<SharedMilestone>(WebProjectsRepository.MILESTONES_KEY);
    const deleted = all.find((m) => m.id === milestoneId);
    if (!deleted) {
      return { detachedTaskIds: [] };
    }

    const detachedTaskIds: string[] = [];
    if (
      typeof localStorage !== 'undefined' &&
      localStorage.getItem(WebProjectsRepository.TASKS_KEY) !== null
    ) {
      const tasks = this.readArray<SharedTask>(WebProjectsRepository.TASKS_KEY);
      let changed = false;
      const nextTasks = tasks.map((t) => {
        if (t.milestoneId !== milestoneId) return t;
        changed = true;
        detachedTaskIds.push(t.id);
        const copy = { ...t };
        delete copy.milestoneId;
        return copy;
      });
      if (changed) {
        this.writeArray(WebProjectsRepository.TASKS_KEY, nextTasks);
      }
    }

    this.writeArray(
      WebProjectsRepository.MILESTONES_KEY,
      all.filter((m) => m.id !== milestoneId)
    );
    return { deleted, detachedTaskIds };
  }
}
