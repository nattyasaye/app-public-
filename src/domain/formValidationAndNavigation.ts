/**
 * Form Validation, Input Handling, Dirty State Checking, and Navigation Management
 * Production-grade business logic layer for Daywell application.
 */

import { CalendarDate, DayTimeOfDay } from './date';
import { formatCentsAsInput, parseDecimalToCentsStrict } from './financialEngine';

const MAX_AMOUNT_CENTS = 100_000_000 * 100; // 100,000,000 ETB
const MAX_FEE_CENTS = 100_000 * 100; // 100,000 ETB

export interface ValidationResult<T = Record<string, string>> {
  isValid: boolean;
  errors: T;
}

// ----------------------------------------------------------------------------
// Numeric & Amount Parsing / Formatting Utilities (Task 06 & 07)
// ----------------------------------------------------------------------------

/**
 * Parses a decimal string (e.g. "120.50", " 1,250.75 ", ".5") into integer cents (1 ETB = 100 cents).
 * Uses pure integer string parsing with zero floating-point arithmetic.
 */
export function parseAmountToCents(amountStr: string): { valid: boolean; cents: number; error?: string } {
  if (typeof amountStr !== 'string') {
    return { valid: false, cents: 0, error: 'Amount must be a text value' };
  }

  const cleaned = amountStr.trim().replace(/,/g, '');
  if (!cleaned) {
    return { valid: false, cents: 0, error: 'Amount is required' };
  }

  const decimalRegex = /^(\d+)?(\.\d{1,2})?$/;
  if (!decimalRegex.test(cleaned) || cleaned === '.') {
    return { valid: false, cents: 0, error: 'Enter a valid amount (maximum 2 decimal places, e.g. 150.00)' };
  }

  const parsed = parseDecimalToCentsStrict(cleaned);
  if (!parsed.valid) {
    return { valid: false, cents: 0, error: 'Enter a valid numerical amount' };
  }

  if (parsed.cents <= 0) {
    return { valid: false, cents: 0, error: 'Amount must be greater than zero' };
  }

  if (parsed.cents > MAX_AMOUNT_CENTS) {
    return { valid: false, cents: 0, error: 'Amount exceeds maximum allowable limit (100,000,000 ETB)' };
  }

  return { valid: true, cents: parsed.cents };
}

/**
 * Validates a transfer fee string (can be zero or empty) using pure integer parsing.
 */
export function parseFeeToCents(feeStr?: string): { valid: boolean; cents: number; error?: string } {
  if (!feeStr || !feeStr.trim()) {
    return { valid: true, cents: 0 };
  }
  const cleaned = feeStr.trim().replace(/,/g, '');
  if (cleaned.startsWith('-')) {
    return { valid: false, cents: 0, error: 'Fee cannot be negative' };
  }
  const decimalRegex = /^(\d+)?(\.\d{1,2})?$/;
  if (!decimalRegex.test(cleaned) || cleaned === '.') {
    return { valid: false, cents: 0, error: 'Fee must be a valid number (maximum 2 decimal places)' };
  }
  const parsed = parseDecimalToCentsStrict(cleaned);
  if (!parsed.valid || parsed.cents < 0) {
    return { valid: false, cents: 0, error: 'Fee cannot be negative' };
  }
  if (parsed.cents > MAX_FEE_CENTS) {
    return { valid: false, cents: 0, error: 'Fee exceeds reasonable limit (100,000 ETB)' };
  }
  return { valid: true, cents: parsed.cents };
}

// ----------------------------------------------------------------------------
// Date & Time Validation Utilities (Task 06 & 07)
// ----------------------------------------------------------------------------

export function isValidDateFormat(dateStr: string): boolean {
  const parsed = CalendarDate.tryParse(dateStr);
  if (!parsed) return false;
  return parsed.year >= 1900 && parsed.year <= 2100;
}

