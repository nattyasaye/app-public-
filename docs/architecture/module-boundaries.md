# Daywell — Module Boundaries & Cross-Module Contracts

> **Purpose:** Defines clean architectural layering, ownership per domain module, platform service abstractions, and coupling restrictions for Flutter Android and Web Preview.  
> **Governed By:** [PROJECT_CONSTITUTION.md](../../PROJECT_CONSTITUTION.md) (Sections 2.2 & 2.10)

---

## 1. Layer Dependency Rules

```
  Presentation (ui/screens/, ui/shell/, ui/widgets/  |  src/components/, src/App.tsx)
         │
         ▼  (reads state & dispatches user intents)
  Application  (flutter_app/lib/application/<module>/*_controller.dart + *_state.dart)
         │
         ├───────────────────────────┐
         ▼                           ▼
  Domain (pure business rules,   Data & Platform Services
   models, repo contracts)        (Drift repositories, coordinator, backup, notifications)
         ▲                           │
         └───────────────────────────┘  (Data implements Domain contracts; Domain never imports Data/UI)
```

### Mandatory Boundary Rules
1. **Domain Layer Purity**: Code under `flutter_app/lib/domain/` and `src/domain/` MUST contain zero Flutter widget imports, zero Drift/SQLite imports, and zero React/DOM imports.
2. **Presentation Decoupling**: Flutter UI screens and widgets MUST communicate through module controllers (`FinanceController`, `TasksController`, `NotesController`, `CalendarController`, `InboxController`) or thin `AppStateManager` callbacks—never executing raw SQL queries or multi-table DB transactions from widgets.
3. **Thin Composition Root (`AppStateManager`)**: Located in `flutter_app/lib/ui/app_state.dart`, `AppStateManager` initializes `AppDatabase`, runs recovery/startup coordination, wires the 5 controllers + `DriftSearchRepository`, and schedules finance reminders. It holds zero duplicated mutable entity lists; read-only legacy adapter classes (`TaskModel`, `ProjectModel`, `NoteModel`, `InboxItemModel`) remain isolated for compatibility.
4. **Repository Ownership**: Every write table belongs to a single domain repository. `DriftSearchRepository` reads read-only projections across `InboxItems`, `Tasks`, `Notes`, `CalendarEvents`, `FinancialCommitments`, `AccountsTable`, `JournalEntriesTable`, and `DebtsTable` + `PartiesTable`.
5. **Automated Boundary Enforcement (Governance Stage 3.3 — `Implemented`)**: `npm run check-architecture` ([`scripts/check_architecture_boundaries.mjs`](../../scripts/check_architecture_boundaries.mjs), chained into `npm run lint` and CI) parses TypeScript and Dart directives without being tripped by comments or string literals, enforcing domain purity (`flutter_app/lib/domain/`, `src/domain/`), layer isolation (`application`, `data`, `services`, `presentation`, `core`), `pubspec.yaml` asset isolation, and direct browser-global (`localStorage`, `sessionStorage`, `window`, `document`) bans in Web domain files (`src/domain/backupTypes.ts` decouples `backupCrypto.ts` from `src/data/localDatabase.ts` while re-exporting types compatibly from `localDatabase.ts`).
   - **Narrow Allowlist Exceptions ([`scripts/architecture_allowlist.json`](../../scripts/architecture_allowlist.json)):** Wildcards/globs are rejected; only exact documented edges are allowlisted today: `flutter_app/lib/ui/app_state.dart` (thin composition root wiring `AppDatabase`/repositories), `flutter_app/lib/ui/shell/daywell_shell_status_view.dart -> RawDatabaseRecoveryExporter` (legacy startup recovery diagnostic edge), and `flutter_app/lib/core/shared_foundation_bridge.dart -> AppStateManager / DoubleEntryEngine` (pre-existing legacy core bridge).
   - **Documented Static Limitation:** Browser-global checks detect direct un-aliased `localStorage`, `sessionStorage`, `window`, and `document` identifier references outside comments, strings, member reads, and property keys; indirect aliasing (such as `globalThis['localStorage']`) is not statically detected without full type/dataflow analysis.

---

## 2. Verified Module Inventory

