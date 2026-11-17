import React, { useMemo, useState } from 'react';
import { CalendarDate, SharedDateFormatter } from '../../domain/date';
import { ProjectBlockProgressMetric } from '../../domain/projectsEngine';
import {
  SharedProject,
  SharedProjectBlockType,
  SharedProjectTrackingBlock,
  SharedProjectTrackingRecord,
} from '../../domain/sharedFoundation';
import {
  ProjectValidationError,
  formatNumber,
  parseCounterBlockConfig,
  parseScheduleBlockConfig,
  projectsService,
} from '../../services/projectsService';
import {
  Archive,
  Check,
  ChevronDown,
  ChevronRight,
  Edit3,
  FolderPlus,
  Plus,
  RotateCcw,
  Star,
  Trash2,
  X,
} from 'lucide-react';
import {
  DaywellButton,
  DaywellCard,
  DaywellConfirmationDialog,
  DaywellEmptyState,
  DaywellIconButton,
  DaywellProgressBar,
  DaywellSearchField,
  DaywellSectionHeader,
  DaywellSelectField,
  DaywellStatusBadge,
  DaywellStatusBanner,
  DaywellTextField,
} from '../ui';

export interface ProjectTrackingBlocksSectionProps {
  project: SharedProject;
  blocks: SharedProjectTrackingBlock[];
  records: SharedProjectTrackingRecord[];
  blockMetrics: ProjectBlockProgressMetric[];
  primaryBlockId?: string;
  onRefresh: () => void;
}

