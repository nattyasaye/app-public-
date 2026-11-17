# AGENTS.md — Daywell Repository Agent Instructions

> **Governance Stage:** 2 (AI Agent Instruction Integration)  
> **Primary Authority:** [`PROJECT_CONSTITUTION.md`](./PROJECT_CONSTITUTION.md)  
> **Scope:** General repository-wide instructions for all AI coding agents working on Daywell (**Flutter Android** and **Google AI Studio Web Preview**).

---

## 1. Mandatory Pre-Work Reading & Inspection

Before making non-trivial edits, designing features, or proposing replacements:

1. Read [`PROJECT_CONSTITUTION.md`](./PROJECT_CONSTITUTION.md).
2. Read the task-relevant guides under [`docs/architecture/`](./docs/architecture/overview.md):
   - **System Topology & Root Doc Index:** [`docs/architecture/overview.md`](./docs/architecture/overview.md)
   - **Tokens, Schemas, Rules, Dates & Codegen:** [`docs/architecture/shared-foundation.md`](./docs/architecture/shared-foundation.md)
   - **SQLite v7, Migrations, Integrity & Backup:** [`docs/architecture/data-and-persistence.md`](./docs/architecture/data-and-persistence.md)
   - **Layering, Controllers, Repos & Isolation:** [`docs/architecture/module-boundaries.md`](./docs/architecture/module-boundaries.md)
   - **5-Level UI Hierarchy, Theme & Conflicts:** [`docs/architecture/ui-design-system.md`](./docs/architecture/ui-design-system.md)
   - **Flutter vs. Web Parity & Known Gaps:** [`docs/architecture/cross-platform-parity.md`](./docs/architecture/cross-platform-parity.md)
   - **Test Suites, CI & Verification Limits:** [`docs/architecture/testing-standards.md`](./docs/architecture/testing-standards.md)
   - **Architectural Decision Records (ADRs):** [`docs/architecture/decisions/README.md`](./docs/architecture/decisions/README.md)
3. Inspect the live source files in the target area before proposing new abstractions or replacements.

---

## 2. Authority Hierarchy & Conflict Resolution

### General Repository Authority (Strict Top-Down Order)

1. **`PROJECT_CONSTITUTION.md`** — Supreme engineering authority.
2. **Accepted ADRs (`/docs/architecture/decisions/ADR-*.md`, `Status: accepted`)** — Binding approved architectural decisions beneath the constitution.
3. **`/docs/architecture/*.md`** — Authoritative topic-specific architecture documentation, which must remain consistent with the constitution and accepted ADRs.
4. **`/shared_foundation/*.json`** — Canonical machine-readable contracts, tokens, and shared specifications within their defined domains (`design_tokens.json`, `business_rules.json`, `schema_contracts.json`, `canonical_seed_database.json`, `calendar_test_vectors.json`).
5. **`/design_assets/`** — Approved visual references and SVG icons, subject to the dedicated 5-level UI authority hierarchy below.
6. **Generated Code & Platform Implementations** — `src/domain/sharedFoundation.ts`, `flutter_app/lib/core/shared_foundation*.dart`, Flutter Android app (`flutter_app/`), and Web Preview (`src/`), which must follow the applicable higher-level authorities.

**Proposed ADRs (such as `ADR-006`) are not binding.** Pre-constitution root documents (`DEVELOPMENT_ROADMAP.md`, `FINANCE_UI_AUDIT.md`, `IMPLEMENTATION_CHECKLIST.md`, `IMPLEMENTATION_STATUS.md`, `PRODUCTION_APK_AUDIT.md`, `INSTALLED_STORAGE_AND_APK_SIZE_AUDIT.md`, `STORAGE_OPTIMIZATION_FAILURE_INVESTIGATION.md`) are **historical/superseded records** indexed in `docs/architecture/overview.md` and MUST NOT override the Constitution, accepted ADRs, or `/docs/architecture/`. `MAYBE_LATER.md` is the deferred backlog ledger.

