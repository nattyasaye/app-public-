# Daywell — System Architecture Overview

> **Document Role:** Authoritative top-level map of Daywell's dual-platform architecture, actual implementation status, historical document index, and `/docs/architecture/` suite.  
> **Governed By:** [PROJECT_CONSTITUTION.md](../../PROJECT_CONSTITUTION.md)

---

## 1. High-Level System Topology

Daywell consists of two client runtimes fed by a single specification layer (`/shared_foundation/`):

```
┌────────────────────────────────────────────────────────────────────────────┐
│                   CANONICAL SPECIFICATION LAYER                            │
│  /shared_foundation/                                                       │
│   ├── design_tokens.json (v1.1.0)                                          │
│   ├── business_rules.json (v1.0.0; Finance, Tasks, Calendar & Projects rules)│
│   ├── schema_contracts.json (v2.0.0, schemaVersion: 10)                    │
│   ├── canonical_seed_database.json (schemaVersion: 5; clean seed + cats)   │
│   └── calendar_test_vectors.json (Ethiopian <-> Gregorian reference cases) │
└─────────────────────┬──────────────────────────────────────────────────────┘
                      │  npm run sync-foundation (scripts/sync_foundation.mjs)
        ┌─────────────┴─────────────────────────────┐
        ▼                                           ▼
┌─────────────────────────────────┐      ┌──────────────────────────────────┐
│  FLUTTER ANDROID APP            │      │  GOOGLE AI STUDIO WEB PREVIEW    │
│  /flutter_app/lib/              │      │  /src/                           │
│                                 │      │                                  │
│  • core/   (Tokens, Date, Core) │      │  • domain/ (Foundation, Date,    │
│  • domain/ (Finance v7, Tasks,  │      │    Finance v7, Projects, Crypto) │
│            Projects, Notes, Cal)│      │  • data/   (localDatabase.ts,    │
│  • application/ (6 Controllers) │      │    projectsRepository.ts)        │
│  • data/   (Drift SQLite v10,   │      │  • services/ (SharedStateBridge, │
│            25 tables, 7 repos,  │      │    DataPortabilityService)       │
│            Recovery Exporter)   │      │  • components/ & App.tsx         │
│  • services/ (Backup, Export,   │      │    (React 19 + Vite + Tailwind)  │
│            Notifications)       │      │                                  │
│  • ui/     (M3 Theme, Shared    │      │  Persistence: localStorage       │
│            Widgets, Shell, Views│      │  Status: Interactive browser     │
│            ; Stage 2 Proj UI Pending) │  preview & prototype host        │
└─────────────────────────────────┘      └──────────────────────────────────┘
```

---

## 2. Actual vs. Intended Architecture Inventory

Per [PROJECT_CONSTITUTION.md](../../PROJECT_CONSTITUTION.md), every module and subsystem is classified by what is **verified in source code today**, separating real behavior from partial scaffolds or future plans.