| Module | Flutter Domain / App / Data | Flutter UI Host | Web Preview Host | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Finance** | `domain/finance/` (`double_entry_engine.dart`, `finance_contracts.dart`, `finance_models.dart`, `financial_engine.dart`, `recurring_engine.dart`) · `FinanceController` · `DriftFinanceRepository` | `FinanceView` + 4 tabs (`Overview`, `Transactions`, `Plan`, `Reports`) + `FinanceSetupWizard` + `FinanceComposerSheet` | `DaywellFinanceModule.tsx` + 4 tabs + `FinanceComposerModal.tsx` | **Partially implemented** — Recovery Stage 2.1 is implemented and conditionally accepted, whereas existing Finance v7 has identified defects and incomplete cross-platform integration, and Stage 2.2 ETB currency isolation is an approved requirement not yet completed and accepted |
| **Tasks (with Projects & Milestones)** | `domain/tasks/` + `domain/projects/progress_engine.dart` · `TasksController` · `DriftTasksRepository` | `TasksView` (Tasks & Projects tabs) | `DaywellTasksModule.tsx` + static/empty prototype `projects`/`project_detail` screens in `App.tsx` | **Implemented** (Tasks); **Partially implemented** (standalone Projects/Goals parity) |
| **Notes** | `domain/notes/` · `NotesController` · `DriftNotesRepository` | `NotesView` + full-screen `_NoteEditorScreen` | `DaywellNotesModule.tsx` | **Implemented** |
| **Calendar** | `domain/calendar/` · `CalendarController` · `CalendarRepository` | `CalendarPlaceholderView` (reads `CalendarController` state; links to `TasksView`) | `DaywellCalendarModule.tsx` (Month, Week, Day, Agenda + Event CRUD + Task overlay) | **Partially implemented** (Web full UI; Flutter placeholder UI) |
| **Inbox & Quick Capture** | `domain/inbox/` · `InboxController` · `InboxRepository` | `QuickCaptureDialog` + Android `MethodChannel('com.example.personalmanagement/quick_capture')` | Quick Capture sheet in `App.tsx` | **Implemented** (cross-platform capture semantics differ slightly—see [cross-platform-parity.md](./cross-platform-parity.md)) |
| **Search** | `DriftSearchRepository` (`ISearchRepository`) | Exposed via controller/search helpers | Per-module search filters in Tasks/Notes/Finance/Calendar | **Partially implemented** (Flutter unified SQLite search repo exists without dedicated global search screen; Web uses per-module filters) |

---

## 3. Platform Service Contracts (`/flutter_app/lib/core/interfaces/platform_service_interfaces.dart`)

| Abstract Contract | Intended Responsibility | Current Implementation Status |
| :--- | :--- | :--- |
| `INotificationService` | Local offline task/commitment reminders | **Partially implemented** — `LocalNotificationService` creates 3 Android channels (`task`, `commitment`, `custom`) and requests permissions, but `scheduleReminder()` currently calls `_notificationsPlugin.show(...)` immediately instead of `zonedSchedule` for future timestamps. Runtime Android device alerts are **Unverified**. |
| `IBackupService` | File-path encrypted SQLite archive & inspect API | **Planned / Interface-only** — `EncryptionBackupService` implements AES-GCM-256 JSON string encrypt/decrypt (`BackupView`), not the `IBackupService` file-archive interface. |
| `ISecureStorageService` | Android Keystore / iOS Keychain secrets | **Planned / Interface-only** — `flutter_secure_storage` package is declared in `pubspec.yaml`, with no implementing class in `flutter_app/lib/`. |
| `IWidgetSyncService` | Home-screen Quick Capture & Today widgets | **Planned / Interface-only** — No implementing class exists yet. |

---

## 4. Extensibility Rules for Future Modules

Adding a future standalone module (such as standalone **Goals**, **Relationships**, or **Habits**) MUST follow this exact checklist without restructuring `/docs/architecture/`:
1. Define canonical entity contracts in `/shared_foundation/schema_contracts.json` and run `npm run sync-foundation`.
2. Add normalized tables and atomic migrations in `AppDatabase`, plus an isolated repository implementing a pure-domain contract.
3. Add an immutable state class + `ChangeNotifier` controller registered in `AppStateManager`.
4. Add UI screens using shared `DaywellTheme` tokens and `/flutter_app/lib/ui/widgets/` primitives, mirrored in Web Preview.
5. Update `module-boundaries.md`, `data-and-persistence.md`, `ui-design-system.md`, and `cross-platform-parity.md` in the same stage.