### Dedicated 5-Level UI Source-of-Truth Hierarchy

Per Constitution Section 2.4 and `ADR-005`, UI/design conflicts resolve strictly in this separate hierarchy:

1. **Approved Daywell product and visual design decisions** (`PROJECT_CONSTITUTION.md` §2.4 + accepted UI ADRs including `ADR-005`)
2. **Canonical shared design tokens & design-system contracts** (`/shared_foundation/design_tokens.json` and generated Dart, TypeScript, and CSS `daywellTokens.css` modules)
3. **Approved screen specifications & visual design assets** (`/design_assets/` screens and SVGs)
4. **Shared UI component specs & interaction/validation contracts** (`docs/architecture/ui-design-system.md`, `flutter_app/lib/ui/widgets/shared_ui_widgets.dart`, `src/components/ui/index.ts`)
5. **Platform-specific implementations** (`flutter_app/lib/ui/` and `src/`)

### Conflict Resolution Procedure

- If an instruction file conflicts with `PROJECT_CONSTITUTION.md` or an `accepted` ADR, **the Constitution and accepted ADR take precedence**.
- If an architecture guide (`/docs/architecture/*.md`) conflicts with an `accepted` ADR, **identify the discrepancy, follow the accepted decision, and flag the documentation for correction**.
- **Never** silently rewrite or reinterpret an accepted decision.
- If two `accepted` ADRs conflict, or an ambiguity cannot be resolved using `PROJECT_CONSTITUTION.md` (or a UI mockup conflicts with canonical tokens or accepted decisions), **identify the conflict explicitly and request clarification** rather than silently choosing one interpretation.

---

## 3. Capability Status Discipline

Always classify and describe repository capabilities using these five exact labels from `PROJECT_CONSTITUTION.md`:

- `Implemented` | `Partially implemented` | `Planned` | `Deprecated` | `Unverified`

Do not describe architectural requirements, partial scaffolds, or static UI mockups as complete or verified runtime features.

---

## 4. Mandatory Project-Specific Rules

### Architecture & Stage Control
- **Architecture first, implementation second:** Settle domain boundaries, data invariants, and UI contracts before non-trivial implementation.
- **Modular & lean:** Avoid unnecessary abstractions, parallel business engines, or overengineering.
- **Stage discipline:** Work in small, dependency-ordered stages. **Never** implement work outside the user's explicitly authorized stage (including future roadmap stages or `MAYBE_LATER.md` items). Stop cleanly when the authorized stage completes.
- **Architectural deviations:** Explain any proposed deviation clearly and obtain explicit approval before implementing it.

### Data, Persistence & Offline-First Operation
- **100% Offline-First:** Core workflows across Finance, Tasks, Notes, Calendar, and Inbox MUST work with zero mandatory cloud database, login wall, telemetry, or remote API.
- **Dual Persistence Separation:**
  - **Flutter Android (`flutter_app/`):** Drift SQLite (`personal_management.sqlite`, `schemaVersion => 7`) is the intended authoritative persistent store for Android, paired with local recovery/quarantine and `.daywell` PBKDF2/AES-GCM-256 encrypted export/restore.
  - **Web Preview (`src/`):** Uses browser `localStorage` (`daywell_canonical_database_v3` and module keys). **Never** confuse Web `localStorage` persistence with Flutter Drift SQLite persistence.
- **Preserve User Data:** Never silently discard, overwrite, or reset user-created data. Follow established ledger, atomic migration, fail-closed validation, and recovery rules.
- **Civil Calendar Precision:** Date-only fields use canonical `YYYY-MM-DD` under `Africa/Addis_Ababa` (`UTC+3`, no DST); timestamps use UTC ISO-8601; Ethiopian calendar preserves 13 months with Pagume 5/6 leap accuracy (`year % 4 == 3`).

