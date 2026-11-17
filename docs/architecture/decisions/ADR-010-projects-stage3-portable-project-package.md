# ADR-010: Projects Stage 3 Portable `.daywellproject` Package Import & Export

- **Status:** accepted
- **Date / Version:** 2026-11-17 / Projects Stage 3 (`.daywellproject` `formatVersion = 1`)
- **Affected Docs:** [`docs/architecture/shared-foundation.md`](../shared-foundation.md), [`docs/architecture/data-and-persistence.md`](../data-and-persistence.md), [`docs/architecture/module-boundaries.md`](../module-boundaries.md), [`docs/architecture/cross-platform-parity.md`](../cross-platform-parity.md), [`docs/architecture/testing-standards.md`](../testing-standards.md)

---

## Context

Users prepare structured projects—such as outreach campaigns, video study curricula, or build trackers—on desktop browsers in Daywell Web Preview and need to transfer individual projects cleanly to Daywell on Android (and vice versa) completely offline without exporting the entire Daywell database, Finance ledger, unrelated Tasks, or user settings.

## Decision

1. **Canonical Versioned Package Contract (`shared_foundation/business_rules.json`):**
   - Define `projectPackage` in `shared_foundation/business_rules.json` (`formatId: "daywell_project_package"`, `currentFormatVersion: 1`, `minSupportedFormatVersion: 1`, `fileExtension: ".daywellproject"`), code-generated into `SHARED_PROJECT_PACKAGE_SPEC` (TypeScript) and `SharedProjectPackageSpec` (Dart).
   - Maintain a strict version boundary: `.daywellproject` `formatVersion: 1` is independent from `AppDatabase.schemaVersion` (`9`), `schema_contracts.json` (`9`), canonical exchange `schemaVersion` (`5`, `snapshotFormatVersion: 2`), Finance schema (`7`), and `.daywell` encrypted backup `format_version` (`1`).
2. **Self-Contained Single-Project Payload & Full History:**
   - Package JSON carries `formatId`, `formatVersion`, `exportedAt` (UTC ISO-8601), `sourcePlatform`, `project`, `trackingBlocks`, and `trackingRecords`.
   - Exports include **all** tracking blocks (both active and archived) and **all** tracking records (groups, items, checklists, schedules, append-only progress logs, and compensating corrections) belonging to the selected project.
   - Cross-module local references (`project.goalId` and `record.linkedTaskId`) are intentionally omitted on export and stripped/cleared on import so packages remain portable across independent device databases.
   - Encryption, cloud synchronization, Finance records, user settings, and unrelated Tasks/Notes/Goals are excluded by design.
3. **Fail-Closed Validation, New-Project Import Semantics & ID Remapping:**
   - Both Web (`src/domain/projectPackage.ts`) and Flutter (`flutter_app/lib/domain/projects/project_package_codec.dart`) parse and validate the full package structure, `formatId`, `formatVersion` bounds (rejecting unsupported future versions `> currentFormatVersion` fail-closed), canonical `YYYY-MM-DD` dates, block rules, topological parent/rollup/correction links, and `300`-char record title limits **before** mutating storage.
   - Valid imports always create a **new** project keeping the **original title intact** (no silent overwrite, merge UI, or title suffixing), assigning collision-free local IDs for the project, every block, and every record while consistently remapping `customFields.primaryBlockId`, counter `config.rollupSourceBlockId`, `parentRecordId`, and correction `metadata.compensatesRecordId`.
   - Repository writes are atomic (`_db.transaction(...)` in `DriftProjectsRepository`; pre-validated + rollback-guarded `localStorage` commit in `WebProjectsRepository`), leaving existing projects untouched on any failure.
4. **Platform I/O Without New Dependencies:**
   - **Web Preview:** Downloads `.daywellproject` JSON via browser `Blob` (`projectsService.downloadProjectPackage`) and imports via `<input type="file">` or JSON paste in `ProjectImportModal`.
   - **Flutter Android:** Exports a temporary `.daywellproject` file shared via existing `path_provider` + `share_plus` (`ProjectPackageIoService.exportPackageFile`), and imports via a dedicated `MethodChannel('com.example.personalmanagement/project_package')` Android SAF `ACTION_OPEN_DOCUMENT` picker (`MainActivity.kt`) paired with a JSON paste fallback in `ProjectImportDialog`, adding zero third-party pub dependencies.

## Justification

- Pure-domain codecs (`projectPackage.ts` and `project_package_codec.dart`) keep format rules testable without UI, DOM, or SQLite coupling and mirror each other against `/shared_foundation/fixtures/sample_project_package_v1.json`.
- Always creating a new project with fresh IDs eliminates merge ambiguity and cross-device primary-key collisions cleanly while preserving full project progress history.

## Migration Strategy

- `.daywellproject` `formatVersion = 1` establishes the initial baseline for project packages (`minSupportedFormatVersion = 1`, `currentFormatVersion = 1`).
- Future additive changes (`formatVersion = 2+`) MUST provide deterministic v1 -> vN upcasting during `parseAndValidate` per `ADR-007`, while unsupported future versions (`> currentFormatVersion`) fail closed with `unsupported_version` / `unsupportedVersion`.

## Affected Consumers

- `shared_foundation/{business_rules.json,fixtures/sample_project_package_v1.json}`, generated `src/domain/sharedFoundation.ts`, `flutter_app/lib/core/shared_foundation*.dart`.
- Web `src/domain/projectPackage.ts`, `src/data/projectsRepository.ts`, `src/services/projectsService.ts`, `src/components/projects/{ProjectImportModal.tsx,ProjectsWorkspaceView.tsx,ProjectDetailView.tsx}`.
- Flutter `flutter_app/lib/domain/projects/{project_package_codec.dart,project_contracts.dart}`, `data/repositories/projects_repository.dart`, `application/projects/projects_controller.dart`, `services/export/project_package_io_service.dart`, `ui/screens/projects/{project_import_dialog.dart,projects_workspace_tab.dart,project_detail_screen.dart}`, `android/.../MainActivity.kt`.

## Alternatives Considered

1. **Adding `file_picker` Pub Dependency for Android Import:** Rejected to avoid introducing new native Gradle/Flutter plugin surface when `ACTION_OPEN_DOCUMENT` via `MethodChannel` + JSON paste covers Android file picking cleanly with zero extra dependencies.
2. **Title Deduplication Suffix (`"(Imported)"`) or Interactive Merge Dialog:** Rejected per user requirement in favor of preserving the original project title as a clean new project without merge complexity.
3. **Reusing Full-Database Canonical Snapshot Format:** Rejected to prevent leaking unrelated Tasks, Notes, Finance ledger rows, and settings into single-project transfers.

## Consequences & Trade-Offs

- **Positive:** Seamless offline transfer of projects (all 4 block types, rollups, archived history, and progress logs) between Web Preview and Android; fail-closed validation protects existing databases.
- **Trade-Off:** Cross-module `goalId` and `linkedTaskId` references are intentionally cleared on transfer; Android SAF file picker runtime and Dart/Flutter unit tests remain **Unverified locally** pending CI and physical Android verification.
