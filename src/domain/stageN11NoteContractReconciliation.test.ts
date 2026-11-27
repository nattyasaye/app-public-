import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  CANONICAL_NOTE_LINKED_MODULES,
  SHARED_BUSINESS_RULES,
  SharedNote,
  SharedNoteLinkedModule,
} from './sharedFoundation';
import {
  MAX_NOTE_TITLE_LENGTH,
  normalizeTaskNoteRecord,
} from './taskNotes';
import { SharedBridgeNote, SharedStateBridge } from '../services/sharedStateBridge';

const REPO_ROOT = process.cwd();

function read(relPath: string): string {
  return fs.readFileSync(path.join(REPO_ROOT, relPath), 'utf8');
}

function withMockBrowserStorage(fn: (store: Map<string, string>) => void): void {
  const store = new Map<string, string>();
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
    dispatchEvent: () => true,
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
    fn(store);
  } finally {
    (globalThis as any).window = prevWindow;
    (globalThis as any).localStorage = prevLocalStorage;
  }
}

describe('Stage N1.1 — Canonical Note Contract Reconciliation & Compatibility', () => {
  it('1. schema_contracts.json reconciles Note fields, bounds, relationships, and fieldMappings without schema version bump', () => {
    const contracts = JSON.parse(read('shared_foundation/schema_contracts.json'));
    assert.strictEqual(contracts.schemaVersion, 13);

    const note = contracts.entities.Note;
    assert.ok(note, 'entities.Note must exist in schema_contracts.json');

    const fields = note.fields;
    assert.deepStrictEqual(Object.keys(fields), [
      'id',
      'title',
      'body',
      'folder',
      'tags',
      'isPinned',
      'isFavorite',
      'isArchived',
      'isTrashed',
      'projectId',
      'goalId',
      'linkedModule',
      'linkedId',
      'createdAt',
      'updatedAt',
    ]);

    assert.deepStrictEqual(fields.title, {
      type: 'string',
      required: true,
      maxLength: 250,
    });
    assert.deepStrictEqual(fields.body, { type: 'string', required: true });
    assert.deepStrictEqual(fields.folder, {
      type: 'string',
      required: false,
      default: 'General',
    });
    assert.deepStrictEqual(fields.projectId, { type: 'string', required: false });
    assert.deepStrictEqual(fields.goalId, { type: 'string', required: false });
    assert.deepStrictEqual(fields.linkedModule, {
      type: 'string',
      enum: ['tasks', 'finance', 'calendar'],
      required: false,
    });
    assert.deepStrictEqual(fields.linkedId, { type: 'string', required: false });

    assert.strictEqual(note.fieldMappings?.body?.canonicalField, 'body');
    assert.deepStrictEqual(note.fieldMappings?.body?.runtimeAliases, ['content']);
    assert.strictEqual(note.fieldMappings?.folder?.canonicalField, 'folder');
    assert.deepStrictEqual(note.fieldMappings?.folder?.runtimeAliases, [
      'category',
      'notebook',
    ]);
    assert.strictEqual(note.fieldMappings?.linkedPair?.legacyAliases?.taskId?.linkedModule, 'tasks');
    assert.strictEqual(note.fieldMappings?.timestamps?.legacyAliases?.createdAtUtc, 'createdAt');
  });

  it('2. business_rules.json, generated TS SharedNote/SHARED_BUSINESS_RULES.notes, and pure-Dart SharedNoteContracts stay synchronized', () => {
    const rules = JSON.parse(read('shared_foundation/business_rules.json'));
    assert.ok(rules.notes, 'business_rules.json must include notes section');
    assert.deepStrictEqual(SHARED_BUSINESS_RULES.notes, rules.notes);
    assert.strictEqual(MAX_NOTE_TITLE_LENGTH, rules.notes.maxTitleLength);
    assert.deepStrictEqual([...CANONICAL_NOTE_LINKED_MODULES], rules.notes.linkedModules);

    const linkedModCheck: SharedNoteLinkedModule = 'tasks';
    const canonicalNote: SharedNote = {
      id: 'note-contract-1',
      title: 'Reconciled Contract Note',
      body: 'Body content',
      folder: 'General',
      tags: ['alpha'],
      isPinned: true,
      isFavorite: false,
      isArchived: false,
      isTrashed: false,
      projectId: 'proj-1',
      goalId: 'goal-1',
      linkedModule: linkedModCheck,
      linkedId: 'task-1',
      createdAt: '2026-04-01T00:00:00.000Z',
      updatedAt: '2026-04-01T00:00:00.000Z',
    };
    const bridgeAssignable: SharedNote = canonicalNote as SharedBridgeNote;
    assert.strictEqual(bridgeAssignable.projectId, 'proj-1');
    assert.strictEqual(bridgeAssignable.goalId, 'goal-1');

    const dartCore = read('flutter_app/lib/core/shared_foundation_core.dart');
    assert.doesNotMatch(dartCore, /package:flutter\//);
    assert.doesNotMatch(dartCore, /package:drift\//);
    assert.match(dartCore, /class SharedNoteContracts/);
    assert.match(dartCore, /static const int maxTitleLength = 250;/);
    assert.match(dartCore, /static const List<String> canonicalLinkedModules = \[\s*'tasks',\s*'finance',\s*'calendar',\s*\];/);
    assert.match(dartCore, /static const String defaultExchangeFolder = 'General';/);
    assert.match(dartCore, /static const String defaultFlutterCategory = 'general';/);
    assert.match(dartCore, /static const String defaultWebNotebook = 'Personal';/);
    assert.match(dartCore, /static const String legacyTaskIdAlias = 'taskId';/);
  });

  it('3. Flutter Drift Notes, NoteEntity, DatabasePersistenceCoordinator, and Web TaskNoteRecord align on reconciled fields & aliases', () => {
    const tables = read('flutter_app/lib/data/database/tables.dart');
    assert.match(tables, /class Notes extends Table[\s\S]*TextColumn get content =>/);
    assert.match(tables, /class Notes extends Table[\s\S]*TextColumn get category =>/);
    assert.match(tables, /class Notes extends Table[\s\S]*TextColumn get projectId =>/);
    assert.match(tables, /class Notes extends Table[\s\S]*TextColumn get goalId =>/);
    assert.match(tables, /class Notes extends Table[\s\S]*TextColumn get linkedModule =>/);
    assert.match(tables, /class Notes extends Table[\s\S]*TextColumn get linkedId =>/);
    assert.match(tables, /class Notes extends Table[\s\S]*BoolColumn get isTrashed =>/);

    const noteModels = read('flutter_app/lib/domain/notes/note_models.dart');
    assert.match(noteModels, /static const int maxTitleLength = 250;/);
    assert.match(noteModels, /json\['content'\] \?\? json\['body'\] \?\? ''/);
    assert.match(noteModels, /json\['category'\] \?\? json\['folder'\] \?\? 'general'/);
    assert.match(noteModels, /json\['projectId'\]/);
    assert.match(noteModels, /json\['goalId'\]/);

    const coordinator = read('flutter_app/lib/data/database/database_persistence_coordinator.dart');
    assert.match(coordinator, /'content': n\.content/);
    assert.match(coordinator, /'category': n\.category/);
    assert.match(coordinator, /'projectId': n\.projectId/);
    assert.match(coordinator, /'goalId': n\.goalId/);
    assert.match(coordinator, /ORPHANED_NOTE_PROJECT_CLEARED/);
    assert.match(coordinator, /ORPHANED_NOTE_GOAL_CLEARED/);
    assert.match(coordinator, /_optString\(n, 'content', ctx, allowEmpty: true\) \?\?[\s\S]*_optString\(n, 'body', ctx, allowEmpty: true\)/);
    assert.match(coordinator, /_optString\(n, 'category', ctx, allowEmpty: false\) \?\?[\s\S]*_optString\(n, 'folder', ctx, allowEmpty: false\)/);

    // Web domain normalizer accepts body/content and folder/category/notebook symmetrically
    const fromCanonical = normalizeTaskNoteRecord({
      id: 'n-canon',
      title: 'Canonical',
      body: 'Body text',
      folder: 'Reference',
      projectId: 'proj-1',
      goalId: 'goal-1',
      linkedModule: 'finance',
      linkedId: 'tx-1',
      isFavorite: true,
      isTrashed: false,
      createdAt: '2026-04-01T00:00:00.000Z',
      updatedAt: '2026-04-01T00:00:00.000Z',
    });
    assert.ok(fromCanonical);
    assert.strictEqual(fromCanonical.content, 'Body text');
    assert.strictEqual(fromCanonical.notebook, 'Reference');
    assert.strictEqual(fromCanonical.projectId, 'proj-1');
    assert.strictEqual(fromCanonical.goalId, 'goal-1');
    assert.strictEqual(fromCanonical.linkedModule, 'finance');
    assert.strictEqual(fromCanonical.linkedId, 'tx-1');
    assert.strictEqual(fromCanonical.isFavorite, true);
    assert.strictEqual(fromCanonical.isTrashed, false);

    const fromFlutter = normalizeTaskNoteRecord({
      id: 'n-flut',
      title: 'Flutter',
      content: 'Flutter content',
      category: 'reflection',
      createdAt: '2026-04-01T00:00:00.000Z',
      updatedAt: '2026-04-01T00:00:00.000Z',
    });
    assert.ok(fromFlutter);
    assert.strictEqual(fromFlutter.content, 'Flutter content');
    assert.strictEqual(fromFlutter.notebook, 'reflection');
  });

  it('4. SharedStateBridge round-trips canonical (body/folder), Flutter (content/category), and Web (content/notebook) Notes while clearing orphaned projectId/goalId', () => {
    withMockBrowserStorage((store) => {
      const payload = {
        schemaVersion: 5,
        snapshotFormatVersion: 2,
        databaseSchemaVersion: 12,
        financeSchemaVersion: 7,
        appVersion: '1.0.2+3',
        exportedAt: '2026-04-01T12:00:00.000Z',
        isFinanceSetupCompleted: false,
        openingBalanceCents: 0,
        accounts: [],
        categories: [],
        transactions: [],
        tasks: [
          {
            id: 'task-1',
            title: 'Linked Task',
            status: 'not_started',
            priority: 'medium',
            createdAt: '2026-04-01T10:00:00.000Z',
          },
        ],
        goals: [
          {
            id: 'goal-live',
            title: 'Live Goal',
            status: 'active',
          },
        ],
        projects: [
          {
            id: 'proj-live',
            title: 'Live Project',
            status: 'active',
            goalId: 'goal-live',
          },
        ],
        notes: [
          {
            id: 'note-canonical',
            title: 'Canonical Note',
            body: 'Canonical body',
            folder: 'General',
            tags: ['canon'],
            isPinned: true,
            isFavorite: true,
            isArchived: false,
            isTrashed: false,
            projectId: 'proj-live',
            goalId: 'goal-live',
            linkedModule: 'tasks',
            linkedId: 'task-1',
            createdAt: '2026-04-01T09:00:00.000Z',
            updatedAt: '2026-04-01T11:00:00.000Z',
          },
          {
            id: 'note-flutter',
            title: 'Flutter Note',
            content: 'Flutter body',
            category: 'reference',
            tags: ['flutter'],
            isPinned: false,
            isFavorite: false,
            isArchived: true,
            isTrashed: false,
            projectId: 'proj-missing',
            goalId: 'goal-missing',
            linkedModule: 'calendar',
            linkedId: 'evt-1',
            createdAt: '2026-04-01T08:00:00.000Z',
            updatedAt: '2026-04-01T10:30:00.000Z',
          },
          {
            id: 'note-web',
            title: 'Web Note',
            content: 'Web body',
            notebook: 'Personal',
            tags: [],
            isPinned: false,
            isArchived: false,
            linkedModule: 'finance',
            linkedId: 'tx-1',
            createdAt: '2026-04-01T07:00:00.000Z',
            updatedAt: '2026-04-01T09:30:00.000Z',
          },
        ],
        inboxItems: [],
        calendarEvents: [],
      };

      const importRes = SharedStateBridge.importFromAndroidJson(JSON.stringify(payload));
      assert.strictEqual(importRes.success, true, importRes.error);

      // Web runtime store persists content & notebook while preserving projectId, goalId, and links
      const storedRuntimeNotes = JSON.parse(store.get('daywell_notes') ?? '[]');
      assert.strictEqual(storedRuntimeNotes.length, 3);
      assert.strictEqual(storedRuntimeNotes[0].content, 'Canonical body');
      assert.strictEqual(storedRuntimeNotes[0].notebook, 'General');
      assert.strictEqual(storedRuntimeNotes[0].projectId, 'proj-live');
      assert.strictEqual(storedRuntimeNotes[0].goalId, 'goal-live');
      assert.strictEqual(storedRuntimeNotes[0].isFavorite, true);

      // Orphaned projectId/goalId on note-flutter are cleared safely without dropping the note
      assert.strictEqual(storedRuntimeNotes[1].projectId, undefined);
      assert.strictEqual(storedRuntimeNotes[1].goalId, undefined);
      assert.strictEqual(storedRuntimeNotes[1].linkedModule, 'calendar');
      assert.strictEqual(storedRuntimeNotes[1].linkedId, 'evt-1');

      // Re-exported canonical state emits canonical body & folder while keeping full metadata
      const exported = JSON.parse(SharedStateBridge.exportToAndroidJson());
      assert.strictEqual(exported.notes.length, 3);
      assert.deepStrictEqual(
        exported.notes.map((n: Record<string, unknown>) => ({
          id: n.id,
          body: n.body,
          folder: n.folder,
          projectId: n.projectId,
          goalId: n.goalId,
          linkedModule: n.linkedModule,
          linkedId: n.linkedId,
          isFavorite: n.isFavorite,
          isArchived: n.isArchived,
          isTrashed: n.isTrashed,
        })),
        [
          {
            id: 'note-canonical',
            body: 'Canonical body',
            folder: 'General',
            projectId: 'proj-live',
            goalId: 'goal-live',
            linkedModule: 'tasks',
            linkedId: 'task-1',
            isFavorite: true,
            isArchived: false,
            isTrashed: false,
          },
          {
            id: 'note-flutter',
            body: 'Flutter body',
            folder: 'reference',
            projectId: undefined,
            goalId: undefined,
            linkedModule: 'calendar',
            linkedId: 'evt-1',
            isFavorite: false,
            isArchived: true,
            isTrashed: false,
          },
          {
            id: 'note-web',
            body: 'Web body',
            folder: 'Personal',
            projectId: undefined,
            goalId: undefined,
            linkedModule: 'finance',
            linkedId: 'tx-1',
            isFavorite: false,
            isArchived: false,
            isTrashed: false,
          },
        ]
      );
    });
  });
});
