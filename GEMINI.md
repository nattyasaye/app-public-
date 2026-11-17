# GEMINI.md — Daywell Gemini Agent Instructions

> **Governance Stage:** 2 (AI Agent Instruction Integration)  
> **Primary Authority:** [`PROJECT_CONSTITUTION.md`](./PROJECT_CONSTITUTION.md)  
> **General Agent Entry Point:** [`AGENTS.md`](./AGENTS.md)

---

## 1. Instruction Discovery & Loading Procedure (Important)

Do **not** assume `GEMINI.md` is automatically loaded across every Gemini surface:

| Gemini Environment | Discovery Behavior | Required Action |
| :--- | :--- | :--- |
| **Google AI Studio Build / Web Chat** *(primary project workflow)* | **Not verified as auto-loaded** from repository files into system instructions. | **Manual attachment / prompt reference required:** Explicitly instruct Gemini at session start: *"Read and follow `PROJECT_CONSTITUTION.md`, `GEMINI.md`, and the relevant `/docs/architecture/` files before making changes."* |
| **Gemini CLI** | Automatically discovers and concatenates `GEMINI.md` files hierarchically (`~/.gemini/GEMINI.md`, workspace root/ancestors, and subdirectories). | Inspect active loaded context with `/memory show` and refresh after edits with `/memory reload`. *(Live CLI loading not tested in this container.)* |
| **Gemini Code Assist (IDE)** | Automatic `GEMINI.md` loading is **unverified** in this environment. | Explicitly reference `GEMINI.md` and `PROJECT_CONSTITUTION.md` in chat/context unless IDE rules confirm automatic ingestion. |

---

## 2. Authority Hierarchy & Conflict Resolution

Gemini agents MUST follow the exact same authority hierarchy and status discipline as [`AGENTS.md`](./AGENTS.md) and [`PROJECT_CONSTITUTION.md`](./PROJECT_CONSTITUTION.md):

### General Repository Authority (Strict Top-Down Order)
1. `PROJECT_CONSTITUTION.md` — Supreme engineering authority.
2. `accepted` ADRs in `/docs/architecture/decisions/ADR-*.md` — Binding approved architectural decisions beneath the constitution (**`proposed` ADRs like `ADR-006` are not binding**).
3. `/docs/architecture/*.md` — Authoritative topic-specific architecture documentation, which must remain consistent with the constitution and accepted ADRs.
4. `/shared_foundation/*.json` — Canonical machine-readable contracts, tokens, and shared specifications within their defined domains.
5. `/design_assets/` — Approved visual references, subject to the dedicated 5-level UI authority hierarchy below.
6. Generated code (`src/domain/sharedFoundation.ts`, `flutter_app/lib/core/shared_foundation*.dart`) & platform implementations (`flutter_app/`, `src/`) — Must follow the applicable higher-level authorities.

Historical root Markdown files (`DEVELOPMENT_ROADMAP.md`, `FINANCE_UI_AUDIT.md`, `IMPLEMENTATION_CHECKLIST.md`, `IMPLEMENTATION_STATUS.md`, `PRODUCTION_APK_AUDIT.md`, `INSTALLED_STORAGE_AND_APK_SIZE_AUDIT.md`, `STORAGE_OPTIMIZATION_FAILURE_INVESTIGATION.md`) are **historical/superseded** and MUST NOT override the Constitution, accepted ADRs, or `/docs/architecture/`.

### Dedicated 5-Level UI Source-of-Truth Hierarchy
1. Approved Daywell product & visual design decisions (Constitution §2.4 + accepted UI ADRs including `ADR-005`)
2. Canonical shared design tokens (`/shared_foundation/design_tokens.json` & generated Dart, TypeScript, and `src/styles/daywellTokens.css` modules)
3. Approved screen specs & visual assets (`/design_assets/`)
4. Shared UI component specs & interaction/validation contracts (`/docs/architecture/ui-design-system.md`, `flutter_app/lib/ui/widgets/shared_ui_widgets.dart`, `src/components/ui/index.ts`)
5. Platform-specific Flutter (`flutter_app/lib/ui/`) and Web Preview (`src/`) implementations

**Conflict Rules:**
- If `GEMINI.md` conflicts with `PROJECT_CONSTITUTION.md` or an `accepted` ADR, the Constitution and accepted ADR govern.
- If an architecture guide (`/docs/architecture/*.md`) conflicts with an `accepted` ADR, **identify the discrepancy, follow the accepted decision, and flag the documentation for correction**.
- **Never** silently rewrite or reinterpret an accepted decision.
- If two `accepted` ADRs conflict, or an ambiguity cannot be resolved using `PROJECT_CONSTITUTION.md`, **request clarification** rather than silently choosing one interpretation.

