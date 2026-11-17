# Daywell — Governance Stage 3.4.4 Revised Implementation Plan: Snapshot Fidelity, Reminders, Settings & Restore Integrity

> **Status:** Planning-only revision (`Plan action: revise`). No source, test, foundation, or documentation files have been edited.  
> **Governing Authorities:** `PROJECT_CONSTITUTION.md` (§2.5, §2.6, §2.11), `ADR-003` (Finance Ledger Invariants), `ADR-007` (Mandatory Backward Compatibility), `docs/architecture/data-and-persistence.md`, `docs/architecture/shared-foundation.md`, `docs/architecture/cross-platform-parity.md`.  
> **Preserved Version & Compatibility Boundaries:** Drift `schemaVersion => 7`, Canonical Exchange `schemaVersion: 5`, Finance `financeSchemaVersion: 7`, encrypted `.daywell` `format_version: 1`, Web `LocalDatabaseState` `version: 3`, PBKDF2 (100,000 iterations) / AES-GCM-256 cryptography, and all historical `AppDatabase.onUpgrade` branches (`from < 2..7`) remain unchanged. Legacy `importSnapshot` signature `Future<void> importSnapshot(...)` referenced by `src/domain/batch10Stage2Consolidation.test.ts` is also preserved alongside `importSnapshotDetailed(...)`.

---

## 1. Verified Relationship Classification (All 22 Drift Tables + SQLite Unique Constraints)

Every persisted relationship across all 22 tables in `/flutter_app/lib/data/database/tables.dart` and unique indexes in `/flutter_app/lib/data/database/app_database.dart` (`lines 715–729`, with `PRAGMA foreign_keys = ON` active) is classified directly from the live schema and repository contracts into four tiers:

### Tier 1 — Required Database Foreign Keys (`NOT NULL` `.references(...)` in `tables.dart`)
Missing/null/empty IDs or references to non-existent parents **fail closed pre-transaction** (`BackupValidationException(BackupFailureKind.invalidPayload, ...)`), with **zero** silent row drops and **zero** synthetic parent fabrication:

| Child Table & Column | Target Table & Column | SQLite `onDelete` | Import Rule |
| :--- | :--- | :--- | :--- |
| `Milestones.projectId` | `Projects.id` | `cascade` | Reject if missing/null or absent from `projects` (or live DB when `clearExisting: false`). |
| `FinancialTransactions.categoryId` | `FinancialCategories.id` | `restrict` | **Strict contract rule below** — never fabricate arbitrary missing categories. |
| `CommitmentSettlementsTable.commitmentId` | `FinancialCommitments.id` | `restrict` | Reject if missing or absent from `commitments` / live DB. |
| `CommitmentSettlementsTable.entryId` | `JournalEntriesTable.id` | `restrict` | Reject if missing or absent from `journalEntries` / live DB. |
| `PostingsTable.entryId` | `JournalEntriesTable.id` | `restrict` | Reject if missing or absent from `journalEntries` / live DB. |
| `PostingsTable.accountId` | `AccountsTable.id` | `restrict` | Reject if missing or absent from `accounts` / live DB (note: system control accounts like `acc-sys-*` are auto-seeded during import and valid targets). |
| `DebtsTable.originEntryId` | `JournalEntriesTable.id` | `restrict` | Reject if missing or absent from `journalEntries` / live DB. |
| `DebtsTable.partyId` | `PartiesTable.id` | `restrict` | Reject if missing or absent from `parties` / live DB. |
| `SettlementAllocationsTable.settlementEntryId` | `JournalEntriesTable.id` | `restrict` | Reject if missing or absent from `journalEntries` / live DB. |
| `SettlementAllocationsTable.debtId` | `DebtsTable.id` | `restrict` | Reject if missing or absent from `debts` / live DB. |
| `BudgetsTable.categoryId` | `FinancialCategories.id` | `restrict` | Reject if missing or absent from `categories` / live DB. |

#### Explicit Contract Resolution for `FinancialTransactions.categoryId`
- **Live Contract Tension Verified:**
  - `tables.dart:159-160` defines `FinancialTransactions.categoryId` as `NOT NULL` with `.references(FinancialCategories, #id, onDelete: KeyAction.restrict)` (enforced by SQLite `PRAGMA foreign_keys = ON`).
  - `schema_contracts.json:112` declares `Transaction.categoryId` as `required: false` (because `type: "transfer"` conceptually carries no income/expense category — see `finance_repository.dart:974` — and cross-platform Web `SharedTransaction` payloads may omit `categoryId`).
  - Currently, `database_persistence_coordinator.dart:876-891` silently defaults missing `categoryId` AND fabricates arbitrary missing categories (`cat-*` inserted into `financial_categories`).
- **Stage 3.4.4 Rule:**
  1. Remove arbitrary category synthesis (`lines 878–891`) completely.
  2. Whenever a transaction explicitly provides a non-empty `categoryId` that does **not** exist in imported `categories` (or live DB when `clearExisting: false`), **fail closed** with `BackupValidationException(BackupFailureKind.invalidPayload, ...)`.
  3. If `categoryId` is omitted or `null`:
     - For `snapshotVersion >= 7` non-transfer rows (`income` / `expense`), **fail closed** (`categoryId` is required).
     - For `type == 'transfer'` or legacy cross-platform `snapshotVersion < 7` snapshots omitting `categoryId`, resolve to the canonical starter category (`'cat-other-inc'` for income, `'cat-other-exp'` for expense/transfer) **only if** that canonical starter category exists in the target database/snapshot (or is seeded strictly from `CanonicalSeedDatabase` starter categories with explicit warning `LEGACY_TRANSACTION_DEFAULT_CATEGORY_APPLIED`) — never synthesizing custom user categories.