| Capability / Area | Status | Verified Reality in Repository | Authoritative Detail |
| :--- | :--- | :--- | :--- |
| **Shared Foundation Specs & Codegen** | **Implemented** | `scripts/sync_foundation.mjs` validates `design_tokens.json` (`v1.1.0`), `business_rules.json` (`v1.0.0`), and `schema_contracts.json` (`v2.0.0`, `schemaVersion: 10`) and generates `src/domain/sharedFoundation.ts`, `src/styles/daywellTokens.css`, `flutter_app/lib/core/shared_foundation_core.dart`, and `flutter_app/lib/core/shared_foundation.dart`. | [shared-foundation.md](./shared-foundation.md) |
| **Dual Ethiopian-Gregorian Date Engine** | **Implemented** | Parallel verified engines in `flutter_app/lib/core/date/` and `src/domain/date/`, both tested against `calendar_test_vectors.json` (`UTC+3` Addis Ababa, 13 months, Pagume 5/6 leap rule). | [shared-foundation.md](./shared-foundation.md) |
| **Drift SQLite Database (Schema v10)** | **Implemented** (Flutter execution & Drift codegen **Unverified** locally) | `AppDatabase` (`schemaVersion => 10`) defines 25 tables (including `DailyPlanningEntries` and `Tasks` +6 Stage 0.2B columns alongside `ProjectTrackingBlocks` and `ProjectTrackingRecords`), performance indices, `V6LedgerMigrator`, `V7LedgerHardener`, atomic `from < 10` migration, `DatabasePersistenceCoordinator`, and `RawDatabaseRecoveryExporter`. Dart `build_runner` regeneration (`app_database.g.dart`) and Android execution are **Unverified** locally (no `flutter`/`dart`/`adb` in container). | [data-and-persistence.md](./data-and-persistence.md) |
| **Finance Module (v7 Double-Entry + Safe Harbor)** | **Partially implemented** | **Recovery Stage 2.1** is **Implemented** and conditionally accepted (integer-cents ledger scaffold, `SYSTEM_CONTROL_ACCOUNT_IDS`, immutable void/correction patterns, 4 UI tabs + composer/wizard in Flutter and Web Preview). **Stage 2.2 Strict ETB Isolation** is implemented in code (Web verified in Node; Flutter CI-pending), while remaining Finance v7 cross-platform integration defects keep overall status **Partially implemented**. | [module-boundaries.md](./module-boundaries.md), [data-and-persistence.md](./data-and-persistence.md), [cross-platform-parity.md](./cross-platform-parity.md) |
| **Tasks Module** | **Implemented** | `TasksController` + `DriftTasksRepository` (preserving `Tasks.projectId` / `Milestones.projectId` FKs) and `TasksView` in Flutter; `DaywellTasksModule` + `daywell_tasks` in `localStorage` on Web. | [cross-platform-parity.md](./cross-platform-parity.md) |
| **Projects Stage 1 Tracking Foundation** | **Partially implemented** *(Stage 1 foundation **Implemented**; Stage 2 UI & Stage 3 `.daywellproject` **Planned**)* | **Stage 1:** Dedicated `IProjectsRepository` (`DriftProjectsRepository` + `ProjectsController` on Flutter; `WebProjectsRepository` + `projectsEngine.ts` on Web), 3-table model (`Projects` extended + `ProjectTrackingBlocks` + `ProjectTrackingRecords`), append-only progress logs & compensating corrections, multi-metric `ProgressEngine`, typed custom fields, and `SharedStateBridge` / coordinator v9 integration. Web/Node verified locally; Flutter analysis/tests **Unverified** locally pending CI. Stage 2 Projects UI and Stage 3 portable `.daywellproject` packaging remain **Planned**. | [module-boundaries.md](./module-boundaries.md), [data-and-persistence.md](./data-and-persistence.md), [ADR-009](./decisions/ADR-009-projects-stage1-tracking-foundation-and-schema-v9.md) |
| **Notes Module** | **Implemented** | `NotesController` + `DriftNotesRepository` + `NotesView` (`All`, `Pinned`, `Favorites`, `Archive`, `Trash`, editor) in Flutter; `DaywellNotesModule` (`All`, `Pinned`, `Archive` — lacks Favorites/Trash tabs) on Web. | [cross-platform-parity.md](./cross-platform-parity.md) |
| **Calendar Module** | **Partially implemented** | **Web Preview:** Full `DaywellCalendarModule` (Month/Week/Day/Agenda, dual calendar toggle, event CRUD, task overlay). **Flutter:** Domain/Repo/Controller (`CalendarController` + `CalendarEvents` table) exist, but shell hosts `CalendarPlaceholderView` ("Calendar workspace coming soon"). | [cross-platform-parity.md](./cross-platform-parity.md) |
| **Inbox & Quick Capture** | **Implemented** | `InboxController` + `QuickCaptureDialog` in Flutter (also Android MethodChannel intent listener); Quick Capture bottom sheet in Web `App.tsx` (expense Quick Capture enforces ETB-only rules, whereas task/note/reminder write directly to module stores rather than Web `daywell_inbox_items`). | [cross-platform-parity.md](./cross-platform-parity.md) |
| **Design Token Consumption** | **Implemented** (with 5 legacy Flutter allowlist files) | Canonical `design_tokens.json` -> `src/styles/daywellTokens.css` (`--dw-*`), `SHARED_DESIGN_TOKENS`, and `DaywellTheme` / `context.daywellColors`. Web UI has `0` hardcoded hexes; Flutter `MoreView` & `DashboardView` have `0` raw `Colors.*` / `Color(0x...)` (5 legacy Flutter files capped in `ui_consistency_allowlist.json`). | [ui-design-system.md](./ui-design-system.md) |
| **Encrypted Backup & Restore** | **Partially implemented** | Flutter `EncryptionBackupService` + `BackupView` support PBKDF2-HMAC-SHA256 (`100,000` rounds) + AES-GCM-256 `.daywell` copy/paste envelopes over v4–v9 exchange (`databaseSchemaVersion: 1..9`, kept separate from `AppDatabase` v10 until Stage 0.2C serializes v10 Task/DailyPlanning data) canonical snapshots AND canonical JSON export/import. Web `src/domain/backupCrypto.ts` validates envelope headers on `LocalDatabaseState` v3 (unit-tested), while Web `sync_backup` screen exports/imports unencrypted canonical JSON (`SharedStateBridge`). | [data-and-persistence.md](./data-and-persistence.md) |
| **Platform Service Interfaces** | **Partially implemented** | 4 interfaces declared in `platform_service_interfaces.dart`. Only `INotificationService` has an implementation (`LocalNotificationService`, whose `scheduleReminder` calls immediate `.show()` rather than `zonedSchedule`). `ISecureStorageService`, `IBackupService`, `IWidgetSyncService` have no implementing classes. | [module-boundaries.md](./module-boundaries.md) |
| **Projects, Project Detail, Goals, Relationships, Priorities, Tools, History (Web Showcase Screens)** | **Deprecated** (Prototype UI) / **Planned** | Web `App.tsx` prototype screens (`projects`, `project_detail`, `goals`, `relationships`, `priorities`, `tools`, `history`) remain explicitly badged **`Deprecated Prototype`** during Projects Stage 1 (pre-Stage 2 UI). Flutter has `Goals`/`Projects`/`Milestones` SQLite tables (Stage 2 Projects UI **Planned**). | [cross-platform-parity.md](./cross-platform-parity.md) |
| **Web Sync Status & Telegram Backup Cards** | **Deprecated** (Static Preview) / **Planned** | `src/App.tsx` (`sync_backup` Sync/Telegram cards and `Today` sample cards) render with canonical tokens and explicit **`Deprecated Prototype`** badges with no backing sync engine. | [cross-platform-parity.md](./cross-platform-parity.md) |
| **Android APK R8 Shrinking** | **Partially implemented / Conflicting Docs** | `flutter_app/android/app/proguard-rules.pro` exists, and `.github/workflows/android.yml` builds isolated ARM64 release APKs; however, `flutter_app/android/app/build.gradle` currently has `minifyEnabled false` and `shrinkResources false`. | [testing-standards.md](./testing-standards.md) |

