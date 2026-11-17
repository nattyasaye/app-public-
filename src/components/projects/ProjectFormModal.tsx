import React, { useEffect, useMemo, useRef, useState } from 'react';
import { CalendarDate } from '../../domain/date';
import {
  SharedGoal,
  SharedProject,
  SharedProjectBlockType,
  SharedProjectTrackingBlock,
} from '../../domain/sharedFoundation';
import {
  InlineBlockDraft,
  ProjectValidationError,
  parseCounterBlockConfig,
  projectsService,
} from '../../services/projectsService';
import { Layers, Plus, Trash2, X } from 'lucide-react';
import {
  DaywellButton,
  DaywellCard,
  DaywellIconButton,
  DaywellSelectField,
  DaywellStatusBadge,
  DaywellStatusBanner,
  DaywellTextField,
} from '../ui';
import { UnsavedChangesDialog } from '../UnsavedChangesDialog';

export interface ProjectFormModalProps {
  isOpen: boolean;
  editingProject?: SharedProject;
  existingBlocks?: SharedProjectTrackingBlock[];
  onClose: () => void;
  onSaved: (project: SharedProject) => void;
}

const BLOCK_TYPE_OPTIONS: { value: SharedProjectBlockType; label: string }[] = [
  { value: 'counter', label: 'Counter (tally / goal)' },
  { value: 'grouped_list', label: 'Grouped List (categories & items)' },
  { value: 'checklist', label: 'Checklist (to-do items)' },
  { value: 'schedule', label: 'Schedule (dated sessions / duration)' },
];