export function isValidTimeFormat(timeStr: string): boolean {
  return DayTimeOfDay.tryParse(timeStr) !== null;
}

/**
 * Checks whether start time is strictly before or equal to end time.
 */
export function validateTimeRange(startTime: string, endTime: string): { valid: boolean; error?: string } {
  if (!isValidTimeFormat(startTime)) {
    return { valid: false, error: 'Start time is not a valid time (HH:MM)' };
  }
  if (!isValidTimeFormat(endTime)) {
    return { valid: false, error: 'End time is not a valid time (HH:MM)' };
  }
  if (startTime > endTime) {
    return { valid: false, error: 'End time cannot be earlier than start time' };
  }
  return { valid: true };
}

// ----------------------------------------------------------------------------
// Task Form Validation (Task 07)
// ----------------------------------------------------------------------------

export interface TaskFormInput {
  title: string;
  description?: string;
  dueDate?: string;
  scheduledDate?: string;
  scheduledTime?: string;
}

export function validateTaskForm(input: TaskFormInput): ValidationResult {
  const errors: Record<string, string> = {};

  // Title: required, non-whitespace
  if (!input.title || !input.title.trim()) {
    errors.title = 'Task title is required';
  } else if (input.title.trim().length > 250) {
    errors.title = 'Task title cannot exceed 250 characters';
  }

  // Due Date: optional, but must be valid if given
  if (input.dueDate && input.dueDate.trim() && !isValidDateFormat(input.dueDate)) {
    errors.dueDate = 'Due date must be a valid date (YYYY-MM-DD)';
  }

  // Scheduled Date: optional, but must be valid if given
  if (input.scheduledDate && input.scheduledDate.trim() && !isValidDateFormat(input.scheduledDate)) {
    errors.scheduledDate = 'Scheduled date must be a valid date (YYYY-MM-DD)';
  }

  // Scheduled Time: optional, but must be valid HH:MM if given
  if (input.scheduledTime && input.scheduledTime.trim() && !isValidTimeFormat(input.scheduledTime)) {
    errors.scheduledTime = 'Scheduled time must be a valid time (HH:MM)';
  }

  return {
    isValid: Object.keys(errors).length === 0,
    errors,
  };
}

// ----------------------------------------------------------------------------
// Calendar Event Form Validation (Task 07)
// ----------------------------------------------------------------------------

export interface CalendarEventFormInput {
  title: string;
  date: string;
  endDate?: string;
  isAllDay: boolean;
  startTime?: string;
  endTime?: string;
  location?: string;
}

export function validateCalendarEventForm(input: CalendarEventFormInput): ValidationResult {
  const errors: Record<string, string> = {};

  if (!input.title || !input.title.trim()) {
    errors.title = 'Event title is required';
  } else if (input.title.trim().length > 200) {
    errors.title = 'Event title cannot exceed 200 characters';
  }

  const parsedStart = input.date ? CalendarDate.tryParse(input.date) : null;
  if (!parsedStart || parsedStart.year < 1900 || parsedStart.year > 2100) {
    errors.date = 'Please select a valid date';
  }

  let isMultiDay = false;
  if (input.endDate && input.endDate.trim()) {
    const parsedEnd = CalendarDate.tryParse(input.endDate);
    if (!parsedEnd || parsedEnd.year < 1900 || parsedEnd.year > 2100) {
      errors.endDate = 'Please select a valid end date';
    } else if (parsedStart && parsedEnd.isBefore(parsedStart)) {
      errors.endDate = 'End date cannot precede start date';
    } else if (parsedStart && parsedEnd.isAfter(parsedStart)) {
      isMultiDay = true;
    }
  }

  if (!input.isAllDay) {
    if (!input.startTime) {
      errors.startTime = 'Start time is required for timed events';
    } else if (!isValidTimeFormat(input.startTime)) {
      errors.startTime = 'Start time is invalid (HH:MM)';
    }

    if (!input.endTime) {
      errors.endTime = 'End time is required for timed events';
    } else if (!isValidTimeFormat(input.endTime)) {
      errors.endTime = 'End time is invalid (HH:MM)';
    }

    if (
      !isMultiDay &&
      input.startTime &&
      input.endTime &&
      isValidTimeFormat(input.startTime) &&
      isValidTimeFormat(input.endTime)
    ) {
      if (input.startTime > input.endTime) {
        errors.endTime = 'End time cannot be earlier than start time';
      }
    }
  }

  return {
    isValid: Object.keys(errors).length === 0,
    errors,
  };
}