---

## 3. Historical & Root Documentation Status Index

All pre-existing Markdown documents at repository root are **preserved untouched** for historical auditability per Governance Stage 1 rules. They are NOT authoritative over `PROJECT_CONSTITUTION.md` or `/docs/architecture/`.

| Root File | Original Purpose / Date | Current Governance Status | Superseded By / Notes |
| :--- | :--- | :--- | :--- |
| `/DEVELOPMENT_ROADMAP.md` | Early multi-phase feature & architecture roadmap | **Deprecated / Superseded** | Replaced by `PROJECT_CONSTITUTION.md`, [overview.md](./overview.md), and [cross-platform-parity.md](./cross-platform-parity.md). Contains early `localStorage` & pre-v7 assumptions. |
| `/FINANCE_UI_AUDIT.md` | Pre-Stage-4 Finance Web vs. Flutter audit (2026-11-10) | **Deprecated / Superseded** | Outdated: audited an earlier `finance_view.dart` before the modular 4-tab `flutter_app/lib/ui/screens/finance/` implementation existed. Replaced by [cross-platform-parity.md](./cross-platform-parity.md). |
| `/IMPLEMENTATION_CHECKLIST.md` | Early architecture checklist (2026-11-10) | **Deprecated / Superseded** | Historical Phase 0/Stage 1 checklist (`schemaVersion: 3` era). Current reality is tracked in [data-and-persistence.md](./data-and-persistence.md) and [module-boundaries.md](./module-boundaries.md). |
| `/IMPLEMENTATION_STATUS.md` | Running log of Batches 5–6, early UI parity, and CI fixes (2026-11-10) | **Historical / Partially Superseded** | Preserved as historical changelog. Its module status claims predate Finance v7 hardening, `DaywellAdaptiveScaffold`, and `CalendarPlaceholderView`. |
| `/PRODUCTION_APK_AUDIT.md` | Stage 2 dummy-data removal & clean initialization audit (2026-11-11) | **Historical Reference** | Preserved as Stage 2 audit log. Its clean-init and `KnownSeedIds` rules are now codified in [shared-foundation.md](./shared-foundation.md) and [data-and-persistence.md](./data-and-persistence.md). |
| `/INSTALLED_STORAGE_AND_APK_SIZE_AUDIT.md` | APK 3-tier size baseline & debug vs. release investigation (2026-11-11) | **Historical Reference (Partially Inaccurate vs. Current Gradle)** | Explains fat debug APK vs. ARM64 release math, but note current `flutter_app/android/app/build.gradle` sets `minifyEnabled false` and `shrinkResources false`. |
| `/STORAGE_OPTIMIZATION_FAILURE_INVESTIGATION.md` | Container vs. GitHub sync & CI `kernel_blob.bin` bleed analysis (2026-11-11) | **Historical Reference (Partially Inaccurate vs. Current Gradle)** | Explains CI isolation fixes, though current `flutter_app/android/app/build.gradle` does not currently have R8 `minifyEnabled true` enabled. |
| `/MAYBE_LATER.md` | Permanent bucket list of deferred, experimental, & excluded features | **Active Feature Backlog (Partially Outdated in Section F)** | Preserved as the backlog ledger under Constitution Section 2.10. Note: Several items listed as removed in Section F (Budgets, Debts, Reporting) were later re-implemented in Finance v7. |

