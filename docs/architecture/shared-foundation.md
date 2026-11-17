# Daywell — Shared Foundation Architecture

> **Purpose:** Documents the canonical `/shared_foundation/` specification files, automated code-generation pipeline, shared domain contracts, and cross-platform date/business rule synchronization.  
> **Governed By:** [PROJECT_CONSTITUTION.md](../../PROJECT_CONSTITUTION.md) (Sections 2.3 & 2.4)

---

## 1. Shared Foundation Specification & Generation Pipeline

| Component | Status | Verified Location / Mechanism |
| :--- | :--- | :--- |
| **Canonical JSON Specifications** | **Implemented** | `/shared_foundation/` (`design_tokens.json`, `business_rules.json`, `schema_contracts.json`, `canonical_seed_database.json`, `calendar_test_vectors.json`) |
| **Generator & Check Script (`sync-foundation` / `check-foundation`)** | **Implemented** | `/scripts/sync_foundation.mjs` invoked via `npm run sync-foundation` (chained into `npm run build`) and non-mutating `npm run check-foundation` (`--check`, chained into `npm run lint`) |
| **Generated TypeScript Foundation** | **Implemented** | `/src/domain/sharedFoundation.ts` |
| **Generated Web CSS Design Tokens** | **Implemented** | `/src/styles/daywellTokens.css` (`--dw-*` Light/Dark CSS custom properties + `.dw-type-*` classes, imported by `/src/index.css`) |
| **Generated Pure-Dart Foundation Core** | **Implemented** | `/flutter_app/lib/core/shared_foundation_core.dart` (no `dart:ui` / Flutter dependency so pure-Dart tests & data layers import cleanly) |
| **Generated Flutter Design Tokens Wrapper** | **Implemented** | `/flutter_app/lib/core/shared_foundation.dart` (re-exports `shared_foundation_core.dart` + Flutter `Color` / `SharedTextStyleToken`) |
| **Automated Parity Tests & UI Gate** | **Implemented** | `/src/domain/sharedFoundationParity.test.ts`, `/src/domain/uiConsistencyGovernance.test.ts`, `npm run check-ui`, and `/flutter_app/test/shared_design_tokens_test.dart` + `shared_date_foundation_test.dart` |

### Strict Generation Rule
Contributors MUST NEVER edit `/src/domain/sharedFoundation.ts`, `/src/styles/daywellTokens.css`, `/flutter_app/lib/core/shared_foundation_core.dart`, or `/flutter_app/lib/core/shared_foundation.dart` manually. Always edit the source JSON under `/shared_foundation/`, run `npm run sync-foundation`, and verify parity tests.

---

## 2. Canonical Specification Inventory

### 2.1 `design_tokens.json` (v1.1.0 — **Implemented**)
Validated strictly at generation time by `validateDesignTokens()` in `scripts/sync_foundation.mjs`:
- **Colors**: `primary`, `secondary`, `surface` (12 light/dark canvas, subtle, card, elevated, border, divider keys), `text` (8 light/dark keys), and `semantic` (`income`, `expense`, `transfer`, `success`, `error`, `warning`, `info` with `on*` and light/dark `*Container` pairs).
- **Typography**: `fontFamilySerif`, `fontFamilySans`, `fontFamilyMono`, plus 10 scale roles (`display`, `heading`, `title`, `body`, `bodyCompact`, `label`, `caption`, `numericHero`, `numericBody`, `mono`) with font weight, line height, letter spacing, font role, and `tabularFigures`.
- **Spacing, Radii, Elevation, Breakpoints**: `spacing` (`xs..xl`), `radii` (`sm..sheet, full`), `elevation` (`none..high`), and `breakpoints` (`medium: 600`, `expanded: 840`, `maxContentWidth: 720`, `maxWideWidth: 1120`).

### 2.2 `business_rules.json` (v1.0.0 — **Implemented**)
- **Finance**: `currencyCode: "ETB"`, `minorUnitsPerMajor: 100`, integer cents enforcement, reject `<= 0` amounts, reject identical transfer accounts, transfer preserves combined balance, safe deletion guards for accounts and categories with transactions.
- **Tasks**: Priority weights (`urgent: 4`, `high: 3`, `medium: 2`, `low: 1`), `defaultPriority: "medium"`, `defaultStatus: "not_started"`.
- **Calendar**: `system: "ethiopian_dual"`, 13 months, 30 days for months 1–12, Pagume 5 days (6 when `year % 4 == 3`), `canonicalDateFormat: "YYYY-MM-DD"`, `timeConvention: "UTC+3"`, `fixedUtcOffsetMinutes: 180`.
- **Projects (Stage 1 / 1.1 — [ADR-009](./decisions/ADR-009-projects-stage1-tracking-foundation-and-schema-v9.md))**: Statuses (`active`, `completed`, `on_hold` — separate from `isArchived`), block types (`counter`, `grouped_list`, `checklist`, `schedule`), record types (`group`, `grouped_item`, `checklist_item`, `schedule_item`, `progress_log`), custom field types (`text`, `number`, `date`, `boolean`, `select`), bounded limits (`maxBlocksPerProject: 32`, `maxCustomFieldDefinitions: 24`, `maxCustomFieldSelectOptions: 50`, `maxHierarchyDepth: 3`, `maxTrackingRecordTitleLength: 300`), append-only progress logs with explicit compensating corrections, single-source derived rollups (disallowing direct logging on rollup counters), independent multi-metric evaluation (no implicit cross-block averaging; `requiresExplicitPrimaryBlockForOverallPercent: true`), and schedule duration rule options (`manual`, `threshold_percent`, `exact_duration`). Generated identically into `SHARED_PROJECT_RULES` (TS) and `SharedProjectRules` (Dart).

