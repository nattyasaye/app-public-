import { CalendarDate, EthiopiaClock } from './date';
import {
  CANONICAL_DAILY_RHYTHM_DAY_STATUSES,
  CANONICAL_DAILY_RHYTHM_FINANCE_CLOSE_STATUSES,
  SHARED_BUSINESS_RULES,
  SharedDailyRhythmDay,
  SharedDailyRhythmDayStatus,
  SharedDailyRhythmFinanceCloseStatus,
  SharedDailyRhythmTaskReviewEvidence,
} from './sharedFoundation';

export {
  CANONICAL_DAILY_RHYTHM_DAY_STATUSES,
  CANONICAL_DAILY_RHYTHM_FINANCE_CLOSE_STATUSES,
};

export type DailyRhythmDayStatus = SharedDailyRhythmDayStatus;
export type DailyRhythmFinanceCloseStatus = SharedDailyRhythmFinanceCloseStatus;
export type DailyRhythmTaskReviewEvidence = SharedDailyRhythmTaskReviewEvidence;
export type DailyRhythmDayRecord = SharedDailyRhythmDay;

export const DAILY_RHYTHM_RULES = SHARED_BUSINESS_RULES.dailyRhythm;

export const DAILY_RHYTHM_QUALIFYING_DAYS_PER_FREEZE =
  DAILY_RHYTHM_RULES.qualifyingDaysPerFreeze;
export const DAILY_RHYTHM_MAX_STREAK_FREEZES =
  DAILY_RHYTHM_RULES.maxStreakFreezes;
export const DAILY_RHYTHM_MAX_PROTECTED_GAP_DAYS =
  DAILY_RHYTHM_RULES.maxProtectedGapDays;

const DETERMINISTIC_EPOCH_ISO = '1970-01-01T00:00:00.000Z';

export type DailyRhythmMutationReason =
  | 'updated'
  | 'past_day_locked'
  | 'future_day_locked'
  | 'unchanged'
  | 'invalid_date';

export interface DailyRhythmMutationResult {
  applied: boolean;
  reason: DailyRhythmMutationReason;
  record: DailyRhythmDayRecord;
}

export interface DailyRhythmTodayOptions {
  todayIso?: string;
  today?: CalendarDate;
  todayInstant?: Date;
}

export interface DailyRhythmEvaluatedDay {
  dateIso: string;
  ethiopianDateIso: string;
  record: DailyRhythmDayRecord;
  status: DailyRhythmDayStatus;
  faithComplete: boolean;
  tasksComplete: boolean;
  financeComplete: boolean;
  completedResponsibilities: number;
  qualifies: boolean;
  isToday: boolean;
  isProvisionalFreeze: boolean;
  streakAfterDay: number;
  bestStreakAfterDay: number;
  totalQualifyingDaysAfterDay: number;
  availableFreezesAfterDay: number;
}

export interface DailyRhythmTimelineSummary {
  todayIso: string;
  todayEthiopianIso: string;
  todayStatus: DailyRhythmDayStatus;
  todayRecord: DailyRhythmDayRecord;
  todayFaithComplete: boolean;
  todayTasksComplete: boolean;
  todayFinanceComplete: boolean;
  todayCompletedResponsibilities: number;
  isTodayInProgress: boolean;
  currentStreak: number;
  bestStreak: number;
  totalQualifyingDays: number;
  availableFreezes: number;
  daysTowardNextFreeze: number;
  daysUntilNextFreeze: number;
  freezesEarnedTotal: number;
  freezesUsedTotal: number;
  provisionalFreezeActive: boolean;
  startDateIso?: string;
  days: DailyRhythmEvaluatedDay[];
  byDate: Record<string, DailyRhythmEvaluatedDay>;
}

function clampNonNegativeInt(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return 0;
  const truncated = Math.trunc(value);
  return truncated < 0 ? 0 : truncated;
}

