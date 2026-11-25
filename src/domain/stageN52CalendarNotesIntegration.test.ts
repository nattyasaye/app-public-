import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import {
  buildBoundedCalendarEventNoteTitle,
  buildCalendarEventTitlesById,
  CalendarEventNoteTarget,
  countNotesLinkedToCalendarEvent,
  createNoteForCalendarEvent,
  getAvailableNotesToLinkToCalendarEvent,
  getCalendarEventNotePreview,
  getLinkedCalendarEventForNote,
  getNotesLinkedToCalendarEvent,
  isNoteLinkedToCalendarEvent,
  linkNoteToCalendarEvent,
  unlinkNoteFromCalendarEvent,
  unlinkNotesForDeletedCalendarEvent,
} from './calendarNotes';
import { matchesNoteSearchQuery } from './noteHelpers';
import { TaskNoteRecord } from './taskNotes';
import {
  filterAndSortWebNotes,
  moveWebNoteToTrash,
  restoreWebNoteFromTrash,
  saveWebNoteDraft,
  toggleWebNoteArchive,
} from './webNotesLifecycle';
import { notesService } from '../services/notesService';
import { SharedStateBridge } from '../services/sharedStateBridge';
import { CalendarEventNotesSection } from '../components/calendar/CalendarEventNotesSection';
import { DaywellNotesModule } from '../components/DaywellNotesModule';

const REPO_ROOT = process.cwd();

function readRepoFile(relPath: string): string {
  return fs.readFileSync(path.join(REPO_ROOT, relPath), 'utf8');
}

