import React, { useState } from 'react';
import { CalendarDate, SharedDateFormatter } from '../../domain/date';
import { SharedMilestone } from '../../domain/sharedFoundation';
import { DaywellTaskRecord } from '../../domain/taskOperations';
import { projectsService } from '../../services/projectsService';
import { Calendar, Check, Edit3, Flag, Plus, Trash2, X } from 'lucide-react';
import {
  DaywellButton,
  DaywellCard,
  DaywellConfirmationDialog,
  DaywellIconButton,
  DaywellProgressBar,
  DaywellStatusBadge,
} from '../ui';

export interface ProjectMilestonesSectionProps {
  projectId: string;
  milestones: SharedMilestone[];
  linkedTasks: DaywellTaskRecord[];
  onRefresh: () => void;
  onNotifyUndo?: (message: string, undoAction: () => void) => void;
}

export function ProjectMilestonesSection({
  projectId,
  milestones,
  linkedTasks,
  onRefresh,
  onNotifyUndo,
}: ProjectMilestonesSectionProps) {
  const [isAdding, setIsAdding] = useState(false);
  const [newTitle, setNewTitle] = useState('');
  const [newDueDate, setNewDueDate] = useState('');
  const [formError, setFormError] = useState<string | null>(null);

  const [editingId, setEditingId] = useState<string | null>(null);
  const [editTitle, setEditTitle] = useState('');
  const [editDueDate, setEditDueDate] = useState('');
  const [editError, setEditError] = useState<string | null>(null);

  const [pendingDelete, setPendingDelete] = useState<SharedMilestone | null>(
    null
  );

  const completedCount = milestones.filter((m) => m.isCompleted).length;
  const milestonePct =
    milestones.length > 0
      ? Math.round((completedCount / milestones.length) * 100)
      : 0;

  const taskCountByMilestone = new Map<string, { total: number; done: number }>();
  for (const t of linkedTasks) {
    if (!t.milestoneId || t.isArchived || t.status === 'cancelled') continue;
    const prev = taskCountByMilestone.get(t.milestoneId) ?? { total: 0, done: 0 };
    const isDone = t.completed === true || t.status === 'completed';
    taskCountByMilestone.set(t.milestoneId, {
      total: prev.total + 1,
      done: prev.done + (isDone ? 1 : 0),
    });
  }

  const handleCreate = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = newTitle.trim();
    if (!trimmed) {
      setFormError('Milestone title is required.');
      return;
    }
    try {
      projectsService.createMilestone({
        projectId,
        title: trimmed,
        dueDate: newDueDate.trim() || undefined,
      });
      setNewTitle('');
      setNewDueDate('');
      setFormError(null);
      setIsAdding(false);
      onRefresh();
    } catch (err) {
      setFormError(
        err instanceof Error ? err.message : 'Unable to create milestone.'
      );
    }
  };

  const handleStartEdit = (m: SharedMilestone) => {
    setEditingId(m.id);
    setEditTitle(m.title);
    setEditDueDate(m.dueDate ?? '');
    setEditError(null);
  };

  const handleSaveEdit = (m: SharedMilestone) => {
    const trimmed = editTitle.trim();
    if (!trimmed) {
      setEditError('Milestone title is required.');
      return;
    }
    try {
      projectsService.updateMilestone({
        milestoneId: m.id,
        title: trimmed,
        dueDate: editDueDate.trim() || undefined,
        isCompleted: m.isCompleted,
      });
      setEditingId(null);
      setEditTitle('');
      setEditDueDate('');
      setEditError(null);
      onRefresh();
    } catch (err) {
      setEditError(
        err instanceof Error ? err.message : 'Unable to update milestone.'
      );
    }
  };

  const handleToggle = (m: SharedMilestone) => {
    const previousState = m.isCompleted;
    projectsService.toggleMilestone(m.id, !previousState);
    onRefresh();
    onNotifyUndo?.(
      !previousState
        ? `Completed milestone "${m.title}"`
        : `Reopened milestone "${m.title}"`,
      () => {
        projectsService.toggleMilestone(m.id, previousState);
        onRefresh();
      }
    );
  };

  const handleConfirmDelete = () => {
    if (!pendingDelete) return;
    const target = pendingDelete;
    const { deleted, detachedTaskIds } = projectsService.deleteMilestone(
      target.id
    );
    setPendingDelete(null);
    onRefresh();
    if (deleted) {
      onNotifyUndo?.(`Deleted milestone "${deleted.title}"`, () => {
        projectsService.restoreMilestoneSnapshot(deleted, detachedTaskIds);
        onRefresh();
      });
    }
  };

  return (
    <DaywellCard padding="md" radius="lg" className="space-y-3">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div className="flex items-center gap-2">
          <Flag className="w-4 h-4 text-[var(--dw-primary)]" />
          <div>
            <h2 className="text-xs font-bold uppercase tracking-wider text-[var(--dw-text-primary)]">
              Milestones
            </h2>
            <p className="text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
              {milestones.length > 0
                ? `${completedCount}/${milestones.length} complete (${milestonePct}%)`
                : 'Optional checkpoints to pace this project'}
            </p>
          </div>
        </div>

        <DaywellButton
          label={isAdding ? 'Close' : 'Add Milestone'}
          variant={isAdding ? 'outlined' : 'tonal'}
          size="compact"
          leadingIcon={isAdding ? <X className="w-3.5 h-3.5" /> : <Plus className="w-3.5 h-3.5" />}
          onClick={() => {
            setIsAdding((v) => !v);
            setFormError(null);
          }}
        />
      </div>

      {milestones.length > 0 && (
        <DaywellProgressBar
          value={milestonePct}
          label="Project milestones completion"
        />
      )}

      {isAdding && (
        <form
          onSubmit={handleCreate}
          className="p-3 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] space-y-2.5"
        >
          <div className="grid grid-cols-1 sm:grid-cols-12 gap-2">
            <div className="sm:col-span-7">
              <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                Milestone Title *
              </label>
              <input
                aria-label="New milestone title"
                type="text"
                placeholder="e.g. Phase 1 Prototype Sign-off"
                value={newTitle}
                onChange={(e) => {
                  setNewTitle(e.target.value);
                  if (formError) setFormError(null);
                }}
                className="w-full min-h-[38px] px-3 py-1.5 bg-[var(--dw-card)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
              />
            </div>
            <div className="sm:col-span-5">
              <label className="block dw-type-caption uppercase text-[var(--dw-text-muted)] mb-1">
                Due Date (Optional)
              </label>
              <input
                aria-label="New milestone due date"
                type="date"
                value={newDueDate}
                onChange={(e) => setNewDueDate(e.target.value)}
                className="w-full min-h-[38px] px-3 py-1.5 bg-[var(--dw-card)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
              />
            </div>
          </div>
          {formError && (
            <p className="text-[11px] text-[var(--dw-error)] font-medium">
              {formError}
            </p>
          )}
          <div className="flex items-center justify-end gap-2">
            <DaywellButton
              label="Cancel"
              variant="outlined"
              size="compact"
              onClick={() => {
                setIsAdding(false);
                setNewTitle('');
                setNewDueDate('');
                setFormError(null);
              }}
            />
            <DaywellButton
              type="submit"
              label="Save Milestone"
              variant="primary"
              size="compact"
            />
          </div>
        </form>
      )}

      {milestones.length === 0 && !isAdding ? (
        <p className="text-xs text-[var(--dw-text-muted)] italic">
          No milestones yet. Add key checkpoints and optionally link tasks to them.
        </p>
      ) : (
        <div className="space-y-2">
          {milestones.map((m) => {
            const isEditing = editingId === m.id;
            const parsedDue = m.dueDate ? CalendarDate.tryParse(m.dueDate) : null;
            const linkedStats = taskCountByMilestone.get(m.id);

            return (
              <div
                key={m.id}
                className="p-2.5 bg-[var(--dw-surface-subtle)] rounded-[var(--dw-radius-md)] border border-[var(--dw-border)]"
              >
                {isEditing ? (
                  <div className="space-y-2">
                    <div className="grid grid-cols-1 sm:grid-cols-12 gap-2">
                      <input
                        aria-label={`Edit milestone ${m.title}`}
                        type="text"
                        value={editTitle}
                        onChange={(e) => {
                          setEditTitle(e.target.value);
                          if (editError) setEditError(null);
                        }}
                        className="sm:col-span-7 min-h-[36px] px-2.5 py-1 bg-[var(--dw-card)] rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                      />
                      <input
                        aria-label={`Edit milestone due date ${m.title}`}
                        type="date"
                        value={editDueDate}
                        onChange={(e) => setEditDueDate(e.target.value)}
                        className="sm:col-span-5 min-h-[36px] px-2.5 py-1 bg-[var(--dw-card)] rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-primary)] outline-none focus:border-[var(--dw-primary)]"
                      />
                    </div>
                    {editError && (
                      <p className="text-[11px] text-[var(--dw-error)]">
                        {editError}
                      </p>
                    )}
                    <div className="flex items-center justify-end gap-1.5">
                      <DaywellButton
                        label="Cancel"
                        variant="outlined"
                        size="compact"
                        onClick={() => {
                          setEditingId(null);
                          setEditError(null);
                        }}
                      />
                      <DaywellButton
                        label="Save"
                        variant="primary"
                        size="compact"
                        onClick={() => handleSaveEdit(m)}
                      />
                    </div>
                  </div>
                ) : (
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-start gap-2.5 min-w-0 flex-1">
                      <button
                        type="button"
                        aria-label={
                          m.isCompleted
                            ? `Reopen milestone ${m.title}`
                            : `Complete milestone ${m.title}`
                        }
                        onClick={() => handleToggle(m)}
                        className={`w-4 h-4 mt-0.5 rounded-[var(--dw-radius-sm)] border flex items-center justify-center shrink-0 cursor-pointer transition-colors ${
                          m.isCompleted
                            ? 'bg-[var(--dw-primary)] border-[var(--dw-primary)] text-[var(--dw-on-primary)]'
                            : 'border-[var(--dw-border)] bg-[var(--dw-card)] hover:border-[var(--dw-primary)]'
                        }`}
                      >
                        {m.isCompleted && <Check className="w-3 h-3 stroke-[3]" />}
                      </button>

                      <div className="min-w-0 space-y-1">
                        <p
                          className={`text-xs font-semibold leading-snug ${
                            m.isCompleted
                              ? 'line-through text-[var(--dw-text-muted)]'
                              : 'text-[var(--dw-text-primary)]'
                          }`}
                        >
                          {m.title}
                        </p>
                        <div className="flex flex-wrap items-center gap-2 text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
                          <DaywellStatusBadge
                            tone={m.isCompleted ? 'success' : 'neutral'}
                            showIcon={false}
                            label={m.isCompleted ? 'Completed' : 'Pending'}
                          />
                          {m.dueDate && (
                            <span className="flex items-center gap-1">
                              <Calendar className="w-3 h-3" />
                              {parsedDue
                                ? SharedDateFormatter.formatDual(parsedDue, false)
                                : m.dueDate}
                            </span>
                          )}
                          {linkedStats && (
                            <span>
                              {linkedStats.done}/{linkedStats.total}{' '}
                              {linkedStats.total === 1 ? 'task' : 'tasks'}
                            </span>
                          )}
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center gap-0.5 shrink-0">
                      <DaywellIconButton
                        label={`Edit milestone ${m.title}`}
                        size="compact"
                        tone="muted"
                        onClick={() => handleStartEdit(m)}
                        icon={<Edit3 className="w-3.5 h-3.5" />}
                      />
                      <DaywellIconButton
                        label={`Delete milestone ${m.title}`}
                        size="compact"
                        tone="danger"
                        onClick={() => setPendingDelete(m)}
                        icon={<Trash2 className="w-3.5 h-3.5" />}
                      />
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      <DaywellConfirmationDialog
        isOpen={Boolean(pendingDelete)}
        title={`Delete milestone "${pendingDelete?.title ?? ''}"?`}
        description="Tasks linked to this milestone will remain safe inside this project and have their milestone link cleared."
        confirmLabel="Delete Milestone"
        destructive
        onCancel={() => setPendingDelete(null)}
        onConfirm={handleConfirmDelete}
      />
    </DaywellCard>
  );
}
