# Daywell — Permanent Project Constitution

> **Governance Stage:** 1 (Permanent Engineering Constitution & Architecture Documentation)  
> **Scope:** Authoritative across the entire Daywell repository—including the production **Flutter Android application**, the **Google AI Studio Web Preview**, the **Shared Foundation**, persistence layers, UI/design systems, testing, and documentation.  
> **Audience:** All human engineers and all AI coding agents, regardless of IDE, model, or tooling.

---

## 1. Purpose and Authority Hierarchy

Daywell is a private, offline-first personal life management application built around Finance, Tasks, Notes, Calendar, and Inbox/Quick Capture, designed for Ethiopian civil calendar (`UTC+3`) and Ethiopian Birr (`ETB`) precision alongside dual-platform consistency.

When documents, prototypes, or platform code disagree, contributors and AI agents MUST resolve authority in the following strict top-down order:

1. **This Constitution (`PROJECT_CONSTITUTION.md`)** — Permanent, tool-agnostic engineering laws.
2. **Authoritative Architecture & UI Documentation (`/docs/architecture/*.md`)** — Verified current system truth, contracts, and parity specifications.
3. **Architectural Decision Records (`/docs/architecture/decisions/ADR-*.md`)** — Recorded, rationale-backed technical commitments.
4. **Canonical Shared Foundation Specs (`/shared_foundation/*.json`)** — Single source of truth for generated tokens, schemas, business rules, clean seed state, and calendar vectors.
5. **Visual Design Assets (`/design_assets/`)** — Approved screen references and iconography, interpreted through the UI Source-of-Truth Hierarchy (Section 2.4).
6. **Generated Foundations & Platform Implementations** — `src/domain/sharedFoundation.ts`, `flutter_app/lib/core/shared_foundation*.dart`, Flutter Android app (`flutter_app/`), and Google AI Studio Web Preview (`src/`).

Pre-constitution root audit, checklist, investigation, and roadmap Markdown files are preserved untouched as **historical records** (indexed in [Architecture Overview](./docs/architecture/overview.md)) and MUST NOT override this Constitution or `/docs/architecture/`.

### Status Classification Standard

All architecture and parity documentation under `/docs/architecture/` MUST classify system capabilities using these five explicit labels:

| Status Label | Definition |
| :--- | :--- |
| **Implemented** | Verified in current source code and functioning according to available evidence. |
| **Partially implemented** | Some parts exist, but the complete capability is not implemented or verified. |
| **Planned** | Approved or proposed for future implementation, not currently implemented. |
| **Deprecated** | Previously implemented or documented, no longer authoritative or intended for use. |
| **Unverified** | Insufficient evidence to establish current implementation or runtime correctness. |

Never present planned or partial functionality as complete or verified.

---

## 2. The Eleven Permanent Constitutional Rules

### 2.1 Architecture First
- Architecture, domain boundaries, data invariants, and UI contracts MUST be settled and documented before non-trivial implementation begins.
- No contributor or AI agent may invent ad-hoc architectures inside feature screens, helpers, or prototype components that bypass established layers.
- Every implementation stage MUST verify its alignment with [Architecture Overview](./docs/architecture/overview.md) and active ADRs before editing runtime code.

### 2.2 Modular Architecture
- **Strict Layer Separation**:
  - **Flutter Android (`flutter_app/lib/`)**: `core/` (tokens, date, platform interfaces, generated foundation) → `domain/` (pure models, engines, abstract repository contracts) → `application/` (state + controllers) → `data/` (Drift SQLite, migrations, recovery, repository implementations) & `services/` (crypto backup, export, notifications) → `ui/` (theme, shared widgets, shell, module screens).
  - **Google AI Studio Web Preview (`src/`)**: `domain/` (pure TS engines, date math, crypto, generated foundation) → `data/` & `services/` (local stores, portability, canonical bridge) → `components/` & `App.tsx`.
- **Module Isolation**: Modules (`Finance`, `Tasks`, `Notes`, `Calendar`, `Inbox`) own their domain models, controllers, and repositories. Cross-module communication MUST flow through public domain contracts, application controllers, or thin composition-root coordination—never via direct cross-module database table mutations.
- **No Unbounded Cross-Platform Leaks**: Flutter production packages (`flutter_app/lib/`) MUST never import or bundle `src/`, `design_assets/`, or Web Preview mockups.
- Detailed rules live in [Module Boundaries](./docs/architecture/module-boundaries.md).

### 2.3 Single Source of Truth — Data & Business Logic
- Shared domain constants, color/type/spacing tokens, entity schema contracts, core business formulas, clean seed data, and Ethiopian/Gregorian test vectors live canonically in `/shared_foundation/`:
  - `design_tokens.json`
  - `business_rules.json`
  - `schema_contracts.json`
  - `canonical_seed_database.json`
  - `calendar_test_vectors.json`
