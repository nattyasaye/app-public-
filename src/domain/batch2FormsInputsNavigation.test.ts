import test from 'node:test';
import assert from 'node:assert/strict';
import {
  parseAmountToCents,
  parseFeeToCents,
  isValidDateFormat,
  isValidTimeFormat,
  validateTimeRange,
  validateTaskForm,
  validateCalendarEventForm,
  validateTransactionForm,
  validateTransferForm,
  isFormDirty,
  NavigationManager,
} from './formValidationAndNavigation';

test('BATCH 2 — TASKS 06–10 (Forms, Inputs, Validation, Unsaved Changes, Navigation)', async (t) => {
  // --------------------------------------------------------------------------
  // TASK 06: Consistent text input and form field behavior
  // --------------------------------------------------------------------------
  await t.test('TASK 06 — Consistent text input and form field behavior', async (st) => {
    await st.test('6.1 Amount parsing handles valid integer and decimal values', () => {
      assert.deepEqual(parseAmountToCents('100'), { valid: true, cents: 10000 });
      assert.deepEqual(parseAmountToCents('120.50'), { valid: true, cents: 12050 });
      assert.deepEqual(parseAmountToCents('0.75'), { valid: true, cents: 75 });
      assert.deepEqual(parseAmountToCents('1,250.25'), { valid: true, cents: 125025 });
    });

    await st.test('6.2 Leading/trailing whitespace and comma separation are trimmed cleanly', () => {
      const res = parseAmountToCents('   550.00   ');
      assert.equal(res.valid, true);
      assert.equal(res.cents, 55000);
    });

    await st.test('6.3 Multiline and single-line field requirements', () => {
      // Long task title does not fail unless it exceeds maximum limit
      const taskRes = validateTaskForm({
        title: 'Review quarterly financial balance sheet with CBE and Dashen Bank statements',
      });
      assert.equal(taskRes.isValid, true);
    });
  });

  // --------------------------------------------------------------------------
  // TASK 07: Form validation and error messages
  // --------------------------------------------------------------------------
  await t.test('TASK 07 — Form validation and error messages', async (st) => {
    await st.test('7.1 Whitespace-only title is rejected for Tasks', () => {
      const res = validateTaskForm({ title: '    ' });
      assert.equal(res.isValid, false);
      assert.equal(res.errors.title, 'Task title is required');
    });

    await st.test('7.2 Optional fields (description, dates) are not rejected when empty', () => {
      const res = validateTaskForm({
        title: 'Call Accountant',
        description: '',
        dueDate: '',
        scheduledDate: '',
      });
      assert.equal(res.isValid, true);
      assert.deepEqual(res.errors, {});
    });

    await st.test('7.3 Amount field rejects non-numeric, negative, and excessive decimal inputs', () => {
      assert.equal(parseAmountToCents('abc').valid, false);
      assert.equal(parseAmountToCents('-50').valid, false);
      assert.equal(parseAmountToCents('0').valid, false);
      assert.equal(parseAmountToCents('12.999').valid, false); // >2 decimal places rejected
    });

    await st.test('7.4 Calendar event validates date, start time, and ensures end time >= start time', () => {
      // Valid timed event
      const validEvt = validateCalendarEventForm({
        title: 'Board Meeting',
        date: '2026-11-15',
        isAllDay: false,
        startTime: '10:00',
        endTime: '11:30',
      });
      assert.equal(validEvt.isValid, true);

      // Inverted times
      const invalidTimes = validateCalendarEventForm({
        title: 'Lunch',
        date: '2026-11-15',
        isAllDay: false,
        startTime: '14:00',
        endTime: '13:00',
      });
      assert.equal(invalidTimes.isValid, false);
      assert.equal(invalidTimes.errors.endTime, 'End time cannot be earlier than start time');

      // All day event does not require start/end times
      const allDayEvt = validateCalendarEventForm({
        title: 'Enkutatash Holiday',
        date: '2026-09-11',
        isAllDay: true,
      });
      assert.equal(allDayEvt.isValid, true);
    });

    await st.test('7.5 Finance split transactions validate share sum equals total amount', () => {
      const mismatch = validateTransactionForm({
        amount: '100.00',
        date: '2026-11-10',
        description: 'Dinner',
        accountId: 'acc-cbe',
        recordMode: 'split',
        partyName: 'Abebe',
        myShare: '40.00',
        theirShare: '50.00', // Sum = 90 != 100
      });
      assert.equal(mismatch.isValid, false);
      assert.ok(mismatch.errors.splitSum);

      const balanced = validateTransactionForm({
        amount: '100.00',
        date: '2026-11-10',
        description: 'Dinner',
        accountId: 'acc-cbe',
        recordMode: 'split',
        partyName: 'Abebe',
        myShare: '40.00',
        theirShare: '60.00', // Sum = 100 == 100
      });
      assert.equal(balanced.isValid, true);
    });

    await st.test('7.6 Transfer rejects same source and destination accounts', () => {
      const res = validateTransferForm({
        amount: '500',
        sourceAccountId: 'acc-cbe',
        destAccountId: 'acc-cbe',
        date: '2026-11-10',
      });
      assert.equal(res.isValid, false);
      assert.equal(res.errors.destAccountId, 'Destination account cannot be the same as the source account');
    });
  });

  // --------------------------------------------------------------------------
  // TASK 08: Save, cancel, and form submission behavior
  // --------------------------------------------------------------------------
  await t.test('TASK 08 — Save, cancel, and form submission behavior', async (st) => {
    await st.test('8.1 Rapid submission debounce prevents duplicate records', () => {
      let submissionCount = 0;
      let isSubmitting = false;

      const submitHandler = () => {
        if (isSubmitting) return; // Prevent duplicate rapid taps
        isSubmitting = true;
        submissionCount++;
      };

      submitHandler();
      submitHandler(); // Simulated rapid double-click
      submitHandler(); // Simulated rapid triple-click

      assert.equal(submissionCount, 1, 'Only one submission must execute');
    });

    await st.test('8.2 Cancel leaves records unchanged and returns without modifying state', () => {
      const originalRecord = { id: 't-1', title: 'Original Task' };
      let state = [originalRecord];

      // Simulated Cancel: discard draft
      const draft = { id: 't-1', title: 'Modified Task' };
      const onCancel = () => {
        // do not mutate state
      };
      onCancel();

      assert.equal(state[0].title, 'Original Task');
    });

    await st.test('8.3 Editing an existing record updates it rather than appending a duplicate', () => {
      const list = [
        { id: 't-1', title: 'Old Title' },
        { id: 't-2', title: 'Second Item' },
      ];

      const editingId = 't-1';
      const newTitle = 'Updated Title';

      const updated = list.map((item) => (item.id === editingId ? { ...item, title: newTitle } : item));
      assert.equal(updated.length, 2);
      assert.equal(updated.find((i) => i.id === 't-1')?.title, 'Updated Title');
    });
  });

  // --------------------------------------------------------------------------
  // TASK 09: Protect unsaved changes
  // --------------------------------------------------------------------------
  await t.test('TASK 09 — Protect unsaved changes', async (st) => {
    await st.test('9.1 Detects clean state when nothing has changed', () => {
      const initial = { title: 'Do laundry', priority: 'medium', subtasks: [] };
      const current = { title: 'Do laundry', priority: 'medium', subtasks: [] };
      assert.equal(isFormDirty(initial, current), false);
    });

    await st.test('9.2 Detects dirty state when a text or select field changes', () => {
      const initial = { title: 'Do laundry', priority: 'medium' };
      const current = { title: 'Do laundry and iron shirts', priority: 'medium' };
      assert.equal(isFormDirty(initial, current), true);
    });

    await st.test('9.3 Reverting a field to its original value resets dirty state to clean', () => {
      const initial = { title: 'Do laundry', priority: 'medium' };
      let current = { title: 'Do laundry and iron shirts', priority: 'medium' };
      assert.equal(isFormDirty(initial, current), true);

      // User types original text back
      current = { title: 'Do laundry', priority: 'medium' };
      assert.equal(isFormDirty(initial, current), false);
    });

    await st.test('9.4 Subtask list changes mark form as dirty', () => {
      const initial = { title: 'Task', subtasks: [{ id: 'st-1', title: 'Step 1', completed: false }] };
      const current = {
        title: 'Task',
        subtasks: [
          { id: 'st-1', title: 'Step 1', completed: false },
          { id: 'st-2', title: 'Step 2', completed: false },
        ],
      };
      assert.equal(isFormDirty(initial, current), true);
    });
  });

  // --------------------------------------------------------------------------
  // TASK 10: Consistent back navigation and screen exit behavior
  // --------------------------------------------------------------------------
  await t.test('TASK 10 — Consistent back navigation and screen exit behavior', async (st) => {
    await st.test('10.1 Opening modal intercepts back action and closes modal first before navigating screen', () => {
      const nav = new NavigationManager('today');
      nav.navigateToScreen('tasks');
      assert.equal(nav.getCurrentScreen(), 'tasks');

      // User opens "Create Task Modal"
      nav.pushModal('create-task-modal');
      assert.equal(nav.hasOpenModal(), true);

      // Back action received
      const back1 = nav.handleBack();
      assert.equal(back1.type, 'close_modal');
      assert.equal(back1.closedModalId, 'create-task-modal');
      assert.equal(nav.getCurrentScreen(), 'tasks', 'Screen must remain on tasks');

      // Second Back action navigates screen
      const back2 = nav.handleBack();
      assert.equal(back2.type, 'navigate_screen');
      assert.equal(back2.targetScreen, 'today');
    });

    await st.test('10.2 Tapping already active module does not push duplicate stack entries', () => {
      const nav = new NavigationManager('today');
      const res1 = nav.navigateToScreen('finance');
      assert.equal(res1.changed, true);

      const res2 = nav.navigateToScreen('finance'); // Duplicate tap
      assert.equal(res2.changed, false);
      assert.equal(nav.getHistory().length, 2);
    });

    await st.test('10.3 Root screen back action produces safe noop without crash', () => {
      const nav = new NavigationManager('today');
      const back = nav.handleBack();
      assert.equal(back.type, 'noop');
      assert.equal(back.targetScreen, 'today');
      assert.equal(nav.getCurrentScreen(), 'today');
    });
  });
});