function normalizeOptionalIsoTimestamp(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

export function resolveDailyRhythmToday(
  options?: DailyRhythmTodayOptions
): CalendarDate {
  if (options?.today) return options.today;
  if (options?.todayIso !== undefined) {
    return CalendarDate.parse(options.todayIso);
  }
  if (options?.todayInstant !== undefined) {
    return CalendarDate.fromUtcInstantInEthiopia(options.todayInstant);
  }
  return CalendarDate.today();
}

function resolveNowIso(
  nowIso?: string,
  options?: DailyRhythmTodayOptions
): string {
  const explicit = normalizeOptionalIsoTimestamp(nowIso);
  if (explicit) return explicit;
  if (options?.todayInstant) return options.todayInstant.toISOString();
  return EthiopiaClock.nowUtc().toISOString();
}

export function normalizeDailyRhythmFinanceCloseStatus(
  status?: unknown
): DailyRhythmFinanceCloseStatus {
  const trimmed = typeof status === 'string' ? status.trim() : '';
  if (
    (CANONICAL_DAILY_RHYTHM_FINANCE_CLOSE_STATUSES as readonly string[]).includes(
      trimmed
    )
  ) {
    return trimmed as DailyRhythmFinanceCloseStatus;
  }
  return DAILY_RHYTHM_RULES.defaultFinanceCloseStatus;
}

export function normalizeDailyRhythmTaskReviewEvidence(
  raw: unknown
): DailyRhythmTaskReviewEvidence | undefined {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return undefined;
  const obj = raw as Record<string, unknown>;
  return {
    overdueCount: clampNonNegativeInt(obj.overdueCount),
    todayCount: clampNonNegativeInt(obj.todayCount),
    plannedCount: clampNonNegativeInt(obj.plannedCount),
    completedTodayCount: clampNonNegativeInt(obj.completedTodayCount),
  };
}

export function createEmptyDailyRhythmDay(
  dateIso: string,
  updatedAt = DETERMINISTIC_EPOCH_ISO
): DailyRhythmDayRecord {
  const parsedDate = CalendarDate.parse(dateIso);
  return {
    dateIso: parsedDate.toIsoString(),
    bibleStudyDone: false,
    prayerDone: false,
    taskReviewConfirmed: false,
    financeCloseStatus: DAILY_RHYTHM_RULES.defaultFinanceCloseStatus,
    updatedAt: normalizeOptionalIsoTimestamp(updatedAt) ?? DETERMINISTIC_EPOCH_ISO,
  };
}

export function normalizeDailyRhythmDay(
  raw: unknown
): DailyRhythmDayRecord | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const obj = raw as Record<string, unknown>;
  const rawDate = typeof obj.dateIso === 'string' ? obj.dateIso : '';
  const parsedDate = CalendarDate.tryParse(rawDate);
  if (!parsedDate) return null;

  const bibleStudyDone = obj.bibleStudyDone === true;
  const prayerDone = obj.prayerDone === true;
  const taskReviewConfirmed = obj.taskReviewConfirmed === true;
  const financeCloseStatus = normalizeDailyRhythmFinanceCloseStatus(
    obj.financeCloseStatus
  );

  const bibleStudyCompletedAt = bibleStudyDone
    ? normalizeOptionalIsoTimestamp(obj.bibleStudyCompletedAt)
    : undefined;
  const prayerCompletedAt = prayerDone
    ? normalizeOptionalIsoTimestamp(obj.prayerCompletedAt)
    : undefined;
  const taskReviewedAt = taskReviewConfirmed
    ? normalizeOptionalIsoTimestamp(obj.taskReviewedAt)
    : undefined;
  const taskReviewEvidence = taskReviewConfirmed
    ? normalizeDailyRhythmTaskReviewEvidence(obj.taskReviewEvidence)
    : undefined;
  const financeClosedAt = isDailyRhythmFinanceClosedStatus(financeCloseStatus)
    ? normalizeOptionalIsoTimestamp(obj.financeClosedAt)
    : undefined;
  const updatedAt =
    normalizeOptionalIsoTimestamp(obj.updatedAt) ?? DETERMINISTIC_EPOCH_ISO;

  return {
    dateIso: parsedDate.toIsoString(),
    bibleStudyDone,
    ...(bibleStudyCompletedAt !== undefined ? { bibleStudyCompletedAt } : {}),
    prayerDone,
    ...(prayerCompletedAt !== undefined ? { prayerCompletedAt } : {}),
    taskReviewConfirmed,
    ...(taskReviewedAt !== undefined ? { taskReviewedAt } : {}),
    ...(taskReviewEvidence !== undefined ? { taskReviewEvidence } : {}),
    financeCloseStatus,
    ...(financeClosedAt !== undefined ? { financeClosedAt } : {}),
    updatedAt,
  };
}

