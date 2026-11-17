# Daywell — Projects Module: Stage 1 (Architecture, Shared Contracts & Persistence Foundation)

Establishes an extensible, 100% offline-first Projects data model, shared cross-platform contracts, and backward-compatible SQLite and browser storage foundation inside the Tasks workspace without modifying Finance or building Stage 2/3 user interfaces prematurely.

### User Review & Critical Decisions

> [!IMPORTANT]
> **Confirmed Stage 1 Architectural Choices (From Clarification Interview)**
> All three core structural decisions have been confirmed and govern this Stage 1 implementation:

- **Confirmed Decision 1 — Module Integration**: Extend the existing Projects entity and persistence table inside the Tasks workspace, paired with a dedicated Projects repository interface and dedicated Projects application controller (preserving existing Tasks, Milestones, and Notes foreign-key links while keeping Task–Project orchestration decoupled).
- **Confirmed Decision 2 — SQLite Persistence Granularity**: Use a pragmatic **3-table relational model**—the extended Projects table, a reusable Tracking Blocks table, and a unified Tracking Records & Append-Only Progress Logs table—instead of proliferation across 6+ single-purpose tables or burying mutable tracking logs inside opaque project JSON blobs.
- **Confirmed Decision 3 — Archive Lifecycle & Compatibility**: Add an explicit `isArchived` boolean alongside existing project statuses (`active`, `completed`, `on_hold`) so prior backups, Tasks filters, and compatibility baselines remain 100% intact.

> [!NOTE]
> **Database & Snapshot Versioning Note (`v8` → `v9`)**
> Extending Shared Foundation entity contracts and adding new SQLite tables/columns requires incrementing both the Shared Foundation contract version and the authoritative SQLite database schema from version `8` to `9`, with a transactional non-destructive upgrade step and updated canonical snapshot bounds (`4..9`).

---

### 1. Overview & Core Concept

- **What It Does**: Evolves Daywell’s basic project-and-milestone container into a structured, composable project tracking engine capable of representing wildly different user-created projects—from outbound outreach campaigns to multi-video learning plans—through reusable typed tracking blocks, hierarchical groups, schedules, custom metadata fields, and append-only dated progress logs.
- **Target Audience / Persona**: Offline-first Daywell users managing multi-week or multi-month initiatives alongside daily Tasks, Notes, and Calendar events, including desktop-prepared projects that will later transfer into Android in Stage 3.
- **Key Value**: Lets one stable relational schema and pure domain progress engine power diverse projects without hardcoding project-specific screens, custom scripting runtimes, or bespoke per-template tables.

---

### 2. User Experience & Visual Design

> [!NOTE]
> **Stage 1 Scope Boundary — Foundation Only**
> Stage 1 delivers zero end-user UI changes so domain boundaries, accounting/date invariants, and persistence settle first before Stage 2 interactive screens and Stage 3 portable project packages. Existing Flutter and Web views remain visually untouched.

- **Key User Flows Supported Under the Hood**:
  - **Batch Outreach Workflow (Use Case A — BIM Company Outreach)**: Create a project with a target deadline, daily outreach pace target, custom campaign metadata, a campaign-wide counter block (e.g., `1,000` emails), and a hierarchical grouped list (`10` region/city groups holding `100` cities with individual targets). Log outreach batches strictly by city record, email count, and canonical date (`YYYY-MM-DD`), while campaign, group, city, and daily-pace totals derive deterministically from persisted logs.
  - **Structured Curriculum Workflow (Use Case B — Video Learning Plan)**: Create a project containing ordered video checklist or schedule items with individual durations (minutes), planned dates (`YYYY-MM-DD`), completion states, optional links to Daywell Tasks, and independent progress rollups tracking videos completed, minutes watched, and scheduled lessons finished.
- **Visual Identity & Stage 2 Readiness**:
  - Multi-metric progress summaries and tracking-block status models will surface structured labels, percentages, counts, and remaining-pace figures aligned cleanly with Daywell’s single canonical design token system (`--dw-*` / `DaywellTheme`) and tabular numeric typography when Stage 2 UI is built.
- **Interactive Feedback & Integrity Guards**:
  - Domain validators fail closed on negative batch counts, invalid canonical dates, missing parent blocks/groups, cyclic group links, or unknown tracking block types, giving Stage 2 screens clear deterministic validation messages before any write executes.

---

### 3. Key Product Decisions & Trade-Offs

- **Audit Finding — Preserving Reusable Foundations**:
  - **Chosen Approach**: Reuse existing Ethiopian civil calendar & UTC timestamp utilities, existing Tasks/Notes/Milestones foreign-key links to Projects, and the existing project progress engine (expanded additively into a multi-metric domain engine).
  - **Why**: Existing Tasks and Notes modules already associate records to Projects via `projectId` (`ON DELETE SET NULL`), and keeping shared date normalization prevents timezone drift around `UTC+3`.
  - **Conflicts Addressed**: Web currently separates a prototype card list inside the app shell from the canonical bridge projects store; Stage 1 anchors Web Projects state on a canonical repository + storage keys synced through the bridge without altering legacy Web UI prototype cards prematurely.

