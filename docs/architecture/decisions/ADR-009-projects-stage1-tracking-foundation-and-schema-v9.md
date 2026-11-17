# ADR-009: Projects Stage 1 Composable Tracking Foundation and Schema v9

- **Status:** accepted
- **Date / Version:** 2026-11-17 / Projects Stage 1 (`AppDatabase.schemaVersion = 9`, `schema_contracts.json = 9`)
- **Affected Docs:** [`docs/architecture/overview.md`](../overview.md), [`docs/architecture/shared-foundation.md`](../shared-foundation.md), [`docs/architecture/data-and-persistence.md`](../data-and-persistence.md), [`docs/architecture/module-boundaries.md`](../module-boundaries.md), [`docs/architecture/cross-platform-parity.md`](../cross-platform-parity.md), [`docs/architecture/testing-standards.md`](../testing-standards.md)

---

## Context

Projects in Daywell previously existed only as a lightweight container (`Projects` + `Milestones` managed inside `DriftTasksRepository` and `TasksController`) that derived a single combined task/milestone percentage. That model could not represent diverse user-defined initiatives—such as an outreach campaign with nested region/city targets and dated batch logs, or a curriculum with planned lesson dates, planned durations, and separate actual watched minutes—without either hardcoding single-purpose screens/tables per use case or stuffing mutable tracking history into unindexed JSON blobs.

## Decision

1. **Projects Inside the Tasks Workspace via Dedicated Abstractions:** Retain Projects within the Tasks workspace and preserve existing `Tasks.projectId`, `Milestones.projectId`, `Notes.projectId`, and `Projects.goalId` foreign keys, while introducing a dedicated pure-domain `IProjectsRepository` (`DriftProjectsRepository` on Flutter, `WebProjectsRepository` on Web) and a dedicated `ProjectsController` decoupled from `TasksController`.
2. **Pragmatic 3-Table Relational Persistence Model (`schemaVersion = 9`):**
   - Extend `Projects` additively with `isArchived` (`false` default), optional `startDate` (`YYYY-MM-DD`), bounded `customFieldsJson` (`'{}'` default), and `updatedAt` (backfilled from `createdAt` on upgrade).
   - Add `ProjectTrackingBlocks` supporting 4 initial block types (`counter`, `grouped_list`, `checklist`, `schedule`) with typed per-block `configJson`.
   - Add `ProjectTrackingRecords` supporting 5 record types (`group`, `grouped_item`, `checklist_item`, `schedule_item`, `progress_log`) with strict project/block/parent ownership validation, cycle detection, and optional `linkedTaskId` (`ON DELETE SET NULL`).
3. **Separate Lifecycle Archive Flag (`isArchived`):** Keep `isArchived: boolean` orthogonal to project `status` (`active`, `completed`, `on_hold`), preserving existing statuses and historical progress data on archive.
4. **Append-Only Progress Logs & Deterministic Derived Metrics:** Treat `progress_log` entries as append-only (`updateRecord` / `deleteRecord` reject mutations fail-closed; adjustments use explicit compensating logs via `metadata.isCorrection`, `metadata.compensatesRecordId`, and `metadata.correctionReason`). Derive all counter, group, daily, and duration totals deterministically in `ProgressEngine` / `projectsEngine.ts`, disallow implicit averaging across unrelated blocks, require explicit `customFields.primaryBlockId` for `overallPercentage`, and forbid direct logging on rollup counters configured with `rollupSourceBlockId`.
5. **Version Domain & Stage Boundaries:**
   - Advance `schema_contracts.json` and `AppDatabase.schemaVersion` from `8` to `9`; expand canonical snapshot compatibility bounds from `4..8` to `4..9` (`SharedStateBridge` accepts `4..9` while still emitting canonical exchange `schemaVersion: 5` alongside `financeSchemaVersion: 7`).
   - Keep `.daywell` encrypted backup `format_version: 1` and Finance exchange contract versions unchanged.
   - Defer Stage 2 UI screens, full 100-city seed fixtures, and Stage 3 portable `.daywellproject` package serialization/import workflows out of Stage 1.

## Justification

- A 3-table relational model supports SQL indexing (`project_id`, `block_id`, `parent_record_id`, `recorded_date`, `linked_task_id`), relational cascade/detach rules, and partial/incremental batch log appends without table proliferation or large-JSON write amplification.
- Deriving totals strictly from persisted logs eliminates counter drift and mirrors Daywell's ledger integrity model (`ADR-003`).
- Keeping `isArchived` separate from `status` protects existing v4–v8 backups and Tasks filters per `ADR-007`.

## Migration Strategy

- Atomic SQLite `from < 9` upgrade checks existing columns/tables idempotently, adds `projects.{is_archived, start_date, custom_fields_json, updated_at}`, backfills `updated_at` from `created_at`, creates `project_tracking_blocks`, `project_tracking_records`, and 5 v9 indices, and executes `PRAGMA foreign_key_check` prior to commit.
- Older v4–v8 canonical snapshots and `.daywell` backups restore safely with empty `projectTrackingBlocks` and `projectTrackingRecords` lists.

## Affected Consumers

- `shared_foundation/{schema_contracts.json,business_rules.json}`, generated `src/domain/sharedFoundation.ts`, `flutter_app/lib/core/shared_foundation*.dart`.
- Flutter `domain/projects/*`, `application/projects/*`, `data/database/{tables.dart,app_database.dart,database_persistence_coordinator.dart}`, `data/repositories/projects_repository.dart`, `ui/app_state.dart`, `services/backup/encryption_backup_service.dart`.
- Web `src/domain/projectsEngine.ts`, `src/data/projectsRepository.ts`, `src/services/sharedStateBridge.ts`.

## Alternatives Considered

1. **Per-Block Normalized Tables (6+ tables):** Rejected due to unnecessary migration and coordinator complexity in Stage 1.
2. **Single JSON Blob Inside `Projects`:** Rejected because mutable nested items and append-only dated progress logs cannot be SQL-indexed or foreign-key checked cleanly.
3. **Encoding `archived` Into `Project.status`:** Rejected because archiving would overwrite user-selected `active`/`completed`/`on_hold` status and break legacy status contracts.

## Consequences & Trade-Offs

- **Positive:** One shared relational model handles counters, hierarchical groups, checklists, and schedules without custom scripting or Finance coupling; Tasks/Milestones/Notes compatibility remains intact.
- **Trade-Off:** Pre-v9 Android builds cannot open v9 SQLite files or v9 snapshots (failing closed via `UnsupportedDatabaseVersionException` / `unsupportedFutureSchema`). Flutter `build_runner` regeneration and `flutter test` remain CI-pending where Dart/Flutter SDK is absent locally.