export function isDailyRhythmFaithComplete(day: DailyRhythmDayRecord): boolean {
  return day.bibleStudyDone === true && day.prayerDone === true;
}

export function isDailyRhythmTasksComplete(day: DailyRhythmDayRecord): boolean {
  return day.taskReviewConfirmed === true;
}

export function isDailyRhythmFinanceClosedStatus(
  status: DailyRhythmFinanceCloseStatus
): boolean {
  return (
    status === 'closed_with_transactions' ||
    status === 'closed_no_transactions'
  );
}

export function isDailyRhythmFinanceComplete(day: DailyRhythmDayRecord): boolean {
  return isDailyRhythmFinanceClosedStatus(day.financeCloseStatus);
}

export function countCompletedDailyRhythmResponsibilities(
  day: DailyRhythmDayRecord
): number {
  let count = 0;
  if (isDailyRhythmFaithComplete(day)) count += 1;
  if (isDailyRhythmTasksComplete(day)) count += 1;
  if (isDailyRhythmFinanceComplete(day)) count += 1;
  return count;
}

export function isDailyRhythmDayQualifying(day: DailyRhythmDayRecord): boolean {
  return (
    isDailyRhythmFaithComplete(day) &&
    isDailyRhythmTasksComplete(day) &&
    isDailyRhythmFinanceComplete(day)
  );
}

export function hasDailyRhythmAnyActivity(day: DailyRhythmDayRecord): boolean {
  return (
    day.bibleStudyDone ||
    day.prayerDone ||
    day.taskReviewConfirmed ||
    day.financeCloseStatus !== DAILY_RHYTHM_RULES.defaultFinanceCloseStatus
  );
}

function recordFreshnessEpoch(record: DailyRhythmDayRecord): number {
  const parsed = Date.parse(record.updatedAt);
  return Number.isFinite(parsed) ? parsed : 0;
}

function financeStatusRank(status: DailyRhythmFinanceCloseStatus): number {
  switch (status) {
    case 'closed_with_transactions':
      return 3;
    case 'closed_no_transactions':
      return 2;
    case 'needs_reconfirmation':
      return 1;
    case 'open':
    default:
      return 0;
  }
}

function compareCodeUnits(a: string, b: string): number {
  if (a === b) return 0;
  return a < b ? -1 : 1;
}

function compareRecordTieBreaker(
  candidate: DailyRhythmDayRecord,
  existing: DailyRhythmDayRecord
): number {
  const candidateUpdated = recordFreshnessEpoch(candidate);
  const existingUpdated = recordFreshnessEpoch(existing);
  if (candidateUpdated !== existingUpdated) {
    return candidateUpdated - existingUpdated;
  }
  if (candidate.updatedAt !== existing.updatedAt) {
    return compareCodeUnits(candidate.updatedAt, existing.updatedAt);
  }
  const candidateScore =
    (candidate.bibleStudyDone ? 1 : 0) +
    (candidate.prayerDone ? 1 : 0) +
    (candidate.taskReviewConfirmed ? 1 : 0) +
    financeStatusRank(candidate.financeCloseStatus);
  const existingScore =
    (existing.bibleStudyDone ? 1 : 0) +
    (existing.prayerDone ? 1 : 0) +
    (existing.taskReviewConfirmed ? 1 : 0) +
    financeStatusRank(existing.financeCloseStatus);
  if (candidateScore !== existingScore) {
    return candidateScore - existingScore;
  }
  return compareCodeUnits(JSON.stringify(candidate), JSON.stringify(existing));
}

export function normalizeDailyRhythmTimeline(
  records: Iterable<unknown>
): DailyRhythmDayRecord[] {
  const byDate = new Map<string, DailyRhythmDayRecord>();
  for (const raw of records) {
    const normalized = normalizeDailyRhythmDay(raw);
    if (!normalized) continue;
    const existing = byDate.get(normalized.dateIso);
    if (!existing || compareRecordTieBreaker(normalized, existing) > 0) {
      byDate.set(normalized.dateIso, normalized);
    }
  }
  return Array.from(byDate.values()).sort((a, b) =>
    a.dateIso.localeCompare(b.dateIso)
  );
}

