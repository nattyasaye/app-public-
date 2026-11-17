# Daywell — Data & Persistence Architecture

> **Purpose:** Authoritative specification of Daywell's offline-first local storage, Drift SQLite v9 schema, migrations, financial & project integrity invariants, backup encryption, and cross-platform data exchange.  
> **Governed By:** [PROJECT_CONSTITUTION.md](../../PROJECT_CONSTITUTION.md) (Sections 2.5, 2.6, 2.11), [ADR-007](./decisions/ADR-007-mandatory-backward-compatibility.md), [ADR-008](./decisions/ADR-008-retire-account-isactive-and-schema-v8.md), and [ADR-009](./decisions/ADR-009-projects-stage1-tracking-foundation-and-schema-v9.md)

---

## 1. Persistence Architecture Overview

Daywell enforces sovereign local storage with zero mandatory remote database:

| Platform | Primary Store | Status | Secondary / Exchange Format |
| :--- | :--- | :--- | :--- |
| **Flutter Android** | Drift SQLite (`personal_management.sqlite`, `schemaVersion => 9`) | **Implemented** (on-device runtime APK behavior **Unverified** in Linux container) | Canonical JSON snapshot (`DatabasePersistenceCoordinator`, exports `schemaVersion: 9`) + `.daywell` PBKDF2/AES-GCM-256 encrypted JSON envelope (`EncryptionBackupService`, `format_version: 1`) + raw cold recovery bundle (`RawDatabaseRecoveryExporter`). Stage 3 `.daywellproject` portable project package remains **Planned**. |
| **Web Preview** | Browser `localStorage` (`daywell_canonical_database_v3` + per-module keys + `localDatabase.ts` store + `WebProjectsRepository`) | **Implemented** | Canonical JSON export/import via `SharedStateBridge`; `backupCrypto.ts` Web Crypto PBKDF2/AES-GCM-256 helper (**Implemented** in domain/tests, **not wired** to `sync_backup` screen UI) |

---

## 2. Flutter Drift SQLite Schema (`schemaVersion => 9`)

Defined in `/flutter_app/lib/data/database/tables.dart` and registered in `AppDatabase` (`/flutter_app/lib/data/database/app_database.dart`):

### Complete Verified 24-Table Inventory

| Domain Group | Table Class (count) | Purpose & Key Relational Rules |
| :--- | :--- | :--- |
| **Productivity, Planning & Projects Tracking (9)** | `InboxItems`, `Goals`, `Projects`, `ProjectTrackingBlocks`, `ProjectTrackingRecords`, `Milestones`, `Tasks`, `Notes`, `CalendarEvents` | `Projects.goalId -> Goals` (`SET NULL`); `Projects` adds `isArchived`, `startDate`, `customFieldsJson`, `updatedAt` in v9. `ProjectTrackingBlocks.projectId -> Projects` (`CASCADE`). `ProjectTrackingRecords` links `projectId -> Projects` (`CASCADE`), `blockId -> ProjectTrackingBlocks` (`CASCADE`), `parentRecordId -> ProjectTrackingRecords` (`RESTRICT`, deleted bottom-up on project/block delete), and `linkedTaskId -> Tasks` (`SET NULL`). `Milestones.projectId -> Projects` (`CASCADE`); `Tasks.projectId/milestoneId` (`SET NULL`); `Notes.projectId/goalId` (`SET NULL`). Dates stored as canonical `YYYY-MM-DD` strings (`schema v5+`). |
| **System & Alerts (2)** | `Reminders`, `AppSettings` | `Reminders` (`schema v8+`) includes nullable `title` and `channelId` (`channel_id`) columns; `AppSettings` holds key-value user preferences and internal sentinels (`initial_seed_completed`, `is_finance_setup_completed`, `opening_balance_cents`, `ledger_migration_report_v7`, v6 sentinel). |
| **Legacy / Compat Finance (5)** | `FinancialCategories`, `FinancialTransactions`, `FinancialCommitments`, `CommitmentSettlementsTable`, `SavingsGoals` | v7 enforces `ON DELETE RESTRICT` on category, linked account, debt, entry, and recurring-rule FKs. `FinancialCommitments` adds `direction` (`outflow`/`inflow`) and `legacyPaidUnverified`. |
| **Double-Entry Ledger (8)** | `AccountsTable`, `PartiesTable`, `JournalEntriesTable`, `PostingsTable`, `DebtsTable`, `SettlementAllocationsTable`, `BudgetsTable`, `RecurringRulesTable` | `AccountsTable` standardizes account lifecycle on `isArchived` ([ADR-008](./decisions/ADR-008-retire-account-isactive-and-schema-v8.md)). Strictly enforces `ON DELETE RESTRICT` on ledger links (`PostingsTable -> JournalEntriesTable & AccountsTable`, `DebtsTable -> originEntryId & PartiesTable`, etc.). |

