# Daywell — Testing, Verification & Build Governance Standards

> **Status Legend:** `Implemented` | `Partially implemented` | `Planned` | `Deprecated` | `Unverified`  
> Every verification command, test count, CI step, and environment limitation in this document reflects live inspection and executed checks as of Governance Stage 1.

---

## 1. Two Verification Environments (Local Container vs. GitHub Actions CI)

Daywell maintains two test harnesses (`npm` / `tsx` for Shared Foundation & Web TypeScript, and `flutter test` / `flutter analyze` for Dart & Drift SQLite). Understanding which checks run where prevents false confidence:

| Capability / Tool | Local Workspace Container | GitHub Actions CI (`.github/workflows/android.yml`) |
| :--- | :--- | :--- |
| **Node.js / `tsx` / `tsc` / `vite`** | **Available** — runs locally and fast | **Available** — Node.js `22` (`test` job) |
| **Flutter SDK (`3.24.5`) & Dart** | **NOT INSTALLED** (`which flutter dart` missing) | **Available** — `subosito/flutter-action@v2` (`3.24.5`, stable) |
| **Java 17 / Android SDK / Gradle APK Build** | **NOT INSTALLED** | **Available** — builds & signs `arm64-v8a` release APK (`build-release` job) |
| **Physical Android Device / Emulator** | **Unavailable** | **Unavailable** (automated APK signature check only; no instrumentation/device run) |

---

## 2. Verified TypeScript & Shared Foundation Test Suite

- **Runner:** `npm test` → `tsx --test src/domain/*.test.ts src/domain/date/*.test.ts` ([`package.json`](../../package.json))
- **Foundation Freshness & Contract Gate:** `npm run check-foundation` → `node scripts/sync_foundation.mjs --check` (non-mutating freshness, 5-file JSON schema validation, Git-diffed `ADR-007` baseline non-regression + accepted-ADR validation, and `AppDatabase.schemaVersion` guard)
- **Architecture Boundary Gate:** `npm run check-architecture` → `node scripts/check_architecture_boundaries.mjs` (TS/Dart layer imports, narrow allowlist manifest, `pubspec.yaml` asset isolation, and direct Web domain browser-global checks)
- **Migration Compatibility Gate:** `npm run check-migrations` → `node scripts/check_migration_compatibility.mjs` (static verification of `AppDatabase.schemaVersion >= 13`, explicit fail-closed `if (from > to) { throw ...; }` guard at the top of `onUpgrade`, absence of nonexistent Drift `onDowngrade`, ascending `from < 2..13` + sequential upgrade steps, forbidden `fallbackToDestructiveMigration`, and required delegates)
- **UI Consistency & Design-Token Gate:** `npm run check-ui` → `node scripts/check_ui_consistency.mjs` (verifies `design_tokens.json` parity across `src/styles/daywellTokens.css`, `src/domain/sharedFoundation.ts`, `flutter_app/lib/core/shared_foundation.dart`, and `src/index.css`; enforces zero hardcoded hex literals in Web UI; blocks raw `Color(0x...)` and unallowlisted/expanding `Colors.*` in Flutter UI via `scripts/ui_consistency_allowlist.json`; verifies 16-family shared UI primitive parity between `flutter_app/lib/ui/widgets/` and `src/components/ui/`)
- **Typecheck & Verification Lint:** `npm run lint` → `npm run check-foundation && npm run check-architecture && npm run check-migrations && npm run check-ui && tsc --noEmit` (or `npx tsc --noEmit` for TypeScript-only check)
- **Last Locally Verified Run:** Re-verified on Stage 5 via `npm test`, `npm run lint`, and `npm run build` (see session verification output; Flutter `build_runner`, `dart format`, `flutter analyze`, and `flutter test` remain **Unverified locally — pending CI**).

### Inventory of TypeScript Test Files (`src/domain/` & `src/domain/date/`)