export function ProjectFormModal({
  isOpen,
  editingProject,
  existingBlocks = [],
  onClose,
  onSaved,
}: ProjectFormModalProps) {
  const isEditing = Boolean(editingProject);
  const titleRef = useRef<HTMLInputElement>(null);

  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [status, setStatus] = useState<SharedProject['status']>('active');
  const [startDate, setStartDate] = useState('');
  const [targetDate, setTargetDate] = useState('');
  const [goalId, setGoalId] = useState('');
  const [primarySelection, setPrimarySelection] = useState('');
  const [draftBlocks, setDraftBlocks] = useState<InlineBlockDraft[]>([]);

  // Inline block composer state
  const [isAddingDraft, setIsAddingDraft] = useState(false);
  const [draftType, setDraftType] = useState<SharedProjectBlockType>('counter');
  const [draftTitle, setDraftTitle] = useState('');
  const [draftUnitLabel, setDraftUnitLabel] = useState('');
  const [draftTargetValue, setDraftTargetValue] = useState('');
  const [draftDailyTargetValue, setDraftDailyTargetValue] = useState('');
  const [draftCounterMode, setDraftCounterMode] = useState<'direct' | 'rollup'>('direct');
  const [draftRollupSourceId, setDraftRollupSourceId] = useState('');
  const [draftShowGroupTotals, setDraftShowGroupTotals] = useState(true);
  const [draftGroupLabel, setDraftGroupLabel] = useState('');
  const [draftItemLabel, setDraftItemLabel] = useState('');
  const [draftScheduleRule, setDraftScheduleRule] = useState<
    'manual' | 'threshold_percent' | 'exact_duration'
  >('manual');
  const [draftThresholdPct, setDraftThresholdPct] = useState('80');
  const [draftTrackDuration, setDraftTrackDuration] = useState(true);

  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [draftErrorMsg, setDraftErrorMsg] = useState<string | null>(null);
  const [showUnsavedPrompt, setShowUnsavedPrompt] = useState(false);

  const goals: SharedGoal[] = useMemo(() => {
    if (!isOpen) return [];
    return projectsService.getGoals();
  }, [isOpen]);

  const activeExistingBlocks = useMemo(
    () => existingBlocks.filter((b) => !b.isArchived),
    [existingBlocks]
  );

  // Hydrate state when modal opens
  useEffect(() => {
    if (!isOpen) return;
    if (editingProject) {
      setTitle(editingProject.title);
      setDescription(editingProject.description ?? '');
      setStatus(editingProject.status);
      setStartDate(editingProject.startDate ?? '');
      setTargetDate(editingProject.targetDate ?? '');
      setGoalId(editingProject.goalId ?? '');
      const rawPrimary =
        typeof editingProject.customFields?.primaryBlockId === 'string'
          ? editingProject.customFields.primaryBlockId
          : '';
      setPrimarySelection(rawPrimary);
    } else {
      setTitle('');
      setDescription('');
      setStatus('active');
      setStartDate('');
      setTargetDate('');
      setGoalId('');
      setPrimarySelection('');
    }
    setDraftBlocks([]);
    setIsAddingDraft(false);
    setDraftType('counter');
    setDraftTitle('');
    setDraftUnitLabel('');
    setDraftTargetValue('');
    setDraftDailyTargetValue('');
    setDraftCounterMode('direct');
    setDraftRollupSourceId('');
    setDraftShowGroupTotals(true);
    setDraftGroupLabel('');
    setDraftItemLabel('');
    setDraftScheduleRule('manual');
    setDraftThresholdPct('80');
    setDraftTrackDuration(true);
    setErrorMsg(null);
    setDraftErrorMsg(null);
    setShowUnsavedPrompt(false);

    const timer = setTimeout(() => {
      titleRef.current?.focus();
    }, 50);
    return () => clearTimeout(timer);
  }, [isOpen, editingProject]);

  // Sibling blocks eligible as rollup source (cannot be another rollup counter)
  const eligibleRollupSources = useMemo(() => {
    const out: { id: string; title: string; blockType: SharedProjectBlockType }[] = [];
    for (const b of activeExistingBlocks) {
      if (b.blockType === 'counter') {
        const cfg = parseCounterBlockConfig(b.config);
        if (cfg.rollupSourceBlockId) continue;
      }
      out.push({ id: b.id, title: b.title, blockType: b.blockType });
    }
    for (const d of draftBlocks) {
      if (d.blockType === 'counter' && d.config?.rollupSourceBlockId) continue;
      out.push({ id: d.tempId, title: d.title, blockType: d.blockType });
    }
    return out;
  }, [activeExistingBlocks, draftBlocks]);

  const primaryBlockOptions = useMemo(() => {
    const opts: { value: string; label: string }[] = [
      { value: '', label: 'None (track each block separately)' },
    ];
    for (const b of activeExistingBlocks) {
      opts.push({ value: b.id, label: `${b.title} (${b.blockType.replace('_', ' ')})` });
    }
    for (const d of draftBlocks) {
      opts.push({
        value: d.tempId,
        label: `${d.title} (${d.blockType.replace('_', ' ')}) · new`,
      });
    }
    return opts;
  }, [activeExistingBlocks, draftBlocks]);

  const isDirty = useMemo(() => {
    if (!isOpen) return false;
    if (!editingProject) {
      return Boolean(
        title.trim() ||
          description.trim() ||
          startDate ||
          targetDate ||
          goalId ||
          draftBlocks.length > 0 ||
          draftTitle.trim()
      );
    }
    const origPrimary =
      typeof editingProject.customFields?.primaryBlockId === 'string'
        ? editingProject.customFields.primaryBlockId
        : '';
    return (
      title !== editingProject.title ||
      description !== (editingProject.description ?? '') ||
      status !== editingProject.status ||
      startDate !== (editingProject.startDate ?? '') ||
      targetDate !== (editingProject.targetDate ?? '') ||
      goalId !== (editingProject.goalId ?? '') ||
      primarySelection !== origPrimary ||
      draftBlocks.length > 0 ||
      Boolean(draftTitle.trim())
    );
  }, [
    isOpen,
    editingProject,
    title,
    description,
    status,
    startDate,
    targetDate,
    goalId,
    primarySelection,
    draftBlocks,
    draftTitle,
  ]);

  if (!isOpen) return null;

  const handleRequestClose = () => {
    if (isDirty) {
      setShowUnsavedPrompt(true);
    } else {
      onClose();
    }
  };

  const resetDraftComposer = () => {
    setIsAddingDraft(false);
    setDraftType('counter');
    setDraftTitle('');
    setDraftUnitLabel('');
    setDraftTargetValue('');
    setDraftDailyTargetValue('');
    setDraftCounterMode('direct');
    setDraftRollupSourceId('');
    setDraftShowGroupTotals(true);
    setDraftGroupLabel('');
    setDraftItemLabel('');
    setDraftScheduleRule('manual');
    setDraftThresholdPct('80');
    setDraftTrackDuration(true);
    setDraftErrorMsg(null);
  };

  const handleAddDraftBlock = () => {
    const cleanTitle = draftTitle.trim();
    if (!cleanTitle) {
      setDraftErrorMsg('Tracking block title is required.');
      return;
    }
    if (cleanTitle.length > 200) {
      setDraftErrorMsg('Tracking block title cannot exceed 200 characters.');
      return;
    }

    let parsedTarget: number | undefined;
    if (draftTargetValue.trim()) {
      const n = Number(draftTargetValue);
      if (!Number.isFinite(n) || n < 0) {
        setDraftErrorMsg('Target value must be a valid non-negative number.');
        return;
      }
      parsedTarget = n;
    }

    let parsedDailyTarget: number | undefined;
    if (draftDailyTargetValue.trim()) {
      const n = Number(draftDailyTargetValue);
      if (!Number.isFinite(n) || n < 0) {
        setDraftErrorMsg('Daily target must be a valid non-negative number.');
        return;
      }
      parsedDailyTarget = n;
    }

    let config: Record<string, unknown> = {};
    if (draftType === 'counter') {
      if (draftCounterMode === 'rollup') {
        if (!draftRollupSourceId) {
          setDraftErrorMsg('Select a source tracking block for this rollup counter.');
          return;
        }
        config = {
          rollupSourceBlockId: draftRollupSourceId,
          allowDirectLogging: false,
        };
      } else {
        config = { allowDirectLogging: true };
      }
    } else if (draftType === 'grouped_list') {
      config = {
        showGroupTotals: draftShowGroupTotals,
        showDailyTotals: true,
        ...(draftGroupLabel.trim() ? { groupLabel: draftGroupLabel.trim() } : {}),
        ...(draftItemLabel.trim() ? { itemLabel: draftItemLabel.trim() } : {}),
      };
    } else if (draftType === 'checklist') {
      config = { allowReorder: true };
    } else if (draftType === 'schedule') {
      const pct = Number(draftThresholdPct);
      const ratio =
        draftScheduleRule === 'threshold_percent'
          ? Math.max(0.05, Math.min(1, (Number.isFinite(pct) ? pct : 80) / 100))
          : 1.0;
      config = {
        completionRule: draftScheduleRule,
        autoCompleteThresholdRatio: ratio,
        trackActualDuration: draftTrackDuration,
      };
    }

    const tempId = `draft-${Date.now()}-${Math.floor(Math.random() * 10000)}`;
    const nextDraft: InlineBlockDraft = {
      tempId,
      blockType: draftType,
      title: cleanTitle,
      ...(draftUnitLabel.trim() ? { unitLabel: draftUnitLabel.trim() } : {}),
      ...(parsedTarget !== undefined ? { targetValue: parsedTarget } : {}),
      ...(parsedDailyTarget !== undefined
        ? { dailyTargetValue: parsedDailyTarget }
        : {}),
      config,
    };

    setDraftBlocks((prev) => {
      const updated = [...prev, nextDraft];
      if (!primarySelection && activeExistingBlocks.length === 0 && updated.length === 1) {
        setPrimarySelection(tempId);
      }
      return updated;
    });
    resetDraftComposer();
  };

  const handleRemoveDraft = (tempId: string) => {
    setDraftBlocks((prev) =>
      prev
        .filter((b) => b.tempId !== tempId)
        .filter((b) => b.config?.rollupSourceBlockId !== tempId)
    );
    if (primarySelection === tempId) {
      setPrimarySelection('');
    }
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg(null);

    const cleanTitle = title.trim();
    if (!cleanTitle) {
      setErrorMsg('Project title is required.');
      titleRef.current?.focus();
      return;
    }
    if (startDate && !CalendarDate.tryParse(startDate)) {
      setErrorMsg('Start date must be valid YYYY-MM-DD.');
      return;
    }
    if (targetDate && !CalendarDate.tryParse(targetDate)) {
      setErrorMsg('Target date must be valid YYYY-MM-DD.');
      return;
    }
    if (startDate && targetDate && targetDate < startDate) {
      setErrorMsg('Target date cannot be earlier than start date.');
      return;
    }

    try {
      let saved: SharedProject;
      if (editingProject) {
        const isDraftPrimary = draftBlocks.some((d) => d.tempId === primarySelection);
        saved = projectsService.updateProjectDetails({
          projectId: editingProject.id,
          title: cleanTitle,
          description: description.trim() || undefined,
          status,
          startDate: startDate || undefined,
          targetDate: targetDate || undefined,
          goalId: goalId || undefined,
          primaryBlockId: !isDraftPrimary && primarySelection ? primarySelection : undefined,
          primaryDraftTempId: isDraftPrimary ? primarySelection : undefined,
          newBlocks: draftBlocks,
        });
      } else {
        saved = projectsService.createProjectWithBlocks({
          title: cleanTitle,
          description: description.trim() || undefined,
          status,
          startDate: startDate || undefined,
          targetDate: targetDate || undefined,
          goalId: goalId || undefined,
          primaryDraftTempId: primarySelection || undefined,
          blocks: draftBlocks,
        });
      }
      onSaved(saved);
    } catch (err) {
      if (err instanceof ProjectValidationError) {
        setErrorMsg(err.message);
      } else {
        setErrorMsg(err instanceof Error ? err.message : 'Unable to save project.');
      }
    }
  };

  return (
    <>
      <div
        role="dialog"
        aria-modal="true"
        aria-label={isEditing ? 'Edit Project' : 'New Project'}
        className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs"
        onClick={(e) => {
          if (e.target === e.currentTarget) handleRequestClose();
        }}
      >
        <div className="w-full max-w-lg bg-[var(--dw-elevated)] rounded-[var(--dw-radius-xl)] p-5 shadow-2xl border border-[var(--dw-border)] space-y-4 max-h-[90vh] overflow-y-auto">
          <div className="flex items-center justify-between">
            <h2 className="dw-type-title text-[var(--dw-text-primary)]">
              {isEditing ? 'Edit Project' : 'New Project'}
            </h2>
            <DaywellIconButton
              label="Close project dialog"
              size="compact"
              tone="muted"
              onClick={handleRequestClose}
              icon={<X className="w-4 h-4" />}
            />
          </div>

          {errorMsg ? <DaywellStatusBanner tone="error" message={errorMsg} /> : null}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block dw-type-label text-[var(--dw-text-secondary)] mb-1">
                Project Title <span className="text-[var(--dw-error)]">*</span>
              </label>
              <input
                ref={titleRef}
                type="text"
                placeholder="e.g. Read 12 Books, Website Redesign, Study Plan"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                maxLength={200}
                className="w-full min-h-[44px] rounded-[var(--dw-radius-md)] bg-[var(--dw-card)] text-[var(--dw-text-primary)] placeholder:text-[var(--dw-text-muted)] border border-[var(--dw-border)] px-3 py-2 text-sm focus:outline-none focus:border-[var(--dw-primary)] focus:ring-2 focus:ring-[var(--dw-primary)]/25"
              />
            </div>

            <div className="space-y-1.5">
              <label className="block dw-type-label text-[var(--dw-text-secondary)]">
                Description (Optional)
              </label>
              <textarea
                rows={2}
                placeholder="What does completing this project look like?"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                className="w-full rounded-[var(--dw-radius-md)] bg-[var(--dw-card)] text-[var(--dw-text-primary)] placeholder:text-[var(--dw-text-muted)] border border-[var(--dw-border)] px-3 py-2 text-xs focus:outline-none focus:border-[var(--dw-primary)] focus:ring-2 focus:ring-[var(--dw-primary)]/25"
              />
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-2.5">
              <DaywellSelectField
                label="Status"
                value={status}
                onChange={(e) =>
                  setStatus(e.target.value as SharedProject['status'])
                }
                options={[
                  { value: 'active', label: 'Active' },
                  { value: 'on_hold', label: 'On Hold' },
                  { value: 'completed', label: 'Completed' },
                ]}
              />
              <DaywellTextField
                label="Start Date"
                type="date"
                value={startDate}
                onChange={(e) => setStartDate(e.target.value)}
              />
              <DaywellTextField
                label="Target Date"
                type="date"
                value={targetDate}
                onChange={(e) => setTargetDate(e.target.value)}
              />
            </div>

            {(goals.length > 0 || goalId) && (
              <DaywellSelectField
                label="Linked Goal (Optional)"
                value={goalId}
                onChange={(e) => setGoalId(e.target.value)}
                options={[
                  { value: '', label: 'No goal linked' },
                  ...goals.map((g) => ({ value: g.id, label: g.title })),
                  ...(goalId && !goals.some((g) => g.id === goalId)
                    ? [{ value: goalId, label: `Goal (${goalId})` }]
                    : []),
                ]}
              />
            )}

            {/* Inline Tracking Blocks Section */}
            <div className="pt-3 border-t border-[var(--dw-divider)] space-y-3">
              <div className="flex items-center justify-between gap-2">
                <div>
                  <h3 className="dw-type-label text-[var(--dw-text-primary)]">
                    Tracking Blocks (Optional)
                  </h3>
                  <p className="text-[11px] text-[var(--dw-text-muted)]">
                    Add counters, grouped lists, checklists, or schedules now or later in details.
                  </p>
                </div>
                {!isAddingDraft && (
                  <DaywellButton
                    label="Add Block"
                    variant="tonal"
                    size="compact"
                    leadingIcon={<Plus className="w-3.5 h-3.5" />}
                    onClick={() => {
                      setIsAddingDraft(true);
                      setDraftErrorMsg(null);
                    }}
                  />
                )}
              </div>

              {activeExistingBlocks.length > 0 && (
                <div className="space-y-1.5">
                  <p className="text-[11px] font-medium text-[var(--dw-text-muted)]">
                    Configured blocks ({activeExistingBlocks.length})
                  </p>
                  {activeExistingBlocks.map((b) => (
                    <div
                      key={b.id}
                      className="flex items-center justify-between gap-2 px-3 py-2 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-xs"
                    >
                      <div className="flex items-center gap-2 min-w-0">
                        <Layers className="w-3.5 h-3.5 text-[var(--dw-primary)] shrink-0" />
                        <span className="font-semibold text-[var(--dw-text-primary)] truncate">
                          {b.title}
                        </span>
                      </div>
                      <span className="text-[11px] text-[var(--dw-text-muted)] shrink-0 capitalize">
                        {b.blockType.replace('_', ' ')}
                      </span>
                    </div>
                  ))}
                </div>
              )}

              {draftBlocks.length > 0 && (
                <div className="space-y-1.5">
                  {draftBlocks.map((d) => (
                    <div
                      key={d.tempId}
                      className="flex items-center justify-between gap-2 px-3 py-2 rounded-[var(--dw-radius-md)] bg-[var(--dw-card)] border border-[var(--dw-border)] text-xs"
                    >
                      <div className="min-w-0 space-y-0.5">
                        <div className="flex items-center gap-2">
                          <span className="font-semibold text-[var(--dw-text-primary)] truncate">
                            {d.title}
                          </span>
                          <DaywellStatusBadge
                            tone="neutral"
                            showIcon={false}
                            label={d.blockType.replace('_', ' ')}
                          />
                        </div>
                        <p className="text-[11px] text-[var(--dw-text-muted)]">
                          {d.blockType === 'counter' && d.config?.rollupSourceBlockId
                            ? 'Rollup counter (read-only aggregate)'
                            : [
                                d.targetValue !== undefined
                                  ? `Target: ${d.targetValue}${d.unitLabel ? ` ${d.unitLabel}` : ''}`
                                  : null,
                                d.dailyTargetValue !== undefined
                                  ? `Daily: ${d.dailyTargetValue}${d.unitLabel ? ` ${d.unitLabel}` : ''}`
                                  : null,
                              ]
                                .filter(Boolean)
                                .join(' · ') || 'Ready to track'}
                        </p>
                      </div>
                      <DaywellIconButton
                        label={`Remove block ${d.title}`}
                        size="compact"
                        tone="danger"
                        onClick={() => handleRemoveDraft(d.tempId)}
                        icon={<Trash2 className="w-3.5 h-3.5" />}
                      />
                    </div>
                  ))}
                </div>
              )}

              {isAddingDraft && (
                <DaywellCard variant="subtle" padding="compact" radius="md" className="space-y-3">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-bold text-[var(--dw-text-primary)]">
                      Configure New Block
                    </span>
                    <DaywellButton
                      label="Cancel"
                      variant="text"
                      size="compact"
                      onClick={resetDraftComposer}
                    />
                  </div>

                  {draftErrorMsg ? (
                    <DaywellStatusBanner tone="error" message={draftErrorMsg} />
                  ) : null}

                  <DaywellSelectField
                    label="Block Type"
                    value={draftType}
                    onChange={(e) => {
                      setDraftType(e.target.value as SharedProjectBlockType);
                      setDraftErrorMsg(null);
                    }}
                    options={BLOCK_TYPE_OPTIONS}
                  />

                  <DaywellTextField
                    label="Block Title *"
                    placeholder={
                      draftType === 'counter'
                        ? 'e.g. Pages read'
                        : draftType === 'grouped_list'
                        ? 'e.g. Study chapters'
                        : draftType === 'checklist'
                        ? 'e.g. Launch preparation'
                        : 'e.g. Practice sessions'
                    }
                    value={draftTitle}
                    onChange={(e) => setDraftTitle(e.target.value)}
                  />

                  <div className="grid grid-cols-3 gap-2">
                    <DaywellTextField
                      label="Unit"
                      placeholder={draftType === 'schedule' ? 'min' : 'e.g. pages'}
                      value={draftUnitLabel}
                      onChange={(e) => setDraftUnitLabel(e.target.value)}
                    />
                    <DaywellTextField
                      label="Target"
                      type="number"
                      min="0"
                      step="any"
                      placeholder="Optional"
                      value={draftTargetValue}
                      onChange={(e) => setDraftTargetValue(e.target.value)}
                    />
                    <DaywellTextField
                      label="Daily Target"
                      type="number"
                      min="0"
                      step="any"
                      placeholder="Optional"
                      value={draftDailyTargetValue}
                      onChange={(e) => setDraftDailyTargetValue(e.target.value)}
                    />
                  </div>

                  {draftType === 'counter' && eligibleRollupSources.length > 0 && (
                    <div className="space-y-2 pt-1">
                      <DaywellSelectField
                        label="Counter Mode"
                        value={draftCounterMode}
                        onChange={(e) =>
                          setDraftCounterMode(e.target.value as 'direct' | 'rollup')
                        }
                        options={[
                          { value: 'direct', label: 'Direct logging counter' },
                          {
                            value: 'rollup',
                            label: 'Rollup counter (mirrors another block)',
                          },
                        ]}
                      />
                      {draftCounterMode === 'rollup' && (
                        <DaywellSelectField
                          label="Rollup Source Block"
                          value={draftRollupSourceId}
                          onChange={(e) => setDraftRollupSourceId(e.target.value)}
                          options={[
                            { value: '', label: 'Select a block to roll up...' },
                            ...eligibleRollupSources.map((s) => ({
                              value: s.id,
                              label: `${s.title} (${s.blockType.replace('_', ' ')})`,
                            })),
                          ]}
                        />
                      )}
                    </div>
                  )}

                  {draftType === 'grouped_list' && (
                    <div className="space-y-2 pt-1">
                      <label className="flex items-center gap-2 text-xs text-[var(--dw-text-secondary)] cursor-pointer">
                        <input
                          type="checkbox"
                          checked={draftShowGroupTotals}
                          onChange={(e) => setDraftShowGroupTotals(e.target.checked)}
                          className="w-4 h-4 accent-[var(--dw-primary)]"
                        />
                        <span>Show per-group totals</span>
                      </label>
                      <div className="grid grid-cols-2 gap-2">
                        <DaywellTextField
                          label="Group Term (Optional)"
                          placeholder="e.g. Category"
                          value={draftGroupLabel}
                          onChange={(e) => setDraftGroupLabel(e.target.value)}
                        />
                        <DaywellTextField
                          label="Item Term (Optional)"
                          placeholder="e.g. Task"
                          value={draftItemLabel}
                          onChange={(e) => setDraftItemLabel(e.target.value)}
                        />
                      </div>
                    </div>
                  )}

                  {draftType === 'schedule' && (
                    <div className="space-y-2 pt-1">
                      <DaywellSelectField
                        label="Session Completion Rule"
                        value={draftScheduleRule}
                        onChange={(e) =>
                          setDraftScheduleRule(
                            e.target.value as
                              | 'manual'
                              | 'threshold_percent'
                              | 'exact_duration'
                          )
                        }
                        options={[
                          { value: 'manual', label: 'Manual checkbox completion' },
                          {
                            value: 'threshold_percent',
                            label: 'Auto-complete at percentage of planned duration',
                          },
                          {
                            value: 'exact_duration',
                            label: 'Auto-complete when full planned duration is logged',
                          },
                        ]}
                      />
                      {draftScheduleRule === 'threshold_percent' && (
                        <DaywellTextField
                          label="Completion Threshold (%)"
                          type="number"
                          min="1"
                          max="100"
                          value={draftThresholdPct}
                          onChange={(e) => setDraftThresholdPct(e.target.value)}
                        />
                      )}
                      <label className="flex items-center gap-2 text-xs text-[var(--dw-text-secondary)] cursor-pointer">
                        <input
                          type="checkbox"
                          checked={draftTrackDuration}
                          onChange={(e) => setDraftTrackDuration(e.target.checked)}
                          className="w-4 h-4 accent-[var(--dw-primary)]"
                        />
                        <span>Track logged duration against planned minutes</span>
                      </label>
                    </div>
                  )}

                  <div className="flex justify-end">
                    <DaywellButton
                      label="Add This Block"
                      variant="secondary"
                      size="compact"
                      onClick={handleAddDraftBlock}
                    />
                  </div>
                </DaywellCard>
              )}

              {primaryBlockOptions.length > 1 && (
                <DaywellSelectField
                  label="Primary Progress Block (Optional)"
                  value={primarySelection}
                  onChange={(e) => setPrimarySelection(e.target.value)}
                  options={primaryBlockOptions}
                />
              )}
            </div>

            <div className="flex items-center justify-end gap-2 pt-2 border-t border-[var(--dw-divider)]">
              <DaywellButton
                label="Cancel"
                variant="outlined"
                onClick={handleRequestClose}
              />
              <DaywellButton
                type="submit"
                label={isEditing ? 'Save Project' : 'Create Project'}
                variant="primary"
                disabled={!title.trim()}
              />
            </div>
          </form>
        </div>
      </div>

      <UnsavedChangesDialog
        isOpen={showUnsavedPrompt}
        onContinueEditing={() => setShowUnsavedPrompt(false)}
        onDiscardChanges={() => {
          setShowUnsavedPrompt(false);
          onClose();
        }}
      />
    </>
  );
}