### Projects Stage 1 Data & Calculation Invariants (**Implemented** — Web Node-verified; Flutter CI-pending)

- **Projects vs. Tasks Distinction:** Ordinary **Tasks** remain single actionable items managed in `TasksController` / `DriftTasksRepository`, optionally associating to a Project via `Tasks.projectId`. **Projects** are independent user-created initiatives representing structured outcomes, milestones, custom metadata definitions/values (`customFieldsJson`), and reusable tracking blocks managed through `IProjectsRepository` (`DriftProjectsRepository` / `WebProjectsRepository`) and `ProjectsController`.
- **Three-Table Relational Model:**
  1. `Projects`: Keeps `id`, `goalId`, `title`, `description`, `status` (`active | completed | on_hold`), `targetDate`, `createdAt` and adds `isArchived` (orthogonal lifecycle flag preserving `status`), optional `startDate` (`YYYY-MM-DD`), typed `customFieldsJson` (`definitions`, `values`, `primaryBlockId`), and `updatedAt`.
  2. `ProjectTrackingBlocks`: Per-project reusable typed blocks (`counter`, `grouped_list`, `checklist`, `schedule`) with `unitLabel`, optional `targetValue`, optional `dailyTargetValue`, `sortOrder`, `isArchived`, and typed `configJson` (no arbitrary formulas/scripts). Max `32` blocks per project.
  3. `ProjectTrackingRecords`: Unified records (`group`, `grouped_item`, `checklist_item`, `schedule_item`, `progress_log`) with `parentRecordId`, optional `linkedTaskId`, `targetValue`, `deltaValue`, `durationMinutes`, `isCompleted`/`completedAt`, canonical `recordedDate`/`scheduledDate` (`YYYY-MM-DD`), and bounded `metadataJson`.
- **Ownership, Hierarchy, Deletion & Append-Only History:**
  - Validation rejects cross-project block references, cross-block/missing parent records, invalid record-to-block pairings, parent cycles, nesting deeper than `3`, direct logging on rollup counters (`rollupSourceBlockId != null`), checklist progress logs, missing `goalId`/`linkedTaskId` on writes, and negative `progress_log` deltas without explicit correction metadata.
  - `progress_log` rows are append-only: `updateRecord` and `deleteRecord` fail closed; corrections must append a compensating `progress_log` (`metadata.isCorrection = true`, `compensatesRecordId`, `correctionReason`) via `appendProgressCorrection`.
  - Archiving a project or block never destroys historical records. Deleting a block or project cascades only owned tracking blocks/records/milestones bottom-up while detaching `Tasks.projectId` to `null` (`Tasks` survive intact).
- **Deterministic Progress & Duration Rules:**
  - `ProgressEngine` / `projectsEngine.ts` treat project definitions (`targetValue`, planned `durationMinutes`, `customFields`) as distinct from derived rollups (`loggedTotal`, `groupMetrics`, `dailyTotalsByDate`, `actualLoggedDurationMinutes`), maintaining one source of truth when a counter rolls up from a `grouped_list` via `rollupSourceBlockId`.
  - Multiple independent measurements (counter/grouped items, checklist completion, schedule completion, planned vs. actual watched minutes, linked tasks excluding `cancelled`, milestones) are never implicitly averaged; `overallPercentage` is populated **only** when `customFields.primaryBlockId` references an existing non-archived block.
  - For video/curriculum schedules, `durationMinutes` stores planned length, `progress_log.deltaValue` records actual watched minutes without conflating completion with watched time, and `ScheduleBlockConfig.completionRule` evaluates `manual`, `threshold_percent`, or `exact_duration` explicitly via `meetsScheduleDurationRule`.

