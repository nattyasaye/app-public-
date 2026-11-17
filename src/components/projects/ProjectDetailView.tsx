import React, { useCallback, useEffect, useState } from 'react';
import { CalendarDate, SharedDateFormatter } from '../../domain/date';
import { SharedProject } from '../../domain/sharedFoundation';
import {
  EnrichedProgressLogEntry,
  ProjectDetailSnapshot,
  projectsService,
} from '../../services/projectsService';
import {
  Archive,
  ArrowLeft,
  Calendar,
  Edit3,
  RotateCcw,
  Target,
  Trash2,
} from 'lucide-react';
import {
  DaywellButton,
  DaywellCard,
  DaywellConfirmationDialog,
  DaywellContentState,
  DaywellIconButton,
  DaywellProgressBar,
  DaywellStatusBadge,
  DaywellStatusBanner,
  DaywellStatusTone,
} from '../ui';
import { ProjectFormModal } from './ProjectFormModal';
import { ProjectTrackingBlocksSection } from './ProjectTrackingBlocksSection';
import { ProjectProgressHistorySection } from './ProjectProgressHistorySection';

export interface ProjectDetailViewProps {
  projectId: string;
  onBack: () => void;
  onDeleted: () => void;
}

function formatDualDateLabel(isoDate?: string): string | undefined {
  if (!isoDate) return undefined;
  const parsed = CalendarDate.tryParse(isoDate);
  if (!parsed) return isoDate;
  return SharedDateFormatter.formatDual(parsed);
}

function getStatusBadgeSpec(project: SharedProject): {
  label: string;
  tone: DaywellStatusTone;
} {
  if (project.isArchived) {
    return { label: 'Archived', tone: 'neutral' };
  }
  switch (project.status) {
    case 'completed':
      return { label: 'Completed', tone: 'success' };
    case 'on_hold':
      return { label: 'On Hold', tone: 'warning' };
    default:
      return { label: 'Active', tone: 'info' };
  }
}