- Generated foundation files (`src/domain/sharedFoundation.ts`, `flutter_app/lib/core/shared_foundation_core.dart`, `flutter_app/lib/core/shared_foundation.dart`) MUST ONLY be updated via `npm run sync-foundation` (`scripts/sync_foundation.mjs`), never edited by hand.
- Parallel hand-authored domain engines (such as Calendar date math, Double-Entry / Safe Harbor Finance math, and Encrypted Backup envelope format) MUST obey the same canonical math invariants and pass cross-platform vector/parity tests.
- Detailed rules live in [Shared Foundation](./docs/architecture/shared-foundation.md).

### 2.4 Single Source of Truth — UI & Design (Flutter Android + Google AI Studio Web Preview)
Both the Flutter Android application and the Google AI Studio Web Preview represent **Daywell** and MUST share one canonical UI and design specification rather than drifting into separate products.

#### Explicit UI Source-of-Truth Hierarchy
Conflicting visual or interaction sources MUST be resolved strictly in this order:
1. **Approved Daywell product and visual design decisions** (Constitution + accepted UI ADRs, including [ADR-005](./docs/architecture/decisions/ADR-005-canonical-ui-authority-and-parity.md)).
2. **Canonical shared design tokens and design-system contracts** (`/shared_foundation/design_tokens.json` and generated Dart, TypeScript, and CSS token modules).
3. **Approved screen specifications and visual design assets/mockups** (`/design_assets/` screens and SVG icons).
4. **Shared UI component specifications and interaction contracts** (`/docs/architecture/ui-design-system.md`, `flutter_app/lib/ui/widgets/shared_ui_widgets.dart`, `src/components/ui/`, and validation/state rules).
5. **Platform-specific Flutter and Web Preview implementations** (`flutter_app/lib/ui/` and `src/`).

#### Mandatory UI Governance Rules
- **Canonical Tokens Only**: Generated design tokens MUST originate exclusively from `/shared_foundation/design_tokens.json` via `npm run sync-foundation`, producing `SharedDesignTokens` (Dart), `SHARED_DESIGN_TOKENS` (TypeScript), and `--dw-*` CSS custom properties (`src/styles/daywellTokens.css`). Flutter (`DaywellTheme`, `DaywellTypography`, `context.daywellColors`) and Web Preview (`src/index.css`, `src/App.tsx`, `src/components/`) MUST NOT independently invent competing color palettes, spacing scales, typography tokens, or semantic roles. Unallowlisted hardcoded hex literals (`#RGB`/`#RRGGBB`) in Web UI and raw `Color(0x...)` or unallowlisted `Colors.*` literals in Flutter UI are forbidden and enforced by `npm run check-ui`.
- **Shared UI Primitives & Patterns**: Equivalent cross-platform UI building blocks (`DaywellButton`, `DaywellIconButton`, `DaywellCard`, `DaywellSectionHeader`, `DaywellEmptyState`, `DaywellStatusBadge`, `DaywellStatusBanner`, `DaywellLoadingIndicator`, `DaywellProgressBar`, `DaywellTextField`, `DaywellSearchField`, `DaywellSelectField` / `DaywellDropdownField`, `DaywellSectionContainer`, `DaywellContentState`, `DaywellConfirmationDialog`) MUST be maintained symmetrically in `flutter_app/lib/ui/widgets/shared_ui_widgets.dart` and `src/components/ui/index.ts`. Existing reusable components MUST NOT be bypassed or deleted to simplify one screen.
- **Deprecated Mockup Discipline**: Non-live static mockup screens or sample cards retained for preview visibility MUST be explicitly marked as `Deprecated Prototype` (`DeprecatedPrototypeBanner` / `DaywellStatusBadge`) so they are never mistaken for live canonical product features, and MUST still render using canonical `--dw-*` design tokens.
- **Conflict Transparency**: If an approved mockup conflicts with a canonical design token, or a screen spec conflicts with an existing shared component contract, contributors MUST NOT silently pick one; document the conflict explicitly and preserve the established canonical contract until an approved design decision resolves it.
- **Permitted Platform Adaptations**: Platform-specific differences are permitted when justified by native usability, accessibility, responsive layout, or technical runtime constraints (for example: Material 3 bottom bar / tablet navigation rail on Flutter vs. responsive Web Preview layout and file input/download mechanics, or omitted bundled fonts on Android for compact APK size). Intentional platform adaptations MUST be documented in [Cross-Platform Parity](./docs/architecture/cross-platform-parity.md).
- **Coordinated Change Evaluation & Future Module Inheritance**: Every relevant UI change or newly introduced module MUST be evaluated against both Flutter Android and Web Preview, preserve prior responsive/accessibility improvements, inherit `design_tokens.json` + shared primitives automatically, and update `/docs/architecture/ui-design-system.md` and `/docs/architecture/cross-platform-parity.md` in the same stage. We do NOT require identical source code or rigid pixel cloning across platforms, but we DO require equivalent product identity, visual language, information hierarchy, terminology, interaction meaning, validation semantics, and core workflow behavior.