### Migration & Hardening Chain (`AppDatabase.onUpgrade`)
- **Fail-Closed Downgrade Guard (`from > to`) & `schemaVersion => 9`:** Because Drift's `MigrationStrategy` has no `onDowngrade` callback and routes `from > to` opens into `onUpgrade(m, from, to)`, the top of `onUpgrade` immediately throws `UnsupportedDatabaseVersionException(fromVersion: from, toVersion: to)` before any `from < N` step or index statement runs. Because Drift (`NativeDatabase`) does not automatically wrap `onUpgrade` in a SQLite transaction, `AppDatabase.migration` explicitly wraps `onUpgrade` execution inside `transaction(() async { ... })` via `_withTransactionalUpgrade` (after the fail-closed `from > to` guard) so any failure rolls back all DDL and DML atomically.
- `from < 2`: Creates double-entry tables (`AccountsTable`, `PartiesTable`, `JournalEntriesTable`, `PostingsTable`, `DebtsTable`, `SettlementAllocationsTable`).
- `from < 3`: Adds `openingBalanceCents` and `openingBalanceDate` to `AccountsTable`.
- `from < 4`: Adds rich task/note fields, `isArchived` on categories, transaction transfer/correction columns, and `CalendarEvents`.
- `from < 5`: Pre-flight validates legacy dates (`_validateLegacyDatesBeforeV5Migration` fail-closed), adds `endDateIso`, and converts `DateTimeColumn` civil dates to canonical `YYYY-MM-DD` strings in `UTC+3`.
- `from < 6` / `< 7`: `V6LedgerMigrator` + `V7LedgerHardener` normalize account `subType` & `isSystem`, synthesize `SYSTEM_CONTROL_ACCOUNT_IDS`, link debt write-offs, backfill `CommitmentSettlementsTable`, verify 5-case opening balances, audit Tier A/B debt controls, and run `verifyInvariantsOnly(db)`—rolling back atomically on failure.
- `from < 8`: Additive, idempotent reminder fidelity upgrade adding nullable `reminders.title` and `reminders.channel_id` via `_addColumnIfMissing` and running `PRAGMA foreign_key_check` prior to commit, preserving all pre-existing reminder rows with `null` values for the new columns.
- `from < 9`: Additive, idempotent Projects Stage 1 upgrade adding `projects.{is_archived, start_date, custom_fields_json, updated_at}`, backfilling `updated_at = created_at` on pre-existing rows without mutating Tasks/Milestones/Notes/Finance data, creating `project_tracking_blocks`, `project_tracking_records`, and 5 v9 query indices (`idx_project_blocks_project_sort`, `idx_project_records_project_block`, `idx_project_records_parent`, `idx_project_records_recorded_date`, `idx_project_records_linked_task`), and running `PRAGMA foreign_key_check` prior to commit.
- `beforeOpen`: Enables `PRAGMA foreign_keys = ON` after the migration transaction commits. (Because SQLite ignores `PRAGMA foreign_keys` toggles inside an active transaction as a no-op, pre-commit relational checks inside `onUpgrade` MUST execute `PRAGMA foreign_key_check` explicitly.)

---

## 3. Financial & Calendar Data Invariants