- **Decision 1 — Pragmatic 3-Table Persistence Over 6+ Tables or Single-Blob JSON**:
  - **Chosen Approach**: Extend the existing Projects table additively (`isArchived`, `startDate`, `customFieldsJson`, `updatedAt`) and add two foreign-keyed child tables: `ProjectTrackingBlocks` (reusable block configurations per project) and `ProjectTrackingRecords` (structured items such as groups, grouped items, checklist items, schedule items, and append-only `progress_log` entries).
  - **Why**: Querying, indexing, cascade-deleting, foreign-key checking, and migrating stay lightweight while keeping mutable records normalized (preventing write-amplification or concurrency corruption from rewriting huge project JSON documents on every batch log).
  - **Alternatives Considered**: A 6+ table normalized hierarchy for every block variant adds heavy migration boilerplate for little gain in Stage 1; storing all cities/videos/logs inside one JSON column breaks SQL indexing and integrity checks.

- **Decision 2 — Strictly Derived Totals for Counter & Grouped Progress**:
  - **Chosen Approach**: Keep cumulative counts (`cityCount`, `groupCount`, `campaignTotal`, daily totals) strictly derived from persisted `progress_log` records inside the domain engine rather than trusting cached mutable counters.
  - **Why**: Avoids silent drift when a batch log is added, edited, deleted, or imported across devices, directly mirroring Daywell’s ledger-first integrity discipline in Finance.
  - **Alternatives Considered**: Updating stored `currentValue` counters inline risks partial-write desynchronization if logs are edited or restored out of order.

- **Decision 3 — Forward-Only, Additive Backward Compatibility (`ADR-007`)**:
  - **Chosen Approach**: Add optional fields and new project tracking collections additively in Shared Foundation, bump SQLite & schema contracts cleanly from `v8` → `v9` with idempotent column/table checks and foreign-key verification, and expand snapshot/encrypted backup bounds (`4..9`) so `v4..v8` snapshots and `.daywell` backups restore cleanly with empty tracking blocks/records.
  - **Why**: Guarantees zero disruption to existing user data, Tasks workflows, Finance ledgers, and released `.daywell` backups.

---

### 4. Technical Architecture & Data Strategy *(Technical Reference)*

#### System Architecture & Data Flow Diagram

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                       SHARED FOUNDATION CONTRACTS (v9)                       │
│  Canonical Entity Schemas (Project + TrackingBlock + TrackingRecord)        │
│  Allowed Block Types, Record Types, Custom Field Types & Progress Rules     │
└───────────────────────────────┬──────────────────────┬───────────────────────┘
                                │                      │
               generated rules  │                      │  generated TS contracts
               & enums          ▼                      ▼  & constants
┌─────────────────────────────────────────┐  ┌─────────────────────────────────┐
│     FLUTTER ANDROID (Authoritative)     │  │      WEB PREVIEW (Parity)       │
│                                         │  │                                 │
│  ┌───────────────────────────────────┐  │  │  ┌───────────────────────────┐  │
│  │  Domain Layer (Pure Dart)         │  │  │  │ Domain Layer (Pure TS)    │  │
│  │  • Project, Block, Record Models  │  │  │  │ • Parity Validation       │  │
│  │  • Custom Field Typed Schema      │  │  │  │ • Multi-Metric Engine     │  │
│  │  • Multi-Metric Progress Engine   │  │  │  │   (Tasks/Milestones/Logs/ │  │
│  │  • IProjectsRepository Contract   │  │  │  │    Durations/Schedule Pace)│  │
│  └─────────────────┬─────────────────┘  │  │  └─────────────┬─────────────┘  │
│                    │                    │  │                │                │
│  ┌─────────────────▼─────────────────┐  │  │  ┌─────────────▼─────────────┐  │
│  │  Application Layer                │  │  │  │ Web Projects Repository   │  │
│  │  • ProjectsController & State     │  │  │  │ & SharedStateBridge (v9)  │  │
│  │    (wired into AppStateManager;   │  │  │  │ • Browser Storage Sync    │  │
│  │     TasksController preserved)    │  │  │  │ • Cross-Platform Import/  │  │
│  └─────────────────┬─────────────────┘  │  │  │   Export Parity           │  │
│                    │                    │  │  └───────────────────────────┘  │
│  ┌─────────────────▼─────────────────┐  │  └─────────────────────────────────┘
│  │  Data & Persistence Layer         │  │
│  │  • Drift SQLite Schema v9         │  │
│  │    - Projects (extended)          │  │
│  │    - ProjectTrackingBlocks        │  │
│  │    - ProjectTrackingRecords       │  │
│  │  • Atomic v8 → v9 Migration       │  │
│  │  • Coordinator & .daywell Backups │  │
│  │    (Snapshot/Restore Bounds 4..9) │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

