import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  getAvailableNotesToLink,
  getNotesLinkedToTask,
  linkNoteToTask,
  TaskNoteRecord,
  undoTaskNoteLink,
  unlinkNoteFromTask,
  unlinkNotesForDeletedTask,
} from './taskNotes';
import {
  linkNoteToCalendarEvent,
  undoCalendarEventNoteLink,
  unlinkNoteFromCalendarEvent,
} from './calendarNotes';

const REPO_ROOT = process.cwd();

function readRepoFile(relPath: string): string {
  return fs.readFileSync(path.join(REPO_ROOT, relPath), 'utf8');
}

function makeNote(
  id: string,
  title: string,
  overrides: Partial<TaskNoteRecord> = {}
): TaskNoteRecord {
  return {
    id,
    title,
    content: overrides.content ?? '',
    notebook: overrides.notebook ?? 'Personal',
    tags: overrides.tags ?? [],
    isPinned: overrides.isPinned ?? false,
    isArchived: overrides.isArchived ?? false,
    ...(overrides.isFavorite !== undefined
      ? { isFavorite: overrides.isFavorite }
      : {}),
    ...(overrides.isTrashed !== undefined
      ? { isTrashed: overrides.isTrashed }
      : {}),
    ...(overrides.projectId !== undefined
      ? { projectId: overrides.projectId }
      : {}),
    ...(overrides.goalId !== undefined ? { goalId: overrides.goalId } : {}),
    ...(overrides.linkedModule !== undefined
      ? { linkedModule: overrides.linkedModule }
      : {}),
    ...(overrides.linkedId !== undefined
      ? { linkedId: overrides.linkedId }
      : {}),
    createdAt: overrides.createdAt ?? '2026-03-01T09:00:00.000Z',
    updatedAt: overrides.updatedAt ?? '2026-03-02T09:00:00.000Z',
  };
}