---

## 3. Gemini Operational Rules (Mandatory Workflow)

1. **Read First, Inspect Live Code:** Before non-trivial changes, read `PROJECT_CONSTITUTION.md`, the relevant `/docs/architecture/*.md` docs, and the actual target source files across **both** Flutter and Web when modifying UI.
2. **Understand Before Replacing:** Inspect existing Flutter (`flutter_app/lib/ui/`) and Web (`src/`) implementations thoroughly before introducing new abstractions or replacing working modules.
3. **Zero Duplication & Zero Bloat:** Avoid unnecessary file creation, duplicated state stores, parallel business logic, and separate platform UI design systems.
4. **Never Edit Generated Files Manually:**
   - Do NOT hand-edit `src/domain/sharedFoundation.ts`, `src/styles/daywellTokens.css`, `flutter_app/lib/core/shared_foundation_core.dart`, `flutter_app/lib/core/shared_foundation.dart`, or Drift `*.g.dart` files.
   - Do NOT silently alter `/shared_foundation/*.json` contracts; changes there require authorized scope, `npm run sync-foundation`, parity test verification, and same-stage doc updates.
5. **Strict Stage Boundary:** Never implement a later roadmap stage, `MAYBE_LATER.md` backlog item, or unrequested fix just because it appears in documentation. **Stop after completing the explicitly authorized stage.**
6. **Same-Stage Documentation Updates:** If an authorized stage changes architecture, schemas, shared contracts, design tokens, module boundaries, or parity behavior, update `/docs/architecture/` and `/docs/architecture/decisions/` in the same stage.
7. **Complete Change Reporting:** Report **every modified or created file** and explain why it changed.
8. **Zero Fabricated Verification:** Never claim a build, test, migration, lint, or Android device check succeeded unless you actually executed it in the current session (or verified a CI log). Clearly separate executed checks (`npm run check-ui`, `npm test`, `npm run lint`, `npm run build`) from unavailable local checks (Flutter SDK, Dart, Android Gradle build, physical Android device).

---

## 4. Non-Negotiable Domain & Platform Guardrails

- **Status Honesty:** Classify features accurately as `Implemented`, `Partially implemented`, `Planned`, `Deprecated`, or `Unverified`.
- **Offline-First & Persistence Separation:** Core features work 100% offline. Drift SQLite (`schemaVersion => 8`) is Android's authoritative store; Web Preview uses browser `localStorage`. Never silently discard, overwrite, or reset user data.
- **Finance Reality (`ADR-003`):** Enforce integer-cents arithmetic, balanced double-entry postings, immutable void/supersede chains, and safe deletion/archive guards. Remember: **Recovery Stage 2.1** is implemented and conditionally accepted; **Finance v7** is **Partially implemented** with open defects/integration gaps; **Recovery Stage 2.2 ETB currency isolation** is **incomplete and unaccepted**—never claim it is complete.
- **UI & Parity (Mandatory Procedure Before UI Edits):**
  - Read Constitution §2.4, `ADR-005`, `docs/architecture/ui-design-system.md`, and `docs/architecture/cross-platform-parity.md`.
  - Inspect both `flutter_app/lib/ui/` and `src/` to identify shared UI elements vs. permitted documented adaptations, and evaluate shared design changes across both platforms.
  - Consume canonical tokens (`DaywellTheme` / `context.daywellColors` on Flutter; `--dw-*` in `src/styles/daywellTokens.css` & `SHARED_DESIGN_TOKENS` on Web) and shared primitives (`flutter_app/lib/ui/widgets/shared_ui_widgets.dart` ↔ `src/components/ui/`)—**zero** unallowlisted Web hex literals, **zero** raw `Color(0x...)`, and **no expanding** `Colors.*` in Flutter (verified by `npm run check-ui`).
  - Preserve existing responsive layouts, accessibility improvements, and reusable primitives; mark non-live static prototype views/cards `Deprecated Prototype`; ensure any future module inherits the canonical design system automatically; keep `flutter_app/lib/` completely isolated from `src/` and `/design_assets/`.
- **Backward Compatibility (`ADR-007` & Constitution §2.11):** Preserve compatibility for all new changes across schemas, persisted models, backups/restores, snapshots/imports/exports, Shared Foundation contracts, and Flutter/Web parity. Review migration and persisted-data impacts, preserve previously released backup formats until explicitly deprecated, test previous-version data where relevant, fail safely on unsupported future versions, and document/obtain approval for intentional breaking changes (internal interface refactors require updating all affected consumers/tests together). Avoid unnecessary retroactive rewrites of untouched historical code, assessing existing defects when touched or on material data-integrity/functionality risk.
