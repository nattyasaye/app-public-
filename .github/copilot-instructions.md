# Daywell — GitHub Copilot Repository Instructions

> **Governance Stage:** 2 (AI Agent Instruction Integration)  
> **Primary Authority:** [`PROJECT_CONSTITUTION.md`](../PROJECT_CONSTITUTION.md)  
> **General Agent Entry Point:** [`AGENTS.md`](../AGENTS.md)

---

## 1. Before Suggesting or Writing Non-Trivial Code

1. Read [`PROJECT_CONSTITUTION.md`](../PROJECT_CONSTITUTION.md) and the relevant architecture docs under `/docs/architecture/`:
   - `overview.md` (topology, verified status, historical root-doc index)
   - `shared-foundation.md` (`/shared_foundation/*.json` & `sync-foundation`)
   - `data-and-persistence.md` (Drift SQLite v7, migrations, Web `localStorage`, backup crypto)
   - `module-boundaries.md` (layering, controllers, repositories, Flutter/Web isolation)
   - `ui-design-system.md` (5-level UI hierarchy, tokens, documented conflicts)
   - `cross-platform-parity.md` (Flutter Android vs. Web Preview parity matrix)
   - `testing-standards.md` (Node/TS checks vs. CI-only Flutter/Android checks)
   - `decisions/README.md` (`accepted` vs. `proposed` ADRs)
2. Inspect existing implementations before proposing replacements, new helpers, or new abstractions.

---

## 2. Authority Hierarchy & Conflict Resolution

### General Repository Authority (Strict Top-Down Order)
1. `PROJECT_CONSTITUTION.md` — Supreme engineering authority.
2. `accepted` ADRs in `/docs/architecture/decisions/ADR-*.md` — Binding approved architectural decisions beneath the constitution (**`proposed` ADRs such as `ADR-006` are not binding**).
3. `/docs/architecture/*.md` — Authoritative topic-specific architecture documentation, which must remain consistent with the constitution and accepted ADRs.
4. `/shared_foundation/*.json` — Canonical machine-readable contracts, tokens, and shared specifications within their defined domains.
5. `/design_assets/` — Approved visual references, subject to the dedicated 5-level UI authority hierarchy below.
6. Generated code & platform implementations (`flutter_app/`, `src/`) — Must follow the applicable higher-level authorities.

Do **not** treat pre-constitution root Markdown files (`DEVELOPMENT_ROADMAP.md`, `FINANCE_UI_AUDIT.md`, `IMPLEMENTATION_CHECKLIST.md`, `IMPLEMENTATION_STATUS.md`, `PRODUCTION_APK_AUDIT.md`, `INSTALLED_STORAGE_AND_APK_SIZE_AUDIT.md`, `STORAGE_OPTIMIZATION_FAILURE_INVESTIGATION.md`) as overriding authority. `MAYBE_LATER.md` is the deferred backlog ledger.

### Dedicated 5-Level UI Source-of-Truth Hierarchy
1. Approved Daywell product and visual design decisions (Constitution §2.4 + accepted UI ADRs including `ADR-005`)
2. Canonical shared design tokens (`/shared_foundation/design_tokens.json` & generated Dart, TypeScript, and `src/styles/daywellTokens.css` modules)
3. Approved screen specs and visual assets (`/design_assets/`)
4. Shared UI component specs & interaction/validation contracts (`/docs/architecture/ui-design-system.md`, `flutter_app/lib/ui/widgets/shared_ui_widgets.dart`, `src/components/ui/index.ts`)
5. Platform-specific Flutter (`flutter_app/lib/ui/`) and Web Preview (`src/`) implementations

**Conflict Rules:**
- If instructions conflict with `PROJECT_CONSTITUTION.md` or an `accepted` ADR, the Constitution and accepted ADR govern.
- If an architecture guide (`/docs/architecture/*.md`) conflicts with an `accepted` ADR, **identify the discrepancy, follow the accepted decision, and flag the documentation for correction**.
- **Never** silently rewrite or reinterpret an accepted decision.
- If two `accepted` ADRs conflict, or an ambiguity cannot be resolved using `PROJECT_CONSTITUTION.md`, **request clarification** instead of silently picking a convenient interpretation.

---

## 3. Core Architecture, Data & UI Rules

