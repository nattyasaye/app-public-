import React, { useState } from 'react';
import {
  SharedMilestone,
  SharedProjectTrackingRecord,
} from '../../domain/sharedFoundation';
import {
  CANONICAL_TASK_PRIORITIES,
  CANONICAL_TASK_STATUSES,
  computeSubtaskProgress,
  DaywellTaskRecord,
  isTaskCompleted,
  resolveEffectiveTaskStatus,
  TASK_PRIORITY_LABELS,
  TASK_STATUS_LABELS,
  TaskPriority,
  TaskStatus,
} from '../../domain/taskOperations';
import {
  ProjectSectionsViewModel,
  projectsService,
} from '../../services/projectsService';
import {
  Calendar,
  Check,
  CheckSquare,
  Edit3,
  Flag,
  FolderPlus,
  Plus,
  Trash2,
  X,
} from 'lucide-react';
import {
  DaywellButton,
  DaywellCard,
  DaywellConfirmationDialog,
  DaywellIconButton,
  DaywellProgressBar,
  DaywellStatusBadge,
} from '../ui';

export interface ProjectTasksSectionsCardProps {
  projectId: string;
  sectionsView: ProjectSectionsViewModel;
  milestones: SharedMilestone[];
  onRefresh: () => void;
  onNotifyUndo?: (message: string, undoAction: () => void) => void;
}