export function ProjectTrackingBlocksSection({
  project,
  blocks,
  records,
  blockMetrics,
  primaryBlockId,
  onRefresh,
}: ProjectTrackingBlocksSectionProps) {
  const [actionError, setActionError] = useState<string | null>(null);
  const [showArchivedBlocks, setShowArchivedBlocks] = useState(false);

  // Block composer modal state (add or edit metadata; blockType is locked when editing)
  const [blockModalOpen, setBlockModalOpen] = useState(false);
  const [editingBlock, setEditingBlock] =
    useState<SharedProjectTrackingBlock | undefined>(undefined);
  const [blkType, setBlkType] = useState<SharedProjectBlockType>('counter');
  const [blkTitle, setBlkTitle] = useState('');
  const [blkUnit, setBlkUnit] = useState('');
  const [blkTarget, setBlkTarget] = useState('');
  const [blkDailyTarget, setBlkDailyTarget] = useState('');
  const [blkSetPrimary, setBlkSetPrimary] = useState(false);
  const [blkCounterMode, setBlkCounterMode] = useState<'direct' | 'rollup'>('direct');
  const [blkRollupSourceId, setBlkRollupSourceId] = useState('');
  const [blkShowGroupTotals, setBlkShowGroupTotals] = useState(true);
  const [blkGroupLabel, setBlkGroupLabel] = useState('');
  const [blkItemLabel, setBlkItemLabel] = useState('');
  const [blkScheduleRule, setBlkScheduleRule] = useState<
    'manual' | 'threshold_percent' | 'exact_duration'
  >('manual');
  const [blkThresholdPct, setBlkThresholdPct] = useState('80');
  const [blkTrackDuration, setBlkTrackDuration] = useState(true);
  const [blkModalError, setBlkModalError] = useState<string | null>(null);

  // Confirm delete block
  const [blockToDelete, setBlockToDelete] =
    useState<SharedProjectTrackingBlock | null>(null);

  const metricByBlockId = useMemo(
    () => new Map(blockMetrics.map((m) => [m.blockId, m])),
    [blockMetrics]
  );

  const activeBlocks = useMemo(
    () => blocks.filter((b) => !b.isArchived),
    [blocks]
  );
  const archivedBlocks = useMemo(
    () => blocks.filter((b) => b.isArchived),
    [blocks]
  );

  const rollupSourceOptions = useMemo(() => {
    return activeBlocks.filter((b) => {
      if (editingBlock && b.id === editingBlock.id) return false;
      if (b.blockType === 'counter') {
        const cfg = parseCounterBlockConfig(b.config);
        if (cfg.rollupSourceBlockId) return false;
      }
      return true;
    });
  }, [activeBlocks, editingBlock]);

  const openAddBlock = () => {
    setEditingBlock(undefined);
    setBlkType('counter');
    setBlkTitle('');
    setBlkUnit('');
    setBlkTarget('');
    setBlkDailyTarget('');
    setBlkSetPrimary(!primaryBlockId && activeBlocks.length === 0);
    setBlkCounterMode('direct');
    setBlkRollupSourceId('');
    setBlkShowGroupTotals(true);
    setBlkGroupLabel('');
    setBlkItemLabel('');
    setBlkScheduleRule('manual');
    setBlkThresholdPct('80');
    setBlkTrackDuration(true);
    setBlkModalError(null);
    setBlockModalOpen(true);
  };

  const openEditBlock = (block: SharedProjectTrackingBlock) => {
    setEditingBlock(block);
    setBlkType(block.blockType);
    setBlkTitle(block.title);
    setBlkUnit(block.unitLabel ?? '');
    setBlkTarget(
      block.targetValue !== undefined ? String(block.targetValue) : ''
    );
    setBlkDailyTarget(
      block.dailyTargetValue !== undefined ? String(block.dailyTargetValue) : ''
    );
    setBlkSetPrimary(primaryBlockId === block.id);

    if (block.blockType === 'counter') {
      const cfg = parseCounterBlockConfig(block.config);
      setBlkCounterMode(cfg.rollupSourceBlockId ? 'rollup' : 'direct');
      setBlkRollupSourceId(cfg.rollupSourceBlockId ?? '');
    } else if (block.blockType === 'grouped_list') {
      const cfg = block.config ?? {};
      setBlkShowGroupTotals(cfg.showGroupTotals !== false);
      setBlkGroupLabel(
        typeof cfg.groupLabel === 'string' ? cfg.groupLabel : ''
      );
      setBlkItemLabel(typeof cfg.itemLabel === 'string' ? cfg.itemLabel : '');
    } else if (block.blockType === 'schedule') {
      const cfg = parseScheduleBlockConfig(block.config);
      setBlkScheduleRule(cfg.completionRule);
      setBlkThresholdPct(
        String(Math.round((cfg.autoCompleteThresholdRatio ?? 1) * 100))
      );
      setBlkTrackDuration(cfg.trackActualDuration);
    }

    setBlkModalError(null);
    setBlockModalOpen(true);
  };

  const handleSaveBlockModal = (e: React.FormEvent) => {
    e.preventDefault();
    setBlkModalError(null);

    const cleanTitle = blkTitle.trim();
    if (!cleanTitle) {
      setBlkModalError('Block title is required.');
      return;
    }

    let parsedTarget: number | undefined;
    if (blkTarget.trim()) {
      const n = Number(blkTarget);
      if (!Number.isFinite(n) || n < 0) {
        setBlkModalError('Target value must be a valid non-negative number.');
        return;
      }
      parsedTarget = n;
    }

    let parsedDailyTarget: number | undefined;
    if (blkDailyTarget.trim()) {
      const n = Number(blkDailyTarget);
      if (!Number.isFinite(n) || n < 0) {
        setBlkModalError('Daily target must be a valid non-negative number.');
        return;
      }
      parsedDailyTarget = n;
    }

    let config: Record<string, unknown> = {};
    if (blkType === 'counter') {
      if (blkCounterMode === 'rollup') {
        if (!blkRollupSourceId) {
          setBlkModalError('Select a source block for this rollup counter.');
          return;
        }
        config = {
          rollupSourceBlockId: blkRollupSourceId,
          allowDirectLogging: false,
        };
      } else {
        config = { allowDirectLogging: true };
      }
    } else if (blkType === 'grouped_list') {
      config = {
        showGroupTotals: blkShowGroupTotals,
        showDailyTotals: true,
        ...(blkGroupLabel.trim() ? { groupLabel: blkGroupLabel.trim() } : {}),
        ...(blkItemLabel.trim() ? { itemLabel: blkItemLabel.trim() } : {}),
      };
    } else if (blkType === 'checklist') {
      config = { allowReorder: true };
    } else if (blkType === 'schedule') {
      const pct = Number(blkThresholdPct);
      const ratio =
        blkScheduleRule === 'threshold_percent'
          ? Math.max(0.05, Math.min(1, (Number.isFinite(pct) ? pct : 80) / 100))
          : 1.0;
      config = {
        completionRule: blkScheduleRule,
        autoCompleteThresholdRatio: ratio,
        trackActualDuration: blkTrackDuration,
      };
    }

    try {
      if (editingBlock) {
        projectsService.updateBlock({
          ...editingBlock,
          title: cleanTitle,
          unitLabel: blkUnit.trim() || undefined,
          targetValue: parsedTarget,
          dailyTargetValue: parsedDailyTarget,
          config,
        });
        if (blkSetPrimary) {
          projectsService.setPrimaryBlock(project.id, editingBlock.id);
        } else if (primaryBlockId === editingBlock.id) {
          projectsService.setPrimaryBlock(project.id, undefined);
        }
      } else {
        projectsService.createBlock({
          projectId: project.id,
          blockType: blkType,
          title: cleanTitle,
          unitLabel: blkUnit.trim() || undefined,
          targetValue: parsedTarget,
          dailyTargetValue: parsedDailyTarget,
          config,
          setAsPrimary: blkSetPrimary,
        });
      }
      setBlockModalOpen(false);
      onRefresh();
    } catch (err) {
      setBlkModalError(
        err instanceof Error ? err.message : 'Unable to save tracking block.'
      );
    }
  };

  const runSafely = (fn: () => void) => {
    setActionError(null);
    try {
      fn();
      onRefresh();
    } catch (err) {
      setActionError(
        err instanceof ProjectValidationError || err instanceof Error
          ? err.message
          : 'Operation failed.'
      );
    }
  };

  return (
    <section className="space-y-3">
      <DaywellSectionHeader
        title="Tracking Blocks"
        count={activeBlocks.length}
        actionLabel="+ Add Block"
        onActionPressed={openAddBlock}
      />

      {actionError ? (
        <DaywellStatusBanner
          tone="error"
          message={actionError}
          onDismiss={() => setActionError(null)}
        />
      ) : null}

      {activeBlocks.length === 0 ? (
        <DaywellCard padding="md" radius="lg">
          <DaywellEmptyState
            icon={<Plus className="w-7 h-7" />}
            message="No tracking blocks yet"
            subtitle="Add a counter, grouped list, checklist, or schedule block to track progress your way."
            actionLabel="Add Tracking Block"
            onActionPressed={openAddBlock}
          />
        </DaywellCard>
      ) : (
        <div className="space-y-3">
          {activeBlocks.map((block) => {
            const metric = metricByBlockId.get(block.id);
            const blockRecords = records.filter((r) => r.blockId === block.id);
            const isPrimary = primaryBlockId === block.id;

            return (
              <TrackingBlockCard
                key={block.id}
                projectId={project.id}
                block={block}
                allBlocks={blocks}
                records={blockRecords}
                metric={metric}
                isPrimary={isPrimary}
                onEdit={() => openEditBlock(block)}
                onTogglePrimary={() =>
                  runSafely(() =>
                    projectsService.setPrimaryBlock(
                      project.id,
                      isPrimary ? undefined : block.id
                    )
                  )
                }
                onArchive={() =>
                  runSafely(() =>
                    projectsService.setBlockArchived(block.id, true)
                  )
                }
                onError={(msg) => setActionError(msg)}
                onMutated={() => {
                  setActionError(null);
                  onRefresh();
                }}
              />
            );
          })}
        </div>
      )}

      {archivedBlocks.length > 0 && (
        <div className="pt-1 space-y-2">
          <DaywellButton
            label={
              showArchivedBlocks
                ? `Hide archived blocks (${archivedBlocks.length})`
                : `Show archived blocks (${archivedBlocks.length})`
            }
            variant="text"
            size="compact"
            onClick={() => setShowArchivedBlocks((s) => !s)}
          />

          {showArchivedBlocks && (
            <div className="space-y-2">
              {archivedBlocks.map((blk) => (
                <DaywellCard
                  key={blk.id}
                  variant="subtle"
                  padding="compact"
                  radius="md"
                  className="flex items-center justify-between gap-2"
                >
                  <div className="min-w-0">
                    <p className="text-xs font-semibold text-[var(--dw-text-secondary)] truncate">
                      {blk.title}
                    </p>
                    <p className="text-[11px] text-[var(--dw-text-muted)] capitalize">
                      {blk.blockType.replace('_', ' ')} · Archived
                    </p>
                  </div>
                  <div className="flex items-center gap-1 shrink-0">
                    <DaywellButton
                      label="Restore"
                      variant="outlined"
                      size="compact"
                      leadingIcon={<RotateCcw className="w-3 h-3" />}
                      onClick={() =>
                        runSafely(() =>
                          projectsService.setBlockArchived(blk.id, false)
                        )
                      }
                    />
                    <DaywellIconButton
                      label={`Delete archived block ${blk.title}`}
                      size="compact"
                      tone="danger"
                      onClick={() => setBlockToDelete(blk)}
                      icon={<Trash2 className="w-3.5 h-3.5" />}
                    />
                  </div>
                </DaywellCard>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Add / Edit Block Modal */}
      {blockModalOpen && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={editingBlock ? 'Edit Tracking Block' : 'Add Tracking Block'}
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs"
          onClick={(e) => {
            if (e.target === e.currentTarget) setBlockModalOpen(false);
          }}
        >
          <div className="w-full max-w-md bg-[var(--dw-elevated)] rounded-[var(--dw-radius-xl)] p-5 shadow-2xl border border-[var(--dw-border)] space-y-4 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <h3 className="dw-type-title text-[var(--dw-text-primary)]">
                {editingBlock ? 'Edit Tracking Block' : 'Add Tracking Block'}
              </h3>
              <DaywellIconButton
                label="Close block dialog"
                size="compact"
                tone="muted"
                onClick={() => setBlockModalOpen(false)}
                icon={<X className="w-4 h-4" />}
              />
            </div>

            {blkModalError ? (
              <DaywellStatusBanner tone="error" message={blkModalError} />
            ) : null}

            <form onSubmit={handleSaveBlockModal} className="space-y-3">
              <DaywellSelectField
                label="Block Type"
                disabled={Boolean(editingBlock)}
                value={blkType}
                onChange={(e) => setBlkType(e.target.value as SharedProjectBlockType)}
                options={[
                  { value: 'counter', label: 'Counter' },
                  { value: 'grouped_list', label: 'Grouped List' },
                  { value: 'checklist', label: 'Checklist' },
                  { value: 'schedule', label: 'Schedule' },
                ]}
              />

              <DaywellTextField
                label="Title *"
                placeholder="e.g. Chapters completed, Daily practice..."
                value={blkTitle}
                onChange={(e) => setBlkTitle(e.target.value)}
              />

              <div className="grid grid-cols-3 gap-2">
                <DaywellTextField
                  label="Unit"
                  placeholder="Optional"
                  value={blkUnit}
                  onChange={(e) => setBlkUnit(e.target.value)}
                />
                <DaywellTextField
                  label="Target"
                  type="number"
                  min="0"
                  step="any"
                  placeholder="Optional"
                  value={blkTarget}
                  onChange={(e) => setBlkTarget(e.target.value)}
                />
                <DaywellTextField
                  label="Daily Target"
                  type="number"
                  min="0"
                  step="any"
                  placeholder="Optional"
                  value={blkDailyTarget}
                  onChange={(e) => setBlkDailyTarget(e.target.value)}
                />
              </div>

              {blkType === 'counter' && (
                <div className="space-y-2 pt-1">
                  <DaywellSelectField
                    label="Counter Mode"
                    value={blkCounterMode}
                    onChange={(e) =>
                      setBlkCounterMode(e.target.value as 'direct' | 'rollup')
                    }
                    options={[
                      { value: 'direct', label: 'Direct counter' },
                      {
                        value: 'rollup',
                        label: 'Rollup counter (reads another block)',
                      },
                    ]}
                  />
                  {blkCounterMode === 'rollup' && (
                    <DaywellSelectField
                      label="Source Block"
                      value={blkRollupSourceId}
                      onChange={(e) => setBlkRollupSourceId(e.target.value)}
                      options={[
                        { value: '', label: 'Select a source block...' },
                        ...rollupSourceOptions.map((b) => ({
                          value: b.id,
                          label: `${b.title} (${b.blockType.replace('_', ' ')})`,
                        })),
                      ]}
                    />
                  )}
                </div>
              )}

              {blkType === 'grouped_list' && (
                <div className="space-y-2 pt-1">
                  <label className="flex items-center gap-2 text-xs text-[var(--dw-text-secondary)] cursor-pointer">
                    <input
                      type="checkbox"
                      checked={blkShowGroupTotals}
                      onChange={(e) => setBlkShowGroupTotals(e.target.checked)}
                      className="w-4 h-4 accent-[var(--dw-primary)]"
                    />
                    <span>Show per-group totals</span>
                  </label>
                  <div className="grid grid-cols-2 gap-2">
                    <DaywellTextField
                      label="Group Term"
                      placeholder="e.g. Module"
                      value={blkGroupLabel}
                      onChange={(e) => setBlkGroupLabel(e.target.value)}
                    />
                    <DaywellTextField
                      label="Item Term"
                      placeholder="e.g. Lesson"
                      value={blkItemLabel}
                      onChange={(e) => setBlkItemLabel(e.target.value)}
                    />
                  </div>
                </div>
              )}

              {blkType === 'schedule' && (
                <div className="space-y-2 pt-1">
                  <DaywellSelectField
                    label="Completion Rule"
                    value={blkScheduleRule}
                    onChange={(e) =>
                      setBlkScheduleRule(
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
                        label: 'Auto-complete at threshold %',
                      },
                      {
                        value: 'exact_duration',
                        label: 'Auto-complete at 100% planned duration',
                      },
                    ]}
                  />
                  {blkScheduleRule === 'threshold_percent' && (
                    <DaywellTextField
                      label="Threshold (%)"
                      type="number"
                      min="1"
                      max="100"
                      value={blkThresholdPct}
                      onChange={(e) => setBlkThresholdPct(e.target.value)}
                    />
                  )}
                  <label className="flex items-center gap-2 text-xs text-[var(--dw-text-secondary)] cursor-pointer">
                    <input
                      type="checkbox"
                      checked={blkTrackDuration}
                      onChange={(e) => setBlkTrackDuration(e.target.checked)}
                      className="w-4 h-4 accent-[var(--dw-primary)]"
                    />
                    <span>Track actual vs planned minutes</span>
                  </label>
                </div>
              )}

              <label className="flex items-center gap-2 text-xs text-[var(--dw-text-secondary)] pt-1 cursor-pointer">
                <input
                  type="checkbox"
                  checked={blkSetPrimary}
                  onChange={(e) => setBlkSetPrimary(e.target.checked)}
                  className="w-4 h-4 accent-[var(--dw-primary)]"
                />
                <span>Use as Primary Progress Block for this project</span>
              </label>

              <div className="flex items-center justify-end gap-2 pt-2">
                <DaywellButton
                  label="Cancel"
                  variant="outlined"
                  size="compact"
                  onClick={() => setBlockModalOpen(false)}
                />
                <DaywellButton
                  type="submit"
                  label={editingBlock ? 'Save Block' : 'Add Block'}
                  variant="primary"
                  size="compact"
                />
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Delete Archived Block Confirmation */}
      <DaywellConfirmationDialog
        isOpen={Boolean(blockToDelete)}
        title={`Delete "${blockToDelete?.title ?? ''}"?`}
        description="This permanently removes the archived tracking block and all records inside it. This action cannot be undone."
        confirmLabel="Delete Forever"
        destructive
        onCancel={() => setBlockToDelete(null)}
        onConfirm={() => {
          if (blockToDelete) {
            runSafely(() =>
              projectsService.deleteBlock(project.id, blockToDelete.id)
            );
          }
          setBlockToDelete(null);
        }}
      />
    </section>
  );
}

// =============================================================================
// Per-Block Adaptive Card Renderer
// =============================================================================

interface TrackingBlockCardProps {
  projectId: string;
  block: SharedProjectTrackingBlock;
  allBlocks: SharedProjectTrackingBlock[];
  records: SharedProjectTrackingRecord[];
  metric?: ProjectBlockProgressMetric;
  isPrimary: boolean;
  onEdit: () => void;
  onTogglePrimary: () => void;
  onArchive: () => void;
  onError: (msg: string) => void;
  onMutated: () => void;
}

function TrackingBlockCard({
  projectId,
  block,
  allBlocks,
  records,
  metric,
  isPrimary,
  onEdit,
  onTogglePrimary,
  onArchive,
  onError,
  onMutated,
}: TrackingBlockCardProps) {
  const todayIso = CalendarDate.today().toIsoString();

  // Counter direct log state
  const [counterDelta, setCounterDelta] = useState('1');
  const [counterDate, setCounterDate] = useState(todayIso);

  // Grouped list state
  const [newGroupTitle, setNewGroupTitle] = useState('');
  const [newGroupTarget, setNewGroupTarget] = useState('');
  const [showAddGroup, setShowAddGroup] = useState(false);
  const [addingItemGroupId, setAddingItemGroupId] = useState<string | null>(null);
  const [newItemTitle, setNewItemTitle] = useState('');
  const [newItemTarget, setNewItemTarget] = useState('');
  const [loggingItemId, setLoggingItemId] = useState<string | null>(null);
  const [itemLogDelta, setItemLogDelta] = useState('1');
  const [itemLogDate, setItemLogDate] = useState(todayIso);

  // Checklist state
  const [newChecklistTitle, setNewChecklistTitle] = useState('');
  const [editingRecordId, setEditingRecordId] = useState<string | null>(null);
  const [editingRecordTitle, setEditingRecordTitle] = useState('');

  // Schedule state
  const [showAddSchedule, setShowAddSchedule] = useState(false);
  const [newSchedTitle, setNewSchedTitle] = useState('');
  const [newSchedDate, setNewSchedDate] = useState(todayIso);
  const [newSchedDuration, setNewSchedDuration] = useState('30');
  const [loggingSchedId, setLoggingSchedId] = useState<string | null>(null);
  const [schedLogMinutes, setSchedLogMinutes] = useState('30');
  const [schedLogDate, setSchedLogDate] = useState(todayIso);

  const runAction = (fn: () => void) => {
    try {
      fn();
      onMutated();
    } catch (err) {
      onError(err instanceof Error ? err.message : 'Unable to update block.');
    }
  };

  const blockTypeLabel =
    block.blockType === 'counter'
      ? parseCounterBlockConfig(block.config).rollupSourceBlockId
        ? 'Rollup counter'
        : 'Counter'
      : block.blockType === 'grouped_list'
      ? 'Grouped list'
      : block.blockType === 'checklist'
      ? 'Checklist'
      : 'Schedule';

  return (
    <DaywellCard padding="md" radius="lg" className="space-y-3">
      {/* Header */}
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0 space-y-0.5">
          <div className="flex items-center flex-wrap gap-1.5">
            <h3 className="text-sm font-bold text-[var(--dw-text-primary)] truncate">
              {block.title}
            </h3>
            {isPrimary && (
              <DaywellStatusBadge
                tone="success"
                showIcon={false}
                label="Primary"
              />
            )}
          </div>
          <p className="text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
            {blockTypeLabel}
            {metric ? ` · ${projectsService.formatBlockMetricSummary(metric)}` : ''}
          </p>
        </div>

        <div className="flex items-center gap-0.5 shrink-0">
          <DaywellIconButton
            label={
              isPrimary
                ? `Unset ${block.title} as primary block`
                : `Set ${block.title} as primary progress block`
            }
            size="compact"
            tone={isPrimary ? 'primary' : 'muted'}
            onClick={onTogglePrimary}
            icon={<Star className={`w-3.5 h-3.5 ${isPrimary ? 'fill-current' : ''}`} />}
          />
          <DaywellIconButton
            label={`Edit block ${block.title}`}
            size="compact"
            tone="muted"
            onClick={onEdit}
            icon={<Edit3 className="w-3.5 h-3.5" />}
          />
          <DaywellIconButton
            label={`Archive block ${block.title}`}
            size="compact"
            tone="muted"
            onClick={onArchive}
            icon={<Archive className="w-3.5 h-3.5" />}
          />
        </div>
      </div>

      {/* Block Progress Bar when applicable */}
      {metric?.progressPercent !== undefined && (
        <DaywellProgressBar
          value={metric.progressPercent}
          label={`${block.title} progress`}
        />
      )}

      {/* Adaptive Block Body */}
      {block.blockType === 'counter' && (
        <CounterBlockBody
          projectId={projectId}
          block={block}
          allBlocks={allBlocks}
          metric={metric}
          counterDelta={counterDelta}
          setCounterDelta={setCounterDelta}
          counterDate={counterDate}
          setCounterDate={setCounterDate}
          onRunAction={runAction}
          onError={onError}
        />
      )}

      {block.blockType === 'grouped_list' && (
        <GroupedListBlockBody
          projectId={projectId}
          block={block}
          records={records}
          metric={metric}
          showAddGroup={showAddGroup}
          setShowAddGroup={setShowAddGroup}
          newGroupTitle={newGroupTitle}
          setNewGroupTitle={setNewGroupTitle}
          newGroupTarget={newGroupTarget}
          setNewGroupTarget={setNewGroupTarget}
          addingItemGroupId={addingItemGroupId}
          setAddingItemGroupId={setAddingItemGroupId}
          newItemTitle={newItemTitle}
          setNewItemTitle={setNewItemTitle}
          newItemTarget={newItemTarget}
          setNewItemTarget={setNewItemTarget}
          loggingItemId={loggingItemId}
          setLoggingItemId={setLoggingItemId}
          itemLogDelta={itemLogDelta}
          setItemLogDelta={setItemLogDelta}
          itemLogDate={itemLogDate}
          setItemLogDate={setItemLogDate}
          onRunAction={runAction}
          onError={onError}
        />
      )}

      {block.blockType === 'checklist' && (
        <div className="space-y-2.5">
          {records
            .filter((r) => r.recordType === 'checklist_item')
            .map((item) => (
              <div
                key={item.id}
                className="flex items-center justify-between gap-2 py-1 border-b border-[var(--dw-divider)] last:border-b-0"
              >
                {editingRecordId === item.id ? (
                  <div className="flex-1 flex items-center gap-1.5">
                    <input
                      type="text"
                      value={editingRecordTitle}
                      onChange={(e) => setEditingRecordTitle(e.target.value)}
                      className="flex-1 min-h-[36px] px-2.5 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
                    />
                    <DaywellButton
                      label="Save"
                      variant="primary"
                      size="compact"
                      onClick={() => {
                        if (!editingRecordTitle.trim()) return;
                        runAction(() => {
                          projectsService.updateRecord({
                            ...item,
                            title: editingRecordTitle.trim(),
                          });
                          setEditingRecordId(null);
                        });
                      }}
                    />
                    <DaywellButton
                      label="Cancel"
                      variant="text"
                      size="compact"
                      onClick={() => setEditingRecordId(null)}
                    />
                  </div>
                ) : (
                  <>
                    <button
                      type="button"
                      onClick={() =>
                        runAction(() => projectsService.toggleRecordCompleted(item))
                      }
                      className="flex items-center gap-2.5 flex-1 min-w-0 text-left min-h-[36px] cursor-pointer"
                    >
                      <span
                        className={`w-4 h-4 rounded-[var(--dw-radius-sm)] border flex items-center justify-center shrink-0 ${
                          item.isCompleted
                            ? 'bg-[var(--dw-primary)] border-[var(--dw-primary)] text-[var(--dw-on-primary)]'
                            : 'border-[var(--dw-border)]'
                        }`}
                      >
                        {item.isCompleted && <Check className="w-3 h-3 stroke-[3]" />}
                      </span>
                      <span
                        className={`text-xs truncate ${
                          item.isCompleted
                            ? 'line-through text-[var(--dw-text-muted)]'
                            : 'text-[var(--dw-text-primary)] font-medium'
                        }`}
                      >
                        {item.title}
                      </span>
                    </button>
                    <div className="flex items-center gap-0.5 shrink-0">
                      <DaywellIconButton
                        label={`Rename ${item.title}`}
                        size="compact"
                        tone="muted"
                        onClick={() => {
                          setEditingRecordId(item.id);
                          setEditingRecordTitle(item.title ?? '');
                        }}
                        icon={<Edit3 className="w-3 h-3" />}
                      />
                      <DaywellIconButton
                        label={`Delete ${item.title}`}
                        size="compact"
                        tone="danger"
                        onClick={() =>
                          runAction(() => projectsService.deleteRecord(item.id))
                        }
                        icon={<Trash2 className="w-3 h-3" />}
                      />
                    </div>
                  </>
                )}
              </div>
            ))}

          <form
            onSubmit={(e) => {
              e.preventDefault();
              if (!newChecklistTitle.trim()) return;
              runAction(() => {
                projectsService.createChecklistItem({
                  projectId,
                  blockId: block.id,
                  title: newChecklistTitle.trim(),
                });
                setNewChecklistTitle('');
              });
            }}
            className="flex items-center gap-2 pt-1"
          >
            <input
              type="text"
              placeholder="Add checklist item..."
              value={newChecklistTitle}
              onChange={(e) => setNewChecklistTitle(e.target.value)}
              className="flex-1 min-h-[40px] px-3 py-1.5 text-xs rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-primary)] placeholder:text-[var(--dw-text-muted)] focus:outline-none focus:border-[var(--dw-primary)]"
            />
            <DaywellButton
              type="submit"
              label="Add"
              variant="tonal"
              size="compact"
              disabled={!newChecklistTitle.trim()}
            />
          </form>
        </div>
      )}

      {block.blockType === 'schedule' && (
        <ScheduleBlockBody
          projectId={projectId}
          block={block}
          records={records}
          metric={metric}
          showAddSchedule={showAddSchedule}
          setShowAddSchedule={setShowAddSchedule}
          newSchedTitle={newSchedTitle}
          setNewSchedTitle={setNewSchedTitle}
          newSchedDate={newSchedDate}
          setNewSchedDate={setNewSchedDate}
          newSchedDuration={newSchedDuration}
          setNewSchedDuration={setNewSchedDuration}
          loggingSchedId={loggingSchedId}
          setLoggingSchedId={setLoggingSchedId}
          schedLogMinutes={schedLogMinutes}
          setSchedLogMinutes={setSchedLogMinutes}
          schedLogDate={schedLogDate}
          setSchedLogDate={setSchedLogDate}
          onRunAction={runAction}
          onError={onError}
        />
      )}
    </DaywellCard>
  );
}

// --- Sub-renderers ---

function CounterBlockBody(props: {
  projectId: string;
  block: SharedProjectTrackingBlock;
  allBlocks: SharedProjectTrackingBlock[];
  metric?: ProjectBlockProgressMetric;
  counterDelta: string;
  setCounterDelta: (v: string) => void;
  counterDate: string;
  setCounterDate: (v: string) => void;
  onRunAction: (fn: () => void) => void;
  onError: (msg: string) => void;
}) {
  const {
    projectId,
    block,
    allBlocks,
    metric,
    counterDelta,
    setCounterDelta,
    counterDate,
    setCounterDate,
    onRunAction,
    onError,
  } = props;
  const cfg = parseCounterBlockConfig(block.config);
  const isRollup = Boolean(cfg.rollupSourceBlockId) || !cfg.allowDirectLogging;
  const sourceBlock = cfg.rollupSourceBlockId
    ? allBlocks.find((b) => b.id === cfg.rollupSourceBlockId)
    : undefined;
  const unit = block.unitLabel ?? metric?.unitLabel;

  return (
    <div className="space-y-2.5">
      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-[var(--dw-text-secondary)] dw-type-numeric-body">
        <span>
          Today:{' '}
          <strong className="text-[var(--dw-text-primary)]">
            {formatNumber(metric?.todayTotal ?? 0)}
            {unit ? ` ${unit}` : ''}
          </strong>
          {metric?.dailyTargetValue !== undefined
            ? ` / ${formatNumber(metric.dailyTargetValue)}`
            : ''}
        </span>
        {metric?.paceNeededPerDay !== undefined && (
          <span>
            Pace needed:{' '}
            <strong className="text-[var(--dw-text-primary)]">
              {formatNumber(Number(metric.paceNeededPerDay.toFixed(1)))}/day
            </strong>
          </span>
        )}
        {metric?.daysRemaining !== undefined && (
          <span>{metric.daysRemaining}d left</span>
        )}
      </div>

      {isRollup ? (
        <div className="p-2.5 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[11px] text-[var(--dw-text-secondary)]">
          Automatic rollup from{' '}
          <strong className="text-[var(--dw-text-primary)]">
            {sourceBlock?.title ?? cfg.rollupSourceBlockId ?? 'source block'}
          </strong>
          . Log progress in the source block to update this total.
        </div>
      ) : (
        <div className="flex flex-wrap items-center gap-2 pt-0.5">
          <DaywellButton
            label={`+1${unit ? ` ${unit}` : ''}`}
            variant="tonal"
            size="compact"
            onClick={() =>
              onRunAction(() =>
                projectsService.logProgress({
                  projectId,
                  blockId: block.id,
                  deltaValue: 1,
                  recordedDate: counterDate || CalendarDate.today().toIsoString(),
                })
              )
            }
          />
          <input
            type="number"
            min="0.01"
            step="any"
            aria-label={`Log amount for ${block.title}`}
            value={counterDelta}
            onChange={(e) => setCounterDelta(e.target.value)}
            className="w-20 min-h-[36px] px-2.5 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-primary)] dw-type-numeric-body"
          />
          <input
            type="date"
            aria-label={`Log date for ${block.title}`}
            value={counterDate}
            onChange={(e) => setCounterDate(e.target.value)}
            className="min-h-[36px] px-2 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
          />
          <DaywellButton
            label="Log"
            variant="primary"
            size="compact"
            onClick={() => {
              const delta = Number(counterDelta);
              if (!Number.isFinite(delta) || delta <= 0) {
                onError('Progress amount must be greater than 0.');
                return;
              }
              onRunAction(() =>
                projectsService.logProgress({
                  projectId,
                  blockId: block.id,
                  deltaValue: delta,
                  recordedDate: counterDate || CalendarDate.today().toIsoString(),
                })
              );
            }}
          />
        </div>
      )}
    </div>
  );
}

function GroupedListBlockBody(props: {
  projectId: string;
  block: SharedProjectTrackingBlock;
  records: SharedProjectTrackingRecord[];
  metric?: ProjectBlockProgressMetric;
  showAddGroup: boolean;
  setShowAddGroup: (v: boolean) => void;
  newGroupTitle: string;
  setNewGroupTitle: (v: string) => void;
  newGroupTarget: string;
  setNewGroupTarget: (v: string) => void;
  addingItemGroupId: string | null;
  setAddingItemGroupId: (v: string | null) => void;
  newItemTitle: string;
  setNewItemTitle: (v: string) => void;
  newItemTarget: string;
  setNewItemTarget: (v: string) => void;
  loggingItemId: string | null;
  setLoggingItemId: (v: string | null) => void;
  itemLogDelta: string;
  setItemLogDelta: (v: string) => void;
  itemLogDate: string;
  setItemLogDate: (v: string) => void;
  onRunAction: (fn: () => void) => void;
  onError: (msg: string) => void;
}) {
  const {
    projectId,
    block,
    records,
    metric,
    showAddGroup,
    setShowAddGroup,
    newGroupTitle,
    setNewGroupTitle,
    newGroupTarget,
    setNewGroupTarget,
    addingItemGroupId,
    setAddingItemGroupId,
    newItemTitle,
    setNewItemTitle,
    newItemTarget,
    setNewItemTarget,
    loggingItemId,
    setLoggingItemId,
    itemLogDelta,
    setItemLogDelta,
    itemLogDate,
    setItemLogDate,
    onRunAction,
    onError,
  } = props;

  const [itemSearch, setItemSearch] = useState('');
  const [itemFilter, setItemFilter] = useState<'all' | 'remaining' | 'done' | 'over'>('all');
  const [selectedGroupId, setSelectedGroupId] = useState<string>('all');
  const [collapsedGroupIds, setCollapsedGroupIds] = useState<Record<string, boolean>>({});
  const [editingGroupId, setEditingGroupId] = useState<string | null>(null);
  const [editingGroupTitle, setEditingGroupTitle] = useState('');
  const [editingGroupTarget, setEditingGroupTarget] = useState('');
  const [editingItemId, setEditingItemId] = useState<string | null>(null);
  const [editingItemTitle, setEditingItemTitle] = useState('');
  const [editingItemTarget, setEditingItemTarget] = useState('');

  const cfg = block.config ?? {};
  const showGroupTotals = cfg.showGroupTotals !== false;
  const showDailyTotals = cfg.showDailyTotals !== false;
  const groupNoun =
    typeof cfg.groupLabel === 'string' && cfg.groupLabel.trim()
      ? cfg.groupLabel.trim()
      : 'Group';
  const itemNoun =
    typeof cfg.itemLabel === 'string' && cfg.itemLabel.trim()
      ? cfg.itemLabel.trim()
      : 'Item';
  const unit = block.unitLabel ?? metric?.unitLabel;

  const groups = records.filter((r) => r.recordType === 'group');
  const items = records.filter((r) => r.recordType === 'grouped_item');
  const groupMetricMap = new Map(
    (metric?.groupMetrics ?? []).map((g) => [g.groupId, g])
  );
  const itemTotals = metric?.itemTotals ?? {};
  const showFilterToolbar = items.length > 6 || groups.length > 1;
  const normalizedQuery = itemSearch.trim().toLowerCase();
  const hasOverItems = (metric?.overTargetItemCount ?? 0) > 0;
  const activeGroupFilterId =
    selectedGroupId !== 'all' && groups.some((g) => g.id === selectedGroupId)
      ? selectedGroupId
      : 'all';

  const itemMatchesFilter = (item: SharedProjectTrackingRecord): boolean => {
    const logged = itemTotals[item.id] ?? 0;
    const target = item.targetValue;
    const isOver = target !== undefined && target > 0 && logged > target;
    const isDone =
      item.isCompleted || (target !== undefined && target > 0 && logged >= target);

    if (itemFilter === 'remaining' && isDone) return false;
    if (itemFilter === 'done' && !isDone) return false;
    if (itemFilter === 'over' && !isOver) return false;
    return true;
  };

  const ungroupedItems =
    activeGroupFilterId !== 'all'
      ? []
      : items.filter((i) => {
          if (i.parentRecordId) return false;
          if (!itemMatchesFilter(i)) return false;
          if (normalizedQuery) {
            return (i.title ?? '').toLowerCase().includes(normalizedQuery);
          }
          return true;
        });

  const allCollapsed =
    groups.length > 0 && groups.every((g) => Boolean(collapsedGroupIds[g.id]));

  const toggleAllGroups = () => {
    if (allCollapsed) {
      setCollapsedGroupIds({});
    } else {
      const next: Record<string, boolean> = {};
      for (const g of groups) next[g.id] = true;
      setCollapsedGroupIds(next);
    }
  };

  const renderItemRow = (item: SharedProjectTrackingRecord) => {
    const logged = itemTotals[item.id] ?? 0;
    const target = item.targetValue;
    const overAmount =
      target !== undefined && target > 0 && logged > target ? logged - target : 0;
    const remainingAmount =
      target !== undefined && target > 0 ? Math.max(0, target - logged) : undefined;
    const isLogging = loggingItemId === item.id;
    const isEditing = editingItemId === item.id;
    const done =
      item.isCompleted || (target !== undefined && target > 0 && logged >= target);
    const parsedDelta = Number(itemLogDelta);
    const willExceedTarget =
      isLogging &&
      target !== undefined &&
      target > 0 &&
      Number.isFinite(parsedDelta) &&
      parsedDelta > 0 &&
      logged + parsedDelta > target;
    const parsedLogDate = CalendarDate.tryParse(itemLogDate);

    const submitItemLog = (e?: React.FormEvent) => {
      if (e) e.preventDefault();
      const delta = Number(itemLogDelta);
      if (!Number.isFinite(delta) || delta <= 0) {
        onError('Logged progress must be greater than 0.');
        return;
      }
      onRunAction(() => {
        projectsService.logProgress({
          projectId,
          blockId: block.id,
          parentRecordId: item.id,
          deltaValue: delta,
          recordedDate: itemLogDate || CalendarDate.today().toIsoString(),
        });
        setLoggingItemId(null);
      });
    };

    const submitItemEdit = (e: React.FormEvent) => {
      e.preventDefault();
      const cleanTitle = editingItemTitle.trim();
      if (!cleanTitle) {
        onError(`${itemNoun} title is required.`);
        return;
      }
      let parsedTarget: number | undefined;
      if (editingItemTarget.trim()) {
        const t = Number(editingItemTarget);
        if (!Number.isFinite(t) || t < 0) {
          onError(`${itemNoun} target must be a valid non-negative number.`);
          return;
        }
        parsedTarget = t;
      }
      const nextRecord: SharedProjectTrackingRecord = {
        ...item,
        title: cleanTitle,
      };
      if (parsedTarget !== undefined) {
        nextRecord.targetValue = parsedTarget;
      } else {
        delete nextRecord.targetValue;
      }
      onRunAction(() => {
        projectsService.updateRecord(nextRecord);
        setEditingItemId(null);
      });
    };

    return (
      <div
        key={item.id}
        className={`py-2 border-b border-[var(--dw-divider)] space-y-1.5 ${
          isLogging || isEditing
            ? 'md:col-span-2 bg-[var(--dw-card)] rounded-[var(--dw-radius-sm)] px-2.5 my-1'
            : ''
        }`}
      >
        {isEditing ? (
          <form onSubmit={submitItemEdit} className="flex flex-wrap items-center gap-1.5">
            <input
              type="text"
              aria-label={`Edit ${itemNoun.toLowerCase()} title`}
              placeholder={`${itemNoun} title...`}
              value={editingItemTitle}
              onChange={(e) => setEditingItemTitle(e.target.value)}
              className="flex-1 min-w-[150px] min-h-[34px] px-2.5 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
            />
            <input
              type="number"
              min="0"
              step="any"
              aria-label={`Edit ${itemNoun.toLowerCase()} target`}
              placeholder="Target"
              value={editingItemTarget}
              onChange={(e) => setEditingItemTarget(e.target.value)}
              className="w-24 min-h-[34px] px-2 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-primary)] dw-type-numeric-body"
            />
            <DaywellButton
              type="submit"
              label="Save"
              variant="primary"
              size="compact"
            />
            <DaywellButton
              label="Cancel"
              variant="text"
              size="compact"
              onClick={() => setEditingItemId(null)}
            />
          </form>
        ) : (
          <div className="flex items-center justify-between gap-2">
            <button
              type="button"
              onClick={() =>
                onRunAction(() => projectsService.toggleRecordCompleted(item))
              }
              className="flex items-center gap-2 flex-1 min-w-0 text-left cursor-pointer"
            >
              <span
                className={`w-4 h-4 rounded-[var(--dw-radius-sm)] border flex items-center justify-center shrink-0 ${
                  done
                    ? 'bg-[var(--dw-primary)] border-[var(--dw-primary)] text-[var(--dw-on-primary)]'
                    : 'border-[var(--dw-border)]'
                }`}
              >
                {done && <Check className="w-3 h-3 stroke-[3]" />}
              </span>
              <span
                className={`text-xs truncate ${
                  done
                    ? 'line-through text-[var(--dw-text-muted)]'
                    : 'text-[var(--dw-text-primary)] font-medium'
                }`}
              >
                {item.title}
              </span>
            </button>

            <div className="flex items-center gap-1 shrink-0">
              {overAmount > 0 && (
                <DaywellStatusBadge
                  tone="warning"
                  showIcon={false}
                  label={`Over +${formatNumber(overAmount)}`}
                />
              )}
              <span className="text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
                {target !== undefined
                  ? `${formatNumber(logged)}/${formatNumber(target)}${
                      unit ? ` ${unit}` : ''
                    }`
                  : logged > 0
                  ? `${formatNumber(logged)}${unit ? ` ${unit}` : ''}`
                  : ''}
              </span>
              <DaywellButton
                label="+ Log"
                variant="text"
                size="compact"
                onClick={() => {
                  setEditingItemId(null);
                  setLoggingItemId(isLogging ? null : item.id);
                  setItemLogDelta('1');
                }}
              />
              <DaywellIconButton
                label={`Edit ${item.title}`}
                size="compact"
                tone="muted"
                onClick={() => {
                  setLoggingItemId(null);
                  setEditingItemId(item.id);
                  setEditingItemTitle(item.title ?? '');
                  setEditingItemTarget(
                    item.targetValue !== undefined ? String(item.targetValue) : ''
                  );
                }}
                icon={<Edit3 className="w-3 h-3" />}
              />
              <DaywellIconButton
                label={`Delete ${item.title}`}
                size="compact"
                tone="danger"
                onClick={() =>
                  onRunAction(() => projectsService.deleteRecord(item.id))
                }
                icon={<Trash2 className="w-3 h-3" />}
              />
            </div>
          </div>
        )}

        {isLogging && !isEditing && (
          <form onSubmit={submitItemLog} className="pl-6 space-y-1.5">
            <div className="flex flex-wrap items-center gap-1.5">
              <input
                type="number"
                min="0.01"
                step="any"
                aria-label={`Progress delta for ${item.title}`}
                value={itemLogDelta}
                onChange={(e) => setItemLogDelta(e.target.value)}
                className="w-20 min-h-[34px] px-2 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-primary)] dw-type-numeric-body"
              />
              <DaywellButton
                label="+5"
                variant="outlined"
                size="compact"
                onClick={() => setItemLogDelta('5')}
              />
              <DaywellButton
                label="+10"
                variant="outlined"
                size="compact"
                onClick={() => setItemLogDelta('10')}
              />
              {remainingAmount !== undefined && remainingAmount > 0 && (
                <DaywellButton
                  label={`Left (${formatNumber(remainingAmount)})`}
                  variant="tonal"
                  size="compact"
                  onClick={() => setItemLogDelta(String(remainingAmount))}
                />
              )}
              <input
                type="date"
                aria-label={`Log date for ${item.title}`}
                value={itemLogDate}
                onChange={(e) => setItemLogDate(e.target.value)}
                className="min-h-[34px] px-2 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
              />
              <DaywellButton
                type="submit"
                label="Save"
                variant="primary"
                size="compact"
              />
            </div>
            {parsedLogDate && (
              <p className="text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
                {SharedDateFormatter.formatDual(parsedLogDate)}
              </p>
            )}
            {willExceedTarget && target !== undefined && (
              <p className="text-[11px] text-[var(--dw-warning)] dw-type-numeric-body">
                Exceeds {itemNoun.toLowerCase()} target by +
                {formatNumber(logged + parsedDelta - target)}: actual sent count
                is saved, excess does not inflate target completion.
              </p>
            )}
          </form>
        )}
      </div>
    );
  };

  const completedTowardTarget =
    metric?.targetCompletedTotal ?? metric?.loggedTotal ?? 0;
  const remainingBlockTotal =
    metric?.targetValue !== undefined && metric.targetValue > 0
      ? Math.max(0, metric.targetValue - completedTowardTarget)
      : undefined;

  return (
    <div className="space-y-3">
      {(showDailyTotals &&
        (metric?.dailyTargetValue !== undefined ||
          (metric?.todayTotal ?? 0) > 0 ||
          metric?.paceNeededPerDay !== undefined)) ||
      (metric?.overTargetAmount ?? 0) > 0 ? (
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-[var(--dw-text-secondary)] dw-type-numeric-body">
          {showDailyTotals &&
            (metric?.dailyTargetValue !== undefined ||
              (metric?.todayTotal ?? 0) > 0) && (
              <span>
                Today:{' '}
                <strong className="text-[var(--dw-text-primary)]">
                  {formatNumber(metric?.todayTotal ?? 0)}
                  {unit ? ` ${unit}` : ''}
                </strong>
                {metric?.dailyTargetValue !== undefined
                  ? ` / ${formatNumber(metric.dailyTargetValue)}`
                  : ''}
              </span>
            )}
          {remainingBlockTotal !== undefined && (
            <span>
              Remaining:{' '}
              <strong className="text-[var(--dw-text-primary)]">
                {formatNumber(remainingBlockTotal)}
                {unit ? ` ${unit}` : ''}
              </strong>
            </span>
          )}
          {showDailyTotals &&
            metric?.paceNeededPerDay !== undefined &&
            metric.paceNeededPerDay > 0 && (
              <span>
                Pace needed:{' '}
                <strong className="text-[var(--dw-text-primary)]">
                  {formatNumber(Number(metric.paceNeededPerDay.toFixed(1)))}/day
                </strong>
              </span>
            )}
          {(metric?.overTargetAmount ?? 0) > 0 && (
            <span className="text-[var(--dw-warning)] font-medium">
              Actual sent: {formatNumber(metric?.loggedTotal ?? 0)} (+
              {formatNumber(metric?.overTargetAmount ?? 0)} over target)
            </span>
          )}
        </div>
      ) : null}

      {showFilterToolbar && (
        <div className="space-y-2 p-2.5 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)]">
          <div className="flex flex-wrap items-center gap-2">
            <DaywellSearchField
              value={itemSearch}
              onChange={setItemSearch}
              placeholder={`Search ${itemNoun.toLowerCase()}s or ${groupNoun.toLowerCase()}s...`}
              ariaLabel={`Search ${block.title}`}
              className="flex-1 min-w-[180px]"
            />
            {groups.length > 0 && !normalizedQuery && activeGroupFilterId === 'all' && (
              <DaywellButton
                label={allCollapsed ? 'Expand all' : 'Collapse all'}
                variant="outlined"
                size="compact"
                onClick={toggleAllGroups}
              />
            )}
          </div>
          <div className="flex flex-wrap items-center gap-1.5">
            {(
              [
                { key: 'all', label: `All (${items.length})` },
                { key: 'remaining', label: 'Remaining' },
                { key: 'done', label: 'Done' },
                ...(hasOverItems
                  ? [
                      {
                        key: 'over' as const,
                        label: `Over target (${metric?.overTargetItemCount ?? 0})`,
                      },
                    ]
                  : []),
              ] as const
            ).map((opt) => {
              const selected = itemFilter === opt.key;
              return (
                <button
                  key={opt.key}
                  type="button"
                  onClick={() => setItemFilter(opt.key)}
                  className={`min-h-[30px] px-2.5 py-1 rounded-[var(--dw-radius-full)] text-[11px] font-semibold transition-colors cursor-pointer ${
                    selected
                      ? 'bg-[var(--dw-primary-container)] text-[var(--dw-on-primary-container)] border border-[var(--dw-primary)]'
                      : 'bg-[var(--dw-card)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)]'
                  }`}
                >
                  {opt.label}
                </button>
              );
            })}
          </div>
          {groups.length > 1 && (
            <div className="flex flex-wrap items-center gap-1.5 pt-1 border-t border-[var(--dw-divider)]">
              <button
                type="button"
                onClick={() => setSelectedGroupId('all')}
                className={`min-h-[28px] px-2.5 py-0.5 rounded-[var(--dw-radius-full)] text-[11px] font-semibold transition-colors cursor-pointer ${
                  activeGroupFilterId === 'all'
                    ? 'bg-[var(--dw-primary)] text-[var(--dw-on-primary)]'
                    : 'bg-[var(--dw-card)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)]'
                }`}
              >
                All {groupNoun.toLowerCase()}s ({groups.length})
              </button>
              {groups.map((grp) => {
                const gm = groupMetricMap.get(grp.id);
                const count =
                  gm?.itemCount ??
                  items.filter((i) => i.parentRecordId === grp.id).length;
                const isSelected = activeGroupFilterId === grp.id;
                return (
                  <button
                    key={grp.id}
                    type="button"
                    onClick={() => setSelectedGroupId(isSelected ? 'all' : grp.id)}
                    className={`min-h-[28px] px-2.5 py-0.5 rounded-[var(--dw-radius-full)] text-[11px] font-semibold transition-colors cursor-pointer ${
                      isSelected
                        ? 'bg-[var(--dw-primary)] text-[var(--dw-on-primary)]'
                        : 'bg-[var(--dw-card)] text-[var(--dw-text-secondary)] border border-[var(--dw-border)]'
                    }`}
                  >
                    {grp.title} ({count})
                  </button>
                );
              })}
            </div>
          )}
        </div>
      )}

      {groups.map((grp) => {
        if (activeGroupFilterId !== 'all' && grp.id !== activeGroupFilterId) {
          return null;
        }
        const gm = groupMetricMap.get(grp.id);
        const rawChildren = items.filter((i) => i.parentRecordId === grp.id);
        const groupMatchesQuery =
          Boolean(normalizedQuery) &&
          (grp.title ?? '').toLowerCase().includes(normalizedQuery);
        const filteredChildren = rawChildren.filter((child) => {
          if (!itemMatchesFilter(child)) return false;
          if (!normalizedQuery || groupMatchesQuery) return true;
          return (child.title ?? '').toLowerCase().includes(normalizedQuery);
        });

        if (
          (normalizedQuery || itemFilter !== 'all') &&
          filteredChildren.length === 0 &&
          !(groupMatchesQuery && itemFilter === 'all')
        ) {
          return null;
        }

        const isAddingHere = addingItemGroupId === grp.id;
        const isEditingGroup = editingGroupId === grp.id;
        const isCollapsed =
          activeGroupFilterId === 'all' &&
          !normalizedQuery &&
          itemFilter === 'all' &&
          !isAddingHere &&
          !isEditingGroup &&
          Boolean(collapsedGroupIds[grp.id]);
        const groupCompleted = gm?.targetCompletedTotal ?? gm?.loggedTotal ?? 0;
        const groupOver = gm?.overTargetAmount ?? 0;

        const submitGroupEdit = (e: React.FormEvent) => {
          e.preventDefault();
          const cleanTitle = editingGroupTitle.trim();
          if (!cleanTitle) {
            onError(`${groupNoun} title is required.`);
            return;
          }
          let parsedTarget: number | undefined;
          if (editingGroupTarget.trim()) {
            const t = Number(editingGroupTarget);
            if (!Number.isFinite(t) || t < 0) {
              onError(`${groupNoun} target must be a valid non-negative number.`);
              return;
            }
            parsedTarget = t;
          }
          const nextGroup: SharedProjectTrackingRecord = {
            ...grp,
            title: cleanTitle,
          };
          if (parsedTarget !== undefined) {
            nextGroup.targetValue = parsedTarget;
          } else {
            delete nextGroup.targetValue;
          }
          onRunAction(() => {
            projectsService.updateRecord(nextGroup);
            setEditingGroupId(null);
          });
        };

        return (
          <div
            key={grp.id}
            className="p-2.5 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] space-y-2"
          >
            <div className="flex items-center justify-between gap-2">
              <button
                type="button"
                onClick={() =>
                  setCollapsedGroupIds((prev) => ({
                    ...prev,
                    [grp.id]: !prev[grp.id],
                  }))
                }
                className="flex items-center gap-1.5 min-w-0 flex-1 text-left cursor-pointer"
                aria-expanded={!isCollapsed}
              >
                {isCollapsed ? (
                  <ChevronRight className="w-4 h-4 text-[var(--dw-text-muted)] shrink-0" />
                ) : (
                  <ChevronDown className="w-4 h-4 text-[var(--dw-text-muted)] shrink-0" />
                )}
                <div className="min-w-0">
                  <div className="flex items-center flex-wrap gap-1.5">
                    <p className="text-xs font-bold text-[var(--dw-text-primary)] truncate">
                      {grp.title}
                    </p>
                    {groupOver > 0 && gm && (
                      <DaywellStatusBadge
                        tone="warning"
                        showIcon={false}
                        label={`${formatNumber(gm.loggedTotal)} sent (+${formatNumber(
                          groupOver
                        )})`}
                      />
                    )}
                  </div>
                  {showGroupTotals && gm && (
                    <p className="text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
                      {gm.targetValue !== undefined
                        ? `${formatNumber(groupCompleted)} / ${formatNumber(
                            gm.targetValue
                          )}${unit ? ` ${unit}` : ''} (${Math.round(
                            gm.progressPercent ?? 0
                          )}%) · `
                        : gm.loggedTotal > 0
                        ? `${formatNumber(gm.loggedTotal)}${
                            unit ? ` ${unit}` : ''
                          } · `
                        : ''}
                      {gm.completedItemCount}/{gm.itemCount}{' '}
                      {itemNoun.toLowerCase()}s
                    </p>
                  )}
                </div>
              </button>
              <div className="flex items-center gap-1 shrink-0">
                <DaywellButton
                  label={`+ ${itemNoun}`}
                  variant="text"
                  size="compact"
                  onClick={() => {
                    setAddingItemGroupId(isAddingHere ? null : grp.id);
                    setNewItemTitle('');
                    setNewItemTarget('');
                  }}
                />
                <DaywellIconButton
                  label={`Edit ${grp.title}`}
                  size="compact"
                  tone="muted"
                  onClick={() => {
                    setEditingGroupId(isEditingGroup ? null : grp.id);
                    setEditingGroupTitle(grp.title ?? '');
                    setEditingGroupTarget(
                      grp.targetValue !== undefined ? String(grp.targetValue) : ''
                    );
                  }}
                  icon={<Edit3 className="w-3 h-3" />}
                />
                <DaywellIconButton
                  label={`Delete ${grp.title}`}
                  size="compact"
                  tone="danger"
                  onClick={() =>
                    onRunAction(() => projectsService.deleteRecord(grp.id))
                  }
                  icon={<Trash2 className="w-3 h-3" />}
                />
              </div>
            </div>

            {isEditingGroup && (
              <form
                onSubmit={submitGroupEdit}
                className="flex flex-wrap items-center gap-1.5 p-2 rounded-[var(--dw-radius-sm)] bg-[var(--dw-card)] border border-[var(--dw-border)]"
              >
                <input
                  type="text"
                  aria-label={`Edit ${groupNoun.toLowerCase()} title`}
                  placeholder={`${groupNoun} title...`}
                  value={editingGroupTitle}
                  onChange={(e) => setEditingGroupTitle(e.target.value)}
                  className="flex-1 min-w-[150px] min-h-[34px] px-2.5 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
                />
                <input
                  type="number"
                  min="0"
                  step="any"
                  aria-label={`Edit ${groupNoun.toLowerCase()} target`}
                  placeholder="Target"
                  value={editingGroupTarget}
                  onChange={(e) => setEditingGroupTarget(e.target.value)}
                  className="w-24 min-h-[34px] px-2 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-primary)] dw-type-numeric-body"
                />
                <DaywellButton
                  type="submit"
                  label="Save"
                  variant="primary"
                  size="compact"
                />
                <DaywellButton
                  label="Cancel"
                  variant="text"
                  size="compact"
                  onClick={() => setEditingGroupId(null)}
                />
              </form>
            )}

            {showGroupTotals && gm?.progressPercent !== undefined && (
              <DaywellProgressBar
                value={gm.progressPercent}
                label={`${grp.title} progress`}
              />
            )}

            {!isCollapsed && filteredChildren.length > 0 && (
              <div className="pl-1 grid grid-cols-1 md:grid-cols-2 gap-x-4">
                {filteredChildren.map(renderItemRow)}
              </div>
            )}

            {isAddingHere && (
              <div className="flex flex-wrap items-center gap-1.5 pt-1">
                <input
                  type="text"
                  placeholder={`${itemNoun} title...`}
                  value={newItemTitle}
                  onChange={(e) => setNewItemTitle(e.target.value)}
                  className="flex-1 min-w-[140px] min-h-[36px] px-2.5 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-card)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
                />
                <input
                  type="number"
                  min="0"
                  step="any"
                  placeholder="Target"
                  value={newItemTarget}
                  onChange={(e) => setNewItemTarget(e.target.value)}
                  className="w-20 min-h-[36px] px-2 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-card)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
                />
                <DaywellButton
                  label="Add"
                  variant="primary"
                  size="compact"
                  onClick={() => {
                    if (!newItemTitle.trim()) return;
                    const t = newItemTarget.trim()
                      ? Number(newItemTarget)
                      : undefined;
                    if (t !== undefined && (!Number.isFinite(t) || t < 0)) {
                      onError('Item target must be non-negative.');
                      return;
                    }
                    onRunAction(() => {
                      projectsService.createGroupedItem({
                        projectId,
                        blockId: block.id,
                        groupId: grp.id,
                        title: newItemTitle.trim(),
                        targetValue: t,
                      });
                      setAddingItemGroupId(null);
                      setNewItemTitle('');
                      setNewItemTarget('');
                    });
                  }}
                />
              </div>
            )}
          </div>
        );
      })}

      {ungroupedItems.length > 0 && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-x-4">
          {ungroupedItems.map(renderItemRow)}
        </div>
      )}

      {addingItemGroupId === '__ungrouped__' && (
        <div className="flex flex-wrap items-center gap-1.5">
          <input
            type="text"
            placeholder={`${itemNoun} title...`}
            value={newItemTitle}
            onChange={(e) => setNewItemTitle(e.target.value)}
            className="flex-1 min-w-[140px] min-h-[36px] px-2.5 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
          />
          <input
            type="number"
            min="0"
            step="any"
            placeholder="Target"
            value={newItemTarget}
            onChange={(e) => setNewItemTarget(e.target.value)}
            className="w-20 min-h-[36px] px-2 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
          />
          <DaywellButton
            label="Add"
            variant="primary"
            size="compact"
            onClick={() => {
              if (!newItemTitle.trim()) return;
              const t = newItemTarget.trim() ? Number(newItemTarget) : undefined;
              onRunAction(() => {
                projectsService.createGroupedItem({
                  projectId,
                  blockId: block.id,
                  title: newItemTitle.trim(),
                  targetValue: t,
                });
                setAddingItemGroupId(null);
                setNewItemTitle('');
                setNewItemTarget('');
              });
            }}
          />
        </div>
      )}

      {showAddGroup && (
        <div className="flex flex-wrap items-center gap-1.5 p-2 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)]">
          <input
            type="text"
            placeholder={`New ${groupNoun.toLowerCase()} title...`}
            value={newGroupTitle}
            onChange={(e) => setNewGroupTitle(e.target.value)}
            className="flex-1 min-w-[140px] min-h-[36px] px-2.5 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-card)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
          />
          <input
            type="number"
            min="0"
            step="any"
            placeholder="Target"
            value={newGroupTarget}
            onChange={(e) => setNewGroupTarget(e.target.value)}
            className="w-20 min-h-[36px] px-2 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-card)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
          />
          <DaywellButton
            label={`Add ${groupNoun}`}
            variant="primary"
            size="compact"
            onClick={() => {
              if (!newGroupTitle.trim()) return;
              const t = newGroupTarget.trim()
                ? Number(newGroupTarget)
                : undefined;
              onRunAction(() => {
                projectsService.createGroup({
                  projectId,
                  blockId: block.id,
                  title: newGroupTitle.trim(),
                  targetValue: t,
                });
                setNewGroupTitle('');
                setNewGroupTarget('');
                setShowAddGroup(false);
              });
            }}
          />
        </div>
      )}

      <div className="flex flex-wrap items-center gap-2 pt-1">
        <DaywellButton
          label={`+ Add ${groupNoun}`}
          variant="outlined"
          size="compact"
          leadingIcon={<FolderPlus className="w-3.5 h-3.5" />}
          onClick={() => setShowAddGroup(!showAddGroup)}
        />
        <DaywellButton
          label={`+ Add ${itemNoun}`}
          variant="text"
          size="compact"
          onClick={() => {
            setAddingItemGroupId(
              addingItemGroupId === '__ungrouped__' ? null : '__ungrouped__'
            );
            setNewItemTitle('');
            setNewItemTarget('');
          }}
        />
      </div>
    </div>
  );
}

function ScheduleBlockBody(props: {
  projectId: string;
  block: SharedProjectTrackingBlock;
  records: SharedProjectTrackingRecord[];
  metric?: ProjectBlockProgressMetric;
  showAddSchedule: boolean;
  setShowAddSchedule: (v: boolean) => void;
  newSchedTitle: string;
  setNewSchedTitle: (v: string) => void;
  newSchedDate: string;
  setNewSchedDate: (v: string) => void;
  newSchedDuration: string;
  setNewSchedDuration: (v: string) => void;
  loggingSchedId: string | null;
  setLoggingSchedId: (v: string | null) => void;
  schedLogMinutes: string;
  setSchedLogMinutes: (v: string) => void;
  schedLogDate: string;
  setSchedLogDate: (v: string) => void;
  onRunAction: (fn: () => void) => void;
  onError: (msg: string) => void;
}) {
  const {
    projectId,
    block,
    records,
    metric,
    showAddSchedule,
    setShowAddSchedule,
    newSchedTitle,
    setNewSchedTitle,
    newSchedDate,
    setNewSchedDate,
    newSchedDuration,
    setNewSchedDuration,
    loggingSchedId,
    setLoggingSchedId,
    schedLogMinutes,
    setSchedLogMinutes,
    schedLogDate,
    setSchedLogDate,
    onRunAction,
    onError,
  } = props;

  const [editingSchedId, setEditingSchedId] = useState<string | null>(null);
  const [editingSchedTitle, setEditingSchedTitle] = useState('');
  const [editingSchedDate, setEditingSchedDate] = useState('');
  const [editingSchedDuration, setEditingSchedDuration] = useState('');

  const cfg = parseScheduleBlockConfig(block.config);
  const items = records.filter((r) => r.recordType === 'schedule_item');
  const itemTotals = metric?.itemTotals ?? {};

  const ruleText =
    cfg.completionRule === 'manual'
      ? 'Manual completion'
      : cfg.completionRule === 'exact_duration'
      ? 'Auto-completes at 100% planned minutes'
      : `Auto-completes at ${Math.round(
          cfg.autoCompleteThresholdRatio * 100
        )}% planned minutes`;

  return (
    <div className="space-y-2.5">
      <p className="text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
        {ruleText}
        {cfg.trackActualDuration && metric && metric.plannedDurationMinutes > 0
          ? ` · Logged ${metric.actualLoggedDurationMinutes} of ${metric.plannedDurationMinutes} min`
          : ''}
      </p>

      <div className="space-y-1.5">
        {items.map((item) => {
          const loggedMins = itemTotals[item.id] ?? 0;
          const isLogging = loggingSchedId === item.id;
          const isEditing = editingSchedId === item.id;
          const schedCal = item.scheduledDate
            ? CalendarDate.tryParse(item.scheduledDate)
            : undefined;
          const dateSubtitle = schedCal
            ? SharedDateFormatter.formatDual(schedCal)
            : item.scheduledDate;

          const submitScheduleEdit = (e: React.FormEvent) => {
            e.preventDefault();
            const cleanTitle = editingSchedTitle.trim();
            if (!cleanTitle) {
              onError('Session title is required.');
              return;
            }
            const cleanDate = editingSchedDate.trim() || undefined;
            if (cleanDate && !CalendarDate.tryParse(cleanDate)) {
              onError('Scheduled date must be a valid date.');
              return;
            }
            let parsedMins: number | undefined;
            if (editingSchedDuration.trim()) {
              const raw = Number(editingSchedDuration);
              if (!Number.isFinite(raw) || raw < 0) {
                onError('Duration must be non-negative minutes.');
                return;
              }
              parsedMins = Math.round(raw);
            }
            const nextSession: SharedProjectTrackingRecord = {
              ...item,
              title: cleanTitle,
            };
            if (cleanDate !== undefined) {
              nextSession.scheduledDate = cleanDate;
            } else {
              delete nextSession.scheduledDate;
            }
            if (parsedMins !== undefined) {
              nextSession.durationMinutes = parsedMins;
            } else {
              delete nextSession.durationMinutes;
            }
            onRunAction(() => {
              projectsService.updateRecord(nextSession);
              setEditingSchedId(null);
            });
          };

          return (
            <div
              key={item.id}
              className="py-1.5 border-b border-[var(--dw-divider)] last:border-b-0 space-y-1.5"
            >
              {isEditing ? (
                <form
                  onSubmit={submitScheduleEdit}
                  className="p-2 rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] space-y-2"
                >
                  <div className="flex flex-wrap items-center gap-1.5">
                    <input
                      type="text"
                      aria-label={`Edit session title for ${item.title}`}
                      placeholder="Session title..."
                      value={editingSchedTitle}
                      onChange={(e) => setEditingSchedTitle(e.target.value)}
                      className="flex-1 min-w-[160px] min-h-[34px] px-2.5 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-card)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
                    />
                    <input
                      type="date"
                      aria-label={`Edit scheduled date for ${item.title}`}
                      value={editingSchedDate}
                      onChange={(e) => setEditingSchedDate(e.target.value)}
                      className="min-h-[34px] px-2 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-card)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
                    />
                    <input
                      type="number"
                      min="0"
                      step="1"
                      aria-label={`Edit planned minutes for ${item.title}`}
                      placeholder="Min"
                      value={editingSchedDuration}
                      onChange={(e) => setEditingSchedDuration(e.target.value)}
                      className="w-20 min-h-[34px] px-2 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-card)] border border-[var(--dw-border)] text-[var(--dw-text-primary)] dw-type-numeric-body"
                    />
                    <DaywellButton
                      type="submit"
                      label="Save"
                      variant="primary"
                      size="compact"
                    />
                    <DaywellButton
                      label="Cancel"
                      variant="text"
                      size="compact"
                      onClick={() => setEditingSchedId(null)}
                    />
                  </div>
                </form>
              ) : (
                <div className="flex items-start justify-between gap-2">
                  <button
                    type="button"
                    onClick={() =>
                      onRunAction(() => projectsService.toggleRecordCompleted(item))
                    }
                    className="flex items-start gap-2.5 flex-1 min-w-0 text-left cursor-pointer"
                  >
                    <span
                      className={`mt-0.5 w-4 h-4 rounded-[var(--dw-radius-sm)] border flex items-center justify-center shrink-0 ${
                        item.isCompleted
                          ? 'bg-[var(--dw-primary)] border-[var(--dw-primary)] text-[var(--dw-on-primary)]'
                          : 'border-[var(--dw-border)]'
                      }`}
                    >
                      {item.isCompleted && <Check className="w-3 h-3 stroke-[3]" />}
                    </span>
                    <div className="min-w-0">
                      <p
                        className={`text-xs truncate ${
                          item.isCompleted
                            ? 'line-through text-[var(--dw-text-muted)]'
                            : 'text-[var(--dw-text-primary)] font-medium'
                        }`}
                      >
                        {item.title}
                      </p>
                      <p className="text-[11px] text-[var(--dw-text-muted)] dw-type-numeric-body">
                        {[
                          dateSubtitle ?? null,
                          item.durationMinutes !== undefined
                            ? `${formatNumber(loggedMins)}/${item.durationMinutes} min`
                            : loggedMins > 0
                            ? `${formatNumber(loggedMins)} min logged`
                            : null,
                        ]
                          .filter(Boolean)
                          .join(' · ') || 'Unscheduled'}
                      </p>
                    </div>
                  </button>

                  <div className="flex items-center gap-0.5 shrink-0">
                    {cfg.trackActualDuration && (
                      <DaywellButton
                        label="+ Min"
                        variant="text"
                        size="compact"
                        onClick={() => {
                          setEditingSchedId(null);
                          setLoggingSchedId(isLogging ? null : item.id);
                          setSchedLogMinutes(
                            item.durationMinutes ? String(item.durationMinutes) : '30'
                          );
                        }}
                      />
                    )}
                    <DaywellIconButton
                      label={`Edit session ${item.title}`}
                      size="compact"
                      tone="muted"
                      onClick={() => {
                        setLoggingSchedId(null);
                        setEditingSchedId(item.id);
                        setEditingSchedTitle(item.title ?? '');
                        setEditingSchedDate(item.scheduledDate ?? '');
                        setEditingSchedDuration(
                          item.durationMinutes !== undefined
                            ? String(item.durationMinutes)
                            : ''
                        );
                      }}
                      icon={<Edit3 className="w-3 h-3" />}
                    />
                    <DaywellIconButton
                      label={`Delete session ${item.title}`}
                      size="compact"
                      tone="danger"
                      onClick={() =>
                        onRunAction(() => projectsService.deleteRecord(item.id))
                      }
                      icon={<Trash2 className="w-3 h-3" />}
                    />
                  </div>
                </div>
              )}

              {isLogging && !isEditing && (
                <div className="pl-6 flex flex-wrap items-center gap-1.5">
                  <input
                    type="number"
                    min="1"
                    step="any"
                    aria-label={`Minutes logged for ${item.title}`}
                    value={schedLogMinutes}
                    onChange={(e) => setSchedLogMinutes(e.target.value)}
                    className="w-20 min-h-[34px] px-2 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
                  />
                  <input
                    type="date"
                    value={schedLogDate}
                    onChange={(e) => setSchedLogDate(e.target.value)}
                    className="min-h-[34px] px-2 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
                  />
                  <DaywellButton
                    label="Log"
                    variant="primary"
                    size="compact"
                    onClick={() => {
                      const mins = Number(schedLogMinutes);
                      if (!Number.isFinite(mins) || mins <= 0) {
                        onError('Logged minutes must be greater than 0.');
                        return;
                      }
                      onRunAction(() => {
                        projectsService.logProgress({
                          projectId,
                          blockId: block.id,
                          parentRecordId: item.id,
                          deltaValue: mins,
                          recordedDate:
                            schedLogDate || CalendarDate.today().toIsoString(),
                        });
                        setLoggingSchedId(null);
                      });
                    }}
                  />
                </div>
              )}
            </div>
          );
        })}
      </div>

      {showAddSchedule ? (
        <div className="p-2.5 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] space-y-2">
          <div className="flex flex-wrap items-center gap-2">
            <input
              type="text"
              placeholder="Session title..."
              value={newSchedTitle}
              onChange={(e) => setNewSchedTitle(e.target.value)}
              className="flex-1 min-w-[160px] min-h-[38px] px-2.5 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-card)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
            />
            <input
              type="date"
              value={newSchedDate}
              onChange={(e) => setNewSchedDate(e.target.value)}
              className="min-h-[38px] px-2 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-card)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
            />
            <input
              type="number"
              min="0"
              placeholder="Min"
              value={newSchedDuration}
              onChange={(e) => setNewSchedDuration(e.target.value)}
              className="w-20 min-h-[38px] px-2 py-1 text-xs rounded-[var(--dw-radius-sm)] bg-[var(--dw-card)] border border-[var(--dw-border)] text-[var(--dw-text-primary)]"
            />
          </div>
          <div className="flex justify-end gap-2">
            <DaywellButton
              label="Cancel"
              variant="text"
              size="compact"
              onClick={() => setShowAddSchedule(false)}
            />
            <DaywellButton
              label="Add Session"
              variant="primary"
              size="compact"
              onClick={() => {
                if (!newSchedTitle.trim()) return;
                const mins = newSchedDuration.trim()
                  ? Math.round(Number(newSchedDuration))
                  : undefined;
                if (mins !== undefined && (!Number.isFinite(mins) || mins < 0)) {
                  onError('Duration must be non-negative minutes.');
                  return;
                }
                onRunAction(() => {
                  projectsService.createScheduleItem({
                    projectId,
                    blockId: block.id,
                    title: newSchedTitle.trim(),
                    scheduledDate: newSchedDate || undefined,
                    durationMinutes: mins,
                  });
                  setNewSchedTitle('');
                  setShowAddSchedule(false);
                });
              }}
            />
          </div>
        </div>
      ) : (
        <DaywellButton
          label="+ Add Session"
          variant="outlined"
          size="compact"
          onClick={() => setShowAddSchedule(true)}
        />
      )}
    </div>
  );
}