### Tier 2 — Nullable Database Foreign Keys (`.nullable().references(...)` in `tables.dart`)
Because the schema declares these nullable, dangling/non-existent targets or self-reference cycles are **warn-cleared to `null`** with structured `SnapshotImportDiagnostic` warnings (never dropping the parent/child row):

| Child Table & Column | Target Table & Column | SQLite `onDelete` | Warning Code on Clear |
| :--- | :--- | :--- | :--- |
| `Projects.goalId` | `Goals.id` | `setNull` | `ORPHANED_PROJECT_GOAL_CLEARED` |
| `Tasks.projectId` | `Projects.id` | `setNull` | `ORPHANED_TASK_PROJECT_CLEARED` |
| `Tasks.milestoneId` | `Milestones.id` | `setNull` | `ORPHANED_TASK_MILESTONE_CLEARED` |
| `Notes.projectId` | `Projects.id` | `setNull` | `ORPHANED_NOTE_PROJECT_CLEARED` |
| `Notes.goalId` | `Goals.id` | `setNull` | `ORPHANED_NOTE_GOAL_CLEARED` |
| `FinancialCategories.parentId` | `FinancialCategories.id` | `restrict` | `ORPHANED_CATEGORY_PARENT_CLEARED` (also breaks self/cycle links) |
| `FinancialCommitments.linkedAccountId` | `AccountsTable.id` | `restrict` | `ORPHANED_COMMITMENT_ACCOUNT_CLEARED` |
| `FinancialCommitments.categoryId` | `FinancialCategories.id` | `restrict` | `ORPHANED_COMMITMENT_CATEGORY_CLEARED` |
| `FinancialCommitments.linkedDebtId` | `DebtsTable.id` | `restrict` | `ORPHANED_COMMITMENT_DEBT_CLEARED` |
| `FinancialCommitments.settlementEntryId` | `JournalEntriesTable.id` | `restrict` | `ORPHANED_COMMITMENT_ENTRY_CLEARED` |
| `FinancialCommitments.recurringRuleId` | `RecurringRulesTable.id` | `restrict` | `ORPHANED_RECURRING_RULE_LINK_CLEARED` |
| `SavingsGoals.linkedAccountId` | `AccountsTable.id` | `restrict` | `ORPHANED_SAVINGS_ACCOUNT_CLEARED` |
| `JournalEntriesTable.correctedFromEntryId` | `JournalEntriesTable.id` | `restrict` | `ORPHANED_CORRECTED_ENTRY_CLEARED` (also breaks self/cycle links) |
| `DebtsTable.writeOffEntryId` | `JournalEntriesTable.id` | `restrict` | `ORPHANED_DEBT_WRITEOFF_ENTRY_CLEARED` |
| `RecurringRulesTable.accountId` | `AccountsTable.id` | `restrict` | `ORPHANED_RULE_ACCOUNT_CLEARED` |
| `RecurringRulesTable.destinationAccountId` | `AccountsTable.id` | `restrict` | `ORPHANED_RULE_DESTINATION_CLEARED` |
| `RecurringRulesTable.categoryId` | `FinancialCategories.id` | `restrict` | `ORPHANED_RULE_CATEGORY_CLEARED` |
| `RecurringRulesTable.linkedDebtId` | `DebtsTable.id` | `restrict` | `ORPHANED_RULE_DEBT_CLEARED` |
| `PostingsTable.categoryId` | `FinancialCategories.id` | `restrict` | `ORPHANED_POSTING_CATEGORY_CLEARED` |

### Tier 3 — Optional Soft Relationships Not Enforced by SQLite
Columns without `.references(...)` declarations in `tables.dart`:

| Table & Column | Relationship Semantics | Stage 3.4.4 Handling |
| :--- | :--- | :--- |
| `FinancialTransactions.accountId` | Nullable soft ref to `AccountsTable.id` | Warn-clear to `null` (`ORPHANED_TRANSACTION_ACCOUNT_CLEARED`) if non-null and missing from `accounts` / live DB. *(Pre-v6 migration may still safely offset missing posting accounts to `acc-sys-legacy-offset`.)* |
| `FinancialTransactions.destinationAccountId` | Nullable soft ref to `AccountsTable.id` | Warn-clear to `null` (`ORPHANED_TRANSACTION_DESTINATION_CLEARED`) if non-null and missing. |
| `FinancialTransactions.correctedFromId` | Nullable self soft ref to `FinancialTransactions.id` | Warn-clear to `null` (`ORPHANED_TRANSACTION_CORRECTION_CLEARED`) if self-referencing or missing. |
| `JournalEntriesTable.legacySourceTxId` | Nullable audit/provenance tag (`tx-*`, `open:<accId>`, `open:<accId>:rev:n`) | Preserve valid string values untouched; enforce partial uniqueness in pre-validation because `idx_journal_legacy_source` is `UNIQUE WHERE legacy_source_tx_id IS NOT NULL` (`app_database.dart:715`). |
| `Reminders.targetId` + `Reminders.targetType` | Polymorphic soft link (`NOT NULL` in SQLite, zero SQLite FK) | For `targetType` in `{'task', 'commitment', 'calendar_event', 'note'}`: require non-empty `targetId` and verify existence in the matching entity table (or live DB on `clearExisting: false`). If target does not exist, skip inserting the dangling reminder with explicit warning `ORPHANED_REMINDER_SKIPPED`. For `targetType == 'custom'`: no entity lookup required (`targetId` defaults safely if omitted by Web fixtures, never skipped). |

