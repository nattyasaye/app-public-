import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { ProjectProgressSummary } from '../../domain/projectsEngine';
import { SharedProject } from '../../domain/sharedFoundation';
import { SharedStateBridge } from '../../services/sharedStateBridge';
import {
  PreparedProjectPackageImport,
  projectsService,
} from '../../services/projectsService';
import {
  Archive,
  ChevronRight,
  Download,
  Layers,
  Plus,
  RotateCcw,
  Trash2,
  Upload,
} from 'lucide-react';
import {
  DaywellButton,
  DaywellCard,
  DaywellConfirmationDialog,
  DaywellContentState,
  DaywellIconButton,
  DaywellProgressBar,
  DaywellSearchField,
  DaywellStatusBadge,
  DaywellStatusBanner,
  DaywellStatusTone,
} from '../ui';
import { ProjectFormModal } from './ProjectFormModal';
import { ProjectImportModal } from './ProjectImportModal';
import { ProjectDetailView } from './ProjectDetailView';

export type ProjectWorkspaceFilter = 'active' | 'on_hold' | 'completed' | 'archived';

export interface ProjectsWorkspaceViewProps {
  selectedProjectId?: string | null;
  onSelectProjectId?: (projectId: string | null) => void;
  externalCreateTrigger?: number;
}

function getFilterBadgeTone(status: SharedProject['status'], isArchived: boolean): {
  label: string;
  tone: DaywellStatusTone;
} {
  if (isArchived) return { label: 'Archived', tone: 'neutral' };
  switch (status) {
    case 'completed':
      return { label: 'Completed', tone: 'success' };
    case 'on_hold':
      return { label: 'On Hold', tone: 'warning' };
    default:
      return { label: 'Active', tone: 'info' };
  }
}