### 2.5 Offline-First Architecture
- Daywell MUST operate 100% offline for all core workflows across Finance, Tasks, Notes, Calendar, and Inbox.
- **Zero Mandatory Cloud Dependency**: No cloud database, login wall, telemetry beacon, analytics tracker, or remote API call may be required for core app startup, data persistence, search, or reporting.
- **Sovereign Local Persistence**:
  - Flutter Android uses on-device Drift SQLite (`personal_management.sqlite`) plus local atomic recovery/quarantine and passphrase-encrypted `.daywell` export/restore.
  - Web Preview uses browser `localStorage` (`daywell_canonical_database_v3` and module stores) plus canonical JSON exchange (`SharedStateBridge`).
- Any future optional sync/export transport MUST preserve offline-first primacy and explicit user initiation.

### 2.6 Data Integrity
- **Integer-Cents Money**: All monetary amounts MUST be stored and computed strictly as signed/unsigned integer minor units (`cents`, where `1 ETB = 100 cents`). Floating-point money storage or ledger arithmetic is forbidden.
- **Double-Entry Balanced Ledger**: Every posted `JournalEntry` MUST satisfy $\sum \text{Debits} == \sum \text{Credits}$ in minor units (`DoubleEntryEngine` invariants). Unbalanced entries MUST be rejected.
- **ETB First-Release Currency Isolation**: `ETB` is the primary first-release reporting currency, governed by Stage 2.2 strict currency isolation (`verified_etb` vs. `verified_non_etb` vs. `unverified`; non-ETB accounts/entries MUST NOT contaminate ETB Safe Harbor, Net Worth, P&L, or debt totals).
- **Immutable Audit Trail**: Financial records MUST NOT be silently overwritten or hard-deleted to erase history; corrections use explicit `isVoided` / `isSuperseded` / replacement chains (`correctedFromEntryId`, `voidReason`). Account opening-balance revisions MUST NEVER synthesize fake salary/income transactions.
- **Safe Deletion Guards**: Accounts and categories referenced by non-superseded history MUST be blocked from destructive deletion and guided to archive instead.
- **Civil Calendar Integrity**: Calendar date-only fields MUST store canonical `YYYY-MM-DD` strings under `Africa/Addis_Ababa` (`UTC+3`, no DST). Instant timestamps MUST use explicit UTC ISO-8601. Ethiopian calendar math MUST preserve 13 months with Pagume 5/6 leap year accuracy (`year % 4 == 3`).
- **Clean Startup & Legacy Purge**: Fresh installs initialize empty user collections (retaining legitimate default categories). Known historical demo seed IDs (`KnownSeedIds` / `KNOWN_SEED_IDS`) are purged safely without harming user records.
- **Fail-Closed Migrations & Recovery**: Database upgrades and canonical imports MUST execute atomically inside transactions with pre-flight invariant validation and raw backup/quarantine recovery paths.

### 2.7 Implementation Stages
- All work proceeds in **small, dependency-ordered, single-purpose implementation stages**.
- Each stage has an explicit scope, dependency prerequisites, target modules, and verifiable completion criteria.
- **No Premature Implementation**: Contributors and AI agents MUST NOT implement future stages, unrequested modules, or unapproved features ahead of authorization (for example, do not build Governance Stage 2 agent prompts or Stage 3 CI scripts during Stage 1; do not implement `MAYBE_LATER.md` backlog items unless explicitly scheduled).
- **No Overloaded Stages**: Never bundle unrelated architecture changes, UI redesigns, and multi-module feature rewrites into one opaque batch.

### 2.8 Testing & Verification
- Every change MUST be verified proportionate to its blast radius using concrete, actually executed checks.
- **No Fabricated Verification**: Never claim tests, builds, linters, or on-device behaviors passed unless they were executed in the current environment or verified CI run. Explicitly distinguish:
  - Verified TypeScript / Web Preview checks (`npm test`, `tsc --noEmit`, Vite build, `sync-foundation` parity).
  - Verified CI Flutter checks (`flutter pub get`, `build_runner`, `dart format`, `flutter analyze`, `flutter test`, APK build & signature verification).
  - **Unverified** runtime behaviors when Flutter SDK, emulator, or physical Android hardware is unavailable in the local container.
- Detailed commands, test inventories, and gates live in [Testing Standards](./docs/architecture/testing-standards.md).