describe('STAGE N5.2.2 — CROSS-MODULE NOTE RELATIONSHIP PROTECTION', () => {
  it('1. Task -> Notes blocks silent overwrite of an existing Calendar relationship and surfaces linkedCalendarEventId', () => {
    const notes: TaskNoteRecord[] = [
      makeNote('n-cal', 'Board Meeting Notes', {
        linkedModule: 'calendar',
        linkedId: 'evt-board',
        projectId: 'proj-gov',
        goalId: 'goal-2026',
        notebook: 'Work',
        tags: ['board', 'q2'],
        isPinned: true,
        isFavorite: true,
        content: 'Review [[Q2 Targets]] before vote.',
      }),
      makeNote('n-cal-missing', 'Historical Event Memo', {
        linkedModule: 'calendar',
        linkedId: 'evt-missing-404',
        projectId: 'proj-archive',
      }),
    ];

    const available = getAvailableNotesToLink(notes, 'task-new');
    assert.strictEqual(available.length, 2);
    assert.strictEqual(available[0].linkedCalendarEventId, 'evt-board');
    assert.strictEqual(available[0].isLinkedToOtherModule, true);
    assert.strictEqual(available[1].linkedCalendarEventId, 'evt-missing-404');
    assert.strictEqual(available[1].isLinkedToOtherModule, true);

    const blockedDefault = linkNoteToTask(notes, 'n-cal', 'task-new');
    assert.strictEqual(blockedDefault.ok, false);
    assert.ok(blockedDefault.error?.includes('already linked to a Calendar event'));

    const blockedStrict = linkNoteToTask(
      notes,
      'n-cal',
      'task-new',
      new Date('2026-03-10T10:00:00.000Z'),
      { allowReassign: false }
    );
    assert.strictEqual(blockedStrict.ok, false);

    // Calendar relationship and all metadata stay intact
    const preserved = blockedDefault.notes.find((n) => n.id === 'n-cal')!;
    assert.strictEqual(preserved.linkedModule, 'calendar');
    assert.strictEqual(preserved.linkedId, 'evt-board');
    assert.strictEqual(preserved.projectId, 'proj-gov');
    assert.strictEqual(preserved.goalId, 'goal-2026');
    assert.strictEqual(preserved.notebook, 'Work');
    assert.deepStrictEqual(preserved.tags, ['board', 'q2']);
    assert.strictEqual(preserved.isPinned, true);
    assert.strictEqual(preserved.isFavorite, true);
    assert.strictEqual(preserved.content, 'Review [[Q2 Targets]] before vote.');
  });

  it('2 & 3. Cancelling preserves Calendar relationship; confirming replacement changes only the primary link while keeping metadata & Project link', () => {
    const initial: TaskNoteRecord[] = [
      makeNote('n-cal', 'Investor Update Prep', {
        linkedModule: 'calendar',
        linkedId: 'evt-investor',
        projectId: 'proj-fundraise',
        goalId: 'goal-series-a',
        notebook: 'Executive',
        tags: ['deck', 'finance'],
        isPinned: true,
        isArchived: true,
        isFavorite: true,
        content: 'Sync numbers with [[Data Room]]',
      }),
    ];

    // Simulated Cancel: UI aborts before calling linkNoteToTask(..., { allowReassign: true })
    const cancelledNotes = [...initial];
    assert.strictEqual(cancelledNotes[0].linkedModule, 'calendar');
    assert.strictEqual(cancelledNotes[0].linkedId, 'evt-investor');

    // Simulated Confirm: explicit allowReassign: true
    const confirmed = linkNoteToTask(
      cancelledNotes,
      'n-cal',
      'task-follow-up',
      new Date('2026-03-11T12:00:00.000Z'),
      { allowReassign: true }
    );
    assert.strictEqual(confirmed.ok, true);
    assert.strictEqual(confirmed.previousLinkedModule, 'calendar');
    assert.strictEqual(confirmed.previousLinkedId, 'evt-investor');

    const updated = confirmed.updatedNote!;
    assert.strictEqual(updated.linkedModule, 'tasks');
    assert.strictEqual(updated.linkedId, 'task-follow-up');
    // Project & unrelated metadata remain untouched
    assert.strictEqual(updated.projectId, 'proj-fundraise');
    assert.strictEqual(updated.goalId, 'goal-series-a');
    assert.strictEqual(updated.notebook, 'Executive');
    assert.deepStrictEqual(updated.tags, ['deck', 'finance']);
    assert.strictEqual(updated.isPinned, true);
    assert.strictEqual(updated.isArchived, true);
    assert.strictEqual(updated.isFavorite, true);
    assert.strictEqual(updated.content, 'Sync numbers with [[Data Room]]');

    assert.strictEqual(getNotesLinkedToTask(confirmed.notes, 'task-follow-up').length, 1);
  });

  it('4. Missing Calendar event references trigger explicit unavailable-event warnings without crashing in both Web & Flutter UI', () => {
    const tasksModule = readRepoFile('src/components/DaywellTasksModule.tsx');
    const notesModule = readRepoFile('src/components/DaywellNotesModule.tsx');
    const calendarNotesSection = readRepoFile(
      'src/components/calendar/CalendarEventNotesSection.tsx'
    );
    const appTsx = readRepoFile('src/App.tsx');

    // App passes calendarEvents to DaywellTasksModule
    assert.match(appTsx, /<DaywellTasksModule[\s\S]*calendarEvents=\{calendarEvents\}/);

    // Web Task->Notes handles missing Calendar event safely and asks confirmation via DaywellConfirmationDialog
    assert.match(tasksModule, /linkedCalendarEventId/);
    assert.match(tasksModule, /Linked event unavailable/);
    assert.match(tasksModule, /an unavailable Calendar event/);
    assert.match(tasksModule, /DaywellConfirmationDialog/);
    assert.match(tasksModule, /Replace existing link\?/);

    // Web Notes editor also guards Task & Calendar replacement + missing event warning
    assert.match(notesModule, /pendingCrossModuleLink/);
    assert.match(notesModule, /an unavailable Calendar event/);
    assert.match(notesModule, /DaywellConfirmationDialog/);

    // Web Calendar notes section displays unavailable task/event fallback labels
    assert.match(calendarNotesSection, /Linked task unavailable/);
    assert.match(calendarNotesSection, /Linked event unavailable/);
  });

  it('5. Existing Stage 7/8 Task -> Task linking without cross-module conflicts still works without extra confirmation', () => {
    const notes: TaskNoteRecord[] = [
      makeNote('n-free', 'Free Note'),
      makeNote('n-task-a', 'Existing Task Note', {
        linkedModule: 'tasks',
        linkedId: 'task-a',
        projectId: 'proj-ops',
      }),
    ];

    // Linking unlinked note to task succeeds cleanly
    const resFree = linkNoteToTask(notes, 'n-free', 'task-b');
    assert.strictEqual(resFree.ok, true);
    assert.strictEqual(resFree.updatedNote?.linkedModule, 'tasks');
    assert.strictEqual(resFree.updatedNote?.linkedId, 'task-b');

    // Reassigning Task A note -> Task B without allowReassign (existing Stage 7 behavior) still works
    const resTaskReassign = linkNoteToTask(resFree.notes, 'n-task-a', 'task-b');
    assert.strictEqual(resTaskReassign.ok, true);
    assert.strictEqual(resTaskReassign.previousLinkedModule, 'tasks');
    assert.strictEqual(resTaskReassign.previousLinkedId, 'task-a');
    assert.strictEqual(resTaskReassign.updatedNote?.linkedModule, 'tasks');
    assert.strictEqual(resTaskReassign.updatedNote?.linkedId, 'task-b');
    assert.strictEqual(resTaskReassign.updatedNote?.projectId, 'proj-ops');

    // Picker copy keeps existing Stage 7 '(linking reassigns)' for task links and skips confirmation dialog
    const tasksModule = readRepoFile('src/components/DaywellTasksModule.tsx');
    assert.match(tasksModule, /\(linking reassigns\)/);
  });

  it('6. Undo protection prevents silently overwriting newer relationships or restoring missing targets', () => {
    // Case A: Confirmed replacement Task -> Calendar -> later moved elsewhere -> old Calendar Undo must abort
    const afterReassignToCal = linkNoteToCalendarEvent(
      [
        makeNote('n1', 'Sprint Scope', {
          linkedModule: 'tasks',
          linkedId: 'task-1',
        }),
      ],
      'n1',
      'evt-1',
      undefined,
      { allowReassign: true }
    );
    assert.strictEqual(afterReassignToCal.ok, true);

    const movedToAnotherEvent = linkNoteToCalendarEvent(
      afterReassignToCal.notes,
      'n1',
      'evt-2',
      undefined,
      { allowReassign: true }
    );
    assert.strictEqual(movedToAnotherEvent.ok, true);

    const staleCalUndo = undoCalendarEventNoteLink({
      notes: movedToAnotherEvent.notes,
      noteId: 'n1',
      appliedEventId: 'evt-1',
      previousLinkedModule: 'tasks',
      previousLinkedId: 'task-1',
      previousTargetExists: true,
    });
    assert.strictEqual(staleCalUndo.ok, false);
    assert.strictEqual(staleCalUndo.notes[0].linkedModule, 'calendar');
    assert.strictEqual(staleCalUndo.notes[0].linkedId, 'evt-2');

    // Case B: Confirmed replacement Calendar -> Task -> previous event later deleted -> Task Undo must NOT restore dangling event link
    const afterReassignToTask = linkNoteToTask(
      [
        makeNote('n2', 'Design Signoff', {
          linkedModule: 'calendar',
          linkedId: 'evt-deleted',
        }),
      ],
      'n2',
      'task-9',
      undefined,
      { allowReassign: true }
    );
    assert.strictEqual(afterReassignToTask.ok, true);

    const danglingTaskUndo = undoTaskNoteLink({
      notes: afterReassignToTask.notes,
      noteId: 'n2',
      appliedTaskId: 'task-9',
      previousLinkedModule: 'calendar',
      previousLinkedId: 'evt-deleted',
      previousTargetExists: false,
    });
    assert.strictEqual(danglingTaskUndo.ok, false);
    assert.strictEqual(danglingTaskUndo.notes[0].linkedId, 'task-9');

    // Valid Task link undo restores previous Calendar event link when current state still matches appliedTaskId and event exists
    const validTaskUndo = undoTaskNoteLink({
      notes: afterReassignToTask.notes,
      noteId: 'n2',
      appliedTaskId: 'task-9',
      previousLinkedModule: 'calendar',
      previousLinkedId: 'evt-deleted',
      previousTargetExists: true,
    });
    assert.strictEqual(validTaskUndo.ok, true);
    assert.strictEqual(validTaskUndo.updatedNote?.linkedModule, 'calendar');
    assert.strictEqual(validTaskUndo.updatedNote?.linkedId, 'evt-deleted');

    // Case C: Unlink from Task -> User links note to Calendar -> Tapping Task Unlink Undo with allowReassign: false blocks overwrite!
    const unlinkedTask = unlinkNoteFromTask(
      [
        makeNote('n3', 'Shared Memo', {
          linkedModule: 'tasks',
          linkedId: 'task-a',
        }),
      ],
      'n3',
      'task-a'
    );
    assert.strictEqual(unlinkedTask.ok, true);
    const linkedToCalMeanwhile = linkNoteToCalendarEvent(
      unlinkedTask.notes,
      'n3',
      'evt-urgent'
    );
    assert.strictEqual(linkedToCalMeanwhile.ok, true);

    const blockedTaskUnlinkUndo = linkNoteToTask(
      linkedToCalMeanwhile.notes,
      'n3',
      'task-a',
      undefined,
      { allowReassign: false }
    );
    assert.strictEqual(blockedTaskUnlinkUndo.ok, false);
    assert.strictEqual(blockedTaskUnlinkUndo.notes[0].linkedModule, 'calendar');
    assert.strictEqual(blockedTaskUnlinkUndo.notes[0].linkedId, 'evt-urgent');

    // Case D: Unlink from Calendar -> User links note to Task -> Tapping Calendar Unlink Undo with allowReassign: false blocks overwrite!
    const unlinkedCal = unlinkNoteFromCalendarEvent(
      linkedToCalMeanwhile.notes,
      'n3',
      'evt-urgent'
    );
    assert.strictEqual(unlinkedCal.ok, true);
    const linkedToTaskMeanwhile = linkNoteToTask(unlinkedCal.notes, 'n3', 'task-b');
    assert.strictEqual(linkedToTaskMeanwhile.ok, true);

    const blockedCalUnlinkUndo = linkNoteToCalendarEvent(
      linkedToTaskMeanwhile.notes,
      'n3',
      'evt-urgent',
      undefined,
      { allowReassign: false }
    );
    assert.strictEqual(blockedCalUnlinkUndo.ok, false);
    assert.strictEqual(blockedCalUnlinkUndo.notes[0].linkedModule, 'tasks');
    assert.strictEqual(blockedCalUnlinkUndo.notes[0].linkedId, 'task-b');

    // Case E: Task deleted -> previously unlinked note linked to Calendar -> Task delete Undo restores only notes that are still unlinked
    const afterDeleteTask = unlinkNotesForDeletedTask(
      [
        makeNote('n-del', 'Meeting Followup', {
          linkedModule: 'tasks',
          linkedId: 'task-gone',
        }),
      ],
      'task-gone'
    );
    const relinkedToCal = linkNoteToCalendarEvent(
      afterDeleteTask.notes,
      'n-del',
      'evt-keep'
    );
    const undoDeleteLinkRestore = linkNoteToTask(
      relinkedToCal.notes,
      'n-del',
      'task-gone',
      undefined,
      { allowReassign: false }
    );
    assert.strictEqual(undoDeleteLinkRestore.ok, false);
    assert.strictEqual(undoDeleteLinkRestore.notes[0].linkedModule, 'calendar');
    assert.strictEqual(undoDeleteLinkRestore.notes[0].linkedId, 'evt-keep');

    // Web modules must use undoTaskNoteLink / undoCalendarEventNoteLink / allowReassign: false in Undo callbacks
    const tasksModule = readRepoFile('src/components/DaywellTasksModule.tsx');
    const calendarModule = readRepoFile('src/components/DaywellCalendarModule.tsx');
    const notesModule = readRepoFile('src/components/DaywellNotesModule.tsx');
    assert.match(tasksModule, /undoTaskNoteLink/);
    assert.match(tasksModule, /allowReassign:\s*false/);
    assert.match(calendarModule, /undoCalendarEventNoteLink/);
    assert.match(calendarModule, /allowReassign:\s*false/);
    assert.match(notesModule, /undoTaskNoteLink/);
    assert.match(notesModule, /undoCalendarEventNoteLink/);
    assert.match(notesModule, /allowReassign:\s*false/);
  });

  it('7. Flutter & Web share equivalent cross-module relationship protection, UI tokens, and zero silent overwrite contracts', () => {
    const notesController = readRepoFile(
      'flutter_app/lib/application/notes/notes_controller.dart'
    );
    const tasksView = readRepoFile('flutter_app/lib/ui/screens/tasks_view.dart');
    const calendarView = readRepoFile(
      'flutter_app/lib/ui/screens/calendar_view.dart'
    );
    const notesView = readRepoFile('flutter_app/lib/ui/screens/notes_view.dart');
    const mainDart = readRepoFile('flutter_app/lib/main.dart');

    // NotesController remains generic without 'tasks' string literal and blocks cross-module + Calendar overwrites when allowReassign is omitted/false
    assert.strictEqual(notesController.includes("'tasks'"), false);
    assert.match(notesController, /bool\?\s+allowReassign/);
    assert.match(notesController, /NoteEntity\.calendarLinkModule/);

    // Main wires calendarController into TasksView
    assert.match(mainDart, /calendarController:\s*_state\.calendarController/);

    // TasksView resolves Calendar event titles, warns on unavailable events, prompts DaywellConfirmationDialog, and guards Undo
    assert.match(tasksView, /CalendarController\?\s+calendarController/);
    assert.match(tasksView, /Currently linked to Calendar event/);
    assert.match(tasksView, /Linked event unavailable/);
    assert.match(tasksView, /an unavailable Calendar event/);
    assert.match(tasksView, /DaywellConfirmationDialog\.show/);
    assert.match(tasksView, /Replace existing link\?/);
    assert.match(tasksView, /allowReassign:\s*false/);
    assert.doesNotMatch(tasksView, /Color\(0x/);

    // CalendarView checks event availability & link conflicts on Undo and clarifies missing target text
    assert.match(calendarView, /an unavailable task/);
    assert.match(calendarView, /an unavailable Calendar event/);
    assert.match(calendarView, /Could not undo: note relationship changed\./);
    assert.doesNotMatch(calendarView, /Color\(0x/);

    // NotesView confirms before cross-module/Calendar replacement in _linkTask/_linkCalendarEvent and protects Undo
    assert.match(notesView, /_describeCurrentPrimaryLinkTarget/);
    assert.match(notesView, /Replace existing link\?/);
    assert.match(notesView, /Could not undo: note relationship changed\./);
    assert.doesNotMatch(notesView, /Color\(0x/);
  });
});