export function ProjectTasksSectionsCard({
  projectId,
  sectionsView,
  milestones,
  onRefresh,
  onNotifyUndo,
}: ProjectTasksSectionsCardProps) {
  const [isAddingSection, setIsAddingSection] = useState(false);
  const [newSectionTitle, setNewSectionTitle] = useState('');
  const [sectionError, setSectionError] = useState<string | null>(null);

  const [renamingSectionId, setRenamingSectionId] = useState<string | null>(
    null
  );
  const [renameTitle, setRenameTitle] = useState('');
  const [renameError, setRenameError] = useState<string | null>(null);

  const [pendingDeleteSection, setPendingDeleteSection] =
    useState<SharedProjectTrackingRecord | null>(null);

  // Task Modal (Create or Edit inside Project Details)
  const [isTaskModalOpen, setIsTaskModalOpen] = useState(false);
  const [editingTask, setEditingTask] = useState<DaywellTaskRecord | null>(null);
  const [taskTitle, setTaskTitle] = useState('');
  const [taskDescription, setTaskDescription] = useState('');
  const [taskPriority, setTaskPriority] = useState<TaskPriority>('medium');
  const [taskStatus, setTaskStatus] = useState<TaskStatus>('not_started');
  const [taskDueDate, setTaskDueDate] = useState('');
  const [taskScheduledDate, setTaskScheduledDate] = useState('');
  const [taskSectionId, setTaskSectionId] = useState('');
  const [taskMilestoneId, setTaskMilestoneId] = useState('');
  const [taskFormError, setTaskFormError] = useState<string | null>(null);

  const [pendingDeleteTask, setPendingDeleteTask] =
    useState<DaywellTaskRecord | null>(null);

  const allTasks = [
    ...sectionsView.sections.flatMap((s) => s.tasks),
    ...sectionsView.unsectionedTasks,
  ];
  const completedTasksCount = allTasks.filter((t) => isTaskCompleted(t)).length;
  const tasksPct =
    allTasks.length > 0
      ? Math.round((completedTasksCount / allTasks.length) * 100)
      : 0;

  const milestoneById = new Map(milestones.map((m) => [m.id, m]));
  const taskToSectionId = new Map<string, string>();
  for (const sec of sectionsView.sections) {
    for (const t of sec.tasks) {
      taskToSectionId.set(t.id, sec.record.id);
    }
  }

  const handleCreateSection = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = newSectionTitle.trim();
    if (!trimmed) {
      setSectionError('Section name is required.');
      return;
    }
    try {
      projectsService.createProjectSection(projectId, trimmed);
      setNewSectionTitle('');
      setSectionError(null);
      setIsAddingSection(false);
      onRefresh();
    } catch (err) {
      setSectionError(
        err instanceof Error ? err.message : 'Unable to create section.'
      );
    }
  };

  const handleSaveRenameSection = (sectionId: string) => {
    const trimmed = renameTitle.trim();
    if (!trimmed) {
      setRenameError('Section name is required.');
      return;
    }
    try {
      projectsService.renameProjectSection(sectionId, trimmed);
      setRenamingSectionId(null);
      setRenameTitle('');
      setRenameError(null);
      onRefresh();
    } catch (err) {
      setRenameError(
        err instanceof Error ? err.message : 'Unable to rename section.'
      );
    }
  };

  const handleConfirmDeleteSection = () => {
    if (!pendingDeleteSection) return;
    const target = pendingDeleteSection;
    const { deletedGroup, detachedTaskIds } =
      projectsService.deleteProjectSection(projectId, target.id);
    setPendingDeleteSection(null);
    onRefresh();
    if (deletedGroup) {
      onNotifyUndo?.(
        `Removed section "${deletedGroup.title ?? 'Section'}"`,
        () => {
          projectsService.restoreProjectSection(
            projectId,
            deletedGroup,
            detachedTaskIds
          );
          onRefresh();
        }
      );
    }
  };

  const openCreateTask = (defaultSectionId = '') => {
    setEditingTask(null);
    setTaskTitle('');
    setTaskDescription('');
    setTaskPriority('medium');
    setTaskStatus('not_started');
    setTaskDueDate('');
    setTaskScheduledDate('');
    setTaskSectionId(defaultSectionId);
    setTaskMilestoneId('');
    setTaskFormError(null);
    setIsTaskModalOpen(true);
  };

  const openEditTask = (task: DaywellTaskRecord) => {
    setEditingTask(task);
    setTaskTitle(task.title);
    setTaskDescription(task.description ?? '');
    setTaskPriority(task.priority);
    setTaskStatus(resolveEffectiveTaskStatus(task));
    setTaskDueDate(task.dueDate ?? '');
    setTaskScheduledDate(task.scheduledDate ?? '');
    setTaskSectionId(taskToSectionId.get(task.id) ?? '');
    setTaskMilestoneId(task.milestoneId ?? '');
    setTaskFormError(null);
    setIsTaskModalOpen(true);
  };

  const handleSaveTaskModal = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = taskTitle.trim();
    if (!trimmed) {
      setTaskFormError('Task title is required.');
      return;
    }
    try {
      if (editingTask) {
        projectsService.updateTaskInProject(editingTask.id, {
          title: trimmed,
          description: taskDescription,
          priority: taskPriority,
          status: taskStatus,
          dueDate: taskDueDate,
          scheduledDate: taskScheduledDate,
          milestoneId: taskMilestoneId || '',
          sectionId: taskSectionId || null,
        });
      } else {
        projectsService.createTaskInProject({
          projectId,
          title: trimmed,
          description: taskDescription,
          priority: taskPriority,
          status: taskStatus,
          dueDate: taskDueDate || undefined,
          scheduledDate: taskScheduledDate || undefined,
          milestoneId: taskMilestoneId || undefined,
          sectionId: taskSectionId || undefined,
        });
      }
      setIsTaskModalOpen(false);
      setTaskFormError(null);
      onRefresh();
    } catch (err) {
      setTaskFormError(
        err instanceof Error ? err.message : 'Unable to save task.'
      );
    }
  };

  const handleToggleTask = (task: DaywellTaskRecord) => {
    const wasDone = isTaskCompleted(task);
    const prevSectionId = taskToSectionId.get(task.id);
    const { previousTasks } = projectsService.toggleTaskCompletionInProject(
      task.id
    );
    onRefresh();
    onNotifyUndo?.(
      wasDone ? `Reopened "${task.title}"` : `Completed "${task.title}"`,
      () => {
        projectsService.restoreTasksSnapshot(
          previousTasks,
          prevSectionId
            ? { projectId, taskId: task.id, sectionId: prevSectionId }
            : undefined
        );
        onRefresh();
      }
    );
  };

  const handleMoveTaskSection = (task: DaywellTaskRecord, nextSectionId: string) => {
    projectsService.assignTaskToProjectSection(
      projectId,
      task.id,
      nextSectionId || null
    );
    onRefresh();
  };

  const handleConfirmDeleteTask = () => {
    if (!pendingDeleteTask) return;
    const target = pendingDeleteTask;
    const { previousTasks, deleted, previousSection } =
      projectsService.deleteTaskInProject(target.id);
    setPendingDeleteTask(null);
    setIsTaskModalOpen(false);
    onRefresh();
    if (deleted) {
      onNotifyUndo?.(`Deleted "${deleted.title}"`, () => {
        projectsService.restoreTasksSnapshot(
          previousTasks,
          previousSection
            ? {
                projectId: previousSection.projectId,
                taskId: deleted.id,
                sectionId: previousSection.sectionId,
              }
            : undefined
        );
        onRefresh();
      });
    }
  };

  const renderTaskRow = (task: DaywellTaskRecord) => {
    const completed = isTaskCompleted(task);
    const subProg = computeSubtaskProgress(task.subtasks);
    const milestone = task.milestoneId
      ? milestoneById.get(task.milestoneId)
      : undefined;
    const currentSectionId = taskToSectionId.get(task.id) ?? '';

    return (
      <div
        key={task.id}
        className="p-2.5 bg-[var(--dw-card)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] flex items-start justify-between gap-2.5"
      >
        <div className="flex items-start gap-2.5 min-w-0 flex-1">
          <button
            type="button"
            aria-label={
              completed ? `Reopen ${task.title}` : `Complete ${task.title}`
            }
            onClick={() => handleToggleTask(task)}
            className={`w-4 h-4 mt-0.5 rounded-[var(--dw-radius-sm)] border flex items-center justify-center shrink-0 cursor-pointer transition-colors ${
              completed
                ? 'bg-[var(--dw-primary)] border-[var(--dw-primary)] text-[var(--dw-on-primary)]'
                : 'border-[var(--dw-border)] bg-[var(--dw-surface-subtle)] hover:border-[var(--dw-primary)]'
            }`}
          >
            {completed && <Check className="w-3 h-3 stroke-[3]" />}
          </button>

          <div
            role="button"
            tabIndex={0}
            onClick={() => openEditTask(task)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                openEditTask(task);
              }
            }}
            className="min-w-0 flex-1 space-y-1 cursor-pointer"
          >
            <p
              className={`text-xs font-semibold leading-snug ${
                completed
                  ? 'line-through text-[var(--dw-text-muted)]'
                  : 'text-[var(--dw-text-primary)]'
              }`}
            >
              {task.title}
            </p>
            <div className="flex flex-wrap items-center gap-2 text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
              <span
                className={`flex items-center gap-0.5 font-semibold ${
                  task.priority === 'urgent'
                    ? 'text-[var(--dw-error)]'
                    : task.priority === 'high'
                    ? 'text-[var(--dw-warning)]'
                    : 'text-[var(--dw-text-muted)]'
                }`}
              >
                <Flag className="w-3 h-3" />
                {TASK_PRIORITY_LABELS[task.priority]}
              </span>
              {milestone && (
                <DaywellStatusBadge
                  tone={milestone.isCompleted ? 'success' : 'info'}
                  showIcon={false}
                  label={milestone.title}
                />
              )}
              {subProg.total > 0 && (
                <span>
                  {subProg.completed}/{subProg.total} subtasks
                </span>
              )}
              {task.dueDate && (
                <span className="flex items-center gap-0.5 text-[var(--dw-primary)]">
                  <Calendar className="w-3 h-3" />
                  Due {task.dueDate}
                </span>
              )}
            </div>
          </div>
        </div>

        <div className="flex items-center gap-1 shrink-0">
          {sectionsView.sections.length > 0 && (
            <select
              aria-label={`Section for ${task.title}`}
              value={currentSectionId}
              onChange={(e) => handleMoveTaskSection(task, e.target.value)}
              className="max-w-[110px] min-h-[30px] px-2 py-0.5 bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] rounded-[var(--dw-radius-sm)] text-[11px] text-[var(--dw-text-secondary)] outline-none focus:border-[var(--dw-primary)]"
            >
              <option value="">General</option>
              {sectionsView.sections.map((s) => (
                <option key={s.record.id} value={s.record.id}>
                  {s.record.title}
                </option>
              ))}
            </select>
          )}
          <DaywellIconButton
            label={`Edit task ${task.title}`}
            size="compact"
            tone="muted"
            onClick={() => openEditTask(task)}
            icon={<Edit3 className="w-3.5 h-3.5" />}
          />
          <DaywellIconButton
            label={`Delete task ${task.title}`}
            size="compact"
            tone="danger"
            onClick={() => setPendingDeleteTask(task)}
            icon={<Trash2 className="w-3.5 h-3.5" />}
          />
        </div>
      </div>
    );
  };

  return (
    <DaywellCard padding="md" radius="lg" className="space-y-3">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div className="flex items-center gap-2">
          <CheckSquare className="w-4 h-4 text-[var(--dw-primary)]" />
          <div>
            <h2 className="text-xs font-bold uppercase tracking-wider text-[var(--dw-text-primary)]">
              Tasks & Sections
            </h2>
            <p className="text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
              {allTasks.length > 0
                ? `${completedTasksCount}/${allTasks.length} tasks done (${tasksPct}%)`
                : 'Organize actionable tasks into project sections'}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-1.5">
          <DaywellButton
            label={isAddingSection ? 'Cancel Section' : 'Add Section'}
            variant="outlined"
            size="compact"
            leadingIcon={<FolderPlus className="w-3.5 h-3.5" />}
            onClick={() => {
              setIsAddingSection((v) => !v);
              setSectionError(null);
            }}
          />
          <DaywellButton
            label="Add Task"
            variant="tonal"
            size="compact"
            leadingIcon={<Plus className="w-3.5 h-3.5" />}
            onClick={() => openCreateTask()}
          />
        </div>
      </div>

      {allTasks.length > 0 && (
        <DaywellProgressBar
          value={tasksPct}
          label="Project tasks completion"
        />
      )}

      {isAddingSection && (
        <form
          onSubmit={handleCreateSection}
          className="p-3 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] space-y-2"
        >
          <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)]">
            New Section Name *
          </label>
          <div className="flex items-center gap-2">
            <input
              aria-label="New section name"
              type="text"
              placeholder="e.g. Research & Design"
              value={newSectionTitle}
              onChange={(e) => {
                setNewSectionTitle(e.target.value);
                if (sectionError) setSectionError(null);
              }}
              className="flex-1 min-h-[38px] px-3 py-1.5 bg-[var(--dw-card)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
            />
            <DaywellButton
              type="submit"
              label="Create"
              variant="primary"
              size="compact"
            />
          </div>
          {sectionError && (
            <p className="text-[11px] text-[var(--dw-error)]">{sectionError}</p>
          )}
        </form>
      )}

      {allTasks.length === 0 && sectionsView.sections.length === 0 && !isAddingSection ? (
        <p className="text-xs text-[var(--dw-text-muted)] italic">
          No tasks linked yet. Add a task or create sections to organize this project&apos;s work.
        </p>
      ) : (
        <div className="space-y-3">
          {sectionsView.sections.map((sectionGroup) => {
            const sec = sectionGroup.record;
            const secDone = sectionGroup.tasks.filter((t) =>
              isTaskCompleted(t)
            ).length;
            const isRenaming = renamingSectionId === sec.id;

            return (
              <div
                key={sec.id}
                className="p-3 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] space-y-2"
              >
                {isRenaming ? (
                  <div className="space-y-1.5">
                    <div className="flex items-center gap-1.5">
                      <input
                        aria-label={`Rename section ${sec.title ?? ''}`}
                        type="text"
                        value={renameTitle}
                        onChange={(e) => {
                          setRenameTitle(e.target.value);
                          if (renameError) setRenameError(null);
                        }}
                        className="flex-1 min-h-[34px] px-2.5 py-1 bg-[var(--dw-card)] rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                      />
                      <DaywellIconButton
                        label="Save section name"
                        size="compact"
                        tone="primary"
                        onClick={() => handleSaveRenameSection(sec.id)}
                        icon={<Check className="w-3.5 h-3.5" />}
                      />
                      <DaywellIconButton
                        label="Cancel rename section"
                        size="compact"
                        tone="muted"
                        onClick={() => {
                          setRenamingSectionId(null);
                          setRenameError(null);
                        }}
                        icon={<X className="w-3.5 h-3.5" />}
                      />
                    </div>
                    {renameError && (
                      <p className="text-[11px] text-[var(--dw-error)]">
                        {renameError}
                      </p>
                    )}
                  </div>
                ) : (
                  <div className="flex items-center justify-between gap-2">
                    <div className="flex items-center gap-2 min-w-0">
                      <span className="text-xs font-bold text-[var(--dw-text-primary)] truncate">
                        {sec.title}
                      </span>
                      <span className="text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
                        ({secDone}/{sectionGroup.tasks.length})
                      </span>
                    </div>
                    <div className="flex items-center gap-0.5 shrink-0">
                      <DaywellIconButton
                        label={`Add task to ${sec.title ?? 'section'}`}
                        size="compact"
                        tone="primary"
                        onClick={() => openCreateTask(sec.id)}
                        icon={<Plus className="w-3.5 h-3.5" />}
                      />
                      <DaywellIconButton
                        label={`Rename section ${sec.title ?? ''}`}
                        size="compact"
                        tone="muted"
                        onClick={() => {
                          setRenamingSectionId(sec.id);
                          setRenameTitle(sec.title ?? '');
                          setRenameError(null);
                        }}
                        icon={<Edit3 className="w-3.5 h-3.5" />}
                      />
                      <DaywellIconButton
                        label={`Delete section ${sec.title ?? ''}`}
                        size="compact"
                        tone="danger"
                        onClick={() => setPendingDeleteSection(sec)}
                        icon={<Trash2 className="w-3.5 h-3.5" />}
                      />
                    </div>
                  </div>
                )}

                {sectionGroup.tasks.length === 0 ? (
                  <p className="text-[11px] text-[var(--dw-text-muted)] italic">
                    No tasks in this section yet.
                  </p>
                ) : (
                  <div className="space-y-1.5">
                    {sectionGroup.tasks.map((t) => renderTaskRow(t))}
                  </div>
                )}
              </div>
            );
          })}

          {sectionsView.unsectionedTasks.length > 0 && (
            <div className="space-y-1.5">
              {sectionsView.sections.length > 0 && (
                <div className="flex items-center justify-between px-0.5">
                  <span className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
                    General ({sectionsView.unsectionedTasks.length})
                  </span>
                </div>
              )}
              {sectionsView.unsectionedTasks.map((t) => renderTaskRow(t))}
            </div>
          )}
        </div>
      )}

      {/* Task Create/Edit Modal Scoped to Project */}
      {isTaskModalOpen && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={editingTask ? 'Edit Project Task' : 'Add Project Task'}
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs"
          onClick={(e) => {
            if (e.target === e.currentTarget) setIsTaskModalOpen(false);
          }}
        >
          <div className="w-full max-w-md bg-[var(--dw-elevated)] rounded-[var(--dw-radius-xl)] p-5 shadow-2xl border border-[var(--dw-border)] space-y-3.5 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <h3 className="dw-type-title text-[var(--dw-text-primary)]">
                {editingTask ? 'Edit Project Task' : 'New Project Task'}
              </h3>
              <DaywellIconButton
                label="Close project task modal"
                size="compact"
                tone="muted"
                onClick={() => setIsTaskModalOpen(false)}
                icon={<X className="w-4 h-4" />}
              />
            </div>

            <form onSubmit={handleSaveTaskModal} className="space-y-3">
              <div>
                <label className="block dw-type-caption uppercase text-[var(--dw-text-secondary)] mb-1">
                  Task Title *
                </label>
                <input
                  aria-label="Project task title"
                  type="text"
                  placeholder="e.g. Draft onboarding copy"
                  value={taskTitle}
                  onChange={(e) => {
                    setTaskTitle(e.target.value);
                    if (taskFormError) setTaskFormError(null);
                  }}
                  className="w-full min-h-[40px] px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                />
              </div>

              <div>
                <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                  Description (Optional)
                </label>
                <textarea
                  rows={2}
                  value={taskDescription}
                  onChange={(e) => setTaskDescription(e.target.value)}
                  className="w-full px-3 py-2 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                />
              </div>

              <div className="grid grid-cols-2 gap-2.5">
                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Priority
                  </label>
                  <select
                    aria-label="Project task priority"
                    value={taskPriority}
                    onChange={(e) =>
                      setTaskPriority(e.target.value as TaskPriority)
                    }
                    className="w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  >
                    {CANONICAL_TASK_PRIORITIES.map((p) => (
                      <option key={p} value={p}>
                        {TASK_PRIORITY_LABELS[p]}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Status
                  </label>
                  <select
                    aria-label="Project task status"
                    value={taskStatus}
                    onChange={(e) => setTaskStatus(e.target.value as TaskStatus)}
                    className="w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  >
                    {CANONICAL_TASK_STATUSES.map((s) => (
                      <option key={s} value={s}>
                        {TASK_STATUS_LABELS[s]}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-2.5">
                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Section
                  </label>
                  <select
                    aria-label="Project task section"
                    value={taskSectionId}
                    onChange={(e) => setTaskSectionId(e.target.value)}
                    className="w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  >
                    <option value="">General / Unassigned</option>
                    {sectionsView.sections.map((s) => (
                      <option key={s.record.id} value={s.record.id}>
                        {s.record.title}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Milestone
                  </label>
                  <select
                    aria-label="Project task milestone"
                    value={taskMilestoneId}
                    onChange={(e) => setTaskMilestoneId(e.target.value)}
                    className="w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  >
                    <option value="">None</option>
                    {milestones.map((m) => (
                      <option key={m.id} value={m.id}>
                        {m.title}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-2.5">
                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Scheduled Date
                  </label>
                  <input
                    aria-label="Project task scheduled date"
                    type="date"
                    value={taskScheduledDate}
                    onChange={(e) => setTaskScheduledDate(e.target.value)}
                    className="w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  />
                </div>
                <div>
                  <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                    Due Date
                  </label>
                  <input
                    aria-label="Project task due date"
                    type="date"
                    value={taskDueDate}
                    onChange={(e) => setTaskDueDate(e.target.value)}
                    className="w-full min-h-[38px] px-2.5 py-1.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                  />
                </div>
              </div>

              {taskFormError && (
                <p className="text-[11px] text-[var(--dw-error)] font-medium">
                  {taskFormError}
                </p>
              )}

              <div className="flex items-center justify-between pt-2">
                {editingTask ? (
                  <DaywellButton
                    label="Delete Task"
                    variant="text"
                    size="compact"
                    onClick={() => setPendingDeleteTask(editingTask)}
                    className="!text-[var(--dw-error)]"
                  />
                ) : (
                  <div />
                )}
                <div className="flex items-center gap-2">
                  <DaywellButton
                    label="Cancel"
                    variant="outlined"
                    size="compact"
                    onClick={() => setIsTaskModalOpen(false)}
                  />
                  <DaywellButton
                    type="submit"
                    label={editingTask ? 'Save Changes' : 'Add Task'}
                    variant="primary"
                    size="compact"
                  />
                </div>
              </div>
            </form>
          </div>
        </div>
      )}

      <DaywellConfirmationDialog
        isOpen={Boolean(pendingDeleteSection)}
        title={`Remove section "${pendingDeleteSection?.title ?? ''}"?`}
        description="Tasks inside this section remain safely attached to your project under General."
        confirmLabel="Remove Section"
        destructive
        onCancel={() => setPendingDeleteSection(null)}
        onConfirm={handleConfirmDeleteSection}
      />

      <DaywellConfirmationDialog
        isOpen={Boolean(pendingDeleteTask)}
        title={`Delete task "${pendingDeleteTask?.title ?? ''}"?`}
        description="This permanently removes the task. You can undo immediately afterward."
        confirmLabel="Delete Task"
        destructive
        onCancel={() => setPendingDeleteTask(null)}
        onConfirm={handleConfirmDeleteTask}
      />
    </DaywellCard>
  );
}