- **Architecture & Scope:** Work in small, dependency-ordered stages. Do not implement unrequested features, future roadmap stages, or `MAYBE_LATER.md` items. Do not add new dependencies without explicit justification and approval.
- **Generated-Code Boundaries:** Never manually edit `src/domain/sharedFoundation.ts`, `src/styles/daywellTokens.css`, `flutter_app/lib/core/shared_foundation_core.dart`, `flutter_app/lib/core/shared_foundation.dart`, or Drift `*.g.dart` outputs. Edit `/shared_foundation/*.json` and run `npm run sync-foundation` only when authorized.
- **Layer & Platform Isolation:**
  - Flutter (`flutter_app/lib/`): `core/` -> `domain/` -> `application/` -> `data/` & `services/` -> `ui/`. Keep `domain/` free of Flutter and Drift imports; never import or bundle `src/` or `/design_assets/`.
  - Web Preview (`src/`): `domain/` -> `data/` & `services/` -> `components/` & `App.tsx`. Keep `domain/` free of React/DOM imports.
- **Offline-First & Persistence:** Zero mandatory cloud dependency. Drift SQLite (`schemaVersion => 8`) is Android's authoritative persistent store; Web Preview uses browser `localStorage`. Never silently discard, overwrite, or reset user-created data. Preserve non-destructive Drift SQLite upgrade safety.
- **Finance Status & Invariants (`ADR-003`):** Use integer minor units (`cents`, `1 ETB = 100 cents`), balanced double-entry postings, immutable void/supersede chains, and safe deletion/archive guards. **Accurate status:** Recovery Stage 2.1 is `Implemented` (conditionally accepted); Finance v7 is `Partially implemented` with open defects/integration gaps; Recovery Stage 2.2 ETB currency isolation is **incomplete and unaccepted**—never claim it is complete.
- **UI & Parity (Mandatory Pre-Change Procedure):** Before modifying or creating UI on either platform: (1) read Constitution §2.4, `ADR-005`, `docs/architecture/ui-design-system.md`, and `docs/architecture/cross-platform-parity.md`; (2) inspect both `flutter_app/lib/ui/` and `src/`; (3) identify shared elements vs. documented adaptations (`docs/architecture/cross-platform-parity.md`) and preserve responsive/accessibility work and reusable components; (4) consume canonical tokens (`DaywellTheme` / `context.daywellColors` on Flutter; `--dw-*` CSS vars & `SHARED_DESIGN_TOKENS` on Web) and shared primitives (`shared_ui_widgets.dart` ↔ `src/components/ui/`) with zero hardcoded hexes or unallowlisted `Colors.*`; (5) label non-live static mockups `Deprecated Prototype`; (6) evaluate both platforms when shared UI changes and ensure new modules inherit canonical tokens and primitives automatically.
- **Backward Compatibility (`ADR-007` & Constitution §2.11):** Preserve compatibility for all new changes across schemas, persisted models, backups/restores, snapshots/imports/exports, Shared Foundation contracts, and Flutter/Web parity. Review migration and persisted-data impacts, preserve previously released backup formats until explicitly deprecated, test previous-version data where relevant, fail safely on unsupported future versions, and document/obtain approval for intentional breaking changes (internal interface refactors require updating all affected consumers/tests together). Avoid unnecessary retroactive rewrites of untouched historical code, assessing existing defects when touched or on material data-integrity/functionality risk.

---

## 4. Documentation, Assumptions & Verification

- **Same-Stage Doc Sync:** Update affected `/docs/architecture/` guides and `/docs/architecture/decisions/` ADRs in the same stage when architectural contracts, schemas, tokens, module boundaries, or parity behaviors change.
- **Honest Claims:** Classify status using `Implemented`, `Partially implemented`, `Planned`, `Deprecated`, or `Unverified`. Clearly flag assumptions and unverified items.
- **Verification Discipline:** Report only checks actually executed (`npm run check-ui`, `npm test`, `npm run lint`, `npm run build` in Node environments; `flutter analyze`, `flutter test`, `dart format`, and Gradle APK builds in Flutter/CI environments). Never claim Flutter/Android device behavior passed unless executed on-device or in verified CI.

---

## 5. Discovery & Scope Note

- `.github/copilot-instructions.md` is GitHub Copilot's standard repository-wide instruction file (applied across Copilot Chat, supported IDEs, and Copilot Coding Agent on GitHub.com).
- Live Copilot instruction ingestion is **unverified** inside this local workspace container.
- Governance Stage 2 intentionally uses a single repository-wide file rather than path-specific `.github/instructions/*.instructions.md` files.