| Focus Area | Verified Test Files |
| :--- | :--- |
| **Ethiopian Calendar & Civil Dates** | `src/domain/date/dateFoundation.test.ts` |
| **SQLite Schema & Migration Contracts** | `src/domain/date/sqliteMigrationVerification.test.ts`, `src/domain/androidUpdateDataPreservation.test.ts`, `src/domain/stage2CleanInitialization.test.ts`, `src/domain/stage3BuildBoundarySeparation.test.ts`, `src/domain/stage4Contracts.test.ts` |
| **Shared Foundation, UI Governance & Portability Parity** | `src/domain/sharedFoundationParity.test.ts`, `src/domain/uiConsistencyGovernance.test.ts`, `src/domain/stage32FoundationGovernance.test.ts`, `src/domain/stage33GovernanceEnforcement.test.ts`, `src/domain/stage342BackupValidation.test.ts`, `src/domain/sharedStateBridge.test.ts`, `src/domain/coreModulesIntegration.test.ts` |
| **Finance v6/v7 Double-Entry, Stage 2.2 & Stage 5 SMS** | `src/domain/doubleEntryFinance.test.ts`, `src/domain/financeV7WebParity.test.ts`, `src/domain/stage22CurrencyIsolation.test.ts`, `src/domain/stageF4ReportingAndPortability.test.ts`, `src/domain/financeStage1TransferAndExpenseFees.test.ts`, `src/domain/financeStage2RemoveTransactionNote.test.ts`, `src/domain/financeStage3EtbOnlyCleanup.test.ts`, `src/domain/stage5FinanceSms.test.ts`, `src/domain/batch5FinanceFoundation.test.ts`, `src/domain/batch6FinanceIntegrity.test.ts`, `src/domain/batch7FinanceArchitecture.test.ts` |
| **Navigation, Tasks, Projects, Notes & Inbox Architecture** | `src/domain/batch1NavigationFoundation.test.ts`, `src/domain/batch2FormsInputsNavigation.test.ts`, `src/domain/batch8TasksArchitecture.test.ts`, `src/domain/projectsStage1.test.ts`, `src/domain/projectsStage2Workspace.test.ts`, `src/domain/projectPackage.test.ts`, `src/domain/batch9NotesInboxArchitecture.test.ts`, `src/domain/batch10Stage2Consolidation.test.ts`, `src/domain/stageN12NoteDomainHelpers.test.ts`, `src/domain/stageN13WebNotesLifecycle.test.ts`, `src/domain/stageN21NoteMarkdown.test.ts`, `src/domain/stageN22NoteEditorFormatting.test.ts`, `src/domain/stageN23NoteChecklists.test.ts`, `src/domain/stageN24NoteInternalLinks.test.ts`, `src/domain/stageN31FlutterNotesUiCompliance.test.ts`, `src/domain/stageN41NotesSearchIntegration.test.ts` |
| **Daily Rhythm (Stage A Engine, Stage B Persistence/Backup & Stage C Workflows)** | `src/domain/dailyRhythm.test.ts`, `src/domain/stageBDailyRhythmPersistence.test.ts`, `src/domain/stageCDailyRhythmWorkflows.test.ts` |

---

## 3. Flutter / Dart Test Suite (CI-Executed; Local Status: `Unverified`)

Because Flutter/Dart is not installed in the local workspace container, Dart tests and `flutter analyze` are verified via GitHub Actions CI, while their local execution in this container is **Unverified**.

- **CI Pipeline Commands (`.github/workflows/android.yml` `test` job):**
  1. `flutter pub get`
  2. `dart run build_runner build --delete-conflicting-outputs`
  3. `dart format --output=none --set-exit-if-changed lib test`
  4. `flutter analyze`
  5. `flutter test`

### Inventory of Flutter Test Files (`flutter_app/test/`)

