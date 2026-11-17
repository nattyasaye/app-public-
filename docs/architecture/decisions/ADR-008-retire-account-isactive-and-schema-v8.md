# ADR-008: Retire `Account.isActive` in Favor of `isArchived` and Advance Schema to Version 8

- **Status:** accepted
- **Date / Version:** 2026-11-16 / Governance Stage 3.4.4.1 (`AppDatabase.schemaVersion = 8`, `schema_contracts.json = 8`)
- **Affected Docs:** [`PROJECT_CONSTITUTION.md`](../../../PROJECT_CONSTITUTION.md), [`docs/architecture/shared-foundation.md`](../shared-foundation.md), [`docs/architecture/data-and-persistence.md`](../data-and-persistence.md), [`docs/architecture/cross-platform-parity.md`](../cross-platform-parity.md)

---

## Context

During Governance Stage 3.4.4.1, an independent cross-platform audit identified two persistence and contract drift defects:

1. **Phantom `Account.isActive` Contract Field:** `shared_foundation/schema_contracts.json`, `scripts/foundation_compatibility_baseline.json`, generated `SharedAccount`, and parts of the Web Finance domain (`doubleEntryFinance.ts`, `financeV7Engine.ts`, `SharedStateBridge`) tracked `Account.isActive`, whereas Android's authoritative Drift table (`AccountsTable` in `flutter_app/lib/data/database/tables.dart`) has always persisted `isArchived` (`BoolColumn get isArchived => boolean().withDefault(const Constant(false))()`) and has never stored `isActive`. Maintaining both flags created redundant filtering (`!a.isArchived && a.isActive !== false`) and a non-persistent contract field on Android.
2. **Missing Reminder Columns (`title`, `channelId`) in SQLite v7:** `shared_foundation/schema_contracts.json` defines nullable `title` and `channelId` on `Reminder`, and Web `SharedStateBridge` already round-trips them, while Android's `Reminders` table in schema v7 omitted those two columns, causing `DatabasePersistenceCoordinator` to validate and discard them on import.

## Decision

1. **Retire `Account.isActive` and standardize on `isArchived`:** Remove `isActive` from `shared_foundation/schema_contracts.json` (`entities.Account.fields`), `scripts/foundation_compatibility_baseline.json` (`protectedSchemaContracts.Account.fields`), generated `SharedAccount`, and Web/Dart shared balance helpers. Retain `isActive` strictly where it belongs on `RecurringRule.isActive` and `Reminder.isActive`, as well as transient UI wizard row checkboxes (`setupAccountsList`).
2. **Advance Drift `AppDatabase` and `schema_contracts.json` to `schemaVersion = 8`:** Add nullable `TextColumn title` and `TextColumn channelId` (`channel_id` in SQLite) to `Reminders` via an additive, idempotent `if (from < 8)` migration block in `AppDatabase.migration`, preserving all existing v7 rows, foreign keys, and user data.

## Justification

- Having both `Account.isArchived` and `Account.isActive` violates single-source-of-truth contract fidelity between Android SQLite (`AccountsTable`) and Web `SharedStateBridge`.
- Android SQLite has always treated `isArchived == false` as an active account; retiring the unpersisted duplicate flag `Account.isActive` eliminates silent loss of `isActive` across Android backup/restore without requiring a redundant SQLite column.
- Advancing schema v7 -> v8 solely for `reminders.title` and `reminders.channel_id` restores 1:1 cross-platform Reminder fidelity with zero destructive changes.

## Migration Strategy

1. **Backward Compatibility (`ADR-007`):**
   - Supported Flutter canonical snapshot bounds remain `4..8` (omitted version defaults to `5`), ensuring v4, v5, v6, and v7 encrypted `.daywell` backups and canonical JSON snapshots import seamlessly into v8 databases.
   - Unknown or legacy `isActive` properties present on `accounts[]` objects in older backups or Web `localStorage` data do not cause snapshot rejection on either platform; when Web `SharedStateBridge` normalizes legacy account records or archives, `isArchived` remains the canonical boolean flag (with legacy `{ isActive: false }` gracefully treated as archived if `isArchived` was not explicitly set).
   - Multi-hop SQLite upgrades (`v4 -> v8`, `v6 -> v8`, `v7 -> v8`) run atomically inside `AppDatabase.migration.onUpgrade` with fail-closed downgrade protection (`from > to` throws `UnsupportedDatabaseVersionException`) and zero destructive fallback.

## Affected Consumers

- **Canonical Contracts & Generators:** `shared_foundation/schema_contracts.json`, `scripts/foundation_compatibility_baseline.json`, `scripts/sync_foundation.mjs`, `src/domain/sharedFoundation.ts`, `flutter_app/lib/core/shared_foundation_core.dart`, `flutter_app/lib/core/shared_foundation.dart`.
- **Web Domain, Bridge & UI:** `src/domain/doubleEntryFinance.ts`, `src/domain/financeV7Engine.ts`, `src/services/sharedStateBridge.ts`, `src/components/DaywellFinanceModule.tsx`, `src/components/finance/FinanceOverviewTab.tsx`, `src/components/finance/FinanceComposerModal.tsx`.
- **Flutter Database & Coordinator:** `flutter_app/lib/data/database/tables.dart`, `flutter_app/lib/data/database/app_database.dart`, `flutter_app/lib/data/database/app_database.g.dart`, `flutter_app/lib/data/database/database_persistence_coordinator.dart`, `flutter_app/lib/services/backup/encryption_backup_service.dart`.

## Alternatives Considered

1. **Add `is_active` column to Drift `AccountsTable`:** Rejected because it duplicates `is_archived` semantics (`isActive = !isArchived`), creating contradictory states (`isArchived: true, isActive: true`) across the double-entry engine.
2. **Keep `Account.isActive` in `schema_contracts.json` as Web-only:** Rejected under Constitution §2.2 and ADR-002, which prohibit divergent platform entity contracts.

## Consequences & Trade-Offs

- **Positive:** Single canonical account lifecycle boolean (`isArchived`) across contract, Web, and Android SQLite; full Reminder `title`/`channelId` round-trip fidelity on Android and Web.
- **Trade-Off:** Pre-v8 Android releases remain unable to open v8 SQLite files or v8 backups, failing closed with `UnsupportedDatabaseVersionException` / `unsupportedFutureSchema`.