function validateTodayOnlyMutation(
  dateIso: string,
  existingRecord: DailyRhythmDayRecord | null | undefined,
  options?: DailyRhythmTodayOptions
):
  | { ok: true; targetIso: string; baseRecord: DailyRhythmDayRecord }
  | { ok: false; result: DailyRhythmMutationResult } {
  const targetDate = CalendarDate.tryParse(dateIso);
  if (!targetDate) {
    const fallback = existingRecord
      ? normalizeDailyRhythmDay(existingRecord) ??
        createEmptyDailyRhythmDay(resolveDailyRhythmToday(options).toIsoString())
      : createEmptyDailyRhythmDay(resolveDailyRhythmToday(options).toIsoString());
    return {
      ok: false,
      result: {
        applied: false,
        reason: 'invalid_date',
        record: fallback,
      },
    };
  }

  const targetIso = targetDate.toIsoString();
  const normalizedExisting =
    (existingRecord ? normalizeDailyRhythmDay(existingRecord) : null) ??
    createEmptyDailyRhythmDay(targetIso);
  const baseRecord =
    normalizedExisting.dateIso === targetIso
      ? normalizedExisting
      : createEmptyDailyRhythmDay(targetIso);

  const today = resolveDailyRhythmToday(options);
  if (targetDate.isBefore(today)) {
    return {
      ok: false,
      result: {
        applied: false,
        reason: 'past_day_locked',
        record: baseRecord,
      },
    };
  }
  if (targetDate.isAfter(today)) {
    return {
      ok: false,
      result: {
        applied: false,
        reason: 'future_day_locked',
        record: baseRecord,
      },
    };
  }

  return { ok: true, targetIso, baseRecord };
}

export function updateDailyRhythmFaith(params: {
  record?: DailyRhythmDayRecord | null;
  dateIso: string;
  bibleStudyDone?: boolean;
  prayerDone?: boolean;
  nowIso?: string;
} & DailyRhythmTodayOptions): DailyRhythmMutationResult {
  const check = validateTodayOnlyMutation(params.dateIso, params.record, params);
  if (!check.ok) return check.result;

  const { baseRecord } = check;
  const now = resolveNowIso(params.nowIso, params);
  const nextBible =
    params.bibleStudyDone !== undefined
      ? params.bibleStudyDone
      : baseRecord.bibleStudyDone;
  const nextPrayer =
    params.prayerDone !== undefined ? params.prayerDone : baseRecord.prayerDone;

  if (
    nextBible === baseRecord.bibleStudyDone &&
    nextPrayer === baseRecord.prayerDone
  ) {
    return { applied: false, reason: 'unchanged', record: baseRecord };
  }

  const nextBibleAt = nextBible
    ? baseRecord.bibleStudyDone
      ? baseRecord.bibleStudyCompletedAt ?? now
      : now
    : undefined;
  const nextPrayerAt = nextPrayer
    ? baseRecord.prayerDone
      ? baseRecord.prayerCompletedAt ?? now
      : now
    : undefined;

  const updated: DailyRhythmDayRecord = {
    ...baseRecord,
    bibleStudyDone: nextBible,
    ...(nextBibleAt !== undefined ? { bibleStudyCompletedAt: nextBibleAt } : {}),
    prayerDone: nextPrayer,
    ...(nextPrayerAt !== undefined ? { prayerCompletedAt: nextPrayerAt } : {}),
    updatedAt: now,
  };
  if (!nextBible) delete updated.bibleStudyCompletedAt;
  if (!nextPrayer) delete updated.prayerCompletedAt;

  return { applied: true, reason: 'updated', record: updated };
}