| Focus Area | Verified Test Files (`*_test.dart`) |
| :--- | :--- |
| **Foundation, Tokens & Calendar Dates** | `shared_design_tokens_test.dart`, `ethiopian_calendar_test.dart`, `shared_date_foundation_test.dart` |
| **Theme, Shell & Shared UI Widgets** | `daywell_theme_test.dart`, `daywell_shared_primitives_test.dart`, `daywell_shared_patterns_test.dart`, `daywell_shell_test.dart`, `dashboard_view_test.dart` |
| **Database Migrations & Consolidation** | `database_migration_test.dart`, `stage2_consolidation_test.dart` |
| **Finance v6 / v7 / Stage 4 / Stage 2.2 / Stage 5–6 SMS** | `financial_engine_test.dart`, `double_entry_finance_test.dart`, `finance_contracts_v6_test.dart`, `finance_engine_v6_test.dart`, `finance_v6_migration_test.dart`, `finance_repository_test.dart`, `finance_controller_test.dart`, `finance_v7_domain_test.dart`, `finance_v7_migration_test.dart`, `finance_v7_stage416_test.dart`, `stage4_finance_test.dart`, `finance_stage_f3_composer_test.dart`, `finance_stage_f4_test.dart`, `finance_stage1_transfer_and_expense_fees_test.dart`, `finance_stage2_remove_transaction_note_test.dart`, `finance_stage3_etb_only_cleanup_test.dart`, `stage5_finance_sms_test.dart`, `stage6_android_sms_inbox_test.dart` |
| **Tasks, Projects, Notes, Inbox, Search, Notifications & Calendar** | `task_and_project_test.dart`, `projects_stage1_test.dart`, `project_package_test.dart`, `inbox_repository_test.dart`, `notes_inbox_architecture_test.dart`, `local_search_test.dart`, `stage5_notes_notifications_calendar_test.dart`, `stage_n12_note_domain_helpers_test.dart`, `stage_n14_notes_lifecycle_and_save_integrity_test.dart`, `stage_n21_note_markdown_test.dart`, `stage_n22_note_editor_formatting_test.dart`, `stage_n23_note_checklists_test.dart`, `stage_n24_note_internal_links_test.dart`, `stage_n31_notes_ui_compliance_test.dart`, `stage_n41_notes_shared_search_test.dart` |
| **Daily Rhythm (Stage A Engine, Stage B Persistence/Backup & Stage C Workflows)** | `daily_rhythm_engine_test.dart`, `stageb_daily_rhythm_persistence_and_backup_test.dart`, `stagec_daily_rhythm_workflows_test.dart` |
| **Encrypted Backup, Version Bounds & Restore** | `stage6_backup_restore_test.dart`, `stage342_backup_snapshot_validation_test.dart`, `stage344_snapshot_fidelity_restore_test.dart` |
| **Test Helpers** | `flutter_app/test/support/` |

---

## 4. Android Release Build & APK Configuration Truth

**Verified in `.github/workflows/android.yml` (sole active CI workflow after removing duplicate `flutter_app/.github/workflows/android.yml`) and `flutter_app/android/app/build.gradle`:**
- **Triggers & Job Gating:** `test` job checks out full history (`fetch-depth: 0` for Git baseline diffing) and runs on `push` / `pull_request` for `main` / `master` and `workflow_dispatch` (executing `npm run check-foundation`, `npm run check-architecture`, `npm run check-migrations`, `npm run check-ui`, `npm test`, `npm run lint`, and Flutter format/analyze/test checks); `build-release` APK packaging runs strictly on `push` to `main` / `master` or `workflow_dispatch` (never on pull requests).
- **Target ABI:** Standalone `android-arm64` (`flutter build apk --release --target-platform android-arm64`), artifact `daywell-arm64-v8a-release-apk`.
- **SDK Levels (`build.gradle`):** `compileSdk = 35`, `ndkVersion = "25.1.8937393"`, `minSdk = 26`, `targetSdk = 34`, `version: 1.0.2+3` (`pubspec.yaml`), `multiDexEnabled = true`, `coreLibraryDesugaringEnabled = true`.
- **Fail-Closed Release Signing Guard:** Both `flutter_app/android/app/build.gradle` and `.github/workflows/android.yml` now fail closed whenever any `*Release*` build runs without a persistent keystore (`flutter_app/android/app/release.keystore` decoded from `KEYSTORE_BASE64` or local `flutter_app/android/key.properties`) and complete credentials (`KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` defaulting to `KEYSTORE_PASSWORD`). Ephemeral CI `keytool -genkeypair` fallback has been removed so CI cannot silently rotate signing certificates and break in-place updates (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). `.gitignore` excludes `*.keystore`, `*.jks`, `*.p12`, and `flutter_app/android/key.properties`.
- **CI APK Metadata & Certificate Verification:** `build-release` validates `pubspec.yaml` `X.Y.Z+N` version format (and optional `workflow_dispatch` `build_number >= pubspec`), inspects `aapt2 dump badging` (`package: name='com.example.personalmanagement'`, `versionCode`, `versionName`, `sdkVersion:'26'` / `minSdkVersion:'26'` with `aapt2 dump xmltree` `uses-sdk` fallback, non-`application-debuggable`), checks standalone `arm64-v8a` completeness, verifies `apksigner verify --verbose --print-certs` (rejecting `CN=Android Debug` or `CN=Daywell CI Release`), and removes decoded keystore files afterward.
- **Important Contradiction with Legacy Root Docs (`R8 / Shrinking`):** `build.gradle` currently sets:
  ```gradle
  minifyEnabled false
  shrinkResources false
  ```
  Historical root audits (`INSTALLED_STORAGE_AND_APK_SIZE_AUDIT.md`, `STORAGE_OPTIMIZATION_FAILURE_INVESTIGATION.md`) discussed enabling R8 shrinking, which is **currently disabled** in live Gradle config.