### Finance Invariants (**Partially implemented** — Recovery Stage 2.1 **Implemented** / Conditionally Accepted; Stage 2.2 ETB Isolation **Implemented in Code; Android CI Pending**)
- **Integer Minor Units (Stage 2.1 — Implemented / Conditionally Accepted)**: `1 ETB = 100 cents`. Zero floating-point amounts in ledger design and core domain rules.
- **Balanced Postings & System Control Accounts (`SYSTEM_CONTROL_ACCOUNT_IDS`)**: Every `JournalEntry` requires $\sum \text{Debits} == \sum \text{Credits}$ and strictly positive `amountCents`; system control IDs (`acc-sys-equity`, `acc-sys-income`, `acc-sys-expense`, `acc-sys-receivable`, `acc-sys-payable`, `acc-sys-legacy-offset`) are excluded from user account totals.
- **Immutable History**: Transactions/journal entries use `isVoided` / `isSuperseded` + `correctedFromEntryId` / `voidReason` instead of destructive history rewriting.
- **Finance v7 Ledger Integration Status**: Existing Finance v7 architecture is **Partially implemented**, with identified defects and incomplete cross-platform integration between Flutter SQLite and Web Preview (`localStorage` / `SharedStateBridge`).
- **Stage 2.2 Strict ETB Currency Isolation ([ADR-003](./decisions/ADR-003-finance-v7-double-entry-and-etb-isolation.md)):** Accounts classify deterministically via `classifyCurrencyCode` as `verified_etb`, `verified_non_etb`, or `unverified`. All new account creations, ledger writes, transfers, commitments, savings goals, recurring rules, quick-capture triage, `SharedFoundationBridge.auditConsistency`, and fail-closed `unvoidJournalEntry`/`restoreTransaction` activations enforce verified ETB only; legacy unverified accounts remain isolated/read-only (rename/archive only); non-ETB and unverified persisted records remain strictly excluded from ETB Safe Harbor, Net Worth, P&L, Cashflow, and debt totals while displaying explicit `Excluded (<CODE>)` / `Currency Review` / `(Unverified)` indicators without reinterpreting unknown amounts as ETB. Strict integer minor-unit decimal parsing eliminates floating-point input math on both platforms. Web/Node Stage 2.2 enforcement is verified via `npm test`; Flutter/Drift execution remains **Unverified** locally pending CI (`flutter analyze` & `flutter test`).

### Calendar & Time Invariants (**Implemented** in Dart & TypeScript)
- **Zone**: Fixed `Africa/Addis_Ababa` (`UTC+3`, `fixedUtcOffsetMinutes: 180`, zero DST).
- **Date-Only vs. Instant**: Civil calendar dates use `YYYY-MM-DD` (`CalendarDate`); timestamps use UTC ISO-8601 (`EthiopiaClock`). Both Projects `startDate`/`targetDate` and tracking record `recordedDate`/`scheduledDate` use canonical `YYYY-MM-DD` rather than UTC-shifted instants, keeping daily outreach totals accurate regardless of Gregorian vs. Ethiopian display formatting.
- **Ethiopian Calendar**: 13 months; 30 days in months 1–12; Pagume 5 days (6 in leap years where `year % 4 == 3`); Julian Day Number anchor `1724221`.

---

## 4. Startup Recovery, Quarantine, Encrypted Backup & Stage 3 Package Boundary

