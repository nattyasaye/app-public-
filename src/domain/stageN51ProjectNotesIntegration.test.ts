import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import {
  buildBoundedProjectNoteTitle,
  buildProjectTitlesById,
  clearNoteProject,
  countNotesForProject,
  createNoteForProject,
  getNoteContentPreview,
  getNotesForProject,
  getProjectForNote,
  isNoteLinkedToProject,
  setNoteProject,
  unlinkNotesForDeletedProject,
} from './projectNotes';
import { matchesNoteSearchQuery } from './noteHelpers';
import {
  filterAndSortWebNotes,
  moveWebNoteToTrash,
  saveWebNoteDraft,
} from './webNotesLifecycle';
import { TaskNoteRecord } from './taskNotes';
import { SharedProject } from './sharedFoundation';
import { WebProjectsRepository } from '../data/projectsRepository';
import { notesService } from '../services/notesService';
import { SharedStateBridge } from '../services/sharedStateBridge';
import { ProjectNotesSection } from '../components/projects/ProjectNotesSection';
import { ProjectDetailView } from '../components/projects/ProjectDetailView';
import { DaywellNotesModule } from '../components/DaywellNotesModule';

const REPO_ROOT = process.cwd();

function readRepoFile(relPath: string): string {
  return fs.readFileSync(path.join(REPO_ROOT, relPath), 'utf8');
}