### 2.3 `schema_contracts.json` (v2.0.0, `schemaVersion: 9` — **Implemented**)
Defines 18 canonical exchange/domain entity shapes and time convention (`Africa/Addis_Ababa`, `UTC+3`, `observesDst: false`):
- `Task`, `Note`, `CalendarEvent`, `Account` (including 11-value `subType` enum, `isSystem`, and standardized `isArchived` lifecycle per [ADR-008](./decisions/ADR-008-retire-account-isactive-and-schema-v8.md)), `Category`, `Transaction`, `Project` (extended additively with `isArchived`, `startDate`, `customFields`, `updatedAt`), `ProjectTrackingBlock`, `ProjectTrackingRecord`, `Goal`, `InboxItem`, `Commitment`, `CommitmentSettlement`, `SavingsGoal`, `Budget`, `RecurringRule`, `Reminder` (`title`, `channelId`, `targetId`, `targetType`, `triggerTimeUtc`, `isActive`, `createdAt`), and `AppSetting` (`key`, `value`, `updatedAt`).
- Note: Double-entry relational entities (`PartiesTable`, `JournalEntriesTable`, `PostingsTable`, `DebtsTable`, `SettlementAllocationsTable`, `Milestones`) exist in Flutter SQLite and TypeScript `SharedDatabaseStateV7` extensions rather than inside `schema_contracts.json` directly.

### 2.4 `canonical_seed_database.json` (**Implemented**)
- Clean empty startup state: currently declares `"schemaVersion": 5` (`appVersion: "1.0.2+3"`, `isFinanceSetupCompleted: false`, `openingBalanceCents: 0`), with empty `accounts`, `transactions`, `tasks`, `notes`, `projects`, `goals`, `inboxItems`, and `calendarEvents` collections. *(Note: `schema_contracts.json` declares `schemaVersion: 9`; `canonical_seed_database.json` and `SharedStateBridge` remain exchange `schemaVersion: 5` + `financeSchemaVersion: 7` by design across separate version domains.)*
- Preserves default Ethiopian spending/income `categories` (`Food`, `Transport`, `Housing`, `Utilities`, `Communication`, `Other`, `Salary`, `From Asaye`, `Other Income`).
- Paired with `KNOWN_SEED_IDS` (TS) and `KnownSeedIds` (Dart) generated by `sync_foundation.mjs` to purge historical demo data from existing installations safely (with `SharedStateBridge.purgeKnownSeedData()` also removing linked `projectTrackingBlocks` / `projectTrackingRecords` when purging known seed projects).

### 2.5 `calendar_test_vectors.json` (v1.0.0 — **Implemented**)
- Shared astronomical/civil Julian Day Number conversion truth table (`Ethiopian Epoch JDN 1724221`, `1900-02-28`, `2000-02-29`, `Pagume 5/6` across `1999`, `2015`, `2016`, `2017`, `2019` E.C.), plus invalid Gregorian and Ethiopian date rejection lists.

---

## 3. Generated Logic vs. Parallel Platform Engines (Verified Factual Boundary)