### Tier 4 — Standalone Root Tables (No Foreign Key Dependencies)
- `InboxItems`
- `Goals`
- `CalendarEvents`
- `AppSettings` (keyed by `key`)
- `AccountsTable`
- `PartiesTable`

### Additional SQLite Unique Constraints Enforced Pre-Transaction
From `app_database.dart:715–729`:
1. `BudgetsTable`: Composite unique index `idx_budgets_month_category` on `(month_iso, category_id)`. Duplicate `(monthIso, categoryId)` pairs within `budgets` must fail pre-validation cleanly.
2. `JournalEntriesTable`: Partial unique index `idx_journal_legacy_source` on `legacy_source_tx_id WHERE legacy_source_tx_id IS NOT NULL`. Duplicate non-null `legacySourceTxId` values must fail pre-validation cleanly.

---

## 2. Per-Table Duplicate-ID Rules

- **Strict Per-Table Primary-Key Scope:**
  - Each of the 21 `id`-keyed collections maintains its own independent `seenIds` set during pre-validation; `appSettings` maintains its own `seenKeys` set (`key`).
  - Reusing the same ID across **different** tables (e.g., an `Account`, a `Goal`, a `Commitment`, and a `Reminder` all using ID `'item-1'` or a shared deterministic UUID) is completely legal in SQLite and **MUST be allowed**.
  - Duplicate primary keys **within the same table** abort pre-validation fail-closed with `BackupValidationException(BackupFailureKind.invalidPayload, 'Duplicate primary key "<id>" in "<table>" at index <i/>.')`.
- **Legacy v4 `goals` Shape Compatibility:**
  - `database_persistence_coordinator.dart:643` skips `goals` items that are actually legacy savings goals (`containsKey('targetCents') && !containsKey('status')`) so they migrate into `savingsGoals`.
  - Pre-validation applies that exact partition **before** tracking `goals` vs. `savingsGoals` `seenIds` so valid legacy v4 exports do not trigger false duplicate-ID or missing-field rejections.
- **Per-Table Composite / Partial Uniqueness:**
  - `budgets`: track `seenMonthCategory = <(String monthIso, String categoryId)>{}` and fail closed on duplicates.
  - `journalEntries`: track `seenLegacySourceTxIds = <String>{}` across non-null `legacySourceTxId` values and fail closed on duplicates.

---

## 3. Complete `Reminder` and `AppSetting` Contract Proposals

### Verified Persisted Schema Audit
1. **Drift `Reminders` (`tables.dart:252–262`):** Exactly 6 columns:
   - `id` (`TextColumn`, PK)
   - `targetId` (`TextColumn`, non-null)
   - `targetType` (`TextColumn`, non-null — e.g., `'task'`, `'commitment'`, `'calendar_event'`, `'custom'`)
   - `triggerTimeUtc` (`DateTimeColumn`, non-null)
   - `isActive` (`BoolColumn`, default `true`)
   - `createdAt` (`DateTimeColumn`, non-null)
2. **Web `LocalReminder` (`src/domain/backupTypes.ts:111–120`):** Has `id`, optional `targetId?` (omitted on `'custom'` seed `'rem-3'` in `localDatabase.ts:297`), `targetType` (`'task' | 'commitment' | 'custom' | 'note'`), `title`, `triggerTimeUtc`, `isActive`, optional `channelId?`, `createdAtUtc`.
3. **Drift `AppSettings` (`tables.dart:265–273`):** Exactly 3 columns:
   - `key` (`TextColumn`, PK)
   - `value` (`TextColumn`, non-null)
   - `updatedAt` (`DateTimeColumn`, non-null)