// ----------------------------------------------------------------------------
// Finance Transaction Form Validation (Task 07)
// ----------------------------------------------------------------------------

export interface TransactionFormInput {
  amount: string;
  date: string;
  description: string;
  accountId: string;
  category?: string;
  partyName?: string;
  recordMode: 'direct_expense' | 'income' | 'lend' | 'borrow' | 'third_party_paid' | 'split';
  myShare?: string;
  theirShare?: string;
}

export function validateTransactionForm(input: TransactionFormInput): ValidationResult & { parsedCents: number } {
  const errors: Record<string, string> = {};

  // Amount
  const amountRes = parseAmountToCents(input.amount);
  if (!amountRes.valid) {
    errors.amount = amountRes.error || 'Invalid amount';
  }

  // Date
  if (!input.date || !isValidDateFormat(input.date)) {
    errors.date = 'Please provide a valid date';
  }

  // Account
  if (!input.accountId || !input.accountId.trim()) {
    errors.accountId = 'Please select an account';
  }

  // Party Name required for third party, lend, borrow, split
  if (['lend', 'borrow', 'third_party_paid', 'split'].includes(input.recordMode)) {
    if (!input.partyName || !input.partyName.trim()) {
      errors.partyName = 'Contact / Party name is required for debt & split transactions';
    }
  }

  // Split shares verification
  if (input.recordMode === 'split') {
    const myShareRes = parseAmountToCents(input.myShare || '0');
    const theirShareRes = parseAmountToCents(input.theirShare || '0');

    if (!myShareRes.valid) {
      errors.myShare = 'Enter your valid share';
    }
    if (!theirShareRes.valid) {
      errors.theirShare = 'Enter their valid share';
    }

    if (amountRes.valid && myShareRes.valid && theirShareRes.valid) {
      const sum = myShareRes.cents + theirShareRes.cents;
      if (sum !== amountRes.cents) {
        errors.splitSum = `Shares sum (${formatCentsAsInput(sum)} ETB) must equal total amount (${formatCentsAsInput(amountRes.cents)} ETB)`;
      }
    }
  }

  return {
    isValid: Object.keys(errors).length === 0,
    errors,
    parsedCents: amountRes.cents || 0,
  };
}

// ----------------------------------------------------------------------------
// Transfer Form Validation (Task 07)
// ----------------------------------------------------------------------------

export interface TransferFormInput {
  amount: string;
  fee?: string;
  sourceAccountId: string;
  destAccountId: string;
  date: string;
}

export function validateTransferForm(input: TransferFormInput): ValidationResult & { parsedAmountCents: number; parsedFeeCents: number } {
  const errors: Record<string, string> = {};

  const amountRes = parseAmountToCents(input.amount);
  if (!amountRes.valid) {
    errors.amount = amountRes.error || 'Invalid amount';
  }

  const feeRes = parseFeeToCents(input.fee);
  if (!feeRes.valid) {
    errors.fee = feeRes.error || 'Invalid fee';
  }

  if (!input.sourceAccountId) {
    errors.sourceAccountId = 'Select a source account';
  }
  if (!input.destAccountId) {
    errors.destAccountId = 'Select a destination account';
  }
  if (input.sourceAccountId && input.destAccountId && input.sourceAccountId === input.destAccountId) {
    errors.destAccountId = 'Destination account cannot be the same as the source account';
  }

  if (!input.date || !isValidDateFormat(input.date)) {
    errors.date = 'Select a valid date';
  }

  return {
    isValid: Object.keys(errors).length === 0,
    errors,
    parsedAmountCents: amountRes.cents || 0,
    parsedFeeCents: feeRes.cents || 0,
  };
}

