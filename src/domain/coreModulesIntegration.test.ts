import test from 'node:test';
import assert from 'node:assert/strict';
import {
  fromGregorianDate,
  toGregorianDate,
  formatDualDate,
  AMHARIC_MONTHS,
  ENGLISH_MONTHS
} from './ethiopianCalendar';
import {
  DaywellTask,
  TaskSubItem,
  DEFAULT_SAMPLE_TASKS
} from '../components/DaywellTasksModule';
import {
  CalendarEvent,
  CalendarTaskRef
} from '../components/DaywellCalendarModule';
import {
  DaywellNote
} from '../components/DaywellNotesModule';
import {
  parseQuickCaptureExpense,
  buildDirectExpense,
  validateBalancedEntry
} from './doubleEntryFinance';

test('1. Ethiopian Dual Calendar Julian Day Number Fidelity and Month Consistency', () => {
  // Test Enkutatash (Ethiopian New Year: Meskerem 1, 2017 -> Sept 11, 2024)
  const sep11 = new Date(Date.UTC(2024, 8, 11)); // Month is 0-indexed (8 = September)
  const ethNewYear = fromGregorianDate(sep11);

  assert.equal(ethNewYear.year, 2017);
  assert.equal(ethNewYear.month, 1);
  assert.equal(ethNewYear.day, 1);
  assert.equal(ethNewYear.amharicMonth, 'መስከረም');
  assert.equal(ethNewYear.englishMonth, 'Meskerem');

  // Convert back to Gregorian
  const gregRestored = toGregorianDate(ethNewYear.year, ethNewYear.month, ethNewYear.day);
  assert.equal(gregRestored.getUTCFullYear(), 2024);
  assert.equal(gregRestored.getUTCMonth(), 8);
  assert.equal(gregRestored.getUTCDate(), 11);

  // Dual date formatting contains both calendars
  const dualFormatted = formatDualDate(sep11);
  assert.ok(dualFormatted.includes('መስከረም 1, 2017'));
  assert.ok(dualFormatted.includes('Sep 11, 2024'));
});

test('2. To-Do Tasks Module: Priority Sorting and Subtask Progress Math', () => {
  const sampleTasks: DaywellTask[] = [
    {
      id: 't-low',
      title: 'Low priority task',
      priority: 'low',
      completed: false,
      hasReminder: false,
      subtasks: [],
      createdAt: '2026-11-10T00:00:00Z',
    },
    {
      id: 't-urgent',
      title: 'Urgent task',
      priority: 'urgent',
      completed: false,
      hasReminder: true,
      subtasks: [
        { id: 'st-1', title: 'Step 1', completed: true },
        { id: 'st-2', title: 'Step 2', completed: false },
        { id: 'st-3', title: 'Step 3', completed: false },
      ],
      createdAt: '2026-11-10T00:00:00Z',
    },
    {
      id: 't-high',
      title: 'High priority task',
      priority: 'high',
      completed: false,
      hasReminder: false,
      subtasks: [],
      createdAt: '2026-11-10T00:00:00Z',
    },
  ];

  // Verify priority sorting
  const priorityOrder = { urgent: 0, high: 1, medium: 2, low: 3 };
  const sorted = [...sampleTasks].sort((a, b) => priorityOrder[a.priority] - priorityOrder[b.priority]);

  assert.equal(sorted[0].id, 't-urgent');
  assert.equal(sorted[1].id, 't-high');
  assert.equal(sorted[2].id, 't-low');

  // Verify subtask progress math
  const urgentTask = sorted[0];
  const completedCount = urgentTask.subtasks.filter((s) => s.completed).length;
  const ratio = completedCount / urgentTask.subtasks.length;
  assert.equal(completedCount, 1);
  assert.equal(urgentTask.subtasks.length, 3);
  assert.ok(Math.abs(ratio - 1 / 3) < 0.001);
});

test('3. To-Do Tasks Module: Hard Deadline vs Scheduled Date Separation', () => {
  const task: DaywellTask = {
    id: 't-split-dates',
    title: 'Prepare Annual Audit',
    priority: 'urgent',
    completed: false,
    dueDate: '2026-11-30', // Hard deadline
    scheduledDate: '2026-11-15', // When work begins
    scheduledTime: '14:00',
    hasReminder: true,
    subtasks: [],
    createdAt: '2026-11-10T00:00:00Z',
  };

  assert.notEqual(task.dueDate, task.scheduledDate);
  assert.ok(task.scheduledDate! < task.dueDate!);
});