| Mechanism | Status | Verified Implementation Details |
| :--- | :--- | :--- |
| **Clean Empty Startup & Legacy Purge** | **Implemented** | `canonical_seed_database.json` starts empty with `isFinanceSetupCompleted: false`; `KnownSeedIds` / `KNOWN_SEED_IDS` purges legacy demo IDs safely (including `projectTrackingBlocks` / `projectTrackingRecords` tied to seed projects in `SharedStateBridge.purgeKnownSeedData`). |
| **Startup Failure Diagnostic & Recovery Host** | **Implemented** (Flutter execution **Unverified** locally; CI-pending for Stage 3.4.3 / 3.4.4 / v9 additions) | `RawDatabaseRecoveryExporter` classifies `migrationInvariant`, `unsupportedSchemaVersion` (`UnsupportedDatabaseVersionException`), `sqliteCorruption`, and `fileSystemIo`, persists diagnostic JSON atomically, exports verified SHA-256 cold bundles, keeps `.sqlite`/`-wal`/`-shm` intact on failure, blocks blind retries via `!canRetryUpgrade` for corruption and unsupported future schema versions (`AppStateManager.retryInitialize`), and supports copy-back `restoreFromQuarantine` keeping quarantine artifacts intact until every restore-critical invariant passes. |
| **Encrypted `.daywell` Envelope Format & Fail-Closed Header Validation** | **Implemented** (Unit/widget test execution **Unverified** locally for Flutter; Node tests passing for Web; Web UI wiring deferred) | **Algorithm:** PBKDF2-HMAC-SHA256 (`100,000` exact iterations, 16-byte random salt), AES-GCM-256 (12-byte nonce, 16-byte MAC), 64-hex SHA-256 plaintext checksum (`format: 'personal_mgmt_encrypted_backup'`, exact `format_version: 1`, exact `kdf: 'PBKDF2-HMAC-SHA256'`, exact `iterations: 100000` with zero silent default fallbacks). **Flutter** (`EncryptionBackupService.validateAndParseEnvelope` + `BackupView`) validates envelope headers before quarantine confirmation, DB close, or swap, accepts canonical inner schema versions `4..9`, and maps failures to `BackupFailureKind`. **Web** (`src/domain/backupCrypto.ts` `validateBackupEnvelopeHeader` + `decryptDatabaseBackup`) enforces exact envelope/KDF checks and accepts `LocalDatabaseState` `version: 3` only (`BackupValidationError`), while Web `sync_backup` screen remains unencrypted canonical JSON (`SharedStateBridge`). |
| **Snapshot Fidelity, Projects Stage 1 Integration & Restore Rollback** | **Implemented** (Flutter execution **Unverified** locally; Web `SharedStateBridge` v9 tests verified in Node) | All 4 Flutter snapshot/restore entry points (`restoreEncryptedBackupInRecovery`, `restoreFromEncryptedBackup`, `importCanonicalSnapshot`, `DatabasePersistenceCoordinator.importSnapshotDetailed`) share unified DB-free Phase A pre-validation (`validateAndPrepareSnapshot`) across all 24 tables (`Reminders`, `AppSettings`, `ProjectTrackingBlocks`, `ProjectTrackingRecords` included) **before** DB close, clear, or quarantine, serialized by an in-flight `_isRestoreInProgress` guard. Exports sort `projectTrackingRecords` parent-before-child; imports topologically insert parents before children, reject cyclic/missing required parents fail-closed before mutation, sanitize optional dangling `linkedTaskId` with diagnostics (Flutter) / clean strip (Web), and default missing collections on v4–v8 backups to `[]`. Quarantine restore reopens `verifiedDb`, runs `PRAGMA quick_check`, `PRAGMA foreign_key_check`, `V7LedgerHardener.verifyInvariantsOnly`, strict controller rehydration (including `ProjectsController`), and isolates post-commit cleanup warnings cleanly. |
| **Stage 3 Portable Project Package Boundary (`.daywellproject`)** | **Planned** (Not implemented in Stage 1) | Full-database backups (`.daywell` `format_version: 1` and canonical exchange `v4..9`) remain strictly separate from the planned Stage 3 portable single-project package (`.daywellproject`). Stage 1 establishes a JSON-serializable, ID-addressable boundary (Project metadata, `ProjectTrackingBlocks`, ordered `ProjectTrackingRecords` including optional `progress_log` history, and typed `customFields`/`config` maps) with package versioning independent of SQLite `schemaVersion: 9`. File serialization, pickers, import preview, ID remapping on collision, and Android file intents belong to Stage 3. |
| **Analytical Exports (CSV / XLSX / SQL)** | **Partially mirrored** | **Flutter (`FinanceExportService`):** UTF-8 BOM CSV (`\uFEFF` for Amharic/Ge'ez Excel compatibility) + SQL statements tagging excluded/unverified records and filtering `view_cash_flow` to liquid ETB (excluding `receivable` & `savings_vault`). **Web (`DataPortabilityService`):** Multi-sheet `.xlsx` (SheetJS), CSVs, SQLite export, Data Dictionary ZIP (`JSZip`) + SHA-256 manifest preserving native isolated records (`EXCLUDED_<CODE>` / `CURRENCY_REVIEW`) while filtering `Cash_Flow_Ledger` & SQLite `view_cash_flow` strictly to liquid ETB (excluding `receivable` & `savings_vault`). |

---

## 5. Web Preview `localStorage` Key Map (Factual Reference)

- `daywell_canonical_database_v3`: Canonical bridge state synced by `SharedStateBridge`.
- Per-module live keys read/written by Web modules and `WebProjectsRepository`: `daywell_user_profile`, `daywell_finance_setup_completed`, `daywell_accounts`, `daywell_categories`, `daywell_finance_transactions`, `daywell_transactions`, `daywell_journal_entries`, `daywell_postings`, `daywell_parties`, `daywell_debts`, `daywell_settlement_allocations`, `daywell_commitments`, `daywell_commitment_settlements`, `daywell_savings_goals`, `daywell_budgets`, `daywell_recurring_rules`, `daywell_tasks`, `daywell_notes`, `daywell_calendar_events`, `daywell_projects`, `daywell_project_tracking_blocks`, `daywell_project_tracking_records`, `daywell_milestones`, `daywell_goals`, `daywell_inbox_items`, `daywell_reminders`, `daywell_app_settings`.
- `personal_management_offline_db_v1`: Legacy offline store defined in `src/data/localDatabase.ts`.

---

## 6. Backward Compatibility & Versioning Rules ([ADR-007](./decisions/ADR-007-mandatory-backward-compatibility.md))

Daywell strictly separates its version domains so changing one boundary never silently mutates unrelated contracts:

1. **Separated Version Domains:**
   - **Drift Database Schema (`AppDatabase.schemaVersion`):** `9` (v8 -> v9 adds Projects Stage 1 schema).
   - **Shared Foundation Contract (`schema_contracts.json`):** `v2.1.0`, `schemaVersion: 9` (tracks SQLite/domain parity).
   - **Canonical Exchange & Seed Version (`canonical_seed_database.json` / `SharedStateBridge` output):** Remains `schemaVersion: 5` alongside `financeSchemaVersion: 7` (not bumped merely for Stage 1 Projects).
   - **Snapshot Ingest Compatibility Bounds:** Expanded deliberately from `4..8` to `4..9` across `DatabasePersistenceCoordinator`, `EncryptionBackupService`, and `SharedStateBridge.importFromAndroidJson`.
   - **Encrypted `.daywell` Envelope Format:** Remains `format_version: 1` (not incremented for schema v9).
   - **Legacy Web `LocalDatabaseState`:** Remains `version: 3` (unchanged).
2. **Preserve Previously Released Migrations & Backups:** Previously released `AppDatabase.onUpgrade` steps (`from < 2` through `from < 9`, verified sequentially ascending in `app_database.dart`) and previously released `.daywell` backup formats (`format_version: 1`) remain supported until retired by an explicit, approved deprecation decision (no arbitrary rolling cutoff). Static AST/token enforcement via `npm run check-migrations` ([`scripts/check_migration_compatibility.mjs`](../../scripts/check_migration_compatibility.mjs) and [`scripts/migration_compatibility_baseline.json`](../../scripts/migration_compatibility_baseline.json)) verifies monotonic `schemaVersion >= 9`, explicit `if (from > to) { throw ...; }` fail-closed guard at the top of `onUpgrade` (and absence of nonexistent Drift `onDowngrade`), preserved ascending `from < 2..9` branches, required delegate classes (`V6LedgerMigrator`, `V7LedgerHardener`), and prohibition of `fallbackToDestructiveMigration` (**runtime SQLite migration execution remains CI/Flutter-only and Unverified locally**).
3. **Forward Database Migration Standards (`v9` Baseline -> `v10+`):**
   - `AppDatabase.schemaVersion => 9` is the current baseline from which all future schema increments (`v10+`) must guarantee non-destructive upgrades and user data preservation.
   - All future `onUpgrade` steps (`from < 10`, ...) must remain incremental (`if (from < N)` in ascending order), deterministic, idempotent when reopened at the target `user_version`, and free of destructive table drops or data resets.
   - Failed migrations must roll back atomically leaving the prior `PRAGMA user_version`, schema, and user rows intact; unsupported future schemas (`from > to`) must fail closed with `UnsupportedDatabaseVersionException` / `DatabaseFailureCategory.unsupportedSchemaVersion` without deleting or overwriting user database files or allowing blind retries.
4. **No Blanket Historical Rewrite:** Existing historical migrations (`from < 2` through `from < 8`) and untouched historical defects are evaluated on touch or when posing material data-integrity or functionality risks rather than through unrequested blanket retroactive rewrites.