#### Data Model & State Entities

1. **Extended Project Entity (`Projects` Table — Schema v9)**:
   - Keeps `id`, `goalId` (FK `Goals`, `ON DELETE SET NULL`), `title`, `description`, `status` (`active | completed | on_hold`), `targetDate` (`YYYY-MM-DD`), `createdAt`.
   - Adds `isArchived` (`false` default), `startDate` (`YYYY-MM-DD`, optional), `customFieldsJson` (serialized typed project metadata & definitions, `'{}'` default), `updatedAt` (timestamp, backfilled to `createdAt` on upgrade).

2. **Project Tracking Block Entity (`ProjectTrackingBlocks` Table — Schema v9)**:
   - Links to parent project via `projectId` (`ON DELETE CASCADE`).
   - Supports canonical `blockType` values: `counter`, `grouped_list`, `checklist`, `schedule`.
   - Captures `title`, `unit` (e.g., `emails`, `videos`, `minutes`), optional integer `targetValue` and `dailyTargetValue`, `sortOrder`, `isArchived`, typed `configJson` (column/field definitions and rollup hints), `createdAt`, `updatedAt`.

3. **Project Tracking Record Entity (`ProjectTrackingRecords` Table — Schema v9)**:
   - Links to `projectId` and `blockId` (`ON DELETE CASCADE`), optional self-reference `parentRecordId` (`ON DELETE CASCADE`, supporting group → item and item → log hierarchy), and optional `linkedTaskId` (FK `Tasks`, `ON DELETE SET NULL`, supporting task-linked videos/steps without duplicating Tasks).
   - Supports canonical `recordType` values:
     - `group` (e.g., BIM city-group header with derived subgroup rollups)
     - `grouped_item` (e.g., BIM city with individual integer `targetValue`)
     - `checklist_item` (ordered deliverable or video item with completion state and optional duration)
     - `schedule_item` (scheduled session/lesson with canonical `scheduledDate` and `durationMinutes`)
     - `progress_log` (append-only dated delta entry storing `deltaValue`, canonical `recordedDate` `YYYY-MM-DD`, and optional note)
   - Captures `title`, `isCompleted`, `targetValue`, `deltaValue`, `durationMinutes`, `scheduledDate`, `recordedDate`, `sortOrder`, structured `metadataJson` (custom field values), `createdAt`, `updatedAt`.

4. **Shared Business Rules & Derived Multi-Metric Progress Summary**:
   - **Independent Measurements Preserved**: A project progress snapshot reports structured measurements rather than collapsing everything to one ambiguous number:
     - Linked tasks completed / total
     - Milestones completed / total
     - Checklist / grouped items completed / total
     - Numeric target completed / total (derived by summing `progress_log.deltaValue` overall, per group, per item, and by date for daily-target pace)
     - Duration minutes completed / total (for time-weighted curricula like Video Learning Plans)
     - Schedule adherence (scheduled items completed vs. due by reference date)
     - Explicit primary rollup percentage derived cleanly across active measurements (`0..100`).
   - **Custom Fields Contract**: Typed key/definition schema supporting `text`, `number`, `date`, `boolean`, and `select` values without dynamic expression evaluation or arbitrary scripts.

#### Interactive Component, Persistence & Migration Mapping

- **Atomic SQLite `v8` → `v9` Migration**:
  - Checks existing table schema idempotently before adding `projects` columns (`is_archived`, `start_date`, `custom_fields_json`, `updated_at`), backfills `updated_at` cleanly from `created_at` without touching Tasks/Finance/Notes rows, creates `project_tracking_blocks` and `project_tracking_records` tables plus query indices (`project_id`, `block_id`, `parent_record_id`, `recorded_date`), and runs foreign-key integrity checks inside the transaction.
- **Snapshot & Encrypted Backup Round-Trip**:
  - Database persistence exports and restores `projectTrackingBlocks` and `projectTrackingRecords` atomically alongside existing modules in strict parent-before-child FK order, sanitizes dangling optional references (`goalId`, `linkedTaskId`), rejects orphan required block/record parent IDs fail-closed before mutation, and preserves backward compatibility for prior `v4..v8` snapshots and backups.
- **Controller & Cross-Platform Parity**:
  - Flutter `ProjectsController` coordinates project CRUD, tracking blocks, group/item records, batch progress logging, archive/status transitions, and multi-metric summaries through `IProjectsRepository` and integrates cleanly into `AppStateManager` recovery/reload flows while preserving `TasksController` compatibility.
  - Web mirrors the exact same domain validation, progress calculation rules, canonical storage sync, and snapshot bridge handling (`schemaVersion` exchange + `projectTrackingBlocks` / `projectTrackingRecords` validation), accompanied by unit tests modeling both **BIM Company Outreach** (100 cities in 10 groups, 1,000 target, batch logging) and **Video Learning Plan** (100 videos with durations & dates), plus Flutter `v8` → `v9` migration tests and updated architecture docs.
