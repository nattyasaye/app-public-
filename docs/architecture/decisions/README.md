# Daywell — Architectural Decision Records (ADRs)

This directory holds Daywell's permanent record of significant architectural, data, persistence, and UI/design decisions.

---

## ADR Governance Rules

1. **Immutability & Supersession:** Accepted ADRs are never silently overwritten to erase history. When a decision changes, add a new ADR (`ADR-NNN-...`) and update the prior ADR's status to `superseded` with a link to its replacement.
2. **Accurate Status Discipline:**
   - Record **only** genuinely approved and established technical/product commitments as `accepted`.
   - Record unresolved cross-platform gaps, speculative sync choices, or unapproved architectural shifts as `proposed`.
3. **Mandatory Same-Stage Updates:** Any future stage introducing or altering an architectural commitment MUST create or update the relevant ADR alongside the affected `/docs/architecture/*.md` document in the same stage.

---

## ADR Index

| ID | Title | Status | Date / Stage | Scope |
| :--- | :--- | :---: | :--- | :--- |
| [ADR-001](./ADR-001-offline-first-dual-persistence.md) | Offline-First Architecture with Dual Local Persistence (Drift SQLite + Browser `localStorage`) | **accepted** | Governance Stage 1 | Core Architecture, Data, Privacy |
| [ADR-002](./ADR-002-shared-foundation-single-source-of-truth.md) | Canonical Shared Foundation & Deterministic Generation Pipeline | **accepted** | Governance Stage 1 | Tokens, Schemas, Rules, Vectors |
| [ADR-003](./ADR-003-finance-v7-double-entry-and-etb-isolation.md) | Finance v7 Double-Entry Ledger, Integer Cents & Stage 2.2 ETB Isolation | **accepted** | Governance Stage 1 | Finance Domain, Migrations |
| [ADR-004](./ADR-004-backward-compatibility-deferred.md) | Pre-Release Backward Compatibility Deferral Policy *(Superseded by [ADR-007](./ADR-007-mandatory-backward-compatibility.md))* | **superseded** | Governance Stage 1 | Constitution, Schemas, Prototypes |
| [ADR-005](./ADR-005-canonical-ui-authority-and-parity.md) | Canonical 5-Level UI Source-of-Truth Hierarchy & Equivalent Cross-Platform Parity | **accepted** | Governance Stage 1 | Flutter UI, Web Preview, Assets |
| [ADR-006](./ADR-006-unresolved-cross-platform-parity-and-sync.md) | Unresolved Cross-Platform Parity Gaps, Backup Alignment, Calendar UI & R8 Shrinking | **proposed** | Governance Stage 1 | Pending Future Stages |
| [ADR-007](./ADR-007-mandatory-backward-compatibility.md) | Mandatory Forward-Going Backward Compatibility Policy *(Supersedes [ADR-004](./ADR-004-backward-compatibility-deferred.md))* | **accepted** | Governance Amendment (2026-11-15) | Schemas, Backups, Snapshots, Contracts |
| [ADR-008](./ADR-008-retire-account-isactive-and-schema-v8.md) | Retire `Account.isActive` in Favor of `isArchived` and Advance Schema to Version 8 | **accepted** | Governance Stage 3.4.4.1 (2026-11-16) | Schemas, Accounts, Reminders, Migrations |
| [ADR-009](./ADR-009-projects-stage1-tracking-foundation-and-schema-v9.md) | Projects Stage 1 Composable Tracking Foundation and Schema v9 | **accepted** | Projects Stage 1 (2026-11-17) | Projects, Schemas, Persistence, Parity |

---

## Standard ADR Template

Every new ADR added to this directory MUST include these sections:

- **Title:** `# ADR-NNN: Short Decision Title`
- **Metadata Block:**
  - `Status:` `proposed` | `accepted` | `superseded` | `deprecated`
  - `Date / Version:` ISO date or milestone reference (`schemaVersion`, stage)
  - `Affected Docs:` Links to impacted `/docs/architecture/*.md` files & `PROJECT_CONSTITUTION.md`
- **Context:** The forces, constraints, and verified problem statement.
- **Decision:** Concrete architectural rule or unresolved proposal.
- **Alternatives Considered:** Viable options evaluated and why they were rejected or deferred.
- **Consequences & Trade-Offs:** Positive outcomes, maintenance costs, risks, and follow-up obligations.