// ----------------------------------------------------------------------------
// Dirty Checking Utility (Task 09: Protect Unsaved Changes)
// ----------------------------------------------------------------------------

/**
 * Checks whether any value in `current` differs from `initial`.
 * Returns false if all values match (or are both equivalently empty).
 */
export function isFormDirty<T extends Record<string, any>>(initial: T, current: T, keys?: (keyof T)[]): boolean {
  const keysToCheck = (keys || Object.keys(current)) as (keyof T)[];

  for (const k of keysToCheck) {
    const initVal = initial[k];
    const currVal = current[k];

    // Arrays (e.g. subtasks, tags)
    if (Array.isArray(initVal) && Array.isArray(currVal)) {
      if (initVal.length !== currVal.length) return true;
      for (let i = 0; i < initVal.length; i++) {
        const itemInit = initVal[i];
        const itemCurr = currVal[i];
        if (typeof itemInit === 'object' && itemInit !== null && typeof itemCurr === 'object' && itemCurr !== null) {
          if (JSON.stringify(itemInit) !== JSON.stringify(itemCurr)) return true;
        } else if (itemInit !== itemCurr) {
          return true;
        }
      }
      continue;
    }

    // String normalization: treat undefined and '' as equivalent
    const normInit = typeof initVal === 'string' ? initVal.trim() : initVal ?? '';
    const normCurr = typeof currVal === 'string' ? currVal.trim() : currVal ?? '';

    if (normInit !== normCurr) {
      return true;
    }
  }

  return false;
}

// ----------------------------------------------------------------------------
// Navigation & Modal Stack Manager (Task 10)
// ----------------------------------------------------------------------------

export class NavigationManager {
  private modalStack: string[] = [];
  private screenHistory: string[] = ['today'];

  constructor(initialScreen: string = 'today') {
    this.screenHistory = [initialScreen];
  }

  pushModal(modalId: string): void {
    if (!this.modalStack.includes(modalId)) {
      this.modalStack.push(modalId);
    }
  }

  removeModal(modalId: string): void {
    this.modalStack = this.modalStack.filter((id) => id !== modalId);
  }

  hasOpenModal(): boolean {
    return this.modalStack.length > 0;
  }

  getTopModal(): string | null {
    return this.modalStack.length > 0 ? this.modalStack[this.modalStack.length - 1] : null;
  }

  navigateToScreen(screen: string): { changed: boolean; newHistory: string[] } {
    const current = this.getCurrentScreen();
    if (current === screen) {
      return { changed: false, newHistory: [...this.screenHistory] };
    }
    this.screenHistory.push(screen);
    return { changed: true, newHistory: [...this.screenHistory] };
  }

  getCurrentScreen(): string {
    return this.screenHistory[this.screenHistory.length - 1] || 'today';
  }

  getHistory(): string[] {
    return [...this.screenHistory];
  }

  /**
   * Evaluates a Back action.
   * If any modal is open, pops the top modal FIRST.
   * Otherwise, pops the screen history.
   */
  handleBack(): {
    type: 'close_modal' | 'navigate_screen' | 'noop';
    closedModalId?: string;
    targetScreen?: string;
  } {
    if (this.modalStack.length > 0) {
      const closedModalId = this.modalStack.pop();
      return { type: 'close_modal', closedModalId };
    }

    if (this.screenHistory.length > 1) {
      this.screenHistory.pop();
      const targetScreen = this.getCurrentScreen();
      return { type: 'navigate_screen', targetScreen };
    }

    return { type: 'noop', targetScreen: 'today' };
  }
}