function makeProject(
  id: string,
  title: string,
  overrides: Partial<SharedProject> = {}
): SharedProject {
  return {
    id,
    title,
    description: overrides.description ?? 'Project description',
    status: overrides.status ?? 'active',
    isArchived: overrides.isArchived ?? false,
    createdAt: overrides.createdAt ?? '2026-03-01T08:00:00.000Z',
    updatedAt: overrides.updatedAt ?? '2026-03-01T08:00:00.000Z',
    ...(overrides.goalId !== undefined ? { goalId: overrides.goalId } : {}),
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

describe('STAGE N5.1 — PROJECT NOTES INTEGRATION (WEB, BRIDGE & PARITY)', () => {
  it('1. Views notes belonging to a Project with active-first sorting, trash exclusion, previews, and SSR ProjectDetailView section', () => {
    const p1 = makeProject('proj-solar', 'Solar Retrofit');
    const p2 = makeProject('proj-garden', 'Balcony Garden');

    const notes: TaskNoteRecord[] = [
      makeNote('n-arch', 'Old Inverter Spec', {
        projectId: 'proj-solar',
        content: '## Archived\nReplaced by MPPT spec.',
        isArchived: true,
        updatedAt: '2026-03-05T10:00:00.000Z',
      }),
      makeNote('n-active', 'Panel Wiring Notes', {
        projectId: 'proj-solar',
        content: '## Wiring\nUse **6mm** copper cable with [[Battery Sizing]].',
        isPinned: false,
        updatedAt: '2026-03-04T10:00:00.000Z',
        tags: ['hardware', 'roof'],
      }),
      makeNote('n-pinned', 'Safety Checklist', {
        projectId: 'proj-solar',
        content: '- [ ] Disconnect main breaker',
        isPinned: true,
        updatedAt: '2026-03-03T10:00:00.000Z',
      }),
      makeNote('n-trash', 'Discarded Quote', {
        projectId: 'proj-solar',
        isTrashed: true,
      }),
      makeNote('n-other', 'Soil Mix', {
        projectId: 'proj-garden',
      }),
    ];

    const projectNotes = getNotesForProject(notes, p1.id);
    assert.deepStrictEqual(
      projectNotes.map((n) => n.id),
      ['n-pinned', 'n-active', 'n-arch']
    );
    assert.strictEqual(countNotesForProject(notes, p1.id), 3);
    assert.strictEqual(
      countNotesForProject(notes, p1.id, { includeArchived: false }),
      2
    );
    assert.strictEqual(isNoteLinkedToProject(notes[3], p1.id), false);
    assert.strictEqual(isNoteLinkedToProject(notes[4], p2.id), true);

    const preview = getNoteContentPreview(notes[1].content, 60);
    assert.ok(preview.includes('Wiring'));
    assert.ok(preview.includes('6mm copper cable'));

    const sectionHtml = renderToStaticMarkup(
      React.createElement(ProjectNotesSection, {
        project: p1,
        notes,
        onOpenNote: () => {},
        onCreateNote: () => {},
      })
    );
    assert.ok(sectionHtml.includes('NOTES (3)'));
    assert.ok(sectionHtml.includes('Safety Checklist'));
    assert.ok(sectionHtml.includes('Panel Wiring Notes'));
    assert.ok(sectionHtml.includes('Old Inverter Spec'));
    assert.ok(!sectionHtml.includes('Discarded Quote'));
    assert.ok(!sectionHtml.includes('Soil Mix'));

    const emptyHtml = renderToStaticMarkup(
      React.createElement(ProjectNotesSection, {
        project: p2,
        notes: [],
        onOpenNote: () => {},
        onCreateNote: () => {},
      })
    );
    assert.ok(emptyHtml.includes('No notes for this project yet'));
    assert.ok(emptyHtml.includes('New Note'));

    const detailSrc = readRepoFile('src/components/projects/ProjectDetailView.tsx');
    assert.ok(detailSrc.includes('<ProjectNotesSection'));
    assert.ok(detailSrc.includes('project={project}'));
    assert.ok(detailSrc.includes('notes={effectiveNotes}'));
    assert.ok(detailSrc.includes('onOpenNote={onNavigateToNote}'));
    assert.ok(detailSrc.includes('onCreateNote={handleCreateProjectNote}'));
  });

  it('2. Creates a new note from a Project with projectId auto-set, bounded title, and collision-safe ID', () => {
    const longProject = makeProject('proj-long', 'P'.repeat(280));
    const existing = [
      makeNote('note-1700000000000', 'Preexisting note'),
    ];
    const now = new Date(1700000000000);

    const createdRes = createNoteForProject({
      notes: existing,
      project: longProject,
      nowUtc: now,
    });
    assert.strictEqual(createdRes.ok, true);
    assert.ok(createdRes.note);
    assert.strictEqual(createdRes.note.projectId, 'proj-long');
    assert.strictEqual(createdRes.note.id, 'note-1700000000000-2');
    assert.strictEqual(createdRes.note.title.length, 250);
    assert.strictEqual(createdRes.notes.length, 2);

    const shortProject = makeProject('proj-short', 'Q3 Hiring');
    const secondRes = createNoteForProject({
      notes: createdRes.notes,
      project: shortProject,
      nowUtc: new Date('2026-03-10T12:00:00.000Z'),
    });
    assert.strictEqual(secondRes.ok, true);
    assert.strictEqual(secondRes.note?.title, 'Q3 Hiring — Note');
    assert.strictEqual(secondRes.note?.projectId, 'proj-short');
    assert.strictEqual(buildBoundedProjectNoteTitle('   '), 'Project Note');
  });

  it('3. Opening an existing Project note & DaywellNotesModule wiring flush pending edits and resolve project badges', () => {
    const p1 = makeProject('proj-alpha', 'Alpha Launch');
    const linked = makeNote('note-alpha', 'Launch Memo', {
      projectId: 'proj-alpha',
      linkedModule: 'tasks',
      linkedId: 'task-99',
    });
    const dangling = makeNote('note-dangling', 'Legacy Memo', {
      projectId: 'proj-deleted',
    });

    const notesHtml = renderToStaticMarkup(
      React.createElement(DaywellNotesModule, {
        notes: [linked, dangling],
        onUpdateNotes: () => {},
        projects: [p1],
        requestedNoteFocus: { noteId: linked.id, nonce: 1 },
        isActive: true,
        layoutMode: 'auto',
      })
    );
    assert.ok(notesHtml.includes('Launch Memo'));
    assert.ok(notesHtml.includes('Alpha Launch'));
    assert.ok(notesHtml.includes('Project unavailable'));

    const tasksModuleSrc = readRepoFile('src/components/DaywellTasksModule.tsx');
    const projectsWorkspaceSrc = readRepoFile(
      'src/components/projects/ProjectsWorkspaceView.tsx'
    );
    const projectDetailSrc = readRepoFile(
      'src/components/projects/ProjectDetailView.tsx'
    );
    const webAppSrc = readRepoFile('src/App.tsx');

    assert.ok(webAppSrc.includes('onNavigateToNote={(noteId) => {'));
    assert.ok(webAppSrc.includes("navigateTo('notes')"));
    assert.ok(webAppSrc.includes('projects={allProjects}'));
    assert.ok(tasksModuleSrc.includes('onUpdateNotes={applyNotesUpdate}'));
    assert.ok(tasksModuleSrc.includes('onNavigateToNote={onNavigateToNote}'));
    assert.ok(projectsWorkspaceSrc.includes('onNavigateToNote={onNavigateToNote}'));
    assert.ok(projectDetailSrc.includes('handleCreateProjectNote'));
    assert.ok(projectDetailSrc.includes('onNavigateToNote(createdNote.id)'));
  });

  it('4. Associates, reassigns, or removes a note Project association while enforcing single-project invariant and blocking trashed edits', () => {
    const notes: TaskNoteRecord[] = [
      makeNote('n-1', 'Design Plan', {
        tags: ['ui'],
        notebook: 'Work',
        goalId: 'goal-1',
        linkedModule: 'tasks',
        linkedId: 'task-7',
      }),
      makeNote('n-trash', 'Trashed Draft', { isTrashed: true }),
    ];

    const assigned = setNoteProject(notes, 'n-1', 'proj-1');
    assert.strictEqual(assigned.ok, true);
    assert.strictEqual(assigned.updatedNote?.projectId, 'proj-1');
    assert.strictEqual(assigned.previousProjectId, undefined);

    const moved = setNoteProject(assigned.notes, 'n-1', 'proj-2');
    assert.strictEqual(moved.ok, true);
    assert.strictEqual(moved.updatedNote?.projectId, 'proj-2');
    assert.strictEqual(moved.previousProjectId, 'proj-1');

    const cleared = clearNoteProject(moved.notes, 'n-1');
    assert.strictEqual(cleared.ok, true);
    assert.strictEqual(cleared.notes.length, 2);
    assert.strictEqual(cleared.updatedNote?.projectId, undefined);
    assert.strictEqual(cleared.updatedNote?.linkedModule, 'tasks');
    assert.strictEqual(cleared.updatedNote?.linkedId, 'task-7');
    assert.strictEqual(cleared.updatedNote?.goalId, 'goal-1');
    assert.deepStrictEqual(cleared.updatedNote?.tags, ['ui']);

    const trashBlocked = setNoteProject(cleared.notes, 'n-trash', 'proj-1');
    assert.strictEqual(trashBlocked.ok, false);

    // saveWebNoteDraft preserves existing projectId by default, updates when passed, and clears when clearProjectId=true
    const draftSaved = saveWebNoteDraft({
      notes: moved.notes,
      noteId: 'n-1',
      title: 'Design Plan v2',
      content: 'Updated content [[Other Note]]',
      notebook: 'Work',
      tags: ['ui'],
    });
    assert.strictEqual(draftSaved.status, 'updated');
    assert.strictEqual(
      draftSaved.notes.find((n) => n.id === 'n-1')?.projectId,
      'proj-2'
    );

    const draftCleared = saveWebNoteDraft({
      notes: draftSaved.notes,
      noteId: 'n-1',
      title: 'Design Plan v3',
      content: 'Updated content [[Other Note]]',
      notebook: 'Work',
      tags: ['ui'],
      clearProjectId: true,
    });
    assert.strictEqual(
      draftCleared.notes.find((n) => n.id === 'n-1')?.projectId,
      undefined
    );
  });

  it('5. Preserves notes intact when a Project is archived or permanently deleted', () => {
    withMockBrowserStorage((store) => {
      const repo = new WebProjectsRepository();
      repo.createProject({
        id: 'proj-del',
        title: 'Temporary Initiative',
        status: 'active',
        isArchived: false,
      });

      const initialNotes: TaskNoteRecord[] = [
        makeNote('n-keep-1', 'Project Research', {
          projectId: 'proj-del',
          content: 'Findings stay safe [[Index]]',
          tags: ['research'],
          notebook: 'Studies',
          linkedModule: 'tasks',
          linkedId: 'task-keep-1',
          goalId: 'goal-keep',
        }),
        makeNote('n-keep-2', 'Archived Project Memo', {
          projectId: 'proj-del',
          isArchived: true,
        }),
        makeNote('n-other-proj', 'Other Project Note', {
          projectId: 'proj-stay',
        }),
      ];
      notesService.saveNotes(initialNotes);

      // Archiving project keeps notes linked and visible
      repo.setProjectArchived('proj-del', true);
      const afterArchive = notesService.loadNotes();
      assert.strictEqual(countNotesForProject(afterArchive, 'proj-del'), 2);

      // Deleting project detaches projectId from daywell_notes without deleting notes or task links
      repo.deleteProject('proj-del');
      const afterDelete = notesService.loadNotes();
      assert.strictEqual(afterDelete.length, 3);

      const n1 = afterDelete.find((n) => n.id === 'n-keep-1')!;
      assert.strictEqual(n1.projectId, undefined);
      assert.strictEqual(n1.linkedModule, 'tasks');
      assert.strictEqual(n1.linkedId, 'task-keep-1');
      assert.strictEqual(n1.goalId, 'goal-keep');
      assert.deepStrictEqual(n1.tags, ['research']);
      assert.strictEqual(n1.notebook, 'Studies');

      const n2 = afterDelete.find((n) => n.id === 'n-keep-2')!;
      assert.strictEqual(n2.projectId, undefined);
      assert.strictEqual(n2.isArchived, true);

      const nOther = afterDelete.find((n) => n.id === 'n-other-proj')!;
      assert.strictEqual(nOther.projectId, 'proj-stay');

      assert.ok(store.has('daywell_notes'));

      // Direct domain helper verification
      const unlinked = unlinkNotesForDeletedProject(initialNotes, 'proj-del');
      assert.strictEqual(unlinked.unlinkedCount, 2);
      assert.deepStrictEqual(unlinked.unlinkedNoteIds, ['n-keep-1', 'n-keep-2']);
    });
  });

  it('6. Handles missing or deleted Project references safely without throwing', () => {
    const p1 = makeProject('proj-exists', 'Existing Project');
    const orphanNote = makeNote('n-orphan', 'Orphaned Project Note', {
      projectId: 'proj-missing-999',
    });
    const validNote = makeNote('n-valid', 'Valid Note', {
      projectId: 'proj-exists',
    });

    assert.strictEqual(getProjectForNote(orphanNote, [p1]), null);
    assert.strictEqual(getProjectForNote(validNote, [p1])?.id, 'proj-exists');
    assert.deepStrictEqual(getNotesForProject([orphanNote, validNote], 'proj-missing-999').length, 1);

    const html = renderToStaticMarkup(
      React.createElement(DaywellNotesModule, {
        notes: [orphanNote],
        onUpdateNotes: () => {},
        projects: [p1],
        requestedNoteFocus: { noteId: orphanNote.id, nonce: 1 },
        isActive: true,
        layoutMode: 'auto',
      })
    );
    assert.ok(html.includes('Project unavailable'));
  });

  it('7. Preserves existing Task links (linkedModule/linkedId), tags, folders, and internal links across Project edits & Trash restore', () => {
    const notes = [
      makeNote('n-combo', 'Combined Note', {
        content: 'See [[Architecture]] and complete task.',
        notebook: 'Engineering',
        tags: ['backend', 'v2'],
        linkedModule: 'tasks',
        linkedId: 'task-42',
        goalId: 'goal-7',
      }),
    ];

    const withProj = setNoteProject(notes, 'n-combo', 'proj-99');
    assert.strictEqual(withProj.ok, true);

    const trashed = moveWebNoteToTrash(withProj.notes, 'n-combo');
    const noteAfterTrash = trashed.notes[0];
    assert.strictEqual(noteAfterTrash.isTrashed, true);
    assert.strictEqual(noteAfterTrash.projectId, 'proj-99');
    assert.strictEqual(noteAfterTrash.linkedModule, 'tasks');
    assert.strictEqual(noteAfterTrash.linkedId, 'task-42');
    assert.strictEqual(noteAfterTrash.notebook, 'Engineering');
    assert.deepStrictEqual(noteAfterTrash.tags, ['backend', 'v2']);
  });

  it('8. Search discovers project notes by title, content, and associated project title; SharedStateBridge round-trips projectId and sanitizes dangling references', () => {
    const projects = [makeProject('proj-coffee', 'Coffee Export Portal')];
    const projectTitles = buildProjectTitlesById(projects);

    const activeProjectNote = makeNote('n-coffee', 'Port Customs Checklist', {
      projectId: 'proj-coffee',
      content: 'Submit bill of lading',
      tags: ['logistics'],
    });
    const archivedProjectNote = makeNote('n-coffee-old', 'Legacy Export Plan', {
      projectId: 'proj-coffee',
      isArchived: true,
    });
    const trashedProjectNote = makeNote('n-coffee-trash', 'Discarded Customs Draft', {
      projectId: 'proj-coffee',
      isTrashed: true,
    });

    assert.strictEqual(
      matchesNoteSearchQuery(activeProjectNote, 'Coffee Export Portal', {
        projectTitle: projectTitles.get('proj-coffee'),
      }),
      true
    );

    const activeHits = filterAndSortWebNotes(
      [activeProjectNote, archivedProjectNote, trashedProjectNote],
      { activeTab: 'all', searchQuery: 'coffee export', projectTitlesById: projectTitles }
    );
    assert.deepStrictEqual(
      activeHits.map((n) => n.id),
      ['n-coffee']
    );

    const archivedHits = filterAndSortWebNotes(
      [activeProjectNote, archivedProjectNote, trashedProjectNote],
      { activeTab: 'archived', searchQuery: 'coffee export', projectTitlesById: projectTitles }
    );
    assert.deepStrictEqual(
      archivedHits.map((n) => n.id),
      ['n-coffee-old']
    );

    withMockBrowserStorage((store) => {
      store.set(
        'daywell_projects',
        JSON.stringify([makeProject('proj-coffee', 'Coffee Export Portal')])
      );
      notesService.saveNotes([
        activeProjectNote,
        makeNote('n-dangling-backup', 'Dangling Note', {
          projectId: 'proj-missing-import',
        }),
      ]);

      const exportedRaw = SharedStateBridge.exportToAndroidJson();
      const exported = JSON.parse(exportedRaw);
      const exportedNote = exported.notes.find(
        (n: any) => n.id === 'n-coffee'
      );
      assert.strictEqual(exportedNote.projectId, 'proj-coffee');

      store.clear();
      const importRes = SharedStateBridge.importFromAndroidJson(exportedRaw);
      assert.strictEqual(importRes.success, true);

      const restoredNotes = notesService.loadNotes();
      const restoredValid = restoredNotes.find((n) => n.id === 'n-coffee');
      const restoredDangling = restoredNotes.find(
        (n) => n.id === 'n-dangling-backup'
      );
      assert.strictEqual(restoredValid?.projectId, 'proj-coffee');
      assert.strictEqual(restoredDangling?.projectId, undefined);
    });
  });

  it('9. Flutter Project–Notes implementation matches Web invariants and adheres strictly to Daywell UI token compliance', () => {
    const projectNotesHelper = readRepoFile(
      'flutter_app/lib/domain/notes/project_notes_helpers.dart'
    );
    const noteHelpers = readRepoFile(
      'flutter_app/lib/domain/notes/note_helpers.dart'
    );
    const projectsRepo = readRepoFile(
      'flutter_app/lib/data/repositories/projects_repository.dart'
    );
    const notesCtrl = readRepoFile(
      'flutter_app/lib/application/notes/notes_controller.dart'
    );
    const searchRepo = readRepoFile(
      'flutter_app/lib/data/repositories/search_repository.dart'
    );
    const projectNotesWidget = readRepoFile(
      'flutter_app/lib/ui/screens/projects/project_notes_widget.dart'
    );
    const projectDetailScreen = readRepoFile(
      'flutter_app/lib/ui/screens/projects/project_detail_screen.dart'
    );
    const notesView = readRepoFile('flutter_app/lib/ui/screens/notes_view.dart');
    const dartTest = readRepoFile(
      'flutter_app/test/stage_n51_project_notes_test.dart'
    );

    assert.ok(projectNotesHelper.includes('getNotesForProject'));
    assert.ok(projectNotesHelper.includes('findLinkedProject'));
    assert.ok(projectNotesHelper.includes('buildDefaultProjectNoteTitle'));
    assert.ok(noteHelpers.includes('String? projectTitle'));
    assert.ok(projectsRepo.includes('projectId: Value(null)'));
    assert.ok(notesCtrl.includes('Future<({bool saved, String? errorMessage})> setNoteProject('));
    assert.ok(searchRepo.includes('projectTitle: projectTitle'));
    assert.ok(projectNotesWidget.includes('No notes for this project yet'));
    assert.ok(projectDetailScreen.includes('ProjectNotesWidget'));
    assert.ok(notesView.includes('Project unavailable'));
    assert.ok(notesView.includes('Add Project'));
    assert.ok(dartTest.includes('Stage N5.1'));

    for (const src of [projectNotesWidget, projectDetailScreen, notesView]) {
      assert.strictEqual(/Color\(\s*0x/i.test(src), false);
      const materialColors = (
        src.match(/\bColors\.[a-zA-Z0-9_]+/g) || []
      ).filter((m) => m !== 'Colors.transparent');
      assert.strictEqual(materialColors.length, 0);
    }

    const webProjectNotes = readRepoFile(
      'src/components/projects/ProjectNotesSection.tsx'
    );
    const webNotesModule = readRepoFile('src/components/DaywellNotesModule.tsx');
    for (const src of [webProjectNotes, webNotesModule]) {
      assert.strictEqual(/#[0-9a-fA-F]{3,8}\b/.test(src), false);
    }
  });
});