### Finance Invariants & Current Reality
- **Accepted Requirements (`ADR-003`):** Integer minor units (`cents`, `1 ETB = 100 cents`, zero floats), balanced double-entry `JournalEntry` postings ($\sum \text{Debits} == \sum \text{Credits}$), system control accounts (`SYSTEM_CONTROL_ACCOUNT_IDS`), immutable void/supersede correction chains (never fabricate income on opening-balance edits), safe deletion/archive guards, and Stage 2.2 strict ETB first-release currency isolation.
- **Accurate Current Status (Do Not Overclaim):**
  - **Recovery Stage 2.1** is **Implemented** and conditionally accepted.
  - **Existing Finance v7 architecture** is **Partially implemented**, with identified defects and incomplete cross-platform integration.
  - **Recovery Stage 2.2 ETB currency isolation** is an approved architectural requirement that remains **incomplete and unaccepted**. **Never claim ETB isolation is complete.**

### UI & Cross-Platform Parity (Mandatory Pre-Change Procedure)
- **One Canonical Design System:** Flutter Android (`DaywellTheme`, `DaywellTypography`, `context.daywellColors`, `flutter_app/lib/ui/widgets/shared_ui_widgets.dart`) and Web Preview (`src/styles/daywellTokens.css` `--dw-*` CSS variables, `SHARED_DESIGN_TOKENS`, `src/components/ui/`) share **one** canonical design system sourced exclusively from `/shared_foundation/design_tokens.json`. Do not invent independent platform design systems, custom color palettes, or duplicate component families.
- **Mandatory Procedure Before Any UI Change or New Module:**
  1. Read `PROJECT_CONSTITUTION.md` (§2.4), `ADR-005`, `docs/architecture/ui-design-system.md`, and `docs/architecture/cross-platform-parity.md`.
  2. Inspect the existing implementations in **both** `flutter_app/lib/ui/` and `src/` (`src/App.tsx`, `src/index.css`, `src/components/`).
  3. Identify shared UI elements vs. permitted platform adaptations (`NavigationBar`/`NavigationRail`/`PopScope` and omitted bundled fonts on Android vs. responsive browser shell on Web). Preserve existing responsive layouts, accessibility targets (`48dp`/`44px`), and reusable components.
  4. Consume canonical tokens (`--dw-*`, `SHARED_DESIGN_TOKENS`, `DaywellTheme`, `context.daywellColors`) and shared primitives (`src/components/ui/`, `shared_ui_widgets.dart`)—never introduce hardcoded Web hex colors, raw Flutter `Color(0x...)` literals, or unallowlisted `Colors.*` calls. Any future module automatically inherits this canonical design system.
  5. Mark any non-live mockup views or sample cards explicitly as `Deprecated Prototype` (`DeprecatedPrototypeBanner` / `DaywellStatusBadge`).
  6. Evaluate shared UI changes across **both** Flutter Android and Web Preview and update `ui-design-system.md` / `cross-platform-parity.md` in the same stage.
- **Known Drift Reality:** Flutter `MoreView` and `DashboardView` are fully migrated (`0` `Colors.*` / `Color(0x...)`) and Web UI has `0` hardcoded hexes; 5 legacy Flutter UI files remain capped in `scripts/ui_consistency_allowlist.json` (shrink-only), and Flutter `CalendarPlaceholderView` remains a documented placeholder. Do not silently mask or worsen these gaps.
- **Intentional Adaptations:** Platform-specific adaptations (e.g., Material 3 `NavigationBar`/`NavigationRail` and omitted bundled fonts on Android vs. responsive browser shell on Web) must be intentional and documented in `docs/architecture/cross-platform-parity.md`.