- **Unverified Runtime Hardware Behaviors:** Physical Android device APK installation, `apksigner` verification output on real CI artifacts, in-place SQLite upgrade preservation on real hardware across signed versions, `MainActivity.kt` share-intent ingestion, and Android 13+ notification permissions (`flutter_local_notifications` scheduled delivery) remain **Unverified** outside CI/device testing.

---

## 5. Verification Governance Rules for All Future Stages

1. **Zero Fabricated Results:** Agents and engineers MUST ONLY report tests, linters, builds, or manual checks they actually ran in the current session or read directly from a verified CI log.
2. **Stage-Appropriate Verification Scope:**
   - **Documentation-only stage (like Governance Stage 1):** Verify Markdown paths/links, run non-mutating health checks (`npm test`, `npx tsc --noEmit`), and confirm zero unintended edits to runtime code or historical docs.
   - **Shared Foundation / TypeScript / Web stage:** Run `npm run sync-foundation` (if JSON changed), `npm run lint` (`tsc --noEmit`), `npm test`, and `npm run build` / browser verification as appropriate.
   - **Flutter / Dart / Schema stage:** Must update/add matching `flutter_app/test/*_test.dart` coverage and pass CI (`dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`, and `build_runner` if Drift/Riverpod codegen changed); explicitly mark Flutter checks as **Unverified locally — pending CI** whenever executed from a container without the Flutter SDK.
3. **Cross-Platform Vector Parity:** Any modification to date math, Safe Harbor math, double-entry balancing, or backup crypto MUST include parity test cases proving identical results across TypeScript and Dart.
4. **No Silent Test Weakening:** Never delete, skip (`skip: true`), or loosen assertions in existing failing tests just to turn a suite green unless an approved stage explicitly supersedes the tested requirement and updates its ADR/docs.
5. **Backward-Compatibility & Forward Migration Verification ([ADR-007](./decisions/ADR-007-mandatory-backward-compatibility.md)):**
   - Changes to schemas, persisted models, backup envelopes, snapshots, Shared Foundation contracts, or internal interfaces MUST include proportionate verification of preserved SQLite migration paths, deterministic upcasting of documented previous-version payloads, coordinated updates across all affected in-repo consumers, and fail-closed rejection of unsupported future versions.
   - **Stage 3.4.3 Real SQLite Forward-Migration & Rollback Rules:** Every schema increment from `schemaVersion => 7` (`v8+`) MUST be tested against a **real file-backed SQLite database** (never mock databases alone) covering: (a) clean opening and relational preservation on `v7`, (b) forward upgrade data/FK preservation and safe column defaults, (c) idempotent reopen without re-executing `onUpgrade`, (d) mid-migration DDL+DML failure and `PRAGMA foreign_key_check` abort proving complete SQLite transaction rollback (`user_version` unchanged, partial DDL/DML reverted), and (e) fail-closed rejection when opening a newer `from > to` database (`UnsupportedDatabaseVersionException` / `DatabaseFailureCategory.unsupportedSchemaVersion`, `canRetryUpgrade == false`, and untouched database bytes).
   - *(Current Status: Stage 3.2/3.3/3.4.2/3.4.2.1/3.4.3/3.4.4 and Projects Stage 1/1.1 Node tests—including `projectsStage1.test.ts`, `sharedStateBridge.test.ts`, and `stage342BackupValidation.test.ts`—plus static migration/architecture/foundation gates execute locally; Flutter/Dart checks including `dart run build_runner build --delete-conflicting-outputs`, `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `database_migration_test.dart` (`v1->v9`, `v2->v9`, `v5->v9`, `v4->v9` rollback), `projects_stage1_test.dart`, `stage342_backup_snapshot_validation_test.dart`, and `stage344_snapshot_fidelity_restore_test.dart` remain **Unverified locally** due to absent Flutter/Dart SDK and await GitHub Actions CI execution.)*
