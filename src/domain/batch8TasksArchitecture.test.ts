import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';

describe('DAYWELL TO-DO & PROJECTS MODULE ARCHITECTURE AUDIT (PROMPT 2.4)', () => {
  const rootDir = process.cwd();
  const libDir = path.join(rootDir, 'flutter_app', 'lib');
  const domainTasksDir = path.join(libDir, 'domain', 'tasks');
  const appTasksDir = path.join(libDir, 'application', 'tasks');
  const repoTasksPath = path.join(libDir, 'data', 'repositories', 'tasks_repository.dart');
  const appDatabasePath = path.join(libDir, 'data', 'database', 'app_database.dart');

  it('1. Domain Layer Isolation: domain/tasks/ contains zero Drift, SQLite, or Flutter widget imports', () => {
    assert.strictEqual(fs.existsSync(domainTasksDir), true, 'domain/tasks directory must exist');

    const domainFiles = fs.readdirSync(domainTasksDir).filter((f) => f.endsWith('.dart'));
    assert.strictEqual(domainFiles.length >= 2, true, 'Must have task_models.dart and task_contracts.dart');

    for (const f of domainFiles) {
      const fullPath = path.join(domainTasksDir, f);
      const content = fs.readFileSync(fullPath, 'utf8');

      // Domain must not depend on Drift, SQLite, or Flutter UI
      assert.strictEqual(
        content.includes('package:drift'),
        false,
        `Domain file ${f} must NOT import Drift`
      );
      assert.strictEqual(
        content.includes('package:flutter/material.dart') || content.includes('package:flutter/widgets.dart'),
        false,
        `Domain file ${f} must NOT import Flutter UI widgets`
      );
      assert.strictEqual(
        content.includes('package:sqflite'),
        false,
        `Domain file ${f} must NOT import sqflite`
      );
    }
  });

  it('2. Repository Contract Decomposition: task_contracts.dart defines sub-contracts and unified ITasksRepository', () => {
    const contractsPath = path.join(domainTasksDir, 'task_contracts.dart');
    assert.strictEqual(fs.existsSync(contractsPath), true, 'task_contracts.dart must exist in domain layer');
    const content = fs.readFileSync(contractsPath, 'utf8');

    // Sub-contracts
    assert.strictEqual(content.includes('abstract class ITaskRepositoryContract'), true);
    assert.strictEqual(content.includes('abstract class IProjectRepositoryContract'), true);
    assert.strictEqual(content.includes('abstract class IMilestoneRepositoryContract'), true);

    // Unified interface implementing all sub-contracts
    assert.strictEqual(content.includes('abstract class ITasksRepository'), true);
    assert.strictEqual(content.includes('implements'), true);
    assert.strictEqual(content.includes('ITaskRepositoryContract'), true);
    assert.strictEqual(content.includes('IProjectRepositoryContract'), true);
    assert.strictEqual(content.includes('IMilestoneRepositoryContract'), true);
  });

  it('3. Data Layer Implementation: DriftTasksRepository implements ITasksRepository with atomic transactions', () => {
    assert.strictEqual(fs.existsSync(repoTasksPath), true, 'tasks_repository.dart must exist in data layer');
    const content = fs.readFileSync(repoTasksPath, 'utf8');

    // Implements ITasksRepository
    assert.strictEqual(content.includes('class DriftTasksRepository implements ITasksRepository'), true);

    // Queries relational tables
    assert.strictEqual(content.includes('_db.tasks'), true);
    assert.strictEqual(content.includes('_db.projects'), true);
    assert.strictEqual(content.includes('_db.milestones'), true);

    // Atomic relational cleanup on project deletion
    assert.strictEqual(content.includes('_db.transaction('), true);
  });

  it('4. Application Layer Encapsulation: TasksController and TasksModuleState decouple workflows from UI', () => {
    const controllerPath = path.join(appTasksDir, 'tasks_controller.dart');
    const statePath = path.join(appTasksDir, 'tasks_state.dart');

    assert.strictEqual(fs.existsSync(controllerPath), true, 'tasks_controller.dart must exist');
    assert.strictEqual(fs.existsSync(statePath), true, 'tasks_state.dart must exist');

    const controllerContent = fs.readFileSync(controllerPath, 'utf8');
    const stateContent = fs.readFileSync(statePath, 'utf8');

    // Controller depends on ITasksRepository abstraction, not Drift
    assert.strictEqual(controllerContent.includes('ITasksRepository'), true);
    assert.strictEqual(controllerContent.includes('package:drift'), false, 'Controller must NOT import Drift directly');

    // State is immutable and exposes deterministic calculations
    assert.strictEqual(stateContent.includes('class TasksModuleState'), true);
    assert.strictEqual(stateContent.includes('filteredTasks'), true);
    assert.strictEqual(stateContent.includes('todayCount'), true);
    assert.strictEqual(stateContent.includes('inboxCount'), true);
    assert.strictEqual(stateContent.includes('getProjectProgress'), true);
  });

  it('5. AppStateManager Integration: Composes and hydrates TasksController from SQLite without sync bridges', () => {
    const appStatePath = path.join(libDir, 'ui', 'app_state.dart');
    const content = fs.readFileSync(appStatePath, 'utf8');

    assert.strictEqual(
      content.includes('late final TasksController tasksController;') ||
        content.includes('late TasksController tasksController;'),
      true
    );
    assert.strictEqual(content.includes('tasksController = TasksController('), true);
    assert.strictEqual(content.includes('tasksController.loadAll()'), true);
    assert.strictEqual(content.includes('_syncTasksController'), false);
  });

  it('6. Presentation Layer: TasksView supports direct TasksController injection', () => {
    const viewPath = path.join(libDir, 'ui', 'screens', 'tasks_view.dart');
    const content = fs.readFileSync(viewPath, 'utf8');

    assert.strictEqual(content.includes('final TasksController? controller;'), true);
    assert.strictEqual(content.includes('TasksController get effectiveController'), true);
  });

  it('7. Schema Version 5 Integrity Verification: app_database.dart upgrades to schemaVersion 5 and preserves historical migrations', () => {
    assert.strictEqual(fs.existsSync(appDatabasePath), true, 'app_database.dart must exist');
    const content = fs.readFileSync(appDatabasePath, 'utf8');

    const versionMatch = content.match(/int get schemaVersion => (\d+);/);
    assert.ok(versionMatch && Number(versionMatch[1]) >= 5, 'schemaVersion must be >= 5');

    // Verify historical migrations v1 -> v2, v2 -> v3, v3 -> v4, and v4 -> v5
    assert.strictEqual(content.includes('if (from < 2)'), true);
    assert.strictEqual(content.includes('if (from < 3)'), true);
    assert.strictEqual(content.includes('if (from < 4)'), true);
    assert.strictEqual(content.includes('if (from < 5)'), true);
  });
});