| Shared Capability | Status | Sync Mechanism | Known Discrepancies / Notes |
| :--- | :--- | :--- | :--- |
| **Simple Ledger Helpers & Seed Purge IDs** | **Implemented** | Direct code generation into `sharedFoundation.ts` & `shared_foundation_core.dart` | Matches identically across both runtimes. |
| **Ethiopian-Gregorian Date & `UTC+3` Clock** | **Implemented** (Parallel) | Shared algorithms validated against `calendar_test_vectors.json` | Implemented separately in `src/domain/date/` & `flutter_app/lib/core/date/` rather than generated by `sync_foundation.mjs`. Both pass vector tests. |
| **Projects Stage 1 Validation & Progress Engine** | **Implemented** (Parallel Domain Engines) | Shared constants/rules via `SharedProjectRules` / `SHARED_PROJECT_RULES`; symmetric validation & multi-metric calculation rules | `flutter_app/lib/domain/projects/` (`project_validation_service.dart`, `progress_engine.dart`) & `src/domain/projectsEngine.ts` implement identical date (`CalendarDate`), custom-field, append-only log, compensating-correction, rollup, and schedule duration semantics. Web tests verified in Node; Flutter tests CI-pending. |
| **Finance v7 Double-Entry & Currency Isolation Engine** | **Partially implemented** (Parallel) | Parity fixtures (`stage22CurrencyIsolation.test.ts`, `finance_v7_stage416_test.dart`) | Parallel domain/engine code exists in `src/domain/doubleEntryFinance.ts` + `financeV7Engine.ts` + `financialEngine.ts` vs. `flutter_app/lib/domain/finance/double_entry_engine.dart` + `financial_engine.dart`. Recovery Stage 2.1 is implemented and conditionally accepted; Stage 2.2 strict ETB-only isolation, integer-only decimal cent parsing, Quick Capture FX token rejection, and snapshot non-coercion rules are implemented across Web (verified via Node) and Flutter (**Unverified** locally pending CI); remaining Finance v7 integration gaps stay tracked. |
| **Canonical Snapshot & Version Domains** | **Aligned** (Separated Domains) | `schema_contracts.json` (`v2.0.0`, `schemaVersion: 9`), `AppDatabase` (`9`), exchange `schemaVersion: 5`, `snapshotFormatVersion: 2` | `DatabasePersistenceCoordinator.exportSnapshot()`, `SharedFoundationBridge.exportToCanonicalJson`, `SharedStateBridge.assembleLiveDatabaseState()`, and `canonical_seed_database.json` all emit canonical exchange `schemaVersion: 5`; coordinators/bridge also emit `snapshotFormatVersion: 2` (`databaseSchemaVersion: 9` on Flutter; `financeSchemaVersion: 7` on Web), while accepting exchange `schemaVersion: 4..9` (omitted => `5`), `snapshotFormatVersion: 1..2` (omitted => `1`), and optional `databaseSchemaVersion: 1..9` fail-closed. |
| **Web Consumption of Generated Tokens** | **Implemented** | `src/styles/daywellTokens.css` (CSS vars) + `SHARED_DESIGN_TOKENS` + `src/components/ui/` | `src/index.css`, `src/App.tsx`, and `src/components/` consume `--dw-*` CSS custom properties and `SHARED_DESIGN_TOKENS` with zero hardcoded hex literals, enforced by `npm run check-ui`. |

### Backward-Compatibility & Automated Enforcement ([ADR-007](./decisions/ADR-007-mandatory-backward-compatibility.md))
Per Constitution Section 2.11 and [ADR-007](./decisions/ADR-007-mandatory-backward-compatibility.md), new modifications to `/shared_foundation/*.json` MUST preserve existing TS and Dart consumers (for example, additive contract fields and retaining `KnownSeedIds` purge entries) or deliver coordinated migrations and parity tests across both platforms in the same stage.

Stages 3.2–3.3 enforce these guarantees via `npm run check-foundation` (`node scripts/sync_foundation.mjs --check`, run automatically by `npm run lint` and CI):
- **Non-destructive Freshness:** Verifies `src/domain/sharedFoundation.ts`, `flutter_app/lib/core/shared_foundation_core.dart`, and `flutter_app/lib/core/shared_foundation.dart` match current `/shared_foundation/*.json` specs byte-for-byte without modifying files.
- **Complete 5-File Validation:** Validates `design_tokens.json`, `business_rules.json`, `schema_contracts.json`, `canonical_seed_database.json`, and `calendar_test_vectors.json`.
- **Contract Non-Regression Baseline & Git Base Diff (Stage 3.3):** Checks protected design tokens, `KnownSeedIds` / `KNOWN_SEED_IDS`, `SYSTEM_CONTROL_ACCOUNT_IDS` / `SystemControlAccounts`, `business_rules.json` keys, and `schema_contracts.json` entities/fields/types/required flags/enums against `/scripts/foundation_compatibility_baseline.json` AND (when Git history is present or required in CI/via `--base-rev`) compares the current baseline against the authoritative Git base revision (`pull_request.base.sha` / push `before` / `HEAD^`), failing closed in GitHub Actions if history is shallow or unavailable or if callers attempt `--base-rev` override. Breaking baseline changes require `intentionalRemovals` referencing an **`accepted`** ADR under `/docs/architecture/decisions/ADR-*.md` with non-empty `## Justification`, `## Migration Strategy`, and `## Affected Consumers` sections, existing `coordinatedConsumers` files, and existing `verificationTests` files (note: structural ADR validation checks format/status/links and **does NOT replace human review and approval**).
- **Schema-Version Alignment Guard:** Enforces `flutter_app/lib/data/database/app_database.dart` (`AppDatabase.schemaVersion`) == `shared_foundation/schema_contracts.json` (`schemaVersion`, currently `9`) while leaving `canonical_seed_database.json` (`5`) and `SharedStateBridge` (`5`) intentionally untouched.