export function ProjectsWorkspaceView({
  selectedProjectId: controlledSelectedId,
  onSelectProjectId,
  externalCreateTrigger = 0,
}: ProjectsWorkspaceViewProps) {
  const [internalSelectedId, setInternalSelectedId] = useState<string | null>(null);
  const selectedId =
    controlledSelectedId !== undefined ? controlledSelectedId : internalSelectedId;
  const selectProject = (id: string | null) => {
    if (onSelectProjectId) {
      onSelectProjectId(id);
    } else {
      setInternalSelectedId(id);
    }
  };

  const [projects, setProjects] = useState<SharedProject[]>([]);
  const [summaries, setSummaries] = useState<Record<string, ProjectProgressSummary>>(
    {}
  );
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [filter, setFilter] = useState<ProjectWorkspaceFilter>('active');
  const [searchQuery, setSearchQuery] = useState('');
  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const [isImportOpen, setIsImportOpen] = useState(false);
  const [statusNotice, setStatusNotice] = useState<{
    tone: 'success' | 'error';
    title?: string;
    message: string;
    actionProjectId?: string;
  } | null>(null);
  const [projectToDelete, setProjectToDelete] = useState<SharedProject | null>(
    null
  );

  const reload = useCallback(() => {
    try {
      const all = projectsService.listProjects({ includeArchived: true });
      const nextSummaries = projectsService.getAllProjectSummaries({
        includeArchived: true,
      });
      setProjects(all);
      setSummaries(nextSummaries);
      setErrorMsg(null);
    } catch (err) {
      setErrorMsg(
        err instanceof Error ? err.message : 'Unable to load projects.'
      );
    }
  }, []);

  useEffect(() => {
    reload();
    const handler = () => reload();
    if (typeof window !== 'undefined') {
      window.addEventListener(SharedStateBridge.SYNC_EVENT_NAME, handler);
      return () =>
        window.removeEventListener(SharedStateBridge.SYNC_EVENT_NAME, handler);
    }
    return undefined;
  }, [reload]);

  useEffect(() => {
    if (externalCreateTrigger > 0) {
      setIsCreateOpen(true);
    }
  }, [externalCreateTrigger]);

  const counts = useMemo(() => {
    let active = 0;
    let onHold = 0;
    let completed = 0;
    let archived = 0;
    for (const p of projects) {
      if (p.isArchived) {
        archived += 1;
      } else if (p.status === 'on_hold') {
        onHold += 1;
      } else if (p.status === 'completed') {
        completed += 1;
      } else {
        active += 1;
      }
    }
    return { active, onHold, completed, archived };
  }, [projects]);

  const filteredProjects = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    return projects.filter((p) => {
      if (filter === 'archived') {
        if (!p.isArchived) return false;
      } else {
        if (p.isArchived) return false;
        if (p.status !== filter) return false;
      }
      if (q) {
        const hay = `${p.title} ${p.description ?? ''}`.toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });
  }, [projects, filter, searchQuery]);

  if (selectedId) {
    return (
      <ProjectDetailView
        projectId={selectedId}
        onBack={() => {
          selectProject(null);
          reload();
        }}
        onDeleted={() => {
          selectProject(null);
          reload();
        }}
      />
    );
  }

  const handleExportProject = (project: SharedProject) => {
    try {
      const { filename } = projectsService.downloadProjectPackage(project.id);
      setStatusNotice({
        tone: 'success',
        title: 'Project exported',
        message: `Downloaded "${filename}" (${project.title}).`,
      });
    } catch (err) {
      setStatusNotice({
        tone: 'error',
        title: 'Export failed',
        message:
          err instanceof Error
            ? err.message
            : 'Unable to export project package.',
      });
    }
  };

  const handleImported = (result: PreparedProjectPackageImport) => {
    setIsImportOpen(false);
    setFilter(result.project.isArchived ? 'archived' : result.project.status);
    reload();
    setStatusNotice({
      tone: 'success',
      title: 'Project imported',
      message: `Imported "${result.project.title}" (${result.trackingBlocks.length} ${
        result.trackingBlocks.length === 1 ? 'block' : 'blocks'
      }, ${result.trackingRecords.length} ${
        result.trackingRecords.length === 1 ? 'record' : 'records'
      }).`,
      actionProjectId: result.project.id,
    });
  };

  return (
    <div className="space-y-4">
      {/* Search + Primary Actions */}
      <div className="flex flex-wrap items-center gap-2">
        <DaywellSearchField
          value={searchQuery}
          onChange={setSearchQuery}
          placeholder="Search projects..."
          ariaLabel="Search projects"
          className="flex-1 min-w-[200px]"
        />
        <div className="flex items-center gap-2 shrink-0">
          <DaywellButton
            label="Import / Template"
            variant="outlined"
            size="compact"
            leadingIcon={<Upload className="w-4 h-4" />}
            onClick={() => setIsImportOpen(true)}
          />
          <DaywellButton
            label="New Project"
            variant="primary"
            size="compact"
            leadingIcon={<Plus className="w-4 h-4" />}
            onClick={() => setIsCreateOpen(true)}
          />
        </div>
      </div>

      {statusNotice && (
        <DaywellStatusBanner
          tone={statusNotice.tone}
          title={statusNotice.title}
          message={statusNotice.message}
          actionLabel={statusNotice.actionProjectId ? 'Open' : undefined}
          onActionPressed={
            statusNotice.actionProjectId
              ? () => {
                  const id = statusNotice.actionProjectId!;
                  setStatusNotice(null);
                  selectProject(id);
                }
              : undefined
          }
          onDismiss={() => setStatusNotice(null)}
          liveRegion
        />
      )}

      {/* Filter Tabs */}
      <div
        className="flex items-center gap-1.5 overflow-x-auto pb-0.5"
        role="tablist"
        aria-label="Project lifecycle filters"
      >
        {(
          [
            { key: 'active', label: `Active (${counts.active})` },
            { key: 'on_hold', label: `On Hold (${counts.onHold})` },
            { key: 'completed', label: `Completed (${counts.completed})` },
            { key: 'archived', label: `Archived (${counts.archived})` },
          ] as const
        ).map((tab) => {
          const isActive = filter === tab.key;
          return (
            <button
              key={tab.key}
              type="button"
              role="tab"
              aria-selected={isActive}
              onClick={() => setFilter(tab.key)}
              className={`min-h-[36px] text-xs px-3.5 py-1.5 rounded-[var(--dw-radius-full)] font-semibold transition-all shrink-0 cursor-pointer ${
                isActive
                  ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)] font-bold'
                  : 'bg-[var(--dw-card)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)] hover:bg-[var(--dw-surface-subtle)]'
              }`}
            >
              {tab.label}
            </button>
          );
        })}
      </div>

      {/* Project List */}
      <DaywellContentState
        error={errorMsg}
        isEmpty={filteredProjects.length === 0 && !errorMsg}
        emptyIcon={<Layers className="w-8 h-8" />}
        emptyMessage={
          searchQuery.trim()
            ? `No ${filter.replace('_', ' ')} projects match "${searchQuery.trim()}"`
            : filter === 'active'
            ? 'No active projects yet'
            : `No ${filter.replace('_', ' ')} projects`
        }
        emptySubtitle={
          filter === 'active' && !searchQuery.trim()
            ? 'Group larger goals with custom tracking blocks like counters, checklists, grouped lists, or schedules.'
            : undefined
        }
        emptyActionLabel={
          filter === 'active' && !searchQuery.trim() ? 'New Project' : undefined
        }
        onEmptyAction={() => setIsCreateOpen(true)}
        onRetry={reload}
      >
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {filteredProjects.map((project) => {
            const summary = summaries[project.id];
            const activeMetrics = (summary?.blockMetrics ?? []).filter(
              (m) => !m.isArchived
            );
            const badgeSpec = getFilterBadgeTone(project.status, Boolean(project.isArchived));
            const metaParts = [
              project.targetDate ? `Target ${project.targetDate}` : null,
              activeMetrics.length > 0
                ? `${activeMetrics.length} ${
                    activeMetrics.length === 1 ? 'block' : 'blocks'
                  }`
                : null,
              summary && summary.linkedTasksTotal > 0
                ? `${summary.linkedTasksCompleted}/${summary.linkedTasksTotal} tasks`
                : null,
            ].filter(Boolean);

            return (
              <DaywellCard
                key={project.id}
                padding="md"
                radius="lg"
                onClick={() => selectProject(project.id)}
                className="flex flex-col justify-between h-full space-y-2.5"
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0 space-y-1">
                    <div className="flex items-center flex-wrap gap-1.5">
                      <h3 className="text-sm font-bold text-[var(--dw-text-primary)] truncate">
                        {project.title}
                      </h3>
                      {(project.status !== 'active' || project.isArchived) && (
                        <DaywellStatusBadge
                          tone={badgeSpec.tone}
                          showIcon={false}
                          label={badgeSpec.label}
                        />
                      )}
                    </div>
                    {metaParts.length > 0 && (
                      <p className="text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
                        {metaParts.join(' · ')}
                      </p>
                    )}
                  </div>

                  <div
                    className="flex items-center gap-0.5 shrink-0"
                    onClick={(e) => e.stopPropagation()}
                  >
                    <DaywellIconButton
                      label={`Export ${project.title} (.daywellproject)`}
                      size="compact"
                      tone="muted"
                      onClick={() => handleExportProject(project)}
                      icon={<Download className="w-3.5 h-3.5" />}
                    />
                    <DaywellIconButton
                      label={
                        project.isArchived
                          ? `Restore ${project.title}`
                          : `Archive ${project.title}`
                      }
                      size="compact"
                      tone="muted"
                      onClick={() => {
                        projectsService.setProjectArchived(
                          project.id,
                          !project.isArchived
                        );
                        reload();
                      }}
                      icon={
                        project.isArchived ? (
                          <RotateCcw className="w-3.5 h-3.5" />
                        ) : (
                          <Archive className="w-3.5 h-3.5" />
                        )
                      }
                    />
                    {project.isArchived && (
                      <DaywellIconButton
                        label={`Delete ${project.title} permanently`}
                        size="compact"
                        tone="danger"
                        onClick={() => setProjectToDelete(project)}
                        icon={<Trash2 className="w-3.5 h-3.5" />}
                      />
                    )}
                    <ChevronRight className="w-4 h-4 text-[var(--dw-text-muted)] ml-0.5" />
                  </div>
                </div>

                {project.description && (
                  <p className="text-xs text-[var(--dw-text-secondary)] line-clamp-2">
                    {project.description}
                  </p>
                )}

                {summary?.primaryMetric ? (
                  <div className="space-y-1.5 pt-0.5">
                    <div className="flex items-center justify-between text-[11px] dw-type-numeric-body">
                      <span className="text-[var(--dw-text-secondary)] truncate">
                        {summary.primaryMetric.title}:{' '}
                        {projectsService.formatBlockMetricSummary(
                          summary.primaryMetric
                        )}
                      </span>
                      {summary.overallPercentage !== undefined && (
                        <span className="font-bold text-[var(--dw-text-primary)] shrink-0 ml-2">
                          {Math.round(summary.overallPercentage)}%
                        </span>
                      )}
                    </div>
                    {summary.overallPercentage !== undefined && (
                      <DaywellProgressBar
                        value={summary.overallPercentage}
                        label={`${project.title} progress`}
                      />
                    )}
                  </div>
                ) : activeMetrics.length > 0 ? (
                  <div className="space-y-1 pt-0.5 border-t border-[var(--dw-divider)]">
                    {activeMetrics.slice(0, 2).map((m) => (
                      <div
                        key={m.blockId}
                        className="flex items-center justify-between text-[11px] text-[var(--dw-text-secondary)] dw-type-numeric-body"
                      >
                        <span className="truncate">{m.title}</span>
                        <span className="shrink-0 ml-2 font-medium">
                          {projectsService.formatBlockMetricSummary(m)}
                        </span>
                      </div>
                    ))}
                    {activeMetrics.length > 2 && (
                      <p className="text-[11px] text-[var(--dw-text-muted)]">
                        +{activeMetrics.length - 2} more tracking block(s)
                      </p>
                    )}
                  </div>
                ) : null}
              </DaywellCard>
            );
          })}
        </div>
      </DaywellContentState>

      <ProjectFormModal
        isOpen={isCreateOpen}
        onClose={() => setIsCreateOpen(false)}
        onSaved={(created) => {
          setIsCreateOpen(false);
          reload();
          selectProject(created.id);
        }}
      />

      <ProjectImportModal
        isOpen={isImportOpen}
        onClose={() => setIsImportOpen(false)}
        onImported={handleImported}
      />

      <DaywellConfirmationDialog
        isOpen={Boolean(projectToDelete)}
        title={`Delete "${projectToDelete?.title ?? ''}" forever?`}
        description="This permanently removes the archived project, its tracking blocks, and its progress history. Linked tasks stay intact and are safely unlinked."
        confirmLabel="Delete Forever"
        destructive
        onCancel={() => setProjectToDelete(null)}
        onConfirm={() => {
          if (projectToDelete) {
            projectsService.deleteArchivedProject(projectToDelete.id);
          }
          setProjectToDelete(null);
          reload();
        }}
      />
    </div>
  );
}