### Additive Shared Foundation Contract Additions (`/shared_foundation/schema_contracts.json`, `ADR-007` Compliant)
- **`Reminder`:**
  - `id` (`string`, `required: true`)
  - `targetId` (`string`, `required: true` in canonical contract; Web export synthesizes `r.targetId || (r.targetType === 'custom' ? r.id : '')`, while Drift pre-validation accepts omitted `targetId` only when `targetType == 'custom'` by normalizing to `'custom:<id>'` or `id`, and rejects missing `targetId` for entity-targeted types)
  - `targetType` (`string`, `enum: ["task", "commitment", "calendar_event", "note", "custom"]`, `required: true`)
  - `triggerTimeUtc` (`string`, `format: "date-time"`, `required: true`)
  - `isActive` (`boolean`, `default: true`)
  - `createdAt` (`string`, `format: "date-time"`, `required: true`)
  - `title` (`string`, `required: false` — preserves Web `LocalReminder.title` across Web/cross-platform round-trips without altering Drift's 6-column table)
  - `channelId` (`string`, `required: false` — preserves Web `LocalReminder.channelId` cleanly)
- **`AppSetting`:**
  - `key` (`string`, `required: true`)
  - `value` (`string`, `required: true`)
  - `updatedAt` (`string`, `format: "date-time"`, `required: false` — exported deterministically in UTC ISO-8601 by Drift & Web; optional on import with current UTC fallback if omitted)
- **`SharedDatabaseState` (generated in `src/domain/sharedFoundation.ts` & `flutter_app/lib/core/shared_foundation_core.dart`):**
  - Add optional properties `reminders?: SharedReminder[]` and `appSettings?: SharedAppSetting[]` so all pre-3.4.4 fixtures and `canonical_seed_database.json` remain 100% valid (`canonical_seed_database.json` untouched).
  - Update `scripts/foundation_compatibility_baseline.json` additively to protect `Reminder` and `AppSetting` contracts alongside existing entities.

### Complete Application Settings Classification Policy (`app_settings_policy.dart`)
| Category | Persisted Keys Verified in Codebase | Export Behavior | Import Behavior |
| :--- | :--- | :--- | :--- |
| **User-Owned Settings (`appSettings` array)** | `calendar_display_mode` (`app_database.dart:619`), `default_currency` (`app_database.dart:627`), `calendar_preference` (`tables.dart:267`), plus any non-excluded custom `app_settings` keys (and Web `daywell_finance_planning_horizon` / `daywell_user_profile` where bridged into `daywell_app_settings`) | Exported in `appSettings`, sorted deterministically by `key` with `key`, `value`, `updatedAt`. | If `'appSettings'` key is **present** & `clearExisting`: delete existing non-excluded `app_settings` rows and insert validated entries cleanly. If `'appSettings'` is **omitted**: preserve existing user-owned `app_settings` rows untouched + record `LEGACY_APP_SETTINGS_OMITTED`. |
| **Top-Level Typed Ledger Settings** | `opening_balance_cents` (`AppDatabase.openingBalanceKey`), `is_finance_setup_completed` (`AppDatabase.financeSetupKey`), `ledger_migration_report_v7` (`V7LedgerHardener.v7ReportKey`) | Exported exclusively as typed root snapshot fields (`openingBalanceCents`, `isFinanceSetupCompleted`, `ledgerMigrationReportV7`) — omitted from `appSettings` array to prevent dual-source conflicts. | Validated strictly at root (`int`, `bool`, `String?`). On clean `v7+` replace when `ledgerMigrationReportV7` is omitted/null, clear any stale `ledger_migration_report_v7` row rather than leaving old DB diagnostics behind. |
| **Excluded Internal Sentinels & Secret / Credential / Transient / Device-Bound Keys** | `initial_seed_completed` (`AppDatabase.seedSentinelKey`), `ledger_v6_migrated_at` (`V6LedgerMigrator.v6MigratedSentinelKey`), plus prefixes/keys `secret_`, `token_`, `auth_`, `passphrase_`, `device_`, `push_token`, `local_cache_`, `transient_` (and `ISecureStorageService` hardware secrets) | **Never** exported into snapshots or `.daywell` backups. | Protected on import: `initial_seed_completed` set to `'true'`; `ledger_v6_migrated_at` cleared on replace before conditional `< 6` migration; any excluded/secret/top-level key injected inside incoming `appSettings` is skipped with diagnostic warning (`EXCLUDED_APP_SETTING_SKIPPED`), never overwriting local sentinels or device credentials. |

- **Strict Settings Failure Safety:** Malformed `'appSettings'` entries (non-list, non-object element, empty/non-string `key`, non-string `value`, duplicate `key`, unparseable `updatedAt`) or malformed optional root fields (`openingBalanceCents` non-int, `isFinanceSetupCompleted` non-bool, `ledgerMigrationReportV7` non-string) **always fail closed pre-transaction**, leaving existing `app_settings` untouched.

---

## 4. Unified Pre-Validation Architecture (Single Path Across All 4 Entry Points)

All backup/snapshot restore entry points route through **one shared validation & preparation pipeline** on `DatabasePersistenceCoordinator`:

```
  1. restoreEncryptedBackupInRecovery / Detailed (AppStateManager)
  2. restoreFromEncryptedBackup / Detailed         (AppStateManager)
  3. importCanonicalSnapshot / Detailed            (AppStateManager)
  4. importSnapshot / importSnapshotDetailed       (DatabasePersistenceCoordinator)
         │
         ▼
  [Phase A — DB-Free Structural, Scalar, Schema & Version Validation]
    • validateCanonicalSnapshot(decoded, expectedHeaderVersion: ...)
    • Type-safe scalar/date/timestamp/JSON extraction across all 22 tables + top-level settings
    • Per-table duplicate-PK checks + budgets (monthIso, categoryId) + journal legacySourceTxId checks
    • Intra-snapshot Tier 1 required FK validation (when clearExisting: true, 100% self-contained without DB!)
    • Normalization plan for Tier 2 nullable FKs, Tier 3 soft links & reminders, and structured SnapshotImportDiagnostics
         │
         ├── For clearExisting: false (incremental import inside importSnapshotDetailed):
         │   Supplement missing parent ID lookups from live DB BEFORE any write begins.
         │
         ▼
  [Only if Phase A succeeds:]
    • Entry points (1) & (2 with _canRebuildDatabase): proceed to _closeDbSafely -> quarantineLiveDatabaseFiles -> freshDb -> Phase B
    • Entry points (2 without _canRebuildDatabase), (3), (4): execute Phase B in single _db.transaction(...)
```

### Shared Pipeline API Design
- Add pure value types in `/flutter_app/lib/core/interfaces/platform_service_interfaces.dart`:
  - `SnapshotDiagnosticSeverity { info, warning }`
  - `SnapshotImportDiagnostic { code, message, table, recordId, field, severity }`
  - `SnapshotImportReport { warnings, diagnostics, restoredRecordCounts }`
  - Extend `BackupRestoreResult` backward-compatibly with optional `warnings` (`List<String>`, default `const []`) and `diagnostics` (`List<SnapshotImportDiagnostic>`, default `const []`).
- Add `PreparedSnapshotImport` (typed normalized records across all 22 tables + prepared settings + pre-write `diagnostics`) and `DatabasePersistenceCoordinator.validateAndPrepareSnapshot(...)`:
  - Entry point `1` (`restoreEncryptedBackupInRecovery[Detailed]`) and `2` (`restoreFromEncryptedBackup[Detailed]`) execute envelope check -> decryption -> JSON map check -> `DatabasePersistenceCoordinator.validateAndPrepareSnapshot(decoded, expectedHeaderVersion: validatedEnvelope.schemaVersion)` **before closing active `_db` or calling `quarantineLiveDatabaseFiles()`**.
  - Entry point `3` (`importCanonicalSnapshot[Detailed]`) and `4` (`importSnapshot` / `importSnapshotDetailed`) execute the exact same `validateAndPrepareSnapshot` before opening the write transaction (or reuse the already-prepared `PreparedSnapshotImport` via an internal/optional parameter so validation is never duplicated or skipped).
  - Preserve `Future<void> importSnapshot(Map<String, dynamic> stateMap, {bool clearExisting = true})` delegating to `importSnapshotDetailed(...)` so `src/domain/batch10Stage2Consolidation.test.ts:247` stays green.

---

## 5. Required & Optional Relationship Handling

1. **Zero Unsafe Casts / Zero Silent Fallbacks:**
   - Replace every unchecked `as String` / `as int?` / `as bool?` / `as List` in `database_persistence_coordinator.dart` with typed helper extractors (`_reqString`, `_optString`, `_reqInt`, `_optInt`, `_reqBool`, `_optBool`, `_reqInstantUtc`, `_optInstantUtc`, `_reqDate`, `_optDate`, `_optStringList`, `_optJsonList`) that include exact context `'<collection>[<index>].<field>'` and throw `BackupValidationException(BackupFailureKind.invalidPayload, ...)`.
   - Enforce domain bounds pre-transaction: positive `amountCents > 0` for `postings`, `commitmentSettlements`, `budgets.limitCents`, `recurringRules.amountCents`, `recurringRules.interval >= 1`; valid `YYYY-MM` for `budgets.monthIso`; valid `calendarEvents.endDateIso >= dateIso`; non-empty required names/titles/rawText/values (respecting only documented optional defaults from `schema_contracts.json` such as `status`, `priority`, `direction`, `isArchived`, `isProcessed`, `createdAt`).
2. **Tier 1 Required FK Rejections (Zero Silent Drops):**
   - Reject pre-transaction if any required parent ID in `milestones.projectId`, `transactions.categoryId` (subject to the Section 1 contract rule), `postings.entryId`/`accountId`, `debts.originEntryId`/`partyId`, `settlementAllocations.settlementEntryId`/`debtId`, `budgets.categoryId`, or `commitmentSettlements.commitmentId`/`entryId` is missing. Remove all silent `continue;` branches (`lines 704, 963, 996, 1039, 1103, 1236`).
3. **Tier 2 Nullable FK & Cycle Clear-with-Warning:**
   - Topologically sort `financialCategories` (`parentId`) and `journalEntries` (`correctedFromEntryId`) via cycle-safe sort; clear missing or cyclic `parentId`/`correctedFromEntryId` and any missing Tier 2 nullable FKs (`projects.goalId`, `tasks.projectId/milestoneId`, `notes.projectId/goalId`, `postings.categoryId`, `debts.writeOffEntryId`, `savingsGoals.linkedAccountId`, `recurringRules.*`, `financialCommitments.*`) to `null`, emitting a structured `SnapshotImportDiagnostic(severity: warning, code: ...)` for every cleared link.
4. **Tier 3 Reminders & Legacy Omission Rules:**
   - When `'reminders'` is supplied: verify each reminder row cleanly; if `targetType` is `'task' | 'commitment' | 'calendar_event' | 'note'` and `targetId` does not exist in imported targets (or live DB when `clearExisting: false`), skip inserting the reminder and emit `SnapshotImportDiagnostic(severity: warning, code: 'ORPHANED_REMINDER_SKIPPED', table: 'reminders', recordId: id, field: 'targetId')`. Persist all valid active & inactive reminders with exact `triggerTimeUtc`, `isActive`, `createdAt`.
   - When `'reminders'` is omitted (`clearExisting: true`): clear `_db.reminders` cleanly and emit `LEGACY_REMINDERS_OMITTED` (`info` severity).
   - When `'appSettings'` is omitted (`clearExisting: true`): preserve existing user-owned `app_settings` rows untouched and emit `LEGACY_APP_SETTINGS_OMITTED` (`info` severity); clear stale `ledger_migration_report_v7` on clean `v7+` replace when `ledgerMigrationReportV7` is omitted.
5. **Transaction-End SQLite Check:**
   - Before committing the SQLite write transaction in `importSnapshotDetailed`, execute `PRAGMA foreign_key_check` explicitly inside the transaction; if any violation row exists, throw `BackupValidationException(BackupFailureKind.databaseImportFailure, ...)` to trigger automatic SQLite rollback.

---

## 6. Safe Database Rollback & Quarantine Restoration Sequence

Currently, `RawDatabaseRecoveryExporter.restoreFromQuarantine` (`raw_database_recovery_exporter.dart:576–596`) moves files out of `recovery_quarantine/` and deletes the quarantine directory, while `AppStateManager.restoreEncryptedBackupInRecovery` (`app_state.dart:769–773`) deletes quarantine before reopening SQLite, rebinding controllers, or rehydrating controllers.

### Stage 3.4.4 Hardened `RawDatabaseRecoveryExporter.restoreFromQuarantine`
- Keep `_candidateDatabaseFiles(mainFile.path)` covering `.sqlite`, `-wal`, and `-shm`.
- Update `restoreFromQuarantine(QuarantineResult quarantine)` to:
  1. Delete any partial live `.sqlite`, `-wal`, and `-shm` at live paths (caller MUST have already closed every DB connection).
  2. **Copy** quarantined files back to their original paths (`quarantined.copy(entry.key)`) instead of destructive `rename`/delete, so the quarantine backup remains intact on disk if rollback encounters I/O errors or subsequent inspection is needed.

### Stage 3.4.4 8-Step Recovery & Rollback Sequence in `AppStateManager.restoreEncryptedBackupInRecovery`
Before quarantine creation: snapshot `final wasInitializedBeforeRestore = _isInitialized && !_dbClosed;` and finish Phase A validation cleanly.
After `quarantine = await _recoveryExporter.quarantineLiveDatabaseFiles()`, execute:
1. Open `freshDb`, `ensureInitialized()`, `importSnapshotDetailed(...)`.
2. Close `freshDb` (`await _closeDbSafely(freshDb)`) so all dirty WAL frames checkpoint/flush and disk files settle cleanly (when `_canRebuildDatabase`).
3. Reopen `verifiedDb = builder()`, `await verifiedDb.ensureInitialized()`, verify `PRAGMA quick_check` returns `'ok'`, verify `PRAGMA foreign_key_check` is empty, and run `V7LedgerHardener.verifyInvariantsOnly(verifiedDb)`.
4. Rebind & rehydrate while **quarantine is still intact on disk**:
   - `await _rebindDatabase(verifiedDb)`
   - `await _rehydrateAllControllersStrict()` (wrapping `loadAll`/`loadNotes`/`loadItems` so any controller error thrown or captured into `.errorMessage` during restore bubbles cleanly as a failure rather than hiding partial hydration!)
   - Run `await _processDueRecurringRulesStrict()` (so DB-mutating due rule generation completes and is verified before quarantine removal).

If **any error** occurs across steps 1–4, execute this exact ordered rollback:
1. **Cancel active stream watchers:** `await inboxController.disposeAsync()` (if controllers were already bound to `freshDb`/`verifiedDb`).
2. **Detach controllers/listeners:** `_disposeControllersOnly()` so zero listeners or controllers continue dispatching against the failed DB.
3. **Close every candidate DB connection & await completion:** Close `verifiedDb` (if open) AND `freshDb` (if open and distinct) via `await _closeDbSafely(...)`, setting `_dbClosed = true` and preventing any controller/repository from reading `.sqlite`/`-wal`/`-shm`.
4. **Preserve quarantine artifacts:** Do **not** call `deleteQuarantine(quarantine)`; leave the quarantine copy on disk alongside diagnostics for safety.
5. **Restore original DB + WAL/SHM safely:** `await _recoveryExporter.restoreFromQuarantine(quarantine)` restores `.sqlite` and any original `-wal` / `-shm` sidecar files atomically.
6. **Restore prior DB/AppState cleanly according to pre-restore health:**
   - **If `wasInitializedBeforeRestore == true` (healthy in-app `.daywell` restore failed mid-way):** Reopen original DB (`restoredOrigDb = builder(); await restoredOrigDb.ensureInitialized()`), rebind `_rebindDatabase(restoredOrigDb)`, rehydrate all controllers cleanly, and restart `inboxController.startWatchingUnprocessed()` so the user's pre-restore app session remains functional. (If reopening even the restored original DB fails, classify the error, persist failure diagnostics atomically, set `_isInitialized = false`, `_dbClosed = true`.)
   - **If `wasInitializedBeforeRestore == false` (recovery-mode restore from corrupt/unopenable startup DB failed):** Do **not** reopen the known-corrupt original DB into live controllers; keep `_dbClosed = true`, `_isInitialized = false`, preserve existing `_startupFailure` and `migration_last_failure.json` diagnostic state.
7. **Preserve recovery & backup diagnostics:** Populate `_lastBackupResult = BackupRestoreResult.failure(classified.kind, '${classified.message} Original database was restored from quarantine.')`, keeping `quarantineDirectoryPath` intact.
8. **Notify UI cleanly** (`notifyListeners()`) and rethrow `classified` (or return `BackupRestoreResult.failure` in the `Detailed` wrapper).

---

## 7. Restore-Critical vs. Best-Effort Post-Commit Boundary

`await _recoveryExporter.deleteQuarantine(quarantine)` and `await _recoveryExporter.clearFailureDiagnostic()` execute **strictly at the boundary** between these two groups:

| Phase | Operations | Failure Policy |
| :--- | :--- | :--- |
| **Restore-Critical (Gates `deleteQuarantine`)** | 1. Phase A fail-closed structural, type, scalar, PK, unique-index & FK pre-validation<br>2. Atomic `importSnapshotDetailed` + transaction-end `PRAGMA foreign_key_check`<br>3. Disk close `freshDb` + reopen `verifiedDb` + `ensureInitialized()`<br>4. `PRAGMA quick_check == 'ok'`, `PRAGMA foreign_key_check` empty, `V7LedgerHardener.verifyInvariantsOnly`<br>5. `_rebindDatabase(verifiedDb)` + `_rehydrateAllControllersStrict()` (zero controller load errors)<br>6. `_processDueRecurringRulesStrict()` (authoritative DB rule execution before quarantine deletion) | **Any failure triggers the full 8-step rollback** in Section 6, leaves quarantine intact, and marks restore failed. |
| **Quarantine Cleanup & State Flip** | `_recoveryExporter.deleteQuarantine(quarantine)` -> `_recoveryExporter.clearFailureDiagnostic()` -> reset `_startupFailure = null`, `_isInitialized = true`, set `_lastBackupResult = BackupRestoreResult.success(..., warnings, diagnostics)` | Only runs once every restore-critical invariant has passed on reopened SQLite & hydrated controllers. |
| **Best-Effort Post-Commit (After `deleteQuarantine`)** | 1. `inboxController.startWatchingUnprocessed()`<br>2. `_scheduledCommitmentReminders.clear()` + `syncFinanceDueReminders()` (`INotificationService.initialize` & `scheduleReminder` calls for due commitments / active reminders)<br>3. UI `notifyListeners()` | Guarded safely so missing OS notification plugin bindings, permission denials, or background stream hiccups log/attach info warnings without rolling back the already-verified restored database. |

---

## 8. Exact Expected Files to Change (Upon Approval)

1. **`/shared_foundation/schema_contracts.json`** — Add `Reminder` and `AppSetting` entity contracts.
2. **`/scripts/sync_foundation.mjs`** — Extend TypeScript/Dart schema generation (`SharedReminder`, `SharedAppSetting`, optional `reminders?` & `appSettings?` on `SharedDatabaseState`).
3. **`/scripts/foundation_compatibility_baseline.json`** — Add `Reminder` and `AppSetting` to `protectedSchemaContracts`.
4. **Generated via `npm run sync-foundation` (never manually edited):**
   - `/src/domain/sharedFoundation.ts`
   - `/flutter_app/lib/core/shared_foundation_core.dart`
   - `/flutter_app/lib/core/shared_foundation.dart`
5. **`/flutter_app/lib/core/interfaces/platform_service_interfaces.dart`** — Add `SnapshotDiagnosticSeverity`, `SnapshotImportDiagnostic`, `SnapshotImportReport`, and optional backward-compatible `warnings` / `diagnostics` fields on `BackupRestoreResult`.
6. **`/flutter_app/lib/data/database/app_settings_policy.dart`** *(new)* — Centralize `AppSettingsBackupPolicy` (user-owned allowlist, top-level managed finance/ledger keys, excluded internal sentinels, and secret/credential/transient/device-bound exclusion rules).
7. **`/flutter_app/lib/data/database/database_persistence_coordinator.dart`** — Export `reminders` & exportable `appSettings`; implement unified `validateAndPrepareSnapshot`, strict typed field extractors, per-table duplicate-PK/unique-index checks, Tier 1–4 relationship enforcement (zero arbitrary category fabrication, zero silent drops), `importSnapshotDetailed`, legacy `importSnapshot` delegate, and pre-commit `PRAGMA foreign_key_check`.
8. **`/flutter_app/lib/data/database/raw_database_recovery_exporter.dart`** — Harden `restoreFromQuarantine` to copy-back quarantined `.sqlite`, `-wal`, and `-shm` safely while preserving quarantine artifacts during rollback.
9. **`/flutter_app/lib/ui/app_state.dart`** — Route all 4 restore/import entry points through `validateAndPrepareSnapshot`; implement full Section 6–7 disk close/reopen verification, strict controller rehydration, hardened 8-step rollback, deferred `deleteQuarantine`, best-effort post-commit notification/watcher wiring, and diagnostic warning propagation to `BackupRestoreResult`.
10. **`/flutter_app/lib/ui/screens/backup_view.dart`** — Minimal feedback copy refinement when `result.warnings.isNotEmpty`.
11. **`/src/services/sharedStateBridge.ts`** — Add `'reminders'` and `'appSettings'` to `OPTIONAL_ARRAY_COLLECTIONS`, `REMINDERS_STORAGE_KEY = 'daywell_reminders'`, `APP_SETTINGS_STORAGE_KEY = 'daywell_app_settings'`, fail-closed validation (respecting settings exclusion rules), and full preserve/round-trip across `assembleLiveDatabaseState`, `saveCanonicalState`, and `importFromAndroidJson`.
12. **Tests:**
    - `/flutter_app/test/stage344_snapshot_fidelity_restore_test.dart` *(new)*
    - `/src/domain/sharedStateBridge.test.ts` *(extended)*
13. **Same-Stage Architecture Documentation:**
    - `/docs/architecture/data-and-persistence.md`
    - `/docs/architecture/testing-standards.md`

---

## 9. Tests Required to Prove the Behavior

### Flutter Automated Test Suite (`/flutter_app/test/stage344_snapshot_fidelity_restore_test.dart` — Verified in Flutter CI)
1. **Reminders Round-Trip & Soft-Link Policy:**
   - Export/import round-trip preserves `task`, `commitment`, `calendar_event`, and `custom` reminders with exact UTC `triggerTimeUtc`, `isActive`, `targetId`, `targetType`, `createdAt`.
   - Dangling `task`/`commitment`/`calendar_event`/`note` reminders warn-skip cleanly with `ORPHANED_REMINDER_SKIPPED` diagnostic while valid reminders (including `custom`) are preserved.
   - Omitted `'reminders'` on replace clears `_db.reminders` and records `LEGACY_REMINDERS_OMITTED`; invalid reminder scalar/date/duplicate-ID payloads fail closed pre-transaction with DB unchanged.
2. **Application Settings Fidelity, Exclusions & Stale Cleanup:**
   - User-owned settings (`calendar_display_mode`, `default_currency`, `calendar_preference`, custom user keys) round-trip cleanly.
   - Internal sentinels (`initial_seed_completed`, `ledger_v6_migrated_at`) and injected `secret_*`/`token_*`/`auth_*`/`passphrase_*`/`device_*`/`push_token`/`local_cache_*`/`transient_*` keys are never exported and safely excluded with warning diagnostics.
   - Omitted `'appSettings'` preserves local user settings untouched with `LEGACY_APP_SETTINGS_OMITTED`; omitted `ledgerMigrationReportV7` on clean v7 replace clears stale prior `ledger_migration_report_v7`.
   - Malformed `'appSettings'` or top-level `openingBalanceCents`/`isFinanceSetupCompleted` fails closed without overwriting valid settings.
3. **Per-Table Duplicate-ID & Cross-Table ID Reuse:**
   - Same-table duplicate PK (in `tasks`, `reminders`, `appSettings.key`, etc.) fails closed pre-transaction; same ID reused across different tables (e.g., `Account` `'shared-1'` + `Goal` `'shared-1'`) succeeds cleanly.
   - Duplicate `(monthIso, categoryId)` in `budgets` and duplicate non-null `legacySourceTxId` in `journalEntries` fail closed pre-transaction cleanly.
4. **Tier 1 Required vs. Tier 2/3 Optional FK & No-Category-Fabrication Enforcement:**
   - Broken Tier 1 required FKs (including `transactions.categoryId` pointing to a missing category — proving zero synthetic category insertion — plus `milestones.projectId`, `postings.*`, `debts.*`, `settlementAllocations.*`, `budgets.categoryId`, `commitmentSettlements.*`) fail closed **before** DB clear, DB close, or quarantine creation.
   - Broken Tier 2 nullable FKs (`tasks.projectId`, `tasks.milestoneId`, `notes.projectId`, `notes.goalId`, `categories.parentId` + cycle, `journalEntries.correctedFromEntryId` + cycle, `commitments.*`, `recurringRules.*`, `savingsGoals.linkedAccountId`, `debts.writeOffEntryId`, `postings.categoryId`) and Tier 3 soft tx links (`accountId`/`destinationAccountId`/`correctedFromId`) warn-clear to `null` with explicit diagnostics surfaced in `BackupRestoreResult.warnings` and `diagnostics`.
   - Every unsafe type mismatch (`amountCents` as string, `estimatedDurationMinutes` as string, `isPinned` as string, invalid date/JSON list) rejects pre-transaction as `BackupFailureKind.invalidPayload` rather than mid-transaction `TypeError` / `databaseImportFailure`.
5. **Unified 4-Entrypoint Validation & Hardened Quarantine Rollback:**
   - Verify all 4 entry points (`restoreEncryptedBackupInRecovery`, `restoreFromEncryptedBackup`, `importCanonicalSnapshot`, `DatabasePersistenceCoordinator.importSnapshotDetailed`) reject identical malformed/broken-FK snapshots pre-quarantine and pre-clear.
   - Simulated post-import / post-reopen failure during `restoreEncryptedBackupInRecovery` (e.g., via test hook/fault injection before quarantine deletion): verifies controller disposal, closing both candidate DB handles, keeping quarantine files intact on disk, copy-back restoration of `.sqlite` + `-wal` + `-shm`, reopening/rehydrating original DB when healthy before restore (or preserving corrupt-startup recovery state & diagnostics when previously broken), and preserving diagnostic details.
   - Simulated best-effort post-commit `INotificationService` exception after `deleteQuarantine`: verifies restore still succeeds cleanly without triggering rollback.

### Node / Web Tests (`/src/domain/sharedStateBridge.test.ts` — Executed Locally via `npm test`)
1. `SharedStateBridge` round-trips optional `reminders` and `appSettings` across `importFromAndroidJson`, `saveCanonicalState`, and `assembleLiveDatabaseState` (preserving Web `title`/`channelId` and normalized `targetId`).
2. Secret/internal excluded keys injected in `appSettings` are excluded cleanly; malformed `reminders` or `appSettings` fail closed without mutating any `localStorage` key.
3. Omitted `reminders` and `appSettings` remain optional and backward-compatible with pre-3.4.4 snapshots and existing `batch10Stage2Consolidation.test.ts` assertions.

---

## 10. Remaining Technical Uncertainties

1. **`FinancialTransactions.categoryId` Omission on Cross-Platform / Transfer Payloads:** `schema_contracts.json:112` keeps `Transaction.categoryId` optional for transfers and Web cross-platform payloads, while Drift's `FinancialTransactions.categoryId` SQLite column is `NOT NULL REFERENCES financial_categories(id)`. Resolving missing-on-export `categoryId` only for `transfer` / `< v7` payloads against canonical `'cat-other-exp'`/`'cat-other-inc'` (never synthesizing user categories and always failing closed on any explicit non-existent `categoryId`) resolves this cleanly, though extreme synthetic fixtures with empty `categories: []` and an omitted-category transfer would still need a starter category or fail SQLite FK constraints.
2. **Web `LocalReminder` Extra Columns (`title`, `channelId`) & Optional `targetId`:** Drift's `Reminders` table has only 6 columns (`id`, `targetId`, `targetType`, `triggerTimeUtc`, `isActive`, `createdAt`) and does not persist `title` or `channelId` (it derives notification titles from the linked target or fallback). Adding optional `title?` and `channelId?` to `SharedReminder` in `schema_contracts.json` prevents Web data loss without requiring a Drift v8 migration, though an Android->Web->Android round-trip through Flutter drops `title`/`channelId` by Drift v7 schema design.
3. **Controller Hydration Fault Surfacing:** Several existing controllers (`FinanceController.loadAll`, `InboxController.loadItems`, etc.) currently catch repository exceptions into `_state.errorMessage` instead of rethrowing. During `_rehydrateAllControllersStrict()`, Stage 3.4.4 must explicitly inspect controller `errorMessage` fields after `await Future.wait(...)` (or provide strict restore hydration checks) so a SQLite read failure during rehydration reliably triggers Section 6 rollback rather than silently passing.
4. **Local Container Toolchain Boundary:** This environment runs Node.js checks (`npm run sync-foundation`, `npm test`, `npm run lint`, `npm run build`, `compile_applet`, `lint_applet`) directly, whereas Flutter/Dart/Android SDK (`flutter analyze`, `flutter test`) require the Flutter host / GitHub Actions CI workflow (`.github/workflows/android.yml`).