export function confirmDailyRhythmTaskReview(params: {
  record?: DailyRhythmDayRecord | null;
  dateIso: string;
  evidence?: DailyRhythmTaskReviewEvidence;
  nowIso?: string;
} & DailyRhythmTodayOptions): DailyRhythmMutationResult {
  const check = validateTodayOnlyMutation(params.dateIso, params.record, params);
  if (!check.ok) return check.result;

  const { baseRecord } = check;
  const now = resolveNowIso(params.nowIso, params);
  const normalizedEvidence = params.evidence
    ? normalizeDailyRhythmTaskReviewEvidence(params.evidence)
    : baseRecord.taskReviewEvidence;

  const updated: DailyRhythmDayRecord = {
    ...baseRecord,
    taskReviewConfirmed: true,
    taskReviewedAt: now,
    ...(normalizedEvidence !== undefined
      ? { taskReviewEvidence: normalizedEvidence }
      : {}),
    updatedAt: now,
  };

  return { applied: true, reason: 'updated', record: updated };
}

export function confirmDailyRhythmFinanceClose(params: {
  record?: DailyRhythmDayRecord | null;
  dateIso: string;
  hasTransactions: boolean;
  nowIso?: string;
} & DailyRhythmTodayOptions): DailyRhythmMutationResult {
  const check = validateTodayOnlyMutation(params.dateIso, params.record, params);
  if (!check.ok) return check.result;

  const { baseRecord } = check;
  const now = resolveNowIso(params.nowIso, params);
  const nextStatus: DailyRhythmFinanceCloseStatus = params.hasTransactions
    ? 'closed_with_transactions'
    : 'closed_no_transactions';

  const updated: DailyRhythmDayRecord = {
    ...baseRecord,
    financeCloseStatus: nextStatus,
    financeClosedAt: now,
    updatedAt: now,
  };

  return { applied: true, reason: 'updated', record: updated };
}

export function reopenDailyRhythmFinanceDay(params: {
  record?: DailyRhythmDayRecord | null;
  dateIso: string;
  nowIso?: string;
} & DailyRhythmTodayOptions): DailyRhythmMutationResult {
  const check = validateTodayOnlyMutation(params.dateIso, params.record, params);
  if (!check.ok) return check.result;

  const { baseRecord } = check;
  if (baseRecord.financeCloseStatus === 'open') {
    return { applied: false, reason: 'unchanged', record: baseRecord };
  }

  const now = resolveNowIso(params.nowIso, params);
  const updated: DailyRhythmDayRecord = {
    ...baseRecord,
    financeCloseStatus: 'open',
    updatedAt: now,
  };
  delete updated.financeClosedAt;

  return { applied: true, reason: 'updated', record: updated };
}

/**
 * Reacts to a Finance ledger change (create, edit, or void) on [dateIso].
 *
 * Historical protection rule:
 * - Only same-day ledger changes (`dateIso == todayIso`) require reconfirming
 *   an already-closed Finance Daily Rhythm status (`closed_* -> needs_reconfirmation`).
 * - Historical corrections (`dateIso < todayIso`) leave finalized historical Daily
 *   Rhythm check-ins untouched so past earned or spent freezes never vanish.
 */
export function applyDailyRhythmFinanceLedgerChange(params: {
  record?: DailyRhythmDayRecord | null;
  dateIso: string;
  nowIso?: string;
} & DailyRhythmTodayOptions): DailyRhythmMutationResult {
  const check = validateTodayOnlyMutation(params.dateIso, params.record, params);
  if (!check.ok) return check.result;

  const { baseRecord } = check;
  if (!isDailyRhythmFinanceClosedStatus(baseRecord.financeCloseStatus)) {
    return { applied: false, reason: 'unchanged', record: baseRecord };
  }

  const now = resolveNowIso(params.nowIso, params);
  const updated: DailyRhythmDayRecord = {
    ...baseRecord,
    financeCloseStatus: 'needs_reconfirmation',
    updatedAt: now,
  };
  delete updated.financeClosedAt;

  return { applied: true, reason: 'updated', record: updated };
}