### 2.9 Documentation
- Architecture, UI contracts, parity status, and ADRs MUST reflect the **actual codebase**, not wishful memory.
- **Documentation Maintenance Rule**: Whenever a future implementation changes an authoritative architectural contract, design token, database schema, module boundary, cross-platform behavior, or approved technical decision, the corresponding documentation under `/docs/architecture/` and `/docs/architecture/decisions/` MUST be updated **within the same implementation stage**.
  - Design token changes → update [UI Design System](./docs/architecture/ui-design-system.md).
  - Database schema or persistence changes → update [Data and Persistence](./docs/architecture/data-and-persistence.md).
  - Module boundary or interface changes → update [Module Boundaries](./docs/architecture/module-boundaries.md).
  - Cross-platform feature/workflow changes → update [Cross-Platform Parity](./docs/architecture/cross-platform-parity.md).
  - Approved architectural choices → create or update an ADR in `/docs/architecture/decisions/`.
- Trivial bug fixes or internal refactors that preserve all contracts and behaviors do NOT require documentation churn.
- Pre-existing historical root Markdown files MUST remain untouched and clearly indexed as historical/superseded in [Architecture Overview](./docs/architecture/overview.md).

### 2.10 Scope Control
- Implement strictly what the authorized stage requests—nothing more, nothing hidden.
- Do not introduce drive-by rewrites of working unrelated modules, new third-party dependencies, telemetry, or speculative abstractions without explicit approval.
- Long-term ideas, rejected concepts, and deferred enhancements belong in `MAYBE_LATER.md`, not uninvited inside feature PRs.

### 2.11 Backward Compatibility — Mandatory Going Forward
- **Explicit Policy ([ADR-007](./docs/architecture/decisions/ADR-007-mandatory-backward-compatibility.md))**: Backward compatibility is **mandatory** for all new development and modifications from the Governance Amendment adopting ADR-007 onward across database schemas, persisted models, backups, restores, snapshots, imports/exports, Shared Foundation contracts, internal interfaces, and Flutter/Web interoperability.
- **Preservation & Fail-Closed Rules**:
  - Previously released Drift SQLite migration paths (`AppDatabase.onUpgrade`) and non-destructive upgrade safety MUST remain available so existing installations can upgrade without silent data loss.
  - Previously released backup formats (such as `.daywell` `format_version: 1`) MUST remain supported until an explicit, approved deprecation decision retires them; documented previously released snapshot/import formats MUST be handled via deterministic upcasters.
  - Unsupported future versions MUST fail safely (fail-closed) without destructive fallback or silent truncation; no arbitrary rolling version limit is imposed.
  - Shared Foundation changes MUST preserve existing consumers or provide coordinated migrations and parity tests; breaking internal interface changes are permitted only when all affected in-repository consumers, implementations, and tests are updated together with appropriate verification.
  - Any intentional breaking change to persisted contracts or interoperability requires documented justification, migration strategy, testing, and explicit approval.
- **No Blanket Retroactive Rewrite**: Existing pre-decision code does not require a blanket rewrite; however, pre-existing compatibility defects MUST be assessed whenever the affected area is modified or when they pose a material data-integrity or functionality risk.

---

## 3. Hierarchy, Conflicts, and Amendments

### Conflict Resolution Procedure
1. Check whether an explicit user directive for the active authorized stage narrows scope.
2. Consult `PROJECT_CONSTITUTION.md` (this file).
3. Consult the matching topic guide in `/docs/architecture/` and active `Accepted` ADRs in `/docs/architecture/decisions/`.
4. Inspect live code and `/shared_foundation/*.json` directly.
5. If code or a legacy root doc contradicts `/docs/architecture/` or `/shared_foundation/`, do NOT silently follow the stale artifact—either follow the Constitution/authoritative contract or document the discrepancy (`Partially implemented` / `Unverified` / `Proposed` ADR) and surface it cleanly.

### Amendment Process
Permanent changes to Sections 2.1–2.11 or Section 3 of this Constitution require:
1. A dedicated **Architectural Decision Record (ADR)** in `/docs/architecture/decisions/` explaining Context, Decision, Alternatives, and Consequences.
2. Explicit user approval of that ADR.
3. Synchronous updates in the same stage to `PROJECT_CONSTITUTION.md` and every affected `/docs/architecture/*.md` guide.

### Future Extensibility Rule
When new modules (e.g., standalone Projects, Goals, Relationships, Habits) are introduced:
- They inherit every rule in Section 2 automatically without needing to modify Section 2.
- They add module contracts inside [Module Boundaries](./docs/architecture/module-boundaries.md), entities inside `/shared_foundation/schema_contracts.json` and [Data and Persistence](./docs/architecture/data-and-persistence.md), UI specs inside [UI Design System](./docs/architecture/ui-design-system.md), and rows inside [Cross-Platform Parity](./docs/architecture/cross-platform-parity.md).
