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
2. **Presentation Decoupling**: Flutter UI screens and widgets MUST communicate through module controllers (`FinanceController`, `TasksController`, `ProjectsController`, `NotesController`, `CalendarController`, `InboxController`, `DailyRhythmController`) or thin `AppStateManager` callbacks—never executing raw SQL queries or multi-table DB transactions from widgets.
3. **Thin Composition Root (`AppStateManager`)**: Located in `flutter_app/lib/ui/app_state.dart`, `AppStateManager` initializes `AppDatabase`, runs recovery/startup coordination, wires the 7 controllers (`FinanceController`, `TasksController`, `ProjectsController`, `NotesController`, `CalendarController`, `InboxController`, `DailyRhythmController`) + `DriftSearchRepository`, coordinates cross-module Finance ledger reconfirmation observers into `DailyRhythmController`, and schedules finance reminders. It holds zero duplicated mutable entity lists; read-only legacy adapter classes (`TaskModel`, `ProjectModel`, `NoteModel`, `InboxItemModel`) remain isolated for compatibility.
4. **Repository Ownership**: Every write table belongs to a single domain repository. `DriftProjectsRepository` (`IProjectsRepository`) owns Projects, `ProjectTrackingBlocks`, and `ProjectTrackingRecords` mutations (while coordinating bottom-up child cleanup and `Tasks.projectId` detachment on project deletion), leaving Tasks and Milestones orchestration inside `DriftTasksRepository` / `TasksController`. `DriftSearchRepository` reads read-only projections across `InboxItems`, `Tasks`, `Notes`, `CalendarEvents`, `FinancialCommitments`, `AccountsTable`, `JournalEntriesTable`, and `DebtsTable` + `PartiesTable`.
5. **Automated Boundary Enforcement (Governance Stage 3.3 — `Implemented`)**: `npm run check-architecture` ([`scripts/check_architecture_boundaries.mjs`](../../scripts/check_architecture_boundaries.mjs), chained into `npm run lint` and CI) parses TypeScript and Dart directives without being tripped by comments or string literals, enforcing domain purity (`flutter_app/lib/domain/`, `src/domain/`), layer isolation (`application`, `data`, `services`, `presentation`, `core`), `pubspec.yaml` asset isolation, and direct browser-global (`localStorage`, `sessionStorage`, `window`, `document`) bans in Web domain files (`src/domain/backupTypes.ts` decouples `backupCrypto.ts` from `src/data/localDatabase.ts` while re-exporting types compatibly from `localDatabase.ts`, `src/domain/projectsEngine.ts` mirrors Flutter's pure domain validation and progress engine, and `src/domain/projectPackage.ts` / `flutter_app/lib/domain/projects/project_package_codec.dart` isolate `.daywellproject` serialization and validation in pure domain code while platform file I/O lives in `services/export/project_package_io_service.dart` and `src/services/projectsService.ts`).
   - **Narrow Allowlist Exceptions ([`scripts/architecture_allowlist.json`](../../scripts/architecture_allowlist.json)):** Wildcards/globs are rejected; only exact documented edges are allowlisted today: `flutter_app/lib/ui/app_state.dart` (thin composition root wiring `AppDatabase`/repositories including `DriftProjectsRepository` and `DriftDailyRhythmRepository`), `flutter_app/lib/ui/shell/daywell_shell_status_view.dart -> RawDatabaseRecoveryExporter` (legacy startup recovery diagnostic edge), and `flutter_app/lib/core/shared_foundation_bridge.dart -> AppStateManager / DoubleEntryEngine` (pre-existing legacy core bridge).
   - **Documented Static Limitation:** Browser-global checks detect direct un-aliased `localStorage`, `sessionStorage`, `window`, and `document` identifier references outside comments, strings, member reads, and property keys; indirect aliasing (such as `globalThis['localStorage']`) is not statically detected without full type/dataflow analysis.

---

## 2. Verified Module Inventory

| Module | Flutter Domain / App / Data | Flutter UI Host | Web Preview Host | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Finance** | `domain/finance/` (`double_entry_engine.dart`, `finance_contracts.dart`, `finance_models.dart`, `financial_engine.dart`, `recurring_engine.dart`) · `FinanceController` · `DriftFinanceRepository` | `FinanceView` + 4 tabs (`Overview`, `Transactions`, `Plan`, `Reports`) + `FinanceSetupWizard` + `FinanceComposerSheet` | `DaywellFinanceModule.tsx` + 4 tabs + `FinanceComposerModal.tsx` | **Partially implemented** — Recovery Stage 2.1 is implemented and conditionally accepted, whereas existing Finance v7 has identified defects and incomplete cross-platform integration, and Stage 2.2 ETB currency isolation is an approved requirement not yet completed and accepted |
| **Tasks** | `domain/tasks/` (`task_models.dart`, `task_recurrence_engine.dart`, `task_reminder_engine.dart`, `task_calendar_engine.dart`, `task_summary_engine.dart`, `daily_planning_engine.dart`) · `TasksController` · `DriftTasksRepository` | `TasksView` (`Tasks` & `Projects` tabs + `requestedTaskFocus` / `requestedSubTab` / `onOpenCalendarDate` + `TaskReminderEditorSection` / `TaskReminderDetailsSection`) + `DashboardView` (`DashboardTasksSection`) | `DaywellTasksModule.tsx` + `src/domain/taskCalendar.ts` + `src/domain/taskReminders.ts` + `src/domain/taskSummaries.ts` + `src/services/taskRemindersService.ts` + `TaskReminderFields.tsx` + `App.tsx` (`Today` Dashboard) | **Implemented** (Web Stages 0.2C & 1–6 Node-verified; Flutter runtime CI-pending) |
| **Projects (Stage 1–3)** | `domain/projects/` (`project_models.dart`, `project_contracts.dart`, `project_validation_service.dart` *(missing on disk)*, `progress_engine.dart`, `project_package_codec.dart`) · `ProjectsController` (`ProjectsModuleState`) · `DriftProjectsRepository` · `ProjectPackageIoService` | `TasksView` (`ProjectsWorkspaceTab`, `ProjectDetailScreen`, `ProjectFormSheet`, `ProjectImportDialog`) + `DashboardView` (`DashboardProjectProgressSection`) | `DaywellTasksModule.tsx` (`ProjectsWorkspaceView`, `ProjectDetailView`, `ProjectFormModal`, `ProjectImportModal`) + `projectsService.ts` + `src/domain/projectsEngine.ts` + `src/domain/projectPackage.ts` + `src/data/projectsRepository.ts` + `App.tsx` (`Project Progress`) | **Implemented** on Web (Node-verified); **Implemented in Code / Unverified** on Flutter Android (`MainActivity` SAF `MethodChannel`, `flutter analyze`, `flutter test`, and `app_database.g.dart` codegen CI-pending) |
| **Notes** | `domain/notes/` (`note_models.dart`, `note_helpers.dart`, `note_markdown.dart`, `note_editor_formatting.dart`, `note_links.dart`, `task_notes_helpers.dart`) · `NotesController` · `DriftNotesRepository` | `NotesView` (`_NoteEditorSurface` wide detail + `_NoteEditorScreen` narrow route + `onRegisterPendingSaveFlush` + `requestedNoteFocus`) + `NoteMarkdownPreview` (`ui/widgets/notes/note_markdown_preview.dart`) | `DaywellNotesModule.tsx` + `src/domain/noteHelpers.ts` + `src/domain/noteMarkdown.ts` + `src/domain/noteEditorFormatting.ts` + `src/domain/noteLinks.ts` + `src/domain/webNotesLifecycle.ts` + `src/components/notes/NoteMarkdownPreview.tsx` | **Implemented** on Web (Stages N1.2, N1.3, N2.1–N2.4, N3.2, N3.3, N4.1 Node-verified); **Implemented in Code / Unverified** on Flutter (Stages 8, N1.4, N2.1–N2.4, N3.1–N3.3, N4.1 CI-pending) |
| **Calendar** | `domain/calendar/` + `domain/tasks/task_calendar_engine.dart` (pure projection) · `CalendarController` · `CalendarRepository` | `CalendarView` (Month / Day / Agenda + Event CRUD + `TaskCalendarEngine` task/recurrence overlay + `onOpenTask`; `CalendarPlaceholderView` retained solely for unit-test compatibility) | `DaywellCalendarModule.tsx` (Month, Week, Day, Agenda + Event CRUD + `projectTasksForDateRange` task/recurrence overlay + `onNavigateToTask` / `requestedFocusDate`) | **Implemented** on Web (Stage 4 Node-verified); **Implemented in Code / Unverified** on Flutter (`CalendarView` CI-pending) |
| **Inbox & Quick Capture** | `domain/inbox/` · `InboxController` · `InboxRepository` | `QuickCaptureDialog` + Android `MethodChannel('com.example.personalmanagement/quick_capture')` | Quick Capture sheet in `App.tsx` | **Implemented** (cross-platform capture semantics differ slightly—see [cross-platform-parity.md](./cross-platform-parity.md)) |
| **Daily Rhythm (Stage A–C Workflows)** | `domain/daily_rhythm/` (`daily_rhythm_models.dart`, `daily_rhythm_contracts.dart`, `daily_rhythm_engine.dart`, `daily_rhythm_workflows.dart`) · `DailyRhythmController` · `DriftDailyRhythmRepository` (`daily_rhythm_days` v12) | `DailyFaithCheckInCard` (`MoreView`), `DailyTaskReviewCard` (`TasksView` Today & `MyDayPlanningView`), `DailyFinanceCloseCard` (`FinanceTransactionsTab`) via `daily_rhythm_workflow_widgets.dart` *(Dashboard & Calendar hub deferred to Stage D)* | `src/domain/dailyRhythm.ts`, `src/domain/dailyRhythmWorkflows.ts` · `dailyRhythmService.ts`, `dailyRhythmWorkflowService.ts` · `DailyFaithCheckInCard` (`App.tsx` More), `DailyTaskReviewCard` (`DaywellTasksModule.tsx` Today & `MyDayPlanningView.tsx`), `DailyFinanceCloseCard` (`DaywellFinanceModule.tsx` & `FinanceTransactionsTab.tsx`) *(Dashboard & Calendar hub deferred to Stage D)* | **Implemented** on Web (Stage A–C Node-verified); **Implemented in Code / Unverified** on Flutter (`DailyRhythmController`, `DriftDailyRhythmRepository`, SQLite v12, & Stage C workflows CI-pending; Stage D Dashboard/Calendar **Planned**) |
| **Search** | `DriftSearchRepository` (`ISearchRepository`) · `NoteDomainHelpers.matchesNoteSearchQuery` (`src/domain/noteHelpers.ts` / `note_helpers.dart`) | Exposed via controller/search helpers (`NotesView` `requestedNoteFocus` & `onRegisterPendingSaveFlush`) | Per-module search filters in Tasks/Notes/Finance/Calendar (`DaywellNotesModule` + `webNotesLifecycle` + `taskNotes`) | **Partially implemented** (Stage N4.1 completes Notes integration in `DriftSearchRepository` & Web Notes search/navigation; Flutter unified SQLite search repo exists without dedicated global search screen and Web uses per-module filters) |

---

## 3. Platform Service Contracts (`/flutter_app/lib/core/interfaces/platform_service_interfaces.dart`)

| Abstract Contract | Intended Responsibility | Current Implementation Status |
| :--- | :--- | :--- |
| `INotificationService` | Local offline task/commitment reminders | **Partially implemented** — `LocalNotificationService` creates 3 Android channels (`task`, `commitment`, `custom`), requests Android/iOS permissions, generates deterministic FNV-1a notification IDs, and schedules cancelable in-session stepped Dart `Timer`s (used by `TasksController` alongside Finance `syncFinanceDueReminders`), rather than OS background `zonedSchedule` alarms that survive app termination. Web reuses shared `Reminders` storage via `taskRemindersService` (`Notification` API + in-tab foreground timers/alerts, with no background delivery when closed). Runtime Android device alerts are **Unverified**. |
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