function buildEvaluatedDay(params: {
  date: CalendarDate;
  record: DailyRhythmDayRecord;
  status: DailyRhythmDayStatus;
  qualifies: boolean;
  isToday: boolean;
  isProvisionalFreeze: boolean;
  streakAfterDay: number;
  bestStreakAfterDay: number;
  totalQualifyingDaysAfterDay: number;
  availableFreezesAfterDay: number;
}): DailyRhythmEvaluatedDay {
  const { record } = params;
  return {
    dateIso: params.date.toIsoString(),
    ethiopianDateIso: params.date.toEthiopian().toIsoString(),
    record,
    status: params.status,
    faithComplete: isDailyRhythmFaithComplete(record),
    tasksComplete: isDailyRhythmTasksComplete(record),
    financeComplete: isDailyRhythmFinanceComplete(record),
    completedResponsibilities: countCompletedDailyRhythmResponsibilities(record),
    qualifies: params.qualifies,
    isToday: params.isToday,
    isProvisionalFreeze: params.isProvisionalFreeze,
    streakAfterDay: params.streakAfterDay,
    bestStreakAfterDay: params.bestStreakAfterDay,
    totalQualifyingDaysAfterDay: params.totalQualifyingDaysAfterDay,
    availableFreezesAfterDay: params.availableFreezesAfterDay,
  };
}