export function ProjectDetailView({
  projectId,
  onBack,
  onDeleted,
}: ProjectDetailViewProps) {
  const [snapshot, setSnapshot] = useState<ProjectDetailSnapshot | undefined>(
    undefined
  );
  const [history, setHistory] = useState<EnrichedProgressLogEntry[]>([]);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [isEditOpen, setIsEditOpen] = useState(false);
  const [confirmDeleteOpen, setConfirmDeleteOpen] = useState(false);

  const loadSnapshot = useCallback(() => {
    try {
      const next = projectsService.getProjectDetailSnapshot(projectId);
      setSnapshot(next);
      setHistory(
        next ? projectsService.getChronologicalProgressHistory(projectId) : []
      );
      setErrorMsg(null);
    } catch (err) {
      setErrorMsg(
        err instanceof Error ? err.message : 'Unable to load project details.'
      );
    }
  }, [projectId]);

  useEffect(() => {
    loadSnapshot();
  }, [loadSnapshot]);

  const project = snapshot?.project;
  const blocks = snapshot?.blocks ?? [];
  const records = snapshot?.records ?? [];
  const summary = snapshot?.summary;
  const linkedTasks = snapshot?.linkedTasks ?? [];
  const goal = project?.goalId
    ? projectsService.getGoals().find((g) => g.id === project.goalId)
    : undefined;

  const startLabel = formatDualDateLabel(project?.startDate);
  const targetLabel = formatDualDateLabel(project?.targetDate);

  const handleToggleArchive = () => {
    if (!project) return;
    try {
      projectsService.setProjectArchived(project.id, !project.isArchived);
      loadSnapshot();
    } catch (err) {
      setErrorMsg(
        err instanceof Error ? err.message : 'Unable to update archive state.'
      );
    }
  };

  const handleConfirmDelete = () => {
    if (!project) return;
    try {
      projectsService.deleteArchivedProject(project.id);
      setConfirmDeleteOpen(false);
      onDeleted();
    } catch (err) {
      setConfirmDeleteOpen(false);
      setErrorMsg(
        err instanceof Error ? err.message : 'Unable to delete project.'
      );
    }
  };

  const statusSpec = project ? getStatusBadgeSpec(project) : null;
  const activeBlockCount = blocks.filter((b) => !b.isArchived).length;

  return (
    <div className="space-y-4">
      {/* Header Bar */}
      <div className="flex items-center justify-between gap-2 pt-1">
        <div className="flex items-center gap-2 min-w-0">
          <DaywellIconButton
            label="Back to projects"
            tone="muted"
            onClick={onBack}
            icon={<ArrowLeft className="w-5 h-5" />}
          />
          <div className="min-w-0">
            <div className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
              PROJECT DETAILS
            </div>
            <h1 className="dw-type-heading text-[var(--dw-text-primary)] truncate">
              {project?.title ?? 'Project'}
            </h1>
          </div>
        </div>

        {project && (
          <div className="flex items-center gap-1 shrink-0">
            <DaywellIconButton
              label="Edit project"
              tone="muted"
              onClick={() => setIsEditOpen(true)}
              icon={<Edit3 className="w-4 h-4" />}
            />
            <DaywellIconButton
              label={project.isArchived ? 'Restore project' : 'Archive project'}
              tone="muted"
              onClick={handleToggleArchive}
              icon={
                project.isArchived ? (
                  <RotateCcw className="w-4 h-4" />
                ) : (
                  <Archive className="w-4 h-4" />
                )
              }
            />
            {project.isArchived && (
              <DaywellIconButton
                label="Delete project forever"
                tone="danger"
                onClick={() => setConfirmDeleteOpen(true)}
                icon={<Trash2 className="w-4 h-4" />}
              />
            )}
          </div>
        )}
      </div>

      <DaywellContentState
        error={errorMsg}
        isEmpty={!project && !errorMsg}
        emptyMessage="Project not found"
        emptySubtitle="This project may have been removed."
        emptyActionLabel="Back to Projects"
        onEmptyAction={onBack}
        onRetry={loadSnapshot}
      >
        {project && summary && (
          <div className="space-y-4">
            {project.isArchived && (
              <DaywellStatusBanner
                tone="warning"
                title="Archived project"
                message="This project is archived and hidden from your active workspace. Restore it to continue active work, or delete it permanently."
                actionLabel="Restore"
                onActionPressed={handleToggleArchive}
              />
            )}

            {/* Metadata & Narrative Card */}
            <DaywellCard padding="md" radius="lg" className="space-y-2.5">
              <div className="flex items-center justify-between flex-wrap gap-2">
                {statusSpec && (
                  <DaywellStatusBadge
                    tone={statusSpec.tone}
                    showIcon={false}
                    label={statusSpec.label}
                  />
                )}
                {summary.linkedTasksTotal > 0 && (
                  <span className="text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
                    {summary.linkedTasksCompleted}/{summary.linkedTasksTotal} linked tasks done
                  </span>
                )}
              </div>

              {project.description && (
                <p className="text-xs text-[var(--dw-text-secondary)] leading-relaxed">
                  {project.description}
                </p>
              )}

              {(startLabel || targetLabel || goal) && (
                <div className="pt-1.5 border-t border-[var(--dw-divider)] space-y-1 text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
                  {(startLabel || targetLabel) && (
                    <div className="flex items-center gap-1.5">
                      <Calendar className="w-3.5 h-3.5 text-[var(--dw-primary)] shrink-0" />
                      <span>
                        {[
                          startLabel ? `Start: ${startLabel}` : null,
                          targetLabel ? `Target: ${targetLabel}` : null,
                        ]
                          .filter(Boolean)
                          .join(' · ')}
                      </span>
                    </div>
                  )}
                  {(goal || project.goalId) && (
                    <div className="flex items-center gap-1.5">
                      <Target className="w-3.5 h-3.5 text-[var(--dw-primary)] shrink-0" />
                      <span>
                        Goal: {goal?.title ?? project.goalId}
                      </span>
                    </div>
                  )}
                </div>
              )}
            </DaywellCard>

            {/* Primary Progress Card (never averages across unrelated blocks) */}
            {summary.hasInvalidPrimaryBlockReference ? (
              <DaywellStatusBanner
                tone="warning"
                title="Primary tracking block unavailable"
                message="The block configured for overall progress was archived or removed. Star an active block below or restore the archived block."
              />
            ) : summary.primaryMetric ? (
              <DaywellCard variant="primaryContainer" padding="md" radius="lg" className="space-y-2">
                <div className="flex items-baseline justify-between gap-2">
                  <div className="min-w-0">
                    <div className="dw-type-caption uppercase tracking-wider text-[var(--dw-on-primary-container)] opacity-80">
                      OVERALL PROGRESS · {summary.primaryMetric.title}
                    </div>
                    <p className="text-xs font-semibold text-[var(--dw-on-primary-container)] dw-type-numeric-body">
                      {projectsService.formatBlockMetricSummary(summary.primaryMetric)}
                    </p>
                  </div>
                  {summary.overallPercentage !== undefined && (
                    <span className="dw-type-numeric-hero text-[var(--dw-on-primary-container)] shrink-0">
                      {Math.round(summary.overallPercentage)}%
                    </span>
                  )}
                </div>
                {summary.overallPercentage !== undefined && (
                  <DaywellProgressBar
                    value={summary.overallPercentage}
                    label={`${project.title} overall progress`}
                  />
                )}
              </DaywellCard>
            ) : activeBlockCount > 0 ? (
              <DaywellCard variant="subtle" padding="compact" radius="lg">
                <p className="text-[11px] text-[var(--dw-text-secondary)]">
                  Each tracking block reports its own metric below. Star any active block to promote it as this project&apos;s headline progress.
                </p>
              </DaywellCard>
            ) : null}

            {/* Linked Tasks Summary (read-only link readout if any exist) */}
            {linkedTasks.length > 0 && (
              <DaywellCard padding="compact" radius="lg" className="space-y-1.5">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-bold text-[var(--dw-text-primary)]">
                    Linked Tasks
                  </span>
                  <span className="text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
                    {summary.linkedTasksCompleted}/{summary.linkedTasksTotal} complete
                  </span>
                </div>
                <div className="space-y-1">
                  {linkedTasks.slice(0, 5).map((task) => (
                    <p
                      key={task.id}
                      className={`text-xs truncate ${
                        task.status === 'completed'
                          ? 'line-through text-[var(--dw-text-muted)]'
                          : 'text-[var(--dw-text-secondary)]'
                      }`}
                    >
                      · {task.title}
                    </p>
                  ))}
                  {linkedTasks.length > 5 && (
                    <p className="text-[11px] text-[var(--dw-text-muted)]">
                      +{linkedTasks.length - 5} more in Tasks tab
                    </p>
                  )}
                </div>
              </DaywellCard>
            )}

            {/* Tracking Blocks */}
            <ProjectTrackingBlocksSection
              project={project}
              blocks={blocks}
              records={records}
              blockMetrics={summary.blockMetrics}
              primaryBlockId={summary.primaryBlockId}
              onRefresh={loadSnapshot}
            />

            {/* Append-Only Progress History + Adjustment */}
            <ProjectProgressHistorySection
              projectId={project.id}
              history={history}
              onRefresh={loadSnapshot}
            />
          </div>
        )}
      </DaywellContentState>

      {project && (
        <ProjectFormModal
          isOpen={isEditOpen}
          editingProject={project}
          existingBlocks={blocks}
          onClose={() => setIsEditOpen(false)}
          onSaved={() => {
            setIsEditOpen(false);
            loadSnapshot();
          }}
        />
      )}

      <DaywellConfirmationDialog
        isOpen={confirmDeleteOpen}
        title={`Delete "${project?.title ?? ''}" forever?`}
        description="This permanently deletes the archived project, all of its tracking blocks, and all progress logs. Any linked tasks remain safe and become unlinked."
        confirmLabel="Delete Forever"
        destructive
        onCancel={() => setConfirmDeleteOpen(false)}
        onConfirm={handleConfirmDelete}
      />
    </div>
  );
}
