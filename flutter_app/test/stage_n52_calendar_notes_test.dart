import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/calendar/calendar_controller.dart';
import 'package:personal_management_app/application/notes/notes_controller.dart';
import 'package:personal_management_app/core/date/shared_date.dart';
import 'package:personal_management_app/core/theme/daywell_theme.dart';
import 'package:personal_management_app/data/database/app_database.dart';
import 'package:personal_management_app/data/database/database_persistence_coordinator.dart';
import 'package:personal_management_app/data/repositories/calendar_repository.dart';
import 'package:personal_management_app/data/repositories/notes_repository.dart';
import 'package:personal_management_app/data/repositories/search_repository.dart';
import 'package:personal_management_app/domain/calendar/calendar_models.dart';
import 'package:personal_management_app/domain/notes/calendar_notes_helpers.dart';
import 'package:personal_management_app/domain/notes/note_models.dart';
import 'package:personal_management_app/ui/screens/calendar_view.dart';
import 'package:personal_management_app/ui/screens/notes_view.dart';

import 'support/sqlite_test_helper.dart';

void main() {
  setUpAll(configureSqliteForHostTests);

  group('Stage N5.2 — Calendar Event Notes Integration', () {
    test(
      '1. CalendarNotesHelper filters, sorts (pinned/active before archived, trashed excluded), detects primary link conflicts, and builds previews',
      () {
        final ev1 = CalendarEventEntity(
          id: 'evt-1',
          title: 'Board Sync',
          dateIso: '2026-03-15',
          startTime: '09:00',
        );
        final longEv = CalendarEventEntity(
          id: 'evt-long',
          title: 'E' * 280,
          dateIso: '2026-03-16',
        );
        final t1 = DateTime.utc(2026, 3, 1, 9);
        final t2 = DateTime.utc(2026, 3, 2, 9);
        final t3 = DateTime.utc(2026, 3, 3, 9);

        final notes = <NoteEntity>[
          NoteEntity(
            id: 'n-arch',
            title: 'Archived Deck',
            content: 'Last quarter summary',
            linkedModule: NoteEntity.calendarLinkModule,
            linkedId: 'evt-1',
            isArchived: true,
            createdAt: t1,
            updatedAt: t3,
          ),
          NoteEntity(
            id: 'n-active',
            title: 'Agenda',
            content: '## Topics\nReview **runway** and [[Roadmap]].',
            linkedModule: NoteEntity.calendarLinkModule,
            linkedId: 'evt-1',
            createdAt: t1,
            updatedAt: t2,
          ),
          NoteEntity(
            id: 'n-pin',
            title: 'Key Questions',
            content: '- [ ] Confirm budget cap',
            linkedModule: NoteEntity.calendarLinkModule,
            linkedId: 'evt-1',
            isPinned: true,
            createdAt: t1,
            updatedAt: t1,
          ),
          NoteEntity(
            id: 'n-trash',
            title: 'Discarded Draft',
            linkedModule: NoteEntity.calendarLinkModule,
            linkedId: 'evt-1',
            isTrashed: true,
          ),
          NoteEntity(
            id: 'n-task',
            title: 'Task Note',
            linkedModule: NoteEntity.taskLinkModule,
            linkedId: 'task-42',
          ),
          NoteEntity(
            id: 'n-free',
            title: 'Standalone Note',
          ),
        ];

        final linked = CalendarNotesHelper.getNotesForEvent(notes, 'evt-1');
        expect(linked.map((n) => n.id).toList(), ['n-pin', 'n-active', 'n-arch']);
        expect(CalendarNotesHelper.countNotesForEvent(notes, 'evt-1'), 3);
        expect(
          CalendarNotesHelper.countNotesForEvent(
            notes,
            'evt-1',
            includeArchived: false,
          ),
          2,
        );
        expect(
          CalendarNotesHelper.isNoteLinkedToEvent(notes[3], 'evt-1'),
          isFalse,
        );

        final candidates =
            CalendarNotesHelper.getAvailableNotesForEventLink(notes, 'evt-1');
        expect(candidates.map((c) => c.note.id).toList(), ['n-free', 'n-task']);
        expect(candidates[0].hasExistingPrimaryLink, isFalse);
        expect(candidates[1].hasExistingPrimaryLink, isTrue);
        expect(candidates[1].isLinkedToOtherModule, isTrue);
        expect(candidates[1].linkedTaskId, 'task-42');

        expect(CalendarNotesHelper.findLinkedEvent(notes[1], [ev1])?.id, 'evt-1');
        expect(CalendarNotesHelper.findLinkedEvent(notes[4], [ev1]), isNull);
        expect(
          CalendarNotesHelper.buildDefaultEventNoteTitle(ev1),
          'Board Sync — Notes',
        );
        expect(
          CalendarNotesHelper.buildDefaultEventNoteTitle(longEv).length,
          NoteEntity.maxTitleLength,
        );
        expect(
          CalendarNotesHelper.buildContentPreview(notes[1].content),
          contains('Review runway'),
        );
      },
    );

    test(
      '2. DriftCalendarRepository, CalendarController, NotesController & DriftSearchRepository link/unlink notes, preserve notes & projectId on event delete, and search by event title',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final calendarRepo = DriftCalendarRepository(db);
        final notesRepo = DriftNotesRepository(db);
        final searchRepo = DriftSearchRepository(db);
        late final NotesController notesCtrl;
        final calendarCtrl = CalendarController(
          repository: calendarRepo,
          onEventDeleted: (eventId) => notesCtrl.clearLinksForTarget(
            module: NoteEntity.calendarLinkModule,
            targetId: eventId,
          ),
        );
        notesCtrl = NotesController(repository: notesRepo);
        addTearDown(() {
          calendarCtrl.dispose();
          notesCtrl.dispose();
        });

        final event = CalendarEventEntity(
          id: 'evt-fintech',
          title: 'Addis FinTech Summit',
          dateIso: '2026-03-20',
          startTime: '10:00',
        );
        await calendarCtrl.addEvent(event);

        final created = await notesCtrl.createNote(
          id: 'note-summit',
          title: CalendarNotesHelper.buildDefaultEventNoteTitle(event),
          content: 'Keynote payment rails takeaways [[Settlement Notes]]',
          category: 'work_projects',
          projectId: 'proj-payments',
          tags: const ['fintech'],
          linkedModule: NoteEntity.calendarLinkModule,
          linkedId: event.id,
        );
        expect(created.linkedModule, NoteEntity.calendarLinkModule);
        expect(created.linkedId, event.id);
        expect(created.projectId, 'proj-payments');

        // Search finds note by linked Calendar event title
        final hits = await searchRepo.searchAll(
          'FinTech Summit',
          entityFilter: 'note',
        );
        expect(hits.map((r) => r.id), contains('note-summit'));
        expect(hits.first.snippet, contains('Event: Addis FinTech Summit'));

        // Deleting Calendar event unlinks the note without deleting it or stripping projectId/tags/content
        await calendarCtrl.deleteEvent(event.id);
        final surviving = await notesRepo.getNoteById('note-summit');
        expect(surviving, isNotNull);
        expect(surviving?.linkedModule, isNull);
        expect(surviving?.linkedId, isNull);
        expect(surviving?.projectId, 'proj-payments');
        expect(surviving?.tags, const ['fintech']);
        expect(surviving?.category, 'work_projects');
        expect(
          notesCtrl.state.findById('note-summit')?.linkedModule,
          isNull,
        );
      },
    );

    test(
      '3. DatabasePersistenceCoordinator round-trips Calendar event links and preserves metadata',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final coordinator = DatabasePersistenceCoordinator(db);
        final payload = jsonEncode({
          'schemaVersion': 5,
          'snapshotFormatVersion': 2,
          'databaseSchemaVersion': 12,
          'exportedAt': '2026-03-10T10:00:00.000Z',
          'calendarEvents': [
            {
              'id': 'evt-backup',
              'title': 'Annual Planning Retreat',
              'dateIso': '2026-04-02',
              'isAllDay': true,
              'category': 'work',
              'createdAt': '2026-03-01T08:00:00.000Z',
              'updatedAt': '2026-03-01T08:00:00.000Z',
            },
          ],
          'notes': [
            {
              'id': 'note-cal-backup',
              'title': 'Retreat Pre-read',
              'body': 'Strategic priorities',
              'folder': 'general',
              'tags': ['strategy'],
              'linkedModule': 'calendar',
              'linkedId': 'evt-backup',
              'createdAt': '2026-03-01T08:00:00.000Z',
              'updatedAt': '2026-03-01T08:00:00.000Z',
            },
          ],
        });

        final restoreRes = await coordinator.importCanonicalJson(payload);
        expect(restoreRes.isSuccess, isTrue);

        final notesRepo = DriftNotesRepository(db);
        final restored = await notesRepo.getNoteById('note-cal-backup');
        expect(restored?.linkedModule, NoteEntity.calendarLinkModule);
        expect(restored?.linkedId, 'evt-backup');
        expect(restored?.tags, const ['strategy']);
      },
    );

    testWidgets(
      '4. CalendarView edit modal shows linked notes & creates new event note; NotesView shows Linked Event bar and missing event fallback',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        await db.ensureInitialized();
        addTearDown(db.close);

        final calendarRepo = DriftCalendarRepository(db);
        final notesRepo = DriftNotesRepository(db);
        final calendarCtrl = CalendarController(repository: calendarRepo);
        final notesCtrl = NotesController(repository: notesRepo);
        addTearDown(() {
          calendarCtrl.dispose();
          notesCtrl.dispose();
        });

        final targetDate = CalendarDate(year: 2026, month: 3, day: 18);
        calendarCtrl.setSelectedCalendarDate(targetDate);
        final ev = CalendarEventEntity(
          id: 'evt-ui-1',
          title: 'Product Design Critique',
          dateIso: targetDate.toIsoString(),
          startTime: '11:00',
        );
        await calendarCtrl.addEvent(ev);
        await calendarCtrl.loadAll();
        await notesCtrl.loadNotes();

        final openedNoteIds = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light(),
            home: CalendarView(
              calendarController: calendarCtrl,
              notesController: notesCtrl,
              onOpenNote: openedNoteIds.add,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap event card on selected day to open Edit Event modal
        await tester.tap(find.text('Product Design Critique').first);
        await tester.pumpAndSettle();

        expect(find.text('LINKED NOTES (0)'), findsOneWidget);
        expect(find.text('No notes linked to this event yet'), findsOneWidget);

        // Tap New Note from Edit Event modal
        await tester.tap(find.text('New Note').first);
        await tester.pumpAndSettle();

        expect(notesCtrl.state.notes.length, 1);
        final created = notesCtrl.state.notes.first;
        expect(created.linkedModule, NoteEntity.calendarLinkModule);
        expect(created.linkedId, ev.id);
        expect(created.title, 'Product Design Critique — Notes');
        expect(openedNoteIds, [created.id]);

        // Also add an orphaned calendar-linked note and inspect NotesView
        await notesCtrl.createNote(
          id: 'note-orphan-cal',
          title: 'Legacy Calendar Memo',
          content: 'Still intact',
          linkedModule: NoteEntity.calendarLinkModule,
          linkedId: 'evt-deleted-999',
        );

        CalendarEventEntity? openedEvent;
        await tester.pumpWidget(
          MaterialApp(
            theme: DaywellTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(size: Size(1000, 800)),
              child: NotesView(
                controller: notesCtrl,
                calendarController: calendarCtrl,
                requestedNoteFocus: (noteId: created.id, nonce: 1),
                onOpenCalendarEvent: (event) => openedEvent = event,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Linked Event: Product Design Critique'),
          findsOneWidget,
        );
        expect(find.text('Linked event unavailable'), findsWidgets);
        // Single primary link guard: Link Task & Link Event hidden when already linked
        expect(find.text('Link Task'), findsNothing);
        expect(find.text('Link Event'), findsNothing);

        await tester.tap(find.text('Open').first);
        await tester.pumpAndSettle();
        expect(openedEvent?.id, ev.id);
      },
    );
  });
}