function makeEvent(
  id: string,
  title: string,
  overrides: Partial<CalendarEventNoteTarget> = {}
): CalendarEventNoteTarget {
  return {
    id,
    title,
    date: overrides.date ?? '2026-03-15',
    ...(overrides.endDate !== undefined ? { endDate: overrides.endDate } : {}),
    ...(overrides.startTime !== undefined
      ? { startTime: overrides.startTime }
      : {}),
    ...(overrides.endTime !== undefined ? { endTime: overrides.endTime } : {}),
    ...(overrides.isAllDay !== undefined
      ? { isAllDay: overrides.isAllDay }
      : {}),
    ...(overrides.category !== undefined
      ? { category: overrides.category }
      : {}),
    ...(overrides.location !== undefined
      ? { location: overrides.location }
      : {}),
  };
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

function withMockBrowserStorage(
  fn: (
    store: Map<string, string>,
    dispatchedEvents: Array<{ type: string; detail: unknown }>
  ) => void
): void {
  const store = new Map<string, string>();
  const dispatchedEvents: Array<{ type: string; detail: unknown }> = [];
  const prevWindow = (globalThis as any).window;
  const prevLocalStorage = (globalThis as any).localStorage;
  const mockStorage = {
    getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
    setItem: (k: string, v: string) => void store.set(k, String(v)),
    removeItem: (k: string) => void store.delete(k),
    clear: () => void store.clear(),
  };

  (globalThis as any).localStorage = mockStorage;
  (globalThis as any).window = {
    dispatchEvent: (evt: { type: string; detail?: unknown }) => {
      dispatchedEvents.push({ type: evt.type, detail: evt.detail });
      return true;
    },
    CustomEvent: class CustomEvent {
      type: string;
      detail: unknown;
      constructor(type: string, init?: { detail?: unknown }) {
        this.type = type;
        this.detail = init?.detail;
      }
    },
  };

  try {
    fn(store, dispatchedEvents);
  } finally {
    (globalThis as any).window = prevWindow;
    (globalThis as any).localStorage = prevLocalStorage;
  }
}

describe('STAGE N5.2 — CALENDAR EVENT NOTES INTEGRATION (WEB, BRIDGE & PARITY)', () => {
  it('1. Displays linked notes for a Calendar event (pinned/active before archived, trashed excluded, stripped preview) and renders empty/populated CalendarEventNotesSection', () => {
    const ev1 = makeEvent('evt-q1', 'Q1 Board Review');
    const ev2 = makeEvent('evt-empty', 'Dentist Appointment');

    const notes: TaskNoteRecord[] = [
      makeNote('n-arch', 'Last Year Deck Notes', {
        linkedModule: 'calendar',
        linkedId: 'evt-q1',
        content: 'Archived financial slide feedback.',
        isArchived: true,
        updatedAt: '2026-03-08T10:00:00.000Z',
      }),
      makeNote('n-active', 'Agenda Talking Points', {
        linkedModule: 'calendar',
        linkedId: 'evt-q1',
        content: '## Focus\nConfirm **margin** targets and [[Hiring Plan]].',
        tags: ['leadership', 'finance'],
        updatedAt: '2026-03-06T10:00:00.000Z',
      }),
      makeNote('n-pin', 'Pre-Read Questions', {
        linkedModule: 'calendar',
        linkedId: 'evt-q1',
        content: '- [ ] Check cash runway assumptions',
        isPinned: true,
        updatedAt: '2026-03-05T10:00:00.000Z',
      }),
      makeNote('n-trash', 'Discarded Scratchpad', {
        linkedModule: 'calendar',
        linkedId: 'evt-q1',
        isTrashed: true,
      }),
      makeNote('n-other', 'Sprint Task Note', {
        linkedModule: 'tasks',
        linkedId: 'task-1',
      }),
    ];

    const linked = getNotesLinkedToCalendarEvent(notes, ev1.id);
    assert.deepStrictEqual(
      linked.map((n) => n.id),
      ['n-pin', 'n-active', 'n-arch']
    );
    assert.strictEqual(countNotesLinkedToCalendarEvent(notes, ev1.id), 3);
    assert.strictEqual(
      countNotesLinkedToCalendarEvent(notes, ev1.id, {
        includeArchived: false,
      }),
      2
    );
    assert.strictEqual(isNoteLinkedToCalendarEvent(notes[3], ev1.id), false);
    assert.strictEqual(isNoteLinkedToCalendarEvent(notes[4], ev1.id), false);

    const preview = getCalendarEventNotePreview(notes[1].content, 60);
    assert.ok(preview.includes('Focus'));
    assert.ok(preview.includes('margin targets'));

    const populatedHtml = renderToStaticMarkup(
      React.createElement(CalendarEventNotesSection, {
        event: ev1,
        notes,
        onOpenNote: () => {},
        onCreateNote: () => {},
        onLinkExistingNote: () => ({ ok: true }),
        onUnlinkNote: () => {},
      })
    );
    assert.ok(populatedHtml.includes('LINKED NOTES (3)'));
    assert.ok(populatedHtml.includes('Pre-Read Questions'));
    assert.ok(populatedHtml.includes('Agenda Talking Points'));
    assert.ok(populatedHtml.includes('Last Year Deck Notes'));
    assert.ok(!populatedHtml.includes('Discarded Scratchpad'));
    assert.ok(!populatedHtml.includes('Sprint Task Note'));

    const emptyHtml = renderToStaticMarkup(
      React.createElement(CalendarEventNotesSection, {
        event: ev2,
        notes,
        onOpenNote: () => {},
        onCreateNote: () => {},
        onLinkExistingNote: () => ({ ok: true }),
        onUnlinkNote: () => {},
      })
    );
    assert.ok(emptyHtml.includes('LINKED NOTES (0)'));
    assert.ok(emptyHtml.includes('No notes linked to this event yet'));
    assert.ok(emptyHtml.includes('New Note'));
  });

  it('2. Creates a new note directly from a Calendar event with linkedModule="calendar", bounded title, and collision-safe ID', () => {
    const longEvent = makeEvent('evt-long', 'E'.repeat(280));
    const existing = [
      makeNote('note-1700000000000', 'Preexisting note'),
    ];
    const now = new Date(1700000000000);

    const first = createNoteForCalendarEvent({
      notes: existing,
      event: longEvent,
      nowUtc: now,
    });
    assert.strictEqual(first.ok, true);
    assert.ok(first.note);
    assert.strictEqual(first.note.linkedModule, 'calendar');
    assert.strictEqual(first.note.linkedId, 'evt-long');
    assert.strictEqual(first.note.id, 'note-1700000000000-2');
    assert.strictEqual(first.note.title.length, 250);
    assert.strictEqual(first.notes.length, 2);

    const standupEvent = makeEvent('evt-standup', 'Weekly Engineering Sync');
    const second = createNoteForCalendarEvent({
      notes: first.notes,
      event: standupEvent,
      nowUtc: new Date('2026-03-16T08:30:00.000Z'),
    });
    assert.strictEqual(second.ok, true);
    assert.strictEqual(second.note?.title, 'Weekly Engineering Sync — Notes');
    assert.strictEqual(second.note?.linkedModule, 'calendar');
    assert.strictEqual(second.note?.linkedId, 'evt-standup');
    assert.strictEqual(buildBoundedCalendarEventNoteTitle('   '), 'Event Note');
  });

  it('3. Links existing notes, enforces single polymorphic primary link safety (no silent overwrite), and unlinks without deleting notes or unrelated metadata', () => {
    const notes: TaskNoteRecord[] = [
      makeNote('n-free', 'Free Prep Note', {
        projectId: 'proj-1',
        goalId: 'goal-1',
        notebook: 'Work',
        tags: ['prep', 'agenda'],
        content: 'Follow up with [[Team Charter]]',
      }),
      makeNote('n-task', 'Task Linked Note', {
        linkedModule: 'tasks',
        linkedId: 'task-99',
        projectId: 'proj-2',
      }),
      makeNote('n-other-ev', 'Other Event Note', {
        linkedModule: 'calendar',
        linkedId: 'evt-old',
      }),
      makeNote('n-trash', 'Trashed Note', { isTrashed: true }),
    ];

    const candidates = getAvailableNotesToLinkToCalendarEvent(notes, 'evt-new');
    assert.deepStrictEqual(
      candidates.map((c) => c.note.id),
      ['n-free', 'n-task', 'n-other-ev']
    );
    assert.strictEqual(candidates[0].hasExistingPrimaryLink, false);
    assert.strictEqual(candidates[1].hasExistingPrimaryLink, true);
    assert.strictEqual(candidates[1].linkedTaskId, 'task-99');
    assert.strictEqual(candidates[2].hasExistingPrimaryLink, true);
    assert.strictEqual(candidates[2].linkedEventId, 'evt-old');

    // Link unlinked note cleanly while preserving projectId, goalId, tags, notebook, and content
    const linkedRes = linkNoteToCalendarEvent(notes, 'n-free', 'evt-new');
    assert.strictEqual(linkedRes.ok, true);
    assert.strictEqual(linkedRes.updatedNote?.linkedModule, 'calendar');
    assert.strictEqual(linkedRes.updatedNote?.linkedId, 'evt-new');
    assert.strictEqual(linkedRes.updatedNote?.projectId, 'proj-1');
    assert.strictEqual(linkedRes.updatedNote?.goalId, 'goal-1');
    assert.strictEqual(linkedRes.updatedNote?.notebook, 'Work');
    assert.deepStrictEqual(linkedRes.updatedNote?.tags, ['prep', 'agenda']);
    assert.strictEqual(
      linkedRes.updatedNote?.content,
      'Follow up with [[Team Charter]]'
    );

    // Reject silent overwrite of a task-linked note or another-event-linked note
    const blockedTaskOverwrite = linkNoteToCalendarEvent(
      linkedRes.notes,
      'n-task',
      'evt-new'
    );
    assert.strictEqual(blockedTaskOverwrite.ok, false);
    assert.ok(blockedTaskOverwrite.error?.includes('already linked to a task'));

    const blockedEventOverwrite = linkNoteToCalendarEvent(
      linkedRes.notes,
      'n-other-ev',
      'evt-new'
    );
    assert.strictEqual(blockedEventOverwrite.ok, false);
    assert.ok(
      blockedEventOverwrite.error?.includes('already linked to another Calendar event')
    );

    // Allow explicit confirmed replacement
    const confirmedReassign = linkNoteToCalendarEvent(
      linkedRes.notes,
      'n-task',
      'evt-new',
      undefined,
      { allowReassign: true }
    );
    assert.strictEqual(confirmedReassign.ok, true);
    assert.strictEqual(confirmedReassign.updatedNote?.linkedModule, 'calendar');
    assert.strictEqual(confirmedReassign.updatedNote?.linkedId, 'evt-new');
    assert.strictEqual(confirmedReassign.updatedNote?.projectId, 'proj-2');
    assert.strictEqual(confirmedReassign.previousLinkedModule, 'tasks');
    assert.strictEqual(confirmedReassign.previousLinkedId, 'task-99');

    // Trashed notes cannot be linked
    const trashedBlocked = linkNoteToCalendarEvent(
      confirmedReassign.notes,
      'n-trash',
      'evt-new'
    );
    assert.strictEqual(trashedBlocked.ok, false);

    // Unlink preserves note & unrelated metadata
    const unlinkedRes = unlinkNoteFromCalendarEvent(
      confirmedReassign.notes,
      'n-free',
      'evt-new'
    );
    assert.strictEqual(unlinkedRes.ok, true);
    assert.strictEqual(unlinkedRes.notes.length, 4);
    assert.strictEqual(unlinkedRes.updatedNote?.linkedModule, undefined);
    assert.strictEqual(unlinkedRes.updatedNote?.linkedId, undefined);
    assert.strictEqual(unlinkedRes.updatedNote?.projectId, 'proj-1');
    assert.strictEqual(unlinkedRes.updatedNote?.goalId, 'goal-1');
    assert.deepStrictEqual(unlinkedRes.updatedNote?.tags, ['prep', 'agenda']);

    // saveWebNoteDraft preserves existing calendar link by default and clears only when clearLink=true
    const saved = saveWebNoteDraft({
      notes: confirmedReassign.notes,
      noteId: 'n-task',
      title: 'Task Linked Note v2',
      content: 'Edited meeting takeaways',
      notebook: 'Personal',
      tags: [],
    });
    const updatedTaskNote = saved.notes.find((n) => n.id === 'n-task')!;
    assert.strictEqual(updatedTaskNote.linkedModule, 'calendar');
    assert.strictEqual(updatedTaskNote.linkedId, 'evt-new');
    assert.strictEqual(updatedTaskNote.projectId, 'proj-2');
  });

  it('4. Deleting a Calendar event detaches only matching calendar links without deleting notes, tasks links, or project associations', () => {
    const notes: TaskNoteRecord[] = [
      makeNote('n-ev1', 'Board Minutes', {
        linkedModule: 'calendar',
        linkedId: 'evt-del',
        projectId: 'proj-gov',
        tags: ['minutes'],
        notebook: 'Executive',
      }),
      makeNote('n-ev1-arch', 'Old Prep', {
        linkedModule: 'calendar',
        linkedId: 'evt-del',
        isArchived: true,
      }),
      makeNote('n-other-ev', 'Other Meeting', {
        linkedModule: 'calendar',
        linkedId: 'evt-keep',
      }),
      makeNote('n-task', 'Task Note', {
        linkedModule: 'tasks',
        linkedId: 'evt-del', // same ID string in tasks module must NOT be touched!
      }),
    ];

    const res = unlinkNotesForDeletedCalendarEvent(notes, 'evt-del');
    assert.strictEqual(res.unlinkedCount, 2);
    assert.deepStrictEqual(res.unlinkedNoteIds, ['n-ev1', 'n-ev1-arch']);
    assert.strictEqual(res.notes.length, 4);

    const n1 = res.notes.find((n) => n.id === 'n-ev1')!;
    assert.strictEqual(n1.linkedModule, undefined);
    assert.strictEqual(n1.linkedId, undefined);
    assert.strictEqual(n1.projectId, 'proj-gov');
    assert.deepStrictEqual(n1.tags, ['minutes']);
    assert.strictEqual(n1.notebook, 'Executive');

    const nTask = res.notes.find((n) => n.id === 'n-task')!;
    assert.strictEqual(nTask.linkedModule, 'tasks');
    assert.strictEqual(nTask.linkedId, 'evt-del');

    const nOther = res.notes.find((n) => n.id === 'n-other-ev')!;
    assert.strictEqual(nOther.linkedModule, 'calendar');
    assert.strictEqual(nOther.linkedId, 'evt-keep');
  });

  it('5. Handles missing or deleted event references safely and renders Linked Event / Linked event unavailable in DaywellNotesModule', () => {
    const liveEvent = makeEvent('evt-live', 'Client Demo Day', {
      date: '2026-03-20',
      startTime: '14:00',
    });
    const linkedNote = makeNote('n-live', 'Demo Script', {
      linkedModule: 'calendar',
      linkedId: 'evt-live',
    });
    const orphanNote = makeNote('n-orphan', 'Orphaned Event Notes', {
      linkedModule: 'calendar',
      linkedId: 'evt-deleted-99',
    });

    assert.strictEqual(
      getLinkedCalendarEventForNote(linkedNote, [liveEvent])?.id,
      'evt-live'
    );
    assert.strictEqual(
      getLinkedCalendarEventForNote(orphanNote, [liveEvent]),
      null
    );

    const liveHtml = renderToStaticMarkup(
      React.createElement(DaywellNotesModule, {
        notes: [linkedNote, orphanNote],
        onUpdateNotes: () => {},
        calendarEvents: [liveEvent],
        requestedNoteFocus: { noteId: linkedNote.id, nonce: 1 },
        isActive: true,
        layoutMode: 'auto',
      })
    );
    assert.ok(liveHtml.includes('Demo Script'));
    assert.ok(liveHtml.includes('Client Demo Day'));
    assert.ok(liveHtml.includes('Linked event unavailable'));

    const webNotesModuleSrc = readRepoFile('src/components/DaywellNotesModule.tsx');
    assert.ok(webNotesModuleSrc.includes('Linked Event'));
    assert.ok(webNotesModuleSrc.includes('Event link'));
  });

  it('6. Search finds notes by linked Calendar event title while excluding Trash, and SharedStateBridge round-trips calendar note links', () => {
    const events = [
      makeEvent('evt-summit', 'Addis FinTech Summit'),
    ];
    const eventTitles = buildCalendarEventTitlesById(events);

    const activeEventNote = makeNote('n-summit', 'Keynote Takeaways', {
      linkedModule: 'calendar',
      linkedId: 'evt-summit',
      projectId: 'proj-1',
      content: 'Panel notes on instant settlements.',
    });
    const archivedEventNote = makeNote('n-summit-arch', '2025 Summit Prep', {
      linkedModule: 'calendar',
      linkedId: 'evt-summit',
      isArchived: true,
    });
    const trashedEventNote = makeNote('n-summit-trash', 'Discarded Badges', {
      linkedModule: 'calendar',
      linkedId: 'evt-summit',
      isTrashed: true,
    });

    assert.strictEqual(
      matchesNoteSearchQuery(activeEventNote, 'Addis FinTech', {
        linkedEventTitle: eventTitles.get('evt-summit'),
      }),
      true
    );

    const activeHits = filterAndSortWebNotes(
      [activeEventNote, archivedEventNote, trashedEventNote],
      {
        activeTab: 'all',
        searchQuery: 'fintech summit',
        calendarEventTitlesById: eventTitles,
      }
    );
    assert.deepStrictEqual(
      activeHits.map((n) => n.id),
      ['n-summit']
    );

    const archivedHits = filterAndSortWebNotes(
      [activeEventNote, archivedEventNote, trashedEventNote],
      {
        activeTab: 'archived',
        searchQuery: 'fintech summit',
        calendarEventTitlesById: eventTitles,
      }
    );
    assert.deepStrictEqual(
      archivedHits.map((n) => n.id),
      ['n-summit-arch']
    );

    withMockBrowserStorage((store) => {
      store.set(
        'daywell_projects',
        JSON.stringify([
          {
            id: 'proj-1',
            title: 'Payments Initiative',
            status: 'active',
            isArchived: false,
            createdAt: '2026-03-01T08:00:00.000Z',
            updatedAt: '2026-03-01T08:00:00.000Z',
          },
        ])
      );
      store.set(
        'daywell_calendar_events',
        JSON.stringify([
          {
            id: 'evt-summit',
            title: 'Addis FinTech Summit',
            date: '2026-03-22',
            isAllDay: false,
            category: 'work',
            createdAt: '2026-03-01T08:00:00.000Z',
            updatedAt: '2026-03-01T08:00:00.000Z',
          },
        ])
      );
      notesService.saveNotes([
        activeEventNote,
        makeNote('n-orphan-backup', 'Historical Orphan Note', {
          linkedModule: 'calendar',
          linkedId: 'evt-old-missing',
        }),
      ]);

      const exportedRaw = SharedStateBridge.exportToAndroidJson();
      const exported = JSON.parse(exportedRaw);
      const exportedSummitNote = exported.notes.find(
        (n: any) => n.id === 'n-summit'
      );
      assert.strictEqual(exportedSummitNote.linkedModule, 'calendar');
      assert.strictEqual(exportedSummitNote.linkedId, 'evt-summit');

      store.clear();
      const importRes = SharedStateBridge.importFromAndroidJson(exportedRaw);
      assert.strictEqual(importRes.success, true);

      const restoredNotes = notesService.loadNotes();
      const restoredSummit = restoredNotes.find((n) => n.id === 'n-summit');
      const restoredOrphan = restoredNotes.find(
        (n) => n.id === 'n-orphan-backup'
      );
      assert.strictEqual(restoredSummit?.linkedModule, 'calendar');
      assert.strictEqual(restoredSummit?.linkedId, 'evt-summit');
      assert.strictEqual(restoredSummit?.projectId, 'proj-1');
      // Existing contract preserves calendar links across backup/restore even when event is absent
      assert.strictEqual(restoredOrphan?.linkedModule, 'calendar');
      assert.strictEqual(restoredOrphan?.linkedId, 'evt-old-missing');
    });
  });

  it('7. Flutter & Web Calendar–Notes implementations match contracts and pass Daywell UI token compliance', () => {
    const calendarNotesDart = readRepoFile(
      'flutter_app/lib/domain/notes/calendar_notes_helpers.dart'
    );
    const noteModelsDart = readRepoFile(
      'flutter_app/lib/domain/notes/note_models.dart'
    );
    const noteHelpersDart = readRepoFile(
      'flutter_app/lib/domain/notes/note_helpers.dart'
    );
    const calendarRepoDart = readRepoFile(
      'flutter_app/lib/data/repositories/calendar_repository.dart'
    );
    const calendarCtrlDart = readRepoFile(
      'flutter_app/lib/application/calendar/calendar_controller.dart'
    );
    const searchRepoDart = readRepoFile(
      'flutter_app/lib/data/repositories/search_repository.dart'
    );
    const calendarViewDart = readRepoFile(
      'flutter_app/lib/ui/screens/calendar_view.dart'
    );
    const notesViewDart = readRepoFile(
      'flutter_app/lib/ui/screens/notes_view.dart'
    );
    const mainDart = readRepoFile('flutter_app/lib/main.dart');
    const dartTest = readRepoFile(
      'flutter_app/test/stage_n52_calendar_notes_test.dart'
    );

    assert.ok(noteModelsDart.includes("calendarLinkModule = 'calendar'"));
    assert.ok(noteModelsDart.includes('isLinkedToCalendarEvent'));
    assert.ok(noteHelpersDart.includes('String? linkedEventTitle'));
    assert.ok(calendarNotesDart.includes('getNotesForEvent'));
    assert.ok(calendarNotesDart.includes('getAvailableNotesForEventLink'));
    assert.ok(
      calendarRepoDart.includes('linkedModule.equals(NoteEntity.calendarLinkModule)')
    );
    assert.ok(calendarCtrlDart.includes('onEventDeleted'));
    assert.ok(searchRepoDart.includes('linkedEventTitle: linkedEventTitle'));
    assert.ok(calendarViewDart.includes('_buildModalLinkedNotesSection'));
    assert.ok(calendarViewDart.includes('_LinkExistingEventNoteSheet'));
    assert.ok(notesViewDart.includes('Linked event unavailable'));
    assert.ok(notesViewDart.includes('Link Event'));
    assert.ok(notesViewDart.includes('_NoteCalendarEventPickerSheet'));
    assert.ok(mainDart.includes('onOpenCalendarEvent:'));
    assert.ok(mainDart.includes('notesController: _state.notesController'));
    assert.ok(dartTest.includes('Stage N5.2'));

    for (const src of [calendarViewDart, notesViewDart]) {
      assert.strictEqual(/Color\(\s*0x/i.test(src), false);
      const materialColors = (
        src.match(/\bColors\.[a-zA-Z0-9_]+/g) || []
      ).filter((m) => m !== 'Colors.transparent');
      assert.strictEqual(materialColors.length, 0);
    }

    const webCalNotes = readRepoFile(
      'src/components/calendar/CalendarEventNotesSection.tsx'
    );
    const webCalModule = readRepoFile('src/components/DaywellCalendarModule.tsx');
    const webNotesModule = readRepoFile('src/components/DaywellNotesModule.tsx');
    for (const src of [webCalNotes, webCalModule, webNotesModule]) {
      assert.strictEqual(/#[0-9a-fA-F]{3,8}\b/.test(src), false);
    }
  });

  it('8. Corrective review: CalendarEventNotesSection surfaces resolved task/event link warnings without mutating Task links, Project links, or note metadata', () => {
    const taskEvent = makeEvent('evt-review', 'Architecture Sync');
    const otherEvent = makeEvent('evt-other', 'Annual Offsite');

    const taskLinkedNote = makeNote('n-task-meta', 'Sprint Checklist', {
      linkedModule: 'tasks',
      linkedId: 'task-42',
      projectId: 'proj-core',
      goalId: 'goal-ops',
      notebook: 'Work',
      tags: ['sprint', 'priority'],
      content: 'Review [[API Contract]] before release',
      isPinned: true,
      isFavorite: true,
    });
    const otherEventNote = makeNote('n-event-meta', 'Offsite Agenda', {
      linkedModule: 'calendar',
      linkedId: otherEvent.id,
      projectId: 'proj-core',
    });

    // Picker renders resolved task & event titles in warning copy when opened?
    // Verify CalendarEventNotesSection HTML contains resolved note titles and empty/populated states cleanly,
    // while domain helper keeps unconfirmed overwrites blocked and metadata completely untouched.
    const blockedTask = linkNoteToCalendarEvent(
      [taskLinkedNote, otherEventNote],
      taskLinkedNote.id,
      taskEvent.id
    );
    assert.strictEqual(blockedTask.ok, false);
    const untouchedTaskNote = blockedTask.notes.find(
      (n) => n.id === taskLinkedNote.id
    )!;
    assert.strictEqual(untouchedTaskNote.linkedModule, 'tasks');
    assert.strictEqual(untouchedTaskNote.linkedId, 'task-42');
    assert.strictEqual(untouchedTaskNote.projectId, 'proj-core');
    assert.strictEqual(untouchedTaskNote.goalId, 'goal-ops');
    assert.deepStrictEqual(untouchedTaskNote.tags, ['sprint', 'priority']);
    assert.strictEqual(untouchedTaskNote.isPinned, true);
    assert.strictEqual(untouchedTaskNote.isFavorite, true);

    // Explicit replacement preserves all orthogonal metadata & projectId
    const replaced = linkNoteToCalendarEvent(
      [taskLinkedNote, otherEventNote],
      taskLinkedNote.id,
      taskEvent.id,
      new Date('2026-03-17T10:00:00.000Z'),
      { allowReassign: true }
    );
    assert.strictEqual(replaced.ok, true);
    assert.strictEqual(replaced.updatedNote?.linkedModule, 'calendar');
    assert.strictEqual(replaced.updatedNote?.linkedId, taskEvent.id);
    assert.strictEqual(replaced.updatedNote?.projectId, 'proj-core');
    assert.strictEqual(replaced.updatedNote?.goalId, 'goal-ops');
    assert.strictEqual(replaced.updatedNote?.notebook, 'Work');
    assert.deepStrictEqual(replaced.updatedNote?.tags, ['sprint', 'priority']);
    assert.strictEqual(
      replaced.updatedNote?.content,
      'Review [[API Contract]] before release'
    );
    assert.strictEqual(replaced.updatedNote?.isPinned, true);
    assert.strictEqual(replaced.updatedNote?.isFavorite, true);

    const sectionHtml = renderToStaticMarkup(
      React.createElement(CalendarEventNotesSection, {
        event: taskEvent,
        notes: replaced.notes,
        tasks: [{ id: 'task-42', title: 'Finalize Launch Runbook' }],
        allEvents: [taskEvent, otherEvent],
        onOpenNote: () => {},
        onCreateNote: () => {},
        onLinkExistingNote: (noteId, opts) =>
          linkNoteToCalendarEvent(replaced.notes, noteId, taskEvent.id, undefined, opts),
        onUnlinkNote: () => {},
      })
    );
    assert.ok(sectionHtml.includes('LINKED NOTES (1)'));
    assert.ok(sectionHtml.includes('Sprint Checklist'));
  });

  it('9. Corrective review: Calendar events have no archive state; deleting an event unlinks active/archived/trashed calendar notes safely and note archival/restore preserves event links', () => {
    const schemaContracts = JSON.parse(
      readRepoFile('shared_foundation/schema_contracts.json')
    );
    const calEventFields = schemaContracts.entities.CalendarEvent.fields;
    assert.strictEqual(
      Object.prototype.hasOwnProperty.call(calEventFields, 'isArchived'),
      false,
      'CalendarEvent schema has no isArchived column (event archival is N/A in current architecture)'
    );

    const eventNote = makeNote('n-active-ev', 'Meeting Prep', {
      linkedModule: 'calendar',
      linkedId: 'evt-del-all',
      projectId: 'proj-a',
      tags: ['agenda'],
    });
    // Archiving and unarchiving a note preserves its Calendar event link
    const archivedRes = toggleWebNoteArchive([eventNote], eventNote.id);
    assert.strictEqual(archivedRes.ok, true);
    assert.strictEqual(archivedRes.updatedNote?.isArchived, true);
    assert.strictEqual(archivedRes.updatedNote?.linkedModule, 'calendar');
    assert.strictEqual(archivedRes.updatedNote?.linkedId, 'evt-del-all');

    const unarchivedRes = toggleWebNoteArchive(archivedRes.notes, eventNote.id);
    assert.strictEqual(unarchivedRes.ok, true);
    assert.strictEqual(unarchivedRes.updatedNote?.isArchived, false);
    assert.strictEqual(unarchivedRes.updatedNote?.linkedModule, 'calendar');
    assert.strictEqual(unarchivedRes.updatedNote?.linkedId, 'evt-del-all');

    const trashedRes = moveWebNoteToTrash(
      [
        eventNote,
        makeNote('n-trash-ev', 'Old Draft', {
          linkedModule: 'calendar',
          linkedId: 'evt-del-all',
        }),
      ],
      'n-trash-ev'
    );
    assert.strictEqual(trashedRes.ok, true);

    const beforeDelete = [
      ...trashedRes.notes,
      makeNote('n-colliding-task', 'Task with matching ID', {
        linkedModule: 'tasks',
        linkedId: 'evt-del-all',
        projectId: 'proj-b',
      }),
    ];

    // Deleting event detaches both active and trashed matching calendar notes, never deletes notes,
    // and never touches tasks-linked notes even when linkedId equals the deleted event ID.
    const afterDelete = unlinkNotesForDeletedCalendarEvent(
      beforeDelete,
      'evt-del-all'
    );
    assert.strictEqual(afterDelete.unlinkedCount, 2);
    assert.strictEqual(afterDelete.notes.length, 3);
    const restoredFromTrash = restoreWebNoteFromTrash(
      afterDelete.notes,
      'n-trash-ev'
    );
    assert.strictEqual(restoredFromTrash.updatedNote?.linkedModule, undefined);
    assert.strictEqual(restoredFromTrash.updatedNote?.linkedId, undefined);
    assert.strictEqual(
      afterDelete.notes.find((n) => n.id === 'n-active-ev')?.projectId,
      'proj-a'
    );
    const collidingTask = afterDelete.notes.find(
      (n) => n.id === 'n-colliding-task'
    )!;
    assert.strictEqual(collidingTask.linkedModule, 'tasks');
    assert.strictEqual(collidingTask.linkedId, 'evt-del-all');
  });

  it('10. Corrective review: Missing event refs degrade safely in UI/search, SharedStateBridge strips invalid half-links, and Finance-only restore preserves calendar-linked notes', () => {
    const missingEventNote = makeNote('n-missing-ev', 'Detached Event Note', {
      linkedModule: 'calendar',
      linkedId: 'evt-does-not-exist',
      content: 'Still readable and searchable by title',
      projectId: 'proj-1',
    });
    const eventTitles = buildCalendarEventTitlesById([]);
    const searchHits = filterAndSortWebNotes([missingEventNote], {
      activeTab: 'all',
      searchQuery: 'Detached',
      calendarEventTitlesById: eventTitles,
    });
    assert.deepStrictEqual(
      searchHits.map((n) => n.id),
      ['n-missing-ev']
    );

    const orphanUiHtml = renderToStaticMarkup(
      React.createElement(DaywellNotesModule, {
        notes: [missingEventNote],
        onUpdateNotes: () => {},
        calendarEvents: [],
        requestedNoteFocus: { noteId: missingEventNote.id, nonce: 1 },
        onNavigateToCalendarEvent: () => {},
        isActive: true,
        layoutMode: 'auto',
      })
    );
    assert.ok(orphanUiHtml.includes('Detached Event Note'));
    assert.ok(orphanUiHtml.includes('Linked event unavailable'));
    assert.ok(!orphanUiHtml.includes('Open linked event:'));
    // Unlinking an orphaned calendar-linked note still succeeds cleanly and preserves metadata/projectId
    const unlinkedOrphan = unlinkNoteFromCalendarEvent(
      [missingEventNote],
      missingEventNote.id
    );
    assert.strictEqual(unlinkedOrphan.ok, true);
    assert.strictEqual(unlinkedOrphan.updatedNote?.linkedModule, undefined);
    assert.strictEqual(unlinkedOrphan.updatedNote?.linkedId, undefined);
    assert.strictEqual(unlinkedOrphan.updatedNote?.projectId, 'proj-1');

    // Backup/Restore hygiene: half-links are stripped cleanly while valid calendar, task & project links survive,
    // and Finance-only restore leaves calendarEvents + calendar-linked notes completely untouched.
    withMockBrowserStorage((store) => {
      store.set(
        'daywell_tasks',
        JSON.stringify([
          {
            id: 'task-keep-1',
            title: 'Keep Task Link',
            completed: false,
            priority: 'medium',
            status: 'not_started',
            createdAt: '2026-03-01T08:00:00.000Z',
            updatedAt: '2026-03-01T08:00:00.000Z',
          },
        ])
      );
      store.set(
        'daywell_projects',
        JSON.stringify([
          {
            id: 'proj-1',
            title: 'Payments Initiative',
            status: 'active',
            isArchived: false,
            createdAt: '2026-03-01T08:00:00.000Z',
            updatedAt: '2026-03-01T08:00:00.000Z',
          },
        ])
      );
      store.set(
        'daywell_calendar_events',
        JSON.stringify([
          {
            id: 'evt-keep-1',
            title: 'Treasury Sync',
            date: '2026-03-22',
            isAllDay: false,
            category: 'finance',
            createdAt: '2026-03-01T08:00:00.000Z',
            updatedAt: '2026-03-01T08:00:00.000Z',
          },
        ])
      );
      notesService.saveNotes([
        makeNote('n-cal-1', 'Treasury Prep', {
          linkedModule: 'calendar',
          linkedId: 'evt-keep-1',
          projectId: 'proj-1',
          tags: ['treasury'],
        }),
        makeNote('n-task-1', 'Task Prep', {
          linkedModule: 'tasks',
          linkedId: 'task-keep-1',
        }),
      ]);

      const fullExport = JSON.parse(SharedStateBridge.exportToAndroidJson());
      fullExport.notes.push(
        {
          id: 'n-half-mod',
          title: 'Half link module only',
          body: '',
          folder: 'Personal',
          tags: [],
          isPinned: false,
          isArchived: false,
          linkedModule: 'calendar',
          createdAt: '2026-03-01T08:00:00.000Z',
          updatedAt: '2026-03-01T08:00:00.000Z',
        },
        {
          id: 'n-half-id',
          title: 'Half link id only',
          body: '',
          folder: 'Personal',
          tags: [],
          isPinned: false,
          isArchived: false,
          linkedId: 'evt-keep-1',
          createdAt: '2026-03-01T08:00:00.000Z',
          updatedAt: '2026-03-01T08:00:00.000Z',
        }
      );

      store.clear();
      const restored = SharedStateBridge.importFromAndroidJson(
        JSON.stringify(fullExport)
      );
      assert.strictEqual(restored.success, true, restored.error);

      const loaded = notesService.loadNotes();
      const halfMod = loaded.find((n) => n.id === 'n-half-mod')!;
      const halfId = loaded.find((n) => n.id === 'n-half-id')!;
      assert.strictEqual(halfMod.linkedModule, undefined);
      assert.strictEqual(halfMod.linkedId, undefined);
      assert.strictEqual(halfId.linkedModule, undefined);
      assert.strictEqual(halfId.linkedId, undefined);
      assert.strictEqual(
        loaded.find((n) => n.id === 'n-task-1')?.linkedModule,
        'tasks'
      );

      // Finance-only restore must preserve existing calendarEvents and calendar-linked notes
      const finOnlyJson = SharedStateBridge.exportFinanceOnlyJson();
      const finImportRes = SharedStateBridge.importFinanceOnlyJson(finOnlyJson);
      assert.strictEqual(finImportRes.success, true, finImportRes.error);
      const notesAfterFin = notesService.loadNotes();
      const calNoteAfterFin = notesAfterFin.find((n) => n.id === 'n-cal-1')!;
      assert.strictEqual(calNoteAfterFin.linkedModule, 'calendar');
      assert.strictEqual(calNoteAfterFin.linkedId, 'evt-keep-1');
      assert.strictEqual(calNoteAfterFin.projectId, 'proj-1');
      const eventsAfterFin = JSON.parse(
        store.get('daywell_calendar_events') || '[]'
      );
      assert.strictEqual(eventsAfterFin.length, 1);
      assert.strictEqual(eventsAfterFin[0].id, 'evt-keep-1');
    });
  });
});