export function evaluateDailyRhythmTimeline(
  records: Iterable<unknown>,
  options?: DailyRhythmTodayOptions
): DailyRhythmTimelineSummary {
  const today = resolveDailyRhythmToday(options);
  const todayIso = today.toIsoString();
  const todayEthiopianIso = today.toEthiopian().toIsoString();
  const normalizedList = normalizeDailyRhythmTimeline(records);

  const byDateInput = new Map<string, DailyRhythmDayRecord>();
  let startDate: CalendarDate | null = null;

  for (const rec of normalizedList) {
    const recDate = CalendarDate.parse(rec.dateIso);
    if (recDate.isAfter(today)) continue;
    byDateInput.set(rec.dateIso, rec);
    if (startDate === null && hasDailyRhythmAnyActivity(rec)) {
      startDate = recDate;
    }
  }

  const todayRecord =
    byDateInput.get(todayIso) ?? createEmptyDailyRhythmDay(todayIso);

  if (startDate === null) {
    const todayQualifies = isDailyRhythmDayQualifying(todayRecord);
    const todayStatus: DailyRhythmDayStatus = todayQualifies
      ? 'complete'
      : hasDailyRhythmAnyActivity(todayRecord)
        ? 'partial'
        : 'untouched';
    const evaluatedToday = buildEvaluatedDay({
      date: today,
      record: todayRecord,
      status: todayStatus,
      qualifies: todayQualifies,
      isToday: true,
      isProvisionalFreeze: false,
      streakAfterDay: 0,
      bestStreakAfterDay: 0,
      totalQualifyingDaysAfterDay: 0,
      availableFreezesAfterDay: 0,
    });
    return {
      todayIso,
      todayEthiopianIso,
      todayStatus,
      todayRecord,
      todayFaithComplete: evaluatedToday.faithComplete,
      todayTasksComplete: evaluatedToday.tasksComplete,
      todayFinanceComplete: evaluatedToday.financeComplete,
      todayCompletedResponsibilities: evaluatedToday.completedResponsibilities,
      isTodayInProgress: !todayQualifies,
      currentStreak: 0,
      bestStreak: 0,
      totalQualifyingDays: 0,
      availableFreezes: 0,
      daysTowardNextFreeze: 0,
      daysUntilNextFreeze: DAILY_RHYTHM_QUALIFYING_DAYS_PER_FREEZE,
      freezesEarnedTotal: 0,
      freezesUsedTotal: 0,
      provisionalFreezeActive: false,
      days: [evaluatedToday],
      byDate: { [todayIso]: evaluatedToday },
    };
  }

  const totalDays = today.differenceInDays(startDate) + 1;
  const evaluatedDays: DailyRhythmEvaluatedDay[] = [];
  const evaluatedByDate: Record<string, DailyRhythmEvaluatedDay> = {};

  let currentStreak = 0;
  let bestStreak = 0;
  let totalQualifyingDays = 0;
  let availableFreezes = 0;
  let freezesEarnedTotal = 0;
  let freezesUsedTotal = 0;
  let provisionalFreezeActive = false;

  for (let offset = 0; offset < totalDays; offset++) {
    const dayDate = startDate.addDays(offset);
    const dayIso = dayDate.toIsoString();
    const record = byDateInput.get(dayIso) ?? createEmptyDailyRhythmDay(dayIso);
    const qualifies = isDailyRhythmDayQualifying(record);
    const isToday = dayDate.isSameDay(today);

    let status: DailyRhythmDayStatus;
    let isProvisionalFreeze = false;

    if (qualifies) {
      status = 'complete';
      currentStreak += 1;
      totalQualifyingDays += 1;
      if (currentStreak > bestStreak) {
        bestStreak = currentStreak;
      }
      if (totalQualifyingDays % DAILY_RHYTHM_QUALIFYING_DAYS_PER_FREEZE === 0) {
        if (availableFreezes < DAILY_RHYTHM_MAX_STREAK_FREEZES) {
          availableFreezes += 1;
          freezesEarnedTotal += 1;
        }
      }
    } else if (isToday) {
      status = hasDailyRhythmAnyActivity(record) ? 'partial' : 'untouched';
    } else {
      // Finished past day (dayDate < today) that did not qualify.
      if (currentStreak <= 0) {
        status = 'missed';
        currentStreak = 0;
      } else {
        const nextDay = dayDate.addDays(1);
        const nextIsToday = nextDay.isSameDay(today);
        if (nextIsToday) {
          // Yesterday missed while today is `today`:
          // If today has not qualified yet, protection is provisional and
          // reverts cleanly to `missed` tomorrow if today also misses.
          // Once today qualifies, protection is finalized (`isProvisionalFreeze = false`).
          const todayQualifies = isDailyRhythmDayQualifying(todayRecord);
          if (availableFreezes > 0) {
            status = 'freeze_protected';
            if (!todayQualifies) {
              isProvisionalFreeze = true;
              provisionalFreezeActive = true;
            }
            availableFreezes -= 1;
            freezesUsedTotal += 1;
          } else {
            status = 'missed';
            currentStreak = 0;
          }
        } else {
          // nextDay < today: check whether nextDay qualified so we only
          // protect an isolated 1-day gap (never part of a multi-day absence).
          const nextIso = nextDay.toIsoString();
          const nextRecord = byDateInput.get(nextIso);
          const nextQualifies =
            nextRecord !== undefined && isDailyRhythmDayQualifying(nextRecord);
          if (nextQualifies && availableFreezes > 0) {
            status = 'freeze_protected';
            availableFreezes -= 1;
            freezesUsedTotal += 1;
          } else {
            status = 'missed';
            currentStreak = 0;
          }
        }
      }
    }

    const evaluated = buildEvaluatedDay({
      date: dayDate,
      record,
      status,
      qualifies,
      isToday,
      isProvisionalFreeze,
      streakAfterDay: currentStreak,
      bestStreakAfterDay: bestStreak,
      totalQualifyingDaysAfterDay: totalQualifyingDays,
      availableFreezesAfterDay: availableFreezes,
    });
    evaluatedDays.push(evaluated);
    evaluatedByDate[dayIso] = evaluated;
  }

  const evaluatedToday = evaluatedByDate[todayIso];
  const daysTowardNextFreeze =
    totalQualifyingDays % DAILY_RHYTHM_QUALIFYING_DAYS_PER_FREEZE;
  const daysUntilNextFreeze =
    DAILY_RHYTHM_QUALIFYING_DAYS_PER_FREEZE - daysTowardNextFreeze;

  return {
    todayIso,
    todayEthiopianIso,
    todayStatus: evaluatedToday.status,
    todayRecord: evaluatedToday.record,
    todayFaithComplete: evaluatedToday.faithComplete,
    todayTasksComplete: evaluatedToday.tasksComplete,
    todayFinanceComplete: evaluatedToday.financeComplete,
    todayCompletedResponsibilities: evaluatedToday.completedResponsibilities,
    isTodayInProgress: !evaluatedToday.qualifies,
    currentStreak,
    bestStreak,
    totalQualifyingDays,
    availableFreezes,
    daysTowardNextFreeze,
    daysUntilNextFreeze,
    freezesEarnedTotal,
    freezesUsedTotal,
    provisionalFreezeActive,
    startDateIso: startDate.toIsoString(),
    days: evaluatedDays,
    byDate: evaluatedByDate,
  };
}