### Backward Compatibility (Mandatory Going Forward — `ADR-007`)
- **Mandatory New-Work Standard (`PROJECT_CONSTITUTION.md` §2.11 & `ADR-007`):** Preserve backward compatibility for all new changes across database schemas (`AppDatabase.onUpgrade`), persisted models, backups/restores, snapshots/imports/exports, Shared Foundation contracts, internal interfaces, and Flutter/Web interoperability.
- **Data, Migration & Backup Discipline:** Review migration and persisted-data implications before changing schemas or contracts; preserve previously released backup formats until an explicit, approved deprecation decision retires them; test previous-version data/migrations where relevant; and fail safely on unsupported future versions (no arbitrary rolling version limit).
- **Breaking Changes & Historical Code:** Document and obtain explicit approval for any intentional breaking change (internal interface refactors are permitted when all in-repo consumers, implementations, and tests update together with verification). Do not perform unnecessary retroactive rewrites of untouched historical code; assess existing compatibility defects when modifying that area or when they pose material data-integrity or functionality risks.

---

## 5. Platform-Specific Engineering Directions

### Flutter Android (`flutter_app/`)
- Respect strict unidirectional layering: `core/` -> `domain/` -> `application/` -> `data/` & `services/` -> `ui/`.
- Keep `flutter_app/lib/domain/` free of Flutter widget and Drift/SQLite imports.
- UI widgets communicate via module controllers (`FinanceController`, `TasksController`, `NotesController`, `CalendarController`, `InboxController`) or thin `AppStateManager` callbacks—never raw SQL from UI.
- **Isolation Guard:** `flutter_app/lib/` and `flutter_app/pubspec.yaml` MUST NEVER import or bundle `src/`, `/design_assets/`, or Web Preview mockups.
- **Generated Files:** Never manually edit `flutter_app/lib/core/shared_foundation.dart`, `flutter_app/lib/core/shared_foundation_core.dart`, or Drift `*.g.dart` files. Run `npm run sync-foundation` after editing `/shared_foundation/*.json`, and `dart run build_runner` in Flutter environments when Drift/codegen changes.

### Google AI Studio Web Preview (`src/`)
- Respect layering: `domain/` -> `data/` & `services/` -> `components/` & `App.tsx`. Keep `src/domain/` free of React/DOM imports.
- **Generated Files:** Never manually edit `src/domain/sharedFoundation.ts` or `src/styles/daywellTokens.css`; regenerate via `npm run sync-foundation` (`scripts/sync_foundation.mjs`).
- Keep `SharedStateBridge` canonical JSON schemas (`schemaVersion: 5` exchange / `7` Finance / `4..8` ingest bounds) and pure TypeScript engines (Calendar math, Finance math, `backupCrypto.ts`) aligned with `/shared_foundation/` parity tests.

---

## 6. Same-Stage Documentation & Honest Verification

### Documentation Maintenance
When an authorized stage changes architecture, database schemas, shared foundation contracts, design tokens, module boundaries, or cross-platform behavior, update the affected guides in `/docs/architecture/` and create/update ADRs in `/docs/architecture/decisions/` **within the same stage**.

### Verification & Reporting Standards
- **Only report checks you actually executed** in the current session (or verified directly from CI logs). Never fabricate test results, assume repository state, or claim unexecuted builds passed.
- **Local Container vs. CI Truth:**
  - Local container supports Node.js checks: `npm run check-foundation`, `npm run check-architecture`, `npm run check-migrations`, `npm run check-ui`, `npm test`, `npm run lint` (`check-foundation && check-architecture && check-migrations && check-ui && tsc --noEmit`), `npm run build`.
  - Local container does **not** install Flutter SDK, Dart, Java/Android SDK, or Android hardware/emulator (`flutter analyze`, `flutter test`, `dart format`, and Gradle APK builds run in `.github/workflows/android.yml`).
- Always separate **automated test evidence**, **static inspection**, and **unverified runtime/physical-device behavior** in final reports.

---

## 7. Instruction Discovery & Tool Behavior

- **`AGENTS.md`** follows the open repository instruction convention automatically discovered by compatible agents (e.g., Codex, Cursor, Windsurf, Google Jules, GitHub Copilot coding agent).
- Automated loading by external tools cannot be verified inside this local container; when working in tools that do not auto-load `AGENTS.md`, explicitly attach or reference `AGENTS.md` and `PROJECT_CONSTITUTION.md` at session start.