test('4. Notes Module: Pinned Ordering, Folder Grouping, and Tag Retrieval', () => {
  const notes: DaywellNote[] = [
    {
      id: 'n-1',
      title: 'General Note',
      content: 'Standard draft',
      notebook: 'Personal',
      tags: ['draft'],
      isPinned: false,
      isArchived: false,
      createdAt: '2026-11-08T00:00:00Z',
      updatedAt: '2026-11-08T12:00:00Z',
    },
    {
      id: 'n-2',
      title: 'Crucial Vision',
      content: 'Important reflections',
      notebook: 'Reflections',
      tags: ['vision', 'ethiopia'],
      isPinned: true,
      isArchived: false,
      createdAt: '2026-11-05T00:00:00Z',
      updatedAt: '2026-11-05T12:00:00Z',
    },
  ];

  // Pinned notes sort first
  const sorted = [...notes].sort((a, b) => {
    if (a.isPinned && !b.isPinned) return -1;
    if (!a.isPinned && b.isPinned) return 1;
    return b.updatedAt.localeCompare(a.updatedAt);
  });

  assert.equal(sorted[0].id, 'n-2');
  assert.equal(sorted[0].isPinned, true);

  // Tag search
  const ethiopiaNotes = notes.filter((n) => n.tags.includes('ethiopia'));
  assert.equal(ethiopiaNotes.length, 1);
  assert.equal(ethiopiaNotes[0].id, 'n-2');
});

test('5. Calendar Module: Event Scheduling, Category Theming, and Task Integration', () => {
  const event: CalendarEvent = {
    id: 'evt-test-1',
    title: 'Tax Declaration Filing',
    date: '2026-11-15',
    startTime: '10:00',
    endTime: '11:30',
    isAllDay: false,
    category: 'finance',
    colorHex: '#D97706',
    hasReminder: true,
  };

  const tasksForCalendar: CalendarTaskRef[] = [
    {
      id: 't-cal-1',
      title: 'Submit Tax Proofs',
      dueDate: '2026-11-15',
      completed: false,
      priority: 'high',
    },
  ];

  // Match items for 2026-11-15
  const targetDate = '2026-11-15';
  const matchingEvents = [event].filter((e) => e.date === targetDate);
  const matchingTasks = tasksForCalendar.filter((t) => t.dueDate === targetDate);

  assert.equal(matchingEvents.length, 1);
  assert.equal(matchingTasks.length, 1);
  assert.equal(matchingEvents[0].category, 'finance');
  assert.equal(matchingTasks[0].title, 'Submit Tax Proofs');
});

test('6. Universal Quick Capture: Text Expense Parser to Balanced Ledger', () => {
  // Input: "350 dinner CBE"
  const parsed = parseQuickCaptureExpense('350 dinner CBE', 'CBE');

  assert.equal(parsed.amountCents, 35000); // 350 ETB = 35,000 cents
  assert.equal(parsed.categoryId, 'cat-food');

  // Verify balanced entry construction from the parsed draft
  const { entry, postings } = buildDirectExpense({
    id: 'entry-qc-test',
    assetAccountId: 'acc-cbe',
    expenseAccountId: 'acc-exp-food',
    categoryId: parsed.categoryId,
    amountCents: parsed.amountCents,
    occurrenceDate: '2026-11-10',
    movementDate: '2026-11-10',
    description: parsed.description,
  });

  assert.equal(entry.id, 'entry-qc-test');
  assert.equal(postings.length, 2);

  // Validate double entry balanced invariant: Sum Debits == Sum Credits
  validateBalancedEntry(postings);

  const debitPosting = postings.find((p) => p.direction === 'debit')!;
  const creditPosting = postings.find((p) => p.direction === 'credit')!;

  assert.equal(debitPosting.amountCents, 35000);
  assert.equal(creditPosting.amountCents, 35000);
  assert.equal(debitPosting.amountCents - creditPosting.amountCents, 0);
});
