# ADR-003: Finance v7 Double-Entry Ledger, Integer Cents & Stage 2.2 ETB Isolation

- **Status:** `accepted` *(Architectural Decision Only — see Implementation Status below)*
- **Date / Version:** Governance Stage 1 (`schemaVersion => 7`, Finance v7 / Stage 2.2 architectural specification)
- **Affected Docs:** [PROJECT_CONSTITUTION.md](../../../PROJECT_CONSTITUTION.md), [Architecture Overview](../overview.md), [Data and Persistence](../data-and-persistence.md), [Module Boundaries](../module-boundaries.md), [Cross-Platform Parity](../cross-platform-parity.md)

### Important Distinction: Decision Status vs. Implementation Status
- **Architectural Decision (`accepted`):** The rules below (integer minor units, balanced double-entry accounting, immutable correction chains, archive guards, and Stage 2.2 strict ETB first-release currency isolation) are permanent approved architectural requirements.
- **Current Implementation Reality (Governance Stage 1.1 Audit):**
  - **Recovery Stage 2.1:** **Implemented** and conditionally accepted.
  - **Existing Finance v7 Architecture:** **Partially implemented**, with identified defects and incomplete cross-platform integration.
  - **Recovery Stage 2.2 ETB Currency Isolation:** Strict ETB-only write enforcement, integer-only decimal cent parsing, Quick Capture FX token rejection, unvoid/`restoreTransaction` legacy/non-ETB gating, `SharedFoundationBridge.auditConsistency` ETB asset scoping, analytical export `EXCLUDED_<CODE>` / `CURRENCY_REVIEW` / `savings_vault` Cash Flow isolation, and snapshot `currencyCode` validation (`v7+` fail-closed; `<7` unverified non-coercion) have been **Implemented** on Web TypeScript (verified via Node tests) and **Implemented** in Flutter Dart source (**Unverified** locally pending CI `flutter analyze` / `flutter test` execution and acceptance).

---

## Context

Earlier single-entry transaction records and floating-point amounts introduced rounding drift, silent overwrites of opening balances (which could fabricate fake income), destructive deletion of categories/accounts that broke historical reports, and contamination of primary **Ethiopian Birr (`ETB`)** liquidity metrics when non-ETB or unverified currency records were present.

---

## Decision

1. **Strict Integer-Cents Representation:** All balances, budgets, debts, goals, and journal lines MUST be stored and calculated strictly in signed/unsigned integer minor units (`cents`, where `1 ETB = 100 cents`). Floating-point monetary storage is prohibited.
2. **Balanced Double-Entry Accounting (`v6` / `v7`):** Every financial posting generates a `JournalEntry` backed by `JournalLines` inside `DoubleEntryEngine`, constrained by $\sum \text{Debits} == \sum \text{Credits}$ and anchored to immutable system control accounts (`SYS_CTRL_OPENING_EQUITY`, `SYS_CTRL_INCOME`, `SYS_CTRL_EXPENSE`).
3. **Immutable Correction Chains & Deletion Guards:** Posted financial entries are corrected via void/supersede replacement chains (`isVoided`, `isSuperseded`, `correctedFromEntryId`, `voidReason`)—never silent deletion or fake income entries during opening-balance adjustments. Referenced accounts and categories cannot be hard-deleted and must be archived instead.
4. **Stage 2.2 ETB First-Release Currency Isolation (Approved Requirement — Implemented in Code; Android CI Pending):** First-release Safe Harbor, Net Worth, Debt totals, and P&L aggregations MUST restrict calculations strictly to `verified_etb` records (`currencyCode == 'ETB'` explicit verified rows). Non-ETB (`verified_non_etb`) and `unverified` entries MUST be explicitly flagged/isolated in UI banners and analytics so they never corrupt ETB totals.

---

## Alternatives Considered

1. **Simple Single-Entry Expense Table + Dynamic Sums:** Rejected because transfers, debt tracking, opening equity adjustments, and audit-safe void/replace corrections become fragile and error-prone.
2. **Automatic Static FX Conversion in First Release:** Rejected because offline users lack trustworthy live FX rates, and mixing converted estimates into Safe Harbor undermines cashflow accuracy.

---

## Consequences & Trade-Offs

- **Intended Positive Outcomes:** Eliminates floating-point rounding drift, enforces audit-safe edit history, and establishes verifiable accounting integrity and trustworthy ETB Safe Harbor figures once Finance v7 integration defects are closed and Stage 2.2 Flutter/Android checks pass CI.
- **Negative / Trade-Offs:** Schema migrations (`v5 → v6 → v7`) and canonical JSON validation (`RawDatabaseRecoveryExporter`, `SharedStateBridge`) are noticeably more complex, and cross-platform parity & CI runtime verification remain tracked under [ADR-006](./ADR-006-unresolved-cross-platform-parity-and-sync.md).