---

## 4. Authoritative Documentation Map (`/docs/architecture/`)

| Document | Scope |
| :--- | :--- |
| [overview.md](./overview.md) | This file: high-level topology, actual vs. intended inventory, root doc status index. |
| [shared-foundation.md](./shared-foundation.md) | `/shared_foundation/*.json` specs, `sync_foundation.mjs` generator, cross-platform date & currency parity specs. |
| [data-and-persistence.md](./data-and-persistence.md) | Drift SQLite v10 schema (25 tables), migrations, coordinator, recovery, encryption, Web `localStorage` duality. |
| [module-boundaries.md](./module-boundaries.md) | Layering, 6 controllers, 7 repositories, platform interfaces, cross-module & Flutter/Web isolation contracts. |
| [ui-design-system.md](./ui-design-system.md) | 5-tier UI authority hierarchy, theme/tokens, shared primitives & patterns, design assets mapping, conflicts. |
| [cross-platform-parity.md](./cross-platform-parity.md) | Visual & functional Flutter Android vs. Web Preview parity matrix, intentional adaptations, unresolved gaps. |
| [testing-standards.md](./testing-standards.md) | Verified test suites (`npm test`, Dart tests, CI APK pipeline), verification rules, unverified areas. |
| [decisions/README.md](./decisions/README.md) | ADR index, status definitions, and template for future architectural decisions. |
